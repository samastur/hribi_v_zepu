import Foundation

public enum HikeSortKey: String, CaseIterable, Sendable {
    case dateAdded, walkingTime, difficulty, elevation, driveTime

    public var label: String {
        switch self {
        case .dateAdded: "Dodano"
        case .walkingTime: "Čas hoje"
        case .difficulty: "Zahtevnost"
        case .elevation: "Višinska razlika po poti"
        case .driveTime: "Čas vožnje"
        }
    }
}

/// nil field = that filter is inactive.
public struct HikeFilter: Equatable, Sendable {
    public var walkingRange: ClosedRange<Int>?
    public var elevationRange: ClosedRange<Int>?
    public var difficulties: Set<String>?

    public init() {}

    public var isActive: Bool {
        walkingRange != nil || elevationRange != nil || difficulties != nil
    }
}

public enum HikeListModel {
    /// Filter then sort. Hikes missing a filtered field are always kept;
    /// hikes missing the sort field go last regardless of direction.
    public static func arrange(_ hikes: [StoredHike], sort: HikeSortKey, ascending: Bool,
                               filter: HikeFilter, driveSeconds: (String) -> Int?) -> [StoredHike] {
        let filtered = hikes.filter { stored in
            let hike = stored.hike
            if let range = filter.walkingRange, let minutes = hike.walkingMinutes,
               !range.contains(minutes) { return false }
            if let range = filter.elevationRange, let meters = hike.routeElevationMeters,
               !range.contains(meters) { return false }
            if let allowed = filter.difficulties, let text = hike.difficultyText,
               !allowed.contains(text) { return false }
            return true
        }

        func sortValue(_ stored: StoredHike) -> Double? {
            switch sort {
            case .dateAdded: stored.hike.dateAdded.timeIntervalSince1970
            case .walkingTime: stored.hike.walkingMinutes.map(Double.init)
            case .difficulty: stored.hike.difficultyRank.map(Double.init)
            case .elevation: stored.hike.routeElevationMeters.map(Double.init)
            case .driveTime: driveSeconds(stored.hike.slug).map(Double.init)
            }
        }

        return filtered.sorted { a, b in
            switch (sortValue(a), sortValue(b)) {
            case let (va?, vb?): ascending ? va < vb : va > vb
            case (nil, .some): false
            case (.some, nil): true
            case (nil, nil): a.hike.dateAdded > b.hike.dateAdded
            }
        }
    }

    public static func walkingBounds(_ hikes: [StoredHike]) -> ClosedRange<Int>? {
        bounds(hikes.compactMap { $0.hike.walkingMinutes })
    }

    public static func elevationBounds(_ hikes: [StoredHike]) -> ClosedRange<Int>? {
        bounds(hikes.compactMap { $0.hike.routeElevationMeters })
    }

    /// Distinct difficulty texts present, ordered easy→hard; unrecognized values last, alphabetical.
    public static func difficultiesPresent(_ hikes: [StoredHike]) -> [String] {
        Set(hikes.compactMap { $0.hike.difficultyText }).sorted { a, b in
            switch (Hike.difficultyRank(from: a), Hike.difficultyRank(from: b)) {
            case let (ra?, rb?): ra == rb ? a < b : ra < rb
            case (nil, .some): false
            case (.some, nil): true
            case (nil, nil): a < b
            }
        }
    }

    public static func driveTimeText(seconds: Int) -> String {
        let minutes = (seconds + 30) / 60
        if minutes < 60 { return "\(minutes) min" }
        let remainder = minutes % 60
        return remainder == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(remainder) min"
    }

    private static func bounds(_ values: [Int]) -> ClosedRange<Int>? {
        guard let min = values.min(), let max = values.max() else { return nil }
        return min...max
    }
}
