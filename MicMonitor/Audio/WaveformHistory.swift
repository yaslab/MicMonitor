import Accelerate
import Synchronization

struct WaveformBin: Sendable, Equatable {
    /// ビン内の最大値（符号付き、線形）。正側の振れ幅。
    var max: Float
    /// ビン内の最小値（符号付き、線形）。負側の振れ幅。
    var min: Float
    /// ビン内の RMS（線形）。
    var rms: Float

    /// 符号を問わない最大振幅。
    var peak: Float { Swift.max(max, -min, 0) }

    static let silent = WaveformBin(max: 0, min: 0, rms: 0)
}

struct WaveformSnapshot: Sendable {
    /// チャンネルごとのビン列（古い順）。要素数は `capacity` 以下。
    var channels: [[WaveformBin]]
    var capacity: Int
    /// 最新のビンの次の通し番号（記録開始からの累計ビン数）。
    /// `channels[ch][i]` の通し番号は `endIndex - channels[ch].count + i`。
    var endIndex: Int
}

/// 波形を一定間隔のビン（最大値・最小値・RMS）に間引いて、チャンネルごとのリングバッファに保持する。
final class WaveformHistory: Sendable {
    static let binsPerSecond = 200

    private struct State {
        var capacity: Int
        var samplesPerBin = 240
        /// 次に書き込む位置。
        var head = 0
        /// 保持しているビン数。
        var count = 0
        /// 記録開始からの累計ビン数（描画で列のまとめ方を固定するための通し番号）。
        var totalBins = 0
        var rings: [[WaveformBin]] = []
        // 作りかけのビン
        var accumulatedFrames = 0
        var accumulatedMax: [Float] = []
        var accumulatedMin: [Float] = []
        var accumulatedSumOfSquares: [Float] = []

        var channelCount: Int { rings.count }

        /// ビンごとに呼ばれるため、ch 数が同じならメモリを確保せずにその場で初期化する。
        mutating func resetAccumulators() {
            accumulatedFrames = 0
            if accumulatedMax.count != channelCount {
                accumulatedMax = Array(repeating: -.infinity, count: channelCount)
                accumulatedMin = Array(repeating: .infinity, count: channelCount)
                accumulatedSumOfSquares = Array(repeating: 0, count: channelCount)
                return
            }
            for ch in 0..<channelCount {
                accumulatedMax[ch] = -.infinity
                accumulatedMin[ch] = .infinity
                accumulatedSumOfSquares[ch] = 0
            }
        }

        /// リングバッファを古い順に並べ、最新の `limit` 個を返す。
        func ordered(_ ring: [WaveformBin], limit: Int) -> [WaveformBin] {
            let n = Swift.min(count, limit)
            let start = (head - n + capacity) % capacity
            return (0..<n).map { ring[(start + $0) % capacity] }
        }
    }

    private let state: Mutex<State>

    init(capacity: Int) {
        state = Mutex(State(capacity: Swift.max(1, capacity)))
    }

    /// ch 数が変わったときだけ履歴を消す。サンプルレートの変更ではビンの幅を計算し直すだけ。
    func configure(channelCount: Int, sampleRate: Double) {
        state.withLock { state in
            state.samplesPerBin = Swift.max(1, Int((sampleRate / Double(Self.binsPerSecond)).rounded()))
            if state.channelCount != channelCount {
                state.rings = Array(repeating: Array(repeating: .silent, count: state.capacity), count: channelCount)
                state.head = 0
                state.count = 0
                state.totalBins = 0
            }
            state.resetAccumulators()
        }
    }

    /// 容量を変更する。最新のものから入る分だけ引き継ぐ。
    func setCapacity(_ newCapacity: Int) {
        let newCapacity = Swift.max(1, newCapacity)
        state.withLock { state in
            guard newCapacity != state.capacity else { return }
            let old = state
            let kept = Swift.min(old.count, newCapacity)
            state.rings = old.rings.map { ring in
                var result = old.ordered(ring, limit: kept)
                result.append(contentsOf: repeatElement(.silent, count: newCapacity - kept))
                return result
            }
            state.capacity = newCapacity
            state.count = kept
            state.head = kept % newCapacity
        }
    }

    func process(_ data: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int, frameCount: Int) {
        state.withLock { state in
            let channels = Swift.min(channelCount, state.channelCount)
            guard channels > 0 else { return }
            var offset = 0
            while offset < frameCount {
                let n = Swift.min(state.samplesPerBin - state.accumulatedFrames, frameCount - offset)
                let length = vDSP_Length(n)
                for ch in 0..<channels {
                    let samples = UnsafePointer(data[ch] + offset)
                    var maximum: Float = 0
                    var minimum: Float = 0
                    var sumOfSquares: Float = 0
                    vDSP_maxv(samples, 1, &maximum, length)
                    vDSP_minv(samples, 1, &minimum, length)
                    vDSP_svesq(samples, 1, &sumOfSquares, length)
                    state.accumulatedMax[ch] = Swift.max(state.accumulatedMax[ch], maximum)
                    state.accumulatedMin[ch] = Swift.min(state.accumulatedMin[ch], minimum)
                    state.accumulatedSumOfSquares[ch] += sumOfSquares
                }
                state.accumulatedFrames += n
                offset += n

                if state.accumulatedFrames >= state.samplesPerBin {
                    let head = state.head
                    let frames = Float(state.accumulatedFrames)
                    for ch in 0..<channels {
                        state.rings[ch][head] = WaveformBin(
                            max: state.accumulatedMax[ch],
                            min: state.accumulatedMin[ch],
                            rms: (state.accumulatedSumOfSquares[ch] / frames).squareRoot()
                        )
                    }
                    state.resetAccumulators()
                    state.head = (head + 1) % state.capacity
                    state.count = Swift.min(state.count + 1, state.capacity)
                    state.totalBins += 1
                }
            }
        }
    }

    func snapshot() -> WaveformSnapshot {
        state.withLock { state in
            WaveformSnapshot(channels: state.rings.map { state.ordered($0, limit: state.count) },
                             capacity: state.capacity,
                             endIndex: state.totalBins)
        }
    }
}
