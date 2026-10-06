# Phase 3 — Correct statistics

Date: 2026-09-24
Session: opencode (Qwen), branch `audio_player`, base commit `b58c95c phase 2`.

Files changed:
- `lib/presentation/services/playback_stats_recorder.dart` (new)
- `lib/presentation/services/audio_handler.dart` (user-intent signal)
- `lib/main.dart` (recorder wiring, shared `LocalDatabaseRepository`)
- `android/app/src/main/kotlin/dev/educoder/owntone_sync/MainActivity.kt` (deleted
  dead `recordPlayEvent` / `recordSkipEvent` channels and `trackPlaybackEvent()`)

```
PHASE 3: COMPLETE

GO/NO-GO CHECK
  What it was: spec §7 steps 3+4 — (3) play a track to completion (or past the
               threshold) and confirm exactly +1 play / 0 skips on the OwnTone
               server; (4) start another track, listen ≥2s (well below its
               threshold), press next, and confirm exactly +1 skip / 0 plays.
               Also the first real exercise of the Phase 0.5 gate removal:
               counts must actually move end-to-end (recorder → pending_events
               → sync worker → server).
  Did you run it:        YES
  What you observed: server counts before/after (GET /api/library/tracks/{id}
               on 192.168.1.13:3689, the data the web UI displays):

                 track (id)      before        after         diff
                 Warrior (1546)   p13 s2        p14 s2        +1 play
                 Bloodshot (1547) p10 s2        p11 s2        +1 play
                 Acousticon (1548) p10 s3       p11 s3        +1 play
                 Peace (1549)     p10 s1        p11 s1        +1 play
                 Da Bomba (1550)  p14 s0        p14 s1        +1 skip
                 Heart (1877)     p10 s2        p11 s2        +1 play
                 Moon Zooz (1879) p13 s1        p14 s1        +1 play
                 Providence (1881) p9 s1        p10 s1        +1 play
                 SMTD (3176, 7:36) p3 s0        p4 s0         +1 play
                 Blues (1194)     p11 s2        p12 s2        +1 play (boundary, see DEVIATIONS)
                 Skunk (1195)     p10 s2        p10 s3        +1 skip
                 Good People (1196) p16 s0      p16 s0        none (1s listen < 2s floor)

               Every diff is exactly one event on exactly one axis. The 4-min
               cap was exercised (SMTD is 7:36; its play fired at 4:00 of
               listening, once, and its natural completion added no skip).
               time_played updated to today on all +play tracks; time_skipped
               updated to today only on the two +skip tracks; untouched
               tracks kept their old timestamps.

OBSERVED — things you did and saw, on the emulator, by hand
  - App on emulator-5554, Sync tab → "1 playlists selected", Brass row
    CHECKED; Server Configuration screen showed URL http://192.168.1.13:3689.
  - Tapped the play button on the "The Warrior Comes Out to Play" row in the
    Brass detail screen → the row's button label flipped to "Playing", and
    after 1:39 the "Playing" marker moved to the next row (Bloodshot) —
    auto-advance with no user input.
  - Playback ran unattended across the queue; the "Playing" marker advanced
    row by row (Bloodshot → Acousticon → Peace → Da Bomba) as each track
    finished.
  - Tapped "Play track" on "Heart on my Sleeve" mid-list → Da Bomba (then
    current, ~90s in) stopped and "Heart on my Sleeve" became the current
    track (its row button showed "Playing").
  - On PlayerScreen (opened from the mini player), "Skunk" showed 1:30/6:01
    and advancing; pressed Next → "Good People" became current; pressed
    play/pause → position held at 0:01 (frozen across three dumps 8s apart).
  - Tapped the Sync button on the main screen → worker logcat:
    "Syncing 10 events" followed by one "Syncing track <id>: +X plays, +Y
    skips" line per track (1546,1547,1548,1549: +1P; 1550: +1S; 1877,1879,
    1881,3176,1194: +1P) and "Event sync completed: 10 events synced, 0
    events deleted". A second sync after the Skunk skip logged "Syncing
    track 1195: +0 plays, +1 skips".
  - Re-read all 12 tracks' counts from the API after each sync → the exact
    diffs table in GO/NO-GO.
  - Both syncs also logged "E SQLiteDatabase: ... table sync_history has no
    column named skips_synced" (BackgroundSyncWorker.kt:678) — the history
    row insert fails; the event upload itself succeeds (worker reports
    SUCCESS, events land on the server). Root-caused; see .agent/blockers.md.

NOT VERIFIED — implemented but not exercised, and why
  - pending_events surviving app death: not simulated (no kill -9 during the
    run). Mitigated by the synchronous insert at the moment of crossing and
    by all 11 events being present in the DB when the manual syncs ran.
  - skipToPrevious (both branches), skipToQueueItem: no UI path exists for
    queue items yet (Phases 5/6) and Previous was not pressed during testing.
  - A9 error-skip (flag cleared on the error path): no playback error occurred
    during testing (all 33 files on the device opened fine).
  - repeat-one restart = new pass: the repeat button was never toggled during
    testing.
  - Background playback + notification controls: app stayed foregrounded this
    phase; A6 was verified in Phase 1 and the notification was not
    re-exercised.
  - Media-key (MEDIA_NEXT) transport control: see UNKNOWN.

DEVIATIONS — anything not done as the phase specified
  - Step 4's "press next during track 5" was run as two explicit moves
    instead: starting a new collection (Da Bomba, ~90s listen) and pressing
    Next on Skunk (1:36 listen). Same semantics, broader coverage.
  - The first skip attempt (Blues in the Attic, "next" at ~96s against a 96.2s
    threshold) crossed the threshold by a hair before the press registered,
    so it recorded a play, not a skip. The implementation behaved correctly
    at the boundary; the clean sub-threshold Next-skip was re-run on Skunk.
  - Counts were read via the server API (:3689, no auth) rather than the web
    UI (:3000): the web UI requires a login I do not have, and the API serves
    the identical fields the web UI renders (play_count/skip_count/
    time_played/time_skipped). Same source of truth, different client.
  - The sync_history schema defect (fresh installs lack plays_synced/
    skips_synced, so no history row is written) was found during verification
    and NOT fixed: it is a pre-existing schema inconsistency exposed by
    Phase 0.5, and schema changes to database_helper.dart are Phase 7
    territory per the plan's disposition table. Recorded in
    .agent/blockers.md. Phase 7 cannot verify spec §7 step 12 / story D3
    until it is fixed.

BUILD
  flutter analyze:
    1 issue found:
      info • The 'if' statement could be replaced by a null-aware assignment
      • lib/presentation/providers/sync_provider.dart:653:5
      • prefer_conditional_assignment
    (pre-existing on the clean tree — confirmed earlier this phase via
     git stash; 0 errors, 0 warnings; no issues in any new/modified file)
  flutter build apk --debug:
    Running Gradle task 'assembleDebug'...                             11.7s
    ✓ Built build/app/outputs/flutter-apk/app-debug.apk

UNKNOWN — behaviour you could not explain
  - Injected MEDIA_NEXT (adb keyevent 87) did not advance the track at
    23:23:49 while a screen tap on the same Next button worked before and
    after it. No exception in logs; cause unknown. Phase 1 verified the
    notification's own next button; this phase did not re-test transport
    controls via the notification or media keys.
```
