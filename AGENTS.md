# MicMonitor

Mac のマイク入力（レベル・波形・スペクトル・スペクトログラム）をリアルタイムに確認する macOS アプリ。SwiftUI + AVAudioEngine + Core Audio HAL。

- 仕様: @docs/SPEC.md（スレッドとエンジン再構成の方針は第 3 章）
- 画面デザイン: docs/ui/README.md と docs/ui/source の HTML。仕様と食い違うときは SPEC.md が優先
- ビルド・プレビュー・実行: Xcode MCP（`xcrun mcpbridge`）を使う。Xcode の GUI を開いていなくても、先に XcodeOpenWorkspace でプロジェクトを開けば使える
- `MicMonitor/` はフォルダ参照なので、ファイルの追加・削除でプロジェクトファイルを編集する必要はない

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
