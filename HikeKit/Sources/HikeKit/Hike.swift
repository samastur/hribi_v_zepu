import Foundation

public struct Coordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct MetadataField: Codable, Equatable, Sendable {
    public let label: String
    public let value: String
    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct HikeSection: Codable, Equatable, Sendable {
    public let title: String
    public let paragraphs: [String]
    public init(title: String, paragraphs: [String]) {
        self.title = title
        self.paragraphs = paragraphs
    }
}

public struct HikeImage: Codable, Equatable, Sendable {
    public let filename: String
    public let remoteURL: URL
    public init(filename: String, remoteURL: URL) {
        self.filename = filename
        self.remoteURL = remoteURL
    }
}

public struct Hike: Codable, Equatable, Identifiable, Sendable {
    public var id: String { slug }
    public let slug: String
    public let sourceURL: URL
    public let title: String
    public let metadata: [MetadataField]
    public let coordinate: Coordinate?
    public let sections: [HikeSection]
    public let images: [HikeImage]
    public let expectedImageCount: Int
    public let dateAdded: Date

    public init(slug: String, sourceURL: URL, title: String, metadata: [MetadataField],
                coordinate: Coordinate?, sections: [HikeSection], images: [HikeImage],
                expectedImageCount: Int, dateAdded: Date) {
        self.slug = slug
        self.sourceURL = sourceURL
        self.title = title
        self.metadata = metadata
        self.coordinate = coordinate
        self.sections = sections
        self.images = images
        self.expectedImageCount = expectedImageCount
        self.dateAdded = dateAdded
    }

    public func metadataValue(_ label: String) -> String? {
        metadata.first { $0.label == label }?.value
    }
}

public extension JSONEncoder {
    static var hike: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var hike: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
