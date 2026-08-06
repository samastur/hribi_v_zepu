import SwiftUI
import HikeKit

@main
struct HribiVZepuApp: App {
    var body: some Scene {
        WindowGroup {
            HikeListView(store: HikeStore(baseDirectory: HikeStore.defaultDirectory()),
                         locationStore: LocationStore(fileURL: LocationStore.defaultFileURL()),
                         travelTimeStore: TravelTimeStore(fileURL: TravelTimeStore.defaultFileURL()))
        }
    }
}
