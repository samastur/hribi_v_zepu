import XCTest
@testable import HikeKit

/// Single-threaded in tests; recorded state read only after fill() returns.
final class FakeEstimator: RouteEstimator, @unchecked Sendable {
    var requestedSlugsByCoordinate: [Coordinate] = []
    var failFor: Set<Double> = []  // destination latitudes that throw

    struct NoRoute: Error {}

    func driveTime(from: Coordinate, to: Coordinate) async throws -> TimeInterval {
        requestedSlugsByCoordinate.append(to)
        if failFor.contains(to.latitude) { throw NoRoute() }
        return 60 * to.latitude  // deterministic, distinguishable per hike
    }
}

@MainActor
final class TravelTimeServiceTests: XCTestCase {
    var fileURL: URL!
    var store: TravelTimeStore!
    var estimator: FakeEstimator!
    var service: TravelTimeService!
    let location = SavedLocation(name: "Dom", latitude: 46.05, longitude: 14.51)

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TravelTimeServiceTests-\(UUID().uuidString).json")
        store = TravelTimeStore(fileURL: fileURL)
        estimator = FakeEstimator()
        service = TravelTimeService(estimator: estimator, store: store, spacing: .zero)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func makeHike(slug: String, latitude: Double?) -> Hike {
        Hike(slug: slug, sourceURL: URL(string: "https://www.hribi.net/izlet/\(slug)/1/2/3")!,
             title: slug, metadata: [],
             coordinate: latitude.map { Coordinate(latitude: $0, longitude: 13.8) },
             sections: [], images: [], expectedImageCount: 0,
             dateAdded: Date(timeIntervalSince1970: 0))
    }

    func testFillsMissingEntriesAndSkipsHikesWithoutCoordinate() async {
        let hikes = [makeHike(slug: "a", latitude: 46.1),
                     makeHike(slug: "none", latitude: nil),
                     makeHike(slug: "b", latitude: 46.2)]
        await service.fill(hikes: hikes, location: location, onEntry: nil)
        XCTAssertEqual(store.entry(locationID: location.id, slug: "a")?.driveSeconds, Int(60 * 46.1))
        XCTAssertEqual(store.entry(locationID: location.id, slug: "b")?.driveSeconds, Int(60 * 46.2))
        XCTAssertNil(store.entry(locationID: location.id, slug: "none"))
        XCTAssertEqual(estimator.requestedSlugsByCoordinate.count, 2)
    }

    func testSkipsAlreadyCachedEntries() async {
        store.set(TravelTimeEntry(driveSeconds: 999, fetchedAt: Date()),
                  locationID: location.id, slug: "a")
        await service.fill(hikes: [makeHike(slug: "a", latitude: 46.1)], location: location, onEntry: nil)
        XCTAssertEqual(estimator.requestedSlugsByCoordinate.count, 0)
        XCTAssertEqual(store.entry(locationID: location.id, slug: "a")?.driveSeconds, 999)
    }

    func testFailureLeavesEntryUncachedAndContinues() async {
        estimator.failFor = [46.1]
        let hikes = [makeHike(slug: "bad", latitude: 46.1), makeHike(slug: "good", latitude: 46.2)]
        await service.fill(hikes: hikes, location: location, onEntry: nil)
        XCTAssertNil(store.entry(locationID: location.id, slug: "bad"))
        XCTAssertNotNil(store.entry(locationID: location.id, slug: "good"))
        // Retried on a later fill:
        estimator.failFor = []
        await service.fill(hikes: hikes, location: location, onEntry: nil)
        XCTAssertNotNil(store.entry(locationID: location.id, slug: "bad"))
    }

    func testOnEntryCallbackFires() async {
        var received: [String] = []
        await service.fill(hikes: [makeHike(slug: "a", latitude: 46.1)], location: location) { slug, _ in
            received.append(slug)
        }
        XCTAssertEqual(received, ["a"])
    }
}
