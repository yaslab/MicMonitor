import AVFoundation
import CoreAudio
import os

struct CaptureFormat: Equatable, Sendable {
    let sampleRate: Double
    let channelCount: Int
}

extension CaptureFormat {
    init(_ format: AVAudioFormat) {
        self.init(sampleRate: format.sampleRate, channelCount: Int(format.channelCount))
    }
}

enum CaptureError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "このデバイスの入力フォーマットには対応していません。"
        }
    }
}

/// AVAudioEngine で指定デバイスから入力を取り、レベルと波形のストアに流す。
/// モニター再生が有効なときは、別のエンジン（`MonitorPlayback`）でシステム既定の出力にも流す。
@MainActor
final class AudioCaptureEngine {
    /// モニター再生に対応する最大の入力チャンネル数。
    static let maxMonitorChannels = 2
    /// リアルタイムスレッドとポンプの間のリングバッファの長さ（秒）。
    private static let ringSeconds = 1.0

    private let levels: LevelStore
    private let waveform: WaveformHistory
    private let spectrum: SpectrumAnalyzer
    private var engine: AVAudioEngine?
    private var playback: MonitorPlayback?
    private var ring: SampleRingBuffer?
    private var pumpTask: Task<Void, Never>?
    private var configurationTasks: [Task<Void, Never>] = []
    private var format: CaptureFormat?

    /// `AVAudioEngineConfigurationChange` で再構成が必要になったときに呼ばれる。
    var onConfigurationChange: (() -> Void)?

    /// モニター再生を開始できなかったときの理由。計測は続ける。
    private(set) var monitorError: String?

    var monitorVolume: Float = 0.5 {
        didSet { playback?.volume = monitorVolume }
    }

    init(levels: LevelStore, waveform: WaveformHistory, spectrum: SpectrumAnalyzer) {
        self.levels = levels
        self.waveform = waveform
        self.spectrum = spectrum
    }

    @discardableResult
    func start(deviceID: AudioDeviceID, monitoring: Bool) throws -> CaptureFormat {
        stop()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        try input.withAUAudioUnit { unit in try unit.setDeviceID(deviceID) }

        let format = input.outputFormat(forBus: 0)
        let channels = Int(format.channelCount)
        guard channels > 0, format.sampleRate > 0,
              format.commonFormat == .pcmFormatFloat32, !format.isInterleaved
        else { throw CaptureError.unsupportedFormat }

        // 再生に失敗しても計測は止めない
        var playback: MonitorPlayback?
        if monitoring, channels <= Self.maxMonitorChannels {
            do {
                playback = try MonitorPlayback(format: format, volume: monitorVolume)
            } catch {
                monitorError = "モニター再生を開始できませんでした: \(error.localizedDescription)"
                MonitorModel.logger.error("Failed to start monitor playback: \(error.localizedDescription, privacy: .public)")
            }
        }
        // ここから先で失敗したら、始めた再生とポンプを止める
        var pumpTask: Task<Void, Never>?
        var started = false
        defer {
            if !started {
                pumpTask?.cancel()
                playback?.stop()
            }
        }

        levels.configure(channelCount: channels)
        waveform.configure(channelCount: channels, sampleRate: format.sampleRate)
        spectrum.configure(channelCount: channels, sampleRate: format.sampleRate)

        // リアルタイムスレッド（シンクノード）→ リングバッファ → ポンプ（タスク）→ 集計・再生
        let ring = SampleRingBuffer(channelCount: channels, capacity: Int(format.sampleRate * Self.ringSeconds))
        let pump = AudioPump(format: format, ring: ring, levels: levels,
                             waveform: waveform, spectrum: spectrum, playback: playback)
        let sink = AVAudioSinkNode(receiverBlock: Self.makeReceiverBlock(ring: ring))
        engine.attach(sink)
        try engine.connectNode(input, to: sink, format: format)

        engine.prepare()
        pumpTask = pump.start()
        guard pumpTask != nil else { throw CaptureError.unsupportedFormat }
        try engine.start()
        started = true

        self.engine = engine
        self.playback = playback
        self.ring = ring
        self.pumpTask = pumpTask
        observeConfigurationChanges(of: engine)
        if let playback { observeConfigurationChanges(of: playback.engine) }

        let captureFormat = CaptureFormat(format)
        self.format = captureFormat
        return captureFormat
    }

    func stop() {
        configurationTasks.forEach { $0.cancel() }
        configurationTasks = []
        // 入力 → ポンプの順に止めてから再生を止める。ポンプのタスクは次の周期（最大 5 ms 後）に終わるまで
        // 再生への参照を持ち続けるが、`MonitorPlayback` の解放は isolated deinit により MainActor で行われる
        engine?.stop()
        engine = nil
        pumpTask?.cancel()
        pumpTask = nil
        ring = nil
        format = nil
        playback?.stop()
        playback = nil
        monitorError = nil
    }

    /// `stop()` でタスクをキャンセルすると監視も終わる（まだ処理していない通知は捨てる）。
    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        let changes = NotificationCenter.default.notifications(named: .AVAudioEngineConfigurationChange, object: engine)
        configurationTasks.append(Task { [weak self] in
            for await _ in changes {
                self?.handleConfigurationChange()
            }
        })
    }

    /// 起動直後にも通知が届くことがあるため、実際に止まったか入力フォーマットが変わったときだけ再構成を求める。
    /// 出力側（モニター再生）は、出力デバイスの変更などでエンジンが止まったときに再構成する。
    private func handleConfigurationChange() {
        guard let engine else { return }
        let current = CaptureFormat(engine.inputNode.outputFormat(forBus: 0))
        let playbackStopped = playback.map { !$0.isRunning } ?? false
        let needsRestart = !engine.isRunning || current != format || playbackStopped
        MonitorModel.logger.debug("Configuration change: running \(engine.isRunning), format \(current.sampleRate) Hz \(current.channelCount) ch, playback stopped \(playbackStopped), restart: \(needsRestart)")
        if needsRestart { onConfigurationChange?() }
    }

    #if DEBUG
    /// 計測用: シンクノードの呼び出し回数と、リングバッファがあふれて捨てたフレーム数。
    var sinkStatistics: (calls: Int, droppedFrames: Int)? {
        ring.map { ($0.writeCallCount, $0.droppedFrames) }
    }
    #endif

    /// シンクノードのクロージャはリアルタイムスレッドで呼ばれる。リングバッファへのコピーだけを行う。
    ///
    /// nonisolated な文脈で作る。MainActor の文脈で作ると、Swift 6 の実行時の分離チェックで
    /// リアルタイムスレッドから呼ばれた際にクラッシュする。
    /// 再生（`MonitorPlayback`）はここでは持たず、ポンプのタスクに渡す。
    nonisolated private static func makeReceiverBlock(ring: SampleRingBuffer) -> AVAudioSinkNodeReceiverBlock {
        { _, frameCount, bufferList in
            ring.write(bufferList, frameCount: Int(frameCount))
            return noErr
        }
    }
}
