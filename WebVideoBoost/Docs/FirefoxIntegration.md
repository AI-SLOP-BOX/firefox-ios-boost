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
boost.enterPiP { result in /* 'enter' / 'no-video' / 'unsupported' / 'disabled' */ }
boost.exitPiP()
```
`VideoPiPController.onEvent` で `enter/leave` を受けてボタンの選択状態を更新する。

### 1-4. PiPのON/OFF設定 (バックグラウンド再生のみ運用)
`BoostSettings` がUserDefaults永続化済み。設定画面のトグルと配線するだけ:
```swift
// 読み込み→反映 (WKEngineSession生成時など、attach(to:)の前に)
BoostSettings.load().apply(to: boost)
// 保存 (トグル変更時。次に開くタブから反映。既存タブのenterPiPは即無効化)
var s = BoostSettings.load(); s.pipEnabled = toggle.isOn; s.save().apply(to: boost)
```
キー: `wvb.pip.enabled` / `wvb.backgroundAudio.enabled` / `wvb.adblock.enabled`。
PiP OFFでもバックグラウンド再生・広告ブロックは動き続ける。

## 2. 広告ブロック強化 (uBOL内包)

現状: `firefox-ios/Client/ContentBlocker/ContentBlocker.swift` が
`WKContentRuleListStore.default()` に ETP (Disconnect系) + `ad-block` (RemoteSettings) を
`setupTrackingProtection(forTab:rules:)` (`:202-230`) で適用。
cosmetic (要素非表示) は無し (`TrackingProtectionStats.js` は統計報告のみ)。

### 2-1. リスト (内包済み・取得不要)
uBOL既定セット相当はコミット済みでそのまま使える:
- 生リスト: `WebVideoBoost/FilterLists/` (8ファイル + `manifest.json` に版記録)
- 変換済み: `WebVideoBoost/Sources/WebVideoBoost/AdBlock/Lists/wvb-ubo-part-{0,1,2}.json`
  (約11.6万ルール。`css-display-none` 1500件埋め込み済み)

Xcode側は `wvb-ubo-part-*.json` をアプリターゲットの Copy Bundle Resources に追加するだけ
(既存の `disconnect-block-*.json` と同列に置くと分かりやすい)。
SwiftPM参照なら `Bundle.module` から自動解決される。

更新したい時だけ:
```bash
cd WebVideoBoost/Tools
./fetch_ubol_lists.sh   # 最新取得 (manifest更新)
./update_ubol_lists.sh  # JSON再生成
```

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

## 4. 省メモリ運用 (ブラウザ全体が重い場合)

メモリ食いの主犯は (1)広告・トラッカーのJS/画像、(2)複数タブのWKWebView常駐。
対策は3層:

### 4-1. 軽量リストを使う (`--lite`)
```bash
python3 Tools/ublock_to_webkit.py --out <ListsLite> --lite
```
EasyList+Peter Lowe+uAssets filtersのみで約1/3のルール数。
体感ブロック率は維持しつつ、コンパイル時間・常駐メモリが減る。
低メモリ端末向けビルドはLiteを既定にするのが推奨。

### 4-2. 再生タブをoffloadから除外する
`TabManagerImplementation.offloadBackgroundWebViews` (`TabManagerImplementation.swift:1170-1185`) は
メモリ警告時に背景タブのWebViewを解放する。再生中タブを巻き込むと音が止まるため除外する:

```swift
// offloadBackgroundWebViews 内のフィルタに追加
let playingTabs = Set(tabs.filter { $0.webVideoBoost?.isPlaying == true }.map { $0 })
let backgroundTabsWithWebViews = tabs.filter {
    $0.webView != nil && $0 !== selectedTab && !playingTabs.contains($0)
}
```

タブ切替時には `MemorySaver.suspendInactive(allWebViews, active: current, protected: playingWebViews)`
を呼ぶ (メディア停止+ロード中断。WebView破棄より復帰が速い)。

### 4-3. 計測
- Xcode: Debug Navigator → Memory でタブ数 vs フットプリントを確認
- 目安: 広告ブロック有効で画像・iframe広告ページの常駐が大幅減 (重いページほど効果大)
- `MemorySaver.clearDiskCachesOlderThan()` はCookieを消さずキャッシュのみ掃除

## 5. 動作確認チェックリスト

- [ ] Safari同等ページで `<video>` 再生 → `boost.enterPiP()` でフローティング表示
- [ ] YouTube (m.youtube.com) で再生 → PiPボタン/JSの両経路でPiP
- [ ] `adblock-tester.com` でスコア向上 (ETPのみ時と比較)
- [ ] YouTubeプレロールでスキップボタン自動押下 / 不可広告の高速消化
- [ ] ホーム画面移行・画面ロック後も音声継続、ロック画面に再生コントロール表示
- [ ] ETP Strict/Standard切替後もuBOLルールが残る (2-2の回帰確認)

## 6. 他ブラウザへの転用

- `WebVideoBoost/` をそのままSwiftPM参照するだけ。呼び出しはREADMEの3行。
- リスト生成物 (`wvb-ubo-part-*.json`) はバンドル配置のみで流用可。
- Orion等WebKit系ブラウザも `configure + attach + didEnterBackground` の3点で同じ効果。
