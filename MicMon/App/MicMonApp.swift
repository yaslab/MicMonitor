import AppKit
import SwiftUI

@main
struct MicMonApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: MonitorModel
    @State private var display: DisplayModeController

    init() {
        let model = MonitorModel()
        _model = State(initialValue: model)
        _display = State(initialValue: DisplayModeController(model: model))
    }

    var body: some Scene {
        Window("MicMon", id: Self.mainWindowID) {
            ContentView()
                .environment(model)
                .environment(display)
        }
        .defaultSize(width: 760, height: 520)
        // カード表示中はこのウィンドウを隠したまま終了するため、状態の復元に任せると次回の起動時に
        // ウィンドウが作られないことがある。常に起動時に作り、カード表示ならすぐ隠す
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)
        .commands {
            DisplayModeCommands(display: display)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// 表示メニューの「カード表示 / ウィンドウ表示に切り替え」（⌘⇧M）。
private struct DisplayModeCommands: Commands {
    let display: DisplayModeController
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // メインウィンドウがまだ作られていないときに、カードから開けるようにする
        let _ = display.setOpenMainWindow { openWindow(id: MicMonApp.mainWindowID) }
        CommandGroup(after: .toolbar) {
            Button(display.mode == .card ? "ウィンドウ表示に切り替え" : "カード表示に切り替え") {
                display.toggle()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `DisplayModeController` が設定する。カード表示中はメインウィンドウを隠しているだけなので終了しない。
    @MainActor static var isCardMode: () -> Bool = { false }
    /// 起動完了時（前回カード表示で終了していればカードを出す）。
    @MainActor static var onLaunch: () -> Void = {}
    /// Dock のアイコンがクリックされたとき（カード表示中ならウィンドウ表示に戻す）。
    @MainActor static var onReopen: () -> Void = {}

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.onLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // メインウィンドウを隠す（orderOut）と、AppKit は最後のウィンドウが閉じられたとみなす
        !Self.isCardMode()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard Self.isCardMode() else { return true }
        Self.onReopen()
        return false
    }
}
