import SwiftUI
import HikeKit

struct HikeListView: View {
    let store: HikeStore
    @State private var hikes: [StoredHike] = []
    @State private var showingAdd = false
    @State private var pendingDelete: StoredHike?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if hikes.isEmpty {
                    ContentUnavailableView(
                        "No hikes yet",
                        systemImage: "mountain.2",
                        description: Text("Tap + and paste a hribi.net hike link, or share one from Safari."))
                } else {
                    hikeList
                }
            }
            .navigationTitle("Hribi v žepu")
            .toolbar {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showingAdd, onDismiss: reload) {
                AddHikeView(store: store)
            }
            .confirmationDialog(
                "Delete \u{201C}\(pendingDelete?.hike.title ?? "")\u{201D}?",
                isPresented: Binding(get: { pendingDelete != nil },
                                     set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let target = pendingDelete { try? store.delete(slug: target.hike.slug) }
                    pendingDelete = nil
                    reload()
                }
            }
            .onAppear(perform: reload)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reload() } // pick up hikes saved via the share extension
            }
        }
    }

    private var hikeList: some View {
        List {
            ForEach(hikes) { stored in
                NavigationLink {
                    HikeDetailView(store: store, initial: stored, onChange: reload)
                } label: {
                    HikeRow(stored: stored, driveText: nil)
                }
            }
            .onDelete { indexSet in
                pendingDelete = indexSet.first.map { hikes[$0] }
            }
            Section {
                Text("Total: \(ByteCountFormatter.string(fromByteCount: store.totalSizeBytes(), countStyle: .file))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reload() { hikes = store.listHikes() }
}

struct HikeRow: View {
    let stored: StoredHike
    let driveText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stored.hike.title).font(.headline)
            if let stats = statLine {
                stats.font(.subheadline)
            }
            Text(ByteCountFormatter.string(fromByteCount: stored.sizeBytes, countStyle: .file))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    /// One Text so the stats wrap as a single line of colored segments.
    private var statLine: Text? {
        let hike = stored.hike
        var parts: [Text] = []
        if let walk = hike.metadataValue("Čas hoje") {
            parts.append(Text(walk).foregroundStyle(Color.statWalking))
        }
        if let difficulty = hike.difficultyText {
            parts.append(Text(difficulty).foregroundStyle(Color.statDifficulty))
        }
        if let elevation = hike.metadataValue("Višinska razlika po poti") {
            parts.append(Text(elevation).foregroundStyle(Color.statElevation))
        }
        if let driveText {
            parts.append(Text("\(Image(systemName: "car.fill")) \(driveText)")
                .foregroundStyle(Color.statDrive))
        }
        guard let first = parts.first else { return nil }
        let separator = Text(" · ").foregroundStyle(.secondary)
        return parts.dropFirst().reduce(first) { accumulated, part in
            Text("\(accumulated)\(separator)\(part)")
        }
    }
}
