import AVFoundation

/// macOS: オーディオセッションはないので、入力デバイスはエンジンの入力ノードに直接指定する
/// （`AUAudioUnit.setDeviceID(_:)`）。セッションの出来事も起きない。
@MainActor
final class AudioSessionController: AudioSessionControlling {
    var onEvent: ((AudioSessionEvent) -> Void)?

    func activate(preferredInputUID: String?, monitoring: Bool) async throws {}

    func deactivate() async {}

    func bind(_ input: AVAudioInputNode, to device: AudioInputDevice) throws {
        try input.withAUAudioUnit { unit in try unit.setDeviceID(device.id) }
    }
}
