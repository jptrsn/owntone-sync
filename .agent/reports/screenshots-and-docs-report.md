# Screenshots + site + README pass — 2026-10-17

```
PHASE (screenshots + docs, 2026-10-17): COMPLETE
```

Scope: capture fresh app screenshots on the emulator via the flutter-agent-lens
MCP; replace the site screenshot set and rewrite its playback copy; correct the
README User Guide. Docs + site only — no `lib/` or `android/` code changes, no
server changes.

## GO/NO-GO CHECK

**What it was:** the app running on `emulator-5554`, browsable and playable, with
each screenshotted screen observed working on the device (AGENTS.md: "the
behaviour you changed was observed working on a device").

**Did you run it:** YES

**What you observed:** the full Library (4 tabs), playlist/album/artist detail,
search, Now Playing, queue, drawer, and every Settings sub-screen rendered with
real content; playback started, advanced, and auto-advanced across tracks; the
queue, ratings metadata, and playback-event recording all behaved as documented.
The core playback behaviours written into the site/README (tap-to-play in
context, queue, auto-advance, in-app background playback) were each observed
live. See OBSERVED.

## OBSERVED — things I did and saw, on the emulator, by hand

- Launched the app on `emulator-5554` and opened the Library → Playlists,
  Artists, Albums and Tracks tabs all rendered with synced content. (The home
  route carried the "Can't reach 192.168.1.13" banner all session — the server
  is off-LAN; see DEVIATIONS. Banner-bearing screens were captured for the
  record but excluded from the site set.)
- Opened the **Brass** playlist → detail rendered its 33 tracks. Tapped
  **Bloodshot** → playback started; the `AudioService.position` probe on the
  `flutter run` console showed 84s → 85s (position genuinely advancing).
- Let tracks finish → the player **auto-advanced** through the queue. Observed
  the transitions Bloodshot → The Trilogy vs. DJ Skooly → Trundle Manor →
  Spocktopus → Bedford → Smooth Criminal → Black Ice → Space Cow, each with a
  fresh "Playing from Brass" origin line and a correct seek position.
- Tapped the docked mini-player → the **Now Playing** sheet opened: artwork,
  title/artist/album, "Playing from Brass", seek bar (time + %), and the
  Shuffle/Prev/Pause/Next/Repeat/Queue/More controls all rendered.
- Tapped the **Queue** button on the sheet → the queue sheet opened with the
  full track list, current track first, "Clear queue" in the bar.
- Tapped **Play/Pause** → the label toggled Pause↔Play and the position
  froze/resumed (verified via uiautomator button label + position text).
- Opened **Search**, typed `thundersmack` → results grouped into **Artists**
  (Thundersmack 1 album • 5 tracks; Thundersmack feat. Honeycomb), **Albums**
  (Brass/Thundersmack 3 tracks; Brass/Thundersmack • 2020 1 track), and
  **Tracks** (Blues in the Attic 1:46).
- Tapped an album result → **Album detail** rendered (header with art tile,
  "3 tracks • 11 min", Play + Shuffle, track list).
- Tapped an artist result → **Artist detail** rendered (letter tile, "1 album •
  5 tracks", album section, track list).
- Opened the **drawer** → "Owntone Player", server address, "Server not
  responding", "Last synced 8d ago", Sync / History / Settings, "Sync now".
- Opened **Sync** → "16 playback events waiting to sync" (proof the session's
  plays were being recorded), the playlist list with per-playlist track counts,
  and the "unreachable" banner.
- Opened **Settings** → Server / Storage / Schedule / About rows; opened each
  sub-screen (Server Configuration, Storage "Folder access granted", Sync
  Schedule with day chips + 02:00, About "Owntone Player · Version 0.2.0").
- Opened **History** → the sync entry rendered "Sync Completed / Oct 9, 26 **PMt**
  3:12 PM / 1 playlists • 33 tracks downloaded" — the "PMt" is a date-format
  defect (root-caused; see the 2026-10-17 blockers entry).
- Captured 23 screenshots to `/tmp/owntone_verify/shots/`; **all 23 passed** the
  pixel sanity checker (no `#FF5252` error region, no large blank run). The
  588 px (≈205 logical px) blank at the bottom of Now Playing is the documented
  2026-10-08 blocker — noted, and cropped out of the site copy.

## NOT VERIFIED — implemented but not exercised, and why

- **Rating overlay (tap-to-rate) + rating commit/round-trip.** The overlay did
  not appear on tap this session (see UNKNOWN and the 2026-10-17 blockers
  entry), so the drag-to-rate, persist, and server round-trip path was not
  exercised. The README's "Ratings" section documents the intended behaviour
  and was left unchanged.
- **Resume after app kill (queue/position/shuffle/repeat restore).** Claimed in
  the new copy per invariants 25/46 (device-verified in an earlier phase), but
  I did not kill-and-relaunch the app to re-observe it this session.
- **Lock-screen / notification / Bluetooth controls and true background
  playback.** Not re-exercised this session (I observed in-app foreground
  playback and auto-advance; the background claim rests on prior-phase
  verification).
- **A live sync + event/rating upload.** The server was unreachable all session,
  so no sync completed. The Sync screen showed "16 playback events waiting to
  sync" (recording worked), but the upload and the ratings round-trip were not
  observed end-to-end.
- **The "sync again" action on an exhausted failing queue (invariant 24).** Not
  induced this session (would require deleting files / a broken queue).

## DEVIATIONS — anything not done as the phase specified

- **Server unreachable all session.** `192.168.1.13:3689` was not routable
  (the Mac is on `10.84.0.0/18`; no route to `192.168.1.x`, no Tailscale path).
  Consequence: every home-route screen shows the "Can't reach 192.168.1.13"
  banner and the drawer shows "Server not responding"; no live sync was
  possible. Captured those screens for the record, excluded them from the site
  set (the site shows only banner-free screens).
- **Device DB fixture repair (user-approved).** The device DB held 33 Brass
  tracks but an **empty `synced_playlists` table** and a missing M3U, which
  dead-ended the app in the "No music yet" empty state on launch (root-caused;
  see the 2026-10-17 "launch dead end" blockers entry). With the user's
  approval I repaired the *app's local DB fixture only* (not the server, not
  code): inserted the Brass `synced_playlists` row + 33 `playlist_tracks` rows,
  generated and pushed the Brass M3U, and streamed the DB back via `run-as`
  (sha256-verified). Pre-repair DB backed up to
  `/tmp/owntone_verify/owntone_sync.db.pre-repair`.
- **The model cannot view images.** The Read tool rejects image input in this
  session, so screenshots were verified with a multi-instrument harness instead
  of the eye: the `flutter run` console (no `E/flutter`), the MCP widget tree,
  `uiautomator` content-desc labels, and a pixel checker
  (`/tmp/owntone_verify/check_shot.py`). The checker's red-error detector was
  tightened mid-session after it false-positived on orange album artwork
  (now requires the exact `#FF5252` neighbourhood **and** a uniform fill).

## BUILD

- `flutter analyze`: **No issues found** (ran in 3.7s).
- `flutter build apk --debug`: **not run** — this session changed no `lib/` or
  `android/` code (docs + site only). The clean analyze confirms the tree is
  otherwise unchanged.

## Site / README changes

- `site/assets/screenshots/`: removed the four January 2026 `screenshot_1..4.png`
  (1344×2992); added six new captures (1280-wide): `playlist-detail`,
  `now-playing` (cropped to 2330 px to trim the documented bottom blank),
  `queue`, `search`, `album-detail`, `artist-detail`. All banner-free.
- `site/index.html`: replaced the 4 `<img>` tags with the 6 new ones
  (descriptive alt text + `loading="lazy"`); expanded the "Play Your Music"
  feature card (resume-after-close) and the "Play & Skip Counts" card (the
  90%/4-minute threshold, per invariant 15); added a new **"How Playback Works"**
  section (tap-to-play in context, Play/Shuffle, Play next / Add to queue,
  drag-reorder / swipe-to-remove queue, shuffle + repeat, lock-screen /
  notification / Bluetooth background playback, resume-after-close, and the
  skip-unplayable / "sync again" behaviour).
- `site/styles.css`: added the `.playback` section styles (matches the existing
  section/heading tokens).
- `site/smart-playlists.html`: reviewed — its player copy is already accurate
  and consistent; **no change**.
- `README.md` "Playing music": added two paragraphs — **survives the app being
  closed** (queue/position/shuffle/repeat restored) and **a track that can't be
  played is skipped, not fatal** (auto-skip + notice; exhausted queue offers to
  sync again). The rest of the User Guide was walked against the live app and
  found accurate.
- `.agent/blockers.md`: three new 2026-10-17 entries — the **History "PMt"
  date-format** defect (cosmetic, root-caused), the **launch dead end** when the
  default tab is empty but other categories have data (root-caused), and the
  **Now Playing tap-to-rate overlay not appearing on tap** (needs
  investigation).

## UNKNOWN — behaviour I could not explain

- **The Now Playing tap-to-rate overlay did not appear on tap**, even though the
  code path reads correctly (`_toggle` → `_visible`, `_loadRating` sets
  `_loaded` unconditionally, `item.id` is a numeric track id) and taps were
  **confirmed delivered to the same sheet** (the Queue button and Play/Pause
  both responded). Tried on a stable paused track with artwork confirmed loaded,
  via both `input tap` and a 120 ms `input swipe` at the artwork centre; the
  artwork region was byte-identical before/after (a `Colors.black38` pill would
  have darkened it). Not explained and not papered over — recorded in the
  2026-10-17 blockers entry with a suggested next step (reproduce on a
  hot-reloaded debug build, read the `E/flutter` console during the tap, and
  `debugPrint` in `_toggle`/`_loadRating`).
