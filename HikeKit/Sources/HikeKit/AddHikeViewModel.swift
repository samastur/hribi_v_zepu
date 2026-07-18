import Foundation
import Combine

@MainActor
public final class AddHikeViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case downloading(DownloadProgress)
        case success(String)
        case failure(String)

        public var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }
    }

    @Published public var urlText: String = ""
    @Published public private(set) var state: State = .idle
    @Published public var duplicateSlug: String?

    private let store: HikeStore
    private let downloader: HikeDownloader

    public init(store: HikeStore, downloader: HikeDownloader = HikeDownloader()) {
        self.store = store
        self.downloader = downloader
    }

    public var validatedURL: URL? { HikeURL.validate(urlText) }

    /// Fills the field from the clipboard, but only with a valid hike URL and only when empty.
    public func prefillFromClipboard(_ clipboard: String?) {
        guard urlText.isEmpty, let clipboard, HikeURL.validate(clipboard) != nil else { return }
        urlText = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func download(isRefresh: Bool = false) async {
        guard let url = validatedURL, let slug = HikeURL.slug(from: url) else {
            state = .failure("That is not a hribi.net hike link. Expected https://www.hribi.net/izlet/…")
            return
        }
        if !isRefresh, store.contains(slug: slug) {
            duplicateSlug = slug
            return
        }
        duplicateSlug = nil
        state = .downloading(.fetchingPage)
        do {
            let result = try await downloader.download(from: url) { [weak self] progress in
                Task { @MainActor in self?.state = .downloading(progress) }
            }
            try store.save(stagingDirectory: result.stagingDirectory, slug: result.hike.slug)
            state = .success(result.hike.title)
        } catch {
            state = .failure("Download failed (\(error.localizedDescription)). Check your connection and try again.")
        }
    }
}
