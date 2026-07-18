import XCTest
@testable import HikeKit

final class HikeStoreTests: XCTestCase {
    var base: URL!
    var store: HikeStore!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("HikeStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = HikeStore(baseDirectory: base)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    func makeHike(slug: String, dateAdded: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Hike {
        Hike(slug: slug,
             sourceURL: URL(string: "https://www.hribi.net/izlet/\(slug)/1/2/3")!,
             title: "Hike \(slug)", metadata: [], coordinate: nil,
             sections: [], images: [HikeImage(filename: "001.jpg", remoteURL: URL(string: "https://x.net/a.jpg")!)],
             expectedImageCount: 1, dateAdded: dateAdded)
    }

    /// Builds a staging dir shaped like HikeDownloader output: hike.json, page.html, images/001.jpg
    func makeStaging(for hike: Hike, imageBytes: Int = 1000) throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        let images = staging.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try JSONEncoder.hike.encode(hike).write(to: staging.appendingPathComponent("hike.json"))
        try Data("<html>page</html>".utf8).write(to: staging.appendingPathComponent("page.html"))
        try Data(repeating: 0xAB, count: imageBytes).write(to: images.appendingPathComponent("001.jpg"))
        return staging
    }

    func testSaveLoadRoundTrip() throws {
        let hike = makeHike(slug: "alpha")
        try store.save(stagingDirectory: try makeStaging(for: hike), slug: hike.slug)
        let stored = try store.load(slug: "alpha")
        XCTAssertEqual(stored.hike, hike)
        XCTAssertGreaterThan(stored.sizeBytes, 1000)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.imageFileURL(slug: "alpha", filename: "001.jpg").path))
    }

    func testListSortedByDateAddedDescending() throws {
        let older = makeHike(slug: "older", dateAdded: Date(timeIntervalSince1970: 1_000))
        let newer = makeHike(slug: "newer", dateAdded: Date(timeIntervalSince1970: 2_000))
        try store.save(stagingDirectory: try makeStaging(for: older), slug: older.slug)
        try store.save(stagingDirectory: try makeStaging(for: newer), slug: newer.slug)
        XCTAssertEqual(store.listHikes().map { $0.hike.slug }, ["newer", "older"])
    }

    func testContainsAndDelete() throws {
        let hike = makeHike(slug: "gone")
        try store.save(stagingDirectory: try makeStaging(for: hike), slug: hike.slug)
        XCTAssertTrue(store.contains(slug: "gone"))
        try store.delete(slug: "gone")
        XCTAssertFalse(store.contains(slug: "gone"))
        XCTAssertThrowsError(try store.load(slug: "gone"))
    }

    func testSaveReplacesExistingHike() throws {
        let v1 = makeHike(slug: "same")
        try store.save(stagingDirectory: try makeStaging(for: v1, imageBytes: 500), slug: v1.slug)
        let v2 = makeHike(slug: "same", dateAdded: Date(timeIntervalSince1970: 9_999))
        try store.save(stagingDirectory: try makeStaging(for: v2, imageBytes: 5000), slug: v2.slug)
        let stored = try store.load(slug: "same")
        XCTAssertEqual(stored.hike.dateAdded, Date(timeIntervalSince1970: 9_999))
        XCTAssertEqual(store.listHikes().count, 1)
        let imageURL = store.imageFileURL(slug: "same", filename: "001.jpg")
        let imageSize = (try? imageURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        XCTAssertEqual(imageSize, 5000, "old hike content must be fully replaced")
    }

    func testTotalSize() throws {
        XCTAssertEqual(store.totalSizeBytes(), 0)
        let hike = makeHike(slug: "sized")
        try store.save(stagingDirectory: try makeStaging(for: hike, imageBytes: 10_000), slug: hike.slug)
        XCTAssertGreaterThan(store.totalSizeBytes(), 10_000)
    }

    func testListSkipsCorruptEntries() throws {
        let hike = makeHike(slug: "good")
        try store.save(stagingDirectory: try makeStaging(for: hike), slug: hike.slug)
        let corrupt = base.appendingPathComponent("corrupt", isDirectory: true)
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: corrupt.appendingPathComponent("hike.json"))
        XCTAssertEqual(store.listHikes().map { $0.hike.slug }, ["good"])
    }

    func testSaveRejectsStagingWithoutManifest() throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.save(stagingDirectory: staging, slug: "broken")) {
            XCTAssertEqual($0 as? HikeStoreError, .missingManifest("broken"))
        }
        XCTAssertFalse(store.contains(slug: "broken"))
        try? FileManager.default.removeItem(at: staging)
    }
}
