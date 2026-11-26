# Issue #11: host-executable diagnosis pass (third-party session stack on the harness)

Session: 2026-11-26, follow-on to `issue-14-btkey-probe-report.md` (same day —
the `[BTKEY]` probe build is what this pass pressed keys against). Task from
#11: run the harness-executable part of the diagnosis — re-run the "car" under
the reporter's morning conditions (owntone_remote notification present,
AntennaPod present, all permanently-active sessions in the stack), read
`Media button session is …` ownership **before every press**, and execute the
force-stop-remote discriminator where reachable.

The 8-scenario matrix from 2026-11-24 (`bt-avrcp-skip-issue-11-report.md`) was
not re-derived. Root cause stays UNKNOWN per verification-protocol §2 — nothing
here names the failing leg of the user's real failure.

```
PHASE #11 host pass: BLOCKED (on the real-car capture — the issue's defining
check cannot be executed from the harness; this report covers the
host-executable part, which was fully run)

GO/NO-GO CHECK
  What it was: a real broken-state capture in the user's car (dumpsys
    before/after each head-unit press while keys are actually lost).
  Did you run it:        NO — impossible from the bench: the harness has
    never induced the failure (8/8 then, and the 3 new third-party-stack
    orders below all pass too). Status is BLOCKED per §3.
  What the host pass did run: every scenario below, each press bracketed by
    owner + state reads and witnessed by [BTKEY] (never rsp_code alone).

OBSERVED — things I did and saw, on the Pixel 6 + ESP32 CarHarness, by hand
  Setup: AntennaPod launched (episode played ~5 s via its UI, paused via
  dispatch — GAIN holder, active=true); owntone_remote launched (its
  notification present, session active=true mirroring the server); Samsung
  band session permanently active; our debug build with the #14 probe.

  - S0 (full stack present, we play): ESP32 next/prev/pause/play → 4/4
    [BTKEY] lines, rsp_code 9 every send, our active item id advanced
    30→31 and PLAYING/PAUSED followed the presses, owner stayed ours
    (media-session/31) before AND after every press. PASS.
  - S1 (remote restart wake): force-stop + relaunch owntone_remote while
    we were playing; its notification appeared (wake). Owner did NOT move
    (stayed ours). Read from dumpsys.
  - T1 (server-driven "remote playing"): started the server player
    (PUT /api/player/play) so the remote's mirror state went
    PLAYING(3) at the server's position. Owner STILL stayed ours;
    ESP32 next → [BTKEY] +1 (idx 32) — we received it, server did not
    (still item 215539). Then paused the server (restore).
    FINDING F1: the focus-less permanently-active session cannot take the
    button session even while mirroring PLAYING — audio_service guards
    enterPlayingState's setActive(true) with !isActive() and the remote's
    session is always active=true, so AOSP never gets the setActive that
    mows the button-session pin. Consistent with #11's note that the
    mirror session "cannot easily be made the button session on demand";
    now mechanically explained. No harness-reachable order (wake,
    server-play, our-play-last) moves the pin off the current player.
  - T3 (SIMULATED routing-leg failure — clearly labelled as simulation, NOT
    the user's trigger): AntennaPod's Play (UI button, fresh dump) → owner
    moved to antennapod session/35 + GAIN (our app auto-paused on focus
    loss — which already differs from the user's "keeps playing" state);
    dispatch pause → AntennaPod paused, owner STAYED on it (the stale-pin
    state the clean-state dump in the issue shows). ESP32 next → rsp_code
    9 (press+release), [BTKEY] delta 0, our session state byte-identical,
    AntennaPod's session block updated (its state changed; our app
    received nothing). FINDING F2 — the witness template for the
    "session routing" leg: ACCEPT×2 + zero BTKEY + owner line naming
    another package + our frozen state line. A real broken-state capture
    that matches this template → session routing; BTKEY +1 with no audble
    effect → our callback; no ACCEPT → BT stack target side.
  - T4 (reclaim differential): in-app PLAY from paused (mini-player,
    fresh dump → tap) → owner moved back to ours, ESP32 next → [BTKEY] +1
    delivered. FINDING F3: in-app PLAY-from-paused ALWAYS reclaims the
    button session on the harness (focus-GAIN path). The reporter states
    in-app PLAY does not restore control in the car without the BT
    power-cycle. Taken together this is evidence AGAINST the user's state
    being a harness-reachable owner pin, and points toward suspects 3/4
    (the cached current-session in com.google.android.bluetooth) — a
    differential result, not a root cause.
  - T5 (relaunch-alone differential): force-stop + relaunch (ESP32 stayed
    connected, no BT power-cycle) → A8 restored queue, new pid, new
    session/36; every ESP32 press → [BTKEY] delta 1 on the new pid.
    FINDING F4: relaunch alone always restores delivery on the harness;
    the reporter says it never does in the car — same direction as F3,
    BT-stack-side state our process cannot reset.
  - T4/T5 side observation → FINDING F5 (ADJACENT DEFECT, not #11,
    not chased — reporting per AGENTS.md): pressing next while on the
    LAST track (item 33/34, repeat off) → A9 endOfQueue stop leaves
    playing=true + processingState=completed stale: session projection
    stuck PLAYING while AudioTrack is stopped (dumpsys audio: state:stopped,
    A2DP Suspended on the ESP32); mini player shows "Pause"; persists across
    force-stop + relaunch (restored completed state); head-unit PLAY then
    PAUSES (toggle from stale playing=true) and next is inert. Reproduced
    twice. Only at the queue tail; deserves its own issue.

NOT VERIFIED — implemented but not exercised, and why
  - The five in-car differentials (in-app PLAY from paused while broken;
    notification buttons while broken; head unit vs AntennaPod at the same
    moment; relaunch alone while broken; 3-way press comparison) — all
    require the failure to be live; blocked on the real-car capture.
  - force-stop-owntone_remote as a discriminator: not reachable — the
    remote never became the button session in any harness-reachable order
    (F1), so there was no hijacked state to test the remedy on.

DEVIATIONS — anything not done as the issue specified
  - T3's owner-pin was produced via AntennaPod (the only session on the rig
    that CAN take the pin while its audio is absent). It is a simulation of
    the routing-leg signature (F2 template), produced on purpose, and is
    explicitly NOT evidence about the user's trigger (our app was paused,
    unlike the user's keeps-playing state).
  - Server player was transiently started/stopped (PUT play, then pause) to
    drive the remote's mirror state — see SIDE EFFECTS.
  - "Was the media notification visible": our media notification sits in the
    shade's SILENT bucket (importance LOW — invariant 34's class) even while
    playing; for the reporter's capture ask them to pull the shade down
    fully, and treat notification-visibility as "present in dumpsys
    notification", not "visible at a glance".
  - Head unit = the ESP32 CarHarness (model N/A); Android Auto N/A (plain
    A2DP/AVRCP by construction). App alive-time at tests: minutes.

UNKNOWN — behaviour you could not explain
  - F5's stale playing=true/completed after the A9 end-of-queue stop (why
    the session projection keeps PLAYING after stop() and why A8 restore
    reseeds completed+playing). Not investigated — out of scope here.
  - Why the owner pin survived AntennaPod pausing in T3 (AOSP releases it
    after a timeout in some cases) — not explored; irrelevant to the
    template (the pin demonstrably held long enough across a press).
```

## Server / device side effects (disclosed; verification-protocol honesty)

- Server `192.168.1.13`: baseline recorded before any change
  (`pause, item_id 215539, shuffle on, repeat off, volume 46, progress 21290 ms`).
  PUT play (~70 s while T1 ran) then PUT pause. Final verified against the
  API: `pause`, **item_id 215539 (unchanged)**, shuffle/repeat/volume
  unchanged; `item_progress_ms` advanced 21290 → 94799 (progress is not
  rewindable via the API — disclosed drift). Queue contents untouched.
- Device: our debug build replaced (35695df → develop+probe, same debug
  key), left paused on a healthy queue; one pending **skip** row is queued in
  the app DB from the F5 queue-tail press (uploads on the user's next sync —
  app's designed behaviour). AntennaPod and owntone_remote force-stopped
  (their state at session start). ESP32 left powered, A2DP connected.
  Shared AVD OwnTone_U2_API_36: debug build upgraded 0.3.3→0.3.4+23 and a
  debug-key-signed release-profile APK was installed on it during the #14
  checks; emulator then shut down.

## Evidence (transcribed per invariant 12 — /tmp is volatile)

- `/tmp/owntone_verify/p11.log` — all [BTKEY] lines (S0 4, T1 1, T4 1, T5 2).
- `/tmp/owntone_verify/esp_*.log` — per-press ESP32 logs (rsp_code 9 on
  every press+release; A2DP Started/Suspended transitions).
- `/tmp/owntone_verify/ms_stack1.txt` — session-stack snapshot (three
  permanently-active third-party sessions + ours, GAIN holder).
- `/tmp/owntone_verify/srv/*_baseline.json` + final API read above.

## What this pass changes for #11

- The developable unit "run the harness pass under the reporter's
  conditions" is DONE; the issue remains **blocked on the real-car capture**,
  and root cause stays UNKNOWN.
- The capture becomes interpretable: whoever posts the broken-state bundle
  compares it against F2's template (BTKEY vs owner line vs ACCEPT codes)
  and F3/F4 (in-app-PLAY and relaunch behaviour) to name the leg.
- Suggested follow-ups (not done here, per scope): (a) file F5 as its own
  issue; (b) post this report's findings as a comment on #11 — offer
  recorded, awaiting the user's go.
