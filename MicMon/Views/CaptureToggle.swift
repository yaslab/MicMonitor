import SwiftUI

/// 計測（マイク入力）の停止・再開ボタン。マイクのミュート（`InputVolumeControl`）と区別するため、
/// マイクではなく一時停止・再生のアイコンを使う。
struct CaptureToggle: View {
    /// カード表示用（アイコンだけ）。
    var compact = false

    @Environment(MonitorModel.self) private var model

    var body: some View {
        let paused = model.isPaused
        let title = paused ? "計測を開始" : "計測を停止"
        let help = paused ? "マイクからの入力の計測を再開する（⌘.）" : "マイクからの入力の計測を止め、マイクの使用をやめる（⌘.）"
        let systemImage = paused ? "play.fill" : "pause.fill"
        if compact {
            Button {
                model.togglePause()
            } label: {
                Image(systemName: systemImage)
                    .foregroundStyle(paused ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityLabel(title)
        } else {
            Button {
                model.togglePause()
            } label: {
                Label(title, systemImage: systemImage)
            }
            .help(help)
        }
    }
}

/// 計測を止めている間、メーターの代わりに出す表示。
struct PausedNotice: View {
    var compact = false

    var body: some View {
        Label("計測を停止中", systemImage: "pause.circle")
            .font(compact ? .caption : .body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
