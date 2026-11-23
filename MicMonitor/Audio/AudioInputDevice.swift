/// 入力チャンネルを持つオーディオデバイス。
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// OS がデバイスを指すための ID（macOS は `AudioDeviceID` で再接続すると変わる。iOS は入力ポートの UID）。
    let id: AudioDeviceHandle
    /// 再起動・再接続をまたいで変わらない識別子。
    let uid: String
    let name: String
    let inputChannelCount: Int
}
