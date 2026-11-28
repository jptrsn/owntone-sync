# Issue #12 — red "server unreachable" surfaces behind a user-request gate — builder report

Run 2026-11-28, unit 3. Branch `fix/issue-12-unreachable-warning-gate` off
`develop@b443406`. Spec copy `.ai-dlc/night-2026-11-28/issues/12.md`, plan
`.ai-dlc/night-2026-11-28/plans/12.md` (implemented as written; deviations
below). Builder spawn #1. Commits: `7769b7d` (code + invariants), `6a1f080`
(tests), report commit follows.

```
PHASE: COMPLETE

GO/NO-GO CHECK
  What it was: the issue's DoD witnessed on this run's night AVD — a cold
    boot whose only fetch is the unrequested startup probe renders NONE of
    the four red surfaces while the failure-classification log line still
    fires (D1); a user-initiated fetch against the same refusing endpoint
    renders all four (D2); a same-host URL edit re-silences everything (D3);
    home Retry re-fires a real fetch and keeps surfaces visible (D4/i); a
    reachable real server cold-boots clean with "Fetched 13 playlists" (D4/ii);
    an unroutable host cold-boots silent whatever the classifier says (D5) —
    plus the T1-T8/W1-W4b unit matrix pinning the gate semantics.
  Did you run it:        YES (all five rows on OwnToneSyncNight28_3_API_36;
    rows H1/H2 are pre-declared BLOCKED-PENDING-HOST-VERIFICATION per run.md,
    never attempted — substitute proofs named in ASSUMPTIONS).
  What you observed:     every row as planned. Key verbatim rows in OBSERVED.
    E/flutter = 0 at every capture. AVD deleted after the pass.

SUMMARY
  Implemented as planned: a derived, never-persisted bool
  `_unreachableWarningVisible` on SyncProvider, written ONLY at the two
  fenced fetchPlaylists sites (failure leg sets it
  `userInitiated && classified == unreachable`; success leg clears it) and
  cleared by setServerUrl; the four read sites — library_screen banner
  (:275 area), library_screen app-bar badge (:368 area, gate-off falls back
  to the neutral cloud_outlined render), app_drawer "Server not responding"
  (:82-83) and sync_screen _buildStateBanner unreachable case (:62) — AND the
  gate; the three user-action fetch call sites (banner Retry
  library_screen.dart:305, Load Playlists sync_screen.dart:259, pull-to-
  refresh sync_screen.dart:408) pass fetchPlaylists(userInitiated: true);
  the startup probe at sync_provider.dart:178 keeps the default false.
  ConnectivityState state machine, the errno classifier, the in-flight
  worker guard and shouldBlockManualSync are untouched — connectivityState
  stays the sole, UNGATED input to shouldBlockManualSync (invariant 43).
  Invariant 41 amended (user-request gate sentence) + new entry 57 in the
  SAME commit as the code, index line updated.
  Tests: +14 (baseline 164 -> 178). T1-T8 in
  test/sync_provider_connectivity_test.dart (gate matrix: userInitiated x
  unreachable/offline/succeeded x persistence-across-unrequested-probe,
  citing invariants 39/40/41/43); new file test/unreachable_warning_gate_test.dart
  (seed + W1-W4b: banner/badge/drawer/sync-banner across gate on/off,
  neutral-fallback, empty-list legs) on the helpers pattern, zero new
  dependencies, no network, no AudioService.init.

GATES (verbatim tails)
  flutter analyze:
    info • 'onReorder' is deprecated and shouldn't be used. Use the
    onReorderItem callback instead. ... queue_sheet.dart:160:27 •
    deprecated_member_use
    1 issue found. (ran in 3.4s)
    -> 0 errors / 0 warnings; the sole issue is the accepted baseline info.
  flutter test:
    00:12 +178: All tests passed!
  flutter build apk --debug:
    Running Gradle task 'assembleDebug'...                           1,643ms
    ✓ Built build/app/outputs/flutter-apk/app-debug.apk
  Kotlin gate: N/A — git diff b443406..HEAD touches no android/ path.
  Tool churn: post-gate `git status --short` = pre-existing untracked
  .ai-dlc/ + .opencode/ only; analysis_options.yaml and
  android/gradle.properties diff-empty.
  Versions: host Flutter 3.47.9; CI pin 3.41.7 untouched; pubspec untouched.

OBSERVED — things I did and saw, on the AVD (OwnToneSyncNight28_3_API_36,
android-36 google_apis arm64, pixel_6 profile, headless swiftshader;
instrumented via uiautomator dump + screencap + logcat after `am start` —
no VM service on am-start launches, sanctioned fallback harness per run.md).
  Server posture: host-side = exactly 2 GETs of
  /api/library/playlists?limit=1000 (200, total=13) — run start and before
  the D4(ii) device step. App-side = its own GET fetches (logcat
  "Fetched 13 playlists from server"). Zero PUT/POST from anyone. No
  playback, no "Sync now" tap, ever.
  Device posture: only emulator-5554 addressed; Pixel 6 (25071FDF600953)
  never addressed (present in `adb devices` only); ESP32 harness untouched.

  D1 (cold boot, unrequested probe, refusing endpoint http://127.0.0.1:9):
    URL saved via drawer→Server→field→Save; `am force-stop` + `am start`.
    Home + drawer dumps contain no "Can't reach", no "Server not
    responding", no red badge desc; app-bar desc = 'Sync'. logcat carries the
    classifier line "... SocketException: Connection refused ..., errno = 111
    ... (state: ConnectivityState.unreachable)" from the launch probe —
    classification fires, presentation stays silent. E/flutter=0.
    Artifacts /tmp/owntone-night/d0.png, d1_home.xml, d1_drawer.xml/png.
  D2 (user request, same refusing endpoint):
    app-bar icon → Sync → Load Playlists. Sync screen banner:
    "Can't reach 127.0.0.1 - is your server running?" [158,1441][985,1494].
    Back → home: same banner [105,312][891,364] + 'Retry' [912,275][1080,401]
    + badge content-desc = the sentence. Drawer: 'Server not responding'.
    2x (state: ConnectivityState.unreachable) lines; E/flutter=0.
    First-run precondition (disclosed): READ_MEDIA_AUDIO pm grant + SAF
    Music-folder pick via scripted DocumentsUI (run.md-authorized), done on
    this throwaway AVD only. POST_NOTIFICATIONS never requested (dumpsys
    grants=false). Artifacts d2_sync_gatedon.png, d2_home.png/xml,
    d2_drawer.xml/png.
  D3 (URL :9 → :10, host unchanged):
    Save → snackbar "Server address updated." → home. All four surfaces
    silent (badge desc 'Sync', drawer shows '127.0.0.1:10', no
    "Server not responding", no banner). Banner band (y 270-470) sampled red
    pixel count = 0. E/flutter=0. d3_home_silent.png.
  D4/i (gate armed, then home Retry):
    URL back to :9, Load Playlists to arm the gate, `logcat -c`, tap home
    Retry → all four surfaces persist AND exactly one NEW
    (state: ConnectivityState.unreachable) line appears post-clear — Retry
    fires a real user-initiated fetch, not a repaint. Band red count 155 vs
    0 on the silent baseline (same sampler). d4_home_gatedon.png.
  D4/ii (real server http://192.168.1.13:3689, cold start):
    logcat: "Fetched 13 playlists from server", zero (state:) failure lines.
    Home silent: no red text anywhere, badge desc 'Sync', band red = 0.
    Badge-glyph differential: crop (943,139)-(1070,265) differs from the
    cloud_outlined baseline capture by 1152 px and from the cloud_off+red-dot
    capture by 1765 px — a third glyph, consistent with cloud_done
    (differential witness; not glyph-template-matched, see ASSUMPTIONS).
    Prefs target-verified via run-as FlutterSharedPreferences.xml =
    http://192.168.1.13:3689. E/flutter=0. d4_home_reachable.png.
  D5 (unroutable host http://10.255.255.1:3689, cold start):
    logcat: "Failed to fetch playlists: DioException [connection timeout]:
    ... longer than 0:00:10.000000 ... (state: ConnectivityState.unreachable)"
    — the V3-anticipated emulator substitute (blackhole → timeout →
    unreachable instead of errno-113 → offline). Home AND drawer silent
    regardless of the classified label; E/flutter=0. This is the strongest
    form of the claim: presentation is silent even when the classifier says
    unreachable, provided nobody asked. d5_home.png, d5_drawer.xml.
  Teardown: `adb emu kill` + avdmanager delete avd → avdmanager list
  OwnToneSyncNight28_3 count = 0; `adb devices` shows only the (untouched)
  Pixel 6.

DEVIATIONS — anything not done as the plan specified
  1. W4 split into W4 + W4b (14 new tests, not the planned 12): the plan's
     single W4 "empty list" leg is not reachable in one provider —
     setServerUrl performs no list mutation (no write to the in-memory
     playlists in sync_provider.dart), so the "just saved, nothing cached"
     honesty scenario needs a FRESH provider. W4 keeps the cached-list leg;
     W4b adds the fresh-provider leg. Same invariants cited, both legs
     witnessed.
  2. D2 precondition: the storage-permission view had to be cleared first
     (READ_MEDIA_AUDIO + SAF folder) — the plan's D2 steps did not anticipate
     first-run UI on a virgin AVD. run.md-authorized scripted flow; product
     unaffected.
  3. Invariant-37 "Different server?" dialog: appeared on the two HOST-
     changing saves (:9→:3689, :3689→10.255.255.1) — the plan's procedure did
     not mention it. Took "Keep library" (invariant-37 default; nothing had
     ever been synced on this AVD, so keep-vs-reset is equivalent here). The
     dialog is adjacent behaviour, not the change under test; no defect
     observed in it.
  4. Harness hardening (no product change): one Save tap missed with the IME
     open and did not persist (prefs read proved it before any assertion was
     made). Procedure hardened to: hide keyboard (keyevent 111) → dump-verify
     field text → tap Save → run-as prefs read as the save witness.

UNKNOWN — behaviour you could not explain
  (none — the two initially-surprising readings were both explained: the
  :3689 save persisting as :9 = missed tap with IME up, verified via run-as;
  the "address = 127.0.0.1, port = 42338" text in a refused line while prefs
  still held :9 = invariant 39's documented unreliable SocketException
  address/port text, which is precisely why target evidence is the run-as
  prefs read, never the message string.)

RESOLVED FINDINGS
  (none — builder pass 1; no review round has run yet)

ASSUMPTIONS
  A1-A6 from the validated plan accepted as written (gate assignment
  semantics from the issue's AC matrix; suppression elsewhere untouched;
  background worker never writes the gate; gate-off badge = the neutral
  offline render; drawer reads via the provider getter; AC9 evidence =
  diff-scope + green suite + review, not a fabricated prompt-timing test).
  Additional assumptions I made and relied on:
  - SocketException address/port message text is unreliable (invariant 39)
    and was NEVER used as evidence of which host was contacted; the target of
    every fetch row is witnessed by the run-as prefs file + the logcat
    outcome shape.
  - cloud_done glyph identity is a differential witness (badge-crop pixel
    diff vs the two known other glyphs + absence of the red dot + the
    "Fetched" success line), not an OCR/template match.
  - D5's timeout→unreachable shape is the V3-sanctioned emulator substitute
    for the cellular errno-113→offline shape; the offline CLASSIFICATION path
    (which presentation does not depend on, per the amended invariant 41) is
    instead witnessed by T-rows (provider matrix) and W-rows (widget matrix).
  - The gate is an in-memory derived bool, never persisted: a fresh process
    always starts gate-off (D1 is that witness); no restore path can show a
    red surface the user did not ask for in this session.
  - H1/H2 (host-session rows: maintainer harness Cases A/B/C re-run with
    invariant-53 prefs; real cellular shapes) were NOT attempted, per run.md
    pre-declaration — Pixel 6 and ESP32 harness untouched. Named substitute
    proofs: D1-D5 above (loopback-refused + blackhole substitutes,
    zero-server-write throughout) + T1-T8/W1-W4b + the two host GET witness
    readings (200/total=13).
```
