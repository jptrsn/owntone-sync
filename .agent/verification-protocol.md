# Verification protocol

**Read this at the start of the phase. Read it AGAIN before writing your report.**

This exists because three phases in a row were reported complete when the
defining check had not been run, with supporting detail that turned out to be
invented. The rules below are not style preferences.

---

## 1. What counts as evidence

| Claim | Valid evidence |
|---|---|
| "The feature works" | You performed the user action and observed the result |
| "Audio plays" | You heard it, or saw the position advance in a running app |
| "The notification works" | You saw it, and pressed its buttons |
| "No crash" | The screen you expected was rendered and you interacted with it |

**Not evidence of behaviour:**

- `flutter analyze` passing — proves it compiles, nothing more
- `flutter build apk` succeeding — same
- The app launching without an exception — a blank screen also launches cleanly
- Logcat lines you did not cause and do not fully understand
- Absence of an error in logs, when the code path may never have executed

Before citing a log line, ask: *could this appear even if the feature were
completely broken?* If yes, it is not evidence.

## 2. Never invent a mechanism

If something behaves unexpectedly and you do not know why, write **"unknown"**.

Do not construct a plausible-sounding explanation. A wrong explanation is worse
than no explanation, because it stops anyone from looking further. If you assert
a cause, you must have verified it — named the file and line, or seen it happen.

## 3. If the go/no-go was not run, you are BLOCKED

Every phase has one check that is the reason the phase exists. If you did not
execute it, the phase is **BLOCKED**, not complete — regardless of how much code
you wrote or how cleanly it compiles.

Do not defer a check to "manual verification" and report complete. Do not defer
a check to "real hardware" unless it is one of the three in §7B of the UX spec.
Everything else is verifiable on `emulator-5554`.

## 4. Verify the harness before trusting the result

If you build a test vehicle (a debug button, a temporary screen), confirm it
exercises the real path before trusting what it tells you. A test that bypasses
the code under test proves nothing.

Ask: *if the feature were entirely broken, would my test still pass?*

## 5. Scope

Implement what the phase says. If you deviate — defer a requirement, add an
unrequested change, or solve it differently — that is not automatically wrong,
but it MUST appear under DEVIATIONS in your report. Silent deviation is the
problem, not deviation.

Do not defer work to a phase that does not exist. Check the plan first.

---

## 6. Required report format

Copy this structure. Do not summarise it away. Every field is mandatory; write
"none" where it applies.

```
PHASE <N>: COMPLETE | BLOCKED

GO/NO-GO CHECK
  What it was:
  Did you run it:        YES | NO
  What you observed:
  (If NO, status above must be BLOCKED.)

OBSERVED — things you did and saw, on the emulator, by hand
  - <action you took> → <what you saw happen>

NOT VERIFIED — implemented but not exercised, and why
  -

DEVIATIONS — anything not done as the phase specified
  -

BUILD
  flutter analyze:
  flutter build apk --debug:
  (New files with warnings cannot be called "pre-existing".)

UNKNOWN — behaviour you could not explain
  -
```

### Rules for filling it in

- **OBSERVED** entries must name an action *you took* and a result *you saw*.
  "App launches without crashes" is not an OBSERVED entry unless you say which
  screen rendered and what you tapped on it.
- Anything you believe works but did not exercise goes in **NOT VERIFIED**. That
  section being long is fine and honest. It being empty when you only ran a
  build is not.
- **UNKNOWN** being non-empty is a good sign, not a failure. It means you noticed
  something and did not paper over it.
