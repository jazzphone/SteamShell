# SteamShell 2.0.2 coordinated release

Released: 2026-08-10

This directory is the immutable source lock for SteamShell 2.0.2 and
SteamShell-XFE 2.0.2, and it contains the verified installer built from that
source, on the same terms as 2.0.1.

`current\SteamShell.exe` is the executable produced by the validation harness in
this directory on the date above, from these exact sources.

## Release scope

2.0.2 is a patch release on top of 2.0.1: a convergence release. 2.0.1 left the
two products sharing their logic but not their surfaces. This one finishes the
Settings window, and most of what a user notices follows from that. Fifty-one
commits, and the recurring finding is the one 2.0.1 began recording — a
difference between the two trees is usually nobody's decision, and the reason
written beside it has usually gone stale.

**The companion's Settings window is standalone's**, not merely similar to it.
One window frame, one scrolling pass, one ordered list of pages, one set of
layout builders, and one placement routine shared by every window Settings can
open. Startup Programs was a list box and two buttons and is now standalone's
editor, with the selected command line, Browse, Apply, Remove, Test Launch and
Move Up/Down. Launcher Cleanup carried a note sending the user to Notepad for
the two lists that decide everything the page does; both are on the page.
Advanced & Logging drew its thirteen buttons above the settings the page is
named for. Every executable list in both products is one editor.

**The companion gained what that surface reaches:** the Live Log viewer, the
log-rotation settings whose rows it was already drawing, the controller test,
and the controller mapping editor on standalone's rows. It contributed Restore
Defaults back, which standalone never had.

**A controller now works over elevated windows in the companion**, which it did
not: the helper ran with input disabled, so a pad was dead over Task Manager and
every other High-integrity window. Both recorded reasons had stopped being true.
**The companion's elevated frame-cap writes default on**, because RTSS installs
under Program Files and `RTSSHooks64.dll` loads into the calling process, so an
unelevated companion silently could not set the FPS value.

Four defects fixed here were reachable in normal use:

- **The companion's Settings window would not open.** Reaching Advanced &
  Logging threw `Invalid callback function` and the window never drew. A seam
  written to be *called* had been wired directly to a button's Click handler.
- **Switching applications in Xbox Mode.** The Xbox FSE task switcher is an
  `explorer.exe` window that holds the foreground while open, so that entry on
  the companion's automatic-mouse list turned the stick into a pointer over the
  switcher itself. The companion no longer accepts it anywhere. Standalone keeps
  it, because it replaces Explorer as the shell.
- **A startup program ran at every boot and appeared nowhere.** The shared
  reader took forty slots while the shell's editor, Health Check, category reset
  and shipped INI all said twenty, so a hand-written `Program21` launched at
  sign-in while being invisible and unremovable. There is one slot count now.
- **LT and RT stopped changing category in the shell's Full Settings**, after a
  rename collided with the locals holding the current sample and made the edge
  test a self-comparison.

**Settings saves are one transaction in both products.** The companion wrote
each key straight into the live file and stopped at the first failure, which
does not undo the keys already written; standalone hand-rolled a second staging
loop of its own. Both stage a copy and replace the file only once every write in
the batch has succeeded.

Full detail is in `SteamShell\CHANGELOG.md` under 2.0.2.

## Version and schema lock

| Component | Product version | Compiled file version | Settings schema |
|---|---:|---:|---:|
| SteamShell | 2.0.2 | 2.0.2.0 | 23 |
| SteamShell elevated helper | 2.0.2 | 2.0.2.1 | Uses standalone settings |
| SteamShell-XFE | 2.0.2 | 2.0.2.0 | 18 |

The helper's fourth version field differs from the main executable's on purpose,
so every 2.0.2 setup or upgrade replaces an older embedded helper. It is not a
patch number.

Neither settings schema changed in this release. Both products upgrade from
2.0.1 in place with no migration.

`ElevatedHelperExpectedVersion` moved to `2.0.2.1` and is compared for exact
equality. Standalone re-extracts its embedded helper whenever the copy on disk
does not match, so it self-heals; the companion reports the mismatch and asks
for `SteamShell.exe` to be run. Upgrading by launching the companion first will
therefore show one elevated-helper warning until standalone has run once.

This bump changed 26 literals across seven files, eight of them written a second
time as escaped regex inside the two validators — the spelling that made the
2.0.0 bump miss five copies. Each was replaced against an expected occurrence
count per file, aborting rather than half-landing on a mismatch, and AutoHotkey's
own `2.0.19` requirement shares a prefix with the version being moved and was
excluded and re-counted afterwards. The thirty documentation mentions were read
individually rather than replaced, because a reference to the working tree and a
reference to the downloadable release do not move at the same time.

## Verification status

Full harness run on Windows, 2026-08-10 — **all checks passed**, reported by the
maintainer, on the tree locked here. The Windows test checklists for both
products were worked on this build and confirmed by the maintainer, including
the four items new to this release: the companion's Settings window opening,
application switching in Xbox Mode, the companion's Save & Apply landing fields
and the startup list together, and Health Check's elevated-helper row after the
version moved.

The compiled versions in this directory were additionally confirmed by reading
each binary's PE version resource: `2.0.2.0` for SteamShell and SteamShell-XFE,
`2.0.2.1` for the helper. `current\SteamShell.exe` is byte-identical to the
`dist\` executable the harness published. The tree copy here was verified
against the working tree by recursive diff, with only the transient `dist\`,
`build\` and `__pycache__` excluded, rather than assumed.

Structural facts about this exact source, from `SteamShell\Replay-Validation.py`,
which replays both validators' assertions without Windows:

- 375 functions defined once in `SteamShell-Shared.ahk` (both trees) and 147 in
  `SteamShell-Common.ahk` (all three programs); no tree redefines any of them.
- 66 functions are defined in both trees. 6 are flagged by the fingerprint gate
  and 36 are recorded in `DIVERGENT_FUNCTIONS.txt` with a stated reason.
- 56 shared seams, counted against the expected total in `Validate-Common.ps1`.
- 1,123 product assertions replayed from the two validators, all passing. A
  further 65 are written against a property subject and are only checked on
  Windows.
- Function totals: SteamShell 481, SteamShell-XFE 224, SteamShell-Helper 46.

The harness gained one check this cycle that the Windows build could not have
made: event-handler arity. The Settings crash above passed a full build because
the name existed, the function was real, and every assertion about it held — only
its arity was wrong, and nothing read arity. It is checked now, in the Python
replay, so it is caught without Windows.

## Known limits

Unchanged from 2.0.1:

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
- Windows Settings and other packaged Store applications still cannot be added
  to an executable list by name.
- The recent-application history still does not survive a restart.
- Runtime INIs, logs, controller profiles, diagnostic archives, `build\`,
  `dist\` and machine-specific state are not part of this snapshot.

New in 2.0.2:

- **`explorer.exe` is refused on the companion's automatic-mouse list**, and
  that is deliberate rather than a default. Explorer owns the Xbox FSE task
  switcher, so the entry cannot be honoured there. A companion whose list held
  only `explorer.exe` is left with an empty list, which turns automatic mouse
  mode off exactly as an empty list always has; the log says so once per load.
  The entry is not removed from the user's INI, so saving in Settings is what
  clears it. Standalone is unaffected.
- **The companion's startup-program edits are staged until Save & Apply.** Add
  Program used to write immediately.
- **Controller mapping edits are staged until Save in both products.** The
  companion applied each change the instant it was made, which cannot survive an
  editor that offers Revert.
- **The startup slot count is twenty in both products.** A companion settings
  file holding more keeps them — nothing is deleted — but slots past twenty are
  not read, and are named once per load in the log.

## Checksums (SHA-256)

Covers every file in this directory except `RELEASE.md`, whose contents include
the table itself.

| File | SHA-256 |
|---|---|
| `README.md` | `af8ee3386151d2fefab8675e90f493134562ac37ab2618ea2ecc359604c5879f` |
| `Run-SteamShellValidation.cmd` | `c23db975b6da023ab3938fa85e394d6ea24e36f1d91437c03e7b97b2bdb32742` |
| `Run-SteamShellValidation.ps1` | `e4bb7f4c2d2530c17ae6ea1ea458e0ae79e50130dd5be1c8e563664f55720de5` |
| `STEAMSHELL_PROJECT_OVERVIEW.md` | `8d0b7bde28429e009a9293c6e432ecf13f9c8aaf2cff835ad6fb439d5309b407` |
| `SteamShell/Build-SteamShell.cmd` | `30a085ed1548c8cc3462dd3d31f0b5d4a02ca1594028d228a11ed68ad548b05a` |
| `SteamShell/Build-SteamShell.ps1` | `c5f2e34196c61849c75951e5bada6a21e6a2ac290b501c334afe08907a85ba17` |
| `SteamShell/CHANGELOG.md` | `2f898f911ee33ba39dfba45fab6679c1deb86c1083cc012906a19d0d51958b98` |
| `SteamShell/COMMON_FUNCTIONS.txt` | `8e66c277619f3c3145382b2f4fd2c64a0ebc2fdb3ade22493a10dc53429cb816` |
| `SteamShell/CROSS_NAME_DUPLICATES.txt` | `3da6a0c6850894be94b191696e58210a80f7c4cb101bfcd9355804e7c008f0a3` |
| `SteamShell/DIVERGENT_FUNCTIONS.txt` | `f8ef5093d1622a75625c40601dd4904bbff36f1ddd318b0b8cc2664d6cbed556` |
| `SteamShell/INI_READER_MIGRATION.md` | `3e409f547efafc1fc103eb2705b37f59e044d148d862d29b6460b0d0d145b0bd` |
| `SteamShell/PRODUCT_SURFACES.txt` | `e69703a4a7cbcf07331007a9a5d4e263fb7d815a43ef821a5ad5db856ede63eb` |
| `SteamShell/QUICKMENU_ROWS.txt` | `c5718b526520f1adca565758b16f05c9506a56a4c33fd029278f086b00bd5786` |
| `SteamShell/README-XFE.md` | `874a3706203f3398f089566687710ae738e4b2b5b107b952763ed5ab1d3b92d2` |
| `SteamShell/README.md` | `7d24f5d197b48609d2990ee69892cb14cf7180c82313602e3633a1a427006d5d` |
| `SteamShell/Replay-Validation.py` | `8a523dd9fa44ab42072aa9a71261c44cfbb9bdacb96599a642246b58d52c4418` |
| `SteamShell/SHARED_FUNCTIONS.txt` | `36b8360331cce214742e72a183f1003109675798c8e64d391bff7d199318aed3` |
| `SteamShell/SteamShell-Common.ahk` | `a82594a049468d9648526144b8e43432555e6c1ca20bb28cafb380fdcb4b5366` |
| `SteamShell/SteamShell-Helper.ahk` | `c38fb35e1b2deb24dc277c83178ceda59ad8ccc4b812e835a1f8ee79ca2ea300` |
| `SteamShell/SteamShell-Shared.ahk` | `2de18362a01cecb710bbfcc0080fa0be0bf6d7a35f9a930094f466639dc86e20` |
| `SteamShell/SteamShell-XFE.ahk` | `98a6bdf0a9dfcb319c9f41673304a51cf7a09aa3dafcd3e94d6b68ca60a06e95` |
| `SteamShell/SteamShell-XFE_SAMPLE.ini` | `99ebfe16d8ef034f22728a1ab447fb72133403009488a3fab5e2faff4be80ce5` |
| `SteamShell/SteamShell.ahk` | `ba9e2dd871d723a61273df7a4c6b7ccfefe6d39a272646245d3b9ddb71dab3d4` |
| `SteamShell/SteamShell.reg` | `4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a` |
| `SteamShell/SteamShellSettings_SAMPLE.ini` | `9718fdfb62a7d1de3d4b32be6e6eac193ad81e959e3398bb5072ac2fe4b4bc7a` |
| `SteamShell/Test-ControllerProfiles.py` | `37737b6aeb8242607d362b4f6779330a3f396a62a0abcec8bb29f1346eb947e7` |
| `SteamShell/Validate-Common.ps1` | `72d245a9c8d874ef2efeb8d570d826ad3579e19971040fd1d880a1b0bca0d4af` |
| `SteamShell/Validate-SteamShell-XFE.ps1` | `2963889523f414d4fb3748d704383d5e6703ddfd7dffe3be6af7bf1b2e729117` |
| `SteamShell/Validate-SteamShell.ps1` | `8e12a208db341ddec298352776f67177a6a3ed1c432b3d108b6600192bab2a48` |
| `SteamShell/WINDOWS_TEST_CHECKLIST-XFE.md` | `cc6a448005b36f5c2acffcd58fada3bc1ad81fd7d623f2d8f3f9e9a7970ff237` |
| `SteamShell/WINDOWS_TEST_CHECKLIST.md` | `d81865be30ae562586327d53065f5b466ecddf90582347171d159a2efd02db3d` |
| `SteamShell/XFE_PARITY_NOTES.md` | `6aca37da34c03f7f0593356bb96b39c4131d163e7f7e2b5a15770d9e823611ed` |
| `SteamShell/assets/SteamShell-XFE-icon.png` | `c7a85f0e7bc20ec733fc5d9737167cde7965d4def90946353005926b85357005` |
| `SteamShell/assets/SteamShell-XFE.ico` | `2fe6f14f89e2a051e753a767b2da68e16f5666baef11d0252c954c5c69c93002` |
| `SteamShell/assets/SteamShell-icon.png` | `bf8d9908917c4063e6bdb515a30e2519fa363d69b6ed08fb03dc6e2f1abc2170` |
| `SteamShell/assets/SteamShell.ico` | `260dba5dc8d228ede26089e63749ca53c0b2b3d369ff2b3cedd1232d4121a92b` |
| `SteamShell/extras/bigpicture_startup.webm` | `a12363458ace3a72a975c0ba650890960c439f39f96712805e896bf7c86f363b` |
| `SteamShell/extras/black.png` | `0ab0900f03e8f2a825691374d5e063a177085dc6a572ef15e7750b4a2bd69b41` |
| `SteamShell/images/control-panel.png` | `0199cfbf13f982031c536be47e312205b06960d5c206f6363d942830da25f42e` |
| `current/SteamShell.exe` | `2b0add3ff08fb8c02726c21394c4ef09a67e0db28fce4940e96d0fb4ab86bfd7` |
