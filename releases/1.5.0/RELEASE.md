# SteamShell 1.5.0

Released: 2026-07-25

This directory preserves the stable coordinated window-engine release selected
after HTPC runtime testing. It is the source-of-truth checkpoint for 1.5.0 and
should not be edited when later development resumes.

SteamShell remains one portable executable; installation is optional and uses
the same EXE. Build `SteamShell.ahk` on Windows with the included
`Build-SteamShell.ps1`. The script requires AutoHotkey v2.0.19 or newer with a
64-bit base and was tested with AutoHotkey v2.0.26 64-bit.

The build script runs the static validator and AutoHotkey syntax validation
before invoking Ahk2Exe. No compiled EXE is stored in this source snapshot.

## Release checkpoint

- Coordinated geometry and foreground window engine
- Steam Big Picture fallback and taskbar guarding
- Legacy fullscreen-game recognition
- Controller-first Quick Menu, Task Switcher, and Settings editor
- Portable setup, optional installation, health checks, and safe desktop restore
- Sleep-safe cursor hiding and verified game-to-Steam cursor parking
- Settings schema 6 with non-destructive synchronization and migration backups

## SHA-256

```text
2417a0021a2af2b28d23267b4ff0a7a94a7c8480f9379f9d5a390c6e09d53493  Build-SteamShell.ps1
93a854cca5f837ce590e46e9444c74c17e2ca3c72181aedcb65534f7f513757f  CHANGELOG.md
0bc8a4a7f3f532e76fd6b0542c9b62faebb92d1fe60f38618940114a710df20e  README.md
44fdfa261a09237a8230b7fe8eda3c3c258e9fb0404a3dc5fb942b462a908d8a  SteamShell.ahk
4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a  SteamShell.reg
a381d0afd6049b755978550ef1be65f15032a3c228f4de62abea0433611923c3  SteamShellSettings_SAMPLE.ini
7cce202496d7cbee43bc80afa2adb0ff5e834748942e6abe3bb7501b06fccb60  Validate-SteamShell.ps1
a5875723e163a8999ded0554a9014fad53c0051daa18132c8c796c30b8f8fd57  WINDOWS_TEST_CHECKLIST.md
a12363458ace3a72a975c0ba650890960c439f39f96712805e896bf7c86f363b  extras/bigpicture_startup.webm
0ab0900f03e8f2a825691374d5e063a177085dc6a572ef15e7750b4a2bd69b41  extras/black.png
0199cfbf13f982031c536be47e312205b06960d5c206f6363d942830da25f42e  images/control-panel.png
```
