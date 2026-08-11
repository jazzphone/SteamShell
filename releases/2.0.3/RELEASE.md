# SteamShell 2.0.3 coordinated release

Released: 2026-08-11

This directory is the immutable source lock for SteamShell 2.0.3 and
SteamShell-XFE 2.0.3, and it contains the verified installer built from that
source, on the same terms as 2.0.2.

`current\SteamShell.exe` is the executable produced by the validation harness in
this directory on the date above, from these exact sources.

    SHA-256  f2de422f3f2da01ee2e477c75383d874a3eb0f85734207961f65e29a30bab4a2
    Size     5,386,240 bytes

## Release scope

2.0.3 is a patch release on top of 2.0.2, and it does two things: it adds a way
to run SteamShell that does not replace the Windows shell, and it removes the
last places where the two products did the same job twice.

**SteamShell no longer has to be the Windows shell.** Setup's first question now
offers three answers rather than two, and the middle one -- *run alongside
Explorer* -- is the one to choose on a machine that is also used as a PC.
Explorer keeps the desktop and the taskbar, nothing is written to the shell
registry, and Steam is not launched automatically. What remains is the Quick
Menu, the controller pointer and mappings, RTSS control, startup programs and
Launcher Cleanup.

That mode was mostly already built. Exiting to the desktop has always stood down
precisely the four things that only mean anything while SteamShell owns
presentation -- the taskbar guard, the desktop backdrop, shell monitoring and the
window engine -- so Alongside is that state made permanent rather than a second
flag beside it. What it adds is refusal: the takeover is declined, the tray draws
no row offering it, and nothing writes the shell registry value.

The window engine is off there deliberately. Alongside assumes a keyboard and
mouse are within reach, and a program rearranging windows on an ordinary desktop
is an annoyance rather than a help.

**The GameInput backend is gone**, and the reason it went is the reason it
existed: it was measured byte-identical to XInput at every sample, including the
all-zero readings inside Xbox FSE. The two share a layer, so no choice between
them could help -- which is why RawInput was built. The measurement is kept in
`README-XFE.md`; the 189 lines of COM vtable interop that produced it are not.
Removing it made `ControllerReadState` identical in both products, so it is one
shared definition now instead of two.

**The elevated helper launch is one path.** Running the scheduled task, waiting
for the process, falling back to a UAC prompt and building the schtasks command
line were each written twice; they are written once. `schtasks.exe` is invoked by
absolute path in both products now -- the companion resolved it by bare name,
which is the weaker form in the one command whose purpose is to reach a
High-integrity token. Setup registers the companion's task while it already holds
an administrator token, so the companion no longer prompts on the secure desktop
the first time its helper is used.

## What a 2.0.2 user notices

- Setup asks a three-way question instead of a two-way one.
- The companion's Backend setting no longer offers `gameinput`. A settings file
  naming it falls back to `auto`.
- The companion's elevated helper is on by default, gated on the same setting the
  shell uses rather than on the RTSS frame-cap flag -- that flag had been doing
  two jobs since the helper gained input.
- The companion's helper task is renamed to "SteamShell XFE Elevated Input
  Helper". Registration and uninstall both retire the old name.
- The companion's tray gains Learn Controller and Delete Learned Profile.
- Launcher Cleanup keeps running after you exit to the desktop. It was gated on
  desktop mode, and closing a launcher that outlived its game has nothing to do
  with who owns the desktop.

## Validation

Built and verified by `Run-SteamShellValidation.ps1` in this directory: both
trees and the helper parse under AutoHotkey 2.0.26, both product validators pass,
and the structural half of both is replayed by `Replay-Validation.py`.

Two gates were added in this release. Seam **parameter shapes** are now compared
between the trees -- `$sharedSeamAllowed` recorded that those functions differ per
product but never checked that they take the same arguments, and two had drifted.
Seam **subset relationships** are reported, because one tree's call sequence being
a strict subset of the other's is the shape of a fix applied to one product and
not the other.

Four rules that only Windows could check are replayed in `Replay-Validation.py`
now: required functions, the elevation allowlist, continuation-section hazards,
and the sample INI against the embedded schema.

The full list of changes is in `SteamShell/CHANGELOG.md`.
