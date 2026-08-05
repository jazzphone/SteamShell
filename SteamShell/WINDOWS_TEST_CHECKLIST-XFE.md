# SteamShell XFE Windows test checklist

For release **1.9.9**. The coordinated locked source snapshot is
`releases/1.9.9/`.

Everything under *Additions since 0.1.14* arrived in 0.1.15. 0.1.16 adds the
RTSS frame-cap input changes described in *Custom FPS stepping* below.
0.1.17 adds the Quick Menu rendering, lifecycle, accent, recovery-layout, and
complete display-mode enumeration changes at the top of this checklist.
0.1.18 adds the audit-hardening checks below. 0.1.19 adds the XFE startup
curtain retirement and Assist hardening checks. 0.1.20 adds the Quick Menu
keyboard, persistent mouse, mappings gesture, and Windows Settings checks.

Test this separately from the standalone SteamShell 1.9.9 runtime, then run the
combined release validator from `releases\1.9.9`.

## Schema 13 — cursor and park settings renamed to standalone's

- **Upgrade with non-default values, which is where a rename loses data.** On a
  schema-12 INI set `[Cursor] EnableAutoHide=false`, `HideDelayMs=4000`,
  `ParkEdge=left`, `ParkYPercent=0.20`, `ParkOnStartup=false`. Start the new
  build and confirm all five arrive as `[Features] EnableAutoHideCursor=false`,
  `[Features] EnableMouseParkOnBoot=false`, `[Timing] MouseHideDelay=4000`,
  `[MousePark] MouseParkEdge=left`, `[MousePark] MouseParkYPercent=0.20`, with
  the old keys gone and `moved 5 setting(s)` in the log.
- Confirm the behaviour actually follows the migrated values: pointer hides
  after 4 seconds, parks to the **left** edge at 20% height, and does not park
  at startup.
- Confirm `ParkOnGameStart`, `ParkOnSteamReturn` and `ForegroundPollMs` are
  still in `[Cursor]` and still work — they were deliberately not renamed.
- On a read-only INI, confirm the old `[Cursor]` values are still honoured
  rather than reverting to defaults.

## Shared-code consolidation

- **On a display that cannot do HDR:** the Display page must read
  `HDR   Not Supported`, and the D-pad must **step over** that row rather than
  highlighting it. Same in standalone.
- With RTSS not installed, confirm the RTSS rows are likewise skipped, and that
  a page where every row is inert still lets you reach Back.

- Confirm the Quick Menu bottom line still shows the button hint, and shows a
  status message when there is one. `QuickMenuDestroyWindow` and the status
  control are now shared code.
- Confirm a **click on a Quick Menu row still activates it** in XFE (it selects
  in standalone). That difference now runs through `QuickMenuMouseChoose`.
- Confirm a two-press confirmation still works — Save Frame Limit To Profile is
  the easiest — and that the message reads *"Select again within 5 seconds to
  confirm ..."*.
- Confirm the log still rotates at `LogRotateMaxKB` and keeps `LogRotateBackups`
  files. `RotateLogIfNeeded` is shared now; set `LogRotateMaxKB=32` to trigger
  it quickly.
- **HDR:** with a display that cannot report Advanced Color state, confirm the
  Quick Menu says *"Windows HDR state is unavailable"* and **not** "...use A to
  toggle". Pressing A must report the same thing and must never send `Win+Alt+B`.
- Confirm the helper-verification failure message names *the companion*, and
  that a support bundle redacts XFE's directory as `%XFE_DIR%`.

## Schema 12 — commented settings file and aligned sections

None of this has executed. The reader change affects **every** setting XFE has,
so this section comes first.

### The reader must survive comments

- Start XFE with the new `SteamShell-XFE_SAMPLE.ini` copied as
  `SteamShell-XFE.ini`. Open Settings and confirm every value matches the file
  rather than falling back to a default. The old reader would have read
  `true  ; explanation` as an unrecognised string.
- **The specific one to look at:** open the Quick Menu and check the accent row
  reads `Purple`, not `Purple ; Steam Blue|Blue|Purple|...`. That is the visible
  symptom of the old reader, and it was present in shipped samples.
- Confirm automatic mouse mode is actually **on** with the commented file in
  place. It defaults to on, and the old reader would have resolved the commented
  value to off. Check `EnableViewButtonActions`, `EnableGameFocusLite`,
  `SuspendOnShellOverlay` and `LaunchDeElevated` the same way — all default on.
- Put a deliberate typo in a boolean (`EnableAutoHide=yse`). Confirm it falls
  back to the setting's own default (on) rather than to `false`, and that
  Settings shows it as on.
- Add your own trailing comment to a value through a text editor, restart, and
  confirm the setting is unchanged and the comment survives a Settings save.

### Schema 12 migration

- **Upgrade path, which is the one that can lose data.** Take an existing
  schema-11 `SteamShell-XFE.ini`, set `[Controller] EnableAutoMouseMode=false`
  and `[Assist] HardKill=false`, then start the new build. Confirm both values
  arrive as `false` at `[Features] EnableAutoMouseMode` and
  `[LauncherCleanup] HardKill`, that the old keys are gone, and that the log
  records `moved 2 setting(s)`.
- Confirm a **fresh** install writes `[Features]` and `[LauncherCleanup]`
  directly and never logs a migration.
- Run the upgrade twice. The second run must move nothing and log nothing.
- Put a conflicting value at the destination by hand before upgrading; confirm
  the destination wins and the source key is still removed.
- On a read-only INI, confirm the companion still starts, logs the failure as a
  warning, and keeps reading the old location rather than losing the setting.

## Additions consolidated into 1.9.9 from 0.1.21

- Open Controller Mappings directly from Quick Settings with persistent Mouse
  Mode off. Confirm the right stick moves the visible pointer and RB clicks.
  Repeat with every companion Settings/editor window and a native file picker.
- Confirm schema 8 copies the old `CustomFrameCap` to `PresetFrameCap`.
- Set Preset to 158 and Custom to 157. Cycle away and back, then restart XFE;
  confirm each entry restores its own value.

## Additions in 0.1.20

- Confirm the main page order is Audio, Display & HDR, RTSS & Performance,
  Steam Menu, Steam Quick Access, Task Switcher, Game Bar, Open Keyboard, Mouse
  Mode, Settings, and System.
- Select Open Keyboard and confirm Quick Settings disappears before the touch
  keyboard appears.
- Enable Mouse Mode and confirm controller pointer/mappings work without
  View/Back, including while Xbox FSE/Steam is the shell surface. Restart and
  confirm it persists; disable it and confirm the normal modifier gate returns.
- With Mouse Mode On, close Quick Settings with B and launch Open Keyboard with
  A. Confirm neither button fires its normal mapping again when released.
- Hold Y on the main page and confirm the styled Controller Mappings submenu
  opens inside Quick Settings. Confirm it shows the loaded mappings and ends
  with **Set Controller Mappings**; selecting that row closes Quick Settings and
  opens the full editor. A short Y tap must do nothing and no Controller Layout
  row remains on the main page.
- Open Settings ▸ Windows Settings and confirm the Quick Menu is dismissed before
  Windows Settings appears. Confirm Settings reads `Features & Configuration`,
  System reads `Power & Diagnostics`, and every static row label is title-cased.

## Additions in 0.1.19

- Complete **Retired XFE startup curtain** and the expanded **Assist features**
  scenarios below.
- Confirm schema 6 preserves a `.pre-schema-6.bak` before removing the retired
  `[StartupSplash]` section.
- Run the XFE validator and confirm it rejects any restored startup-curtain UI
  or runtime entry point, the old unconditional CPU result, a Steam tool-window
  filter regression, or an image-name-wide delayed hard kill.

## Additions in 0.1.18

- Confirm migration to settings schema 5 adds `Companion.LogRotateMaxKB` and
  `LogRotateBackups` without replacing existing values. Use a low threshold and
  verify rotation reaches multi-digit backups such as `.log.10`.
- With `DiagnosticLogging=false`, press and release controller buttons and
  confirm per-edge input lines are absent. Enable it and confirm they appear.
- Navigate every Quick Menu page with the left stick as well as the D-pad.
  Confirm held input repeats normally and neutralizing the stick stops it.
- Configure a missing RTSS path while RTSS exists at its standard
  `%ProgramFiles(x86)%` location. Confirm the main summary, RTSS page, Start
  action, Health Check, and `RTSSHooks64.dll` lookup all use that installation.
- Run `..\Run-SteamShellValidation.cmd`; confirm XFE participates in syntax,
  static, broken-source, and locked-stale-output checks, and that a failure
  returns a non-zero process exit code without replacing root `current\`.

## Additions in 0.1.17

- Confirm the INI migrates to settings schema 4 without changing existing
  values and adds `QuickMenu.AccentColor=Steam Blue` plus
  `QuickMenu.AccentColorCustom=A970FF`.
- Open every Quick Menu page at 100%, 150%, and the HTPC's normal scaling.
  Confirm each row is sharp, text is vertically centred, long values ellipsize,
  and the menu shows no blank frame or control-by-control assembly.
- Confirm the base is dark neutral charcoal (`#242424`) and no one-pixel native or DWM border is
  visible around any edge of the Quick Menu.
- Confirm unselected labels and values appear neutral gray, without a blue tint.
- A custom exterior shadow is intentionally not required; confirm the menu remains
  a clean opaque panel against both light and dark content.
- Move selection repeatedly. Confirm exactly one rounded panel has the accent
  outline, left bar, and clearly visible glow. Select the first and last rows to
  prove the glow is not clipped; no stale pixels or GDI degradation should
  appear after sustained navigation.
- Navigate rapidly and enter/leave several submenus. No blank/background-only
  frame should appear during either a row bitmap swap or a page resize.
- In Quick Menu ▸ Settings, cycle all accent presets in both directions and
  confirm wrapping, immediate repaint, and a matching derived fill tint. In Full
  Settings ▸ General, select Custom and verify a valid `RRGGBB` value persists.
- On Windows 11 confirm smooth composited outer corners; on Windows 10 confirm
  the region fallback still rounds the window without clipping a row.

## Additions since 0.1.14

### Frame Limit row (replaces the separate Frame Limiter row)

- Cycle Left/Right through **Off · 30 · 40 · 60 · 90 · 120 · Preset · Custom** and confirm RTSS reflects each value.
- **The preset must survive an off/on round trip.** Set 72 via Custom, cycle to `Off`, press Right, and confirm it
  returns to **72** rather than 30. "Off" clears RTSS's limiter flag and must never write `0` over the value.
- Press Left repeatedly while already on `Off` and confirm the flag write and its status message do not repeat.
- **The selection must survive a reboot.** Set a standard cap, then Preset, then
  Custom, rebooting after each, and confirm the row comes back exactly as it was
  left rather than `Off`. Repeat with the limiter left `Off` and confirm it comes
  back `Off` with one Right press returning to the previous number, not 30.
- Confirm the log records `Restored the last Frame Limit selection: …` and that
  the restore did **not** launch RTSS: with RTSS closed at startup, `RTSS.exe`
  must not appear until something else starts it, and the restore must then apply
  on its own within about two minutes.
- Turn off **Restore last selection when RTSS starts** in Settings ▸ RTSS &
  Performance, reboot, and confirm XFE leaves RTSS alone.
- Set `[RTSS] UseDllIntegration=false`, restart, and confirm the log says the
  restore requires DLL integration rather than waiting out the full deadline.
- Confirm Preset uses the value saved in Settings, while Custom restores the
  last value adjusted on its own row rather than inheriting the prior selection.
- Temporarily set Preset to 60. Confirm the cycle still reaches 90 and 120
  normally instead of treating the same 60 FPS number as two distinct states.
- On Custom FPS, confirm every tap changes the value by exactly 1. Hold Right
  and confirm only the repeat rate accelerates; after release, the next tap is
  still exactly 1.
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

- Double-click `Build-SteamShell.cmd` with AutoHotkey v2.0.26 64-bit installed.
  One script builds all three binaries; the companion no longer has its own.
  Confirm the result remains visible until a key is pressed.
- Confirm **both** validators pass — the shell's and this one — since the single
  build runs both.
- Confirm the companion is left at `dist\SteamShell-XFE.exe` for this test.
  Installing it for real is Setup Assistant inside `SteamShell.exe`.
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
- Leave SteamShell-XFE.exe **out** of AnyFSE's startup applications. Setup
  Assistant registers the logon task, so adding it there as well starts two
  companions.
- After a Setup Assistant install, reboot and confirm exactly **one**
  `SteamShell-XFE.exe` process. Then deliberately add it to AnyFSE's startup
  list as well, reboot, and confirm two appear — this is the misconfiguration
  the old instruction produced, and it should be recognisable when reported.
- Open **Settings → General** and confirm the integration note names only the
  AnyFSE Home app and *Exit FSE when Home app exits*, and tells you not to add
  the companion to AnyFSE's startup applications. It must no longer instruct
  adding it as a startup app.
- Turn **Exit FSE when Home app exits** off.
- While Xbox FSE is active, confirm heartbeat lines continue for at least a
  minute, proving the companion survives rather than being suspended.
- Close and relaunch Steam; confirm the same companion PID survives.


### One logon task, one name

Two programs used to register this task under different names, so a machine could
carry both and start two companions. These steps prove they converge.

- Fresh machine: install XFE with Setup Assistant. In Task Scheduler confirm
  exactly one task named **SteamShell XFE Companion**, and that its trigger shows
  a **10 second delay** — Setup's old task had none.
- Open **Settings → Advanced → Check Logon Task**. Confirm it now FINDS the task
  and writes its definition to the log. It used to report none after a Setup
  install.
- Press **Create Logon Task**. Confirm it replaces the same task rather than
  adding a second, and that no task named `SteamShell-XFE` exists afterwards.
- **Migration.** On a machine that already has the old `SteamShell-XFE` task,
  run either route and confirm the old name is deleted and only
  `SteamShell XFE Companion` remains.
- **Remove Logon Task** must clear both names. Confirm no SteamShell XFE task of
  either name survives, then reboot and confirm the companion does not start.
- Uninstall from Setup Assistant and confirm the same.
- Reboot with the task registered and confirm exactly **one** companion process,
  starting about ten seconds after sign-in rather than immediately.
- Confirm the registered account shows as the interactive user. Renaming a
  Windows account must not break the task — the definition stores a SID.

## Upgrading while the companion is running

This is the normal case, not the awkward one: the logon task starts the
companion at sign-in, so it is running every time Setup Assistant is opened on a
configured machine. Setup used to try to replace a locked image and fail, which
meant it could essentially never apply here.

- **The reported case.** With the companion running, launch a newer
  `SteamShell.exe`, let it open Setup Assistant, and apply. Confirm it succeeds
  rather than reporting that the companion could not be deployed, and that
  `SteamShell-XFE.exe` carries the new file version.
- Confirm the log records `Setup closed PID … before replacing it` followed by
  the restart line.
- Confirm the companion is running again when the result dialog closes, and that
  the dialog mentions it was closed and restarted. On a first install — nothing
  running beforehand — confirm it says nothing about a restart.
- **Integrity check, and this is the important one.** With the companion
  restarted by Setup, add the *Integrity Level* column in Task Manager and
  confirm `SteamShell-XFE.exe` is **Medium**. Setup runs elevated, so a restart
  through `Run` would silently hand the companion an administrator token —
  exactly what choosing XFE is meant to avoid.
- Repeat with the **opt-in elevated RTSS helper enabled** so a helper is also
  resident. Confirm both are closed, both are replaced, and the helper reports
  file version 1.9.9.4.
- Confirm the settings INI, `SteamShell-XFE-Controllers.ini`, and the log
  survive the upgrade intact. The companion is closed with WM_CLOSE so its exit
  handler runs; a truncated or missing learned profile means it was terminated
  instead.
- **Uninstall while running.** Confirm the companion is stopped before removal
  and that the directory is fully removed rather than partially.

## Retired XFE startup curtain

- Start 0.1.19 with a copy of an older schema-5 INI whose `[StartupSplash]`
  section is enabled. Confirm no curtain or video appears over Steam.
- Confirm the section is removed, `SettingsSchemaVersion=6` is written, and the
  original values remain recoverable in `SteamShell-XFE.ini.pre-schema-6.bak`.
- Confirm neither the full Settings window nor Quick Menu Settings exposes a
  startup-curtain control. Standalone SteamShell still owns its startup
  curtain/video; this retirement is XFE-only.

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
- Confirm the selected row is a rounded panel with an accent outline, left bar,
  and glow, and that **only one row is highlighted** as you navigate — a stale
  highlight means the bitmap is not repainting.
- Visit every page; confirm no row is cut off and the window ends just below the
  content rather than carrying a large empty margin.
- Navigate between pages: the window resizes and re-centres **without blinking**
  and without stealing activation.
- Close the menu, launch and leave a fullscreen game, then wait on Xbox FSE
  without reopening the menu. No title, rows, footer, or noninteractive menu
  fragments may reappear. Reopen it afterwards and confirm it is responsive.
- Open Settings; confirm centred, all seven categories, no overlapping controls.
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

The value column is right-aligned, and text that is too long is ellipsized by
the GDI+ painter.

- On the main page, the **Audio** row must show the volume as a percentage at the
  far right, after the output device name.
- Compare it with the Audio page's **Volume** row: both come from the same
  function and must agree. A main-page row reading `%` or a bare digit means the
  column is clipping, not that the volume is unreadable.
- Try an output device with a long name and confirm the percentage still shows.

## Display mode enumeration

- On a 4K TV or monitor, open Quick Menu → Display & HDR and cycle Resolution
  through the complete list. Confirm `2560×1440` and `3840×2160` appear when
  Windows offers them; the list must not stop near `1280×1024`.
- Check the log for `Display modes: Windows reported N entries`; systems whose
  drivers expose more than 512 combinations must still reach their 4K modes.

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

- Open Quick Menu → Settings; confirm seven toggle rows, **Windows Settings**,
  and **All Settings…**.
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
- **Windows Settings** dismisses the Quick Menu and opens the Windows Settings app.

## Settings window layout and focus

- Open Settings from the **chord**, from **Ctrl+Alt+Shift+S/P**, and from the
  Quick Menu. In all three cases it must appear **in front on its own**, with no
  task switcher. It is always-on-top for this reason: Xbox FSE is a fullscreen
  window, so a normal window can hold focus and still render behind it.
- On **Controller & Cursor**, confirm **Delete Learned Profile** does not overlap
  the "Park after returning to Steam" checkbox.
- On **Steam** and **Advanced**, confirm no explanatory paragraph is cut off at
  the bottom.
- Visit all seven categories and confirm nothing is clipped or overlapping. The
  requested window is 920x660; page content stops above the button bar at y610.
- At each display scale, confirm the visible outer window is vertically centred
  in the monitor work area. Its title bar and bottom edge should have equal
  usable space; the bottom must not extend below the taskbar or visible desktop.

## Settings categories

- Confirm the sidebar lists seven categories, including **Steam**, **Startup
  Programs**, and **Assist**, with no **Startup Splash** category.
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
- Confirm the Apply row counts down (`Select To KEEP (12s)`) during the window.
- Repeat and select Apply again to keep all three settings.
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
- Minimize the game and confirm CPU activity continues to block cleanup. Then
  set `CpuThresholdPercent=0` and confirm only fullscreen/borderless window shape
  is used.
- With `HardKill=true`, use a test launcher that ignores `WM_CLOSE`. Confirm the
  delayed pass closes only the original PID. Disable Launcher Cleanup during the
  grace period and confirm the pending force-close is cancelled. Repeat while a
  game starts during the grace period and confirm the process is left running.

**Game Focus Lite:**

- Confirm a game returns to the foreground when something steals it.
- Confirm it does **not** fight Xbox FSE surfaces.

**Steam Assist Lite** (enable last, alone):

- Watch for it duplicating or fighting AnyFSE's own return-to-Home behaviour.
- Confirm Steam remains a valid target when its visible Big Picture window has
  `WS_EX_TOOLWINDOW` without `WS_EX_APPWINDOW`.
- Bring File Explorer, the desktop, and the taskbar to the foreground and confirm
  the assist never takes focus away from those `explorer.exe` surfaces.

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
- Repeat with the configured path missing but a stock RTSS installation present;
  confirm **Start RTSS** appears and launches the discovered default executable.
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

## Frame Limit row reaches every entry

The bug this replaces: pressing **A** repeatedly reached OFF, PRESET and CUSTOM
and stopped there, with 30/40/60/90/120 unreachable in that direction.

- Open Quick Menu → RTSS with RTSS running and the limiter **off**.
- Press **A** repeatedly and confirm the row walks the full list in order —
  OFF, 30, 40, 60, 90, 120, PRESET, CUSTOM — and then wraps back to OFF.
- Confirm each stop actually applies: check the value in RTSS itself, not only
  the row text.
- Press **Left/Right** on the same row and confirm it still *clamps* rather than
  wrapping, and that Right from OFF still restores the FPS RTSS was holding
  rather than stepping to 30.

## Quick Menu does not clip when a page grows

- With RTSS **not** running, open Quick Menu → RTSS. The page shows two rows.
- Leave the page open and start RTSS from elsewhere.
- Confirm the page grows to four rows, the window resizes and re-centres, and
  the bottom row and the button hint are fully visible.
- Navigate to another page and back; confirm no leftover empty space.


## Hold to drag

New. `Builtin:LeftClick` is press-and-hold; everything else is unchanged.

**The failure this must never produce is a mouse button stuck down.** Less severe here than in the shell -- Explorer still owns the
desktop -- but keep a keyboard connected anyway.

- With RB bound to Left click (the default), hold View/Back, hold RB, move the
  right stick. Confirm a drag: select text, move a file, drag a window title bar.
- Tap RB. Confirm it still produces an ordinary single click.
- Confirm RB double-click still works by tapping twice.
- **Release checks.** Start a drag, then in turn: release View/Back mid-drag;
  let automatic mouse mode end by switching to an application not on the list;
  press the Quick Menu chord; press the Settings chord; unplug the controller.
  After each, confirm the button is NOT still down — click somewhere harmless and
  confirm nothing is selected or dragged.
- **Inside Xbox FSE.** Confirm the controller still navigates FSE normally and
  no drag occurs there, since FSE is not on the automatic mouse list.
- **Watchdog.** With a drag held, suspend the poll (open Settings, or reload).
  Within ~35 seconds confirm the log records *Released a synthetic mouse button
  held past the safety limit* and the button is up.
- **Exit and error.** Exit the companion mid-drag and confirm the button is released.
- **Mapping editor.** Confirm the `RB.Long` row reads *Reserved for mouse (hold
  to drag)*, and that **Set Built-in** and **Record Shortcut** both refuse it with
  a status message rather than accepting a binding that can never fire.
- Change `RB.Short` to something else and confirm `RB.Long` becomes settable
  again and shows its real action.
- Bind Left click to **A** instead and confirm drag moves to A and RB returns to
  a normal Short/Long button.
- Confirm **Right click is unchanged** — RT taps produce a context menu and
  holding RT does not drag.


### Steam in the task switcher

- With Xbox FSE running and Steam Big Picture behind it, open the Task Switcher.
  **Steam must be listed.** It was being dropped as a cloaked window before the
  tool-window exception was ever reached.
- Select it and confirm it comes to the front.
- Confirm no other cloaked or tool windows have appeared alongside it — the
  exemption is meant to be Steam-specific, not a relaxation of the rules.
- If Steam's row has no title, confirm it reads something usable rather than
  being blank.

### Elevated RTSS helper without a prompt

- Enable elevated frame-cap writes and set a cap. On first use, confirm the
  protected task is registered and no UAC prompt appears afterwards.
- Confirm no `HighestAvailable` task exists **before** the opt-in is used.
- Confirm the task and the helper directory are both removed by Setup
  Assistant's uninstall.

## Automatic mouse mode

Schema 11 removed `EnableDesktopAutoMouseMode` and
`DesktopAutoMouseExcludeExeList`. Two settings remain.

- Defaults: `EnableAutoMouseMode=true`, `AutoMouseExeList=explorer.exe`.
- On the Windows desktop, move the right stick without holding View/Back and
  confirm the pointer moves, and that a hidden cursor is revealed rather than
  moved invisibly. Include Start and the search surface.
- Switch to Xbox FSE and confirm the pointer does **not** activate there, and
  that FSE navigation is unaffected. This now follows from FSE not being on the
  list rather than from an exclusion, so it is worth confirming rather than
  assuming.
- Add a second application to `AutoMouseExeList`, save, and confirm the pointer
  starts activating inside it without a restart.
- Clear `AutoMouseExeList` entirely and confirm the pointer stops activating
  anywhere, and that holding View/Back still works.
- With the pointer wrongly active somewhere, confirm the Quick Menu and Settings
  chords still work, so the list can be corrected without a keyboard.
- Set `EnableAutoMouseMode=false` and confirm holding View/Back still works.
- Confirm **Settings → Controller & Cursor** shows exactly two automatic-mouse
  rows — the master switch and the application list — with no exclusions field.

### Schema 11 migration

- Start with an INI containing `EnableDesktopAutoMouseMode=true` and a populated
  `DesktopAutoMouseExcludeExeList`. Launch the companion.
- Confirm **both keys are deleted** from `[Controller]`, `AutoMouseExeList` is
  unchanged, and `SettingsSchemaVersion=11`.
- Confirm the log records the retirement and states that automatic mouse mode
  now applies only to `AutoMouseExeList`. This narrows behaviour, so a silent
  migration is the failure — the line is the deliverable.
- Repeat with a **read-only** INI: confirm the companion still starts, both keys
  are ignored by the poll loop regardless, and the warning names the reason.

## Opt-in elevated RTSS helper

### RTSS shortcut messages

- Clear each of the six RTSS shortcut settings in turn, disable DLL integration,
  and confirm the companion names **the specific setting** that is blank rather
  than saying "the RTSS shortcut".


**None of this has executed.** The helper, its deployment in XFE mode, and every
refusal path below are new and unrun. Test on a machine you can recover.

Run these as a **standard user** with RTSS installed in its default
`C:\Program Files (x86)\RivaTuner Statistics Server` location. Anywhere the
account can already write RTSS's own directory, none of this applies and the
in-process write works on its own — which is itself worth confirming once.

### The default: nothing is elevated

- Install XFE through `SteamShell.exe` Setup in XFE mode, as an administrator.
- Confirm the completion dialog says the elevated helper was installed and is
  **turned off**.
- Confirm `%ProgramFiles%\SteamShell-XFE\bin\SteamShell-Helper.exe` exists,
  reports file version **1.9.9.4**, and that `icacls` on **both** the directory
  and the file lists SYSTEM and Administrators as Full and Users as read/execute
  — the file must list ACEs, not an empty DACL. This is the failure that shipped
  once in the standalone path and certified itself as protected.
- Confirm `dir /q` shows the helper **owned by Administrators**, not by the
  account that ran Setup. This is the ordering bug that would fail every install.
- Sign in normally. Confirm **no UAC prompt**, no `SteamShell-Helper.exe` in Task
  Manager, and that Health Check reports `elevated RTSS helper disabled
  (default)`.
- Open Quick Menu → RTSS. Confirm the Frame Limit row reports **read-only** and
  *Save Limit to Profile* reports **Unavailable**.

### Turning it on

- Settings ▸ RTSS & Performance ▸ **Write the cap through an elevated helper**,
  then Save & Apply.
- Confirm a UAC prompt appears **at that moment**, without a restart. Accept it.
- Confirm `SteamShell-Helper.exe` is running, Health Check reports it as PASS
  with its PID, and the elevated-helper-protection line reports PASS.
- Confirm the Frame Limit row is no longer read-only.
- **Decline** the UAC prompt on a second attempt and confirm the companion keeps
  running, Health Check says WARN with the cancellation reason, and the row goes
  back to read-only rather than silently accepting presses.

### The write actually reaches RTSS

- Note the modified time and contents of RTSS's `Global` profile file.
- Change the cap from the Quick Menu. Confirm **the file on disk changes** —
  not only the row text — and that RTSS's own window updates live.
- Confirm the cap takes **one** press, not several. Two processes touching RTSS
  at once is what made it take several in standalone.
- Launch a game, open Quick Menu → RTSS → **Save Limit to Profile**, confirm
  twice. Confirm a profile for that executable appears in RTSS's `Profiles`
  directory holding the right `FramerateLimit`, and that the Frame Limit row
  still reads the **global** value afterwards.
- Check `%ProgramFiles%\SteamShell-XFE\bin\SteamShell-Helper.log` for the
  matching request lines.

### The refusals

- With the helper running, put a name that is not a running process into the
  per-game request path and confirm the helper logs a refusal rather than
  writing it.
- Point `[RTSS] Path` at an `RTSS.exe` **outside** Program Files and confirm the
  helper logs that it will not write there. The companion's own write already
  works in that case.
- Grant your own account Modify on `%ProgramFiles%\SteamShell-XFE\bin`.
  Restart the companion and confirm it **refuses to elevate**, logs the reason,
  and Health Check reports the protection line as WARN naming your SID.
- Separately, take ownership of that directory without adding a writable ACE and
  confirm the same refusal — the owner has implicit `WRITE_DAC`, so ownership
  alone must be enough to refuse.
- Re-run Setup as administrator and confirm owner, DACL and helper all recover.

### Turning it off, and lifecycle

- Clear the checkbox and Save & Apply. Confirm the helper process **exits
  immediately**, without a restart, and Health Check returns to the disabled
  line.
- With it enabled, end `SteamShell-Helper.exe` from Task Manager. Confirm the
  next frame-cap press fails **promptly** rather than pausing for three seconds,
  and logs that the helper process exited.
- Exit the companion with the helper running. Confirm the helper exits on its
  own within a few seconds.
- Confirm the helper **never** shows a window, message box, or error dialog in
  any of the above.

### What the helper must NOT do

- With the helper running and Task Manager focused, press a mapped controller
  button. Confirm **nothing happens** — XFE's helper carries no elevated input,
  and the accepted cost in the README still applies in full.
- Confirm no elevated window is centred or maximised while the helper runs.

### Uninstall

- Uninstall XFE from Setup Assistant. Confirm it says the helper directory was
  left in place, and that nothing starts it afterwards.

## Settings fields round-trip

`RTSS.RestoreFrameLimitOnStartup` was registered as a Settings field and neither
populated nor saved: the checkbox always drew unchecked and clearing it did
nothing. A validator assertion now covers every field structurally, but confirm
the two in this area by hand.

- Set `RestoreFrameLimitOnStartup=false` in the INI, open Settings, and confirm
  the checkbox is **unchecked**.
- Tick it, Save & Apply, and confirm the INI now reads `true`.
- Repeat for **Write the cap through an elevated helper**.

## Settings window: flowing rows and a scrolling viewport

**Unrun.** Every page was rebuilt and the window gained a scrolling content area
it never had. A page that draws over the title, a page that cannot be scrolled to
the bottom, or a control left behind by the scroll are all new failure modes.

### It still opens and looks right

- Open Settings with `Ctrl+Alt+Shift+S` and from Quick Menu → All Settings.
- Confirm the log says `Settings layout audit passed for all categories`. If it
  reports issues, they name the page and the coordinates — treat that as a
  failure, not a warning.
- Visit all seven categories with the sidebar and with LT/RT. Confirm each shows
  its own title and description, and no control from another page.
- Confirm nothing draws over the page title, the sidebar, or the footer.

### Scrolling

- **General**, **Steam**, **Startup Programs**, **Assist** and **Advanced** must
  show **no scrollbar** — they fit.
- **Controller & Cursor** and **RTSS & Performance** must show one.
- On both, drag the thumb to the bottom and confirm the last row is fully
  visible and not clipped by the footer.
- Click above and below the thumb (page up/down) and the arrows (line up/down).
- Scroll with the mouse wheel over the page background.
- Scroll with the **left stick** on a controller, and confirm the right stick
  still moves the pointer at the same time.
- Put the pointer over the Startup Programs list box and use the wheel. The
  **list** must scroll, not the page.
- Scroll one page down, switch to another category and back, and confirm it
  returns to where you left it.
- Watch for trails or half-drawn controls while dragging the thumb quickly. That
  is what the redraw batching prevents.

### Rows are where they should be

- **Controller & Cursor**: confirm the four automatic-mouse controls (Enable,
  Everywhere-except, Exclusions, Allowlist) are in the **left column, below the
  parking rows** — not in a right-hand column.
- **RTSS & Performance**: confirm it is one list with **Overlay** and **Frame
  Limiter** section headings, and no group boxes.
- **General**: confirm the order is Quick Menu, Audio, Display, accent colour,
  custom accent, chord hold, heartbeat.

### The settings still round-trip

This is the important one: the pages were rebuilt, so every field's wiring is new
even though the keys did not change.

- Change **one setting on every page**, Save & Apply, close Settings, reopen, and
  confirm each change is still shown.
- Check the INI directly for the four whose stored value comes from a dropdown
  **index**, because reordering a list would invert them silently:
  `RTSS.OverlayControlMode`, `RTSS.FrameLimiterControlMode`,
  `StartupPrograms.WindowMode`, `Cursor.ParkEdge`. Set each to its **second**
  option, save, and confirm the INI holds the expected string.
- Confirm the Record… buttons on every shortcut row record into the right field.
- Confirm Browse… on the RTSS path row fills the RTSS executable field.
- Confirm all twelve Advanced buttons still do what their labels say.

## Which window is the game

The per-game RTSS cap is keyed on an executable name, so the failure this fixes
is a cap written to the wrong program's profile and reported as saved.

- **Upgrade with a customised INI.** Schema 13 to 14 adds twelve `[Assist]` keys.
  Change several unrelated Assist values first, upgrade, and confirm they survive
  and the new keys appear with the documented defaults.
- **A launcher that is fullscreen.** Leave a store launcher maximised with a game
  running behind it, then save a per-game cap. It must go to the game, not the
  launcher. Check the log names the exe it chose.
- **A fullscreen video or browser** with no game running: saving a per-game cap
  must not target it.
- **A game with the sound muted** must still be detected — audio adds to the
  score, it is not required.
- **A windowed game** below the fullscreen tolerance: the scorer returns nothing
  and the last-observed-foreground fallback should still let the save proceed.
- Set `[Assist] EnableAudioAssist=false` and confirm detection still works on
  shape and CPU alone.
- Confirm Game Focus, Steam Assist and Launcher Cleanup behave exactly as before
  — they use the old shape test and must be unaffected.

## Game-score diagnostics and the shared Health Check

- **Upgrade with a customised INI.** Schema 14 to 15 adds a `[Logging]` section.
  Change several unrelated values first, upgrade, and confirm they survive and
  `[Logging]` appears with everything off.
- Set `[Logging] EnableGameScoreLogging=true` and `GameLogMode=TOPN`, open the
  Quick Menu over a game, and confirm a candidate table appears in the log with
  score, CPU, audio and fullscreen columns. It must match the shell's format.
- Set `GameLogMode=DIAGNOSTIC` and confirm rejected near-misses appear too.
- Confirm a table is written whenever candidates exist, and that the best one is
  used regardless of its score. A low-scoring but scored candidate must NOT send
  the save back to the last-observed foreground window.
- Confirm `GameLogIntervalMs` rate-limits: no more than one table per interval.
- Leave it `OFF` and confirm the log is unchanged from before this build.
- **Health Check** now shows a list with Status/Check/Details, plus Refresh and
  Copy Report. Confirm every row has all three fields and none reads "PASS —".
- Confirm Copy Report puts the whole report on the clipboard with the companion's
  name and version in the header.
- Confirm Refresh re-runs the checks without reopening the window.
- Confirm Export Diagnostic ZIP still works and the window centres on the active
  monitor.

## A minimized game must still be nameable

- Start an exclusive-fullscreen game, alt-tab so it minimizes itself, open the
  Quick Menu and save a per-game frame cap. It must target the game.
- With `[Logging] EnableGameScoreLogging=true` and `GameLogMode=TOPN`, confirm the
  minimized game appears as a candidate with `FS=Y`.
- **Close** a game, then open the Quick Menu and try to save a per-game cap. It
  must NOT target the closed game — that is the stale-name case the removed
  fallback used to produce.
- Confirm Game Focus, Steam Assist and Launcher Cleanup are unaffected; the
  inventory gained fields but they read the same keys as before.

## The companion records itself

- **Upgrade with a customised INI.** Schema 15 to 16 adds a `[Setup]` section.
  Change unrelated values first, upgrade, and confirm they survive and `[Setup]`
  appears with `Product=XFE`.
- Confirm `InstallDirectory` and `DataDirectory` are filled in on first run and
  match where the companion actually is.
- Restart and confirm they are NOT rewritten — an ordinary start should do no
  file writes for this.
- **Move the folder** and restart: exactly one warning naming both paths, and the
  companion runs normally.
- Confirm a companion copied by hand, never installed by Setup Assistant, still
  records itself correctly.

- **Health Check row.** Open Health Check and confirm an "Installation record"
  row. On a normal install it must read PASS. After editing `[Setup]
  InstallDirectory` to a wrong path it must read WARN and name both paths.
- On a machine where Setup has never run, the row must read INFO and say nothing
  is recorded — not WARN. A new installation is not a faulty one.

## A moved companion says so

- Move the companion folder and start it. The tray tip must end with
  "— installation moved" and the status line must say so once.
- It must start and behave normally: assists, Quick Menu and RTSS all unaffected.
- Re-run Setup Assistant from SteamShell.exe, or correct `[Setup]
  InstallDirectory` by hand, and confirm the notice clears on next start.

## Tray icon and menu

- **The bug this fixes.** Kill `explorer.exe` from Task Manager and let it
  restart. Before this change the companion's tray icon was gone for good; it
  must now come back with its menu intact.
- Confirm the menu is: Quick Menu, Settings, separator, Disable/Enable, Exit.
- Use Disable, and confirm the entry renames to Enable AND the Quick Menu entry
  greys out. Re-enable and confirm both revert.
- With a moved installation, confirm a new first entry appears — "Installation
  moved — open Settings" — and that it disappears once the record is corrected.
  This is the entry the old build-once menu could not show at all.
- Confirm double-clicking the icon still opens the Quick Menu.

## RTSS after the shared-code move

- Toggle the RTSS overlay and frame limiter; both must report on screen as before.
- Set a global and a per-game frame cap with the elevated RTSS helper enabled and
  running, then with it killed. The second must fail promptly, not freeze.
- Confirm the Quick Menu title still reads "SteamShell XFE  ›  <page>".
- Hold the d-pad on Volume and Custom FPS; both must still repeat.
- Scroll the Settings window with the wheel and confirm it behaves as before.
