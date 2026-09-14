import WebKit

/// WebVideoBoost: PiP + uBOL強化広告ブロック + バックグラウンド再生をひとまとめにするFacade。
/// 他ブラウザへの転用はこのクラスだけ見ればよい。
/// ```swift
/// let boost = WebVideoBoost()
/// WebVideoBoost.configureForNewWebView(configuration) // configuration生成直後
/// boost.attach(to: webView) // webView生成直後 (UserScript/MessageHandler登録)
/// boost.enterPiP()
/// ```
public final class WebVideoBoost {
    public let pip: VideoPiPController
    public let background: BackgroundPlaybackController
    public let adblock: UBOLContentBlocker

    /// バックグラウンド再生を有効にするか (審査が厳しい場合はfalse)
    public var enableBackgroundAudio = true
    public var enableAdblock = true
    public var enablePiP = true
    /// バックグラウンド突入時に自動PiPを試すか (既定false)。
    /// 成功はタップ直後などtransient activationが残っている場合に限られる。
    /// 音声継続が主目的ならfalseのままでよい (pause抑止で音は残る)。
    public var autoPiPOnBackground = false

    public init() {
        self.pip = VideoPiPController()
        self.background = BackgroundPlaybackController()
        self.adblock = UBOLContentBlocker()
    }

    // MARK: - Static (configuration生成時に呼ぶ)

    /// WKWebViewConfiguration生成直後に呼ぶ。PiPに必要なフラグを立てる。
    public static func configureForNewWebView(_ configuration: WKWebViewConfiguration) {
        VideoPiPController.configure(configuration)
    }

    // MARK: - Attach (webView生成直後に呼ぶ)

    /// - Parameters:
    ///   - adblockListNames: uBOL生成JSON名。nilなら自動検出。
    ///   - nowPlayingTitle/Artist: ロック画面表示用
    public func attach(
        to webView: WKWebView,
        adblockListNames: [String]? = nil,
        nowPlayingTitle: String? = nil,
        nowPlayingArtist: String? = nil
    ) {
        if enablePiP {
            pip.install(into: webView)
        }
        if enableAdblock {
            adblock.install(into: webView, bundledListNames: adblockListNames)
        }
        if enableBackgroundAudio {
            background.nowPlayingTitle = nowPlayingTitle
            background.nowPlayingArtist = nowPlayingArtist
            _ = background.activateSession()
            background.install(into: webView)
        }
        // 相互参照用にwebViewを保持
        pip.webView = webView
        background.webView = webView
        adblock.webView = webView
    }

    /// アプリがバックグラウンドに入る時に呼ぶ (SceneDelegate/AppDelegateから)
    public func didEnterBackground() {
        guard enableBackgroundAudio else { return }
        background.beginBackgroundGuard()
        if enablePiP && autoPiPOnBackground {
            pip.webView?.evaluateJavaScript(
                "window.__wvbTryAutoPiP ? window.__wvbTryAutoPiP() : 'not-installed'",
                completionHandler: nil)
        }
    }

    /// 再生中かどうか。タブ解放 (`offloadBackgroundWebViews` 等) から外す判定に使う。
    public var isPlaying: Bool { background.isPlaying }

    // MARK: - Convenience

    public func enterPiP(completion: ((Any?) -> Void)? = nil) {
        pip.enterPiP(completion: completion)
    }

    public func exitPiP(completion: ((Any?) -> Void)? = nil) {
        pip.exitPiP(completion: completion)
    }
}
