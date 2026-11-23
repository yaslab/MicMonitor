# MicMonitor iPhone・iPad 画面デザイン

SPEC.md の 6.2 節に対応する見た目の資料。仕様と食い違うときは SPEC.md を優先する。
Claude の Artifact（Design キャンバス）「MicMonitor iPhone・iPad デザイン」の書き出し。読み方・ブラウザでの開き方・Mac と iOS で共通の色は [../README.md](../README.md) にある。

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
- ステータスバーとホームインジケーターは描いていない（上端の余白がその分）。iPhone 横の左右の余白 62 はセーフエリアを含む。

## iOS だけの色

| 用途 | トークン | ダーク | ライト |
|---|---|---|---|
| 画面の背景（システムのグループ背景） | bg | #000000 | #F2F2F7 |
| 欄の中の区切り線 | sep | #38383A | #E5E5EA |
| スライダーの溝 | track | #3A3A3C | #D1D1D6 |
| スライダーの目盛り | tick | #636366 | #AEAEB2 |
| スライダーのつまみ | knob | #FFFFFF | #FFFFFF |
| ガラスのボタンの背景 / 枠 | glass / glassBorder | rgba(120,120,128,0.24) / 白 10% | rgba(255,255,255,0.78) / 黒 8% |
| スイッチ（オフ） | switchOff | #39393D | #E3E3E8 |
| メーターの溝・権限なしのアイコンの丸 | clipOffBg | #2C2C2E | #E9E9EB |
