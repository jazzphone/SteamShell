# SteamShell 1.7.4

Released: 2026-07-31

This directory is the locked source release for SteamShell 1.7.4. Do not edit
this snapshot when later development resumes; make changes in `SteamShell/`
under a later version.

Build `SteamShell.ahk` on Windows by double-clicking `Build-SteamShell.cmd`. The
underlying PowerShell script requires AutoHotkey v2.0.19 or newer with a 64-bit
base, runs `Validate-SteamShell.ps1` and AutoHotkey syntax validation, and then
compiles `dist\SteamShell.exe` with the included icon.

No compiled EXE is stored in this snapshot.

**Settings schema moves 12 → 14.** Existing values remain authoritative. The
migration adds Quick Menu accent selection/custom color, desktop-wide automatic
mouse mode, and its executable exclusion list only when those keys are missing.

## Release scope

### Quick Menu renderer and lifecycle

- Replaces 28 flat row controls with one opaque, physical-pixel-sized GDI+
  surface using ClearType text, rounded selected fill, accent outline/bar/glow,
  neutral `#242424` charcoal, and neutral-gray unselected text.
- Adds nine accent presets plus a custom `RRGGBB` value; selected fill is derived
  from the accent rather than retaining a blue tint.
- Uses atomic bitmap/page redraws while open to reduce navigation flicker, and
  releases every replaced bitmap.
- Suppresses the native/DWM outer border. A custom exterior shadow is omitted to
  keep the menu one reliable opaque window over fullscreen applications.
- Destroys the closed menu HWND and owned bitmap. Desktop/Steam transitions also
  flush DWM, preventing a scrambled, noninteractive hidden menu from returning
  after a game or presentation transition.

### Desktop return and automatic mouse

- Fixes the `MouseHidden` AutoHotkey v2 scope error in automatic mouse mode.
- Treats an `explorer.exe` allowlist entry as the Windows shell family, including
  Start, Shell Experience, and Search hosts.
- Adds desktop-wide automatic mouse mode, enabled only while Explorer owns the
  desktop, with an explicit game/application exclusion list and persistent tray
  toggle. SteamShell presentation retains the conservative allowlist behavior.
- Return to SteamShell now launches Steam Big Picture before re-arming shell
  presentation rather than entering an empty recovery state.

### Display and recovery fixes

- Removes the 512-entry `EnumDisplaySettings` ceiling that could truncate a
  modern GPU/4K TV mode table at `1280×1024`. Enumeration now continues until
  Windows reports the end and logs reported/retained counts; resolution and
  refresh rate use the same complete table.
- Recovery explanations auto-size, and their large headings are created with
  the correct font metrics so text is not clipped at high DPI.

## Verification status

Maintainer hardware feedback during development confirmed the redesigned visual
direction, darker neutral background, automatic mouse operation, the Start-menu
shell-host coverage, desktop/menu recovery iterations, and the corrected 4K
resolution enumeration.

The final destroy-on-close menu lifecycle, desktop-wide automatic mouse behavior
across a broad application set, automatic Return to SteamShell launch path, and
both long recovery-error layouts remain explicit Windows checklist items. This
lock records a requested working checkpoint; it does not imply every item in
`WINDOWS_TEST_CHECKLIST.md` was rerun after the final source change.

Verified in the available development environment:

- Static regex replay: 133 assertions, 94 evaluated passes, no real evaluated
  failures. The reported Settings-panel failure is a known limitation of the
  local Python replay shim, which cannot evaluate the PowerShell category loop.
- `git diff --check` passed before snapshot creation.
- Source/sample settings schema is version 14 and the release version is 1.7.4.

Full PowerShell validation, AutoHotkey syntax validation, compilation, and the
Windows acceptance checklist must be run on Windows.

## Known limits

- SteamShell cannot make ordinary XInput/GameInput controller delivery exclusive
  while the Quick Menu is open; some games can still receive the same input.
- Display modes are read from the primary display and modes below 640×480,
  24 Hz, or 24-bit color remain intentionally filtered.
- Desktop-wide automatic mouse should exclude games or applications that need
  raw controller input.
- A custom Quick Menu exterior shadow is intentionally not implemented.
- Compiled executables and user INI/log files are not part of the locked source
  snapshot.

## Checksums (SHA-256)

The checksum table below covers every file in this directory except
`RELEASE.md`, whose contents include the table itself.

| File | SHA-256 |
|---|---|
| `Build-SteamShell.cmd` | `30a085ed1548c8cc3462dd3d31f0b5d4a02ca1594028d228a11ed68ad548b05a` |
| `Build-SteamShell.ps1` | `baa9319ccedbf8f42b5b5ff0713ee2746bcd489d36acef3c41912baba0672497` |
| `CHANGELOG.md` | `1daa2df18ab2d9fb5c8d803813dc131a87c6edeacea3c56f39ba58e385d5f882` |
| `README.md` | `349ef4668177bca4febbcb5ef5986848174232d03646cd8cd5bdfc27a06013a4` |
| `SteamShell.ahk` | `4ab43499cb6f08ec6413f2ba9b1a3ef844d5fa13e393df9bfb7f5475e895f698` |
| `SteamShell.reg` | `4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a` |
| `SteamShellSettings_SAMPLE.ini` | `321b08095808dcf20e69d0e265f203abd9604b740fa3fdfa988be4484f7f1723` |
| `Validate-SteamShell.ps1` | `fe58d5701b5c29ae980802402209ac8fe395d25e6dfff2eb11dd447f060c12f2` |
| `WINDOWS_TEST_CHECKLIST.md` | `e64fdc6c9babd24079550750ef6e573a137009207184f2b5693793a94c9dda49` |
| `XFE_PARITY_NOTES.md` | `33d28e811bc066e243389ae2e502aee3cdfc160a8e32279d5c2c6ccb0beff225` |
| `assets/SteamShell-icon.png` | `bf8d9908917c4063e6bdb515a30e2519fa363d69b6ed08fb03dc6e2f1abc2170` |
| `assets/SteamShell.ico` | `260dba5dc8d228ede26089e63749ca53c0b2b3d369ff2b3cedd1232d4121a92b` |
| `extras/bigpicture_startup.webm` | `a12363458ace3a72a975c0ba650890960c439f39f96712805e896bf7c86f363b` |
| `extras/black.png` | `0ab0900f03e8f2a825691374d5e063a177085dc6a572ef15e7750b4a2bd69b41` |
| `images/control-panel.png` | `0199cfbf13f982031c536be47e312205b06960d5c206f6363d942830da25f42e` |
