import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(MonitorModel.self) private var model
    @State private var ballistics = MeterBallistics()

    var body: some View {
        Group {
            if model.permission == .denied {
                PermissionDeniedView()
            } else {
                monitor
            }
        }
        .frame(minWidth: 560, minHeight: 380)
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    private var monitor: some View {
        VStack(alignment: .leading, spacing: 16) {
            DevicePicker()

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            TimelineView(.animation(paused: !model.isRunning)) { context in
                let readings = ballistics.update(levels: model.levels.read(), now: context.date)
                let snapshot = model.waveform.snapshot()
                VStack(alignment: .leading, spacing: 16) {
                    LevelMeterSection(readings: readings, onResetClip: { model.resetClip() })
                    WaveformSection(snapshot: snapshot, seconds: model.historySeconds)
                }
            }

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
    ContentView()
        .environment(MonitorModel())
}
