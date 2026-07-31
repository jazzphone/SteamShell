# SteamShell changelog

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
  preserved its complete source release in `releases/1.5.0`.

## 1.4.0

- Frozen known-good baseline before the coordinated window-engine rewrite.
- Source, settings sample, validation/build scripts, documentation, checksums, and
  test checklist are preserved in `releases/1.4.0`.
