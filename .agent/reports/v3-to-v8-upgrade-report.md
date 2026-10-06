# V3→V8 UPGRADE VERIFICATION: BLOCKED

Pre-release verification of the exact upgrade path every existing user will run:
installed v0.1.8 (`main` @ 9970b9f, DB user_version 3), populated it genuinely,
then installed the `audio_player` branch build (562e0e9, DB user_version 8)
**over the top** and verified checks A–F. Report format per
`.agent/verification-protocol.md` §6; this is a targeted verification, not a
phase, so the header names the task instead of a phase number.

---

## GO/NO-GO CHECK

What it was: checks **A + C + D together** — the app launches on a real v3
database with no migration exception (A); the upgraded schema is identical to
a fresh v8 install (C); no data was lost (D).

Did you run it: YES

What you observed:

- **A — PASS.** First launch after the over-the-top install rendered the
  Library screen (Brass / Soul rows). Zero `E/flutter` lines, zero
  `FATAL EXCEPTION`, zero SQLite/migration errors in the full first-launch
  logcat capture (`/tmp/owntone_verify/v8_firstlaunch.logcat`, 775 lines;
  capture verified to contain the app process's Flutter engine and Dart VM
  startup). No exceptions in any later capture either.
- **C — FAIL.** The upgraded database's schema is **not identical** to a
  fresh v8 install's schema. The `.schema` diff is non-empty (verbatim below,
  §C). Object inventory is identical (18 objects each, same tables and
  indexes, no missing/extra object anywhere), but two column definitions in
  `synced_tracks` diverge: `content_uri TEXT` (upgraded, from the v4
  migration's `ADD COLUMN content_uri TEXT`) vs `content_uri TEXT DEFAULT ''`
  (fresh, from `_createDB`), and `artwork_source TEXT` (upgraded, v8
  migration) vs `artwork_source TEXT DEFAULT NULL` (fresh). `sync_history`
  differs only by a whitespace artifact of the ALTER rewrite (`,` attached to
  the previous column vs on its own line) — same columns, same defaults.
- **D — PASS.** The migration itself dropped nothing: pulled the DB
  immediately after the post-upgrade launch (before any v8 sync) and every
  v3 row was present — 95/95 `synced_tracks` rows with byte-identical content,
  2/2 playlists, 95/95 `playlist_tracks` pairs, the v3 `sync_history` row
  intact with `plays_synced`/`skips_synced` NULL, both v3
  `sync_history_playlists` children intact, 0 orphans. The only delta across
  the whole session (one `playlist_tracks` pair removed) happened during the
  *post-upgrade sync*, not the migration: the server's Soul playlist lost
  "A Man and a Half" (track 2936) mid-session (server-side membership flux,
  invariant 27); the local track row is retained by design.

**Verdict: BLOCKED.** Check C failed — the upgraded schema is not identical
to the fresh one. Per the task rule ("if any of the three fails, this release
is BLOCKED"), this release is blocked on C. This is stated plainly, not as a
minor issue: the divergence is silent, it was introduced without any test
comparing the two paths (the repo has no `test/` directory at all), and it is
the same drift class — `_createDB` and the migration chain defining the same
column differently — that this check exists to catch. The functional-impact
analysis is in §C for the decision-maker: every code path currently treats
NULL ≡ `''` for these columns, so no user-visible defect was demonstrated in
this verification; the block is on the check's standard, not on an observed
breakage.

---

## OBSERVED — things I did and saw, on the emulator, by hand

- `git checkout main`, `flutter clean`, `flutter build apk --debug`,
  uninstalled the previously installed app, installed the v0.1.8 APK →
  first-launch notification-permission dialog appeared; pressed Allow.
- Sync tab showed "Storage Permission Required" → pressed "Grant Permission"
  → READ_MEDIA_AUDIO permission dialog → Allow → SAF folder picker opened
  directly in the Music folder → "USE THIS FOLDER" → "Allow" on the final
  confirmation. App advanced to "Server Not Configured".
- "Configure Server" → the URL field was **pre-filled** with
  `http://192.168.1.100:3689` (actual text, not just hint). My first two
  typing attempts interleaved with the pre-fill and produced a 52-char
  mangled value that failed validation ("Invalid URL format"); cleared via
  long-press → Select all → DEL, retyped `http://192.168.1.13:3689`, pressed
  Save, and confirmed the saved value in
  `shared_prefs/FlutterSharedPreferences.xml`
  (`flutter.server_url = http://192.168.1.13:3689`).
- "Load Playlists" fetched all 13 server playlists → selected **Brass (33)**
  and **Soul (62)** → "2 playlists selected" → pressed Sync.
- Watched the sync via `logcat -s BackgroundSyncWorker`: all 95 tracks
  genuinely downloaded (worker: "Background sync completed: 95 tracks
  downloaded in 768891ms"), including several 100 MB files.
- Pulled the DB: `PRAGMA user_version` = 3; `sync_history` had 1 row
  (status success, 2 playlists, 95 tracks, trigger manual);
  `sync_history_playlists` had 2 children with valid `sync_id=1`;
  `sync_history` had **no** `plays_synced`/`skips_synced` columns — exactly
  the v3 fresh-install shape the v6 migration must handle.
- `git checkout audio_player`, `flutter clean`, `flutter build apk --debug`,
  `adb install -r` **over the top** (no uninstall, no data clear). Verified
  the on-device DB was byte-identical to the before-capture
  (`cmp` clean; user_version still 3) before launching.
- Launched the app → the new Library UI rendered (Playlists/Artists/Albums/
  Tracks tabs; Brass 33, Soul 62) — no crash, no `E/flutter` in the capture.
- Tracks tab listed the v3-synced tracks (e.g. "A Man and a Half — Wilson
  Pickett • Wilson Pickett's Greatest Hits • 2:51").
- Tapped "A Man and a Half" → row switched to "Now playing", mini player
  docked under the list (invariant 16), media session:
  `state=PLAYING(3)`, queue size 95, metadata = that track.
- Opened the Now Playing sheet → showed the track, "Playing from All tracks",
  position reaching 2:51 / 100% at track end → the player auto-advanced to
  the next track ("Acousticon Theme"), which I then watched advance
  1:1 with wall clock (media session `position` delta 131296 ms exactly
  matched the `updated`-timestamp delta over the window) — real 1.0×
  playback on the upgraded database.
- Sync screen showed "2 playlists selected" and "2 playback events waiting
  to sync" (the first events this DB has ever carried). Pressed Sync →
  worker logged "Syncing track 2936: +1 plays, +0 skips",
  "Syncing track 1548: +1 plays, +0 skips" — 2936 = "A Man and a Half",
  1548 = "Acousticon Theme" (natural completions, zero skips — invariant 9),
  "Artwork resolution complete: 82 embedded, 1 server, 12 absent, 0 failed",
  "Background sync completed: 0 tracks downloaded in 24268ms (status=success)".
- Pulled the DB: `sync_history` row 2 = `(…, 'manual', 2, 0)` with
  `plays_synced=2, skips_synced=0` — the v3-era missing-column INSERT
  failure is gone; v3 row 1 preserved with NULLs. `pending_events` back to 0
  (uploaded). `artwork_source`: 82 embedded / 1 server / 12 none, 0 NULL —
  all 95 resolved on the first v8 sync.
- Verified artwork files on disk: the 18 distinct content-addressed files
  referenced by 83 track rows all exist in
  `/data/user/0/dev.educoder.owntone_sync/files/artwork/`, all non-zero
  (3.7 KB–108 KB).
- Force-stopped and relaunched the app (queue-restore test): the persisted
  queue came back from `playback_state` — playback resumed and the app was
  showing "Ain't No Love in the Heart of the City" as "Now playing" (the
  third track: the restored second track completed during my session). Track
  rows now show server ratings ("Rated 5.0 of 5", "Rated 3.0 of 5") pulled by
  the v8 sync.
- For check C: uninstalled, reinstalled the same APK, launched → Library
  showed the empty state ("No Music Synced / Set up sync"); the fresh v8 DB
  was created on launch (`user_version` = 8); pulled it and diffed schemas.
- Left the device on the audio_player build, launched, rendering the Library
  screen with no errors.

## NOT VERIFIED — implemented but not exercised, and why

- **Artwork rendering in the UI (pixels).** Artwork *resolution* is fully
  verified at the DB + file level (§C/F), but I could not visually confirm
  the cover images paint in rows or the player sheet: this model has no
  image input, so a screencap is unreadable to me. A human should glance at
  one album row before shipping.
- **The actual audio.** No audio capture exists on the emulator; playback is
  evidenced by PLAYING state, 1:1 position advance, track-end transition and
  auto-advance — not by hearing it.
- **v3-era event tracking** (`MediaNotificationListener`): the v0.1.8 app has
  no player, so no in-app playback existed to track; the tracking toggle is
  off by default and no other app on the emulator produces media
  notifications. The v3 fixture therefore carries no `pending_events` rows —
  expected, and it does not affect the DB shape under test.
- **Scheduled/background sync on the upgraded DB.** Only the manual sync
  path (invariant 33) was exercised. The worker's guards for a scheduled run
  hitting an intermediate schema (`hasRatingSupport`/`hasArtworkSupport`,
  `DatabaseHelper.kt:129,183`) were not exercised here because the app
  always launched (and migrated) before any worker ran.
- **Intermediate single-step upgrades** (3→4, 4→5, … in isolation) — out of
  scope by design; this verification's point is the full 3→8 jump.

## DEVIATIONS — anything not done as the procedure specified

- **Step 2 "Play a track or two" is impossible on v0.1.8 — the released app
  has no player at all.** `main`'s pubspec has no audio dependency
  (`just_audio`/`audio_service` absent), and its `PlaylistDetailScreen`
  renders rows with no play affordance; the only playback-related code is
  the external-app notification listener. I populated the v3 fixture with
  sync data only, and verified playback on the upgraded app instead (check F
  requires playback there anyway, which is a superset).
- **Check C required wiping the upgraded install** ("install the branch build
  on a wiped app"), so the final device state is a fresh, empty audio_player
  install, not the upgraded library. The upgraded database was preserved to
  the host before wiping (`/tmp/owntone_verify/v8_after_sync.db` and
  `v8_upgraded.db`).
- Fresh-install notification-permission prompts were answered "Allow" — an
  artifact of the uninstall-for-fresh-install steps, not part of the upgrade
  path (an upgrading user already granted it under v0.1.8).
- No other deviations; the OwnTone server was never written to except via
  the app's own event uploads (2 play events, the app's normal behaviour).

## BUILD

flutter analyze: `No issues found! (ran in 3.2s)` (audio_player @ 562e0e9)
flutter build apk --debug: succeeded for both `main` @ 9970b9f (v0.1.8+17)
and `audio_player` @ 562e0e9; both installed on emulator-5554.

## UNKNOWN — behaviour I could not explain

- **v3 sync re-downloaded all 95 tracks despite 194 files already on disk**
  ("Found 194 existing files in tracks directory" immediately followed by
  "0 tracks already on device"). The existing-file matcher clearly didn't
  match the pre-existing files' naming; I did not trace the mechanism (out
  of scope, and re-downloading is harmless to the test). Noted so nobody
  later "fixes" something that may be intentional.
- The worker log line "Event sync completed: 2 events synced, 0 events
  deleted" while the `pending_events` rows were in fact removed afterwards —
  the deletion evidently happens outside that log line's counter. DB state
  (0 rows) is ground truth; the log line's semantics were not traced.

---

# CHECK DETAILS

## Check A — no crash on first launch, no migration exception: PASS

- Full first-launch logcat (`v8_firstlaunch.logcat`): 775 lines,
  `E/flutter` count **0**, `FATAL EXCEPTION` **0**, no
  `SQLiteException` / `no such table` / `no such column` / migration
  strings. Capture sanity: contains the app's Flutter engine load, Dart VM
  start, Impeller init, and the rendered UI (uiautomator dump of the Library
  screen taken from the same launch).
- Post-upgrade DB pulled **before** the first launch to prove the migration
  ran from a real v3 file: byte-identical to the before-capture,
  `user_version` 3, 1 history row, 95 tracks.
- Zero `E/flutter` lines also across the entire working session
  (`v8_work.logcat`, playback + sync + relaunch).

## Check B — schema reached v8: PASS

Pulled immediately after first post-upgrade launch (file
`v8_upgraded.db`):

```
user_version: 8
synced_tracks columns:
  id, title, artist, album, album_artist, local_path, server_path,
  download_timestamp, file_size, genre, length_ms, track_number,
  disc_number, year, artwork_url, artwork_path,
  content_uri, rating, artwork_source
sync_history columns:
  id, timestamp, status, playlists_synced, tracks_downloaded,
  tracks_deleted, error_message, duration_ms, trigger_type,
  plays_synced, skips_synced
tables:
  android_metadata, pending_events, pending_track_edits, playback_state,
  playlist_cache, playlist_tracks, sync_history, sync_history_playlists,
  synced_playlists, synced_tracks
```

All required objects present: `synced_tracks.content_uri` / `.rating` /
`.artwork_source`, `sync_history.plays_synced` / `.skips_synced`, tables
`playback_state` and `pending_track_edits`.

## Check C — schema equivalence (upgraded vs fresh v8): **FAIL**

Method: fresh install of the same APK on the wiped app; DB created on first
launch (`user_version` 8); `.schema` from both databases diffed.

**Verbatim `diff` output** (`diff v8_upgraded_schema.txt v8_fresh_schema.txt`;
exit code 1):

```
33,34c33,45
<         artwork_path TEXT DEFAULT ''
<       , content_uri TEXT, rating INTEGER NOT NULL DEFAULT 0, artwork_source TEXT);
---
>         artwork_path TEXT DEFAULT '',
>         content_uri TEXT DEFAULT '',
>         rating INTEGER NOT NULL DEFAULT 0,
>         artwork_source TEXT DEFAULT NULL
>       );
> CREATE TABLE pending_track_edits (
>         track_id   INTEGER NOT NULL,
>         field      TEXT    NOT NULL,
>         new_value  TEXT    NOT NULL,
>         base_value TEXT    NOT NULL,
>         updated_at INTEGER NOT NULL,
>         PRIMARY KEY (track_id, field)
>       );
60,61c71,74
<         trigger_type TEXT NOT NULL
<       , plays_synced INTEGER DEFAULT NULL, skips_synced INTEGER DEFAULT NULL);
---
>         trigger_type TEXT NOT NULL,
>         plays_synced INTEGER DEFAULT NULL,
>         skips_synced INTEGER DEFAULT NULL
>       );
70a84,96
> CREATE TABLE playback_state (
>         id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
>         queue_ids TEXT NOT NULL,
>         current_track_id INTEGER,
>         position_ms INTEGER NOT NULL DEFAULT 0,
>         shuffle_enabled INTEGER NOT NULL DEFAULT 0,
>         shuffle_indices TEXT NOT NULL DEFAULT '',
>         repeat_mode TEXT NOT NULL DEFAULT 'none',
>         origin_kind TEXT,
>         origin_id INTEGER,
>         origin_name TEXT,
>         updated_at INTEGER NOT NULL
>       );
78,98d103
< CREATE TABLE playback_state (
<           id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
<           queue_ids TEXT NOT NULL,
<           current_track_id INTEGER,
<           position_ms INTEGER NOT NULL DEFAULT 0,
<           shuffle_enabled INTEGER NOT NULL DEFAULT 0,
<           shuffle_indices TEXT NOT NULL DEFAULT '',
<           repeat_mode TEXT NOT NULL DEFAULT 'none',
<           origin_kind TEXT,
<           origin_id INTEGER,
<           origin_name TEXT,
<           updated_at INTEGER NOT NULL
<         );
< CREATE TABLE pending_track_edits (
<           track_id   INTEGER NOT NULL,
<           field      TEXT    NOT NULL,
<           new_value  TEXT    NOT NULL,
<           base_value TEXT    NOT NULL,
<           updated_at INTEGER NOT NULL,
<           PRIMARY KEY (track_id, field)
<         );
```

**Reading of the diff** (whitespace-normalized, per-object comparison of all
18 objects in both `sqlite_master`s):

| Object | Difference | Kind |
|---|---|---|
| inventory (all 10 tables + 8 indexes) | none — identical sets | — |
| `synced_tracks` | `content_uri TEXT` (upgraded) vs `content_uri TEXT DEFAULT ''` (fresh) | **substantive** — different column default |
| `synced_tracks` | `artwork_source TEXT` (upgraded) vs `artwork_source TEXT DEFAULT NULL` (fresh) | **substantive** textually, functionally identical (both store NULL when omitted) |
| `sync_history` | `NOT NULL ,` vs `NOT NULL,` (space-before-comma left by the ALTER rewrite) | cosmetic |
| `playback_state`, `pending_track_edits` | different position in the dump (appended at end by the v6/v7 `CREATE TABLE IF NOT EXISTS` migrations vs mid-file in `_createDB`) and 10- vs 8-space indentation | cosmetic |
| everything else | byte-identical after whitespace normalization | — |

So: no table, index, column or constraint is missing or extra on either side
— this is **not** the sync_history-disaster class (a column absent on one
path, breaking INSERTs). But the two paths do store **different CREATE
statements for `synced_tracks`**, which is exactly the drift class check C
exists to catch, and the check's standard is "must be identical".

**Functional-impact analysis of the one behaviour-relevant difference
(`content_uri`: NULL default on upgraded rows vs `''` default on fresh rows,
for rows inserted without an explicit value):**

- Every reader treats NULL and `''` identically:
  - `lib/presentation/services/track_uri_resolver.dart:21-26`
    `_isUsableTreeUri`: `uri != null && uri.isNotEmpty && …` → both rejected
    → walk fallback. Doc comment at :30-31 says "treating `''` as null".
  - v5 purge, `lib/data/database/database_helper.dart:229-231`:
    `WHERE content_uri IS NOT NULL AND content_uri != ''` → both "empty".
  - Kotlin writer `android/…/DatabaseHelper.kt:85`
    (`if (track.contentUri != null) put(…)`), invalidator at :265 (writes
    explicit NULL).
- In the actual upgraded fixture the difference never manifests: the first
  v8 sync wrote an explicit tree-scoped URI to **all 95** rows
  (`content://com.android.externalstorage.documents/tree/…`), so no row ever
  took either default.
- No user-visible defect was demonstrated. The block stands on the check's
  standard (schemas not identical) and on the process fact: nothing in the
  repo (no `test/` directory exists) compares the `_createDB` and migration
  paths, so this divergence was introduced silently and would re-accrue
  silently on every future column added to `_createDB` but not mirrored
  (with matching defaults) in a migration.

Fix direction for the decision-maker (not applied — report only): make the
migrations emit the same column definitions as `_createDB`
(`ADD COLUMN content_uri TEXT DEFAULT ''` in the v4 step;
`ADD COLUMN artwork_source TEXT DEFAULT NULL` in the v8 step), or normalize
`_createDB` to the migration forms — then re-run this exact A+C+D procedure.
Note an in-place re-ALTER of already-v8 databases is not possible without a
version bump; the fresh-vs-upgraded comparison is the standing regression
check this should become.

## Check D — data survived: PASS

Row counts, every table, before (v3, after v3 sync) → after migration (v8,
first post-upgrade launch, **before** any v8 sync) → after post-upgrade sync:

| table | v3 before | v8 post-migration | v8 after sync |
|---|---|---|---|
| synced_tracks | 95 | 95 | 95 |
| synced_playlists | 2 | 2 | 2 |
| playlist_tracks | 95 | 95 | 94 |
| sync_history | 1 | 1 | 2 |
| sync_history_playlists | 2 | 2 | 4 |
| playlist_cache | 13 | 13 | 13 |
| pending_events | 0 | 0 | 0 |
| pending_track_edits | — (no table) | 0 | 0 |
| playback_state | — (no table) | 0 | 1 |

- All 95 v3 `synced_tracks` rows present post-migration with
  **byte-identical content** (id/title/artist/album/local_path/file_size
  compared row by row: 0 mismatches).
- All 95 v3 `playlist_tracks` pairs present post-migration (set comparison).
- The v3 `sync_history` row survived verbatim, with the two new columns NULL:
  `(1, 1791178109883, 'success', 2, 95, 0, None, 768891, 'manual', None, None)`.
- Both v3 `sync_history_playlists` children survived
  (`sync_id=1`); the v6 orphan-cleanup DELETE was a no-op (0 orphans in).
- The single `playlist_tracks` delta (95→94, after the post-upgrade sync,
  not after the migration): server-side Soul membership loss — pair
  `(Soul, track 2936 "A Man and a Half" – Wilson Pickett)` removed; track
  row retained in `synced_tracks` (invariant 27, designed behaviour; Soul has
  shrunk before in this project's history). Nothing was silently dropped by
  the upgrade.
- Additions are all legitimate new data from the post-upgrade run:
  `sync_history` +1 (the new sync, `plays_synced=2, skips_synced=0`),
  `sync_history_playlists` +2 (its children), `playback_state` +1 (persisted
  queue).

## Check E — no orphans: PASS

`SELECT COUNT(*) FROM sync_history_playlists WHERE sync_id NOT IN (SELECT id
FROM sync_history)` → **0** on the v3 before DB and **0** on the upgraded DB
(after migration and after the post-upgrade sync).

## Check F — the app works on the upgraded database: PASS

- **Library lists previously synced tracks:** Tracks tab rendered the v3
  downloads ("A Man and a Half", "Acousticon Theme", "Ain't No Love in the
  Heart of the City", …); Playlists tab showed Brass 33 / Soul 62.
- **A track plays:** tapped "A Man and a Half" → "Now playing" on the row,
  mini player docked, media session PLAYING with queue size 95; the sheet
  showed the track through to 2:51/100%, then the player auto-advanced to
  "Acousticon Theme", whose position advanced 1:1 with wall clock
  (Δposition 131296 ms = Δ`updated` 131296 ms).
- **A sync completes and writes a new history row:** manual sync from the
  Sync screen succeeded in 24.3 s (0 downloads — files already present),
  wrote `sync_history` row 2 with `plays_synced=2, skips_synced=0` and 2
  children; the 2 waiting playback events were uploaded (both **plays**, 0
  skips — natural completions, invariant 9) and `pending_events` returned to
  0.
- **Artwork resolves:** first v8 sync resolved all 95 tracks —
  "82 embedded, 1 server, 12 absent, 0 failed"; `artwork_source` is
  populated for 100% of rows (0 NULL); 18 distinct content-addressed files
  on disk, all non-zero. UI paint of the images not visually confirmed
  (model has no image input — see NOT VERIFIED).
- Bonus (restore path): after force-stop + relaunch the queue was restored
  from `playback_state` and playback resumed (app showed the third queue
  track as "Now playing"), and server ratings now render on rows.

---

# Evidence files (host, `/tmp/owntone_verify/`)

| file | what |
|---|---|
| `v3_before.db` | the v3 database, pulled after the v3 sync (byte-verified pre-upgrade) |
| `v3_before_schema.txt` / `v3_objects.txt` | v3 `.schema` / object inventory |
| `v8_upgraded.db` | same DB immediately after the 3→8 migration, before any v8 sync |
| `v8_after_sync.db` | upgraded DB after the post-upgrade sync (final upgraded state) |
| `v8_fresh.db` | fresh-install v8 database (check C) |
| `v8_upgraded_schema.txt` / `v8_fresh_schema.txt` | the two `.schema` dumps |
| `schema_diff_verbatim.txt` | the verbatim diff (reproduced in §C) |
| `v3_launch.logcat`, `v8_firstlaunch.logcat`, `v8_work.logcat` | full logcat captures (filter note: `E/flutter` tag, per invariant 29) |
| `v3_sync_worker.log`, `v8_sync_worker.log` | `logcat -s BackgroundSyncWorker` captures |
| `v3_*.xml`, `v8_*.xml` | uiautomator dumps at each UI step |
| `main_db_helper.dart`, `main_databasehelper.kt`, `main_worker.kt` | `main` branch sources extracted for comparison |
