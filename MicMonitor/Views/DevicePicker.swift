import SwiftUI

/// 入力デバイスの選択と、使用中のフォーマット（例: 48 kHz · 2 ch）。
/// 選んだデバイスが未接続でシステム既定で代用している間は、2 行目にその旨を出す。
struct DevicePicker: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("入力")
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
                Picker("入力デバイス", selection: $model.selection) {
                    DeviceOptions()
                }
                .labelsHidden()
                .frame(minWidth: 160, idealWidth: 260, maxWidth: 360, alignment: .leading)
                if let format = model.activeFormat {
                    Text(Self.describe(format))
                        .font(AppFont.secondary.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            if model.isUsingFallback {
                Label(model.fallbackMessage, systemImage: "exclamationmark.triangle")
                    .font(AppFont.secondary)
                    .foregroundStyle(Color.warning)
                    // 「入力」ラベルの幅ぶん下げて、ピッカーの左端にそろえる
                    .padding(.leading, 34)
            }
        }
    }

    /// 例: 48 kHz · 2 ch
    static func describe(_ format: CaptureFormat) -> String {
        let kHz = format.sampleRate / 1000
        let rate = kHz.rounded() == kHz ? String(format: "%.0f", kHz) : String(format: "%.1f", kHz)
        return "\(rate) kHz · \(format.channelCount) ch"
    }
}

/// 入力デバイスの選択肢: 「システム既定」、接続中のデバイス、未接続の選択中デバイス。Mac と iOS で共通。
struct DeviceOptions: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        Text(model.systemDefaultLabel).tag(DeviceSelection.systemDefault)
        Divider()
        ForEach(model.deviceManager.inputDevices) { device in
            Text(device.name).tag(DeviceSelection.device(uid: device.uid))
        }
        if model.isUsingFallback, case .device(let uid) = model.selection {
            Text("\(model.selectedDeviceName ?? uid)（未接続）").tag(model.selection)
        }
    }
}

extension MonitorModel {
    /// 選んだデバイスが未接続でシステム既定で代用しているときの説明。
    var fallbackMessage: String {
        if let name = selectedDeviceName {
            "「\(name)」が接続されていないため、システム既定で継続中（再接続で戻ります）"
        } else {
            "選択したデバイスが接続されていないため、システム既定で継続中（再接続で戻ります）"
        }
    }
}
