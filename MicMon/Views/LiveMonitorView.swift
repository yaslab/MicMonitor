import SwiftUI

/// メーター・波形・スペクトルを毎フレーム描画する。ウィンドウ表示とカード表示で共有する。
///
/// `LevelStore.read()` は読むたびに Peak の保持をリセットするため、読み手は 1 つにする必要がある。
/// 表示していない側は `isActive = false` で描画を止める。
struct LiveMonitorView: View {
    /// カード表示用の詰めたレイアウト（メーターを半分の高さで表示し、dB 目盛りと波形を省く。スペクトルは小さく出す）。
    var compact = false
    var isActive = true

    @Environment(MonitorModel.self) private var model
    @State private var ballistics = MeterBallistics()
    @State private var spectrumBallistics = SpectrumBallistics()

    var body: some View {
        TimelineView(.animation(paused: !model.isRunning || !isActive)) { context in
            let readings = ballistics.update(levels: model.levels.read(), now: context.date)
            let bands = spectrumBallistics.update(snapshot: model.spectrum.snapshot(), now: context.date)
            VStack(alignment: .leading, spacing: compact ? 8 : 16) {
                LevelMeterSection(readings: readings, showsScale: !compact, compact: compact,
                                  onResetClip: { ballistics.resetClip() })
                if !compact {
                    WaveformSection(snapshot: model.waveform.snapshot(), seconds: model.historySeconds)
                }
                SpectrumSection(bands: bands, compact: compact)
            }
        }
    }
}
