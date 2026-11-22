import Accelerate
import Synchronization

struct SpectrumSnapshot: Sendable {
    /// FFT のビンごとの振幅（線形。フルスケールの正弦波が 1 になるように正規化）。
    /// `amplitudes[k]` の周波数は `k * binWidth` Hz。全チャンネルのパワーの平均。
    var amplitudes: [Float]
    var binWidth: Double

    static let empty = SpectrumSnapshot(amplitudes: [], binWidth: 0)
}

/// 直近のサンプルをチャンネルごとに保持し、読み出し時に FFT（Hann 窓）で振幅スペクトルを求める。
///
/// 書き込みはポンプのキュー、`snapshot()` は MainActor から呼ぶ。FFT は読み出し時に Mutex の中で行う
/// （4096 点 × ch 数で数十 µs 程度なので、ポンプを待たせる時間は短い）。
final class SpectrumAnalyzer: @unchecked Sendable {
    /// 対応する最大の FFT 長（2 の累乗の指数）。
    private static let maxLog2n = 13

    private struct State {
        var log2n = 12
        var sampleRate: Double = 48_000
        /// チャンネルごとの直近 `size` サンプルのリングバッファ。
        var rings: [[Float]] = []
        var head = 0
        var window: [Float] = []
        // FFT 用の作業領域（読み出しのたびに確保しないよう保持する）
        var windowed: [Float] = []
        var real: [Float] = []
        var imag: [Float] = []
        var magnitudes: [Float] = []
        var powerSum: [Float] = []

        var size: Int { 1 << log2n }
        var channelCount: Int { rings.count }
    }

    /// `state` の中でのみ使う（FFT の呼び出しは Mutex で直列化される）。
    private let fftSetup: FFTSetup
    private let state = Mutex(State())

    init() {
        fftSetup = vDSP_create_fftsetup(vDSP_Length(Self.maxLog2n), FFTRadix(kFFTRadix2))!
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// 分解能が 10〜20 Hz 程度になるよう、サンプルレートから FFT 長を決める（48 kHz で 4096 点 ≈ 11.7 Hz、85 ms）。
    func configure(channelCount: Int, sampleRate: Double) {
        state.withLock { state in
            state.sampleRate = sampleRate
            state.log2n = sampleRate > 64_000 ? 13 : 12
            let size = state.size
            state.rings = Array(repeating: Array(repeating: 0, count: size), count: channelCount)
            state.head = 0
            state.window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                       count: size, isHalfWindow: false)
            state.windowed = Array(repeating: 0, count: size)
            state.real = Array(repeating: 0, count: size / 2)
            state.imag = Array(repeating: 0, count: size / 2)
            state.magnitudes = Array(repeating: 0, count: size / 2)
            state.powerSum = Array(repeating: 0, count: size / 2)
        }
    }

    func reset() {
        state.withLock { state in
            for ch in state.rings.indices {
                state.rings[ch].withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
            }
            state.head = 0
        }
    }

    func process(_ data: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int, frameCount: Int) {
        guard frameCount > 0 else { return }
        state.withLock { state in
            let channels = min(channelCount, state.channelCount)
            guard channels > 0 else { return }
            let size = state.size
            // バッファより長く届いたときは末尾の `size` サンプルだけを使う
            let skip = max(0, frameCount - size)
            let count = frameCount - skip
            let head = state.head
            let firstPart = min(count, size - head)
            for ch in 0..<channels {
                let source = UnsafePointer(data[ch] + skip)
                state.rings[ch].withUnsafeMutableBufferPointer { ring in
                    let base = ring.baseAddress!
                    (base + head).update(from: source, count: firstPart)
                    if firstPart < count {
                        base.update(from: source + firstPart, count: count - firstPart)
                    }
                }
            }
            state.head = (head + count) % size
        }
    }

    func snapshot() -> SpectrumSnapshot {
        state.withLock { state in
            let channels = state.channelCount
            guard channels > 0 else { return .empty }
            let size = state.size
            let half = size / 2
            let head = state.head
            let log2n = vDSP_Length(state.log2n)
            state.powerSum.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }

            for ch in 0..<channels {
                // 古い順に並べながら窓を掛ける
                state.rings[ch].withUnsafeBufferPointer { ring in
                    state.window.withUnsafeBufferPointer { window in
                        state.windowed.withUnsafeMutableBufferPointer { out in
                            let older = size - head
                            vDSP_vmul(ring.baseAddress! + head, 1, window.baseAddress!, 1,
                                      out.baseAddress!, 1, vDSP_Length(older))
                            if head > 0 {
                                vDSP_vmul(ring.baseAddress!, 1, window.baseAddress! + older, 1,
                                          out.baseAddress! + older, 1, vDSP_Length(head))
                            }
                        }
                    }
                }
                state.real.withUnsafeMutableBufferPointer { real in
                    state.imag.withUnsafeMutableBufferPointer { imag in
                        var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imag.baseAddress!)
                        state.windowed.withUnsafeBufferPointer { input in
                            input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                            }
                        }
                        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                        // imag[0] にはナイキスト周波数の成分が入っている。DC だけを残す
                        imag[0] = 0
                        state.magnitudes.withUnsafeMutableBufferPointer { magnitudes in
                            vDSP_zvmags(&split, 1, magnitudes.baseAddress!, 1, vDSP_Length(half))
                        }
                    }
                }
                vDSP.add(state.powerSum, state.magnitudes, result: &state.powerSum)
            }

            // zrip の出力は DFT の 2 倍。Hann 窓の総和は size / 2 なので、
            // 振幅 = 2|X| / Σw = |出力| / (size / 2)。チャンネル間はパワーで平均する
            let scale = 1 / (Float(channels) * Float(half) * Float(half))
            var amplitudes = vDSP.multiply(scale, state.powerSum)
            vForce.sqrt(amplitudes, result: &amplitudes)
            return SpectrumSnapshot(amplitudes: amplitudes, binWidth: state.sampleRate / Double(size))
        }
    }
}
