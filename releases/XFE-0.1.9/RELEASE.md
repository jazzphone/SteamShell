# SteamShell-XFE 0.1.9

Locked: 2026-07-26

This directory preserves the SteamShell-XFE companion source at the point where
the controller-learning wizard was first confirmed working on real hardware. It
is a **source checkpoint to return to**, not a finished release, and should not
be edited when development continues in `SteamShell-XFE/`.

Build `SteamShell-XFE.ahk` on Windows with the included
`Build-SteamShell-XFE.ps1`. The script requires AutoHotkey v2.0.19 or newer with
a 64-bit base and was tested with AutoHotkey v2.0.26 64-bit. It runs the static
validator and AutoHotkey syntax validation before invoking Ahk2Exe. No compiled
EXE is stored in this snapshot — the one present in the working directory at the
time of locking predated these sources and would have been misleading to keep.

## Why this point was chosen

0.1.8 introduced learned RawInput controller profiles that passed a written
simulation and then failed repeatedly on hardware. 0.1.9 is the round that made
them work. Confirmed by the user on 2026-07-26:

> The learn controller wizard is working and the results are working as well.

That was verified on two different machines — a ROG Xbox Ally X and an HTPC with
an Xbox controller — which is the first time any learned-profile build has been
confirmed on more than one.

## What is verified, and what is not

**Verified on hardware:**

- The learning wizard completes and the resulting profile drives the pointer,
  buttons, D-pad and triggers correctly.
- The pointer is steady after saving, on both machines.

**Verified by automated check only:**

- 94 static validator assertions (`Validate-SteamShell-XFE.ps1`).
- 13 simulation tests (`Test-ControllerProfiles.py`), including the Settings
  layout overlap check.
- Setting parity: every setting the runtime reads exists in the sample INI, and
  every setting the Settings window writes is both loaded and documented — 51
  fields, no gaps either way.

**Not verified at all.** Several fixes landed after the last hardware session
and have never run:

- Startup-program launch window mode (Normal / Minimized / Hidden), including
  the de-elevated route where `explorer.exe` chooses the show state.
- The cursor park edge, now defaulting to centre-right.
- Topmost dialogs — every `MsgBox` and `FileSelect` was rerouted so a dialog is
  not hidden behind its own always-on-top owner.

`WINDOWS_TEST_CHECKLIST.md` opens with an eight-item "test these first" list
covering exactly these.

## Contents of this checkpoint

- Learned RawInput controller profiles, with the 0.1.9 hardening: little-endian
  only, stick centre-of-range check, sticks may not share bytes *except their
  own field*, rejected axes delete their provisional entry and record the real
  reason, opening analogue scan, press-and-release gating, an inert controller
  while the wizard is open, digital step timeouts, D-pad set validation, and a
  post-save rest check with profile deletion.
- Recovery paths that work without a pointer or a controller:
  `Ctrl+Alt+Shift+D` deletes a learned profile, `Ctrl+Alt+Shift+I` re-arms
  controller input, `Ctrl+Alt+Shift+Q`/`S`/`P` reach the menus from a keyboard.
- Quick Menu Settings page with live toggles written to the INI on the spot.
- Assist features with shell-overlay suspension for the Xbox FSE task switcher,
  matched by window class.
- Logon task registered from XML so it starts on battery.
- Settings schema 3.

## Known limits recorded at lock time

- **Signed axes are not supported.** The decoder reads `u8`, `u16le` and
  `u16be`. A controller reporting sticks as signed would be rejected by the
  centre-of-range check — legibly, since rejections now log their reason, but
  rejected. Adding `s16le` is a small change and deliberately not made without a
  device that needs it.
- **Only one side of each axis is measured.** The wizard prompts one direction
  and applies that travel to both sides. A genuinely asymmetric axis would
  saturate slightly early one way. A scaling imperfection, not a sign error.
- **Byte-aligned fields only.** Axes packed at 12 bits, or two axes across three
  bytes, would not learn.
- **The wizard derives the report layout independently in each axis step.** The
  stick-claiming and centre-of-range rules constrain it, but the durable design
  determines the layout *once* from the opening analogue scan and then only asks
  which axis is which. That remains the next real piece of engineering.
- **Shared trigger axes cannot report both triggers at once.** Chords must not
  require both; the Settings chord deliberately avoids them.

## SHA-256

```text
b814fc6190dc32fe17497423f6474e30f53b5354e256020b8c55e7d266295623  Build-SteamShell-XFE.ps1
1b3fbb140c9fbb74b76e81dd5c4ad22f046f38e51101a060ef7591d61bbab8df  README.md
3d8f8c60159a41d480ed3c2fdd03041f5aa9bc11a41ab663ea650d21f1abfd3d  SteamShell-XFE.ahk
1dcf6fa7d14b522165038e854f27a9ffaab1cbe6aae81c4f1df7896ff9e6a32d  SteamShell-XFE_SAMPLE.ini
a753a95d2f54ab399709928d11449bde8216a3bed4ec5852770d537796e8e70d  Test-ControllerProfiles.py
cd946e052d01a26af8010b121ca823de3b029919bcc624683a2d955389e100bd  Validate-SteamShell-XFE.ps1
2b72da4bdea9ab610bc0f2a2b8fdec4b253220decf0fa928f78f521edb46cd2d  WINDOWS_TEST_CHECKLIST.md
```

## Returning to this checkpoint

Copy the files back over `SteamShell-XFE/`, then confirm the checksums above
match before building. `Test-ControllerProfiles.py` runs anywhere Python 3 is
available and needs neither Windows nor a controller, so it is the fastest
confirmation that a restored tree is intact.
