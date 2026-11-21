import AVFoundation
import Foundation
import Observation
import os

@MainActor
@Observable
final class MonitorModel {
    enum Permission { case unknown, granted, denied }

    static let logger = Logger(subsystem: "MicMon", category: "Monitor")
    static let historyRange = 1...60
    static let defaultHistorySeconds = 10

    private enum Keys {
        static let deviceUID = "selectedDeviceUID"
        static let deviceName = "selectedDeviceName"
        static let historySeconds = "historySeconds"
        static let monitorEnabled = "monitorEnabled"
        static let monitorVolume = "monitorVolume"
    }

    let deviceManager = AudioDeviceManager()
    let inputVolume = InputVolumeController()
    let levels = LevelStore()
    let waveform: WaveformHistory
    private let engine: AudioCaptureEngine
    private let defaults: UserDefaults
    @ObservationIgnored private var pendingRestart: Task<Void, Never>?
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private var isStarting = false

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

    /// 波形履歴の長さ（秒）。`historyRange` の範囲内で設定すること。
    var historySeconds: Int {
        didSet {
            defaults.set(historySeconds, forKey: Keys.historySeconds)
            waveform.setCapacity(historySeconds * WaveformHistory.binsPerSecond)
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

    private(set) var permission: Permission = .unknown
    private(set) var activeDevice: AudioInputDevice?
    private(set) var activeFormat: CaptureFormat?
    private(set) var isRunning = false
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

        waveform = WaveformHistory(capacity: seconds * WaveformHistory.binsPerSecond)
        engine = AudioCaptureEngine(levels: levels, waveform: waveform)
        engine.monitorVolume = volume

        deviceManager.onChange = { [weak self] in self?.reconcile() }
        engine.onConfigurationChange = { [weak self] in self?.scheduleRestart() }
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

    /// ウィンドウ表示とカード表示の両方から呼ばれるため、動作中なら何もしない。
    func start() async {
        // 権限の確認を待っている間にもう一方から呼ばれても、二重に起動しない
        if isStarting || (wantsRunning && isRunning) { return }
        isStarting = true
        defer { isStarting = false }
        wantsRunning = true
        await updatePermission()
        reconcile(force: true)
    }

    func stop() {
        wantsRunning = false
        pendingRestart?.cancel()
        engine.stop()
        isRunning = false
        levels.reset()
    }

    func resetClip() {
        levels.resetClip()
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
        guard wantsRunning, permission == .granted else { return }
        let target = resolveDevice()
        if !force, isRunning, target?.id == activeDevice?.id { return }
        restart(with: target)
    }

    private func restart(with device: AudioInputDevice?) {
        pendingRestart?.cancel()
        engine.stop()
        isRunning = false
        monitorErrorMessage = nil
        activeDevice = device
        inputVolume.attach(to: device?.id)
        guard let device else {
            activeFormat = nil
            levels.reset()
            errorMessage = "入力デバイスが見つかりません。"
            Self.logger.error("No input device to start")
            return
        }
        do {
            let format = try engine.start(deviceID: device.id, monitoring: monitorEnabled)
            activeFormat = format
            isRunning = true
            errorMessage = nil
            monitorErrorMessage = engine.monitorError
            Self.logger.info("Started \(device.name, privacy: .public) (id \(device.id)) \(format.sampleRate) Hz \(format.channelCount) ch, monitoring: \(self.monitorEnabled)")
            #if DEBUG
            logSignalAfterStart()
            #endif
        } catch {
            activeFormat = nil
            levels.reset()
            errorMessage = "「\(device.name)」を開始できませんでした: \(error.localizedDescription)"
            Self.logger.error("Failed to start \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
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
