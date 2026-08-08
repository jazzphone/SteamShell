# Next steps, and what was learned getting here

Written 2026-08-08, immediately after 2.0.0; Part 1 rewritten the same day once
the queue had been worked. This is a work queue and a set of warnings.

Part 1 is nearly empty and what is left needs hardware. Parts 2 and 3 are not a
queue and do not expire -- do not delete this file with them in it.

The warnings matter more than the queue. Most of them cost real time this pass,
several produced a wrong answer that survived until something contradicted it,
and every one of them will recur for the next person who greps this codebase the
obvious way.

---

## Part 1 — What is left

The 2026-08-08 queue ran. A, B, C, D, E and F are done and are in the history
with their reasoning; what follows is the remainder, and one item that was
proposed and turned out not to be worth doing as described.

### G. `PollController` core extraction — half done, half needs hardware

Banked: `ControllerPrimeHoldTables` and `ControllerApplyStickDeadzone`, both in
`SteamShell-Common.ahk`. Those were the two blocks each tree ran on every tick
and could be moved by inspection.

Not done, and deliberately: the shared `ControllerPollFrame` -- read, edge
detection, hold and chord tracking. The loop is 550 lines in the shell against
435 in the companion, the state is a dozen statics threaded through by
reference, and the differences are real: the shell has the controller test and
the settings editor, the companion has `CompanionDisabled`, a fresh-baseline
path and per-edge diagnostic logging.

**It needs a machine with AutoHotkey and a controller.** Extract with both trees
behaving identically and verify on hardware, THEN touch dispatch -- two commits,
in that order. The gate scores the pair 0.31, so nothing demands it.

### H. Event-driving the window enumeration — still parked on one number

Open **Settings → Advanced → Health Check**, "Coordinated window engine" row. It
reports `last scan N windows in Mms`.

- ~12 windows in ~3 ms → **delete this item**; 0.6% of a tick is not worth a hook.
- ~60 windows in ~45 ms → 9% of every tick confirming nothing changed; worth doing.

If it is worth doing, the narrow version is: hook `EVENT_SYSTEM_FOREGROUND` and
`EVENT_OBJECT_SHOW`/`HIDE` only -- **not** `EVENT_OBJECT_LOCATIONCHANGE`, which
fires per-pixel during drags and would cost more than the polling it replaces --
and keep the 500 ms timer as a safety net. `TaskbarGuardWinEvent` is the working
template, including its reentrancy guard and its "log when the hook was
unavailable" discipline.

There is now one enumeration to hook rather than four:
`SharedWindowInventoryBuild`.

### I. Hardware verification (maintainer)

Everything below was written or changed statically and has not been run.

- **The shell's controller diagnostic tick.** New. Settings → Controller →
  "Log all XInput slots on every change", then read the log for `Diag` lines.
  Before this it was a control that did nothing; the failure mode to watch for
  is the opposite one, a tick that never stops.
- **The Task Switcher, in both products.** The list is one shared function now.
  In the companion, Steam Big Picture must still appear under Xbox FSE -- that
  is the fix the shared filter was built around. In the shell, check that an
  ordinary desktop session's switcher looks exactly as it did, and that a
  minimized exclusive-fullscreen game is still offered.
- **The companion's screen probe and assist.** Both read the shared inventory
  now. The probe should still list MORE windows than the inventory, with an
  `excluded-from-inventory:` reason on each.
- **Sleep/resume.** The trap: if device hand-over alone recovers input you will
  see neither a `Power: resumed from sleep` nor a `Power: wall-clock gap` line,
  and layers 2 and 3 go untested. Try a longer sleep, and from inside a
  fullscreen game where XInput cannot mask a RawInput failure.
- **`ExportDiagnosticBundle` in both products.** Both callers were rewritten onto
  the shared `ExportDiagnosticArchive`; only statically validated.
- **Controller mouse speed** should feel unchanged after upgrading. If it feels
  roughly double, the ×32 migration factor is wrong for this hardware and 62.5 is
  correct -- a one-line change in both migrations.

### D, revisited: the settings-row check does not catch what it was proposed for

`Assert-SettingsRowsReachConsumers` exists and is mutation-tested. It proves a
row's key is read back and that the value reaches a consumer, and it would catch
a genuinely unwired row.

**It would not have caught `DiagnosticLogging`,** which is the reason it was
proposed. That row passed both steps in the shell: read, and consumed -- by
`PositionGuiCentered`, which logs window centring rather than the XInput slots
the label promises. Telling that apart from `RtssOverlayToggleShortcut`, which is
also consumed only in `SteamShell-Shared.ahk` and is entirely correct, needs the
label's MEANING, and no static check has that.

Recorded because the gap is easy to mistake for coverage. A control that lies is
still found by reading the label and following the flag, and by nothing else.

---

## Part 2 — Traps in this codebase

Each of these produced a wrong answer that survived until something contradicted
it.

### Searching for a version string misses the escaped form

The 2.0.0 bump failed the build on a clean tree. `grep "1\.9\.9"` finds `1.9.9`
but **not** `1\.9\.9\.0` — the regex-escaped form used inside PowerShell
`-match` patterns. Five literals were missed that way.

Search for **both spellings**, or better, do not create the second one: versions
are now derived from each source's own `@Ahk2Exe-SetVersion`, stated once in
`Validate-SteamShell.ps1`'s metadata block.

### `sed -n '/^Func/,/^}/p'` truncates

`SteamShell.ahk` has de-indented blocks (see F), so a `}` can appear at column 0
*inside* a function. Range extraction stops there and silently returns a
fragment.

This nearly produced a reported bug that did not exist — a truncated
`PollController` appeared to set `inPoll := true` and never clear it. Proper
brace matching showed the `finally` that clears it. **Always brace-match.**

### Grepping for a feature by one tree's function name

The Task Switcher was declared missing from XFE because `GetTaskSwitcherWindows`
returns nothing there. It existed as `GetSwitchableWindows`. An entire
architectural justification was then built on top of an absence that was really a
naming difference. The list is `SharedTaskSwitcherWindows` now, and the pair --
along with the activate and close pairs, which stay separate -- is written down
in `CROSS_NAME_DUPLICATES.txt`.

**Search for the behaviour** — the Quick Menu row id, the page constant, the log
string — not the shell's identifier.

### `try {}` swallows; `try/finally` re-throws

All three programs register `OnError(HandleUncaughtError)`, which logs an
uncaught throw with file and line. `try/finally` with no catch **re-throws**, so
those reach the log. Only a **bare `try {}`** swallows, and what it swallows
never reaches `OnError`.

"Silent failure" in this codebase means bare-try specifically, not the ~880
`try` occurrences overall. `Shared:383` and `Shared:5528` document both halves;
the second records a real bug caused by exactly this.

### The gate's score is not any approximation of it

Seven documented scores were wrong because they came from a rough
`difflib`-over-call-names rather than the real fingerprint. `PollController` was
recorded as 0.61 when it is **0.31**; `TrayOpenQuickMenu` as 0.50 when it became
**1.00** after its drift was fixed.

Read scores out of `Replay-Validation.py`'s own `fingerprint`/`similarity`, or
instrument its gate. Do not estimate.

### `Replay-Validation.py` mirrors `Validate-Common.ps1` by hand

Two implementations of one check, and only the PowerShell runs on Windows. It
drifted once already — the PowerShell moved to 0.45, gained a seam exemption and
changed its stale-entry rule, and the replay reported ten failures on a tree
Windows called clean.

**Any edit to the gate belongs in both, in the same commit.** The seam count
expectation (`$sharedSeamExpectedCount`, currently 36) likewise.

### `Test-ControllerProfiles.py` mirrors the decoder, it does not read it

Breaking the big-endian decode in `SteamShell-Shared.ahk` does **not** fail the
simulation. It guards the design against regression in its own Python model; it
does not detect an AutoHotkey-side change. Its docstring says so. Worth knowing
now that it actually runs.

### Windows App Execution Aliases are not interpreters

`Get-Command python3` finds a stub under `WindowsApps` that prints an advert for
the Microsoft Store and exits 9009. Probe by running `--version` and checking the
exit code — never trust presence on `PATH`.

### A comment asserting something about the *other* tree is not evidence

`GameShapeFactsForWindow` was per-tree because a companion-side comment said
*"the shell can assume the game is on `A_Screen*`"*. The shell cannot. That
sentence read as a decision for as long as nobody checked it.

Contrast the Steam-cloaking comment in `GetSwitchableWindows`, which asserts
something **verifiable** — FSE cloaks Steam, the shell does not run under FSE —
and is checkable in a minute. The difference between those two comments is the
difference between a design record and a rationalisation.

### Corrections made to my own analysis this pass

Recorded so they are not re-derived: de-indents were counted at **187**, not
~650, and 155 ambiguous ones have since been indented with a check in both
harnesses to stop them regrowing -- so the number to know now is that the
remaining braceless bodies all END their block and read fine; visible
top-level windows were quoted as 50–150 from a generic-desktop figure and are
**unknown** for this workload (the Health Check reports the real number); XFE
**has** the Task Switcher; `EnablePersistentMouseMode` **is** honoured by the
shell, in `AutoMouseModeActive` rather than in `PollController`;
`QuickMenuEnsureContentFits`'s early return was recommended and then found to be
wrong, because the shell's unconditional move is how the menu follows the
foreground window's monitor.

---

## Part 3 — Repository state

- **History was rewritten** on 2026-08-08 to replace a private author email with
  `4240091+jazzphone@users.noreply.github.com`. Any clone predating that is on a
  dead history — **re-clone, do not pull**.
- `refs/original` and the pre-rewrite bundle have been deleted. **The remote is
  the only backup.**
- `legacy-web-uploads` holds the original 25 web-upload commits, seven of which
  carry the old email. Those have been public on GitHub since January 2026 and
  are also reachable via tags `v1.0`–`v1.2`. Left deliberately: scrubbing them
  means rewriting those tags, and GitHub does not promptly garbage-collect.
- `releases/2.0.0/RELEASE.md` is an **immutable lock with its own checksum
  table**. Do not edit it to improve wording — it described the state accurately
  at release time. Living documentation goes in the README and the wiki.
- Local git identity is set to the noreply address; new commits inherit it.
