# Hribi v žepu — Design Spec

**Date:** 2026-07-18
**Status:** Approved by user (brainstorming session)

## Purpose

A personal iOS app that downloads hike pages from [hribi.net](https://www.hribi.net) for offline use. hribi.net hosts detailed hike descriptions for Slovenia — including route photos that help with path-finding — but the site is unusable without an internet connection, which is often missing in the mountains.

The user provides a link to a hike (e.g. `https://www.hribi.net/izlet/zadnjica_pogacnikov_dom_na_kriskih_podih/1/164/268`); the app downloads all its content including full-size images, splits it into logically separate sections, and presents it in a clean native reading UI. The user can delete hikes and see how much storage each one uses.

Personal use only: installed on the user's own iPhone via Xcode (free Apple ID signing to start; 7-day provisioning limit accepted, upgradeable to a paid account later without data loss).

## Requirements

1. Add a hike two ways: **Share sheet** from Safari ("Share → Hribi v žepu") and **paste URL** inside the app.
2. Download the full hike content for offline use: metadata, all text sections, all route photos at full resolution, and the user comments/discussion thread.
3. Present content with sections separated (getting there vs. the route itself vs. sights, etc.).
4. "Navigate to trailhead" button using the hike's parsed coordinates, formatted so Google Maps recognizes it; Apple Maps fallback. (Navigation itself requires connectivity — that is fine.)
5. Manage hikes: delete (with confirmation), show per-hike size on disk and total storage used.
6. Refresh a saved hike (re-download in place — picks up new comments/photos).

Out of scope (YAGNI): GPX tracks, offline maps, hike search/browse, accounts, iPad/Mac targets, App Store distribution.

## Architecture

- **SwiftUI app**, minimum iOS 26 (the target iPhone runs current iOS), two targets:
  - `HribiVZepu` — main app
  - `ShareExtension` — share-sheet extension that accepts URLs
- **App Group container** shared by both targets so hikes saved from the share sheet appear in the app immediately.
- **SwiftSoup** (via Swift Package Manager) for HTML parsing.
- No backend, no database, no accounts. Everything on-device.

### Components

| Component | Responsibility |
|---|---|
| `HikeStore` | Folder-per-hike storage: list, load, atomic save, delete, size accounting |
| `HikeDownloader` | Fetch page + images with progress reporting; temp-folder staging |
| `HikeParser` | HTML → structured `Hike` model (SwiftSoup) |
| Main app UI | Hike list, add sheet, hike detail, photo viewer |
| Share extension UI | Receive URL, run downloader with progress, report result |

## Storage

One self-contained folder per hike inside the App Group container:

```
Hikes/
  <hike-slug>/
    hike.json      ← parsed structured content (metadata, sections, image manifest)
    page.html      ← raw original page (~230 KB) — insurance; allows re-parsing
                     after parser improvements without re-downloading
    images/        ← full-size photos (~100 KB each, ~40–50 per typical hike)
```

- Hike identity = URL slug (the `izlet/<slug>/...` path segment). Adding an already-saved hike offers **Refresh** instead of duplicating.
- Per-hike size = folder size; total = sum. Delete = remove folder. List = folder scan (sorted by date added, from folder creation date stored in `hike.json`).
- Downloads write to a temporary staging folder and are moved into place atomically on completion. A failed download leaves no partial hike; a refresh that fails leaves the old version intact.

## Downloading & Parsing

Input validation: URL must match `hribi.net/izlet/...`; anything else is rejected with a clear message.

Parsed from the page (labels are consistent bold text on the site):

- **Title** (`<h1>`) — parse failure here aborts with "couldn't parse this page".
- **Metadata fields:** Izhodišče (start), Širina/Dolžina (coordinates), Cilj (destination), Čas hoje (walking time), Dolžina poti (length), Zahtevnost (difficulty), Višinska razlika (elevation gain), Višinska razlika po poti, Priporočena oprema — poletje/zima. All optional; missing fields simply don't render.
- **Sections**, stored separately: Dostop do izhodišča, Opis poti, Ob poti, Izlet lahko podaljšamo do naslednjih ciljev, Priporočamo, and the comments/discussion thread. Unrecognized labeled blocks are preserved under an "Other" section, never silently dropped.
- **Coordinates:** parsed from Širina/Dolžina into decimal lat/lon.
- **Images:** all `slike1/*.th.jpg` thumbnails found in the content; full-size URL = thumbnail URL with `.th` stripped (verified against the live site). Downloaded in page order.

Text keeps basic formatting (paragraphs, emphasis, links) rendered natively.

## UI

**Hike list (home).** Rows: name, key stats (time, difficulty, elevation gain), size on disk. Footer: total storage used. Swipe-to-delete with confirmation. **+** opens the add sheet.

**Add sheet.** URL field, auto-filled from clipboard when it contains a hribi.net link. Download button with progress ("page… photo 12 of 43…"). Errors shown inline.

**Hike detail.** Metadata card on top; **Navigate to trailhead** button when coordinates exist — opens `https://www.google.com/maps/dir/?api=1&destination=<lat>,<lon>` (opens the Google Maps app when installed), with an Apple Maps option as fallback. Sections below as independently expandable groups; comments at the bottom. Photos inline where they belong, tappable into a full-screen pager with pinch-to-zoom. Toolbar menu: Refresh, Open original in Safari, Delete.

**Share extension.** Validates the shared URL, downloads with progress, reports success or a clear error (e.g. offline). No pending-queue: on failure the user simply retries later.

## Error Handling

| Failure | Behavior |
|---|---|
| Invalid / non-hike URL | Rejected with clear message |
| Network loss mid-download | Nothing saved (staging folder discarded); "retry when online" |
| Some photos fail, page ok | Hike saved, marked e.g. "38 of 43 photos"; Refresh fetches stragglers |
| Page markup unrecognizable | Explicit "couldn't parse this page" error, nothing saved |
| Duplicate URL | Offer Refresh instead of re-adding |
| Refresh fails | Existing saved version untouched |

## Testing

All automated tests run on the **local iOS simulator** via `xcodebuild test` (the iOS simulator runtime must be downloaded during project setup — Xcode 26.6 is installed but currently has no simulator runtimes). **Definition of done: the full suite passes in the simulator.**

- **Parser unit tests** against saved fixture HTML: the Zadnjica–Pogačnikov dom page plus 1–2 structurally different hikes (easy valley walk, via ferrata) to catch layout variation. This is the fragile part — the parser is coupled to hribi.net's markup; a site redesign breaks new downloads (not saved hikes) until the parser is updated, and `page.html` backups allow offline re-parsing after a fix.
- **HikeStore unit tests:** atomic save, delete, size calculation, duplicate detection.
- **Live end-to-end test (in simulator):** downloads a real hike from hribi.net through the full `HikeDownloader` → `HikeParser` → `HikeStore` pipeline and asserts the result — title parsed, expected sections present, coordinates parsed, all images downloaded and non-empty, size accounting correct. This test hits the network by design (it validates against the live site); it fails if hribi.net is unreachable, which is acceptable for a personal project. To avoid hammering hribi.net it is skipped unless `RUN_LIVE_TESTS=1` is set — routine test runs use only committed fixtures; the done-gate (and deliberate fetch-debugging runs) enable it explicitly.
- **Manual on-device verification** (the parts automation can't cover well): share extension flow, Google Maps handoff, offline reading (airplane mode).
