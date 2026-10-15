# Widget-test program (2026-10-15) — COMPLETE (test-verified; device pass deferred to the user)

Executed per `.agent/widget-test-task.md` as three serial fresh subagent
units (A: harness + geometry guards, ending RED; B: header fix, turning it
GREEN; C: per-screen smoke tests, green only), with the orchestrator
re-running every gate itself between units. Attended variant: the user was
present; **nothing was committed**.

Subagent unit reports: `.agent/reports/unit-b-detail-header-fix.md`
(Unit B; Units A and C returned their reports to the orchestrator only).

## GO/NO-GO CHECK

What it was: the program's defining cycle — Unit A's guards end RED on the
overlap assertions **only** (harness proven by matching rects), Unit B's
fix turns them GREEN without touching the tests, Unit C adds green-only
smoke tests, and the whole suite ends green.
Did you run it: YES (orchestrator, not the subagents)
What you observed:
- Baseline (pre-A): `flutter analyze` clean; `flutter test` → `00:08 +128:
  All tests passed!`.
- Unit A gate (orchestrator): guard file `00:08 +1 -3: Some tests failed.` —
  the 3 failures are the expanded overlap assertions only, each printing
  both rects; the playlist rects match the 2026-10-13 measurement to the
  pixel (title `72.2,122 → 182.2,150` over icon `24.2,100 → 88.2,164`; the
  blocker recorded x 72–182, y 122–150 / x 24–88, y 100–164). No
  MissingPluginException / finder-not-found / timeout. Guard file runtime
  ~8 s (< 2 min cap). Full suite `00:08 +129 -3` — all 128 pre-existing
  tests green, only the 3 new guards red.
- Unit B gate (orchestrator): guard file `00:08 +4: All tests passed!`;
  full suite `00:08 +132: All tests passed!` (128 + 4). `git diff` confirms
  the guard and helper files were untouched by Unit B; the lib change is
  the three screens + one new shared widget.
- Unit C gate (orchestrator): smoke file `00:08 +11: All tests passed!`;
  full suite `00:09 +143: All tests passed!` (128 pre-existing + 4 guards +
  1 seed + 10 smoke). Guard file re-verified byte-consistent with the
  post-Unit-A state (217 lines, 7 `expectNoOverlap` calls, collapse
  sanity check at :94); helper change is one additive optional parameter
  (`pumpScreen(syncProvider:)`).

## What is TEST-VERIFIED (this program's evidence)

- **Expanded header, all three screens:** title does not overlap the
  icon / `AlbumArtTile` / `CircleAvatar` and does not overlap the meta
  text, measured on the real screens against the real FFI DB
  (`test/detail_header_geometry_test.dart`, expanded phase). Before the
  fix these assertions failed with rects matching the 2026-10-13
  measurement; after, they pass.
- **Collapsed header, all three screens:** the bar fully collapses
  (height ≤ 57, pre-asserted), the name is present inside the
  `FlexibleSpaceBar`, clears `Icons.arrow_back`, and does not overflow the
  bar's right/bottom edges (collapsed phase).
- **The fix's shape** (`collection_detail_header.dart`, invariant 47):
  `title` owns the collapsed state (`maxLines: 1` + ellipsis); the
  background row owns the expanded state, top-anchored, height-pinned,
  faded before the title sweep. Unit B's scratch mid-scroll sweep (15
  offsets per screen, since deleted) found the row opaque only while ≥ 8 px
  clear of the title; a 105-char name collapsed one-line, ellipsized to the
  bar width, clear of the back button.
- **Smoke render + key elements** for Library, Search, Sync, Schedule,
  Server config, Settings, About, History, Storage, and the Now Playing
  sheet (empty state) — one test per screen, each assertion citing its
  spec requirement or invariant (`test/screen_smoke_test.dart`).
- **SDK facts the fix was designed against** (verified against the
  Flutter 3.41.7 source): `collapsedTitle`/`collapsedTitlePadding` do not
  exist; `pinned` → `toolbarOpacity` 1.0 → title visible in every scroll
  state; default title padding start 72 / bottom 16 when
  `centerTitle: false` + leading; background at opacity 0 at full
  collapse.

## What is DEVICE-PENDING (the user's pass; no device was available to this program)

- **Both scroll states of all three detail screens on a device**, including
  the long real names named in the 2026-10-08 entry (*"Ain't No Love in
  the Heart of the City"*, *"Black Moon Rising (live from Capitol Studio
  A)"*) — open each detail screen, confirm no overlap at rest, scroll to
  full collapse, confirm again. This is the bar for closing the two
  blocker entries on device; they are marked RESOLVED on the
  widget-test-verified basis, with this deferral recorded in each entry.
- **The Now Playing sheet's loaded-track state** (artwork, origin line,
  seek bar, controls): `just_audio`'s platform channels are not mocked by
  the harness, so a `playCollection`-driven queue cannot load in a widget
  test. The sheet's empty state is test-covered; the loaded state remains
  device-verified only (it was last device-verified in Phase 8 and the
  U-phases).
- **The mid-scroll fade window on a device** — covered in the widget-test
  environment by Unit B's sweep; a real scroll on a real screen is part of
  the device pass above.
- **`flutter build apk --debug`** — not run; not a gate of this program's
  definition of done (pure Dart widget change + test additions; Kotlin
  untouched; `flutter analyze` clean).

## OBSERVED — actions taken and results seen (orchestrator, this session)

- Ran the guard file pre-fix → saw the three expanded-overlap failures
  print both rects, matching the 2026-10-13 recorded measurement (harness
  proven per protocol §4 before trusting the red).
- Verified the collapsed-state claim against the SDK source
  (`flexible_space_bar.dart:323-329`: 72 px default start padding with
  leading) rather than trusting either the 2026-10-08 device observation
  or the subagent's summary.
- Ran the guard file post-fix → 4/4; ran the full suite → 132/132, then
  143/143 after Unit C.
- Confirmed by `git diff` that Unit B touched only the three screens + one
  new widget, and that Unit C's only helper change is an additive optional
  parameter.
- Read every new/changed file (helper, guards, header widget, three screen
  diffs, smoke file) before re-running gates — subagent summaries were
  treated as claims throughout.
- Verified finding F1 directly: `sync_screen.dart:33` does
  `context.read<SyncProvider>()` in `dispose()`.

## NOT VERIFIED — implemented but not exercised, and why

- The device items above (the reason they are listed separately).
- The F1 fix itself — not implemented: Unit C's brief authorized
  test-side changes only; the defect is reported (blockers 2026-10-15
  entry) and the smoke test tolerates exactly that one signature
  (message + `sync_screen.dart` in the stack), everything else still
  failing the test.

## DEVIATIONS — anything not done as the task doc specified

- The task doc's Unit B fix line names `collapsedTitle` /
  `collapsedTitlePadding`. **Those parameters do not exist in Flutter
  3.41.7** (grep of `packages/flutter/lib` finds no `collapsedTitle`).
  The doc's own caveat applied ("verify defaults against the Flutter SDK
  source rather than guessing"); the implemented shape is the one the doc's
  alternative and blockers option (b) point to: `title` owns the collapsed
  state, the background row is re-anchored out of the title zone with an
  adaptive fade. Recorded in invariant 47.
- The Now Playing sheet is covered in its **empty state** only — the task
  doc's "else" branch ("cover the empty state and record the limitation");
  the limitation is recorded in the test file's header and above.
- Unit C surfaced finding F1 (pre-existing lib defect). Per scope it was
  reported, not fixed; a new OPEN entry was added to
  `.agent/blockers.md` (2026-10-15) and the smoke test works around it with
  a tightly scoped, teardown-restored `FlutterError.onError` override.
- The 2026-10-13 and 2026-10-08 (collapsed title) blocker entries are
  marked RESOLVED on the widget-test-verified basis with the device
  deferral recorded in each entry — the task doc's definition of done
  ("device-verification explicitly deferred to the user"), not the
  protocol §3 device bar (no device was available; the deferral was agreed
  in the task doc's "Where things stand").

## BUILD

flutter analyze: `No issues found!` (0 errors, 0 warnings) — run by the
orchestrator after each unit.
flutter build apk --debug: not run (see NOT VERIFIED).
flutter test (full suite, final): `00:09 +143: All tests passed!`

## Review pass (2026-10-15, agentic review of PR #7)

An independent reviewer (agentic-code-review skill: grounded in the pinned
3.41.7 SDK source + docs-mcp, gates re-run by the reviewer: analyze ✓,
143/143 ✓, CI ✓) returned **approve-with-nits** with five findings. All five
were applied before merge:

1. `blockers.md` 2026-10-13 entry pointed at the deleted probe file and
   told the reader to run it — now points at the promoted guard.
2. `blockers.md` F1 entry misquoted the framework error ("…is not
   allowed" / provider check) — actual 3.41.7 message is "…is unsafe."
   (`widgets/framework.dart:5050`), check at `framework.dart:5046`.
3. Seeded playlist ids 1/2 collided with the v3 migration fixture's
   `Brass`/`Soul` in the shared file: a false-quiescence window under CI
   load could have doubled the counts the smoke tests read. Playlists now
   seed at ids 101/102 (guard updated to `playlistId: 101`), and the two
   exact-count smoke assertions are shared-state-tolerant
   (`findsWidgets` / `textContaining`).
4. The F1 `FlutterError.onError` tolerance now matches the framework's
   exact error summary, not a message prefix.
5. The degenerate-branch comment in `collection_detail_header.dart`
   describes both guarded conditions.

The reviewer's clean findings (all SDK claims verified against source,
fade math re-derived and sound, guards provably fail on the recorded
pre-fix rects, harness race/FakeAsync discipline intact, invariants 47–49
consistent with the code) are recorded in its report.

## UNKNOWN — behaviour you could not explain

- None new. Unit B's one UNKNOWN (why a `Row` containing an `Expanded`
  column stretches to the full incoming height instead of shrink-wrapping)
  is resolved: flex children are laid out with the Row's incoming
  cross-axis constraints (`flex.dart` `Flexible`/`FlexFit` docs,
  :140/:390/:480), and a `MainAxisSize.max` Column fills them — consistent
  with the 220 px the Unit B session measured on the album header. The
  `SizedBox(height: rowHeight)` pin makes it moot in the header either way
  (invariant 47).
