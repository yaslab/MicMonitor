import AVFoundation
import Synchronization

/// リアルタイムスレッド（書き込み 1 本）から別スレッド（読み出し 1 本）へサンプルを渡す、ロックなしのリングバッファ。
///
/// `write` は `AVAudioSinkNode` のリアルタイムスレッドから呼ぶため、ロック・メモリ確保・待ちをしない。
/// 読み出しが追いつかず空きが足りないときは、そのブロックを捨てて `droppedFrames` に数える。
final class SampleRingBuffer: @unchecked Sendable {
    let channelCount: Int
    /// チャンネルあたりのフレーム数。
    let capacity: Int

    private let storage: [UnsafeMutablePointer<Float>]
    /// 書き込み・読み出しの累計フレーム数（単調増加。位置は capacity で割った余り）。
    private let writeCount = Atomic<Int>(0)
    private let readCount = Atomic<Int>(0)
    private let dropped = Atomic<Int>(0)
    private let writeCalls = Atomic<Int>(0)

    init(channelCount: Int, capacity: Int) {
        self.channelCount = channelCount
        self.capacity = capacity
        storage = (0..<channelCount).map { _ in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
            pointer.initialize(repeating: 0, count: capacity)
            return pointer
        }
    }

    deinit {
        storage.forEach { $0.deallocate() }
    }

    var droppedFrames: Int { dropped.load(ordering: .relaxed) }
    /// `write` が呼ばれた回数（計測用）。
    var writeCallCount: Int { writeCalls.load(ordering: .relaxed) }

    /// 書き込み側（リアルタイムスレッド）。非インターリーブの Float32 を想定。
    func write(_ bufferList: UnsafePointer<AudioBufferList>, frameCount: Int) {
        writeCalls.add(1, ordering: .relaxed)
        guard frameCount > 0 else { return }
        let written = writeCount.load(ordering: .relaxed)
        let read = readCount.load(ordering: .acquiring)
        guard frameCount <= capacity - (written - read) else {
            dropped.add(frameCount, ordering: .relaxed)
            return
        }

        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        let start = written % capacity
        let firstPart = min(frameCount, capacity - start)
        for ch in 0..<min(channelCount, buffers.count) {
            guard let source = buffers[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
            let destination = storage[ch]
            (destination + start).update(from: source, count: firstPart)
            if firstPart < frameCount {
                destination.update(from: source + firstPart, count: frameCount - firstPart)
            }
        }
        writeCount.store(written + frameCount, ordering: .releasing)
    }

    /// 読み出し側。`buffer` の容量まで読み、`frameLength` を設定して読んだフレーム数を返す。
    func read(into buffer: AVAudioPCMBuffer) -> Int {
        guard let destination = buffer.floatChannelData else { return 0 }
        let read = readCount.load(ordering: .relaxed)
        let written = writeCount.load(ordering: .acquiring)
        let frames = min(written - read, Int(buffer.frameCapacity))
        guard frames > 0 else {
            buffer.frameLength = 0
            return 0
        }

        let start = read % capacity
        let firstPart = min(frames, capacity - start)
        for ch in 0..<min(channelCount, Int(buffer.format.channelCount)) {
            let source = storage[ch]
            destination[ch].update(from: source + start, count: firstPart)
            if firstPart < frames {
                (destination[ch] + firstPart).update(from: source, count: frames - firstPart)
            }
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        readCount.store(read + frames, ordering: .releasing)
        return frames
    }
}
