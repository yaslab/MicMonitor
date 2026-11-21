import SwiftUI

struct WaveformSection: View {
    let snapshot: WaveformSnapshot
    let seconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(snapshot.channels.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Text(ChannelLabel.label(index: index, count: snapshot.channels.count))
                        .font(.caption.monospaced())
                        .frame(width: 20, alignment: .trailing)
                    WaveformView(bins: snapshot.channels[index], capacity: snapshot.capacity)
                        .frame(minHeight: 40, maxHeight: .infinity)
                }
            }
            HStack {
                Text("-\(seconds)s")
                Spacer()
                if seconds > 1 {
                    Text(String(format: "-%gs", Double(seconds) / 2))
                    Spacer()
                }
                Text("now")
            }
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.leading, 28)
        }
    }
}

/// dB スケールの波形。中心線から上下対称に描き、右端が最新。
struct WaveformView: View {
    let bins: [WaveformBin]
    let capacity: Int

    private static let gridDB: [Float] = [-6, -20, -40]

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4),
                         with: .color(.secondary.opacity(0.08)))

            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: mid))
            grid.addLine(to: CGPoint(x: size.width, y: mid))
            for db in Self.gridDB {
                let offset = CGFloat(Decibel.normalized(db)) * mid
                for y in [mid - offset, mid + offset] {
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            context.stroke(grid, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)

            guard capacity > 0, !bins.isEmpty, size.width >= 1 else { return }

            // 1 列あたり 1 ピクセル以上、ビンが足りなければ 1 ビン 1 列
            let columns = max(1, min(Int(size.width), capacity))
            let columnWidth = size.width / CGFloat(columns)
            // 履歴が容量に満たない間は左側を空ける
            let leadingEmpty = capacity - bins.count

            var peakPath = Path()
            var rmsPath = Path()
            for column in 0..<columns {
                let lower = max(column * capacity / columns - leadingEmpty, 0)
                let upper = min((column + 1) * capacity / columns - leadingEmpty, bins.count)
                guard lower < upper else { continue }
                var peak: Float = 0
                var rms: Float = 0
                for i in lower..<upper {
                    peak = max(peak, bins[i].peak)
                    rms = max(rms, bins[i].rms)
                }
                let x = CGFloat(column) * columnWidth
                let peakHeight = CGFloat(Decibel.normalized(Decibel.from(peak))) * mid
                let rmsHeight = CGFloat(Decibel.normalized(Decibel.from(rms))) * mid
                peakPath.addRect(CGRect(x: x, y: mid - peakHeight, width: columnWidth + 0.5, height: peakHeight * 2))
                rmsPath.addRect(CGRect(x: x, y: mid - rmsHeight, width: columnWidth + 0.5, height: rmsHeight * 2))
            }
            context.fill(peakPath, with: .color(.accentColor.opacity(0.4)))
            context.fill(rmsPath, with: .color(.accentColor))
        }
    }
}
