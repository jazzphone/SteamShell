# SteamShell changelog

## 1.6.0 — 2026-07-26

- Ported the applicable SteamShell-XFE presentation refinements without changing
  the standalone shell, taskbar, Explorer, or focus-engine ownership model.
- Reworked the Quick Menu into a persistent, repaint-in-place overlay with filled
  selection rows, tighter geometry, keyboard navigation, and reveal-before-shape
  DPI handling so rounded regions cannot clip high-scale displays.
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
