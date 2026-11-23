import SwiftUI

/// iOS の画面の配置。Size Class で iPhone と iPad の作りを分け、iPad では横幅で列の数を決める
/// （docs/ui/ios のデザイン）。
///
/// | 条件 | 配置 |
/// |------|------|
/// | 高さが compact（iPhone 横） | 2 列・小さいタイトル |
/// | 幅が compact（iPhone 縦、iPad の狭い分割） | 1 列・大きいタイトル |
/// | regular × regular（iPad）で幅 1000pt 以上 | 2 列 |
/// | regular × regular（iPad）で幅 1000pt 未満 | 1 列（グラフを高く） |
///
/// 文字がアクセシビリティサイズのときは、2 列でも 1 列にする（左の列に収まらないため）。
struct ScreenLayout: Equatable {
    enum Kind: Equatable {
        case phone, phoneLandscape, tablet, tabletLandscape
    }

    /// iPad で 2 列にする横幅。
    static let tabletTwoColumnWidth: CGFloat = 1000

    let kind: Kind
    let isAccessibilitySize: Bool

    init(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?, width: CGFloat,
         dynamicTypeSize: DynamicTypeSize) {
        if vertical == .compact {
            kind = .phoneLandscape
        } else if horizontal == .compact {
            kind = .phone
        } else {
            kind = width >= Self.tabletTwoColumnWidth ? .tabletLandscape : .tablet
        }
        isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
    }

    var usesLargeTitle: Bool { kind == .phone }

    /// 2 列のときの左の列（入力とモニター再生の操作）の幅。1 列なら nil。
    var leftColumnWidth: CGFloat? {
        guard !isAccessibilitySize else { return nil }
        switch kind {
        case .phoneLandscape: return 300
        case .tabletLandscape: return 360
        case .phone, .tablet: return nil
        }
    }

    /// 画面の左右の余白（セーフエリアの内側）。
    var horizontalPadding: CGFloat {
        switch kind {
        case .phone, .phoneLandscape: 16
        case .tablet, .tabletLandscape: 24
        }
    }

    var metrics: MonitorMetrics {
        var m = MonitorMetrics()
        // チャンネル番号と目盛りの列は同じ幅にして、波形とスペクトログラムの時間軸をそろえる
        m.gutterWidth = 30
        m.axisWidth = 30
        m.gutterSpacing = 10
        m.panelCornerRadius = 16
        m.panelPadding = EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16)
        m.meterPanelPadding = EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16)
        m.meterBarHeight = 14
        m.clipCapWidth = 6
        m.pausedMeterHeight = 64
        switch kind {
        case .phone:
            m.sectionSpacing = 20
            m.waveformHeight = 64
            m.spectrogramHeight = 120
            m.spectrumHeight = 140
            m.pausedSpectrumHeight = 160
        case .phoneLandscape:
            m.sectionSpacing = 16
            m.waveformHeight = 56
            m.spectrogramHeight = 96
            m.spectrumHeight = 112
            m.pausedSpectrumHeight = 132
        case .tablet:
            m.sectionSpacing = 24
            m.waveformHeight = 72
            m.spectrogramHeight = 150
            m.spectrumHeight = 170
            m.pausedSpectrumHeight = 190
        case .tabletLandscape:
            m.sectionSpacing = 24
            m.waveformHeight = 64
            m.spectrogramHeight = 132
            m.spectrumHeight = 150
            m.pausedSpectrumHeight = 170
        }
        return m
    }
}
