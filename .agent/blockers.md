# Blockers and discovered defects

> **Currently open (newest first):**
>
> - 2026-10-17 — Now Playing tap-to-rate overlay did not appear on tap during
>   the screenshot pass (several attempts, `input tap` and `input swipe`, taps
>   confirmed delivered via the queue button). Needs investigation; not touched
>   here (docs/screenshots session, no `lib/` edits).
> - 2026-10-15 — `SyncScreen.dispose` does an ancestor lookup
>   (`context.read<SyncProvider>()`) on a deactivated element — a debug-only
>   FlutterError at tree finalization, first surfaced by the widget-test
>   program's smoke tests (finding F1). Tolerated in exactly that signature in
>   `test/screen_smoke_test.dart`; fix is a one-line lib change, unmade because
>   the program authorized test-side changes only.
> - 2026-10-10 — a sync run started against the previous server can complete
>   after `setServerUrl` and establish `reachable` for the new, unprobed host
>   (the fetch path is generation-fenced; the worker-completion write is not).
>   Quiet-icon-only artifact; U2's offline sync guard treats it as
>   non-blocking (invariant 43). Fix needs the Kotlin URL-stamp fence.
> - 2026-10-08 — Now Playing sheet leaves ~205 logical px blank at the bottom.
> - 2026-10-06 — "Playlist 4 of 3" during the artwork pass (cosmetic).
> - 2026-10-06 — playback started on its own after a long sync (cause unknown;
>   needs logcat, not source reading).
>
> Resolved: the 2026-10-17 launch-dead-end entry was fixed and
> device-verified 2026-10-19 on `fix/launch-dead-end` (the launch load is
> now `reloadAll()`, all four categories, so an empty default tab cannot
> hide populated ones; guards in `test/browse_provider_launch_test.dart`,
> invariant 51). The 2026-10-17 History-date "PMt" entry was fixed and
> device-verified 2026-10-18 on `fix/history-date-pmt` (quoted `'at'`
> literal + `yyyy` in the two patterns; guard in
> `test/history_timestamp_test.dart`, invariant 50). The 2026-10-13 and
> 2026-10-08 (collapsed title) detail-header
> entries were fixed and **widget-test-verified** by the 2026-10-15
> widget-test program (guards in `test/detail_header_geometry_test.dart`);
> their device pass is explicitly deferred to the user (no device was
> available to the program). The 2026-10-08 search entry (the field never
> rendered — search was entirely unusable) was fixed and device-verified the
> same day. The 2026-10-02 scheduled-sync entry (two compounding defects, both
> present in released `main`) was fixed and device-verified on 2026-10-03.
> Everything dated 2026-09 is resolved; the 2026-10-02 star-rendering entry is a
> struck misobservation, not a defect.

## 2026-10-17 — RESOLVED (device-verified 2026-10-18): History date renders "PMt" instead of "at" (cosmetic)

### Resolution (2026-10-18, fix/history-date-pmt)

The two patterns now quote the literal and use the 4-digit year
(`history_screen.dart`): `DateFormat("EEEE 'at' h:mm a")` and
`DateFormat("MMM d, yyyy 'at' h:mm a")`. The formatter was extracted from
the widget to the pure top-level `formatSyncTimestamp(timestampMs, {now})`
and all four branches are pinned by `test/history_timestamp_test.dart`
(cites this entry), including the "this week" branch with a Monday
timestamp against a pinned Wednesday `now` — on a Sunday that branch is
unreachable on device (startOfWeek == today). Device-verified 2026-10-18 on
emulator-5554: the Oct 9 row renders "Oct 9, 2026 at 3:12 PM" (0× "PMt" in
the screen dump; a "Yesterday at …" control row renders correctly).
Process note: the device's natural rows were wiped by a storage-induced
reinstall during the pass (INSTALL_FAILED_INSUFFICIENT_STORAGE → flutter
auto-uninstall), so the Oct 9 row was re-seeded locally as an exact
reproduction of this entry's row (allowed for rows with no natural row) —
see `.agent/reports/fix-history-date-pmt-report.md`. Guard: invariant 50.

Observed on the History screen during the 2026-10-17 screenshot pass: the
oldest sync entry rendered

```
Sync Completed
Oct 9, 26 PMt 3:12 PM
1 playlists • 33 tracks downloaded
```

The word "at" is being mangled into "PMt".

**Root cause:** `history_screen.dart` builds two of its four date strings with
`at` **inside** the DateFormat pattern:

```dart
return DateFormat('EEEE at h:mm a').format(date);        // :75 (this week)
return DateFormat('MMM d, y at h:mm a').format(date);    // :78 (older)
```

In a `DateFormat` pattern, a bare `a` is the **AM/PM marker**, not a literal.
So the `at` in the pattern is parsed as `a` (→ "PM" for a 3:12 PM timestamp)
followed by the literal `t` — producing "PMt". The `y` in the :78 pattern is
also the 2-digit year, so the intended "Oct 9, 2026 at 3:12 PM" comes out as
"Oct 9, 26 PMt 3:12 PM".

The other two branches are correct: `:61-69` (today) builds plain Dart strings,
and `:72` (yesterday) puts "at" in the **interpolated** Dart string
(`'Yesterday at ${DateFormat('h:mm a').format(date)}'`), where it is a literal.

**Fix direction:** quote the literal in the pattern —
`DateFormat("EEEE 'at' h:mm a")` and `DateFormat("MMM d, yyyy 'at' h:mm a")`
(`yyyy` if a 4-digit year is wanted, `y` if 2-digit is acceptable). Verify the
"this week" and "older" branches each render "at", not "PMt".

**Not fixed here:** this was a docs/screenshots session with no `lib/` edits in
scope. Cosmetic — the timestamp is still readable, but it is the History
screen's headline text for anything older than yesterday.

---

## 2026-10-17 — RESOLVED (device-verified 2026-10-19): launch dead end when the default Library tab is empty but other categories have data

### Resolution (2026-10-19, fix/launch-dead-end)

Fixed with the entry's recommended option (b): `LibraryScreen`'s launch
load (the `initState` post-frame callback) now calls
`BrowseProvider.reloadAll()` — all four categories — instead of
`loadData()` (current category only), so `hasContent` is computed from
real data on launch. The tab-switch path and the post-sync refresh keep
`loadData()`. Device-verified on emulator-5554 against the gold-seed DB
(genuine 10-16 pull of this entry's state: `synced_playlists` empty,
33 `synced_tracks`): RED reproduced with the pre-fix build ("No music
yet", no TabBar, no data); GREEN with the fixed build — the TabBar with
all four tabs rendered on first launch, no relaunch and no sync, the
Playlists tab showing its genuine empty list, and Artists/Albums/Tracks
showing the seeded Brass data. Guard:
`test/browse_provider_launch_test.dart` (cites invariant 51). Option (a)
(DB-backed `hasContent`) was not needed — (b) proved right on device.
See `.agent/reports/fix-launch-dead-end-report.md`.

Observed on emulator-5554 during the 2026-10-17 screenshot pass. The device DB
held 33 synced tracks (Artists/Albums/Tracks all populated) but an empty
`synced_playlists` table. On launch the app showed the **"No music yet"** empty
state and offered **no way in**: no TabBar, no list, no route to the data that
was sitting in the database. (The session recovered by repopulating
`synced_playlists`; see the report for the fixture detail.)

**Mechanism:** `lib/presentation/providers/browse_provider.dart`:

- `loadData()` (:104) loads **only the current category**
  (`_loadCategory(_currentCategory)`). `LibraryScreen` calls it from `initState`,
  so at launch only the default tab (**Playlists**) is loaded; the other three
  lists stay empty.
- `hasContent` (:70) is `_playlists.isNotEmpty || _artists.isNotEmpty ||
  _albums.isNotEmpty || _tracks.isNotEmpty` — an OR over **all four** in-memory
  lists.

So when the default tab is empty and the others have not been loaded, every
list is empty and `hasContent` is `false` — even though Artists/Albums/Tracks
hold rows. `LibraryScreen` then swaps the whole tabbed body for the empty state,
and (as the 2026-09-27 entry established) the empty state has **no TabBar**, so
there is no in-app control that would trigger `setCategory` → `loadData()` for
another category. Dead end; only a relaunch into a different default tab, or a
sync, recovers.

**Why this is not the resolved 2026-09-27 defect.** That entry was the
*after-sync* case — the library not refreshing once a sync finished — and Phase 7
closed it by refreshing `BrowseProvider` on sync completion (and adding
`reloadAll()` for the wiped-library case). This is the *launch* case: no sync is
in flight, the data is already in the DB, and nothing re-evaluates `hasContent`
across categories. The Phase 7 refresh never fires because no sync completes.

**When it is reachable:** any state where the default tab's table is empty but
another category is not — e.g. all playlists deselected/removed while tracks
remain, a partial or interrupted sync, or (as here) a DB whose
`synced_playlists` is empty while `synced_tracks` is not. Not the common
happy path, but a real trap with no in-app escape.

**Fix direction (two options):** (a) make `hasContent` reflect the database, not
the four in-memory lists — e.g. a cheap "does any category have rows" count — so
an empty current tab can't hide populated others; or (b) on launch load all
categories (call `reloadAll()`, not `loadData()`) so `hasContent` is computed
from real data. Either way, verify: seed a DB with an empty Playlists table but
populated Tracks, launch, and confirm the Tabbed library (not the empty state)
appears with no relaunch or sync.

**Not fixed here:** docs/screenshots session, no `lib/` edits in scope.

---

## 2026-10-17 — OPEN: Now Playing tap-to-rate overlay did not appear on tap

Observed on emulator-5554 during the 2026-10-17 screenshot pass. The README and
the player UX spec both document: on the Now Playing sheet, **tap the artwork to
reveal the five-star rating strip** (`player_screen.dart`
`_AlbumArtWithRating`, `onTap: _toggle` → `_visible = true`, rendered under
`if (_visible && _loaded)`). During the pass, tapping the artwork did **not**
reveal the overlay.

**What was tried (all on a stable, paused track with artwork confirmed loaded):**

- `adb shell input tap 640 688` (artwork centre) — no change.
- `adb shell input swipe 640 688 640 688 120` (a 120 ms press) — no change.
- Pixel diff of a pre-tap baseline vs post-tap capture: the artwork region was
  byte-identical (centre brightness 89.2 before and after); a `Colors.black38`
  pill over this artwork would have darkened it measurably. It did not.
- **Tap delivery was confirmed working on the same sheet** in the same session:
  tapping the Queue button opened the queue, and tapping Play/Pause toggled
  playback. So the sheet receives taps; the artwork specifically did not toggle.

The code path reads correctly (`_toggle` sets `_visible`, `_loadRating` sets
`_loaded` unconditionally after its DB read, and `item.id` is a numeric track id
so `_trackId` is non-null), which is why this is flagged as *needs
investigation* rather than a confirmed defect — but the on-device behaviour
repeatedly contradicts the documented behaviour, and the two are exactly the
class of discrepancy this project has lost sessions to (a negative/absent result
is a claim about the feature **and** the harness).

**Suggested next step:** reproduce with a hot-reloaded debug build and read the
`E/flutter` console during the tap (attach `flutter run`, per the rendering-bug
trap in AGENTS.md); add a `debugPrint` in `_toggle`/`_loadRating` to confirm
whether the tap reaches `_toggle` and whether `_loaded` is true. Only then
decide whether it is a hit-test issue (the `Hero`/`ClipRRect` wrapping the
`GestureDetector`), a `_loaded`-never-set issue, or a harness artifact.

**Not fixed here:** docs/screenshots session, no `lib/` edits in scope. The
README's "Ratings" section documents the intended behaviour and was left
unchanged; this entry records that the behaviour did not reproduce on device.

---

## 2026-10-15 — OPEN: `SyncScreen.dispose` ancestor lookup on a deactivated element (finding F1)

Found by the widget-test program's Unit C smoke tests
(`test/screen_smoke_test.dart`), not on device.

**Symptom:** pumping `SyncScreen` in a widget test and then unmounting the
tree surfaces

```
FlutterError: Looking up a deactivated widget's ancestor is unsafe.
```

reported (not rethrown) from `BuildOwner.finalizeTree`, interrupting the
unmount. Debug-only; release is unaffected (the lookup in a deactivated
element is an assertion, and the listener it removes is on a provider the
tree is disposing anyway — no functional impact observed in the test).

**Mechanism:** `lib/presentation/screens/sync_screen.dart:33` —
`dispose()` calls `context.read<SyncProvider>().removeListener(
_loadPendingEventCount)`. `context.read` is an
`InheritedWidget` ancestor lookup; inside `dispose` the element is already
deactivating, which the framework's own debug check
(`_debugCheckStateIsActiveForAncestorLookup`, `widgets/framework.dart:5046`,
Flutter 3.41.7) asserts on. The framework's
own error hint: capture the dependency in `didChangeDependencies` via
`dependOnInheritedWidgetOfExactType` and call `removeListener` on the saved
reference (or drop the read if the listener is only informational).

**Why it is not fixed here:** the widget-test program authorized
test-side changes only (no `lib/` edits in Unit C). The smoke test
tolerates **exactly** this signature (message + `sync_screen.dart` in the
stack), everything else still fails the test, and it pops the route inside
the test body so the fallout is contained — see the header of
`test/screen_smoke_test.dart`.

**Fix direction (one line, when a `lib/` change is in scope):** save the
`SyncProvider` reference in `didChangeDependencies`
(`dependOnInheritedWidgetOfExactType`), remove the listener from the saved
reference in `dispose`. Then delete the tolerance block from the smoke test.

**Verification when fixed:** `flutter test test/screen_smoke_test.dart`
green with the tolerance removed; full suite green.

---

## 2026-10-13 — RESOLVED (widget-test-verified 2026-10-15; device pass deferred to the user): collection detail headers — the title overlaps the icon and track count (expanded)

Reported from device use (playlist screen). **Confirmed by widget-test
geometry measurement on all three collection detail screens**. The
measurement probe was `test/scratch_playlist_header_probe.dart`
(deliberately not a `*_test.dart` — see the race note under Verification).
It was promoted to the permanent guard `test/detail_header_geometry_test.dart`
by the 2026-10-15 widget-test program and deleted; the guard's pre-fix red
rects matched the numbers below. Run the guard, not the probe.

### Resolution (2026-10-15, widget-test program)

Fixed by Unit B of the program and verified by Unit A's promoted guards
(`test/detail_header_geometry_test.dart`, which went 1/4 → 4/4 on this
fix; the expanded failures' printed rects matched the measurements below,
e.g. playlist title `72.2,122 → 182.2,150` over icon `24.2,100 → 88.2,164`).
The fix is the shared `lib/presentation/widgets/collection_detail_header.dart`
(see invariant 47): one layout owner per visible scroll state — the
`FlexibleSpaceBar` title (`maxLines: 1`, ellipsis) owns the collapsed bar,
and the icon/artwork + meta row is the expanded-state owner, top-anchored,
height-pinned, and faded out before the title sweep reaches it.
**Device verification of both scroll states on all three screens (including
the long real names) is explicitly deferred to the user** — no device was
available to the program (scope agreed in `.agent/widget-test-task.md`).

### Mechanism

All three screens use the same shape
(`playlist_detail_screen.dart:71-103`, `album_detail_screen.dart:95-143`,
`artist_detail_screen.dart:79-111`):

```dart
SliverAppBar(
  expandedHeight: 180 / 260 / 200,
  pinned: true,
  flexibleSpace: FlexibleSpaceBar(
    title: Text(name),                          // layer A
    background: Padding(24, 24, 24, 16) →
      Align(bottomLeft) → Row(icon, 16px, meta) // layer B
  ),
)
```

`FlexibleSpaceBar` lays out `background` and `title` as **independent layers
of one Stack**; nothing reserves space between them. The background content
is anchored bottom-left of the flexible space (24 px in, 16 px up), and in
the expanded state the bar's title is also placed at the bottom of the
flexible space (measured: always 30 px above the bar's bottom edge, for all
three `expandedHeight`s). The two independent layouts claim the same
bottom-left region, so the name paints over the icon and the track count.

### Measured (expanded, initial load; logical px, 800×600 test surface)

| screen (expandedHeight) | title | icon / art | meta |
|---|---|---|---|
| playlist (180) | x 72–182, y 122–150 | x 24–88, y 100–164 | x 104–233, y 120–144 |
| artist (200) | x 72–204, y 142–170 | x 24–96, y 112–184 | x 112–403, y 136–160 |
| album (260) | x 72–182, y 202–230 | x 24–144, y 74–194 | x 160–358, y 228–244 |

- **playlist:** title∩icon = true (16 px horizontal), title∩count = true
  (78 px of the name over the count) — the reported defect.
- **artist:** title∩avatar = true (24 px), title∩meta = true (92 px).
- **album:** title∩art = false (8 px clear), title∩meta = true (2 px, with a
  short fixture name — a wider real name collides more). Most latent, same
  defect.
- In all three, the icon and the meta do **not** overlap each other (the
  Row's 16 px gap holds); every overlap is the title against them. The
  horizontal extent of the collision is name-width dependent.

### Same root pattern as the 2026-10-08 entry, at the other scroll extreme

The 2026-10-08 entry (title over the back button, collapsed) is the same
defect class: the `FlexibleSpaceBar` title is a layer that reserves no space
against anything else the bar shows — here the bottom-left background
content (expanded), there the toolbar's leading slot (collapsed). A fix that
addresses only the expanded layout leaves the collapsed overlap open (and
vice versa); **verify both states on all three screens**.

### Why the suite missed it

Every existing test is pure logic, DB migration, or static source guard —
there are no widget tests, so nothing measures layout. This is the defect
class a widget geometry guard closes: the probe asserts
`!title.overlaps(icon)` and `!title.overlaps(meta)` on the real screens in
the expanded state, plus the collapsed-state title/back-button assertion the
2026-10-08 entry calls for. It is the first concrete candidate for a widget
test in this repo.

### Fix direction

Give the header content one owner. Either (a) put the name inside the
`background` layout (e.g. a `Column` with the name above the icon/meta row)
and pass a `collapsedTitle` for the collapsed bar, or (b) keep `title` and
re-anchor the background content away from the title zone. Option (a)
concentrates the whole header in one layout, which makes this overlap class
structurally impossible; it still needs the 2026-10-08 entry's collapsed-bar
fix (`titlePadding` + `maxLines: 1` + ellipsis) to close both entries at
once. Spec requirement: B3 (`player-ux-spec.md` — header with
artwork/title/metadata, collapsing on scroll).

### Verification

The promoted probe must pass **expanded and collapsed** on all three
screens. Device check: open each detail screen and confirm no overlap at
rest, then scroll until the bar is fully collapsed and confirm again
(long-name playlists/albums/artists — the library has names long enough to
trigger the collapsed variant; see the 2026-10-08 entry).

**Race note for whoever promotes the probe to a permanent `*_test.dart`:**
the probe's seed step deletes and recreates
`.dart_tool/sqflite_common_ffi/databases/owntone_sync.db` — the same file
`database_migration_test.dart` drives through parallel isolates
(`DatabaseHelper` hard-codes the file name). A permanent geometry test must
seed without deleting the file first (check-and-insert, not recreate), or
the suite will be flaky under `flutter test`'s default file parallelism.

---

## 2026-10-10 — OPEN: a sync completion started against the previous server can establish `reachable` for the new host

Found in the agentic re-review of PR #3 (`ux-u1`). The fetch path's state
writes are fenced by the `_fetchGeneration` token (invariant 40), but the
worker-completion write — `sync_provider.dart:370`,
`_connectivity = ConnectivityState.reachable` on a `success`/`partial`
completion — is the one remaining unfenced state write: a run started
against the previous server (manual `startSync` or scheduled) that
completes after `setServerUrl` establishes `reachable` for the new,
unprobed host.

**Why it is milder than the fetch race the fence closes:** the path only
ever sets `reachable` (quiet icon, no banner, no red), and the next fetch
re-probes and corrects the state. The visible artifact is the app-bar icon
flipping from neutral to "Sync" until then.

**Why it is not fenced with the same token:** the worker runs in the
background (possibly from a previous app session) and the completion event
carries no server URL, so the provider cannot tell which address a run
belongs to. Fencing it needs the worker to stamp its URL into the
completion event — a Kotlin change.

**Carried into U2 — accounted for (Phase U2, decision D2):** the U2 offline
sync guard reads `lastProbeResult`, not the raw state, and treats a stale
`reachable` as non-blocking: a completion that far is only reachable if the
run got to a server, so a route existed; at worst the manual attempt fails for
a real reason and that row is the same class of record the sanctioned
`unreachable` retry writes (invariant 43). The alternatives — a
probe-before-sync (adds up to the 10 s connect timeout to every sanctioned
retry) and a fence (needs the worker to stamp its URL into the completion
event, a Kotlin change) — were both rejected for a "small, low-risk, ships
alone" phase. **The defect itself stays open:** the unfenced
worker-completion write still establishes `reachable` for a new, unprobed
host; the fix is the Kotlin URL-stamp fence described above.

---

## 2026-09-28 — RESOLVED: the two 2026-09 entries were fixed and device-verified in Phase 7

- **2026-09-24 schema defect:** fixed by the v5→v6 migration
  (`database_helper.dart` `oldVersion < 6`): adds the two columns only when
  absent, deletes the orphaned `sync_history_playlists` children, creates
  `playback_state`. Verified in all three migration shapes and a real sync
  afterwards (history row written with non-null counts; server diff
  +14 plays / +4 skips). See `.agent/invariants.md` entry 8.
- **2026-09-27 empty-state dead end:** fixed by Phase 7 item 2
  (`LibraryScreen._onSyncCompleted` → queue reconcile +
  `BrowseProvider.loadData()`). Verified on a genuine fresh install
  (`pm clear`): empty state → configure URL → grant folder → load playlists →
  select Brass + Soul → sync 88 tracks → Library shows both playlists with
  **no app restart**. See `.agent/invariants.md` and the Phase 7 report.

Both entries below are kept as history.

---

## 2026-09-24 — `sync_history` missing `plays_synced`/`skips_synced` on fresh installs (found in Phase 3) — **RESOLVED 2026-09-28 in Phase 7**

**Symptom (observed on emulator-5554 during Phase 3 verification):** every sync
fails to write a history row:

```
E SQLiteDatabase: android.database.sqlite.SQLiteException:
table sync_history has no column named skips_synced (code 1 SQLITE_ERROR):
... INSERT INTO sync_history(...,skips_synced,...,plays_synced,...) ...
  at dev.educoder.owntone_sync.DatabaseHelper.insertSyncHistory(DatabaseHelper.kt:167)
  at dev.educoder.owntone_sync.BackgroundSyncWorker$doWork$2(BackgroundSyncWorker.kt:678)
```

The event upload itself succeeds (the error is caught; the worker reports
SUCCESS and the events are uploaded). But no `sync_history` row is written, so
the History screen shows nothing and `plays_synced`/`skips_synced` can never be
read back.

**Root cause:** the Dart schema is inconsistent between fresh installs and
upgrades.

- `lib/data/database/database_helper.dart` `_createDB` (fresh installs,
  version 5) creates `sync_history` **without** `plays_synced` /
  `skips_synced`.
- The `oldVersion < 3` migration adds those two columns, but it only runs for
  DBs that pre-date v3.
- The Kotlin worker (`android/.../DatabaseHelper.kt:161-162`) opens the same
  `owntone_sync.db` and, since Phase 0.5 made `playsSynced`/`skipsSynced`
  unconditional (always non-null), always includes both columns in the INSERT.

So on any fresh install the INSERT always fails. Before Phase 0.5 the columns
were included only when the (then-removable) event-tracking toggle was on,
which is why the defect stayed latent.

**Why this is not fixed in Phase 3:** Phase 3's go/no-go is the play/skip
counts on the OwnTone server, and those verified correct. Fixing this means a
schema change to `database_helper.dart` (add the columns to `_createDB` plus a
version-6 migration that must not double-add columns on v3-migrated DBs) — the
disposition table assigns `database_history`/`database_helper.dart` revisions
to Phase 7, and the binding constraints say not to modify the sync pipeline
beyond the named additive changes.

**Affected checks:** Phase 0.5's deferred half-verification ("newest
sync_history row has non-null plays_synced") and spec §7 step 12 / story D3
(History shows plays and skips uploaded per sync run). Phase 7 must fix the
schema before it can verify step 12.

**Not affected:** event recording, event upload, server counts — all verified
working in Phase 3.

---

## 2026-09-27 — Library never refreshes after a sync; first sync leaves a dead end (found during Phase 6 setup) — **RESOLVED 2026-09-28 in Phase 7**

**Symptom (observed on emulator-5554, fresh AVD):** installed the app, granted
the folder, selected Brass plus one other playlist, and synced. The sync
succeeded — 95 files on disk under `/sdcard/Music/tracks` — but the Library
screen still showed the "No Music Synced" empty state with no tracks anywhere.
Force-stopping and relaunching the app made the whole library appear
immediately, so the data was in the database the entire time.

**Root cause:** `LibraryScreen` calls `BrowseProvider.loadData()` **only in
`initState`** (`lib/presentation/screens/library_screen.dart:38-46`). Nothing
listens for sync completion, so the UI holds whatever it read at startup.

**Why the first sync is the worst case, and not just "a stale list".** When
`BrowseProvider.hasContent` is false, `LibraryScreen` replaces the entire tabbed
body with the empty state. Switching tabs is what would otherwise trigger a
reload — `setCategory` calls `loadData()` — but with the empty state rendered
there are no tabs to switch. A first-time user therefore reaches a state with
**no in-app route out of it**: sync completes, the screen still says "No Music
Synced", and only killing and reopening the app recovers. It reads as a broken
install rather than a stale list.

**Where it gets fixed:** Phase 7 item 2 already requires "On sync completion,
refresh `BrowseProvider`" (stories C2/C3), so no new work needs scheduling — but
that item is written in terms of keeping a *populated* library current. Whoever
implements it must confirm the **empty → populated** transition specifically,
on a genuinely fresh install, without restarting the app. A refresh that only
reloads list contents will incidentally fix this because `hasContent` is
re-evaluated on rebuild — but it must be verified, not assumed.

**Not affected:** the sync pipeline, the database, file download, or playback.
Purely a UI refresh gap.

---

## 2026-10-02 — AFFECTS RELEASED `main`: scheduled sync chain can die permanently and cannot be revived from the UI — **RESOLVED 2026-10-03 on `audio_player` (device-verified)**

Two separate defects that compound. Both exist in released **v0.1.8** on `main`,
not just on `audio_player`. Found during the Phase 8 hardware pass on a physical
device; the code was then confirmed identical on `main`. Fixed on `audio_player`
2026-10-03 (a main hotfix would collide with the imminent merge); see the
"Fix + verification" section at the end of this entry.

Neither is caused by the refactor. Both are candidates for a fix released
independently of this branch.

### DEFECT-2 — saving a schedule enqueues nothing on Android 12+

`MainActivity.registerBackgroundSync` builds a `OneTimeWorkRequest` with **both**
`setInitialDelay(delayMillis, …)` and `setExpedited(…)`. WorkManager rejects that
combination: `.build()` throws

```
IllegalArgumentException: Expedited jobs cannot be delayed
```

on API 31+. The source comment reads *"Use OneTimeWorkRequest with calculated
delay and expedited flag"* — the author intended both, not knowing they are
mutually exclusive.

Consequences, all silent:

- The throw lands **before** `enqueueUniqueWork(..., ExistingWorkPolicy.REPLACE, …)`,
  so nothing is enqueued **and** nothing existing is replaced.
- It is swallowed by the enclosing `try/catch`, so the UI reports success.
- Enabling a schedule therefore does not start it.
- Changing a schedule's time does not take effect until **one sync later**,
  because `REPLACE` never runs and the old job survives. The worker's
  `scheduleNextSync` reads `flutter.sync_schedule` from prefs afterwards and
  picks up the new value then.

**Why it has gone unnoticed:** `BackgroundSyncWorker.scheduleNextSync` enqueues
*without* `setExpedited`, so it works. Any completed sync chains the next one, and
the chain is self-sustaining. A user who runs one manual sync after enabling a
schedule sees correct behaviour indefinitely. **Confirmed on a Pixel 10 running the
production build: scheduled syncs appear in history and work as expected.**

**Deterministic**, reproduced on the hardware-pass device and root-caused there.

### Chain fragility — `scheduleNextSync()` is missing from the failure path

`scheduleNextSync()` is called at exactly two places in `BackgroundSyncWorker`:
the success path, and the "skipping today" path — the latter carrying the comment
*"Still queue up tomorrow's attempt - skipping today must not break the recurring
schedule."*

The `catch (e: Exception)` handler returns **`Result.failure()`** and never
re-arms. Not `Result.retry()`, so WorkManager will not back off and retry either.

**So one failed scheduled sync kills the chain permanently** — server off, router
rebooting, phone off WiFi at the scheduled minute, storage full. And because
DEFECT-2 means the settings screen cannot enqueue anything, **toggling the
schedule off and on cannot revive it.** Only a manual sync can, and nothing tells
the user that; the schedule keeps displaying as enabled.

Someone wrote the line-218 comment specifically to protect the chain against a
skipped day, and the error path drops it anyway.

### Severity

Narrower than "scheduled sync is broken" — it works fine until the first failure.
But the failure is silent, permanent, and unrecoverable through the UI, on an app
whose core promise is unattended background syncing.

### Fix sketch

- Drop `setExpedited` from the delayed request (a scheduled sync is by definition
  not expedited), or drop `setInitialDelay` and express the schedule differently.
  Do **not** keep both.
- Call `scheduleNextSync()` on the failure path too, or return `Result.retry()`
  so WorkManager retries with backoff.
- Stop reporting success from the schedule-save handler when the enqueue threw.

### Confirming it on a working device (non-destructive)

Make one scheduled sync fail — disable WiFi before the scheduled minute, or point
the server URL at a closed port and restore it afterwards. Then check whether any
scheduled sync fires again without a manual one. If the chain is dead, confirmed.

### Fix + verification (2026-10-03, device: Pixel 6, Android 16 / API 36)

**The fix** (4 files):

- `MainActivity.kt` — the delayed request in `registerBackgroundSync()` no
  longer calls `setExpedited(...)`; the method now returns `Boolean` and
  `updateSyncSchedule` reports the real result. The manual "run now" request
  (no initial delay) is untouched — that pairing is legal.
- `BackgroundSyncWorker.kt` — the `catch (e: Exception)` path now calls
  `scheduleNextSync()` before `Result.failure()`, matching the success and
  skip paths.
- `sync_provider.dart` — `updateSyncSchedule` throws if the native side says
  the schedule was not registered.
- `schedule_config_screen.dart` — shows "Failed to save schedule" instead of a
  false success.

**Why re-arm rather than `Result.retry()`.** The recurring schedule is a
self-chaining one-time work: every finished run enqueues the next scheduled run.
`retry()` re-runs the same spec with backoff and only re-arms the chain if a
retry eventually succeeds via the success path — a failure outlasting the
retries (or the user disabling the schedule mid-retry) leaves the schedule dead
and unrevivable from the UI, the same state this entry describes. Re-arming is
the only choice that deterministically keeps the user's cadence.

**Verified on device (full evidence in `.agent/reports/scheduled-sync-fix-report.md`):**

1. **Arming** — saved a schedule ~50s out; the worker started at the second,
   `Trigger type: scheduled`, completed, re-armed; History row shows the
   "Scheduled" chip. Pre-fix this save threw and still reported success
   (reproduced 3× the day before).
2. **Replacement** — changed the time while a job was pending; WorkManager's DB
   held one spec at the new time (old spec gone); the new time fired, the old
   did not.
3. **Chain survival (the go/no-go)** — made one scheduled sync fail by removing
   `flutter.server_url` from prefs (the worker's outer catch threw at
   BackgroundSyncWorker.kt:305); the failure re-armed the next run, and after
   restoring the URL via the UI a subsequent scheduled sync fired and succeeded
   with no manual sync.
4. **Happy path** — every successful scheduled run re-armed the next
   (23:03 → 23:17 → 01:21 → 01:36); a genuine save shows the snackbar (pixel
   A/B: bottom bar present at +1s, gone at +5s).

**Not verified / known remaining gaps.** The "Failed to save schedule" negative
case (enqueue no longer throws in repro conditions). The closed-port / no-WiFi
failure mode from the suggestion above: by code path it is swallowed per-playlist
(BackgroundSyncWorker.kt:406–648) and never reaches the outer catch, so a dead
server is recorded as a "success" run with playlist errors — the missing-URL
condition was used for the chain test instead; the closed-port run itself was
not executed. Two adjacent pre-existing gaps remain, out of scope, backlog:
user-cancel of a running sync (CANCELLED_BY_APP → no re-arm) and setForeground
refusal (Result.failure → no re-arm) can still kill the schedule.

---

## 2026-10-02 — NOT A DEFECT: rate-sheet star rendering

The Phase 8 hardware-pass report lists "Rate-sheet star rendering (gray outline
blobs, no amber fill, row overflows right edge)" as a visual defect in the release
build.

**Retested by hand on the device: rendering is correct.** Struck — do not fix, and
do not carry it forward as a known defect.

Two reasons it was a misobservation, recorded so the same conclusion is not
re-reached:

- An **unrated** track correctly renders five grey outlines. `_starIcon` lights a
  star only when `halfStars > index * 2`, and a track whose *local* rating is 0
  shows no fill no matter what the server holds — server ratings only reach the
  local DB through a sync's reconciliation pass. The row's own read-only stars
  (shown only when `rating > 0`) are the control: amber on the row but grey in the
  sheet would be a real bug; grey in both is correct.
- The overflow claim does not survive arithmetic: 5 stars × 28 logical px + 16 px
  internal padding = 156 px, in a `MainAxisSize.min` centred `Row` inside a sheet
  with 24 px side padding. That cannot reach the right edge on any phone.

Both observations came from screencap pixel analysis — the instrument behind two
earlier false conclusions in this project (invariants 18 and 29). See
verification-protocol §4: a negative result from your own harness is a claim about
two things.

---

## 2026-10-06 — OPEN: two defects observed on a real device after upgrading to v0.2.0

Reported from first real-world use: a Pixel upgraded from v0.1.8, manual sync of
a ~1,700-track library where every file was already on the device but no artwork
had been cached.

### (a) "Playlist 4 of 3" during the artwork pass — confirmed by code read

`SyncProgressBroadcaster.kt:91` formats the sync notification as:

```kotlin
.setSubText("Playlist ${currentPlaylistIndex + 1}/$totalPlaylists • Track …")
```

and the artwork resolution pass (`BackgroundSyncWorker.kt:989`) passes
`totalPlaylists` as **both** the index and the total, because it runs after the
playlist loop and has no meaningful playlist index. With 3 playlists that renders
`3 + 1` of `3`. `syncEvents` sidesteps the same problem by passing `0, 1`.

The track counter is wrong in that phase too: it reports `tracksProcessed` /
`totalTracks` carried over from the download phase while actually working through
a different set (tracks lacking artwork).

**Fix direction:** a phase that is not per-playlist should not render a playlist
counter at all. Either suppress the sub-text for non-playlist phases, or pass a
sentinel the formatter recognises — do not paper over it with arithmetic. The
same applies to the track counter during that phase.

Cosmetic, but it is the most visible part of a long sync.

### (b) Playback started on its own after the sync completed — NOT app code

A track began playing with no user action, immediately after a ~1,700-track sync
finished.

**This is not the app calling play().** Every playback trigger in Dart was
checked: there are exactly four `play()` / `playCollection()` call sites and all
four are user-initiated (a track row tap, the mini player button, the Now Playing
button, the collection Play/Shuffle actions). `_onSyncCompleted`
(`library_screen.dart:95`) does only two things — `reconcileQueue()` and
`BrowseProvider.loadData()` — and `reconcileQueue` early-returns when nothing was
deleted, which is this case: every track was already present.

So something **external** asked the MediaSession to play. Unconfirmed candidates:
a Bluetooth device connecting and sending PLAY, a stray media-button event,
Android's media-resumption feature, or the sync foreground service ending and
leaving the media session as the active one.

**Cause unknown, and not determinable from source.** Diagnosing it needs logcat
from the moment it happens:

```
adb logcat -d | grep -iE "MediaButton|MediaSession|KEYCODE_MEDIA|audio_service|OwnToneAudioHandler"
```

That will show whether a media button arrived and from where. Do not guess at a
fix without it — this project has lost sessions to exactly that
(verification-protocol §4).

Two contextual notes: it followed an unusually long sync, so it may be scale- or
duration-dependent; and spontaneous playback is user-hostile in a way the
"Playlist 4 of 3" bug is not. Of the two, this is the one that matters.

---

## 2026-10-08 — OPEN: Now Playing sheet leaves ~205 logical px of empty space at the bottom

Reported from device use. **Confirmed from the geometry in
`reports/now-playing-overlap-sweep-report.md`**, which captured it without
noticing.

The sheet is `SizedBox(height: screenHeight * 0.92)` (`player_screen.dart`),
bottom-aligned. On the test device (1280×2856 at dpr 3.0 → **952 logical px**
tall) that is 875.8 px, spanning y **76 → 952**.

Its lowest content is the queue glyph at y **718.8–746.8** (paragraph `[81]` in
that report's verbatim sweep). Nothing is below it.

**952 − 746.8 ≈ 205 logical px of blank sheet** — about 615 physical px, ~22% of
the screen height.

**Cause:** the fixed `0.92` fraction. Phase 5 chose an explicit height
deliberately — the code comment records that a full-height child is laid out as
a full-screen page rather than a bottom sheet — but the fraction was evidently
chosen by eye and the content does not fill it.

**Fix direction:** size the sheet to its content while preserving bottom-sheet
semantics (`mainAxisSize.min` on the content column, or a layout that measures
rather than guesses). Read the existing comment before changing the height: the
constraint it describes is real, and simply deleting the `SizedBox` reintroduces
the full-screen-page behaviour.

Note this is also an argument against hard-coded screen fractions generally —
the same sheet on a shorter device may have no gap, or clip.

---

## 2026-10-08 — RESOLVED (widget-test-verified 2026-10-15; device pass deferred to the user): detail-screen title overlaps the back button when the app bar collapses

The defect the "Now Playing overlap sweep" was sent to find. It is **not** on the
Now Playing sheet — that screen has no `AppBar` and no back button at all, which
is what that sweep correctly established. It is on the **collection detail
screens**.

`album_detail_screen.dart:95-101`:

```dart
SliverAppBar(
  expandedHeight: 260,
  pinned: true,
  flexibleSpace: FlexibleSpaceBar(
    title: Text(widget.albumName),   // no maxLines, no titlePadding
```

A `pinned` `SliverAppBar` with a `FlexibleSpaceBar` title: as it collapses the
title slides into the toolbar, and the default `titlePadding` does not reserve
room for the `leading` back button. With a long name the title runs underneath
the back arrow.

The library contains names long enough to trigger it, e.g. *"Ain't No Love in
the Heart of the City"* and *"Black Moon Rising (live from Capitol Studio A)"*.

**Almost certainly present in all three detail screens** (album, artist,
playlist) — they share the pattern. Verify each rather than assuming.

**Fix direction:** set `titlePadding` to leave room for the leading widget, and
constrain the title (`maxLines: 1`, ellipsis). Verify **collapsed**, not just
expanded: the overlap only appears once scrolled.

**Process note for whoever picks this up:** the sweep that looked for this
measured 83 paragraphs and classified all 18 intersections as benign layering —
correctly — but did not then ask whether the geometry it had just captured
revealed anything *else* wrong. The empty-sheet defect above was visible in its
own output. When a targeted sweep finds nothing, inspect the layout you measured
for other anomalies before concluding there is no defect.

### Resolution (2026-10-15, widget-test program)

Two independent facts, both verified against the Flutter 3.41.7 SDK source:

1. The overlap itself does not reproduce on this SDK's defaults: with
   `centerTitle: false` and a leading widget, `FlexibleSpaceBar`'s title
   now defaults to a 72 px start padding (`flexible_space_bar.dart:323-329`),
   which clears the 56 px leading slot. The device observation above
   predates that framework default (the program's collapsed-phase guard —
   title found in the bar, clear of `Icons.arrow_back`, within the bar's
   bounds — passes on 3.41.7).
2. The fix the entry asks for is in place regardless: Unit B constrained
   the title to `maxLines: 1` + ellipsis in
   `collection_detail_header.dart`, so a long name (e.g. the two named
   above) can no longer wrap or run past the bar's right/bottom edges —
   asserted by the guard's collapsed phase, which pre-checks the bar
   actually collapsed (height ≤ 57) before measuring.

**Device verification (the long real names, fully-collapsed bar on all
three screens) is explicitly deferred to the user** — no device was
available to the program.

---

## 2026-10-08 — RESOLVED (device-verified same day): search was completely unusable — the search field never rendered

Reported from device use: search cannot be made to work at all.

**Root cause:** `search_screen.dart` passed an `Expanded` as `AppBar.title`:

```dart
appBar: AppBar(
  titleSpacing: 0,
  title: Expanded(          // <- AppBar.title is not a Flex
    child: TextField(...),
  ),
)
```

`Expanded` is a `ParentDataWidget` that writes flex parent data; it is only
legal as a direct child of a `Row`, `Column` or `Flex`, because it works by
setting layout parameters **on its parent**. `AppBar.title` is not a flex
container, so this throws at layout:

```
Incorrect use of ParentDataWidget.
Expanded widgets must be placed directly inside Flex widgets.
```

In a debug build the title slot becomes a red error widget; in a **release**
build it is an inert grey box. Either way **there is no text field**, so no
query can ever be typed and search appears totally broken.

**Everything downstream was verified correct and needed no change:**

- Navigation: `library_screen.dart:184` `_openSearch` pushes `SearchScreen`,
  wired to the app-bar `Icons.search` action at `:233-237`.
- SQL: `LocalDatabaseRepository.searchLibrary` (`:858`) is correct — pulled the
  live device DB (93 tracks) and ran its exact query for `pickett`:
  `SELECT COUNT(*) FROM synced_tracks st WHERE LOWER(st.title) LIKE '%pickett%'
  ESCAPE '\' OR …` → **13 rows**.
- Wiring: `_onChanged` debounces at 300 ms, `_search` calls `searchLibrary` and
  `setState`s; `_buildBody` handles empty-query, searching, null, no-results
  and grouped-results.

**Fix applied:** removed the `Expanded`, leaving the `TextField` as the title
directly. `titleSpacing: 0` already does the intended job — the title slot
receives the width left over after `leading` and `actions`. A comment above the
title records why an `Expanded` must not come back. Swept `lib/` for the same
misuse elsewhere (`title:`/`leading:`/`child: Expanded`): no other occurrences.
`flutter analyze` clean.

**Verified on device 2026-10-08** by the user: the search field renders,
accepts input, and returns results. Closed.

**Why no earlier phase caught it.** `flutter analyze` cannot see it: it is a
runtime parent-data contract, not a type error. Phase 6's verification used
`uiautomator` dumps, which report a node tree whose shape looks plausible even
when the subtree is an error widget. This is the third defect in this project
whose signature is "visible only in the `E/flutter` console" — see invariant 29
and the Phase 8 blank-sheet entry.

**Plan coverage gap worth noting:** `.agent/ux-refactor.md` mentions search in
three places (the screen inventory, the §2 comparison, and §5's deliberate
decision not to change modal-vs-tab) and every one of them **assumes it works**.
No phase U0–U4 would have touched this file. The UX review inherited the
assumption rather than exercising the screen.
