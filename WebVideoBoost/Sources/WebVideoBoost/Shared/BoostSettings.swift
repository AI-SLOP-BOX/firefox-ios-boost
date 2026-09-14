import Foundation

/// BoostSettings: WebVideoBoostの機能ON/OFFをUserDefaultsに永続化する。
/// 設定画面 (FirefoxのSettings等) から3行で配線できる:
/// ```swift
/// var settings = BoostSettings.load()
/// settings.pipEnabled = toggle.isOn // PiPいらなければfalse
/// settings.save().apply(to: boost)  // 最新のboostに反映
/// ```
/// 注意: PiPのUserScriptはWebView生成時に注入されるため、OFFへの切り替えは
/// 次に開くタブ (新WebView) から反映される。既存タブは `enterPiP()` が無効化される。
public struct BoostSettings {
    public static let pipEnabledKey = "wvb.pip.enabled"
    public static let backgroundAudioEnabledKey = "wvb.backgroundAudio.enabled"
    public static let adblockEnabledKey = "wvb.adblock.enabled"

    public var pipEnabled = true
    public var backgroundAudioEnabled = true
    public var adblockEnabled = true

    public init() {}
    public init(pipEnabled: Bool, backgroundAudioEnabled: Bool, adblockEnabled: Bool) {
        self.pipEnabled = pipEnabled
        self.backgroundAudioEnabled = backgroundAudioEnabled
        self.adblockEnabled = adblockEnabled
    }

    public static func load(from defaults: UserDefaults = .standard) -> BoostSettings {
        var s = BoostSettings()
        // 初回 (キー未登録) はtrue扱いにするためobject(forKey:)の有無で判定
        if defaults.object(forKey: pipEnabledKey) != nil {
            s.pipEnabled = defaults.bool(forKey: pipEnabledKey)
        }
        if defaults.object(forKey: backgroundAudioEnabledKey) != nil {
            s.backgroundAudioEnabled = defaults.bool(forKey: backgroundAudioEnabledKey)
        }
        if defaults.object(forKey: adblockEnabledKey) != nil {
            s.adblockEnabled = defaults.bool(forKey: adblockEnabledKey)
        }
        return s
    }

    @discardableResult
    public func save(to defaults: UserDefaults = .standard) -> BoostSettings {
        defaults.set(pipEnabled, forKey: Self.pipEnabledKey)
        defaults.set(backgroundAudioEnabled, forKey: Self.backgroundAudioEnabledKey)
        defaults.set(adblockEnabled, forKey: Self.adblockEnabledKey)
        return self
    }

    /// WebVideoBoostインスタンスに反映する。`attach(to:)` の前に呼ぶ。
    public func apply(to boost: WebVideoBoost) {
        boost.enablePiP = pipEnabled
        boost.enableBackgroundAudio = backgroundAudioEnabled
        boost.enableAdblock = adblockEnabled
        if !pipEnabled { boost.autoPiPOnBackground = false }
    }
}
