PHASE 2: BLOCKED

GO/NO-GO CHECK
  What it was: A 100+ track queue starts without visible stall — the defining
  check for the fast-path URI-resolution work (Defect A). Concretely: tap
  "Play All" on the synced library and observe playback start quickly because
  the fast path resolves content URIs directly instead of falling back to the
  slow per-file directory walk.
  Did you run it:        NO
  What you observed: Tapped "Play All" on the 233-track library with cold (empty)
  content URIs. All 233 tracks resolved (0 "Failed to resolve"); the fast path
  succeeded for the large majority and a fluctuating subset (21–231 across runs)
  fell back to the walk. But the media session stayed state=NONE — playback
  never started. openFileDescriptor reads on the SAF document URIs were denied
  intermittently (SecurityException: "requires that you obtain access using
  ACTION_OPEN_DOCUMENT or related APIs"), while tree-listing and document
  writes worked normally (a Brass sync downloaded 33 tracks with 0 errors).
  Re-granting the SAF folder permission (multiple times) and `pm clear` +
  re-grant did not restore read access. The 100+ queue therefore could not be
  observed starting.

OBSERVED — things you did and saw, on the emulator, by hand
  - (Original working session, before the debug APK reinstall) Opened
    PlayerScreen → back → reopened → the seek bar rendered and the log had 0
    "Bad state: Stream has already been listened to" exceptions. (Defect B
    fix verified.)
  - (Original working session) Mini player and player screen rendered from the
    controller streams; seek-bar max = duration and position advanced smoothly
    in real time (4:01 → 4:17 over ~16s); auto-advance within a collection
    worked (Skunk → Good People in playlist order).
  - (Original working session) Tapped "Play track" on a list row → a queue in
    playlist order started (no single-item queue).
  - (This session) Triggered a Brass sync (33 tracks) → log showed "Found 231
    existing files in tracks directory" and 33 tracks downloaded with 0
    SecurityExceptions → the SAF grant permits tree-listing and document writes.
  - (This session) Tapped "Play All" (233 tracks, cold URIs) → all 233 resolved
    (0 "Failed to resolve"); "Fast content URI build failed" appeared for a
    fluctuating subset (21 in the final clean run) which fell back to the walk;
    media session stayed state=NONE (playback did not start).
  - (This session) Re-granted the SAF folder permission and also did `pm clear`
    + a single clean re-grant → the fast path's openFileDescriptor reads were
    still denied intermittently.

NOT VERIFIED — implemented but not exercised, and why
  - Defect A fast path end-to-end (a 100+ queue actually starts playing
    without stall): implemented (openFileDescriptor validation) and observed to
    build correct URIs and succeed for the majority of tracks, but end-to-end
    playback could not be observed because the emulator's SAF document-read
    access (openFileDescriptor) is intermittently denied on this emulator after
    the debug APK reinstall. A full AVD reset is the next step to attempt
    verification.
  - Defect B on the current (post-reinstall) build: verified in the original
    working session but not re-verified after the reinstall (the environment
    broke before a re-run).

DEVIATIONS — anything not done as the phase specified
  - The designed fast-path fix validated with DocumentFile.exists()/isFile()
    (query-based). I kept the by-hand single-segment document URI but replaced
    the validation with openFileDescriptor (the operation playback uses).
    Rationale: the original defect was that the query-based validation failed;
    openFileDescriptor is what playback actually opens, and it was working in
    the original session.
  - Seeded the local DB with 233 track records (metadata for files already on
    disk) and reset their content_uri to empty, to force a cold re-resolution
    without re-downloading the ~3.4G library (the emulator only had ~2G free).
    Test-harness action, not a product change.
  - Deleted 324 synced track files to free ~2.2G of emulator storage (required
    for the APK install); 33 (Brass) were re-downloaded during sync testing.

BUILD
  flutter analyze: 0 errors, 0 warnings (1 pre-existing info at
    lib/presentation/providers/sync_provider.dart:653)
  flutter build apk --debug: OK

UNKNOWN — behaviour you could not explain
  - Why the emulator's SAF document-read access (openFileDescriptor) is
    intermittently denied (21–231 tracks across runs) after the debug APK
    reinstall, while tree-listing and writes work, and re-grant + `pm clear`
    does not restore it. Cause unknown.
  - Why the fast-path failure count varied between runs (231 → 82 → 21) with no
    code or grant change in between. Suggests a race/flaky state; not pinned
    down.
