import SwiftUI

struct LevelMeterSection: View {
    let readings: [MeterReading]
    /// カード表示用: バー 7pt・文字 9pt にし、チャンネル番号・CLIP・dB 目盛りを省く。
    let compact: Bool
    let onResetClip: () -> Void

    private static let clipWidth: CGFloat = 44
    private static let valueWidth: CGFloat = 70

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
            VStack(alignment: .leading, spacing: 6) {
                ForEach(readings.indices, id: \.self) { index in
                    let reading = readings[index]
                    HStack(spacing: MonitorLayout.gutterSpacing) {
                        Text(ChannelLabel.label(index: index, count: readings.count))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: MonitorLayout.gutterWidth, alignment: .leading)
                        MeterBar(reading: reading, track: .meterTrack, cornerRadius: 3)
                            .frame(height: 12)
                        ClipIndicator(isOn: reading.clipped, onReset: onResetClip)
                            .frame(width: Self.clipWidth)
                        // 数字はピークホールド（直近のピークを 1.5 秒保持してから下げる）
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(Decibel.format(reading.holdDB))
                                .font(.system(size: 12, design: .monospaced))
                            Text(" dB")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: Self.valueWidth, alignment: .trailing)
                    }
                    .frame(height: 18)
                }
                HStack(spacing: MonitorLayout.gutterSpacing) {
                    Color.clear.frame(width: MonitorLayout.gutterWidth, height: 1)
                    MeterScale()
                        .frame(height: 14)
                    Color.clear.frame(width: Self.clipWidth + MonitorLayout.gutterSpacing + Self.valueWidth,
                                      height: 1)
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
            .font(.system(size: 10, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(isOn ? Color.white : Color.clipOffText)
            .frame(maxWidth: .infinity)
            .frame(height: 16)
            .background(isOn ? Self.litBackground : Color.meterTrack, in: RoundedRectangle(cornerRadius: 3))
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

struct MeterScale: View {
    private static let ticks: [Float] = [-60, -48, -36, -24, -18, -12, -6, -3, 0]

    var body: some View {
        Canvas { context, size in
            for tick in Self.ticks {
                let x = CGFloat(Decibel.normalized(tick)) * size.width
                let anchor: UnitPoint = tick == Self.ticks.first ? .topLeading
                    : tick == Self.ticks.last ? .topTrailing : .top
                context.draw(Text(String(format: "%.0f", tick)).font(MonitorLayout.axisFont).foregroundStyle(.secondary),
                             at: CGPoint(x: x, y: 0), anchor: anchor)
            }
        }
    }
}
