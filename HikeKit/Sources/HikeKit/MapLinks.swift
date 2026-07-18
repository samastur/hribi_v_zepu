import Foundation

public enum MapLinks {
    /// Universal Google Maps directions URL — opens the Google Maps app when installed.
    public static func googleMaps(to coordinate: Coordinate) -> URL {
        URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordinate.latitude),\(coordinate.longitude)")!
    }

    public static func appleMaps(to coordinate: Coordinate) -> URL {
        URL(string: "https://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)")!
    }
}
