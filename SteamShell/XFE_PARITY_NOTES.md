# SteamShell / XFE parity notes

This file records the July 2026 parity review. It began when `SteamShell-XFE/`
was a source reference only and standalone changes belonged in `SteamShell/`;
since 1.7.1 / 0.1.15 that is no longer true. See *`SteamShell-XFE/` is no longer
only a reference* at the end.

**`SteamShell-XFE/` no longer exists as a directory.** Both trees, the shared
file, both validators and the one build script live in `SteamShell/`, so a
release is a copy of one folder. Where this document says `SteamShell-XFE/` it
is describing the layout at the time, and the file it means is now
`SteamShell/SteamShell-XFE.ahk`. Frozen snapshots under `releases/` keep the
two-folder layout they were locked with.

## Ported to standalone SteamShell

- XFE's final borderless Quick Menu geometry, open-session window/control pool,
  compact footer hints, keyboard navigation,
  redraw-suspended page composition, and reveal-before-measure/shape DPI fixes.
- The post-1.7.3 Quick Menu render layer and accent palette were implemented in
  both trees together: one opaque, physical-pixel-sized GDI+ surface; rounded
  selected fill; accent outline, bar, and padded DPI-scaled glow; neutral
  `#242424` charcoal base; atomic no-erase bitmap/page redraws;
  neutral-gray unselected text; border-suppressed Windows 11 outer corners; and the same preset/custom
  accent model. Both trees destroy the closed menu HWND rather than retaining a
  hidden DWM surface across fullscreen transitions. `QuickMenuRowValueText()` isolates
  the only painter difference: standalone resolves values live while XFE rows
  already carry their rendered value.
- XFE's exact top-level Quick Menu row set and descriptive value column,
  configurable Steam Menu/Quick Access/overlay shortcuts, and foreground-thread
  handoff so Steam Big Picture does not navigate behind the menu.
- XFE's Audio, Display & HDR, and RTSS & Performance submenu row models,
  including independent staged resolution/refresh/scale selection and a single
  guarded Apply transaction.
- XFE's Quick Menu keyboard routing and navigation. Standalone intentionally
  keeps its distinct `Ctrl+Alt+Shift+P` Control Panel shortcut because
  `Ctrl+Alt+Shift+S` already opens Full Settings.
- Standalone notification-area and executable icon, tray recovery actions, and
  build-time icon embedding, plus the double-clickable Windows build launcher.
- XFE's *usable* notification-area icon, which required the standalone shell to
  survive a desktop restore. SteamShell now has a desktop mode: Explorer takes
  the desktop back while SteamShell stays resident for the tray icon, controller
  mouse, and Quick Menu. XFE gets this for free by never owning the shell;
  standalone had to add an explicit mode with a `TaskbarCreated` re-assert,
  because its own restore path restarts Explorer.
- Desktop-wide automatic mouse and its tray toggle remain standalone-only: they
  are keyed to that explicit Explorer-owned desktop mode. XFE never performs a
  SteamShell-to-Explorer presentation transition. XFE briefly had an equivalent
  and schema 11 removed it; see *A second one that should have matched* for why
  the stand-in for `DesktopMode` could not be made correct.
- Live RTSS global Overlay and Frame Limiter state/control through
  `RTSSHooks64.dll`, foreground-profile `FramerateLimit`, and automatic
  HotkeyHandler fallback.
- The **combined Frame Limit row** (Off · 30 · 40 · 60 · 90 · 120 · Preset · Custom), the
  conditional Custom FPS row with hold-to-repeat, and **Save Limit to Profile**.
  This one was *not* a port in either direction: it was designed once and applied
  to both trees in the same pass, so the behaviour is identical apart from the
  refresh model. XFE rebuilds its whole row list on every repaint, so the Custom
  row appears on its own; standalone composes rows separately and needs an
  explicit rebuild on the transition into and out of Custom.
- Live primary-display HDR state with explicit Off/On control and Win+Alt+B
  fallback when Advanced Color state is unavailable.
- Primary-display Windows Scale selection with the existing 15-second guarded
  rollback and delayed Quick Menu re-centering.
- Screen-coordinate cursor observation and selectable left/right parking edge.

## Already at parity or stronger in standalone

- Startup black/video presentation and startup-program window modes.
- Full Settings categories, controller shortcut recording, immediate Quick Menu
  settings writes, topmost dialog handling, and monitor-aware Settings sizing.
- Task Switcher one-shot selection, explicit Y focus lock, close/force-close
  behavior, and legacy/tool-window game handling.
- Audio output, volume, mute, display-mode safety revert, health checks,
  diagnostics, and controller mapping.

## Deliberately not ported

- RawInput/GameInput controller learning and device hand-over. Those solve Xbox
  FSE withholding background XInput; standalone owns the foreground and its
  established XInput path does not have that failure mode.

  **This rationale is now only half the story.** It answers the FSE question and
  nothing else, and a second reason to port has since appeared: a controller in
  DirectInput mode — measured on an 8BitDo Ultimate 2 — **is not an XInput device
  at all**, so standalone does not see a degraded controller, it sees nothing.

  **Taken, August 2026.** RawInput, the profile store and the Learn Controller
  wizard are in `SteamShell-Shared.ahk` and both products use them. See *RawInput
  and the Learner, ported* below.

  The Settings chord condition attached to this port was **missed when the port
  was made and fixed afterwards**, which is the argument for writing conditions
  down: standalone required `LT+RT+LB+RB+L3+R3`, and non-XInput backends report
  both triggers on one shared axis where they cancel out, so that chord is
  physically unreachable on the very controller the port exists for — and it is
  the only keyboardless route to Full Settings. Standalone now uses XFE's
  `LB+RB+L3+R3`, triggers ignored rather than forbidden.
- XFE Game Focus Lite, Steam Assist Lite, and Launcher Cleanup Lite. Standalone
  already has the coordinated Window Engine and full Launcher Cleanup.
- XFE task-switcher activation rules and Steam-return workarounds. Standalone
  owns presentation and already has focus pinning and guarded legacy surfaces.
- Companion Disable/Enable. Pausing a utility companion is safe; pausing the
  standalone shell while it owns Explorer/taskbar state is not. Desktop mode is
  the standalone equivalent: it hands presentation back to Explorer through the
  guarded restore rather than pausing SteamShell in place, and it is reversible
  from the same tray menu.
- XFE startup-curtain semantics. The presentation-only companion curtain was
  retired in XFE 0.1.19 because AnyFSE starts Steam before the companion, making
  the cover inherently late. Standalone's splash remains part of its actual
  Steam startup lifecycle.

## Release boundary

The standalone and XFE working trees are both **2.0.3** and are locked together
in the self-contained `releases/2.0.3/` bundle. Standalone uses settings schema
23 and XFE uses schema 18. The earlier `releases/1.7.7/` and
`releases/XFE-0.1.21/` snapshots remain intact; `releases/1.7.4/` remains intact;
`releases/1.7.3/` remains the deliberate revert point immediately before the
Quick Menu rendering rewrite, and `releases/XFE-0.1.17/` remains intact.
The earlier `releases/1.7.2/`, `releases/1.7.1/`, `releases/1.7.0/`, `releases/1.6.0/`,
`releases/1.5.0/`, `releases/XFE-0.1.14/`, `releases/XFE-0.1.15/` and
`releases/XFE-0.1.16/` directories remain unchanged.

1.7.0 is the first release whose headline features have no XFE counterpart to
port from. Desktop mode and the desktop blackout exist because standalone
SteamShell owns the shell, which is precisely the thing XFE was built never to
do.

## `SteamShell-XFE/` is no longer only a reference

The rule at the top of this file — XFE is a source reference, standalone changes
belong in `SteamShell/` — **stopped holding in the working tree after 1.7.0**.
`SteamShell-XFE.ahk` now carries changes of its own:

- The combined Frame Limit row, Custom FPS, and Save Limit to Profile, designed
  jointly with standalone rather than ported either way.
- A bounds guard in `ControllerLearnSkip`. `ControllerLearnNextStep` increments
  unconditionally, so after the final step the index sits one past the end while
  the wizard saves — and Skip is a GUI button, clickable in that window. It threw
  `Invalid index: 23` on hardware.
- Motion-sensor exclusion in the learner's axis search, after an 8BitDo Ultimate 2
  put six free-running 16-bit motion axes into a 34-byte report and won every
  axis step.
- Removal of the handler cases and functions left dead by the row merge.
- Matching updates to `Validate-SteamShell-XFE.ps1`, whose RTSS parity assertions
  still described the removed `rtssLimiterState` row.

All of the above is locked at `releases/XFE-0.1.15/`. **0.1.16** adds the
RTSS frame-cap input work — the debounced write and hold-to-repeat — again
designed once and applied to both trees in the same pass, and is locked at
`releases/XFE-0.1.16/`. Earlier snapshots are untouched.

The shared Quick Menu renderer, closed-window teardown, recovery-layout fixes,
and complete driver-mode enumeration are locked at `releases/1.7.4/` and
`releases/XFE-0.1.17/`. Standalone 1.7.4 additionally contains desktop-wide
automatic mouse mode and its Explorer/Start/Search integration.

So the rule at the top of this file now reads: **XFE is a parallel tree, not a
reference.** Changes that belong to both — the Frame Limit row is the first —
are designed once and applied to both in the same pass, and each keeps its own
version and its own locked release.

## August 2026 cross-tree audit

A mechanical diff of every shared function found that of 143 shared names, only
42 were identical once indentation was normalized. Most of the remaining 101 are
legitimately different — the page models, desktop-mode gating. (`SetStatus`
versus `ShowNotification` was cited here as an example and should not have been;
see the correction below.) These were not, and have been corrected in both trees:

- **Build exit codes.** XFE's build script documents that `$LASTEXITCODE` is
  unreliable for GUI-subsystem executables and uses `Start-Process -Wait
  -PassThru`; standalone used the call operator. Standalone now matches, and
  both reject a stale output EXE.

  Tested on hardware afterwards, and the audit's original severity was wrong:
  standalone's syntax gate was *not* broken. The old code piped through
  `ForEach-Object`, and draining that pipeline synchronizes on process exit, so
  the exit code arrived correctly. On Windows PowerShell 5.1.26100 with
  AutoHotkey 2.0.26 a broken source returned 2 through both mechanisms. Keep the
  change as hardening — it survives someone later removing the pipe — but it did
  not fix a live defect. Whatever XFE's comment was written in response to, this
  configuration does not reproduce it.
- **Log rotation.** Standalone had it; XFE had none at all, while logging one
  line per controller button edge unconditionally. XFE now has the same rotation
  (`[Companion] LogRotateMaxKB`/`LogRotateBackups`, schema 5 — moved to
  `[Logging]` in schema 18, see below) and the per-edge
  line moved behind the `DiagnosticLogging` flag that already gated the
  timer-driven diagnostic tick. Standalone's rotation no longer measures the
  file on every line.
- **Left-stick Quick Menu navigation.** XFE's `QuickMenuHandleController` took
  `lx` and `ly` and never read them, so the menu could only be driven from the
  D-pad. Standalone's stick-to-D-pad synthesis is now ported across.
- **RTSS default-path discovery.** Standalone probed the stock install location
  when `[RTSS] Path` was unset; XFE gave up. Both now route menu availability,
  launch, health reporting, and hooks-DLL lookup through one resolver, so an
  ordinary RTSS install works consistently without configuration.
- **HDR Win+Alt+B fallback — a divergence, not a gap.** The audit read the
  "ported to standalone" note above, saw XFE lacked the fallback, and filed it
  as a parity gap. That was wrong, and XFE's own validator caught it on the
  first build.

  Three independent things say it was deliberate. XFE **0.1.9** drove the HDR
  row with nothing but `SendChordSafe("#!b")` and had no DisplayConfig HDR code
  at all; **0.1.14** has twelve DisplayConfig references, no chord, and adds the
  `-notmatch` assertion **in that same release**. And the XFE README states the
  rule in user-facing terms: read the primary display's Advanced Color state
  "rather than assuming what the Win+Alt+B shortcut did", and on an unreadable
  driver/API state show **Unavailable** "without sending a blind toggle". That
  last clause is precisely the behaviour the port changed.

  So the rule is: XFE reports an unreadable state rather than guessing at it.
  The port was reverted and the divergence recorded in `SHARED_FUNCTIONS.txt`.

  What *did* survive into both trees is splitting the fallback out of
  `SetQuickMenuHdrState`'s `allowToggleFallback` flag — standalone now has an
  explicit `RequestHdrToggleFallback()`, because Win+Alt+B is a toggle and the
  flag made the requested on/off state silently meaningless.
- **Return shapes.** `GetPrimaryHdrState` now reports `wideColorEnforced` in
  both; `GetRtssFrameLimit` now reports the resolved profile and guards the
  `SplitPath` result in both.
- **Shared painter.** The GDI+ module reference is released with a matching
  `FreeLibrary`, and a failed `CreateDIBSection` is detected and logged rather
  than silently blanking the rows. Applied identically, so `EnsureGdiPlus`,
  `ShutdownGdiPlus`, and `QuickMenuPaintRows` remain byte-identical across the
  two trees.

**The thing that made all of this hard to see was formatting.** Standalone
indented with one space and XFE with four, so a raw diff of the two trees was
100% noise and the genuinely identical shared functions showed as 100% changed.
Drift was invisible by construction.

Standalone has therefore been reindented to XFE's four-space convention, and its
`switch`/`case` bodies indented to match. That change was mechanical and
content-preserving: only leading whitespace moved, the embedded default INI's
continuation section was left byte-for-byte alone, and every line's content was
verified unchanged afterwards. At that audit checkpoint all 48 manifest
functions were **byte-identical** across the two trees, where none were before.
Following later manifest additions, the current manifest contains 47.
SteamShell's 1.7.8 development line, now released as 1.9.9, deliberately removed
`OpenOSK` and `OpenWindowsSettings`
because standalone must cross its verified standard-user boundary while
normal-integrity XFE launches them directly; the manifest records that
architecture decision beside the earlier HDR exception.

### The largest deliberate divergence: privilege architecture

Standalone's elevated helper, Setup Assistant, installation layout, shell
registration, and Auto-Login have **no XFE counterpart and are not candidates for
one**. This is the biggest structural difference between the two trees and it was
not written down anywhere until now, which made it look like an omission rather
than a decision.

The reason is what each program is. Standalone replaces the Windows shell, so it
starts before a desktop exists, must cross a verified standard-user boundary to
launch anything, and needs a separate High-integrity process to reach windows
UIPI puts out of its reach. XFE is an ordinary normal-integrity companion started
from an existing desktop: it launches applications directly, never registers
itself as the shell, and has no elevated window to service. Porting the helper
would give XFE an administrator process it has no use for, and porting Setup
would give it an installer for a layout it does not have.

**Part of that list has since been reversed, and it is recorded here rather than
quietly deleted.** The original text said none of the following belonged in
`SHARED_FUNCTIONS.txt` and none should be added later: `StartElevatedInputHelper`,
`StopElevatedInputHelper`, `SyncElevatedInputHelperWithSettings`,
`ElevatedHelperLocationIsProtected`, `SteamShellPathIsAdminOnlyWritable`,
`HardenElevatedHelperDirectory`, `ControllerHandleElevatedForeground`,
`DeploySteamShell`, the `ElevatedRtss*`/`ApplyElevatedRtss*`/
`RequestElevatedRtssFrameLimit`/`WaitForElevatedRtssRequest` family, and the
`SetupAssistant*`, `RegisterElevatedHelperTask`, and Auto-Login families.

XFE now has a default-on input and RTSS helper, so three groups moved into
`SteamShell-Shared.ahk`:

- `SteamShellPathIsAdminOnlyWritable` and `ElevatedHelperLocationIsProtected` —
  the protection gate. It takes a path and an expected version and inspects
  owner, DACL and readability. It knows nothing about either program.
- `GetProcessTokenSecurity` and the token helpers, plus
  `QuoteWindowsCommandLineArg` and `StrRepeat`. "Is that process the same user,
  in the same session, at High integrity?" is one question, not two.
- The `ElevatedRtss*` request channel. Both trees ask the same helper for the
  same thing in the same words; only `ElevatedRtssRequestPath()` stays per-tree,
  because the two programs keep their data in different places.

The rest of the list stands, and the line it now draws is worth stating: **the
gate is shared, deployment remains Setup-owned.** `HardenElevatedHelperDirectory`, the
embedded payload, `ExtractEmbeddedElevatedHelper`, installation modes, the
protected on-demand task registration and every `SetupAssistant*` function
remain in `SteamShell.exe`, because they are properties of the shared installer
rather than of the normal-integrity companion. XFE has no embedded payload and
no administrator rights: it verifies and launches, or it explains why it would
not. Setup deploys the helper and registers its task in XFE mode.

`StartElevatedInputHelper` and XFE's `StartElevatedRtssHelper` also stayed
separate, deliberately. They are different launches of the same binary:
standalone passes `--product=standalone`, while XFE passes `--product=xfe` to
disable geometry. Both prefer their protected on-demand task and fall back to
explicit UAC.

**This divergence had a user-visible consequence, and that is what changed the
decision.** Writing RTSS's frame cap is not a convenience the helper improves —
it is the only way it works at all for a standard user, because
`RTSSHooks64.dll` is loaded into the calling process and RTSS installs under
Program Files. Standalone routes both the global cap and per-game **Save Limit
to Profile** through the helper. XFE had no helper, so on a stock RTSS install an
unelevated XFE could read the cap and toggle the limiter flag (shared memory, no
file) but could not change the FPS value or save a profile; its Frame Limit row
reported itself read-only, which was accurate.

That was a real gap rather than a tidy divergence, and it turned out to be the
argument that carried — stronger than the elevated-input case, because input
has a workaround (reach the window another way) and this had none.

**Resolved: XFE now has a default-on elevated input and RTSS helper.** It carries
controller input over administrator windows and protected RTSS writes, while
geometry remains off because Xbox FSE owns presentation.

The one place the two trees do meet is the controller mapping vocabulary. The
helper implements the builtin keystrokes as fixed actions and declines the five
that start a process or raise a window; XFE implements the whole vocabulary
directly because it is already at the right integrity to do so. If a builtin is
added to either tree, it needs a decision about which side of the standalone
helper boundary it falls on — see the builtin split in `README.md`.

### One that should have matched all along

Controller reach over the application's own windows was an enumerated list in
standalone and a single process-wide question in XFE. The divergence was
defended on grounds that did not survive being checked — an evaluation order
that is not what the code does, and presentation windows that cannot be active
because they are `WS_EX_NOACTIVATE`. Standalone now asks XFE's question.

Worth recording as a pattern rather than an incident: the justification for a
divergence is itself a claim, and an old one is worth re-testing before it is
used to defend the next decision. This paragraph is its own example. It used to
end "`SettingsEditorControllerActive` and `ControllerSettingsSurfaceActive` are
still separate functions because their surrounding globals differ" — and the
globals were exactly two things, a helper each tree had and the other did not,
and one flag with two names. Named, they took a commit. There is now ONE
`ControllerSettingsSurfaceActive`, in `SteamShell-Shared.ahk`, and the companion
gained the shell's owner-chain walk by inheriting it.

### A second one that should have matched: automatic mouse mode

Found by using XFE rather than by reading it. Returning to the Windows desktop
left the controller with no pointer, because XFE had no automatic mouse mode at
all — only holding View/Back, or `EnablePersistentMouseMode` for always-on. The
feature had simply never been ported.

The adaptation was the part recorded here, and **the adaptation was wrong.** It
is preserved below because the reasoning that produced it is the reusable part.

Standalone chooses between its per-application allowlist and its blanket
exclusion list by asking `DesktopMode`, which is a shell-replacement concept: a
companion that never owns the shell has no equivalent, and every foreground
window is a desktop window as far as it is concerned. The tempting reading was
that XFE therefore only needs the blanket list — which would have made
`AutoMouseExeList` configuration that does nothing. So `EnableDesktopAutoMouseMode`
was introduced to make the selection in XFE: on, the pointer active everywhere
except a `DesktopAutoMouseExcludeExeList` defaulting to Xbox FSE's shell
surfaces; off, only in the named applications. Both settings kept the meaning
they have in standalone, and neither became dead configuration.

**Schema 11 removed the exclusion mode entirely.** The test applied above was
"does every setting still do something?", and both settings passed it. That was
the wrong test. The right one is *can this setting be correct?* — and the
exclusion list could not, because the question it was really answering is **"am
I inside Xbox FSE right now?"**, which Windows exposes no way to ask. What
shipped was a hand-maintained list of another product's process names, which
goes stale silently and wears a configuration field while doing it. Keeping
`AutoMouseExeList` reachable was a good reason to reject "blanket list only"; it
was not a good enough reason to invent a mode that cannot be right.

What remains is the allowlist and its master switch: standalone's
non-`DesktopMode` behaviour, unchanged and unadapted. Xbox FSE needs no
exclusion because it is simply never on the list. The removal narrows behaviour
for anyone running the old default, so `RetireDesktopAutoMouseSettings` deletes
both keys and logs what changed rather than doing it quietly.

The generalisable finding: **when a port needs a stand-in for a concept the
other program does not have, the stand-in has to be answerable, not merely
non-empty.** A configuration field is not a substitute for a fact the program
cannot obtain.

`AutoMouseProcessMatches` moved into the shared file, because the list means the
same thing in both programs. `AutoMouseModeActive` stayed per-tree, and now
differs only by the `DesktopMode` branch standalone has and XFE does not — a
smaller divergence than the one it replaced.

### Still divergent, and both are decisions rather than oversights

- **The elevated helper is now in both trees, with one deliberate capability
  difference.** Both default it on, carry controller input and protected RTSS
  writes, prefer a protected on-demand task, and fall back to explicit UAC.
  Standalone also enables geometry; XFE disables it because Xbox FSE owns
  presentation. Same binary, same protection gate, different `--product`.
- **The Settings windows are laid out by different mechanisms.** RESOLVED. XFE
  now uses flowing row builders and a scrolling content viewport, like
  standalone, and the four category names shared with standalone — General,
  Controller & Cursor, RTSS & Performance, Startup Programs — present the
  settings that exist in both in standalone's order and wording.

  The precondition is worth recording, because "port the builders" was not
  enough on its own. Flattened into single flowing columns, two of XFE's pages
  run to roughly 800px against a 410px content area in a fixed 920x660 window.
  Standalone only fits because it scrolls; XFE never got that, so its pages had
  grown sideways into hand-placed columns instead. The viewport had to be ported
  first.

  What stayed different, deliberately: choice lists derive their stored value
  from the selected index, so `OverlayControlMode`, `FrameLimiterControlMode`,
  `WindowMode` and `ParkEdge` keep XFE's order — reordering one to match
  standalone's wording would invert the setting, and an assertion now pins it.
  `ControllerIndex` stays an edit here where standalone uses a dropdown, for the
  same reason: the round-trip is a value, not an index.

  The three pages with no standalone counterpart — Steam, Assist, Advanced —
  were not aligned with anything, and standalone's Startup & Splash, Focus &
  Windows and Launcher Cleanup have no XFE counterpart. Inventing settings on
  either side to force symmetry would be worse than the difference.

### Enforcing it

The shared functions now live in **one file**. `SteamShell-Shared.ahk` sits
beside both trees in `SteamShell/` and is `#Include`d by both at compile time, so a shared
function can no longer drift: there is no second copy to drift from. The
validator that used to compare two copies and fail on drift — a net that catches
falls — now guards the arrangement instead. It fails if a shared function is
redefined inside a tree (which would shadow the shared definition and still
compile), if the shared file defines something the manifest does not list, if
either tree stops including it, or if either tree stops providing the seam.

Shared code may call back into exactly two per-tree functions, `LogLine` and
`SharedPersistSettings(changes)`. The second exists because each tree names its
own settings file and its own PID — **not** because the trees write settings
differently. They no longer do: both wrappers pass those two values to
`CommitIniChangesAt` in `SteamShell-Common.ahk`, which stages a copy and replaces
the live INI only after every write in the batch has succeeded. XFE's loop of
bare `IniWrite` calls is gone.

The manifest is still a decision record, not a lock. If two functions genuinely
need to diverge, move the function back into both trees and remove the name in
the same commit — the point is that a divergence is written down rather than
discovered. The checker also reports functions that have *become* identical in
both trees and are candidates to move in, which is how the list grows.

The move was deliberately conservative. A similarity scan suggested nine more
functions were "near-identical"; on inspection only four were behaviourally
identical. The rest differ by product — `QuickMenuMouseActivate` vs
`QuickMenuMouseSelect`, `SetStatus` vs `ShowNotification`, `QuickMenuStatusCtrl`
vs `QuickMenuFooterCtrl`, and the product name each embeds — and stayed where
they were. A high similarity score is a hint, not a decision.

The check has no skip path. It used to be skipped when the sibling tree was
absent, which was the normal case inside a frozen `releases/` snapshot holding
one tree — and a silent skip is the last thing a check like this should be
capable of. Both trees, the shared file and the manifest are now in one folder,
a snapshot is that whole folder, so the skip had nothing left to describe and
was removed. The check itself lives in `Validate-Common.ps1` and runs from both
validators.

### How much is left to share

Measured rather than guessed, because the intuition here is wrong. Taking the
144 shared function names and progressively ignoring every cosmetic difference:

| if we also ignore… | identical |
|---|---|
| nothing (as shipped) | 42 |
| comments | 46 |
| line wrapping | 47 |
| `ShowNotification` vs `SetStatus` | 47 |
| `ClampInt` vs `Max(Min())` | 48 |
| product-identity strings | 50 |

**This measurement was wrong, and the conclusion drawn from it was wrong.** It
compared raw text, where indentation and local variable names dominate, and it
was taken before 161 functions moved into the shared files. Re-measured
structurally -- comments stripped, literals collapsed, notify aliases folded --
eleven functions that "differed substantively" were the same code formatted
differently, and all eleven are now defined once. `Report-StructuralDrift` in
`Validate-Common.ps1` reports this figure on every build so it cannot go stale
again. The original claim follows for the record.

Unifying *everything* cosmetic buys eight functions. About **94 shared-name
functions differ substantively** — different page models, different foreground
semantics, desktop-mode gating, one tree owning the shell and the other refusing
to. That is real divergence, not drift.

The other direction was checked too: all standalone-only functions
cross-compared against all XFE-only functions for same-logic-different-name
duplication.

**That check previously reported "exactly one hit, a six-line cancel helper.
Nothing is hiding." Re-running it found five, two of them byte-identical:**

| standalone | XFE | similarity | lines |
|---|---|---|---|
| `ShortenQuickMenuText` | `ShortenText` | **1.00** | 4 |
| `HandleUncaughtSteamShellError` | `HandleUncaughtCompanionError` | **1.00** | 5 |
| `StopElevatedInputHelper` | `StopElevatedRtssHelper` | 0.95 | 21 |
| `RecordShortcutChord_Cancel` | `RecordShortcutCancel` | 0.83 | 6 |
| `SettingsEditorMouseWheel` | `SettingsMouseWheel` | 0.75 | 16 |

The cancel helper is the one the earlier figure recorded. The other four are
either newer than that measurement or were missed by it; the earlier scan did
not state its similarity threshold or whether it normalised comments and
whitespace, which is why the numbers cannot be reconciled and the claim could
not be checked without redoing the work.

Both byte-identical pairs are self-contained and would belong in
`SteamShell-Common.ahk` rather than the shared file: neither touches a global,
and the uncaught-error handler differs from the elevated helper's equivalent for
a real reason — the helper exits and suppresses AutoHotkey's dialog, because a
modal error box on a shell desktop is unrecoverable.

**Four of the five are now shared.** What kept each pair apart was smaller than
the name suggested:

| pair | what actually differed | now |
|---|---|---|
| `ShortenQuickMenuText` / `ShortenText` | nothing | `SteamShell-Common.ahk` as `ShortenText` |
| `HandleUncaught*Error` | nothing | `SteamShell-Common.ahk` as `HandleUncaughtError` |
| `StopElevated*Helper` | one log label | `SteamShell-Shared.ahk` as `StopElevatedHelper`, label via `ProductIdentity()["helperLabel"]` |
| `RecordShortcut*Cancel` | one Map key: `"ih"` vs `"input"` | `SteamShell-Shared.ahk` as `RecordShortcutCancel` |

**Starting** the helper stays per-tree because paths, task names and deployment
responsibilities differ; both products prefer a protected task and can fall back
to explicit UAC.
**Stopping** it is not like that: closing a process by PID and waiting is the
same operation either way.

**`SettingsEditorMouseWheel` / `SettingsMouseWheel` stays split.** Three real
differences, not naming: XFE also guards on `SettingsVisible` (a global
standalone does not have at all — zero references), also excludes the `ListBox`
class, and scrolls through a differently-shaped settings window. Two seams for an
18-line function is a worse trade than the duplication.

> **Two of those three held up; the middle one was a bug wearing a rationale.**
> `SettingsVisible` really is XFE-only (zero references in standalone), and the
> scroll target really is a differently-shaped window. But "XFE also excludes the
> `ListBox` class" was recorded as a product difference when standalone's
> settings window has a category `ListBox` of its own — hovering it and scrolling
> moved the settings page instead of the list. Standalone now excludes it too.
>
> The conclusion still stands: two seams for an 18-line function is a poor trade
> and the pair stays split. What was wrong was counting a missing exclusion as
> evidence for splitting it.

**One thing this pass exposed that had nothing to do with sharing.** Moving the
uncaught-error handler into `SteamShell-Common.ahk` meant a tree could stop
calling `OnError` entirely while the body assertion still passed, because Common
supplies the function either way. Only the elevated helper's registration had
ever been asserted. Both trees now pin theirs against `$rawSource`. A shared
definition can quietly cover for a program that never wires it up, and that is
worth checking for wherever a per-tree registration meets a shared body.

So **48 is close to the natural ceiling**, and it is not worth renaming
`ShowNotification` to `SetStatus` across standalone to inflate it. The two status
mechanisms genuinely differ — standalone's schedules a footer repaint when the
message expires, XFE's does not — and collapsing the names would hide that.

> **This was wrong, and it was wrong on the facts rather than on judgement.**
> Both functions scheduled that repaint, with the same
> `SetTimer(QuickMenuRefresh, -(StatusVisibleMs + 100))` under the same
> `if QuickMenuVisible`, against the same five globals. They were the same
> nineteen lines. The claimed difference was not there to be hidden.
>
> The name `ShowNotification` is a leftover from a bottom-corner toast the shell
> removed for being distracting over the Quick Menu; both products have shown the
> Quick Menu status line ever since. Because two names existed, every function
> that reported anything looked product-specific — `SendRtssShortcut`'s entire
> diff was four notify calls.
>
> The implementation now lives once in `SteamShell-Shared.ahk` as `SharedNotify`,
> and each tree keeps a one-line alias so its own call sites are unchanged. The
> conclusion that renaming for its own sake is not worth doing still stands. What
> was wrong was the evidence offered for it, which nobody had checked.

The corollary matters more than the number: *"how many functions are
byte-identical" is a poor proxy for "how much do these trees benefit each
other."* The most valuable thing this comparison turned up — XFE's typed INI
readers making a whole bug class unrepresentable, scoped in
`INI_READER_MIGRATION.md` — would not add a single name to the manifest.

### Settings file layout — aligned in schema 12, with a stated limit

The two products organised their INI files by different rules, and neither was
wrong:

| | standalone | XFE (before schema 12) |
|---|---|---|
| Cross-cutting feature switches | all 13 in `[Features]` | beside the settings they gate |
| Assist / cleanup tuning | `[GameForegroundAssist]`, `[LauncherCleanup]` | one merged `[Assist]` |

Both were internally consistent, which is why this was never drift. The cost was
paid by the user rather than the code: someone who had configured one product
looked in the wrong section in the other.

Schema 12 adopts **standalone's** rule, because standalone is the larger surface
and the one whose sections a user meets first. Six keys moved —
`EnableAutoMouseMode` to `[Features]`, and `CooldownSec`, `GracefulCloseMs`,
`HardKill`, `RequireNoGame`, `LauncherProcesses` to `[LauncherCleanup]`.

**The limit is deliberate and worth stating, because it will look incomplete.**
Only settings that exist in both trees *under the same name* moved. XFE's
`TickIntervalMs` is standalone's `CheckIntervalMs`; XFE's `CpuThresholdPercent`
is standalone's `GameCPUThresholdPercent`. Moving those into a shared section
without renaming them helps nobody find anything, and renaming them as well
would assert a parity that does not exist: XFE's assist features are reduced
versions, which is precisely what the `Lite` in `EnableGameFocusLite`,
`EnableSteamAssistLite` and `EnableLauncherCleanupLite` records. `[Assist]`
therefore still exists and still holds the XFE-only tuning.

`SettingsSchemaVersion` also stayed in `[Companion]` rather than moving to
standalone's `[SteamShell]`. Those are each product's own identity section, not
a mismatch; giving the companion a `[SteamShell]` section would be the error.

### Current state (August 2026, end of the consolidation pass)

The figures above are the record of individual audits and are left as they were
written. These are the numbers now:

| | Aug 2026 (first pass) | now |
|---|---|---|
| Defined once in `SteamShell-Common.ahk` (all three programs) | 90 | **106** |
| Defined once in `SteamShell-Shared.ahk` (both trees) | 103 | **237** |
| Same-named functions still defined in both trees | 69 | **61** |
| ...of those, declared divergent with a reason | — | **20** |
| ...of those, still 0.90+ once naming and formatting are ignored | 0 | **2** |

Both remaining 0.90+ pairs are seams declared in `DIVERGENT_FUNCTIONS.txt`:
`ProductIdentity`, where each product names itself, and
`ProductControllerLearnConsumesReport`, where the shared RawInput handler asks
each tree whether its learner wants a report. Neither is drift; both are the
mechanism working.

**This table went stale exactly the way the ones above it did**, and it said it
could not. The figures were written at the end of one consolidation pass and
were wrong within a month — Shared more than doubled. `Report-StructuralDrift`
does hold the last row honest on every build, which is why that row is the only
one that was still right. A number in prose is a number nobody recomputes.

The last row is the one that matters, and the reason it is zero: every function
that was the same code wearing different names or indentation is now defined
once. What remains below 0.70 is divergence with a reason — different page
models, desktop-mode gating, one tree owning the shell and the other refusing to.

`Report-StructuralDrift` in `Validate-Common.ps1` recomputes that last row on
every build and reports it, so this table cannot go quietly stale the way the
measurements above it did. It reports rather than fails: a high structural score
is evidence, not a verdict.

### Sorting the duplication by intent, not by similarity

The table above counts byte-identical functions. Sorting the 83 functions
defined in both trees by *why* they differ turned out to be the more useful
question, and produced a different answer:

| Why they differ | Count | What was done |
|---|---|---|
| Nothing — byte-identical | 3 | shared |
| One product string | 3 | shared behind `ProductIdentity()` |
| Variable or control names only | 4 | renamed, then shared |
| A real product decision | 2 | kept, behind a seam |
| Genuinely different | 71 | left alone |

**The seams are the mechanism, and they are cheap.** `SharedNotify` already
existed for the notification surface; `ProductIdentity()` and
`QuickMenuMouseChoose` joined it. A seam turns "these differ, so they must be
duplicated" into "these differ *here*, and are identical everywhere else."

**Two findings worth keeping:**

*A justification outlived its code.* `SHARED_FUNCTIONS.txt` recorded
`VerifyElevatedHelperProcess` as per-tree because the trees "compare against
different helper paths". They read the same global; only the error message
differed. A recorded decision is only as good as the last time somebody checked
it against the source.

*Sharing a message without sharing the behaviour is its own bug.* The shared
`SetQuickMenuHdrState` told the user to "use A to toggle" when HDR state was
unreadable. Standalone's A falls back to the `Win+Alt+B` chord; XFE's A reports
the same unavailability, so the advice looped. The HDR divergence itself is
correct and stays — see `SHARED_FUNCTIONS.txt` — but the shared text now says
only what is true in both.

### Still divergent by feature, not by implementation

Two things XFE has and standalone does not, where the intent applies to both.
Recorded here because they are *ports*, not consolidation, and should not be
mistaken for drift:

- ~~**RawInput controller backend.**~~ Ported August 2026. Both products read
  the backend from `SteamShell-Shared.ahk`; standalone gained `[Controller]
  Backend`, the RawInput probe, and Learn Controller in its own Settings.
- **Steam View button tap/hold.** Standalone already has `MenuShortcut` and
  `OverlayShortcut`, so the intent is fully present; only the tap/hold
  resolution and its two hold thresholds are missing.



### Log rotation named once

Both products rotate the same way and named it differently: `[Companion]
LogRotateMaxKB` in the companion, `[Logging] GameLogRotateMaxKB` in the shell.
Rotation was never game-specific — the same two values size and count the
backups of the shell's log, the companion's log, and the elevated HELPER's log,
and only one of those is a game log.

The cost was not cosmetic. The helper serves both products and branched on
`--product=` to read one setting under two spellings, and that branch is only as
correct as the strings it hard-codes: read the wrong product's key and it falls
back to a default rather than what the user configured, which shows as a log
growing without bound rather than as anything failing.

Both now use `[Logging] LogRotateMaxKB` and `LogRotateBackups`. The helper reads
them once. Schema 22 in the shell and 18 in the companion carry existing values
across.

### RawInput and the Learner, ported

Taken August 2026, and the reasoning that had it listed as "still divergent by
feature" was wrong in an instructive way.

It was recorded as XFE-only because of why XFE BUILT it: XInput and GameInput
both read all zeros inside Xbox FSE. That is why it exists, and it is not what
it does. The registration passes `RIDEV_INPUTSINK`, so reports arrive whether or
not the program owns the foreground, and it registers both the gamepad and
joystick usages because controllers vary in which they report. That is general
HID gamepad support, and it answers a question the shell has more sharply than
the companion does: a controller XInput cannot see left the SHELL with no input
at all, on a machine with no taskbar and no Start menu to fall back to.

Twenty functions and about 700 lines of backend, then thirty-nine and about
1,200 of wizard, moved to `SteamShell-Shared.ahk` rather than being copied. The
wizard moved whole, GUI included: it is a self-contained dialog rather than a
page of either Settings window, so nothing about it belonged to one tree.

Backend SELECTION stays per-product, because the shell has no GameInput. Its
`ControllerReadState` tries RawInput and falls through — `RawInputReadState`
answers false whenever no report has arrived inside `RawInputStaleMs` — so a
machine whose pad XInput already handles never takes the new path.

Three things had to follow it and did not, all found later:

- The Settings chord, above. Written down as a condition, missed anyway.
- The controller poll must stand down while the wizard is open. XFE has had that
  guard since it wrote the wizard, with a comment listing what happens without
  it: A opens the touch keyboard, Y opens Game Bar, L3+R3 throws the Quick Menu
  on top. The shell gained the wizard and not the guard, and the wizard was
  unfinishable — the D-pad moved focus between its own buttons while it asked
  for a D-pad direction, because `ControllerSettingsSurfaceActive()` answers true
  for any window this process owns.
- The RawInput arrival counter logged every two seconds regardless of the probe
  setting. Survivable in a companion that registers only inside Xbox FSE;
  not survivable in a shell that runs all the time and now registers by default.

### The Settings windows, unified

The two Settings surfaces were separate implementations of the same screen.
Their final scrolling seam is gone too: both now place their page controls in
the same clipped child-window host, and Setup Assistant uses that host as well.

| | where it lives now |
|---|---|
| What every page contains | `SettingsCategoryRows` in Shared — all ten categories, each row tagged `both`, `standalone` or `xfe` |
| Where every control sits | `SettingsLayout` in Shared — one set of columns, the shell's |
| The row builders | Shared — the shell's, moved intact, with the window passed in |
| Walking a category | one adapter, taking the product |
| Filling the window | from the row specs, both products |
| Writing it back | from the same specs |
| Scrolling | `SharedScrollHost*` in Shared — one clipped canvas move per tick |

Six seams remain, each answering something only a product knows: where a field
is recorded, what "changed" means, what Browse and Record do, whether a switch
greys other rows, whether the product has section headings, and whether a
learner wants a report.

One row is hand-placed and cannot move: the shell's foreground-sensitivity
choice, keyed `GameMinScoreToActivate`. The companion compiles Shared and
forbids that name — it is a shell responsibility, and a name in a string still
counts. The boundary stayed as written rather than being widened to admit it.

What the unification found, which is the argument for doing it: two choice lists
in opposite orders where only one product read the index, so merging them would
have silently inverted overlay and frame-limiter control mode; five numeric rows
whose stated range disagreed with what the code accepted, one of them a range no
tree allowed at all; and a controller-index row that became a dropdown while its
save still read `.Value`, writing 1-4 into a setting that means 0-3.

### Merging the runtimes entirely — recommended against

Moved here from `POST_1.9.9_STATUS.md` when that document was retired. It is a
standing decision about the relationship between the two trees, which is what
this file is for; it was only ever in a status note because that is where it was
written.

Measured before the shared-file work: **149 common function names**, of which 47
were byte-identical (627 LOC, about 2% of the combined 31.5k lines) and 35 were
genuinely different (<0.50 similarity). The functions that differ most are the
core of each program — `PollController` is 334 vs 404 lines because standalone
reads XInput and XFE reads RawInput through learned profiles, which is the
reason XFE exists at all.

**The argument against is not the effort.** Today an XFE change *cannot* break
the shell, because XFE is a different binary. That isolation is the most
valuable safety property this project has, and it is free. Merging would delete
it to unify 627 lines.

Worth revisiting after the unified installer ships, once there is evidence about
how much duplicated maintenance actually remains.

The August 2026 audit is a data point *for* keeping them separate: the automatic
mouse mode divergence it found was not between the two trees at all, it was
between `SteamShell.ahk` and `SteamShell-Helper.ahk` — two programs that already
share `SteamShell-Common.ahk`. Sharing code does not by itself stop two
processes answering the same question differently. Only having one answer does.

## The settings surface, after the page audit

The pages now line up where they can, and the places they do not are the places
the products genuinely differ.

| page | shell | companion |
|---|---|---|
| General | 8 rows | 6 |
| Startup & Splash | 12 | — |
| Startup Programs | 4 | 5 |
| Controller & Cursor | 13 | 13 |
| Steam | 9 | 8 |
| Focus & Windows | 7 | — |
| RTSS & Performance | 14 | 14 |
| Launcher Cleanup | 10 | 6 |
| Assist | — | 5 |
| Advanced & Logging | 11 | 2 |

Three pages are the shell's alone — splash, focus and window management — because
Xbox FSE owns presentation and the companion has no equivalent. Assist is the
companion's alone. Everything else exists in both.

**`Advanced` is `Advanced & Logging` in both.** The `tableKey` argument on
`SettingsAddRowsForCategory` existed for that single name mismatch and is now
unused by every caller.

**The shell gained a Steam page.** It had always read the whole `[Steam]` section
and offered none of it. This is what made the View-button rows ship invisible:
they were tagged for the shell and built correctly, onto a page nothing drew. The
category list and the constructed panels are now asserted to be the same set, in
both directions.

**Both products have Launcher Cleanup.** The keys overlap but the rows are not
shared: the two clamp differently — `CooldownSec` is 30..7200 in the companion and
0..86400 in the shell, `GracefulCloseMs` 500..30000 against 0..60000 — and a
shared row would offer one product values its own `LoadSettings` rounds away.

**A settings row is only real if its page is drawn and its section is read.** Two
new checks came out of this audit: no product may build two controls for the same
section and key (the shell briefly had three, each silently overwriting the other
on save), and every row's category must be one the product actually draws.

## What the fingerprint gate cannot see

The August audit's premise was that a call-sequence comparison finds duplication
that text comparison misses. It does. This pass found two pairs it cannot.

- **Pure-data functions have no call sequence.** `InitDefaultControllerMappings`
  and `DefaultControllerMappings` produced the same 22 bindings and three display
  overrides under two names — 22 subscript assignments against one `Map()`
  literal. Neither the name-keyed gate nor the cross-name one could see them.
- **A `DllCall` target is part of the sequence.** `RevealWindow` was already one
  function in two files, differing only in whether the call named its DLL.
  `"User32\ShowWindow"` is not the string `"ShowWindow"`, so an identical pair
  scored 0.00 and was never flagged.

Both are recorded in `CROSS_NAME_DUPLICATES.txt`. The gap is written down rather
than closed: comparing data tables structurally is a different check, and a weak
version would be worse than knowing this one does not cover them.

### August 2026, second pass: the bar itself was the blind spot

The gate demanded a reason at **0.75 or above**. Everything below that was not
judged and not recorded — it was simply not looked at.

That threshold is wrong in a way worth stating plainly: **two copies of one
routine drift apart in structure as well as in text, so the longer a duplicate
goes unmerged the lower it scores.** The metric loses confidence exactly as the
problem gets worse. A low score is evidence of nothing, which is the same argument
this file already makes about text similarity.

Lowered to **0.45**. Eleven pairs appeared, and reading them rather than scoring
them found two that were drift:

- **`TrayOpenQuickMenu`, nine lines.** The shell raised the Quick Menu with
  `WinActivate`; the companion used `ForceForegroundWindow`. That is the hardened
  primitive — `SteamShell-Common.ahk`'s own header records that the shell's
  version was the one kept — and the shell already used it at every *other* Quick
  Menu site. `WinActivate` loses to the foreground lock a fullscreen game holds,
  which is exactly the situation someone reaching for the tray icon is in. Fixed,
  not recorded.
- **`QuickMenuHandleController`, 0.73.** Above the old bar the whole time and
  simply never listed. Its TASKS-page handling is genuine; its B-button branch
  restated the MAIN-page test that shared `QuickMenuGoBack` already makes.

`PollController` is the one to know about: **0.31, about 350 lines on each side,
and one input loop written twice.** The low score is the finding, not a comfort. Most of the difference is renaming —
`prevButtons`/`previousButtons`, `btnDefs`/`buttonDefinitions` — which is
precisely the tidying the fingerprint was built to see through, and it still hid
under the old bar for the gate's entire life. The genuine differences are bolted
onto the ends. It is the largest consolidation left and the riskiest, being the
input path of the product that runs as the shell.

### The controller mouse, and a shared UI primitive

`ApplyControllerMouseMove` was already shared, which is why the smoothness fix
reached three programs from one edit. Worth recording *what* it fixed, because the
cause was not in the mouse code at all:

**Windows quantises timers to about 15.625 ms** unless a process raises the
resolution, and none of the three does. A timer fires on the first tick boundary
at or after its interval, so `ControllerPollIntervalMs = 16` — 0.375 ms past a
boundary — could not fire at 15.625 and waited for 31.25. Both products polled at
roughly **32 Hz while the setting said 62.5**, and because 16 sits only marginally
over, scheduling noise flipped the interval between one boundary and two.

Speed was then a distance *per tick*, so uneven timing became uneven distance on
screen. That is a shared-code bug that no parity check could have found: the two
copies agreed perfectly, and both were wrong.

The fix makes speed a velocity scaled by measured elapsed time, which decouples it
from the tick rate — so the interval could be moved to 15 without changing how
fast the cursor travels. Those two were the same knob before, which is why neither
had ever been adjusted.

`SettingsAddSliderField` is new and shared. It is the first row type added since
the settings spec was unified, and it needed one thing the others did not:

> **Assigning `.Value` in code does not raise `Change`** in AutoHotkey; only the
> user moving the control does. A slider carries a separate value readout, so
> without an explicit repaint the number shows what the row was BUILT with while
> the track sits at the loaded value.

The repaint could not be a per-field callback, because **the two products hold
their field registries differently** — the shell an array of field Maps, the
companion a Map from `Section.Key` to the control — and only one of them can carry
a closure. That is `SettingsRegisterBuiltField`'s entry in this file, seen from the
other side: the divergence is real, and it constrains what a shared builder may
assume. The readouts are registered in one Map keyed on the slider's own handle,
which both products can reach.

The two trees also reach the same *behaviour* by different routes for controller
adjustment, and this one is not worth merging: the shell has a field-aware adjust
path and now reads the row's declared step from the spec, while the companion
navigates its Settings window with ordinary arrow keys and gets the same 100 px/s
movement from the track's own line size. Two mechanisms, one outcome, and the
companion's needs no code at all.

### The gate compares functions, so inline logic is invisible at any threshold

Lowering the bar closes one blind spot. It cannot close this one.

`GameWindowShapeVerdict` is shared **so both products reach the same answer from
the same numbers**. Each tree then built the facts map inline — the companion
per-monitor, the shell against `A_Screen*` only. A fullscreen game on a second
monitor was measured against the first monitor's size at an origin of `(1920, 0)`,
failed the position tolerance, and scored as borderless or was rejected outright.

There was never a function pair, so no threshold would have found it.

Worse, it was *recorded as deliberate* — in a companion-side comment asserting
something about the other tree: "the shell can assume the game is on `A_Screen*`".
It cannot; it centres its own GUIs per monitor and resolves a monitor index for
the foreground window. It is one shared function now,
`GameShapeFactsForWindow`.

> **A shared arbiter fed by two private argument builders is a duplicate with
> extra steps.** Sharing the function that decides is worth little if each tree
> assembles what it decides on, and nothing in this project will notice.

Everything else shared in this pass moved rather than being ported, for the same
reason: `PowerBroadcastMessage`, `ControllerResumeGapCheck` and
`RearmControllerInput` were all companion-only, all needed by the shell, and all
name nothing per-product. Copying any of them would have created a divergent pair
on the day it was written.

### Two supporting fixes to the gate itself

- **The stale-entry check was stricter than its own error message.** It required
  membership in the flagged set, which is only populated *after* the threshold
  test — so an entry for a genuinely divergent pair scoring below the bar failed
  the build as stale. `OpenWindowsSettings` scores **0.00** because a
  privilege-boundary divergence shares no calls at all, so the file was
  structurally unable to hold exactly the knowledge that is hardest to recover.
  The threshold now decides what *must* be explained; being a real pair decides
  what *may* be.
- **The per-product seam is exempt.** `$sharedSeamAllowed` is already the record
  that those functions differ. At 0.45 the gate began demanding a second
  declaration for six of them, and double-booking one fact in two lists is how
  the counts in this project keep going wrong.

## A recorded reason is not evidence

Two entries in `DIVERGENT_FUNCTIONS.txt` were re-read against the code rather than
taken at their word, and were false — not stale, false.

- **`ProductControllerLearnConsumesReport`** was kept per-tree because "Shared
  cannot read a global it does not declare into both trees". `SteamShell-Shared.ahk`
  declares `LearnActive` in seven other functions and the entire learner wizard
  lives there. The two bodies were byte-identical.
- **`MouseWatchHoldsCursorVisible`** said the shell holds the cursor visible for
  nothing. It has a pointer-driven Settings editor, and the cursor was vanishing
  mid-edit — blinking, with a controller connected, as the poll and the watch
  fought each other.

The same re-reading found `SettingsProductWireDependency` recorded as a design
choice — "the companion has no dependency pass, so its body is deliberately
empty" — when two of the eight rows the shared spec marks with `dependency` are
`product: both` and reached that empty body. That was an unimplemented feature
described as a settled decision.

Worth noting how the first fix hid itself: correcting
`MouseWatchHoldsCursorVisible` changed the pair from identical-shaped to
genuinely different, which un-flagged it, which made its manifest entry stale and
required deleting it. **Fixing the bug removed the only written record that the
pair differs at all.** That is a property of a gate that only demands reasons for
what it flags, not a mistake — but it is the mechanism by which this file drifts
away from the code.

## What is left between the two controller backends

`ControllerReadState` is the last substantial divergence, and it is now one thing.
Both trees try RawInput first, both decline to fall back when RawInput was asked
for by name, and both finish at the shared `XInputResolveController`. The shell's
body is a strict subset of the companion's because the companion also tries a
GameInput backend in between and records which one answered.

Sharing it needs `InitGameInput`, `GameInputReadState`, `ShutdownGameInput` and
`SetActiveBackend` in both trees — a new input backend in the product that runs as
the shell, which wants hardware behind it rather than a review.

The part that mattered is already shared. The shell read only the configured
XInput slot, so a pad that Steam Input moved mid-session stopped answering, on the
product where the recovery on offer was to change Controller Index in Settings
using the controller that had just stopped working.

## The learner is shared, and that is now load-bearing

An 8BitDo Ultimate 2 in DirectInput mode produced a trigger bound to a gyro axis
in the shell, and the first instinct was that the companion had solved it and the
shell had not — the drift this document exists to catch.

It had not. All 32 learner functions live in `SteamShell-Shared.ahk` and none in
either tree, so both products ran the identical filter and would both have done
the same thing on that pad. What looked like drift was one product being tested
on hardware the other had not met.

That is the arrangement working, and it is worth stating plainly because the
opposite reading is so available: when two products behave differently, shared
code means the difference is in the input or the environment, not the source. The
fix landed in both at once.

The audit that followed found four defects in that shared code, so this is not an
argument that sharing makes code correct — only that it makes one fix enough.

## What is still per-tree in the controller path

- `RestCheckPeak` is declared in each tree, because `SteamShell-Shared.ahk`
  cannot declare a global. Same for the four learner flags added with the audit.
- `TempDisables` is the shell's alone, which is why its enumerate-while-modifying
  walk had no companion counterpart to compare against. The companion's
  equivalent, `AssistCpuSamples`, already cloned before deleting — as does
  `held` in `SteamShell-Common.ahk`. The shell was the only one of the three that
  did not, and nothing could see that because there was no shared name to compare.
