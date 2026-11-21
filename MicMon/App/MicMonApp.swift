import AppKit
import SwiftUI

@main
struct MicMonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = MonitorModel()

    var body: some Scene {
        Window("MicMon", id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 760, height: 520)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
