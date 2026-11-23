import CoreGraphics
import SwiftUI

struct SettingsView: View {
    @Environment(MonitorModel.self) private var model
    @AppStorage(SpectrogramColormap.storageKey) private var colormap = SpectrogramColormap.defaultValue

    var body: some View {
        @Bindable var model = model
        let range = MonitorModel.historyRange
        Form {
            Section {
                #if os(macOS)
                LabeledContent("履歴の長さ") {
                    HStack(spacing: 14) {
                        historySlider
                        Stepper(value: $model.historySeconds, in: range) {
                            Text("\(model.historySeconds) 秒")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                #else
                // 幅の狭い画面でもスライダーを広く取れるよう、ステッパーの行の下に置く
                VStack(spacing: 8) {
                    Stepper(value: $model.historySeconds, in: range) {
                        LabeledContent("履歴の長さ") {
                            Text("\(model.historySeconds) 秒")
                                .monospacedDigit()
                        }
                    }
                    historySlider
                        .accessibilityHidden(true)
                }
                #endif
            } header: {
                Text("波形")
            } footer: {
                Text("1〜60 秒。波形とスペクトログラムの両方に適用されます。")
                    .font(AppFont.footnote)
                    .foregroundStyle(.secondary)
            }
            #if os(macOS)
            Section("スペクトログラム") {
                ColormapList(selection: $colormap)
                ColormapDescription(colormap: colormap)
            }
            #else
            Section("スペクトログラムのカラーマップ") {
                ForEach(SpectrogramColormap.allCases) { item in
                    ColormapRow(colormap: item, isSelected: item == colormap) { colormap = item }
                }
            }
            Section {
                ColormapDescription(colormap: colormap)
            }
            Section {
                Toggle("バックグラウンドでも計測を続ける", isOn: $model.continuesInBackground)
            } header: {
                Text("バックグラウンド")
            } footer: {
                Text("オフのときは、ほかのアプリに切り替えたり画面をロックしたりすると計測とモニター再生を止め、戻ったときに再開します。")
                    .font(AppFont.footnote)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 560)
        #endif
    }

    private var historySlider: some View {
        @Bindable var model = model
        let range = MonitorModel.historyRange
        #if os(macOS)
        return Slider(value: $model.historySecondsValue,
                      in: Double(range.lowerBound)...Double(range.upperBound),
                      step: 1) {
            Text("履歴の長さ")
        }
        .labelsHidden()
        #else
        // iOS は step を付けると 60 個の目盛りの点が出るので付けない（値は historySecondsValue が丸める）
        return Slider(value: $model.historySecondsValue,
                      in: Double(range.lowerBound)...Double(range.upperBound)) {
            Text("履歴の長さ")
        }
        .labelsHidden()
        #endif
    }
}

#if !os(macOS)
/// iOS: カラーマップの選択の 1 行（選択中はチェックマーク）。
private struct ColormapRow: View {
    let colormap: SpectrogramColormap
    let isSelected: Bool
    let select: () -> Void

    @ScaledMetric(relativeTo: .body) private var swatchWidth: CGFloat = 120

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
                Text(colormap.name)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ColormapGradient(colormap: colormap)
                    .frame(width: min(swatchWidth, 160), height: 14)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(colormap.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
#endif

#if os(macOS)
/// カラーマップの選択。各行に色の見本（弱い → 強い）を付ける。
private struct ColormapList: View {
    @Binding var selection: SpectrogramColormap

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("カラーマップ")
            VStack(spacing: 0) {
                ForEach(SpectrogramColormap.allCases) { colormap in
                    row(colormap)
                }
            }
            .padding(.horizontal, -8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("カラーマップ")
    }

    private func row(_ colormap: SpectrogramColormap) -> some View {
        let selected = colormap == selection
        return Button {
            selection = colormap
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.6),
                                  lineWidth: selected ? 4 : 1.5)
                    .frame(width: 14, height: 14)
                Text(colormap.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ColormapGradient(colormap: colormap)
                    .frame(width: 160, height: 12)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(colormap.name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

#endif

/// カラーマップの横向きのグラデーション（左が弱い）。単色は透明から始まるので、グラフの下地の上に重ねる。
private struct ColormapGradient: View {
    let colormap: SpectrogramColormap

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.plot)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(gradient: colormap.gradient, startPoint: .leading, endPoint: .trailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.primary.opacity(0.1))
            }
    }
}

/// 選択中のカラーマップの見本・色の流れ・特徴。
private struct ColormapDescription: View {
    let colormap: SpectrogramColormap

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                heading("見本")
                ColormapSample(colormap: colormap)
                    #if os(macOS)
                    .frame(height: 84)
                    #else
                    .frame(height: 96)
                    #endif
            }
            VStack(alignment: .leading, spacing: 6) {
                heading("色の流れ")
                ColormapGradient(colormap: colormap)
                    .frame(height: 14)
                HStack {
                    Text("-100 dB")
                    Spacer()
                    Text("-75")
                    Spacer()
                    Text("-50")
                    Spacer()
                    Text("-25")
                    Spacer()
                    Text("0 dB")
                }
                .font(AppFont.axis)
                .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                heading("特徴")
                Text(colormap.summary)
                    .font(AppFont.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(AppFont.panelTitle)
            .kerning(0.4)
            .foregroundStyle(.secondary)
    }
}

/// カラーマップの見本。話し声のようなスペクトログラムを計算で作り、選んだカラーマップで塗る（実際の入力ではない）。
private struct ColormapSample: View {
    let colormap: SpectrogramColormap

    var body: some View {
        Canvas { context, size in
            let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5)
            context.fill(shape, with: .color(.plot))
            context.clip(to: shape)
            let accent = Color.accentColor.resolve(in: context.environment)
            if let image = SampleSpectrogram.image(colormap: colormap, accent: accent) {
                context.draw(Image(decorative: image, scale: 1).interpolation(.medium),
                             in: CGRect(origin: .zero, size: size))
            }
        }
    }
}

/// 見本のスペクトログラム（docs/ui/macos の Settings.dc.html の見本と同じ作り方）。
private enum SampleSpectrogram {
    static let columns = 110
    static let rows = 40

    /// レベル 0...255（行は下が低い周波数）。一度だけ計算する。
    private static let levels: [UInt8] = {
        var random = LinearCongruential(seed: 11)
        var bursts: [(center: Double, width: Double, amplitude: Double)] = []
        var u = 0.02
        while u < 0.97 {
            if u > 0.45 && u < 0.55 {
                u = 0.55
                continue
            }
            let width = 0.008 + random.next() * 0.02
            bursts.append((u, width, pow(10, (-5 - random.next() * 18) / 20)))
            u += width * 1.6 + random.next() * 0.03
        }
        func envelope(_ u: Double) -> Double {
            var sum = 0.0012
            for burst in bursts {
                let d = (u - burst.center) / burst.width
                if d > -4 && d < 4 { sum += burst.amplitude * exp(-d * d) }
            }
            return min(1, sum)
        }
        func shape(_ f: Double, _ u: Double) -> Double {
            var s = 0.0
            if f > 400 { s -= 7 * log2(f / 400) }
            if f < 150 { s -= 14 * log2(150 / f) }
            let f1 = 520 + 260 * sin(u * 30)
            let f2 = 1600 + 500 * cos(u * 23)
            return s + 10 * exp(-pow(log2(f / f1) / 0.35, 2)) + 7 * exp(-pow(log2(f / f2) / 0.4, 2))
        }

        random = LinearCongruential(seed: 5)
        var levels = [UInt8](repeating: 0, count: columns * rows)
        for column in 0..<columns {
            let u = (Double(column) + 0.5) / Double(columns)
            let db = 20 * log10(max(envelope(u), 1e-6))
            for row in 0..<rows {
                let f = 20 * pow(2, (Double(row) + 0.5) / Double(rows) * 10)
                let level = max(-95 + random.next() * 7, db - 26 + shape(f, u) + (random.next() - 0.5) * 6)
                levels[column * rows + row] = UInt8(min(max((level + 100) / 100, 0), 1) * 255)
            }
        }
        return levels
    }()

    static func image(colormap: SpectrogramColormap, accent: Color.Resolved) -> CGImage? {
        let lut = colormap.lookupTable(accent: accent)
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        for column in 0..<columns {
            for row in 0..<rows {
                let color = lut[Int(levels[column * rows + row])]
                let offset = ((rows - 1 - row) * columns + column) * 4
                pixels[offset] = color.red
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.blue
                pixels[offset + 3] = color.alpha
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(width: columns, height: rows, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: columns * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// 見本を毎回同じにするための簡単な乱数（0..<1）。
private struct LinearCongruential {
    var state: UInt32

    init(seed: UInt32) { state = seed }

    mutating func next() -> Double {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / 4_294_967_296
    }
}

#Preview {
    SettingsView()
        .environment(MonitorModel())
        .frame(height: 720)
}
