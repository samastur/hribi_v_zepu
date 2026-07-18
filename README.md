# Hribi v žepu

Personal iOS app that saves hikes from [hribi.net](https://www.hribi.net) for offline reading —
description, metadata, photos, and comments — with per-hike storage accounting.

## Development

- Xcode project is generated: `xcodegen generate` (config in `project.yml`).
- All logic lives in the `HikeKit` local Swift package.
- Fast tests during development: `cd HikeKit && swift test` (runs on macOS, fixtures only — never touches hribi.net).
- The done-gate: `cd HikeKit && TEST_RUNNER_RUN_LIVE_TESTS=1 xcodebuild test -scheme HikeKit -destination 'platform=iOS Simulator,name=iPhone 17'`
  — includes a live end-to-end test that downloads a real hike from hribi.net (needs network;
  gated behind `RUN_LIVE_TESTS=1` to avoid hammering the site).

## Installing on your iPhone

1. Open `HribiVZepu.xcodeproj` in Xcode, select the `HribiVZepu` scheme.
2. In *Signing & Capabilities* (both targets), pick your personal team (free Apple ID works).
   If bundle or group IDs collide, change `com.markos.hribivzepu` / `group.com.markos.hribivzepu`
   in `project.yml` and regenerate.
3. Connect the iPhone, enable Developer Mode (Settings → Privacy & Security), select it as the
   run destination, and press Run.
4. Free-account caveat: the install expires after 7 days — reconnect and Run again.
   Your saved hikes survive reinstalls.

## Adding a hike

- In Safari, open a hike on hribi.net → Share → **Hribi v žepu**, or
- in the app, tap **+** and paste the hike link.
