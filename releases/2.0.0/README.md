# SteamShell 2.0.0 — self-contained release bundle

This directory is the immutable source lock for SteamShell 2.0.0 and its
SteamShell-XFE companion, together with the verified installer built from it.

Everything needed to reproduce that installer is inside this directory. Copying
it elsewhere does not require the repository working tree or any earlier release.

## What is here

- `current\SteamShell.exe` — the verified installer, built and published by the
  validation harness below. **One executable installs both products.** It embeds
  the elevated helper and the XFE companion and deploys them through its Setup
  Assistant.
- `SteamShell\` — the complete source tree: all five AutoHotkey sources, both
  static validators, the shared parity checker, the build scripts, sample INIs,
  icons and documentation.
- `Run-SteamShellValidation.cmd` / `.ps1` — the full harness. Syntax-checks all
  sources, runs both validators, compiles all three binaries, proves the gate
  rejects broken and stale output, and republishes `current\` only if everything
  passes.
- `STEAMSHELL_PROJECT_OVERVIEW.md` — the design and incident record.

## Rebuild it yourself

Double-click `Run-SteamShellValidation.cmd`, or:

```
powershell -ExecutionPolicy Bypass -File Run-SteamShellValidation.ps1
```

Requires Windows, Windows PowerShell 5.1, and AutoHotkey v2 (2.0.19 or newer,
64-bit base) with Ahk2Exe. The harness resolves every path relative to its own
location.

To build only the installer, double-click `SteamShell\Build-SteamShell.cmd`. That
compiles and version-checks the helper (2.0.0.1), then the companion (2.0.0.0),
embeds both, and verifies the main executable reports 2.0.0.0. Each step runs the
local static validators before the compiler is started.

## Before you run the installer

**SteamShell replaces the Windows shell.** It rewrites the shell registry value,
terminates `explorer.exe` on its restore paths, and takes over the session. Test
it on a machine or account you are prepared to restore.

`Ctrl+Alt+Shift+E` is the emergency permanent restore: it registers Explorer as
the shell and closes SteamShell.

The validation harness never runs the executables it produces, and neither should
an automated process.
