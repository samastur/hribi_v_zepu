# Hribi v žepu

Personal iOS app that saves hikes from [hribi.net](https://www.hribi.net) for offline reading —
description, metadata, photos, and comments — with per-hike storage accounting.

## Development

- Xcode project is generated: `xcodegen generate` (config in `project.yml`; build settings
  shared by every target in `Config/Shared.xcconfig`).
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
xcrun simctl launch booted net.gaivo.HribiVZepu
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

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and put your Apple team ID
   in it (Xcode → Settings → Accounts). The file is gitignored and the project picks it up on
   the next `xcodegen generate`. Nothing else in the repository names a team.
   If bundle or group IDs collide, change `net.gaivo.HribiVZepu` / `group.net.gaivo.HribiVZepu`
   in `project.yml`, the entitlements files and `HikeStore.appGroupID`, and regenerate.
2. Open `HribiVZepu.xcodeproj` in Xcode and select the `HribiVZepu` scheme.
3. Connect the iPhone, enable Developer Mode (Settings → Privacy & Security), select it as the
   run destination, and press Run.
4. Free-account caveat: the install expires after 7 days — reconnect and Run again.
   Your saved hikes survive reinstalls.

## TestFlight (with a paid developer account)

`scripts/testflight` archives a Release build, signs it for App Store distribution and uploads
it to App Store Connect. The build number is the UTC time of the build, such as
`202610281030`, so each upload is higher than the last with nothing to bump or commit.
`MARKETING_VERSION` in `Config/Shared.xcconfig` can stay `1.0` forever. Because the number is
a timestamp, upload through the script rather than Xcode's Archive, which would use the
`CURRENT_PROJECT_VERSION` of `1` and be rejected as lower.

Once per Apple account:

1. Set up `Config/Local.xcconfig` as above and sign in to your Apple account in Xcode →
   Settings → Accounts. With `-allowProvisioningUpdates`, Xcode registers the identifiers and
   app group and makes the distribution certificate and profiles.
2. In [App Store Connect](https://appstoreconnect.apple.com), add a new iOS app with the
   bundle identifier `net.gaivo.HribiVZepu`. Apple offers no way to do this from the command line.

Then `scripts/testflight` from `main`. The archive is built unsigned (a fresh CI runner has no
development certificate), each bundle is signed locally with its entitlements (a signature that
needs no certificate), and the export signs it with Apple's cloud-managed distribution
certificate while keeping those entitlements, so the app group shared by the app and the share
extension survives. Processing takes a few minutes; then internal testers get the build in the
TestFlight app without review.

One-time setup for a new tester (e.g. family member with their own Apple ID):
App Store Connect → Users and Access → add them (any role) → in the app's TestFlight
tab, add them to an internal testing group. They install via the TestFlight app.

### Every month, without anyone

TestFlight builds expire after 90 days. `.github/workflows/testflight.yml` runs
`scripts/testflight` on the first of each month at 06:00 UTC, so testers always have a build
well inside its 90 days and get what was merged since. It can also be started by hand from the
Actions tab. It builds `main` as it is, without running the tests, so keep `main` green.

It signs with an App Store Connect API key instead of an Xcode login. Set up once, in the
repository's Settings → Secrets and variables → Actions:

| Kind | Name | Value |
|---|---|---|
| Variable | `DEVELOPMENT_TEAM` | As in `Local.xcconfig` |
| Secret | `ASC_KEY_ID` | The key's ID |
| Secret | `ASC_ISSUER_ID` | The issuer ID above the list of keys |
| Secret | `ASC_KEY` | The whole `.p8` file |

Make the key in App Store Connect → Users and Access → Integrations → App Store Connect API,
as a team key with the Admin role: only Admin may use the cloud-managed distribution
certificate. Apple lets you download the `.p8` once. API keys do not expire, and the cloud
certificate is renewed by Apple, so nothing here needs a yearly turn. The same team key serves
every app in the team.

Without `DEVELOPMENT_TEAM` the job is skipped, so forks are not bothered by it. GitHub silently
disables scheduled workflows in a public repository after 60 days with no activity; the last
step enables the workflow again on every run, which restarts that count. When a scheduled run
fails, GitHub emails whoever last changed its schedule.

## Adding a hike

- In Safari, open a hike on hribi.net → Share → **Hribi v žepu**, or
- in the app, tap **+** and paste the hike link.
