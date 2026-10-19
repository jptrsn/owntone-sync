# Fix report — launch dead end when the default Library tab is empty but other categories have data (2026-10-17 blocker entry)

Branch `fix/launch-dead-end` (from main db3b05d). Commit 33395bf (fix +
guard test). Date: 2026-10-19 (unattended build unit 2 of the overnight
run).

```
PHASE fix/launch-dead-end (2026-10-17 launch dead-end entry): COMPLETE

GO/NO-GO CHECK
  What it was: per the entry's verify — seed the app DB with an empty
    Playlists table but populated Tracks (the gold-seed DB, a genuine
    10-16 pull of the 10-17 dead-end state: synced_playlists 0 rows,
    33 synced_tracks with local_path/content_uri/file_size populated),
    launch, and confirm the TABBED library (not the empty state) appears
    with no relaunch or sync — and that switching to the populated tabs
    shows the data (the in-app way out of the former dead end).
  Did you run it:        YES
  What you observed: RED (installed pre-fix build + gold seed, no
    install): launch rendered "No music yet" + "Set up sync" with NO
    TabBar (u2_red_library.xml: 0× Playlists/Artists/Albums/Tracks
    labels, 0× track data; positive controls present — "Library" title,
    drawer, Search, Sort by). GREEN (fixed build, adb install -r, gold
    seed sha256-verified intact): the same launch rendered the TabBar
    with all four tabs ("Playlists Tab 1 of 4" … "Tracks Tab 4 of 4"),
    0× "No music yet", the Playlists tab showing its genuine empty list
    ("No playlists synced"); tapping Artists / Albums / Tracks showed
    the seeded Brass data (u2_green_artists/albums/tracks.xml). No
    relaunch, no sync (console: "Fetch playlists skipped - server URL
    not configured"; server unreachable and no sync attempted, per the
    run brief). Attached flutter attach + app-pid logcat: 0 "E flutter"
    AND 0 "E/flutter" (both grep forms) for the whole pass, 0 FATAL, 0
    ANR.

OBSERVED — things you did and saw, on the emulator, by hand
  - Launched the AVD windowed (flutter emulators --launch
    Pixel_9_Pro_API_36); identity confirmed with `adb -s emulator-5554
    emu avd name` → Pixel_9_Pro_API_36 (single qemu process, single adb
    device). (See DEVIATIONS for a kill/relaunch incident during a
    preflight identity check; re-verified before any device work.)
  - df /data: 91% full, 587,936 KB free (< the 1.2 GB plan threshold).
    Freed space in the plan's priority order, recording every file:
    14 stale /data/local/tmp files (Phase-8/Unit-1 session artefacts,
    ~1.5 MB), 69 stale /storage/emulated/0 root files (10-09/10-16
    session dumps, ~0.9 MB), then 28 of the 33 Brass MP3s (235.4 MB) —
    full delete list in /tmp/owntone_verify/u2_delete_list.txt; kept 5
    (see ASSUMPTIONS). Free: 587,936 → 831,420 KB (87%).
  - Pulled the pre-seed app DB (u2_preseed_app.db: schema v8, 0
    playlists, 0 tracks, 2 history rows — the Unit-1 build's state) and
    pushed the gold seed (126,976 bytes) via run-as while the app was
    stopped; device sha256 448fe1facb…d31984b = host sha256 (byte-
    identical).
  - RED: force-stopped the app, `flutter attach` (u2_red_attach.log) +
    `am start` → Library showed the empty state ("No music yet", "No
    music yet" grep 1×, "Set up sync" button) with no TabBar and no
    data, despite the 33-track DB (u2_red_library.xml). App logcat
    (pid 4491): "Fetch playlists skipped - server URL not configured",
    "No background sync running"; 0 E flutter / 0 E/flutter.
  - Installed the fixed build: `adb install -r` → Success (no storage
    failure at 812 MB free); lastUpdateTime 2026-10-18 22:49:21; gold-
    seed DB sha256 re-verified identical after the install.
  - GREEN: force-stop, `flutter attach` (u2_green_attach.log) +
    `am start` → the Tabbed library rendered on first launch: all four
    tabs, "No music yet" 0×, Playlists tab = "No playlists synced"
    (genuinely empty) (u2_green_library.xml).
  - Tapped Artists (480,396) → all seeded artists with counts (Too Many
    Zooz 6 albums • 13 tracks; Thundersmack 1 album • 5 tracks; Young-
    blood Brass Band 2 albums • 11 tracks; the feat. credits as their
    own rows — invariant 21) (u2_green_artists.xml).
  - Tapped Albums (800,396) → the seeded albums incl. the multiple
    distinct "Brass" albums by different artists/years (invariant 21)
    (u2_green_albums.xml).
  - Tapped Tracks (1120,396) → track rows (title / artist • album /
    length) (u2_green_tracks.xml).
  - SAF grant state (plan item 4): Storage screen found "Music folder /
    No folder access" + "Grant access" (the Unit-1 wipe lost the grant).
    Re-granted through the app's flow (U3 device-pass recipe): Grant
    access → system dialog "Allow Owntone Player to access music and
    audio on this device?" → Allow → SAF picker (already at Music,
    showing its playlists/tracks children — the tree survived the
    uninstall, invariant 36) → USE THIS FOLDER → "Allow Owntone Player
    to access files in Music?" → ALLOW → Storage screen "Music folder /
    Folder access granted" + "Change folder" (u2_green_storage*.xml,
    u2_green_grant1.xml, u2_green_saf1/2.xml).
  - Returned to the Library (Tracks tab retained) — still the tabbed
    body with data (u2_green_final.xml). Final DB pull: sha256 still
    the gold seed (the app never rewrote it — no sync, no playback).
  - No no-op swipe / re-dump recovery was needed: every dump carried
    full semantics from the first attempt (the invariants 29/42 trap
    did not materialize; the tab labels live in content-desc, not
    text — a raw-substring scan per invariant 18, not a text-only
    regex).

NOT VERIFIED — implemented but not exercised, and why
  - Option (a) (DB-backed hasContent) — not implemented: the entry
    allows it only if (b) proves wrong on device; (b) verified green.
  - The genuinely-empty-DB launch (all four tables empty → empty state
    with "Set up sync") on device this unit — code path untouched by
    this fix and device-verified on this same AVD by Unit 1 (pre-wipe
    state); not re-exercised to avoid another wipe of the seeded state.
  - Any sync / server behaviour — server unreachable from this host and
    no sync authorized by the run brief.
  - Playback of the kept MP3s — not exercised (a later unit needs
    them; nothing this unit changed touches playback).

DEVIATIONS — anything not done as the phase specified
  - AVD incident: during the boot-wait preflight, a compound identity-
    check command mis-included `adb emu kill` and killed the
    just-launched AVD before it had finished booting. Relaunched with
    the prescribed command and re-verified identity (emu avd name) +
    state (app install timestamp, DB, MP3 count) before any device
    work. No verification evidence was taken before the relaunch; the
    boot-timing oddity it left behind is in UNKNOWN.
  - Console instrument: `flutter attach`'s own log mirrored only the
    connect banner in both passes (no runtime prints), so the app-pid
    logcat window (u2_red_logcat.txt / u2_green_logcat_final.txt) is
    the console evidence — the same fallback the QA sessions used when
    attach was not the complete instrument (see UNKNOWN).

BUILD
  flutter analyze:  No issues found! (ran in 3.3s)
  flutter test:    All 157 tests passed! (154 pre-existing + 3 new in
                   test/browse_provider_launch_test.dart)
  flutter build apk --debug:  ✓ Built build/app/outputs/flutter-
                   apk/app-debug.apk (198,693,643 bytes)

UNKNOWN — behaviour you could not explain
  - Why Unit 1's 160 MB install failed with 570 MB free ("Failed to
    override installation location") remains unknown — and why this
    unit's 190 MB `adb install -r` succeeded at 812 MB free without
    the failure. Consistent with an environmental (near-full-partition)
    trigger, not app-related; recorded for the later units: expect
    install trouble below ~1 GB free on this AVD.
  - Boot-timing anomaly around the DEVIATIONS incident: after the
    accidental kill + relaunch, `sys.boot_completed` read 1 within ~10 s
    and `uptime` read 17 min — longer than the relaunch interval,
    inconsistent with a plain cold boot at that moment. The identity
    and state checks all agree (single qemu process, emu avd name,
    app/DB/MP3 state matching the AVD's known history), and all
    verification evidence is internally consistent (sha256-verified DB,
    matching pids in logcat). Mechanism: unknown.
  - Why the `flutter attach` logs carried no runtime print output in
    either pass (banner only), while the same app's prints appear in
    logcat — recorded; the logcat pid-windows cover the same span.
```

## Evidence

- `/tmp/owntone_verify/u2_red_library.xml` — RED: empty state, no TabBar
  (the dead end reproduced on this device with the gold seed).
- `/tmp/owntone_verify/u2_red_attach.log`, `u2_red_logcat.txt` — RED
  console (0 E flutter / 0 E/flutter; no sync triggered).
- `/tmp/owntone_verify/u2_green_library.xml` — GREEN: TabBar with all
  four tabs, Playlists tab genuinely empty, no empty state.
- `/tmp/owntone_verify/u2_green_artists.xml` / `u2_green_albums.xml` /
  `u2_green_tracks.xml` — the three populated tabs showing the seeded
  Brass data.
- `/tmp/owntone_verify/u2_green_attach.log`, `u2_green_logcat.txt`,
  `u2_green_logcat_final.txt` — GREEN console (0 E flutter / 0
  E/flutter / 0 FATAL / 0 ANR across the whole app window).
- `/tmp/owntone_verify/u2_green_storage.xml` (No folder access) →
  `u2_green_grant1.xml` (audio dialog) → `u2_green_saf1.xml` (SAF
  picker) → `u2_green_saf2.xml` (ALLOW) → `u2_green_storage2.xml`
  (Folder access granted) — the SAF re-grant pass.
- `/tmp/owntone_verify/u2_green_final.xml` — final Library state.
- `/tmp/owntone_verify/u2_preseed_app.db` — pre-seed app DB (Unit-1
  state); gold seed `/tmp/owntone_verify/owntone_sync.db` sha256
  448fe1facb943a96093128321a497f12a8586d8582d6c686381a0d265d31984b
  (verified on-device before launch and after install + pass).
- `/tmp/owntone_verify/u2_delete_list.txt` — the 28 deleted Brass MP3s
  (235.4 MB); kept: 1196 Good People, 1197 Times Square, 1546 The
  Warrior Comes Out to Play, 1870 Chandelier, 1872 Car Alarm.
- `/tmp/owntone_verify/u2_avd_launch*.log`, `u2_avd_launch2.log` — AVD
  launches (both empty = clean launches).
- Guard test: `test/browse_provider_launch_test.dart` (3 tests, cites
  invariant 51). Harness self-check per protocol §4: with the launch
  path temporarily reverted to `loadData()`, the launch-path test fails
  (`Expected: non-empty, Actual: []` on the artists list); restored
  before committing.

## Fix (what changed, why)

- `lib/presentation/screens/library_screen.dart` — the launch load in
  `initState` (post-frame callback) now calls `BrowseProvider.reloadAll()`
  (all four categories) instead of `loadData()` (current category only).
  `hasContent` is an OR over all four in-memory lists; with a current-
  category-only launch load, an empty default tab (Playlists) plus
  unpopulated other lists kept `hasContent` false even with 33 tracks in
  the DB — and with no TabBar rendered there is no in-app control that
  would trigger `setCategory` → `loadData()` for another category. The
  tab-switch path (`setCategory`) and the post-sync refresh
  (`_onSyncCompleted`) keep `loadData()`: by then the launch load has
  populated all four lists and only the current category needs a fresh
  read. A comment at the call site records why `reloadAll()` must not be
  "tidied" back to `loadData()`.
- Guard: `test/browse_provider_launch_test.dart` — (1) the provider seam:
  `reloadAll()` populates all four lists from a DB holding all four;
  (2) the launch path: pumping `LibraryScreen` as `home` (the production
  shape, main.dart) leaves all four lists populated and the tabbed body
  rendered. The true dead-end state (playlists empty, tracks populated)
  cannot be expressed against the shared FFI DB file — constraint 2
  forbids deleting the fixture playlists — so the device go/no-go above
  is the acceptance test for that state.
- Invariant 51 (launch loads every category); blocker entry marked
  RESOLVED.

## Device state left

App: fixed build (this branch's APK) over the gold-seed DB (sha256-
verified); unconfigured (no server URL — the Unit-1 wipe's state); SAF
folder access re-granted to the Music tree; drawer "Last synced 9d ago"
reads the seed's history row. AVD killed at the end of the unit; /data
at 87% (831,420 KB free); 5 Brass MP3s remain as the only playback
material (plan requirement).
