import AVFoundation
import os

/// iOS: 計測の前にオーディオセッションを録音用に設定して有効にし、入力はセッションの優先する入力で選ぶ。
/// 割り込み（通話・Siri など）とメディアサービスの再起動を `onEvent` で知らせる。
///
/// - モードは `.measurement`（自動ゲイン・音声処理を切る）。
/// - モニター再生がオフのときは `.record` で出力を使わない。オンのときは `.playAndRecord`。iPhone では
///   ヘッドホンがなければイヤースピーカーから鳴る（ハウリングを避けるため、スピーカーには切り替えない）。
@MainActor
final class AudioSessionController: AudioSessionControlling {
    var onEvent: ((AudioSessionEvent) -> Void)?

    /// 入力の処理単位の希望（macOS の 512 フレーム ≈ 10.7 ms に近づける）。実際の値は経路で決まる。
    private nonisolated static let preferredIOBufferDuration: TimeInterval = 0.01
    private nonisolated static let logger = Logger(subsystem: "MicMonitor", category: "Session")

    private var tokens: [NotificationCenter.ObservationToken] = []
    private var resetTask: Task<Void, Never>?

    init() {
        let center = NotificationCenter.default
        tokens = [
            // ほかのアプリや通話による停止（自分で setActive(false) したときは appDeactivated で、無視する）
            center.addObserver(of: AVAudioSession.self, for: .didBecomeInactive) { [weak self] message in
                guard case .systemInterruption(let context) = message.deactivationResult else { return }
                Self.logger.info("Interrupted (reason \(context.reason.rawValue))")
                self?.onEvent?(.interruptionBegan)
            },
            center.addObserver(of: AVAudioSession.self, for: .resumptionRecommendation) { [weak self] message in
                self?.onEvent?(.interruptionEnded(shouldResume: message.recommendation == .shouldResume))
            },
        ]
        let resets = center.notifications(named: AVAudioSession.mediaServicesWereResetNotification)
        resetTask = Task { [weak self] in
            for await _ in resets {
                self?.onEvent?(.needsRestart)
            }
        }
    }

    /// セッションの設定と有効化は終わるまで呼んだスレッドを止める（数十〜数百 ms）ので、メインスレッドの外で行う。
    ///
    /// 非同期の `activate(options:)` は使わない。完了してすぐにエンジンを作ると、入力のフォーマットが
    /// まだ 0 Hz で I/O ユニットの初期化に失敗した（iOS 27 シミュレータ、-10851）。同期の `setActive(true)` は
    /// 戻った時点で経路の設定まで終わっている。
    func activate(preferredInput: AudioInputDevice?, monitoring: Bool) async throws {
        try await Self.configureAndActivate(preferredInputUID: preferredInput?.uid, monitoring: monitoring)
    }

    func deactivate() async {
        await Self.deactivateSession()
    }

    @concurrent
    private nonisolated static func configureAndActivate(preferredInputUID: String?, monitoring: Bool) async throws {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]
        if monitoring { options.insert(.allowBluetoothA2DP) }
        try session.setCategory(monitoring ? .playAndRecord : .record, mode: .measurement, options: options)
        // 一覧はカテゴリを設定してから取れる。nil ならシステム既定（経路の既定の入力）に追従する
        let port = preferredInputUID.flatMap { uid in
            session.availableInputs?.first { $0.uid == uid }
        }
        try session.setPreferredInput(port)
        do {
            try session.setPreferredIOBufferDuration(preferredIOBufferDuration)
        } catch {
            logger.error("Failed to set the preferred I/O buffer duration: \(error.localizedDescription, privacy: .public)")
        }
        try session.setActive(true)
        let inputs = session.currentRoute.inputs.map(\.portName).joined(separator: ", ")
        logger.info("Activated: input \(inputs, privacy: .public), \(session.sampleRate) Hz, I/O buffer \(session.ioBufferDuration * 1000) ms, monitoring \(monitoring)")
    }

    @concurrent
    private nonisolated static func deactivateSession() async {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Failed to deactivate the audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 入力はセッションの優先する入力で選んでいるので、エンジン側では何もしない。
    func bind(_ input: AVAudioInputNode, to device: AudioInputDevice) throws {}
}
