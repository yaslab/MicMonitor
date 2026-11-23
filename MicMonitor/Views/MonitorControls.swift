import SwiftUI

/// モニター再生（入力をヘッドホンに流す）のスイッチと音量。ウィンドウ表示の最下段に置く。
struct MonitorControls: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let available = model.canMonitor && !model.isCaptureStopped
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Toggle("モニター再生", isOn: $model.monitorEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text("モニター再生")
                    .font(.body)
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
                    .font(AppFont.secondary.monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
                    .opacity(model.monitorEnabled ? 1 : 0.45)
            }
            .disabled(!available)

            MonitorCaption()
                .font(AppFont.footnote)
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

}

/// モニター再生の操作の下の説明（ヘッドホンの注意、使えない理由、再生のエラー）。
struct MonitorCaption: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        if let monitorError = model.monitorErrorMessage {
            Label(monitorError, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.danger)
        } else {
            Label(captionText, systemImage: "headphones")
                .foregroundStyle(.secondary)
        }
    }

    private var captionText: String {
        if model.isCaptureStopped {
            return "計測を停止しているため、モニター再生も止まっています"
        }
        if let format = model.activeFormat, !model.canMonitor {
            return "\(format.channelCount) ch の入力はモニター再生に対応していません（\(AudioCaptureEngine.maxMonitorChannels) ch まで）"
        }
        #if os(macOS)
        return "ハウリングを防ぐため、ヘッドホンで聴いてください · 出力: システム既定"
        #else
        return "ハウリングを防ぐため、ヘッドホンで聴いてください · 出力: 現在の出力先"
        #endif
    }
}
