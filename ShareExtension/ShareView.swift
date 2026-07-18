import SwiftUI
import UniformTypeIdentifiers
import HikeKit

struct ShareView: View {
    let extensionContext: NSExtensionContext?
    let onFinish: () -> Void
    @StateObject private var viewModel = AddHikeViewModel(
        store: HikeStore(baseDirectory: HikeStore.defaultDirectory()))
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                switch viewModel.state {
                case .idle:
                    HStack { ProgressView(); Text("Reading link…") }
                case .downloading(.fetchingPage):
                    HStack { ProgressView(); Text("Downloading page…") }
                case .downloading(.downloadingImage(let index, let total)):
                    HStack { ProgressView(); Text("Photo \(index) of \(total)…") }
                case .success(let title):
                    Label("Saved: \(title)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure(let message):
                    Text(message).foregroundStyle(.red)
                }
                if viewModel.duplicateSlug != nil {
                    Button("Already saved — refresh it") {
                        Task { await viewModel.download(isRefresh: true) }
                    }
                }
            }
            .navigationTitle("Hribi v žepu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button(viewModel.state.isDownloading ? "Cancel" : "Done") {
                    downloadTask?.cancel()
                    onFinish()
                }
            }
            .onAppear {
                downloadTask = Task { await run() }
            }
        }
    }

    private func run() async {
        guard let url = await sharedURL() else {
            viewModel.urlText = "" // triggers the not-a-hike-link failure below
            await viewModel.download()
            return
        }
        viewModel.urlText = url.absoluteString
        await viewModel.download()
    }

    private func sharedURL() async -> URL? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap(\.attachments)
            .flatMap { $0 } ?? []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
            if let url = item as? URL { return url }
        }
        return nil
    }
}
