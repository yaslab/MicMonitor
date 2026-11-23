# MicMonitor

マイク入力（レベル・波形・スペクトル・スペクトログラム）をリアルタイムに確認するアプリ。macOS・iOS・iPadOS（visionOS もビルドは通る）。SwiftUI + AVAudioEngine + Core Audio HAL（macOS）/ AVAudioSession（iOS）。

- 仕様: @docs/SPEC.md（スレッドとエンジン再構成の方針は第 3 章）
- 画面デザイン: Mac は docs/ui/README.md と docs/ui/source、iPhone・iPad は docs/ui/ios。仕様と食い違うときは SPEC.md が優先
- ビルド・プレビュー・実行: Xcode MCP（`xcrun mcpbridge`）を使う。Xcode の GUI を開いていなくても、先に XcodeOpenWorkspace でプロジェクトを開けば使える
- `MicMonitor/` はフォルダ参照なので、ファイルの追加・削除でプロジェクトファイルを編集する必要はない
- プラットフォーム専用のファイルは `MicMonitor/` の下の `Platform/macOS/` か `Platform/iOS/` フォルダに置く（`Platform/iOS/` は iOS・iPadOS・visionOS 共通）。ターゲットのビルド設定 `EXCLUDED_SOURCE_FILE_NAMES[sdk=…]` で、もう一方の SDK のビルドから除外している。ファイルの一部だけが違うときは `#if os(macOS)` で分ける
  - 除外のパターンの `*` は `/` をまたがないため、階層ごとに並べている（`Platform/<OS>/` の下 3 階層まで）。それより深く置くときはパターンを足す
  - 両方のフォルダに同じ名前のファイルを置かない（除外していてもビルドの出力ファイルの名前がぶつかって失敗する）。同じ型を両方で実装するときは `PlatformInputVolume.macOS.swift` / `PlatformInputVolume.iOS.swift` のようにファイル名で分ける
  - 両方で実装する型とプロトコルの対応は `Audio/AudioPlatform.swift` にある（SPEC.md 3.3 節）

## 落とし穴

- `AVAudioSinkNode` のクロージャはリアルタイムスレッドで呼ばれる。ここではリングバッファへのコピーだけを行い、ロック・メモリ確保・MainActor への hop をしない。集計や再生の予約は `AudioPump` のタスクで行う
- リアルタイムスレッドやリスナーから呼ばれるクロージャは `nonisolated` な関数の中で作る。MainActor の文脈で作ると、Swift 6 の実行時の分離チェックでクラッシュする
- `MonitorPlayback` をメインスレッド以外で解放すると AVAudioEngine の内部でデッドロックする。`isolated deinit` を外さない
- 入力と再生は別々の `AVAudioEngine` にしている（1 つのエンジンでは入力デバイスの出力にしか再生できない）。1 つにまとめない
- `AVAudioEngineConfigurationChange` は起動直後にも届く。毎回エンジンを作り直すと再起動のループになる
- Xcode Previews では計測を始めない（`MonitorModel.start()` の `XCODE_RUNNING_FOR_PREVIEWS` の確認）。プレビューのプロセスが裏に残ってマイクを使い続けるため
- カード表示中はメインウィンドウを閉じずに `orderOut` で隠している。閉じると AppKit が最後のウィンドウとみなしてアプリが終了する
- 入力デバイスの一覧からは、AVAudioEngine が自動で作るプライベートな集約デバイス（`CADefaultDeviceAggregate-…`）を除いている
- `SpectrogramColormapTables.swift` は matplotlib から書き出した表。手で編集しない
- docs/ui/source の HTML にある波形などのデータと 10 色のカラーマップは見た目用の仮のもの。アプリでは使わない
- 文字は `.font(.system(size:))` で固定せず、`AppFont` の text style を使う（iOS の Dynamic Type のため。macOS では大きさが変わらない。Mac 専用のカードだけは固定のまま）。計測の欄の寸法は `MonitorMetrics`（環境値）から取る
- iOS のオーディオセッションの `setActive` はメインスレッドで呼ばない（`AudioSessionController.iOS.swift` の `@concurrent` の関数で呼んでいる）。非同期の `activate(options:)` に置き換えない（完了直後は入力が 0 Hz でエンジンの開始に失敗する）
- iOS では Info.plist の `UIApplicationSceneManifest` の自動生成を止めている（自動生成だと複数ウィンドウが有効になり、`LevelStore.read()` の読み手が 2 つになる）。生成に戻さない
