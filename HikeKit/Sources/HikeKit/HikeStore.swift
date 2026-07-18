import Foundation

public struct StoredHike: Identifiable, Equatable {
    public var id: String { hike.slug }
    public let hike: Hike
    public let directory: URL
    public let sizeBytes: Int64

    public init(hike: Hike, directory: URL, sizeBytes: Int64) {
        self.hike = hike
        self.directory = directory
        self.sizeBytes = sizeBytes
    }
}

public enum HikeStoreError: Error, Equatable {
    case notFound(String)
    case missingManifest(String)
}

/// Folder-per-hike storage: <base>/<slug>/{hike.json, page.html, images/}
public final class HikeStore {
    public static let appGroupID = "group.com.markos.hribivzepu"

    public let baseDirectory: URL
    private let fm = FileManager.default

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        try? fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    /// App Group container when available (device/simulator with entitlement), Documents otherwise.
    public static func defaultDirectory() -> URL {
        let fm = FileManager.default
        let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return container.appendingPathComponent("Hikes", isDirectory: true)
    }

    public func directory(for slug: String) -> URL {
        baseDirectory.appendingPathComponent(slug, isDirectory: true)
    }

    public func imageFileURL(slug: String, filename: String) -> URL {
        directory(for: slug).appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(filename)
    }

    public func contains(slug: String) -> Bool {
        fm.fileExists(atPath: directory(for: slug).appendingPathComponent("hike.json").path)
    }

    public func load(slug: String) throws -> StoredHike {
        let dir = directory(for: slug)
        guard fm.fileExists(atPath: dir.path) else { throw HikeStoreError.notFound(slug) }
        let manifest = dir.appendingPathComponent("hike.json")
        guard let data = fm.contents(atPath: manifest.path) else {
            throw HikeStoreError.missingManifest(slug)
        }
        let hike = try JSONDecoder.hike.decode(Hike.self, from: data)
        return StoredHike(hike: hike, directory: dir, sizeBytes: Self.directorySize(dir))
    }

    public func listHikes() -> [StoredHike] {
        let subdirs = (try? fm.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil)) ?? []
        return subdirs
            .compactMap { try? load(slug: $0.lastPathComponent) }
            .sorted { $0.hike.dateAdded > $1.hike.dateAdded }
    }

    /// Atomically installs a fully-staged hike folder; replaces any existing version.
    public func save(stagingDirectory: URL, slug: String) throws {
        let dest = directory(for: slug)
        if fm.fileExists(atPath: dest.path) {
            _ = try fm.replaceItemAt(dest, withItemAt: stagingDirectory)
        } else {
            try fm.moveItem(at: stagingDirectory, to: dest)
        }
    }

    public func delete(slug: String) throws {
        let dir = directory(for: slug)
        guard fm.fileExists(atPath: dir.path) else { throw HikeStoreError.notFound(slug) }
        try fm.removeItem(at: dir)
    }

    public func totalSizeBytes() -> Int64 {
        listHikes().reduce(0) { $0 + $1.sizeBytes }
    }

    static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}
