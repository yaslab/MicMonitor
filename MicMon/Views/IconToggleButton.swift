import SwiftUI

/// アイコンだけのボタン。オンの状態（`isHighlighted`）ではアクセントカラー、オフではグレーにする。
struct IconToggleButton: View {
    let systemImage: String
    let isHighlighted: Bool
    /// VoiceOver のラベル。`help` を省くとツールチップにも使う。
    let label: String
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(isHighlighted ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}
