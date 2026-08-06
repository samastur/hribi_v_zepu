import Foundation
import MapKit

public protocol RouteEstimator: Sendable {
    /// Estimated car travel time in seconds between two coordinates.
    func driveTime(from: Coordinate, to: Coordinate) async throws -> TimeInterval
}

/// Fills the TravelTimeStore for one location: skips cached slugs and hikes
/// without a coordinate, spaces requests to stay friendly with MapKit
/// throttling, persists each result immediately, and stops when cancelled.
/// Failures are skipped and retried on the next fill call.
@MainActor
public final class TravelTimeService {
    private let estimator: RouteEstimator
    private let store: TravelTimeStore
    private let spacing: Duration

    public init(estimator: RouteEstimator, store: TravelTimeStore, spacing: Duration = .seconds(1)) {
        self.estimator = estimator
        self.store = store
        self.spacing = spacing
    }

    public func fill(hikes: [Hike], location: SavedLocation,
                     onEntry: ((String, TravelTimeEntry) -> Void)? = nil) async {
        for hike in hikes {
            guard !Task.isCancelled else { return }
            guard let destination = hike.coordinate,
                  store.entry(locationID: location.id, slug: hike.slug) == nil
            else { continue }
            if let seconds = try? await estimator.driveTime(from: location.coordinate, to: destination) {
                // MKDirections doesn't observe Swift cancellation, so re-check here: a
                // location/hike deleted while this await was in flight must not be
                // re-persisted after its purge, which would orphan a bucket in the store.
                guard !Task.isCancelled else { return }
                let entry = TravelTimeEntry(driveSeconds: Int(seconds), fetchedAt: Date())
                store.set(entry, locationID: location.id, slug: hike.slug)
                onEntry?(hike.slug, entry)
            }
            try? await Task.sleep(for: spacing)
        }
    }
}

public struct MapKitRouteEstimator: RouteEstimator {
    public struct NoRouteFound: Error {}

    public init() {}

    public func driveTime(from: Coordinate, to: Coordinate) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = Self.mapItem(for: from)
        request.destination = Self.mapItem(for: to)
        request.transportType = .automobile
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw NoRouteFound() }
        return route.expectedTravelTime
    }

    /// MKMapItem(location:address:) needs iOS 26 / macOS 26; the package still
    /// targets macOS 14 so `swift test` runs there, hence the MKPlacemark path.
    private static func mapItem(for coordinate: Coordinate) -> MKMapItem {
        #if os(iOS)
        return MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                         address: nil)
        #else
        return MKMapItem(placemark: MKPlacemark(coordinate:
            CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)))
        #endif
    }
}
