# MicMonitor 画面デザイン

SPEC.md（仕様）の第 6 章に対応する見た目の資料。仕様と食い違うときは SPEC.md を優先する。
どちらもダークモードとライトモードの両方がある。アプリはシステムの外観設定に従って切り替える。

| フォルダ | 内容 | SPEC.md | Claude Design のキャンバス |
|---|---|---|---|
| [macos/](macos/README.md) | Mac のウィンドウ・設定・カード | 6, 6.1 | 「MicMonitor 画面デザイン」 |
| [ios/](ios/README.md) | iPhone・iPad の画面と設定 | 6.2 | 「MicMonitor iPhone・iPad デザイン」 |

各フォルダの `source/` は、それぞれのキャンバスの書き出し。`source/canvas.json` はキャンバスの上で画面をどう並べるか（位置・大きさ・題名・メモ）を書いた索引で、画面の見た目には関わらない。
ここ（docs/ui/README.md）には両方に共通することを、各フォルダの README にはその OS だけのこと（ファイルの一覧、寸法、その OS だけの色）を書く。

## ソースをブラウザで開く

`source/support.js` は .dc.html を表示するための簡易ランタイム（Design キャンバスの本来のランタイムの互換版）。.dc.html が同じフォルダの `./support.js` を読み込むため、両方のフォルダに同じものを置いている。

- 他のファイルを読み込まない画面（Mac の Main・Settings・Card、iOS の Main・Settings）は、ダブルクリックで直接開ける。
- 他のファイルを読み込む画面（ライトモードや停止中など）は、ブラウザの制限で直接（file://）は開けない。ローカルサーバー経由で開く:

  ```
  python3 -m http.server 8000 --directory docs/ui/macos/source
  python3 -m http.server 8001 --directory docs/ui/ios/source
  ```

  → http://localhost:8000/WindowLight.dc.html、http://localhost:8001/PhoneLight.dc.html など
- ボタン（計測の停止、モニター再生、カラーマップの選択など）はクリックで動く。
- Mac 以外の環境では、文字の形が実機と少し違う。

## ソース（.dc.html）の読み方

- 色・サイズ・余白・角丸・フォントサイズは、各要素の `style="…"` に px 単位で書いてある。SwiftUI の pt としてそのまま使える。
- 色は `{{t.xxx}}` の形で書いてあり、`<script>` 内の `THEMES` の同じ名前の値が入る（下の表と各フォルダの README の表と同じ）。
- `{{…}}` は `<script>` 内の `renderVals()` が返す値。`<sc-if>` は条件表示、`<sc-for>` は繰り返し、`<dc-import>` は別のファイルの画面の読み込み。
- `<script>` の中の波形・スペクトル・スペクトログラムのデータは**見た目用の仮データ**。アプリでは使わない（実データは AudioPump 経由のストアから取る）。
- カラーマップの色の表（`MAPS`）は各 10 色の近似。アプリでは SPEC.md のとおり matplotlib の 256 色の表を使う。

## 共通の色

Mac と iOS で同じ値。その OS だけの色（背景・ボタン・スライダーなど）は各フォルダの README にある。

### 文字と欄

| 用途 | トークン | ダーク | ライト |
|---|---|---|---|
| 欄（パネル）の背景 | panel | #161618 | #FFFFFF |
| 欄の枠・区切り線 | line | #2A2A2E | #DADADF |
| グラフの下地 | plot | #0E0E10 | #F5F5F7 |
| グラフの目盛り線 | grid | #1F1F23 | #E6E6EB |
| 文字（主） | text | #F2F2F7 | #1D1D1F |
| 文字（やや弱い・アイコン） | textSoft | #D1D1D6 | #3A3A3C |
| 文字（副） | text2 | #A1A1A8 | #4F4F54 |
| 文字（補助・軸ラベル） | text3 | #8E8E93 | #636366 |
| アクセント | accent | #0A84FF | #007AFF |

アクセントはシステムのアクセントカラー（`Color.accentColor`）に置き換える。

### 計測の表示

| 用途 | トークン | ダーク | ライト |
|---|---|---|---|
| メーター 緑（〜-18 dB） | mG | #30D158 | #34C759 |
| メーター 黄（〜-6 dB） | mY | #FFD60A | #FFCC00 |
| メーター 赤（-6 dB〜） | mR | #FF453A | #FF3B30 |
| メーターの Peak | — | 上の色の 38% | 上の色の 38% |
| メーターのゾーンの区切り | panel | 欄の背景色で幅 2pt（-18・-6 dB） | 同左 |
| 目盛りの上の色の帯 | mG / mY / mR | 上の色の 75% | 上の色の 90% |
| クリップ表示 点灯 | clipOn / clipGlow | #FF453A（周りに同色の光） | #D70015（周りに同色の 18% の輪） |
| クリップ表示 消灯 | clipOff | #3A3A3C | #D1D1D6 |
| クリップ時の右肩の数値 | danger | #FF6961 | #D70015 |
| 波形 Peak | accent | アクセント 40% | アクセント 40% |
| 波形 RMS | rms | #3D9BFF | #0060DF |
| スペクトル 塗り | accent | アクセント 45% | アクセント 45% |
| スペクトル ピークホールド線 | peakLine | #E5E5EA の 85% | #1D1D1F の 85% |
| 「停止時点のまま表示」の注記 | warn | #FFD60A | #7A5200 |
| 権限なしのアイコン | danger | #FF6961 | #D70015 |

スペクトログラムのカラーマップ（viridis など）はダーク・ライト共通。単色のときはアクセントカラーをレベルに比例した透明度で塗る。

## 実装のヒント

- 上の色の多くはシステムカラーに相当する。SwiftUI では、固定値より標準のセマンティックカラーを使うほうがダーク・ライトの切り替えに自然に追従する。対応の目安は次のとおり。
  - text → `.primary`
  - text2 / text3 → `.secondary` / `.tertiary`
  - メーターの色 → `.green` `.yellow` `.red`
- グラフの下地・RMS・ピークホールド線などの独自の色は、Asset Catalog に Any / Dark の 2 値で登録する。
- ピッカー・スライダー・トグル・ボタン・設定画面は、SwiftUI の標準コントロールで近づければよい。
- メーター・波形・スペクトル・スペクトログラムは `Canvas` で自前描画する（Mac と iOS で共有）。
- 文字の大きさは px をそのまま pt にせず、`AppFont` の text style で指定する（macOS の text style は大きさが固定で、Mac のデザインの寸法と同じになるものを選んでいる。iOS では Dynamic Type に従う）。
