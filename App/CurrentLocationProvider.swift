import CoreLocation

/// One-shot async wrapper around CLLocationManager: requests when-in-use
/// authorization if needed, then delivers a single coordinate.
final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate {
    enum LocationError: LocalizedError {
        case denied
        var errorDescription: String? {
            "Dostop do lokacije je zavrnjen — omogočite ga v Nastavitvah, ali dodajte lokacijo prek iskanja oz. zemljevida."
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: resume(.failure(LocationError.denied))
            default: manager.requestLocation()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: resume(.failure(LocationError.denied))
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.first?.coordinate else { return }
        resume(.success(coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resume(.failure(error))
    }

    private func resume(_ result: Result<CLLocationCoordinate2D, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
