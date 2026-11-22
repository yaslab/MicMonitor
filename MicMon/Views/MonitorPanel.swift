import SwiftUI

/// ウィンドウ表示の寸法（docs/design の Main.dc.html）。
enum MonitorLayout {
    /// グラフの左のチャンネル番号・目盛りの列の幅。
    static let gutterWidth: CGFloat = 28
    /// その列とグラフの間隔。
    static let gutterSpacing: CGFloat = 10
    /// 軸の目盛りの文字。
    static let axisFont = Font.system(size: 10).monospacedDigit()
}

/// ウィンドウ表示の 1 欄。上に見出し（左に名前、右に説明）、その下に枠付きのパネルを置く。
struct MonitorPanel<Content: View>: View {
    let title: String
    var caption: String?
    /// 見出しの名前の右に警告色で出す注記（停止中の「停止時点のまま表示」など）。
    var note: String?
    var padding = EdgeInsets(top: 10, leading: 14, bottom: 6, trailing: 14)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(.secondary)
                if let note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.warning)
                }
                Spacer(minLength: 8)
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.panelBorder)
                }
        }
    }
}

/// 計測を止めている間、メーターやスペクトルの代わりに出す表示。
struct PausedNotice: View {
    let compact: Bool
    /// ウィンドウ表示での高さ（メーターとスペクトルで違う）。
    var height: CGFloat = 56

    var body: some View {
        if compact {
            Text("計測を停止中")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(Color.cardPausedBox, in: RoundedRectangle(cornerRadius: 5))
        } else {
            Label("計測を停止中", systemImage: "pause.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
    }
}

/// 履歴の時間軸の目盛り（左端が `seconds` 秒前、右端が現在）。波形とスペクトログラムで共通に使う。
/// 目盛りは 4〜6 本になるよう、1・2・5・10・15・20・30 秒のうち合う間隔で打つ。
struct TimeAxis: View {
    let seconds: Int

    static func step(for seconds: Int) -> Int {
        [1, 2, 5, 10, 15, 20, 30].first { seconds <= $0 * 5 } ?? 30
    }

    var body: some View {
        Canvas { context, size in
            guard seconds > 0 else { return }
            let step = Self.step(for: seconds)
            for offset in stride(from: 0, through: seconds, by: step) {
                let x = size.width * (1 - CGFloat(offset) / CGFloat(seconds))
                let anchor: UnitPoint = offset == 0 ? .topTrailing : offset == seconds ? .topLeading : .top
                let label = offset == 0 ? "now" : "-\(offset) s"
                context.draw(Text(label).font(MonitorLayout.axisFont).foregroundStyle(.secondary),
                             at: CGPoint(x: x, y: 0), anchor: anchor)
            }
        }
        .frame(height: 14)
    }
}
