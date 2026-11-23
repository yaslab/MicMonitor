import SwiftUI
import UIKit

/// iOS の画面。上にナビゲーションバー（計測の停止・再開と設定のボタン）、その下にスクロールする計測の欄を並べる。
/// 配置は `ScreenLayout`（Size Class と横幅）で決める。
struct MonitorScreen: View {
    @Environment(MonitorModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var width: CGFloat = 0
    @State private var showsSettings = false

    var body: some View {
        let layout = ScreenLayout(horizontal: horizontalSizeClass, vertical: verticalSizeClass,
                                  width: width, dynamicTypeSize: dynamicTypeSize)
        NavigationStack {
            content(layout)
                .environment(\.monitorMetrics, layout.metrics)
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("MicMonitor")
                .navigationBarTitleDisplayMode(layout.usesLargeTitle ? .large : .inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        CaptureToggle()
                            .disabled(model.permission == .denied)
                    }
                    #if !os(visionOS)
                    // Liquid Glass で 2 つのボタンを別々の丸にする（visionOS にはない）
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    #endif
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsSettings = true
                        } label: {
                            Label("設定", systemImage: "gearshape")
                        }
                        .keyboardShortcut(",", modifiers: .command)
                    }
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .sheet(isPresented: $showsSettings) {
            SettingsSheet()
                .environment(model)
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // 設定で続けるようにしていなければ、計測を止める
                model.enterBackground()
            case .active:
                if model.permission == .denied {
                    // 設定アプリでマイクを許可して戻ってきたら、計測を始め直す
                    Task { await model.start() }
                } else {
                    // バックグラウンドに入って止めていたら再開する
                    Task { await model.enterForeground() }
                }
            default:
                break
            }
        }
    }

    @ViewBuilder
    private func content(_ layout: ScreenLayout) -> some View {
        if model.permission == .denied {
            PermissionDeniedView(
                message: "入力レベルを表示するには、マイクへのアクセスが必要です。「設定」アプリの「MicMonitor」で「マイク」をオンにしてください。",
                buttonTitle: "設定を開く"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .frame(maxWidth: 560)
            .padding(layout.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                // 背景（.background）に入ると描画を止める。前面にいない間は誰も見ていないため
                LiveMonitorView(isActive: scenePhase != .background, leftColumnWidth: layout.leftColumnWidth) {
                    InputSection()
                } trailing: {
                    MonitorPlaybackSection()
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
    }
}

/// 設定のシート。
private struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("設定")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") { dismiss() }
                    }
                }
        }
    }
}
