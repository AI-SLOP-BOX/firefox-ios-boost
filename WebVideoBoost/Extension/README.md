# YouTube Boost (Safari Web Extension)

YouTube用の **PiPボタン＋バックグラウンド再生維持** 拡張機能。
広告ブロックは含まない (uBOL等と併用する前提)。

## 機能

- 動画ページにフローティング「PiP」ボタン (タップ一発でPiP。Safari標準API→失敗時webkit方式)
- ポップアップから「今の動画をPiPにする」
- バックグラウンド維持: `document.hidden`偽装＋背景突入時の自動`pause()`抑止 (ページ世界ガード)
- 設定トグル (PiPボタン表示 / バックグラウンド維持) は`chrome.storage.sync`で同期

## 構成

```
Extension/
  manifest.json                 # MV3。YouTube系ドメイン限定
  content/youtube_boost.js      # isolated world: ボタン・監視・popup連携
  content/youtube_boost.css     # ボタン見た目
  content/page_guard.js         # page world: hidden偽装・pause抑止 (scriptタグ注入)
  popup/popup.html, popup.js    # トグル + PiPボタン
  icons/icon{16,48,128}.png
```

## 試し方 (署名なし・開発中)

### Safari (Mac)
1. Safari → 設定 → 詳細 →「メニューバーに“開発”メニューを表示」
2. 開発 →「未署名の機能拡張を許可」
3. 開発 → 拡張機能ビルダーを使わない場合: Xcodeターゲット化 (下記) が正規ルート。
   手軽には Chrome/Edge の手順で動作確認できる (MV3互換のため)。

### Chrome / Edge (動作確認用)
1. `chrome://extensions` → デベロッパーモードON
2. 「パッケージ化されていない拡張機能を読み込む」→ この`Extension/`フォルダを選択
3. youtube.comを開いてPiPボタンが出ることを確認

### iOS Safari で使う (正規ルート)
1. Xcodeでホストアプリ (本フォーク等) に Safari Extension ターゲットを追加し、
   この`Extension/`をリソースとして組み込む
2. 実機ビルド → 設定 → Safari → 機能拡張 → YouTube BoostをON
3. App Store配布には有料Developer Programが必要

## 制限 (正直メモ)

- PiP開始にはユーザージェスチャ (transient activation・数秒) が必須で、裏からの無条件自動突入は不可。
  そのため本拡張は「裏に回った瞬間に1回だけ黙って試す」ベストエフォートを実装
  (`autoPip` 設定・既定ON)。再生ボタン押下直後に裏に回した場合などに成功する。
  Chromium系では `autoPictureInPicture` 属性も付与 (対応ブラウザのタブ切替自動PiP用)。
  iOSは「設定 > 一般 > ピクチャインピクチャ > 自動で開始」ONでOS側自動PiPも効く。
  確実にPiPにする運用はボタンのタップ。
- iOSで画面ロック・他アプリ移行後の継続は、OSのオーディオセッションに依存。
  アプリ内ブラウザ版 (WebVideoBoost本体) と違い、拡張機能はSafariの再生管理に乗る
- YouTubeのDOM変更でボタン位置等がずれる可能性あり (セレクタは広めに取得)
