import SwiftUI

/// iOS・iPadOS・visionOS: 画面は 1 つ（`MonitorScreen`）。設定はシートで開く。Mac のカード表示はない。
/// 計測の停止・再開（⌘.）は iPad のメニューバーとキーボードショートカットの一覧に出す。
@main
struct MicMonitorApp: App {
    @State private var model = MonitorModel()

    var body: some Scene {
        WindowGroup {
            MonitorScreen()
                .environment(model)
        }
        .commands {
            CaptureCommands(model: model)
        }
    }
}
