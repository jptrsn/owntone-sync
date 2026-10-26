PHASE: remove track number from playlist detail rows — COMPLETE

Requested 2026-10-26: the playlist detail row showed the track's
`track_number` (or a music-note icon when 0) in the 40 px leading column;
remove it so title/artist/album get the width. User confirmed the option to
reclaim the whole column (also freeing the blank column on search /
artist / all-tracks rows, which already pass no leading). Album detail
still shows track numbers — out of scope, untouched.

Diff: `playlist_detail_screen.dart` drops the `leading:` argument;
`library_rows.dart` `TrackRow` reserves the 40 px slot only when a leading
is supplied or the row is the now-playing row. Invariant 54 added.

GO/NO-GO CHECK
  What it was: on-device before/after rendering of the playlist detail
    rows' leading content, via uiautomator semantics dumps (no vision
    model available — assertions read content-desc text, not screenshots).
  Did you run it:        YES
  What you observed: same harness on OwnTone_U2_API_36 (emulator-5556),
    synced 33-track playlist "Brass":
      BEFORE (git-reverted code installed): 33 rows, all four probed
        titles present, 18 rows whose merged content-desc began with a
        track-number segment ('1\nGood People\n…', '7\nPastime
        Paradise\n…').
      AFTER (working-tree code installed): 33 rows, all four probed
        titles present, 0 rows with a track-number segment.

OBSERVED — things you did and saw, on the emulator, by hand
  - Tapped through setup on a data-wiped app state: Set up sync →
    Configure Server → typed http://192.168.1.13:3689 (driver `tap` +
    `enter_text` on the TextField) → Save → Load Playlists → ticked Brass
    (row read "Brass\n33 tracks") → Sync → progress banners "Syncing:
    Brass", "Playlist 1/1 - Track 18/33" … 26/33 → completion.
  - Storage re-grant: tapped Grant Permission → drove the native
    DocumentsUI picker (uiautomator bounds + `input tap`) → USE THIS
    FOLDER (Music root) → ALLOW.
  - Opened the Playlists tab → Brass row → detail screen; rows rendered
    title + "artist • album" + duration (uiautomator content-desc, rows
    collected across the full scroll extent, 33 unique).
  - Harness sanity check first (AGENTS.md trap): the same numbered-row
    detector saw 18 numbered rows on the pre-change build before the
    post-change "0" was believed.
  - Server reads only (GET /api/library, /api/library/playlists,
    playlists/11/tracks). No server state modified. Playback never
    started; no track was played.
  - flutter analyze → No issues found; flutter test → 159 passed;
    flutter build apk --debug → built.

NOT VERIFIED — implemented but not exercised, and why
  - The now-playing `graphic_eq` icon in a playlist row (new `isCurrent`
    branch of the leading slot): starting audible playback needs the
    user's explicit confirmation of that specific action (audio safety),
    so it was not exercised. The branch's code is the previous
    `SizedBox(width: 40) + Icon` moved out of an always-present wrapper.
  - Album detail's track-number leading (code untouched by the diff; not
    re-observed on device).

DEVIATIONS — anything not done as the phase specified
  - `TrackRow` is shared, so the freed 40 px column also affects search,
    artist-detail and all-tracks rows (blank column removed there too).
    Called out to and approved by the user before editing.
  - Verification harness: the MCP flutter-driver tool reported the driver
    extension disabled and hung (`waitUntilNoTransientCallbacks` never
    resolved) even though the raw `ext.flutter.driver` RPC answered
    instantly; and `package:flutter_driver`'s client hung after connect.
    Fell back to raw VM-service WebSocket RPC for taps/entry +
    `set_semantics`, then uiautomator dumps for assertions. Temporary
    scaffolding (flutter_driver dev-dep, `test/driver_main.dart`,
    `test_driver/`) was created for this and fully removed afterwards.
  - Used the OwnTone_U2_API_36 AVD (own instance, killed after the
    session) instead of the shared emulator-5554, per user instruction.

BUILD
  flutter analyze: No issues found! (ran in 2.7s)
  flutter build apk --debug: ✓ Built build/app/outputs/flutter-apk/app-debug.apk
  (flutter test: +159 All tests passed!)

UNKNOWN — behaviour you could not explain
  - The AVD's app data (server URL, SAF grant, previously-synced Brass)
    disappeared mid-session, between two host-side reinstall cycles;
    neither `adb install -r` nor force-stop explains it. The other active
    session on this machine may have touched the app or AVD. Re-created
    the state (server configured, storage granted, Brass synced) — the
    device is left richer than found, not poorer.
  - The MCP dart `flutter_driver` tool's extension probe hangs while the
    identical raw RPC works; not root-caused (tooling, not app).
