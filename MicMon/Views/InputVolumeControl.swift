import SwiftUI

/// 選択中デバイスのシステム入力音量。
struct InputVolumeControl: View {
    /// カード表示用（ラベル・割合・説明文を省き、小さいスライダーにする）。
    var compact = false

    @Environment(MonitorModel.self) private var model

    var body: some View {
        if compact {
            HStack(spacing: 6) {
                muteButton(size: 13)
                slider
            }
            .controlSize(.mini)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("入力音量")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                    muteButton(size: 16)
                        .frame(width: 28, height: 28)
                    slider
                    Text(percentText)
                        .font(.system(size: 12).monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
                if model.activeDevice != nil, !model.inputVolume.isSettable {
                    Text(model.inputVolume.volume == nil ? "このデバイスには入力音量がありません"
                                                         : "このデバイスの入力音量は変更できません")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 52 + 10 + 28 + 10)
                }
            }
        }
    }

    private var percentText: String {
        guard let volume = model.inputVolume.volume else { return "—" }
        return "\(Int((volume * 100).rounded()))%"
    }

    private func muteButton(size: CGFloat) -> some View {
        let muted = model.inputVolume.isMuteActive
        return Button {
            model.inputVolume.toggleMute()
        } label: {
            Image(systemName: muted ? "mic.slash" : "mic")
                .font(.system(size: size))
                .foregroundStyle(muted ? Color.danger : Color.primary.opacity(0.85))
                .frame(width: size + 4)
        }
        .buttonStyle(.borderless)
        .disabled(!model.inputVolume.isSettable)
        .help(muted ? "ミュートを解除して元の音量に戻す" : "ミュートする")
        .accessibilityLabel(muted ? "ミュート解除" : "ミュート")
    }

    private var slider: some View {
        @Bindable var model = model
        // 無段階。目盛り（0%, 17%, 33%, 50%, 67%, 83%, 100%）の近くでは吸着する
        return Slider(value: $model.inputVolumeValue, in: 0...1) {
            Text("入力音量")
        } ticks: {
            SliderTickContentForEach(MonitorModel.inputVolumeTicks, id: \.self) { value in
                SliderTick(value)
            }
        } onEditingChanged: { isEditing in
            model.inputVolume.editingChanged(isEditing)
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .disabled(!model.inputVolume.isSettable)
    }
}
