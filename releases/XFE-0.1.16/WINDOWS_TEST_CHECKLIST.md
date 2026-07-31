# SteamShell XFE Windows test checklist

For release **0.1.16**, locked at `releases/XFE-0.1.16/`.

Everything under *Additions since 0.1.14* arrived in 0.1.15. 0.1.16 adds the
RTSS frame-cap input changes described in *Custom FPS stepping* below.

Test this separately from the locked SteamShell 1.5.0 build.

## Additions since 0.1.14

### Frame Limit row (replaces the separate Frame Limiter row)

- Cycle Left/Right through **Off · 30 · 40 · 60 · 90 · 120 · Custom** and confirm RTSS reflects each value.
- **The preset must survive an off/on round trip.** Set 72 via Custom, cycle to `Off`, press Right, and confirm it
  returns to **72** rather than 30. "Off" clears RTSS's limiter flag and must never write `0` over the value.
- Press Left repeatedly while already on `Off` and confirm the flag write and its status message do not repeat.
- Select `Custom` from `120` and confirm the frame rate does not change — Custom only reveals the row.
- On Custom FPS, hold Right and confirm the step escalates 1 → 5 → 10; after a pause a single press moves by 1.
- Confirm every change targets the **global** profile and no per-game profile is touched.
- **Save Limit to Profile:** confirm the row shows the foreground game's executable, requires two presses, and
  that RTSS then shows the value on that game's profile **with its other settings unchanged**. Over Big Picture
  with no game running it must read `No game in foreground` and do nothing.
- Run it once against a game with no existing profile and confirm a new `.cfg` appears in RTSS's `Profiles`
  folder. If not, `SaveProfile` does not create profiles here and the row is silently doing nothing.

### Learn Controller with a motion-sensor pad

Confirmed on an 8BitDo Ultimate 2 in DInput mode (34-byte report, ~1 kHz, twelve free-running motion bytes).

- Run the wizard and confirm all four **sticks resolve**. Before the fix they failed repeatedly with
  `byte 22 u8 rests at 0% of range`, because motion axes out-travelled the real stick on every step.
- Confirm **RT does not bind to a motion byte**. A trigger legitimately rests at an end of range, so it had no
  sanity check and was the one control that silently learned wrong.
- Check the log's `Learn: analogue bytes = …` line and confirm the axes that resolved are the low-numbered stick
  bytes, not the high-numbered motion ones.
- Press **Skip** on the final step. Confirm the wizard finishes and saves without throwing `Invalid index`.
- Delete the profile (`Ctrl+Alt+Shift+D`) and confirm the built-in layout returns.

> If a profile was saved before this fix, **delete it first.** A trigger bound to a motion byte feeds continuous
> phantom input.

## Test these first — the 0.1.9 regressions

These all failed on real controllers and displays in 0.1.8.

Everything below has a dedicated section later. This is the short list of what
actually failed on real controllers and displays, so a build can be rejected
quickly:

1. **Quick Menu, first open.** Fully visible, rounded on all four corners. A
   clean rounded edge cutting through a row means the region is clipping it.
2. **Cursor.** Opens hidden, stays hidden across page changes.
3. **Settings.** Comes to the front on its own from the chord, the hotkey, and
   the Quick Menu — no task switcher.
4. **Audio row.** Shows a percentage on the main page, matching the Audio page.
5. **Learn Controller.** Pressing B must not close it. A nudged stick must not be
   learned as L3. Every saved axis must be `u16le` or `u8`, and each stick's
   neutral near half of full scale.
6. **After saving a profile**, the pointer must be steady. `Ctrl+Alt+Shift+D`
   must remove the profile without needing the pointer.
7. **Learn Controller, sticks.** Each of the four stick steps must resolve. If
   any reports "not detected" no matter how far the stick is pushed, stop — that
   is the 0.1.9 self-claiming bug, and the log now names the actual reason.
8. **Dialogs must be visible.** Open Settings, then Startup Programs → Add
   Program: the file picker must appear in front. Change something and press
   Close: the "Save changes before closing?" box must appear in front. A dialog
   that has the keyboard but cannot be seen reads as a frozen application.
9. **Task Switcher.** Steam Big Picture must appear even when its current
   steamwebhelper window is marked `WS_EX_TOOLWINDOW` without
   `WS_EX_APPWINDOW`; unrelated overlay/tool windows must remain excluded.

## Build and launch

- Double-click `Build-SteamShell-XFE.cmd` with AutoHotkey v2.0.26 64-bit
  installed. Confirm the result remains visible until a key is pressed.
- Confirm static validation passes.
- Launch as a standard user; do not enable **Run as administrator**.
- Confirm a second launch leaves the original process running.
- Confirm `SteamShell-XFE.ini` and `SteamShell-XFE.log` appear beside the EXE.
- **Check the startup lines first.** The INI is read from beside the executable,
  so editing a copy elsewhere has no effect and looks like a broken feature:

```text
Settings file: C:\...\SteamShell-XFE.ini
Resolved: Backend=auto, DiagnosticLogging=false, RawInputProbe=false, ...
```

## AnyFSE lifecycle

- Configure Steam Big Picture as the AnyFSE Home app.
- Add SteamShell-XFE.exe as an AnyFSE startup app, **or** use the logon task and
  remove it from AnyFSE so it is not started twice.
- Turn **Exit FSE when Home app exits** off.
- While Xbox FSE is active, confirm heartbeat lines continue for at least a
  minute, proving the companion survives rather than being suspended.
- Close and relaunch Steam; confirm the same companion PID survives.

## Startup splash

- Leave **Startup Splash** disabled and confirm startup is unchanged.
- Enable **Black**, set a short duration, and confirm the primary display is
  covered immediately and fades back to Xbox FSE without taking focus.
- Select a valid video and `mpv.exe`, enable **Video**, and confirm no desktop or
  Xbox FSE frame flashes before MPV becomes visible.
- With **Play the entire video** enabled, confirm the curtain closes when MPV
  exits. Set a short safety timeout and confirm it still closes if MPV hangs.
- Disable full-duration playback and confirm `DurationMs` closes the video.
- Temporarily configure a missing video and then a missing MPV executable;
  confirm each falls back to Black and records the reason in the log.
- Exit or choose **Disable** from the tray while the curtain is active; confirm
  XFE closes only the MPV process it launched and removes the black cover.
- On an HDR television, leave **Force MPV to SDR** enabled and confirm the TV
  does not switch HDR modes for the startup clip.

## Controller input backend

Leave **Input backend** on **Auto**. It reads RawInput inside Xbox FSE and
XInput on the desktop; neither works in both places alone.

`rawinput` and `xinput` are diagnostic settings with **no fallback** — input is
dead wherever that source is silent. That is deliberate: it is the only way to
prove which backend is actually carrying input. Do not leave either one set.

The built-in RawInput layout understands the **ROG Ally controller**. Other
byte-aligned HID gamepads must be taught once with **Settings → Controller &
Cursor → Learn Controller**. XInput-only/XUSB pads that publish no HID gamepad
collection cannot be learned.

On the desktop:

- Press every button; log lines should read `Controller input [xinput]`.
- Confirm the Quick Menu, mappings and controller mouse all work.

Inside Xbox FSE:

- Confirm `RawInput: registered for background gamepad/joystick reports`.
- Confirm `RawInput: decoding reports from device 0x...` on the first press.
- Press every button; log lines should read `Controller input [rawinput]`.
- **Confirm View, Menu, L3 and R3 all register** — the buttons XInput never sees
  inside FSE, and the reason RawInput exists.
- Hold **L3 + R3**: the Quick Menu opens.
- Hold **LB + RB + L3 + R3**: Settings opens. The triggers are deliberately not
  part of this chord — RawInput reports them on one combined axis where they
  cancel out, so a chord requiring both can never be detected.
- Confirm LT and RT still work individually for mapped actions.
- Confirm the right stick moves the pointer correctly on both axes; the HID
  report has Y inverted relative to XInput and the decoder compensates.

Then leave FSE and confirm input still works on the desktop, proving the
handover works in both directions.

## Learn Controller and saved RawInput profiles

Run this with at least one non-Ally HID gamepad. If it already has a section in
`SteamShell-XFE-Controllers.ini`, move that file aside before the test and
restore it afterwards if needed.

- Inside Xbox FSE, open **Settings → Controller & Cursor → Learn Controller**.
- With two controllers connected, release both during the initial idle-input
  measurement, then press and release one button on only the target controller
  when the prompt changes.
  Confirm the wizard identifies that device rather than whichever pad happened
  to publish the first idle report.
- Release everything when prompted. Do not rest a thumb on either stick while
  the neutral baseline is measured.
- **The first step is an analogue scan.** Roll both sticks fully around and sweep
  both triggers, then let go. Confirm the log reads
  `Learn: analogue bytes = ...` and lists the stick/trigger bytes but **not** the
  button or hat bytes.
- **On the L3 and R3 steps, deliberately move the stick as you click it in.** It
  must still learn the stick-click bit, not the stick movement. At rest an axis
  low byte is 0x00, so a nudge sets bits that were clear at rest — the exact test
  a button has to pass — and these two steps cannot be done without touching the
  stick.
- If the analogue scan is skipped, expect that failure to return; the scan is what
  prevents it.
- **Press B during a prompt.** Nothing must happen. The controller is inert while
  the wizard is open — B is normally mapped to Escape, which used to close the
  wizard outright. Confirm A, X, Y and Start also do nothing (they are normally
  Enter, touch keyboard, Game Bar and Start menu), and that holding L3 + R3 does
  not raise the Quick Menu on top.
- **Watch the `N reports seen` counter** on every step. It separates the two ways
  a step can appear stuck: zero means the controller is silent (wrong backend, or
  outside FSE), while a rising count means reports are arriving and being
  rejected.
- The **Guide** step is optional and uses a shorter window. On the Ally the button
  is swallowed by Windows and never reaches the report, so confirm the step gives
  up on its own rather than blocking the D-pad steps that follow it.
- **Press each D-pad direction squarely.** A diagonal reads as its own hat value,
  which breaks the set. Deliberately press one direction diagonally and confirm
  the wizard detects the bad set, says so, and **retries the four directions once**
  rather than saving a broken D-pad.
- Confirm a clean run produces either a `Hat` line or four distinct D-pad button
  entries — never a mixture, and never two directions on the same bit.
- Complete every available button and D-pad prompt. A control the device lacks —
  a Guide button hidden by its driver, say — must **time out and skip itself**,
  since the controller cannot reach the Skip button. **Skip**, **Start Over**,
  **Save** and **Cancel** remain usable by mouse or touchscreen.
- Each digital step must advance from the single press report; holding a button
  or D-pad direction must not be required.
- **Then hold one button down deliberately** past the point of detection. The
  detail line must read `-- now let go`, and the wizard must NOT advance until you
  release. A blind timer here let a still-held button answer the next prompt and
  be learned as that button's bit.
- After the release-gated advance, confirm no two logical buttons share a physical
  bit in the saved profile.
- As each step advances, confirm the detail line shows `Detected:` followed by the
  logical control, report byte, bit mask, and polarity. The next prompt must
  retain it as `Last detected:` rather than clearing the evidence.
- For each stick prompt, move smoothly to the requested edge, then release it.
  For each trigger, squeeze smoothly to full travel, then release it. Confirm
  the wizard waits while the input is held and advances only after it returns to
  rest; the prior input must not appear in the next reading.
- Save. Confirm `SteamShell-XFE-Controllers.ini` appears beside the executable
  and contains the target VID/PID section, `ReportLength`, `Buttons`, `Axes`,
  `IdentityFallback=device`, and either `Hat` or four D-pad button entries.

**After saving.** A profile with a mis-learned axis reads as permanently
deflected and sends the pointer across the screen, which also makes it hard to
reach the UI to undo.

- Confirm every learned axis is `u16le` or `u8` in the saved INI. **A `u16be`
  entry means the learner regressed** — HID multi-byte fields are little-endian.
- Confirm each stick's `neutral` is near half of full scale (about 32768 for
  `u16le`). A stick rests at its centre; anything else is the wrong field.
- Confirm no two sticks share a byte offset. LT and RT sharing one is fine and
  correct for a combined trigger axis.
- Watch for `Learn: <axis> rejected -- byte N rests at X% of range` in the log.
  That is the centre check firing, and the step retries.
- After Save, leave the controller alone. Confirm the log reads
  `Controller profile: rest check passed`.
- If it reads `rest check FAILED`, a dialog names the offending axes and offers to
  delete the profile. Accept it and re-learn, moving each stick fully to the
  prompted edge and letting it return to centre.
- Confirm **Ctrl+Alt+Shift+D** deletes the profile without needing the pointer,
  and that **Settings → Controller & Cursor → Delete Learned Profile** does too.
- After deletion, confirm the built-in layout is back and the pointer is steady.

**When Windows will not identify the device.** Measured on the ROG Ally X: all
three identity routes returned nothing and Save refused. That now falls back to a
profile keyed on report length.

- If Save reports a length fallback, confirm the section is named `LEN_<n>` with
  `IdentityFallback=length`, and that the profile still activates.
- Read the `RawInput identity: ... unidentifiable` line in the log and record
  what each of the three routes returned. That line is the only way to find out
  why the Ally withholds its metadata.
- A length-keyed profile is matched on report length alone. That is exactly what
  the built-in layout does, so it is no less safe — but confirm a second 16-byte
  controller is not silently decoded with it.
- Confirm the wizard closes without restarting the companion, and the log reads
  `with learned profile 'VID_..._PID_...'` on the next target-controller report.
- Press every button and all eight D-pad directions. Confirm no two logical
  buttons fire from the same physical control.
- Move both sticks slowly through their full range. Confirm X directions and
  XInput-style Y directions are correct, centre is neutral, and full travel
  reaches the expected pointer/navigation speed.
- Test LT and RT independently. If the hardware uses separate axes, both should
  remain readable together. If it uses one shared axis like the Ally, each
  should work alone and cancel when both are held.
- Reconnect the controller and repeat inside FSE. Then sleep/resume and confirm
  the same saved profile is selected after RawInput adopts the new device
  handle.
- Start the wizard again and cancel it halfway through. Confirm the existing
  profile remains untouched.
- Temporarily change a saved axis offset beyond `ReportLength`, reload, and
  confirm the invalid field is ignored without crashing. Restore the file.

For development-only algorithm coverage, run:

```text
python Test-ControllerProfiles.py
```

It exercises 8-bit axes, 16-bit little- and big-endian axes, independent and
shared triggers, measured travel, and active-low buttons without controller
hardware.

## Elevation

The logon task runs at normal privileges by design. If you ever run the
companion elevated, expect this and do not treat it as a new bug:

- Open the Quick Menu over Steam and press the D-pad. **While elevated, Steam
  navigates underneath the menu** — it cannot inspect an elevated foreground
  window, so it never registers that it lost focus.
- Confirm the log's startup line reports `standard user` in normal operation.

## Steam actions

Requires `MenuShortcut` and `QuickAccessShortcut` to be bound inside Steam. The
log records exactly what was sent, so check there before assuming a failure is
the companion's.

With **Steam in front**:

- Quick Menu → Steam Menu sends `Ctrl+1`; the row displays that shortcut.
  **Confirm it reads `Ctrl+1`, not `CtrlShift+1`.**
- Quick Menu → Steam Quick Access sends `Ctrl+2`.
- Tap **View**: Steam menu opens. Hold past 500 ms: Quick Access opens.

With a **game in front**:

- Quick Menu → Steam Menu sends a held `Shift+Tab` chord and the row shows it.
- Tap **View**: nothing from the companion; the game still receives the button.
- Hold **View** past 1000 ms: the Steam overlay opens through the same held-key
  sender.
- Confirm both actions write `Steam overlay send: Shift + Tab,
  foreground=<game>.exe` to the log. If the foreground is wrong, investigate
  focus restoration; if the game is elevated, the normal-privilege companion
  cannot inject into it.

Tap and hold switch independently (Settings → Steam, or Quick Menu → Settings):

- Turn **View tap action** off. Tap View with Steam in front: nothing happens.
  Hold View: Quick Access still opens.
- Turn **View tap** back on and **View hold** off. Hold View past the threshold:
  **nothing happens.** A long press must *not* fall through and fire the tap
  action instead.
- Turn the master **View button Steam actions** off: neither fires.

Modifier interaction, which must not regress:

- Hold **View** and press a mapped button: the mapping fires and **no** Steam
  shortcut is sent.
- Hold **View** and move a stick: no Steam shortcut is sent.
- Open the Quick Menu while View is held, then release: no shortcut fires.
- In a real game, hold and release **View without moving a stick** and confirm
  the overlay triggers. Stick movement suppresses the action by design.

## Window layout, scaling, and centring

Run at the display scaling actually in use, then repeat at one other scaling.
Windows reports a GUI's size in logical units before it is shown but physical
pixels afterwards, so centring is computed from the size measured after the
window is really on screen.

- Note Windows Settings → System → Display → Scale before testing.
- Enable `Controller.DiagnosticLogging` and read the `Center:` line:
  `measured` must be the **physical** size, not the requested one.
- Open the Quick Menu: centred, rounded corners, no drawn border.
- **Watch the moment it appears.** It must arrive already centred with rounded
  corners — no visible jump into position, and no square-cornered frame first.
  The whole calculation now happens while the window is hidden.
- Navigate between pages and watch the resize: the window must not appear at its
  new size in the old position for a frame. Resize and move are one operation.
- Confirm the selected row is a filled bar and that **only one row is
  highlighted** as you navigate — a stale highlight means backgrounds are not
  repainting.
- Visit every page; confirm no row is cut off and the window ends just below the
  content rather than carrying a large empty margin.
- Navigate between pages: the window resizes and re-centres **without blinking**
  and without stealing activation.
- Open Settings; confirm centred, all eight categories, no overlapping controls.
- On multi-monitor, move the foreground app to the second monitor and confirm
  both windows open there.

## Cursor, window sizing and focus (regressions with one shared cause)

AutoHotkey v2 defaults mouse coordinates to **Client**, not Screen. Every
`MouseGetPos` here wants an absolute position, so this is now set explicitly.

- Open the Quick Menu and **do not touch the mouse**. The cursor must hide and
  **stay** hidden while you move between pages. It previously reappeared on every
  page change: the window moved, the coordinate origin moved with it, and the
  unmoved pointer read as having moved.
- Confirm moving the mouse still brings the cursor straight back.
- On a multi-monitor setup, confirm the Quick Menu still opens on the monitor
  holding the foreground app.

Window sizing:

- Visit every Quick Menu page and confirm **none is cut off** at any display
  scaling. The window is sized by `Gui.Show` so the frame and the controls inside
  it are scaled by the same thing; an earlier version predicted the physical size
  from `A_ScreenDPI` and could size the window wrong.
- Repeat at a second display scaling, and on a TV at 4K if available.
- If a page is still clipped, enable `Controller.DiagnosticLogging` and read the
  `Center:` line — it reports requested, measured and final sizes.

Focus:

- From the Quick Menu choose **Settings → All Settings…**. The Settings window
  must come to the **front on its own**, without the task switcher. Closing the
  Quick Menu normally hands the foreground back to Xbox FSE, which then wins the
  race against the window being opened.
- Confirm closing the Quick Menu by any other route still returns focus to
  whatever was in front.

## Quick Menu drawing on a large/high-DPI display

Measured failing on a 4K television: the first appearance was cut off at the
bottom and had square corners, while every page change after it was correct.

- Open the Quick Menu and check the **first** appearance: fully visible including
  the bottom status line, and rounded on all four corners.
- Check the log for `Quick Menu: content needed Npx more than the window had`.
  That line means the safety net fired — the window is correct, but the height
  arithmetic still disagreed with the layout. It reports the client height and
  where the status line actually ends, which is the evidence for why.
- **A clean rounded edge cutting through a row means the region is clipping the
  window, not that the content overflowed.** Corners are now applied only to a
  visible window for exactly this reason; a hidden window can report a wrong size,
  and `WinSetRegion` clips to whatever it is given.
- Visit every page and confirm none is clipped.
- Repeat at a second display scaling.

## Quick Menu value column

The value column is right-aligned, so text that is too long is clipped from the
**left**. Anything that must remain readable has to be last in the string.

- On the main page, the **Audio** row must show the volume as a percentage at the
  far right, after the output device name.
- Compare it with the Audio page's **Volume** row: both come from the same
  function and must agree. A main-page row reading `%` or a bare digit means the
  column is clipping, not that the volume is unreadable.
- Try an output device with a long name and confirm the percentage still shows.

## Quick Menu behaviour

- Hold L3 + R3 for 700 ms; confirm it opens once.
- **Confirm the cursor hides** when the menu opens, and reappears if the mouse
  moves.
- Confirm the bottom line shows the button hint when idle, transient status
  after an action, and clears itself after a few seconds.
- Select **Sleep** once without confirming: the status line must show the
  "select again within 5 seconds" prompt and must not clear before it expires.
- **Keyboard:** arrows navigate, Left/Right adjust, Enter/Space select,
  Backspace/Escape back, Delete closes a window, Home/End jump. Confirm arrow
  keys do **not** get swallowed when the menu is closed.
- `Ctrl+Alt+Shift+P` opens Settings, as does `Ctrl+Alt+Shift+S`.

## Quick Menu Settings page

- Open Quick Menu → Settings; confirm seven toggle rows and **All Settings…**.
- Flip a row with **A**, and another with **Left/Right**: both must work.
- **Confirm the row's value updates immediately** and the status line names it.
- **Open the INI and confirm the value was written**, without pressing Save
  anywhere. A toggle that only changes the runtime value looks identical until
  the next restart, which is when it would silently revert.
- Enable **Game Focus Lite** from the Quick Menu with no other assist feature on,
  and confirm the log records the assist timer starting. Disable it again and
  confirm the timer stops — the timer only exists while something needs it.
- Open the full Settings window afterwards and confirm the checkboxes match what
  the Quick Menu shows.
- **All Settings…** opens the Settings window.

## Settings window layout and focus

- Open Settings from the **chord**, from **Ctrl+Alt+Shift+S/P**, and from the
  Quick Menu. In all three cases it must appear **in front on its own**, with no
  task switcher. It is always-on-top for this reason: Xbox FSE is a fullscreen
  window, so a normal window can hold focus and still render behind it.
- On **Controller & Cursor**, confirm **Delete Learned Profile** does not overlap
  the "Park after returning to Steam" checkbox.
- On **Steam** and **Advanced**, confirm no explanatory paragraph is cut off at
  the bottom.
- Visit all eight categories and confirm nothing is clipped or overlapping. The
  requested window is 920x660; page content stops above the button bar at y610.
- At each display scale, confirm the visible outer window is vertically centred
  in the monitor work area. Its title bar and bottom edge should have equal
  usable space; the bottom must not extend below the taskbar or visible desktop.

## Settings categories

- Confirm the sidebar lists eight categories, including **Steam** and
  **Startup Splash**.
- **Cycle with LT/RT all the way round in both directions and confirm every
  category is reachable**, including Assist and Advanced. The wrap point was
  previously hard-coded to 4 and those two could not be reached at all.
- On **Steam**, record the three shortcuts and confirm they display correctly.
- Save, restart, and confirm all Steam values persisted.
- On **Controller & Cursor**, confirm both controller buttons end above the
  fixed Save/Close footer and no helper text is clipped underneath them.

## Display picker

- Resolution, Refresh rate, and Scale are three Left/Right rows; there is no
  paging.
- On an HDR-capable primary display, confirm HDR initially matches Windows
  Settings. A toggles the known state, Left explicitly selects Off, and Right
  explicitly selects On; repeating Left while already off or Right while already
  on must leave the state unchanged rather than toggling it.
- On a non-HDR primary display, confirm the row says `Unsupported`. If the
  Advanced Color query fails, confirm it says `Unavailable`; neither case may
  send the old Win+Alt+B shortcut.
- Confirm Scale begins on the percentage currently shown by Windows Settings
  for the primary display and offers only normal Windows scale percentages.
- **Cycling any of the three rows must not change the display.** Only Apply does.
- Change resolution, refresh, and Scale together, then Apply. Confirm all three
  change as one transaction.
- Keep the Quick Menu open while Scale changes. After Windows settles, confirm
  the same Display & HDR page re-centres itself without navigating Back or
  reopening the menu, and that selection remains on Apply for confirmation.
- Apply, do not confirm, and verify resolution, refresh, and Scale all
  automatically revert.
- After the automatic revert, confirm the open Quick Menu re-centres again
  without manual navigation.
- Confirm the Apply row counts down (`Select to KEEP (12s)`) during the window.
- Repeat and select Apply again to keep all three settings.
- On a multi-monitor system, confirm only the Windows primary display changes,
  even when the Quick Menu was opened over an application on another monitor.
- If Scale reads `Unavailable`, confirm resolution, refresh, and HDR still work
  and retain their existing safety behavior; save the diagnostic ZIP and record
  the Windows build and display driver.
- Exit the companion during a pending transaction and confirm its exit handler
  restores the old resolution, refresh, and Scale.

## Task Switcher

- Confirm the row shows a live window count.
- **A** switches to a window. Check the log for `activated` vs
  `could not activate` — FSE may re-assert its own window.
- **X** closes; **X again within 5 s** force-closes, with the status line
  explaining the escalation.
- Confirm no invisible or phantom UWP entries appear in the list.

## Settings and dialogs

- Open Settings and confirm right-stick pointer, RB click, D-pad, LT/RT category
  switching and Y save all work.
- **Every dialog must open in FRONT of the Settings window.** All our windows are
  topmost, and a non-topmost dialog cannot rise above its own topmost owner — it
  appears behind, holding the keyboard, looking like a freeze. Check each:
  Browse (RTSS), Startup Programs → Add, "Save changes before closing?", Restore
  Defaults in the mapping editor, and every Learn Controller message box.
- Check the same **inside Xbox FSE**, not only on the desktop. This is where the
  obvious fix — dropping the owner's topmost bit — would fail instead, by putting
  Settings and the dialog together behind FSE.
- **Open a file picker (Browse, or Startup Programs → Add) and confirm the
  controller can both move the pointer AND click.** Clicking was previously
  disabled while a dialog was open.
- Confirm LT/RT category switching and Y save do **not** act while a picker is
  open.
- Record an RTSS shortcut and a controller shortcut; save, restart, retest.
- Confirm displayed shortcuts read correctly: `Ctrl+Shift+O`, `Ctrl+Alt+Tab`,
  `Alt+F4` — never doubled `Shift`.

## Logon task

Test this **on battery, undocked**. That is the case the previous version got
wrong, and testing it plugged in will not reproduce the failure.

- Settings → Advanced → **Create Logon Task**; approve the UAC prompt.
- Press **Check Logon Task** and read the log. Confirm the definition shows
  `Power Management` **without** "Stop on battery / no start on battery", and an
  execution time limit of `Disabled`.
- Reboot **on battery** and confirm SteamShell XFE is running afterwards. The
  log should show a startup line roughly 10 seconds after logon.
- Reboot again plugged in and confirm the same.
- Start docked, then **undock while running**, and confirm the companion is not
  terminated — `StopIfGoingOnBatteries` would otherwise kill it.
- If it still does not start, press **Check Logon Task** and read **Last Run
  Time** and **Last Result** in the log before changing anything else.
- Confirm the task appears under Task Scheduler Library as `SteamShell-XFE`,
  running as your own account at **least privilege**, not "Highest privileges".
- **Remove Logon Task**, reboot, confirm it does not start, and confirm the task
  is gone from Task Scheduler.

## Startup programs

- Add a program, save, restart the companion, confirm it launches after the
  delay.
- Add a second and confirm the stagger.
- Restart with the program already running and confirm it is skipped.
- Remove an entry, save, and confirm it does not return on reload.

### Launch window mode (`WindowMode`)

Test each mode with a program that draws a window — Notepad is enough, and a
program with a splash screen (a launcher, RTSS) is the case that actually
matters.

- **Normal** — the window appears as it normally would.
- **Minimized** — it starts on the taskbar and nothing appears over Xbox FSE.
- **Hidden** — no window at all, and `ProcessExist` still finds it running.
- **Hidden, with a splash screen.** This is the real test: the splash appears
  after the initial show state was applied, so only the post-launch sweep can
  catch it.
- **Hidden, with "Start them as the normal user" ON, running elevated.** On this
  route explorer.exe starts the program and picks the show state itself, so the
  sweep is the *only* thing enforcing the mode. If Hidden works everywhere else
  and fails here, the sweep is the part that is broken.
- **Open the program yourself a minute after startup and confirm it stays open.**
  Enforcement is bounded to a few seconds precisely so it cannot fight you later.

## Assist features

Enable one at a time, in this order.

**Launcher Cleanup Lite** (no focus changes, so it cannot conflict):

- With a launcher open and no game running, confirm it closes after the settle
  time, and the log records it.
- Start a game and confirm cleanup does **not** run while it is detected.

**Game Focus Lite:**

- Confirm a game returns to the foreground when something steals it.
- Confirm it does **not** fight Xbox FSE surfaces.

**Steam Assist Lite** (enable last, alone):

- Watch for it duplicating or fighting AnyFSE's own return-to-Home behaviour.

**The Xbox FSE task switcher, with Steam Assist Lite on.** This is the case the
overlay check exists for, and the shipped process list is a guess that may not
match your Windows build:

- Open the FSE task/application switcher and leave it open for ~10 seconds.
- **It must stay open.** Previously Steam Assist took focus back and dismissed
  it, because the switcher never owned the foreground.
- Check the log for `Assist: suspended, shell overlay on screen (...)`. That line
  names the window that matched, and is the proof the guard fired.
- The match should read `explorer.exe [XamlExplorerHostIslandWindow] foreground`
  — the identity measured on 2026-07-25.
- **If the switcher is still dismissed, the default list does not name it.** Run
  **Settings → Advanced → Probe Screen**, open the switcher during the six-second
  countdown, then read the log: it lists **every top-level window** with process,
  class, size, topmost/foreground state, and the reason any window was excluded
  from the assist inventory. Add the `class:` it reports to
  `[Assist] ShellOverlayProcesses` and retest. Prefer the class over the exe —
  `explorer.exe` would also match the desktop, taskbar and File Explorer.
- Confirm the suspend line is rate-limited rather than one entry per tick.
- With the switcher closed, confirm assistance resumes.
- Turn `SuspendOnShellOverlay` off and confirm the old behaviour returns — that
  is what proves the guard is the thing making the difference.

**Probe Screen itself:**

- Run it from Settings → Advanced: the Settings window hides for the capture and
  **comes back afterwards**, and does not appear in its own inventory.
- Confirm it logs a foreground line, a window count, one line per window, and a
  final overlay-match line.
- **Confirm nothing on screen changed** — the probe reads only.

For all three:

- **Open the Quick Menu, Settings, the mapping editor, a shortcut capture and a
  file picker in turn, and confirm assistance never steals focus from any of
  them.** Assistance suspends whenever a SteamShell XFE window is in front.

## Utilities

- Cycle audio outputs, adjust volume, toggle mute.
- Confirm the state-aware HDR row has passed the Display picker tests above.
- Stop RTSS, open **RTSS & Performance**, and confirm **Start RTSS** appears.
  Select it and verify RTSS launches minimized and the page changes to the live
  Overlay and Frame Limiter rows. Test a missing executable path and confirm the
  menu reports it without attempting a blind shortcut.
- With RTSS running, confirm the **RTSS Settings** row says only **Running**,
  without repeating Overlay/Limiter state. Select it and confirm SteamShell XFE
  Settings opens directly on **RTSS & Performance**.
- Return to the main Quick Menu and confirm **RTSS & Performance** shows the
  glanceable **Overlay On | Limiter On** summary with the actual states, without
  clipping at the normal Quick Menu width.
- In SteamShell XFE Settings → **RTSS & Performance**, confirm the DLL
  explanation is readable and **Use RTSSHooks64.dll…** defaults on. Turn it off,
  save, and confirm the main summary says **Running | Shortcuts**, the RTSS page
  uses the configured shortcut rows/cap label, and no live state is claimed.
  Turn it back on and confirm the live rows return.
- With RTSS running, open **RTSS & Performance** and confirm Overlay and Frame
  Limiter show the same global On/Off state as RTSS. Verify A toggles each
  state, Left turns it off, and Right turns it on.
- Set distinct `FramerateLimit` values in RTSS's global profile and the test
  game's application profile. Open the Quick Menu over the game and over an
  application without a profile; confirm the limiter row shows the applicable
  FPS value and correctly shows **Uncapped** when it is zero.
- Repeat with RTSS running elevated and SteamShell XFE running as its normal
  standard user. Confirm each accepted change updates the row; if Windows blocks
  the write, confirm the menu warns rather than showing the requested state.
- Confirm “Limiter On” is not mistaken for an active cap: set the applicable
  RTSS profile to zero and verify the menu still reports the global limiter
  switch, while the game remains uncapped.
- Temporarily point the RTSS path at a copy/install without
  `RTSSHooks64.dll`; confirm the menu reports state unavailable and the
  configured overlay/limiter shortcuts still work as the fallback.
- Verify touch keyboard and classic OSK.
- Open Task View and Game Bar. Game Bar is sent after a short settle delay;
  confirm it opens and stays open rather than flashing away.
- Export a Diagnostic ZIP and confirm it lands on the desktop with the log tail,
  settings and environment inside.

## Notification-area icon and Disable / Enable

- Confirm the charcoal/cyan SteamShell XFE icon appears in the Windows
  notification area or its overflow panel. Build the executable and confirm it
  carries the same icon without requiring the external asset beside it.
- Right-click it and verify **Open Quick Menu**, **Open Settings**, **Disable**,
  and **Exit**. Confirm Open Settings remains usable while disabled.
- Select **Disable** while the Quick Menu is open. Confirm the menu closes, the
  cursor is visible, controller mouse/mappings stop, assist actions stop, and
  the global XFE hotkeys no longer respond. Confirm the tray item changes to
  **Enable** and Open Quick Menu is disabled.
- Release or press controller buttons while disabled, then select **Enable**.
  Confirm polling and hotkeys resume without a stale click, mapping, or
  controller-release action firing.
- Disable before the Startup Programs delay expires and confirm pending startup
  programs do not launch. Restart XFE and confirm Disable was session-only and
  the companion starts enabled.
- Select **Exit** and confirm the companion and notification-area icon close.

## Sleep and resume, inside Xbox FSE

This is the case that broke, and it must be tested **inside FSE** — the desktop
recovers on its own via XInput and will pass regardless.

- With `Backend=auto`, sleep the Ally, wake it, and press every button **without
  leaving FSE**. Input must work.
- Check the log for `RawInput: device 0x... went quiet; adopting 0x...`. That line
  is the fix working, and it confirms the handle changed across the suspend.
- Repeat with `Backend=rawinput` explicitly. This is the important run: that
  setting now has **no XInput fallback**, so any input you see is genuinely
  RawInput. Set it back to `auto` afterwards.
- Repeat with several sleeps in a row, and with a long sleep (over an hour).
- Sleep while the Quick Menu is open, wake, and confirm the menu is still usable.

Diagnosing a failure, in order:

- **If the log shows no `adopting` line and no reports at all**, RawInput
  registration was lost rather than the handle changing. Look for
  `Power: resumed from sleep` or `Power: heartbeat gap of Ns`, then
  `RawInput: registered...`, then `RawInput: NO reports since resume after 10s`.
- **If neither a Power line nor a heartbeat-gap line appears**, no resume was
  detected at all — expected under modern standby for the broadcast, but the
  heartbeat gap should still catch it. Note the heartbeat interval; the gap
  detector needs a sleep longer than roughly two intervals.
- **Press `Ctrl+Alt+Shift+I` (or Settings → Advanced → Re-arm Controller).**
  If that restores input, the cause is the device lock or the registration, not
  the backend — which is the whole point of having the manual path.

## Cursor and sleep

- Confirm startup parking moves the hidden cursor to the **right** edge, halfway
  down — the default is now centre-right.
- Leave **Park when a game enters fullscreen** enabled, place the pointer in the
  middle of Steam, and launch a game. Within about one second of its fullscreen
  window taking focus, confirm the pointer is parked and hidden at the selected
  edge.
- During the parking delay, switch away from the game. Confirm XFE does not move
  the pointer in the newly foreground window.
- Open Xbox FSE, Game Bar, and the task switcher. Confirm none is mistaken for a
  newly launched game and none triggers game-entry parking.
- Set **Park the cursor at** to *Left edge* (`ParkEdge=left`), save, and confirm
  parking follows it at startup, on game entry, and on the return to Steam.
- Set `ParkYPercent` to 0.05 and confirm parking moves to the top of that edge,
  so the two settings compose.
- Run `powercfg /requests`; confirm SteamShell XFE creates no request.
- Leave the PC idle through the display-off and sleep timers.
- Confirm the heartbeat does not prevent display-off or S0 sleep.
- With an assist feature enabled, confirm the 2-second tick also does not.

## Non-interference

- Confirm Xbox FSE still owns window maximisation, centring and desktop
  switching.
- Confirm the companion never writes the Winlogon Shell registry value.
- Confirm it never kills/restarts Explorer, hides the taskbar, or resizes a
  window it does not own.
- Exercise Steam exit/restart and non-Steam apps for at least one longer play
  session as the final release smoke test.
