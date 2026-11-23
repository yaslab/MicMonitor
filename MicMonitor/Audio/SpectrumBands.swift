import Foundation

/// FFT のビンを、`SpectrumScale` の対数間隔の帯域（20 Hz〜20.48 kHz を 1/12 オクターブ）にまとめる。
/// スペクトル表示とスペクトログラムで共通に使う。
struct SpectrumBands: Sendable {
    /// 各帯域の下端・上端の周波数（帯域数 + 1 個）。
    private let edges: [Double]

    var count: Int { edges.count - 1 }

    init() {
        let octaves = log2(SpectrumScale.maxFrequency / SpectrumScale.minFrequency)
        let count = Int((octaves * Double(SpectrumScale.bandsPerOctave)).rounded())
        edges = (0...count).map {
            SpectrumScale.minFrequency * pow(2, Double($0) / Double(SpectrumScale.bandsPerOctave))
        }
    }

    /// 帯域ごとの振幅（線形）。低い周波数が先。
    func amplitudes(of snapshot: SpectrumSnapshot) -> [Float] {
        (0..<count).map {
            amplitude(snapshot.amplitudes, binWidth: snapshot.binWidth, lower: edges[$0], upper: edges[$0 + 1])
        }
    }

    /// 帯域に含まれるビンの最大値。ビンより狭い帯域（低域）は中心周波数で隣のビンと線形補間する。
    private func amplitude(_ amplitudes: [Float], binWidth: Double, lower: Double, upper: Double) -> Float {
        guard binWidth > 0, amplitudes.count > 1 else { return 0 }
        let last = amplitudes.count - 1
        let lowerBin = Int((lower / binWidth).rounded(.up))
        let upperBin = min(Int((upper / binWidth).rounded(.down)), last)
        if lowerBin <= upperBin {
            return amplitudes[lowerBin...upperBin].max() ?? 0
        }
        let position = (lower * upper).squareRoot() / binWidth
        guard position < Double(last) else { return 0 }
        let index = Int(position)
        let fraction = Float(position - Double(index))
        return amplitudes[index] * (1 - fraction) + amplitudes[index + 1] * fraction
    }
}
