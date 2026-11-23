import Foundation

struct MeterReading: Equatable {
    var rmsDB: Float
    var peakDB: Float
    var holdDB: Float
    var clipped: Bool
}

/// 描画フレームの間の経過時間。一時停止明けなどで大きく飛ばないよう上限を設ける。
struct FrameClock {
    static let maxStep: TimeInterval = 0.25
    private var lastUpdate: Date?

    /// 前回からの経過秒数（初回は 0）。
    mutating func step(to now: Date) -> Float {
        let elapsed = lastUpdate.map { now.timeIntervalSince($0) } ?? 0
        lastUpdate = now
        return Float(min(max(elapsed, 0), Self.maxStep))
    }
}

/// ピークホールド（dB）。ピークが保持値以上なら更新し、保持時間を過ぎたら下げ始める。
struct PeakHold {
    private(set) var value: Float
    private var time = Date.distantPast

    init(_ value: Float) {
        self.value = value
    }

    /// - Parameters:
    ///   - peak: このフレームのピーク。
    ///   - level: 下げるときの下限（減衰中の現在値）。
    ///   - release: 保持時間を過ぎたあと、このフレームで下げる量。
    mutating func update(peak: Float, level: Float, release: Float, holdSeconds: TimeInterval, now: Date) {
        if peak >= value {
            value = peak
            time = now
        } else if now.timeIntervalSince(time) > holdSeconds {
            value = max(level, value - release)
        }
    }
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
        var hold = PeakHold(Decibel.floor)
        /// 最後にクリップを検出した時刻。
        var clipTime = Date.distantPast
    }

    private var channels: [Channel] = []
    private var clock = FrameClock()

    func update(levels: [ChannelLevel], now: Date) -> [MeterReading] {
        #if DEBUG
        TimingProbe.frame.record()
        #endif
        let dt = clock.step(to: now)
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
            channel.hold.update(peak: peakDB, level: channel.peak, release: decay,
                                holdSeconds: Self.holdSeconds, now: now)
            // クリップ表示も、最後のクリップからピークホールドと同じ時間だけ点灯させて自動で消す
            if level.clipped { channel.clipTime = now }
            let clipped = now.timeIntervalSince(channel.clipTime) <= Self.holdSeconds
            channels[i] = channel
            readings.append(MeterReading(rmsDB: channel.rms, peakDB: channel.peak,
                                         holdDB: channel.hold.value, clipped: clipped))
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
