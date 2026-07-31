# SteamShell 1.7.1

Released: 2026-07-31

This directory is the locked source release for SteamShell 1.7.1. Do not edit
this snapshot when later development resumes; make changes in `SteamShell/`
under a later version.

Build `SteamShell.ahk` on Windows by double-clicking `Build-SteamShell.cmd`. The
underlying PowerShell script requires AutoHotkey v2.0.19 or newer with a 64-bit
base, runs `Validate-SteamShell.ps1` and AutoHotkey syntax validation, and then
compiles `dist\SteamShell.exe` with the included icon.

No compiled EXE is stored in this snapshot. The source, documented
configuration, validator, build launchers, icon assets, and test checklist are
the authoritative release.

**Settings schema stays at 10.** Nothing in 1.7.1 adds or retires an INI key, so
upgrading from 1.7.0 involves no migration and existing configuration files are
untouched.

## Release scope

1.7.1 is a reliability and audit release on top of 1.7.0. It adds no new
subsystem; every change either fixes a failure observed on hardware or removes
code that no longer had a caller.

### Steam startup is judged by a window, not a process

`MonitorShell` previously accepted `ProcessExist("steam.exe")` as proof that
Steam had started. On a Wi-Fi handheld the process appears almost immediately
and then sits on a "Connecting", sign-in, or client-update window for as long as
the network takes; on Ethernet the Big Picture window wins that race and the
state is never reached.

The consequence was worse than a slow start. Seeing the process set
`SteamObservedRunning` on the first tick, and every branch that can raise the
recovery screen is nested under `!SteamObservedRunning` — so the recovery screen
became permanently unreachable, the session was marked `ACTIVE`, and the startup
curtain stayed up over nothing. On a machine where SteamShell is the Winlogon
shell, that is an indefinite black screen with no taskbar and no cursor.

Startup now requires a Steam-owned window covering at least 60% of its monitor
in both dimensions. Coverage rather than title is deliberate: it survives client
updates, a renamed or localised window title, and the
`steam.exe`/`steamwebhelper.exe` ownership split. Once seen, the observation is
**latched** and never re-tested, so a game covering or minimising Big Picture
cannot re-open the startup path.

Three supporting fixes were required for that to be reachable at all:

- `ShowStartupRecovery` and `ShowPendingStartupRecovery` both returned early when
  `steam.exe` existed — the exact state a stalled boot is in.
- `LaunchSteamBpm` latched observation whenever Steam was already running, so
  **Retry** on the recovery screen dismissed the screen and stranded the user.
- The splash guard re-asserted topmost twice a second with no awareness of
  SteamShell's own windows, so the recovery screen was buried within 500 ms.

### RTSS frame cap is now writable from the Quick Menu

One **Frame Limit** row folds RTSS's two independent mechanisms — the global
limiter flag and the profile's `FramerateLimit` — into a single control cycling
`Off · 30 · 40 · 60 · 90 · 120 · Custom`. Selecting `Custom` reveals a **Custom
FPS** row whose step escalates 1 → 5 → 10 on consecutive presses, because Quick
Menu navigation is edge-triggered and never auto-repeats.

"Off" maps to the flag and never writes `0`, so a cap survives an off/on round
trip instead of being forgotten. Every write targets the **global** profile; the
only per-game write is the explicit, two-press **Save Limit to Profile** row,
which loads the target profile first so the game's other tuning survives.

Requires `SetProfileProperty`, `SaveProfile` and `UpdateProfiles` from
`RTSSHooks64.dll`. All three are optional — a build without them keeps overlay
and limiter control and shows the cap read-only.

### Controller Settings chord

`LT+RT+LB+RB+L3+R3` now requires a **hold**, declines while another surface
already owns controller input, and returns once fired. It previously fired on the
press edge from above the poll's consumer gates, so a stray grip during play
could throw Full Settings over a running game, and pressing it with the Quick
Menu open produced a focused Settings window that ignored input while the menu
behind it kept responding.

### Codebase audit

- 16 unreferenced functions removed, including two mutually-referencing chains (a
  theming chain and a geometry chain) that only kept each other alive.
- 8 dead Quick Menu handler cases removed.
- 13 globals that existed only as in-function declarations given script-scope
  declarations, and two script-scope variables given `global` so they are
  super-globals like the other 311.
- Both validators updated; their RTSS parity assertions still described the
  removed `rtssLimiterState` row and failed the build.

## Verification status

**Validated on hardware by the maintainer prior to this lock**, on a ROG Xbox
Ally X and an Ethernet-connected HTPC. The build compiles, the static validator
passes, and general operation was confirmed.

This is a maintainer-reported pass rather than an item-by-item transcript of
`WINDOWS_TEST_CHECKLIST.md`. Two checks in that document are written to catch
**silent** failure and are worth repeating if behaviour is ever doubted, because
each logs success either way:

- **`SaveProfile` creating a profile that does not exist.** If the installed RTSS
  only overwrites existing profiles, Save Limit to Profile does nothing while the
  log reports success. Confirm a new `.cfg` appears in RTSS's `Profiles` folder.
- **Retry on the Steam recovery screen.** With Steam running but not rendering,
  Retry previously marked the session healthy and dismissed the only way back.

Verified by static analysis only, without hardware:

- Both source files lex to balanced brace depth with no duplicate definitions.
- All `SetTimer` / `Hotkey` / `OnMessage` / `CallbackCreate` / `OnExit` targets
  resolve to defined functions.
- No variable shadows a function name; no function declares the same global
  twice; no `case` carries more than 20 values.
- Every Settings-editor field maps to a key `LoadSettings` reads, and the
  embedded and sample INI schemas agree.
- The validator's regex assertions were replayed in Python before the build.

## Known limits

- The 60% monitor-coverage threshold for Big Picture is a constant
  (`SteamStartupSurfaceMinCoverage`), not an INI key.
- The frame-cap presets are a code constant (`RtssFrameCapPresets`), not
  configurable.
- Custom-mode selection is session state and is not persisted.
- `SteamShell.reg` still assumes `C:\Utilities\SteamShell.exe` and remains a
  manual fallback; the Install action is the supported route.

## Checksums (SHA-256)

| File | SHA-256 |
|---|---|
| `Build-SteamShell.cmd` | `30a085ed1548c8cc3462dd3d31f0b5d4a02ca1594028d228a11ed68ad548b05a` |
| `Build-SteamShell.ps1` | `baa9319ccedbf8f42b5b5ff0713ee2746bcd489d36acef3c41912baba0672497` |
| `CHANGELOG.md` | `27e0a0dee824d9646cae55fa0e6d42a9f43189027c0387b85201bcd2bc82c4fd` |
| `README.md` | `dd0c8f46422f145159fedca0edcf1c3b00046f1c843f4bdc94171a074a20a1e9` |
| `SteamShell.ahk` | `f94b5fdd1a271b3368f81f76a657dbfcabd2407522d275132e8504f67af3c7c9` |
| `SteamShell.reg` | `4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a` |
| `SteamShellSettings_SAMPLE.ini` | `f58cbcc0131d7c376dabcf32d4bd9023d56e592f8d89a4a4d7133aaa903c89b2` |
| `Validate-SteamShell.ps1` | `dacbd7ff593f6fe220c8d016483fc47ff3cb8bc881406d59199c04efff5d2ba5` |
| `WINDOWS_TEST_CHECKLIST.md` | `c25152f4b61bc466ad152444f6b8519acb4e28cb4b31ba70017ff7c270d4f374` |
| `XFE_PARITY_NOTES.md` | `d89f44b40e9023314711480f0eba818ca1813ef08a6ccab52552c3915ad7a03e` |
| `assets/SteamShell-icon.png` | `bf8d9908917c4063e6bdb515a30e2519fa363d69b6ed08fb03dc6e2f1abc2170` |
| `assets/SteamShell.ico` | `260dba5dc8d228ede26089e63749ca53c0b2b3d369ff2b3cedd1232d4121a92b` |
| `extras/bigpicture_startup.webm` | `a12363458ace3a72a975c0ba650890960c439f39f96712805e896bf7c86f363b` |
| `extras/black.png` | `0ab0900f03e8f2a825691374d5e063a177085dc6a572ef15e7750b4a2bd69b41` |
| `images/control-panel.png` | `0199cfbf13f982031c536be47e312205b06960d5c206f6363d942830da25f42e` |
