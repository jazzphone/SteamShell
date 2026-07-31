# SteamShell (Steam BPM Focus + Window Helper)

** I won't be providing any support for this and you are using this at your own risk. **

Vibe coded with ChatGPT

## Screenshots

### Control Panel (live in Steam Big Picture)
![SteamShell Control Panel](images/control-panel.png)

## What it is

- An AutoHotkey v2 “console/kiosk helper” that launches Steam Big Picture Mode (BPM),
  keeps the right window in front (Steam vs games vs whitelisted apps), optionally
  recenters/maximizes windows, and provides a Control Panel plus controller-to-mouse/keyboard mode.

  **The `.exe` file on the releases page is compiled with Ahk2Exe. SteamShell requires AutoHotkey v2.0.19 or
  newer with a 64-bit base.**

  The included `.reg` file remains a manual fallback and assumes `C:\Utilities\SteamShell.exe`. The preferred
  setup method is the single-EXE Install SteamShell action described below.

The validated pre-rewrite 1.4 source baseline is preserved in
`../releases/1.4.0`, the coordinated window-engine baseline is preserved in
`../releases/1.5.0`, and the XFE-parity baseline is preserved in
`../releases/1.6.0`. The 1.7.0 source is preserved in `../releases/1.7.0`.

The 1.7.1 source is preserved in `../releases/1.7.1`. This tree is the locked
SteamShell **1.7.2** source, preserved in `../releases/1.7.2`. The feature-by-feature XFE port decisions are recorded in
`XFE_PARITY_NOTES.md`.

## Settings upgrades

SteamShell synchronizes `SteamShellSettings.ini` with its built-in settings schema during startup. Missing options
are added with their defaults, but existing values—including intentionally blank values—are not overwritten.
Explicitly retired options are removed after any legacy value is transferred to its replacement. Before changing
an older file, SteamShell creates a versioned backup beside it, such as
`SteamShellSettings.ini.pre-schema-0.bak`. Automatically added options may appear at the end of their section
without the descriptive comments included in a newly generated file. Legacy ANSI/UTF-8 INI files are backed up
and converted to UTF-16 for reliable Unicode-path support. Schema migrations and Settings-editor saves are staged
in a temporary copy and replace the live INI only after every change succeeds.

## Hotkeys

- Ctrl+Alt+Shift+E : Emergency **permanent** restore — registers Explorer as the shell and closes SteamShell
- Ctrl+Alt+Shift+R : Reload SteamShellSettings.ini
- Ctrl+Alt+Shift+G : Run Game Foreground Assist (one-shot)
- Ctrl+Alt+Shift+P : Open Control Panel
- Ctrl+Alt+Shift+Q : Open the controller-first Quick Menu
- Ctrl+Alt+Shift+S : Open the persistent Settings editor

## Controller shortcuts

- Hold L3 + R3 for about 0.7 seconds : Open or close Quick Menu
- Hold View/Back and tap Start : Open the Windows Start menu
- Hold View/Back and hold Start : Open File Explorer
- The mapped Task Manager action uses Windows' native Ctrl+Shift+Esc shortcut. If Windows elevates Task Manager,
  a non-elevated SteamShell cannot control its window or inject mapped mouse input into it.
- LT + RT + LB + RB + L3 + R3, **held** : Emergency/fallback Full Settings chord. The hold matches the Quick Menu's
  L3 + R3 chord so a stray grip during play cannot throw Full Settings over a running game. It is declined while the
  Quick Menu, Full Settings, the controller test, or the Steam recovery screen already has controller input — each of
  those offers its own route to Settings.

Every View/Back mapping, including these Start actions, can be reassigned in the Controller Mapping window. Quick
Menu and Control Panel remain available as optional built-in actions but are unassigned by default.

### Automatic mouse mode

`[Controller] AutoMouseExeList` names executables where those same mappings apply **without holding View/Back**.
Settings ▸ Controller & Cursor ▸ **Automatic mouse mode for these EXEs** edits the list; it is **empty by default**,
so naming an executable is the entire opt-in.

It is deliberately not a second input mode. The View/Back mappings are already a complete desktop mouse out of the
box — right stick moves, left stick scrolls, D-pad arrows, RB left-clicks, RT right-clicks, X opens the touch
keyboard, Start opens the Start menu — so automatic mode reuses them rather than inventing a parallel keymap that
could drift from the one you configured. What happens automatically is exactly what holding View/Back does, and
holding View/Back while it is active changes nothing.

Reasonable entries are `explorer.exe` and a browser such as `brave.exe`. Note that `explorer.exe` is also the
desktop and the taskbar, not just File Explorer, so listing it engages automatic mode for those too.

**Do not list a game.** If you do, the controller becomes a mouse inside it — but the escape chords still work,
because they are evaluated before automatic mode and read the real button state. L3 + R3 opens the Quick Menu and
the held six-button chord opens Full Settings, so the list can always be corrected without reaching for a keyboard.

The cursor is unhidden when automatic mode engages; moving a pointer that cannot be seen is not a usable mode.

## Administrator startup

By default, SteamShell restores the behavior used by versions 1.2 and 1.3: if it starts without administrator
rights, it relaunches itself with Windows' `Run as administrator` verb before starting Steam or changing the shell
UI. This allows controller mouse input and window management to interact with elevated Windows surfaces such as
Task Manager. Command-line modes such as `/install`, `/restore`, and `/safe` are preserved during the handoff.

The **Run SteamShell as administrator on startup** checkbox under **Startup & Splash** can disable this relaunch;
the change takes effect on the next launch. When it is off, Windows integrity isolation can prevent SteamShell's
controller mouse and injected input from working in elevated applications. The option defaults to On.

If Windows denies or cancels elevation, SteamShell continues non-elevated instead of leaving the system without a
shell. Health Check reports the active privilege state. With UAC prompting enabled, Windows can display an elevation
prompt at SteamShell startup; programs launched directly by SteamShell can inherit its elevated token.

## Major features

- Steam exit / desktop restore: When Steam closes, SteamShell restores the normal desktop state:
  - Unhides the taskbar
  - Temporarily sets Explorer as the shell (Winlogon Shell)
  - Starts/restarts Explorer so you get a usable desktop
  - Then reverts the shell setting back to SteamShell.exe for next boot
  - Arms automatic restoration only after **Steam Big Picture has actually been seen on screen**, then confirms a
    sustained exit. A running `steam.exe` is deliberately not enough: on a Wi-Fi handheld the process appears at
    once and then sits on a "Connecting", sign-in, or client-update window for as long as the network takes, and
    treating that as success made the recovery screen unreachable behind the startup curtain
  - Verifies the shell registry value and retries Explorer until a real taskbar appears
  - Keeps SteamShell running with a retry prompt if desktop restoration cannot be verified

- Coordinated window engine: Builds one validated window inventory and gives exactly one focus arbiter authority
  over pinned tasks, AlwaysFocus applications, detected games, and the Steam fallback. Geometry changes defer
  focus decisions until the next cycle so centering and activation do not fight each other.
- Steam BPM boot + refocus: Keeps BPM usable as a “shell” after boot, restores the proven partial-title matching
  behavior, and ignores minimized, off-screen, non-activating, and auxiliary Steam windows when deciding whether
  another application truly remains.
- Taskbar Guard: Uses a Windows show-event hook to hide primary and secondary Explorer taskbars as soon as they
  appear, with a low-frequency safety check for recreated or missed taskbar windows. The guard is stopped before
  intentional desktop restoration.
- Game Foreground Assist: Helps bring “fullscreen-ish” game windows forward using cached Win32 process-time
  samples instead of per-candidate WMI queries.
- Legacy game windows: Large, unowned, activatable surfaces from older games can participate even when they have
  no title or use the ToolWindow style. Small, owned, transparent, minimized, and non-activating windows remain
  excluded.
- AlwaysFocus list: A list of EXEs that should win focus over Steam when present. Add one from a currently
  running application or browse directly to its executable.
- Window management: Center windows and maximize only when “large enough,” with an exclusion list, bounded
  correction attempts, HWND/PID revalidation, and automatic cache cleanup.
- Cursor helpers: park the pointer at the active display edge once at boot and after a managed focus change using
  `SetCursorPos` rather than synthetic mouse input. The foreground observer also catches Steam restoring itself
  after a game; a short one-shot settle and verification keep Steam from restoring the old pointer position.
  Periodic checks of an already-focused window do not move the pointer or reset Windows' idle clock, so display-off
  and sleep timers can still expire. Physical mouse movement restores the cursor.
- Logging + live log viewer: Writes a log and provides an in-app live viewer for debugging. Operational notices
  and warnings are always retained; game-candidate scoring remains separately optional.
- Hidden Startup Programs: Optional list of extra programs to launch hidden/minimized at boot.
- Controller mouse mode (hold View/Back): Right stick moves mouse, left stick scrolls, D-pad arrows.
  Buttons are configurable (Short/Long) via the Controller Mapping window.
- Launcher Cleanup - Clean up launchers after exiting your game so no unnecessary tasks run in the background.
  Aggressive process termination is disabled by default.
- Controller-first Quick Menu with live volume/mute, audio output switching, guarded display-mode changes,
  Windows HDR toggle, focus controls, RTSS hooks, and confirmation-protected power actions.
- A compact Windows 11-aware Quick Menu with action and warning details retained in the SteamShell log.

## Quick Menu

The Quick Menu is designed for borderless-fullscreen games and Steam Big Picture. Navigate with the D-pad,
press A to select, B to go back, and left/right to adjust supported values.
The XFE-parity overlay is borderless, stays alive between page changes, and
repaints its existing rows while window redraw is suspended so each page appears
fully composed. It uses rendered dimensions for high-DPI centering and
rounded-corner shaping without the DWM backdrop frame.
When it has keyboard focus, arrows navigate, Enter/Space selects, Backspace goes
back, Home/End jump, and Delete closes the selected Task Switcher window.

- **Compact main page:** Audio, Display & HDR, RTSS & Performance, Steam Menu,
  Steam Quick Access, Controller Layout, Task Switcher, Game Bar, Settings, and
  System—the same top-level row set and descriptive value column as XFE.
- **Steam Menu / Launch Steam:** the row tracks whether Steam is running. With
  Steam running it sends the Steam Menu shortcut (or the in-game overlay chord
  when Steam is not the foreground application). With Steam closed it reads
  **Launch Steam**, starts Big Picture, and returns SteamShell to shell mode.
  Steam Quick Access reports `Steam is not running` and is inert meanwhile.
- **System:** Diagnostics, Health Check, **Exit Steam to Desktop** (or **Return
  to SteamShell** while in desktop mode), **Exit SteamShell**, Sleep, Restart,
  and Shut Down. Every one of those requires a second press to confirm.
- **Audio:** the XFE-matched submenu contains Back, Output, Volume, and Mute.
  Output and Volume support left/right adjustment.
- **Display:** the XFE picker stages Resolution, Refresh rate, and Scale
  independently, then applies them together from one Apply row. This avoids the
  former paginated list of flattened resolution/refresh combinations. A changed
  display transaction automatically reverts after 15 seconds unless Apply is
  selected again to keep it.
- **HDR:** reads the primary display's Windows Advanced Color state and provides
  explicit Off/On control. If the display driver does not expose that
  DisplayConfig interface, the row honestly reports Unsupported or Unavailable
  and does not claim an unverified state change.
- **RTSS:** with `UseDllIntegration=true`, SteamShell reads RTSS's live global
  overlay state through `RTSSHooks64.dll` and toggles it directly. **Frame Limit**
  is one row covering both of RTSS's mechanisms — the global limiter flag and the
  profile's `FramerateLimit` — cycling **Off · 30 · 40 · 60 · 90 · 120 · Custom**
  with Left/Right. Choosing Custom reveals a **Custom FPS** row whose step
  escalates 1 → 5 → 10 on consecutive presses, because Quick Menu navigation is
  edge-triggered and never auto-repeats. "Off" maps to the flag and never writes
  `0`, so turning the cap off and back on restores the number instead of
  forgetting it. **Save Limit to Profile** copies the current cap into the
  foreground executable's own RTSS profile behind a two-press confirmation; every
  other write targets the global profile only. If that DLL or its write exports
  are unavailable, the cap shows read-only and the configured HotkeyHandler
  shortcuts remain the automatic fallback. The submenu also distinguishes
  disabled, missing, ready-to-start, and running states and links directly to
  RTSS Settings.
- **Controller Layout:** shows the currently loaded short/long action for every supported View/Back button mapping.
- **Steam actions:** Steam Menu sends the configured Big Picture shortcut when
  Steam was in front and the configured overlay shortcut when a game was in
  front. The in-game overlay chord uses a paced key-down event so Steam's hook
  can reliably observe Shift+Tab after focus returns to the game. Steam Menu
  and Steam Quick Access default to Ctrl+1 and Ctrl+2; Game Bar shows Win+G.
- **Task Switcher:** lists normal visible application windows in Windows' current stacking order. Selecting one
  with A performs a one-time switch without pinning it. Pressing Y switches to that window and applies the
  session-only focus lock. The lock permits dialogs from the same application, releases when the selected window
  closes, and can be released from Task Switcher or by returning to the game/Steam. Press X on a highlighted
  window to send it a normal Windows close request; SteamShell does not force-terminate the process, so
  applications can still show their own save or confirmation dialogs. Hold X for the configured
  `TaskForceCloseHoldMs` interval to terminate the owning process; this can discard unsaved work and closes every
  window hosted by that process.
- **System:** groups Diagnostics Control Panel, Exit Steam to Desktop, sleep, restart, and shutdown.
- **Exit Steam to Desktop:** gracefully shuts Steam down first, then uses the same Explorer/shell restoration
  path used when Steam exits normally. If Steam does not close, restoration is cancelled rather than leaving a
  partially restored desktop. Automatic restoration remains disarmed until a **Big Picture window covering most of
  its monitor** has actually been seen; `SteamStartupGraceMs` then controls how long a boot may go without one
  before the recovery screen appears. Once seen, that observation is latched — a game covering or minimising Big
  Picture never re-opens the startup path — and process gaps must last for `SteamExitConfirmMs` before automatic
  restoration begins.
- **Power:** sleep, restart, and shutdown require a second confirmation.

Exclusive-fullscreen games may minimize when a normal Windows overlay receives focus. Borderless fullscreen is
recommended. SteamShell explicitly takes foreground ownership when Quick Menu opens so Steam Big Picture stops
handling its navigation. AutoHotkey observes XInput but does not suppress it at the driver level, so unusual games
that process controller input globally while unfocused may still see navigation presses.

## Settings

The Quick Menu includes a controller-friendly **Settings** area with four focused categories:

- **General + Startup:** startup splash, taskbar behavior, and Quick Menu Audio/Display modules.
- **Controller + Cursor:** controller mouse mode and speed, cursor hiding, event-based left/right mouse parking, and the
  controller mapping editor.
- **Focus + Window Engine:** Steam refocus, game foreground assistance, AlwaysFocus support, coordinated window
  management, and the session focus pause.
- **RTSS + Performance:** integration enable, overlay/limiter control modes, and the configured custom frame cap.

Quick Menu changes are written to `SteamShellSettings.ini` immediately. Startup-only rows are marked `NEXT BOOT`.

## Notification-area control

SteamShell uses its standalone charcoal/cyan controller icon in source mode and
embeds the same multi-resolution icon in compiled builds. The icon is registered
before SteamShell starts Explorer, because Winlogon starts SteamShell while no
shell exists yet: the first attempt to place the icon always fails, and the
`TaskbarCreated` broadcast that accompanies the first taskbar is what actually
places it. SteamShell listens for that broadcast and re-asserts the icon every
time, which also covers the Explorer restart performed during a desktop restore.

While SteamShell owns presentation the taskbar is hidden, so the icon is present
but not visible. It becomes the primary control surface in **desktop mode**
(below).

**Right-clicking the icon opens the ordinary Windows menu**, matching XFE.
Double-clicking opens the Quick Menu, via the menu's default item.

It briefly did not. AutoHotkey will not run a timer while a menu is displayed and
controller polling is a timer, so a native tray menu freezes controller-as-mouse
for as long as it is open — meaning a controller user could open the menu and
then be unable to move the pointer onto it. The right-click was taken over and
the Quick Menu shown instead.

That had the context backwards. Reaching a tray icon at all means using a
pointer, and a controller user opens the Quick Menu with L3 + R3 or
`Ctrl+Alt+Shift+Q` rather than steering a cursor into the notification area. The
interception optimised for a case that barely happens, at the cost of the one
that happens constantly: someone at a keyboard and mouse wanting a small, fast
menu where they clicked.

The freeze is accepted rather than forgotten. Anyone who does reach the menu by
controller emulation dismisses it the way any menu is dismissed — Escape, or a
click elsewhere — both available to whatever pointer opened it.

Every action in the tray menu is also reachable from the Quick Menu, so a
controller user never needs the notification area at all:

| Action | Where |
|---|---|
| Open Settings | Settings ▸ Open Full Settings Editor |
| Reload Settings | Settings ▸ Reload Settings |
| Open Diagnostics | System ▸ Diagnostics Control Panel |
| Launch Steam | main page ▸ Launch Steam (desktop mode) |
| Return to SteamShell | System ▸ Return to SteamShell (desktop mode) |
| Exit Steam to Desktop | System ▸ Exit Steam to Desktop (shell mode) |
| Exit SteamShell | System ▸ Exit SteamShell |

A session Disable action is intentionally not included because standalone
SteamShell owns Explorer and taskbar presentation while it is running.

## Desktop mode

Exiting to the desktop no longer terminates SteamShell. Explorer takes the
desktop back, but SteamShell stays resident so the notification-area icon,
controller-as-mouse, and the Quick Menu keep working on the normal Windows
desktop. Desktop mode is entered by:

- Steam closing while SteamShell is monitoring it (the automatic path),
- Quick Menu ▸ System ▸ **Exit Steam to Desktop**,
- the tray's **Exit Steam to Desktop**, or
- **Restore Desktop** on the Steam-did-not-start recovery screen.

In desktop mode SteamShell disarms everything that would fight Explorer: shell
monitoring, the window engine, the Taskbar Guard, cursor hiding and parking, and
Launcher Cleanup. Only controller polling stays scheduled. None of your saved
settings are modified — returning simply reschedules them.

Getting back:

- Quick Menu ▸ System ▸ **Return to SteamShell**, or the tray equivalent. If
  Steam is not running, the recovery screen is presented rather than leaving you
  on a guarded desktop with nothing to return to.
- The main Quick Menu's **Steam Menu** row becomes **Launch Steam** whenever
  Steam is not running. Choosing it launches Big Picture *and* returns to
  SteamShell presentation. Steam started by hand from the desktop deliberately
  does **not** re-arm the shell — only a launch SteamShell performed itself does,
  so starting Steam to browse your library never yanks the desktop away.

Registry behaviour is unchanged. A session restore still writes `explorer.exe`
to the current-user Winlogon `Shell` value as crash insurance before touching
Explorer, then writes the configured SteamShell value back once the taskbar is
verified, so the next sign-in still starts SteamShell. Only **Permanently
Restore Explorer** (Settings ▸ Advanced, the Setup Assistant, or
Ctrl+Alt+Shift+E) leaves `explorer.exe` registered — and that path still closes
SteamShell, because there is no longer a shell for it to own.

**Exit SteamShell** fully terminates the process. From desktop mode it exits
directly. From shell mode it performs the guarded desktop restore first and exits
as part of the same transaction, so it can never leave you with a hidden taskbar
and no shell.

If SteamShell is killed unexpectedly while in desktop mode, its Explorer-recovery
handler deliberately does nothing: Explorer is already the healthy visible shell
and the registry already holds the value you asked for. Running the recovery
would kill the desktop you are working on and silently drop SteamShell as the
next-sign-in shell.

**Open Full Settings Editor** launches a native Windows editor with General, Startup & Splash, Startup Programs,
Controller & Cursor, Focus & Windows, RTSS & Performance, Launcher Cleanup, and Advanced & Logging categories.
It validates numeric ranges before saving and provides Windows Browse dialogs for Steam.exe, the startup video,
mpv.exe, RTSS.exe, and each of the 20 optional startup-program slots. Its height follows the active monitor's
work area with a 660-logical-pixel ceiling, and long categories use a native Windows scrollbar that stays
synchronized with the mouse wheel. Wider field-label columns prevent long diagnostics labels from clipping,
and Advanced actions use a consistent two-column grid. The editor uses a standard Windows title bar with working
Close and Minimize controls; Maximize is disabled because the layout intentionally keeps a fixed width.

The full editor also supports direct controller navigation while it is foreground: D-pad or left stick moves
between controls, left/right adjusts choices and numeric values, A activates the selected control, LT/RT changes
category, Y saves, and B closes when no changes are pending. The right stick automatically controls the pointer,
and RB runs its configured short action (Left Click by default). That automatic pointer mode follows native file
and message dialogs plus SteamShell companion windows opened from Settings, including Controller Mapping,
AlwaysFocus Manager, Health Check, Diagnostics, and the live log. Companion windows receive pointer movement and
clicks without accidentally inheriting Settings-only category changes or save actions. Holding View/Back
temporarily uses the other normal configurable mappings, including mapped clicks and shortcuts. Selecting an edit
field with A opens the Windows touch keyboard; unsaved changes are never silently discarded from the controller.
Touch-keyboard requests use Windows' presentation host rather than restarting `TabTip.exe` or
`TextInputHost.exe`, with `/SeekDesktop` and the separately mapped classic OSK available as fallbacks for
custom-shell systems.

Settings-owned file pickers temporarily lower the always-on-top editor so the picker always remains accessible,
then restore and reactivate Settings when browsing is finished.

The Startup Programs category provides explicit **Add Program**, **Browse Selected**, **Apply Command**, and
**Remove Selected** actions, along with **Test Launch**, reordering, and Hidden/Minimized/Normal window modes.
New programs use the selected empty slot or the next available slot, while replacing an executable preserves
arguments already entered after it. The full editor applies runtime-compatible changes when **Save & Apply** is
selected and identifies options that require the next launch.
The RTSS shortcut rows include **Record** buttons that capture a key combination and convert it to the required
AutoHotkey send syntax. Advanced & Logging includes the common focus, game-assist, reload, INI, and live-log
actions; the separate Diagnostics Panel remains available for timed overrides and detailed runtime status.

Advanced & Logging also provides **Install SteamShell as Shell**, **Repair SteamShell Installation**,
**Register Current EXE as Shell**, and **Permanently Restore Explorer**.
These actions use the same compiled EXE—there is no companion service, updater, or recovery executable.
The managed Install action copies SteamShell to `%LocalAppData%\SteamShell` before registration. Register Current
EXE instead writes the current compiled EXE's exact path directly to the current-user Winlogon `Shell` value,
matching a portable `.reg` workflow. That EXE must not be moved or deleted until Explorer is restored.

The same area provides configuration recovery and diagnostics:

- **Health Check** validates Steam, the INI/schema, shell registration, Explorer/taskbar, startup paths, RTSS,
  controller detection/mapping conflicts, Launcher Cleanup safety, and desktop recovery.
- **Export Diagnostic ZIP** creates a sanitized bundle on the desktop containing the health report, system
  information, settings, and recent log lines.
- **Create Settings Backup**, **Export Settings**, and **Import / Restore** preserve portable configurations.
- **Restore Category Defaults** and **Reset All Settings** create backups before changing anything.
- **Restart in Safe Mode** keeps Explorer available and disables shell automation for the current session.
- **Setup Assistant** connects Steam/RTSS selection, controller testing, Health Check, portable use, installation,
  and recovery without a separate installer.

The Focus and Launcher Cleanup categories use executable-list editors rather than raw pipe-separated text.
Launcher Cleanup includes its background-helper list and a read-only preview of currently running cleanup targets.
Controller & Cursor includes a live controller test; inputs are captured instead of forwarded through mappings,
and a three-second centered-stick sample can calculate and apply a conservative deadzone.

Focus & Windows exposes the user-facing Steam refocus, game assistance, foreground-sensitivity preset,
AlwaysFocus, coordinated window-management toggle, maximize-width percentage, and exclusion controls. Foreground
sensitivity defaults to Responsive (55); Balanced (60) and Conservative (70) remain available without exposing
the individual CPU, audio, title, and geometry score components. The coordinated engine's scan cadence, retry
budget, and process sampling cadence use conservative internal defaults so ineffective timing combinations cannot
be configured. Quick Menu reports Window Management as `COORDINATED`, while Health Check and Diagnostics report
the last inventory size, scan duration, decision, and cumulative geometry/focus actions.

The Settings editor disables options that do not apply to the selected RTSS mode, Launcher Cleanup safety
configuration, or logging detail. `GameLogMode=OFF` is the single logging disable state; the former duplicate
logging checkbox is removed during settings migration. Steam is intentionally omitted from the AlwaysFocus Manager
because Steam fallback already has a dedicated place in the focus policy and allowing it into AlwaysFocus would
make it outrank games.

**Customize Quick Menu** can reorder the main rows and hide optional entries. Settings and System are always
retained as recovery paths even if the stored order is malformed.

## Single-EXE setup and recovery

SteamShell can install itself for the current Windows user. Compile the EXE, run it once from the normal desktop,
open Full Settings, and select **Install SteamShell as Shell**. The setup action:

- Copies the EXE to `%LocalAppData%\SteamShell\SteamShell.exe`
- Copies the current INI when the installed location does not already have one
- Saves the previous per-user Windows shell value
- Verifies the new shell registration
- Adds an emergency Restore Windows Desktop shortcut to the current user's Start menu

For a portable deployment such as `C:\Utilities\SteamShell.exe`, use **Register Current EXE as Shell** instead.
It verifies the direct current-user Winlogon registration, preserves the previous shell value, and creates the
same emergency restore shortcut without copying the EXE.

The main application follows the administrator-startup setting. Optional operations that require more permission
can fail cleanly when SteamShell is running unelevated.

The same EXE supports these command modes:

```text
SteamShell.exe /install
SteamShell.exe /repair
SteamShell.exe /restore
SteamShell.exe /uninstall
SteamShell.exe /safe
SteamShell.exe /selftest
```

Use `/install` and `/repair` from the normal Explorer desktop when another SteamShell instance is not active.
While SteamShell is running, use the equivalent buttons in Full Settings. `/restore` and `/uninstall` intentionally
replace the active instance so they can recover the desktop.

`/restore` and `/uninstall` both permanently register Explorer as the Windows shell and start a verified desktop.
They deliberately leave the SteamShell folder and INI in place so recovery never deletes user data. If SteamShell
is forcibly ended, open Task Manager with Ctrl+Shift+Esc, choose **Run new task**, and run:

```text
%LocalAppData%\SteamShell\SteamShell.exe /restore
```

If Steam itself cannot start, SteamShell displays a recovery window with Retry Steam, Open Settings, and Restore
Desktop. The D-pad selects an action and A activates it.

`/safe` does not change the saved INI or permanent shell registration. It starts Explorer, skips Steam and startup
programs, disables the splash, cursor parking/hiding, window/focus automation, and Launcher Cleanup, then opens
Full Settings. Reloading the INI during that session cannot re-enable the disabled modules.

`/selftest` runs parser, schema, list-normalization, Quick Menu ordering, startup-command, and process-time CPU
calculation invariants without starting the normal shell session.

## Build validation

`Build-SteamShell.ps1` runs `Validate-SteamShell.ps1` before asking AutoHotkey to validate and compile the script.
The static validator checks duplicate function declarations, embedded/sample INI schema parity, required recovery
and window-engine functions, Settings-editor and Quick Menu schema bindings, named UI/timer callbacks, Quick Menu
row dispatch, ampersand-safe Settings headings, the controller-deadzone migration, desktop-restore linkage,
whitespace hygiene, one full-window scanner, and one scheduled focus-policy call. It also rejects the retired WMI
process query and legacy focus entry points.

## Optional RTSS setup

SteamShell pre-fills RTSS's standard executable path and leaves integration
disabled until setup is complete. Set `[RTSS] EnableIntegration=true`.
`UseDllIntegration=true` (the default) derives `RTSSHooks64.dll` from the
configured executable directory and uses its `GetFlags`/`SetFlags` exports for
live global state and direct control, plus `LoadProfile`/`GetProfileProperty` to
read the cap and `SetProfileProperty`/`SaveProfile`/`UpdateProfiles` to write it.

The three write exports are treated as **optional**. An RTSS build without them
keeps overlay and limiter control and shows the frame cap read-only, rather than
taking the whole integration down. Writes go to the **global** profile; the only
per-game write is the explicit, confirmed **Save Limit to Profile** row.

`SaveProfile` persists to RTSS's own configuration, so a cap set from the Quick
Menu is a real edit visible in RTSS, and every write is logged.

If the DLL is missing, incompatible, disabled, or blocked by a privilege
boundary, SteamShell falls back to the existing shortcut configuration. In that
mode `OverlayControlMode=Toggle` cannot report the resulting state and therefore
continues to label the action `TOGGLE`.

For deterministic controls, configure separate Show OSD and Hide OSD hotkeys in RTSS or MSI Afterburner:

```ini
OverlayControlMode=Separate
OverlayOnShortcut=^+1
OverlayOffShortcut=^+2
```

Separate mode displays explicit Overlay On and Overlay Off actions. Ctrl+Shift+1 and Ctrl+Shift+2 are prefilled;
configure exactly the same Show and Hide actions in RTSS or MSI Afterburner.

The settings below configure the **shortcut fallback** — the path used when the
DLL or its write exports are unavailable. With DLL integration working, the Quick
Menu's Frame Limit row supplies the presets and the Custom value directly, and
none of these shortcuts are needed:

```ini
[RTSS]
EnableIntegration=true
Path=C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe
UseDllIntegration=true
OverlayToggleShortcut=^+o       ; Ctrl+Shift+O
FrameLimiterControlMode=Toggle
CustomFrameCap=117
CustomFrameCapShortcut=^+f      ; Ctrl+Shift+F
```

In shortcut-fallback Toggle mode, the Quick Menu displays `TOGGLE • 117 FPS`
but does not claim the limiter is on or off. `CustomFrameCap` is only the
fallback label, so configure RTSS to use the same value. With DLL integration,
the Frame Limit row instead sets RTSS's global limiter flag and the global
profile's numeric limit directly, and `CustomFrameCap` is unused.

For explicit limiter controls, configure matching enable and disable actions:

```ini
FrameLimiterControlMode=Separate
CustomFrameCap=117
FrameLimiterOnShortcut=^+5
FrameLimiterOffShortcut=^+6
```

Separate mode displays Frame Limiter On and Frame Limiter Off. Ctrl+Shift+5 and Ctrl+Shift+6 are prefilled; configure
matching enable and disable actions in RTSS. The retired `FrameCapOptions`, `FrameCap0Shortcut`, and numbered
`FrameCap...Shortcut` fields are ignored if they remain in an older settings file.

## Building the executable

SteamShell remains compatible with AutoHotkey v2.0.19 and newer and compiles into one executable with Ahk2Exe.
On Windows, install AutoHotkey v2 with its compiler and
run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Build-SteamShell.ps1
```

For a double-clickable build with a persistent result window, run
`Build-SteamShell.cmd`.

The build script creates `dist\SteamShell.exe` and embeds
`assets\SteamShell.ico` by default (`-IconPath` still accepts an override).
Windows-specific features must be tested on the intended HTPC;
they cannot be executed or validated from a macOS development machine.

SteamShell intentionally rejects a 32-bit AutoHotkey base. If compiling through the Ahk2Exe GUI instead of the
build script, select `AutoHotkey64.exe` as the Base File. The build script checks both system-wide and per-user
AutoHotkey installations and selects the 64-bit v2 interpreter automatically.

## Black desktop background

`[Features] EnableDesktopBlackout` (**on by default**) removes the wallpaper and
desktop icons from every gap around Steam — after the splash fades before Steam
paints, when Steam is windowed or minimised, and between a game exiting and Steam
repainting.

It works in two parts. A full-screen black window supplies the pixels, and the
Explorer desktop windows (`Progman` and `WorkerW`) are hidden the same way the
taskbar already is. Both are needed: a bottom-most window alone lands *below*
`Progman` where it is invisible, and hiding `Progman` alone leaves nothing
painting the screen.

**It owns no system or registry state.** The wallpaper setting is never touched.
Everything the blackout changes either dies with the process or is undone by the
Explorer restart that unexpected-exit recovery already performs. That is why this
approach was chosen over clearing the wallpaper through `SPI_SETDESKWALLPAPER`,
which would survive a crash and leave the user to restore it by hand.

Safeguards:

- The backdrop is `WS_EX_NOACTIVATE`, so it cannot take focus, and
  `WS_EX_TOOLWINDOW`, so it never appears in Alt+Tab.
- It is re-sunk to the bottom every second, and re-hidden on the same
  `EVENT_OBJECT_SHOW` hook the Taskbar Guard uses, so Explorer cannot quietly
  restore the desktop behind it.
- If the backdrop is ever detected as the foreground window it is pushed straight
  back down and the event is logged.
- It is sized to the whole virtual screen and re-fits when the monitor layout or
  resolution changes.
- Health Check reports blackout state, backdrop presence, desktop visibility, and
  whether the event hook or the periodic fallback is doing the work.
- It is disabled automatically in Safe Mode and in desktop mode, and released
  before every desktop restore.

**Turning it off:** Quick Menu ▸ Settings ▸ General + Startup ▸ **Black Desktop
Background**, which applies immediately rather than at next boot. That matters —
if the backdrop ever misbehaves, the Quick Menu is `AlwaysOnTop` and stays
reachable over it, so a controller alone is enough to recover. The same setting
is in Full Settings under Features.

Desktop icons are hidden along with the wallpaper. If you want the wallpaper gone
but icons kept, this setting is not the right shape for that — say so and it can
be split into two levels.

## Explorer “ghost mode” (Game Bar / UWP compatibility)

SteamShell uses an “Explorer ghost mode” approach so you get a console-like experience **without** breaking
Windows features that depend on Explorer/UWP plumbing (notably **Microsoft Game Bar** and other UWP components).

What this means in practice:
- **Explorer is running in the background** to keep required Windows components happy.
- The **taskbar / shell UI is hidden**, so you still get a clean “Steam-first” kiosk feel.
- This helps keep **Game Bar** (Win+G) and other UWP-backed features working, even though you’re not using the
  normal Explorer desktop as your primary shell.

When Steam exits:
- SteamShell performs a full desktop restore (unhide taskbar + start/restart Explorer) so you land on a normal desktop.
- It then resets the Winlogon Shell setting back to SteamShell.exe so the next reboot returns to the SteamShell setup.
- SteamShell itself stays running in **desktop mode** so its notification-area icon, controller mouse, and Quick
  Menu remain available. See [Desktop mode](#desktop-mode).

Because the restore restarts Explorer, every notification-area icon in the session is destroyed and re-added via
the `TaskbarCreated` broadcast. SteamShell re-asserts its own icon on that broadcast rather than relying on
timing, since it is the process that killed Explorer.
