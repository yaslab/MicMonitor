import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(MonitorModel.self) private var model
    @Environment(DisplayModeController.self) private var display

    var body: some View {
        Group {
            if model.permission == .denied {
                PermissionDeniedView()
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
                    .font(.system(size: 12))
                    .foregroundStyle(Color.danger)
            }

            LiveMonitorView(isActive: display.mode == .window)

            MonitorControls()
        }
    }
}

/// マイクの使用が許可されていないときの画面。許可はシステム設定でしか変えられないので、そこを開くボタンを出す。
private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "mic.slash")
                .font(.system(size: 28))
                .foregroundStyle(Color.danger)
                .frame(width: 64, height: 64)
                .background(Color.meterTrack, in: Circle())
                .accessibilityHidden(true)
            Text("マイクへのアクセスが許可されていません")
                .font(.system(size: 17, weight: .semibold))
            Text("入力レベルを表示するには、マイクへのアクセスが必要です。システム設定の「プライバシーとセキュリティ」›「マイク」で MicMon をオンにしてください。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
            Button("システム設定を開く") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.panelBorder)
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
