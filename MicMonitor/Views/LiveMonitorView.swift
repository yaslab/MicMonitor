import SwiftUI

/// メーター・波形・スペクトル・スペクトログラムを毎フレーム描画する。ウィンドウ表示とカード表示で共有する。
///
/// `LevelStore.read()` は読むたびに Peak の保持をリセットするため、読み手は 1 つにする必要がある。
/// 表示していない側は `isActive = false` で描画を止める。
///
/// ウィンドウ表示では各欄を見出し付きのパネル（`MonitorPanel`）に入れる。カード表示では詰めて並べ、
/// メーターのすぐ下に `belowMeters`（カードの入力音量スライダー）を挟む。
///
/// iOS では `leading`（入力のカード）と `trailing`（モニター再生）も一緒に並べる。1 列なら上から
/// leading・レベル・波形・スペクトログラム・スペクトル・trailing、2 列なら左の列に操作（leading・trailing）、
/// 右の列に計測（レベル・波形・スペクトログラム・スペクトル）。メーターのバーを広く取るため、レベルは右の列に置く。
struct LiveMonitorView<BelowMeters: View, Leading: View, Trailing: View>: View {
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
    /// 2 列にするときの左の列の幅（nil なら 1 列）。
    var leftColumnWidth: CGFloat?
    @ViewBuilder var belowMeters: BelowMeters
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    /// ウィンドウ表示では常に両方、カード表示ではスペクトルの欄にどちらか一方を出す。
    private var showsSpectrogram: Bool { !compact || (showsSpectrum && cardShowsSpectrogram.wrappedValue) }
    private var showsSpectrumGraph: Bool { !compact || (showsSpectrum && !cardShowsSpectrogram.wrappedValue) }

    @Environment(MonitorModel.self) private var model
    @Environment(\.monitorMetrics) private var metrics
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
        } else if let leftColumnWidth {
            HStack(alignment: .top, spacing: metrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    leading
                    trailing
                }
                .frame(width: leftColumnWidth)
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    levelPanel(meters)
                    graphPanels(paused: paused, spectrum: spectrum)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                leading
                levelPanel(meters)
                graphPanels(paused: paused, spectrum: spectrum)
                trailing
            }
        }
    }

    private func levelPanel(_ meters: [MeterReading]?) -> some View {
        MonitorPanel(title: "レベル", caption: "Peak（淡）/ RMS（濃）· dBFS", padding: metrics.meterPanelPadding) {
            if let meters {
                LevelMeterSection(readings: meters, compact: false, onResetClip: { ballistics.resetClip() })
                    .axisTypeSize()
            } else {
                PausedNotice(compact: false, height: metrics.pausedMeterHeight)
            }
        }
    }

    @ViewBuilder
    private func graphPanels(paused: Bool, spectrum: [SpectrumBand]?) -> some View {
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
                    .axisTypeSize()
            } else {
                PausedNotice(compact: false, height: metrics.pausedSpectrumHeight)
            }
        }
    }

    // グラフの欄は文字の大きさに上限を付ける（欄の中の @ScaledMetric もこの上限で計算される）
    private var waveform: some View {
        WaveformSection(snapshot: model.waveform.snapshot(), seconds: model.historySeconds, compact: compact)
            .axisTypeSize()
    }

    private var spectrogram: some View {
        SpectrogramSection(snapshot: model.spectrogram.snapshot(), seconds: model.historySeconds, compact: compact)
            .axisTypeSize()
    }

    private var spectrogramCaption: String {
        "\(colormap.shortName) · 全チャンネル平均 · -100〜0 dBFS"
    }
}

extension LiveMonitorView where Leading == EmptyView, Trailing == EmptyView {
    /// カード表示用（メーターの下に `belowMeters` を挟む）。
    init(compact: Bool = false, showsWaveform: Bool = true, showsSpectrum: Bool = true,
         cardShowsSpectrogram: Binding<Bool> = .constant(false), isActive: Bool,
         @ViewBuilder belowMeters: () -> BelowMeters) {
        self.init(compact: compact, showsWaveform: showsWaveform, showsSpectrum: showsSpectrum,
                  cardShowsSpectrogram: cardShowsSpectrogram, isActive: isActive, leftColumnWidth: nil,
                  belowMeters: belowMeters, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

extension LiveMonitorView where BelowMeters == EmptyView, Leading == EmptyView, Trailing == EmptyView {
    /// Mac のウィンドウ表示用。
    init(isActive: Bool) {
        self.init(isActive: isActive) { EmptyView() }
    }
}

extension LiveMonitorView where BelowMeters == EmptyView {
    /// iOS の画面用。`leftColumnWidth` を渡すと 2 列にする。
    init(isActive: Bool, leftColumnWidth: CGFloat?,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.init(isActive: isActive, leftColumnWidth: leftColumnWidth,
                  belowMeters: { EmptyView() }, leading: leading, trailing: trailing)
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
