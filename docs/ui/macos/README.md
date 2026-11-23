# MicMonitor Mac 画面デザイン

SPEC.md の第 6 章（ウィンドウ）と 6.1 節（カード）に対応する見た目の資料。仕様と食い違うときは SPEC.md を優先する。
Claude の Artifact（Design キャンバス）「MicMonitor 画面デザイン」の書き出し。読み方・ブラウザでの開き方・Mac と iOS で共通の色は [../README.md](../README.md) にある。

## ファイル

### ダークモード

| ソース | 内容 | SPEC.md |
|---|---|---|
| source/Main.dc.html | ウィンドウ表示（計測中） | 6 |
| source/WindowPaused.dc.html | 計測を停止中（Main を paused で表示） | 6（計測の停止） |
| source/WindowNoPermission.dc.html | マイク権限なし（Main を denied で表示） | 6 |
| source/Settings.dc.html | 設定（⌘,） | 6, F4 |
| source/Card.dc.html | カード表示（単体） | 6.1 |
| source/CardVariants.dc.html | カード表示のバリエーション（通常・スペクトログラム・停止中・メニュー・最小幅/1ch/エラー） | 6.1 |

### ライトモード

| ソース | 内容 |
|---|---|
| source/WindowLight.dc.html | ウィンドウ表示（計測中） |
| source/WindowPausedLight.dc.html | 計測を停止中 |
| source/WindowNoPermissionLight.dc.html | マイク権限なし |
| source/SettingsLight.dc.html | 設定（⌘,） |
| source/CardVariantsLight.dc.html | カード表示のバリエーション |

ライトモードのソースは、Main・Settings・Card に `theme="light"` を渡して表示しているだけの小さなファイル。画面の中身と色の切り替えは Main.dc.html・Settings.dc.html・Card.dc.html の `THEMES`（`dark` / `light`）にある。

## 寸法

ウィンドウは 760 × 900 pt、設定は 560 × 720 pt、カードは幅 300 pt（最小 220）。アプリの計測の欄の寸法は `MonitorMetrics.window`。

## Mac だけの色

### ウィンドウと設定

| 用途 | トークン | ダーク | ライト |
|---|---|---|---|
| ウィンドウ背景 | window | #1C1C1E（設定は #1E1E20） | #ECECEC |
| タイトルバー | chrome | #2C2C2E | #E3E3E5 |
| タイトルバー下の線 | titleBorder | #0E0E10 | #C9C9CD |
| 設定のグループ背景 / 枠 | group / groupBorder | #2A2A2D / #36363A | #FFFFFF / #DADADF |
| ボタン背景 / 枠 | btn / btnBorder | #3A3A3C / #4A4A4E | #FFFFFF / #C9C9CD |
| スライダーの溝 | track | #48484A | #D1D1D6 |
| スライダーの目盛り | tick | #6E6E73 | #AEAEB2 |
| スライダーのつまみ | knob | #F2F2F7 | #FFFFFF（細い枠線付きの影） |
| 設定の選択中の行 | rowSel | #3A3A3D | #E8E8ED |
| 主ボタン（システム設定を開く・計測を開始） | — | #0A64D6 に白文字 | #0A64D6 に白文字 |
| メーターの溝 | chrome | #2C2C2E | #E3E3E5 |

### カード（HUD）

| 用途 | トークン | ダーク | ライト |
|---|---|---|---|
| 背景 | hud | rgba(32,32,36,0.86) | rgba(248,248,250,0.86) |
| 枠 | hudBorder | 白 14% | 黒 12% |
| グラフの下地 | well | 黒 35% | 黒 5% |
| メーターの溝 | hudTrack | 白 10% | 黒 10% |
| 「計測を停止中」の帯 | pausedBox | 白 6% | 黒 5% |
| スライダーの溝 / 目盛り | sliderTrack / tick | 白 18% / 白 30% | 黒 15% / 黒 25% |
| アイコンボタン（オン） | toggleBg / toggleFg | アクセント 28% / #64B5FF | アクセント 14% / #0060DF |
| アイコンボタン（オフ） | text2 | #A1A1A8 | #5F5F64 |
| 「…」メニュー背景 | menu | rgba(44,44,48,0.97) | rgba(250,250,252,0.97) |
| エラー文 | errorText | #FF9F0A | #A84800 |
| クリップ時の数値 | clipText | #FF6961 | #D70015 |
| クリップ表示 点灯 / 消灯 | clipOn / hudTrack | #FF453A / 白 10%（メーターの溝と同じ） | #D70015 / 黒 10%（メーターの溝と同じ） |
| 色の帯 | stripOpacity | メーターの色の 75% | メーターの色の 90% |

メーターのゾーンの区切りは、カードの背景が透けるように切り抜く（ウィンドウのように欄の背景色では塗らない）。

## 実装のヒント

- ウィンドウ背景は `windowBackgroundColor`。
- カードの背景は `NSVisualEffectView`（`.hudWindow`）。外観に合わせて自動で明暗が変わる。
- カードの文字は Dynamic Type の対象外なので、`.font(.system(size:))` の固定のままでよい。
