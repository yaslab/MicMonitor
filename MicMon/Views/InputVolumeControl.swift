import SwiftUI

/// 選択中デバイスのシステム入力音量。
struct InputVolumeControl: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let volume = model.inputVolume.volume
        HStack(spacing: 8) {
            Text("入力音量")
            Image(systemName: "mic")
                .foregroundStyle(.secondary)
            // 無段階。目盛り（0%, 17%, 33%, 50%, 67%, 83%, 100%）の近くでは吸着する
            Slider(value: $model.inputVolumeValue, in: 0...1) {
                Text("入力音量")
            } ticks: {
                SliderTickContentForEach(MonitorModel.inputVolumeTicks, id: \.self) { value in
                    SliderTick(value)
                }
            }
            .labelsHidden()
                .frame(maxWidth: 260)
                .disabled(!model.inputVolume.isSettable)
            if model.activeDevice != nil, !model.inputVolume.isSettable {
                Text(volume == nil ? "このデバイスには入力音量がありません" : "このデバイスの入力音量は変更できません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
