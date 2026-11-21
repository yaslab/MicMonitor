import SwiftUI

/// メーターと波形を毎フレーム描画する。ウィンドウ表示とカード表示で共有する。
///
/// `LevelStore.read()` は読むたびに Peak の保持をリセットするため、読み手は 1 つにする必要がある。
/// 表示していない側は `isActive = false` で描画を止める。
struct LiveMonitorView: View {
    /// カード表示用の詰めたレイアウト（dB 目盛りと時間軸を省く）。
    var compact = false
    var isActive = true

    @Environment(MonitorModel.self) private var model
    @State private var ballistics = MeterBallistics()

    var body: some View {
        TimelineView(.animation(paused: !model.isRunning || !isActive)) { context in
            let readings = ballistics.update(levels: model.levels.read(), now: context.date)
            let snapshot = model.waveform.snapshot()
            VStack(alignment: .leading, spacing: compact ? 8 : 16) {
                LevelMeterSection(readings: readings, showsScale: !compact, onResetClip: { model.resetClip() })
                WaveformSection(snapshot: snapshot, seconds: model.historySeconds, showsTimeAxis: !compact)
            }
        }
    }
}
