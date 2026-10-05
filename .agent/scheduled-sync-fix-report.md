# SCHEDULED-SYNC FIX (DEFECT A + DEFECT B): COMPLETE

Targeted hotfix on `audio_player` (a main hotfix would collide with the imminent
merge; both defects exist in released main). Not a phase; report uses the
verification-protocol §6 structure.

Environment: Pixel 6 (25071FDF600953), **Android 16 (API 36)** — required, since
both defects are API-31+ behaviour. Server `http://192.168.1.13:3689`
(invariant #10). All times below are device-local EDT. All evidence is from
`adb logcat -s BackgroundSyncWorker MainActivity`, the WorkManager database
(`no_backup/androidx.work.workdb` via `run-as`, debug build), and
`uiautomator dump` / screencap pixel analysis.

## GO/NO-GO CHECK
  What it was: make one scheduled sync fail, restore the condition, and confirm a
    subsequent scheduled sync still fires without any manual sync (Defect B).
    Plus: saving a schedule actually enqueues a job that fires on time (Defect A).
  Did you run it:        YES
  What you observed:
    - Arming: saved a daily schedule for 23:03 (today, ~50s out) at 23:02.
      At 23:03:00.087 the worker started, "Trigger type: scheduled", completed,
      and logged "Next sync scheduled for Sat Oct 03 23:03:00". No manual sync
      was pressed. History screen shows the row with a "Scheduled" trigger chip.
      Before the fix this save threw `IllegalArgumentException: Expedited jobs
      cannot be delayed`, enqueued nothing, and still reported success
      (reproduced 3x on this device in the 2026-10-02 session).
    - Replacement: with a job pending for 23:03, saved a new time 23:17.
      work.db held exactly one `sync-task` spec (dcc5e9c7), trigger 23:17:00.022;
      the old 23:03 spec was gone. It fired 23:17:00.054 (worker id matched
      dcc5e9c7), "Trigger type: scheduled", re-armed for the next day. The old
      time did not fire.
    - Chain survival: armed 23:45 with `flutter.server_url` removed from
      SharedPreferences (worker throws "No server URL configured" in the named
      catch). It fired 23:45:00.051, "Trigger type: scheduled", logged
      "Background sync failed with exception" (SyncException at
      BackgroundSyncWorker.kt:305), and — the fix — "Next sync scheduled for
      Sat Oct 03 23:45:00". work.db held one `sync-task` spec (fbb09243) with
      trigger 10-03 23:45:00, enqueued by the failed run itself. History screen
      shows "Sync Failed … Yesterday at 11:45 PM" with a "Scheduled" chip.
      Restored the URL through the UI, saved a new schedule (01:21); it fired
      01:21:00.047, "Trigger type: scheduled", succeeded, re-armed for Sun Oct
      04 01:21:00. No manual sync between the failure and that fire.
    - Happy path: every successful scheduled run re-armed the next one (23:03 →
      23:17 → 01:21 → 01:36, "Next sync scheduled for …" each time), and a
      successful save shows the transient snackbar (pixel A/B below).

## OBSERVED — things you did and saw, on the emulator, by hand
  - Uninstalled the release v0.1.8 APK, installed the fixed debug APK, launched
    → Library screen rendered (empty; app data wiped by the uninstall).
  - Granted notification + media permission on the system dialogs → app
    proceeded to Server Configuration.
  - Tapped "Grant Music Access" → SAF document picker opened (the picker runs in
    the system process, so `uiautomator dump` could not see it); selected
    "OwnToneMusic" from the picker screenshot coordinates.
  - Typed the server URL, saved → "Server configured" snackbar, Library
    populated (Brass / Soul / Holiday Music rows).
  - Tapped a playlist row, selected Brass + Soul + Holiday Music → "Playlists
    saved" snackbar.
  - Pressed "Sync Now" (manual baseline) → worker ran: "Background sync
    completed: 152 tracks downloaded in 90581ms" (22:44, Trigger manual).
    Re-granted the battery-optimization exemption afterwards
    (`dumpsys deviceidle whitelist +dev.educoder.owntone_sync`) because the
    uninstall wiped it.
  - Saved a daily schedule for 23:03 (a few minutes out) → logcat: "Background
    sync scheduled for Fri Oct 02 23:03:00 EDT 2026 (4 minutes from now)". At
    23:03:00.087: "=== SYNC WORKER STARTED === … Trigger type: scheduled",
    "Background sync completed: 0 tracks downloaded in 2302ms" (152 already
    present), "Next sync scheduled for Sat Oct 03 23:03:00".
  - Saved 23:17 while the 23:03 job was pending → work.db: one spec, trigger
    23:17:00.022, old spec gone. Fired 23:17:00.054 as scheduled.
  - (Past-time branch, observed en route: at 22:56:52 saving a time already in
    the past scheduled for the next day: "… (1438 minutes from now)".)
  - Forced the next scheduled run (23:45) to fail by removing
    `flutter.server_url` from SharedPreferences while the app was stopped, then
    launching the app so the process started without the pref → it fired
    23:45:00.051 scheduled, "No server URL configured", "Background sync failed
    with exception" (BackgroundSyncWorker.kt:305), then "Next sync scheduled for
    Sat Oct 03 23:45:00" (re-armed by the failure path). work.db: one spec
    fbb09243, trigger 10-03 23:45:00.
  - Restored the URL via the UI (Server Configuration, save), saved schedule
    01:21 → fired 01:21:00.047 scheduled, "Event sync completed: 30 events
    synced" (playback events accumulated during the session), "Background sync
    completed: 0 tracks downloaded in 26514ms", "Next sync scheduled for Sun Oct
    04 01:21:00".
  - Saved 01:36 (01:32) → fired 01:36:00.045 scheduled, completed 01:36:03.503,
    re-armed for Sun Oct 04 01:36:00.
  - Success-reporting A/B: saved at 01:32:22; screencap at +1s vs +5s, same
    Library screen. Bottom band (y≈2220–2400) bright (~226 grey) at +1s, dark
    again (~18–60) at +5s — a 4-second bottom-anchored snackbar appeared exactly
    once, on the genuine save. (The bar's text was not read off the pixels.)
  - History screen after all runs: 6 rows in order — Scheduled/Completed 01:36,
    Scheduled/Completed 01:21, Scheduled/**Failed** "Yesterday at 11:45 PM",
    Scheduled/Completed 23:17, Scheduled/Completed 23:03, Manual/Completed
    22:44 (152 tracks). Trigger chips on every row as expected.
  - Toggled "Enable Automatic Sync" off and saved (device restore) → logcat
    "Background sync disabled"; work.db: the one `sync-task` spec now
    CANCELLED, no ENQUEUED/RUNNING jobs; prefs `enabled:false`.

## NOT VERIFIED — implemented but not exercised, and why
  - The "Failed to save schedule" error snackbar (Defect A's reporting fix,
    negative case): after removing `setExpedited` the enqueue no longer throws
    in the repro conditions, so the failure branch was not triggered on device.
    Verified by code inspection only (invokeMethod<bool> → throw → snackbar).
  - The task's suggested failure mode (closed port / no Wi-Fi) was **not** the
    one tested, by code-path analysis: every per-playlist network call is inside
    a per-iteration try/catch (BackgroundSyncWorker.kt:406–648), so a dead
    server is swallowed per playlist and the run completes as "success" with
    playlist errors, re-arming via the success path. It never reaches the outer
    `catch (e: Exception)` that Defect B names. The missing-server-URL
    condition reaches that catch (thrown at BackgroundSyncWorker.kt:305), so it
    was used instead. The closed-port run itself (a "success" row with per-
    playlist errors) was not executed on device.
  - `Result.retry()` alternative: not implemented (re-arm chosen, rationale
    below); its interaction with this worker is unverified.
  - Two adjacent pre-existing gaps, out of scope, untested:
    (a) user-cancel of a running sync (CANCELLED_BY_APP → handleInterruption →
    Result.success, no re-arm) and (b) setForeground refusal
    (ForegroundServiceStartNotAllowedException → Result.failure, no re-arm).
    Both could still kill the schedule; noted for the backlog, not fixed here.
  - The success-snackbar's text: pixel evidence shows the transient bottom bar;
    the text was not read off the pixels.

## DEVIATIONS — anything not done as the phase specified
  - The device held the hardware-pass release build (v0.1.8, non-debuggable).
    Installing the fixed debug build required uninstall → app data (DB, prefs,
    folder grant, battery exemption) wiped. Reconfigured from scratch: URL,
    OwnToneMusic folder, three playlists, one manual sync (152 tracks re-
    downloaded; the 142 user files on /sdcard/OwnToneMusic were overwritten in
    place where names matched). Battery exemption re-granted via
    `dumpsys deviceidle whitelist`.
  - Failure injection required two setup steps because of Android semantics:
    the in-process SharedPreferences cache is authoritative while the app runs
    (editing the file under a running process doesn't stick), and force-stop
    cancels the pending WorkManager job (documented behaviour, observed during
    the experiment: the app-startup re-register then re-armed for the next day).
    Final sequence: app stopped → edit prefs file → launch app → arm schedule.
  - One `adb exec-out screencap` hung ~17 min and one input sequence ~35 min
    (transport-level stall, recovered without reconnect); one save therefore
    landed at 00:11 instead of 23:58 and scheduled for that night. Harness
    incident, no app state corrupted, sequence captured.
  - Schedules were set a few minutes out (per the task), not the daily 2 am;
    `requiresCharging`/`requiresWifi` left off to keep the constraint/skip
    paths out of the arming tests.

## BUILD
  flutter analyze:
    No issues found!
  flutter build apk --debug:
    Built build/app/outputs/flutter-apk/app-debug.apk

## Fix rationale — re-arm on failure, not Result.retry()
  The app's recurring schedule is a self-chaining one-time work: every finished
  run enqueues the next scheduled run (success path and "skipping today" path
  already do this — the skip path carries the load-bearing comment "skipping
  today must not break the recurring schedule"). The failure path now follows
  the same rule. `Result.retry()` re-runs the same spec with backoff and only
  re-arms the recurring chain if a retry eventually succeeds via the success
  path; a failure outlasting the retries (or the user disabling the schedule
  mid-retry, which `cancelAllWorkByTag` would cancel) leaves the recurring
  schedule with no pending work — the same "dead and not revivable from the
  UI" state. The two are also mutually exclusive here: `scheduleNextSync`'s
  `enqueueUniqueWork(REPLACE, "sync-task")` would cancel a pending retry spec.
  Re-arming is the only choice that deterministically keeps the cadence the
  user configured.

## UNKNOWN — behaviour you could not explain
  - `dumpsys jobscheduler` showed nonsense relative offsets for the sync job at
    one point (e.g. "Enqueue time: -9h24m" for a job enqueued seconds earlier).
    Same "frozen/cached display" unknown as the hardware-pass report; the
    absolute trigger time was therefore read from WorkManager's own DB instead.
  - Why one `adb exec-out screencap -p` blocked ~17 min and one input sequence
    ~35 min on the USB connection, then recovered: unknown (transport-level).

## APPENDIX — file changes
  - android/app/src/main/kotlin/dev/educoder/owntone_sync/MainActivity.kt
    - `registerBackgroundSync()` now returns `Boolean` (false: no schedule,
      unparseable schedule, enqueue threw; true: cancelled-disabled, or
      enqueued).
    - Delayed (scheduled) request: removed `.setExpedited(...)`. The manual
      "run now" request (~line 167, no initial delay) is unchanged — that
      pairing is legal.
    - `updateSyncSchedule` handler now replies with the real result.
  - android/app/src/main/kotlin/dev/educoder/owntone_sync/BackgroundSyncWorker.kt
    - `catch (e: Exception)` now calls `scheduleNextSync()` before
      `Result.failure()` (comment records the why).
  - lib/presentation/providers/sync_provider.dart
    - `updateSyncSchedule` reads the native `bool` and throws if registration
      did not take effect.
  - lib/presentation/screens/schedule_config_screen.dart
    - Save button: on failure shows "Failed to save schedule" (no pop, no
      success snackbar); on success pops and shows "Schedule saved: …".
