import WebKit

/// MemorySaver: 複数WKWebViewを抱えるブラウザ用の省メモリヘルパー。
/// Firefox依存なし。TabManager (例: `offloadBackgroundWebViews`) や
/// 自前タブ管理から呼ぶ。再生中タブは `protected` に入れて解放から守る。
public final class MemorySaver: NSObject {
    /// 非選択タブを「一時停止」する。WebView自体は破棄しないため復帰が速い。
    /// - JSメディアを全停止 + ロード中断。画像デコード・JSタイマーが落ち着く。
    public static func suspend(_ webView: WKWebView) {
        webView.stopLoading()
        webView.evaluateJavaScript(
            "Array.from(document.querySelectorAll('video,audio')).forEach(m=>{try{m.pause()}catch(e){}});",
            completionHandler: nil)
    }

    /// 選択中以外のWebViewを一時停止する。
    /// - Parameters:
    ///   - webViews: 管理中の全WebView
    ///   - active: 現在表示中のWebView (停止しない)
    ///   - protected: バックグラウンド再生中など、停止してはいけないWebView
    /// - Returns: 停止した件数
    @discardableResult
    public static func suspendInactive(
        _ webViews: [WKWebView],
        active: WKWebView?,
        protected: [WKWebView] = []
    ) -> Int {
        var count = 0
        for wv in webViews {
            if wv === active { continue }
            if protected.contains(where: { $0 === wv }) { continue }
            suspend(wv)
            count += 1
        }
        return count
    }

    /// メモリ警告時の定番処理。通知側から呼ぶ:
    /// `NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification ...)`
    @discardableResult
    public static func handleMemoryWarning(
        webViews: [WKWebView],
        active: WKWebView?,
        protected: [WKWebView] = []
    ) -> Int {
        let n = suspendInactive(webViews, active: active, protected: protected)
        clearDiskCachesOlderThan(days: 7)
        return n
    }

    /// 古いディスクキャッシュの掃除 (メモリ本体ではないがWebKit全体の肥大化を抑える)。
    /// 実行は非同期。Cookieは消さない (ログイン維持)。
    public static func clearDiskCachesOlderThan(days: Double = 7) {
        let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
        let since = Date(timeIntervalSinceNow: -days * 86400)
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: since) {}
    }
}
