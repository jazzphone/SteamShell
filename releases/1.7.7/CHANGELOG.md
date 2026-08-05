# SteamShell changelog

## 1.7.7 — 2026-08-01

- All SteamShell settings/editor surfaces now temporarily receive controller
  mouse input while active. This includes Controller Mapping opened directly
  from Quick Settings; it does not alter the persisted Mouse Mode setting.
- RTSS Frame Limit now cycles through the standard caps, a named configurable
  **Preset**, and **Custom**. Schema 16 copies the old `CustomFrameCap` into the
  new `PresetFrameCap`, while Custom keeps and persists its own last adjusted
  value. The same behavior ships in XFE 0.1.21/schema 8.

## 1.7.6 — 2026-08-01

- Added **Open Keyboard** immediately below Game Bar. Quick Settings is fully
  dismissed before the Windows touch keyboard is presented.
- Added a persisted **Mouse Mode** main-row toggle. When enabled, the controller
  pointer and mappings work without holding View/Back; enabling it also repairs
  a disabled controller-mapping master switch.
- Replaced the main-page Controller Layout row with **hold Y on the main page**
  to open the styled Controller Mappings submenu. Its final **Set Controller
  Mappings** row opens the full editor.
- Added **Windows Settings** to Settings; removed Reload Settings there and the
  Diagnostics Control Panel and Health Check rows from System.
- Standardized Quick Settings labels and descriptions to title case. Settings
  now reads **Features & Configuration** and System reads **Power & Diagnostics**.
- Advanced settings schema to 15. Existing custom row order is retained while
  the retired layout row is removed and the two new rows are inserted after
  Game Bar. The same applicable behavior is mirrored in XFE 0.1.20/schema 7.
- Updated fresh-install and missing-key defaults from the validated living-room
  profile: faster focus/exit timing, a 30% window threshold, Purple Quick Menu,
  3000 controller deadzone, Explorer automatic mouse, guarded launcher cleanup,
  and RTSS Separate controls with a 158 FPS custom cap. Startup launch scheduling
  is enabled but every `Program1`–`Program20` slot remains blank. Applicable
  Quick Menu, controller, startup, Lite Assist, cleanup, and RTSS defaults are
  mirrored in XFE.

## 1.7.5 — 2026-08-01

Findings from a full cross-tree audit of SteamShell and SteamShell-XFE. Every
item below that touches shared behaviour was applied to both trees in the same
pass; see `XFE_PARITY_NOTES.md`.

The initial audit pass was validated on Windows 11 with Windows PowerShell
5.1.26100 and AutoHotkey 2.0.26: both sources parsed, both validators passed,
both trees compiled, and the standalone negative build tests passed. The
follow-up fixes below changed both sources and the root harness and therefore
still require a fresh Windows run of `Run-SteamShellValidation.cmd`. Nothing
*behavioural* has been verified — see the caveat at the end of this entry.

- **Audit follow-up:** RTSS default-path discovery is centralized across menu,
  launch, health, and hooks-DLL lookup in both applications. XFE now loads its
  log-rotation values into the intended globals. SteamShell resolves unquoted
  shell paths with spaces and PATH executables, and a failed PreviousShell
  write-back retains the recovery shortcut and registry metadata.
- **Validation publication:** the root harness tests broken source and stale
  output in both build trees, returns a non-zero exit code on failure, and
  publishes both hash-verified EXEs to root `current\` as one directory
  transaction only after the complete run passes. Cross-tree parity can no
  longer silently skip when both trees exist but its checker is missing.

- **Build:** `Build-SteamShell.ps1` now reads the real exit code of
  `AutoHotkey64.exe /Validate` and `Ahk2Exe.exe` via `Start-Process -Wait
  -PassThru`, matching what XFE already did, and verifies the output EXE was
  rewritten by *this* build so a stale `dist\SteamShell.exe` cannot satisfy the
  existence check.

  On the severity: this was **not** a live defect, contrary to how the audit
  first reported it. Both executables are GUI-subsystem, for which Windows
  PowerShell can fail to set `$LASTEXITCODE` — but the previous code piped the
  output through `ForEach-Object`, and draining that pipeline synchronizes on
  process exit, so the exit code was reliable in practice. Measured on Windows
  PowerShell 5.1.26100 with AutoHotkey 2.0.26: a deliberately broken source
  returned exit code 2 through both the old and the new mechanism. The change is
  kept because it does not depend on the pipe remaining in place — removing the
  `2>&1 |` during some later edit would silently reintroduce the hazard — and
  because it separates stdout from stderr. It is hardening, not a bug fix.
- **Uninstall:** `HKCU\Software\SteamShell\PreviousShell` is now read back.
  Both registration paths had recorded it since 1.5.0 and nothing ever read it:
  every restore wrote a literal `explorer.exe`, and the uninstall then deleted
  the key holding the only record. A user who ran a different custom shell
  before installing SteamShell lost it silently and unrecoverably. `/uninstall`
  now reinstates the recorded shell after verifying it exists and does not point
  back at SteamShell. `/restore` deliberately keeps its hardcoded `explorer.exe`:
  it is the emergency path, where a known-good shell beats a faithful one.
- **Quick Menu:** the selection index is normalized at every site that moves it
  rather than downstream in the repaint. `QuickMenuRefresh` returns early on an
  empty page, which is exactly where a stale out-of-range index used to survive.
- **HDR:** the Win+Alt+B compatibility fallback moved out of
  `SetQuickMenuHdrState`'s `allowToggleFallback` flag and into an explicit
  `RequestHdrToggleFallback()`. Win+Alt+B is a toggle, so the requested on/off
  state was silently discarded on the one path that used the flag. A successful
  HDR change now queues a display reflow, because Windows updates the reported
  state asynchronously after the display blanks.
- `GetPrimaryHdrState` reports `wideColorEnforced`, and `GetRtssFrameLimit`
  reports the resolved profile name and no longer lets an empty `SplitPath`
  result turn a named profile request into a global one. Both bring standalone
  in line with XFE, which already returned these.
- Splash `Mute`, `PlayFullDuration`, and `SafetyMaxMs` had INI defaults that
  disagreed with their own parse-failure fallbacks, so a malformed value
  produced the opposite of the documented default — and quadrupled the splash
  safety ceiling from 15 s to 60 s. The validator now fails on any such pair.
- `CloseExeProcesses` re-validates the process name before it reaches a
  `cmd /c taskkill` command line, and quotes it. Every caller already passed a
  name `ParseExeListPipe` had checked; the guarantee now belongs to the function
  instead of to its callers' habits.
- Log rotation no longer calls `FileGetSize` on every written line. The size is
  estimated between checks and confirmed for real before anything is moved.
- GDI+ is released with a matching `FreeLibrary`, and a failed
  `CreateDIBSection` is detected and logged instead of silently blanking the
  Quick Menu rows. Both applied identically to XFE.
- Validator: the settings schema version is derived from the source and
  cross-checked against the sample rather than compared with a hardcoded `14`,
  which had to be hand-edited on every bump and failed as a false alarm until it
  was. Added assertions pinning the PreviousShell restore, the `/restore` versus
  `/uninstall` split, the HDR fallback separation, and log rotation.
- **Formatting:** `SteamShell.ahk` is reindented from one space to XFE's four,
  with `switch`/`case` bodies aligned to match. Content-only-preserving: nothing
  but leading whitespace moved, the embedded default INI's continuation section
  is untouched, and every line's content was verified identical afterwards. This
  is what makes cross-tree drift visible at all — before it, a raw diff of the
  two trees was entirely noise.
- **Cross-tree check:** `SHARED_FUNCTIONS.txt` and `Validate-SharedParity.ps1`
  at the repository root assert that the 42 functions shared with SteamShell-XFE
  are byte-identical, and both trees' validators run it. Drift now fails the
  build instead of waiting to be found by an audit. The check is skipped when the
  sibling tree is absent, as inside a frozen `releases/` snapshot. The manifest
  also records, in comments, the shared-looking functions that are *deliberately*
  different and why — currently `ToggleQuickMenuHdrState`.

- **Shared-surface pass.** A follow-up measurement asked what *else* could be
  shared. The answer was "less than expected": unifying every cosmetic
  difference — comments, line wrapping, `ShowNotification`/`SetStatus`,
  `ClampInt` vs `Max(Min())`, product-identity strings — would take the
  byte-identical count from 42 to only 50 of 144. Roughly 94 shared-name
  functions differ substantively, and a cross-comparison of all 399 standalone-only
  against all 235 XFE-only functions found exactly one near-duplicate, a
  six-line helper. There is no large hidden seam between these trees.

  What was worth doing, and was done: the four functions that differed *only* by
  comments now carry the better comment in both (`ApplyRoundedCorners` gains the
  measured-on-a-4K-television explanation; XFE gains the PolicyConfig COM
  rationale). `ClampInt`/`ClampFloat` were added to XFE, which had neither and
  open-coded `Max(lo, Min(hi, x))` at 19 sites. And `DisplayChangeSafetyTick`
  now guards its repaint with `if QuickMenuVisible` in both trees rather than
  repainting a destroyed menu once a second for the whole 15-second revert
  window. The manifest grew from 42 to **48**.

  Applying the clamp helper to XFE alone silently broke `BlendHexColor` and
  `CenteredPosition`, which had been byte-identical. `Validate-SharedParity.ps1`
  caught it immediately — the check earning its place on its second day.

- **Proposed, not done:** `INI_READER_MIGRATION.md` scopes replacing the
  composed `ClampInt(ToInt(IniReadS(...)))` idiom with XFE-style typed readers.
  That idiom states each default twice and is where the `[Splash]` defect above
  came from; XFE's shape makes it unrepresentable rather than merely detectable.
  47 call sites in the shell-replacement tree, and not purely mechanical, so it
  wants its own pass.

**Not verified:** everything behavioural. The Quick Menu paint path, the HDR
fallback on a display without Advanced Color, log rotation actually rolling at
256 KB, and `PreviousShell` restore have all been validated as *code* and none of
them as *behaviour*. `PreviousShell` in particular rewrites the Winlogon shell
value and should only be exercised on a machine you can roll back.

## 1.7.4 — 2026-07-31

- Advanced the settings schema from 12 to 14 for Quick Menu accent options and
  desktop-wide automatic mouse mode/exclusions. Existing values are preserved;
  only missing keys receive defaults during migration.
- Removed the 512-entry display-mode enumeration ceiling that could truncate a
  modern GPU/4K TV's driver list at 1280×1024. Resolution selection now reads
  until Windows reports the true end and logs reported/retained mode counts.
- Replaced the Quick Menu's 28 flat label/value controls with one opaque GDI+
  row surface. The selected row now has an antialiased rounded fill, accent
  outline, left accent bar, and soft glow matching the new design reference.
- Rendered that surface at the control's physical pixel size for high-DPI
  sharpness, retained ClearType by keeping it opaque, and delete each replaced
  bitmap so navigation cannot leak a GDI object per repaint.
- Added a live Quick Menu accent setting shared by standalone and XFE: nine
  presets plus a custom `RRGGBB` value. The selected fill is derived from the
  accent so non-blue colors remain visually coherent.
- Prefer Windows 11's composited DWM corners, with `WinSetRegion` retained as the
  Windows 10 fallback.
- Matched the reference more closely after hardware review: changed the panel
  base from Steam blue-black to neutral charcoal, reserved bitmap padding so
  first/last-row glow is not clipped, strengthened and DPI-scaled that glow, and
  suppressed both the native border style and Windows 11's DWM border color.
- Let both recovery dialogs auto-size their wrapped reason text instead of
  clipping long restore errors inside a fixed 56-pixel control.
- Darkened the neutral panel base to `#242424` after the first visual pass, and
  made row-bitmap swaps/page changes redraw atomically with `RDW_NOERASE` so
  navigation no longer flashes the control background between frames.
- Changed unselected labels and values from blue-gray to neutral gray. A custom
  exterior shadow remains intentionally omitted so the menu can stay one opaque,
  non-layered window.
- Made desktop restoration destroy and flush the Quick Menu's compositor surface
  before Steam closes, then block recreation during the shutdown wait. A normal
  hide could leave a non-interactive image of the title, rows, and footer behind
  when the Windows desktop became visible.
- Fixed automatic mouse mode crashing when it first tried to unhide a hidden
  cursor: `PollController()` now declares `MouseHidden` global before reading
  and assigning it.
- Made an `explorer.exe` automatic-mouse entry cover the complete Windows shell
  family, including Start and Search surfaces hosted by separate Windows 10/11
  processes.
- Made **Return to SteamShell** launch Steam Big Picture automatically instead of
  resuming an empty guarded presentation and immediately showing recovery. The
  return transition also destroys the Quick Menu surface to prevent a stale
  compositor image.
- Fixed both recovery headings being vertically clipped at high DPI by creating
  their controls with the large title font instead of resizing an s11 control
  after layout measurement.
- Added desktop-wide automatic mouse mode. It is enabled by default only while
  Explorer owns presentation, has an explicit game/application exclusion list,
  and returns to the conservative allowlist in SteamShell/Big Picture mode.
- Added a checked **Automatic Mouse Throughout Desktop** tray item that persists
  the desktop-wide toggle without deleting either executable list.
- Stopped retaining a hidden Quick Menu HWND between open sessions. Closing the
  menu now detaches its bitmap and destroys the window, preventing DWM from
  resurrecting a stale, non-interactive menu image when a fullscreen game exits.
  Atomic repainting remains active for row and page changes while the menu is open.
- Locked the complete source, documentation, tests, build inputs, assets, and
  SHA-256 manifest in `../releases/1.7.4/`.

## 1.7.3 — 2026-07-31

- Added **automatic mouse mode**. `[Controller] AutoMouseExeList` names
  executables where the View/Back mappings apply without holding View/Back, edited
  from Settings ▸ Controller & Cursor. Empty by default; naming an executable is
  the entire opt-in.
- Implemented it as a **virtual View/Back hold** rather than a second input mode.
  The existing mappings are already a complete desktop mouse — right stick moves,
  left stick scrolls, D-pad arrows, RB left-click, RT right-click, Start opens the
  Start menu — so there was nothing to design and no parallel keymap that could
  drift from the configured one. What happens automatically is exactly what
  holding View/Back does.
- Evaluated it **after** the Quick Menu and Full Settings chords, which read the
  real button state. That is what keeps a misconfigured list recoverable: name a
  game by mistake and the controller becomes a mouse inside it, but both chords
  still work, so the list can be corrected without a keyboard.
- Added `[Features] EnableAutoMouseMode`, on by default, as a kill switch that
  is independent of the EXE list. Disabling a feature should not require deleting
  the configuration that took effort to build, and it is checked ahead of the
  result cache so turning it off takes effect on the next poll.
- Unhid the cursor when the mode engages. Moving a pointer that cannot be seen is
  not a usable mode.
- Settings schema is now **12**. The only changes are the two new keys, which
  `SyncSettingsIniSchema` adds to existing files with their defaults, so
  upgrading changes no existing value.

## 1.7.2 — 2026-07-31

Field fixes from hardware testing, a recovery-path audit, and the logging and
input-feel work that came out of both. Settings schema stays at 10: nothing here
adds or retires an INI key, so upgrading from 1.7.1 involves no migration.

- Made the desktop-restore failure screen **controller-navigable**. It was a
  native `MsgBox`, which the controller poll loop has no handling for, so
  answering it needed pointer emulation — hold View/Back, right stick, mapped
  click — and only if controller mouse or the Quick Menu happened to be enabled.
  That is the more severe of the two recovery states: Explorer may be dead, so
  there is no taskbar and no other application to reach. It now matches the
  Steam-did-not-start screen, which was already a controller-first GUI, and both
  share one input handler.
- Surfaced warnings in the Quick Menu footer. `ShowNotification` is log-only by
  design — the old bottom-corner overlay was distracting and is not coming back —
  but that left 52 warnings visible only to someone who opens the log, which on a
  couch device is nobody. A message now displaces the button hint for four
  seconds when the menu is open, and the hint returns on its own. Matches XFE's
  `SetStatus`.
- Stopped writing to RTSS on **every press** of the Custom FPS row. Each press
  was a `LoadProfile` + `SetProfileProperty` + `SaveProfile` — a disk write —
  plus `UpdateProfiles`, so the limiter was genuinely reconfigured a dozen times
  while scrolling and the frame rate chased the number. The value is now held
  pending, the row shows it immediately, and RTSS is written once the user stops.
- Restored the **native Windows menu** on tray right-click, matching XFE.
  Double-click still opens the Quick Menu via the menu's default item. The
  interception that replaced right-click with the Quick Menu existed because a
  native menu freezes controller polling — true, but it had the context
  backwards: reaching a tray icon means using a pointer, and a controller user
  opens the Quick Menu by chord or hotkey. It optimised for a case that barely
  happens at the cost of the one that happens constantly. The freeze is accepted
  rather than forgotten, and the validator now asserts the interception has *not*
  returned so it cannot come back by accident.
- Replaced press-count escalation with **hold-to-repeat**. Growing the step after
  several quick presses meant tapping quickly silently changed what a tap did —
  the same gesture produced 1, 5 or 10 depending on timing the user could not
  see. A press is now always exactly one step, however fast presses arrive.
- Made speed come from **holding**, and accelerated the repeat *rate* rather than
  the step: 80 ms, then 40 ms after 1.2 s, then 20 ms after 2.5 s. Every change
  stays 1, so the value is predictable and can be stopped exactly where wanted;
  holding just delivers more of them. This also removed grid-snapping, which only
  existed to make large steps land on round numbers.
- Limited repeat to rows whose value is a **number**, not a list. Scrubbing audio
  output or resolution at fifty changes a second would be useless and would fire
  real device work per step.
- Cancelled a pending value when a preset is chosen. Without it, the deferred
  commit could fire *after* the preset and overwrite it. Save Limit to Profile
  flushes it instead, so the profile gets the value on screen rather than a stale
  one.
- Stopped the window engine centring **dropdown menus and other popups**. They
  are real top-level windows, so nothing excluded them, but centring one is
  actively wrong rather than untidy: a dropdown is positioned relative to the
  control that opened it, and moving it to the middle of the screen detaches it
  from its parent. Centring had no size or structure test at all — its only
  condition was being more than two pixels off centre, whereas maximising has
  always been gated by `MinWidthPercent` *and* the window having a maximise box.
- Filtered those by **structure rather than name**: child windows, non-activatable
  windows, captionless windows below a size floor, small tool windows, and the
  classic popup classes. A class blacklist alone cannot keep up, since every UI
  framework invents its own popup class, while the styles that make something a
  popup are the ones Windows itself uses to decide it is not a normal application
  window.
- Used **size, not ownership**, as the discriminator for captionless windows. The
  first attempt required the window to be owned as well, reasoning that a dialog
  is owned but keeps its caption. That fixed Explorer's dropdowns and missed
  Qt's — PCSX2's menus are unowned and passed straight through. Ownership is a
  framework detail; size is not. A dropdown is small, a borderless game fills the
  screen, and a captioned window is exempt entirely so small dialogs are still
  centred.
- Added a diagnostic line recording what the engine centred and why it qualified
  — process, class, size, style, exStyle, owner — under `GameLogMode=DIAGNOSTIC`.
  Two rounds of this bug were diagnosed by guessing at the UI framework instead
  of reading the window; the next one names itself.
- Gave every operational log line a **timestamp and a level**, matching XFE.
  Standalone's `LogLine` added neither, so the log recorded what happened but not
  when — two lines could be a second or an hour apart with nothing to say which,
  and elapsed time is exactly what a startup stall, a focus handoff, or a
  sustained-exit window has to be reasoned about in. The only timestamped lines
  were the game-score rows, which stamped themselves.
- Split `LogRawLine` out for that game-score table. It is columnar and formats
  its own leading timestamp, so a second prefix would misalign every row.
  `ShowNotification` now passes its level to `LogLine` instead of embedding
  `NOTICE [Warning]:` in the message text.
- Logged **what holds the foreground** when the Quick Menu fails to take it. The
  existing lines reported only that the handoff failed, which is not actionable:
  a game holding focus, Steam holding it, and a Windows surface holding it need
  completely different responses. The line now names the process, window class,
  size, and whether it covers its monitor — an exclusive-fullscreen game is the
  usual reason the handoff is refused, and that cannot be told from a borderless
  one by process name alone.
- Deliberately did **not** add further retry attempts. The handoff is refused by
  rule rather than by timing, so more attempts do not change the outcome, and
  against a game that re-asserts itself they become a focus fight — which on an
  exclusive-fullscreen title means repeated minimise/restore churn, worse than
  the problem being solved. The reasoning is recorded at the call site.
- Fixed **Save Limit to Profile** reporting `No game in foreground` while a game
  was plainly running and the Task Switcher was listing it. The row used only the
  raw foreground window captured when the Quick Menu opened, and that is
  regularly `steam.exe` — the window engine's Steam refocus can pull Big Picture
  forward moments beforehand, and a borderless game can sit behind a Steam
  surface. Both are excluded on purpose, so the row went blank. It now falls back
  to the window engine's detected game, which is the same detection driving Game
  Foreground Assist and what the Task Switcher reflects.
- Made that row say what it saw. `Steam in front, no game detected` and
  `No game in foreground` are different problems, and this row is the only place
  the difference is visible. The save also logs both candidate sources.
- Corrected the RTSS page's footer hint, which still read `Left/Right Off/On`
  after the Frame Limit row replaced the separate limiter row.

## 1.7.1 — 2026-07-31

Startup reliability, live RTSS frame-cap control, and a codebase audit. Settings
schema stays at 10: nothing here adds or retires an INI key.

- Added a live **Frame Limit** row to the Quick Menu's RTSS page, cycling
  `Off · 30 · 40 · 60 · 90 · 120 · Custom` with Left/Right. Selecting Custom
  reveals a **Custom FPS** row beneath it for any value. Written through
  `SetProfileProperty` / `SaveProfile` / `UpdateProfiles` on `RTSSHooks64.dll`,
  which the integration now resolves alongside the existing read exports; all
  three are optional, so an RTSS build without them keeps overlay and limiter
  control and shows the cap read-only rather than failing outright.
- Folded the separate **Frame Limiter** row into that one row wherever live DLL
  control is available. RTSS has two independent mechanisms — a global
  limiter-disabled flag and a per-profile `FramerateLimit` — and surfacing both
  meant two rows that could each mean "no limiting". The shortcut fallback path
  still shows both, because without the DLL there is no value to fold in.
- Mapped "Off" to the limiter **flag**, never to the value. Writing 0 would
  discard the user's number, so an off/on round trip would silently forget 72
  and come back uncapped; clearing the flag leaves 72 in the profile, and
  cycling back on restores it instead of jumping to the first preset.
- Restricted every frame-cap write to the **global** profile. Per-game profiles
  are the user's own tuning, and a quick menu that writes whichever profile
  happens to be in the foreground can silently change a game's configuration.
- Escalated the Custom FPS step 1 → 5 → 10 on consecutive presses, resetting on
  any pause or reversal. Quick Menu navigation is edge-triggered and nothing in
  the menu auto-repeats, so the existing fixed step of 1 needed sixty presses to
  get from 60 to 120.
- Added a **Save Limit to Profile** row that copies the current global frame cap
  into the foreground executable's own RTSS profile, with that executable's name
  shown in the value column. The name comes from what owned the screen before
  the menu opened, since asking once the menu is up always answers SteamShell;
  Steam's own surfaces are excluded, because a profile named `steam.exe` caps
  the client rather than a game.
- Made that write surgical rather than a clone. The target profile is loaded
  first so any other tuning the user has done for that game survives, and only
  `FramerateLimit` is replaced. It is also the only place a per-game profile is
  ever written, it requires the existing two-press confirmation, and it restores
  the global profile afterwards so the Frame Limit row keeps reading the value
  it is supposed to show.
- Updated the Quick Menu RTSS parity assertions in `Validate-SteamShell.ps1`
  and `Validate-SteamShell-XFE.ps1`, which still described the removed
  `rtssLimiterState` row. They now assert the combined Frame Limit row, the
  conditional Custom FPS row, and Save Limit to Profile, so the guard protects
  the current design instead of blocking the build on the old one.
- Stopped the startup curtain from burying SteamShell's own windows. The splash
  guard re-asserted topmost every `SplashTopmostGuardMs`, and since Full
  Settings, the Quick Menu and the Steam recovery screen are also topmost, the
  curtain won every half second and buried whatever the user had just opened.
  It now yields while any of those is visible; the curtain stays up and its
  close timer is untouched. This mattered because those windows are the only
  ways out of a stuck curtain on a handheld with no keyboard — the recovery
  screen reached by the startup fix above was being covered by the very thing
  it existed to escape.
- Gave the controller Full Settings chord a hold requirement, a yield, and an
  early return. It fired on the press edge from above the poll's consumer
  gates, so a stray grip during play could throw Full Settings over a running
  game, and pressing it with the Quick Menu open produced a focused Settings
  window that ignored input while the Quick Menu behind it kept receiving every
  button. It now matches the Quick Menu chord's hold, declines while another
  surface owns controller input, and returns once fired. The chord state is
  also cleared at both existing discard points, so a disconnect mid-hold cannot
  complete a stale chord on reconnect.
- Stopped re-issuing the limiter flag write when the Frame Limit row is already
  at `Off`. Left clamps to that entry at the end of the list, so every further
  press repeated the `SetFlags` call and re-showed its notification.
- Removed the Quick Menu handler cases left dead by the Frame Limiter row
  merge (`rtssLimiterState`) and a set of older ones no longer produced by any
  row (`audio`, `rtss`, `rtssOn`, `rtssOff`, `framecap`, `framecapOn`,
  `framecapOff`). `case "audio"` was shared with the live `audioOutput` and only
  the dead label was dropped; the identically named case in the Quick Menu
  order-label mapper is unrelated and untouched.
- Removed 16 unreferenced functions, including a theming chain
  (`ApplySteamShellTheme` → `ApplyModernWindowStyle` → `ColorRefFromRgb`,
  `ThemeNativeControl`) and a geometry chain (`GetClientRectPx`,
  `ForceGuiFullscreen`, `GetGuiClientSize`, `GetPrimaryMonitorRect`) that only
  referenced each other. `Validate-SteamShell.ps1` mentions
  `ApplyModernWindowStyle` in a `-notmatch` assertion, which still passes.
- Declared the frame-cap status-control handles at script scope. Rows 5-8 were
  added later and existed only as in-function declarations, making them ordinary
  globals while rows 1-4 were super-globals; the writes are inside `try` and the
  guard tests only row 1, so an undeclared handle would have silently stopped
  updating rather than failing. Same for `ControllerMapGui`,
  `g_ControllerMapUI`, `_ShortcutCap`, and the Control Panel speed controls.
- Declared `AudioPeakThreshold` and `DEFAULT_AUDIO_PEAK_THRESHOLD` with
  `global`, matching every other script-scope variable. Without it a function
  reading them without its own declaration would get an empty local.
- Cached the global `FramerateLimit` read for 400 ms, on the same reasoning as
  `IsSteamRunning`: the row is evaluated once per repaint and every miss costs a
  `LoadProfile` plus a `GetProfileProperty` round trip. The cache is dropped
  after any write so the row can never show a value it just replaced.

- Judge Steam's startup by a **Big Picture surface** rather than by
  `ProcessExist("steam.exe")`. The process appears almost immediately and then
  sits on a "Connecting", sign-in, or client-update window for as long as the
  network takes, which on a Wi-Fi handheld is long enough to matter and on a
  wired HTPC never is. Treating the bare process as success set
  `SteamObservedRunning` on the first monitor tick, and because every branch
  that can raise the recovery screen is nested under `!SteamObservedRunning`,
  that screen became permanently unreachable — with the startup curtain up, the
  result was an indefinite black screen on a machine whose only shell is
  SteamShell.
- Added `SteamBpmSurfacePresent`, a startup-strength companion to
  `WindowEngineFindBpm`. The existing matcher is deliberately permissive (a
  4096 px floor is right for "find something worth refocusing") and Steam's
  startup dialogs clear it easily, so startup now requires a Steam-owned window
  covering `SteamStartupSurfaceMinCoverage` (0.6) of its monitor in both
  dimensions. Coverage rather than title keeps this working across client
  updates, renamed or localized titles, and the steam.exe/steamwebhelper.exe
  ownership split.
- Latched `SteamObservedRunning` explicitly: it is set once and never cleared,
  so a game covering, replacing, or minimizing Big Picture cannot re-open the
  startup path mid-session.
- Stopped the recovery screen's guards from dismissing themselves on a running
  process. `ShowStartupRecovery` and `ShowPendingStartupRecovery` both returned
  early when `steam.exe` existed, which is exactly the state a stalled boot is
  in; both now test for the Big Picture surface.
- Closed a trap on the recovery screen's **Retry**. `LaunchSteamBpm` latched
  `SteamObservedRunning` whenever `steam.exe` was already running, so pressing
  Retry against a stalled Steam marked the session ACTIVE, dismissed the
  recovery screen, and left the user on the black screen with no way to raise it
  again. Observation there now requires the surface too, and each attempt clears
  the one-shot startup warning so a failed retry can raise the screen again.

## 1.7.0 — 2026-07-26

- Added **desktop mode**. Exiting to the desktop no longer terminates
  SteamShell: Explorer takes the desktop back while SteamShell stays resident so
  the notification-area icon, controller-as-mouse, and Quick Menu keep working.
  Entered from the automatic Steam-exit restore, Quick Menu ▸ System, the tray,
  and the Steam-did-not-start recovery screen.
- Made the notification-area menu context-aware and gave the tray a genuine
  **Exit SteamShell**. From shell mode that exit performs the guarded desktop
  restore first, so it can never leave the user with a hidden taskbar and no
  shell.
- Took over the tray icon's right-click and opened the Quick Menu instead of a
  native Windows menu. AutoHotkey will not launch a timer thread while a menu is
  displayed, and controller polling is a timer, so the native menu froze
  controller-as-mouse for as long as it was open — a controller user could open
  the tray menu and then be unable to move the pointer onto it. The Quick Menu is
  an ordinary window and stays fully navigable by controller, mouse, and
  keyboard. The native menu is still built for the double-click default action
  and as a fallback.
- Added a **Reload Settings** row to the Quick Menu's Settings page. It was
  previously reachable only from the tray menu or Ctrl+Alt+Shift+R, neither of
  which a controller-only user on the desktop can reach.
- Registered a `TaskbarCreated` listener and re-assert the tray icon on every
  broadcast. The restore path restarts Explorer, which destroys every existing
  notification-area icon; without this the icon that desktop mode depends on
  could silently fail to come back.
- Moved tray initialisation ahead of SteamShell's own Explorer launch. Winlogon
  starts SteamShell before any shell exists, so the icon's first placement
  always fails and the broadcast is what actually places it.
- Isolated shell enforcement from controller input in `ApplyRuntimeTimers`.
  Desktop mode leaves shell monitoring, the window engine, the Taskbar Guard,
  cursor hiding/parking, and Launcher Cleanup unscheduled while keeping
  controller polling alive. No persisted setting is mutated, so returning to
  shell mode is a pure rescheduling operation.
- Explicitly disarm the Steam lifecycle when entering desktop mode. A stopped
  timer was not sufficient: `SteamLaunched` remaining true meant any reschedule
  would observe Steam as launched-but-absent and immediately re-enter the
  restore path.
- Suppressed the unexpected-exit Explorer recovery in desktop and safe modes.
  Killing SteamShell there would have restarted the user's live Explorer session
  and silently dropped SteamShell as the next-sign-in shell.
- Changed the Quick Menu's **Steam Menu** row to **Launch Steam** when Steam is
  not running. Launching from that row also returns SteamShell to shell mode;
  Steam started by hand from the desktop deliberately does not, so browsing a
  library from the desktop never yanks the desktop away. Steam Quick Access
  reports `Steam is not running` and is inert meanwhile.
- Changed the recovery screen's **Restore Desktop** from a permanent restore to
  a session restore. A single failed Steam launch no longer deregisters
  SteamShell as the Windows shell, and the permanent restore remains available
  from Settings, the Setup Assistant, and Ctrl+Alt+Shift+E.
- Made the Steam-shutdown failure paths visible. `ShowNotification` is log-only,
  so abandoning a restore with the taskbar still hidden was silent. A Steam that
  will not close within 20 seconds now offers to restore the desktop anyway.
- Stopped cursor parking and hiding from running while Explorer owns the
  desktop, and reported the active presentation mode in Health Check.
- Added a **black desktop background** (`[Features] EnableDesktopBlackout`, on by
  default). A full-screen `WS_EX_NOACTIVATE` black window supplies the pixels
  while `Progman`/`WorkerW` are hidden through the same `EVENT_OBJECT_SHOW` hook
  and one-second safety check the Taskbar Guard uses, so neither the wallpaper
  nor desktop icons show in the gaps around Steam. It deliberately owns no
  system or registry state — the wallpaper setting is never touched, and
  everything it changes dies with the process or is undone by the Explorer
  restart that unexpected-exit recovery already performs. Clearing the wallpaper
  through `SPI_SETDESKWALLPAPER` was rejected for the opposite reason: it
  survives a crash.
- Guarded the backdrop against the one failure that would matter: it is re-sunk
  to the bottom every tick, and if it is ever detected as the foreground window
  it is pushed back down and the event is logged. The blackout is released on
  every path that hands presentation back to Explorer — desktop restore, Safe
  Mode, exit cleanup, and any timer reconfiguration.
- Made the blackout toggleable from Quick Menu ▸ Settings ▸ General + Startup
  with immediate effect rather than at next boot, so a controller alone is
  enough to recover if the backdrop misbehaves on a given machine. The Quick
  Menu is `AlwaysOnTop` and stays reachable over it.
- Reported blackout state, backdrop presence, desktop visibility, and hook mode
  in Health Check.
- Advanced the settings schema to 10 for `Features.EnableDesktopBlackout`.
- Extended static validation to cover the desktop-mode contract: the
  session/permanent exit split, lifecycle disarm, timer isolation, tray
  re-assert, tray-before-Explorer ordering, the suppressed exit recovery, the
  tray right-click interception, Reload Settings remaining reachable from the
  Quick Menu, and the desktop blackout's non-activating backdrop, paint-before-
  hide ordering, release on every Explorer handoff, and controller toggle.
- Replaced the duplicated Quick Menu settings-row `case` lists with shared
  `IsQuickMenuToggleSetting` / `IsQuickMenuAdjustSetting` predicates over one
  pipe-separated source of truth. AutoHotkey v2 allows at most 20 values per
  `Case`, and the longer list had reached that ceiling. Static validation now
  rejects any `Case` carrying more than 20 values, counts the predicates' id
  lists as activation coverage, verifies both switches still consult them, and
  reports a dispatch entry whose Quick Menu row no longer exists.
- Taught static validation to reject an `else` attached to a braceless `try`
  if-body, which AutoHotkey v2 cannot parse. `Loop`/`While`/`For` are excluded
  because v2 gives those their own legitimate `Else` clause.
- Promoted the desktop-mode build to SteamShell 1.7.0 and preserved its source,
  build files, assets, documentation, tests, and checksum manifest in
  `../releases/1.7.0`.

## 1.6.0 — 2026-07-26

- Ported the applicable SteamShell-XFE presentation refinements without changing
  the standalone shell, taskbar, Explorer, or focus-engine ownership model.
- Reworked the Quick Menu into an open-session repaint-in-place overlay with
  filled selection rows, tighter geometry, keyboard navigation, and
  reveal-before-shape DPI handling so rounded regions cannot clip high-scale
  displays. Closed menu sessions are now destroyed rather than retained hidden.
- Added live RTSS global overlay/limiter state and direct control through
  `RTSSHooks64.dll`, including the foreground profile's actual frame limit.
  Existing HotkeyHandler shortcuts remain the automatic compatibility fallback.
- Replaced the blind HDR shortcut with live primary-display Advanced Color state
  and explicit Off/On control, retaining Win+Alt+B as an honest fallback.
- Added primary-display Windows Scale control with the existing 15-second safety
  rollback and delayed Quick Menu re-centering after DPI changes.
- Added a configurable left/right mouse-parking edge and fixed all mouse
  observation to use screen coordinates.
- Added a standalone SteamShell icon, notification-area menu, and default icon
  embedding in Windows builds.
- Added a double-clickable Windows build launcher that preserves and displays
  the PowerShell build's real exit code.
- Advanced the settings schema to 7 for `MouseParkEdge` and
  `RTSS.UseDllIntegration`.
- Added an all-category Full Settings geometry audit that logs invalid,
  unregistered, overlapping, or horizontally out-of-bounds native controls,
  plus validation against duplicate persistent settings bindings.
- Kept the expanded static validator compatible with inbox Windows PowerShell
  5.1 by using trailing binary operators for multiline regex expressions, and
  corrected its trailing-whitespace regex so lines ending in `t` are not
  reported as false positives.
- Removed a duplicate `MouseParkEdge` global declaration that AutoHotkey v2
  rejected at load time, taught static validation to detect duplicate
  per-function globals, and made build-time interpreter diagnostics visible.
- Made Ahk2Exe builds print the selected compiler, base, output, icon, exit
  code, and captured compiler diagnostic instead of returning an opaque
  missing-output error.
- Added **Register Current EXE as Shell** to Advanced & Logging for portable
  deployments. It verifies the exact compiled path in the current-user
  Winlogon `Shell` value, preserves recovery metadata, and creates the
  emergency Explorer-restore shortcut without copying the EXE.
- Matched the standalone Quick Menu presentation to XFE's final borderless
  layout, removed its DWM backdrop frame, and batched page construction while
  redraw is disabled so page changes appear fully composed.
- Capped Full Settings at 660 logical pixels, based its monitor-fit calculation
  on the native GUI DPI instead of Steam's virtualized DPI, widened field-label
  columns, and reorganized Advanced actions into an aligned two-column grid.
- Replaced Full Settings' utility-window chrome with a standard title bar:
  Close and Minimize are available, Maximize remains disabled, and vertical
  resizing is preserved.
- Matched XFE's Quick Menu main page row-for-row with Steam Menu, Steam Quick
  Access, Game Bar, and descriptive right-column summaries in place of generic
  arrows and standalone-only return/focus rows.
- Added configurable Steam Menu, Quick Access, and in-game overlay shortcuts,
  including a schema-8 migration that gives existing installations the new
  main-page order while retaining applicable hidden-row preferences.
- Ported XFE's foreground-thread handoff to Quick Menu, with one delayed retry,
  so Steam Big Picture no longer retains focus and processes menu navigation at
  the same time.
- Kept the useful standalone keyboard split while porting XFE's Quick Menu
  behavior: `Ctrl+Alt+Shift+Q` opens Quick Menu, `Ctrl+Alt+Shift+S` opens Full
  Settings, and `Ctrl+Alt+Shift+P` remains dedicated to Control Panel.
  Focus-gated Quick Menu keyboard navigation is protected by static validation.
- Replaced the remaining legacy Audio, Display, and RTSS Quick Menu submenus
  with XFE's row sets and behavior. Display now stages Resolution, Refresh rate,
  and Scale independently and applies them as one 15-second guarded transaction.
- Fixed shortcut presentation so the `+` separator inserted by `Ctrl+` is not
  mistaken for an AutoHotkey Shift modifier; Steam Menu and Steam Quick Access
  now correctly display Ctrl+1 and Ctrl+2.
- Ported XFE's paced `SendEvent` delivery for the in-game Steam overlay, giving
  Steam's hook enough modifier-down time to reliably observe Shift+Tab.
- Split Task Switcher selection into A for a one-time switch and Y for an
  explicit switch-and-lock, while retaining X close/hold-to-force-close.
- Added a default-on **Run SteamShell as administrator on startup** setting
  under Startup & Splash. Disabling it takes effect next launch and warns that
  Windows may block controller mouse/input control of elevated applications.
- Advanced the settings schema to 9 for the administrator-startup preference.
- Clarified the Task Switcher footer so the X close action also advertises
  hold-X force-close.
- Kept Settings' automatic right-stick/RB pointer mode active across its native
  dialogs and SteamShell companion windows, while keeping category navigation
  and save actions scoped to the main Settings window.
- Promoted the completed parity build to SteamShell 1.6.0 and preserved its
  source, build files, assets, documentation, tests, and checksum manifest in
  `../releases/1.6.0`.

## 1.5.0 — 2026-07-25

- Replaced independent geometry and focus timers with one coordinated window engine.
- Added one shared, validated window inventory for geometry, focus, Task Switcher,
  AlwaysFocus, game detection, and Launcher Cleanup window heuristics.
- Added bounded state-aware center/maximize corrections.
- Added a single focus priority: pinned task, AlwaysFocus, game, then Steam.
- Replaced per-candidate WMI CPU queries with cached Win32 `GetProcessTimes` samples.
- Added Quick Menu coordinated status, Health Check diagnostics, and engine-focused
  Windows tests.
- Added schema 5 settings refinement: coordinated-engine cadence and retry values now
  use safe internal defaults, shell monitoring is independently scheduled, logging
  uses one mode selector, and dependent controls disable when irrelevant.
- Clarified RTSS's display-only frame-cap value and AlwaysFocus's intentional Steam
  exclusion.
- Lowered the default controller stick deadzone from 8000 to 4000 while preserving
  existing user-selected values.
- Expanded pre-build validation to audit Settings and Quick Menu schema bindings,
  named callbacks, menu dispatch, controller-deadzone migration, and the verified
  desktop-restore path.
- Moved Full Settings category switching from LB/RB to LT/RT and restored RB's
  configured short action for right-stick pointer clicks.
- Replaced destructive TabTip/TextInputHost restarts with a Windows touch-keyboard
  presentation request, plus TabTip startup and `/SeekDesktop` fallbacks.
- Added a short geometry settle period and a fresh bounded retry budget when an
  application changes its own startup geometry, avoiding premature suppression.
- Restored the 1.2/1.3 administrator relaunch so controller input and window
  management can interact with elevated Windows surfaces. The handoff now
  preserves command-line modes and safely continues non-elevated if it fails.
- Routed both modern touch-keyboard executable fallbacks through Explorer's
  desktop automation so TabTip does not inherit SteamShell's administrator
  token; classic OSK remains the recovery path when that launch is unavailable.
- Added schema 6 foreground tuning: Responsive (55) is the new default, while
  Balanced (60), Conservative (70), and pre-existing custom values remain
  selectable or preserved in Full Settings.
- Moved the Full Settings Window Management toggle into Focus & Windows,
  changed the maximize-width control to a readable percentage, and normalized
  decimal serialization so binary floating-point noise no longer appears in
  the INI.
- Replaced taskbar hiding inside Steam process polling with a dedicated
  event-driven Taskbar Guard plus a one-second safety check. Desktop restore,
  Safe Mode, and process cleanup explicitly stop the guard before showing the
  normal shell.
- Restored the pre-engine partial-title behavior for Big Picture and tightened
  Steam fallback blockers so minimized, off-screen, tiny, non-activating, and
  auxiliary Steam windows cannot indefinitely reset the refocus timer.
- Expanded Window Engine diagnostics to identify the executable and title
  currently blocking Steam fallback, and Health Check now reports Taskbar
  Guard mode and visibility.
- Changed automatic cursor parking from synthetic mouse input to `SetCursorPos`,
  preserving Windows' idle clock and automatic sleep while retaining hover
  cleanup after real focus changes. Health Check now reports last-input age.
- Made cursor parking follow the observed non-Steam-to-Steam foreground
  transition, including cases where Steam restores itself without a
  SteamShell activation. Parking now waits once for the focused window to
  settle, targets that window's actual monitor edge, verifies the result once,
  and cancels if the user supplies new Windows input or changes applications.
- Added guarded legacy-game surface recognition for older DirectX titles whose
  main window is untitled or marked as a ToolWindow. Qualifying windows now
  participate in Task Switcher, game focus, AlwaysFocus, Steam-refocus blocking,
  and Launcher Cleanup game detection without admitting small overlays.
  Minimized captionless popup surfaces can also be restored as exclusive-
  fullscreen games, while ordinary minimized applications remain manual
  Task Switcher entries.
- Promoted the coordinated window-engine build to the stable 1.5.0 release and
  preserved its complete source release in `../releases/1.5.0`.

## 1.4.0

- Frozen known-good baseline before the coordinated window-engine rewrite.
- Source, settings sample, validation/build scripts, documentation, checksums, and
  test checklist are preserved in `../releases/1.4.0`.
