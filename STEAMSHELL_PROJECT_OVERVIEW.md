# SteamShell Project Overview

**Document status:** August 10, 2026

**Stable SteamShell release:** 2.0.1 (locked at `releases/2.0.1/`, with the verified installer)

**SteamShell working tree:** 2.0.2, settings schema 23 (helper 2.0.2.1)

**Stable SteamShell-XFE release:** 2.0.1 (locked at `releases/2.0.1/`)

**SteamShell-XFE working tree:** 2.0.2, settings schema 18

**Development line:** 2.0.2, a coordinated patch release on top of 2.0.1; earlier releases preserved as immutable checkpoints

> 2.0.2 is the WORKING TREE version. The downloadable release is still 2.0.1:
> `releases/2.0.2/` cannot exist until a Windows build produces the verified
> installer it is locked around, so every `releases/2.0.1` path below points at
> 2.0.1 deliberately.

## Executive summary

SteamShell is a living-room Windows gaming project with two related, but intentionally different, applications:

1. **SteamShell 1.7** is the complete home-theater PC shell. It launches Steam Big Picture, manages Windows Explorer and the taskbar, decides which game or application should be in front, provides controller-driven system controls, and restores the normal Windows desktop when the gaming session ends.
2. **SteamShell-XFE** is an experimental companion for Microsoft's Xbox Full Screen Experience (Xbox FSE). Xbox FSE remains responsible for the shell, application presentation, and Home app lifecycle. The companion is intended to add SteamShell's useful controller controls without competing with Xbox FSE.

SteamShell and SteamShell-XFE 2.0.1 are the coordinated locked stable release.
The bundle is the major pre-2.0 architecture checkpoint. Standalone separates
its normal-integrity shell UI and application launches from a narrowly scoped
elevated helper. XFE continues to operate inside Xbox FSE while Xbox FSE retains
ownership of the shell and application presentation.

Both locked releases paint their Quick Menu rows
as one opaque GDI+ bitmap at physical pixel size, with rounded selected fill,
accent outline, left bar, padded/DPI-scaled glow, neutral charcoal base, and a
shared preset/custom accent setting. Windows 11 supplies composited outer corners
with its border color suppressed; Windows 10 retains the region fallback. The
first Windows pass found and corrected the clipped glow, blue-black base, outer
border, recovery-text clipping, and standalone automatic-mouse scope error. The
second pass darkened the base to `#242424` and removed the erase phases that
caused a flash during row and submenu navigation. Unselected labels and values
now use neutral grays rather than the earlier blue-gray palette. The menu does
not force a custom exterior shadow: doing so reliably would require a more
fragile layered companion window, so the single opaque window is retained.
Desktop restoration also destroys and flushes the menu's DWM surface, then
latches recreation off before Steam begins shutting down. This prevents a stale,
non-interactive image of its title, rows, or footer surviving the handoff to
Explorer.

## What the comments were worth, and what replaced them

**August 5, 2026.** A cross-tree audit found that this project's prose — these
notes, the file headers, the explanations beside individual functions — had been
describing intent at the time of writing rather than behaviour, and that several
load-bearing claims were simply false:

- `SteamShell-Shared.ahk` documented a **three-function** seam. The real count
  was **28**.
- `SteamShell-Common.ahk` said the shared file "reaches into **eight** tree
  functions." Also 28.
- Both files named `SharedNotify` as something each tree must define. It is
  defined in the shared file, and neither tree defines it.
- This document said the companion's settings schema was **11**. It was **16**.

The pattern matters more than any single error. `SteamShell-Common.ahk`'s header
already contained the diagnosis, written about the shared file: it *"documented
two permitted callbacks and had grown to eight before anyone noticed, because
nothing enumerated what actually left the file."* The remedy — an enforced
allowlist — was then applied only to `SteamShell-Common.ahk`. The shared file
kept its prose, and the growth resumed, from eight to 28.

**Prose cannot hold a list that changes.** Every list of that kind now lives
where it is executed rather than where it is read: `$sharedSeamAllowed` and the
declaration-block check in `Validate-Common.ps1`, `SHARED_FUNCTIONS.txt`,
`COMMON_FUNCTIONS.txt`, and `DIVERGENT_FUNCTIONS.txt`. Where a comment states a
count, it now says where the real one is kept.

### The measurement that was wrong, and why it read as success

The shared-parity check compared function bodies with `-ceq` and reported
nothing for months. That was taken as evidence the consolidation was complete.

It could not have reported anything. Two copies of one routine are never
textually identical once either has been touched, and touching them is exactly
what happens when a copy is tidied — a renamed parameter, a rewrapped
`DllCall`, a `switch` rewritten as a `Map`. Measuring *text* scored
`ControllerBindingPretty` at 0.26 similarity and `GetLastLines` at 0.49. Both
have an **identical call sequence**; one is a `switch` against a `Map`, the
other is the same function with a parameter deleted.

Comparing what the code **calls** instead found **34 of the 67** functions
defined in both trees to be the same routine written twice — about 526 lines.
Six of the eight strict-subset pairs were XFE-inside-standalone, which is not
two programs growing apart. It is one program copied and trimmed.

That comparison is now the fingerprint gate. Divergence is declared in
`DIVERGENT_FUNCTIONS.txt` with a stated reason and fails the build otherwise,
including when an entry goes stale — so the file cannot quietly become a list
nobody reads.

### What the gate cannot see, measured

An August 2026 audit pass found two duplicate pairs the fingerprint gate is
structurally unable to flag, and they are worth knowing because they bound what a
green build means.

- **A pure-data function has no call sequence.** `InitDefaultControllerMappings`
  and the companion's `DefaultControllerMappings` built the same 22 controller
  bindings and three display overrides under two names — 22 subscript assignments
  against one `Map()` literal. Invisible to the name-keyed gate *and* to the
  cross-name one.
- **A `DllCall` target is part of the sequence.** `RevealWindow` was already one
  function in two files, differing only in whether the call spelled its DLL.
  `"User32\ShowWindow"` is not the string `"ShowWindow"`, so a behaviourally
  identical pair scored 0.00.

Both gaps are recorded in `CROSS_NAME_DUPLICATES.txt` rather than closed, on the
grounds that a weak structural comparison of data tables would be worse than
knowing this one does not cover them.

The same pass found that a *recorded reason is not evidence*. Two entries in
`DIVERGENT_FUNCTIONS.txt` were false rather than stale — one claimed the shared
file could not read a global it declares in seven other functions, the other
described a product feature that exists. Re-reading reasons against the code, not
only checking that they are present, is a separate activity from running the gate.

### The replay must agree with the build

`Replay-Validation.py` reproduces the structural checks and replays the ~1,076
regex assertions out of the two PowerShell validators, so most work can be
verified without Windows. Its own header warns that a gate the two harnesses
disagree about is worse than no gate, and that happened: a PowerShell scan with no
Python counterpart failed on Windows while the replay passed.

Checks added since, all of which exist because something got through:

- Sources must decode as **UTF-8**. A cp1252 em dash written into a UTF-8 file
  made `grep` treat it as binary and silently return no matches — a tool
  reporting "not found" when it means "unreadable".
- A **PowerShell variable** may not hold both a lookup table and raw text inside
  one function. Reusing one replaced a function-body table with a string, and the
  failure surfaced hundreds of lines later at an unrelated `.ContainsKey`.
- No product may build **two controls for the same setting**; each product's save
  writes every registered field, so one silently overwrites the other.
- Every settings row's **category must be a page the product draws**, and the
  declared category list must equal the set of constructed panels — in both
  directions.
- A **percent field must convert both ways**. One that divided by 100 on save
  with nothing multiplying back made its own window unsaveable on open.

### What this means for reading the rest of this document

The narrative sections here — *Solved:*, *Reversed:*, *What hardware testing
changed* — remain the most valuable material in the repository, because they
record **why** a decision was made or undone, which no check can capture. Treat
them as history, which they are and are good at.

Treat any **count, list, or "these are the N functions that…"** in prose as
unverified. If it matters, the enforced version is in a manifest or a validator.

## What 1.7.4 / 0.1.17 added

- A shared opaque, high-DPI GDI+ Quick Menu renderer with rounded selection,
  configurable accent, glow, neutral charcoal/gray palette, and no native outer
  border. Atomic in-session repaints reduce navigation flicker.
- Closed menus destroy their HWND and owned bitmap rather than retaining a
  hidden compositor surface that can return scrambled after a fullscreen game.
- Display mode discovery reads until Windows reports the true end of the driver
  table; the former 512-entry ceiling could stop a 4K TV at `1280×1024`.
- Recovery headings and wrapped explanations size correctly at high DPI.
- SteamShell 1.7.4 additionally fixes automatic-mouse cursor scope, expands an
  `explorer.exe` allowlist entry across Start/Search shell hosts, adds
  desktop-wide automatic mouse with exclusions and a tray toggle, and makes
  Return to SteamShell launch Steam Big Picture automatically.
- Settings schema advances 12→14 in SteamShell and 3→4 in XFE. Existing values
  remain authoritative; only missing new keys receive defaults.

1.6.0 completed the XFE parity port; 1.7.0 is the first release whose headline
features have no XFE counterpart, because they follow directly from standalone
SteamShell owning the shell—the thing XFE was built never to do. SteamShell now
survives exiting to the Windows desktop instead of terminating, keeping its
notification-area icon, controller mouse, and Quick Menu available on the normal
desktop, and it can replace the wallpaper and desktop icons with a black backdrop
in the gaps around Steam. `releases/1.7.0/` is the immutable release checkpoint;
`releases/1.6.0/` and `releases/1.5.0/` remain unchanged as its baselines.

## What 1.7.1 / 0.1.15 and 1.7.2 / 0.1.16 added

Both were locked on 2026-07-31 after maintainer validation on hardware. Their
`RELEASE.md` files record scope, verification status, known limits, and
checksums.

**SteamShell 1.7.1:**

- Steam startup is judged by a **Big Picture surface**, not by `ProcessExist("steam.exe")`. See *Solved: black screen after login* below.
- The RTSS Quick Menu gains the combined **Frame Limit** row, the conditional **Custom FPS** row, and **Save Limit to Profile**.
- The startup curtain yields the topmost band while one of SteamShell's own windows is on screen, which is what makes the recovery screen and the Settings chord reachable during a stalled boot.
- The controller Settings chord now requires a hold, declines while another surface owns controller input, and returns once fired.
- An audit removed 16 unreferenced functions and 8 dead Quick Menu handler cases, and declared 13 globals that existed only inside the functions that used them.

**SteamShell-XFE 0.1.15:**

- The same Frame Limit / Custom FPS / Save Limit to Profile design, applied in the same pass rather than ported either way.
- Motion-sensor exclusion in the controller learner's axis search, and a bounds guard on the wizard's Skip button. **Confirmed on hardware** with an 8BitDo Ultimate 2.
- Removal of the handler cases and functions left dead by the row merge.

Both validators were updated in step; their RTSS parity assertions still
described the removed `rtssLimiterState` row and would otherwise have failed the
build — which is exactly what happened, and is the reason the regex assertions
are now replayed in Python on the development machine before every build.

**SteamShell 1.7.2** — almost entirely fixes found by running it:

- **Save Limit to Profile** reported `No game in foreground` while a game was running and the Task Switcher listed it. The row used only the foreground captured when the menu opened, which is regularly `steam.exe`; it now falls back to the window engine's detected game.
- The window engine **centred dropdown menus**. Centring had no size or structure test at all, while maximising has always had two. Popups are now filtered structurally — and by size rather than ownership, after the first attempt fixed Explorer's dropdowns and missed Qt's.
- **Every log line has a timestamp and a level.** Only the game-score rows had one, because they stamped themselves; the operational log recorded what happened but not when.
- The desktop-restore failure screen is **controller-navigable**, matching the Steam-did-not-start screen. It was a native `MsgBox` the poll loop has no handling for — in the state where Explorer may be dead.
- Warnings **surface in the Quick Menu footer**. 52 of them were log-only, which on a couch device means nobody.
- The tray right-click shows the **native Windows menu** again. See *Reversed: the tray right-click interception* below.
- Custom FPS stepping is **debounced and hold-repeating**. See *Reversed: frame-cap step escalation* below.

**SteamShell-XFE 0.1.16:**

- The same debounced write and hold-to-repeat, applied in the same pass.
- The Save Limit to Profile fallback, using the last foreground that looked game-like.

### Reversed: frame-cap step escalation (July 31, 2026)

The Custom FPS row could not auto-repeat, because Quick Menu navigation is edge-triggered — the poll loop reports `buttons & ~prevButtons` and the menu handler only ever received edges. A fixed step of 1 therefore needed sixty presses to cross 60→120, so the step grew after several fast presses: 1, then 5, then 10.

**That made a tap mean different things at different times.** The same gesture produced 1, 5 or 10 depending on timing the user could not see, and fast tapping — the natural response to a value moving too slowly — silently became the thing that made it jump. Reported from hardware twice, the second time precisely: *"single press, regardless of how much time is in between, is still only a single increase."*

The fix was to stop treating presses as the speed control. The held button state is now passed into the menu handler, and speed comes from **holding**, accelerating the repeat *rate* rather than the step — 80 ms, then 40 ms, then 20 ms. Every change stays 1, so the value can be stopped exactly where wanted. That also removed grid-snapping, which existed only to make large steps land on round numbers.

Separately, each press had been writing straight to RTSS: a `LoadProfile` plus a `SetProfileProperty` plus a `SaveProfile` — a disk write — plus `UpdateProfiles`. The limiter was genuinely reconfigured a dozen times during a scroll and the frame rate chased the number. The value is now held pending and committed once, ~400 ms after input stops.

**Lesson.** An escalating step is a reasonable answer to "no auto-repeat", and it was the wrong one, because it makes the same input mean different things without telling the user. The constraint that produced it — edges only — was itself removable; the handler simply had never been given the held state.

### Reversed: the tray right-click interception (July 31, 2026)

1.7.0 took over the notification icon's right-click and showed the Quick Menu instead of the native Windows menu. The reasoning was sound as far as it went: AutoHotkey will not run a timer while a menu is displayed, controller polling is a timer, so a native tray menu freezes controller-as-mouse for as long as it is open — and a controller user could open a menu they were then unable to navigate.

**It had the context backwards.** Reaching a tray icon at all means using a pointer, and a controller user opens the Quick Menu with L3+R3 or `Ctrl+Alt+Shift+Q` rather than steering a cursor into the notification area. The interception optimised for a case that barely occurs at the cost of the one that occurs constantly: someone at a keyboard and mouse wanting a small, fast menu where they clicked.

The freeze is accepted rather than forgotten — anyone who does reach the menu by controller emulation dismisses it the way any menu is dismissed, and the pointer that opened it can do that. Double-click still opens the Quick Menu.

**Lesson, and it generalises.** The original decision reasoned correctly about the *mechanism* and never asked who is holding what when the situation arises. A guard against an input method is only worth its cost where that input method is actually in use.

### Solved: black screen after login (July 31, 2026)

**Symptom.** Intermittently, on a ROG Xbox Ally X, the device reached a black screen after login and stayed there. The same build on a wired HTPC never did it. Because SteamShell is registered as the Winlogon shell, there was no taskbar, no Explorer desktop, and no visible cursor to recover with.

**Cause.** `MonitorShell` judged Steam's health by `ProcessExist("steam.exe")`. That is a poor proxy at boot: the process appears almost immediately and then sits on a "Connecting", sign-in, or client-update window for as long as the network takes. On Ethernet the Big Picture window wins that race; on Wi-Fi, with association, DHCP and DNS still in flight, it does not.

The consequence was not merely a slow start. Seeing the process set `SteamObservedRunning` on the very first tick, and **every branch that could raise the recovery screen is nested under `!SteamObservedRunning`** — so the screen became permanently unreachable, the session was marked `ACTIVE`, and the startup curtain stayed up over nothing. There is no network readiness check anywhere in the startup path; Steam is launched the instant Winlogon starts the shell.

**Fix.** Startup and steady state are now judged by deliberately different signals. Until Big Picture has been seen, a running `steam.exe` proves nothing; observation requires a Steam-owned window covering at least 60% of its monitor in both dimensions. Once seen, the observation is **latched** and never re-tested, so a game covering or minimising Big Picture cannot re-open the startup path.

Coverage rather than title is the discriminator on purpose. It survives client updates, a renamed or localised window title, and the `steam.exe`/`steamwebhelper.exe` ownership split — none of which a title match survives on its own. The existing permissive matcher is unchanged and still used for refocus; its 4096-pixel floor is right for "find something worth activating" and wrong for "has Steam finished starting", because Steam's own startup dialogs clear it easily.

**Three things had to move together, and that is the interesting part.** Fixing the health check alone would have changed nothing:

1. `ShowStartupRecovery` and `ShowPendingStartupRecovery` both returned early when `steam.exe` existed — the exact state a stalled boot is in. They would have dismissed the screen the instant it tried to appear.
2. `LaunchSteamBpm` latched observation whenever Steam was already running, so **Retry** on the recovery screen marked the session healthy, dismissed the screen, and stranded the user with no way to raise it again.
3. The splash guard re-asserted topmost twice a second with no awareness of SteamShell's own windows, so the recovery screen would have been buried within 500 ms of appearing.

**Lesson.** A liveness check and a readiness check are different questions, and a process handle answers only the first. The deeper failure was structural: the recovery path was gated behind the very flag the bug set wrongly, so one bad inference disabled the mechanism built to survive it. Recovery paths should not depend on the state they exist to recover from.

## At-a-glance comparison

| Area | SteamShell 1.7 | SteamShell-XFE |
|---|---|---|
| Status | Locked release 2.0.1 | Locked release 2.0.1 |
| Current working version | 2.0.2 | 2.0.2 |
| Primary role | Complete Steam-centered Windows shell | Utility companion to Xbox FSE |
| Owns the Windows shell | Yes, when installed or registered as the shell | No |
| Launches and monitors Steam | Yes | No |
| Manages Explorer and the taskbar | Yes | No |
| Manages window focus and geometry | Yes | No; Xbox FSE owns presentation |
| Quick Menu | Yes | Yes |
| Full Settings interface | Yes | Yes, with XFE-specific options |
| Controller mouse and mappings | Yes | Yes, working inside Xbox FSE via RawInput |
| Task switcher | Custom switcher with focus pinning | Custom switcher, one-shot activation only |
| Portable operation | Yes | Yes |
| Installer required | No | No installer is provided or intended |
| Best use | Dedicated Steam Big Picture HTPC | Xbox FSE system needing extra controls |

## Design principles shared by both applications

- Provide a controller-first experience suitable for a television.
- Preserve keyboard hotkeys as recovery and testing paths.
- Remain usable as a portable executable.
- Keep configuration in a readable INI file beside the executable.
- Favor bounded retries, validation, and recoverable failure over endless automation loops.
- Avoid unnecessary polling and synthetic activity that can prevent Windows from sleeping.
- Keep advanced options available without overwhelming the normal user.

---

# SteamShell 1.7

## What SteamShell 1.7 is trying to accomplish

SteamShell 1.7 turns a dedicated Windows gaming PC into a Steam-centered console. It is designed for a machine that normally boots directly into Steam Big Picture and is operated primarily with an Xbox-compatible controller.

It coordinates the entire session:

1. SteamShell starts and prepares the gaming environment.
2. Explorer may remain available in the background for Windows components such as Game Bar and UWP applications, while its desktop-facing UI stays hidden.
3. Steam Big Picture becomes the main interface.
4. Games, launchers, and explicitly favored applications are brought forward when appropriate.
5. Controller mappings and the Quick Menu provide access to common Windows and performance functions.
6. Exiting Steam to the desktop restores Explorer and the taskbar in a controlled sequence, and SteamShell stays resident so its controller controls remain available on the desktop.

## Current release state

- **Stable release:** 2.0.1, frozen with XFE in `releases/2.0.1`
- **Active source:** 2.0.2 in `SteamShell/`
- **Runtime:** AutoHotkey v2, 64-bit
- **Validated compiler baseline:** AutoHotkey v2.0.26 64-bit
- **Settings schema:** 18
- **Distribution model:** One portable executable, with optional installation/registration

The `releases/1.7.0` directory is the permanent release snapshot and should not
be casually edited. Later development must use a later version.

## Core session and shell features

### Steam lifecycle

- Launches Steam in Big Picture mode.
- Detects and monitors the Steam session.
- Returns focus to Steam when a game or application closes and no better foreground candidate remains.
- Provides explicit Steam recovery and refocus controls.
- Supports an orderly **Exit Steam to Desktop** flow.

### Explorer and taskbar management

- Uses an Explorer background or “ghost” mode so Windows features that depend on Explorer can continue to work.
- Hides the taskbar and related shell surfaces during the console session.
- Uses a Windows event hook to react when taskbar windows reappear.
- Retains a low-frequency safety check in case an event is missed.
- Suspends shell hiding during the desktop restoration process.
- Optionally replaces the wallpaper and desktop icons with a black backdrop, using the same event-hook and periodic-safety pattern. It owns no system or registry state: the wallpaper setting is never touched, and everything it changes dies with the process or is undone by the Explorer restart that unexpected-exit recovery already performs.

### Desktop restoration and desktop mode

The desktop exit operation does not permanently remove SteamShell as the configured shell. It:

1. Stops SteamShell's taskbar guard and desktop blackout.
2. Unhides the taskbar, desktop, and shell windows.
3. Temporarily restores the normal Explorer shell state.
4. Starts or restarts Explorer and verifies that the desktop is usable.
5. Restores SteamShell's shell registration for the next boot.
6. Enters **desktop mode** rather than exiting.

Since 1.7.0, a session restore leaves SteamShell resident. Explorer owns the desktop again, but the notification-area icon, controller-as-mouse, and Quick Menu keep working on the normal Windows desktop. Shell monitoring, the window engine, the taskbar guard, cursor handling, and launcher cleanup are unscheduled while controller polling stays alive; no persisted setting is modified, and returning re-enables them after the Big Picture launch request is accepted.

SteamShell 1.7.4 enables controller mouse mappings across all ordinary
foreground applications while desktop mode is active. A persisted tray/Settings
toggle can disable that behavior immediately, and an explicit executable
exclusion list protects games or other applications that need raw controller
input. SteamShell presentation continues to use the narrower opt-in allowlist.

Returning to the shell is explicit — Quick Menu or the tray — and always passes
through SteamShell's Big Picture launch helper before re-arming shell mode. The
Quick Menu's **Launch Steam** row uses the same transaction. Steam started by
hand from the desktop deliberately does not re-arm, so browsing a library from
the desktop never takes the desktop away.

A **permanent** restore still exits the process, because it has deregistered SteamShell as the Windows shell and there is nothing left to own. **Exit SteamShell** fully terminates: directly from desktop mode, or via the guarded restore first from shell mode, so it can never leave the user with a hidden taskbar and no shell.

Killing SteamShell while it is in desktop mode deliberately triggers no Explorer recovery. Explorer is already the healthy visible shell and the registry already holds the intended value; running the recovery would kill the desktop in use and silently drop SteamShell as the next-sign-in shell.

Separate Settings actions allow the user to deliberately make SteamShell the Windows shell or permanently restore the Windows desktop shell.

## Coordinated Window Engine

SteamShell uses the coordinated engine introduced in 1.5 rather than several
independent focus loops. A single inventory of valid windows feeds the focus,
game detection, AlwaysFocus, geometry, and recovery decisions.

The engine considers:

- Whether SteamShell's own Quick Menu or Settings interface owns focus.
- Explicitly pinned or selected application windows.
- Applications in the AlwaysFocus list.
- Active game and fullscreen-style windows.
- Steam Big Picture when no application remains.
- Window visibility, validity, process identity, dimensions, ownership, and other eligibility checks.

This reduces competing focus decisions. It also allows bounded activation attempts and records why a window won, lost, or was ignored.

### Focus and geometry controls

- Configurable foreground sensitivity score, with a default of **55**.
- Steam refocus delay.
- Optional game foreground assistance.
- Option to run assistance only while Steam is the foreground application.
- AlwaysFocus executable list and manager.
- Maximum-width threshold for deciding when to center or maximize a window.
- Executable exclusions for applications that should never be centered or maximized.
- Compatibility handling for older and unusual windows, including legacy 32-bit games.

Steam itself is intentionally not listed in the AlwaysFocus manager because it is handled as a dedicated fallback by the Window Engine.

## Controller support

SteamShell uses XInput for Xbox-compatible controller input.

### Default interaction model

- Hold **View/Back** as the controller mapping modifier.
- While View/Back is held, mapped buttons can perform short-press and long-press actions.
- **View/Back + Start, short press:** open the Windows Start menu.
- **View/Back + Start, long press:** open File Explorer.
- Hold **L3 + R3** to open or close the Quick Menu.
- Hold **LB + RB + L3 + R3** to open SteamShell Settings. (Still works if you also hold the triggers; they are ignored rather than forbidden.)
- Default controller deadzone: **4000**.

Mappings are configurable and can target built-in actions or recorded keyboard shortcuts. Long-press actions are separated from normal presses to avoid accidental activation.

### Controller mouse

- While View/Back is held, the right stick controls the pointer and the left
  stick scrolls.
- Controller buttons provide click and navigation actions.
- Full Settings enables right-stick pointer movement and the configured RB click
  automatically. That automatic pointer context follows native dialogs and
  SteamShell companion windows opened from Settings, while category switching
  and saving remain scoped to the main Settings window.
- Settings uses LT/RT to change categories so RB remains available for pointer clicking.
- Mouse speed and deadzone are configurable.

## Cursor behavior and sleep

- Automatically hides an idle cursor.
- Parks the cursor at boot, when a game/fullscreen-style window enters the
  foreground, and when returning focus to Steam, when enabled.
- Parks against the configurable left or right vertical edge.
- Uses a direct cursor-position operation instead of continuously generating mouse movement.
- Keeps the cursor hidden while it is being parked.
- Avoids a permanent mouse-parking timer so Windows idle and sleep detection are not continually reset.

## Quick Menu

The Quick Menu is a borderless controller-first overlay for common living-room
actions. During one open session it takes foreground ownership, supports keyboard
navigation, and updates rows/pages without recreating the window. Closing it
destroys the HWND and row bitmap so DWM cannot carry a hidden stale surface across
fullscreen game transitions. It uses DPI-aware centering and shaping; its layout
can be customized, and unnecessary items can be hidden.

Available functions include:

- XFE-matched Audio submenu with Output, Volume, and Mute.
- XFE-matched Display & HDR submenu with independently staged Resolution,
  Refresh rate, and Windows Scale choices.
- One guarded Apply transaction with automatic 15-second resolution,
  refresh-rate, and scale reversion.
- Live primary-display HDR state and explicit On/Off control.
- XFE-matched RTSS & Performance submenu with disabled, missing,
  ready-to-start, and running states.
- RTSS overlay and frame-limiter control with custom frame-cap support.
- Live RTSS global state and foreground-profile frame-cap display through
  `RTSSHooks64.dll`, with the configured shortcuts retained as fallback.
- Context-aware Steam Menu and Steam Quick Access actions. Steam's in-game
  overlay uses a paced Shift+Tab event so the game hook can observe the chord.
  With Steam closed the row becomes **Launch Steam**, which starts Big Picture
  and returns SteamShell to shell mode.
- Controller Mappings submenu via a main-page hold-Y gesture, with a final
  **Set Controller Mappings** row for the full editor.
- Task Switcher: **A** switches once, **Y** switches and applies a session focus
  lock, **X** requests close, and holding **X** force-closes the process.
- Game Bar, Open Keyboard, persistent Mouse Mode, Full Settings, Windows
  Settings, sleep, restart, shutdown, and recovery actions.
- Context-aware System rows: **Exit Steam to Desktop** in shell mode becomes
  **Return to SteamShell** in desktop mode, alongside a distinct **Exit
  SteamShell** that fully terminates. Both require a second press to confirm.
- Direct access to SteamShell and Windows Settings, plus an immediate-effect
  **Black Desktop Background** toggle.

The notification-area icon's right-click opens the Quick Menu rather than a
native Windows menu. AutoHotkey will not run a timer while a menu is displayed,
and controller polling is a timer, so a native tray menu froze
controller-as-mouse for as long as it was open. Every action the tray menu
offered is reachable from the Quick Menu.

RTSS defaults include:

- Executable: `C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe`
- Overlay on: `Ctrl+Shift+1`
- Overlay off: `Ctrl+Shift+2`
- Frame limiter on: `Ctrl+Shift+5`
- Frame limiter off: `Ctrl+Shift+6`

These shortcuts must correspond to configured RTSS profiles or hotkeys on the target computer.

## SteamShell Settings

SteamShell Settings is the primary persistent configuration interface. The smaller Control Panel remains available for temporary session controls, timed focus disabling, and live-log viewing; related health and maintenance tools also appear under Settings.

Main categories include:

- General
- Startup & Splash
- Startup Programs
- Controller & Cursor
- Focus & Windows
- RTSS & Performance
- Launcher Cleanup
- Advanced & Logging

Settings features include:

- Standard Windows title bar with Close and Minimize; Maximize is disabled.
- Monitor-bounded height, fixed width, scrollable categories, and overlap audits.
- Controller and mouse navigation that follows Settings-owned dialogs and
  SteamShell companion windows.
- Scrollable category pages.
- Browse buttons for executable paths.
- Add/remove lists for startup programs, launcher cleanup, exclusions, and AlwaysFocus applications.
- Shortcut recording for controller, RTSS overlay, and frame-limiter actions.
- Controller testing and calibration.
- Health check and self-test results.
- Diagnostic ZIP creation.
- Settings backup, import, export, category reset, and full reset.
- Safe Mode and setup assistance.
- Default-on elevated input-helper toggle with an explicit warning about
  controller mouse/input limitations in administrator applications when disabled.
- Clear status for unsaved changes.

The INI maintenance layer adds new settings and removes obsolete managed settings without replacing unrelated user values. Migration creates backups and uses transactional file replacement.

## Startup programs and launcher cleanup

- Optional programs can start silently with the console session.
- Executable paths can be added through the Settings file picker.
- Launcher cleanup can close selected launcher processes after games end.
- A separate protected list prevents important executables from being closed.
- Cleanup is optional and does not need to be enabled for normal operation.

## Logging, recovery, and diagnostics

- Runtime log beside the executable.
- Startup health checks.
- Safe Mode.
- Self-test and validation commands.
- Settings and registration repair.
- Diagnostic archive creation.
- Bounded recovery when Explorer, Steam, or a selected window does not respond as expected.

Useful recovery hotkeys:

| Hotkey | Action |
|---|---|
| `Ctrl+Alt+Shift+Q` | Open Quick Menu |
| `Ctrl+Alt+Shift+S` | Open SteamShell Settings |
| `Ctrl+Alt+Shift+E` | Emergency exit and permanently restore the Explorer desktop |
| `Ctrl+Alt+Shift+R` | Reload `SteamShellSettings.ini` |
| `Ctrl+Alt+Shift+G` | Run Game Foreground Assist once |
| `Ctrl+Alt+Shift+P` | Open the session Control Panel |

## Portable and installed operation

SteamShell does not require an installer to run.

### Portable use

- Compile or copy `SteamShell.exe` to the desired directory.
- Keep its INI and optional assets beside it.
- Run it directly.
- Portable mode can use all normal application features.

### Optional installed shell use

The recommended managed layout installs the main executable under:

`%ProgramFiles%\SteamShell\SteamShell.exe`

Settings, logs, and backups live under `%ProgramData%\SteamShell`; current-location
and browsed portable layouts remain available through Setup Assistant.

`rtss-request.ini` appears in that directory once the elevated helper has been
asked to write an RTSS frame cap. It is a request rather than configuration —
an FPS value, an optional profile name, and a sequence number — kept out of
`SteamShellSettings.ini` so a transient message never stages through the
settings transaction, and so the whole of what crosses into the elevated process
is one small file. It is not cleaned up on exit and is safe to delete.

The assistant is monitor-height bounded and vertically scrollable for television
DPI scaling. Its height is calculated from the target monitor's physical work
area and effective DPI, capped at 80% initially and re-measured before display.
It displays the resolved Steam and optional RTSS executable paths,
checks their usual Program Files locations automatically, and keeps owned
confirmations above the wizard. UAC Settings and external documentation
temporarily lower/minimize the assistant so their windows remain visible.

Install and upgrade require an explicit **Run as administrator** maintenance
launch. A normal attempt records a one-time user/session-bound request, restores
Explorer, and exits after explaining the relaunch. Elevated Setup consumes that
request, rejects cross-account elevation, closes existing same-identity main and
helper processes, and then opens the Explorer-backed assistant. It never silently
promotes the ordinary shell process.

During an elevated Setup session, the assistant can also configure Windows
Auto-Login. Credentials are validated by Windows before the documented
`DefaultPassword` LSA secret is stored; no plaintext password is written to the
SteamShell INI, log, registry value, or a process command line. Disable removes
both the protected secret and any plaintext fallback value.

Selecting an existing sidecar portable directory with Portable enabled is an
upgrade operation: the existing INI is preserved, both the main EXE and embedded
helper are staged and replaced, and the helper's expected file version is
verified before success is reported. After target verification, only a
pending/in-progress `SteamShell` sidecar beside the separate updater is removed;
the installed target, completed configurations, links/junctions, and any source
containing the target are protected. The updater then exits. The owned completion
dialog offers Restart Now, which requests a normal immediate Windows reboot, and
Restart Later.

Supported maintenance commands include:

- `/install`
- `/repair`
- `/restore`
- `/uninstall`
- `/safe`
- `/selftest`

Starting in the 1.7.8 development line, locked as 1.9.9, `SteamShell.exe` stays at normal integrity so
its Quick Menu and Settings correctly take controller focus away from Steam. An
embedded `SteamShell-Helper.exe` is extracted separately and runs High only for
safe controller input and coordinated window geometry for High-integrity
applications. The main process
accepts it only after path, user, session, and token-integrity verification.
Steam, startup applications, RTSS, MPV, Explorer, and ordinary Windows utilities
therefore remain Medium integrity. Health Check reports both privilege states and
the observed integrity of core external processes.

---

# SteamShell-XFE

## What SteamShell-XFE is trying to accomplish

SteamShell-XFE is a companion application for Microsoft's Xbox Full Screen Experience. It is not intended to replace Xbox FSE, Steam, or the Windows shell.

Its goal is to provide selected SteamShell conveniences while letting Xbox FSE remain responsible for:

- The Home application.
- Fullscreen presentation.
- Window sizing and focus.
- Taskbar and desktop transitions.
- Starting and returning to the primary gaming interface.

The companion should remain alive if Steam closes or restarts. Its useful functions should be available independently of the selected Xbox FSE Home application.

## Current state

- **Working version:** 1.9.9
- **Last locked release:** 1.9.9, frozen with standalone in `releases/1.9.9`
- **Status:** Windows-validated locked release source
- **Runtime:** AutoHotkey v2, 64-bit
- **Settings schema:** 8
- **Privilege target:** Standard user
- **Distribution model:** Portable companion executable

The application works when launched and tested from the normal Windows desktop. Its Quick Menu and Settings UI use rendered dimensions for centering. Quick Menu controls persist while the menu is open and the complete window is destroyed on close, preventing stale DWM surfaces across fullscreen transitions.

## Included features

- Controller-first Quick Menu UI.
- Audio output, volume, and mute controls.
- Resolution and refresh-rate selection with timed reversion.
- Windows display-scale selection, staged with resolution and refresh rate and
  covered by the same timed reversion.
- State-aware primary-display HDR status and explicit On/Off control.
- RTSS overlay and frame-limiter shortcuts.
- Controller mappings with short and long actions.
- Controller mouse.
- Touch Keyboard and classic On-Screen Keyboard actions.
- Cursor hiding and parking, against either vertical edge at a configurable height — centre-right by default, where a cursor that briefly reappears is least visible on a TV.
- Default-on cursor parking when a game/fullscreen-style window enters the
  foreground, with a delayed foreground check that avoids moving the pointer in
  a window that replaced it.
- Windows Game Bar.
- Task switcher listing switchable windows, with close and force-close.
- Context-aware Steam Menu and Steam Quick Access actions, from the Quick Menu or the View button.
- Optional assist features: Game Focus Lite, Steam Assist Lite, Launcher Cleanup Lite.
- Assist game detection combines fullscreen/borderless shape with conservative
  CPU sampling for minimized games; delayed hard-kill is restricted to the
  original PID and process creation identity and rechecks safety gates.
- Assist suspension while a shell overlay such as the Xbox FSE task switcher is on screen, matched by process name or window class.
- Quick Menu Settings page: live toggles for the assist features, the overlay suspension, and the View button actions, each written to the INI on the spot, plus Windows Settings.
- Main-page Open Keyboard, persistent Mouse Mode, and hold-Y access to Controller Mappings.
- Independently switchable View button tap and hold actions.
- Probe Screen: a delayed, read-only capture of every visible window with process, class, geometry, and topmost/foreground state.
- Startup programs, launched de-elevated when the companion is elevated, with a Normal/Minimized/Hidden launch window mode ported from SteamShell 1.5 and enforced for a few seconds after launch.
- Optional Scheduled Task that starts the companion at logon, registered from XML so it runs on battery and survives undocking.
- Diagnostic ZIP export.
- Full keyboard operation of the Quick Menu.
- Sidebar Settings interface.
- Health check.
- Heartbeat, all-slot controller diagnostics, and a RawInput report probe.
- Sleep, restart, shutdown, and related power actions.
- RawInput, XInput, and GameInput backends with automatic selection.
- Empirical RawInput controller-learning wizard with persistent per-device profiles.
- XInput controller discovery across slots 0 through 3.

XFE hotkeys:

| Hotkey | Action |
|---|---|
| `Ctrl+Alt+Shift+Q` | Open Quick Menu |
| `Ctrl+Alt+Shift+S` | Open Settings |
| `Ctrl+Alt+Shift+P` | Open Settings (the same chord opens standalone SteamShell's Control Panel) |
| `Ctrl+Alt+Shift+R` | Reload the companion |
| `Ctrl+Alt+Shift+I` | Re-arm controller input after sleep |
| `Ctrl+Alt+Shift+D` | Delete the learned controller profile and restore the built-in layout |
| `Ctrl+Alt+Shift+X` | Exit the companion |

## The architectural boundary (revised, 0.1.6)

The boundary was originally "no window engine at all". Testing showed that was drawn in the wrong place: the useful half of SteamShell 1.5's engine — the window inventory and game detection — carries no risk of competing with Xbox FSE, because it only *reads*. What competes is the geometry layer.

**The boundary is now: inventory and detection yes, presentation never.**

Used by the XFE companion:

- Window inventory and classification (a standalone implementation, not the 1.5 engine).
- Game detection, including the CPU heuristic, which is what makes automatic launcher cleanup safe.
- One-shot window activation, on explicit request.

Never present, and enforced by `Validate-SteamShell-XFE.ps1`:

- **Window sizing, centring, maximising or restoring.** The validator forbids `WindowEngineApplyGeometry`, `WindowEngineIsGeometryCandidate`, `WinMaximize(` and `WinMinimize(` by name.
- Focus pinning and continuous focus enforcement.
- Winlogon shell registration, repair, or restoration.
- Explorer lifecycle management.
- Taskbar hiding or guarding.
- Steam launch, monitoring, recovery, or exit monitoring.
- Splash-screen ownership.
- SteamShell installation workflow.
- **Self-elevation.** The validator permits `*RunAs` only for `schtasks.exe`, and forbids it entirely when the target is the companion's own path.

Two features previously listed as excluded — startup programs and launcher cleanup — are now included, because neither touches window presentation. Launcher cleanup is automatic and keeps 1.5's safety guards, which the ported game detection makes possible.

## Elevation: tested and rejected

The companion runs at **normal privileges**, and the optional logon task never requests elevation.

While an elevated window of the companion holds the foreground, **Steam cannot inspect it**, so Steam never registers that it lost focus and keeps acting on controller input underneath the Quick Menu. Both applications respond to the same press, and an A press can activate something in Steam while the user is choosing Sleep or Shutdown. Measured on hardware, July 2026.

The accepted cost: at normal privileges the companion cannot send input to, activate or close windows owned by elevated applications, so controller mappings silently do nothing while an elevated anti-cheat game is in front.

The companion never relaunches itself elevated — a non-elevated parent starts it, so that would raise a UAC prompt on every boot. A Scheduled Task created from Settings → Advanced is the supported route, and it is created without highest privileges.

## Intended Xbox FSE configuration

The planned AnyFSE arrangement is:

1. Use AnyFSE's built-in Steam Big Picture launcher as the Home application.
2. Add `SteamShell-XFE.exe` as a startup companion application.
3. Turn off **Exit FSE when Home app exits** so the FSE session survives a Steam restart.
4. Do not configure SteamShell-XFE itself as the Home application.

SteamShell-XFE does not need to be elevated for its normal target design, and it must run in the same interactive user session as the controller-driven experience.

## Solved: controller input inside Xbox FSE (July 25, 2026)

**Xbox FSE withholds controller input from background processes at a layer beneath both XInput and GameInput. RawInput reads underneath that layer and receives the complete gamepad state.** Version 0.1.5 ships a RawInput backend, and the companion is functional inside FSE for the first time.

### How it was established

Each step was measured rather than inferred, and several plausible theories were disproved along the way.

| Finding | Evidence |
|---|---|
| Not a device or driver limitation | `XInputGetCapabilities` reports `buttonmask=0xF3FF` — the pad declares every button in question |
| Not Steam Input, and not virtualisation | Only one XInput slot is ever populated; no duplicate or synthesised device exists. Also reproduced with the Xbox app as Home and Steam not running at all |
| Not the companion dying or being suspended | Heartbeat entries continue throughout the FSE session |
| Not elevation | Tested elevated, no change |
| Not a GameInput focus policy | `SetFocusPolicy` only lets an application **opt out** of background input; the default already permits it |
| Not fixable by changing backend | XInput and GameInput report **byte-identical** state at every sample, including all-zero inside FSE. On Windows 11 XInput is layered over the same gaming-input stack, so they are not independent observers |
| Presentation was never the problem | The Quick Menu displays correctly inside FSE, and keyboard hotkeys reach the background companion |

The decisive measurement was a diagnostic that sampled **all four XInput slots plus GameInput on one tick**, alongside a RawInput probe. Inside FSE, with `fg=ApplicationFrameHost.exe`, XInput and GameInput both read `0x0000` while RawInput delivered full HID reports.

### Why RawInput works

RawInput registered with `RIDEV_INPUTSINK` receives HID reports from the HID stack regardless of foreground ownership. That is a genuinely different path from the Xbox gaming-input stack that FSE gates.

The report layout was derived empirically by pressing known buttons and reading the raw bytes. For the controller tested (16-byte report):

| Bytes | Meaning |
|---|---|
| 1–2, 3–4, 5–6, 7–8 | LX, LY, RX, RY — 16-bit LE, `0x8000` centre, `0x0000` = left/up |
| 9–10 | Combined trigger axis — `0x8000` neutral, above = LT, below = RT |
| 11 | A, B, X, Y, LB, RB, View, Menu (bits 0–7) |
| 12 | L3, R3, Guide (bits 0–2) |
| 13 | D-pad hat, 1–8 clockwise from north |

All eight test buttons decoded correctly and in the order pressed, including the View, Menu, L3 and R3 that XInput never sees inside FSE.

### Consequences for the design

- **`auto` is the default backend.** RawInput is silent outside FSE and XInput reads zeros inside it, so neither works everywhere alone. Auto uses whichever is currently producing data.
- **The triggers cannot both be read on RawInput.** They share one axis and cancel out, so the Settings chord dropped its trigger requirement and is now **LB + RB + L3 + R3**, held. The old six-button press still satisfies it.
- **The decoder is controller-specific.** It accepts only 16-byte reports and locks to the first device producing one, falling back to XInput for anything else. Other pads may need their layout added.
- **GameInput remains selectable purely as a documented negative result.** It is provably identical to XInput here and offers nothing.

### Superseded conclusions

Earlier revisions of this document asserted, in order, that Xbox FSE's background input routing was at fault, then that Steam Input was virtualising the pad, then that no input-backend work could fix the problem. **All three were wrong** and are recorded here only so the same theories are not re-explored. The evidence against each is in the table above.

## Solved: the logon task registered but never ran (0.1.7)

**Symptom.** Settings → Advanced → Create Logon Task reported success, the task was visible and healthy in Task Scheduler, and the companion did not start after a reboot.

**Cause.** The task was created with `schtasks /create /sc onlogon`, which takes Task Scheduler's default conditions. Those defaults include `DisallowStartIfOnBatteries = true` — "start the task only if the computer is on AC power". On a ROG Ally running undocked, the trigger fired at every logon and Windows declined to start the task every time. Nothing reports this as an error; the task simply shows no last-run result.

**Fix.** The task is now registered from an explicit XML definition via `schtasks /create /xml`, which sets `DisallowStartIfOnBatteries=false`, `StopIfGoingOnBatteries=false` (undocking would otherwise terminate the companion), `ExecutionTimeLimit=PT0S` (the default terminates it after 72 hours), `RunLevel=LeastPrivilege`, and a 10-second logon delay so the shell and Xbox FSE come up first. The `<Settings>` element order is copied from a Task Scheduler export, because the schema is order-sensitive and rejects a rearranged file wholesale.

**Diagnostic added.** Settings → Advanced → **Check Logon Task** dumps `schtasks /query /v` to the log, including Last Run Time and Last Result. The absence of that information is why the original failure could only be guessed at.

**Lesson, and it is a general one.** A convenience wrapper that inherits defaults inherits *all* of them, including ones chosen for a desktop on mains power. This project targets a battery-powered handheld, where several Windows defaults are actively wrong. The validator now rejects the `/sc onlogon` form by name.

## Implemented: learned RawInput controller profiles (0.1.8)

The built-in fallback remains specific to the ROG Ally's 16-byte report, but it is no longer the only RawInput layout that can be decoded. **Settings → Controller & Cursor → Learn Controller** records an empirical profile for the HID gamepad the user actually operates.

The wizard captures a neutral baseline, filters bits that jitter at rest, and prompts for each button, D-pad direction, stick axis, and trigger. It supports active-high and active-low buttons, masked hats that may share a byte with buttons, four independent D-pad bits, 8-bit axes, 16-bit little- and big-endian axes, measured travel, separate triggers, and shared trigger axes. Axis width and byte order are chosen from the whole movement path rather than one endpoint, because a 16-bit low byte wraps repeatedly during travel and otherwise looks like a stronger 8-bit field.

Profiles live beside the settings file as `<settings>-Controllers.ini`, keyed by VID/PID plus interface and collection where available. They are validated against the saved report length before use and take precedence over the Ally fallback. Cancelling the wizard or having no profile changes nothing about existing input behavior.

**Both products, since August 2026.** The backend, the profile store and the wizard live in `SteamShell-Shared.ahk`; this section's "the companion" was true when it was written. Standalone needed it more sharply than the companion did: a controller XInput cannot see left the *shell* with no input at all, on a machine with no taskbar and no Start menu to fall back to. Standalone's Settings chord moved from `LT+RT+LB+RB+L3+R3` to `LB+RB+L3+R3` at the same time, because non-XInput backends commonly report both triggers on one shared axis where they cancel out — making the old chord unreachable on exactly the controllers the backend exists for, and it is the only keyboardless route to Full Settings.

| Controller | Desktop | Inside Xbox FSE |
|---|---|---|
| ROG Ally built-in | Works | Works (measured) |
| 8BitDo Ultimate 2, DInput mode | Works (measured) — learned, 34-byte report | Learn once, then decode through its saved RawInput profile |
| Other byte-aligned HID gamepad (DualShock, Switch Pro, 8BitDo DInput) | Works via XInput | Learn once, then decode through its saved RawInput profile |
| Xbox Wireless Controller / XInput-only pads | Works via XInput | Dead — XUSB typically publishes no HID gamepad collection, so RawInput never sees the device |

This still cannot invent a HID collection that does not exist. XInput-only/XUSB pads remain unavailable inside FSE, and unusually packed sub-byte axes or devices that switch report formats may still require HID-descriptor parsing or a hand-written profile. Rejections remain logged per device rather than failing silently.

### Solved: motion sensors defeated the axis search (July 31, 2026)

**Symptom.** An 8BitDo Ultimate 2 in DirectInput mode learned all eleven buttons and the D-pad without trouble, then failed every stick step twice in a row. The report counter on the opening scan climbed past 5000 without the controller being touched.

**Cause.** Two things, both the gyro. The report is 34 bytes at roughly 1 kHz, and **12 of those 34 bytes were still changing with the controller at rest** — six 16-bit motion axes. The axis search ranks candidates by how far they travelled, and a motion axis travels its full range continuously, so it beat the real stick on every step:

```text
Learn: rest sampled from 1822 reports; 12 of 34 bytes changed during rest.
Learn: LX not detected -- byte 22 u8 rests at 0% of range, and a stick rests at the centre.
Learn: RT = byte 22 u16le neutral 62720 direction -1
```

The four sticks were rescued by the existing rest-at-centre rule. **RT was not.** A trigger legitimately rests at an end of its range, so it had no equivalent sanity check — and bound itself to a motion byte, which then saved into the profile as a permanently deflected trigger.

**Fix.** A byte that was still changing across four or more of its bits while nothing was held is treated as free-running and withheld from the axis search. The discriminator is bit count, not movement: a stick resting at centre jitters in its lowest one or two bits, while a motion axis saturates the byte. If the filter leaves no candidate at all, the search retries once with those bytes restored and logs that it did, so a controller whose sticks genuinely jitter widely stays learnable.

**Also fixed in the same pass.** `ControllerLearnNextStep` increments the step index unconditionally, so after the final step it sits one past the end while the wizard finishes and saves. Skip is a GUI button and can be clicked inside that window — which indexed the step array out of range and threw `Invalid index: 23`. It now checks the upper bound as well as the lower one.

**Lesson.** The axis heuristics all assume a control that *returns to rest*. Every rule that survives contact with hardware here — little-endian only, a stick rests at centre, sticks cannot share bytes — is a statement about resting behaviour. A sensor that never rests is outside that model entirely, and the honest fix was to exclude it rather than to weaken a rule that was doing its job.

**Not solved, and worth stating.** This device returned no device path, no HID VID/PID, and no preparsed descriptor, so its profile is keyed on report length (`LEN_34`) and any other 34-byte pad would match it. The missing preparsed descriptor also means HID-descriptor parsing — the proper fix for guessing at layouts at all — is not currently available for this device through that route.

### Why DirectInput was not added

The obvious reading of "the controller needs DirectInput mode" is that the companion needs a DirectInput backend. It does not, and building one would have been a mistake.

"DirectInput mode" is a label on the controller, not a wire protocol. What the pad emits in that mode is an ordinary HID report, and RawInput is already registered for **both** the HID Gamepad (`0x05`) and Joystick (`0x04`) usages precisely because controllers vary in which they report. The bytes were arriving correctly the entire time; only the learner's heuristics were confused.

A `dinput8` backend would have been a second, weaker path to the same data: manual COM vtable calls with no typelib, no per-device profiles, a combined trigger axis, and no Guide button. The cheaper alternative — the legacy `joyGetPosEx` API — has the same layout ambiguity with less control.

The general form: when a device "needs mode X", check what mode X actually puts on the wire before adopting the API named after it.

## Solved: the controller cursor stepped along its path (August 2026)

**Symptom.** Controller mouse movement had been jittery since the first version — "ticking along the path" rather than travelling it. Speed and responsiveness were never wrong, which is why it read as a rendering problem and went unexamined for so long.

**Cause, and it was not in the mouse code.** **Windows quantises timers to about 15.625 ms** unless a process raises the resolution, and none of the three programs does. A timer fires on the first tick boundary at or after its requested interval — so `ControllerPollIntervalMs = 16`, sitting **0.375 ms past a boundary**, could not fire at 15.625 and waited for 31.25. Every product polled at roughly **32 Hz while the setting implied 62.5**. Because 16 is only marginally over the boundary, ordinary scheduling noise flipped the interval between one tick and two.

`ControllerMouseSpeed` was then a distance **per poll tick**, so uneven timing became uneven distance: ticks arriving 15.6, 31.2, 31.2 ms apart moved the cursor the same amount each time. At 32 updates a second the cursor made 20–100 pixel hops, unevenly spaced. A real mouse moves 1–8 px per update.

**Fix, in three parts that had to land together.**

1. **Speed became a velocity**, scaled by measured elapsed time. A late tick moves proportionally further, so on-screen velocity is constant regardless of how the timer behaves.
2. **The default interval moved to 15 ms**, which fires on every boundary — about 64 Hz, halving the step size at identical speed.
3. **The sub-pixel remainder is carried between ticks** rather than rounded away, because the smaller per-tick distances would otherwise be re-quantised.

Parts 1 and 2 are inseparable: poll rate and cursor speed were the same knob, so changing the interval alone would have doubled the speed. That coupling is why the value survived for the life of the project.

**Not a parity failure.** `ApplyControllerMouseMove` was already shared, so all three programs had the identical bug and every cross-tree check passed. A duplication gate proves two copies agree; it says nothing about whether they are right.

**Lesson.** A setting whose unit is "per tick" silently depends on the scheduler being accurate, and Windows timers are not. Anything that should feel continuous has to be expressed as a rate and integrated against a real clock. The setting had also been *documented* as 62.5 Hz for years while delivering 32 — the number was in the INI comment, and nothing measured it.

## Solved: controller input dead after sleep (July 25, 2026)

**Symptom.** On a ROG Xbox Ally X, controller input worked, the machine slept, and after waking nothing responded inside Xbox FSE. Setting `Backend=rawinput` explicitly did not help. Returning to the Windows desktop restored input immediately, with no restart.

**Cause.** The decoder locks onto the first device that produces a correctly shaped report, storing the `RAWINPUTHEADER.hDevice` handle, and that lock had no release. Those handles are **not stable for the life of the process**: Windows re-enumerates HID devices across a suspend and the same controller returns with a *different* handle. Every post-wake report was therefore discarded — silently, because discarding a report from another device is exactly what the lock is for.

**Why the desktop appeared to recover.** It did not; `auto` was falling back to XInput, whose `XInputResolveController` rescans all four slots and re-resolves on its own. RawInput stayed dead the whole time. The asymmetry was the clue: the one backend with no re-acquisition path was the one that failed.

**Fix, in three layers.**

1. **Device hand-over.** If the locked device has been quiet for over a second and a different one is producing correctly shaped reports, the decoder adopts it. Depends on no notification from Windows, so this is the layer that does the work. An actively reporting device is never displaced, preserving the reason the lock exists.
2. **`WM_POWERBROADCAST`.** Releases the lock and re-asserts the registration on resume — the one failure hand-over cannot fix, because a lost registration produces no report to adopt.
3. **Wall-clock gap.** A periodic check arriving far later than scheduled implies the machine slept. Necessary because **modern standby does not reliably deliver the power broadcast**, and modern standby is what a handheld sleeps into, so layer 2 cannot be the only trigger.

Plus a manual re-arm (`Ctrl+Alt+Shift+I` or Settings → Advanced) that releases the lock, re-registers, and forces an XInput rescan. It exists as much for diagnosis as for recovery: if it restores input, the cause is the lock or the registration rather than the backend.

**August 2026 — this was companion-only, and nobody had noticed.** Layers 2 and 3 and the manual re-arm were written here and never called from `SteamShell.ahk`. The shell had layer 1 and nothing else, which covers a stale handle and does nothing for a registration that did not come back. All three now live in `SteamShell-Shared.ahk` and both products use them.

Layer 3 also changed shape. It was a gap between 60-second heartbeats, with a `HeartbeatSeconds * 2 + 30` threshold — so a resume took up to 150 seconds to notice, and the shell, having no heartbeat, could not host it at all. It is now `ControllerResumeGapCheck`, driven from `PollController` in both trees, which reports the poll interval as its cadence and therefore fires in about 30 seconds.

**`A_Now`, not `A_TickCount`, is the load-bearing detail.** The tick counter does not advance through suspend, so a gap check written on ticks sees no gap and silently reports that the machine never slept. Both validators now assert that specifically. The assertion this replaced checked only that a `Heartbeat` body mentioned two names — a rewrite to `A_TickCount` would have kept it green and killed the feature.

**Lesson.** A cache keyed on an OS handle needs an invalidation story, and "the process is still running" is not one. The identity filter here was correct in purpose and wrong in lifetime, and its failure mode was silence — the same shape as several earlier problems on this backend.

## Solved: the Xbox FSE task switcher (July 25, 2026)

With Steam Assist Lite enabled, opening the FSE task/application switcher caused Steam to take focus back and dismiss it. Assist was doing exactly what it was told; the guard it had could not see the switcher.

**Measured identity.** The switcher is an **`explorer.exe` window of class `XamlExplorerHostIslandWindow`**, and it **does own the foreground** while open.

**Two wrong assumptions, corrected in order.**

1. *That the switcher never takes the foreground.* It does. The original
   `IgnoreForegroundProcesses` check missed it because the default omitted
   `explorer.exe`. XFE 0.1.19 protects Explorer when it owns the foreground;
   class-specific matching is still required for overlay detection when an
   Explorer-hosted surface is drawn above some other foreground window.
2. *That scanning the window inventory would find it.* It cannot. XAML island hosts are **tool windows**, and `AssistInventoryBuild` drops tool windows deliberately. With the switcher filling the screen the inventory contained exactly one window: Steam. The first implementation of the overlay check scanned that inventory and was therefore incapable of ever matching, even though the correct class was already in the default list.

**The fix.** Detection inspects the **foreground window directly**, matching process name or `class:`, before falling back to an inventory scan for topmost overlays that do not take the foreground. Class matching is what makes an `explorer.exe`-hosted surface addressable without pausing assistance for the desktop and the taskbar.

**How it was found.** Probe Screen, added in the same version. Its first run reported the foreground as `explorer.exe [XamlExplorerHostIslandWindow]` alongside an inventory of one window — which named the surface *and* exposed the flaw in the detection in a single log. The probe now enumerates every top-level window rather than the inventory, and prints why each window the inventory rejected was rejected, because that reason was the diagnostic.

**Lesson.** A filtered list built for one purpose is usually the wrong input for another. The inventory is intentionally narrow — it answers "what could I activate or close?" — and reusing it to answer "what is on screen?" silently returns a subset with no error anywhere. The validator now requires the overlay check to read the foreground window directly, and the probe to enumerate all windows.

## The `&` output-parameter bug, twice (July 26, 2026)

An AutoHotkey `&` output parameter is left **unset** when the call fails, and that beats any initialisation done beforehand. So this shape is unsafe:

```
finalX := 0
try WinGetPos(&finalX, ...)   ; fails -> finalX is now UNSET, not 0
LogLine(... finalX ...)       ; "this local variable has not been assigned a value"
```

It was found and fixed in **0.1.2** for `actualWidth`, and a validator rule was added — naming that one variable. In **0.1.8** the identical bug crashed the companion as `finalX` in the centering diagnostic, surfacing only when a user enabled diagnostic logging for the first time. Three more instances were then found in the window-inventory loops, where windows can disappear mid-enumeration and the risk is highest.

**The lesson is about the guard, not the bug.** A rule written against a specific *name* only prevents that exact recurrence. It is now written against the *shape*: no bare `try WinGetPos(...)` anywhere. Measure inside a braced `try` and copy the outputs out only on success.

## Corrected: what `auto` actually does, and how standard the layout is (July 26, 2026)

Measured on a separate HTPC with an Xbox controller:

```
Controller input [rawinput]: buttons=0x0340, LT=0, RT=0.
Controller Settings chord detected [rawinput].
```

- **`auto` is not "XInput outside FSE".** It tries RawInput first *everywhere* and uses it whenever HID reports arrive. This document and a previous analysis both claimed otherwise. `Controller input [rawinput]` is the line that settles which backend is active; the `RawInputProbe` lines do **not**, because the probe logs arriving messages regardless of which backend is consuming them.
- **The built-in layout is not Ally-only.** That Xbox controller decoded correctly with it: `LB|RB|L3|R3` resolved to the Settings chord, View and B were right, and both triggers read independently. Xbox-compatible HID pads appear to share the layout, not just the stick offsets.

This is fortunate rather than guaranteed: the built-in layout is still selected on **report length alone**, so any 16-byte HID gamepad gets decoded with it whether or not that is correct.

## What hardware testing changed (0.1.9, July 26 2026)

0.1.8's learned-profile system passed a written simulation and then failed repeatedly on real controllers. Every fix below came from a measurement, and several corrected an earlier analysis that had been asserted with more confidence than the evidence supported.

### The learner was guessing in a space too large to guess in

Each of the six axis steps independently chose an offset, a width and an endianness. Three runs on the same controller produced three different answers, once including LX=1, LY=2, RX=4, RY=3 — overlapping fields that cannot describe any real report. A profile saved with `RX:5:u16be:21884` pinned the right stick at roughly -10700 with the controller untouched, and the pointer ran across the screen.

Two **physical constraints** replaced the heuristics:

- **USB HID specifies little-endian for multi-byte fields.** Big-endian is not a layout that exists on these devices, and offering it doubled the search space. The learner no longer guesses it; the decoder still understands it for hand-written profiles.
- **A self-centring stick rests at the centre of its range.** Measured: all four sticks and the shared trigger sat between 47.6% and 50.4% of full scale at rest, while the big-endian readings scattered to 85%, 4.5% and 0.2%. A candidate resting outside 35–65% is the wrong field.

Plus: a stick may not reuse bytes another stick has claimed. Triggers stay exempt, because a shared trigger axis is a real layout.

#### …and that last constraint then broke every stick

Reported from hardware on the next run: **no stick would map at all**, each one failing with "not enough travel" however far it was pushed, while the triggers went on working.

The stick-claiming rule was correct about the constraint and wrong about the mechanism. The resolver does not run once at the end of a gesture; it runs **on every report**, and each run writes its provisional answer into the results map so the release test can watch a decoded field rather than raw bytes. The claim loop excluded every stick already in that map — including the step's own entry, written one report earlier. From the second report onward, each stick's field was unavailable to itself.

The triggers still worked because they are exempt from stick claiming, which is exactly the shape of the report: everything fine except the sticks.

Three things came out of it:

- The claim loop skips the current step's own name.
- **A rejected axis now deletes its provisional entry.** The one saved with a partial sweep's `neutral` and `extent` is precisely the kind of entry that sends the pointer across the screen — and the user did see the pointer veer right after a run where nothing appeared to map. Skipping a step mid-gesture discards it too.
- The wizard said "Not enough travel" for *every* failure, including ones with nothing to do with travel. Each rejection now records its actual reason and logs it.

The lesson is narrower than "test on hardware": **a constraint added to shrink a search space has to account for when the search runs.** This one was written as if resolution happened once.

### The wizard fought the user

- **Pressing B closed it.** The wizard diverted only the RawInput path, so the poll loop kept reading the same pad through XInput and firing its normal mappings — B is Escape. A, X, Y and Start all had side effects too. The controller is now inert while the wizard is open, which in turn required digital steps to time out on their own, since Skip is unreachable without a pointer.
- **A nudged stick was learned as a button.** At rest an axis low byte is `0x00`, so moving the stick sets bits that were clear at rest — precisely the test a button has to pass. It bit hardest on L3/R3, which cannot be pressed without touching the stick. An opening analogue scan now identifies which bytes carry analogue values and excludes them from every button step.
- **Prompts said "press and hold" while detection happened on press**, then advanced on a blind timer. A still-held button satisfied the next step's test. Advancing is now gated on seeing the release.
- **A diagonal D-pad press corrupted the whole D-pad**, because the four directions are only meaningful as a set. They are now validated together and retried once.

### Guards written against a name, not a shape

An AutoHotkey `&` output parameter is left **unset** when the call fails, which beats any prior initialisation. Fixed in 0.1.2 for `actualWidth` with a validator rule naming that variable — and the identical bug returned in 0.1.8 as `finalX`, crashing the companion the first time a user enabled diagnostic logging. Three more instances were then found in the window-inventory loops.

The rule is now written against the shape: no bare `try WinGetPos(...)` anywhere. **A guard written against a specific name only prevents that exact recurrence.**

### Rendering: measuring things that were not ready

- **The Quick Menu was clipped with a clean rounded edge through a row.** `WinSetRegion` clips, and it was being applied while the window was still hidden — deliberately, to avoid one frame of square corners. A hidden window can report the wrong size. Shaping a hidden window is now banned outright, and the menu is revealed before it is measured or shaped.
- **The cursor kept reappearing.** AutoHotkey v2 defaults `CoordMode "Mouse"` to `Client`, so when the menu moved, the origin moved with it and an unmoved pointer read as having moved. Every `MouseGetPos` here wants screen coordinates.
- **Settings opened behind Xbox FSE.** It had the foreground the whole time; FSE is a fullscreen window, so a normal window can be focused and still render behind it. The Quick Menu never had the problem because it was always-on-top. No amount of retrying `SetForegroundWindow` fixes z-order.
- **Dialogs then opened behind Settings.** A direct consequence of the always-on-top fix above, reported on the next pass. A non-topmost dialog cannot rise above a topmost window *even when that window is its own owner*, so a `MsgBox` or file picker held the focus and the keyboard while being invisible — which reads as the application having frozen. The fix makes the dialogs topmost as well (`MB_SYSTEMMODAL` for message boxes; a promotion timer for `FileSelect`, which has no equivalent option). The obvious alternative — dropping the owner's topmost bit for the duration — is wrong here: inside FSE it hides the owner behind FSE and takes the dialog with it. The validator now forbids bare `MsgBox` and `FileSelect` calls, because this is a class of bug rather than two sites.
- **The audio row showed `%` instead of `100%`.** The value column is right-aligned, so overlong text is clipped from the *left*, and the volume was at the front of the string. This was first misdiagnosed as a volume-reading failure and "fixed" in the wrong place. In a right-aligned column, **put the value that matters last.**

### Two corrections to this document's own claims

- **`auto` is not "XInput outside FSE".** It tries RawInput first everywhere and uses it whenever HID reports arrive. `Controller input [rawinput]` is the line that settles which backend is active; the probe lines do not, since the probe logs arriving messages regardless of consumer.
- **The built-in layout is not Ally-only.** A separate Xbox controller on a different machine decoded correctly with it — buttons, hat and both triggers. Fortunate rather than guaranteed: selection is still by report length alone.

### The validator had gone stale in the same release

Four assertions in `Validate-SteamShell-XFE.ps1` no longer matched the code they were written to protect, because 0.1.9's fixes changed it and the validator was never re-run — PowerShell is not available on the development machine, so it only runs on Windows at build time.

One of them was actively wrong: it demanded that the Quick Menu's corners be rounded **before** it is revealed, which is the exact ordering that clipped the menu on a 4K display. Had the build been run, that assertion would have failed the fix that repaired the bug.

All four are corrected, and the rounded-corner rule now states the invariant the fix established — reveal first, then measure and shape — plus a second rule on the helper itself, so it holds for every caller rather than only the Quick Menu. **A validator that is not run is not a validator**; the regex checks are now also replayed in Python on this machine, which catches this class of drift without Windows.

### Method

The recurring failure was reasoning from an assumption instead of a measurement, and three fixes had to be redone because of it. What consistently worked: capture the raw reports, replay them through the logic, and only then change code. The 0.1.9 fixes for endianness and centre-of-range were each verified by replaying the user's own captured report and confirming the rules reject exactly the broken axes and keep the sound ones.

## XFE release history

| Version | Purpose |
|---|---|
| 0.1.0 | Initial companion proof of concept |
| 0.1.1 | Persistent Quick Menu, improved centering, restored sidebar Settings layout |
| 0.1.2 | Corrected the `actualWidth`/ByRef centering error |
| 0.1.3 | Added XInput slot discovery and detailed controller diagnostics |
| 0.1.4 | Added the selectable GameInput background-input backend with XInput fallback (negative result) |
| 0.1.5 | RawInput backend — controller input works inside Xbox FSE. Context-aware Steam actions, View button actions, DPI-correct window centring |
| 0.1.6 | Task switcher, assist features, startup programs, logon task, diagnostic ZIP, Quick Menu redesign and keyboard support. Elevation tested and rejected |
| 0.1.7 | Quick Menu Settings page of live toggles; separate View tap/hold switches; new Steam settings category; shell-overlay suspension for the Xbox FSE task switcher, matched by window class; Probe Screen diagnostic; logon task rebuilt from XML so it starts on battery; Check Logon Task diagnostic; windows placed and shaped before they are shown; RawInput device-lock hand-over so controller input survives sleep; manual controller re-arm; fixed Settings category cycling stuck at 4 of 6 |
| 0.1.8 | Learned RawInput controller profiles; idle-filtered controller selection; single-report digital learning for change-only devices; active-high/active-low buttons; masked hat or bit D-pads; 8-bit and 16-bit LE/BE axes; measured travel; shared or independent triggers; bounds-checked profile loading; deterministic controller-profile simulation |
| 0.1.9 | Hardening of 0.1.8 against hardware testing: little-endian-only axis learning; stick centre-of-range check; sticks may not share bytes *except their own field*; rejected axes delete their provisional entry and record the real reason; opening analogue scan so a nudged stick is not learned as a button; press-and-release gating; controller inert while the wizard is open; digital step timeouts; D-pad set validation with retry; post-save rest check and profile deletion; report-length profile fallback when Windows will not identify a device; identity-lookup backoff off the input hot path. Plus: CoordMode fixed to Screen; Quick Menu revealed before it is measured and shaped; Settings always-on-top; Settings window enlarged with an automated layout check; audio summary reordered; four unsafe ByRef WinGetPos sites fixed; every MsgBox and FileSelect routed through a topmost wrapper so dialogs are not hidden by their own always-on-top owner; four stale validator assertions corrected. New: startup-program launch window mode (Normal/Minimized/Hidden, ported from 1.5) and a configurable cursor park edge, defaulting to centre-right |
| 0.1.10 | Added primary-display Windows Scale to Display & HDR. Resolution, refresh rate, and scale are staged independently, applied together, and restored together by the 15-second safety revert or the exit handler. Scale degrades to an unavailable row when Windows rejects the DisplayConfig DPI packet. The open Quick Menu reflows and re-centres after both apply and revert once the new DPI has settled. Replaced the blind HDR shortcut with live primary-display Advanced Color state plus explicit Off/On control. |
| 0.1.11 | Added live RTSS global Overlay and Frame Limiter state through the `GetFlags`/`SetFlags` exports in `RTSSHooks64.dll`, plus the applicable application/global profile's real `FramerateLimit` value. The Quick Menu shows On/Off and the cap, A toggles, and Left/Right explicitly disable/enable. When RTSS is installed but stopped, the page offers a couch-friendly Start RTSS action and refreshes into live controls after launch. Settings explains the path-derived DLL integration and provides a default-on switch to disable it and force the existing shortcut/cap-label mode. |
| 0.1.12 | Added an original multi-resolution SteamShell XFE icon and notification-area menu for opening the Quick Menu or Settings, temporarily disabling/enabling companion behavior, and exiting. Disable pauses operational timers, RawInput processing, pending startup launches, and global hotkeys while leaving Settings and the tray recovery path available. |
| 0.1.13 | Ported the optional SteamShell 1.5 startup presentation into XFE as a primary-display black curtain or MPV video, with black handoffs, mute/full-duration/SDR controls, fade-out, safety timeout, Settings integration, and cleanup on Disable or Exit. It remains presentation-only and does not gate Steam or manage Xbox FSE. |
| 0.1.14 | Locked release. Steam returns to the Task Switcher even when its Big Picture window is published as a tool window; in-game Steam Overlay injection uses a timed Shift+Tab chord; Quick Menu Settings toggles write before applying and remain synchronized with full Settings; System diagnostics were removed from the couch menu while remaining in Advanced; Settings uses its visible DPI-scaled frame for vertical centring; fullscreen/game-entry cursor parking is enabled by default; the Windows build has a double-clickable CMD launcher and reliable GUI-process exit-code handling. |

| 0.1.15 | Combined **Frame Limit** Quick Menu row — Off · 30 · 40 · 60 · 90 · 120 · Custom — folding RTSS's global limiter flag and the profile's `FramerateLimit` into one control, with a conditional Custom FPS row whose step escalates 1 → 5 → 10 because Quick Menu navigation never auto-repeats. "Off" maps to the flag and never writes `0`, so a cap survives an off/on round trip. Writes go to the global profile only, except the explicit two-press **Save Limit to Profile** row, which copies the current cap into the foreground executable's own profile. Adds the `SetProfileProperty`/`SaveProfile`/`UpdateProfiles` exports, all optional — a build without them shows the cap read-only. Plus: motion-sensor exclusion in the learner's axis search; a bounds guard on the wizard's Skip button; removal of the handler cases and functions left dead by the row merge; and matching validator assertions. |
| 0.1.16 | RTSS frame-cap input: the write is debounced and committed once after input stops rather than on every press, and the Custom FPS row uses hold-to-repeat with an accelerating rate instead of an escalating step, so a press is always exactly one change. Save Limit to Profile falls back to the last game-like foreground when the captured one is Steam. |
| 0.1.17 | Shared Quick Menu rendering release: opaque high-DPI GDI+ rows, configurable accent and derived fill, neutral charcoal palette, glow and border suppression, atomic open-session repaint, destroy-on-close compositor lifecycle, recovery-title sizing, and complete driver-reported resolution/refresh enumeration beyond the former 512-mode ceiling. Settings schema 4 adds the accent options. |
| 0.1.18 | Cross-tree audit hardening: bounded log rotation and diagnostic-only controller-edge logging, restored left-stick Quick Menu navigation, centralized RTSS discovery, shared clamp helpers, validator negative tests, and transactional root validation publishing. Settings schema 5. |
| 0.1.19 | Retired XFE's late presentation-only startup curtain/video because AnyFSE starts Steam first; schema 6 backs up and removes the obsolete section. Assist now retains Steam Big Picture tool windows, protects Explorer foreground surfaces, uses effective CPU game detection for minimized/non-fullscreen games, and restricts delayed hard-kill to revalidated original process identities. |
| 0.1.20 | Quick Settings refresh: Open Keyboard and persistent Mouse Mode on the main page, hold Y for the styled Controller Mappings submenu with a final editor action, Windows Settings in the Settings submenu, retired main-page Controller Layout row, and consistent title casing. Settings schema 7. |
| 0.1.21 | Automatic controller mouse input on every companion settings/editor surface, plus distinct RTSS Preset and retained Custom frame-cap values. Settings schema 8. |

The older ZIP files in the XFE directory are retained source checkpoints from
the diagnostic phase.

**0.1.9 is locked as a checkpoint** at `releases/XFE-0.1.9/`, alongside `SteamShell-XFE-0.1.9-test-source.zip` in the XFE directory. It was locked on 2026-07-26 at the point where the controller-learning wizard was first confirmed working on hardware, on both the Ally and the HTPC — the first learned-profile build confirmed on more than one machine.

The unpacked directory is the one to use for comparison or restoration; the ZIP exists to match the naming of the earlier snapshots. `releases/XFE-0.1.9/RELEASE.md` records SHA-256 for every file, what is verified on hardware versus by automated check only, what has never run at all, and the known limits as they stood at lock time. No compiled EXE is stored — the one in the working directory predated these sources.

**0.1.14 is locked as the first XFE release** at `releases/XFE-0.1.14/`.
Its `RELEASE.md` records scope, verification status, known limits, and SHA-256
checksums. The release directory should not be edited; later development belongs
in `SteamShell/` and must use a later version.

**0.1.15 is locked** at `releases/XFE-0.1.15/` — the Frame Limit row, the
motion-sensor fix, and the Skip bounds guard.

**0.1.17 is locked** at `releases/XFE-0.1.17/` — the shared Quick Menu renderer,
closed-window lifecycle fix, recovery layout, accent schema, and complete
display-mode enumeration. `releases/XFE-0.1.16/` remains unchanged.

**1.9.9 is the current locked XFE release** at `releases/1.9.9/SteamShell-XFE/`.
It consolidates the 0.1.21 line—the
cross-tree audit hardening, retired late startup presentation, Assist fixes,
Quick Settings refresh, automatic settings mouse, and independent RTSS Preset
and retained Custom values.

The matching shareable archive is
`releases/SteamShell-XFE-0.1.14-source.zip` (SHA-256
`bc24eb2e697edbc3747940035db222cf970f2fb3881a8117a9c8f840f82d8abb`).

---

# Which application should be used?

Use **SteamShell 1.7** when:

- Steam Big Picture should be the main console interface.
- SteamShell should own boot, focus, taskbar, Explorer, and desktop restoration.
- The custom task switcher and Window Engine are desired.
- The established, tested behavior is more important than Xbox FSE integration.

Use **SteamShell-XFE** when:

- Xbox Full Screen Experience should own the session.
- AnyFSE will select Steam or another application as Home.
- Only the controller utilities and system controls are wanted.
- Experimental input and presentation work is acceptable.

Do not run both as competing shell managers. It is reasonable to keep both executables on the computer, but only one architecture should own the active console session.

---

# Project file layout

```text
workspace-root/
├── STEAMSHELL_PROJECT_OVERVIEW.md
├── Run-SteamShellValidation.cmd
├── Run-SteamShellValidation.ps1
├── SteamShell/                       <- everything the build and validators need
│   ├── SteamShell.ahk                   the Windows shell replacement
│   ├── SteamShell-XFE.ahk               the Xbox FSE companion
│   ├── SteamShell-Helper.ahk            the elevated helper, one payload, two products
│   ├── SteamShell-Common.ahk            self-contained; #Included by ALL THREE
│   ├── COMMON_FUNCTIONS.txt             the manifest for the common half
│   ├── SteamShell-Shared.ahk            tree-coupled; #Included by both trees
│   ├── SHARED_FUNCTIONS.txt             the manifest of what is shared, and why
│   ├── Build-SteamShell.cmd
│   ├── Build-SteamShell.ps1             builds all three binaries in order
│   ├── Validate-Common.ps1              scaffolding only; no product rules
│   ├── Validate-SteamShell.ps1
│   ├── Validate-SteamShell-XFE.ps1
│   ├── Test-ControllerProfiles.py       learned-controller and Settings-layout simulation
│   ├── SteamShellSettings_SAMPLE.ini
│   ├── SteamShell-XFE_SAMPLE.ini
│   ├── SteamShell.reg
│   ├── README.md                        standalone
│   ├── README-XFE.md                    companion
│   ├── CHANGELOG.md
│   ├── XFE_PARITY_NOTES.md
│   ├── INI_READER_MIGRATION.md
│   ├── WINDOWS_TEST_CHECKLIST.md
│   ├── WINDOWS_TEST_CHECKLIST-XFE.md
│   ├── assets/
│   │   ├── SteamShell.ico
│   │   ├── SteamShell-icon.png
│   │   ├── SteamShell-XFE.ico
│   │   └── SteamShell-XFE-icon.png
│   ├── extras/
│   │   ├── bigpicture_startup.webm
│   │   └── black.png
│   └── images/
│       └── control-panel.png
├── archive/
│   └── xfe-test-sources/             historical XFE 0.1.x source zips
├── current/                          the published, verified SteamShell.exe
└── releases/
    ├── 1.4.0/ … 1.7.7/               frozen standalone snapshots
    ├── 1.9.9/                        coordinated standalone/XFE bundle and checksums
    └── XFE-0.1.9/ … XFE-0.1.21/      frozen companion snapshots
```

**One folder is the unit of a release.** `SteamShell/` reaches outside itself for
nothing: both AutoHotkey trees, the shared file and its manifest, both
validators, the shared scaffolding, and the one build script are all in it. Copy
the directory and it builds. That is why `SteamShell-Shared.ahk`,
`SHARED_FUNCTIONS.txt` and the parity check are no longer at the workspace root,
and why `#Include SteamShell-Shared.ahk` no longer climbs a level.

Frozen snapshots under `releases/` predate this and keep the two-folder layout
they were locked with. They are self-contained on their own terms and are not
rewritten.


## SteamShell files

| File | Purpose |
|---|---|
| `SteamShell/SteamShell.ahk` | Active and locked SteamShell 1.9.9 source. |
| `SteamShell/SteamShell-Helper.ahk` | Narrow elevated-window controller helper, compiled and embedded by the main build. |
| `SteamShell/assets/` | Standalone notification-area and compiled executable icon assets. |
| `SteamShell/SteamShellSettings_SAMPLE.ini` | Documented configuration template. Runtime settings are written to `SteamShellSettings.ini`. |
| `SteamShell/SteamShell.reg` | Optional registry setup/reference for configuring SteamShell as the per-user shell. |
| `SteamShell/Build-SteamShell.cmd` | Double-clickable Windows build launcher with visible result and preserved exit code. |
| `SteamShell/Build-SteamShell.ps1` | The only build script. Runs both validators, then compiles the helper, the XFE companion and `SteamShell.exe` with both embedded, version-verifying each. |
| `SteamShell/Validate-SteamShell.ps1` | Static and runtime-oriented validation checks used before compiling or releasing. |
| `SteamShell/README.md` | Main setup, operation, configuration, and troubleshooting documentation. |
| `SteamShell/CHANGELOG.md` | Version history and notable behavioral changes. |
| `SteamShell/XFE_PARITY_NOTES.md` | Ported, already-covered, and deliberately excluded XFE parity decisions. |
| `SteamShell/WINDOWS_TEST_CHECKLIST.md` | Manual Windows acceptance and regression checklist. |
| `SteamShell/INI_READER_MIGRATION.md` | Scoped, not-yet-started plan to adopt XFE's typed INI readers. A proposal, not a record of work done. |
| `SteamShell/extras/` | Optional splash/video and background assets. |
| `SteamShell/images/` | Documentation screenshots and images. |

## Root files

| File | Purpose |
|---|---|
| `Run-SteamShellValidation.cmd` | Double-clickable launcher for the combined validation and build run. |
| `Run-SteamShellValidation.ps1` | Validates and builds the project in one pass: AutoHotkey syntax, both static validators, the shared-parity check, version-verified compilation of all three binaries, the negative gate tests, and the transactional publish. |

## Release directories

The `releases` directory contains frozen source snapshots:

- `releases/1.4.0` preserves the previous stable architecture.
- `releases/1.5.0` is the source of truth for the locked SteamShell 1.5 release.
- `releases/1.6.0` preserves the release between 1.5 and 1.7.
- `releases/1.7.0` is the source of truth for the locked SteamShell 1.7 release.
- `releases/1.7.1`, `releases/1.7.2` are the intermediate locked 1.7 patch releases.
- `releases/1.7.3` is the deliberate revert point immediately before the Quick Menu rendering rewrite.
- `releases/1.7.4` preserves the earlier Quick Menu rendering checkpoint.
- `releases/1.7.7` is the prior locked SteamShell patch release.
- `releases/1.9.9` is the current coordinated, self-contained SteamShell and XFE release bundle.
- `releases/XFE-0.1.9` is the SteamShell-XFE companion at the point the controller-learning wizard was confirmed working on hardware. A test-candidate checkpoint, not a finished release; its `RELEASE.md` is explicit about which parts have never run.
- `releases/XFE-0.1.14` is the first locked SteamShell-XFE release, preserving
  the complete source, build launchers, icon assets, configuration sample,
  documentation, validation, simulation, and checksums.
- `releases/XFE-0.1.15`, `releases/XFE-0.1.16` are the intermediate locked
  SteamShell-XFE patch releases.
- `releases/XFE-0.1.17` preserves the earlier Quick Menu rendering checkpoint.
- `releases/XFE-0.1.21` is the prior locked SteamShell-XFE patch release.

Each release directory is self-contained enough to inspect, validate, and rebuild that version. Release snapshots should only change to correct packaging mistakes; feature development should create a later version instead.
`releases/1.7.0/RELEASE.md` records the 1.7 scope, verification boundary, and
SHA-256 manifest.

## SteamShell-XFE and cross-tree files

These live in `SteamShell/` alongside the standalone sources — the single-folder
reorganisation put both products and everything the build needs in one place.

| File | Purpose |
|---|---|
| `SteamShell/SteamShell-XFE.ahk` | Active and locked XFE 1.9.9 source. |
| `SteamShell/assets/SteamShell-XFE.ico` | Multi-resolution Windows executable and notification-area icon. |
| `SteamShell/assets/SteamShell-XFE-icon.png` | Transparent high-resolution preview/source for the XFE icon. |
| `SteamShell/SteamShell-XFE_SAMPLE.ini` | Documented XFE configuration template. Runtime settings are written to `SteamShell-XFE.ini`. |
| `SteamShell/Validate-SteamShell-XFE.ps1` | Validation checks specific to the stripped-down companion architecture. Deliberately a separate script from `Validate-SteamShell.ps1`: several of its architecture rules are the exact inverse of the shell's, and a merged script would need every one of them to name its own scope, where a mis-scoped rule stops applying instead of failing. |
| `SteamShell/Test-ControllerProfiles.py` | Deterministic simulation for learned widths, endianness, directions, ranges, button polarity, and trigger layouts. |
| `SteamShell/README-XFE.md` | XFE setup, boundaries, hotkeys, and AnyFSE guidance. |
| `SteamShell/WINDOWS_TEST_CHECKLIST-XFE.md` | Desktop and Xbox FSE test procedure. |
| `SteamShell/SteamShell-Common.ahk` | The self-contained half of the shared code, `#Include`d by **all three** programs including the elevated helper. May not declare a global or reference anything outside itself — that invariant is what lets it compile into a High-integrity binary, and it is enforced rather than trusted. |
| `SteamShell/COMMON_FUNCTIONS.txt` | The manifest for the common half. A decision record, like `SHARED_FUNCTIONS.txt`. |
| `SteamShell/SteamShell-Shared.ahk` | The **tree-coupled** half: RTSS orchestration, Quick Menu painting, elevated-helper lifecycle. `#Include`d by both trees only, because it reaches into per-tree functions and would not compile in the helper. Functions only — no top-level code, because it is inserted into two different auto-execute sections. Calls back into **29 per-tree functions** — the seam — of which the `Product*` group (`ProductIdentity`, `ProductHealthResults`, `ProductTrayItems`, `ProductBestGameExe`, `ProductVersionText`, `ProductCenterGui`, `ProductTrayBaseTip`) exists purely so shared logic can ask a question each product answers differently. `LogLine` and `SharedPersistSettings` are the two oldest. Every name is verified present in **both** trees by `Assert-SharedParity`, so a shared body cannot quietly depend on something only one product defines. |
| `SteamShell/SHARED_FUNCTIONS.txt` | The manifest of what lives in the shared file. A decision record: removing a name, and moving the function back into both trees, records a divergence as deliberate. |
| `SteamShell/Validate-Common.ps1` | Scaffolding shared by both validators — `Assert-True`, include resolution, the structural scans, and the shared-parity check. Mechanism only; no product rules. |
| `archive/xfe-test-sources/*.zip` | Historical source packages for individual XFE test candidates, kept out of the release folder. |

## Generated files at runtime

These files are normally created beside the applicable executable and are not primary source files:

| Application | Settings | Controller profiles | Log |
|---|---|---|---|
| SteamShell 1.7 | `SteamShellSettings.ini` | `SteamShellSettings-Controllers.ini` | `SteamShell.log` |
| SteamShell-XFE | `SteamShell-XFE.ini` | `SteamShell-XFE-Controllers.ini` | `SteamShell-XFE.log` |

Backup, migration, diagnostic ZIP, and temporary transaction files may also be created during settings maintenance or troubleshooting.

## Build output

On a Windows development system, the one build script produces:

- `SteamShell\build\SteamShell-Helper.exe` — embedded payload
- `SteamShell\build\SteamShell-XFE.exe` — embedded payload
- `SteamShell\dist\SteamShell.exe` — the installer, carrying both
- `SteamShell\dist\SteamShell-XFE.exe` — development copy only

Only `SteamShell.exe` is published. It is the installer and the uninstaller for
both products, so a second `SteamShell-XFE.exe` beside it is not a distributable
— it is an invitation to a hand-copied install with no logon task, no writable
companion directory, and no dormant elevated helper. The companion is installed
by choosing XFE in Setup Assistant.

The root `Run-SteamShellValidation.cmd` validates and builds everything in one
pass, breaks each of the three sources in turn to prove the gate rejects them,
locks each freshness-checked output to prove a stale artefact is refused, and
only on a completely passing run publishes the verified installer to root
`current\`. A failed run leaves the prior `current\` directory unchanged and
returns a non-zero exit code.

Compiled executables are build artifacts. The authoritative project history is the source, sample configuration, validation script, documentation, and frozen release snapshot.

---

# Recommended project direction

## SteamShell 1.7

Treat 1.9.9 as the current locked checkpoint. Keep 1.7.3 as the
pre-rendering-rewrite revert point. Its predecessors
1.7.3, 1.7.2, 1.7.1 and 1.7.0 remain frozen:

- Work through the Desktop mode and Desktop blackout sections of
  `WINDOWS_TEST_CHECKLIST.md` before treating either as settled.
- The blackout hides `Progman`/`WorkerW`. That is reasoned by analogy to the
  taskbar hiding SteamShell already performs, not verified; Game Bar and other
  UWP surfaces are the most likely to object. It can be switched off from
  Quick Menu ▸ Settings ▸ General + Startup with immediate effect.
- Run extended play testing rather than broad feature development.
- Record reproducible regressions before changing shell, taskbar, focus, cursor, or sleep behavior.
- Apply fixes or features only in a later version.
- Keep the frozen `releases/1.7.0` and `releases/1.6.0` snapshots unchanged.

## SteamShell-XFE

The two questions that gated the whole project are now answered:

1. ~~Prove background controller input inside Xbox FSE.~~ **Solved in 0.1.5 via RawInput.** XInput and GameInput are both gated; RawInput reads underneath and receives everything.
2. ~~Prove the Quick Menu presentation model inside Xbox FSE.~~ **Confirmed working.** FSE displays the Quick Menu, and keyboard hotkeys reach the background companion.

Treat 1.9.9 as the current completed checkpoint. Its predecessors 0.1.14,
0.1.15, 0.1.16, and 0.1.17 remain frozen:

3. Prefer extended play and sleep/resume testing over broad feature work.
4. Record reproducible regressions before changing RawInput, display safety,
   focus, cursor, or fullscreen detection.
5. Continue testing the learned-profile wizard against additional controller
   families and document report layouts the byte-aligned learner cannot
   represent.
6. Keep `releases/XFE-0.1.14` frozen; fixes belong in a later version.

The XFE project should not inherit SteamShell's shell and window-management systems merely to work around Xbox FSE. Its value comes from remaining a small companion with a clear division of responsibility.

---

# External references

- [Windows gaming full screen experience](https://support.microsoft.com/en-us/topic/windows-gaming-full-screen-experience-67fb8d12-5467-4a95-8adf-0a10789576ab)
- [AnyFSE project](https://github.com/ashpynov/AnyFSE)
- [GameInput fundamentals](https://learn.microsoft.com/en-us/gaming/gdk/docs/features/common/input/overviews/input-fundamentals)
- [GameInput focus policy](https://learn.microsoft.com/en-us/gaming/gdk/docs/reference/input/gameinput-v2/enums/gameinputfocuspolicy-v2)
- [`IGameInput::SetFocusPolicy`](https://learn.microsoft.com/en-us/gaming/gdk/docs/reference/input/gameinput/interfaces/igameinput/methods/igameinput_setfocuspolicy)
- [Windows.Gaming.Input](https://learn.microsoft.com/en-us/uwp/api/windows.gaming.input)
