import SwiftUI

/// 表示メニューの「計測を停止 / 計測を開始」（⌘.）。macOS ではカード表示中はメニューバーが出ないため、カードのボタンから操作する。
/// iPad ではメニューバーとキーボードショートカットの一覧に出る。
struct CaptureCommands: Commands {
    let model: MonitorModel

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(model.isCaptureStopped ? "計測を開始" : "計測を停止") {
                model.togglePause()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(model.permission == .denied)
        }
    }
}
