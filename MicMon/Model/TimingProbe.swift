#if DEBUG
import Foundation
import Synchronization

/// 計測用（DEBUG のみ）: 一定数のイベントの到着時刻と値を記録し、間隔の統計を返す。
/// タップのスレッドからも MainActor からも記録できる。
final class TimingProbe: Sendable {
    /// 入力タップのバッファ到着（値 = フレーム数）。
    static let tap = TimingProbe()
    /// 描画フレーム（値は未使用）。
    static let frame = TimingProbe()

    private static let capacity = 600

    private struct Sample {
        var time: ContinuousClock.Instant
        var value: Int
    }

    private let samples = Mutex<[Sample]>([])

    func reset() {
        samples.withLock {
            $0.removeAll(keepingCapacity: true)
            $0.reserveCapacity(Self.capacity)
        }
    }

    func record(_ value: Int = 0) {
        let now = ContinuousClock.now
        samples.withLock {
            if $0.count < Self.capacity { $0.append(Sample(time: now, value: value)) }
        }
    }

    /// 間隔（ms）の最小・平均・最大と、1 秒あたりの回数、値の分布。
    func summary() -> String {
        let samples = samples.withLock { $0 }
        guard samples.count >= 2, let first = samples.first, let last = samples.last else {
            return "\(samples.count) events"
        }
        let intervals = zip(samples.dropFirst(), samples).map { ms($0.time - $1.time) }
        let span = ms(last.time - first.time)
        let rate = Double(samples.count - 1) / (span / 1000)
        let values = Dictionary(grouping: samples, by: \.value).mapValues(\.count)
            .sorted { $0.key < $1.key }
            .map { "\($0.key)×\($0.value)" }
            .joined(separator: " ")
        return String(format: "%d events in %.0f ms, %.1f /s, interval min %.1f / avg %.1f / max %.1f ms",
                      samples.count, span, rate,
                      intervals.min() ?? 0, intervals.reduce(0, +) / Double(intervals.count), intervals.max() ?? 0)
            + ", values: \(values)"
    }

    private func ms(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }
}
#endif
