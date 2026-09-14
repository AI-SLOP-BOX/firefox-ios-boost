# ARCHITECTURE

## 設計方針

- **Firefox非依存**: `WebVideoBoost` は `WebKit / AVFoundation / MediaPlayer / Foundation` のみ参照。
  `firefox-ios/*` や `BrowserKit/*` のimportは禁止 (テストで担保するなら `grep -r "BrowserKit\|FirefoxTab" Sources` が0件)。
- **設定と装着の分離**: iOS WKWebViewは `configuration` が生成時固定のため、
  `configureForNewWebView(_:)` (生成前) と `attach(to:)` (生成後) に分ける。
- **WebKit標準に乗る**: 独自ネットワークスタックを持たず、
  `WKContentRuleListStore` + `WKUserScript` + `requestPictureInPicture/webkitSetPresentationMode` に寄せる。
  これにより将来のWebKit変更にも追従しやすい。

## 各機能の仕組み

### 1. PiP (`VideoPiP/`)

- Native: `WKWebViewConfiguration.allowsPictureInPictureMediaPlayback = true`
  (+ `allowsInlineMediaPlayback`, `allowsAirPlayForMediaPlayback`)。
- JS (`video_pip.js`, atDocumentEnd, 全フレーム):
  `querySelectorAll('video')` をhookし、`enter/leavepictureinpicture` を `wvbPip` ハンドラに通知。
  `__wvbEnterPiP()` は面積最大+再生中のvideoを選び、
  標準 `requestPictureInPicture()` → 失敗時 `webkitSetPresentationMode('picture-in-picture')`。
- なぜ二段構えか: iOS WKWebViewでは標準APIが `NotSupportedError` になるケースがあり、
  prefixedが実効ルートのため。

### 2. 広告ブロック (`AdBlock/`)

- ネットワーク遮断: WebKit content-blocker JSON (`block` / `ignore-previous-rules`)。
  `Tools/ublock_to_webkit.py` で uAssets/EasyList/EasyPrivacy/Peter Lowe から生成。
  50k件上限のため `wvb-ubo-part-N.json` に分割 (既定45k)。
- 要素非表示: WebKit `css-display-none` に変換できなかった分は `cosmetic.js`
  (MutationObserverで遅延生成枠も追従) で `display:none`。
- 動画内広告: `youtube_adskip.js` (スキップボタンクリック + 不可広告の高速消化)。
- firefox-ios既存の `ContentBlocker` (ETP: Disconnect系) とは併用。
  既存が `removeAllContentRuleLists()` で全消しするため、統合時は追記方式に変更する
  (FirefoxIntegration.md参照)。

### 3. バックグラウンド再生 (`BackgroundPlayback/`)

4点セット:
1. `Info.plist UIBackgroundModes=audio` (firefox-iosは既存)
2. `AVAudioSession(.playback)` + `setActive(true)` (起動時に1回)
3. WebViewを破棄しない (firefox-iosの `WKEngineSession` はdetachのみで破棄なし — 適合)
4. `background_playback.js` (atDocumentStart) で `visibilitychange/pagehide` 登録の無力化 +
   `document.hidden=false` 偽装 + 背景突入直後の `pause()` ガード

- ロック画面/コントロールセンター: `MPRemoteCommandCenter` (play/pause/toggle) +
  `MPNowPlayingInfoCenter`。YouTubeのタイトル取得までは踏み込まず、
  呼び出し側が `nowPlayingTitle/Artist` を渡す方式 (,title取得JSはサイト依存が大きいため)。

## ディレクトリ対応表 (firefox-ios統合点)

| 機能 | firefox-ios側の統合点 | WebVideoBoost側 |
|---|---|---|
| PiP設定 | `BrowserKit/.../WKEngineConfigurationProvider.swift:67-94` | `VideoPiPController.configure` |
| UserScript装着 | `BrowserKit/.../WKEngineSession.swift:97-125,350-372` | `WebVideoBoost.attach` |
| 広告NW遮断 | `firefox-ios/Client/ContentBlocker/ContentBlocker.swift:202-243,415-472` | `UBOLContentBlocker.applyNetworkRules` |
| 広告cosmetic | (新規。既存は統計JSのみ) | `cosmetic.js` |
| BG音声 | `firefox-ios/Client/Application/AppDelegate.swift:145-147` + `Client/Info.plist:216` | `BackgroundPlaybackController` |
