# Issue #21 — end-of-queue stale PLAYING projection — builder report

Run 2026-11-28, unit 2. Branch `fix/issue-21-end-of-queue-stale-projection`
off `develop@a96a864`. Spec copy `.ai-dlc/night-2026-11-28/issues/21.md`,
plan `.ai-dlc/night-2026-11-28/plans/21.md` (implemented as written;
deviations below). Builder spawn #2 (spawn #1 crashed on an infra API
failure; its uncommitted tree was reviewed as a starting point — the test
suite was rewritten where the harness was blind, see OBSERVED; its /tmp
dumpsys captures were NOT trusted as evidence, every reading below was
re-derived by this session on its own AVD).

```
PHASE: COMPLETE

GO/NO-GO CHECK
  What it was: the issue's DoD witnessed on this run's night AVD —
    end-of-queue leaves a stopped-shaped dumpsys media_session projection,
    mini player reads "Play", force-stop+relaunch stays correct, and an
    external PLAY from that state starts playback (dispatch = wiring
    witness only) — after reproducing the stale state pre-fix.
  Did you run it:        YES
  What you observed:    pre-fix (a96a864, instrumented): natural completion
    of the queue tail left state=PLAYING(3) with AudioTrack state:stopped
    and mini "Pause"; post-fix (3d2da3f): state=PAUSED(2), mini "Play",
    and `cmd media_session dispatch play` produced
    `[BTKEY] click(media) playing=false proc=AudioProcessingState.completed`
    then state=PLAYING(3) with AudioTrack state:started and the position
    advancing from 0. Verbatim rows in OBSERVED.

SUMMARY
  Root cause (code-confirmed against pinned sources, reproduced on device):
  just_audio 0.10.6's play() leaves `playing` true through completion
  (just_audio.dart:1074-1078) and its platform-event conversion preserves
  it (subscribeToEvents: playerEvent.copyWith(playbackEvent:) — playing
  rides through), so the handler's playbackEventStream listener published
  playing=true + processingState=completed, and audio_service 0.18.19
  AudioService.java:607 maps completed+playing to STATE_PLAYING — the
  stale PLAYING with nothing audible; BaseAudioHandler.click
  (audio_service.dart:3089-3105) then toggled a media-key PLAY toward
  pause. Fix: heal at the single funnel where `completed` enters the app
  — publish playing=false immediately and pause the platform (deferred one
  microtask; the inline form re-enters just_audio's synchronously-firing
  subject), and override play() to seek(0)+play when processingState ==
  completed so a resume actually moves. queueExhausted stays
  A9-error-only (invariant 24). Tests: T1-T5 on a fake JustAudioPlatform
  double (test/fake_just_audio_platform.dart, zero new dependencies, no
  network, no AudioService.init). The issue's relaunch-PLAYING leg did
  NOT reproduce at a96a864 (see UNKNOWN); restore is paused by
  construction, matching the plan's code-derived finding.

GATES (verbatim tails)
  flutter analyze:
    info • 'onReorder' is deprecated and shouldn't be used. Use the
    onReorderItem callback instead. [...] •
    lib/presentation/widgets/queue_sheet.dart:160:27 •
    deprecated_member_use
    1 issue found. (ran in 3.6s)
    (sole issue = the accepted baseline info; 0 errors, 0 warnings)
  flutter test:
    00:10 +164: All tests passed!
    (159 pre-existing + 5 new in end_of_queue_projection_test.dart)
  flutter build apk --debug:
    Running Gradle task 'assembleDebug'...                              9.2s
    ✓ Built build/app/outputs/flutter-apk/app-debug.apk
  Kotlin gate (./gradlew :app:testDebugUnitTest): not required — android/
    not touched (git diff --name-only: lib/... + test/... only).
  Tool churn: none occurred (post-gate `git status` still showed only the
    three unit files + untracked .ai-dlc/.opencode, which stay unstaged).

OBSERVED — things I did and saw, on the AVD (OwnToneSyncNight28_2_API_36,
created + deleted by this unit; resolved via
`getprop ro.boot.qemu.avd_name` → OwnToneSyncNight28_2_API_36), and in the
test harness. Emulator was launched -no-audio -no-window: all authorised
local playback was silent; nothing audible anywhere. Server
192.168.1.13: every call was a GET (checked before each device step;
"server GET ok" logged).

  Harness (test-side) — before trusting the suite:
  - Ran T1-T5 on the crashed builder's tests (after extracting the fake to
    the plan's file): 5/5 pass.
  - Mutation: removed the heal block → T1/T3/T4 red, T5 green (correct —
    T5 guards restore, not heal) — but T2 PASSED. Probe (`PROBE@1` /
    `PROBE@11` scratch run, heal still removed): handler
    playing=true/completed while the mini button still read
    `[Play, Next]` after pump 1 and only flipped `[Pause, Next]` by pump
    11 → T2 was passing on the StreamBuilder's pre-first-value branch.
    Rewrote T2 with a presence control (force playing=true → must render
    Pause, then restore the healed state → must render Play). Re-ran the
    mutation: T1/T2/T3/T4 red, T5 green.
  - Mutation: removed the seek from the play() override → only T3 red.
  - Mutation: called pause inline (no microtask) → T1-T4 red with
    `Bad state: Cannot fire new event. Controller is already firing an
    event` — the handler comment's claim is witnessed, not assumed.
  - Restored the fixed file from a /tmp backup copy (never
    `git checkout -- <path>`); 5/5 green again.

  Setup (pre-fix instrumented build, worktree at a96a864 + one temporary
  debugPrint in the listener; never committed, main tree untouched):
  - Guided setup: granted Music folder via the app's SAF flow (picker →
    USE THIS FOLDER → ALLOW); server URL seeded via run-as per invariant
    53 (DEVIATIONS); selected Brass (34 tracks) in the app's Sync screen;
    sync → `Sync completed with status: success`, 34 × "Downloaded track".
  - VERIFY-LIVE-1(i) pre-fix — tapped the tail row (Mummifried 3:50):
    during play `state=PlaybackState {state=PLAYING(3), ..., active item
    id=33}`; after natural completion:
    `state=PlaybackState {state=PLAYING(3), position=230426, buffered
    position=230426, ..., active item id=33}` while
    `dumpsys audio`: `AudioTrack u/pid:10213/5701 state:stopped` and the
    mini player tooltip read "Pause" → F5 reproduced exactly.
    VERIFY-LIVE-3 witness (same session, flutter console):
    `[VERIFY21] completed-event dataPlaying=true idx=33
    updPos=0:03:50.426000` — the handler's playbackEventStream really
    receives completed while data says playing → heal placement stands
    (no processingStateStream move needed).
  - VERIFY-LIVE-1(ii) pre-fix — pressed Next on the mini player mid-play
    of the last track: dumpsys byte-identical (same `updated=1807069`
    stamp), mini still "Pause" → seekToNext() no-op confirmed; the next
    path never reaches completed (plan's note, confirmed).
  - VERIFY-LIVE-1(iii) pre-fix — `am force-stop` + `am start`: session
    `state=PAUSED(2), position=230429, active item id=33`, mini "Play".
    The relaunch-PLAYING claim did NOT reproduce at a96a864 (see UNKNOWN).
  - AC4 pre-fix (the "PLAY pauses" symptom) — from that restored-completed
    state, `cmd media_session dispatch play` twice:
    `[BTKEY] click(media) playing=false proc=AudioProcessingState.ready idx=33`
    → state=PLAYING(3) with position pinned (230436, never advanced) →
    second dispatch: `[BTKEY] click(media) playing=true
    proc=AudioProcessingState.completed idx=33` → state=PAUSED(2).
    A PLAY that plays nothing, then a PLAY that pauses — as filed.

  Post-fix (branch build via flutter run, same AVD/data):
  - D1 — played the tail row to natural completion. During:
    `state=PLAYING(3), active item id=33`. After:
    `state=PlaybackState {state=PAUSED(2), position=230432, ...}` with
    `AudioPlaybackConfiguration ... u/pid:10213/6912 ... state:stopped`
    and mini tooltip "Play". (Control vs pre-fix: same action, PAUSED
    instead of PLAYING.)
  - D2 (wiring witness only — `cmd media_session dispatch` bypasses the
    Bluetooth stack) — from the healed state: dispatch play →
    `[BTKEY] click(media) playing=false proc=AudioProcessingState.completed idx=33`
    then `state=PLAYING(3), position=2539` (advancing; buffered 78654)
    and `AudioPlaybackConfiguration ... state:started` →
    VERIFY-LIVE-2: seek(0)+play genuinely starts the platform from the
    top. Dispatch pause → PAUSED(2), position 35775 (proof playback had
    genuinely advanced).
  - D3 — healed+paused state: mini "Play" (widget dump, home route);
    `am force-stop` + `am start` → `state=PAUSED(2)`,
    `queueTitle=null, size=34` (queue restored), `active item id=33`,
    `description=Mummifried, TOO MANY ZOOZ, Brasshouse`, position 35724
    (restored at the tail-side position, invariant 46 intact), AudioTrack
    `state:idle`, mini player restored with track title + "Play".
    AC3 holds across relaunch.
  - D4a — played the second-to-last row (Show Me That Dance Called the
    Second Line, 456.8 s): at the boundary the session stayed PLAYING(3)
    and `active item id` moved 32 → 33 with position advancing from 0
    (51002 seen), zero BTKEY lines → mid-queue natural completion still
    auto-advances; the heal never fires mid-queue (A2 pinned).
  - D4b — backed up the tail file (`adb pull`, MD5
    11303d4224c0d4d62cb3af4f8f94807b, held at
    /tmp/owntone-night/unit2-retry/mummifried_backup.mp3), overwrote it on
    the AVD only with 64 KiB of /dev/urandom, replayed it from the mini
    player on the home route →
    `[OwnToneAudioHandler] PlayerException: Source error (code=0,
    index=33)` + banner "Queue ended - no more playable tracks" +
    `state=NONE(0)` (stop() idle path). The A9 error path is still
    terminal; the completion heal did not hijack it. Restored the file:
    device MD5 matches the backup (11303d4224c0d4d62cb3af4f8f94807b).
  - Played-track disclosure (run.md §Audio-safety 2): Mummifried full
    pass ×1 (D1) + ~33 s (D2) + ~51 s (after D4a advance); Show Me That
    Dance full pass ×1 (D4a). ≥threshold passes record local `play` rows
    in pending_events. These are possible future stats flushes —
    no sync-now / stats upload was triggered after any playback (last
    sync completed before the first playback); server-side counts
    untouched (zero writes, GET-only throughout).

  Host-deferred rows (run.md units-exception policy — pre-declared, never
  attempted):
  | Row | Criterion | Status | Substitute proof |
  |---|---|---|---|
  | H1 | Real head-unit/ESP32 AVRCP PLAY from the end-of-queue state | BLOCKED-PENDING-HOST-VERIFICATION | D2 dispatch witness + T3 dispatch test + pre-fix/ post-fix dumpsys contrast |
  | H2 | Real BT AVRCP play/pause from lock screen (A6 BT row) | BLOCKED-PENDING-HOST-VERIFICATION | T1+T3 + D1/D2 dumpsys witnesses |

  NOT VERIFIED — implemented but not exercised, and why
  - Real Bluetooth delivery (rows H1/H2 above) — device policy.
  - The Pixel-6 / v0.3.4+23 variant of the relaunch-PLAYING leg — not
    reproducible from this codebase; handed to the host session (UNKNOWN).
  - Notification transport buttons in the healed state (out of AC scope;
    invariant 55 already documents they bypass click()).

DEVIATIONS — anything not done as the plan specified
  - T2 pumps MiniPlayer directly under a Provider (the helpers' pumpScreen
    pumps whole screens with channel mocks; only the controller seam is
    needed), and overrides PlaybackController.positionData because
    AudioService.position needs the static handler installed by
    AudioService.init, which the plan's harness rules exclude. T2 also
    gained a presence control (OBSERVED) — a §4 requirement, not plan text.
  - The heal's `_audioPlayer.pause()` is deferred one microtask (the plan
    said a guarded pause(); inline re-enters the synchronously-firing
    subject — witnessed). Publish stays immediate as the plan requires.
  - Server URL seeded via run-as (invariant 53) after the emulator's text
    field refused `input text`; the URL field is not the path under test.
  - Test playlist = Brass (34 tracks); "last track" = the app's tail row
    (Mummifried, app row order). Tracks played disclosed above.
  - Fake platform lives in test/fake_just_audio_platform.dart (the plan's
    file set) — the crashed builder had it inlined in the test file.

UNKNOWN — behaviour you could not explain
  - The issue's "stale projection survives app relaunch" leg did not
    reproduce on the pre-fix build at a96a864: after force-stop+relaunch
    the session read PAUSED(2) with mini "Play". The code says why it
    can't (no `playing` column; restore never sets playing — plan
    APPROACH), so the filed behaviour belongs to the v0.3.4+23 line the
    reporter observed and its mechanism is not derivable from this tree.
    Not chased (prior-diagnosis rule); host rows carry the Pixel-6 variant.
  - Pre-fix dispatch play #1 printed proc=ready (not completed) at the
    click while the tail was already at the end — restore leaves
    processingState ready at the tail and the platform moved to completed
    between the two dispatches (the second click saw completed). Expected
    shape from restore's seek + platform ENDED event; not traced deeper.

RESOLVED FINDINGS
  F1 (major, r1) → fixed via PR-body edit by orchestrator; verified by
    fixer — see ## Review round 1. (F2 minor not assigned to the fixer.)

ASSUMPTIONS
  - "Stopped-shaped" = PAUSED(2) (plan A1); PLAY-from-completed = resume-from-top (A4); no queueExhausted/notice on natural completion (A3); completed only at tail (A2, pinned by T4/T5/D4a).
  - Server URL seeded via run-as (invariant 53) — URL field is not the path under test.
  - Emulator `-no-audio` satisfies the audible-playback constraint; played tracks (Mummifried ×~2.5 passes, Show Me That Dance ×1) may sit in local pending_events — never flushed (no sync after playback; zero server writes).
  - Pre-fix instrumented build existed only in a /tmp worktree (temp debugPrint, never committed); crashed spawn #1's /tmp evidence treated as untrusted, everything re-derived.
  - Fake placed in plan's separate file (crashed builder had it inlined).
```

---

## Review round 1 (2026-11-27, PR #22)

Reviewer r1 (comment 7230378028): 0 blocker / 1 major (F1) / 1 minor (F2) /
0 nit. Assigned to fixer: F1 only (F2 minor not assigned — orchestrator
accepted it as transcription-only at ledger 2026-11-27T23:48:54Z).

### F1 (major) — PR body carried a GitHub closing keyword (`Closes #21`); merging would auto-close #21, defeating run.md §Merge/close policy for units 2–4 (host rows H1/H2 need the issue open)

**fixed via PR-body edit by orchestrator per the finding's suggested fix;
verified by fixer.** The orchestrator owns PR-body writes (the body was
orchestrator-authored; the fixer role's only GitHub action is `git push`),
so the keyword removal was effected by `gh pr edit 22`; this round's job was
verify-by-evidence on the live body and record.

Verification (fixer, 2026-11-27T23:55Z) against the live body
(`gh pr view 22 --json body -q .body` saved to /tmp/owntone-night/pr22-body.txt):

```
$ grep -n -i -E '(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[[:space:]]+#[0-9]+' /tmp/owntone-night/pr22-body.txt
(no output — grep exit 1: no closing keyword immediately precedes any #<number> reference)
$ tr '\n' ' ' < /tmp/owntone-night/pr22-body.txt | grep -o -i -E '.{20}(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[[:space:]]+#[0-9]+.{10}'
(no output — grep exit 1: same check with newlines flattened, so keyword-at-EOL + reference-at-next-BOL is covered too)
$ grep -n -E '#[0-9]+' /tmp/owntone-night/pr22-body.txt
1:Issue: #21 (must NOT auto-close — see merge policy note at end) — end-of-queue left a stale `PLAYING` media-session projection (`playing=true` + `processingState=completed` → `dumpsys media_session` `state=PLAYING(3)` with AudioTrack stopped, mini player "Pause", external PLAY toggling to pause).
25:Issue linkage: #21 — no closing keyword used on purpose. Per this run's merge policy for units 2-4: the issue must remain OPEN after merge; host rows H1/H2 stay tracked there until the host session runs them; the host session then performs the closure.
```

The two boundary lines (the only `#<number>` references in the body):
line 1 opener `Issue: #21 (must NOT auto-close — see merge policy note at
end) — …` — token immediately before the reference is `Issue:`; the
substring `auto-close` sits *after* the reference and is followed by `—`,
never by `#` (and `auto-close`/`closing`/`closure` are not GitHub closing
keywords anyway). Line 25 linkage `Issue linkage: #21 — no closing keyword
used on purpose. …` — token immediately before the reference is `linkage:`.
Keyword occurrences elsewhere in the body (`pre-fix`, `Post-fix`) are
hyphenated prose, never adjacent to a reference. PR title checked too
(keyword grep exit 1). Verdict: merging PR #22 as it stands will NOT close
#21; closure stays with the host session per policy. No residual
keyword+reference found → not blocked.

Fixer gate re-run (role step 4) on unchanged head 9fd6517 — no code/test
changes this round; Kotlin gate n/a (`android/` untouched, diff file set
unchanged):
- `flutter analyze` → `1 issue found. (ran in 3.3s)`; sole issue = accepted
  baseline info `queue_sheet.dart:160:27 deprecated_member_use`; 0 errors,
  0 warnings.
- `flutter test` → `00:10 +164: All tests passed!`
- `flutter build apk --debug` → `✓ Built build/app/outputs/flutter-apk/app-debug.apk`
- Tool churn: none — post-gate `git diff` empty on `analysis_options.yaml`
  and `android/gradle.properties`; `git status` shows only the pre-existing
  untracked `.ai-dlc/`/`.opencode/` (never staged).

DEVICE: none — F1 is GitHub metadata; no behaviour change → no AVD created,
no server call beyond none (zero HTTP this round), no device touched.
