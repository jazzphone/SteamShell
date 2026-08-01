# SteamShell / XFE parity notes

This file records the July 2026 parity review. It began when `SteamShell-XFE/`
was a source reference only and standalone changes belonged in `SteamShell/`;
since 1.7.1 / 0.1.15 that is no longer true. See *`SteamShell-XFE/` is no longer
only a reference* at the end.

## Ported to standalone SteamShell

- XFE's final borderless Quick Menu geometry, open-session window/control pool,
  compact footer hints, keyboard navigation,
  redraw-suspended page composition, and reveal-before-measure/shape DPI fixes.
- The post-1.7.3 Quick Menu render layer and accent palette were implemented in
  both trees together: one opaque, physical-pixel-sized GDI+ surface; rounded
  selected fill; accent outline, bar, and padded DPI-scaled glow; neutral
  `#242424` charcoal base; atomic no-erase bitmap/page redraws;
  neutral-gray unselected text; border-suppressed Windows 11 outer corners; and the same preset/custom
  accent model. Both trees destroy the closed menu HWND rather than retaining a
  hidden DWM surface across fullscreen transitions. `QuickMenuRowValueText()` isolates
  the only painter difference: standalone resolves values live while XFE rows
  already carry their rendered value.
- XFE's exact top-level Quick Menu row set and descriptive value column,
  configurable Steam Menu/Quick Access/overlay shortcuts, and foreground-thread
  handoff so Steam Big Picture does not navigate behind the menu.
- XFE's Audio, Display & HDR, and RTSS & Performance submenu row models,
  including independent staged resolution/refresh/scale selection and a single
  guarded Apply transaction.
- XFE's Quick Menu keyboard routing and navigation. Standalone intentionally
  keeps its distinct `Ctrl+Alt+Shift+P` Control Panel shortcut because
  `Ctrl+Alt+Shift+S` already opens Full Settings.
- Standalone notification-area and executable icon, tray recovery actions, and
  build-time icon embedding, plus the double-clickable Windows build launcher.
- XFE's *usable* notification-area icon, which required the standalone shell to
  survive a desktop restore. SteamShell now has a desktop mode: Explorer takes
  the desktop back while SteamShell stays resident for the tray icon, controller
  mouse, and Quick Menu. XFE gets this for free by never owning the shell;
  standalone had to add an explicit mode with a `TaskbarCreated` re-assert,
  because its own restore path restarts Explorer.
- Desktop-wide automatic mouse and its tray toggle remain standalone-only: they
  are keyed to that explicit Explorer-owned desktop mode. XFE never performs a
  SteamShell-to-Explorer presentation transition.
- Live RTSS global Overlay and Frame Limiter state/control through
  `RTSSHooks64.dll`, foreground-profile `FramerateLimit`, and automatic
  HotkeyHandler fallback.
- The **combined Frame Limit row** (Off · 30 · 40 · 60 · 90 · 120 · Custom), the
  conditional Custom FPS row with hold-to-repeat, and **Save Limit to Profile**.
  This one was *not* a port in either direction: it was designed once and applied
  to both trees in the same pass, so the behaviour is identical apart from the
  refresh model. XFE rebuilds its whole row list on every repaint, so the Custom
  row appears on its own; standalone composes rows separately and needs an
  explicit rebuild on the transition into and out of Custom.
- Live primary-display HDR state with explicit Off/On control and Win+Alt+B
  fallback when Advanced Color state is unavailable.
- Primary-display Windows Scale selection with the existing 15-second guarded
  rollback and delayed Quick Menu re-centering.
- Screen-coordinate cursor observation and selectable left/right parking edge.

## Already at parity or stronger in standalone

- Startup black/video presentation and startup-program window modes.
- Full Settings categories, controller shortcut recording, immediate Quick Menu
  settings writes, topmost dialog handling, and monitor-aware Settings sizing.
- Task Switcher one-shot selection, explicit Y focus lock, close/force-close
  behavior, and legacy/tool-window game handling.
- Audio output, volume, mute, display-mode safety revert, health checks,
  diagnostics, and controller mapping.

## Deliberately not ported

- RawInput/GameInput controller learning and device hand-over. Those solve Xbox
  FSE withholding background XInput; standalone owns the foreground and its
  established XInput path does not have that failure mode.

  **This rationale is now only half the story.** It answers the FSE question and
  nothing else, and a second reason to port has since appeared: a controller in
  DirectInput mode — measured on an 8BitDo Ultimate 2 — **is not an XInput device
  at all**, so standalone does not see a degraded controller, it sees nothing.
  XFE reads it today through RawInput plus a learned profile. Porting RawInput,
  the profile store, and the Learn Controller wizard is therefore an open
  decision rather than a closed one.

  If it is taken, standalone's `LT+RT+LB+RB+L3+R3` Settings chord **must** be
  ported to XFE's `LB+RB+L3+R3` at the same time. Non-XInput backends commonly
  report both triggers on one shared axis where they cancel out, which would make
  that chord physically unreachable — on the one controller the port exists for,
  and it is the only keyboardless route to Full Settings.
- XFE Game Focus Lite, Steam Assist Lite, and Launcher Cleanup Lite. Standalone
  already has the coordinated Window Engine and full Launcher Cleanup.
- XFE task-switcher activation rules and Steam-return workarounds. Standalone
  owns presentation and already has focus pinning and guarded legacy surfaces.
- Companion Disable/Enable. Pausing a utility companion is safe; pausing the
  standalone shell while it owns Explorer/taskbar state is not. Desktop mode is
  the standalone equivalent: it hands presentation back to Explorer through the
  guarded restore rather than pausing SteamShell in place, and it is reversible
  from the same tray menu.
- XFE startup-curtain semantics. Standalone's splash is part of its actual Steam
  startup lifecycle rather than a presentation-only companion curtain.

## Release boundary

The active tree is the locked **1.7.4** source with settings schema 14. Its
frozen release is `releases/1.7.4/`; `releases/1.7.3/` remains the deliberate
revert point immediately before the Quick Menu rendering rewrite.
The earlier `releases/1.7.2/`, `releases/1.7.1/`, `releases/1.7.0/`, `releases/1.6.0/`,
`releases/1.5.0/`, `releases/XFE-0.1.14/`, `releases/XFE-0.1.15/` and
`releases/XFE-0.1.16/` directories remain unchanged.

1.7.0 is the first release whose headline features have no XFE counterpart to
port from. Desktop mode and the desktop blackout exist because standalone
SteamShell owns the shell, which is precisely the thing XFE was built never to
do.

## `SteamShell-XFE/` is no longer only a reference

The rule at the top of this file — XFE is a source reference, standalone changes
belong in `SteamShell/` — **stopped holding in the working tree after 1.7.0**.
`SteamShell-XFE/SteamShell-XFE.ahk` now carries changes of its own:

- The combined Frame Limit row, Custom FPS, and Save Limit to Profile, designed
  jointly with standalone rather than ported either way.
- A bounds guard in `ControllerLearnSkip`. `ControllerLearnNextStep` increments
  unconditionally, so after the final step the index sits one past the end while
  the wizard saves — and Skip is a GUI button, clickable in that window. It threw
  `Invalid index: 23` on hardware.
- Motion-sensor exclusion in the learner's axis search, after an 8BitDo Ultimate 2
  put six free-running 16-bit motion axes into a 34-byte report and won every
  axis step.
- Removal of the handler cases and functions left dead by the row merge.
- Matching updates to `Validate-SteamShell-XFE.ps1`, whose RTSS parity assertions
  still described the removed `rtssLimiterState` row.

All of the above is locked at `releases/XFE-0.1.15/`. **0.1.16** adds the
RTSS frame-cap input work — the debounced write and hold-to-repeat — again
designed once and applied to both trees in the same pass, and is locked at
`releases/XFE-0.1.16/`. Earlier snapshots are untouched.

The shared Quick Menu renderer, closed-window teardown, recovery-layout fixes,
and complete driver-mode enumeration are locked at `releases/1.7.4/` and
`releases/XFE-0.1.17/`. Standalone 1.7.4 additionally contains desktop-wide
automatic mouse mode and its Explorer/Start/Search integration.

So the rule at the top of this file now reads: **XFE is a parallel tree, not a
reference.** Changes that belong to both — the Frame Limit row is the first —
are designed once and applied to both in the same pass, and each keeps its own
version and its own locked release.
