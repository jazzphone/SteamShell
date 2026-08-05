# SteamShell 1.9.9 source release

This is the coordinated, self-contained pre-2.0 source release for both
SteamShell platforms:

- `SteamShell\` contains standalone SteamShell and its embedded elevated-helper
  source.
- `SteamShell-XFE\` contains the Xbox Full Screen Experience companion.

## Validate and build both applications

On Windows, install AutoHotkey v2.0.19 or newer with the Ahk2Exe compiler, then
double-click:

```text
Run-SteamShellValidation.cmd
```

The launcher runs the complete static, syntax, negative-build, and compilation
harness. A successful run writes each executable to its local `dist\` directory
and transactionally publishes both verified version-1.9.9.0 executables to this
release folder's `current\` directory.

The harness never starts either compiled executable.

## Build one application

- Double-click `SteamShell\Build-SteamShell.cmd` for `SteamShell.exe`.
- Double-click `SteamShell-XFE\Build-SteamShell-XFE.cmd` for
  `SteamShell-XFE.exe`.

The standalone build first validates and compiles
`SteamShell-Helper.ahk`, verifies helper file version 1.9.9.1, embeds that helper
into the main executable, and verifies the main file version is 1.9.9.0. The XFE
build verifies its output file version is 1.9.9.0. Each build runs its local
static validator before invoking AutoHotkey.

## Requirements and output

- Windows PowerShell 5.1 is the tested harness environment.
- AutoHotkey v2.0.19 or newer, 64-bit, including Ahk2Exe.
- Python is optional for compilation. Run
  `python SteamShell-XFE\Test-ControllerProfiles.py` separately when changing
  XFE's learned-controller decoder or profile format.
- Generated `build\`, `dist\`, and `current\` directories are not part of the
  locked source snapshot.

Do not run `SteamShell.exe` on a Windows machine unless you are prepared for it
to install or operate as the Winlogon shell. See each platform's README and
Windows test checklist before deployment.
