# Widget-test program — task definition (handoff from the 2026-10-13 session)

Process definition for adding the repo's first widget tests: detail-header
geometry guards, the header fix they force, and per-screen smoke tests.
Written to be executed by a **fresh session** with no other context, as
serial subagent units per the pattern in `.agent/overnight-pipeline.md`
(orchestrator/subagent split, fresh context per spawn, orchestrator
re-runs gates). This is the attended variant: the user is present, no
commits are authorized.

## Kickoff

Paste this as the entire first message of a fresh session started at the
repo root:

```
Read .agent/widget-test-task.md and execute it: Unit A, then Unit B, then
Unit C, each a fresh general subagent per that document. Re-run the gates
yourself between units; do not trust subagent summaries.
```

## Where things stand (2026-10-13)

- The defect is defined: `.agent/blockers.md` 2026-10-13 entry (expanded
  header: title overlaps icon and track count — mechanism + measured rects
  + fix direction) and 2026-10-08 entry (collapsed: title over the back
  button — same root pattern). Both stay OPEN until Unit B's fix is
  device-verified.
- A proven measurement harness exists:
  `test/scratch_playlist_header_probe.dart` (run explicitly with
  `flutter test test/scratch_playlist_header_probe.dart`; deliberately NOT
  a `*_test.dart` — see the race note in the blockers entry). It pumps the
  three real detail screens against a real FFI SQLite DB and prints the
  header rects; verified this session.
- Working tree (uncommitted): the new blockers.md entry; the probe file
  (renamed off `*_test.dart`); `test/scratch_bisect_probe_test.dart`
  deleted. `lib/` untouched. Suite green: `flutter analyze` clean,
  128/128 tests pass.
- **Scope agreed with the user: guards + header fix + all-screen smoke
  tests** (the largest option offered). No device was connected at
  handoff: the fix lands test-verified; the device pass is the user's
  (the protocol's bar for closing the entries).
- The spec requirement behind the guards is B3
  (`.agent/player-ux-spec.md` — detail header with artwork/title/metadata,
  collapsing on scroll).

## Hard constraints (discovered the hard way — re-derivation is expensive)

1. **FakeAsync:** `testWidgets()` bodies run under a fake event loop; real
   I/O (FFI SQLite) never completes inside them. DB setup happens in plain
   `test()` calls (real zone) that run first; pump loops must never await a
   DB future. (Comment block at the top of the probe file.)
2. **Shared FFI DB file race:** the FFI factory resolves to the fixed path
   `.dart_tool/sqflite_common_ffi/databases/owntone_sync.db`, which
   `test/database/database_migration_test.dart` drives in parallel isolates
   under `flutter test`'s default file parallelism. Test seeding must be
   check-and-insert — NEVER delete or recreate that file. (blockers
   2026-10-13, "Race note".)
3. **Header finders need scoping:** list rows below the header contain
   their own "tracks" texts and avatars. Scope all header finders with
   `find.descendant(of: find.byType(FlexibleSpaceBar), matching: ...)`.
4. **A hang with no test progress is a zone bug (constraint 1), not
   slowness.** First `flutter test` runs compile the audio stack slowly,
   but progress lines always appear. Cap suspect runs:
   `perl -e 'alarm 150; exec @ARGV' flutter test <file>`.
5. **The geometry guards are a contract, not a snapshot.** They encode the
   requirement (spec B3 + the two blocker entries), not current behaviour.
   Nobody may weaken them (shrink finders, add tolerances, remove
   assertions) to make them pass — a guard that no longer measures overlap
   is worse than none. If one looks wrong, it gets adjudicated, not edited.

## Orchestration rules (adapted from `.agent/overnight-pipeline.md`)

- One fresh `general` subagent per unit, **serial** (shared working tree —
  two concurrent agents clobber each other; AGENTS.md trap #3).
- Subagent prompts are self-contained: subagents do not see the
  orchestrator's conversation. Standing lines: read AGENTS.md first; no
  `question` tool; record ambiguity under ASSUMPTIONS in the return; no
  `git commit`/`git push`.
- The orchestrator **re-runs every gate itself** between units (a
  subagent's "green" is a claim). Gates: `flutter analyze` (0 errors, 0
  warnings), `flutter test` (full suite).
- Unit A ends **RED** (only the new overlap assertions fail); Unit B turns
  it **GREEN** without touching the tests; Unit C adds green tests only.
- Subagent return format: `SUMMARY / GATES (verbatim tails) / ASSUMPTIONS /
  BLOCKERS`.

## Unit A — helper + detail-header geometry guards (must end RED)

Create `test/widget_test_helpers.dart`:

- `initWidgetTestDb()`: sets `databaseFactory = databaseFactoryFfiNoIsolate`
  (pattern: `test/database/db_lifecycle_helpers.dart:596`). Idempotent.
- `seedDetailScreens()`: plain-async seeder, check-and-insert (constraint
  2): playlist id 101 "Brass" (2 tracks), playlist id 102 "Soul" (1 track)
  (PR #7 review fix 2026-10-15: ids 1/2 collided with the v3 migration
  fixture in the same shared file, so they moved out of the 1-3 range, as
  the track ids already were),
  album "Album X" by "Artist A" (2 tracks, one with year 1970), artist
  "Solo Artist" (1 track, album "Other Album"), 2 `sync_history` rows + 2
  `sync_history_playlists` children (one success, one partial with a
  playlist `error_message`), 1 `pending_events` row. Required NOT NULL
  columns: `test/database/db_lifecycle_helpers.dart` (`seedV3Data`) and the
  fresh-v8 DDL in `lib/data/database/database_helper.dart`. Fixture names
  must not collide with each other (no track titled "Brass").
- `makePlaybackController()`: `OwnToneAudioHandler()` +
  `TrackUriResolver()` + `LocalDatabaseRepository()` + `PlaybackController`
  (all constructible in a pure Dart-VM test; verified).
- `pumpScreen(WidgetTester, Widget screen)`: `MaterialApp` with the app's
  real light theme (copy from `lib/main.dart` `MyApp._buildApp`, incl.
  `appBarTheme: AppBarTheme(centerTitle: false, elevation: 0)`), wrapped in
  `MultiProvider` (real `SyncProvider()`, `BrowseProvider()`,
  `Provider<PlaybackController>.value`), screen pushed via Navigator above
  a simple home route so a back button exists.
- Channel-mock helper via `TestDefaultBinaryMessengerBinding`, prewired:
  `dev.educoder.owntone_sync/player` `getAppVersion` → `0.0.0-test`,
  `.../sync` (methods → sensible defaults), `.../sync_progress` (empty
  event stream), `.../events`, `.../storage`. Copy the pattern from
  `test/sync_provider_connectivity_test.dart` — study it, don't reinvent.
- Rect/overlap helpers as the probe has them.
- Document constraints 1 and 2 as comments at the top of the file.

Create `test/detail_header_geometry_test.dart` guarding
`playlist_detail_screen.dart`, `album_detail_screen.dart`,
`artist_detail_screen.dart`:

- Per screen: seed, pump pushed above home.
- **Expanded** (initial load; finders scoped per constraint 3): title text
  does NOT overlap the icon / `AlbumArtTile` / `CircleAvatar`; title does
  NOT overlap the meta text ("N tracks" family).
- **Collapsed** (drag the screen's `CustomScrollView` up ~300 px, pump):
  collapsed title does NOT overlap the leading back button; title does not
  overflow the bar (constrained by maxLines/ellipsis).
- Failure messages print the rects (like the probe).

Delete `test/scratch_playlist_header_probe.dart` (harness absorbed).

Gates: analyze clean; the guard file fails on the overlap assertions ONLY
(harness errors — MissingPluginException, finder-not-found, timeout —
mean fix the harness until the red is the assertion); full suite: every
pre-existing test passes; the guard file runs in < 2 min.

## Unit B — fix the three detail-screen headers (must go GREEN)

- Input: both blockers entries; the failing guards (the arbiter).
- **Forbidden:** modifying `test/detail_header_geometry_test.dart` or the
  helper to make assertions pass (constraint 5). If an assertion looks
  wrong: return BLOCKED with the argument; the orchestrator + user
  adjudicate.
- Fix design (blockers 2026-10-13, option (a)): one layout owner per
  header. Move the name into the `FlexibleSpaceBar` `background` as a
  `Column` above the icon/meta row (name: `maxLines: 1`, ellipsis); pass
  `collapsedTitle` (same constraints) and set `collapsedTitlePadding` so
  it clears the leading back button — verify defaults against the Flutter
  SDK source (`app_bar.dart`) rather than guessing; the guards decide.
  Keep `expandedHeight`, `pinned`, colours, and the icon/meta row (with
  its 16 px gap) unchanged. Album screen: name above the Row(art,
  meta-Column); artist: name above Row(avatar, meta).
- Gates: analyze clean; full suite green; a per-screen note on how each
  guard now passes. No commit.

## Unit C — smoke tests for the remaining screens (green only)

Pump each remaining screen with seeded representative data; assert no
render exception (`RenderFlex` overflow throws in tests — free coverage)
plus 1–2 key-element assertions derived from `.agent/player-ux-spec.md`.

Screens: `library_screen`, `search_screen`, `sync_screen`,
`schedule_config_screen`, `server_config_screen`, `settings_screen`,
`about_screen`, `history_screen`, `storage_screen`, and the Now Playing
sheet (`player_screen.dart` `showNowPlayingSheet` — first check what it
renders with an empty queue; if it needs a loaded queue, drive one through
the controller if feasible, else cover the empty state and record the
limitation).

Per-screen seams (patterns already in the suite): sync screen +
`SyncProvider` → dio-interceptor + channel mocks,
`test/sync_provider_connectivity_test.dart`; schedule →
`SharedPreferences` `flutter.sync_schedule` (JSON per the `SyncSchedule`
model) + sync channel; server config → dio probe pattern,
`test/server_probe_test.dart`; about → `getAppVersion` mock; storage →
storage-channel mock; history → seeded `sync_history` rows (helper).

No `lib/` changes: if a screen cannot render in a test environment without
one, return it as per-screen BLOCKED with evidence and cover what does
render. No goldens. One focused test per screen (render + 1–2
assertions) — this is a net for regressions, not a behaviour spec.

## Definition of done (whole program)

- `flutter analyze` clean; `flutter test` fully green, guards included.
- Blockers 2026-10-13 + 2026-10-08 entries marked RESOLVED with the
  device-verification explicitly deferred to the user (no device was
  available to this program).
- `invariants.md`: new entries for what a future session must not undo —
  (a) `FlexibleSpaceBar` `title` and `background` are independent layers;
  detail headers keep exactly one layout owner; (b) the two test-env
  constraints (FakeAsync I/O, shared FFI DB file); (c) the geometry guards
  are a contract (constraint 5).
- Report in `.agent/reports/` per `.agent/verification-protocol.md` §6,
  stating plainly what is test-verified vs device-pending.
- Nothing committed — the user decides when the work lands.
