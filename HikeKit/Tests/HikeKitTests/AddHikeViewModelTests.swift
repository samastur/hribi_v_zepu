import XCTest
@testable import HikeKit

@MainActor
final class AddHikeViewModelTests: XCTestCase {
    var base: URL!
    var store: HikeStore!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AddVMTests-\(UUID().uuidString)", isDirectory: true)
        store = HikeStore(baseDirectory: base)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    func makeVM() throws -> AddHikeViewModel {
        let stub = StubFetcher()
        let html = try fixture("komarna_vas")
        stub.responses[komarnaURL] = Data(html.utf8)
        for url in try HikeParser().parse(html: html, sourceURL: komarnaURL).imageURLs {
            stub.responses[url] = Data("jpegbytes".utf8)
        }
        return AddHikeViewModel(store: store, downloader: HikeDownloader(fetcher: stub))
    }

    func testSuccessfulDownloadSavesToStore() async throws {
        let vm = try makeVM()
        vm.urlText = komarnaURL.absoluteString
        await vm.download()
        XCTAssertEqual(vm.state, .success("Komarna vas - Gače"))
        XCTAssertTrue(store.contains(slug: "komarna_vas_gace_"))
    }

    func testInvalidURLFails() async throws {
        let vm = try makeVM()
        vm.urlText = "https://example.com/whatever"
        await vm.download()
        guard case .failure = vm.state else { return XCTFail("expected failure, got \(vm.state)") }
        XCTAssertEqual(store.listHikes().count, 0)
    }

    func testDuplicateDetectedAndRefreshOverwrites() async throws {
        let vm = try makeVM()
        vm.urlText = komarnaURL.absoluteString
        await vm.download()
        XCTAssertEqual(vm.state, .success("Komarna vas - Gače"))

        let vm2 = try makeVM()
        vm2.urlText = komarnaURL.absoluteString
        await vm2.download()
        XCTAssertEqual(vm2.duplicateSlug, "komarna_vas_gace_")
        guard case .idle = vm2.state else { return XCTFail("no download before user confirms") }

        await vm2.download(isRefresh: true)
        XCTAssertEqual(vm2.state, .success("Komarna vas - Gače"))
        XCTAssertEqual(store.listHikes().count, 1)
    }

    func testNetworkFailureLeavesNothingSaved() async throws {
        let vm = AddHikeViewModel(store: store, downloader: HikeDownloader(fetcher: StubFetcher()))
        vm.urlText = komarnaURL.absoluteString
        await vm.download()
        guard case .failure(let message) = vm.state else { return XCTFail("expected failure") }
        XCTAssertTrue(message.contains("try again"), "message should suggest retrying: \(message)")
        XCTAssertEqual(store.listHikes().count, 0)
    }

    func testClipboardPrefillOnlyForHikeURLs() throws {
        let vm = try makeVM()
        vm.prefillFromClipboard("not a link")
        XCTAssertEqual(vm.urlText, "")
        vm.prefillFromClipboard(komarnaURL.absoluteString)
        XCTAssertEqual(vm.urlText, komarnaURL.absoluteString)
        vm.prefillFromClipboard("https://www.hribi.net/izlet/other/1/2/3")
        XCTAssertEqual(vm.urlText, komarnaURL.absoluteString, "must not overwrite user input")
    }
}
