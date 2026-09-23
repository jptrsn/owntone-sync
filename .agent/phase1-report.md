PHASE 1: COMPLETE

GO/NO-GO CHECK
  What it was: Validate that content:// URIs play through just_audio's native path:
    (a) audio plays from a content:// URI, (b) media notification shows track title
    and artist, (c) the notification's NEXT button advances to the next track,
    (d) a track reaching its natural end auto-advances, plus pause → notification
    icon switches to play.
  Did you run it:        YES
  What you observed:
    - (a) After tapping the debug FAB, user heard audible playback of the first
      track on the emulator (20:20 and again after the play() fix; confirmed a
      second time on the final build at 21:33).
    - (b) User saw the media notification showing the track title and artist.
      Corroborated via `adb shell dumpsys notification`: a MediaStyle
      notification for dev.educoder.owntone_sync with title/subText/text
      strings whose lengths (16/7/37) exactly match the first track's metadata
      ("Acousticon Theme" / "Unlearn" / "Youngblood Brass Band feat. DJ Skooly").
    - (c) User tapped skip-forward on the media notification; logcat shows the
      active media item changing from "Acousticon Theme" (id=1548) to
      "Almost Never" (id=1577) at 20:27:13.
    - (d) With no user interaction, logcat shows the queue advancing track by
      track: Almost Never → Bad Guy (20:32:05) → Bedford (20:35:21) → … →
      Car Alarm (20:54:29) → … → Chandelier (21:03:48) → Da Bomba. User
      confirmed: "it's proceeding to the next track at each track end."
    - Pause/resume on the notification: user confirmed "pause and resume work
      as expected, icon state updates properly."

OBSERVED — things you did and saw, on the emulator, by hand
  - Tapped the debug FAB (agent tap via `input tap` at its dumped bounds,
    center ~921,2589) → TrackUriResolver logs show 10 tracks resolved to
    content://com.android.externalstorage.documents/... URIs; playbackState
    reaches playing=true, processingState=ready; user hears audio.
  - Ran `adb shell dumpsys notification` while playing → MediaStyle media
    notification present with title/artist/album strings matching the current
    track's metadata (check b).
  - Asked user to tap the notification's skip-forward button (agent could not
    access the shade UI; see DEVIATIONS) → logcat mediaItem change confirms the
    queue advanced by one track (check c).
  - Left the app running unattended → logcat mediaItem sequence advances
    through the queue with no input; user confirms audible end-of-track
    auto-advance (check d).
  - Asked user to tap pause then play on the notification → user confirms icon
    state toggles correctly.
  - After the updatePosition fix (see DEVIATIONS), user watched the
    notification progress bar for ~60s → "it's advancing slowly and smoothly."

NOT VERIFIED — implemented but not exercised, and why
  - skipToPrevious B5 behaviour (>3s restarts current, <3s goes to previous):
    the user's free-form interaction may have hit skip-back at least once, but
    the agent did not deliberately drive and observe this branch.
  - Seek / seekForward / seekBackward (in systemActions): not exercised; the
    compact notification only shows prev/play/next and no in-app seek UI exists
    yet (player screen is unreachable in Phase 1).
  - Queue operations (addQueueItem / insertQueueItem / removeQueueItem /
    updateQueue): no UI to drive them in Phase 1.
  - Shuffle and repeat modes: no UI to drive them in Phase 1.
  - A9 error auto-advance (errorStream → seekToNext): all 10 tracks were
    playable, so the error path never fired.
  - Play-count reporting (PlayerProvider._checkPlayEvent at 90% position):
    position now advances so the threshold is reachable, but the recorded
    count was not cross-checked against the OwnTone server.
  - §7B real-hardware checks (Bluetooth/AVRCP, headphone unplug → pause,
    playback surviving Doze): real hardware only, explicitly deferred by the
    spec.

DEVIATIONS — anything not done as the phase specified
  - Notification button taps (check c, pause check) were performed by the user
    on the agent's explicit request, not by the agent: `uiautomator dump`
    could not capture the notification shade (the notification's animating
    progress bar prevented the idle state, and the shade window never appeared
    in dumps), so the agent had no coordinates to tap. Each user tap was
    requested for one specific button and the result was confirmed in logcat.
  - Two functional defects found during verification were fixed in
    audio_handler.dart (beyond the original fix list):
    1. playCollection loaded sources but never called play(), so audio stayed
       at processingState=ready without starting. Added _audioPlayer.play()
       after setAudioSources. Verified: user hears audio after the fix.
    2. The playbackEventStream handler emitted the raw platform
       `event.updatePosition` (a sparse cached sample, frozen at the
       track-start value) while copyWith stamped a fresh updateTime, resetting
       the notification's playhead projection baseline on every sparse event
       and making the playhead snap backwards. Now emits
       `_audioPlayer.position` (just_audio's extrapolated live position),
       which is the value the audio_service/Android media-session projection
       expects. Verified: user reports the playhead "advancing slowly and
       smoothly" after the fix.
  - PlayerProvider is kept wired to the new handler's streams (it is deleted
    in Phase 2 with its consumers); its kDebugMode logs were used as the
    observation channel for mediaItem/playbackState.

BUILD
  flutter analyze: 0 errors, 0 warnings, 1 info
    (prefer_conditional_assignment, sync_provider.dart:653 — pre-existing
    file, not modified in this phase)
  flutter build apk --debug: SUCCESS

UNKNOWN — behaviour you could not explain
  - During playback, platform PlaybackEvents arrive at irregular ~26–44s
    intervals (visible as repeated mediaItem/playbackState log lines for the
    same track). Read in just_audio 0.10.6 source: the Android
    bufferWatcher (AudioPlayer.java:115–142) re-broadcasts a playback event
    whenever the ExoPlayer buffered position changes, and the Dart layer
    re-emits sequenceState on every playback event
    (just_audio.dart:324–327) — so the cadence tracks how fast the content://
    source buffers over the network. Not instrumented on device; stated from
    source reading only.
  - The first PlaybackEvent after a track starts reports
    updatePosition ≈ 10–20ms rather than 0. Presumed to be ExoPlayer's
    initial render offset; not investigated further because the extrapolation
    fix makes it irrelevant to the visible position.
