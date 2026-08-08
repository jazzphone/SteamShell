# SteamShell 1.9.9 Release Acceptance Test Checklist

The working tree and coordinated locked source snapshot are 1.9.9. The release
bundle is `releases/1.9.9/`.

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
  `%ProgramFiles%\SteamShell\SteamShell.exe`, with writable data under
  `%ProgramData%\SteamShell`.
- Confirm the emergency Restore Windows Desktop shortcut appears in the current user's Start menu.
- Confirm the existing customized INI is copied only when the installed folder does not already contain one.
- Read the current-user Winlogon `Shell` value and confirm it contains the quoted installed EXE path.
- Select Repair SteamShell Installation and confirm it succeeds without changing existing settings.
- Run the installed EXE with `/restore`; confirm Explorer and a visible taskbar appear and remain registered for
  the next sign-in.
- Reinstall, force-end SteamShell, use Task Manager > Run new task to execute `/restore`, and confirm the normal
  desktop returns.
- With **Enable elevated helper for administrator windows** enabled, confirm
  the main shell remains Medium, the helper is High, and Health Check reports both.
- From a compiled EXE in a disposable portable path, select Register Current EXE as Shell. Confirm the warning
  displays the exact current path, then verify the current-user Winlogon `Shell` value contains that quoted path.
- Confirm direct registration preserves the previous shell metadata and creates the Restore Windows Desktop
  shortcut without copying the EXE to `%LocalAppData%\SteamShell`.
- Permanently Restore Explorer after the direct-registration test and confirm the Winlogon `Shell` value returns
  to `explorer.exe`.
- Before installing, register a harmless test shell command whose executable
  path contains spaces and arguments. Confirm `/uninstall` resolves and restores
  it rather than replacing it with Explorer.
- Force the saved PreviousShell write-back to fail. Confirm Explorer remains
  registered, `/uninstall` reports failure, and the Restore Windows Desktop
  shortcut plus `HKCU\Software\SteamShell\PreviousShell` remain available for a
  retry.

## 1.9.9 standard-user application launches

- Perform a full reboot into SteamShell, not only a launch from an existing
  Explorer desktop. Confirm the background Explorer broker, Steam, and startup
  applications all start without the Recovery screen. If Explorer needs time
  to initialize, confirm the log reports that its desktop-shell broker became
  ready and contains no `String has no property named Document` failure.
- From a deliberately invalid Steam path, open Recovery, restore the path, and
  select **Retry Steam**. Confirm Steam starts. Select **Restore Desktop** in a
  separate run and confirm a Medium-integrity Explorer taskbar appears; neither
  action may loop back with errors 267 or 1346.
- Start SteamShell normally with the elevated helper enabled. In Task
  Manager or Process Explorer, confirm `SteamShell.exe`, Steam, Explorer, RTSS,
  and MPV are Medium integrity while only `SteamShell-Helper.exe` is High.
- For a Standard installation, confirm Task Scheduler contains the hidden
  on-demand **SteamShell Elevated Input Helper** task, its
  action points at the installed helper, it uses InteractiveToken/HighestAvailable,
  and normal shell startup runs it without another UAC prompt. Delete/disable the
  task and confirm SteamShell logs the failure and falls back to an explicit
  helper UAC request. Repair Setup afterward.
- Apply both **Custom** and **Portable** installs with shell registration and
  confirm Setup warns
  that Windows will ask for administrator approval each time the helper starts,
  including at sign-in, and that no scheduled task is registered for either.
- **Upgrade detection.** With SteamShell installed as the shell, reopen Setup and
  confirm it preselects shell mode, the right location, and a ticked **Register…
  as the Windows shell**, with a status line naming the detected installation.
  Repeat on an XFE machine and confirm it preselects XFE mode, XFE's location,
  and the startup box matching whether the logon task exists. Delete the HKCU
  `Product` value and confirm detection still works from the Winlogon value and
  the scheduled task alone.
- **Optional file deletion.** After unregistering, confirm the second prompt
  lists the exact paths and what is kept. Decline once and confirm nothing was
  deleted. Then accept and confirm only the listed items went.
- **The directory rule is the important one.** Install portably into a folder
  that also contains unrelated files, then uninstall with deletion. The
  unrelated files and the folder itself must survive; only `SteamShell.exe` and
  the `SteamShell` sidecar folder may go. Repeat with a Standard install and
  confirm `%ProgramFiles%\SteamShell` and `%ProgramData%\SteamShell` are
  removed whole.
- **Stale record.** Install, then delete the install folder by hand, then run the
  uninstall. It must report the recorded path as no longer present and offer
  nothing, rather than acting on it.
- **Emptied and reused folder.** Install portably, delete SteamShell's files from
  the sidecar folder by hand, put an unrelated file there, then uninstall with
  deletion. The folder must be kept, with the reason given.
- **No record at all.** Delete the whole `HKCU\Software\SteamShell` key with the
  shell still registered, then uninstall. Detection must still work from the
  Winlogon value, and any deletion offered must be based on that path.
- **Contradiction.** Point `InstalledPath` at a different directory from the one
  in the Winlogon value and run the uninstall. It must offer nothing and say the
  two sources disagree.
- **Running executable.** Run the uninstall from the installed
  `SteamShell.exe` itself and confirm it reports that it cannot delete the
  running executable rather than failing silently or removing its own folder.
- **Controller reaches every window.** With only a controller, open in turn: Full
  Settings, Controller Mapping, Always-Focus manager, Control Panel, Setup
  Assistant, Auto-Login, Health Check, Quick Menu Layout, the live log, the setup
  completion dialog, and the uninstall product dialog. In each, confirm the right
  stick moves the pointer and RB clicks without holding View/Back and without
  changing the saved Mouse Mode. The Quick Menu is the deliberate exception — it
  is controller-driven and needs no pointer.
- **No dialog hides behind a window.** Walk every message the assistant can
  raise — apply failures, the uninstall confirmations, the file and folder
  pickers, Auto-Login, Health Check, Controller Test — and confirm each appears
  in front. Repeat from Full Settings and from the Control Panel, both of which
  are also always-on-top. Any dialog you have to alt-tab to find is a bug.
- **Closing Setup exits SteamShell during first run.** Run SteamShell.exe from a
  folder that is not an installation, let Setup Assistant open, then close it
  with the Close button, the title-bar X, and Escape in turn. Each must exit the
  process — check Task Manager — and leave a usable Explorer desktop. Then open
  Setup from Full Settings on a completed installation and confirm closing it
  only hides the window and SteamShell keeps running.
- **The product prompt is reachable.** Force it by clearing both the HKCU record
  and the detection evidence, then uninstall from the assistant. The dialog must
  appear **in front of** the always-on-top Setup Assistant, and its buttons must
  read SteamShell / SteamShell-XFE / Cancel rather than Yes / No / Cancel. Confirm
  the same for every other message the uninstall shows.
- **It should not normally appear at all.** With a normal installation detected,
  uninstalling from the assistant must never show the product prompt — the
  assistant already knows which product it found and passes it through.
- **Uninstall from Setup.** Use *6. Remove an installation* on each product type.
  Confirm it names what it found, that declining the confirmation changes
  nothing, that accepting retires only the registration or logon task, and that
  the executable and settings survive. Then run it with nothing installed and
  confirm it says so instead of acting.
- **Product question.** Confirm Setup Assistant opens with *1. What are you
  setting up?* and that the two options are **mutually exclusive** — selecting one
  must clear the other. Confirm choosing XFE disables and clears **Register the
  selected SteamShell.exe as the Windows shell**, disables **Portable**, changes
  the recommended location to `%LOCALAPPDATA%\Programs\SteamShell-XFE`, and
  changes the location summary to describe the companion layout. Switching back
  to shell mode must restore all four.
- **Startup registration is per product.** In shell mode, **Register… as the
  Windows shell** must be enabled and **Start SteamShell-XFE automatically at
  sign-in** disabled; in XFE mode, the reverse. Apply XFE mode with the startup
  box **unchecked** and confirm no `SteamShell XFE Companion` task is created,
  `XfeLogonTaskRegistered` is `false`, and the completion dialog says to start it
  manually. Re-apply with it checked and confirm the task appears.
- **Install XFE.** Apply in XFE mode and confirm: `SteamShell-XFE.exe` appears in
  the chosen directory, `HKCU\Software\SteamShell\Product` is `XFE`, a
  `SteamShell XFE Companion` logon task exists whose principal is
  **LeastPrivilege** and not HighestAvailable, Winlogon's `Shell` value is
  unchanged, and no elevated helper was deployed. Sign out and back in; XFE must
  start at normal integrity.
- **Switch shell to XFE.** With SteamShell registered as the shell, apply XFE
  mode. Explorer must be restored, the helper task removed, and the next sign-in
  must reach a normal desktop with XFE running.
- **Launch after XFE.** Run `SteamShell.exe` on an XFE machine. It must open
  Setup Assistant and must not take over the shell.
- **Product-aware uninstall.** `/uninstall` on an XFE machine removes the logon
  task and leaves Winlogon alone; on a shell machine it restores Explorer as
  before. Then delete the `Product` value by hand and confirm the ambiguity
  dialog appears and that Cancel does nothing.
- **`/restore` stays product-independent.** Run it on an XFE machine and confirm
  it still registers Explorer without error.
- **Owner of the freshly deployed helper.** After a clean Setup, confirm
  `SteamShell-Helper.exe` itself is owned by Administrators, not by the account
  that ran Setup. Setup hardens, replaces, then hardens again for exactly this
  reason; a single pass leaves the new file owned by its creator and the
  verification correctly refuses it.
- After any Setup, inspect the helper's `bin` directory with
  `icacls "<path>\bin"`. Confirm only SYSTEM and Administrators hold write access
  and that Users are read/execute. Confirm the owner is Administrators as well —
  a user-owned object remains user-reclaimable even with a read-only-looking
  DACL. Repeat in portable mode while the INI, `logs`, and `backups` folders
  beside it stay writable. Health Check must report **Elevated helper
  protection** as passing.
- Grant the interactive user Modify on that `bin` directory by hand and restart
  SteamShell. Confirm it **refuses to elevate the helper**, logs that the location
  is not administrator-protected, and Health Check reports the protection row as
  failed with the re-run-Setup instruction. Re-apply Setup and confirm both
  recover. Repeat with the write grant on `SteamShell-Helper.exe` alone. Then set
  the directory owner to the interactive user without adding a writable allow
  entry; confirm SteamShell still refuses to elevate it and Setup restores the
  Administrators owner.
- Confirm `SteamShell-Helper.log` is written beside `SteamShell-Helper.exe` and
  not in the writable data folder, and that it rotates at
  `[Logging] LogRotateMaxKB` into the configured number of backups. (Renamed in
  schema 22; the GameLog-prefixed value is carried across on upgrade.)
- Open Quick Menu over Steam and use the controller. Confirm Steam does not react
  in the background. Repeat in Explorer and normal-integrity Settings.
- Put elevated Task Manager in front. Confirm the main log records no duplicate
  mapped actions, while the helper provides pointer, scrolling, clicks, D-pad,
  and safe configured built-in short/long bindings. Open Quick Menu with L3+R3 and confirm the
  helper immediately yields when the normal-integrity menu becomes foreground.
- Open elevated Task Manager in a restored window. Confirm the helper waits for
  it to settle, centers it, and maximizes it when its width meets
  `MinWidthPercent`. Add `taskmgr.exe` to `ExcludeExeList` and confirm neither
  action occurs; remove it and confirm geometry resumes. Turn Window Management
  Off and confirm the helper stops changing elevated-window geometry.
- Enter Desktop mode and restore Task Manager. Confirm helper-driven controller
  input still works but Task Manager is not automatically moved or maximized.
  Return to Shell mode and confirm elevated geometry is enabled again without
  launching a second helper.
- Configure a custom `Send:` binding and exercise it over an elevated window.
  Confirm the helper ignores it while safe built-ins continue to work; the
  writable INI must not become an arbitrary elevated keystroke bridge.
- With elevated Task Manager focused, exercise every builtin mapping in turn.
  Touch keyboard, on-screen keyboard, File Explorer, Quick Menu, and Control Panel
  must work and must come from the Medium-integrity main process; Task Manager,
  Start menu, Game Bar, `Ctrl+Alt+Tab`, clicks, `Enter`, `Esc`, and `Alt+F4` must
  work and come from the helper. Confirm no mapping fires twice and none is dead.
  The on-screen keyboard in particular must be reachable so Task Manager's **Run
  new task** box can be typed into with no physical keyboard.
- Set `[QuickMenu] Enable=false`, reload, and confirm L3/R3 bindings now fire over
  an elevated window instead of being reserved for a menu that cannot open.
- Change `ControllerPollIntervalMs`, reload, and confirm the helper log records the
  configuration reload and the new rate takes effect without restarting SteamShell.
- Launch a game from Big Picture and confirm the game and any ordinary launcher
  it starts are Medium integrity. Confirm the Steam Overlay and controller input
  still work.
- Configure one EXE in Startup Programs for each Normal, Minimized, and Hidden
  mode. Confirm all three run as the signed-in user at Medium integrity, their
  show modes are retained, and hidden-window enforcement still follows the real
  child PID.
- Configure a quoted `.cmd` startup entry with a path containing spaces and
  arguments. Confirm it runs under the standard token and receives its arguments
  exactly once.
- Open Windows Settings, the touch keyboard, classic OSK, the SteamShell INI,
  the log, RTSS, and an exported diagnostic bundle. Confirm none of the launched
  interactive applications is High integrity.
- Exit Steam to Desktop and confirm the recreated Explorer taskbar belongs to a
  Medium-integrity `explorer.exe`. Repeat after an unexpected SteamShell exit and
  in `/safe` mode.
- Open Health Check and confirm **Standard-user launch capability** passes and
  the Steam, Explorer, and RTSS integrity rows report Medium. Confirm tracked
  external processes do not report unexpected integrity.
- Temporarily break the Steam path and confirm recovery remains controller
  accessible and the launch failure is explicit; restore the path and retry.
- With UAC disabled on a disposable test configuration, confirm Health Check
  warns that no linked token exists and the log identifies the inherited-token
  fallback. Re-enable UAC after this test.
- If over-the-shoulder elevation credentials for a different administrator are
  available, start from the normal user and supply those credentials. Confirm
  SteamShell refuses the mismatched linked token and does not launch Steam or
  startup applications as the administrator.

## 1.7.5 audit hardening

- Run `..\Run-SteamShellValidation.cmd`. Confirm all three AHK sources parse, both static
  validators pass, and the broken-source plus locked-stale-output tests run for
  both `SteamShell.exe` and `SteamShell-XFE.exe`.
- Force any validation failure and confirm the command returns a non-zero exit
  code and does not change the existing root `current\` directory.
- On a passing run, confirm root `current\` is replaced as one publication and
  contains both EXEs byte-for-byte identical to their respective `dist\` copies.
- Set a low log-rotation threshold and generate enough activity for backup 10.
  Confirm `.log.1` through `.log.10` rotate correctly and remain ignored by Git.
- Repeatedly open, navigate, and close the Quick Menu while watching GDI object
  count in Task Manager. Confirm the count returns to its baseline and no blank
  row bitmap appears.
- Configure an invalid RTSS path while RTSS is installed in its stock
  `%ProgramFiles(x86)%` location. Confirm the menu, launch action, Health Check,
  and DLL lookup all discover the same executable.

## Settings migration

- Start once with a copy of an older customized `SteamShellSettings.ini`.
- Confirm all existing values remain unchanged, including deliberately blank values.
- Confirm an existing UTF-8 INI is backed up as `.pre-unicode.bak`, converted to UTF-16, and still retains Unicode
  paths and deliberately blank RTSS shortcuts.
- Confirm missing current options and `[SteamShell] SettingsSchemaVersion=19` are added.
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
- Confirm schema 14's custom Quick Menu order is retained by schema 15, the
  retired Layout row is removed, and Open Keyboard plus Mouse Mode are inserted
  immediately after Game Bar and start visible.
- Confirm schema 15's `RTSS.CustomFrameCap` value is copied to the new
  `RTSS.PresetFrameCap` during schema 16 migration and remains as the initial
  retained Custom value.
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
- Confirm the panel background is dark neutral charcoal (`#242424`) rather than the former
  blue-black, and inspect all four edges for any one-pixel native/DWM border.
- Confirm unselected labels and values appear neutral gray, without a blue tint.
- A custom exterior shadow is intentionally not required; confirm the menu remains
  a clean opaque panel against both light and dark content.
- Move repeatedly through rows and pages; confirm the existing window repaints in place without a square-corner
  flash, blank frame, visible control-by-control assembly, or whole-window flicker.
- Watch both the selected row and footer while tapping rapidly: neither the row
  surface nor the whole panel should flash to a blank/background-only frame.
- Open and close the Quick Menu during a game, then exit the game with the menu
  closed. Repeat after several menu sessions. Confirm no hidden menu title, row
  surface, footer, or non-interactive ghost reappears over Big Picture.
- From System, confirm **Exit Steam to Desktop** and keep pressing the controller
  Quick Menu chord while Steam closes. Confirm no title, row surface, footer, or
  other menu fragment appears as the Windows desktop becomes visible. Once the
  desktop is ready, open and close the Quick Menu once and confirm the rebuilt
  menu is complete and responsive.
- Confirm the XFE-style title, rounded selected panel, accent outline and left
  bar, aligned value column, and left-aligned footer hint remain consistent on
  Main and every submenu. Only the selected row should glow, and the glow must
  remain visible when the first or last row is selected rather than clipping at
  the row surface boundary.
- Force both the Steam-startup and desktop-restore recovery screens with a long
  multi-line error reason. Confirm the complete reason and instruction text are
  visible, both large headings are vertically complete, and the button row moves
  down instead of overlapping or clipping the content.
- In Quick Menu ▸ Settings ▸ General & Startup, cycle every accent preset in
  both directions. Confirm the list wraps, the row repaints immediately without
  flicker, and the fill tint follows the accent instead of staying blue-grey.
- Select Custom, set `QuickMenu.AccentColorCustom=A970FF`, and confirm the live
  value reads `Custom · A970FF`. Try malformed hex in a disposable INI and
  confirm the renderer remains readable with the Purple fallback.
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
- Open elevated Task Manager, select its search box, invoke the modern touch keyboard with the controller, and
  confirm the request is made while SteamShell remains Medium and only the helper reports High. Record whether
  the Windows keyboard itself permits text entry across the integrity boundary on the tested Windows build.
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

- After a normal sign-in, confirm SteamShell shows **Elevated: No** in Task Manager
  and `SteamShell-Helper.exe` shows High integrity. Health Check must pass both rows.
- Launch `SteamShell.exe /safe` from a non-elevated prompt and confirm it stays
  non-elevated, keeps Explorer available, and does not start the elevated helper.
- In **Startup & Splash**, turn off **Enable elevated helper for administrator
  windows** and save **without restarting**. Confirm `SteamShell-Helper.exe`
  disappears from Task Manager immediately, the log records that it was stopped,
  and Health Check no longer reports a running helper. Turn it back on, save, and
  confirm a verified helper starts again in the same session. Then repeat across a
  full restart to confirm the startup path still honors the setting.
- Set a Frame Limit (a standard cap, then the Preset, then Custom), reboot, and
  confirm each one comes back exactly as it was left rather than OFF. Repeat with
  the limiter deliberately set to **Off** and confirm it comes back Off and that
  one Right press returns to the previous number, not 30 FPS.
- Confirm `SteamShell.log` records `Restored the last Frame Limit selection: …`
  and that RTSS was not launched by the restore: with RTSS closed at sign-in,
  `RTSS.exe` must not appear until Steam or a startup entry starts it, and the
  restore must then apply on its own within about two minutes.
- Turn off **Restore the last Frame Limit selection when RTSS starts** in
  Settings → RTSS, reboot, and confirm SteamShell leaves RTSS alone.
- Set `[RTSS] UseDllIntegration=false`, reboot, and confirm the log says the
  restore requires DLL integration instead of waiting out the full deadline.

#### Elevated Frame Limit write — the acceptance test

This is the one that decides whether the feature works. Run it from a **standard
user** session with SteamShell **not** elevated and RTSS installed in its stock
Program Files location — the case where every previous build reported the row
read-only.

- Note the modified timestamp and the `[Framerate] Limit=` line in
  `…\RivaTuner Statistics Server\Profiles\Global`. Cycle the Quick Menu's Frame
  Limit row to a value RTSS does not currently hold. Confirm **the file on disk
  changes**, the row lands on the value pressed, and `SteamShell-Helper.log`
  records `RTSS global FramerateLimit written as … for request …`. A row that
  moves while the file does not is the failure this test exists to catch.
- Confirm `SteamShell.log` says `set to … through the elevated helper` and does
  **not** report the cap as read-only.
- Walk all four selection kinds plus Off, then reboot and confirm the restore
  still reproduces each one.
- **The negative.** Turn off **Use the elevated helper to set the Frame Limit**
  in Settings → RTSS and save. Without restarting, cycle the row again: the cap
  must not change and the row must report itself read-only. Nothing should reach
  `SteamShell-Helper.log` — a request logged there means the setting is not being
  honoured. Turn it back on, save, and confirm writes resume **in the same
  session**: the read-only latch is cleared by the settings reload, so this must
  not need a sign-out.
- **Known gap, do not report as new.** With that setting off, in an unelevated
  session, a **per-game** save may still report success it did not achieve. The
  in-process verification re-reads the copy `SetProfileProperty` just wrote, so
  it cannot always tell a persisted write from a discarded one — which is why
  the supported path does not attempt the write in-process at all. Ground truth
  is the profile file under RTSS's `Profiles\` directory. The global cap is not
  affected: its read-back is honest because `UpdateProfiles` reloads from disk.
- **The refusal paths.** Point `[RTSS] Path` at a copy of RTSS outside Program
  Files and confirm the helper log refuses it by name rather than writing — main
  can already write those itself, so the cap must still work there. Then point
  `[RTSS] Path` at a directory containing no `RTSS.exe` and confirm the helper
  refuses and writes nothing anywhere.
- Confirm `rtss-request.ini` in the data directory contains only `Fps` and `Seq`,
  and that the settings INI gained no request keys.
- **RTSS's own window must follow the change live.** With the RTSS window open
  on the Global profile, change the cap from the Quick Menu and confirm the
  Framerate limit shown *in RTSS* updates without touching RTSS — no profile
  switch needed. Two earlier designs failed exactly here while the frame rate
  was correctly limited, so a capped rate is not evidence on its own.
- **Save Limit to Profile, from a standard-user session.** With a game in the
  foreground, set a cap and use **Save Limit to Profile**. Confirm the game's
  profile in RTSS holds the value, and that `SteamShell.log` records it as saved
  through the elevated helper. Then confirm the negative that used to be
  invisible: turn off **Use the elevated helper to set the Frame Limit**, try
  again, and confirm you are told *profile not saved* rather than being shown a
  green success for a write that did not happen.
- **A profile name that names nothing.** With the helper running, hand-edit
  `rtss-request.ini` to a `Profile` naming a process that is not running, bump
  `Seq`, and confirm `SteamShell-Helper.log` refuses it by name and writes
  nothing. Repeat with a name containing a backslash and confirm it is refused
  as not a plain executable name.
- **Dial a Custom value quickly.** Hold Left or Right on the Custom row so the
  number moves several steps in under a second, then stop. The number must
  settle on the value dialled without visibly jumping backwards to the previous
  cap and forwards again. A jump means the row is being repainted mid-write.
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


## Hold to drag

New. `Builtin:LeftClick` is press-and-hold; everything else is unchanged.

**The failure this must never produce is a mouse button stuck down.** On a shell
replacement that is unrecoverable without a keyboard, so keep one connected for
every test below.

- With RB bound to Left click (the default), hold View/Back, hold RB, move the
  right stick. Confirm a drag: select text, move a file, drag a window title bar.
- Tap RB. Confirm it still produces an ordinary single click.
- Confirm RB double-click still works by tapping twice.
- **Release checks.** Start a drag, then in turn: release View/Back mid-drag;
  let automatic mouse mode end by switching to an application not on the list;
  press the Quick Menu chord; press the Settings chord; unplug the controller.
  After each, confirm the button is NOT still down — click somewhere harmless and
  confirm nothing is selected or dragged.
- **Elevated handoff.** Start a drag over an ordinary window and move the pointer
  onto Task Manager so the foreground becomes elevated mid-gesture. The drag must
  END rather than continue, and the button must not stay down.
- **Watchdog.** With a drag held, suspend the poll (open Settings, or reload).
  Within ~35 seconds confirm the log records *Released a synthetic mouse button
  held past the safety limit* and the button is up.
- **Exit and error.** Exit SteamShell mid-drag and confirm the button is released.
- **Mapping editor.** Select RB: confirm the Long combo, Record and Clear are
  greyed out and the note reads *Reserved for mouse: hold RB to drag*. Confirm
  the list's Long column reads *Reserved for mouse (hold to drag)*.
- Change RB's Short to something else and confirm the Long row becomes editable
  again immediately, without reopening the editor.
- Bind Left click to **A** instead and confirm drag moves to A and RB returns to
  a normal Short/Long button.
- Confirm **Right click is unchanged** — RT taps produce a context menu and
  holding RT does not drag.

## Automatic mouse mode

- Confirm `AutoMouseExeList` is **empty** on a fresh install and that behaviour is unchanged: the controller does
  nothing without View/Back held.
- Add `explorer.exe` from Settings ▸ Controller & Cursor. With File Explorer foreground and **View/Back not held**,
  confirm the right stick moves the pointer, the left stick scrolls, the D-pad sends arrows, RB left-clicks and
  RT right-clicks — the same actions holding View/Back gives.
- With only `explorer.exe` listed, test the desktop, taskbar, Start menu, and
  Start/Search results. Confirm automatic mouse mode remains active as focus
  moves between Explorer, `StartMenuExperienceHost.exe` (or the older
  `ShellExperienceHost.exe`), and `SearchHost.exe`/`SearchUI.exe`.
- Confirm holding View/Back while automatic mode is active changes nothing, rather than double-firing.
- Switch to a non-listed application and confirm the controller goes inert again without View/Back.
- With the cursor auto-hidden, switch to a listed application and confirm the
  pointer becomes visible without an AutoHotkey error dialog. This specifically
  covers the `MouseHidden` global-scope regression.
- **The recovery case:** add a game's EXE to the list deliberately, launch it, and confirm the controller becomes a
  mouse — then confirm **L3 + R3 still opens the Quick Menu** and the held six-button chord still opens Full
  Settings. Remove the entry from Settings. This is the path that makes a mistake survivable, so it is worth
  proving rather than assuming.
- With `explorer.exe` still listed, clear **Automatic mouse mode in the applications listed below** in Settings.
  Confirm the controller goes inert in File Explorer without View/Back, that View/Back itself still works normally,
  and that the EXE list is **still populated** when the checkbox is re-ticked.
- Confirm an upgraded INI gains `AutoMouseExeList=` with an empty value and `EnableAutoMouseMode=true`, and that no
  other setting changed.
- Confirm the same upgrade adds `EnableDesktopAutoMouseMode=true` and an empty
  `DesktopAutoMouseExcludeExeList` without changing the existing allowlist.

### Automatic mouse mode over an ELEVATED window

This is the case the two processes used to answer differently, so it is the one
worth proving. Main decides and publishes; the helper reads. Nothing here has
executed.

- **In desktop mode**, open an elevated window that is *not* Task Manager, MMC,
  Control Panel or Settings-admin-flows — `regedit.exe` run as administrator is
  the easiest. With **View/Back not held**, confirm the right stick moves the
  pointer, the left stick scrolls, and **RB left-clicks inside it**. Before the
  fix the pointer did not move and RB did nothing, while X still opened the
  on-screen keyboard — the keyboard with no way to click it is the symptom.
- With the same window focused, confirm **X opens the on-screen keyboard and it
  is usable**: pointer moves onto it, RB clicks its keys, and the keystrokes
  reach the elevated window.
- Clear **Automatic mouse mode** in Settings while that elevated window is still
  foreground. Confirm the controller goes inert **in both halves** within a poll
  or two — no pointer movement *and* no Enter/Esc/Alt+F4 — rather than one half
  stopping and the other continuing.
- Hold View/Back with automatic mode off and confirm full control returns. This
  is the fallback that must survive the coordination event failing to open.
- Check `SteamShell-Helper.log` for
  `The parent automatic-mouse event could not be opened`. It should **not**
  appear. If it does, mouse mode will only engage while View/Back is physically
  held, which is the conservative failure and not a crash.

### Elevated RTSS frame cap: refusals and completion matching

- With `[RTSS] EnableElevatedFrameCapWrites=false` and an unelevated session,
  press the Frame Limit row. Confirm the Quick Menu **does not freeze for three
  seconds per press**. Before the fix the helper declined without signalling and
  main sat out its whole timeout with `Critical` on.
- Confirm `SteamShell-Helper.log` records the refusal by request number, and
  that `rtss-request.ini` gains a `[Result] Seq` that matches the `[Request]
  Seq` beside it.
- Dial a Custom FPS quickly with Left/Right held. Confirm the number never jumps
  backwards and that the log contains no
  `Ignored an RTSS completion for request` lines in the steady state — one or
  two under deliberate load is the mechanism working, not a fault.

### Inert Quick Menu rows

- On a display that cannot do HDR, the Display page must read
  `HDR   Not Supported` and the D-pad must **step over** it rather than
  highlighting a row that does nothing. Previously it could be selected and A
  did nothing, with no message.
- Repeat with RTSS not installed (the RTSS rows) and with no application windows
  open (the Task Switcher row).
- Confirm a page where every row is inert still lets you reach Back, and that
  the selection never gets stuck.
- Confirm ordinary pages still move exactly one row per press.

### Uninstall must not leave the machine looking installed

The bug this fixes is invisible until you uninstall twice, so test in this order.

- **The reported case.** On a PC where XFE was previously installed and removed,
  open Setup Assistant. It must detect **SteamShell**, not SteamShell-XFE.
  Before this fix it reported XFE forever after, because the companion's
  executable is deliberately left on disk and its recorded path was never
  cleared.
- Uninstall XFE and confirm `HKCU\Software\SteamShell` no longer holds
  `XfeInstalledPath`, `XfeHelperDeployed`, `XfeLogonTaskRegistered` or
  `Product`. Confirm the companion's EXE and INI are still there — those are
  meant to survive.
- Uninstall the shell and confirm `InstalledPath`, `DataPath` and
  `InstallationMode` **remain**. Launch the retained EXE by hand and confirm it
  still finds its ProgramData settings rather than falling back to portable.
- **Both products, then remove one with file deletion.** Install the shell,
  install XFE over it, then uninstall XFE and choose to delete files. The
  shell's `InstalledPath`/`DataPath`/`InstallationMode` and `PreviousShell` must
  survive. Previously the whole key was deleted, taking the shell's restore
  metadata with it.
- Confirm the key itself disappears only when nothing of either product is left.
- **The task, without its flag.** Register the on-demand helper task, delete
  `HelperTaskRegistered` by hand, then uninstall. The task must still be gone
  from Task Scheduler.
- Confirm the standalone uninstall message now names the elevated helper folder
  it leaves behind, the way the XFE one always has.

### Section 4 must show one product's sign-in option

- **On a PC with nothing installed** — the case that was broken — open Setup
  Assistant. With "Replace the Windows shell" selected, only "Register the
  selected SteamShell.exe as the Windows shell" may be ticked; the XFE logon-task
  box must be clear and greyed.
- Switch to the XFE product and confirm the two swap: XFE ticked and enabled,
  the shell box clear and greyed.
- Switch back and forth several times and confirm it keeps swapping rather than
  latching.
- Repeat on a PC that already has one product installed, where the boxes should
  open reflecting what is actually registered.

### RTSS must not freeze when the elevated helper dies

- **The three-second freeze.** With the elevated helper running and
  `[RTSS] EnableElevatedFrameCapWrites=true`, kill `SteamShell-Helper.exe` in Task
  Manager, then change the global frame cap from the Quick Menu. It must fail
  promptly — before this fix it froze for three seconds, and up to six on the
  path that also retried per-game.
- Confirm the log names which case it was, and that the on-screen message does
  not claim the helper "could not apply it either" when no helper was running.
- **RTSS absent.** Point `[Paths] RTSS` at a file that does not exist and select
  an RTSS row. It must say RTSS was not found, not silently do nothing.
- **Read-only latch.** Force a write that RTSS accepts but does not keep (RTSS
  under Program Files, elevated writes off). The row goes read-only for the
  session — confirm the user is told, and told what to change.
- Confirm a PC that never had a helper is still instant, not delayed.

### Uninstall must offer a choice when it cannot tell

- **Nothing registered.** Install XFE and decline the logon task, then open
  Setup Assistant and choose Uninstall. It must show the product prompt naming
  both products, not "nothing was detected". Pick SteamShell-XFE and confirm it
  reports success — before this fix it said the installation could not be fully
  removed, because there was no task to delete.
- Confirm the confirmation reads "Remove the installation you chose?" on that
  path, and still reads "Remove the detected installation?" on a normal one.
- Cancel at the product prompt and confirm the status line says nothing was
  changed and the registry is untouched.
- **Uninstall from a different copy.** Delete `RegisteredPath` by hand from a
  working shell install, then run uninstall from a freshly downloaded
  `SteamShell.exe` in another folder. The prompt must appear and removal must
  complete.
- Check the log records which product was chosen at the prompt.

### Dialogs must appear in front

- With a fullscreen game running, trigger the Steam-launch-failure dialog (point
  `[Paths] SteamPath` at something that does not exist). It must appear **over**
  the game, not behind it.
- Open the Auto-Login prompts from Setup Assistant and confirm each appears in
  front. Previously one asked for neither an owner nor topmost.
- Repeat the three desktop-restore prompts with something fullscreen in front.

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

- Right-click the SteamShell tray icon and confirm the **ordinary Windows menu** appears where you clicked, with
  Open Quick Menu, Open Settings, Open Diagnostics, the desktop/shell actions, Reload Settings and Exit.
- Confirm **double-clicking** the icon opens the Quick Menu, via the menu's default item.
- Note that controller polling stops while that native menu is displayed; this is known and accepted. Confirm
  Escape or a click elsewhere dismisses it and polling resumes.
- Drive the whole flow with the controller only, no keyboard or mouse — but using the **chord**, not the tray:
  L3 + R3 to open the Quick Menu, then System ▸ Return to SteamShell. The tray is a pointer surface by design.
- Confirm Reload Settings remains available from the tray and
  `Ctrl+Alt+Shift+R`, but is absent from the Quick Menu Settings page.
- Confirm double-clicking the tray icon still opens the Quick Menu via the menu's default action.

**Behaviour while in desktop mode**

- With desktop-wide automatic mouse enabled, confirm controller mouse mappings
  work without View/Back in Explorer, Start, Settings, a browser, and another
  ordinary desktop application. Return to SteamShell and confirm those unlisted
  applications immediately return to the conservative allowlist behavior.
- Add a test application's EXE to `DesktopAutoMouseExcludeExeList`; in desktop
  mode confirm automatic mouse stops only in that application and resumes when
  focus leaves it. Remove the disposable entry after testing.
- In desktop mode, confirm the tray shows a checked **Automatic Mouse Throughout
  Desktop** item. Toggle it off and verify automatic mouse stops in every desktop
  app, then reopen the tray and confirm the check remains off. Toggle it back on,
  reload settings, and confirm the enabled state persisted.
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

- With Steam fully closed, choose Quick Menu ▸ System ▸ **Return to SteamShell**
  and repeat with the tray equivalent. Confirm Steam Big Picture starts
  automatically, the taskbar hides, and Taskbar Guard/window management resume.
- Point the configured Steam path at a missing executable, then choose Return to
  SteamShell. Confirm the launch failure stays on the usable Explorer desktop;
  it must not switch presentation first or show the ordinary no-Steam recovery.
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
- On a 4K TV or monitor, confirm `2560×1440` and `3840×2160` appear when Windows
  offers them; the list must not stop near `1280×1024`. Check the log for
  `Display modes: Windows reported N entries`, especially when N exceeds 512.
- Stage a resolution, refresh rate, and—when available—Scale change together.
  Select Apply and confirm it performs one guarded transaction.
- Confirm Apply changes to `Select To KEEP (15s)` and counts down. Select it
  again to keep the transaction; repeat and ignore it to restore the old mode
  and scale after 15 seconds.
- **KEEP must never be refused.** Whenever the row reads `Select To KEEP`, one
  press must confirm — the toast reads *Display settings kept* and the countdown
  stops. Work through every case that used to eat the press:
  - a **59.94 Hz** mode, where the enumerated list says 60 and Windows reports
    59 as current. This is the one that produced "sometimes it keeps, sometimes
    it ignores you", so test it explicitly if the display offers such a mode.
  - a change that includes **Scale**, pressed KEEP as soon as the row appears
    rather than after waiting for the desktop to settle.
  - a resolution the driver stops offering after the change (hot-plug or switch
    inputs mid-window if the panel allows it).
  In every case confirm the change **survives past 15 seconds**. A refused press
  used to look like nothing happening, then a revert.
- Confirm the toast after Apply reads *Select KEEP within 15 seconds or it
  reverts* and no longer says "Select CURRENT again".
- Verify the Quick Menu re-centers after Windows finishes applying a new DPI.
- On an HDR-capable primary display, confirm the row reports live On/Off state;
  A toggles it and Left/Right explicitly select Off/On.
- On a driver without Advanced Color state, confirm the row reports Unsupported
  or Unavailable and cannot claim or apply an unverified state.

## RTSS

### RTSS control feedback and ordering

- With RTSS running and DLL integration on, select **Overlay ON** while the
  overlay is already on. Confirm it reports *RTSS overlay is already on* rather
  than doing nothing. Repeat for Overlay OFF and both frame-limiter states.
- Confirm a no-op limiter press does **not** rewrite `SteamShellSettings.ini`
  (compare the file timestamp before and after).
- Clear `[RTSS] OverlayToggleShortcut`, close RTSS, and toggle the overlay from
  the Quick Menu with DLL integration off. Confirm SteamShell says *Configure
  RTSS OverlayToggleShortcut first* and that **RTSS is not launched** — the old
  order started it first and only then reported the missing shortcut.
- Repeat for each of the six shortcut settings and confirm the message names the
  specific one that is blank.
- Set `[RTSS] EnableIntegration=false` and confirm every RTSS control refuses
  with the integration message rather than acting.


- Confirm the submenu matches XFE: Back; the applicable disabled/start/missing
  or Overlay/Frame Limit controls; Save Limit to Profile; and RTSS Settings.

### Frame Limit row

- Set Preset to 158 in Settings. Cycle Left/Right through
  **Off · 30 · 40 · 60 · 90 · 120 · Preset · Custom** and confirm Preset shows
  and applies **158 FPS**.
- **The preset must survive an off/on round trip.** Set 72 via Custom, cycle to `Off`, then press Right. Confirm
  it returns to **72**, not to 30. "Off" clears RTSS's limiter flag and must never write `0` over the value.
- Press Left repeatedly while already on `Off`. Confirm it does not re-issue the flag write or re-show its
  notification on every press.
- Adjust Custom to 157, cycle to Preset, then back to Custom. Confirm Preset
  restores 158 and Custom restores 157, including after restarting SteamShell.
- Temporarily set Preset to 60. Confirm the cycle still reaches 90 and 120
  normally instead of treating the same 60 FPS number as two distinct states.
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
- Force either the FPS write or limiter-flag write to fail during a cycle and
  during startup restore. Confirm SteamShell logs/reports the failure and does
  not record or announce the requested selection as successfully applied.

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
- Temporarily turn the elevated helper Off and run RTSS elevated. Confirm
  SteamShell remains normal integrity, reports the disabled helper, and does not
  claim that blocked elevated-window input succeeded. Restore the helper afterward.
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
  Steam Quick Access, Task Switcher, Game Bar, Open Keyboard, Mouse Mode,
  Settings, and System.
- Confirm the main page uses summaries/descriptions rather than arrows: live Audio/Display/RTSS state, actual Steam
  shortcuts, the window count, `Win + G`, `Open Touch Keyboard`, Mouse Mode's
  On/Off state, `Features & Configuration`, and `Power & Diagnostics`.
- Confirm the main page opens Audio, Display, RTSS, Task Switcher, Settings, and System submenus
  without clipping. Confirm Steam Menu, Steam Quick Access, and Game Bar close the menu, restore the prior
  foreground, and then send the displayed shortcut.
- Select Open Keyboard and confirm the Quick Menu disappears before the touch
  keyboard appears. Open Settings ▸ Windows Settings and confirm the same
  dismiss-before-launch behavior.
- Enable Mouse Mode without holding View/Back and confirm the right stick,
  scrolling, clicks, and configured mappings operate in shell mode. Restart and
  confirm the toggle remains On; turn it Off and confirm View/Back is required.
- With Mouse Mode On, close Quick Settings with B and launch Open Keyboard with
  A. Confirm neither button fires its normal mapping again when released.
- Page changes reuse the same Quick Menu window with no visible teardown/rebuild.
- At 100%, 150%, 200%, and the HTPC's normal Windows scale, the first Quick Menu
  appearance is fully visible and rounded; no region clips through a row.
- With the Quick Menu focused, verify arrows, Enter/Space, Backspace, Home/End,
  and Task Switcher Delete match controller behavior.
- No bottom-corner SteamShell notification overlay appears.
- Hold Y on the main page and confirm the styled Controller Mappings submenu
  opens inside Quick Settings. Confirm it shows the loaded mappings and ends
  with **Set Controller Mappings**; selecting that row closes Quick Settings and
  opens the full editor. A short Y tap must do nothing.
- Confirm Settings has no Reload Settings row, and System has no Diagnostics
  Control Panel or SteamShell Health Check row.
- Action and warning messages remain available in `SteamShell.log`.
- Leave game-score logging disabled and confirm operational startup, recovery, and desktop-restore messages still
  appear in `SteamShell.log`.

## First-run Setup Assistant and deployment

- Run a freshly compiled EXE normally from a disposable Explorer desktop with
  no sidecar or legacy INI. Confirm the administrator-required dialog says
  **Please Start SteamShell As Administrator for First Install or Upgrade** and
  no deployment begins. Click OK and confirm SteamShell exits, its helper is not
  left running, and Explorer plus the taskbar remain usable.
- Right-click that same EXE and select **Run as administrator** using the signed-in
  account. Confirm the one-time request is accepted, Setup Assistant opens
  automatically, and Steam, splash, blackout, startup programs, launcher cleanup,
  and focus/window automation do not start.
- From a completed normal-integrity SteamShell session with its verified helper
  running, open Setup Assistant and press Apply. Confirm the same administrator
  notice appears and OK closes the main instance. Relaunch as administrator and
  confirm Setup Mode closes any remaining same-user SteamShell/helper processes
  before allowing Apply; neither old EXE remains locked during upgrade.
- On a disposable account, supply over-the-shoulder credentials for a different
  administrator. Confirm Setup rejects the user/session mismatch, keeps Explorer
  usable, and performs no deployment. Cancel the Run-as-administrator UAC prompt
  and confirm the already-restored desktop remains usable.
- Test at the HTPC's normal DPI and at 100%, 150%, 200%, and 300%. Confirm the
  assistant stays within the monitor, has a working vertical scrollbar when
  needed, and Apply Setup, Restore Desktop, Close Setup, and status text are all
  reachable. Confirm its outer height remains below roughly 88% of the selected
  monitor's work area and that moving between different-DPI monitors recalculates
  the next time the assistant opens.
- With Steam and RTSS in their default Program Files (x86) directories, confirm
  both are detected and their complete paths are visible. Move a disposable copy
  to Program Files and confirm that fallback is detected. Confirm Steam's Valve
  registry location is honored for a custom install and manual selection updates
  the visible field immediately.
- Remove or invalidate Steam.exe and confirm Apply Setup refuses to continue and
  names the bad path. Leave RTSS absent and confirm setup continues with RTSS
  clearly marked optional.
- Close and reopen the pending assistant. Confirm setup remains Pending and the desktop stays usable.
- Select **Use current location** without shell registration. Confirm `SteamShell.exe` stays in place and the
  `SteamShell` sidecar contains `SteamShellSettings.ini`, `logs`, `backups`, and
  `bin\SteamShell-Helper.exe`; confirm SetupState becomes Complete only in the sidecar copy.
- Test **Choose another location** both with and without Portable selected. Confirm portable data follows the EXE
  while the managed custom layout uses `%ProgramData%\SteamShell`.
- Create a disposable sidecar portable installation, **leave its main/helper
  processes running**, and open Setup Assistant from a newer EXE in another
  directory. (This step used to say "close its main/helper processes" — the
  procedure was written around the bug. Setup closes them now, and leaving them
  running is what tests it.)
  Browse to the existing portable directory and select Portable. Confirm the
  summary says it is an upgrade, the existing INI is byte-preserved apart from
  intentional schema/setup-state changes, both EXEs are replaced, the helper
  reports file version 1.9.9.4, and the registered shell path is unchanged.
- For that disposable upgrade, confirm the pending/in-progress `SteamShell`
  sidecar beside the separate updater EXE is permanently removed only after
  target verification. Confirm the target installation's `SteamShell` sidecar
  and settings remain present and that the updater exits after **Restart Later**.
- Repeat the cleanup guard checks with a completed source sidecar, a source
  link/junction, and a selected target nested beneath the source sidecar. Confirm
  each source is retained and the completion dialog explains why it was not
  removed. These tests must use disposable folders.
- **XFE logon task.** After installing XFE from Setup Assistant, confirm the task
  is named `SteamShell XFE Companion`, carries a 10-second logon delay, and that
  no `SteamShell-XFE` task remains. Uninstall must clear both names.


### Elevation without a prompt, in every install mode

The point of all of this: a UAC consent dialog runs on the secure desktop, where
a controller cannot answer it. These confirm no prompt appears anywhere it can
be avoided, and that it still appears where it must.

- **Standard install.** Reboot and confirm the helper starts with **no UAC
  prompt**. Health Check must report it running through the protected task.
- **Custom install under Program Files.** Same — this used to prompt on every
  start and no longer should.
- **Portable in a folder only administrators can write.** Confirm Setup does
  **not** ask where to put the helper, keeps it beside the executable, and that
  no prompt appears at sign-in. The log must say the folder was found protected.
- **Portable in an ordinary user-writable folder.** Confirm Setup asks, names
  the actual reason (*"it can be written by …"*), and that the answer is written
  to `[Setup] PortableHelperLocation`.
  - Choose **Program Files**: helper lands in `%ProgramFiles%\SteamShell\bin`,
    no prompt at sign-in.
  - Choose **This folder**: helper stays beside the executable and a UAC prompt
    appears — verify it is not silently skipped.
- **The prompt itself.** While the helper-location question is on screen, confirm
  it is above the assistant, cannot be lost behind it, and that the **controller
  can move the pointer and click its buttons**. Repeat with the assistant behind
  another window first.
- **Standard user account.** With a non-administrator signed in, confirm the
  helper does not start, the log says the token was not High integrity, and that
  Windows does **not** prompt for an administrator's credentials.
- **A protected location that stops being protected.** Grant your account Modify
  on the helper's `bin`, restart, and confirm SteamShell refuses to elevate,
  Health Check says why, and it falls back to a prompt rather than using the task.

### Uninstalling from somewhere else

- Install portable to a folder, then run uninstall from a **freshly downloaded
  `SteamShell.exe` in Downloads**. Confirm it finds the installation from the
  registry record, and that the removal plan lists the helper directory —
  whichever of the two locations was used — rather than reporting it as "not a
  folder SteamShell created".
- Confirm the helper directory is actually gone afterwards. It is
  administrator-owned, so a user cannot clean it up by hand if uninstall misses it.
- Confirm the scheduled task is gone too, for both the shell helper and XFE.

### Replacing an executable that is running

Setup replaces `SteamShell-XFE.exe` and `SteamShell-Helper.exe` in place, and
Windows locks a running image. Every case below used to fail; the XFE one failed
on **every** apply, because the logon task starts the companion at sign-in.

- With the companion running, apply Setup. Confirm it succeeds, the log records
  `Setup closed PID … before replacing it`, and the deployed
  `SteamShell-XFE.exe` carries the new file version.
- Confirm the companion is **restarted** afterwards and that the result dialog
  says so. Then check its integrity level in Task Manager: it must be
  **Medium**, not High. Setup is elevated, so a restart through `Run` would have
  handed XFE an administrator token — this is the check that catches that.
- With a helper resident from an earlier unelevated session, apply Setup.
  Confirm the helper is closed, `bin` is hardened, the payload is replaced, and
  `SteamShell-Helper.exe` reports file version 1.9.9.4. Confirm the *order* in
  the log: the stop precedes the harden.
- **Foreign process refusal.** Copy an unrelated executable over
  `SteamShell-XFE.exe`'s path and run it as a different user (or from a
  different session), then apply. Confirm Setup **refuses** rather than killing
  it, names the PID, and leaves the installation untouched.
- **Uninstall with everything running.** Confirm the companion and helper are
  stopped before removal and that no item is reported as a failure. Repeat with
  a helper that cannot be closed and confirm uninstall still proceeds and
  reports only the item that survived.
- **Message quality.** Make a replace fail while a process holds the file (deny
  yourself the close, or hold the file open from another tool) and confirm the
  error names *the file is in use by a running process* rather than a bare
  `[Win32 32]`.

- On a disposable Windows session, apply Setup and confirm the owned completion
  dialog stays above the assistant and offers **Restart Now** and **Restart
  Later**. Confirm Restart Later does not reboot. After saving all work, repeat
  and confirm Restart Now initiates a normal Windows reboot.
- Test **Standard installation** from an elevated setup session. Confirm the EXE is copied and verified at
  `%ProgramFiles%\SteamShell\SteamShell.exe`, the protected component directory is beneath that program folder,
  `components\bin\SteamShell-Helper.exe` is extracted there, and settings/logs/backups are under
  `%ProgramData%\SteamShell` and writable by the interactive user.
- Make the selected target unwritable. Confirm SetupState is not Complete,
  Explorer remains registered/available, and the error identifies the operation
  that failed.
- With shell registration selected, confirm the prior shell value is backed up, Winlogon points to the selected
  EXE only after file verification, and **Restore Windows Desktop** is present in the Start menu.
- Attempt to register a portable copy from a removable, mapped/network, or temporary location. Confirm a prominent
  warning appears and declining it leaves shell registration unchanged.
- Start from a schema-16 settings file. Confirm migration creates a backup, advances to schema 19, records SetupState
  Complete, and does not open first-run Setup Mode.
- Open UAC Settings and Microsoft Autologon Guidance from the assistant. Confirm both are launched at normal user
  integrity, the assistant minimizes instead of covering them, and it restores
  after they close. Confirm every setup warning and success/failure message is
  owned by and displayed above the assistant.
- On a disposable local test account, open **Configure Auto-Login**, enter one
  incorrect password, and confirm Windows rejects it without enabling
  `AutoAdminLogon`. Enter the correct credentials and confirm the next reboot
  logs into that account. Verify no `DefaultPassword` registry string exists,
  the password appears in neither SteamShell INI/log nor any process command
  line, and the password is held as the Windows LSA secret. Test **Disable
  Auto-Login**, reboot, and confirm the normal sign-in screen returns. Hold Shift
  during one enabled boot and confirm Windows bypasses Auto-Login for that boot.

## Compile

After the script passes the checks above:

```powershell
powershell -ExecutionPolicy Bypass -File .\Build-SteamShell.ps1
```

Also double-click `Build-SteamShell.cmd` and confirm it keeps the result visible
and returns the PowerShell build's failure/success exit code.

The compiled executable is written to `dist\SteamShell.exe`.
The build also produces two intermediates in `build\` and embeds both:
`SteamShell-Helper.exe`, verified at version 1.9.9.4, and `SteamShell-XFE.exe`,
verified at 1.9.9.0. Confirm the main EXE reports file version 1.9.9.0. Neither
intermediate is a distribution file. A development copy of the companion is also
left at `dist\SteamShell-XFE.exe`; it is not published, because installing XFE
is Setup Assistant's job.
Confirm the build output identifies `AutoHotkey64.exe`; do not use `AutoHotkey32.exe` as the Ahk2Exe Base File.
- Confirm the compiled executable and notification-area entry use the standalone
  charcoal/cyan SteamShell “S” controller icon.
- Right-click the notification-area icon and verify Quick Menu, Settings,
  Diagnostics, Reload Settings, and Exit to Desktop.

## Frame Limit row reaches every entry

The bug this replaces: pressing **A** repeatedly reached OFF, PRESET and CUSTOM
and stopped there, with 30/40/60/90/120 unreachable in that direction.

- Open Quick Menu → RTSS with RTSS running and the limiter **off**.
- Press **A** repeatedly and confirm the row walks the full list in order —
  OFF, 30, 40, 60, 90, 120, PRESET, CUSTOM — and then wraps back to OFF.
- Confirm each stop actually applies: check the value in RTSS itself, not only
  the row text.
- Confirm entering and leaving CUSTOM still adds and removes the **Custom FPS**
  row, and that the menu rebuilds rather than repainting on that transition.
- Press **Left/Right** on the same row and confirm it still *clamps* rather than
  wrapping, and that Right from OFF still restores the FPS RTSS was holding
  rather than stepping to 30.

## One helper payload, two products

`SteamShell-Helper.exe` now serves XFE as well, in a strictly narrower shape.
The standalone behaviour must be **unchanged**, and that is what these steps
check; the XFE half is in `WINDOWS_TEST_CHECKLIST-XFE.md`, beside this file.

**Unrun.** The `--product` argument, the input gate, and the XFE deployment
inside Setup Assistant are all new.

- After a clean Setup in shell mode, open the registered task in Task Scheduler
  and confirm its arguments begin with `--product=standalone`.
- Confirm `SteamShell-Helper.exe` reports file version **1.9.9.4** and that the
  main EXE still reports 1.9.9.0.
- Confirm the helper's own log line names `product standalone, input on,
  geometry on`.
- With Task Manager focused, confirm every builtin mapping still fires exactly
  once and the on-screen keyboard is still reachable. A helper that had silently
  taken the XFE product would do no input at all.
- Confirm elevated windows are still centred and maximised.
- Confirm the frame cap and per-game profile save still work from a standard-user
  session, and that the file on disk changes.

### Setup Assistant, XFE mode

- Run Setup in **XFE mode** as an administrator on a machine that has no
  standalone installation.
- Confirm it creates `%ProgramFiles%\SteamShell-XFE\bin`, deploys the helper
  there, and that the directory and file are Administrators-owned with a
  non-empty DACL.
- Confirm **no** `SteamShell Elevated Input Helper` scheduled task is created for
  XFE, and that the XFE logon task is still `LeastPrivilege`.
- Confirm the helper is **not** placed inside the XFE install directory.
- Break the deployment deliberately (deny the installing administrator write
  access to `%ProgramFiles%\SteamShell-XFE`) and confirm Setup still installs
  XFE, reports the helper as not installed, and logs the reason rather than
  failing the whole install.

### Both products on one machine

- Not a supported configuration, but confirm it fails safely: install standalone,
  then install XFE over it, and confirm Explorer is restored, the standalone
  helper task is removed, and the XFE helper is deployed to its own directory
  without touching the standalone one.

## The installation record must notice a move

- **Normal start, nothing to report.** Launch an installed copy and confirm the
  log contains no "Installation record:" line.
- **Fresh install.** Complete Setup on a clean PC and confirm the first start is
  silent — a new installation has nothing to disagree with.
- **Move it.** Edit `[Setup] InstallDirectory` in the settings file to a path that
  is not where the EXE lives, restart, and confirm exactly one warning naming
  both paths, and that SteamShell starts normally regardless.
- **The migration case.** Copy an installed folder to another PC, delete
  `HKCU\Software\SteamShell`, and start it. It must log the drift and still run.
- Confirm nothing branches on the result: the shell must start, register and
  behave identically whether the record agrees or not.

- **Health Check row.** Open Health Check and confirm an "Installation record"
  row. On a normal install it must read PASS. After editing `[Setup]
  InstallDirectory` to a wrong path it must read WARN and name both paths.
- On a machine where Setup has never run, the row must read INFO and say nothing
  is recorded — not WARN. A new installation is not a faulty one.

## A moved installation offers Setup, and never forces it

- **The safety property, test it first.** Edit `[Setup] InstallDirectory` to a
  path that does not exist and reboot. SteamShell must start **normally** as the
  shell. It must NOT drop into first-run Setup. This is the failure that would
  leave a machine with no shell.
- Confirm the tray menu shows "Installation moved — open Setup Assistant" at the
  top, and the tray tip ends with "— installation moved".
- Click it and confirm Setup Assistant opens with the reason in its status line.
- Complete Setup and confirm the tray entry disappears without a restart.
- Restore the correct path and confirm the entry is gone and the tip is normal.
- On a healthy install, confirm no tray entry and no status message anywhere.

## Tray icon and menu

- **Explorer restart.** Kill `explorer.exe` from Task Manager and let it restart.
  The tray icon must come back within a second or so, with its menu intact, and
  the log must record that it was re-asserted.
- Confirm the menu order is unchanged: Quick Menu, Settings, Diagnostics, then
  the desktop-mode block, then Reload Settings and Exit.
- Switch to desktop mode and back; confirm "Automatic Mouse Throughout Desktop"
  appears only in desktop mode and its tick matches the setting.
- Confirm double-clicking the icon still opens the Quick Menu.

## Upgrading a portable installation

- **The reported case.** With a portable install (SteamShell and its helper in
  one folder, registered as the shell), run a freshly downloaded SteamShell.exe
  and open Setup Assistant. It must show "Existing SteamShell installation
  detected at <that folder>" — not a blank location.
- Confirm "Choose another location" is preselected with that folder filled in,
  and that **Portable installation is ticked**.
- Apply, and confirm it does NOT ask for administrator approval and does NOT
  create anything under ProgramData. The settings must stay in the sidecar.
- Check `[Setup] InstallationMode` afterwards still reads `Portable`, not
  `Custom`.
- **Managed install, unchanged.** Repeat on a Standard install and confirm
  Standard is preselected and Portable is clear.
- Delete `RegisteredPath` by hand from a portable install and confirm Setup still
  finds the folder — that leaves the Winlogon value as the only record.

## RTSS after the shared-code move

- Toggle the RTSS overlay and frame limiter from the Quick Menu; both must report
  success or failure on screen exactly as before.
- Set a global frame cap and a per-game cap, with and without the elevated helper
  running. With the helper killed, both must fail promptly rather than freezing.
- Confirm the log's "required DLL exports were not found" line now names the DLL
  path when RTSSHooks is present but missing exports.
- Scroll the Settings window with the wheel; confirm the page scrolls, and that
  hovering the category list scrolls the LIST and not the page.
- Confirm the Quick Menu title still reads "SteamShell  ›  <page>".
- Hold the d-pad on Volume, Custom FPS and Controller Mouse Speed; each must
  repeat.

## Settings is drawn by shared code now

Both products' Settings windows are built from one table, one set of columns and
one set of row builders. Nothing below is a new feature; it is the same window
built by code it was not built by before, so the failures to look for are
visual and per-row.

- Open every category in both products. Every row must have its label on the
  left, its control at the same x on every page, and nothing clipped at the
  right edge or overlapping the row below.
- Confirm the status line does not say a layout warning was recorded. If it
  does, the log names the control and the page.
- Path rows (Steam executable, RTSS executable) must show their **Browse**
  button, and it must open a file dialog. This is the row whose controls were
  registered by hand before the move and crashed the window when they were not.
- Shortcut rows must show **Record**, and recording must write the chord into
  the field.
- Note rows must wrap fully — no clipped last line — and must disappear when you
  change category rather than staying on top of the next page.
- Change a value on every KIND of row (checkbox, dropdown, number, shortcut,
  path), Save & Apply, close, reopen. Every one must come back as set. Dropdowns
  are the ones to watch: they are saved by their text now, not their position.
- In the companion, check the Startup Programs list and the Advanced page's
  logon-task status line specifically; both were still positioned for the old
  narrower window.
- On the shell's Focus & Windows and Launcher Cleanup pages, toggle the switches
  that gate other rows — game assistance, window management, require-no-game,
  CPU/audio, download guard. The rows they gate must grey out immediately, not
  after reopening the window.

## Controller: backend, learner, and the chords

Standalone gained the RawInput backend and the Learn Controller wizard. The
first test matters most: a controller that already worked must be unaffected.

- With an XInput controller and `[Controller] Backend=Auto`, confirm nothing
  changed — mouse mode, mappings, chords, Quick Menu all as before. RawInput
  stays silent and XInput answers, which is the whole safety argument.
- Health Check must name which backend answered rather than reporting no
  controller when one is working over RawInput.
- With a non-XInput controller: set `RawInputProbe=true` and confirm the log
  reports WM_INPUT arriving. If the report length is not 16 bytes the log says
  so and points at Learn Controller.
- Run Learn Controller to completion and Save. Confirm the profile file appears
  beside the settings file, and that the pad then works without the wizard open.
- **While the wizard is open, the controller must do nothing else.** No pointer
  movement, no D-pad moving focus between the wizard's own buttons, no Quick
  Menu when it asks for L3 and R3. This made the wizard unfinishable.
- After closing the wizard, confirm a button that was held during it does not
  fire its mapping.
- **Settings chord is now LB + RB + L3 + R3, held** — no triggers. Confirm it
  opens Full Settings, and that holding the old six-button combination still
  works. The triggers were removed because a shared trigger axis makes them
  cancel out, which put Full Settings out of reach on exactly the controllers
  the backend was added for.
- With the probe off, confirm the log is NOT filling with "RawInput probe: N
  WM_INPUT message(s)". That line is every two seconds when it is on.


## The View button's own action

Off by default here, unlike the companion. Enable it in **Settings → Steam**
first; the tap and hold switches beside it are on.

- **Hold View and press A. No Steam shortcut may fire.** This is the whole
  safety mechanism: any other input during the hold marks the press as a
  modifier use and its action is dropped on release. Repeat with the triggers
  and with a stick pushed, which also count.
- With Steam in front, tap View and confirm the Steam menu opens; hold it and
  confirm Quick Access opens instead.
- In a game, tap View and confirm **nothing** happens — the game keeps its own
  use of the button — then hold and confirm the overlay opens. The in-game hold
  threshold is deliberately longer (1000 ms against 500 ms) because View is
  commonly the scoreboard button.
- Turn automatic mouse mode on and confirm no action fires when it engages or
  releases. Mouse mode is expressed as a virtual View hold, and the action must
  read the physical button only.
- Hold View, open the Quick Menu or a recovery dialog, close it, release View.
  No action may fire: a press made to reach a dialog is not a press meant for
  Steam, and the release would otherwise report a hold as long as the dialog
  was up.
- Turn the master switch off and confirm the button reverts to being purely the
  mapping modifier.

## The controller keeps working when XInput moves it

- Launch a game through Steam Input, which adds a virtual pad and shifts the
  physical one. **The controller must keep working.** Confirm the log records
  `XInput controller moved from slot N to slot M`.
- Unplug the controller and confirm `XInput controller disconnected from slot N`,
  then reconnect and confirm it is found again without changing any setting.
- With no controller at all, confirm the controller test panel says "No
  controller detected on any XInput slot" rather than naming the configured
  index — the slot is discovered now, so the configured one is not the answer.
- Health Check must report the slot that ANSWERED, and name the configured one
  alongside it when they differ.

## Settings the window itself was breaking

- Open **Focus & Windows** and confirm **Maximize width threshold (%)** reads
  `30`, not `0.3`. Press Save with nothing changed and confirm it saves. This
  field is stored as a fraction and shown as a percentage, and only the save
  half of that conversion used to exist, so the window blocked its own Save on
  every open.
- Open the Quick Menu over the Settings window, change a setting from the menu,
  then press Save in Settings. **The menu's change must survive.** Settings
  writes every field it holds, so the stale control used to overwrite it.
- With **Hide the cursor after inactivity** on, open Settings and sit still past
  the hide delay. The cursor must stay visible. With a controller connected,
  watch for a blink rather than a disappearance — that was the poll and the
  watch fighting each other.
- In **Settings → RTSS**, switch **Overlay control mode** between Toggle and
  Separate and confirm the shortcut rows below grey and un-grey correctly,
  including on first open. Repeat for **Frame limiter control mode**.

## Settings pages and layout

- Confirm the category list reads: General, Startup & Splash, Startup Programs,
  Controller & Cursor, Steam, Focus & Windows, RTSS & Performance, Launcher
  Cleanup, Advanced & Logging — nine pages, each of which opens and draws.
- The new **Steam** page holds the three Steam shortcuts, the Big Picture window
  title, and the five View button rows. Confirm each saves and survives a reload.
- On **Startup Programs**, confirm the seven buttons form three even columns
  rather than two ragged rows, and that the second row lines up with the first.
- On **Advanced & Logging**, confirm the four shell-registration actions are the
  first two rows. **Permanently Restore Explorer must be easy to find** — it is
  the escape hatch, and it used to be the tenth of nineteen buttons.
- Open every page in turn and confirm the layout audit reports no issues in the
  log: no control crossing the content boundary, and no two controls overlapping.

## Controller learner, after the DirectInput audit

Run these with a pad whose gyro is live — an 8BitDo in DirectInput mode is the
case they were written from.

- **The wizard must not ask for the Guide/Xbox button.** Confirm the step list
  goes ... L3, R3, D-pad up. Pressing Guide at any point should do whatever
  Windows normally does and not disturb the wizard.
- Keep hands off during both "hands off" countdowns. Then confirm every button
  step detects its button. This is the failure that looked like the wizard
  ignoring the controller.
- Now deliberately **hold A during the "hands off — do not touch anything yet"
  countdown**, then continue. The A step should fail, and the log must say
  `byte N moved for A but every changed bit is masked as rest noise`. Press
  Start Over and confirm a clean run works.
- Confirm the rest-sample line names the byte offsets, e.g.
  `12 of 34 bytes changed during rest (bytes 14,15,...)`. Button bytes appearing
  there means something was held.
- **Press Start Over during a pause** — right after an axis completes, or while
  "let go of everything and we will try this one again" is showing. The wizard
  must restart cleanly with no error dialog. Repeat with Close instead of Start
  Over, then reopen immediately.
- On a gyro pad, watch the trigger steps. If a trigger cannot be told apart from
  the motion sensor the wizard must **skip it and carry on**, logging
  `NOT retrying with them included`. It must never bind a trigger to a motion
  byte — the symptom of that is the rest check reporting `LT=255` with nothing
  touched.
- Complete a profile and Save. Confirm no `.update-<pid>.tmp` file is left beside
  `<settings>-Controllers.ini`, and that the profile is complete: report length,
  buttons, axes and hat all present.
- Save a profile on a machine that has never had one, so the profile file does
  not exist yet. It must be created rather than failing.
- Provoke the rest check to fail (a deliberately bad profile), answer **Yes** to
  deleting it, and confirm the profile is deleted and the shell reloads —
  **no "Item has no value" error box.**
- Read the wizard end to end as a first-time user. No byte numbers, masks or
  `active-high` should appear on screen; all of that belongs in the log.
