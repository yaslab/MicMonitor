import CoreAudio
import Observation
import os

/// 入力デバイスのシステム入力音量（システム設定 > サウンド > 入力 と同じ値）を読み書きする。
@MainActor
@Observable
final class InputVolumeController {
    /// 0...1。デバイスが入力音量を持たないときは nil。
    private(set) var volume: Float?
    /// アプリから変更できるか。
    private(set) var isSettable = false

    @ObservationIgnored private var deviceID: AudioDeviceID?
    @ObservationIgnored private var elements: [AudioObjectPropertyElement] = []
    @ObservationIgnored private var listeners: [CoreAudioHAL.PropertyListener] = []

    private static let logger = Logger(subsystem: "MicMon", category: "InputVolume")

    /// 対象デバイスを切り替える。同じデバイスなら何もしない。
    func attach(to deviceID: AudioDeviceID?) {
        guard deviceID != self.deviceID else { return }
        detach()
        self.deviceID = deviceID
        guard let deviceID else { return }

        elements = CoreAudioHAL.inputVolumeElements(deviceID)
        isSettable = !elements.isEmpty && elements.allSatisfy {
            CoreAudioHAL.isInputVolumeSettable(deviceID, element: $0)
        }
        listeners = elements.compactMap { element in
            CoreAudioHAL.addListener(deviceID, address: CoreAudioHAL.inputVolumeAddress(element: element)) { [weak self] in
                self?.refresh()
            }
        }
        refresh()
        Self.logger.info("Device \(deviceID): volume elements \(self.elements, privacy: .public), settable \(self.isSettable)")
    }

    /// 全要素に同じ値を設定する（チャンネルごとの音量しかないデバイスでも一括で変える）。
    func setVolume(_ newValue: Float) {
        guard let deviceID, isSettable else { return }
        let value = min(max(newValue, 0), 1)
        let succeeded = elements.map { CoreAudioHAL.setInputVolume(deviceID, element: $0, value) }
        if succeeded.contains(false) {
            Self.logger.error("Failed to set input volume on device \(deviceID)")
        }
        volume = value
    }

    private func detach() {
        listeners.forEach(CoreAudioHAL.removeListener)
        listeners = []
        elements = []
        deviceID = nil
        volume = nil
        isSettable = false
    }

    /// 外部（システム設定や他のアプリ）での変更を反映する。チャンネルごとの場合は平均を表示する。
    private func refresh() {
        guard let deviceID else { return }
        let values = elements.compactMap { CoreAudioHAL.inputVolume(deviceID, element: $0) }
        let newVolume = values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
        if newVolume != volume { volume = newVolume }
    }
}
