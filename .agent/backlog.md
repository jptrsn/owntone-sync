# Backlog

Ideas captured but **not scheduled**. Nothing here is a phase. Do not implement
anything from this file unless it has been promoted into
`.agent/player-refactor-plan.md` §3 as a numbered phase.

---

## `usermark` editing

The realistic second user of `pending_track_edits` (Phase 8), and the thing that
justifies building that table generically rather than adding a `rating` column
and a `server_rating` column.

- `usermark` is an integer `>= 0`, documented as "user review marking", already
  present on the OwnTone track object and settable via the same
  `PUT /api/library/tracks/{id}` endpoint as `rating`.
- Needs only a `synced_tracks` column for last-known server truth and a UI.
  Reconciliation, the conflict rule, the coverage sweep and the push path all
  come free from Phase 8.
- **Open question before any of it is worth doing:** what would the marks *mean*
  to this user? The API assigns no semantics. Decide that first; a numeric field
  with no agreed meaning is not a feature.

## Tag editing — BLOCKED, probably permanently

Editing `title` / `artist` / `album` / `album_artist` / `genre` / `year` on a
track. Raised as a motivation for the generic edit queue, then investigated and
found not to be possible.

`PUT /api/library/tracks/{id}` accepts exactly six parameters: `rating`,
`play_count`, `skip_count`, `usermark`, `time_played`, `time_skipped`. No tag
fields.

Two near-misses worth recording so they are not rediscovered as false leads:

- `PUT /api/queue/items/{id}` *does* accept `title`, `album`, `artist`,
  `album_artist`, `composer`, `genre`, `artwork_url` — but that edits an
  ephemeral **queue item** in the server's own playback queue, intended for
  overriding metadata on internet-radio streams. It never writes to the library.
- Editing file tags on disk plus `PUT /api/rescan` would work for a server-local
  library, but this app holds **synced copies on the phone**, not the server's
  originals. Local tag edits cannot propagate.

**Conclusion:** server-side tag editing requires an upstream OwnTone API change.
If it matters, the path is a feature request to the project, not something
designable here. Do not carry it as an aspiration.

## Sort orders not yet offered

Phase 6 shipped per-category sort with persistence. The option sets were chosen
to cover the spec, not to be exhaustive:

- Playlists / Artists: A→Z, Z→A
- Albums: A→Z, Year
- Tracks: Title, Artist, Album, Year, Date added

Anything beyond that (album artist, genre, play count, rating once Phase 8 lands,
duration) is unscheduled. Play count and rating in particular only become
sortable once those columns exist locally.

## Album artwork is never cached locally

**RESOLVED (2026-10-04):** artwork is now resolved and cached during sync
(content-addressed, app-private; `artwork_source` negative cache; embedded
first, server fallback) — see `.agent/reports/artwork-fix-report.md` and invariant 35.
`synced_tracks.artwork_path` now has a writer (the Kotlin sync worker), and
`artwork_source` tracks where it came from.

**Correction of the record:** this entry called the server's `artwork_url`
"an absolute URL on the OwnTone host". That is **wrong** — it is a *relative*
path (e.g. `/artwork/item/874`) that must be joined to the server base URL.
It is also populated for 100% of tracks and therefore says nothing about
whether art actually exists (the server answers HTTP 204, empty body, for
artless tracks — not 404).

## Writing artwork back into the files' tags — deferred

Writing the cached artwork back into the synced audio files (ID3 picture
frames, etc.) — considered and deliberately deferred when the local artwork
cache was built (2026-10-04):

- It needs a tag-**writing** dependency (Android has no built-in writer;
  `MediaMetadataRetriever` reads only), against the long-held no-new-deps
  line.
- It **mutates the user's own irreplaceable media files**, and a tag-write
  bug corrupts music. The project's original constraint was that the user
  owns these files; writing to them goes further than anything done so far.
- A SAF in-place rewrite means read-whole-file / modify / write-back,
  needing temp-and-rename to be crash-safe.
- The local cache is required regardless, so write-back is purely additive
  and can be added later at no cost.

One risk that does **not** apply: `file_size` is written but never compared,
so a tag write would not trigger spurious re-downloads.

## Sync screen: Cancel button never renders for a scheduled run that starts while the app is alive

Discovered incidentally during the 2026-10-04 sync-status fix session, and
recorded only in `.agent/reports/sync-status-fix-report.md` — which is a historical
record, not guidance, so it will be lost. Logged here.

For a **scheduled** run that starts while the app is already alive, the Sync
screen's Cancel button never renders. Mechanism: `SyncProvider` subscribes to
the progress EventChannel only at construction
(`_initialize` → `checkIfSyncRunning`), so a run that begins afterwards never
drives the UI into its cancellable state. That session had to cancel through
the notification action instead (invariant 34). Not fixed — out of scope for
the artwork work.

## Two remaining ways the scheduled-sync chain can still die

**RESOLVED (2026-10-04):** both paths now re-arm via a `finally` block in
`doWork()` (`BackgroundSyncWorker.kt`), which replaces the three per-path
`scheduleNextSync()` calls. The user-cancel path was exercised end-to-end
on emulator-5554 (notification Cancel during a scheduled run →
`status=cancelled` + "Next sync scheduled for …" + job queued in
jobscheduler); the disable-mid-run and skip-today exits were exercised too.
The `setForeground`-refusal path is structurally covered by the same
`finally` but was not exercised (cannot be induced on demand). See
`.agent/reports/sync-status-fix-report.md`.

The 2026-10-03 fix closed the two paths named in the blocker (illegal
`setExpedited` pairing, and the missing re-arm on `catch (e: Exception)`).
Code-path analysis during that fix found **two more** that were not touched:

- **User-cancel of a running sync** — `CANCELLED_BY_APP` → `handleInterruption`
  → `Result.success()`, with **no** `scheduleNextSync()`. Cancelling a sync
  therefore stops all future scheduled syncs.
- **`setForeground` refusal** — `ForegroundServiceStartNotAllowedException` →
  `Result.failure()`, with **no** re-arm.

Both leave the schedule displaying as enabled while nothing is queued, and —
as before — only a manual sync revives it. Neither was introduced by the fix;
both predate it and exist on released `main`.

Lower severity than the fixed pair: user-cancel is deliberate (though the
consequence is invisible and surprising), and `setForeground` refusal is rare.
But the principle the code already states at the skip-today call site — *"skipping
today must not break the recurring schedule"* — applies to every exit path, and
only three of five currently honour it. The durable fix is to re-arm in a
`finally`-style guarantee rather than per-path.

## A sync where every playlist fails still reports success

**RESOLVED (2026-10-04):** `computeSyncStatus` (top-level pure function in
`BackgroundSyncWorker.kt`) derives the run-level status from the
per-playlist outcomes — all failed → `failed`, some → `partial`, none →
`success` — and the run-level message ("All N playlists failed to sync" /
"N of M playlists failed to sync") is now stored on the history row and
surfaced in History (red "Sync Failed" / amber "Sync Completed with
Errors") and on the Library banner + app-bar dot. The all-failed path was
exercised on emulator-5554 (dead loopback + blackhole URLs, manual and
scheduled runs). The **partial** path is implemented but unexercised (needs
a server-side change; live shared library must not be touched). See
`.agent/reports/sync-status-fix-report.md`.

Found while trying to induce a sync failure for the 2026-10-03 chain test. Every
per-playlist network call sits inside a per-iteration `try/catch`
(`BackgroundSyncWorker.kt:406-648`), so an unreachable server is swallowed per
playlist and the run completes as **success** with per-playlist errors recorded.
It never reaches the outer `catch (e: Exception)`.

Consequence: with the server down but reachable-ish (closed port), Sync History
shows a completed sync that downloaded nothing. A missing server *URL* does throw
and is handled correctly; a dead *server* does not.

Worth deciding what the intended semantics are: a run where every playlist failed
is arguably a failed sync, and should be surfaced as one rather than recorded as
completed.

## Re-run the fresh-vs-upgraded schema diff (check C) — unverified change

The v3→v8 upgrade verification (2026-10-05, `.agent/reports/v3-to-v8-upgrade-report.md`)
found the only real divergence between the two schema paths: `_createDB` emitted
`content_uri TEXT DEFAULT ''` and `artwork_source TEXT DEFAULT NULL`, while the
v4 and v8 `ALTER TABLE ... ADD COLUMN` statements cannot carry a default and
produced bare `TEXT`.

Fixed by aligning `_createDB` **down** to match the migrations — SQLite cannot
alter a column default without rebuilding the table, and a rebuild on a
multi-thousand-row table is far riskier than the divergence. Safe to change
because `main` ships DB v3, so no released user has a fresh v4+ database; only
dev devices carry the old DDL, and those get wiped.

**This change was verified by reading both paths, NOT by executing them.**
Re-run check C to close it: dump `.schema` from a fresh v8 install and from a
v3-upgraded database, and diff. They must now be byte-identical.

Two traps worth knowing when you do:

- SQLite stores the `CREATE TABLE` text **verbatim in `sqlite_master`, comments
  included** (verified locally). A comment inside the SQL string shows up as a
  schema diff on its own. Commentary belongs above the `db.execute()` call, in
  Dart. The first attempt at this fix made exactly that mistake.
- Column ORDER also matters to the diff. Migrations append in version order
  (v4 `content_uri`, v7 `rating`, v8 `artwork_source`) and `_createDB` currently
  lists them in the same order. Keep it that way.

This is the first thing the migration test suite should automate — it is a
pure-SQL check that needs no device, and it generically catches a bug class that
has already cost this project one serious defect (`sync_history` silently
lacking two columns on every fresh install until v6).

## Artwork `'none'` is a one-way latch with no invalidation path

`artwork_source = 'none'` means "checked both sources, no art exists". It is
never re-examined, which is correct for performance — without it every sync
re-probes every artless file, tolerable at 95 tracks and painful at 5,000.

But it is permanent. If artwork is later added to those files' tags, or appears
on the server, nothing re-probes them. On the current library that is 12 tracks
(measured: 82 embedded / 1 server / 12 none of 95).

Possible closes, none urgent:
- a "re-scan artwork" action in Settings that clears `'none'` rows
- clear `artwork_source` when a track is re-downloaded (the file changed, so its
  embedded tags may have too)
- a staleness policy — re-probe `'none'` rows older than N days

The middle option is probably the cheapest and catches the most realistic case.

## A live playback queue is not reconciled after an intentional library wipe

Found adjacent to Phase U0 (2026-10-08), pre-existing and deliberately not
folded into it.

When the user confirms a server change as a *different* server, the app resets
its library metadata — but a queue already loaded into the player keeps playing
tracks whose rows no longer exist. Phase 7 built
`PlaybackController.reconcileQueue(aliveTrackIds)` for exactly this shape of
problem, wired to sync completion (`LibraryScreen._onSyncCompleted`), but the
destructive-reset path does not call it.

Cheap fix: call `reconcileQueue` with the surviving ids after a reset, the same
way sync completion does. Note that Phase 7's own report lists the
reconcile-removal path as NOT VERIFIED, so this is also the first real exercise
of that code — expect to be testing both at once.

Low urgency: reaching it requires deliberately changing to a different server
and choosing to start fresh.

## Unexplained app process death during an airplane-mode cycle

Observed once during Phase U0 verification (2026-10-08): the app process died
during an airplane-mode on/off cycle, with **no crash trace** in logcat. The
affected check was re-run and passed cleanly.

Unexplained, and deliberately recorded rather than guessed at (protocol §2).

**Watch for this in Phase U1**, which is entirely about airplane-mode behaviour
and cycles connectivity repeatedly by design. If it recurs there, capture the
full logcat immediately rather than re-running — a second sighting in the phase
that stresses this path is worth more than a clean retry. If it never recurs,
it stays an unexplained one-off.
