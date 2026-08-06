import SwiftUI
import MapKit
import HikeKit

struct AddLocationView: View {
    let locationStore: LocationStore
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable {
        case search = "Išči", current = "Tu sem", map = "Zemljevid"
    }

    @State private var mode: Mode = .search
    @State private var name = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var searchText = ""
    @State private var results: [MKMapItem] = []
    @State private var locating = false
    @State private var errorText: String?
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.12, longitude: 14.82),  // Slovenia
        span: MKCoordinateSpan(latitudeDelta: 2.4, longitudeDelta: 3.6)))
    private let locationProvider = CurrentLocationProvider()

    var body: some View {
        NavigationStack {
            Form {
                Section("Ime") {
                    TextField("npr. Dom", text: $name)
                }
                Section("Lokacija") {
                    Picker("Način", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .search: searchContent
                    case .current: currentContent
                    case .map: mapContent
                    }

                    if let coordinate {
                        Text(String(format: "Izbrano: %.5f, %.5f", coordinate.latitude, coordinate.longitude))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Nova lokacija")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Prekliči") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Shrani") { save() }
                        .disabled(coordinate == nil
                                  || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder private var searchContent: some View {
        TextField("Naslov ali kraj", text: $searchText)
            .autocorrectionDisabled()
            .onSubmit(runSearch)
        ForEach(results, id: \.self) { item in
            Button {
                coordinate = item.location.coordinate
                if name.trimmingCharacters(in: .whitespaces).isEmpty {
                    name = item.name ?? ""
                }
            } label: {
                VStack(alignment: .leading) {
                    Text(item.name ?? "—")
                    if let fullAddress = item.address?.fullAddress {
                        Text(fullAddress).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var currentContent: some View {
        Button {
            locating = true
            errorText = nil
            Task {
                defer { locating = false }
                do { coordinate = try await locationProvider.currentCoordinate() }
                catch { errorText = error.localizedDescription }
            }
        } label: {
            if locating { ProgressView() } else { Label("Uporabi trenutno lokacijo", systemImage: "location.fill") }
        }
        .disabled(locating)
    }

    @ViewBuilder private var mapContent: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let coordinate {
                    Marker(name.isEmpty ? "Izbrano" : name, coordinate: coordinate)
                }
            }
            .frame(height: 300)
            .onTapGesture { screenPoint in
                if let tapped = proxy.convert(screenPoint, from: .local) {
                    coordinate = tapped
                }
            }
        }
        Text("Tapnite zemljevid za izbiro točke.")
            .font(.footnote).foregroundStyle(.secondary)
    }

    private func runSearch() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        errorText = nil
        Task {
            do { results = try await MKLocalSearch(request: request).start().mapItems }
            catch { errorText = "Iskanje ni uspelo — preverite povezavo." }
        }
    }

    private func save() {
        guard let coordinate else { return }
        locationStore.add(SavedLocation(name: name.trimmingCharacters(in: .whitespaces),
                                        latitude: coordinate.latitude,
                                        longitude: coordinate.longitude))
        onSaved()
        dismiss()
    }
}
