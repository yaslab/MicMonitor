import SwiftUI

/// ウィンドウ表示（iOS では画面）の 1 欄。上に見出し（左に名前、右に説明）、その下に枠付きのパネルを置く。
struct MonitorPanel<Content: View>: View {
    let title: String
    var caption: String?
    /// 見出しの名前の右に警告色で出す注記（停止中の「停止時点のまま表示」など）。
    var note: String?
    /// 中身の余白。nil なら `MonitorMetrics.panelPadding`。
    var padding: EdgeInsets?
    @ViewBuilder var content: Content

    @Environment(\.monitorMetrics) private var metrics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
                #if !os(macOS)
                .padding(.horizontal, 4)
                #endif
            content
                .padding(padding ?? metrics.panelPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: metrics.panelCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.panelCornerRadius)
                        .strokeBorder(Color.panelBorder)
                }
        }
    }
}

private extension MonitorPanel {
    /// 見出し。アクセシビリティサイズの文字では 1 行に収まらないので、名前・注記・説明を縦に並べる。
    @ViewBuilder
    var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                titleText
                if let note { noteText(note) }
                if let caption {
                    Text(caption)
                        .font(AppFont.panelCaption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleText
                    .layoutPriority(1)
                if let note {
                    noteText(note)
                        .layoutPriority(1)
                }
                Spacer(minLength: 8)
                if let caption {
                    Text(caption)
                        .font(AppFont.panelCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    var titleText: some View {
        Text(title)
            .font(AppFont.panelTitle)
            .kerning(0.4)
            .foregroundStyle(.secondary)
    }

    func noteText(_ note: String) -> some View {
        Text(note)
            .font(AppFont.panelNote)
            .foregroundStyle(Color.warning)
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
                .font(AppFont.secondary)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: height)
        }
    }
}

/// 履歴の時間軸の目盛り（左端が `seconds` 秒前、右端が現在）。波形とスペクトログラムで共通に使う。
/// 目盛りは 4〜6 本になるよう、1・2・5・10・15・20・30 秒のうち合う間隔で打つ（幅が足りなければ間引く）。
struct TimeAxis: View {
    let seconds: Int

    /// 軸やチャンネル番号の列の幅に掛ける Dynamic Type の倍率（macOS では常に 1）。
    @ScaledMetric(relativeTo: .caption2) private var scale: CGFloat = 1

    static func step(for seconds: Int) -> Int {
        [1, 2, 5, 10, 15, 20, 30].first { seconds <= $0 * 5 } ?? 30
    }

    var body: some View {
        Canvas { context, size in
            guard seconds > 0 else { return }
            let step = Self.step(for: seconds)
            // 右端（now）から step 秒ごと。左から右の順に並べる
            let ticks = stride(from: 0, through: seconds, by: step).reversed().map { offset in
                AxisLabels.Tick(x: size.width * (1 - CGFloat(offset) / CGFloat(seconds)),
                                text: offset == 0 ? "now" : "-\(offset) s")
            }
            AxisLabels.drawHorizontal(Array(ticks), in: context, size: size)
        }
        .frame(height: 14 * scale)
        .axisTypeSize()
        .accessibilityHidden(true)
    }
}
