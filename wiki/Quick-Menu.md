# Quick Menu
The Quick Menu is SteamShell's controller-first surface. It draws over whatever
is in front — Steam Big Picture, a game, or the desktop — and closes back to it.

**Controls:** D-pad moves · **A** selects · **B** goes back · **Left/Right**
adjusts a value without leaving the row · **Delete** closes the selected window
on the Task Switcher page · **Home/End** jump to the first and last row.

Every row shows its live value on the right, so the menu is a status readout as
much as a control panel.

## Quick Menu main page

The top level. Every row shows its current value on the right, so the menu doubles as a status readout — you can see the active audio device, resolution, refresh rate, scale and RTSS state without selecting anything.

![Quick Menu main page over Steam Big Picture](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/quickmenu-main.png)

## Audio

Output device, volume and mute. Left/Right cycles the output device in place; there is no separate dialog to get lost in.

![Quick Menu Audio page showing Output, Volume and Mute](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/quickmenu-audio.png)

## Display & HDR

HDR, resolution, refresh rate and scale, read live from Windows DisplayConfig. **Apply** commits the selection and shows CURRENT when what is on screen already matches.

![Quick Menu Display and HDR page showing HDR off, 3840x2160, 60 Hz, 300 percent scale](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/quickmenu-display-hdr.png)

## RTSS & Performance

Overlay on/off and the frame limit, driven through RivaTuner Statistics Server. **Save Limit To Profile** writes the cap to the foreground game's own RTSS profile — the status text tells you what it would target right now.

![Quick Menu RTSS and Performance page showing Overlay on and a 158 FPS preset frame limit](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/quickmenu-rtss-performance.png)

## Current App

Per-application actions for whatever was in front when the menu opened: add it to automatic mouse mode, keep it always in focus, protect it from Launcher Cleanup, or exclude it from desktop mouse mode.

![Quick Menu Current App page showing Automatic Mouse, Always In Focus, Protect From Cleanup and Exclude From Desktop Mouse](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/quickmenu-current-app.png)

## System

Exit Steam to the desktop, see what the window engine currently scores as a game, close SteamShell, or sleep, restart and shut down the machine.

![Quick Menu System page showing Exit Steam To Desktop, Game Detection, Current Application, Exit SteamShell, Sleep, Restart PC and Shut Down](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/quickmenu-system.png)

## Settings submenu

The settings a controller can reach without a keyboard, grouped the same way the desktop editor is. **Open Full Settings Editor** hands off to the desktop window when you need a key that is not here.

![Quick Menu Settings submenu listing General, Controller, Focus, RTSS, Windows Settings and Open Full Settings Editor](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/quickmenu-settings.png)

## Settings → General & Startup

Startup splash, taskbar hiding and the black desktop background. Rows that only take effect on the next boot say so rather than pretending to apply now.

![Quick Menu General and Startup page showing Startup Splash, Hide Taskbar In Shell, Black Desktop Background and Quick Menu Accent](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/quickmenu-settings-general-startup.png)

## Settings → Controller & Cursor

Controller mouse mode and speed, cursor auto-hide and delay, and where the pointer parks when it gets out of the way.

![Quick Menu Controller and Cursor page showing Controller Mouse, speed, Auto-Hide Cursor, hide delay and mouse parking](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/quickmenu-settings-controller-cursor.png)

## Settings → Focus & Windows

The shell half: Steam refocus, Game Foreground Assist, AlwaysFocus and the coordinated window engine, with the live state of the current focus-assistance session.

![Quick Menu Focus and Windows page showing Steam Refocus, Game Foreground Assist, AlwaysFocus Support and Window Management](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/quickmenu-settings-focus-windows.png)

## Settings → RTSS & Performance

Whether RTSS integration is on, how the overlay and limiter controls are bound, and the preset frame cap the Quick Menu offers.

![Quick Menu RTSS and Performance settings page showing RTSS Integration, Overlay Controls, Frame Limiter Controls and Preset Frame Cap](https://raw.githubusercontent.com/jazzphone/SteamShell/main/SteamShell/images/quickmenu-settings-rtss-performance.png)
