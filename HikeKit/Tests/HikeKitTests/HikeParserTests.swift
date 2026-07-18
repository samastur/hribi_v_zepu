import XCTest
@testable import HikeKit

func fixture(_ name: String) throws -> String {
    let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")!
    return try String(contentsOf: url, encoding: .utf8)
}

let zadnjicaURL = URL(string: "https://www.hribi.net/izlet/zadnjica_pogacnikov_dom_na_kriskih_podih/1/164/268")!
let mojstrovkaURL = URL(string: "https://www.hribi.net/izlet/vrsic_mala_mojstrovka_hanzova_pot/1/224/1148")!
let komarnaURL = URL(string: "https://www.hribi.net/izlet/komarna_vas_gace_/1/899/2354")!

final class HikeParserTests: XCTestCase {
    let parser = HikeParser()

    func testParsesTitleAndSlug() throws {
        let parsed = try parser.parse(html: try fixture("zadnjica"), sourceURL: zadnjicaURL)
        XCTAssertEqual(parsed.title, "Zadnjica - Pogačnikov dom na Kriških podih")
        XCTAssertEqual(parsed.slug, "zadnjica_pogacnikov_dom_na_kriskih_podih")
    }

    func testParsesMetadata() throws {
        let parsed = try parser.parse(html: try fixture("zadnjica"), sourceURL: zadnjicaURL)
        let get = { label in parsed.metadata.first { $0.label == label }?.value }
        XCTAssertEqual(get("Izhodišče"), "Zadnjica (642 m)")
        XCTAssertEqual(get("Čas hoje"), "4 h")
        XCTAssertEqual(get("Zahtevnost"), "lahka označena pot")
        XCTAssertEqual(get("Višinska razlika"), "1408 m")
        // stats noise must be skipped
        XCTAssertNil(get("Ogledov"))
        XCTAssertNil(get("Število slik"))
        XCTAssertNil(get("Število komentarjev"))
        // coordinates are structured, not a metadata row
        XCTAssertNil(get("Širina/Dolžina"))
    }

    func testParsesCoordinates() throws {
        let parsed = try parser.parse(html: try fixture("zadnjica"), sourceURL: zadnjicaURL)
        XCTAssertEqual(parsed.coordinate?.latitude ?? 0, 46.38240, accuracy: 0.0001)
        XCTAssertEqual(parsed.coordinate?.longitude ?? 0, 13.76040, accuracy: 0.0001)
    }

    func testParsesOtherFixtures() throws {
        let mojstrovka = try parser.parse(html: try fixture("mojstrovka"), sourceURL: mojstrovkaURL)
        XCTAssertEqual(mojstrovka.title, "Vršič - Mala Mojstrovka (Hanzova pot)")
        XCTAssertEqual(mojstrovka.metadata.first { $0.label == "Zahtevnost" }?.value, "zelo zahtevna označena pot")

        let komarna = try parser.parse(html: try fixture("komarna_vas"), sourceURL: komarnaURL)
        XCTAssertEqual(komarna.title, "Komarna vas - Gače")
        XCTAssertEqual(komarna.coordinate?.latitude ?? 0, 45.67200, accuracy: 0.0001)
    }

    func testThrowsWhenTitleMissing() {
        XCTAssertThrowsError(try parser.parse(html: "<html><body>nope</body></html>", sourceURL: zadnjicaURL)) {
            XCTAssertEqual($0 as? HikeParserError, .titleNotFound)
        }
    }
}
