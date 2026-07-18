import Foundation
import SwiftSoup

public struct ParsedHike: Equatable, Sendable {
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

public struct HikeParser: Sendable {
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
            sections: try parseSections(doc),
            imageURLs: try parseImageURLs(doc)
        )
    }

    /// Bold-labelled blocks that are site chrome, not hike content.
    private static let skippedSectionPrefixes = ["Za objavo komentarja", "Diskusija o izletu"]

    private func parseSections(_ doc: Document) throws -> [HikeSection] {
        var sections: [HikeSection] = []
        for div in try doc.select("div[style*=padding-top:10px]").array() {
            guard let first = div.children().first(), first.tagName() == "b" else { continue }
            let title = try first.text().trimmingCharacters(in: CharacterSet(charactersIn: ": \u{00a0}"))
            guard !title.isEmpty,
                  !Self.skippedSectionPrefixes.contains(where: { title.hasPrefix($0) })
            else { continue }
            try first.remove()
            let paragraphs = try Self.paragraphs(fromInnerHTML: div.html())
            guard !paragraphs.isEmpty else { continue }
            sections.append(HikeSection(title: title, paragraphs: paragraphs))
        }
        sections.append(contentsOf: try parseComments(doc))
        return sections
    }

    /// Splits an HTML fragment into plain-text paragraphs at <br> boundaries.
    static func paragraphs(fromInnerHTML html: String) throws -> [String] {
        let marked = html.replacingOccurrences(
            of: #"<br\s*/?>"#, with: "\u{2029}", options: [.regularExpression, .caseInsensitive])
        let text = try SwiftSoup.parse(marked).text()
        return text
            .split(separator: "\u{2029}")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{00a0}"))) }
            .filter { !$0.isEmpty }
    }

    private func parseComments(_ doc: Document) throws -> [HikeSection] {
        var paragraphs: [String] = []
        for block in try doc.select("div.vrk0, div.vrk1").array() {
            var author = "", date = "", text = ""
            if let a = try block.select("a.ime").first() { author = try a.text() }
            if let d = try block.select("span.komDatum").first() { date = try d.text() }
            if let t = try block.select("td.komS").first() { text = try t.text() }
            guard !text.isEmpty else { continue }
            paragraphs.append("\(author) (\(date)): \(text)")
        }
        return paragraphs.isEmpty ? [] : [HikeSection(title: "Komentarji", paragraphs: paragraphs)]
    }

    private func parseImageURLs(_ doc: Document) throws -> [URL] {
        var urls: [URL] = []
        for img in try doc.select("img.slikagm").array() {
            var src = try img.attr("src")
            if src.hasPrefix("//") { src = "https:" + src }
            src = src
                .replacingOccurrences(of: ".th.jpg", with: ".jpg")
                .replacingOccurrences(of: " ", with: "%20")
            if let url = URL(string: src) { urls.append(url) }
        }
        return urls
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
