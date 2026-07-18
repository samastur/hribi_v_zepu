import XCTest
@testable import HikeKit

/// Serves canned responses; records requested URLs. Thread-safe enough for serial test use.
final class StubFetcher: DataFetching, @unchecked Sendable {
    var responses: [URL: Data] = [:]
    var failing: Set<URL> = []
    private(set) var requested: [URL] = []

    func data(from url: URL) async throws -> Data {
        requested.append(url)
        if failing.contains(url) { throw HikeDownloaderError.httpStatus(404) }
        guard let data = responses[url] else { throw HikeDownloaderError.httpStatus(404) }
        return data
    }
}

final class HikeDownloaderTests: XCTestCase {
    func makeStub() throws -> (StubFetcher, [URL]) {
        let stub = StubFetcher()
        let html = try fixture("komarna_vas") // smallest fixture, 28 images
        stub.responses[komarnaURL] = Data(html.utf8)
        let imageURLs = try HikeParser().parse(html: html, sourceURL: komarnaURL).imageURLs
        for url in imageURLs { stub.responses[url] = Data("jpegbytes".utf8) }
        return (stub, imageURLs)
    }

    func testDownloadsPageAndAllImagesIntoStaging() async throws {
        let (stub, imageURLs) = try makeStub()
        let result = try await HikeDownloader(fetcher: stub)
            .download(from: komarnaURL, dateAdded: Date(timeIntervalSince1970: 42))

        XCTAssertEqual(result.hike.title, "Komarna vas - Gače")
        XCTAssertEqual(result.hike.images.count, imageURLs.count)
        XCTAssertEqual(result.hike.expectedImageCount, imageURLs.count)
        XCTAssertEqual(result.hike.images.first?.filename, "001.jpg")
        XCTAssertEqual(result.hike.dateAdded, Date(timeIntervalSince1970: 42))

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: result.stagingDirectory.appendingPathComponent("hike.json").path))
        XCTAssertTrue(fm.fileExists(atPath: result.stagingDirectory.appendingPathComponent("page.html").path))
        for image in result.hike.images {
            XCTAssertTrue(fm.fileExists(atPath: result.stagingDirectory
                .appendingPathComponent("images").appendingPathComponent(image.filename).path))
        }
        try? fm.removeItem(at: result.stagingDirectory)
    }

    func testReportsProgress() async throws {
        let (stub, imageURLs) = try makeStub()
        let progress = ProgressCollector()
        let result = try await HikeDownloader(fetcher: stub).download(from: komarnaURL) { p in
            progress.append(p)
        }
        XCTAssertEqual(progress.events.first, .fetchingPage)
        XCTAssertEqual(progress.events.last, .downloadingImage(index: imageURLs.count, total: imageURLs.count))
        try? FileManager.default.removeItem(at: result.stagingDirectory)
    }

    func testToleratesFailedImages() async throws {
        let (stub, imageURLs) = try makeStub()
        stub.failing = [imageURLs[0], imageURLs[1]]
        let result = try await HikeDownloader(fetcher: stub).download(from: komarnaURL)
        XCTAssertEqual(result.hike.images.count, imageURLs.count - 2)
        XCTAssertEqual(result.hike.expectedImageCount, imageURLs.count)
        try? FileManager.default.removeItem(at: result.stagingDirectory)
    }

    func testPageFailureThrows() async {
        let stub = StubFetcher() // no responses at all
        do {
            _ = try await HikeDownloader(fetcher: stub).download(from: komarnaURL)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? HikeDownloaderError, .httpStatus(404))
        }
    }

    func testRejectsNonHikeURL() async {
        do {
            _ = try await HikeDownloader(fetcher: StubFetcher())
                .download(from: URL(string: "https://example.com/nope")!)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? HikeDownloaderError, .invalidHikeURL)
        }
    }
}

final class ProgressCollector: @unchecked Sendable {
    private(set) var events: [DownloadProgress] = []
    private let lock = NSLock()
    func append(_ p: DownloadProgress) {
        lock.lock(); events.append(p); lock.unlock()
    }
}
