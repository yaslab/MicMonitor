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
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Picker("入力デバイス", selection: $model.selection) {
                    Text(model.systemDefaultLabel).tag(DeviceSelection.systemDefault)
                    Divider()
                    ForEach(model.deviceManager.inputDevices) { device in
                        Text(device.name).tag(DeviceSelection.device(uid: device.uid))
                    }
                    if model.isUsingFallback, case .device(let uid) = model.selection {
                        Text("\(model.selectedDeviceName ?? uid)（未接続）").tag(model.selection)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 160, idealWidth: 260, maxWidth: 360, alignment: .leading)
                if let format = model.activeFormat {
                    Text(Self.describe(format))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            if model.isUsingFallback {
                Label(fallbackMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.warning)
                    // 「入力」ラベルの幅ぶん下げて、ピッカーの左端にそろえる
                    .padding(.leading, 34)
            }
        }
    }

    private var fallbackMessage: String {
        if let name = model.selectedDeviceName {
            "「\(name)」が接続されていないため、システム既定で継続中（再接続で戻ります）"
        } else {
            "選択したデバイスが接続されていないため、システム既定で継続中（再接続で戻ります）"
        }
    }

    private static func describe(_ format: CaptureFormat) -> String {
        let kHz = format.sampleRate / 1000
        let rate = kHz.rounded() == kHz ? String(format: "%.0f", kHz) : String(format: "%.1f", kHz)
        return "\(rate) kHz · \(format.channelCount) ch"
    }
}
