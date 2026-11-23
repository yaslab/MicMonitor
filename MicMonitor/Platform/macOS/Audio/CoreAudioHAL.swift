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

    // MARK: - 汎用の読み書き

    /// 固定長のプロパティを読む。`initial` は読み込み先の初期値（型と大きさを決める）。
    private static func value<T>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, initial: T) -> T? {
        var addr = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0) }
        return status == noErr ? value : nil
    }

    /// CF オブジェクト（CFString・CFDictionary など）のプロパティを読む。HAL は +1 で返す。
    private static func object<T: AnyObject>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        guard let unmanaged = value(id, address, initial: Unmanaged<T>?.none) ?? nil else { return nil }
        return unmanaged.takeRetainedValue()
    }

    private static func setValue<T>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, _ newValue: T) -> Bool {
        var addr = address
        let status = withUnsafePointer(to: newValue) {
            AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
        return status == noErr
    }

    private static func hasProperty(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var addr = address
        return AudioObjectHasProperty(id, &addr)
    }

    private static func isSettable(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var addr = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &addr, &settable) == noErr && settable.boolValue
    }

    // MARK: - デバイス

    static func deviceIDs() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        let id = value(systemObject, address(kAudioHardwarePropertyDefaultInputDevice),
                       initial: AudioDeviceID(kAudioObjectUnknown))
        return id == kAudioObjectUnknown ? nil : id
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        let value: CFString? = object(id, address(selector))
        return value as String?
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
        value(id, address(kAudioDevicePropertyTransportType), initial: UInt32(0))
    }

    /// プライベートな集約デバイスか。
    ///
    /// AVAudioEngine などが既定の入出力を束ねるために自動で作る `CADefaultDeviceAggregate-<pid>-<n>` が該当する。
    /// 作成したプロセスにしか見えず、エンジンの作り直しで消えるため、入力デバイスの候補から除く。
    /// ユーザーが Audio MIDI 設定で作った集約デバイスはプライベートではないので残る。
    static func isPrivateAggregate(_ id: AudioDeviceID) -> Bool {
        guard transportType(id) == kAudioDeviceTransportTypeAggregate,
              let composition: CFDictionary = object(id, address(kAudioAggregateDevicePropertyComposition))
        else { return false }
        return ((composition as NSDictionary)[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue ?? false
    }

    // MARK: - 入力音量

    static func inputVolumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: element)
    }

    /// 入力音量を持つ要素。マスター（要素 0）があればそれだけ、なければ音量を持つチャンネル（要素 1...n）。
    static func inputVolumeElements(_ id: AudioDeviceID) -> [AudioObjectPropertyElement] {
        if hasProperty(id, inputVolumeAddress(element: kAudioObjectPropertyElementMain)) {
            return [kAudioObjectPropertyElementMain]
        }
        let channels = inputChannelCount(id)
        guard channels > 0 else { return [] }
        return (1...UInt32(channels)).filter { hasProperty(id, inputVolumeAddress(element: $0)) }
    }

    static func isInputVolumeSettable(_ id: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        isSettable(id, inputVolumeAddress(element: element))
    }

    static func inputVolume(_ id: AudioDeviceID, element: AudioObjectPropertyElement) -> Float? {
        value(id, inputVolumeAddress(element: element), initial: Float32(0))
    }

    @discardableResult
    static func setInputVolume(_ id: AudioDeviceID, element: AudioObjectPropertyElement, _ volume: Float) -> Bool {
        setValue(id, inputVolumeAddress(element: element), Float32(min(max(volume, 0), 1)))
    }

    /// 入力音量の dB 値（デバイスが dB 換算に対応していない場合は nil）。
    static func inputVolumeDecibels(_ id: AudioDeviceID, element: AudioObjectPropertyElement) -> Float? {
        value(id, address(kAudioDevicePropertyVolumeDecibels, scope: kAudioObjectPropertyScopeInput, element: element),
              initial: Float32(0))
    }

    /// 入力音量の dB の範囲。
    static func inputVolumeDecibelRange(_ id: AudioDeviceID, element: AudioObjectPropertyElement) -> ClosedRange<Float>? {
        let addr = address(kAudioDevicePropertyVolumeRangeDecibels, scope: kAudioObjectPropertyScopeInput, element: element)
        guard let range = value(id, addr, initial: AudioValueRange()), range.mMinimum <= range.mMaximum else { return nil }
        return Float(range.mMinimum)...Float(range.mMaximum)
    }

    // MARK: - 入力ミュート

    static func inputMuteAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput, element: element)
    }

    static func isInputMuteSettable(_ id: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        let addr = inputMuteAddress(element: element)
        return hasProperty(id, addr) && isSettable(id, addr)
    }

    static func isInputMuted(_ id: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool? {
        value(id, inputMuteAddress(element: element), initial: UInt32(0)).map { $0 != 0 }
    }

    @discardableResult
    static func setInputMuted(_ id: AudioDeviceID, element: AudioObjectPropertyElement, _ muted: Bool) -> Bool {
        setValue(id, inputMuteAddress(element: element), UInt32(muted ? 1 : 0))
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
    @discardableResult
    static func addListener(
        _ objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        handler: @escaping @MainActor @Sendable () -> Void
    ) -> PropertyListener? {
        var addr = address
        // nonisolated な文脈でクロージャを作り、MainActor 分離の実行時チェックを避ける。
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
    /// アプリの寿命と同じだけ使う前提のため、解除しない（登録したリスナーは捨てる）。
    static func addSystemListener(
        _ selector: AudioObjectPropertySelector,
        handler: @escaping @MainActor @Sendable () -> Void
    ) {
        addListener(systemObject, address: address(selector), handler: handler)
    }
}
