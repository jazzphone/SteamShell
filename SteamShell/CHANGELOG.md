# SteamShell changelog

## Unreleased — the RTSS cluster, the settings scrollbar and the Quick Menu title are defined once

Nine functions moved, about 330 lines that existed twice.

**To Shared:** `GetRtssHooksApi`, `ApplyRtssGlobalState`, `InitXInput`,
`SetRtssGlobalFrameLimit`, `SaveRtssFrameLimitToProfile`, `SettingsUpdateScrollBar`,
`QuickMenuTitleText`, `QuickMenuRowAcceptsRepeat`. **To Common:** `QuickMenuIdSet`.

The two frame-cap functions needed one genuinely new abstraction:
`ProductElevatedHelperAlive()`. The shell tests that the helper process exists and
re-verifies its identity on a one-second cache; the companion only tests that it
exists. Both are right for their program, and neither was a reason to keep 143
lines twice.

Everything else resolved through abstractions that already existed —
`SharedNotify` for the notify alias, `ProductIdentity` for the product's own name,
`GetQuickMenuPreviousExe` and `ProductBestGameExe` for the diagnostic line naming
the foreground game. `ProductIdentity` gained a `title`, separate from `name`
because the latter is prose used inside sentences ("the companion") and not what
belongs at the top of a menu.

`SettingsUpdateScrollBar` came with two small seams for the scrollbar control and
the viewport height — two globals in the shell, `SettingsLayout()` in the
companion. It was found by comparing six-line **blocks** rather than whole
functions: the names differ and the whole-function score sat below the cross-name
threshold, so no function-level scan could see it.

`QuickMenuRowAcceptsRepeat` had been recorded as a real divergence because the two
matched on different row fields. They were not testing different things: `MenuRow`
sets `action` equal to `id` for every adjustable row but one, so matching on `id`
is both equivalent and more robust. The remaining difference was that the shell
has a `qMouseSpeed` row the companion does not — naming it in a shared set costs
nothing, because a row that is never built cannot be selected.

One behaviour improved rather than merely merged: the "required DLL exports were
not found" line now names the DLL it looked in, which the companion's copy did and
the shell's did not.

Twelve assertions pinned the old shapes and failed, which is what they are for.
Each was repointed at what it protected rather than at the form it was written in
— `$rawSource` to `$source` for bodies that moved, the notify alias, and the
elevated-write gate now going through the seam.

Same-named functions in both trees: **67**. Still 0.80 or above structurally:
**three**, all verified — `ProductIdentity` (a seam, identical in shape and
required to differ in content), `SendSteamOverlayChord` (the companion's
`CompanionDisabled` guard, a concept the shell does not have at all) and
`QuickMenuGoBack` (different page stacks).

## Unreleased — a portable installation can be upgraded in place

Reported from a portable install with SteamShell and its helper in one folder:
Setup Assistant recognised it as a Standalone installation but did not know where
it lived.

The product came from the registration and was right. The directory came from
`InstalledPath`, which a portable installation never has — it is written by the
`if !portableMode` branch, deliberately, because a portable copy is
self-describing through its sidecar and must not overwrite a managed
installation's record. So detection knew what it was and had nowhere to point.

Two records do survive, and neither was consulted. `RegisteredPath` is written
inside `if registerShell`, which portable installs take, and the Winlogon `Shell`
value is the most authoritative of the three because it is what Windows will
actually launch. `ResolveInstalledShellExecutable` now tries all three in that
order and takes the first that exists on disk, parsing the Winlogon command with
the same `ShellCommandExecutablePath` a saved previous shell already gets.

**The second half is worse than the reported symptom.**
`SetupAssistantPreselectExistingInstallation` never restored the Portable
checkbox, and `SetupAssistantGetDeployment` reads exactly the browse radio and
that checkbox to decide the mode. An upgrade of a portable installation therefore
came back as `Custom` — which requires administrator approval and moves the data
into ProgramData. A portable install would have been converted into a managed one
because a checkbox was not ticked back.

`InstalledShellIsPortable` infers it from the absence of `InstalledPath` rather
than from `InstallationMode`, because that setting is written by the same branch
and is equally absent. "Registered, but no `InstalledPath`" is the shape the
deploy code guarantees for a portable installation, rather than one inferred from
a name.

Verified against six cases including a portable install whose only record is the
Winlogon value, a portable install that has been moved, and a managed install
whose executable has been deleted.

## Unreleased — the companion's tray icon survives an Explorer restart

The menus differ; the machinery around them did not. `ApplyTrayIconImage`,
`RegisterTaskbarCreatedListener`, `TaskbarCreatedHandler`, `ReassertTrayIcon`,
`InitializeTrayMenu` and a new `BuildProductTrayMenu` are shared, with
`ProductTrayItems()` and `ProductTrayBaseTip()` as the per-tree seams and the
icon filename carried in `ProductIdentity`.

**The companion had no TaskbarCreated handling at all.** Explorer rebuilds the
notification area and broadcasts that message; an icon that does not re-add
itself is gone until the program restarts. The shell handled it because it
manages Explorer, but an Explorer crash or a Windows update happens to any
process with a tray icon — and losing it took away the only route to Settings,
Disable and Exit that does not need a controller.

**The strategies differed, and that was the real difference.** The shell rebuilt
its whole menu on every refresh; the companion built its menu once and then
mutated it with `Rename` and `Enable`. That is not a style choice: a menu that is
never rebuilt cannot gain or lose an entry, which is why the companion could only
show a moved installation in its tooltip while the shell offered a menu entry for
it. Building both from a declarative list gives the companion the rebuild, and
with it conditional entries — the moved-installation entry now appears in its
menu too, opening its own Settings rather than a Setup Assistant it does not have.

The menus themselves stay per-tree, because they genuinely differ: desktop mode,
diagnostics and Reload Settings on one side, Disable/Enable on the other. Same
shape as the Health Check — share the harness, keep the content.

Ten assertions pinned `A_TrayMenu.Add(...)` literally and failed on the change.
Each was repointed at what it was actually protecting — that the checked state
still comes from both auto-mouse flags, that the moved-installation entry is
still offered, that the ordering still starts with the Quick Menu — rather than
at the imperative form it happened to be written in.

## Unreleased — a moved installation offers Setup Assistant, and never demands it

The verdict is now surfaced where a user can act on it. In SteamShell it adds a
tray entry, "Installation moved — open Setup Assistant", above everything else in
the menu, marks the tray tip, and states the reason in Setup Assistant's own
status line when that window opens. In the companion it marks the tray tip and
says it once through the status line at startup.

**What it deliberately does not do is decide anything.**
`SetupAssistantRequired()` is what determines whether the shell runtime starts at
all, and the verdict does not reach it. A stale string in a settings file must
never be able to leave a machine sitting in Setup with no shell — that would be
far worse than the wrong path it was reporting. `SetupAssistantRequired` still
reads `SetupState`, `SetupVersion` and `Product` and nothing else, which is
long-standing deliberate behaviour, and an assertion now pins both halves: the
verdict must stay out of it, and the tray offer must stay in.

No dialog at startup in either product. SteamShell is the shell, and the
companion starts alongside Steam under Xbox FSE — a modal in either case lands on
top of a session the user is in the middle of entering. A tray entry waits until
it is wanted.

The verdict is evaluated once per session and cached. The record is written by
Setup and by first-run self-recording, neither of which happens mid-session, and
the tray menu is rebuilt on every presentation-mode change — a settings-file read
per rebuild for an answer that cannot have changed. Setup Assistant refreshes the
cache after a successful apply, because it has just rewritten the record it would
otherwise be judged by.

Two globals had to be declared at the new call sites. Left undeclared they would
have resolved to empty locals, and an empty live path compares unequal to a
recorded one — so a correct installation would have reported itself as moved.

## Unreleased — one verdict on the installation, reported in Health Check

`SteamShellInstallationVerdict` classifies what the record says about the running
installation as `consistent`, `new`, `moved` or `older`, and
`AddInstallationRecordHealthRow` puts that in the Health Check of both products.
The startup log line and the Health Check row now come from the same
classification rather than two descriptions that could drift apart.

**Only `moved` is a warning.** A `new` or `older` record is a fact about the
installation, not a fault in it: a fresh machine has nothing recorded yet, and an
older Setup workflow version is what an upgrade looks like from the inside.
Marking either as a warning trains the user to ignore the row that matters.

**`moved` is decided before the version.** A copy carried between machines is
usually stale in both respects at once, and checking the version first would
report "recorded by an older Setup" while burying the fact that the paths belong
to a different PC.

Built from AutoHotkey built-ins only. `ToInt`, `ToBool` and
`NormalizeSteamShellProduct` are standalone-only, and a shared function that
quietly depended on them would fail to load in the companion.

Still advisory: nothing branches on the verdict. Note that `SetupAssistantRequired`
already gates on `SetupState`, `SetupVersion` and `Product` and has done for some
time -- that is existing, deliberate behaviour. What stays advisory is the
comparison of the recorded paths and mode against reality.

## Unreleased — the installation record can now contradict the installation

Setup already recorded what an installation is, in two places. The registry key
carries `Product`, `InstalledPath`, `DataPath`, `InstallationMode`,
`RegisteredPath` and `PreviousShell`; the settings file carries a `[Setup]`
section with `SetupState`, `SetupVersion`, `Product`, `InstallationMode`,
`InstallDirectory` and `DataDirectory`.

Three of those six INI keys were **written and read by nothing**.
`InstallationMode`, `InstallDirectory` and `DataDirectory` were produced by
Setup, documented in the sample INI as though they meant something, and consumed
nowhere -- a record with no power to contradict the thing it described.

They are read now, compared against what is actually running, and any
disagreement is logged. Paths compare case-insensitively with trailing separators
removed, since neither is meaningful on Windows. A record with no `SetupState`
returns no drift at all, so a fresh installation cannot report itself as moved.

**Advisory, and that is the design, not a first step toward enforcement.** This
runs on a Windows shell replacement. A stale path in a settings file must never
be able to leave a machine with nothing to log in to, so the check logs and
returns; no caller branches on it.

**The companion gained a `[Setup]` section of its own** (schema 16), and writes
it itself. Setup Assistant records an XFE install in SteamShell's registry key
and SteamShell's INI, not the companion's -- and a companion copied into place by
hand never met that installer at all. It fills in its directories on first run
and only when they are absent, so an ordinary start does no file writes.

The registry stays the better source while it exists. It is also exactly what
does not survive a move: copy an installation to another PC and HKCU is empty
while the settings file still describes the old machine. The file travels with
the installation, which is what makes it the only record able to notice.

What already worked and was left alone: startup trusts the registry's `DataPath`
only when `InstalledPath` matches the running executable, so a portable or test
copy cannot adopt an installed shell's settings. That check was already right.

## Unreleased — the companion can see a minimized game, so its last stand-in is gone

Found by auditing the 27 seam functions for the pattern behind the score-floor
mistake: a weaker mechanism standing in for one the other product has, wearing a
plausible reason.

One more instance, and it was the same author. `XfeBestGameWindow` passed a
hardcoded `false` for `minimizedLegacy`, because the companion's inventory did not
carry the fields to answer, and the gap was covered by falling back to
`LastObservedGameExe`. An exclusive-fullscreen game often minimizes itself the
moment Steam takes focus, and a minimized window has geometry no shape test can
read, so those games scored as nothing and the stored foreground name was the
only answer left. That name outlives the process it names, which is how a
per-game cap could reach a profile for a game that had already exited.

`WindowEngineIsLegacyApplicationSurface`, `WindowEngineIsMinimizedLegacyGameSurface`
and `WindowEngineItemIntersectsMonitor` moved to Common -- none touches a global.
The companion's inventory gained `style`, `exStyle`, `owner`, `minMax`, `area`,
`desktop`, `steam`, `proc` and `scriptOwned`; the last three alias existing keys
under the names the detectors were written against. The additions are additive
and the assist features read what they always read.

The fallback is deleted rather than demoted. `ProductBestGameExe` now returns the
scored answer and nothing else, in both products.

What deliberately did NOT come across: the shell uses these detectors to decide
whether a minimized window may be RESTORED, which is an activation concern the
companion excludes by design. Here they answer only "is this a game", for naming
a profile.

**`SharedPersistSettings` was audited and left alone.** The shell stages a copy
and swaps atomically while the companion writes directly, and the recorded reason
holds: a half-written settings file on the Windows shell is a machine that boots
into nothing, where for an ordinary application it is lost settings. The
consequence genuinely differs, which is what separates a decision from drift.

## Unreleased — the companion can now say why it chose a window, and its Health Check grew up

Two pieces of the shell that the companion should always have had.

**Game-score diagnostics.** The companion gained the scorer last change but not
the logging around it, so when it picked the wrong window for a per-game RTSS cap
-- a cap keyed on an executable name, where a wrong pick lands in another
program's profile -- there was no way to see what it had considered. The shell
could answer that; the companion could not, for the same decision made by the
same code.

The column formatters (`TruncPad`, `NowStamp`, `FmtPid`, `FmtCpu`, `FmtScore`,
`FmtHwnd`, `FmtRect`) moved to Common and the table itself
(`LogRow`, `LogRawLine`, `ShouldLogRateLimited`, `LogGameCandidateTable`) to
Shared. The shell's evaluate loop now builds only the header -- the activation
threshold and any skip reason are its own context -- and hands the rest over. A
log from either product reads identically.

Companion schema 15 adds a `[Logging]` section, which this product did not have:
rotation lived under `[Companion]` and there was nothing to configure about
diagnostics because there were none. Rotation stays where it is; moving a key
every existing INI already carries would break them for no gain. Everything is
off by default -- this writes a table on every evaluation and is a
troubleshooting aid, not something a normal session should pay for.

Both products log every candidate they considered, so the case that most needs
explaining -- candidates were found and none looked right -- produces a table
rather than silence.

**The companion's score floor on the RTSS naming path is gone, and the setting
with it.** It was added in the previous change and was a mistake. The shell sets
`LastBestCandidateProc` from its best candidate unconditionally; its
`GameMinScoreToActivate` governs pulling FOCUS to a game, which is disruptive and
a different question from naming a profile. The companion applied that floor to
naming, and falling below it returned `LastObservedGameExe` -- the foreground-only
observation the scorer exists to replace. A low score therefore discarded a
scored answer in favour of an unscored one, which is backwards. Both products now
return the best candidate and let `IsUsableProfileExe` reject Steam, Explorer and
their own executable, which is the filter that was always doing the real work.
Nothing plausible is lost: protected processes, launchers, our own windows and
anything failing the shape test never become candidates at all.

Schema stays 15 -- it has not shipped, so the retired `[Assist] GameMinScore` key
is simply removed rather than migrated.

**Health Check.** The harness moved to Shared; the checks stayed per-tree behind
a `ProductHealthResults()` seam, joined by `ProductVersionText()` and
`ProductCenterGui()`.

Which conditions matter is entirely product-specific -- the shell tests Winlogon
registration and standard-user launch capability, the companion tests controller
backends and AnyFSE -- but presenting them is not. The companion had built its
whole report inline as flat "PASS - text" strings in a read-only edit box, which
left it unable to copy the report, unable to refresh without reopening, and
rebuilding the same text separately inside its export bundle. It now gets the
shell's sortable list, Copy Report and Refresh, and there is one definition of
the report format.

`HealthResult` kept the shell's signature -- push onto a passed array rather than
return a Map -- because forty-odd call sites already read that way, and changing
the shape to suit a second caller would have been the tail wagging the dog.

An assertion pinning two Health Check sentences was repointed at their
**structure** instead: a disabled helper and an enabled-but-not-running helper
must remain distinct rows with distinct statuses. That claim survives rewording;
the prose did not.

## Unreleased — the rest of the duplication, and a check so it does not come back

Continuing the triage. Every function that was structurally identical between the
trees is now defined once: **zero remain at or above 0.90** once naming and
formatting are ignored, down from six. Same-named functions in both trees fell
from 80 to 66.

**Moved to Shared:** `GetQuickMenuPreviousExe`, `RtssProfileTargetExe`,
`RtssSaveProfileValueText`, `CycleDefaultAudioOutput`, `CycleRtssFrameCap`.

Two of those were not the naming drift they looked like.

`GetQuickMenuPreviousExe` derives the executable **live** from the window handle;
the companion read a `QuickMenuPreviousExe` string captured when the menu opened.
The companion already tracked the handle on the adjacent line, so adopting the
live form costs no new state and fixes a real case: a game that exits while the
Quick Menu is open left the snapshot holding its name, and a per-game frame cap
would then be written to a profile for a process that no longer exists. Reading
through the handle returns "" once the window dies. The snapshot is retained for
its other uses, which legitimately want "what was in front", not "what is".

`CycleRtssFrameCap` differed in its **signature**: the shell returns a value and
branches on it, the companion returned nothing. The shell's version is the one
kept; the companion's call sites ignore the result and are unchanged.

A `ProductBestGameExe` seam replaces the part of the target resolution that is
genuinely per-tree — the shell answers from its window engine's scored candidate,
the companion from `XfeBestGameWindow` with its foreground observation beneath.

**`Report-StructuralDrift` in `Validate-Common.ps1`** compares same-named
functions with comments stripped, string and number literals collapsed, and the
notify aliases folded, then reports anything at or above 0.90. It **reports and
does not fail**: a high structural score is evidence, not a verdict, and
`SettingsEditorMouseWheel` and its twin are deliberately separate. The point is
that new drift is visible in the pass that would otherwise bury it.

Both functions were moved by script with a single substitution — the notify name
— rather than retyped, after hand-merging introduced two regressions in the
previous change.

## Unreleased — five functions were duplicated for no reason, and one hid a leak

A claim in `XFE_PARITY_NOTES.md` — that the functions differing between the trees
are "real divergence, not drift" — was repeated without being tested. Testing it
does not support it.

Similarity was being measured on raw text, where indentation and local variable
names dominate. Re-measuring structurally — comments stripped, locals renamed to
a placeholder, known aliases folded — separates the two cases. Of 41 same-named
functions below 0.70 raw similarity, only **7** are documented anywhere as
deliberate. Six scored **0.91 or higher structurally**: the same code, formatted
and named differently.

`XInputGetState` is the clearest illustration: 0.70 raw, one algorithm, identical
DllCalls including the ordinal-100 Guide-bit trick. The distance was `bufState`
against `state`, `bEx` against `exButtons`, and one tree indented.

**The root cause was the notify seam.** `SharedNotify` was defined in each tree
and delegated outward to `ShowNotification` or `SetStatus` — which turned out to
be the same nineteen lines against the same five globals. The shell's name is a
leftover from a bottom-corner toast it removed years ago; both products have
shown the Quick Menu status line ever since. Because the two names existed, every
function that reported anything looked product-specific. `SendRtssShortcut`'s
entire diff was four notify calls.

The seam now points the other way: the implementation lives in
`SteamShell-Shared.ahk` and each tree keeps a one-line alias, so 58 and 78 call
sites are untouched and there is no second copy to drift. The companion also
regains the empty-message guard it had lost.

**Moved to Common:** `SendToPretty`, `ForceForegroundWindow`.
**Moved to Shared:** `SharedNotify`, `SendRtssShortcut`, `XInputGetState`.

`ForceForegroundWindow` was hiding a defect. The shell undoes `AttachThreadInput`
in a `finally`; the companion detached inline, so a throw from
`SetForegroundWindow` left this process's input queue attached to another
thread's for the rest of the session. The shell's version is the one kept, along
with its explicit `User32\` prefixes — an unqualified `DllCall` resolves by
search order, which is not something a focus primitive should depend on.

Two regressions were introduced while merging by hand and caught by existing
assertions before the build: `Send` in place of `SendChordSafe`, which would have
sent chords without releasing held modifiers, and `Trim(shortcut) = ""` in place
of `shortcut = ""`. Both pins were written against the original shape and did
their job.

## Unreleased — both products now decide "which window is the game" the same way

The arbiter moved to `SteamShell-Common.ahk` and both trees call it.

The shell scored every visible window on shape, CPU and audio and ranked them.
The companion asked only whether the *foreground* window was at least 85% x 80%
of its monitor. For focus assistance that was adequate. For the per-game RTSS
frame cap it was not: that cap is keyed on an executable **name**, so a
misidentification does not degrade gracefully — the cap is written to another
program's RTSS profile and reported as saved. A fullscreen launcher, a video
player and a browser all pass a shape-only test. CPU and audio are what disagree,
and the companion was already sampling both for other purposes.

**What moved to Common:** `GameWindowShapeVerdict`, `GameWindowCpuVerdict`,
`SortCandidatesByScoreAreaDesc`, and the WASAPI per-process peak helpers
`GuidBuf`, `GetActiveAudioPidPeaks`, `GetActiveAudioPidPeaksCached` — none of
which touch product state.

**Deliberately two verdicts rather than one call.** Each tree samples CPU only
for windows that pass the shape test, and audio only for those that pass CPU,
because the CPU sampler mutates a per-PID cache and the audio map is built lazily
on first use. A single function taking every signal pre-gathered would collect
both for windows about to be discarded, on every tick.

**The shell's behaviour is unchanged.** Verified by fuzzing the original inline
logic against the extracted version across 300,000 random candidates covering all
three outcomes — accepted, `TOO_SMALL`, `CPU_ZERO_STRICT` — with zero
differences. A second copy of the same shape test inside `HasGameLikeWindow` now
calls the shared verdict too; it had duplicated the expressions and constants, so
a tolerance changed in one place disagreed silently with the other.

The Window Engine itself was **not** ported, and should not be. Its focus
arbitration, activation rules and geometry are excluded from the companion by
design — "the geometry layer of 1.5's window engine is never ported". The
recorded boundary was always *inventory and detection yes, geometry no*, so
improving detection completes that line rather than crossing it. Nothing added
here moves, sizes or focuses a window.

`AssistWindowLooksLikeGame` is untouched and still drives Game Focus, Steam
Assist and Launcher Cleanup. The scorer answers a different question, and
changing the cheap shape test would have altered three behaviours to fix one.

Companion settings schema 14 adds twelve `[Assist]` keys for the scorer, all
defaulting to the shell's values so both products choose the same window. The
foreground observation is retained below the scorer as a last resort, for the
case where nothing clears the threshold.

## Unreleased — three RTSS defects the companion did not have

Found by diffing the RTSS cluster against SteamShell-XFE ahead of sharing it. The
two trees call the same DLL through the same path, and most of what separates
them is drift — line wrapping, parameter names, `ShowNotification` vs `SetStatus`.
Three differences were not drift, and all three were the shell falling behind.

**A helper that exits mid-session froze the UI for three seconds per write.**
`ElevatedRtssWritesAvailable()` is `ElevatedHelperAvailable && RtssElevatedFrameCapWrites`
— two flags. Nothing clears them when the helper process dies, so the request was
posted to a listener that no longer existed and `WaitForElevatedRtssRequest` ran
its full 3000 ms timeout under `Critical("On")`. Two of the four elevated-write
sites had no gate at all, so a single frame-cap change could pay that twice: six
seconds of frozen UI. Never having had a helper was always safe, since
`RequestElevatedRtssFrameLimit` returns false immediately; it is specifically the
mid-session death that cost the freeze. All four sites now confirm the process
through `ElevatedHelperIsVerified()`, which already existed and does `ProcessExist`
plus an identity re-check on a one-second cache — the companion's equivalent gate
was never ported, but the shell's own is stronger.

**Selecting an RTSS row with RTSS missing did nothing and said nothing.**
`ApplyRtssGlobalState` returned false silently. On a couch UI with no keyboard
that is indistinguishable from a broken menu. It now reports the reason, as the
companion always has.

**The frame cap could latch read-only for the session without telling anyone.**
When RTSS accepted a write and then reported a different value, the shell set
`RtssFrameCapWriteBlocked`, wrote a log line and returned — so the Frame Limit row
stopped responding with no explanation on screen. It now says so, and names which
of the three cases occurred: the helper tried and failed, no helper was running,
or elevated writes are switched off. The old text asserted "the elevated helper
could not apply it either", which became untrue once the write was gated.

## Unreleased — Setup Assistant showed both products' sign-in options as ticked

Section 4 offered "Register the selected SteamShell.exe as the Windows shell"
and "Start SteamShell-XFE automatically at sign-in" both ticked at once, even
though the two products are mutually exclusive.

Two separate causes. `SetupAssistantRefreshProductMode` cleared only the opposite
product's box on the XFE branch and not on the shell branch, so the XFE logon-task
box kept the tick it was created with. And the function was reached only from the
product radio buttons and from `SetupAssistantPreselectExistingInstallation`,
which returns early when nothing is installed — so on a clean PC, the first-run
case every new user sees, it never ran at all and both boxes stayed ticked *and*
enabled.

Both branches now set both boxes, and the product mode is applied whether or not
anything was preselected. Disabling the irrelevant box was already intended and
was not by itself enough: a ticked checkbox states an intention whether or not it
can be clicked.

Apply was never affected. It branches on the selected product before reading
either value, so the irrelevant checkbox could not reach an install — this was
what the window showed, not what it did.

## Unreleased — uninstall had no way forward when detection failed

Setup Assistant answered a failed detection with "No installed SteamShell or
SteamShell-XFE was detected on this PC. Nothing was changed." and stopped there.

A prompt for exactly this case already existed — `ChooseSteamShellProductToRemove`,
which names both products and describes what removing each one does — but it was
reachable only from `/uninstall` on the command line. Setup Assistant never got
to it: on failure it returned, and on success it passed the product as
`knownProduct`, which short-circuits ahead of the prompt.

That dead end became easier to reach in the same change that made detection ask
what is *registered to start* rather than what exists on disk. Three ordinary
cases land there: an XFE install whose logon task was declined, a shell whose
Winlogon value was already put back by hand or by a half-finished uninstall, and
the documented workflow of uninstalling from a freshly downloaded `SteamShell.exe`
against a registry that has been partly cleaned.

Setup Assistant now offers the same prompt, quoting the resolver's own reason for
being unsure, and the confirmation says "Remove the installation you chose?"
rather than claiming a detection that did not happen.

Removing the XFE logon task no longer reports failure when there is no task to
remove. `schtasks /delete` exits non-zero for a task that does not exist, and
that value was returned straight out of `RemoveSteamShellXfeInstallation`, so an
uninstall with nothing to remove told the user the installation could not be
fully removed while every other step had in fact succeeded. Success now means the
task is absent afterwards; only a task that survives a delete attempt is a
failure, and that is logged with its name. This was reachable before today's
change — an install whose logon task was declined hit it — and would have
affected every hand-picked XFE removal, since that prompt is reached precisely
because nothing is registered.

`SteamShellXfeLogonTaskExists` takes an optional task name so the removal can
confirm its own work against both the current and legacy names. Existing callers
are unchanged.

The validator now rejects a wrapped expression whose line begins with `(`.
AutoHotkey v2 treats such a line as the start of a continuation *section* and
parses the rest of it as continuation options, so an inline ternary wrapped that
way fails to load with "Invalid option" and nothing in the file runs. It reads as
ordinary formatting and survives review; the confirmation prompt above was
written that way and only the AutoHotkey parser rejected it. A `(` line that
closes on the same line is an expression and still passes, as does a deliberate
continuation section with or without options.

## Unreleased — uninstall left the machine looking installed

Reported from a real machine: Setup Assistant kept offering to remove
SteamShell-XFE on a PC where only the shell was installed.

**Both uninstalls deliberately keep the executable and its settings** — they say
so to the user in as many words. That makes file presence useless as a test of
what is installed, and detection was testing exactly that:

```ahk
xfeOnDisk := xfePath != "" && FileExist(xfePath) != ""
if (xfeStartsAtLogon || xfeOnDisk) { product := "XFE" ... }
```

XFE uninstall cleared `Product` and `XfeLogonTaskRegistered` but never
`XfeInstalledPath`, so a recorded path went on pointing at a file that was
deliberately left. XFE is tested first, so the machine reported XFE **forever
after** — over a shell installation that was genuinely there.

**Five values were never deleted by any uninstall**: `InstalledPath`,
`DataPath`, `InstallationMode`, `XfeInstalledPath`, `XfeHelperDeployed`.

Five fixes:

**1. XFE uninstall clears its own location records.** `XfeInstalledPath` and
`XfeHelperDeployed` — the latter was written and never read at all. Standalone's
three are deliberately **not** treated this way: its startup matches the
recorded EXE against the running one to find its ProgramData, so deleting them
would strand a retained installation's settings. The existing comment saying so
was right.

**2. Detection asks what is registered to start, not what exists.** Both
`DetectExistingSteamShellInstallation` and `ResolveInstalledSteamShellProduct`
now key on the logon task and its flag for XFE, and the Winlogon value and
`RegisteredPath` for the shell — evidence an uninstall actually clears. XFE is
still tested first, which was never the bug.

**3. The registry key is no longer deleted wholesale.**
`SetupAssistantUninstall` ended in `RegDeleteKey` on the whole SteamShell key,
reached only when the user also chose to delete files. On a machine that had run
both products that took the *other* product's `InstalledPath`, `DataPath` and
`InstallationMode` — the three the ordinary uninstall carefully preserves — and
`PreviousShell`, which is what a later restore needs to put the user's original
shell back. Now product-scoped, and the key itself goes only once nothing is
left in it.

**4. The elevated helper task is removed unconditionally.** It was gated on
`HelperTaskRegistered`, which Setup writes at the end — so an interrupted
install, a hand-edited registry or an upgrade from a build that never wrote it
left the task behind with nothing to notice. A stale `HighestAvailable` task
pointing at a binary is the worst artefact an uninstall can leave, which is why
the XFE path has always removed its equivalent without asking first.

**5. Standalone names the helper it leaves behind**, as XFE already did. The
binary is administrator-owned in an administrator-only directory and nothing
starts it once the shell is gone — a reason to say where it is, not a reason to
stay quiet.

### Dialogs that could open behind something

Two real gaps, found while checking the above:

- **`AutoLogonDialogMessage` asked for neither an owner nor MB_TOPMOST** when
  its window did not exist, so it took ordinary z-order. It is reached during
  sign-in configuration, where a prompt nobody can see is a machine that appears
  to have stopped.
- **Four dialogs used a bare `262144`** — topmost, but never owned. Owning to an
  active SteamShell window is stronger where one exists; `MB_TOPMOST` is the
  fallback, not the default. The three desktop-restore prompts and the Steam
  launch failure now route through the helper that picks.

Every dialog in the tree is now owned-or-topmost, and a new assertion fixes the
number of raw `MsgBox` calls at five, so a sixth way to open one fails the build.

## Unreleased — the two shelved items, taken off the shelf

### Typed settings readers, and a bug class that can no longer be written

Standalone stated every default twice:

```ahk
ClampInt(ToInt(IniReadS("Timing","MouseHideDelay","1000"), 1000), 0, 60000)
```

once as the absent-key default, once as the parse-failure fallback, with nothing
forcing them to agree. Three pairs had already drifted: `[Splash] Mute`
documented `false` and fell back `true`, `PlayFullDuration` the reverse, and
`SafetyMaxMs` quadrupled its own ceiling. A validator assertion caught that
class; the typed readers make it **unwriteable**, which is the stronger fix.

**89 sites migrated** — 42 int, 8 float, 39 bool. The plan estimated 47 and had
never counted the boolean sites. Every default and every bound was compared
before and after: **zero parameter changes, zero settings lost.**

The readers went into `SteamShell-Shared.ahk` rather than being a third copy, so
both programs compile one definition. That was only possible because XFE's
readers had been fixed first — before that they could not strip an inline
comment, and `ReadBool` returned a hardcoded `false` for anything unrecognised
instead of the setting's own default. Porting them earlier would have imported
two defects into the shell.

**One composed read survives, and the validator names it.**
`EnableMouseParkOnFocusChange` takes its default from a retired key when one is
present, so its default is a computed expression that a one-default reader
cannot express. Migrating it means deciding how long retired keys stay honoured
— a separate question. The 55 bare `IniReadS` sites are untouched: they state
one default and never had the defect.

The old mismatch assertion is kept but can no longer fire, so a new one forbids
the composed form outright. **A rule that cannot fail is the failure this
project keeps rediscovering**, so the floor is now held by something that can.
Two further rules were added: every typed reader must route through
`CleanIniValue`, and `SettingsPath` and `IniPath` must be reassigned in step —
the readers take their path from the second, and three sites move both.

### Validator patterns bounded to the functions they name

**348 patterns bounded, up from 18. None left unbounded.** The 236 deliberate
cross-file ordering checks were not touched.

The method was the finding. Bounding a pattern that already matches inside its
function cannot change the result, so every one of 952 assertion results was
compared before and after: anything that changed was either a latent overrun or
a broken edit. **Exactly one changed.**

```
'(?sm)^OpenParentGeometryEvent\(\).*?OpenEventW.*?Local\\SteamShellGeometry-.*?'
'ParentAllowsElevatedGeometry\(\).*?WaitForSingleObject'
```

It anchors on one function and requires two things from the **next** one. Split
into two bounded assertions, so each checks the function it names. That is the
second real overrun this codebase has produced, after the Frame Limit `wrap`
parameter.

Three newly bounded patterns were mutation-tested and all three still fail when
the thing they check is broken.

**The first attempt corrupted both validators.** Patterns were matched against a
comment-stripped copy and rewritten in the original at those offsets; comment
lines change length, so the offsets meant nothing and the edit landed on 84
lines of the cross-file ordering checks — precisely the ones that must not be
bounded. Reverted from a backup taken beforehand. **That is the third blanket
text transform to cause damage in this work**, after a migration table rewritten
into a self-move and an embedded INI key renamed inside a string literal. The
common thread is verifying the summary a transform prints rather than the result
it produced.

Two assertions per validator turned out to have a **comment inside the pattern
expression**, which makes them invisible to any matcher working on raw text.
Those needed hand edits.

## Unreleased — four functions that were one function under two names

The parity checks match on **name** first, so a function copied into both trees
and then renamed in one of them is invisible to every check this project has.
Cross-comparing standalone-only against XFE-only functions for the same *logic*
found five such pairs; four are now shared, and what kept each apart was smaller
than the rename implied:

| pair | what actually differed |
|---|---|
| `ShortenQuickMenuText` / `ShortenText` | **nothing** |
| `HandleUncaughtSteamShellError` / `HandleUncaughtCompanionError` | **nothing** |
| `StopElevatedInputHelper` / `StopElevatedRtssHelper` | one log label |
| `RecordShortcutChord_Cancel` / `RecordShortcutCancel` | one Map key, `"ih"` vs `"input"` |

The two with nothing between them are pure and touch no global, so they went to
`SteamShell-Common.ahk` — the shortener, and the uncaught-error handler that
releases a held mouse button before anything else. The other two touch per-tree
globals and went to `SteamShell-Shared.ahk`; the log label became
`ProductIdentity()["helperLabel"]`, reusing the seam added earlier rather than
adding another.

**Starting** the elevated helper stays per-tree and `SHARED_FUNCTIONS.txt` still
records why. **Stopping** it does not: closing a process by PID and waiting for
it to go is the same operation in both products.

`SettingsEditorMouseWheel` / `SettingsMouseWheel` stays split. Its differences
are real rather than cosmetic — XFE guards on a `SettingsVisible` global that
standalone does not have at all, excludes an extra control class, and scrolls a
differently-shaped window. Two seams for eighteen lines is the worse trade.

**A gap this opened, and closed.** With the uncaught-error handler in Common, a
tree could stop calling `OnError` entirely and the body assertion would still
pass, because Common supplies the function regardless. Only the elevated
helper's registration had ever been asserted. Both trees now pin theirs against
`$rawSource`. Wherever a per-tree registration meets a shared body, the wiring
needs its own assertion or the shared definition covers for a program that never
installs it.

Two validator assertions needed the `$rawSource` → `$source` move again, for the
third time in this work — and this time the offline replay caught them
immediately rather than a Windows run finding them. **951 regex assertions, 2
count assertions, 0 failures, 0 harmful vacuity.**

## Unreleased — second Windows run: a count, and an assertion that had gone quiet

One failure, and it found two problems in the same assertion — one loud, one
silent.

**The loud one.** `[regex]::Matches($rawSource, 'SendRtssShortcut\(').Count -ge 5`
counts call sites in the **unresolved** tree. `ToggleRtssOverlay` and
`ToggleRtssFrameLimiter` moved into `SteamShell-Shared.ahk` when they turned out
to be byte-identical, and took two of the five call sites with them. Three left,
rule broken, nothing actually wrong. Counting now uses `$source`, with the
includes resolved, where all five are still visible.

**The silent one, in the same `Assert-True`.** Its last clause is
`$rawSource -notmatch '^ToggleRtssOverlay\(\)\s*\{ … EnsureRtssRunning\(\)'` —
the rule that exists because that function once ran `EnsureRtssRunning` *before*
checking the shortcut, launching RTSS for a user who had configured nothing.
With the function no longer defined in `$rawSource`, a pattern anchored on its
definition **could never match, so the assertion could never fail.** It would
have gone green forever. Also moved to `$source`, where it can fail again.

That is the shape this changelog keeps recording — an assertion that passes
because it stopped being able to run — and this time the *cause* was a function
moving between files rather than a body being edited underneath a loose regex.

**The offline replay missed it for the third documented reason.** It models
`$var -match '…'`. This was `[regex]::Matches(…).Count`, which is neither a
match expression nor a structural set comparison; it is the third class this
project has already written down. The replay now covers `.Count` comparisons and
`.Index` anchors as well.

**And a new check, because the silent failure is the dangerous one.** The replay
now scans for *harmful vacuity*: a `-notmatch` that reaches into a function's
**body** where that function is absent from the subject it is being matched
against **but still compiled into that program.** Absence assertions — "the
helper must not define this at all" — are correctly left alone; there are six,
and they are doing their job. Harmful vacuity is now **zero**, where before this
fix it was one.

## Unreleased — first Windows run of this work, and what it caught

`Run-SteamShellValidation.cmd` on Windows PowerShell 5.1 with AutoHotkey 2.0.26.
Both syntax checks passed and XFE's validator passed; standalone's failed on
**one assertion, reporting two defects, both introduced by this work.**

**A blanket rename reached inside a string literal.** Renaming standalone's
`GameLogRotateMaxKB`/`GameLogRotateBackups` **globals** to match XFE's used a
lookbehind that protected quoted occurrences — so `IniReadS("Logging",
"GameLogRotateMaxKB", ...)` survived correctly. It did not protect the *embedded
default INI text*, where the same names sit at the start of a line inside a
multi-line string. Those two lines were rewritten, so the INI that a fresh
install writes declared `LogRotateMaxKB=` while the code that reads it still
asked for `GameLogRotateMaxKB` — a setting that would have been written and then
ignored. The embedded text is restored; the INI keys on disk never changed, and
that was the whole point of renaming only the globals.

**A documented setting was added to one place and not the other.**
`[StartupPrograms] StaggerMs` has always been read by standalone and never
listed in its sample; adding it to the sample without adding it to the embedded
default made the two disagree in the opposite direction. It is now in both, so
the setting is finally real in the file a fresh install writes.

**This is the second blanket text replace to cause a defect in this work** — the
first rewrote a migration table's own entry into a self-move. Both were caught by
reading the result back rather than by trusting the edit.

**The offline replay could not have caught either.** It replayed the validators'
**949 regex assertions** and none of their **89 structural ones** — set
comparisons, version cross-checks, file existence, the AutoHotkey/Python
constant check. The failing assertion was structural: *"Sample INI is missing
schema keys"*, a set difference between the embedded schema and the sample. That
is precisely the blind spot this project has already recorded twice, under
*"three classes of validator check that my offline simulation could not see"*.
The replay now covers the schema comparisons in both directions, the schema
version cross-checks, the required-function list, the default/parse-failure
fallback rule, and the simulation constant.

Everything else in the run behaved correctly: the negative tests reported
**SKIPPED** rather than PASS, because section 5 checks for a green baseline
before breaking anything, and `current/` was left untouched.

## Unreleased — consolidation by intent, not by byte-identity

`XFE_PARITY_NOTES.md` has long argued that *"how many functions are
byte-identical is a poor proxy for how much these trees benefit each other."*
This pass took that seriously and sorted the 83 functions defined in both trees
by **why** they differ rather than by how much.

**Eleven functions moved into `SteamShell-Shared.ahk`** (54 → 65), in three
groups:

*Already identical.* `ToggleRtssOverlay`, `ToggleRtssFrameLimiter` and
`ControllerMouseSafetyTick` were byte-identical including comments, and the
parity advisory had been printing them under *"Identical in both trees and not
yet shared"* on every build.

*Differing by one product string.* `VerifyElevatedHelperProcess`,
`SanitizeDiagnosticText` and `IsUsableProfileExe` differed by an error message,
a redaction token and an executable name respectively — nothing else. A single
`ProductIdentity()` seam returning name/exe/dirToken covers all three, chosen
over three accessors because the seam this file may call back into is
enumerated and checked, so it is worth keeping small.

**One stale decision record, corrected.** `SHARED_FUNCTIONS.txt` recorded that
`VerifyElevatedHelperProcess` "stays per-tree: standalone compares against its
own installed-helper path and XFE against a different one." Both trees read that
path from the same global. There was never a difference to preserve — only the
closing message named its own product. The justification had outlived the code
it described, which is exactly how a function stays duplicated for years.

*Differing by names.* `RotateLogIfNeeded` was the same algorithm twice, differing
by two globals and three local variable names. `QuickMenuDestroyWindow` differed
by a line wrap. Standalone's `QuickMenuFooterCtrl` and XFE's
`QuickMenuStatusCtrl` are the same bottom line under two names, and standalone's
`GameLogRotateMaxKB`/`GameLogRotateBackups` globals are XFE's
`LogRotateMaxKB`/`LogRotateBackups`. Both renamed in standalone — **the INI keys
are untouched**, so no settings file changes.

**Two real differences kept, behind seams rather than duplication.** Clicking a
Quick Menu row *selects* it in standalone and *activates* it in XFE — a
deliberate product decision, now expressed as `QuickMenuMouseChoose` with all
the DPI-scaled hit-testing above it shared. `QuickMenuConfirm` routes its
message through the existing `SharedNotify` seam.

**A dead row you could highlight, in both products.** A display that cannot do
HDR produced a row reading `HDR   Unsupported` that the D-pad landed on
normally, and pressing A did **nothing at all** — no message, no error. XFE
reached that by an explicit `case "none": return`, standalone by falling through
its activate switch with no case. Same result, two routes, and neither told the
user anything.

Now: the wording is **`Not Supported`** in both, and `QuickMenuMoveSelection`
steps over inert rows instead of stopping on them. Six rows are inert in each
product — HDR, resolution and scale when the display cannot report them, the
empty task list, and the two RTSS-absent rows.

**`QuickMenuMoveSelection` is in `SteamShell-Shared.ahk`, behind two seams.** It
was written into both trees first, which was the wrong call in the same pass
that spent its time removing exactly that kind of duplication — the two
differences are seam-shaped, not intent-shaped:

- `QuickMenuNormalizeSelection` puts an out-of-range index back in range.
  Standalone **clamps**, XFE **wraps**. A real, long-standing product difference
  in how the menu feels, and deliberately not unified.
- `QuickMenuRowIsInert` answers "does this row do anything?" from whatever each
  tree's row model can answer it with — standalone from a list of row ids
  because its rows carry no action field, XFE from `action = "none"`. The two
  sets are deliberately the same six rows.

Between them sits the part worth writing once: a loop bounded by the row count
that restores the original selection when every row is inert, which is the only
reason a page of nothing but status rows terminates instead of spinning at a
boundary.

Verified by exhausting every possible layout of 1–7 rows, both directions, both
movers: **movement from a usable row never lands on an inert one, always
terminates, and always stays in range.** The first version of that test asserted
something stronger and wrong — that the result is never inert *at all* — which
fails whenever the selection already sat on an inert row and clamping cannot
move it. The code was right and the test was wrong.

**HDR: a divergence that was recorded for years and could not run.**

`ToggleQuickMenuHdrState` differed by one line — standalone sent the blind
`Win+Alt+B` chord when DisplayConfig could not report Advanced Color state, XFE
reported Unavailable — and `SHARED_FUNCTIONS.txt` recorded it as a deliberate,
well-evidenced product difference.

Tracing it settled the question: **that branch is unreachable from the menu in
both products.** When HDR state cannot be read, both trees build a *different*
row, id `hdrUnavailable`, and that row is display-only in both — standalone
handles it in the value-text switch and in neither the adjust nor the activate
switch, XFE gives it action `"none"`. So a user who cannot read HDR state never
gets an actionable HDR row at all, and the chord could only ever have fired if
the state became unreadable *between* the menu being built and the button being
pressed.

The chord is deleted rather than ported. `RequestHdrToggleFallback` is gone,
`ToggleQuickMenuHdrState` is one shared definition, and standalone gained XFE's
rule forbidding `#!b` — so the shared file cannot reintroduce it for either
product. XFE's original reasoning (0.1.9 drove this row with the chord alone and
no live state) is exactly why the rule was kept rather than relaxed. Standalone's
assertion previously *required* the fallback and now forbids it.

The shared `SetQuickMenuHdrState` also said **"Windows HDR state is unavailable;
use A to toggle"** — advice only standalone's A could honour. It now says only
what is true in both. Worth being accurate about: that message is on the same
near-unreachable path, so this was a correctness fix to shared text rather than
a defect users were hitting.

**Schema 13 aligns cursor and pointer parking.** Both products have the feature
and named it differently throughout — XFE's `ParkYPercent` and standalone's
`MouseParkYPercent` even carried word-for-word the same explanation, which is
how the duplication was noticed. Five keys renamed and moved to standalone's
names and sections: `EnableAutoHide`→`[Features] EnableAutoHideCursor`,
`ParkOnStartup`→`[Features] EnableMouseParkOnBoot`, `HideDelayMs`→`[Timing]
MouseHideDelay`, `ParkEdge`→`[MousePark] MouseParkEdge`,
`ParkYPercent`→`[MousePark] MouseParkYPercent`. The schema 12 migration table
already carried a destination *key* as well as a destination section, so a
rename needed no new machinery.

`ParkOnGameStart`, `ParkOnSteamReturn` and `ForegroundPollMs` stay in
`[Cursor]`: standalone's `EnableMouseParkOnFocusChange` parks on any focus
change it causes, which is a different rule from "Steam came back to the front",
not a differently-named version of it. Standalone's sample also now documents
`[StartupPrograms] StaggerMs`, which it has always read and never listed.

**Two validator assertions needed follow-up**, both found by replay rather than
by reasoning. One pinned `ControllerMouseSafetyTick` against `$rawSource` — the
*unresolved* tree — so moving the function into the shared file correctly broke
it; it now uses `$source`, while the two assertions either side of it stay on
`$rawSource` because arming the watchdog is a per-tree property. The other still
expected `^ParkEdge=right$`. **941 assertions replay clean.**

**Not done, and why.** Standalone has no RawInput backend and no Steam View
button tap/hold actions; XFE has both, and the intent applies to the shell
identically — a controller in DirectInput mode is invisible to XInput in either
product. Those are feature ports rather than consolidation and are recorded in
`XFE_PARITY_NOTES.md` as such. `PollController` (0.26 similar),
`QuickMenuActivateSelected` (0.34) and `LoadControllerMappings` (0.24) remain
genuinely different and are the reason there are two programs.

## Unreleased — XFE settings: a reader that survives being documented

**XFE's INI could not carry comments, so it did not have any.** Its four typed
readers took the value as everything after the `=`. `EnableAutoMouseMode=true  ;
note` was therefore read as the string `true  ; note`, which is not `true`, so
the setting came back off. With **45 settings in this tree defaulting to on**,
documenting the file would have switched them off one at a time.

That is the whole reason the two samples looked so different: standalone
documents **122 of its 174** settings and XFE documented **3 of 104**. It was
never a writing job nobody got round to. Three of the three comments XFE did
carry were misbehaving — `AccentColor=Purple  ; Steam Blue|Blue|...` resolved
the colour correctly by falling back, then stored the whole comment string as
the accent *name* and displayed it in the Quick Menu.

Three changes, in the order they had to happen:

**1. One `CleanIniValue`, in `SteamShell-Common.ahk`.** All three programs had
their own comment-stripping: standalone's was complete, the helper's was a
near-copy, and XFE had none. It is now defined once, in the file every program
compiles, and XFE's `ReadText`/`ReadBool`/`ReadInt`/`ReadNumber` all route
through it. `ReadBool` also now returns its **fallback** for an unrecognised
value instead of a hardcoded `false` — the old behaviour turned any typo, any
stray comment, into a silent opt-out of a feature that defaults to on. The
helper's reader had always done this correctly; XFE's now matches it.

**2. All 104 settings documented**, reusing standalone's existing wording
verbatim for the 38 settings that exist in both under the same name, so the two
files read identically where they describe the same thing. `[ControllerMap]`
gained the block header standalone has, extended with XFE's actual builtin
action list. Verified mechanically: every one of the 104 values parses to
exactly its intended value through the new reader, and **46 of them would have
been misparsed by the old one**.

**3. Schema 12 aligns section placement.** Six keys moved so that a setting
shared with standalone is found in the same section in both:
`EnableAutoMouseMode` from `[Controller]` to `[Features]`, and `CooldownSec`,
`GracefulCloseMs`, `HardKill`, `RequireNoGame`, `LauncherProcesses` from
`[Assist]` to `[LauncherCleanup]`. Migration runs before defaults are filled in
— the other order writes the default into the new location and strands the
user's own value in the old one. Only same-name settings moved; XFE's assist
tuning that standalone names differently stayed put, because moving a
differently-named setting into a shared section makes it no easier to find while
still invalidating every existing file.

Six `$sample` assertions in XFE's validator anchored on `^Key=value$` and broke
the moment the sample carried comments. They now use `(?:\s*;.*)?$` — the idiom
standalone's validator has always needed for exactly this reason. **941
validator assertions replayed clean afterwards.**

**Worth recording as a near miss.** The section move was applied to the source
with a blanket text replace, which also rewrote the migration table's own first
entry into `["Features", ..., "Features", ...]` — a self-move. That would have
left `EnableAutoMouseMode` stranded in `[Controller]` while `[Features]` took the
default, silently switching automatic mouse mode back **on** for anyone who had
turned it off. Caught by reading the table back rather than by any check, which
is the same lesson this changelog keeps recording: a mechanical edit needs its
result inspected, not just its exit status.

## Unreleased — audit fixes: one answer per question, and checks that can fail

Six defects, found by auditing the working tree rather than by any check. Four
of them were sitting behind a check that was written to catch exactly that
defect and structurally could not.

**XFE never read a RawInput device path, on any machine, ever.**
`buffer := Buffer(...)` in `RawInputDeviceKey` and `RawInputDeviceName`. Locals
are case-insensitive, so the constructor resolved to the unassigned local and
threw — into a bare `try` with no `catch`, so it was silent. Consequences, none
of them visibly a crash: the `&MI_`/`&Col` suffixes that separate the collections
of a **composite** gamepad were never appended, so every collection of one
physical device collapsed onto a single profile key; the `DEV_` checksum
fallback was unreachable; and every learned profile recorded an empty `Name`.
The once-per-device diagnostic then printed `chars=<n> path='(none)'`, which
reads as a driver returning a size and no path and sent two investigations at
the HID stack. It now carries `pathError=` as well.

**The check for that bug compared locals against functions defined in this
project.** `Buffer` is a *built-in* class, defined in none of these files, so it
was never in the lookup. `Assert-AhkStructure` now works per function and asks
whether a name is both assigned as a local and called as `name(` in the same
body — which needs no list of builtin names to maintain, and does not fail on
ordinary locals like `send := SubStr(v, 6)` that shadow nothing anyone calls
there. Mutation-tested: clean on the fixed tree, two hits on the bug restored.

**Seven functions were invisible to every structural check.**
`Get-AhkFunctionBodies` required the whole header on one line, and seven real
definitions wrap their parameter lists — including
`CreateProcessWithStandardToken` and `LaunchInteractiveApp`, which is to say the
privilege boundary was the least-checked code in the tree. They were exempt from
the duplicate scan, the shadow scan, the manifest scans and the cross-tree
reachability check. The parser now accumulates a wrapped header until its
parentheses balance, counting them in code only so a default value or a trailing
comment cannot unbalance a well-formed one. Column-zero *calls* in the
auto-execute section are still not definitions, told apart by the only thing
that distinguishes them: a definition's header is followed by `{`.

**Reachability was checked in one direction out of four.** It asked only whether
XFE or the helper called something defined solely in `SteamShell.ahk`. It now
enumerates what each program compiles and checks all three against every file
they do not, which closes main calling into the helper, either tree calling the
other's private functions, and the helper reaching into `SteamShell-Shared.ahk`.
An unresolved call is a **load-time** failure in AutoHotkey, and `/Validate`
reports it in a modal dialog — so the harness hangs with no output at all.

**Main and the helper each decided whether the controller was a mouse, and could
not agree.** The real answer depends on `DesktopMode`, which the helper cannot
observe, so what stood in for it there was a hardcoded list of four executable
names. In desktop mode this tree answers "everything except the exclusion list".
For **every elevated window outside those four** — an elevated installer,
`regedit`, an elevated console — main ran automatic mouse mode and the helper did
not: the user got the five normal-integrity builtins main keeps (touch keyboard,
on-screen keyboard, Explorer, Quick Menu, Control Panel) and no cursor movement,
no scrolling and no click to use them with. `AutoMouseModeActive()` is now
authoritative and published on a manual-reset event, exactly like the geometry
event; the helper reads it and ORs in the physical View/Back it reads itself, so
a held button still works if the event never arrives. Five settings the helper
re-derived it from are no longer read there — a second copy is what let them
disagree.

**Four of five helper refusals never signalled completion.** The comment above
them said every exit did. Main waits 3000 ms with `Critical` on, so each refusal
was a three-second freeze of the Windows shell, once per button press; the
reachable case is the up-to-one-second window where main and the helper disagree
about `EnableElevatedFrameCapWrites`. The whole body is now inside the `try`,
and the assertion pins that the `try` opens *before the first refusal* rather
than pinning the one path that already worked.

**A completion could satisfy the wrong request.** Resetting the completion event
before issuing a request cannot cancel a completion that arrives *after* the
reset: a request that timed out at three seconds and finished a moment later
signalled the next request's wait, so main resumed reading RTSS while the helper
was mid-sequence — the exact interleaving the event exists to prevent — and
reported a write that was about to succeed as a failure. The helper now records
which request finished in `[Result] Seq` before signalling, and the wait keeps
waiting when the answer belongs to somebody else.

**Smaller, same shape.** `CommitIniChanges` returned `false` for a reentrant call
with no log line, so a dropped write was indistinguishable from a failed one;
staging files left by a killed process are now swept at startup, keyed on a PID
that is no longer running. Section 5b of the harness listed `"exit code"` among
the phrases that prove a build rejected *this* fault — and every throw in
`Build-SteamShell.ps1` that reaches a validator or the compiler carries it, which
collapsed the test back to "it threw". The two ends of the elevated RTSS channel
and of the automatic-mouse event are literals in files that share no code; all
four are now pinned against each other.

**941 validator assertions were replayed offline** against the include-resolved
sources before any of this was handed over, with PowerShell's case-insensitive
`-match` semantics and its ANSI decoding reproduced. None of it has run on
Windows. See `WINDOWS_TEST_CHECKLIST.md`.

**`POST_1.9.9_STATUS.md` has been retired.** It had become a second source of
truth and had already drifted: it described `SteamShell-Shared.ahk` as 1,739
lines and 78 functions when the file was 1,463 and 54, claimed 77 shared
functions against an actual 54, put the XFE settings schema at 10 in its summary
table while a later section of the same document said 11, and called the helper
955 lines when it was over 1,500. Its content lives in `CHANGELOG.md`, the two
READMEs, `XFE_PARITY_NOTES.md` and the two test checklists, which are the files
that own it. Three things existed nowhere else and were moved rather than lost:
the measured *merging the runtimes* decision to `XFE_PARITY_NOTES.md`, the
UTF-8 BOM encoding landmine into `Validate-Common.ps1` where it actually bites,
and the shelved unbounded-pattern work, recorded below.

**Still on the shelf: unbounded `(?s).*?` validator patterns — re-measured, and
the number that matters is zero.**

Two different populations had been conflated, which is part of why this never
started. Separating them:

| | standalone | XFE |
|---|---|---|
| anchored on `^Function(` with a lazy gap, **capable** of running past the end | 117 | 4 |
| **actually** matching past the end of that function today | **0** | **0** |

Every one of the 121 currently matches entirely inside the function it names.
So this is **purely preventive work with no present defect behind it**, which is
the honest reason it keeps being deferred and also the reason it is safe to do
incrementally: bounding a pattern that already matches within the body cannot
change what the validators accept or reject today.

The risk is prospective and has been realised exactly once: when a body changes,
an unbounded pattern can silently start matching something *else* rather than
failing. That is the Frame Limit `wrap` parameter — the pattern matched the call
site in `QuickMenuAdjustSelected` and ran on into the definition from there, so
adding a parameter to the function it named did not disturb it. Bounded since.

A further **117 standalone / 110 XFE** lazy patterns are *not* anchored on a
function definition at all: they are the deliberate cross-file ordering checks,
they are meant to span, and they must not be bounded. Any batch pass has to
classify before it edits, which is the work.

The edit itself is mechanical — `(?:(?!\n\})[\s\S])*?` — but a blunt pass over
these validators has already caused three build failures in a row, and each
batch needs mutation-testing on Windows because this workspace cannot run
PowerShell. That round trip, not the edit, is the cost.

**Superseded figures:** an earlier note recorded "40, of which 39 remain" and
"73 deliberate". Those came from a narrower and undocumented definition of
"names a function"; the table above states its own.

## Unreleased — one shared definition, all three programs

**No UAC prompt on any installation mode.**

A UAC consent dialog runs on the **secure desktop**, where no process can inject
input — not SteamShell, not the helper. On a handheld with only a controller
that is not an annoyance, it is unanswerable: the user has to find a keyboard.

The prompt existed because Portable and Custom were refused the protected
on-demand task, and they were refused it because the helper sat beside the
executable — in a folder the interactive user holds Modify on, which includes
`FILE_DELETE_CHILD`. That lets a non-administrator delete the hardened `bin`
*despite* its own ACL, recreate it, and point `schtasks /run` at their own
binary. A task is an unprompted elevation to whatever sits at its action path.

**The binary carries no user state**, so nothing about it needs to travel with a
portable install. It now goes to `%ProgramFiles%\SteamShell\bin`, which is what
XFE already did, and the task gate became the actual security property:

```
taskEligible := ElevatedHelperLocationIsProtected(ElevatedHelperPath, &err)
```

Custom-under-Program-Files stops prompting as a side effect, and the check fails
closed.

**Portable keeps a real choice, decided by evidence.** Setup tests the folder
with `SteamShellPathIsAdminOnlyWritable`. If the user put it somewhere
non-administrators cannot write, the helper stays beside the executable, the
task is registered, and nothing is traded or asked. Only when the folder *is*
user-writable is there a decision, and then it is offered with the actual reason
named. The answer is recorded in `[Setup] PortableHelperLocation` rather than
re-derived, so permissions changing later cannot move the helper out from under
a task already registered against the old path.

**XFE gets the same task**, registered lazily the first time the RTSS opt-in is
used rather than at install, so a machine that never enables it never carries a
`HighestAvailable` entry.

A task and `*RunAs` produce an identical token for an administrator. What the
task changes is the prompt — and the standard-user case, which today can only
"succeed" by starting the helper as a *different* user, which the helper
correctly refuses. It now degrades cleanly instead.

**Uninstall reaches all of it.** Both helper locations are offered in every mode,
derived from the *resolved install directory* rather than `A_ScriptDir` — an
uninstall is routinely driven by a freshly downloaded `SteamShell.exe` whose
`A_ScriptDir` is the Downloads folder. Both were also being rejected by
`SteamShellRemovableDirectoryKind` as "not a folder SteamShell created", which
would have left an administrator-owned directory the user cannot delete
themselves; all three helper paths are recognised now.

**XFE's task switcher lost Steam, and the exception was in the wrong place.**

Steam Big Picture vanished from the switcher under Xbox FSE. There was already
an exception for the tool-window rule — Steam publishes a titled, full-sized
window as `WS_EX_TOOLWINDOW` without `WS_EX_APPWINDOW` — but it sat at the END of
the filter chain, and three earlier gates rejected Steam before it was reached:
**cloaked** (Windows cloaks Steam while FSE owns the screen, which is exactly
when you want to switch to it), **empty title**, and **minimum size**. Steam is
resolved first now and exempt from all four. The shell's own filter is untouched;
it never hit this because Xbox FSE is not running there, so Steam is never
cloaked — same rule, different world.

**Startup programs: two implementations, each missing what the other had.**

Policy shared in `SteamShell-Common.ahk`; the launch primitive stays per-tree,
because the shell must de-elevate through its verified path where the companion
uses a plain `Run`.

| | shell had | companion had |
|---|---|---|
| Command-line arguments | yes | **no** — `FileExist` rejected any entry with args |
| Stagger between launches | **no** | yes |
| Skip if already running | **no** | yes |
| Window-mode enforcement | one shot at +200 ms, `Hidden` only | 6 s sweep, all modes |
| Slots | **20** (the editor offered 40) | 40 |

So `Minimized` was a setting the shell saved and never applied, and entries 21–40
were accepted and never launched.


**The XFE logon task was registered by both programs, under two names.**

Setup Assistant created **`SteamShell XFE Companion`** with **no logon delay**;
XFE's own *Settings → Advanced → Create Logon Task* created **`SteamShell-XFE`**
with a **10-second delay**. Different names means different tasks, and four
things followed:

- After a Setup install, **Check Logon Task** queried the companion's own name,
  found nothing, and reported that no task was registered — while one was.
- Pressing **Create Logon Task** then registered a *second* task, so **two
  companions started at sign-in**.
- **Remove Logon Task** deleted only the companion's own. Setup's survived, so
  "removed" did not remove.
- `README-XFE.md` documents a 10-second logon delay to let the shell and Xbox FSE
  come up first. Setup's task had none — and this release made Setup the
  recommended route, so the documented behaviour was false for most installs.

One name (`SteamShell XFE Companion`, matching `SteamShell Elevated Input
Helper`) and one XML, both in `SteamShell-Common.ahk`. The XML kept is the
companion's, because its differences are the ones with stated reasons: the logon
delay, `AllowHardTerminate=false`, and an element order copied from a real Task
Scheduler export because the schema rejects rearrangement with an unhelpful
error.

Both routes now delete the legacy name when registering or removing, so a machine
that has been through either converges on one task. Uninstall clears both.

The account is resolved as a **SID** in both, which survives a user rename;
the companion previously used `DOMAIN\User` and falls back to it only if the SID
cannot be read.

**`XmlEscape` and `XmlEscapeText` were the same function under two names**, and
the companion's escaped four entities where the shell's escaped five — the
apostrophe was missing, which a user name containing one would have exposed. One
definition now, in Common.


**Four RTSS control fixes, found by laying the two programs side by side.**

Comparing the trees turned up three suspected gaps. **Two were my misreading** —
the companion *does* gate on `EnableRTSSIntegration` and *does* check the
shortcut is configured; both checks live inside its `SendRtssShortcut` helper
rather than inline, and a token diff showed "relocated" as "missing". Reading the
code settled it. What survived was one real gap and three found on the way:

- **Selecting a state RTSS already holds said nothing.** In the shell,
  `SetRtssOverlayState` and `SetRtssFrameLimiterState` applied the change only
  when it differed and otherwise returned in silence — no toast, nothing. On a
  couch UI with no keyboard, "nothing happened" is indistinguishable from "this
  is broken". Both now report *"RTSS overlay is already on"*, as the companion
  already did.
- **`ToggleRtssOverlay` launched RTSS before checking the shortcut.** Three of
  the shell's four fallback paths asked *is the shortcut configured?* before
  *is RTSS running?*; this one asked the other way round, so a user with no
  `OverlayToggleShortcut` got RTSS started for them and was then told they could
  not use it.
- **A no-op press wrote the settings file.** `SetRtssFrameLimiterState` fell
  through to `PersistRtssFrameCapStateNow` even when the limiter already matched
  and nothing had been applied.
- **The companion did not say WHICH shortcut to configure.** It said "Configure
  the RTSS shortcut in Settings first" where six such settings exist. It now
  names the one that is blank, as the shell always did.

**The shell gained the companion's `SendRtssShortcut` helper**, which is what
allowed the ordering drift in the first place: four hand-written copies of the
same three checks, and one of the four wrong. Now one copy, and the order is
asserted — with a `-notmatch` that specifically forbids `EnsureRtssRunning`
reappearing inside `ToggleRtssOverlay`.

The two helpers are **deliberately not shared**. They call `EnsureRtssRunning`,
which genuinely differs — the shell launches through its verified-launch path,
the companion through a plain `Run`. Sixteen duplicated lines is the cheaper
price than a sixth callback out of the shared file, which had just come down
from eight to five.


**The display stack and four RTSS reads were duplicated. They are not now — and
unifying them fixed five real gaps.**

Of 103 functions defined in both trees, exactly one was byte-identical. The
interesting ones were *near*-identical, and a token-level diff separated
accidental drift from deliberate divergence.

**Accidental (now one definition):** the whole primary-display stack. Eight pure
Windows API functions moved to `SteamShell-Common.ahk` — all three programs —
and fifteen selection/state functions to `SteamShell-Shared.ahk`, along with
`GetRtssFrameLimit`, `GetRtssGlobalState`, `AdjustRtssCustomFrameCap` and
`ResolveRtssExecutablePath`.

**What the merge fixed, rather than merely deduplicated:**

- **`ResolveRtssExecutablePath` — the shell could not find a stock RTSS install.**
  The companion falls back to `%ProgramFiles(x86)%\RivaTuner Statistics Server`
  when `[RTSS] Path` is unset; the shell did not, so an ordinary RTSS install
  reported "RTSS was not found at the configured path" on every row. The shell
  now has the fallback.
- **...and the companion could not expand `%VAR%` in `[RTSS] Path`.** Its own
  path normaliser only trimmed quotes; the shell's also expands environment
  variables and resolves relative paths. The more capable one won, so each
  program gained the other's half.
- **Three failures were logged without a severity** in the shell
  (`ApplyPrimaryDisplayScale`, `ApplyPrimaryHdrState`, `GetRtssGlobalState`)
  where the companion logged them as warnings.
- **`GetPrimaryDisplayScale` lost two diagnostic paths** in the shell that the
  companion had — an unavailable DisplayConfig source and an unsupported range
  now say so once instead of failing silently.
- **The Apply row read `Select To Apply` in one and `Select to apply` in the
  other.** Both now read `Select To Apply`, pinned in both validators.

**Deliberate divergence, left alone.** The rest of RTSS stays per-tree, and the
reasons are load-bearing: `EnsureRtssRunning` launches through the shell's
verified-launch path versus a plain `Run`; profile targeting reads two different
game-detection engines; the companion wraps every write in
`EnsureElevatedRtssHelperAlive` because its helper is opt-in and on demand; and
`PersistRtssCustomFrameCap` stages through `CommitIniChanges` because a
half-written settings file in the Windows shell is a machine that signs in to
nothing.

**One new seam, and the old one shrank.** `SharedNotify(message, kind)` routes
shared code to whichever surface a program has — a toast in the shell, the status
line in the companion. With the API half moved into Common, the shared file's
callbacks into the trees went from **eight to five**, and Common's is enforced as
an allowlist of exactly one (`LogLine`) — the check enumerates every call leaving
the file, which is what `SteamShell-Shared.ahk` never had and why it grew to
eight unnoticed.


**Hold to drag — `Builtin:LeftClick` is now press-and-hold, in all three programs.**

Hold the button bound to Left click (right bumper by default), move the right
stick, release. A tap still produces an ordinary click, so nothing is lost for
the common case and no new configuration exists.

**Left click only.** Nobody drags with the right button, and leaving it atomic
halves the surface of a change whose worst failure is a mouse button stuck down.
The rule follows the *binding*, not the button, so moving Left click to another
button moves drag with it.

**The change is in the poll loops, not in the binding executors** — and that is
the whole design. `ExecuteControllerBinding` has press-only callers: standalone's
Settings pointer fires `RB.Short` on press with nothing that will ever see the
release. A button-down issued there would never be lifted, inside the Settings
window, which is the one place a user has no other pointer. A `-notmatch` in both
validators keeps `HoldControllerMouseButton` out of those functions.

**The Short/Long conflict is made unreachable, not explained.** A button whose
Short is Left click cannot have a Long: Short resolves on *release*, and holding
is the point. Standalone's editor disables the Long combo, its Record and Clear
buttons, and shows *"Reserved for mouse: hold RB to drag."*; the list's Long
column reads *Reserved for mouse (hold to drag)*. XFE's editor is a flat key
list, so the matching `.Long` row shows the same text and **refuses to be set**,
by built-in or by recorded shortcut. Defaults ship `RB.Long=Builtin:None`, so
nothing breaks for anyone who never changed it.

Triggers are covered as well as buttons, in all three, because the rule is about
the binding rather than about a particular input.


**The hold-to-drag safety machinery, shipped inert.**

Nothing presses a mouse button yet. This step builds only the part that has to
be right before anything does, so the plumbing can be proven on a build where a
mistake cannot manifest.

`SteamShell-Common.ahk` gains a ledger of synthetic mouse buttons the process is
holding, plus `HoldControllerMouseButton`, `ReleaseControllerMouseButtons` and
`ExpireControllerMouseButtons`. The ledger is a **static inside a function**
rather than a global, because that file may not declare globals — the invariant
that lets the helper include it at all.

Three properties are asserted rather than reviewed:

- **Release is wired into the reset seam**, not into call sites. Every abort path
  already calls `ResetControllerEdgeState`, which is exactly the set of places a
  held button must not survive — and is the reason standalone's seven
  hand-copied reset blocks were collapsed into one body first.
- **The ledger entry is deleted before the `SendInput`.** A throw inside
  `SendInput` would otherwise leave a name recorded as held forever and turn
  every later release into a no-op. Releasing a button that was not down is
  harmless; believing one is held when nothing will release it is not.
- **The watchdog is armed at top level and never disarmed**, on a timer
  independent of the controller poll. The first placement put it inside
  `ApplyRuntimeTimers`, which stops every timer and re-arms what the current mode
  wants — so it would have been cancelled exactly when the poll loop was
  cancelled, which is the case it exists to cover. XFE's first placement sat
  below an early return for a disabled companion, with the same effect. Both are
  now unconditional, and a `-notmatch` forbids the `ApplyRuntimeTimers` placement
  coming back.

**Standalone and XFE gained `OnError` handlers.** Only the helper had one, added
after a shadowed local put AutoHotkey's own error dialog on the shell desktop.
The same exposure was always present in both trees and is worse once a button can
be held: an uncaught throw would leave it down behind a modal dialog on a desktop
that may have no taskbar. Both handlers release first, then log, then let
AutoHotkey proceed as before.


**The controller-as-mouse arithmetic existed five times.**

Not three — five. Once in each program's poll loop, plus a fourth and fifth copy
on the Settings pointer surfaces of the two trees. Identical in every one: the
same `Round((stick / 32767.0) * speed)`, the same negated Y, the same
`MouseMove(dx, dy, 0, "R")`, the same wheel loop.

`SteamShell-Common.ahk` now defines `ApplyControllerMouseMove`,
`ApplyControllerMouseScroll` and `ResetControllerEdgeState`. The three programs
read three different input sources — XInput, RawInput through learned profiles,
and XInput from a High-integrity token — and that is why they are three
programs. What they did with the *result* was never different.

What deliberately stayed with the callers: the speed choice including the
fast-modifier trigger, the scroll rate limit, and the gating. Those genuinely
differ, and the Settings surfaces differ again — no fast modifier, because the
triggers change category there, and one wheel notch per tick rather than
`ControllerScrollStep`, because a Settings list is short.

The per-tree edge scalars also stayed at their call sites. Standalone clears
`prevViewDown` everywhere; XFE clears `previousViewDown` and `viewWasDown` at
some sites and neither at others; the helper clears `previousButtons`. Folding
any of them into the shared body would have changed behaviour at the sites that
deliberately do not reset them — so standalone keeps a two-line wrapper, and the
other two call the shared body directly.

The pin that matters is a `-notmatch`: `32767.0` may not appear in any tree or
in the helper. A sixth copy would have to contain it.


**The helper stopped carrying its own copy of the token walk.**

`ProcessIntegrityRid` (38 lines) and `GetProcessIdentity` (62) are gone from
`SteamShell-Helper.ahk`. Both were second implementations of SID, session and
integrity-level parsing that `GetProcessTokenSecurity` already did, now reachable
through `SteamShell-Common.ahk`. The helper source drops from 1,580 to 1,504
lines, and the duplicated copy was the one inside the binary that runs with a
High-integrity token.

The consolidation is worth more than the line count. Main and the helper both
answer *"is the foreground elevated?"*, and that question is how they agree which
of them owns the controller — disagree, and a window is serviced twice or not at
all. They were answering it **differently**: main compared integrity *names*, the
helper tested the raw RID against `0x3000`. The two agreed only because
`GetProcessTokenSecurity` maps `0x3000..0x3FFF` to High and `>= 0x4000` to
System. Agreement by coincidence is not a property anyone was maintaining. The
helper now wraps the shared function in `ProcessIsElevatedIntegrity` and applies
the same `High || System` test main does, pinned by an assertion that reads both
sides plus the RID mapping itself.

`ReadInt` and `ReadFloat` keep their own `Min(Max(...))` clamping rather than
switching to `ClampInt`/`ClampFloat`. It is the identical expression in builtins,
so changing it would be churn — the duplication worth removing was the hundred
lines of token parsing, not the arithmetic.

**Two harness faults found by the first build of this work.**

- A stale assertion still read the reset as `downTick[def[1]] := 0` and stopped
  matching once the seven hand-copied blocks became one call. It was also one of
  the unbounded `(?s).*?` patterns, scanning the whole file from the branch
  rather than the branch itself. Rewritten bounded to the branch and naming the
  call, and mutation-tested.
- **Every negative test reported PASS while testing nothing.** `Assert-True`
  throws, so with one assertion already failing the build rejected each broken
  copy for the original reason. Sections 5b/5c now require a green baseline
  before running at all, and require the failure to be *about the fault they
  injected*. (Detail was in `POST_1.9.9_STATUS.md`, since retired; the surviving
  account is in the post-1.9.9 audit entry at the top of this file.)

All 759 `$source` patterns across both validators are now reproduced offline
against the include-resolved sources before anything is handed over — matching
PowerShell's case-insensitive `-match`, which an earlier version of that check
got wrong.

`SteamShell-Shared.ahk` was included by the two trees and **not** by
`SteamShell-Helper.exe`, so the helper carried its own copy of anything it
needed. The question was why that had to be true. It did not.

**The measurement.** Of 78 functions in the shared file, **39 are entirely
self-contained** — no globals, and calling nothing outside themselves — and 39
orchestrate tree state. That is close to an even split, and it is the finding:
half of what looked shareable is genuinely coupled to RTSS, the Quick Menu and
the elevated-helper lifecycle, and half is not coupled to anything.

**Why the helper could not simply include it.** Not the globals — unused
functions with unset globals are inert. The blocker is that the shared file
calls **eight** functions that live only in the trees (`ApplyRtssGlobalState`,
`ElevatedRtssRequestPath`, `GetRtssFrameLimit`, `GetPrimaryDisplayScale`,
`QuickMenuBuildGui`, `VerifyElevatedHelperProcess`, plus the documented
`LogLine` and `SharedPersistSettings`). AutoHotkey resolves a call to an
undefined function at **load time** and `#Include` is all-or-nothing, so
including it in the helper is a compile failure, not a subtle risk.

Worth stating plainly: the file **documented a two-function seam and had grown
to eight**, and nothing noticed, because the validator only ever pinned the two
it named.

**The split.** `SteamShell-Common.ahk` now holds the 39 self-contained functions
and is `#Include`d by **all three** programs. `SteamShell-Shared.ahk` keeps the
tree-coupled 39 and stays with the two trees.

The invariant that makes it work is mechanical, not a convention:

> Nothing in `SteamShell-Common.ahk` may declare a global, or call or reference
> any function not defined in that file or built in to AutoHotkey.

`Assert-SharedParity` now enforces it directly — zero `global` declarations,
zero references into the coupled half — alongside a second manifest
(`COMMON_FUNCTIONS.txt`), a shadowing check across all four files, an assertion
that **all three** programs include it, and one that the helper does **not**
include the coupled half. Both shared files were added to the harness's negative
tests, so breaking either has to fail the build.

Nothing moved changed. Verified mechanically: no name collides across the four
files, the common half references nothing in the coupled half, both manifests
match their files exactly, and braces balance in both.

## Unreleased — Setup could not replace a file that was running

**Fixed, and it was not an upgrade inconvenience — it was a hard blocker.**

Reported as "launching SteamShell.exe for the first time to run Setup Assistant
doesn't close SteamShell-XFE.exe, so the process fails". Confirmed, and broader
than reported.

`ExtractEmbeddedXfe` ends in `FileMove(stagedPath, targetPath, true)` over
`SteamShell-XFE.exe`. Windows holds an exclusive write lock on a running image,
so that is a sharing violation. Nothing anywhere stopped the companion first —
there was no `ProcessClose` for XFE in the entire setup path.

Three things made it worse than an edge case:

- `DeploySteamShellXfe` calls it with `forceReplace := true`, so even a
  same-version re-apply attempts the overwrite. XFE's logon task starts the
  companion at sign-in, so on an XFE machine **Setup could essentially never
  apply** — not merely that upgrading was awkward.
- **The same bug existed for the elevated helper**, in both deployment paths.
  `StopElevatedInputHelper` was only ever reached from
  `SyncElevatedInputHelperWithSettings`, never from Setup.
- **And for uninstall**, where it was quieter: a resident companion or helper
  made `DirDelete` fail partway, leaving a half-removed installation reported as
  a list of failures.

### What was already there, and why it did not help

`CloseExistingSteamShellInstancesForElevatedSetup` had closed `SteamShell.exe`
and `SteamShell-Helper.exe` since the elevated-takeover work, identity-checked
and graceful. **`SteamShell-XFE.exe` was simply not in the list** — the one
executable that is running on every configured XFE machine. It is now.

### The fix

`StopRunningSteamShellExecutable(path)` runs before every in-place replace, in
this order:

1. **Identity before anything is closed.** Only a process whose image path is
   exactly the target counts, and it must belong to the interactive user in this
   session. A process carrying the right path with the wrong owner **stops the
   install** rather than being terminated — Setup replacing a file is not a
   licence to kill processes it cannot account for.
2. **WM_CLOSE first.** It delegates to `CloseSteamShellProcessForSetup`, which
   posts to the script's *hidden* main window with `DetectHiddenWindows`
   enabled. An open-coded `WinClose` would have found nothing and silently
   always terminated — XFE keeps its INI, learned controller profiles and log
   beside its executable, so a hard kill mid-write is not the opening move.
3. **Wait for the lock, not for the process.** `WaitForReplaceableFile` probes
   by opening the file for write, because a handle can outlive the process by a
   moment and a fixed `Sleep` is a guess.

For both helper paths the stop happens **before the directory is hardened**, not
after: hardening a locked file secures a directory around a stale binary.

A companion Setup stopped is restarted afterwards, through Explorer's desktop
automation object rather than `Run` — this process is elevated, and a child of
it would inherit an administrator token. An accidentally elevated XFE is the one
outcome its whole architecture exists to avoid. The result dialog says what
happened, and only when something was actually stopped.

**No `MOVEFILE_DELAY_UNTIL_REBOOT` fallback.** Deferring silently to a reboot
would report success for an install that has not happened, which is a failure
mode this project has already been bitten by twice.

### The error message was part of the bug

`DescribeFileFailure` named only Win32 5. A sharing violation is Win32 **32**,
so the single most likely deployment failure rendered as a bare `[Win32 32]` —
naming neither the cause nor the remedy, which is how two sessions were spent
reading it as a payload problem. 32, 33 and 1224 are now named.

### Verified

Eleven new assertions, of which the ordering ones are the point: each stop must
appear **before** the operation it protects. Four were mutation-tested —
removing the companion stop, moving the helper stop after the harden, restarting
with `Run` instead of the desktop shell, and dropping the Win32 32 case all fail
the build. **None of this has executed on Windows.**

## Unreleased — from hardware: KEEP, automatic mouse, and a stale instruction

Three reports, all found by using the programs rather than by any assertion.

### Quick Menu KEEP refused presses, in both trees

**Fixed.** After a display change the Apply row reads `Select To KEEP (Ns)` and
a 15-second timer is running to revert. Pressing A on it worked sometimes and
did nothing other times, and when it did nothing the timer ran out and took the
change with it.

The row was right and the handler was wrong. `GetDisplayApplyValue` has always
reported KEEP unconditionally while a change is pending, but
`ApplyDisplaySelection` re-derived the live display state first and confirmed
only if it still equalled the selection. That gave the press four ways to be
refused through no fault of the user:

| Gate | Why it can be false right after a successful change |
|---|---|
| The mode lookup in `QuickMenuDisplayModes` | the driver stops offering the entry |
| `GetPrimaryDisplayMode()` | can fail outright |
| `modeSame` | `EnumDisplaySettings(ENUM_CURRENT_SETTINGS)` reports **59** Hz for a mode enumerated as **60** (59.94) |
| `scaleSame` | `GetPrimaryDisplayScale` goes through `QueryDisplayConfig`, which can return nothing while the topology settles |

The third is the one that produced the reported symptom exactly: it is a
property of the *mode*, so KEEP silently never worked for 59.94 modes and always
worked for the rest.

Keeping is a state operation — discard the saved old mode, stop the timer — and
it is now answered first and without a condition, before any lookup runs. The
toast also stopped saying "Select CURRENT again" and now names the row the user
is looking at. Pinned in both validators with a body-bounded assertion that
fails if the guard, the old refusal message, or a lookup ahead of the pending
check comes back.

### XFE automatic mouse mode: exclusion mode removed (XFE schema 11)

`EnableDesktopAutoMouseMode` and `DesktopAutoMouseExcludeExeList` are gone.
`EnableAutoMouseMode` plus `AutoMouseExeList` is the whole feature, which is
standalone's non-`DesktopMode` behaviour unadapted.

The removed mode was introduced so that neither setting became dead
configuration, and it passed that test. It failed a better one. Standalone picks
between allowlist and blanket exclusion using `DesktopMode`; XFE has none, so
the exclusion list was the stand-in — and it was standing in for **"am I inside
Xbox FSE right now?"**, which Windows exposes no way to ask. What shipped was a
hand-maintained list of another product's process names, defaulting to
`XboxPcApp.exe|GameBar.exe|XboxGameBarWidgets.exe|ShellHost.exe`. A list like
that goes stale silently while wearing a configuration field, which is worse
than not having the feature.

Xbox FSE now needs no exclusion because it is simply never on the allowlist.

`RetireDesktopAutoMouseSettings` deletes both keys from an existing INI and
**logs what changed**, because this narrows behaviour: anyone on the old default
had a pointer in every foreground application and now has one only where they
say so. Asserted in both directions — the allowlist must be there and the
removed mode must not — so reintroducing it has to be deliberate.

### The XFE Settings integration note described a step that now double-starts

**Fixed.** The General page told users to add `SteamShell-XFE.exe` as an AnyFSE
startup application. Setup Assistant registers a per-user logon task when it
installs XFE, so following that produced two companions. The note now carries
only what Setup cannot do — AnyFSE's Home app and its *Exit FSE when Home app
exits* switch — and says plainly not to add the companion to AnyFSE's startup
list. `README-XFE.md`'s recommended configuration was reordered to match; the
logon task is no longer the "alternatively".

### Not fixed here

Controller mouse over **Task Manager** is still reported as dead while it works
over other elevated windows. No code path was found that blocks it, and the
helper's input loop logs nothing at all after its startup line — there is no
record of an elevated foreground being seen, of XInput returning no device, or
of mouse mode engaging. Diagnosing it needs that instrumentation first.

**Hold-to-drag is genuinely absent, in all three trees.** `Builtin:LeftClick`
is an atomic `Click()` fired on button *release* via the Short-press path, so
there is no button-down state and a drag cannot work by construction. Adding it
is straightforward; doing it *safely* is not, and it is deliberately not bundled
here. A stuck `LButton down` in a Winlogon shell replacement is unrecoverable
without a keyboard, so every early-return reset path — around eight in
`PollController` alone — has to force the button up, and a drag that crosses
from a normal window into an elevated one changes which process owns the held
button mid-gesture.

## Unreleased — one folder, one build script, one published executable

Structural only. No runtime behaviour changed; every file that moved kept its
contents.

**One folder.** `SteamShell-XFE/` is gone. Both AutoHotkey trees, the shared
file, its manifest, both validators, the shared scaffolding and the one build
script now live in `SteamShell/`, and nothing in that folder reaches outside it.
Copy the directory and it builds — which is the point: locking a release is a
copy of one directory.

Two files had to be renamed on the way in, because both trees had one:
`README.md` → `README-XFE.md` and `WINDOWS_TEST_CHECKLIST.md` →
`WINDOWS_TEST_CHECKLIST-XFE.md`. `#Include ..\SteamShell-Shared.ahk` became
`#Include SteamShell-Shared.ahk`. The XFE 0.1.x test-source zips moved to
`archive/xfe-test-sources/` so they are not carried into every release copy.

**One build script.** `Build-SteamShell-XFE.ps1` is gone; `Build-SteamShell.ps1`
compiles the helper, then XFE, then `SteamShell.exe` embedding both, and runs
*both* validators first. The `-XfePayloadPath` hand-off the two-script
arrangement needed went with it.

**Two validators, still.** `Validate-Common.ps1` holds `Assert-True`, the
`#Include` resolver, the structural scans and the shared-parity check —
mechanism only. The product rules stayed apart, and that is not tidiness left
undone. XFE forbids `RegWrite(`, `RegDelete(`, `WinMaximize(`,
`SetWinEventHook`, `RestoreExplorerDesktop` and `HideShellTaskbars`; the shell
uses all six, 45 call sites between them. Merged, every architecture assertion
would have to name its own scope, and a mis-scoped rule does not fail — it
silently stops applying. That list is what keeps XFE from growing into a shell.

**One published executable.** `current/` now receives `SteamShell.exe` alone. It
is the installer and the uninstaller for both products, so a loose
`SteamShell-XFE.exe` beside it is not a distributable — it is an invitation to a
hand-copied install with no logon task, no writable companion directory and no
dormant helper. The build still writes one to `dist/` for developing XFE.

**The negative tests got wider, not narrower.** Folding two build scripts into
one could have deleted 5b and 5c's XFE arm. Instead they now iterate over
sources and outputs rather than build scripts: 5b breaks each of the three
sources in turn — `SteamShell-Helper.ahk` was never covered before, and it is
the payload that gets a High-integrity token — and 5c locks both freshness-
checked outputs, the embedded XFE payload and the published installer.

Two silent-skip paths disappeared by construction. The harness no longer has to
remember to copy `SteamShell-Shared.ahk` beside a temp tree, because the tree is
self-contained; and the parity check no longer has a "skipped when the sibling
tree is absent" branch, because a snapshot is the whole folder now. Both of
those had already produced tests that passed for the wrong reason.

**Not done, deliberately:** the two runtimes stay separate binaries. An XFE
change still cannot break the shell, which `XFE_PARITY_NOTES.md` calls the most
valuable safety property this project has, under *Merging the runtimes entirely*.
Folders are not runtimes.


## Unreleased — an opt-in elevated RTSS helper for XFE, and a scrolling XFE Settings window

Validated by `Run-SteamShellValidation.cmd`? **Not yet — see the note at the end
of this entry.** No behaviour below has executed; both `WINDOWS_TEST_CHECKLIST.md`
files carry the manual steps.

`SteamShell-Helper.exe` advances to **1.9.9.4**. XFE settings schema advances to
**10**. `SteamShell.exe` stays at 1.9.9.0 and standalone stays at schema 20.

Two independent pieces of work: the helper, and the Settings window rewrite at
the end of this entry. Nothing in either has executed.

### The decision, stated

The post-1.9.9 audit recommended an XFE helper be built opt-in and default off,
or not at all. `XFE_PARITY_NOTES.md` flagged that recommendation for reassessment
once the helper stopped being about controller input and started owning the RTSS
frame cap, where the cost of not having it is a feature that does not function.

**Built, opt-in, default off — and narrowed to RTSS writes only.**

The reassessment was right that the balance moved, but it moved for one half of
the helper and not the other:

- **The RTSS write has no workaround.** `RTSSHooks64.dll` loads into the calling
  process, so on a stock Program Files install an unelevated XFE can read the cap
  and toggle the limiter flag but cannot set the FPS value or save a per-game
  profile. That is a dead feature, not an inconvenience.
- **Elevated input does have one**, and porting it would have shipped something
  worse than nothing. The helper's input implementation is XInput, and XFE exists
  because XInput is not enough for its users: Xbox FSE withholds background
  XInput, and a controller in DirectInput mode is not an XInput device at all. It
  would have worked only for the people who did not need XFE, while charging
  every XFE user a resident High-integrity process polling a controller.

So `--product=xfe` gets the frame cap and nothing else: no controller input, no
window geometry, no UI. Default off, stated plainly in `README-XFE.md`,
and a UAC prompt at startup when it is on — which is an honest representation of
what was turned on.

### One payload, two products

`SteamShell-Helper.exe` takes a new `--product` argument. Anything that is not
exactly `xfe` is the standalone helper, stated in that direction on purpose: the
failure modes are not symmetric. An XFE helper behaving as standalone merely does
more than it was asked; a standalone helper behaving as XFE silently does no
elevated input at all and watches for the wrong parent process.

The standalone path is deliberately untouched — the input gate sits *after* the
RTSS request service inside `PollController`, so the sequence confirmed working
on hardware runs exactly as before.

### Deployment stays with Setup

XFE has no embedded payload and no administrator rights, so it can never install
or repair the helper. Setup Assistant deploys it in XFE mode to
`%ProgramFiles%\SteamShell-XFE\bin`, **dormant** — deliberately not inside XFE's
own install directory, which Setup makes user-writable so the companion can keep
its INI, learned profiles and log beside its executable. A user-writable parent
can be deleted and recreated whole, which is exactly why standalone refuses to
give its Custom and Portable layouts an independently invokable helper task.

Same ordering as the shell path, for the same reason: harden, replace the payload,
harden **again**, verify. The second pass is not redundant. icacls cannot set the
owner of a file that does not exist yet, and Windows takes a new file's owner from
the creating token, so a freshly extracted helper is owned by the installing
administrator's own SID and the file-level gate would correctly refuse it. An
earlier revision of the shell path ran `/setowner` once, before the payload
existed, and would have failed every install.

XFE gets **no** on-demand `HighestAvailable` task and only ever uses explicit UAC.
A deployment failure is reported, not fatal: the shell needs its helper to reach
elevated windows at all, while XFE needs it only for a cap the user has not asked
for yet.

### Three groups of functions moved into `SteamShell-Shared.ahk`

`XFE_PARITY_NOTES.md` recorded that the elevated-helper functions would never be
shared. That is reversed there rather than quietly deleted, and the line it now
draws is **the gate is shared, deployment is not**:

- `SteamShellPathIsAdminOnlyWritable` / `ElevatedHelperLocationIsProtected` — a
  path and an expected version, owner, DACL and readability. Knows nothing about
  either program.
- `GetProcessTokenSecurity` and the token helpers, `QuoteWindowsCommandLineArg`,
  `StrRepeat` — "same user, same session, High integrity?" is one question.
- The `ElevatedRtss*` request channel. `ElevatedRtssRequestPath()` stays per-tree,
  because that is the only part that genuinely differs.

No new shared file was introduced, so the parity checker, both build scripts and
sections 5b/5c of `Run-SteamShellValidation.ps1` were unchanged by this work.
(All four have since been reorganised — see the single-folder entry above.
`Validate-SharedParity.ps1` is now the parity check inside `Validate-Common.ps1`.)

### XFE's RTSS write paths now mirror standalone exactly

- **Straight to the helper when one exists**, never a local write first. Both
  paths. The helper only exists in an unelevated session, which is the only
  session where `SaveProfile` fails silently — and for per-game profiles trying
  first is actively harmful, because verifying a named profile re-reads the copy
  `SetProfileProperty` just wrote and says yes.
- **`SaveRtssFrameLimitToProfile` had always reported success unconditionally.**
  Every unelevated XFE user had been told their per-game profiles were saving.
  Same root cause standalone fixed; it was still live here. It now reads the
  profile back.
- **The global cap logged "set to N" before proving it.** Moved below the
  read-back.
- A latched `RtssFrameCapWriteBlocked` no longer refuses a per-game save before
  the helper is asked. The two conditions behind `RtssFrameCapWritable` have
  different causes and needed different answers.

### Found in passing

- **A dead Settings control.** XFE's `RTSS.RestoreFrameLimitOnStartup` checkbox
  was registered as a field and neither populated nor saved, so it always drew
  unchecked and clearing it did nothing. Fixed, and a **structural** validator
  assertion now requires every registered field to appear in both
  `SettingsPopulate` and `SaveSettings` — which is what would have caught it.
- **An unanchored `-notmatch` fired on its own explanation.** XFE's validator
  asserted `$source -notmatch 'HighestAvailable'`, and the first comment in the
  tree explaining *why* XFE does not get a `HighestAvailable` task failed the
  build. That is the documented weakness of a bare-word negative assertion,
  observed rather than theorised. The pattern is now anchored to
  `<RunLevel>HighestAvailable</RunLevel>`, which is the rule it was protecting.
- **The old "only schtasks.exe may be elevated" rule could not fail.** Its
  character class excluded the quote character, so `"*RunAs " QuoteWindowsCommandLineArg(path)`
  matched nothing and the rule would have passed while saying nothing about the
  new elevation. Rewritten to enumerate the two permitted forms.

## The XFE Settings window now flows and scrolls

Separate from the helper work above, and applied to `SteamShell-XFE.ahk` only.

Standalone lays its Settings out with `SettingsEditorAdd*` helpers and a flowing
`&y` cursor; XFE positioned every control absolutely. That is why adding a row to
XFE meant re-flowing a page by hand — and why, when automatic mouse mode was
added, its four controls went into a free right-hand column instead of the
position standalone keeps them in.

**Porting the row builders alone was not possible, and the reason is worth
recording.** Flattened into single flowing columns, Controller & Cursor runs to
about 800px and RTSS & Performance to about 800px, against a content area of
410px in a fixed 920×660 window. Standalone only fits because it has a scrolling
viewport. XFE never got one, so the two pages had grown *sideways* instead — the
side-by-side group boxes on the RTSS page are the symptom, not the design.

So the viewport was ported first: positions captured once from the real
controls, per-category scroll offsets, a scrollbar that appears only when a page
needs it, wheel and `WM_VSCROLL` handling, and all control movement batched
behind `WM_SETREDRAW` so thumb tracking cannot leave trails. The left stick
already sends `WheelUp`/`WheelDown` over a Settings surface, so the controller
scrolls the page with no new binding.

Then the pages were rebuilt on flowing builders — `SettingsAddCheckboxRow`,
`AddEditRow`, `AddChoiceRow`, `AddShortcutRow`, `AddPathRow`, `AddNoteRow`,
`AddSectionRow`, `AddButtonRow` — each taking the cursor by reference. Adding a
row costs a line again.

**The four categories that share a name with a standalone category** — General,
Controller & Cursor, RTSS & Performance, Startup Programs — now present the
settings that exist in *both* in standalone's order and wording. The automatic
mouse controls are back in the left column below the parking rows. The other
three pages have no standalone counterpart and are ordered for their own sake,
which is correct: standalone's Startup & Splash, Focus & Windows and Launcher
Cleanup do jobs XFE deliberately leaves to Xbox FSE.

**What deliberately did not change.** Choice lists derive their stored value from
the selected index, so reordering one to match standalone's wording would invert
the setting. `OverlayControlMode`, `FrameLimiterControlMode`, `WindowMode` and
`ParkEdge` keep XFE's order, and an assertion pins it. Numeric fields that
standalone presents as dropdowns (`ControllerIndex`) stay as edits here for the
same reason: the round-trip is a value, not an index, and a cosmetic change is
not worth an off-by-one.

**The Python layout simulation had to be rewritten, not deleted.**
`test_settings_layout_has_no_overlaps` read literal coordinates out of the
source; there are none left. It now simulates the cursor instead, which makes it
cover *every* row rather than only the ones written longhand — and it reads the
columns from `SettingsLayout()` and each builder's advance from that builder's
own `y +=` line, so the simulation cannot drift from the code it checks. Only
the *shape* of each builder is written down in the test.

A runtime `SettingsAuditLayout` was added alongside it, matching standalone's:
it runs once on the real controls before the window is shown, because font and
DPI decide a row's actual size and an overlap can exist that no source-level
check can see.

**Found while porting:** the field round-trip assertion added earlier in this
entry was itself incomplete. It matched `SettingsRegisterField` with a *literal*
category, and the row helpers passed the category as a variable — so it covered
37 of the 61 fields. Anchored on the builder call sites it now covers all 61.

### Two faults the first Windows run found

**A version literal with nothing anchoring it.** Bumping the helper to 1.9.9.4
updated the helper source, `ElevatedHelperExpectedVersion`, the build's own gate
and the version-metadata assertion — and missed a fourth copy, a bare
`$buildScript -match '1\.9\.9\.3'` buried inside a different assertion about
embedding. A correct, consistent tree failed the build with a message about the
helper no longer being compiled.

Two faults in one clause: it did not say which number it was checking, and it
tied that number to nothing. It now reads the version out of the helper's own
`@Ahk2Exe-SetVersion` and requires the build to gate on exactly that string, so
the copy is gone rather than corrected. Same family as the unbounded-regex
weakness on the shelf — an assertion that names something without anchoring to
it.

**`Validate-SharedParity.ps1` earned its keep.** It reported
`WaitForVerifiedElevatedHelper` as having become identical in both trees, which
it had: XFE's copy was written to match standalone's exactly. Moved into
`SteamShell-Shared.ahk` — 78 shared functions. That "candidates to move in"
report is the half of the checker that grows the manifest rather than guarding
it, and this is the first time it has caught a duplicate at the moment it was
created.

### Verification status — read this

Every new assertion in both validators was mutation-tested: the behaviour it
names was broken and the assertion confirmed to fail. That was done with a
regex-equivalent harness, **not** by running PowerShell, because this work was
authored on macOS where neither PowerShell nor AutoHotkey is available.

`Run-SteamShellValidation.cmd` has now been run once on Windows and found the
version-literal fault above. That run reached:

| | Result |
|---|---|
| `SteamShell-Helper.ahk` syntax | PASS |
| `SteamShell-XFE.ahk` syntax | PASS |
| `Validate-SteamShell-XFE.ps1` | PASS |
| `Build-SteamShell-XFE.ps1` | PASS, verified 1.9.9.0 |
| `Validate-SteamShell.ps1` | FAIL — the version literal |
| `Build-SteamShell.ps1` | not reached |
| **`SteamShell.ahk` syntax** | **not reached** |

The last row matters most: standalone's syntax is validated inside its build,
after the freshly compiled helper payload exists, and the build stopped at the
validator. So the largest edits in this entry — the three groups of functions
moved out of `SteamShell.ahk` and the XFE helper deployment inside Setup
Assistant — have **not been parsed by AutoHotkey even once**. The harness must
be re-run.

A passing build still proves nothing about behaviour.

## Unreleased — post-1.9.9 helper hardening

Validated end to end by `Run-SteamShellValidation.cmd` on Windows PowerShell 5.1
with AutoHotkey 2.0.26: syntax, both static validators, both builds, and the
negative tests. Behaviour is a separate question — see `WINDOWS_TEST_CHECKLIST.md`,
since no Setup or runtime path below has executed yet.

Findings from an audit of the 1.9.9 elevated-helper split. The main executable
stays at file version 1.9.9.0; the helper advances to 1.9.9.1 → 1.9.9.2 →
**1.9.9.3** so every install and upgrade replaces the earlier payload.
`releases/1.9.9/` is unchanged and remains the locked 1.9.9 source of truth.

- **The RTSS Frame Limit now works without running SteamShell as
  administrator.** The diagnosis in 1.9.9 was right and the conclusion was
  incomplete: `RTSSHooks64.dll` is loaded into the *calling* process, so
  `SaveProfile` writes with that process's token, and RTSS's default install is
  under Program Files. The row therefore reported itself read-only for every
  standard user — correct, but the feature was dead for exactly the people the
  Quick Menu exists for.

  The elevated helper now performs that write, running the same sequence in its
  own process. `SetRtssGlobalFrameLimit` only latches `RtssFrameCapWriteBlocked`
  after the helper has failed too, and the latch is cleared when settings reload
  so re-enabling the option does not need a sign-out. New
  `[RTSS] EnableElevatedFrameCapWrites` (default on, honoured without a restart)
  and a matching Settings checkbox; schema 20.

  **Getting there took two wrong architectures, recorded because the reasoning
  is the useful part.** The first had the helper write only the profile *file*
  and left every RTSSHooks call in main. That persisted the global cap correctly
  and reproduced neither of the other behaviours an elevated SteamShell had:
  RTSS's own window never updated, and per-game profile saves still silently did
  nothing. The second kept the split and added a `SetProfileProperty` push from
  main after the helper's write, on the theory that the GUI watches the state
  that call writes. It did not fix the display either.

  The sequence cannot be split. The helper now runs the whole of it —
  `LoadProfile`, `SetProfileProperty`, `SaveProfile`, `UpdateProfiles` — in its
  own process, loading `RTSSHooks64.dll` by full path from the same gated
  install directory the profiles come from. That is precisely what an elevated
  SteamShell always did, and reproducing a sequence known to work beat
  continuing to reason about a third-party program's internals. Main's job is
  now only to request and to verify.

  **Two processes must not touch RTSS at once.** While the helper ran its
  sequence, main polled `RtssGlobalFrameLimit` every 25 ms — and that calls
  `LoadProfile`, which reloads RTSS's shared profile state from disk. A poll
  landing between the helper's `SetProfileProperty` and its `SaveProfile`
  reloaded the old value on top of it, so a cap sometimes took several presses.
  Nothing was wrong with the write; the checking was trampling it. Main now
  makes no RTSS calls at all until the helper signals completion through a
  second named event, and the helper signals from a `finally` so refusals return
  immediately instead of costing main its timeout.

  **Neither path attempts the write in-process first any more.** The helper only
  exists in an unelevated session — `StartElevatedInputHelper` refuses under an
  admin token — which is precisely the session where `SaveProfile` fails
  silently. Trying locally first could never succeed there, and for per-game
  profiles it was actively harmful: verifying a named profile re-reads the copy
  `SetProfileProperty` just wrote, so the check passed while nothing had been
  saved and the helper was never asked. That is why an added read-back did not
  fix per-game saves on its own. The global cap had escaped the same trap only
  by accident, because `UpdateProfiles` reloads from disk and clobbers the
  in-memory value. Both paths now go straight to the helper when one exists.

  **A cap was logged as set before it was proved.** `SetRtssGlobalFrameLimit`
  wrote its success line ahead of the read-back, so every change recorded
  success twice — once falsely — which is the same habit the per-game path was
  being cured of, sitting in the global one.

  Two smaller faults fixed along the way. **A Custom value dialled in with
  Left/Right jumped backwards and then forwards** — the wait for the helper
  yields, and AutoHotkey ran the Quick Menu refresh timer during it, repainting
  the row from RTSS's not-yet-updated value. The wait is now `Critical` and
  polls at 25 ms rather than 100. **`NotifyRtssSettingsChanged` was posted
  before the read-back**, i.e. before the helper had written anything; that
  ordering was wrong regardless of what the undocumented WM_APP+100 message
  does, and nothing in this project records what that is.

  **Per-game profile saves now prove themselves.** `SaveRtssFrameLimitToProfile`
  called `SaveProfile` from main, so it had the identical silent failure — and
  reported success anyway, with a green notification and a log line, for a
  profile RTSS never received. Every unelevated user had been told their
  profiles were saving. The save is now verified by reading the named profile
  back, falls back to the helper, and says *profile not saved* when it did not.

  **A per-game profile name is corroborated, not trusted.** The name cannot be
  derived in the helper — by the time a request arrives the Quick Menu is the
  foreground window, not the game — so main sends it and the helper checks it:
  it must look like a bare executable name (a pattern no path separator or drive
  colon can satisfy) **and** name a process running at that moment. A tampered
  settings file can reach a profile named after a process the user is actually
  running, inside RTSS's own profile directory, and no further. An earlier
  revision refused per-game saves outright on the grounds that the name was
  attacker-influenceable; corroboration turned out to be the better answer than
  removing a feature.

  **The configured `[RTSS] Path` is honoured but not trusted.** Setup Assistant
  establishes it and an RTSS installed somewhere non-default should not silently
  lose the feature — but the settings file is user-writable in every
  installation mode, so the hint is corroborated the same way Setup corroborates
  a directory before deleting it: it has to name `RTSS.exe`, `RTSS.exe` has to
  be there, the real directory (junctions resolved through
  `GetFinalPathNameByHandle`) has to sit under a Program Files root read from
  **HKLM** rather than from `%ProgramFiles%` — which this process inherits from
  whoever launched it and which is therefore not evidence — and `Profiles\` has
  to resolve to a directory still inside that install. An RTSS outside Program
  Files is refused, which costs nothing: those installs are writable by the
  account main already runs as, so main's own write works there.

  **Per-game profiles stay at medium integrity, permanently.**
  `SaveRtssFrameLimitToProfile` names its profile after the foreground
  executable. That name is attacker-influenceable — harmless with a medium token
  and an arbitrary file-creation primitive with a high one. The helper's profile
  name is a literal that is never composed, and `Validate-SteamShell.ps1` fails
  the build if the helper ever gains a call to that function.

- **The elevated helper is now gated on an administrator-only location, not just
  a version number.** Matching `1.9.9.2` only proved that *some* file carrying
  that version resource sat at the expected path, and a version resource is
  metadata anyone can stamp onto anything. Setup now restricts the helper's `bin`
  directory to SYSTEM and Administrators (read/execute for others) in **every**
  installation mode, verifies the result, and fails the install if it cannot.
  Before each launch SteamShell re-checks the binary *and* its directory and
  refuses to elevate when either is writable by anyone else. Program Files
  installs got this from inherited ACLs; portable and browsed-custom targets
  never did, which made a user-writable helper directory a local privilege
  escalation. Only `bin` is restricted, so portable layouts keep their writable
  INI, logs, and backups. Health Check reports the state as **Elevated helper
  protection**.
  A follow-up review closed two holes in that gate: Setup now changes and verifies
  the owner as well as the DACL (an owner has implicit permission to rewrite the
  DACL), and it secures the directory before forcibly replacing the embedded
  helper instead of accepting a pre-existing same-version file. ACL enumeration
  and SID-conversion failures now fail closed rather than being skipped.
- **The Auto-Login password is actually zeroed now.** The buffer wipe called
  `RtlSecureZeroMemory`, which is an inline function in `winnt.h` and not an
  export of kernel32 or anything else, so the `DllCall` threw on every attempt
  and a bare `try` discarded the error — the plaintext password was never
  cleared. It now uses the exported `RtlZeroMemory`, without swallowing failures.
- **`EnableElevatedInputHelper` takes effect on reload.** Turning a security
  control off used to leave the elevated process injecting for the rest of the
  session while Health Check reported it running. Reloading settings now stops a
  running helper when the option is cleared, and starts one when it is set.
- **Mappings that must run at normal integrity are no longer dropped.** Main
  yielded all controller handling while an elevated window was foreground, but
  the helper deliberately declines to start processes or raise windows from a
  High-integrity token — so touch keyboard, on-screen keyboard, File Explorer,
  Quick Menu, and Control Panel were handled by neither. With Task Manager
  focused there was no way to reach the on-screen keyboard and type into it.
  Main now keeps exactly those five; the helper gained the remaining fixed
  keystrokes (Task Manager, Start menu, Game Bar, `Ctrl+Alt+Tab`). Every builtin
  is handled by exactly one process. Custom `Send:` strings from the writable INI
  remain ignored over elevated windows. The helper also picked up the main tree's
  `SendChordSafe` modifier-release guard and now uses it for `Alt+F4` as well, so
  system chords behave the same on both sides of the boundary.
- **Only Standard installations register the protected on-demand task.** A
  follow-up review found that securing a Custom install's `bin` is insufficient
  when an arbitrary writable parent can delete and recreate the whole path; the
  task can be invoked directly, bypassing SteamShell's runtime DACL/owner check.
  Custom and Portable therefore keep explicit UAC and Setup warns before
  registering either as the shell. The unified installer should revisit Custom
  only by placing its task target below a known protected ancestor chain.
- **The helper no longer has any UI.** A non-administrator running the
  `HighestAvailable` task got a Medium-integrity helper that opened a modal
  message box on a shell desktop that may have no taskbar and no keyboard. It
  logs and exits instead. A task-started helper that fails verification is also
  closed rather than left behind while the direct-UAC route starts a second one.
- **The helper log moved beside the protected binary and now rotates.** It was
  written into the user-writable data directory — an elevated appender on a
  user-controlled path — and grew without bound while the main tree rotated its
  own. It uses the same `[Logging]` size and backup-count settings.
- **The Frame Limit selection now survives a reboot.** SteamShell was a live view
  of RTSS with no memory of its own: RTSS keeps the FPS number in its global
  profile, but the limiter on/off state is the runtime flag bit `0x4` in RTSS
  shared memory and "Custom" is a SteamShell concept RTSS never sees. Nothing in
  the startup path touched RTSS, and the Quick Menu persisted only
  `EnableIntegration`, `OverlayControlMode`, and `FrameLimiterControlMode` — so
  after every reboot the row read **OFF**, and because the "coming off Off
  restores the number" shortcut requires the *flag* to be what turned it off, one
  press landed on 30 FPS rather than the user's own cap.

  Schema 19 adds `[RTSS] LastFrameCapMode` and `LastFrameCapFps`, written by
  every branch that changes the selection — including Off, which keeps the number
  for the same reason the Off entry never writes 0 into the profile.
  `RestoreRtssFrameLimitTick` reapplies it once RTSS is available, and only
  writes the profile when RTSS does not already agree. It **never starts RTSS**:
  restoring a cap is not a reason to launch a program the user did not ask for,
  so it polls for up to two minutes after startup instead, which is also what
  makes it work when RTSS arrives later through Steam or a startup entry. New
  `[RTSS] RestoreFrameLimitOnStartup` (default on) and a matching Settings
  checkbox turn it off. Requires `UseDllIntegration`; the shortcut fallback can
  only toggle, not select an FPS, and says so rather than silently waiting.
  Follow-up review also made every FPS/flag write part of the success condition:
  a rejected RTSS write is no longer persisted or logged as a restored selection.
- **Setup now installs either product.** `SteamShell.exe` embeds the XFE
  companion the same way it embeds the elevated helper, and the Setup Assistant
  opens with the question everything else depends on: *replace the Windows shell,
  or work alongside Xbox Full Screen Experience?*

  XFE mode installs `SteamShell-XFE.exe`, grants the interactive user write
  access to its own directory (XFE keeps its INI, controller profiles, and log
  beside the executable), and registers a **LeastPrivilege** logon task. It never
  registers a Windows shell, never deploys the elevated helper, and never
  elevates — the validator asserts all three, including that the task principal
  is not `HighestAvailable`. Choosing XFE on a machine where SteamShell is
  currently the shell restores Explorer first, so switching is a supported move
  rather than something that leaves Winlogon pointing at an abandoned executable.

  Which product a machine has is recorded in HKCU `Product` and in schema 19's
  `[Setup] Product`, because the uninstall for one is wrong for the other:
  running the shell restore on an XFE machine would rewrite a Winlogon value
  SteamShell never set. `/uninstall` resolves the recorded product and
  cross-checks it against what is on disk, and only asks the user when the record
  is missing or contradicted — a question the installer should be able to answer
  itself is a question that collects wrong answers. Unattended and ambiguous does
  nothing rather than guessing. `/restore` stays product-independent on purpose:
  it is the command reached for when the desktop is gone, which cannot happen on
  an XFE machine.

  A machine recorded as XFE never starts the shell runtime from `SteamShell.exe`;
  `SetupAssistantRequired` returns true so it opens Setup instead. There it is
  the installer and the uninstaller, not the product.
- Fixed the product radios not being mutually exclusive. AutoHotkey groups radio
  buttons that are created **consecutively**, and the per-option description text
  had been added between them, which ended the run: both rendered selected and
  Apply read whichever it liked. The descriptions are now positioned after both
  radios from their measured positions. The validator pins the adjacency,
  because nothing else prevents it.
- **Setup Assistant opens on what is already installed.** It detects an existing
  installation and preselects the product, the location, and the startup
  registration to match, so an upgrade does not depend on the user reproducing
  choices they made months ago. Everything stays editable; only the starting
  state changes, and the status line says what was found.

  Detection is evidence-first. The Winlogon `Shell` value and the
  `SteamShell XFE Companion` scheduled task are the things that actually have an
  effect, so they are read directly rather than trusting SteamShell's own HKCU
  record — which may have been lost, written under a different profile, or never
  made it when a registration failed. The record supplies only the install
  directory, which nothing else stores. XFE is tested first because it is the
  more specific claim: a logon task is not something a shell install produces.
- **Controller reach now matches XFE, and stops being a list.** Every SteamShell
  settings and editor surface temporarily receives right-stick pointer and click
  while it is active, without changing the persisted Mouse Mode setting. That set
  used to be an enumerated list of windows, and the uninstall dialog was added
  without joining it — so it worked when raised from Setup Assistant, which was
  on the list, and would have been dead when raised from `/uninstall`.

  The list was defended on two grounds, and neither held. That standalone
  evaluates this before the Quick Menu branch: it does not — `PollController`
  returns from the Quick Menu branch first. That the splash and desktop backdrop
  would wrongly qualify: they cannot, because all three presentation windows are
  created `WS_EX_NOACTIVATE` and never become the active window. What the list
  actually did was go stale.

  Standalone now asks the same question XFE has always asked — *is the active
  window one of ours?* — keeping the owner-chain walk that catches native common
  dialogs hosted outside the process. Dialog ownership moved to the same rule and
  is strictly better for it: owning to the active window means a dialog cannot be
  owned by a SteamShell window that is itself behind a fullscreen game. Two
  programs with the same requirement no longer have two different answers to it,
  and the validator pins the *rule*, failing the build if either function goes
  back to naming windows.
- **Every modal dialog is now owned, or topmost when there is nothing to own
  it.** Almost every SteamShell window is `+AlwaysOnTop`, because it is a kiosk
  shell that has to stay in front of Steam and games — so an unowned `MsgBox`
  opens *behind* whichever one is showing, and with the taskbar hidden there is
  no way to find it. The user sees a frozen window and nothing to click.

  A single `SteamShellDialogOwnerHwnd` now resolves the owner, checking the
  innermost window first so a dialog raised from the Controller Test sits above
  the Controller Test rather than above the Settings window behind it. An audit
  of all 18 modal call sites across both trees found four unprotected ones —
  the administrator-setup prompt, the setup abort, the Control Panel save
  failure, and the self-test report — all now routed through it. The rest were
  already owned or already passed `262144`.

  The file pickers were correct but for a subtle reason worth recording:
  `+OwnDialogs` is per-**thread** in AutoHotkey, so applying it when a GUI is
  created does nothing for a later event handler. Three of the four re-applied it
  per call; `SetupAssistantSelectDirectory` did not, and now does.
- **Closing Setup Assistant during first-run setup exits SteamShell.** In that
  mode SteamShell is an installer, not the shell: it runs from wherever it was
  launched, Explorer owns the desktop, and Steam, the splash, the blackout, and
  taskbar hiding are all suppressed. Closing the window used to leave it resident
  — a copy of the shell running out of a downloads folder or a network share,
  with no visible window and no way for the user to know it was there. On a
  completed installation the assistant is just a settings window and closing it
  still only hides it.
- Fixed the uninstall product prompt, which had two problems at once. It was a
  Yes/No/Cancel box where **Yes** meant SteamShell and **No** meant
  SteamShell-XFE — not a question anyone can answer from the buttons — and it was
  unowned, so it opened *behind* the always-on-top Setup Assistant where it could
  not be seen or reached. It is now an owned dialog whose buttons are named
  **SteamShell**, **SteamShell-XFE**, and **Cancel**, each with a line saying
  what it does. The four other message boxes on the uninstall path were unowned
  for the same reason and are now owned too.
- Fixed the cause of that prompt appearing at all. Setup Assistant identifies the
  product from the Winlogon value and the scheduled task, then called an
  uninstall that re-derived it from the HKCU record — a second, weaker answer
  that could fail where the first had succeeded, putting an ambiguity prompt in
  front of a user who was never ambiguous. The caller now passes the product it
  already resolved, and the uninstall falls back to the live evidence before
  asking.
- **Setup Assistant can uninstall.** A new *Remove an installation* section
  retires the detected installation's shell registration or logon task, after an
  explicit confirmation, and leaves every file and setting in place. This is the
  fallback for a user who cannot reach a command line — which, on a machine where
  SteamShell is the shell and something has gone wrong, is not a rare position to
  be in. It reuses the same product-aware path as `/uninstall`.
- **Uninstall can optionally delete the files, as a second, separate decision.**
  Setup records where everything went, so finding the files was never the
  problem. The problem is that an install *directory* is not necessarily ours: a
  portable EXE dropped into a folder of other tools, a "use current location"
  install, or a browsed directory the user already had would all be destroyed by
  a naive folder delete.

  So a directory is removed only when SteamShell **chose the path itself and
  created it** — `%ProgramData%\SteamShell`, `%ProgramFiles%\SteamShell`,
  `%LOCALAPPDATA%\Programs\SteamShell-XFE`, and the fixed-name `SteamShell` and
  `components` folders directly beneath a recorded install directory. A folder
  the user chose keeps everything except SteamShell's own files, which are
  removed by exact path because the file itself is unambiguous.

  **The registry record is treated as a claim, not proof.** It is written by
  whichever copy ran Setup, it survives a manual delete, and a freshly downloaded
  EXE inherits it wholesale — so a stale entry could name a path that now holds
  something else. Three things guard against that. A recorded path that no longer
  exists is reported rather than silently skipped. A directory is removed only if
  it still *contains* a SteamShell artifact, so a folder that has been emptied
  and reused is kept whatever HKCU says. And the recorded location is
  cross-checked against independent evidence — Winlogon's shell value for the
  shell, the logon task's own action for XFE — which both stands in for a missing
  record and catches a stale one: if the two disagree, nothing at all is offered
  and the assistant says why rather than looking like it found nothing.

  The plan is shown in full before anything happens, including what is being
  kept and why. Deleting is never bundled into the unregister confirmation:
  it is offered only after unregistering has already succeeded, because it is
  the one part of this that cannot be undone. Paths are re-checked at execution
  rather than only when the plan was built, the running executable is never a
  target, and drive roots, system locations, and reparse points are refused
  outright. The HKCU record is removed only once the files actually are.
- The XFE logon task is now an explicit choice, matching shell mode's
  **Register… as the Windows shell**. `DeploySteamShellXfe` had always handled a
  declined startup task — removing any stale one and saying so on the completion
  dialog — but Apply passed `true` unconditionally, so nothing could reach that
  path: the capability existed in the code and was absent from the product. Only
  the checkbox that applies to the selected mode is enabled.
- The mode question now reconfigures what follows it. Choosing XFE disables and
  clears **Register… as the Windows shell**, disables **Portable** (a shell
  layout concept — XFE's data is always beside its executable, so the checkbox
  would do nothing), and changes the recommended location to
  `%LOCALAPPDATA%\Programs\SteamShell-XFE`. Program Files was wrong for XFE:
  Setup grants the signed-in user write access to XFE's own directory, and a
  user-writable Program Files subdirectory is poor hygiene even when nothing in
  it is ever elevated. The location summary describes the companion layout
  rather than the shell one.
- **`Build-SteamShell.ps1` builds the XFE payload before compiling.** It invokes
  XFE's own build script with an explicit output path rather than making a second
  Ahk2Exe call, so the embedded companion goes through XFE's validator and its
  own version check instead of a parallel build path that could drift. This does
  make the standalone build depend on the sibling tree, so a release bundle must
  contain both — which the 1.9.9 bundle already does.
- **Fixed an install-breaking ordering bug in the helper hardening.** `/setowner`
  ran once, on the directory, *before* the payload was extracted. Windows takes a
  new file's owner from the creating token, and the "default owner for objects
  created by members of the Administrators group" policy has defaulted to the
  object creator since XP SP2 — so the freshly written helper was owned by the
  installing administrator's own SID rather than Administrators, and the
  verification that checks the file as well as the directory would have refused
  it, failing every install. Setup now hardens, replaces, hardens again, and then
  verifies. It failed closed, but it failed.
- **The functions both trees share now live in one file.** `SteamShell-Shared.ahk`
  at the repository root is `#Include`d by SteamShell.ahk and SteamShell-XFE.ahk
  and holds 56 functions. `SHARED_FUNCTIONS.txt` used to record which functions
  were *supposed* to stay byte-identical and `Validate-SharedParity.ps1` failed
  the build when one drifted — a net that catches falls. Defining each function
  once removes the edge: there is no second copy to drift from. The checker's job
  changed to match, and it now fails if a shared function is redefined inside a
  tree (which would shadow the shared one and still compile), if the shared file
  defines something the manifest does not list, if either tree stops including
  it, or if either tree stops providing the seam below.

  Shared code may call back into exactly two per-tree functions: `LogLine` and
  `SharedPersistSettings(changes)`. The second exists because both trees write
  settings correctly for what they are — standalone stages a copy and replaces
  the live INI only after every write succeeds, because a half-written settings
  file in the Windows shell is a machine that signs in to nothing; XFE writes
  directly, because it is an ordinary application.

  Conservative on purpose: only functions that are already behaviourally
  identical moved. A similarity scan suggested nine more were "near-identical",
  but on inspection only four were — the rest differ by product
  (`QuickMenuMouseActivate` vs `MouseSelect`, `SetStatus` vs `ShowNotification`,
  `QuickMenuStatusCtrl` vs `QuickMenuFooterCtrl`) and stayed in their trees.
- Both validators now resolve `#Include` before asserting, so every check still
  sees the source as AutoHotkey does. Reading the tree file alone would have
  silently passed every assertion about a function that moved out of it.

  The resolver uses `Get-Content -Raw` rather than
  `[System.IO.File]::ReadAllLines`, because it has to reproduce what the
  assertions already saw rather than improve on it. The first attempt did the
  latter and broke two assertions on Windows in two different ways. **Line
  endings:** these sources are LF-only, `ReadAllLines` drops the terminators and
  `StringBuilder.AppendLine` writes CRLF, and .NET's `(?m)$` matches before `\n`
  — so every `^...$` pattern failed on the intervening `\r`. **Encoding:**
  Windows PowerShell decodes a BOM-less file as ANSI while `ReadAllLines` decodes
  UTF-8, and the one assertion containing a non-ASCII character (`PRESET · … FPS`)
  matches only because the pattern and the source are mis-decoded identically.
  Decoding the source correctly broke it.
- `Run-SteamShellValidation.ps1` now copies `SteamShell-Shared.ahk` beside the
  temporary tree it builds in sections 5b and 5c. Those tests copy a single tree
  into a temp directory and run its build script there, so the include could not
  resolve and every build failed on the missing file — which *looked* like a pass,
  because the build did reject the tree, while proving nothing about the broken
  source or the stale output each test exists to check. The same class of silent
  pass the 5c comment already records for a different cause.
- **XFE gained the Frame Limit restore** in the same change, because the restore
  now lives in the shared file rather than being written twice. XFE advances to
  schema 9 with the same `[RTSS] RestoreFrameLimitOnStartup`, `LastFrameCapMode`,
  and `LastFrameCapFps` keys and its own Settings checkbox.
- Fixed a validator assertion that could not fail. The pin on
  `PersistRtssFrameCapSelection` used an unbounded `(?s).*?CommitIniChanges`,
  which matched 128,000 characters past the end of the function and kept passing
  after the body stopped calling it. It is now bounded to the function body with
  `(?!\n\})`, and asserts the seam the body actually uses.
- Removed a stale seven-line comment fragment above `CancelPendingRtssFrameCap`
  in both trees. It duplicated an older draft of `AdjustRtssCustomFrameCap`'s
  documentation and described behaviour belonging to a different function.
- The helper now honors `[QuickMenu] Enable`, so L3/R3 bindings stop being
  reserved over elevated windows when the Quick Menu is turned off, and re-arms
  its poll timer when `ControllerPollIntervalMs` changes instead of keeping its
  startup rate until restart.
- Body-bounded validator patterns are anchored to column 0. Without it,
  `Name\([^)]*\)\s*\{` matches a *call* used as a braced `if` condition, so an
  assertion meant to inspect a function body inspected an unrelated block
  instead — which is how a `-notmatch` guard reported a violation that was not
  there. 22 patterns were genuinely body-bounded and are anchored; the rest match
  indented call sites deliberately and are not.
- The validator pins all of the above: every Frame Limit branch recording what it
  applied and the restore never launching RTSS, the DACL gate and its trusted-SID
  set, Setup's hardening and verification, the log location and rotation, the
  live enable/disable path, the builtin split across both trees, the absence of
  helper UI, and that the password wipe uses an exported function.
- Documentation: `XFE_PARITY_NOTES.md` now records the helper, Setup Assistant,
  and installation layout as a deliberate standalone-only divergence; the project
  overview's file layout lists the root validation and shared-parity files and
  `INI_READER_MIGRATION.md`; the README documents the protection requirement, the
  builtin split, the narrowed elevated auto-mouse set, and the portable UAC
  behavior.

### From testing 1.9.9 on hardware

Four reports, all confirmed in the source. The first three are fixed here; the
fourth was assessed as a decision rather than a defect, and the conclusion is
recorded in `XFE_PARITY_NOTES.md`.

- **The Frame Limit row could only reach OFF, PRESET and CUSTOM.** Reported in
  both trees, and correct: the A button called the same *clamped* cycler that
  Left/Right uses. A clamp is right for Left/Right, which can walk back down an
  ascending scale — and wrong for A, which has no reverse and simply stopped on
  the last entry. Compounding it, the "coming off Off" shortcut restores the FPS
  number RTSS still holds, which is usually the configured Preset or a Custom
  value, both near the *end* of the list. So pressing A from Off jumped past
  every standard cap in one step, and pressing A again reached Custom and stuck
  there. 30/40/60/90/120 were only reachable by pressing Left from Preset, which
  nobody had a reason to try. `CycleRtssFrameCap` now takes `wrap`, which the
  activate path passes and Left/Right does not; the Off shortcut is suppressed
  when wrapping, because a jump to the far end of a list you can only walk
  forward through is what made the caps unreachable in the first place.
- **The XFE Quick Menu could be cut off at the bottom.** Intermittent, and it
  had to be: XFE re-derives the whole row list on every refresh, unlike
  standalone where the rows are fixed when the page is built — but only
  `QuickMenuBuildGui` sized the window. Any page that *grew* during a refresh
  painted the extra rows past the window's bottom edge. The RTSS page is the one
  that does this, since its rows come from live RTSS state: RTSS starting while
  the page was open took it from two rows to four and clipped the bottom two.
  The sizing step is now `QuickMenuResizeToRows`, and a refresh calls it when the
  row count actually changed — not on every repaint, which would re-centre the
  window under the user for a value change.
- **XFE gained automatic mouse mode.** It had none: only holding View/Back, or
  `EnablePersistentMouseMode` for always-on. Returning to the Windows desktop
  therefore left the controller with no pointer, where standalone gives one.
  XFE now has the same two gates — `EnableAutoMouseMode` as the master switch,
  then either the blanket `DesktopAutoMouseExcludeExeList` or the per-application
  `AutoMouseExeList`. Standalone chooses between those lists with `DesktopMode`,
  which has no meaning in a companion that never owns the shell;
  `EnableDesktopAutoMouseMode` makes the choice instead, so both knobs keep their
  standalone meaning and neither becomes configuration that does nothing. Xbox
  FSE and its shell surfaces are excluded by default: they are controller-driven,
  and a pointer inside them is the one place this feature would do harm.
  `AutoMouseProcessMatches` moved to `SteamShell-Shared.ahk`, since the list
  means the same thing in both programs; `AutoMouseModeActive` stays per-tree,
  because the choice above is exactly what differs.
- **The hardening added above left the helper with an empty DACL, so it never
  ran at all.** Confirmed on hardware 2026-08-02 and self-inflicted: `(OI)` and
  `(CI)` are *inheritance* flags with no meaning on a file, and the grant was
  issued with `/T`, so icacls applied the same string to
  `SteamShell-Helper.exe` — where it was rejected, after `/inheritance:r` had
  already stripped what the file would otherwise have inherited. The binary was
  left with **no ACEs at all**, which denies everyone including Administrators.
  `/C` suppressed the error and the process still exited 0, so Setup recorded a
  success. `icacls` on the directory listed all three ACEs correctly; `icacls`
  on the helper listed none.

  **Every existing check passed**, and that is the more important half.
  `SteamShellPathIsAdminOnlyWritable` asks only whether anyone outside
  SYSTEM/Administrators can *write* — and nobody can write a file nobody can
  touch, so an unlaunchable helper was certified as protected. The main process
  could not even read its version resource, concluded the helper was missing,
  and tried to re-extract it into an administrators-only directory; that is
  where the `Extraction failed: Failed` line came from, for a file that was
  present the entire time. Four changes:
  - The flagged grant now applies to the **directory only** — no `/T` — and the
    contents are made to inherit it with `icacls <bin>\* /reset /T /C /Q`. That
    also repairs an already-broken install, because the reset runs before the
    payload is replaced.
  - `ElevatedHelperLocationIsProtected` now proves the binary is **readable**
    and carries the expected version, not merely that it is unwritable.
    "Protected" has to mean usable-and-locked, not just locked.
  - An unelevated session no longer attempts an extraction that cannot succeed
    against an administrators-only directory. It names the actual remedy — run
    Setup elevated — instead of reporting a file error.
  - Both extraction paths report the Win32 code and target path (see below).
- **The Frame Limit row was silently discarding every write, and blaming the
  wrong thing for it.** The wrap fix above was real but was not the reported
  fault. `RTSSHooks64.dll` is loaded into SteamShell's *own* process, so
  `SaveProfile` writes with SteamShell's token — and against RTSS's default
  Program Files install an unelevated write is refused **silently**:
  `SetProfileProperty` succeeds against the in-memory copy, `SaveProfile` fails,
  `UpdateProfiles` reloads the old value over the top, and every read afterwards
  returns the number that was already there. The row therefore never left the
  entry matching that stale value, which is why the standard caps looked
  unreachable and Custom looked like it reverted the moment you moved off it.
  Confirmed on hardware 2026-08-02: cycling logged a successful write on every
  press while the on-disk `Profiles\Global` never changed, and running SteamShell
  as administrator fixed it outright. The limiter flag worked throughout —
  `SetFlags` goes through RTSS's shared memory rather than a file, which is
  exactly why On/Off was the one thing that worked.

  `SetRtssGlobalFrameLimit` now reads the value straight back and latches
  `RtssFrameCapWriteBlocked` when RTSS disagrees. After that the row reports
  itself read-only and says *why* — "RTSS profile writes need administrator
  rights" rather than the old "This RTSS build cannot set the frame cap
  directly", which named the wrong cause and sent anyone reading it to check
  their RTSS version. Detected from a real failed write rather than by probing,
  because the honest probe — creating a file in RTSS's `Profiles` directory —
  risks leaving a stray file where RTSS enumerates profiles.
- **The Custom FPS row adjusted from the wrong number.** The value column shows
  the live cap; the arithmetic started from the persisted `RtssCustomFrameCap`,
  so once those had drifted apart the first press jumped somewhere unrelated to
  what was on screen. It now adjusts from the displayed value.
- **Helper extraction failures were undiagnosable.** AutoHotkey's file commands
  throw with the bare message `"Failed"`, so a real install logged *"Extraction
  failed: Failed Run SteamShell as administrator and apply Setup to install the
  matching helper"* — naming neither the path nor the reason, and giving advice
  the user had already followed. Both extraction paths now report the Win32 code
  (calling out access denied by name) and the target path.
- One validator assertion had quietly stopped being able to fail. `(?s)Cycle
  RtssFrameCap\(direction\).*?` matched the *call site* in
  `QuickMenuAdjustSelected` and ran on into the definition from there, so it
  passed unchanged when the signature gained `wrap`. It is now bounded to the
  function body, which is the same fix the remaining 39 unbounded patterns need.

## 1.9.9 — 2026-08-01

- Locks the large pre-2.0 architecture transition as a coordinated standalone
  and XFE source release. Both applications now report 1.9.9, and their compiled
  binaries carry file version 1.9.9.0.
- The standalone elevated helper carries file version 1.9.9.1 so every 1.9.9
  install or upgrade replaces earlier helper payloads. Both build scripts and
  the combined validation harness reject compiled files with unexpected version
  metadata.
- The locked `releases/1.9.9/` bundle contains both complete source trees, both
  local double-click build launchers, the shared parity inputs, and the root
  double-click validation/build launcher. It can validate and compile both EXEs
  without depending on files outside the release directory.
- Includes all implementation changes developed under the 1.7.8 line below:
  normal-integrity UI and application launch ownership, the scoped elevated
  input/window helper, transactional Setup Assistant and upgrade paths,
  first-launch administration handoff, safer recovery/desktop restoration,
  DPI-aware setup UI, integrated Auto-Login, and the supporting validation and
  test coverage.

## 1.7.8 development line — consolidated into 1.9.9

- Install and upgrade are now explicit administrator maintenance sessions. A
  normal-integrity Apply or pending first launch explains that SteamShell must
  be started with **Run as administrator**, records the requesting user/session,
  restores an Explorer desktop, and exits when the user acknowledges the dialog.
  The matching elevated launch consumes that one-time request and opens Setup
  Mode instead of silently elevating or starting the ordinary shell runtime.
- Elevated Setup now closes existing same-user/same-session `SteamShell.exe`
  instances and waits for their parent-bound helpers to exit, then terminates
  only verified helper leftovers. Cross-account elevation is rejected, failed
  takeover is reported, and setup never overwrites a helper that is still in use.
- Setup Assistant now sizes from the target monitor's physical work area and
  effective per-monitor DPI, uses an 80% initial-height budget with a 620-logical
  cap, and re-measures the hidden outer window against an 88% safety ceiling.
- Existing sidecar portable targets are explicitly identified as upgrades.
  Apply preserves their INI, stages/replaces the main EXE, and atomically stages,
  version-checks, and replaces the embedded helper before confirming success.
  A successful upgrade then permanently removes only the pending/in-progress
  `SteamShell` sidecar beside the separate updater EXE and exits that updater;
  exact-path, Setup-state, link/junction, and target-containment guards protect
  the live installation and every completed source configuration.
- Successful Setup now ends with an owned **Restart Now** / **Restart Later**
  dialog. Restart Now invokes Windows' normal immediate reboot command and exits
  intentionally, while Restart Later still closes a no-longer-needed upgrader.
- Elevated Task Manager and other High-integrity application windows now receive
  the same center/maximize policy through `SteamShell-Helper.exe`. The main
  Window Engine explicitly defers those windows to the verified helper, which
  honors the existing toggle, maximize threshold, exclusions, settling delay,
  and bounded retries. A parent-owned runtime event disables helper geometry in
  Desktop/Safe modes without disabling elevated controller input. Helper file
  version 1.7.8.1 forces replacement of the earlier input-only 1.7.8 payload.
- Setup Assistant is now monitor-height bounded, resizable, and vertically
  scrollable, so the status and Apply controls remain reachable at television
  DPI scaling. Steam and RTSS paths are shown directly and are discovered from
  their Program Files defaults (plus Steam's registered install location).
- Setup-owned confirmations are explicitly parented above the assistant.
  External UAC/Microsoft windows temporarily minimize and lower the assistant,
  then restore it after the external process exits.
- Added an integrated Auto-Login dialog. It validates credentials through
  Windows, stores the password as the documented protected `DefaultPassword`
  LSA secret, writes `AutoAdminLogon` only after that succeeds, supports secure
  disable/removal, and never places the password in the INI, log, or a process
  command line. The dialog warns that physical access grants account access and
  that administrators can retrieve LSA secrets.
- Added transactional first-run Setup Mode in schema 17. Fresh configurations
  keep Explorer visible and suppress Steam, splash, blackout, taskbar hiding,
  startup programs, cleanup, and window/focus automation until setup completes;
  existing configurations migrate directly to Complete.
- Setup Assistant now supports a recommended Program Files/ProgramData layout,
  current-location portable sidecars, and browsed custom locations with an
  optional portable layout. It verifies staged EXEs, creates data/component
  directories, applies current-user ProgramData access, records InProgress
  before changes and Complete last, and optionally registers the selected EXE
  as the shell with recovery metadata and shortcut.
- Added safe links to Windows UAC settings and Microsoft's Autologon guidance.
  SteamShell never disables UAC; the later integrated Auto-Login dialog keeps
  its requested password out of plaintext settings, logs, and command lines.
- Portable shell registration now warns about writable placement and warns
  again for removable, network, mapped, or temporary targets.
- Replaced monolithic administrator startup with an embedded
  `SteamShell-Helper.exe`. The registered shell, Quick Menu, Settings, recovery,
  Steam, and ordinary children now remain Medium integrity; only the hidden
  helper elevates, and it injects controller input exclusively while a
  High/System-integrity window is foreground.
- Advanced to schema 18 and migrated `RunElevatedOnStartup` to the accurately
  scoped `EnableElevatedInputHelper` setting without changing the user's choice.
- The main and helper both detect the integrity boundary. Main evaluates its
  recovery/menu/settings chords first and then yields all normal mappings while
  the helper owns an elevated foreground, preventing duplicate cursor movement,
  clicks, long presses, or release actions. The helper exits with its parent,
  has no UI/tray icon, reloads mapping changes, and writes a separate log.
- Helper acceptance is fail-closed: the main process verifies the helper's exact
  executable path, interactive user SID, session, and High-integrity token before
  yielding controller input, then periodically re-verifies that boundary.
- `Build-SteamShell.ps1` validates and compiles the helper first, verifies its
  file version, and embeds that payload in the single published SteamShell EXE.
  Setup and startup extract and version-check it in the managed component or
  portable sidecar `bin` directory.
- Direct executables still retain the verified standard-user launch boundary as
  a defense when SteamShell is explicitly started elevated for pending setup or
  by the user. Normal completed sessions launch them directly at Medium
  integrity with real PIDs and requested show states.
- Background Explorer is established before optional startup programs. Health
  Check now reports launch capability, launch-route failures, and the observed
  integrity of Steam, Explorer, RTSS, and tracked external children.
- The validator pins helper embedding/versioning, High/System foreground
  gating, parent lifetime, input ownership, explicit administrator Setup
  takeover, standard launch, startup order, and Health Check invariants.
- Corrected the token-information helper's output parameter name so it cannot
  shadow AutoHotkey's case-insensitive built-in `Buffer` class during the first
  pre-elevation SID lookup. The validator now pins that collision fix.
- Corrected cold-boot process creation after hardware testing exposed Windows
  errors 267 and 1346. The verified linked token is now duplicated as an
  explicit primary token, `SeImpersonatePrivilege` is enabled and checked, and
  a validated application directory is passed directly as `WStr` instead of a
  hand-built pointer. If Windows still rejects the native route before a shell
  exists, SteamShell starts Explorer through Explorer's own self-de-elevation
  path and accepts it only after user, session, and Medium-integrity checks.
  Shell-brokered executables recover their PID so MPV lifetime and hidden
  startup-window enforcement remain connected.
- Closed the remaining cold-boot race between Explorer creating its verified
  taskbar and publishing its desktop COM automation object. The standard-user
  fallback now re-verifies Explorer's user, session, and Medium integrity while
  waiting up to ten seconds for that broker to become ready, instead of opening
  Recovery on the transient `String has no property named Document` error.

## 1.7.7 — 2026-08-01

- All SteamShell settings/editor surfaces now temporarily receive controller
  mouse input while active. This includes Controller Mapping opened directly
  from Quick Settings; it does not alter the persisted Mouse Mode setting.
- RTSS Frame Limit now cycles through the standard caps, a named configurable
  **Preset**, and **Custom**. Schema 16 copies the old `CustomFrameCap` into the
  new `PresetFrameCap`, while Custom keeps and persists its own last adjusted
  value. The same behavior ships in XFE 0.1.21/schema 8.

## 1.7.6 — 2026-08-01

- Added **Open Keyboard** immediately below Game Bar. Quick Settings is fully
  dismissed before the Windows touch keyboard is presented.
- Added a persisted **Mouse Mode** main-row toggle. When enabled, the controller
  pointer and mappings work without holding View/Back; enabling it also repairs
  a disabled controller-mapping master switch.
- Replaced the main-page Controller Layout row with **hold Y on the main page**
  to open the styled Controller Mappings submenu. Its final **Set Controller
  Mappings** row opens the full editor.
- Added **Windows Settings** to Settings; removed Reload Settings there and the
  Diagnostics Control Panel and Health Check rows from System.
- Standardized Quick Settings labels and descriptions to title case. Settings
  now reads **Features & Configuration** and System reads **Power & Diagnostics**.
- Advanced settings schema to 15. Existing custom row order is retained while
  the retired layout row is removed and the two new rows are inserted after
  Game Bar. The same applicable behavior is mirrored in XFE 0.1.20/schema 7.
- Updated fresh-install and missing-key defaults from the validated living-room
  profile: faster focus/exit timing, a 30% window threshold, Purple Quick Menu,
  3000 controller deadzone, Explorer automatic mouse, guarded launcher cleanup,
  and RTSS Separate controls with a 158 FPS custom cap. Startup launch scheduling
  is enabled but every `Program1`–`Program20` slot remains blank. Applicable
  Quick Menu, controller, startup, Lite Assist, cleanup, and RTSS defaults are
  mirrored in XFE.

## 1.7.5 — 2026-08-01

Findings from a full cross-tree audit of SteamShell and SteamShell-XFE. Every
item below that touches shared behaviour was applied to both trees in the same
pass; see `XFE_PARITY_NOTES.md`.

The initial audit pass was validated on Windows 11 with Windows PowerShell
5.1.26100 and AutoHotkey 2.0.26: both sources parsed, both validators passed,
both trees compiled, and the standalone negative build tests passed. The
follow-up fixes below changed both sources and the root harness and therefore
still require a fresh Windows run of `Run-SteamShellValidation.cmd`. Nothing
*behavioural* has been verified — see the caveat at the end of this entry.

- **Audit follow-up:** RTSS default-path discovery is centralized across menu,
  launch, health, and hooks-DLL lookup in both applications. XFE now loads its
  log-rotation values into the intended globals. SteamShell resolves unquoted
  shell paths with spaces and PATH executables, and a failed PreviousShell
  write-back retains the recovery shortcut and registry metadata.
- **Validation publication:** the root harness tests broken source and stale
  output in both build trees, returns a non-zero exit code on failure, and
  publishes both hash-verified EXEs to root `current\` as one directory
  transaction only after the complete run passes. Cross-tree parity can no
  longer silently skip when both trees exist but its checker is missing.

- **Build:** `Build-SteamShell.ps1` now reads the real exit code of
  `AutoHotkey64.exe /Validate` and `Ahk2Exe.exe` via `Start-Process -Wait
  -PassThru`, matching what XFE already did, and verifies the output EXE was
  rewritten by *this* build so a stale `dist\SteamShell.exe` cannot satisfy the
  existence check.

  On the severity: this was **not** a live defect, contrary to how the audit
  first reported it. Both executables are GUI-subsystem, for which Windows
  PowerShell can fail to set `$LASTEXITCODE` — but the previous code piped the
  output through `ForEach-Object`, and draining that pipeline synchronizes on
  process exit, so the exit code was reliable in practice. Measured on Windows
  PowerShell 5.1.26100 with AutoHotkey 2.0.26: a deliberately broken source
  returned exit code 2 through both the old and the new mechanism. The change is
  kept because it does not depend on the pipe remaining in place — removing the
  `2>&1 |` during some later edit would silently reintroduce the hazard — and
  because it separates stdout from stderr. It is hardening, not a bug fix.
- **Uninstall:** `HKCU\Software\SteamShell\PreviousShell` is now read back.
  Both registration paths had recorded it since 1.5.0 and nothing ever read it:
  every restore wrote a literal `explorer.exe`, and the uninstall then deleted
  the key holding the only record. A user who ran a different custom shell
  before installing SteamShell lost it silently and unrecoverably. `/uninstall`
  now reinstates the recorded shell after verifying it exists and does not point
  back at SteamShell. `/restore` deliberately keeps its hardcoded `explorer.exe`:
  it is the emergency path, where a known-good shell beats a faithful one.
- **Quick Menu:** the selection index is normalized at every site that moves it
  rather than downstream in the repaint. `QuickMenuRefresh` returns early on an
  empty page, which is exactly where a stale out-of-range index used to survive.
- **HDR:** the Win+Alt+B compatibility fallback moved out of
  `SetQuickMenuHdrState`'s `allowToggleFallback` flag and into an explicit
  `RequestHdrToggleFallback()`. Win+Alt+B is a toggle, so the requested on/off
  state was silently discarded on the one path that used the flag. A successful
  HDR change now queues a display reflow, because Windows updates the reported
  state asynchronously after the display blanks.
- `GetPrimaryHdrState` reports `wideColorEnforced`, and `GetRtssFrameLimit`
  reports the resolved profile name and no longer lets an empty `SplitPath`
  result turn a named profile request into a global one. Both bring standalone
  in line with XFE, which already returned these.
- Splash `Mute`, `PlayFullDuration`, and `SafetyMaxMs` had INI defaults that
  disagreed with their own parse-failure fallbacks, so a malformed value
  produced the opposite of the documented default — and quadrupled the splash
  safety ceiling from 15 s to 60 s. The validator now fails on any such pair.
- `CloseExeProcesses` re-validates the process name before it reaches a
  `cmd /c taskkill` command line, and quotes it. Every caller already passed a
  name `ParseExeListPipe` had checked; the guarantee now belongs to the function
  instead of to its callers' habits.
- Log rotation no longer calls `FileGetSize` on every written line. The size is
  estimated between checks and confirmed for real before anything is moved.
- GDI+ is released with a matching `FreeLibrary`, and a failed
  `CreateDIBSection` is detected and logged instead of silently blanking the
  Quick Menu rows. Both applied identically to XFE.
- Validator: the settings schema version is derived from the source and
  cross-checked against the sample rather than compared with a hardcoded `14`,
  which had to be hand-edited on every bump and failed as a false alarm until it
  was. Added assertions pinning the PreviousShell restore, the `/restore` versus
  `/uninstall` split, the HDR fallback separation, and log rotation.
- **Formatting:** `SteamShell.ahk` is reindented from one space to XFE's four,
  with `switch`/`case` bodies aligned to match. Content-only-preserving: nothing
  but leading whitespace moved, the embedded default INI's continuation section
  is untouched, and every line's content was verified identical afterwards. This
  is what makes cross-tree drift visible at all — before it, a raw diff of the
  two trees was entirely noise.
- **Cross-tree check:** `SHARED_FUNCTIONS.txt` and `Validate-SharedParity.ps1`
  at the repository root assert that the 42 functions shared with SteamShell-XFE
  are byte-identical, and both trees' validators run it. Drift now fails the
  build instead of waiting to be found by an audit. The check is skipped when the
  sibling tree is absent, as inside a frozen `releases/` snapshot. The manifest
  also records, in comments, the shared-looking functions that are *deliberately*
  different and why — currently `ToggleQuickMenuHdrState`.

- **Shared-surface pass.** A follow-up measurement asked what *else* could be
  shared. The answer was "less than expected": unifying every cosmetic
  difference — comments, line wrapping, `ShowNotification`/`SetStatus`,
  `ClampInt` vs `Max(Min())`, product-identity strings — would take the
  byte-identical count from 42 to only 50 of 144. Roughly 94 shared-name
  functions differ substantively, and a cross-comparison of all 399 standalone-only
  against all 235 XFE-only functions found exactly one near-duplicate, a
  six-line helper. There is no large hidden seam between these trees.

  What was worth doing, and was done: the four functions that differed *only* by
  comments now carry the better comment in both (`ApplyRoundedCorners` gains the
  measured-on-a-4K-television explanation; XFE gains the PolicyConfig COM
  rationale). `ClampInt`/`ClampFloat` were added to XFE, which had neither and
  open-coded `Max(lo, Min(hi, x))` at 19 sites. And `DisplayChangeSafetyTick`
  now guards its repaint with `if QuickMenuVisible` in both trees rather than
  repainting a destroyed menu once a second for the whole 15-second revert
  window. The manifest grew from 42 to **48**.

  Applying the clamp helper to XFE alone silently broke `BlendHexColor` and
  `CenteredPosition`, which had been byte-identical. `Validate-SharedParity.ps1`
  caught it immediately — the check earning its place on its second day.

- **Proposed, not done:** `INI_READER_MIGRATION.md` scopes replacing the
  composed `ClampInt(ToInt(IniReadS(...)))` idiom with XFE-style typed readers.
  That idiom states each default twice and is where the `[Splash]` defect above
  came from; XFE's shape makes it unrepresentable rather than merely detectable.
  47 call sites in the shell-replacement tree, and not purely mechanical, so it
  wants its own pass.

**Not verified:** everything behavioural. The Quick Menu paint path, the HDR
fallback on a display without Advanced Color, log rotation actually rolling at
256 KB, and `PreviousShell` restore have all been validated as *code* and none of
them as *behaviour*. `PreviousShell` in particular rewrites the Winlogon shell
value and should only be exercised on a machine you can roll back.

## 1.7.4 — 2026-07-31

- Advanced the settings schema from 12 to 14 for Quick Menu accent options and
  desktop-wide automatic mouse mode/exclusions. Existing values are preserved;
  only missing keys receive defaults during migration.
- Removed the 512-entry display-mode enumeration ceiling that could truncate a
  modern GPU/4K TV's driver list at 1280×1024. Resolution selection now reads
  until Windows reports the true end and logs reported/retained mode counts.
- Replaced the Quick Menu's 28 flat label/value controls with one opaque GDI+
  row surface. The selected row now has an antialiased rounded fill, accent
  outline, left accent bar, and soft glow matching the new design reference.
- Rendered that surface at the control's physical pixel size for high-DPI
  sharpness, retained ClearType by keeping it opaque, and delete each replaced
  bitmap so navigation cannot leak a GDI object per repaint.
- Added a live Quick Menu accent setting shared by standalone and XFE: nine
  presets plus a custom `RRGGBB` value. The selected fill is derived from the
  accent so non-blue colors remain visually coherent.
- Prefer Windows 11's composited DWM corners, with `WinSetRegion` retained as the
  Windows 10 fallback.
- Matched the reference more closely after hardware review: changed the panel
  base from Steam blue-black to neutral charcoal, reserved bitmap padding so
  first/last-row glow is not clipped, strengthened and DPI-scaled that glow, and
  suppressed both the native border style and Windows 11's DWM border color.
- Let both recovery dialogs auto-size their wrapped reason text instead of
  clipping long restore errors inside a fixed 56-pixel control.
- Darkened the neutral panel base to `#242424` after the first visual pass, and
  made row-bitmap swaps/page changes redraw atomically with `RDW_NOERASE` so
  navigation no longer flashes the control background between frames.
- Changed unselected labels and values from blue-gray to neutral gray. A custom
  exterior shadow remains intentionally omitted so the menu can stay one opaque,
  non-layered window.
- Made desktop restoration destroy and flush the Quick Menu's compositor surface
  before Steam closes, then block recreation during the shutdown wait. A normal
  hide could leave a non-interactive image of the title, rows, and footer behind
  when the Windows desktop became visible.
- Fixed automatic mouse mode crashing when it first tried to unhide a hidden
  cursor: `PollController()` now declares `MouseHidden` global before reading
  and assigning it.
- Made an `explorer.exe` automatic-mouse entry cover the complete Windows shell
  family, including Start and Search surfaces hosted by separate Windows 10/11
  processes.
- Made **Return to SteamShell** launch Steam Big Picture automatically instead of
  resuming an empty guarded presentation and immediately showing recovery. The
  return transition also destroys the Quick Menu surface to prevent a stale
  compositor image.
- Fixed both recovery headings being vertically clipped at high DPI by creating
  their controls with the large title font instead of resizing an s11 control
  after layout measurement.
- Added desktop-wide automatic mouse mode. It is enabled by default only while
  Explorer owns presentation, has an explicit game/application exclusion list,
  and returns to the conservative allowlist in SteamShell/Big Picture mode.
- Added a checked **Automatic Mouse Throughout Desktop** tray item that persists
  the desktop-wide toggle without deleting either executable list.
- Stopped retaining a hidden Quick Menu HWND between open sessions. Closing the
  menu now detaches its bitmap and destroys the window, preventing DWM from
  resurrecting a stale, non-interactive menu image when a fullscreen game exits.
  Atomic repainting remains active for row and page changes while the menu is open.
- Locked the complete source, documentation, tests, build inputs, assets, and
  SHA-256 manifest in `../releases/1.7.4/`.

## 1.7.3 — 2026-07-31

- Added **automatic mouse mode**. `[Controller] AutoMouseExeList` names
  executables where the View/Back mappings apply without holding View/Back, edited
  from Settings ▸ Controller & Cursor. Empty by default; naming an executable is
  the entire opt-in.
- Implemented it as a **virtual View/Back hold** rather than a second input mode.
  The existing mappings are already a complete desktop mouse — right stick moves,
  left stick scrolls, D-pad arrows, RB left-click, RT right-click, Start opens the
  Start menu — so there was nothing to design and no parallel keymap that could
  drift from the configured one. What happens automatically is exactly what
  holding View/Back does.
- Evaluated it **after** the Quick Menu and Full Settings chords, which read the
  real button state. That is what keeps a misconfigured list recoverable: name a
  game by mistake and the controller becomes a mouse inside it, but both chords
  still work, so the list can be corrected without a keyboard.
- Added `[Features] EnableAutoMouseMode`, on by default, as a kill switch that
  is independent of the EXE list. Disabling a feature should not require deleting
  the configuration that took effort to build, and it is checked ahead of the
  result cache so turning it off takes effect on the next poll.
- Unhid the cursor when the mode engages. Moving a pointer that cannot be seen is
  not a usable mode.
- Settings schema is now **12**. The only changes are the two new keys, which
  `SyncSettingsIniSchema` adds to existing files with their defaults, so
  upgrading changes no existing value.

## 1.7.2 — 2026-07-31

Field fixes from hardware testing, a recovery-path audit, and the logging and
input-feel work that came out of both. Settings schema stays at 10: nothing here
adds or retires an INI key, so upgrading from 1.7.1 involves no migration.

- Made the desktop-restore failure screen **controller-navigable**. It was a
  native `MsgBox`, which the controller poll loop has no handling for, so
  answering it needed pointer emulation — hold View/Back, right stick, mapped
  click — and only if controller mouse or the Quick Menu happened to be enabled.
  That is the more severe of the two recovery states: Explorer may be dead, so
  there is no taskbar and no other application to reach. It now matches the
  Steam-did-not-start screen, which was already a controller-first GUI, and both
  share one input handler.
- Surfaced warnings in the Quick Menu footer. `ShowNotification` is log-only by
  design — the old bottom-corner overlay was distracting and is not coming back —
  but that left 52 warnings visible only to someone who opens the log, which on a
  couch device is nobody. A message now displaces the button hint for four
  seconds when the menu is open, and the hint returns on its own. Matches XFE's
  `SetStatus`.
- Stopped writing to RTSS on **every press** of the Custom FPS row. Each press
  was a `LoadProfile` + `SetProfileProperty` + `SaveProfile` — a disk write —
  plus `UpdateProfiles`, so the limiter was genuinely reconfigured a dozen times
  while scrolling and the frame rate chased the number. The value is now held
  pending, the row shows it immediately, and RTSS is written once the user stops.
- Restored the **native Windows menu** on tray right-click, matching XFE.
  Double-click still opens the Quick Menu via the menu's default item. The
  interception that replaced right-click with the Quick Menu existed because a
  native menu freezes controller polling — true, but it had the context
  backwards: reaching a tray icon means using a pointer, and a controller user
  opens the Quick Menu by chord or hotkey. It optimised for a case that barely
  happens at the cost of the one that happens constantly. The freeze is accepted
  rather than forgotten, and the validator now asserts the interception has *not*
  returned so it cannot come back by accident.
- Replaced press-count escalation with **hold-to-repeat**. Growing the step after
  several quick presses meant tapping quickly silently changed what a tap did —
  the same gesture produced 1, 5 or 10 depending on timing the user could not
  see. A press is now always exactly one step, however fast presses arrive.
- Made speed come from **holding**, and accelerated the repeat *rate* rather than
  the step: 80 ms, then 40 ms after 1.2 s, then 20 ms after 2.5 s. Every change
  stays 1, so the value is predictable and can be stopped exactly where wanted;
  holding just delivers more of them. This also removed grid-snapping, which only
  existed to make large steps land on round numbers.
- Limited repeat to rows whose value is a **number**, not a list. Scrubbing audio
  output or resolution at fifty changes a second would be useless and would fire
  real device work per step.
- Cancelled a pending value when a preset is chosen. Without it, the deferred
  commit could fire *after* the preset and overwrite it. Save Limit to Profile
  flushes it instead, so the profile gets the value on screen rather than a stale
  one.
- Stopped the window engine centring **dropdown menus and other popups**. They
  are real top-level windows, so nothing excluded them, but centring one is
  actively wrong rather than untidy: a dropdown is positioned relative to the
  control that opened it, and moving it to the middle of the screen detaches it
  from its parent. Centring had no size or structure test at all — its only
  condition was being more than two pixels off centre, whereas maximising has
  always been gated by `MinWidthPercent` *and* the window having a maximise box.
- Filtered those by **structure rather than name**: child windows, non-activatable
  windows, captionless windows below a size floor, small tool windows, and the
  classic popup classes. A class blacklist alone cannot keep up, since every UI
  framework invents its own popup class, while the styles that make something a
  popup are the ones Windows itself uses to decide it is not a normal application
  window.
- Used **size, not ownership**, as the discriminator for captionless windows. The
  first attempt required the window to be owned as well, reasoning that a dialog
  is owned but keeps its caption. That fixed Explorer's dropdowns and missed
  Qt's — PCSX2's menus are unowned and passed straight through. Ownership is a
  framework detail; size is not. A dropdown is small, a borderless game fills the
  screen, and a captioned window is exempt entirely so small dialogs are still
  centred.
- Added a diagnostic line recording what the engine centred and why it qualified
  — process, class, size, style, exStyle, owner — under `GameLogMode=DIAGNOSTIC`.
  Two rounds of this bug were diagnosed by guessing at the UI framework instead
  of reading the window; the next one names itself.
- Gave every operational log line a **timestamp and a level**, matching XFE.
  Standalone's `LogLine` added neither, so the log recorded what happened but not
  when — two lines could be a second or an hour apart with nothing to say which,
  and elapsed time is exactly what a startup stall, a focus handoff, or a
  sustained-exit window has to be reasoned about in. The only timestamped lines
  were the game-score rows, which stamped themselves.
- Split `LogRawLine` out for that game-score table. It is columnar and formats
  its own leading timestamp, so a second prefix would misalign every row.
  `ShowNotification` now passes its level to `LogLine` instead of embedding
  `NOTICE [Warning]:` in the message text.
- Logged **what holds the foreground** when the Quick Menu fails to take it. The
  existing lines reported only that the handoff failed, which is not actionable:
  a game holding focus, Steam holding it, and a Windows surface holding it need
  completely different responses. The line now names the process, window class,
  size, and whether it covers its monitor — an exclusive-fullscreen game is the
  usual reason the handoff is refused, and that cannot be told from a borderless
  one by process name alone.
- Deliberately did **not** add further retry attempts. The handoff is refused by
  rule rather than by timing, so more attempts do not change the outcome, and
  against a game that re-asserts itself they become a focus fight — which on an
  exclusive-fullscreen title means repeated minimise/restore churn, worse than
  the problem being solved. The reasoning is recorded at the call site.
- Fixed **Save Limit to Profile** reporting `No game in foreground` while a game
  was plainly running and the Task Switcher was listing it. The row used only the
  raw foreground window captured when the Quick Menu opened, and that is
  regularly `steam.exe` — the window engine's Steam refocus can pull Big Picture
  forward moments beforehand, and a borderless game can sit behind a Steam
  surface. Both are excluded on purpose, so the row went blank. It now falls back
  to the window engine's detected game, which is the same detection driving Game
  Foreground Assist and what the Task Switcher reflects.
- Made that row say what it saw. `Steam in front, no game detected` and
  `No game in foreground` are different problems, and this row is the only place
  the difference is visible. The save also logs both candidate sources.
- Corrected the RTSS page's footer hint, which still read `Left/Right Off/On`
  after the Frame Limit row replaced the separate limiter row.

## 1.7.1 — 2026-07-31

Startup reliability, live RTSS frame-cap control, and a codebase audit. Settings
schema stays at 10: nothing here adds or retires an INI key.

- Added a live **Frame Limit** row to the Quick Menu's RTSS page, cycling
  `Off · 30 · 40 · 60 · 90 · 120 · Custom` with Left/Right. Selecting Custom
  reveals a **Custom FPS** row beneath it for any value. Written through
  `SetProfileProperty` / `SaveProfile` / `UpdateProfiles` on `RTSSHooks64.dll`,
  which the integration now resolves alongside the existing read exports; all
  three are optional, so an RTSS build without them keeps overlay and limiter
  control and shows the cap read-only rather than failing outright.
- Folded the separate **Frame Limiter** row into that one row wherever live DLL
  control is available. RTSS has two independent mechanisms — a global
  limiter-disabled flag and a per-profile `FramerateLimit` — and surfacing both
  meant two rows that could each mean "no limiting". The shortcut fallback path
  still shows both, because without the DLL there is no value to fold in.
- Mapped "Off" to the limiter **flag**, never to the value. Writing 0 would
  discard the user's number, so an off/on round trip would silently forget 72
  and come back uncapped; clearing the flag leaves 72 in the profile, and
  cycling back on restores it instead of jumping to the first preset.
- Restricted every frame-cap write to the **global** profile. Per-game profiles
  are the user's own tuning, and a quick menu that writes whichever profile
  happens to be in the foreground can silently change a game's configuration.
- Escalated the Custom FPS step 1 → 5 → 10 on consecutive presses, resetting on
  any pause or reversal. Quick Menu navigation is edge-triggered and nothing in
  the menu auto-repeats, so the existing fixed step of 1 needed sixty presses to
  get from 60 to 120.
- Added a **Save Limit to Profile** row that copies the current global frame cap
  into the foreground executable's own RTSS profile, with that executable's name
  shown in the value column. The name comes from what owned the screen before
  the menu opened, since asking once the menu is up always answers SteamShell;
  Steam's own surfaces are excluded, because a profile named `steam.exe` caps
  the client rather than a game.
- Made that write surgical rather than a clone. The target profile is loaded
  first so any other tuning the user has done for that game survives, and only
  `FramerateLimit` is replaced. It is also the only place a per-game profile is
  ever written, it requires the existing two-press confirmation, and it restores
  the global profile afterwards so the Frame Limit row keeps reading the value
  it is supposed to show.
- Updated the Quick Menu RTSS parity assertions in `Validate-SteamShell.ps1`
  and `Validate-SteamShell-XFE.ps1`, which still described the removed
  `rtssLimiterState` row. They now assert the combined Frame Limit row, the
  conditional Custom FPS row, and Save Limit to Profile, so the guard protects
  the current design instead of blocking the build on the old one.
- Stopped the startup curtain from burying SteamShell's own windows. The splash
  guard re-asserted topmost every `SplashTopmostGuardMs`, and since Full
  Settings, the Quick Menu and the Steam recovery screen are also topmost, the
  curtain won every half second and buried whatever the user had just opened.
  It now yields while any of those is visible; the curtain stays up and its
  close timer is untouched. This mattered because those windows are the only
  ways out of a stuck curtain on a handheld with no keyboard — the recovery
  screen reached by the startup fix above was being covered by the very thing
  it existed to escape.
- Gave the controller Full Settings chord a hold requirement, a yield, and an
  early return. It fired on the press edge from above the poll's consumer
  gates, so a stray grip during play could throw Full Settings over a running
  game, and pressing it with the Quick Menu open produced a focused Settings
  window that ignored input while the Quick Menu behind it kept receiving every
  button. It now matches the Quick Menu chord's hold, declines while another
  surface owns controller input, and returns once fired. The chord state is
  also cleared at both existing discard points, so a disconnect mid-hold cannot
  complete a stale chord on reconnect.
- Stopped re-issuing the limiter flag write when the Frame Limit row is already
  at `Off`. Left clamps to that entry at the end of the list, so every further
  press repeated the `SetFlags` call and re-showed its notification.
- Removed the Quick Menu handler cases left dead by the Frame Limiter row
  merge (`rtssLimiterState`) and a set of older ones no longer produced by any
  row (`audio`, `rtss`, `rtssOn`, `rtssOff`, `framecap`, `framecapOn`,
  `framecapOff`). `case "audio"` was shared with the live `audioOutput` and only
  the dead label was dropped; the identically named case in the Quick Menu
  order-label mapper is unrelated and untouched.
- Removed 16 unreferenced functions, including a theming chain
  (`ApplySteamShellTheme` → `ApplyModernWindowStyle` → `ColorRefFromRgb`,
  `ThemeNativeControl`) and a geometry chain (`GetClientRectPx`,
  `ForceGuiFullscreen`, `GetGuiClientSize`, `GetPrimaryMonitorRect`) that only
  referenced each other. `Validate-SteamShell.ps1` mentions
  `ApplyModernWindowStyle` in a `-notmatch` assertion, which still passes.
- Declared the frame-cap status-control handles at script scope. Rows 5-8 were
  added later and existed only as in-function declarations, making them ordinary
  globals while rows 1-4 were super-globals; the writes are inside `try` and the
  guard tests only row 1, so an undeclared handle would have silently stopped
  updating rather than failing. Same for `ControllerMapGui`,
  `g_ControllerMapUI`, `_ShortcutCap`, and the Control Panel speed controls.
- Declared `AudioPeakThreshold` and `DEFAULT_AUDIO_PEAK_THRESHOLD` with
  `global`, matching every other script-scope variable. Without it a function
  reading them without its own declaration would get an empty local.
- Cached the global `FramerateLimit` read for 400 ms, on the same reasoning as
  `IsSteamRunning`: the row is evaluated once per repaint and every miss costs a
  `LoadProfile` plus a `GetProfileProperty` round trip. The cache is dropped
  after any write so the row can never show a value it just replaced.

- Judge Steam's startup by a **Big Picture surface** rather than by
  `ProcessExist("steam.exe")`. The process appears almost immediately and then
  sits on a "Connecting", sign-in, or client-update window for as long as the
  network takes, which on a Wi-Fi handheld is long enough to matter and on a
  wired HTPC never is. Treating the bare process as success set
  `SteamObservedRunning` on the first monitor tick, and because every branch
  that can raise the recovery screen is nested under `!SteamObservedRunning`,
  that screen became permanently unreachable — with the startup curtain up, the
  result was an indefinite black screen on a machine whose only shell is
  SteamShell.
- Added `SteamBpmSurfacePresent`, a startup-strength companion to
  `WindowEngineFindBpm`. The existing matcher is deliberately permissive (a
  4096 px floor is right for "find something worth refocusing") and Steam's
  startup dialogs clear it easily, so startup now requires a Steam-owned window
  covering `SteamStartupSurfaceMinCoverage` (0.6) of its monitor in both
  dimensions. Coverage rather than title keeps this working across client
  updates, renamed or localized titles, and the steam.exe/steamwebhelper.exe
  ownership split.
- Latched `SteamObservedRunning` explicitly: it is set once and never cleared,
  so a game covering, replacing, or minimizing Big Picture cannot re-open the
  startup path mid-session.
- Stopped the recovery screen's guards from dismissing themselves on a running
  process. `ShowStartupRecovery` and `ShowPendingStartupRecovery` both returned
  early when `steam.exe` existed, which is exactly the state a stalled boot is
  in; both now test for the Big Picture surface.
- Closed a trap on the recovery screen's **Retry**. `LaunchSteamBpm` latched
  `SteamObservedRunning` whenever `steam.exe` was already running, so pressing
  Retry against a stalled Steam marked the session ACTIVE, dismissed the
  recovery screen, and left the user on the black screen with no way to raise it
  again. Observation there now requires the surface too, and each attempt clears
  the one-shot startup warning so a failed retry can raise the screen again.

## 1.7.0 — 2026-07-26

- Added **desktop mode**. Exiting to the desktop no longer terminates
  SteamShell: Explorer takes the desktop back while SteamShell stays resident so
  the notification-area icon, controller-as-mouse, and Quick Menu keep working.
  Entered from the automatic Steam-exit restore, Quick Menu ▸ System, the tray,
  and the Steam-did-not-start recovery screen.
- Made the notification-area menu context-aware and gave the tray a genuine
  **Exit SteamShell**. From shell mode that exit performs the guarded desktop
  restore first, so it can never leave the user with a hidden taskbar and no
  shell.
- Took over the tray icon's right-click and opened the Quick Menu instead of a
  native Windows menu. AutoHotkey will not launch a timer thread while a menu is
  displayed, and controller polling is a timer, so the native menu froze
  controller-as-mouse for as long as it was open — a controller user could open
  the tray menu and then be unable to move the pointer onto it. The Quick Menu is
  an ordinary window and stays fully navigable by controller, mouse, and
  keyboard. The native menu is still built for the double-click default action
  and as a fallback.
- Added a **Reload Settings** row to the Quick Menu's Settings page. It was
  previously reachable only from the tray menu or Ctrl+Alt+Shift+R, neither of
  which a controller-only user on the desktop can reach.
- Registered a `TaskbarCreated` listener and re-assert the tray icon on every
  broadcast. The restore path restarts Explorer, which destroys every existing
  notification-area icon; without this the icon that desktop mode depends on
  could silently fail to come back.
- Moved tray initialisation ahead of SteamShell's own Explorer launch. Winlogon
  starts SteamShell before any shell exists, so the icon's first placement
  always fails and the broadcast is what actually places it.
- Isolated shell enforcement from controller input in `ApplyRuntimeTimers`.
  Desktop mode leaves shell monitoring, the window engine, the Taskbar Guard,
  cursor hiding/parking, and Launcher Cleanup unscheduled while keeping
  controller polling alive. No persisted setting is mutated, so returning to
  shell mode is a pure rescheduling operation.
- Explicitly disarm the Steam lifecycle when entering desktop mode. A stopped
  timer was not sufficient: `SteamLaunched` remaining true meant any reschedule
  would observe Steam as launched-but-absent and immediately re-enter the
  restore path.
- Suppressed the unexpected-exit Explorer recovery in desktop and safe modes.
  Killing SteamShell there would have restarted the user's live Explorer session
  and silently dropped SteamShell as the next-sign-in shell.
- Changed the Quick Menu's **Steam Menu** row to **Launch Steam** when Steam is
  not running. Launching from that row also returns SteamShell to shell mode;
  Steam started by hand from the desktop deliberately does not, so browsing a
  library from the desktop never yanks the desktop away. Steam Quick Access
  reports `Steam is not running` and is inert meanwhile.
- Changed the recovery screen's **Restore Desktop** from a permanent restore to
  a session restore. A single failed Steam launch no longer deregisters
  SteamShell as the Windows shell, and the permanent restore remains available
  from Settings, the Setup Assistant, and Ctrl+Alt+Shift+E.
- Made the Steam-shutdown failure paths visible. `ShowNotification` is log-only,
  so abandoning a restore with the taskbar still hidden was silent. A Steam that
  will not close within 20 seconds now offers to restore the desktop anyway.
- Stopped cursor parking and hiding from running while Explorer owns the
  desktop, and reported the active presentation mode in Health Check.
- Added a **black desktop background** (`[Features] EnableDesktopBlackout`, on by
  default). A full-screen `WS_EX_NOACTIVATE` black window supplies the pixels
  while `Progman`/`WorkerW` are hidden through the same `EVENT_OBJECT_SHOW` hook
  and one-second safety check the Taskbar Guard uses, so neither the wallpaper
  nor desktop icons show in the gaps around Steam. It deliberately owns no
  system or registry state — the wallpaper setting is never touched, and
  everything it changes dies with the process or is undone by the Explorer
  restart that unexpected-exit recovery already performs. Clearing the wallpaper
  through `SPI_SETDESKWALLPAPER` was rejected for the opposite reason: it
  survives a crash.
- Guarded the backdrop against the one failure that would matter: it is re-sunk
  to the bottom every tick, and if it is ever detected as the foreground window
  it is pushed back down and the event is logged. The blackout is released on
  every path that hands presentation back to Explorer — desktop restore, Safe
  Mode, exit cleanup, and any timer reconfiguration.
- Made the blackout toggleable from Quick Menu ▸ Settings ▸ General + Startup
  with immediate effect rather than at next boot, so a controller alone is
  enough to recover if the backdrop misbehaves on a given machine. The Quick
  Menu is `AlwaysOnTop` and stays reachable over it.
- Reported blackout state, backdrop presence, desktop visibility, and hook mode
  in Health Check.
- Advanced the settings schema to 10 for `Features.EnableDesktopBlackout`.
- Extended static validation to cover the desktop-mode contract: the
  session/permanent exit split, lifecycle disarm, timer isolation, tray
  re-assert, tray-before-Explorer ordering, the suppressed exit recovery, the
  tray right-click interception, Reload Settings remaining reachable from the
  Quick Menu, and the desktop blackout's non-activating backdrop, paint-before-
  hide ordering, release on every Explorer handoff, and controller toggle.
- Replaced the duplicated Quick Menu settings-row `case` lists with shared
  `IsQuickMenuToggleSetting` / `IsQuickMenuAdjustSetting` predicates over one
  pipe-separated source of truth. AutoHotkey v2 allows at most 20 values per
  `Case`, and the longer list had reached that ceiling. Static validation now
  rejects any `Case` carrying more than 20 values, counts the predicates' id
  lists as activation coverage, verifies both switches still consult them, and
  reports a dispatch entry whose Quick Menu row no longer exists.
- Taught static validation to reject an `else` attached to a braceless `try`
  if-body, which AutoHotkey v2 cannot parse. `Loop`/`While`/`For` are excluded
  because v2 gives those their own legitimate `Else` clause.
- Promoted the desktop-mode build to SteamShell 1.7.0 and preserved its source,
  build files, assets, documentation, tests, and checksum manifest in
  `../releases/1.7.0`.

## 1.6.0 — 2026-07-26

- Ported the applicable SteamShell-XFE presentation refinements without changing
  the standalone shell, taskbar, Explorer, or focus-engine ownership model.
- Reworked the Quick Menu into an open-session repaint-in-place overlay with
  filled selection rows, tighter geometry, keyboard navigation, and
  reveal-before-shape DPI handling so rounded regions cannot clip high-scale
  displays. Closed menu sessions are now destroyed rather than retained hidden.
- Added live RTSS global overlay/limiter state and direct control through
  `RTSSHooks64.dll`, including the foreground profile's actual frame limit.
  Existing HotkeyHandler shortcuts remain the automatic compatibility fallback.
- Replaced the blind HDR shortcut with live primary-display Advanced Color state
  and explicit Off/On control, retaining Win+Alt+B as an honest fallback.
- Added primary-display Windows Scale control with the existing 15-second safety
  rollback and delayed Quick Menu re-centering after DPI changes.
- Added a configurable left/right mouse-parking edge and fixed all mouse
  observation to use screen coordinates.
- Added a standalone SteamShell icon, notification-area menu, and default icon
  embedding in Windows builds.
- Added a double-clickable Windows build launcher that preserves and displays
  the PowerShell build's real exit code.
- Advanced the settings schema to 7 for `MouseParkEdge` and
  `RTSS.UseDllIntegration`.
- Added an all-category Full Settings geometry audit that logs invalid,
  unregistered, overlapping, or horizontally out-of-bounds native controls,
  plus validation against duplicate persistent settings bindings.
- Kept the expanded static validator compatible with inbox Windows PowerShell
  5.1 by using trailing binary operators for multiline regex expressions, and
  corrected its trailing-whitespace regex so lines ending in `t` are not
  reported as false positives.
- Removed a duplicate `MouseParkEdge` global declaration that AutoHotkey v2
  rejected at load time, taught static validation to detect duplicate
  per-function globals, and made build-time interpreter diagnostics visible.
- Made Ahk2Exe builds print the selected compiler, base, output, icon, exit
  code, and captured compiler diagnostic instead of returning an opaque
  missing-output error.
- Added **Register Current EXE as Shell** to Advanced & Logging for portable
  deployments. It verifies the exact compiled path in the current-user
  Winlogon `Shell` value, preserves recovery metadata, and creates the
  emergency Explorer-restore shortcut without copying the EXE.
- Matched the standalone Quick Menu presentation to XFE's final borderless
  layout, removed its DWM backdrop frame, and batched page construction while
  redraw is disabled so page changes appear fully composed.
- Capped Full Settings at 660 logical pixels, based its monitor-fit calculation
  on the native GUI DPI instead of Steam's virtualized DPI, widened field-label
  columns, and reorganized Advanced actions into an aligned two-column grid.
- Replaced Full Settings' utility-window chrome with a standard title bar:
  Close and Minimize are available, Maximize remains disabled, and vertical
  resizing is preserved.
- Matched XFE's Quick Menu main page row-for-row with Steam Menu, Steam Quick
  Access, Game Bar, and descriptive right-column summaries in place of generic
  arrows and standalone-only return/focus rows.
- Added configurable Steam Menu, Quick Access, and in-game overlay shortcuts,
  including a schema-8 migration that gives existing installations the new
  main-page order while retaining applicable hidden-row preferences.
- Ported XFE's foreground-thread handoff to Quick Menu, with one delayed retry,
  so Steam Big Picture no longer retains focus and processes menu navigation at
  the same time.
- Kept the useful standalone keyboard split while porting XFE's Quick Menu
  behavior: `Ctrl+Alt+Shift+Q` opens Quick Menu, `Ctrl+Alt+Shift+S` opens Full
  Settings, and `Ctrl+Alt+Shift+P` remains dedicated to Control Panel.
  Focus-gated Quick Menu keyboard navigation is protected by static validation.
- Replaced the remaining legacy Audio, Display, and RTSS Quick Menu submenus
  with XFE's row sets and behavior. Display now stages Resolution, Refresh rate,
  and Scale independently and applies them as one 15-second guarded transaction.
- Fixed shortcut presentation so the `+` separator inserted by `Ctrl+` is not
  mistaken for an AutoHotkey Shift modifier; Steam Menu and Steam Quick Access
  now correctly display Ctrl+1 and Ctrl+2.
- Ported XFE's paced `SendEvent` delivery for the in-game Steam overlay, giving
  Steam's hook enough modifier-down time to reliably observe Shift+Tab.
- Split Task Switcher selection into A for a one-time switch and Y for an
  explicit switch-and-lock, while retaining X close/hold-to-force-close.
- Added a default-on **Run SteamShell as administrator on startup** setting
  under Startup & Splash. Disabling it takes effect next launch and warns that
  Windows may block controller mouse/input control of elevated applications.
- Advanced the settings schema to 9 for the administrator-startup preference.
- Clarified the Task Switcher footer so the X close action also advertises
  hold-X force-close.
- Kept Settings' automatic right-stick/RB pointer mode active across its native
  dialogs and SteamShell companion windows, while keeping category navigation
  and save actions scoped to the main Settings window.
- Promoted the completed parity build to SteamShell 1.6.0 and preserved its
  source, build files, assets, documentation, tests, and checksum manifest in
  `../releases/1.6.0`.

## 1.5.0 — 2026-07-25

- Replaced independent geometry and focus timers with one coordinated window engine.
- Added one shared, validated window inventory for geometry, focus, Task Switcher,
  AlwaysFocus, game detection, and Launcher Cleanup window heuristics.
- Added bounded state-aware center/maximize corrections.
- Added a single focus priority: pinned task, AlwaysFocus, game, then Steam.
- Replaced per-candidate WMI CPU queries with cached Win32 `GetProcessTimes` samples.
- Added Quick Menu coordinated status, Health Check diagnostics, and engine-focused
  Windows tests.
- Added schema 5 settings refinement: coordinated-engine cadence and retry values now
  use safe internal defaults, shell monitoring is independently scheduled, logging
  uses one mode selector, and dependent controls disable when irrelevant.
- Clarified RTSS's display-only frame-cap value and AlwaysFocus's intentional Steam
  exclusion.
- Lowered the default controller stick deadzone from 8000 to 4000 while preserving
  existing user-selected values.
- Expanded pre-build validation to audit Settings and Quick Menu schema bindings,
  named callbacks, menu dispatch, controller-deadzone migration, and the verified
  desktop-restore path.
- Moved Full Settings category switching from LB/RB to LT/RT and restored RB's
  configured short action for right-stick pointer clicks.
- Replaced destructive TabTip/TextInputHost restarts with a Windows touch-keyboard
  presentation request, plus TabTip startup and `/SeekDesktop` fallbacks.
- Added a short geometry settle period and a fresh bounded retry budget when an
  application changes its own startup geometry, avoiding premature suppression.
- Restored the 1.2/1.3 administrator relaunch so controller input and window
  management can interact with elevated Windows surfaces. The handoff now
  preserves command-line modes and safely continues non-elevated if it fails.
- Routed both modern touch-keyboard executable fallbacks through Explorer's
  desktop automation so TabTip does not inherit SteamShell's administrator
  token; classic OSK remains the recovery path when that launch is unavailable.
- Added schema 6 foreground tuning: Responsive (55) is the new default, while
  Balanced (60), Conservative (70), and pre-existing custom values remain
  selectable or preserved in Full Settings.
- Moved the Full Settings Window Management toggle into Focus & Windows,
  changed the maximize-width control to a readable percentage, and normalized
  decimal serialization so binary floating-point noise no longer appears in
  the INI.
- Replaced taskbar hiding inside Steam process polling with a dedicated
  event-driven Taskbar Guard plus a one-second safety check. Desktop restore,
  Safe Mode, and process cleanup explicitly stop the guard before showing the
  normal shell.
- Restored the pre-engine partial-title behavior for Big Picture and tightened
  Steam fallback blockers so minimized, off-screen, tiny, non-activating, and
  auxiliary Steam windows cannot indefinitely reset the refocus timer.
- Expanded Window Engine diagnostics to identify the executable and title
  currently blocking Steam fallback, and Health Check now reports Taskbar
  Guard mode and visibility.
- Changed automatic cursor parking from synthetic mouse input to `SetCursorPos`,
  preserving Windows' idle clock and automatic sleep while retaining hover
  cleanup after real focus changes. Health Check now reports last-input age.
- Made cursor parking follow the observed non-Steam-to-Steam foreground
  transition, including cases where Steam restores itself without a
  SteamShell activation. Parking now waits once for the focused window to
  settle, targets that window's actual monitor edge, verifies the result once,
  and cancels if the user supplies new Windows input or changes applications.
- Added guarded legacy-game surface recognition for older DirectX titles whose
  main window is untitled or marked as a ToolWindow. Qualifying windows now
  participate in Task Switcher, game focus, AlwaysFocus, Steam-refocus blocking,
  and Launcher Cleanup game detection without admitting small overlays.
  Minimized captionless popup surfaces can also be restored as exclusive-
  fullscreen games, while ordinary minimized applications remain manual
  Task Switcher entries.
- Promoted the coordinated window-engine build to the stable 1.5.0 release and
  preserved its complete source release in `../releases/1.5.0`.

## 1.4.0

- Frozen known-good baseline before the coordinated window-engine rewrite.
- Source, settings sample, validation/build scripts, documentation, checksums, and
  test checklist are preserved in `../releases/1.4.0`.
