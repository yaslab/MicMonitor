import Foundation

enum Decibel {
    /// メーター・波形の表示レンジの下限 (dBFS)。スペクトルは `SpectrumScale.floorDB` を使う。
    static let floor: Float = -60

    /// 線形振幅を dBFS に変換し、下限でクランプする。
    static func from(_ amplitude: Float, floor: Float = Decibel.floor) -> Float {
        amplitude > 0 ? max(floor, 20 * log10(amplitude)) : floor
    }

    /// dBFS を表示レンジ（`floor`...0）内の 0...1 に正規化する。
    static func normalized(_ db: Float, floor: Float = Decibel.floor) -> Float {
        min(max((db - floor) / -floor, 0), 1)
    }

    static func format(_ db: Float) -> String {
        db <= floor ? "-∞" : String(format: "%.1f", db)
    }
}
