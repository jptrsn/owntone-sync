---
title: Media browse tree + play-from callbacks (getChildren / playFromMediaId / playFromSearch)
status: pending
workflow: default
depends_on: [unit-02-aa-optin]
quality_gates:
  - name: analyze
    command: flutter analyze
  - name: flutter-test
    command: flutter test
  - name: gradle-test
    command: ./gradlew -p android :app:testDebugUnitTest
  - name: build
    command: flutter build apk --debug
---

# Unit 03 — Browse tree and play-from callbacks

Give the car host a browsable, playable library. `OwnToneAudioHandler`
(inheriting `audio_service` `BaseAudioHandler`) currently returns the
defaults: `getChildren → []`, `getMediaItem → null`,
`playFromMediaId/playFromSearch → no-op` (verified in
`audio_service-0.18.19/lib/audio_service.dart`, `BaseAudioHandler`). The
Android side is already wired: `AudioService.onLoadChildren` delegates to the
Dart handler via method channel (`getChildren`, `getMediaItem`,
`playFromMediaId`, `playFromSearch`, `search` all exist in
`AudioServicePlugin.java`), and `onGetRoot` returns the browsable root
`root` and the recent root `recent` — only the Dart half is missing.

Reference: `docs/android-media-overview.md` (content tree, FLAG_PLAYABLE /
FLAG_BROWSABLE), `docs/android-media-enable-playback.md` (required actions,
initial state, queue), `docs/android-media-errors.md` (error states).

## Design

### MediaItem id (mediaId) scheme

Stable, encodable, decodable. The **track id MUST equal the track's local
DB id string** — that is the `MediaItem.id` the app already uses during
playback (`playback_controller.dart:_toMediaItem`), so session metadata,
queue items, and browse leaves agree:

| Node | mediaId format | Notes |
|---|---|---|
| Track (leaf) | `track:<dbId>` | `FLAG_PLAYABLE` only |
| Album (node) | `album:<name>\u001f<albumArtist>\u001f<year>` | `FLAG_PLAYABLE \| FLAG_BROWSABLE` (playable = play the album, like a playlist). Key matches `LocalDatabaseRepository.getTracksByAlbum(albumName, albumArtist:, year:)` — the same triple `library_rows.dart` uses |
| Artist (node) | `artist:<name>` | `FLAG_PLAYABLE \| FLAG_BROWSABLE`. Key matches `getTracksByArtist` |
| Playlist (node) | `playlist:<dbId>` | `FLAG_PLAYABLE \| FLAG_BROWSABLE`. Stable int id |
| Section (node) | `section:all` \| `section:albums` \| `section:artists` \| `section:playlists` | `FLAG_BROWSABLE` only |

Use unit-separator `\u001f` between album components (album names can
legitimately contain `:` and `/`); URL-encode names inside `artist:` /
`album:` as well to be safe against `+`/`%` ambiguity. Encode/decode must be
a **pure Dart pair of functions** (no DB access) so they are unit-testable
both directions.

### Tree shape

Browsable root (`root`):
```
root
├── section:all        "All tracks"     → track:*
├── section:albums     "Albums"         → album:*
├── section:artists    "Artists"        → artist:*
└── section:playlists  "Playlists"      → playlist:*
```
Recent root (`recent`): the last N (spec: 20) **distinct** played tracks,
newest first, as playable leaves, from `getSyncHistory` (playback records
with track ids) — same list the phone shows in History. If history is empty,
recent root returns `[]` (AA shows its own empty state).

`getChildren(parentMediaId)`:
- `root` → the four sections (with `artUri` left null; section icons are the
  host's business).
- `section:all` → all tracks (`getAllTracks`), as `MediaItem`s built by the
  same mapping as playback (`_toMediaItem`-equivalent: title, artist, album,
  duration, `artUri` file, `extras: {albumArtist, year, uri?}` — **uri is
  NOT resolvable in the service context for every track at browse time**, so
  do not require `extras['uri']` on browse leaves; resolution happens in
  `playFromMediaId`).
- `section:albums` → one node per album from `getAllAlbums`.
- `section:artists` → `getAllArtists`.
- `section:playlists` → `getAllPlaylistsWithCounts`.
- `album:*` / `artist:*` / `playlist:*` → their tracks (playable leaves).
- `track:*` → `[]` (leaf).
- Unknown id → `[]` (never throw; log it).

`getMediaItem(mediaId)` → the `MediaItem` for any of the above (sections and
nodes included), `null` for unknown.

`subscribeToChildren(parentMediaId)` → re-emit (any options) when the local
library changes: hook the existing **sync-completed** notification path
(the app already broadcasts sync completion through
`MainActivity`'s progress channel / `SyncProvider`). Do not add new DB
watchers.

### Playback callbacks

- `playFromMediaId(mediaId, [extras])`:
  - `track:<id>` → resolve the track's audio file (same resolution
    `PlaybackController` uses — `track_uri_resolver.dart`), play it **in its
    album context** when the track's album has ≥ 2 synced tracks (keeps
    next/previous meaningful), standalone otherwise.
  - `album:*` / `artist:*` / `playlist:*` → play the collection from the
    start (existing `playCollection`-family paths via `PlaybackController`).
  - `section:*` → play the section's content from the start (all tracks /
    all album-first-tracks).
  - Unknown/failed resolution → do nothing, set the session error state per
    `docs/android-media-errors.md` only if it was a user-visible request
    (record the exact call used; `audio_service` surfaces
    `processingState error` — check what AA renders for it during
    verification).
- `playFromSearch(query, [extras])`: `searchLibrary(query)` → play the best
  matching track (first result) in its album context; no results → no-op
  (AA announces no results itself).
- `search(query, [extras])` (the `onSearch` path — AA's on-screen search):
  return up to 12 matching **track** items (playable leaves) from
  `searchLibrary`. AA renders them; tapping fires `playFromMediaId`.

### Reuse, not reimplementation

All playback goes through the **existing** `PlaybackController` /
`OwnToneAudioHandler` funnel so the invariants hold: `_userInitiatedPending`
is set (car requests are user-initiated moves — stats must record them as
skips, per the handler's own contract), A9 auto-advance is untouched,
repeat/shuffle restore is untouched. The handler already holds everything;
the new code is the mapping layer (mediaId ↔ DB rows ↔ `MediaItem`).

### Error state while the car is connected

When the A9 terminal path fires (`queueExhaustedStream`), the session
already goes to `processingState: error`. Extend it (small change, flagged in
the report) to also carry a **user-facing message** for the car: e.g.
`'No playable tracks in queue — sync again on the phone'` (allFailed) /
`'Queue ended'` (endOfQueue), via `playbackState` error copyWith (check the
`audio_service` `PlaybackState` API for the error-message field in the
indexed docs before using it).

## Tests (write first — TDD within the default workflow)

Cite the requirement each test guards (repo test rule). Pure-Dart tests, no
device:

- mediaId encode/decode round-trip: album names with `:`, `/`, `+`, spaces,
  unicode; artist with `&`; year 0; unknown prefix decodes to `null`.
- Section/node → `MediaItem` mapping from DB-shaped fixtures (title/artist/
  album/duration/artUri/extras present and correct; `uri` extra absent at
  browse time).
- `search` result cap (12) and dedupe.
- Recent-root: distinct, newest-first, cap 20, empty-history → `[]`.

Handler-level integration (existing suite conventions, `flutter test` with
the sqflite ffi setup already used for `DatabaseHelper`):
- `getChildren('root')` returns the four sections after a fixture sync.
- `playFromMediaId('track:<id>')` starts playback of the right file (use the
  existing test seam for the audio player — see `test/` for the pattern).

## Completion criteria

### Success cases

- [ ] DHU browse view shows the four sections; each descends correctly to
      its children; a track leaf plays audio through the car speakers.
- [ ] Album/artist/playlist nodes are **playable**: tapping the node
      (not a child) starts the collection.
- [ ] Recent root (if the host surfaces it) shows the last played tracks.
- [ ] On-screen search in the car returns results; playing a result works.
- [ ] Voice/`playFromSearch` best-match plays (verify with the DHU mic
      `mic play` command if AA search is reachable, otherwise mark
      not-verified-automated and verify by the DHU console search path).
- [ ] `flutter test` covers the new mapping layer (tests committed, green).
- [ ] Stats: a car-initiated track change is recorded as a user skip by the
      stats recorder (verify with the existing stats instrumentation).

### Failure cases

- [ ] Track with a missing/unsynced audio file: tapping it in the car does
      not hang or crash; A9 advances; the failure is visible (session error
      state / skipped-track notice on the phone).
- [ ] Empty library (fresh install): browse root shows sections; sections
      are empty; nothing crashes.
- [ ] Unknown mediaId (hand-crafted via Media Controller Test app or
      `adb shell am`-free tooling): `[]` / no-op, logged.

## Risks / unknowns

- **Browse-time file resolution.** Some hosts may expect `uri` on leaves;
  if AA refuses to play a leaf without it, resolve the file at browse time
  (the DB has the path) and put it in `extras['uri']` — the playback path
  already prefers it. Decide during verification, record the outcome.
- **`PlaybackState` error message field** in audio_service 0.18.19 — check
  the indexed docs; if absent, the error-message sub-feature is deferred
  (AA shows a generic error; phone still gets the A9 notice).
- Recent-root support varies by host (AA "recently played" is system-fed);
  do not over-invest — the spec is "if the host surfaces it".
