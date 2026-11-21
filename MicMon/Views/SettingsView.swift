import SwiftUI

struct SettingsView: View {
    @Environment(MonitorModel.self) private var model

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
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }
}
