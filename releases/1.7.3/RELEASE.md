# SteamShell 1.7.3

Released: 2026-07-31

This directory is the locked source release for SteamShell 1.7.3. Do not edit
this snapshot when later development resumes; make changes in `SteamShell/`
under a later version.

Build `SteamShell.ahk` on Windows by double-clicking `Build-SteamShell.cmd`. The
underlying PowerShell script requires AutoHotkey v2.0.19 or newer with a 64-bit
base, runs `Validate-SteamShell.ps1` and AutoHotkey syntax validation, and then
compiles `dist\SteamShell.exe` with the included icon.

No compiled EXE is stored in this snapshot.

**Settings schema moves 10 → 12.** Two keys are added; none are retired.
`SyncSettingsIniSchema` writes both into an existing INI with their defaults, so
upgrading from 1.7.2 changes no value a user has set.

## Why this release exists

1.7.3 is a **deliberate revert point**, taken immediately before the Quick Menu
rendering rewrite begins. That work replaces the row control pool with GDI+
painting in both trees, and it is the kind of change that is much easier to
abandon than to unwind. Locking here means the decision to back out stays cheap.

It is not a feature-driven release. Its content is automatic mouse mode, which
happened to be what was in the tree when the checkpoint was wanted.

## Release scope

### Automatic mouse mode

`[Controller] AutoMouseExeList` names executables in which the View/Back
mappings apply **without holding View/Back**. Empty by default, so naming an
executable is the entire opt-in.

It is implemented as a **virtual View/Back hold**, not a second input mode. The
existing mappings are already a complete desktop mouse — right stick moves, left
stick scrolls, D-pad sends arrows, RB left-clicks, RT right-clicks, X opens the
touch keyboard, Start opens the Start menu — so automatic mode reuses them
rather than introducing a parallel keymap that could drift from the configured
one. Everything downstream reduces to a single condition:

```ahk
viewDown := (buttons & 0x0020) || autoMouse
```

The defaults happen to make this safe in a way worth recording: `L3.Short` and
`R3.Short` are `Builtin:None`, so the L3 + R3 Quick Menu chord does not also
fire a mapping.

**Recoverability was the design constraint.** `autoMouse` is evaluated *after*
the Quick Menu and Full Settings chords, which read the real button state. Name
a game by mistake and the controller becomes a mouse inside it, but L3 + R3
still opens the Quick Menu and the held six-button chord still opens Full
Settings, so the list can be corrected without reaching for a keyboard. The
validator asserts this ordering so a later refactor cannot quietly remove it.

The cursor is unhidden when the mode engages; moving a pointer that cannot be
seen is not a usable mode.

### A kill switch independent of the list

`[Features] EnableAutoMouseMode`, default true. Emptying the EXE list also
disables the feature, but it costs the user the list they built — which makes
*"is this feature causing what I am seeing?"* an expensive question to ask. Both
gates must pass: the toggle allows the feature, the list decides where it
applies.

It is checked ahead of the 250 ms result cache in `AutoMouseModeActive()`, so
switching it off takes effect on the next poll rather than up to a quarter
second later.

## Verification status

**This lock is weaker than 1.7.2's, and deliberately so** — it is a revert point
taken on request, not a release held until hardware sign-off.

Automatic mouse mode has **not been confirmed on hardware**. It was delivered
and its checklist section written, but no test result was reported back before
the checkpoint was taken. The section in `WINDOWS_TEST_CHECKLIST.md` is
therefore outstanding work, not a record of a completed pass.

The item most worth running is the recovery case, because it is the one that
makes a mistake survivable:

- Add a game's EXE to the list deliberately, launch it, confirm the controller
  becomes a mouse — then confirm **L3 + R3 still opens the Quick Menu** and the
  held six-button chord still opens Full Settings.

Everything carried forward from 1.7.2 was validated on hardware at that lock and
is unchanged here.

Verified by static analysis:

- Balanced brace depth, 517 definitions, no duplicates, no unreferenced
  functions, no lazily-created globals, no dead switch cases.
- All timer, hotkey, message and callback targets resolve.
- No variable shadows a function name; no function declares the same global twice.
- Embedded schema and sample INI agree exactly: 158 keys each, no key in one and
  absent from the other.
- The validator's regex assertions were replayed in Python before the lock:
  116 assertions, 77 pass, 0 real failures. The single reported failure is a
  known limitation of the local evaluator, which cannot resolve a `foreach` when
  checking that every Full Settings category has a constructed panel; verified
  by hand.

## Known limits

- Automatic mouse mode is **standalone only**. XFE has View tap/hold actions
  (Steam Menu / Quick Access) that standalone does not, so synthesising a
  permanent virtual View state there needs its own analysis rather than the same
  change applied twice.
- `explorer.exe` is the desktop and the taskbar as well as File Explorer, so
  listing it engages automatic mode for those too.
- GDK titles using GameInput continue to receive controller input while the
  Quick Menu holds the foreground. Confirmed on Forza Horizon 6 with Steam Input
  disabled and the handoff verified. Not fixable in user mode; XInput has no
  exclusive mode and GameInput's background policy belongs to the application.
- `MinCenterCoverage` (0.40), the frame-cap presets and the automatic-mouse
  cache interval are code constants, not INI keys.
- Custom-mode selection is session state and is not persisted.

## Checksums (SHA-256)

| File | SHA-256 |
|---|---|
| `Build-SteamShell.cmd` | `30a085ed1548c8cc3462dd3d31f0b5d4a02ca1594028d228a11ed68ad548b05a` |
| `Build-SteamShell.ps1` | `baa9319ccedbf8f42b5b5ff0713ee2746bcd489d36acef3c41912baba0672497` |
| `CHANGELOG.md` | `ada9fb2f922cde88588a25938237ee4a2056b80fee5c56b5a87c7a353e5b7e40` |
| `README.md` | `58f37755b46f7c89b7ba1264330aabdf932012618ccb83479e7cacf11c7dcd04` |
| `SteamShell.ahk` | `ab0491570148b3970d3b929c91428c462586bd3ad166b36b2b91ecc6b270de37` |
| `SteamShell.reg` | `4e0fa881d4457ccb8be362908e7d9c378e32fc6a25eeb64851b7b396fca7220a` |
| `SteamShellSettings_SAMPLE.ini` | `63f314184a7bd468853e33de409abd531c254ff8ebc819af0cdb2c7e98dd50e8` |
| `Validate-SteamShell.ps1` | `4ad0b3152b3c3233a7b9d5f100f4b823cbb02c27ce215d015cb9725422831734` |
| `WINDOWS_TEST_CHECKLIST.md` | `5e26fb4e3eb51057d6638ce7e3358ec50304c7b95a2ac6261dd34bbd4b1247b1` |
| `XFE_PARITY_NOTES.md` | `a564f5264f3260de49e853fb065acd3864ad4163cac3c3614c3d89c00dc25d9b` |
| `assets/SteamShell-icon.png` | `bf8d9908917c4063e6bdb515a30e2519fa363d69b6ed08fb03dc6e2f1abc2170` |
| `assets/SteamShell.ico` | `260dba5dc8d228ede26089e63749ca53c0b2b3d369ff2b3cedd1232d4121a92b` |
| `extras/bigpicture_startup.webm` | `a12363458ace3a72a975c0ba650890960c439f39f96712805e896bf7c86f363b` |
| `extras/black.png` | `0ab0900f03e8f2a825691374d5e063a177085dc6a572ef15e7750b4a2bd69b41` |
| `images/control-panel.png` | `0199cfbf13f982031c536be47e312205b06960d5c206f6363d942830da25f42e` |
