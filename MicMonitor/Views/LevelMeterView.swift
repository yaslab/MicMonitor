import SwiftUI

struct LevelMeterSection: View {
    let readings: [MeterReading]
    /// カード表示用: バー 7pt・文字 9pt にし、チャンネル番号・CLIP・dB 目盛りを省く。
    let compact: Bool
    let onResetClip: () -> Void

    @Environment(\.monitorMetrics) private var metrics
    /// 軸やチャンネル番号の列の幅に掛ける Dynamic Type の倍率（macOS では常に 1）。
    @ScaledMetric(relativeTo: .caption2) private var scale: CGFloat = 1

    var body: some View {
        if compact {
            VStack(spacing: 4) {
                ForEach(readings.indices, id: \.self) { index in
                    let reading = readings[index]
                    HStack(spacing: 6) {
                        MeterBar(reading: reading, track: .cardTrack, cornerRadius: 2)
                            .frame(height: 7)
                        // 数字はピークホールド（直近のピークを 1.5 秒保持してから下げる）。クリップ中は赤にする
                        Text(Decibel.format(reading.holdDB))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(reading.clipped ? Color.danger : Color.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        } else {
            let gutter = metrics.gutterWidth * scale
            let clipWidth = metrics.clipWidth * scale
            let valueWidth = metrics.valueWidth * scale
            VStack(alignment: .leading, spacing: 6) {
                ForEach(readings.indices, id: \.self) { index in
                    let reading = readings[index]
                    HStack(spacing: metrics.gutterSpacing) {
                        Text(ChannelLabel.label(index: index, count: readings.count))
                            .font(AppFont.channelLabel)
                            .foregroundStyle(.secondary)
                            .frame(width: gutter, alignment: .leading)
                            .axisTypeSize()
                        MeterBar(reading: reading, track: .meterTrack, cornerRadius: metrics.meterBarHeight / 4)
                            .frame(height: metrics.meterBarHeight)
                        ClipIndicator(isOn: reading.clipped, onReset: onResetClip)
                            .frame(width: clipWidth, height: metrics.clipHeight * scale)
                            .axisTypeSize()
                        // 数字はピークホールド（直近のピークを 1.5 秒保持してから下げる）
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(Decibel.format(reading.holdDB))
                                .font(AppFont.meterValue)
                            Text(" dB")
                                .font(AppFont.meterUnit)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .frame(width: valueWidth, alignment: .trailing)
                        .axisTypeSize()
                    }
                    .frame(minHeight: metrics.meterRowHeight)
                }
                HStack(spacing: metrics.gutterSpacing) {
                    Color.clear.frame(width: gutter, height: 1)
                    MeterScale()
                    Color.clear.frame(width: clipWidth + metrics.gutterSpacing + valueWidth, height: 1)
                }
            }
        }
    }
}

/// メーターの横の「CLIP」。クリップすると赤く点灯し、1.5 秒で自動的に消える。クリックですぐに消せる。
private struct ClipIndicator: View {
    let isOn: Bool
    let onReset: () -> Void

    /// 点灯時の背景（ダーク・ライト共通）。
    private static let litBackground = Color(.sRGB, red: 0xD7 / 255, green: 0, blue: 0x15 / 255)

    var body: some View {
        Text("CLIP")
            .font(AppFont.clip)
            .kerning(0.6)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isOn ? Color.white : Color.clipOffText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isOn ? Self.litBackground : Color.meterTrack, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture(perform: onReset)
            .help("クリップ表示（1.5 秒で自動的に消える。クリックですぐに消す）")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isOn ? "クリップ" : "クリップなし")
            .accessibilityHint("クリップ表示を消します")
    }
}

struct MeterBar: View {
    let reading: MeterReading
    let track: Color
    let cornerRadius: CGFloat

    private static let segments: [(lower: Float, upper: Float, color: Color)] = [
        (Decibel.floor, -18, .green),
        (-18, -6, .yellow),
        (-6, 0, .red),
    ]

    var body: some View {
        Canvas { context, size in
            func x(_ db: Float) -> CGFloat { CGFloat(Decibel.normalized(db)) * size.width }

            let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius)
            context.fill(shape, with: .color(track))
            context.clip(to: shape)

            // Peak（淡色）の上に RMS（濃色）を重ねる
            for (value, opacity) in [(reading.peakDB, 0.38), (reading.rmsDB, 1.0)] {
                for segment in Self.segments where value > segment.lower {
                    let x0 = x(segment.lower)
                    let x1 = x(min(value, segment.upper))
                    context.fill(Path(CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)),
                                 with: .color(segment.color.opacity(opacity)))
                }
            }

            if reading.holdDB > Decibel.floor {
                let color = Self.segments.last { reading.holdDB > $0.lower }?.color ?? .green
                let holdX = min(max(x(reading.holdDB) - 1, 0), size.width - 2)
                context.fill(Path(CGRect(x: holdX, y: 0, width: 2, height: size.height)), with: .color(color))
            }
        }
    }
}

/// メーターの dB 目盛り。幅が足りなければ間引く（両端は残す）。
struct MeterScale: View {
    private static let ticks: [Float] = [-60, -48, -36, -24, -18, -12, -6, -3, 0]

    /// 軸やチャンネル番号の列の幅に掛ける Dynamic Type の倍率（macOS では常に 1）。
    @ScaledMetric(relativeTo: .caption2) private var scale: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let ticks = Self.ticks.map {
                AxisLabels.Tick(x: CGFloat(Decibel.normalized($0)) * size.width, text: String(format: "%.0f", $0))
            }
            AxisLabels.drawHorizontal(ticks, in: context, size: size)
        }
        .frame(height: 14 * scale)
        .axisTypeSize()
        .accessibilityHidden(true)
    }
}
