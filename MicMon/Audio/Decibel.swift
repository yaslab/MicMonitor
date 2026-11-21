import Foundation

enum Decibel {
    /// 表示レンジの下限 (dBFS)。
    static let floor: Float = -60

    /// 線形振幅を dBFS に変換し、下限でクランプする。
    static func from(_ amplitude: Float) -> Float {
        amplitude > 0 ? max(floor, 20 * log10(amplitude)) : floor
    }

    /// dBFS を表示レンジ内の 0...1 に正規化する。
    static func normalized(_ db: Float) -> Float {
        min(max((db - floor) / -floor, 0), 1)
    }

    static func format(_ db: Float) -> String {
        db <= floor ? "-∞" : String(format: "%.1f", db)
    }
}
