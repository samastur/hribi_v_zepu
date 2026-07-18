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
            images: [HikeImage(filename: "001.jpg", remoteURL: URL(string: "https://www.hribi.net/slike1/a.jpg")!)],
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
}
