import SwiftUI

/// 選択中デバイスのシステム入力音量。
struct InputVolumeControl: View {
    /// カード表示用（ラベルと説明文を省き、スライダーを幅いっぱいにする）。
    var compact = false

    @Environment(MonitorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let volume = model.inputVolume.volume
        HStack(spacing: 8) {
            if !compact {
                Text("入力音量")
            }
            let muted = model.inputVolume.isMuteActive
            Button {
                model.inputVolume.toggleMute()
            } label: {
                Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(muted ? Color.red : Color.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .disabled(!model.inputVolume.isSettable)
            .help(muted ? "ミュートを解除して元の音量に戻す" : "ミュートする")
            .accessibilityLabel(muted ? "ミュート解除" : "ミュート")
            // 無段階。目盛り（0%, 17%, 33%, 50%, 67%, 83%, 100%）の近くでは吸着する
            Slider(value: $model.inputVolumeValue, in: 0...1) {
                Text("入力音量")
            } ticks: {
                SliderTickContentForEach(MonitorModel.inputVolumeTicks, id: \.self) { value in
                    SliderTick(value)
                }
            } onEditingChanged: { isEditing in
                model.inputVolume.editingChanged(isEditing)
            }
            .labelsHidden()
            .frame(maxWidth: compact ? .infinity : 260)
            .disabled(!model.inputVolume.isSettable)
            if !compact, model.activeDevice != nil, !model.inputVolume.isSettable {
                Text(volume == nil ? "このデバイスには入力音量がありません" : "このデバイスの入力音量は変更できません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
