# Stale playlist count after missed sync completion — device reproduction

**Bug:** Playlists tab shows the pre-sync track count (8) while the playlist
detail shows the post-sync count (2), after a background sync the app never
heard about. Recorded as the 2026-10-22 OPEN entry in `.agent/blockers.md`.

**Build under test:** `c94aa9b` (v0.3.1+20, the released commit), debug APK.
**Device:** emulator-5556 (`Pixel_9_Pro_API_36`, the session's own AVD — the
serial was confirmed via `lsof -p <qemu-pid> | grep avd` per invariant 42,
because another session's emulator, emulator-5554, was also attached). The
physical device `25071FDF600953` was attached but is the user's phone and was
not touched.

BUG CAPTURE: COMPLETE

GO/NO-GO CHECK
  What it was: reproduce the user-reported 8-vs-2 divergence on a virtual
  device, with the database correct and only the in-memory list stale, and
  confirm the mechanism (completion broadcast dropped because the app was not
  subscribed while the scheduled work was ENQUEUED).
  Did you run it:        YES
  What you observed: see OBSERVED. List "Rediscover — 8 tracks" and detail
  "Rediscover — 2 tracks" were on screen at the same time, 40 s after the
  worker logged `status=success`; logcat shows the worker run with no
  "Progress listener attached" and no Dart "Sync completed with status" line.

OBSERVED — things I did and saw, on emulator-5556, by hand

Setup (all via the app's own UI unless noted):
  - Installed the debug APK over the existing app data (33 Brass tracks, no
    playlists, no server URL — the state left by the 2026-10-19 session).
  - Seeded the DB while force-stopped (run-as, base64 chunked write — the
    first write attempt hung and truncated the file; restored from the host
    copy; `PRAGMA integrity_check` = ok): `synced_playlists` row for
    Rediscover (id 17, server's real name/path/type) + 8 `playlist_tracks`
    rows (the server's 2 real track ids 1617/2389 + 6 fabricated ids) — i.e.
    yesterday's pre-shrink state. Server holds Rediscover at 2 tracks (curl
    `GET /api/library/playlists?limit=1000` and
    `GET /api/library/playlists/17/tracks`, read-only).
  - Server Configuration: typed `http://192.168.1.13:3689`, saved.
  - Sync screen: selected Brass + Rediscover ("2 playlists selected").
  - Storage: "Folder access granted" (the system permission had survived; no
    re-grant needed).
  - Schedule: enabled daily 11:23, charging/WiFi conditions off, saved.
    (First save attempt landed 0-1 s after the minute tick and enqueued
    TOMORROW's 11:03 — `registerBackgroundSync` rolls past times forward a day;
    `flutter.expected_next_sync` and WorkManager's `WorkSpec` (state 0 =
    ENQUEUED) confirmed. Re-saved for 11:23; `expected_next_sync` then pointed
    at today 11:23:00.)

Reproduction run (11:17–11:24):
  - Cold-launched the app at ~11:17 (work ENQUEUED, ~6 min out). Playlists tab
    rendered **Rediscover — 8 tracks** (fresh read of the seeded DB).
  - Navigated: Sync screen → Settings → Schedule → saved the 11:23 target.
    Went back to the Library and left it on the Playlists tab. (At 11:17 the
    launch's `fetchPlaylists` had failed transiently — a red
    "Can't reach 192.168.1.13" banner was up; curl from host and ping from the
    emulator both succeeded, so the server was reachable and this was a
    transient probe failure, not a server fault.)
  - 11:23:00.029 worker started (logcat, verbatim):
    `MainActivity: Background sync scheduled for Thu Oct 22 11:23:00 EDT 2026
    (0 minutes from now)` at 11:22:35 (the launch's re-enqueue), then
    `WM-WorkerWrapper: Starting work ... BackgroundSyncWorker`,
    `=== SYNC WORKER STARTED ===`, `Trigger type: scheduled`.
  - Worker: `No events to sync`; Brass 33 (28 re-downloaded — the SAF tree
    held only 5 files from an earlier session); **11:23:26.582 `Playlist
    Rediscover has 2 tracks`**; downloaded 1617 + 2389; `11:23:28.323
    Background sync completed: 30 tracks downloaded in 28286ms (status=success)`;
    `Next sync scheduled for Fri Oct 23 11:23:00`.
  - **Nowhere in the capture: "Progress listener attached" (MainActivity) or
    `flutter: Sync completed with status`** — the completion broadcast hit a
    null `eventSink` and was dropped.
  - In the app, still on the Playlists tab, no tab switch, no restart:
    **Rediscover — 8 tracks** (stale).
  - Tapped into Rediscover: **Rediscover — 2 tracks**, rows "Toda mi vida —
    Pueblo Café" and "Ex's and Oh's — Elle King" (the server's two tracks,
    freshly downloaded). → **The user's exact symptom, 8 list / 2 detail.**
  - Back on the list: still **8 tracks** (back navigation does not reload).
  - Drawer: **"Last synced 12d ago"** (stale — the sync finished 6 min ago) and
    **"Server not responding"** (the transient `unreachable` from the 11:17
    fetch failure; a successful sync would have set reachable, but that
    transition lives in the same dropped handler).
  - History screen (live DB read in `initState`): fresh row **"Sync Completed
    — 9 minutes ago — 2 playlists • 30 tracks downloaded — [Scheduled]"** above
    the Oct 9 manual row. → The app's own record that the sync ran, while its
    list/drawer/state stayed pre-sync. (This is the user's "the playback events
    synced properly" observation: History is a live DB read.)
  - DB check (run-as extract): `playlist_tracks` for id 17 = **2 rows**;
    `sync_history` gained the scheduled/success row. The write was correct —
    only the refresh was missed.
  - Recovery: switched to the Tracks tab and back to Playlists →
    **Rediscover — 2 tracks** (`setCategory` → `loadData`). The data was right
    all along; the missed completion is the whole defect.

Control run (11:34–11:40, protocol §4 positive check):
  - Force-stopped, re-seeded the 8 membership rows (same base64 restore path),
    relaunched cold: list showed **Rediscover — 8 tracks**; the 11:17 banner
    was gone (this launch's fetch succeeded → reachable).
  - Sync screen → tapped **Sync** (manual). Logcat: `Manual sync triggered
    (expedited)` then **`Progress listener attached`** — the subscription the
    reproduction run lacked.
  - Worker 11:38:15→11:38:17, `status=success`, `Playlist Rediscover has 2
    tracks`, 0 downloads. Logcat: **`flutter: 💡 Sync completed with status:
    success`** — the Dart side received the event (the reproduction run never
    logged this line).
  - Back on the Library: Playlists tab auto-refreshed to **Brass — 33 tracks,
    Rediscover — 2 tracks** with no tab switch; no banner; the system
    notification-permission prompt appeared (invariant 44 — first successful
    sync; it is requested inside the same completion handler, further evidence
    the handler ran). The healthy path works end to end.

NOT VERIFIED — implemented but not exercised, and why
  - The user's exact overnight timing on the phone (process alive vs killed,
    which screen was showing, when WorkManager actually started the work).
    The ENQUEUED-at-launch shape is the one consistent with every reported
    observation — a launch after the rewrite heals via the `reloadAll()`
    launch load (invariant 51), and a launch that catches the work RUNNING
    subscribes and refreshes — but the phone's own logcat is not available,
    so the precise minute on the phone remains **unknown**.
  - The current-category-only gap of a *received* completion (other tabs
    staying stale until a switch) — real in code (`loadData()` vs
    `reloadAll()`), not separately demonstrated: it would require the server's
    membership of a second playlist to change in the same run.
  - The `unreachable`-banner pinning was caused by a transient fetch failure
    in the repro, not by the missed completion alone; it is recorded as an
    additional stale-state side effect sharing the root cause, not as a
    second defect.

DEVIATIONS — anything not done as the task specified
  - The task said "virtual device"; the shared emulator-5554 belongs to
    another session, so the session's own AVD (emulator-5556) was used, per
    invariant 42's serial-confirmation rule.
  - The emulator's app data was re-configured (server URL, Brass selection,
    schedule toggles, notification permission granted at the first-success
    prompt) — necessary because a previous session had wiped it. State was
    restored afterwards: Brass-only selection (`["11"]`), schedule disabled,
    no ENQUEUED work left in WorkManager. Rediscover's 2 downloaded MP3s and
    their `synced_tracks` rows remain locally (invariant 27: local files are
    kept on membership loss) — 2 small files in the emulator's test SAF tree.
  - Seeding the pre-shrink state (8 membership rows, 6 of them fabricated ids)
    was done on the emulator's local DB only — the OwnTone server was read,
    never written (no rating/count changes, no playlist edits).

BUILD
  flutter analyze: not run — no code changes in this capture (task was to
  record and confirm the bug, not fix it).
  flutter build apk --debug: succeeded (build/app/outputs/flutter-apk/
  app-debug.apk, installed as `dev.educoder.owntone_sync` v0.3.1+20).

UNKNOWN — behaviour I could not explain
  - The 11:17 `fetchPlaylists` failure on an actually-reachable server
    (classified `unreachable` → banner; the 11:34 fetch of the same URL
    succeeded). Possibly LAN/VPN churn on the host at that minute, or a dio
    timeout; not chased — it served as the repro's stale-banner fixture and
    is unrelated to the count divergence.
  - `adb exec-out run-as ... sh -c 'cat > file' < local` hangs (stdin is not
    forwarded through run-as), leaving the file truncated. Worked around with
    base64 chunks; the hang itself is unexplained.
  - WorkManager deferred nothing in either run (the 11:23 work fired at the
    second), so the deferral window (WorkManager can delay ENQUEUED work
    minutes to hours) is a documented capability, not something observed here.
    It widens the repro's window on real devices but was not needed on the
    emulator.

Evidence files: `/tmp/owntone_verify/` (logcat_bug.txt, logcat_control.txt,
ui_*.xml dumps, emu_*.db DB extracts) — session-local, not committed.
