import Foundation

public protocol DataFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionFetcher: DataFetching {
    public init() {}
    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HikeDownloaderError.httpStatus(http.statusCode)
        }
        return data
    }
}

public enum HikeDownloaderError: Error, Equatable {
    case invalidHikeURL
    case httpStatus(Int)
    case pageDecodingFailed
}

public enum DownloadProgress: Equatable, Sendable {
    case fetchingPage
    case downloadingImage(index: Int, total: Int)
}

public struct DownloadResult: Sendable {
    public let hike: Hike
    public let stagingDirectory: URL
}

public final class HikeDownloader: Sendable {
    private let fetcher: DataFetching
    private let parser: HikeParser

    public init(fetcher: DataFetching = URLSessionFetcher()) {
        self.fetcher = fetcher
        self.parser = HikeParser()
    }

    /// Downloads page + images into a fresh staging directory (caller installs it via HikeStore.save).
    /// Individual image failures are tolerated; the page itself must succeed.
    public func download(
        from url: URL,
        dateAdded: Date = Date(),
        progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) async throws -> DownloadResult {
        guard let validated = HikeURL.validate(url.absoluteString),
              let slug = HikeURL.slug(from: validated)
        else { throw HikeDownloaderError.invalidHikeURL }

        progress(.fetchingPage)
        let pageData = try await fetcher.data(from: validated)
        guard let html = String(data: pageData, encoding: .utf8) else {
            throw HikeDownloaderError.pageDecodingFailed
        }
        let parsed = try parser.parse(html: html, sourceURL: validated)

        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            let imagesDir = staging.appendingPathComponent("images", isDirectory: true)
            try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            try pageData.write(to: staging.appendingPathComponent("page.html"))

            var images: [HikeImage] = []
            let total = parsed.imageURLs.count
            for (index, remoteURL) in parsed.imageURLs.enumerated() {
                progress(.downloadingImage(index: index + 1, total: total))
                guard let data = try? await fetcher.data(from: remoteURL), !data.isEmpty else { continue }
                let filename = String(format: "%03d.jpg", index + 1)
                try data.write(to: imagesDir.appendingPathComponent(filename))
                images.append(HikeImage(filename: filename, remoteURL: remoteURL))
            }

            let hike = Hike(
                slug: slug, sourceURL: validated, title: parsed.title,
                metadata: parsed.metadata, coordinate: parsed.coordinate,
                sections: parsed.sections, images: images,
                expectedImageCount: total, dateAdded: dateAdded)
            try JSONEncoder.hike.encode(hike).write(to: staging.appendingPathComponent("hike.json"))
            return DownloadResult(hike: hike, stagingDirectory: staging)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }
}
