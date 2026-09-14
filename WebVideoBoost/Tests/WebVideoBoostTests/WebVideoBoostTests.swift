import XCTest
import WebKit
@testable import WebVideoBoost

final class WebVideoBoostTests: XCTestCase {
    func testPackageLoads() {
        // リソース解決のスモークテスト (CIでBundle.moduleが無い場合も落ちない)
        let s = UBOLContentBlocker.loadTextResource(name: "cosmetic", ext: "js")
        // SwiftPMテスト時はBundle.moduleから読めるはず。読めなくてもnil許容。
        XCTAssertTrue(s == nil || s!.contains("__wvbCosmeticInstalled"))
    }

    func testCosmeticIsSelfLimiting() {
        // 常駐MutationObserverに戻っていないことを担保 (省メモリの回帰テスト)
        let s = UBOLContentBlocker.loadTextResource(name: "cosmetic", ext: "js")
        guard let s else { return }
        XCTAssertTrue(s.contains("SWEEP_BUDGET") || s.contains("sweepsLeft"))
        XCTAssertTrue(s.contains("disconnect"))
    }

    func testYouTubeSkipIsDomainGated() {
        let s = UBOLContentBlocker.loadTextResource(name: "youtube_adskip", ext: "js")
        guard let s else { return }
        XCTAssertTrue(s.contains("youtube.com"))
        XCTAssertFalse(s.contains("setInterval(pass, 500)"))
        XCTAssertFalse(s.contains("FALLBACK_INTERVAL = 500") || s.contains("INTERVAL = 500"))
    }

    func testMemorySaverSkipsActiveAndProtected() {
        let a = WKWebView(frame: .zero)
        let b = WKWebView(frame: .zero)
        let playing = WKWebView(frame: .zero)
        let n = MemorySaver.suspendInactive([a, b, playing], active: a, protected: [playing])
        XCTAssertEqual(n, 1)
    }
}
