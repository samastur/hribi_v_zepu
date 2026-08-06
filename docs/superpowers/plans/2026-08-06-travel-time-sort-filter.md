# Travel Time, Sorting & Filtering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Saved named start locations with cached car travel times to each hike's trailhead (MapKit), plus sorting and per-field-colored filtering of the hike list on Čas hoje, Zahtevnost, Višinska razlika po poti, and drive time.

**Architecture:** All logic lives in the `HikeKit` local Swift package (pure, unit-tested): stat parsing as `Hike` extensions, two new JSON-file stores (`LocationStore`, `TravelTimeStore`) following the existing `HikeStore` pattern, a `TravelTimeService` behind a `RouteEstimator` protocol (production adapter wraps `MKDirections`), and `HikeListModel` for sort/filter. SwiftUI views in `App/` consume these. Stored hike JSON is unchanged — no migration.

**Tech Stack:** Swift 5 mode, SwiftUI, MapKit (`MKDirections`, `MKLocalSearch`, `Map`), CoreLocation, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-05-travel-time-sort-filter-design.md`

## Global Constraints

- Package platforms: iOS "26.0", macOS .v14 (`HikeKit/Package.swift`). App deployment target iOS "26.0".
- Fast tests must run on macOS with no network: `cd HikeKit && swift test`. Never add tests that touch hribi.net or Apple routing servers.
- App build check: `xcodebuild -project HribiVZepu.xcodeproj -scheme HribiVZepu -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath DerivedData build` (run `xcodegen generate` first only when `project.yml` changed).
- JSON persistence uses the existing `JSONEncoder.hike` / `JSONDecoder.hike` (ISO-8601 dates, pretty, sorted keys).
- App group ID: `group.com.markos.hribivzepu` (constant `HikeStore.appGroupID`); file stores fall back to Documents when the group container is unavailable (same pattern as `HikeStore.defaultDirectory()`).
- UI copy for the new features is Slovenian (matches the hike field names): "Čas hoje", "Zahtevnost", "Višinska razlika po poti", "Čas vožnje", "Dodano", "Filtri", "Lokacije".
- Commit messages: `feat:`/`fix:`/`chore:` prefix, imperative, lowercase summary. **No Co-Authored-By or other trailers** (user preference).
- Public API in HikeKit needs explicit `public` and `public init` (existing convention).

## File Structure

| File | Responsibility |
|------|---------------|
| `HikeKit/Sources/HikeKit/HikeStats.swift` (new) | Parse Čas hoje / Višinska razlika po poti / Zahtevnost into numbers |
| `HikeKit/Sources/HikeKit/SavedLocation.swift` (new) | `SavedLocation` model + `LocationStore` (locations.json, active selection) |
| `HikeKit/Sources/HikeKit/TravelTimeStore.swift` (new) | Per-(location, hike) drive-time cache (traveltimes.json) |
| `HikeKit/Sources/HikeKit/TravelTimeService.swift` (new) | `RouteEstimator` protocol, `TravelTimeService` fill loop, `MapKitRouteEstimator` |
| `HikeKit/Sources/HikeKit/HikeListModel.swift` (new) | `HikeSortKey`, `HikeFilter`, arrange (filter+sort), bounds helpers, drive-time formatting |
| `App/StatColor.swift` (new) | Fixed per-field colors with light/dark variants |
| `App/FilterSheetView.swift` (new) | Filter sheet: range sliders + difficulty toggles |
| `App/LocationsView.swift` (new) | Manage-locations sheet (activate, delete, add entry point) |
| `App/AddLocationView.swift` (new) | Add location: search / current GPS / map pin |
| `App/CurrentLocationProvider.swift` (new) | One-shot async CoreLocation wrapper |
| `App/HikeListView.swift` (modify) | Colored row, sort menu, filter button, location menu, service wiring |
| `App/HribiVZepuApp.swift` (modify) | Construct the new stores |
| `project.yml` (modify) | `NSLocationWhenInUseUsageDescription` |

---

### Task 1: Hike stat parsing

**Files:**
- Create: `HikeKit/Sources/HikeKit/HikeStats.swift`
- Test: `HikeKit/Tests/HikeKitTests/HikeStatsTests.swift`

**Interfaces:**
- Consumes: `Hike`, `MetadataField`, `Hike.metadataValue(_:)` (existing).
- Produces: `Hike.walkingMinutes: Int?`, `Hike.routeElevationMeters: Int?`, `Hike.difficultyText: String?`, `Hike.difficultyRank: Int?`, and static parsers `Hike.walkingMinutes(from: String?) -> Int?`, `Hike.meters(from: String?) -> Int?`, `Hike.difficultyRank(from: String?) -> Int?`. Later tasks (5, 6, 7) rely on these exact names.

- [ ] **Step 1: Write the failing tests**

```swift
// HikeKit/Tests/HikeKitTests/HikeStatsTests.swift
import XCTest
@testable import HikeKit

final class HikeStatsTests: XCTestCase {
    func makeHike(metadata: [MetadataField]) -> Hike {
        Hike(slug: "s", sourceURL: URL(string: "https://www.hribi.net/izlet/s/1/2/3")!,
             title: "T", metadata: metadata, coordinate: nil, sections: [], images: [],
             expectedImageCount: 0, dateAdded: Date(timeIntervalSince1970: 0))
    }

    func testWalkingMinutesParsing() {
        XCTAssertEqual(Hike.walkingMinutes(from: "4 h"), 240)
        XCTAssertEqual(Hike.walkingMinutes(from: "3 h 30 min"), 210)
        XCTAssertEqual(Hike.walkingMinutes(from: "45 min"), 45)
        XCTAssertEqual(Hike.walkingMinutes(from: "4,5 h"), 270)
        XCTAssertEqual(Hike.walkingMinutes(from: "4.5 h"), 270)
        XCTAssertNil(Hike.walkingMinutes(from: nil))
        XCTAssertNil(Hike.walkingMinutes(from: ""))
        XCTAssertNil(Hike.walkingMinutes(from: "neznano"))
    }

    func testMetersParsing() {
        XCTAssertEqual(Hike.meters(from: "1410 m"), 1410)
        XCTAssertEqual(Hike.meters(from: "1.410 m"), 1410)
        XCTAssertEqual(Hike.meters(from: "80 m"), 80)
        XCTAssertNil(Hike.meters(from: nil))
        XCTAssertNil(Hike.meters(from: "veliko"))
    }

    func testDifficultyRankOrdering() {
        let ordered = [
            "lahka označena pot", "zahtevna označena pot", "zelo zahtevna označena pot",
            "lahko brezpotje", "zahtevno brezpotje", "zelo zahtevno brezpotje",
            "lahka plezalna pot", "zahtevna plezalna pot", "zelo zahtevna plezalna pot",
        ]
        let ranks = ordered.map { Hike.difficultyRank(from: $0) }
        XCTAssertEqual(ranks, [0, 1, 2, 3, 4, 5, 6, 7, 8].map { Optional($0) })
        XCTAssertNil(Hike.difficultyRank(from: "turno smučanje"))
        XCTAssertNil(Hike.difficultyRank(from: nil))
    }

    func testHikeAccessorsReadMetadata() {
        let hike = makeHike(metadata: [
            MetadataField(label: "Čas hoje", value: "3 h 30 min"),
            MetadataField(label: "Zahtevnost", value: "zahtevna označena pot"),
            MetadataField(label: "Višinska razlika", value: "1408 m"),
            MetadataField(label: "Višinska razlika po poti", value: "1410 m"),
        ])
        XCTAssertEqual(hike.walkingMinutes, 210)
        XCTAssertEqual(hike.difficultyText, "zahtevna označena pot")
        XCTAssertEqual(hike.difficultyRank, 1)
        XCTAssertEqual(hike.routeElevationMeters, 1410, "must read the 'po poti' field, not plain Višinska razlika")
    }

    func testMissingMetadataGivesNil() {
        let hike = makeHike(metadata: [])
        XCTAssertNil(hike.walkingMinutes)
        XCTAssertNil(hike.routeElevationMeters)
        XCTAssertNil(hike.difficultyText)
        XCTAssertNil(hike.difficultyRank)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd HikeKit && swift test --filter HikeStatsTests`
Expected: FAIL to compile — `walkingMinutes` not defined.

- [ ] **Step 3: Write the implementation**

```swift
// HikeKit/Sources/HikeKit/HikeStats.swift
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
        if let match = raw.firstMatch(of: /(\d+(?:\.\d+)?)\s*h\b/), let hours = Double(match.1) {
            total += hours * 60
            matched = true
        }
        if let match = raw.firstMatch(of: /(\d+)\s*min\b/), let minutes = Double(match.1) {
            total += minutes
            matched = true
        }
        return matched ? Int(total.rounded()) : nil
    }

    static func meters(from text: String?) -> Int? {
        guard let raw = text?.replacingOccurrences(of: ".", with: ""),
              let match = raw.firstMatch(of: /(\d+)\s*m\b/)
        else { return nil }
        return Int(match.1)
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd HikeKit && swift test --filter HikeStatsTests`
Expected: all PASS. Also run the full suite once: `swift test` — no regressions.

- [ ] **Step 5: Commit**

```bash
git add HikeKit/Sources/HikeKit/HikeStats.swift HikeKit/Tests/HikeKitTests/HikeStatsTests.swift
git commit -m "feat: parse walking time, elevation and difficulty from hike metadata"
```

---

### Task 2: SavedLocation model and LocationStore

**Files:**
- Create: `HikeKit/Sources/HikeKit/SavedLocation.swift`
- Test: `HikeKit/Tests/HikeKitTests/LocationStoreTests.swift`

**Interfaces:**
- Consumes: `Coordinate`, `HikeStore.appGroupID`, `JSONEncoder.hike`/`JSONDecoder.hike` (existing).
- Produces: `SavedLocation` (`id: UUID`, `name: String`, `latitude/longitude: Double`, `coordinate: Coordinate`, memberwise `init(id:name:latitude:longitude:)` with `id` defaulting to `UUID()`); `LocationStore` with `init(fileURL:)`, `static defaultFileURL() -> URL`, `locations: [SavedLocation]`, `activeLocation: SavedLocation?`, `add(_:)`, `delete(id:)`, `setActive(id:)`. Tasks 4, 8, 9 rely on these names.

- [ ] **Step 1: Write the failing tests**

```swift
// HikeKit/Tests/HikeKitTests/LocationStoreTests.swift
import XCTest
@testable import HikeKit

final class LocationStoreTests: XCTestCase {
    var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocationStoreTests-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testStartsEmpty() {
        let store = LocationStore(fileURL: fileURL)
        XCTAssertTrue(store.locations.isEmpty)
        XCTAssertNil(store.activeLocation)
    }

    func testFirstAddedLocationBecomesActive() {
        let store = LocationStore(fileURL: fileURL)
        let home = SavedLocation(name: "Dom", latitude: 46.05, longitude: 14.51)
        store.add(home)
        XCTAssertEqual(store.activeLocation?.id, home.id)
        let cottage = SavedLocation(name: "Vikend", latitude: 46.35, longitude: 14.10)
        store.add(cottage)
        XCTAssertEqual(store.activeLocation?.id, home.id, "adding more must not steal active")
    }

    func testSetActiveAndPersistAcrossReload() {
        let store = LocationStore(fileURL: fileURL)
        let home = SavedLocation(name: "Dom", latitude: 46.05, longitude: 14.51)
        let cottage = SavedLocation(name: "Vikend", latitude: 46.35, longitude: 14.10)
        store.add(home)
        store.add(cottage)
        store.setActive(id: cottage.id)

        let reloaded = LocationStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.locations.map(\.id), [home.id, cottage.id])
        XCTAssertEqual(reloaded.activeLocation?.id, cottage.id)
        XCTAssertEqual(reloaded.activeLocation?.name, "Vikend")
    }

    func testSetActiveIgnoresUnknownID() {
        let store = LocationStore(fileURL: fileURL)
        let home = SavedLocation(name: "Dom", latitude: 46.05, longitude: 14.51)
        store.add(home)
        store.setActive(id: UUID())
        XCTAssertEqual(store.activeLocation?.id, home.id)
    }

    func testDeleteActiveClearsActive() {
        let store = LocationStore(fileURL: fileURL)
        let home = SavedLocation(name: "Dom", latitude: 46.05, longitude: 14.51)
        store.add(home)
        store.delete(id: home.id)
        XCTAssertTrue(store.locations.isEmpty)
        XCTAssertNil(store.activeLocation)
        XCTAssertNil(LocationStore(fileURL: fileURL).activeLocation)
    }

    func testCoordinateBridge() {
        let loc = SavedLocation(name: "X", latitude: 46.1, longitude: 14.2)
        XCTAssertEqual(loc.coordinate, Coordinate(latitude: 46.1, longitude: 14.2))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd HikeKit && swift test --filter LocationStoreTests`
Expected: FAIL to compile — `SavedLocation` not defined.

- [ ] **Step 3: Write the implementation**

```swift
// HikeKit/Sources/HikeKit/SavedLocation.swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd HikeKit && swift test --filter LocationStoreTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add HikeKit/Sources/HikeKit/SavedLocation.swift HikeKit/Tests/HikeKitTests/LocationStoreTests.swift
git commit -m "feat: saved start locations with active selection"
```

---

### Task 3: TravelTimeStore cache

**Files:**
- Create: `HikeKit/Sources/HikeKit/TravelTimeStore.swift`
- Test: `HikeKit/Tests/HikeKitTests/TravelTimeStoreTests.swift`

**Interfaces:**
- Consumes: `HikeStore.appGroupID`, `JSONEncoder.hike`/`JSONDecoder.hike`.
- Produces: `TravelTimeEntry` (`driveSeconds: Int`, `fetchedAt: Date`); `TravelTimeStore` (`@MainActor`) with `init(fileURL:)`, `static defaultFileURL() -> URL`, `entry(locationID:slug:) -> TravelTimeEntry?`, `set(_:locationID:slug:)`, `driveSeconds(for locationID: UUID) -> [String: Int]`, `purgeLocation(id:)`, `purgeHike(slug:)`. Tasks 4, 8, 9 rely on these names. `fetchedAt` is stored for the future refresh/traffic feature — nothing reads it yet.

- [ ] **Step 1: Write the failing tests**

```swift
// HikeKit/Tests/HikeKitTests/TravelTimeStoreTests.swift
import XCTest
@testable import HikeKit

@MainActor
final class TravelTimeStoreTests: XCTestCase {
    var fileURL: URL!
    let home = UUID()
    let cottage = UUID()

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TravelTimeStoreTests-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func entry(_ seconds: Int) -> TravelTimeEntry {
        TravelTimeEntry(driveSeconds: seconds, fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testSetAndGetPersistAcrossReload() {
        let store = TravelTimeStore(fileURL: fileURL)
        store.set(entry(3600), locationID: home, slug: "triglav")
        XCTAssertEqual(store.entry(locationID: home, slug: "triglav")?.driveSeconds, 3600)
        XCTAssertNil(store.entry(locationID: home, slug: "unknown"))
        XCTAssertNil(store.entry(locationID: cottage, slug: "triglav"))

        let reloaded = TravelTimeStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entry(locationID: home, slug: "triglav")?.driveSeconds, 3600)
        XCTAssertEqual(reloaded.entry(locationID: home, slug: "triglav")?.fetchedAt,
                       Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testEntriesSurvivePerLocation() {
        let store = TravelTimeStore(fileURL: fileURL)
        store.set(entry(3600), locationID: home, slug: "triglav")
        store.set(entry(600), locationID: cottage, slug: "triglav")
        XCTAssertEqual(store.driveSeconds(for: home), ["triglav": 3600])
        XCTAssertEqual(store.driveSeconds(for: cottage), ["triglav": 600])
    }

    func testPurgeLocation() {
        let store = TravelTimeStore(fileURL: fileURL)
        store.set(entry(3600), locationID: home, slug: "triglav")
        store.set(entry(600), locationID: cottage, slug: "triglav")
        store.purgeLocation(id: home)
        XCTAssertTrue(store.driveSeconds(for: home).isEmpty)
        XCTAssertEqual(store.driveSeconds(for: cottage), ["triglav": 600])
        XCTAssertTrue(TravelTimeStore(fileURL: fileURL).driveSeconds(for: home).isEmpty)
    }

    func testPurgeHikeRemovesSlugFromAllLocations() {
        let store = TravelTimeStore(fileURL: fileURL)
        store.set(entry(3600), locationID: home, slug: "triglav")
        store.set(entry(1200), locationID: home, slug: "stol")
        store.set(entry(600), locationID: cottage, slug: "triglav")
        store.purgeHike(slug: "triglav")
        XCTAssertEqual(store.driveSeconds(for: home), ["stol": 1200])
        XCTAssertTrue(store.driveSeconds(for: cottage).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd HikeKit && swift test --filter TravelTimeStoreTests`
Expected: FAIL to compile — `TravelTimeEntry` not defined.

- [ ] **Step 3: Write the implementation**

```swift
// HikeKit/Sources/HikeKit/TravelTimeStore.swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd HikeKit && swift test --filter TravelTimeStoreTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add HikeKit/Sources/HikeKit/TravelTimeStore.swift HikeKit/Tests/HikeKitTests/TravelTimeStoreTests.swift
git commit -m "feat: per-location drive time cache"
```

---

### Task 4: TravelTimeService and route estimators

**Files:**
- Create: `HikeKit/Sources/HikeKit/TravelTimeService.swift`
- Test: `HikeKit/Tests/HikeKitTests/TravelTimeServiceTests.swift`

**Interfaces:**
- Consumes: `Coordinate`, `Hike`, `SavedLocation`, `TravelTimeStore`, `TravelTimeEntry`.
- Produces: `RouteEstimator` protocol with `func driveTime(from: Coordinate, to: Coordinate) async throws -> TimeInterval`; `TravelTimeService` (`@MainActor`) with `init(estimator:store:spacing:)` (spacing defaults to `.seconds(1)`) and `fill(hikes: [Hike], location: SavedLocation, onEntry: ((String, TravelTimeEntry) -> Void)?) async`; `MapKitRouteEstimator` (production). Task 9 relies on these names.

- [ ] **Step 1: Write the failing tests**

```swift
// HikeKit/Tests/HikeKitTests/TravelTimeServiceTests.swift
import XCTest
@testable import HikeKit

/// Single-threaded in tests; recorded state read only after fill() returns.
final class FakeEstimator: RouteEstimator, @unchecked Sendable {
    var requestedSlugsByCoordinate: [Coordinate] = []
    var failFor: Set<Double> = []  // destination latitudes that throw

    struct NoRoute: Error {}

    func driveTime(from: Coordinate, to: Coordinate) async throws -> TimeInterval {
        requestedSlugsByCoordinate.append(to)
        if failFor.contains(to.latitude) { throw NoRoute() }
        return 60 * to.latitude  // deterministic, distinguishable per hike
    }
}

@MainActor
final class TravelTimeServiceTests: XCTestCase {
    var fileURL: URL!
    var store: TravelTimeStore!
    var estimator: FakeEstimator!
    var service: TravelTimeService!
    let location = SavedLocation(name: "Dom", latitude: 46.05, longitude: 14.51)

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TravelTimeServiceTests-\(UUID().uuidString).json")
        store = TravelTimeStore(fileURL: fileURL)
        estimator = FakeEstimator()
        service = TravelTimeService(estimator: estimator, store: store, spacing: .zero)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func makeHike(slug: String, latitude: Double?) -> Hike {
        Hike(slug: slug, sourceURL: URL(string: "https://www.hribi.net/izlet/\(slug)/1/2/3")!,
             title: slug, metadata: [],
             coordinate: latitude.map { Coordinate(latitude: $0, longitude: 13.8) },
             sections: [], images: [], expectedImageCount: 0,
             dateAdded: Date(timeIntervalSince1970: 0))
    }

    func testFillsMissingEntriesAndSkipsHikesWithoutCoordinate() async {
        let hikes = [makeHike(slug: "a", latitude: 46.1),
                     makeHike(slug: "none", latitude: nil),
                     makeHike(slug: "b", latitude: 46.2)]
        await service.fill(hikes: hikes, location: location, onEntry: nil)
        XCTAssertEqual(store.entry(locationID: location.id, slug: "a")?.driveSeconds, Int(60 * 46.1))
        XCTAssertEqual(store.entry(locationID: location.id, slug: "b")?.driveSeconds, Int(60 * 46.2))
        XCTAssertNil(store.entry(locationID: location.id, slug: "none"))
        XCTAssertEqual(estimator.requestedSlugsByCoordinate.count, 2)
    }

    func testSkipsAlreadyCachedEntries() async {
        store.set(TravelTimeEntry(driveSeconds: 999, fetchedAt: Date()),
                  locationID: location.id, slug: "a")
        await service.fill(hikes: [makeHike(slug: "a", latitude: 46.1)], location: location, onEntry: nil)
        XCTAssertEqual(estimator.requestedSlugsByCoordinate.count, 0)
        XCTAssertEqual(store.entry(locationID: location.id, slug: "a")?.driveSeconds, 999)
    }

    func testFailureLeavesEntryUncachedAndContinues() async {
        estimator.failFor = [46.1]
        let hikes = [makeHike(slug: "bad", latitude: 46.1), makeHike(slug: "good", latitude: 46.2)]
        await service.fill(hikes: hikes, location: location, onEntry: nil)
        XCTAssertNil(store.entry(locationID: location.id, slug: "bad"))
        XCTAssertNotNil(store.entry(locationID: location.id, slug: "good"))
        // Retried on a later fill:
        estimator.failFor = []
        await service.fill(hikes: hikes, location: location, onEntry: nil)
        XCTAssertNotNil(store.entry(locationID: location.id, slug: "bad"))
    }

    func testOnEntryCallbackFires() async {
        var received: [String] = []
        await service.fill(hikes: [makeHike(slug: "a", latitude: 46.1)], location: location) { slug, _ in
            received.append(slug)
        }
        XCTAssertEqual(received, ["a"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd HikeKit && swift test --filter TravelTimeServiceTests`
Expected: FAIL to compile — `RouteEstimator` not defined.

- [ ] **Step 3: Write the implementation**

```swift
// HikeKit/Sources/HikeKit/TravelTimeService.swift
import Foundation
import MapKit

public protocol RouteEstimator: Sendable {
    /// Estimated car travel time in seconds between two coordinates.
    func driveTime(from: Coordinate, to: Coordinate) async throws -> TimeInterval
}

/// Fills the TravelTimeStore for one location: skips cached slugs and hikes
/// without a coordinate, spaces requests to stay friendly with MapKit
/// throttling, persists each result immediately, and stops when cancelled.
/// Failures are skipped and retried on the next fill call.
@MainActor
public final class TravelTimeService {
    private let estimator: RouteEstimator
    private let store: TravelTimeStore
    private let spacing: Duration

    public init(estimator: RouteEstimator, store: TravelTimeStore, spacing: Duration = .seconds(1)) {
        self.estimator = estimator
        self.store = store
        self.spacing = spacing
    }

    public func fill(hikes: [Hike], location: SavedLocation,
                     onEntry: ((String, TravelTimeEntry) -> Void)? = nil) async {
        for hike in hikes {
            guard !Task.isCancelled else { return }
            guard let destination = hike.coordinate,
                  store.entry(locationID: location.id, slug: hike.slug) == nil
            else { continue }
            if let seconds = try? await estimator.driveTime(from: location.coordinate, to: destination) {
                let entry = TravelTimeEntry(driveSeconds: Int(seconds), fetchedAt: Date())
                store.set(entry, locationID: location.id, slug: hike.slug)
                onEntry?(hike.slug, entry)
            }
            try? await Task.sleep(for: spacing)
        }
    }
}

public struct MapKitRouteEstimator: RouteEstimator {
    public struct NoRouteFound: Error {}

    public init() {}

    public func driveTime(from: Coordinate, to: Coordinate) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate:
            CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate:
            CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)))
        request.transportType = .automobile
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw NoRouteFound() }
        return route.expectedTravelTime
    }
}
```

Note: `MapKitRouteEstimator` is compile-verified only — no test may call Apple's routing servers. If `MKMapItem(placemark:)` produces deprecation warnings on the iOS 26 SDK, keep it anyway: the replacement (`MKMapItem(location:address:)`) is unavailable on macOS 14, which `swift test` builds against.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd HikeKit && swift test --filter TravelTimeServiceTests`
Expected: all PASS. Then the full suite: `swift test` — no regressions.

- [ ] **Step 5: Commit**

```bash
git add HikeKit/Sources/HikeKit/TravelTimeService.swift HikeKit/Tests/HikeKitTests/TravelTimeServiceTests.swift
git commit -m "feat: travel time service with MapKit route estimator"
```

---

### Task 5: Sort and filter model

**Files:**
- Create: `HikeKit/Sources/HikeKit/HikeListModel.swift`
- Test: `HikeKit/Tests/HikeKitTests/HikeListModelTests.swift`

**Interfaces:**
- Consumes: `StoredHike`, `Hike.walkingMinutes` / `.routeElevationMeters` / `.difficultyRank` / `.difficultyText` (Task 1).
- Produces:
  - `HikeSortKey: String, CaseIterable, Sendable` — cases `dateAdded, walkingTime, difficulty, elevation, driveTime`; `var label: String` (Slovenian).
  - `HikeFilter` — `walkingRange: ClosedRange<Int>?`, `elevationRange: ClosedRange<Int>?`, `difficulties: Set<String>?`, `isActive: Bool`, `init()` giving all-nil.
  - `HikeListModel.arrange(_:sort:ascending:filter:driveSeconds:) -> [StoredHike]`
  - `HikeListModel.walkingBounds(_:) -> ClosedRange<Int>?`, `.elevationBounds(_:) -> ClosedRange<Int>?`, `.difficultiesPresent(_:) -> [String]`
  - `HikeListModel.driveTimeText(seconds: Int) -> String` — "45 min", "1 h 5 min", "2 h".
  Tasks 6, 7, 9 rely on these exact names.

- [ ] **Step 1: Write the failing tests**

```swift
// HikeKit/Tests/HikeKitTests/HikeListModelTests.swift
import XCTest
@testable import HikeKit

final class HikeListModelTests: XCTestCase {
    func stored(slug: String, date: TimeInterval = 0, walk: String? = nil,
                difficulty: String? = nil, elevation: String? = nil) -> StoredHike {
        var metadata: [MetadataField] = []
        if let walk { metadata.append(MetadataField(label: "Čas hoje", value: walk)) }
        if let difficulty { metadata.append(MetadataField(label: "Zahtevnost", value: difficulty)) }
        if let elevation { metadata.append(MetadataField(label: "Višinska razlika po poti", value: elevation)) }
        let hike = Hike(slug: slug, sourceURL: URL(string: "https://www.hribi.net/izlet/\(slug)/1/2/3")!,
                        title: slug, metadata: metadata, coordinate: nil, sections: [], images: [],
                        expectedImageCount: 0, dateAdded: Date(timeIntervalSince1970: date))
        return StoredHike(hike: hike, directory: URL(fileURLWithPath: "/tmp/\(slug)"), sizeBytes: 0)
    }

    let noDrive: (String) -> Int? = { _ in nil }

    func testDefaultSortIsDateAddedDescending() {
        let hikes = [stored(slug: "old", date: 1_000), stored(slug: "new", date: 2_000)]
        let result = HikeListModel.arrange(hikes, sort: .dateAdded, ascending: false,
                                           filter: HikeFilter(), driveSeconds: noDrive)
        XCTAssertEqual(result.map(\.hike.slug), ["new", "old"])
    }

    func testSortByWalkingTimeMissingLast() {
        let hikes = [stored(slug: "long", walk: "6 h"),
                     stored(slug: "unknown"),
                     stored(slug: "short", walk: "1 h 30 min")]
        let asc = HikeListModel.arrange(hikes, sort: .walkingTime, ascending: true,
                                        filter: HikeFilter(), driveSeconds: noDrive)
        XCTAssertEqual(asc.map(\.hike.slug), ["short", "long", "unknown"])
        let desc = HikeListModel.arrange(hikes, sort: .walkingTime, ascending: false,
                                         filter: HikeFilter(), driveSeconds: noDrive)
        XCTAssertEqual(desc.map(\.hike.slug), ["long", "short", "unknown"],
                       "missing values stay last even when descending")
    }

    func testSortByDifficultyAndElevation() {
        let hikes = [stored(slug: "hard", difficulty: "zelo zahtevna označena pot", elevation: "1.500 m"),
                     stored(slug: "easy", difficulty: "lahka označena pot", elevation: "300 m")]
        XCTAssertEqual(HikeListModel.arrange(hikes, sort: .difficulty, ascending: true,
                                             filter: HikeFilter(), driveSeconds: noDrive).map(\.hike.slug),
                       ["easy", "hard"])
        XCTAssertEqual(HikeListModel.arrange(hikes, sort: .elevation, ascending: false,
                                             filter: HikeFilter(), driveSeconds: noDrive).map(\.hike.slug),
                       ["hard", "easy"])
    }

    func testSortByDriveTimeUsesLookup() {
        let hikes = [stored(slug: "far"), stored(slug: "near"), stored(slug: "nocoord")]
        let drive: (String) -> Int? = { ["far": 7200, "near": 1200][$0] }
        let result = HikeListModel.arrange(hikes, sort: .driveTime, ascending: true,
                                           filter: HikeFilter(), driveSeconds: drive)
        XCTAssertEqual(result.map(\.hike.slug), ["near", "far", "nocoord"])
    }

    func testRangeFiltersKeepHikesMissingTheField() {
        var filter = HikeFilter()
        filter.walkingRange = 120...300
        let hikes = [stored(slug: "in", walk: "3 h"),
                     stored(slug: "out", walk: "6 h"),
                     stored(slug: "unknown")]
        let result = HikeListModel.arrange(hikes, sort: .dateAdded, ascending: false,
                                           filter: filter, driveSeconds: noDrive)
        XCTAssertEqual(Set(result.map(\.hike.slug)), ["in", "unknown"])
    }

    func testElevationRangeFilter() {
        var filter = HikeFilter()
        filter.elevationRange = 500...1000
        let hikes = [stored(slug: "in", elevation: "800 m"), stored(slug: "out", elevation: "1.400 m")]
        let result = HikeListModel.arrange(hikes, sort: .dateAdded, ascending: false,
                                           filter: filter, driveSeconds: noDrive)
        XCTAssertEqual(result.map(\.hike.slug), ["in"])
    }

    func testDifficultyFilterKeepsMissing() {
        var filter = HikeFilter()
        filter.difficulties = ["lahka označena pot"]
        let hikes = [stored(slug: "easy", difficulty: "lahka označena pot"),
                     stored(slug: "hard", difficulty: "zahtevno brezpotje"),
                     stored(slug: "unknown")]
        let result = HikeListModel.arrange(hikes, sort: .dateAdded, ascending: false,
                                           filter: filter, driveSeconds: noDrive)
        XCTAssertEqual(Set(result.map(\.hike.slug)), ["easy", "unknown"])
    }

    func testIsActive() {
        var filter = HikeFilter()
        XCTAssertFalse(filter.isActive)
        filter.difficulties = ["lahka označena pot"]
        XCTAssertTrue(filter.isActive)
    }

    func testBoundsAndDifficultiesPresent() {
        let hikes = [stored(slug: "a", walk: "2 h", difficulty: "zahtevna označena pot", elevation: "1.400 m"),
                     stored(slug: "b", walk: "5 h 30 min", difficulty: "lahka označena pot", elevation: "600 m"),
                     stored(slug: "c")]
        XCTAssertEqual(HikeListModel.walkingBounds(hikes), 120...330)
        XCTAssertEqual(HikeListModel.elevationBounds(hikes), 600...1400)
        XCTAssertEqual(HikeListModel.difficultiesPresent(hikes),
                       ["lahka označena pot", "zahtevna označena pot"], "ordered easy→hard")
        XCTAssertNil(HikeListModel.walkingBounds([stored(slug: "c")]))
    }

    func testDriveTimeText() {
        XCTAssertEqual(HikeListModel.driveTimeText(seconds: 45 * 60), "45 min")
        XCTAssertEqual(HikeListModel.driveTimeText(seconds: 3900), "1 h 5 min")
        XCTAssertEqual(HikeListModel.driveTimeText(seconds: 7200), "2 h")
        XCTAssertEqual(HikeListModel.driveTimeText(seconds: 29), "0 min")
    }

    func testSortKeyLabels() {
        XCTAssertEqual(HikeSortKey.dateAdded.label, "Dodano")
        XCTAssertEqual(HikeSortKey.walkingTime.label, "Čas hoje")
        XCTAssertEqual(HikeSortKey.difficulty.label, "Zahtevnost")
        XCTAssertEqual(HikeSortKey.elevation.label, "Višinska razlika po poti")
        XCTAssertEqual(HikeSortKey.driveTime.label, "Čas vožnje")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd HikeKit && swift test --filter HikeListModelTests`
Expected: FAIL to compile — `HikeListModel` not defined.

- [ ] **Step 3: Write the implementation**

```swift
// HikeKit/Sources/HikeKit/HikeListModel.swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd HikeKit && swift test --filter HikeListModelTests`
Expected: all PASS. Then the full suite: `swift test` — no regressions.

- [ ] **Step 5: Commit**

```bash
git add HikeKit/Sources/HikeKit/HikeListModel.swift HikeKit/Tests/HikeKitTests/HikeListModelTests.swift
git commit -m "feat: hike list sorting and filtering model"
```

---

### Task 6: Colored stat row

**Files:**
- Create: `App/StatColor.swift`
- Modify: `App/HikeListView.swift` (the `HikeRow` struct at the bottom)

**Interfaces:**
- Consumes: `Hike.difficultyText` (Task 1), `metadataValue(_:)` (existing).
- Produces: `Color.statWalking`, `.statDifficulty`, `.statElevation`, `.statDrive`; `HikeRow` gains `let driveText: String?` (pass `nil` everywhere until Task 9 wires real values). Task 9 relies on `driveText`.

- [ ] **Step 1: Create the stat colors**

```swift
// App/StatColor.swift
import SwiftUI

extension Color {
    /// Resolves per light/dark so each variant can be tuned for ≥4.5:1 contrast
    /// against the system grouped list background.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    // Fixed field-identity colors (spec): blue / orange / purple / teal.
    static let statWalking = Color(light: Color(red: 0.00, green: 0.27, blue: 0.68),
                                   dark: Color(red: 0.45, green: 0.66, blue: 1.00))
    static let statDifficulty = Color(light: Color(red: 0.58, green: 0.24, blue: 0.00),
                                      dark: Color(red: 1.00, green: 0.63, blue: 0.30))
    static let statElevation = Color(light: Color(red: 0.42, green: 0.13, blue: 0.66),
                                     dark: Color(red: 0.79, green: 0.57, blue: 1.00))
    static let statDrive = Color(light: Color(red: 0.00, green: 0.35, blue: 0.34),
                                 dark: Color(red: 0.31, green: 0.80, blue: 0.77))
}
```

- [ ] **Step 2: Replace `HikeRow` in `App/HikeListView.swift`**

Replace the entire existing `HikeRow` struct (currently a `statLine: String` joining Čas hoje / Zahtevnost / plain "Višinska razlika") with:

```swift
struct HikeRow: View {
    let stored: StoredHike
    let driveText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stored.hike.title).font(.headline)
            if let stats = statLine {
                stats.font(.subheadline)
            }
            Text(ByteCountFormatter.string(fromByteCount: stored.sizeBytes, countStyle: .file))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    /// One Text so the stats wrap as a single line of colored segments.
    private var statLine: Text? {
        let hike = stored.hike
        var parts: [Text] = []
        if let walk = hike.metadataValue("Čas hoje") {
            parts.append(Text(walk).foregroundStyle(Color.statWalking))
        }
        if let difficulty = hike.difficultyText {
            parts.append(Text(difficulty).foregroundStyle(Color.statDifficulty))
        }
        if let elevation = hike.metadataValue("Višinska razlika po poti") {
            parts.append(Text(elevation).foregroundStyle(Color.statElevation))
        }
        if let driveText {
            parts.append((Text(Image(systemName: "car.fill")) + Text(" \(driveText)"))
                .foregroundStyle(Color.statDrive))
        }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) {
            $0 + Text(" · ").foregroundStyle(.secondary) + $1
        }
    }
}
```

And update the single call site inside `hikeList` from `HikeRow(stored: stored)` to:

```swift
HikeRow(stored: stored, driveText: nil)
```

- [ ] **Step 3: Build and verify in the simulator**

```bash
xcodebuild -project HribiVZepu.xcodeproj -scheme HribiVZepu \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath DerivedData build
xcrun simctl boot "iPhone 17" || true
open -a Simulator
xcrun simctl install booted DerivedData/Build/Products/Debug-iphonesimulator/HribiVZepu.app
xcrun simctl launch booted com.markos.hribivzepu
```

Expected: build succeeds; a saved hike row shows Čas hoje in blue, Zahtevnost in orange, Višinska razlika **po poti** in purple, separated by grey dots. Toggle dark mode (Simulator: Features → Toggle Appearance) — colors switch to their brighter dark variants and stay readable. If no hike is saved, add one first (see README "Adding a hike").

- [ ] **Step 4: Commit**

```bash
git add App/StatColor.swift App/HikeListView.swift
git commit -m "feat: per-field colored stats in hike list rows"
```

---

### Task 7: Sort menu and filter sheet

**Files:**
- Create: `App/FilterSheetView.swift`
- Modify: `App/HikeListView.swift`

**Interfaces:**
- Consumes: `HikeSortKey`, `HikeFilter`, `HikeListModel.arrange/walkingBounds/elevationBounds/difficultiesPresent` (Task 5).
- Produces: `FilterSheetView(walkingBounds:elevationBounds:difficulties:filter:)`; `HikeListView` gains `@AppStorage` sort state and `@State` filter state. Task 9 extends the same `arrange` call with real drive times.

- [ ] **Step 1: Create the filter sheet**

```swift
// App/FilterSheetView.swift
import SwiftUI
import HikeKit

struct FilterSheetView: View {
    let walkingBounds: ClosedRange<Int>?
    let elevationBounds: ClosedRange<Int>?
    let difficulties: [String]
    @Binding var filter: HikeFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let bounds = walkingBounds {
                    RangeFilterSection(title: "Čas hoje", bounds: bounds,
                                       format: { HikeListModel.driveTimeText(seconds: $0 * 60) },
                                       selection: $filter.walkingRange)
                }
                if let bounds = elevationBounds {
                    RangeFilterSection(title: "Višinska razlika po poti", bounds: bounds,
                                       format: { "\($0) m" },
                                       selection: $filter.elevationRange)
                }
                if !difficulties.isEmpty {
                    Section("Zahtevnost") {
                        ForEach(difficulties, id: \.self) { value in
                            Toggle(value, isOn: binding(for: value))
                        }
                    }
                }
                Section {
                    Button("Počisti filtre", role: .destructive) { filter = HikeFilter() }
                        .disabled(!filter.isActive)
                }
            }
            .navigationTitle("Filtri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Končano") { dismiss() } }
            }
        }
    }

    /// nil difficulty set means "all allowed"; the set materializes on first toggle-off
    /// and collapses back to nil when every value is on again.
    private func binding(for value: String) -> Binding<Bool> {
        Binding(
            get: { filter.difficulties?.contains(value) ?? true },
            set: { isOn in
                var selected = filter.difficulties ?? Set(difficulties)
                if isOn { selected.insert(value) } else { selected.remove(value) }
                filter.difficulties = selected == Set(difficulties) ? nil : selected
            })
    }
}

/// Min/max pair of sliders over the values present in saved hikes.
/// nil selection = filter inactive (sliders sit at the bounds).
struct RangeFilterSection: View {
    let title: String
    let bounds: ClosedRange<Int>
    let format: (Int) -> String
    @Binding var selection: ClosedRange<Int>?

    var body: some View {
        Section(title) {
            let current = selection ?? bounds
            LabeledContent("Od", value: format(current.lowerBound))
            Slider(value: Binding(
                get: { Double(current.lowerBound) },
                set: { newValue in
                    let lower = min(Int(newValue), current.upperBound)
                    selection = lower...current.upperBound
                }), in: Double(bounds.lowerBound)...Double(bounds.upperBound), step: 1)
            LabeledContent("Do", value: format(current.upperBound))
            Slider(value: Binding(
                get: { Double(current.upperBound) },
                set: { newValue in
                    let upper = max(Int(newValue), current.lowerBound)
                    selection = current.lowerBound...upper
                }), in: Double(bounds.lowerBound)...Double(bounds.upperBound), step: 1)
        }
    }
}
```

- [ ] **Step 2: Wire sort and filter into `HikeListView`**

In `App/HikeListView.swift`:

Add state (below the existing `@State` properties):

```swift
    @AppStorage("sortKey") private var sortKeyRaw = HikeSortKey.dateAdded.rawValue
    @AppStorage("sortAscending") private var sortAscending = false
    @State private var filter = HikeFilter()
    @State private var showingFilters = false

    private var sortKey: HikeSortKey { HikeSortKey(rawValue: sortKeyRaw) ?? .dateAdded }

    private var displayedHikes: [StoredHike] {
        HikeListModel.arrange(hikes, sort: sortKey, ascending: sortAscending,
                              filter: filter, driveSeconds: { _ in nil })
    }
```

Change `hikeList`'s `ForEach(hikes)` to `ForEach(displayedHikes)`, and the delete mapping to `pendingDelete = indexSet.first.map { displayedHikes[$0] }`.

Replace the single-button `.toolbar { ... }` with:

```swift
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    sortMenu
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: filter.isActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterSheetView(walkingBounds: HikeListModel.walkingBounds(hikes),
                                elevationBounds: HikeListModel.elevationBounds(hikes),
                                difficulties: HikeListModel.difficultiesPresent(hikes),
                                filter: $filter)
                    .presentationDetents([.medium, .large])
            }
```

Add the sort menu as a private property:

```swift
    private var sortMenu: some View {
        Menu {
            ForEach(HikeSortKey.allCases, id: \.self) { key in
                Button {
                    if sortKey == key {
                        sortAscending.toggle()
                    } else {
                        sortKeyRaw = key.rawValue
                        sortAscending = key != .dateAdded  // dates default newest-first
                    }
                } label: {
                    if sortKey == key {
                        Label(key.label, systemImage: sortAscending ? "chevron.up" : "chevron.down")
                    } else {
                        Text(key.label)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }
```

- [ ] **Step 3: Build and verify in the simulator**

Run the same build/install/launch commands as Task 6 Step 3. Verify with at least two saved hikes:
- Sort menu lists Dodano / Čas hoje / Zahtevnost / Višinska razlika po poti / Čas vožnje; picking Čas hoje reorders; picking it again flips direction (chevron flips).
- Sort choice survives app relaunch (`xcrun simctl launch booted com.markos.hribivzepu` again).
- Filter sheet shows both range sections with bounds matching your hikes' min/max and a toggle per difficulty present; narrowing a range hides out-of-range hikes but never hides a hike missing that field; the toolbar filter icon fills while any filter is active; "Počisti filtre" restores everything.
- Sorting by Čas vožnje puts everything in date order (all missing) — real values arrive in Task 9.

- [ ] **Step 4: Commit**

```bash
git add App/FilterSheetView.swift App/HikeListView.swift
git commit -m "feat: sort menu and filter sheet for hike list"
```

---

### Task 8: Locations management UI

**Files:**
- Create: `App/LocationsView.swift`, `App/AddLocationView.swift`, `App/CurrentLocationProvider.swift`
- Modify: `project.yml` (location permission string)

**Interfaces:**
- Consumes: `LocationStore` (Task 2), `TravelTimeStore.purgeLocation(id:)` (Task 3).
- Produces: `LocationsView(locationStore:travelTimeStore:onChange:)` — manage sheet; `AddLocationView(locationStore:onSaved:)`; `CurrentLocationProvider.currentCoordinate() async throws -> CLLocationCoordinate2D`. Task 9 presents `LocationsView` from the list's location menu.

- [ ] **Step 1: Add the location permission string**

In `project.yml`, under `targets.HribiVZepu.info.properties`, add:

```yaml
        NSLocationWhenInUseUsageDescription: Lokacija se uporabi samo za shranjevanje trenutnega mesta kot izhodišča za izračun časa vožnje do izletov.
```

Then run: `xcodegen generate`

- [ ] **Step 2: Create the one-shot location provider**

```swift
// App/CurrentLocationProvider.swift
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
```

- [ ] **Step 3: Create the add-location view**

```swift
// App/AddLocationView.swift
import SwiftUI
import MapKit
import HikeKit

struct AddLocationView: View {
    let locationStore: LocationStore
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable {
        case search = "Išči", current = "Tu sem", map = "Zemljevid"
    }

    @State private var mode: Mode = .search
    @State private var name = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var searchText = ""
    @State private var results: [MKMapItem] = []
    @State private var locating = false
    @State private var errorText: String?
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.12, longitude: 14.82),  // Slovenia
        span: MKCoordinateSpan(latitudeDelta: 2.4, longitudeDelta: 3.6)))
    private let locationProvider = CurrentLocationProvider()

    var body: some View {
        NavigationStack {
            Form {
                Section("Ime") {
                    TextField("npr. Dom", text: $name)
                }
                Section("Lokacija") {
                    Picker("Način", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .search: searchContent
                    case .current: currentContent
                    case .map: mapContent
                    }

                    if let coordinate {
                        Text(String(format: "Izbrano: %.5f, %.5f", coordinate.latitude, coordinate.longitude))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Nova lokacija")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Prekliči") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Shrani") { save() }
                        .disabled(coordinate == nil
                                  || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder private var searchContent: some View {
        TextField("Naslov ali kraj", text: $searchText)
            .autocorrectionDisabled()
            .onSubmit(runSearch)
        ForEach(results, id: \.self) { item in
            Button {
                coordinate = item.placemark.coordinate
                if name.trimmingCharacters(in: .whitespaces).isEmpty {
                    name = item.name ?? ""
                }
            } label: {
                VStack(alignment: .leading) {
                    Text(item.name ?? "—")
                    if let title = item.placemark.title {
                        Text(title).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var currentContent: some View {
        Button {
            locating = true
            errorText = nil
            Task {
                defer { locating = false }
                do { coordinate = try await locationProvider.currentCoordinate() }
                catch { errorText = error.localizedDescription }
            }
        } label: {
            if locating { ProgressView() } else { Label("Uporabi trenutno lokacijo", systemImage: "location.fill") }
        }
        .disabled(locating)
    }

    @ViewBuilder private var mapContent: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let coordinate {
                    Marker(name.isEmpty ? "Izbrano" : name, coordinate: coordinate)
                }
            }
            .frame(height: 300)
            .onTapGesture { screenPoint in
                if let tapped = proxy.convert(screenPoint, from: .local) {
                    coordinate = tapped
                }
            }
        }
        Text("Tapnite zemljevid za izbiro točke.")
            .font(.footnote).foregroundStyle(.secondary)
    }

    private func runSearch() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        errorText = nil
        Task {
            do { results = try await MKLocalSearch(request: request).start().mapItems }
            catch { errorText = "Iskanje ni uspelo — preverite povezavo." }
        }
    }

    private func save() {
        guard let coordinate else { return }
        locationStore.add(SavedLocation(name: name.trimmingCharacters(in: .whitespaces),
                                        latitude: coordinate.latitude,
                                        longitude: coordinate.longitude))
        onSaved()
        dismiss()
    }
}
```

- [ ] **Step 4: Create the manage-locations view**

```swift
// App/LocationsView.swift
import SwiftUI
import HikeKit

struct LocationsView: View {
    let locationStore: LocationStore
    let travelTimeStore: TravelTimeStore
    var onChange: () -> Void
    @State private var locations: [SavedLocation] = []
    @State private var activeID: UUID?
    @State private var showingAdd = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if locations.isEmpty {
                    ContentUnavailableView(
                        "Ni lokacij",
                        systemImage: "house",
                        description: Text("Dodajte izhodiščno lokacijo (npr. dom) za izračun časa vožnje do izletov."))
                } else {
                    List {
                        ForEach(locations) { location in
                            Button {
                                locationStore.setActive(id: location.id)
                                refresh()
                                onChange()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(location.name).foregroundStyle(.primary)
                                        Text(String(format: "%.5f, %.5f", location.latitude, location.longitude))
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if location.id == activeID {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let location = locations[index]
                                locationStore.delete(id: location.id)
                                travelTimeStore.purgeLocation(id: location.id)
                            }
                            refresh()
                            onChange()
                        }
                    }
                }
            }
            .navigationTitle("Lokacije")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Končano") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddLocationView(locationStore: locationStore) {
                    refresh()
                    onChange()
                }
            }
            .onAppear(perform: refresh)
        }
    }

    private func refresh() {
        locations = locationStore.locations
        activeID = locationStore.activeLocation?.id
    }
}
```

- [ ] **Step 5: Build and verify in the simulator**

Build/install/launch as in Task 6 Step 3 (note: `xcodegen generate` already ran in Step 1; the views aren't reachable from the UI yet — that's Task 9 — so just confirm the build succeeds).

Run: `cd HikeKit && swift test`
Expected: build succeeds, full test suite still passes.

- [ ] **Step 6: Commit**

```bash
git add App/LocationsView.swift App/AddLocationView.swift App/CurrentLocationProvider.swift project.yml
git commit -m "feat: manage start locations with search, GPS and map pin entry"
```

---

### Task 9: Wire travel times into the list

**Files:**
- Modify: `App/HribiVZepuApp.swift`, `App/HikeListView.swift`

**Interfaces:**
- Consumes: everything above — `LocationStore`, `TravelTimeStore`, `TravelTimeService`, `MapKitRouteEstimator`, `LocationsView`, `HikeListModel.driveTimeText(seconds:)`, `HikeRow(stored:driveText:)`.
- Produces: the finished feature.

- [ ] **Step 1: Construct stores in the app entry**

```swift
// App/HribiVZepuApp.swift — replace the whole file
import SwiftUI
import HikeKit

@main
struct HribiVZepuApp: App {
    var body: some Scene {
        WindowGroup {
            HikeListView(store: HikeStore(baseDirectory: HikeStore.defaultDirectory()),
                         locationStore: LocationStore(fileURL: LocationStore.defaultFileURL()),
                         travelTimeStore: TravelTimeStore(fileURL: TravelTimeStore.defaultFileURL()))
        }
    }
}
```

- [ ] **Step 2: Wire the service and location menu into `HikeListView`**

Add properties (`store` stays as is):

```swift
    let locationStore: LocationStore
    let travelTimeStore: TravelTimeStore
    @State private var driveTimes: [String: Int] = [:]
    @State private var activeLocationName: String?
    @State private var showingLocations = false
    @State private var fillTask: Task<Void, Never>?
```

Update `displayedHikes` to use real drive times:

```swift
    private var displayedHikes: [StoredHike] {
        HikeListModel.arrange(hikes, sort: sortKey, ascending: sortAscending,
                              filter: filter, driveSeconds: { driveTimes[$0] })
    }
```

Pass drive text into the row (in `hikeList`):

```swift
                    HikeRow(stored: stored,
                            driveText: driveTimes[stored.hike.slug]
                                .map { HikeListModel.driveTimeText(seconds: $0) })
```

Extend `reload()` so every existing trigger (appear, foreground, add-sheet dismiss) also refreshes travel times:

```swift
    private func reload() {
        hikes = store.listHikes()
        refreshTravelTimes()
    }

    /// Loads cached times for the active location and fetches any missing ones.
    /// Cancels an in-flight fill first so switching locations mid-fill is safe.
    private func refreshTravelTimes() {
        fillTask?.cancel()
        guard let active = locationStore.activeLocation else {
            activeLocationName = nil
            driveTimes = [:]
            return
        }
        activeLocationName = active.name
        driveTimes = travelTimeStore.driveSeconds(for: active.id)
        let pending = hikes.map(\.hike)
        fillTask = Task {
            let service = TravelTimeService(estimator: MapKitRouteEstimator(), store: travelTimeStore)
            await service.fill(hikes: pending, location: active) { slug, entry in
                driveTimes[slug] = entry.driveSeconds
            }
        }
    }
```

In the delete confirmation handler, purge the hike's cached times alongside the existing delete:

```swift
                Button("Delete", role: .destructive) {
                    if let target = pendingDelete {
                        try? store.delete(slug: target.hike.slug)
                        travelTimeStore.purgeHike(slug: target.hike.slug)
                    }
                    pendingDelete = nil
                    reload()
                }
```

Add the location menu to the toolbar — a leading item next to the existing trailing group:

```swift
                ToolbarItem(placement: .topBarLeading) {
                    locationMenu
                }
```

```swift
    private var locationMenu: some View {
        Menu {
            ForEach(locationStore.locations) { location in
                Button {
                    locationStore.setActive(id: location.id)
                    refreshTravelTimes()
                } label: {
                    if location.name == activeLocationName {
                        Label(location.name, systemImage: "checkmark")
                    } else {
                        Text(location.name)
                    }
                }
            }
            Divider()
            Button("Uredi lokacije…") { showingLocations = true }
        } label: {
            Label(activeLocationName ?? "Lokacije", systemImage: "house")
        }
    }
```

And present the manage sheet (next to the existing sheets):

```swift
            .sheet(isPresented: $showingLocations, onDismiss: refreshTravelTimes) {
                LocationsView(locationStore: locationStore,
                              travelTimeStore: travelTimeStore,
                              onChange: refreshTravelTimes)
            }
```

- [ ] **Step 3: Full verification (done-gate)**

```bash
cd HikeKit && swift test && cd ..
xcodebuild -project HribiVZepu.xcodeproj -scheme HribiVZepu \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath DerivedData build
xcrun simctl boot "iPhone 17" || true
open -a Simulator
xcrun simctl install booted DerivedData/Build/Products/Debug-iphonesimulator/HribiVZepu.app
xcrun simctl launch booted com.markos.hribivzepu
```

Manual checklist in the simulator (needs ≥2 saved hikes with coordinates):
1. Location menu (house icon, top-left) → "Uredi lokacije…" → add "Dom" via search (e.g. "Ljubljana"). It becomes active automatically.
2. Within a minute, rows grow a teal car segment with drive times; sort by Čas vožnje works.
3. Add a second location (e.g. "Bled") via map pin, activate it — times refetch for the new location.
4. Switch back to "Dom" — times appear instantly (cached, no refetch delay).
5. Force-quit and relaunch offline (Mac Wi-Fi off) — cached drive times still shown.
6. Delete a hike — app behaves normally; re-adding it fetches its time again.

- [ ] **Step 4: Commit**

```bash
git add App/HribiVZepuApp.swift App/HikeListView.swift
git commit -m "feat: drive times from active location in hike list"
```

---

## Self-Review Notes

- Spec coverage: stat parsing (T1), locations + active (T2), per-location cache with fetchedAt (T3), service with skip-cached/spacing/incremental-persist/retry (T4), sort/filter with missing-last semantics (T5), colored row incl. switch to "po poti" (T6), sort menu persistence + filter sheet with bounds/chips/badge/session-only filters (T7), three add methods + permission string + purge on location delete (T8), location menu, fill triggers (appear/foreground/add/switch), purge on hike delete, offline display (T9). Non-goals (refresh action, traffic estimates) correctly absent.
- Type consistency: `driveText` (T6→T9), `HikeRow(stored:driveText:)`, `fill(hikes:location:onEntry:)` (T4→T9), `driveSeconds(for:)` (T3→T9), `HikeListModel.driveTimeText(seconds:)` (T5→T7/T9) all match.
