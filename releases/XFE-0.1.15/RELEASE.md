# SteamShell XFE 0.1.15

Released: 2026-07-31

This directory is the locked source release for SteamShell XFE 0.1.15. Do not
edit this snapshot when later development resumes; make changes in
`SteamShell-XFE/` under a later version.

Build `SteamShell-XFE.ahk` on Windows by double-clicking
`Build-SteamShell-XFE.cmd`. The underlying PowerShell script requires AutoHotkey
v2.0.19 or newer with a 64-bit base, runs the static validator and AutoHotkey
syntax validation, and then compiles `dist\SteamShell-XFE.exe` with the included
icon.

No compiled EXE is stored in this snapshot. The source, documented
configuration, validation, simulation, build launchers, icon assets, and test
checklist are the authoritative release.

**Settings schema stays at 3.** Nothing in 0.1.15 adds or retires an INI key.

## Release scope

0.1.15 is a controller-learning and RTSS release on top of 0.1.14.

### The learner survives a motion-sensor controller

Measured on an **8BitDo Ultimate 2** in DirectInput mode: a 34-byte report at
roughly 1 kHz, of which **12 bytes were still changing with the controller
untouched** — six 16-bit motion axes.

The axis search ranks candidates by how far they travelled, and a motion axis
travels its full range continuously, so it beat the real stick on every step:

```text
Learn: rest sampled from 1822 reports; 12 of 34 bytes changed during rest.
Learn: LX not detected -- byte 22 u8 rests at 0% of range, and a stick rests at the centre.
Learn: RT = byte 22 u16le neutral 62720 direction -1
```

All four sticks were rescued by the existing rest-at-centre rule. **RT was not.**
A trigger legitimately rests at an end of its range, so it had no equivalent
sanity check and bound itself to a motion byte — saving into the profile as a
permanently deflected trigger.

A byte still changing across four or more of its bits while nothing is held is
now treated as free-running and withheld from the axis search. The discriminator
is bit count, not movement: a stick resting at centre jitters in its lowest one
or two bits, while a motion axis saturates the byte. If the filter leaves no
candidate at all, the search retries once with those bytes restored and logs that
it did, so a controller whose sticks genuinely jitter widely stays learnable.

### Wizard Skip crash

`ControllerLearnNextStep` increments the step index unconditionally, so after the
final step it sits one past the end while the wizard finishes and saves. Skip is
a GUI button and can be clicked inside that window, which indexed the step array
out of range and threw `Invalid index: 23` on hardware. It now checks the upper
bound as well as the lower one.

### RTSS frame cap is writable from the Quick Menu

One **Frame Limit** row folds RTSS's two independent mechanisms — the global
limiter flag and the profile's `FramerateLimit` — into a single control cycling
`Off · 30 · 40 · 60 · 90 · 120 · Custom`. Selecting `Custom` reveals a **Custom
FPS** row whose step escalates 1 → 5 → 10 on consecutive presses, because Quick
Menu navigation is edge-triggered and never auto-repeats.

"Off" maps to the flag and never writes `0`, so a cap survives an off/on round
trip. Every write targets the **global** profile; the only per-game write is the
explicit, two-press **Save Limit to Profile** row, which loads the target profile
first so the game's other tuning survives.

Requires `SetProfileProperty`, `SaveProfile` and `UpdateProfiles` from
`RTSSHooks64.dll`. All three are optional — a build without them keeps overlay
and limiter control and shows the cap read-only.

The separate Frame Limiter row is gone wherever live DLL control is available;
the shortcut fallback still shows both, because without the DLL there is no value
to fold in.

### Housekeeping

- Removed the handler cases and functions left dead by the row merge, including
  `GetRtssFrameCapLabel`, plus five other unreferenced functions.
- Updated `Validate-SteamShell-XFE.ps1`, whose three RTSS parity assertions still
  described the removed `rtssLimiterState` row.

## Verification status

**Confirmed on hardware, specifically:**

- The motion-sensor fix and the Skip bounds guard, on an 8BitDo Ultimate 2 in
  DirectInput mode. This was the failure that motivated the release, and the fix
  was confirmed working by the maintainer.
- The build compiles and the static validator passes.
- General operation validated by the maintainer prior to this lock.

This is a maintainer-reported pass rather than an item-by-item transcript of
`WINDOWS_TEST_CHECKLIST.md`. One check in that document is written to catch
**silent** failure and is worth repeating if behaviour is ever doubted, because
it logs success either way:

- **`SaveProfile` creating a profile that does not exist.** If the installed RTSS
  only overwrites existing profiles, Save Limit to Profile does nothing while the
  log reports success. Confirm a new `.cfg` appears in RTSS's `Profiles` folder.

Verified by static analysis only, without hardware:

- The source lexes to balanced brace depth with no duplicate definitions.
- All timer, message and callback targets resolve to defined functions.
- No variable shadows a function name; no function declares the same global
  twice.
- The validator's regex assertions were replayed in Python before the build.

## Known limits

- **A DirectInput-mode pad is an ordinary HID gamepad.** RawInput registers for
  both the HID Gamepad (`0x05`) and Joystick (`0x04`) usages and already receives
  those reports, so no `dinput8` backend exists or is needed. That decision is
  recorded rather than left implicit.
- **The Ultimate 2 returns no device path, VID/PID, or preparsed descriptor**, so
  its profile is keyed on report length (`LEN_34`) and any other 34-byte pad
  would match it. The missing preparsed descriptor also means HID-descriptor
  parsing is not available for this device through that route.
- The free-running threshold (four bits) is a code constant, not an INI key.
- The frame-cap presets are a code constant (`RtssFrameCapPresets`).
- Custom-mode selection is session state and is not persisted.
- XInput-only/XUSB pads still cannot be learned; they publish no HID gamepad
  collection for RawInput to read inside Xbox FSE.

## Checksums (SHA-256)

| File | SHA-256 |
|---|---|
| `Build-SteamShell-XFE.cmd` | `060b53005ae0a0ccfa47cd262f4fa6aa45e9b66e0b62fba6f26b5a90be4b4f11` |
| `Build-SteamShell-XFE.ps1` | `7a90e6c6e34051d84e361527586d566fbede4f85cafd5339d404d89d9c4c0eb6` |
| `README.md` | `375fe9ac7e2d4db6ddf89a815860620b41bebf6241903188ba29f7bf9cb91f28` |
| `SteamShell-XFE.ahk` | `88e3835327e31ccbf5e6665208a768c84db1b06457e4b8dca693b07cb745cc98` |
| `SteamShell-XFE_SAMPLE.ini` | `7b52c72c8354a4a8e11982b09b5ce302ecc24c3ea1801557aad493ac847cd085` |
| `Test-ControllerProfiles.py` | `1b98b4d2cb21a479a545dd36c91020f85334e06d3b2ef0a152080d9ab0c96be0` |
| `Validate-SteamShell-XFE.ps1` | `090a5234d4478d4fb2940f996129e8ff443c245267cd2541fd587d10aa24c569` |
| `WINDOWS_TEST_CHECKLIST.md` | `6e8a1e0aa54f4cfc2d8c85343cf2bb6f3350092e6aafdec38eab7a71dceedea0` |
| `assets/SteamShell-XFE-icon.png` | `c7a85f0e7bc20ec733fc5d9737167cde7965d4def90946353005926b85357005` |
| `assets/SteamShell-XFE.ico` | `2fe6f14f89e2a051e753a767b2da68e16f5666baef11d0252c954c5c69c93002` |
