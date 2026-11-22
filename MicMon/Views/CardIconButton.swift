import SwiftUI

/// カードのヘッダーに置く 24pt 四方のアイコンボタン。
struct CardIconButton: View {
    enum Style {
        /// 切り替えのオン: アクセントカラーの淡い背景。
        case on
        /// 切り替えのオフ: 背景なし、グレーのアイコン。
        case off
        /// 普段のボタン: 薄い背景。
        case filled
        /// 目立たせるボタン（止めている間の「計測を開始」）: アクセントカラーで塗る。
        case prominent
    }

    let systemImage: String
    let style: Style
    /// VoiceOver のラベル。`help` を省くとツールチップにも使う。
    let label: String
    var help: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: style == .prominent || style == .filled ? 10 : 12, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 24, height: 24)
                .background(background, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? label)
        .accessibilityLabel(label)
    }

    private var foreground: Color {
        switch style {
        case .on: .cardToggleText
        case .off: .secondary
        case .filled: .primary
        case .prominent: .white
        }
    }

    private var background: Color {
        switch style {
        case .on: .accentColor.opacity(colorScheme == .dark ? 0.28 : 0.14)
        case .off: .clear
        case .filled: .cardIconButton
        case .prominent: .accentColor
        }
    }
}
