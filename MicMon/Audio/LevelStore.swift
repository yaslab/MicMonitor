import Accelerate
import Synchronization

struct ChannelLevel: Sendable, Equatable {
    /// 前回の `read()` 以降の最大 Peak（線形振幅）。
    var peak: Float
    /// 直近バッファの RMS（線形振幅）。
    var rms: Float
    /// クリップを検出したか（`resetClip()` まで保持）。
    var clipped: Bool
}

/// タップのスレッドで書き、UI で読むチャンネルごとのレベル。
final class LevelStore: Sendable {
    /// -0.1 dBFS
    static let clipThreshold: Float = 0.988_553

    private struct State {
        var peak: [Float] = []
        var rms: [Float] = []
        var clipped: [Bool] = []
    }

    private let state = Mutex(State())

    func configure(channelCount: Int) {
        state.withLock { state in
            if state.peak.count != channelCount {
                state.clipped = Array(repeating: false, count: channelCount)
            }
            state.peak = Array(repeating: 0, count: channelCount)
            state.rms = Array(repeating: 0, count: channelCount)
        }
    }

    func reset() {
        state.withLock { state in
            for i in state.peak.indices {
                state.peak[i] = 0
                state.rms[i] = 0
            }
        }
    }

    func resetClip() {
        state.withLock { state in
            for i in state.clipped.indices { state.clipped[i] = false }
        }
    }

    func process(_ data: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int, frameCount: Int) {
        guard frameCount > 0 else { return }
        let length = vDSP_Length(frameCount)
        state.withLock { state in
            for ch in 0..<min(channelCount, state.peak.count) {
                var peak: Float = 0
                var rms: Float = 0
                vDSP_maxmgv(data[ch], 1, &peak, length)
                vDSP_rmsqv(data[ch], 1, &rms, length)
                state.peak[ch] = max(state.peak[ch], peak)
                state.rms[ch] = rms
                if peak >= Self.clipThreshold { state.clipped[ch] = true }
            }
        }
    }

    /// 現在の値を返し、Peak の保持をリセットする。
    func read() -> [ChannelLevel] {
        state.withLock { state in
            let result = state.peak.indices.map {
                ChannelLevel(peak: state.peak[$0], rms: state.rms[$0], clipped: state.clipped[$0])
            }
            for i in state.peak.indices { state.peak[i] = 0 }
            return result
        }
    }
}
