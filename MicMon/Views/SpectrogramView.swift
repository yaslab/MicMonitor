import CoreGraphics
import SwiftUI

/// スペクトログラム（横軸が時間、縦軸が対数周波数、色がレベル。色の付け方は設定で選ぶ）。時間軸は波形とそろえる。
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

    @AppStorage(SpectrogramColormap.storageKey) private var colormap = SpectrogramColormap.defaultValue
    @State private var imageCache = SpectrogramImageCache()

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
                if let image = imageCache.image(for: snapshot, columnsPerPixel: columnsPerPixel,
                                                colormap: colormap, accent: accent) {
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
}

/// スペクトログラムの画像を、新しく届いた列の分だけ描き足して使い回す。
///
/// 画像の 1 ピクセル幅は `columnsPerPixel` 列分（その中の最大値）で、まとめ方は通し番号で固定している。
/// そのため、届き終わった列のピクセルはあとから変わらない。新しい列が届いたら画素を左にずらし、
/// 最新の列を含むピクセルだけを計算し直す。列が増えていないフレームは前の画像をそのまま使う。
/// まとめる列の数・容量・カラーマップ・アクセントカラーが変わったら作り直す。
/// Canvas の描画（メインスレッド）からだけ使う。
private final class SpectrogramImageCache {
    private struct Key: Equatable {
        var columnsPerPixel: Int
        var capacity: Int
        var rowCount: Int
        var colormap: SpectrogramColormap
        var accent: Color.Resolved
    }

    private static let transparent = SpectrogramColormap.Pixel(red: 0, green: 0, blue: 0, alpha: 0)

    private var key: Key?
    private var lut: [SpectrogramColormap.Pixel] = []
    /// 画像の幅（ピクセル）。表示範囲（容量ぶんの列）がピクセルの境目をまたいでも収まるよう 1 つ多く取る。
    private var width = 0
    private var rows = 0
    /// RGBA（乗算済みアルファ）。上端が高い周波数。列が届いていないピクセルは透明（0）。
    private var pixels: [UInt8] = []
    /// 左端のピクセルの番号（列の通し番号 / `columnsPerPixel`）。
    private var startPixel = 0
    /// この通し番号の手前までの列を画素に反映した。
    private var drawnEnd = 0
    private var image: CGImage?

    /// `firstIndex` は画像の左端に当たる列の通し番号。`snapshot` には列が 1 つ以上あること。
    func image(for snapshot: SpectrogramSnapshot, columnsPerPixel: Int, colormap: SpectrogramColormap,
               accent: Color.Resolved) -> (image: CGImage, firstIndex: Int)? {
        let newKey = Key(columnsPerPixel: columnsPerPixel, capacity: snapshot.capacity,
                         rowCount: snapshot.rowCount, colormap: colormap, accent: accent)
        let firstColumn = snapshot.endIndex - snapshot.columnCount
        // 最新の列を右端のピクセルに置く
        let newStartPixel = (snapshot.endIndex - 1) / columnsPerPixel - width + 1

        if newKey != key {
            key = newKey
            lut = colormap.lookupTable(accent: accent)
            width = (snapshot.capacity + columnsPerPixel - 1) / columnsPerPixel + 1
            rows = snapshot.rowCount
            pixels = [UInt8](repeating: 0, count: width * rows * 4)
            startPixel = (snapshot.endIndex - 1) / columnsPerPixel - width + 1
            drawnEnd = firstColumn
            image = nil
        } else if snapshot.endIndex == drawnEnd, let image {
            return (image, startPixel * columnsPerPixel)
        } else if snapshot.endIndex < drawnEnd {
            // 別の履歴に変わった（通常は起きない）。全部描き直す
            clear()
            startPixel = newStartPixel
            drawnEnd = firstColumn
        } else {
            scroll(by: newStartPixel - startPixel)
            startPixel = newStartPixel
        }
        drawnEnd = max(drawnEnd, firstColumn, startPixel * columnsPerPixel)

        snapshot.levels.withUnsafeBufferPointer { levels in
            pixels.withUnsafeMutableBufferPointer { pixels in
                // 途中までしか届いていなかったピクセル（drawnEnd を含むもの）から右端までを計算し直す
                for pixel in (drawnEnd / columnsPerPixel)...((snapshot.endIndex - 1) / columnsPerPixel) {
                    let x = pixel - startPixel
                    let groupStart = pixel * columnsPerPixel
                    let lower = max(groupStart, firstColumn) - firstColumn
                    let upper = min(groupStart + columnsPerPixel, snapshot.endIndex) - firstColumn
                    for row in 0..<rows {
                        var color = Self.transparent
                        if lower < upper {
                            var level: UInt8 = 0
                            for column in lower..<upper {
                                level = max(level, levels[column * rows + row])
                            }
                            color = lut[Int(level)]
                        }
                        let offset = ((rows - 1 - row) * width + x) * 4
                        pixels[offset] = color.red
                        pixels[offset + 1] = color.green
                        pixels[offset + 2] = color.blue
                        pixels[offset + 3] = color.alpha
                    }
                }
            }
        }
        drawnEnd = snapshot.endIndex

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let newImage = CGImage(width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32,
                                     bytesPerRow: width * 4, space: space,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else {
            image = nil
            return nil
        }
        image = newImage
        return (newImage, startPixel * columnsPerPixel)
    }

    /// 画素を `count` ピクセル左にずらし、空いた右側を透明にする。
    private func scroll(by count: Int) {
        guard count > 0 else { return }
        guard count < width else {
            clear()
            return
        }
        let rowBytes = width * 4
        let shiftBytes = count * 4
        pixels.withUnsafeMutableBytes { bytes in
            let base = bytes.baseAddress!
            for row in 0..<rows {
                let start = base + row * rowBytes
                memmove(start, start + shiftBytes, rowBytes - shiftBytes)
                memset(start + rowBytes - shiftBytes, 0, shiftBytes)
            }
        }
    }

    private func clear() {
        pixels.withUnsafeMutableBytes { _ = $0.initializeMemory(as: UInt8.self, repeating: 0) }
    }
}
