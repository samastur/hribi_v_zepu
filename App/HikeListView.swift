import SwiftUI
import HikeKit

struct HikeListView: View {
    let store: HikeStore
    let locationStore: LocationStore
    let travelTimeStore: TravelTimeStore
    @State private var hikes: [StoredHike] = []
    @State private var showingAdd = false
    @State private var pendingDelete: StoredHike?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("sortKey") private var sortKeyRaw = HikeSortKey.dateAdded.rawValue
    @AppStorage("sortAscending") private var sortAscending = false
    @State private var filter = HikeFilter()
    @State private var showingFilters = false
    @State private var driveTimes: [String: Int] = [:]
    @State private var activeLocationName: String?
    @State private var showingLocations = false
    @State private var fillTask: Task<Void, Never>?

    private var sortKey: HikeSortKey { HikeSortKey(rawValue: sortKeyRaw) ?? .dateAdded }

    private var displayedHikes: [StoredHike] {
        HikeListModel.arrange(hikes, sort: sortKey, ascending: sortAscending,
                              filter: filter, driveSeconds: { driveTimes[$0] })
    }

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
                ToolbarItem(placement: .topBarLeading) {
                    locationMenu
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    sortMenu
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: filter.isActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterSheetView(walkingBounds: HikeListModel.walkingBounds(hikes),
                                elevationBounds: HikeListModel.elevationBounds(hikes),
                                difficulties: HikeListModel.difficultiesPresent(hikes),
                                filter: $filter)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingAdd, onDismiss: reload) {
                AddHikeView(store: store)
            }
            .sheet(isPresented: $showingLocations, onDismiss: refreshTravelTimes) {
                LocationsView(locationStore: locationStore,
                              travelTimeStore: travelTimeStore,
                              onChange: refreshTravelTimes)
            }
            .confirmationDialog(
                "Delete \u{201C}\(pendingDelete?.hike.title ?? "")\u{201D}?",
                isPresented: Binding(get: { pendingDelete != nil },
                                     set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let target = pendingDelete {
                        try? store.delete(slug: target.hike.slug)
                        travelTimeStore.purgeHike(slug: target.hike.slug)
                    }
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
            ForEach(displayedHikes) { stored in
                NavigationLink {
                    HikeDetailView(store: store, initial: stored, onChange: reload)
                } label: {
                    HikeRow(stored: stored,
                            driveText: driveTimes[stored.hike.slug]
                                .map { HikeListModel.driveTimeText(seconds: $0) })
                }
            }
            .onDelete { indexSet in
                pendingDelete = indexSet.first.map { displayedHikes[$0] }
            }
            Section {
                Text("Total: \(ByteCountFormatter.string(fromByteCount: store.totalSizeBytes(), countStyle: .file))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(HikeSortKey.allCases, id: \.self) { key in
                Button {
                    if sortKey == key {
                        sortAscending.toggle()
                    } else {
                        sortKeyRaw = key.rawValue
                        sortAscending = key != .dateAdded  // dates default newest-first
                    }
                } label: {
                    if sortKey == key {
                        Label(key.label, systemImage: sortAscending ? "chevron.up" : "chevron.down")
                    } else {
                        Text(key.label)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    private var locationMenu: some View {
        Menu {
            ForEach(locationStore.locations) { location in
                Button {
                    locationStore.setActive(id: location.id)
                    refreshTravelTimes()
                } label: {
                    if location.name == activeLocationName {
                        Label(location.name, systemImage: "checkmark")
                    } else {
                        Text(location.name)
                    }
                }
            }
            Divider()
            Button("Uredi lokacije…") { showingLocations = true }
        } label: {
            Label(activeLocationName ?? "Lokacije", systemImage: "house")
        }
    }

    private func reload() {
        hikes = store.listHikes()
        refreshTravelTimes()
    }

    /// Loads cached times for the active location and fetches any missing ones.
    /// Cancels an in-flight fill first so switching locations mid-fill is safe.
    private func refreshTravelTimes() {
        fillTask?.cancel()
        guard let active = locationStore.activeLocation else {
            activeLocationName = nil
            driveTimes = [:]
            return
        }
        activeLocationName = active.name
        driveTimes = travelTimeStore.driveSeconds(for: active.id)
        let pending = hikes.map(\.hike)
        fillTask = Task {
            let service = TravelTimeService(estimator: MapKitRouteEstimator(), store: travelTimeStore)
            await service.fill(hikes: pending, location: active) { slug, entry in
                driveTimes[slug] = entry.driveSeconds
            }
        }
    }
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
