import SwiftUI

/// スペクトル表示の目盛り。横軸は対数（20 Hz〜約 20 kHz）、縦軸は dBFS。
enum SpectrumScale {
    static let minFrequency = 20.0
    /// 20 Hz からちょうど 10 オクターブ（帯域が横軸に過不足なく並ぶように）。
    static let maxFrequency = 20_480.0
    static let floorDB: Float = -100
    /// 1 オクターブあたりの帯域数。
    static let bandsPerOctave = 12
    /// 縦の格子線と、ウィンドウ表示の周波数軸の目盛り（位置をそろえるため共通にする）。
    static let gridFrequencies: [Double] = [50, 100, 200, 500, 1000, 2000, 5000, 10_000]

    /// 周波数を横軸の 0...1 にする。
    static func position(_ frequency: Double) -> Double {
        log2(frequency / minFrequency) / log2(maxFrequency / minFrequency)
    }

    static func normalized(_ db: Float) -> Float {
        Decibel.normalized(db, floor: floorDB)
    }

    static func decibel(_ amplitude: Float) -> Float {
        Decibel.from(amplitude, floor: floorDB)
    }

    static func label(_ frequency: Double) -> String {
        frequency >= 1000 ? String(format: "%gk", frequency / 1000) : String(format: "%g", frequency)
    }
}

struct SpectrumBand: Equatable {
    var levelDB: Float
    var holdDB: Float
}

/// FFT のビンを対数間隔の帯域にまとめ、表示の減衰とピークホールドを行う。描画フレームごとに `update` を呼ぶ。
@MainActor
final class SpectrumBallistics {
    static let releaseDBPerSecond: Float = 60
    static let holdReleaseDBPerSecond: Float = 30
    static let holdSeconds: TimeInterval = 1.5

    private let layout = SpectrumBands()
    private var bands: [SpectrumBand]
    private var holds: [PeakHold]
    private var clock = FrameClock()

    init() {
        bands = Array(repeating: SpectrumBand(levelDB: SpectrumScale.floorDB, holdDB: SpectrumScale.floorDB),
                      count: layout.count)
        holds = Array(repeating: PeakHold(SpectrumScale.floorDB), count: layout.count)
    }

    func update(snapshot: SpectrumSnapshot, now: Date) -> [SpectrumBand] {
        let dt = clock.step(to: now)
        let decay = Self.releaseDBPerSecond * dt
        let holdDecay = Self.holdReleaseDBPerSecond * dt
        let amplitudes = layout.amplitudes(of: snapshot)

        for i in bands.indices {
            let db = SpectrumScale.decibel(amplitudes[i])
            let level = max(db, bands[i].levelDB - decay)
            holds[i].update(peak: db, level: level, release: holdDecay, holdSeconds: Self.holdSeconds, now: now)
            bands[i] = SpectrumBand(levelDB: level, holdDB: holds[i].value)
        }
        return bands
    }
}

struct SpectrumSection: View {
    let bands: [SpectrumBand]
    let compact: Bool

    private static let compactAxisFrequencies: [Double] = [100, 1000, 10_000]
    private static let gutterWidth: CGFloat = 20
    /// カード表示での高さ。カードの波形も 1 段をこの高さにそろえる。
    static let compactHeight: CGFloat = 36

    var body: some View {
        if compact {
            SpectrumView(bands: bands, labels: Self.compactAxisFrequencies, showsGrid: false)
                .frame(height: Self.compactHeight)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // 縦軸（dBFS）の目盛り
                    VStack(alignment: .trailing) {
                        Text("0")
                        Spacer()
                        Text("-50")
                        Spacer()
                        Text(String(format: "%.0f", SpectrumScale.floorDB))
                    }
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: Self.gutterWidth, alignment: .trailing)
                    SpectrumView(bands: bands, labels: [], showsGrid: true)
                }
                .frame(height: 120)
                FrequencyAxis(frequencies: SpectrumScale.gridFrequencies)
                    .frame(height: 10)
                    .padding(.leading, Self.gutterWidth + 8)
            }
        }
    }
}

/// 対数周波数軸の目盛り（文字だけ）。
private struct FrequencyAxis: View {
    let frequencies: [Double]

    var body: some View {
        Canvas { context, size in
            for frequency in frequencies {
                let x = CGFloat(SpectrumScale.position(frequency)) * size.width
                context.draw(Text(SpectrumScale.label(frequency)).font(.system(size: 9)).foregroundStyle(.secondary),
                             at: CGPoint(x: x, y: 0), anchor: .top)
            }
            context.draw(Text("Hz").font(.system(size: 9)).foregroundStyle(.secondary),
                         at: CGPoint(x: size.width, y: 0), anchor: .topTrailing)
        }
    }
}

/// 振幅スペクトル（塗り: 現在値、線: ピークホールド）。
struct SpectrumView: View {
    let bands: [SpectrumBand]
    /// グラフの中に描く周波数の目盛り（カード表示用）。
    let labels: [Double]
    let showsGrid: Bool

    private static let gridDB: [Float] = [-20, -40, -60, -80]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4),
                         with: .color(.secondary.opacity(0.08)))

            func y(_ db: Float) -> CGFloat { size.height * (1 - CGFloat(SpectrumScale.normalized(db))) }

            var grid = Path()
            for frequency in SpectrumScale.gridFrequencies {
                let x = CGFloat(SpectrumScale.position(frequency)) * size.width
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            if showsGrid {
                for db in Self.gridDB {
                    grid.move(to: CGPoint(x: 0, y: y(db)))
                    grid.addLine(to: CGPoint(x: size.width, y: y(db)))
                }
            }
            context.stroke(grid, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)

            for frequency in labels {
                let x = CGFloat(SpectrumScale.position(frequency)) * size.width + 2
                context.draw(Text(SpectrumScale.label(frequency)).font(.system(size: 8)).foregroundStyle(.secondary),
                             at: CGPoint(x: x, y: 1), anchor: .topLeading)
            }

            guard bands.count > 1, size.width >= 1 else { return }
            context.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4))

            // 各帯域の中心に点を置く
            let step = size.width / CGFloat(bands.count)
            func x(_ index: Int) -> CGFloat { (CGFloat(index) + 0.5) * step }

            var level = Path()
            level.move(to: CGPoint(x: 0, y: size.height))
            level.addLine(to: CGPoint(x: 0, y: y(bands[0].levelDB)))
            var hold = Path()
            hold.move(to: CGPoint(x: 0, y: y(bands[0].holdDB)))
            for (i, band) in bands.enumerated() {
                level.addLine(to: CGPoint(x: x(i), y: y(band.levelDB)))
                hold.addLine(to: CGPoint(x: x(i), y: y(band.holdDB)))
            }
            level.addLine(to: CGPoint(x: size.width, y: y(bands[bands.count - 1].levelDB)))
            level.addLine(to: CGPoint(x: size.width, y: size.height))
            level.closeSubpath()
            hold.addLine(to: CGPoint(x: size.width, y: y(bands[bands.count - 1].holdDB)))

            context.fill(level, with: .color(.accentColor.opacity(0.5)))
            context.stroke(hold, with: .color(.accentColor), lineWidth: 1)
        }
    }
}
