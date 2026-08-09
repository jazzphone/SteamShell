# SteamShell 2.0.1 coordinated release

Released: 2026-08-09

This directory is the immutable source lock for SteamShell 2.0.1 and
SteamShell-XFE 2.0.1, and it contains the verified installer built from that
source, on the same terms as 2.0.0.

`current\SteamShell.exe` is the executable produced by the validation harness in
this directory on the date above, from these exact sources.

## Release scope

2.0.1 is a patch release on top of 2.0.0. It is the 2.0.0 follow-up queue,
worked in order, plus one feature that came out of reading the settings rather
than the code.

**The executable lists could only be filled by typing.** Every exclusion,
allowlist and protection setting in both products names executables, and all of
them assumed the user knew what a process was called and had a keyboard to type
it with. In a living room neither is reliably true, so the lists stayed empty and
the features that read them looked broken. Two answers, kept separate because
they answer different questions:

- **Recent…** offers the last five applications that were in the foreground,
  deduped by executable, with the last window title beside each name. In the
  shell it is a third button on every executable-list field in Settings, plus
  **Add Recent App…** in the AlwaysFocus Manager; in the companion it is **Add
  Recent Application…** under Controller & Cursor. The history is sampled on its
  own one-second timer rather than from either tree's foreground observer,
  because the shell's stops in desktop mode and the history would have had a hole
  in it in exactly the state a user goes looking for the setting. It is held in
  memory and never written to disk. The reason it is a history and not a live
  window list is the applications already **closed** — those are the ones whose
  executable name can no longer be looked up.
- **Quick Menu ▸ System ▸ Current Application** names what is in front right now,
  into four destinations in the shell and two in the companion, showing
  *(already added)* on a second visit. It works there and cannot work in
  Settings, because both trees snapshot the previous foreground window before the
  menu takes it and Settings has no equivalent moment.

**Store apps are refused by name, in both routes.** A packaged application's
visible window belongs to `ApplicationFrameHost.exe`, so adding it by name would
write one entry that silently matches Settings, Photos, Calculator and the Store
at once. The picker drops the frame host from its history; Current Application
says *"Store app — cannot be added by name"* rather than staying silent, because
there the user is pointing at the window.

Also in this release:

- **The shipped automatic-mouse allowlist is no longer one entry.** It is
  `explorer.exe|brave.exe|chrome.exe|msedge.exe|firefox.exe|notepad.exe|taskmgr.exe`,
  stated once in `DefaultAutoMouseExeList()` and held to the shell's embedded
  default INI text and both sample files by the build.
  `DesktopAutoMouseExcludeExeList` now ships **empty**; it shipped `brave.exe`,
  which is the opposite list, so automatic mouse was turned *off* for Brave on
  the desktop and never turned on in shell mode.
- **Fixed: Quick Menu pages that did not open.** Selecting Current Application in
  the shell appeared to do nothing. The page variable moved while the previous
  page's rows stayed on screen, because the four cases that navigate from the
  activation switch repainted instead of rebuilding — and a repaint redraws the
  rows the page was built with. Game Detection and both Back To System rows had
  the same defect. All navigation in both products now goes through one shared
  `QuickMenuGoToPage`; neither tree assigns the page any more, and the build
  fails if one starts again.
- **Deleting a learned controller profile** is reachable in the shell, which had
  no route to it at all: `Ctrl+Alt+Shift+D`, the notification-area menu, and
  Settings ▸ Controller & Cursor. Three routes because a profile that learned an
  axis wrongly reads as a stick held over, so the pointer runs off and the
  controller becomes the thing that cannot be used to reach the fix.
- **The shell's four controller Health Check rows** come from one shared builder,
  so both products word them identically. The XInput slot is reported for XInput
  only; it had been printed beside RawInput readings, where it was whatever
  XInput last left behind.
- **A on the companion's Quick Menu** steps Quick Menu Accent, Controller Mouse
  Speed, Cursor Hide Delay and Preset Frame Cap, which did nothing there before.
- **StartMenu bound to a controller button** goes through `SendChordSafe`,
  matching what the elevated helper always did.

`SteamShell\CHANGELOG.md` carries the full record, including the 2.0.0 follow-up
items landed earlier in the cycle.

## Version and schema lock

| Component | Product version | Compiled file version | Settings schema |
|---|---:|---:|---:|
| SteamShell | 2.0.1 | 2.0.1.0 | 23 |
| SteamShell elevated helper | 2.0.1 | 2.0.1.1 | Uses standalone settings |
| SteamShell-XFE | 2.0.1 | 2.0.1.0 | 18 |

The helper's fourth version field differs from the main executable's on purpose,
so every 2.0.1 setup or upgrade replaces an older embedded helper. It is not a
patch number.

Neither settings schema changed in this release. Both products upgrade from 2.0.0
in place with no migration.

The 2.0.0 lock recorded that its own bump initially failed on five literals
written a second time as escaped regex, and that a future bump would need the
canonical block edited and nothing else. That was true of the build's version
gates, which are derived from each source's `@Ahk2Exe-SetVersion` and did not
need touching. It was not true of everything: this bump still changed 22 literals
across the three sources, the build script's messages, both validators' escaped
copies and the harness. Each was replaced against an expected occurrence count
rather than by a blind search-and-replace, and the structural replay re-ran every
version assertion before the Windows build was started.

## Verification status

Full harness run on Windows, 2026-08-09 — **all checks passed**, reported by the
maintainer. `current\` was published as one directory transaction after every
check passed, and the executable in this directory is byte-identical to the one
the harness published (SHA-256 below).

Structural facts about this exact source, from `SteamShell\Replay-Validation.py`,
which replays both validators' assertions without Windows:

- 292 functions defined once in `SteamShell-Shared.ahk` (both trees) and 130 in
  `SteamShell-Common.ahk` (all three programs); no tree redefines any of them.
- 58 functions are defined in both trees. 13 are flagged by the fingerprint gate
  and 37 are recorded in `DIVERGENT_FUNCTIONS.txt` with a stated reason.
- 1,088 product assertions replayed from the two validators, all passing. A
  further 65 are written against a property subject and are only checked on
  Windows.
- Function totals: SteamShell 527, SteamShell-XFE 229, SteamShell-Helper 42.

**Not claimed:** that every scenario in either Windows checklist was rerun
immediately before locking. `SteamShell\WINDOWS_TEST_CHECKLIST.md` describes what
to exercise. The maintainer hardware-tested the Quick Menu navigation fix — the
defect that prompted this release — and confirmed Current Application opens its
destination page. The write itself, the *(already added)* state on a second
visit, and the Store-app refusal are covered by validator assertions rather than
by a reported hardware pass.

## Known limits

Unchanged from 2.0.0:

- SteamShell is a Windows shell replacement and must be tested on a recoverable
  Windows account or device before deployment.
- The elevated helper is intentionally limited to elevated foreground input and
  window geometry; the visible shell and UI remain normal integrity.
- XFE depends on Xbox FSE / AnyFSE launch behaviour and RawInput-capable
  controller reports. XInput-only controllers may remain unavailable inside
  Xbox FSE.
- The Quick Menu cannot make controller APIs exclusive; another foreground or
  background application can still consume input independently.
- Display, HDR, audio, RTSS, Game Bar and touch-keyboard behaviour depends on
  Windows, driver and third-party component support.
- `WindowEngineApplyGeometry` still centres windows against the primary monitor.
  The game *scorer* is per-monitor; window *placement* is not.
- Runtime INIs, logs, controller profiles, diagnostic archives, `build\`,
  `dist\` and machine-specific state are not part of this snapshot.

New in 2.0.1:

- **Windows Settings cannot be added to an executable list by name**, by either
  route, and neither can any other packaged Store application. Its visible window
  belongs to `ApplicationFrameHost.exe`; the name behind it is a host shared by
  every windowed Store app. The refusal is deliberate and stays until the hosted
  process behind the frame can be resolved properly.
- **The recent-application history does not survive a restart.** It is in memory
  by design, so the picker is empty on a fresh login until applications have been
  used.

## Checksums (SHA-256)

Covers every file in this directory except `RELEASE.md`, whose contents include
the table itself.

| File | SHA-256 |
|---|---|
| `README.md` | `d2ca3caf2b365e4be0a940bbaf895c7f635d901c7a9e7dc2c6768c2d3edfed02` |
| `Run-SteamShellValidation.cmd` | `c23db975b6da023ab3938fa85e394d6ea24e36f1d91437c03e7b97b2bdb32742` |
| `Run-SteamShellValidation.ps1` | `37e88cbf72ca96ef25cc0dcb8f49693cc61e138603960a4f7926bbca8bb78f59` |
| `STEAMSHELL_PROJECT_OVERVIEW.md` | `86914bd54357b6d3c653f0ce4c93c0a627362c82356f3ef4c5f6550d0f217ac2` |
| `SteamShell/Build-SteamShell.cmd` | `30a085ed1548c8cc3462dd3d31f0b5d4a02ca1594028d228a11ed68ad548b05a` |
| `SteamShell/Build-SteamShell.ps1` | `402fa86e13e75ae6d5989ac4cd801a690d73aa3b522a768c47f2157612a6cc37` |
| `SteamShell/CHANGELOG.md` | `7fad804d93105da7fb97681dec90427d790322249bbe52c56243a72a338291cd` |
| `SteamShell/COMMON_FUNCTIONS.txt` | `835ded654e5153397ed6092c8316db973b75248fd08f9ccc32387a4a8f7da922` |
| `SteamShell/CROSS_NAME_DUPLICATES.txt` | `aa82ec6549413f7d48bbd20b9a71ed23ccf38d12821f88fe96f234a49d00bca8` |
| `SteamShell/DIVERGENT_FUNCTIONS.txt` | `e77c5284533b8ab8c19f2403064eb2b148c9f4751ad4433defc3c86de306c484` |
| `SteamShell/INI_READER_MIGRATION.md` | `3e409f547efafc1fc103eb2705b37f59e044d148d862d29b6460b0d0d145b0bd` |
| `SteamShell/QUICKMENU_ROWS.txt` | `c5718b526520f1adca565758b16f05c9506a56a4c33fd029278f086b00bd5786` |
| `SteamShell/README-XFE.md` | `5bc592af5f3ed3602e6df28fec4b504de80b49312cd64e7573e7a6ec3bb3d89f` |
| `SteamShell/README.md` | `69f2061c55d71c5f489f495ee247adac317cd2c4f22db534711b38f22a40364f` |
| `SteamShell/Replay-Validation.py` | `0f665748bd477eceb7eeb54cd584e19c2f9145c27e4e879d9c79984f2e65b14e` |
| `SteamShell/SHARED_FUNCTIONS.txt` | `25fd8c5df4e83b33a1dee88c76d2ffbe6d153857628175b0099ddab60b0a3ba0` |
| `SteamShell/SteamShell-Common.ahk` | `28faa6b963779b88f83eca811b41b19ba20c9ce4c0126faa9b0431d19c50303e` |
| `SteamShell/SteamShell-Helper.ahk` | `405ed5eb87996e68e27933298c0158942f0c46d7e3fadc507005aa12c17cef92` |
| `SteamShell/SteamShell-Shared.ahk` | `d583a27ea2ef99f2f596a861727adddf6e188e3107d36bc0916beae289dfc358` |
| `SteamShell/SteamShell-XFE.ahk` | `622a9d2f8b701137610c4132100b2b8c3a9c3b950f168c140110f5d3266b987c` |
| `SteamShell/SteamShell-XFE_SAMPLE.ini` | `2a4f3fa688a455eb07e42e1b69e2eb6e0568fe810de627fb0ae8dd42cfb74de5` |
| `SteamShell/SteamShell.ahk` | `6ed9707599502fb68479ec14175226aa652fa48798792a7bf5a67c5e793f2218` |
| `SteamShell/SteamShell.reg` | `4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a` |
| `SteamShell/SteamShellSettings_SAMPLE.ini` | `2116101fe6d3e20c6d29fe4db0ba9d5c93c1836f1cd12d5b1ad7cca11a87ce58` |
| `SteamShell/Test-ControllerProfiles.py` | `4c8be166ae2836db9957984ed3b38e5dfa9b4f2186f38c79ddfa0cd64886e6ef` |
| `SteamShell/Validate-Common.ps1` | `9fd5ca52c732beb83232aa125a5304d2596e7530e503262ba0b4d297875ed288` |
| `SteamShell/Validate-SteamShell-XFE.ps1` | `b405f00f77e96bb6d49e5d73509707408b92749ee7c58c002a2c20cde383496e` |
| `SteamShell/Validate-SteamShell.ps1` | `35cb1c8fcedc61d002e2d618fef68d8425534dbf6aea8c811d018a693b5a4329` |
| `SteamShell/WINDOWS_TEST_CHECKLIST-XFE.md` | `e24a74b1c0b2ebf36d4038fdfe28034e74dd9ab92a1154c35baefd880ffb766b` |
| `SteamShell/WINDOWS_TEST_CHECKLIST.md` | `764452032a2a62738ba076e929ab08f0277341dec53befdaf1adf33dbf02c119` |
| `SteamShell/XFE_PARITY_NOTES.md` | `738115eea263245a0fbefdb9e17e9de5373ff66ea4198699fedde2c7c6595266` |
| `SteamShell/assets/SteamShell-XFE-icon.png` | `c7a85f0e7bc20ec733fc5d9737167cde7965d4def90946353005926b85357005` |
| `SteamShell/assets/SteamShell-XFE.ico` | `2fe6f14f89e2a051e753a767b2da68e16f5666baef11d0252c954c5c69c93002` |
| `SteamShell/assets/SteamShell-icon.png` | `bf8d9908917c4063e6bdb515a30e2519fa363d69b6ed08fb03dc6e2f1abc2170` |
| `SteamShell/assets/SteamShell.ico` | `260dba5dc8d228ede26089e63749ca53c0b2b3d369ff2b3cedd1232d4121a92b` |
| `SteamShell/extras/bigpicture_startup.webm` | `a12363458ace3a72a975c0ba650890960c439f39f96712805e896bf7c86f363b` |
| `SteamShell/extras/black.png` | `0ab0900f03e8f2a825691374d5e063a177085dc6a572ef15e7750b4a2bd69b41` |
| `SteamShell/images/control-panel.png` | `0199cfbf13f982031c536be47e312205b06960d5c206f6363d942830da25f42e` |
| `current/SteamShell.exe` | `a66c4d6631374dce002350ffa4abe2188067055e63713647e813fb177a787324` |

