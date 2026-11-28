# Issue 13 — Server discovery (LAN browse) — BUILDER report

Branch `fix/issue-13-server-discovery`, HEAD `1b4a21f`. Commits: `a919ee2`
(Kotlin channel + TXT tests), `cec7488` (Dart service + UI + invariant #58,
same commit per plan), `af28caa` (tests T1–T8 / W1–W6 / G1), `1b4a21f`
(Kotlin main-thread EventSink marshalling — device-found defect).

## SUMMARY
DNS-SD browse (`_http._tcp` + `_daap._tcp`) over an EventChannel
(`dev.educoder.owntone_sync/discovery`), decoded TXT filtered on
`mtd-version=`, deduped by (host, port), each candidate probe-verified
(GET-only) before it can be used. Candidate tap fills the Advanced field and
runs the existing probe; **no discovery path writes `setServerUrl`** — Save is
the only save site and goes through the invariant-37 `Different server?`
dialog (new invariant #58 pins this). Unconfigured Sync step is scan-primary
with manual entry demoted to the Advanced tile (invariants 41/44 order kept).

## GO/NO-GO CHECK
  What it was: plan §DEVICE D1/D2a/D3 on the night AVD + gates incl. Kotlin
  under JDK 17; pre-declared host rows D2/D4/D5/H1/H2.
  Did you run it:        YES
  What you observed: all three AVD legs witnessed with real rows; NSD
  multicast genuinely worked on `OwnToneSyncNight28_4_API_36` (real hp-server
  row surfaced), so D2/D4/D5/H1 upgraded from BLOCKED to AVD-witnessed. H2
  stands pre-declared (plan §DEVICE allows upgrade only for D2/D4/D5/H1).

## GATES (fresh on 1b4a21f, verbatim tails)
  flutter analyze:        `1 issue found.` — sole item baseline info
                          `queue_sheet.dart:160` deprecated_member_use. 0 errors, 0 warnings.
  flutter test:           `00:12 +203: All tests passed!` (178 base + 25 new)
  gradle :app:testDebugUnitTest (zulu-17): `BUILD SUCCESSFUL in 15s`;
                          `TEST-dev.educoder.owntone_sync.ServerDiscoveryTxtTest.xml`
                          `tests="5" skipped="0" failures="0" errors="0"`
  flutter build apk --debug: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`
  pubspec.yaml / pubspec.lock / AndroidManifest.xml byte-unchanged (`git diff --stat` empty for all three).
  Closing-keyword grep on every commit message before commit: silent.

## DEVICE — night AVD only (`OwnToneSyncNight28_4_API_36`, emulator-5554; identity confirmed via `ro.boot.qemu.avd_name`; Pixel 6 25071FDF600953 never touched; ESP32 serial never touched; server traffic GET-only, zero writes)

### OBSERVED — action → result (uiautomator content-desc dumps + run-as cat; screenshots under /tmp/owntone-night/)
  - D1 cold start (fresh app data): unconfigured Sync step renders
    `Server Not Configured`, `Scan for servers` (primary), `Enter address
    manually (advanced)`; 0 red pixels below appbar (PIL), `E/flutter` count 0.
  - D2a scan lifecycle: tap → `Scanning the network for OwnTone servers…` +
    `Stop scanning`; on stop → explicit outcome (`No OwnTone servers found`
    + `Scan again` on a genuinely empty window; never a stuck spinner).
  - D2 (upgraded): after the threading fix, scan returned the real deduped
    row `My Music on hp-server — 192.168.1.13:3689` — NSD multicast works on
    this AVD; logcat shows `NSD browsing` for both types, zero
    `ensureRunningOnMainThread` / `Failed to forward`.
  - D4 (upgraded): tapping the row filled the Advanced field
    (`text="http://192.168.1.13:3689"`) and probe verdict `Connected to
    192.168.1.13`; `FlutterSharedPreferences.xml` absent (run-as) before and
    after the tap — candidate tap saves nothing.
  - D3(i) manual refused: typed `http://127.0.0.1:9`, Test connection →
    `Can't reach 127.0.0.1 - is your server running?` (red verdict is the
    user-requested test — sanctioned non-goal per plan; no server traffic).
  - D3(ii) live verdict: typed `http://192.168.1.13:3689` → `Connected to
    192.168.1.13` (GET precondition before the step: `/api/now-playing` → 400).
  - D3(iii) save + order: Save → screen closed, prefs written
    (`flutter.server_url=http://192.168.1.13:3689`, run-as), Settings row
    live-updated, guided flow shows folder step (`Storage Permission
    Required`) — invariant-44 order holds.
  - D5 (upgraded): saved a divergent `http://10.0.0.1:3689` (via `Different
    server?` → `Keep library` — snackbar `Server address updated. Your
    library was kept.`); re-scan → tapped row `My Music on hp-server —
    192.168.1.13:3689` → `Connected to 192.168.1.13` → Save → `Different
    server?` with correct old→new body (`http://10.0.0.1:3689` to
    `http://192.168.1.13:3689`) → **Cancel** → stayed on screen, prefs still
    `http://10.0.0.1:3689`, no wipe, no `Error resetting data`.
  - H1 (upgraded): host-side `dns-sd -B _http._tcp` concurrent with the scan
    listed 12 instances (wled-dresser, Volumio Kitchen, red-lamp, wled-hall,
    wled-1354d3, wled-sink, bathroom_vent, My Music on hp-server,
    pet-feeder, powr316, Brother HL-L2405W, doorbell); the app rendered
    exactly 1 row — 11 unrelated devices filtered out.
  - Defect found and fixed on device: first build produced zero rows despite
    clean browsing — NsdManager delivers `onServiceResolved` on its own
    HandlerThread and every `EventSink.success` threw
    `FlutterJNI.ensureRunningOnMainThread`. Fixed by marshalling emissions to
    the main looper (`1b4a21f`); rebuilt APK shows rows + zero such log lines.

### NOT VERIFIED — implemented but not exercised
  - `Stop scanning` mid-browse beyond the brief window above (dedupe reset on
    re-browse tested only as W-unit).
  - Concurrent duplicate resolve events (dedupe covered by T3/W2, not device).
  - API < 30 fallback (no such device; see ASSUMPTIONS).
  - Scan error state (Kotlin `onDiscoveryStopped`/unavailable) — never
    induced; W5/W6 cover the Dart half only.
  - Long-scan (>60 s) stale-entry expiry behaviour on device.
  - Physical phone behaviour (harness was an emulator; H2 row covers this).

### DEVIATIONS
  - Kotlin: real android.jar has **no** `getTxtRecords()` and no string
    `attributes` (plan sketched them). TXT source became
    `getAttributes(): Map<String, byte[]>` (API 30+); IPv4 via
    `getHostAddresses()` (API 33+) not `getAddresses()`; `serviceName` not
    `instanceName`; `onServiceFound(NsdServiceInfo)` single-arg. On API 27–29
    TXT is unobtainable → such services fail the `mtd-version` filter and
    manual entry remains the documented fallback.
  - Added `@visibleForTesting probeOverride` / `sourceFactory` / `probe`
    seams (plan W-suite implies injectability; production defaults unchanged).
  - `ExpansibleController` instead of the deprecated `ExpansionTileController`
    (host Flutter 3.41.7-era CI pin vs 3.47.9 local; deprecation warning would
    have broken the 0-warning gate).
  - `screen_smoke_test.dart` adjusted to open the Advanced tile — mandated by
    the plan's new layout, not a loosening (assertions unchanged).
  - Invariant #58 shipped in the code commit (`cec7488`) as the plan required.

### UNKNOWN
  - An intermediate working note claimed "Save persisted" before the Save tap
    had actually been dispatched; the real witness came later (prefs cat +
    folder step, dumps `h3/h4`). Recorded so nobody re-derives it.
  - One earlier "No OwnTone servers found" witness was taken on the
    pre-threading-fix build (rows were silently dropped); the post-fix genuine
    row witness supersedes it. Empty state itself was still a correct render.
  - `dns-sd` second run showed 0 Adds (mDNS cache TTL); the first run's
    12-instance listing is the H1 witness.
  - Harness notes (emulator-only, app untouched): uiautomator taps hit an
    open IME's window (dismiss via conditional `dumpsys input_method`
    check); left-edge swipe at x≤5 triggers system back; TalkBack semantics
    were enabled and POST_NOTIFICATIONS granted **to TalkBack only** so
    content-desc dumps and notification popups behaved.

### ASSUMPTIONS
  - Kotlin API deviations: `getAttributes()` (API 30+) for TXT,
    `getHostAddresses()` (API 33+) for IPv4, `serviceName`; on API 27–29
    TXT is unobtainable → manual-entry fallback (recorded also under
    DEVIATIONS).
  - `@visibleForTesting` probe/source seams added for the injected fakes.
  - `ExpansibleController`-family usage chosen to satisfy the deprecation
    gate.
  - The existing smoke test was opened the Advanced tile per the mandated
    layout (test adaptation, behaviour under test unchanged).
  - Harness: TalkBack semantics enabled; notification grant given to
    TalkBack only; IME-occlusion tap lesson recorded.
  - The first D2a empty-state witness was from the pre-fix build
    (superseded by the post-fix witnessed rows).

### RESOLVED FINDINGS
  (empty — until review rounds)

### BUILD
  flutter analyze: 0 errors / 0 warnings (1 baseline info, `queue_sheet.dart:160`).
  flutter build apk --debug: succeeded (final HEAD).
