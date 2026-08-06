// HikeKit/Tests/HikeKitTests/TravelTimeStoreTests.swift
import XCTest
@testable import HikeKit

@MainActor
final class TravelTimeStoreTests: XCTestCase {
    var fileURL: URL!
    let home = UUID()
    let cottage = UUID()

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TravelTimeStoreTests-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func entry(_ seconds: Int) -> TravelTimeEntry {
        TravelTimeEntry(driveSeconds: seconds, fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testSetAndGetPersistAcrossReload() {
        let store = TravelTimeStore(fileURL: fileURL)
        store.set(entry(3600), locationID: home, slug: "triglav")
        XCTAssertEqual(store.entry(locationID: home, slug: "triglav")?.driveSeconds, 3600)
        XCTAssertNil(store.entry(locationID: home, slug: "unknown"))
        XCTAssertNil(store.entry(locationID: cottage, slug: "triglav"))

        let reloaded = TravelTimeStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entry(locationID: home, slug: "triglav")?.driveSeconds, 3600)
        XCTAssertEqual(reloaded.entry(locationID: home, slug: "triglav")?.fetchedAt,
                       Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testEntriesSurvivePerLocation() {
        let store = TravelTimeStore(fileURL: fileURL)
        store.set(entry(3600), locationID: home, slug: "triglav")
        store.set(entry(600), locationID: cottage, slug: "triglav")
        XCTAssertEqual(store.driveSeconds(for: home), ["triglav": 3600])
        XCTAssertEqual(store.driveSeconds(for: cottage), ["triglav": 600])
    }

    func testPurgeLocation() {
        let store = TravelTimeStore(fileURL: fileURL)
        store.set(entry(3600), locationID: home, slug: "triglav")
        store.set(entry(600), locationID: cottage, slug: "triglav")
        store.purgeLocation(id: home)
        XCTAssertTrue(store.driveSeconds(for: home).isEmpty)
        XCTAssertEqual(store.driveSeconds(for: cottage), ["triglav": 600])
        XCTAssertTrue(TravelTimeStore(fileURL: fileURL).driveSeconds(for: home).isEmpty)
    }

    func testPurgeHikeRemovesSlugFromAllLocations() {
        let store = TravelTimeStore(fileURL: fileURL)
        store.set(entry(3600), locationID: home, slug: "triglav")
        store.set(entry(1200), locationID: home, slug: "stol")
        store.set(entry(600), locationID: cottage, slug: "triglav")
        store.purgeHike(slug: "triglav")
        XCTAssertEqual(store.driveSeconds(for: home), ["stol": 1200])
        XCTAssertTrue(store.driveSeconds(for: cottage).isEmpty)
    }
}
