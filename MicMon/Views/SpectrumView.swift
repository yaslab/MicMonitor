import SwiftUI

/// スペクトル表示の目盛り。横軸は対数（20 Hz〜約 20 kHz）、縦軸は dBFS。
enum SpectrumScale {
    static let minFrequency = 20.0
    /// 20 Hz からちょうど 10 オクターブ（帯域が横軸に過不足なく並ぶように）。
    static let maxFrequency = 20_480.0
    static let floorDB: Float = -100
    /// 1 オクターブあたりの帯域数。
    static let bandsPerOctave = 12
    /// ウィンドウ表示の周波数軸の目盛り。
    static let axisFrequencies: [Double] = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10_000, 20_000]
    /// 縦の格子線（10 倍ごと）。スペクトログラムの周波数の目盛りにも使う。
    static let decadeFrequencies: [Double] = [100, 1000, 10_000]
    /// ウィンドウ表示の dB 軸の目盛りと横の格子線。
    static let axisDB: [Float] = [0, -20, -40, -60, -80, -100]

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

/// `SpectrumBands` でまとめた帯域ごとに、表示の減衰とピークホールドを行う。描画フレームごとに `update` を呼ぶ。
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

    /// カード表示での高さ。カードの波形も 1 段をこの高さにそろえる。
    static let compactHeight: CGFloat = 36

    var body: some View {
        if compact {
            SpectrumView(bands: bands, compact: true)
                .frame(height: Self.compactHeight)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: MonitorLayout.gutterSpacing) {
                    DecibelAxis()
                        .frame(width: MonitorLayout.gutterWidth)
                    SpectrumView(bands: bands, compact: false)
                }
                .frame(height: 112)
                FrequencyAxis()
                    .frame(height: 14)
                    .padding(.leading, MonitorLayout.gutterWidth + MonitorLayout.gutterSpacing)
            }
        }
    }
}

/// 縦の dBFS 軸の目盛り（文字だけ）。両端の文字はグラフの中に収める。
private struct DecibelAxis: View {
    var body: some View {
        Canvas { context, size in
            for db in SpectrumScale.axisDB {
                let y = size.height * (1 - CGFloat(SpectrumScale.normalized(db)))
                let anchor: UnitPoint = db == SpectrumScale.axisDB.first ? .topTrailing
                    : db == SpectrumScale.axisDB.last ? .bottomTrailing : .trailing
                context.draw(Text(String(format: "%.0f", db)).font(MonitorLayout.axisFont).foregroundStyle(.secondary),
                             at: CGPoint(x: size.width, y: y), anchor: anchor)
            }
        }
    }
}

/// 対数周波数軸の目盛り（文字だけ）。両端の文字はグラフの中に収める。
private struct FrequencyAxis: View {
    var body: some View {
        Canvas { context, size in
            let frequencies = SpectrumScale.axisFrequencies
            for frequency in frequencies {
                let x = CGFloat(SpectrumScale.position(frequency)) * size.width
                let anchor: UnitPoint = frequency == frequencies.first ? .topLeading
                    : frequency == frequencies.last ? .topTrailing : .top
                context.draw(Text(SpectrumScale.label(frequency)).font(MonitorLayout.axisFont).foregroundStyle(.secondary),
                             at: CGPoint(x: frequency == frequencies.last ? size.width : x, y: 0), anchor: anchor)
            }
        }
    }
}

/// 振幅スペクトル（塗り: 現在値、線: ピークホールド）。
struct SpectrumView: View {
    let bands: [SpectrumBand]
    /// カード表示用: 格子線を描かず、下地を半透明にする。
    let compact: Bool

    var body: some View {
        Canvas { context, size in
            let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)
            context.fill(shape, with: .color(compact ? .cardWell : .plot))
            context.clip(to: shape)

            func y(_ db: Float) -> CGFloat { size.height * (1 - CGFloat(SpectrumScale.normalized(db))) }

            if !compact {
                var grid = Path()
                for frequency in SpectrumScale.decadeFrequencies {
                    let x = (CGFloat(SpectrumScale.position(frequency)) * size.width).rounded()
                    grid.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
                }
                for db in SpectrumScale.axisDB {
                    let y = min(y(db).rounded(), size.height - 1)
                    grid.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                }
                context.fill(grid, with: .color(.plotGrid))
            }

            guard bands.count > 1, size.width >= 1 else { return }

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

            context.fill(level, with: .color(.accentColor.opacity(compact ? 0.5 : 0.45)))
            context.stroke(hold, with: .color(.peakLine.opacity(0.85)), lineWidth: compact ? 1 : 1.25)
        }
    }
}
