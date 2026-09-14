# WebVideoBoost

iOS WKWebView用: **PiP / 広告ブロック強化(uBOL内包) / バックグラウンド再生** の転用可能な共通モジュール。
Firefox iOSフォーク (`../firefox-ios-boost`) にも、他のWKWebViewブラウザにも組み込める。

## 構成

```
WebVideoBoost/
  Package.swift                        # SwiftPM (iOS15+, 依存なし: WebKit/AVFoundation/MediaPlayerのみ)
  Sources/WebVideoBoost/
    Shared/WebVideoBoost.swift         # Facade。まずここを読む
    Shared/MemorySaver.swift            # 省メモリ (非選択タブ停止・再生タブ保護)
    VideoPiP/VideoPiPController.swift + video_pip.js
    BackgroundPlayback/BackgroundPlaybackController.swift + background_playback.js
    AdBlock/UBOLContentBlocker.swift + cosmetic.js + youtube_adskip.js
  Tools/
    ublock_to_webkit.py                # uBO/EasyList -> WebKit content-blocker JSON変換
    update_ubol_lists.sh               # リスト更新ワンコマンド
  Extension/                           # Safari Web Extension (YouTube用PiP+BG。広告ブロックなし)
    manifest.json + content/ + popup/ + icons/
  Docs/
    ARCHITECTURE.md
    FirefoxIntegration.md              # firefox-iosへの差分手順 (ファイル名:行番号付き)
```

## 使い方 (他ブラウザ転用: 3行)

```swift
import WebKit
import WebVideoBoost

// 1) configuration生成直後
let config = WKWebViewConfiguration()
WebVideoBoost.configureForNewWebView(config)

// 2) webView生成直後
let boost = WebVideoBoost()
let webView = WKWebView(frame: .zero, configuration: config)
boost.attach(to: webView)

// 3) バックグラウンド突入時 (SceneDelegate/AppDelegate)
boost.didEnterBackground()

// PiPボタン
boost.enterPiP()
```

## 広告ブロックリスト (uBOL内包済み)

uBOL既定セット相当の生リストを `FilterLists/` にバージョン固定で内包し、
変換済みJSON (`Sources/WebVideoBoost/AdBlock/Lists/wvb-ubo-part-*.json`,
約11.6万ルール) までコミット済み。取得なしでそのまま使える。

```bash
cd WebVideoBoost/Tools
./update_ubol_lists.sh    # 内包rawからJSON再生成 (通常は不要)
./fetch_ubol_lists.sh     # 最新リストに更新したい時だけ
```

詳細は `FilterLists/README.md`。変換方針は `Tools/ublock_to_webkit.py` 冒頭参照。

## 省メモリ設計 (なぜ軽いか)

- **遮断はネイティブ側**: `WKContentRuleList` (WebKit内部処理) でJSヒープを使わない。
  要素非表示も `css-display-none` をJSONに埋め込み、JSの常駐監視に頼らない。
- **JSは自己停止**: `cosmetic.js` は最大30回・60秒で監視切断、非表示タブでは何もしない。
  `youtube_adskip.js` はYouTube以外即return、広告なし約60秒で停止。
- **タブ管理**: `MemorySaver.suspendInactive` で非選択タブのメディア停止+ロード中断。
  再生中タブは `BackgroundPlaybackController.isPlaying` で保護する。
  Firefox本体の `TabManagerImplementation.offloadBackgroundWebViews` (メモリ警告時に
  背景タブのWebViewを解放) と併用し、再生タブだけ除外するのが推奨。

## バックグラウンド再生 (できる)

実装済み。条件は4点セット:

1. `Info.plist UIBackgroundModes=audio` (firefox-iosは既存)
2. `BackgroundPlaybackController().activateSession()` を起動時に1回
3. WebViewを破棄しない (Firefoxのセッションはdetachのみで適合)
4. `boost.didEnterBackground()` をbackground突入時に呼ぶ

ロック画面コントロール (`MPRemoteCommandCenter`/NowPlaying) 付き。
再生中は `boost.isPlaying` がtrueになり、MemorySaver/offloadの保護対象になる。

## 注意 (審査・ポリシー)

- バックグラウンド再生は `UIBackgroundModes=audio` + `AVAudioSession(.playback)` が必須。
  音楽・動画ブラウザとして正当に継続する場合のみ有効にすること。
  審査で「audioを宣言しながら無音時に継続」と見なされるとリジェクト対象。
- YouTube広告スキップはDOM操作。YouTube利用規約との関係は各自確認のこと。
