import AVFoundation
import CoreAudio
import os

struct CaptureFormat: Equatable, Sendable {
    let sampleRate: Double
    let channelCount: Int
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
    private var pump: AudioPump?
    private var configurationObservers: [any NSObjectProtocol] = []
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
        try input.auAudioUnit.setDeviceID(deviceID)

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

        levels.configure(channelCount: channels)
        waveform.configure(channelCount: channels, sampleRate: format.sampleRate)
        spectrum.configure(channelCount: channels, sampleRate: format.sampleRate)

        // リアルタイムスレッド（シンクノード）→ リングバッファ → ポンプ（専用キュー）→ 集計・再生
        let ring = SampleRingBuffer(channelCount: channels, capacity: Int(format.sampleRate * Self.ringSeconds))
        guard let pump = AudioPump(format: format, ring: ring, levels: levels,
                                   waveform: waveform, spectrum: spectrum, playback: playback)
        else {
            playback?.stop()
            throw CaptureError.unsupportedFormat
        }
        let sink = AVAudioSinkNode(receiverBlock: Self.makeReceiverBlock(ring: ring))
        engine.attach(sink)
        engine.connect(input, to: sink, format: format)

        engine.prepare()
        pump.start()
        do {
            try engine.start()
        } catch {
            pump.stop()
            playback?.stop()
            throw error
        }

        self.engine = engine
        self.playback = playback
        self.ring = ring
        self.pump = pump
        observeConfigurationChanges(of: engine)
        if let playback { observeConfigurationChanges(of: playback.engine) }

        let captureFormat = CaptureFormat(sampleRate: format.sampleRate, channelCount: channels)
        self.format = captureFormat
        return captureFormat
    }

    func stop() {
        configurationObservers.forEach(NotificationCenter.default.removeObserver)
        configurationObservers = []
        // 入力 → ポンプの順に止めて再生への予約を止めてから、再生を止めて解放する（解放は MainActor で行う）
        engine?.stop()
        engine = nil
        pump?.stop()
        pump = nil
        ring = nil
        format = nil
        playback?.stop()
        playback = nil
        monitorError = nil
    }

    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
        configurationObservers.append(observer)
    }

    /// 起動直後にも通知が届くことがあるため、実際に止まったか入力フォーマットが変わったときだけ再構成を求める。
    /// 出力側（モニター再生）は、出力デバイスの変更などでエンジンが止まったときに再構成する。
    private func handleConfigurationChange() {
        guard let engine else { return }
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let current = CaptureFormat(sampleRate: inputFormat.sampleRate, channelCount: Int(inputFormat.channelCount))
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
    /// 再生（`MonitorPlayback`）はここでは持たず、ポンプが弱参照で持つ（解放がメインスレッド以外で起きるとクラッシュするため）。
    nonisolated private static func makeReceiverBlock(ring: SampleRingBuffer) -> AVAudioSinkNodeReceiverBlock {
        { _, frameCount, bufferList in
            ring.write(bufferList, frameCount: Int(frameCount))
            return noErr
        }
    }
}
