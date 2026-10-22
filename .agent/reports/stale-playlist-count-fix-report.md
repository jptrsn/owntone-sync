# Stale playlist count after missed sync completion — fix verification

**Fix under test:** (a) the launch probe reports the `sync-task` work's state
(`getSyncWorkState`: `running` | `pending` | `none`) and
`SyncProvider.checkIfSyncRunning` subscribes to the progress EventChannel for
`pending` as well as `running` (without claiming `isSyncing`), and (c)
`_onSyncCompleted` reloads via `reloadAll()` instead of `loadData()`.
Resolves the 2026-10-22 entry in `.agent/blockers.md`; the mechanism is now
invariant 52 (with corrections noted in invariants 34 and 51).

**Files changed:** `MainActivity.kt` (probe), `sync_provider.dart` (probe
consumer), `library_screen.dart` (completion refresh),
`test/sync_provider_connectivity_test.dart` (mocks + new pending-probe test),
`test/widget_test_helpers.dart` (mock).

**Build under test:** debug APK of the working tree (base `c94aa9b` + this
fix). **Device:** emulator-5554, `Pixel_9_Pro_API_36` — identity confirmed
per invariant 42 via `lsof` on the qemu pid (pid 8902 →
`Pixel_9_Pro_API_36.avd`). Note the serial is not the one the original
reproduction ran on: the environment was reset mid-session (~13:37–16:52,
both AVDs died, `/tmp` wiped) and the restarted instance took serial 5554.
The AVD's userdata survived the reset (app install and seeded DB intact).
The physical device `25071FDF600953` was attached and not touched.

GO/NO-GO CHECK
  What it was: the blockers entry's "Verification when fixed", unmodified —
  seed Rediscover's membership at 8 while the server holds 2, schedule a
  sync, launch the app while the work is ENQUEUED, and after the worker
  completes confirm, with no tab switch and no restart, that the list shows
  2, the drawer's "Last synced" is current, and a pre-existing
  `unreachable` banner (had one existed) would be cleared by the same
  handler.
  Did you run it:        YES (banner half: no banner existed at launch — see
                         NOT VERIFIED)
  What you observed: see OBSERVED. The completion event reached Dart
  ("Sync completed with status: success" — the line absent from the bug run)
  and the Playlists tab auto-refreshed 8 → 2 with no tab switch and no
  restart; drawer read "Last synced 4m ago", server reachable.

OBSERVED — things I did and saw, on emulator-5554, by hand

Setup:
  - Seeded the DB (app force-stopped, base64-chunked run-as write):
    `synced_playlists` row for Rediscover (id 17, the server's live
    name/path/type) + 8 `playlist_tracks` rows (real ids 1617/2389 + 6
    fabricated 90001–90006) — yesterday's pre-shrink state. Server read via
    curl (read-only): Rediscover holds 2 tracks.
  - Wrote the app prefs directly (app force-stopped): playlist selection
    `["11","17"]` (Brass + Rediscover) and schedule enabled daily 17:10,
    charging/WiFi conditions off. The worker and the launch-time
    `registerBackgroundSync()` both read these same prefs, so this exercises
    the exact production code path under test without the slow UI dance.
    (First attempt encoded the selection list as one base64 blob of
    prefix+JSON; the plugin's ListEncoder then fell back to legacy Java
    deserialization and crashed `_initialize` at the prefs read with
    `StreamCorruptedException` — the correct on-disk form is
    `base64(prefix) + "!" + raw JSON`, as the app itself writes it. Fixed
    and re-verified before the run.)
  - The 13:40 first target was abandoned for 17:10 after the environment
    reset — 10+ minute lead time for the slow-acting session, per session
    guidance.

The run (16:56–17:11):
  - Cold-launched at 16:56 while the 17:10 work was ENQUEUED. Logcat:
    `16:56:36 Background sync scheduled for Thu Oct 22 17:10:00 EDT 2026
    (13 minutes from now)` (the launch's REPLACE re-enqueue, in native
    `onCreate`), then `16:56:38 Sync work state: pending (found 1 work
    items, states: [ENQUEUED])` — the new probe answering the question the
    old one couldn't — then `flutter: 💡 Background sync enqueued —
    subscribing for its completion` and `Progress listener attached`
    (MainActivity: the EventChannel sink now exists; both lines were absent
    in the 11:17 bug run).
  - UI baseline: Playlists tab **Brass — 33 tracks / Rediscover — 8 tracks**
    (fresh read of the seeded DB), no unreachable banner.
  - Left alone. `17:10:00.039 === SYNC WORKER STARTED ===`, `Trigger type:
    scheduled`; `17:10:33 Playlist Rediscover has 2 tracks` (membership
    rewritten); `17:10:35.417 Background sync completed: 35 tracks
    downloaded in 35386ms (status=success)`; **`17:10:35.418 flutter: 💡
    Sync completed with status: success`** — the completion event reached
    the Dart side. `17:10:35.420 Next sync scheduled for Fri Oct 23
    17:10:00`.
  - UI, still on the Playlists tab, no tab switch, no restart (dumped
    ~17:11): **Rediscover — 2 tracks** (auto-refreshed from 8; Brass — 33
    unchanged). The reported 8-vs-2 divergence is gone.
  - Drawer: **"Last synced 4m ago"**, server line `192.168.1.13:3689` with
    no "Server not responding" (in the bug run this line sat at "12d ago"
    with the server-not-responding note).
  - DB (run-as extract): `playlist_tracks` → 11:33, 17:2; newest
    `sync_history` row `success | scheduled | 2 playlists | 35 tracks`.
  - Unit test (the guard): pending probe → subscription established,
    `isSyncing` false; first progress event flips `isSyncing` on;
    completion reconciles reachability and fires `syncCompleted` —
    passes (`flutter test test/sync_provider_connectivity_test.dart
    --plain-name "pending"`: 1 passed).

NOT VERIFIED — implemented but not exercised, and why
  - The pre-existing `unreachable`-banner clearing by the completion
    handler: no banner existed at this run's launch (the 11:17 bug run's
    banner was a fixture of a transient fetch failure). The state transition
    lives in the same completion branch that provably ran (`Sync completed
    with status: success` → the handler sets `reachable`), but it was not
    independently observed clearing a live banner in this build.
  - The detail screen's count was verified via the DB (the detail renders a
    live `getTracksForPlaylist` over the same `playlist_tracks` table),
    because a mid-cleanup tap misfired into the Sync screen and the
    uiautomator dumps around it were zero-text (paint wedge, invariant 32).
    The detail screen's correctness was already device-established in the
    original reproduction report.
  - The BLOCKED branch of the new probe: the scheduled work sat in ENQUEUED
    the whole window on this emulator (network always available), so the
    `pending`-via-BLOCKED path is verified only by code reading and the
    unit test's `pending` state, not by a device that actually blocked.

DEVIATIONS — anything not done as the task specified
  - Prefs (selection + schedule) were written directly to the on-disk XML
    with the app force-stopped, instead of through the Sync/Settings UI:
    faster, deterministic, and it feeds the same code paths the worker and
    the launch-time registration read — but it bypasses the UI's save-time
    validation, which was not the object under test.
  - Schedule target was 17:10 (10+ minute lead) rather than "a couple of
    minutes out", per session guidance on lead time for scheduled actions.
  - The first prefs write used a wrong list encoding and crashed
    `_initialize` (StreamCorruptedException, 13:33 run) — an error in the
    harness, not the app; the app recovered cleanly on the corrected
    relaunch and the crash line was confirmed absent from the 16:56 run.
  - The environment reset (~13:37–16:52) killed both AVDs and wiped
    `/tmp/owntone_verify`; the scratch scripts were recreated and the run
    continued on the restarted AVD (new serial 5554). The original bug
    run's evidence files (logcat_bug.txt, logcat_control.txt, UI dumps, DB
    extracts) are lost with it — their content is preserved in
    `stale-playlist-count-report.md`, which stands.

BUILD
  flutter analyze: 0 errors, 0 warnings ("No issues found!").
  flutter test: 159 passed (158 pre-existing + the new pending-probe test).
  flutter build apk --debug: succeeded; installed over the running app
  (streamed install) after clearing the previous session's ~280 MB of test
  MP3s from the SAF tree (the install initially failed on a 495 MB
  /data; the MP3s were synthetic test artifacts, none from the user).

UNKNOWN — behaviour I could not explain
  - The environment reset itself (both AVDs dead, /tmp wiped, ~3 hours
    between the last and next action) — no record of what did it.
  - The zero-text uiautomator dumps remained intermittent on this AVD as on
    the last (invariant 32's paint wedge); worked around with retry and
    prefs/DB cross-checks.

Post-run cleanup (observed): Rediscover deselected (selection restored to
Brass-only `["11"]` via prefs + relaunch), schedule disabled — launch log
confirms `Background sync disabled` and `WM-Processor: Processor
cancelling <5a42e315-...>` (tomorrow's 17:10 work cancelled); logcat
capture stopped. Emulator left running with the app installed; server
untouched (read-only throughout).
