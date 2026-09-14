# firefox-ios (fork: AI-SLOP-BOX/firefox-ios-boost) 統合手順

対象: `firefox-ios-boost` (sparse clone済み)。行番号は調査時点 (2026-09, main, depth1)。

## 0. WebVideoBoostを参照する

選択肢A (推奨・転用容易): SwiftPMで参照
- `firefox-ios-boost` のワークスペースに `WebVideoBoost` パッケージを追加し、
  `BrowserKit` (`BrowserKit/Sources/WebEngine`) から依存する。
- `WebVideoBoost` はFirefox非依存のため、他ブラウザでも同じPackageを参照できる。

選択肢B (簡易): ファイルコピー
- `WebVideoBoost/Sources/WebVideoBoost/**` を `firefox-ios/Client/Frontend/WebVideoBoost/` にコピーし、
  `.js` を Copy Bundle Resources に追加する。

以下は選択肢A/Bどちらでも同じ呼び出し位置。

## 1. PiP

### 1-1. configurationにフラグを立てる
ファイル: `BrowserKit/Sources/WebEngine/WKWebview/WKEngineConfigurationProvider.swift:67-94`
`createConfiguration(parameters:)` 内、`allowsInlineMediaPlayback = true` の直後に追加:

```swift
configuration.allowsInlineMediaPlayback = true
// WebVideoBoost: PiP許可 (他ブラウザ転用時は WebVideoBoost.configureForNewWebView 相当)
configuration.allowsPictureInPictureMediaPlayback = true
configuration.allowsAirPlayForMediaPlayback = true
```

`BrowserViewController+WebViewDelegates.swift:285-298` のプレビュー用クローンは
意図的にPiP無効化しているため変更しない。

### 1-2. UserScript/MessageHandlerを装着
ファイル: `BrowserKit/Sources/WebEngine/WKWebview/WKEngineSession.swift:97-125`
`userScriptManager.injectUserScriptsIntoWebView(webView)` の後に追加:

```swift
// WebVideoBoost: PiP + BG + AdBlock装着 (1行で3機能)
let boost = WebVideoBoost()
WebVideoBoost.configureForNewWebView(webView.configuration) // 既に1-1済みなら不要
boost.attach(to: webView)
// boostはセッション存続中保持すること (例: WKEngineSessionのプロパティに)
self.webVideoBoost = boost
```

`WKEngineSession.swift:260-266 close()` では `boost` の参照を外すだけでよい
(`uninstall` は任意。WebView破棄時にハンドラも消える)。

### 1-3. PiPボタンの配線例 (ツールバー/長押しメニュー)
```swift
boost.enterPiP { result in /* 'enter' / 'no-video' / 'unsupported' */ }
boost.exitPiP()
```
`VideoPiPController.onEvent` で `enter/leave` を受けてボタンの選択状態を更新する。

## 2. 広告ブロック強化 (uBOL内包)

現状: `firefox-ios/Client/ContentBlocker/ContentBlocker.swift` が
`WKContentRuleListStore.default()` に ETP (Disconnect系) + `ad-block` (RemoteSettings) を
`setupTrackingProtection(forTab:rules:)` (`:202-230`) で適用。
cosmetic (要素非表示) は無し (`TrackingProtectionStats.js` は統計報告のみ)。

### 2-1. リスト生成
```bash
cd WebVideoBoost/Tools
./update_ubol_lists.sh ../../firefox-ios-boost/firefox-ios/Client/Assets/WebVideoBoostLists
# 生成: wvb-ubo-part-N.json + cosmetic_selectors.json
```
生成JSONをXcodeの Copy Bundle Resources に追加する
(既存の `disconnect-block-*.json` と同列に置くと分かりやすい)。

### 2-2. 競合回避: removeAllContentRuleLists() の追記方式化
`ContentBlocker.swift:232-243 removeTrackingProtection(forTab:)` は現状:
```swift
tab.currentWebView()?.configuration.userContentController.removeAllContentRuleLists()
```
これを呼ぶとuBOL分も消える。対策はどちらか:
- (a) `setupTrackingProtection` 後に `UBOLContentBlocker.applyNetworkRules` を再適用する, or
- (b) `removeTrackingProtection` を「ETP分だけremove」に変える (推奨。識別子で判定):

```swift
// 変更例 (b): ETP識別子のみ外す
let keepPrefix = UBOLContentBlocker.ruleIdentifierPrefix
// userContentController.contentRuleLists を走査し、identifierがkeepPrefixで始まらないものだけ外す。
// WKUserContentControllerに個別remove APIが無い場合は、uBOL分を外した後に再addする。
```

最小差分で確実なのは (a):
```swift
// FirefoxTabContentBlocker.setupForTab の末尾に追加
ContentBlocker.shared.setupTrackingProtection(forTab: tab, ...) {
    UBOLContentBlocker().applyNetworkRules(to: tab.webView) // 要webView取得
}
```

### 2-3. cosmetic / YouTubeスキップの装着
`WKEngineSession` の `addContentScripts` (`WKEngineSession.swift:350-372`) とは別に、
`WebVideoBoost.attach` が `cosmetic.js` + `youtube_adskip.js` を入れる (1-2で済み)。
`cosmetic_selectors.json` の内容を `cosmetic.js` の `__WVB_COSMETIC_SELECTORS` に埋め込むと精度が上がる:
```bash
python3 Tools/inject_selectors.py --selectors <lists>/cosmetic_selectors.json
# (未実装なら手動で配列を置換)
```

## 3. バックグラウンド再生

現状: `firefox-ios/Client/Info.plist:216-222` に `audio` あり (土台OK)。
`AppDelegate.swift:145-147` が `BackgroundAudioHelper` を呼ぶが実体は別途確認。
`AVAudioSession / MPNowPlayingInfoCenter / MPRemoteCommandCenter` の使用は無し。

### 3-1. AudioSession有効化 (起動時1回)
`firefox-ios/Client/Application/AppDelegate.swift` の `didFinishLaunching` 付近、
`BackgroundAudioHelper` 呼び出しと併置:

```swift
// WebVideoBoost: BG再生のOS側許可
BackgroundPlaybackController().activateSession()
```

### 3-2. WebView装着 + background突入通知
- 装着は1-2の `boost.attach(to:)` で済み (内部で `activateSession + install + RemoteCommands` まで行う)。
- `SceneDelegate.swift:100-113 sceneDidEnterBackground` の先頭に追加:

```swift
// WebVideoBoost: 背景突入直後のpauseガード (2秒)
(engineSession as? WebVideoBoostHolding)?.webVideoBoost?.didEnterBackground()
```

`WKEngineSession.webView` はbackgroundで破棄されない (detachのみ。
`WKEngineView.swift:38-56`, `WKSessionLifecycleManager.swift:63-74` で確認済み) ため、
特別な保持処理は不要。`pauseAllMediaPlayback()` をbackground時に呼ばないこと。

### 3-3. Info.plist確認
`firefox-ios/Client/Info.plist` の `UIBackgroundModes` に `audio` が残っていること。
無いと問答無用で止まる。審査時は「ブラウザのメディア継続」として正当性を説明する。

## 4. 動作確認チェックリスト

- [ ] Safari同等ページで `<video>` 再生 → `boost.enterPiP()` でフローティング表示
- [ ] YouTube (m.youtube.com) で再生 → PiPボタン/JSの両経路でPiP
- [ ] `adblock-tester.com` でスコア向上 (ETPのみ時と比較)
- [ ] YouTubeプレロールでスキップボタン自動押下 / 不可広告の高速消化
- [ ] ホーム画面移行・画面ロック後も音声継続、ロック画面に再生コントロール表示
- [ ] ETP Strict/Standard切替後もuBOLルールが残る (2-2の回帰確認)

## 5. 他ブラウザへの転用

- `WebVideoBoost/` をそのままSwiftPM参照するだけ。呼び出しはREADMEの3行。
- リスト生成物 (`wvb-ubo-part-*.json`) はバンドル配置のみで流用可。
- Orion等WebKit系ブラウザも `configure + attach + didEnterBackground` の3点で同じ効果。
