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
                    WaveformView(bins: snapshot.channels[index], capacity: snapshot.capacity,
                                 endIndex: snapshot.endIndex)
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

/// 符号付きの波形（上側が正、下側が負、それぞれ dB スケール）。右端が最新。
struct WaveformView: View {
    let bins: [WaveformBin]
    let capacity: Int
    /// 最新のビンの次の通し番号（`WaveformSnapshot.endIndex`）。
    let endIndex: Int

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
            context.clip(to: Path(CGRect(origin: .zero, size: size)))

            // 1 列（1 ピクセル以上）にまとめるビンの数
            let binsPerColumn = max(1, Int((Double(capacity) / Double(size.width)).rounded(.up)))
            let binWidth = size.width / CGFloat(capacity)
            // 通し番号: bins[0] の番号と、左端（x = 0）に当たる番号。履歴が容量に満たない間は左側が空く
            let firstIndex = endIndex - bins.count
            let windowStart = endIndex - capacity

            /// 振幅（線形・0 以上）を中心線からの高さにする。
            func height(_ amplitude: Float) -> CGFloat {
                CGFloat(Decibel.normalized(Decibel.from(amplitude))) * mid
            }

            var peakPath = Path()
            var rmsPath = Path()
            // 列のまとめ方は表示位置ではなく通し番号で固定する。表示位置で区切ると、データが届くたびに
            // 各列に入るビンが入れ替わり、片側だけのビン（5 ms の中で符号が変わらない）が出たり消えたりしてチラつく
            var groupStart = firstIndex / binsPerColumn * binsPerColumn
            while groupStart < endIndex {
                let lower = max(groupStart, firstIndex) - firstIndex
                let upper = min(groupStart + binsPerColumn, endIndex) - firstIndex
                defer { groupStart += binsPerColumn }
                guard lower < upper else { continue }
                var maximum: Float = 0
                var minimum: Float = 0
                var rms: Float = 0
                for i in lower..<upper {
                    maximum = max(maximum, bins[i].max)
                    minimum = min(minimum, bins[i].min)
                    rms = max(rms, bins[i].rms)
                }
                let x = CGFloat(groupStart - windowStart) * binWidth
                let width = CGFloat(binsPerColumn) * binWidth + 0.5
                // 上側は正の最大値、下側は負の最小値の大きさ（それぞれ dB スケール）
                let upperHeight = height(maximum)
                let lowerHeight = height(-minimum)
                peakPath.addRect(CGRect(x: x, y: mid - upperHeight, width: width, height: upperHeight + lowerHeight))
                // RMS は符号を持たないので上下同じ高さ。ただし各側の振れ幅を超えないようにする
                let rmsHeight = height(rms)
                let rmsUpper = min(rmsHeight, upperHeight)
                let rmsLower = min(rmsHeight, lowerHeight)
                rmsPath.addRect(CGRect(x: x, y: mid - rmsUpper, width: width, height: rmsUpper + rmsLower))
            }
            context.fill(peakPath, with: .color(.accentColor.opacity(0.4)))
            context.fill(rmsPath, with: .color(.accentColor))
        }
    }
}
