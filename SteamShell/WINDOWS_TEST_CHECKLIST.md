# SteamShell 1.7.1 Acceptance Test Checklist

This development workspace cannot execute AutoHotkey, XInput, Windows display/audio APIs, or RTSS. Test the
uncompiled script on the HTPC before replacing the current shell executable.

## Safe first launch

1. Keep the existing working `SteamShell.exe` available under a different filename.
2. Keep a keyboard connected and verify `Ctrl+Alt+Shift+E` still restores the desktop.
3. Run `SteamShell.ahk` from a normal Explorer desktop before installing it as the Winlogon shell.
4. Run the compiled EXE with `/selftest` and confirm all core invariant checks pass.
5. Open Quick Menu with `Ctrl+Alt+Shift+Q`. Confirm the menu takes foreground
   focus and arrows, Enter/Space, Backspace, Home/End, and Task Switcher Delete
   operate it without moving Steam Big Picture behind it.
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
- With **Run SteamShell as administrator on startup** enabled, confirm normal startup requests elevation when
  required and Health Check reports administrator privileges.
- From a compiled EXE in a disposable portable path, select Register Current EXE as Shell. Confirm the warning
  displays the exact current path, then verify the current-user Winlogon `Shell` value contains that quoted path.
- Confirm direct registration preserves the previous shell metadata and creates the Restore Windows Desktop
  shortcut without copying the EXE to `%LocalAppData%\SteamShell`.
- Permanently Restore Explorer after the direct-registration test and confirm the Winlogon `Shell` value returns
  to `explorer.exe`.

## Settings migration

- Start once with a copy of an older customized `SteamShellSettings.ini`.
- Confirm all existing values remain unchanged, including deliberately blank values.
- Confirm an existing UTF-8 INI is backed up as `.pre-unicode.bak`, converted to UTF-16, and still retains Unicode
  paths and deliberately blank RTSS shortcuts.
- Confirm missing current options and `[SteamShell] SettingsSchemaVersion=9` are added.
- Confirm `SteamShellSettings.ini.pre-schema-0.bak` contains the original file.
- Confirm an old default `Start.Short=Builtin:None` and `Start.Long=Builtin:None` migrate to
  `Builtin:StartMenu` and `Builtin:Explorer`.
- Confirm custom Start short/long mappings remain unchanged during migration.
- Confirm the former default `ControllerDeadzone=8000` migrates to `4000`, while a different customized deadzone
  remains unchanged.
- Confirm the former default `GameMinScoreToActivate=60` migrates to `55`, while a different customized threshold
  remains unchanged.
- Confirm schema 7's Quick Menu order migrates to the XFE-parity row set, the three new Steam shortcut settings are
  added, applicable hidden-row choices are preserved, and Steam Menu, Steam Quick Access, and Game Bar start visible.
- Confirm `EnableMouseParkEveryRefocus` transfers to `EnableMouseParkOnFocusChange` only when the replacement is
  absent, then is removed.
- Confirm legacy `Timing.WindowCheckInterval`, `Timing.SteamRefocusPollingInterval`, all five `[WindowEngine]`
  tuning keys, `Features.EnableCursorHideOnBoot`, `Features.EnableCursorHideOnRefocus`, and
  `Logging.EnableGameScoreLogging` are removed. Their safe behavior is now internal and
  `Logging.GameLogMode=OFF` is the single logging disable state.
- Confirm retired `FrameCapOptions`, `FrameCap0Shortcut`, and numbered `FrameCap...Shortcut` entries are removed.
- Start SteamShell again and confirm the INI and backup are not rewritten when no migration is needed.
- Make the settings file read-only, attempt a Settings-editor save, and confirm the original file remains intact and
  the editor reports the failure.

## Quick Menu settings

- Confirm the main Quick Menu matches XFE's borderless panel: no DWM outline, caption edge, or backdrop frame.
- Move repeatedly through rows and pages; confirm the existing window repaints in place without a square-corner
  flash, blank frame, visible control-by-control assembly, or whole-window flicker.
- Confirm the XFE-style title, inset continuous selection bar, aligned value column, and left-aligned footer hint
  remain consistent on Main and every submenu.
- Open Quick Menu > Settings and confirm General, Controller, Focus, and RTSS categories fit without clipping.
- Confirm Focus reports Window Management as `ON • COORDINATED`.
- Toggle a persistent option, close and reopen SteamShell, and confirm the value remains changed.
- Confirm startup-only rows show `NEXT BOOT`.
- Adjust controller mouse speed, cursor hide delay, and the custom frame cap with left/right.
- Disable auto-hide while the cursor is hidden and confirm the cursor becomes visible.
- Open Controller Mapping and Full Settings Editor from the Quick Menu.
- Press B in a Settings category to return to the Settings page, then press B again to return to the main page.

## Full Settings editor

- Open the editor with `Ctrl+Alt+Shift+S` and confirm all eight categories switch without overlapping controls.
- Confirm `Ctrl+Alt+Shift+P` opens Control Panel and `Ctrl+Alt+Shift+S` opens Full Settings.
- Confirm the window has a normal title bar: Close and Minimize work, Maximize is visible but disabled, and the
  window still resizes vertically without allowing its width to change.
- Immediately after the first open, confirm `SteamShell.log` contains
  `Settings layout audit passed for all categories.` and no `Settings layout audit found` warning.
- Inspect every category at the minimum 450-pixel window height, its initial monitor-fitted height, and the maximum
  660-pixel height. Scroll each long category from top to bottom and confirm no row is clipped beneath a heading,
  category list, scrollbar, divider, status line, or footer.
- Confirm headings and category rows display literal ampersands in `Startup & Splash`, `Controller & Cursor`,
  `Focus & Windows`, `RTSS & Performance`, and `Advanced & Logging`.
- In General, confirm the Steam Menu, Steam Quick Access, and in-game overlay shortcut fields and Record buttons
  are aligned, remain reachable at the minimum window height, and save/reload without changing unrelated settings.
- At the HTPC's Windows scaling level, confirm the editor fits inside the monitor work area and the Save, Reload,
  and Close buttons remain visible.
- Without holding View/Back, use the right stick and RB click in Settings, a
  file picker, Controller Mapping, AlwaysFocus Manager, Health Check,
  Diagnostics, and Live Log. Confirm automatic pointer control continues in
  each window and returns to Settings when it closes.
- In a companion window, press LT/RT or Y and confirm it does not switch the
  hidden Settings category or save Settings; those commands remain scoped to
  the main Settings window.
- On a monitor with additional vertical space, confirm the editor opens taller than the former 620-pixel limit.
  Drag its lower resize edge up and down and confirm the category list, content viewport, scrollbar, status line,
  divider, and footer buttons resize together without overlap. Confirm the window width remains fixed.
- Drag and page through the native scrollbar in long categories, then use the mouse wheel; confirm both remain
  synchronized and the scrollbar disappears in categories whose content already fits.
- Repeat scrollbar dragging and mouse-wheel scrolling at 100%, 125%, and 150% display scaling; confirm controls
  do not smear, trail, overlap, or leave stale pixels behind.
- Repeat the initial-open fit check at 300% scaling on the 4K display. Confirm the title bar and footer both remain
  inside the monitor work area, long field labels are complete, and Advanced actions form two aligned columns.
- In Controller & Cursor, confirm the Mouse Parking Edge dropdown is fully separated from the two action buttons,
  and that both `Right` and `Left` save and reload correctly.
- In RTSS & Performance, confirm the full DLL-integration checkbox label is visible, the shortcut rows and Launch
  Selected RTSS button do not overlap it or one another, and the category scrolls far enough to reveal the button.
- Switch each RTSS control mode between `Toggle` and `Separate`; confirm only its applicable shortcut field(s) are
  enabled. Toggle DLL integration separately and confirm the shortcut fields remain available as fallback controls.
- In Focus & Windows, confirm Window Management is available, Foreground Sensitivity defaults to
  `Responsive (55)`, and the other choices are `Balanced (60)` and `Conservative (70)`.
- Confirm Maximize Width Threshold fits on one line, displays `20` rather than a raw fraction, accepts values from
  5 through 100, and saves `20` as `WindowManagement.MinWidthPercent=0.2` without floating-point noise.
- Load a custom `GameMinScoreToActivate` value such as `65`, open and save Full Settings without changing its
  `Custom (65)` selection, and confirm the value remains `65`.
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
  control, left/right adjusts choices and numeric fields, A activates controls, and LT/RT changes categories once
  per pull.
- Confirm the right stick moves the pointer without holding Back and the configured RB short action (Left Click by
  default) clicks the control beneath it. Confirm both also operate the pointer in a Settings file picker. In the
  main Settings window, hold Back and verify the other normal configured mappings work without causing a stale
  trigger-based category change after Back is released.
- Select an edit field with A and confirm the Windows touch keyboard opens. Confirm Y saves changes.
- Confirm opening the touch keyboard does not terminate `TextInputHost.exe`. Close it and invoke it again, then
  confirm the modern keyboard presents even when `TabTip.exe` was already running in the background.
- Open Task Manager, select its search box, invoke the modern touch keyboard with the controller, and confirm it
  appears and enters text while SteamShell and Task Manager both report elevated.
- Confirm the X long-press classic OSK fallback still opens independently of the modern touch keyboard.
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
- Confirm low-level Window Engine timing/retry fields no longer appear in Settings or the synchronized INI.
- Change RTSS Overlay and Frame Limiter control modes; confirm only the shortcut fields used by the selected mode
  remain enabled.
- Toggle Launcher Cleanup Require No Game, CPU/audio detection, and Download Guard; confirm dependent controls
  enable only when they can affect behavior.
- Change Game Log Detail between OFF, ACTIVATIONS, TOPN, and DIAGNOSTIC; confirm irrelevant logging controls are
  disabled and ACTIVATIONS records an actual game activation.
- Open AlwaysFocus Manager and confirm its explanation says Steam is managed separately. Confirm Steam is omitted
  while other visible applications remain available.
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

- After a normal sign-in, confirm SteamShell shows **Elevated: Yes** in Task Manager. Run Health Check and confirm
  **Runtime privileges** reports administrator privileges.
- Launch `SteamShell.exe /safe` from a non-elevated prompt and confirm the elevated replacement retains `/safe`
  rather than starting a normal shell session.
- In **Startup & Splash**, turn off **Run SteamShell as administrator on startup**, save, and restart SteamShell.
  Confirm it does not request elevation and Health Check warns that control of elevated applications may be
  blocked. Turn it back on, restart, and confirm elevation returns.
- Holding L3 + R3 for about 0.7 seconds opens and closes Quick Menu.
- Holding Back and tapping Start opens the Windows Start menu.
- Holding Back and holding Start past `ControllerChordHoldMs` opens File Explorer without also opening Start.
- The six-button fallback chord opens Full Settings when **held**, without also opening Quick Menu. Confirm a brief
  press does nothing — the hold now matches the Quick Menu's L3+R3 chord so a stray grip during play cannot throw
  Full Settings over a running game.
- With the Quick Menu already open, press the six-button chord. Confirm Full Settings does **not** open and the
  Quick Menu keeps receiving every button. Repeat with the Steam recovery screen and the controller test open.
  Previously this opened a focused Settings window that ignored input while the surface behind it kept responding.
- Disconnect the controller midway through holding the chord, reconnect, and confirm Full Settings does not open
  by itself — the hold state is discarded on disconnect.
- D-pad and left stick navigate.
- A selects and B closes/goes back.
- Existing Back + button mappings still work.
- Close every existing Task Manager instance, then use the mapped Task Manager action. Confirm Windows opens it
  through Ctrl+Shift+Esc, the window centers/maximizes after settling, and the normal Back-modified controller
  pointer and click mappings work.
- Disable Controller Mouse Mode while leaving Quick Menu enabled. Confirm L3+R3 and Quick Menu navigation still
  work, but Back mappings, stick mouse movement, scrolling, and D-pad passthrough do not.
- Disconnect and reconnect the controller while holding a button. Confirm reconnecting does not fire a stale short
  press, long press, Task Switcher close, or Quick Menu action.
- Open Controller Test and confirm buttons, triggers, and raw axes update without sending mapped actions elsewhere.
- Leave the sticks untouched for the three-second center sample, apply the suggested deadzone, and confirm the new
  value is written to the INI and reflected in Full Settings.

## Focus

- Confirm Health Check reports the coordinated engine inventory size, scan duration, and most recent decision.
- Launch Unreal Tournament 2004 (or another older DirectX title). Confirm an untitled/ToolWindow render surface
  appears in Task Switcher using its executable as the fallback label, can be selected and locked, and is brought
  forward by Game Foreground Assist.
- Let Steam steal focus so the legacy exclusive-fullscreen window minimizes. Confirm it remains in Task Switcher
  despite its tiny minimized rectangle and Game Foreground Assist restores it when its retained window style is
  a captionless popup.
- While that legacy game is running, confirm Steam does not reclaim focus and Launcher Cleanup does not treat the
  session as having no game.
- Leave only Steam Big Picture usable, with another application minimized, and confirm Steam becomes foreground
  after the configured refocus delay without requiring Alt+Tab.
- Move a titled test window entirely off-screen, then return to Steam and confirm the off-screen window does not
  indefinitely block Steam fallback.
- Leave auxiliary Steam or `steamwebhelper.exe` windows present and confirm they do not count as another open
  application. Confirm the largest Big Picture title match is selected.
- Set `BpmTitle` to a valid substring of the complete Big Picture title and confirm refocus still works.
- Keep a meaningful non-Steam application visible and confirm Diagnostics identifies its executable and truncated
  title as the reason Steam fallback is waiting.
- Open several normal windows and confirm the engine performs one inventory pass per tick rather than separate
  geometry, game, AlwaysFocus, Task Switcher, and Launcher Cleanup window enumerations.
- Open Task Manager and another application whose window grows during startup. Confirm the engine waits for the
  initial layout to settle, then centers/maximizes the final normal window rather than exhausting its correction
  attempts against an intermediate startup size.
- Move a managed normal window repeatedly and confirm SteamShell stops correcting it after the configured recent
  action budget, then safely reconsiders it after the suppression window.
- Confirm a newly centered/maximized window does not trigger a focus activation during the same engine cycle.
- With competing candidates present, verify the priority order is Task Switcher lock, AlwaysFocus, game, then
  Steam fallback, with no two windows alternating focus.
- Open a dialog belonging to a pinned process and confirm the dialog remains in front.
- Run Game Foreground Assist twice several seconds apart and confirm the second CPU sample becomes known without
  a WMI service/query delay.
- Open Quick Menu over Steam and confirm the menu becomes the foreground window. Use D-pad and A throughout the
  main page and a submenu; Steam Big Picture must not move or activate anything behind it.
- Closing it restores Steam.
- Opening it over a borderless game and closing it restores the game.
- Focus Assistance can still be paused and resumed from Quick Menu Settings.
- Task Switcher lists visible application windows but omits SteamShell, the desktop, and taskbars.
- Pressing A on a task activates it once, does not report `LOCKED`, and does not keep pulling it back to the front.
- Pressing Y on a task activates it and the main menu reports `LOCKED`.
- Pressing X on a task requests that window to close and refreshes the task list.
- Confirm the Task Switcher footer explicitly shows `Hold X force close`.
- An application with unsaved work can show its normal save/close confirmation; the Quick Menu gets out of its
  way and the process is not force-terminated.
- Holding X for about 1.2 seconds force-closes the selected process without also sending the normal close action.
- Verify the force-close test with a disposable application: unsaved work can be lost and all windows belonging
  to that process can close.
- Pressing X on Back, paging, or Release Focus Lock rows does nothing.
- Confirm Steam, Explorer, SteamShell, and Windows shell-host processes cannot be force-closed from Task Switcher.
- Another unrelated application does not permanently steal focus from the Y-locked task.
- Dialogs belonging to the selected application remain usable.
- Release Focus Lock clears the task lock.
- Closing the selected window clears the task lock automatically.

## Desktop restoration

- Leave the controller untouched and confirm Health Check's Windows input idle value steadily increases even when
  SteamShell parks the cursor after a managed focus change. Confirm the configured Windows display-off and sleep
  timeouts occur normally.
- If idle time increases but sleep still does not occur, run `powercfg /requests` from an elevated terminal to
  identify a driver or application power request outside SteamShell.
- Confirm Health Check reports Taskbar Guard active, the primary taskbar hidden, and either
  `event hook + periodic safety` or the periodic-only recovery mode.
- While SteamShell is active, invoke the Start menu, Game Bar, and File Explorer several times; confirm neither
  the primary nor a secondary-monitor taskbar remains visible.
- Restart Explorer during a disposable test session and confirm a recreated taskbar is hidden again. Verify the
  log reports periodic-only mode if Windows refuses the event hook.
- During a deliberately slow or failed Steam launch, background `explorer.exe` may run for Game Bar support, but
  the taskbar and desktop never replace SteamShell merely because the startup-warning delay expires.
- Confirm the log records a single startup warning after `SteamStartupGraceMs` while automatic restoration remains
  disarmed until **Big Picture has actually been seen on screen** — the log line is
  `Shell monitor: Steam Big Picture observed`, not the old process-only message.

### Startup surface detection — the black-screen fix

Run these on the Wi-Fi handheld, not the wired HTPC; the wired machine wins the startup race and never reaches
these states. Drop `SteamStartupGraceMs` to about `20000` while testing so each attempt is not a two-minute wait.

- **Normal boot.** Confirm the log reports `Steam Big Picture observed` and that the session reaches `ACTIVE`.
- **The actual failure.** Boot with Wi-Fi disabled or the access point unreachable. Steam will start and sit on a
  connecting/sign-in window. Confirm that after the grace period the **controller-navigable recovery screen
  appears** — previously this produced an indefinite black screen, because a running `steam.exe` marked the
  session healthy and put the recovery screen permanently out of reach.
- On that recovery screen, press **Retry**. Confirm the screen does not silently vanish and strand you: with Steam
  running but not rendering, Retry used to mark the session healthy and dismiss the only way back.
- **Latching.** Once Big Picture has been seen, launch a game that covers or minimises it. Confirm no recovery
  screen appears and no restore is attempted — the observation must never be re-tested.
- **Exit still works.** Quit Steam from Big Picture and confirm the desktop restore still happens after
  `SteamExitConfirmMs`.

### Desktop-restore failure screen

- Force a restore failure (deny the shell registry write, or block Explorer from starting). Confirm the
  **DESKTOP RESTORE FAILED** screen appears with Retry Restore / Open Settings / Keep SteamShell Running.
- Drive it with the **controller only** — D-pad moves between buttons, A activates. It previously required
  pointer emulation, which is the wrong thing to depend on when Explorer may be dead.
- Confirm Retry re-runs the restore and that declining leaves SteamShell running with controller input working.

### Popups must not be centred

- Open a dropdown, a combo box list, and a right-click context menu in **Explorer and in a Qt application such
  as PCSX2**. Confirm none of them jump to the centre of the screen. Qt popups are unowned, which is why an
  ownership-based filter caught Explorer's and missed these. They are positioned relative to the control that opened them, so
  centring detaches them from their parent.
- Confirm a real **dialog** — one with a title bar — is still centred. Dialogs are owned like dropdowns are, and
  the two are told apart by the caption, so this is the case a too-broad filter would break.
- Confirm ordinary application windows are still centred and maximised as before.
- With an older game that presents a titled ToolWindow surface, confirm it is still managed. Tool windows are
  only rejected when they are also small, so a full-size game surface still qualifies.
- Confirm a **borderless fullscreen** application is still centred/maximised. Captionless windows are judged by
  size, and a borderless window is meant to pass that test where a dropdown does not.
- If a popup still gets centred, set `GameLogMode=DIAGNOSTIC` and reproduce. The `Geometry: centred ...` line
  reports the class, size, style, exStyle and owner of whatever was moved — send that rather than the app name.

### Quick Menu status line

- Trigger a warning with the Quick Menu open — easiest is an RTSS action with RTSS stopped, or an audio
  action on a machine with endpoint switching unavailable. Confirm the message replaces the footer hint.
- Confirm the hint returns by itself after about four seconds without touching anything.
- Confirm the message still reaches `SteamShell.log`; the footer is additional, not a replacement.

### Startup curtain must yield

- With the splash enabled, open Full Settings during the curtain using the controller chord. Confirm Settings
  **stays in front** rather than being buried within about half a second. The splash guard re-asserts topmost
  twice a second and previously had no awareness of SteamShell's own windows.
- Repeat with the Quick Menu and with the Steam recovery screen.
- Close that window and confirm the curtain returns to the front and still fades on its own schedule.
- Configure an invalid Steam path and confirm the recovery window appears after the splash, remains above other
  windows, and offers Retry Steam, Open Settings, and Restore Desktop.
- In that recovery window, confirm D-pad changes the focused action and A activates it.
- After Steam has been observed running, a brief `steam.exe` restart shorter than `SteamExitConfirmMs` does not
  restore the desktop.
- Exit Steam to Desktop asks Steam to close gracefully.
- Explorer, the taskbar, and normal desktop startup complete exactly as they do after exiting Steam directly.
- If Steam refuses to close within 20 seconds, confirm a visible prompt appears offering to restore the desktop
  anyway, and that declining leaves SteamShell active without a partially restored desktop.
- With an unset or invalid Steam path, confirm Exit Steam to Desktop shows a visible message rather than
  abandoning the restore silently while the taskbar is still hidden.
- Exiting Steam directly and using the Quick Menu both restore a visible `Shell_TrayWnd` taskbar.
- Desktop restoration verifies the shell registry write, retries Explorer, and logs whether its taskbar appeared.
- Simulate one failed Explorer launch and confirm SteamShell retries. Simulate all restore attempts failing and
  confirm SteamShell remains running with a Retry/Cancel prompt rather than exiting into a blank desktop.
- A normal session restore puts the configured SteamShell value back for the next sign-in after the handoff completes.
- Disable the startup splash and confirm window management becomes active after startup rather than remaining
  permanently disarmed.
- Run the compiled EXE with `/safe`; confirm Explorer and Settings open, Steam/startup programs do not launch, the
  taskbar remains visible, and reloading settings does not reactivate focus, window, cursor, or cleanup automation.

## Desktop blackout

This is the least-proven feature in the build. Hiding `Progman`/`WorkerW` is reasoned by analogy to the taskbar
hiding that already works, not verified — treat Game Bar and UWP as the things most likely to object. The escape
hatch is Quick Menu ▸ Settings ▸ General + Startup ▸ Black Desktop Background, which applies immediately.

**Does it work at all**

- Boot into SteamShell and confirm the wallpaper and desktop icons are gone everywhere Steam does not cover —
  after the splash fades, and with Steam windowed or minimised.
- Confirm Health Check reports Desktop blackout active, backdrop present, desktop hidden, and whether the event
  hook or the periodic fallback is in use.
- Exit a game back to Steam and confirm no wallpaper flashes through the transition.

**The risky interactions — test these deliberately**

- Open Game Bar (Win+G) several times. Confirm it still opens, overlays correctly, and closes. This is the
  specific thing hiding `Progman` could break.
- Open and use other UWP surfaces: the touch keyboard, notification centre, and any Xbox overlays you rely on.
- Confirm the Start menu still opens if you invoke it, and that dismissing it does not leave the desktop visible.
- Launch a borderless-fullscreen game and an exclusive-fullscreen game. Confirm neither shows a black frame and
  neither loses focus to the backdrop.

**Safety behaviour**

- Confirm the backdrop never appears in Alt+Tab and can never be focused by clicking the black area.
- Change resolution and refresh rate from Quick Menu ▸ Display. Confirm the backdrop re-fits with no gap at any
  screen edge.
- On a multi-monitor setup, confirm the backdrop covers every monitor, including one positioned left of or above
  the primary (negative virtual-screen coordinates).
- Search the log for the backdrop reaching the foreground. It should never appear; if it does, capture the log.
- Turn the setting off from the Quick Menu and confirm the wallpaper and icons return **immediately**, not at
  next boot. Turn it back on and confirm the blackout returns immediately.

**Release on every handoff**

- Exit Steam to desktop. Confirm the wallpaper and desktop icons come back with the taskbar.
- Return to SteamShell and confirm the blackout re-applies.
- Run with `/safe` and confirm the wallpaper and icons are visible and stay visible.
- Exit SteamShell normally and confirm the desktop is fully restored.
- **End Task SteamShell while the blackout is active.** The desktop windows stay hidden because OnExit cannot
  run — confirm the existing unexpected-exit recovery restarts Explorer and the desktop comes back on its own.
- Force a Steam-restore failure and confirm the desktop is visible for the Retry/Cancel prompt rather than the
  prompt appearing over a black screen.

## Desktop mode

Run every item below on a disposable test sign-in. Several deliberately kill Explorer or SteamShell.

**Entering**

- Exit Steam normally and confirm SteamShell does **not** close. The taskbar returns, and SteamShell's icon is
  present in the notification area (check the overflow panel first; pin it if you want it beside the clock).
- Confirm the same for Quick Menu ▸ System ▸ Exit Steam to Desktop and for the tray's Exit Steam to Desktop.
- Confirm Health Check reports presentation mode `Desktop mode` and that the log records desktop mode becoming
  active.
- Confirm the tray tooltip reads `SteamShell — desktop mode`.

**Tray icon survival — the highest-risk item**

- The restore restarts Explorer, destroying every tray icon. After each entry into desktop mode, confirm
  SteamShell's icon is actually present and its menu opens. Repeat at least three times: this is a timing race.
- While already in desktop mode, kill and restart Explorer manually (`taskkill /F /IM explorer.exe`, then run
  `explorer.exe`). Confirm the icon returns and the log records the re-assert.
- Confirm the icon is also present after a cold boot into SteamShell, before any restore has happened. It is
  registered before SteamShell launches Explorer specifically so the first `TaskbarCreated` is not missed.

**Tray right-click**

- Right-click the SteamShell tray icon and confirm the **Quick Menu** opens rather than a native Windows menu.
- Immediately after it opens, confirm controller-as-mouse still moves the pointer, and that the D-pad navigates
  the Quick Menu. A native menu would freeze both — AutoHotkey does not run timers while a menu is displayed.
- Drive the whole flow with the controller only, no keyboard or mouse: point at the icon, right-click via the
  mapped button, then navigate to System ▸ Return to SteamShell and activate it.
- Confirm Settings ▸ Reload Settings works from the Quick Menu, since it is no longer reachable from the tray.
- Confirm double-clicking the tray icon still opens the Quick Menu via the menu's default action.

**Behaviour while in desktop mode**

- Controller-as-mouse still moves the pointer and clicks on the Explorer desktop.
- Ctrl+Alt+Shift+Q and the controller chord both open the Quick Menu over the desktop.
- The taskbar stays visible: open and close Start, File Explorer, and Game Bar several times and confirm nothing
  re-hides them. Health Check should report the Taskbar Guard inactive.
- No window is centred, maximised, or refocused. Move and resize an Explorer window and confirm it stays put.
- The cursor is never auto-hidden or parked, including after closing the Quick Menu, regardless of the
  auto-hide-cursor and mouse-park settings.
- Reload settings from the tray and confirm none of the above automation reactivates.
- Confirm the log shows no repeated desktop-restore attempts. A `SteamLaunched` left armed would re-enter the
  restore path on every shell-monitor tick.

**Steam row**

- With Steam closed, the Quick Menu main page reads **Launch Steam** with value `Big Picture`, and Steam Quick
  Access reads `Steam is not running` and does nothing when selected.
- Start Steam by hand from the desktop. Confirm SteamShell stays in desktop mode — the taskbar must not vanish —
  and that the row changes back to **Steam Menu** with the configured shortcut.
- Close Steam again, then choose **Launch Steam** from the Quick Menu. Confirm Steam starts *and* SteamShell
  returns to shell mode with the taskbar hidden.
- Point the Steam path at a missing executable and choose Launch Steam. Confirm a visible failure message and
  that SteamShell stays in desktop mode with the desktop intact.

**Returning and exiting**

- Quick Menu ▸ System ▸ Return to SteamShell (and the tray equivalent) hides the taskbar, restarts the Taskbar
  Guard, and resumes window management. Confirm each in Health Check.
- Return to SteamShell while Steam is not running and confirm the Steam-did-not-start recovery screen is
  presented rather than an empty guarded desktop.
- Quick Menu ▸ System ▸ Exit SteamShell from **desktop mode** closes the process and leaves Explorer, the
  taskbar, and the Winlogon `Shell` value untouched.
- Quick Menu ▸ System ▸ Exit SteamShell from **shell mode** restores the desktop first, then closes. Confirm the
  taskbar is visible and the `Shell` value is back to the configured SteamShell value.
- Both exit rows require a second press to confirm.

**Registry and recovery — verify with `reg query "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v Shell`**

- After any session restore, `Shell` is the configured SteamShell value. Reboot and confirm SteamShell starts.
- **End Task SteamShell while in desktop mode.** Explorer must keep running untouched, and `Shell` must still be
  the configured SteamShell value. Nothing may be restarted and nothing may be rewritten.
- End Task SteamShell while in **shell mode** and confirm the old recovery still fires: `Shell` becomes
  `explorer.exe` and Explorer is restarted.
- End Task SteamShell while in **Safe Mode** and confirm `Shell` is left alone and Explorer is not restarted.
- Settings ▸ Advanced ▸ Permanently Restore Explorer still closes SteamShell and leaves `Shell` as
  `explorer.exe`. Same for Ctrl+Alt+Shift+E and the Setup Assistant's Restore Desktop.
- The recovery screen's **Restore Desktop** is now a *session* restore: confirm SteamShell stays running, enters
  desktop mode, and `Shell` remains the configured SteamShell value.
- Force a restore failure (deny the shell registry write, or block Explorer from starting) and confirm the
  Retry/Cancel prompt still appears, that cancelling leaves controller polling working, and that SteamShell does
  not exit into a blank desktop.

## Audio

- Confirm the submenu matches XFE exactly: Back, Output, Volume, and Mute.
- Current default playback-device name appears.
- Left/right switches among active playback devices.
- Volume changes in 5% steps.
- Mute toggles.

If endpoint switching reports an error, disable `[AudioQuickControls]` temporarily and retain the log. Default
endpoint selection uses Windows' PolicyConfig interface and needs confirmation on the target Windows build.

## Display

- Current resolution and refresh rate are correct.
- Confirm the submenu matches XFE: Back, HDR, Resolution, Refresh rate, Scale,
  and Apply. It must not show the old paginated resolution/refresh combinations.
- Cycle Resolution and confirm Refresh rate immediately remains valid for that
  resolution. Cycle Refresh rate independently; neither action changes Windows
  until Apply is selected.
- Stage a resolution, refresh rate, and—when available—Scale change together.
  Select Apply and confirm it performs one guarded transaction.
- Confirm Apply changes to `Select to KEEP (15s)` and counts down. Select it
  again to keep the transaction; repeat and ignore it to restore the old mode
  and scale after 15 seconds.
- Verify the Quick Menu re-centers after Windows finishes applying a new DPI.
- On an HDR-capable primary display, confirm the row reports live On/Off state;
  A toggles it and Left/Right explicitly select Off/On.
- On a driver without Advanced Color state, confirm the row reports Unsupported
  or Unavailable and cannot claim or apply an unverified state.

## RTSS

- Confirm the submenu matches XFE: Back; the applicable disabled/start/missing
  or Overlay/Frame Limit controls; Save Limit to Profile; and RTSS Settings.

### Frame Limit row

- Cycle Left/Right through **Off · 30 · 40 · 60 · 90 · 120 · Custom** and confirm RTSS shows each value.
- **The preset must survive an off/on round trip.** Set 72 via Custom, cycle to `Off`, then press Right. Confirm
  it returns to **72**, not to 30. "Off" clears RTSS's limiter flag and must never write `0` over the value.
- Press Left repeatedly while already on `Off`. Confirm it does not re-issue the flag write or re-show its
  notification on every press.
- Select `Custom` from `120` and confirm the frame rate does **not** change — landing on Custom only reveals the
  row, seeded from whatever is live.
- On the Custom FPS row, tap Right **as fast as you can**. Every tap must move the value by exactly 1 — no
  acceleration from tapping speed, which was the previous behaviour and made a tap mean different things at
  different times.
- **Hold** Right. Confirm the value starts climbing after about 0.4 s and speeds up the longer it is held, while
  still moving one at a time. Release and confirm it stops immediately where you left it.
- Move to a list-valued row — audio Output, or Resolution — and hold Left/Right. Confirm it does **not** repeat;
  those step once per press on purpose.
- **The frame rate must not chase the number while scrolling.** RTSS is written once, after about 400 ms of no
  input, not on every press. Watch the RTSS overlay: the cap should change once when you stop, not continuously.
- Scroll to a value, then immediately cycle away to a preset before stopping. Confirm the preset sticks and the
  half-dialled custom value does not land a moment later.
- Scroll to a value and immediately choose **Save Limit to Profile**. Confirm the profile receives the value shown
  on screen, not the previous one.
- Confirm every change lands on RTSS's **global** profile and that no per-game profile is modified.
- Temporarily use an RTSS build without `SetProfileProperty`/`SaveProfile`/`UpdateProfiles`, or rename the DLL.
  Confirm the cap shows **read-only** and that Overlay and limiter control still work.

### Save Limit to Profile

- With a game in the foreground, open the Quick Menu and confirm the row shows **that game's executable name** —
  not `SteamShell.exe`, which is what asking after the menu opened would return.
- Press A once and confirm it asks for confirmation; press A again and confirm the log records the write.
- **In RTSS itself**, confirm the game's profile now shows the value *and that its other settings are unchanged*.
  The write is deliberately surgical rather than a copy of the global profile; this is the only way to see it.
- Open the menu over Steam Big Picture with no game running and confirm the row reads `No game in foreground` and
  does nothing — a profile named `steam.exe` would cap the client rather than a game.
- Run it once against a game that has **no** existing RTSS profile and confirm a new `.cfg` appears in RTSS's
  `Profiles` folder. If it does not, `SaveProfile` does not create profiles on this RTSS build and the row is
  silently doing nothing — the log will still claim success.
- With integration disabled, confirm `RTSS Integration — Disabled`.
- With integration enabled, RTSS stopped, and the configured executable present,
  confirm `Start RTSS — Launch configured executable` starts it.
- Confirm generated settings prefill the standard RTSS path and `UseDllIntegration=true`.
- Enable `[RTSS] EnableIntegration=true`.
- With RTSS running, confirm the main row reports live Overlay and Limiter state.
- Confirm A and Left/Right directly toggle each global state and the menu refreshes
  to the state RTSS reports.
- Give the test game's application profile a distinct frame limit and confirm the
  limiter row shows that value when the menu opens over the game.
- Temporarily turn administrator startup Off, run RTSS elevated, and start
  SteamShell unelevated; if Windows blocks a write, confirm SteamShell logs a
  warning rather than claiming success. Restore administrator startup afterward.
- Temporarily remove/rename `RTSSHooks64.dll`, or set `UseDllIntegration=false`,
  and confirm the shortcut fallback below remains available.
- Configure RTSS HotkeyHandler for fallback testing.
- Confirm the generated settings prefill `OverlayToggleShortcut=^+o` (Ctrl+Shift+O).
- Confirm the configured overlay shortcut works outside SteamShell.
- In Toggle mode, confirm Quick Menu sends Ctrl+Shift+O, labels the action TOGGLE, and does not claim the overlay
  itself is on or off.
- Confirm RTSS Settings reports Setup required, Ready to start, Running, or Not
  found as appropriate and opens Full Settings directly to RTSS & Performance.
- Confirm Steam Menu and Steam Quick Access display and send Ctrl+1 and Ctrl+2,
  never `CtrlShift+1` or `CtrlShift+2`.
- Open Quick Menu over a borderless game and select Steam Menu. Confirm the game
  regains focus before the paced Shift+Tab chord is sent and Steam's in-game
  overlay opens reliably.
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
- With `EnableMouseParkOnBoot=true`, test `MouseParkEdge=Right` and `Left`;
  the pointer parks two pixels inside the selected vertical edge of the active display.
- Physical mouse movement restores the cursor; it hides again after `MouseHideDelay`.
- Opening or closing the Quick Menu, selecting a Task Switcher window, or moving between Steam and a game parks the
  pointer once after the new window receives focus and its short settle period completes.
- Move the pointer over a visible Steam tile, launch a game, and close it normally. Confirm Steam may restore itself
  without a forced activation, the pointer moves to the selected edge within about one second, and the old tile is no
  longer hovered when the cursor becomes visible.
- During the focus settle period, physically move the mouse or switch to another application. Confirm the pending park
  is cancelled and does not pull the pointer away from the user's new position.
- Repeated focus polling while the same window is already active does not move the pointer or reset the idle timer.
- With only Steam Big Picture idle, Windows display-off and automatic sleep timers still expire normally.
- Confirm the compact main page lists, in order: Audio, Display & HDR, RTSS & Performance, Steam Menu,
  Steam Quick Access, Controller Layout, Task Switcher, Game Bar, Settings, and System.
- Confirm the main page uses summaries/descriptions rather than arrows: live Audio/Display/RTSS state, actual Steam
  shortcuts, `View mappings`, the window count, `Win + G`, `Features & configuration`, and `Power & diagnostics`.
- Confirm the main page opens Audio, Display, RTSS, Controller Layout, Task Switcher, Settings, and System submenus
  without clipping. Confirm Steam Menu, Steam Quick Access, and Game Bar close the menu, restore the prior
  foreground, and then send the displayed shortcut.
- Page changes reuse the same Quick Menu window with no visible teardown/rebuild.
- At 100%, 150%, 200%, and the HTPC's normal Windows scale, the first Quick Menu
  appearance is fully visible and rounded; no region clips through a row.
- With the Quick Menu focused, verify arrows, Enter/Space, Backspace, Home/End,
  and Task Switcher Delete match controller behavior.
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

Also double-click `Build-SteamShell.cmd` and confirm it keeps the result visible
and returns the PowerShell build's failure/success exit code.

The compiled executable is written to `dist\SteamShell.exe`.
Confirm the build output identifies `AutoHotkey64.exe`; do not use `AutoHotkey32.exe` as the Ahk2Exe Base File.
- Confirm the compiled executable and notification-area entry use the standalone
  charcoal/cyan SteamShell “S” controller icon.
- Right-click the notification-area icon and verify Quick Menu, Settings,
  Diagnostics, Reload Settings, and Exit to Desktop.
