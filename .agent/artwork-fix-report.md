ARTWORK FIX: COMPLETE

GO/NO-GO CHECK
  What it was: sync, then confirm REAL album art renders in the mini player,
               the Now Playing sheet, and album rows — naming the specific
               albums. Artwork has never once displayed, so "unchanged" is a
               failure.
  Did you run it:        YES
  What you observed:
  - Installed the debug APK, launched the app (v8 migration added
    artwork_source), opened Library → Albums. Of the first 10 album rows, 8
    rendered real covers — 1989 (Taylor Swift), AM (Arctic Monkeys), Attack
    & Release (The Black Keys), Black Holes and Revelations (Muse), Black
    Pumas (Black Pumas), Brass (James Newton Howard), Brass (New Birth Brass
    Band), Brass (The Soul Rebels). The other two — Alternative (Audioslave)
    and Brass (Moon Hooch & Too Many Zooz) — rendered the clean grey
    placeholder, and the DB confirms their tracks (855, 1875) are exactly
    the artwork_source='none' rows.
  - Album detail headers: What Happens Now (Dasha) and Black Pumas both
    rendered their covers.
  - Play (What Happens Now) → mini player showed the Dasha cover; the Now
    Playing sheet ("Austin" / Dasha, position advancing 0:54 → 29%) showed
    the Dasha cover.
  - Play (Black Pumas) → Now Playing sheet ("Black Moon Rising" / Black
    Pumas) showed the Black Pumas cover; mini player the same.
  - Method note: this model cannot view images directly, so every "renders
    real art" claim above is a screenshot pixel analysis: color-bucket
    diversity (quantized 5-bit-per-channel) of the exact art tile region,
    calibrated against the known placeholder asset (flat, 1 bucket, avg
    200,210,215) and the known covers. Placeholders measured 13 buckets /
    ≥78% grey-224; real covers measured 27–189 buckets. The two
    signatures are unambiguous and repeated across 15+ tiles and 6
    screenshots.

MEASURED SPLIT (embedded vs server) — was unknown before this fix
  194 tracks resolved in the first pass:
    embedded: 172 (88.7%)  — read from the audio files' own tags
    server:     5 ( 2.6%)  — tracks 854 (Bill Withers), 1146 + 1147 (Dasha),
                                 2923 (Jack Harris), 3161 (GRiZ)
    none:      17 ( 8.8%)  — checked both sources, absent (incl. 1867, 1873)
    failed:    0
  So the embedded path is the DOMINANT path in this library (the local
  files carry their own art); the server fallback serves tracks whose files
  lack embedded art — still 3% of the library, and the only path for any
  future artless file. 177 resolved tracks produced 50 cache files
  (content addressing collapsed the rest).

OBSERVED — things you did and saw, on the emulator, by hand
  - Tapped Sync on the Sync screen (manual sync) → logcat:
    "Resolving artwork for 194 track(s)" … "Artwork resolution complete:
    172 embedded, 5 server, 17 absent, 0 failed (will retry)" → "Background
    sync completed: 0 tracks downloaded in 14207ms (status=success)".
  - Pulled the app DB (run-as + host sqlite3) after the sync: 172 embedded /
    5 server / 17 none; track 874 → 'embedded'; 1867 + 1873 → 'none' with
    empty artwork_path; the 14 "The Best of Otis Redding" tracks all point
    at ONE path (…/ae1b44d4…jpg) — dedup by construction.
  - Listed files/artwork on device: 50 files, all .jpg, sizes 3,713–126,148
    B, **no zero-byte file**; the on-disk filename set diffed byte-for-byte
    equal to the DB's distinct artwork_path set (50 = 50, no orphans, no
    missing).
  - Opened Albums tab → 8/10 rows real covers, 2 placeholders = the two
    'none' tracks (see GO/NO-GO).
  - Opened "What Happens Now" / Dasha detail (its 2 tracks are the
    server-sourced ones) → header rendered the Dasha cover; tapped Play →
    mini player + Now Playing sheet rendered it (above).
  - Opened "Black Pumas" detail (embedded-sourced) → header + Now Playing
    sheet rendered the cover (above).
  - Airplane mode (svc wifi/data off; emulator ping → "Network is
    unreachable") → force-stopped the app, relaunched → the server-fetch
    banner appeared ("Failed to fetch playlists: DioException [connection
    err…]") as expected, but the library rendered, the restored queue
    ("Black Moon Rising" / Black Pumas) showed its cover in the mini player
    from cache, and the Albums tab rendered identically (7 real + 2
    placeholder) with zero network. This is the actual requirement.
  - Re-enabled wifi, DELETED track 874's local file (7,831,742 B mp3), ran a
    second sync from the Sync screen → "Need to download 1 tracks",
    "Downloaded track: Your One and Only Man (7831742 bytes)", and **zero
    artwork log lines** — the pass found no artwork_source IS NULL rows, so
    nothing was re-probed or re-fetched (negative cache). DB after: 874's
    download_timestamp changed (1790645308007 → 1791170670449, i.e. the
    upsert ran) while its artwork_path is byte-identical
    (…/ae1b44d4…jpg) — upsert survival (invariant 26). Cache file set
    diffed identical (no new files). The 17 'none' rows are still 'none'.
  - Searched "Bad Guy" and "Black Ice"; the album rows for both known-204
    tracks (Brass / Too Many Zooz / 2020 — tracks 1866+1867; Unknown album /
    Too Many Zooz — track 1873) rendered the clean placeholder (same
    78.5%-grey / 13-bucket signature as the other 'none' rows).
  - Full-session logcat: zero E/flutter lines.

NOT VERIFIED — implemented but not exercised, and why
  - isStopped mid-pass cancellation (resolveArtwork breaks and the run is
    recorded cancelled) — no cancel was issued during a pass; would require
    cancelling a sync at the exact moment it is in the artwork phase.
  - The hasArtworkSupport()=false skip (worker running against a pre-v8 DB
    before the app has launched once after an update) — every sync in this
    session ran after the app had migrated the DB. The guard is the same
    proven pattern as hasRatingSupport().
  - The server-error → NULL retry path (fetchTrackArtwork throwing keeps the
    row NULL) and the embedded-read-failure → server fallback path — 0
    failures occurred; both would need a fault injection (e.g. an
    unreachable server mid-pass) to exercise.
  - storeArtworkFile's temp-and-rename crash path — not inducible on demand.
  - resetAppData's artwork deletion (deleteTrack's new absolute-path branch)
    — not exercised; it would wipe the user's synced library.
  - A *scheduled* (non-manual) run executing the pass — same doWork path as
    the verified manual sync; the pass is trigger-type agnostic.

DEVIATIONS — anything not done as the phase specified
  - Deleted more than the named dead helper: `downloadArtwork` was joined by
    its orphaned siblings (`getArtworkPath`, `generateArtworkFilename`,
    `getArtworkFilePath`, `artworkExists`, `_getArtworkAbsolutePath`) and the
    now-dead `artwork/`-prefix branches inside fileExists/getFileSize/
    writeFile — all confirmed to have no callers once downloadArtwork went.
    `deleteTrack` gained an absolute-path branch: resetAppData deletes
    artwork via it, and artwork_path is now an absolute path the old
    relative-`artwork/` branch could never match.
  - Dart album queries (getAllAlbums, searchLibrary) changed from
    `GROUP BY …, artwork_path` to `MAX(artwork_path) AS artwork_path` with
    `GROUP BY album, album_artist, year`. With per-track content-addressed
    paths, a mixed-source album — Rebel Era/GRiZ (3 embedded + 1 server
    track) occurred on the very first sync — would otherwise split into
    duplicate identical rows.
  - The GO/NO-GO pixel evidence is screencap + PIL color statistics
    calibrated against the known placeholder asset and covers, because this
    model cannot view images directly (see method note in GO/NO-GO).
  - `DatabaseHelper.kt` (Kotlin) was changed although the scope list named
    the three worker files: the worker's DB access layer is the only place
    that can read the unresolved-track set and write artwork_path/
    artwork_source from Kotlin (tolerant artworkSource read,
    hasArtworkSupport(), getTracksNeedingArtwork(), updateTrackArtwork()).
    There is no other home for these inside the named files.

BUILD
  flutter analyze: No issues found (0 errors, 0 warnings)
  flutter build apk --debug: ✓ Built build/app/outputs/flutter-apk/app-debug.apk
  (Gradle assembleDebug — includes the Kotlin changes)

UNKNOWN — behaviour you could not explain
  - After track 874's re-download, its content_uri string is byte-identical
    to the pre-delete one. The fast path (invariant 6) builds the document
    URI deterministically from the tree + relative path, so a same-path
    re-download reproduces the URI instead of a new document id. Harmless
    here — the URI resolves to the new file at the same path, and the
    resolver/upsert handled it (artwork survived, playback file is the new
    one). Invariant 26's "new MediaStore document id" premise did not apply
    to this fast-path URI shape. Not chased further: the property invariant
    26 actually protects (artwork_path surviving the upsert) was verified.
  - A queue restored from before artwork was resolved keeps placeholder
    art for that session: MediaItems are built with the DB state at queue-
    load time, and reconcileQueue (sync completion) only removes dead
    tracks, never rebuilds items. On the first-ever post-fix sync the
    restored queue looked stale until the next queue load; every steady-
    state cold start restores with art (verified in the offline cold-start
    test, where the restored queue showed its cover immediately).
