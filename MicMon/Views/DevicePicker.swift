import SwiftUI

struct DevicePicker: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 4) {
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
            .frame(maxWidth: 480)

            HStack(spacing: 8) {
                if model.isUsingFallback {
                    Text("選択したデバイスが未接続のため、システム既定を使用しています。")
                }
                if let format = model.activeFormat {
                    Text(Self.describe(format))
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private static func describe(_ format: CaptureFormat) -> String {
        let kHz = format.sampleRate / 1000
        let rate = kHz.rounded() == kHz ? String(format: "%.0f", kHz) : String(format: "%.1f", kHz)
        return "\(rate) kHz · \(format.channelCount) ch"
    }
}
