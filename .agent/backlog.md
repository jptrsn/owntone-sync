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

`synced_tracks.artwork_path` has **no writer anywhere in the codebase**
(checked during Phase 7, 2026-09-28) — album art is never cached locally. The
server's `artwork_url` (an absolute URL on the OwnTone host) is the only
source; every artwork display is a live network fetch. Offline artwork, or
caching it on sync, would be new work — not a bug to fix, and not something a
later phase silently "repairs" by writing the column.

## Two remaining ways the scheduled-sync chain can still die

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
