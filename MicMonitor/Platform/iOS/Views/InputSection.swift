import SwiftUI

/// iOS: 入力のカード（デバイスの選択とフォーマット、入力音量）と、その下の警告。
struct InputSection: View {
    @Environment(MonitorModel.self) private var model
    @Environment(\.monitorMetrics) private var metrics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 使用中のデバイス名。まだ決まっていなければ選択中のもの。
    private var deviceTitle: String {
        if let name = model.activeDevice?.name { return name }
        if case .device = model.selection, let name = model.selectedDeviceName { return name }
        return "システム既定"
    }

    /// 2 行目: システム既定に追従しているか、とフォーマット（例: システム既定 · 48 kHz · 1 ch）。
    private var deviceDetail: String? {
        let format = model.activeFormat.map(DevicePicker.describe)
        // デバイスがまだ決まっていないとき（1 行目が「システム既定」）は繰り返さない
        let following = model.selection == .systemDefault && model.activeDevice != nil ? "システム既定" : nil
        let parts = [following, format].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                deviceRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(minHeight: 56)

                Divider()
                    .padding(.leading, 16)

                InputVolumeControl(style: .touch)
                    .padding(.leading, 6)
                    .padding(.trailing, 16)
                    .padding(.vertical, 6)
                    .frame(minHeight: 56)
            }
            .background(Color.panel, in: RoundedRectangle(cornerRadius: metrics.panelCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.panelCornerRadius)
                    .strokeBorder(Color.panelBorder)
            }

            if model.isUsingFallback {
                Label(model.fallbackMessage, systemImage: "exclamationmark.triangle")
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.warning)
                    .padding(.horizontal, 16)
            }
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.danger)
                    .padding(.horizontal, 16)
            }
        }
    }

    /// 「入力」とデバイスの選択。アクセシビリティサイズの文字では横に収まらないので縦に並べる。
    @ViewBuilder
    private var deviceRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text("入力")
                deviceMenu
                if let detail = deviceDetail {
                    Text(detail)
                        .font(AppFont.secondary.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LabeledContent {
                VStack(alignment: .trailing, spacing: 2) {
                    deviceMenu
                    if let detail = deviceDetail {
                        Text(detail)
                            .font(AppFont.secondary.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } label: {
                Text("入力")
            }
        }
    }

    // 選択肢の文言（「システム既定（…）」）は長いので、ボタンには使用中のデバイス名だけを出し、
    // システム既定に追従しているかは下の行に出す
    private var deviceMenu: some View {
        @Bindable var model = model
        return Menu {
            Picker("入力デバイス", selection: $model.selection) {
                DeviceOptions()
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text(deviceTitle)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("入力デバイス")
        .accessibilityValue(deviceTitle)
    }
}
