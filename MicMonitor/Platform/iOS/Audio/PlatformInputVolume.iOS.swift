import AVFoundation

/// iOS: 音量はオーディオセッションの入力ゲイン（`AVAudioSession.inputGain`、0...1）。
/// 経路（デバイス）によっては変更できない（`isInputGainSettable`）。
///
/// ミュートは `AVAudioApplication` の入力ミュートで、このアプリの入力だけが無音になる
/// （macOS と違い、他のアプリの録音には効かない）。iOS にはシステム全体の入力ミュートがない。
/// ゲインを変更できない経路でもミュートはできる。
@MainActor
final class PlatformInputVolume: InputVolumeBackend {
    private var gainObservation: NSKeyValueObservation?
    private var tasks: [Task<Void, Never>] = []

    init(device: AudioInputDevice, onChange: @escaping @MainActor @Sendable () -> Void) {
        gainObservation = Self.observeGain(onChange)
        let center = NotificationCenter.default
        // 経路が変わると、ゲインを変更できるかどうかも変わる
        let routeChanges = center.notifications(named: AVAudioSession.routeChangeNotification)
        let muteChanges = center.notifications(named: AVAudioApplication.inputMuteStateChangeNotification)
        tasks = [
            Task { for await _ in routeChanges { onChange() } },
            Task { for await _ in muteChanges { onChange() } },
        ]
    }

    func invalidate() {
        gainObservation?.invalidate()
        gainObservation = nil
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    var isVolumeSettable: Bool { AVAudioSession.sharedInstance().isInputGainSettable }
    var hasMute: Bool { true }

    func volume() -> Float? {
        AVAudioSession.sharedInstance().inputGain
    }

    func setVolume(_ value: Float) -> Bool {
        do {
            try AVAudioSession.sharedInstance().setInputGain(min(max(value, 0), 1))
            return true
        } catch {
            return false
        }
    }

    func isMuted() -> Bool {
        AVAudioApplication.shared.isInputMuted
    }

    func setMuted(_ muted: Bool) -> Bool {
        do {
            try AVAudioApplication.shared.setInputMuted(muted)
            return true
        } catch {
            return false
        }
    }

    #if DEBUG
    var debugState: String {
        let session = AVAudioSession.sharedInstance()
        return String(format: "gain %.3f, settable %@, app input muted %@",
                      session.inputGain, String(session.isInputGainSettable),
                      String(AVAudioApplication.shared.isInputMuted))
    }
    #endif

    /// KVO のクロージャは任意のスレッドで呼ばれる。nonisolated な文脈で作り、MainActor に移ってから知らせる
    /// （MainActor の文脈で作ると、Swift 6 の実行時の分離チェックでクラッシュする）。
    nonisolated private static func observeGain(
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) -> NSKeyValueObservation {
        AVAudioSession.sharedInstance().observe(\.inputGain, options: []) { _, _ in
            Task { @MainActor in handler() }
        }
    }
}
