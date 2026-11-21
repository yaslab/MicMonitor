import CoreAudio

/// 入力チャンネルを持つ Core Audio デバイス。
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    /// 再起動・再接続をまたいで変わらない識別子。
    let uid: String
    let name: String
    let inputChannelCount: Int
}
