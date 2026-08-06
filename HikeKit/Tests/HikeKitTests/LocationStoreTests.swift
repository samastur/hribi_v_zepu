import XCTest
@testable import HikeKit

final class LocationStoreTests: XCTestCase {
    var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocationStoreTests-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testStartsEmpty() {
        let store = LocationStore(fileURL: fileURL)
        XCTAssertTrue(store.locations.isEmpty)
        XCTAssertNil(store.activeLocation)
    }

    func testFirstAddedLocationBecomesActive() {
        let store = LocationStore(fileURL: fileURL)
        let home = SavedLocation(name: "Dom", latitude: 46.05, longitude: 14.51)
        store.add(home)
        XCTAssertEqual(store.activeLocation?.id, home.id)
        let cottage = SavedLocation(name: "Vikend", latitude: 46.35, longitude: 14.10)
        store.add(cottage)
        XCTAssertEqual(store.activeLocation?.id, home.id, "adding more must not steal active")
    }

    func testSetActiveAndPersistAcrossReload() {
        let store = LocationStore(fileURL: fileURL)
        let home = SavedLocation(name: "Dom", latitude: 46.05, longitude: 14.51)
        let cottage = SavedLocation(name: "Vikend", latitude: 46.35, longitude: 14.10)
        store.add(home)
        store.add(cottage)
        store.setActive(id: cottage.id)

        let reloaded = LocationStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.locations.map(\.id), [home.id, cottage.id])
        XCTAssertEqual(reloaded.activeLocation?.id, cottage.id)
        XCTAssertEqual(reloaded.activeLocation?.name, "Vikend")
    }

    func testSetActiveIgnoresUnknownID() {
        let store = LocationStore(fileURL: fileURL)
        let home = SavedLocation(name: "Dom", latitude: 46.05, longitude: 14.51)
        store.add(home)
        store.setActive(id: UUID())
        XCTAssertEqual(store.activeLocation?.id, home.id)
    }

    func testDeleteActiveClearsActive() {
        let store = LocationStore(fileURL: fileURL)
        let home = SavedLocation(name: "Dom", latitude: 46.05, longitude: 14.51)
        store.add(home)
        store.delete(id: home.id)
        XCTAssertTrue(store.locations.isEmpty)
        XCTAssertNil(store.activeLocation)
        XCTAssertNil(LocationStore(fileURL: fileURL).activeLocation)
    }

    func testCoordinateBridge() {
        let loc = SavedLocation(name: "X", latitude: 46.1, longitude: 14.2)
        XCTAssertEqual(loc.coordinate, Coordinate(latitude: 46.1, longitude: 14.2))
    }
}
