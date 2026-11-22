import SwiftUI

struct SettingsView: View {
    @Environment(MonitorModel.self) private var model
    @AppStorage(SpectrogramColormap.storageKey) private var colormap = SpectrogramColormap.defaultValue

    var body: some View {
        @Bindable var model = model
        let range = MonitorModel.historyRange
        Form {
            Section("波形") {
                LabeledContent("履歴の長さ") {
                    HStack {
                        Slider(value: $model.historySecondsValue,
                               in: Double(range.lowerBound)...Double(range.upperBound),
                               step: 1)
                        Stepper(value: $model.historySeconds, in: range) {
                            Text("\(model.historySeconds) 秒")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            Section("スペクトログラム") {
                Picker("カラーマップ", selection: $colormap) {
                    ForEach(SpectrogramColormap.allCases) { colormap in
                        Text(colormap.name).tag(colormap)
                    }
                }
                ColormapDescription(colormap: colormap)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }
}

/// 選択中のカラーマップの見本（弱い → 強い）と、色の流れ・特徴。
private struct ColormapDescription: View {
    let colormap: SpectrogramColormap

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.secondary.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(gradient: colormap.gradient, startPoint: .leading, endPoint: .trailing))
                    }
                    .frame(height: 14)
                HStack {
                    Text("弱い")
                    Spacer()
                    Text("強い")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            LabeledContent("色の流れ", value: colormap.flow)
            Text(colormap.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
