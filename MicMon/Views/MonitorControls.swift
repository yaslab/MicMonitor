import SwiftUI

struct MonitorControls: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                Toggle("モニター再生", isOn: $model.monitorEnabled)
                    .toggleStyle(.switch)
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill")
                    Slider(value: $model.monitorVolume, in: 0...1)
                        .frame(width: 160)
                    Image(systemName: "speaker.wave.3.fill")
                }
                .foregroundStyle(.secondary)
                .disabled(!model.monitorEnabled)
            }
            .disabled(!model.canMonitor)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        if let format = model.activeFormat, !model.canMonitor {
            return "\(format.channelCount) ch の入力はモニター再生に対応していません（\(AudioCaptureEngine.maxMonitorChannels) ch まで）。"
        }
        return "システム既定の出力デバイスで再生します。ハウリングを防ぐため、ヘッドホンを使用してください。"
    }
}
