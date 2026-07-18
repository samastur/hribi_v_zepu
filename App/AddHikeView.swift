import SwiftUI
import HikeKit

struct AddHikeView: View {
    @StateObject private var viewModel: AddHikeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var didAdd = false
    @State private var downloadTask: Task<Void, Never>?

    init(store: HikeStore) {
        _viewModel = StateObject(wrappedValue: AddHikeViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hike link") {
                    TextField("https://www.hribi.net/izlet/…", text: $viewModel.urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Button("Download") {
                        downloadTask = Task { await viewModel.download() }
                    }
                    .disabled(viewModel.validatedURL == nil || viewModel.state.isDownloading)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    stateView
                }
            }
            .navigationTitle("Add hike")
            .toolbar {
                Button(didAdd ? "Done" : "Cancel") {
                    downloadTask?.cancel()
                    dismiss()
                }
            }
            .onAppear {
                viewModel.prefillFromClipboard(UIPasteboard.general.string)
            }
            .onChange(of: viewModel.state) { _, state in
                if case .success = state { didAdd = true }
            }
            .alert("Already saved", isPresented: Binding(
                get: { viewModel.duplicateSlug != nil },
                set: { if !$0 { viewModel.duplicateSlug = nil } })
            ) {
                Button("Refresh it") { downloadTask = Task { await viewModel.download(isRefresh: true) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This hike is already on your phone. Download it again to pick up new comments and photos?")
            }
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .downloading(.fetchingPage):
            HStack { ProgressView(); Text("Downloading page…") }
        case .downloading(.downloadingImage(let index, let total)):
            HStack { ProgressView(); Text("Photo \(index) of \(total)…") }
        case .success(let title):
            Label(title, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}
