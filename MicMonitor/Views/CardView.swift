import AppKit
import SwiftUI

/// 画面の最前面に常駐する小さなカード。メーター・波形・スペクトル（波形とスペクトルは切り替え可）・入力音量を表示する。
/// スペクトルの欄はクリックでスペクトログラムと切り替わる。
/// どこを掴んでもドラッグで移動でき、離したときに画面端の近くなら吸着する。
struct CardView: View {
    @Environment(MonitorModel.self) private var model
    @Environment(DisplayModeController.self) private var display
    @AppStorage("cardShowsWaveform") private var showsWaveform = true
    @AppStorage("cardShowsSpectrum") private var showsSpectrum = true
    @AppStorage("cardShowsSpectrogram") private var showsSpectrogram = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                CaptureToggle(compact: true)
                Text(model.activeDevice?.name ?? "入力デバイスなし")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 4)
                Spacer(minLength: 4)
                SectionToggle(isOn: $showsWaveform, systemImage: "waveform", name: "波形")
                SectionToggle(isOn: $showsSpectrum, systemImage: "chart.bar", name: "スペクトル")
                Menu {
                    Button("ウィンドウ表示に切り替え") {
                        display.showWindow()
                    }
                    Button("設定…") {
                        display.showSettings()
                    }
                    Divider()
                    Button("終了") {
                        NSApp.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.borderless)
                .frame(width: 24, height: 24)
                .help("その他")
                .accessibilityLabel("その他")
            }
            .frame(height: 24)

            LiveMonitorView(compact: true, showsWaveform: showsWaveform, showsSpectrum: showsSpectrum,
                            cardShowsSpectrogram: $showsSpectrogram, isActive: display.mode == .card) {
                InputVolumeControl(compact: true)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.cardErrorText)
                    .lineLimit(2)
            }
        }
        .padding(EdgeInsets(top: 9, leading: 11, bottom: 11, trailing: 11))
        .frame(minWidth: DisplayModeController.cardMinimumWidth, maxWidth: .infinity, alignment: .topLeading)
        // 高さは中身に合わせる（パネルの高さもこれに固定され、幅だけ変えられる）
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        // スライダーやボタンは自分のジェスチャーが優先されるので、それ以外の場所を掴むと移動する
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { _ in display.cardDragChanged() }
                .onEnded { _ in display.cardDragEnded() }
        )
        .task { await model.start() }
    }
}

/// カードのヘッダーに置く、セクションの表示・非表示を切り替えるボタン。表示中はアクセントカラーにする。
private struct SectionToggle: View {
    @Binding var isOn: Bool
    let systemImage: String
    let name: String

    var body: some View {
        CardIconButton(systemImage: systemImage, style: isOn ? .on : .off,
                       label: isOn ? "\(name)を隠す" : "\(name)を表示する") {
            isOn.toggle()
        }
    }
}

#Preview {
    let model = MonitorModel()
    CardView()
        .environment(model)
        .environment(DisplayModeController(model: model))
        .frame(width: 300)
        .background(.regularMaterial)
}
