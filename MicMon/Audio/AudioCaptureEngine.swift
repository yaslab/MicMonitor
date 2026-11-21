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
/// モニター再生が有効なときは、入力をシステム既定の出力にも流す。
@MainActor
final class AudioCaptureEngine {
    /// モニター再生に対応する最大の入力チャンネル数。
    static let maxMonitorChannels = 2

    private let levels: LevelStore
    private let waveform: WaveformHistory
    private var engine: AVAudioEngine?
    private var monitorMixer: AVAudioMixerNode?
    private var configurationObserver: (any NSObjectProtocol)?
    private var format: CaptureFormat?

    /// `AVAudioEngineConfigurationChange` を受けたときに呼ばれる。
    var onConfigurationChange: (() -> Void)?

    var monitorVolume: Float = 0.5 {
        didSet { monitorMixer?.outputVolume = monitorVolume }
    }

    init(levels: LevelStore, waveform: WaveformHistory) {
        self.levels = levels
        self.waveform = waveform
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

        levels.configure(channelCount: channels)
        waveform.configure(channelCount: channels, sampleRate: format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 1024, format: format,
                         block: Self.makeTapBlock(levels: levels, waveform: waveform))

        var mixer: AVAudioMixerNode?
        if monitoring, channels <= Self.maxMonitorChannels {
            let node = AVAudioMixerNode()
            engine.attach(node)
            engine.connect(input, to: node, format: format)
            engine.connect(node, to: engine.mainMixerNode, format: nil)
            node.outputVolume = monitorVolume
            mixer = node
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }

        self.engine = engine
        self.monitorMixer = mixer
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
        let captureFormat = CaptureFormat(sampleRate: format.sampleRate, channelCount: channels)
        self.format = captureFormat
        return captureFormat
    }

    /// 起動直後にも通知が届くことがあるため、実際に止まったかフォーマットが変わったときだけ再構成を求める。
    private func handleConfigurationChange() {
        guard let engine else { return }
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let current = CaptureFormat(sampleRate: inputFormat.sampleRate, channelCount: Int(inputFormat.channelCount))
        let needsRestart = !engine.isRunning || current != format
        MonitorModel.logger.debug("Configuration change: running \(engine.isRunning), format \(current.sampleRate) Hz \(current.channelCount) ch, restart: \(needsRestart)")
        if needsRestart { onConfigurationChange?() }
    }

    func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        monitorMixer = nil
        format = nil
    }

    /// タップのクロージャは nonisolated な文脈で作る。
    /// MainActor の文脈で作ると、Swift 6 の実行時の分離チェックでタップのスレッドから呼ばれた際にクラッシュする。
    nonisolated private static func makeTapBlock(levels: LevelStore, waveform: WaveformHistory) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let data = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            levels.process(data, channelCount: channels, frameCount: frames)
            waveform.process(data, channelCount: channels, frameCount: frames)
        }
    }
}
