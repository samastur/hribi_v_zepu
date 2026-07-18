import XCTest
@testable import HikeKit

final class HikeModelTests: XCTestCase {
    func makeHike() -> Hike {
        Hike(
            slug: "test_hike",
            sourceURL: URL(string: "https://www.hribi.net/izlet/test_hike/1/2/3")!,
            title: "Test Hike",
            metadata: [MetadataField(label: "Čas hoje", value: "4 h")],
            coordinate: Coordinate(latitude: 46.3824, longitude: 13.7604),
            sections: [HikeSection(title: "Opis poti", paragraphs: ["Prvi odstavek.", "Drugi odstavek."])],
            images: [HikeImage(filename: "001.jpg", remoteURL: URL(string: "https://www.hribi.net/slike1/a.jpg")!, caption: "A caption")],
            expectedImageCount: 2,
            dateAdded: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testCodableRoundTrip() throws {
        let hike = makeHike()
        let data = try JSONEncoder.hike.encode(hike)
        let decoded = try JSONDecoder.hike.decode(Hike.self, from: data)
        XCTAssertEqual(decoded, hike)
    }

    func testMetadataValueLookup() {
        let hike = makeHike()
        XCTAssertEqual(hike.metadataValue("Čas hoje"), "4 h")
        XCTAssertNil(hike.metadataValue("Zahtevnost"))
    }

    func testHikeImageCaptionCodableRoundTrip() throws {
        let image = HikeImage(filename: "001.jpg", remoteURL: URL(string: "https://www.hribi.net/slike1/a.jpg")!, caption: "Pot se vrne v gozd.")
        let data = try JSONEncoder.hike.encode(image)
        let decoded = try JSONDecoder.hike.decode(HikeImage.self, from: data)
        XCTAssertEqual(decoded, image)
        XCTAssertEqual(decoded.caption, "Pot se vrne v gozd.")
    }

    func testHikeImageLegacyDecodingNilCaption() throws {
        // JSON without a "caption" key — backward compat with already-saved hikes
        let json = """
        {"filename":"001.jpg","remoteURL":"https://www.hribi.net/slike1/a.jpg"}
        """
        let decoded = try JSONDecoder.hike.decode(HikeImage.self, from: Data(json.utf8))
        XCTAssertNil(decoded.caption, "legacy JSON without caption key must decode caption as nil")
    }
}
