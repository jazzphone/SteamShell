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
;@Ahk2Exe-SetVersion 1.9.9.0
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

global AppVersion := "1.9.9"
global SettingsSchemaVersion := 17
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
global AutoMouseExeListRaw := "explorer.exe"
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
global ControllerPollIntervalMs := 16
global ControllerDeadzone := 3000
global ControllerMouseSpeed := 100
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
global MouseHideDelayMs := 1000
global ParkOnStartup := true
global ParkOnGameStart := true
global ParkOnSteamReturn := true
; Which side of the screen the cursor is parked against. Right by default: on a
; TV the right edge is where a cursor that briefly reappears is least noticeable,
; and nothing in Xbox FSE puts controls there.
global ParkEdge := "right"
global ParkYPercent := 0.50
global ForegroundPollMs := 500
global EnableAudioQuickControls := true
global EnableDisplayQuickControls := true
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
global ElevatedHelperExpectedVersion := "1.9.9.4"
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
            "SettingsSchemaVersion", 16,
            "HeartbeatSeconds", 60,
            "LogRotateMaxKB", 256,
            "LogRotateBackups", 2
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
            "ChordHoldMs", 500,
            "AccentColor", "Purple",
            "AccentColorCustom", "107C10"
        ),
        "Controller", Map(
            "EnableControllerMouseMode", "true",
            "EnablePersistentMouseMode", "false",
            "AutoMouseExeList", "explorer.exe",
            "Backend", "auto",
            "DiagnosticLogging", "false",
            "RawInputProbe", "false",
            "RawInputStaleMs", 5000,
            "ControllerIndex", 0,
            "ControllerPollIntervalMs", 16,
            "ControllerDeadzone", 3000,
            "ControllerMouseSpeed", 100,
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
            "EnableGameScoreLogging", "false",
            "GameLogMode", "OFF",
            "GameLogTopN", 3,
            "GameLogIntervalMs", 3000,
            "GameLogIncludeTitles", "true"
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
        "Audio", Map(
            "EnableQuickControls", "true"
        ),
        "Display", Map(
            "EnableQuickControls", "true"
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

DefaultControllerMappings() {
    global ControllerMap, ControllerMapDisplay
    ControllerMap := Map(
        "RB.Short", "Builtin:LeftClick", "RB.Long", "Builtin:None",
        "RT.Short", "Builtin:RightClick", "RT.Long", "Builtin:None",
        "LT.Short", "Send:^+o", "LT.Long", "Send:^+f",
        "LB.Short", "Send:^!{Tab}", "LB.Long", "Builtin:TaskManager",
        "A.Short", "Builtin:Enter", "A.Long", "Builtin:None",
        "B.Short", "Builtin:Esc", "B.Long", "Builtin:AltF4",
        "X.Short", "Builtin:TabTip", "X.Long", "Builtin:OSK",
        "Y.Short", "Builtin:WinG", "Y.Long", "Builtin:None",
        "Start.Short", "Builtin:StartMenu", "Start.Long", "Builtin:Explorer",
        "L3.Short", "Builtin:None", "L3.Long", "Builtin:None",
        "R3.Short", "Builtin:None", "R3.Long", "Builtin:None"
    )
    ControllerMapDisplay := Map(
        "LT.Short", "Ctrl+Shift+O",
        "LT.Long", "Ctrl+Shift+F",
        "LB.Short", "Ctrl+Alt+Tab"
    )
}

EnsureSettingsFile() {
    global IniPath, SettingsSchemaVersion, ControllerMap, ControllerMapDisplay
    RetireStartupSplashSettings()
    RetireDesktopAutoMouseSettings()
    MigrateRtssPresetFrameCap()
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

    DefaultControllerMappings()
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
        ["Cursor", "ParkOnStartup", "Features", "EnableMouseParkOnBoot"],
        ["Cursor", "HideDelayMs", "Timing", "MouseHideDelay"],
        ["Cursor", "ParkEdge", "MousePark", "MouseParkEdge"],
        ["Cursor", "ParkYPercent", "MousePark", "MouseParkYPercent"]]
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
    global HeartbeatSeconds, EnableQuickMenu, EnableGameDetectionMenu, QuickMenuChordHoldMs
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
    global EnableAutoHideCursor, MouseHideDelayMs, ParkOnStartup
    global ParkOnGameStart, ParkOnSteamReturn, ParkEdge, ParkYPercent
    global ForegroundPollMs
    global EnableAudioQuickControls, EnableDisplayQuickControls
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
    LogRotateMaxKB := ReadInt("Companion", "LogRotateMaxKB", 256, 32, 8192)
    LogRotateBackups := ReadInt("Companion", "LogRotateBackups", 2, 0, 10)
    EnableQuickMenu := ReadBool("QuickMenu", "Enable", true)
    EnableGameDetectionMenu := ReadBool("QuickMenu", "ShowGameDetection", true)
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
    AutoMouseExeListRaw := ReadText("Controller", "AutoMouseExeList", "explorer.exe")
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
    ControllerPollIntervalMs := ReadInt("Controller", "ControllerPollIntervalMs", 16, 8, 100)
    ControllerDeadzone := ReadInt("Controller", "ControllerDeadzone", 3000, 1000, 16000)
    ControllerMouseSpeed := ReadInt("Controller", "ControllerMouseSpeed", 100, 10, 300)
    ControllerMouseFastMultiplier := ReadNumber("Controller", "ControllerMouseFastMultiplier", 2.5, 1, 6)
    ControllerScrollIntervalMs := ReadInt("Controller", "ControllerScrollIntervalMs", 80, 20, 500)
    ControllerScrollStep := ReadInt("Controller", "ControllerScrollStep", 1, 1, 10)
    ControllerChordHoldMs := ReadInt("Controller", "ControllerChordHoldMs", 500, 200, 3000)
    SteamMenuShortcut := ReadText("Steam", "MenuShortcut", "^1")
    SteamQuickAccessShortcut := ReadText("Steam", "QuickAccessShortcut", "^2")
    SteamOverlayShortcut := ReadText("Steam", "OverlayShortcut", "+{Tab}")
    EnableViewSteamActions := ReadBool("Steam", "EnableViewButtonActions", true)
    EnableViewTapAction := ReadBool("Steam", "EnableViewTapAction", true)
    EnableViewHoldAction := ReadBool("Steam", "EnableViewHoldAction", true)
    ViewHoldMs := ReadInt("Steam", "ViewHoldMs", 500, 200, 5000)
    ViewHoldInGameMs := ReadInt("Steam", "ViewHoldInGameMs", 1000, 200, 5000)
    EnableStartupPrograms := ReadBool("StartupPrograms", "Enable", true)
    StartupProgramDelayMs := ReadInt("StartupPrograms", "DelayMs", 2000, 0, 120000)
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
    EnableGameScoreLogging := ReadBool("Logging", "EnableGameScoreLogging", false)
    GameLogMode := ReadText("Logging", "GameLogMode", "OFF")
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
    MouseHideDelayMs := ReadInt(MovedSettingSection("Timing", "Cursor", "MouseHideDelay"), "MouseHideDelay", 1000, 250, 10000)
    ParkOnStartup := ReadBool(MovedSettingSection("Features", "Cursor", "EnableMouseParkOnBoot"), "EnableMouseParkOnBoot", true)
    ParkOnGameStart := ReadBool("Cursor", "ParkOnGameStart", true)
    ParkOnSteamReturn := ReadBool("Cursor", "ParkOnSteamReturn", true)
    ParkEdge := StrLower(Trim(ReadText(MovedSettingSection("MousePark", "Cursor", "MouseParkEdge"), "MouseParkEdge", "right"))) = "left"
        ? "left" : "right"
    ParkYPercent := ReadNumber(MovedSettingSection("MousePark", "Cursor", "MouseParkYPercent"), "MouseParkYPercent", 0.50, 0.05, 0.95)
    ForegroundPollMs := ReadInt("Cursor", "ForegroundPollMs", 500, 250, 5000)
    EnableAudioQuickControls := ReadBool("Audio", "EnableQuickControls", true)
    EnableDisplayQuickControls := ReadBool("Display", "EnableQuickControls", true)
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
    global IniPath, ControllerMap, ControllerMapDisplay
    DefaultControllerMappings()
    keys := [
        "A.Short", "A.Long", "B.Short", "B.Long", "X.Short", "X.Long",
        "Y.Short", "Y.Long", "LB.Short", "LB.Long", "RB.Short", "RB.Long",
        "LT.Short", "LT.Long", "RT.Short", "RT.Long", "Start.Short",
        "Start.Long", "L3.Short", "L3.Long", "R3.Short", "R3.Long"
    ]
    for key in keys {
        value := ""
        try value := IniRead(IniPath, "ControllerMap", key, "")
        if (value = "")
            continue
        if (SubStr(value, 1, 5) != "Send:" && SubStr(value, 1, 8) != "Builtin:")
            value := "Send:" value
        ControllerMap[key] := value
        if (SubStr(value, 1, 5) = "Send:") {
            display := ""
            try display := IniRead(IniPath, "ControllerMap", key ".Display", "")
            ControllerMapDisplay[key] := display != "" ? display : SendToPretty(SubStr(value, 6))
        }
    }
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

TrayOpenQuickMenu(*) {
    global CompanionDisabled, QuickMenuVisible, QuickMenuGui
    if CompanionDisabled
        return
    if QuickMenuVisible {
        try QuickMenuGui.Show()
        try ForceForegroundWindow(QuickMenuGui.Hwnd)
        return
    }
    ShowQuickMenu()
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
    SetStatus("Settings reloaded", "Info")
}

LogLine(message, level := "Info") {
    global LogPath
    line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " message "`r`n"
    ; StrLen undercounts multi-byte UTF-8, which is fine: the estimate only has
    ; to be close enough to decide when to measure for real.
    RotateLogIfNeeded(StrLen(line))
    try FileAppend(line, LogPath, "UTF-8")
}

; Alias for SharedNotify, which holds the implementation. Kept so this tree's
; call sites read naturally.
SetStatus(message, level := "Info") {
    SharedNotify(message, level)
}

Heartbeat() {
    global AppVersion, HeartbeatSeconds, LastHeartbeatStamp
    now := A_Now
    if (LastHeartbeatStamp != "") {
        elapsed := 0
        try elapsed := DateDiff(now, LastHeartbeatStamp, "Seconds")
        ; A heartbeat that arrives far later than it was scheduled for means the
        ; machine was asleep in between.
        ;
        ; This is the resume detector that depends on nothing being delivered to
        ; us. WM_POWERBROADCAST is handled as well, but it is not reliably sent
        ; under modern standby -- which is the state a ROG Ally actually sleeps
        ; into, so the broadcast cannot be the only trigger.
        if (elapsed > HeartbeatSeconds * 2 + 30) {
            LogLine("Power: heartbeat gap of " elapsed "s (expected about "
                . HeartbeatSeconds "s). Treating this as a resume and re-arming "
                . "controller input.")
            RawInputResetDeviceLock("resume inferred from heartbeat gap")
            SetTimer(RawInputReregister, -1000)
        }
    }
    LastHeartbeatStamp := now
    LogLine("Heartbeat: XFE companion " AppVersion " is responsive.")
}

; Forces controller input to be re-acquired: RawInput forgets its device handle
; and re-registers, and XInput re-resolves its slot on the next poll.
;
; Exposed manually as well as automatically because it is the fastest way to
; confirm what a post-sleep failure actually was. If this restores input, the
; problem is the stale device handle or the registration -- not the backend.
RearmControllerInput(*) {
    global ActiveControllerIndex
    LogLine("Controller: manual re-arm requested.")
    RawInputResetDeviceLock("manual re-arm")
    ; -1 makes XInputResolveController rescan all four slots rather than trusting
    ; the slot it last succeeded on.
    ActiveControllerIndex := -1
    RawInputReregister()
    SetStatus("Controller input re-armed")
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
    ReleaseQuickMenuPaintResources()
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

; MB_SYSTEMMODAL. Despite the name, its actual effect here is to make the message
; box topmost, which is exactly what is needed and needs no timer.
TopmostMsgBox(text, title := "", options := "") {
    return MsgBox(text, title, Trim(options " 4096"))
}

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

GetMonitorWorkAreaForPoint(x, y, &left, &top, &right, &bottom) {
    count := MonitorGetCount()
    Loop count {
        MonitorGetWorkArea(A_Index, &ml, &mt, &mr, &mb)
        if (x >= ml && x < mr && y >= mt && y < mb) {
            left := ml, top := mt, right := mr, bottom := mb
            return A_Index
        }
    }
    MonitorGetWorkArea(1, &left, &top, &right, &bottom)
    return 1
}


GetMonitorIndexForWindow(hwnd) {
    if hwnd {
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            centerX := wx + Floor(ww / 2)
            centerY := wy + Floor(wh / 2)
            count := MonitorGetCount()
            Loop count {
                MonitorGet(A_Index, &left, &top, &right, &bottom)
                if (centerX >= left && centerX < right
                    && centerY >= top && centerY < bottom)
                    return A_Index
            }
        }
    }
    MouseGetPos(&mx, &my)
    return GetMonitorWorkAreaForPoint(mx, my, &left, &top, &right, &bottom)
}

CenterGuiOnMonitorActual(guiObj, monitorIndex, width, height, noActivate := false,
        deferShow := false) {
    monitorIndex := ClampInt(monitorIndex, 1, MonitorGetCount())
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    return PositionGuiCentered(guiObj, left, top, right, bottom, width, height,
        noActivate, deferShow)
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

; Makes visible a window that PositionGuiCentered was asked to leave hidden.
;
; ShowWindow rather than Gui.Show, because Gui.Show with no coordinates
; re-auto-sizes and re-centres the window -- undoing the placement this whole
; sequence just computed.
RevealWindow(guiObj, noActivate := false) {
    static SW_SHOWNOACTIVATE := 4
    static SW_SHOW := 5
    try DllCall("ShowWindow", "Ptr", guiObj.Hwnd, "Int",
        noActivate ? SW_SHOWNOACTIVATE : SW_SHOW)
}

; Sizes and centres a window, never showing it at an intermediate position.
;
; The whole calculation happens while the window is HIDDEN on a first show. That
; is the point of the sequence: the size is measured, the position computed, then
; re-measured and corrected, and none of those intermediate states reach the
; screen. Showing the window first and correcting afterwards is what made the
; Quick Menu visibly snap into place as it opened.
;
; With deferShow, the window is left hidden and the caller reveals it with
; RevealWindow once anything else that depends on the final size is done --
; rounded corners, in the Quick Menu's case, which otherwise appear square for a
; frame. Returns true when a show was deferred.
PositionGuiCentered(guiObj, left, top, right, bottom, width, height,
        noActivate := false, deferShow := false) {
    global EnableControllerDiagnostics
    wasVisible := false
    try wasVisible := DllCall("IsWindowVisible", "Ptr", guiObj.Hwnd, "Int") != 0

    scale := 1.0
    try scale := A_ScreenDPI / 96.0
    actualWidth := width
    actualHeight := height

    if wasVisible {
        ; Already on screen, so it cannot be hidden to be measured: hiding and
        ; re-showing blinks the menu on every page change and churns activation,
        ; which is exactly what keeping the menu alive was meant to avoid.
        ;
        ; Instead the physical size is predicted -- the same multiplication
        ; Gui.Show does the RESIZE, and the move follows separately.
        ;
        ; An earlier version predicted the physical size as width * A_ScreenDPI/96
        ; and did resize and move in one SetWindowPos, to avoid a frame showing
        ; the new size at the old position. That prediction is only as good as
        ; A_ScreenDPI matching whatever AutoHotkey used when it laid the controls
        ; out, and a mismatch does not cost a wobble -- it sizes the window wrong
        ; and cuts the content off. Letting Gui.Show size it means the window and
        ; the controls inside it are always scaled by the same thing.
        guiObj.Show("NA w" width " h" height)
        try {
            WinGetPos(&resizedX, &resizedY, &resizedWidth, &resizedHeight,
                "ahk_id " guiObj.Hwnd)
            if (resizedWidth > 0 && resizedHeight > 0) {
                actualWidth := resizedWidth
                actualHeight := resizedHeight
            }
        }
        CenteredPosition(left, top, right, bottom, actualWidth, actualHeight, &x, &y)
        MoveWindowPhysical(guiObj.Hwnd, x, y)
    } else {
        ; Realise and size the window while it stays hidden.
        guiObj.Show("Hide w" width " h" height)
        try {
            WinGetPos(&measuredX, &measuredY, &measuredWidth, &measuredHeight,
                "ahk_id " guiObj.Hwnd)
            if (measuredWidth > 0)
                actualWidth := measuredWidth
            if (measuredHeight > 0)
                actualHeight := measuredHeight
        }
        ; A window measured before it is really on screen can report the LOGICAL
        ; size it was asked for rather than the physical size it will occupy. At
        ; 150% scaling a 720x518 request becomes a 1082x779 window, and centring
        ; the smaller figure pushes it down and right by half the difference.
        ; Getting back exactly what was requested is the signature of that case.
        if (scale != 1.0 && actualWidth = width && actualHeight = height) {
            actualWidth := Round(width * scale)
            actualHeight := Round(height * scale)
        }
        CenteredPosition(left, top, right, bottom, actualWidth, actualHeight, &x, &y)
        MoveWindowPhysical(guiObj.Hwnd, x, y)
    }

    ; Measure the real window and re-centre from the true size. This is what
    ; makes the result correct at any scaling; the estimate above only has to be
    ; close enough. On a first show this correction is free, because the window
    ; is still hidden.
    try {
        WinGetPos(&shownX, &shownY, &shownWidth, &shownHeight, "ahk_id " guiObj.Hwnd)
        if (shownWidth > 0 && shownHeight > 0) {
            actualWidth := shownWidth
            actualHeight := shownHeight
            CenteredPosition(left, top, right, bottom, shownWidth, shownHeight,
                &correctedX, &correctedY)
            if (Abs(shownX - correctedX) > 1 || Abs(shownY - correctedY) > 1) {
                MoveWindowPhysical(guiObj.Hwnd, correctedX, correctedY)
                x := correctedX
                y := correctedY
            }
        }
    }

    deferred := false
    if !wasVisible {
        if deferShow
            deferred := true
        else
            RevealWindow(guiObj, noActivate)
    }

    ; Report every input to the calculation and the position actually achieved.
    ; Centering has been guessed at twice; this makes a miss readable instead of
    ; something to theorise about.
    if EnableControllerDiagnostics {
        ; Measured into separate variables and copied only on success.
        ;
        ; A `&` output parameter is left UNSET when the call fails, which beats
        ; the := 0 initialisation -- so a bare `try WinGetPos(&finalX, ...)`
        ; followed by a use of finalX crashes with "this local variable has not
        ; been assigned a value" the moment the window goes away mid-call. That
        ; is exactly the 0.1.2 `actualWidth` bug, recurring under a new name
        ; because the guard against it named one variable.
        finalX := 0, finalY := 0, finalW := 0, finalH := 0
        try {
            WinGetPos(&measuredFinalX, &measuredFinalY, &measuredFinalW,
                &measuredFinalH, "ahk_id " guiObj.Hwnd)
            finalX := measuredFinalX, finalY := measuredFinalY
            finalW := measuredFinalW, finalH := measuredFinalH
        }
        LogLine("Center: work=" left "," top ".." right "," bottom
            . " requested=" width "x" height
            . " measured=" actualWidth "x" actualHeight
            . " target=" x "," y
            . " final=" finalX "," finalY " " finalW "x" finalH
            . (wasVisible ? " (resize in place)" : "")
            . (deferred ? " (show deferred)" : ""))
    }
    return deferred
}

MouseWatch() {
    global EnableAutoHideCursor, MouseHidden, LastMouseX, LastMouseY
    global LastMouseMoveTick, MouseHideDelayMs, QuickMenuVisible, SettingsVisible
    if !EnableAutoHideCursor
        return
    MouseGetPos(&mx, &my)
    if (mx != LastMouseX || my != LastMouseY) {
        LastMouseX := mx
        LastMouseY := my
        LastMouseMoveTick := A_TickCount
        if MouseHidden {
            SystemCursor("Show")
            MouseHidden := false
        }
        return
    }
    ; Settings is pointer-driven, so the cursor stays put while it is open. The
    ; Quick Menu is navigated with the D-pad, so the cursor should hide there as
    ; it does everywhere else -- moving the mouse brings it straight back.
    if SettingsVisible
        return
    if (!MouseHidden && A_TickCount - LastMouseMoveTick >= MouseHideDelayMs) {
        SystemCursor("Hide")
        MouseHidden := true
    }
}

; Puts the pointer out of the way: hard against one vertical edge, at
; ParkYPercent down it. The right edge is the default because a cursor that
; briefly reappears there is the least visible on a TV, and because Xbox FSE and
; Steam both keep their navigation on the left.
;
; The inset is 2px rather than 0: at the exact edge some surfaces read the
; pointer as having left the window entirely and drop their hover state.
ParkCursor(*) {
    global ParkEdge, ParkYPercent, LastMouseX, LastMouseY, LastMouseMoveTick
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
            targetX := ParkEdge = "left"
                ? wx + Min(INSET, Max(0, ww - 1))
                : wx + Max(0, ww - 1 - INSET)
            targetY := wy + Round(wh * ParkYPercent)
            placed := true
        }
    }
    if !placed {
        MouseGetPos(&mx, &my)
        GetMonitorWorkAreaForPoint(mx, my, &left, &top, &right, &bottom)
        targetX := ParkEdge = "left" ? left + INSET : right - 1 - INSET
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
    if IsCloakedWindow(hwnd)
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
SetActiveBackend(backend) {
    global ActiveInputBackend
    static lastLoggedBackend := ""
    static lastLogTick := 0
    static everLogged := Map()
    if (ActiveInputBackend = backend)
        return
    ActiveInputBackend := backend
    if (backend = lastLoggedBackend)
        return
    if (everLogged.Has(backend) && lastLogTick && A_TickCount - lastLogTick < 5000)
        return
    everLogged[backend] := true
    lastLoggedBackend := backend
    lastLogTick := A_TickCount
    LogLine("Controller backend is now " backend ".")
}



; ==============================================================================
; RawInput probe
; ==============================================================================
; Answers exactly one question: do controller HID reports reach this background
; process inside Xbox FSE?
;
; XInput and GameInput have been shown to report byte-identical state at every
; sample, including all-zero inside FSE, which means they share a layer and no
; choice between them can help. RawInput is a different mechanism: HID reports
; delivered as WM_INPUT messages straight from the HID stack, and RIDEV_INPUTSINK
; explicitly requests delivery while the process is NOT in the foreground.
;
; This began as a diagnostic probe. The registration and WM_INPUT handler now
; serve three consumers: optional raw-byte logging, the normal RawInput decoder,
; and the controller learner. Logging remains independently switchable.
RawInputProbeStart() {
    global EnableRawInputProbe, RawInputProbeActive, ControllerBackend
    static RIDEV_INPUTSINK := 0x00000100
    static USAGE_PAGE_GENERIC := 0x01
    static USAGE_GAMEPAD := 0x05
    static USAGE_JOYSTICK := 0x04

    if RawInputProbeActive
        return false
    ; Register whenever RawInput is either the input source or being logged.
    backend := StrLower(ControllerBackend)
    needed := EnableRawInputProbe || backend = "rawinput" || backend = "auto"
    ; Say so explicitly when not needed. Returning in silence made a setting that
    ; never reached the application look identical to a probe that ran and found
    ; nothing, which cost a full test cycle.
    if !needed {
        LogLine("RawInput: not registered (backend=" backend
            . ", probe=" (EnableRawInputProbe ? "on" : "off") ").")
        return false
    }
    hwnd := A_ScriptHwnd
    if !hwnd {
        LogLine("RawInput probe: no script window available.", "Warning")
        return false
    }

    ; Two RAWINPUTDEVICE entries, 16 bytes each on x64. Gamepad and joystick are
    ; both registered because controllers vary in which usage they report.
    devices := Buffer(32, 0)
    NumPut("UShort", USAGE_PAGE_GENERIC, devices, 0)
    NumPut("UShort", USAGE_GAMEPAD, devices, 2)
    NumPut("UInt", RIDEV_INPUTSINK, devices, 4)
    NumPut("Ptr", hwnd, devices, 8)
    NumPut("UShort", USAGE_PAGE_GENERIC, devices, 16)
    NumPut("UShort", USAGE_JOYSTICK, devices, 18)
    NumPut("UInt", RIDEV_INPUTSINK, devices, 20)
    NumPut("Ptr", hwnd, devices, 24)

    ok := false
    try ok := DllCall("RegisterRawInputDevices", "Ptr", devices, "UInt", 2,
        "UInt", 16, "Int") != 0
    if !ok {
        LogLine("RawInput probe: RegisterRawInputDevices failed (err "
            . A_LastError ").", "Warning")
        return false
    }
    OnMessage(0x00FF, RawInputProbeMessage)
    RawInputProbeActive := true
    LogLine("RawInput: registered for background gamepad/joystick reports.")
    RawInputProbeEnumerate()
    return true
}

; Forgets the locked device and clears the cached report.
;
; Called on a deliberate power transition rather than on every device change: it
; also clears RawInputLastReportTick, which the automatic backend selection reads,
; so resetting it casually would make `auto` flip to XInput mid-session.
RawInputResetDeviceLock(reason) {
    global RawInputDevice, RawInputLastReportTick, RawInputState
    if (!RawInputDevice && !RawInputLastReportTick)
        return
    LogLine("RawInput: releasing device lock 0x" Format("{:X}", RawInputDevice)
        . " (" reason "). The next matching report re-locks.")
    RawInputDevice := 0
    RawInputLastReportTick := 0
    NumPut("UInt", 0, RawInputState, 0)
    NumPut("UInt", 0, RawInputState, 4)
    NumPut("UInt", 0, RawInputState, 8)
    NumPut("UInt", 0, RawInputState, 12)
}

; Re-asserts the RawInput registration after a resume.
;
; The registration is per-window and should survive a suspend, since the window
; does. Re-asserting it is cheap and removes the possibility that it did not,
; which is the one failure mode device adoption cannot recover from: adoption
; needs a WM_INPUT to react to, and there is nothing to adopt if registration is
; gone.
RawInputReregister() {
    global RawInputProbeActive
    RawInputProbeActive := false
    if RawInputProbeStart()
        SetTimer(RawInputResumeVerify, -10000)
}

; Reports whether controller reports actually resumed.
;
; Without this, a failed recovery is silent, and silence has already cost several
; test cycles on this backend.
RawInputResumeVerify() {
    global RawInputLastReportTick, RawInputDevice, ControllerBackend
    if RawInputLastReportTick {
        LogLine("RawInput: reports resumed on device 0x"
            . Format("{:X}", RawInputDevice) ".")
        return
    }
    LogLine("RawInput: NO reports since resume after 10s. Press a button; if this"
        . " persists, RawInput did not recover and the backend is effectively "
        . (StrLower(ControllerBackend) = "rawinput" ? "dead until restart"
            : "XInput only"), "Warning")
}

; Sleep and resume.
;
; The controller is re-enumerated across a suspend and returns with a new device
; handle, so the decoder is told to forget the one it locked onto before the
; machine slept.
PowerBroadcastMessage(wParam, lParam, msg, hwnd) {
    static PBT_APMSUSPEND := 0x04
    static PBT_APMRESUMESUSPEND := 0x07
    static PBT_APMRESUMEAUTOMATIC := 0x12
    if (wParam = PBT_APMSUSPEND) {
        LogLine("Power: system suspending.")
        RawInputResetDeviceLock("system suspending")
        return true
    }
    if (wParam = PBT_APMRESUMESUSPEND || wParam = PBT_APMRESUMEAUTOMATIC) {
        LogLine("Power: resumed from sleep; re-arming controller input.")
        RawInputResetDeviceLock("system resumed")
        ; XInput re-resolves its own slot on the next poll, so only RawInput needs
        ; help here. Delayed, because the HID stack is still re-enumerating at the
        ; moment the resume notification arrives.
        SetTimer(RawInputReregister, -2500)
        return true
    }
    return true
}

; Lists what RawInput actually knows about. Registration succeeds even when no
; matching device exists, so a successful register followed by silence proves
; nothing on its own. This reports whether a HID gamepad/joystick collection
; exists at all -- Xbox pads on the XUSB driver are known not to publish one,
; which would explain silence without any filtering being involved.
RawInputProbeEnumerate() {
    static RIDI_DEVICEINFO := 0x2000000B
    static RIM_TYPEHID := 2
    static LIST_ENTRY_SIZE := 16

    count := 0
    try {
        if (DllCall("GetRawInputDeviceList", "Ptr", 0, "UInt*", &count,
            "UInt", LIST_ENTRY_SIZE, "UInt") = 0xFFFFFFFF || !count) {
            LogLine("RawInput probe: device list unavailable.", "Warning")
            return
        }
        list := Buffer(count * LIST_ENTRY_SIZE, 0)
        got := count
        if (DllCall("GetRawInputDeviceList", "Ptr", list, "UInt*", &got,
            "UInt", LIST_ENTRY_SIZE, "UInt") = 0xFFFFFFFF) {
            LogLine("RawInput probe: device list read failed.", "Warning")
            return
        }
        hidCount := 0
        Loop got {
            offset := (A_Index - 1) * LIST_ENTRY_SIZE
            hDevice := NumGet(list, offset, "Ptr")
            if (NumGet(list, offset + 8, "UInt") != RIM_TYPEHID)
                continue
            hidCount++
            info := Buffer(32, 0)
            NumPut("UInt", 32, info, 0)
            size := 32
            if (DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", RIDI_DEVICEINFO,
                "Ptr", info, "UInt*", &size, "UInt") = 0xFFFFFFFF)
                continue
            LogLine("RawInput HID: vid=0x" Format("{:04X}", NumGet(info, 8, "UInt"))
                . " pid=0x" Format("{:04X}", NumGet(info, 12, "UInt"))
                . " usagePage=0x" Format("{:02X}", NumGet(info, 20, "UShort"))
                . " usage=0x" Format("{:02X}", NumGet(info, 22, "UShort")))
        }
        LogLine("RawInput probe: " got " devices enumerated, " hidCount " of them HID."
            . (hidCount ? "" : " No HID collection exists for RawInput to deliver."))
    }
}

RawInputProbeMessage(wParam, lParam, msg, hwnd) {
    global EnableRawInputProbe, LearnActive, CompanionDisabled
    static RID_INPUT := 0x10000003
    static HEADER_SIZE := 24
    static RIM_TYPEHID := 2
    static lastHex := ""
    static lastTick := 0
    static arrivals := 0
    static lastArrivalLog := 0
    if CompanionDisabled
        return 0

    ; Count arrivals BEFORE any filtering. Without this, a message that is
    ; received and then discarded during parsing is indistinguishable from a
    ; message that never arrived.
    arrivals++
    if (A_TickCount - lastArrivalLog >= 2000) {
        lastArrivalLog := A_TickCount
        LogLine("RawInput probe: " arrivals " WM_INPUT message(s) received so far.")
    }

    size := 0
    try {
        if (DllCall("GetRawInputData", "Ptr", lParam, "UInt", RID_INPUT,
            "Ptr", 0, "UInt*", &size, "UInt", HEADER_SIZE) = 0xFFFFFFFF || !size)
            return
        data := Buffer(size, 0)
        if (DllCall("GetRawInputData", "Ptr", lParam, "UInt", RID_INPUT,
            "Ptr", data, "UInt*", &size, "UInt", HEADER_SIZE) = 0xFFFFFFFF)
            return
        if (NumGet(data, 0, "UInt") != RIM_TYPEHID)
            return
        device := NumGet(data, 8, "Ptr")
        sizeHid := NumGet(data, HEADER_SIZE, "UInt")
        count := NumGet(data, HEADER_SIZE + 4, "UInt")
        if (!sizeHid || !count)
            return
        ; Report the first report only, and cap the byte count: this identifies
        ; presses without turning a 125 Hz stream into an unreadable log.
        limit := Min(sizeHid, 20)
        hex := ""
        Loop limit
            hex .= Format("{:02X}", NumGet(data, HEADER_SIZE + 8 + A_Index - 1, "UChar")) " "
        hex := RTrim(hex)

        ; The learning wizard sees reports first and consumes them: while it is
        ; open, decoding as well would fire mappings from the very buttons being
        ; pressed to teach the layout.
        if LearnActive {
            ControllerLearnReport(data, HEADER_SIZE + 8, sizeHid, device)
            if !EnableRawInputProbe
                return
        } else {
            ; Decode EVERY report, before any log rate-limiting. The cached state
            ; is what the poll loop reads, so dropping reports here would drop
            ; input.
            RawInputDecodeReport(data, HEADER_SIZE + 8, sizeHid, device)
        }

        if !EnableRawInputProbe
            return
        ; Log on change, rate-limited, so a held button cannot flood the log.
        if (hex = lastHex || A_TickCount - lastTick < 60)
            return
        lastHex := hex
        lastTick := A_TickCount
        foreground := "unknown"
        try foreground := WinGetProcessName("A")
        LogLine("RawHID dev=0x" Format("{:X}", device)
            . " len=" sizeHid " n=" count " [" hex "] fg=" foreground)
    }
}

; Decodes one HID gamepad report into the XINPUT_STATE-shaped buffer the rest of
; the companion consumes, so mappings, chords and the controller mouse are
; identical on every backend.
;
; Layout verified against hardware (device 0x10062, 16-byte report):
;   1-2 LX, 3-4 LY, 5-6 RX, 7-8 RY   16-bit LE, 0x8000 centre, 0x0000 = left/up
;   9-10  combined trigger axis      0x8000 neutral, above = LT, below = RT
;   11    A B X Y LB RB View Menu    bits 0..7
;   12    L3 R3 Guide                bits 0..2
;   13    D-pad hat, 1..8 clockwise from north, 0 = released
; Decides whether this device is the one whose reports we decode.
;
; The lock is not permanent, and must not be. RawInputDevice holds a
; RAWINPUTHEADER.hDevice handle, and those handles are NOT stable for the life of
; the process: Windows re-enumerates HID devices across sleep/resume and the same
; controller comes back with a DIFFERENT handle. A permanent lock then rejects
; every report the controller sends -- silently, because rejecting a report from
; another device is normal behaviour. Measured symptom: input works, the Ally
; sleeps, and input never returns inside FSE, while the desktop keeps working
; because `auto` falls back to XInput, which re-resolves its slot on its own.
;
; So the lock is handed over when the locked device has gone quiet and a different
; one is producing usable reports. A device that is actively reporting is never
; displaced, which is what keeps a headset or remote out of the decoder -- the
; reason the lock exists at all.
RawInputClaimDevice(device) {
    global RawInputDevice, RawInputLastReportTick
    static DEVICE_HANDOVER_MS := 1000
    if (RawInputDevice && device != RawInputDevice) {
        if (RawInputLastReportTick
            && A_TickCount - RawInputLastReportTick < DEVICE_HANDOVER_MS)
            return false
        LogLine("RawInput: device 0x" Format("{:X}", RawInputDevice) " went quiet; "
            . "adopting 0x" Format("{:X}", device)
            . " (re-enumerated, most likely across sleep).")
        RawInputDevice := device
        return true
    }
    if !RawInputDevice {
        RawInputDevice := device
        LogLine("RawInput: decoding reports from device 0x" Format("{:X}", device) ".")
    }
    return true
}

RawInputDecodeReport(data, base, length, device) {
    global RawInputState, RawInputLastReportTick, RawInputDevice
    static EXPECTED_LENGTH := 16
    static warnedDevices := Map()
    static announcedProfile := Map()

    ; Only accept the report shape this decoder was verified against, and stay
    ; with the first device that produces one. Other HID devices (headsets,
    ; remotes) also raise WM_INPUT and would decode into nonsense.
    ;
    ; The byte layout below is NOT generic HID -- it is the layout of the ROG
    ; Ally's built-in controller, read off the hardware. A controller with any
    ; other report shape is rejected here, which is the safe outcome on the
    ; desktop (XInput takes over) and a dead controller inside Xbox FSE, where
    ; XInput reads zeros. Logged per device rather than once, because "some
    ; other controller was ignored" is the whole diagnosis.
    ; A learned profile takes precedence, and is tried before the length check --
    ; the whole point of learning a controller is that its reports are a shape
    ; this built-in layout would reject.
    deviceKey := RawInputDeviceKey(device)
    profile := LoadControllerProfile(deviceKey)
    ; No identity available, so fall back to a profile keyed on report length.
    if (!IsObject(profile) && deviceKey = "")
        profile := LoadControllerProfile(ControllerProfileLengthKey(length))
    if (IsObject(profile) && profile["length"] = length) {
        if !RawInputClaimDevice(device)
            return false
        if !announcedProfile.Has(device) {
            announcedProfile[device] := true
            LogLine("RawInput: decoding device 0x" Format("{:X}", device)
                . " with learned profile '" profile["key"] "'.")
        }
        return RawInputProfileDecode(profile, data, base, length)
    }

    if (length != EXPECTED_LENGTH) {
        if !warnedDevices.Has(device) {
            warnedDevices[device] := true
            LogLine("RawInput: ignoring " length "-byte reports from device 0x"
                . Format("{:X}", device) " (" RawInputDeviceKey(device) "). The "
                . "built-in layout only understands " EXPECTED_LENGTH "-byte "
                . "reports (the ROG Ally controller). Use Settings -> Controller "
                . "& Cursor -> Learn Controller to teach this one, or it will work on the "
                . "desktop through XInput but not inside Xbox FSE.", "Warning")
        }
        return false
    }
    if !RawInputClaimDevice(device)
        return false

    buttons := 0
    face := NumGet(data, base + 11, "UChar")
    extra := NumGet(data, base + 12, "UChar")
    hat := NumGet(data, base + 13, "UChar")
    if (face & 0x01)
        buttons |= 0x1000        ; A
    if (face & 0x02)
        buttons |= 0x2000        ; B
    if (face & 0x04)
        buttons |= 0x4000        ; X
    if (face & 0x08)
        buttons |= 0x8000        ; Y
    if (face & 0x10)
        buttons |= 0x0100        ; LB
    if (face & 0x20)
        buttons |= 0x0200        ; RB
    if (face & 0x40)
        buttons |= 0x0020        ; View
    if (face & 0x80)
        buttons |= 0x0010        ; Menu
    if (extra & 0x01)
        buttons |= 0x0040        ; L3
    if (extra & 0x02)
        buttons |= 0x0080        ; R3
    if (extra & 0x04)
        buttons |= 0x0400        ; Guide
    switch hat {
        case 1:
            buttons |= 0x0001
        case 2:
            buttons |= 0x0001 | 0x0008
        case 3:
            buttons |= 0x0008
        case 4:
            buttons |= 0x0002 | 0x0008
        case 5:
            buttons |= 0x0002
        case 6:
            buttons |= 0x0002 | 0x0004
        case 7:
            buttons |= 0x0004
        case 8:
            buttons |= 0x0001 | 0x0004
    }

    ; Combined trigger axis. LT and RT cancel when held together, so a chord can
    ; never require both at once on this backend.
    trigger := NumGet(data, base + 9, "UShort")
    lt := 0
    rt := 0
    if (trigger > 0x8000)
        lt := Min(255, (trigger - 0x8000) // 128)
    else if (trigger < 0x8000)
        rt := Min(255, (0x8000 - trigger) // 128)

    NumPut("UInt", 0, RawInputState, 0)
    NumPut("UShort", buttons, RawInputState, 4)
    NumPut("UChar", lt, RawInputState, 6)
    NumPut("UChar", rt, RawInputState, 7)
    NumPut("Short", RawInputAxis(NumGet(data, base + 1, "UShort")), RawInputState, 8)
    ; HID reports up as 0x0000; XInput expects up to be positive.
    NumPut("Short", -RawInputAxis(NumGet(data, base + 3, "UShort")), RawInputState, 10)
    NumPut("Short", RawInputAxis(NumGet(data, base + 5, "UShort")), RawInputState, 12)
    NumPut("Short", -RawInputAxis(NumGet(data, base + 7, "UShort")), RawInputState, 14)
    RawInputLastReportTick := A_TickCount
    return true
}

RawInputAxis(raw) {
    value := raw - 0x8000
    if (value < -32767)
        return -32767
    return value > 32767 ? 32767 : value
}

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

; The section name used when Windows will not identify a device at all.
;
; Keying a profile on report length is less precise than VID/PID, but it is
; exactly as precise as the built-in layout it replaces -- that already matches on
; nothing but `length = 16`. So this is not a new risk, it is the existing one
; made writable, and it is what lets a controller whose metadata Windows withholds
; still be taught.
ControllerProfileLengthKey(length) {
    return "LEN_" length
}

ControllerProfilePath() {
    global IniPath
    return RegExReplace(IniPath, "\.ini$", "") "-Controllers.ini"
}

; A stable identity for a RawInput device.
;
; hDevice handles change across sleep and re-plugging, so they cannot key a saved
; profile. The device interface path does contain a stable identity -- the USB
; vendor and product IDs, plus the interface and collection when a device exposes
; several -- so that is what is extracted. If the driver withholds both the path
; and numeric IDs, the HID preparsed descriptor is hashed as a final stable
; layout identity.
RawInputDeviceKey(hDevice, refresh := false) {
    static RIDI_DEVICENAME := 0x20000007
    static RIDI_DEVICEINFO := 0x2000000B
    static RIDI_PREPARSEDDATA := 0x20000005
    static cache := Map()
    ; Identity lookups that failed recently, and when they may be retried.
    ;
    ; Failure must not be cached permanently -- a metadata query can fail while
    ; the HID stack is still settling, and Save needs a later attempt to be able
    ; to succeed. But it must not be retried on every report either: this runs
    ; from the WM_INPUT handler at over 100 Hz, and the fallback chain below costs
    ; five syscalls plus a byte-at-a-time hash of the entire HID descriptor. For a
    ; device that can never be identified, that is pure waste on the input hot
    ; path of a handheld. So failure backs off for a couple of seconds instead.
    static failedUntil := Map()
    static IDENTITY_RETRY_MS := 2000
    if (refresh && cache.Has(hDevice))
        cache.Delete(hDevice)
    if refresh
        failedUntil.Delete(hDevice)
    if cache.Has(hDevice)
        return cache[hDevice]
    if (failedUntil.Has(hDevice) && A_TickCount < failedUntil[hDevice])
        return ""
    ; Captured for the diagnostic at the end of this function.
    infoVid := 0
    infoPid := 0
    infoResult := "not tried"
    descriptorBytes := 0
    descriptorResult := "not tried"
    name := ""
    size := 0
    nameError := ""
    ; NOT named "buffer", and the catch is not optional.
    ;
    ; AutoHotkey identifiers are case-insensitive, so a local called buffer IS
    ; the Buffer class: the constructor on the right resolved to the unassigned
    ; local and threw before it ever ran. Inside the bare try that used to be
    ; here that throw was swallowed, so RIDI_DEVICENAME appeared to fail on every
    ; device on every machine -- which silently removed the &MI_/&Col suffixes
    ; below, collapsing every collection of a composite gamepad onto one profile
    ; key, and made the DEV_ checksum fallback unreachable. The failure is
    ; carried to the once-per-device diagnostic at the end of this function
    ; rather than logged here, because this runs from WM_INPUT above 100 Hz.
    ;
    ; ElevatedRtssFinalPath in SteamShell-Helper.ahk carries the same note.
    try {
        DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", RIDI_DEVICENAME,
            "Ptr", 0, "UInt*", &size)
        if size {
            nameBuffer := Buffer(size * 2 + 2, 0)
            if (DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", RIDI_DEVICENAME,
                "Ptr", nameBuffer, "UInt*", &size, "UInt") != 0xFFFFFFFF)
                name := StrGet(nameBuffer, "UTF-16")
        }
    } catch as err {
        nameError := err.Message
    }
    key := ""
    if RegExMatch(name, "i)VID_([0-9A-F]{4})&PID_([0-9A-F]{4})", &match) {
        key := "VID_" StrUpper(match[1]) "_PID_" StrUpper(match[2])
        ; A composite device exposes several collections; the gamepad is only one
        ; of them, so the interface and collection numbers are part of the identity.
        if RegExMatch(name, "i)&MI_([0-9A-F]{2})", &mi)
            key .= "_MI_" StrUpper(mi[1])
        if RegExMatch(name, "i)&Col([0-9]{2})", &col)
            key .= "_Col" col[1]
    } else if (name != "") {
        ; No VID/PID in the path. Fall back to a checksum of it, which is still
        ; stable for this device on this machine.
        sum := 0
        Loop Parse name
            sum := Mod(sum * 31 + Ord(A_LoopField), 0xFFFFFFF)
        key := "DEV_" Format("{:07X}", sum)
    }
    if (key = "") {
        ; Some HID stacks deliver reports but do not return an interface path
        ; for RIDI_DEVICENAME. RIDI_DEVICEINFO carries the numeric HID VID/PID
        ; independently, so use it before declaring the device unidentifiable.
        try {
            info := Buffer(32, 0)
            NumPut("UInt", 32, info, 0)
            infoSize := 32
            infoResult := DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt",
                RIDI_DEVICEINFO, "Ptr", info, "UInt*", &infoSize, "UInt")
            infoVid := NumGet(info, 8, "UInt") & 0xFFFF
            infoPid := NumGet(info, 12, "UInt") & 0xFFFF
            if (infoResult != 0xFFFFFFFF) {
                vid := NumGet(info, 8, "UInt")
                pid := NumGet(info, 12, "UInt")
                if (vid || pid)
                    key := "VID_" Format("{:04X}", vid & 0xFFFF)
                        . "_PID_" Format("{:04X}", pid & 0xFFFF)
            }
        }
    }
    if (key = "") {
        ; RawInput cannot deliver HID reports without preparsed descriptor data.
        ; Some virtualised/filtered Ally drivers expose that data while
        ; returning neither a device path nor usable RID_DEVICE_INFO IDs. Hash
        ; the descriptor so the learned layout still survives handle changes.
        try {
            descriptorSize := 0
            result := DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt",
                RIDI_PREPARSEDDATA, "Ptr", 0, "UInt*", &descriptorSize, "UInt")
            descriptorResult := result
            descriptorBytes := descriptorSize
            if (result != 0xFFFFFFFF && descriptorSize > 0) {
                descriptor := Buffer(descriptorSize, 0)
                result := DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice,
                    "UInt", RIDI_PREPARSEDDATA, "Ptr", descriptor,
                    "UInt*", &descriptorSize, "UInt")
                if (result != 0xFFFFFFFF && descriptorSize > 0) {
                    hash := 2166136261
                    Loop descriptorSize
                        hash := Mod((hash ^ NumGet(descriptor,
                            A_Index - 1, "UChar")) * 16777619, 0x100000000)
                    key := "HID_DESC_" Format("{:08X}", hash)
                        . "_" descriptorSize
                }
            }
        }
    }
    ; Record what each route actually returned the first time a device cannot be
    ; identified. "No identity available" is unactionable on its own, and this
    ; failed on real hardware -- the Ally's own controller -- so the three return
    ; values are the diagnosis.
    static reported := Map()
    if (key = "" && !reported.Has(hDevice)) {
        reported[hDevice] := true
        LogLine("RawInput identity: device 0x" Format("{:X}", hDevice)
            . " unidentifiable. RIDI_DEVICENAME chars=" size
            . " path='" (name != "" ? name : "(none)") "'"
            ; Without this, a throw inside the path lookup was indistinguishable
            ; from the HID stack returning a size and no path, and pointed the
            ; diagnosis at the driver instead of at this function.
            . (nameError != "" ? " pathError='" nameError "'" : "")
            . ", RIDI_DEVICEINFO vid=0x" Format("{:04X}", infoVid)
            . " pid=0x" Format("{:04X}", infoPid) " rc=" infoResult
            . ", RIDI_PREPARSEDDATA bytes=" descriptorBytes
            . " rc=" descriptorResult ".", "Warning")
    }
    ; Success caches permanently; failure only backs off. See failedUntil above.
    if (key != "") {
        cache[hDevice] := key
        failedUntil.Delete(hDevice)
    } else {
        failedUntil[hDevice] := A_TickCount + IDENTITY_RETRY_MS
    }
    return key
}

; The human-readable device path, recorded beside a learned profile so the INI
; can be read by a person. Called once per Save, not on the input path.
;
; NOT named "buffer" -- see the note in RawInputDeviceKey. This copy had the
; same defect, so every profile ever saved recorded an empty Name.
RawInputDeviceName(hDevice) {
    static RIDI_DEVICENAME := 0x20000007
    name := ""
    size := 0
    try {
        DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", RIDI_DEVICENAME,
            "Ptr", 0, "UInt*", &size)
        if size {
            nameBuffer := Buffer(size * 2 + 2, 0)
            if (DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", RIDI_DEVICENAME,
                "Ptr", nameBuffer, "UInt*", &size, "UInt") != 0xFFFFFFFF)
                name := StrGet(nameBuffer, "UTF-16")
        }
    } catch as err {
        LogLine("RawInput: the device path for 0x" Format("{:X}", hDevice)
            . " could not be read: " err.Message, "Warning")
    }
    return name
}

; The XInput button bit for each name the learner knows.
ControllerButtonBits() {
    static bits := Map(
        "Up", 0x0001, "Down", 0x0002, "Left", 0x0004, "Right", 0x0008,
        "Menu", 0x0010, "View", 0x0020, "L3", 0x0040, "R3", 0x0080,
        "LB", 0x0100, "RB", 0x0200, "Guide", 0x0400,
        "A", 0x1000, "B", 0x2000, "X", 0x4000, "Y", 0x8000)
    return bits
}

; Loads a profile, or 0 when the device has none.
;
; Returns a Map of: length, buttons (array of name/offset/mask/pressed), hat
; (Map or 0), axes (Map of name -> offset/size/neutral/direction/extent).
;
; The optional fourth button field and sixth axis field were added after the
; first profile draft. Missing fields retain the original active-high and
; full-range behaviour, so hand-written or early profiles remain valid.
LoadControllerProfile(key, refresh := false) {
    static cache := Map()
    if (key = "")
        return 0
    ; Saving a VID/PID-only fallback must invalidate any previously cached miss
    ; for the same device's more-specific MI/collection key.
    if refresh
        cache := Map()
    if cache.Has(key)
        return cache[key]
    path := ControllerProfilePath()
    if !FileExist(path) {
        cache[key] := 0
        return 0
    }
    section := key
    length := 0
    try length := Integer(IniRead(path, section, "ReportLength", "0"))
    ; A device path may be available on one boot and unavailable on another.
    ; Profiles saved from numeric RIDI_DEVICEINFO therefore use VID/PID only;
    ; allow a later, more-specific MI/collection key to find that base profile.
    if (length <= 0
        && RegExMatch(key, "i)^(VID_[0-9A-F]{4}_PID_[0-9A-F]{4})", &base)
        && base[1] != key) {
        section := base[1]
        try length := Integer(IniRead(path, section, "ReportLength", "0"))
    }
    if (length <= 0) {
        cache[key] := 0
        return 0
    }
    profile := Map("length", length, "buttons", [], "hat", 0, "axes", Map(),
        "name", "", "key", section)
    try profile["name"] := IniRead(path, section, "Name", "")

    buttonText := ""
    try buttonText := IniRead(path, section, "Buttons", "")
    bits := ControllerButtonBits()
    for _, entry in StrSplit(buttonText, "|") {
        parts := StrSplit(Trim(entry), ":")
        if (parts.Length < 3 || !bits.Has(parts[1]))
            continue
        try {
            offset := Integer(parts[2])
            mask := Integer(parts[3])
            pressed := parts.Length >= 4 ? Integer(parts[4]) : mask
            if (offset < 0 || offset >= length || mask < 1 || mask > 255)
                continue
            profile["buttons"].Push(Map(
                "bit", bits[parts[1]],
                "offset", offset,
                "mask", mask,
                "pressed", pressed & mask))
        }
    }

    hatText := ""
    try hatText := IniRead(path, section, "Hat", "")
    parts := StrSplit(Trim(hatText), ":")
    ; Current: offset : mask : released : N : NE : E : SE : S : SW : W : NW
    ; Early profiles omitted mask; 0xFF preserves their whole-byte behaviour.
    if (parts.Length >= 10) {
        try {
            offset := Integer(parts[1])
            hasMask := parts.Length >= 11
            mask := hasMask ? Integer(parts[2]) : 0xFF
            releasedIndex := hasMask ? 3 : 2
            firstDirectionIndex := hasMask ? 4 : 3
            released := Integer(parts[releasedIndex])
            if (offset < 0 || offset >= length || mask < 1 || mask > 255
                || released < 0 || released > 255)
                throw Error("Invalid hat")
            directions := Map()
            ; Same clockwise-from-north order the built-in layout uses.
            order := [0x0001, 0x0001 | 0x0008, 0x0008, 0x0002 | 0x0008,
                0x0002, 0x0002 | 0x0004, 0x0004, 0x0001 | 0x0004]
            Loop 8 {
                value := Integer(parts[firstDirectionIndex + A_Index - 1])
                if (value < 0 || value > 255)
                    throw Error("Invalid hat")
                directions[value] := order[A_Index]
            }
            profile["hat"] := Map("offset", offset,
                "mask", mask, "released", released, "directions", directions)
        }
    }

    axisText := ""
    try axisText := IniRead(path, section, "Axes", "")
    validAxisNames := Map("LX", true, "LY", true, "RX", true, "RY", true,
        "LT", true, "RT", true)
    validAxisSizes := Map("u8", true, "u16le", true, "u16be", true)
    for _, entry in StrSplit(axisText, "|") {
        parts := StrSplit(Trim(entry), ":")
        if (parts.Length < 5)
            continue
        try {
            name := parts[1]
            offset := Integer(parts[2])
            size := parts[3]
            neutral := Integer(parts[4])
            direction := Integer(parts[5])
            extent := parts.Length >= 6 ? Integer(parts[6]) : 0
            width := size = "u8" ? 1 : 2
            fullScale := size = "u8" ? 255 : 65535
            if (!validAxisNames.Has(name) || !validAxisSizes.Has(size)
                || offset < 0 || offset + width > length
                || neutral < 0 || neutral > fullScale
                || (direction != -1 && direction != 1)
                || extent < 0 || extent > fullScale)
                continue
            profile["axes"][name] := Map(
                "offset", offset,
                "size", size,
                "neutral", neutral,
                "direction", direction,
                "extent", extent)
        }
    }
    if (profile["buttons"].Length = 0 && !IsObject(profile["hat"])
        && profile["axes"].Count = 0) {
        cache[key] := 0
        return 0
    }
    cache[key] := profile
    return profile
}

; Reads one axis field out of a report.
ControllerProfileAxisRaw(data, base, axis) {
    offset := base + axis["offset"]
    if (axis["size"] = "u8")
        return NumGet(data, offset, "UChar")
    if (axis["size"] = "u16be") {
        high := NumGet(data, offset, "UChar")
        return (high << 8) | NumGet(data, offset + 1, "UChar")
    }
    return NumGet(data, offset, "UShort")
}

; Full scale of an axis field, used to normalise to XInput's ranges.
ControllerProfileAxisSpan(axis) {
    return axis["size"] = "u8" ? 255 : 65535
}

; Decodes a report using a learned profile.
;
; Produces exactly the same XINPUT_STATE-shaped buffer as the built-in decoder,
; so every mapping, chord and the controller mouse behave identically no matter
; how the layout was obtained.
RawInputProfileDecode(profile, data, base, length) {
    global RawInputState, RawInputLastReportTick
    if (length != profile["length"])
        return false

    buttons := 0
    for _, button in profile["buttons"] {
        value := NumGet(data, base + button["offset"], "UChar")
        if ((value & button["mask"]) = button["pressed"])
            buttons |= button["bit"]
    }
    hat := profile["hat"]
    if IsObject(hat) {
        value := NumGet(data, base + hat["offset"], "UChar") & hat["mask"]
        if (value != hat["released"] && hat["directions"].Has(value))
            buttons |= hat["directions"][value]
    }

    lt := 0
    rt := 0
    axes := profile["axes"]
    ; A shared trigger axis is not a special case here: LT and RT simply resolve
    ; to the same offset with opposite directions, which is how the learner
    ; records what it observed.
    for _, name in ["LT", "RT"] {
        if !axes.Has(name)
            continue
        axis := axes[name]
        raw := ControllerProfileAxisRaw(data, base, axis)
        delta := (raw - axis["neutral"]) * axis["direction"]
        if (delta <= 0)
            continue
        ; The travel is only ever one side of neutral, and which side depends on
        ; the direction, so the divisor has to follow it. Using the full span
        ; would halve a trigger that rests at mid-scale -- which a shared trigger
        ; axis does.
        span := axis["extent"]
        if (span <= 0) {
            span := (axis["direction"] > 0)
                ? ControllerProfileAxisSpan(axis) - axis["neutral"]
                : axis["neutral"]
        }
        value := Min(255, Round(delta * 255 / Max(1, span)))
        if (name = "LT")
            lt := value
        else
            rt := value
    }

    thumbs := Map("LX", 8, "LY", 10, "RX", 12, "RY", 14)
    NumPut("UInt", 0, RawInputState, 0)
    NumPut("UShort", buttons, RawInputState, 4)
    NumPut("UChar", lt, RawInputState, 6)
    NumPut("UChar", rt, RawInputState, 7)
    for name, stateOffset in thumbs {
        value := 0
        if axes.Has(name) {
            axis := axes[name]
            raw := ControllerProfileAxisRaw(data, base, axis)
            offsetFromRest := raw - axis["neutral"]
            ; Each side of neutral is scaled by its own travel, so an axis whose
            ; rest point is not exactly mid-scale still reaches full deflection
            ; both ways instead of clipping one side and falling short on the
            ; other.
            span := axis["extent"]
            if (span <= 0) {
                span := (offsetFromRest >= 0)
                    ? ControllerProfileAxisSpan(axis) - axis["neutral"]
                    : axis["neutral"]
            }
            scaled := Round(offsetFromRest * 32767 / Max(1, span))
            value := ClampFloat(scaled * axis["direction"], -32767, 32767)
        }
        NumPut("Short", value, RawInputState, stateOffset)
    }
    RawInputLastReportTick := A_TickCount
    return true
}

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
global RestCheckPeak := Map()
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

; The prompts, in order. Buttons first: they are unambiguous and confirm the
; report is being read correctly before anything subtler is attempted.
ControllerLearnSteps() {
    static steps := [
        ; Analogue bytes are found FIRST, and every later button step ignores
        ; them.
        ;
        ; Without this, a stick that moves even slightly during a button step is
        ; read as the button. At rest LX is 0x8000, so its low byte is 0x00; nudge
        ; the stick and that byte becomes something like 0x40 -- a bit that was
        ; never set at rest, which is exactly the test a button has to pass. It is
        ; worst on L3 and R3, where the stick must be touched to click it in.
        Map("kind", "wiggle", "name", "Analogue scan",
            "prompt", "Roll BOTH sticks around their full range, squeeze BOTH "
                . "triggers, then let go of everything"),
        Map("kind", "button", "name", "A", "prompt", "Press and release the A button"),
        Map("kind", "button", "name", "B", "prompt", "Press and release the B button"),
        Map("kind", "button", "name", "X", "prompt", "Press and release the X button"),
        Map("kind", "button", "name", "Y", "prompt", "Press and release the Y button"),
        Map("kind", "button", "name", "LB", "prompt", "Press and release the LEFT bumper"),
        Map("kind", "button", "name", "RB", "prompt", "Press and release the RIGHT bumper"),
        Map("kind", "button", "name", "View", "prompt", "Press and release the View / Back button"),
        Map("kind", "button", "name", "Menu", "prompt", "Press and release the Menu / Start button"),
        Map("kind", "button", "name", "L3",
            "prompt", "Click the LEFT stick in, then release"),
        Map("kind", "button", "name", "R3",
            "prompt", "Click the RIGHT stick in, then release"),
        Map("kind", "button", "name", "Guide", "prompt", "Press and release the Guide / Xbox button",
            "optional", true),
        Map("kind", "dpad", "name", "Up", "prompt", "Press and release the D-pad UP"),
        Map("kind", "dpad", "name", "Right", "prompt", "Press and release the D-pad RIGHT"),
        Map("kind", "dpad", "name", "Down", "prompt", "Press and release the D-pad DOWN"),
        Map("kind", "dpad", "name", "Left", "prompt", "Press and release the D-pad LEFT"),
        ; "want" is the sign XInput expects for the direction being asked for, so
        ; the learned multiplier lands in XInput's convention whichever way the
        ; hardware happens to count. Sticks are asked for LEFT, where XInput is
        ; negative, and UP, where XInput is positive -- opposite signs for what
        ; feels like the same question, which is exactly the sort of thing worth
        ; writing down rather than rediscovering.
        Map("kind", "axis", "name", "LX", "want", -1,
            "prompt", "Move the LEFT stick fully LEFT, then RELEASE it"),
        Map("kind", "axis", "name", "LY", "want", 1,
            "prompt", "Move the LEFT stick fully UP, then RELEASE it"),
        Map("kind", "axis", "name", "RX", "want", -1,
            "prompt", "Move the RIGHT stick fully LEFT, then RELEASE it"),
        Map("kind", "axis", "name", "RY", "want", 1,
            "prompt", "Move the RIGHT stick fully UP, then RELEASE it"),
        Map("kind", "axis", "name", "LT", "want", 1,
            "prompt", "Squeeze the LEFT trigger fully, then RELEASE it"),
        Map("kind", "axis", "name", "RT", "want", 1,
            "prompt", "Squeeze the RIGHT trigger fully, then RELEASE it")
    ]
    return steps
}

; Feeds one report to the learner. Called from the WM_INPUT handler ahead of the
; normal decode, and only while the wizard is open.
ControllerLearnReport(data, base, length, device) {
    global LearnActive, LearnDevice, LearnDeviceKey, LearnLength, LearnBaseline
    global LearnStepIndex, LearnCaptureUntil, LearnPeak
    global LearnRestNoise, LearnRestSampling, LearnRestCount
    global LearnIdentifyDevices, LearnIdentifyReady
    global LearnReleaseOffset, LearnStepReports
    if !LearnActive
        return
    ; Select the controller that the user actually operates. RawInput gamepads
    ; often publish idle reports continuously, so locking to the first hDevice
    ; seen makes the prompt meaningless when more than one pad is connected.
    if !LearnDevice {
        if !LearnIdentifyDevices.Has(device) {
            LearnIdentifyDevices[device] := Map(
                "length", length,
                "baseline", ControllerLearnCopyReport(data, base, length),
                "noise", Buffer(length, 0))
            return
        }
        known := LearnIdentifyDevices[device]
        if (known["length"] != length) {
            LearnIdentifyDevices[device] := Map(
                "length", length,
                "baseline", ControllerLearnCopyReport(data, base, length),
                "noise", Buffer(length, 0))
            return
        }
        baseline := known["baseline"]
        noise := known["noise"]
        if !LearnIdentifyReady {
            ; First learn which bits move while every controller is idle. This
            ; prevents 16-bit stick low-byte jitter from selecting the first pad
            ; that happens to publish reports.
            Loop length {
                offset := A_Index - 1
                now := NumGet(data, base + offset, "UChar")
                changed := now ^ NumGet(baseline, offset, "UChar")
                NumPut("UChar", NumGet(noise, offset, "UChar") | changed,
                    noise, offset)
                NumPut("UChar", now, baseline, offset)
            }
            return
        }
        identified := false
        Loop length {
            offset := A_Index - 1
            now := NumGet(data, base + offset, "UChar")
            was := NumGet(baseline, offset, "UChar")
            changed := (now ^ was) & ~NumGet(noise, offset, "UChar") & 0xFF
            if changed {
                identified := true
                break
            }
        }
        ; Some controllers publish only on state changes: one press report, then
        ; silence while the button remains held. Idle noise was measured before
        ; the prompt, so the first clean change is the only reliable selector.
        if !identified
            return
        LearnDevice := device
        LearnDeviceKey := RawInputDeviceKey(device)
        LearnLength := length
        ; Start the explicit rest phase from the report that completed device
        ; identification, not the first report ever seen from that device.
        ;
        ; A change-only controller may first appear when A is pressed, then be
        ; identified by the release report. Keeping the first report would make
        ; "A held" the resting baseline: A would be learned on release, and B
        ; would keep colliding with that false mapping forever.
        LearnBaseline := ControllerLearnCopyReport(data, base, length)
        LearnRestNoise := Buffer(length, 0)
        LogLine("Learn: capturing from device 0x" Format("{:X}", device)
            . " key=" (LearnDeviceKey != "" ? LearnDeviceKey : "unknown")
            . " reportLength=" length ".")
        ControllerLearnUpdateUi()
        return
    }
    if (device != LearnDevice || length != LearnLength)
        return
    ; Rest sampling. The baseline is every detection's reference point, so it is
    ; taken while the user has explicitly let go, not from the report that
    ; happened to identify the device -- that one arrived with a button held.
    if LearnRestSampling {
        LearnRestCount += 1
        Loop length {
            offset := A_Index - 1
            value := NumGet(data, base + A_Index - 1, "UChar")
            ; The first explicit rest report refreshes the earlier idle
            ; baseline. Only later rest-to-rest changes are noise.
            if (LearnRestCount > 1) {
                changed := value ^ NumGet(LearnBaseline, offset, "UChar")
                NumPut("UChar", NumGet(LearnRestNoise, offset, "UChar") | changed,
                    LearnRestNoise, offset)
            }
            NumPut("UChar", value, LearnBaseline, offset)
        }
        return
    }
    ; A detected control is waiting to be released; nothing else is examined until
    ; it is, so a held button cannot answer the next prompt.
    if (LearnReleaseOffset >= 0) {
        ControllerLearnReleaseCheck(data, base, length)
        return
    }
    if (LearnStepIndex < 1 || !LearnCaptureUntil)
        return
    LearnStepReports += 1
    ControllerLearnExamine(data, base, length)
}

ControllerLearnCopyReport(data, base, length) {
    report := Buffer(length, 0)
    Loop length
        NumPut("UChar", NumGet(data, base + A_Index - 1, "UChar"),
            report, A_Index - 1)
    return report
}

; Turns the value census into the set of analogue bytes.
;
; Two conditions, both needed. A wide spread alone would also match a byte that
; happened to hold two far-apart button masks; a large distinct count alone could
; match a counter or timestamp field, which some reports carry. Requiring a byte
; to take many different values ACROSS a wide range is what isolates a real
; analogue control.
ControllerLearnClassifyAnalog() {
    global LearnAnalogValues, LearnAnalogBytes, LearnBaseline
    static MIN_DISTINCT_VALUES := 6
    static MIN_RANGE := 32
    LearnAnalogBytes := Map()
    described := ""
    for offset, values in LearnAnalogValues {
        if (values.Count < MIN_DISTINCT_VALUES)
            continue
        low := 255
        high := 0
        for value in values {
            low := Min(low, value)
            high := Max(high, value)
        }
        if (high - low < MIN_RANGE)
            continue
        LearnAnalogBytes[offset] := true
        described .= (described != "" ? ", " : "") offset
            . " (" values.Count " values, " low "-" high ")"
    }
    LogLine("Learn: analogue bytes = "
        . (described != "" ? described : "none detected")
        . ". Button steps will ignore them.")
    return LearnAnalogBytes.Count
}

; Compares one report against the baseline for the current step.
ControllerLearnExamine(data, base, length) {
    global LearnBaseline, LearnStepIndex, LearnResultButtons, LearnResultAxes
    global LearnHatValues, LearnPeak, LearnDetailCtrl, LearnRestNoise
    global LearnAnalogBytes, LearnAnalogValues
    global LearnExcursion, LearnAxisSamples, LearnAxisStarted
    step := ControllerLearnSteps()[LearnStepIndex]
    kind := step["kind"]

    ; Census of the values each byte takes while the analogue controls are swept.
    if (kind = "wiggle") {
        Loop length {
            offset := A_Index - 1
            value := NumGet(data, base + offset, "UChar")
            if !LearnAnalogValues.Has(offset)
                LearnAnalogValues[offset] := Map()
            LearnAnalogValues[offset][value] := true
        }
        return
    }

    if (kind = "dpad") {
        ; A D-pad is either four bits or one hat byte, and which it is CANNOT be
        ; decided from a single direction. On a hat, "up" is just a value in a
        ; byte, and its low bit is indistinguishable from a button bit -- on the
        ; ROG Ally itself, hat=1 for up would otherwise be learned as a button at
        ; byte 13 bit 0, and then right (hat=3) would learn the same bit again.
        ;
        ; So each direction is recorded as an (offset, value) pair and the
        ; decision is deferred until all four are known. ControllerLearnHatText
        ; makes it: evenly spaced values on one byte are a hat, anything else
        ; falls back to one bit per direction.
        Loop length {
            offset := A_Index - 1
            now := NumGet(data, base + offset, "UChar")
            was := NumGet(LearnBaseline, offset, "UChar")
            if (now = was)
                continue
            ; Skip bits that were already moving while at rest, and any byte the
            ; opening scan identified as analogue.
            if (LearnAnalogBytes.Has(offset))
                continue
            if ((now ^ was) & NumGet(LearnRestNoise, offset, "UChar"))
                continue
            for _, existing in LearnHatValues {
                if (existing["offset"] = offset && existing["value"] = now)
                    return
            }
            LearnHatValues[step["name"]] := Map("offset", offset, "value", now,
                "released", was)
            ; Mask 0: the whole hat byte must return to its resting value.
            ControllerLearnAccept(step["name"] " = byte " offset " value " now,
                offset, 0)
            return
        }
        return
    }

    if (kind = "button") {
        ; A bit whose state differs now and NEVER changed during rest.
        ;
        ; Comparing against the resting transition mask is what keeps analogue
        ; jitter out while still allowing buttons whose pressed state is zero.
        Loop length {
            offset := A_Index - 1
            ; An analogue byte is never a button, however convincing it looks.
            ; A stick nudged during this step changes bits that were clear at
            ; rest, which is precisely the test below -- and on L3/R3 the stick
            ; has to be touched, so this is the common case, not an edge one.
            if (LearnAnalogBytes.Has(offset))
                continue
            now := NumGet(data, base + offset, "UChar")
            was := NumGet(LearnBaseline, offset, "UChar")
            restNoise := NumGet(LearnRestNoise, offset, "UChar")
            changed := (now ^ was) & ~restNoise & 0xFF
            if !changed
                continue
            ; Take the lowest set bit, so a byte carrying several changes at once
            ; still yields one unambiguous mask.
            mask := changed & -changed
            ; Accept the press report itself. The Ally and other change-only
            ; devices send no duplicate reports while a digital control is held.
            ; Rest sampling already removed bits that jitter without a press.
            pressed := now & mask
            ControllerLearnRecordButton(step["name"], offset, mask, pressed)
            return
        }
        return
    }

    ; Axis capture is a gesture: move outward, then return to neutral. Finishing
    ; on the return report gives the next prompt a clean baseline and prevents a
    ; held stick or trigger from spilling into the next reading.
    report := ControllerLearnCopyReport(data, base, length)
    active := ControllerLearnReportAxisActive(report, LearnAxisStarted ? 6 : 12)
    if !LearnAxisStarted {
        if !active
            return
        LearnAxisStarted := true
        try LearnDetailCtrl.Text := "Movement detected — return it to rest to finish."
    } else if !active {
        ControllerLearnCompleteAxis(step)
        return
    }

    LearnAxisSamples.Push(report)
    Loop length {
        offset := A_Index - 1
        delta := Abs(NumGet(report, offset, "UChar")
            - NumGet(LearnBaseline, offset, "UChar"))
        if (delta > NumGet(LearnExcursion, offset, "UChar"))
            NumPut("UChar", delta, LearnExcursion, offset)
    }
    peak := 0
    Loop length
        peak := Max(peak, NumGet(LearnExcursion, A_Index - 1, "UChar") * 256)
    if (peak > LearnPeak) {
        LearnPeak := peak
        try LearnDetailCtrl.Text := "Movement detected — return it to rest to finish."
    }
    ; Once enough travel exists, remember the likely field. This lets the
    ; release test use the decoded 8/16-bit value rather than being fooled by a
    ; wrapping low byte near a 16-bit axis's centre.
    ControllerLearnResolveAxis(step)
}

; True while the current analogue control is away from rest. A resolved 16-bit
; field is checked as a whole because its low byte can wrap at centre. For an
; 8-bit or not-yet-resolved field, clean unclaimed byte movement is safer: an
; early low-byte candidate must not look released merely because it wrapped
; through its resting value halfway across a 16-bit sweep.
ControllerLearnReportAxisActive(report, byteThreshold) {
    global LearnBaseline, LearnResultButtons, LearnResultAxes, LearnHatValues
    global LearnRestNoise, LearnStepIndex, LearnLength
    step := ControllerLearnSteps()[LearnStepIndex]
    if LearnResultAxes.Has(step["name"]) {
        axis := LearnResultAxes[step["name"]]
        if (axis["size"] != "u8") {
            raw := ControllerLearnBufferAxisRaw(
                report, axis["offset"], axis["size"])
            return Abs(raw - axis["neutral"]) >= 1500
        }
    }

    claimed := Map()
    for _, button in LearnResultButtons
        claimed[button["offset"]] := true
    for _, hat in LearnHatValues
        claimed[hat["offset"]] := true
    Loop LearnLength {
        offset := A_Index - 1
        if claimed.Has(offset)
            continue
        now := NumGet(report, offset, "UChar")
        was := NumGet(LearnBaseline, offset, "UChar")
        cleanChange := (now ^ was)
            & ~NumGet(LearnRestNoise, offset, "UChar") & 0xFF
        if (cleanChange && Abs(now - was) >= byteThreshold)
            return true
    }
    return false
}

; A failed resolve must leave nothing behind.
;
; This function runs on every report of the gesture, so a provisional answer from
; an earlier report is already sitting in LearnResultAxes when a later one fails.
; Saving that entry would write a field the learner had since REJECTED into the
; profile -- with a neutral and extent measured from a partial sweep, which is a
; direct route to a pointer that will not sit still.
ControllerLearnRejectAxis(step, reason) {
    global LearnResultAxes, LearnAxisRejection
    LearnAxisRejection := reason
    if LearnResultAxes.Has(step["name"])
        LearnResultAxes.Delete(step["name"])
    return false
}

ControllerLearnLargestExcursion() {
    global LearnExcursion, LearnLength
    largest := 0
    Loop LearnLength
        largest := Max(largest, NumGet(LearnExcursion, A_Index - 1, "UChar"))
    return largest
}

; Chooses the field the axis actually occupies, once the whole movement has been
; seen, and converts the observed direction into XInput's convention.
; True when a byte was still moving while the user was holding nothing.
;
; A stick resting at centre jitters in its lowest one or two bits, which is why
; LearnRestNoise exists at all. A motion sensor is different in kind: it streams
; continuously and saturates the whole byte. Counting bits separates the two
; without needing to know which controller this is.
ControllerLearnByteFreeRunning(offset) {
    global LearnRestNoise
    static MIN_FREE_RUNNING_BITS := 4
    mask := NumGet(LearnRestNoise, offset, "UChar")
    bits := 0
    Loop 8 {
        if (mask & (1 << (A_Index - 1)))
            bits += 1
    }
    return bits >= MIN_FREE_RUNNING_BITS
}

; allowRestNoisy is set only by this function's own single retry -- see the
; rejection path at the end.
ControllerLearnResolveAxis(step, allowRestNoisy := false) {
    global LearnAxisSamples, LearnExcursion, LearnLength
    global LearnResultAxes, LearnResultButtons, LearnHatValues, LearnPeak
    global LearnAxisRejection
    static MIN_NORMALISED_DELTA := 4000
    static MIN_BYTE_EXCURSION := 8
    static MIN_PAIR_BALANCE := 0.20

    LearnAxisRejection := ""
    if (LearnAxisSamples.Length = 0)
        return ControllerLearnRejectAxis(step, "no reports were captured")

    ; Buttons and the D-pad own their bytes. Excluding them prevents an
    ; accidentally held button from looking like a full-scale 8-bit trigger.
    claimed := Map()
    for _, button in LearnResultButtons
        claimed[button["offset"]] := true
    for _, hat in LearnHatValues
        claimed[hat["offset"]] := true
    ; Motion sensors own their bytes too, and they never stop moving. On an
    ; 8BitDo Ultimate 2 the 34-byte report carries six 16-bit motion axes that
    ; stream at ~1 kHz, so twelve bytes sweep their full range continuously
    ; whatever the user does. They out-travel the real stick on every step and
    ; were winning the score: measured on hardware, all four sticks failed with
    ; "byte 22 rests at 0% of range", and RT was learned onto that same motion
    ; byte because a trigger legitimately rests at an end of range and so had no
    ; equivalent sanity check to save it.
    ;
    ; Excluded rather than down-ranked because a motion byte can beat a stick on
    ; any score built from travel alone.
    excludedNoisy := 0
    if !allowRestNoisy {
        Loop LearnLength {
            offset := A_Index - 1
            if (!claimed.Has(offset) && ControllerLearnByteFreeRunning(offset)) {
                claimed[offset] := true
                excludedNoisy += 1
            }
        }
    }
    ; A stick cannot share bytes with another stick. Without this the four stick
    ; steps were resolved independently and could land on overlapping fields --
    ; measured once as LX=1, LY=2, RX=4, RY=3, which cannot describe any real
    ; report. Triggers are deliberately exempt: a shared trigger axis is a real
    ; layout, and LT and RT resolving to the same offset is the right answer.
    ;
    ; The step's OWN entry must be excluded. This function runs again on every
    ; report of the gesture, and each run writes its answer into LearnResultAxes
    ; so that ControllerLearnReportAxisActive can watch the decoded field rather
    ; than raw bytes. Without this skip, the second report claimed the very bytes
    ; the first report had just chosen, so the field became unavailable to itself:
    ; every stick then failed with "Not enough travel" no matter how far it was
    ; pushed. Triggers were unaffected, because they are exempt below -- which is
    ; exactly the pattern that was reported from hardware.
    static STICKS := Map("LX", true, "LY", true, "RX", true, "RY", true)
    if STICKS.Has(step["name"]) {
        for name, learned in LearnResultAxes {
            if (!STICKS.Has(name) || name = step["name"])
                continue
            claimed[learned["offset"]] := true
            if (learned["size"] != "u8")
                claimed[learned["offset"] + 1] := true
        }
    }

    best8 := 0
    Loop LearnLength {
        offset := A_Index - 1
        if claimed.Has(offset)
            continue
        if (NumGet(LearnExcursion, offset, "UChar") < MIN_BYTE_EXCURSION)
            continue
        candidate := ControllerLearnAxisStats(offset, "u8")
        if (candidate["delta"] < MIN_NORMALISED_DELTA)
            continue
        if (!IsObject(best8) || candidate["score"] > best8["score"])
            best8 := candidate
    }

    best16 := 0
    if (LearnLength >= 2) {
        Loop LearnLength - 1 {
            offset := A_Index - 1
            if (claimed.Has(offset) || claimed.Has(offset + 1))
                continue
            firstExcursion := NumGet(LearnExcursion, offset, "UChar")
            secondExcursion := NumGet(LearnExcursion, offset + 1, "UChar")
            if (firstExcursion < MIN_BYTE_EXCURSION
                || secondExcursion < MIN_BYTE_EXCURSION)
                continue
            ; Two adjacent 8-bit axes can both drift a little. A real 16-bit
            ; field moves both bytes materially over a full sweep.
            balance := Min(firstExcursion, secondExcursion)
                / Max(firstExcursion, secondExcursion)
            if (balance < MIN_PAIR_BALANCE)
                continue
            ; LITTLE-ENDIAN ONLY. USB HID specifies little-endian for multi-byte
            ; fields, so a big-endian gamepad axis is not a thing that exists --
            ; and offering it as a candidate was actively harmful. Measured on
            ; hardware: at rest the low bytes of every stick jitter constantly
            ; while the high bytes sit still, so a big-endian read promotes that
            ; jitter to the high byte. RX was learned as u16be with a neutral of
            ; 21884 against an actual rest value of 128, which pinned the right
            ; stick at about +19300 and sent the pointer across the screen.
            ;
            ; RawInputProfileDecode still UNDERSTANDS u16be, so a hand-written
            ; profile can use it. The learner simply never guesses it.
            candidate := ControllerLearnAxisStats(offset, "u16le")
            if (candidate["delta"] < MIN_NORMALISED_DELTA
                || candidate["coherence"] < 0.55)
                continue
            if (!IsObject(best16) || candidate["score"] > best16["score"])
                best16 := candidate
        }
    }

    ; Prefer a coherent 16-bit field even when one constituent byte has a larger
    ; endpoint delta. That is normal at 0xFFFF: the low byte moved 255 counts,
    ; while the actual 16-bit field moved about half its range.
    chosen := 0
    if (IsObject(best16)
        && (!IsObject(best8) || best16["score"] >= best8["score"] * 0.45)) {
        chosen := best16
    } else if IsObject(best8) {
        chosen := best8
    }
    if !IsObject(chosen) {
        ; Preference, not prohibition. If nothing survives the motion filter,
        ; try once more with those bytes allowed back in -- a controller whose
        ; sticks really do jitter across several bits at rest must still be
        ; learnable.
        if (!allowRestNoisy && excludedNoisy > 0) {
            LogLine("Learn: no candidate outside the " excludedNoisy
                . " free-running byte(s); retrying with them included.")
            return ControllerLearnResolveAxis(step, true)
        }
        return ControllerLearnRejectAxis(step,
            "no unclaimed field moved far enough (largest byte excursion "
            . ControllerLearnLargestExcursion() " counts)")
    }
    ; "want" is the sign XInput uses for the direction that was asked for. If the
    ; hardware moves the same way, the multiplier is +want; if it counts the
    ; other way, -want.
    ; A stick rests at the CENTRE of its range. That is physics, not a heuristic:
    ; a self-centring stick cannot rest anywhere else. Measured on hardware, all
    ; four sticks and the shared trigger sat between 47.6% and 50.4% of full scale
    ; at rest. So a candidate field whose rest value is nowhere near the middle is
    ; not the field this axis lives in -- most often it means a neighbouring
    ; axis's bytes were picked up instead.
    ;
    ; Triggers are exempt: a separate trigger legitimately rests at zero, and only
    ; a shared one rests at mid-scale.
    static STICK_NAMES := Map("LX", true, "LY", true, "RX", true, "RY", true)
    if STICK_NAMES.Has(step["name"]) {
        fullScale := chosen["size"] = "u8" ? 255 : 65535
        centreFraction := chosen["neutral"] / fullScale
        if (centreFraction < 0.35 || centreFraction > 0.65) {
            return ControllerLearnRejectAxis(step,
                "byte " chosen["offset"] " " chosen["size"] " rests at "
                . Round(centreFraction * 100) "% of range, and a stick rests at "
                . "the centre")
        }
    }
    ; decoded = (raw - neutral) * k, and at the prompted extreme that must carry
    ; the sign `want`. (raw - neutral) has sign s there, so k = want * s.
    want := step["want"]
    direction := (chosen["raw"] < chosen["neutral"]) ? -want : want
    LearnResultAxes[step["name"]] := Map(
        "offset", chosen["offset"],
        "size", chosen["size"],
        "neutral", chosen["neutral"],
        "direction", direction,
        "extent", Max(1, chosen["extent"]))
    LearnPeak := chosen["delta"]
    return true
}

ControllerLearnBufferAxisRaw(report, offset, size) {
    if (size = "u8")
        return NumGet(report, offset, "UChar")
    if (size = "u16be")
        return (NumGet(report, offset, "UChar") << 8)
            | NumGet(report, offset + 1, "UChar")
    return NumGet(report, offset, "UShort")
}

; Measures the farthest point of the outward sweep and how directly it got there.
; Correct endianness produces a nearly monotonic path (coherence near 1);
; interpreting the same bytes backwards wraps repeatedly and scores poorly.
ControllerLearnAxisStats(offset, size) {
    global LearnAxisSamples, LearnBaseline
    neutral := ControllerLearnBufferAxisRaw(LearnBaseline, offset, size)
    previous := neutral
    path := 0
    pathAtPeak := 0
    peakRaw := neutral
    peakIndex := 0
    extent := 0
    for index, report in LearnAxisSamples {
        raw := ControllerLearnBufferAxisRaw(report, offset, size)
        path += Abs(raw - previous)
        previous := raw
        sampleExtent := Abs(raw - neutral)
        if (sampleExtent > extent) {
            extent := sampleExtent
            peakRaw := raw
            peakIndex := index
            pathAtPeak := path
        }
    }
    scale := size = "u8" ? 256 : 1
    delta := extent * scale
    coherence := extent / Max(1, pathAtPeak)
    score := delta * (0.20 + 0.80 * coherence)
    if (size != "u8") {
        highOffset := size = "u16le" ? offset + 1 : offset
        ; The high byte of a real 16-bit field changes progressively as the
        ; control travels. Under the wrong byte order it is the wrapping low
        ; byte instead. Weighting that path prevents one final 0xFF sample from
        ; making the reversed interpretation look like a 65,000-count sweep.
        score *= ControllerLearnHighByteQuality(highOffset, peakIndex)
    }
    return Map(
        "offset", offset,
        "size", size,
        "neutral", neutral,
        "raw", peakRaw,
        "extent", extent,
        "delta", delta,
        "coherence", coherence,
        "score", score)
}

ControllerLearnHighByteQuality(offset, sampleCount) {
    global LearnAxisSamples, LearnBaseline
    previous := NumGet(LearnBaseline, offset, "UChar")
    path := 0
    transitions := 0
    endpoint := previous
    Loop sampleCount {
        report := LearnAxisSamples[A_Index]
        value := NumGet(report, offset, "UChar")
        if (value != previous)
            transitions += 1
        path += Abs(value - previous)
        previous := value
        endpoint := value
    }
    endpoint := Abs(endpoint - NumGet(LearnBaseline, offset, "UChar"))
    coherence := endpoint / Max(1, path)
    activity := transitions / Max(1, sampleCount)
    return (0.25 + 0.75 * coherence) * (0.25 + 0.75 * activity)
}

ControllerLearnRecordButton(name, offset, mask, pressed) {
    global LearnResultButtons
    for _, existing in LearnResultButtons {
        if (existing["name"] = name)
            return
        if (existing["offset"] = offset && existing["mask"] = mask) {
            ; The previous prompt is probably still being held. Do not map two
            ; logical buttons to one physical bit; keep waiting for a new answer.
            return
        }
    }
    LearnResultButtons.Push(Map(
        "name", name, "offset", offset, "mask", mask, "pressed", pressed))
    ControllerLearnAccept(name " = byte " offset " bit 0x"
        . Format("{:02X}", mask) (pressed ? " active-high" : " active-low"),
        offset, mask)
}

; Records a detected button or D-pad direction, then waits for it to be RELEASED
; before moving on.
;
; A fixed delay is not enough here. Detection happens on press, so with a blind
; timer the next prompt can appear while the control is still held -- and the next
; step looks for any bit differing from rest, which the still-held control
; satisfies. The result is the next button being learned as the previous one's
; bit. Releasing is therefore part of the step, and the prompts say so.
ControllerLearnAccept(detail, offset := -1, mask := 0) {
    global LearnDetailCtrl, LearnCaptureUntil, LearnLastAccepted
    global LearnReleaseOffset, LearnReleaseMask, LearnReleaseUntil
    LearnLastAccepted := detail
    try LearnDetailCtrl.Text := "Detected: " detail " -- now let go"
    LogLine("Learn: " detail ".")
    LearnCaptureUntil := 0
    if (offset < 0) {
        SetTimer(ControllerLearnNextStep, -600)
        return
    }
    LearnReleaseOffset := offset
    LearnReleaseMask := mask
    ; Bounded, so a latching or sticky control cannot strand the wizard. The
    ; timeout advances anyway and the log records that the release was not seen.
    LearnReleaseUntil := A_TickCount + 6000
}

; Watches for the accepted control to return to its resting state.
ControllerLearnReleaseCheck(data, base, length) {
    global LearnBaseline, LearnReleaseOffset, LearnReleaseMask, LearnReleaseUntil
    offset := LearnReleaseOffset
    if (offset < 0 || offset >= length)
        return
    now := NumGet(data, base + offset, "UChar")
    was := NumGet(LearnBaseline, offset, "UChar")
    ; A mask of 0 means the whole byte matters, which is the hat case.
    if LearnReleaseMask {
        if ((now & LearnReleaseMask) != (was & LearnReleaseMask))
            return
    } else if (now != was) {
        return
    }
    LearnReleaseOffset := -1
    LearnReleaseMask := 0
    LearnReleaseUntil := 0
    SetTimer(ControllerLearnNextStep, -150)
}

; ------------------------------------------------------------------------------
; Learning wizard UI
; ------------------------------------------------------------------------------
ShowControllerLearner(*) {
    global LearnGui, LearnActive, LearnDevice, LearnDeviceKey, LearnLength
    global LearnBaseline, LearnRestNoise, LearnRestSampling, LearnRestCount
    global LearnStepIndex, LearnResultButtons, LearnResultAxes, LearnHatValues
    global LearnPromptCtrl, LearnDetailCtrl, LearnProgressCtrl, LearnCaptureUntil
    global LearnLastAccepted
    global LearnIdentifyDevices, LearnIdentifyReady
    global SettingsDialogActive, MouseHidden
    global LearnAnalogBytes, LearnAnalogValues, LearnDpadRetries
    global LearnCountdownCtrl
    if LearnActive {
        try WinActivate("ahk_id " LearnGui.Hwnd)
        return
    }
    ; RawInput has to be listening or there is nothing to learn from.
    if !RawInputProbeStart() {
        if !RawInputRegistered() {
            TopmostMsgBox("RawInput is not registered, so no controller reports can be "
                . "read.`n`nSet Input backend to Auto or RawInput, then try again.",
                "Learn controller", "Iconx")
            return
        }
    }
    ; The normal decoder is paused while reports are consumed by the learner.
    ; Clear its cached state first so a pre-wizard held button cannot remain
    ; logically pressed until the stale timeout expires.
    RawInputResetDeviceLock("controller learner opened")
    LearnActive := true
    LearnDevice := 0
    LearnDeviceKey := ""
    LearnLength := 0
    LearnBaseline := 0
    LearnRestNoise := 0
    LearnRestSampling := false
    LearnRestCount := 0
    LearnStepIndex := 0
    LearnAnalogBytes := Map()
    LearnAnalogValues := Map()
    LearnDpadRetries := 0
    LearnResultButtons := []
    LearnResultAxes := Map()
    LearnHatValues := Map()
    LearnLastAccepted := ""
    LearnCaptureUntil := 0
    LearnIdentifyDevices := Map()
    LearnIdentifyReady := false
    ; The pointer is needed for the buttons on this window.
    if MouseHidden {
        SystemCursor("Show")
        MouseHidden := false
    }
    ; Treated as a dialog so the assist features stay out of the way and the
    ; controller's own mappings do not fire while it is being pressed for
    ; learning.
    SettingsDialogActive := true

    learn := Gui("+AlwaysOnTop -MinimizeBox", "Learn Controller")
    learn.Opt("+OwnDialogs")
    learn.MarginX := 24
    learn.MarginY := 18
    learn.SetFont("s14 Bold", "Segoe UI")
    LearnPromptCtrl := learn.AddText("x24 y20 w480 h60 +Wrap",
        "Release every controller for a moment")
    ; A large, always-visible countdown. Several steps are observation windows
    ; that end on a timer, and without a clock the wizard looks like it has hung
    ; rather than like it is waiting for you.
    learn.SetFont("s34 Bold", "Segoe UI")
    LearnCountdownCtrl := learn.AddText("x516 y16 w108 h64 +Right", "")
    learn.SetFont("s10 Norm", "Segoe UI")
    LearnDetailCtrl := learn.AddText("x24 y88 w600 h24",
        "Measuring idle input before device selection...")
    LearnProgressCtrl := learn.AddText("x24 y116 w600 h24", "")
    learn.AddText("x24 y148 w600 h56 +Wrap",
        "Press each button once. For sticks and triggers, move fully as prompted, "
        . "then release. Skip anything this controller does not have.")
    skip := learn.AddButton("x24 y214 w130 h34", "Skip")
    skip.OnEvent("Click", (*) => ControllerLearnSkip())
    restart := learn.AddButton("x164 y214 w130 h34", "Start Over")
    restart.OnEvent("Click", (*) => ControllerLearnRestart())
    save := learn.AddButton("x374 y214 w120 h34", "Save")
    save.OnEvent("Click", (*) => ControllerLearnSave())
    cancel := learn.AddButton("x504 y214 w120 h34", "Cancel")
    cancel.OnEvent("Click", (*) => CloseControllerLearner())
    learn.OnEvent("Close", (*) => CloseControllerLearner())
    learn.OnEvent("Escape", (*) => CloseControllerLearner())
    LearnGui := learn
    foreground := 0
    try foreground := WinExist("A")
    CenterGuiOnMonitorActual(learn, GetMonitorIndexForWindow(foreground), 648, 268)
    try ForceForegroundWindow(learn.Hwnd)
    SetTimer(ControllerLearnIdentificationReady, -1200)
    LogLine("Learn: wizard opened.")
}

RawInputRegistered() {
    global RawInputProbeActive
    return RawInputProbeActive
}

CloseControllerLearner(*) {
    global LearnActive, LearnGui, SettingsDialogActive
    LearnActive := false
    SettingsDialogActive := false
    SetTimer(ControllerLearnTick, 0)
    SetTimer(ControllerLearnBeginSteps, 0)
    SetTimer(ControllerLearnNextStep, 0)
    SetTimer(ControllerLearnIdentificationReady, 0)
    if IsSet(LearnGui) {
        try LearnGui.Destroy()
        LearnGui := unset
    }
    LogLine("Learn: wizard closed.")
}

ControllerLearnRestart() {
    global LearnDevice, LearnDeviceKey, LearnLength, LearnBaseline
    global LearnRestNoise, LearnRestSampling, LearnRestCount
    global LearnStepIndex, LearnResultButtons, LearnResultAxes
    global LearnHatValues, LearnCaptureUntil
    global LearnLastAccepted
    global LearnIdentifyDevices, LearnIdentifyReady
    global LearnAnalogBytes, LearnAnalogValues, LearnDpadRetries
    LearnAnalogBytes := Map()
    LearnAnalogValues := Map()
    LearnDpadRetries := 0
    LearnDevice := 0
    LearnDeviceKey := ""
    LearnLength := 0
    LearnBaseline := 0
    LearnRestNoise := 0
    LearnRestSampling := false
    LearnRestCount := 0
    LearnStepIndex := 0
    LearnResultButtons := []
    LearnResultAxes := Map()
    LearnHatValues := Map()
    LearnLastAccepted := ""
    LearnCaptureUntil := 0
    LearnIdentifyDevices := Map()
    LearnIdentifyReady := false
    SetTimer(ControllerLearnTick, 0)
    SetTimer(ControllerLearnBeginSteps, 0)
    SetTimer(ControllerLearnNextStep, 0)
    SetTimer(ControllerLearnIdentificationReady, -1200)
    ControllerLearnUpdateUi()
}

ControllerLearnIdentificationReady() {
    global LearnActive, LearnDevice, LearnIdentifyReady
    global LearnPromptCtrl, LearnDetailCtrl
    if (!LearnActive || LearnDevice)
        return
    LearnIdentifyReady := true
    try LearnPromptCtrl.Text := "Press and release any button to choose the controller"
    try LearnDetailCtrl.Text := "This selects the device; button mapping starts after rest measurement."
}

; Once a device has been identified, the steps begin.
ControllerLearnUpdateUi() {
    global LearnDevice, LearnStepIndex, LearnPromptCtrl, LearnDetailCtrl
    global LearnLength, LearnDeviceKey, LearnIdentifyReady
    global LearnRestSampling, LearnRestCount
    if !LearnDevice {
        if LearnIdentifyReady {
            try LearnPromptCtrl.Text := "Press and release any button to choose the controller"
            try LearnDetailCtrl.Text := "This selects the device; button mapping starts after rest measurement."
        } else {
            try LearnPromptCtrl.Text := "Release every controller for a moment"
            try LearnDetailCtrl.Text := "Measuring idle input before device selection..."
        }
        return
    }
    if (LearnStepIndex = 0) {
        try LearnPromptCtrl.Text := "Let go of everything"
        try LearnDetailCtrl.Text := "Device " LearnDeviceKey ", " LearnLength
            . "-byte reports. Measuring the resting state..."
        LearnRestSampling := true
        LearnRestCount := 0
        SetTimer(ControllerLearnBeginSteps, -1800)
    }
}

; Ends rest sampling and starts prompting.
;
; The resting measurement matters more than anything else here. Every detection
; is a difference from it, and the set of bits seen at rest is what stops a
; jittering analogue axis from being learned as a button.
ControllerLearnBeginSteps() {
    global LearnActive, LearnStepIndex, LearnRestSampling, LearnRestCount
    global LearnRestNoise, LearnLength
    if !LearnActive
        return
    LearnRestSampling := false
    noisy := 0
    Loop LearnLength {
        if NumGet(LearnRestNoise, A_Index - 1, "UChar")
            noisy += 1
    }
    LogLine("Learn: rest sampled from " LearnRestCount " report"
        . (LearnRestCount = 1 ? "" : "s") "; " noisy " of " LearnLength
        . " bytes changed during rest.")
    if (LearnRestCount = 0) {
        ; Some controllers only report on change, so silence at rest is normal
        ; and the idle report captured before the identifying press is retained.
        ; Worth recording, because it also means a missed press produces no
        ; report to examine.
        LogLine("Learn: no reports while at rest; this controller reports only "
            . "on change. Using the pre-selection idle report as the baseline.")
    }
    LearnStepIndex := 1
    ControllerLearnStartCapture()
    SetTimer(ControllerLearnTick, 100)
}

ControllerLearnStartCapture() {
    global LearnCaptureUntil, LearnPeak, LearnPromptCtrl, LearnProgressCtrl
    global LearnStepIndex, LearnDetailCtrl, LearnLength
    global LearnExcursion, LearnAxisSamples, LearnAxisStarted, LearnResultAxes
    global LearnLastAccepted
    global LearnReleaseOffset, LearnReleaseMask, LearnReleaseUntil
    global LearnStepReports
    steps := ControllerLearnSteps()
    if (LearnStepIndex > steps.Length) {
        ControllerLearnFinish()
        return
    }
    step := steps[LearnStepIndex]
    LearnPeak := 0
    ; Any release the previous step was waiting on is no longer relevant; Skip and
    ; Start Over both arrive here.
    LearnReleaseOffset := -1
    LearnReleaseMask := 0
    LearnReleaseUntil := 0
    LearnStepReports := 0
    LearnExcursion := Buffer(Max(1, LearnLength), 0)
    LearnAxisSamples := []
    LearnAxisStarted := false
    if (step["kind"] = "axis" && LearnResultAxes.Has(step["name"]))
        LearnResultAxes.Delete(step["name"])
    ; The axis deadline is only a retry watchdog. Normal completion happens when
    ; the requested control returns to neutral.
    ; The scan is a fixed observation window rather than something that can be
    ; "answered", so it runs on a timer of its own.
    if (step["kind"] = "wiggle") {
        LearnCaptureUntil := A_TickCount + 12000
    } else if (step["kind"] = "axis") {
        LearnCaptureUntil := A_TickCount + 30000
    } else if step.Has("optional") {
        ; The Guide button in particular is usually swallowed by Windows and never
        ; reaches the HID report, so waiting the full time for it just stalls the
        ; wizard before the D-pad steps.
        LearnCaptureUntil := A_TickCount + 8000
    } else {
        LearnCaptureUntil := A_TickCount + 20000
    }
    try LearnPromptCtrl.Text := step["prompt"]
    try LearnProgressCtrl.Text := "Step " LearnStepIndex " of " steps.Length
    ; Braces required: a braceless `if` body that is a `try` lets the following
    ; `else` bind to the try, which is a syntax error without a catch.
    if (step["kind"] = "axis") {
        try LearnDetailCtrl.Text := "Move to the requested edge, then let it return to rest."
    } else {
        detail := LearnLastAccepted != "" ? "Last detected: " LearnLastAccepted
            : "Waiting for the press report..."
        try LearnDetailCtrl.Text := detail
    }
}

ControllerLearnNextStep() {
    global LearnActive, LearnStepIndex
    if !LearnActive
        return
    steps := ControllerLearnSteps()
    finished := LearnStepIndex
    LearnStepIndex += 1
    ; The four D-pad directions are only meaningful as a set, so they are checked
    ; once the last one is in rather than individually.
    if (finished >= 1 && finished <= steps.Length
        && steps[finished]["kind"] = "dpad"
        && (LearnStepIndex > steps.Length
            || steps[LearnStepIndex]["kind"] != "dpad")) {
        if !ControllerLearnValidateDpad()
            return
    }
    ControllerLearnStartCapture()
}

; Checks the four D-pad directions as a set, and retries them once if they do not
; describe a real D-pad.
;
; A slightly diagonal press is the failure this catches. On a hat, up-and-right
; reads as the diagonal value rather than the cardinal -- so "Up" gets recorded as
; 2 instead of 1, the four values stop being evenly spaced, the hat is rejected,
; and the bit fallback then collides because 3 and 5 share their lowest bit. One
; imprecise press quietly ruins the whole D-pad, so it is worth detecting and
; simply asking again.
;
; Returns true to carry on, false when it has rewound for a retry.
ControllerLearnValidateDpad() {
    global LearnHatValues, LearnStepIndex, LearnDpadRetries
    global LearnDetailCtrl, LearnPromptCtrl
    static DIRECTIONS := ["Up", "Right", "Down", "Left"]
    ; A clean hat is the best outcome and needs no further checking.
    if (ControllerLearnHatText() != "")
        return true
    ; Otherwise it must be four distinct single bits, which is the other real
    ; D-pad shape.
    seen := Map()
    distinctBits := 0
    for _, name in DIRECTIONS {
        if !LearnHatValues.Has(name)
            continue
        entry := LearnHatValues[name]
        mask := entry["value"] & ~entry["released"] & 0xFF
        ; Exactly one bit set.
        if (!mask || (mask & (mask - 1)))
            continue
        key := entry["offset"] ":" mask
        if seen.Has(key)
            continue
        seen[key] := true
        distinctBits += 1
    }
    if (distinctBits = DIRECTIONS.Length)
        return true
    if (LearnDpadRetries >= 1) {
        LogLine("Learn: D-pad still inconsistent after a retry; saving whatever "
            . "was captured. Check the Hat and Buttons lines in the profile.",
            "Warning")
        return true
    }
    LearnDpadRetries += 1
    for _, name in DIRECTIONS
        LearnHatValues.Delete(name)
    ; Rewind to the first D-pad step. StartCapture is called from the timer below.
    steps := ControllerLearnSteps()
    Loop steps.Length {
        if (steps[A_Index]["kind"] = "dpad") {
            LearnStepIndex := A_Index
            break
        }
    }
    LogLine("Learn: the four D-pad directions do not describe a hat or four "
        . "distinct bits, most likely a diagonal press. Retrying them.", "Warning")
    try LearnPromptCtrl.Text := "Let us try the D-pad again"
    try LearnDetailCtrl.Text := "Press each direction squarely — a diagonal reads "
        . "as its own value and breaks the set."
    SetTimer(ControllerLearnStartCapture, -1500)
    return false
}

ControllerLearnSkip() {
    global LearnActive, LearnStepIndex, LearnLastAccepted, LearnResultAxes
    ; The upper bound matters as much as the lower one. ControllerLearnNextStep
    ; increments unconditionally, so after the final step LearnStepIndex sits one
    ; past the end while the wizard finishes and saves. Skip is a GUI button and
    ; can be clicked inside that window, which indexed the step array out of
    ; range and threw "Invalid index" on a controller whose last steps were being
    ; skipped anyway.
    if (!LearnActive || LearnStepIndex < 1
        || LearnStepIndex > ControllerLearnSteps().Length)
        return
    LogLine("Learn: step " LearnStepIndex " skipped.")
    step := ControllerLearnSteps()[LearnStepIndex]
    ; Skipping mid-gesture must discard the provisional answer too. It was
    ; measured from an incomplete sweep, so its neutral and extent are both wrong,
    ; and a wrong extent is what sends the pointer across the screen.
    if (step["kind"] = "axis" && LearnResultAxes.Has(step["name"]))
        LearnResultAxes.Delete(step["name"])
    LearnLastAccepted := step["name"] " skipped"
    ControllerLearnNextStep()
}

ControllerLearnCompleteAxis(step) {
    global LearnCaptureUntil, LearnResultAxes, LearnLastAccepted
    global LearnDetailCtrl, LearnPeak, LearnAxisRejection
    LearnCaptureUntil := 0
    if ControllerLearnResolveAxis(step) {
        axis := LearnResultAxes[step["name"]]
        LearnLastAccepted := step["name"] " = byte " axis["offset"] " "
            . axis["size"] " neutral " axis["neutral"] " direction "
            . axis["direction"]
        try LearnDetailCtrl.Text := "Detected: " LearnLastAccepted
        LogLine("Learn: " LearnLastAccepted ".")
        SetTimer(ControllerLearnNextStep, -700)
    } else {
        LearnLastAccepted := step["name"] " not detected"
        try LearnDetailCtrl.Text := "Not detected — release everything, then move "
            . "it all the way and hold for a moment."
        LogLine("Learn: " step["name"] " not detected -- "
            . (LearnAxisRejection != "" ? LearnAxisRejection : "no reason recorded")
            . ". Retrying.", "Warning")
        SetTimer(ControllerLearnStartCapture, -900)
    }
}

; Analogue steps normally finish on release. This timer only recovers from an
; incomplete gesture instead of silently advancing with a held value.
ControllerLearnTick() {
    global LearnActive, LearnCaptureUntil, LearnStepIndex
    global LearnLastAccepted, LearnDetailCtrl, LearnProgressCtrl
    global LearnReleaseOffset, LearnReleaseMask, LearnReleaseUntil
    global LearnStepReports, LearnCountdownCtrl
    if !LearnActive
        return
    ; The countdown, and live evidence that reports are arriving at all. Without
    ; the latter, a step that rejects everything looks identical to a controller
    ; that has gone silent.
    if LearnCaptureUntil {
        try LearnCountdownCtrl.Text := Max(0,
            Round((LearnCaptureUntil - A_TickCount) / 1000))
    } else {
        try LearnCountdownCtrl.Text := ""
    }
    if (LearnStepIndex >= 1 && LearnCaptureUntil) {
        steps := ControllerLearnSteps()
        if (LearnStepIndex <= steps.Length) {
            try LearnProgressCtrl.Text := "Step " LearnStepIndex " of "
                . steps.Length "  -  " LearnStepReports " report"
                . (LearnStepReports = 1 ? "" : "s") " seen"
        }
    }
    ; A release we never saw. Advance anyway rather than stranding the wizard on a
    ; latching control, and say so, because the next step may misread the still
    ; active input.
    if (LearnReleaseOffset >= 0) {
        if (LearnReleaseUntil && A_TickCount >= LearnReleaseUntil) {
            LogLine("Learn: release of byte " LearnReleaseOffset " was never seen; "
                . "continuing anyway.", "Warning")
            LearnReleaseOffset := -1
            LearnReleaseMask := 0
            LearnReleaseUntil := 0
            SetTimer(ControllerLearnNextStep, -150)
        }
        return
    }
    if (!LearnCaptureUntil || A_TickCount < LearnCaptureUntil)
        return
    steps := ControllerLearnSteps()
    if (LearnStepIndex < 1 || LearnStepIndex > steps.Length)
        return
    step := steps[LearnStepIndex]
    if (step["kind"] = "wiggle") {
        LearnCaptureUntil := 0
        found := ControllerLearnClassifyAnalog()
        LearnLastAccepted := found " analogue byte" (found = 1 ? "" : "s") " found"
        try LearnDetailCtrl.Text := found " analogue byte"
            . (found = 1 ? "" : "s") " found; buttons will ignore them."
        SetTimer(ControllerLearnNextStep, -600)
        return
    }
    ; A digital step that never saw its control moves on by itself.
    ;
    ; The controller is deliberately inert while the wizard is open, so Skip can
    ; only be reached with a mouse or the touchscreen. Without this, a control the
    ; pad does not have -- a Guide button hidden by its driver, say -- would stall
    ; the whole wizard for anyone holding only a controller.
    if (step["kind"] != "axis") {
        LearnCaptureUntil := 0
        LearnLastAccepted := step["name"] " not detected"
        try LearnDetailCtrl.Text := "Not detected — skipping " step["name"] "."
        LogLine("Learn: " step["name"] " timed out; skipped.", "Warning")
        SetTimer(ControllerLearnNextStep, -400)
        return
    }
    LearnCaptureUntil := 0
    LearnLastAccepted := step["name"] " timed out"
    try LearnDetailCtrl.Text := "Timed out — release everything; retrying this step."
    LogLine("Learn: " step["name"] " timed out before returning to rest. Retrying.",
        "Warning")
    SetTimer(ControllerLearnStartCapture, -1200)
}

ControllerLearnFinish() {
    global LearnPromptCtrl, LearnDetailCtrl, LearnProgressCtrl, LearnCaptureUntil
    global LearnResultButtons, LearnResultAxes, LearnHatValues
    LearnCaptureUntil := 0
    SetTimer(ControllerLearnTick, 0)
    try LearnPromptCtrl.Text := "Done — review and save"
    learnedButtons := LearnResultButtons.Length + Min(4, LearnHatValues.Count)
    try LearnProgressCtrl.Text := learnedButtons " buttons/D-pad directions, "
        . LearnResultAxes.Count " axes learned"
    try LearnDetailCtrl.Text := "Save writes the profile and activates it immediately."
}

; Writes the learned profile and refreshes the decoder cache immediately.
ControllerLearnSave() {
    global LearnDeviceKey, LearnLength, LearnResultButtons, LearnResultAxes
    global LearnHatValues, LearnDevice, LearnPromptCtrl, LearnDetailCtrl
    if (LearnLength <= 0 || !LearnDevice) {
        TopmostMsgBox("No controller was identified yet.", "Learn controller", "Iconx")
        return
    }
    if (LearnDeviceKey = "")
        LearnDeviceKey := RawInputDeviceKey(LearnDevice, true)
    ; Windows will not identify this device by any of the three routes. Rather than
    ; discard a completed wizard, save the profile keyed on report length -- the
    ; same thing the built-in layout matches on, so nothing is made less safe.
    identityFallback := false
    if (LearnDeviceKey = "") {
        LogLine("Learn: reports were captured from device 0x"
            . Format("{:X}", LearnDevice)
            . ", but Windows returned no device path, HID VID/PID, or "
            . "preparsed descriptor. Saving keyed on the "
            . LearnLength "-byte report length instead.",
            "Warning")
        LearnDeviceKey := ControllerProfileLengthKey(LearnLength)
        identityFallback := true
    }
    if (LearnResultButtons.Length = 0 && LearnResultAxes.Count = 0
        && LearnHatValues.Count = 0) {
        TopmostMsgBox("Nothing was learned, so there is no profile to save.",
            "Learn controller", "Iconx")
        return
    }
    path := ControllerProfilePath()
    ; A hat is only written when the four directions form an evenly spaced
    ; sequence on one byte. Otherwise the D-pad is bits, and the values recorded
    ; per direction become ordinary button entries.
    hatText := ControllerLearnHatText()
    buttons := LearnResultButtons.Clone()
    if (hatText = "") {
        dpadButtons := ControllerLearnDpadButtons()
        if IsObject(dpadButtons) {
            for _, button in dpadButtons
                buttons.Push(button)
        } else if (LearnHatValues.Count > 0) {
            LogLine("Learn: D-pad values were neither a regular hat nor four "
                . "independent bits; leaving the D-pad unmapped.", "Warning")
        }
    }
    buttonText := ""
    for _, button in buttons {
        buttonText .= (buttonText != "" ? "|" : "")
            . button["name"] ":" button["offset"] ":" button["mask"]
            . ":" button["pressed"]
    }
    axisText := ""
    for name, axis in LearnResultAxes {
        axisText .= (axisText != "" ? "|" : "")
            . name ":" axis["offset"] ":" axis["size"] ":" axis["neutral"]
            . ":" axis["direction"] ":" axis["extent"]
    }
    try {
        IniWrite(LearnLength, path, LearnDeviceKey, "ReportLength")
        IniWrite(ShortenText(RawInputDeviceName(LearnDevice), 120), path,
            LearnDeviceKey, "Name")
        IniWrite(buttonText, path, LearnDeviceKey, "Buttons")
        IniWrite(axisText, path, LearnDeviceKey, "Axes")
        IniWrite(hatText, path, LearnDeviceKey, "Hat")
        ; Recorded so a length-keyed profile is identifiable as the fallback it is.
        IniWrite(identityFallback ? "length" : "device", path, LearnDeviceKey,
            "IdentityFallback")
    } catch as err {
        TopmostMsgBox("Could not write the profile:`n`n" err.Message,
            "Learn controller", "Iconx")
        return
    }
    LogLine("Learn: saved profile '" LearnDeviceKey "' with " buttons.Length
        . " buttons, " LearnResultAxes.Count " axes, D-pad as "
        . (hatText != "" ? "a hat" : "bits") ".")
    if !IsObject(LoadControllerProfile(LearnDeviceKey, true)) {
        TopmostMsgBox("The profile was written but did not pass validation. Check "
            . ControllerProfilePath() " and the log before trying again.",
            "Learn controller", "Iconx")
        return
    }
    RawInputResetDeviceLock("controller profile saved")
    CloseControllerLearner()
    ; A bad axis reading does not fail quietly -- it drives the pointer across the
    ; screen and makes the machine hard to use. Verify the profile against the
    ; controller at rest before leaving the user with it.
    ControllerProfileRestCheckBegin()
    TopmostMsgBox("Profile saved and activated for " LearnDeviceKey ".",
        "Learn controller", "Iconi")
}

; Checks a freshly saved profile decodes to neutral while nothing is touched.
;
; An axis learned with the wrong neutral, direction or extent reads as permanently
; deflected, and the controller mouse then flies across the screen -- which also
; makes it hard to reach Settings to undo. If any stick is pegged with the
; controller at rest this says so plainly and offers to delete the profile there
; and then.
;
; Sampled over a WINDOW rather than at one instant. A statically mis-learned axis
; reads wrong in every report, so one sample would find it -- but an axis
; mis-bound to a motion sensor oscillates, and a single sample can catch it as it
; passes through neutral. That is not hypothetical: the 8BitDo Ultimate 2 that
; motivated the free-running filter had RT bound to a gyro byte, and the axis a
; motion sensor is bound to is exactly the axis that will not hold still. Peak
; magnitude across the window is what a pegged axis cannot hide from.
ControllerProfileRestCheckBegin() {
    global RestCheckPeak, RestCheckSamples
    RestCheckPeak := Map("LX", 0, "LY", 0, "RX", 0, "RY", 0, "LT", 0, "RT", 0)
    RestCheckSamples := 0
    SetTimer(ControllerProfileRestCheck, 120)
}

ControllerProfileRestCheck() {
    global RawInputState, RawInputLastReportTick, ControllerDeadzone
    global RestCheckPeak, RestCheckSamples
    static WINDOW_SAMPLES := 12          ; ~1.4 s at the 120 ms tick
    if !RawInputLastReportTick {
        SetTimer(ControllerProfileRestCheck, 0)
        return
    }
    RestCheckSamples += 1
    for name, offset in Map("LX", 8, "LY", 10, "RX", 12, "RY", 14) {
        value := Abs(NumGet(RawInputState, offset, "Short"))
        if (value > RestCheckPeak[name])
            RestCheckPeak[name] := value
    }
    for name, offset in Map("LT", 6, "RT", 7) {
        value := NumGet(RawInputState, offset, "UChar")
        if (value > RestCheckPeak[name])
            RestCheckPeak[name] := value
    }
    if (RestCheckSamples < WINDOW_SAMPLES)
        return
    SetTimer(ControllerProfileRestCheck, 0)

    ; Generous: this is looking for an axis that is pegged, not for drift.
    limit := Max(ControllerDeadzone * 2, 12000)
    offenders := ""
    for _, name in ["LX", "LY", "RX", "RY"] {
        if (RestCheckPeak[name] > limit)
            offenders .= (offenders != "" ? ", " : "") name "=" RestCheckPeak[name]
    }
    for _, name in ["LT", "RT"] {
        if (RestCheckPeak[name] > 80)
            offenders .= (offenders != "" ? ", " : "") name "=" RestCheckPeak[name]
    }
    if (offenders = "") {
        LogLine("Controller profile: rest check passed over " RestCheckSamples
            . " samples; all axes read neutral.")
        return
    }
    LogLine("Controller profile: rest check FAILED over " RestCheckSamples
        . " samples. Peak with nothing touched: " offenders
        . ". The pointer will drift or run away.", "Error")
    answer := TopmostMsgBox("The saved controller profile reads as if the controller is "
        . "being held, with nothing touched:`n`n" offenders "`n`n"
        . "This makes the pointer run across the screen. Delete the profile and "
        . "go back to the built-in layout?`n`n"
        . "Choose No to keep it and re-learn the sticks yourself.",
        "Controller profile looks wrong", "YesNo Icon!")
    if (answer = "Yes")
        DeleteControllerProfileForActiveDevice()
}

; Removes the profile in use for the device currently being decoded.
;
; The escape hatch for a bad profile. It has to work without the pointer, because
; a bad profile is precisely what takes the pointer away, so it is also on
; Ctrl+Alt+Shift+D.
DeleteControllerProfileForActiveDevice(*) {
    global RawInputDevice
    key := ""
    if RawInputDevice
        key := RawInputDeviceKey(RawInputDevice, true)
    path := ControllerProfilePath()
    removed := ""
    ; Both the identity key and the length-keyed fallback are candidates, and the
    ; fallback is the one a device Windows will not identify ended up under.
    for _, candidate in [key, ControllerProfileLengthKey(16)] {
        if (candidate = "")
            continue
        length := 0
        try length := Integer(IniRead(path, candidate, "ReportLength", "0"))
        if (length <= 0)
            continue
        try {
            IniDelete(path, candidate)
            removed .= (removed != "" ? ", " : "") candidate
        }
    }
    if (removed = "") {
        SetStatus("No controller profile to delete")
        LogLine("Controller profile: nothing to delete.")
        return
    }
    LogLine("Controller profile: deleted " removed ". Reloading.", "Warning")
    Reload()
}

; Builds the hat line, or "" when the D-pad was learned as ordinary bits.
;
; The eight-way table is derived from the four cardinals that were observed:
; hats number their positions clockwise from north, so once north and east are
; known the diagonals follow. A hat whose four cardinals are not evenly spaced is
; not one this can describe, and is rejected rather than guessed at.
ControllerLearnHatText() {
    global LearnHatValues
    for _, name in ["Up", "Right", "Down", "Left"] {
        if !LearnHatValues.Has(name)
            return ""
    }
    offset := LearnHatValues["Up"]["offset"]
    released := LearnHatValues["Up"]["released"]
    for _, name in ["Right", "Down", "Left"] {
        if (LearnHatValues[name]["offset"] != offset
            || LearnHatValues[name]["released"] != released)
            return ""
    }
    up := LearnHatValues["Up"]["value"]
    right := LearnHatValues["Right"]["value"]
    down := LearnHatValues["Down"]["value"]
    left := LearnHatValues["Left"]["value"]
    step := right - up
    if (step <= 0 || down - up != step * 2 || left - up != step * 3)
        return ""
    values := []
    mask := 0
    Loop 8 {
        value := up + Round((A_Index - 1) * step / 2)
        if (value < 0 || value > 255)
            return ""
        values.Push(value)
        mask |= value ^ released
    }
    if !mask
        return ""
    ; Store only the hat bits. Many common HID reports put a four-bit hat and
    ; face buttons in the same byte; whole-byte matching would make the D-pad
    ; disappear whenever one of those buttons was held.
    text := offset ":" mask ":" (released & mask)
    for _, value in values
        text .= ":" (value & mask)
    return text
}

; Returns four active-high or active-low button entries when the D-pad is made
; from independent bits. A non-regular hat is not guessed into bits: doing so can
; map several directions to the same lowest bit and is worse than leaving it
; explicitly unmapped.
ControllerLearnDpadButtons() {
    global LearnHatValues, LearnResultButtons
    buttons := []
    used := Map()
    for _, button in LearnResultButtons
        used[button["offset"] ":" button["mask"]] := true
    for _, name in ["Up", "Right", "Down", "Left"] {
        if !LearnHatValues.Has(name)
            return 0
        entry := LearnHatValues[name]
        changed := (entry["value"] ^ entry["released"]) & 0xFF
        if (!changed || (changed & (changed - 1)))
            return 0
        key := entry["offset"] ":" changed
        if used.Has(key)
            return 0
        used[key] := true
        buttons.Push(Map(
            "name", name,
            "offset", entry["offset"],
            "mask", changed,
            "pressed", entry["value"] & changed))
    }
    return buttons
}

; RawInput is event-driven, so the poll loop reads the most recent decoded
; report. Reports stop arriving entirely outside Xbox FSE, so a stale cache is
; cleared to neutral rather than left holding a button down forever.
RawInputReadState(&state) {
    global RawInputState, RawInputLastReportTick, RawInputStaleMs
    if !RawInputLastReportTick
        return false
    if (A_TickCount - RawInputLastReportTick > RawInputStaleMs) {
        if (NumGet(RawInputState, 4, "UShort") || NumGet(RawInputState, 6, "UChar")
            || NumGet(RawInputState, 7, "UChar")) {
            NumPut("UInt", 0, RawInputState, 0)
            NumPut("UInt", 0, RawInputState, 4)
            NumPut("UInt", 0, RawInputState, 8)
            NumPut("UInt", 0, RawInputState, 12)
        }
        return false
    }
    if !IsObject(state)
        state := Buffer(16, 0)
    Loop 16
        NumPut("UChar", NumGet(RawInputState, A_Index - 1, "UChar"), state, A_Index - 1)
    return true
}

XInputGetCapabilities(index, &caps) {
    global XInputDll
    if (XInputDll = "" && !InitXInput())
        return 1167
    if !IsObject(caps)
        caps := Buffer(20, 0)
    try {
        return DllCall(XInputDll "\XInputGetCapabilities", "UInt", index,
            "UInt", 0, "Ptr", caps, "UInt")
    } catch {
        return 1
    }
}

; ==============================================================================
; Controller diagnostics
; ==============================================================================
; Samples EVERY XInput slot plus GameInput on one tick and logs the combined
; state whenever it changes.
;
; The normal poll stops at the first slot that answers, which cannot tell a
; genuinely filtered pad from a virtualised one. When something captures a
; physical controller and re-publishes a partial copy, the giveaway is two
; devices present at once where one forwards only a subset of the buttons. The
; reported capabilities (type/subtype/flags) also tend to differ between real
; and synthesised devices. Logging the foreground process alongside them shows
; which application owned focus at the moment a button went missing.
ControllerDiagnosticTick() {
    global EnableControllerDiagnostics, ControllerBackend, ActiveInputBackend
    global GameInputReady, GameInputFailed
    global GameInputLastRawButtons, GameInputLastHr
    static lastSignature := ""
    static capsLogged := Map()
    static lastKeepaliveTick := 0

    if !EnableControllerDiagnostics
        return

    ; Initialise GameInput for OBSERVATION even when it is not the active input
    ; backend. The comparison between the two stacks is the entire point of this
    ; diagnostic, and it must not force the user to route real input through the
    ; less-proven backend just to collect it.
    if (!GameInputReady && !GameInputFailed)
        InitGameInput()

    slotText := ""
    signature := ""
    Loop 4 {
        index := A_Index - 1
        slotState := Buffer(16, 0)
        if (XInputGetState(index, &slotState) != 0) {
            slotText .= " s" index "=-"
            signature .= "-|"
            continue
        }
        buttons := NumGet(slotState, 4, "UShort")
        lt := NumGet(slotState, 6, "UChar")
        rt := NumGet(slotState, 7, "UChar")
        slotText .= " s" index "=0x" Format("{:04X}", buttons)
        if (lt > 30 || rt > 30)
            slotText .= "(LT" lt "/RT" rt ")"
        signature .= buttons "," lt "," rt "|"
        ; Capabilities are static per device, so report them once per slot.
        if !capsLogged.Has(index) {
            capsLogged[index] := true
            caps := Buffer(20, 0)
            if (XInputGetCapabilities(index, &caps) = 0) {
                LogLine("Diag slot " index " capabilities:"
                    . " type=" NumGet(caps, 0, "UChar")
                    . " subtype=" NumGet(caps, 1, "UChar")
                    . " flags=0x" Format("{:04X}", NumGet(caps, 2, "UShort"))
                    . " buttonmask=0x" Format("{:04X}", NumGet(caps, 4, "UShort")))
            } else {
                LogLine("Diag slot " index " capabilities unavailable.")
            }
        }
    }

    giText := "off"
    if GameInputReady {
        giState := Buffer(16, 0)
        if GameInputReadState(&giState) {
            giText := "0x" Format("{:04X}", NumGet(giState, 4, "UShort"))
                . " raw=0x" Format("{:08X}", GameInputLastRawButtons)
            signature .= GameInputLastRawButtons
        } else {
            giText := "noreading hr=0x" Format("{:08X}", GameInputLastHr & 0xFFFFFFFF)
            signature .= "none"
        }
    } else if GameInputFailed {
        giText := "initfailed"
    }

    ; Change-only logging cannot distinguish a process reading constant zeros
    ; from one that has been suspended or killed: both go silent. An unconditional
    ; keepalive line every few seconds makes silence unambiguous evidence that the
    ; companion stopped running, rather than something needing interpretation.
    unchanged := signature = lastSignature
    if (unchanged && lastKeepaliveTick && A_TickCount - lastKeepaliveTick < 5000)
        return
    lastKeepaliveTick := A_TickCount
    lastSignature := signature

    foreground := "unknown"
    try foreground := WinGetProcessName("A")
    LogLine("Diag " (unchanged ? "(alive) " : "") ControllerBackend "/" ActiveInputBackend
        . slotText " | GI=" giText " | fg=" foreground)
}

XInputResolveController(&state) {
    global ControllerIndex, ActiveControllerIndex
    static lastMissingLogTick := 0

    ; Prefer the last controller that answered, then the configured index,
    ; then scan every remaining XInput slot. Steam Input and Xbox mode can
    ; reorder physical/virtual controllers without restarting this process.
    candidates := []
    seen := Map()
    if (ActiveControllerIndex >= 0 && ActiveControllerIndex <= 3) {
        candidates.Push(ActiveControllerIndex)
        seen[ActiveControllerIndex] := true
    }
    if !seen.Has(ControllerIndex) {
        candidates.Push(ControllerIndex)
        seen[ControllerIndex] := true
    }
    Loop 4 {
        index := A_Index - 1
        if !seen.Has(index)
            candidates.Push(index)
    }

    for _, index in candidates {
        if (XInputGetState(index, &state) = 0) {
            if (ActiveControllerIndex != index) {
                oldIndex := ActiveControllerIndex
                ActiveControllerIndex := index
                if (oldIndex < 0)
                    LogLine("XInput controller connected on slot " index ".")
                else
                    LogLine("XInput controller moved from slot " oldIndex " to slot " index ".")
            }
            return true
        }
    }

    if (ActiveControllerIndex >= 0) {
        LogLine("XInput controller disconnected from slot " ActiveControllerIndex ".", "Warning")
        ActiveControllerIndex := -1
        lastMissingLogTick := A_TickCount
    } else if (!lastMissingLogTick || A_TickCount - lastMissingLogTick >= 30000) {
        LogLine("No XInput controller detected on slots 0–3.", "Warning")
        lastMissingLogTick := A_TickCount
    }
    return false
}

ExecuteControllerBinding(key) {
    value := GetBindingValue(key)
    if (value = "" || value = "Builtin:None")
        return
    if (SubStr(value, 1, 5) = "Send:") {
        shortcut := SubStr(value, 6)
        if (shortcut != "")
            SendChordSafe(shortcut)
        return
    }
    if (SubStr(value, 1, 8) != "Builtin:")
        return
    action := SubStr(value, 9)
    switch action {
        case "LeftClick":
            try Click("Left")
        case "RightClick":
            try Click("Right")
        case "Enter":
            try SendInput("{Enter}")
        case "Esc":
            try SendInput("{Esc}")
        case "AltF4":
            SendChordSafe("!{F4}")
        case "TabTip":
            OpenTouchKeyboard()
        case "OSK":
            OpenOSK()
        case "WinG":
            SendChordSafe("#g")
        case "StartMenu":
            try SendInput("{LWin}")
        case "Explorer":
            try Run("explorer.exe")
        case "CtrlAltTab":
            SendChordSafe("^!{Tab}")
        case "TaskManager":
            SendChordSafe("^+{Esc}")
        case "TaskView":
            SendChordSafe("#{Tab}")
        case "WindowsDesktop":
            ; Win+D. The previous Win+F11 is not a Windows shortcut at all, so
            ; this action had never done anything.
            SendChordSafe("#d")
        case "QuickMenu":
            ToggleQuickMenu()
        case "Settings":
            ShowSettings()
    }
}


ControllerBindingPretty(key) {
    global ControllerMapDisplay
    value := GetBindingValue(key)
    if (value = "")
        return "None"
    if (SubStr(value, 1, 5) = "Send:") {
        ; The stored display text only wins if there IS some. `try return` falls
        ; through on a THROW, so an entry that exists and is empty returned a
        ; blank label rather than the shortcut -- the row simply went nameless.
        ; Standalone tests the value; this now does too.
        display := ""
        try display := ControllerMapDisplay[key]
        return display != "" ? display : SendToPretty(SubStr(value, 6))
    }
    if (SubStr(value, 1, 8) = "Builtin:") {
        action := SubStr(value, 9)
        labels := Map(
            "None", "None", "LeftClick", "Left click", "RightClick", "Right click",
            "Enter", "Enter", "Esc", "Back / Escape", "AltF4", "Close window",
            "TabTip", "Touch keyboard", "OSK", "Classic keyboard",
            "WinG", "Game Bar", "StartMenu", "Start menu", "Explorer", "File Explorer",
            "CtrlAltTab", "Application switcher", "TaskManager", "Task Manager",
            "TaskView", "Task View", "WindowsDesktop", "Windows desktop",
            "QuickMenu", "Quick Menu", "Settings", "Settings"
        )
        return labels.Has(action) ? labels[action] : action
    }
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
        SetStatus("Enable RTSS integration in Settings first", "Warning")
        return
    }
    if ProcessExist("RTSS.exe") {
        SetStatus("RTSS is already running")
        SetTimer(RefreshQuickMenuAfterRtssStart, -100)
        return
    }
    SetStatus("Starting RTSS…")
    if EnsureRtssRunning() {
        SetStatus("RTSS started")
        ; ProcessWait confirms the executable, but its hooks DLL and shared state
        ; can take another moment to become queryable. Rebuild once after that
        ; settles so Start RTSS becomes the live state rows and the shorter page
        ; is measured/re-centred.
        SetTimer(RefreshQuickMenuAfterRtssStart, -600)
    } else {
        SetStatus("RTSS did not start", "Warning")
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

; Resolves the View button's own action, on release.
;
; View is also the mapping modifier, so this only runs when nothing else was
; touched during the hold -- otherwise "hold View, press A" would fire a Steam
; shortcut underneath the mapping. Resolving on release rather than at a timer
; is what makes that possible.
;
;   Steam in front   tap  -> Steam menu        hold -> Steam Quick Access
;   Game in front    tap  -> nothing           hold -> Steam overlay
;
; The tap doing nothing in a game is deliberate: the companion never blocks
; input, so the game receives View normally and keeps its own use of it.
ViewButtonReleased(heldMs, usedAsModifier) {
    global EnableViewSteamActions, EnableViewTapAction, EnableViewHoldAction
    global ViewHoldMs, ViewHoldInGameMs
    global SteamMenuShortcut, SteamQuickAccessShortcut, SteamOverlayShortcut
    if (!EnableViewSteamActions || usedAsModifier)
        return
    steamFront := SteamIsInFront()
    ; In a game the threshold is longer: View is commonly the scoreboard or map
    ; button there and gets held on purpose, so a short threshold would keep
    ; throwing the Steam overlay up during play.
    threshold := steamFront ? ViewHoldMs : ViewHoldInGameMs
    ; Tap and hold are switched independently. A disabled hold still counts as a
    ; hold rather than falling through to the tap action -- releasing after a
    ; long press must never send the shortcut the short press would have.
    if (heldMs >= threshold) {
        if !EnableViewHoldAction
            return
        shortcut := steamFront ? SteamQuickAccessShortcut : SteamOverlayShortcut
        LogLine("View held " heldMs "ms (threshold " threshold ") -> "
            . (steamFront ? "Steam Quick Access" : "Steam overlay")
            . " (" SendToPretty(shortcut) ").")
        if steamFront
            SendChordSafe(shortcut)
        else
            SendSteamOverlayChord()
        return
    }
    if (!EnableViewTapAction || !steamFront)
        return
    LogLine("View tapped -> Steam Menu (" SendToPretty(SteamMenuShortcut) ").")
    SendChordSafe(SteamMenuShortcut)
}

; Steam Menu: Steam's own menu when Steam is in front, the in-game overlay when
; a game is.
SendSteamMenu(steamInFront) {
    global SteamMenuShortcut, SteamOverlayShortcut
    shortcut := steamInFront ? SteamMenuShortcut : SteamOverlayShortcut
    SetStatus("Steam Menu: " SendToPretty(shortcut))
    return shortcut
}

SendSteamQuickAccess(steamInFront) {
    global SteamQuickAccessShortcut
    SetStatus("Steam Quick Access: " SendToPretty(SteamQuickAccessShortcut))
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
        SetStatus("Could not write the task definition", "Warning")
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
        SetStatus("Logon task created")
        LogLine("Created logon task '" LogonTaskName() "' at normal privileges, "
            . "runs on battery, 10s logon delay, no execution time limit.")
        ; Record what was actually registered, so a later "it did not start"
        ; can be answered from the log instead of guessed at.
        LogLogonTaskDetails()
    } else {
        SetStatus("Could not create the logon task", "Warning")
        LogLine("Creating logon task failed (exit " exitCode ").", "Warning")
    }
    SettingsRefreshLogonTaskStatus()
}

RemoveLogonTask(*) {
    global SettingsDialogActive
    if !LogonTaskExists() {
        SetStatus("No logon task is registered")
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
        SetStatus("Logon task removed")
        LogLine("Removed logon task '" LogonTaskName() "'.")
    } else {
        SetStatus("Could not remove the logon task", "Warning")
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
    SetStatus("Logon task details written to the log")
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
    ; Arguments are supported now. The old code treated the whole entry as a
    ; path, so "app.exe --flag" failed FileExist and was silently skipped -- the
    ; shell had always handled it.
    target := "", params := ""
    if !SplitStartupCommandLine(path, &target, &params) {
        LogLine("Startup program entry could not be parsed: " path, "Warning")
        return false
    }
    target := NormalizeMediaPath(target)
    if (target = "" || !FileExist(target)) {
        LogLine("Startup program not found: " target, "Warning")
        return false
    }
    path := target
    SplitPath(path, &fileName, &directory)
    if (fileName != "" && ProcessExist(fileName)) {
        LogLine("Startup program already running, skipped: " fileName)
        return false
    }
    mode := NormalizeWindowMode(StartupWindowMode)
    ; Run's own show-state argument. It only reaches the child on the direct
    ; route: the de-elevated route asks explorer.exe to start the program, and
    ; explorer decides the show state itself, so the sweep below is what actually
    ; enforces the mode there.
    runOptions := mode = "hidden" ? "Hide" : (mode = "minimized" ? "Min" : "")
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
    if (CompanionDisabled || !EnableStartupPrograms || StartupPrograms.Length = 0)
        return
    LogLine("Launching " StartupPrograms.Length " startup program(s).")
    delay := 0
    for _, path in StartupPrograms {
        if (delay = 0)
            LaunchStartupProgram(path)
        else
            SetTimer(LaunchStartupProgram.Bind(path), -delay)
        delay += StartupProgramStaggerMs
    }
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

AssistInventoryBuild() {
    static WS_EX_TOOLWINDOW := 0x00000080
    static WS_EX_APPWINDOW := 0x00040000
    static SHELL_CLASSES := Map(
        "Progman", true, "WorkerW", true, "Shell_TrayWnd", true,
        "Shell_SecondaryTrayWnd", true)
    items := []
    for hwnd in WinGetList() {
        visible := DllCall("IsWindowVisible", "Ptr", hwnd, "Int") != 0
        if (!visible || IsCloakedWindow(hwnd))
            continue
        cls := "", title := "", exe := "", pid := 0
        try cls := WinGetClass("ahk_id " hwnd)
        if SHELL_CLASSES.Has(cls)
            continue
        try title := WinGetTitle("ahk_id " hwnd)
        try exe := WinGetProcessName("ahk_id " hwnd)
        try pid := WinGetPID("ahk_id " hwnd)
        exeLower := StrLower(exe)
        exStyle := 0
        try exStyle := WinGetExStyle("ahk_id " hwnd)
        ; Steam Big Picture can be a visible, titled steamwebhelper tool window
        ; without WS_EX_APPWINDOW under Xbox FSE. Keep the exception narrow;
        ; every other palette and overlay remains excluded from the inventory.
        if ((exStyle & WS_EX_TOOLWINDOW) && !(exStyle & WS_EX_APPWINDOW)
            && !IsSteamProcess(exeLower))
            continue
        x := 0, y := 0, w := 0, h := 0
        try {
            WinGetPos(&posX, &posY, &posW, &posH, "ahk_id " hwnd)
            x := posX, y := posY, w := posW, h := posH
        }
        ; A minimized window reports off-screen coordinates rather than nothing,
        ; so this guard is about genuinely degenerate rectangles and must not be
        ; widened to exclude them -- WinGetMinMax below is what identifies them.
        if (w <= 0 || h <= 0)
            continue
        minMax := 0
        try minMax := WinGetMinMax("ahk_id " hwnd)
        style := 0
        try style := WinGetStyle("ahk_id " hwnd)
        ; The extra fields exist for the shared legacy/minimized-game detectors in
        ; SteamShell-Common.ahk. They are additive: the assist features read the
        ; keys they always read and are unaffected.
        ;
        ; "proc" and "scriptOwned" duplicate "exe" and "ours" under the names the
        ; shell's inventory uses, because the detectors were written against that
        ; inventory and aliasing two keys is cheaper than forking them.
        items.Push(Map(
            "hwnd", hwnd, "title", title, "class", cls, "exe", exeLower,
            "pid", pid, "x", x, "y", y, "w", w, "h", h,
            "ours", IsOurWindow(hwnd),
            "proc", exeLower,
            "scriptOwned", IsOurWindow(hwnd),
            "desktop", SHELL_CLASSES.Has(cls),
            "steam", IsSteamProcess(exeLower),
            "style", style,
            "exStyle", exStyle,
            "owner", DllCall("User32\GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr"), ; GW_OWNER
            "minMax", minMax,
            "area", Max(0, w) * Max(0, h)))
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
AssistProcessCpuSample(pid) {
    global AssistCpuSamples
    static PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    now := A_TickCount
    unknown := Map("usage", 0.0, "known", false, "lastSeen", now)
    if !pid
        return unknown
    handle := DllCall("OpenProcess", "UInt", PROCESS_QUERY_LIMITED_INFORMATION,
        "Int", 0, "UInt", pid, "Ptr")
    if !handle
        return unknown
    creation := Buffer(8, 0), exitTime := Buffer(8, 0)
    kernel := Buffer(8, 0), user := Buffer(8, 0)
    ok := DllCall("GetProcessTimes", "Ptr", handle, "Ptr", creation, "Ptr", exitTime,
        "Ptr", kernel, "Ptr", user, "Int")
    DllCall("CloseHandle", "Ptr", handle)
    if !ok
        return unknown
    ; FILETIME units are 100ns.
    creationValue := NumGet(creation, 0, "Int64")
    total := NumGet(kernel, 0, "Int64") + NumGet(user, 0, "Int64")
    if AssistCpuSamples.Has(pid) {
        previous := AssistCpuSamples[pid]
        if (previous["creation"] = creationValue) {
            elapsed := now - previous["tick"]
            busy := total - previous["total"]
            usage := (elapsed > 0 && busy >= 0)
                ? ClampFloat((busy / (elapsed * 10000.0)) * 100.0, 0, 10000)
                : previous["usage"]
            sample := Map(
                "usage", usage, "known", elapsed > 0,
                "creation", creationValue, "total", total,
                "tick", now, "lastSeen", now)
            AssistCpuSamples[pid] := sample
            return sample
        }
    }
    sample := Map(
        "usage", 0.0, "known", false,
        "creation", creationValue, "total", total,
        "tick", now, "lastSeen", now)
    AssistCpuSamples[pid] := sample
    return sample
}

AssistPruneCpuSamples(inventory) {
    global AssistCpuSamples
    live := Map()
    for _, item in inventory
        live[item["pid"]] := true
    for pid in AssistCpuSamples.Clone() {
        if !live.Has(pid)
            AssistCpuSamples.Delete(pid)
    }
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
XfeBestGameWindow() {
    global LastBestCandidateProc, LastBestCandidateScore
    global AssistCpuThresholdPercent, AssistProtectedProcesses
    global AssistLauncherProcesses, EnableAudioAssist, AudioPeakThreshold
    protectedSet := ProcessNameSetFromList(AssistProtectedProcesses)
    launcherSet := ProcessNameSetFromList(AssistLauncherProcesses)
    weights := XfeGameScoreWeights()
    candidates := []
    audioMap := ""
    for _, item in AssistInventoryGet() {
        if (item["ours"] || item["title"] = "" || item["exe"] = "")
            continue
        if (protectedSet.Has(item["exe"]) || launcherSet.Has(item["exe"]))
            continue
        ; Per MONITOR, not the primary screen. The shell can assume the game is
        ; on A_Screen*; a companion under Xbox FSE cannot, and the inventory
        ; already carries the handle needed to ask.
        ; An exclusive-fullscreen game that minimized itself when Steam took
        ; focus. Its geometry is meaningless, so the shape test is bypassed
        ; entirely -- GameWindowShapeVerdict treats minimizedLegacy as nearFS --
        ; and the monitor lookup below would be answering about coordinates that
        ; are off-screen by design.
        minimizedLegacy := WindowEngineIsMinimizedLegacyGameSurface(item)
        left := 0, top := 0, screenW := A_ScreenWidth, screenH := A_ScreenHeight
        if !minimizedLegacy {
            monitorIndex := GetMonitorIndexForWindow(item["hwnd"])
            try MonitorGet(monitorIndex, &left, &top, &right, &bottom)
            catch
                continue
            screenW := right - left
            screenH := bottom - top
            if (screenW <= 0 || screenH <= 0)
                continue
        }
        shapeVerdict := GameWindowShapeVerdict(
            Map("w", item["w"], "h", item["h"],
                "x", item["x"] - left, "y", item["y"] - top,
                "screenW", screenW, "screenH", screenH,
                "titleLength", StrLen(item["title"]),
                "minimizedLegacy", minimizedLegacy),
            weights)
        if (!shapeVerdict["accepted"])
            continue
        ; Sampled only after the shape passes, and audio only after CPU passes.
        ; Both are measurements with a cost, and the shell orders them the same
        ; way for the same reason.
        cpu := 0.0
        cpuKnown := false
        if item["pid"] {
            sample := AssistProcessCpuSample(item["pid"])
            if IsObject(sample) {
                cpu := sample["usage"]
                cpuKnown := sample["known"]
            }
        }
        cpuVerdict := GameWindowCpuVerdict(
            shapeVerdict["score"], cpu, cpuKnown, weights)
        if (!cpuVerdict["accepted"])
            continue
        score := cpuVerdict["score"]
        audioActive := false
        if (EnableAudioAssist && item["pid"]) {
            if (!IsObject(audioMap))
                audioMap := GetActiveAudioPidPeaksCached()
            if (audioMap.Has(item["pid"]) && audioMap[item["pid"]] > AudioPeakThreshold) {
                score += weights["audioActive"]
                audioActive := true
            }
        }
        candidate := Map()
        for key, value in item
            candidate[key] := value
        candidate["score"] := score
        ; The columns LogGameCandidateTable renders. "proc" duplicates "exe":
        ; the shell's inventory calls it proc and the table was written against
        ; that, and one aliased key is cheaper than a second table format.
        candidate["proc"] := item["exe"]
        candidate["cpu"] := cpu
        candidate["cpuKnown"] := cpuKnown
        candidate["audio"] := audioActive
        candidate["nearFS"] := shapeVerdict["nearFS"]
        candidates.Push(candidate)
    }
    if (candidates.Length > 1)
        SortCandidatesByScoreAreaDesc(candidates)
    LogGameCandidateTable(candidates, [], "best-candidate")
    ; The same snapshot the shell takes, at the same point: after the sort,
    ; before anything decides what to do with the answer.
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
    ; No score floor, matching the shell, which sets LastBestCandidateProc from
    ; the best candidate unconditionally.
    ;
    ; A floor was worse than none here. The shell's GameMinScoreToActivate is
    ; named for ACTIVATION -- the confidence needed to pull focus back to a game,
    ; which is a disruptive act. Naming a profile is not that. Worse, falling
    ; below the floor sent this back to LastObservedGameExe, the foreground-only
    ; observation the scorer exists to replace, so a low score discarded a scored
    ; answer in favour of an unscored one.
    ;
    ; Everything not plausibly a game is already gone before a score exists:
    ; protected processes, launchers, our own windows and anything that fails the
    ; shape test never become candidates, and IsUsableProfileExe rejects Steam,
    ; Explorer and this executable afterwards.
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
    SetStatus("Screen probe: capturing in " Round(delayMs / 1000) "s, see the log")
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
    static WS_EX_TOOLWINDOW := 0x00000080
    static WS_EX_APPWINDOW := 0x00040000
    shown := 0
    hidden := 0
    for hwnd in WinGetList() {
        cls := "", title := "", exe := ""
        try cls := WinGetClass("ahk_id " hwnd)
        try title := WinGetTitle("ahk_id " hwnd)
        try exe := StrLower(WinGetProcessName("ahk_id " hwnd))
        exStyle := 0
        try exStyle := WinGetExStyle("ahk_id " hwnd)
        x := 0, y := 0, w := 0, h := 0
        try {
            WinGetPos(&posX, &posY, &posW, &posH, "ahk_id " hwnd)
            x := posX, y := posY, w := posW, h := posH
        }
        visible := DllCall("IsWindowVisible", "Ptr", hwnd, "Int") != 0
        cloaked := IsCloakedWindow(hwnd)
        toolWindow := (exStyle & WS_EX_TOOLWINDOW) && !(exStyle & WS_EX_APPWINDOW)
        isForeground := hwnd = foregroundHwnd
        ; An untitled, invisible, zero-sized window is noise. The foreground is
        ; always reported whatever shape it is in.
        if (!isForeground && !visible && title = "") {
            hidden += 1
            continue
        }
        reasons := ""
        if !visible
            reasons .= " hidden"
        if cloaked
            reasons .= " cloaked"
        if toolWindow
            reasons .= " toolwindow"
        if (w <= 0 || h <= 0)
            reasons .= " zero-size"
        shown += 1
        LogLine("Screen probe:   " (exe != "" ? exe : "?") " [" cls "]"
            . " " w "x" h " at " x "," y
            . ((exStyle & WS_EX_TOPMOST) ? " topmost" : "")
            . (isForeground ? " FOREGROUND" : "")
            . (IsOurWindow(hwnd) ? " (ours)" : "")
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
    SetStatus("Screen probe complete — see the log")
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
        SetStatus("Launcher cleanup closed " closed " launcher"
            . (closed = 1 ? "" : "s"))
}

; ==============================================================================
; Task switcher
; ==============================================================================
; Lists switchable top-level windows so one can be brought forward or closed.
;
; This is deliberately NOT a port of SteamShell 1.5's switcher. That one records
; the chosen window as a pinned foreground and keeps enforcing focus on it,
; which is precisely the job Xbox FSE owns; duplicating it would put two
; managers in a fight over the same window. Here activation is a single
; one-shot request -- raise the window once, then leave presentation alone.
;
; The window list is built directly from WinGetList rather than from any shared
; window inventory, so nothing here grows into a focus engine.
IsCloakedWindow(hwnd) {
    cloaked := 0
    try DllCall("Dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14,
        "Int*", &cloaked, "UInt", 4)
    return cloaked != 0
}

GetSwitchableWindowsSummary() {
    count := GetSwitchableWindows().Length
    if (count = 0)
        return "No Windows"
    return count " window" (count = 1 ? "" : "s")
}

GetSwitchableWindows() {
    static WS_EX_TOOLWINDOW := 0x00000080
    static WS_EX_APPWINDOW := 0x00040000
    static SHELL_CLASSES := Map(
        "Progman", true, "WorkerW", true, "Shell_TrayWnd", true,
        "Shell_SecondaryTrayWnd", true, "WindowsDashboard", true)
    windows := []
    for hwnd in WinGetList() {
        if IsOurWindow(hwnd)
            continue
        if !DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
            continue
        title := "", cls := "", exe := ""
        try title := WinGetTitle("ahk_id " hwnd)
        try cls := WinGetClass("ahk_id " hwnd)
        try exe := WinGetProcessName("ahk_id " hwnd)
        ; Steam is resolved FIRST, because every gate below it had to be waived
        ; for Steam and only one of them ever was.
        ;
        ; Steam Big Picture vanished from the switcher under Xbox FSE. There was
        ; already an exception for the tool-window rule -- Steam publishes a
        ; titled, full-sized window as WS_EX_TOOLWINDOW without WS_EX_APPWINDOW
        ; -- but it sat at the END of the chain, and three earlier gates rejected
        ; Steam before it was ever reached:
        ;
        ;   cloaked      Windows cloaks Steam while Xbox FSE owns the screen,
        ;                which is exactly when the user wants to switch to it.
        ;   empty title  a cloaked window frequently reports none.
        ;   size         and frequently reports no usable size either.
        ;
        ; The shell tree never hit this because Xbox FSE is not running there, so
        ; Steam is never cloaked. Same rule, different world -- which is why the
        ; fix belongs here and the shell's own filter is left alone.
        isSteamWindow := IsSteamProcess(exe)
        if (!isSteamWindow && IsCloakedWindow(hwnd))
            continue
        if (SHELL_CLASSES.Has(cls))
            continue
        if (title = "" && !isSteamWindow)
            continue
        exStyle := 0
        try exStyle := WinGetExStyle("ahk_id " hwnd)
        ; Tool windows are palettes and overlays, not applications, unless they
        ; explicitly ask to appear in the task list.
        ;
        ; Steam Big Picture under current Xbox FSE builds is the exception: its
        ; visible, titled, full-sized window can be published by steamwebhelper
        ; as WS_EX_TOOLWINDOW without WS_EX_APPWINDOW. Applying the generic rule
        ; made Steam disappear from the switcher entirely. Keep the exception
        ; process-specific; relaxing the rule globally would bring back every
        ; overlay, popup and helper palette.
        if ((exStyle & WS_EX_TOOLWINDOW) && !(exStyle & WS_EX_APPWINDOW)
            && !isSteamWindow)
            continue
        w := 0, h := 0
        try {
            WinGetPos(, , &posW, &posH, "ahk_id " hwnd)
            w := posW, h := posH
        }
        if ((w < 120 || h < 80) && !isSteamWindow)
            continue
        ; A cloaked Steam window reports no title, so give the row something the
        ; user can read rather than a blank entry.
        if (title = "")
            title := exe " (Steam)"
        windows.Push(Map("hwnd", hwnd, "title", title, "exe", exe))
    }
    return windows
}

ActivateSwitchableWindow(hwnd) {
    if !DllCall("IsWindow", "Ptr", hwnd) {
        SetStatus("That window is no longer available", "Warning")
        QuickMenuRefresh()
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
        SetStatus("Windows could not activate that window", "Warning")
}

CloseSwitchableWindow(hwnd, force := false) {
    if !DllCall("IsWindow", "Ptr", hwnd) {
        QuickMenuRefresh()
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
    ; Give the window a moment to go before the list is rebuilt.
    SetTimer(QuickMenuRefresh, -400)
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
        SetStatus("Force closed " ShortenText(title, 30), "Warning")
        return
    }
    CloseSwitchableWindow(hwnd, false)
    QuickMenuConfirmAction := confirmId
    QuickMenuConfirmUntilTick := A_TickCount + 5000
    SetStatus("Closing " ShortenText(title, 26) " — press X again to force", "Warning")
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
    global QuickMenuPage, EnableAudioQuickControls, EnableDisplayQuickControls
    global QuickMenuDisplayModes
    global RtssOverlayControlMode, RtssFrameLimiterControlMode
    global EnableRTSSIntegration, RtssPath
    global QuickMenuPreviousExe, QuickMenuTaskWindows
    global SteamMenuShortcut, SteamQuickAccessShortcut, SteamOverlayShortcut
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    global DisplaySelectedScalePercent
    global EnablePersistentMouseMode
    global RtssPendingFrameCap
    global EnableGameDetectionMenu, LastGameCandidates
    rows := []
    switch QuickMenuPage {
        case "MAIN":
            if EnableAudioQuickControls
                rows.Push(MenuRow("audioPage", "Audio", GetAudioSummary(), "page:AUDIO"))
            if EnableDisplayQuickControls
                rows.Push(MenuRow("displayPage", "Display & HDR", GetDisplaySummary(), "page:DISPLAY"))
            rows.Push(MenuRow("rtssPage", "RTSS & Performance", GetRtssSummary(), "page:RTSS"))
            ; Show the shortcut each row will actually send, so the menu makes
            ; the Steam/in-game difference visible rather than surprising.
            steamFront := IsSteamProcess(QuickMenuPreviousExe)
            rows.Push(MenuRow("steamMenu", "Steam Menu",
                SendToPretty(steamFront ? SteamMenuShortcut : SteamOverlayShortcut),
                "steamMenu"))
            rows.Push(MenuRow("steamQuickAccess", "Steam Quick Access",
                SendToPretty(SteamQuickAccessShortcut), "steamQuickAccess"))
            rows.Push(MenuRow("tasksPage", "Task Switcher",
                GetSwitchableWindowsSummary(), "page:TASKS"))
            rows.Push(MenuRow("gameBar", "Game Bar", "Win + G", "gameBar"))
            rows.Push(MenuRow("openKeyboard", "Open Keyboard", "Open Touch Keyboard",
                "openKeyboard"))
            rows.Push(MenuRow("mouseMode", "Mouse Mode",
                OnOffText(EnablePersistentMouseMode), "toggle:mouseMode", true))
            rows.Push(MenuRow("settingsPage", "Settings", "Features & Configuration",
                "page:SETTINGS"))
            rows.Push(MenuRow("systemPage", "System", "Power & Diagnostics", "page:SYSTEM"))
        case "SETTINGS":
            ; The switches worth reaching from a controller. Everything else
            ; still lives in the full Settings window at the bottom of the page.
            rows.Push(MenuRow("back", "Back", "", "back"))
            for _, row in QuickMenuSettingsRows()
                rows.Push(row)
            rows.Push(MenuRow("windowsSettings", "Windows Settings",
                "Open Windows Settings", "windowsSettings"))
            rows.Push(MenuRow("settings", "All Settings…", "Open Settings Window",
                "settings"))
        case "TASKS":
            rows.Push(MenuRow("back", "Back", "", "back"))
            QuickMenuTaskWindows := GetSwitchableWindows()
            if (QuickMenuTaskWindows.Length = 0) {
                rows.Push(MenuRow("noTasks", "No Switchable Windows", "", "none"))
            } else {
                ; The control pool holds 14 rows and Back takes one.
                Loop Min(QuickMenuTaskWindows.Length, 13) {
                    item := QuickMenuTaskWindows[A_Index]
                    rows.Push(MenuRow("taskWindow:" item["hwnd"],
                        ShortenText(item["title"], 34), item["exe"],
                        "taskWindow:" item["hwnd"]))
                }
            }
        case "AUDIO":
            rows.Push(MenuRow("back", "Back", "", "back"))
            rows.Push(MenuRow("audioOutput", "Output", GetAudioOutputName(), "audioOutput", true))
            rows.Push(MenuRow("volume", "Volume", GetVolumeText(), "volume", true))
            rows.Push(MenuRow("mute", "Mute", GetMuteText(), "mute"))
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
                rows.Push(MenuRow("hdr", "HDR", hdrValue, hdrAction,
                    !hdr["forceDisabled"]))
            } else {
                rows.Push(MenuRow("hdrUnavailable", "HDR",
                    IsObject(hdr) ? "Not Supported" : "Unavailable", "none"))
            }
            if (QuickMenuDisplayModes.Length = 0)
                QuickMenuDisplayModes := GetPrimaryDisplayModes()
            if (QuickMenuDisplayModes.Length = 0) {
                rows.Push(MenuRow("displayUnavailable", "No Compatible Modes Reported", "", "none"))
            } else {
                EnsureDisplaySelection()
                rows.Push(MenuRow("displayResolution", "Resolution",
                    "‹ " DisplaySelectedWidth " × " DisplaySelectedHeight " ›",
                    "displayResolution", true))
                rows.Push(MenuRow("displayRefresh", "Refresh Rate",
                    "‹ " DisplaySelectedFrequency " Hz ›", "displayRefresh", true))
                scale := EnsureDisplayScaleSelection()
                if IsObject(scale) {
                    rows.Push(MenuRow("displayScale", "Scale",
                        "‹ " DisplaySelectedScalePercent "% ›", "displayScale", true))
                } else {
                    rows.Push(MenuRow("displayScaleUnavailable", "Scale",
                        "Unavailable", "none"))
                }
                rows.Push(MenuRow("displayApply", "Apply", GetDisplayApplyValue(),
                    "displayApply"))
            }
        case "RTSS":
            rows.Push(MenuRow("back", "Back", "", "back"))
            rtssRunning := ProcessExist("RTSS.exe") != 0
            if !rtssRunning {
                if !EnableRTSSIntegration {
                    rows.Push(MenuRow("rtssDisabled", "RTSS Integration",
                        "Disabled", "none"))
                } else if ResolveRtssExecutablePath() != "" {
                    rows.Push(MenuRow("rtssStart", "Start RTSS",
                        "Launch Configured Executable", "rtssStart"))
                } else {
                    rows.Push(MenuRow("rtssMissing", "RTSS",
                        "Executable Not Found", "none"))
                }
            } else {
                rtssState := GetRtssGlobalState()
                if IsObject(rtssState) {
                    rows.Push(MenuRow("rtssOverlayState", "Overlay",
                        "‹ " (rtssState["overlay"] ? "ON" : "OFF") " ›",
                        "rtssOverlayState", true))
                    ; One row for the limiter flag and its target. The separate
                    ; "Frame Limiter" row is gone here on purpose: with live DLL
                    ; control, two rows that can each mean "no limiting" only
                    ; fight each other. The shortcut fallback below still needs
                    ; both, because without the DLL there is no value to fold in.
                    rows.Push(MenuRow("rtssFrameLimit", "Frame Limit",
                        RtssFrameCapValueText(), "rtssFrameLimit", true))
                    capState := GetRtssFrameCapState()
                    if (IsObject(capState) && capState["mode"] = "custom")
                        ; A pending value is what the user is looking at and
                        ; adjusting; the live one has not caught up yet by design.
                        rows.Push(MenuRow("rtssFrameLimitCustom", "Custom FPS",
                            "‹ " (RtssPendingFrameCap > 0
                                ? RtssPendingFrameCap : capState["fps"]) " FPS ›",
                            "rtssFrameLimitCustom", true))
                    ; Always present, even with nothing to save to: the value
                    ; column explains why rather than the row disappearing,
                    ; which would read as the feature being missing.
                    rows.Push(MenuRow("rtssSaveProfile", "Save Limit To Profile",
                        RtssSaveProfileValueText(), "rtssSaveProfile"))
                } else if (RtssOverlayControlMode = "separate") {
                    rows.Push(MenuRow("overlayOn", "Overlay On", "", "overlayOn"))
                    rows.Push(MenuRow("overlayOff", "Overlay Off", "", "overlayOff"))
                } else {
                    rows.Push(MenuRow("overlayToggle", "Toggle Overlay", "",
                        "overlayToggle"))
                }
                if !IsObject(rtssState) {
                    if (RtssFrameLimiterControlMode = "separate") {
                        rows.Push(MenuRow("limiterOn", "Frame Limiter On",
                            GetFrameCapLabel(), "limiterOn"))
                        rows.Push(MenuRow("limiterOff", "Frame Limiter Off", "",
                            "limiterOff"))
                    } else {
                        rows.Push(MenuRow("limiterToggle", "Toggle Frame Limiter",
                            GetFrameCapLabel(), "limiterToggle"))
                    }
                }
            }
            rows.Push(MenuRow("rtssSettings", "RTSS Settings", GetRtssAvailability(),
                "rtssSettings"))
        case "LAYOUT":
            rows.Push(MenuRow("back", "Back", "", "back"))
            for _, button in ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "Start", "L3", "R3"] {
                value := ControllerBindingPretty(button ".Short")
                longValue := ControllerBindingPretty(button ".Long")
                if (longValue != "None")
                    value .= "  /  Hold: " longValue
                rows.Push(MenuRow("layout:" button, button, value, "none"))
            }
            rows.Push(MenuRow("setControllerMappings", "Set Controller Mappings",
                "Open Mapping Editor", "setControllerMappings"))
        case "SYSTEM":
            rows.Push(MenuRow("back", "Back", "", "back"))
            rows.Push(MenuRow("sleep", "Sleep", "", "sleep"))
            rows.Push(MenuRow("restart", "Restart", "", "restart"))
            rows.Push(MenuRow("shutdown", "Shut Down", "", "shutdown"))
            if EnableGameDetectionMenu
                rows.Push(MenuRow("gameDetection", "Game Detection",
                    QuickMenuGameDetectionValue(), "page:GAMESCORE"))
            rows.Push(MenuRow("exit", "Exit Companion", "", "exit"))
        ; Read-only. Every number was already computed to choose a game; this
        ; only shows the losers beside the winner.
        case "GAMESCORE":
            rows.Push(MenuRow("back", "Back", "", "back"))
            if (LastGameCandidates.Length = 0) {
                rows.Push(MenuRow("gameScoreEmpty", "No candidates scored yet",
                    "", "none"))
            } else {
                for _, rowId in QuickMenuGameScoreIds()
                    rows.Push(MenuRow(rowId, QuickMenuGameScoreLabel(rowId),
                        QuickMenuGameScoreValue(rowId), "none"))
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
QuickMenuToggleMeta(id) {
    global EnableGameFocusLite, EnableSteamAssistLite, EnableLauncherCleanupLite
    global AssistSuspendOnShellOverlay
    global EnableViewSteamActions, EnableViewTapAction, EnableViewHoldAction
    global EnablePersistentMouseMode
    switch id {
        case "gameFocus":
            return Map("section", "Assist", "key", "EnableGameFocusLite",
                "label", "Game Focus Lite", "value", EnableGameFocusLite)
        case "steamAssist":
            return Map("section", "Assist", "key", "EnableSteamAssistLite",
                "label", "Steam Assist Lite", "value", EnableSteamAssistLite)
        case "launcherCleanup":
            return Map("section", "Assist", "key", "EnableLauncherCleanupLite",
                "label", "Launcher Cleanup Lite", "value", EnableLauncherCleanupLite)
        case "shellOverlay":
            return Map("section", "Assist", "key", "SuspendOnShellOverlay",
                "label", "Pause Assist On FSE Switcher",
                "value", AssistSuspendOnShellOverlay)
        case "viewActions":
            return Map("section", "Steam", "key", "EnableViewButtonActions",
                "label", "View Button Steam Actions", "value", EnableViewSteamActions)
        case "viewTap":
            return Map("section", "Steam", "key", "EnableViewTapAction",
                "label", "View Tap Action", "value", EnableViewTapAction)
        case "viewHold":
            return Map("section", "Steam", "key", "EnableViewHoldAction",
                "label", "View Hold Action", "value", EnableViewHoldAction)
        case "mouseMode":
            return Map("section", "Controller", "key", "EnablePersistentMouseMode",
                "label", "Mouse Mode", "value", EnablePersistentMouseMode)
    }
    return 0
}

QuickMenuToggleSetting(id) {
    global EnableGameFocusLite, EnableSteamAssistLite, EnableLauncherCleanupLite
    global AssistSuspendOnShellOverlay
    global EnableViewSteamActions, EnableViewTapAction, EnableViewHoldAction
    global EnableControllerMouseMode, EnablePersistentMouseMode
    global IniPath
    meta := QuickMenuToggleMeta(id)
    if !IsObject(meta)
        return
    next := !meta["value"]
    ; Persistence is the transaction boundary. Do not change the live state or
    ; claim success if the portable INI is read-only or otherwise unwritable.
    enabledControllerMaster := false
    try {
        if (id = "mouseMode" && next && !EnableControllerMouseMode) {
            IniWrite("true", IniPath, "Controller", "EnableControllerMouseMode")
            enabledControllerMaster := true
        }
        IniWrite(next ? "true" : "false",
            IniPath, meta["section"], meta["key"])
    } catch as err {
        if enabledControllerMaster
            try IniWrite("false", IniPath, "Controller", "EnableControllerMouseMode")
        LogLine("Quick Menu: could not save " meta["label"] " ("
            . err.Message ").", "Warning")
        SetStatus("Could not save " meta["label"], "Warning")
        return
    }
    switch id {
        case "gameFocus":
            EnableGameFocusLite := next
        case "steamAssist":
            EnableSteamAssistLite := next
        case "launcherCleanup":
            EnableLauncherCleanupLite := next
        case "shellOverlay":
            AssistSuspendOnShellOverlay := next
        case "viewActions":
            EnableViewSteamActions := next
        case "viewTap":
            EnableViewTapAction := next
        case "viewHold":
            EnableViewHoldAction := next
        case "mouseMode":
            EnablePersistentMouseMode := next
            if enabledControllerMaster {
                EnableControllerMouseMode := true
                SetFieldValue("Controller.EnableControllerMouseMode", true)
            }
    }
    ; If the full Settings window happens to be open behind the Quick Menu,
    ; update its matching control too. Otherwise a later Save there could write
    ; the stale pre-toggle value back over this persisted couch change.
    SetFieldValue(meta["section"] "." meta["key"], next)
    LogLine("Quick Menu: " meta["label"] " -> " OnOffText(next) ".")
    ; The assist timer only exists while something needs it, so enabling the
    ; first assist feature has to create it and disabling the last has to stop
    ; it. Re-applying the timers is idempotent and does that in one place.
    if (meta["section"] = "Assist")
        ApplyRuntimeTimers()
    SetStatus(meta["label"] ": " OnOffText(next))
}

; Rows for the Quick Menu's Settings page: the switches worth reaching from the
; couch, without opening the full Settings window on a TV.
QuickMenuSettingsRows() {
    rows := []
    for _, id in ["gameFocus", "steamAssist", "launcherCleanup", "shellOverlay",
        "viewActions", "viewTap", "viewHold"] {
        meta := QuickMenuToggleMeta(id)
        rows.Push(MenuRow("toggle:" id, meta["label"], OnOffText(meta["value"]),
            "toggle:" id, true))
    }
    rows.Push(MenuRow("accentColor", "Accent Color", QuickMenuAccentValueText(),
        "accentColor", true))
    return rows
}

; Steps the accent to the next preset and persists it. Wraps at both ends: a
; color list has no meaningful first or last, and stopping at Teal would make
; the default feel like a dead end.
CycleQuickMenuAccent(direction) {
    global IniPath, QuickMenuAccentName, QuickMenuAccentCustomHex
    names := QuickMenuAccentPresetNames()
    index := 1
    for candidateIndex, candidateName in names {
        if (StrLower(candidateName) = StrLower(QuickMenuAccentName)) {
            index := candidateIndex
            break
        }
    }
    index += direction
    if (index < 1)
        index := names.Length
    else if (index > names.Length)
        index := 1
    chosen := names[index]
    ; Persistence is the transaction boundary, matching QuickMenuToggleSetting:
    ; do not repaint in a color the INI could not record.
    try {
        IniWrite(chosen, IniPath, "QuickMenu", "AccentColor")
    } catch as err {
        LogLine("Quick Menu: could not save accent color (" err.Message ").",
            "Warning")
        SetStatus("Could not save accent color", "Warning")
        return
    }
    QuickMenuApplyAccent(chosen, QuickMenuAccentCustomHex)
    ; If the full Settings window is open behind the Quick Menu, update its
    ; control too, or a later Save there would write the stale value back.
    SetFieldText("QuickMenu.AccentColor", chosen)
    LogLine("Quick Menu: accent -> " chosen ".")
    SetStatus("Accent: " QuickMenuAccentValueText())
}

GuiSafeLabel(text) {
    return StrReplace(text, "&", "&&")
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

GetDisplaySummary() {
    mode := GetPrimaryDisplayMode()
    if !IsObject(mode)
        return "Unavailable"
    scale := GetPrimaryDisplayScale()
    scaleText := IsObject(scale) ? "  •  " scale["percent"] "%" : ""
    return mode["width"] "×" mode["height"] "  •  " mode["frequency"] " Hz"
        . scaleText
}

GetRtssSummary() {
    global EnableRTSSIntegration, RtssPath, RtssUseDllIntegration
    if !EnableRTSSIntegration
        return "Setup Required"
    if ProcessExist("RTSS.exe") {
        if !RtssUseDllIntegration
            return "Running | Shortcuts"
        state := GetRtssGlobalState()
        if IsObject(state)
            return "Overlay " (state["overlay"] ? "On" : "Off")
                . " | Limiter " (state["limiter"] ? "On" : "Off")
        return "Running"
    }
    return ResolveRtssExecutablePath() != "" ? "RTSS Ready" : "RTSS Not Found"
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

; Per-tree seam for the shared request channel. XFE keeps its data beside its
; executable, so the request file goes there rather than in a ProgramData
; directory the companion does not have.
;
; Deliberately not the settings file. This is a request, not a setting: it has
; no meaning once serviced, and keeping it separate means the whole of what
; crosses into the elevated process is two integers and a name in a file that
; contains nothing else.
ElevatedRtssRequestPath() {
    return A_ScriptDir "\rtss-request.ini"
}

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
        "--product=xfe --main-path=" '"' A_ScriptFullPath '"', helperDirectory)
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
        . " --product=xfe"
        . " --parent-pid=" ScriptPid
        . " --settings=" QuoteWindowsCommandLineArg(IniPath)
        . " --log=" QuoteWindowsCommandLineArg(helperLog)
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
SharedPersistSettings(changes) {
    global IniPath
    for _, item in changes {
        try IniWrite(item["value"], IniPath, item["section"], item["key"])
        catch as err {
            LogLine(
                "Setting " item["section"] "/" item["key"]
                . " could not be saved: " err.Message, "Warning")
            return false
        }
    }
    return true
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

PersistRtssCustomFrameCap(value) {
    global IniPath, RtssCustomFrameCap
    value := ClampInt(value, 10, 1000)
    try IniWrite(value, IniPath, "RTSS", "CustomFrameCap")
    catch as err {
        LogLine("RTSS Custom FPS could not be retained: " err.Message, "Warning")
        SetStatus("The Custom FPS value could not be retained", "Warning")
        return false
    }
    RtssCustomFrameCap := value
    ; Committing a Custom value is also a selection of Custom at that value.
    ; Recorded here rather than in the caller: CommitRtssPendingFrameCap is
    ; shared, so it cannot carry a tree-specific call.
    PersistRtssFrameCapSelection("custom", value)
    return true
}

ToggleQuickMenu(*) {
    global QuickMenuVisible
    if QuickMenuVisible
        HideQuickMenu()
    else
        ShowQuickMenu()
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
    ; Hiding alone can leave the child title/rows/footer surfaces cached in DWM
    ; when a fullscreen game or Xbox FSE replaces its presentation surface.
    ; Hide the parent first, then retire the whole menu session.
    if IsSet(QuickMenuGui) {
        try DllCall("User32\ShowWindow", "Ptr", QuickMenuGui.Hwnd, "Int", 0)
        try QuickMenuGui.Hide()
    }
    QuickMenuVisible := false
    QuickMenuDestroyWindow()
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

; Exit cleanup uses the same ownership-safe teardown as an ordinary close.
ReleaseQuickMenuPaintResources() {
    QuickMenuDestroyWindow()
}

; The one line of the painter that differs between the two trees, isolated so
; the rest can stay identical: standalone resolves a row's value live, while XFE
; rebuilds its whole row list per repaint and already carries it.
QuickMenuRowValueText(row) {
    return row["value"]
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
    statusY := 0, statusHeight := 0, clientHeight := 0
    winX := 0, winY := 0, winWidth := 0, winHeight := 0
    try {
        ControlGetPos(, &measuredStatusY, , &measuredStatusHeight,
            QuickMenuStatusCtrl, QuickMenuGui)
        WinGetClientPos(, , , &measuredClientHeight, "ahk_id " QuickMenuGui.Hwnd)
        WinGetPos(&measuredWinX, &measuredWinY, &measuredWinWidth,
            &measuredWinHeight, "ahk_id " QuickMenuGui.Hwnd)
        statusY := measuredStatusY, statusHeight := measuredStatusHeight
        clientHeight := measuredClientHeight
        winX := measuredWinX, winY := measuredWinY
        winWidth := measuredWinWidth, winHeight := measuredWinHeight
    }
    if (statusHeight <= 0 || clientHeight <= 0 || winHeight <= 0)
        return
    ; The bottom margin is derived from the status line's own scaled height, so it
    ; stays proportional without reintroducing a DPI calculation.
    needed := statusY + statusHeight + Round(statusHeight * 0.45)
    if (needed <= clientHeight)
        return
    grow := needed - clientHeight
    monitorIndex := ClampInt(QuickMenuMonitorIndex, 1, MonitorGetCount())
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    ; Never grow past the screen. If the content genuinely does not fit, a window
    ; the size of the work area is the honest outcome; growing beyond it would
    ; just move the clipping off-screen where it cannot be seen.
    maxHeight := bottom - top
    newHeight := Min(winHeight + grow, maxHeight)
    CenteredPosition(left, top, right, bottom, winWidth, newHeight, &x, &y)
    MoveWindowPhysical(QuickMenuGui.Hwnd, x, y, winWidth, newHeight)
    LogLine("Quick Menu: content needed " grow "px more than the window had "
        . "(client " clientHeight ", status ends " (statusY + statusHeight)
        . "); grew to " winWidth "x" newHeight " and re-centred."
        . (newHeight < winHeight + grow ? " Clamped to the work area." : ""),
        "Warning")
}

QuickMenuRender() {
    global QuickMenuRows, QuickMenuSelected, QuickMenuTitleCtrl, QuickMenuStatusCtrl
    global QuickMenuRowsCtrl
    global LastStatusText, LastStatusLevel, QuickMenuVisible
    global QM_BG, QM_ROW_SELECTED, QM_ACCENT, QM_LABEL, QM_LABEL_SELECTED, QM_VALUE
    if !QuickMenuVisible
        return
    QuickMenuRows := QuickMenuGetRows()
    if (QuickMenuRows.Length = 0)
        return
    QuickMenuSelected := ClampInt(QuickMenuSelected, 1, QuickMenuRows.Length)
    QuickMenuTitleCtrl.Text := GuiSafeLabel(QuickMenuTitleText())
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
    QuickMenuStatusCtrl.Text := GuiSafeLabel(status != "" ? status : QuickMenuHint())
    QuickMenuStatusCtrl.SetFont(
        "s9 c" (status != "" && LastStatusLevel = "Warning" ? "FFCA70" : QM_VALUE) " Norm",
        "Segoe UI")
    try QuickMenuStatusCtrl.Redraw()
}

; Button hint, tailored to the page so it lists only what actually applies.
QuickMenuHint() {
    global QuickMenuPage
    if (QuickMenuPage = "TASKS")
        return "D-Pad Move  •  A Switch To  •  X Close  •  B Back"
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
    if (SubStr(action, 1, 7) = "toggle:") {
        QuickMenuToggleSetting(SubStr(action, 8))
        QuickMenuRefresh()
        return
    }
    switch action {
        case "none":
            return
        case "back":
            QuickMenuGoBack()
            return
        case "audioOutput":
            CycleDefaultAudioOutput(1)
        case "accentColor":
            QuickMenuAdjustSelected(1)
        case "volume":
            QuickMenuAdjustSelected(1)
        case "mute":
            try {
                SoundSetMute(-1)
                SetStatus(SoundGetMute() ? "Audio muted" : "Audio unmuted")
            } catch {
                SetStatus("Windows mute control is unavailable", "Warning")
            }
        case "hdr":
            ToggleQuickMenuHdrState()
        case "displayResolution":
            CycleDisplayResolution(1)
        case "displayRefresh":
            CycleDisplayFrequency(1)
        case "displayScale":
            CycleDisplayScale(1)
        case "displayApply":
            ApplyDisplaySelection()
        case "rtssStart":
            StartRtssFromQuickMenu()
        case "overlayToggle":
            ToggleRtssOverlay()
        case "rtssOverlayState":
            ToggleRtssOverlay()
        case "overlayOn":
            SetRtssOverlayState(true)
        case "overlayOff":
            SetRtssOverlayState(false)
        case "limiterToggle":
            ToggleRtssFrameLimiter()
        case "rtssFrameLimit":
            ; Wraps: A is the only control on this row for a user who never
            ; discovers Left/Right, so it has to be able to reach every entry.
            CycleRtssFrameCap(1, true)
        case "rtssFrameLimitCustom":
            AdjustRtssCustomFrameCap(1)
        case "rtssSaveProfile":
            ; Writes a file RTSS then applies to that game on every future
            ; launch, with nothing on screen afterwards to say it happened.
            if (RtssProfileTargetExe() = "")
                SetStatus("No foreground game to save a profile for", "Warning")
            else if QuickMenuConfirm("rtssSaveProfile",
                "saving " RtssProfileTargetExe() " frame limit")
                SaveRtssFrameLimitToProfile()
        case "limiterOn":
            SetRtssFrameLimiterState(true)
        case "limiterOff":
            SetRtssFrameLimiterState(false)
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
        case "settings":
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
        case "exit":
            if !QuickMenuConfirm("exit", "exit")
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
    ; A two-state row has nothing to step through, so Left and Right both simply
    ; flip it -- the same thing A does. Direction is deliberately ignored.
    if (SubStr(action, 1, 7) = "toggle:") {
        QuickMenuToggleSetting(SubStr(action, 8))
        QuickMenuRefresh()
        return
    }
    switch action {
        case "audioOutput":
            CycleDefaultAudioOutput(direction)
        case "volume":
            try {
                nextVolume := ClampInt(Round(SoundGetVolume()) + direction * 5, 0, 100)
                SoundSetVolume(nextVolume)
                SetStatus("Volume " nextVolume "%")
            } catch {
                SetStatus("Windows volume control is unavailable", "Warning")
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
            CycleRtssFrameCap(direction)
        case "rtssFrameLimitCustom":
            AdjustRtssCustomFrameCap(direction)
        case "accentColor":
            CycleQuickMenuAccent(direction)
    }
    QuickMenuRefresh()
}

; Moves the selection, wrapping at both ends. Shared by the controller and the
; keyboard so the two can never drift apart.
; Rows that only report state and cannot be acted on, which this tree already
; marks with action "none". Standalone answers the same question from a list of
; row ids, because its rows carry no action field; the two sets are deliberately
; the same six rows.
; Per-tree seam for SteamShell-Shared.ahk's QuickMenuMoveSelection. This tree
; WRAPS around the ends; standalone clamps.
QuickMenuNormalizeSelection() {
    global QuickMenuRows, QuickMenuSelected
    if (QuickMenuSelected < 1)
        QuickMenuSelected := QuickMenuRows.Length
    if (QuickMenuSelected > QuickMenuRows.Length)
        QuickMenuSelected := 1
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
    settings := Gui("-Resize +AlwaysOnTop +MinSize900x600",
        "SteamShell XFE Settings")
    settings.Opt("+OwnDialogs")
    settings.MarginX := 24
    settings.MarginY := 16
    settings.SetFont("s18 Bold", "Segoe UI")
    settings.AddText("x24 y16 w860 h34", "SteamShell XFE Settings")
    settings.SetFont("s9 Norm", "Segoe UI")
    settings.AddText("x24 y52 w870 h24",
        "Right stick pointer • RB click • D-pad navigate • LT/RT categories • X keyboard • Y save")
    SettingsCategoryList := settings.AddListBox(
        "x24 y96 w225 h500 Choose1",
        SettingsCategoryNames())
    SettingsCategoryList.OnEvent("Change", SettingsCategoryChanged)
    settings.AddText("x264 y96 w1 h504 +0x10")
    settings.SetFont("s16 Bold", "Segoe UI")
    SettingsCategoryTitleCtrl := settings.AddText("x286 y96 w610 h32", "General")
    settings.SetFont("s9 Norm", "Segoe UI")
    SettingsCategoryDescriptionCtrl := settings.AddText(
        "x286 y132 w610 h42 +Wrap",
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
    SettingsAddCheckboxRow(settings, category, "QuickMenu.Enable",
        "Enable the controller-first Quick Menu", &y)
    SettingsAddCheckboxRow(settings, category, "Audio.EnableQuickControls",
        "Show Audio controls in the Quick Menu", &y)
    SettingsAddCheckboxRow(settings, category, "Display.EnableQuickControls",
        "Show Display and HDR controls in the Quick Menu", &y)
    SettingsAddChoiceRow(settings, category, "QuickMenu.AccentColor",
        "Quick Menu accent color", QuickMenuAccentPresetNames(), &y)
    SettingsAddEditRow(settings, category, "QuickMenu.AccentColorCustom",
        "Custom accent (RRGGBB, used when accent is Custom)", &y)
    SettingsAddEditRow(settings, category, "QuickMenu.ChordHoldMs",
        "Quick Menu L3+R3 hold time (ms)", &y, true)
    ; XFE only from here: the companion has to prove it is still responsive
    ; while Xbox FSE is in front, which the shell never needs to do.
    SettingsAddEditRow(settings, category, "Companion.HeartbeatSeconds",
        "Heartbeat log interval (seconds)", &y, true)
    ; Startup is no longer something to configure here. Setup Assistant inside
    ; SteamShell.exe registers a per-user logon task when it installs XFE, so the
    ; old advice to add SteamShell-XFE.exe as an AnyFSE startup application now
    ; starts the companion twice. What is left is the part Setup cannot do,
    ; because it belongs to AnyFSE's own configuration.
    SettingsAddNoteRow(settings, category,
        "Integration: configure AnyFSE to launch Steam Big Picture as the Home "
        . "app, and leave “Exit FSE when Home app exits” off. Setup Assistant "
        . "already starts this companion at sign-in — do not also add it to "
        . "AnyFSE's startup applications.", &y, 60)

    ; Controller & Cursor
    category := "Controller & Cursor"
    y := SettingsFirstRowY()
    SettingsAddCheckboxRow(settings, category,
        "Controller.EnableControllerMouseMode",
        "Enable controller mouse mode while holding View/Back", &y)
    ; XFE only. Standalone reads XInput and has no backend to choose.
    SettingsAddChoiceRow(settings, category, "Controller.Backend",
        "Input backend", ["Auto", "XInput", "GameInput", "RawInput"], &y, 150)
    SettingsAddNoteRow(settings, category,
        "Auto is recommended: RawInput works inside Xbox FSE, XInput on the desktop.",
        &y)
    SettingsAddEditRow(settings, category, "Controller.ControllerIndex",
        "Controller index (0–3)", &y, true)
    SettingsAddEditRow(settings, category, "Controller.ControllerMouseSpeed",
        "Controller mouse speed", &y, true)
    SettingsAddEditRow(settings, category, "Controller.ControllerDeadzone",
        "Stick deadzone", &y, true)
    SettingsAddEditRow(settings, category, "Controller.ControllerChordHoldMs",
        "Mapping long-press threshold (ms)", &y, true)
    SettingsAddCheckboxRow(settings, category, "Cursor.EnableAutoHide",
        "Automatically hide an idle mouse cursor", &y)
    SettingsAddEditRow(settings, category, "Cursor.HideDelayMs",
        "Cursor hide delay (ms)", &y, true)
    SettingsAddCheckboxRow(settings, category, "Cursor.ParkOnStartup",
        "Park the mouse at the display edge once during startup", &y)
    SettingsAddCheckboxRow(settings, category, "Cursor.ParkOnGameStart",
        "Park when a game enters fullscreen", &y)
    SettingsAddCheckboxRow(settings, category, "Cursor.ParkOnSteamReturn",
        "Park after returning to Steam", &y)
    SettingsAddChoiceRow(settings, category, "Cursor.ParkEdge",
        "Mouse parking edge", ["Right edge", "Left edge"], &y, 150)
    ; In the left column and in standalone's position, and now the same two rows
    ; standalone shows: a master switch and the allowlist it consults.
    SettingsAddCheckboxRow(settings, category, "Controller.EnableAutoMouseMode",
        "Enable automatic mouse mode (master switch)", &y)
    SettingsAddEditRow(settings, category, "Controller.AutoMouseExeList",
        "Automatic mouse applications (pipe-separated)", &y, false, 300)
    SettingsAddNoteRow(settings, category,
        "The controller acts as a mouse in these applications without holding "
        . "View/Back. Leave Xbox FSE off the list: it is controller-driven and "
        . "a pointer inside it gets in the way.", &y, 40)
    SettingsAddButtonRow(settings, category, [
        ["Controller Mappings...", ShowMappingEditor],
        ["Learn Controller...", ShowControllerLearner],
        ["Delete Learned Profile", DeleteControllerProfileForActiveDevice]], &y)

    ; Steam — no standalone counterpart. Standalone keeps its three Steam
    ; shortcuts in General; here they belong to a page that also owns the View
    ; button behaviour, which standalone does not have.
    category := "Steam"
    y := SettingsFirstRowY()
    SettingsAddNoteRow(settings, category,
        "These shortcuts must match the bindings configured inside Steam itself. "
        . "The menu shortcuts only reach Steam while Steam owns the foreground.",
        &y, 40)
    SettingsAddShortcutRow(settings, category, "Steam.MenuShortcut",
        "Steam Menu shortcut", &y)
    SettingsAddShortcutRow(settings, category, "Steam.QuickAccessShortcut",
        "Steam Quick Access shortcut", &y)
    SettingsAddShortcutRow(settings, category, "Steam.OverlayShortcut",
        "In-game Steam overlay shortcut", &y)
    SettingsAddSectionRow(settings, category, "View button", &y)
    SettingsAddCheckboxRow(settings, category, "Steam.EnableViewButtonActions",
        "Enable View button Steam actions", &y)
    ; Tap and hold are separate switches because they misfire differently: the
    ; hold is the one a game's own use of View can trigger by accident.
    SettingsAddCheckboxRow(settings, category, "Steam.EnableViewTapAction",
        "Tap — Steam menu when Steam is in front, nothing in a game", &y)
    SettingsAddCheckboxRow(settings, category, "Steam.EnableViewHoldAction",
        "Hold — Steam Quick Access, or the overlay in a game", &y)
    SettingsAddEditRow(settings, category, "Steam.ViewHoldMs",
        "Hold, Steam in front (ms)", &y, true)
    SettingsAddEditRow(settings, category, "Steam.ViewHoldInGameMs",
        "Hold, in a game (ms)", &y, true)
    SettingsAddNoteRow(settings, category,
        "Longer in a game: View is often the scoreboard button and gets held.",
        &y)

    ; RTSS & Performance
    category := "RTSS & Performance"
    y := SettingsFirstRowY()
    SettingsAddCheckboxRow(settings, category, "RTSS.EnableIntegration",
        "Enable RTSS integration in the Quick Menu", &y)
    SettingsAddPathRow(settings, category, "RTSS.Path", "RTSS executable",
        SettingsBrowseRtss, &y)
    SettingsAddCheckboxRow(settings, category, "RTSS.UseDllIntegration",
        "Use RTSSHooks64.dll for live state and direct control (recommended)", &y)
    SettingsAddNoteRow(settings, category,
        "Loaded beside the configured RTSS.exe. Disable this to force the "
        . "shortcut controls and configured FPS cap label.", &y, 40)
    ; The two group boxes this replaces could not flow: a group box needs its
    ; height before the rows inside it exist, which is what forced the whole
    ; page into two hand-placed columns.
    SettingsAddSectionRow(settings, category, "Overlay", &y)
    SettingsAddChoiceRow(settings, category, "RTSS.OverlayControlMode",
        "Overlay control mode", ["Separate On / Off", "Toggle"], &y)
    SettingsAddShortcutRow(settings, category, "RTSS.OverlayToggleShortcut",
        "Overlay toggle shortcut", &y)
    SettingsAddShortcutRow(settings, category, "RTSS.OverlayOnShortcut",
        "Overlay on shortcut", &y)
    SettingsAddShortcutRow(settings, category, "RTSS.OverlayOffShortcut",
        "Overlay off shortcut", &y)
    SettingsAddSectionRow(settings, category, "Frame Limiter", &y)
    SettingsAddChoiceRow(settings, category, "RTSS.FrameLimiterControlMode",
        "Frame limiter control mode", ["Separate On / Off", "Toggle"], &y)
    SettingsAddEditRow(settings, category, "RTSS.PresetFrameCap",
        "Preset Frame Cap (FPS)", &y, true)
    SettingsAddCheckboxRow(settings, category,
        "RTSS.RestoreFrameLimitOnStartup",
        "Restore the last Frame Limit selection when RTSS starts", &y)
    ; OFF by default here, unlike standalone. The label leads with what it costs,
    ; because the cost is what a user who chose XFE cares about: XFE is chosen
    ; precisely because nothing in it is elevated. See README-XFE.md.
    SettingsAddCheckboxRow(settings, category,
        "RTSS.EnableElevatedFrameCapWrites",
        "Use an elevated helper to set the Frame Limit — needed when RTSS is in "
        . "Program Files, and asks for UAC at startup", &y, 44)
    SettingsAddShortcutRow(settings, category, "RTSS.CustomFrameCapShortcut",
        "Frame limiter toggle shortcut", &y)
    SettingsAddShortcutRow(settings, category, "RTSS.FrameLimiterOnShortcut",
        "Frame limiter on shortcut", &y)
    SettingsAddShortcutRow(settings, category, "RTSS.FrameLimiterOffShortcut",
        "Frame limiter off shortcut", &y)

    ; Startup Programs
    category := "Startup Programs"
    y := SettingsFirstRowY()
    SettingsAddCheckboxRow(settings, category, "StartupPrograms.Enable",
        "Launch configured startup programs with the companion", &y)
    SettingsAddEditRow(settings, category, "StartupPrograms.DelayMs",
        "Launch delay (ms)", &y, true)
    ; XFE only: standalone launches its startup programs as one batch.
    SettingsAddEditRow(settings, category, "StartupPrograms.StaggerMs",
        "Gap between launches (ms)", &y, true)
    SettingsAddChoiceRow(settings, category, "StartupPrograms.WindowMode",
        "Launch window mode", ["Normal", "Minimized", "Hidden"], &y, 150)
    StartupProgramsList := settings.AddListBox(
        "x300 y" y " w570 h180")
    SettingsTrackControl(category, StartupProgramsList)
    y += 190
    SettingsAddButtonRow(settings, category, [
        ["Add Program...", SettingsAddStartupProgram],
        ["Remove Selected", SettingsRemoveStartupProgram]], &y)
    SettingsAddNoteRow(settings, category,
        "Hidden suits background helpers that should never draw over Xbox FSE.",
        &y)
    SettingsAddCheckboxRow(settings, category,
        "StartupPrograms.LaunchDeElevated",
        "Start them as the normal user when the companion is elevated", &y)

    ; Assist — no standalone counterpart. Standalone has a coordinated Window
    ; Engine and a full Launcher Cleanup; these are the deliberately smaller
    ; versions that never touch presentation.
    category := "Assist"
    y := SettingsFirstRowY()
    SettingsAddNoteRow(settings, category,
        "Automatic help from the shared default profile. None of these ever resize, "
        . "centre or maximise anything — Xbox FSE keeps control of presentation.",
        &y, 40)
    SettingsAddCheckboxRow(settings, category, "Assist.EnableGameFocusLite",
        "Game Focus Lite — return a game to the foreground if something steals it",
        &y)
    SettingsAddCheckboxRow(settings, category, "Assist.EnableSteamAssistLite",
        "Steam Assist Lite — return to Steam when no game is running", &y)
    SettingsAddCheckboxRow(settings, category,
        "Assist.EnableLauncherCleanupLite",
        "Launcher Cleanup Lite — close game launchers once nothing is playing", &y)
    SettingsAddCheckboxRow(settings, category, "Assist.SuspendOnShellOverlay",
        "Pause while the Xbox FSE switcher or another shell overlay is on screen",
        &y)
    SettingsAddEditRow(settings, category, "Assist.TickIntervalMs",
        "Check interval (ms)", &y, true)
    SettingsAddEditRow(settings, category, "Assist.CpuThresholdPercent",
        "Game CPU threshold (%, 0 = window shape only)", &y, true)
    SettingsAddEditRow(settings, category, "Assist.ForegroundStableSec",
        "Settle time before cleanup (s)", &y, true)
    SettingsAddEditRow(settings, category, "Assist.CooldownSec",
        "Minimum time between cleanups (s)", &y, true)
    SettingsAddCheckboxRow(settings, category, "Assist.HardKill",
        "Force close launchers that ignore a polite close request", &y)
    SettingsAddNoteRow(settings, category,
        "Process lists are edited in the INI under [Assist]. Assistance always "
        . "pauses while any SteamShell XFE window is in front. Use Quick Menu → "
        . "All Settings → Advanced → Probe Screen to identify an overlay that is "
        . "not being caught.", &y, 52)

    ; Advanced
    category := "Advanced"
    y := SettingsFirstRowY()
    SettingsAddNoteRow(settings, category,
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
    LogonTaskStatusCtrl := settings.AddText("x300 y" y " w570 h20 +Wrap", "")
    SettingsTrackControl(category, LogonTaskStatusCtrl)
    y += 28
    SettingsAddCheckboxRow(settings, category, "Controller.DiagnosticLogging",
        "Log all XInput slots and GameInput on every change (diagnostic)", &y)
    SettingsAddCheckboxRow(settings, category, "Controller.RawInputProbe",
        "Log raw background HID gamepad reports (RawInput probe)", &y)
    SettingsAddNoteRow(settings, category,
        "The heartbeat log proves whether the companion remains responsive while "
        . "Xbox FSE is active. Diagnostic logging compares every controller slot "
        . "against GameInput and records the foreground process, which reveals a "
        . "virtualised pad forwarding only some buttons.", &y, 60)

    settings.AddText("x24 y616 w430 h26 vSettingsStatus", "All changes saved")
    saveButton := settings.AddButton("x620 y610 w135 h34 Default", "Save && Apply")
    saveButton.OnEvent("Click", SaveSettings)
    closeButton := settings.AddButton("x770 y610 w110 h34", "Close")
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
SettingsLayout() {
    static layout := Map(
        "labelX", 300, "labelWidth", 250,
        "controlX", 570, "controlWidth", 200,
        "contentX", 300, "contentWidth", 570,
        "contentRight", 870,
        "contentTop", 190, "contentBottom", 600,
        "scrollBarX", 878, "scrollBarWidth", 16)
    return layout
}

SettingsFirstRowY() {
    return SettingsLayout()["contentTop"]
}

; Records the control against its category AND its original geometry.
;
; Every control reaches this function -- SettingsRegisterField calls it too -- so
; it is the one choke point where positions can be captured without a builder
; being able to forget. "scrollable" separates page content from the fixed frame
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

SettingsSetRedraw(enabled) {
    global SettingsGui
    if (!IsSet(SettingsGui) || !IsObject(SettingsGui))
        return
    try DllCall("User32\SendMessageW",
        "Ptr", SettingsGui.Hwnd,
        "UInt", 0x000B, ; WM_SETREDRAW
        "Ptr", enabled ? 1 : 0,
        "Ptr", 0,
        "Ptr")
}

SettingsRepaint() {
    global SettingsGui
    if (!IsSet(SettingsGui) || !IsObject(SettingsGui))
        return
    ; RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW
    try DllCall("User32\RedrawWindow",
        "Ptr", SettingsGui.Hwnd,
        "Ptr", 0,
        "Ptr", 0,
        "UInt", 0x0185,
        "Int")
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
    SettingsSetRedraw(false)
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
        SettingsSetRedraw(true)
        SettingsRepaint()
    }
}


SettingsGetScrollTrackPosition() {
    global SettingsScrollBar
    if !IsObject(SettingsScrollBar)
        return 0
    scrollInfo := Buffer(28, 0)
    NumPut("UInt", 28, scrollInfo, 0)
    NumPut("UInt", 0x10, scrollInfo, 4) ; SIF_TRACKPOS
    try {
        if DllCall("User32\GetScrollInfo",
            "Ptr", SettingsScrollBar.Hwnd,
            "Int", 2, ; SB_CTL
            "Ptr", scrollInfo)
            return NumGet(scrollInfo, 24, "Int")
    }
    return 0
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
            newOffset := SettingsGetScrollTrackPosition()
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
    rootHwnd := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    if (rootHwnd != SettingsGui.Hwnd)
        return
    ; A list box owns its own wheel: scrolling the page out from under the
    ; startup-program list while the user is picking a row is not helpful.
    controlClass := ""
    try controlClass := WinGetClass("ahk_id " hwnd)
    if (controlClass = "ListBox" || controlClass = "SysListView32")
        return
    delta := (wParam >> 16) & 0xFFFF
    if (delta & 0x8000)
        delta -= 0x10000
    if (delta != 0)
        SettingsScroll(delta > 0 ? -1 : 1)
    return 0
}

; Audits the ORIGINAL, unscrolled geometry of every page.
;
; This runs once, on the real native controls, so it catches what a source regex
; cannot: DPI- and font-dependent control sizes, two rows accidentally given the
; same cursor value, content crossing into the category list, and controls
; running under the scrollbar. It reports rather than blocking Settings, because
; Settings is also the recovery surface.
SettingsAuditLayout() {
    global SettingsCategoryControls, SettingsControlPositions
    layout := SettingsLayout()
    contentLeft := 286
    contentRight := layout["scrollBarX"]
    issues := []
    for _, name in SettingsCategoryNames() {
        if (!SettingsCategoryControls.Has(name)
            || SettingsCategoryControls[name].Length = 0) {
            issues.Push(name ": page has no controls.")
            continue
        }
        positioned := []
        for _, control in SettingsCategoryControls[name] {
            if !SettingsControlPositions.Has(control.Hwnd) {
                issues.Push(name ": a control has no recorded position.")
                continue
            }
            pos := SettingsControlPositions[control.Hwnd]
            if (pos["w"] <= 0 || pos["h"] <= 0) {
                issues.Push(name ": a control has invalid dimensions.")
                continue
            }
            if (pos["scrollable"]
                && (pos["x"] < contentLeft
                    || pos["x"] + pos["w"] > contentRight)) {
                issues.Push(name ": a control crosses the content boundary.")
            }
            for _, previous in positioned {
                other := previous["pos"]
                overlaps := pos["x"] < other["x"] + other["w"]
                    && pos["x"] + pos["w"] > other["x"]
                    && pos["y"] < other["y"] + other["h"]
                    && pos["y"] + pos["h"] > other["y"]
                if overlaps
                    issues.Push(name ": two controls overlap at "
                        . pos["x"] "," pos["y"] ".")
            }
            positioned.Push(Map("pos", pos))
        }
    }
    return issues
}

SettingsReportLayoutAudit() {
    issues := SettingsAuditLayout()
    if (issues.Length = 0) {
        LogLine("Settings layout audit passed for all categories.")
        return true
    }
    summary := ""
    for _, issue in issues
        summary .= (summary = "" ? "" : " | ") issue
    LogLine("Settings layout audit found " issues.Length " issue(s): " summary,
        "Warning")
    SettingsUpdateStatus("Layout warning recorded in the log")
    return false
}

SettingsRegisterField(category, key, control, eventName := "Change") {
    global SettingsFields
    SettingsFields[key] := control
    SettingsTrackControl(category, control)
    control.OnEvent(eventName, SettingsMarkDirty)
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
; the index (SetDropDownMode, WindowModeChoiceToValue, ParkEdge). Reordering a
; list to match standalone's would invert the setting, so the lists keep XFE's
; order and only the labels were aligned.
SettingsAddChoiceRow(guiObj, category, key, labelText, choices, &y, width := 200) {
    layout := SettingsLayout()
    label := guiObj.AddText("x" layout["labelX"] " y" (y + 3)
        . " w" layout["labelWidth"] " h22 +0x200", labelText)
    SettingsTrackControl(category, label)
    list := guiObj.AddDropDownList("x" layout["controlX"] " y" y
        . " w" width " h300", choices)
    SettingsRegisterField(category, key, list, "Change")
    y += 34
    return list
}

SettingsAddCheckboxRow(guiObj, category, key, labelText, &y, height := 26) {
    layout := SettingsLayout()
    options := "x" layout["contentX"] " y" y " w" layout["contentWidth"]
        . " h" height
    if (height > 26)
        options .= " +Wrap"
    control := guiObj.AddCheckbox(options, labelText)
    SettingsRegisterField(category, key, control, "Click")
    y += height + 6
    return control
}

; A caption, not a field. Used where a page needs a sentence of context and for
; the section breaks that replaced the two side-by-side group boxes on the RTSS
; page -- group boxes cannot flow, because their height has to be known before
; the rows inside them exist.
SettingsAddNoteRow(guiObj, category, text, &y, height := 22) {
    layout := SettingsLayout()
    control := guiObj.AddText("x" layout["contentX"] " y" y
        . " w" layout["contentWidth"] " h" height " +Wrap", text)
    SettingsTrackControl(category, control)
    y += height + 8
    return control
}

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

SettingsAddEditRow(guiObj, category, key, labelText, &y, numeric := false, width := 150) {
    layout := SettingsLayout()
    label := guiObj.AddText("x" layout["labelX"] " y" (y + 3)
        . " w" layout["labelWidth"] " h22 +0x200", labelText)
    SettingsTrackControl(category, label)
    options := "x" layout["controlX"] " y" y " w" width " h26"
    if numeric
        options .= " Number"
    edit := guiObj.AddEdit(options)
    SettingsRegisterField(category, key, edit, "Change")
    y += 34
    return edit
}

SettingsAddShortcutRow(guiObj, category, key, labelText, &y) {
    layout := SettingsLayout()
    label := guiObj.AddText("x" layout["labelX"] " y" (y + 3)
        . " w" layout["labelWidth"] " h22 +0x200", labelText)
    SettingsTrackControl(category, label)
    edit := guiObj.AddEdit("x" layout["controlX"] " y" y " w200 h26")
    SettingsRegisterField(category, key, edit, "Change")
    button := guiObj.AddButton("x778 y" (y - 1) " w92 h28", "Record...")
    button.OnEvent("Click", SettingsRecordShortcut.Bind(key))
    SettingsTrackControl(category, button)
    y += 34
    return edit
}

; A text field with a Browse button, for a path. Wider than a plain edit row
; because a path is unreadable in 150 pixels.
SettingsAddPathRow(guiObj, category, key, labelText, browseCallback, &y) {
    layout := SettingsLayout()
    label := guiObj.AddText("x" layout["labelX"] " y" (y + 3) " w160 h22 +0x200",
        labelText)
    SettingsTrackControl(category, label)
    edit := guiObj.AddEdit("x466 y" y " w300 h26")
    SettingsRegisterField(category, key, edit, "Change")
    button := guiObj.AddButton("x774 y" (y - 1) " w96 h28", "Browse...")
    button.OnEvent("Click", browseCallback)
    SettingsTrackControl(category, button)
    y += 34
    return edit
}

; Up to three buttons on one flowing line. entries is an array of
; [label, callback] pairs; more than three wraps onto the next line.
SettingsAddButtonRow(guiObj, category, entries, &y) {
    static COLUMNS := [300, 496, 692]
    static BUTTON_WIDTH := 178
    static LINE_HEIGHT := 42
    index := 0
    for _, entry in entries {
        column := Mod(index, COLUMNS.Length)
        if (column = 0 && index > 0)
            y += LINE_HEIGHT
        button := guiObj.AddButton(
            "x" COLUMNS[column + 1] " y" y " w" BUTTON_WIDTH " h34", entry[1])
        button.OnEvent("Click", entry[2])
        SettingsTrackControl(category, button)
        index += 1
    }
    if (index > 0)
        y += LINE_HEIGHT
    return y
}

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
            "Optional automatic help: game focus, Steam return, launcher cleanup, "
            . "and when to stay out of the way."],
        ["Advanced",
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
            SetStatus("That program is already in the list", "Warning")
            return
        }
    }
    if (StartupPrograms.Length >= 40) {
        SetStatus("Startup program list is full", "Warning")
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
        SetStatus("Select a program to remove first", "Warning")
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
    SettingsCategoryTitleCtrl.Text := GuiSafeLabel(meta[1])
    SettingsCategoryDescriptionCtrl.Text := GuiSafeLabel(meta[2])
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

SettingsPopulate() {
    global SettingsFields, SettingsDirty, RtssPath
    if (SettingsFields.Count = 0)
        return
    SetFieldValue("QuickMenu.Enable", ReadBool("QuickMenu", "Enable", true))
    SetFieldValue("QuickMenu.ChordHoldMs", ReadInt("QuickMenu", "ChordHoldMs", 500, 250, 3000))
    SetFieldText("QuickMenu.AccentColor", ReadText("QuickMenu", "AccentColor", "Purple"))
    SetFieldValue("QuickMenu.AccentColorCustom", ReadText("QuickMenu", "AccentColorCustom", "107C10"))
    SetFieldValue("Companion.HeartbeatSeconds",
        ReadInt("Companion", "HeartbeatSeconds", 60, 5, 3600))
    SetFieldValue("Audio.EnableQuickControls", ReadBool("Audio", "EnableQuickControls", true))
    SetFieldValue("Display.EnableQuickControls", ReadBool("Display", "EnableQuickControls", true))
    SetFieldValue("Controller.EnableControllerMouseMode",
        ReadBool("Controller", "EnableControllerMouseMode", true))
    SetFieldValue("Controller.EnableAutoMouseMode",
        ReadBool(MovedSettingSection("Features", "Controller", "EnableAutoMouseMode"), "EnableAutoMouseMode", true))
    SetFieldValue("Controller.AutoMouseExeList",
        ReadText("Controller", "AutoMouseExeList", "explorer.exe"))
    SetBackendChoice("Controller.Backend", ReadText("Controller", "Backend", "xinput"))
    SetFieldValue("Controller.DiagnosticLogging",
        ReadBool("Controller", "DiagnosticLogging", false))
    SetFieldValue("Controller.RawInputProbe",
        ReadBool("Controller", "RawInputProbe", false))
    SetFieldValue("StartupPrograms.Enable", ReadBool("StartupPrograms", "Enable", true))
    SetFieldValue("StartupPrograms.DelayMs",
        ReadInt("StartupPrograms", "DelayMs", 2000, 0, 120000))
    SetFieldValue("StartupPrograms.StaggerMs",
        ReadInt("StartupPrograms", "StaggerMs", 1200, 0, 30000))
    SetWindowModeChoice("StartupPrograms.WindowMode",
        ReadText("StartupPrograms", "WindowMode", "Hidden"))
    SetFieldValue("StartupPrograms.LaunchDeElevated",
        ReadBool("StartupPrograms", "LaunchDeElevated", true))
    SettingsRefreshStartupProgramsList()
    SettingsRefreshLogonTaskStatus()
    SetFieldValue("Assist.EnableGameFocusLite",
        ReadBool("Assist", "EnableGameFocusLite", true))
    SetFieldValue("Assist.EnableSteamAssistLite",
        ReadBool("Assist", "EnableSteamAssistLite", true))
    SetFieldValue("Assist.EnableLauncherCleanupLite",
        ReadBool("Assist", "EnableLauncherCleanupLite", true))
    SetFieldValue("Assist.SuspendOnShellOverlay",
        ReadBool("Assist", "SuspendOnShellOverlay", true))
    SetFieldValue("Steam.MenuShortcut", ReadText("Steam", "MenuShortcut", "^1"))
    SetFieldValue("Steam.QuickAccessShortcut",
        ReadText("Steam", "QuickAccessShortcut", "^2"))
    SetFieldValue("Steam.OverlayShortcut", ReadText("Steam", "OverlayShortcut", "+{Tab}"))
    SetFieldValue("Steam.EnableViewButtonActions",
        ReadBool("Steam", "EnableViewButtonActions", true))
    SetFieldValue("Steam.EnableViewTapAction", ReadBool("Steam", "EnableViewTapAction", true))
    SetFieldValue("Steam.EnableViewHoldAction", ReadBool("Steam", "EnableViewHoldAction", true))
    SetFieldValue("Steam.ViewHoldMs", ReadInt("Steam", "ViewHoldMs", 500, 200, 5000))
    SetFieldValue("Steam.ViewHoldInGameMs",
        ReadInt("Steam", "ViewHoldInGameMs", 1000, 200, 5000))
    SetFieldValue("Assist.TickIntervalMs",
        ReadInt("Assist", "TickIntervalMs", 2000, 500, 30000))
    SetFieldValue("Assist.CpuThresholdPercent",
        ReadInt("Assist", "CpuThresholdPercent", 12, 0, 100))
    SetFieldValue("Assist.ForegroundStableSec",
        ReadInt("Assist", "ForegroundStableSec", 30, 5, 600))
    SetFieldValue("Assist.CooldownSec",
        ReadInt(MovedSettingSection("LauncherCleanup", "Assist", "CooldownSec"), "CooldownSec", 300, 30, 7200))
    SetFieldValue("Assist.HardKill", ReadBool(MovedSettingSection("LauncherCleanup", "Assist", "HardKill"), "HardKill", true))
    SetFieldValue("Controller.ControllerIndex",
        ReadInt("Controller", "ControllerIndex", 0, 0, 3))
    SetFieldValue("Controller.ControllerDeadzone",
        ReadInt("Controller", "ControllerDeadzone", 3000, 1000, 16000))
    SetFieldValue("Controller.ControllerMouseSpeed",
        ReadInt("Controller", "ControllerMouseSpeed", 100, 10, 300))
    SetFieldValue("Controller.ControllerChordHoldMs",
        ReadInt("Controller", "ControllerChordHoldMs", 500, 200, 3000))
    SetFieldValue("Cursor.EnableAutoHide", ReadBool(MovedSettingSection("Features", "Cursor", "EnableAutoHideCursor"), "EnableAutoHideCursor", true))
    SetFieldValue("Cursor.HideDelayMs", ReadInt(MovedSettingSection("Timing", "Cursor", "MouseHideDelay"), "MouseHideDelay", 1000, 250, 10000))
    SetFieldValue("Cursor.ParkOnStartup", ReadBool(MovedSettingSection("Features", "Cursor", "EnableMouseParkOnBoot"), "EnableMouseParkOnBoot", true))
    SetFieldValue("Cursor.ParkOnGameStart", ReadBool("Cursor", "ParkOnGameStart", true))
    SetFieldValue("Cursor.ParkOnSteamReturn", ReadBool("Cursor", "ParkOnSteamReturn", true))
    SetParkEdgeChoice("Cursor.ParkEdge", ReadText(MovedSettingSection("MousePark", "Cursor", "MouseParkEdge"), "MouseParkEdge", "right"))
    SetFieldValue("RTSS.EnableIntegration", ReadBool("RTSS", "EnableIntegration", true))
    SetFieldValue("RTSS.Path", ReadText("RTSS", "Path", RtssPath))
    SetFieldValue("RTSS.UseDllIntegration",
        ReadBool("RTSS", "UseDllIntegration", true))
    SetDropDownMode("RTSS.OverlayControlMode",
        ReadText("RTSS", "OverlayControlMode", "separate"))
    SetFieldValue("RTSS.OverlayOnShortcut", ReadText("RTSS", "OverlayOnShortcut", "^+1"))
    SetFieldValue("RTSS.OverlayOffShortcut", ReadText("RTSS", "OverlayOffShortcut", "^+2"))
    SetFieldValue("RTSS.OverlayToggleShortcut", ReadText("RTSS", "OverlayToggleShortcut", "^+o"))
    SetDropDownMode("RTSS.FrameLimiterControlMode",
        ReadText("RTSS", "FrameLimiterControlMode", "separate"))
    SetFieldValue("RTSS.PresetFrameCap", ReadInt("RTSS", "PresetFrameCap", 158, 0, 1000))
    SetFieldValue("RTSS.FrameLimiterOnShortcut",
        ReadText("RTSS", "FrameLimiterOnShortcut", "^+5"))
    SetFieldValue("RTSS.FrameLimiterOffShortcut",
        ReadText("RTSS", "FrameLimiterOffShortcut", "^+6"))
    SetFieldValue("RTSS.CustomFrameCapShortcut",
        ReadText("RTSS", "CustomFrameCapShortcut", "^+f"))
    ; RestoreFrameLimitOnStartup was a dead control: the checkbox existed and was
    ; registered as a field, but nothing populated it and nothing saved it, so it
    ; always drew unchecked and clearing it did nothing. Found while adding the
    ; checkbox beside it; fixed here and in SaveSettings.
    SetFieldValue("RTSS.RestoreFrameLimitOnStartup",
        ReadBool("RTSS", "RestoreFrameLimitOnStartup", true))
    SetFieldValue("RTSS.EnableElevatedFrameCapWrites",
        ReadBool("RTSS", "EnableElevatedFrameCapWrites", false))
    SettingsDirty := false
    SettingsUpdateStatus()
}

SetFieldValue(key, value) {
    global SettingsFields
    if SettingsFields.Has(key)
        SettingsFields[key].Value := value
}

SetBackendChoice(key, backend) {
    global SettingsFields
    if !SettingsFields.Has(key)
        return
    switch StrLower(Trim(backend)) {
        case "xinput":
            SettingsFields[key].Choose(2)
        case "gameinput":
            SettingsFields[key].Choose(3)
        case "rawinput":
            SettingsFields[key].Choose(4)
        default:
            SettingsFields[key].Choose(1)
    }
}

; Matches the dropdown order: 1 Auto, 2 XInput, 3 GameInput, 4 RawInput.
; Auto is first because it is the default and the only choice that works both
; inside and outside Xbox FSE.
BackendChoiceToValue(index) {
    switch index {
        case 2:
            return "xinput"
        case 3:
            return "gameinput"
        case 4:
            return "rawinput"
        default:
            return "auto"
    }
}

; Matches the dropdown order: 1 Normal, 2 Minimized, 3 Hidden.
SetWindowModeChoice(key, mode) {
    global SettingsFields
    if !SettingsFields.Has(key)
        return
    switch NormalizeWindowMode(mode) {
        case "minimized":
            SettingsFields[key].Choose(2)
        case "hidden":
            SettingsFields[key].Choose(3)
        default:
            SettingsFields[key].Choose(1)
    }
}

WindowModeChoiceToValue(index) {
    switch index {
        case 2:
            return "Minimized"
        case 3:
            return "Hidden"
        default:
            return "Normal"
    }
}

; Matches the dropdown order: 1 Right edge, 2 Left edge.
SetParkEdgeChoice(key, edge) {
    global SettingsFields
    if SettingsFields.Has(key)
        SettingsFields[key].Choose(StrLower(Trim(edge)) = "left" ? 2 : 1)
}

SetDropDownMode(key, mode) {
    global SettingsFields
    if SettingsFields.Has(key)
        SettingsFields[key].Choose(StrLower(mode) = "toggle" ? 2 : 1)
}

GetFieldValue(key, fallback := "") {
    global SettingsFields
    if !SettingsFields.Has(key)
        return fallback
    return SettingsFields[key].Value
}

SaveSettings(*) {
    global IniPath, SettingsDirty
    pairs := [
        ["QuickMenu", "Enable", GetFieldValue("QuickMenu.Enable") ? "true" : "false"],
        ["QuickMenu", "ChordHoldMs", GetFieldValue("QuickMenu.ChordHoldMs", 500)],
        ["QuickMenu", "AccentColor", GetFieldText("QuickMenu.AccentColor", "Purple")],
        ["QuickMenu", "AccentColorCustom", GetFieldValue("QuickMenu.AccentColorCustom", "107C10")],
        ["Companion", "HeartbeatSeconds", GetFieldValue("Companion.HeartbeatSeconds", 60)],
        ["Audio", "EnableQuickControls",
            GetFieldValue("Audio.EnableQuickControls") ? "true" : "false"],
        ["Display", "EnableQuickControls",
            GetFieldValue("Display.EnableQuickControls") ? "true" : "false"],
        ["Controller", "EnableControllerMouseMode",
            GetFieldValue("Controller.EnableControllerMouseMode") ? "true" : "false"],
        ["Features", "EnableAutoMouseMode",
            GetFieldValue("Controller.EnableAutoMouseMode") ? "true" : "false"],
        ["Controller", "AutoMouseExeList",
            GetFieldText("Controller.AutoMouseExeList", "explorer.exe")],
        ["Controller", "Backend",
            BackendChoiceToValue(GetFieldValue("Controller.Backend", 1))],
        ["Controller", "DiagnosticLogging",
            GetFieldValue("Controller.DiagnosticLogging") ? "true" : "false"],
        ["Controller", "RawInputProbe",
            GetFieldValue("Controller.RawInputProbe") ? "true" : "false"],
        ["StartupPrograms", "Enable",
            GetFieldValue("StartupPrograms.Enable") ? "true" : "false"],
        ["StartupPrograms", "DelayMs", GetFieldValue("StartupPrograms.DelayMs", 2000)],
        ["StartupPrograms", "StaggerMs", GetFieldValue("StartupPrograms.StaggerMs", 1200)],
        ["StartupPrograms", "WindowMode",
            WindowModeChoiceToValue(GetFieldValue("StartupPrograms.WindowMode", 3))],
        ["StartupPrograms", "LaunchDeElevated",
            GetFieldValue("StartupPrograms.LaunchDeElevated") ? "true" : "false"],
        ["Assist", "EnableGameFocusLite",
            GetFieldValue("Assist.EnableGameFocusLite") ? "true" : "false"],
        ["Assist", "EnableSteamAssistLite",
            GetFieldValue("Assist.EnableSteamAssistLite") ? "true" : "false"],
        ["Assist", "EnableLauncherCleanupLite",
            GetFieldValue("Assist.EnableLauncherCleanupLite") ? "true" : "false"],
        ["Assist", "TickIntervalMs", GetFieldValue("Assist.TickIntervalMs", 2000)],
        ["Assist", "CpuThresholdPercent", GetFieldValue("Assist.CpuThresholdPercent", 12)],
        ["Assist", "ForegroundStableSec", GetFieldValue("Assist.ForegroundStableSec", 30)],
        ["LauncherCleanup", "CooldownSec", GetFieldValue("Assist.CooldownSec", 300)],
        ["LauncherCleanup", "HardKill", GetFieldValue("Assist.HardKill") ? "true" : "false"],
        ["Assist", "SuspendOnShellOverlay",
            GetFieldValue("Assist.SuspendOnShellOverlay") ? "true" : "false"],
        ["Steam", "MenuShortcut", GetFieldValue("Steam.MenuShortcut")],
        ["Steam", "QuickAccessShortcut", GetFieldValue("Steam.QuickAccessShortcut")],
        ["Steam", "OverlayShortcut", GetFieldValue("Steam.OverlayShortcut")],
        ["Steam", "EnableViewButtonActions",
            GetFieldValue("Steam.EnableViewButtonActions") ? "true" : "false"],
        ["Steam", "EnableViewTapAction",
            GetFieldValue("Steam.EnableViewTapAction") ? "true" : "false"],
        ["Steam", "EnableViewHoldAction",
            GetFieldValue("Steam.EnableViewHoldAction") ? "true" : "false"],
        ["Steam", "ViewHoldMs", GetFieldValue("Steam.ViewHoldMs", 500)],
        ["Steam", "ViewHoldInGameMs", GetFieldValue("Steam.ViewHoldInGameMs", 1000)],
        ["Controller", "ControllerIndex", GetFieldValue("Controller.ControllerIndex", 0)],
        ["Controller", "ControllerDeadzone", GetFieldValue("Controller.ControllerDeadzone", 3000)],
        ["Controller", "ControllerMouseSpeed", GetFieldValue("Controller.ControllerMouseSpeed", 100)],
        ["Controller", "ControllerChordHoldMs",
            GetFieldValue("Controller.ControllerChordHoldMs", 500)],
        ["Features", "EnableAutoHideCursor",
            GetFieldValue("Cursor.EnableAutoHide") ? "true" : "false"],
        ["Timing", "MouseHideDelay", GetFieldValue("Cursor.HideDelayMs", 1000)],
        ["Features", "EnableMouseParkOnBoot",
            GetFieldValue("Cursor.ParkOnStartup") ? "true" : "false"],
        ["Cursor", "ParkOnGameStart",
            GetFieldValue("Cursor.ParkOnGameStart") ? "true" : "false"],
        ["Cursor", "ParkOnSteamReturn",
            GetFieldValue("Cursor.ParkOnSteamReturn") ? "true" : "false"],
        ["MousePark", "MouseParkEdge",
            GetFieldValue("Cursor.ParkEdge", 1) = 2 ? "left" : "right"],
        ["RTSS", "EnableIntegration",
            GetFieldValue("RTSS.EnableIntegration") ? "true" : "false"],
        ["RTSS", "Path", GetFieldValue("RTSS.Path")],
        ["RTSS", "UseDllIntegration",
            GetFieldValue("RTSS.UseDllIntegration") ? "true" : "false"],
        ["RTSS", "OverlayControlMode",
            GetFieldValue("RTSS.OverlayControlMode") = 2 ? "toggle" : "separate"],
        ["RTSS", "OverlayOnShortcut", GetFieldValue("RTSS.OverlayOnShortcut")],
        ["RTSS", "OverlayOffShortcut", GetFieldValue("RTSS.OverlayOffShortcut")],
        ["RTSS", "OverlayToggleShortcut", GetFieldValue("RTSS.OverlayToggleShortcut")],
        ["RTSS", "FrameLimiterControlMode",
            GetFieldValue("RTSS.FrameLimiterControlMode") = 2 ? "toggle" : "separate"],
        ["RTSS", "PresetFrameCap", GetFieldValue("RTSS.PresetFrameCap", 158)],
        ["RTSS", "FrameLimiterOnShortcut", GetFieldValue("RTSS.FrameLimiterOnShortcut")],
        ["RTSS", "FrameLimiterOffShortcut", GetFieldValue("RTSS.FrameLimiterOffShortcut")],
        ["RTSS", "CustomFrameCapShortcut", GetFieldValue("RTSS.CustomFrameCapShortcut")],
        ["RTSS", "RestoreFrameLimitOnStartup",
            GetFieldValue("RTSS.RestoreFrameLimitOnStartup") ? "true" : "false"],
        ["RTSS", "EnableElevatedFrameCapWrites",
            GetFieldValue("RTSS.EnableElevatedFrameCapWrites") ? "true" : "false"]
    ]
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
        SetStatus("Settings saved and applied")
    } catch as err {
        SettingsUpdateStatus("Save failed: " err.Message)
        SetStatus("Settings save failed: " err.Message, "Warning")
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
    builtins := editor.AddDropDownList("xm y+12 w220 Choose1", [
        "None", "Left click", "Right click", "Enter", "Back / Escape",
        "Close window", "Touch keyboard", "Classic keyboard", "Game Bar",
        "Start menu", "File Explorer", "Application switcher", "Task Manager",
        "Task View", "Windows desktop", "Quick Menu", "Settings"
    ])
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
    values := Map(
        "None", "Builtin:None",
        "Left click", "Builtin:LeftClick",
        "Right click", "Builtin:RightClick",
        "Enter", "Builtin:Enter",
        "Back / Escape", "Builtin:Esc",
        "Close window", "Builtin:AltF4",
        "Touch keyboard", "Builtin:TabTip",
        "Classic keyboard", "Builtin:OSK",
        "Game Bar", "Builtin:WinG",
        "Start menu", "Builtin:StartMenu",
        "File Explorer", "Builtin:Explorer",
        "Application switcher", "Builtin:CtrlAltTab",
        "Task Manager", "Builtin:TaskManager",
        "Task View", "Builtin:TaskView",
        "Windows desktop", "Builtin:WindowsDesktop",
        "Quick Menu", "Builtin:QuickMenu",
        "Settings", "Builtin:Settings"
    )
    return values.Has(label) ? values[label] : "Builtin:None"
}

MappingSetBuiltin(dropDown, *) {
    global ControllerMap, ControllerMapDisplay, IniPath
    key := SelectedMappingKey()
    if (key = "") {
        SetStatus("Select a controller mapping first", "Warning")
        return
    }
    if MappingKeyIsReservedForMouse(key) {
        SetStatus(key " is reserved: that button is held to drag the mouse",
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
    SetStatus(key " updated")
}

MappingRecordShortcut(*) {
    global ControllerMap, ControllerMapDisplay, IniPath, SettingsDialogActive
    key := SelectedMappingKey()
    if (key = "") {
        SetStatus("Select a controller mapping first", "Warning")
        return
    }
    if MappingKeyIsReservedForMouse(key) {
        SetStatus(key " is reserved: that button is held to drag the mouse",
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
        SetStatus(key " recorded as " result["display"])
    }
}

MappingRestoreDefaults(*) {
    global ControllerMap, ControllerMapDisplay, IniPath
    answer := TopmostMsgBox("Restore every controller mapping to its default?",
        "Controller Mappings", "YesNo Icon?")
    if (answer != "Yes")
        return
    DefaultControllerMappings()
    for key, value in ControllerMap {
        IniWrite(value, IniPath, "ControllerMap", key)
        if ControllerMapDisplay.Has(key)
            IniWrite(ControllerMapDisplay[key], IniPath, "ControllerMap", key ".Display")
        else
            try IniDelete(IniPath, "ControllerMap", key ".Display")
    }
    RefreshMappingList()
    SetStatus("Controller mappings restored to defaults")
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
    try {
        DirCreate(tempDir)

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
        FileAppend(SanitizeDiagnosticText(info), tempDir "\Environment.txt", "UTF-8")

        if FileExist(IniPath)
            FileAppend(SanitizeDiagnosticText(FileRead(IniPath)),
                tempDir "\SteamShell-XFE-settings.ini", "UTF-8")
        if FileExist(LogPath)
            FileAppend(SanitizeDiagnosticText(GetLastLines(FileRead(LogPath), 2000)),
                tempDir "\SteamShell-XFE-log-tail.txt", "UTF-8")

        ; PowerShell wants the paths in single quotes, with any literal single
        ; quote doubled. Building that quote from Chr(39) keeps AHK's own string
        ; escaping out of it: a run of three quote characters is read by AHK as
        ; an escaped quote, which silently moves the string boundaries.
        psQuote := Chr(39)
        psSource := StrReplace(tempDir "\*", psQuote, psQuote psQuote)
        psTarget := StrReplace(zipPath, psQuote, psQuote psQuote)
        psCommand := "Compress-Archive -Path " psQuote psSource psQuote
            . " -DestinationPath " psQuote psTarget psQuote " -Force"
        exitCode := RunWait('powershell -NoProfile -NonInteractive -Command "'
            . psCommand '"', , "Hide")
        try DirDelete(tempDir, true)
        if (exitCode = 0 && FileExist(zipPath)) {
            SetStatus("Diagnostics saved to the desktop")
            LogLine("Diagnostic bundle written to " zipPath ".")
            try Run('explorer.exe /select,"' zipPath '"')
        } else {
            SetStatus("Could not create the diagnostic ZIP", "Warning")
            LogLine("Diagnostic bundle failed (exit " exitCode ").", "Warning")
        }
    } catch as err {
        try DirDelete(tempDir, true)
        SetStatus("Diagnostics export failed: " err.Message, "Warning")
        LogLine("Diagnostic bundle error: " err.Message, "Warning")
    }
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

    controller := Buffer(16, 0)
    if ControllerReadState(&controller) {
        HealthResult(results, "PASS", "Controller",
            ActiveInputBackend = "rawinput"
                ? "Reading through RawInput, which works inside Xbox FSE."
                : (ActiveInputBackend = "gameinput"
                    ? "Reading through GameInput."
                    : "Detected at XInput slot " ActiveControllerIndex "."))
    } else {
        HealthResult(results, "WARN", "Controller",
            "No controller detected on any backend.")
    }
    HealthResult(results, "INFO", "Input backend",
        "Setting: " ControllerBackend ". Active: " ActiveInputBackend ".")
    HealthResult(results,
        !RawInputProbeActive ? "INFO" : (RawInputLastReportTick ? "PASS" : "INFO"),
        "RawInput",
        !RawInputProbeActive
            ? "Not registered."
            : (RawInputLastReportTick
                ? "Registered and receiving HID reports."
                : "Registered, no reports yet. Expected outside Xbox FSE."))
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
    CenterGuiOnMonitorActual(guiObj, GetMonitorIndexForWindow(WinExist("A")), 900, 560)
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
    inPoll := true
    try {
        for definition in buttonDefinitions {
            name := definition[1]
            if !downTick.Has(name)
                downTick[name] := 0
            if !longFired.Has(name)
                longFired[name] := false
        }
        if !downTick.Has("LT")
            downTick["LT"] := 0
        if !downTick.Has("RT")
            downTick["RT"] := 0
        if !longFired.Has("LT")
            longFired["LT"] := false
        if !longFired.Has("RT")
            longFired["RT"] := false

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
        if (wasDisabled || ControllerNeedsFreshBaseline) {
            ; Establish a fresh baseline without firing edges for buttons that
            ; happen to be held at the instant the companion is enabled.
            if ControllerReadState(&state) {
                ResetControllerEdgeState(downTick, longFired, triggerDown,
                    buttonDefinitions)
                previousButtons := NumGet(state, 4, "UShort")
                previousViewDown := (previousButtons & 0x0020) != 0
                viewWasDown := previousViewDown
                wasDisabled := false
                ControllerNeedsFreshBaseline := false
            }
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
        if LearnActive {
            previousButtons := 0
            previousViewDown := false
            viewWasDown := false
            quickChordSince := 0
            quickChordFired := false
            ResetControllerEdgeState(downTick, longFired, triggerDown, buttonDefinitions)
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
        buttons := NumGet(state, 4, "UShort")
        lt := NumGet(state, 6, "UChar")
        rt := NumGet(state, 7, "UChar")
        lx := NumGet(state, 8, "Short")
        ly := NumGet(state, 10, "Short")
        rx := NumGet(state, 12, "Short")
        ry := NumGet(state, 14, "Short")
        pressed := buttons & ~previousButtons
        released := (~buttons) & previousButtons
        previousButtons := buttons
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

        if (Abs(lx) < ControllerDeadzone)
            lx := 0
        if (Abs(ly) < ControllerDeadzone)
            ly := 0
        if (Abs(rx) < ControllerDeadzone)
            rx := 0
        if (Abs(ry) < ControllerDeadzone)
            ry := 0

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
        if settingsComboDown {
            if !settingsChordSince
                settingsChordSince := now
            if (!settingsChordFired && now - settingsChordSince >= QuickMenuChordHoldMs) {
                settingsChordFired := true
                LogLine("Controller Settings chord detected [" ActiveInputBackend "].")
                ShowSettings()
                return
            }
        } else {
            settingsChordSince := 0
            settingsChordFired := false
        }

        ; Quick Menu: hold L3 + R3 with no conflicting chord buttons.
        quickChordDown := EnableQuickMenu
            && (buttons & 0x0040) && (buttons & 0x0080)
            && !(buttons & 0x0020) && !(buttons & 0x0010)
            && !(buttons & 0x0100) && !(buttons & 0x0200)
            && lt <= 30 && rt <= 30
        if quickChordDown {
            if !quickChordSince
                quickChordSince := now
            if (!quickChordFired && now - quickChordSince >= QuickMenuChordHoldMs) {
                quickChordFired := true
                LogLine("Controller Quick Menu chord detected on slot "
                    ActiveControllerIndex ".")
                ToggleQuickMenu()
                return
            }
        } else {
            quickChordSince := 0
            quickChordFired := false
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
        viewDown := (buttons & 0x0020) != 0
        if viewDown {
            if !viewWasDown {
                viewWasDown := true
                viewPressTick := now
                viewUsedAsModifier := false
            }
            ; Any other input during the hold means View was being used as the
            ; mapping modifier or to drive the pointer, so its own action is
            ; suppressed on release.
            if ((buttons & ~0x0020) || lt > 30 || rt > 30
                || lx != 0 || ly != 0 || rx != 0 || ry != 0)
                viewUsedAsModifier := true
        } else if viewWasDown {
            viewWasDown := false
            ViewButtonReleased(now - viewPressTick, viewUsedAsModifier)
            viewUsedAsModifier := false
        }

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

        if !previousViewDown {
            for definition in buttonDefinitions {
                name := definition[1]
                mask := definition[2]
                if (buttons & mask) {
                    downTick[name] := now
                    longFired[name] := false
                }
            }
            if (lt > 30)
                downTick["LT"] := now, triggerDown["LT"] := true
            if (rt > 30)
                downTick["RT"] := now, triggerDown["RT"] := true
        }
        previousViewDown := true

        ApplyControllerMouseMove(rx, ry,
            rt > 30 ? Round(ControllerMouseSpeed * ControllerMouseFastMultiplier)
                    : ControllerMouseSpeed)
        if (ly != 0 && now - lastScroll >= ControllerScrollIntervalMs) {
            lastScroll := now
            ApplyControllerMouseScroll(ly, ControllerScrollStep)
        }

        for definition in buttonDefinitions {
            name := definition[1]
            mask := definition[2]
            ; Left click is press-and-hold, so it can drag. Down on press, up on
            ; release, and no Short/Long for that button: Short fires on release,
            ; by which time a drag has already happened. The mapping editor shows
            ; the Long slot as reserved.
            if ControllerBindingHoldsMouseButton(GetBindingValue(name ".Short")) {
                if (pressed & mask)
                    HoldControllerMouseButton("LButton")
                if (released & mask)
                    ReleaseControllerMouseButtons()
                downTick[name] := 0, longFired[name] := false
                continue
            }
            if (pressed & mask)
                downTick[name] := now, longFired[name] := false
            if ((buttons & mask) && !longFired[name] && downTick[name]
                && now - downTick[name] >= ControllerChordHoldMs
                && HasLongBinding(name)) {
                longFired[name] := true
                ExecuteControllerBinding(name ".Long")
            }
            if ((released & mask) && downTick[name]) {
                if !longFired[name]
                    ExecuteControllerBinding(name ".Short")
                downTick[name] := 0
                longFired[name] := false
            }
        }

        for _, triggerName in ["LT", "RT"] {
            isDown := triggerName = "LT" ? lt > 30 : rt > 30
            justPressed := isDown && !triggerDown[triggerName]
            justReleased := !isDown && triggerDown[triggerName]
            triggerDown[triggerName] := isDown
            if ControllerBindingHoldsMouseButton(
                GetBindingValue(triggerName ".Short")) {
                if justPressed
                    HoldControllerMouseButton("LButton")
                if justReleased
                    ReleaseControllerMouseButtons()
                downTick[triggerName] := 0, longFired[triggerName] := false
                continue
            }
            if justPressed
                downTick[triggerName] := now, longFired[triggerName] := false
            if (isDown && !longFired[triggerName] && downTick[triggerName]
                && now - downTick[triggerName] >= ControllerChordHoldMs
                && HasLongBinding(triggerName)) {
                longFired[triggerName] := true
                ExecuteControllerBinding(triggerName ".Long")
            }
            if (justReleased && downTick[triggerName]) {
                if !longFired[triggerName]
                    ExecuteControllerBinding(triggerName ".Short")
                downTick[triggerName] := 0
                longFired[triggerName] := false
            }
        }

        if (pressed & 0x0001)
            try SendInput("{Up}")
        if (pressed & 0x0002)
            try SendInput("{Down}")
        if (pressed & 0x0004)
            try SendInput("{Left}")
        if (pressed & 0x0008)
            try SendInput("{Right}")
        if (pressed & 0x0400)
            ExecuteControllerBinding("Y.Short")
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
if ParkOnStartup
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
    ; SetStatus, not a dialog. This runs during startup and the companion starts
    ; alongside Steam under Xbox FSE -- a modal here would land on top of a
    ; session the user is in the middle of entering. The Quick Menu shows it when
    ; opened, the tray tip carries it meanwhile, and Health Check has the detail.
    alert := InstallationRecordAlert(A_ScriptDir, A_ScriptDir, "Portable")
    if (alert != "")
        SetStatus(alert, "Warning")
}

; Seam for SteamShell-Shared.ahk. ProcessExist plus clearing the stale flag;
; the shell re-verifies identity as well, which is the stronger check.
ProductElevatedHelperAlive() {
    return EnsureElevatedRtssHelperAlive()
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


EnsureRtssRunning() {
    path := ResolveRtssExecutablePath()
    if ProcessExist("RTSS.exe")
        return true
    if (path = "")
        return false
    try {
        Run('"' path '"', , "Min")
        return ProcessWait("RTSS.exe", 3) != 0
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
    static cachedResult := false
    static cachedTick := 0
    ; All kill switches are checked ahead of the cache so tray/Settings changes
    ; take effect on the next poll rather than up to 250 ms later.
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
