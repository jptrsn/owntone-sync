# Phase 8 verification report

PHASE 8: COMPLETE

GO/NO-GO CHECK
  What it was:
    The reason Phase 8 exists — the rating round trip (plan steps 5–7):
    (a) PUSH a rating committed in the app to the OwnTone server;
    (b) PULL a server-side rating change into the local row;
    (c) CONFLICT — server and app both changed since the edit's baseline —
    server wins, the local edit is dropped, and no PUT is sent.
  Did you run it:        YES
  What you observed:
    (a) Push: R1 (874) set to 70 on the Now Playing sheet, then Sync →
        worker log "Pushed 2 track rating(s) in one bulk request" (874 and
        876 in one request) → GET /api/library/tracks/874 returned rating=70.
        (874 had been dropped out of the server's Soul smart playlist, so
        this push went through the coverage-sweep path, not the playlist
        loop — a bonus sweep verification.)
    (b) Pull: server 743 set 62→40 via API, then Sync → local DB 743=40,
        row content-desc "Rated 2.0 of 5".
    (c) Conflict: server 1873 set to 40 while the app had a pending edit
        70 (base 60) → Sync → local 1873=40, pending edit deleted, no PUT
        sent, row "Rated 2.0 of 5", server still 40.

OBSERVED — things you did and saw, on the emulator, by hand
  - Tapped the album art on the Now Playing sheet → the 5-star overlay
    appeared; tapped again → it hid; left it alone → it auto-hid after ~5 s
    of idle (plan step 1).
  - Dragged the stars +182 px → rating moved exactly +10 (one half star);
    a full-left drag rendered 0 (5 empty grey stars, row loses its "Rated"
    text); a full sweep of the control covers 0→100. Mapping: 128 physical
    px per 10 rating units plus a one-time ~54 px touch slop (steps 2, 4).
  - Dragged 300 px vertically at constant x → rating unchanged and the
    list behind did not scroll (step 3).
  - Released a drag → the new rating was committed (visible in
    synced_tracks.rating and in pending_track_edits with the correct
    base_value) (step 4).
  - Step 8 (offline): airplane mode ON (ping from the emulator: "Network is
    unreachable"); committed 743 40→50 then 50→60 while offline (DB showed
    743=60, edit (60, base 40)); force-stopped the app; relaunched → the
    rating survived the process death (sheet stars 3.0 = 60); airplane mode
    OFF → Sync → "Pushed 1 track rating(s)" → server 743 = 60, edit cleared.
  - Step 9 (base_value double-edit): rated 874 70→80→90 in the app; after
    the second edit the pending row was (new=90, base=70) — the baseline
    stayed anchored to the server value, not the previous edit. Set server
    874=80, Sync → server won: local 80, edit deleted, no PUT (server
    stayed 80, not 90), row "Rated 4.0 of 5".
  - Step 10 (no-op sync): a sync with no pending edits and no server
    changes produced zero rating-related lines in the BackgroundSyncWorker
    log.
  - Step 11 (playback of a rated track): 743 (rated 60) played from the
    mini player; media_session position advanced 442 → 26592 ms — audio
    plays after rating updates, content_uri intact.
  - R4 coverage sweep (1867 "Bad Guy"): rated 100→90 on the sheet; only
    Soul selected (1867 belongs only to the deselected Brass and Five
    Stars playlists) → Sync → "Pushed 1 track rating(s) in one bulk
    request" → server 1867 = 90, local 90, edit cleared. Re-selected
    Brass, Synced again (clean, 0 rating lines) — selection restored to
    the original [Brass, Soul].
  - Phase 7 overlap, case a (non-current queued track missing): fixture
    5-track Brass queue, current = 1871 @ 30000 ms, non-current 1872
    deleted from synced_tracks + playlist_tracks; cold launch →
    PlaybackState PAUSED @ position=30000, active item id=2 (1871's index
    in the surviving queue), media session queue size=4 (was 5), no crash.
  - Phase 7 overlap, case b (current track missing): same fixture, current
    1871 deleted instead → cold launch → PAUSED, active item id=0 (first
    surviving track, 1196), queue size=4, no crash. (1871 was restored to
    the DB afterwards.)
  - Defect found and fixed during verification: rating committed on the
    sheet left the detail/search screen rows behind it stale (the sheet
    refreshes only BrowseProvider). Added a nowPlayingSheetOpen listener
    that reloads the screen's own list on sheet close in
    playlist_detail_screen.dart, album_detail_screen.dart,
    artist_detail_screen.dart, search_screen.dart (uncommitted in the
    working tree; see DEVIATIONS). Verified end-to-end: rated 100→70 on
    the sheet, closed it, the row underneath read "Rated 3.5 of 5".
  - Restore: PUT /api/library/tracks/{id}?rating=N for all five test
    tracks (874→55, 743→62, 1873→60, 1867→100, and 876→80 — 876 was
    accidentally rated 80→90 during gesture testing and that 90 had been
    pushed to the server); a final Sync ran clean; GET-verified all five
    server values match the originals. Local DB matches for all five
    (874 and 876 were written locally to the server values directly, since
    they are outside the selected playlists and no pending edit — see
    invariant 30); pending_track_edits empty.

NOT VERIFIED — implemented but not exercised, and why
  - The three §7B hardware checks (Bluetooth/AVRCP transport control,
    headphone-unplug pause, Doze/background sync delivery) — the emulator
    cannot run them; handed to the user (see below), not claimed.
  - A rating PUSH through the playlist-loop path (S == base for a track in
    a selected playlist): every bulk push observed went through the
    coverage sweep (874/876, 1867). The loop's reconciliation logic was
    exercised in both other directions (pull, server-wins), but a loop-path
    push was not observed.
  - The row stars for 1867 after its sweep push were confirmed via DB +
    API, not re-read on screen (the list-painting wedge below made the
    Brass detail screen unreliable at that point).
  - The sync screen's "Offline" banner state machine under repeated
    toggles beyond the single airplane-mode cycle tested.

DEVIATIONS — anything not done as the phase specified
  - Precision-loss (the control quantizes, the server does not): the app
    displays round(rating/10) half-stars (ties round up — Dart .round())
    and edits snap to multiples of 10. The server accepts any 0–100, so a
    server value like 55 displays as 3.0 and the nearest editable values
    are 60/50. This is the control's resolution, reported as specified.
  - 200-vs-204 plan correction: the plan assumed the bulk rating endpoint
    returns 204; this OwnTone server returns 200 for
    PUT /api/library/tracks/{id} (and the bulk path). The worker accepts
    any 2xx, so behaviour is unchanged; noted for the record.
  - Phase 7 overlap used DB fixtures (playback_state queue rows +
    deleted-track surgery) instead of playing a Brass queue through the
    UI — allowed by the handoff ("Phase 7 precedent used DB fixtures")
    and forced in practice by the list-painting wedge (UNKNOWN below).
  - 876 "Mr. Pitiful" (outside the four-track test set) was rated 80→90
    during gesture testing, the 90 was pushed, and it was restored to 80
    at the end (GET-verified).
  - Playback-stat side effects on the server from this session: 66
    pre-existing play events were uploaded in the first sync, Black Ice
    (1873) was played past the 240 s completion threshold once, and 743
    had sub-threshold plays — so play_count/time_played for those tracks
    advanced. Ratings (the Phase 8 subject) are fully restored.
  - The verification found and fixed one defect (stale detail/search rows
    after a sheet rating commit). The 4-file fix is UNCOMMITTED in the
    working tree (branch audio_player; the Phase 8 implementation itself
    is committed as f22db4c).
  - One stray tap on the sync screen briefly selected the Five Stars
    playlist (selection 2→3→2…); the final selection was verified back to
    the original [Brass, Soul] in shared_prefs + synced_playlists.

BUILD
  flutter analyze:
    No issues found (full project, final tree including the 4-file fix;
    all debug instrumentation used during diagnosis removed).
  flutter build apk --debug:
    ✓ Built build/app/outputs/flutter-apk/app-debug.apk

UNKNOWN — behaviour you could not explain
  - Mid-session, after an airplane-mode on/off cycle plus force-stop
    relaunches, ListView/ListView.builder on some screens painted only the
    first item (library: 1 of 2 playlist rows; search: section header with
    0 rows) while the plain-Scaffold Sync screen painted all rows. No
    framework error in an attached flutter run; LayoutBuilder constraints
    inside the broken lists were correct (h=706/772, right item count) —
    a paint problem, not layout; reproduced under Impeller/OpenGLES and
    under --enable-software-rendering; survived an adb reboot; a fresh
    element (tab bounce) painted correctly; uiautomator returned zero
    labels for the app during the wedge while the system Settings app
    still dumped. No app code changed between the last good render and the
    first blank one, so this is not attributed to Phase 8 code. Promoted
    to invariant 32 with the constraint evidence and a recovery recipe.
  - The OwnTone server intermittently dropped rapid consecutive PUTs
    (curl exit 000) but succeeded when spaced 1–2 s apart. Transient
    server/LAN behaviour; all values were re-PUT and GET-verified.

§7B hardware checks — for the user (not run; the emulator cannot run them)
  1. Bluetooth/AVRCP: pair the phone, start playback from the app, and
     press play/pause/next/skip on a BT headset or car unit; the app's
     media session (audio_service) should follow the remote transport
     commands.
  2. Headphone-unplug pause: plug in wired headphones, play a track, unplug
     — the app should auto-pause (AudioService default behaviour).
  3. Doze/background sync delivery: on a physical phone with Wi-Fi, force
     the app to the background, let the device enter Doze, and confirm the
     WorkManager `sync-task` still runs at its scheduled window
     (logcat -s BackgroundSyncWorker on the phone, or a visible
     "Background sync completed").
