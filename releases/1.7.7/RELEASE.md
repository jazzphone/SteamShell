# SteamShell 1.7.7

Released: 2026-08-01

This directory is the locked source release for SteamShell 1.7.7. Do not edit
this snapshot when later development resumes; make changes in `SteamShell/`
under a later version.

Build `SteamShell.ahk` on Windows by double-clicking `Build-SteamShell.cmd`. The
underlying PowerShell script requires AutoHotkey v2.0.19 or newer with a 64-bit
base, runs `Validate-SteamShell.ps1` and AutoHotkey syntax validation, and then
compiles `dist\SteamShell.exe` with the included icon.

No compiled EXE is stored in this snapshot.

**Settings schema moves 14 → 16.** Schema 15 migrates the Quick Menu layout for
Open Keyboard and persistent Mouse Mode while retiring the old Controller
Layout row. Schema 16 copies the existing RTSS `CustomFrameCap` into the new
`PresetFrameCap` when Preset is absent, preserving the user's established cap
while Custom gains its own retained value.

## Release scope

- Hardens builds and validation: real GUI-process exit codes, fresh-output
  checks, broken-source and stale-output negative tests, transactional
  publication to root `current\`, bounded log rotation, centralized RTSS
  discovery, shared-function parity enforcement, and safer shell restoration.
- Refreshes Quick Settings with Open Keyboard, persistent Mouse Mode, hold-Y
  Controller Mappings, Windows Settings, streamlined Settings/System pages, and
  consistently title-cased labels.
- Makes every SteamShell settings/editor surface temporarily controller-mouse
  capable, including Controller Mapping opened directly from Quick Settings,
  without changing the persisted Mouse Mode toggle.
- Splits RTSS frame-cap behavior into a configured **Preset** and a separately
  retained **Custom** value. Both survive cycling and restart; a Preset that
  duplicates a standard cap is deduplicated so the normal cycle cannot skip.
- Applies the validated living-room defaults: Purple Quick Menu, 3000
  controller deadzone, Explorer automatic mouse, faster focus/exit timing,
  guarded launcher cleanup, enabled startup scheduling with empty application
  slots, and RTSS Separate controls with a 158 FPS Preset.
- Includes the cross-tree audit notes and the scoped typed-INI-reader migration
  proposal without undertaking that separate migration in this release.

## Verification status

The maintainer reported the resulting implementation working on the Windows
target and requested this lock. The root Windows harness was exercised with
Windows PowerShell 5.1.26100 and AutoHotkey 2.0.26; both AutoHotkey sources
parsed cleanly. Two final static-validator mismatches found by that run—the old
Steam Blue accent expectation and an XFE case-insensitive variable/function
name collision—were corrected before this snapshot.

Verified again while creating the lock:

- Source version is 1.7.7 and embedded/sample settings schema is 16.
- Source files in this snapshot are byte-identical to the working tree at lock
  time.
- Deterministic controller-profile simulation passed in the companion tree.
- The 49 declared shared functions remained byte-identical across both active
  trees.
- Function-shadow, RTSS Preset/Custom wiring, migration ordering, documentation
  coupling, and duplicate-definition checks passed.
- `git diff --check` passed.
- Every checksum below was regenerated from the completed snapshot and then
  verified.

This records a validated working checkpoint, not a claim that every manual
scenario in `WINDOWS_TEST_CHECKLIST.md` was rerun immediately before the lock.

## Known limits

- SteamShell intentionally starts elevated so controller mouse and actions can
  reach elevated Windows surfaces such as Task Manager; it therefore remains a
  high-trust Windows shell application.
- SteamShell cannot make ordinary XInput/GameInput delivery exclusive while the
  Quick Menu is open; some games may also receive the same controller input.
- Display and RTSS operations depend on driver/API support and retain the
  guarded fallbacks documented in the README and Windows checklist.
- Compiled executables, runtime INIs/logs, `.DS_Store`, and machine-specific
  state are not part of this locked source snapshot.

## Checksums (SHA-256)

The checksum table covers every file in this directory except `RELEASE.md`,
whose contents include the table itself.

| File | SHA-256 |
|---|---|
| `Build-SteamShell.cmd` | `30a085ed1548c8cc3462dd3d31f0b5d4a02ca1594028d228a11ed68ad548b05a` |
| `Build-SteamShell.ps1` | `775d7d906a9a4f92df88b57a9c6c1efffb7b6c11e6509a0d554930bc94cdd2d2` |
| `CHANGELOG.md` | `4ee11a1e94a5ec3efe84e72330e783098d8e6eea60684996d1bdca15e3e3cee7` |
| `INI_READER_MIGRATION.md` | `6a534d6b9fa35f7eb08ae0ac86d35b889fbe2c38989ca683464ca446ae224155` |
| `README.md` | `d23505a23d499df9ca38762d2474966660c56a965c49ae44010d70a8cc3b3f30` |
| `SteamShell.ahk` | `a1e470a48b5af4e067fdfdeba610ca43654b6fa723498056ee51d8f6d91800a7` |
| `SteamShell.reg` | `4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a` |
| `SteamShellSettings_SAMPLE.ini` | `6ce5318cc8287ca2d0d3bc49c05d872f718e30d89e5e17dadc084832a6f999ce` |
| `Validate-SteamShell.ps1` | `3105effddaf7e97e5773a58300b33584f8614662bf786a47115fe8d8980234a0` |
| `WINDOWS_TEST_CHECKLIST.md` | `cc97e2f5028ba6ebd1b21708375194c9be5778544f0caa884625b8cca3b5264d` |
| `XFE_PARITY_NOTES.md` | `3606a4c4459ce09d1f174c10eb67d07c049b76cfdbc37693e07a20ffa2486013` |
| `assets/SteamShell-icon.png` | `bf8d9908917c4063e6bdb515a30e2519fa363d69b6ed08fb03dc6e2f1abc2170` |
| `assets/SteamShell.ico` | `260dba5dc8d228ede26089e63749ca53c0b2b3d369ff2b3cedd1232d4121a92b` |
| `extras/bigpicture_startup.webm` | `a12363458ace3a72a975c0ba650890960c439f39f96712805e896bf7c86f363b` |
| `extras/black.png` | `0ab0900f03e8f2a825691374d5e063a177085dc6a572ef15e7750b4a2bd69b41` |
| `images/control-panel.png` | `0199cfbf13f982031c536be47e312205b06960d5c206f6363d942830da25f42e` |
