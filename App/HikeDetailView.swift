import SwiftUI
import HikeKit

struct HikeDetailView: View {
    let store: HikeStore
    let onChange: () -> Void
    @State private var stored: StoredHike
    @State private var expandedSections: Set<String>
    @State private var fullscreenIndex: Int?
    @State private var confirmingDelete = false
    @StateObject private var refreshModel: AddHikeViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: HikeStore, initial: StoredHike, onChange: @escaping () -> Void) {
        self.store = store
        self.onChange = onChange
        _stored = State(initialValue: initial)
        _expandedSections = State(initialValue: ["Opis poti"])
        let model = AddHikeViewModel(store: store)
        model.urlText = initial.hike.sourceURL.absoluteString
        _refreshModel = StateObject(wrappedValue: model)
    }

    private var hike: Hike { stored.hike }

    private var pagerItems: [PagerItem] {
        hike.images.enumerated().map { index, image in
            PagerItem(
                id: index,
                fileURL: store.imageFileURL(slug: hike.slug, filename: image.filename),
                caption: image.caption
            )
        }
    }

    var body: some View {
        List {
            metadataSection
            if let coordinate = hike.coordinate {
                Section {
                    Link(destination: MapLinks.googleMaps(to: coordinate)) {
                        Label("Navigate to trailhead (Google Maps)", systemImage: "car")
                    }
                    Link(destination: MapLinks.appleMaps(to: coordinate)) {
                        Label("Navigate (Apple Maps)", systemImage: "map")
                    }
                }
            }
            ForEach(hike.sections, id: \.title) { section in
                Section {
                    DisclosureGroup(
                        section.title,
                        isExpanded: Binding(
                            get: { expandedSections.contains(section.title) },
                            set: { expanded in
                                if expanded { expandedSections.insert(section.title) }
                                else { expandedSections.remove(section.title) }
                            })
                    ) {
                        ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                        }
                    }
                }
            }
            photosSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(hike.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarMenu }
        .fullScreenCover(item: $fullscreenIndex) { index in
            PhotoPagerView(items: pagerItems, startIndex: index) {
                fullscreenIndex = nil
            }
        }
        .confirmationDialog("Delete \u{201C}\(hike.title)\u{201D}?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                try? store.delete(slug: hike.slug)
                onChange()
                dismiss()
            }
        }
        .onChange(of: refreshModel.state) { _, state in
            if case .success = state, let reloaded = try? store.load(slug: hike.slug) {
                stored = reloaded
                onChange()
            }
        }
    }

    private var metadataSection: some View {
        Section {
            ForEach(hike.metadata, id: \.label) { field in
                LabeledContent(field.label, value: field.value)
            }
            if hike.images.count < hike.expectedImageCount {
                Text("\(hike.images.count) of \(hike.expectedImageCount) photos downloaded — use Refresh to retry")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if refreshModel.state.isDownloading {
                HStack { ProgressView(); Text("Refreshing…") }
            }
        } footer: {
            Text(ByteCountFormatter.string(fromByteCount: stored.sizeBytes, countStyle: .file))
        }
    }

    private var photosSection: some View {
        Section("Slike (\(hike.images.count))") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                ForEach(pagerItems) { item in
                    LocalImage(fileURL: item.fileURL, contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 100, maxHeight: 100)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { fullscreenIndex = item.id }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var toolbarMenu: some View {
        Menu {
            Button {
                Task { await refreshModel.download(isRefresh: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(refreshModel.state.isDownloading)
            Link(destination: hike.sourceURL) {
                Label("Open original in Safari", systemImage: "safari")
            }
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
