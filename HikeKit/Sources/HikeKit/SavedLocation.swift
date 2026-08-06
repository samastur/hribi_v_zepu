import Foundation

public struct SavedLocation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let latitude: Double
    public let longitude: Double

    public init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

/// Saved start locations plus the active selection, persisted in a single JSON file.
public final class LocationStore {
    private struct FileContents: Codable {
        var locations: [SavedLocation] = []
        var activeLocationID: UUID?
    }

    public let fileURL: URL
    private var contents: FileContents

    public init(fileURL: URL) {
        self.fileURL = fileURL
        contents = (try? JSONDecoder.hike.decode(FileContents.self, from: Data(contentsOf: fileURL)))
            ?? FileContents()
    }

    /// App Group container when available, Documents otherwise (same fallback as HikeStore).
    public static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let container = fm.containerURL(forSecurityApplicationGroupIdentifier: HikeStore.appGroupID)
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return container.appendingPathComponent("locations.json")
    }

    public var locations: [SavedLocation] { contents.locations }

    public var activeLocation: SavedLocation? {
        contents.locations.first { $0.id == contents.activeLocationID }
    }

    /// The first location ever added becomes active automatically.
    public func add(_ location: SavedLocation) {
        contents.locations.append(location)
        if contents.activeLocationID == nil { contents.activeLocationID = location.id }
        persist()
    }

    public func delete(id: UUID) {
        contents.locations.removeAll { $0.id == id }
        if contents.activeLocationID == id { contents.activeLocationID = nil }
        persist()
    }

    public func setActive(id: UUID) {
        guard contents.locations.contains(where: { $0.id == id }) else { return }
        contents.activeLocationID = id
        persist()
    }

    private func persist() {
        try? JSONEncoder.hike.encode(contents).write(to: fileURL, options: .atomic)
    }
}
