import Foundation

public extension Hike {
    /// "Čas hoje" as total minutes: "4 h" → 240, "3 h 30 min" → 210, "45 min" → 45, "4,5 h" → 270.
    var walkingMinutes: Int? { Self.walkingMinutes(from: metadataValue("Čas hoje")) }

    /// "Višinska razlika po poti" in meters, tolerant of thousands separators ("1.410 m").
    var routeElevationMeters: Int? { Self.meters(from: metadataValue("Višinska razlika po poti")) }

    /// Raw "Zahtevnost" value, e.g. "lahka označena pot".
    var difficultyText: String? { metadataValue("Zahtevnost") }

    /// Fixed easy→hard order: severity within path type, types ordered
    /// označena pot < brezpotje < plezalna pot. Unrecognized values → nil.
    var difficultyRank: Int? { Self.difficultyRank(from: difficultyText) }

    static func walkingMinutes(from text: String?) -> Int? {
        guard let raw = text?.lowercased().replacingOccurrences(of: ",", with: ".") else { return nil }
        var total = 0.0
        var matched = false

        let hoursPattern = try! NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)\\s*h\\b", options: [])
        let hoursRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        if let match = hoursPattern.firstMatch(in: raw, options: [], range: hoursRange),
           let range = Range(match.range(at: 1), in: raw),
           let hours = Double(String(raw[range])) {
            total += hours * 60
            matched = true
        }

        let minutesPattern = try! NSRegularExpression(pattern: "(\\d+)\\s*min\\b", options: [])
        let minutesRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        if let match = minutesPattern.firstMatch(in: raw, options: [], range: minutesRange),
           let range = Range(match.range(at: 1), in: raw),
           let minutes = Double(String(raw[range])) {
            total += minutes
            matched = true
        }

        return matched ? Int(total.rounded()) : nil
    }

    static func meters(from text: String?) -> Int? {
        guard let raw = text?.replacingOccurrences(of: ".", with: "") else { return nil }
        let pattern = try! NSRegularExpression(pattern: "(\\d+)\\s*m\\b", options: [])
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = pattern.firstMatch(in: raw, options: [], range: range),
              let matchRange = Range(match.range(at: 1), in: raw)
        else { return nil }
        return Int(String(raw[matchRange]))
    }

    static func difficultyRank(from text: String?) -> Int? {
        guard let text = text?.lowercased() else { return nil }
        let typeRanks = ["označena pot": 0, "brezpotje": 1, "plezalna pot": 2]
        // Order matters: "zelo zahtevn" must be tested before "zahtevn".
        let severityRanks: [(prefix: String, rank: Int)] =
            [("zelo zahtevn", 2), ("zahtevn", 1), ("lahk", 0)]
        guard let type = typeRanks.first(where: { text.contains($0.key) })?.value,
              let severity = severityRanks.first(where: { text.hasPrefix($0.prefix) })?.rank
        else { return nil }
        return type * 3 + severity
    }
}
