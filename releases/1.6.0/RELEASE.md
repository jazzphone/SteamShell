# SteamShell 1.6.0

Released: 2026-07-26

This directory is the immutable source checkpoint for SteamShell 1.6.0. It
captures the standalone SteamShell parity and usability work completed against
SteamShell-XFE while preserving standalone ownership of Steam, Explorer, the
taskbar, window focus, and desktop restoration.

SteamShell remains one portable executable; installation is optional and uses
the same EXE. Build `SteamShell.ahk` on Windows with `Build-SteamShell.cmd` or
`Build-SteamShell.ps1`. The script requires AutoHotkey v2.0.19 or newer with a
64-bit base. The build runs static validation and native AutoHotkey syntax
validation before invoking Ahk2Exe.

No compiled EXE is stored in this source snapshot. Source/schema/dispatch audits
passed at lock time. Native Windows compilation and the included hardware
acceptance checklist remain required before replacing a deployed shell binary.

## Release checkpoint

- XFE-parity persistent, borderless Quick Menu with foreground input ownership,
  keyboard/controller navigation, descriptive rows, and repaint-in-place updates
- XFE-matched Audio, Display & HDR, and RTSS & Performance submenus
- Independent staged resolution, refresh-rate, and scale selection with a
  guarded 15-second display transaction
- Live HDR and RTSS state with compatible shortcut fallbacks
- Reliable paced in-game Steam overlay chord delivery
- Task Switcher with A one-shot switching, Y switch-and-lock, X close, and
  hold-X force-close
- Standard, monitor-bounded Full Settings window with topmost owned dialogs and
  automatic controller pointer support across companion windows
- Configurable default-on administrator startup with an explicit unelevated-mode
  limitation warning
- Standalone executable/tray icon, double-clickable build launcher, portable
  shell registration, health checks, diagnostics, and guarded desktop restore
- Screen-coordinate cursor handling and selectable left/right mouse parking
- Settings schema 9 with non-destructive synchronization and migration backups

## Verification status

- Static source structure: passed
- Settings editor/schema parity: 76 fields and 155 schema keys
- Quick Menu dispatch inventory: 77 row IDs
- SteamShell-XFE source: unchanged
- Native AutoHotkey validation/build: run on Windows before deployment
- HTPC controller/display/RTSS acceptance: use `WINDOWS_TEST_CHECKLIST.md`

## SHA-256

```text
30a085ed1548c8cc3462dd3d31f0b5d4a02ca1594028d228a11ed68ad548b05a  Build-SteamShell.cmd
baa9319ccedbf8f42b5b5ff0713ee2746bcd489d36acef3c41912baba0672497  Build-SteamShell.ps1
4848a35cb174f1c2e8db69b89939d6767e5ef557cd8f1f4eaae71e1204a1e57f  CHANGELOG.md
e1681b83419c1be82f2cfe7ffc053cf872b1779a21882e50270586daca24f3de  README.md
94c1e25f806bea8311ea6bdc3593e3e7b38802cacada748696698eba3e9d4323  SteamShell.ahk
4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a  SteamShell.reg
13ec67ee57ee6f9f6376d0b1a4b6b4080fc12fa77d2b37682a3bdcd328882111  SteamShellSettings_SAMPLE.ini
33d60dab4a674fa8947ccad0d2e9628e8a78431f4d849a1d2337b8c0052ab792  Validate-SteamShell.ps1
506a2e299859b3f70b843f2cb59ed18bc0165a406bd5eca05e86cf6e09b0b46a  WINDOWS_TEST_CHECKLIST.md
f529b7ae85f7541db703e898fa55afe87f48670e178452f9b4fc9a6ee9df9df9  XFE_PARITY_NOTES.md
bf8d9908917c4063e6bdb515a30e2519fa363d69b6ed08fb03dc6e2f1abc2170  assets/SteamShell-icon.png
260dba5dc8d228ede26089e63749ca53c0b2b3d369ff2b3cedd1232d4121a92b  assets/SteamShell.ico
a12363458ace3a72a975c0ba650890960c439f39f96712805e896bf7c86f363b  extras/bigpicture_startup.webm
0ab0900f03e8f2a825691374d5e063a177085dc6a572ef15e7750b4a2bd69b41  extras/black.png
0199cfbf13f982031c536be47e312205b06960d5c206f6363d942830da25f42e  images/control-panel.png
```
