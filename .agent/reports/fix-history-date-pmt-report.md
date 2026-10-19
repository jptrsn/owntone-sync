# Fix report — History date renders "PMt" instead of "at" (2026-10-17 blocker entry)

Branch `fix/history-date-pmt` (from main 0c2b633). Commit 29a2c31 (fix +
test seam + unit test). Date: 2026-10-18 (unattended build unit 1 of the
overnight run).

```
PHASE fix/history-date-pmt (2026-10-17 "PMt" blocker entry): COMPLETE

GO/NO-GO CHECK
  What it was: on the History screen of emulator-5554, the Oct 9 sync row
    from the blocker entry must render "Oct 9, 2026 at 3:12 PM" (quoted
    literal + 4-digit year) instead of "Oct 9, 26 PMt 3:12 PM" — no "PMt"
    anywhere on the screen, the already-correct "Yesterday at …" branch
    still correct, and a clean console for the pass.
  Did you run it:        YES
  What you observed: uiautomator dump of the History screen (evidence
    /tmp/owntone_verify/pmt_history_screen.xml + .png): the Oct 9 row's
    node label is "Sync Completed\nOct 9, 2026 at 3:12 PM\n1 playlists •
    33 tracks downloaded, Collapsed" — the entry's intended string
    verbatim. Grep of the dump: 0× "PMt", 0× "AMt", 0× "26 PMt", 1× "Oct
    9, 2026 at 3:12 PM", 1× "Yesterday at 2:30 PM" (control row). Attached
    `flutter attach` console (pmt_attach.log): 0 "E flutter" AND 0
    "E/flutter" (both grep forms, per invariant 29 / the QA-5 re-
    baselining), 0 FATAL, 0 deactivated-widget noise for the whole pass.

OBSERVED — things you did and saw, on the emulator, by hand
  - flutter run -d emulator-5554 (attached) → app launched; the install
    failed INSTALL_FAILED_INSUFFICIENT_STORAGE and flutter auto-uninstalled
    the old version → fresh install wiped the app data (DB + prefs). First
    run's console: 0 E flutter, 0 E/flutter, 0 FATAL. (See DEVIATIONS.)
  - Pulled the app DB via run-as → every table empty (0 tracks / 0
    playlists / 0 history); no AVD snapshot exists, so the pre-wipe rows
    were unrecoverable and the natural Oct 9 row was gone.
  - Seeded sync_history locally (allowed where a branch has no natural
    row): the entry's Oct 9 row (2026-10-09 15:12 EDT, success, 1
    playlist, 33 tracks, trigger manual) + a constructed control row
    (2026-10-17 14:30 EDT, success, 1 playlist, 0 tracks) for the
    already-correct "yesterday" branch; pushed the file back via run-as
    while the app was stopped, relaunched with am start + flutter attach
    (no reinstall, so the seeded data held).
  - Drawer → History (taps from uiautomator bounds) → the screen rendered
    both rows: the Oct 9 row reads "Oct 9, 2026 at 3:12 PM" and the
    control row reads "Yesterday at 2:30 PM"; "Sync History" title,
    "Manual" chips and "Back" all present (harness positive controls —
    the dump sees known-present things before any absence is claimed);
    the drawer header's "Last synced 1d ago" line read the seeded newest
    row (cross-surface confirmation the app consumed the rows).
  - Tapped the Oct 9 row to expand → "Duration 7m 32s" (the seeded
    452000 ms), "Playlists 1", "Downloaded 33" rendered; the row stays
    functional and the fixed string holds in the expanded state too.
  - No no-op swipe / re-dump recovery was needed: every dump carried full
    semantics from the first attempt (the invariants 29/42 trap did not
    materialize; recorded per the unit brief).

NOT VERIFIED — implemented but not exercised, and why
  - The "this week" branch on device: unreachable on a Sunday
    (startOfWeek == today, so every past row falls into "older"); pinned
    by the unit test instead (Monday timestamp against a pinned Wednesday
    now) — per the unit brief.
  - The "today" (relative-time) branch on device: no natural row and no
    sync possible (server unreachable by environment override); pinned by
    the unit test instead.
  - The pre-wipe natural device rows: lost to the storage-induced
    reinstall before they could be pulled (harness ordering mistake —
    the DB should have been pulled before the first flutter run); the
    seeded Oct 9 row is an exact reproduction of the entry's row (same
    local time 3:12 PM, same counts) so the rendered string is still the
    entry's exact intended string.
  - Any playback / library / sync behaviour: untouched by this change.

DEVIATIONS — anything not done as the phase specified
  - The device's natural Oct 9 row was destroyed by flutter run's
    auto-uninstall (INSTALL_FAILED_INSUFFICIENT_STORAGE, 570 MB free on a
    91%-full 5.8 GB /data vs a 160 MB debug APK) before it could be
    pulled; verification therefore ran against a seeded reproduction of
    the entry's row. The unit brief allows seeding "only where a branch
    has no natural row" — after the wipe, no branch had one.
  - The test seam is `{DateTime? now}` (nullable, resolved in the body)
    rather than `{DateTime now = DateTime.now()}` as the brief's sketch:
    Dart forbids non-constant default parameter values. No behaviour
    change; the tests pass `now:` explicitly.
  - Drawer/History navigation ran on an unconfigured app (post-wipe
    state); the History screen does not depend on configuration, so this
    does not affect the check.

BUILD
  flutter analyze:  No issues found! (ran in 3.1s)
  flutter test:    All 154 tests passed! (143 pre-existing + 11 new in
                   test/history_timestamp_test.dart)
  flutter build apk --debug:  ✓ Built build/app/outputs/flutter-apk/app-debug.apk

UNKNOWN — behaviour you could not explain
  - Why a 160 MB debug APK fails to install with 570 MB free on /data
    ("Failed to override installation location"). Space appears
    sufficient; the failure is environmental (partition layout of this
    near-full AVD, invariant 42's disk note), not app-related. Consequence
    for later units: ANY flutter run / reinstall on emulator-5554 will
    uninstall + wipe app data first. The AVD was left killed; the last
    install on it held the fixed build with an empty (unconfigured)
    library and the two seeded sync_history rows.
```

## Evidence

- `/tmp/owntone_verify/pmt_history_screen.xml` / `.png` — History screen,
  collapsed state (the GO/NO-GO dump + screencap).
- `/tmp/owntone_verify/pmt_history_expanded.xml` — the Oct 9 row expanded
  (Duration / Playlists / Downloaded stats).
- `/tmp/owntone_verify/pmt_attach.log` — attached `flutter attach` console
  for the History pass (0 E flutter / 0 E/flutter / 0 FATAL).
- `/tmp/owntone_verify/pmt_run.log`, `pmt_run2.log` — the two `flutter run`
  sessions (record the install failure + wipe sequence).
- `/tmp/owntone_verify/pmt_history.db`, `pmt_verify*.db` — pulled/verified
  device DB state.
- Unit test: `test/history_timestamp_test.dart` (11 tests, all four
  branches, cites this entry; the "this week" branch pinned with a Monday
  timestamp against a Wednesday `now`).

## Fix (what changed, why)

- `lib/presentation/screens/history_screen.dart` — the "this week" and
  "older" DateFormat patterns now quote the literal and use the 4-digit
  year: `DateFormat("EEEE 'at' h:mm a")`,
  `DateFormat("MMM d, yyyy 'at' h:mm a")`. A bare `a` in a pattern is the
  AM/PM marker, so the unquoted `at` parsed as `a` + literal `t` → "PMt";
  `y` was the 2-digit year → "Oct 9, 26". The formatter was extracted
  from the widget to the pure top-level
  `formatSyncTimestamp(timestampMs, {DateTime? now})` (plus the private
  top-level `_isInCurrentWeek`) — a minimal seam, no behaviour change —
  so the branches are test-pinned.
- Guard: invariant 50 (what breaks if the quotes get tidied back out);
  blocker entry marked RESOLVED.
