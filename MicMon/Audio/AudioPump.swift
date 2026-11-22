import AVFoundation

/// `SampleRingBuffer` を一定間隔で読み出し、レベル・波形・スペクトル・モニター再生に渡す。
///
/// リアルタイムスレッドではサンプルのコピーだけを行い、Mutex を使う集計や再生の予約は
/// `start()` が返すタスクで行う。間隔ぶん（最大 5 ms 程度）の遅れが加わる。
struct AudioPump: Sendable {
    static let interval: Duration = .milliseconds(5)
    /// 1 回の読み出しの最大フレーム数。
    private static let chunkFrames: AVAudioFrameCount = 4096

    let format: AVAudioFormat
    let ring: SampleRingBuffer
    let levels: LevelStore
    let waveform: WaveformHistory
    let spectrum: SpectrumAnalyzer
    /// 所有は `AudioCaptureEngine`。タスクが最後の参照を持っていても、解放は `MonitorPlayback` の
    /// isolated deinit により MainActor で行われる。
    let playback: MonitorPlayback?

    /// ポンプのタスクを始める。キャンセルすると止まる。作業用のバッファを作れなければ nil。
    func start() -> Task<Void, Never>? {
        guard let scratch = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.chunkFrames) else { return nil }
        // MainActor から切り離して実行する（作業用のバッファはこのタスクだけが使う）
        return Task.detached(priority: .high) {
            await run(scratch: scratch)
        }
    }

    /// 前回の予定時刻から `interval` ごとに起きる（処理時間で周期がずれていかないように）。
    /// 処理が遅れて予定時刻を過ぎたときは、まとめて追いつこうとせず今から数え直す。
    private func run(scratch: AVAudioPCMBuffer) async {
        let clock = ContinuousClock()
        var deadline = clock.now
        while !Task.isCancelled {
            drain(into: scratch)
            deadline = max(deadline + Self.interval, clock.now)
            do {
                try await Task.sleep(until: deadline, tolerance: .milliseconds(1), clock: clock)
            } catch {
                return
            }
        }
    }

    /// たまっている分をすべて処理する。
    private func drain(into scratch: AVAudioPCMBuffer) {
        while true {
            let frames = ring.read(into: scratch)
            guard frames > 0, let data = scratch.floatChannelData else { return }
            let channels = Int(scratch.format.channelCount)
            #if DEBUG
            TimingProbe.tap.record(frames)
            #endif
            levels.process(data, channelCount: channels, frameCount: frames)
            waveform.process(data, channelCount: channels, frameCount: frames)
            spectrum.process(data, channelCount: channels, frameCount: frames)
            playback?.enqueue(scratch)
            if frames < Int(Self.chunkFrames) { return }
        }
    }
}
