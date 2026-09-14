import WebKit

/// UBOLContentBlocker: uBlock Origin Lite相当のフィルタをWKWebViewに適用する。
/// - ネットワーク遮断は WKContentRuleList (WebKit content-blocker JSON) で行う
///   (Tools/ublock_to_webkit.py が uAssets/EasyList等から生成。50k件ごとに分割)
/// - cosmetic (要素非表示) は WebKitの css-display-none + cosmetic.js の二段構え
/// - YouTube動画内広告はDOM操作の youtube_adskip.js で補助
/// - Firefox依存なし。他ブラウザでも `install(into:)` だけで使える。
public final class UBOLContentBlocker: NSObject {
    /// WKContentRuleListStore上の識別子プレフィックス。Tools出力と一致させる。
    public static let ruleIdentifierPrefix = "wvb-ubo-part-"
    public static let cosmeticHandlerName = "wvbCosmetic"

    public weak var webView: WKWebView?
    private var installed = false

    /// バンドル/アプリ内に配置した生成JSONのファイル名群 (例: ["wvb-ubo-part-0", ...])。
    /// 既定はメインバンドルから prefix 検索で自動検出を試みる。
    public var bundledListNames: [String]?

    public override init() { super.init() }

    // MARK: - Install

    /// - Parameters:
    ///   - webView: 適用先
    ///   - bundledListNames: 生成JSONのベース名配列。nilなら自動検出。
    ///   - enableCosmetic: 要素非表示JSを入れるか
    ///   - enableYouTubeSkip: YouTube動画内広告スキップを入れるか
    public func install(
        into webView: WKWebView,
        bundledListNames: [String]? = nil,
        enableCosmetic: Bool = true,
        enableYouTubeSkip: Bool = true
    ) {
        guard !installed else { return }
        installed = true
        self.webView = webView
        self.bundledListNames = bundledListNames

        let ucc = webView.configuration.userContentController
        if enableCosmetic, let src = Self.loadTextResource(name: "cosmetic", ext: "js") {
            ucc.addUserScript(WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        if enableYouTubeSkip, let src = Self.loadTextResource(name: "youtube_adskip", ext: "js") {
            ucc.addUserScript(WKUserScript(source: src, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        }
        applyNetworkRules(to: webView, listNames: bundledListNames)
    }

    // MARK: - Network rules

    /// コンパイル済みJSONをWKContentRuleListStoreに登録し、webViewにaddする。
    /// firefox-ios統合時は既存の ContentBlocker.shared.setupTrackingProtection と競合しないよう、
    /// `removeAllContentRuleLists()` を呼ばず追加のみ行う (Firefox側は追記方式に変更する。Docs参照)。
    public func applyNetworkRules(to webView: WKWebView, listNames: [String]? = nil) {
        let names = listNames ?? self.bundledListNames ?? Self.discoverBundledLists()
        guard !names.isEmpty else { return }
        guard let store = WKContentRuleListStore.default() else { return }
        let ucc = webView.configuration.userContentController
        for name in names {
            guard let json = Self.loadTextResource(name: name, ext: "json") else { continue }
            // 識別子はファイル名をそのまま使い、再コンパイル済みならlookupで再利用
            store.lookUpContentRuleList(forIdentifier: name) { existing, _ in
                if let existing = existing {
                    ucc.add(existing)
                    return
                }
                store.compileContentRuleList(forIdentifier: name, encodedContentRuleList: json) { rule, _ in
                    if let rule = rule {
                        DispatchQueue.main.async { ucc.add(rule) }
                    }
                }
            }
        }
    }

    // MARK: - Helpers (public for tests / Firefox integration)

    /// メインバンドル + SwiftPM Bundle.module からテキストリソースを読む。
    /// 内包リスト (AdBlock/Lists/*.json) はサブディレクトリも探す。
    public static func loadTextResource(name: String, ext: String) -> String? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: ext),
           let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Lists"),
           let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        #endif
        if let url = Bundle.main.url(forResource: name, withExtension: ext),
           let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Lists"),
           let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        return nil
    }

    /// `<prefix><number>.json` をバンドル内から自動検出 (最大20パート)
    public static func discoverBundledLists(prefix: String = ruleIdentifierPrefix, maxParts: Int = 20) -> [String] {
        var out: [String] = []
        for i in 0..<maxParts {
            let name = "\(prefix)\(i)"
            #if SWIFT_PACKAGE
            if Bundle.module.url(forResource: name, withExtension: "json") != nil { out.append(name); continue }
            #endif
            if Bundle.main.url(forResource: name, withExtension: "json") != nil { out.append(name); continue }
            // 連番が途切れたら終了 (part-0必須)
            if !out.isEmpty { break }
        }
        return out
    }
}
