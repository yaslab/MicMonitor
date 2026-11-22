import SwiftUI

/// メーター・波形・スペクトルを毎フレーム描画する。ウィンドウ表示とカード表示で共有する。
///
/// `LevelStore.read()` は読むたびに Peak の保持をリセットするため、読み手は 1 つにする必要がある。
/// 表示していない側は `isActive = false` で描画を止める。
struct LiveMonitorView: View {
    /// カード表示用の詰めたレイアウト（メーターを半分の高さで表示し、dB 目盛りを省く。波形とスペクトルは小さく出す）。
    var compact = false
    /// 波形を表示するか。ウィンドウ表示では常に表示し、カード表示では切り替えられる。
    var showsWaveform = true
    /// スペクトルを表示するか。ウィンドウ表示では常に表示し、カード表示では切り替えられる。
    var showsSpectrum = true
    let isActive: Bool

    @Environment(MonitorModel.self) private var model
    @State private var ballistics = MeterBallistics()
    @State private var spectrumBallistics = SpectrumBallistics()

    var body: some View {
        if model.isPaused {
            paused
        } else {
            live
        }
    }

    /// 計測を止めている間。メーターとスペクトルは出さず、波形は止めた時点のまま表示する。
    private var paused: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 16) {
            PausedNotice(compact: compact)
            if showsWaveform {
                WaveformSection(snapshot: model.waveform.snapshot(), seconds: model.historySeconds,
                                compact: compact)
            }
        }
    }

    private var live: some View {
        TimelineView(.animation(paused: !model.isRunning || !isActive)) { context in
            let readings = ballistics.update(levels: model.levels.read(), now: context.date)
            VStack(alignment: .leading, spacing: compact ? 8 : 16) {
                LevelMeterSection(readings: readings, showsScale: !compact, compact: compact,
                                  onResetClip: { ballistics.resetClip() })
                if showsWaveform {
                    WaveformSection(snapshot: model.waveform.snapshot(), seconds: model.historySeconds,
                                    compact: compact)
                }
                if showsSpectrum {
                    SpectrumSection(bands: spectrumBallistics.update(snapshot: model.spectrum.snapshot(),
                                                                     now: context.date),
                                    compact: compact)
                }
            }
        }
    }
}
