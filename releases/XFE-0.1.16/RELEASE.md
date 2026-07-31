# SteamShell XFE 0.1.16

Released: 2026-07-31

This directory is the locked source release for SteamShell XFE 0.1.16. Do not
edit this snapshot when later development resumes; make changes in
`SteamShell-XFE/` under a later version.

Build `SteamShell-XFE.ahk` on Windows by double-clicking
`Build-SteamShell-XFE.cmd`. The underlying PowerShell script requires AutoHotkey
v2.0.19 or newer with a 64-bit base, runs the static validator and AutoHotkey
syntax validation, and then compiles `dist\SteamShell-XFE.exe` with the included
icon.

No compiled EXE is stored in this snapshot.

**Settings schema stays at 3.** Nothing in 0.1.16 adds or retires an INI key.

## Release scope

0.1.16 is the RTSS frame-cap input work, designed once and applied to both trees
in the same pass rather than ported in either direction.

### The Custom FPS row no longer escalates its step

Quick Menu navigation is edge-triggered — the poll loop reports
`buttons & ~prevButtons` and the menu handler only ever received edges — so a
fixed step of 1 needed sixty presses to cross 60→120 and the step grew after
several fast presses: 1, then 5, then 10.

That made the same gesture produce different results depending on timing the user
could not see, and fast tapping — the natural response to a value moving too
slowly — became the thing that made it jump.

A press is now always exactly one step. Speed comes from **holding**, and
accelerates the repeat *rate* rather than the step: 80 ms, then 40 ms after
1.2 s, then 20 ms after 2.5 s. The value can therefore be stopped exactly where
wanted. This required passing the held button state into the menu handler, which
had never been given it — the constraint that made escalation seem necessary was
itself removable.

Repeat applies only to rows whose value is a number. Scrubbing a list-valued row
such as audio output at fifty changes a second would be useless and would fire
real device work per step.

### The write is debounced

`SetRtssGlobalFrameLimit` is a `LoadProfile` plus a `SetProfileProperty` plus a
`SaveProfile` — a disk write — plus `UpdateProfiles`. Writing per press meant the
limiter was genuinely reconfigured a dozen times during a scroll, and the frame
rate chased the number. The value is now held pending, the row renders it
immediately, and RTSS is written once ~400 ms after input stops.

Deferring the write introduced an ordering hazard, handled explicitly: choosing a
preset cancels anything pending, or the timer would fire afterwards and overwrite
it, and Save Limit to Profile flushes it, or the profile would receive a stale
value.

### Save Limit to Profile

The row reported `No game in foreground` while a game was running, because it
used only the foreground captured when the menu opened — regularly `steam.exe`,
which is excluded deliberately. It now falls back to the last foreground that
looked game-like, tracked by the foreground observer that already runs
unconditionally and which survives Steam coming forward afterwards.

## Verification status

**Validated on hardware by the maintainer prior to this lock.** The frame-cap
stepping behaviour was the subject of two rounds of hardware feedback and was
confirmed working at this revision: a press moves the value by exactly one
however fast presses arrive, and holding accelerates.

Carried forward from 0.1.15 and still confirmed: the motion-sensor exclusion in
the controller learner and the wizard's Skip bounds guard, on an 8BitDo
Ultimate 2 in DirectInput mode.

One check in `WINDOWS_TEST_CHECKLIST.md` is written to catch **silent** failure
and is worth repeating if behaviour is ever doubted, because it logs success
either way:

- `SaveProfile` creating a profile that does not already exist.

Verified by static analysis only:

- Balanced brace depth, no duplicate definitions, no unreferenced functions, no
  lazily-created globals.
- All timer, message and callback targets resolve.
- No variable shadows a function name; no function declares the same global twice.
- The validator's regex assertions were replayed in Python before the build.

## Known limits

- A DirectInput-mode pad is an ordinary HID gamepad, which is why no `dinput8`
  backend exists or is needed. RawInput registers for both the HID Gamepad and
  Joystick usages and already receives those reports.
- The 8BitDo Ultimate 2 returns no device path, VID/PID or preparsed descriptor,
  so its profile is keyed on report length (`LEN_34`) and any other 34-byte pad
  would match it. That also puts HID-descriptor parsing out of reach for it.
- The free-running threshold, the frame-cap presets and the repeat timings are
  code constants, not INI keys.
- Custom-mode selection is session state and is not persisted.
- XInput-only/XUSB pads still cannot be learned; they publish no HID gamepad
  collection for RawInput to read inside Xbox FSE.

## Checksums (SHA-256)

| File | SHA-256 |
|---|---|
| `Build-SteamShell-XFE.cmd` | `060b53005ae0a0ccfa47cd262f4fa6aa45e9b66e0b62fba6f26b5a90be4b4f11` |
| `Build-SteamShell-XFE.ps1` | `7a90e6c6e34051d84e361527586d566fbede4f85cafd5339d404d89d9c4c0eb6` |
| `README.md` | `007f34a260483da438410258e99647f2c0ab2519938ce315f47c0ebc718cfb17` |
| `SteamShell-XFE.ahk` | `9f777d7473afe1d05c9bf88bc1cc10ae07bc6a07c7d33637ba3498c0bff56a5a` |
| `SteamShell-XFE_SAMPLE.ini` | `7b52c72c8354a4a8e11982b09b5ce302ecc24c3ea1801557aad493ac847cd085` |
| `Test-ControllerProfiles.py` | `1b98b4d2cb21a479a545dd36c91020f85334e06d3b2ef0a152080d9ab0c96be0` |
| `Validate-SteamShell-XFE.ps1` | `090a5234d4478d4fb2940f996129e8ff443c245267cd2541fd587d10aa24c569` |
| `WINDOWS_TEST_CHECKLIST.md` | `4db58bbf48b52b214748c7f7b2855476a2e7efd85afa88f2bc287ec938abf557` |
| `assets/SteamShell-XFE-icon.png` | `c7a85f0e7bc20ec733fc5d9737167cde7965d4def90946353005926b85357005` |
| `assets/SteamShell-XFE.ico` | `2fe6f14f89e2a051e753a767b2da68e16f5666baef11d0252c954c5c69c93002` |
