import SwiftUI

/// 画面の文字の役割ごとのフォント。すべて text style なので、iOS では Dynamic Type で大きさが変わる。
/// macOS の text style は大きさが固定（body 13・callout 12・subheadline 11・footnote 10）で、
/// docs/ui の Mac の寸法と同じになるように選んでいる。iOS の寸法は docs/ui/ios のデザイン（標準の Large）に合わせる。
enum AppFont {
    #if os(macOS)
    /// 欄の見出し（「レベル」「波形」など）。Mac 11pt / iOS 13pt。
    static let panelTitle = Font.subheadline.weight(.semibold)
    /// 欄の見出しの右の説明。Mac 11pt / iOS 12pt。
    static let panelCaption = Font.subheadline
    /// 見出しの注記（「停止時点のまま表示」）。Mac 10pt / iOS 12pt。
    static let panelNote = Font.footnote
    /// チャンネル番号。Mac 11pt / iOS 13pt。
    static let channelLabel = Font.subheadline.monospacedDigit()
    /// メーターの数値。Mac 12pt / iOS 15pt。
    static let meterValue = Font.callout.monospaced()
    /// 数値の単位（dB）。Mac 10pt / iOS 12pt。
    static let meterUnit = Font.footnote
    /// 「CLIP」。Mac 10pt / iOS 12pt。
    static let clip = Font.footnote.weight(.bold)
    /// グラフの軸の文字。Mac 10pt / iOS 11pt。
    static let axis = Font.footnote.monospacedDigit()
    /// 項目名やフォーマットなどの補助の文字（「入力」「48 kHz · 2 ch」「62%」）。Mac 12pt / iOS 15pt。
    static let secondary = Font.callout
    /// 補足の説明文（モニター再生の注意など）。Mac 12pt / iOS 13pt。
    static let footnote = Font.callout
    #else
    static let panelTitle = Font.footnote.weight(.semibold)
    static let panelCaption = Font.caption
    static let panelNote = Font.caption
    static let channelLabel = Font.footnote.monospacedDigit()
    static let meterValue = Font.subheadline.monospaced()
    static let meterUnit = Font.caption
    static let clip = Font.caption.weight(.bold)
    static let axis = Font.caption2.monospacedDigit()
    static let secondary = Font.subheadline
    static let footnote = Font.footnote
    #endif
}

/// 計測の各欄の寸法。ウィンドウやレイアウトごとに `.environment(\.monitorMetrics, …)` で渡す。
/// 文字の幅に関わる寸法（`gutterWidth` など）は基準の値で、使う側で Dynamic Type の倍率（`@ScaledMetric`）を掛ける。
struct MonitorMetrics: Equatable {
    /// グラフの左のチャンネル番号の列の幅。
    var gutterWidth: CGFloat = 28
    /// スペクトログラムとスペクトルの左の目盛り（周波数・dB）の列の幅。
    var axisWidth: CGFloat = 28
    /// その列とグラフの間隔。
    var gutterSpacing: CGFloat = 10
    /// 欄と欄の間隔。
    var sectionSpacing: CGFloat = 16
    var panelCornerRadius: CGFloat = 10
    var panelPadding = EdgeInsets(top: 10, leading: 14, bottom: 6, trailing: 14)
    var meterPanelPadding = EdgeInsets(top: 12, leading: 14, bottom: 8, trailing: 14)
    var meterBarHeight: CGFloat = 12
    var meterRowHeight: CGFloat = 18
    var clipWidth: CGFloat = 44
    var clipHeight: CGFloat = 16
    var valueWidth: CGFloat = 70
    /// 波形の 1 段の最小の高さ（余れば伸びる）。
    var waveformHeight: CGFloat = 54
    var spectrogramHeight: CGFloat = 104
    var spectrumHeight: CGFloat = 112
    /// 止めている間の「計測を停止中」の高さ。
    var pausedMeterHeight: CGFloat = 56
    var pausedSpectrumHeight: CGFloat = 130

    /// Mac のウィンドウ（docs/ui の Main.dc.html）。
    static let window = MonitorMetrics()
}

extension EnvironmentValues {
    @Entry var monitorMetrics = MonitorMetrics.window
}

extension View {
    /// グラフの軸の文字が大きくなりすぎないようにする（グラフの領域を残すため）。
    /// `DynamicTypeSize.accessibility1` までで止める。欄ごと（`WaveformSection` など）に付けると、
    /// 欄の中の `@ScaledMetric`（列の幅）も同じ上限で計算される。
    func axisTypeSize() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// 横に並ぶ軸の目盛りの文字を描く。左端と右端の文字はグラフの内側に収め、重なる文字は間引く（両端は残す）。
/// 幅の狭い画面や大きな文字でも読めるようにするため。
enum AxisLabels {
    struct Tick {
        let x: CGFloat
        let text: String
    }

    /// 文字と文字の最小の間隔。
    private static let minimumGap: CGFloat = 4

    /// `ticks` は左から右の順。
    static func drawHorizontal(_ ticks: [Tick], in context: GraphicsContext, size: CGSize) {
        guard !ticks.isEmpty else { return }
        let resolved = ticks.map { tick -> (text: GraphicsContext.ResolvedText, frame: CGRect) in
            let text = context.resolve(Text(tick.text).font(AppFont.axis).foregroundStyle(.secondary))
            let measured = text.measure(in: CGSize(width: CGFloat.infinity, height: size.height))
            return (text, CGRect(x: tick.x, y: 0, width: measured.width, height: measured.height))
        }
        // 目盛りの位置を中心にし、はみ出す端の文字は内側に寄せる
        var frames = resolved.map(\.frame)
        for index in frames.indices {
            let width = frames[index].width
            frames[index].origin.x = min(max(frames[index].minX - width / 2, 0), max(size.width - width, 0))
        }

        for index in visibleIndices(frames) {
            context.draw(resolved[index].text, in: frames[index])
        }
    }

    /// 重ならない範囲で、右端（now・0 dB・20k）から等間隔（1 つおき、2 つおき…）に残す。
    /// 左端の文字は、重ならなければ間隔に関係なく残す。
    private static func visibleIndices(_ frames: [CGRect]) -> [Int] {
        let last = frames.count - 1
        func fits(_ indices: [Int]) -> Bool {
            zip(indices, indices.dropFirst()).allSatisfy { frames[$0].maxX + minimumGap <= frames[$1].minX }
        }
        for step in 1...max(last, 1) {
            var indices = Array(stride(from: last, through: 0, by: -step).reversed())
            guard fits(indices) else { continue }
            if indices.first != 0, fits([0] + indices) {
                indices.insert(0, at: 0)
            }
            return indices
        }
        return [last]
    }
}
