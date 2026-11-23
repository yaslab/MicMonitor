import SwiftUI

/// 計測（マイク入力）の停止・再開ボタン。マイクのミュート（`InputVolumeControl`）と区別するため、
/// マイクではなく一時停止・再生のアイコンを使う。止めている間は「計測を開始」を目立つ色（主ボタン）にする。
struct CaptureToggle: View {
    /// カード表示用（アイコンだけ）。
    var compact = false

    @Environment(MonitorModel.self) private var model

    var body: some View {
        let paused = model.isCaptureStopped
        let title = paused ? "計測を開始" : "計測を停止"
        let help = paused ? "マイクからの入力の計測を再開する（⌘.）" : "マイクからの入力の計測を止め、マイクの使用をやめる（⌘.）"
        let systemImage = paused ? "play.fill" : "pause.fill"
        if compact {
            CardIconButton(systemImage: systemImage, style: paused ? .prominent : .filled, label: title, help: help) {
                model.togglePause()
            }
        } else if paused {
            Button {
                model.togglePause()
            } label: {
                label(title, systemImage: systemImage)
            }
            .buttonStyle(.borderedProminent)
            .help(help)
        } else {
            Button {
                model.togglePause()
            } label: {
                label(title, systemImage: systemImage)
            }
            .help(help)
        }
    }

    /// iOS のツールバーでは `Label` がアイコンだけになるため、文字も並べて出す（何のボタンかわかるように）。
    @ViewBuilder
    private func label(_ title: String, systemImage: String) -> some View {
        #if os(macOS)
        Label(title, systemImage: systemImage)
        #else
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .padding(.horizontal, 4)
        #endif
    }
}
