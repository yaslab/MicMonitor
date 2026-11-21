import AVFoundation

/// `SampleRingBuffer` を一定間隔で読み出し、レベル・波形・モニター再生に渡す。
///
/// リアルタイムスレッドではサンプルのコピーだけを行い、Mutex を使う集計や再生の予約は
/// このポンプの専用キューで行う。間隔ぶん（最大 5 ms 程度）の遅れが加わる。
final class AudioPump: @unchecked Sendable {
    static let interval: DispatchTimeInterval = .milliseconds(5)
    /// 1 回の読み出しの最大フレーム数。
    private static let chunkFrames: AVAudioFrameCount = 4096

    private let ring: SampleRingBuffer
    private let levels: LevelStore
    private let waveform: WaveformHistory
    /// 所有は `AudioCaptureEngine`（MainActor）。解放がこのキューで起きないよう弱参照で持つ。
    private weak var playback: MonitorPlayback?
    private let scratch: AVAudioPCMBuffer
    private let queue = DispatchQueue(label: "MicMon.AudioPump", qos: .userInteractive)
    /// MainActor からのみ触る。
    private var timer: DispatchSourceTimer?

    init?(format: AVAudioFormat, ring: SampleRingBuffer, levels: LevelStore,
          waveform: WaveformHistory, playback: MonitorPlayback?) {
        guard let scratch = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.chunkFrames) else { return nil }
        self.ring = ring
        self.levels = levels
        self.waveform = waveform
        self.playback = playback
        self.scratch = scratch
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.drain() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// たまっている分をすべて処理する（ポンプのキューで実行）。
    private func drain() {
        while true {
            let frames = ring.read(into: scratch)
            guard frames > 0, let data = scratch.floatChannelData else { return }
            let channels = Int(scratch.format.channelCount)
            #if DEBUG
            TimingProbe.tap.record(frames)
            #endif
            levels.process(data, channelCount: channels, frameCount: frames)
            waveform.process(data, channelCount: channels, frameCount: frames)
            playback?.enqueue(scratch)
            if frames < Int(Self.chunkFrames) { return }
        }
    }
}
