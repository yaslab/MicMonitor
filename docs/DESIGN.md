# MicMon 設計書 v0.3

Mac のマイク入力をリアルタイムでモニタリングする macOS アプリ。用途は自分用（デバッグ実行）。

## 1. 要件

### 1.1 機能要件

| # | 機能 | 内容 |
|---|------|------|
| F1 | マイク選択 | 接続中の入力デバイスを一覧表示して選択。先頭に「システム既定」 |
| F2 | レベル表示 | チャンネルごとのレベルメーター（Peak + RMS、dBFS） |
| F3 | 波形履歴 | チャンネルごとに直近 N 秒分の波形（縦軸 dB スケール）をスクロール表示 |
| F4 | 設定 | N（1〜60 秒、既定 10 秒）を設定画面（⌘,）で変更 |
| F5 | モニター再生 | 入力音をシステム既定の出力デバイスで再生。オン/オフと音量 |
| F6 | 入力音量 | 選択中デバイスのシステム入力音量（システム設定 > サウンド > 入力 と同じ値）を表示・変更 |

### 1.2 決定事項

- 対象: macOS 26.0 以降のみ。Swift 6 言語モード、Default Actor Isolation は指定なし（nonisolated）
- メーター: 表示レンジ -60〜0 dBFS、Peak（淡色）と RMS（濃色）、ピークホールド 1.5 秒、クリップ表示（-0.1 dBFS 以上で点灯、クリックで解除）
- 波形: チャンネルごとに 1 段。縦軸は dB スケール（-60〜0 dBFS、中心から上下対称）
- ウィンドウ: 通常ウィンドウ 1 枚（`Window` シーン）。閉じたらアプリ終了
- 「システム既定」選択時は OS 側の既定マイク変更に追従
- 選択中のデバイスが外れたらシステム既定で継続し、再接続されたら元のデバイスに戻す
- 選択デバイス・N・モニター再生のオン/オフと音量は UserDefaults に保存
- 対象外: 録音・保存、他のウィンドウ形態（必要なら別途）
- 配布: 自分用。署名・公証は考慮しない

## 2. 技術選定

| 領域 | 採用 | 理由 |
|------|------|------|
| UI | SwiftUI（`Window` + `Settings` シーン） | |
| 状態管理 | Observation (`@Observable`, `@MainActor`) | |
| デバイス一覧・変更通知 | Core Audio HAL (`AudioObject*`) | 入力ch数・UID の取得、追加/削除・既定デバイス変更の監視ができる |
| 音声入出力 | AVAudioEngine。入力デバイスは `inputNode.auAudioUnit.setDeviceID(_:)` で指定 | タップでのバッファ取得と、モニター再生のミキサー接続が簡単 |
| 信号処理 | Accelerate (vDSP) | |
| 描画 | SwiftUI `Canvas` + `TimelineView(.animation)` | |
| スレッド間共有 | `Synchronization.Mutex` | |

AVAudioEngine でデバイス切り替えが不安定な場合は、AUHAL を直接使う実装に差し替える（`AudioCaptureEngine` の中だけで閉じるようにしてある）。

## 3. アーキテクチャ

```
MainActor                                         タップのスレッド（AVAudioEngine 内部）
─────────────────────────────────────────         ──────────────────────────────────────
ContentView ─ TimelineView(.animation)            AVAudioEngine
  ├ DevicePicker                                    inputNode ──tap──▶ LevelStore.process
  ├ LevelMeterSection ◀── levels.read() ───┐           │          └──▶ WaveformHistory.process
  ├ WaveformSection  ◀── waveform.snapshot()┤           └─(モニター時)─▶ MonitorPlayback（別エンジン）─▶ 出力
  └ MonitorControls                         │
SettingsView                                │     LevelStore / WaveformHistory は
MonitorModel ── AudioCaptureEngine ─────────┘     Mutex で保護された Sendable クラス
     └── AudioDeviceManager（HAL リスナー）
```

| 型 | 責務 | 分離 |
|----|------|------|
| `AudioInputDevice` | `id`, `uid`, `name`, `inputChannelCount` | 値型 |
| `DeviceSelection` | `.systemDefault` / `.device(uid:)`。UID で保存（`AudioDeviceID` は再接続で変わるため） | 値型 |
| `CoreAudioHAL` | HAL プロパティ取得・リスナー登録のヘルパー | nonisolated |
| `InputVolumeController` | 使用中デバイスの入力音量の読み書きと、外部での変更の監視 | MainActor |
| `AudioDeviceManager` | 入力デバイス一覧と既定入力デバイスを保持。変化したら `onChange` を呼ぶ | MainActor |
| `AudioCaptureEngine` | エンジン構築・タップ・停止。構成変更通知を中継 | MainActor（タップ処理は nonisolated） |
| `MonitorPlayback` | 出力専用の AVAudioEngine。タップのバッファをコピーして `AVAudioPlayerNode` で再生 | 予約はタップのスレッド、それ以外は MainActor |
| `LevelStore` | ch ごとの Peak（前回の読み出し以降の最大値）・RMS・クリップ | Sendable + Mutex |
| `WaveformHistory` | ch ごとのリングバッファ（ビンごとに Peak と RMS） | Sendable + Mutex |
| `MeterBallistics` | 表示側の減衰とピークホールド | MainActor（View が所有） |
| `MonitorModel` | 権限、選択、設定、エンジンの再構成を統括 | MainActor |

### 3.1 スレッドの方針

- `installTap` のコールバックは IO スレッドではないため、短時間の Mutex なら使ってよい。コールバック内ではメモリ確保と MainActor への hop をしない。
- タップのクロージャは `nonisolated` な関数の中で生成する（MainActor のコンテキストで作ると、Swift 6 の実行時の分離チェックでクラッシュするため）。
- UI は毎フレーム、ストアからスナップショットを取得して描画する（プル型）。

### 3.2 エンジンの再構成

次の場合にエンジンを作り直す（数十 ms 途切れる）。

- 解決したデバイスの ID が変わった（選択変更、デバイスの抜き差し、既定デバイスの変更）
- モニター再生のオン/オフ（オフのときは出力側に一切接続しない）
- `AVAudioEngineConfigurationChange` 通知（サンプルレート変更など）。300 ms 待ってから作り直す
  - この通知は起動直後にも届くため、エンジンが止まっているか、入力フォーマットが変わったときだけ作り直す（毎回作り直すと再起動のループになる）

ch 数が変わらなければ波形履歴は保持する。

## 4. 信号処理

### 4.1 レベル

- バッファ（約 1024 フレーム）ごとに ch ごとに `vDSP_maxmgv`（Peak）と `vDSP_rmsqv`（RMS）を計算する。
- Peak は UI が読むまで最大値を保持し、読んだらリセットする（取りこぼしを防ぐため）。
- 表示側: アタックは即時、リリースは 20 dB/秒、ピークホールドは 1.5 秒保持してから 20 dB/秒で下げる。
- 色分け: 緑（〜-18 dB）、黄（〜-6 dB）、赤（-6 dB〜）。

### 4.2 波形履歴

- 200 ビン/秒（5 ms/ビン）に間引く。1 ビン = Peak（`vDSP_maxmgv`）と RMS（`vDSP_svesq` の合計から計算）。
- バッファ境界をまたぐビンは累積値を持ち越して計算する。
- 容量 = N × 200（60 秒 × 2ch でも約 190KB）。N を変えたら、最新のものから入る分だけ引き継ぐ。
- 描画: 横幅のピクセル列ごとに該当するビンの最大値を取り、dB → 0〜1 に正規化して中心から上下対称に描く。Peak は淡色、RMS は濃色で塗る。

## 5. モニター再生

- macOS の AVAudioEngine は inputNode と outputNode で 1 つの I/O ユニットを共有する。入力デバイスを指定したエンジンの出力はそのデバイス（入力専用なら 0 ch）になり、別デバイスへの出力は初期化に失敗する（-10875）。
- そのため再生は**出力専用の別エンジン**（`MonitorPlayback`）で行う。タップで受け取ったバッファをコピーし、`AVAudioPlayerNode.scheduleBuffer` で予約する。出力先はシステム既定の出力デバイスで、サンプルレートの違いは mainMixer が変換する。
- 再生待ちが 250 ms を超えたら入力を捨て、クロック差で遅延が増え続けないようにする。遅延はタップのバッファ長ぶん（数十〜100 ms 程度）。
- 再生の開始に失敗しても計測は続け、モニター操作の下にエラーを表示する。
- 再生側のエンジンが止まったら（出力デバイスの変更など）全体を再構成する。
- 既定はオフ。ハウリング防止のため、UI にヘッドホン使用の注意を出す。
- 入力が 3ch 以上のデバイスでは無効にする（ミキサーのチャンネルレイアウトが合わずに例外で落ちるのを避けるため）。必要になったら ch 選択式で対応する。
- 入力と出力が別デバイスのため、クロックのずれによる途切れは許容する。

## 5.1 入力音量

- Core Audio HAL の `kAudioDevicePropertyVolumeScalar`（入力スコープ、0...1）を読み書きする。システム全体の設定なので、アプリを終了しても値は残る。
- 要素 0（マスター）があればそれを使い、なければ音量を持つチャンネル（要素 1...n）すべてに同じ値を設定する。表示はその平均。
- `AudioObjectIsPropertySettable` で変更できないデバイスはスライダーを無効にし、理由を表示する。
- 音量プロパティを監視し、システム設定や他のアプリでの変更を UI に反映する。対象デバイスが変わったらリスナーを付け替える。
- スライダーは無段階。7 つの目盛り（0%, 17%, 33%, 50%, 67%, 83%, 100%）を表示し、目盛りから ±2% 以内では目盛りの値に吸着する。
- ミュートは扱わない。

## 6. UI

- メイン: デバイスピッカー（フォールバック中はその旨を表示）、フォーマット表示（例: 48 kHz · 2 ch）、入力音量スライダー、メーター（ch ごと: ラベル、バー、数値、クリップ）、dB 目盛り、波形（ch ごと）、時間軸（-N s 〜 now）、モニター再生の操作。
- マイク権限が拒否されている場合は、システム設定を開くボタンを出す。
- 設定（⌘,）: 波形履歴の長さ（スライダー + ステッパー、1〜60 秒）。

## 7. ファイル構成

```
MicMon/
  App/MicMonApp.swift
  Audio/AudioInputDevice.swift, CoreAudioHAL.swift, AudioDeviceManager.swift,
        AudioCaptureEngine.swift, MonitorPlayback.swift, InputVolumeController.swift, LevelStore.swift,
        WaveformHistory.swift, Decibel.swift
  Model/DeviceSelection.swift, MonitorModel.swift
  Views/ContentView.swift, DevicePicker.swift, LevelMeterView.swift, MeterBallistics.swift,
        WaveformView.swift, MonitorControls.swift, InputVolumeControl.swift, SettingsView.swift
```

## 8. 今後

- 単体テスト（`WaveformHistory` のビン化と容量変更、`LevelStore` の dB 値）。テストターゲットを Xcode で追加してから行う
- 3ch 以上のデバイスでのモニター再生
