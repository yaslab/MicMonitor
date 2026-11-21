import CoreAudio
import Foundation

/// Core Audio HAL のプロパティ取得とリスナー登録のヘルパー。
enum CoreAudioHAL {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func deviceIDs() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &id)
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func transportType(_ id: AudioDeviceID) -> UInt32? {
        var addr = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// プライベートな集約デバイスか。
    ///
    /// AVAudioEngine などが既定の入出力を束ねるために自動で作る `CADefaultDeviceAggregate-<pid>-<n>` が該当する。
    /// 作成したプロセスにしか見えず、エンジンの作り直しで消えるため、入力デバイスの候補から除く。
    /// ユーザーが Audio MIDI 設定で作った集約デバイスはプライベートではないので残る。
    static func isPrivateAggregate(_ id: AudioDeviceID) -> Bool {
        guard transportType(id) == kAudioDeviceTransportTypeAggregate else { return false }
        var addr = address(kAudioAggregateDevicePropertyComposition)
        var value: Unmanaged<CFDictionary>?
        var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return false }
        let composition = value.takeRetainedValue() as NSDictionary
        return (composition[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue ?? false
    }

    // MARK: - 入力音量

    static func inputVolumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: element)
    }

    /// 入力音量を持つ要素。マスター（要素 0）があればそれだけ、なければ音量を持つチャンネル（要素 1...n）。
    static func inputVolumeElements(_ id: AudioDeviceID) -> [AudioObjectPropertyElement] {
        var master = inputVolumeAddress(element: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(id, &master) { return [kAudioObjectPropertyElementMain] }
        let channels = inputChannelCount(id)
        guard channels > 0 else { return [] }
        return (1...UInt32(channels)).filter { element in
            var addr = inputVolumeAddress(element: element)
            return AudioObjectHasProperty(id, &addr)
        }
    }

    static func isInputVolumeSettable(_ id: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        var addr = inputVolumeAddress(element: element)
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &addr, &settable) == noErr && settable.boolValue
    }

    static func inputVolume(_ id: AudioDeviceID, element: AudioObjectPropertyElement) -> Float? {
        var addr = inputVolumeAddress(element: element)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    @discardableResult
    static func setInputVolume(_ id: AudioDeviceID, element: AudioObjectPropertyElement, _ volume: Float) -> Bool {
        var addr = inputVolumeAddress(element: element)
        var value = Float32(min(max(volume, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(id, &addr, 0, nil, size, &value) == noErr
    }

    // MARK: - リスナー

    /// 登録したリスナー。解除には登録時と同じブロックが必要なため保持しておく。
    final class PropertyListener {
        fileprivate let objectID: AudioObjectID
        fileprivate var address: AudioObjectPropertyAddress
        fileprivate let block: AudioObjectPropertyListenerBlock

        fileprivate init(objectID: AudioObjectID, address: AudioObjectPropertyAddress, block: @escaping AudioObjectPropertyListenerBlock) {
            self.objectID = objectID
            self.address = address
            self.block = block
        }
    }

    /// 任意のオブジェクトのプロパティ変化を監視する。handler はメインスレッドで呼ばれる。
    static func addListener(
        _ objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        handler: @escaping @MainActor @Sendable () -> Void
    ) -> PropertyListener? {
        var addr = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        guard AudioObjectAddPropertyListenerBlock(objectID, &addr, DispatchQueue.main, block) == noErr else { return nil }
        return PropertyListener(objectID: objectID, address: address, block: block)
    }

    /// デバイスが既に外れている場合は失敗するが、無視してよい。
    static func removeListener(_ listener: PropertyListener) {
        _ = AudioObjectRemovePropertyListenerBlock(listener.objectID, &listener.address, DispatchQueue.main, listener.block)
    }

    /// システムオブジェクトのプロパティ変化を監視する。handler はメインスレッドで呼ばれる。
    /// アプリの寿命と同じだけ使う前提のため、解除の API は用意していない。
    static func addSystemListener(
        _ selector: AudioObjectPropertySelector,
        handler: @escaping @MainActor @Sendable () -> Void
    ) {
        var addr = address(selector)
        // nonisolated な文脈でクロージャを作り、MainActor 分離の実行時チェックを避ける。
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        _ = AudioObjectAddPropertyListenerBlock(systemObject, &addr, DispatchQueue.main, block)
    }
}
