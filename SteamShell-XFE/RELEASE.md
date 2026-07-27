# SteamShell XFE 0.1.14

Released: 2026-07-26

This directory is the locked source release for SteamShell XFE 0.1.14. It
preserves the controller-utility companion selected after iterative Xbox Full
Screen Experience testing. Do not edit this snapshot when later development
resumes; make changes in `SteamShell-XFE/` under a later version.

Build `SteamShell-XFE.ahk` on Windows by double-clicking
`Build-SteamShell-XFE.cmd`. The underlying PowerShell script requires
AutoHotkey v2.0.19 or newer with a 64-bit base, runs the static validator and
AutoHotkey syntax validation, and then compiles `dist\SteamShell-XFE.exe` with
the included icon.

No compiled EXE is stored in this source snapshot. The source, documented
configuration, validation, simulation, build launchers, icon assets, and test
checklist are the authoritative release.

## Release scope

- RawInput-first automatic controller input that remains functional inside Xbox
  FSE, with XInput fallback outside it.
- Persistent empirical controller profiles and the guided controller-learning
  workflow.
- Controller-first Quick Menu and full Settings interface.
- Audio, primary-display resolution, refresh rate, DPI scale, and state-aware
  HDR controls with timed display-mode reversion.
- RTSS Overlay and Frame Limiter state/cap integration through
  `RTSSHooks64.dll`, with shortcut fallback and couch-friendly RTSS startup.
- Context-aware Steam and in-game Overlay actions.
- Task Switcher, optional assist features, startup programs, startup curtain,
  logon task, diagnostics, and recovery hotkeys.
- Notification-area icon with Quick Menu, Settings, Disable/Enable, and Exit.
- Cursor hiding plus default-on parking at startup, on game/fullscreen entry,
  and when returning to Steam.

## 0.1.14 stabilization

- Steam Big Picture remains visible in the Task Switcher when
  `steamwebhelper.exe` publishes it as a tool window.
- The in-game Steam Overlay action sends a timed Shift+Tab chord that games can
  reliably receive; the already-working Steam Ctrl+1/Ctrl+2 path remains
  unchanged.
- Quick Menu Settings toggles write successfully before changing runtime state,
  update full Settings immediately, and persist across restart.
- Low-value System diagnostics were removed from the Quick Menu while remaining
  available in Settings → Advanced and through recovery hotkeys.
- Settings uses the actual visible DPI-scaled outer frame for vertical
  centring, and its compact footer remains inside the monitor work area.
- A newly foreground game/fullscreen-style window parks and hides the cursor by
  default. The delayed action verifies the same window is still foreground and
  excludes Steam, launchers, Xbox FSE, Game Bar, and configured shell overlays.
- The build launcher is double-clickable and preserves build output; the
  PowerShell build reads real exit codes from the AutoHotkey GUI processes.

## Verification status

- The portable Python suite passes all 12 simulation tests, including learned
  controller decoding, change-only reports, layout constraints, and Settings
  overlap checks.
- The source contains no forbidden bare `try WinGetPos(...)` calls; the final
  game-entry parking call uses the required braced ByRef measurement pattern.
- Core controller input, Quick Menu, Settings, and several display/RTSS/tray
  changes were exercised iteratively on the target Windows systems during
  development.
- This release was assembled in an environment without PowerShell, AutoHotkey,
  or Ahk2Exe. Therefore the complete Windows static validator, AutoHotkey syntax
  validation, and compilation must be rerun with the included CMD launcher
  before distributing a compiled EXE. `WINDOWS_TEST_CHECKLIST.md` remains the
  target-system acceptance procedure.

## Known limits

- Windows has no universal “is game” flag. Game-entry parking uses a
  conservative fullscreen-geometry test and the configured shell/launcher
  exclusions.
- The RawInput learner supports byte-aligned buttons, hats, 8-bit axes, and
  unsigned 16-bit little-endian axes. Packed or signed axis layouts may require
  a hand-written profile or future descriptor parsing.
- A shared trigger axis cannot report both triggers independently at once.
- Windows DPI-scale control uses the current DisplayConfig device-info packet
  and intentionally becomes unavailable if Windows rejects it.
- RTSS DLL control requires compatible `RTSSHooks64.dll` exports and the same
  effective access level; the documented shortcut mode remains the fallback.
- Startup video mode requires a user-supplied `mpv.exe` and video file.

## SHA-256

```text
060b53005ae0a0ccfa47cd262f4fa6aa45e9b66e0b62fba6f26b5a90be4b4f11  Build-SteamShell-XFE.cmd
7a90e6c6e34051d84e361527586d566fbede4f85cafd5339d404d89d9c4c0eb6  Build-SteamShell-XFE.ps1
d24ab1c17e42f470dc42d7fbca79c073b80013410c547d7e516bb04efba3931c  README.md
056a920fdb0507b40616caa53a8a7bbc94a02a2571cab9d93da78d02096d8525  SteamShell-XFE.ahk
7b52c72c8354a4a8e11982b09b5ce302ecc24c3ea1801557aad493ac847cd085  SteamShell-XFE_SAMPLE.ini
1b98b4d2cb21a479a545dd36c91020f85334e06d3b2ef0a152080d9ab0c96be0  Test-ControllerProfiles.py
f5959ecc0ec3fc69203a5e475c1dba3dd9259ca00d7bb8ffd930f43c779e24e9  Validate-SteamShell-XFE.ps1
84d9286a97b0400eb5400b839e60aa8e0743fa9dc37180cf1fb294710087144f  WINDOWS_TEST_CHECKLIST.md
2fe6f14f89e2a051e753a767b2da68e16f5666baef11d0252c954c5c69c93002  assets/SteamShell-XFE.ico
c7a85f0e7bc20ec733fc5d9737167cde7965d4def90946353005926b85357005  assets/SteamShell-XFE-icon.png
```
