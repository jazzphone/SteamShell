# SteamShell changelog

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
