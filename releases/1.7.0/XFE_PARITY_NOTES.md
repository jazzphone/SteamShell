# SteamShell / XFE parity notes

This file records the July 2026 parity review. `SteamShell-XFE/` and its locked
release remain source references only; standalone changes belong in
`SteamShell/`.

## Ported to standalone SteamShell

- XFE's final borderless Quick Menu geometry, persistent window/control pool,
  filled selection rows, compact footer hints, keyboard navigation,
  redraw-suspended page composition, and reveal-before-measure/shape DPI fixes.
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
- Live RTSS global Overlay and Frame Limiter state/control through
  `RTSSHooks64.dll`, foreground-profile `FramerateLimit`, and automatic
  HotkeyHandler fallback.
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

The active tree is the locked `1.7.0` source with settings schema 10. Its frozen
checkpoint is `releases/1.7.0/`; the earlier `releases/1.5.0/`,
`releases/1.6.0/`, and `releases/XFE-0.1.14/` directories remain unchanged.

1.7.0 is the first release whose headline features have no XFE counterpart to
port from. Desktop mode and the desktop blackout exist because standalone
SteamShell owns the shell, which is precisely the thing XFE was built never to
do. `SteamShell-XFE/` remains a source reference only and is unchanged.
