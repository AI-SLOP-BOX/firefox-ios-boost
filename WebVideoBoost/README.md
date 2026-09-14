# WebVideoBoost

iOS WKWebView用: **PiP / 広告ブロック強化(uBOL内包) / バックグラウンド再生** の転用可能な共通モジュール。
Firefox iOSフォーク (`../firefox-ios-boost`) にも、他のWKWebViewブラウザにも組み込める。

## 構成

```
WebVideoBoost/
  Package.swift                        # SwiftPM (iOS15+, 依存なし: WebKit/AVFoundation/MediaPlayerのみ)
  Sources/WebVideoBoost/
    Shared/WebVideoBoost.swift         # Facade。まずここを読む
    VideoPiP/VideoPiPController.swift + video_pip.js
    BackgroundPlayback/BackgroundPlaybackController.swift + background_playback.js
    AdBlock/UBOLContentBlocker.swift + cosmetic.js + youtube_adskip.js
  Tools/
    ublock_to_webkit.py                # uBO/EasyList -> WebKit content-blocker JSON変換
    update_ubol_lists.sh               # リスト更新ワンコマンド
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

## 広告ブロックリストの更新

```bash
cd WebVideoBoost/Tools
./update_ubol_lists.sh ../Sources/WebVideoBoost/AdBlock/Lists
# 生成物: wvb-ubo-part-N.json + cosmetic_selectors.json をアプリバンドルに追加
```

変換方針は `Tools/ublock_to_webkit.py` 冒頭コメント参照 (表現できない高度記法はスキップして誤ブロックを防ぐ)。

## 注意 (審査・ポリシー)

- バックグラウンド再生は `UIBackgroundModes=audio` + `AVAudioSession(.playback)` が必須。
  音楽・動画ブラウザとして正当に継続する場合のみ有効にすること。
  審査で「audioを宣言しながら無音時に継続」と見なされるとリジェクト対象。
- YouTube広告スキップはDOM操作。YouTube利用規約との関係は各自確認のこと。
