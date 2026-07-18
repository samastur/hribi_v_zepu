import Foundation
import SwiftSoup

public struct ParsedHike: Equatable {
    public let slug: String
    public let sourceURL: URL
    public let title: String
    public let metadata: [MetadataField]
    public let coordinate: Coordinate?
    public let sections: [HikeSection]
    public let imageURLs: [URL]
}

public enum HikeParserError: Error, Equatable {
    case invalidURL
    case titleNotFound
}

public struct HikeParser {
    public init() {}

    /// View-count style rows that are noise offline; coordinates get structured handling.
    private static let skippedMetadataLabels: Set<String> = [
        "Širina/Dolžina", "Ogledov", "Število slik", "Število komentarjev",
    ]

    public func parse(html: String, sourceURL: URL) throws -> ParsedHike {
        guard let slug = HikeURL.slug(from: sourceURL) else { throw HikeParserError.invalidURL }
        let doc = try SwiftSoup.parse(html)

        guard let h1 = try doc.select("h1").first(),
              case let title = try h1.text().trimmingCharacters(in: .whitespaces),
              !title.isEmpty
        else { throw HikeParserError.titleNotFound }

        return ParsedHike(
            slug: slug,
            sourceURL: sourceURL,
            title: title,
            metadata: try parseMetadata(doc),
            coordinate: try parseCoordinate(doc),
            sections: [],
            imageURLs: []
        )
    }

    private func parseMetadata(_ doc: Document) throws -> [MetadataField] {
        var fields: [MetadataField] = []
        for div in try doc.select("div.g2").array() {
            guard let bold = try div.select("b").first() else { continue }
            let label = try bold.text().trimmingCharacters(in: CharacterSet(charactersIn: ": \u{00a0}"))
            guard !label.isEmpty, !Self.skippedMetadataLabels.contains(label) else { continue }
            let fullText = try div.text()
            let value = fullText
                .replacingOccurrences(of: try bold.text(), with: "")
                .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{00a0}")))
            guard !value.isEmpty else { continue }
            fields.append(MetadataField(label: label, value: value))
        }
        return fields
    }

    private func parseCoordinate(_ doc: Document) throws -> Coordinate? {
        guard let span = try doc.select("span#kf0").first() else { return nil }
        return Self.coordinate(from: try span.text())
    }

    /// Parses "46,38240°N 13,76040°E" (decimal comma, optional nbsp/slash separators).
    static func coordinate(from text: String) -> Coordinate? {
        let cleaned = text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: ",", with: ".")
        guard let range = cleaned.range(of: #"([0-9.]+)°N\s*/?\s*([0-9.]+)°E"#, options: .regularExpression)
        else { return nil }
        let numbers = String(cleaned[range])
            .components(separatedBy: CharacterSet(charactersIn: "°NE/ "))
            .compactMap(Double.init)
        guard numbers.count >= 2 else { return nil }
        return Coordinate(latitude: numbers[0], longitude: numbers[1])
    }
}
