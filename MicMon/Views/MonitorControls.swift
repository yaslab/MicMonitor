import SwiftUI

/// モニター再生（入力をヘッドホンに流す）のスイッチと音量。ウィンドウ表示の最下段に置く。
struct MonitorControls: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let available = model.canMonitor && !model.isPaused
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Toggle("モニター再生", isOn: $model.monitorEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text("モニター再生")
                    .font(.system(size: 13))
                    .frame(width: 96, alignment: .leading)
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Slider(value: $model.monitorVolume, in: 0...1) {
                    Text("モニター再生の音量")
                }
                .labelsHidden()
                .disabled(!model.monitorEnabled)
                Text("\(Int((model.monitorVolume * 100).rounded()))%")
                    .font(.system(size: 12).monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
                    .opacity(model.monitorEnabled ? 1 : 0.45)
            }
            .disabled(!available)

            caption
                .font(.system(size: 12))
                // スイッチの幅ぶん下げて、「モニター再生」の文字の左端にそろえる
                .padding(.leading, 46)
        }
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.panelBorder)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var caption: some View {
        if let monitorError = model.monitorErrorMessage {
            Label(monitorError, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.danger)
        } else {
            Label(captionText, systemImage: "headphones")
                .foregroundStyle(.secondary)
        }
    }

    private var captionText: String {
        if model.isPaused {
            return "計測を停止しているため、モニター再生も止まっています"
        }
        if let format = model.activeFormat, !model.canMonitor {
            return "\(format.channelCount) ch の入力はモニター再生に対応していません（\(AudioCaptureEngine.maxMonitorChannels) ch まで）"
        }
        return "ハウリングを防ぐため、ヘッドホンで聴いてください · 出力: システム既定"
    }
}
