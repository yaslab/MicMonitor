import CoreAudio
import os

/// macOS: Core Audio HAL の入力スコープの音量（`kAudioDevicePropertyVolumeScalar`）とミュート
/// （`kAudioDevicePropertyMute`）。システム全体の設定（システム設定 > サウンド > 入力 と同じ値）で、
/// アプリを終了しても値は残る。
///
/// 要素 0（マスター）があればそれを使い、なければ音量を持つチャンネル（要素 1...n）すべてに同じ値を設定する。
@MainActor
final class PlatformInputVolume: InputVolumeBackend {
    private let deviceID: AudioDeviceID
    private let elements: [AudioObjectPropertyElement]
    /// ミュートを変更できる要素。マスターがあればそれだけ。空ならミュートなし（0 は最小ゲイン）。
    private let muteElements: [AudioObjectPropertyElement]
    private var listeners: [CoreAudioHAL.PropertyListener] = []

    let isVolumeSettable: Bool
    var hasMute: Bool { !muteElements.isEmpty }

    private static let logger = Logger(subsystem: "MicMonitor", category: "InputVolume")

    init(device: AudioInputDevice, onChange: @escaping @MainActor @Sendable () -> Void) {
        let deviceID = device.id
        let elements = CoreAudioHAL.inputVolumeElements(deviceID)
        let muteElements = if CoreAudioHAL.isInputMuteSettable(deviceID, element: kAudioObjectPropertyElementMain) {
            [kAudioObjectPropertyElementMain]
        } else {
            elements.filter { CoreAudioHAL.isInputMuteSettable(deviceID, element: $0) }
        }
        self.deviceID = deviceID
        self.elements = elements
        self.muteElements = muteElements
        isVolumeSettable = !elements.isEmpty && elements.allSatisfy {
            CoreAudioHAL.isInputVolumeSettable(deviceID, element: $0)
        }

        let addresses = elements.map { CoreAudioHAL.inputVolumeAddress(element: $0) }
            + muteElements.map { CoreAudioHAL.inputMuteAddress(element: $0) }
        listeners = addresses.compactMap { CoreAudioHAL.addListener(deviceID, address: $0, handler: onChange) }
        Self.logger.info("Device \(deviceID): volume elements \(elements, privacy: .public), settable \(self.isVolumeSettable), mute elements \(muteElements, privacy: .public)")
    }

    func invalidate() {
        listeners.forEach(CoreAudioHAL.removeListener)
        listeners = []
    }

    /// チャンネルごとの場合は平均。
    func volume() -> Float? {
        let values = elements.compactMap { CoreAudioHAL.inputVolume(deviceID, element: $0) }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }

    /// 音量を持つ全要素に同じ値を設定する。途中で失敗しても残りの要素にも設定し、すべて成功したら true。
    func setVolume(_ value: Float) -> Bool {
        elements.map { CoreAudioHAL.setInputVolume(deviceID, element: $0, value) }.allSatisfy { $0 }
    }

    func isMuted() -> Bool {
        muteElements.contains { CoreAudioHAL.isInputMuted(deviceID, element: $0) == true }
    }

    /// ミュートを持つ全要素に同じ状態を設定する。途中で失敗しても残りの要素にも設定し、すべて成功したら true。
    func setMuted(_ muted: Bool) -> Bool {
        muteElements.map { CoreAudioHAL.setInputMuted(deviceID, element: $0, muted) }.allSatisfy { $0 }
    }

    #if DEBUG
    /// 各要素の scalar・dB・dB の範囲と、ミュートの状態。
    var debugState: String {
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
