# AGENTS.md

Instructions for AI agents working in this repository.

**This file is a router, not a manual.** It carries only what you need *before
you know what you need*. Everything else lives in `.agent/` and should be read
when the task makes it relevant — not loaded up front.

## The project

A Flutter + Android app that syncs music from a self-hosted
[OwnTone](https://owntone.github.io/owntone-server/) server to an Android device
and plays it offline, sending play counts, skip counts and ratings back to the
server. Kotlin handles background sync, Storage Access Framework file I/O and
WorkManager scheduling; playback runs on `just_audio` behind `audio_service`.

Shipped at v0.2.0. The eight-phase player refactor is complete.

## Read these, in this order

| File | When | Why |
|---|---|---|
| `.agent/invariants.md` | **Always, before writing code** | 36 facts established the hard way, each with what breaks if you undo it. It has an index — use it. |
| `.agent/verification-protocol.md` | **Always** | What counts as evidence, and the report format. Short. |
| `.agent/blockers.md` | **Always** | Open defects. What you are about to fix may already be diagnosed here. |
| `.agent/player-ux-spec.md` | Changing behaviour | What the app is meant to do: user stories, acceptance criteria. |
| `.agent/player-refactor-plan.md` §2 | Touching playback | The architecture. **§1 and §3 are historical** — they describe code as it was before the refactor. |
| `.agent/backlog.md` | Asked to | Unscheduled ideas. Not a to-do list. |
| `.agent/reports/` | Rarely | Historical evidence of what was verified. **Not guidance** — anything still binding was promoted into `invariants.md`. |

## Never commit or push without being asked

**Stop when the work is done and say so. Do not run `git commit` or `git push`
unless the user has explicitly asked you to in that message.**

This applies to every agent working here, including the session that wrote this
file. "Do the work", "fix it", "make the change" and "do everything" are
instructions to edit files — not to commit them, and certainly not to push.
Leave the changes in the working tree and report what you changed; the user
decides when and how they land.

Why it is a hard rule rather than a preference:

- A push is **outward-facing and public**. This repository is public and
  publishes releases; an unwanted commit is visible immediately and awkward to
  retract.
- It removes the user's review step. A diff in the working tree can be read,
  amended or discarded in seconds; a pushed commit cannot.
- Commit granularity and message wording are the user's call. Bundling unrelated
  work into one commit, or splitting related work across several, is a decision
  — not a detail.

When you believe something is ready, say what you would commit and offer. If the
user says "commit and push", do both. If they say "commit", commit and stop.

## How to work here

**Confirm scope before editing.** State what you understand the task to be and
what you intend to change, then wait. Most waste in this repo has come from
confident work on a misread task.

**Stay in scope.** Raise adjacent problems in your report rather than fixing
them. If you deviate from what was asked, say so explicitly — deviation is often
right, silent deviation never is.

**Verify claims against the code.** Instructions you are given, including from
this file, may be stale. Check before building on them.

**When something looks wrong in `invariants.md`, stop and say so.** Do not
silently change it. Each entry has a `RESOLVED CONCERN` field precisely because
sessions keep re-deriving settled questions — check there before raising one.

**Ask before adding a dependency.** The short dependency list is deliberate.

## Done means

- `flutter analyze` → 0 errors, 0 warnings
- `flutter test` → passes (Kotlin: `./gradlew :app:testDebugUnitTest`, needs JDK 17)
- `flutter build apk --debug` → succeeds
- The behaviour you changed was **observed working on a device**
- A report in `.agent/reports/` using the template in `verification-protocol.md` §6
- `invariants.md` updated with anything a future session must not undo

A clean analyze and a green build are not evidence that anything works. If you
could not run the check that is the point of the task, the task is **BLOCKED**,
not complete — say so plainly.

## Tests

There is a suite, derived from `invariants.md` rather than from the
implementation. If you add a test, cite the invariant or requirement it guards.
A test that restates current behaviour is worse than none: it makes fixing a bug
harder while providing false assurance.

**A failing test is a finding.** Report it; do not adjust the test to match the
code without saying so.

## Devices and the server

**The OwnTone server at `192.168.1.13` holds the user's real, curated music
library.** Read from it freely. Do not modify it — no deleting playlists, no
editing tracks. Induce failure cases from the app side instead. If a check
requires changing a rating or a count, record the original first, restore it
afterwards, and confirm the restore against the API.

An emulator (`emulator-5554`) is usually available; a physical phone sometimes
is. Check `flutter devices`.

**Verification is manual** — drive the app's own UI.

## Three traps that have each cost a session

These are here, rather than in `invariants.md`, because you need them *before*
you are in trouble.

**For a rendering bug, attach `flutter run` and read the console.** Framework
errors log under the tag `E/flutter`, and `uiautomator dump` returns an empty
window while the Now Playing sheet is open — so the two obvious instruments both
fail silently on the same screen. Screencap pixel-counting can tell you *that*
nothing rendered, never *why*.

**If a check reports a feature missing, suspect your harness first.** A negative
result from a test you wrote is a claim about two things: the feature and the
test. Confirm the harness can see a known-present thing before concluding
absence.

**Running more than one agent at once? Give each its own git worktree.** Two
sessions sharing a working copy will clobber each other — a branch switch or a
stash in one destroys uncommitted work in the other.

```
git worktree add ../owntone-<task> -b <task>
```

## Commit messages

When you have been asked to commit (see the rule at the top — do not commit
otherwise), explain *why*, not what — the diff shows what. Where a change is non-obvious or
looks like something a future reader would "tidy up," say what breaks if they
do. Several commits here exist mainly to carry that warning.
