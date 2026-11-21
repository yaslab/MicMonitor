import CoreAudio
import Observation
import os

/// 入力デバイスのシステム入力音量（システム設定 > サウンド > 入力 と同じ値）を読み書きする。
///
/// 入力音量は多くのデバイスでゲイン（例: 内蔵マイクは -12〜+12 dB）で、0 にしても無音にならない。
/// そのため、デバイスがミュートを持つ場合は 0 をミュートとして扱う。
@MainActor
@Observable
final class InputVolumeController {
    /// 0...1。ミュート中は 0。デバイスが入力音量を持たないときは nil。
    private(set) var volume: Float?
    /// アプリから変更できるか。
    private(set) var isSettable = false
    /// ミュート中か（システム設定や他のアプリでのミュートも含む）。
    private(set) var isMuted = false

    @ObservationIgnored private var deviceID: AudioDeviceID?
    @ObservationIgnored private var elements: [AudioObjectPropertyElement] = []
    /// ミュートを変更できる要素。マスターがあればそれだけ。空ならミュートなし（0 は最小ゲイン）。
    @ObservationIgnored private var muteElements: [AudioObjectPropertyElement] = []
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
        if CoreAudioHAL.isInputMuteSettable(deviceID, element: kAudioObjectPropertyElementMain) {
            muteElements = [kAudioObjectPropertyElementMain]
        } else {
            muteElements = elements.filter { CoreAudioHAL.isInputMuteSettable(deviceID, element: $0) }
        }

        let addresses = elements.map { CoreAudioHAL.inputVolumeAddress(element: $0) }
            + muteElements.map { CoreAudioHAL.inputMuteAddress(element: $0) }
        listeners = addresses.compactMap { address in
            CoreAudioHAL.addListener(deviceID, address: address) { [weak self] in
                self?.refresh()
            }
        }
        refresh()
        Self.logger.info("Device \(deviceID): volume elements \(self.elements, privacy: .public), settable \(self.isSettable), mute elements \(self.muteElements, privacy: .public)")
    }

    /// 全要素に同じ値を設定する（チャンネルごとの音量しかないデバイスでも一括で変える）。
    /// 0 のときはミュートし、0 より大きければミュートを解除する（ミュートがあるデバイスのみ）。
    func setVolume(_ newValue: Float) {
        guard let deviceID, isSettable else { return }
        let value = min(max(newValue, 0), 1)
        let mute = value <= 0 && !muteElements.isEmpty

        var succeeded = elements.map { CoreAudioHAL.setInputVolume(deviceID, element: $0, value) }
        if !muteElements.isEmpty, mute != isMuted {
            succeeded += muteElements.map { CoreAudioHAL.setInputMuted(deviceID, element: $0, mute) }
        }
        if succeeded.contains(false) {
            Self.logger.error("Failed to set input volume/mute on device \(deviceID)")
        }
        volume = value
        isMuted = mute
    }

    private func detach() {
        listeners.forEach(CoreAudioHAL.removeListener)
        listeners = []
        elements = []
        muteElements = []
        deviceID = nil
        volume = nil
        isSettable = false
        isMuted = false
    }

    /// 外部（システム設定や他のアプリ）での変更を反映する。チャンネルごとの場合は平均を表示する。
    private func refresh() {
        guard let deviceID else { return }
        let muted = muteElements.contains { CoreAudioHAL.isInputMuted(deviceID, element: $0) == true }
        let values = elements.compactMap { CoreAudioHAL.inputVolume(deviceID, element: $0) }
        let newVolume: Float? = values.isEmpty ? nil : (muted ? 0 : values.reduce(0, +) / Float(values.count))
        if newVolume != volume { volume = newVolume }
        if muted != isMuted { isMuted = muted }
        #if DEBUG
        Self.logger.debug("Input volume: \(self.debugState, privacy: .public)")
        #endif
    }

    #if DEBUG
    /// 計測用: 各要素の scalar・dB・dB の範囲と、ミュートの状態。
    var debugState: String {
        guard let deviceID else { return "no device" }
        let volumes = elements.map { element in
            let scalar = CoreAudioHAL.inputVolume(deviceID, element: element).map { String(format: "%.3f", $0) } ?? "-"
            let db = CoreAudioHAL.inputVolumeDecibels(deviceID, element: element).map { String(format: "%.1f dB", $0) } ?? "-"
            let range = CoreAudioHAL.inputVolumeDecibelRange(deviceID, element: element)
                .map { String(format: "%.1f...%.1f dB", $0.lowerBound, $0.upperBound) } ?? "-"
            return "element \(element): scalar \(scalar), \(db), range \(range)"
        }
        let mutes = muteElements.map { element in
            "mute[\(element)] \(CoreAudioHAL.isInputMuted(deviceID, element: element).map(String.init(describing:)) ?? "-")"
        }
        return (volumes + (mutes.isEmpty ? ["mute none"] : mutes)).joined(separator: "; ")
    }
    #endif
}
