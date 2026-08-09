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

### G. `PollController` core extraction — done, and unrun

The head is shared too, in pieces. A block diff of the two loops found the tail
because the tail is contiguous; the head's duplication is INTERLEAVED with gates
that genuinely differ, so a block diff reports "these differ" and says nothing
about four routines inside them. Those four are shared now:
`ControllerDecodeState`, `ControllerButtonEdges`, `ControllerChordFired` (which
had FOUR copies -- two chords, two products) and `ControllerTrackViewButton`.
The XINPUT_GAMEPAD byte layout is in one place; it was in three.


Shared: `ControllerPrimeHoldTables`, `ControllerApplyStickDeadzone`, and now
`ControllerPollFrame` — the whole mapping tail, from "the modifier is held" to
the Guide button. Both loops went from ~330 code lines to ~245, and the heads
that remain are genuinely two programs: the shell gates on its controller test,
the settings editor, two recovery dialogs and an elevated foreground; the
companion on `CompanionDisabled` and its own fresh-baseline path.

**Two behaviours changed in the companion**, both toward the shell's more careful
version, and both need a controller to confirm:

- A button already being timed keeps its clock when View goes down, instead of
  restarting it.
- An adopted trigger has its long-fired flag cleared, so a trigger that fired a
  Long in an earlier hold can fire one again.

Both are asserted in `Assert-ControllerPollFrame` and its Python twin, and all
four mutations were checked. **Neither has been run on hardware.** They are the
kind of change that shows up as "that button sometimes does nothing" rather than
as a crash, so they belong at the top of the controller pass:

- hold each face button briefly and long, on both products;
- hold a trigger long enough to fire its Long, release, and fire it again;
- hold a button, THEN press View, and confirm releasing it still fires Short;
- a Left-click binding must still drag rather than accrue a hold.

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
- **The Task Switcher, in both products.** The list is one shared function now,
  and three smaller differences came out of the merge, each worth one glance:
  the companion's rows show the executable in lower case where they used to show
  it as Windows reports it; the count in the "tasks" row may be up to a second
  stale, while the page itself is always enumerated fresh; and the screen probe
  now drops a window whose title, class or position cannot be read at all, where
  it used to list it as 0x0. That last one is a small loss for a diagnostic whose
  job is completeness, and is the only one of the three that is not an
  improvement.
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

### J. Cross-name consolidation — one left, and it needs hardware

Batches A to D landed. Seventeen candidates became ten, nine QUEUED entries
became one, and four unported defects were fixed on the way:

1. `AssistProcessCpuSample` marked a sample `known` on elapsed time alone, so a
   negative CPU delta reached the companion's game detector as a known sample
   carrying the previous usage figure. **Fixed** — the shared sampler requires a
   non-negative delta, which is what the shell already did.
2. `AssistPruneCpuSamples` dropped a sample the moment its PID left the filtered
   inventory. **Fixed** — the shared prune carries the shell's 30-second grace.
3. The shell logged a failed Settings layout audit at Info. **Fixed** — Warning
   in both.
4. `RunStartupCommandLine` never checked its target existed. **Fixed** — the
   shared prepare step does, for both.

**What is left of the cross-name work:** `XfeBestGameWindow` /
`WindowEngineEvaluateGame`. The verdict layer and now the CPU sampler are both
shared, so what remains duplicated is the candidate loop between them. The
shell's cooldown, Steam-foreground gate and reject logging stay its own. It is
the game-detection path on a program that replaces the Windows shell, so it
wants a machine with a controller — same gate as item G.

**Four contracts are now checked** that were held by nothing:

- the binding table must be an ordered array with unique actions and labels, and
  every action must reach an implementation;
- the two score-weight tables must offer the same keys, because the shared
  scorers index them by name and a missing key scores as empty on one product
  only;
- the helper's five command-line flags must be exactly what
  `SteamShell-Helper.ahk` parses, in both directions, and neither tree may spell
  one itself;
- and a Settings row must still reach a consumer, from the earlier pass.

**Still open and deliberately not merged:** `QuickMenuGetRows` /
`QuickMenuGetDefinitions` share 85 row labels. The rows genuinely differ, but the
settings surface has a shared spec tagging each row `both` / `standalone` / `xfe`
and the Quick Menu has none, so the same user-facing strings are typed twice.
That is a bigger idea than a merge.

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

### The validation harness is CPU-bound, not I/O-bound

Settled by measurement on 2026-08-08, after two wrong guesses. The full run is
about 235s; the timing column in the summary breaks it down. What it is NOT:

- **Not the UNC root.** `Get-ReadStats` reports *15 file reads (92 served from
  cache) in 508 ms* against a 26s validator. Two percent.
- **Not repeated reads.** Caching every source per process and caching
  `Get-EffectiveSource` whole moved the total 231.2s -> 235.9s, i.e. nothing.
- **Not the checks being numerous.** Running them ONCE instead of nine times is
  already done, and the remaining runs are the ones that carry signal.

It is .NET regex: ~1,100 assertions, most `(?s)` with `.*?`, each scanning an
effective source of ~1.5 MB with the includes inlined. The only real fix is to
run assertions against extracted function bodies rather than the whole file --
a rewrite of all 1,100, not a tuning pass, and not obviously worth it for the
~50s it might save.

**Do not optimise the file I/O again.** The counter in each validator's pass line
is there to say so; if it ever grows into seconds, something changed.

The one cheap cut left: the first negative test in 5b still runs both validators
(56.6s, of which ~46s is validation) to prove they work against a tree at a
different path. Dropping it saves a fifth of the run and loses that one
guarantee.

### An assertion that stops checking anything does not fail

The reflex after moving code is "remember to update the validators." It is not
enough, and the build already covers the case it addresses: an assertion that
NAMES a moved function fails loudly and gets fixed. The two that hurt keep
passing.

**Unbounded forward scans.** `(?s)Name\(\)\s*\{.*?Thing` reads as "Thing appears
inside Name" and does not mean it -- `.*?` runs to the end of the file. Once
Thing moves out of Name, the pattern finds it in a later function and the
assertion passes for the wrong reason. Two real cases were found by encoding
this rule: the shell's untitled-legacy-surface rule, where deleting the rule
outright did not fail the build, and the companion's assist-timer rule, which
named a function that has never re-applied the timers. Use
`(?:(?!\n\})[\s\S])*?`.

A pattern that terminates on `^}` bounds itself. Applying the body-scan idiom to
one of those breaks it -- the scan stops before the newline the `^}` needs --
which is how the first, indiscriminate pass at this broke ten extractors.

**Vacuous body constraints.** `$helperSource -notmatch '(?sm)^Name\(\)\s*\{...X'`
is true forever if the subject does not define `Name`. One real case: a rule
about the helper's `ApplyRuntimeTimers`, which the helper does not have.
Asserting a function is ABSENT is legitimate and reads as `-notmatch
'(?m)^Name\('` with nothing after it.

Both are checked now, in both harnesses, by `Assert-ValidatorAssertionShapes`
and `check_validator_assertion_shapes`. That is the durable version of "update
the validators": not a reminder, a build failure.

### `Replay-Validation.py` cannot see an assertion written against a property

It replays `$source -match '...'`. It does **not** replay
`$probeMatch.Value -match '...'` -- the usual shape once a validator has pulled
one function body out -- because its subject scan looks for `$name -match` and a
property access does not match that. Nor does the "every subject must be known"
check notice them, though its own comment claims EVERY subject.

**62 rules are in that blind spot,** and one of them failed on Windows against a
tree this script had just called clean: the companion's screen-probe rule, which
pinned `WinGetList()` inside `RunScreenProbe`.

The count is printed in the summary now, next to the replayed one. It is not
closed, because closing it means reimplementing each extraction here -- the
duplication this file already warns about. Treat the second number as the size
of what only Windows checks, and when a change touches a function that a
validator extracts by name, read that validator.

The other half of the same trap: **Windows reports the FIRST failure only**,
because `Assert-True` throws. One `FAIL` line is a lower bound.

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

Contrast the Steam-cloaking comment, then in `GetSwitchableWindows` and now in
`SharedTaskSwitcherWindows`, which asserts something **verifiable** — FSE cloaks
Steam, the shell does not run under FSE — and is checkable in a minute. It also
turned out to be the half worth keeping when the two copies were merged. The difference between those two comments is the
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
