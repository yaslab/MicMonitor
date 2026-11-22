import CoreGraphics
import SwiftUI

/// スペクトログラム（横軸が時間、縦軸が対数周波数、濃さがレベル）。時間軸は波形とそろえる。
struct SpectrogramSection: View {
    let snapshot: SpectrogramSnapshot
    let seconds: Int
    /// カード表示用: 目盛りを中に描き、時間軸を省いて、スペクトルと同じ高さにする。
    var compact = false

    private static let axisFrequencies: [Double] = [100, 1000, 10_000]
    private static let gutterWidth: CGFloat = 20

    var body: some View {
        if compact {
            SpectrogramView(snapshot: snapshot, gridFrequencies: Self.axisFrequencies,
                            labels: Self.axisFrequencies)
                .frame(height: SpectrumSection.compactHeight)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    FrequencyLabels(frequencies: Self.axisFrequencies)
                        .frame(width: Self.gutterWidth)
                    SpectrogramView(snapshot: snapshot, gridFrequencies: Self.axisFrequencies)
                }
                .frame(height: 100)
                TimeAxis(seconds: seconds)
                    .padding(.leading, Self.gutterWidth + 8)
            }
        }
    }
}

/// 縦の対数周波数軸の目盛り（文字だけ）。
private struct FrequencyLabels: View {
    let frequencies: [Double]

    var body: some View {
        Canvas { context, size in
            for frequency in frequencies {
                let y = (1 - CGFloat(SpectrumScale.position(frequency))) * size.height
                context.draw(Text(SpectrumScale.label(frequency)).font(.system(size: 9)).foregroundStyle(.secondary),
                             at: CGPoint(x: size.width, y: min(max(y, 6), size.height - 6)), anchor: .trailing)
            }
        }
    }
}

struct SpectrogramView: View {
    let snapshot: SpectrogramSnapshot
    let gridFrequencies: [Double]
    /// グラフの中（左端）に描く周波数の目盛り（カード表示用）。
    var labels: [Double] = []

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let shape = Path(roundedRect: bounds, cornerRadius: 4)
            context.fill(shape, with: .color(.secondary.opacity(0.08)))
            context.clip(to: shape)

            let capacity = snapshot.capacity
            if capacity > 0, snapshot.columnCount > 0, size.width >= 1 {
                // 1 ピクセル（以上）にまとめる列の数。まとめ方は波形と同じく通し番号で固定する（チラつかないように）
                let columnsPerPixel = max(1, Int((Double(capacity) / Double(size.width)).rounded(.up)))
                let accent = Color.accentColor.resolve(in: context.environment)
                if let image = Self.makeImage(snapshot, columnsPerPixel: columnsPerPixel, color: accent) {
                    let columnWidth = size.width / CGFloat(capacity)
                    let windowStart = snapshot.endIndex - capacity
                    let x = CGFloat(image.firstIndex - windowStart) * columnWidth
                    let width = CGFloat(image.image.width * columnsPerPixel) * columnWidth
                    context.draw(Image(decorative: image.image, scale: 1).interpolation(.medium),
                                 in: CGRect(x: x, y: 0, width: width, height: size.height))
                }
            }

            var grid = Path()
            for frequency in gridFrequencies {
                let y = (1 - CGFloat(SpectrumScale.position(frequency))) * size.height
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)

            for frequency in labels {
                let y = (1 - CGFloat(SpectrumScale.position(frequency))) * size.height
                context.draw(Text(SpectrumScale.label(frequency)).font(.system(size: 8)).foregroundStyle(.secondary),
                             at: CGPoint(x: 2, y: min(max(y, 5), size.height - 5)), anchor: .leading)
            }
        }
    }

    /// 1 ピクセル幅が `columnsPerPixel` 列分（その中の最大値）の画像を作る。上端が高い周波数。
    /// `firstIndex` は画像の左端の列の通し番号。
    private static func makeImage(_ snapshot: SpectrogramSnapshot, columnsPerPixel: Int,
                                  color: Color.Resolved) -> (image: CGImage, firstIndex: Int)? {
        let rows = snapshot.rowCount
        let firstColumn = snapshot.endIndex - snapshot.columnCount
        let firstIndex = firstColumn / columnsPerPixel * columnsPerPixel
        let width = (snapshot.endIndex - firstIndex + columnsPerPixel - 1) / columnsPerPixel

        // レベル 0...255 を、アクセントカラーの濃さ（乗算済みアルファ）にする
        let lut: [(UInt8, UInt8, UInt8, UInt8)] = (0..<256).map { level in
            let alpha = Float(level) / 255
            func channel(_ value: Float) -> UInt8 { UInt8((min(max(value, 0), 1) * alpha * 255).rounded()) }
            return (channel(color.red), channel(color.green), channel(color.blue), UInt8(level))
        }

        var pixels = [UInt8](repeating: 0, count: width * rows * 4)
        snapshot.levels.withUnsafeBufferPointer { levels in
            pixels.withUnsafeMutableBufferPointer { pixels in
                for x in 0..<width {
                    let groupStart = firstIndex + x * columnsPerPixel
                    let lower = max(groupStart, firstColumn) - firstColumn
                    let upper = min(groupStart + columnsPerPixel, snapshot.endIndex) - firstColumn
                    guard lower < upper else { continue }
                    for row in 0..<rows {
                        var level: UInt8 = 0
                        for column in lower..<upper {
                            level = max(level, levels[column * rows + row])
                        }
                        let (r, g, b, a) = lut[Int(level)]
                        let offset = ((rows - 1 - row) * width + x) * 4
                        pixels[offset] = r
                        pixels[offset + 1] = g
                        pixels[offset + 2] = b
                        pixels[offset + 3] = a
                    }
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return (image, firstIndex)
    }
}
