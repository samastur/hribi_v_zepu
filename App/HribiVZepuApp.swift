import SwiftUI
import HikeKit

@main
struct HribiVZepuApp: App {
    // Stored once for the app's lifetime: re-creating these on each body
    // re-evaluation would spawn fresh store instances while an in-flight fill
    // task still holds the previous one, so its later file write would clobber
    // whatever the new instance had already saved (last-writer-wins).
    private let store = HikeStore(baseDirectory: HikeStore.defaultDirectory())
    private let locationStore = LocationStore(fileURL: LocationStore.defaultFileURL())
    private let travelTimeStore = TravelTimeStore(fileURL: TravelTimeStore.defaultFileURL())

    var body: some Scene {
        WindowGroup {
            HikeListView(store: store, locationStore: locationStore, travelTimeStore: travelTimeStore)
        }
    }
}
