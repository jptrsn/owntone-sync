# PIXEL 6 PRE-RELEASE QA: COMPLETE

The 12-test pre-release QA run for 0.2.0 on the user's real device, run
serially over 2026-10-12 → 2026-10-14 (three orchestrator sessions; two
crash recoveries, both resumed from the ledger). Plan, approvals, and the
per-test evidence live in the run ledger (`.agent/reports/overnight-ledger.md`,
gitignored run-scratch — this report is the durable distillation).

- Device: 25071FDF600953 (Pixel 6 / oriole, Android 16 / API 36, the user's
  phone — no emulators were started or touched).
- App: 0.2.0+18 debug APK installed in place over the user's 0.1.8
  (versionCode 17) — signature-compatible, data preserved. Final state of
  the run carries the **4190f3d** build (the QA-11 position fix).
- Server: `http://192.168.1.13:3689` — the user's real, curated library.
- Evidence: screencaps, uiautomator dumps and logcats under
  `/tmp/owntone_verify/qa{1..12b}_*` (ephemeral — /tmp; the ledger entries
  carry the per-test distillation).

## GO/NO-GO CHECK

What it was: all 12 approved test cases pass on the real device over
real 0.1.8 data, with a clean console (no app-code `E flutter` lines) and
the server left as found (except the two sanctioned round-trip writes,
each recorded and restored).
Did you run it:        YES
What you observed: all 12 PASS (QA-5's initial FAIL dispositioned — see
FINDING 1; QA-11's initial observation fixed and re-verified — see
FINDING 2). Server integrity held (see SERVER INTEGRITY).

## OBSERVED — one line per test (action → result)

- QA-1 migration & launch → 0.1.8 data renders the library after the
  in-place upgrade; no crash; U4 reframe live (Owntone Player drawer
  header, regrouped drawer); About "Version 0.2.0". PASS.
- QA-2 library & browse → 4 tabs, playlist detail, track list, artwork,
  search, sort all correct. PASS (one observation — search artist-row
  count — fixed in 2cc100c, see FINDING 3).
- QA-3 playback core → play/pause/resume, next/previous, seek, queue,
  shuffle/repeat all work; console clean. PASS.
- QA-4 mini player on every screen (invariant 16) → mini player docked on
  every destination incl. Settings hub children; Now Playing
  open/close round-trips. PASS.
- QA-5 Now Playing + background → sheet controls work; audio continues
  screen-off; media-notification controls work; relaunch consistent.
  First run FAIL on the console criterion only — dispositioned PASS (see
  FINDING 1).
- QA-6 sync round-trip → app-bar sync icon deep path (invariant 33);
  manual sync writes a History row with Manual chip; the play-counts the
  sync wrote were restored per-track to the recorded originals and
  verified via API; server playlist set unchanged. PASS.
- QA-7 play-count round-trip → original recorded via API; >=30 s of
  playback; count incremented on sync; original restored via API and
  restore verified. PASS.
- QA-8 offline state (invariants 40/41/43) → airplane mode ON:
  probed-offline path, manual sync blocked with helper text, NO failed
  History row for the offline attempt; airplane OFF: state recovers.
  PASS.
- QA-9 unreachable state (invariant 41) → saved a closed port (:9999):
  red only where designed, drawer "Server not responding", manual sync
  ran and wrote failed History rows (one per tap — two taps were needed
  to catch the running state on camera), retry stayed red; original URL
  restored and verified in-session. PASS (log ring-wrap disclosed in the
  ledger entry; a live in-test logcat check plus an empty crash buffer
  cover the evicted span).
- QA-10 drawer & settings (U4) → header lines, address tap target,
  Settings hub subtitles, About version, enabled "Sync now" all as
  specified for the `reachable` state; mini player docked throughout;
  playback position byte-identical start→end. PASS.
- QA-11 kill & relaunch → force-stop while playing, relaunch: consistent
  state, no zombie audio — but the persisted position was NOT restored
  (FINDING 2). PASS on the run's criteria; the position defect was fixed
  afterwards (4190f3d) and device-verified in both cases before QA-9 ran.
- QA-12a storage (UI-only, no changes) → "Music folder / Folder access
  granted", "Change folder" button (not tapped), hub/card subtitles
  agree. PASS.
- QA-12b schedule (the one sanctioned change) → configured daily 02:00,
  all days, charging + WiFi conditions; snackbar "Schedule saved: Daily
  at 02:00"; native log `Background sync scheduled for Wed Oct 14
  02:00:00 EDT 2026`; job pending in `dumpsys jobscheduler`
  (SystemJobService, only TIMING_DELAY unsatisfied); prefs
  `flutter.sync_schedule` + `flutter.expected_next_sync` exactly as
  configured; force-stop + relaunch: every value persisted and the
  worker re-registered on cold start. PASS.

## FINDINGS

1. **QA-5 console criterion — harness-induced framework noise
   (dispositioned PASS, no code change).** Raw logcat prints `E flutter`
   (space), not `E/flutter` (slash) — the original grep undercounted.
   Every line in the affected windows is the same debug-build-only
   assertion "Looking up a deactivated widget's ancestor is unsafe" via
   `_ImageState.didChangeAccessibilityFeatures` — uiautomator's
   accessibility-toggle racing image deactivation. 100%
   `package:flutter` frames, zero app-code lines. Console criterion for
   QA-6+ re-baselined to "no E-flutter lines attributable to app code";
   release builds do not contain the debug check.
2. **QA-11 position not restored after kill — FIXED (4190f3d).**
   `just_audio` re-broadcasts the sequence on every playback event and
   the per-emission reset in the position tracker zeroed the row a
   restore had just read. Fixed by resetting the persisted position only
   on a real track change (`playback_position_tracker.dart` + test);
   device-verified in both cases (position survives kill; a real track
   change still resets).
3. **QA-2 observation — search artist-row count (2cc100c).** Artist rows
   in search are now counted with the invariant-21 membership rule.

Also during the run: a stuck TalkBack tutorial wedged the device at
17:45Z on 2026-10-13 (ledger INCIDENT entry) — resolved, and a fix
subagent retry followed; QA-11 was deliberately moved ahead of QA-9 so
the position fix could be verified before the unreachable-state test
inherited the 4190f3d build.

## SERVER INTEGRITY

Read-only throughout, except the two sanctioned round-trips, each done
as the approved plan required: QA-7's single play-count (original
recorded, restored, restore verified via GET) and QA-6's synced
play-counts (each affected track's `play_count` + `time_played` recorded
via GET before the sync, restored via `PUT`, each restore verified via
GET). No playlist edits or deletions, no rating changes. QA-9's
unreachable test targeted a closed port (:9999) only — zero writes
possible, none made.

## GIT STATE

Four local commits were made during the run (per the QA plan, local
main, no push) and were **pushed to origin on 2026-10-14 on user
instruction** (`612fd5a..4190f3d`):

- 7cbf356 Remove F-Droid metadata — the project publishes GitHub releases only
- 15f1a24 Version-control the overnight pipeline process definition
- 2cc100c Count search artist rows with the invariant-21 membership rule
- 4190f3d Reset the persisted position only on a real track change (QA-11)

`main` is in sync with `origin/main`. A pre-release 0.2.0 should include
them (notably 4190f3d).

## SCHEDULED SYNC STATE (for the follow-up)

QA-12b left the overnight schedule **ENABLED** (orchestrator decision,
recorded in the ledger): daily at **02:00** (device-local, EDT), all
seven days, "Only when charging" ON, "Only on WiFi" ON. Verified armed:
`flutter.expected_next_sync` = `1791957600000` (Wed Oct 14 02:00:00
EDT 2026); the WorkManager job (OneTimeWorkRequest, tag `sync-task`,
via SystemJobService) was pending with only TIMING_DELAY unsatisfied —
re-verified by the orchestrator after the subagent finished. The app is
already on the battery-optimization ignore list
(`isIgnoringBatteryOptimizations == true`), so there is no Doze
exemption to grant.

### FOLLOW-UP: validate the overnight fire (the one open item)

1. On the phone: Sync → History. Expect a **new** History row for the
   scheduled run — a "Sync Completed" row stamped ~02:00 EDT with the
   scheduled-sync chip (NOT "Manual"), dated after
   `1791957600000`. The two failed "Manual" rows from QA-9 remain below
   it until superseded by design (see NOT VERIFIED).
2. If it fired: also confirm the drawer status line flipped to
   "Last synced …" (it reads the newest History row via
   `describeLastSync`, `lib/presentation/widgets/app_drawer.dart:30`)
   and that the next run is re-queued (native log:
   `Background sync scheduled for <next 02:00> …`;
   `flutter.expected_next_sync` advanced by ~24 h).
3. If it did NOT fire: the app has a missed-sync path — a red banner
   "Scheduled sync at … may have been skipped. Check battery
   settings." Diagnostics in order: (a) `flutter.expected_next_sync`
   still `1791957600000` (never ran) vs advanced (ran, re-queued);
   (b) logcat for `BackgroundSyncWorker` lines — "Skipping scheduled
   sync - device is not plugged in" means the charging condition failed
   (the worker checks "plugged in" at start; the phone must have been
   charging at 02:00 — WiFi is a WorkManager constraint, UNMETERED);
   (c) `adb shell dumpsys jobscheduler` for a stale or re-queued
   `#BackgroundSyncWorker` job.

## NOT VERIFIED / KNOWN LOCAL STATE

- **The overnight fire itself** — the point of the follow-up above; the
  job is armed, the fire is not yet observed.
- **Two failed "Manual" History rows** (QA-9's unreachable-state test,
  by design of that test) remain in local history, and the drawer reads
  "Last sync failed …" until the first successful sync supersedes them.
  Designed behaviour of `describeLastSync`/history, not a defect.
- The battery-optimization prompt path (dialog + in-screen banner) was
  never rendered — the app is already exempt, so the branch is
  unexercised on this device. Its rendering is U4's; the strings and
  flow are in `schedule_config_screen.dart`.

## DEVIATIONS

- QA-5's first run returned FAIL (criterion 6); dispositioned PASS by
  the orchestrator after re-grepping all five logcats with the correct
  `E flutter` pattern and inspecting the stacks (FINDING 1). No code
  change — there is no app-side fix surface.
- QA-11 ran ahead of QA-9 (orchestrator decision, ledger entry at
  12:58Z) so its fix could land in the build QA-9 inherited.
- Console evidence for QA-10/QA-12a/QA-12b is logcat windows, not an
  attached `flutter run` — `flutter attach` was impossible on the
  pre-existing process without a force-stop, which was out of scope for
  those tests (QA-12b's own force-stop happened after its console window
  closed, per its entry).

## UNKNOWN — behaviour I could not explain

- None open. (QA-11's position loss and QA-5's console noise — the two
  things the run could not initially explain — are both resolved:
  FINDING 2 and FINDING 1 respectively.)
