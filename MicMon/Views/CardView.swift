import SwiftUI

/// 画面の最前面に常駐する小さなカード。メーター・波形（切り替え可）・スペクトル・入力音量を表示する。
/// どこを掴んでもドラッグで移動でき、離したときに画面端の近くなら吸着する。
struct CardView: View {
    @Environment(MonitorModel.self) private var model
    @Environment(DisplayModeController.self) private var display
    @AppStorage("cardShowsWaveform") private var showsWaveform = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(model.activeDevice?.name ?? "入力デバイスなし")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button {
                    showsWaveform.toggle()
                } label: {
                    Image(systemName: "waveform")
                        .foregroundStyle(showsWaveform ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(showsWaveform ? "波形を隠す" : "波形を表示する")
                .accessibilityLabel(showsWaveform ? "波形を隠す" : "波形を表示する")
                Button {
                    display.showWindow()
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.borderless)
                .help("ウィンドウ表示に戻す（⌘⇧M）")
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            LiveMonitorView(compact: true, showsWaveform: showsWaveform, isActive: display.mode == .card)
            InputVolumeControl(compact: true)
        }
        .padding(12)
        .frame(minWidth: DisplayModeController.cardMinimumWidth, maxWidth: .infinity, alignment: .topLeading)
        // 高さは中身に合わせる（パネルの高さもこれに固定され、幅だけ変えられる）
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        // スライダーやボタンは自分のジェスチャーが優先されるので、それ以外の場所を掴むと移動する
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { _ in display.cardDragChanged() }
                .onEnded { _ in display.cardDragEnded() }
        )
        .task { await model.start() }
    }
}
