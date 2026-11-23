import SwiftUI

struct LevelMeterSection: View {
    let readings: [MeterReading]
    /// カード表示用: バー 7pt・文字 9pt にし、チャンネル番号・クリップ表示・dB 目盛り・ゾーンの区切りを省く。
    let compact: Bool
    let onResetClip: () -> Void

    @Environment(\.monitorMetrics) private var metrics
    /// 軸やチャンネル番号の列の幅に掛ける Dynamic Type の倍率（macOS では常に 1）。
    @ScaledMetric(relativeTo: .caption2) private var scale: CGFloat = 1

    /// ゾーン（緑・黄・赤）の境目の切れ目の幅。メーターと目盛りの上の色の帯で同じにする。
    private static let zoneGap: CGFloat = 2
    /// バーと右端のクリップ表示の間隔。
    private static let clipSpacing: CGFloat = 2

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
            VStack(alignment: .leading, spacing: 6) {
                ForEach(readings.indices, id: \.self) { index in
                    let reading = readings[index]
                    HStack(alignment: .bottom, spacing: metrics.gutterSpacing) {
                        Text(ChannelLabel.label(index: index, count: readings.count))
                            .font(AppFont.channelLabel)
                            .foregroundStyle(.secondary)
                            .frame(width: gutter, height: metrics.meterBarHeight, alignment: .leading)
                            .axisTypeSize()
                        VStack(alignment: .trailing, spacing: 2) {
                            // 右肩の数字はピークホールド（直近のピークを 1.5 秒保持してから下げる）。クリップ中は赤にする
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(Decibel.format(reading.holdDB))
                                    .font(AppFont.meterValue)
                                    .foregroundStyle(reading.clipped ? Color.danger : Color.primary)
                                Text("dB")
                                    .font(AppFont.meterUnit)
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                            .axisTypeSize()
                            HStack(spacing: Self.clipSpacing) {
                                MeterBar(reading: reading, track: .meterTrack,
                                         cornerRadius: metrics.meterBarHeight / 4, zoneGap: Self.zoneGap)
                                ClipIndicator(isOn: reading.clipped, onReset: onResetClip)
                                    .frame(width: metrics.clipCapWidth)
                            }
                            .frame(height: metrics.meterBarHeight)
                        }
                    }
                    .padding(.bottom, 3)
                }
                HStack(spacing: metrics.gutterSpacing) {
                    Color.clear.frame(width: gutter, height: 1)
                    HStack(alignment: .top, spacing: Self.clipSpacing) {
                        VStack(spacing: 3) {
                            ZoneStrip(gap: Self.zoneGap)
                                .frame(height: 3)
                            MeterScale()
                        }
                        Color.clear.frame(width: metrics.clipCapWidth, height: 1)
                    }
                }
            }
        }
    }
}

/// メーターの右端（0 dB の先）の細いクリップ表示。クリップすると赤く点灯し、1.5 秒で自動的に消える。
/// クリックですぐに消せる。小さいので、押せる範囲は周りに広げている。
/// 点灯時、ダークでは周りに同色の光、ライトでは同色の 18% の輪を付ける（docs/ui/README.md）。
private struct ClipIndicator: View {
    let isOn: Bool
    let onReset: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// 押せる範囲を四方に広げる量。iOS は幅 6pt を 44pt にする（HIG の最小のタップ領域）。
    #if os(macOS)
    private static let hitOutset: CGFloat = 8
    #else
    private static let hitOutset: CGFloat = 19
    #endif

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isOn ? Color.clipOn : Color.clipOff)
            .background {
                if isOn && colorScheme == .light {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.clipOn.opacity(0.18))
                        .padding(-2)
                }
            }
            .shadow(color: isOn && colorScheme == .dark ? Color.clipOn.opacity(0.7) : .clear, radius: 3)
            .contentShape(Rectangle().inset(by: -Self.hitOutset))
            .onTapGesture(perform: onReset)
            .help("クリップ表示（1.5 秒で自動的に消える。クリックですぐに消す）")
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isOn ? "クリップ" : "クリップなし")
            .accessibilityHint("クリップ表示を消します")
    }
}

struct MeterBar: View {
    let reading: MeterReading
    let track: Color
    let cornerRadius: CGFloat
    /// 0 より大きければ、ゾーンの境目（-18・-6 dB）にこの幅の切れ目を入れる。
    var zoneGap: CGFloat = 0

    static let segments: [(lower: Float, upper: Float, color: Color)] = [
        (Decibel.floor, -18, .green),
        (-18, -6, .yellow),
        (-6, 0, .red),
    ]

    /// 各ゾーンの範囲。境目は左右に `gap / 2` ずつ空ける（両端は空けない）。
    static func zoneRects(in size: CGSize, gap: CGFloat) -> [(rect: CGRect, color: Color)] {
        segments.indices.map { index in
            let segment = segments[index]
            let x0 = CGFloat(Decibel.normalized(segment.lower)) * size.width + (index == 0 ? 0 : gap / 2)
            let x1 = CGFloat(Decibel.normalized(segment.upper)) * size.width - (index == segments.count - 1 ? 0 : gap / 2)
            return (CGRect(x: x0, y: 0, width: max(x1 - x0, 0), height: size.height), segment.color)
        }
    }

    var body: some View {
        Canvas { context, size in
            func x(_ db: Float) -> CGFloat { CGFloat(Decibel.normalized(db)) * size.width }

            context.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius))
            var zoned = context
            if zoneGap > 0 {
                var path = Path()
                for zone in Self.zoneRects(in: size, gap: zoneGap) { path.addRect(zone.rect) }
                zoned.clip(to: path)
            }
            zoned.fill(Path(CGRect(origin: .zero, size: size)), with: .color(track))

            // Peak（淡色）の上に RMS（濃色）を重ねる
            for (value, opacity) in [(reading.peakDB, 0.38), (reading.rmsDB, 1.0)] {
                for segment in Self.segments where value > segment.lower {
                    let x0 = x(segment.lower)
                    let x1 = x(min(value, segment.upper))
                    zoned.fill(Path(CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)),
                               with: .color(segment.color.opacity(opacity)))
                }
            }

            // ピークホールドの線は切れ目の上にも描く
            if reading.holdDB > Decibel.floor {
                let color = Self.segments.last { reading.holdDB > $0.lower }?.color ?? .green
                let holdX = min(max(x(reading.holdDB) - 1, 0), size.width - 2)
                context.fill(Path(CGRect(x: holdX, y: 0, width: 2, height: size.height)), with: .color(color))
            }
        }
    }
}

/// メーターの目盛りの上の細い色の帯。緑・黄・赤のゾーンの範囲を、メーターが光っていなくても示す。
struct ZoneStrip: View {
    let gap: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            context.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2))
            for zone in MeterBar.zoneRects(in: size, gap: gap) {
                context.fill(Path(zone.rect), with: .color(zone.color))
            }
        }
        .opacity(colorScheme == .dark ? 0.75 : 0.9)
        .accessibilityHidden(true)
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

#Preview("レベル") {
    let readings = [
        MeterReading(rmsDB: -34.5, peakDB: -24.2, holdDB: -20.4, clipped: false),
        MeterReading(rmsDB: -19.8, peakDB: -4.1, holdDB: -0.1, clipped: true),
    ]
    VStack(spacing: 16) {
        LevelMeterSection(readings: readings, compact: false, onResetClip: {})
        LevelMeterSection(readings: readings, compact: true, onResetClip: {})
    }
    .padding()
    .frame(width: 720)
}
