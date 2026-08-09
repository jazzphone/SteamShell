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

The 1.7.1 source is preserved in `../releases/1.7.1`. This tree is the
SteamShell **2.0.1** source; 2.0.0 is locked together with XFE in
`../releases/2.0.0`, and 1.7.3 remains the
pre-rendering-rewrite revert point. The feature-by-feature XFE port decisions are recorded in
`XFE_PARITY_NOTES.md`. The current settings schema is 23.

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
- Ctrl+Alt+Shift+I : Re-arm controller input (recovery and diagnosis after sleep)
- Ctrl+Alt+Shift+D : Delete the learned controller profile (recovery from a bad one)

## Controller shortcuts

- Hold L3 + R3 for about 0.5 seconds : Open or close Quick Menu
- Hold View/Back and tap Start : Open the Windows Start menu
- Hold View/Back and hold Start : Open File Explorer
- The mapped Task Manager action uses Windows' native Ctrl+Shift+Esc shortcut. If Windows elevates Task Manager,
  the separate elevated helper supplies safe controller mouse actions while the main shell stays normal.
- LB + RB + L3 + R3, **held** : Emergency/fallback Full Settings chord. The hold matches the Quick Menu's
  L3 + R3 chord so a stray grip during play cannot throw Full Settings over a running game. It is declined while the
  Quick Menu, Full Settings, the controller test, or the Steam recovery screen already has controller input — each of
  those offers its own route to Settings.

Every View/Back mapping, including these Start actions, can be reassigned in the Controller Mapping window. Quick
Menu and Control Panel remain available as optional built-in actions but are unassigned by default.

## Controller input after sleep

SteamShell recovers controller input across a suspend without help. It is worth
knowing how, because the failure it guards against is silent.

RawInput locks onto one device handle so a headset or a remote cannot feed
nonsense into the decoder. Those handles are **not stable**: Windows re-enumerates
HID devices across a suspend and the same controller comes back with a different
one. Three layers cover that:

1. **Device hand-over.** If the locked device has been quiet for over a second and
   a different one is producing usable reports, the decoder adopts it. This
   depends on no notification from Windows, so it is the layer that does the work.
   A device that is actively reporting is never displaced.
2. **`WM_POWERBROADCAST`.** Releases the lock and re-asserts the RawInput
   registration on resume — the one failure hand-over cannot fix, because a lost
   registration produces no report to adopt.
3. **A wall-clock gap check**, run from the controller poll. **Modern standby does
   not reliably deliver the power broadcast**, and modern standby is what a
   handheld sleeps into, so layer 2 cannot be the only trigger. The check compares
   `A_Now`, not a tick counter — the tick counter does not advance through
   suspend, so a gap measured on ticks sees nothing at all.

**Manual recovery:** `Ctrl+Alt+Shift+I`, or **Settings → Advanced → Re-arm
Controller Input**. It releases the lock, re-registers RawInput and forces an
XInput rescan.

It is a diagnostic as much as a recovery, and the honest limitation is reaching
it: a user whose controller has stopped answering cannot navigate to a button with
the controller, and a handheld has no keyboard. What it buys is a one-click answer
to *which* failure you had — if input returns, the cause was the stale handle or
the registration rather than the backend.

Reconnecting a controller while the machine is running needs none of this.
RawInput is registered by **usage page**, not by device, so a reconnected pad
starts producing reports immediately and hand-over adopts it within a second.

## Controller mouse smoothness

Cursor speed is a **velocity** — `ControllerMouseSpeed` is pixels per second at
full stick deflection, and the Settings slider shows the whole usable range
rather than asking you to guess a number.

It was pixels per *poll tick*, which made the cursor's speed depend on how often
the timer happened to fire, and that produced a visible stepping along the path:

- **Windows quantises timers to about 15.625 ms** unless a process raises the
  resolution, and nothing here does. A timer fires on the first tick boundary at
  or after its interval, so the old 16 ms poll — 0.375 ms past a boundary — could
  not fire at 15.625 and waited for 31.25. The poll ran at roughly **32 Hz while
  the setting implied 62.5**, and scheduling noise flipped it between one boundary
  and two.
- **A fixed distance per tick turns uneven timing into uneven distance.** Ticks
  arriving 15.6, 31.2, 31.2 ms apart moved the cursor the same amount each time,
  so it stepped rather than travelled.

Movement is now scaled by measured elapsed time, so a late tick moves
proportionally further and on-screen velocity stays constant regardless of the
timer. The default interval is **15 ms**, which fires on every boundary — about
64 Hz, half the step size of before at the same speed. A sub-pixel remainder is
carried between ticks rather than rounded away, which is what makes the smaller
distances usable.

Changing the poll interval now changes *smoothness only*, not speed. That is the
point of the change: the two used to be the same knob.

**Upgrading:** settings schema 23 converts existing values (×32) so the cursor
moves at the speed you were already used to, and moves a `ControllerPollIntervalMs`
of exactly 16 to 15. A deliberately chosen interval is left alone.

### The View/Back button's own action

View/Back can also carry a Steam action of its own, on a press that was **not**
used to reach a mapping. It is off by default here and configured in
**Settings → Steam**.

| | tap | hold |
|---|---|---|
| Steam in front | Steam menu | Steam Quick Access |
| a game in front | nothing | Steam overlay |

The tap doing nothing inside a game is deliberate: SteamShell never blocks input,
so the game receives View normally and keeps its own use of it. The in-game hold
threshold is separate and longer (1000 ms against 500 ms) because View is
commonly the scoreboard or map button.

This does not conflict with View/Back being the mapping modifier. Any other input
during the hold — a button, a trigger, a stick — marks the press as a modifier use
and its own action is dropped on release, so *hold View, press A* fires the A
mapping and nothing else. Automatic mouse mode is expressed as a virtual View
hold and never triggers it either; only the physical button counts.

### Automatic mouse mode

`[Controller] AutoMouseExeList` names executables where those same mappings apply **without holding View/Back**.
Settings ▸ Controller & Cursor edits the list — **Shell-mode automatic mouse
allowlist** in SteamShell, **Automatic mouse applications (pipe-separated)** in
the companion. The exclusion list beside it is **Desktop-mode exclusions
(games/apps)**.

Both products ship the same default list:
`explorer.exe|brave.exe|chrome.exe|msedge.exe|firefox.exe|notepad.exe|taskmgr.exe`
— the Windows shell surfaces, the four browsers most likely to be installed, and
the two utilities a sofa user is most likely to need. `DesktopAutoMouseExcludeExeList`
ships **empty**. It previously shipped `brave.exe`, which is the opposite list: it
turned automatic mouse *off* for Brave in desktop mode while never turning it on
in shell mode, so a browser was the one place the pointer did not work.

Windows Settings is deliberately absent, and cannot be added by name at all:
`ms-settings:` opens a window owned by `ApplicationFrameHost.exe`, so
`SystemSettings.exe` never matches a foreground lookup. Control Panel is absent
because it is an Explorer window and `explorer.exe` already covers it.

`[Features] EnableAutoMouseMode` (Settings ▸ Controller & Cursor ▸ **Enable
automatic mouse mode (master switch)**) is a separate switch, on by default. It
exists so the behaviour can be turned off without discarding the
list: the list is the part that takes effort to build, and *is this feature causing what I am seeing?* is a question
worth being able to answer without having to rebuild it afterwards. Both gates must pass — the toggle allows the
feature, the list decides where it applies during SteamShell presentation — so
clearing either one is enough to stop shell-mode automatic mouse. The master
toggle also disables the desktop-wide mode described below.

It is deliberately not a second input mode. The View/Back mappings are already a complete desktop mouse out of the
box — right stick moves, left stick scrolls, D-pad arrows, RB left-clicks, RT right-clicks, X opens the touch
keyboard, Start opens the Start menu — so automatic mode reuses them rather than inventing a parallel keymap that
could drift from the one you configured. What happens automatically is exactly what holding View/Back does, and
holding View/Back while it is active changes nothing.

Reasonable entries are `explorer.exe` and a browser such as `brave.exe`. The
`explorer.exe` entry represents the Windows shell family: File Explorer, desktop,
taskbar, Start menu, and Start/Search surfaces. Modern Windows hosts Start and
Search in separate system processes, but SteamShell resolves those internally so
they do not need to be added to the list individually.

**Do not list a game.** If you do, the controller becomes a mouse inside it — but the escape chords still work,
because they are evaluated before automatic mode and read the real button state. L3 + R3 opens the Quick Menu and
the held six-button chord opens Full Settings, so the list can always be corrected without reaching for a keyboard.

The cursor is unhidden when automatic mode engages; moving a pointer that cannot be seen is not a usable mode.

### Desktop-wide automatic mouse

`[Features] EnableDesktopAutoMouseMode=true` makes automatic mouse mode apply to
every foreground application while SteamShell is in Windows desktop mode. This
is enabled by default because **Exit Steam to Desktop** explicitly hands control
to Windows; the conservative `AutoMouseExeList` behavior resumes automatically
when SteamShell presentation returns.

`[Controller] DesktopAutoMouseExcludeExeList` is the pipe-separated safety list
for games or applications that must keep raw controller input on the desktop.
SteamShell intentionally does not guess from fullscreen window shape: a
maximized browser, media player, remote desktop, or emulator can look identical
to a game. Add a game's executable here before launching it from desktop mode.

While desktop mode is active, the notification-area menu includes a checked
**Automatic Mouse Throughout Desktop** item. Selecting it immediately disables
or enables the desktop-wide behavior and saves the setting. Turning it off from
the tray disables automatic mouse throughout desktop mode; it does not erase the
allowlist or exclusion list. Enabling it also enables the master automatic-mouse
switch if that prerequisite was off, so a checked tray item always means the
feature is genuinely active.

## Naming an application without typing it

Every list above is a list of executable names, and every one of them used to be
filled in the same way: know what the process is called, then type it. On a
machine being driven from a sofa that is the step that does not happen, so the
lists stay empty and the features that read them look like they do not work.

Two answers, deliberately kept separate, because they answer different questions.

### Recent… — what you were using

A picker of the last **five** applications you had in the foreground, most recent
first, one row per executable however many windows it had, with the last window
title beside the name so `brave.exe` is recognisable as the thing you were
reading.

- **Shell:** every executable-list field in Settings now has three buttons —
  **Browse… / Recent… / Remove** — where it had two. Also **AlwaysFocus Manager ▸
  Add Recent App…**.
- **Companion:** Settings ▸ Controller & Cursor ▸ **Add Recent Application…**,
  which appends to the automatic-mouse list.

The history is sampled on its own one-second timer rather than from either tree's
foreground observer, because the shell's observer runs inside the window-engine
tick and that stops in desktop mode — the history would have been silently empty
in one mode of one product, which is worse than having none.

It is held **in memory and never written to disk**. It lasts as long as the
process, which for a shell is the whole login session; persisting it would mean an
INI that grows, a pruning rule, and a record of every application the user has
opened sitting inside a diagnostic bundle they were asked to send to somebody.

The point of a history rather than a live window list is the applications you have
**closed**: those are exactly the ones whose executable name you no longer have any
way to look up.

Excluded from it: SteamShell's own windows, the desktop, taskbar, Start, Search,
the touch keyboard, the lock screen — things Windows shows rather than things a
user ran — and everything hosted by `ApplicationFrameHost.exe`.

### Current Application — what you are looking at now

Quick Menu ▸ System ▸ **Current Application**, in both products. The row's value is
the executable that was in front when the menu opened; selecting it lists the
executable lists that application can be added to, and choosing one writes it,
logs the section and key, and notifies. A second visit shows **(already added)**
beside a destination it is already on.

| Destination | Setting | Shell | Companion |
|---|---|:---:|:---:|
| Automatic Mouse | `[Controller] AutoMouseExeList` | Yes | Yes |
| Always In Focus | `[AlwaysFocus] ExeList` | Yes | — |
| Protect From Cleanup | `[LauncherCleanup] ExcludeExeList` | Yes | — |
| Protect From Cleanup | `[Assist] ProtectedProcesses` | — | Yes |
| Exclude From Desktop Mouse | `[Controller] DesktopAutoMouseExcludeExeList` | Yes | — |

The two "protect from cleanup" rows are one destination under two spellings: each
product has always stored that list in its own place, and inventing a third
location to make the table shorter would break both products' existing settings.

This works in the Quick Menu and cannot work in Settings, for the same reason:
both trees snapshot the previous foreground window before the menu takes it, and
Settings has no equivalent moment.

**A Store app is refused, out loud.** With Windows Settings, Photos or Calculator
in front the row reads *"Store app — cannot be added by name"* and will not open
the destination page. A packaged app's visible window belongs to
`ApplicationFrameHost.exe`, so adding it by name would write one entry that
silently matches Settings, Photos, Calculator, the Store and everything else of
that shape. The picker above handles the same case by filtering the frame host out
of its history; here the user is pointing *at* the window, so filtering would look
like the feature being broken and it says so instead.

## Two products, one installer

`SteamShell.exe` installs either of two things, and Setup Assistant opens with
the question everything else depends on:

| | Replace the Windows shell | Work alongside Xbox FSE |
|---|---|---|
| What is installed | `SteamShell.exe` | `SteamShell-XFE.exe` |
| Winlogon `Shell` registration | Yes | **Never** |
| Elevated input helper | Yes | **Never** — XFE stays normal integrity |
| Startup | Winlogon | Per-user logon task, `LeastPrivilege` |
| Recovery shortcut | Yes | Not needed; Explorer still owns the desktop |
| Auto-Login, UAC guidance | Shared | Shared |

The XFE companion is embedded in `SteamShell.exe` exactly as the elevated helper
is, so one download installs either. Choosing XFE on a machine where SteamShell
is currently the registered shell restores Explorer first, so switching products
is a supported move rather than something that leaves Winlogon pointing at an
executable you have stopped using.

XFE keeps its INI, controller profiles, and log beside its own executable, so
Setup makes that directory writable by you. That is safe for the same reason it
is not safe for the helper: nothing in the XFE layout is ever handed an elevated
token.

### Which product this PC has

Recorded in `HKCU\Software\SteamShell\Product` and in `[Setup] Product`,
because the uninstall for one product is wrong for the other — running the shell
restore on an XFE machine would rewrite a Winlogon value SteamShell never set.

`SteamShell.exe /uninstall` resolves the recorded product, cross-checks it
against what is actually on disk, and only asks you when the record is missing or
contradicts the disk. Running unattended with an ambiguous record does nothing
rather than guessing.

`/restore` is deliberately product-independent: it is the emergency command for
when the desktop is gone, which cannot happen on an XFE machine, so it always
puts Explorer back.

Once a machine is recorded as XFE, `SteamShell.exe` no longer starts the shell
runtime at all — it opens Setup Assistant, because there it is the installer and
the uninstaller rather than the product.

## Elevated window helper

SteamShell 2.0.1 uses two privilege levels. `SteamShell.exe`—including Quick
Menu, Settings, recovery, Steam launch, and every ordinary child—runs at normal
integrity. This lets Steam observe that a normal SteamShell window took the
foreground, preventing controller input from continuing into Big Picture behind
Quick Menu, Explorer, or Settings.

`SteamShell-Helper.exe` is compiled first and embedded inside the main EXE. Setup
extracts it to the protected managed component directory or the portable
sidecar's `bin` directory. At normal startup the main process verifies the
helper version and starts only that helper elevated. Standard installations
register a hidden, on-demand highest-privilege scheduled task whose action points
through the protected Program Files chain; this avoids a UAC prompt on every
shell start. If task registration or launch fails, SteamShell falls back to an
explicit UAC request. Custom and Portable installs always use explicit UAC. Even
when their `bin` itself is secured, an arbitrary writable parent can allow the
whole path to be deleted and recreated; an independently invokable task would
bypass SteamShell's launch-time protection check. Registering either as the
Windows shell therefore prompts for administrator approval at every sign-in, and
Setup warns before applying that combination. The helper has no
tray icon or visible UI, exits when its parent SteamShell process ends, and
polls/injects controller input only while a High/System-integrity window owns
the foreground. It also applies the same center/maximize policy, threshold, and
exclusion lists to elevated application windows that Windows prevents the
normal-integrity Window Engine from moving. Geometry uses the same bounded
settle/retry policy rather than continually forcing an application-controlled
window. The helper also verifies that its user and session match its
parent before enabling its input timer; the main independently verifies the
helper's exact path, user, session, and High-integrity token. Main SteamShell detects the same boundary and stops its own
mapping path there, preventing duplicate movement, clicks, or release actions.
The parent exposes only a per-process Windows event for geometry state: Shell
mode signals it, while Desktop and Safe modes reset it. This preserves elevated
controller input in Task Manager on the desktop without unexpectedly managing
desktop-mode window positions.
The helper accepts only a fixed safe elevated-input vocabulary: pointer motion,
wheel, clicks, arrows, Enter, Escape, and Alt+F4. It deliberately ignores custom
`Send:` bindings and launch/system actions so the user-writable INI cannot become
an arbitrary high-integrity keystroke or process-launch bridge. Task Manager, a
small fixed set of Windows administration hosts, and executables explicitly put
on the user's automatic-mouse allowlist receive automatic mouse mode; other
elevated applications require the physical View/Back modifier unless the user
has deliberately enabled persistent mouse mode.

The **Enable elevated helper for administrator windows** option under
**Startup & Splash** defaults to On. If elevation is declined, SteamShell and
all normal-integrity features continue working; controller input and automatic
geometry for elevated windows are unavailable. Turning the option off and
reloading settings stops a helper that is already running, rather than waiting
for the next SteamShell start.

Helper activity and failures are recorded in `SteamShell-Helper.log` **beside the
helper executable** — `components\bin` for a managed install, `SteamShell\bin`
for a portable one — and are reported by Health Check. It is not written to the
writable data folder: an elevated process appending to a path the interactive
user controls is an invitation to redirect that write somewhere it does not
belong. The log rotates on the same `[Logging]` size and backup-count settings
as `SteamShell.log`.

### The helper binary must be administrator-protected

Setup restricts the `bin` directory holding `SteamShell-Helper.exe` to SYSTEM and
Administrators (read and execute for everyone else) in **every** installation
mode, portable included, and changes the owner to Administrators. Ownership is
part of the protection: Windows gives an object's owner the implicit ability to
rewrite its DACL, even when no writable allow entry is visible. Only `bin` is
restricted, so a portable layout keeps its writable INI, logs, and backups beside
it as before.

Before each launch SteamShell re-checks that neither the helper nor its directory
is owned by or writable by anyone outside that set, and **refuses to elevate it**
if either is. Setup secures the directory before unconditionally replacing the
helper from the embedded payload; it never blesses a pre-existing file merely
because its version resource matches. A version resource is metadata that anyone
can stamp onto any file, so without these checks a writable helper directory
would be a way to have SteamShell hand arbitrary code an administrator token.

If Health Check reports **Elevated helper protection** as failed — most likely
because the folder was moved by hand, or the helper on disk is not the
2.0.1.1 build this release expects — start
SteamShell with **Run as administrator** and apply Setup again to re-secure it.

### Controller behavior over administrator windows

While a High/System-integrity window such as Task Manager owns the foreground,
the helper handles cursor movement, scrolling, clicks, `Enter`, `Esc`, `Alt+F4`,
Task Manager, Start menu, Game Bar, and `Ctrl+Alt+Tab`. The main process keeps
handling the five mappings that must run at normal integrity — **touch keyboard,
on-screen keyboard, File Explorer, Quick Menu, and Control Panel** — because they
start a process or raise a SteamShell window, neither of which should inherit an
administrator token. Every builtin mapping is therefore handled by exactly one of
the two processes.

Custom `Send:` mappings are deliberately ignored over elevated windows. The INI is
user-writable by design, and honoring arbitrary keystrokes from it inside a
High-integrity process would turn a settings file into a privilege boundary.

`EnableDesktopAutoMouseMode` is also narrowed there: automatic mouse mode applies
to Task Manager, Microsoft Management Console, Control Panel, and the Settings
administrator flows, but not to every elevated application. Hold **View/Back** to
use the controller mouse in any other administrator window.

The signed-in shell account must itself have an administrator split token for
the helper to run under the same identity. Supplying credentials for a different
administrator is deliberately rejected rather than creating a cross-account
elevated input bridge.

Install and upgrade are explicit administrator maintenance sessions. If a
pending first launch or Setup **Apply** runs normally, SteamShell displays
**Please Start SteamShell As Administrator for First Install or Upgrade**. OK
records a one-time request for that exact user/session, restores a usable
Explorer desktop, and closes the current instance. Right-click the same
`SteamShell.exe` and select **Run as administrator**. The elevated launch opens
Setup Mode, closes existing same-user/same-session SteamShell instances, waits
for their parent-bound helpers, and closes only verified helper leftovers.
Using credentials for a different administrator is rejected. Completed normal
shell sessions remain unelevated. Portable installations warn that the user is
responsible for keeping both the main EXE and extracted helper in a trusted
directory.

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
- Hidden Startup Programs: Optional list of extra programs launched as the
  standard interactive user, hidden/minimized at boot.
- Controller mouse mode (hold View/Back, or enable persistent Mouse Mode): Right
  stick moves mouse, left stick scrolls, D-pad arrows.
  Buttons are configurable (Short/Long) via the Controller Mapping window.
- Launcher Cleanup - Clean up launchers after exiting your game so no unnecessary tasks run in the background.
  Aggressive process termination is disabled by default.
- Controller-first Quick Menu with live volume/mute, audio output switching, guarded display-mode changes,
  Windows HDR toggle, focus controls, RTSS hooks, and confirmation-protected power actions.
- A compact Windows 11-aware Quick Menu with action and warning details retained in the SteamShell log.

## Quick Menu

The Quick Menu is designed for borderless-fullscreen games and Steam Big Picture. Navigate with the D-pad,
press A to select, B to go back, and left/right to adjust supported values.
The XFE-parity overlay is borderless, stays alive between page changes during an
open session, and
repaints its rows as one opaque GDI+ bitmap while window redraw is suspended, so
each page appears fully composed. The selected row has an antialiased rounded
fill, accent outline, left accent bar, and visible DPI-scaled glow; values are right-aligned
and ellipsized when necessary. The bitmap is created at the control's physical
pixel size for sharp high-DPI rendering without turning the menu into a layered
window. Its base is dark neutral charcoal (`#242424`) rather than Steam
blue-black. Bitmap swaps and page redraws suppress background erasure so normal
navigation does not flash between frames. Windows 11
supplies antialiased window corners with its border drawing explicitly disabled;
unselected labels and values use neutral grays rather than blue-gray text.
Windows 10 uses the shaped-window fallback when modern DWM corner attributes are
unavailable. A custom exterior shadow is deliberately omitted because its robust
implementation would require a separate layered companion window.
Closing the menu destroys its window and bitmap rather than retaining a hidden
DWM surface; the next open rebuilds it. This prevents a stale menu image from
reappearing when a fullscreen game exits.
During **Exit Steam to Desktop**, the menu window and row bitmap are destroyed
and flushed from DWM, then cannot be recreated until Explorer is ready. The next
open rebuilds them normally. This prevents a non-interactive image of its child
surfaces surviving as Steam's fullscreen presentation disappears.
When it has keyboard focus, arrows navigate, Enter/Space selects, Backspace goes
back, Home/End jump, and Delete closes the selected Task Switcher window.

- **Compact main page:** Audio, Display & HDR, RTSS & Performance, Steam Menu,
  Steam Quick Access, Task Switcher, Game Bar, Open Keyboard, Mouse Mode,
  Settings, and System—the same applicable top-level row set and descriptive
  value column as XFE. Hold Y on this page to open the styled Controller
  Mappings submenu.
- **Accent color:** Settings ▸ General & Startup ▸ Quick Menu Accent cycles
  Steam Blue, Blue, Purple, Magenta, Red, Orange, Yellow, Green, Teal, and a
  custom `RRGGBB` color. The fill is derived from the accent and changes live;
  Full Settings exposes both the preset and custom-hex fields.
- **Steam Menu / Launch Steam:** the row tracks whether Steam is running. With
  Steam running it sends the Steam Menu shortcut (or the in-game overlay chord
  when Steam is not the foreground application). With Steam closed it reads
  **Launch Steam**, starts Big Picture, and returns SteamShell to shell mode.
  Steam Quick Access reports `Steam is not running` and is inert meanwhile.
- **System:** **Exit Steam to Desktop** (or **Return to SteamShell** while in
  desktop mode), **Game Detection**, **Current Application**, **Exit
  SteamShell**, Sleep, Restart, and Shut Down. The transition, exit, and power
  actions require a second press to confirm.
- **Game Detection:** a read-only page showing what the window scorer decided —
  the winner and every candidate it beat, with the numbers that produced the
  result. Every one of those numbers was already computed in order to pick a
  game; this only shows the losers beside the winner, which is the difference
  between "it picked the wrong window" and a report someone can act on without
  asking for a log. Present when `EnableGameDetectionMenu` is on.
- **Current Application:** names the executable that was in front when the menu
  opened and adds it to one of four executable lists — Automatic Mouse, Always
  In Focus, Protect From Cleanup, Exclude From Desktop Mouse. It sits beside
  Game Detection rather than inside it: that page explains what the scorer
  decided, this one *writes settings*, and a user should not have to enter a
  diagnostic to configure something. See **Naming an application without typing
  it** above for the destination table and the Store-app refusal.
- **Audio:** the XFE-matched submenu contains Back, Output, Volume, and Mute.
  Output and Volume support left/right adjustment.
- **Display:** the XFE picker stages Resolution, Refresh Rate, and Scale
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
  profile's `FramerateLimit` — cycling **Off · 30 · 40 · 60 · 90 · 120 · Preset · Custom**
  with Left/Right. Preset uses `PresetFrameCap` from Settings. Choosing Custom
  restores its last retained value and reveals a **Custom FPS** row whose step
  is always exactly 1. Holding Left/Right accelerates the repeat rate while
  preserving precise single-step input, and the new cap is committed once after
  input settles rather than writing the RTSS profile on every repeat. "Off" maps
  to the flag and never writes `0`, so turning the cap off and back on restores
  the number instead of forgetting it. The selection is also recorded and
  reapplied after a reboot — see **Restoring the Frame Limit** below. **Save Limit to Profile** copies the current cap into the
  foreground executable's own RTSS profile behind a two-press confirmation; every
  other write targets the global profile only. If that DLL or its write exports
  are unavailable, the cap shows read-only and the configured HotkeyHandler
  shortcuts remain the automatic fallback. The submenu also distinguishes
  disabled, missing, ready-to-start, and running states and links directly to
  RTSS Settings.
- **Controller Mappings:** hold Y on the main page to open the Quick Settings
  mapping reference. Its final **Set Controller Mappings** row opens the full
  editor when changes are needed. The former main-page Controller Layout row
  remains removed.
- **Open Keyboard:** closes Quick Settings before presenting the Windows touch
  keyboard.
- **Mouse Mode:** applies the controller pointer and mappings without holding
  View/Back, including in shell mode. The choice is saved immediately.
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
- **Settings:** includes Windows Settings and the full SteamShell Settings
  editor. The former Reload Settings row has been removed.
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
- **Controller + Cursor:** controller mouse capability and speed, cursor hiding,
  and event-based left/right mouse parking. Hold Y on the main page for the
  Controller Mappings submenu and select **Set Controller Mappings** to edit.
- **Focus + Window Engine:** Steam refocus, game foreground assistance, AlwaysFocus support, coordinated window
  management, and the session focus pause.
- **RTSS + Performance:** integration enable, overlay/limiter control modes, the configured custom frame cap, and whether the last Frame Limit selection is restored when RTSS starts.

Quick Menu changes are written to `SteamShellSettings.ini` immediately. Startup-only rows are marked `NEXT BOOT`.
The Settings landing page also opens Windows Settings or the full SteamShell
Settings editor.

The full Settings editor has nine pages: **General**, **Startup & Splash**,
**Startup Programs**, **Controller & Cursor**, **Steam**, **Focus & Windows**,
**RTSS & Performance**, **Launcher Cleanup** and **Advanced & Logging**. The
Steam page holds the three Steam shortcuts, the Big Picture window title and the
View button's own action; it is new, and before it existed the `[Steam]` section
could only be changed by editing the INI.

Shell registration lives at the top of **Advanced & Logging** — installing or
registering SteamShell as the shell, repairing a managed installation, and
**Permanently Restore Explorer**, which is the escape hatch if the machine is
misbehaving and you want your desktop back.

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

The controller-facing actions needed during a session remain reachable from
the Quick Menu:

| Action | Where |
|---|---|
| Open Settings | Settings ▸ Open Full Settings Editor |
| Open Windows Settings | Settings ▸ Windows Settings |
| Open Keyboard | main page ▸ Open Keyboard |
| Toggle persistent controller pointer | main page ▸ Mouse Mode |
| View Controller Mappings | hold Y on the main page |
| Set Controller Mappings | mapping submenu ▸ Set Controller Mappings |
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

- Quick Menu ▸ System ▸ **Return to SteamShell**, or the tray equivalent. This
  launches Steam Big Picture when needed and then restores SteamShell
  presentation; it does not intentionally enter recovery merely because Steam
  was closed on the desktop.
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
arguments already entered after it. Every entry launches directly from the normal-integrity main shell; the
verified standard-token route remains available during the temporary elevated Setup session. The full editor applies runtime-compatible changes when **Save & Apply** is
selected and identifies options that require the next launch.
The RTSS shortcut rows include **Record** buttons that capture a key combination and convert it to the required
AutoHotkey send syntax. Advanced & Logging includes the common focus, game-assist, reload, INI, and live-log
actions; the separate Diagnostics Panel remains available for timed overrides and detailed runtime status.

Advanced & Logging also provides **Install SteamShell as Shell**, **Repair SteamShell Installation**,
**Register Current EXE as Shell**, and **Permanently Restore Explorer**.
These actions use the same compiled main EXE—there is no service, updater, or separate recovery executable. The
only companion binary is the embedded, narrowly scoped elevated window helper described above.
The managed Install action places SteamShell under `%ProgramFiles%\SteamShell`, stores writable settings and logs
under `%ProgramData%\SteamShell`, and applies Modify access only to that data tree for the interactive user.
Register Current EXE instead writes the current compiled EXE's exact path directly to the current-user Winlogon
`Shell` value, matching a portable `.reg` workflow. That EXE must not be moved or deleted until Explorer is restored.

The same area provides configuration recovery and diagnostics:

- **Health Check** validates Steam, the INI/schema, shell registration, Explorer/taskbar, startup paths, RTSS,
  external-launch capability and process integrity, controller detection/mapping conflicts, Launcher Cleanup
  safety, and desktop recovery. It also reports the **installation record** — see below. The window, the report
  format, **Refresh** and **Copy Report** are shared with SteamShell-XFE, so a report from either product reads
  the same; only the checks themselves differ.

  Its four controller rows — **Controller**, **Input backend**, **RawInput** and
  **Controller mappings** — are also shared, so both products word them
  identically. **Input backend** reads `Setting: <configured>. Active:
  <backend>` — the preference and the backend actually serving reads, side by
  side, which is the distinction that matters when `Backend=Auto` picked
  something other than what you expected. The XInput slot is shown for XInput
  only, 1-based, with the configured slot beside it when they differ; it used to
  be printed beside a RawInput reading, where the number was whatever XInput had
  last left behind.
- **Export Diagnostic ZIP** creates a sanitized bundle on the desktop containing the health report, system
  information, settings, and recent log lines.
- **Create Settings Backup**, **Export Settings**, and **Import / Restore** preserve portable configurations.
- **Restore Category Defaults** and **Reset All Settings** create backups before changing anything.
- **Restart in Safe Mode** keeps Explorer available and disables shell automation for the current session.
- **Setup Assistant** connects detected and visibly displayed Steam/RTSS paths,
  controller testing, Health Check, UAC controls, integrated Windows Auto-Login,
  standard/custom/portable deployment, optional shell registration, and recovery
  without a separate installer. Its monitor-bounded content has a vertical
  scrollbar for television DPI scaling.

The Focus and Launcher Cleanup categories use executable-list editors rather than raw pipe-separated text.
Launcher Cleanup includes its background-helper list and a read-only preview of currently running cleanup targets.
Controller & Cursor includes a live controller test; inputs are captured instead of forwarded through mappings,
and a three-second centered-stick sample can calculate and apply a conservative deadzone.

It also chooses the **input backend**, and this is what makes a non-XInput
controller usable at all. `[Controller] Backend` is `Auto` by default: RawInput
is read whenever HID reports are arriving and XInput otherwise, so a controller
XInput already handles is unaffected and keeps using XInput. A controller XInput
cannot see — a pad in DirectInput mode is not an XInput device — previously left
SteamShell with no input whatsoever, on a machine where SteamShell has replaced
the shell and there is no taskbar to fall back to.

RawInput reaches any HID gamepad, but the built-in layout only decodes 16-byte
reports. **Learn Controller** teaches it any other pad: it captures a neutral
baseline, filters bits that jitter at rest, and prompts for each button, D-pad
direction, stick axis and trigger. Profiles are stored beside the settings file
as `<settings>-Controllers.ini`, keyed by VID/PID, and are validated against the
saved report length before use. The wizard is reachable from Settings and from
the notification-area menu — deliberately both, because the user who needs it is
the one whose controller does not work yet.

Its undo is reachable from all three: **Settings → Controller & Cursor → Delete
Learned Profile**, the notification-area menu, and `Ctrl+Alt+Shift+D`. Three
routes because a profile that learned an axis wrongly does not simply fail to
help — it reads as a stick held over, so the pointer runs off the screen and the
controller becomes the thing you cannot use to reach the fix. The keyboard chord
is the one that works when the pointer has already gone. Deleting restores the
built-in layout and reloads.

The wizard speaks plainly — "Got it — the A button. Let go." rather than the
byte and bit it matched. The byte, mask and neutral value still go to the log,
where they are what makes a misbehaving pad diagnosable.

It does **not** ask for the Guide/Xbox button. Windows usually swallows that
press before it reaches the HID report, and when it does not, it opens Game Bar
over the wizard and takes the foreground away mid-mapping. Pads that report the
Guide bit over XInput still map it to `Y.Short`, and profiles learned before this
keep decoding theirs.

Anything held during the two "hands off" countdowns is recorded as resting noise
and then ignored for the rest of the session — that is what keeps stick jitter
and gyro drift out of the button steps. If a press is being swallowed for that
reason the log now says so by name instead of appearing to ignore the pad.

A trigger is never matched against a byte that moves on its own. A stick is saved
by resting at its centre, which a motion sensor does not; a trigger legitimately
rests at one end, so nothing downstream can catch that mistake. Where the only
candidates are motion bytes the step is skipped and the rest of the profile is
kept, rather than binding a trigger to a gyro and leaving the pointer running
across the screen.

The profile is written in one staged commit, so it is either the profile just
learned or the one that was there before — never half of each.

While the wizard is open the controller poll stands down entirely. It reads the
pad itself, and every button it asks for otherwise means something: L3+R3 is the
Quick Menu chord, and the D-pad would move focus between the wizard's own
buttons while it is asking for a D-pad direction.

`[Controller] RawInputProbe` logs raw HID reports for diagnosis, and
`DiagnosticLogging` logs every XInput slot on change. Both are off by default and
neither writes to the log when off.

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

SteamShell can install itself for the current Windows user. A new settings file has
`[Setup] SetupState=Pending`, so the first launch starts an Explorer-backed Setup Mode: Steam, the splash, desktop
blackout, taskbar hiding, startup programs, and focus/window automation remain off until setup is completed. An
existing schema-16-or-earlier settings file migrates directly to `Complete` so an upgrade does not unexpectedly
replace a working sign-in with the wizard.

The assistant offers three layouts:

- **Standard (recommended):** `%ProgramFiles%\SteamShell\SteamShell.exe`, protected component space under the
  same program directory, and writable settings/logs/backups under `%ProgramData%\SteamShell`.
- **Use current location:** leaves `SteamShell.exe` where it is and creates a portable `SteamShell` sidecar with
  `SteamShellSettings.ini`, `logs`, `backups`, and the component `bin` directory.
- **Choose another location:** copies the EXE to a selected directory. With Portable selected it uses the sidecar;
  otherwise it uses ProgramData for writable data.

Setup stages and verifies the EXE, preserves an existing target configuration during repair, migrates the current
configuration into a new target, records `InProgress`, and writes `Complete` only after the selected deployment and
optional shell registration finish. Shell registration remains an explicit checkbox, saves the previous per-user
shell value, and creates an emergency Restore Windows Desktop shortcut. Portable shell registration warns when the
chosen executable is on removable, network, or temporary storage and reminds the user that its directory must be
trusted and permanent.

The Applications section first honors an existing valid selection, then checks
Steam and RTSS beneath both Program Files directories; Steam's registered Valve
install location is also considered. Both resulting paths remain visible in
read-only fields, and Apply refuses to continue without a valid `Steam.exe`.

To upgrade an existing sidecar-based portable installation, first use its tray
menu to **Exit SteamShell**, then launch the new verified EXE from another
directory. In Setup Assistant choose **Choose another location**, browse to the
directory containing the installed `SteamShell.exe`, and select **Portable**.
The summary identifies the existing portable installation. Apply stages and
replaces the main EXE, preserves `SteamShell\SteamShellSettings.ini`, extracts
and version-verifies the embedded helper through a temporary file, and replaces
`SteamShell\bin\SteamShell-Helper.exe`. The old process must be stopped because
Windows does not permit an executing helper binary to be replaced. Once every
target verification succeeds, SteamShell permanently deletes only the
pending/in-progress `SteamShell` sidecar beside the separate updater EXE and
then exits the updater. It will not delete the target installation sidecar, a
completed source configuration, a link/junction, or a source folder containing
the selected target.

The final owned dialog offers **Restart Now** and **Restart Later**. Restart Now
requests an immediate Windows reboot; Restart Later leaves reboot timing to the
user. The dialog identifies the reboot as optional when shell registration was
not changed. A successful upgrade closes the updater after either selection
because the installed copy is now authoritative.

The assistant calculates its initial client height from the selected monitor's
physical work area and effective DPI. It uses no more than 80% of that work area,
caps the logical client height at 620 pixels, measures the hidden outer window,
and reduces it again if non-client scaling would cross an 88% safety ceiling.
The vertical scrollbar keeps every action reachable at the smaller size.

**Configure Auto-Login** opens an owned credential dialog during an elevated
Setup session. SteamShell asks Windows to validate the user/domain/password,
stores the password as Windows' protected `DefaultPassword` LSA secret, and only
then enables `AutoAdminLogon`. The password is never written to
`SteamShellSettings.ini`, a log, or a child-process command line. Disabling the
feature turns off `AutoAdminLogon`, removes any plaintext fallback value, and
deletes the LSA secret. Automatic login still gives anyone with physical access
the configured account, and another administrator can retrieve LSA secrets, so
it is intended only for a physically secured gaming PC.

The main application stays at normal integrity after Setup. The independently configurable elevated helper owns
controller input and coordinated geometry for administrator windows; optional privileged maintenance operations
fail cleanly or ask for approval when required.

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

`/restore` and `/uninstall` both start a verified Explorer desktop and deliberately leave the SteamShell folder
and INI in place, so recovery never deletes user data. They differ in what they register as the next sign-in shell:

- `/restore` is the emergency path. It always registers `explorer.exe`. When a session is already broken, a
  known-good shell beats a faithful one, so this mode never reinstates anything else.
- `/uninstall` is the deliberate path. It puts back the shell that was registered before SteamShell took over,
  recorded at install time in `HKCU\Software\SteamShell\PreviousShell`. That value is only used when it is
  verifiable: it must exist on disk and must not itself point at SteamShell, otherwise `explorer.exe` is kept.
  On a normal machine the recorded value *is* `explorer.exe`, so the two modes behave identically; the difference
  only shows up if you were running some other custom shell before installing SteamShell.

If SteamShell is forcibly ended, open Task Manager with Ctrl+Shift+Esc, choose **Run new task**, and run:

```text
%ProgramFiles%\SteamShell\SteamShell.exe /restore
```

If Steam itself cannot start, SteamShell displays a recovery window with Retry Steam, Open Settings, and Restore
Desktop. The D-pad selects an action and A activates it.

`/safe` does not change the saved INI or permanent shell registration. It starts Explorer, skips Steam and startup
programs, disables the splash, cursor parking/hiding, window/focus automation, and Launcher Cleanup, then opens
Full Settings. Reloading the INI during that session cannot re-enable the disabled modules.

`/selftest` runs parser, schema, list-normalization, Quick Menu ordering, startup-command, and process-time CPU
calculation invariants without starting the normal shell session.

## Build validation

`Build-SteamShell.ps1` is the only build script and produces all three
binaries. It runs **both** validators — `Validate-SteamShell.ps1` and
`Validate-SteamShell-XFE.ps1` — then validates and compiles
`SteamShell-Helper.ahk` and verifies helper version 2.0.1.1, validates and
compiles `SteamShell-XFE.ahk` and verifies version 2.0.1.0, and finally
validates and compiles `SteamShell.ahk` with both payloads embedded, verifying
the published executable reports 2.0.1.0.

Everything it needs is in this folder, which is what makes locking a release a
copy of one directory.
The static validator checks duplicate function declarations, embedded/sample INI schema parity, required recovery
and window-engine functions, Settings-editor and Quick Menu schema bindings, named UI/timer callbacks, Quick Menu
row dispatch, ampersand-safe Settings headings, the controller-deadzone migration, desktop-restore linkage,
whitespace hygiene, one full-window scanner, and one scheduled focus-policy call. It also rejects the retired WMI
process query and legacy focus entry points.

From the workspace root, double-click `Run-SteamShellValidation.cmd`. It runs
the whole gate: AutoHotkey syntax, both validators, the shared-parity check, the
full build, then negative tests that break each of the three sources in turn and
lock each freshness-checked output to prove a stale artefact is refused. Only
after every check passes does it publish `SteamShell.exe` to the root
`current\`. Failures return a non-zero exit code and leave the previous
`current\` untouched.

Only the installer is published. It carries both payloads and installs either
product through Setup Assistant, so a loose `SteamShell-XFE.exe` beside it would
only invite a hand-copied install with no logon task, no writable companion
directory, and no dormant helper.

## RTSS setup

SteamShell pre-fills RTSS's standard executable path and enables integration by
default. If RTSS is not installed, the Quick Menu reports that setup is required.
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
OverlayControlMode=Separate
OverlayToggleShortcut=^+o       ; Ctrl+Shift+O
FrameLimiterControlMode=Separate
PresetFrameCap=158             ; Named Preset entry in the live cycle
CustomFrameCap=158
RestoreFrameLimitOnStartup=true ; Reapply the last selection once RTSS is running
CustomFrameCapShortcut=^+f      ; Ctrl+Shift+F
```

In shortcut-fallback Toggle mode, the Quick Menu uses `PresetFrameCap` as its
configured FPS label but does not claim the limiter is on or off. With DLL
integration, Preset applies that value directly; `CustomFrameCap` records the
last value adjusted on the Custom FPS row and restores it whenever Custom is
selected again.

### Setting the Frame Limit without running as administrator

`RTSSHooks64.dll` is loaded into whichever process calls it, so the write that
saves a frame cap happens with *that* process's token — and RTSS installs under
Program Files by default. An unelevated SteamShell therefore could not save a
cap, and was not told: the value changed in RTSS's memory, the save failed
silently, and the next read returned the old number. The row reported itself
read-only, which was accurate and left the feature unusable for anyone not
running SteamShell as administrator.

The elevated helper now performs that write, running the same sequence an
elevated SteamShell always did — load the profile, set the frame limit, save,
apply — in the process that holds the right token. SteamShell itself then reads
the value back from RTSS, so the check that decides success still runs in the
ordinary, unelevated process where you can see it fail. **Use the elevated
helper to set the Frame Limit** in Settings → RTSS
(`EnableElevatedFrameCapWrites`, default on) turns it off, and takes effect
immediately rather than at the next sign-in.

This covers **Save Limit to Profile** as well. Per-game profiles live in the
same protected directory, so they had the same silent failure — and worse, they
reported success anyway. A profile save is now verified before it is reported,
and says so plainly when it does not stick.

RTSS's own window follows the change live, because the whole write happens in
one process the way it always did before the split.

This needs the elevated helper, so it applies to Shell installs only. Two things
it deliberately will not do:

- **It will not write an RTSS outside Program Files.** It checks that the
  configured `[RTSS] Path` really names `RTSS.exe`, that the real directory sits
  under a Program Files location read from the registry, and that `Profiles\`
  resolves to somewhere still inside that install. Anything else is refused —
  which costs nothing, because an RTSS you can write to is one SteamShell can
  already write to without the helper.
- **It will not accept a profile name it cannot corroborate.** A per-game name
  has to look like a plain executable name *and* match a process that is running
  at that moment, or the helper refuses it. SteamShell knows which game the
  Quick Menu was opened over and the helper does not, so the name is sent — and
  then checked against reality rather than trusted.

### Restoring the Frame Limit

RTSS keeps only part of the selection across a restart. The FPS number lives in
its global profile and is persisted, but the limiter on/off state is a runtime
flag in RTSS's shared memory, and "Custom" is a SteamShell concept RTSS never
sees. On its own, that means every reboot came back reading **OFF**, with the
first Right press landing on 30 FPS rather than your own cap.

SteamShell now records what it applied in `[RTSS] LastFrameCapMode` and
`LastFrameCapFps` — including while Off, where the number is kept for the same
reason the Off entry never writes `0` — and reapplies it once RTSS is running.
**Restore the last Frame Limit selection when RTSS starts** in Settings → RTSS
(`RestoreFrameLimitOnStartup`, default on) controls this.

Two deliberate limits:

- **It never starts RTSS.** Reapplying a cap is not a reason to launch a program
  you did not ask for. SteamShell polls for up to two minutes after startup
  instead, which is also what makes it work when RTSS arrives later through Steam
  or a startup entry.
- **It only writes RTSS's profile when RTSS does not already agree.** That write
  is a real edit to RTSS's own configuration, so it does not happen on every boot
  when RTSS kept the value by itself.

**The limiter is re-enabled even when the FPS cannot be written.** These are two
different mechanisms: the FPS is a property of RTSS's Global profile on disk,
which a standard user cannot save against a stock Program Files install, while
the limiter flag goes through RTSS's shared memory and works either way. The
restore used to give up on the flag when the FPS write failed, which made the
limiter's survival depend on whether RTSS happened to already hold your number.
It now re-enables the limiter regardless and logs which half was restored — you
will be capping at RTSS's own value rather than yours, and the recorded selection
is kept so the next boot still tries for it. See *Setting the Frame Limit without
running as administrator* above for the remedies.

This needs `UseDllIntegration=true`. The shortcut fallback can only toggle the
limiter, not select a specific FPS; with DLL integration off, SteamShell logs
that and skips the restore rather than waiting. The outcome is always recorded in
`SteamShell.log` as `Restored the last Frame Limit selection: …`.

For explicit limiter controls, configure matching enable and disable actions:

```ini
FrameLimiterControlMode=Separate
PresetFrameCap=117
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

The build script creates `dist\SteamShell.exe` and embeds both the verified
helper payload and `assets\SteamShell.ico` (`-IconPath` still accepts an
override). The intermediate `build\SteamShell-Helper.exe` is not a separate
distribution requirement; the main EXE extracts it during Setup or first normal
startup.
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

That re-assertion is now shared with SteamShell-XFE, which had no `TaskbarCreated` handling of its own and lost
its icon permanently whenever Explorer restarted for any reason.

### The installation record

`[Setup]` records what this installation is and where it lives: `Product`, `InstallationMode`, `InstallDirectory`
and `DataDirectory`, alongside `SetupState` and `SetupVersion`. The registry key under `HKCU\Software\SteamShell`
carries the same facts for a managed install and is the better source while it exists — but it is exactly what
does not survive a move. Copy an installation to another PC and the registry is empty while the settings file
still describes the old machine, so the file is the only record able to notice.

At every start the record is compared against where SteamShell is actually running. A mismatch is logged, shown
on the tray tooltip, offered as a tray entry that opens Setup Assistant, and reported in Health Check.

**It never decides anything.** `SetupAssistantRequired()` determines whether the shell runtime starts, and the
comparison does not reach it. A stale path in a settings file must not be able to leave a machine sitting in
Setup with no shell — which would be far worse than the wrong path it was reporting. Startup separately trusts
the registry's `DataPath` only when `InstalledPath` matches the running executable, so a portable or test copy
cannot adopt an installed shell's settings.
