// HikeKit/Tests/HikeKitTests/HikeStatsTests.swift
import XCTest
@testable import HikeKit

final class HikeStatsTests: XCTestCase {
    func makeHike(metadata: [MetadataField]) -> Hike {
        Hike(slug: "s", sourceURL: URL(string: "https://www.hribi.net/izlet/s/1/2/3")!,
             title: "T", metadata: metadata, coordinate: nil, sections: [], images: [],
             expectedImageCount: 0, dateAdded: Date(timeIntervalSince1970: 0))
    }

    func testWalkingMinutesParsing() {
        XCTAssertEqual(Hike.walkingMinutes(from: "4 h"), 240)
        XCTAssertEqual(Hike.walkingMinutes(from: "3 h 30 min"), 210)
        XCTAssertEqual(Hike.walkingMinutes(from: "45 min"), 45)
        XCTAssertEqual(Hike.walkingMinutes(from: "4,5 h"), 270)
        XCTAssertEqual(Hike.walkingMinutes(from: "4.5 h"), 270)
        XCTAssertNil(Hike.walkingMinutes(from: nil))
        XCTAssertNil(Hike.walkingMinutes(from: ""))
        XCTAssertNil(Hike.walkingMinutes(from: "neznano"))
    }

    func testMetersParsing() {
        XCTAssertEqual(Hike.meters(from: "1410 m"), 1410)
        XCTAssertEqual(Hike.meters(from: "1.410 m"), 1410)
        XCTAssertEqual(Hike.meters(from: "80 m"), 80)
        XCTAssertNil(Hike.meters(from: nil))
        XCTAssertNil(Hike.meters(from: "veliko"))
    }

    func testDifficultyRankOrdering() {
        let ordered = [
            "lahka označena pot", "zahtevna označena pot", "zelo zahtevna označena pot",
            "lahko brezpotje", "zahtevno brezpotje", "zelo zahtevno brezpotje",
            "lahka plezalna pot", "zahtevna plezalna pot", "zelo zahtevna plezalna pot",
        ]
        let ranks = ordered.map { Hike.difficultyRank(from: $0) }
        XCTAssertEqual(ranks, [0, 1, 2, 3, 4, 5, 6, 7, 8].map { Optional($0) })
        XCTAssertNil(Hike.difficultyRank(from: "turno smučanje"))
        XCTAssertNil(Hike.difficultyRank(from: nil))
    }

    func testHikeAccessorsReadMetadata() {
        let hike = makeHike(metadata: [
            MetadataField(label: "Čas hoje", value: "3 h 30 min"),
            MetadataField(label: "Zahtevnost", value: "zahtevna označena pot"),
            MetadataField(label: "Višinska razlika", value: "1408 m"),
            MetadataField(label: "Višinska razlika po poti", value: "1410 m"),
        ])
        XCTAssertEqual(hike.walkingMinutes, 210)
        XCTAssertEqual(hike.difficultyText, "zahtevna označena pot")
        XCTAssertEqual(hike.difficultyRank, 1)
        XCTAssertEqual(hike.routeElevationMeters, 1410, "must read the 'po poti' field, not plain Višinska razlika")
    }

    func testMissingMetadataGivesNil() {
        let hike = makeHike(metadata: [])
        XCTAssertNil(hike.walkingMinutes)
        XCTAssertNil(hike.routeElevationMeters)
        XCTAssertNil(hike.difficultyText)
        XCTAssertNil(hike.difficultyRank)
    }
}
