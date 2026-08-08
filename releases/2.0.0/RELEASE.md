# SteamShell 2.0.0 coordinated release

Released: 2026-08-08

This directory is the immutable source lock for SteamShell 2.0.0 and
SteamShell-XFE 2.0.0, and — unlike 1.9.9 — it also contains the verified
installer built from that source.

`current\SteamShell.exe` is the executable produced by the validation harness in
this directory on the date above, from these exact sources. 1.9.9 shipped source
only; its `RELEASE.md` said so, and its `current\` folder was local build output
excluded by `.gitignore`. This release stores the binary deliberately, so the
rule that excluded `releases/1.9.9/current/` is not extended here.

## Release scope

2.0.0 is the release that followed the 1.9.9 architecture checkpoint. Two themes
run through it.

**Consolidation became a mechanism rather than a goal.** Both products compile one
`SteamShell-Shared.ahk` and one `SteamShell-Common.ahk`; the manifests are checked
exactly; and the duplicate gate runs at 0.45 rather than 0.75. That threshold had
been hiding real drift, because two copies of one routine drift apart in
*structure* as well as text — so the longer a duplicate goes unmerged, the lower it
scores. The metric loses confidence exactly as the problem gets worse.

**Several defects were in code that was already shared, or already documented as
deliberate.** The controller cursor stepped along its path in all three programs
because `ApplyControllerMouseMove` was shared *and wrong*. The shell scored a
second-monitor game against the primary display because a comment in the other
tree asserted it could. The shell had no sleep-resume path because every part of
one had been written in the companion and never called from the shell. A
duplication gate proves two copies agree; it says nothing about whether they are
right, and a divergence recorded in prose is not evidence that anyone decided it.

User-visible changes:

- **Controller cursor movement is smooth.** Speed is a velocity scaled by measured
  elapsed time rather than a distance per poll tick; the poll fires on every
  Windows timer boundary instead of every other one; the sub-pixel remainder is
  carried between ticks. Cursor speed itself is unchanged.
- **Controller mouse speed is a slider** with its range visible, replacing an edit
  box that required knowing what a reasonable number was.
- **A fullscreen game on a second monitor is detected correctly** by the shell.
- **The shell recovers controller input after sleep**, through `WM_POWERBROADCAST`
  and a wall-clock gap check that does not depend on being notified — necessary
  because modern standby, which is what a handheld sleeps into, does not reliably
  deliver the broadcast.
- **Re-arm controller input** on `Ctrl+Alt+Shift+I` and in Settings → Advanced, in
  both products.
- **Batched controller reports are decoded**, not dropped. On a change-only pad a
  coalesced press previously never arrived at all.
- **The XInput sweep no longer costs about 250 calls per second** with no
  controller attached.
- Defects found and fixed across the controller learner, the Settings window,
  Setup Assistant, uninstall, the installation record and the RTSS cluster.

`SteamShell\CHANGELOG.md` carries the full section-by-section record.

## Version and schema lock

| Component | Product version | Compiled file version | Settings schema |
|---|---:|---:|---:|
| SteamShell | 2.0.0 | 2.0.0.0 | 23 |
| SteamShell elevated helper | 2.0.0 | 2.0.0.1 | Uses standalone settings |
| SteamShell-XFE | 2.0.0 | 2.0.0.0 | 18 |

The helper's fourth version field differs from the main executable's on purpose,
so every 2.0.0 setup or upgrade replaces an older embedded helper.

Those numbers are stated **once**, in `Validate-SteamShell.ps1`'s version metadata
block, and derived everywhere else from each source's own `@Ahk2Exe-SetVersion`.
The 2.0.0 bump initially failed on five literals that had been written a second
time as escaped regex — the exact fault a comment in that file described having
fixed for the helper alone. A future bump needs the canonical block edited and
nothing else.

## Settings upgrade

Existing settings files upgrade in place on first run. Schema 23 includes one
change that is not additive:

**`ControllerMouseSpeed` changed unit** — pixels per second, where it was pixels
per poll tick. **Every stored value is converted, not only the former default**,
because leaving a custom 150 alone would have produced a cursor that barely moves.
The conversion is ×32, the rate the poll actually ran at rather than the 62.5 Hz
the old setting implied; it preserves the speed the user has been living with. A
`ControllerPollIntervalMs` of exactly 16 becomes 15, while a deliberately chosen
interval is left alone.

The companion applies the same two conversions, detected by range rather than by
schema version, matching how its other migrations work.

## Verification status

Full harness run on Windows PowerShell 5.1.26100.4202 with AutoHotkey 2.0.26,
2026-08-08 — **all checks passed**:

- Syntax: all five AutoHotkey sources parse cleanly.
- Both static validators pass, each running the cross-tree parity check.
- Shared parity: 256 functions defined once in `SteamShell-Shared.ahk` (two
  trees) and 109 in `SteamShell-Common.ahk` (all three programs); no tree
  redefines any of them.
- Fingerprint gate: 15 of the 57 functions defined in both trees are declared
  divergent in `DIVERGENT_FUNCTIONS.txt`, each with a stated reason.
- Quick Menu: 129 rows across both products; every row reaches an activate path
  and every handler has a row.
- Static validation: 878 functions, 184 settings keys, 77 Quick Menu rows, 124
  named callbacks.
- Compiled and verified: helper 2.0.0.1, companion 2.0.0.0, installer 2.0.0.0.
- **Negative tests passed end to end, for the first time.** A deliberately broken
  copy of each of the five sources was rejected before the compiler was started,
  and a locked output file was correctly rejected as a leftover artefact for both
  `build\SteamShell-XFE.exe` and `dist\SteamShell.exe`. Earlier runs could only
  report these as inconclusive: a failing baseline makes a broken tree prove
  nothing.
- `current\` was published as one directory transaction after every check passed.

The maintainer has hardware-tested the controller mouse smoothness fix and the
settings slider on an ROG Xbox Ally X.

**Not claimed:** that every scenario in either Windows checklist was rerun
immediately before locking. The sleep and resume recovery paths in particular are
verified by construction and by their validator assertions rather than by a
suspend cycle on the day of release. `SteamShell\WINDOWS_TEST_CHECKLIST.md`
describes what to exercise, including the case where device hand-over alone
recovers input and layers 2 and 3 therefore go untested.

## Known limits

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
  The game *scorer* became per-monitor in this release; window *placement* did
  not.
- Runtime INIs, logs, controller profiles, diagnostic archives, `build\`,
  `dist\` and machine-specific state are not part of this snapshot.

## Checksums (SHA-256)

Covers every file in this directory except `RELEASE.md`, whose contents include
the table itself.

| File | SHA-256 |
|---|---|
| `README.md` | `0e63f3d8e4d55d4a0952e03a6fdf2be5f6033c4762fc26f58e47f0da90f35062` |
| `Run-SteamShellValidation.cmd` | `c23db975b6da023ab3938fa85e394d6ea24e36f1d91437c03e7b97b2bdb32742` |
| `Run-SteamShellValidation.ps1` | `cf4c686bf83a86ff272a226614c61dda7b7a29ede76581389e852e280f3b8262` |
| `STEAMSHELL_PROJECT_OVERVIEW.md` | `0f64881598dfea7338ff5c3f23cb360a40112f84926c7d6622ff64575ffe30a6` |
| `SteamShell/Build-SteamShell.cmd` | `30a085ed1548c8cc3462dd3d31f0b5d4a02ca1594028d228a11ed68ad548b05a` |
| `SteamShell/Build-SteamShell.ps1` | `4af4b7d26576b3361c11adc9797bf0c43f4943fa341af56e7a009603ffa7d94c` |
| `SteamShell/CHANGELOG.md` | `e462f37b57ba2dacd138a72ead9a1846aa237048e47dee171adf20e6c4b69809` |
| `SteamShell/COMMON_FUNCTIONS.txt` | `b45473ddac6caaefa6215443a6d77c121e58172e6e8121b8f6d354e2d862d24f` |
| `SteamShell/CROSS_NAME_DUPLICATES.txt` | `6c1058f19970f7e90a43cf6e0ab86d63d1debf08816523939fc7de0c7becac74` |
| `SteamShell/DIVERGENT_FUNCTIONS.txt` | `091fcf3fa45490b11c7cc7763cfcf69f34abf1680c4a8eb04a06604969ab8b11` |
| `SteamShell/INI_READER_MIGRATION.md` | `3e409f547efafc1fc103eb2705b37f59e044d148d862d29b6460b0d0d145b0bd` |
| `SteamShell/QUICKMENU_ROWS.txt` | `c58df3b3b644c1ff19b1da85a1737cccb90b8b05c97646ee33262eeb8e8bd0c6` |
| `SteamShell/README-XFE.md` | `f25dcbfde6a92401fbb12cb40783a08a66bb3168df6529959d391ff159475190` |
| `SteamShell/README.md` | `83505a3512aae650cd2bb6b19ac5617579a3af24bd65703e331576dc38803eec` |
| `SteamShell/Replay-Validation.py` | `bdb2f4179ee1d556b3a5e31ac8c6bf10fa5983aebbc9618fba8930d567b0467b` |
| `SteamShell/SHARED_FUNCTIONS.txt` | `5fb7f5a4c6f0558cf92ace03e2cf01a63564e896bb4149f2eea64d4ba6c5d3c9` |
| `SteamShell/SteamShell-Common.ahk` | `d359ee6af78a13f48918fd5c5d9870ee742cdc51818ba2ba78485b45a7e1274e` |
| `SteamShell/SteamShell-Helper.ahk` | `e43345c0927b78417a0e74603907f71cd7eafd359471565c335989233b87e602` |
| `SteamShell/SteamShell-Shared.ahk` | `3ac9a71d07d08a3ee0a57720d7fd5d1eea67a683de85d154d36c3040adce1dcc` |
| `SteamShell/SteamShell-XFE.ahk` | `5fea5dec7a4cb8dcc205889f347a14221a945b44ea8abc0a52ab1d431f1279b0` |
| `SteamShell/SteamShell-XFE_SAMPLE.ini` | `2e413e1f3c549a89f091173412effe2b13aae1c310ea56fd60b6d4c95ecf4f05` |
| `SteamShell/SteamShell.ahk` | `58606b9fc532d0aecf1802b34a0326cb29d78d67e0879ab2bedb64a1c4fb2676` |
| `SteamShell/SteamShell.reg` | `4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a` |
| `SteamShell/SteamShellSettings_SAMPLE.ini` | `3d96a1568c53a3372a56f14864877de456c407d214aeca80145e89f5f13bee86` |
| `SteamShell/Test-ControllerProfiles.py` | `4bae10b14c19139925a4430d5c7708dd32d1061f2687c79202feba24e496c32d` |
| `SteamShell/Validate-Common.ps1` | `946b8d57262845b318c6fa0e6e941c3227b88a5fbf28702b45ed070efe4194d2` |
| `SteamShell/Validate-SteamShell-XFE.ps1` | `9112f04e89bf0c8933beedfd8a2348e05cb7fce1ec8047e6bd6377ce5016bf3e` |
| `SteamShell/Validate-SteamShell.ps1` | `97124702b70ca3ebe76c3a05623070db9aadbaa633bd82c6594907f45729a0b2` |
| `SteamShell/WINDOWS_TEST_CHECKLIST-XFE.md` | `e24a74b1c0b2ebf36d4038fdfe28034e74dd9ab92a1154c35baefd880ffb766b` |
| `SteamShell/WINDOWS_TEST_CHECKLIST.md` | `764452032a2a62738ba076e929ab08f0277341dec53befdaf1adf33dbf02c119` |
| `SteamShell/XFE_PARITY_NOTES.md` | `ff7dd9042bfea389804b1ab702c78bda1ccd82a04921906fff858e130cc37333` |
| `SteamShell/assets/SteamShell-XFE-icon.png` | `c7a85f0e7bc20ec733fc5d9737167cde7965d4def90946353005926b85357005` |
| `SteamShell/assets/SteamShell-XFE.ico` | `2fe6f14f89e2a051e753a767b2da68e16f5666baef11d0252c954c5c69c93002` |
| `SteamShell/assets/SteamShell-icon.png` | `bf8d9908917c4063e6bdb515a30e2519fa363d69b6ed08fb03dc6e2f1abc2170` |
| `SteamShell/assets/SteamShell.ico` | `260dba5dc8d228ede26089e63749ca53c0b2b3d369ff2b3cedd1232d4121a92b` |
| `SteamShell/extras/bigpicture_startup.webm` | `a12363458ace3a72a975c0ba650890960c439f39f96712805e896bf7c86f363b` |
| `SteamShell/extras/black.png` | `0ab0900f03e8f2a825691374d5e063a177085dc6a572ef15e7750b4a2bd69b41` |
| `SteamShell/images/control-panel.png` | `0199cfbf13f982031c536be47e312205b06960d5c206f6363d942830da25f42e` |
| `current/SteamShell.exe` | `4a17cb13ae492a0fdd556154439441bf679e53002ac11018e4b47c10b77b3043` |
