import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(MonitorModel.self) private var model
    @Environment(DisplayModeController.self) private var display

    var body: some View {
        Group {
            if model.permission == .denied {
                PermissionDeniedView(
                    message: "入力レベルを表示するには、マイクへのアクセスが必要です。システム設定の「プライバシーとセキュリティ」›「マイク」で MicMonitor をオンにしてください。",
                    buttonTitle: "システム設定を開く"
                ) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                monitor
            }
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20))
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity, alignment: .top)
        .background(WindowAccessor { display.registerMainWindow($0) })
        // カード表示中はこのウィンドウを隠すだけなので、ここでは計測を止めない
        .task { await model.start() }
        // システム設定でマイクを許可して戻ってきたら、計測を始め直す
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard model.permission == .denied else { return }
            Task { await model.start() }
        }
    }

    private var monitor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                DevicePicker()
                Spacer(minLength: 0)
                CaptureToggle()
                Button {
                    display.showCard()
                } label: {
                    Label("カード表示", systemImage: "rectangle.inset.topright.filled")
                }
                .help("最前面に常駐する小さなカードに切り替える（⌘⇧M）")
            }
            InputVolumeControl()

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(AppFont.secondary)
                    .foregroundStyle(Color.danger)
            }

            LiveMonitorView(isActive: display.mode == .window)

            MonitorControls()
        }
    }
}

#Preview {
    let model = MonitorModel()
    ContentView()
        .environment(model)
        .environment(DisplayModeController(model: model))
        .frame(width: 760, height: 900)
}
