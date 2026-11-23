import AVFoundation

typealias AudioDeviceHandle = String

/// iOS: オーディオセッションの入力ポート（`AVAudioSession.availableInputs`）を入力デバイスとして扱う。
/// ID はポートの UID。一覧はセッションのカテゴリを録音用にしてから取れるので、有効にした後に取り直す
/// （`MonitorModel.restart()`）。
///
/// iOS には「システム既定の入力」を直接得る API がない。優先する入力（`preferredInput`）を指定していない
/// ときの経路の入力を既定とみなし、指定している間は最後に見た既定を使う。指定している間は経路から既定を
/// 確かめられないので、最後に見た既定が分からないとき（指定したまま起動した、指定中に入力が増減した）は推測せず nil にする
/// （「システム既定」の名前を出さない）。
@MainActor
final class PlatformInputDevices: InputDeviceSource {
    private var lastDefaultUID: String?
    /// 直前に見た入力の UID。指定中に増減したら、最後に見た既定はもう当てにならない。
    private var lastDeviceUIDs: Set<String> = []
    private var tasks: [Task<Void, Never>] = []

    func inputDevices() -> [AudioInputDevice] {
        (AVAudioSession.sharedInstance().availableInputs ?? []).map { port in
            // チャンネル数はセッションを有効にするまで取れないことがある。実際の数は入力フォーマットで決まる
            AudioInputDevice(id: port.uid, uid: port.uid, name: port.portName,
                             inputChannelCount: max(port.channels?.count ?? 1, 1))
        }
    }

    func defaultInputDeviceID(in devices: [AudioInputDevice]) -> AudioDeviceHandle? {
        let session = AVAudioSession.sharedInstance()
        let uids = Set(devices.map(\.uid))
        let isPinned = session.preferredInput != nil
        if !isPinned {
            if let uid = session.currentRoute.inputs.first?.uid { lastDefaultUID = uid }
        } else if uids != lastDeviceUIDs {
            lastDefaultUID = nil
        }
        lastDeviceUIDs = uids
        if let uid = lastDefaultUID, uids.contains(uid) { return uid }
        if isPinned { return nil }
        // 録音用にする前など、経路に入力がないとき
        let builtIn = session.availableInputs?.first { $0.portType == .builtInMic }?.uid
        return builtIn ?? devices.first?.uid
    }

    /// 経路の変更（ヘッドセットの抜き差しなど）。自分のカテゴリ変更や入力の指定でも届くが、
    /// `MonitorModel.reconcile()` は使うデバイスが変わらなければ何もしない。
    func observeChanges(_ handler: @escaping @MainActor @Sendable () -> Void) {
        let changes = NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification)
        tasks.append(Task {
            for await _ in changes {
                handler()
            }
        })
    }
}
