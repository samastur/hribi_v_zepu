import XCTest
@testable import HikeKit

/// Hits the live hribi.net site (spec requirement). Fails without network.
/// Skipped unless RUN_LIVE_TESTS=1 so routine test runs never hammer hribi.net.
final class LiveDownloadTests: XCTestCase {
    func testDownloadsRealHikeEndToEnd() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1",
                          "live test disabled — set RUN_LIVE_TESTS=1 to run against hribi.net")
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveE2E-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = HikeStore(baseDirectory: base)

        let result = try await HikeDownloader().download(from: zadnjicaURL)
        try store.save(stagingDirectory: result.stagingDirectory, slug: result.hike.slug)

        let stored = try store.load(slug: "zadnjica_pogacnikov_dom_na_kriskih_podih")
        let hike = stored.hike
        XCTAssertEqual(hike.title, "Zadnjica - Pogačnikov dom na Kriških podih")
        XCTAssertEqual(hike.coordinate?.latitude ?? 0, 46.38240, accuracy: 0.001)
        XCTAssertEqual(hike.metadataValue("Zahtevnost"), "lahka označena pot")

        let sectionTitles = hike.sections.map(\.title)
        XCTAssertTrue(sectionTitles.contains("Dostop do izhodišča"))
        XCTAssertTrue(sectionTitles.contains("Opis poti"))
        XCTAssertTrue(sectionTitles.contains("Komentarji"))

        XCTAssertGreaterThanOrEqual(hike.images.count, 40)
        XCTAssertEqual(hike.images.count, hike.expectedImageCount, "all photos should download")
        for image in hike.images {
            let file = store.imageFileURL(slug: hike.slug, filename: image.filename)
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            XCTAssertGreaterThan(size, 1_000, "\(image.filename) should be a real photo")
        }
        XCTAssertGreaterThan(stored.sizeBytes, 1_000_000, "a full hike is several MB")
        XCTAssertEqual(store.totalSizeBytes(), stored.sizeBytes)
    }
}
