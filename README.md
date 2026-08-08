# SteamShell

**Boot straight into Steam Big Picture, and drive Windows from the couch with a controller.**

SteamShell replaces the Windows shell with Steam Big Picture Mode. It keeps the right
window in front, gives you a controller-driven pointer and Quick Menu, and hands the
desktop back cleanly when you're done.

Its companion, **SteamShell XFE**, does the controller half *without* replacing anything —
for people running Windows' Xbox Full Screen Experience instead.

> [!WARNING]
> **SteamShell is a Windows shell replacement.** It rewrites the shell registry value,
> terminates `explorer.exe` on its restore paths, and takes over the session.
> **Test it on a machine or account you are prepared to restore.**
>
> `Ctrl+Alt+Shift+E` is the emergency permanent restore: it registers Explorer as the
> shell and closes SteamShell. Learn it before you need it.
>
> The XFE companion changes nothing about your shell and carries none of this risk.

![SteamShell Control Panel running inside Steam Big Picture](SteamShell/images/control-panel.png)

## Download

**[Latest release &rarr; SteamShell.exe](https://github.com/jazzphone/SteamShell/releases/latest)**

One executable installs both products. It embeds the elevated helper and the XFE
companion and deploys whichever you choose through its Setup Assistant.

Verify it if you like — the same binary is committed at
`releases/2.0.0/current/SteamShell.exe` and its SHA-256 is in
[`releases/2.0.0/RELEASE.md`](releases/2.0.0/RELEASE.md) alongside the exact source
that produced it.

## Getting started

1. Put `SteamShell.exe` somewhere sensible and run it.
2. The **Setup Assistant** opens on first run. Pick which product you want, confirm the
   detected Steam path, and choose whether to register as the shell.
3. Press `Ctrl+Alt+Shift+S` for the full Settings editor, or hold **L3 + R3** on a
   controller for the Quick Menu.

Requires Windows 10 or 11. Running from source additionally needs AutoHotkey v2.0.19 or
newer, 64-bit.

## Which one do I want?

|  | **SteamShell** | **SteamShell XFE** |
|---|---|---|
| Replaces the Windows shell | Yes | **No** |
| Boots to Steam Big Picture | Yes | No — you use Xbox FSE |
| Controller pointer and Quick Menu | Yes | Yes |
| Window management and focus assist | Yes | Lightweight assist only |
| Display, HDR, audio, RTSS controls | Yes | Yes |
| Risk if something goes wrong | You may need to restore the shell | Close it |

Both are 2.0.0 and share most of their code.

## Hotkeys

| Key | Action |
|---|---|
| `Ctrl+Alt+Shift+E` | **Emergency permanent restore** — Explorer becomes the shell again |
| `Ctrl+Alt+Shift+Q` | Quick Menu |
| `Ctrl+Alt+Shift+S` | Settings editor |
| `Ctrl+Alt+Shift+P` | Control Panel |
| `Ctrl+Alt+Shift+R` | Reload settings |
| `Ctrl+Alt+Shift+G` | Run Game Foreground Assist once |
| `Ctrl+Alt+Shift+I` | Re-arm controller input |

On a controller: hold **L3 + R3** for the Quick Menu, hold **View/Back** for the mouse
pointer, and hold **View/Back + Start** for the Windows Start menu.

## Documentation

The [**wiki**](https://github.com/jazzphone/SteamShell/wiki) is the reader-friendly
documentation — installing, settings, controller mappings, troubleshooting.

In-repo, for depth:

| File | What it covers |
|---|---|
| [`SteamShell/README.md`](SteamShell/README.md) | Full standalone reference |
| [`SteamShell/README-XFE.md`](SteamShell/README-XFE.md) | Full companion reference |
| [`SteamShell/CHANGELOG.md`](SteamShell/CHANGELOG.md) | Every change, by release |
| [`STEAMSHELL_PROJECT_OVERVIEW.md`](STEAMSHELL_PROJECT_OVERVIEW.md) | Design decisions and incident write-ups |
| [`SteamShell/WINDOWS_TEST_CHECKLIST.md`](SteamShell/WINDOWS_TEST_CHECKLIST.md) | What to exercise on real hardware |

## Building from source

```
Run-SteamShellValidation.cmd
```

Syntax-checks all five AutoHotkey sources, runs both static validators, compiles the
helper, the companion and the installer, proves the build gate rejects broken and stale
output, and only then publishes to `current\`.

Needs Windows, PowerShell 5.1, and AutoHotkey v2 with Ahk2Exe. To build the installer
alone, use `SteamShell\Build-SteamShell.cmd`.

The harness never runs what it compiles, and neither should any automated process.

## A note on how this is built

Two programs share one codebase. `SteamShell-Common.ahk` is compiled into all three
binaries, `SteamShell-Shared.ahk` into both main products, and a set of static
validators enforce that: exact function manifests, a duplicate-detection gate, and
assertions that pin behaviour rather than implementation. If a shared function drifts,
a count goes stale, or a fix lands in one product and not the other, the build fails.

`SteamShell/DIVERGENT_FUNCTIONS.txt` records every place the two products *deliberately*
differ, with the reason — because a divergence nobody wrote down is indistinguishable
from a bug nobody noticed.

## Licence and support

**No support is provided. Use at your own risk.**

This is a personal project shared in case it's useful. It replaces the Windows shell;
please read the warning at the top before running it on a machine that matters to you.
