import Foundation
import WebKit

/// UBOLAutoUpdater: アプリ内でuBOLリストを自動更新する。
/// 仕組み:
///   - WKContentRuleListStoreにコンパイル済みリストを保持。
///     更新は「古い識別子を全remove → 新しいのをcompileしてadd」。
///   - アプリ起動時にmanifestのbuiltAtとUserDefaults内の記録を比較。
///     異なる場合のみ`updateFromBundle()`を呼ぶ (自動更新は1回)。
///   - デフォルトはアプリ内バンドルのリストを使用。
///     オンライン更新は署名付きremote manifestを`updateFromRemote(url:)`で。
///
/// 注意: WKContentRuleListStoreはアプリ全体で共有されるため、
/// 古いリストremove中にタブが一瞬ブロックを失う可能性がある。
/// 実運用ではバックグラウンドで更新を済ませてからタブに紐付け直す。
public final class UBOLAutoUpdater: NSObject {
    public static let shared = UBOLAutoUpdater()
    public static let lastUpdateKey = "wvb.ubo.lastUpdate"
    public static let manifestKey = "wvb.ubo.manifest"

    public weak var delegate: UBOLAutoUpdaterDelegate?
    public private(set) var lastManifest: UBOLManifest?
    public private(set) var isUpdating = false

    public protocol UBOLAutoUpdaterDelegate: AnyObject {
        func updater(_ updater: UBOLAutoUpdater, didUpdate manifest: UBOLManifest)
        func updater(_ updater: UBOLAutoUpdater, failed error: Error)
    }

    public struct UBOLManifest: Codable, Equatable {
        public let format: Int
        public let builtAt: String
        public let parts: [Part]
        public let sha256: String
        public let totalBytes: Int
        public struct Part: Codable, Equatable {
            public let file: String
            public let sha256: String
            public let rules: Int
            public let bytes: Int
        }
    }

    private override init() {
        super.init()
        lastManifest = loadManifest()
    }

    // MARK: - 更新判定

    /// アプリ内リストの変更検出 (filesize合計で判定)
    public static func localFilesSize() -> Int? {
        guard let base = Bundle.main.url(forResource: "Lists", withExtension: nil)?.path else { return nil }
        var size = 0
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: base)
            for f in files.sorted() {
                if f.hasPrefix("wvb-ubo-part-") && f.hasSuffix(".json") {
                    let attrs = try FileManager.default.attributesOfItem(atPath: (base as NSString).appendingPathComponent(f))
                    size += attrs[.size] as? Int ?? 0
                }
            }
        } catch { return nil }
        return size
    }

    /// 更新が必要かどうか (filesize合計で判定)
    public var needsUpdate: Bool {
        guard let size = Self.localFilesSize() else { return true }
        return lastManifest?.totalBytes != size
    }

    // MARK: - アプリ内更新

    @discardableResult
    public func updateFromBundle() async -> Bool {
        guard !isUpdating else { return false }
        isUpdating = true
        defer { isUpdating = false }
        do {
            guard let store = WKContentRuleListStore.default(),
                  let manifest = loadManifest() else { return false }
            let available = await getAvailableIdentifiers(store)
            for id in available where id.hasPrefix("wvb-ubo-part-") {
                await removeSafely(store, identifier: id)
            }
            for part in manifest.parts {
                let name = part.file.replacingOccurrences(of: ".json", with: "")
                guard let json = UBOLContentBlocker.loadTextResource(name: name, ext: "json") else { continue }
                await compileAndRegister(store, identifier: part.file, json: json)
            }
            lastManifest = manifest
            saveManifest(manifest)
            delegate?.updater(self, didUpdate: manifest)
            return true
        } catch {
            delegate?.updater(self, failed: error)
            return false
        }
    }

    /// 署名付きremote manifestから更新
    public func updateFromRemote(url: URL) async -> Bool {
        do {
            let data = try await Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(UBOLManifest.self, from: data)
            lastManifest = manifest
            saveManifest(manifest)
            delegate?.updater(self, didUpdate: manifest)
            return true
        } catch {
            delegate?.updater(self, failed: error)
            return false
        }
    }

    // MARK: - Private

    private func saveManifest(_ manifest: UBOLManifest) {
        if let data = try? JSONEncoder().encode(manifest) {
            UserDefaults.standard.set(data, forKey: Self.manifestKey)
        }
        UserDefaults.standard.set(Date(), forKey: Self.lastUpdateKey)
    }

    private func loadManifest() -> UBOLManifest? {
        if let data = UserDefaults.standard.data(forKey: Self.manifestKey),
           let m = try? JSONDecoder().decode(UBOLManifest.self, from: data) { return m }
        guard let data = UBOLContentBlocker.loadTextResource(name: "lists-manifest", ext: "json"),
              let m = try? JSONDecoder().decode(UBOLManifest.self, from: Data(data.utf8)) else { return nil }
        return m
    }

    private func getAvailableIdentifiers(_ store: WKContentRuleListStore) async -> [String] {
        var ids: [String] = []
        let sem = DispatchSemaphore(value: 0)
        store.getAvailableContentRuleListIdentifiers { result in ids = result ?? []; sem.signal() }
        _ = sem.wait(timeout: .now() + 10)
        return ids
    }

    private func removeSafely(_ store: WKContentRuleListStore, identifier: String) async {
        let sem = DispatchSemaphore(value: 0)
        store.removeContentRuleList(forIdentifier: identifier) { _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 10)
    }

    private func compileAndRegister(_ store: WKContentRuleListStore, identifier: String, json: String) async {
        let sem = DispatchSemaphore(value: 0)
        store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { _, _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 60)
    }
}
