import AVFoundation
import Foundation
import Observation
import os

@MainActor
@Observable
final class MonitorModel {
    enum Permission { case unknown, granted, denied }

    static let logger = Logger(subsystem: "MicMonitor", category: "Monitor")
    static let historyRange = 1...60
    static let defaultHistorySeconds = 10

    private enum Keys {
        static let deviceUID = "selectedDeviceUID"
        static let deviceName = "selectedDeviceName"
        static let historySeconds = "historySeconds"
        static let monitorEnabled = "monitorEnabled"
        static let monitorVolume = "monitorVolume"
        static let continuesInBackground = "continuesInBackground"
    }

    let deviceManager = AudioDeviceManager()
    let inputVolume = InputVolumeController()
    /// iOS のオーディオセッション（macOS では入力ノードへのデバイスの指定だけを行う）。
    private let session = AudioSessionController()
    let levels = LevelStore()
    let waveform: WaveformHistory
    let spectrum = SpectrumAnalyzer()
    let spectrogram: SpectrogramHistory
    private let engine: AudioCaptureEngine
    private let defaults: UserDefaults
    @ObservationIgnored private var pendingRestart: Task<Void, Never>?
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private var isStarting = false
    /// iOS: 通話などの割り込みで止められている間は true。終わるまで再起動しない。
    /// この間は計測を止めているものとして表示する（`isCaptureStopped`）。
    private(set) var isInterrupted = false
    /// セッションの有効化・無効化を順に行うためのタスク（前の操作が終わってから次を始める）。
    @ObservationIgnored private var sessionWork: Task<Void, Never>?
    /// 再起動の世代。有効化を待っている間に別の再起動や停止・割り込みがあったら、古い再起動ではエンジンを始めない。
    @ObservationIgnored private var restartGeneration = 0
    /// セッションの有効化を待っている間は true。始めるときに使うデバイスを決め直すので、その間の再起動は要らない。
    @ObservationIgnored private var isActivating = false
    /// 直前の再起動でセッションに指定した優先する入力の UID（iOS）。選択が変わったら、使うデバイスが同じでも指定し直す。
    @ObservationIgnored private var appliedPreferredInputUID: String?

    var selection: DeviceSelection {
        didSet {
            guard selection != oldValue else { return }
            if case .device(let uid) = selection, let device = deviceManager.device(uid: uid) {
                selectedDeviceName = device.name
            }
            defaults.set(selection.storageValue, forKey: Keys.deviceUID)
            reconcile()
        }
    }

    /// 選択中デバイスの名前（未接続のときの表示用）。
    private(set) var selectedDeviceName: String? {
        didSet { defaults.set(selectedDeviceName, forKey: Keys.deviceName) }
    }

    /// 波形・スペクトログラムの履歴の長さ（秒）。`historyRange` の範囲内で設定すること。
    var historySeconds: Int {
        didSet {
            defaults.set(historySeconds, forKey: Keys.historySeconds)
            waveform.setCapacity(historySeconds * WaveformHistory.binsPerSecond)
            spectrogram.setCapacity(historySeconds * SpectrogramHistory.columnsPerSecond)
        }
    }

    var monitorEnabled: Bool {
        didSet {
            guard monitorEnabled != oldValue else { return }
            defaults.set(monitorEnabled, forKey: Keys.monitorEnabled)
            reconcile(force: true)
        }
    }

    var monitorVolume: Float {
        didSet {
            defaults.set(monitorVolume, forKey: Keys.monitorVolume)
            engine.monitorVolume = monitorVolume
        }
    }

    /// iOS: バックグラウンドでも計測を続けるか。既定（false）では、バックグラウンドに入ると止めて前面に戻ったら再開する。
    var continuesInBackground: Bool {
        didSet { defaults.set(continuesInBackground, forKey: Keys.continuesInBackground) }
    }

    /// iOS: バックグラウンドに入ったために止めているか。前面に戻ったら再開する（ユーザーの停止 `isPaused` とは別）。
    @ObservationIgnored private var isSuspendedInBackground = false

    private(set) var permission: Permission = .unknown
    private(set) var activeDevice: AudioInputDevice?
    private(set) var activeFormat: CaptureFormat?
    private(set) var isRunning = false
    /// ユーザーが計測を止めているか。止めている間は `start()` が呼ばれても始めない
    /// （ウィンドウやカードが表示されたときに呼ばれるため）。次回の起動時は計測を始める。
    private(set) var isPaused = false
    private(set) var errorMessage: String?
    /// モニター再生だけが失敗したときの理由（計測は続いている）。
    private(set) var monitorErrorMessage: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedSeconds = defaults.object(forKey: Keys.historySeconds) as? Int ?? Self.defaultHistorySeconds
        let seconds = min(max(storedSeconds, Self.historyRange.lowerBound), Self.historyRange.upperBound)
        let volume = (defaults.object(forKey: Keys.monitorVolume) as? NSNumber)?.floatValue ?? 0.5

        historySeconds = seconds
        selection = DeviceSelection(storageValue: defaults.string(forKey: Keys.deviceUID))
        selectedDeviceName = defaults.string(forKey: Keys.deviceName)
        monitorEnabled = defaults.bool(forKey: Keys.monitorEnabled)
        monitorVolume = volume
        continuesInBackground = defaults.bool(forKey: Keys.continuesInBackground)

        waveform = WaveformHistory(capacity: seconds * WaveformHistory.binsPerSecond)
        spectrogram = SpectrogramHistory(capacity: seconds * SpectrogramHistory.columnsPerSecond)
        engine = AudioCaptureEngine(levels: levels, waveform: waveform, spectrum: spectrum,
                                    spectrogram: spectrogram)
        engine.monitorVolume = volume

        deviceManager.onChange = { [weak self] in self?.reconcile() }
        engine.onConfigurationChange = { [weak self] in self?.scheduleRestart() }
        session.onEvent = { [weak self] event in self?.handleSessionEvent(event) }
    }

    // MARK: - 表示用

    /// Slider 用（`historySeconds` の Double 版）。
    var historySecondsValue: Double {
        get { Double(historySeconds) }
        set { historySeconds = Int(newValue.rounded()) }
    }

    /// 入力音量スライダーの目盛りの数（両端を含む）。
    static let inputVolumeTickCount = 7
    /// 目盛りにこの距離（0...1 の範囲で）まで近づいたら吸着させる。
    static let inputVolumeSnapDistance: Float = 0.02

    static var inputVolumeTicks: [Float] {
        (0..<inputVolumeTickCount).map { Float($0) / Float(inputVolumeTickCount - 1) }
    }

    /// 目盛りの近くなら目盛りの値に、そうでなければそのままの値にする（無段階 + 吸着）。
    static func snappedInputVolume(_ value: Float) -> Float {
        let nearest = inputVolumeTicks.min { abs($0 - value) < abs($1 - value) } ?? value
        return abs(nearest - value) <= inputVolumeSnapDistance ? nearest : value
    }

    /// Slider 用（入力音量 0...1）。
    var inputVolumeValue: Float {
        get { inputVolume.volume ?? 0 }
        set { inputVolume.setVolume(Self.snappedInputVolume(newValue)) }
    }

    var systemDefaultLabel: String {
        if let name = deviceManager.defaultInputDevice?.name {
            "システム既定（\(name)）"
        } else {
            "システム既定"
        }
    }

    /// 指定デバイスが見つからず、システム既定で代用しているか。
    var isUsingFallback: Bool {
        guard case .device(let uid) = selection else { return false }
        return deviceManager.device(uid: uid) == nil
    }

    var canMonitor: Bool {
        guard let channels = activeFormat?.channelCount else { return false }
        return channels <= AudioCaptureEngine.maxMonitorChannels
    }

    // MARK: - 開始・停止

    private static let isRunningForPreviews =
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    /// ウィンドウ表示とカード表示の両方から呼ばれるため、動作中なら何もしない。
    func start() async {
        // Xcode のプレビューではマイクを使わない（プレビューを描いたプロセスが裏に残り、マイクを使い続けることがある）
        if Self.isRunningForPreviews { return }
        // 権限の確認を待っている間にもう一方から呼ばれても、二重に起動しない
        if isPaused || isStarting || (wantsRunning && (isRunning || isActivating)) { return }
        isStarting = true
        defer { isStarting = false }
        wantsRunning = true
        await updatePermission()
        reconcile(force: true)
    }

    func stop() {
        wantsRunning = false
        pendingRestart?.cancel()
        restartGeneration += 1
        isActivating = false
        engine.stop()
        enqueueSessionWork { [session] in await session.deactivate() }
        isRunning = false
        resetMeters()
    }

    /// 計測を止める。オーディオエンジンを解放するので、マイクの使用も止まる（モニター再生も止まる）。
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        stop()
        errorMessage = nil
        monitorErrorMessage = nil
        Self.logger.info("Paused by user")
    }

    /// iOS: バックグラウンドに入った。続ける設定でなければ計測を止める（マイクとモニター再生も止まる）。
    /// ユーザーが止めている間（`isPaused`）は何もしない。割り込み中は止めておき、戻ったら割り込みの状態のまま始め直す。
    func enterBackground() {
        guard !continuesInBackground, wantsRunning else { return }
        isSuspendedInBackground = true
        stop()
        Self.logger.info("Stopped in background")
    }

    /// iOS: 前面に戻った。バックグラウンドに入ったために止めていたら再開する。
    func enterForeground() async {
        guard isSuspendedInBackground else { return }
        isSuspendedInBackground = false
        Self.logger.info("Restarting after returning to foreground")
        await start()
    }

    /// 止めていた計測を再開する。
    func resume() async {
        guard isPaused else { return }
        isPaused = false
        // 割り込みの終わりの通知は届かないことがある。ユーザーが再開したら割り込みは終わったものとして始め直す
        // （まだ続いていればセッションの有効化に失敗し、その理由を出す）
        isInterrupted = false
        Self.logger.info("Resumed by user")
        await start()
    }

    /// 計測が止まっているか（ユーザーが止めているか、割り込みで止められている）。
    /// 停止・再開ボタンを「計測を開始」にし、計測の欄とモニター再生を止めた状態の表示にする。
    var isCaptureStopped: Bool { isPaused || isInterrupted }

    func togglePause() {
        if isPaused {
            Task { await resume() }
        } else if isInterrupted {
            retryAfterInterruption()
        } else {
            pause()
        }
    }

    /// 割り込みで止められているときに「計測を開始」が押された。割り込みの終わりの通知は届かないことがあるので、
    /// 終わったものとして始め直す（まだ続いていればセッションの有効化に失敗し、その理由を出す）。
    private func retryAfterInterruption() {
        Self.logger.info("Retry after interruption by user")
        isInterrupted = false
        if errorMessage == Self.interruptionMessage { errorMessage = nil }
        reconcile(force: true)
    }

    // MARK: - 内部

    private func updatePermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permission = .granted
        case .notDetermined:
            permission = await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
        default:
            permission = .denied
        }
        Self.logger.info("Microphone permission: \(String(describing: self.permission), privacy: .public); \(self.deviceManager.inputDevices.count) input devices, default: \(self.deviceManager.defaultInputDevice?.name ?? "none", privacy: .public)")
    }

    /// iOS でセッションの優先する入力に指定する UID。システム既定なら nil。
    /// 一覧（`deviceManager`）はセッションを録音用にするまで揃わないので、一覧に無くても選択の UID をそのまま渡す。
    /// macOS は入力ノードにデバイスを直接指定するので使わない（常に nil）。
    private var preferredInputUID: String? {
        #if os(macOS)
        return nil
        #else
        guard case .device(let uid) = selection else { return nil }
        return uid
        #endif
    }

    private func resolveDevice() -> AudioInputDevice? {
        switch selection {
        case .systemDefault:
            deviceManager.defaultInputDevice
        case .device(let uid):
            deviceManager.device(uid: uid) ?? deviceManager.defaultInputDevice
        }
    }

    /// 選択・接続状況に合わせてエンジンを (再) 起動する。
    private func reconcile(force: Bool = false) {
        guard wantsRunning, permission == .granted, !isInterrupted else { return }
        if !force, preferredInputUID == appliedPreferredInputUID {
            // 有効化を待っている間は、始めるときにデバイスを決め直すので待つ
            // （有効化そのものが起こす経路の変更通知で、始めかけたものを捨てないように）
            if isActivating { return }
            if isRunning, resolveDevice()?.id == activeDevice?.id { return }
        }
        restart()
    }

    private func restart() {
        pendingRestart?.cancel()
        engine.stop()
        isRunning = false
        monitorErrorMessage = nil
        restartGeneration += 1
        let generation = restartGeneration
        let preferredInputUID = preferredInputUID
        appliedPreferredInputUID = preferredInputUID
        isActivating = true
        let monitoring = monitorEnabled
        // iOS はエンジンを作る前に、セッションで入力を選んで有効にする（macOS では何もしない）。
        // 有効化は非同期なので、待っている間に別の再起動・停止・割り込みがあったら何もしない
        enqueueSessionWork { [weak self, session] in
            do {
                try await session.activate(preferredInputUID: preferredInputUID, monitoring: monitoring)
            } catch {
                guard let self, generation == self.restartGeneration else { return }
                self.isActivating = false
                self.activeDevice = nil
                self.inputVolume.attach(to: nil)
                self.fail("オーディオセッションを開始できませんでした: \(error.localizedDescription)")
                Self.logger.error("Failed to activate audio session: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let self, generation == self.restartGeneration else { return }
            self.isActivating = false
            guard self.wantsRunning, !self.isInterrupted else { return }
            self.startEngine()
        }
    }

    /// セッションの操作を、前の操作が終わってから行う（有効化と無効化が入れ違わないように）。
    private func enqueueSessionWork(_ operation: @escaping @MainActor () async -> Void) {
        let previous = sessionWork
        sessionWork = Task {
            await previous?.value
            await operation()
        }
    }

    /// セッションを有効にしたあとで、使うデバイスを決めてエンジンを始める。
    private func startEngine() {
        // iOS では有効にしてから入力の一覧と経路が決まるため、取り直してから使うデバイスを決める
        deviceManager.refresh()
        let device = resolveDevice()
        activeDevice = device
        inputVolume.attach(to: device)
        guard let device else {
            fail("入力デバイスが見つかりません。")
            Self.logger.error("No input device to start")
            return
        }
        do {
            let session = session
            let format = try engine.start(monitoring: monitorEnabled) { input in
                try session.bind(input, to: device)
            }
            activeFormat = format
            isRunning = true
            errorMessage = nil
            monitorErrorMessage = engine.monitorError
            Self.logger.info("Started \(device.name, privacy: .public) (id \(device.id)) \(format.sampleRate) Hz \(format.channelCount) ch, monitoring: \(self.monitorEnabled)")
            #if DEBUG
            logSignalAfterStart()
            #endif
        } catch {
            fail("「\(device.name)」を開始できませんでした: \(error.localizedDescription)")
            Self.logger.error("Failed to start \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 開始できなかったときに、表示をリセットして理由を出す。
    private func fail(_ message: String) {
        activeFormat = nil
        resetMeters()
        errorMessage = message
    }

    /// メーターとスペクトルの保持を消す（波形は止めた時点のまま残す）。
    private func resetMeters() {
        levels.reset()
        spectrum.reset()
    }

    #if DEBUG
    /// 開始 1 秒後に波形履歴を見て、音声が流れているかをログに出す。
    private func logSignalAfterStart() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.isRunning else { return }
            let snapshot = self.waveform.snapshot()
            let summary = snapshot.channels.enumerated().map { index, bins in
                let recent = bins.suffix(WaveformHistory.binsPerSecond)
                let maximum = recent.map(\.max).max() ?? 0
                let minimum = recent.map(\.min).min() ?? 0
                let positiveOnly = recent.filter { $0.min > 0 }.count
                let negativeOnly = recent.filter { $0.max < 0 }.count
                return "ch\(index + 1): \(bins.count) bins (one-signed: +\(positiveOnly) / -\(negativeOnly) of \(recent.count)), max \(String(format: "%+.4f", maximum)) (\(Decibel.format(Decibel.from(maximum))) dB), min \(String(format: "%+.4f", minimum)) (\(Decibel.format(Decibel.from(-minimum))) dB)"
            }
            Self.logger.debug("Signal check: \(summary.joined(separator: ", "), privacy: .public)")

            // 起動直後を避けて 3 秒間、シンクノードの呼び出し・ポンプの処理間隔・描画フレームの間隔を計測する
            let sinkBefore = self.engine.sinkStatistics
            TimingProbe.tap.reset()
            TimingProbe.frame.reset()
            let measureSeconds = 3.0
            try? await Task.sleep(for: .seconds(measureSeconds))
            guard self.isRunning else { return }
            if let before = sinkBefore, let after = self.engine.sinkStatistics, let format = self.activeFormat {
                let calls = after.calls - before.calls
                let rate = Double(calls) / measureSeconds
                let framesPerCall = rate > 0 ? format.sampleRate / rate : 0
                Self.logger.debug("Sink timing: \(String(format: "%.1f calls/s (≈%.0f frames, %.1f ms per call)", rate, framesPerCall, framesPerCall / format.sampleRate * 1000), privacy: .public), dropped \(after.droppedFrames - before.droppedFrames) frames")
            }
            Self.logger.debug("Pump timing: \(TimingProbe.tap.summary(), privacy: .public)")
            Self.logger.debug("Frame timing: \(TimingProbe.frame.summary(), privacy: .public)")
        }
    }
    #endif

    private static let interruptionMessage = "通話などの割り込みのため、計測を中断しています。"

    /// iOS のオーディオセッションの出来事。割り込みの間は止めておき、終わったら再開する。
    private func handleSessionEvent(_ event: AudioSessionEvent) {
        Self.logger.info("Audio session event: \(String(describing: event), privacy: .public)")
        switch event {
        case .interruptionBegan:
            isInterrupted = true
            pendingRestart?.cancel()
            restartGeneration += 1
            isActivating = false
            engine.stop()
            isRunning = false
            resetMeters()
            if wantsRunning { errorMessage = Self.interruptionMessage }
        case .interruptionEnded(let shouldResume):
            isInterrupted = false
            // 割り込みの表示だけを消す（再開中に起きたほかのエラーは残す）
            if errorMessage == Self.interruptionMessage { errorMessage = nil }
            if shouldResume {
                reconcile(force: true)
            } else if wantsRunning {
                // 再開がすすめられないとき（ほかのアプリが音声を使い続けているなど）は、計測を止めた状態にする。
                // 「計測を開始」で再開できる
                pause()
            }
        case .needsRestart:
            scheduleRestart()
        }
    }

    /// 構成変更通知は続けて届くことがあるため、少し待ってから再起動する。
    private func scheduleRestart() {
        pendingRestart?.cancel()
        pendingRestart = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.deviceManager.refresh()
            self?.reconcile(force: true)
        }
    }
}
