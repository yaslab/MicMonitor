import AVFoundation

// プラットフォームごとに実装する部分の約束ごと。
// 実装は同じ型名で `Platform/macOS/Audio/`（Core Audio HAL）と `Platform/iOS/Audio/`（AVAudioSession）に置き、
// ビルド設定 `EXCLUDED_SOURCE_FILE_NAMES` でどちらか一方だけをコンパイルする。
//
// | プロトコル                | 実装の型名               |
// |---------------------------|--------------------------|
// | `InputDeviceSource`       | `PlatformInputDevices`   |
// | `InputVolumeBackend`      | `PlatformInputVolume`    |
// | `AudioSessionControlling` | `AudioSessionController` |
//
// あわせて、デバイスの ID の型 `AudioDeviceHandle` もプラットフォームごとに定める
// （macOS は `AudioDeviceID`、iOS は入力ポートの UID）。

/// 入力デバイスの一覧とシステム既定の入力デバイスを OS から取得する。
@MainActor
protocol InputDeviceSource: AnyObject {
    /// 入力チャンネルを持つデバイス（並べ替えは `AudioDeviceManager` が行う）。
    func inputDevices() -> [AudioInputDevice]
    /// システム既定の入力デバイス。`devices` は直前に取得した一覧。
    func defaultInputDeviceID(in devices: [AudioInputDevice]) -> AudioDeviceHandle?
    /// 一覧または既定デバイスが変わったかもしれないときに `handler` を呼ぶ（メインスレッド）。
    /// アプリの寿命と同じだけ使う前提のため、解除はしない。
    func observeChanges(_ handler: @escaping @MainActor @Sendable () -> Void)
}

/// 1 つの入力デバイスの入力音量（0...1）とミュートを読み書きする。
/// ミュート前の音量を覚えるなどの振る舞いは `InputVolumeController` が共通で持つ。
@MainActor
protocol InputVolumeBackend: AnyObject {
    /// `onChange` は外部（システム設定や他のアプリ）で音量やミュートが変わったときに呼ぶ（メインスレッド）。
    init(device: AudioInputDevice, onChange: @escaping @MainActor @Sendable () -> Void)
    /// 監視をやめる。対象デバイスを切り替える前に呼ばれる。
    func invalidate()

    /// 音量を変更できるか。
    var isVolumeSettable: Bool { get }
    /// 音量と別にミュートを持つか。持つときはスライダーの 0 をミュートとして扱う。
    /// 持たないときは 0 は最小ゲインで、ミュートボタンは音量を 0 にする。
    var hasMute: Bool { get }
    /// 実際の音量（ミュートは考慮しない）。音量を持たないときは nil。
    func volume() -> Float?
    /// 成功したら true。
    func setVolume(_ value: Float) -> Bool
    func isMuted() -> Bool
    /// 成功したら true。
    func setMuted(_ muted: Bool) -> Bool

    #if DEBUG
    /// 計測用の状態の説明。
    var debugState: String { get }
    #endif
}

/// オーディオセッションで起きた、計測に影響する出来事。
enum AudioSessionEvent: Sendable {
    /// 通話などの割り込みで入出力が止められた。
    case interruptionBegan
    /// 割り込みが終わった。`shouldResume` はシステムが再開をすすめているか。
    case interruptionEnded(shouldResume: Bool)
    /// メディアサービスの再起動などで、エンジンを作り直す必要がある。
    case needsRestart
}

/// 計測の前後のオーディオセッションの操作と、エンジンの入力デバイスの指定。
@MainActor
protocol AudioSessionControlling: AnyObject {
    /// セッションの出来事を受け取る（メインスレッド）。macOS では呼ばれない。
    var onEvent: ((AudioSessionEvent) -> Void)? { get set }
    /// エンジンを作る前に呼ぶ。`preferredInput` が nil ならシステム既定の入力に追従する。
    /// `monitoring` はモニター再生のために出力も使うか。
    /// セッションの有効化は時間がかかるため非同期（メインスレッドを止めない）。
    func activate(preferredInput: AudioInputDevice?, monitoring: Bool) async throws
    /// 計測を止めたときに呼ぶ。
    func deactivate() async
    /// エンジンの入力ノードを `device` に向ける。エンジンを開始する前に呼ぶ。
    func bind(_ input: AVAudioInputNode, to device: AudioInputDevice) throws
}
