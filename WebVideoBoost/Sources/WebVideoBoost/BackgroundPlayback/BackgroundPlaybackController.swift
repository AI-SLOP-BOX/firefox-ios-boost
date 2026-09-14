#if os(iOS)
import AVFoundation
import MediaPlayer
#endif
import WebKit

/// BackgroundPlayback: WKWebViewの音をバックグラウンドでも継続させる。
/// 依存は AVFoundation/MediaPlayer/WebKit のみ (Firefox非依存で他ブラウザ転用可)。
///
/// 必須の組み合わせ (どれか欠けると止まる):
///  1. Info.plist `UIBackgroundModes` に `audio` (firefox-iosは既存: Client/Info.plist:216)
///  2. 本クラスの `activateSession()` (.playback カテゴリ)
///  3. WebViewを破棄しない (タブ切替・backgroundで close/removeAll しない)
///  4. 本JS (`background_playback.js`) でページ側の自動pauseを抑止
public final class BackgroundPlaybackController: NSObject {
    public static let messageHandlerName = "wvbBg"

    public weak var webView: WKWebView?
    public var onEvent: ((String) -> Void)?

    /// リモコン/NowPlaying表示に使うメタデータ
    public var nowPlayingTitle: String?
    public var nowPlayingArtist: String?

    /// 現在再生中かどうか (JS側のplay/pauseイベントで更新)。
    /// MemorySaverやTabManagerのoffload判定 (`protected`) に使う。
    public private(set) var isPlaying = false

    private var installed = false

    public init(webView: WKWebView? = nil) {
        self.webView = webView
        super.init()
    }

    // MARK: - Audio session

    /// アプリ起動時 (AppDelegate didFinishLaunching) で1回呼ぶ。
    @discardableResult
    public func activateSession() -> Bool {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback: 無音スイッチを無視し、バックグラウンド継続を許可
            // .mixWithOthersを付けない = 他アプリの音を止めて前面化 (ブラウザ再生として自然)
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: - WebView install

    public func install(into webView: WKWebView, controller: WKUserContentController? = nil) {
        guard !installed else { return }
        installed = true
        self.webView = webView
        let ucc = controller ?? webView.configuration.userContentController
        ucc.add(self, name: Self.messageHandlerName)
        if let source = Self.scriptSource() {
            // 背景抑止は documentStart で入れて visibilitychange 登録より先に割り込む
            let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            ucc.addUserScript(script)
        }
        setupRemoteCommands()
    }

    public func uninstall(from webView: WKWebView? = nil) {
        (webView ?? self.webView)?.configuration.userContentController
            .removeScriptMessageHandler(forName: Self.messageHandlerName)
        installed = false
    }

    /// アプリがバックグラウンドに入る直前に呼ぶと、直後のpauseをJS側で捨てる。
    /// SceneDelegate.sceneDidEnterBackground / AppDelegate.applicationDidEnterBackground から呼ぶ。
    /// - Parameter guardSeconds: ガードする秒数 (既定2.0秒)。長すぎるとユーザーの明示pauseも効かなくなる。
    public func beginBackgroundGuard(guardSeconds: Double = 2.0) {
        webView?.evaluateJavaScript("window.__wvbBgGuard = true;", completionHandler: nil)
        isPlaying = true
        updateNowPlaying(isPlaying: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + guardSeconds) { [weak self] in
            self?.webView?.evaluateJavaScript("window.__wvbBgGuard = false;", completionHandler: nil)
        }
    }

    /// ユーザーが明示的に停止した場合は次1回のpauseだけ通す (ガードで捨てない)。
    public func allowNextPauseOnce() {
        webView?.evaluateJavaScript("window.__wvbAllowPauseOnce = true;", completionHandler: nil)
        isPlaying = false
        updateNowPlaying(isPlaying: false)
    }

    // MARK: - Now Playing / Remote commands

    private func setupRemoteCommands() {
        #if os(iOS)
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true

        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            self?.webView?.evaluateJavaScript(
                "Array.from(document.querySelectorAll('video,audio')).forEach(m=>m.play&&m.play());",
                completionHandler: nil)
            self?.updateNowPlaying(isPlaying: true)
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.allowNextPauseOnce()
            self?.webView?.evaluateJavaScript(
                "Array.from(document.querySelectorAll('video,audio')).forEach(m=>m.pause&&m.pause());",
                completionHandler: nil)
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.webView?.evaluateJavaScript(
                """
                (function(){var m=document.querySelector('video,audio');if(!m)return 'none';
                if(m.paused){m.play();return 'play';}else{m.pause();return 'pause';}})()
                """,
                completionHandler: nil)
            return .success
        }
        #endif
    }

    public func updateNowPlaying(isPlaying: Bool) {
        #if os(iOS)
        var info: [String: Any] = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if let t = nowPlayingTitle { info[MPMediaItemPropertyTitle] = t }
        if let a = nowPlayingArtist { info[MPMediaItemPropertyArtist] = a }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    // MARK: - Private

    static func scriptSource() -> String? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "background_playback", withExtension: "js"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return s
        }
        #endif
        return nil
    }
}

// MARK: - WKScriptMessageHandler
extension BackgroundPlaybackController: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName else { return }
        var type = "event"
        if let body = message.body as? [String: Any], let t = body["type"] as? String { type = t }
        if type == "play" { isPlaying = true; updateNowPlaying(isPlaying: true) }
        if type == "pause" || type == "ended" { isPlaying = false; updateNowPlaying(isPlaying: false) }
        onEvent?(type)
    }
}
