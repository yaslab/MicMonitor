import Foundation
import Observation

/// 入力デバイスの一覧とシステム既定の入力デバイスを保持し、変化を通知する。
/// OS からの取得は `PlatformInputDevices`（`InputDeviceSource`）が行う。
@MainActor
@Observable
final class AudioDeviceManager {
    private(set) var inputDevices: [AudioInputDevice] = []
    private(set) var defaultInputDeviceID: AudioDeviceHandle?

    /// デバイス一覧または既定デバイスが変わったときに呼ばれる。
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let source = PlatformInputDevices()

    var defaultInputDevice: AudioInputDevice? {
        guard let defaultInputDeviceID else { return nil }
        return inputDevices.first { $0.id == defaultInputDeviceID }
    }

    init() {
        refresh()
        source.observeChanges { [weak self] in self?.handleChange() }
    }

    func device(uid: String) -> AudioInputDevice? {
        inputDevices.first { $0.uid == uid }
    }

    func refresh() {
        let devices = source.inputDevices()
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if devices != inputDevices { inputDevices = devices }

        let defaultID = source.defaultInputDeviceID(in: devices)
        if defaultID != defaultInputDeviceID { defaultInputDeviceID = defaultID }
    }

    private func handleChange() {
        refresh()
        onChange?()
    }
}
