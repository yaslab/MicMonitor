import SwiftUI

/// マイクの使用が許可されていないときの画面。許可は OS の設定でしか変えられないので、そこを開くボタンを出す。
/// 文言と開き方はプラットフォームごとに違う（macOS はシステム設定のマイクの欄、iOS は設定アプリのこのアプリの欄）。
struct PermissionDeniedView: View {
    let message: String
    let buttonTitle: String
    let openSettings: () -> Void

    @Environment(\.monitorMetrics) private var metrics
    #if os(macOS)
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64
    #else
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 72
    #endif

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "mic.slash")
                .font(.largeTitle)
                .foregroundStyle(Color.danger)
                .frame(width: iconSize, height: iconSize)
                .background(Color.meterTrack, in: Circle())
                .accessibilityHidden(true)
            Text("マイクへのアクセスが許可されていません")
                #if os(macOS)
                .font(.title2.weight(.semibold))
                #else
                .font(.title3.weight(.semibold))
                #endif
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
            Button(buttonTitle, action: openSettings)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: metrics.panelCornerRadius + 2))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.panelCornerRadius + 2)
                .strokeBorder(Color.panelBorder)
        }
    }
}
