# Handoff prompt for implementing sessions

Run this once per phase, substituting the phase number. Phases are defined in
§3 of `.agent/player-refactor-plan.md`. Start with Phase 0.

---

```
You are implementing a refactor of this Flutter app, defined in two documents in
this repo. Read ALL THREE IN FULL before touching any code — they are
authoritative and supersede anything in .agent/player-spec.md or
.agent/play-music-plan.md (both obsolete; ignore them):

  .agent/player-ux-spec.md        — what we are building and why, plus the
                                    user stories and acceptance criteria
  .agent/player-refactor-plan.md  — the defect inventory, target architecture,
                                    and the phased implementation path
  .agent/verification-protocol.md — what counts as evidence, and the report
                                    format you must use. Short. Binding.

Your job this session is PHASE <N> ONLY, as defined in §3 of the refactor plan.
Do not begin any later phase. Do not do "while I'm here" cleanups that belong to
another phase.

Before writing code:
1. Read all three documents completely.
2. Read §1 of the refactor plan (the defect inventory) carefully — it cites
   file:line evidence for why the current code is broken. Verify those claims
   against the actual code rather than assuming they are still accurate.
3. Read the files this phase touches, per the disposition table in §4.
4. Tell me your understanding of this phase's scope and what you intend to
   change, and wait for my confirmation before editing.

Binding constraints (§5 of the refactor plan):
- Prefer deleting old code over adapting it. The existing player code is the
  source of the bugs; carrying pieces of it forward carries the bugs forward.
- Do not modify the sync download/upload pipeline. Only the additive sync-side
  changes named in §4 are permitted.
- Do not add dependencies beyond those named in Phase 0.
- After the phase: `flutter analyze` must report 0 errors and 0 warnings, and
  `flutter build apk --debug` must succeed. Show me the actual output.
- If something in the spec turns out to be wrong, impossible, or contradicted by
  the code, STOP. Write it to .agent/blockers.md and tell me. Do not improvise a
  different architecture.

Device verification:
- The OwnTone server is at `192.168.1.13`, reachable directly from the emulator
  over the LAN. Use that address as-is; do not assume it runs on the host.
- An Android emulator is available as `emulator-5554` (Android 16, API 36).
  Run the app on it with `flutter run -d emulator-5554` and verify this phase's
  behaviour yourself before reporting done. Do not report a phase complete on a
  clean `flutter analyze` alone.
- §7A of the UX spec lists what the emulator can verify and §7B lists the three
  checks that require real hardware. If this phase's verification falls in §7B,
  say so explicitly and hand me the steps rather than claiming it passed.
- Verification is MANUAL: drive the app's own UI on the emulator. Do not reach
  for adb or shell tooling to inspect app state. `pending_events` lives in
  app-private storage and the emulator image ships no `sqlite3` binary, so it
  cannot be read from the shell — do not waste time trying.
- To check that play and skip counts are correct, use the OwnTone web UI at
  `192.168.1.13` as the source of truth: note a track's play and skip counts
  before, then re-check them after a sync.
- If a step cannot be checked because the app has no view for it yet, say so
  rather than inventing a workaround. Some of those views are story D3 and are
  meant to be built.

When you believe the phase is done, BEFORE writing anything:
1. Re-read .agent/verification-protocol.md in full. Not from memory — open it.
2. Identify this phase's go/no-go check and run it, if you have not already.
   If you have not run it, the phase is BLOCKED, not complete.
3. Write your report using the exact template in §6 of that protocol. Every
   field is mandatory. Do not summarise it into prose.

Claims about behaviour must come from actions you performed and results you
observed on the emulator. A clean analyze and a successful build are not
evidence that anything works.
```

---

## Per-phase notes

**Phase 0** — COMPLETE. Do the `just_audio` / `audio_service` major upgrade in
its own commit with nothing else in it. Everything downstream assumes this
ground is clear.

**Phase 0.5** — COMPLETE. Removed the sync worker's event-upload gate. Note that
its behavioural verification was not possible at the time: nothing writes
`pending_events` until Phase 3, so there were no events to upload. That check is
folded into Phase 3 below.

**Phase 1** — Contains a go/no-go. Validate that `content://` URIs actually play
through `just_audio`'s native path *before* building anything on top of the
handler. It is the top risk in §6 of the refactor plan, and discovering it at
Phase 5 would be expensive.

**Phase 3** — The whole point of the feature is that the numbers reaching OwnTone
are right, so verify against the server, not the app. Play a track to completion,
skip another, run a sync, then check both tracks' play and skip counts in the
OwnTone web UI. This is also the first real test of the Phase 0.5 gate removal —
if counts do not move, the upload path is still broken.

**Phase 7** — Sync against the real server at `192.168.1.13`, reachable directly
from the emulator over the LAN.
