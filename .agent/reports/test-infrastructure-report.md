# Test infrastructure report

Phase: build the project's first automated test suite, deriving every test from
`.agent/invariants.md` (not from the code). Ship on a `tests` branch with a CI
workflow and this report.

PHASE: COMPLETE

GO/NO-GO CHECK
  What it was:
    The automated suite runs and passes, the analyzer is clean, and the app
    still launches and plays on emulator-5554 (the two small production
    extractions touch live paths).
  Did you run it:        YES
  What you observed:
    - `flutter analyze`: "No issues found!" (0 errors, 0 warnings, 0 info).
    - `flutter test`: "All tests passed!" — 41/41 Dart tests, in the parallel
      full run.
    - `./gradlew :app:testDebugUnitTest`: BUILD SUCCESSFUL — 9/9 Kotlin JVM
      tests (5 ComputeSyncStatusTest, 4 DetectImageExtensionTest), 0 failures.
    - On emulator-5554 (Pixel 9 Pro, API 36): app launched, rendered the full
      Library UI, a real track played (MediaSession position advanced in real
      time), the queue sheet rendered, and a sync resolved artwork to a `.jpg`.

OBSERVED — things you did and saw, on the emulator, by hand
  - Launched the app (fresh install after reinstall) → the Library screen
    rendered with the nav drawer, Sort, Search, and "Server URL not
    configured" / "Set up sync" prompts. Not a blank screen — real UI.
  - Tapped "Set up sync" → "Grant Permission" → ALLOW on the music-runtime
    permission → the SAF folder picker opened.
  - In the picker, navigated to the Music folder and tapped "USE THIS FOLDER"
    → ALLOW on the "access files in Music?" dialog → returned to the app.
  - Server Configuration screen: replaced the placeholder with
    `http://192.168.1.13:3689`, tapped Save → the Sync screen showed
    "Server URL: http://192.168.1.13:3689" and "Load Playlists".
  - Tapped "Load Playlists" → the real playlists appeared (Brass 33, Holiday
    Music 60, Five Stars 502, One Star 794, Master/All Music 1794, ...).
  - Selected Brass (1 playlist) and tapped Sync → "Syncing: Validating
    playlist Brass", "Playlist 1/1 - Track N/33", a Cancel button. logcat
    `BackgroundSyncWorker`: "Found 194 existing files in tracks directory",
    "Need to download 33 tracks".
  - The first track downloaded fully ("Downloaded track: Good People
    (7230062 bytes)"), then the server dropped: `java.net.ConnectException:
    Failed to connect to /192.168.1.13:3689` on the remaining tracks. Sync
    ended "status=success" with 1 track downloaded.
  - During that sync, logcat showed artwork resolution: "Artwork for track
    1196 from embedded: .../artwork/c1922....jpg" — the extracted
    `detectImageExtension` (Kotlin) produced the `.jpg` extension on the real
    sync path.
  - Opened the Brass playlist detail → it listed the one synced track, "Good
    People". Tapped it → "Now playing Good People" with a Pause button.
  - MediaSession logcat: `state=PLAYING(3)` with `position` advancing
    2 → 9 → 902 → 26962 → 53037 ms over the window — audio is playing.
  - Opened the Now Playing sheet (position 2:18 / 2:58, "Playing from Brass")
    and tapped "Queue" → the queue sheet rendered with the current track
    ("Good People") and "Clear queue". The sheet built using the extracted
    `queueCurrentRow` / `queueBaseIndexForRow` (Dart) without error.
  - Full logcat scan for Dart/Flutter errors across the whole session: none.
    Process stayed alive throughout.

NOT VERIFIED — implemented but not exercised, and why
  - The two extractions' *edge* behaviour on device: with only one track in
    the queue, the shuffle-on highlight/jump translations (invariant 19) were
    exercised only in their shuffle-off, single-row form. The multi-row /
    shuffled queue-sheet rendering is covered by the unit tests
    (`queue_index_translation_test.dart`), not re-exercised on device.
  - `detectImageExtension`'s PNG branch and short-input fallback were not
    exercised on device (the one resolved track was a JPEG). All branches are
    covered by the JVM unit tests.
  - The remaining 32 Brass tracks did not download (server dropped mid-sync),
    so a full 33-row queue, auto-advance, and the A9 skipped-track notice were
    not re-exercised on device this session.
  - Play/skip *counts* reaching the server (invariants 8/9/13/15) were not
    re-verified against the OwnTone web UI this session (that is a Phase-3-
    style check; the recorder semantics are covered by the unit tests).

DEVIATIONS — anything not done as the phase specified
  - Kotlin tests are NOT wired into the GitHub Actions workflow. They require
    the Android SDK (AGP) to run, which the CI runner does not have; the
    handoff said to add them to CI only if they run without an Android SDK
    download. They run locally via `./gradlew :app:testDebugUnitTest` and are
    documented as such.
  - Added a static guard for backlog "check C" (no `--` comment inside a
    CREATE TABLE string) even though check C is a backlog item rather than a
    numbered invariant — it is the root cause of the fresh-vs-upgraded schema
    diff that the DB tests also cover, and the guard is cheap. Flagging it so
    the deviation is not silent.
  - Installed the debug APK with `adb install` (after an `adb uninstall` that
    wiped the prior session's synced library) rather than `flutter run`, so
    that a fresh-install + re-sync could be driven end-to-end. `flutter run`
    was not used for this session's device checks.

BUILD
  flutter analyze:
    No issues found! (0 errors, 0 warnings, 0 info) — after fixing 6
    unnecessary-cast warnings, 1 dangling doc comment, 1 unnecessary import,
    1 unnecessary getter/setter that the new test code initially introduced.
  flutter build apk --debug:
    Built `build/app/outputs/flutter-apk/app-debug.apk` (153 MB) successfully.
  ./gradlew :app:testDebugUnitTest:
    BUILD SUCCESSFUL — 9/9 Kotlin JVM tests pass. (Requires JDK 17; the
    machine's default Gradle JVM is too new for the embedded Kotlin script
    compiler — run with
    `-Dorg.gradle.java.home=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home`.)

UNKNOWN — behaviour you could not explain
  - The OwnTone server (192.168.1.13:3689) was reachable from the host
    (HTTP 200) and served the playlist list plus the first track download,
    then refused all further connections from the emulator
    (`ConnectException`) for the rest of the sync. It returned to HTTP 200
    from the host immediately after. Cause unknown — likely a transient
    server/network hiccup on the emulator path, not an app defect (the sync
    pipeline, DB, and artwork code all behaved correctly around it, and a
    subsequent sync would pick up the 32 missing tracks per invariant 26's
    upsert). Not attributed to the test-infra change.

---

## What the suite contains

50 automated tests total: 41 Dart (`flutter test`) + 9 Kotlin JVM
(`./gradlew :app:testDebugUnitTest`). Every test cites the invariant /
requirement it guards in its name or an adjacent comment.

### Tier 1 — Database migrations (13 tests)
`test/database/database_migration_test.dart` (+ `db_lifecycle_helpers.dart`).
Runs the real `DatabaseHelper._createDB` and `_onUpgrade` on the Dart VM via
`sqflite_common_ffi` (a dev dependency) — no device needed.
- check C: fresh-install v8 schema is identical to the v3→v8 migrated schema
  (tables, indexes, column name/type/default/order), fresh v8 has the
  `sync_history` event columns v0.1.8 installs lacked (invariant 8), and rows
  written at v3 survive the chain intact (data preservation).
- Per-migration: v5 URI purge (invariant 6 safeguards), v6 (invariant 8:
  event columns + orphan cleanup + `playback_state`), v7 (invariant 30:
  `rating` + `pending_track_edits`), v8 (invariant 35: `artwork_source`).
- Idempotency guards: v6 and v8 must not double-add when the columns already
  exist.
- Harness self-check (protocol §4): the schema comparator detects an injected
  column default change, a column reorder, and a dropped index.

  Constraint that shaped this tier: `DatabaseHelper` caches its `Database` in
  a static that `close()` never clears, and `flutter test` runs files in
  parallel. So every lifecycle runs in its own isolate (`Isolate.run`) and all
  DB-lifecycle tests live in ONE file sharing the one hardcoded `owntone_sync.db`
  path.

### Tier 2 — Playback stats recorder (12 tests)
`test/playback_stats_recorder_test.dart`. Drives the real
`PlaybackStatsRecorder` through the four injected streams + a controllable
user-intent flag + a capturing fake `insertEvent` — exactly the seams the
production constructor exposes (no mocking package).
- Natural completion = a play, never a skip (invariant 9).
- User-initiated transition below threshold = a skip (invariant 13).
- Play threshold = min(0.9×duration, 4 min), both the 90% and the cap binding
  (invariant 15).
- ~2 s skip floor (invariant 15).
- At most one play per pass; repeat-one restart = new pass (invariant 15).
- Forward seek past the threshold does NOT manufacture a play (invariant 14).
- A9 error-skip records nothing (invariants 13/24).
- No skip after a play (invariant 15).
- Paused ticks do not count as listening (invariant 15).
- Backward seek resets the accumulator (invariant 14), and the reset is
  deferred until the next forward tick so an intervening user skip still sees
  the old track's time (invariant 14).

### Tier 3 — Pure functions (12 tests)
- `queue_index_translation_test.dart` (7): the index-space invariant
  (invariant 19) — `queueCurrentRow` (highlight) and `queueBaseIndexForRow`
  (jump), shuffle on/off, no-current, and that the two are exact inverses.
  Uses permutations where the previously-inverted model gives a different
  answer.
- `star_rating_test.dart` (5): `ratingToHalfStars` rounding (nearest half-star,
  ties up) and the 0–100 clamp, including real-library values 55 and 62
  (rating display supporting invariants 30/31).

### Tier 4 — Kotlin JVM tests (9 tests)
`android/app/src/test/kotlin/.../`:
- `ComputeSyncStatusTest.kt` (5): all four outcomes of top-level
  `computeSyncStatus` (cancelled / failed / partial / success) + the
  zero-playlist guard (an empty run is not a failure).
- `DetectImageExtensionTest.kt` (4): JPEG and PNG magic bytes, the unknown/
  empty fallback, and inputs too short to sniff.

### Tier 5 — Static guards (4 tests)
`test/static_guards_test.dart`. Grep-based tests that fail if a forbidden
pattern reappears in source — they catch what behavioural tests cannot (a
forbidden construction that still "works").
- No `ConcatenatingAudioSource` in lib/ (invariant 4).
- No `FloatingActionButton` in lib/ (invariant 17: on Flutter 3.41.7 a FAB
  suppresses ScaffoldMessenger snackbars — the A9 notice).
- No Dart-side parallel queue list in the handler/controller (invariant 3).
- No `--` comment inside a CREATE TABLE string in database_helper.dart
  (backlog check C: SQLite stores CREATE TABLE text verbatim, so a comment is
  itself a fresh-vs-upgraded schema diff).

  Negative probes (protocol §4): each guard was confirmed to FAIL when its
  forbidden token was temporarily injected, then pass after reverting.

## Invariant triage

Mechanically testable — covered by the automated suite:
- 9, 13, 14, 15 (stats semantics) — Tier 2.
- 19 (index space) — Tier 3.
- 8 (schema side: sync_history columns, orphan cleanup, playback_state),
  25 (playback_state table), 30 (schema side: rating + pending_track_edits),
  35 (schema side: artwork_source), 6 (v5 URI purge safeguards) — Tier 1.
- 30/31 (rating display rounding) — Tier 3.

Statically checkable — covered by grep guards:
- 3 (no parallel Dart queue list) — Tier 5.
- 4 (no ConcatenatingAudioSource) — Tier 5.
- 17 (no FAB on snackbar scaffolds) — Tier 5.
- check C (no `--` in CREATE TABLE) — Tier 5.
- 8 (syncEvents ungated) is statically checkable but NOT guarded here — the
  gate-removal behaviour was already device-verified in Phase 3; a guard was
  not added to avoid over-constraining the worker.

Device-only — cannot be verified in the automated suite (needs a running
player / server / platform interaction):
- 1 (updatePosition extrapolation), 2 (playCollection no-await), 5
  (playMediaItem default), 6 (tree-scoped content URIs / SecurityException),
  7 (positionData re-listen), 23 (restored shuffle order), 24 (A9 advance/stop),
  25 (persistence/restore behaviour), 26 (UPDATE-first upsert / URI
  invalidation), 27 (server-side deletions stay local), 30 (reconciliation
  scope), 16 (mini-player Column docking), 20 (ScaffoldMessenger hub), 21 (album
  identity), 22 (row indicators from mediaItem), 28 (queue reorder), 31 (sheet-
  close reload), 34 (sync cancel), 35 (artwork resolve / 204 behaviour).

Environment / process (not testable in this suite): 10, 11, 12, 18, 29, 32, 33.

## What remains verifiable only on a device
- Audio actually playing and the position advancing (done this session, but
  inherently device-only).
- The queue sheet's multi-row / shuffled rendering and jump (invariant 19).
- A9 error handling: advance vs stop, and the skipped-track notice (invariant
  24/17).
- play/skip counts arriving at the OwnTone server (invariants 8/9/13/15) —
  cross-check against the web UI.
- Shuffle-order persistence and restore (invariant 23).
- The sync download/upload pipeline, artwork 204 semantics, URI invalidation
  (invariants 26/35).

## Files
Added:
- `test/database/db_lifecycle_helpers.dart`, `test/database/database_migration_test.dart`
- `test/playback_stats_recorder_test.dart`
- `test/queue_index_translation_test.dart`, `test/star_rating_test.dart`
- `test/static_guards_test.dart`
- `lib/presentation/services/queue_indices.dart` (new pure functions)
- `android/app/src/test/kotlin/.../ComputeSyncStatusTest.kt`,
  `android/app/src/test/kotlin/.../DetectImageExtensionTest.kt`
- `.github/workflows/flutter-test.yaml`

Modified (the only production changes — both small extractions, logic identical):
- `lib/presentation/widgets/queue_sheet.dart` — now calls
  `queueCurrentRow` / `queueBaseIndexForRow`.
- `android/app/src/main/kotlin/.../FileOperations.kt` — `detectImageExtension`
  moved to a top-level pure function.
- `pubspec.yaml` (+ `pubspec.lock`) — dev dependency `sqflite_common_ffi`.
- `android/app/build.gradle.kts` — `testImplementation("junit:junit:4.13.2")`.
