import SwiftUI

/// メーター・波形・スペクトル・スペクトログラムを毎フレーム描画する。ウィンドウ表示とカード表示で共有する。
///
/// `LevelStore.read()` は読むたびに Peak の保持をリセットするため、読み手は 1 つにする必要がある。
/// 表示していない側は `isActive = false` で描画を止める。
///
/// ウィンドウ表示では各欄を見出し付きのパネル（`MonitorPanel`）に入れる。カード表示では詰めて並べ、
/// メーターのすぐ下に `belowMeters`（カードの入力音量スライダー）を挟む。
struct LiveMonitorView<BelowMeters: View>: View {
    /// カード表示用の詰めたレイアウト（メーターを半分の高さで表示し、dB 目盛りを省く。波形・スペクトル・スペクトログラムは小さく出す）。
    var compact = false
    /// 波形を表示するか。ウィンドウ表示では常に表示し、カード表示では切り替えられる。
    var showsWaveform = true
    /// スペクトルを表示するか。ウィンドウ表示では常に表示し、カード表示では切り替えられる。
    var showsSpectrum = true
    /// カード表示で、スペクトルの欄にスペクトログラムを出すか（欄をクリックすると切り替わる）。
    /// ウィンドウ表示では両方を並べるので使わない。
    var cardShowsSpectrogram: Binding<Bool> = .constant(false)
    let isActive: Bool
    @ViewBuilder var belowMeters: BelowMeters

    /// ウィンドウ表示では常に両方、カード表示ではスペクトルの欄にどちらか一方を出す。
    private var showsSpectrogram: Bool { !compact || (showsSpectrum && cardShowsSpectrogram.wrappedValue) }
    private var showsSpectrumGraph: Bool { !compact || (showsSpectrum && !cardShowsSpectrogram.wrappedValue) }

    @Environment(MonitorModel.self) private var model
    @State private var ballistics = MeterBallistics()
    @State private var spectrumBallistics = SpectrumBallistics()
    @AppStorage(SpectrogramColormap.storageKey) private var colormap = SpectrogramColormap.defaultValue

    private static var frozenNote: String { "停止時点のまま表示" }

    var body: some View {
        if model.isPaused {
            sections(meters: nil, spectrum: nil)
        } else {
            TimelineView(.animation(paused: !model.isRunning || !isActive)) { context in
                sections(
                    meters: ballistics.update(levels: model.levels.read(), now: context.date),
                    // 表示していないときは計算もしない
                    spectrum: showsSpectrumGraph
                        ? spectrumBallistics.update(snapshot: model.spectrum.snapshot(), now: context.date) : nil
                )
            }
        }
    }

    /// `meters` が nil なら計測を止めている（メーターとスペクトルの代わりに「計測を停止中」を出し、
    /// 波形とスペクトログラムは止めた時点のまま表示する）。
    @ViewBuilder
    private func sections(meters: [MeterReading]?, spectrum: [SpectrumBand]?) -> some View {
        let paused = meters == nil
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                if let meters {
                    LevelMeterSection(readings: meters, compact: true, onResetClip: { ballistics.resetClip() })
                } else {
                    PausedNotice(compact: true)
                }
                belowMeters
                if showsWaveform {
                    waveform
                }
                if showsSpectrogram {
                    spectrogram
                        .modifier(CardSpectrumSwitch(isEnabled: !paused, showsSpectrogram: cardShowsSpectrogram))
                }
                // 止めている間、スペクトルは出さない
                if showsSpectrumGraph, let spectrum {
                    SpectrumSection(bands: spectrum, compact: true)
                        .modifier(CardSpectrumSwitch(isEnabled: true, showsSpectrogram: cardShowsSpectrogram))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                MonitorPanel(title: "レベル", caption: "Peak（淡）/ RMS（濃）· dBFS",
                             padding: EdgeInsets(top: 12, leading: 14, bottom: 8, trailing: 14)) {
                    if let meters {
                        LevelMeterSection(readings: meters, compact: false, onResetClip: { ballistics.resetClip() })
                    } else {
                        PausedNotice(compact: false, height: 56)
                    }
                }
                MonitorPanel(title: "波形", caption: "直近 \(model.historySeconds) 秒 · 各側 -60〜0 dBFS",
                             note: paused ? Self.frozenNote : nil) {
                    waveform
                }
                MonitorPanel(title: "スペクトログラム", caption: spectrogramCaption,
                             note: paused ? Self.frozenNote : nil) {
                    spectrogram
                }
                MonitorPanel(title: "スペクトル", caption: "1/12 オクターブ · 塗り＝現在値 / 線＝ピークホールド") {
                    if let spectrum {
                        SpectrumSection(bands: spectrum, compact: false)
                    } else {
                        PausedNotice(compact: false, height: 130)
                    }
                }
            }
        }
    }

    private var waveform: some View {
        WaveformSection(snapshot: model.waveform.snapshot(), seconds: model.historySeconds, compact: compact)
    }

    private var spectrogram: some View {
        SpectrogramSection(snapshot: model.spectrogram.snapshot(), seconds: model.historySeconds, compact: compact)
    }

    private var spectrogramCaption: String {
        "\(colormap.shortName) · 全チャンネル平均 · -100〜0 dBFS"
    }
}

extension LiveMonitorView where BelowMeters == EmptyView {
    init(isActive: Bool) {
        self.init(isActive: isActive) { EmptyView() }
    }
}

/// カード表示で、スペクトルの欄をクリックするとスペクトルとスペクトログラムを切り替える。
/// カードはどこを掴んでもドラッグで移動できるので、ボタンではなくタップのジェスチャーにする（動かすとタップにならない）。
private struct CardSpectrumSwitch: ViewModifier {
    let isEnabled: Bool
    @Binding var showsSpectrogram: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contentShape(Rectangle())
                .onTapGesture { showsSpectrogram.toggle() }
                .help(showsSpectrogram ? "クリックでスペクトルに切り替え" : "クリックでスペクトログラムに切り替え")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(showsSpectrogram ? "スペクトルに切り替えます" : "スペクトログラムに切り替えます")
        } else {
            content
        }
    }
}
