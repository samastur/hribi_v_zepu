import SwiftUI
import HikeKit

struct LocationsView: View {
    let locationStore: LocationStore
    let travelTimeStore: TravelTimeStore
    var onChange: () -> Void
    @State private var locations: [SavedLocation] = []
    @State private var activeID: UUID?
    @State private var showingAdd = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if locations.isEmpty {
                    ContentUnavailableView(
                        "Ni lokacij",
                        systemImage: "house",
                        description: Text("Dodajte izhodiščno lokacijo (npr. dom) za izračun časa vožnje do izletov."))
                } else {
                    List {
                        ForEach(locations) { location in
                            Button {
                                locationStore.setActive(id: location.id)
                                refresh()
                                onChange()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(location.name).foregroundStyle(.primary)
                                        Text(String(format: "%.5f, %.5f", location.latitude, location.longitude))
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if location.id == activeID {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let location = locations[index]
                                locationStore.delete(id: location.id)
                                travelTimeStore.purgeLocation(id: location.id)
                            }
                            refresh()
                            onChange()
                        }
                    }
                }
            }
            .navigationTitle("Lokacije")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Končano") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddLocationView(locationStore: locationStore) {
                    refresh()
                    onChange()
                }
            }
            .onAppear(perform: refresh)
        }
    }

    private func refresh() {
        locations = locationStore.locations
        activeID = locationStore.activeLocation?.id
    }
}
