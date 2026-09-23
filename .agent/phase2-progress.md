# Phase 2 progress snapshot (written at compaction boundary)

**Session state: Phase 2 implementation COMPLETE. Static verification PASSED.
Device verification IN PROGRESS with two known defects to fix (one root-caused,
one not yet). No work is mid-flight: all edits are saved on disk, the app
session is stopped.**

Resume order: (1) rebuild apk, (2) fresh `flutter run -d emulator-5554` with a
NEW log file, (3) reproduce the `Bad state` on PlayerScreen and capture its
FIRST full stack trace (previous log lost it to exception deduplication),
(4) fix root cause, (5) apply the fast-path URI fix below, (6) rebuild,
(7) sync a 100+ track playlist via the app UI, (8) full go/no-go verification,
(9) PAUSE playback before ending, (10) re-read verification-protocol.md and
write the §6-format report.

---

## What Phase 2 is

Refactor plan §3 Phase 2: PlaybackController facade + DI + delete PlayerProvider
+ URI-resolution performance. Docs: `.agent/player-ux-spec.md`,
`.agent/player-refactor-plan.md`, `.agent/verification-protocol.md`.
User CONFIRMED the plan with three corrections (all incorporated):
1. `AudioService.position` is fine (PlaybackState.position is a computed
   extrapolated getter, audio_service.dart:267) — do not route around it; if
   the seek bar stalls, the bug is in handler emission or my wiring.
   Do NOT regress audio_handler.dart:43 (`_audioPlayer.position`).
2. Duration needs fallback: prefer player's decoded duration
   (`AudioPlayer.durationStream`, exposed via new handler getter), fall back to
   MediaItem.duration.
3. Keep player_screen minimal — fix §1.3 defects (buffered-as-duration,
   double-seek) and nothing more (Phase 5 replaces it wholesale).

## Implementation — DONE (all files saved)

- NEW `lib/presentation/controllers/playback_controller.dart`:
  PlaybackController(handler, resolver) — no Dart queue list.
  `playCollection(QueueOrigin, List<SyncedTrack>, {startIndex})` = only way to
  start playback (resolves URIs, filters unresolvable, remaps startIndex,
  delegates to handler). Intents: play/pause/stop/seek/skipToNext/skipToPrevious/
  toggleShuffle/cycleRepeat(off→all→one→off)/playNext/enqueue.
  Streams: mediaItem, playbackState, queue (from handler), queueOrigin
  (BehaviorSubject), positionData (cached; rxdart combineLatest3 of
  AudioService.position + bufferedPosition + duration; duration = combineLatest2
  of handler.durationStream ?? mediaItem.duration).
  Value types: QueueOrigin (kind playlist/album/artist/allTracks, id,
  displayName; redirecting const ctors), PositionData.
- DELETED `lib/presentation/providers/player_provider.dart` (0 references remain)
- `lib/main.dart`: no global audioHandler; handler built once in main();
  MultiProvider: SyncProvider (only instance), BrowseProvider (tree singleton),
  Provider<PlaybackController>.value; debug FAB takes controller
- `lib/presentation/widgets/debug_play_button.dart`: takes controller; plays
  whole synced library via playCollection(origin allTracks)
- `lib/presentation/widgets/mini_player.dart`: StreamBuilders on
  controller.mediaItem + playbackState; art from MediaItem.artUri (file scheme →
  FileImage w/ existsSync check, else placeholder asset)
- `lib/presentation/widgets/play_button.dart`: PlayButton + PlayableTile with
  optional collection/index/origin → tap = play-in-context (avoids single-item
  queue MUST NOT); menu: Play / Play Next (controller.playNext) / Add to Queue
  (controller.enqueue). PlayableTile Stack layout KEPT (Phase 6 deletes it)
- `lib/presentation/screens/player_screen.dart`: StreamBuilders; seek bar from
  PositionData (max=duration, seek on onChangeEnd only — §1.3 fixed);
  controls via controller; queue sheet from handler queue stream.
  Control button was ElevatedButton.icon (8px RenderFlex overflow) — FIXED to
  plain ElevatedButton with Icon child (fix saved, not yet compiled)
- `artist/album/playlist_list_view.dart`: long-press Play/Shuffle →
  fetch tracks from LocalDatabaseRepository → controller.playCollection with
  origin; shuffle = Random startIndex + toggleShuffle
- `track_list_view.dart` + 3 detail screens: pass collection/index/origin
  into PlayableTile
- `browse_screen.dart`: BrowseProvider from tree (initState construction removed,
  ChangeNotifierProvider.value wrapper removed)
- `track_uri_resolver.dart`: rewritten — `resolveCollection(tracks)`: prefer
  cached non-empty contentUri ('' = null), ONE batched `buildContentUris`
  channel call for the rest, cache-back to DB; old single/batch methods deleted
- `local_database_repository.dart`: ADDITIVE `updateTracksContentUri(Map<int,String>)`
  (transactional)
- `audio_handler.dart`: ONE additive change — `Stream<Duration?> get
  durationStream => _audioPlayer.durationStream;` (nothing else touched)
- `MainActivity.kt`: `buildContentUri` branch no longer hops to Dispatchers.Main
  (was running the SAF walk on the UI thread — worse than §1.5 documented);
  NEW `buildContentUris` batch branch; buildContentUri = fast ?: walk (walk body
  moved verbatim to buildContentUriWalk)

## Static verification — PASSED

- `flutter analyze`: 0 errors, 0 warnings, 1 info (pre-existing,
  sync_provider.dart:653, untouched file; identical to pre-change baseline)
- `flutter build apk --debug`: SUCCESS
- no file imports main.dart for audioHandler ✓
- `grep -rn "SyncProvider()" lib/` → exactly one construction (main.dart:45);
  the other match is the class constructor definition
- `grep -rn "PlayerProvider" lib/` → nothing

## Device verification — IN PROGRESS

Environment: `emulator-5554` = AVD `Pixel_9_Pro_API_36` (the pre-existing one;
a stray `flutter emulators --launch` attempt started nothing — one qemu PID only).
**This model has NO image input — screencap PNGs cannot be read. Verify UI via
`adb shell uiautomator dump` + `adb shell cat` + parse text/content-desc/bounds
(same approach as Phase 1 report). Taps via `adb shell input tap x y`.**
OwnTone server: 192.168.1.13 (LAN, as-is).

Observed (evidence from uiautomator dumps + logcat I caused):
- App opens on Sync tab (shell unchanged ✓); playlists visible: All Music 1794,
  Brass 33, Five Stars 502, Holiday Music 60, Master 1794, One Star 794,
  Recently Added 0, Recently Played 5; "1 playlists selected"
- Tapped debug FAB → ~30-60s later: `c2.android.mp3.decoder` created +
  BufferPool actively fetching → collection playing through controller
- `adb shell dumpsys media_session` (diagnostic): our package active=true,
  `state=PLAYING(3), position=54861, buffered=106872, speed=1.0`,
  **queue size=33** (Brass was the synced playlist → N=33, so the 100+
  go/no-go part is NOT yet satisfied — must sync a bigger playlist, e.g.
  Five Stars 502, via the app's own Sync screen checkboxes)
- Mini player never appeared in the UI tree while audio played (see defect 2 —
  same root cause suspected; mediaItem subject may be affected too)
- User (watching the emulator) tapped the mini player?? → PlayerScreen opened
  showing "From Now On / Youngblood Brass Band / Unlearn" with album art, but
  **seek bar + controls missing from tree** and error "Bad state: Stream has
  already been listened to" rendered on screen. User: "I don't hear any audio"
  (media session says PLAYING — stuck). User suspects the first ~2 tracks of
  the queue are bad files; "Car Alarm" is known-good from Phase 1 tests.

### DEFECT A (root-caused, fix designed, NOT applied)

`buildContentUriFast` fails for 100% of tracks: logcat spams
`W/DocumentFile: Failed query: java.lang.NullPointerException ... Cursor.getCount()
on a null object` (from `DocumentFile.exists()` on a non-resolving URI).
Diagnosis: `DocumentsContract.buildDocumentUriUsingTree(treeUri,
"tracks/foo.mp3")` goes through `Uri.Builder.appendPath` which keeps `/` as
segment separators, so the produced document URI is
`.../document/primary%3AMusic/tracks/foo.mp3` (multi-segment) instead of the
canonical single-segment `.../document/primary%3AMusic%2Ftracks%2Ffoo.mp3`.
The storage provider can't resolve it → null cursor → fast path null → walk
fallback (old per-segment findFile) did all the real work.
FIX (designed): construct the URI manually in buildContentUriFast:
```kotlin
val treeUri = Uri.parse(musicFolderUriString)
// guard: treeUri.pathSegments.size >= 2 && pathSegments[0] == "tree"
val treeDocId = treeUri.lastPathSegment          // decoded
val documentId = treeDocId + "/" + relativePath
val uri = Uri.parse("content://${treeUri.authority}/document/" +
    Uri.encode(documentId, null))                // encodes ':' and '/'
val doc = DocumentFile.fromSingleUri(this, uri)
if (doc != null && doc.exists() && doc.isFile) uri.toString() else null
```
Keep the `?: buildContentUriWalk(localPath)` fallback.

### DEFECT B (NOT root-caused) — the blocker

"Bad state: Stream has already been listened to" — rendered on PlayerScreen
where the seek control should be; repeats at roughly playback-event cadence.
PlayerScreen's `_buildSeekControl` StreamBuilder<PositionData> is the prime
suspect: `Rx.combineLatest3` result is SINGLE-subscription (rxdart 0.28),
cached in `_positionDataStream`, and PlayerScreen's StreamBuilder is (as far
as I can tell) its only listener. Could not confirm: the first full stack trace
was lost to the flutter tool's "Another exception was thrown" dedup in the log.
Everything else I audited is broadcast (just_audio subjects are
BehaviorSubjects; audio_service handler subjects are BehaviorSubjects;
AudioService.position is a broadcast controller — verified in pub-cache source).
NEXT: fresh run, fresh log, open PlayerScreen once, find the FIRST occurrence
with full stack (`grep -n "Bad state" <log>`, read surrounding lines; the first
one is NOT prefixed "Another exception").

### DEFECT C (cosmetic, fixed in code, not compiled)

PlayerScreen control buttons: ElevatedButton.icon with icon(size/2) +
SizedBox.shrink label + spacing 8 overflowed the 24px content box by 8px
(debug stripes). Fixed: plain ElevatedButton, child = Icon only.

## Facts verified in pub-cache source (do not re-derive)

- audio_service 0.18.19 (resolved): `PlaybackState.position` IS a computed
  getter: `updatePosition + speed*(now - updateTime)` while playing+ready
  (audio_service.dart:267). `AudioService.position` = static broadcast
  createPositionStream (16-200ms ticker). `MediaItem`: id/title non-null,
  album/artist/duration/artUri nullable. `BaseAudioHandler.playMediaItem` is an
  EMPTY default (why old PlayerProvider row-taps were already dead).
- just_audio 0.10.6: `_playbackEventSubject`, `_durationSubject` (seeded null),
  `_sequenceStateSubject` all BehaviorSubjects. `durationStream` replays on
  listen. sequenceStateStream re-emits on every playback event.
- rxdart 0.28.0: `Rx.combineLatestN` signatures require the COMBINE FUNCTION as
  last positional arg and N+1 type args (old list-returning form is gone).
- Flutter here: `Slider.onChanged` is REQUIRED (pass inert `onChanged: (_) {}`
  when seeking only on release).
- Debug FAB's status Text is CLIPPED inside the FloatingActionButton (Phase 1
  design, inherited; Phase 4 deletes the widget) — don't wait for it; use logs.

## Constraints/reminders

- PAUSE playback when testing is done (user instruction; the final verified
  run must end paused).
- Phase 2 ONLY. No Phase 3+ work (stats, NowPlayingSheet, shell, rows).
  Kotlin `recordPlayEvent`/`recordSkipEvent` handlers stay (Phase 3 removes).
  `content_uri` schema migration is NOT Phase 2 (in-code ''-as-null only).
- Do NOT modify sync download/upload pipeline; only the named additive changes.
- If spec is wrong/impossible → `.agent/blockers.md` + STOP, don't improvise.
- Report format: verification-protocol.md §6 template, every field mandatory;
  re-read that file before writing the report (not from memory).
- Go/no-go for Phase 2: debug FAB plays a collection THROUGH THE CONTROLLER +
  a 100+ track playlist starts without visible stall. (33 tracks is not enough.)
- Pre-existing latent bug NOTED, not fixed (out of scope): browse_screen.dart
  empty-state "Go to Sync" button calls DefaultTabController.of(context)
  (null → crash if tapped; unreachable while library has content).
- flutter run log from the broken run (superseded):
  /var/folders/tp/ykywdprs48xb2jjftd7_l2w00000gn/T/opencode/flutter_run.log

## Resume checkpoint (latest — fast-path verification BLOCKED by environment)

Status: Defect B (stream re-listen) fixed + verified in the original working
session. Defect A (fast path) fix implemented (openFileDescriptor validation)
and observed to build correct URIs + succeed for the majority of tracks, but
END-TO-END playback could not be observed: the emulator's SAF document-READ
access (openFileDescriptor) is intermittently DENIED after the debug APK
reinstall (21–231 tracks across runs), while tree-listing + writes work (Brass
sync: 33 downloaded, 0 errors). Re-grant (x3) + `pm clear` did NOT restore
reads. Media session stayed NONE (playback never started). Full report:
.agent/phase2-report.md (PHASE 2: BLOCKED).

Next step to attempt verification: full AVD reset (wipe emulator userdata),
then re-grant + re-sync + re-run the 100+ queue check. Uncertain payoff.

Key facts learned this session (do not re-derive):
- App's real local_path format is "tracks/<file>" (NO leading slash) —
  OwnToneApiClient.kt:144 `filePath = "tracks/$filename"`, FileOperations.kt:111
  `existingFiles.add("$directoryPath/${file.name}")`. A leading slash breaks the
  walk (split("/") yields an empty first segment) and the sync's skip check.
- The fast path's by-hand URI == the walk's buildDocumentUriUsingTree output
  (both `document/primary%3AMusic%2Ftracks%2F<file>`; Uri.encode == appendPath
  encoding). Confirmed the URI form is correct.
- The original fast-path defect was the query-based validation
  (DocumentFile.exists()/isFile -> query() on the single-document URI). The fix
  uses openFileDescriptor (the operation playback uses).
- Emulator storage: /data ~5.8G. Full library ~3.4G. Freed space by deleting
  324 track files (kept 200) + re-downloaded 33 (Brass). 231-233 files on disk.
