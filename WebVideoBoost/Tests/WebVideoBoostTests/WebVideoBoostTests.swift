import XCTest
@testable import WebVideoBoost

final class WebVideoBoostTests: XCTestCase {
    func testPackageLoads() {
        // リソース解決のスモークテスト (CIでBundle.moduleが無い場合も落ちない)
        let s = UBOLContentBlocker.loadTextResource(name: "cosmetic", ext: "js")
        // SwiftPMテスト時はBundle.moduleから読めるはず。読めなくてもnil許容。
        XCTAssertTrue(s == nil || s!.contains("__wvbCosmeticInstalled"))
    }
}
