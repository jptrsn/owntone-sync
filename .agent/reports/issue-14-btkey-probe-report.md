# Issue #14: `[BTKEY]` click() observability probe — device verification report

Session: 2026-11-26. Task: land the `click()` observability probe split out of
#11, and verify it per the #14 acceptance criteria on the Pixel 6 harness device
(25071FDF600953, Android 16/17) with the ESP32 CarHarness, plus a release-silence
check on `OwnTone_U2_API_36`.

Probe: `OwnToneAudioHandler.click([MediaButton button = MediaButton.media])`
overrides, `kDebugMode`-gated `debugPrint('[BTKEY] click(<name>) playing=…
proc=… idx=…')`, then `return super.click(button)` (no behaviour change).
Adopted from the 2026-11-25 working-tree draft; only the doc comment changed
(cites #14; witness for #11).

```
PHASE 14: COMPLETE

GO/NO-GO CHECK
  What it was: real-AVRCP observation — each of the ESP32 CarHarness
    play/pause/next/prev passthrough keys produces a [BTKEY] line
    (logcat -s flutter). rsp_code ACCEPT alone is NOT accepted as delivery.
  Did you run it:        YES
  What you observed: 4/4 keys witnessed. `next` (0x4B) → one
    [BTKEY] click(next)  + AVRCP metadata changed on the ESP32
    ("Heart on my Sleeve"); `prev` (0x4C) → click(previous) + metadata
    change; `play` (0x44) → click(media) + A2DP "audio state: Started",
    ringbuffer PROCESSING, audio packets flowing; `pause` (0x46) →
    click(media) + "Suspended". Every send logged rsp_code 9 (ACCEPT)
    for press+release — recorded, not used as proof.

OBSERVED — things you did and saw, on the device, by hand
  Pixel 6 (debug build with probe; media button session verified as
  dev.educoder.owntone_sync/media-session/31 before pressing anything):
  - `cmd media_session dispatch play|pause|next|previous` → exactly one
    [BTKEY] each: click(media) playing=false, click(media) playing=true,
    click(next), click(previous); active item id moved with next/previous.
    (This path bypasses the Bluetooth stack — validates callback wiring
    only, per #11 note 4.)
  - ESP32 CarHarness `next|prev|play|pause` over real AVRCP → GO/NO-GO
    above. Playback state (PLAYING/PAUSED) and A2DP start/suspend observed
    on the ESP32 log matching the presses; final state PAUSED, item 28.
  - Negative control: tapped the mini player's Next (uiautomator dump →
    bounds → tap) → active item id 28→29, screen updated, and the BTKEY
    count did NOT change (8→8). Tapped Play then the same control again
    → played ~2.7 s (dumpsys position 2673) then paused, BTKEY count
    still unchanged. In-app transport bypasses click() as intended.
  - Notification control (corrects the issue text — see FINDING below):
    with the shade focused (dumpsys window → NotificationShade) and the
    media notification's bounds read from a fresh dump, tapped its
    "Next track" → active item id 29→30 (delivered) and ZERO [BTKEY]
    lines. Earlier pair (Next then Previous on item 29, pos ≥3 s) had
    moved 29→30→29 with pos 0 — also zero BTKEY. The marker does NOT
    fire for notification transport taps.
  OwnTone_U2_API_36 emulator (release-profile APK over the existing
  configured+synced Brass 33 state; only emulator attached, identity
  checked via pgrep):
  - debug build: mini-player Play (dump → bounds → tap) → PLAYING,
    media button session = ours; dispatch pause/play/next/previous/pause
    → 5/5 [BTKEY] lines, item id + playing state moved with them.
  - release-profile build (installed -r): launch rendered the Library
    (dump showed tabs + Brass row + mini player), Play → PLAYING, button
    session ours; `dispatch next` → active item id 2→3 (event delivered
    to the handler) with ZERO [BTKEY] lines; the flutter logcat tag was
    demonstrably alive on that process (captured its Impeller engine
    line, same pid) — the capture is not simply blind.
  - Static pairing: the string BTKEY appears 2× in the debug APK's
    assets/flutter_assets/kernel_blob.bin and 0× in the release APK's
    lib/arm64-v8a/libapp.so — the kDebugMode branch is const-folded out;
    the line cannot exist in release.

FINDING (correction to the #14 text's "distinguishing control"):
  Notification transport taps do NOT produce a [BTKEY] line — contrary to
  the issue's premise that audio_service routes them through the
  key-event funnel. dumpsys notification shows the notification is
  MediaStyle with the `android.media.session` Token extra; SystemUI binds
  those buttons to the session's transport controls directly, so
  onSkipToNext()/onPlay() run without ever passing through
  onMediaButtonEvent → onClick → click(). (The plugin's
  buildMediaButtonPendingIntent key-event broadcasts exist and are set as
  the Actions, but MediaStyle's token binding takes precedence in
  SystemUI.) Consequence for #11: [BTKEY] means "arrived as a genuine
  external media-key event" (head unit / headset / dispatch) — it
  separates key arrivals from BOTH in-app and notification taps. It
  cannot distinguish "our session received a key" from "another session
  received it" — the pre/post-press `dumpsys media_session`
  "Media button session is …" line remains the owner witness.

NOT VERIFIED — implemented but not exercised, and why
  - Wired-headset button path: same click() funnel, no wired headset on
    the rig. Not required by the acceptance criteria.
  - Mpow H20 physical peer: not used this session (ESP32 covered AVRCP).

DEVIATIONS — anything not done as the phase specified
  - The release-silence check used a release-profile APK signed with the
    DEBUG keystore (android/key.properties temporarily pointed at
    ~/.android/debug.keystore), so it could install -r over the debug build
    without wiping the AVD's synced state. Uninstalling instead would have
    wiped the AVD app data (server config + DB). Signing does not affect
    kDebugMode and the `libapp.so` string count (0× BTKEY) is the witness
    for release silence, so this deviation does not touch that conclusion.
    CORRECTED 2026-11-27 (PR #20 review): this bullet originally vouched for
    the restore with "`git status` clean for it". That is not a witness —
    `android/key.properties` is gitignored (`android/.gitignore:12`), so
    `git status` cannot see the file in either the modified or the restored
    state, and `release.sh`'s only relevant preflight (`git status
    --porcelain`, `release.sh:60`) checks the tracked tree and cannot see it
    either. The restore was NOT verified by an inspectable read during the
    session, and "the shipped release remains key.properties-signed" was an
    inference rather than an observation.
    CHECK BEFORE THE NEXT `./release.sh`: read the file back
    (`cat android/key.properties`) and confirm `storeFile` names the release
    keystore, not `~/.android/debug.keystore` — `android/app/build.gradle.kts:12`
    reads that path and `:53` applies it to the release `signingConfig`
    unconditionally, so a leftover redirect would publish a debug-key-signed
    release with every existing preflight green. `git check-ignore -v
    android/key.properties` demonstrates why `git status` cannot be the
    witness. Adjacent, raised not fixed: a `release.sh` preflight that greps
    `storeFile` out of `key.properties` would close this permanently.
  - Verification ran on the physical Pixel 6 (25071FDF600953) rather than
    an AVD. This is deliberate and user-blessed: #11/#14 designate the
    Pixel 6 + ESP32 as the harness rig (debug build, AntennaPod,
    CarHarness already provisioned on it by the 2026-11-24 session).
    invariants.md 42's "never touch the physical device" rule predates
    that blessed harness; flagged here rather than edited, per AGENTS.md.
  - AVD side-effect: OwnTone_U2_API_36's owntone_sync debug build
    upgraded 0.3.3 → 0.3.4+23 (install -r, data preserved) and the
    release-profile build is currently installed on it. Server untouched.

BUILD
  flutter analyze: 0 errors, 0 warnings; 1 pre-existing info
    (queue_sheet.dart:160 onReorder deprecation — present on develop,
    untouched by this change).
  flutter test: 159 passed (includes test/static_guards_test.dart, which
    inspects audio_handler.dart — invariant 3/4 guards intact).
  flutter build apk --debug: succeeds. flutter build apk --release:
    succeeds (with the debug-signing note above).

UNKNOWN — behaviour you could not explain
  - None outstanding. (The one mid-session confusion — a "blind" tap pair
    before the dump-before-tap discipline was enforced — decoded
    consistently afterwards: 29→30→29 with pos 0, i.e. both notification
    buttons landed via the token-transport path.)
```

## Evidence files (transcribed; /tmp is volatile per invariant 12)

- `/tmp/owntone_verify/logcat_probe.log` — Pixel BTKEY lines (8 lines: 4
  dispatch + 4 AVRCP).
- `/tmp/owntone_verify/avd_debug.log` — AVD debug 5 BTKEY lines.
- `/tmp/owntone_verify/avd_release.log` — release: zero BTKEY, Impeller
  line proving tag capture alive on the release pid.
- `/tmp/owntone_verify/n.xml, n2.xml, n3.xml` — shade dumps;
  dumpsys notification excerpt (MediaStyle, Token extra, 3 broadcast
  actions, importance LOW → Silent section) is quoted above.

## For #11

The probe is in the debug build on the Pixel 6. #11's broken-state recipe
witness is now `adb logcat -s flutter | grep BTKEY` (never
`-s OwnToneAudioHandler:*`), paired with the pre/post-press
`dumpsys media_session` "Media button session is …" + active-item-id
reads. ACCEPT is still not delivery; only a BTKEY line is.
