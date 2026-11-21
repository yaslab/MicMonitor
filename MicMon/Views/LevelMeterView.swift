import SwiftUI

struct LevelMeterSection: View {
    let readings: [MeterReading]
    var showsScale = true
    let onResetClip: () -> Void

    private static let labelWidth: CGFloat = 20
    private static let valueWidth: CGFloat = 64
    private static let clipWidth: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(readings.indices, id: \.self) { index in
                let reading = readings[index]
                HStack(spacing: 8) {
                    Text(ChannelLabel.label(index: index, count: readings.count))
                        .font(.caption.monospaced())
                        .frame(width: Self.labelWidth, alignment: .trailing)
                    MeterBar(reading: reading)
                        .frame(height: 14)
                    Text("\(Decibel.format(reading.peakDB)) dB")
                        .font(.caption.monospacedDigit())
                        .frame(width: Self.valueWidth, alignment: .trailing)
                    Circle()
                        .fill(reading.clipped ? Color.red : Color.secondary.opacity(0.25))
                        .frame(width: 10, height: 10)
                        .frame(width: Self.clipWidth)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onResetClip)
                        .help("クリップ表示（クリックで解除）")
                }
            }
            if showsScale {
                HStack(spacing: 8) {
                    Color.clear.frame(width: Self.labelWidth, height: 1)
                    MeterScale()
                        .frame(height: 12)
                    Color.clear.frame(width: Self.valueWidth + Self.clipWidth + 8, height: 1)
                }
            }
        }
    }
}

struct MeterBar: View {
    let reading: MeterReading

    private static let segments: [(lower: Float, upper: Float, color: Color)] = [
        (Decibel.floor, -18, .green),
        (-18, -6, .yellow),
        (-6, 0, .red),
    ]

    var body: some View {
        Canvas { context, size in
            func x(_ db: Float) -> CGFloat { CGFloat(Decibel.normalized(db)) * size.width }

            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3),
                         with: .color(.secondary.opacity(0.15)))

            // Peak（淡色）の上に RMS（濃色）を重ねる
            for (value, opacity) in [(reading.peakDB, 0.4), (reading.rmsDB, 1.0)] {
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
    private static let ticks: [Float] = [-60, -50, -40, -30, -20, -10, -6, -3, 0]

    var body: some View {
        Canvas { context, size in
            for tick in Self.ticks {
                let x = CGFloat(Decibel.normalized(tick)) * size.width
                let anchor: UnitPoint = tick == Self.ticks.first ? .topLeading
                    : tick == Self.ticks.last ? .topTrailing : .top
                context.draw(Text(String(format: "%.0f", tick)).font(.system(size: 9)).foregroundStyle(.secondary),
                             at: CGPoint(x: x, y: 0), anchor: anchor)
            }
        }
    }
}
