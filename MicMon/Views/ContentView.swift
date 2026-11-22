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
        .frame(minWidth: 560, minHeight: 540)
        .background(WindowAccessor { display.registerMainWindow($0) })
        // カード表示中はこのウィンドウを隠すだけなので、ここでは計測を止めない
        .task { await model.start() }
    }

    private var monitor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                DevicePicker()
                Spacer()
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
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            LiveMonitorView(isActive: display.mode == .window)

            Divider()
            MonitorControls()
        }
        .padding()
    }
}

private struct PermissionDeniedView: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("マイクへのアクセスが許可されていません", systemImage: "mic.slash")
        } description: {
            Text("システム設定 > プライバシーとセキュリティ > マイク で MicMon を許可してください。許可後、アプリの再起動が必要な場合があります。")
        } actions: {
            Button("システム設定を開く") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("再試行") {
                Task { await model.start() }
            }
        }
    }
}

#Preview {
    let model = MonitorModel()
    ContentView()
        .environment(model)
        .environment(DisplayModeController(model: model))
}
