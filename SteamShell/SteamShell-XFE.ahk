; ==============================================================================
; SteamShell XFE Companion
; Controller-first utilities for Windows Xbox Full Screen Experience.
;
; This is intentionally NOT a Windows shell, Steam launcher, taskbar guard,
; Explorer manager, window scorer, or focus engine. Xbox FSE owns those jobs.
;
; Hotkeys:
; Ctrl+Alt+Shift+Q  Quick Menu
; Ctrl+Alt+Shift+S  Settings
; Ctrl+Alt+Shift+P  Settings (matches SteamShell 1.5's Control Panel shortcut)
; Ctrl+Alt+Shift+R  Reload settings
; Ctrl+Alt+Shift+I  Re-arm controller input after a backend stall
; Ctrl+Alt+Shift+D  Delete the learned controller profile for this device
; Ctrl+Alt+Shift+X  Exit companion
;
; While the Quick Menu is focused: arrows navigate, Left/Right adjust, Enter or
; Space selects, Backspace or Escape goes back, Delete closes the selected
; window, Home/End jump to the first or last row.
; ==============================================================================
#Requires AutoHotkey v2.0.19 64-bit
#SingleInstance Ignore

; Shared function definitions, compiled into both trees. See the file header
; for the rules and for the per-tree seam it depends on.
#Include SteamShell-Common.ahk
#Include SteamShell-Shared.ahk
;@Ahk2Exe-SetName SteamShell XFE Companion
;@Ahk2Exe-SetDescription Controller-first companion for Xbox Full Screen Experience
;@Ahk2Exe-SetVersion 2.0.0.0
Persistent
SendMode "Input"
SetTitleMatchMode 2
; Mouse coordinates are SCREEN coordinates, everywhere.
;
; AutoHotkey v2 defaults this to Client -- relative to the active window -- which
; is wrong for every use of MouseGetPos in this file. Two consequences were seen
; on hardware:
;
;   - The cursor kept reappearing. The auto-hide watcher compares the pointer's
;     position between ticks, and when the Quick Menu opened or changed page the
;     ORIGIN moved, so the unchanged pointer read as having moved and the cursor
;     was shown again.
;   - Monitor detection could pick the wrong screen, because the work-area
;     lookups feed MouseGetPos results into a screen-coordinate comparison.
;
; Set in the auto-execute section, so it becomes the default for every timer and
; hotkey thread too. MouseMove(..., "R") is relative and unaffected.
CoordMode "Mouse", "Screen"

global AppVersion := "2.0.0"
global SettingsSchemaVersion := 18
global IniPath := A_ScriptDir "\SteamShell-XFE.ini"
global LogPath := A_ScriptDir "\SteamShell-XFE.log"
global ScriptPid := DllCall("GetCurrentProcessId", "UInt")
global XInputDll := ""

; Controller input backend state.
global GameInputModule := 0
global GameInputPtr := 0
global GameInputReady := false
global GameInputFailed := false
global ActiveInputBackend := "none"
global GameInputLastRawButtons := 0
global GameInputLastHr := 0
global LastStatusText := "Ready"
global LastStatusLevel := "Info"
; The Quick Menu status line shows transient feedback only. Zero means nothing
; has been reported yet, so the idle placeholder above is never drawn.
global LastStatusTick := 0
global StatusVisibleMs := 6000
; Disable pauses operational behavior while leaving the notification-area menu
; alive so the companion can be enabled again without a keyboard.
global CompanionDisabled := false
global ControllerNeedsFreshBaseline := false

; Runtime configuration.
global HeartbeatSeconds := 60
global LogRotateMaxKB := 256
global LogRotateBackups := 2
global EnableQuickMenu := true
global QuickMenuChordHoldMs := 500
global EnableControllerMouseMode := true
global EnablePersistentMouseMode := false
; Automatic mouse mode: a master toggle and an allowlist of executables. This is
; standalone's non-desktop-mode behaviour exactly, and it is the whole feature.
;
; It used to have a second gate. Standalone chooses between an allowlist and a
; blanket "everywhere except these" using DesktopMode, and the companion has no
; DesktopMode -- it never owns the shell -- so EnableDesktopAutoMouseMode was
; introduced to make that choice by hand, with a default exclusion list naming
; Xbox FSE's shell surfaces.
;
; That was the wrong shape, because the question it was standing in for is "am I
; inside Xbox FSE right now?" and Windows exposes no way to ask it. The
; exclusion list was a hand-maintained guess at FSE's process names, and a guess
; that has to stay current with someone else's shell is not a feature -- it is a
; standing bug with a configuration field in front of it. "Everywhere except a
; list I have to keep correct" was removed rather than kept working badly.
;
; What remains says only what it can actually know: name the applications where
; the controller should be a mouse. Xbox FSE needs no exclusion because it is
; simply never on the list.
global EnableAutoMouseMode := true
global AutoMouseExeListRaw := DefaultAutoMouseExeList()
global AutoMouseExeSet := Map()
; "auto" (default), "rawinput", "xinput", or "gameinput".
;
; Auto reads RawInput whenever HID reports are arriving and XInput otherwise.
; That combination is what works everywhere: XInput and GameInput both read all
; zeros inside Xbox FSE, and RawInput is silent outside it.
global ControllerBackend := "auto"
; Logs every XInput slot plus GameInput on each change. Diagnostic use only.
global EnableControllerDiagnostics := false
global ControllerDiagnosticIntervalMs := 50
; Logs raw HID gamepad reports received in the background. Diagnostic use only;
; it feeds nothing and decodes nothing.
global EnableRawInputProbe := false
global RawInputProbeActive := false
; RawInput backend state. Reports arrive as WM_INPUT messages and are decoded
; into this XINPUT_STATE-shaped buffer for the poll loop to read.
global RawInputState := Buffer(16, 0)
global RawInputLastReportTick := 0
global RawInputDevice := 0
; Wall-clock stamp of the last heartbeat, used to notice that the machine slept.
global LastHeartbeatStamp := ""
global RawInputStaleMs := 5000
global ControllerIndex := 0
global ActiveControllerIndex := -1
global ControllerPollIntervalMs := 15
global ControllerDeadzone := 3000
global ControllerMouseSpeed := 3200
global ControllerMouseFastMultiplier := 2.5
global ControllerScrollIntervalMs := 80
global ControllerScrollStep := 1
global ControllerChordHoldMs := 500
; Steam shortcuts. These are sent to whatever owns the foreground, so they must
; match the bindings configured inside Steam itself.
global SteamMenuShortcut := "^1"
global SteamQuickAccessShortcut := "^2"
global SteamOverlayShortcut := "+{Tab}"
global EnableViewSteamActions := true
; Tap and hold are separately switchable, because they are not equally welcome.
; The hold is the one that fires by accident: View is a scoreboard or map button
; in many games and gets held on purpose, so someone may want the tap while
; refusing the hold, or the reverse. Both are gated by the master switch above.
global EnableViewTapAction := true
global EnableViewHoldAction := true
; Separate hold thresholds. With Steam in front nothing else wants the View
; button, so a short hold feels responsive. In a game View is commonly the
; scoreboard or map button and gets held deliberately, so the threshold there is
; longer to avoid throwing the Steam overlay up mid-match.
global ViewHoldMs := 500
global ViewHoldInGameMs := 1000
; ------------------------------------------------------------------------------
; Assist features (window inventory, game detection, focus help, cleanup)
;
; These read window and process state and may activate a window or close a
; launcher. They deliberately do NOT size, centre or maximise anything: Xbox FSE
; owns presentation, and geometry is the one part of SteamShell 1.5's window
; engine that is never brought across.
;
; The shared SteamShell default profile enables all three. XFE still omits the
; standalone geometry engine so Xbox FSE remains the sole presentation owner.
; ------------------------------------------------------------------------------
global EnableGameFocusLite := true
global EnableSteamAssistLite := true
global EnableLauncherCleanupLite := true
global AssistTickIntervalMs := 2000
global AssistCpuThresholdPercent := 12
; Scoring inputs for XfeBestGameWindow. The values match the shell's defaults so
; both products answer "which window is the game" identically out of the box.
; Game-score diagnostics. Off by default: this writes a table on every evaluation
; and is a troubleshooting aid, not something a normal session should pay for.
global EnableGameScoreLogging := false
global GameLogMode := "OFF" ; OFF | TOPN | DIAGNOSTIC
global GameLogTopN := 3
global GameLogIntervalMs := 3000
global GameLogIncludeTitles := true
global _LastGameLogTick := 0
global AssistScoreFullscreen := 70
global AssistScoreBorderlessLarge := 45
global AssistScoreTitleBonus := 10
global AssistScoreCpuAboveThreshold := 20
global AssistScoreCpuNonZeroBonus := 15
global AssistScoreAudioActive := 30
global AssistFullscreenTolerance := 0.98
global AssistFullscreenPosTolerancePx := 2
global AssistAllowZeroCpuAsCandidate := true
global EnableAudioAssist := true
global AudioPeakThreshold := 0.02
global AssistForegroundStableSec := 30
global AssistCooldownSec := 300
global AssistGracefulCloseMs := 4000
global AssistHardKill := true
global AssistRequireNoGame := true
global AssistLauncherProcesses := "UbisoftConnect.exe|upc.exe|EpicGamesLauncher.exe|EADesktop.exe|EALauncher.exe|Origin.exe|Battle.net.exe|RockstarGamesLauncher.exe|GalaxyClient.exe|RiotClientServices.exe|RiotClientUx.exe|wgc.exe|Heroic.exe|UbisoftConnectService.exe|UplayWebCore.exe|UplayService.exe|EpicWebHelper.exe|EABackgroundService.exe|BlizzardUpdateAgent.exe|Agent.exe|RockstarService.exe|SocialClubHelper.exe|GalaxyClientService.exe|GalaxyCommunication.exe|RiotClientUxRender.exe|legendary.exe|gogdl.exe|nile.exe"
global AssistProtectedProcesses := "explorer.exe|steam.exe|steamwebhelper.exe|AnyFSE.exe|SteamShell-XFE.exe|dwm.exe|csrss.exe|winlogon.exe"
global AssistIgnoreForegroundProcesses := "explorer.exe|ApplicationFrameHost.exe|ShellHost.exe|GameBar.exe|XboxGameBarWidgets.exe|SearchHost.exe|StartMenuExperienceHost.exe|ShellExperienceHost.exe"
; Shell overlays -- the Xbox FSE task/application switcher and friends.
;
; IgnoreForegroundProcesses is not enough for these. An overlay can sit on top
; without ever owning the foreground, so the foreground still reads as Steam or
; the game and Steam Assist happily "returns to Steam", which dismisses the
; switcher the moment it appears.
;
; Entries are matched against the window's process name, or its class when
; prefixed with "class:".
;
; Measured 2026-07-25: the Xbox FSE switcher is an explorer.exe window of class
; XamlExplorerHostIslandWindow, and it does own the foreground while open. It is
; matched by CLASS on purpose -- an explorer.exe entry would also match the
; desktop, the taskbar and every File Explorer window, and would pause
; assistance far more often than intended.
;
; Use Settings -> Advanced -> Probe Screen to identify anything else.
global AssistSuspendOnShellOverlay := true
global AssistShellOverlayProcesses := "class:XamlExplorerHostIslandWindow|class:MultitaskingViewFrame|class:Windows.UI.Core.CoreWindow|XboxPcApp.exe|GameBar.exe|XboxGameBarWidgets.exe|ShellHost.exe"
; Runtime assist state.
global AssistShellOverlayLastLogTick := 0
global AssistInventory := []
global AssistInventoryTick := 0
global AssistCpuSamples := Map()
global AssistForegroundSteadySince := 0
global AssistLastCleanupTick := 0
global AssistSuspendUntilTick := 0
global AssistLastFocusHwnd := 0
global AssistLastFocusTick := 0
global AssistPendingHardKillPids := Map()

; ------------------------------------------------------------------------------
; Startup programs
;
; Launches a list of applications shortly after the companion starts, so extra
; tools can come up in an FSE session without needing a second startup mechanism.
; ------------------------------------------------------------------------------
global EnableStartupPrograms := true
global StartupProgramDelayMs := 2000
global StartupProgramStaggerMs := 1200
; When the companion itself is elevated, a child process inherits that token.
; Launching through the shell hands the child the ordinary user token instead,
; which matters most for Steam: an elevated Steam passes elevation on to every
; game it starts, and Valve advises against running it that way.
global StartupLaunchDeElevated := true
; How each program's own windows are presented, ported from SteamShell 1.5:
; Normal, Minimized or Hidden. Background helpers -- overlays, controller daemons,
; sync agents -- have no business drawing a window over Xbox FSE, and Hidden is
; how 1.5 kept them out of the way.
global StartupWindowMode := "hidden"
global StartupPrograms := []

global EnableAutoHideCursor := true
global MouseHideDelay := 1000
global EnableMouseParkOnBoot := true
global ParkOnGameStart := true
global ParkOnSteamReturn := true
; Which side of the screen the cursor is parked against. Right by default: on a
; TV the right edge is where a cursor that briefly reappears is least noticeable,
; and nothing in Xbox FSE puts controls there.
global MouseParkEdge := "right"
global ParkYPercent := 0.50
global ForegroundPollMs := 500
global EnableRTSSIntegration := true
global RtssPath := "C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe"
global RtssUseDllIntegration := true
global RtssOverlayControlMode := "separate"
global RtssOverlayToggleShortcut := "^+o"
global RtssOverlayOnShortcut := "^+1"
global RtssOverlayOffShortcut := "^+2"
global RtssFrameLimiterControlMode := "separate"
global RtssPresetFrameCap := 158
global RtssCustomFrameCap := 158
global RtssCustomFrameCapShortcut := "^+f"
global RtssRestoreFrameLimitOnStartup := true
; The Frame Limit selection last applied. RTSS persists only the FPS number
; in its global profile; the limiter on/off flag is runtime state in its
; shared memory, and "Custom" is a concept RTSS never sees. Without these,
; none of the selection survives an RTSS restart. See SteamShell-Shared.ahk.
global RtssLastFrameCapMode := ""
global RtssLastFrameCapFps := 0
global RtssFrameLimiterOnShortcut := "^+5"
global RtssFrameLimiterOffShortcut := "^+6"
; RTSS exposes its global visibility/limiter flags from RTSSHooks64.dll. Keep
; the module loaded while the companion runs so Quick Menu refreshes can query
; those flags without repeatedly loading the DLL.
global RtssHooksModule := 0
global RtssHooksDllPath := ""
global RtssGetFlagsProc := 0
global RtssSetFlagsProc := 0
global RtssLoadProfileProc := 0
global RtssGetProfilePropertyProc := 0
global RtssSetProfilePropertyProc := 0
global RtssSaveProfileProc := 0
global RtssUpdateProfilesProc := 0
global RtssHooksLastFailure := ""
; Quick Menu frame-cap presets, in cycle order. "Off" and "Custom" are derived
; states rather than list entries; see GetRtssFrameCapState.
global RtssFrameCapPresets := [30, 40, 60, 90, 120]
; Session-only. Set when the user cycles to Custom while the live value happens
; to equal a preset; without it the next repaint would derive "preset" again and
; the Custom row would vanish under the selection. Never persisted.
global RtssFrameCapCustomMode := false
; Set the first time RTSS accepts a FramerateLimit write and then reports a
; different value. See RtssFrameCapBlockedReason in SteamShell-Shared.ahk.
global RtssFrameCapWriteBlocked := false
; Repaint cache for the global FramerateLimit read. QuickMenuRender rebuilds
; every row on every refresh and each miss costs a LoadProfile plus a
; GetProfileProperty round trip. Zeroed after any write so the row never shows
; a value it just replaced.
global RtssFrameLimitCacheFps := 0
global RtssFrameLimitCacheTick := 0
; Value the user is currently dialling in, before it reaches RTSS. 0 = nothing
; pending. See AdjustRtssCustomFrameCap.
global RtssPendingFrameCap := 0

; ------------------------------------------------------------------------------
; Opt-in elevated RTSS helper
; ------------------------------------------------------------------------------
; OFF by default, and that is the point: choosing XFE means choosing a companion
; with nothing elevated in it, and turning this on is the user deciding
; otherwise. See StartElevatedRtssHelper for what it does and does not do.
global RtssElevatedFrameCapWrites := false
global ElevatedHelperPath := ""
global ElevatedHelperPid := 0
global ElevatedHelperAvailable := false
global ElevatedHelperLastError := "Not started"
; Must match SteamShell.ahk. One payload, embedded once in SteamShell.exe and
; deployed by one Setup Assistant, so a mismatch here means the two trees were
; built from different commits.
global ElevatedHelperExpectedVersion := "2.0.0.1"
; Recorded once at startup from this process's own token. XFE never re-launches
; itself across the elevation boundary, so unlike standalone there is no
; pre-elevation identity to carry forward -- see InitializeExpectedInteractiveIdentity
; there, which stayed per-tree for exactly that reason.
global ExpectedInteractiveUserSid := ""
global ExpectedInteractiveSessionId := -1
global ElevatedRtssEventHandle := 0
global ElevatedRtssDoneEventHandle := 0
global RtssElevatedRequestSeq := 0

; Controller mappings use View/Back unless persistent Mouse Mode is enabled.
global ControllerMap := Map()
global ControllerMapDisplay := Map()

; Cursor and foreground observer state.
global MouseHidden := false
global LastMouseX := -99999
global LastMouseY := -99999
global LastMouseMoveTick := A_TickCount
global LastObservedForegroundExe := ""
; The last foreground executable that looked game-like, kept separately because
; LastObservedForegroundExe is overwritten the moment Steam comes forward -- and
; "which game is running" has to survive that.
global LastObservedGameExe := ""
; Set by RegisterTaskbarCreatedListener in SteamShell-Shared.ahk. Declared here
; because every other global in this tree is, not because the assignment needs
; it -- an undeclared global would be created by that assignment anyway, which is
; exactly the kind of thing that should not be left to chance.
global TaskbarCreatedMessage := 0
global LastObservedForegroundHwnd := 0
global LastObservedForegroundWasGame := false

; Quick Menu state.
global QuickMenuGui := unset
; Quick Menu layout, shared with the shell. The companion had no layout manager
; and hid its Audio and Display rows through a pair of Enable keys instead;
; those are retired now that this window exists here too.
global QuickMenuMainOrderRaw := "Audio|Display|RTSS|SteamMenu|SteamQuickAccess|Tasks|GameBar|Keyboard|MouseMode|Settings|System"
global QuickMenuHiddenItemsRaw := ""
global QuickMenuMainOrder := []
global QuickMenuHiddenItems := Map()
global QuickMenuLayoutGui := unset
global QuickMenuVisible := false
global QuickMenuPage := "MAIN"
global QuickMenuRows := []
global QuickMenuSelected := 1
; How many rows the window was last sized for. A refresh re-derives the row
; list, so this is what tells it the page grew and the window has to follow.
global QuickMenuSizedRowCount := 0
; Quick Menu palette. One place to change the look; every row color is derived
; from these rather than repeated as literals through the renderer.
global QM_BG := "242424"          ; dark neutral charcoal window background
global QM_ROW_SELECTED := "2C373D" ; selected row fill, derived from the accent
global QM_ACCENT := "66C0F4"      ; selected row bar, outline and value
global QM_LABEL := "D8D8D8"       ; unselected label, neutral light gray
global QM_LABEL_SELECTED := "FFFFFF"
global QM_VALUE := "A0A0A0"       ; unselected value, neutral dim gray

; Quick Menu accent. One setting drives the whole selected-row palette.
;
; The fill is derived rather than stored, because the two are not independent.
; Measured against the original Steam blue, QM_ROW_SELECTED was a ~12% blend of
; the accent into the background -- that relationship is what makes the fill read
; as deliberate instead of as a grey that happens to sit under a colored bar.
; Deriving it means green or purple gets the same treatment automatically rather
; than leaving a blue-grey fill under a green accent.
global QM_ACCENT_BLEND := 0.12
global QuickMenuAccentName := "Purple"
global QuickMenuAccentCustomHex := "107C10"

; Ordered deliberately: an array, not a Map, because AutoHotkey v2 Map
; enumeration order is unspecified and this list is shown to the user.
global QM_ACCENT_PRESETS := [
    ["Steam Blue", "66C0F4"],
    ["Blue", "4C8DFF"],
    ["Purple", "A970FF"],
    ["Magenta", "FF6FD8"],
    ["Red", "FF5C5C"],
    ["Orange", "FF9F45"],
    ["Yellow", "FFD166"],
    ["Green", "5CD65C"],
    ["Teal", "2DD4BF"],
    ["Custom", ""]]
global QuickMenuTitleCtrl := 0
global QuickMenuStatusCtrl := 0
global QuickMenuRowsCtrl := 0
global QuickMenuRowsBitmap := 0
global QuickMenuRedrawSuspended := false

; Game-detection snapshot, read by the shared presentation in
; SteamShell-Shared.ahk. The companion scores candidates in XfeBestGameWindow
; where the shell scores them in WindowEngineEvaluateGame; everything after that
; point is the same question, so it is answered once, in the shared files.
global LastGameCandidates := []
global GameScoreMaxRows := 8
global EnableGameDetectionMenu := true
global LastBestCandidateProc := ""
global LastBestCandidateScore := -1
global GdiPlusToken := 0
global GdiPlusModule := 0
global QuickMenuMonitorIndex := 1
global QuickMenuDisplayModes := []
global QuickMenuAudioDevices := []
; Foreground process captured when the Quick Menu opened, so Steam actions can
; tell Steam from a game after our own window has taken the foreground.
global QuickMenuPreviousExe := ""
global QuickMenuPreviousHwnd := 0
global QuickMenuTaskWindows := []
global QuickMenuTaskPage := 1
global QuickMenuConfirmAction := ""
global QuickMenuConfirmUntilTick := 0
; Pending display selection. Chosen with the Resolution and Refresh rows and
; only applied when Apply is activated.
global DisplaySelectedWidth := 0
global DisplaySelectedHeight := 0
global DisplaySelectedFrequency := 0
global DisplaySelectedScalePercent := 0
global DisplayPendingOldMode := 0
global DisplayPendingOldScale := 0
global DisplayPendingUntilTick := 0

; Health Check state, owned by SteamShell-Shared.ahk.
;
; Declared here because the shared file's rule is that every global it touches
; exists in BOTH trees, and these two existed only in SteamShell.ahk. Nothing
; enforced the rule until now, and the companion got away with it for one
; accidental reason: ShowHealthCheck calls RefreshHealthCheck before the window
; is interactive, so HealthCheckResults is always assigned before Copy Report
; can read it. Move that single line and the companion throws on a button the
; shell handles fine. The empty array is the same default standalone uses.
global HealthCheckGui := unset
global HealthCheckResults := []

; Settings and shortcut-capture state.
global SettingsGui := unset
global SettingsFields := Map()
global SettingsVisible := false
global SettingsDirty := false
global SettingsDialogActive := false
global SettingsCategoryControls := Map()
; Scrolling Settings viewport.
;
; XFE's Settings window is a fixed 920x660 and its pages were positioned by hand,
; which is why two of them grew sideways into a second column instead of down.
; Rows now place themselves, so a page can be taller than the window, and the
; content area scrolls -- the same arrangement standalone has had, ported here so
; the two windows can finally be laid out the same way.
;
; SettingsControlPositions holds each control's ORIGINAL, unscrolled geometry.
; Everything is measured once, when the native controls exist, so scrolling is a
; pure transform of recorded positions and repeated scrolling cannot accumulate
; drift.
global SettingsControlPositions := Map()
global SettingsCategoryOffsets := Map()
global SettingsScrollBar := 0
global StartupProgramsList := unset
global LogonTaskStatusCtrl := unset
global SettingsCategoryList := 0
global SettingsCategoryTitleCtrl := 0
global SettingsCategoryDescriptionCtrl := 0
global SettingsCurrentCategory := 1
global MappingGui := unset
global MappingList := 0
global _ShortcutCap := ""

DefaultSettings() {
    return Map(
        "Companion", Map(
            "SettingsSchemaVersion", 18,
            "HeartbeatSeconds", 60
        ),
        ; Schema 12. Standalone keeps its cross-cutting feature switches in
        ; [Features] rather than beside the settings they gate, and a user who
        ; has configured one product should find the same switch in the same
        ; place in the other. Only settings that exist in BOTH trees under the
        ; SAME name moved; XFE-only concepts stayed where they were, because
        ; putting them in a section standalone does not have would align nothing.
        "Features", Map(
            "EnableAutoMouseMode", "true",
            ; Schema 13. Same intent as standalone's, so the same name and the
            ; same section; a user who configured one product finds it here.
            "EnableAutoHideCursor", "true",
            "EnableMouseParkOnBoot", "true"
        ),
        "Timing", Map(
            "MouseHideDelay", 1000
        ),
        "MousePark", Map(
            "MouseParkEdge", "right",
            "MouseParkYPercent", 0.50
        ),
        "QuickMenu", Map(
            "Enable", "true",
            "ShowGameDetection", "true",
            "MainOrder", "Audio|Display|RTSS|SteamMenu|SteamQuickAccess|Tasks|GameBar|Keyboard|MouseMode|Settings|System",
            "HiddenItems", "",
            "GameScoreMaxRows", 8,
            "ChordHoldMs", 500,
            "AccentColor", "Purple",
            "AccentColorCustom", "107C10"
        ),
        "Controller", Map(
            "EnableControllerMouseMode", "true",
            "EnablePersistentMouseMode", "false",
            "AutoMouseExeList", DefaultAutoMouseExeList(),
            "Backend", "auto",
            "DiagnosticLogging", "false",
            "RawInputProbe", "false",
            "RawInputStaleMs", 5000,
            "ControllerIndex", 0,
            "ControllerPollIntervalMs", 15,
            "ControllerDeadzone", 3000,
            "ControllerMouseSpeed", 3200,
            "ControllerMouseFastMultiplier", 2.5,
            "ControllerScrollIntervalMs", 80,
            "ControllerScrollStep", 1,
            "ControllerChordHoldMs", 500
        ),
        "Steam", Map(
            "MenuShortcut", "^1",
            "QuickAccessShortcut", "^2",
            "OverlayShortcut", "+{Tab}",
            "EnableViewButtonActions", "true",
            "EnableViewTapAction", "true",
            "EnableViewHoldAction", "true",
            "ViewHoldMs", 500,
            "ViewHoldInGameMs", 1000
        ),
        "StartupPrograms", Map(
            "Enable", "true",
            "DelayMs", 2000,
            "StaggerMs", 1200,
            "WindowMode", "Hidden",
            "LaunchDeElevated", "true"
        ),
        "Assist", Map(
            "EnableGameFocusLite", "true",
            "EnableSteamAssistLite", "true",
            "EnableLauncherCleanupLite", "true",
            "TickIntervalMs", 2000,
            "CpuThresholdPercent", 12,
            "ForegroundStableSec", 30,
            "ProtectedProcesses", "explorer.exe|steam.exe|steamwebhelper.exe|AnyFSE.exe|SteamShell-XFE.exe|dwm.exe|csrss.exe|winlogon.exe",
            "IgnoreForegroundProcesses", "explorer.exe|ApplicationFrameHost.exe|ShellHost.exe|GameBar.exe|XboxGameBarWidgets.exe|SearchHost.exe|StartMenuExperienceHost.exe|ShellExperienceHost.exe",
            "SuspendOnShellOverlay", "true",
            "ShellOverlayProcesses", "class:XamlExplorerHostIslandWindow|class:MultitaskingViewFrame|class:Windows.UI.Core.CoreWindow|XboxPcApp.exe|GameBar.exe|XboxGameBarWidgets.exe|ShellHost.exe",
            ; Schema 14. The scorer that decides which window is the game, used
            ; by the per-game RTSS frame cap. Values match SteamShell's defaults
            ; so both products pick the same window; the assist features above
            ; keep their own simpler shape test and are unaffected.
            "ScoreFullscreen", 70,
            "ScoreBorderlessLarge", 45,
            "ScoreTitleBonus", 10,
            "ScoreCpuAboveThreshold", 20,
            "ScoreCpuNonZeroBonus", 15,
            "ScoreAudioActive", 30,
            "FullscreenTolerance", 0.98,
            "FullscreenPosTolerancePx", 2,
            "AllowZeroCpuAsCandidate", "true",
            "EnableAudioAssist", "true",
            "AudioPeakThreshold", 0.02
        ),
        ; Schema 15. This product had no [Logging] section: rotation lived under
        ; [Companion] and there was nothing to configure about diagnostics
        ; because there were none. Rotation stays where it is -- moving a key
        ; every existing INI already carries would break them for no gain.
        ; Schema 16. What this installation believes it is, in the file that
        ; travels with it. The registry record is the better source while it
        ; exists and is exactly what does not survive a move: copy this folder to
        ; another PC and HKCU is empty while this section still describes the old
        ; machine, which is the only way to notice.
        ;
        ; The companion writes its own, because the Setup Assistant that deploys
        ; it records the install in SteamShell's registry key and SteamShell's
        ; INI, not here -- and because a companion copied into place by hand
        ; never met that installer at all.
        "Setup", Map(
            "SetupState", "Complete",
            "SetupVersion", "1",
            "Product", "XFE",
            "InstallationMode", "Portable",
            "InstallDirectory", "",
            "DataDirectory", ""
        ),
        "Logging", Map(
            ; EnableGameScoreLogging is NOT here: it is derived from GameLogMode
            ; now, and writing it back would re-create a key that reads as a
            ; second switch for the same thing.
            "GameLogMode", "OFF",
            "GameLogTopN", 3,
            "GameLogIntervalMs", 3000,
            "GameLogIncludeTitles", "true",
            ; Schema 18. These were in [Companion] under these same names, and
            ; standalone had them in [Logging] under GameLog-prefixed ones. They
            ; size and count backups of the companion log AND the elevated
            ; helper's log, so neither the "Companion" section nor the "Game"
            ; prefix described them. Both products name them this way now.
            "LogRotateMaxKB", 256,
            "LogRotateBackups", 2
        ),
        ; Schema 12. These five carry standalone's own names, so they now carry
        ; standalone's section as well. The rest of the cleanup tuning stayed in
        ; [Assist]: XFE's names for it do not match standalone's, and moving a
        ; differently-named setting into a shared section aligns nothing while
        ; still breaking every existing INI.
        "LauncherCleanup", Map(
            "CooldownSec", 300,
            "GracefulCloseMs", 4000,
            "HardKill", "true",
            "RequireNoGame", "true",
            "LauncherProcesses", "UbisoftConnect.exe|upc.exe|EpicGamesLauncher.exe|EADesktop.exe|EALauncher.exe|Origin.exe|Battle.net.exe|RockstarGamesLauncher.exe|GalaxyClient.exe|RiotClientServices.exe|RiotClientUx.exe|wgc.exe|Heroic.exe|UbisoftConnectService.exe|UplayWebCore.exe|UplayService.exe|EpicWebHelper.exe|EABackgroundService.exe|BlizzardUpdateAgent.exe|Agent.exe|RockstarService.exe|SocialClubHelper.exe|GalaxyClientService.exe|GalaxyCommunication.exe|RiotClientUxRender.exe|legendary.exe|gogdl.exe|nile.exe"
        ),
        "Cursor", Map(
            "ParkOnGameStart", "true",
            "ParkOnSteamReturn", "true",
            "ForegroundPollMs", 500
        ),
        "RTSS", Map(
            "EnableIntegration", "true",
            "Path", "C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe",
            "UseDllIntegration", "true",
            "OverlayControlMode", "separate",
            "OverlayToggleShortcut", "^+o",
            "OverlayOnShortcut", "^+1",
            "OverlayOffShortcut", "^+2",
            "FrameLimiterControlMode", "separate",
            "PresetFrameCap", 158,
            "CustomFrameCap", 158,
            "RestoreFrameLimitOnStartup", "true",
            "EnableElevatedFrameCapWrites", "false",
            "LastFrameCapMode", "",
            "LastFrameCapFps", 0,
            "CustomFrameCapShortcut", "^+f",
            "FrameLimiterOnShortcut", "^+5",
            "FrameLimiterOffShortcut", "^+6"
        )
    )
}

EnsureSettingsFile() {
    global IniPath, SettingsSchemaVersion, ControllerMap, ControllerMapDisplay
    RetireStartupSplashSettings()
    RetireQuickControlSettings()
    RetireDesktopAutoMouseSettings()
    MigrateRtssPresetFrameCap()
    MigrateControllerMouseSpeedToPixelsPerSecond()
    MigrateControllerPollInterval()
    MigrateSectionsToStandaloneLayout()
    defaults := DefaultSettings()
    for section, values in defaults {
        for key, value in values {
            marker := "__STEAMSHELL_XFE_MISSING__"
            current := marker
            try current := IniRead(IniPath, section, key, marker)
            if (current = marker)
                IniWrite(value, IniPath, section, key)
        }
    }
    IniWrite(SettingsSchemaVersion, IniPath, "Companion", "SettingsSchemaVersion")

    InitDefaultControllerMappings()
    for key, value in ControllerMap {
        marker := "__STEAMSHELL_XFE_MISSING__"
        current := marker
        try current := IniRead(IniPath, "ControllerMap", key, marker)
        if (current = marker)
            IniWrite(value, IniPath, "ControllerMap", key)
        if (SubStr(value, 1, 5) = "Send:" && ControllerMapDisplay.Has(key)) {
            displayKey := key ".Display"
            displayCurrent := marker
            try displayCurrent := IniRead(IniPath, "ControllerMap", displayKey, marker)
            if (displayCurrent = marker)
                IniWrite(ControllerMapDisplay[key], IniPath, "ControllerMap", displayKey)
        }
    }
}

; Schema 8 splits the former fallback cap into a named Preset and a separately
; retained Custom value. Copy first, before DefaultSettings adds the missing
; PresetFrameCap, so an existing user value remains the configured preset.
; ControllerMouseSpeed changed UNIT: it was pixels per poll tick, it is now pixels
; per second. A stored 100 therefore means a cursor that crawls rather than one
; that is unchanged, so every value migrates and not just the old default.
;
; x32, because 32 Hz is the rate the poll ACTUALLY ran at. Windows quantises
; timers to about 15.625 ms and nothing raised the resolution, so the old 16 ms
; interval -- 0.375 ms past a boundary -- could not fire before 31.25 ms. The
; conversion preserves the speed the user has been living with rather than the
; speed the setting claimed; those differed by a factor of two.
;
; Detected by RANGE, not by a schema version, matching the other migrations here.
; The old setting was clamped to 1..300 and the new one starts at 200, so any
; value at or below 300 is an old one. A converted value is at least 6400 and can
; never be re-converted.
MigrateControllerMouseSpeedToPixelsPerSecond() {
    global IniPath
    marker := "__STEAMSHELL_XFE_MISSING__"
    stored := marker
    try stored := IniRead(IniPath, "Controller", "ControllerMouseSpeed", marker)
    if (stored = marker)
        return
    value := ToInt(CleanIniValue(stored, "100"), 100)
    if (value <= 0 || value > 300)
        return
    try IniWrite(ClampInt(value * 32, 200, 12000) "",
        IniPath, "Controller", "ControllerMouseSpeed")
}


; The interval that caused the jitter. 16 sat 0.375 ms past a 15.625 ms timer
; boundary, so it waited for the next one and halved the poll rate; 15 fires on
; every boundary. Only the exact former default moves -- a deliberately chosen
; interval is a deliberate choice -- and this is only safe now that cursor speed
; is scaled by measured elapsed time rather than by the tick.
MigrateControllerPollInterval() {
    global IniPath
    marker := "__STEAMSHELL_XFE_MISSING__"
    stored := marker
    try stored := IniRead(IniPath, "Controller", "ControllerPollIntervalMs", marker)
    if (stored = marker)
        return
    if (ToInt(CleanIniValue(stored, "15"), 15) != 16)
        return
    try IniWrite("15", IniPath, "Controller", "ControllerPollIntervalMs")
}


MigrateRtssPresetFrameCap() {
    global IniPath
    marker := "__STEAMSHELL_XFE_MISSING__"
    preset := marker
    custom := marker
    try preset := IniRead(IniPath, "RTSS", "PresetFrameCap", marker)
    if (preset != marker)
        return
    try custom := IniRead(IniPath, "RTSS", "CustomFrameCap", marker)
    if (custom = marker)
        return
    try IniWrite(custom, IniPath, "RTSS", "PresetFrameCap")
}

; Schema 11 retires the "automatic mouse everywhere except these" mode. Its
; exclusion list was a hand-maintained guess at Xbox FSE's process names,
; standing in for a question Windows gives no way to ask; see the globals.
;
; This narrows behaviour for anyone who had the default on, so it is logged
; rather than done quietly: they had a pointer in every foreground application
; and will now have one only in those on AutoMouseExeList. Both keys are removed
; so a stale value cannot look like it is still doing something, and their
; absence is what makes the removal visible in the file the user edits.
RetireDesktopAutoMouseSettings() {
    global IniPath
    marker := "__STEAMSHELL_XFE_MISSING__"
    everywhere := marker
    exclusions := marker
    try everywhere := IniRead(IniPath, "Controller", "EnableDesktopAutoMouseMode", marker)
    try exclusions := IniRead(IniPath, "Controller", "DesktopAutoMouseExcludeExeList", marker)
    if (everywhere = marker && exclusions = marker)
        return
    try {
        if (everywhere != marker)
            IniDelete(IniPath, "Controller", "EnableDesktopAutoMouseMode")
        if (exclusions != marker)
            IniDelete(IniPath, "Controller", "DesktopAutoMouseExcludeExeList")
        LogLine("Settings migration: retired EnableDesktopAutoMouseMode and "
            . "DesktopAutoMouseExcludeExeList. Automatic mouse mode now applies "
            . "only in the applications on AutoMouseExeList.")
    } catch as err {
        ; Both keys are already ignored by the poll loop, so a read-only portable
        ; INI leaves dead configuration behind rather than a broken companion.
        LogLine("Settings migration: could not remove the retired automatic-mouse"
            . " keys (" err.Message ").", "Warning")
    }
}

; Schema 12 puts the settings XFE shares with standalone into the sections
; standalone puts them in.
;
; Nothing about behaviour changes. The point is discoverability: someone who has
; configured one product should find the same setting in the same place in the
; other. The automatic-mouse master switch was in [Controller] here and
; [Features] there; the launcher-cleanup tuning was in [Assist] here and
; [LauncherCleanup] there.
;
; ONLY settings that exist in both trees under the SAME name moved. A setting
; XFE names differently -- TickIntervalMs against standalone's CheckIntervalMs,
; CpuThresholdPercent against GameCPUThresholdPercent -- would not become easier
; to find by moving it into a shared section, and renaming it as well would
; change what it means: XFE's assist features are deliberately reduced versions,
; which is what the "Lite" in their switch names records.
;
; Runs BEFORE DefaultSettings fills in missing keys. The other order writes the
; default into the new location first, and the user's own value is then stranded
; in the old one where nothing reads it.
MigrateSectionsToStandaloneLayout() {
    global IniPath
    static moves := [
        ["Controller", "EnableAutoMouseMode", "Features", "EnableAutoMouseMode"],
        ["Assist", "CooldownSec", "LauncherCleanup", "CooldownSec"],
        ["Assist", "GracefulCloseMs", "LauncherCleanup", "GracefulCloseMs"],
        ["Assist", "HardKill", "LauncherCleanup", "HardKill"],
        ["Assist", "RequireNoGame", "LauncherCleanup", "RequireNoGame"],
        ["Assist", "LauncherProcesses", "LauncherCleanup", "LauncherProcesses"],
        ; Schema 13. Cursor auto-hide and pointer parking exist in both products
        ; and did the same thing under different names -- this tree's ParkYPercent
        ; and standalone's MouseParkYPercent even carried word-for-word the same
        ; explanation. The table already carried a destination KEY as well as a
        ; destination section, so a rename needed no new machinery.
        ;
        ; ParkOnGameStart, ParkOnSteamReturn and ForegroundPollMs stay in
        ; [Cursor]: standalone has no equivalent, and its
        ; EnableMouseParkOnFocusChange is a different rule (any focus change it
        ; causes) rather than a differently-named version of ParkOnSteamReturn
        ; (specifically Steam returning to the front).
        ["Cursor", "EnableAutoHide", "Features", "EnableAutoHideCursor"],
        ["Cursor", "EnableMouseParkOnBoot", "Features", "EnableMouseParkOnBoot"],
        ["Cursor", "HideDelayMs", "Timing", "MouseHideDelay"],
        ["Cursor", "ParkEdge", "MousePark", "MouseParkEdge"],
        ["Cursor", "ParkYPercent", "MousePark", "MouseParkYPercent"],
        ; Schema 18. Log rotation is not companion-specific and not
        ; game-specific: one pair of values sizes this log and the elevated
        ; helper's. [Logging] is where both now live, under these names, which
        ; lets the helper read one key regardless of --product=.
        ["Companion", "LogRotateMaxKB", "Logging", "LogRotateMaxKB"],
        ["Companion", "LogRotateBackups", "Logging", "LogRotateBackups"]]
    marker := "__STEAMSHELL_XFE_MISSING__"
    moved := 0
    for _, move in moves {
        oldValue := marker
        try oldValue := IniRead(IniPath, move[1], move[2], marker)
        if (oldValue = marker)
            continue
        ; A value already at the destination wins, which covers both a migration
        ; that was interrupted and anyone who edited the new location by hand.
        newValue := marker
        try newValue := IniRead(IniPath, move[3], move[4], marker)
        try {
            if (newValue = marker)
                IniWrite(oldValue, IniPath, move[3], move[4])
            IniDelete(IniPath, move[1], move[2])
            moved += 1
        } catch as err {
            ; A read-only portable INI leaves the value readable in its old
            ; place, which is stale configuration rather than a broken companion.
            LogLine("Settings migration: could not move [" move[1] "] " move[2]
                . " to [" move[3] "] (" err.Message ").", "Warning")
        }
    }
    if moved
        LogLine("Settings migration: moved " moved " setting(s) into the sections"
            . " standalone SteamShell uses for them.")
}

; Which section a schema-12 setting is actually in right now.
;
; Normally the new one. But MigrateSectionsToStandaloneLayout cannot write to a
; read-only INI, and a MOVE is not a RETIREMENT: a retired key means nothing any
; more and can be ignored where it lies, while a moved one still means exactly
; what it did and has to keep being honoured wherever it still is.
;
; Without this, a read-only portable install silently reverts all six moved
; settings to their defaults on upgrade -- and for EnableAutoMouseMode the
; default is ON, so a user who had deliberately turned automatic mouse mode off
; would find it back on with nothing in the log to explain it. The reader cannot
; tell "absent" from "present" on its own; it returns the default for both.
MovedSettingSection(newSection, oldSection, key) {
    global IniPath
    marker := "__STEAMSHELL_XFE_MISSING__"
    value := marker
    try value := IniRead(IniPath, newSection, key, marker)
    return value != marker ? newSection : oldSection
}

; Schema 6 retires XFE's presentation-only startup curtain. AnyFSE starts the
; companion after Steam, so the cover could only appear over an already-visible
; client. Preserve one copy of the pre-migration INI before removing the stale
; section, so custom video paths are still recoverable if needed.
; [Audio] and [Display] EnableQuickControls said what [QuickMenu] HiddenItems
; says, for two of the eleven MAIN rows. The layout manager that edits
; HiddenItems is shared with the shell now, so the pair is retired rather than
; kept as a second answer to one question.
RetireQuickControlSettings() {
    global IniPath
    for _, retiredSection in ["Audio", "Display"] {
        existing := ""
        try existing := IniRead(IniPath, retiredSection, "EnableQuickControls", "")
        if (existing = "")
            continue
        try {
            IniDelete(IniPath, retiredSection, "EnableQuickControls")
            LogLine("Settings migration: retired [" retiredSection
                . "] EnableQuickControls; Quick Menu row visibility is "
                . "[QuickMenu] HiddenItems now.")
        } catch as err {
            LogLine("Settings migration: could not remove [" retiredSection
                . "] EnableQuickControls (" err.Message ").", "Warning")
        }
    }
}

RetireStartupSplashSettings() {
    global IniPath
    sectionText := ""
    try sectionText := IniRead(IniPath, "StartupSplash")
    if (sectionText = "")
        return
    backupPath := IniPath ".pre-schema-6.bak"
    try {
        if !FileExist(backupPath)
            FileCopy(IniPath, backupPath)
        IniDelete(IniPath, "StartupSplash")
        LogLine("Settings migration: retired [StartupSplash]; backup is "
            . backupPath ".")
    } catch as err {
        ; The retired section is inert even if a read-only portable INI prevents
        ; cleanup. Do not make the companion unusable over obsolete settings.
        LogLine("Settings migration: could not remove retired [StartupSplash] ("
            . err.Message ").", "Warning")
    }
}

LoadSettings() {
    global HeartbeatSeconds, EnableQuickMenu, EnableGameDetectionMenu, GameScoreMaxRows, QuickMenuChordHoldMs
    global QuickMenuMainOrderRaw, QuickMenuHiddenItemsRaw, QuickMenuMainOrder, QuickMenuHiddenItems
    global LogRotateMaxKB, LogRotateBackups
    global EnableControllerMouseMode, EnablePersistentMouseMode, ControllerIndex, ControllerPollIntervalMs
    global EnableAutoMouseMode, AutoMouseExeListRaw, AutoMouseExeSet
    global ControllerDeadzone, ControllerMouseSpeed, ControllerMouseFastMultiplier
    global ControllerScrollIntervalMs, ControllerScrollStep, ControllerChordHoldMs
    global ControllerBackend, EnableControllerDiagnostics, EnableRawInputProbe
    global RawInputStaleMs
    global SteamMenuShortcut, SteamQuickAccessShortcut, SteamOverlayShortcut
    global EnableViewSteamActions, EnableViewTapAction, EnableViewHoldAction
    global ViewHoldMs, ViewHoldInGameMs
    global EnableGameFocusLite, EnableSteamAssistLite, EnableLauncherCleanupLite
    global AssistTickIntervalMs, AssistCpuThresholdPercent, AssistForegroundStableSec
    global AssistCooldownSec, AssistGracefulCloseMs, AssistHardKill, AssistRequireNoGame
    global AssistLauncherProcesses, AssistProtectedProcesses, AssistIgnoreForegroundProcesses
    global AssistSuspendOnShellOverlay, AssistShellOverlayProcesses
    global EnableStartupPrograms, StartupProgramDelayMs, StartupProgramStaggerMs
    global StartupLaunchDeElevated, StartupWindowMode
    global EnableAutoHideCursor, MouseHideDelay, EnableMouseParkOnBoot
    global ParkOnGameStart, ParkOnSteamReturn, MouseParkEdge, ParkYPercent
    global ForegroundPollMs
    global EnableRTSSIntegration, RtssPath, RtssUseDllIntegration
    global RtssOverlayControlMode
    global RtssOverlayToggleShortcut, RtssOverlayOnShortcut, RtssOverlayOffShortcut
    global RtssFrameLimiterControlMode, RtssPresetFrameCap, RtssCustomFrameCap
    global RtssCustomFrameCapShortcut, RtssFrameLimiterOnShortcut, RtssFrameLimiterOffShortcut
    global RtssRestoreFrameLimitOnStartup, RtssLastFrameCapMode, RtssLastFrameCapFps
    global RtssElevatedFrameCapWrites, RtssFrameCapWriteBlocked
    ; The game-score and Assist weighting keys. Every one of these is read a few
    ; dozen lines below and none was declared, which was survivable only because
    ; they are super-globals -- the assignment reached the right variable anyway.
    ; The block, not the behaviour, was wrong.
    global EnableGameScoreLogging, GameLogMode, GameLogTopN, GameLogIntervalMs
    global GameLogIncludeTitles
    global AssistScoreFullscreen, AssistScoreBorderlessLarge, AssistScoreTitleBonus
    global AssistScoreCpuAboveThreshold, AssistScoreCpuNonZeroBonus
    global AssistScoreAudioActive, AssistFullscreenTolerance
    global AssistFullscreenPosTolerancePx, AssistAllowZeroCpuAsCandidate
    global EnableAudioAssist, AudioPeakThreshold

    ; Floor of 5s rather than 15s: during a short diagnostic run inside Xbox FSE
    ; the heartbeat is the only proof the process is still alive, and a 60s gap
    ; is long enough to hide a death for the whole test.
    HeartbeatSeconds := ReadInt("Companion", "HeartbeatSeconds", 60, 5, 3600)
    LogRotateMaxKB := ReadInt(MovedSettingSection("Logging", "Companion", "LogRotateMaxKB"), "LogRotateMaxKB", 256, 32, 8192)
    LogRotateBackups := ReadInt(MovedSettingSection("Logging", "Companion", "LogRotateBackups"), "LogRotateBackups", 2, 0, 10)
    EnableQuickMenu := ReadBool("QuickMenu", "Enable", true)
    EnableGameDetectionMenu := ReadBool("QuickMenu", "ShowGameDetection", true)
    QuickMenuMainOrderRaw := ReadText("QuickMenu", "MainOrder", QuickMenuMainOrderRaw)
    QuickMenuHiddenItemsRaw := ReadText("QuickMenu", "HiddenItems", "")
    QuickMenuMainOrder := ParseQuickMenuMainOrder(QuickMenuMainOrderRaw)
    QuickMenuHiddenItems := Map()
    for _, hiddenName in StrSplit(QuickMenuHiddenItemsRaw, "|") {
        trimmedName := StrLower(Trim(hiddenName))
        if (trimmedName != "")
            QuickMenuHiddenItems[trimmedName] := true
    }
    GameScoreMaxRows := ReadInt("QuickMenu", "GameScoreMaxRows", 8, 1, 20)
    QuickMenuChordHoldMs := ReadInt("QuickMenu", "ChordHoldMs", 500, 250, 3000)
    ; Resolved through QuickMenuApplyAccent so an unknown preset or malformed hex
    ; falls back to the default instead of reaching the painter.
    QuickMenuApplyAccent(
        ReadText("QuickMenu", "AccentColor", "Purple"),
        ReadText("QuickMenu", "AccentColorCustom", "107C10"))
    EnableControllerMouseMode := ReadBool("Controller", "EnableControllerMouseMode", true)
    EnablePersistentMouseMode := ReadBool(
        "Controller", "EnablePersistentMouseMode", false)
    ; Automatic mouse mode. Both gates must pass: the toggle allows the feature,
    ; the list decides where it applies.
    EnableAutoMouseMode := ReadBool(MovedSettingSection("Features", "Controller", "EnableAutoMouseMode"), "EnableAutoMouseMode", true)
    AutoMouseExeListRaw := ReadText("Controller", "AutoMouseExeList",
        DefaultAutoMouseExeList())
    AutoMouseExeSet := ProcessNameSetFromList(AutoMouseExeListRaw)
    ControllerBackend := StrLower(ReadText("Controller", "Backend", "auto"))
    if (ControllerBackend != "xinput" && ControllerBackend != "gameinput"
        && ControllerBackend != "rawinput" && ControllerBackend != "auto") {
        LogLine("Unknown controller backend '" ControllerBackend
            . "'; using Auto.", "Warning")
        ControllerBackend := "auto"
    }
    EnableControllerDiagnostics := ReadBool("Controller", "DiagnosticLogging", false)
    EnableRawInputProbe := ReadBool("Controller", "RawInputProbe", false)
    RawInputStaleMs := ReadInt("Controller", "RawInputStaleMs", 5000, 500, 60000)
    ControllerIndex := ReadInt("Controller", "ControllerIndex", 0, 0, 3)
    ControllerPollIntervalMs := ReadInt("Controller", "ControllerPollIntervalMs", 15, 8, 100)
    ControllerDeadzone := ReadInt("Controller", "ControllerDeadzone", 3000, 0, 32000)
    ; Bounds match standalone's deliberately: this is one setting, and the Quick
    ; Menu row that steps it is shared. A range the row can leave -- or one the
    ; row cannot reach -- makes the row lie, showing a value the next reload
    ; clamps away. Widened rather than narrowed so no configured value is ever
    ; silently reduced.
    ControllerMouseSpeed := ReadInt("Controller", "ControllerMouseSpeed", 3200, 200, 12000)
    ControllerMouseFastMultiplier := ReadNumber("Controller", "ControllerMouseFastMultiplier", 2.5, 1, 6)
    ControllerScrollIntervalMs := ReadInt("Controller", "ControllerScrollIntervalMs", 80, 20, 500)
    ControllerScrollStep := ReadInt("Controller", "ControllerScrollStep", 1, 1, 10)
    ControllerChordHoldMs := ReadInt("Controller", "ControllerChordHoldMs", 500, 100, 3000)
    SteamMenuShortcut := ReadText("Steam", "MenuShortcut", "^1")
    SteamQuickAccessShortcut := ReadText("Steam", "QuickAccessShortcut", "^2")
    SteamOverlayShortcut := ReadText("Steam", "OverlayShortcut", "+{Tab}")
    EnableViewSteamActions := ReadBool("Steam", "EnableViewButtonActions", true)
    EnableViewTapAction := ReadBool("Steam", "EnableViewTapAction", true)
    EnableViewHoldAction := ReadBool("Steam", "EnableViewHoldAction", true)
    ViewHoldMs := ReadInt("Steam", "ViewHoldMs", 500, 200, 5000)
    ViewHoldInGameMs := ReadInt("Steam", "ViewHoldInGameMs", 1000, 200, 5000)
    EnableStartupPrograms := ReadBool("StartupPrograms", "Enable", true)
    StartupProgramDelayMs := ReadInt("StartupPrograms", "DelayMs", 2000, 0, 600000)
    StartupProgramStaggerMs := ReadInt("StartupPrograms", "StaggerMs", 1200, 0, 30000)
    StartupLaunchDeElevated := ReadBool("StartupPrograms", "LaunchDeElevated", true)
    StartupWindowMode := NormalizeWindowMode(
        ReadText("StartupPrograms", "WindowMode", "Hidden"))
    LoadStartupPrograms()
    EnableGameFocusLite := ReadBool("Assist", "EnableGameFocusLite", true)
    EnableSteamAssistLite := ReadBool("Assist", "EnableSteamAssistLite", true)
    EnableLauncherCleanupLite := ReadBool("Assist", "EnableLauncherCleanupLite", true)
    AssistTickIntervalMs := ReadInt("Assist", "TickIntervalMs", 2000, 500, 30000)
    AssistCpuThresholdPercent := ReadInt("Assist", "CpuThresholdPercent", 12, 0, 100)
    ; Recorded before the drift check reads it back, so a fresh install writes
    ; the truth once rather than reporting itself as moved forever.
    RecordXfeInstallationPaths()
    ; Derived, not read. [Logging] EnableGameScoreLogging used to be its own key
    ; here, which meant the two halves of the shared logger's gate could
    ; disagree: GameLogMode=TOPN with the bool left at its default logged
    ; nothing, and no message said why. See NormalizeGameLogMode.
    GameLogMode := NormalizeGameLogMode(ReadText("Logging", "GameLogMode", "OFF"))
    EnableGameScoreLogging := GameLogMode != "OFF"
    GameLogTopN := ReadInt("Logging", "GameLogTopN", 3, 1, 10)
    GameLogIntervalMs := ReadInt("Logging", "GameLogIntervalMs", 3000, 250, 60000)
    GameLogIncludeTitles := ReadBool("Logging", "GameLogIncludeTitles", true)
    AssistScoreFullscreen := ReadInt("Assist", "ScoreFullscreen", 70, 0, 300)
    AssistScoreBorderlessLarge := ReadInt("Assist", "ScoreBorderlessLarge", 45, 0, 300)
    AssistScoreTitleBonus := ReadInt("Assist", "ScoreTitleBonus", 10, 0, 300)
    AssistScoreCpuAboveThreshold := ReadInt("Assist", "ScoreCpuAboveThreshold", 20, 0, 300)
    AssistScoreCpuNonZeroBonus := ReadInt("Assist", "ScoreCpuNonZeroBonus", 15, 0, 300)
    AssistScoreAudioActive := ReadInt("Assist", "ScoreAudioActive", 30, 0, 200)
    AssistFullscreenTolerance := ReadNumber("Assist", "FullscreenTolerance", 0.98, 0.50, 1.00)
    AssistFullscreenPosTolerancePx := ReadInt("Assist", "FullscreenPosTolerancePx", 2, 0, 200)
    AssistAllowZeroCpuAsCandidate := ReadBool("Assist", "AllowZeroCpuAsCandidate", true)
    EnableAudioAssist := ReadBool("Assist", "EnableAudioAssist", true)
    AudioPeakThreshold := ReadNumber("Assist", "AudioPeakThreshold", 0.02, 0.0, 1.0)
    AssistForegroundStableSec := ReadInt("Assist", "ForegroundStableSec", 30, 5, 600)
    AssistCooldownSec := ReadInt(MovedSettingSection("LauncherCleanup", "Assist", "CooldownSec"), "CooldownSec", 300, 30, 7200)
    AssistGracefulCloseMs := ReadInt(MovedSettingSection("LauncherCleanup", "Assist", "GracefulCloseMs"), "GracefulCloseMs", 4000, 500, 30000)
    AssistHardKill := ReadBool(MovedSettingSection("LauncherCleanup", "Assist", "HardKill"), "HardKill", true)
    AssistRequireNoGame := ReadBool(MovedSettingSection("LauncherCleanup", "Assist", "RequireNoGame"), "RequireNoGame", true)
    AssistLauncherProcesses := ReadText(MovedSettingSection("LauncherCleanup", "Assist", "LauncherProcesses"), "LauncherProcesses", AssistLauncherProcesses)
    AssistProtectedProcesses := ReadText("Assist", "ProtectedProcesses", AssistProtectedProcesses)
    AssistIgnoreForegroundProcesses := ReadText("Assist", "IgnoreForegroundProcesses",
        AssistIgnoreForegroundProcesses)
    AssistSuspendOnShellOverlay := ReadBool("Assist", "SuspendOnShellOverlay", true)
    AssistShellOverlayProcesses := ReadText("Assist", "ShellOverlayProcesses",
        AssistShellOverlayProcesses)
    EnableAutoHideCursor := ReadBool(MovedSettingSection("Features", "Cursor", "EnableAutoHideCursor"), "EnableAutoHideCursor", true)
    ; 0 rather than a 250ms floor, and 60000 rather than 10000: the shared Quick
    ; Menu row offers IMMEDIATE, and a floor the row can step below makes the row
    ; lie -- it would read IMMEDIATE while the next reload clamped the value back
    ; up to 250 and the cursor kept waiting.
    MouseHideDelay := ReadInt(MovedSettingSection("Timing", "Cursor", "MouseHideDelay"), "MouseHideDelay", 1000, 0, 60000)
    EnableMouseParkOnBoot := ReadBool(MovedSettingSection("Features", "Cursor", "EnableMouseParkOnBoot"), "EnableMouseParkOnBoot", true)
    ParkOnGameStart := ReadBool("Cursor", "ParkOnGameStart", true)
    ParkOnSteamReturn := ReadBool("Cursor", "ParkOnSteamReturn", true)
    ; A STRING, not a boolean. This read `... = "left"`, which assigns the RESULT
    ; of that comparison -- so MouseParkEdge held 1 or 0 and every later test of
    ; `MouseParkEdge = "left"` compared a number against a word and was always false.
    ; The cursor parked on the right edge no matter what the setting said, and
    ; the assertion covering it passed because it matched the TEXT of the
    ; comparison rather than the type of the variable.
    MouseParkEdge := StrLower(Trim(ReadText(
        MovedSettingSection("MousePark", "Cursor", "MouseParkEdge"), "MouseParkEdge", "right")))
    if (MouseParkEdge != "left" && MouseParkEdge != "right")
        MouseParkEdge := "right"
    ParkYPercent := ReadNumber(MovedSettingSection("MousePark", "Cursor", "MouseParkYPercent"), "MouseParkYPercent", 0.50, 0.05, 0.95)
    ForegroundPollMs := ReadInt("Cursor", "ForegroundPollMs", 500, 250, 5000)
    EnableRTSSIntegration := ReadBool("RTSS", "EnableIntegration", true)
    RtssPath := ReadText("RTSS", "Path", "C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe")
    RtssUseDllIntegration := ReadBool("RTSS", "UseDllIntegration", true)
    if !RtssUseDllIntegration
        ShutdownRtssHooksApi()
    RtssOverlayControlMode := StrLower(ReadText("RTSS", "OverlayControlMode", "separate"))
    RtssOverlayToggleShortcut := ReadText("RTSS", "OverlayToggleShortcut", "^+o")
    RtssOverlayOnShortcut := ReadText("RTSS", "OverlayOnShortcut", "^+1")
    RtssOverlayOffShortcut := ReadText("RTSS", "OverlayOffShortcut", "^+2")
    RtssFrameLimiterControlMode := StrLower(ReadText("RTSS", "FrameLimiterControlMode", "separate"))
    RtssPresetFrameCap := ReadInt("RTSS", "PresetFrameCap", 158, 0, 1000)
    RtssCustomFrameCap := ReadInt("RTSS", "CustomFrameCap", 158, 10, 1000)
    RtssRestoreFrameLimitOnStartup := ReadBool("RTSS", "RestoreFrameLimitOnStartup", true)
    ; DEFAULT FALSE, and that default is the feature. XFE is chosen because
    ; nothing about it is elevated; this is the user deciding otherwise for the
    ; one thing that cannot work any other way. See StartElevatedRtssHelper.
    RtssElevatedFrameCapWrites := ReadBool(
        "RTSS", "EnableElevatedFrameCapWrites", false)
    ; Reloading settings re-arms the frame cap.
    ;
    ; RtssFrameCapWriteBlocked latches on the first failed write so the row
    ; stops accepting presses it cannot honour. That is right during a session
    ; and wrong across a settings change: turning the elevated write on, or
    ; correcting [RTSS] Path, would otherwise leave the row read-only until the
    ; next sign-in with no way to tell why. The latch costs one failed write to
    ; re-establish, so clearing it here is cheap.
    RtssFrameCapWriteBlocked := false
    RtssLastFrameCapMode := StrLower(Trim(ReadText("RTSS", "LastFrameCapMode", "")))
    if !RtssFrameCapModeIsKnown(RtssLastFrameCapMode)
        RtssLastFrameCapMode := ""
    RtssLastFrameCapFps := ReadInt("RTSS", "LastFrameCapFps", 0, 0, 1000)
    RtssCustomFrameCapShortcut := ReadText("RTSS", "CustomFrameCapShortcut", "^+f")
    RtssFrameLimiterOnShortcut := ReadText("RTSS", "FrameLimiterOnShortcut", "^+5")
    RtssFrameLimiterOffShortcut := ReadText("RTSS", "FrameLimiterOffShortcut", "^+6")
    LoadControllerMappings()
}

LoadControllerMappings() {
    ; Thin wrapper over the shared reader. Nothing to migrate: this product never
    ; shipped the Start.Short/Start.Long pair the shell rewrites.
    LoadControllerMappingsFromIni()
}

ApplyRuntimeTimers() {
    global ControllerPollIntervalMs, EnableAutoHideCursor, ForegroundPollMs
    global HeartbeatSeconds
    global EnableControllerDiagnostics, ControllerDiagnosticIntervalMs
    global EnableGameFocusLite, EnableSteamAssistLite, EnableLauncherCleanupLite
    global AssistTickIntervalMs, AssistHardKill, AssistPendingHardKillPids
    global CompanionDisabled
    SetTimer(PollController, 0)
    SetTimer(MouseWatch, 0)
    SetTimer(ObserveForeground, 0)
    SetTimer(Heartbeat, 0)
    SetTimer(ControllerDiagnosticTick, 0)
    SetTimer(AssistTick, 0)
    if (CompanionDisabled || !EnableLauncherCleanupLite || !AssistHardKill) {
        SetTimer(AssistHardKillLaunchers, 0)
        AssistPendingHardKillPids := Map()
    }
    ; BEFORE the disabled return, deliberately. Disabling the companion stops it
    ; ACTING; this only observes, and the tray still offers Open Settings while
    ; disabled. Stopping the history here would empty the picker in precisely the
    ; state somebody is in when they are working out what to configure.
    SetTimer(RecentAppsTick, RecentAppsIntervalMs())
    if CompanionDisabled
        return
    SetTimer(PollController, ControllerPollIntervalMs)
    ; The assist timer only runs when at least one feature is enabled, so a
    ; default install does no extra polling at all.
    if (EnableGameFocusLite || EnableSteamAssistLite || EnableLauncherCleanupLite) {
        SetTimer(AssistTick, AssistTickIntervalMs)
        LogLine("Assist enabled: gameFocus=" (EnableGameFocusLite ? "on" : "off")
            . ", steamAssist=" (EnableSteamAssistLite ? "on" : "off")
            . ", launcherCleanup=" (EnableLauncherCleanupLite ? "on" : "off")
            . ", tick=" AssistTickIntervalMs "ms.")
    }
    if EnableControllerDiagnostics {
        SetTimer(ControllerDiagnosticTick, ControllerDiagnosticIntervalMs)
        LogLine("Controller diagnostic logging is enabled (all XInput slots).")
    }
    ; Registration is one-time and self-guarded, so calling this on every reload
    ; is safe; RawInput cannot be unregistered mid-session in a useful way.
    RawInputProbeStart()
    ; Sleep/resume. OnMessage with the same callback twice is a no-op, so this is
    ; safe to re-apply on every reload alongside the timers.
    OnMessage(0x0218, PowerBroadcastMessage)
    ; Device arrival and removal, so a controller plugged in while the XInput
    ; sweep is backed off is picked up on the next poll. Purely an accelerator.
    OnMessage(0x0219, DeviceChangeMessage)
    if EnableAutoHideCursor
        SetTimer(MouseWatch, 250)
    SetTimer(ObserveForeground, ForegroundPollMs)
    SetTimer(Heartbeat, HeartbeatSeconds * 1000)
}

SetCompanionHotkeysEnabled(enabled) {
    for key in ["^!+q", "^!+s", "^!+p", "^!+r", "^!+i", "^!+d", "^!+x"] {
        try Hotkey(key, enabled ? "On" : "Off")
    }
}

; Seam for SteamShell-Shared.ahk. The entries this product offers, in order;
; anything that is not a Map is a separator.
;
; Built fresh on every refresh rather than renamed in place. The old code created
; the menu once and mutated it -- Rename("Disable","Enable"), Enable/Disable on
; the Quick Menu entry -- which worked for a label that only ever changed text
; and made a conditional entry impossible. The moved-installation entry below is
; the first thing that needed one.
ProductTrayItems() {
    global CompanionDisabled
    items := []
    if (InstallationRecordAlert(A_ScriptDir, A_ScriptDir, "Portable") != "") {
        ; The companion is not the installer, so this opens its own Settings
        ; rather than a Setup Assistant it does not have. SteamShell.exe is what
        ; re-records the install.
        items.Push(Map(
            "label", "Installation moved — open Settings",
            "handler", TrayOpenSettings))
        items.Push("")
    }
    items.Push(Map(
        "label", "Open Quick Menu", "handler", TrayOpenQuickMenu,
        "disabled", CompanionDisabled))
    items.Push(Map("label", "Open Settings", "handler", TrayOpenSettings))
    items.Push("")
    items.Push(Map(
        "label", CompanionDisabled ? "Enable" : "Disable",
        "handler", ToggleCompanionDisabled))
    items.Push(Map("label", "Exit", "handler", ExitCompanion))
    return items
}

ProductTrayBaseTip() {
    global CompanionDisabled
    return "SteamShell XFE"
        . (CompanionDisabled ? " — Disabled" : "")
        . (InstallationRecordAlert(A_ScriptDir, A_ScriptDir, "Portable") != ""
            ? " — installation moved" : "")
}

SetCompanionDisabled(disabled) {
    global CompanionDisabled, ControllerNeedsFreshBaseline
    global QuickMenuVisible, MouseHidden
    global LearnActive, _ShortcutCap, AssistPendingHardKillPids
    disabled := disabled ? true : false
    if (CompanionDisabled = disabled)
        return
    CompanionDisabled := disabled
    if disabled {
        ControllerNeedsFreshBaseline := true
        ; Let the poll loop clear its private edge/hold state before its timer is
        ; stopped, otherwise a button released while disabled could fire as a
        ; stale release action after re-enabling.
        PollController()
        ApplyRuntimeTimers()
        SetTimer(RunStartupPrograms, 0)
        SetTimer(ParkCursor, 0)
        SetTimer(RunScreenProbe, 0)
        SetTimer(AssistHardKillLaunchers, 0)
        AssistPendingHardKillPids := Map()
        SetTimer(RefreshQuickMenuAfterRtssStart, 0)
        SetTimer(QuickMenuDisplayReflow, 0)
        if LearnActive
            CloseControllerLearner()
        if IsObject(_ShortcutCap)
            RecordShortcutCancel()
        if QuickMenuVisible
            HideQuickMenu()
        try SendInput("{LButton up}{RButton up}{MButton up}"
            . "{Ctrl up}{Alt up}{Shift up}{LWin up}{RWin up}")
        try SystemCursor("Show")
        MouseHidden := false
        SetCompanionHotkeysEnabled(false)
        LogLine("Companion disabled from the notification-area menu.")
    } else {
        SetCompanionHotkeysEnabled(true)
        RawInputResetDeviceLock("companion re-enabled")
        RawInputReregister()
        ApplyRuntimeTimers()
        LogLine("Companion enabled from the notification-area menu.")
    }
    BuildProductTrayMenu()
}

ToggleCompanionDisabled(*) {
    global CompanionDisabled
    SetCompanionDisabled(!CompanionDisabled)
}

TrayOpenSettings(*) {
    ShowSettings()
}

ReloadSettings(*) {
    global QuickMenuVisible, SettingsVisible, GameInputFailed, GameInputReady
    EnsureSettingsFile()
    LoadSettings()
    ; Clear the failure latch so switching the backend in Settings can retry
    ; GameInput without restarting the companion.
    if !GameInputReady
        GameInputFailed := false
    ApplyRuntimeTimers()
    ; Both directions, immediately. An elevated process the user has just asked
    ; to stop, which keeps running until the next sign-in, is not a control.
    SyncElevatedRtssHelperWithSettings()
    if QuickMenuVisible
        QuickMenuBuildGui()
    if SettingsVisible
        SettingsPopulate()
    ShowNotification("Settings reloaded", "Info")
}

Heartbeat() {
    global AppVersion, LastHeartbeatStamp
    now := A_Now
    ; The resume detector that depends on nothing being delivered to us moved to
    ; ControllerResumeGapCheck in SteamShell-Shared.ahk, and PollController drives
    ; it in both products now. It used to live here, which meant the shell -- with
    ; no heartbeat of its own -- had no wall-clock resume detection at all.
    ;
    ; Driving it from the controller poll rather than from here also makes it
    ; self-gating: the check runs exactly when something is reading the pad, and
    ; the cadence it reports is the poll interval rather than a 60-second beat, so
    ; a resume is now noticed within seconds instead of within minutes.
    LastHeartbeatStamp := now
    LogLine("Heartbeat: XFE companion " AppVersion " is responsive.")
}


OnCompanionExit(exitReason, exitCode) {
    ReleaseControllerMouseButtons()
    global DisplayPendingOldMode, DisplayPendingOldScale, AssistPendingHardKillPids
    SetTimer(PollController, 0)
    SetTimer(MouseWatch, 0)
    SetTimer(ObserveForeground, 0)
    SetTimer(ControllerDiagnosticTick, 0)
    SetTimer(AssistTick, 0)
    SetTimer(AssistHardKillLaunchers, 0)
    AssistPendingHardKillPids := Map()
    ShutdownGameInput()
    ShutdownRtssHooksApi()
    ; The shared teardown, directly. This went through a one-line
    ; ReleaseQuickMenuPaintResources that only called it, and standalone had a
    ; function of the same name doing something else -- one name, two routines,
    ; which is the drift the manifests exist to catch and the one form of it a
    ; name-keyed check cannot see.
    QuickMenuDestroyWindow()
    if IsObject(DisplayPendingOldMode) {
        ApplyPrimaryDisplayMode(DisplayPendingOldMode)
        if IsObject(DisplayPendingOldScale)
            ApplyPrimaryDisplayScale(DisplayPendingOldScale["percent"])
    }
    try SystemCursor("Show")
    LogLine("Stopped (" exitReason ", code " exitCode ").")
}

ExitCompanion(*) {
    ExitApp()
}

NormalizePath(path) {
    path := Trim(path, " `t`r`n`"")
    return path
}

IsOurWindow(hwnd) {
    global ScriptPid
    if !hwnd
        return false
    pid := 0
    try pid := WinGetPID("ahk_id " hwnd)
    return pid = ScriptPid
}

; Every companion-owned settings/editor surface gets temporary controller mouse
; behavior without changing the persisted Mouse Mode toggle. Native dialogs are
; covered by SettingsDialogActive because their process may not be ours.
ControllerSettingsSurfaceActive() {
    global SettingsDialogActive
    if SettingsDialogActive
        return true
    hwnd := 0
    try hwnd := WinExist("A")
    return hwnd && IsOurWindow(hwnd)
}

SettingsPrimaryActive() {
    global SettingsGui, SettingsVisible
    if (!SettingsVisible || !IsSet(SettingsGui))
        return false
    try return WinActive("ahk_id " SettingsGui.Hwnd) != 0
    return false
}

; ------------------------------------------------------------------------------
; Dialogs opened by an always-on-top window
;
; Every window this companion shows is +AlwaysOnTop, because that is the only
; thing that makes a window appear over Xbox FSE at all -- FSE is a fullscreen
; window, so a merely focused window still renders behind it.
;
; The cost is that a plain MsgBox or FileSelect appears BEHIND its own owner. An
; owned dialog is normally kept above its owner, but that only holds within a
; z-order band: a non-topmost dialog cannot rise above a topmost window, even its
; own parent. So the dialog has the focus and the keyboard while being invisible,
; which reads as the application having frozen.
;
; Dropping the owner's topmost bit for the duration is the wrong fix. Inside FSE
; that hides the owner behind FSE, and the dialog with it.
; ------------------------------------------------------------------------------


; FileSelect has no equivalent option, so the dialog is promoted after it appears.
;
; The timer does fire while FileSelect blocks: the dialog runs its own message
; pump, which dispatches the WM_TIMER that drives AutoHotkey's timers. Promotion
; repeats because the common file dialog can be recreated (switching between
; places, or a nested overwrite prompt).
TopmostFileSelect(options, rootDir := "", prompt := "", filter := "") {
    SetTimer(PromoteDialogsToTopmost, 60)
    selected := ""
    ; Braces required. A braceless `try` body swallows the following clause, which
    ; is the same binding trap that has bitten this file before.
    try {
        selected := FileSelect(options, rootDir, prompt, filter)
    }
    SetTimer(PromoteDialogsToTopmost, 0)
    return selected
}

PromoteDialogsToTopmost() {
    global ScriptPid
    windows := []
    try windows := WinGetList("ahk_class #32770 ahk_pid " ScriptPid)
    for _, hwnd in windows {
        try WinSetAlwaysOnTop(1, "ahk_id " hwnd)
    }
}


; Hidden GUI measurements can omit the scaled non-client frame and title bar.
; Once a window is visible, measure its real outer rectangle and correct the
; position from that rather than the earlier estimate.
RecenterVisibleGuiOnMonitorActual(guiObj, monitorIndex) {
    monitorIndex := ClampInt(monitorIndex, 1, MonitorGetCount())
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    try {
        WinGetPos(&visibleX, &visibleY, &visibleW, &visibleH,
            "ahk_id " guiObj.Hwnd)
    } catch {
        return false
    }
    if (visibleW <= 0 || visibleH <= 0)
        return false
    CenteredPosition(left, top, right, bottom, visibleW, visibleH,
        &correctedX, &correctedY)
    return MoveWindowPhysical(guiObj.Hwnd, correctedX, correctedY)
}

; Seams for the shared MouseWatch. Nothing stops the pass here -- this product
; has no desktop shell to hand the cursor over to, so the only gate is the
; setting itself.
MouseWatchDisabled() {
    global EnableAutoHideCursor
    return !EnableAutoHideCursor
}

; Settings is pointer-driven, so the cursor stays put while it is open. The
; Quick Menu is deliberately NOT listed: it is navigated with the D-pad, so the
; cursor should hide there as it does everywhere else -- moving the mouse brings
; it straight back.
;
; This is asked AFTER movement tracking, so an open Settings window still lets a
; moved mouse re-show the cursor; only hiding is declined. The shell's gate runs
; before tracking instead, which is why these are two seams and not one.
MouseWatchHoldsCursorVisible() {
    global SettingsVisible
    return SettingsVisible
}

; Puts the pointer out of the way: hard against one vertical edge, at
; ParkYPercent down it. The right edge is the default because a cursor that
; briefly reappears there is the least visible on a TV, and because Xbox FSE and
; Steam both keep their navigation on the left.
;
; The inset is 2px rather than 0: at the exact edge some surfaces read the
; pointer as having left the window entirely and drop their hover state.
ParkCursor(*) {
    global MouseParkEdge, ParkYPercent, LastMouseX, LastMouseY, LastMouseMoveTick
    global EnableAutoHideCursor, MouseHidden
    static INSET := 2
    targetX := 0
    targetY := 0
    placed := false
    hwnd := 0
    try hwnd := WinExist("A")
    if hwnd {
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            targetX := MouseParkEdge = "left"
                ? wx + Min(INSET, Max(0, ww - 1))
                : wx + Max(0, ww - 1 - INSET)
            targetY := wy + Round(wh * ParkYPercent)
            placed := true
        }
    }
    if !placed {
        MouseGetPos(&mx, &my)
        GetMonitorWorkAreaForPoint(mx, my, &left, &top, &right, &bottom)
        targetX := MouseParkEdge = "left" ? left + INSET : right - 1 - INSET
        targetY := top + Round((bottom - top) * ParkYPercent)
    }
    DllCall("SetCursorPos", "Int", targetX, "Int", targetY)
    LastMouseX := targetX
    LastMouseY := targetY
    LastMouseMoveTick := A_TickCount
    if EnableAutoHideCursor {
        SystemCursor("Hide")
        MouseHidden := true
    }
}

; Park only if the window which caused the delayed request still owns the
; foreground. A game can hand focus to a launcher, dialog, or one of our own
; windows during the delay; moving the pointer there would be surprising.
ParkCursorIfStillForeground(hwnd, reason := "") {
    current := 0
    try current := WinExist("A")
    if (!current || current != hwnd || IsOurWindow(current))
        return
    ParkCursor()
    if (reason != "")
        LogLine("Cursor parked: " reason ".")
}

; The companion cannot ask Windows whether an arbitrary executable is a game,
; so use the same conservative shape test as the Assist engine: a visible,
; titled, non-shell/non-launcher window covering most of its monitor. Explicit
; shell-overlay exclusions keep Xbox FSE, Game Bar, and the task switcher from
; being mistaken for a newly opened game.
ForegroundWindowLooksGameLike(hwnd, exe) {
    global AssistShellOverlayProcesses
    if (!hwnd || IsOurWindow(hwnd) || IsSteamProcess(exe))
        return false
    exe := StrLower(exe)
    if AssistForegroundIsProtected(exe)
        return false
    cls := ""
    try cls := WinGetClass("ahk_id " hwnd)
    for _, entry in StrSplit(AssistShellOverlayProcesses, "|") {
        entry := StrLower(Trim(entry))
        if (entry = "")
            continue
        if (SubStr(entry, 1, 6) = "class:") {
            if (StrLower(cls) = SubStr(entry, 7))
                return false
        } else if (exe = entry) {
            return false
        }
    }
    if !DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
        return false
    if IsCloaked(hwnd)
        return false
    title := ""
    pid := 0
    try title := WinGetTitle("ahk_id " hwnd)
    try pid := WinGetPID("ahk_id " hwnd)
    x := 0, y := 0, w := 0, h := 0
    try {
        WinGetPos(&windowX, &windowY, &windowW, &windowH, "ahk_id " hwnd)
        x := windowX, y := windowY, w := windowW, h := windowH
    }
    if (title = "" || w <= 0 || h <= 0)
        return false
    return AssistWindowLooksLikeGame(Map(
        "hwnd", hwnd, "title", title, "class", cls, "exe", exe,
        "pid", pid, "x", x, "y", y, "w", w, "h", h,
        "ours", false))
}

ObserveForeground() {
    global LastObservedForegroundExe, LastObservedForegroundHwnd
    global LastObservedForegroundWasGame, ParkOnGameStart, ParkOnSteamReturn
    global LastObservedGameExe
    hwnd := 0
    try hwnd := WinExist("A")
    if (!hwnd || IsOurWindow(hwnd))
        return
    exe := ""
    try exe := StrLower(WinGetProcessName("ahk_id " hwnd))
    if (exe = "")
        return
    wasSteam := LastObservedForegroundExe = "steam.exe" || LastObservedForegroundExe = "steamwebhelper.exe"
    isSteam := exe = "steam.exe" || exe = "steamwebhelper.exe"
    wasGame := LastObservedForegroundWasGame
    previous := LastObservedForegroundExe
    previousHwnd := LastObservedForegroundHwnd
    isGame := ForegroundWindowLooksGameLike(hwnd, exe)
    LastObservedForegroundExe := exe
    LastObservedForegroundHwnd := hwnd
    LastObservedForegroundWasGame := isGame
    if (isGame && !isSteam)
        LastObservedGameExe := exe
    if (ParkOnGameStart && isGame && (!wasGame || hwnd != previousHwnd))
        SetTimer(ParkCursorIfStillForeground.Bind(hwnd,
            "game/fullscreen window entered the foreground"), -500)
    if (ParkOnSteamReturn && isSteam && !wasSteam && previous != "")
        SetTimer(ParkCursor, -500)
}

; ==============================================================================
; GameInput backend
;
; Xbox FSE appears to withhold View, Menu, L3, and R3 from background XInput
; consumers. GameInput is the only documented Windows input stack with an
; explicit background focus policy, so it is offered as an alternative source
; for the same gamepad state.
;
; This backend is deliberately opt-in and fully fallback-guarded. GameInput is
; a COM-style interface reached through raw vtable offsets: an offset that is
; wrong for the installed GameInput version is not a catchable error, it is an
; access violation. Every entry point below is therefore probed once, failures
; are latched, and any failure returns the companion to XInput rather than
; leaving it without input.
;
; VERIFY BEFORE TRUSTING IN PRODUCTION: the vtable indices and the gamepad
; struct layout below match the documented GameInput v1 interface. If the log
; reports GameInput initialising but readings never arrive, these constants are
; the first thing to re-check against the GameInput version on the machine.
; ==============================================================================
; IGameInput vtable slots (0-2 are IUnknown).
global GI_VT_RELEASE := 2
; Verified working on Windows 11 / July 2026: readings arrive through slot 4.
global GI_VT_GETCURRENTREADING := 4
; UNVERIFIED. Slot 22 raised an exception in testing, so the focus policy is
; never actually applied and the log reports it as unavailable. This turned out
; not to matter: GameInput delivered background readings to the companion while
; Xbox FSE held the foreground, which proves background input already works
; without the call. Correct the slot only if a future need for an explicit
; policy appears; do not read the "unavailable" log line as the cause of any
; missing-button problem.
global GI_VT_SETFOCUSPOLICY := 22
; IGameInputReading vtable slots.
global GIR_VT_GETGAMEPADSTATE := 22
; GameInputKind::GameInputKindGamepad.
global GI_KIND_GAMEPAD := 2
; GameInputFocusPolicy::GameInputDefaultFocusPolicy — background input allowed.
global GI_FOCUS_DEFAULT := 0

InitGameInput() {
    global GameInputModule, GameInputPtr, GameInputReady, GameInputFailed
    global GI_VT_SETFOCUSPOLICY, GI_FOCUS_DEFAULT

    if GameInputReady
        return true
    if GameInputFailed
        return false

    ; Latch failure up front so a broken environment cannot retry every poll.
    GameInputFailed := true

    hmod := 0
    try {
        hmod := DllCall("GetModuleHandle", "Str", "GameInput.dll", "Ptr")
        if !hmod
            hmod := DllCall("LoadLibrary", "Str", "GameInput.dll", "Ptr")
    }
    if !hmod {
        LogLine("GameInput: GameInput.dll is not available; using XInput.", "Warning")
        return false
    }

    proc := 0
    try proc := DllCall("GetProcAddress", "Ptr", hmod, "AStr", "GameInputCreate", "Ptr")
    if !proc {
        LogLine("GameInput: GameInputCreate was not exported; using XInput.", "Warning")
        return false
    }

    obj := 0
    hr := -1
    try hr := DllCall(proc, "Ptr*", &obj, "Int")
    if (hr < 0 || !obj) {
        LogLine("GameInput: GameInputCreate failed (hr=0x"
            . Format("{:08X}", hr & 0xFFFFFFFF) "); using XInput.", "Warning")
        return false
    }

    GameInputModule := hmod
    GameInputPtr := obj

    ; Background input is the entire reason this backend exists. The call is
    ; absent on older GameInput builds, so treat a failure as informational.
    policyText := "not applied"
    try {
        policyProc := GameInputVtable(obj, GI_VT_SETFOCUSPOLICY)
        if policyProc {
            phr := DllCall(policyProc, "Ptr", obj, "Int", GI_FOCUS_DEFAULT, "Int")
            policyText := phr >= 0
                ? "default (background input allowed)"
                : "rejected (hr=0x" Format("{:08X}", phr & 0xFFFFFFFF) ")"
        }
    } catch {
        policyText := "unavailable on this GameInput version"
    }

    GameInputReady := true
    GameInputFailed := false
    LogLine("GameInput: initialised. Focus policy: " policyText ".")
    return true
}

GameInputVtable(ptr, index) {
    if !ptr
        return 0
    table := NumGet(ptr, 0, "Ptr")
    if !table
        return 0
    return NumGet(table, index * A_PtrSize, "Ptr")
}

ShutdownGameInput() {
    global GameInputPtr, GameInputReady, GI_VT_RELEASE
    if !GameInputPtr
        return
    try {
        release := GameInputVtable(GameInputPtr, GI_VT_RELEASE)
        if release
            DllCall(release, "Ptr", GameInputPtr)
    }
    GameInputPtr := 0
    GameInputReady := false
}

; Reads a gamepad through GameInput and writes it into the XINPUT_STATE-shaped
; buffer the rest of the companion already understands, so the poll loop and
; every mapping stay backend-agnostic.
GameInputReadState(&state) {
    global GameInputPtr, GameInputReady, GameInputFailed
    global GI_VT_GETCURRENTREADING, GI_VT_RELEASE
    global GIR_VT_GETGAMEPADSTATE, GI_KIND_GAMEPAD
    global GameInputLastRawButtons, GameInputLastHr

    if !GameInputReady
        return false
    if !IsObject(state)
        state := Buffer(16, 0)

    reading := 0
    hr := -1
    try {
        proc := GameInputVtable(GameInputPtr, GI_VT_GETCURRENTREADING)
        if !proc
            return false
        hr := DllCall(proc, "Ptr", GameInputPtr, "Int", GI_KIND_GAMEPAD,
            "Ptr", 0, "Ptr*", &reading, "Int")
    } catch {
        LogLine("GameInput: reading call raised an exception; reverting to XInput.", "Warning")
        GameInputReady := false
        GameInputFailed := true
        return false
    }
    GameInputLastHr := hr
    ; No reading simply means no gamepad is currently reporting.
    if (hr < 0 || !reading)
        return false

    pad := Buffer(28, 0)
    ok := false
    try {
        proc := GameInputVtable(reading, GIR_VT_GETGAMEPADSTATE)
        if proc
            ok := DllCall(proc, "Ptr", reading, "Ptr", pad, "Int") != 0
    }
    try {
        release := GameInputVtable(reading, GI_VT_RELEASE)
        if release
            DllCall(release, "Ptr", reading)
    }
    if !ok
        return false

    ; GameInputGamepadState: uint32 buttons, then six normalised floats.
    giButtons := NumGet(pad, 0, "UInt")
    GameInputLastRawButtons := giButtons
    lt := NumGet(pad, 4, "Float")
    rt := NumGet(pad, 8, "Float")
    lx := NumGet(pad, 12, "Float")
    ly := NumGet(pad, 16, "Float")
    rx := NumGet(pad, 20, "Float")
    ry := NumGet(pad, 24, "Float")

    buttons := 0
    if (giButtons & 0x0001)
        buttons |= 0x0010    ; Menu  -> Start
    if (giButtons & 0x0002)
        buttons |= 0x0020    ; View  -> Back
    if (giButtons & 0x0004)
        buttons |= 0x1000    ; A
    if (giButtons & 0x0008)
        buttons |= 0x2000    ; B
    if (giButtons & 0x0010)
        buttons |= 0x4000    ; X
    if (giButtons & 0x0020)
        buttons |= 0x8000    ; Y
    if (giButtons & 0x0040)
        buttons |= 0x0001    ; D-pad up
    if (giButtons & 0x0080)
        buttons |= 0x0002    ; D-pad down
    if (giButtons & 0x0100)
        buttons |= 0x0004    ; D-pad left
    if (giButtons & 0x0200)
        buttons |= 0x0008    ; D-pad right
    if (giButtons & 0x0400)
        buttons |= 0x0100    ; LB
    if (giButtons & 0x0800)
        buttons |= 0x0200    ; RB
    if (giButtons & 0x1000)
        buttons |= 0x0040    ; L3
    if (giButtons & 0x2000)
        buttons |= 0x0080    ; R3

    NumPut("UInt", 0, state, 0)
    NumPut("UShort", buttons, state, 4)
    NumPut("UChar", GameInputTrigger(lt), state, 6)
    NumPut("UChar", GameInputTrigger(rt), state, 7)
    NumPut("Short", GameInputAxis(lx), state, 8)
    NumPut("Short", GameInputAxis(ly), state, 10)
    NumPut("Short", GameInputAxis(rx), state, 12)
    NumPut("Short", GameInputAxis(ry), state, 14)
    return true
}

GameInputTrigger(value) {
    scaled := Round(value * 255)
    if (scaled < 0)
        return 0
    return scaled > 255 ? 255 : scaled
}

GameInputAxis(value) {
    scaled := Round(value * 32767)
    if (scaled < -32767)
        return -32767
    return scaled > 32767 ? 32767 : scaled
}

; ==============================================================================
; Backend dispatch
; ==============================================================================
; Single entry point for controller state. GameInput is tried first when
; selected; XInput remains the fallback so the companion is never left without
; input because of a backend problem.
ControllerReadState(&state) {
    global ControllerBackend, ActiveInputBackend, GameInputReady, GameInputFailed
    static warnedUnusable := false

    wanted := StrLower(ControllerBackend)
    ; RawInput first: it is the only source that survives Xbox FSE, and it is
    ; silent everywhere else, so it yields to XInput on the desktop by itself.
    if (wanted = "rawinput" || wanted = "auto") {
        if RawInputReadState(&state) {
            SetActiveBackend("rawinput")
            return true
        }
        ; An explicit rawinput request does NOT fall back to XInput.
        ;
        ; The setting exists to isolate RawInput for diagnosis, and a silent
        ; fallback made it behave identically to auto -- which is precisely what
        ; made a post-sleep test inconclusive: input still worked on the desktop,
        ; which looked like RawInput having recovered when it was XInput the
        ; whole time. A diagnostic setting that quietly does something else is
        ; worse than no setting at all.
        if (wanted = "rawinput") {
            SetActiveBackend("none")
            return false
        }
    }
    if (wanted = "gameinput") {
        if (!GameInputReady && !GameInputFailed)
            InitGameInput()
        if (GameInputReady && GameInputReadState(&state)) {
            SetActiveBackend("gameinput")
            return true
        }
        ; An explicit GameInput request still falls back, but says so once.
        if (wanted = "gameinput" && GameInputFailed && !warnedUnusable) {
            warnedUnusable := true
            LogLine("GameInput was requested but is unusable; falling back to XInput.", "Warning")
        }
    }

    if XInputResolveController(&state) {
        SetActiveBackend("xinput")
        return true
    }

    SetActiveBackend("none")
    return false
}

; Backend selection can legitimately alternate when one source goes quiet, and
; poll runs every ~16 ms, so repeat changes are throttled to keep a flapping
; backend from burying the button diagnostics.
;
; The FIRST time each backend becomes active is always logged, even inside the
; throttle window. Suppressing it once cost a whole test cycle: the switch to
; GameInput happened seconds after startup, was throttled away, and the log
; gave no indication which backend produced the button readings that followed.
; SetActiveBackend lives in SteamShell-Shared.ahk now, with the throttle and the
; always-log-the-first-time rule intact. The shell needed the same answer for its
; Health Check and had no way to record it.



; ==============================================================================
; Controller profiles: learned report layouts
; ==============================================================================
; The decoder above understands one controller, because its byte layout was read
; off that hardware. Everything below lets any controller be taught instead: the
; user presses each button in turn and the learner records which byte and bit
; changed, which is a measurement rather than an assumption about the device.
;
; Profiles live in their own file beside the executable, keyed by USB VID/PID so
; the key survives re-enumeration -- unlike the hDevice handle, which does not.
;
; This is purely additive. A device with no profile falls through to the built-in
; layout exactly as before, so nothing here can break a controller that already
; works.
; ------------------------------------------------------------------------------

; ==============================================================================
; Controller learning
; ==============================================================================
; Teaches the companion an unknown controller by watching what its reports do.
;
; The user is prompted for one input at a time. The learner holds a neutral
; baseline captured while nothing was touched, and compares each incoming report
; against it:
;
;   buttons  a bit whose pressed state differs from the measured rest state
;   D-pad    either a bit, or a byte that takes a distinct value per direction
;   axes     a field that moves a long way from neutral and returns
;
; The combined trigger axis that made this controller awkward in the first place
; needs no special handling: LT and RT are learned independently and simply come
; out sharing an offset with opposite directions.
; ------------------------------------------------------------------------------
global LearnActive := false
global LearnDevice := 0
global LearnDeviceKey := ""
global LearnLength := 0
global LearnBaseline := 0
; Bits that changed during rest sampling. Analogue sticks jitter, so without this
; mask a drifting low byte is indistinguishable from a button press. Recording
; transitions rather than bits that were merely set also lets active-low buttons
; be learned.
global LearnRestNoise := 0
global LearnRestSampling := false
global LearnRestCount := 0
; Peak magnitude per axis across the post-save rest window, and how many samples
; it covers. Declared here rather than created on first use so they behave like
; every other script-scope variable.
; Seeded with every axis it reads, not left empty. ControllerProfileRestCheck
; reads RestCheckPeak[name] for all six unguarded, and an empty Map answers that
; with "Item has no value" -- an uncaught error, from a timer, on the path taken
; immediately after a controller profile is applied. Only
; ControllerProfileRestCheckBegin fills it today, so the reads are safe by
; sequence rather than by construction; this makes them safe either way.
global RestCheckPeak := Map("LX", 0, "LY", 0, "RX", 0, "RY", 0, "LT", 0, "RT", 0)
global RestCheckSamples := 0
; Before a controller is selected, keep one baseline per RawInput device. The
; wizard therefore honours "press any button" even when several pads are
; connected and another one is continuously publishing idle reports.
global LearnIdentifyDevices := Map()
global LearnIdentifyReady := false
; How far each byte travelled during the current axis step, and the most recent
; report. Field width cannot be judged from either alone:
;
;   - At the far stop a 16-bit axis often has a low byte back on its resting
;     value, so the high byte alone looks like a complete 8-bit axis.
;   - Across the travel that low byte wraps through its whole range repeatedly,
;     so by amplitude it looks like the STRONGEST axis in the report.
;
; So amplitude is measured at the farthest point of the outward sweep, while
; the excursion record over the whole travel decides which bytes are genuinely
; part of a field. The sample path also distinguishes little-endian from
; big-endian fields: the correct interpretation moves smoothly, while the wrong
; one wraps whenever the low byte rolls over.
global LearnExcursion := 0
global LearnAxisSamples := []
global LearnAxisStarted := false
; Why the last axis resolve gave up. "Not enough travel" was shown for every
; failure, including ones that had nothing to do with travel, which made a real
; fault indistinguishable from a small movement.
global LearnAxisRejection := ""
; The plain-language twin of LearnLastAccepted. That one keeps the byte, mask
; and neutral value because the log needs them; this is what the window shows.
global LearnLastFriendly := ""
; Set when an axis step is refused for a reason RETRYING CANNOT FIX, so the
; capture timeout skips the step instead of restarting it. Axis steps retry on
; timeout because a timeout is normally transient -- the user was slow, or did
; not return to rest. A trigger whose only candidates are motion bytes is not
; transient: every retry reaches the same refusal, and the controller is inert
; while the wizard is open, so Skip needs a mouse the user may not have.
global LearnAxisUnresolvable := false
; One "that bit is masked as rest noise" line per step, not per report.
; Reports arrive at over 100 Hz and the condition persists for the whole
; step, so an ungated log would be thousands of identical lines.
global LearnNoiseBlamed := false
global LearnStepIndex := 0
global LearnResultButtons := []
global LearnResultAxes := Map()
global LearnHatValues := Map()
global LearnGui := unset
global LearnPromptCtrl := unset
global LearnDetailCtrl := unset
global LearnProgressCtrl := unset
global LearnLastAccepted := ""
; The control the wizard is waiting to see released before the next prompt.
; -1 means nothing is pending. A mask of 0 means the whole byte must return to
; rest, which is how a hat is checked.
; Report bytes that carry an analogue value, found by the opening scan step.
;
; A button is a bit; an axis is a byte that sweeps. The distinguishing evidence is
; how many DISTINCT values a byte takes while the sticks are rolled around: a
; button byte takes two, an axis byte takes dozens. LearnAnalogValues collects
; that census, LearnAnalogBytes is the conclusion, and button detection skips
; every byte in it.
; Reports seen during the current step. "Nothing registers" has two very
; different causes -- no reports arriving at all, or reports arriving and being
; rejected -- and the count is what tells them apart.
global LearnCountdownCtrl := unset
global LearnStepReports := 0
global LearnDpadRetries := 0
global LearnAnalogBytes := Map()
global LearnAnalogValues := Map()
global LearnReleaseOffset := -1
global LearnReleaseMask := 0
global LearnReleaseUntil := 0
global LearnCaptureUntil := 0
global LearnPeak := 0


; Per-tree seam required by SteamShell-Shared.ahk: what this product can add to
; a controller diagnostic tick.
;
; GameInput is the companion's alone -- it reads all zeros outside Xbox FSE, so
; the shell cannot offer it honestly -- and so is the second backend name. Those
; two facts are the whole of the difference between the two ticks, which is why
; the rest of it is shared rather than written twice.
;
; Returned as three strings rather than one so the log line keeps its shape:
; the backend suffix sits with the backend, the GameInput reading after the
; slots, and the signature feeds the tick's change detection without appearing
; in the output at all.
ProductControllerDiagnosticProbe() {
    global ActiveInputBackend, GameInputReady, GameInputFailed
    global GameInputLastRawButtons, GameInputLastHr

    ; Initialise GameInput for OBSERVATION even when it is not the active input
    ; backend. The comparison between the two stacks is the entire point of this
    ; diagnostic, and it must not force the user to route real input through the
    ; less-proven backend just to collect it.
    if (!GameInputReady && !GameInputFailed)
        InitGameInput()

    giText := "off"
    signature := ""
    if GameInputReady {
        giState := Buffer(16, 0)
        if GameInputReadState(&giState) {
            giText := "0x" Format("{:04X}", NumGet(giState, 4, "UShort"))
                . " raw=0x" Format("{:08X}", GameInputLastRawButtons)
            signature := GameInputLastRawButtons
        } else {
            giText := "noreading hr=0x" Format("{:08X}", GameInputLastHr & 0xFFFFFFFF)
            signature := "none"
        }
    } else if GameInputFailed {
        giText := "initfailed"
    }
    return Map("suffix", "/" ActiveInputBackend,
        "detail", " | GI=" giText,
        "signature", signature)
}

; Per-tree seam required by SteamShell-Shared.ahk: the builtin actions only
; this product has.
;
; Explorer is a plain Run here. The companion runs at normal integrity, so
; there is no token to drop and nothing to route around -- the shell's
; de-elevating launch would be ceremony rather than safety.
ProductControllerBindingAction(action) {
    switch action {
        case "Explorer":
            try Run("explorer.exe")
        case "TaskView":
            SendChordSafe("#{Tab}")
        case "WindowsDesktop":
            ; Win+D. The previous Win+F11 is not a Windows shortcut at all, so
            ; this action had never done anything.
            SendChordSafe("#d")
        case "Settings":
            ShowSettings()
    }
}

; The builtin actions this product offers, and what it calls them.
;
; One table, read in both directions through SharedBindingLabelFor and
; SharedBindingActionFor. It used to be two -- this list and
; MappingBuiltinValue's -- which could disagree without anything noticing.
;
; Xbox FSE's vocabulary, deliberately: "Game Bar" rather than Win+G, "Back /
; Escape" rather than Esc, "Close window" rather than Alt+F4. This product sits
; beside a console-style front end and a user reading these has not been looking
; at a Windows desktop. TaskView, WindowsDesktop and Settings exist here and not
; in the shell; ControlPanel is the shell's and not here.
ControllerBindingLabels() {
    static labels := [
        ["None", "None"],
        ["LeftClick", "Left click"],
        ["RightClick", "Right click"],
        ["Enter", "Enter"],
        ["Esc", "Back / Escape"],
        ["AltF4", "Close window"],
        ["TabTip", "Touch keyboard"],
        ["OSK", "Classic keyboard"],
        ["WinG", "Game Bar"],
        ["StartMenu", "Start menu"],
        ["Explorer", "File Explorer"],
        ["CtrlAltTab", "Application switcher"],
        ["TaskManager", "Task Manager"],
        ["TaskView", "Task View"],
        ["WindowsDesktop", "Windows desktop"],
        ["QuickMenu", "Quick Menu"],
        ["Settings", "Settings"]]
    return labels
}

ControllerBindingPretty(key) {
    global ControllerMapDisplay
    value := GetBindingValue(key)
    if (value = "")
        return "None"
    if (SubStr(value, 1, 5) = "Send:") {
        display := ""
        try display := ControllerMapDisplay[key]
        return display != "" ? display : SendToPretty(SubStr(value, 6))
    }
    if (SubStr(value, 1, 8) = "Builtin:")
        return SharedBindingLabelFor(SubStr(value, 9), ControllerBindingLabels())
    return value
}

OpenWindowsSettings() {
    if RunViaDesktopShell("ms-settings:")
        return
    try Run("ms-settings:")
}

OpenOSK() {
    ; Always open the classic On-Screen Keyboard.
    try Run("osk.exe")
}

; ==============================================================================
; Display selection (resolution, refresh rate, and scale chosen independently)
; ==============================================================================

StartRtssFromQuickMenu() {
    global EnableRTSSIntegration
    if !EnableRTSSIntegration {
        ShowNotification("Enable RTSS integration in Settings first", "Warning")
        return
    }
    if ProcessExist("RTSS.exe") {
        ShowNotification("RTSS is already running")
        SetTimer(RefreshQuickMenuAfterRtssStart, -100)
        return
    }
    ShowNotification("Starting RTSS…")
    if EnsureRtssRunning() {
        ShowNotification("RTSS started")
        ; ProcessWait confirms the executable, but its hooks DLL and shared state
        ; can take another moment to become queryable. Rebuild once after that
        ; settles so Start RTSS becomes the live state rows and the shorter page
        ; is measured/re-centred.
        SetTimer(RefreshQuickMenuAfterRtssStart, -600)
    } else {
        ShowNotification("RTSS did not start", "Warning")
    }
}

RefreshQuickMenuAfterRtssStart() {
    global QuickMenuVisible, QuickMenuPage
    if (QuickMenuVisible && QuickMenuPage = "RTSS")
        QuickMenuBuildGui()
}

; Foreground process name right now, ignoring our own windows so that the Quick
; Menu and Settings never count as "the thing in front".
CurrentForegroundExe() {
    global LastObservedForegroundExe
    hwnd := 0
    try hwnd := WinExist("A")
    if (hwnd && IsOurWindow(hwnd))
        return LastObservedForegroundExe
    exe := ""
    try exe := WinGetProcessName("ahk_id " hwnd)
    return exe
}

SteamIsInFront() {
    return IsSteamProcess(CurrentForegroundExe())
}

; Steam Menu: Steam's own menu when Steam is in front, the in-game overlay when
; a game is.
SendSteamMenu(steamInFront) {
    global SteamMenuShortcut, SteamOverlayShortcut
    shortcut := steamInFront ? SteamMenuShortcut : SteamOverlayShortcut
    ShowNotification("Steam Menu: " SendToPretty(shortcut))
    return shortcut
}

SendSteamQuickAccess(steamInFront) {
    global SteamQuickAccessShortcut
    ShowNotification("Steam Quick Access: " SendToPretty(SteamQuickAccessShortcut))
    return SteamQuickAccessShortcut
}

; ==============================================================================
; Elevated logon task
; ==============================================================================
; Optional Scheduled Task that starts the companion at logon.
;
; The task deliberately does NOT request highest privileges. Elevation was
; tested on hardware and rejected: while an elevated window of ours holds the
; foreground, Steam cannot inspect it, so Steam never registers that it lost
; focus and keeps acting on controller input underneath the Quick Menu. Both
; applications respond to the same press, which makes the menu unusable and can
; activate something in Steam while the user is choosing Sleep or Shutdown.
;
; The cost of that decision is accepted and documented: at normal privileges the
; companion cannot send input to, activate or close windows owned by elevated
; applications, so controller mappings do nothing while an elevated anti-cheat
; game is in front. A usable Quick Menu is worth more than that.
;
; A Scheduled Task is still used rather than an elevated manifest, because the
; companion must never relaunch itself elevated -- that would raise a UAC prompt
; on every boot, since a non-elevated parent starts it.
; The task name now lives in SteamShell-Common.ahk, because Setup Assistant
; registers the same task and the two used to disagree. Kept as a wrapper so the
; six call sites below read the same as before.
LogonTaskName() {
    return XfeLogonTaskName()
}

LogonTaskTarget() {
    if A_IsCompiled
        return '"' A_ScriptFullPath '"'
    return '"' A_AhkPath '" "' A_ScriptFullPath '"'
}

LogonTaskExists() {
    exitCode := 1
    try exitCode := RunWait('schtasks.exe /query /tn "' LogonTaskName() '"', , "Hide")
    return exitCode = 0
}

LogonTaskAccount() {
    domain := ""
    try domain := EnvGet("USERDOMAIN")
    if (domain = "")
        domain := A_ComputerName
    return domain "\" A_UserName
}

; The registration XML for the logon task.
;
; This is registered with /xml rather than the much shorter /tr form for one
; reason that matters on a handheld: a task created by `schtasks /create` takes
; Task Scheduler's DEFAULT conditions, and those include
;
;     DisallowStartIfOnBatteries = true
;
; -- "start the task only if the computer is on AC power". On a ROG Ally running
; undocked the task then exists, its trigger fires at logon, and Windows
; declines to start it every time. The task looks perfectly healthy in the
; Task Scheduler UI, which is what makes this so hard to spot.
;
; The other defaults worth overriding here:
;   StopIfGoingOnBatteries  would kill the companion the moment it is undocked.
;   ExecutionTimeLimit      defaults to 72 hours, after which the companion is
;                           terminated mid-session.
;   RunLevel                LeastPrivilege is stated explicitly rather than
;                           inherited, because elevation is a rejected design
;                           decision here, not an accident of the default.
;
; The Delay gives the shell and Xbox FSE time to come up first; launching into a
; half-initialised session is how a startup app ends up behind everything.
; Resolves the account as a SID where possible -- it survives a user rename,
; where DOMAIN\User does not -- and falls back to the domain form only if the
; SID cannot be read. Setup Assistant already used the SID; this is the
; companion adopting the more robust half.
LogonTaskAccountForXml() {
    sidText := ""
    if GetCurrentProcessUserSid(&sidText, &sidError)
        return sidText
    LogLine("Logon task: falling back to DOMAIN\\User; the SID could not be read ("
        . sidError ").", "Warning")
    return LogonTaskAccount()
}

LogonTaskXml() {
    if A_IsCompiled
        return XfeLogonTaskXml(LogonTaskAccountForXml(), A_ScriptFullPath, "", A_ScriptDir)
    return XfeLogonTaskXml(LogonTaskAccountForXml(), A_AhkPath,
        '"' A_ScriptFullPath '"', A_ScriptDir)
}

; Dumps the registered task's full definition to the log.
;
; "The task was created but nothing happened" is unanswerable without this: the
; verbose query reports Last Run Time, Last Result, and the power conditions
; that silently decline to start it.
LogLogonTaskDetails() {
    if !LogonTaskExists() {
        LogLine("Logon task: not registered.")
        return
    }
    output := ""
    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec('schtasks.exe /query /tn "' LogonTaskName() '" /v /fo LIST')
        output := exec.StdOut.ReadAll()
    } catch as err {
        LogLine("Logon task: could not query details (" err.Message ").", "Warning")
        return
    }
    for _, line in StrSplit(output, "`n", "`r") {
        line := Trim(line)
        if (line != "")
            LogLine("Logon task:   " line)
    }
}

; schtasks needs administrator rights to register a highest-privileges task.
; When the companion is already elevated it runs directly; otherwise this is the
; one place a UAC prompt is raised, at the user's explicit request.
RunSchTasks(arguments) {
    try {
        if A_IsAdmin
            return RunWait('schtasks.exe ' arguments, , "Hide")
        return RunWait('*RunAs schtasks.exe ' arguments, , "Hide")
    } catch as err {
        LogLine("Scheduled task command failed: " err.Message, "Warning")
        return -1
    }
}

CreateLogonTask(*) {
    global SettingsDialogActive
    target := LogonTaskTarget()
    SettingsDialogActive := true
    answer := TopmostMsgBox(
        "Create a Scheduled Task that starts SteamShell XFE at logon?`n`n"
        . "Task name: " LogonTaskName() "`n"
        . "Runs: " target "`n`n"
        . "The task runs at normal privileges. The companion cannot control "
        . "windows belonging to elevated applications, which is the accepted "
        . "trade for Steam continuing to work correctly.`n`n"
        . "It is registered to run on battery, 10 seconds after logon, with no "
        . "execution time limit. Windows would otherwise refuse to start it "
        . "while the machine is not plugged in.`n`n"
        . "Afterwards, remove SteamShell XFE from AnyFSE's startup applications "
        . "so it is not started twice.",
        "Create logon task", "OKCancel Icon?")
    SettingsDialogActive := false
    if (answer != "OK")
        return
    ; schtasks requires the XML to be Unicode, and rejects the file outright
    ; otherwise. A_Temp is used rather than the script directory so a read-only
    ; install location cannot break registration.
    xmlPath := A_Temp "\SteamShell-XFE-task.xml"
    try FileDelete(xmlPath)
    try {
        FileAppend(LogonTaskXml(), xmlPath, "UTF-16")
    } catch as err {
        ShowNotification("Could not write the task definition", "Warning")
        LogLine("Creating logon task failed: could not write " xmlPath
            . " (" err.Message ").", "Warning")
        return
    }
    ; Remove the name this companion used to register under, so a machine that
    ; has been through both routes ends up with one task rather than two.
    RunSchTasks('/delete /f /tn "' XfeLogonTaskLegacyName() '"')
    exitCode := RunSchTasks('/create /f /tn "' LogonTaskName() '" /xml "' xmlPath '"')
    try FileDelete(xmlPath)
    if (exitCode = 0) {
        ShowNotification("Logon task created")
        LogLine("Created logon task '" LogonTaskName() "' at normal privileges, "
            . "runs on battery, 10s logon delay, no execution time limit.")
        ; Record what was actually registered, so a later "it did not start"
        ; can be answered from the log instead of guessed at.
        LogLogonTaskDetails()
    } else {
        ShowNotification("Could not create the logon task", "Warning")
        LogLine("Creating logon task failed (exit " exitCode ").", "Warning")
    }
    SettingsRefreshLogonTaskStatus()
}

RemoveLogonTask(*) {
    global SettingsDialogActive
    if !LogonTaskExists() {
        ShowNotification("No logon task is registered")
        SettingsRefreshLogonTaskStatus()
        return
    }
    SettingsDialogActive := true
    answer := TopmostMsgBox("Remove the '" LogonTaskName() "' logon task?`n`n"
        . "SteamShell XFE will no longer start automatically with administrator "
        . "rights. Add it back to AnyFSE's startup applications if you still want "
        . "it to start with the session.",
        "Remove logon task", "OKCancel Icon?")
    SettingsDialogActive := false
    if (answer != "OK")
        return
    RunSchTasks('/delete /f /tn "' XfeLogonTaskLegacyName() '"')
    exitCode := RunSchTasks('/delete /f /tn "' LogonTaskName() '"')
    if (exitCode = 0) {
        ShowNotification("Logon task removed")
        LogLine("Removed logon task '" LogonTaskName() "'.")
    } else {
        ShowNotification("Could not remove the logon task", "Warning")
        LogLine("Removing logon task failed (exit " exitCode ").", "Warning")
    }
    SettingsRefreshLogonTaskStatus()
}

; Logs the task definition and tells the user where to look. Exposed as a button
; because the interesting fields -- Last Run Time, Last Result, and the power
; conditions -- are invisible from inside the companion.
SettingsCheckLogonTask(*) {
    LogLine("Logon task: check requested.")
    LogLogonTaskDetails()
    ShowNotification("Logon task details written to the log")
    SettingsRefreshLogonTaskStatus()
}

SettingsRefreshLogonTaskStatus() {
    global LogonTaskStatusCtrl
    if !IsSet(LogonTaskStatusCtrl)
        return
    text := (LogonTaskExists()
        ? "Logon task is registered."
        : "No logon task registered.")
        . " Currently running " (A_IsAdmin ? "elevated" : "at normal privileges") "."
        . (A_IsAdmin
            ? " Note: while elevated, Steam keeps responding to the controller "
                . "underneath the Quick Menu."
            : "")
    try LogonTaskStatusCtrl.Text := text
}

; ==============================================================================
; Startup programs
; ==============================================================================
LoadStartupPrograms() {
    global IniPath, StartupPrograms
    StartupPrograms := []
    index := 1
    while (index <= 40) {
        value := ""
        try value := IniRead(IniPath, "StartupPrograms", "Program" index, "")
        value := NormalizePath(value)
        if (value != "")
            StartupPrograms.Push(value)
        index += 1
    }
}

SaveStartupPrograms() {
    global IniPath, StartupPrograms
    index := 1
    for _, path in StartupPrograms {
        IniWrite(path, IniPath, "StartupPrograms", "Program" index)
        index += 1
    }
    ; Clear any entries left over from a longer previous list.
    while (index <= 40) {
        try IniDelete(IniPath, "StartupPrograms", "Program" index)
        index += 1
    }
}

NormalizeWindowMode(mode) {
    switch StrLower(Trim(mode)) {
        case "hidden", "hide":
            return "hidden"
        case "minimized", "minimised", "min":
            return "minimized"
        default:
            return "normal"
    }
}

WindowModeLabel(mode) {
    switch NormalizeWindowMode(mode) {
        case "hidden":
            return "Hidden"
        case "minimized":
            return "Minimized"
        default:
            return "Normal"
    }
}

; Launches one program, optionally handing it the ordinary user token, and
; optionally keeping its windows out of sight.
;
; A child inherits the parent's elevation. Starting through the shell instead
; gives the child the desktop's token, which keeps an elevated companion from
; silently elevating Steam and everything Steam then launches.
LaunchStartupProgram(path) {
    global StartupLaunchDeElevated, StartupWindowMode, CompanionDisabled
    if CompanionDisabled
        return false
    if !SharedPrepareStartupProgram(path, &target, &params, &fileName, &directory)
        return false
    path := target
    mode := NormalizeWindowMode(StartupWindowMode)
    runOptions := mode = "hidden" ? "Hide" : (mode = "minimized" ? "Min" : "")
    ; De-elevated through Explorer, which owns the normal-integrity desktop. The
    ; companion runs at normal integrity itself, so this only matters when a user
    ; has started it elevated anyway.
    viaShell := StartupLaunchDeElevated && A_IsAdmin
    try {
        if viaShell
            Run('explorer.exe "' path '"' (params != "" ? " " params : ""), directory)
        else
            Run('"' path '"' (params != "" ? " " params : ""), directory, runOptions)
        LogLine("Started " fileName
            . (viaShell ? " (as normal user)" : "")
            . (mode != "normal" ? " [" WindowModeLabel(mode) "]" : "") ".")
        if (mode != "normal" && fileName != "")
            SetTimer(ApplyStartupWindowMode.Bind(fileName, mode, A_TickCount), -300)
        return true
    } catch as err {
        LogLine("Could not start " path ": " err.Message, "Warning")
        return false
    }
}

; Enforces Hidden or Minimized on a program's windows for a few seconds after it
; starts.
;
; Two reasons this is needed rather than trusting Run's show-state argument.
; Applications with a splash screen, or that recreate their main window after
; initialising, show a window that the original show state never applied to. And
; on the de-elevated route the show state never reached the child at all, since
; explorer.exe started it.
;
; Windows are matched by PROCESS NAME, not by PID: the de-elevated route returns
; explorer's PID, which owns none of the windows we care about.
;
; Running for a fixed window and then stopping is deliberate. A permanent sweep
; would fight the user the moment they deliberately opened the program later.
; Thin wrapper over the shared sweep, so the two programs cannot drift on what
; "Minimized" means or how long they keep trying.
ApplyStartupWindowMode(fileName, mode, startedTick) {
    global CompanionDisabled
    if CompanionDisabled
        return
    if !ApplyStartupWindowModeOnce(
        fileName, NormalizeStartupWindowMode(mode), startedTick + 6000)
        return
    SetTimer(() => ApplyStartupWindowMode(fileName, mode, startedTick), -400)
}

RunStartupPrograms() {
    global EnableStartupPrograms, StartupPrograms, StartupProgramStaggerMs
    global CompanionDisabled
    if (CompanionDisabled || !EnableStartupPrograms)
        return
    SharedLaunchWithStagger(
        StartupPrograms, StartupProgramStaggerMs, LaunchStartupProgram)
}

; ==============================================================================
; Assist engine
; ==============================================================================
; A window inventory and game detector, ported from SteamShell 1.5's window
; engine WITHOUT its geometry layer. Nothing here sizes, centres, maximises or
; restores a window: Xbox FSE owns presentation. The only outward actions are
; activating a window and closing a launcher process.
;
; The engine suspends completely whenever any window belonging to this process
; owns the foreground, so it can never fight the Quick Menu, Settings, the
; mapping editor, a shortcut capture, a file dialog or a message box.
; ------------------------------------------------------------------------------
ProcessNameSetFromList(list) {
    set := Map()
    for _, name in StrSplit(list, "|") {
        name := StrLower(Trim(name))
        if (name != "")
            set[name] := true
    }
    return set
}

; The companion's view of the shared inventory: things that can be activated or
; closed.
;
; THE FILTER IS THE WHOLE FUNCTION NOW. It used to be an enumeration with the
; filter woven through it, which is how the same three rules ended up written a
; second time in the Task Switcher and a third in RunScreenProbe, each
; slightly different. Enumerating is SharedWindowInventoryBuild's job; deciding
; what this product does with the result is this one's.
;
; Desktop and shell windows go, because Xbox FSE owns presentation and none of
; them is a thing to activate. Tool windows go for the same reason -- palettes
; and overlays -- except Steam's, which publishes a visible, titled, full-sized
; Big Picture window as WS_EX_TOOLWINDOW without WS_EX_APPWINDOW under Xbox FSE.
; Degenerate rectangles go; MINIMIZED windows stay, because a minimized window
; reports off-screen coordinates rather than a zero size and "minMax" is the
; question that identifies it.
AssistInventoryBuild() {
    items := []
    for _, item in SharedWindowInventoryBuild() {
        if item["desktop"]
            continue
        if (item["toolWindow"] && !item["steam"])
            continue
        if item["degenerate"]
            continue
        items.Push(item)
    }
    return items
}

AssistInventoryGet(maxAgeMs := 1000) {
    global AssistInventory, AssistInventoryTick
    if (!AssistInventoryTick || A_TickCount - AssistInventoryTick > maxAgeMs) {
        AssistInventory := AssistInventoryBuild()
        AssistInventoryTick := A_TickCount
    }
    return AssistInventory
}

; Rolling CPU usage for one process, as a percentage of one core-equivalent of
; the whole machine. Used to answer "is a game actually running" when window
; shape alone is not conclusive.
; No rate limit: the assist tick is already the slower of the two loops, and
; sampling on every call is what this product has always done.
AssistProcessCpuSample(pid) {
    global AssistCpuSamples
    return SharedProcessCpuSample(pid, AssistCpuSamples)
}

AssistPruneCpuSamples(inventory) {
    global AssistCpuSamples
    SharedPruneCpuSamples(AssistCpuSamples, inventory)
}

; A window is game-like when it belongs to no known shell, launcher or browser
; and covers most of the monitor it sits on. Deliberately conservative: a false
; positive here only suppresses cleanup, which is the safe direction.
; borderlessRatio is the shell's inline 0.90, carried over unchanged rather than
; adopting AssistWindowLooksLikeGame's 0.85/0.80. Those two numbers belong to the
; cheap shape test that still drives the assist features; the scorer is a
; different question and must agree with the shell, not with its neighbour.
XfeGameScoreWeights() {
    global AssistFullscreenTolerance, AssistFullscreenPosTolerancePx
    global AssistScoreFullscreen, AssistScoreBorderlessLarge, AssistScoreTitleBonus
    global AssistCpuThresholdPercent, AssistScoreCpuAboveThreshold
    global AssistScoreCpuNonZeroBonus, AssistAllowZeroCpuAsCandidate
    global AssistScoreAudioActive
    return Map(
        "fullscreenTolerance", AssistFullscreenTolerance,
        "positionTolerancePx", AssistFullscreenPosTolerancePx,
        "borderlessRatio", 0.90,
        "fullscreen", AssistScoreFullscreen,
        "borderlessLarge", AssistScoreBorderlessLarge,
        "titleBonus", AssistScoreTitleBonus,
        "cpuThresholdPercent", AssistCpuThresholdPercent,
        "cpuAboveThreshold", AssistScoreCpuAboveThreshold,
        "cpuNonZeroBonus", AssistScoreCpuNonZeroBonus,
        "allowZeroCpu", AssistAllowZeroCpuAsCandidate,
        "audioActive", AssistScoreAudioActive)
}

; The scored answer to "which window is the game", using the same arbiter as the
; shell through SteamShell-Common.ahk.
;
; AssistWindowLooksLikeGame stays as it is and keeps driving the assist features:
; it is a cheap shape test, it has behaved well for Game Focus and Launcher
; Cleanup, and changing it would change three behaviours to fix one.
;
; What needed a better answer is the per-game RTSS frame cap. That is keyed on an
; executable NAME, so picking the wrong window does not degrade gracefully -- it
; writes the cap to another program's profile and reports success. Shape alone
; cannot separate a game from a fullscreen launcher, a video player or a browser;
; CPU and audio can, and this companion already samples both.
;
; Still no geometry, focus or activation. This reads the inventory it already
; builds and returns a name.
; What this product excludes before a window is even scored.
;
; A callback rather than a shared filter: the shell's exclusions are a different
; set, and folding either into the other would change what each detects as a
; game. Untitled is rejected here and allowed through for a legacy surface in the
; shell -- left as it is, because changing what the companion treats as a game is
; not a refactor.
AssistSkipForGameScore(item) {
    global AssistProtectedProcesses, AssistLauncherProcesses
    static protectedSet := ""
    static launcherSet := ""
    static builtFrom := ""
    ; Rebuilt only when the settings strings change, rather than per window.
    signature := AssistProtectedProcesses "|" AssistLauncherProcesses
    if (builtFrom != signature) {
        protectedSet := ProcessNameSetFromList(AssistProtectedProcesses)
        launcherSet := ProcessNameSetFromList(AssistLauncherProcesses)
        builtFrom := signature
    }
    if (item["title"] = "" || item["exe"] = "")
        return true
    return protectedSet.Has(item["exe"]) || launcherSet.Has(item["exe"])
}

XfeBestGameWindow() {
    global LastBestCandidateProc, LastBestCandidateScore
    global EnableAudioAssist, AudioPeakThreshold
    scored := SharedScoreGameCandidates(
        AssistInventoryGet(), XfeGameScoreWeights(), AssistProcessCpuSample,
        AssistSkipForGameScore,
        EnableAudioAssist, AudioPeakThreshold)
    candidates := scored["candidates"]
    LogGameCandidateTable(candidates, [], "best-candidate")
    CaptureGameCandidates(candidates)
    if (candidates.Length > 0) {
        LastBestCandidateProc := candidates[1]["proc"]
        LastBestCandidateScore := candidates[1]["score"]
    } else {
        LastBestCandidateProc := ""
        LastBestCandidateScore := -1
    }
    if (candidates.Length = 0)
        return ""
    return candidates[1]["exe"]
}

AssistWindowLooksLikeGame(item) {
    global AssistProtectedProcesses, AssistLauncherProcesses
    if (item["ours"] || item["title"] = "")
        return false
    protectedSet := ProcessNameSetFromList(AssistProtectedProcesses)
    launcherSet := ProcessNameSetFromList(AssistLauncherProcesses)
    if (protectedSet.Has(item["exe"]) || launcherSet.Has(item["exe"]))
        return false
    monitorIndex := GetMonitorIndexForWindow(item["hwnd"])
    try MonitorGet(monitorIndex, &left, &top, &right, &bottom)
    catch
        return false
    monitorWidth := right - left
    monitorHeight := bottom - top
    if (monitorWidth <= 0 || monitorHeight <= 0)
        return false
    return item["w"] >= monitorWidth * 0.85 && item["h"] >= monitorHeight * 0.80
}

; True when something game-like appears to be running. A fullscreen/borderless
; window is the fast path. CPU is an additional conservative signal across all
; non-protected, non-launcher visible-window processes, which covers a minimized
; game whose current geometry no longer looks fullscreen.
AssistGameIsRunning(inventory) {
    global AssistCpuThresholdPercent, AssistProtectedProcesses
    global AssistLauncherProcesses
    for _, item in inventory {
        if AssistWindowLooksLikeGame(item)
            return true
    }
    if (AssistCpuThresholdPercent <= 0)
        return false

    protectedSet := ProcessNameSetFromList(AssistProtectedProcesses)
    launcherSet := ProcessNameSetFromList(AssistLauncherProcesses)
    pids := Map()
    for _, item in inventory {
        exe := item["exe"]
        if (!item["pid"] || item["ours"] || exe = ""
            || protectedSet.Has(exe) || launcherSet.Has(exe))
            continue
        pids[item["pid"]] := true
    }
    unknownProcessSeen := false
    for pid in pids {
        sample := AssistProcessCpuSample(pid)
        ; The first successful observation has no delta. Treat it as busy for
        ; one pass rather than race launcher cleanup against an unknown process.
        if (!sample["known"] && sample.Has("creation")) {
            unknownProcessSeen := true
            continue
        }
        if (sample["known"]
            && sample["usage"] >= AssistCpuThresholdPercent)
            return true
    }
    return unknownProcessSeen
}

AssistFindGameWindow(inventory) {
    for _, item in inventory {
        if AssistWindowLooksLikeGame(item)
            return item
    }
    return 0
}

AssistFindSteamWindow(inventory) {
    best := 0
    bestArea := 0
    for _, item in inventory {
        if (item["ours"] || !IsSteamProcess(item["exe"])
            || item["title"] = "")
            continue
        area := item["w"] * item["h"]
        if (area > bestArea) {
            best := item
            bestArea := area
        }
    }
    return best
}

; The single most important guard in this file.
;
; Assistance suspends entirely while this process owns the foreground, which
; covers every window we can put on screen -- Quick Menu, Settings, the mapping
; editor, shortcut capture, health check, file pickers and message boxes -- and
; for a short settle period afterwards so closing one of them does not race a
; focus change.
AssistShouldSuspend() {
    global QuickMenuVisible, SettingsVisible, SettingsDialogActive
    global AssistSuspendUntilTick
    if (QuickMenuVisible || SettingsVisible || SettingsDialogActive) {
        AssistSuspendUntilTick := A_TickCount + 1500
        return true
    }
    hwnd := 0
    try hwnd := WinExist("A")
    if (hwnd && IsOurWindow(hwnd)) {
        AssistSuspendUntilTick := A_TickCount + 1500
        return true
    }
    return AssistSuspendUntilTick && A_TickCount < AssistSuspendUntilTick
}

; Foreground processes we never take focus away from. Xbox FSE surfaces and the
; Windows shell are showing something on purpose; overriding them is precisely
; the fight this companion is meant to avoid.
AssistForegroundIsProtected(exe) {
    global AssistIgnoreForegroundProcesses
    exe := StrLower(exe)
    ; explorer.exe owns the desktop, taskbar and File Explorer. Protect it even
    ; when an older customized INI predates its addition to the default list.
    return exe = "explorer.exe"
        || ProcessNameSetFromList(AssistIgnoreForegroundProcesses).Has(exe)
}

; The Xbox FSE task/application switcher, and anything else on the overlay list.
;
; The foreground check above cannot catch these. An overlay may be drawn on top
; without ever taking the foreground, so the foreground still reads as Steam or
; the game -- and Steam Assist then "returns to Steam", which dismisses the
; switcher the instant it appears. This looks at what is actually on screen.
;
; Three conditions must all hold, so an ordinary background window from a listed
; process cannot suspend assistance forever:
;   1. the exe or class is on the list,
;   2. the window is topmost or owns the foreground,
;   3. it covers most of its monitor.
;
; Returns a description of the matching window, or "" for no match.
AssistShellOverlayVisible(inventory) {
    global AssistSuspendOnShellOverlay, AssistShellOverlayProcesses
    static WS_EX_TOPMOST := 0x00000008
    if !AssistSuspendOnShellOverlay
        return ""
    exeSet := Map()
    classSet := Map()
    for _, entry in StrSplit(AssistShellOverlayProcesses, "|") {
        entry := Trim(entry)
        if (entry = "")
            continue
        if (SubStr(entry, 1, 6) = "class:")
            classSet[StrLower(SubStr(entry, 7))] := true
        else
            exeSet[StrLower(entry)] := true
    }
    if (exeSet.Count = 0 && classSet.Count = 0)
        return ""

    ; 1. The foreground window, inspected DIRECTLY rather than looked up in the
    ;    inventory.
    ;
    ;    This is the path that actually catches the FSE switcher, and the reason
    ;    the first attempt at this check did nothing. Measured 2026-07-25: the
    ;    switcher is an explorer.exe window of class XamlExplorerHostIslandWindow
    ;    and it does own the foreground -- but XAML island hosts are tool
    ;    windows, and AssistInventoryBuild drops tool windows on purpose. With
    ;    the switcher open the inventory held exactly one window, Steam. Any
    ;    check that starts from the inventory is looking somewhere the switcher
    ;    will never be.
    hwnd := 0
    try hwnd := WinExist("A")
    if (hwnd && !IsOurWindow(hwnd)) {
        foregroundExe := ""
        foregroundClass := ""
        try foregroundExe := StrLower(WinGetProcessName("ahk_id " hwnd))
        try foregroundClass := WinGetClass("ahk_id " hwnd)
        ; No size test here. Owning the foreground while matching a listed exe
        ; or class is specific enough on its own, and the geometry of a shell
        ; island window is not reliably reported.
        if (exeSet.Has(foregroundExe) || classSet.Has(StrLower(foregroundClass)))
            return foregroundExe " [" foregroundClass "] foreground"
    }

    ; 2. Overlays that are drawn on top without owning the foreground. These do
    ;    show up in the inventory, and here the size and topmost tests matter:
    ;    without them an ordinary background window from a listed process would
    ;    suspend assistance indefinitely.
    foregroundHwnd := hwnd
    for _, item in inventory {
        if item["ours"]
            continue
        if (!exeSet.Has(item["exe"]) && !classSet.Has(StrLower(item["class"])))
            continue
        exStyle := 0
        try exStyle := WinGetExStyle("ahk_id " item["hwnd"])
        if (!(exStyle & WS_EX_TOPMOST) && item["hwnd"] != foregroundHwnd)
            continue
        monitorIndex := GetMonitorIndexForWindow(item["hwnd"])
        try MonitorGet(monitorIndex, &left, &top, &right, &bottom)
        catch
            continue
        if (right - left <= 0 || bottom - top <= 0)
            continue
        if (item["w"] < (right - left) * 0.60 || item["h"] < (bottom - top) * 0.60)
            continue
        return item["exe"] " [" item["class"] "]"
    }
    return ""
}

; Logs everything currently on screen, after a delay, so the window identity of a
; transient surface can be captured.
;
; The FSE switcher's window identity is not documented and changes between
; Windows builds, so guessing it in the default list is not good enough. This
; makes it a 10-second measurement instead: start the probe, open the switcher,
; read the log, add whatever it names to ShellOverlayProcesses.
;
; It only reads and logs; nothing is activated, closed or resized.
StartScreenProbe(delayMs := 6000) {
    LogLine("Screen probe: capturing in " Round(delayMs / 1000) " seconds -- "
        . "bring the surface you want identified on screen now.")
    ShowNotification("Screen probe: capturing in " Round(delayMs / 1000) "s, see the log")
    SetTimer(RunScreenProbe, -delayMs)
}

RunScreenProbe() {
    static WS_EX_TOPMOST := 0x00000008
    foregroundHwnd := 0
    foregroundExe := ""
    foregroundClass := ""
    try foregroundHwnd := WinExist("A")
    if foregroundHwnd {
        try foregroundExe := WinGetProcessName("ahk_id " foregroundHwnd)
        try foregroundClass := WinGetClass("ahk_id " foregroundHwnd)
    }
    LogLine("Screen probe: foreground is " (foregroundExe != "" ? foregroundExe : "unknown")
        . " [" foregroundClass "] hwnd=" foregroundHwnd ".")
    ; Every top-level window, NOT the assist inventory.
    ;
    ; The inventory is deliberately narrow -- it drops invisible, cloaked and
    ; tool windows because none of those are things to activate or close. That
    ; makes it exactly the wrong list for identifying a surface: the Xbox FSE
    ; switcher is a tool window, so an inventory-based probe reports "1 window,
    ; Steam" while the switcher is filling the screen. Each excluded window is
    ; listed here with the reason it was excluded, because the reason is usually
    ; the interesting part.
    ;
    ; Hence includeHidden, rather than a third enumeration. The reasons printed
    ; below are now the inventory's OWN flags, so the probe cannot disagree with
    ; the list it is explaining -- which it could, and quietly would, while it
    ; recomputed all four of them from the window a second time.
    shown := 0
    hidden := 0
    for _, item in SharedWindowInventoryBuild(true) {
        hwnd := item["hwnd"]
        title := item["title"]
        isForeground := hwnd = foregroundHwnd
        ; An untitled, invisible, zero-sized window is noise. The foreground is
        ; always reported whatever shape it is in.
        if (!isForeground && !item["visible"] && title = "") {
            hidden += 1
            continue
        }
        reasons := ""
        if !item["visible"]
            reasons .= " hidden"
        if item["cloaked"]
            reasons .= " cloaked"
        if item["toolWindow"]
            reasons .= " toolwindow"
        if item["degenerate"]
            reasons .= " zero-size"
        shown += 1
        LogLine("Screen probe:   " (item["exe"] != "" ? item["exe"] : "?")
            . " [" item["class"] "]"
            . " " item["w"] "x" item["h"] " at " item["x"] "," item["y"]
            . ((item["exStyle"] & WS_EX_TOPMOST) ? " topmost" : "")
            . (isForeground ? " FOREGROUND" : "")
            . (item["ours"] ? " (ours)" : "")
            . (reasons != "" ? "  excluded-from-inventory:" reasons : "")
            . " title='" ShortenText(title, 50) "'")
    }
    LogLine("Screen probe: listed " shown " window" (shown = 1 ? "" : "s")
        . ", skipped " hidden " untitled hidden window"
        . (hidden = 1 ? "" : "s") ".")
    ; Age 0 forces a fresh enumeration rather than reusing the cached inventory.
    inventory := AssistInventoryGet(0)
    LogLine("Screen probe: assist inventory holds " inventory.Length " of them. "
        . "A window missing here but present above cannot be matched by an "
        . "inventory scan, only by the foreground check.")
    overlay := AssistShellOverlayVisible(inventory)
    LogLine("Screen probe: shell overlay match = "
        . (overlay != "" ? overlay : "none")
        . ". Add an exe or class: entry to [Assist] ShellOverlayProcesses to match one.")
    ShowNotification("Screen probe complete — see the log")
}

AssistActivate(item, reason) {
    global AssistLastFocusHwnd, AssistLastFocusTick
    hwnd := item["hwnd"]
    ; Bounded: never re-assert the same window more than once every few seconds,
    ; so a window that refuses to come forward cannot become a focus war.
    if (hwnd = AssistLastFocusHwnd && A_TickCount - AssistLastFocusTick < 5000)
        return false
    AssistLastFocusHwnd := hwnd
    AssistLastFocusTick := A_TickCount
    activated := false
    try {
        WinActivate("ahk_id " hwnd)
        activated := WinActive("ahk_id " hwnd) != 0
    }
    LogLine("Assist: " reason " -> " (activated ? "activated" : "could not activate")
        . " '" item["title"] "' (" item["exe"] ").",
        activated ? "Info" : "Warning")
    return activated
}

AssistCloseLaunchers(inventory) {
    global AssistLauncherProcesses, AssistProtectedProcesses
    global AssistGracefulCloseMs, AssistHardKill
    global AssistPendingHardKillPids
    launcherSet := ProcessNameSetFromList(AssistLauncherProcesses)
    protectedSet := ProcessNameSetFromList(AssistProtectedProcesses)
    SetTimer(AssistHardKillLaunchers, 0)
    AssistPendingHardKillPids := Map()
    targets := Map()
    for _, item in inventory {
        exe := item["exe"]
        if (item["ours"] || !launcherSet.Has(exe) || protectedSet.Has(exe))
            continue
        pid := item["pid"]
        if (pid && !targets.Has(pid))
            targets[pid] := Map("exe", exe, "hwnd", item["hwnd"])
    }
    ; Launchers that are running without a visible window still count.
    for exe in launcherSet {
        if protectedSet.Has(exe)
            continue
        found := false
        for _, target in targets {
            if (target["exe"] = exe) {
                found := true
                break
            }
        }
        if found
            continue
        pid := ProcessExist(exe)
        if pid
            targets[pid] := Map("exe", exe, "hwnd", 0)
    }
    if (targets.Count = 0)
        return 0
    closed := 0
    for pid, target in targets {
        exe := target["exe"]
        hwnd := target["hwnd"]
        sample := AssistProcessCpuSample(pid)
        if sample.Has("creation") {
            AssistPendingHardKillPids[pid] := Map(
                "exe", exe, "creation", sample["creation"])
        } else if AssistHardKill {
            LogLine("Assist: launcher cleanup cannot safely force close " exe
                . " because its process identity could not be read.", "Warning")
        }
        ; Braces are required here: a braceless `if` body that is a `try` lets
        ; the following `else` bind to the try (AHK supports Try/Catch/Else),
        ; which is a syntax error without a catch.
        if hwnd {
            try WinClose("ahk_id " hwnd)
        } else {
            try WinClose("ahk_exe " exe)
        }
        closed += 1
        LogLine("Assist: launcher cleanup requested close of " exe ".")
    }
    if (AssistHardKill && AssistPendingHardKillPids.Count)
        SetTimer(AssistHardKillLaunchers, -AssistGracefulCloseMs)
    return closed
}

AssistHardKillLaunchers() {
    global CompanionDisabled, EnableLauncherCleanupLite, AssistHardKill
    global AssistRequireNoGame, AssistPendingHardKillPids
    global AssistLauncherProcesses, AssistProtectedProcesses
    pending := AssistPendingHardKillPids
    AssistPendingHardKillPids := Map()
    if (pending.Count = 0)
        return
    if (CompanionDisabled || !EnableLauncherCleanupLite || !AssistHardKill) {
        LogLine("Assist: launcher force-close cancelled because cleanup is disabled.")
        return
    }

    inventory := AssistInventoryGet(0)
    AssistPruneCpuSamples(inventory)
    if (AssistRequireNoGame && AssistGameIsRunning(inventory)) {
        LogLine("Assist: launcher force-close cancelled because a game is running.")
        return
    }

    launcherSet := ProcessNameSetFromList(AssistLauncherProcesses)
    protectedSet := ProcessNameSetFromList(AssistProtectedProcesses)
    for pid, expected in pending {
        if (!launcherSet.Has(expected["exe"])
            || protectedSet.Has(expected["exe"]))
            continue
        if !ProcessExist(pid)
            continue
        actualExe := ""
        try actualExe := StrLower(ProcessGetName(pid))
        if (actualExe != expected["exe"])
            continue
        sample := AssistProcessCpuSample(pid)
        if (!sample.Has("creation")
            || sample["creation"] != expected["creation"])
            continue
        try {
            ProcessClose(pid)
            LogLine("Assist: launcher cleanup force closed " actualExe
                . " (PID " pid ").", "Warning")
        } catch as err {
            LogLine("Assist: launcher cleanup could not force close " actualExe
                . " (PID " pid "): " err.Message ".", "Warning")
        }
    }
}

; One timer drives all three assist features, in priority order, so they can
; never issue competing focus requests in the same pass.
AssistTick() {
    global EnableGameFocusLite, EnableSteamAssistLite, EnableLauncherCleanupLite
    global AssistRequireNoGame, AssistForegroundStableSec, AssistCooldownSec
    global AssistForegroundSteadySince, AssistLastCleanupTick
    global AssistShellOverlayLastLogTick

    if (!EnableGameFocusLite && !EnableSteamAssistLite && !EnableLauncherCleanupLite)
        return
    if AssistShouldSuspend()
        return

    inventory := AssistInventoryGet(0)
    AssistPruneCpuSamples(inventory)

    ; A shell overlay such as the Xbox FSE task switcher is on screen. Do nothing
    ; at all this pass -- returning to Steam here would dismiss the very surface
    ; the user just opened. Checked after the inventory because it needs the
    ; window list, unlike the cheaper guards in AssistShouldSuspend.
    overlay := AssistShellOverlayVisible(inventory)
    if (overlay != "") {
        ; Rate limited: this can be true for as long as the switcher is open, and
        ; one line per tick would bury everything else in the log.
        if (!AssistShellOverlayLastLogTick
            || A_TickCount - AssistShellOverlayLastLogTick > 10000) {
            AssistShellOverlayLastLogTick := A_TickCount
            LogLine("Assist: suspended, shell overlay on screen (" overlay ").")
        }
        return
    }

    foregroundHwnd := 0
    foregroundExe := ""
    try foregroundHwnd := WinExist("A")
    if foregroundHwnd
        try foregroundExe := StrLower(WinGetProcessName("ahk_id " foregroundHwnd))

    gameWindow := AssistFindGameWindow(inventory)
    gameRunning := AssistGameIsRunning(inventory)

    ; Track how long the foreground has been settled, used as the cleanup gate.
    static lastForegroundExe := ""
    if (foregroundExe != lastForegroundExe) {
        lastForegroundExe := foregroundExe
        AssistForegroundSteadySince := A_TickCount
    }
    steadyMs := AssistForegroundSteadySince ? A_TickCount - AssistForegroundSteadySince : 0

    ; Never take focus from an FSE surface or the Windows shell.
    canTakeFocus := foregroundExe != "" && !AssistForegroundIsProtected(foregroundExe)

    ; 1. Game Focus Lite -- put the game back in front if something stole it.
    if (EnableGameFocusLite && canTakeFocus && IsObject(gameWindow)) {
        if (foregroundHwnd != gameWindow["hwnd"] && foregroundExe != gameWindow["exe"]) {
            AssistActivate(gameWindow, "game focus")
            return
        }
    }

    ; 2. Steam Assist Lite -- with no game present, return to Steam.
    if (EnableSteamAssistLite && canTakeFocus && !gameRunning) {
        steamWindow := AssistFindSteamWindow(inventory)
        if (IsObject(steamWindow) && foregroundHwnd != steamWindow["hwnd"]
            && !IsSteamProcess(foregroundExe)) {
            AssistActivate(steamWindow, "steam assist")
            return
        }
    }

    ; 3. Launcher Cleanup Lite -- only when nothing is playing, the foreground
    ;    has been settled for a while, and the cooldown has elapsed.
    if !EnableLauncherCleanupLite
        return
    if (AssistRequireNoGame && gameRunning)
        return
    if (steadyMs < AssistForegroundStableSec * 1000)
        return
    if (AssistLastCleanupTick
        && A_TickCount - AssistLastCleanupTick < AssistCooldownSec * 1000)
        return
    AssistLastCleanupTick := A_TickCount
    closed := AssistCloseLaunchers(inventory)
    if closed
        ShowNotification("Launcher cleanup closed " closed " launcher"
            . (closed = 1 ? "" : "s"))
}

; A ROW VALUE, so this runs on every Quick Menu repaint. It takes the cached
; inventory; the task PAGE, which is the list the user then acts on, does not.
GetSwitchableWindowsSummary() {
    count := SharedTaskSwitcherWindows(1000).Length
    if (count = 0)
        return "No Windows"
    return count " window" (count = 1 ? "" : "s")
}

ActivateSwitchableWindow(hwnd) {
    if !DllCall("IsWindow", "Ptr", hwnd) {
        ShowNotification("That window is no longer available", "Warning")
        QuickMenuBuildGui()
        return
    }
    title := ""
    try title := WinGetTitle("ahk_id " hwnd)
    HideQuickMenu()
    ; One-shot activation only. No pinning, no repeat enforcement: if Xbox FSE
    ; decides something else belongs in front afterwards, that is its call.
    activated := false
    try {
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            WinRestore("ahk_id " hwnd)
        WinActivate("ahk_id " hwnd)
        activated := WinActive("ahk_id " hwnd) != 0
    }
    LogLine("Task switcher: " (activated ? "activated" : "could not activate")
        . " '" title "'.", activated ? "Info" : "Warning")
    if !activated
        ShowNotification("Windows could not activate that window", "Warning")
}

CloseSwitchableWindow(hwnd, force := false) {
    if !DllCall("IsWindow", "Ptr", hwnd) {
        QuickMenuBuildGui()
        return
    }
    title := ""
    try title := WinGetTitle("ahk_id " hwnd)
    if force {
        pid := 0
        try pid := WinGetPID("ahk_id " hwnd)
        if pid {
            try ProcessClose(pid)
            LogLine("Task switcher: force closed '" title "' (PID " pid ").", "Warning")
        }
    } else {
        try WinClose("ahk_id " hwnd)
        LogLine("Task switcher: close requested for '" title "'.")
    }
    ; Give the window a moment to go before the list is rebuilt. BuildGui, not
    ; Refresh: a repaint no longer re-composes the rows, and the closed window
    ; has to leave the list.
    SetTimer(QuickMenuBuildGui, -400)
}

; X closes the selected window; X again within the confirm window escalates to
; terminating its process. A second press is used rather than a hold because the
; Quick Menu handler only receives button-down edges, and because the status
; line can explain the escalation where a silent hold cannot.
QuickMenuCloseSelected() {
    global QuickMenuRows, QuickMenuSelected
    global QuickMenuConfirmAction, QuickMenuConfirmUntilTick
    if (QuickMenuRows.Length = 0)
        return
    id := QuickMenuRows[QuickMenuSelected]["id"]
    if (SubStr(id, 1, 11) != "taskWindow:")
        return
    hwnd := Round(SubStr(id, 12) + 0)
    title := ""
    try title := WinGetTitle("ahk_id " hwnd)
    confirmId := "forceclose:" hwnd
    if (QuickMenuConfirmAction = confirmId && A_TickCount < QuickMenuConfirmUntilTick) {
        QuickMenuConfirmAction := ""
        CloseSwitchableWindow(hwnd, true)
        ShowNotification("Force closed " ShortenText(title, 30), "Warning")
        return
    }
    CloseSwitchableWindow(hwnd, false)
    QuickMenuConfirmAction := confirmId
    QuickMenuConfirmUntilTick := A_TickCount + 5000
    ShowNotification("Closing " ShortenText(title, 26) " — press X again to force", "Warning")
}

; ==============================================================================
; Controller-first Quick Menu
; ==============================================================================
MenuRow(id, label, value := "", action := "", adjustable := false) {
    return Map(
        "id", id,
        "label", label,
        "value", value,
        "action", action,
        "adjustable", adjustable
    )
}

QuickMenuGetRows() {
    global QuickMenuPage
    global QuickMenuDisplayModes
    global RtssOverlayControlMode, RtssFrameLimiterControlMode
    global EnableRTSSIntegration, RtssPath
    global QuickMenuPreviousExe, QuickMenuTaskWindows, QuickMenuTaskPage
    global SteamMenuShortcut, SteamQuickAccessShortcut, SteamOverlayShortcut
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    global DisplaySelectedScalePercent
    global EnablePersistentMouseMode
    global RtssPendingFrameCap
    global EnableGameDetectionMenu, LastGameCandidates
    global QuickMenuMainOrder, QuickMenuHiddenItems
    rows := []
    switch QuickMenuPage {
        case "MAIN":
            ; Composed from QuickMenuMainOrder, the same way the shell does it,
            ; so the shared layout manager reorders and hides rows here too.
            ; Audio and Display used to be gated by their own Enable keys; that
            ; is what HiddenItems does, and doing it twice meant two settings
            ; could disagree about one row.
            available := Map(
                "audio", MenuRow("audioMenu", "Audio", "", "page:AUDIO"),
                "display", MenuRow("display", "Display & HDR", "", "page:DISPLAY"),
                "rtss", MenuRow("rtssMenu", "RTSS & Performance", "", "page:RTSS"),
                "steammenu", MenuRow("steamMenu", "Steam Menu", "", "steamMenu"),
                "steamquickaccess", MenuRow("steamQuickAccess", "Steam Quick Access", "",
                    "steamQuickAccess"),
                "tasks", MenuRow("tasks", "Task Switcher", "", "page:TASKS"),
                "gamebar", MenuRow("gameBar", "Game Bar", "", "gameBar"),
                "keyboard", MenuRow("openKeyboard", "Open Keyboard", "", "openKeyboard"),
                ; The action is the row id. It used to be "toggle:mouseMode",
                ; which nothing answered to -- the lookup returned nothing, the
                ; toggle returned early, and the row rendered and selected and
                ; did nothing at all. Deriving the action from the id is what
                ; stops that being expressible.
                "mousemode", MenuRow("qPersistentMouse", "Mouse Mode", "",
                    "toggle:qPersistentMouse", true),
                "settings", MenuRow("settings", "Settings", "", "page:SETTINGS"),
                "system", MenuRow("system", "System", "", "page:SYSTEM"))
            added := Map()
            for _, itemName in QuickMenuMainOrder {
                if !available.Has(itemName)
                    continue
                if (QuickMenuHiddenItems.Has(itemName)
                    && itemName != "settings" && itemName != "system")
                    continue
                rows.Push(available[itemName])
                added[itemName] := true
            }
            ; Settings and System are recovery paths and can never be hidden or
            ; lost through a malformed order string.
            for _, requiredName in ["settings", "system"] {
                if !added.Has(requiredName)
                    rows.Push(available[requiredName])
            }
        case "SETTINGS":
            ; A hub, the way the shell's is. The rows outgrew one screen once
            ; the settings the companion already honoured but could not reach
            ; from a controller were given rows of their own.
            rows.Push(MenuRow("back", "Back", "", "back"))
            rows.Push(MenuRow("settingsCompanion", "Companion + Assist", "",
                "page:SETTINGS_COMPANION"))
            rows.Push(MenuRow("settingsInput", "Controller + Cursor", "",
                "page:SETTINGS_INPUT"))
            rows.Push(MenuRow("settingsRtss", "RTSS + Performance", "",
                "page:SETTINGS_RTSS"))
            rows.Push(MenuRow("windowsSettings", "Windows Settings", "", "windowsSettings"))
            ; The one row that opens the full editor, on the hub, in the shell's
            ; words. It used to sit at the bottom of every sub-page, so three
            ; pages each offered their own "All Settings..." and the hub -- where
            ; the shell puts it -- offered none.
            ;
            ; settingsEditor, not settings: MAIN already owns "settings" as the
            ; row that opens this page, and under id-keyed lookup a second row
            ; sharing that id would answer for the first.
            rows.Push(MenuRow("settingsEditor", "Open Full Settings Editor", "",
                "settingsEditor"))
        case "SETTINGS_COMPANION", "SETTINGS_INPUT":
            rows.Push(MenuRow("back", "Back To Settings", "", "page:SETTINGS"))
            for _, row in QuickMenuSettingsRows(QuickMenuPage)
                rows.Push(row)
        case "SETTINGS_RTSS":
            rows.Push(MenuRow("back", "Back To Settings", "", "page:SETTINGS"))
            for _, row in QuickMenuSettingsRows(QuickMenuPage)
                rows.Push(row)
            ; The shell keeps an editor row on THIS page and no other, because
            ; RTSS is where paths and shortcuts are edited and neither fits a
            ; controller. Its words, too.
            rows.Push(MenuRow("settingsEditor", "Edit Paths + Shortcuts", "",
                "settingsEditor"))
        case "TASKS":
            rows.Push(MenuRow("back", "Back", "", "back"))
            QuickMenuTaskWindows := SharedTaskSwitcherWindows()
            if (QuickMenuTaskWindows.Length = 0) {
                rows.Push(MenuRow("tasksUnavailable", "No Switchable Windows", "", "none"))
            } else {
                ; Paged, not truncated. This used to be Loop Min(count, 13) to
                ; fit the control pool, which meant a fourteenth window could not
                ; be reached and nothing on screen said so.
                QuickMenuTaskSlice(QuickMenuTaskWindows.Length,
                    &firstIndex, &lastIndex, &pageCount)
                Loop lastIndex - firstIndex + 1 {
                    item := QuickMenuTaskWindows[firstIndex + A_Index - 1]
                    rows.Push(MenuRow("taskWindow:" item["hwnd"],
                        ShortenText(item["title"], 34), "", "taskWindow:" item["hwnd"]))
                }
                if (pageCount > 1) {
                    pageText := QuickMenuTaskPage " / " pageCount
                    rows.Push(MenuRow("taskPrev", "Previous Page", pageText,
                        "taskPrev", true))
                    rows.Push(MenuRow("taskNext", "Next Page", pageText,
                        "taskNext", true))
                }
            }
        case "AUDIO":
            rows.Push(MenuRow("back", "Back", "", "back"))
            rows.Push(MenuRow("audioOutput", "Output", "", "audioOutput", true))
            rows.Push(MenuRow("volume", "Volume", "", "volume", true))
            rows.Push(MenuRow("mute", "Mute", "", "mute"))
        case "DISPLAY":
            ; Resolution, refresh rate, and Windows Scale are independent
            ; choices, so they get a row each rather than being flattened into
            ; one list of combinations. Cycling only stages values; Apply owns
            ; the real, guarded display transaction.
            rows.Push(MenuRow("back", "Back", "", "back"))
            hdr := GetPrimaryHdrState()
            if IsObject(hdr) && hdr["supported"] {
                hdrValue := hdr["forceDisabled"]
                    ? "Disabled By Windows"
                    : "‹ " (hdr["enabled"] ? "ON" : "OFF") " ›"
                hdrAction := hdr["forceDisabled"] ? "none" : "hdr"
                rows.Push(MenuRow("hdr", "HDR", "", hdrAction, !hdr["forceDisabled"]))
            } else {
                rows.Push(MenuRow("hdrUnavailable", "HDR", "", "none"))
            }
            if (QuickMenuDisplayModes.Length = 0)
                QuickMenuDisplayModes := GetPrimaryDisplayModes()
            if (QuickMenuDisplayModes.Length = 0) {
                rows.Push(MenuRow("displayUnavailable", "No Compatible Modes Reported", "", "none"))
            } else {
                EnsureDisplaySelection()
                rows.Push(MenuRow("displayResolution", "Resolution", "", "displayResolution", true))
                rows.Push(MenuRow("displayRefresh", "Refresh Rate", "", "displayRefresh", true))
                scale := EnsureDisplayScaleSelection()
                if IsObject(scale) {
                    rows.Push(MenuRow("displayScale", "Scale", "", "displayScale", true))
                } else {
                    rows.Push(MenuRow("displayScaleUnavailable", "Scale", "", "none"))
                }
                rows.Push(MenuRow("displayApply", "Apply", "", "displayApply"))
            }
        case "RTSS":
            rows.Push(MenuRow("back", "Back", "", "back"))
            rtssRunning := ProcessExist("RTSS.exe") != 0
            if !rtssRunning {
                if !EnableRTSSIntegration {
                    rows.Push(MenuRow("rtssDisabled", "RTSS Integration", "", "none"))
                } else if ResolveRtssExecutablePath() != "" {
                    rows.Push(MenuRow("rtssStart", "Start RTSS", "", "rtssStart"))
                } else {
                    rows.Push(MenuRow("rtssMissing", "RTSS", "", "none"))
                }
            } else {
                rtssState := GetRtssGlobalState()
                if IsObject(rtssState) {
                    rows.Push(MenuRow("rtssOverlayState", "Overlay", "", "rtssOverlayState", true))
                    ; One row for the limiter flag and its target. The separate
                    ; "Frame Limiter" row is gone here on purpose: with live DLL
                    ; control, two rows that can each mean "no limiting" only
                    ; fight each other. The shortcut fallback below still needs
                    ; both, because without the DLL there is no value to fold in.
                    rows.Push(MenuRow("rtssFrameLimit", "Frame Limit", "", "rtssFrameLimit", true))
                    capState := GetRtssFrameCapState()
                    if (IsObject(capState) && capState["mode"] = "custom")
                        ; A pending value is what the user is looking at and
                        ; adjusting; the live one has not caught up yet by design.
                        rows.Push(MenuRow("rtssFrameLimitCustom", "Custom FPS", "", "rtssFrameLimitCustom", true))
                    ; Always present, even with nothing to save to: the value
                    ; column explains why rather than the row disappearing,
                    ; which would read as the feature being missing.
                    rows.Push(MenuRow("rtssSaveProfile", "Save Limit To Profile", "", "rtssSaveProfile"))
                } else if (RtssOverlayControlMode = "separate") {
                    rows.Push(MenuRow("overlayOn", "Overlay On", "", "overlayOn"))
                    rows.Push(MenuRow("overlayOff", "Overlay Off", "", "overlayOff"))
                } else {
                    rows.Push(MenuRow("overlayToggle", "Toggle Overlay", "",
                        "overlayToggle"))
                }
                if !IsObject(rtssState) {
                    if (RtssFrameLimiterControlMode = "separate") {
                        rows.Push(MenuRow("limiterOn", "Frame Limiter On", "", "limiterOn"))
                        rows.Push(MenuRow("limiterOff", "Frame Limiter Off", "",
                            "limiterOff"))
                    } else {
                        rows.Push(MenuRow("limiterToggle", "Toggle Frame Limiter", "", "limiterToggle"))
                    }
                }
            }
            rows.Push(MenuRow("rtssSettings", "RTSS Settings", "", "rtssSettings"))
        case "LAYOUT":
            rows.Push(MenuRow("back", "Back", "", "back"))
            for _, button in ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "Start", "L3", "R3"] {
                value := ControllerBindingPretty(button ".Short")
                longValue := ControllerBindingPretty(button ".Long")
                if (longValue != "None")
                    value .= "  /  Hold: " longValue
                rows.Push(MenuRow("layout:" button, button, "", "none"))
            }
            rows.Push(MenuRow("setControllerMappings", "Set Controller Mappings", "", "setControllerMappings"))
        case "SYSTEM":
            rows.Push(MenuRow("back", "Back", "", "back"))
            rows.Push(MenuRow("sleep", "Sleep", "", "sleep"))
            rows.Push(MenuRow("restart", "Restart", "", "restart"))
            rows.Push(MenuRow("shutdown", "Shut Down", "", "shutdown"))
            if EnableGameDetectionMenu
                rows.Push(MenuRow("gameDetection", "Game Detection", "", "page:GAMESCORE"))
            ; Beside Game Detection, not folded into it. That page is a read-only
            ; explanation of what the scorer decided; this one WRITES settings.
            rows.Push(MenuRow("currentApp", "Current Application",
                QuickMenuCurrentAppValue(), "currentApp"))
            rows.Push(MenuRow("exitApp", "Exit Companion", "", "exitApp"))
        ; The destinations are decided in SteamShell-Shared.ahk; only the row
        ; shape is this tree's. Same split as GAMESCORE below.
        case "CURRENTAPP":
            rows.Push(MenuRow("back", "Back", "", "back"))
            reason := QuickMenuCurrentAppBlockedReason()
            if (reason != "") {
                rows.Push(MenuRow("currentAppBlocked", reason, "", "none"))
            } else {
                for _, rowId in QuickMenuAppTargetIds("xfe")
                    rows.Push(MenuRow(rowId,
                        QuickMenuAppTargetLabel(rowId, "xfe"), "Add", rowId))
            }
        ; Read-only. Every number was already computed to choose a game; this
        ; only shows the losers beside the winner.
        case "GAMESCORE":
            rows.Push(MenuRow("back", "Back", "", "back"))
            if (LastGameCandidates.Length = 0) {
                rows.Push(MenuRow("gameScoreEmpty", "No candidates scored yet",
                    "", "none"))
            } else {
                for _, rowId in QuickMenuGameScoreIds()
                    rows.Push(MenuRow(rowId, QuickMenuGameScoreLabel(rowId), "", "none"))
            }
    }
    return rows
}

OnOffText(value) {
    return value ? "On" : "Off"
}

; The switches the Quick Menu's Settings page exposes.
;
; Each one is the same setting the full Settings window edits, addressed here by
; a short id so the row table, the toggle and the label all stay in one place. A
; toggle from the Quick Menu writes the INI immediately and then updates the
; live global, so it takes effect at once AND survives a restart. The full
; Settings window's Save button is not involved.
; The live value behind a QuickMenuToggleTable row, by ROW ID.
;
; The product seam standalone already had. AutoHotkey v2 cannot read a global by
; a name held in a variable, so the shared table carries the section and the key
; but not the current state, and each product answers for its own globals here.
;
; This tree used to answer with a QuickMenuToggleMeta() that returned section,
; key, label AND value from one `switch` -- the same routine as the shared table
; plus this function, under a different name, which is why neither the
; fingerprint gate nor DIVERGENT_FUNCTIONS.txt could see the duplicate.
ProductSettingBool(id) {
    global EnableGameFocusLite, EnableSteamAssistLite, EnableLauncherCleanupLite
    global AssistSuspendOnShellOverlay
    global EnableViewSteamActions, EnableViewTapAction, EnableViewHoldAction
    global EnableControllerMouseMode, EnableAutoHideCursor
    global EnableMouseParkOnBoot, EnableRTSSIntegration
    switch id {
        case "gameFocus": return EnableGameFocusLite
        case "steamAssist": return EnableSteamAssistLite
        case "launcherCleanup": return EnableLauncherCleanupLite
        case "shellOverlay": return AssistSuspendOnShellOverlay
        case "viewActions": return EnableViewSteamActions
        case "viewTap": return EnableViewTapAction
        case "viewHold": return EnableViewHoldAction
        ; The four the shell already had rows for. The settings exist here and
        ; are honoured here; until now there was simply no way to reach them
        ; from a controller.
        case "qControllerMouse": return EnableControllerMouseMode
        case "qAutoHideCursor": return EnableAutoHideCursor
        case "qParkBoot": return EnableMouseParkOnBoot
        case "qRtssIntegration": return EnableRTSSIntegration
    }
    return false
}

; Flips one Quick Menu switch and makes it stick.
;
; `label` comes from the row the user is standing on rather than from a table:
; the row already carries the words shown on screen, and a second copy beside
; the section and key is a second thing to keep in step.
;
; The live globals are NOT assigned here. This used to write the INI and then
; hand-assign each global in a `switch` over the same ids -- so every new row
; cost two edits in two places, and forgetting the second gave a row that
; toggled, persisted, logged "-> ON" and changed nothing until the next restart.
; LoadSettings() re-reads all of them from the file that was just written, which
; is what Reload and Save & Apply already do, so the id list exists once.
QuickMenuToggleSetting(id, label := "") {
    if (label = "")
        label := id
    if (id = "qPersistentMouse") {
        QuickMenuTogglePersistentMouse(label)
        return
    }
    ; The rows that flip between two named states rather than on and off.
    if QuickMenuCycleSharedSetting(id) {
        LogLine("Quick Menu: " label " -> " QuickMenuSettingValueText(id) ".")
        ShowNotification(label ": " QuickMenuSettingValueText(id))
        return
    }
    if !QuickMenuToggleTable().Has(id)
        return
    entry := QuickMenuToggleTable()[id]
    next := !ProductSettingBool(id)
    ; Persistence is the transaction boundary. Do not claim success, or report a
    ; new state, if the portable INI is read-only or otherwise unwritable.
    if !ProductApplyQuickMenuSetting(entry["section"], entry["key"],
        next ? "true" : "false")
        return
    LogLine("Quick Menu: " label " -> " OnOffText(next) ".")
    ShowNotification(label ": " OnOffText(next))
}

; Mouse Mode is not in QuickMenuToggleTable because turning it on has to turn
; the controller-mouse master on with it -- one row, two keys -- and a failure
; part-way has to leave neither written. Standalone keeps it out of the table
; for the same reason.
QuickMenuTogglePersistentMouse(label) {
    global IniPath, EnablePersistentMouseMode, EnableControllerMouseMode
    next := !EnablePersistentMouseMode
    enabledControllerMaster := false
    try {
        if (next && !EnableControllerMouseMode) {
            IniWrite("true", IniPath, "Controller", "EnableControllerMouseMode")
            enabledControllerMaster := true
        }
        IniWrite(next ? "true" : "false",
            IniPath, "Controller", "EnablePersistentMouseMode")
    } catch as err {
        if enabledControllerMaster
            try IniWrite("false", IniPath, "Controller", "EnableControllerMouseMode")
        LogLine("Quick Menu: could not save " label " (" err.Message ").", "Warning")
        ShowNotification("Could not save " label, "Warning")
        return
    }
    LoadSettings()
    SetFieldValue("Controller.EnablePersistentMouseMode", next)
    if enabledControllerMaster
        SetFieldValue("Controller.EnableControllerMouseMode", true)
    LogLine("Quick Menu: " label " -> " OnOffText(next) ".")
    ShowNotification(label ": " OnOffText(next))
}

; Rows for the Quick Menu's Settings page: the switches worth reaching from the
; couch, without opening the full Settings window on a TV.
QuickMenuSettingsRows(page := "SETTINGS") {
    rows := []
    ; Label beside the id, the way standalone's row builders state theirs. The
    ; words belong to the row; the section and key belong to the shared table.
    ;
    ; Split across the same pages the shell uses, and in the same order, because
    ; the point of these rows is that someone who configured one product finds
    ; the same switch in the same place in the other. The companion's own assist
    ; and View-button rows stay on the first page: they have no shell equivalent
    ; to sit beside.
    if (page = "SETTINGS_COMPANION") {
        for _, entry in [
            ["gameFocus", "Game Focus Lite"],
            ["steamAssist", "Steam Assist Lite"],
            ["launcherCleanup", "Launcher Cleanup Lite"],
            ["shellOverlay", "Pause Assist On FSE Switcher"],
            ["viewActions", "View Button Steam Actions"],
            ["viewTap", "View Tap Action"],
            ["viewHold", "View Hold Action"]]
            rows.Push(QuickMenuSettingRow(entry[1], entry[2]))
        rows.Push(QuickMenuSettingRow("qAccentColor", "Quick Menu Accent"))
        return rows
    }
    if (page = "SETTINGS_INPUT") {
        for _, entry in [
            ["qControllerMouse", "Controller Mouse"],
            ["qMouseSpeed", "Controller Mouse Speed"],
            ["qPersistentMouse", "Mouse Mode"],
            ["qAutoHideCursor", "Auto-Hide Cursor"],
            ["qMouseHideDelay", "Cursor Hide Delay"],
            ["qParkBoot", "Park Mouse On Boot"],
            ["qParkEdge", "Mouse Parking Edge"]]
            rows.Push(QuickMenuSettingRow(entry[1], entry[2]))
        return rows
    }
    if (page = "SETTINGS_RTSS") {
        for _, entry in [
            ["qRtssIntegration", "RTSS Integration"],
            ["qOverlayMode", "Overlay Controls"],
            ["qLimiterMode", "Frame Limiter Controls"],
            ["qFrameCap", "Preset Frame Cap"]]
            rows.Push(QuickMenuSettingRow(entry[1], entry[2]))
        return rows
    }
    return rows
}

; One settings row. The action IS the id -- see the note beside the Mouse Mode
; row on MAIN for what happens when it is allowed to be anything else.
QuickMenuSettingRow(id, label) {
    return MenuRow("toggle:" id, label, QuickMenuSettingValueText(id),
        "toggle:" id, true)
}

ShortText(text, maxChars) {
    text := Trim(text)
    return StrLen(text) <= maxChars ? text : SubStr(text, 1, maxChars - 1) "…"
}

GetAudioOutputName() {
    try return ShortText(SoundGetName(), 34)
    return "Unavailable"
}

; Volume as a percentage, or an honest "Unavailable".
;
; The previous form was `try return Round(SoundGetVolume()) "%"`, which on the
; HTPC's NVIDIA HDMI endpoint produced a bare "%" -- the number went missing while
; the suffix survived, so the row looked broken rather than unsupported. Reading
; the value first and checking it before formatting means the only two outcomes
; are a real number or a stated failure, and the reason is logged once.
GetVolumeText() {
    static warned := false
    volume := ""
    try {
        volume := SoundGetVolume()
    } catch as err {
        if !warned {
            warned := true
            LogLine("Audio: volume is unreadable on this endpoint (" err.Message
                . ").", "Warning")
        }
        return "Unavailable"
    }
    if (volume = "" || !IsNumber(volume)) {
        if !warned {
            warned := true
            LogLine("Audio: volume query returned no value on this endpoint.",
                "Warning")
        }
        return "Unavailable"
    }
    return Round(volume) "%"
}

GetMuteText() {
    try return SoundGetMute() ? "ON" : "OFF"
    return "Unavailable"
}

; Audio summary for the main page, ordered so the volume survives.
;
; The value column is a right-aligned control, so anything too long is clipped
; from the LEFT. With the volume first, the volume was the part being thrown
; away: the row rendered as "%" or "6" while the Audio page showed 100% from the
; very same function. That looked like a broken volume reading and was
; misdiagnosed as one -- it is a column-width problem, not a formatting one.
;
; So the volume goes LAST, where clipping cannot reach it, and the device name is
; shortened further to make the whole thing likely to fit. If anything is lost it
; is the middle of a device name, which is the part that matters least.
GetAudioSummary() {
    return ShortText(GetAudioOutputName(), 22) "  •  " GetVolumeText()
}


; ==============================================================================
; OPT-IN ELEVATED RTSS HELPER
; ==============================================================================
; What this is, and what it deliberately is not.
;
; XFE runs at medium integrity by design. Two consequences follow, and only one
; of them is fixed here.
;
;   1. UIPI blocks XFE's synthetic input from an elevated foreground window,
;      exactly as it blocked standalone's before 1.9.9. NOT FIXED, on purpose.
;      The remedy in SteamShell-Helper.ahk is XInput, and XFE exists precisely
;      because XInput is not enough for its users -- a controller in DirectInput
;      mode is not an XInput device at all. Elevated input would therefore have
;      worked only for the people who did not need XFE in the first place, while
;      costing every XFE user a permanently resident elevated process that polls
;      a controller. There is also a workaround: reach the window another way.
;
;   2. RTSSHooks64.dll is loaded into the CALLING process, so SaveProfile runs
;      with XFE's token, and RTSS installs under Program Files. An unelevated
;      XFE can read the cap and toggle the limiter flag -- shared memory, no
;      file -- but cannot set the FPS value or save a per-game profile. FIXED
;      here, because there is no workaround at all: the Frame Limit row reports
;      itself read-only and the feature does not function.
;
; The runtime posture is the real cost of any elevated helper, and this is the
; narrowest shape that answers (2): one High-integrity process that services a
; bounded request and does no input, no window management, and no UI. It is
; still OFF by default. The payload is deployed by Setup Assistant in XFE mode
; so the setting can be turned on later without re-running an installer, but a
; binary on disk is not an elevated process, and nothing starts it until the
; user asks.
;
; XFE never deploys, hardens, or extracts the helper: it has no embedded payload
; and no administrator rights. It verifies and launches, or it explains why it
; would not, and points at Setup.

; Fixed, and deliberately NOT inside XFE's own install directory.
;
; Setup grants the signed-in user write access to that directory -- XFE keeps
; its INI, learned controller profiles and log beside its executable -- and a
; user-writable parent can be deleted and recreated whole, which is exactly the
; reason standalone refuses to give its Custom and Portable layouts an
; independently invokable helper task. Program Files has the protected ancestor
; chain that makes the payload's own ACL mean something.
;
; A_ProgramFiles expands an environment variable this process inherited from
; whoever started it, so it is not evidence of anything on its own. It does not
; have to be: ElevatedHelperLocationIsProtected checks the owner and DACL of the
; path this resolves to, and a redirected value pointing somewhere the user can
; write fails that check and the helper is not launched.
XfeElevatedHelperPath() {
    return A_ProgramFiles "\SteamShell-XFE\bin\SteamShell-Helper.exe"
}

; Recorded once, from this process's own token.
XfeInitializeInteractiveIdentity() {
    global ExpectedInteractiveUserSid, ExpectedInteractiveSessionId
    if !GetCurrentProcessUserSid(&sidText, &sidError) {
        ExpectedInteractiveUserSid := ""
        LogLine("The companion's own user SID could not be read (" sidError
            . "); the elevated RTSS helper cannot be verified.", "Warning")
    } else {
        ExpectedInteractiveUserSid := sidText
    }
    if !GetCurrentProcessSessionId(&sessionId)
        sessionId := -1
    ExpectedInteractiveSessionId := sessionId
}

; ElevatedRtssRequestPath() is shared now. XFE keeping its data beside its
; executable was a reason to answer ProductDataDir() differently, not a reason
; to write the path builder twice; see that seam below.

; Explicit UAC, always. Standalone has a protected on-demand scheduled task for
; its Standard installation mode, which avoids a prompt; XFE does not get one
; and should not. A task registered at HighestAvailable can be invoked with
; schtasks /run without asking this process to re-check anything, so it is only
; safe where the whole path sits below a protected ancestor chain that Setup
; established. XFE's own directory is user-writable by design, and giving it an
; independently invokable auto-elevation task would reintroduce exactly the
; bypass standalone removed for its Custom mode.
;
; The prompt is therefore part of the feature rather than a wart on it: turning
; this on means seeing UAC when the companion starts, which is an honest
; representation of what was turned on.
; The companion's helper is started through a protected on-demand task when one
; can be registered, and by explicit UAC otherwise.
;
; A UAC prompt runs on the SECURE DESKTOP, where no process can inject input --
; not the companion, not the helper. On a handheld with only a controller that
; is not an annoyance, it is a dead end: the user has to find a keyboard. The
; task removes the prompt, and is only safe because the helper lives under
; %ProgramFiles%\SteamShell-XFE\bin where the interactive user cannot replace it.
;
; Registered lazily, the first time the opt-in is actually used, rather than at
; install: someone who never enables elevated frame-cap writes should never have
; a HighestAvailable task on their machine.
XfeElevatedHelperTaskName() {
    return "SteamShell XFE Elevated RTSS Helper"
}

EnsureXfeElevatedHelperTask(helperPath, &failureReason) {
    failureReason := ""
    if !ElevatedHelperLocationIsProtected(helperPath, &protectionError) {
        failureReason := "The helper location is not administrator-protected ("
            . protectionError ")."
        return false
    }
    if (RunSchTasks('/query /tn "' XfeElevatedHelperTaskName() '"') = 0)
        return true
    SplitPath(helperPath, , &helperDirectory)
    account := LogonTaskAccountForXml()
    xml := ElevatedHelperTaskXml(account, helperPath,
        SharedElevatedHelperArguments("xfe", 0, A_ScriptFullPath),
        helperDirectory)
    xmlPath := A_Temp "\SteamShell-XFE-helper-task.xml"
    try FileDelete(xmlPath)
    try FileAppend(xml, xmlPath, "UTF-16")
    catch as err {
        failureReason := "The task definition could not be written (" err.Message ")."
        return false
    }
    exitCode := RunSchTasks(
        '/create /f /tn "' XfeElevatedHelperTaskName() '" /xml "' xmlPath '"')
    try FileDelete(xmlPath)
    if (exitCode != 0) {
        failureReason := "schtasks /create returned " exitCode "."
        return false
    }
    LogLine("Registered the protected on-demand task '"
        . XfeElevatedHelperTaskName() "' so the elevated RTSS helper starts "
        . "without a UAC prompt.")
    return true
}

StartElevatedRtssHelper() {
    global RtssElevatedFrameCapWrites, ElevatedHelperPath, ElevatedHelperPid
    global ElevatedHelperAvailable, ElevatedHelperLastError
    global ElevatedHelperExpectedVersion, IniPath, ScriptPid

    ElevatedHelperAvailable := false
    ElevatedHelperPid := 0
    if !RtssElevatedFrameCapWrites {
        ElevatedHelperLastError := "Disabled in Settings."
        return false
    }
    ; An elevated companion writes RTSS profiles with its own token already, so
    ; a second elevated process would buy nothing and cost a UAC prompt.
    if A_IsAdmin {
        ElevatedHelperLastError :=
            "The companion is already running elevated; the helper is unnecessary."
        LogLine("Elevated RTSS helper: " ElevatedHelperLastError)
        return false
    }
    ElevatedHelperPath := XfeElevatedHelperPath()
    installedVersion := ""
    try installedVersion := FileGetVersion(ElevatedHelperPath)
    if (installedVersion != ElevatedHelperExpectedVersion) {
        ; XFE has no embedded payload and no way to write into an
        ; administrator-only directory, so there is nothing to retry here. Name
        ; the actual remedy rather than reporting a bare file error.
        ElevatedHelperLastError := installedVersion = ""
            ? "The elevated helper is not installed, or cannot be read by this "
                . "account. Run SteamShell.exe Setup as administrator to install it."
            : "The installed helper is version " installedVersion "; this build "
                . "expects " ElevatedHelperExpectedVersion ". Run SteamShell.exe "
                . "Setup as administrator to replace it."
        LogLine("Elevated RTSS helper: " ElevatedHelperLastError, "Warning")
        return false
    }
    ; Fail closed. A helper whose directory or binary the interactive user can
    ; write is a local privilege escalation dressed up as a feature, and this is
    ; the only gate standing between a writable path and a High-integrity token.
    if !ElevatedHelperLocationIsProtected(ElevatedHelperPath, &protectionError) {
        ElevatedHelperLastError :=
            "The installed helper is not administrator-protected, so it was not elevated. "
            . protectionError
            . " Run SteamShell.exe Setup as administrator again to re-secure it."
        LogLine("Elevated RTSS helper: " ElevatedHelperLastError, "Warning")
        return false
    }
    ; Beside the helper rather than beside XFE's own log: an elevated process
    ; appending to a path the interactive user controls invites a reparse-point
    ; redirection onto a file it should never have touched.
    SplitPath(ElevatedHelperPath, , &helperDirectory)
    helperLog := helperDirectory "\SteamShell-Helper.log"
    ; The protected on-demand task first, because a UAC prompt runs on the secure
    ; desktop where a controller cannot answer it. Registered lazily here rather
    ; than at install, so a machine that never enables this never carries a
    ; HighestAvailable task.
    if EnsureXfeElevatedHelperTask(ElevatedHelperPath, &taskSetupError) {
        existingPids := CaptureExecutablePidSet(ElevatedHelperPath)
        if (RunSchTasks('/run /tn "' XfeElevatedHelperTaskName() '"') = 0) {
            taskPid := WaitForNewExecutablePid(ElevatedHelperPath, existingPids, 5000)
            if (taskPid && WaitForVerifiedElevatedHelper(
                taskPid, &taskVerifyError, 2500)) {
                ElevatedHelperPid := taskPid
                ElevatedHelperAvailable := true
                ElevatedHelperLastError := "Running as PID " taskPid
                    . " through the protected scheduled task."
                LogLine("Elevated RTSS helper: " ElevatedHelperLastError)
                return true
            }
            ; A task process that did not verify is usually one Windows started
            ; with a normal token. Close it rather than leaving it behind while
            ; the direct route starts a second helper.
            if (taskPid && ProcessExist(taskPid))
                try ProcessClose(taskPid)
        }
        LogLine("Elevated RTSS helper: the scheduled task did not produce a "
            . "verified helper; requesting UAC directly.", "Warning")
    } else if (taskSetupError != "") {
        LogLine("Elevated RTSS helper: no scheduled task (" taskSetupError
            . "); elevation will prompt.", "Warning")
    }
    commandLine := "*RunAs " QuoteWindowsCommandLineArg(ElevatedHelperPath)
        . " " SharedElevatedHelperArguments("xfe", ScriptPid, "", IniPath, helperLog)
    try {
        Run(commandLine, A_ScriptDir, , &ElevatedHelperPid)
        ElevatedHelperAvailable := WaitForVerifiedElevatedHelper(
            ElevatedHelperPid, &verificationError, 2500)
        ElevatedHelperLastError := ElevatedHelperAvailable
            ? "Running as PID " ElevatedHelperPid "."
            : "The elevated helper could not be verified: " verificationError
        LogLine("Elevated RTSS helper: " ElevatedHelperLastError,
            ElevatedHelperAvailable ? "Info" : "Warning")
        return ElevatedHelperAvailable
    } catch as err {
        ElevatedHelperLastError := "Elevation was cancelled or failed: " err.Message
        LogLine("Elevated RTSS helper unavailable: " ElevatedHelperLastError,
            "Warning")
        return false
    }
}

; Turning the setting off must take effect now, not at the next sign-in.
;
; This is the same rule standalone learned the hard way: an elevated process the
; user has just asked to stop, which keeps running for the rest of the session
; while Health Check reports it as fine, is not a control. Called from
; ReloadSettings, so Save & Apply both starts and stops it.
; The helper is a separate process the user can end from Task Manager, and
; nothing in XFE watches it. Without this, a dead helper would cost every
; frame-cap press the full three-second request timeout before failing, and the
; row would look broken rather than unelevated.
;
; Checked at the point of use rather than on a timer, because this is the only
; place the answer matters and a timer would be one more thing running for a
; feature that is off by default.
EnsureElevatedRtssHelperAlive() {
    global ElevatedHelperAvailable, ElevatedHelperPid, ElevatedHelperLastError
    if !ElevatedHelperAvailable
        return false
    if (ElevatedHelperPid && ProcessExist(ElevatedHelperPid))
        return true
    ElevatedHelperAvailable := false
    ElevatedHelperLastError := "The helper process exited."
    LogLine("Elevated RTSS helper: " ElevatedHelperLastError, "Warning")
    return false
}

SyncElevatedRtssHelperWithSettings() {
    global RtssElevatedFrameCapWrites, ElevatedHelperAvailable, ElevatedHelperPid
    global ElevatedHelperLastError
    if !RtssElevatedFrameCapWrites {
        if (ElevatedHelperPid || ElevatedHelperAvailable)
            return StopElevatedHelper("disabled in Settings")
        ElevatedHelperLastError := "Disabled in Settings."
        return true
    }
    if A_IsAdmin
        return false
    if (ElevatedHelperAvailable && ElevatedHelperPid
        && ProcessExist(ElevatedHelperPid))
        return true
    return StartElevatedRtssHelper()
}

; ------------------------------------------------------------------------------
; Quick Menu frame cap
; ------------------------------------------------------------------------------

; The notification half of the shared seam. See the standalone tree: shared code
; calls SharedNotify, and each program routes it to its own surface. The
; companion has a status line rather than a toast.

; Per-tree seam required by SteamShell-Shared.ahk.
;
; Takes an array of Map("section", "key", "value"). XFE is an ordinary companion
; started from an existing desktop, so direct writes are appropriate. Standalone
; implements the same name transactionally, because it is the Windows shell.
; Shared code calls this and does not have to know which.
; Per-tree seam required by SteamShell-Shared.ahk: persist one Quick Menu
; setting AND make it live. This tree writes directly and then re-reads, which
; is what Reload and Save & Apply already do; the shell stages a copy first
; because a half-written INI is a machine that boots into nothing.
ProductApplyQuickMenuSetting(section, key, value) {
    if !SharedPersistSettings([Map("section", section, "key", key, "value", value)]) {
        ShowNotification("The setting could not be saved", "Warning")
        return false
    }
    LoadSettings()
    ApplyRuntimeTimers()
    ; If the full Settings window is open behind the Quick Menu, update its
    ; control too, or a later Save there writes the stale value back over this.
    ;
    ; Normalised first: these arrive as the words written to the INI, and in
    ; AutoHotkey v2 the STRING "false" is a non-empty string and therefore TRUE.
    ; Handing it straight to a checkbox would tick every box it just cleared.
    SetFieldValue(section "." key,
        value = "true" ? true : (value = "false" ? false : value))
    return true
}

; Per-tree seam required by SteamShell-Shared.ahk: does the learning wizard want
; this report instead of the decoder?
;
; While the wizard is open it consumes reports, because decoding as well would
; fire mappings from the very buttons being pressed to teach the layout.
;
; Returns true when the learner took the report.
; Per-tree seam required by SteamShell-Shared.ahk: a modal dialog is up, so
; controller input must not also drive the menu behind it. Each tree already had
; a flag for this and they are not the same name.
ProductSetDialogActive(active) {
    global SettingsDialogActive
    SettingsDialogActive := active
}

; The seam shared code persists through, bound to this program's INI and PID.
;
; This wrote each key straight into the live file in a loop and returned false at
; the first failure -- which does not undo the keys already written. A three-key
; save failing on the third left the file holding two of them while telling the
; caller nothing was saved, and ProductApplyQuickMenuSetting responds to that
; false by reloading settings from a file that now agrees with neither the caller
; nor the user. It also meant a crash or a power loss mid-save could truncate the
; settings file outright, because IniWrite rewrites it in place.
;
; Standalone had already solved this properly, so the loop is gone rather than
; patched: CommitIniChangesAt stages a copy, writes into the copy and moves it
; over the original, so the file is either fully updated or untouched.
SharedPersistSettings(changes) {
    global IniPath, ScriptPid
    return CommitIniChangesAt(IniPath, ScriptPid, changes)
}

; Staging means the occasional abandoned staging file, so the companion sweeps
; them for the same reason standalone does -- adopting the commit without the
; sweep would just trade one kind of litter for another, beside the INI the user
; is expected to be able to read.
SweepAbandonedSettingsUpdates() {
    global IniPath, ScriptPid
    SweepAbandonedIniUpdates(IniPath, ScriptPid)
}

; Per-tree seam required by SteamShell-Shared.ahk. See the header above
; VerifyElevatedHelperProcess there for why this exists.
;
; "the companion" rather than "SteamShell XFE" in messages on purpose: the text
; it lands in reads "...does not match the companion", which is the name the
; user sees this program called throughout its own UI and logs.
; A click on a Quick Menu row ACTIVATES it here; standalone selects it. See the
; note beside standalone's QuickMenuMouseChoose.
QuickMenuMouseChoose(index) {
    QuickMenuMouseActivate(index)
}

ProductIdentity() {
    static identity := Map(
        "name", "the companion",
        "exe", "steamshell-xfe.exe",
        "dirToken", "XFE_DIR",
        "helperLabel", "Elevated RTSS helper",
        ; Shown at the top of the Quick Menu. Separate from "name", which is
        ; prose used inside sentences.
        "title", "SteamShell XFE",
        ; Tray icon filename under assets\. Read by the shared
        ; ApplyTrayIconImage so the icon lifecycle has no per-tree copy.
        "icon", "SteamShell-XFE.ico")
    return identity
}

; Seam for the shared ToggleQuickMenu. Nothing here refuses to open the menu:
; there is no desktop restore to be in the middle of, and the companion has no
; master enable of its own.
ProductQuickMenuBlockedReason() {
    return ""
}

ShowQuickMenu(*) {
    global EnableQuickMenu, QuickMenuVisible, QuickMenuPage, QuickMenuSelected
    global QuickMenuMonitorIndex, QuickMenuGui, QuickMenuPreviousExe
    global QuickMenuPreviousHwnd, EnableAutoHideCursor, MouseHidden
    if !EnableQuickMenu
        return
    LogLine("Quick Menu requested.")
    foreground := 0
    try foreground := WinExist("A")
    ; Record what was in front BEFORE this window appears. Every Steam action
    ; depends on knowing whether Steam or a game owned the screen, and once the
    ; menu is up the answer would always be "SteamShell-XFE".
    QuickMenuPreviousExe := CurrentForegroundExe()
    ; Remember what had focus so it can be handed back on close.
    QuickMenuPreviousHwnd := (foreground && !IsOurWindow(foreground)) ? foreground : 0
    QuickMenuMonitorIndex := GetMonitorIndexForWindow(foreground)
    QuickMenuPage := "MAIN"
    QuickMenuSelected := 1
    QuickMenuVisible := true
    QuickMenuBuildGui()
    ; Showing an always-on-top window makes it visible but does not necessarily
    ; give it the foreground. Without the foreground, the application behind
    ; keeps receiving controller input and keeps reacting to it.
    gotFocus := false
    try gotFocus := ForceForegroundWindow(QuickMenuGui.Hwnd)
    ; Hide the cursor immediately rather than waiting out the idle delay: the
    ; menu is opened from the controller, so a pointer sitting on top of it is
    ; just clutter.
    if (EnableAutoHideCursor && !MouseHidden) {
        SystemCursor("Hide")
        MouseHidden := true
    }
    try LogLine(
        "Quick Menu shown: hwnd=" QuickMenuGui.Hwnd
        . ", visible=" DllCall("IsWindowVisible", "Ptr", QuickMenuGui.Hwnd, "Int")
        . ", foreground=" (gotFocus ? "yes" : "NO")
        . ", previous=" (QuickMenuPreviousExe != "" ? QuickMenuPreviousExe : "unknown") ".")
}

QuickMenuHideThenSteamMenu(steamInFront) {
    shortcut := SendSteamMenu(steamInFront)
    HideQuickMenu()
    if steamInFront
        SetTimer(() => SendChordSafe(shortcut), -150)
    else
        SetTimer(SendSteamOverlayChord, -150)
}

; Closes the Quick Menu when one of OUR OWN windows is opening next.
;
; The normal close hands the foreground back to whatever was in front, and Xbox
; FSE then re-asserts it. The window opened a moment later therefore loses the
; race and never comes forward -- it has to be found with the task switcher.
; Clearing the remembered window means there is nothing to hand back to.
HideQuickMenuForOwnWindow() {
    global QuickMenuPreviousHwnd
    QuickMenuPreviousHwnd := 0
    HideQuickMenu()
}

HideQuickMenu(*) {
    global QuickMenuVisible, QuickMenuGui, EnableAutoHideCursor, MouseHidden
    global QuickMenuPreviousHwnd, ControllerNeedsFreshBaseline
    wasVisible := QuickMenuVisible
    ; Hiding alone can leave the child title/rows/footer surfaces cached in DWM
    ; when a fullscreen game or Xbox FSE replaces its presentation surface.
    ; Hide the parent first, then retire the whole menu session.
    if IsSet(QuickMenuGui) {
        try DllCall("User32\ShowWindow", "Ptr", QuickMenuGui.Hwnd, "Int", 0)
        try QuickMenuGui.Hide()
    }
    QuickMenuVisible := false
    QuickMenuDestroyWindow()
    ; Everything below is a consequence of a menu having CLOSED, and none of it
    ; is idempotent, so it is gated on the menu actually having been open --
    ; which is what standalone's copy has always done and this one did not.
    ; Called defensively on a menu that was already hidden, this pulled the
    ; foreground to a window remembered from some earlier session, hid the
    ; cursor, and spent the next controller poll on a baseline nothing needed.
    if !wasVisible
        return
    ControllerNeedsFreshBaseline := true
    ; Hand the foreground back to whatever had it, so closing the menu does not
    ; leave the session with nothing focused.
    if (QuickMenuPreviousHwnd && DllCall("IsWindow", "Ptr", QuickMenuPreviousHwnd)) {
        try ForceForegroundWindow(QuickMenuPreviousHwnd)
        QuickMenuPreviousHwnd := 0
    }
    if EnableAutoHideCursor {
        SystemCursor("Hide")
        MouseHidden := true
    }
}

; ---------------------------------------------------------------------------
; Quick Menu accent resolution.
;
; This block is character-for-character identical in standalone SteamShell apart
; from indentation and the two settings reads, which use each tree's own INI
; helper. Keeping it that way is deliberate: the accent is one design applied to
; both, so a fix to the blend or the fallback should be a copy, not a
; re-derivation.
; ---------------------------------------------------------------------------

; The one line of the painter that differs between the two trees, isolated so
; the rest can stay identical: standalone resolves a row's value live, while XFE
; rebuilds its whole row list per repaint and already carries it.
; The value column, resolved when a row is painted rather than when it is built.
;
; This text is deliberately NOT shared with standalone. Once the row ids were
; unified the two resolvers were compared id by id, and 19 of the 35 ids both
; products build answer differently -- standalone says "Big Picture" when Steam
; is not running where this reports the shortcut, its tasks row summarises the
; pinned foreground where this summarises switchable windows, and several rows
; differ in wording alone. This is the companion's vocabulary, the same way
; ControllerBindingPretty is; DIVERGENT_FUNCTIONS.txt records the measurement.
;
; Lazy, because the rows are no longer rebuilt on every render. Values that were
; captured from locals in the row builder -- the HDR state, the RTSS global
; state, whether Steam was in front -- are read again here, which is what makes
; a repaint able to show a changed value without rebuilding the page.
QuickMenuValue(id) {
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    global DisplaySelectedScalePercent, RtssPendingFrameCap
    global EnablePersistentMouseMode, QuickMenuPreviousExe, QuickMenuTaskWindows
    global SteamMenuShortcut, SteamOverlayShortcut, SteamQuickAccessShortcut

    if (SubStr(id, 1, 7) = "layout:") {
        button := SubStr(id, 8)
        value := ControllerBindingPretty(button ".Short")
        longValue := ControllerBindingPretty(button ".Long")
        if (longValue != "None")
            value .= "  /  Hold: " longValue
        return value
    }
    if (SubStr(id, 1, 11) = "taskWindow:") {
        hwnd := ToInt(SubStr(id, 12), 0)
        for _, item in QuickMenuTaskWindows {
            if (item["hwnd"] = hwnd)
                return item["exe"]
        }
        return ""
    }
    if (SubStr(id, 1, 10) = "gamescore:")
        return QuickMenuGameScoreValue(id)
    if (id = "currentApp")
        return QuickMenuCurrentAppValue()

    switch id {
        case "audioMenu": return GetAudioSummary()
        case "display": return SharedDisplayModeText()
        case "rtssMenu": return GetRtssMenuStatus()
        case "tasks": return GetSwitchableWindowsSummary()
        case "steamMenu":
            steamFront := IsSteamProcess(QuickMenuPreviousExe)
            return SendToPretty(steamFront ? SteamMenuShortcut : SteamOverlayShortcut)
        case "steamQuickAccess": return SendToPretty(SteamQuickAccessShortcut)
        case "gameBar": return "Win + G"
        case "openKeyboard": return "Open Touch Keyboard"
        case "qPersistentMouse": return OnOffText(EnablePersistentMouseMode)
        case "settings": return "Features & Configuration"
        case "system": return "Power & Diagnostics"
        case "windowsSettings": return "Open Windows Settings"
        case "settingsEditor": return "Open Settings Window"
        case "setControllerMappings": return "Open Mapping Editor"
        case "gameDetection": return QuickMenuGameDetectionValue()
        case "audioOutput": return GetAudioOutputName()
        case "volume": return GetVolumeText()
        case "mute": return GetMuteText()
        case "hdr":
            hdr := GetPrimaryHdrState()
            if (!IsObject(hdr) || !hdr["supported"])
                return "Unavailable"
            return hdr["forceDisabled"]
                ? "Disabled By Windows"
                : "‹ " (hdr["enabled"] ? "ON" : "OFF") " ›"
        case "hdrUnavailable":
            hdr := GetPrimaryHdrState()
            return IsObject(hdr) ? "Not Supported" : "Unavailable"
        case "displayResolution":
            return "‹ " DisplaySelectedWidth " × " DisplaySelectedHeight " ›"
        case "displayRefresh":
            return "‹ " DisplaySelectedFrequency " Hz ›"
        case "displayScale":
            return "‹ " DisplaySelectedScalePercent "% ›"
        case "displayScaleUnavailable": return "Unavailable"
        case "displayApply": return GetDisplayApplyValue()
        case "rtssDisabled": return "Disabled"
        case "rtssStart": return "Launch Configured Executable"
        case "rtssMissing": return "Executable Not Found"
        case "rtssOverlayState":
            rtssState := GetRtssGlobalState()
            return IsObject(rtssState)
                ? "‹ " (rtssState["overlay"] ? "ON" : "OFF") " ›"
                : "Unavailable"
        case "rtssFrameLimit": return RtssFrameCapValueText()
        case "rtssFrameLimitCustom":
            capState := GetRtssFrameCapState()
            if !IsObject(capState)
                return "Unavailable"
            return "‹ " (RtssPendingFrameCap > 0
                ? RtssPendingFrameCap : capState["fps"]) " FPS ›"
        case "rtssSaveProfile": return RtssSaveProfileValueText()
        case "limiterOn", "limiterToggle": return GetFrameCapLabel()
        case "rtssSettings": return GetRtssAvailability()
    }
    return ""
}

QuickMenuBuildGui() {
    global QuickMenuGui, QuickMenuTitleCtrl, QuickMenuStatusCtrl
    global QuickMenuRowsCtrl
    global QuickMenuVisible, QuickMenuMonitorIndex, QuickMenuRows
    global QM_BG, QM_LABEL, QM_VALUE, QM_LABEL_SELECTED
    if !QuickMenuVisible
        return
    width := QuickMenuWidth()
    if !IsSet(QuickMenuGui) {
        ; No +Border: the drawn frame did not always complete around the window,
        ; and rounded corners are applied instead once the real size is known.
        menu := Gui("+AlwaysOnTop -Caption +ToolWindow", "SteamShell XFE Quick Menu")
        menu.BackColor := QM_BG
        menu.MarginX := QuickMenuRowInset()
        menu.MarginY := 16
        inset := QuickMenuRowInset()
        rowWidth := width - (inset * 2)
        labelWidth := Round(rowWidth * 0.52)
        menu.SetFont("s17 c" QM_LABEL_SELECTED " Bold", "Segoe UI")
        QuickMenuTitleCtrl := menu.AddText("x" (inset + 12) " y20 w" (rowWidth - 12) " h30", "")
        ; One painted surface replaces the 28 Static controls the rows used to
        ; be. 0x0E is SS_BITMAP, 0x40 is SS_REALSIZECONTROL so the static keeps
        ; the size we gave it instead of resizing itself to the bitmap, and
        ; 0x100 is SS_NOTIFY so it still reports clicks.
        QuickMenuRowsCtrl := menu.AddText(
            "x0 y" (QuickMenuRowTop() - QuickMenuGlowPadding())
            . " w" width " h" ((14 * QuickMenuRowHeight()) + (2 * QuickMenuGlowPadding())), "")
        QuickMenuRowsCtrl.Opt("+0x14E")
        QuickMenuRowsCtrl.OnEvent("Click", QuickMenuRowsClick)
        ; Bottom line carries the button hint, and transient status messages when
        ; there are any. Keeping it off the top leaves the title uncluttered.
        menu.SetFont("s9 c" QM_VALUE " Norm", "Segoe UI")
        QuickMenuStatusCtrl := menu.AddText(
            "x" (inset + 12) " y600 w" (rowWidth - 12) " h36 +Wrap", "")
        ; Escape mirrors B: back one page, and close from the main page.
        menu.OnEvent("Escape", (*) => QuickMenuGoBack())
        QuickMenuGui := menu
    }
    QuickMenuSetRedraw(false)
    try {
        QuickMenuRows := QuickMenuGetRows()
        QuickMenuRender()
        QuickMenuResizeToRows()
    } finally {
        QuickMenuSetRedraw(true)
    }
}

; Sizes the window to the rows currently on the page and re-centres it.
;
; Split out of QuickMenuBuildGui because QuickMenuRefresh re-derives the row
; list as well, and until this was reachable from there a refresh that changed
; the row count left the window at its old height with the new rows painted
; below its bottom edge. The RTSS page is where that showed: its rows are
; composed from live RTSS state, so RTSS starting while the page was open took
; it from two rows to four and cut the bottom two off. Intermittent by nature,
; because it needed RTSS to change state during the seconds the page was up.
QuickMenuResizeToRows() {
    global QuickMenuGui, QuickMenuMonitorIndex, QuickMenuRows, QuickMenuSizedRowCount
    if (!IsSet(QuickMenuGui) || QuickMenuRows.Length = 0)
        return
    QuickMenuSizedRowCount := QuickMenuRows.Length
    ; Derive the height from the same figures that lay the content out, so the
    ; window finishes just below the status line. The previous constant left a
    ; fixed 53px of empty space under everything, which reads as a large unused
    ; margin now that the status line is usually blank.
    height := Min(QuickMenuStatusY(QuickMenuRows.Length) + QuickMenuStatusHeight()
        + QuickMenuBottomMargin(), 820)
    deferred := CenterGuiOnMonitorActual(QuickMenuGui, QuickMenuMonitorIndex,
        QuickMenuWidth(), height, false, true)
    ; Reveal first, then measure and shape; redraw remains suspended until the
    ; page, final size and corner state are all ready.
    if deferred
        RevealWindow(QuickMenuGui)
    QuickMenuEnsureContentFits()
    ApplyRoundedCorners(QuickMenuGui, 30)
}

; Grows the Quick Menu if its content does not fit, and re-centres it.
;
; The height handed to Gui.Show is computed in logical units and scaled by
; AutoHotkey; the controls are scaled the same way, so in principle they agree.
; In practice, on a 4K television at high scaling, the first show came out too
; short and the bottom rows were cut off -- the arithmetic and the layout
; disagreed about the final size.
;
; So this stops predicting. It asks where the last control ACTUALLY ended up, in
; the same coordinate space the window is measured in, and resizes to fit if the
; window is short. That is DPI-agnostic by construction: whatever scaling was
; applied to the controls is already baked into the measurement.
QuickMenuEnsureContentFits() {
    global QuickMenuGui, QuickMenuStatusCtrl, QuickMenuMonitorIndex
    if (!IsSet(QuickMenuGui) || !IsSet(QuickMenuStatusCtrl))
        return
    ; The monitor the menu was opened on, stored rather than re-derived. Xbox FSE
    ; owns presentation here, so there is no foreground window to follow and no
    ; re-centre once the content fits -- the false below is that decision.
    monitorIndex := ClampInt(QuickMenuMonitorIndex, 1, MonitorGetCount())
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    QuickMenuFitContent(
        QuickMenuGui, QuickMenuStatusCtrl, left, top, right, bottom, false)
}

QuickMenuRender() {
    global QuickMenuRows, QuickMenuSelected, QuickMenuTitleCtrl, QuickMenuStatusCtrl
    global QuickMenuRowsCtrl
    global LastStatusText, LastStatusLevel, QuickMenuVisible
    global QM_BG, QM_ROW_SELECTED, QM_ACCENT, QM_LABEL, QM_LABEL_SELECTED, QM_VALUE
    if !QuickMenuVisible
        return
    ; Rows are composed in QuickMenuBuildGui, not here. This used to rebuild the
    ; list on EVERY repaint, which re-ran QuickMenuGetRows -- and that function
    ; assigns QuickMenuTaskWindows from SharedTaskSwitcherWindows(), so every nudge of
    ; the D-pad re-enumerated every window on the desktop. Worse, the rebuilt
    ; list was only re-CLAMPED, not re-matched: a window closing between repaints
    ; shifted every row below it up and left the highlight on a different window
    ; than the one the user was looking at. Standalone has always split it this
    ; way; the sites that genuinely change the row SHAPE now say so.
    if (QuickMenuRows.Length = 0)
        return
    QuickMenuSelected := ClampInt(QuickMenuSelected, 1, QuickMenuRows.Length)
    QuickMenuTitleCtrl.Text := GuiLiteralText(QuickMenuTitleText())
    ; The painted band is sized to the rows actually on this page, so a short
    ; page leaves no dead surface for a glow to spill onto.
    QuickMenuRowsCtrl.Move(0, QuickMenuRowTop() - QuickMenuGlowPadding(), QuickMenuWidth(),
        (Max(1, QuickMenuRows.Length) * QuickMenuRowHeight())
            + (2 * QuickMenuGlowPadding()))
    ; Every row is one bitmap, so selection, value text and color all change in
    ; a single repaint rather than by touching 28 controls individually.
    QuickMenuPaintRows()
    ; The bottom line shows the button hint normally and a status message when
    ; there is one, so the hint no longer occupies a line at the top.
    inset := QuickMenuRowInset()
    QuickMenuStatusCtrl.Move(inset + 12, QuickMenuStatusY(QuickMenuRows.Length),
        QuickMenuWidth() - (inset * 2) - 12, QuickMenuStatusHeight())
    status := QuickMenuStatusText()
    QuickMenuStatusCtrl.Text := GuiLiteralText(status != "" ? status : QuickMenuHint())
    QuickMenuStatusCtrl.SetFont(
        "s9 c" (status != "" && LastStatusLevel = "Warning" ? "FFCA70" : QM_VALUE) " Norm",
        "Segoe UI")
    try QuickMenuStatusCtrl.Redraw()
}

; Button hint, tailored to the page so it lists only what actually applies.
QuickMenuHint() {
    global QuickMenuPage
    if (QuickMenuPage = "TASKS")
        return "D-Pad Move  •  A Switch To  •  X Close  •  Left/Right Page  •  B Back"
    if (QuickMenuPage = "DISPLAY")
        return "D-Pad Move  •  Left/Right Change  •  A Select  •  B Back"
    if (QuickMenuPage = "RTSS")
        return "D-Pad Move  •  Left/Right Off/On  •  A Select  •  B Back"
    if (QuickMenuPage = "SETTINGS")
        return "D-Pad Move  •  A Or Left/Right Toggle  •  B Back"
    if (QuickMenuPage = "MAIN")
        return "D-Pad Move  •  A Select  •  Hold Y for Controller Mappings  •  B Back"
    return "D-Pad Move  •  A Select  •  B Back"
}

QuickMenuRefresh() {
    global QuickMenuVisible, QuickMenuRows, QuickMenuSizedRowCount
    if !QuickMenuVisible
        return
    QuickMenuSetRedraw(false)
    try {
        QuickMenuRender()
        ; Only when the count actually moved. A repaint is the common case and
        ; must not re-centre the window under the user for a value change.
        if (QuickMenuRows.Length != QuickMenuSizedRowCount)
            QuickMenuResizeToRows()
    } finally {
        QuickMenuSetRedraw(true)
    }
}

; The status line is transient feedback, not a permanent field, so it stays
; blank unless there is something to say.
;
; It must NOT expire while an action is waiting on a second press: the sleep,
; restart and shutdown confirmations and the timed display-mode revert put their
; only instructions here. Clearing those early would leave a destructive action
; looking like it did nothing, or a bad resolution with no way back explained.
QuickMenuStatusText() {
    global LastStatusText, LastStatusTick, StatusVisibleMs
    global QuickMenuConfirmUntilTick, DisplayPendingUntilTick
    if !LastStatusTick
        return ""
    if (QuickMenuConfirmUntilTick && A_TickCount < QuickMenuConfirmUntilTick)
        return LastStatusText
    if (DisplayPendingUntilTick && A_TickCount < DisplayPendingUntilTick)
        return LastStatusText
    return A_TickCount - LastStatusTick <= StatusVisibleMs ? LastStatusText : ""
}

QuickMenuMouseActivate(index, *) {
    global QuickMenuSelected, QuickMenuRows
    if (index < 1 || index > QuickMenuRows.Length)
        return
    QuickMenuSelected := index
    QuickMenuActivateSelected()
}

QuickMenuActivateSelected() {
    global QuickMenuRows, QuickMenuSelected, QuickMenuPage, QuickMenuPreviousExe
    if (QuickMenuRows.Length = 0)
        return
    action := QuickMenuRows[QuickMenuSelected]["action"]
    if (SubStr(action, 1, 5) = "page:") {
        QuickMenuPage := SubStr(action, 6)
        QuickMenuSelected := 1
        QuickMenuBuildGui()
        return
    }
    if (SubStr(action, 1, 11) = "taskWindow:") {
        ActivateSwitchableWindow(Round(SubStr(action, 12) + 0))
        return
    }
    ; The destination rows on CURRENTAPP. The write, the duplicate check and the
    ; refusal all live in SteamShell-Shared.ahk, so this tree names the product
    ; and nothing else.
    ;
    ; QuickMenuBuildGui, because "(already added)" is part of the row's LABEL
    ; and QuickMenuRender explicitly does not recompose rows -- a repaint would
    ; redraw the label the page was built with, so the add would look like it
    ; did nothing until the page was left and re-entered.
    if (SubStr(action, 1, 11) = "currentapp:") {
        QuickMenuAddCurrentAppTo(action, "xfe")
        QuickMenuBuildGui()
        return
    }

    ; An adjustable row STEPS FORWARD on A, exactly as Right does; only a
    ; two-state row flips. Ordered the same way as QuickMenuAdjustSelected
    ; below, so the two entry points cannot disagree about what a row is.
    ;
    ; Without the first step, the four adjustable rows -- Quick Menu Accent,
    ; Controller Mouse Speed, Cursor Hide Delay and Preset Frame Cap -- reached
    ; QuickMenuToggleSetting, which answers only to qPersistentMouse, the cycle
    ; settings and QuickMenuToggleTable. None of those four is any of them, so
    ; the call returned early and the row rendered, selected and did nothing.
    ; Standalone has always stepped them, through IsQuickMenuAdjustSetting over
    ; the same four ids and the same shared QuickMenuAdjustSharedSetting.
    ;
    ; QUICKMENU_ROWS.txt could not see this: these rows are built by
    ; QuickMenuSettingsRows as "toggle:<id>", which is a FAMILY id, and the
    ; inventory deliberately does not list families one by one.
    if (SubStr(action, 1, 7) = "toggle:"
        && QuickMenuAdjustSharedSetting(SubStr(action, 8), 1)) {
        QuickMenuRefresh()
        return
    }
    if (SubStr(action, 1, 7) = "toggle:") {
        QuickMenuToggleSetting(SubStr(action, 8),
            QuickMenuRows[QuickMenuSelected]["label"])
        QuickMenuRefresh()
        return
    }
    ; A steps in the row's own direction; Left and Right step in theirs. Both
    ; rebuild the menu, so neither falls through to the refresh at the end.
    switch action {
        case "taskPrev":
            ChangeQuickMenuTaskPage(-1)
            return
        case "taskNext":
            ChangeQuickMenuTaskPage(1)
            return
        ; A `case` and not an `if`, deliberately. Assert-QuickMenuRows reads the
        ; CASE LABELS of this function to decide whether a row's action reaches a
        ; handler, so a row handled by an if-block reads to it as a row that does
        ; nothing -- which is the exact failure that check exists to catch.
        case "currentApp":
            ; Nothing to offer, and the row already says why. Opening a page of
            ; destinations that would all refuse is worse than not opening one.
            if !QuickMenuCurrentAppSelectable() {
                ShowNotification(QuickMenuCurrentAppBlockedReason(), "Warning")
                return
            }
            QuickMenuPage := "CURRENTAPP"
            QuickMenuSelected := 1
            QuickMenuBuildGui()
            return
    }
    ; Actions both products implement identically.
    ;
    ; `action`, not `id`: this tree dispatches on the action a row carries, and
    ; for every one of the shared cases the action string and the row id are the
    ; same word. Passing `id` here named a local that is never assigned in this
    ; function -- the same shape of mistake DIVERGENT_FUNCTIONS.txt records for
    ; RecordShortcutChord, where a name the checks could not see resolved to an
    ; empty local and wired a button to nothing.
    if QuickMenuActivateShared(action) {
        QuickMenuRefresh()
        return
    }
    switch action {
        case "none":
            return
        case "back":
            QuickMenuGoBack()
            return
        case "mute":
            try {
                SoundSetMute(-1)
                ShowNotification(SoundGetMute() ? "Audio muted" : "Audio unmuted")
            } catch {
                ShowNotification("Windows mute control is unavailable", "Warning")
            }
        case "rtssStart":
            StartRtssFromQuickMenu()
        case "rtssFrameLimit":
            ; Wraps: A is the only control on this row for a user who never
            ; discovers Left/Right, so it has to be able to reach every entry.
            ;
            ; Entering or leaving Custom adds or removes a row, and the row list
            ; is composed in QuickMenuGetRows, which QuickMenuRefresh no longer
            ; runs. Rebuild only on that transition, never on every press.
            if CycleRtssFrameCap(1, true) {
                QuickMenuBuildGui()
                return
            }
        case "rtssSaveProfile":
            ; Writes a file RTSS then applies to that game on every future
            ; launch, with nothing on screen afterwards to say it happened.
            if (RtssProfileTargetExe() = "")
                ShowNotification("No foreground game to save a profile for", "Warning")
            else if QuickMenuConfirm("rtssSaveProfile",
                "saving " RtssProfileTargetExe() " frame limit")
                SaveRtssFrameLimitToProfile()
        case "gameBar":
            QuickMenuHideThenSend("#g")
            return
        case "openKeyboard":
            HideQuickMenu()
            SetTimer(OpenTouchKeyboard, -100)
            return
        case "steamMenu":
            ; Decided from the foreground captured when the menu opened, not the
            ; current one -- the Quick Menu itself is in front by now.
            QuickMenuHideThenSteamMenu(IsSteamProcess(QuickMenuPreviousExe))
            return
        case "steamQuickAccess":
            QuickMenuHideThenSend(SendSteamQuickAccess(IsSteamProcess(QuickMenuPreviousExe)))
            return
        case "settingsEditor":
            HideQuickMenuForOwnWindow()
            ShowSettings()
            return
        case "windowsSettings":
            HideQuickMenu()
            SetTimer(OpenWindowsSettings, -100)
            return
        case "setControllerMappings":
            HideQuickMenuForOwnWindow()
            SetTimer(ShowMappingEditor, -100)
            return
        case "rtssSettings":
            HideQuickMenuForOwnWindow()
            ShowSettingsCategory("RTSS & Performance")
            return
        case "sleep":
            if !QuickMenuConfirm("sleep", "sleep")
                return
            HideQuickMenu()
            try DllCall("PowrProf\SetSuspendState", "Int", 0, "Int", 0, "Int", 0)
            return
        case "restart":
            if !QuickMenuConfirm("restart", "restart")
                return
            HideQuickMenu()
            try Shutdown(2)
            return
        case "shutdown":
            if !QuickMenuConfirm("shutdown", "shutdown")
                return
            HideQuickMenu()
            try Shutdown(1)
            return
        case "exitApp":
            if !QuickMenuConfirm("exitApp", "exit")
                return
            HideQuickMenu()
            ExitApp()
    }
    QuickMenuRefresh()
}

QuickMenuAdjustSelected(direction) {
    global QuickMenuRows, QuickMenuSelected
    if (QuickMenuRows.Length = 0)
        return
    action := QuickMenuRows[QuickMenuSelected]["action"]
    ; Numbers and list positions step; two-state rows have nothing to step
    ; through, so for those Left and Right both simply flip it -- the same thing
    ; A does, and the direction is deliberately ignored.
    if (SubStr(action, 1, 7) = "toggle:"
        && QuickMenuAdjustSharedSetting(SubStr(action, 8), direction)) {
        QuickMenuRefresh()
        return
    }
    if (SubStr(action, 1, 7) = "toggle:") {
        QuickMenuToggleSetting(SubStr(action, 8),
            QuickMenuRows[QuickMenuSelected]["label"])
        QuickMenuRefresh()
        return
    }
    switch action {
        ; Left and Right both page, in the direction pressed, from either row.
        case "taskPrev", "taskNext":
            ChangeQuickMenuTaskPage(direction)
            return
        case "audioOutput":
            CycleDefaultAudioOutput(direction)
        case "volume":
            try {
                nextVolume := ClampInt(Round(SoundGetVolume()) + direction * 5, 0, 100)
                SoundSetVolume(nextVolume)
                ShowNotification("Volume " nextVolume "%")
            } catch {
                ShowNotification("Windows volume control is unavailable", "Warning")
            }
        case "displayResolution":
            CycleDisplayResolution(direction)
        case "displayRefresh":
            CycleDisplayFrequency(direction)
        case "displayScale":
            CycleDisplayScale(direction)
        case "hdr":
            SetQuickMenuHdrState(direction > 0)
        case "rtssOverlayState":
            SetRtssOverlayState(direction > 0)
        case "rtssFrameLimit":
            ; Same Custom transition as the A press above.
            if CycleRtssFrameCap(direction) {
                QuickMenuBuildGui()
                return
            }
        case "rtssFrameLimitCustom":
            AdjustRtssCustomFrameCap(direction)
    }
    QuickMenuRefresh()
}

QuickMenuHandleController(pressed, lx, ly, buttons := 0) {
    global QuickMenuRows, QuickMenuSelected
    global QuickMenuPage, ControllerChordHoldMs
    static holdDir := 0
    static holdSince := 0
    static lastRepeatTick := 0
    static stickDir := ""
    static lastStickTick := 0
    static mainYDownTick := 0
    static mainYLongFired := false

    ; Holding Y opens the styled Quick Settings mapping page. The separate
    ; editor remains available from that page's final row.
    if (QuickMenuPage != "MAIN") {
        mainYDownTick := 0
        mainYLongFired := false
    } else if (buttons & 0x8000) {
        if !mainYDownTick
            mainYDownTick := A_TickCount
        if (!mainYLongFired
            && A_TickCount - mainYDownTick >= ControllerChordHoldMs) {
            mainYLongFired := true
            QuickMenuPage := "LAYOUT"
            QuickMenuSelected := 1
            QuickMenuBuildGui()
        }
        return
    } else {
        mainYDownTick := 0
        mainYLongFired := false
    }

    ; Left-stick navigation with a short repeat delay for couch use.
    ;
    ; lx and ly were already being passed in from the poll loop and then never
    ; read, so the menu could only be driven from the D-pad. The stick is folded
    ; into the same D-pad bits below rather than handled separately, so every
    ; rule that follows -- hold-to-repeat, row types, page transitions -- applies
    ; identically however the direction arrived.
    newDir := ""
    if (Abs(ly) > 18000)
        newDir := (ly > 0) ? "UP" : "DOWN"
    else if (Abs(lx) > 18000)
        newDir := (lx > 0) ? "RIGHT" : "LEFT"
    if (newDir = "") {
        stickDir := ""
    } else if (newDir != stickDir || A_TickCount - lastStickTick >= 280) {
        stickDir := newDir
        lastStickTick := A_TickCount
        if (newDir = "UP")
            pressed |= 0x0001
        else if (newDir = "DOWN")
            pressed |= 0x0002
        else if (newDir = "LEFT")
            pressed |= 0x0004
        else if (newDir = "RIGHT")
            pressed |= 0x0008
    }

    ; Hold-to-repeat for Left/Right, on rows that are a number rather than a list.
    ;
    ; A press is ALWAYS exactly one step, no matter how fast presses arrive. The
    ; earlier design grew the step after several quick presses, which meant
    ; tapping quickly silently changed what a tap did -- the same gesture
    ; producing 1 or 5 or 10 depending on timing the user could not see.
    ;
    ; Speed comes from holding instead, and it accelerates the REPEAT RATE rather
    ; than the step. Every change stays 1, so the value is always predictable and
    ; can be stopped exactly where wanted; holding simply delivers more of them.
    ; That also removes the need to snap to a grid, which only existed to make
    ; large steps land on round numbers.
    ;
    ; List-valued rows (audio output, resolution) are excluded: scrubbing those
    ; at 50 changes a second would be useless and would fire real device work
    ; per step.
    if QuickMenuRowAcceptsRepeat() {
        dpadDir := (buttons & 0x0008) ? 1 : ((buttons & 0x0004) ? -1 : 0)
        if (!dpadDir) {
            holdDir := 0
        } else if (dpadDir != holdDir) {
            holdDir := dpadDir
            holdSince := A_TickCount
            lastRepeatTick := A_TickCount
        } else {
            heldMs := A_TickCount - holdSince
            if (heldMs >= 400) {
                interval := heldMs >= 2500 ? 20 : (heldMs >= 1200 ? 40 : 80)
                if (A_TickCount - lastRepeatTick >= interval) {
                    lastRepeatTick := A_TickCount
                    pressed |= (dpadDir > 0 ? 0x0008 : 0x0004)
                }
            }
        }
    } else {
        holdDir := 0
    }

    if (pressed & 0x0001) {
        QuickMenuMoveSelection(-1)
        return
    }
    if (pressed & 0x0002) {
        QuickMenuMoveSelection(1)
        return
    }
    if (pressed & 0x0004) {
        QuickMenuAdjustSelected(-1)
        return
    }
    if (pressed & 0x0008) {
        QuickMenuAdjustSelected(1)
        return
    }
    if (pressed & 0x1000) {
        QuickMenuActivateSelected()
        return
    }
    if (pressed & 0x2000) {
        QuickMenuGoBack()
        return
    }
    if (pressed & 0x4000) {
        QuickMenuCloseSelected()
        return
    }
}

; ==============================================================================
; Settings GUI
; ==============================================================================

SettingsMarkDirty(*) {
    global SettingsDirty
    SettingsDirty := true
    SettingsUpdateStatus()
}

SettingsUpdateStatus(message := "") {
    global SettingsGui, SettingsDirty
    if !IsSet(SettingsGui)
        return
    text := message != "" ? message : (SettingsDirty ? "Unsaved changes" : "All changes saved")
    try SettingsGui["SettingsStatus"].Text := text
}

ShowSettingsCategory(categoryName) {
    ShowSettings()
    for index, meta in SettingsCategoryTable() {
        if (meta[1] = categoryName) {
            SettingsShowCategory(index)
            return
        }
    }
}

ShowSettings(*) {
    global SettingsGui, SettingsVisible, SettingsFields, SettingsDirty
    global SettingsCategoryControls, SettingsCategoryList
    global SettingsCategoryTitleCtrl, SettingsCategoryDescriptionCtrl
    global SettingsCurrentCategory, MouseHidden, IniPath, LogPath
    global StartupProgramsList, LogonTaskStatusCtrl
    global SettingsControlPositions, SettingsCategoryOffsets, SettingsScrollBar
    LogLine("Settings window requested.")
    if SettingsVisible {
        try SettingsGui.Show()
        try WinActivate("ahk_id " SettingsGui.Hwnd)
        return
    }
    if MouseHidden {
        SystemCursor("Show")
        MouseHidden := false
    }
    SettingsFields := Map()
    SettingsCategoryControls := Map()
    ; Cleared with the controls they describe. CloseSettings destroys the window,
    ; so a stale HWND from the previous session would otherwise be looked up
    ; against a control that no longer exists.
    SettingsControlPositions := Map()
    SettingsCategoryOffsets := Map()
    for _, name in SettingsCategoryNames()
        SettingsCategoryControls[name] := []
    SettingsDirty := false
    SettingsCurrentCategory := 1
    ; +AlwaysOnTop is what actually makes this window appear.
    ;
    ; Xbox FSE is a fullscreen window, so a normal window can take the foreground
    ; and still render BEHIND it -- which is exactly what was happening: Settings
    ; was focused but invisible, and only the task switcher revealed it. The Quick
    ; Menu never had this problem because it has always been always-on-top. No
    ; amount of retrying SetForegroundWindow fixes a z-order problem.
    settings := Gui("-Resize +AlwaysOnTop +MinSize980x600",
        "SteamShell XFE Settings")
    settings.Opt("+OwnDialogs")
    settings.MarginX := 24
    settings.MarginY := 16
    settings.SetFont("s18 Bold", "Segoe UI")
    settings.AddText("x24 y16 w940 h34", "SteamShell XFE Settings")
    settings.SetFont("s9 Norm", "Segoe UI")
    settings.AddText("x24 y52 w950 h24",
        "Right stick pointer • RB click • D-pad navigate • LT/RT categories • X keyboard • Y save")
    SettingsCategoryList := settings.AddListBox(
        "x24 y96 w225 h500 Choose1",
        SettingsCategoryNames())
    SettingsCategoryList.OnEvent("Change", SettingsCategoryChanged)
    settings.AddText("x245 y96 w1 h504 +0x10")
    settings.SetFont("s16 Bold", "Segoe UI")
    SettingsCategoryTitleCtrl := settings.AddText("x255 y96 w690 h32", "General")
    settings.SetFont("s9 Norm", "Segoe UI")
    SettingsCategoryDescriptionCtrl := settings.AddText(
        "x255 y132 w690 h42 +Wrap",
        "Quick Menu, heartbeat, and the controls shown in the living-room interface.")

    ; --------------------------------------------------------------------------
    ; Pages
    ; --------------------------------------------------------------------------
    ; Every row places itself from the page cursor, so adding one costs a line
    ; and the rest re-flows. Pages may run past the bottom of the window; the
    ; viewport scrolls.
    ;
    ; The four categories that carry the same name as a standalone category --
    ; General, Controller & Cursor, RTSS & Performance, Startup Programs -- now
    ; present the settings that exist in BOTH in standalone's order and wording.
    ; Settings that exist only here follow them. The other three pages have no
    ; standalone counterpart and are ordered for their own sake, which is
    ; correct: standalone's Startup & Splash, Focus & Windows and Launcher
    ; Cleanup do jobs XFE deliberately leaves to Xbox FSE.
    settings.SetFont("s10", "Segoe UI")

    ; General
    category := "General"
    y := SettingsFirstRowY()
    SettingsAddRowsForCategory(settings, category, "xfe", &y)
    SettingsAddButtonRow(settings, category, [
        ["Customize Quick Menu...", ShowQuickMenuLayoutManager]], &y)
    ; Startup is no longer something to configure here. Setup Assistant inside
    ; SteamShell.exe registers a per-user logon task when it installs XFE, so the
    ; old advice to add SteamShell-XFE.exe as an AnyFSE startup application now
    ; starts the companion twice. What is left is the part Setup cannot do,
    ; because it belongs to AnyFSE's own configuration.
    SettingsAddNote(settings, category,
        "Integration: configure AnyFSE to launch Steam Big Picture as the Home "
        . "app, and leave “Exit FSE when Home app exits�? off. Setup Assistant "
        . "already starts this companion at sign-in — do not also add it to "
        . "AnyFSE's startup applications.", &y, 60)

    ; Controller & Cursor
    category := "Controller & Cursor"
    y := SettingsFirstRowY()
    ; The rows themselves are defined once, in SteamShell-Shared.ahk, so this
    ; page and the shell's cannot describe the same settings differently.
    SettingsAddRowsForCategory(settings, category, "xfe", &y)
    SettingsAddTextField(settings, category, "Controller", "AutoMouseExeList",
        "Automatic mouse applications (pipe-separated)", &y,
        DefaultAutoMouseExeList())
    SettingsAddNote(settings, category,
        "The controller acts as a mouse in these applications without holding "
        . "View/Back. Leave Xbox FSE off the list: it is controller-driven and "
        . "a pointer inside it gets in the way.", &y, 40)
    SettingsAddButtonRow(settings, category, [
        ["Add Recent Application...", XfeAddRecentAutoMouseApp]], &y)
    SettingsAddButtonRow(settings, category, [
        ["Controller Mappings...", ShowMappingEditor],
        ["Learn Controller...", ShowControllerLearner],
        ["Delete Learned Profile", DeleteControllerProfileForActiveDevice]], &y)

    ; Steam — no standalone counterpart. Standalone keeps its three Steam
    ; shortcuts in General; here they belong to a page that also owns the View
    ; button behaviour, which standalone does not have.
    category := "Steam"
    y := SettingsFirstRowY()
    SettingsAddNote(settings, category,
        "These shortcuts must match the bindings configured inside Steam itself. "
        . "The menu shortcuts only reach Steam while Steam owns the foreground.",
        &y, 40)
    SettingsAddRowsForCategory(settings, category, "xfe", &y)
    SettingsAddNote(settings, category,
        "Longer in a game: View is often the scoreboard button and gets held.",
        &y)

    ; RTSS & Performance
    category := "RTSS & Performance"
    y := SettingsFirstRowY()
    SettingsAddRowsForCategory(settings, category, "xfe", &y)

    ; Startup Programs
    category := "Startup Programs"
    y := SettingsFirstRowY()
    SettingsAddRowsForCategory(settings, category, "xfe", &y)
    StartupProgramsList := settings.AddListBox(
        "x" SettingsLayout()["contentX"] " y" y
        . " w" SettingsLayout()["contentWidth"] " h180")
    SettingsTrackControl(category, StartupProgramsList)
    y += 190
    SettingsAddButtonRow(settings, category, [
        ["Add Program...", SettingsAddStartupProgram],
        ["Remove Selected", SettingsRemoveStartupProgram]], &y)
    SettingsAddNote(settings, category,
        "Hidden suits background helpers that should never draw over Xbox FSE.",
        &y)

    ; Assist — no standalone counterpart. Standalone has a coordinated Window
    ; Engine and a full Launcher Cleanup; these are the deliberately smaller
    ; versions that never touch presentation.
    category := "Assist"
    y := SettingsFirstRowY()
    SettingsAddNote(settings, category,
        "Automatic help from the shared default profile. None of these ever resize, "
        . "centre or maximise anything — Xbox FSE keeps control of presentation.",
        &y, 40)
    SettingsAddRowsForCategory(settings, category, "xfe", &y)
    SettingsAddNote(settings, category,
        "Process lists are edited in the INI under [Assist]. Assistance always "
        . "pauses while any SteamShell XFE window is in front. Use Quick Menu → "
        . "All Settings → Advanced → Probe Screen to identify an overlay that is "
        . "not being caught.", &y, 52)

    ; Launcher cleanup
    ;
    ; Its own page, as in the shell. These rows were spread across the Assist
    ; page -- three of them -- while three MORE settings this product reads on
    ; every load had no control at all: RequireNoGame, GracefulCloseMs and the
    ; launcher list. A page collects them where somebody looking for launcher
    ; behaviour will look.
    category := "Launcher Cleanup"
    y := SettingsFirstRowY()
    SettingsAddRowsForCategory(settings, category, "xfe", &y)
    SettingsAddNote(settings, category,
        "The launcher list itself is edited in the INI under [LauncherCleanup] "
        . "LauncherProcesses, alongside the protected-process list under "
        . "[Assist] ProtectedProcesses.", &y, 40)

    ; Advanced
    category := "Advanced & Logging"
    y := SettingsFirstRowY()
    SettingsAddNote(settings, category,
        "This companion contains no shell registration, Explorer control, taskbar "
        . "hiding, or window sizing. Xbox FSE keeps control of presentation.",
        &y, 40)
    SettingsAddButtonRow(settings, category, [
        ["Open INI", (*) => Run(IniPath)],
        ["Open Log", (*) => Run(LogPath)],
        ["Health Check", ShowHealthCheck],
        ["Reload INI", ReloadSettings],
        ["Park Cursor Now", ParkCursor],
        ["Exit Companion", ExitCompanion],
        ["Diagnostic ZIP", ExportDiagnosticBundle],
        ["Create Logon Task", CreateLogonTask],
        ["Remove Logon Task", RemoveLogonTask],
        ["Probe Screen", SettingsProbeScreen],
        ["Check Logon Task", SettingsCheckLogonTask],
        ["Re-arm Controller", RearmControllerInput]], &y)
    LogonTaskStatusCtrl := settings.AddText("x" SettingsLayout()["contentX"]
        . " y" y " w" SettingsLayout()["contentWidth"] " h20 +Wrap", "")
    SettingsTrackControl(category, LogonTaskStatusCtrl)
    y += 28
    SettingsAddRowsForCategory(settings, category, "xfe", &y)
    SettingsAddNote(settings, category,
        "The heartbeat log proves whether the companion remains responsive while "
        . "Xbox FSE is active. Diagnostic logging compares every controller slot "
        . "against GameInput and records the foreground process, which reveals a "
        . "virtualised pad forwarding only some buttons.", &y, 60)

    settings.AddText("x24 y616 w430 h26 vSettingsStatus", "All changes saved")
    saveButton := settings.AddButton("x700 y610 w135 h34 Default", "Save && Apply")
    saveButton.OnEvent("Click", SaveSettings)
    closeButton := settings.AddButton("x850 y610 w110 h34", "Close")
    closeButton.OnEvent("Click", CloseSettings)
    settings.OnEvent("Close", CloseSettings)
    settings.OnEvent("Escape", CloseSettings)

    ; Added last, so it sits above the page content in z-order, and sized to the
    ; viewport rather than the window: it scrolls the page, not the frame.
    layout := SettingsLayout()
    SettingsScrollBar := settings.Add("Custom",
        "ClassScrollBar x" layout["scrollBarX"] " y" layout["contentTop"]
        . " w" layout["scrollBarWidth"]
        . " h" (layout["contentBottom"] - layout["contentTop"]) " 0x1")
    ; Re-registering the same callback is a no-op, so this is safe on every open.
    OnMessage(0x020A, SettingsMouseWheel) ; WM_MOUSEWHEEL
    OnMessage(0x0115, SettingsVerticalScroll) ; WM_VSCROLL

    SettingsGui := settings
    SettingsVisible := true
    ; Audited on the real controls, before anything is shown. Font and DPI decide
    ; the actual size of a row, so an overlap that no source-level check can see
    ; is only visible here.
    SettingsReportLayoutAudit()
    SettingsPopulate()
    SettingsShowCategory(1)
    foreground := 0
    try foreground := WinExist("A")
    monitorIndex := GetMonitorIndexForWindow(foreground)
    CenterGuiOnMonitorActual(settings, monitorIndex, 920, 660)
    RecenterVisibleGuiOnMonitorActual(settings, monitorIndex)
    ; Same reason as the Quick Menu: without the foreground, the application
    ; behind keeps receiving controller input while Settings is on screen.
    ;
    ; Retried, because inside Xbox FSE the first attempt loses. FSE re-asserts its
    ; own window right after ours appears, which is why opening Settings a SECOND
    ; time worked -- by then the contest was over. The retries are bounded and
    ; stop as soon as the window is actually in front.
    try ForceForegroundWindow(settings.Hwnd)
    SettingsForegroundRetry(0)
}

; Bounded retry of the foreground grab for the Settings window.
SettingsForegroundRetry(attempt) {
    global SettingsGui, SettingsVisible
    static DELAYS := [120, 300, 700]
    if (!IsSet(SettingsGui) || !SettingsVisible)
        return
    hwnd := 0
    try hwnd := SettingsGui.Hwnd
    if !hwnd
        return
    active := false
    try active := WinActive("ahk_id " hwnd) != 0
    if active {
        if attempt
            LogLine("Settings: came to the front after " attempt " retry"
                . (attempt = 1 ? "" : "s") ".")
        return
    }
    if (attempt >= DELAYS.Length) {
        LogLine("Settings: could not take the foreground after "
            . DELAYS.Length " retries; use the task switcher.", "Warning")
        return
    }
    try ForceForegroundWindow(hwnd)
    SetTimer(() => SettingsForegroundRetry(attempt + 1), -DELAYS[attempt + 1])
}

; ==============================================================================
; SETTINGS LAYOUT AND SCROLLING
; ==============================================================================
; One place for the page geometry. Every builder below reads it, so a row cannot
; be half-ported: changing a column here moves every row that uses it.
;
; The content viewport is everything between the page description and the footer.
; A page may be taller than that; what does not fit scrolls.

SettingsFirstRowY() {
    return SettingsLayout()["contentTop"]
}

; Records the control against its category AND its original geometry.
;
; Every control reaches this function -- the shared row builders through
; SettingsProductTrackControl, the hand-placed ones directly -- so it is the one
; choke point where positions can be captured without a builder being able to
; forget. "scrollable" separates page content from the fixed frame
; (title, description, category list, footer), which must never move.
SettingsTrackControl(category, control) {
    global SettingsCategoryControls, SettingsControlPositions
    global SettingsCategoryOffsets
    SettingsCategoryControls[category].Push(control)
    if !SettingsCategoryOffsets.Has(category)
        SettingsCategoryOffsets[category] := 0
    try {
        control.GetPos(&ctrlX, &ctrlY, &ctrlW, &ctrlH)
        SettingsControlPositions[control.Hwnd] := Map(
            "category", category,
            "x", ctrlX, "y", ctrlY, "w", ctrlW, "h", ctrlH,
            "scrollable", ctrlY >= SettingsLayout()["contentTop"])
    }
    return control
}

; How far this category can scroll, measured from what it actually built rather
; than from a number someone has to remember to update.
SettingsGetMaxScroll(category) {
    global SettingsCategoryControls, SettingsControlPositions
    bottom := SettingsLayout()["contentBottom"]
    maxBottom := bottom
    if !SettingsCategoryControls.Has(category)
        return 0
    for _, control in SettingsCategoryControls[category] {
        if !SettingsControlPositions.Has(control.Hwnd)
            continue
        pos := SettingsControlPositions[control.Hwnd]
        if pos["scrollable"]
            maxBottom := Max(maxBottom, pos["y"] + pos["h"])
    }
    return Max(0, maxBottom - bottom)
}

; Shows one category at its current scroll offset and hides every other.
;
; Redraw is suspended for the whole pass. Without it Windows repaints between the
; Move and the Visible change during thumb tracking, which leaves trails and
; half-drawn controls -- the same reason the Quick Menu composes its pages with
; redraw suspended.
SettingsApplyCategoryLayout(activeCategory) {
    global SettingsCategoryControls, SettingsControlPositions
    global SettingsCategoryOffsets
    layout := SettingsLayout()
    contentTop := layout["contentTop"]
    contentBottom := layout["contentBottom"]
    SettingsEditorSetRedraw(false)
    try {
        offset := SettingsCategoryOffsets.Has(activeCategory)
            ? SettingsCategoryOffsets[activeCategory] : 0
        maxOffset := SettingsGetMaxScroll(activeCategory)
        offset := ClampInt(offset, 0, maxOffset)
        SettingsCategoryOffsets[activeCategory] := offset
        for category, controls in SettingsCategoryControls {
            isActive := category = activeCategory
            for _, control in controls {
                if !isActive {
                    try control.Visible := false
                    continue
                }
                if !SettingsControlPositions.Has(control.Hwnd) {
                    try control.Visible := true
                    continue
                }
                pos := SettingsControlPositions[control.Hwnd]
                if !pos["scrollable"] {
                    try control.Move(pos["x"], pos["y"], pos["w"], pos["h"])
                    try control.Visible := true
                    continue
                }
                newY := pos["y"] - offset
                ; Hidden rather than clipped, because a control moved above the
                ; viewport would otherwise draw over the page title and the
                ; category list.
                inside := newY >= contentTop && newY + pos["h"] <= contentBottom
                try control.Move(pos["x"], newY, pos["w"], pos["h"])
                try control.Visible := inside
            }
        }
        SettingsUpdateScrollBar(offset, maxOffset)
    } finally {
        SettingsEditorSetRedraw(true)
        SettingsEditorRepaint()
    }
}

SettingsActiveCategoryName() {
    global SettingsCurrentCategory
    return SettingsCategoryMeta(SettingsCurrentCategory)[1]
}

SettingsScroll(direction, *) {
    global SettingsCategoryOffsets, SettingsVisible
    if !SettingsVisible
        return
    category := SettingsActiveCategoryName()
    current := SettingsCategoryOffsets.Has(category)
        ? SettingsCategoryOffsets[category] : 0
    maxOffset := SettingsGetMaxScroll(category)
    SettingsCategoryOffsets[category] :=
        ClampInt(current + (direction * 68), 0, maxOffset)
    SettingsApplyCategoryLayout(category)
}

SettingsVerticalScroll(wParam, lParam, msg, hwnd) {
    global SettingsGui, SettingsScrollBar, SettingsCategoryOffsets, SettingsVisible
    if (!IsSet(SettingsGui) || !SettingsVisible || !IsObject(SettingsScrollBar))
        return
    if (lParam != SettingsScrollBar.Hwnd)
        return
    layout := SettingsLayout()
    category := SettingsActiveCategoryName()
    current := SettingsCategoryOffsets.Has(category)
        ? SettingsCategoryOffsets[category] : 0
    maxOffset := SettingsGetMaxScroll(category)
    scrollCode := wParam & 0xFFFF
    lineStep := 34
    pageStep := Max(68, layout["contentBottom"] - layout["contentTop"] - 34)
    switch scrollCode {
        case 0: ; SB_LINEUP
            newOffset := current - lineStep
        case 1: ; SB_LINEDOWN
            newOffset := current + lineStep
        case 2: ; SB_PAGEUP
            newOffset := current - pageStep
        case 3: ; SB_PAGEDOWN
            newOffset := current + pageStep
        case 4, 5: ; SB_THUMBPOSITION / SB_THUMBTRACK
            newOffset := SettingsEditorGetScrollTrackPosition()
        case 6: ; SB_TOP
            newOffset := 0
        case 7: ; SB_BOTTOM
            newOffset := maxOffset
        default:
            return 0
    }
    SettingsCategoryOffsets[category] := ClampInt(newOffset, 0, maxOffset)
    SettingsApplyCategoryLayout(category)
    return 0
}

; The wheel is also how the CONTROLLER scrolls: the left stick already sends
; WheelUp/WheelDown while a Settings surface is active, so pointing with the
; right stick and scrolling with the left works without a new binding.
SettingsMouseWheel(wParam, lParam, msg, hwnd) {
    global SettingsGui, SettingsVisible
    if (!IsSet(SettingsGui) || !SettingsVisible)
        return
    if !SettingsWheelNotch(wParam, hwnd, SettingsGui.Hwnd, &notch)
        return
    if notch
        SettingsScroll(notch)
    return 0
}

; Audits the ORIGINAL, unscrolled geometry of every page.
;
; This runs once, on the real native controls, so it catches what a source regex
; cannot: DPI- and font-dependent control sizes, two rows accidentally given the
; same cursor value, content crossing into the category list, and controls
; running under the scrollbar. It reports rather than blocking Settings, because
; Settings is also the recovery surface.
; This product's state and content column, handed to the shared audit. See the
; shell's twin: the algorithm is one function, the bounds are two numbers.
SettingsAuditLayout() {
    global SettingsCategoryControls, SettingsControlPositions
    layout := SettingsLayout()
    return SharedAuditSettingsLayout(
        SettingsCategoryNames(), SettingsCategoryControls,
        SettingsControlPositions,
        286, layout["scrollBarX"])
}

SettingsShowLayoutWarning(text) {
    SettingsUpdateStatus(text)
}

SettingsReportLayoutAudit() {
    return SharedReportSettingsLayoutAudit(
        SettingsAuditLayout(), SettingsShowLayoutWarning)
}

; ------------------------------------------------------------------------------
; Flowing row builders
; ------------------------------------------------------------------------------
; Every builder takes the page cursor by reference and advances it, so a row
; places itself and adding one costs a line. Before this, each control carried a
; literal y and inserting a row meant re-flowing the whole page by hand -- which
; is why two pages grew sideways into a hand-placed second column instead.
;
; Rows may run past the bottom of the window; the viewport scrolls.

; A choice row stores its value as text, not as the DropDownList's 1-based
; index, so the INI keeps a readable preset name. GetFieldValue/SetFieldValue
; both work in .Value, which for a DropDownList is that index -- hence the
; separate text accessors below rather than a change to the generic pair, which
; every other field type depends on.
;
; The CHOICE ORDER of each list is load-bearing where the value is derived from
; Choice rows are selected and saved by their TEXT, as the shell does. They used
; to be selected and saved by INDEX, which tied the value in the INI to the
; ORDER of a list kept somewhere else -- and two of those lists were in the
; opposite order from the shell's.
;
; A field is identified by Section.Key, the same string its populate and its
; save use. It used to be identified by an id that predated schema 13's section
; moves -- "Cursor.EnableAutoHide" for a setting living at [Features]
; EnableAutoHideCursor -- so the row, the populate and the save agreed only
; because three hand-written names happened to match.
; Per-tree seams required by SteamShell-Shared.ahk's row builders.
;
; Registration records the control against the key its spec names, and tracks
; every control so it shows and hides with its category.
SettingsRegisterBuiltField(category, field) {
    global SettingsFields
    SettingsFields[field["section"] "." field["key"]] := field["ctrl"]
    for _, ctrl in field["controls"]
        SettingsProductTrackControl(category, ctrl)
}

; Per-tree seam: a control belongs to a category, and shows and hides with it.
SettingsProductTrackControl(category, ctrl) {
    SettingsTrackControl(category, ctrl)
}

SettingsProductMarkDirty(*) {
    SettingsMarkDirty()
}

; Only one path row exists here and it is RTSS's, which is why the browse
; callback was a parameter rather than derived: there was nothing to derive it
; from. The shared builder passes the field, so it can be.
SettingsProductBrowsePath(field, prompt, filter, *) {
    SettingsBrowseRtss()
}

SettingsProductRecordShortcut(field, *) {
    SettingsRecordShortcut(field["section"] "." field["key"])
}

; Per-tree seams for the shared adapter. This product has no dependency pass --
; nothing here greys a row from another row -- and it does have section breaks,
; which replaced the group boxes that could not flow.
; Greys the rows whose driver has turned them off.
;
; This body was empty, and that was recorded as a design choice -- the companion
; has no dependency pass, so the seam does nothing. It reads as settled until you
; ask which rows the shared spec marks with "dependency", because two of the
; eight are "product", "both": the RTSS overlay and frame-limiter control modes.
; Both reach this window, and neither did anything here: choosing Toggle left the
; separate On and Off shortcut rows enabled and editable, and choosing Separate
; left the single Toggle shortcut the same way. The user could type a shortcut
; into a field the selected mode ignores, save it, and see no effect.
;
; Only the RTSS pair is handled. The other six dependency rows are all
; "product", "standalone" -- game-assist, window management and launcher cleanup
; -- and none of them is built into this window at all.
SettingsProductWireDependency(ctrl, eventName) {
    ctrl.OnEvent(eventName, SettingsRefreshDependencies)
}

SettingsRefreshDependencies(*) {
    global SettingsFields
    if (SettingsFields.Count = 0)
        return
    ; Compared by TEXT, as everything else in this window now is: the choice rows
    ; carry their words, and the index they sit at is not a value anything else
    ; agrees about.
    overlaySeparate :=
        StrLower(GetFieldText("RTSS.OverlayControlMode", "separate")) = "separate"
    limiterSeparate :=
        StrLower(GetFieldText("RTSS.FrameLimiterControlMode", "separate")) = "separate"
    SettingsSetFieldEnabled("RTSS.OverlayToggleShortcut", !overlaySeparate)
    SettingsSetFieldEnabled("RTSS.OverlayOnShortcut", overlaySeparate)
    SettingsSetFieldEnabled("RTSS.OverlayOffShortcut", overlaySeparate)
    SettingsSetFieldEnabled("RTSS.CustomFrameCapShortcut", !limiterSeparate)
    SettingsSetFieldEnabled("RTSS.FrameLimiterOnShortcut", limiterSeparate)
    SettingsSetFieldEnabled("RTSS.FrameLimiterOffShortcut", limiterSeparate)
}

SettingsSetFieldEnabled(key, enabled) {
    global SettingsFields
    if !SettingsFields.Has(key)
        return
    try SettingsFields[key].Enabled := enabled ? true : false
}

SettingsProductAddSectionRow(guiObj, category, title, &y) {
    SettingsAddSectionRow(guiObj, category, title, &y)
}

; A caption, not a field. Used where a page needs a sentence of context and for
; the section breaks that replaced the two side-by-side group boxes on the RTSS
; page -- group boxes cannot flow, because their height has to be known before
; the rows inside them exist.
SettingsAddSectionRow(guiObj, category, title, &y) {
    layout := SettingsLayout()
    ; One advance, not two. A lead-in written as a second `y +=` would be a
    ; second number for the layout simulation in Test-ControllerProfiles.py to
    ; find, and it would find the first one.
    top := y + 10
    control := guiObj.AddText("x" layout["contentX"] " y" top
        . " w" layout["contentWidth"] " h22", title)
    control.SetFont("s10 Bold", "Segoe UI")
    SettingsTrackControl(category, control)
    ; Restored immediately: AddText inherits the GUI font, so leaving it bold
    ; would silently embolden every row built after this one.
    guiObj.SetFont("s10 Norm", "Segoe UI")
    y += 38
    return control
}

GetFieldText(key, fallback := "") {
    global SettingsFields
    if !SettingsFields.Has(key)
        return fallback
    text := SettingsFields[key].Text
    return (text != "") ? text : fallback
}

SetFieldText(key, value) {
    global SettingsFields
    if SettingsFields.Has(key)
        try SettingsFields[key].Text := value
}

; Appends a recently used application to a pipe-separated exe-list field.
;
; This tree has no ListView exe editor -- its lists are a single edit control
; holding "a.exe|b.exe" -- so the shared picker's answer is appended as text
; rather than added as a row. That is the whole reason ShowApplicationPicker
; hands the choice to a CALLBACK instead of returning it: the shell inserts a
; ListView row, this appends to a string, and the picker has to know neither.
;
; Reads the CONTROL rather than the saved setting, so choosing twice before
; saving adds two applications rather than the second replacing the first.
XfeAppendRecentExeToField(key, exe) {
    exe := StrLower(Trim(exe))
    if (exe = "")
        return
    current := Trim(GetFieldText(key, ""))
    ; ProcessNameSetFromList and not the shell's ParseExeListPipe: this is the
    ; parser this tree uses to build the live set from this very field, so the
    ; duplicate check answers the same question the product will ask of the value
    ; after it is saved. The shell's parser also strips inline comments and
    ; appends a missing ".exe", which are not this field's rules.
    if ProcessNameSetFromList(current).Has(exe) {
        SettingsUpdateStatus(exe " is already in that list.")
        return
    }
    SetFieldText(key, current = "" ? exe : current "|" exe)
    SettingsMarkDirty()
    SettingsUpdateStatus("Added " exe ". Save to keep it.")
}

XfeAddRecentAutoMouseApp(*) {
    ShowApplicationPicker(
        "Add a recently used application to the automatic mouse list.",
        XfeAppendRecentExeToField.Bind("Controller.AutoMouseExeList"))
}

; A text field with a Browse button, for a path. Wider than a plain edit row
; because a path is unreadable in 150 pixels.
; Up to three buttons on one flowing line. entries is an array of
; [label, callback] pairs; more than three wraps onto the next line.

; Runs the screen probe from the Settings window. Settings itself is hidden for
; the duration: the probe exists to identify some other surface, and leaving our
; own window in front is the one guaranteed way to capture nothing useful.
SettingsProbeScreen(*) {
    global SettingsGui, SettingsVisible
    if (IsSet(SettingsGui) && SettingsVisible) {
        try SettingsGui.Hide()
        ; Restore a little after the capture, so the window coming back cannot
        ; itself land in the probe's inventory.
        SetTimer(() => SettingsRestoreAfterProbe(), -7500)
    }
    StartScreenProbe(6000)
}

SettingsRestoreAfterProbe() {
    global SettingsGui, SettingsVisible
    if (!IsSet(SettingsGui) || !SettingsVisible)
        return
    try SettingsGui.Show()
    try ForceForegroundWindow(SettingsGui.Hwnd)
}

; The one definition of the Settings categories. The list box, the page titles,
; the descriptions and LT/RT wrapping all read from here, so adding a category
; cannot leave one of them behind.
SettingsCategoryTable() {
    static categories := [
        ["General",
            "Quick Menu, heartbeat, and the controls shown in the living-room interface."],
        ["Controller & Cursor",
            "View/Back mappings, controller pointer behavior, cursor hiding, and parking."],
        ["Steam",
            "Steam shortcuts, and which View button actions are enabled."],
        ["RTSS & Performance",
            "RTSS executable, DLL live-state mode, shortcut fallback, and cap controls."],
        ["Startup Programs",
            "Applications launched shortly after the companion starts."],
        ["Assist",
            "Optional automatic help: game focus, Steam return, and when to stay "
            . "out of the way."],
        ["Launcher Cleanup",
            "Closing game launchers that keep running after the game has exited."],
        ; "Advanced & Logging", matching the shell. It was "Advanced" here, which
        ; meant the shared row table had to be asked for one name while the page
        ; was drawn under another -- the tableKey argument existed for this single
        ; case. Same rows, same page, same name now, and the argument is gone.
        ["Advanced & Logging",
            "Portable files, diagnostics, cursor test, reload, and companion lifecycle."]
    ]
    return categories
}

SettingsCategoryMeta(index) {
    categories := SettingsCategoryTable()
    index := ClampInt(index, 1, categories.Length)
    return categories[index]
}

SettingsCategoryNames() {
    names := []
    for _, entry in SettingsCategoryTable()
        names.Push(entry[1])
    return names
}

SettingsRefreshStartupProgramsList() {
    global StartupProgramsList, StartupPrograms
    if !IsSet(StartupProgramsList)
        return
    try StartupProgramsList.Delete()
    for _, path in StartupPrograms
        try StartupProgramsList.Add([path])
}

SettingsAddStartupProgram(*) {
    global StartupPrograms, SettingsDialogActive
    SettingsDialogActive := true
    selected := TopmostFileSelect(3, , "Select a program to start",
        "Programs (*.exe)")
    SettingsDialogActive := false
    selected := NormalizePath(selected)
    if (selected = "")
        return
    for _, existing in StartupPrograms {
        if (StrLower(existing) = StrLower(selected)) {
            ShowNotification("That program is already in the list", "Warning")
            return
        }
    }
    if (StartupPrograms.Length >= 40) {
        ShowNotification("Startup program list is full", "Warning")
        return
    }
    StartupPrograms.Push(selected)
    SettingsRefreshStartupProgramsList()
    SettingsMarkDirty()
}

SettingsRemoveStartupProgram(*) {
    global StartupProgramsList, StartupPrograms
    if !IsSet(StartupProgramsList)
        return
    index := 0
    try index := StartupProgramsList.Value
    if (index < 1 || index > StartupPrograms.Length) {
        ShowNotification("Select a program to remove first", "Warning")
        return
    }
    StartupPrograms.RemoveAt(index)
    SettingsRefreshStartupProgramsList()
    SettingsMarkDirty()
}

SettingsCategoryChanged(control, *) {
    SettingsShowCategory(control.Value)
}

SettingsShowCategory(index) {
    global SettingsCategoryControls, SettingsCategoryList
    global SettingsCategoryTitleCtrl, SettingsCategoryDescriptionCtrl
    global SettingsCurrentCategory
    meta := SettingsCategoryMeta(index)
    SettingsCurrentCategory := index
    try SettingsCategoryList.Choose(index)
    SettingsCategoryTitleCtrl.Text := GuiLiteralText(meta[1])
    SettingsCategoryDescriptionCtrl.Text := GuiLiteralText(meta[2])
    ; Shows the page at its own remembered scroll position and hides every other,
    ; which is the only place control visibility is decided now that pages can be
    ; taller than the viewport.
    SettingsApplyCategoryLayout(meta[1])
}

; LT/RT category switching. The wrap point is read from the category table
; rather than hard-coded: it was stuck at 4 while the table had grown to 6, so
; the controller could not reach the last two categories at all.
SettingsChangeCategory(direction) {
    global SettingsCurrentCategory
    count := SettingsCategoryCount()
    nextCategory := SettingsCurrentCategory + direction
    if (nextCategory < 1)
        nextCategory := count
    if (nextCategory > count)
        nextCategory := 1
    SettingsShowCategory(nextCategory)
}

; The number of Settings categories, derived from the same table the list box
; and the titles come from, so adding one cannot leave a stale count behind.
SettingsCategoryCount() {
    return SettingsCategoryTable().Length
}

; The one field this tree builds outside the shared page table.
;
; It was eighteen. The other seventeen moved into SettingsCategoryRows with
; their pages, so they are described where every other row is described. This
; one is a literal row on the Controller page rather than a page of its own,
; and it stays until that row moves too.
;
; movedFrom names the section a setting used to live in, so the read can still
; find a value a migration has not moved yet -- a read-only portable INI never
; gets migrated, and the setting has to keep working where it lies.
SettingsCompanionFieldSpecs() {
    static specs := [
        Map("section", "Controller", "key", "AutoMouseExeList",
            "type", "edit", "default", DefaultAutoMouseExeList())
    ]
    return specs
}

; Every field in the window, shared rows and companion rows together.
SettingsAllFieldSpecs() {
    static all := unset
    if IsSet(all)
        return all
    all := []
    for _, category in SettingsCategoryNames() {
        for _, row in SettingsCategoryRows(category) {
            if (!row.Has("section") || !SettingsRowAppliesTo(row, "xfe"))
                continue
            all.Push(row)
        }
    }
    for _, spec in SettingsCompanionFieldSpecs()
        all.Push(spec)
    return all
}

; Fills the window from the INI, from the specs rather than from a list.
;
; Reads exactly what the old hand-written version read: ReadBool for a checkbox,
; ReadInt with its bounds for a numeric row, ReadText otherwise, and the moved
; section where a row names one.
SettingsPopulateFields() {
    for _, row in SettingsAllFieldSpecs() {
        key := row["section"] "." row["key"]
        section := row.Has("movedFrom")
            ? MovedSettingSection(row["section"], row["movedFrom"], row["key"])
            : row["section"]
        type := row["type"]
        if (type = "checkbox") {
            ; Both spellings, because the two sources spell it differently: the
            ; shared table stores "true" as a string, these specs carry the
            ; literal. AutoHotkey compares the string "true" against the number
            ; 1 as text, so neither test alone covers both.
            enabled := (row["default"] = true || row["default"] = "true")
            SetFieldValue(key, ReadBool(section, row["key"], enabled))
        } else if (type = "choice") {
            SelectChoiceByText(key,
                ReadText(section, row["key"], row["default"]),
                row.Has("xfeChoices") ? row["xfeChoices"] : SettingsRowChoices(row))
        } else if (row.Has("min")) {
            SetFieldValue(key, ReadInt(section, row["key"],
                row["default"], row["min"], row["max"]))
        } else {
            SetFieldValue(key, ReadText(section, row["key"], row["default"]))
        }
    }
}

SettingsPopulate() {
    global SettingsFields, SettingsDirty
    if (SettingsFields.Count = 0)
        return
    ; Every field, from its own spec. This was 111 lines naming all fifty-eight a
    ; second time -- once as a row, once as a read -- and the two agreed only
    ; while somebody kept them in step. They did not always: the controller index
    ; was read as a number after its row became a dropdown, and two settings were
    ; read here with bounds their own LoadSettings had stopped using.
    SettingsPopulateFields()
    ; Sliders carry a separate value readout, and assigning .Value in code does
    ; NOT raise Change -- only the user dragging the track does. Without this the
    ; number beside a slider would show the value it was BUILT with while the
    ; track sits at the loaded one.
    SettingsRefreshSliderReadouts()
    ; Once the values are in, so the window OPENS in the right state. Wiring the
    ; drivers alone would only grey the dependent rows after the user touched a
    ; driver, leaving the first view of the window showing rows the saved mode
    ; already ignores.
    SettingsRefreshDependencies()
    ; Not fields: a list and a status line, filled from elsewhere.
    SettingsRefreshStartupProgramsList()
    SettingsRefreshLogonTaskStatus()
    SettingsDirty := false
    SettingsUpdateStatus()
}

SetFieldValue(key, value) {
    global SettingsFields
    if SettingsFields.Has(key)
        SettingsFields[key].Value := value
}

; Selects a choice row by its TEXT, the way the shell does.
;
; This tree used to Choose() an INDEX for every choice field and read the index
; back on save, so the words on screen and the value in the INI were connected
; only by the ORDER of the list -- and the order lived in a third place. Two
; lists in this program were in the opposite order from the shell's, which made
; merging them a change that would have silently inverted the setting rather
; than a change of wording.
;
; Matching on text has no order to get wrong: the item that says "Toggle" writes
; "toggle". The comparison is case-insensitive and falls back to the first entry,
; because the INI is hand-editable and a value that no longer matches any item
; must land somewhere predictable rather than nowhere.
SelectChoiceByText(key, value, choices) {
    global SettingsFields
    if SettingsFields.Has(key)
        SettingsSelectChoiceByText(SettingsFields[key], value, choices)
}

; Matches the dropdown order: 1 Auto, 2 XInput, 3 GameInput, 4 RawInput.
; Auto is first because it is the default and the only choice that works both
; inside and outside Xbox FSE.
; Matches the dropdown order: 1 Normal, 2 Minimized, 3 Hidden.
; Matches the dropdown order: 1 Right edge, 2 Left edge.
GetFieldValue(key, fallback := "") {
    global SettingsFields
    if !SettingsFields.Has(key)
        return fallback
    return SettingsFields[key].Value
}

; What every field currently holds, ready to be written.
;
; The section, the key and the TYPE all come from the field's own spec, which is
; what makes this safe to derive. Reading the control without knowing its type is
; the trap: a checkbox's .Value is its state but its .Text is its LABEL, and a
; dropdown is the other way round -- .Text is what the user picked, .Value is a
; row number. Sniffing the control would write "Enable RTSS integration in the
; Quick Menu" into the INI for every checkbox at once, and nothing would fail.
;
; An Edit answers the same string to either, which is why "edit", "shortcut" and
; "path" share a branch.
SettingsFieldPairs() {
    pairs := []
    for _, row in SettingsAllFieldSpecs() {
        key := row["section"] "." row["key"]
        default := row.Has("default") ? row["default"] : ""
        if (row["type"] = "checkbox")
            value := GetFieldValue(key) ? "true" : "false"
        else if (row["type"] = "choice")
            value := GetFieldText(key, default)
        else
            value := GetFieldValue(key, default)
        pairs.Push([row["section"], row["key"], value])
    }
    return pairs
}

SaveSettings(*) {
    global IniPath, SettingsDirty
    pairs := SettingsFieldPairs()
    try {
        for _, pair in pairs
            IniWrite(pair[3], IniPath, pair[1], pair[2])
        ; The startup list is variable length, so it is written separately and
        ; before the reload -- LoadSettings would otherwise overwrite the edited
        ; in-memory list with what is still on disk.
        SaveStartupPrograms()
        SettingsDirty := false
        LoadSettings()
        ApplyRuntimeTimers()
        ; Save & Apply is the path this setting is actually toggled from, so the
        ; helper has to start or stop here as well as on Reload.
        SyncElevatedRtssHelperWithSettings()
        SettingsUpdateStatus("Saved and applied")
        ShowNotification("Settings saved and applied")
    } catch as err {
        SettingsUpdateStatus("Save failed: " err.Message)
        ShowNotification("Settings save failed: " err.Message, "Warning")
    }
}

CloseSettings(*) {
    global SettingsGui, SettingsVisible, SettingsDirty, SettingsDialogActive
    if !SettingsVisible
        return
    if SettingsDirty {
        SettingsDialogActive := true
        answer := TopmostMsgBox("Save changes before closing?", "SteamShell XFE Settings",
            "YesNoCancel Icon?")
        SettingsDialogActive := false
        if (answer = "Cancel")
            return
        if (answer = "Yes")
            SaveSettings()
    }
    try SettingsGui.Destroy()
    SettingsVisible := false
    SettingsDirty := false
}

SettingsBrowseRtss(*) {
    global SettingsGui, SettingsDialogActive
    SettingsDialogActive := true
    path := TopmostFileSelect(1, , "Select RTSS.exe", "Programs (*.exe)")
    SettingsDialogActive := false
    if (path != "") {
        SetFieldValue("RTSS.Path", path)
        SettingsMarkDirty()
    }
    try WinActivate("ahk_id " SettingsGui.Hwnd)
}

SettingsRecordShortcut(key, *) {
    global SettingsDialogActive
    SettingsDialogActive := true
    result := RecordShortcutChord()
    SettingsDialogActive := false
    if result["ok"] {
        SetFieldValue(key, result["send"])
        SettingsMarkDirty()
    }
}

; ==============================================================================
; Controller mapping editor
; ==============================================================================
ControllerMappingKeys() {
    return [
        "A.Short", "A.Long", "B.Short", "B.Long", "X.Short", "X.Long",
        "Y.Short", "Y.Long", "LB.Short", "LB.Long", "RB.Short", "RB.Long",
        "LT.Short", "LT.Long", "RT.Short", "RT.Long", "Start.Short",
        "Start.Long", "L3.Short", "L3.Long", "R3.Short", "R3.Long"
    ]
}

ShowMappingEditor(*) {
    global MappingGui, MappingList
    if IsSet(MappingGui) {
        try MappingGui.Show()
        return
    }
    editor := Gui("+AlwaysOnTop +Resize +MinSize680x460", "Controller Mappings")
    editor.SetFont("s10", "Segoe UI")
    editor.AddText("xm ym w720 h42 +Wrap",
        "Controller mouse is automatic in companion settings. These actions run "
        . "elsewhere while View/Back is held or Mouse Mode is enabled. "
        . "Select a row, then choose a built-in action or record a shortcut.")
    list := editor.AddListView("xm y+8 w720 h320 Grid -Multi", ["Input", "Action"])
    list.ModifyCol(1, 140)
    list.ModifyCol(2, 540)
    ; Derived, not typed. This list used to be a third copy of the binding
    ; vocabulary alongside ControllerBindingPretty and MappingBuiltinValue.
    builtins := editor.AddDropDownList("xm y+12 w220 Choose1",
        SharedBindingLabelList(ControllerBindingLabels()))
    applyBuiltin := editor.AddButton("x+8 yp-1 w130 h28", "Set Built-in")
    recordButton := editor.AddButton("x+8 yp w150 h28", "Record Shortcut...")
    resetButton := editor.AddButton("x+8 yp w130 h28", "Restore Defaults")
    closeButton := editor.AddButton("xm y+12 w140 h32", "Close")
    applyBuiltin.OnEvent("Click", MappingSetBuiltin.Bind(builtins))
    recordButton.OnEvent("Click", MappingRecordShortcut)
    resetButton.OnEvent("Click", MappingRestoreDefaults)
    closeButton.OnEvent("Click", CloseMappingEditor)
    editor.OnEvent("Close", CloseMappingEditor)
    editor.OnEvent("Escape", CloseMappingEditor)
    MappingGui := editor
    MappingList := list
    RefreshMappingList()
    editor.Show("AutoSize Center")
}

; A .Long key whose matching .Short is Left click can never fire: that button is
; press-and-hold, and Short is resolved on RELEASE. The editor shows it as
; reserved and refuses to set it, rather than accepting a binding that would
; silently do nothing.
MappingKeyIsReservedForMouse(key) {
    global ControllerMap
    if (StrLower(SubStr(key, -5)) != ".long")
        return false
    shortKey := SubStr(key, 1, StrLen(key) - 5) ".Short"
    return ControllerBindingHoldsMouseButton(GetBindingValue(shortKey))
}

RefreshMappingList() {
    global MappingList
    if !IsObject(MappingList)
        return
    MappingList.Delete()
    for _, key in ControllerMappingKeys()
        MappingList.Add("", key, MappingKeyIsReservedForMouse(key)
            ? "Reserved for mouse (hold to drag)"
            : ControllerBindingPretty(key))
}

SelectedMappingKey() {
    global MappingList
    row := 0
    try row := MappingList.GetNext()
    if !row
        return ""
    return MappingList.GetText(row, 1)
}

MappingBuiltinValue(label) {
    return SharedBindingActionFor(label, ControllerBindingLabels())
}

MappingSetBuiltin(dropDown, *) {
    global ControllerMap, ControllerMapDisplay, IniPath
    key := SelectedMappingKey()
    if (key = "") {
        ShowNotification("Select a controller mapping first", "Warning")
        return
    }
    if MappingKeyIsReservedForMouse(key) {
        ShowNotification(key " is reserved: that button is held to drag the mouse",
            "Warning")
        return
    }
    value := MappingBuiltinValue(dropDown.Text)
    ControllerMap[key] := value
    if ControllerMapDisplay.Has(key)
        ControllerMapDisplay.Delete(key)
    IniWrite(value, IniPath, "ControllerMap", key)
    try IniDelete(IniPath, "ControllerMap", key ".Display")
    RefreshMappingList()
    ShowNotification(key " updated")
}

MappingRecordShortcut(*) {
    global ControllerMap, ControllerMapDisplay, IniPath, SettingsDialogActive
    key := SelectedMappingKey()
    if (key = "") {
        ShowNotification("Select a controller mapping first", "Warning")
        return
    }
    if MappingKeyIsReservedForMouse(key) {
        ShowNotification(key " is reserved: that button is held to drag the mouse",
            "Warning")
        return
    }
    SettingsDialogActive := true
    result := RecordShortcutChord()
    SettingsDialogActive := false
    if result["ok"] {
        ControllerMap[key] := "Send:" result["send"]
        ControllerMapDisplay[key] := result["display"]
        IniWrite("Send:" result["send"], IniPath, "ControllerMap", key)
        IniWrite(result["display"], IniPath, "ControllerMap", key ".Display")
        RefreshMappingList()
        ShowNotification(key " recorded as " result["display"])
    }
}

MappingRestoreDefaults(*) {
    global ControllerMap, ControllerMapDisplay, IniPath
    answer := TopmostMsgBox("Restore every controller mapping to its default?",
        "Controller Mappings", "YesNo Icon?")
    if (answer != "Yes")
        return
    InitDefaultControllerMappings()
    for key, value in ControllerMap {
        IniWrite(value, IniPath, "ControllerMap", key)
        if ControllerMapDisplay.Has(key)
            IniWrite(ControllerMapDisplay[key], IniPath, "ControllerMap", key ".Display")
        else
            try IniDelete(IniPath, "ControllerMap", key ".Display")
    }
    RefreshMappingList()
    ShowNotification("Controller mappings restored to defaults")
}

CloseMappingEditor(*) {
    global MappingGui, MappingList, SettingsDialogActive
    if IsSet(MappingGui)
        try MappingGui.Destroy()
    MappingGui := unset
    MappingList := 0
    SettingsDialogActive := false
}

RecordShortcutKeyDown(inputObj, vk, sc) {
    global _ShortcutCap
    if !IsObject(_ShortcutCap)
        return
    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (keyName = "" || keyName = "Unknown")
        return
    if (keyName = "Escape") {
        RecordShortcutCancel()
        return
    }
    if RecordShortcutSetModifier(keyName, true) {
        if (_ShortcutCap["mainKey"] = "")
            RecordShortcutUpdatePreview()
        return
    }
    _ShortcutCap["mainKey"] := keyName
    _ShortcutCap["snapMods"] := RecordShortcutGetLiveMods()
    RecordShortcutUpdatePreview()
}

RecordShortcutKeyUp(inputObj, vk, sc) {
    global _ShortcutCap
    if !IsObject(_ShortcutCap)
        return
    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if RecordShortcutSetModifier(keyName, false) && _ShortcutCap["mainKey"] = ""
        RecordShortcutUpdatePreview()
}

RecordShortcutSetModifier(keyName, isDown) {
    global _ShortcutCap
    if !IsObject(_ShortcutCap)
        return false
    modifier := ""
    switch keyName {
        case "Ctrl", "Control", "LControl", "RControl", "LCtrl", "RCtrl":
            modifier := "Ctrl"
        case "Alt", "LAlt", "RAlt", "Menu", "LMenu", "RMenu":
            modifier := "Alt"
        case "Shift", "LShift", "RShift":
            modifier := "Shift"
        case "Win", "LWin", "RWin":
            modifier := "Win"
        default:
            return false
    }
    _ShortcutCap["liveMods"][modifier] := isDown
    return true
}

RecordShortcutGetLiveMods() {
    global _ShortcutCap
    mods := Map("Ctrl", false, "Alt", false, "Shift", false, "Win", false)
    try {
        for key, value in _ShortcutCap["liveMods"] {
            if value
                mods[key] := true
        }
    }
    physical := GetPhysicalModsMap()
    for key, value in physical {
        if value
            mods[key] := true
    }
    return mods
}

RecordShortcutUpdatePreview() {
    global _ShortcutCap
    if !IsObject(_ShortcutCap)
        return
    mainKey := _ShortcutCap["mainKey"]
    mods := mainKey != "" ? _ShortcutCap["snapMods"] : RecordShortcutGetLiveMods()
    text := ""
    if mods["Ctrl"]
        text .= "Ctrl+"
    if mods["Alt"]
        text .= "Alt+"
    if mods["Shift"]
        text .= "Shift+"
    if mods["Win"]
        text .= "Win+"
    if (mainKey != "")
        text .= NormalizeKeyForDisplay(mainKey)
    if (text = "")
        text := "(none)"
    try _ShortcutCap["preview"].Text := text
}

RecordShortcutAccept(*) {
    global _ShortcutCap
    if IsObject(_ShortcutCap)
        _ShortcutCap["done"] := true
}

; Bundles the log tail, settings and environment into one zip.
;
; The log records the input backend, the decoded controller reports and the
; window centring maths, so the tail is the single most useful artefact when
; something misbehaves inside Xbox FSE where nothing can be observed directly.
ExportDiagnosticBundle(*) {
    global AppVersion, IniPath, LogPath, ControllerBackend, ActiveInputBackend
    global RawInputProbeActive, RawInputLastReportTick, RawInputDevice
    global GameInputReady, GameInputFailed, ActiveControllerIndex
    stamp := FormatTime(A_Now, "yyyyMMdd-HHmmss")
    tempDir := A_Temp "\SteamShell-XFE-Diagnostics-" stamp
    zipPath := A_Desktop "\SteamShell-XFE-Diagnostics-" stamp ".zip"
        foreground := "unknown"
    try foreground := WinGetProcessName("A")
    caps := Buffer(20, 0)
    capsText := "unavailable"
    if (XInputGetCapabilities(0, &caps) = 0) {
        capsText := "type=" NumGet(caps, 0, "UChar")
            . " subtype=" NumGet(caps, 1, "UChar")
            . " buttonmask=0x" Format("{:04X}", NumGet(caps, 4, "UShort"))
    }
    displayScale := GetPrimaryDisplayScale()
    displayScaleText := IsObject(displayScale)
        ? displayScale["percent"] "%"
        : "unavailable"
    hdr := GetPrimaryHdrState()
    hdrText := !IsObject(hdr)
        ? "unavailable"
        : (!hdr["supported"] ? "unsupported" : (hdr["enabled"] ? "on" : "off"))
    info := "AppVersion=" AppVersion "`r`n"
        . "Generated=" FormatTime(, "yyyy-MM-dd HH:mm:ss") "`r`n"
        . "OSVersion=" A_OSVersion "`r`n"
        . "Is64BitOS=" (A_Is64bitOS ? "true" : "false") "`r`n"
        . "Compiled=" (A_IsCompiled ? "true" : "false") "`r`n"
        . "Elevated=" (A_IsAdmin ? "true" : "false") "`r`n"
        . "ScreenDPI=" A_ScreenDPI " (" Round(A_ScreenDPI / 96.0 * 100) "%)`r`n"
        . "PrimaryDisplayScale=" displayScaleText "`r`n"
        . "PrimaryDisplayHDR=" hdrText "`r`n"
        . "Screen=" A_ScreenWidth "x" A_ScreenHeight "`r`n"
        . "ScriptPath=" A_ScriptFullPath "`r`n"
        . "SettingsPath=" IniPath "`r`n"
        . "BackendSetting=" ControllerBackend "`r`n"
        . "BackendActive=" ActiveInputBackend "`r`n"
        . "XInputSlot=" ActiveControllerIndex "`r`n"
        . "XInputSlot0Caps=" capsText "`r`n"
        . "RawInputRegistered=" (RawInputProbeActive ? "true" : "false") "`r`n"
        . "RawInputDevice=0x" Format("{:X}", RawInputDevice) "`r`n"
        . "RawInputReceiving=" (RawInputLastReportTick ? "true" : "false") "`r`n"
        . "GameInputReady=" (GameInputReady ? "true" : "false") "`r`n"
        . "GameInputFailed=" (GameInputFailed ? "true" : "false") "`r`n"
        . "Foreground=" foreground "`r`n"
        . "AnyFSERunning=" (ProcessExist("AnyFSE.exe") ? "true" : "false") "`r`n"
        . "SteamRunning=" (ProcessExist("steam.exe") ? "true" : "false") "`r`n"

    files := Map()
    files["Environment.txt"] := info
    if FileExist(IniPath)
        files["SteamShell-XFE-sanitized.ini"] := FileRead(IniPath)
    if FileExist(LogPath)
        files["SteamShell-XFE-log-tail.txt"] := GetLastLines(FileRead(LogPath), 2000)

    failureReason := ""
    zipPath := ExportDiagnosticArchive("SteamShell-XFE", files, &failureReason)
    if (zipPath = "") {
        ShowNotification("Diagnostics export failed: " failureReason, "Warning")
        return
    }
    ShowNotification("Diagnostics saved to the desktop")
    try Run('explorer.exe /select,"' zipPath '"')
}

; Seam for SteamShell-Shared.ahk: this companion's own checks. The window, the
; list, the report text, Copy and Refresh all live in the shared harness now.
;
; These were flat "PASS - text" strings assembled into a read-only edit box, so
; there was no way to copy the report, no way to refresh it without reopening,
; and the export bundle rebuilt the same text separately. Splitting status from
; name from detail is what the shared list needs, and it is the same shape the
; shell has always used.
ProductHealthResults() {
    global AppVersion, IniPath, LogPath, ControllerIndex, ActiveControllerIndex, RtssPath
    global EnableRTSSIntegration, RtssUseDllIntegration
    global RtssElevatedFrameCapWrites, ElevatedHelperAvailable, ElevatedHelperPid
    global ElevatedHelperLastError, ElevatedHelperPath
    global ControllerBackend, ActiveInputBackend
    global GameInputReady, GameInputFailed
    global RawInputProbeActive, RawInputLastReportTick
    results := []

    HealthResult(results,
        FileExist(IniPath) ? "PASS" : "FAIL", "Settings file",
        FileExist(IniPath) ? IniPath : IniPath " is missing.")

    AddInstallationRecordHealthRow(results, A_ScriptDir, A_ScriptDir, "Portable")

    ; Controller, Input backend and RawInput are the same three rows in both
    ; products and are built in SteamShell-Shared.ahk. Detection stays here
    ; because ControllerReadState is the part that still differs -- this tree
    ; tries GameInput in between, and the shell deliberately does not offer it.
    controller := Buffer(16, 0)
    SharedControllerHealthRows(results, ControllerReadState(&controller))
    ; The companion's own fourth row. GameInput exists in this product only, so
    ; the shared builder does not describe it.
    HealthResult(results,
        GameInputReady ? "PASS" : (GameInputFailed ? "WARN" : "INFO"),
        "GameInput",
        GameInputReady
            ? "Initialised."
            : (GameInputFailed ? "Unavailable; fallback in use." : "Not requested."))

    if !EnableRTSSIntegration {
        HealthResult(results, "INFO", "RTSS", "Integration is disabled.")
    } else if (ResolveRtssExecutablePath() = "") {
        HealthResult(results, "WARN", "RTSS", "Executable not found.")
    } else if !ProcessExist("RTSS.exe") {
        HealthResult(results, "INFO", "RTSS", "Installed but not running.")
    } else if !RtssUseDllIntegration {
        HealthResult(results, "INFO", "RTSS",
            "Running. DLL integration disabled, shortcut mode active.")
    } else {
        rtssState := GetRtssGlobalState()
        if IsObject(rtssState) {
            HealthResult(results, "PASS", "RTSS",
                "State readable. Overlay " (rtssState["overlay"] ? "on" : "off")
                . ", limiter " (rtssState["limiter"] ? "on" : "off") ".")
        } else {
            HealthResult(results, "WARN", "RTSS",
                "Running but global state is unavailable; shortcut fallback active.")
        }
    }

    ; Two separate rows, because "you did not turn it on" and "you turned it on
    ; and it is not running" are different situations with different remedies,
    ; and the second is the whole reason a frame cap row can still report itself
    ; read-only after opting in.
    if !RtssElevatedFrameCapWrites {
        HealthResult(results, "INFO", "Elevated RTSS helper",
            "Disabled (default). The frame cap is read-only where RTSS needs "
            . "administrator rights.")
    } else if A_IsAdmin {
        HealthResult(results, "INFO", "Elevated RTSS helper",
            "The companion is elevated, so RTSS profile writes already work "
            . "without a helper.")
    } else if (ElevatedHelperAvailable && ElevatedHelperPid
        && VerifyElevatedHelperProcess(ElevatedHelperPid, &helperVerifyError)) {
        HealthResult(results, "PASS", "Elevated RTSS helper",
            "Running as PID " ElevatedHelperPid ".")
    } else {
        HealthResult(results, "WARN", "Elevated RTSS helper",
            "Enabled but unavailable: " ElevatedHelperLastError)
    }

    ; Reported whenever the option is on, whether or not the process started:
    ; "protected" is what decides whether it may be launched at all, and a
    ; failure here is the most likely reason the row above says WARN.
    checkedPath := ElevatedHelperPath != ""
        ? ElevatedHelperPath : XfeElevatedHelperPath()
    if !RtssElevatedFrameCapWrites {
        HealthResult(results, "INFO", "Elevated helper protection",
            "Not checked; the helper is disabled.")
    } else if ElevatedHelperLocationIsProtected(checkedPath, &helperProtectionError) {
        HealthResult(results, "PASS", "Elevated helper protection",
            checkedPath " is administrator-owned and readable.")
    } else {
        HealthResult(results, "WARN", "Elevated helper protection",
            helperProtectionError)
    }

    displayScale := GetPrimaryDisplayScale()
    HealthResult(results, IsObject(displayScale) ? "PASS" : "WARN", "Display scale",
        IsObject(displayScale)
            ? "Primary display at " displayScale["percent"] "%."
            : "Primary display scale control unavailable.")
    hdr := GetPrimaryHdrState()
    if !IsObject(hdr) {
        HealthResult(results, "WARN", "Display HDR", "State unavailable.")
    } else if !hdr["supported"] {
        HealthResult(results, "INFO", "Display HDR",
            "The primary display does not support HDR.")
    } else {
        HealthResult(results, "PASS", "Display HDR",
            "Primary display HDR is " (hdr["enabled"] ? "on" : "off") ".")
    }

    HealthResult(results, ProcessExist("AnyFSE.exe") ? "PASS" : "INFO", "AnyFSE",
        ProcessExist("AnyFSE.exe") ? "Process detected." : "Process not detected.")
    HealthResult(results, ProcessExist("steam.exe") ? "PASS" : "INFO", "Steam",
        ProcessExist("steam.exe") ? "Process detected." : "Not running.")

    HealthResult(results, "INFO", "Runtime",
        (A_PtrSize = 8 ? "64-bit" : "32-bit")
        . ". Administrator: " (A_IsAdmin ? "Yes" : "No, which is the recommendation")
        . ". Log: " LogPath)
    HealthResult(results, "INFO", "Scope",
        "The companion does not modify the Winlogon Shell value and does not "
        . "manage Explorer or the taskbar.")
    return results
}

; Seams for the shared health harness.
ProductVersionText() {
    global AppVersion
    return AppVersion
}

ProductCenterGui(guiObj) {
    ; Centre at whatever size the window already is. This used to pass 900x560 --
    ; the Settings window's size -- for EVERY window SteamShell-Shared.ahk centres
    ; through this seam, so the Quick Menu Layout dialog and the health check were
    ; stretched to Settings' proportions with their content stranded in a corner.
    ;
    ; Moved, never resized, which is also why there is no DPI arithmetic here: the
    ; window keeps the size AutoHotkey laid it out at.
    try {
        WinGetPos(, , &width, &height, "ahk_id " guiObj.Hwnd)
        index := ClampInt(GetMonitorIndexForWindow(WinExist("A")), 1, MonitorGetCount())
        MonitorGetWorkArea(index, &left, &top, &right, &bottom)
        WinMove(Round(left + (((right - left) - width) / 2)),
            Round(top + (((bottom - top) - height) / 2)), , ,
            "ahk_id " guiObj.Hwnd)
    }
}

PollController() {
    global EnableControllerMouseMode, EnablePersistentMouseMode, ControllerIndex, ControllerDeadzone
    global ActiveControllerIndex, ActiveInputBackend
    global ControllerMouseSpeed, ControllerMouseFastMultiplier
    global ControllerScrollIntervalMs, ControllerScrollStep, ControllerChordHoldMs
    global QuickMenuVisible, EnableQuickMenu, QuickMenuChordHoldMs, MouseHidden
    global SettingsVisible, SettingsDialogActive, LearnActive
    global CompanionDisabled, ControllerNeedsFreshBaseline
    global EnableControllerDiagnostics
    global ControllerPollIntervalMs

    static state := Buffer(16, 0)
    static previousButtons := 0
    static previousViewDown := false
    ; View doubles as the mapping modifier and as a Steam button. Its own action
    ; is resolved on RELEASE, and only when nothing else was touched during the
    ; hold, so using it as a modifier never fires a Steam shortcut.
    static viewWasDown := false
    static viewPressTick := 0
    static viewUsedAsModifier := false
    static quickChordSince := 0
    static quickChordFired := false
    static lastScroll := 0
    static downTick := Map()
    static longFired := Map()
    static triggerDown := Map("LT", false, "RT", false)
    static settingsLtDown := false
    static settingsRtDown := false
    static diagnosticLtDown := false
    static diagnosticRtDown := false
    static inPoll := false
    static wasDisabled := false
    static buttonDefinitions := [
        ["A", 0x1000], ["B", 0x2000], ["X", 0x4000], ["Y", 0x8000],
        ["LB", 0x0100], ["RB", 0x0200], ["Start", 0x0010],
        ["L3", 0x0040], ["R3", 0x0080]
    ]

    if inPoll
        return
    ; Before the reentrancy guard: this is a wall-clock check, not controller
    ; work, and it must still run on the tick where a resume is first noticed.
    ControllerResumeGapCheck(ControllerPollIntervalMs / 1000)
    inPoll := true
    try {
        ControllerPrimeHoldTables(downTick, longFired, buttonDefinitions)

        if CompanionDisabled {
            ResetControllerEdgeState(downTick, longFired, triggerDown,
                buttonDefinitions)
            previousButtons := 0
            previousViewDown := false
            viewWasDown := false
            viewPressTick := 0
            viewUsedAsModifier := false
            quickChordSince := 0
            quickChordFired := false
            settingsLtDown := false
            settingsRtDown := false
            diagnosticLtDown := false
            diagnosticRtDown := false
            wasDisabled := true
            return
        }
        ; The learning wizard owns the controller completely.
        ;
        ; It only diverts the RawInput path, so without this the poll loop keeps
        ; reading the same pad through XInput and firing its normal mappings at
        ; every prompt. Measured: pressing B ran Builtin:Esc and CLOSED the
        ; wizard. A is Enter and activates whichever button has focus, X opens the
        ; touch keyboard, Y opens Game Bar, Start opens the Start menu, and
        ; L3 + R3 throws the Quick Menu on top. Nearly every prompt in the wizard
        ; had a destructive side effect.
        ;
        ; Suppressing the pipeline is also why button and D-pad steps must be able
        ; to time out on their own: with the controller inert, there is no way to
        ; press Skip from the couch.
        ;
        ; Ahead of the fresh-baseline block below, not after it. The baseline
        ; block returns too, so from behind it the wizard's request for a baseline
        ; would be granted and cleared on the very next poll -- leaving the
        ; wizard's LAST poll, not its first one after closing, as the edge-free
        ; sample. In front of it the request stands untouched for as long as the
        ; wizard is open and is spent on the first poll after it closes, which is
        ; the poll that needs it.
        if LearnActive {
            ; Not previousButtons := 0. That makes the next poll compute pressed
            ; as buttons & ~0, so every button still held when the wizard closes
            ; arrives as a press edge and fires its mapping -- the misfire this
            ; guard exists to prevent, and the common case rather than the corner,
            ; because the wizard is dismissed by pressing something.
            ControllerNeedsFreshBaseline := true
            previousViewDown := false
            viewWasDown := false
            quickChordSince := 0
            quickChordFired := false
            ResetControllerEdgeState(downTick, longFired, triggerDown, buttonDefinitions)
            return
        }

        if (wasDisabled || ControllerNeedsFreshBaseline) {
            ; Establish a fresh baseline without firing edges for buttons that
            ; happen to be held at the instant the companion is enabled.
            if ControllerReadState(&state) {
                ResetControllerEdgeState(downTick, longFired, triggerDown,
                    buttonDefinitions)
                ; Through the shared decoder like every other read of this
                ; buffer. This was the third place the XINPUT_GAMEPAD byte
                ; layout was written out, and a partial one -- offsets 4, 6 and
                ; 7 only -- which is the shape that goes wrong last and is
                ; noticed least.
                ControllerDecodeState(state, &baseButtons, &baseLt, &baseRt,
                    &baseLx, &baseLy, &baseRx, &baseRy)
                previousButtons := baseButtons
                previousViewDown := (previousButtons & 0x0020) != 0
                viewWasDown := previousViewDown
                ; The triggers are sampled here for the same reason the buttons
                ; are. Left alone they kept their pre-interruption value while
                ; everything around them was reset, so a trigger held across the
                ; interruption read as a rising edge afterwards and changed the
                ; Settings category on its own.
                settingsLtDown := baseLt > 30
                settingsRtDown := baseRt > 30
                wasDisabled := false
                ControllerNeedsFreshBaseline := false
            }
            return
        }

        if !ControllerReadState(&state) {
            previousButtons := 0
            previousViewDown := false
            viewWasDown := false
            quickChordSince := 0
            quickChordFired := false
            ResetControllerEdgeState(downTick, longFired, triggerDown, buttonDefinitions)
            return
        }

        now := A_TickCount
        ControllerDecodeState(state, &buttons, &lt, &rt, &lx, &ly, &rx, &ry)
        ControllerButtonEdges(buttons, &previousButtons, &pressed, &released)
        currentDiagnosticLtDown := lt > 30
        currentDiagnosticRtDown := rt > 30
        ; One line per button edge and per trigger crossing. That is the right
        ; granularity for diagnosing a pad, and far too much for an ordinary
        ; session, so it belongs behind the diagnostic flag that already exists
        ; for exactly this -- the timer-driven ControllerDiagnosticTick is gated
        ; the same way. Left ungated it was the single largest writer to a log
        ; that, until now, never rotated.
        if (EnableControllerDiagnostics
            && (pressed || released
                || currentDiagnosticLtDown != diagnosticLtDown
                || currentDiagnosticRtDown != diagnosticRtDown)) {
            LogLine(
                "Controller input [" ActiveInputBackend "]"
                . (ActiveInputBackend = "xinput" ? " slot " ActiveControllerIndex : "")
                . ": buttons=0x" Format("{:04X}", buttons)
                . ", LT=" lt ", RT=" rt ".")
        }
        diagnosticLtDown := currentDiagnosticLtDown
        diagnosticRtDown := currentDiagnosticRtDown

        ControllerApplyStickDeadzone(&lx, &ly, &rx, &ry, ControllerDeadzone)

        ; Settings chord: LB + RB + L3 + R3, held.
        ;
        ; The triggers are deliberately NOT part of this test. On the RawInput
        ; backend they share one combined axis and cancel each other out, so
        ; "LT and RT both down" is unreadable. Pressing the old six-button
        ; combination still satisfies this one, since the triggers are ignored
        ; rather than forbidden. The hold requirement compensates for the looser
        ; chord so it cannot fire accidentally during play.
        static settingsChordSince := 0
        static settingsChordFired := false
        settingsComboDown := (buttons & 0x0100) && (buttons & 0x0200)
            && (buttons & 0x0040) && (buttons & 0x0080)
        if ControllerChordFired(settingsComboDown, QuickMenuChordHoldMs, now,
            &settingsChordSince, &settingsChordFired) {
            LogLine("Controller Settings chord detected [" ActiveInputBackend "].")
            ShowSettings()
            return
        }

        ; Quick Menu: hold L3 + R3 with no conflicting chord buttons.
        quickChordDown := EnableQuickMenu
            && (buttons & 0x0040) && (buttons & 0x0080)
            && !(buttons & 0x0020) && !(buttons & 0x0010)
            && !(buttons & 0x0100) && !(buttons & 0x0200)
            && lt <= 30 && rt <= 30
        if ControllerChordFired(quickChordDown, QuickMenuChordHoldMs, now,
            &quickChordSince, &quickChordFired) {
            LogLine("Controller Quick Menu chord detected on slot "
                ActiveControllerIndex ".")
            ToggleQuickMenu()
            return
        }

        if QuickMenuVisible {
            ; Forget any in-progress View hold: the menu opening mid-hold must
            ; not fire a Steam shortcut when the button is eventually released.
            viewWasDown := false
            QuickMenuHandleController(pressed, lx, ly, buttons)
            return
        }

        settingsSurfaceActive := ControllerSettingsSurfaceActive()
        settingsMainActive := SettingsPrimaryActive()
        ; Every Settings/editor surface owns right-stick pointer and RB click
        ; without requiring Back or enabling persistent Mouse Mode.
        if settingsSurfaceActive {
            if MouseHidden {
                SystemCursor("Show")
                MouseHidden := false
            }
            ; No fast modifier here: the triggers change Settings category, so
            ; RT is not free to mean "move faster" on this surface.
            ApplyControllerMouseMove(rx, ry, ControllerMouseSpeed)
            if (ly != 0 && now - lastScroll >= ControllerScrollIntervalMs) {
                lastScroll := now
                ; One notch per tick, not ControllerScrollStep: a Settings list
                ; is short and the multiplied step overshoots it.
                ApplyControllerMouseScroll(ly, 1)
            }
            ; Clicking and basic navigation must keep working while a dialog is
            ; up: a file picker or message box is exactly when the controller is
            ; the only pointer available. Previously every one of these was
            ; gated off, so the pointer moved but nothing could be selected.
            if (pressed & 0x0200)
                try Click("Left")
            if (pressed & 0x1000)
                try SendInput("{Enter}")
            if (pressed & 0x2000)
                try SendInput("{Esc}")
            if (pressed & 0x4000)
                OpenTouchKeyboard()
            if (pressed & 0x0001)
                try SendInput("{Up}")
            if (pressed & 0x0002)
                try SendInput("{Down}")
            if (pressed & 0x0004)
                try SendInput("{Left}")
            if (pressed & 0x0008)
                try SendInput("{Right}")
            ; These act on the Settings window itself, so they stay disabled
            ; while a dialog owns input -- switching category or saving behind an
            ; open picker would operate on a window the user cannot see.
            if (settingsMainActive && !SettingsDialogActive) {
                currentLtDown := lt > 30
                currentRtDown := rt > 30
                if (currentLtDown && !settingsLtDown && !currentRtDown)
                    SettingsChangeCategory(-1)
                if (currentRtDown && !settingsRtDown && !currentLtDown)
                    SettingsChangeCategory(1)
                if (pressed & 0x8000)
                    SaveSettings()
                settingsLtDown := currentLtDown
                settingsRtDown := currentRtDown
            } else {
                settingsLtDown := false
                settingsRtDown := false
            }
            previousViewDown := false
            viewWasDown := false
            ResetControllerEdgeState(downTick, longFired, triggerDown, buttonDefinitions)
            return
        }
        settingsLtDown := false
        settingsRtDown := false

        ; View button Steam actions, tracked before the controller-mouse gate so
        ; they work whether or not mouse mode is enabled.
        viewDown := ControllerTrackViewButton(buttons, lt, rt, lx, ly, rx, ry, now,
            &viewWasDown, &viewPressTick, &viewUsedAsModifier)

        if !EnableControllerMouseMode {
            previousViewDown := false
            viewWasDown := false
            ResetControllerEdgeState(downTick, longFired, triggerDown, buttonDefinitions)
            return
        }

        ; Automatic mouse mode is expressed as a virtual View/Back hold, so every
        ; branch below is reached identically whether the user is holding the
        ; button or the foreground application qualifies on its own.
        ;
        ; Deliberately evaluated AFTER the Quick Menu and Settings chords above,
        ; which test the real button state. That is what keeps a misconfigured
        ; list recoverable: exclude the wrong thing and the controller becomes a
        ; mouse where it should not be, but the chords still open the Quick Menu
        ; and Settings, so the list can be corrected without a keyboard.
        autoMouse := AutoMouseModeActive()
        if (autoMouse && MouseHidden) {
            ; Moving a pointer that cannot be seen is not a usable mode.
            try SystemCursor("Show")
            MouseHidden := false
        }
        mappingActive := viewDown || autoMouse
        if !mappingActive {
            previousViewDown := false
            viewWasDown := false
            ResetControllerEdgeState(downTick, longFired, triggerDown, buttonDefinitions)
            return
        }

        ; Everything from here is ControllerPollFrame in SteamShell-Shared.ahk:
        ; adopt held buttons, cursor, wheel, Short/Long for buttons and
        ; triggers, D-pad, Guide. The head above it is this product's own.
        ;
        ; Two behaviours change, both toward the shell's more careful version:
        ; a button already being timed keeps its clock when the modifier goes
        ; down rather than restarting it, and an adopted trigger has its
        ; long-fired flag cleared so a Long can fire again.
        ControllerPollFrame(buttons, pressed, released, lt, rt, rx, ry, ly, now,
            buttonDefinitions, downTick, longFired, triggerDown,
            &previousViewDown, &lastScroll)
    } finally {
        inPoll := false
    }
}

; ==============================================================================
; Startup
; ==============================================================================
OnExit(OnCompanionExit)

OnError(HandleUncaughtError)
; Armed once and never disarmed -- deliberately not beside the poll timer, which
; is cancelled whenever the companion is disabled.
SetTimer(ControllerMouseSafetyTick, 5000)
EnsureSettingsFile()
; After the file is known to exist and before anything reads it, matching
; standalone's order: a sweep is only meaningful once the path is settled, and a
; staging file left by a previous run must not still be sitting there when this
; run stages its own.
SweepAbandonedSettingsUpdates()
LoadSettings()
CheckXfeInstallationRecord()
; Echo the settings file actually in use and the values that came out of it.
; The INI is resolved beside the executable, so editing a copy in another folder
; silently has no effect -- exactly the failure that made a disabled RawInput
; probe look like a probe that found nothing.
LogLine("Settings file: " IniPath)
LogLine("Resolved: Backend=" ControllerBackend
    . ", DiagnosticLogging=" (EnableControllerDiagnostics ? "true" : "false")
    . ", RawInputProbe=" (EnableRawInputProbe ? "true" : "false")
    . ", HeartbeatSeconds=" HeartbeatSeconds ".")
ApplyRuntimeTimers()
; Recorded before anything can ask whether the helper process matches it.
XfeInitializeInteractiveIdentity()
; No-op unless the user opted in. When they have, this is where the UAC prompt
; appears -- once, at startup, and never again for the session.
SyncElevatedRtssHelperWithSettings()
LogLine("Started SteamShell XFE Companion " AppVersion
    . " (PID " ScriptPid ", " (A_IsAdmin ? "administrator" : "standard user") ").")
if EnableMouseParkOnBoot
    SetTimer(ParkCursor, -1000)
if EnableStartupPrograms
    SetTimer(RunStartupPrograms, -StartupProgramDelayMs)

; Armed after the startup entries that usually bring RTSS up. The tick polls for
; RTSS rather than launching it, and stops on the first successful restore or at
; its own deadline. Shared with standalone; see SteamShell-Shared.ahk.
SetTimer(RestoreRtssFrameLimitTick, 2000)

Hotkey("^!+q", ToggleQuickMenu)
Hotkey("^!+s", ShowSettings)
; P matches SteamShell 1.5's Control Panel shortcut. The companion has no
; separate Control Panel, so the equivalent surface is Settings, and keeping the
; muscle memory is worth more than reserving the key.
Hotkey("^!+p", ShowSettings)
Hotkey("^!+r", ReloadSettings)
; Recovery path when controller input is dead and the Quick Menu therefore cannot
; be opened with the controller to fix it.
Hotkey("^!+i", RearmControllerInput)
; Escape hatch for a bad learned profile: it takes the pointer away, so removing
; it must not require the pointer.
Hotkey("^!+d", DeleteControllerProfileForActiveDevice)
Hotkey("^!+x", ExitCompanion)
RegisterQuickMenuKeys()
InitializeTrayMenu()

; Seam for SteamShell-Shared.ahk. The scored answer first; the foreground
; observation is retained below it for the case where nothing clears the score
; threshold -- a windowed game, or one whose CPU has not been sampled yet.
ProductBestGameExe() {
    ; No LastObservedGameExe fallback any more. It existed because the scorer
    ; could not see a minimized game, so a game that minimized itself scored
    ; nothing and the last foreground executable was the only answer left. The
    ; scorer sees them now, and that fallback answered from a stored name that
    ; survives the process it names -- which is how a per-game frame cap ended up
    ; written to a profile for a game that had already exited.
    ;
    ; The shell returns its best candidate here and nothing else; so does this.
    return XfeBestGameWindow()
}

; The companion keeps its settings beside its own executable, so both directories
; are A_ScriptDir. Written only when absent or wrong, so an ordinary start does
; no file writes at all.
RecordXfeInstallationPaths() {
    global IniPath
    recorded := SteamShellSetupRecord()
    if (recorded["installDir"] = "" || recorded["dataDir"] = "") {
        try {
            IniWrite(A_ScriptDir, IniPath, "Setup", "InstallDirectory")
            IniWrite(A_ScriptDir, IniPath, "Setup", "DataDirectory")
        }
    }
}

; Called after settings load. Advisory only -- see LogSteamShellSetupRecordDrift.
CheckXfeInstallationRecord() {
    LogSteamShellSetupRecordDrift(A_ScriptDir, A_ScriptDir, "Portable")
    ; ShowNotification, not a dialog. This runs during startup and the companion starts
    ; alongside Steam under Xbox FSE -- a modal here would land on top of a
    ; session the user is in the middle of entering. The Quick Menu shows it when
    ; opened, the tray tip carries it meanwhile, and Health Check has the detail.
    alert := InstallationRecordAlert(A_ScriptDir, A_ScriptDir, "Portable")
    if (alert != "")
        ShowNotification(alert, "Warning")
}

; Seam for SteamShell-Shared.ahk. ProcessExist plus clearing the stale flag;
; the shell re-verifies identity as well, which is the stronger check.
ProductElevatedHelperAlive() {
    return EnsureElevatedRtssHelperAlive()
}

; Seam for SteamShell-Shared.ahk: where this product keeps files it writes.
;
; XFE is portable and writes beside its own executable -- its INI and its log
; already do. There is no installation record to relocate this, which is the
; whole difference from the shell, where the same seam reads a global that Setup
; can move.
ProductDataDir() {
    return A_ScriptDir
}

; Seams for the shared settings scrollbar. Bounds come from SettingsLayout()
; here; the shell keeps them in two globals.
ProductSettingsScrollBar() {
    global SettingsScrollBar
    return IsObject(SettingsScrollBar) ? SettingsScrollBar : ""
}

ProductSettingsViewportHeight() {
    layout := SettingsLayout()
    return Max(1, layout["contentBottom"] - layout["contentTop"])
}

RunViaDesktopShell(filePath, arguments := "", directory := "", show := 1) {
    static VT_UI4 := 0x13
    static SWC_DESKTOP := ComValue(VT_UI4, 0x8)
    try {
        ComObject("Shell.Application").Windows.Item(SWC_DESKTOP).Document.Application
            .ShellExecute(filePath, arguments, directory, "open", show)
        return true
    } catch {
        return false
    }
}

OpenTouchKeyboard() {
    if WinExist("ahk_class IPTip_Main_Window") {
        try WinShow("ahk_class IPTip_Main_Window")
        try WinActivate("ahk_class IPTip_Main_Window")
        return
    }
    if TryInvokeTouchKeyboard()
        return
    paths := [A_ProgramFiles "\Common Files\microsoft shared\ink\TabTip.exe"]
    try {
        pf86 := EnvGet("ProgramFiles(x86)")
        if (pf86 != "")
            paths.Push(pf86 "\Common Files\microsoft shared\ink\TabTip.exe")
    }
    tabTip := ""
    for _, path in paths {
        if FileExist(path) {
            tabTip := path
            break
        }
    }
    if (tabTip = "") {
        OpenOSK()
        return
    }
    SplitPath(tabTip, , &directory)
    if !ProcessExist("TabTip.exe") {
        if !RunViaDesktopShell(tabTip, "", directory) {
            OpenOSK()
            return
        }
    }
    Sleep 250
    if !TryInvokeTouchKeyboard() {
        if !RunViaDesktopShell(tabTip, "/SeekDesktop", directory)
            OpenOSK()
    }
}

; Seam for the shared EnsureRtssRunning. No de-elevation contingency here --
; the companion never holds a token it must avoid passing on.
ProductLaunchMinimized(path, directory) {
    try {
        Run('"' path '"', directory, "Min")
        return true
    } catch {
        return false
    }
}

RecordShortcutChord() {
    global _ShortcutCap
    result := Map("ok", false, "send", "", "display", "")
    capture := Gui("+AlwaysOnTop -MinimizeBox +ToolWindow", "Record Shortcut")
    capture.SetFont("s10", "Segoe UI")
    capture.AddText("xm", "Press one shortcut chord, then choose OK.")
    capture.SetFont("s12 Bold", "Consolas")
    preview := capture.AddText("xm y+10 w420 h30", "(none)")
    capture.SetFont("s10 Norm", "Segoe UI")
    okButton := capture.AddButton("xm y+10 w90 Default", "OK")
    cancelButton := capture.AddButton("x+10 yp w90", "Cancel")
    _ShortcutCap := Map(
        "gui", capture,
        "preview", preview,
        "input", 0,
        "mainKey", "",
        "liveMods", Map("Ctrl", false, "Alt", false, "Shift", false, "Win", false),
        "snapMods", Map("Ctrl", false, "Alt", false, "Shift", false, "Win", false),
        "done", false,
        "cancelled", false
    )
    okButton.OnEvent("Click", RecordShortcutAccept)
    cancelButton.OnEvent("Click", RecordShortcutCancel)
    capture.OnEvent("Close", RecordShortcutCancel)
    capture.OnEvent("Escape", RecordShortcutCancel)
    input := InputHook()
    input.NotifyNonText := true
    input.KeyOpt("{All}", "NS")
    input.OnKeyDown := RecordShortcutKeyDown
    input.OnKeyUp := RecordShortcutKeyUp
    _ShortcutCap["input"] := input
    capture.Show("AutoSize Center")
    input.Start()
    while IsObject(_ShortcutCap) && !_ShortcutCap["done"]
        Sleep 30
    if !IsObject(_ShortcutCap)
        return result
    cancelled := _ShortcutCap["cancelled"]
    mainKey := _ShortcutCap["mainKey"]
    mods := _ShortcutCap["snapMods"]
    try _ShortcutCap["input"].Stop()
    try _ShortcutCap["gui"].Destroy()
    _ShortcutCap := ""
    if (cancelled || mainKey = "")
        return result
    shortcut := ""
    display := ""
    if mods["Ctrl"]
        shortcut .= "^", display .= "Ctrl+"
    if mods["Alt"]
        shortcut .= "!", display .= "Alt+"
    if mods["Shift"]
        shortcut .= "+", display .= "Shift+"
    if mods["Win"]
        shortcut .= "#", display .= "Win+"
    shortcut .= NormalizeKeyForSend(mainKey)
    display .= NormalizeKeyForDisplay(mainKey)
    result["ok"] := true
    result["send"] := shortcut
    result["display"] := display
    return result
}

AutoMouseModeActive() {
    global EnableAutoMouseMode, EnablePersistentMouseMode, AutoMouseExeSet, ScriptPid
    global LearnActive
    static cachedResult := false
    static cachedTick := 0
    ; All kill switches are checked ahead of the cache so tray/Settings changes
    ; take effect on the next poll rather than up to 250 ms later.
    ; A learning session owns the controller. Nothing else may act on it while
    ; the wizard is asking for one button at a time -- the pointer moving under
    ; the user, or a mapping firing from the very button being taught, is the
    ; wizard fighting itself.
    ;
    ; FIRST, ahead of the persistent-mode check: persistent mode returns true
    ; unconditionally, so anything after it is unreachable while Mouse Mode is
    ; on, which is exactly when this was reported.
    if LearnActive
        return false
    if EnablePersistentMouseMode
        return true
    if !EnableAutoMouseMode
        return false
    if (AutoMouseExeSet.Count = 0)
        return false
    if (cachedTick && A_TickCount - cachedTick < 250)
        return cachedResult
    cachedTick := A_TickCount
    cachedResult := false
    try {
        hwnd := DllCall("User32\GetForegroundWindow", "Ptr")
        if (hwnd && WinGetPID("ahk_id " hwnd) != ScriptPid) {
            foregroundExe := StrLower(WinGetProcessName("ahk_id " hwnd))
            cachedResult := AutoMouseProcessMatches(foregroundExe)
        }
    }
    return cachedResult
}
