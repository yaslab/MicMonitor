import Accelerate
import Synchronization

struct WaveformBin: Sendable, Equatable {
    /// ビン内の最大振幅（線形）。
    var peak: Float
    /// ビン内の RMS（線形）。
    var rms: Float
}

struct WaveformSnapshot: Sendable {
    /// チャンネルごとのビン列（古い順）。要素数は `capacity` 以下。
    var channels: [[WaveformBin]]
    var capacity: Int
}

/// 波形を一定間隔のビン（Peak と RMS）に間引いて、チャンネルごとのリングバッファに保持する。
final class WaveformHistory: Sendable {
    static let binsPerSecond = 200

    private struct State {
        var capacity: Int
        var samplesPerBin = 240
        /// 次に書き込む位置。
        var head = 0
        /// 保持しているビン数。
        var count = 0
        var peaks: [[Float]] = []
        var rms: [[Float]] = []
        // 作りかけのビン
        var accumulatedFrames = 0
        var accumulatedPeak: [Float] = []
        var accumulatedSumOfSquares: [Float] = []

        var channelCount: Int { peaks.count }

        mutating func resetAccumulators() {
            accumulatedFrames = 0
            accumulatedPeak = Array(repeating: 0, count: channelCount)
            accumulatedSumOfSquares = Array(repeating: 0, count: channelCount)
        }

        /// リングバッファを古い順に並べ、最新の `limit` 個を返す。
        func ordered(_ ring: [Float], limit: Int) -> [Float] {
            let n = min(count, limit)
            let start = (head - n + capacity) % capacity
            return (0..<n).map { ring[(start + $0) % capacity] }
        }
    }

    private let state: Mutex<State>

    init(capacity: Int) {
        state = Mutex(State(capacity: max(1, capacity)))
    }

    /// ch 数が変わったときだけ履歴を消す。サンプルレートの変更ではビンの幅を計算し直すだけ。
    func configure(channelCount: Int, sampleRate: Double) {
        state.withLock { state in
            state.samplesPerBin = max(1, Int((sampleRate / Double(Self.binsPerSecond)).rounded()))
            if state.channelCount != channelCount {
                state.peaks = Array(repeating: Array(repeating: 0, count: state.capacity), count: channelCount)
                state.rms = state.peaks
                state.head = 0
                state.count = 0
            }
            state.resetAccumulators()
        }
    }

    /// 容量を変更する。最新のものから入る分だけ引き継ぐ。
    func setCapacity(_ newCapacity: Int) {
        let newCapacity = max(1, newCapacity)
        state.withLock { state in
            guard newCapacity != state.capacity else { return }
            let old = state
            let kept = min(old.count, newCapacity)
            func resized(_ ring: [Float]) -> [Float] {
                var result = old.ordered(ring, limit: kept)
                result.append(contentsOf: repeatElement(0, count: newCapacity - kept))
                return result
            }
            state.peaks = old.peaks.map(resized)
            state.rms = old.rms.map(resized)
            state.capacity = newCapacity
            state.count = kept
            state.head = kept % newCapacity
        }
    }

    func process(_ data: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int, frameCount: Int) {
        state.withLock { state in
            let channels = min(channelCount, state.channelCount)
            guard channels > 0 else { return }
            var offset = 0
            while offset < frameCount {
                let n = min(state.samplesPerBin - state.accumulatedFrames, frameCount - offset)
                for ch in 0..<channels {
                    let samples = UnsafePointer(data[ch] + offset)
                    var peak: Float = 0
                    var sumOfSquares: Float = 0
                    vDSP_maxmgv(samples, 1, &peak, vDSP_Length(n))
                    vDSP_svesq(samples, 1, &sumOfSquares, vDSP_Length(n))
                    state.accumulatedPeak[ch] = max(state.accumulatedPeak[ch], peak)
                    state.accumulatedSumOfSquares[ch] += sumOfSquares
                }
                state.accumulatedFrames += n
                offset += n

                if state.accumulatedFrames >= state.samplesPerBin {
                    let head = state.head
                    let frames = Float(state.accumulatedFrames)
                    for ch in 0..<channels {
                        state.peaks[ch][head] = state.accumulatedPeak[ch]
                        state.rms[ch][head] = (state.accumulatedSumOfSquares[ch] / frames).squareRoot()
                        state.accumulatedPeak[ch] = 0
                        state.accumulatedSumOfSquares[ch] = 0
                    }
                    state.accumulatedFrames = 0
                    state.head = (head + 1) % state.capacity
                    state.count = min(state.count + 1, state.capacity)
                }
            }
        }
    }

    func snapshot() -> WaveformSnapshot {
        state.withLock { state in
            let channels = (0..<state.channelCount).map { ch in
                zip(state.ordered(state.peaks[ch], limit: state.count),
                    state.ordered(state.rms[ch], limit: state.count))
                    .map { WaveformBin(peak: $0, rms: $1) }
            }
            return WaveformSnapshot(channels: channels, capacity: state.capacity)
        }
    }
}
