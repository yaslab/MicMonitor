import Observation
import os

/// 選択中デバイスの入力音量とミュートの表示・変更。OS への読み書きは `PlatformInputVolume`
/// （`InputVolumeBackend`）が行う（macOS はシステム設定 > サウンド > 入力 と同じ値、iOS はセッションの入力ゲイン）。
///
/// 入力音量は多くのデバイスでゲイン（例: Mac の内蔵マイクは -12〜+12 dB）で、0 にしても無音にならない。
/// そのため、デバイスがミュートを持つ場合は 0 をミュートとして扱う。
@MainActor
@Observable
final class InputVolumeController {
    /// 0...1。ミュート中は 0。デバイスが入力音量を持たないときは nil。
    private(set) var volume: Float?
    /// 音量をアプリから変更できるか。
    private(set) var isSettable = false
    /// ミュート中か（システム設定や他のアプリでのミュートも含む）。
    private(set) var isMuted = false
    /// ミュートボタンを使えるか。ミュートを持つか、音量を 0 にできれば使える。
    private(set) var canToggleMute = false

    @ObservationIgnored private var deviceID: AudioDeviceHandle?
    @ObservationIgnored private var backend: PlatformInputVolume?
    /// ミュートする直前の音量。解除するときに音量が 0 ならこの値に戻す。
    private var volumeBeforeMute: Float?
    /// スライダーのドラッグを始めたときの音量。
    @ObservationIgnored private var volumeAtEditStart: Float?

    /// ミュート前の音量がわからないときに戻す音量。
    private static let defaultRestoreVolume: Float = 0.5
    private static let logger = Logger(subsystem: "MicMonitor", category: "InputVolume")

    private var hasMute: Bool { backend?.hasMute ?? false }

    /// 対象デバイスを切り替える。同じデバイスなら何もしない。
    func attach(to device: AudioInputDevice?) {
        guard device?.id != deviceID else { return }
        detach()
        deviceID = device?.id
        guard let device else { return }
        backend = PlatformInputVolume(device: device) { [weak self] in self?.refresh() }
        refresh()
    }

    /// スライダーの操作の開始と終了（`Slider` の `onEditingChanged`）。
    func editingChanged(_ isEditing: Bool) {
        volumeAtEditStart = isEditing ? volume : nil
    }

    /// ミュートボタンの状態。ミュートを持たないデバイスでは、ボタンで 0 にした状態をミュート扱いにする。
    var isMuteActive: Bool {
        isMuted || (!hasMute && volumeBeforeMute != nil && volume == 0)
    }

    /// マイクボタン: ミュートと解除を切り替える。解除するときはミュート前の音量に戻す。
    func toggleMute() {
        isMuteActive ? unmute() : mute()
    }

    private func mute() {
        guard let backend, canToggleMute else { return }
        if let volume, volume > 0 { volumeBeforeMute = volume }
        if backend.hasMute {
            // 音量はそのまま残し、ミュートだけをオンにする（解除すれば元の音量に戻る）
            _ = backend.setMuted(true)
            isMuted = true
        } else {
            // ミュートを持たないデバイスは最小ゲインにするしかない
            _ = backend.setVolume(0)
        }
        volume = 0
    }

    private func unmute() {
        guard let backend, canToggleMute else { return }
        if backend.hasMute { _ = backend.setMuted(false) }
        // スライダーで 0 にしてミュートした場合などは音量自体が 0 なので、ミュート前の音量に戻す
        if isSettable, (backend.volume() ?? 0) <= 0 {
            _ = backend.setVolume(volumeBeforeMute ?? Self.defaultRestoreVolume)
        }
        volumeBeforeMute = nil
        isMuted = false
        refresh()
    }

    /// 0 のときはミュートし、0 より大きければミュートを解除する（ミュートがあるデバイスのみ）。
    func setVolume(_ newValue: Float) {
        guard let backend, isSettable else { return }
        let value = min(max(newValue, 0), 1)
        let mute = value <= 0 && backend.hasMute
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

        var succeeded = backend.setVolume(value)
        if backend.hasMute, mute != isMuted {
            succeeded = backend.setMuted(mute) && succeeded
        }
        if !succeeded {
            Self.logger.error("Failed to set input volume/mute on device \(String(describing: self.deviceID), privacy: .public)")
        }
        volume = value
        isMuted = mute
    }

    private func detach() {
        backend?.invalidate()
        backend = nil
        volumeBeforeMute = nil
        deviceID = nil
        volume = nil
        isSettable = false
        isMuted = false
        canToggleMute = false
    }

    /// 外部（システム設定や他のアプリ）での変更を反映する。
    /// iOS では経路が変わると変更できるかどうかも変わるため、それも読み直す。
    private func refresh() {
        guard let backend else { return }
        let settable = backend.isVolumeSettable
        let canMute = backend.hasMute || settable
        let muted = backend.isMuted()
        let newVolume: Float? = backend.volume().map { muted ? 0 : $0 }
        if settable != isSettable { isSettable = settable }
        if canMute != canToggleMute { canToggleMute = canMute }
        if newVolume != volume { volume = newVolume }
        if muted != isMuted { isMuted = muted }
        #if DEBUG
        Self.logger.debug("Input volume: \(backend.debugState, privacy: .public)")
        #endif
    }

    #if DEBUG
    var debugState: String { backend?.debugState ?? "no device" }
    #endif
}
