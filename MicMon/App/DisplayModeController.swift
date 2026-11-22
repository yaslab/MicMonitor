import AppKit
import Observation
import SwiftUI

enum DisplayMode: String {
    /// 通常のウィンドウ。
    case window
    /// 画面の最前面に常駐する小さなカード。
    case card
}

/// ウィンドウ表示とカード表示を切り替える。
///
/// メインウィンドウ（SwiftUI の `Window` シーン）は閉じずに隠す（`orderOut`）。
/// 閉じると最後のウィンドウを閉じたとみなされてアプリが終了するため。
/// カードは AppKit の `NSPanel` に SwiftUI のビューを載せる（最前面・半透明・画面端への吸着のため）。
@MainActor
@Observable
final class DisplayModeController {
    private(set) var mode: DisplayMode

    @ObservationIgnored private let model: MonitorModel
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private weak var mainWindow: NSWindow?
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    @ObservationIgnored private var openMainWindow: (() -> Void)?
    @ObservationIgnored private var openSettingsWindow: (() -> Void)?

    private static let modeKey = "displayMode"
    private static let cardFrameName = "MicMonCard"
    /// 高さは中身に合わせて決まる（ここでの高さは最初の仮の値）。
    static let cardDefaultSize = NSSize(width: 300, height: 100)
    static let cardMinimumWidth: CGFloat = 220
    /// 画面端からこの距離以内で離したら吸着する。
    private static let snapThreshold: CGFloat = 24
    /// 吸着したときの画面端との余白。
    private static let snapMargin: CGFloat = 8

    init(model: MonitorModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        mode = DisplayMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .window
        AppDelegate.isCardMode = { [weak self] in self?.mode == .card }
        AppDelegate.onReopen = { [weak self] in self?.showWindow() }
        // 前回カード表示で終了していたら、メインウィンドウを待たずにカードを出す
        AppDelegate.onLaunch = { [weak self] in
            if self?.mode == .card { self?.showCard() }
        }
        // カード表示中に開いた設定ウィンドウを閉じたら、Dock のアイコンをまた隠す
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil,
                                               queue: .main) { [weak self] notification in
            let identifier = (notification.object as? NSWindow)?.identifier?.rawValue
            MainActor.assumeIsolated {
                let isSettings = identifier.map(Self.isSettingsWindow) ?? false
                guard isSettings, let self, self.mode == .card else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// メインウィンドウが表示されたときに呼ぶ。カード表示中なら隠す。
    func registerMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        if mode == .card { showCard() }
    }

    /// メインウィンドウを開く処理（SwiftUI の `openWindow`）。メニューの Commands から渡される。
    func setOpenMainWindow(_ action: @escaping () -> Void) {
        openMainWindow = action
    }

    /// 設定ウィンドウを開く処理（SwiftUI の `openSettings`）。メニューの Commands から渡される。
    func setOpenSettings(_ action: @escaping () -> Void) {
        openSettingsWindow = action
    }

    /// 設定ウィンドウを開く。カードの「…」メニューから呼ぶ。
    ///
    /// カードの `NSHostingView` の中から `openSettings` を呼んでも開かないため、アプリのシーン
    /// （Commands）から受け取った処理を使う。また `.accessory` のままでは設定ウィンドウが前面に
    /// 出ないので、開いている間だけ `.regular` にする（閉じたら `.accessory` に戻す）。
    func showSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openSettingsWindow?()
    }

    func toggle() {
        mode == .window ? showCard() : showWindow()
    }

    func showCard() {
        setMode(.card)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
        mainWindow?.orderOut(nil)
        // カード表示中は Dock と ⌘Tab に出さない（メニューバーも出なくなる）
        NSApp.setActivationPolicy(.accessory)
    }

    func showWindow() {
        setMode(.window)
        // Dock のアイコンとメニューバーを戻す
        NSApp.setActivationPolicy(.regular)
        panel?.orderOut(nil)
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            // まだ作られていない（起動時に復元されなかった）場合は SwiftUI に開かせる
            openMainWindow?()
        }
        NSApp.activate()
    }

    // MARK: - カードの移動と吸着

    /// カードのドラッグ中に呼ぶ。マウスの画面座標の移動量だけカードを動かす。
    func cardDragChanged() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
        guard let start = dragStart else { return }
        panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                     y: start.origin.y + mouse.y - start.mouse.y))
    }

    /// ドラッグを離したときに呼ぶ。画面端の近くなら吸着させる。
    func cardDragEnded() {
        dragStart = nil
        snapCardToScreenEdges()
    }

    private func snapCardToScreenEdges() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        let threshold = Self.snapThreshold
        let margin = Self.snapMargin

        let left = visible.minX + margin
        let right = visible.maxX - margin - frame.width
        let bottom = visible.minY + margin
        let top = visible.maxY - margin - frame.height

        if abs(frame.minX - left) < threshold || frame.minX < left {
            frame.origin.x = left
        } else if abs(frame.minX - right) < threshold || frame.minX > right {
            frame.origin.x = right
        }
        if abs(frame.minY - bottom) < threshold || frame.minY < bottom {
            frame.origin.y = bottom
        } else if abs(frame.minY - top) < threshold || frame.minY > top {
            frame.origin.y = top
        }
        if frame.origin != panel.frame.origin {
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    // MARK: - 内部

    /// SwiftUI の `Settings` シーンのウィンドウか（識別子は `com_apple_SwiftUI_Settings_window`）。
    private static func isSettingsWindow(_ identifier: String) -> Bool {
        identifier.contains("Settings")
    }

    private func setMode(_ newMode: DisplayMode) {
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Self.modeKey)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.cardDefaultSize),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        // 他のアプリを使っている間も表示し続ける。クリックしても前面のアプリを切り替えない
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // 吸着のため移動は自前で行う（標準のドラッグ移動では離した瞬間がわからない）
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false

        // 半透明: 背後の画面をぼかして透かす
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        let hosting = NSHostingView(rootView: CardView().environment(model).environment(self))
        // 中身の最小・最大サイズをパネルに反映する。高さは中身に固定され、幅は最小幅以上で自由に変えられる
        hosting.sizingOptions = [.minSize, .maxSize]
        // サイズ変更・角丸・影のため .titled のままにしているが、タイトルバーは使わない。
        // セーフエリアを無効にしないと、タイトルバーの高さぶん上に余白ができる
        hosting.safeAreaRegions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect

        // 位置とサイズは自動保存する。保存がなければ画面の右上に置く
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - Self.cardDefaultSize.width - 16,
                                         y: visible.maxY - Self.cardDefaultSize.height - 16))
        }
        panel.setFrameUsingName(Self.cardFrameName)
        panel.setFrameAutosaveName(Self.cardFrameName)
        return panel
    }
}
