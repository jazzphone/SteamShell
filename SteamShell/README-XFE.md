# SteamShell XFE Companion

SteamShell XFE is a portable controller-utility companion for Windows Xbox Full
Screen Experience. It is separate from the standalone SteamShell application
and does not replace, install, or modify the Windows shell.

The working tree is **2.0.1**, locked with standalone SteamShell in the
self-contained `releases/2.0.1` bundle. Controller input, the Quick Menu,
Settings, display/HDR controls, RTSS integration, and notification-area control
work inside Xbox FSE. The companion remains deliberately separate from the
SteamShell Windows-shell application, whose working tree is also 2.0.1.

1.9.9 advances to settings schema 9 and consolidates the validated 0.1.21 feature
line into the coordinated pre-2.0 version. Every companion-owned settings/editor
surface now gets temporary controller mouse input, including Controller
Mappings opened from Quick Settings. RTSS adds a configurable Preset entry and
persists Custom independently, migrating the former `CustomFrameCap` value into
the new Preset without discarding it.

0.1.20 advances settings schema to 7 and refreshes the Quick Menu in parity
with standalone SteamShell: Open Keyboard and persistent Mouse Mode are on the
main page, holding Y opens the styled Controller Mappings submenu, Windows
Settings is available from Settings, and all row labels/descriptions use
consistent title casing. Its fresh-install defaults also mirror the applicable
parts of the shared living-room profile: Purple Quick Menu, 3000 controller
deadzone, enabled startup scheduling with an empty application list, enabled
Lite Assist/launcher cleanup, and RTSS with a 158 FPS custom cap.

0.1.19 advances settings schema to 6. It removes XFE's late startup
curtain/video, keeps Steam Big Picture tool windows in the assist inventory,
protects Explorer foreground surfaces, makes CPU game detection effective for
non-fullscreen/minimized games, and binds delayed launcher hard-kill to the
original validated process identities. Existing `[StartupSplash]` settings are
backed up and retired automatically.

0.1.18 came out of the August 2026 cross-tree audit at settings schema 5. It
It adds log rotation (`[Logging] LogRotateMaxKB` / `LogRotateBackups`), moves
per-button-edge controller logging behind the existing `DiagnosticLogging`
flag, restores left-stick Quick Menu navigation, and discovers a stock RTSS
install when `[RTSS] Path` is unset. Missing keys are added to an existing INI
automatically; no values are replaced.
Schema 6 deliberately removes only the retired `[StartupSplash]` section after
preserving the pre-migration INI beside it.

It also gains `ClampInt`/`ClampFloat`, replacing 19 open-coded
`Max(lo, Min(hi, x))` sites, and picks up standalone's explanatory comments on
`OpenOSK` and `SetDefaultAudioEndpointId`. Those bring the number of functions
byte-identical with the standalone tree to 48; see `SHARED_FUNCTIONS.txt` and
the parity check in `Validate-Common.ps1`, both beside this file.

HDR behaviour is **unchanged here, and standalone now matches it.** This
companion has reported **Unavailable** rather than sending a blind Win+Alt+B
toggle since 0.1.14, and `Validate-SteamShell-XFE.ps1` asserts the chord appears
nowhere in this tree. Standalone kept the chord as a fallback until it was traced
and found unreachable: both products build a separate, display-only row when HDR
state cannot be read, so the fallback could only ever have fired if the state
became unreadable between the menu being built and the button being pressed. The
chord is now gone from both, `ToggleQuickMenuHdrState` is one shared definition,
and standalone carries the same rule forbidding it.

Its Quick Menu rows are
painted as one high-DPI GDI+ surface with rounded selection, accent outline,
left accent bar, visible glow, dark `#242424` charcoal base, atomic no-erase
repaints, neutral-gray unselected text, and no system-drawn outer border. The
controls persist only for the open menu session; closing destroys the HWND so
DWM cannot revive stale child surfaces after a fullscreen transition. The
renderer and configurable Quick Menu accent were introduced in 0.1.17 with
settings schema 4. The 0.1.18 changes advanced to schema 5 for the audit
hardening described above; 1.9.9 shipped schema 9 and the 2.0.0 tree is at
schema 18. Schema 10 added the opt-in
`[RTSS] EnableElevatedFrameCapWrites` described under *Elevation*; schema 11
retired the automatic-mouse exclusion mode, described under *Automatic mouse
mode*; schema 12 moved the settings XFE shares with standalone SteamShell into
the sections standalone keeps them in, so the same setting is in the same place
in both products; schema 13 did the same for cursor auto-hide and pointer
parking, which both products had under different names.

Schemas 14 to 18 are additions rather than moves, so nothing relocates. Schema 14
added the `[Assist]` scoring keys that decide which window is the game; schema 15
added a `[Logging]` section, which this product did not have at all; schema 16
added `[Setup]`, the record of what this installation is and where it lives;
schemas 17 and 18 added the elevated RTSS helper's opt-in keys and the companion's
heartbeat interval. Nothing about behaviour changed in any of them, and existing
files are migrated on first run.

`ControllerMouseSpeed` changed UNIT in 2.0.0 — pixels per second rather than
pixels per poll tick — and that conversion is *not* driven by the schema number.
It is detected by range, like this product's other migrations, because a stored
value of 100 is unambiguously an old one: the new setting starts at 200. Use the locked release
directory when reproducibility matters.

### Where settings live, and why the INI is now commented

Every setting in `SteamShell-XFE_SAMPLE.ini` now carries an explanation, matching
standalone's sample. That was not possible before: XFE's settings readers took
the value as everything after the `=`, so `EnableAutoMouseMode=true  ; note` was
read as the string `true  ; note` — which is not `true`, and the setting came
back off. Documenting the file would have silently disabled 45 settings that
default to on. All four readers now strip a trailing comment first, through the
same `CleanIniValue` standalone has always used.

Schemas 12 and 13 moved eleven keys so that a setting shared with standalone is
found in the same place, under the same name, in both products. Schema 12 covered
the automatic-mouse switch and launcher cleanup; schema 13 covered cursor
auto-hide and pointer parking, where both products had the feature all along and
named every part of it differently — this tree's `ParkYPercent` and standalone's
`MouseParkYPercent` carried word-for-word the same explanation, which is how the
duplication was noticed:

| Setting | Was | Now |
|---|---|---|
| `EnableAutoMouseMode` | `[Controller]` | `[Features]` |
| `CooldownSec`, `GracefulCloseMs`, `HardKill`, `RequireNoGame`, `LauncherProcesses` | `[Assist]` | `[LauncherCleanup]` |
| `EnableAutoHide` | `[Cursor]` | `[Features]` as `EnableAutoHideCursor` |
| `ParkOnStartup` | `[Cursor]` | `[Features]` as `EnableMouseParkOnBoot` |
| `HideDelayMs` | `[Cursor]` | `[Timing]` as `MouseHideDelay` |
| `ParkEdge` | `[Cursor]` | `[MousePark]` as `MouseParkEdge` |
| `ParkYPercent` | `[Cursor]` | `[MousePark]` as `MouseParkYPercent` |

Only settings that exist in both trees **under the same name** moved. XFE's
assist tuning that standalone names differently — `TickIntervalMs` against
`CheckIntervalMs`, `CpuThresholdPercent` against `GameCPUThresholdPercent` —
stayed in `[Assist]`, because moving a differently-named setting into a shared
section makes it no easier to find while still invalidating every existing file.
The `Lite` in `EnableGameFocusLite` and its siblings is likewise deliberate:
those features are reduced versions of standalone's, and renaming them to match
would claim a parity that does not exist.
Display discovery also reads the complete driver-reported mode table rather
than truncating it after 512 resolution/refresh combinations.

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

Every step says whether the controller is responding. A step that appears stuck
is either receiving nothing (wrong backend, or running outside FSE) or receiving
reports and rejecting them, and that line is what distinguishes them.

The wizard no longer asks for the Guide/Xbox button. Windows usually swallows it,
and when it does not it opens Game Bar over the wizard. The shorter capture window
that step used is still available to any future control that many pads lack.

A trigger is never matched against a byte that moves on its own — a gyro, most
often. A stick is protected by resting at its centre, which a motion sensor does
not do; a trigger legitimately rests at one end, so there is no equivalent check
to save it. Measured on an 8BitDo Ultimate 2 in DirectInput mode with the gyro
live: 12 of 34 bytes moved at rest, and the left trigger had no candidate outside
them. That step is skipped now, keeping the rest of the profile, instead of
binding the trigger to a motion axis and pinning it at fully pressed.

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
3. **Wall-clock gap.** A periodic check arriving far later than it was scheduled
   for means the machine slept. This matters because **modern standby does not
   reliably deliver the power broadcast**, and modern standby is what a ROG Ally
   sleeps into, so layer 2 cannot be the only trigger.

   Layer 3 used to be a gap between 60-second heartbeats, which meant a resume
   could take up to 150 seconds to notice. It is now `ControllerResumeGapCheck`
   in `SteamShell-Shared.ahk`, driven from the controller poll in both products,
   so it reports the poll interval as its cadence and fires in about 30 seconds.
   It compares `A_Now` rather than a tick counter, because **the tick counter does
   not advance through suspend** — a gap measured on ticks sees nothing at all.

XInput needs none of this: `XInputResolveController` rescans all four slots and
re-resolves on its own. That sweep is rate limited to once every 250 ms, because
`XInputGetState` against an empty slot goes down to the device stack rather than
returning a cached state, and with nothing attached the sweep was running on every
16 ms poll. The slot that answered last time is still read on every poll ahead of
the limiter, so a connected controller is never throttled and a mid-session slot
move still recovers on the same tick. That is why, before this was fixed, the desktop kept
working after a wake while Xbox FSE did not — `auto` was quietly falling back to
XInput, and RawInput stayed dead.

**Manual recovery:** `Ctrl+Alt+Shift+I` or **Settings → Advanced → Re-arm
Controller**. Both release the lock, re-register RawInput, and force XInput to
rescan its slots.

## Controller mouse smoothness

Cursor speed is a **velocity** — `ControllerMouseSpeed` is pixels per second at
full stick deflection, and the Settings row is a slider showing the whole usable
range rather than an edit box asking you to guess a number.

It used to be pixels per *poll tick*, which tied the cursor's speed to how often
the timer happened to fire, and the result was motion that visibly stepped along
its path:

- **Windows quantises timers to about 15.625 ms** unless a process raises the
  resolution, and neither product does. A timer fires on the first tick boundary
  at or after its interval, so the old 16 ms poll — 0.375 ms past a boundary —
  could not fire at 15.625 and waited for 31.25. The poll ran at roughly **32 Hz
  while the setting implied 62.5**, and scheduling noise flipped it between one
  boundary and two.
- **A fixed distance per tick turns uneven timing into uneven distance**, so the
  cursor made 20–100 pixel hops at irregular intervals.

Movement is now scaled by measured elapsed time, the default interval is **15 ms**
(which fires on every boundary, about 64 Hz), and the sub-pixel remainder is
carried between ticks instead of being rounded away. Changing the poll interval
now changes smoothness only, not speed — they used to be the same knob, which is
why neither could be adjusted alone.

`ApplyControllerMouseMove` lives in `SteamShell-Common.ahk`, so the shell, the
companion and the elevated helper all move the cursor with the same arithmetic.
The validators forbid the `32767.0` constant anywhere else, which is what stops a
second copy appearing.

**Upgrading:** existing values are converted (×32) so the cursor moves at the
speed you were already used to, and a `ControllerPollIntervalMs` of exactly 16
becomes 15. A deliberately chosen interval is left alone. The conversion is
detected by range rather than by schema version, matching the companion's other
migrations.

On the Settings page the slider steps by 100 px/s. Driving it with the controller
works through the ordinary arrow-key navigation this window already uses — the
track's own line size is what makes each press move a useful amount.

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

### The one exception: an optional RTSS helper, off by default

There is exactly one place where normal privileges do not merely cost
convenience but remove a feature outright, and it has its own opt-in switch.

`RTSSHooks64.dll` is loaded into the **calling** process, so RTSS's
`SaveProfile` runs with this companion's token — and RTSS installs under
Program Files. Unelevated, the companion can read the cap and toggle the
limiter flag, because that goes through RTSS's shared memory and touches no
file, but it **cannot set the FPS value and cannot save a per-game profile**.
The Frame Limit row reports itself read-only, which is accurate, and *Save Limit
to Profile* reports unavailable.

**Write the cap through an elevated helper** in Settings ▸ RTSS & Performance
(`[RTSS] EnableElevatedFrameCapWrites`, **default off**) hands that one write to
`SteamShell-Helper.exe`, a separate High-integrity process that performs the
`LoadProfile` / `SetProfileProperty` / `SaveProfile` / `UpdateProfiles` sequence
and nothing else.

What turning it on costs, stated plainly:

- **A UAC prompt when the companion starts.** Once per session. XFE does not get
  the protected on-demand scheduled task standalone SteamShell uses to avoid
  that prompt, and that is deliberate — such a task can be invoked directly with
  `schtasks /run` without asking the companion to re-check anything, so it is
  only safe below a protected ancestor chain covering the *whole* path. XFE's
  own directory is user-writable by design, because it keeps its INI, learned
  controller profiles and log beside its executable.
- **A second process for the session**, at High integrity, which exits when the
  companion does.

What it deliberately does **not** do:

- **No elevated controller input.** UIPI blocks this companion's synthetic input
  from elevated foreground windows, and the helper *could* have carried input as
  it does for standalone SteamShell — but that implementation is XInput, and XFE
  exists precisely because XInput is not enough for its users. A controller in
  DirectInput mode is not an XInput device at all. Elevated input would have
  worked only for people who did not need XFE, so it was left out. The accepted
  cost above still applies in full.
- **No window management.** Xbox FSE owns presentation.
- **No UI.** The helper cannot show a message box; an uncaught error is logged
  and the process exits.

Before it is ever elevated, the companion checks that `SteamShell-Helper.exe`
carries the exact expected version *and* that both the binary and its directory
are owned by Administrators and writable by nobody else — and that the binary is
still readable, because an over-restrictive ACL is not protection either.
Anything less and it is not launched, and Health Check says why.

**The helper is installed by `SteamShell.exe` Setup in XFE mode**, into
`%ProgramFiles%\SteamShell-XFE\bin`, and lies dormant there. XFE has no embedded
payload and no administrator rights, so it can never install or repair the
helper itself; if it is missing or the wrong version, re-run Setup as an
administrator. It is installed regardless of this setting so that turning the
setting on later does not mean re-running an installer — a binary on disk is not
an elevated process, and nothing starts it until you ask.

It buys nothing where RTSS is installed somewhere this account can already
write, or where you run the companion elevated yourself. In both cases the
in-process write already works, and Health Check says so rather than starting a
process for no reason.

## The Settings window

Eight categories in a sidebar, with a page for each. Rows place themselves from
a flowing cursor, and the content area **scrolls** when a page is taller than the
window — Controller & Cursor and RTSS & Performance both are. The scrollbar
appears only when a page needs it.

Scroll with the mouse wheel, the scrollbar, or the **left stick**, which already
drives the wheel over any Settings surface. The right stick moves the pointer and
RB clicks, LT/RT change category, and Y saves.

Seven of the eight category names are shared with standalone SteamShell —
General, Controller & Cursor, Steam, RTSS & Performance, Startup Programs,
Launcher Cleanup and Advanced & Logging — and present the settings that exist in
*both* in the same order and wording. Three of those are recent: standalone
gained a Steam page (it had always read `[Steam]` and offered none of it), this
companion gained a Launcher Cleanup page, and this companion's **Advanced** page
is now **Advanced & Logging**, matching the shell.

**Assist** is the only page with no standalone counterpart. Standalone's
Startup & Splash and Focus & Windows do jobs this companion deliberately leaves
to Xbox FSE, so those two are not mirrored in either direction.

Launcher Cleanup is a page in both, but the rows are not shared: the two products
clamp the same keys differently — `CooldownSec` is 30..7200 here and 0..86400
there — and a shared row would offer one of them values its own loader rounds
away. Two of its rows, **Only clean up when no game appears to be running** and
**Graceful-close wait before a force close (ms)**, are settings this companion has
always read and previously had no control for.

One limitation worth knowing: a row scrolled out of view is hidden, and a hidden
control cannot be reached by Tab. Scroll to it first. This matches standalone.

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

Rounded, always-on-top, centred on the monitor holding the foreground app. The
rows are one opaque, physical-pixel-sized GDI+ surface rather than a pool of
native text controls. Selection is an antialiased rounded panel with a derived
accent-tinted fill, accent outline, left accent bar, glow, and accent-coloured
value. Windows 11 supplies antialiased outer corners, with the shaped-window path
retained for Windows 10. The bottom line shows the button hint, replaced by
transient status messages when something happens.

Main rows: **Audio**, **Display & HDR**, **RTSS & Performance**, **Steam Menu**,
**Steam Quick Access**, **Task Switcher**, **Game Bar**, **Open Keyboard**,
**Mouse Mode**, **Settings**, and **System**. Open Keyboard dismisses Quick
Settings before presenting the touch keyboard. Mouse Mode persists the normal
controller pointer/mappings without requiring View/Back. Hold Y on the main
page to open the styled Controller Mappings submenu; its final **Set Controller
Mappings** row opens the full editor.

**System** holds Sleep, Restart, Shut Down, **Exit Companion**, and two rows
shared with standalone SteamShell:

- **Game Detection** — a read-only page showing what the window scorer decided,
  the winner and every candidate it beat, with the numbers behind the result.
  Present when `EnableGameDetectionMenu` is on.
- **Current Application** — the executable that was in front when the menu
  opened, addable to **Automatic Mouse** (`[Controller] AutoMouseExeList`) or
  **Protect From Cleanup** (`[Assist] ProtectedProcesses`) without typing its
  name. The row's value is the executable itself, and a destination already
  holding it reads *(already added)*.

  With a **Store app** in front the row instead reads *"Store app — cannot be
  added by name"* and refuses to open. A packaged app's visible window belongs
  to `ApplicationFrameHost.exe`, so adding it by name would write one entry
  matching Settings, Photos, Calculator and the Store at once.

  It works here and cannot work in Settings for the same reason: the companion
  snapshots the previous foreground window when the menu takes the foreground,
  and Settings has no equivalent moment.

### Automatic mouse mode

The controller can act as a pointer without holding View/Back, decided by what
is in the foreground. `EnableAutoMouseMode` is the master switch and
`AutoMouseExeList` names the applications it applies to. That is the whole
feature; an empty list turns it off as surely as the switch does. Both settings
are on **Settings → Controller & Cursor**.

The shipped list is
`brave.exe|chrome.exe|msedge.exe|firefox.exe|notepad.exe|taskmgr.exe` — standalone
SteamShell's default minus `explorer.exe`, stated once in the shared code and
held to both sample INIs by the build.

**`explorer.exe` is not accepted here.** Explorer owns the Xbox FSE
task/application switcher — an `explorer.exe` window that does hold the
foreground while it is open — so an entry for it turns the stick into a pointer
over the switcher itself and application switching in Xbox Mode stops working.
The companion drops the entry when it loads the list and records one line in the
log; the key is left in your INI untouched, and saving on **Settings → Controller
& Cursor** is what clears it. Standalone keeps `explorer.exe` on its own list
because it *replaces* Explorer as the Windows shell, so the same name there means
a File Explorer or Control Panel window you opened deliberately.

If `explorer.exe` was the only entry in your list, dropping it leaves the list
empty — which turns automatic mouse mode off, exactly as an empty list always
has. Add the applications you actually want it in.

**Two ways to add to it without a keyboard**, because a list you can only fill
by typing an executable name is a list that stays empty on a couch:

- **Settings → Controller & Cursor → Add Recent Application…** offers the last
  five applications you had in the foreground, most recent first, with the last
  window title beside each name. The history is in memory only and includes
  applications you have since **closed** — which are exactly the ones whose
  executable name you can no longer look up. SteamShell's own windows, shell
  surfaces, and anything hosted by `ApplicationFrameHost.exe` are excluded.
- **Quick Menu → System → Current Application** adds whatever is in front right
  now. See *Quick Menu* above.

Xbox FSE needs no special handling here — leave it off the list. It is
controller-driven, and a pointer inside it gets in the way rather than helping.

Automatic mouse mode is evaluated *after* the Quick Menu and Settings chords,
which test the real buttons. A list that turns the pointer on somewhere unwanted
is therefore always correctable from the couch, without a keyboard.

#### What schema 11 removed, and why

Until schema 11 there was a second gate: `EnableDesktopAutoMouseMode`, which
switched the feature into an "everywhere *except* these" mode governed by
`DesktopAutoMouseExcludeExeList`, defaulting to `XboxPcApp.exe`, `GameBar.exe`,
`XboxGameBarWidgets.exe` and `ShellHost.exe`.

It existed because standalone SteamShell makes that same choice using
`DesktopMode`, and the companion has no `DesktopMode` — it never owns the shell.
The exclusion list was the stand-in, and it was standing in for a question
Windows gives no way to ask: *am I inside Xbox FSE right now?* A hand-maintained
list of someone else's shell process names is not an answer to that question; it
is a bug that goes stale quietly, wearing a configuration field.

So the mode was removed rather than kept working badly. Both keys are deleted
from an existing INI during migration, and the change is logged, because it
narrows behaviour: anyone running the old default had a pointer in *every*
foreground application and now has one only where they say so.

If you want the old reach back, name the applications explicitly. That is more
typing once, and it never silently stops being true.

**Settings** is a page of switches rather than a shortcut to the Settings
window, so the things worth changing mid-session can be changed from the couch:
the three assist features, the FSE-switcher pause, and the three View button
actions. **A** or **Left/Right** flips a row. Each toggle writes the INI
immediately with no save step and applies at once. The Settings window is still
one row away at the bottom, alongside a direct Windows Settings row.

**System** is intentionally limited to Sleep, Restart, Shut Down, and Exit.
Health Check, Probe Screen, and controller re-arm remain in **Settings →
Advanced**; re-arm also remains available through `Ctrl+Alt+Shift+I`.

The value column is right-aligned and overlong text is ellipsized. The Audio row
still places the percentage last so its most useful state remains easy to scan.

The Settings page includes **Accent Color**. Left/Right cycles Steam Blue, Blue,
Purple, Magenta, Red, Orange, Yellow, Green, Teal, and Custom, wrapping at both
ends and repainting immediately. Full Settings ▸ General exposes the same preset
plus the custom `RRGGBB` value. Unknown presets or malformed custom values fall
back visibly to Purple rather than producing an unreadable menu.

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

Left/Right cycles **Off · 30 · 40 · 60 · 90 · 120 · Preset · Custom**. Preset
uses `PresetFrameCap` from Settings. Choosing `Custom` restores its separately
retained value and reveals a **Custom FPS** row beneath it; Left/Right there steps the value, and
each press changes it by exactly 1. Holding Left/Right accelerates the repeat
rate while keeping that precise step, and the pending value is committed to RTSS
once input settles instead of rewriting the profile on every repeat.

**"Off" maps to the flag, never to the value.** Writing `0` would discard the
number, so an off/on round trip would silently forget 72 and come back uncapped.
Clearing the flag leaves 72 in the profile, and cycling back on restores it
rather than jumping to the first preset.

Every write targets the **global** profile. Per-game profiles are the user's own
tuning, and a menu that writes whichever profile happens to be in the foreground
is a menu that can silently change a game's configuration.

### Restoring the Frame Limit

RTSS keeps only part of the selection across a restart. The FPS number lives in
its global profile and is persisted, but the limiter flag is runtime state in
RTSS's shared memory, and `Custom` is a concept RTSS never sees. On its own that
means every reboot came back reading **Off**, with the first Right press landing
on 30 FPS rather than your own cap.

XFE records what it applied in `[RTSS] LastFrameCapMode` and `LastFrameCapFps` —
including while Off, where the number is kept for the same reason the Off entry
never writes `0` — and reapplies it once RTSS is running. **Restore last
selection when RTSS starts** in Settings ▸ RTSS & Performance
(`RestoreFrameLimitOnStartup`, default on) controls it.

Two deliberate limits: it **never starts RTSS**, polling for up to two minutes
after startup instead, which is also what makes it work when RTSS arrives later;
and it only writes RTSS's profile when RTSS does not already agree, because that
write is a real edit to RTSS's own configuration. It needs `UseDllIntegration` —
the shortcut fallback can only toggle, not select an FPS — and logs that it
skipped rather than waiting if DLL integration is off.

This behaviour is implemented in `SteamShell-Shared.ahk` and is identical in
standalone SteamShell.

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

Writing also needs a token that can write where RTSS is installed, which is a
different problem with a different answer — see *The one exception: an optional
RTSS helper* under **Elevation**. On a stock Program Files install an unelevated
companion shows the same **read-only** cap for that reason rather than because
of the RTSS build.

Both the global cap and *Save Limit to Profile* now **prove** the write instead
of assuming it. The per-game save previously reported success unconditionally,
so an unelevated companion told every standard user their profile had been
saved while `SaveProfile` had silently done nothing. Both paths read the value
back, and when a helper is available they go straight to it rather than
attempting a local write first — verifying a named profile re-reads the copy
`SetProfileProperty` just wrote, so trying locally first passes the check while
nothing has been saved.

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

A fifth entry, **Installation moved — open Settings**, appears above the others
only when the recorded install location does not match where the companion is
actually running. It is an offer and nothing more: the companion starts and
behaves normally either way. See *The installation record* below.

The icon re-adds itself when Explorer restarts. Explorer rebuilds the
notification area and broadcasts `TaskbarCreated`; before this the icon was lost
until the companion was restarted, taking with it the only route to Settings,
Disable and Exit that does not need a controller.

Disable is session-only and leaves the tray menu available for recovery. It
pauses controller polling, assist and cursor timers, diagnostics, startup
launches that have not fired yet, RawInput processing, and the companion's
global hotkeys. It closes an open Quick Menu, shows the system cursor, releases
injected mouse/modifier buttons, and changes the tray action to **Enable**.
Settings remains available from the tray. Enabling starts the configured timers
again and re-arms RawInput without firing stale controller-release actions.

The source-mode tray loads `assets\SteamShell-XFE.ico`. The build script embeds
the same multi-resolution icon in the compiled executable automatically.

## The installation record

`[Setup]` records what this installation is and where it lives: `Product`,
`InstallationMode`, `InstallDirectory` and `DataDirectory`, alongside `SetupState`
and `SetupVersion`. The companion fills in the two directories itself on first
run, and only when they are absent, so an ordinary start does no file writes.

It writes its own record because the Setup Assistant that deploys the companion
records the install in SteamShell's registry key and SteamShell's INI, not this
one — and because a companion copied into place by hand never met that installer
at all.

At every start the record is compared against where the companion is actually
running. A mismatch is logged, marked on the tray tooltip, offered as a tray
entry, and reported in Health Check. **Nothing else happens.** The companion runs
normally either way; the record is information, not permission.

The point is migration. SteamShell's registry record is the better source while
it exists, and is exactly what does not survive a move: copy this folder to
another PC and the registry is empty while the settings file still describes the
old machine. The file travels with the installation, which makes it the only
record able to notice.

## Assist features (enabled by default)

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

Fullscreen/borderless shape is an immediate game signal. CPU is an additional
signal across non-protected, non-launcher processes with visible windows, so a
minimized game can still block cleanup. The first successful process observation
is treated conservatively until a CPU delta exists.

When hard kill is enabled, the delayed pass retains the exact PIDs and
process creation times that received the polite close. Before force-closing it
rechecks that cleanup is still enabled, that no game has appeared, and that each
PID is still the same process. It never performs a new image-name-wide sweep.

Steam Assist keeps the narrow Steam exception used by the Task Switcher for
Big Picture windows published as tool windows, then chooses the largest titled
Steam surface so a small helper popup is not selected instead of Big Picture.

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

It is matched by **class** in the overlay list. An `explorer.exe` overlay entry
would also match the desktop, the taskbar and every File Explorer window, and
would pause assistance far more often than intended. Explorer is separately in
the foreground-protection list, which prevents focus being taken from an
Explorer surface only while that surface actually owns the foreground. Prefer
`class:` overlay entries; use a bare exe name only when every window from that
process should suspend assistance.

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

## Startup programs

Launches a list of applications shortly after the companion starts, with a
configurable initial delay and a stagger between launches. Scheduling defaults
on with a 2-second delay and Hidden window mode, but the application list is
empty until configured. Programs already running are skipped. Managed in
**Settings → Startup Programs**.

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
2. Turn **Exit FSE when Home app exits** off.
3. Do not select SteamShell XFE itself as the custom Home app.
4. Leave `SteamShell-XFE.exe` **out** of AnyFSE's startup applications.

Step 4 is the one that changed. Setup Assistant registers a per-user logon task
when it installs XFE, so the companion already starts at sign-in; adding it to
AnyFSE's startup list as well starts it twice. If you configured XFE before the
unified installer and it is still in that list, remove it from there rather than
removing the task.

The task runs at normal privileges; see the elevation section above. **Settings
→ Advanced → Create Logon Task** registers the same task by hand, for an
installation that did not come from Setup Assistant.

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
- Startup curtain/video and installer. AnyFSE launches Steam before this
  companion, so an XFE curtain would cover an already-visible Steam client.
  Standalone SteamShell retains its lifecycle-integrated startup presentation.

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
- **Game-score logging** (`[Logging]`, off by default) writes a table showing
  which windows were considered as the game and what each scored — shape, CPU,
  audio, and whether it was full-screen. `TOPN` lists the highest scorers;
  `DIAGNOSTIC` also lists the near-misses that were rejected and why. It is the
  same table SteamShell writes, in the same format.

  This matters most for the per-game RTSS frame cap, which is keyed on an
  executable **name**: if the wrong window is chosen the cap is written to
  another program's RTSS profile and reported as saved. A table is written
  whenever candidates exist, including when none was chosen — that is the case
  that most needs explaining.
- **Health Check** (Settings → Advanced) lists each check as Status, Check and
  Details, with **Refresh** and **Copy Report**. It shares its window and report
  format with standalone SteamShell, so a report from either product reads the
  same; only the checks themselves are product-specific. It also carries an
  **Installation record** row — see below.
- **Export Diagnostic ZIP** (health check or Settings → Advanced) bundles the log
  tail, settings and environment — backend, slot capabilities, RawInput state,
  DPI and scaling — with paths sanitised.

Both logging aids are off by default and noisy enough to turn off again once a
question is answered.

## Build

The companion no longer has a build script of its own. One script in this
folder builds all three binaries, because `SteamShell.exe` embeds the companion
so Setup Assistant can install either product. Double-click:

```text
Build-SteamShell.cmd
```

The launcher applies a process-only PowerShell execution-policy bypass and keeps
the window open so the final result or error remains visible. To invoke the
underlying script directly instead:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-SteamShell.ps1
```

It runs both validators, then validates each source with the installed 64-bit
AutoHotkey v2 interpreter before compiling it. The companion is compiled to
`build\SteamShell-XFE.exe` for embedding and verified at file version 2.0.1.0,
and `assets\SteamShell-XFE.ico` is applied automatically. A copy is left in
`dist\SteamShell-XFE.exe` for developing the companion — pass `-NoXfeDist` to
skip it.

**That copy is not how you install XFE.** Setup Assistant inside
`SteamShell.exe` registers the logon task, grants the companion's own directory
to the signed-in user, and deploys the dormant elevated helper; a hand-copied
executable gets none of that. Only `SteamShell.exe` is published to `current\`.

From the workspace root, `Run-SteamShellValidation.cmd` runs the whole gate:
syntax, both validators, the shared-parity check, the full build, then negative
tests that break each of the three sources in turn and lock each
freshness-checked output. A failed run returns non-zero and preserves the
previous `current\` directory.

The learned-profile heuristic can also be exercised without Windows or hardware:

```text
python Test-ControllerProfiles.py
```

The executable is portable. Its settings INI, learned-controller INI, and log
are created beside it.
