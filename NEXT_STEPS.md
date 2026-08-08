# Next steps, and what was learned getting here

Written 2026-08-08, immediately after 2.0.0. This is a work queue and a set of
warnings. Delete it when the queue is empty.

The warnings matter more than the queue. Most of them cost real time this pass,
several produced a wrong answer that survived until something contradicted it,
and every one of them will recur for the next person who greps this codebase the
obvious way.

---

## Part 1 — Proposed work

### A. Share the window inventory (the root fix)

The consolidation shared the **judgement** and left the **inventory** per-tree.
`GameWindowShapeVerdict`, `GameWindowCpuVerdict`, `SortCandidatesByScoreAreaDesc`
and `WindowEngineIsLegacyApplicationSurface` are in `SteamShell-Common.ahk`;
`WindowEngineBuildSnapshot` (shell) and `AssistInventoryBuild` (XFE) are not.

That one missing layer is why the Task Switcher is duplicated, and why XFE
enumerates windows three times while the shell enumerates once.

Measured: **the two inventory items are 21 keys each, 19 identical.** The four
that differ are two aliases (`exe`=`proc`, `ours`=`scriptOwned`), one derived
value (`classLower`), and one genuinely shell-specific flag (`bpm`).

| Step | Work | Risk |
|---|---|---|
| **A1** | Shared builder. Shell's `WindowEngineBuildSnapshot` becomes a wrapper, `bpm` through a seam. Shell behaviour unchanged. | **High** — feeds focus and geometry on the product that *is* the shell |
| **A2** | XFE adopts it. Its three enumerations (`AssistInventoryBuild`, `RunScreenProbe`, `GetSwitchableWindows`) become one. | Medium |
| **A3** | Task Switcher shared: filter + Steam exception, both trees reading the inventory. | Low once A1/A2 land |

Three commits. Build and hardware-test between each.

### B. Task Switcher — already exists in both, under different names

**XFE is not missing this feature.** It is there as `GetSwitchableWindows` /
`ActivateSwitchableWindow` / `CloseSwitchableWindow`, against the shell's
`GetTaskSwitcherWindows` / `SelectTaskSwitcherWindow` /
`RequestCloseTaskSwitcherWindow` / `ForceCloseTaskSwitcherWindow`. Same Quick
Menu row label, same `page:TASKS`.

The names share no words, so the fingerprint gate — which compares functions
defined in both trees **under the same name** — can never see the pair. This is
precisely what `CROSS_NAME_DUPLICATES.txt` exists to record.

**Do not adopt the shell's filter wholesale.** XFE's version is 68 lines against
the shell's 28 because it carries a fix: Steam Big Picture vanished from the
switcher under Xbox FSE, rejected in turn by the cloaked check, the empty-title
check, the size check and the tool-window check. It resolves `isSteamWindow`
first and waives all four. Losing that re-breaks a bug someone spent real time
finding.

Resolved by A3, with the Steam exception unconditional. The shell's snapshot
drops **all** cloaked windows, and Windows cloaks for reasons beyond FSE, so the
shell may have the same latent bug and simply trigger it less often.

### C. `DiagnosticLogging` is a dead setting in the shell

Shipped to **both** products by the shared spec, labelled *"Log all XInput slots
on every change (diagnostic)"*, shown in the shell's Settings editor, read into
`EnableControllerDiagnostics` — and in the shell the only thing that consumes it
is `PositionGuiCentered`, which logs **window centring**. There is no
`ControllerDiagnosticTick` or `ControllerDiagnosticIntervalMs` in the shell.

A control that promises one thing and does another. Fix by porting the tick from
XFE (~30 lines); the global is already declared and read.

### D. Assert every settings row reaches a consumer

Would have caught C. `Assert-QuickMenuRows` already proves every Quick Menu row
reaches an activate path; this is the same check for the settings spec. Cheap,
and it fails the build on the next dead setting instead of waiting for someone to
notice.

### E. `ProductIdentity` prints on every green build

`Structural drift: 1 function(s) at or above 0.9 ... ProductIdentity (1)` appears
in every passing run. It is a false positive: both bodies are a `static Map` and
a `return`, so the call fingerprint is empty on both sides and scores 1.00. They
can never be shared — that is what the seam is for.

Exempt `$sharedSeamAllowed` from the structural-drift **report**, as was already
done for the **gate**. Ten minutes. The cost of leaving it is that a permanent
warning-shaped line in a green build teaches you to skip that section.

### F. De-indented blocks — 187, not 650

A control-flow line whose body sits at the same indent with no brace:

| File | Count | Genuinely ambiguous |
|---|---:|---:|
| `SteamShell.ahk` | 167 | 29 |
| `SteamShell-Common.ahk` | 12 | 3 |
| `SteamShell-Shared.ahk` | 8 | 4 |
| `SteamShell-XFE.ahk` | **0** | 0 |
| `SteamShell-Helper.ahk` | **0** | 0 |

XFE and the Helper are clean; this is legacy style in the oldest file. Fix the
**36 ambiguous** ones by hand and leave the other 151 — reformatting them is a
large diff for aesthetics. Example at `SteamShell.ahk:3297`, in INI parsing, next
door to the `CleanIniValue` bug fixed this pass:

```ahk
if (sc)
raw := Trim(SubStr(raw, 1, sc - 1))   ; guarded
hc := InStr(raw, "#")                  ; NOT guarded, reads as though it is
```

### G. `PollController` core extraction

**63% token-identical** once renamed locals are normalised (41% line-identical,
which is why line diffing misleads here — the button table differs only in line
wrapping). The largest identical runs are the core: state read, edge detection,
hold and chord tracking, mouse move, binding execution.

Differences are nine globals. Shell-only: `ControllerTestGui`,
`SettingsEditorDialogActive`. XFE-only: `CompanionDisabled`,
`EnableControllerDiagnostics`, `EnablePersistentMouseMode`, `ActiveInputBackend`,
`ActiveControllerIndex`, `SettingsVisible`, `SettingsDialogActive`. Two of those
are the same concept renamed (`SettingsEditorDialogActive` /
`SettingsDialogActive`, already recorded as `ProductSetDialogActive`).

Shape: shared `ControllerPollFrame` (read, edges, holds, chords, deadzone) plus
per-tree dispatch, because the products genuinely have different surfaces
competing for input. Two commits — extract with both trees behaving identically
and verify on hardware, *then* touch dispatch. Gate scores it 0.31, so nothing
demands it. Do it for maintenance, not for the score.

### H. Event-driving the window enumeration — parked on one number

Open **Settings → Advanced → Health Check**, "Coordinated window engine" row. It
already reports `last scan N windows in Mms`.

- ~12 windows in ~3 ms → **withdraw this**; 0.6% of a tick is not worth a hook.
- ~60 windows in ~45 ms → 9% of every tick confirming nothing changed; worth doing.

If it is worth doing, the narrow version is: hook `EVENT_SYSTEM_FOREGROUND` and
`EVENT_OBJECT_SHOW`/`HIDE` only — **not** `EVENT_OBJECT_LOCATIONCHANGE`, which
fires per-pixel during drags and would cost more than the polling it replaces —
and keep the 500 ms timer as a safety net. `TaskbarGuardWinEvent` is the working
template, including its reentrancy guard and its "log when the hook was
unavailable" discipline.

### I. Hardware verification (maintainer)

- **Sleep/resume.** The trap: if device hand-over alone recovers input you will
  see neither a `Power: resumed from sleep` nor a `Power: wall-clock gap` line,
  and layers 2 and 3 go untested. Try a longer sleep, and from inside a
  fullscreen game where XInput cannot mask a RawInput failure.
- **`ExportDiagnosticBundle` in both products.** Both callers were rewritten onto
  the shared `ExportDiagnosticArchive`; only statically validated.
- **Controller mouse speed** should feel unchanged after upgrading. If it feels
  roughly double, the ×32 migration factor is wrong for this hardware and 62.5 is
  correct — a one-line change in both migrations.

### Suggested order

**E, D, C** (small; D catches the class C belongs to) → **A1, build, A2, build,
A3** → **F** → **G** → **H** only if the number justifies it.

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
returns nothing there. It exists as `GetSwitchableWindows`. An entire
architectural justification was then built on top of an absence that was really a
naming difference.

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

Recorded so they are not re-derived: de-indents were **187**, not ~650; visible
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
