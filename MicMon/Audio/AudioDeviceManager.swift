import CoreAudio
import Observation

/// 入力デバイスの一覧とシステム既定の入力デバイスを保持し、変化を通知する。
@MainActor
@Observable
final class AudioDeviceManager {
    private(set) var inputDevices: [AudioInputDevice] = []
    private(set) var defaultInputDeviceID: AudioDeviceID?

    /// デバイス一覧または既定デバイスが変わったときに呼ばれる。
    @ObservationIgnored var onChange: (() -> Void)?

    var defaultInputDevice: AudioInputDevice? {
        guard let defaultInputDeviceID else { return nil }
        return inputDevices.first { $0.id == defaultInputDeviceID }
    }

    init() {
        refresh()
        let handler: @MainActor @Sendable () -> Void = { [weak self] in self?.handleHardwareChange() }
        CoreAudioHAL.addSystemListener(kAudioHardwarePropertyDevices, handler: handler)
        CoreAudioHAL.addSystemListener(kAudioHardwarePropertyDefaultInputDevice, handler: handler)
    }

    func device(uid: String) -> AudioInputDevice? {
        inputDevices.first { $0.uid == uid }
    }

    func refresh() {
        let devices = CoreAudioHAL.deviceIDs()
            .compactMap { id -> AudioInputDevice? in
                let channels = CoreAudioHAL.inputChannelCount(id)
                guard channels > 0, let uid = CoreAudioHAL.string(id, kAudioDevicePropertyDeviceUID) else { return nil }
                let name = CoreAudioHAL.string(id, kAudioObjectPropertyName) ?? uid
                return AudioInputDevice(id: id, uid: uid, name: name, inputChannelCount: channels)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if devices != inputDevices { inputDevices = devices }

        let defaultID = CoreAudioHAL.defaultInputDeviceID()
        if defaultID != defaultInputDeviceID { defaultInputDeviceID = defaultID }
    }

    private func handleHardwareChange() {
        refresh()
        onChange?()
    }
}
