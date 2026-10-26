# Screens — navigation and pre-capture assertions

Device: `OwnTone_U2_API_36` AVD, `dev.educoder.owntone_sync`, display
1280x2856 (confirm with `wm size`). Output dir: `site/assets/screenshots/`.
All `waitFor`s go through the raw driver (see driver.md). Content-desc
assertions via uiautomator dump. Synced test content: server playlist
**Brass** (server id 11, 33 tracks) from `http://192.168.1.13:3689`; known
rows: `Good People` (Thundersmack), album `Unlearn` (Youngblood Brass Band,
track `Pastime Paradise`), artist `Too Many Zooz` (track `Bad Guy`).

Before anything: `set_semantics` once; assert Library with
`waitFor "Playlists"` — but **confirm the screen** before tapping: SyncScreen
also contains `Playlists` and `Brass` rows (the picker). Discriminators:
Library has `Albums\nTab 3 of 4`; SyncScreen has `1 playlists selected` /
`Sync Options`.

## 1. playlist-detail.png
1. Library (Playlists tab): `waitFor "Brass"` → `tap "Brass"`.
2. Gate: `waitFor "Play"` (header Play button) and `waitFor "Good People"`.
3. Assert dump: row content-descs like
   `Good People\nThundersmack feat.Honeycomb • Brass\nRated 5.0 of 5\n2:58`;
   **zero** standalone digit nodes 1..33 (invariant 54 — playlist rows are
   lead-free; album rows keep numbers).
4. `adb exec-out screencap -p > playlist-detail.png`.

## 2. album-detail.png
1. `keyevent 4` → Library → `tap "Albums"` (tab).
2. `find_scroll "Unlearn"` → `tap "Unlearn"` (album list is alphabetical and
   lazy; rows below the fold are invisible to ByText).
3. `find_scroll "Pastime Paradise"`; swipe back to top; sleep 1.
4. Assert: `Unlearn` + `Pastime Paradise` in dump; numbered rows may show
   digits in content-desc (`2\nAcousticon Theme\n…`) — expected here.
5. Capture.

## 3. artist-detail.png
1. Back → Library → `tap "Artists"` → `find_scroll "Too Many Zooz"` → tap.
2. `find_scroll "Bad Guy"`; swipe to top.
3. Assert `Too Many Zooz\n6 albums • 13 tracks` (counts may drift with the
   library — match on the artist name + `albums •`).
4. Capture.

## 4. search.png
1. Back → Library (assert `Back` + `Search` content-descs present — the
   Search icon is Library-only; on detail screens it times out).
2. `tap` tooltip `Search` → `tap` ByType `EditableText` → `enter_text "zooz"`.
   The field starts empty; if revisiting, it keeps the old query — clear or
   use a fresh query rather than assuming.
3. `find_scroll "Bad Guy"`; swipe to top.
4. Capture.

## 5–6. now-playing.png + queue.png (playback — audio-safety gate)
Mute first: `cmd media_session volume --stream 3 --set 0`. Record server
counts for the chosen track (see SKILL.md). Play from the **search results**
(`tap "Bad Guy"` — two matches → scroll it into view; use the result row,
Descendant under the list if ambiguous) or an album's `Play` button
(album art guaranteed — good for now-playing).
1. Immediately `tap` tooltip `Pause` (<2 s; server `/api/player` must stay
   `stop` — the app plays local files, never the server output).
2. `tap` ByType `MiniPlayer` → sheet. Gate: `waitFor` tooltip `Queue`.
3. Assert dump: `<title>\n<artist>\n<playlist>`, `0:00\n<m:ss>`,
   `Playing from <source>`. Capture **now-playing.png**.
4. `tap` tooltip `Queue` → gate: content-desc `Clear queue` (it is a
   content-desc, not a text — ByText will "fail"; don't panic). Capture
   **queue.png**.
5. Cleanup: tap `Clear queue`; back out of sheets. Verify sync screen says
   `No playback events waiting to sync` and re-read the track counts from the
   API — unchanged.

## Sizing sanity
All six: `sips -g pixelWidth -g pixelHeight` = device size; static shots
> 150 KB typical. **now-playing ≈ 140 KB = artwork rendered; ≈ 80 KB = no
artwork — re-shoot with a track from an album that showed artwork.**
Old committed PNGs are the size baseline (`git diff --stat`).

## First-run setup (only if `pm clear`ed or Library shows `No playlists synced`)
Drawer (`tap` tooltip `Open navigation menu`) → `Settings` → server tile →
tap field (ByType `EditableText`) → `enter_text "http://192.168.1.13:3689"` →
`tap "Save"`. Then drawer → `Sync` → `Grant Permission` →
uiautomator-tap `Allow` (permissioncontroller) → DocumentsUI usually opens
**already in Music** → `USE THIS FOLDER` → `ALLOW`. Then `Load Playlists` →
`tap "Brass"` → **assert `1 playlists selected`** → Descendant-tap ElevatedButton
`Sync` → `adb logcat -c` first, then poll `logcat -d -s BackgroundSyncWorker`
for `Background sync completed: 33 tracks`. `0 tracks downloaded` on a
re-sync is fine (DB already had them). If Library then shows
`No playlists synced`, you deselected by tapping the row again — reselect and
sync.
