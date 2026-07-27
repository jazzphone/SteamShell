# SteamShell 1.7.0

Released: 2026-07-26

This directory is the immutable source checkpoint for SteamShell 1.7.0. It
captures the desktop-mode work: SteamShell now survives exiting to the Windows
desktop instead of terminating, so its notification-area icon, controller mouse,
and Quick Menu stay available on the normal desktop. It also adds a black
desktop background for the gaps around Steam.

SteamShell remains one portable executable; installation is optional and uses
the same EXE. Build `SteamShell.ahk` on Windows with `Build-SteamShell.cmd` or
`Build-SteamShell.ps1`. The script requires AutoHotkey v2.0.19 or newer with a
64-bit base. The build runs static validation and native AutoHotkey syntax
validation before invoking Ahk2Exe.

No compiled EXE is stored in this source snapshot. Source/schema/dispatch audits
passed at lock time. Native Windows compilation and the included hardware
acceptance checklist remain required before replacing a deployed shell binary.

## Release checkpoint

- **Desktop mode.** Exiting to the desktop no longer terminates SteamShell.
  Explorer takes the desktop back while SteamShell stays resident, entered from
  the automatic Steam-exit restore, Quick Menu, the tray, and the
  Steam-did-not-start recovery screen
- Context-aware notification-area menu with a genuine **Exit SteamShell** that
  performs the guarded desktop restore first when leaving shell mode
- `TaskbarCreated` listener that re-asserts the tray icon, plus tray
  initialisation ahead of SteamShell's own Explorer launch, so the icon survives
  both the first boot and the Explorer restart performed during a restore
- Shell enforcement isolated from controller input: desktop mode leaves shell
  monitoring, the window engine, the Taskbar Guard, cursor hiding, and Launcher
  Cleanup unscheduled while controller polling stays alive, with no persisted
  setting mutated
- Explicit Steam-lifecycle disarm and suppressed unexpected-exit Explorer
  recovery in desktop and safe modes, so killing SteamShell cannot restart a
  live Explorer session or drop the next-sign-in shell registration
- **Launch Steam** replaces the Steam Menu row when Steam is not running, and
  re-arms shell mode only for a launch SteamShell performed itself
- **Black desktop background** (`[Features] EnableDesktopBlackout`, default on):
  a non-activating full-screen backdrop with `Progman`/`WorkerW` hidden through
  the Taskbar Guard's event-hook and periodic-safety pattern, owning no system
  or registry state and toggleable from the Quick Menu with immediate effect
- Tray right-click opens the Quick Menu instead of a native menu, because
  AutoHotkey suspends timers while a menu is displayed and that froze
  controller-as-mouse
- Recovery-screen **Restore Desktop** downgraded from a permanent to a session
  restore, so one failed Steam launch no longer deregisters the Windows shell
- Visible failure paths for Steam shutdown, including an offer to restore the
  desktop anyway when Steam will not close
- Settings schema 10 with non-destructive synchronization and migration backups

## Static validation additions

- Desktop-mode contract: session/permanent exit split, lifecycle disarm, timer
  isolation, tray re-assert, tray-before-Explorer ordering, suppressed exit
  recovery, and the tray right-click interception
- Desktop-blackout contract: non-activating backdrop, paint-before-hide
  ordering, release on all four Explorer-handoff paths, and the controller
  toggle
- AutoHotkey v2 language limits that the interpreter only reports at build time:
  an `else` attached to a braceless `try`, and a `Case` carrying more than 20
  values
- Quick Menu settings rows dispatched through shared predicates are counted as
  activation coverage, both switches must still consult those predicates, and a
  predicate id without a matching row is now an error

## Verification status

- Static source structure: passed
- Settings editor/schema parity: 77 fields and 156 schema keys
- Quick Menu dispatch inventory: 81 row IDs
- Functions: 509; named callbacks: 93
- SteamShell-XFE source: unchanged
- Native AutoHotkey validation/build: run on Windows before deployment
- HTPC controller/display/RTSS acceptance: use `WINDOWS_TEST_CHECKLIST.md`

## Hardware verification still outstanding

The desktop blackout hides `Progman`/`WorkerW`. That is reasoned by analogy to
the taskbar hiding SteamShell already performs, not verified on hardware. Game
Bar and other UWP surfaces are the most likely to object. The blackout section
of `WINDOWS_TEST_CHECKLIST.md` covers this, and the feature can be switched off
from Quick Menu ▸ Settings ▸ General + Startup with immediate effect.

## SHA-256

```text
30a085ed1548c8cc3462dd3d31f0b5d4a02ca1594028d228a11ed68ad548b05a  Build-SteamShell.cmd
baa9319ccedbf8f42b5b5ff0713ee2746bcd489d36acef3c41912baba0672497  Build-SteamShell.ps1
91a3c658bf288614c69f6dfa8467c37e35e4574ef8a07052901142d9522a5df6  CHANGELOG.md
3bd27d8499bb694b45d27d6844b8f72e4b22051fc1a1be50ee19df4e63cf16b7  README.md
cbd8c774db0edd457541c1020cabef1500bf7105966cb046d50729f66576d49b  SteamShell.ahk
4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a  SteamShell.reg
f58cbcc0131d7c376dabcf32d4bd9023d56e592f8d89a4a4d7133aaa903c89b2  SteamShellSettings_SAMPLE.ini
cc1fb5b04e8b873a0b6151a3e3e12c24bc9a46c270e8582d62d033a862a91086  Validate-SteamShell.ps1
0bea9024237c97c499b56e9f26d6554c640f225bb26a4bf4c196a76fb493f06d  WINDOWS_TEST_CHECKLIST.md
8bed28ad7233a08ab0173f6e57367a6407f7faa06cdf2880100cf836b59fe8f3  XFE_PARITY_NOTES.md
bf8d9908917c4063e6bdb515a30e2519fa363d69b6ed08fb03dc6e2f1abc2170  assets/SteamShell-icon.png
260dba5dc8d228ede26089e63749ca53c0b2b3d369ff2b3cedd1232d4121a92b  assets/SteamShell.ico
a12363458ace3a72a975c0ba650890960c439f39f96712805e896bf7c86f363b  extras/bigpicture_startup.webm
0ab0900f03e8f2a825691374d5e063a177085dc6a572ef15e7750b4a2bd69b41  extras/black.png
0199cfbf13f982031c536be47e312205b06960d5c206f6363d942830da25f42e  images/control-panel.png
```
