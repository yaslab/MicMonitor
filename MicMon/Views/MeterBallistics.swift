import Foundation

struct MeterReading: Equatable {
    var rmsDB: Float
    var peakDB: Float
    var holdDB: Float
    var clipped: Bool
}

/// メーター表示の減衰・ピークホールド・クリップ表示の保持。描画フレームごとに `update` を呼ぶ。
@MainActor
final class MeterBallistics {
    static let releaseDBPerSecond: Float = 20
    /// ピークホールドとクリップ表示を保持する時間。
    static let holdSeconds: TimeInterval = 1.5

    private struct Channel {
        var rms = Decibel.floor
        var peak = Decibel.floor
        var hold = Decibel.floor
        var holdTime = Date.distantPast
        /// 最後にクリップを検出した時刻。
        var clipTime = Date.distantPast
    }

    private var channels: [Channel] = []
    private var lastUpdate: Date?

    func update(levels: [ChannelLevel], now: Date) -> [MeterReading] {
        #if DEBUG
        TimingProbe.frame.record()
        #endif
        // 一時停止明けなどで大きく飛ばないよう上限を設ける
        let dt = Float(min(max(lastUpdate.map { now.timeIntervalSince($0) } ?? 0, 0), 0.25))
        lastUpdate = now
        if channels.count != levels.count {
            channels = Array(repeating: Channel(), count: levels.count)
        }

        let decay = Self.releaseDBPerSecond * dt
        var readings: [MeterReading] = []
        readings.reserveCapacity(levels.count)
        for (i, level) in levels.enumerated() {
            let peakDB = Decibel.from(level.peak)
            let rmsDB = Decibel.from(level.rms)
            var channel = channels[i]
            channel.peak = max(peakDB, channel.peak - decay)
            channel.rms = max(rmsDB, channel.rms - decay)
            if peakDB >= channel.hold {
                channel.hold = peakDB
                channel.holdTime = now
            } else if now.timeIntervalSince(channel.holdTime) > Self.holdSeconds {
                channel.hold = max(channel.peak, channel.hold - decay)
            }
            // クリップ表示も、最後のクリップからピークホールドと同じ時間だけ点灯させて自動で消す
            if level.clipped { channel.clipTime = now }
            let clipped = now.timeIntervalSince(channel.clipTime) <= Self.holdSeconds
            channels[i] = channel
            readings.append(MeterReading(rmsDB: channel.rms, peakDB: channel.peak,
                                         holdDB: channel.hold, clipped: clipped))
        }
        return readings
    }

    /// クリップ表示をすぐに消す（丸をクリックしたとき）。
    func resetClip() {
        for i in channels.indices { channels[i].clipTime = .distantPast }
    }
}

enum ChannelLabel {
    static func label(index: Int, count: Int) -> String {
        if count == 2 { return index == 0 ? "L" : "R" }
        return "\(index + 1)"
    }
}
