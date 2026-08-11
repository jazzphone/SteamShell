# Desktop & Tray

SteamShell keeps a notification-area icon whenever it is running, including while
it is acting as the Windows shell. It is the escape hatch: everything below is
reachable with a keyboard and mouse alone, with no controller involved.

## Tray menu

![SteamShell tray menu open on the Windows desktop](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/tray-menu-desktop.png)

| Item | Does |
|---|---|
| **Open Quick Menu** | Same overlay the controller chord opens |
| **Open Settings** | The full desktop Settings editor |
| **Open Diagnostics** | Status, live log and the Health Check |
| **Learn Controller…** | Teach SteamShell a pad that XInput cannot describe |
| **Delete Learned Profile** | Undo the above for the attached device |
| **Automatic Mouse Throughout Desktop** | Toggle desktop-wide automatic mouse mode |
| **Return to SteamShell** | Go back to the shell after exiting to the desktop |
| **Reload Settings** | Re-read the INI without restarting |
| **Exit SteamShell** | Close the shell and restore the desktop |

### Why the controller learner is here

A learned profile that came out wrong does not merely fail to help — it reads as
a stick held over, so the pointer runs off and Settings becomes hard to reach
with the very device the profile broke.

So the learner and its undo are both in the tray, which needs only a keyboard.
The same two items sit in the Settings window and on `Ctrl+Alt+Shift+D`; the
point is that none of the routes to them requires a working controller.
