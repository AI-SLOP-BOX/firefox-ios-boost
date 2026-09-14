import WebKit

/// VideoPiP: WKWebViewにPiP能力を付与する薄いラッパー。
/// - 他ブラウザ転用可: 依存は WebKit のみ。Firefox固有コードを含まない。
/// - 使い方:
///   1. `VideoPiP.configure(_:)` を WKWebViewConfiguration 生成直後に呼ぶ
///   2. WebView生成後に `VideoPiP.install(into:delegate:)` を呼ぶ (UserScript+MessageHandler登録)
///   3. ツールバーボタン等から `controller.enterPiP()` を呼ぶ
public final class VideoPiPController: NSObject {
    public static let messageHandlerName = "wvbPip"

    public weak var webView: WKWebView?
    /// PiP状態変化をUIに反映したい場合に使う (enter/leave/no-video/unsupported)
    public var onEvent: ((String) -> Void)?

    private var installed = false

    public init(webView: WKWebView? = nil) {
        self.webView = webView
    }

    // MARK: - Configuration (WebView生成前に呼ぶ)

    /// WKWebViewConfigurationにPiP/インライン再生を許可する。
    /// firefox-iosでは `DefaultWKEngineConfigurationProvider.createConfiguration` の
    /// `allowsInlineMediaPlayback = true` の直後に呼ぶのが統合点。
    public static func configure(_ configuration: WKWebViewConfiguration) {
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        #else
        _ = configuration
        #endif
        if configuration.mediaTypesRequiringUserActionForPlayback.contains(.all) {
            // PiP/バックグラウンド再生を使いやすくするため、可能なら自動再生制限を緩和。
            // ポリシー上厳しくしたい場合は呼び出し側で上書きしてよい。
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }
    }

    // MARK: - Install (WebView生成後に呼ぶ)

    /// UserScriptとMessageHandlerを登録する。多重呼び出しは無視される。
    public func install(into webView: WKWebView, controller: WKUserContentController? = nil) {
        guard !installed else { return }
        installed = true
        self.webView = webView
        let ucc = controller ?? webView.configuration.userContentController
        ucc.add(self, name: Self.messageHandlerName)
        if let source = Self.scriptSource() {
            let script = WKUserScript(
                source: source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            ucc.addUserScript(script)
        }
    }

    public func uninstall(from webView: WKWebView? = nil) {
        let target = webView ?? self.webView
        target?.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
        installed = false
    }

    // MARK: - Actions

    /// JS内の __wvbEnterPiP() を叩く。完了は onEvent または completion で受け取る。
    public func enterPiP(completion: ((Any?) -> Void)? = nil) {
        webView?.evaluateJavaScript("window.__wvbEnterPiP ? window.__wvbEnterPiP() : 'not-installed'", completionHandler: { result, _ in
            completion?(result)
        })
    }

    public func exitPiP(completion: ((Any?) -> Void)? = nil) {
        webView?.evaluateJavaScript("window.__wvbExitPiP ? window.__wvbExitPiP() : 'not-installed'", completionHandler: { result, _ in
            completion?(result)
        })
    }

    // MARK: - Private

    static func scriptSource() -> String? {
        // SwiftPM resources から読む。単体利用でBundleが見つからない場合はnil。
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "video_pip", withExtension: "js"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return s
        }
        #endif
        return nil
    }
}

// MARK: - WKScriptMessageHandler
extension VideoPiPController: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName else { return }
        var type = "event"
        if let body = message.body as? [String: Any], let t = body["type"] as? String {
            type = t
        } else if let t = message.body as? String {
            type = t
        }
        onEvent?(type)
    }
}
