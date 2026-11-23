# MicMonitor iPhone・iPad 画面デザイン

SPEC.md の 6.2 節に対応する見た目の資料。仕様と食い違うときは SPEC.md を優先する。
Claude の Artifact（Design キャンバス）「MicMonitor iPhone・iPad デザイン」の書き出しで、読み方とブラウザでの開き方は Mac のデザイン（../README.md）と同じ。

## ファイル

| ソース | 内容 |
|---|---|
| source/Main.dc.html | 画面の本体。`layout`（phone / phoneLandscape / tablet / tabletLandscape）・`state`（running / paused / denied）・`theme`（dark / light）で切り替える。単体では iPhone 縦の計測中（ダーク） |
| source/PhonePaused.dc.html | iPhone 縦・計測を停止中 |
| source/PhoneNoPermission.dc.html | iPhone 縦・マイク権限なし |
| source/PhoneLandscape.dc.html | iPhone 横（2 列） |
| source/Settings.dc.html | 設定のシート（iPhone） |
| source/TabletPortrait.dc.html | iPad 縦（1 列） |
| source/TabletLandscape.dc.html | iPad 横（2 列） |
| source/PhoneLight.dc.html, source/TabletLandscapeLight.dc.html | ライトモード |

Main 以外は Main（設定は Settings）に属性を渡して表示しているだけの小さなファイル。iPhone 縦と設定は、スクロールした全体を 1 枚に描いている。

## 寸法と文字

- 文字の大きさは Dynamic Type の標準（Large）のときの値。本文 17（body）、補助 15（subheadline）、欄の見出し 13（footnote・semibold）、欄の説明 12（caption）、軸 11（caption2）。アプリでは `AppFont` の text style で指定する。
- 欄の角丸 16、欄の中の余白 12〜16、チャンネル番号と目盛りの列 30（波形とスペクトログラムの時間軸をそろえる）。
- グラフの高さ（波形の 1 段・スペクトログラム・スペクトル）: iPhone 縦 64・120・140、iPhone 横 56・96・112、iPad 縦 72・150・170、iPad 横 64・132・150。アプリでは `ScreenLayout.metrics`。
- 入力のカードの 2 行目は、システム既定に追従しているときは「システム既定 · 48 kHz · 1 ch」、デバイスを選んでいるときはフォーマットだけ（iPhone の画面は前者、iPad の画面は後者の例）。
- 色は Mac と同じ（../README.md の色の一覧）。画面の背景はシステムのグループ背景（ダーク #000000 / ライト #F2F2F7）。
- ステータスバーとホームインジケーターは描いていない（上端の余白がその分）。iPhone 横の左右の余白 62 はセーフエリアを含む。
