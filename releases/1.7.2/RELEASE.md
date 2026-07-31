# SteamShell 1.7.2

Released: 2026-07-31

This directory is the locked source release for SteamShell 1.7.2. Do not edit
this snapshot when later development resumes; make changes in `SteamShell/`
under a later version.

Build `SteamShell.ahk` on Windows by double-clicking `Build-SteamShell.cmd`. The
underlying PowerShell script requires AutoHotkey v2.0.19 or newer with a 64-bit
base, runs `Validate-SteamShell.ps1` and AutoHotkey syntax validation, and then
compiles `dist\SteamShell.exe` with the included icon.

No compiled EXE is stored in this snapshot.

**Settings schema stays at 10.** Nothing in 1.7.2 adds or retires an INI key, so
upgrading from 1.7.1 involves no migration and existing configuration files are
untouched.

## Release scope

1.7.2 is almost entirely fixes found by running 1.7.1 on hardware, plus the two
reversals those tests forced.

### Save Limit to Profile could not see a running game

The row reported `No game in foreground` while a game was running and the Task
Switcher was listing it. It resolved the target from one source — the foreground
window captured when the Quick Menu opened — and that value is regularly
`steam.exe`, because the window engine's Steam refocus can pull Big Picture
forward moments beforehand and a borderless game can sit behind a Steam surface.
Steam is excluded deliberately, so the row resolved to nothing.

It now falls back to the window engine's detected game, which is the same
detection behind Game Foreground Assist and what the Task Switcher reflects, so
the two can no longer disagree. The row also distinguishes `Steam in front, no
game detected` from `No game in foreground`.

### The window engine centred dropdown menus

Centring had no size or structure test at all — its only condition was being more
than two pixels off centre — while maximising has always been gated by
`MinWidthPercent` *and* the window having a maximise box. A dropdown is a real
top-level window, so nothing excluded it, and centring one is wrong rather than
untidy: it is positioned relative to the control that opened it.

Popups are now filtered structurally. The first attempt keyed on ownership and
fixed Explorer's dropdowns while missing Qt's, because Qt popups are unowned;
ownership turned out to be a framework detail. Captionless windows are now judged
by **size**, with captioned windows exempt so small dialogs are still centred.

### Logging

Every operational line now carries a timestamp and a level, matching XFE. Only
the game-score rows had one, because they stamped themselves, so the log recorded
what happened but not when — and elapsed time is what a startup stall, a focus
handoff, and a sustained-exit window all reduce to.

### Recovery and diagnosis

- The desktop-restore failure screen is controller-navigable, matching the
  Steam-did-not-start screen. It was a native `MsgBox` the poll loop has no
  handling for, in the state where Explorer may be dead.
- The Quick Menu logs what holds the foreground when its handoff fails, and
  detects losing the foreground after acquiring it. Verifying only at open proved
  the menu *acquired* focus, not that it kept it.
- Warnings surface in the Quick Menu footer for four seconds. 52 of them were
  log-only.

### Two reversals

**The tray right-click shows the native Windows menu again.** The interception
added in 1.7.0 was correct about the mechanism — a native menu freezes controller
polling — and wrong about the context. Reaching a tray icon means using a
pointer; a controller user opens the Quick Menu by chord or hotkey. The validator
now asserts the interception has *not* returned.

**Frame-cap stepping no longer escalates.** Growing the step after fast presses
made the same gesture produce 1, 5 or 10 depending on timing the user could not
see. A press is now always one step; speed comes from holding, accelerating the
repeat rate rather than the step. This required passing the held button state
into the menu handler, which previously received only edges — the constraint that
made escalation seem necessary in the first place.

Separately, each press had been writing straight to RTSS, a disk write per press.
The value is now committed once, ~400 ms after input stops.

## Verification status

**Validated on hardware by the maintainer prior to this lock**, on a ROG Xbox
Ally X and an Ethernet-connected HTPC. Confirmed working during testing:

- Save Limit to Profile naming the running game
- Dropdowns no longer centred, in both Explorer and Qt (PCSX2)
- The tray right-click menu
- Custom FPS stepping — a press is one step, holding accelerates

This is a maintainer-reported pass rather than an item-by-item transcript of
`WINDOWS_TEST_CHECKLIST.md`. Two checks in that document are written to catch
**silent** failure and are worth repeating if behaviour is ever doubted, because
each logs success either way:

- `SaveProfile` creating a profile that does not already exist.
- Retry on the Steam recovery screen.

Not exercised on hardware: the desktop-restore failure screen (requires
deliberately breaking a restore) and the startup-surface recovery path with the
network down.

Verified by static analysis only:

- Balanced brace depth, no duplicate definitions, no unreferenced functions, no
  lazily-created globals.
- All timer, hotkey, message and callback targets resolve.
- No variable shadows a function name; no function declares the same global twice.
- Settings-editor fields, embedded schema and sample INI agree.
- The validator's regex assertions were replayed in Python before the build.

## Known limits

- GDK titles using GameInput continue to receive controller input while the Quick
  Menu holds the foreground. Confirmed on Forza Horizon 6 with Steam Input
  disabled and the handoff verified. Not fixable in user mode; XInput has no
  exclusive mode and GameInput's background policy belongs to the application.
- `MinCenterCoverage` (0.40) and the frame-cap presets are code constants, not
  INI keys.
- Custom-mode selection is session state and is not persisted.
- Controller polling stops while the native tray menu is displayed. Accepted; see
  the reversal above.

## Checksums (SHA-256)

| File | SHA-256 |
|---|---|
| `Build-SteamShell.cmd` | `30a085ed1548c8cc3462dd3d31f0b5d4a02ca1594028d228a11ed68ad548b05a` |
| `Build-SteamShell.ps1` | `baa9319ccedbf8f42b5b5ff0713ee2746bcd489d36acef3c41912baba0672497` |
| `CHANGELOG.md` | `a85bec45b1ee5fd2a80a6aa4eaf303754d8a497618bfe57ef90728512c85557f` |
| `README.md` | `5c8f254a8b939b929837f106bd87f275b2b6f7cc959dd2ce54fc9c48e6da0afc` |
| `SteamShell.ahk` | `4ec3b04d124197fc03d1a1833907cb392779a6f8494d8d89d7ef496c884bef30` |
| `SteamShell.reg` | `4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a` |
| `SteamShellSettings_SAMPLE.ini` | `f58cbcc0131d7c376dabcf32d4bd9023d56e592f8d89a4a4d7133aaa903c89b2` |
| `Validate-SteamShell.ps1` | `1a77773caead14456c9858db4407dda7ee441250530fbc767961bff25117bf5b` |
| `WINDOWS_TEST_CHECKLIST.md` | `a20efa10978a92fcdab8d9e9f484c6dcc98cb47f10b942d4a1ab9c0741be5de6` |
| `XFE_PARITY_NOTES.md` | `e7d693f0f65921daace6eb23ce95e42cb8300edeb98ac5198b551287f172c5c3` |
| `assets/SteamShell-icon.png` | `bf8d9908917c4063e6bdb515a30e2519fa363d69b6ed08fb03dc6e2f1abc2170` |
| `assets/SteamShell.ico` | `260dba5dc8d228ede26089e63749ca53c0b2b3d369ff2b3cedd1232d4121a92b` |
| `extras/bigpicture_startup.webm` | `a12363458ace3a72a975c0ba650890960c439f39f96712805e896bf7c86f363b` |
| `extras/black.png` | `0ab0900f03e8f2a825691374d5e063a177085dc6a572ef15e7750b4a2bd69b41` |
| `images/control-panel.png` | `0199cfbf13f982031c536be47e312205b06960d5c206f6363d942830da25f42e` |
