import SwiftUI

/// 画面の最前面に常駐する小さなカード。メーター・波形・入力音量を表示する。
/// どこを掴んでもドラッグで移動でき、離したときに画面端の近くなら吸着する。
struct CardView: View {
    @Environment(MonitorModel.self) private var model
    @Environment(DisplayModeController.self) private var display

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: model.inputVolume.isMuted ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(.secondary)
                Text(model.activeDevice?.name ?? "入力デバイスなし")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
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

            LiveMonitorView(compact: true, isActive: display.mode == .card)
            InputVolumeControl(compact: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
