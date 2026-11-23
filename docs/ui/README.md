# MicMonitor 画面デザイン

SPEC.md（仕様）の第 6 章に対応する見た目の資料。仕様と食い違うときは SPEC.md を優先する。
ダークモードとライトモードの両方がある。アプリはシステムの外観設定に従って切り替える。

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

source/canvas.json は、Claude の Artifact「MicMonitor 画面デザイン」のキャンバスで、上の画面をどう並べるか（位置・大きさ・題名・メモ）を書いた索引。画面の見た目には関わらない。

ライトモードのソースは、Main・Settings・Card に `theme="light"` を渡して表示しているだけの小さなファイル。画面の中身と色の切り替えは Main.dc.html・Settings.dc.html・Card.dc.html の `THEMES`（`dark` / `light`）にある。

ウィンドウは 760 × 900 pt、設定は 560 × 720 pt、カードは幅 300 pt（最小 220）。ブラウザで表示すると、Mac 以外の環境では文字の形が実機と少し違う。

## ソースをブラウザで開く

`source/support.js` は .dc.html を表示するための簡易ランタイム（Design キャンバスの本来のランタイムの互換版）。

- Main・Settings・Card 以外のファイルは別のファイルを読み込むため、ブラウザの制限で直接（file://）は開けない。ローカルサーバー経由で開く:

  ```
  cd docs/ui/source
  python3 -m http.server 8000
  ```

  → http://localhost:8000/WindowLight.dc.html など
- Main・Settings・Card はダブルクリックで直接開ける（CardVariants も Card を読み込むのでサーバー経由）。
- ボタン（計測の停止、モニター再生、カラーマップの選択など）はクリックで動く。

## ソース（.dc.html）の読み方

- 色・サイズ・余白・角丸・フォントサイズは、各要素の `style="…"` に px 単位で書いてある。SwiftUI の pt としてそのまま使える。
- 色は `{{t.xxx}}` の形で書いてあり、`<script>` 内の `THEMES` の同じ名前の値が入る（下の表と同じ）。
- `{{…}}` は `<script>` 内の `renderVals()` が返す値。`<sc-if>` は条件表示、`<sc-for>` は繰り返し。
- `<script>` の中の波形・スペクトル・スペクトログラムのデータは**見た目用の仮データ**。アプリでは使わない（実データは AudioPump 経由のストアから取る）。
- カラーマップの色の表（`MAPS`）は各 10 色の近似。アプリでは SPEC.md のとおり matplotlib の 256 色の表を使う。

## 色の一覧

### ウィンドウと設定

| 用途 | トークン | ダーク | ライト |
|---|---|---|---|
| ウィンドウ背景 | window | #1C1C1E（設定は #1E1E20） | #ECECEC |
| タイトルバー | chrome | #2C2C2E | #E3E3E5 |
| タイトルバー下の線 | titleBorder | #0E0E10 | #C9C9CD |
| パネル背景（ウィンドウ） | panel | #161618 | #FFFFFF |
| 設定のグループ背景 / 枠 | group / groupBorder | #2A2A2D / #36363A | #FFFFFF / #DADADF |
| パネル枠・区切り線 | line | #2A2A2E | #DADADF |
| グラフの下地 | plot | #0E0E10 | #F5F5F7 |
| グラフの目盛り線 | grid | #1F1F23 | #E6E6EB |
| 文字（主） | text | #F2F2F7 | #1D1D1F |
| 文字（やや弱い・アイコン） | textSoft | #D1D1D6 | #3A3A3C |
| 文字（副） | text2 | #A1A1A8 | #4F4F54 |
| 文字（補助・軸ラベル） | text3 | #8E8E93 | #636366 |
| ボタン背景 / 枠 | btn / btnBorder | #3A3A3C / #4A4A4E | #FFFFFF / #C9C9CD |
| スライダーの溝 | track | #48484A | #D1D1D6 |
| スライダーの目盛り | tick | #6E6E73 | #AEAEB2 |
| スライダーのつまみ | knob | #F2F2F7 | #FFFFFF（細い枠線付きの影） |
| 設定の選択中の行 | rowSel | #3A3A3D | #E8E8ED |
| アクセント | accent | #0A84FF | #007AFF |
| 主ボタン（システム設定を開く・計測を開始） | — | #0A64D6 に白文字 | #0A64D6 に白文字 |

アクセントはシステムのアクセントカラー（`Color.accentColor`）に置き換える。

### 計測の表示

| 用途 | トークン | ダーク | ライト |
|---|---|---|---|
| メーター 緑（〜-18 dB） | mG | #30D158 | #34C759 |
| メーター 黄（〜-6 dB） | mY | #FFD60A | #FFCC00 |
| メーター 赤（-6 dB〜） | mR | #FF453A | #FF3B30 |
| メーターの Peak | — | 上の色の 38% | 上の色の 38% |
| CLIP 点灯 | — | #D70015 に白文字 | #D70015 に白文字 |
| CLIP 消灯 | clipOffBg / clipOffFg | #2C2C2E / #98989D | #E3E3E5 / #636366 |
| 波形 Peak | accent | アクセント 40% | アクセント 40% |
| 波形 RMS | rms | #3D9BFF | #0060DF |
| スペクトル 塗り | accent | アクセント 45% | アクセント 45% |
| スペクトル ピークホールド線 | peakLine | #E5E5EA の 85% | #1D1D1F の 85% |
| 「停止時点のまま表示」の注記 | warn | #FFD60A | #7A5200 |
| 権限なしのアイコン | danger | #FF6961 | #D70015 |

スペクトログラムのカラーマップ（viridis など）はダーク・ライト共通。単色のときはアクセントカラーをレベルに比例した透明度で塗る。

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

## 実装のヒント

- 上の色の多くは macOS のシステムカラーに相当する。SwiftUI では、固定値より標準のセマンティックカラーを使うほうがダーク・ライトの切り替えに自然に追従する。対応の目安は次のとおり。
  - text → `.primary`
  - text2 / text3 → `.secondary` / `.tertiary`
  - ウィンドウ背景 → `windowBackgroundColor`
  - メーターの色 → `.green` `.yellow` `.red`
- グラフの下地・RMS・ピークホールド線などの独自の色は、Asset Catalog に Any / Dark の 2 値で登録する。
- ピッカー・スライダー・トグル・ボタン・設定画面は、SwiftUI の標準コントロールで近づければよい。
- メーター・波形・スペクトル・スペクトログラムは `Canvas` で自前描画する。
- カードの背景は `NSVisualEffectView`（`.hudWindow`）。外観に合わせて自動で明暗が変わる。
