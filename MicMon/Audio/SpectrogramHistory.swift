import Synchronization

struct SpectrogramSnapshot: Sendable {
    /// 列を古い順に並べたもの（列の数 × `rowCount`）。1 列は帯域ごとのレベルで、低い周波数が先。
    /// レベルは `SpectrumScale.floorDB`...0 dBFS を 0...255 に量子化した値。
    var levels: [UInt8]
    var rowCount: Int
    var capacity: Int
    /// 最新の列の次の通し番号（記録開始からの累計列数）。
    /// i 番目の列の通し番号は `endIndex - columnCount + i`。
    var endIndex: Int

    var columnCount: Int { rowCount > 0 ? levels.count / rowCount : 0 }
}

/// 一定間隔でスペクトルを求め、対数間隔の帯域にまとめて量子化した列をリングバッファに保持する。
///
/// 書き込みはポンプのタスク、`snapshot()` は MainActor から呼ぶ。FFT は列を作るときにポンプのタスクで行う
/// （48 kHz で 4096 点 × ch 数を 1 秒に 50 回）。
final class SpectrogramHistory: Sendable {
    static let columnsPerSecond = 50

    private struct State {
        var capacity: Int
        var samplesPerColumn = 960
        /// 前の列を作ってから受け取ったフレーム数。
        var pendingFrames = 0
        /// 次に書き込む列の位置。
        var head = 0
        /// 保持している列数。
        var count = 0
        /// 記録開始からの累計列数（描画で列のまとめ方を固定するための通し番号）。
        var totalColumns = 0
        /// `capacity` × 帯域数。
        var ring: [UInt8]

        /// リングバッファを古い順に並べ、最新の `limit` 列を返す。
        func ordered(rowCount: Int, limit: Int) -> [UInt8] {
            let n = min(count, limit)
            let start = (head - n + capacity) % capacity
            var result: [UInt8] = []
            result.reserveCapacity(n * rowCount)
            let firstPart = min(n, capacity - start)
            result.append(contentsOf: ring[(start * rowCount)..<((start + firstPart) * rowCount)])
            result.append(contentsOf: ring[0..<((n - firstPart) * rowCount)])
            return result
        }
    }

    private let bands = SpectrumBands()
    /// 列を作るための FFT。ポンプのタスクだけが使う（`state` の中で呼ぶ）。
    private let analyzer = SpectrumAnalyzer()
    private let state: Mutex<State>

    init(capacity: Int) {
        let capacity = max(1, capacity)
        state = Mutex(State(capacity: capacity, ring: Array(repeating: 0, count: capacity * bands.count)))
    }

    /// サンプルレートや ch 数が変わっても履歴は残す（全チャンネルの平均なので列の意味は変わらない）。
    func configure(channelCount: Int, sampleRate: Double) {
        state.withLock { state in
            analyzer.configure(channelCount: channelCount, sampleRate: sampleRate)
            state.samplesPerColumn = max(1, Int((sampleRate / Double(Self.columnsPerSecond)).rounded()))
            state.pendingFrames = 0
        }
    }

    /// 容量を変更する。最新のものから入る分だけ引き継ぐ。
    func setCapacity(_ newCapacity: Int) {
        let newCapacity = max(1, newCapacity)
        let rowCount = bands.count
        state.withLock { state in
            guard newCapacity != state.capacity else { return }
            let kept = min(state.count, newCapacity)
            var ring = state.ordered(rowCount: rowCount, limit: kept)
            ring.append(contentsOf: repeatElement(0, count: (newCapacity - kept) * rowCount))
            state.ring = ring
            state.capacity = newCapacity
            state.count = kept
            state.head = kept % newCapacity
        }
    }

    func process(_ data: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int, frameCount: Int) {
        guard channelCount > 0 else { return }
        let rowCount = bands.count
        state.withLock { state in
            withUnsafeTemporaryAllocation(of: UnsafeMutablePointer<Float>.self, capacity: channelCount) { pointers in
                var offset = 0
                while offset < frameCount {
                    // 列の区切りでいったん止めて、ちょうどその時点のスペクトルを列にする
                    let n = min(state.samplesPerColumn - state.pendingFrames, frameCount - offset)
                    for ch in 0..<channelCount {
                        pointers[ch] = data[ch] + offset
                    }
                    analyzer.process(UnsafePointer(pointers.baseAddress!), channelCount: channelCount, frameCount: n)
                    state.pendingFrames += n
                    offset += n

                    guard state.pendingFrames >= state.samplesPerColumn else { continue }
                    state.pendingFrames = 0
                    let amplitudes = bands.amplitudes(of: analyzer.snapshot())
                    let base = state.head * rowCount
                    for row in 0..<rowCount {
                        let level = SpectrumScale.normalized(SpectrumScale.decibel(amplitudes[row]))
                        state.ring[base + row] = UInt8((level * 255).rounded())
                    }
                    state.head = (state.head + 1) % state.capacity
                    state.count = min(state.count + 1, state.capacity)
                    state.totalColumns += 1
                }
            }
        }
    }

    func snapshot() -> SpectrogramSnapshot {
        let rowCount = bands.count
        return state.withLock { state in
            SpectrogramSnapshot(levels: state.ordered(rowCount: rowCount, limit: state.count),
                                rowCount: rowCount, capacity: state.capacity, endIndex: state.totalColumns)
        }
    }
}
