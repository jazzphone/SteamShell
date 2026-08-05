# SteamShell 1.9.9 coordinated release

Released: 2026-08-01

This directory is the immutable source lock for standalone SteamShell 1.9.9 and
SteamShell-XFE 1.9.9. It is the large architecture checkpoint immediately before
2.0 development. Future feature work belongs in the active `SteamShell\` and
`SteamShell-XFE\` trees under a later version.

No compiled executable is stored in this snapshot. The complete Windows build
and validation inputs are included and use only paths inside this directory.
See `README.md` for the double-click build procedure.

## Release scope

- Moves both platforms to a coordinated 1.9.9 product version and embeds
  file-version metadata in both main executables.
- Replaces standalone's monolithic elevated runtime with a normal-integrity main
  shell/UI and a narrowly scoped, embedded elevated helper for controller input
  and window geometry on High/System-integrity surfaces.
- Preserves standard-user launch ownership for Steam, Explorer, RTSS, startup
  applications, MPV, and ordinary Windows utilities so foreground Steam does not
  consume controller input behind SteamShell UI.
- Adds the first-run Setup Assistant, Standard/custom/portable install and
  upgrade paths, explicit administrator maintenance handoff, protected helper
  deployment, safe same-user process takeover, rollback-aware state, optional
  shell registration, integrated Auto-Login, and restart completion choices.
- Hardens recovery, Explorer readiness, desktop restoration, DPI-aware setup
  layout, dialog ownership, window-engine/helper coordination, and install-source
  cleanup boundaries.
- Retains the coordinated Quick Settings, automatic controller mouse, mapping,
  RTSS Preset/Custom, window-engine, Lite Assist, launcher cleanup, and XFE
  RawInput/controller-profile behavior documented in the platform READMEs and
  checklists.
- Ships a single top-level validation launcher that syntax-checks all three AHK
  sources, runs both static validators and shared parity checks, compiles both
  applications, rejects broken/stale/version-mismatched output, and publishes
  both EXEs transactionally to `current\` only after all checks pass.

## Version and schema lock

| Component | Product version | Compiled file version | Settings schema |
|---|---:|---:|---:|
| SteamShell | 1.9.9 | 1.9.9.0 | 18 |
| SteamShell elevated helper | 1.9.9 | 1.9.9.1 | Uses standalone settings |
| SteamShell-XFE | 1.9.9 | 1.9.9.0 | 8 |

The helper's fourth version field intentionally differs so every 1.9.9 setup or
upgrade replaces an older embedded helper.

## Self-contained build contract

The following launchers and their complete dependencies are inside this release:

- `Run-SteamShellValidation.cmd` / `.ps1` — validate and compile both platforms.
- `SteamShell\Build-SteamShell.cmd` / `.ps1` — validate and compile standalone,
  including the helper.
- `SteamShell-XFE\Build-SteamShell-XFE.cmd` / `.ps1` — validate and compile XFE.
- Both local static validators, `Validate-SharedParity.ps1`,
  `SHARED_FUNCTIONS.txt`, the XFE controller simulation, icons, and all AHK
  sources required by those scripts.

All scripts resolve their inputs relative to their own location. Copying the
complete `1.9.9` directory elsewhere does not require the repository working
trees or any earlier release directory.

## Verification status

The maintainer has hardware-tested the implementation during the 1.7.8
development line that became 1.9.9, including normal-integrity Steam launch,
controller foreground behavior, helper-driven Task Manager geometry/input,
recovery retry, Setup Assistant, and upgrade behavior.

Verified while creating this source lock:

- Active and release sources declare the exact product/helper versions above.
- Standalone and XFE build scripts reject unexpected compiled file versions.
- The release bundle contains every path referenced by its build and validation
  launchers.
- Release source files are byte-identical to the active trees at lock time.
- Deterministic XFE controller-profile simulation passes.
- Static AHK structure, required-function, version-coupling, shared-parity, and
  whitespace checks pass in the available development environment.
- `git diff --check` passes.
- Every checksum below was generated from the completed snapshot and verified.

The final AutoHotkey syntax and Ahk2Exe compilation pass still requires Windows
with AutoHotkey installed. Run `Run-SteamShellValidation.cmd` from this directory
before publishing compiled binaries. This source lock does not claim every
manual scenario in both Windows checklists was rerun immediately before locking.

## Known limits

- SteamShell is a Windows shell replacement and must be tested on a recoverable
  Windows account/device before deployment.
- The elevated helper is intentionally limited to elevated foreground input and
  geometry; the visible shell/UI remains normal integrity.
- XFE depends on Xbox FSE/AnyFSE launch behavior and RawInput-capable controller
  reports. XInput-only controllers may remain unavailable inside Xbox FSE.
- The Quick Menu cannot make controller APIs exclusive; another foreground or
  background application can still consume input independently.
- Display, HDR, audio, RTSS, Game Bar, and touch-keyboard behavior depends on
  Windows, driver, and third-party component support.
- Generated executables, `build\`, `dist\`, `current\`, runtime INIs/logs,
  controller profiles, diagnostic archives, and machine-specific state are not
  part of this source snapshot.

## Checksums (SHA-256)

The checksum table covers every file in this directory except `RELEASE.md`,
whose contents include the table itself.

| File | SHA-256 |
|---|---|
| `README.md` | `2418f548aeffdd013f62d9ff6150f730c2cc9c8b622073294cf56179b5c8f1c4` |
| `Run-SteamShellValidation.cmd` | `c23db975b6da023ab3938fa85e394d6ea24e36f1d91437c03e7b97b2bdb32742` |
| `Run-SteamShellValidation.ps1` | `83be0a497fee701395381307bd938b11cea0bc5ec5b9485f44c0c1fc2676ebee` |
| `SHARED_FUNCTIONS.txt` | `758646d7ac794dee95420d3f49950557df477381fe7796773dc1673fa7bcca67` |
| `STEAMSHELL_PROJECT_OVERVIEW.md` | `0937cb7afd26fb960e994c26c96b97d8d5be22e255487906e9bddebfa507bcaf` |
| `SteamShell-XFE/Build-SteamShell-XFE.cmd` | `060b53005ae0a0ccfa47cd262f4fa6aa45e9b66e0b62fba6f26b5a90be4b4f11` |
| `SteamShell-XFE/Build-SteamShell-XFE.ps1` | `30d22064fde9af8039b098a98efa2b76426bdf7d456eb2dc4760335097225925` |
| `SteamShell-XFE/README.md` | `5b0cefdfcc09b96d5743768e3d9943974db88afbb3f36cc5580899ca3bd11497` |
| `SteamShell-XFE/SteamShell-XFE.ahk` | `a3cc3c5d2a5e08aeed688a291226a284baecb8ffb54782c99251fee92c97e080` |
| `SteamShell-XFE/SteamShell-XFE_SAMPLE.ini` | `7a19775d26a8f50c2df5c6b59d6aa87a1e4b35b378c75dba917af003f2107029` |
| `SteamShell-XFE/Test-ControllerProfiles.py` | `b8999dd3fc25cd8328c2da448a100ce7f02f5c0265b0f4e4a6fc45553da88add` |
| `SteamShell-XFE/Validate-SteamShell-XFE.ps1` | `f17afc742a09d8327cd0e030e06e27da861df36744da7f8573801928c84d339f` |
| `SteamShell-XFE/WINDOWS_TEST_CHECKLIST.md` | `794ee7fde3795ab01882830fb173af237ca875c370fa47698b6789c77f5674e4` |
| `SteamShell-XFE/assets/SteamShell-XFE-icon.png` | `c7a85f0e7bc20ec733fc5d9737167cde7965d4def90946353005926b85357005` |
| `SteamShell-XFE/assets/SteamShell-XFE.ico` | `2fe6f14f89e2a051e753a767b2da68e16f5666baef11d0252c954c5c69c93002` |
| `SteamShell/Build-SteamShell.cmd` | `30a085ed1548c8cc3462dd3d31f0b5d4a02ca1594028d228a11ed68ad548b05a` |
| `SteamShell/Build-SteamShell.ps1` | `a449c8a3dfb38a24fc54147354bb95c672ea7fc0d8857f8d0635f525ad3802ab` |
| `SteamShell/CHANGELOG.md` | `e837b991fd9f4884f496e5b6d33a65d96c3b3c9e65d1e09fd33bb1973016bbe5` |
| `SteamShell/INI_READER_MIGRATION.md` | `6a534d6b9fa35f7eb08ae0ac86d35b889fbe2c38989ca683464ca446ae224155` |
| `SteamShell/README.md` | `53af0927f16275ebee8db4502b4b08fceb8a66099ce4daf9db245718f1af26b2` |
| `SteamShell/SteamShell-Helper.ahk` | `547089a28afeef704746e7cdd04dc82d78a01960324bc0f2d74c3667f0c09045` |
| `SteamShell/SteamShell.ahk` | `d9f0303d4b0e8fba5e5531a874c03b1f6fb15beebdc8b9919eaf1a7d842ba45a` |
| `SteamShell/SteamShell.reg` | `4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a` |
| `SteamShell/SteamShellSettings_SAMPLE.ini` | `6335a7017567d5458622df6e4e77ec12961e0ac770e3e614195190198a314801` |
| `SteamShell/Validate-SteamShell.ps1` | `062fb4a25450fba5aa82886adae6c7f1d72d220ec2485fc41e90fca136704317` |
| `SteamShell/WINDOWS_TEST_CHECKLIST.md` | `a98abbc95bf93655ae64d363d29547a7c5b6c8bae2dcd4c085fc6e6f488ff045` |
| `SteamShell/XFE_PARITY_NOTES.md` | `b67585cc12996d16d7c38f90c16b1383604a8cae008874b85d39efc70463205a` |
| `SteamShell/assets/SteamShell-icon.png` | `bf8d9908917c4063e6bdb515a30e2519fa363d69b6ed08fb03dc6e2f1abc2170` |
| `SteamShell/assets/SteamShell.ico` | `260dba5dc8d228ede26089e63749ca53c0b2b3d369ff2b3cedd1232d4121a92b` |
| `SteamShell/extras/bigpicture_startup.webm` | `a12363458ace3a72a975c0ba650890960c439f39f96712805e896bf7c86f363b` |
| `SteamShell/extras/black.png` | `0ab0900f03e8f2a825691374d5e063a177085dc6a572ef15e7750b4a2bd69b41` |
| `SteamShell/images/control-panel.png` | `0199cfbf13f982031c536be47e312205b06960d5c206f6363d942830da25f42e` |
| `Validate-SharedParity.ps1` | `ee64e276b84305d512abdd75d2182ef3afd3ab0cb17b616ab2f2549cc2233f54` |
