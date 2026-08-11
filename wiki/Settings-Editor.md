# Settings Editor
The full desktop window, opened with `Ctrl+Alt+Shift+S` or from the tray. Nine
categories covering every key the INI holds.

It is navigable with a controller as well as a mouse — the hint line under the
title says how: **D-pad** navigates, **A** activates, **LT/RT** switch category,
the **right stick** drives the pointer, **RB** is a pointer action, and **Y**
saves.

**Save & Apply** writes the INI through a staged replacement — the batch either
lands whole or leaves the file untouched, so a half-written settings file is
never left behind. **Reload INI** discards unsaved edits and re-reads from disk.

## General

Core shell behaviour and which modules appear in the Quick Menu, plus the accent colour and the two controller hold times.

![Settings editor General page](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/settings-general.png)

## Startup & Splash

The optional elevated helper, the Steam executable, and the boot splash — black, timed, or a video played through MPV.

![Settings editor Startup and Splash page](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/settings-startup-splash.png)

## Startup Programs

Up to twenty standard-user programs launched with the shell, with a delay, a gap between launches, and a window mode.

![Settings editor Startup Programs page](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/settings-startup-programs.png)

## Controller & Cursor

Mouse mode, deadzone, speed and scrolling, cursor hiding, and the controller backend.

![Settings editor Controller and Cursor page](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/settings-controller-cursor.png)

## Steam

What the View/Back button does on a press that did not reach a mapping, plus the Steam menu, Quick Access and in-game overlay shortcuts.

![Settings editor Steam page showing Steam Menu, Quick Access and overlay shortcuts and View button tap and hold actions](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/settings-steam.png)

## Focus & Windows

The window engine: what counts as a game, how hard the shell works to keep it in front, and the exclusion lists.

![Settings editor Focus and Windows page](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/settings-focus-windows.png)

## RTSS & Performance

RTSS paths, shortcuts, DLL integration and the frame-cap behaviour.

![Settings editor RTSS and Performance page](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/settings-rtss-performance.png)

## Launcher Cleanup

Which launcher processes get closed after a game exits, which are protected, and how gracefully.

![Settings editor Launcher Cleanup page](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/settings-launcher-cleanup.png)

## Advanced & Logging

Game-log detail, log rotation, and the two diagnostic switches — XInput slot logging and the RawInput probe.

![Settings editor Advanced and Logging page](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/settings-advanced-logging.png)
