import SwiftUI

/// iOS: モニター再生（入力をヘッドホンに流す）のカード。スイッチの行と音量の行、その下に注意やエラー。
struct MonitorPlaybackSection: View {
    @Environment(MonitorModel.self) private var model
    @Environment(\.monitorMetrics) private var metrics
    @ScaledMetric(relativeTo: .subheadline) private var percentWidth: CGFloat = 48

    var body: some View {
        @Bindable var model = model
        let available = model.canMonitor && !model.isCaptureStopped
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                Toggle("モニター再生", isOn: $model.monitorEnabled)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)

                Divider()
                    .padding(.leading, 16)

                HStack(spacing: 12) {
                    Image(systemName: "speaker.wave.2")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Slider(value: $model.monitorVolume, in: 0...1) {
                        Text("モニター再生の音量")
                    }
                    .labelsHidden()
                    Text("\(Int((model.monitorVolume * 100).rounded()))%")
                        .font(AppFont.secondary.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: percentWidth, alignment: .trailing)
                }
                .disabled(!model.monitorEnabled)
                .opacity(model.monitorEnabled ? 1 : 0.45)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
            }
            .disabled(!available)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: metrics.panelCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.panelCornerRadius)
                    .strokeBorder(Color.panelBorder)
            }

            MonitorCaption()
                .font(AppFont.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
    }
}
