import Foundation

public struct TravelTimeEntry: Codable, Equatable, Sendable {
    public let driveSeconds: Int
    /// When this estimate was computed. Unused today; enables future refresh/staleness logic.
    public let fetchedAt: Date

    public init(driveSeconds: Int, fetchedAt: Date) {
        self.driveSeconds = driveSeconds
        self.fetchedAt = fetchedAt
    }
}

/// Drive times cached per (location, hike) so switching back to a previously
/// used location never refetches. Persists on every mutation.
@MainActor
public final class TravelTimeStore {
    public let fileURL: URL
    private var entries: [String: [String: TravelTimeEntry]]  // locationID.uuidString → slug → entry

    public init(fileURL: URL) {
        self.fileURL = fileURL
        entries = (try? JSONDecoder.hike.decode(
            [String: [String: TravelTimeEntry]].self, from: Data(contentsOf: fileURL))) ?? [:]
    }

    /// App Group container when available, Documents otherwise (same fallback as HikeStore).
    public static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let container = fm.containerURL(forSecurityApplicationGroupIdentifier: HikeStore.appGroupID)
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return container.appendingPathComponent("traveltimes.json")
    }

    public func entry(locationID: UUID, slug: String) -> TravelTimeEntry? {
        entries[locationID.uuidString]?[slug]
    }

    public func set(_ entry: TravelTimeEntry, locationID: UUID, slug: String) {
        entries[locationID.uuidString, default: [:]][slug] = entry
        persist()
    }

    public func driveSeconds(for locationID: UUID) -> [String: Int] {
        (entries[locationID.uuidString] ?? [:]).mapValues(\.driveSeconds)
    }

    public func purgeLocation(id: UUID) {
        entries[id.uuidString] = nil
        persist()
    }

    public func purgeHike(slug: String) {
        for key in entries.keys { entries[key]?[slug] = nil }
        persist()
    }

    private func persist() {
        try? JSONEncoder.hike.encode(entries).write(to: fileURL, options: .atomic)
    }
}
