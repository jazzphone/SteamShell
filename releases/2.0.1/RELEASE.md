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
- **Fixed: the Learn Controller wizard left a button stuck down.** The wizard
  identifies the pad from the first report where a bit changed, which for almost
  every controller is the button going *down* — and that report was copied as
  the resting state. The identifying button then read as permanently pressed for
  the rest of the wizard, was saved into the profile's neutral, and stayed
  pressed afterwards. The pre-press idle report is now the baseline, and nothing
  is measured until the button comes back up.
- **Fixed: the elevated helper only understood XInput.** Over a High-integrity
  window — Task Manager is the everyday case — the pointer is driven by the
  elevated helper, and it read XInput and nothing else. A pad that answers only
  RawInput, which is what that backend and the learning wizard exist for, lost
  the pointer the moment such a window came forward while working everywhere
  else. Identity resolution, profile lookup and report decoding now live in
  `SteamShell-Common.ahk`, which all three programs compile, so the helper runs
  the same decoder against the same profile file as the shell. XInput remains
  the fallback and now finds a pad on any slot rather than only the configured
  one.
- **Fixed: the RTSS limiter came back off after a reboot.** The startup restore
  verifies its write by re-reading RTSS's flag word immediately; RTSS applies
  its own saved runtime state slightly later while it finishes starting, and
  overwrites the flag *after* that check. The log said the cap was restored
  while the machine ran uncapped. The restore now re-checks for 30 seconds and
  re-applies if it reverts — bounded by a deadline, a retry cap, a match on the
  FPS number, and never for a remembered selection of "off".
- **Fixed: the Quick Menu could report the frame limiter OFF when it was on.**
  RTSS answers `GetFlags` as soon as it is running but can fail a profile read
  for a moment longer during startup, and a failed read was reported as a cap of
  zero — which the row renders as OFF. An unreadable cap now reads
  *Unavailable*, is never cached, and is never written into a game profile by
  **Save Limit to Profile**.
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
maintainer, on the tree locked here. `current\` was published as one directory transaction after every
check passed, and the executable in this directory is byte-identical to the one
the harness published (SHA-256 below).

Structural facts about this exact source, from `SteamShell\Replay-Validation.py`,
which replays both validators' assertions without Windows:

- 291 functions defined once in `SteamShell-Shared.ahk` (both trees) and 139 in
  `SteamShell-Common.ahk` (all three programs); no tree redefines any of them.
- 58 functions are defined in both trees. 13 are flagged by the fingerprint gate
  and 37 are recorded in `DIVERGENT_FUNCTIONS.txt` with a stated reason.
- 1,088 product assertions replayed from the two validators, all passing. A
  further 65 are written against a property subject and are only checked on
  Windows.
- Function totals: SteamShell 527, SteamShell-XFE 229, SteamShell-Helper 46.

Hardware-confirmed by the maintainer, each after its own build:

- Current Application opens its destination page (the Quick Menu navigation fix).
- The Learn Controller wizard no longer leaves the identifying button held.
- The controller drives the pointer over an elevated window with the RawInput
  backend.
- The RTSS frame limiter survives a reboot.

**Not claimed:** that every scenario in either Windows checklist was rerun
immediately before locking; `SteamShell\WINDOWS_TEST_CHECKLIST.md` describes what
to exercise. Within the fixes above, what was observed is the user-visible
outcome rather than every branch behind it — the *(already added)* state on a
second visit, the Store-app refusal, the length-keyed profile fallback in the
helper, and the limiter hold's retry and deadline bounds rest on validator
assertions and the structural replay.

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
- **The RTSS limiter hold gives up after 30 seconds and three attempts.** If
  something disables the limiter later than that, or keeps disabling it, the
  hold stops rather than fighting — a program that argues with the user over a
  setting is worse than the fault it is fixing. Each attempt is logged.

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
| `SteamShell/CHANGELOG.md` | `5938d1cca9f963b891fb865bbf070a3280112f1169bf7d0c346ea023ec6e11ce` |
| `SteamShell/COMMON_FUNCTIONS.txt` | `aedb586deeeadd3a42416fccbfe4e5acff9e8d45f24db64f3c298fbd2c8401e4` |
| `SteamShell/CROSS_NAME_DUPLICATES.txt` | `aa82ec6549413f7d48bbd20b9a71ed23ccf38d12821f88fe96f234a49d00bca8` |
| `SteamShell/DIVERGENT_FUNCTIONS.txt` | `e77c5284533b8ab8c19f2403064eb2b148c9f4751ad4433defc3c86de306c484` |
| `SteamShell/INI_READER_MIGRATION.md` | `3e409f547efafc1fc103eb2705b37f59e044d148d862d29b6460b0d0d145b0bd` |
| `SteamShell/QUICKMENU_ROWS.txt` | `c5718b526520f1adca565758b16f05c9506a56a4c33fd029278f086b00bd5786` |
| `SteamShell/README-XFE.md` | `5bc592af5f3ed3602e6df28fec4b504de80b49312cd64e7573e7a6ec3bb3d89f` |
| `SteamShell/README.md` | `69f2061c55d71c5f489f495ee247adac317cd2c4f22db534711b38f22a40364f` |
| `SteamShell/Replay-Validation.py` | `0f665748bd477eceb7eeb54cd584e19c2f9145c27e4e879d9c79984f2e65b14e` |
| `SteamShell/SHARED_FUNCTIONS.txt` | `2554ce06c4e86a76f9f58ab8337ce06cf75a4a1508115282b3a9bf5776f06e96` |
| `SteamShell/SteamShell-Common.ahk` | `469002de721978cce539903da4c1de29911b3712e07c32aa024f4c099094a197` |
| `SteamShell/SteamShell-Helper.ahk` | `0b7a5c14f6638a266273364c73d82b703438c8cd85237cad8f8b66a99bf8f874` |
| `SteamShell/SteamShell-Shared.ahk` | `8b7d4223f7c17487dcbe199a6b55611217052ab390115e07577cb0608cd4c0e1` |
| `SteamShell/SteamShell-XFE.ahk` | `6225e49e6ee53d98f614b2198c93e1fa2814598dea267d3b1434a564cbbc572a` |
| `SteamShell/SteamShell-XFE_SAMPLE.ini` | `2a4f3fa688a455eb07e42e1b69e2eb6e0568fe810de627fb0ae8dd42cfb74de5` |
| `SteamShell/SteamShell.ahk` | `272a10a597d0a27765a08edcbf3330171b300f478fcf9fb503e8e9bc48bd6a4a` |
| `SteamShell/SteamShell.reg` | `4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a` |
| `SteamShell/SteamShellSettings_SAMPLE.ini` | `2116101fe6d3e20c6d29fe4db0ba9d5c93c1836f1cd12d5b1ad7cca11a87ce58` |
| `SteamShell/Test-ControllerProfiles.py` | `fc960e4f815351e2346de98a73c7bfef25f281b4f53d066012487834292e9f02` |
| `SteamShell/Validate-Common.ps1` | `a9404f4818f87a70e3701b73ba173b789d7f389d6a2c248d292b2535dd9f58a4` |
| `SteamShell/Validate-SteamShell-XFE.ps1` | `9c3a53a9bf9433e65489d33b7c2eba564278d3ee32f4e5b9eb9acd426b0f914a` |
| `SteamShell/Validate-SteamShell.ps1` | `1071afd727e429f1ed4154c13602fdc100b6ba7816b66cf88cec8ebad662b807` |
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
| `current/SteamShell.exe` | `c44b50c88a567466dd438b91ebcd085850688d6abd7c0dcbb60c70372dbc5195` |
