# SteamShell XFE 0.1.21

Released: 2026-08-01

This directory is the locked source release for SteamShell XFE 0.1.21. Do not
edit this snapshot when later development resumes; make changes in
`SteamShell-XFE/` under a later version.

Build `SteamShell-XFE.ahk` on Windows by double-clicking
`Build-SteamShell-XFE.cmd`. The underlying PowerShell script requires
AutoHotkey v2.0.19 or newer with a 64-bit base, runs the static validator and
AutoHotkey syntax validation, and then compiles `dist\SteamShell-XFE.exe` with
the included icon.

No compiled EXE is stored in this snapshot.

**Settings schema moves 4 → 8.** Schema 5 adds audit/log hardening settings;
schema 6 backs up and retires the late startup-curtain section; schema 7 adds
the refreshed Quick Settings and persistent Mouse Mode defaults; schema 8
copies an existing `CustomFrameCap` into the new `PresetFrameCap` when needed
and retains Custom independently.

## Release scope

- Applies the cross-tree audit hardening: bounded log rotation,
  diagnostic-only controller-edge logging, restored left-stick menu navigation,
  centralized RTSS discovery, shared clamp helpers, negative validator tests,
  shared-function parity, and transactional root validation publication.
- Removes XFE's startup curtain/video because AnyFSE launches the companion only
  after Steam is already visible. Existing startup-presentation settings are
  backed up and retired rather than left as a misleading late overlay.
- Hardens Lite Assist and launcher cleanup: retains valid Steam tool windows,
  protects Explorer foreground surfaces, uses effective CPU game detection for
  minimized/non-fullscreen games, and revalidates process identity before a
  delayed hard kill.
- Refreshes Quick Settings with Open Keyboard, persistent Mouse Mode, hold-Y
  Controller Mappings, Windows Settings, streamlined Settings/System pages, and
  consistent title casing.
- Gives every companion settings/editor surface temporary controller pointer,
  click, scroll, and basic navigation behavior, including Controller Mappings
  and native dialogs, without changing the persisted Mouse Mode toggle.
- Splits RTSS frame-cap behavior into a configured **Preset** and separately
  retained **Custom** value, with migration of the former value and safe
  handling when Preset duplicates a standard cap.
- Mirrors the applicable validated living-room defaults while keeping startup
  application slots empty and retaining XFE's standard-user privilege model.

## Verification status

The maintainer reported the resulting implementation working on the Windows
target and requested this lock. The root Windows harness was exercised with
Windows PowerShell 5.1.26100 and AutoHotkey 2.0.26; both AutoHotkey sources
parsed cleanly. Two final static-validator mismatches found by that run—the old
standalone accent expectation and this tree's case-insensitive
`settingsPrimaryActive`/`SettingsPrimaryActive()` collision—were corrected
before this snapshot.

Verified again while creating the lock:

- Source version is 0.1.21 and source/sample settings schema is 8.
- Source files in this snapshot are byte-identical to the working tree at lock
  time.
- Deterministic controller-profile simulation passed.
- The 49 declared shared functions remained byte-identical across both active
  trees.
- Function-shadow, RTSS Preset/Custom wiring, migration ordering, documentation
  coupling, and duplicate-definition checks passed.
- `git diff --check` passed.
- Every checksum below was regenerated from the completed snapshot and then
  verified.

This records a validated working checkpoint, not a claim that every manual Xbox
FSE scenario in `WINDOWS_TEST_CHECKLIST.md` was rerun immediately before the
lock.

## Known limits

- Xbox FSE can withhold XInput/GameInput; RawInput and the learned controller
  profiles remain the required working path there.
- The companion deliberately runs at standard-user privilege. It cannot control
  elevated applications, avoiding the measured double-input behavior caused by
  an elevated companion window over Steam/Xbox FSE.
- Startup curtain/video is intentionally absent in XFE; AnyFSE owns launch
  order, and a companion overlay cannot cover Steam before Steam appears.
- The Quick Menu cannot prevent a game using another controller API from also
  receiving controller input.
- Compiled executables, runtime INIs/logs/controller profiles, diagnostic ZIPs,
  `.DS_Store`, and machine-specific state are not part of this locked source
  snapshot.

## Checksums (SHA-256)

The checksum table covers every file in this directory except `RELEASE.md`,
whose contents include the table itself.

| File | SHA-256 |
|---|---|
| `Build-SteamShell-XFE.cmd` | `060b53005ae0a0ccfa47cd262f4fa6aa45e9b66e0b62fba6f26b5a90be4b4f11` |
| `Build-SteamShell-XFE.ps1` | `fbe9c10bac5817c7e77eb1bdc8efef80e2b34cddf4da9b52d9fcd8aef917f1dc` |
| `README.md` | `0f35002f5d3e38204b2b56d4e988cc45417ed5735d3b834cb7896ca65335c7c6` |
| `SteamShell-XFE.ahk` | `cc2e9eaafe0148f0c4f942a079308225a2b9397c6bae283082551b27ca4a2b28` |
| `SteamShell-XFE_SAMPLE.ini` | `7a19775d26a8f50c2df5c6b59d6aa87a1e4b35b378c75dba917af003f2107029` |
| `Test-ControllerProfiles.py` | `b8999dd3fc25cd8328c2da448a100ce7f02f5c0265b0f4e4a6fc45553da88add` |
| `Validate-SteamShell-XFE.ps1` | `f427d4032e6d3b8db201eaead8c93ad203bc80b5a8b3a70f92f9634debb124fe` |
| `WINDOWS_TEST_CHECKLIST.md` | `1b47eca2ea6950e6ee0329a9731367a50996ac202bf0c2e0c382a135b2a6acbf` |
| `assets/SteamShell-XFE-icon.png` | `c7a85f0e7bc20ec733fc5d9737167cde7965d4def90946353005926b85357005` |
| `assets/SteamShell-XFE.ico` | `2fe6f14f89e2a051e753a767b2da68e16f5666baef11d0252c954c5c69c93002` |
