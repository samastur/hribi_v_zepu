// HikeKit/Tests/HikeKitTests/HikeListModelTests.swift
import XCTest
@testable import HikeKit

final class HikeListModelTests: XCTestCase {
    func stored(slug: String, date: TimeInterval = 0, walk: String? = nil,
                difficulty: String? = nil, elevation: String? = nil) -> StoredHike {
        var metadata: [MetadataField] = []
        if let walk { metadata.append(MetadataField(label: "Čas hoje", value: walk)) }
        if let difficulty { metadata.append(MetadataField(label: "Zahtevnost", value: difficulty)) }
        if let elevation { metadata.append(MetadataField(label: "Višinska razlika po poti", value: elevation)) }
        let hike = Hike(slug: slug, sourceURL: URL(string: "https://www.hribi.net/izlet/\(slug)/1/2/3")!,
                        title: slug, metadata: metadata, coordinate: nil, sections: [], images: [],
                        expectedImageCount: 0, dateAdded: Date(timeIntervalSince1970: date))
        return StoredHike(hike: hike, directory: URL(fileURLWithPath: "/tmp/\(slug)"), sizeBytes: 0)
    }

    let noDrive: (String) -> Int? = { _ in nil }

    func testDefaultSortIsDateAddedDescending() {
        let hikes = [stored(slug: "old", date: 1_000), stored(slug: "new", date: 2_000)]
        let result = HikeListModel.arrange(hikes, sort: .dateAdded, ascending: false,
                                           filter: HikeFilter(), driveSeconds: noDrive)
        XCTAssertEqual(result.map(\.hike.slug), ["new", "old"])
    }

    func testSortByWalkingTimeMissingLast() {
        let hikes = [stored(slug: "long", walk: "6 h"),
                     stored(slug: "unknown"),
                     stored(slug: "short", walk: "1 h 30 min")]
        let asc = HikeListModel.arrange(hikes, sort: .walkingTime, ascending: true,
                                        filter: HikeFilter(), driveSeconds: noDrive)
        XCTAssertEqual(asc.map(\.hike.slug), ["short", "long", "unknown"])
        let desc = HikeListModel.arrange(hikes, sort: .walkingTime, ascending: false,
                                         filter: HikeFilter(), driveSeconds: noDrive)
        XCTAssertEqual(desc.map(\.hike.slug), ["long", "short", "unknown"],
                       "missing values stay last even when descending")
    }

    func testSortByDifficultyAndElevation() {
        let hikes = [stored(slug: "hard", difficulty: "zelo zahtevna označena pot", elevation: "1.500 m"),
                     stored(slug: "easy", difficulty: "lahka označena pot", elevation: "300 m")]
        XCTAssertEqual(HikeListModel.arrange(hikes, sort: .difficulty, ascending: true,
                                             filter: HikeFilter(), driveSeconds: noDrive).map(\.hike.slug),
                       ["easy", "hard"])
        XCTAssertEqual(HikeListModel.arrange(hikes, sort: .elevation, ascending: false,
                                             filter: HikeFilter(), driveSeconds: noDrive).map(\.hike.slug),
                       ["hard", "easy"])
    }

    func testSortByDriveTimeUsesLookup() {
        let hikes = [stored(slug: "far"), stored(slug: "near"), stored(slug: "nocoord")]
        let drive: (String) -> Int? = { ["far": 7200, "near": 1200][$0] }
        let result = HikeListModel.arrange(hikes, sort: .driveTime, ascending: true,
                                           filter: HikeFilter(), driveSeconds: drive)
        XCTAssertEqual(result.map(\.hike.slug), ["near", "far", "nocoord"])
    }

    func testRangeFiltersKeepHikesMissingTheField() {
        var filter = HikeFilter()
        filter.walkingRange = 120...300
        let hikes = [stored(slug: "in", walk: "3 h"),
                     stored(slug: "out", walk: "6 h"),
                     stored(slug: "unknown")]
        let result = HikeListModel.arrange(hikes, sort: .dateAdded, ascending: false,
                                           filter: filter, driveSeconds: noDrive)
        XCTAssertEqual(Set(result.map(\.hike.slug)), ["in", "unknown"])
    }

    func testElevationRangeFilter() {
        var filter = HikeFilter()
        filter.elevationRange = 500...1000
        let hikes = [stored(slug: "in", elevation: "800 m"), stored(slug: "out", elevation: "1.400 m")]
        let result = HikeListModel.arrange(hikes, sort: .dateAdded, ascending: false,
                                           filter: filter, driveSeconds: noDrive)
        XCTAssertEqual(result.map(\.hike.slug), ["in"])
    }

    func testDifficultyFilterKeepsMissing() {
        var filter = HikeFilter()
        filter.difficulties = ["lahka označena pot"]
        let hikes = [stored(slug: "easy", difficulty: "lahka označena pot"),
                     stored(slug: "hard", difficulty: "zahtevno brezpotje"),
                     stored(slug: "unknown")]
        let result = HikeListModel.arrange(hikes, sort: .dateAdded, ascending: false,
                                           filter: filter, driveSeconds: noDrive)
        XCTAssertEqual(Set(result.map(\.hike.slug)), ["easy", "unknown"])
    }

    func testIsActive() {
        var filter = HikeFilter()
        XCTAssertFalse(filter.isActive)
        filter.difficulties = ["lahka označena pot"]
        XCTAssertTrue(filter.isActive)
    }

    func testBoundsAndDifficultiesPresent() {
        let hikes = [stored(slug: "a", walk: "2 h", difficulty: "zahtevna označena pot", elevation: "1.400 m"),
                     stored(slug: "b", walk: "5 h 30 min", difficulty: "lahka označena pot", elevation: "600 m"),
                     stored(slug: "c")]
        XCTAssertEqual(HikeListModel.walkingBounds(hikes), 120...330)
        XCTAssertEqual(HikeListModel.elevationBounds(hikes), 600...1400)
        XCTAssertEqual(HikeListModel.difficultiesPresent(hikes),
                       ["lahka označena pot", "zahtevna označena pot"], "ordered easy→hard")
        XCTAssertNil(HikeListModel.walkingBounds([stored(slug: "c")]))
    }

    func testDriveTimeText() {
        XCTAssertEqual(HikeListModel.driveTimeText(seconds: 45 * 60), "45 min")
        XCTAssertEqual(HikeListModel.driveTimeText(seconds: 3900), "1 h 5 min")
        XCTAssertEqual(HikeListModel.driveTimeText(seconds: 7200), "2 h")
        XCTAssertEqual(HikeListModel.driveTimeText(seconds: 29), "0 min")
    }

    func testSortKeyLabels() {
        XCTAssertEqual(HikeSortKey.dateAdded.label, "Dodano")
        XCTAssertEqual(HikeSortKey.walkingTime.label, "Čas hoje")
        XCTAssertEqual(HikeSortKey.difficulty.label, "Zahtevnost")
        XCTAssertEqual(HikeSortKey.elevation.label, "Višinska razlika po poti")
        XCTAssertEqual(HikeSortKey.driveTime.label, "Čas vožnje")
    }
}
