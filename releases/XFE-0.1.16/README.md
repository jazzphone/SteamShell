# SteamShell XFE Companion

SteamShell XFE is a portable controller-utility companion for Windows Xbox Full
Screen Experience. It is a separate application from SteamShell 1.5.0 and does
not replace, install, or modify the Windows shell.

The current release is **0.1.16**, locked as a reproducible source snapshot in
`releases/XFE-0.1.16`. Controller input, the Quick Menu, Settings,
display/HDR controls, RTSS integration, and notification-area control work inside
Xbox FSE. The companion remains deliberately separate from the stable SteamShell
1.5 Windows-shell application.

## Controller input backend

Xbox FSE withholds controller input from background processes. Inside FSE both
XInput and GameInput report **all-zero** state — measured returning
byte-identical values, because on Windows 11 they share the same underlying
gaming-input stack, so choosing between them changes nothing.

**RawInput** reads the HID reports underneath that stack. Registered with
`RIDEV_INPUTSINK`, it receives the complete gamepad state inside FSE, including
the View, Menu, L3 and R3 buttons XInput never sees there. RawInput is in turn
silent outside FSE, so neither source works everywhere on its own.

| `Backend` | Behavior |
|---|---|
| `auto` | **Default, and what you want.** RawInput while HID reports arrive, XInput otherwise — this means RawInput is used *everywhere* it works, not only inside FSE. |
| `rawinput` | RawInput only, **no fallback**. Diagnostic: use it to prove something is genuinely RawInput. Input will be dead wherever RawInput is silent. |
| `xinput` | XInput only. Works on the desktop, reads zeros inside FSE. |
| `gameinput` | Diagnostic only. Measured byte-identical to XInput; kept as a documented negative result. |

Every backend decodes into the same gamepad state, so mappings, the Quick Menu
and the controller mouse behave identically whichever is active.

**To tell which backend is actually carrying input, read this line:**

```text
Controller input [rawinput]: buttons=0x0340, LT=0, RT=0.
```

The `RawInput probe: N WM_INPUT message(s)` lines do **not** answer that question —
the probe logs messages as they arrive regardless of which backend consumes them,
so a log full of them proves only that reports exist. `Controller backend is now
...` records each switch, and the backend legitimately alternates when one source
goes quiet.

### RawInput limitations

- **The ROG Ally triggers share one combined axis.** LT and RT read individually
  but cancel out when held together, so no chord may require both on that
  controller. Learned profiles support either shared or independent triggers.
- **RawInput requires a HID gamepad collection.** XInput-only/XUSB controllers
  commonly expose no usable HID reports, so there is nothing the learner can
  record inside Xbox FSE.
- **The learner maps byte-aligned reports empirically.** It supports active-high
  and active-low button bits, hats or four-bit D-pads, 8-bit axes, 16-bit
  little- or big-endian axes, and measured axis travel. A device with packed
  sub-byte axes, changing report formats, or several modes may still require a
  hand-written profile or future HID-descriptor parsing.
- **Motion sensors are excluded from axis detection.** A gyro/accelerometer pad
  streams continuously whatever the user does, so its bytes out-travel the real
  stick on every step and used to win the axis search outright. Bytes that were
  still moving while nothing was held are therefore not offered as axis
  candidates. See *Motion sensors* below.

### Controller compatibility — read this before assuming it is general

The built-in fallback remains specific to the ROG Ally controller. Its byte
layout was read off hardware:

```
1-2 LX  3-4 LY  5-6 RX  7-8 RY   16-bit LE, 0x8000 centre
9-10    combined trigger axis    0x8000 neutral, above = LT, below = RT
11      A B X Y LB RB View Menu  bits 0..7
12      L3 R3 Guide              bits 0..2
13      D-pad hat, 1..8 clockwise
```

For any other HID gamepad, open **Settings → Controller & Cursor → Learn
Controller**. The wizard selects the pad that is actually operated, measures a
neutral baseline, prompts for each button/D-pad direction/axis, and writes a
profile beside the main settings file:

```text
SteamShell-XFE-Controllers.ini
```

Profiles are keyed by USB VID/PID plus interface and collection where available,
so they survive RawInput handle changes, reconnects, and sleep/resume. A learned
profile is tried before the Ally fallback and is accepted only when its saved
report length and every field boundary are valid. Saving refreshes the decoder
cache immediately; it does not restart the companion or discard other Settings
work.

The generated INI is intentionally inspectable. `Buttons` entries are
`name:byte:mask:pressedValue`; `Axes` entries are
`name:byte:u8|u16le|u16be:neutral:direction:measuredExtent`; and `Hat` stores the
byte, hat-bit mask, released value, and eight clockwise direction values. The
mask lets a hat share a byte with face buttons. Older three-field button,
unmasked hat, and five-field axis entries remain readable with
active-high/whole-byte/full-range defaults.

| Controller | Desktop | Inside Xbox FSE |
|---|---|---|
| ROG Ally built-in | Works | **Works** (measured) |
| 8BitDo Ultimate 2 in DInput mode | **Works** (measured) — learned, 34-byte report | **Learn it once**, then RawInput decodes its saved profile |
| Other byte-aligned HID gamepad (DualShock, Switch Pro, 8BitDo in DInput) | Works via XInput | **Learn it once**, then RawInput can decode its saved profile |
| Xbox Wireless Controller / XInput-only pads | Works via XInput | **Dead** — XUSB typically publishes no HID gamepad collection at all, so RawInput never sees it |

A pad in **DirectInput mode is an ordinary HID gamepad**, which is why it needs
no separate DirectInput backend: RawInput registers for both the HID Gamepad and
Joystick usages, so it already receives those reports. Adding `dinput8` would be
a second, weaker path to the same bytes — one with no per-device profiles, a
combined trigger axis, and no Guide button.

Until a profile exists, rejection is logged per device rather than failing
silently:

```
RawInput: ignoring 64-byte reports from device 0x... (...).
The built-in layout only understands 16-byte reports (the ROG Ally controller).
Use Settings -> Controller & Cursor -> Learn Controller to teach this one.
```

**The controller is inert while the wizard is open.** It has to be: the wizard
only diverts the RawInput path, so otherwise the poll loop keeps reading the same
pad through XInput and firing its normal mappings at every prompt — B is Escape,
which closed the wizard; A is Enter; X opens the touch keyboard and Y the Game Bar.
Because of that, **Skip, Start Over, Save and Cancel need the mouse or the
touchscreen**, and any digital step whose control never appears times out and skips
itself rather than stranding the wizard.

The wizard opens with an **analogue scan**: roll both sticks around and sweep both
triggers once, and every byte that behaves like an axis is recorded and then
ignored by all the button steps. Without it, a stick that moves during a button
step is read as the button — at rest an axis low byte is `0x00`, so a nudge sets
bits that were clear at rest, which is precisely the test a button has to pass. It
is worst on **L3 and R3**, which cannot be pressed without touching the stick. A
byte counts as analogue only if it takes many distinct values *across* a wide
range, so a two-state button byte and a monotonic counter both fail the test.

Each prompt is **press and release** — the wizard detects the control on press and
then waits for it to be let go before moving on. That gate matters: without it, a
still-held button satisfies the next step's "a bit that differs from rest" test and
gets learned as that button's bit.

The four **D-pad** directions are validated as a set once all four are in, because
they only mean anything together. A press that is even slightly diagonal reads as
the diagonal hat value rather than the cardinal — which breaks the even spacing a
hat needs *and* collides in the bit fallback, so one imprecise press quietly ruins
the whole D-pad. If the set describes neither a hat nor four distinct bits, the
wizard says so and asks for the four directions once more.

Every step shows how many reports it has seen. A step that appears stuck is either
receiving nothing (wrong backend, or running outside FSE) or receiving reports and
rejecting them, and the count is what distinguishes them. Steps marked optional —
the Guide button, which Windows usually swallows — give up sooner so they cannot
block the steps behind them.

If Windows will not identify the device — measured on the ROG Ally X, where the
device path, HID VID/PID and preparsed descriptor all came back empty — the
profile is saved keyed on **report length** (`LEN_16`) instead, and marked
`IdentityFallback=length`. That is exactly what the built-in layout matches on, so
it is no less safe; it is just less specific. The log records what each identity
route returned, which is the only way to find out why the metadata is withheld.

The wizard is deliberately additive: cancelling it or having no valid profile
does not alter the known Ally decoder or the normal XInput fallback.

Two physical constraints keep the axis search honest, both added after a learned
profile sent the pointer across the screen:

- **Multi-byte fields are little-endian.** USB HID specifies it, so the learner
  never guesses big-endian. Offering it doubled the search space for something
  that does not exist, and produced an RX axis reading about -10700 with the stick
  untouched. (The decoder still *understands* `u16be`, for hand-written profiles.)
- **A self-centring stick rests at the centre of its range.** Measured on
  hardware, all four sticks and the shared trigger sat between 47.6% and 50.4% of
  full scale at rest. A candidate resting outside 35–65% is the wrong field —
  usually a neighbouring axis's bytes — and is rejected with the reason logged.

A stick also cannot reuse bytes another stick already claimed. Without that, the
four stick steps were resolved independently and once produced LX=1, LY=2, RX=4,
RY=3 — overlapping fields that cannot describe any real report. Triggers are
exempt, because a shared trigger axis is a real layout.

#### Motion sensors

A gyro/accelerometer pad breaks a search built on travel, because its axes never
stop travelling. Measured on an **8BitDo Ultimate 2** in DInput mode: a 34-byte
report at roughly 1 kHz, of which **12 bytes were still moving with the
controller untouched** — six 16-bit motion axes. Those bytes sweep their full
range continuously, so they beat the real stick on every step:

```text
Learn: rest sampled from 1822 reports; 12 of 34 bytes changed during rest.
Learn: LX not detected -- byte 22 u8 rests at 0% of range, and a stick rests at the centre.
Learn: RT = byte 22 u16le neutral 62720 direction -1
```

All four sticks were saved by the rest-at-centre rule above. **RT was not** — a
trigger legitimately rests at an end of its range, so it had no equivalent check
and bound itself to a motion byte.

The fix is a filter, not a new rule about sticks: a byte that was still changing
across **four or more of its bits** while nothing was held is free-running and is
withheld from the axis search. A stick resting at centre jitters in its lowest
one or two bits; a motion axis saturates the byte. If that filter leaves no
candidate at all, the search is retried once with those bytes allowed back in and
the retry is logged, so a controller whose sticks genuinely jitter widely stays
learnable.

**After saving, the profile is checked against the controller at rest.** A
mis-learned axis reads as permanently deflected, which sends the pointer across
the screen — and that also takes away the pointer you would need to undo it. If
any axis is pegged with nothing touched, the wizard says which, and offers to
delete the profile. `Ctrl+Alt+Shift+D` does the same thing without the pointer,
as does **Settings → Controller & Cursor → Delete Learned Profile**. Deleting
restores the built-in layout.

Digital controls are learned from their single clean state-change report. This
matters on the Ally and other devices that send one report when a button or
D-pad direction changes, then remain silent while it is held; duplicate held
reports are not required.

Sticks and triggers are learned as an outward-and-release gesture. Move or
squeeze to the prompted extreme, then let the control return to rest. The
wizard records the outward peak and advances on the neutral report, so a held
axis cannot carry into the next prompt.

### Sleep and resume

`RAWINPUTHEADER.hDevice` handles are **not stable for the life of the process**.
Windows re-enumerates HID devices across a suspend, and the same controller comes
back with a *different* handle. A decoder that locks onto a handle permanently
then rejects every report the controller sends after a wake — silently, because
discarding a report from another device is normal behaviour.

Three layers recover from this:

1. **Device hand-over.** If the locked device has been quiet for more than a
   second and a different one is producing correctly shaped reports, the decoder
   adopts it. This needs no notification from Windows and is the layer that
   actually does the work. A device that is *actively* reporting is never
   displaced, which is what keeps a headset or remote out of the decoder.
2. **`WM_POWERBROADCAST`.** On resume the lock is released and the registration
   re-asserted, in case registration itself was lost — the one failure hand-over
   cannot fix, since there is no report to adopt.
3. **Heartbeat gap.** A heartbeat arriving far later than scheduled means the
   machine slept. This matters because **modern standby does not reliably deliver
   the power broadcast**, and modern standby is what a ROG Ally sleeps into, so
   layer 2 cannot be the only trigger.

XInput needs none of this: `XInputResolveController` rescans all four slots and
re-resolves on its own. That is why, before this was fixed, the desktop kept
working after a wake while Xbox FSE did not — `auto` was quietly falling back to
XInput, and RawInput stayed dead.

**Manual recovery:** `Ctrl+Alt+Shift+I` or **Settings → Advanced → Re-arm
Controller**. Both release the lock, re-register RawInput, and force XInput to
rescan its slots.

## Elevation — deliberately not used

The companion runs at **normal privileges**, and the optional logon task never
requests elevation. This was tested on hardware and rejected:

> While an elevated window of ours holds the foreground, Steam cannot inspect it,
> so Steam never registers that it lost focus and keeps acting on controller
> input underneath the Quick Menu. Both respond to the same press — and an A
> press can activate something in Steam while Sleep or Shutdown is being chosen.

**The accepted cost:** at normal privileges the companion cannot send input to,
activate, or close windows owned by elevated applications. Controller mappings
will silently do nothing while an elevated anti-cheat game is in front. If a
mapping ever "stops working" in one specific game, check this first.

The companion never relaunches itself elevated — that would raise a UAC prompt
on every boot, since a non-elevated parent starts it.

## Windows are always-on-top, and what that costs

Every window here is `+AlwaysOnTop`. Not for prominence — it is the only thing
that makes a window appear over Xbox FSE at all. FSE is a fullscreen window, so a
window can hold the foreground and still render behind it; no amount of retrying
`SetForegroundWindow` changes z-order.

That has one consequence worth knowing, because it looks like a freeze. A
**non-topmost dialog cannot rise above a topmost window even when that window is
its own owner.** A plain `MsgBox` or file picker therefore opens *behind* the
Settings window while holding the focus and the keyboard.

So dialogs are made topmost too, rather than the owner being made not-topmost:

- `MsgBox` gets `MB_SYSTEMMODAL` (4096), whose real effect is to make it topmost.
- `FileSelect` has no such option, so the dialog is promoted after it appears, by
  a timer that keeps running because the common file dialog pumps messages while
  it blocks.

**Dropping the owner's topmost bit is the wrong fix** — inside FSE that puts the
owner behind FSE and takes the dialog down with it. The build validator forbids
bare `MsgBox` and `FileSelect` calls for this reason.

## Controls

| Chord | Action |
|---|---|
| Hold **L3 + R3** | Quick Menu |
| Hold **LB + RB + L3 + R3** | Settings |
| Hold **View** + button | Mapped actions |

The Settings chord does not involve the triggers, because RawInput cannot report
both at once. The older six-button press still satisfies it, since the triggers
are ignored rather than forbidden.

### Keyboard

| Hotkey | Action |
|---|---|
| `Ctrl+Alt+Shift+Q` | Quick Menu |
| `Ctrl+Alt+Shift+S` | Settings |
| `Ctrl+Alt+Shift+P` | Settings (matches SteamShell 1.5's Control Panel shortcut) |
| `Ctrl+Alt+Shift+R` | Reload INI |
| `Ctrl+Alt+Shift+I` | Re-arm controller input (recovery after sleep) |
| `Ctrl+Alt+Shift+D` | Delete the learned controller profile (recovery from a bad one) |
| `Ctrl+Alt+Shift+X` | Exit companion |

While the Quick Menu is focused: **arrows** navigate, **Left/Right** adjust,
**Enter/Space** select, **Backspace/Escape** go back, **Delete** closes the
selected window, **Home/End** jump to first/last. The menu is fully usable
without a controller, which is the recovery path if controller input regresses.

## Steam actions

Steam's menu bindings only reach Steam while Steam owns the foreground; the
in-game equivalent is the overlay. The foreground process is sampled before
acting and the appropriate shortcut sent.

| Quick Menu row | Steam in front | Game in front |
|---|---|---|
| Steam Menu | `MenuShortcut` (`Ctrl+1`) | `OverlayShortcut` (`Shift+Tab`) |
| Steam Quick Access | `QuickAccessShortcut` (`Ctrl+2`) | `QuickAccessShortcut` |

The **View button** carries the same actions, resolved on release:

| | Tap | Hold |
|---|---|---|
| Steam in front | Steam Menu | Steam Quick Access |
| Game in front | *nothing* | Steam overlay |

A tap in-game does nothing on purpose: the companion never blocks input, so the
game receives View normally.

**Tap and hold are switched independently**, because they misfire differently.
The hold is the one a game can trigger by accident — View is often a scoreboard
or map button — while the tap only ever acts with Steam in front. Turn off
whichever gets in the way and keep the other.

| Setting | Effect |
|---|---|
| `EnableViewButtonActions` | Master switch for both |
| `EnableViewTapAction` | Tap → Steam Menu |
| `EnableViewHoldAction` | Hold → Quick Access, or the overlay in a game |

Disabling the hold does **not** make a long press fall through to the tap
action; a long press stays a long press and simply does nothing.

All three are in **Settings → Steam**, and in the Quick Menu under **Settings**.

View is also the modifier for every controller mapping, so its own action fires
only when nothing else was touched during the hold — any other button, a
trigger, or either stick cancels it. The hold threshold is **500 ms with Steam
in front** and **1000 ms in a game**, because View is commonly a scoreboard or
map button that players hold deliberately.

Configure these in the `[Steam]` INI section. The shortcuts must match the
bindings configured inside Steam itself. In-game overlay shortcuts use a held
`SendEvent` chord rather than the near-instant `SendInput` used for ordinary
desktop shortcuts, because Steam's game hook can miss an instantaneous
Shift+Tab pulse. The log records the foreground executable at the exact overlay
send moment.

## Quick Menu

Rounded, always-on-top, centred on the monitor holding the foreground app.
Selection is a filled row with an accent-coloured value. The bottom line shows
the button hint, replaced by transient status messages when something happens.

Pages: **Audio**, **Display & HDR**, **RTSS & Performance**, **Steam Menu**,
**Steam Quick Access**, **Controller Layout**, **Task Switcher**, **Game Bar**,
**Settings**, **System**.

**Settings** is a page of switches rather than a shortcut to the Settings
window, so the things worth changing mid-session can be changed from the couch:
the three assist features, the FSE-switcher pause, and the three View button
actions, plus the next-launch startup splash switch. **A** or **Left/Right**
flips a row. Each toggle writes the INI immediately with no save step. The live
feature toggles apply at once; the explicitly labelled splash switch applies on
the next launch. The Settings window is still one row away at the bottom.

**System** is intentionally limited to Sleep, Restart, Shut Down, and Exit.
Health Check, Probe Screen, and controller re-arm remain in **Settings →
Advanced**; re-arm also remains available through `Ctrl+Alt+Shift+I`.

The value column is right-aligned, so overlong text is clipped from the left.
Anything that must stay readable is placed last — the Audio row shows the output
device first and the volume percentage last, so a long device name loses its
start rather than the volume being cut off.

**Display & HDR** picks resolution, refresh rate, and Windows display scale as
three independent Left/Right rows rather than a paged list of combinations.
Cycling changes nothing until **Apply** is selected, which applies all three as
one primary-display transaction and then runs the 15-second timed revert with a
countdown. Selecting Apply again keeps the complete transaction.
After an apply or automatic revert, the open Quick Menu reruns its measured
layout and centring pass once Windows has settled on the new scale; it stays on
the Display & HDR page with Apply selected for confirmation.

Scale offers only the percentages Windows reports for the primary display. The
underlying DisplayConfig DPI packet is used by current Windows versions but is
not published in the Windows SDK; if Windows or the display driver rejects that
packet, the row honestly shows **Unavailable** while resolution, refresh rate,
and HDR remain usable.

**HDR** reads the primary display's Windows Advanced Color state rather than
assuming what the Win+Alt+B shortcut did. The row shows **On** or **Off**; A
toggles the known state, while Left explicitly turns HDR off and Right turns it
on. A non-HDR display shows **Unsupported**, and an unreadable driver/API state
shows **Unavailable** without sending a blind toggle.

**RTSS & Performance** reads RTSS's global Overlay and Frame Limiter state from
`RTSSHooks64.dll` when RTSS is running. **Overlay** shows **On** or **Off**; A
toggles it, Left explicitly turns it off, and Right turns it on.

**Frame Limit** is a single row covering both of RTSS's mechanisms, because two
rows that can each mean "no limiting" only fight each other:

| RTSS mechanism | Scope | What it is |
|---|---|---|
| Limiter flag (bit `0x4` = disabled) | Global | The master on/off |
| `FramerateLimit` | Per profile | The target, `0` = uncapped |

Left/Right cycles **Off · 30 · 40 · 60 · 90 · 120 · Custom**. Choosing `Custom`
reveals a **Custom FPS** row beneath it; Left/Right there steps the value, and
consecutive presses escalate the step 1 → 5 → 10 so 60 → 120 is about ten
presses rather than sixty. Quick Menu navigation is edge-triggered with no
auto-repeat, which is why the escalation exists.

**"Off" maps to the flag, never to the value.** Writing `0` would discard the
number, so an off/on round trip would silently forget 72 and come back uncapped.
Clearing the flag leaves 72 in the profile, and cycling back on restores it
rather than jumping to the first preset.

Every write targets the **global** profile. Per-game profiles are the user's own
tuning, and a menu that writes whichever profile happens to be in the foreground
is a menu that can silently change a game's configuration.

**Save Limit to Profile** is the one exception, and it is explicit. It copies the
current global cap into the foreground executable's own RTSS profile, showing
that executable's name in the value column — taken from what owned the screen
*before* the menu opened, since asking afterwards always answers SteamShell XFE.
Steam's own surfaces are excluded, because a profile named `steam.exe` caps the
client rather than a game. The write is surgical: the target profile is loaded
first so any other tuning for that game survives, and only `FramerateLimit` is
replaced. It requires the two-press confirmation, and RTSS then applies that
profile automatically every time the game runs.

Writing needs the `SetProfileProperty`, `SaveProfile` and `UpdateProfiles`
exports. They are treated as optional: an RTSS build without them keeps Overlay
and limiter control and shows the cap **read-only** rather than failing outright.

“Limiter On” means RTSS's global limiter-disable switch is clear. The displayed
profile cap must also be non-zero before that application is actually limited.
If the configured RTSS installation does not expose the required interface, the
existing separate/toggle hotkeys and configured SteamShell FPS preset label
remain available as an automatic compatibility fallback, and the menu labels
the live state unavailable. RTSS commonly runs elevated; Windows may allow state
reads while blocking changes or the UI-refresh notification from this
standard-user companion. The menu verifies every direct change and reports a
warning instead of claiming success when RTSS does not accept it.

When integration is enabled and the configured executable exists but RTSS is
not running, this page shows **Start RTSS**. It launches the configured
`RTSS.exe` minimized, waits for the process, and then rebuilds the page into the
live state controls. A missing executable or failed launch remains visible as a
warning so it can be diagnosed without leaving the couch interface.

On the main Quick Menu, **RTSS & Performance** provides the glanceable summary
**Overlay On | Limiter On** (with each live state substituted). Inside the RTSS
page, the **RTSS Settings** row reports only availability—**Running** when its
process is active—because Overlay and Frame Limit already have dedicated rows
there.
Selecting it opens SteamShell XFE Settings directly on **RTSS & Performance**.

That Settings page explains that SteamShell derives `RTSSHooks64.dll` from the
directory containing the configured `RTSS.exe`. **Use RTSSHooks64.dll for live
state and direct control** is enabled by default. Clear it to force shortcut
mode: SteamShell will not load or call the DLL, will use the configured
separate/toggle shortcuts, and will display the configured FPS cap label instead
of querying RTSS profiles.

**Task Switcher** lists switchable windows: **A** switches, **X** closes,
**X again within 5 s** force-closes. Activation is a single one-shot request —
there is no focus pinning, so Xbox FSE keeps control of presentation. Generic
tool windows remain excluded, but Steam and steamwebhelper are deliberately
retained: current Steam Big Picture builds can mark their visible fullscreen
window as a tool window even though it is the application the user needs to
switch back to.

## Notification-area control

SteamShell XFE has its own charcoal/cyan controller-shell icon in the Windows
notification area. Windows may initially place it in the overflow panel; pin it
from Windows if it should always remain beside the clock. Right-clicking offers:

- **Open Quick Menu**
- **Open Settings**
- **Disable** / **Enable**
- **Exit**

Disable is session-only and leaves the tray menu available for recovery. It
pauses controller polling, assist and cursor timers, diagnostics, startup
launches that have not fired yet, RawInput processing, and the companion's
global hotkeys. It closes an open Quick Menu, shows the system cursor, releases
injected mouse/modifier buttons, and changes the tray action to **Enable**.
Settings remains available from the tray. Enabling starts the configured timers
again and re-arms RawInput without firing stale controller-release actions.

The source-mode tray loads `assets\SteamShell-XFE.ico`. The build script embeds
the same multi-resolution icon in the compiled executable automatically.

## Assist features (optional, all off by default)

Ported from SteamShell 1.5's window engine **without its geometry layer**.
Nothing here resizes, centres, maximises or restores a window.

| Feature | What it does |
|---|---|
| **Game Focus Lite** | Returns a game to the foreground if something steals it |
| **Steam Assist Lite** | Returns to Steam when no game is running |
| **Launcher Cleanup Lite** | Closes launchers once nothing is playing |

Launcher Cleanup keeps 1.5's safety guards — `RequireNoGame`, a CPU threshold, a
settle timer and a cooldown. Those guards are why it is safe to run
automatically; they depend on the game detection this port brings across.

**Assistance suspends entirely while any SteamShell XFE window owns the
foreground**, so it can never fight the Quick Menu, Settings, the mapping
editor, a shortcut capture, a file picker or a message box. Focus is never taken
from Xbox FSE surfaces or the Windows shell.

### Shell overlays and the FSE task switcher

Assistance also pauses while a **shell overlay** is on screen — the Xbox FSE
task/application switcher in particular. This needs its own check because the
foreground test above cannot catch it: an overlay can be drawn on top without
ever taking the foreground, so the foreground still reads as Steam or the game,
and Steam Assist Lite dutifully "returns to Steam" — dismissing the switcher the
instant it appears.

**Measured 2026-07-25:** the Xbox FSE task switcher is an **`explorer.exe`
window of class `XamlExplorerHostIslandWindow`**, and it *does* own the
foreground while open.

It is matched by **class**, not by process. An `explorer.exe` entry would also
match the desktop, the taskbar and every File Explorer window, and would pause
assistance far more often than intended. Prefer `class:` entries; use a bare exe
name only when you mean every window that process owns.

Detection runs in two passes:

1. **The foreground window, inspected directly.** This is the pass that catches
   the switcher. It cannot come from the window inventory — XAML island hosts
   are *tool windows*, and the inventory drops tool windows on purpose, so with
   the switcher filling the screen the inventory contains exactly one window:
   Steam. A foreground match needs no size test; owning the foreground while
   matching a listed class is specific enough.
2. **Topmost windows in the inventory**, for overlays drawn on top without
   taking the foreground. Here the window must also cover most of its monitor,
   so an ordinary background window cannot suspend assistance indefinitely.

> If some other surface still steals focus, **Settings → Advanced → Probe
> Screen** identifies it in about ten seconds: it counts down six, then logs
> every top-level window with process, class, size, topmost/foreground state,
> and — for the ones the inventory filters out — the reason. Add what it names
> to `ShellOverlayProcesses`. Settings hides itself while the probe runs.

The probe only reads. It never activates, closes, or resizes anything, and the
validator enforces that.

The assist timer only exists when a feature is enabled, so a default install
does no extra polling at all.

> **Enable Steam Assist Lite last and by itself.** If AnyFSE already returns to
> the Home app when a game exits, the two can duplicate or fight each other.

## Cursor parking

A mouse pointer has no place on a TV. The companion hides it after inactivity
and *parks* it out of the way — at startup, whenever a game/fullscreen-style
window enters the foreground, and whenever the foreground returns to Steam.
Game-entry parking is enabled by default so a newly launched game cannot leave
the pointer sitting in the middle of the picture.

Windows does not provide a universal “is this a game?” flag. XFE therefore uses
the same conservative geometry test as its Assist engine: the window must cover
most of its monitor and must not be Steam, a configured launcher, or a known
Windows/Xbox shell surface. The delayed action verifies that the same window is
still foreground before moving the pointer.

Parking puts it hard against one vertical edge, two pixels in, at `ParkYPercent`
down that edge. `ParkEdge` chooses which: **right** by default, because that is
where a cursor which briefly reappears is least noticeable on a TV, and because
Xbox FSE and Steam both keep their navigation on the left. With the default
`ParkYPercent=0.50` that is centre-right.

The two-pixel inset is deliberate rather than sitting exactly on the edge: some
surfaces read a pointer at the boundary as having left the window entirely and
drop their hover state.

Both are on the **Controller & Cursor** page.

## Startup splash

The optional startup curtain, managed in **Settings → Startup Splash**, covers
the primary display while SteamShell XFE starts. It has two modes:

- **Black** shows an opaque black curtain for `DurationMs`.
- **Video** launches the selected clip fullscreen through `mpv.exe`. It can play
  to completion or use the same fixed duration as the black curtain.

The black curtain is created before MPV starts and remains until MPV has a
visible fullscreen window, preventing the desktop or Xbox FSE from flashing
through. When the video ends, XFE puts the black curtain back before closing MPV,
then fades it away. `SafetyMaxMs` prevents a stuck MPV process or damaged video
from covering the display indefinitely.

Video mode requires both `VideoPath` and `MpvPath`. If either is missing or
cannot be launched, XFE logs the reason and safely falls back to the black
curtain. **Force MPV to SDR** is enabled by default so a startup clip does not
make a television switch HDR modes. The splash is off by default and changes
take effect on the next companion launch.

Its master switch is also available from **Quick Menu → Settings** as
**Startup splash (next launch)**, so it can be changed from the couch after the
paths and mode have been configured once.

This is presentation only: unlike SteamShell 1.5, XFE does not use the curtain
to gate Steam, launch the shell, or control Xbox FSE.

## Startup programs

Launches a list of applications shortly after the companion starts, with a
configurable initial delay and a stagger between launches. Programs already
running are skipped. Managed in **Settings → Startup Programs**.

`LaunchDeElevated` (on by default) starts each program through the shell when
the companion is elevated, so it receives the ordinary user token — an elevated
Steam would otherwise pass elevation to every game it launches.

**Launch window mode** (`WindowMode`) — `Normal`, `Minimized` or `Hidden`,
ported from SteamShell 1.5. `Hidden` is for background helpers (overlays,
controller daemons, sync agents) that have no business drawing a window over
Xbox FSE.

The mode is enforced for a few seconds after launch rather than only being
passed to `Run`, for two reasons. An application with a splash screen, or one
that recreates its main window while initialising, shows a window the initial
show state never applied to. And with `LaunchDeElevated` on, the program is
started by `explorer.exe`, which chooses the show state itself — so the initial
argument never reaches the child at all, and the sweep is the only thing that
works. It matches windows by process name, because on that route the PID `Run`
returns belongs to explorer.

Enforcement stops after a few seconds on purpose: a permanent sweep would
re-hide the program the moment you deliberately opened it later.

## Recommended AnyFSE configuration

1. Select AnyFSE's built-in **Steam Big Picture** launcher.
2. Add `SteamShell-XFE.exe` as an AnyFSE startup application.
3. Turn **Exit FSE when Home app exits** off.
4. Do not select SteamShell XFE itself as the custom Home app.

Alternatively, use **Settings → Advanced → Create Logon Task** to register a
Scheduled Task that starts the companion at logon, and remove it from AnyFSE's
startup applications so it is not started twice. The task runs at normal
privileges; see the elevation section above.

The task is registered from an XML definition rather than the shorter
`schtasks /sc onlogon` form, because that form inherits Task Scheduler's
defaults — and those include **"start the task only if the computer is on AC
power"**. On a handheld running on battery the task registers cleanly, looks
healthy in the Task Scheduler UI, and never starts. The registered task
therefore sets, explicitly:

| Setting | Value | Why |
|---|---|---|
| `DisallowStartIfOnBatteries` | `false` | Otherwise it never starts undocked |
| `StopIfGoingOnBatteries` | `false` | Otherwise undocking kills the companion |
| `ExecutionTimeLimit` | `PT0S` (none) | The default terminates it after 72 hours |
| `RunLevel` | `LeastPrivilege` | Elevation is a rejected decision, stated not inherited |
| Logon delay | 10 s | Lets the shell and Xbox FSE come up first |

**Settings → Advanced → Check Logon Task** writes the task's full definition to
the log, including **Last Run Time** and **Last Result** — the two fields that
answer "the task exists but nothing happened", and which are not otherwise
visible from inside the companion.

## Deliberately excluded

- Winlogon shell registration or repair
- Explorer launch/kill/monitor logic
- Taskbar hiding or guarding
- **Window sizing, centring, maximising or restoring** — Xbox FSE owns
  presentation, and the geometry layer of 1.5's window engine is never ported
- Focus pinning and continuous focus enforcement
- Steam launch, recovery, or exit monitoring
- Splash video and installer

The window **inventory** and **game detection** from 1.5's engine *are* used, to
drive the assist features. The boundary is inventory and detection yes,
presentation never — and the build validator enforces exactly that.

### How the learner is tested

`Test-ControllerProfiles.py` **mirrors** the learning heuristic and the profile
decoder in Python rather than executing the AutoHotkey — the only way to test this
on a machine without Windows and the hardware. It covers the Ally layout, shared
triggers, 8-bit and 16-bit axes, both endiannesses, active-low controls,
change-only reports, hat D-pads, and release-gated analogue capture.

One case is worth calling out because the mirror originally got it wrong in the
same way the code did. The resolver runs on **every report of a gesture**, not
once at the end, and each run writes its provisional answer into the results map
so the release test can watch the decoded field rather than raw bytes. The test
that covers this therefore resolves incrementally, report by report, and applies
the rejection rule at each step — a test that passed the whole sample list at
once would have missed the bug entirely, because the bug only appears on the
second report.

The weakness is inherent: **a mirror can drift from the code it mirrors**, and one
that agrees only with itself proves nothing. The build validator therefore
compares the tuning constants (`MIN_NORMALISED_DELTA`, `MIN_BYTE_EXCURSION`,
`MIN_PAIR_BALANCE`, and the two width-selection ratios) in both files and fails if
they diverge — that being where drift would realistically happen. Behavioural
drift is still possible, so **a learned profile is only really verified on
hardware.**

## Recovery paths

Things that take away the pointer or the controller must be undoable without
them. Each of these came from a failure on hardware:

| Situation | Recovery |
|---|---|
| A learned profile mis-reads an axis and the pointer runs away | `Ctrl+Alt+Shift+D`, or Settings → Controller & Cursor → **Delete Learned Profile**. Restores the built-in layout. |
| Controller input is dead after sleep | `Ctrl+Alt+Shift+I`, or Settings → Advanced → **Re-arm Controller** |
| The Quick Menu cannot be opened with the controller | `Ctrl+Alt+Shift+Q`; Settings is `Ctrl+Alt+Shift+S` or `P` |
| A learned profile is wrong and the wizard will not run | Delete `SteamShell-XFE-Controllers.ini` beside the executable and restart |

After a profile is saved it is checked against the controller at rest. If any
axis reads as deflected with nothing touched, the wizard says which and offers to
delete it rather than leaving you with a runaway pointer.

## Diagnostics

Startup always logs the settings file in use and the values resolved from it.
The INI is read from beside the executable, so editing a copy elsewhere silently
has no effect and looks exactly like a broken feature.

- **`Controller.DiagnosticLogging`** samples all four XInput slots plus
  GameInput on one tick, with per-slot capabilities and the foreground process
  name, plus an `(alive)` keepalive so silence is unambiguous. Also logs window
  centring calculations.
- **`Controller.RawInputProbe`** logs raw HID report bytes and enumerates which
  HID devices RawInput can see.
- **Probe Screen** (Settings → Advanced) logs every
  visible window after a six-second countdown, with process, class, geometry and
  topmost/foreground state. Built for identifying transient surfaces such as the
  FSE task switcher, which cannot be inspected while a settings window is open.
- **Export Diagnostic ZIP** (health check or Settings → Advanced) bundles the log
  tail, settings and environment — backend, slot capabilities, RawInput state,
  DPI and scaling — with paths sanitised.

Both logging aids are off by default and noisy enough to turn off again once a
question is answered.

## Build

For the easiest Windows build, double-click:

```text
Build-SteamShell-XFE.cmd
```

The launcher applies a process-only PowerShell execution-policy bypass and
keeps the window open so the final result or error remains visible. To invoke
the underlying script directly instead:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-SteamShell-XFE.ps1
```

Validates with the installed 64-bit AutoHotkey v2 interpreter before compiling
`dist\SteamShell-XFE.exe`. The build automatically embeds
`assets\SteamShell-XFE.ico`; `-IconPath` can still override it for a custom
build.

The learned-profile heuristic can also be exercised without Windows or hardware:

```text
python Test-ControllerProfiles.py
```

The executable is portable. Its settings INI, learned-controller INI, and log
are created beside it.
