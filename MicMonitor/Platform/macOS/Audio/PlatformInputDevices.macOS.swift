import CoreAudio
import os

typealias AudioDeviceHandle = AudioDeviceID

/// macOS: Core Audio HAL から入力デバイスの一覧とシステム既定の入力デバイスを取得する。
@MainActor
final class PlatformInputDevices: InputDeviceSource {
    private static let logger = Logger(subsystem: "MicMonitor", category: "Devices")

    func inputDevices() -> [AudioInputDevice] {
        CoreAudioHAL.deviceIDs().compactMap { id -> AudioInputDevice? in
            let channels = CoreAudioHAL.inputChannelCount(id)
            guard channels > 0, let uid = CoreAudioHAL.string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = CoreAudioHAL.string(id, kAudioObjectPropertyName) ?? uid
            // AVAudioEngine が既定の入出力を束ねるために自動で作る集約デバイスは出さない
            if CoreAudioHAL.isPrivateAggregate(id) {
                Self.logger.debug("Excluded private aggregate device: \(name, privacy: .public)")
                return nil
            }
            return AudioInputDevice(id: id, uid: uid, name: name, inputChannelCount: channels)
        }
    }

    func defaultInputDeviceID(in devices: [AudioInputDevice]) -> AudioDeviceHandle? {
        CoreAudioHAL.defaultInputDeviceID()
    }

    func observeChanges(_ handler: @escaping @MainActor @Sendable () -> Void) {
        CoreAudioHAL.addSystemListener(kAudioHardwarePropertyDevices, handler: handler)
        CoreAudioHAL.addSystemListener(kAudioHardwarePropertyDefaultInputDevice, handler: handler)
    }
}
