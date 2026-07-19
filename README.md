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

## Trying the app in the iPhone simulator

Easiest: open `HribiVZepu.xcodeproj` in Xcode, select the `HribiVZepu` scheme with an iPhone
simulator as the destination, and press Run. No signing needed for the simulator.

Or from the terminal:

```sh
xcodegen generate
xcodebuild -project HribiVZepu.xcodeproj -scheme HribiVZepu \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath DerivedData build
xcrun simctl boot "iPhone 17" || true       # no-op if already booted
open -a Simulator
xcrun simctl install booted DerivedData/Build/Products/Debug-iphonesimulator/HribiVZepu.app
xcrun simctl launch booted com.markos.hribivzepu
```

(`xcrun simctl list devices available` shows other installed simulators if you prefer a
different one.)

To exercise the full flow, tap **+** in the app and paste a hike link, e.g.
`https://www.hribi.net/izlet/zadnjica_pogacnikov_dom_na_kriskih_podih/1/164/268` — you can
copy it in the simulator via *Edit → Paste* after copying on the Mac (clipboard is shared).
Then try airplane-mode reading: quit the network (Simulator has no airplane mode — just turn
off the Mac's Wi-Fi) and reopen the saved hike. The share-sheet flow needs Safari: open the
hike page in the simulator's Safari, tap Share → **Hribi v žepu**.

Saved hikes persist across app reinstalls in the simulator, and each simulator device keeps
its own storage.

## Installing on your iPhone

1. Open `HribiVZepu.xcodeproj` in Xcode, select the `HribiVZepu` scheme.
2. In *Signing & Capabilities* (both targets), pick your personal team (free Apple ID works).
   If bundle or group IDs collide, change `com.markos.hribivzepu` / `group.com.markos.hribivzepu`
   in `project.yml` and regenerate.
3. Connect the iPhone, enable Developer Mode (Settings → Privacy & Security), select it as the
   run destination, and press Run.
4. Free-account caveat: the install expires after 7 days — reconnect and Run again.
   Your saved hikes survive reinstalls.

## TestFlight refresh (with a paid developer account)

Version and build numbers are defined once in `project.yml` (`MARKETING_VERSION`,
`CURRENT_PROJECT_VERSION`); both targets inherit them, which the App Store Connect
uploader requires. TestFlight builds expire after 90 days, so roughly quarterly:

1. `./scripts/bump-build.sh` — increments the build number and regenerates the project.
   No code changes needed; the version string can stay `1.0` forever.
2. Commit the `project.yml` change.
3. In Xcode: select **Any iOS Device (arm64)** as destination → **Product → Archive** →
   **Distribute App → TestFlight & App Store** (or "TestFlight Internal Only") → Upload.
4. Internal testers get the update automatically in the TestFlight app — no review,
   and the 90-day clock restarts.

One-time setup for a new tester (e.g. family member with their own Apple ID):
App Store Connect → Users and Access → add them (any role) → in the app's TestFlight
tab, add them to an internal testing group. They install via the TestFlight app.

## Adding a hike

- In Safari, open a hike on hribi.net → Share → **Hribi v žepu**, or
- in the app, tap **+** and paste the hike link.
