import XCTest
@testable import HikeKit

final class MapLinksTests: XCTestCase {
    let zadnjica = Coordinate(latitude: 46.3824, longitude: 13.7604)

    func testGoogleMapsURLUsesUniversalDirectionsFormat() {
        XCTAssertEqual(MapLinks.googleMaps(to: zadnjica).absoluteString,
                       "https://www.google.com/maps/dir/?api=1&destination=46.3824,13.7604")
    }

    func testAppleMapsURL() {
        XCTAssertEqual(MapLinks.appleMaps(to: zadnjica).absoluteString,
                       "https://maps.apple.com/?daddr=46.3824,13.7604")
    }
}
