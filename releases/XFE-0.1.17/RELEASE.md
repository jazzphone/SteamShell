# SteamShell XFE 0.1.17

Released: 2026-07-31

This directory is the locked source release for SteamShell XFE 0.1.17. Do not
edit this snapshot when later development resumes; make changes in
`SteamShell-XFE/` under a later version.

Build `SteamShell-XFE.ahk` on Windows by double-clicking
`Build-SteamShell-XFE.cmd`. The underlying PowerShell script requires AutoHotkey
v2.0.19 or newer with a 64-bit base, runs the static validator and AutoHotkey
syntax validation, and then compiles `dist\SteamShell-XFE.exe` with the included
icon.

No compiled EXE is stored in this snapshot.

**Settings schema moves 3 → 4.** Existing values remain authoritative. The
migration adds the Quick Menu accent preset and custom-color keys only when
missing.

## Release scope

- Replaces the Quick Menu row-control pool with one opaque, high-DPI GDI+
  surface using rounded selection, accent outline/bar/glow, neutral `#242424`
  charcoal, neutral-gray text, and atomic open-session repainting.
- Adds nine Quick Menu accent presets plus a custom `RRGGBB` value, with the
  selected fill derived from the accent.
- Suppresses the native/DWM outer border while retaining Windows 11 composited
  corners and the Windows 10 region fallback. A custom exterior shadow remains
  intentionally omitted.
- Destroys the menu HWND and owned bitmap on close so Xbox FSE/DWM cannot revive
  stale title, row, or footer surfaces after a fullscreen transition.
- Removes the 512-entry display-mode ceiling, allowing enumeration to reach all
  driver-reported resolutions and refresh rates, including 4K modes that could
  previously appear after hundreds of low-resolution combinations.
- Corrects high-DPI recovery-heading sizing and expands validation/checklist
  coverage for rendering, lifecycle, bitmap ownership, accent persistence, and
  complete display enumeration.

## Verification status

The shared visual design and complete 4K mode enumeration were refined from
maintainer hardware feedback in the parallel SteamShell tree. XFE parity was
validated structurally and by static replay, but the final 0.1.17 source still
requires its Xbox FSE checklist pass—especially rapid navigation, close/game-exit
ghosting, Windows 10 corner fallback, and a driver table exceeding 512 entries.

Verified in the available development environment:

- Static regex replay: 127 assertions, 86 evaluated passes, 0 evaluated failures.
- Deterministic controller-profile simulation passed.
- `git diff --check` passed before snapshot creation.
- Source/sample settings schema is version 4 and the release version is 0.1.17.

Full PowerShell validation, AutoHotkey syntax validation, compilation, and the
Windows/Xbox FSE acceptance checklist must be run on Windows.

## Known limits

- Xbox FSE can withhold XInput/GameInput; RawInput remains the required working
  backend there and learned profiles remain controller-specific.
- The Quick Menu cannot prevent a game using another controller API from also
  receiving controller input.
- Display modes are read from the primary display and modes below 640×480,
  24 Hz, or 24-bit color remain intentionally filtered.
- A custom Quick Menu exterior shadow is intentionally not implemented.
- Compiled executables and user INI/log files are not part of the locked source
  snapshot.

## Checksums (SHA-256)

The checksum table below covers every file in this directory except
`RELEASE.md`, whose contents include the table itself.

| File | SHA-256 |
|---|---|
| `Build-SteamShell-XFE.cmd` | `060b53005ae0a0ccfa47cd262f4fa6aa45e9b66e0b62fba6f26b5a90be4b4f11` |
| `Build-SteamShell-XFE.ps1` | `7a90e6c6e34051d84e361527586d566fbede4f85cafd5339d404d89d9c4c0eb6` |
| `README.md` | `81eea8f4ec1cc58e3c76d0c35ce5e8982c9db7dd7b818d50908a9a0cd4b020b6` |
| `SteamShell-XFE.ahk` | `8afa08d0b9e044025959415e1b2318516e4e5aaa9c4ac6f746a8faee1bfdf9de` |
| `SteamShell-XFE_SAMPLE.ini` | `333fe55009ced22c212a23ccb2d9b2186bd3e8a0808019a21f76dbb3345fa234` |
| `Test-ControllerProfiles.py` | `1b98b4d2cb21a479a545dd36c91020f85334e06d3b2ef0a152080d9ab0c96be0` |
| `Validate-SteamShell-XFE.ps1` | `b858b7aa25d0e2f578ff16d746547e9f4c59592c98260d44424318ddba78355c` |
| `WINDOWS_TEST_CHECKLIST.md` | `dc6e20774a0f9ea645d4714ed0b62f23d4983f42f27b95c7ddb7c3f500351743` |
| `assets/SteamShell-XFE-icon.png` | `c7a85f0e7bc20ec733fc5d9737167cde7965d4def90946353005926b85357005` |
| `assets/SteamShell-XFE.ico` | `2fe6f14f89e2a051e753a767b2da68e16f5666baef11d0252c954c5c69c93002` |
