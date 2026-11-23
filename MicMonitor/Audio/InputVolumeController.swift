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
    /// ミュートする直前の音量。解除するときに音量が 0 ならこの値に戻す。
    private var volumeBeforeMute: Float?
    /// スライダーのドラッグを始めたときの音量。
    @ObservationIgnored private var volumeAtEditStart: Float?

    /// ミュート前の音量がわからないときに戻す音量。
    private static let defaultRestoreVolume: Float = 0.5
    private static let logger = Logger(subsystem: "MicMonitor", category: "InputVolume")

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

    /// スライダーの操作の開始と終了（`Slider` の `onEditingChanged`）。
    func editingChanged(_ isEditing: Bool) {
        volumeAtEditStart = isEditing ? volume : nil
    }

    /// ミュートボタンの状態。ミュートを持たないデバイスでは、ボタンで 0 にした状態をミュート扱いにする。
    var isMuteActive: Bool {
        isMuted || (muteElements.isEmpty && volumeBeforeMute != nil && volume == 0)
    }

    /// マイクボタン: ミュートと解除を切り替える。解除するときはミュート前の音量に戻す。
    func toggleMute() {
        isMuteActive ? unmute() : mute()
    }

    private func mute() {
        guard let deviceID, isSettable else { return }
        if let volume, volume > 0 { volumeBeforeMute = volume }
        if muteElements.isEmpty {
            // ミュートを持たないデバイスは最小ゲインにするしかない
            setAllVolumes(0, on: deviceID)
        } else {
            // 音量はそのまま残し、ミュートだけをオンにする（解除すれば元の音量に戻る）
            setAllMuted(true, on: deviceID)
            isMuted = true
        }
        volume = 0
    }

    private func unmute() {
        guard let deviceID, isSettable else { return }
        setAllMuted(false, on: deviceID)
        // スライダーで 0 にしてミュートした場合などは音量自体が 0 なので、ミュート前の音量に戻す
        if (hardwareVolume() ?? 0) <= 0 {
            setAllVolumes(volumeBeforeMute ?? Self.defaultRestoreVolume, on: deviceID)
        }
        volumeBeforeMute = nil
        isMuted = false
        refresh()
    }

    /// 全要素に同じ値を設定する（チャンネルごとの音量しかないデバイスでも一括で変える）。
    /// 0 のときはミュートし、0 より大きければミュートを解除する（ミュートがあるデバイスのみ）。
    func setVolume(_ newValue: Float) {
        guard let deviceID, isSettable else { return }
        let value = min(max(newValue, 0), 1)
        let mute = value <= 0 && !muteElements.isEmpty
        if value <= 0 {
            // スライダーで 0 にしたときも、マイクボタンで戻せるようにミュート前の音量を覚えておく。
            // ドラッグ中は直前の値が 0 に近いので、ドラッグを始めたときの音量を使う
            if let start = volumeAtEditStart, start > 0 {
                volumeBeforeMute = start
            } else if let volume, volume > 0 {
                volumeBeforeMute = volume
            }
        } else {
            volumeBeforeMute = nil
        }

        var succeeded = setAllVolumes(value, on: deviceID)
        if !muteElements.isEmpty, mute != isMuted {
            succeeded = setAllMuted(mute, on: deviceID) && succeeded
        }
        if !succeeded {
            Self.logger.error("Failed to set input volume/mute on device \(deviceID)")
        }
        volume = value
        isMuted = mute
    }

    /// 音量を持つ全要素に同じ値を設定する。途中で失敗しても残りの要素にも設定し、すべて成功したら true。
    @discardableResult
    private func setAllVolumes(_ value: Float, on deviceID: AudioDeviceID) -> Bool {
        elements.map { CoreAudioHAL.setInputVolume(deviceID, element: $0, value) }.allSatisfy { $0 }
    }

    /// ミュートを持つ全要素に同じ状態を設定する。途中で失敗しても残りの要素にも設定し、すべて成功したら true。
    @discardableResult
    private func setAllMuted(_ muted: Bool, on deviceID: AudioDeviceID) -> Bool {
        muteElements.map { CoreAudioHAL.setInputMuted(deviceID, element: $0, muted) }.allSatisfy { $0 }
    }

    private func detach() {
        listeners.forEach(CoreAudioHAL.removeListener)
        listeners = []
        elements = []
        muteElements = []
        volumeBeforeMute = nil
        deviceID = nil
        volume = nil
        isSettable = false
        isMuted = false
    }

    /// デバイスの実際の音量（ミュートは考慮しない）。チャンネルごとの場合は平均。
    private func hardwareVolume() -> Float? {
        guard let deviceID else { return nil }
        let values = elements.compactMap { CoreAudioHAL.inputVolume(deviceID, element: $0) }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }

    /// 外部（システム設定や他のアプリ）での変更を反映する。チャンネルごとの場合は平均を表示する。
    private func refresh() {
        guard let deviceID else { return }
        let muted = muteElements.contains { CoreAudioHAL.isInputMuted(deviceID, element: $0) == true }
        let newVolume: Float? = hardwareVolume().map { muted ? 0 : $0 }
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
