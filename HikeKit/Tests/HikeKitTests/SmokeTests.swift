import XCTest
@testable import HikeKit

final class SmokeTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertEqual(HikeKit.version, "0.1.0")
    }
}
