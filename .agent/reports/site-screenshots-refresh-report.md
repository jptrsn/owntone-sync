# Site screenshot refresh pass — 2026-10-22

```
PHASE (site screenshots, 2026-10-22): COMPLETE
```

Scope: replace the six site screenshots (`site/assets/screenshots/`) with fresh
captures of the current UI, on the emulator, via the flutter-agent-lens MCP.
Site assets only — no `lib/` or `android/` code changes, no server changes.

## GO/NO-GO CHECK

**What it was:** each screenshotted screen observed working on the emulator
with real content, captured with the MCP screenshot tool, and the new files
replacing the site set (AGENTS.md: "the behaviour you changed was observed
working on a device").

**Did you run it:** YES

**What you observed:** the full first-run setup flow worked end to end (URL
→ audio permission → SAF Music folder → playlist selection → sync →
first-successful-sync notification prompt, invariant 44); the Library's four
tabs, playlist/album/artist detail, search, Now Playing sheet, and queue
sheet all rendered with synced content; playback started, auto-advanced
across tracks, and paused; all six screens were verified rendered (uiautomator
dumps + MCP widget tree) before capture, and pixel-checked after capture.
See OBSERVED.

## OBSERVED — things I did and saw, on the emulator, by hand

- Launched `Pixel_9_Pro_API_36` (identity confirmed via lsof on the qemu pid
  per invariant 42; it came back as `emulator-5554`). The AVD's display was
  already at the 2026-10-17 pass's geometry — **1280×2856 @ 480dpi (dpr
  3.0)** — so no resize was needed; all captures are 1280-wide, matching the
  replaced set.
- Built the current debug APK (`flutter build apk --debug`, 160 MB) and
  installed it over the stale v0.3.1 release build (see DEVIATIONS 1 for why
  the old app's data was wiped).
- Drove the first-run setup through the app's own UI: empty Library →
  "Set up sync" → SyncScreen → "Configure Server" → typed
  `http://192.168.1.13:3689` into the URL field (dump-confirmed) → **Test
  connection rendered "Connected to 192.168.1.13"** → Save → storage step →
  "Grant Permission" → system audio dialog "Allow" → SAF picker (Music
  pre-suggested) → "USE THIS FOLDER" → "ALLOW".
- "Load Playlists" → console `💡 Fetched 13 playlists from server`; the
  selection list rendered all 13. Selected **Brass only (33 tracks)** per
  invariant 42's user decision (disk management). Tapped Sync.
- Sync ran in the background: logcat `BackgroundSyncWorker` downloaded all
  33 tracks, `Artwork resolution complete: 21 embedded, 0 server, 12 absent,
  0 failed`, `Background sync completed: 33 tracks downloaded in 78429ms
  (status=success)`; the Dart side logged `🐛 Subscribed to sync progress
  events` → `💡 Sync completed with status: success` (invariant 52's
  completion path) and the Library auto-refreshed to the populated state.
- The first-successful-sync **notification prompt** appeared (invariant 44);
  allowed it.
- Opened **Brass** → playlist detail rendered the 33-track list, Play/Shuffle,
  header "Brass — 33 tracks". Tapped a track row (Good People) → playback
  started; the mini player docked with "Now playing / Good People /
  Thundersmack feat.Honeycomb • Brass / 2:58" and a Pause button (dump-
  confirmed, bottom-docked at y 2622–2766). **Captured playlist-detail.**
- Playback **auto-advanced** across the queue (mini player text observed
  moving Good People → Times Square → Pastime Paradise → Bloodshot across the
  captures) — the site's "how playback works" claim, observed live again.
- Albums tab → opened **Unlearn / Youngblood Brass Band (10 tracks, 53 min)**
  → album detail rendered header + track list + Play/Shuffle, mini player
  docked. **Captured album-detail.**
- Artists tab → opened **Thundersmack (1 album • 5 tracks)** → artist detail
  rendered letter tile, "1 album • 5 tracks", the Brass album section and its
  5 track rows, mini player docked. **Captured artist-detail.**
- Search → typed `thundersmack` → results grouped **Artists** (Thundersmack
  1 album • 5 tracks; Thundersmack feat.Honeycomb), **Albums** (Brass/
  Thundersmack 3 tracks; Brass/Thundersmack • 2020 1 track), **Tracks**
  (5 rows); mini player docked with album art in the art region (pixel-
  checked). **Captured search.**
- Tapped the mini player → **NowPlayingSheet** opened (MCP widget tree
  confirmed the sheet mounted with its ListView). The playing track was
  "Pastime Paradise" (Youngblood Brass Band • Unlearn): its artwork was
  resolved on sync — DB row `artwork_path` set to the app-private cache file
  (`597b1ca1….jpg`, `artwork_source='embedded'`, 240×240 JPEG, file
  existence confirmed via run-as). **Captured now-playing** (full height).
- Tapped the sheet's **Queue** button → the queue sheet opened over it with
  the full track list and "Clear queue" (dump-confirmed). **Captured queue.**
- Closed both sheets (back ×2) and paused playback (media key; the control
  flipped Pause→Play). The app was left on the Search screen, paused, Brass
  synced, at v0.3.2+21.
- Pixel sanity check on all six captures (PIL): **no `#FF5252`-class error
  region** (red_frac 0.0000 in all six), no anomalous blank runs except the
  now-playing bottom blank (see crop below) and the artist-detail list
  remainder (short list, normal). All six mean-pixel-diffed against the old
  set (6.8–13.5) — genuinely new renders, not re-saves.
- The unreachable-server banner was **absent** by construction: the server
  was reachable all session (probe + sync), so the state was `reachable`,
  which renders nothing (invariants 40/41). No banner-exclusion was needed,
  unlike the 2026-10-17 pass.
- `flutter analyze`: **No issues found** (4.6 s). `flutter test`: **159/159
  passed** (9 s). No `lib/`/`android/` files were touched, so the suite's
  result is unchanged from `main`.

## NOT VERIFIED — implemented but not exercised, and why

- **Visual review of the final images.** The model in this session cannot
  view images (the Read tool rejects image input), so the captures were
  verified by instrument instead: the pre-capture uiautomator dumps (named
  text/content-desc per screen), the MCP widget tree (NowPlayingSheet
  mount), the pixel checks above, and the artwork DB/file evidence for the
  now-playing shot. Same constraint as the 2026-10-17 pass, same workaround.
  A human glance over the six PNGs before the site deploy is still worth
  doing.
- **The queue's drag-reorder and swipe-to-remove** (invariant 28): the queue
  sheet was opened and captured, but no reordering was performed — a fast
  swipe would have silently rewritten the live shuffle permutation, and the
  capture needed a stable list.
- **Lock-screen / notification / Bluetooth background playback:** playback
  ran only in-app foreground this session; the background claims rest on
  prior-phase verification, as in the 2026-10-17 pass.

## DEVIATIONS — anything not done as the phase specified

1. **The AVD's prior app data was wiped by a wrong-artifact install.**
   `flutter install -d emulator-5554` selected a **stale `app-release.apk`**
   (v0.3.1, Oct 21) left in `build/app/outputs/flutter-apk/` instead of the
   freshly built `app-debug.apk`, and re-installing over the existing
   (differently-signed) app **uninstalled it first**, wiping the 2026-10-22
   session's data (Rediscover seed, schedule, prefs). No host-side DB
   backup survived (the 2026-10-22 `/tmp` wipe, invariant 12's correction),
   so recovery was a genuine first-run setup through the app's UI (which the
   pass then verified anyway). The `build/app/outputs/flutter-apk/`
   directory now holds stale release artifacts alongside the debug one —
   future installs must use the explicit
   `adb install build/app/outputs/flutter-apk/app-debug.apk` path, not
   `flutter install`, or the directory should be cleaned before release
   builds land there.
2. **The library was rebuilt from scratch, Brass only** (invariant 42's user
   decision, "do not re-sync Soul unless asked" — the current server has no
   Soul in the playlist list at all). The 2026-10-17 device fixture
   (Brass + Rediscover) is not reproducible from any surviving backup and
   was not needed: Brass alone populated every screenshotted surface.
3. **The now-playing crop is 2280 px, not the previous 2330 px.** The crop
   trims the documented bottom blank (blockers 2026-10-08) below the
   controls; the new UI's content bottom was **measured** at y=2223 (last
   non-background row above the nav pill; blank below = 626 px ≈ 209
   logical px, consistent with the entry's "~205 logical px"), so the crop
   lands 19 dp below the content rather than at the old pass's 2330.
4. **Playback events were recorded on the real server.** Auto-advance carried
   ~6–8 tracks to completion between the playback start and the pause, so
   their play events are in `pending_events` and will upload on the next
   sync — the app's normal, intended behaviour (invariant 15), exactly what
   the 2026-10-17 pass also left behind ("16 playback events waiting to
   sync"). No ratings or playlist membership were touched; nothing was
   written to the server except via the app's own event pipeline.
5. **A physical Pixel 6 (`25071FDF600953`) was attached with the app
   running** (and is the user's phone). Per invariant 42 it was not touched:
   no install, no driving, no install-on-phone. All work ran on the AVD.
   (A VM-service connection to the phone's running app was made during
   device discovery before the attachment was recognised as the phone; it
   was read-only and disconnected before any device work.)

## BUILD

- `flutter analyze`: **No issues found** (ran in 4.6 s).
- `flutter build apk --debug`: **succeeded** (160 MB `app-debug.apk`, the
  installed artifact — v0.3.2+21).
- `flutter test`: **159/159 passed**.
- Kotlin unit tests not re-run — no `android/` changes.

## UNKNOWN — behaviour I could not explain

- **Post-sheet-close layout oddity on the Search screen (dump-only).**
  After the Now Playing sheet and the queue sheet were both closed with
  back, the next uiautomator dump of the Search screen reported the mini
  player band at y 1650–1848 (middle of the screen; normally 2586–2784),
  the first track row squashed to half height (102 px vs 216 px), and four
  of the five track rows absent from the dump. Cross-checks: the screen was
  pixel-stable (two screencaps 2 s apart, zero differing rows), the
  `flutter run` console was clean (no `E/flutter`), the nav stack showed
  exactly `/` + `SearchScreen`, and navigation from that state worked. The
  oddity appears in **no captured state** — all six deliverable captures
  were dump-verified with the mini player bottom-docked (Pause at y
  2622–2766 in each) and the search shot's art region pixel-confirmed. It
  may be an Impeller dump artifact (invariant 42's "screencap lie two") or a
  transient layout condition after two modal sheets dismiss; not explained,
  not reproduced on a second cycle, and not visible in any deliverable. If
  it is ever seen in a user report, the first step is an attached
  `flutter run` (invariant 29), not this entry.
