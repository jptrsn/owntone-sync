# PHASE 8: HANDOFF — implemented, verification incomplete

Session ended by choice: the implementation is complete and builds clean, the
interactive/round-trip verification list is entirely unstarted, and the session
context was consumed by a blank-sheet debugging detour. A verified handoff
beats rushed verification (per session instruction).

## SCOPE

Phase 8 (final phase, a feature not a refactor): track ratings (0–100,
half-star steps) with a tap-to-toggle star control on the Now Playing artwork,
read-only stars on track rows + "Rate…" row-menu action, durable local
optimistic writes, and sync-side reconciliation/push in
`BackgroundSyncWorker.kt` (server wins on conflict). DB v7.

Authoritative docs: `.agent/player-ux-spec.md`, `.agent/player-refactor-plan.md`
(§3/§8), `.agent/verification-protocol.md`, `.agent/invariants.md`.

## WHAT IS IMPLEMENTED (all in working tree, uncommitted)

Dart:
- `lib/data/database/database_helper.dart` — `version: 7`. `rating INTEGER
  NOT NULL DEFAULT 0` on `synced_tracks` + `pending_track_edits` table
  (`track_id, field, new_value, base_value, updated_at`, composite PK) in
  BOTH `_createDB` and the `oldVersion < 7` migration (migration is
  idempotent: PRAGMA column check before ALTER).
- `lib/data/repositories/local_database_repository.dart` — `SyncedTrack.rating`
  (fromMap `?? 0`); `PendingTrackEditRow`; field-parameterized
  `getPendingTrackEdit` / `insertPendingTrackEdit` / `updatePendingTrackEditValue`
  (the last preserves the original `base_value` on conflict — the one-line
  mistake the plan warns about); `setTrackRating(trackId, rating)`:
  transactional; if no pending edit, base = the rating column read BEFORE the
  update, and a no-op release (value == current, no pending edit) records
  nothing; if a pending edit exists, `base_value` is left untouched.
- `lib/presentation/widgets/star_rating.dart` (NEW) — `ratingToHalfStars`
  (see rule 3); `StarRatingDisplay` (read-only, `Semantics` label
  "Rated X.X of 5"); `RatingControl` (press-and-drag, RELATIVE to the grab,
  `dx / screenWidth × 100`, snap to 10s, clamp 0–100, vertical ignored,
  `onCommit` on every release, `onDragStart`, `onTap`).
- `lib/presentation/screens/player_screen.dart` — `_AlbumArtWithRating`
  (tap artwork toggles the star overlay; 5s auto-hide, 3s after release;
  timer suspended during drag; rating loaded from local DB per track,
  reloaded on track change). Sheet: `_browseProvider` captured in initState,
  `_ratingCommitted` flag → `refresh()` on dismiss; `_onRatingCommitted`
  persists via `setTrackRating`.
- `lib/presentation/widgets/library_rows.dart` — read-only stars in `TrackRow`
  trailing (only when `rating > 0`); "Rate…" `_RowMenuAction` (after "Add to
  queue") opening a bottom sheet with `RatingControl`; optional
  `onRatingChanged` fired on sheet dismiss.
- `onRatingChanged` wired at all 5 `TrackRow` construction sites:
  `track_list_view.dart` (`provider.refresh`), `playlist_detail_screen.dart`
  (`_loadTracks`), `album_detail_screen.dart` (`_loadTracks`),
  `artist_detail_screen.dart` (`_loadTracks`), `search_screen.dart`
  (`() => _search(_query)`).

Kotlin:
- `OwnToneApiClient.kt` — `Track.rating: Int = 0`; `updateTrackRating(trackId,
  rating)` (query param, zero-byte body, like `updateTrackStats`);
  `updateTrackRatings(Map<Int,Int>)` bulk `PUT /api/library/tracks` with
  Moshi `BulkTrackUpdate`/`BulkTrackUpdateItem`, success = any 2xx.
- `DatabaseHelper.kt` — `SyncedTrack.rating` with TOLERANT `fromCursor` read
  (missing column → 0, so pre-migration DBs don't break every other caller);
  `insertOrUpdateTrack` writes `rating` **INSERT path only** (inside
  `updated == 0`, and only if the column exists); `updateTrackRating`
  (rating-only UPDATE, no-op if row missing); `getPendingTrackEdits(field)`,
  `deletePendingTrackEdit(trackId, field)`, `PendingTrackEdit`;
  `hasRatingSupport()` = table AND column both present; private
  `hasColumn(table, column)`.
- `BackgroundSyncWorker.kt` — after `syncEvents`: `ratingPassActive =
  hasRatingSupport()` (logs a warning + skips the whole pass if false);
  snapshot `pendingRatingEdits` map; per-playlist reconciliation right after
  the existing `getTracksByIds` (zero extra HTTP — both sides already in hand):
  no E, S≠local → pull; no E, S==local → nothing; E, S≠base → server wins
  (update local, delete E); E, S==base → queue push of `E.newValue`. After the
  playlist loop: coverage sweep over remaining edits (`getTrack` per row, same
  rules; normally zero rows → zero requests; row left on failure). Then one
  bulk push with per-track PUT fallback; each edit row deleted only when its
  own write succeeded. Push/sweep skipped if `syncCancelled`.

## THE FOUR DESIGN RULES (user-mandated, all in place)

1. **No one-sync lag for fresh downloads** — `rating` is added to the
   `ContentValues` only in the INSERT branch of `insertOrUpdateTrack` (a new
   row cannot have a local edit; the server value is the only truth), never
   before the UPDATE (re-download must not clobber an unpushed user rating).
2. **Guard on table AND column** — `hasRatingSupport()` checks both
   `pending_track_edits` and `synced_tracks.rating`; the whole rating pass
   skips on either missing (scheduled worker can hit a v6 schema; the
   Kotlin side never migrates).
3. **Rounding rule (state it in the report):** `ratingToHalfStars =
   round(rating/10)` half-star units, ties round up — 55 → 3.0, 62 → 3.0,
   50 → 2.5, 40 → 2.0, 100 → 5.0. Shared by display and control. **DEVIATION
   to disclose in the report:** editing a non-multiple-of-10 rating (55/62
   exist in the user's data) necessarily writes 60 or 50 to the server —
   inherent to the half-star spec, but touching such a track destroys
   precision the server currently has.
4. **200-vs-204 (correct the plan in the report):** the plan text says the
   bulk endpoint returns 204; the live server returns **200** (measured).
   Code accepts any 2xx. Also note: `GET /api/library/tracks` (collection)
   returns 400 on this server — the app does not use it (playlist-scope
   endpoint only).

## VERIFIED SO FAR (honest evidence only)

- `flutter analyze`: 0/0 on the final tree. `flutter build apk --debug`:
  succeeds (shown).
- v6→v7 migration ran on the real 95-track DB at app launch (no
  "Rating sync skipped" warning from the worker = schema present).
- First post-update sync: **pull path verified** — every server rating
  landed in the local column and rows render the stars, cross-checked
  against the server API (60→"Rated 3.0 of 5", 100→"5.0", 40→"2.0");
  rounding verified for 55 and 62 (both → 3.0).
- No-op sync baseline: the sync with zero pending edits issued **no rating
  PUTs** (worker log shows only event sync + playlist pass + completion).
- Side effect already happened: that sync also uploaded the 33 pending
  play/skip events queued from earlier verification sessions (real events).
- The Now Playing sheet renders correctly again (see root cause below).

## BLANK SHEET ROOT CAUSE (the debugging detour)

Symptom: in the Phase 8 build the Now Playing sheet opened as a pure-white
92%-height panel with NO content — not even the "No track playing" fallback —
and no Flutter exception appeared in my logcat captures. The Phase 7 baseline
(APK via `git stash` A/B test) rendered the sheet normally (48,261 non-white
px), so it was my code.

Root cause: `_AlbumArtWithRating` used `Stack(fit: StackFit.expand)` directly
as a child of the sheet's vertical `ListView` (unbounded height) →
`BoxConstraints` assertion in `performLayout` + `RenderBox was not laid out:
RenderStack` + `sliver_multi_box_adaptor: 'child.hasSize'` → the sheet body
blanked. The original `_buildAlbumArt` was a fixed-size `Image` (no Stack).

Fix: wrap the Stack in `SizedBox(width: width, height: width)` (bounded
square; comment in the code explains why). After the fix: **0 exceptions in
the attached console, sheet content 48,252 non-white px ≈ baseline 48,261.**

Why logcat looked clean: Flutter framework errors log under the tag
`E/flutter` (line format `E/flutter (pid): ...`), and my greps matched the
pattern `" flutter "` (spaces both sides) which never matches `/flutter (`.
**Lesson for the next session: for render/build diagnosis, attach the console
with `flutter run -d emulator-5554` (output to a file); don't rely on
filtered logcat greps.** (Note: `uiautomator dump` returns an empty window
while the sheet is open — position ticker delays window idle, invariant 17 —
so screencap + pixel analysis was the only observation channel, which is what
hid the exception for so long.)

## FIXED TEST SET — ORIGINALS (recorded at /tmp/owntone_verify/testset.md)

| id  | title                  | playlist | rating | play | skip |
|-----|------------------------|----------|--------|------|------|
| 874 | Your One and Only Man  | Soul     | 55     | 4    | 0    |
| 743 | Cry to Me              | Soul     | 62     | 1    | 0    |
| 1873| Black Ice              | Brass    | 60     | 21   | 3    |
| 1867| Bad Guy                | Brass    | 100    | 13   | 0    |

**Status at handoff: ALL FOUR UNTOUCHED** — re-verified against the server
API at handoff time (values above match the originals). No rating has been
written from the app yet. R3/R4 are Brass-only (confirmed absent from Soul) —
required for the sweep test.

## VERIFICATION PLAN (in order — nothing below is done yet)

Work on `emulator-5554`, OwnTone `192.168.1.13:3689`. **First**: start
`flutter run -d emulator-5554` (console to a file) so exceptions are
unmissable. Useful coordinates (1280×2856): hamburger (84,240); drawer
"Sync" (456,795); Sync button on sync screen (1086,444); mini-player tap to
open sheet (400,2685); mini-player Play button (1040,2694). Sheet content is
observable via screencap + pixel analysis (amber fill (255,193,7) for the
interactive stars; rows expose "Rated X.X of 5" in the row's
content-desc when uiautomator works, i.e. when the sheet is NOT open).

1. **Gesture first (steps 1–4), measure the mapping.** Tap artwork → stars
   appear; tap again → hide; idle ~5s → auto-hide. Press-drag right → half-star
   steps; a full screen-width sweep spans 0→5. Screen is 1280 physical px
   wide and the mapping is a ratio (`dx/width`), so **one half-star = 10% of
   width = 128 physical px**; report the measured mapping (px per half-star)
   for the user's feel judgment. Pure-vertical swipe (same x) → no change,
   gesture not lost. Release → commits (check row stars after closing the
   sheet; the sheet refreshes the library on dismiss). Drag fully left → 0
   (row stars disappear; zero and unrated render identically per spec).
   Use `adb shell input swipe x1 y1 x2 y2 <duration>` for drags.
2. **Round trip (steps 5–11)** on the fixed test set (record any changed
   play/skip side effects): rate R1 3.5★ (70) → sync → server reads 70.
   Server-side change to R2 (e.g. 40) → sync → app shows 2.0. Conflict on R3:
   server set one value, app a different one (base differs) → sync → server
   wins in both places. Offline: `adb emu network offline` (or equivalent),
   rate a track, force-stop, relaunch → rating still shown (durable local);
   restore network, sync → server gets it. Double-edit base_value: R1 — edit
   to X1, edit to X2 (no sync between); set SERVER to X1; sync → server
   (X1) must win (distinguishes correct base preservation from the
   base-overwritten bug). No-PUT no-op sync (baseline already observed once;
   re-confirm via worker log "Pushed N track rating(s)" line ABSENT).
   Playback of a rated track still works (no `content_uri` clobber).
3. **Coverage sweep (R4):** rate R4 in the app → open Sync screen → deselect
   Brass (keep Soul) → sync → the sweep must `getTrack(1867)` and push the
   edit (worker log; server rating changes) → re-select Brass, sync to
   restore selection state.
4. **Phase 7 overlap — restore-with-missing-track (list as DEVIATION in the
   report; Phase 7 precedent used DB fixtures):** play a Brass queue;
   force-stop; pull the DB (`adb shell run-as dev.educoder.owntone_sync cat
   databases/owntone_sync.db > /tmp/...` + host `sqlite3`), delete one
   queued track's `synced_tracks` row (case a: non-current track) + its
   `playlist_tracks` children; push back; launch → expect queue restored
   minus that track, same current track/position, paused. Case b: delete the
   CURRENT track's row → expect restore at the first surviving track,
   paused, no crash (drop/remap logic at
   `lib/presentation/controllers/playback_controller.dart:426-448`).
5. **Restore/confirm the four original ratings** (55/62/60/100) — set via
   `PUT /api/library/tracks/{id}?rating=N` if any test changed them, then
   GET-verify all four, and note it in the report. (They are untouched as of
   handoff; only steps 2–3 will change them.)
6. **§7B hardware checks — hand the user the steps, do NOT claim them**
   (emulator can't run them): Bluetooth/AVRCP transport control,
   headphone-unplug pause, Doze/background sync delivery.
7. **Before claiming done:** re-open `.agent/verification-protocol.md` in
   full; run the go/no-go (the reason Phase 8 exists: round trip 5–7);
   update `.agent/invariants.md` (format used there; RESOLVED CONCERNS —
   promote the `E/flutter` logcat-tag gotcha and the ListView/Stack
   StackFit.expand constraint); write the report in the exact §6 template —
   including the rounding rule (rule 3), the precision-loss DEVIATION, the
   200-vs-204 plan correction (rule 4), the fixture DEVIATION, and every
   mandatory field, no prose summarisation.

## STATE AT HANDOFF

- Working tree: 13 modified + 1 new file (list above via `git status`),
  branch `audio_player`, nothing committed. `.agent/handoff-prompt.md` has
  the user's own edit ("PHASE 8 ONLY") — not mine, don't touch.
- Emulator `emulator-5554`: the FIXED build is installed and was last
  running with a queue restored and playing; the sheet renders correctly.
  App package `dev.educoder.owntone_sync`.
- No debug vehicles left in the code (the BISECT-MARKER was removed;
  analyze 0/0 on the final tree).
- `/tmp/owntone_verify/` holds this session's screenshots/dumps/logs
  (ephemeral; testset.md is the one file that matters).
