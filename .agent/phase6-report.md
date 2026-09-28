# PHASE 6: COMPLETE

## GO/NO-GO CHECK

What it was:
Phase 6 exists to make the browsing surfaces real: row interaction grammar
(spec §5), in-context playback, now-playing indicators, detail headers,
search, and per-category sort persistence. Defining checks per plan §3:
(a) spec §7 step 2 (open an album → tap track 4 → all 10 queued, track 4
current) from **every** list surface; (b) B2 sort persistence across app
restart; (c) the Phase 5 handoff debt — row-menu "Play next"/"Add to queue"
as the **first production callers** of `PlaybackController.playNext`/
`enqueue`, with the shuffle-ON routing check done in the queue sheet AND by
pressing Next (the user-confirmed single most important item of the phase).

Did you run it:        YES

What you observed:
- Shuffle-ON routing (the critical check), from a long-pressed track row on
  the Brass detail screen: "Play next" for Skunk inserted it at **row 1 of
  the play order, immediately after the current track** (row 0 From Now On
  current, row 1 Skunk inserted, row 2 Almost Never, row 3 the original
  Skunk — queue sheet). Then, with the sheet closed, pressed **Next** in
  NowPlayingSheet → **Skunk started playing (0:04/6:01)**. Both checks agree;
  the second is the truth and it passed.
- §7 step 2 from every surface:
  - Albums tab → Unlearn (10 synced tracks; the server album has 11 but
    track #4 "Something" is in no synced playlist) → tapped the 4th visible
    row (Da Bomba) → Now Playing "Da Bomba", "Playing from Unlearn", queue
    sheet = exactly the 10 album tracks in album order, 4th current.
  - Playlists tab → Brass → tapped 4th row (Good People) → 33 queued, current
    track is the tapped one, "Playing from Brass".
  - Artists tab → Too Many Zooz → tapped Trundle Manor → all 13 artist tracks
    queued (incl. "Chandelier" via the `album_artist` OR rule), "Playing
    from Too Many Zooz".
  - Tracks tab → tapped first row (A Man and a Half) → full 95-track list
    queued in title A–Z order (queue head = tapped track, tail = "Your One
    and Only Man", the last title-sorted track), "Playing from All tracks".
  - Search "pickett" → tapped a track result → all 14 track results queued in
    list order, tapped track current, "Playing from Search "pickett"".
- B2 persistence: set Playlists Z–A (Soul first), Artists Z–A (Youngblood
  feat. Talib Kweli first), Albums Year-newest (Brass/Moon Hooch 2025 first),
  Tracks Year-newest (Space Cow 2025 first); force-stopped
  (`am force-stop`, equivalent of the manual Settings force-stop) and
  relaunched → **all four retained** (verified on all four tabs).

## OBSERVED — things you did and saw, on the emulator, by hand

- Cold start → Library: app bar gained a "Sort by" icon; Playlists tab shows
  Brass/Soul rows with "33 tracks"/"62 tracks" subtitles and ⋮ buttons.
- Tapped Brass row → detail screen: collapsing header (title + "33 tracks"),
  prominent Play + Shuffle buttons, track rows with track numbers and ⋮.
- Tapped 4th track (Good People) → the row gained the now-playing indicator
  (semantics label "Now playing" in the dump; title in primary color) and the
  mini player docked showing "Good People" with Pause/Next.
- NowPlayingSheet: "Good People / Thundersmack feat.Honeycomb / Brass",
  "Playing from Brass", position advanced (0:50 → 1:50) while I worked.
- Good People finished naturally mid-verification → player auto-advanced to
  "From Now On" (play-order row 1) — shuffled auto-advance working in
  production, and it meant the Play-next tap landed while From Now On was
  current (see GO/NO-GO).
- Long-pressed the Skunk row → bottom-sheet menu: Play next · Add to queue ·
  Go to album · Go to artist · Track info (exact grammar). The trailing ⋮
  button opens the same menu (verified separately).
- Tapped "Play next" → snackbar `Next up: "Skunk"`; queue order verified as
  in GO/NO-GO; pressing Next played Skunk (0:04/6:01, "Playing from Brass").
- Long-pressed Brass row → Play · Shuffle · Add to queue. "Add to queue" →
  snackbar `Added 33 tracks from Brass to queue` (snackbar visible within
  3.55s of the tap ≈ 2s for 33 appends); playback (Skunk) undisturbed;
  queue tail = end of the appended block ("Show Me That Dance Called the
  Second Line", last track in the collection order the app displays).
- ⋮ on Soul → "Add to queue" → snackbar `Added 62 tracks from Soul to queue`
  visible within 2.7s (≈ <2s for 62 appends) — **no visible stall**; the
  item-by-item path needs no batching (recorded as invariant 19 RESOLVED
  CONCERN with the just_audio source evidence for why setAudioSources
  can't batch it).
- Brass header Shuffle with shuffle already ON (the re-shuffle path):
  playback started on "Show Me That Dance Called the Second Line" (the random
  start track) at 0:09, "Playing from Brass", shuffle ON; queue sheet row 0 =
  that track with a fresh permutation behind it → the random start is the
  track that plays first, not displaced (user note 3 confirmed on device).
- Pickett album header Play → "Don't Fight It" (track #1 in disc/track order)
  started; the previous queue (14 search results) replaced by the 14 album
  tracks; "Playing from Wilson Pickett's Greatest Hits".
- Albums tab: 9 distinct albums named "Brass" (different artists/years).
  Before the fix (pre-existing), any of them queued all 13 same-named tracks
  while the row advertised "1 track". After: "Brass / New Birth Brass Band •
  2008 / 1 track" opens a detail showing exactly its 1 track ("Let Your Mind
  Be Free", 7:36), header "1 track • 7 min • 2008" (singular, final build).
- Artists tab: initials avatar + "N albums • M tracks" rows. Tapped Too Many
  Zooz → detail "6 albums • 13 tracks" with tappable album sections (Brass /
  7 tracks, …) → section header opens the album detail.
  Row-count mismatch found on device (row 12 vs detail 13) and fixed
  (correlated OR-rule count); final build shows "6 albums • 13 tracks"
  (and Youngblood 9→11, Thundersmack 4→5, all now matching their details).
- Search "pickett": grouped results — Artists (Wilson Pickett, 1 album • 14
  tracks), Albums (Wilson Pickett's Greatest Hits, 14 tracks — curly
  apostrophe matched), Tracks (14, alphabetical); no Playlists section (none
  match). Artist row → artist detail; album row → album detail (14 tracks •
  39 min • 1987, genre subtitles); track row → play in context (see
  GO/NO-GO). Clear button resets to the hint state; empty query shows the
  hint.
- Sort menu per tab: Playlists/Artists offer A–Z/Z–A; Albums A–Z/Year;
  Tracks Title/Artist/Album/Year/Date added (5 options, checkmark on active).
- "Track info" from a row menu → dialog with title/artist/album/genre/year/
  duration/file path. "Go to album" from a track row → the correct
  (album, artist, year) detail (1 track, not the 13-track union). "Go to
  artist" → the artist detail. Album-row "Go to artist" (Pickett album) →
  Pickett artist detail.
- Last-row layout with the mini player docked: scrolled the Tracks tab to the
  end — final row "Providence" and its ⋮ at y≈2406, fully above the mini
  player container (top y=2586); last row fully tappable (B4/invariant 16
  still holds).
- Final-build regression: tapped "Let Your Mind Be Free" in the Soul Rebels
  album detail → "Now playing" indicator on the row + mini player docked.
- Force-stop/relaunch also re-confirmed the app reconnects to the running
  audio service (playback kept going across an `am start` while the service
  was alive; a true `am force-stop` kills playback, as Phase 7 will address
  with A8 persistence).

## NOT VERIFIED — implemented but not exercised, and why

- Search debounce (300ms) timing: results appeared after typing; the
  debounce interval itself was not timed.
- Search "No results for "…"" state and the `%`/`_` wildcard escape: neither
  was exercised (no convenient input for them).
- "Add to queue" from a **track** row (snackbar `Added "<title>" to queue`):
  the menu item is the same widget as the verified Play next path; I verified
  Play next's snackbar and the collection-add snackbars, not this one
  specifically.
- Artist-detail header Play and playlist-detail header Shuffle: the three
  headers share `playCollectionInOrder`/`shuffleCollection`; album header
  Play and Brass header Shuffle were exercised, the other two combinations
  not.
- Row menus from the search/artist/album detail surfaces specifically:
  verified from the Tracks tab, Playlists tab and Brass detail; all are the
  same `TrackRow`/collection-row widgets.
- Uppercase/non-ASCII search queries (e.g. "PICKETT", curly-apostrophe
  search terms): the LOWER/Dart-toLowerCase path was verified with lowercase
  input matching curly-apostrophe data, not with non-ASCII input.
- A9 skipped-track notice from the new screens (unchanged Phase 5 code; no
  files deleted this phase).

## DEVIATIONS — anything not done as the phase specified

- `play_button.dart` deleted wholesale instead of rewritten in place; the row
  widgets live in a new `widgets/library_rows.dart` (confirmed the right call
  in the plan conversation; listed for the record).
- **Pre-existing defect fixed, required for the surfaces this phase ships:**
  album identity. `getTracksByAlbum` filtered on album **name only**, so with
  nine same-named "Brass" albums, every one of those rows played all 13
  tracks while advertising 1. Fix: optional `albumArtist`/`year` filters;
  `AlbumDetailScreen` carries the identity; `MediaItem.extras` gained
  `albumArtist`/`year` so the sheet's "Go to album" (Phase 5 code, minimal
  param addition) can disambiguate; artist-detail album sections pass the
  identity only when uniform. Recorded as invariant 21.
- `getAllArtists` counts rewritten (correlated subquery, `artist = X OR
  album_artist = X`) to match `getTracksByArtist` membership — the row count
  previously disagreed with its own detail screen (12 vs 13 for Too Many
  Zooz).
- `getAllArtists` now returns `List<Map>` (was `List<String>`);
  `getAllAlbums` returns a `track_count` column; `getAllPlaylistsWithCounts`
  gained `nameDesc`. All consumers are the Phase 6 browse screens (the
  `sync_provider` pass-through wrapper has no callers and still compiles).
- `SortOrder` enum expanded and restricted per category (map of allowed
  options); the old Tracks-tab `nameDesc` silent-fallback-to-title-ASC bug is
  gone by construction.
- Detail headers use a `pinned` collapsing `SliverAppBar` (collapses to the
  compact bar with back button on scroll) — spec B3 says "collapses on
  scroll"; unpinned would lose the back button.
- Snackbars added to Play next / Add to queue (track and collection) as
  mutation feedback (user-approved for collection adds in the plan).
- `QueueOrigin` gained a `search` kind (`Playing from Search "<query>"`) for
  search in-context playback (user-approved in the plan).
- `PlaybackController` gained `enqueueCollection` (batch URI resolve +
  per-item append) and `currentPlaybackState` (snapshot getter).
- `searchLibrary` uses `LOWER(column) LIKE ?` with the argument lowercased in
  Dart (Unicode-aware) rather than stock SQLite's `LIKE`/`NOCASE`, per the
  plan note on the curly-apostrophe title.

## BUILD

flutter analyze:
`No issues found!` (0 errors, 0 warnings, 0 infos — run after every code
change; final run after the last fix)

flutter build apk --debug:
`✓ Built build/app/outputs/flutter-apk/app-debug.apk` (3 builds; the final
build contains the count fix and the singular-text fix and is the build all
final OBSERVED items ran on)

## UNKNOWN — behaviour you could not explain

- In one sequence, three consecutive back events closed the queue sheet, the
  NowPlayingSheet, then **also left the app** (a non-app "Checking info…"
  state was briefly visible before relaunch via `am start`). Consistent with
  Android 16 predictive-back exiting on back-at-root, but not confirmed; no
  data or playback loss resulted (playback had not restarted yet at that
  point).

## APPENDIX — file changes

- New: `lib/presentation/widgets/library_rows.dart` (TrackRow/PlaylistRow/
  AlbumRow/ArtistRow, shared row menu, track-info dialog, `AlbumArtTile`,
  `artistInitials`, `formatTrackDuration`);
  `lib/presentation/screens/search_screen.dart`;
  `lib/presentation/services/collection_playback.dart`.
- Deleted: `lib/presentation/widgets/play_button.dart`.
- Rewritten: `track_list_view.dart`, `playlist_list_view.dart`,
  `artist_list_view.dart`, `album_list_view.dart`,
  `playlist_detail_screen.dart`, `album_detail_screen.dart`,
  `artist_detail_screen.dart`.
- Revised: `browse_provider.dart` (per-category sort + persistence),
  `library_screen.dart` (search entry + sort menu),
  `playback_controller.dart` (QueueOrigin.search, enqueueCollection,
  currentPlaybackState, extras), `local_database_repository.dart`
  (searchLibrary, counts, nameDesc, album identity),
  `player_screen.dart` (_goToAlbum identity params only).
- Not touched: sync pipeline, `audio_handler.dart`, `shuffle_order.dart`,
  `queue_sheet.dart`, `mini_player.dart` (the two known blockers in
  `.agent/blockers.md` remain Phase 7, unchanged).
