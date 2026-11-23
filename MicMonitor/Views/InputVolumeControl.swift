import SwiftUI

/// 選択中デバイスの入力音量（macOS はシステムの入力音量、iOS はセッションの入力ゲイン）とミュート。
struct InputVolumeControl: View {
    enum Style {
        /// Mac のウィンドウ: 「入力音量」のラベル、マイクボタン、スライダー、割合。変更できない理由を下に出す。
        case window
        /// Mac のカード: ラベル・割合・説明文を省き、小さいスライダーにする。
        case card
        /// iOS: 入力のカードの 1 行。44pt のマイクボタン、スライダー、割合。変更できない理由を下に出す。
        case touch
    }

    var style = Style.window

    @Environment(MonitorModel.self) private var model
    @ScaledMetric(relativeTo: .subheadline) private var percentWidth: CGFloat = 48

    /// カード用（以前の `compact: true`）。
    init(compact: Bool) {
        style = compact ? .card : .window
    }

    init(style: Style = .window) {
        self.style = style
    }

    var body: some View {
        switch style {
        case .card:
            HStack(spacing: 6) {
                muteButton(.system(size: 13), width: 17)
                slider
            }
            .controlSize(.mini)
        case .window:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("入力音量")
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                    muteButton(.system(size: 16), width: 20)
                        .frame(width: 28, height: 28)
                    slider
                    Text(percentText)
                        .font(AppFont.secondary.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
                unavailableReason
                    .padding(.leading, 52 + 10 + 28 + 10)
            }
        case .touch:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    // iOS は Dynamic Type に合わせてアイコンも大きくする
                    muteButton(.title3, width: nil)
                        .frame(minWidth: 44, minHeight: 44)
                    slider
                    Text(percentText)
                        .font(AppFont.secondary.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: percentWidth, alignment: .trailing)
                }
                unavailableReason
                    .padding(.leading, 52)
            }
        }
    }

    @ViewBuilder
    private var unavailableReason: some View {
        if model.activeDevice != nil, !model.inputVolume.isSettable {
            Text(model.inputVolume.volume == nil ? "このデバイスには入力音量がありません"
                                                 : "このデバイスの入力音量は変更できません")
                .font(AppFont.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var percentText: String {
        guard let volume = model.inputVolume.volume else { return "—" }
        return "\(Int((volume * 100).rounded()))%"
    }

    /// `width` を渡すとアイコンの幅をそろえる（Mac のウィンドウとカード）。
    private func muteButton(_ font: Font, width: CGFloat?) -> some View {
        let muted = model.inputVolume.isMuteActive
        return Button {
            model.inputVolume.toggleMute()
        } label: {
            Image(systemName: muted ? "mic.slash" : "mic")
                .font(font)
                .foregroundStyle(muted ? Color.danger : Color.primary.opacity(0.85))
                .frame(width: width)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!model.inputVolume.canToggleMute)
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
