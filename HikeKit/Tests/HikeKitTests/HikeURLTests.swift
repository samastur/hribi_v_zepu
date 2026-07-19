import XCTest
@testable import HikeKit

final class HikeURLTests: XCTestCase {
    func testValidHikeURL() {
        let url = HikeURL.validate("https://www.hribi.net/izlet/zadnjica_pogacnikov_dom_na_kriskih_podih/1/164/268")
        XCTAssertEqual(url?.absoluteString, "https://www.hribi.net/izlet/zadnjica_pogacnikov_dom_na_kriskih_podih/1/164/268")
    }

    func testStripsFragmentAndForcesHTTPS() {
        let url = HikeURL.validate("http://hribi.net/izlet/some_hike/1/2/3#diskusije")
        XCTAssertEqual(url?.absoluteString, "https://hribi.net/izlet/some_hike/1/2/3")
    }

    func testTrimsWhitespace() {
        XCTAssertNotNil(HikeURL.validate("  https://www.hribi.net/izlet/x/1/2/3\n"))
    }

    func testRejectsNonHikePages() {
        XCTAssertNil(HikeURL.validate("https://www.hribi.net/gora/triglav/1/1"))
        XCTAssertNil(HikeURL.validate("https://example.com/izlet/fake/1/2/3"))
        XCTAssertNil(HikeURL.validate("not a url"))
        XCTAssertNil(HikeURL.validate("https://www.hribi.net/izlet"))
    }

    func testSlugExtraction() {
        let url = URL(string: "https://www.hribi.net/izlet/zadnjica_pogacnikov_dom_na_kriskih_podih/1/164/268")!
        XCTAssertEqual(HikeURL.slug(from: url), "zadnjica_pogacnikov_dom_na_kriskih_podih")
        XCTAssertNil(HikeURL.slug(from: URL(string: "https://www.hribi.net/gora/x/1")!))
    }

    func testRejectsPathTraversalSlugs() {
        XCTAssertNil(HikeURL.validate("https://www.hribi.net/izlet/../etc/1/2/3"))
        XCTAssertNil(HikeURL.validate("https://www.hribi.net/izlet/./x/1/2/3"))
        XCTAssertNil(HikeURL.slug(from: URL(string: "https://www.hribi.net/izlet/%2E%2E/x/1/2")!))
    }

    // MARK: - extractHikeURL(fromText:)

    func testExtractHikeURLFromPlainURLString() {
        let result = HikeURL.extractHikeURL(fromText: "https://www.hribi.net/izlet/zadnjica_pogacnikov_dom_na_kriskih_podih/1/164/268")
        XCTAssertEqual(result?.absoluteString, "https://www.hribi.net/izlet/zadnjica_pogacnikov_dom_na_kriskih_podih/1/164/268")
    }

    func testExtractHikeURLFromSurroundingText() {
        let text = "Zadnjica - opis izleta https://www.hribi.net/izlet/zadnjica_pogacnikov_dom_na_kriskih_podih/1/164/268"
        let result = HikeURL.extractHikeURL(fromText: text)
        XCTAssertEqual(result?.absoluteString, "https://www.hribi.net/izlet/zadnjica_pogacnikov_dom_na_kriskih_podih/1/164/268")
    }

    func testExtractHikeURLReturnsNilForNoLinks() {
        XCTAssertNil(HikeURL.extractHikeURL(fromText: "no links here"))
    }

    func testExtractHikeURLReturnsNilForNonHikeURL() {
        XCTAssertNil(HikeURL.extractHikeURL(fromText: "https://example.com/izlet/x/1/2"))
    }

    func testExtractsURLWithTrailingPunctuation() {
        let url = HikeURL.extractHikeURL(fromText: "poglej: https://www.hribi.net/izlet/komarna_vas_gace_/1/899/2354.")
        XCTAssertEqual(url?.absoluteString, "https://www.hribi.net/izlet/komarna_vas_gace_/1/899/2354")
    }
}
