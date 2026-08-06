# Travel time, sorting & filtering — design

**Date:** 2026-08-05
**Status:** Approved

## Goal

Two additions to Hribi v žepu:

1. **Drive time to trailhead.** The user saves one or more named start locations
   (home, weekend house, …), marks one active, and every hike in the list shows the
   estimated car travel time from the active location to the hike's trailhead
   (the coordinate already parsed from hribi.net's Širina/Dolžina field).
2. **Sorting and filtering** of the hike list on Čas hoje (walking time),
   Zahtevnost (difficulty), Višinska razlika po poti (route elevation gain), and
   drive time — with each stat shown in its own high-contrast color in the list row.

Routing uses Apple MapKit (`MKDirections`, `.automobile`) — free, on-device API,
no keys or billing. Google Routes API was considered and rejected for setup cost;
a future switch remains possible behind the `RouteEstimator` protocol.

## Non-goals (future work, deliberately excluded)

- Manual "refresh travel times" action.
- Distinguishing typical vs. current-traffic estimates. The cache schema stores
  `fetchedAt` per entry so both features can be added without migration.
- Showing drive times from more than one location at once.

## Data model & storage (HikeKit)

New types, persisted in the app group container alongside the existing hike storage:

- **`SavedLocation`** — `id: UUID`, `name: String`, `latitude: Double`,
  `longitude: Double`.
- **`LocationStore`** — owns `locations.json`:
  `{ locations: [SavedLocation], activeLocationID: UUID? }`.
  Operations: list, add, delete, set active. Deleting the active location clears
  the active ID (no drive times shown until another is activated).
- **`TravelTimeStore`** — owns `traveltimes.json`:
  `locationID (UUID string) → [hikeSlug → { driveSeconds: Int, fetchedAt: Date }]`.
  Entries are kept per location so switching back to a previously used location is
  instant with no refetching. Deleting a location purges its dictionary; deleting a
  hike purges that slug from every location.

The stored `Hike` JSON is **unchanged** — no migration; existing saved hikes work as-is.

## Derived hike stats (HikeKit, pure functions)

Extension on `Hike`:

- `walkingMinutes: Int?` — parses "Čas hoje" values: `"4 h"`, `"3 h 30 min"`,
  `"45 min"` (decimal comma tolerated, e.g. `"4,5 h"`).
- `routeElevationMeters: Int?` — parses "Višinska razlika po poti", e.g. `"1410 m"`,
  tolerant of thousands separators (`"1.410 m"`).
- `difficultyRank: Int?` and `difficultyText: String?` — maps "Zahtevnost" onto a
  fixed easy→hard order: severity (lahka < zahtevna < zelo zahtevna) within each
  path type, path types ordered označena pot < brezpotje < plezalna pot.
  Unrecognized values get no rank (sort last) but keep their text for filtering.

Any unparseable or absent value returns `nil`; the UI omits that stat.

## Travel time service (HikeKit)

- **`RouteEstimator` protocol** — `driveTime(from: Coordinate, to: Coordinate) async throws -> TimeInterval`.
  Production adapter wraps `MKDirections` (`.automobile`, single route, expected
  travel time). Tests use a fake.
- **`TravelTimeService`** — triggered when a location becomes active, when a hike is
  added, and on app launch/foreground. It iterates all stored hikes that have a
  coordinate, skips slugs already cached for the active location, and fetches the
  rest **sequentially with ~1 s spacing** (MapKit throttling courtesy). Each result
  is persisted immediately so partial progress survives app termination.
- **Failures** (no route, network error): entry stays uncached; retried on the next
  trigger. Offline, cached values display normally.
- Hikes without a coordinate never get a drive time.

## List view

### Row

The current single secondary-colored stat line becomes individually colored segments:

| Stat | Source | Color role |
|------|--------|-----------|
| Čas hoje | metadata | blue |
| Zahtevnost | metadata | orange |
| Višinska razlika po poti | metadata (replaces plain "Višinska razlika" shown today) | purple |
| Drive time | cache, with `car` SF Symbol | teal |

Colors are asset-catalog colors with explicit light- and dark-mode variants; exact
values chosen during implementation for good contrast against both list backgrounds
(target ≥ 4.5:1). A stat is omitted when its value is missing.

### Toolbar

- **Sort menu** — Date added (default, newest first), Čas hoje, Zahtevnost,
  Višinska razlika po poti, Čas vožnje. Selecting the active key again toggles
  ascending/descending. Choice persists across launches (`@AppStorage`).
- **Filter button** — opens the filter sheet; shows a badge while any filter is active.
  Filters reset on app relaunch.
- **Location menu** — lists saved locations (checkmark on the active one, tap to
  switch) plus "Manage locations…".

### Filter sheet

- **Čas hoje** and **Višinska razlika po poti**: range sliders whose bounds are the
  min/max of the values present across saved hikes.
- **Zahtevnost**: multi-select chips of the difficulty values actually present.
- Hikes missing a filtered field are **never excluded** by that filter, and hikes
  missing the active sort field sort to the end. Nothing silently disappears.

## Locations management

Sheet reachable from the location menu:

- List of saved locations — tap to activate, swipe to delete.
- Add flow with three entry methods, each saved under a user-typed name:
  1. Address/place search via `MKLocalSearch`.
  2. "Use current location" — one-shot CoreLocation fix; requires when-in-use
     permission (`NSLocationWhenInUseUsageDescription` added to Info.plist).
  3. Drop a pin on a `Map`.

Activating a location (including a freshly added one) triggers the travel time
service for all hikes not yet cached under it.

## Error handling summary

| Condition | Behavior |
|-----------|----------|
| Hike has no coordinate | No drive time shown; sorts to end on Čas vožnje |
| Route fetch fails / offline | Entry left uncached, retried next trigger; cached values still shown |
| Metadata missing/unparseable | Stat omitted; sorts to end; not excluded by filters |
| Location permission denied | "Use current location" shows an inline hint; other add methods unaffected |
| Active location deleted | Active cleared; drive times hidden until another activated |

## Testing

Unit tests (fixtures/fakes only, no network — consistent with existing test setup):

- Stat parsing variants for all three metadata fields, including malformed input.
- Difficulty ordering table.
- Sort/filter logic (missing-value placement, range bounds, difficulty chips).
- `LocationStore` and `TravelTimeStore` round-trips, purge-on-delete behavior.
- `TravelTimeService` with a fake estimator: skips cached, fetches missing,
  persists incrementally, retries failures on next trigger.

MapKit itself is not exercised by tests; UI verified manually in the simulator.
