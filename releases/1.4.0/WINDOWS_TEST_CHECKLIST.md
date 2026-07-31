# SteamShell 1.4 Windows Test Checklist

This development workspace cannot execute AutoHotkey, XInput, Windows display/audio APIs, or RTSS. Test the
uncompiled script on the HTPC before replacing the current shell executable.

## Safe first launch

1. Keep the existing working `SteamShell.exe` available under a different filename.
2. Keep a keyboard connected and verify `Ctrl+Alt+Shift+E` still restores the desktop.
3. Run `SteamShell.ahk` from a normal Explorer desktop before installing it as the Winlogon shell.
4. Run the compiled EXE with `/selftest` and confirm all core invariant checks pass.
5. Open Quick Menu with `Ctrl+Alt+Shift+Q`.
6. Keep Task Manager available during initial shell testing. Hard-crash recovery is the same EXE:
   `%LocalAppData%\SteamShell\SteamShell.exe /restore`.

## Single-EXE installation and recovery

- From a normal Explorer desktop, compile SteamShell and open Full Settings.
- Select Install SteamShell as Shell and confirm the EXE is copied to
  `%LocalAppData%\SteamShell\SteamShell.exe`.
- Confirm the emergency Restore Windows Desktop shortcut appears in the current user's Start menu.
- Confirm the existing customized INI is copied only when the installed folder does not already contain one.
- Read the current-user Winlogon `Shell` value and confirm it contains the quoted installed EXE path.
- Select Repair SteamShell Installation and confirm it succeeds without changing existing settings.
- Run the installed EXE with `/restore`; confirm Explorer and a visible taskbar appear and remain registered for
  the next sign-in.
- Reinstall, force-end SteamShell, use Task Manager > Run new task to execute `/restore`, and confirm the normal
  desktop returns.
- Confirm setup and normal SteamShell operation do not request elevation.

## Settings migration

- Start once with a copy of an older customized `SteamShellSettings.ini`.
- Confirm all existing values remain unchanged, including deliberately blank values.
- Confirm an existing UTF-8 INI is backed up as `.pre-unicode.bak`, converted to UTF-16, and still retains Unicode
  paths and deliberately blank RTSS shortcuts.
- Confirm missing current options and `[SteamShell] SettingsSchemaVersion=3` are added.
- Confirm `SteamShellSettings.ini.pre-schema-0.bak` contains the original file.
- Confirm an old default `Start.Short=Builtin:None` and `Start.Long=Builtin:None` migrate to
  `Builtin:StartMenu` and `Builtin:Explorer`.
- Confirm custom Start short/long mappings remain unchanged during migration.
- Confirm `EnableMouseParkEveryRefocus` transfers to `EnableMouseParkOnFocusChange` only when the replacement is
  absent, then is removed.
- Confirm retired `FrameCapOptions`, `FrameCap0Shortcut`, and numbered `FrameCap...Shortcut` entries are removed.
- Start SteamShell again and confirm the INI and backup are not rewritten when no migration is needed.
- Make the settings file read-only, attempt a Settings-editor save, and confirm the original file remains intact and
  the editor reports the failure.

## Quick Menu settings

- Open Quick Menu > Settings and confirm General, Controller, Focus, and RTSS categories fit without clipping.
- Toggle a persistent option, close and reopen SteamShell, and confirm the value remains changed.
- Confirm startup-only rows show `NEXT BOOT`.
- Adjust controller mouse speed, cursor hide delay, and the custom frame cap with left/right.
- Disable auto-hide while the cursor is hidden and confirm the cursor becomes visible.
- Open Controller Mapping and Full Settings Editor from the Quick Menu.
- Press B in a Settings category to return to the Settings page, then press B again to return to the main page.

## Full Settings editor

- Open the editor with `Ctrl+Alt+Shift+S` and confirm all eight categories switch without overlapping controls.
- Confirm headings and category rows display literal ampersands in `Startup & Splash`, `Controller & Cursor`,
  `Focus & Windows`, `RTSS & Performance`, and `Advanced & Logging`.
- At the HTPC's Windows scaling level, confirm the editor fits inside the monitor work area and the Save, Reload,
  and Close buttons remain visible.
- On a monitor with additional vertical space, confirm the editor opens taller than the former 620-pixel limit.
  Drag its lower resize edge up and down and confirm the category list, content viewport, scrollbar, status line,
  divider, and footer buttons resize together without overlap. Confirm the window width remains fixed.
- Drag and page through the native scrollbar in long categories, then use the mouse wheel; confirm both remain
  synchronized and the scrollbar disappears in categories whose content already fits.
- Repeat scrollbar dragging and mouse-wheel scrolling at 100%, 125%, and 150% display scaling; confirm controls
  do not smear, trail, overlap, or leave stale pixels behind.
- In Launcher Cleanup, confirm the `Launcher EXEs to close` and `Never close these EXEs` lists display
  side by side without overlap.
- Browse for an EXE in each list, confirm duplicate additions are rejected, remove an entry, save, and verify
  the INI values are written as pipe-separated filenames without full paths.
- In Startup Programs, confirm the mouse wheel over the program list scrolls that list rather than the entire page.
- Use Add Program to select an EXE and confirm it fills the selected empty slot or the next available slot.
- Add optional arguments in the selected-command field, apply them, change rows, and confirm they remain intact.
- Use Browse Selected to replace the EXE and confirm its existing arguments are preserved.
- Remove the selected program, then add another and confirm the newly empty slot is reused.
- Move startup entries up and down, save, and confirm commands remain attached to their new slot numbers.
- Test Launch a harmless program and confirm it starts without waiting for the next boot.
- Test Hidden, Minimized, and Normal startup window modes with disposable programs.
- With the Settings window foreground, confirm D-pad/left-stick navigation automatically reveals and focuses each
  control, left/right adjusts choices and numeric fields, A activates controls, and LB/RB changes categories.
- Confirm the right stick moves the pointer without holding Back. Hold Back and verify the normal configured
  controller mappings—including mapped mouse clicks—work inside Settings and its file picker.
- Select an edit field with A and confirm the Windows touch keyboard opens. Confirm Y saves changes.
- With no pending changes, confirm B closes Settings. With pending changes, confirm B leaves Settings open and
  instructs the user to save or explicitly discard rather than silently losing changes.
- Browse to Steam.exe, mpv.exe, a startup video, and RTSS.exe; cancel each picker once and confirm no value changes.
- Confirm every file picker opens above Settings and remains interactive; Settings should regain always-on-top
  focus only after the picker is accepted or cancelled, without moving or resizing the Settings window.
- Configure a startup-program slot with an executable plus arguments, change slots, return to it, and confirm the
  command remains intact.
- Save, reopen the editor, and confirm edited values and startup-program commands persisted.
- Enter an invalid numeric value and confirm Save identifies the field and does not partially write other changes.
- Make an unsaved change and confirm Close allows saving, discarding with No, or cancelling.
- Confirm the save/discard prompt stays centered above Settings, never appears behind it, and neither window
  maximizes or expands to fill the screen.
- While that prompt is open, confirm D-pad/left-stick changes the selected response, A accepts it, and B cancels.
- Confirm Reload INI asks before discarding unsaved changes.
- Record each RTSS overlay and frame-limiter shortcut, confirm the friendly chord is reported, then save and verify
  the corresponding AutoHotkey send string is written to the INI.
- Confirm Pause / Resume Focus, Run Game Assist, Reload Runtime, Open INI in Notepad, Open Live Log, Diagnostics
  Panel, Restore Category Defaults, Controller Mapping, and AlwaysFocus Manager
  remain reachable.
- In AlwaysFocus Manager, add a visible running application with `Add Selected`, then browse to a different EXE
  with `Browse / Add EXE`; confirm both appear as filenames without full paths.
- Confirm duplicate AlwaysFocus additions are rejected, `Remove Selected` updates the session list, and
  `Write to INI` persists the displayed list as a pipe-separated value.
- Open AlwaysFocus Manager from SteamShell Settings and confirm its EXE picker appears in front of both windows.
- In Focus & Windows, add and remove an EXE from `Never center or maximize these EXEs`, then save and confirm the
  pipe-separated `WindowManagement.ExcludeExeList` value.
- In Launcher Cleanup, add a Background Helper EXE and use Preview Running Cleanup Targets; confirm the preview
  does not close anything.
- Customize the Quick Menu order, hide one optional row, save, and confirm the menu updates. Confirm Settings and
  System cannot be hidden.
- Create and export a settings backup, import it again, and confirm the previous INI was backed up first.
- Reset one category and confirm unrelated categories remain unchanged. Reset all settings using a disposable INI
  and confirm a pre-reset backup is retained.
- Run Health Check with one intentionally invalid startup path and confirm it reports a warning.
- Export a diagnostic ZIP and confirm it contains HealthCheck, SystemInfo, sanitized settings, and recent log files.
- Open Setup Assistant and confirm Steam/RTSS pickers, Controller Test, Health Check, portable mode, and installation
  actions stay in front and remain usable.

## Controller

- Holding L3 + R3 for about 0.7 seconds opens and closes Quick Menu.
- Holding Back and tapping Start opens the Windows Start menu.
- Holding Back and holding Start past `ControllerChordHoldMs` opens File Explorer without also opening Start.
- The six-button fallback chord opens Full Settings without also opening Quick Menu.
- D-pad and left stick navigate.
- A selects and B closes/goes back.
- Existing Back + button mappings still work.
- Disable Controller Mouse Mode while leaving Quick Menu enabled. Confirm L3+R3 and Quick Menu navigation still
  work, but Back mappings, stick mouse movement, scrolling, and D-pad passthrough do not.
- Disconnect and reconnect the controller while holding a button. Confirm reconnecting does not fire a stale short
  press, long press, Task Switcher close, or Quick Menu action.
- Open Controller Test and confirm buttons, triggers, and raw axes update without sending mapped actions elsewhere.
- Leave the sticks untouched for the three-second center sample, apply the suggested deadzone, and confirm the new
  value is written to the INI and reflected in Full Settings.

## Focus

- Opening Quick Menu over Steam does not immediately lose focus.
- Closing it restores Steam.
- Opening it over a borderless game and choosing Return to Game restores the game.
- Focus Assistance can be paused and resumed.
- Task Switcher lists visible application windows but omits SteamShell, the desktop, and taskbars.
- Selecting a task activates it and the main menu reports `LOCKED`.
- Pressing X on a task requests that window to close and refreshes the task list.
- An application with unsaved work can show its normal save/close confirmation; the Quick Menu gets out of its
  way and the process is not force-terminated.
- Holding X for about 1.2 seconds force-closes the selected process without also sending the normal close action.
- Verify the force-close test with a disposable application: unsaved work can be lost and all windows belonging
  to that process can close.
- Pressing X on Back, paging, or Release Focus Lock rows does nothing.
- Confirm Steam, Explorer, SteamShell, and Windows shell-host processes cannot be force-closed from Task Switcher.
- Another unrelated application does not permanently steal focus from the selected task.
- Dialogs belonging to the selected application remain usable.
- Release Focus Lock, Return to Game, and Return to Steam each clear the task lock.
- Closing the selected window clears the task lock automatically.

## Desktop restoration

- During a deliberately slow or failed Steam launch, background `explorer.exe` may run for Game Bar support, but
  the taskbar and desktop never replace SteamShell merely because the startup-warning delay expires.
- Confirm the log records a single startup warning after `SteamStartupGraceMs` while automatic restoration remains
  disarmed until `steam.exe` has actually been observed.
- Configure an invalid Steam path and confirm the recovery window appears after the splash, remains above other
  windows, and offers Retry Steam, Open Settings, and Restore Desktop.
- In that recovery window, confirm D-pad changes the focused action and A activates it.
- After Steam has been observed running, a brief `steam.exe` restart shorter than `SteamExitConfirmMs` does not
  restore the desktop.
- Exit Steam to Desktop asks Steam to close gracefully.
- Explorer, the taskbar, and normal desktop startup complete exactly as they do after exiting Steam directly.
- If Steam refuses to close, SteamShell remains active and does not expose a partially restored desktop.
- Exiting Steam directly and using the Quick Menu both restore a visible `Shell_TrayWnd` taskbar.
- Desktop restoration verifies the shell registry write, retries Explorer, and logs whether its taskbar appeared.
- Simulate one failed Explorer launch and confirm SteamShell retries. Simulate all restore attempts failing and
  confirm SteamShell remains running with a Retry/Cancel prompt rather than exiting into a blank desktop.
- A normal session restore puts the configured SteamShell value back for the next sign-in after the handoff completes.
- Disable the startup splash and confirm window management becomes active after startup rather than remaining
  permanently disarmed.
- Run the compiled EXE with `/safe`; confirm Explorer and Settings open, Steam/startup programs do not launch, the
  taskbar remains visible, and reloading settings does not reactivate focus, window, cursor, or cleanup automation.

## Audio

- Current default playback-device name appears.
- Left/right switches among active playback devices.
- Volume changes in 5% steps.
- Mute toggles.

If endpoint switching reports an error, disable `[AudioQuickControls]` temporarily and retain the log. Default
endpoint selection uses Windows' PolicyConfig interface and needs confirmation on the target Windows build.

## Display

- Current resolution and refresh rate are correct.
- Display + HDR opens a paginated list of modes reported for the primary display.
- Opening the list highlights the current resolution and refresh rate.
- A changed mode displays the keep countdown.
- Selecting the marked current mode again keeps it.
- Ignoring the prompt restores the old mode after 15 seconds.
- Win+Alt+B toggles HDR on the intended display.

## RTSS

- Configure RTSS HotkeyHandler first.
- Confirm the RTSS + Frame Limiter submenu remains visible and reports SETUP REQUIRED before configuration.
- Confirm the generated settings prefill the standard RTSS path and `OverlayToggleShortcut=^+o` (Ctrl+Shift+O).
- Enable `[RTSS] EnableIntegration=true`.
- Confirm the configured overlay shortcut works outside SteamShell.
- In Toggle mode, confirm Quick Menu sends Ctrl+Shift+O, labels the action TOGGLE, and does not claim the overlay
  itself is on or off.
- Confirm the RTSS submenu reports RTSS READY or RTSS RUNNING for the process state.
- In Separate mode, confirm Overlay On sends Ctrl+Shift+1 and Overlay Off sends Ctrl+Shift+2.
- Leave one Separate-mode shortcut blank and confirm the main menu reports OVERLAY INCOMPLETE.
- In limiter Toggle mode, confirm Ctrl+Shift+F is sent and the menu says TOGGLE without claiming an on/off state.
- Set an unusual `CustomFrameCap` value (for example 117), reload settings, and confirm `117 FPS` appears beside
  the toggle action.
- In limiter Separate mode, confirm Frame Limiter On sends Ctrl+Shift+5 and Frame Limiter Off sends Ctrl+Shift+6.
- Leave one limiter Separate-mode shortcut blank and confirm the main menu reports LIMITER INCOMPLETE.
- Confirm old numbered frame-cap preset fields have no effect.
- Verify hiding the OSD does not disable the limiter.

## Visuals and logging

- Control Panel, mapping window, log window, and shortcut recorder use readable native Windows styling.
- Record Win+G and Alt+F4 shortcuts and confirm the recorder captures them without opening Game Bar or closing the
  recorder/application behind it.
- Quick Menu fits at the HTPC's Windows scaling setting and centers on the display containing Steam or the active game.
- With `EnableMouseParkOnBoot=true`, the pointer is parked beyond the right edge once during startup.
- Physical mouse movement restores the cursor; it hides again after `MouseHideDelay`.
- Opening or closing the Quick Menu, selecting a Task Switcher window, or moving between Steam and a game parks the
  pointer once after the new window receives focus.
- Repeated focus polling while the same window is already active does not move the pointer or reset the idle timer.
- With only Steam Big Picture idle, Windows display-off and automatic sleep timers still expire normally.
- The compact main page opens Audio, Display, RTSS, Task Switcher, and System submenus without clipping.
- No bottom-corner SteamShell notification overlay appears.
- Controller Layout reflects the mappings currently loaded from the INI.
- Action and warning messages remain available in `SteamShell.log`.
- Leave game-score logging disabled and confirm operational startup, recovery, and desktop-restore messages still
  appear in `SteamShell.log`.

## Compile

After the script passes the checks above:

```powershell
powershell -ExecutionPolicy Bypass -File .\Build-SteamShell.ps1
```

The compiled executable is written to `dist\SteamShell.exe`.
