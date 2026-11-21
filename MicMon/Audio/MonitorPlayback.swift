import AVFoundation
import Synchronization

/// 入力を、キャプチャ用とは別の AVAudioEngine でシステム既定の出力デバイスに再生する。
///
/// macOS の AVAudioEngine は inputNode と outputNode で 1 つの I/O ユニットを共有する。
/// 入力デバイスを指定したエンジンの出力はそのデバイス（入力専用なら 0 ch）になってしまい、
/// 別デバイスの出力には再生できない。そのため再生は出力専用のエンジンで行い、
/// タップで受け取ったバッファをコピーして `AVAudioPlayerNode` に渡す。
///
/// `enqueue` はタップのスレッドから、それ以外は MainActor から呼ぶ。
/// `AVAudioPlayerNode.scheduleBuffer` はスレッドセーフ。
final class MonitorPlayback: @unchecked Sendable {
    /// 再生待ちがこれを超えたら入力を捨てる（入出力のクロック差で遅延が増え続けるのを防ぐ）。
    private static let maxLatencySeconds = 0.25

    let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let maxPendingFrames: Int
    private let pendingFrames = Atomic<Int>(0)

    init(format: AVAudioFormat, volume: Float) throws {
        self.format = format
        maxPendingFrames = Int(format.sampleRate * Self.maxLatencySeconds)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.volume = volume
        engine.prepare()
        try engine.start()
        player.play()
    }

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    var isRunning: Bool { engine.isRunning }

    func stop() {
        player.stop()
        engine.stop()
    }

    /// タップのバッファは呼び出し後に再利用されるため、コピーしてから予約する。
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0,
              pendingFrames.load(ordering: .relaxed) + frames <= maxPendingFrames,
              let source = buffer.floatChannelData,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              let destination = copy.floatChannelData
        else { return }

        copy.frameLength = buffer.frameLength
        for ch in 0..<min(Int(format.channelCount), Int(buffer.format.channelCount)) {
            destination[ch].update(from: source[ch], count: frames)
        }
        pendingFrames.add(frames, ordering: .relaxed)
        player.scheduleBuffer(copy, completionCallbackType: .dataConsumed) { [weak self] _ in
            self?.pendingFrames.subtract(frames, ordering: .relaxed)
        }
    }
}
