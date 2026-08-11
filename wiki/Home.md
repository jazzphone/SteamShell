# SteamShell Wiki

SteamShell turns a Windows PC into a living-room console: it replaces the
Windows shell, launches Steam Big Picture, keeps the right window in front, and
puts everything you would otherwise need a keyboard for behind a controller-first
Quick Menu.

There are two products in this repository:

| | |
|---|---|
| **SteamShell** | The full shell. Replaces Explorer, launches Steam Big Picture, manages focus and windows. |
| **SteamShell XFE** | A companion for the Windows Xbox Full Screen Experience. Not a shell — Xbox FSE owns presentation; this adds the controller-first utilities on top. |

## Pages

- **[Quick Menu](Quick-Menu)** — the controller-first overlay, page by page
- **[Settings Editor](Settings-Editor)** — the desktop window, category by category
- **[Desktop & Tray](Desktop-and-Tray)** — what SteamShell looks like from the desktop side

## Two ways to reach everything

Every setting has a home in the desktop **Settings editor**. The ones worth
changing from the couch are mirrored into the **Quick Menu**, which draws over
Steam Big Picture and needs nothing but a controller.

Nothing in the Quick Menu is a shortcut to a dialog — values change in place with
Left/Right, and the row shows the current value while you are looking at it.

## Keyboard shortcuts

| Shortcut | Does |
|---|---|
| `Ctrl+Alt+Shift+Q` | Open the Quick Menu |
| `Ctrl+Alt+Shift+S` | Open the Settings editor |
| `Ctrl+Alt+Shift+P` | Open the Control Panel / diagnostics |
| `Ctrl+Alt+Shift+R` | Reload settings from the INI |
| `Ctrl+Alt+Shift+G` | Run Game Assist once |
| `Ctrl+Alt+Shift+I` | Re-arm controller input after a backend stall |
| `Ctrl+Alt+Shift+D` | Delete the learned controller profile for this device |
| `Ctrl+Alt+Shift+E` | Exit to the desktop (permanent restore) |

> Screenshots on these pages are from SteamShell 2.0.2.
