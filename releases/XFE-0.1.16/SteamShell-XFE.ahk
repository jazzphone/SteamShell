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

global AppVersion := "0.1.16"
global SettingsSchemaVersion := 3
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
global EnableQuickMenu := true
global QuickMenuChordHoldMs := 700
global EnableControllerMouseMode := true
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
global ControllerDeadzone := 4000
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
; All three default to OFF. They change what the machine does on its own, so
; they are opt-in rather than something a fresh install starts doing unasked.
; ------------------------------------------------------------------------------
global EnableGameFocusLite := false
global EnableSteamAssistLite := false
global EnableLauncherCleanupLite := false
global AssistTickIntervalMs := 2000
global AssistCpuThresholdPercent := 12
global AssistForegroundStableSec := 20
global AssistCooldownSec := 300
global AssistGracefulCloseMs := 4000
global AssistHardKill := false
global AssistRequireNoGame := true
global AssistLauncherProcesses := "EpicGamesLauncher.exe|EADesktop.exe|EABackgroundService.exe|Battle.net.exe|UbisoftConnect.exe|upc.exe|GalaxyClient.exe|Origin.exe"
global AssistProtectedProcesses := "explorer.exe|steam.exe|steamwebhelper.exe|AnyFSE.exe|SteamShell-XFE.exe|dwm.exe|csrss.exe|winlogon.exe"
global AssistIgnoreForegroundProcesses := "ApplicationFrameHost.exe|ShellHost.exe|GameBar.exe|XboxGameBarWidgets.exe|SearchHost.exe|StartMenuExperienceHost.exe|ShellExperienceHost.exe"
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

; ------------------------------------------------------------------------------
; Startup programs
;
; Launches a list of applications shortly after the companion starts, so extra
; tools can come up in an FSE session without needing a second startup mechanism.
; ------------------------------------------------------------------------------
global EnableStartupPrograms := false
global StartupProgramDelayMs := 4000
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
global StartupWindowMode := "normal"
global StartupPrograms := []

; Optional startup curtain, adapted from SteamShell 1.5. This companion does
; not gate Steam or manage Xbox FSE: it only covers the primary display while a
; black curtain or an MPV-hosted startup video is visible.
global EnableStartupSplash := false
global StartupSplashMode := "black"
global StartupSplashVideoPath := ""
global StartupSplashMpvPath := ""
global StartupSplashMute := false
global StartupSplashPlayFull := true
global StartupSplashForceSdr := true
global StartupSplashDurationMs := 10000
global StartupSplashSafetyMaxMs := 15000
global StartupSplashFadeOutMs := 300
global StartupSplashGui := unset
global StartupSplashMpvPid := 0
global StartupSplashMpvHwnd := 0
global StartupSplashClosing := false

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
global EnableRTSSIntegration := false
global RtssPath := "C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe"
global RtssUseDllIntegration := true
global RtssOverlayControlMode := "separate"
global RtssOverlayToggleShortcut := "^+o"
global RtssOverlayOnShortcut := "^+1"
global RtssOverlayOffShortcut := "^+2"
global RtssFrameLimiterControlMode := "separate"
global RtssCustomFrameCap := 0
global RtssCustomFrameCapShortcut := "^+f"
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
; Repaint cache for the global FramerateLimit read. QuickMenuRender rebuilds
; every row on every refresh and each miss costs a LoadProfile plus a
; GetProfileProperty round trip. Zeroed after any write so the row never shows
; a value it just replaced.
global RtssFrameLimitCacheFps := 0
global RtssFrameLimitCacheTick := 0
; Value the user is currently dialling in, before it reaches RTSS. 0 = nothing
; pending. See AdjustRtssCustomFrameCap.
global RtssPendingFrameCap := 0

; Controller mappings are active while View/Back is held.
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
global LastObservedForegroundHwnd := 0
global LastObservedForegroundWasGame := false

; Quick Menu state.
global QuickMenuGui := unset
global QuickMenuVisible := false
global QuickMenuPage := "MAIN"
global QuickMenuRows := []
global QuickMenuSelected := 1
; Quick Menu palette. One place to change the look; every row colour is derived
; from these rather than repeated as literals through the renderer.
global QM_BG := "171A21"          ; window background
global QM_ROW_SELECTED := "222C3A" ; selected row fill
global QM_ACCENT := "66C0F4"      ; selected row accent bar and value
global QM_LABEL := "C6CCD8"       ; unselected label
global QM_LABEL_SELECTED := "FFFFFF"
global QM_VALUE := "7E8899"       ; unselected value, dimmer for hierarchy
global QuickMenuTitleCtrl := 0
global QuickMenuStatusCtrl := 0
global QuickMenuLabelCtrls := []
global QuickMenuValueCtrls := []
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

; Settings and shortcut-capture state.
global SettingsGui := unset
global SettingsFields := Map()
global SettingsVisible := false
global SettingsDirty := false
global SettingsDialogActive := false
global SettingsCategoryControls := Map()
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
            "SettingsSchemaVersion", 3,
            "HeartbeatSeconds", 60
        ),
        "QuickMenu", Map(
            "Enable", "true",
            "ChordHoldMs", 700
        ),
        "Controller", Map(
            "EnableControllerMouseMode", "true",
            "Backend", "auto",
            "DiagnosticLogging", "false",
            "RawInputProbe", "false",
            "RawInputStaleMs", 5000,
            "ControllerIndex", 0,
            "ControllerPollIntervalMs", 16,
            "ControllerDeadzone", 4000,
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
            "Enable", "false",
            "DelayMs", 4000,
            "StaggerMs", 1200,
            "WindowMode", "Normal",
            "LaunchDeElevated", "true"
        ),
        "StartupSplash", Map(
            "Enable", "false",
            "Mode", "Black",
            "VideoPath", "",
            "MpvPath", "",
            "Mute", "false",
            "PlayFullDuration", "true",
            "ForceSDR", "true",
            "DurationMs", 10000,
            "SafetyMaxMs", 15000,
            "FadeOutMs", 300
        ),
        "Assist", Map(
            "EnableGameFocusLite", "false",
            "EnableSteamAssistLite", "false",
            "EnableLauncherCleanupLite", "false",
            "TickIntervalMs", 2000,
            "CpuThresholdPercent", 12,
            "ForegroundStableSec", 20,
            "CooldownSec", 300,
            "GracefulCloseMs", 4000,
            "HardKill", "false",
            "RequireNoGame", "true",
            "LauncherProcesses", "EpicGamesLauncher.exe|EADesktop.exe|EABackgroundService.exe|Battle.net.exe|UbisoftConnect.exe|upc.exe|GalaxyClient.exe|Origin.exe",
            "ProtectedProcesses", "explorer.exe|steam.exe|steamwebhelper.exe|AnyFSE.exe|SteamShell-XFE.exe|dwm.exe|csrss.exe|winlogon.exe",
            "IgnoreForegroundProcesses", "ApplicationFrameHost.exe|ShellHost.exe|GameBar.exe|XboxGameBarWidgets.exe|SearchHost.exe|StartMenuExperienceHost.exe|ShellExperienceHost.exe",
            "SuspendOnShellOverlay", "true",
            "ShellOverlayProcesses", "class:XamlExplorerHostIslandWindow|class:MultitaskingViewFrame|class:Windows.UI.Core.CoreWindow|XboxPcApp.exe|GameBar.exe|XboxGameBarWidgets.exe|ShellHost.exe"
        ),
        "Cursor", Map(
            "EnableAutoHide", "true",
            "HideDelayMs", 1000,
            "ParkOnStartup", "true",
            "ParkOnGameStart", "true",
            "ParkOnSteamReturn", "true",
            "ParkEdge", "right",
            "ParkYPercent", 0.50,
            "ForegroundPollMs", 500
        ),
        "Audio", Map(
            "EnableQuickControls", "true"
        ),
        "Display", Map(
            "EnableQuickControls", "true"
        ),
        "RTSS", Map(
            "EnableIntegration", "false",
            "Path", "C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe",
            "UseDllIntegration", "true",
            "OverlayControlMode", "separate",
            "OverlayToggleShortcut", "^+o",
            "OverlayOnShortcut", "^+1",
            "OverlayOffShortcut", "^+2",
            "FrameLimiterControlMode", "separate",
            "CustomFrameCap", 0,
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

ReadBool(section, key, fallback) {
    global IniPath
    value := ""
    try value := IniRead(IniPath, section, key, fallback ? "true" : "false")
    value := StrLower(Trim(value))
    return value = "1" || value = "true" || value = "yes" || value = "on"
}

ReadInt(section, key, fallback, minimum, maximum) {
    global IniPath
    value := fallback
    try value := Round(IniRead(IniPath, section, key, fallback))
    catch
        value := fallback
    return Max(minimum, Min(maximum, value))
}

ReadNumber(section, key, fallback, minimum, maximum) {
    global IniPath
    value := fallback
    try value := IniRead(IniPath, section, key, fallback) + 0
    catch
        value := fallback
    return Max(minimum, Min(maximum, value))
}

ReadText(section, key, fallback := "") {
    global IniPath
    value := fallback
    try value := IniRead(IniPath, section, key, fallback)
    return Trim(value)
}

LoadSettings() {
    global HeartbeatSeconds, EnableQuickMenu, QuickMenuChordHoldMs
    global EnableControllerMouseMode, ControllerIndex, ControllerPollIntervalMs
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
    global EnableStartupSplash, StartupSplashMode
    global StartupSplashVideoPath, StartupSplashMpvPath
    global StartupSplashMute, StartupSplashPlayFull, StartupSplashForceSdr
    global StartupSplashDurationMs, StartupSplashSafetyMaxMs
    global StartupSplashFadeOutMs
    global EnableAutoHideCursor, MouseHideDelayMs, ParkOnStartup
    global ParkOnGameStart, ParkOnSteamReturn, ParkEdge, ParkYPercent
    global ForegroundPollMs
    global EnableAudioQuickControls, EnableDisplayQuickControls
    global EnableRTSSIntegration, RtssPath, RtssUseDllIntegration
    global RtssOverlayControlMode
    global RtssOverlayToggleShortcut, RtssOverlayOnShortcut, RtssOverlayOffShortcut
    global RtssFrameLimiterControlMode, RtssCustomFrameCap
    global RtssCustomFrameCapShortcut, RtssFrameLimiterOnShortcut, RtssFrameLimiterOffShortcut

    ; Floor of 5s rather than 15s: during a short diagnostic run inside Xbox FSE
    ; the heartbeat is the only proof the process is still alive, and a 60s gap
    ; is long enough to hide a death for the whole test.
    HeartbeatSeconds := ReadInt("Companion", "HeartbeatSeconds", 60, 5, 3600)
    EnableQuickMenu := ReadBool("QuickMenu", "Enable", true)
    QuickMenuChordHoldMs := ReadInt("QuickMenu", "ChordHoldMs", 700, 250, 3000)
    EnableControllerMouseMode := ReadBool("Controller", "EnableControllerMouseMode", true)
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
    ControllerDeadzone := ReadInt("Controller", "ControllerDeadzone", 4000, 1000, 16000)
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
    EnableStartupPrograms := ReadBool("StartupPrograms", "Enable", false)
    StartupProgramDelayMs := ReadInt("StartupPrograms", "DelayMs", 4000, 0, 120000)
    StartupProgramStaggerMs := ReadInt("StartupPrograms", "StaggerMs", 1200, 0, 30000)
    StartupLaunchDeElevated := ReadBool("StartupPrograms", "LaunchDeElevated", true)
    StartupWindowMode := NormalizeWindowMode(
        ReadText("StartupPrograms", "WindowMode", "Normal"))
    LoadStartupPrograms()
    EnableStartupSplash := ReadBool("StartupSplash", "Enable", false)
    StartupSplashMode := StrLower(
        ReadText("StartupSplash", "Mode", "Black"))
    if (StartupSplashMode != "video")
        StartupSplashMode := "black"
    StartupSplashVideoPath := ReadText("StartupSplash", "VideoPath", "")
    StartupSplashMpvPath := ReadText("StartupSplash", "MpvPath", "")
    StartupSplashMute := ReadBool("StartupSplash", "Mute", false)
    StartupSplashPlayFull := ReadBool(
        "StartupSplash", "PlayFullDuration", true)
    StartupSplashForceSdr := ReadBool("StartupSplash", "ForceSDR", true)
    StartupSplashDurationMs := ReadInt(
        "StartupSplash", "DurationMs", 10000, 0, 60000)
    StartupSplashSafetyMaxMs := ReadInt(
        "StartupSplash", "SafetyMaxMs", 15000, 1000, 600000)
    StartupSplashFadeOutMs := ReadInt(
        "StartupSplash", "FadeOutMs", 300, 0, 5000)
    EnableGameFocusLite := ReadBool("Assist", "EnableGameFocusLite", false)
    EnableSteamAssistLite := ReadBool("Assist", "EnableSteamAssistLite", false)
    EnableLauncherCleanupLite := ReadBool("Assist", "EnableLauncherCleanupLite", false)
    AssistTickIntervalMs := ReadInt("Assist", "TickIntervalMs", 2000, 500, 30000)
    AssistCpuThresholdPercent := ReadInt("Assist", "CpuThresholdPercent", 12, 0, 100)
    AssistForegroundStableSec := ReadInt("Assist", "ForegroundStableSec", 20, 5, 600)
    AssistCooldownSec := ReadInt("Assist", "CooldownSec", 300, 30, 7200)
    AssistGracefulCloseMs := ReadInt("Assist", "GracefulCloseMs", 4000, 500, 30000)
    AssistHardKill := ReadBool("Assist", "HardKill", false)
    AssistRequireNoGame := ReadBool("Assist", "RequireNoGame", true)
    AssistLauncherProcesses := ReadText("Assist", "LauncherProcesses", AssistLauncherProcesses)
    AssistProtectedProcesses := ReadText("Assist", "ProtectedProcesses", AssistProtectedProcesses)
    AssistIgnoreForegroundProcesses := ReadText("Assist", "IgnoreForegroundProcesses",
        AssistIgnoreForegroundProcesses)
    AssistSuspendOnShellOverlay := ReadBool("Assist", "SuspendOnShellOverlay", true)
    AssistShellOverlayProcesses := ReadText("Assist", "ShellOverlayProcesses",
        AssistShellOverlayProcesses)
    EnableAutoHideCursor := ReadBool("Cursor", "EnableAutoHide", true)
    MouseHideDelayMs := ReadInt("Cursor", "HideDelayMs", 1000, 250, 10000)
    ParkOnStartup := ReadBool("Cursor", "ParkOnStartup", true)
    ParkOnGameStart := ReadBool("Cursor", "ParkOnGameStart", true)
    ParkOnSteamReturn := ReadBool("Cursor", "ParkOnSteamReturn", true)
    ParkEdge := StrLower(Trim(ReadText("Cursor", "ParkEdge", "right"))) = "left"
        ? "left" : "right"
    ParkYPercent := ReadNumber("Cursor", "ParkYPercent", 0.50, 0.05, 0.95)
    ForegroundPollMs := ReadInt("Cursor", "ForegroundPollMs", 500, 250, 5000)
    EnableAudioQuickControls := ReadBool("Audio", "EnableQuickControls", true)
    EnableDisplayQuickControls := ReadBool("Display", "EnableQuickControls", true)
    EnableRTSSIntegration := ReadBool("RTSS", "EnableIntegration", false)
    RtssPath := ReadText("RTSS", "Path", "C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe")
    RtssUseDllIntegration := ReadBool("RTSS", "UseDllIntegration", true)
    if !RtssUseDllIntegration
        ShutdownRtssHooksApi()
    RtssOverlayControlMode := StrLower(ReadText("RTSS", "OverlayControlMode", "separate"))
    RtssOverlayToggleShortcut := ReadText("RTSS", "OverlayToggleShortcut", "^+o")
    RtssOverlayOnShortcut := ReadText("RTSS", "OverlayOnShortcut", "^+1")
    RtssOverlayOffShortcut := ReadText("RTSS", "OverlayOffShortcut", "^+2")
    RtssFrameLimiterControlMode := StrLower(ReadText("RTSS", "FrameLimiterControlMode", "separate"))
    RtssCustomFrameCap := ReadInt("RTSS", "CustomFrameCap", 0, 0, 1000)
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
    global AssistTickIntervalMs, CompanionDisabled
    SetTimer(PollController, 0)
    SetTimer(MouseWatch, 0)
    SetTimer(ObserveForeground, 0)
    SetTimer(Heartbeat, 0)
    SetTimer(ControllerDiagnosticTick, 0)
    SetTimer(AssistTick, 0)
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

RefreshTrayMenuState() {
    global CompanionDisabled
    if CompanionDisabled {
        try A_TrayMenu.Rename("Disable", "Enable")
        try A_TrayMenu.Disable("Open Quick Menu")
        A_IconTip := "SteamShell XFE — Disabled"
    } else {
        try A_TrayMenu.Rename("Enable", "Disable")
        try A_TrayMenu.Enable("Open Quick Menu")
        A_IconTip := "SteamShell XFE"
    }
}

SetCompanionDisabled(disabled) {
    global CompanionDisabled, ControllerNeedsFreshBaseline
    global QuickMenuVisible, MouseHidden
    global LearnActive, _ShortcutCap
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
        SetTimer(RefreshQuickMenuAfterRtssStart, 0)
        SetTimer(QuickMenuDisplayReflow, 0)
        CloseStartupSplash(true)
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
    RefreshTrayMenuState()
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

InitializeTrayMenu() {
    iconPath := A_ScriptDir "\assets\SteamShell-XFE.ico"
    if FileExist(iconPath)
        try TraySetIcon(iconPath)
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Open Quick Menu", TrayOpenQuickMenu)
    A_TrayMenu.Add("Open Settings", TrayOpenSettings)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Disable", ToggleCompanionDisabled)
    A_TrayMenu.Add("Exit", ExitCompanion)
    A_TrayMenu.Default := "Open Quick Menu"
    RefreshTrayMenuState()
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
    if QuickMenuVisible
        QuickMenuBuildGui()
    if SettingsVisible
        SettingsPopulate()
    SetStatus("Settings reloaded", "Info")
}

LogLine(message, level := "Info") {
    global LogPath
    line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " message "`r`n"
    try FileAppend(line, LogPath, "UTF-8")
}

SetStatus(message, level := "Info") {
    global LastStatusText, LastStatusLevel, QuickMenuVisible
    global LastStatusTick, StatusVisibleMs
    LastStatusText := message
    LastStatusLevel := level
    LastStatusTick := A_TickCount
    LogLine(message, level)
    if QuickMenuVisible {
        try QuickMenuRefresh()
        ; Re-render once the message expires so it clears itself instead of
        ; sitting there until the next time the menu happens to redraw.
        SetTimer(QuickMenuRefresh, -(StatusVisibleMs + 100))
    }
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
    global DisplayPendingOldMode, DisplayPendingOldScale
    SetTimer(PollController, 0)
    SetTimer(MouseWatch, 0)
    SetTimer(ObserveForeground, 0)
    SetTimer(ControllerDiagnosticTick, 0)
    SetTimer(AssistTick, 0)
    CloseStartupSplash(true)
    ShutdownGameInput()
    ShutdownRtssHooksApi()
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

SendChordSafe(keys) {
    global CompanionDisabled
    if CompanionDisabled
        return false
    try SendInput("{Ctrl up}{Alt up}{Shift up}{LWin up}{RWin up}")
    try SendInput(keys)
    return true
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

; Takes the foreground for one of our own windows.
;
; Windows only permits the process that already owns the foreground to call
; SetForegroundWindow. A background companion therefore shows its window --
; visible, because it is always-on-top -- while the previous application quietly
; keeps focus, and keeps receiving controller input. Attaching to the current
; foreground thread's input queue lifts that restriction for the duration of the
; call.
;
; This is only ever used on windows this process owns, in direct response to the
; user opening them. It is not focus management of other applications, which
; remains Xbox FSE's job.
ForceForegroundWindow(hwnd) {
    if !hwnd
        return false
    try {
        if (DllCall("GetForegroundWindow", "Ptr") = hwnd)
            return true
        currentForeground := DllCall("GetForegroundWindow", "Ptr")
        ourThread := DllCall("GetCurrentThreadId", "UInt")
        foreThread := currentForeground
            ? DllCall("GetWindowThreadProcessId", "Ptr", currentForeground, "Ptr", 0, "UInt")
            : 0
        attached := false
        if (foreThread && foreThread != ourThread)
            attached := DllCall("AttachThreadInput", "UInt", ourThread,
                "UInt", foreThread, "Int", 1) != 0
        DllCall("BringWindowToTop", "Ptr", hwnd)
        DllCall("SetForegroundWindow", "Ptr", hwnd)
        if attached
            DllCall("AttachThreadInput", "UInt", ourThread, "UInt", foreThread, "Int", 0)
        return DllCall("GetForegroundWindow", "Ptr") = hwnd
    }
    return false
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
    monitorIndex := Max(1, Min(MonitorGetCount(), monitorIndex))
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    return PositionGuiCentered(guiObj, left, top, right, bottom, width, height,
        noActivate, deferShow)
}

; Hidden GUI measurements can omit the scaled non-client frame and title bar.
; Once a window is visible, measure its real outer rectangle and correct the
; position from that rather than the earlier estimate.
RecenterVisibleGuiOnMonitorActual(guiObj, monitorIndex) {
    monitorIndex := Max(1, Min(MonitorGetCount(), monitorIndex))
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

; Moves, and optionally resizes, a window in PHYSICAL pixels.
;
; Gui.Show scales the coordinates and sizes it is handed by the DPI factor. That
; is correct for a layout written in logical units and wrong for a position
; computed from WinGetPos, which reports real device pixels. SetWindowPos takes
; device pixels and scales nothing, so the two units never have to be reconciled.
;
; It also moves and resizes in ONE operation, so there is no frame in which the
; window already has its new size at its old position.
MoveWindowPhysical(hwnd, x, y, w := 0, h := 0) {
    static SWP_NOSIZE := 0x0001
    static SWP_NOZORDER := 0x0004
    static SWP_NOACTIVATE := 0x0010
    flags := SWP_NOZORDER | SWP_NOACTIVATE
    if (w <= 0 || h <= 0)
        flags |= SWP_NOSIZE
    result := 0
    try result := DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0,
        "Int", x, "Int", y, "Int", w, "Int", h, "UInt", flags, "Int")
    return result != 0
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

; Centres a window of the given physical size inside a work area, clamping only
; when it genuinely does not fit so that a window which fits keeps its centred
; position untouched.
CenteredPosition(left, top, right, bottom, windowWidth, windowHeight, &x, &y) {
    x := left + Floor(((right - left) - windowWidth) / 2)
    y := top + Floor(((bottom - top) - windowHeight) / 2)
    if (windowWidth < right - left)
        x := Max(left, Min(x, right - windowWidth))
    else
        x := left
    if (windowHeight < bottom - top)
        y := Max(top, Min(y, bottom - windowHeight))
    else
        y := top
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

; ==============================================================================
; Cursor hiding and sleep-safe parking
; ==============================================================================
SystemCursor(mode := "Show") {
    static AndM := Buffer(128, 0xFF)
    static XorM := Buffer(128, 0)
    static Cursors := [32512,32513,32514,32515,32516,32640,32641,32642,
        32643,32644,32645,32646,32648,32649,32650,32651]
    if (mode = "Hide") {
        for _, id in Cursors {
            hCur := DllCall("CreateCursor", "Ptr", 0, "Int", 0, "Int", 0,
                "Int", 32, "Int", 32, "Ptr", AndM, "Ptr", XorM, "Ptr")
            DllCall("SetSystemCursor", "Ptr", hCur, "Int", id)
        }
    } else {
        DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
    }
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
; XInput and controller mappings
; ==============================================================================
InitXInput() {
    global XInputDll
    if (XInputDll != "")
        return true
    for _, dll in ["xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"] {
        try {
            if (DllCall("GetModuleHandle", "Str", dll, "Ptr")
                || DllCall("LoadLibrary", "Str", dll, "Ptr")) {
                XInputDll := dll
                return true
            }
        }
    }
    XInputDll := ""
    return false
}

XInputGetState(index, &state) {
    global XInputDll
    if (XInputDll = "" && !InitXInput())
        return 1167
    if !IsObject(state)
        state := Buffer(16, 0)
    try {
        rc := DllCall(XInputDll "\XInputGetState", "UInt", index, "Ptr", state, "UInt")
        if (rc = 0) {
            try {
                extended := Buffer(16, 0)
                if (DllCall(XInputDll "\100", "UInt", index, "Ptr", extended, "UInt") = 0) {
                    exButtons := NumGet(extended, 4, "UShort")
                    if (exButtons & 0x0400) {
                        buttons := NumGet(state, 4, "UShort")
                        NumPut("UShort", buttons | 0x0400, state, 4)
                    }
                }
            }
        }
        return rc
    } catch {
        XInputDll := ""
        return 1
    }
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
    try {
        DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", RIDI_DEVICENAME,
            "Ptr", 0, "UInt*", &size)
        if size {
            buffer := Buffer(size * 2 + 2, 0)
            if (DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", RIDI_DEVICENAME,
                "Ptr", buffer, "UInt*", &size, "UInt") != 0xFFFFFFFF)
                name := StrGet(buffer, "UTF-16")
        }
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

RawInputDeviceName(hDevice) {
    static RIDI_DEVICENAME := 0x20000007
    name := ""
    size := 0
    try {
        DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", RIDI_DEVICENAME,
            "Ptr", 0, "UInt*", &size)
        if size {
            buffer := Buffer(size * 2 + 2, 0)
            if (DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", RIDI_DEVICENAME,
                "Ptr", buffer, "UInt*", &size, "UInt") != 0xFFFFFFFF)
                name := StrGet(buffer, "UTF-16")
        }
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
            value := Max(-32767, Min(32767, scaled * axis["direction"]))
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

HasLongBinding(buttonName) {
    global ControllerMap
    value := ""
    try value := ControllerMap[buttonName ".Long"]
    return value != "" && value != "Builtin:None"
}

GetBindingValue(key) {
    global ControllerMap
    value := ""
    try value := ControllerMap[key]
    return value
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

; Formats a Send string for display.
;
; The modifier prefix is consumed character by character rather than by
; substitution. Replacing "^" with "Ctrl+" first inserts a "+" that a later
; "+" -> "Shift+" pass then rewrites, which is how "^1" was being displayed as
; "CtrlShift+1".
SendToPretty(shortcut) {
    static MODIFIERS := Map("#", "Win+", "^", "Ctrl+", "!", "Alt+", "+", "Shift+")
    text := Trim(shortcut)
    prefix := ""
    while (text != "" && MODIFIERS.Has(SubStr(text, 1, 1))) {
        prefix .= MODIFIERS[SubStr(text, 1, 1)]
        text := SubStr(text, 2)
    }
    ; Key names arrive braced, e.g. {Tab}; the braces are noise on screen.
    text := StrReplace(StrReplace(text, "{", ""), "}", "")
    return prefix text
}

ControllerBindingPretty(key) {
    global ControllerMapDisplay
    value := GetBindingValue(key)
    if (value = "")
        return "None"
    if (SubStr(value, 1, 5) = "Send:") {
        try return ControllerMapDisplay[key]
        return SendToPretty(SubStr(value, 6))
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

; ==============================================================================
; Touch keyboard
; ==============================================================================
TryInvokeTouchKeyboard() {
    static clsidText := "{4CE576FA-83DC-4F88-951C-9D0782B4E376}"
    static iidText := "{37C994E7-432B-4834-A2F7-DCE1F13B834B}"
    clsid := Buffer(16, 0)
    iid := Buffer(16, 0)
    tip := 0
    if (DllCall("Ole32\CLSIDFromString", "WStr", clsidText, "Ptr", clsid.Ptr, "Int") != 0
        || DllCall("Ole32\CLSIDFromString", "WStr", iidText, "Ptr", iid.Ptr, "Int") != 0)
        return false
    hr := DllCall("Ole32\CoCreateInstance", "Ptr", clsid.Ptr, "Ptr", 0,
        "UInt", 0x5, "Ptr", iid.Ptr, "Ptr*", &tip, "Int")
    if (hr < 0 || !tip)
        return false
    succeeded := false
    try {
        vtable := NumGet(tip, 0, "Ptr")
        method := NumGet(vtable, 3 * A_PtrSize, "Ptr")
        desktop := DllCall("User32\GetDesktopWindow", "Ptr")
        succeeded := DllCall(method, "Ptr", tip, "Ptr", desktop, "Int") >= 0
    } finally {
        try {
            vtable := NumGet(tip, 0, "Ptr")
            release := NumGet(vtable, 2 * A_PtrSize, "Ptr")
            DllCall(release, "Ptr", tip, "UInt")
        }
    }
    return succeeded
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

OpenOSK() {
    try Run("osk.exe")
}

; ==============================================================================
; Audio, display, HDR, and RTSS
; ==============================================================================
GetActiveAudioOutputDevices() {
    devices := []
    iidDevice := "{D666063F-1587-4E43-81F1-B948E807363F}"
    Loop 32 {
        index := A_Index
        try name := SoundGetName(, index)
        catch
            break
        if (name = "")
            continue
        try {
            device := SoundGetInterface(iidDevice, , index)
            idPtr := 0
            ComCall(5, device, "Ptr*", &idPtr)
            id := idPtr ? StrGet(idPtr, "UTF-16") : ""
            if idPtr
                DllCall("Ole32\CoTaskMemFree", "Ptr", idPtr)
            if (id != "")
                devices.Push(Map("name", name, "id", id))
        }
    }
    return devices
}

SetDefaultAudioEndpointId(endpointId) {
    if (endpointId = "")
        return false
    policy := 0
    try policy := ComObject(
        "{870AF99C-171D-4F9E-AF0D-E63DF40C2BC9}",
        "{F8679F50-850A-41CF-9C72-430F290290C8}")
    catch {
        try policy := ComObject(
            "{294935CE-F637-4E7C-A41B-AB255460B862}",
            "{568B9108-44BF-40B4-9006-86AFE5B5A620}")
    }
    if !IsObject(policy)
        return false
    try {
        ComCall(13, policy, "WStr", endpointId, "Int", 0)
        ComCall(13, policy, "WStr", endpointId, "Int", 1)
        ComCall(13, policy, "WStr", endpointId, "Int", 2)
        return true
    } catch {
        return false
    }
}

CycleDefaultAudioOutput(direction) {
    global QuickMenuAudioDevices
    QuickMenuAudioDevices := GetActiveAudioOutputDevices()
    if (QuickMenuAudioDevices.Length = 0) {
        SetStatus("No active audio outputs were found", "Warning")
        return
    }
    currentName := ""
    try currentName := SoundGetName()
    currentIndex := 1
    for index, device in QuickMenuAudioDevices {
        if (device["name"] = currentName) {
            currentIndex := index
            break
        }
    }
    nextIndex := currentIndex + direction
    if (nextIndex < 1)
        nextIndex := QuickMenuAudioDevices.Length
    if (nextIndex > QuickMenuAudioDevices.Length)
        nextIndex := 1
    target := QuickMenuAudioDevices[nextIndex]
    if SetDefaultAudioEndpointId(target["id"])
        SetStatus("Audio output: " target["name"])
    else
        SetStatus("Windows could not switch the audio output", "Warning")
}

GetPrimaryDisplayMode() {
    dm := Buffer(220, 0)
    NumPut("UShort", 220, dm, 68)
    try {
        if !DllCall("User32\EnumDisplaySettingsW", "Ptr", 0, "Int", -1, "Ptr", dm, "Int")
            return 0
    } catch {
        return 0
    }
    return Map(
        "width", NumGet(dm, 172, "UInt"),
        "height", NumGet(dm, 176, "UInt"),
        "frequency", NumGet(dm, 184, "UInt")
    )
}

GetPrimaryDisplayModes() {
    modes := []
    seen := Map()
    modeIndex := 0
    Loop 512 {
        dm := Buffer(220, 0)
        NumPut("UShort", 220, dm, 68)
        ok := false
        try ok := DllCall("User32\EnumDisplaySettingsW", "Ptr", 0,
            "UInt", modeIndex, "Ptr", dm, "Int")
        if !ok
            break
        modeIndex += 1
        width := NumGet(dm, 172, "UInt")
        height := NumGet(dm, 176, "UInt")
        frequency := NumGet(dm, 184, "UInt")
        bpp := NumGet(dm, 168, "UInt")
        if (width < 640 || height < 480 || frequency < 24 || bpp < 24)
            continue
        key := width "x" height "@" frequency
        if seen.Has(key)
            continue
        seen[key] := true
        modes.Push(Map("width", width, "height", height, "frequency", frequency))
    }
    sorted := []
    for _, mode in modes {
        insertAt := sorted.Length + 1
        for pos, existing in sorted {
            lhs := mode["width"] * mode["height"]
            rhs := existing["width"] * existing["height"]
            if (lhs < rhs || (lhs = rhs && mode["frequency"] < existing["frequency"])) {
                insertAt := pos
                break
            }
        }
        sorted.InsertAt(insertAt, mode)
    }
    return sorted
}

ApplyPrimaryDisplayMode(mode) {
    if !IsObject(mode)
        return false
    dm := Buffer(220, 0)
    NumPut("UShort", 220, dm, 68)
    NumPut("UInt", 0x580000, dm, 72)
    NumPut("UInt", mode["width"], dm, 172)
    NumPut("UInt", mode["height"], dm, 176)
    NumPut("UInt", mode["frequency"], dm, 184)
    try {
        result := DllCall("User32\ChangeDisplaySettingsExW", "Ptr", 0,
            "Ptr", dm, "Ptr", 0, "UInt", 0, "Ptr", 0, "Int")
        return result = 0
    } catch {
        return false
    }
}

; Returns the GDI name Windows assigns to the primary display (normally
; \\.\DISPLAY1). Resolution already targets this display by passing NULL to
; EnumDisplaySettings; the scale path resolves the same display explicitly.
GetPrimaryDisplayDeviceName() {
    Loop 16 {
        device := Buffer(840, 0)
        NumPut("UInt", 840, device, 0)
        ok := false
        try ok := DllCall("User32\EnumDisplayDevicesW", "Ptr", 0,
            "UInt", A_Index - 1, "Ptr", device, "UInt", 0, "Int")
        if !ok
            break
        stateFlags := NumGet(device, 324, "UInt")
        if (stateFlags & 0x4)
            return StrGet(device.Ptr + 4, 32, "UTF-16")
    }
    return ""
}

; Resolves the primary GDI display to its active DisplayConfig source. The
; source adapter LUID and id are required by the per-display scale packets.
GetPrimaryDisplayConfigSource() {
    primaryName := GetPrimaryDisplayDeviceName()
    if (primaryName = "")
        return 0
    flags := 0x2 ; QDC_ONLY_ACTIVE_PATHS
    Loop 3 {
        pathCount := 0
        modeCount := 0
        result := -1
        try result := DllCall("User32\GetDisplayConfigBufferSizes",
            "UInt", flags, "UInt*", &pathCount, "UInt*", &modeCount, "Int")
        if (result != 0 || pathCount < 1)
            return 0
        ; DISPLAYCONFIG_PATH_INFO is 72 bytes and DISPLAYCONFIG_MODE_INFO is 64
        ; bytes in this required 64-bit build.
        paths := Buffer(pathCount * 72, 0)
        modes := Buffer(Max(1, modeCount) * 64, 0)
        try result := DllCall("User32\QueryDisplayConfig",
            "UInt", flags, "UInt*", &pathCount, "Ptr", paths,
            "UInt*", &modeCount, "Ptr", modes, "Ptr", 0, "Int")
        if (result = 122) ; ERROR_INSUFFICIENT_BUFFER: topology changed; retry.
            continue
        if (result != 0)
            return 0
        Loop pathCount {
            pathOffset := (A_Index - 1) * 72
            adapterLow := NumGet(paths, pathOffset, "UInt")
            adapterHigh := NumGet(paths, pathOffset + 4, "Int")
            sourceId := NumGet(paths, pathOffset + 8, "UInt")
            ; DISPLAYCONFIG_SOURCE_DEVICE_NAME: 20-byte header + WCHAR[32].
            sourceName := Buffer(84, 0)
            NumPut("UInt", 1, sourceName, 0) ; GET_SOURCE_NAME
            NumPut("UInt", 84, sourceName, 4)
            NumPut("UInt", adapterLow, sourceName, 8)
            NumPut("Int", adapterHigh, sourceName, 12)
            NumPut("UInt", sourceId, sourceName, 16)
            getResult := -1
            try getResult := DllCall("User32\DisplayConfigGetDeviceInfo",
                "Ptr", sourceName, "Int")
            if (getResult != 0)
                continue
            gdiName := StrGet(sourceName.Ptr + 20, 32, "UTF-16")
            if (StrLower(gdiName) = StrLower(primaryName)) {
                return Map(
                    "adapterLow", adapterLow,
                    "adapterHigh", adapterHigh,
                    "sourceId", sourceId,
                    "targetAdapterLow", NumGet(paths, pathOffset + 20, "UInt"),
                    "targetAdapterHigh", NumGet(paths, pathOffset + 24, "Int"),
                    "targetId", NumGet(paths, pathOffset + 28, "UInt"),
                    "name", gdiName
                )
            }
        }
        return 0
    }
    return 0
}

DisplayScaleLevels() {
    ; Windows' fixed scale ladder. The source DPI packet reports min/current/max
    ; as positions relative to the recommended step; min therefore anchors the
    ; first supported entry in this list.
    return [100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500]
}

; Reads the scale range used by Windows Settings for the primary display.
;
; The CCD header and DisplayConfig calls are public, but Windows does not publish
; the GET_DPI_SCALE (-3) and SET_DPI_SCALE (-4) packet definitions in the SDK.
; They are used defensively here: any unsupported/error response simply removes
; the Scale row and leaves resolution/refresh controls working as before.
GetPrimaryDisplayScale() {
    static warned := false
    source := GetPrimaryDisplayConfigSource()
    if !IsObject(source) {
        if !warned {
            warned := true
            LogLine("Display scale: primary DisplayConfig source is unavailable.",
                "Warning")
        }
        return 0
    }
    packet := Buffer(32, 0)
    NumPut("UInt", 0xFFFFFFFD, packet, 0) ; DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE
    NumPut("UInt", 32, packet, 4)
    NumPut("UInt", source["adapterLow"], packet, 8)
    NumPut("Int", source["adapterHigh"], packet, 12)
    NumPut("UInt", source["sourceId"], packet, 16)
    result := -1
    try result := DllCall("User32\DisplayConfigGetDeviceInfo",
        "Ptr", packet, "Int")
    if (result != 0) {
        if !warned {
            warned := true
            LogLine("Display scale: Windows rejected GET_DPI_SCALE (error "
                . result ").", "Warning")
        }
        return 0
    }
    minimum := NumGet(packet, 20, "Int")
    current := NumGet(packet, 24, "Int")
    maximum := NumGet(packet, 28, "Int")
    levels := DisplayScaleLevels()
    count := maximum - minimum + 1
    currentIndex := current - minimum + 1
    if (count < 1 || count > levels.Length
        || currentIndex < 1 || currentIndex > count) {
        if !warned {
            warned := true
            LogLine("Display scale: Windows returned an unsupported range "
                . minimum ".." maximum " with current " current ".", "Warning")
        }
        return 0
    }
    warned := false
    options := []
    Loop count
        options.Push(levels[A_Index])
    return Map(
        "percent", options[currentIndex],
        "options", options,
        "minimum", minimum,
        "current", current,
        "maximum", maximum
    )
}

ApplyPrimaryDisplayScale(percent) {
    info := GetPrimaryDisplayScale()
    if !IsObject(info)
        return false
    selectedIndex := 0
    for index, option in info["options"] {
        if (option = percent) {
            selectedIndex := index
            break
        }
    }
    if !selectedIndex
        return false
    source := GetPrimaryDisplayConfigSource()
    if !IsObject(source)
        return false
    packet := Buffer(24, 0)
    NumPut("UInt", 0xFFFFFFFC, packet, 0) ; DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE
    NumPut("UInt", 24, packet, 4)
    NumPut("UInt", source["adapterLow"], packet, 8)
    NumPut("Int", source["adapterHigh"], packet, 12)
    NumPut("UInt", source["sourceId"], packet, 16)
    NumPut("Int", info["minimum"] + selectedIndex - 1, packet, 20)
    result := -1
    try result := DllCall("User32\DisplayConfigSetDeviceInfo",
        "Ptr", packet, "Int")
    if (result = 0)
        LogLine("Display scale: primary display set to " percent "%.")
    else
        LogLine("Display scale: SET_DPI_SCALE failed with error " result ".",
            "Warning")
    return result = 0
}

; Reads the primary target's documented Advanced Color state. On Windows 10/11,
; advancedColorSupported identifies an HDR-capable path and
; advancedColorEnabled is the live "Use HDR" state.
GetPrimaryHdrState() {
    static warned := false
    path := GetPrimaryDisplayConfigSource()
    if !IsObject(path)
        return 0
    ; DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO:
    ; 20-byte header, 4-byte flags, color encoding, bits per color channel.
    packet := Buffer(32, 0)
    NumPut("UInt", 9, packet, 0) ; GET_ADVANCED_COLOR_INFO
    NumPut("UInt", 32, packet, 4)
    NumPut("UInt", path["targetAdapterLow"], packet, 8)
    NumPut("Int", path["targetAdapterHigh"], packet, 12)
    NumPut("UInt", path["targetId"], packet, 16)
    result := -1
    try result := DllCall("User32\DisplayConfigGetDeviceInfo",
        "Ptr", packet, "Int")
    if (result != 0) {
        if !warned {
            warned := true
            LogLine("HDR: GET_ADVANCED_COLOR_INFO failed with error "
                . result ".", "Warning")
        }
        return 0
    }
    warned := false
    flags := NumGet(packet, 20, "UInt")
    return Map(
        "supported", (flags & 0x1) != 0,
        "enabled", (flags & 0x2) != 0,
        "wideColorEnforced", (flags & 0x4) != 0,
        "forceDisabled", (flags & 0x8) != 0
    )
}

ApplyPrimaryHdrState(enabled) {
    path := GetPrimaryDisplayConfigSource()
    if !IsObject(path)
        return false
    ; DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE:
    ; 20-byte header followed by the enableAdvancedColor bit.
    packet := Buffer(24, 0)
    NumPut("UInt", 10, packet, 0) ; SET_ADVANCED_COLOR_STATE
    NumPut("UInt", 24, packet, 4)
    NumPut("UInt", path["targetAdapterLow"], packet, 8)
    NumPut("Int", path["targetAdapterHigh"], packet, 12)
    NumPut("UInt", path["targetId"], packet, 16)
    NumPut("UInt", enabled ? 1 : 0, packet, 20)
    result := -1
    try result := DllCall("User32\DisplayConfigSetDeviceInfo",
        "Ptr", packet, "Int")
    if (result = 0)
        LogLine("HDR: primary display turned " (enabled ? "on." : "off."))
    else
        LogLine("HDR: SET_ADVANCED_COLOR_STATE failed with error "
            . result ".", "Warning")
    return result = 0
}

SetQuickMenuHdrState(enabled) {
    current := GetPrimaryHdrState()
    if !IsObject(current) {
        SetStatus("Windows HDR state is unavailable", "Warning")
        return
    }
    if !current["supported"] {
        SetStatus("The primary display does not report HDR support", "Warning")
        return
    }
    if current["forceDisabled"] {
        SetStatus("HDR is disabled by Windows or the display driver", "Warning")
        return
    }
    if (current["enabled"] = enabled) {
        SetStatus("HDR is already " (enabled ? "on" : "off"))
        return
    }
    if ApplyPrimaryHdrState(enabled) {
        SetStatus("HDR turned " (enabled ? "on" : "off"))
        ; The display can blank briefly and Windows updates the reported state
        ; asynchronously. Reuse the display reflow timer to refresh the row from
        ; the authoritative state after that transition.
        QueueQuickMenuDisplayReflow()
    } else {
        SetStatus("Windows could not turn HDR " (enabled ? "on" : "off"),
            "Warning")
    }
}

ToggleQuickMenuHdrState() {
    current := GetPrimaryHdrState()
    if !IsObject(current) {
        SetStatus("Windows HDR state is unavailable", "Warning")
        return
    }
    SetQuickMenuHdrState(!current["enabled"])
}

; ==============================================================================
; Display selection (resolution, refresh rate, and scale chosen independently)
; ==============================================================================
; Nothing here changes the display. The chosen values are only applied when the
; Apply row is activated, so cycling through options is free and the existing
; 15-second revert guards the single transaction.
DistinctDisplayResolutions() {
    global QuickMenuDisplayModes
    seen := Map()
    list := []
    for _, mode in QuickMenuDisplayModes {
        key := mode["width"] "x" mode["height"]
        if seen.Has(key)
            continue
        seen[key] := true
        list.Push(Map("width", mode["width"], "height", mode["height"]))
    }
    return list
}

FrequenciesForResolution(width, height) {
    global QuickMenuDisplayModes
    list := []
    for _, mode in QuickMenuDisplayModes {
        if (mode["width"] = width && mode["height"] = height)
            list.Push(mode["frequency"])
    }
    return list
}

; Seeds the pending selection from the mode currently in use, and keeps the
; refresh rate valid whenever the resolution changes.
EnsureDisplaySelection() {
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    if (!DisplaySelectedWidth || !DisplaySelectedHeight) {
        current := GetPrimaryDisplayMode()
        if IsObject(current) {
            DisplaySelectedWidth := current["width"]
            DisplaySelectedHeight := current["height"]
            DisplaySelectedFrequency := current["frequency"]
        } else {
            resolutions := DistinctDisplayResolutions()
            if (resolutions.Length = 0)
                return
            DisplaySelectedWidth := resolutions[1]["width"]
            DisplaySelectedHeight := resolutions[1]["height"]
            DisplaySelectedFrequency := 0
        }
    }
    frequencies := FrequenciesForResolution(DisplaySelectedWidth, DisplaySelectedHeight)
    if (frequencies.Length = 0)
        return
    for _, frequency in frequencies {
        if (frequency = DisplaySelectedFrequency)
            return
    }
    ; The chosen rate is not offered at this resolution; fall back to the
    ; highest one that is.
    best := frequencies[1]
    for _, frequency in frequencies
        if (frequency > best)
            best := frequency
    DisplaySelectedFrequency := best
}

CycleDisplayResolution(direction) {
    global DisplaySelectedWidth, DisplaySelectedHeight
    resolutions := DistinctDisplayResolutions()
    if (resolutions.Length = 0)
        return
    index := 1
    for position, item in resolutions {
        if (item["width"] = DisplaySelectedWidth
            && item["height"] = DisplaySelectedHeight) {
            index := position
            break
        }
    }
    index += direction
    if (index < 1)
        index := resolutions.Length
    if (index > resolutions.Length)
        index := 1
    DisplaySelectedWidth := resolutions[index]["width"]
    DisplaySelectedHeight := resolutions[index]["height"]
    EnsureDisplaySelection()
}

CycleDisplayFrequency(direction) {
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    frequencies := FrequenciesForResolution(DisplaySelectedWidth, DisplaySelectedHeight)
    if (frequencies.Length = 0)
        return
    index := 1
    for position, frequency in frequencies {
        if (frequency = DisplaySelectedFrequency) {
            index := position
            break
        }
    }
    index += direction
    if (index < 1)
        index := frequencies.Length
    if (index > frequencies.Length)
        index := 1
    DisplaySelectedFrequency := frequencies[index]
}

EnsureDisplayScaleSelection() {
    global DisplaySelectedScalePercent
    info := GetPrimaryDisplayScale()
    if !IsObject(info) {
        DisplaySelectedScalePercent := 0
        return 0
    }
    if DisplaySelectedScalePercent {
        for _, option in info["options"] {
            if (option = DisplaySelectedScalePercent)
                return info
        }
    }
    DisplaySelectedScalePercent := info["percent"]
    return info
}

CycleDisplayScale(direction) {
    global DisplaySelectedScalePercent
    info := EnsureDisplayScaleSelection()
    if !IsObject(info)
        return
    options := info["options"]
    index := 1
    for position, option in options {
        if (option = DisplaySelectedScalePercent) {
            index := position
            break
        }
    }
    index += direction
    if (index < 1)
        index := options.Length
    if (index > options.Length)
        index := 1
    DisplaySelectedScalePercent := options[index]
}

; Windows applies a new DPI asynchronously. Refreshing the row text in the same
; thread is too early: the Quick Menu is still measured and centred in the old
; coordinate space, so it lands off-centre until a page change runs the full
; layout pass. Queue that same pass after the display has settled, while keeping
; the current page and selection (especially the Apply row needed to confirm).
QueueQuickMenuDisplayReflow() {
    SetTimer(QuickMenuDisplayReflow, -350)
}

QuickMenuDisplayReflow() {
    global QuickMenuVisible
    if QuickMenuVisible
        QuickMenuBuildGui()
}

GetDisplayApplyValue() {
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    global DisplaySelectedScalePercent
    global DisplayPendingOldMode, DisplayPendingUntilTick
    ; During the revert window this row is the only instruction the user has, so
    ; it counts down rather than just saying something is pending.
    if IsObject(DisplayPendingOldMode) {
        remaining := Max(0, Ceil((DisplayPendingUntilTick - A_TickCount) / 1000))
        return "Select to KEEP (" remaining "s)"
    }
    current := GetPrimaryDisplayMode()
    scale := GetPrimaryDisplayScale()
    scaleSame := !DisplaySelectedScalePercent
        || (IsObject(scale) && scale["percent"] = DisplaySelectedScalePercent)
    if (IsObject(current) && scaleSame
        && current["width"] = DisplaySelectedWidth
        && current["height"] = DisplaySelectedHeight
        && current["frequency"] = DisplaySelectedFrequency)
        return "CURRENT"
    return "Select to apply"
}

; Applies the pending selection, reusing the existing timed-revert protection.
ApplyDisplaySelection() {
    global QuickMenuDisplayModes
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    global DisplaySelectedScalePercent
    global DisplayPendingOldMode, DisplayPendingOldScale, DisplayPendingUntilTick
    candidate := 0
    for _, mode in QuickMenuDisplayModes {
        if (mode["width"] = DisplaySelectedWidth
            && mode["height"] = DisplaySelectedHeight
            && mode["frequency"] = DisplaySelectedFrequency) {
            candidate := mode
            break
        }
    }
    if !IsObject(candidate) {
        SetStatus("That display mode is no longer offered", "Warning")
        return
    }
    currentMode := GetPrimaryDisplayMode()
    if !IsObject(currentMode) {
        SetStatus("Current display mode is unavailable", "Warning")
        return
    }
    currentScale := GetPrimaryDisplayScale()
    modeSame := candidate["width"] = currentMode["width"]
        && candidate["height"] = currentMode["height"]
        && candidate["frequency"] = currentMode["frequency"]
    scaleSame := !DisplaySelectedScalePercent
        || (IsObject(currentScale)
            && currentScale["percent"] = DisplaySelectedScalePercent)

    if IsObject(DisplayPendingOldMode) {
        if (modeSame && scaleSame)
            ConfirmPrimaryDisplayMode()
        else
            SetStatus("Keep or revert the pending display change first", "Warning")
        return
    }
    if (modeSame && scaleSame)
        return
    if (DisplaySelectedScalePercent && !IsObject(currentScale)) {
        SetStatus("Windows display scaling is unavailable", "Warning")
        return
    }

    modeChanged := false
    if !modeSame {
        if !ApplyPrimaryDisplayMode(candidate) {
            SetStatus("Windows rejected that display mode", "Warning")
            return
        }
        modeChanged := true
    }
    if !scaleSame && !ApplyPrimaryDisplayScale(DisplaySelectedScalePercent) {
        modeRestored := !modeChanged || ApplyPrimaryDisplayMode(currentMode)
        scaleRestored := !IsObject(currentScale)
            || ApplyPrimaryDisplayScale(currentScale["percent"])
        QueueQuickMenuDisplayReflow()
        SetStatus(modeRestored && scaleRestored
            ? "Windows rejected that display scale; the old settings were restored"
            : "Windows rejected that display scale; not all old settings restored",
            "Warning")
        return
    }
    DisplayPendingOldMode := currentMode
    DisplayPendingOldScale := currentScale
    DisplayPendingUntilTick := A_TickCount + 15000
    SetTimer(DisplayChangeSafetyTick, 500)
    QueueQuickMenuDisplayReflow()
    SetStatus("Display changed. Select CURRENT again within 15 seconds to keep it.",
        "Warning")
}

ConfirmPrimaryDisplayMode() {
    global DisplayPendingOldMode, DisplayPendingOldScale, DisplayPendingUntilTick
    if !IsObject(DisplayPendingOldMode)
        return
    DisplayPendingOldMode := 0
    DisplayPendingOldScale := 0
    DisplayPendingUntilTick := 0
    SetTimer(DisplayChangeSafetyTick, 0)
    SetStatus("Display settings kept")
}

DisplayChangeSafetyTick() {
    global DisplayPendingOldMode, DisplayPendingOldScale
    global DisplayPendingUntilTick, QuickMenuVisible
    if !IsObject(DisplayPendingOldMode) {
        SetTimer(DisplayChangeSafetyTick, 0)
        return
    }
    if (A_TickCount >= DisplayPendingUntilTick) {
        oldMode := DisplayPendingOldMode
        oldScale := DisplayPendingOldScale
        DisplayPendingOldMode := 0
        DisplayPendingOldScale := 0
        DisplayPendingUntilTick := 0
        SetTimer(DisplayChangeSafetyTick, 0)
        modeRestored := ApplyPrimaryDisplayMode(oldMode)
        scaleRestored := !IsObject(oldScale)
            || ApplyPrimaryDisplayScale(oldScale["percent"])
        QueueQuickMenuDisplayReflow()
        if (modeRestored && scaleRestored)
            SetStatus("Display settings reverted for safety", "Warning")
        else
            SetStatus("Unable to restore all previous display settings", "Warning")
    }
    if QuickMenuVisible
        QuickMenuRefresh()
}

EnsureRtssRunning() {
    global RtssPath
    if ProcessExist("RTSS.exe")
        return true
    path := NormalizePath(RtssPath)
    if (path = "" || !FileExist(path))
        return false
    try {
        Run('"' path '"', , "Min")
        return ProcessWait("RTSS.exe", 3) != 0
    } catch {
        return false
    }
}

StartRtssFromQuickMenu() {
    global EnableRTSSIntegration, RtssPath
    if !EnableRTSSIntegration {
        SetStatus("Enable RTSS integration in Settings first", "Warning")
        return
    }
    if ProcessExist("RTSS.exe") {
        SetStatus("RTSS is already running")
        SetTimer(RefreshQuickMenuAfterRtssStart, -100)
        return
    }
    if !FileExist(NormalizePath(RtssPath)) {
        SetStatus("RTSS was not found at the configured path", "Warning")
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
        SetStatus("RTSS did not start from the configured path", "Warning")
    }
}

RefreshQuickMenuAfterRtssStart() {
    global QuickMenuVisible, QuickMenuPage
    if (QuickMenuVisible && QuickMenuPage = "RTSS")
        QuickMenuBuildGui()
}

ShutdownRtssHooksApi() {
    global RtssHooksModule, RtssHooksDllPath
    global RtssGetFlagsProc, RtssSetFlagsProc
    global RtssLoadProfileProc, RtssGetProfilePropertyProc
    global RtssSetProfilePropertyProc, RtssSaveProfileProc, RtssUpdateProfilesProc
    if RtssHooksModule
        try DllCall("Kernel32\FreeLibrary", "Ptr", RtssHooksModule, "Int")
    RtssHooksModule := 0
    RtssHooksDllPath := ""
    RtssGetFlagsProc := 0
    RtssSetFlagsProc := 0
    RtssLoadProfileProc := 0
    RtssGetProfilePropertyProc := 0
    RtssSetProfilePropertyProc := 0
    RtssSaveProfileProc := 0
    RtssUpdateProfilesProc := 0
}

; Loads the two global-flag exports published by RTSSHooks64.dll. This companion
; is explicitly 64-bit, so it must use the 64-bit hooks DLL beside RTSS.exe.
; Returning false is deliberately non-fatal: older/unusual RTSS installations
; retain the configured shortcut controls as a compatibility fallback.
GetRtssHooksApi() {
    global RtssPath, RtssHooksModule, RtssHooksDllPath
    global RtssGetFlagsProc, RtssSetFlagsProc, RtssHooksLastFailure
    global RtssLoadProfileProc, RtssGetProfilePropertyProc
    global RtssSetProfilePropertyProc, RtssSaveProfileProc, RtssUpdateProfilesProc
    global RtssUseDllIntegration
    if !RtssUseDllIntegration
        return 0
    rtssExe := NormalizePath(RtssPath)
    installDir := ""
    if (rtssExe != "")
        SplitPath(rtssExe, , &installDir)
    dllPath := installDir != "" ? installDir "\RTSSHooks64.dll" : ""
    if (RtssHooksModule && RtssHooksDllPath = dllPath
        && RtssGetFlagsProc && RtssSetFlagsProc) {
        return Map(
            "get", RtssGetFlagsProc,
            "set", RtssSetFlagsProc,
            "loadProfile", RtssLoadProfileProc,
            "getProfileProperty", RtssGetProfilePropertyProc,
            "setProfileProperty", RtssSetProfilePropertyProc,
            "saveProfile", RtssSaveProfileProc,
            "updateProfiles", RtssUpdateProfilesProc
        )
    }
    if RtssHooksModule
        ShutdownRtssHooksApi()
    if (dllPath = "" || !FileExist(dllPath)) {
        if (RtssHooksLastFailure != dllPath) {
            RtssHooksLastFailure := dllPath
            LogLine("RTSS state: RTSSHooks64.dll was not found beside RTSS.exe; "
                . "shortcut fallback remains available.", "Warning")
        }
        return 0
    }
    module := 0
    getProc := 0
    setProc := 0
    loadProfileProc := 0
    getProfilePropertyProc := 0
    setProfilePropertyProc := 0
    saveProfileProc := 0
    updateProfilesProc := 0
    try module := DllCall("Kernel32\LoadLibraryW", "WStr", dllPath, "Ptr")
    if module {
        try getProc := DllCall("Kernel32\GetProcAddress",
            "Ptr", module, "AStr", "GetFlags", "Ptr")
        try setProc := DllCall("Kernel32\GetProcAddress",
            "Ptr", module, "AStr", "SetFlags", "Ptr")
        try loadProfileProc := DllCall("Kernel32\GetProcAddress",
            "Ptr", module, "AStr", "LoadProfile", "Ptr")
        try getProfilePropertyProc := DllCall("Kernel32\GetProcAddress",
            "Ptr", module, "AStr", "GetProfileProperty", "Ptr")
        ; Write path. Deliberately optional: an RTSS build without these still
        ; drives the overlay and limiter flags, and the frame-cap row degrades
        ; to read-only rather than taking the whole integration down with it.
        try setProfilePropertyProc := DllCall("Kernel32\GetProcAddress",
            "Ptr", module, "AStr", "SetProfileProperty", "Ptr")
        try saveProfileProc := DllCall("Kernel32\GetProcAddress",
            "Ptr", module, "AStr", "SaveProfile", "Ptr")
        try updateProfilesProc := DllCall("Kernel32\GetProcAddress",
            "Ptr", module, "AStr", "UpdateProfiles", "Ptr")
    }
    if (!module || !getProc || !setProc) {
        if module
            try DllCall("Kernel32\FreeLibrary", "Ptr", module, "Int")
        if (RtssHooksLastFailure != dllPath) {
            RtssHooksLastFailure := dllPath
            LogLine("RTSS state: GetFlags/SetFlags exports are unavailable in "
                . dllPath "; shortcut fallback remains available.", "Warning")
        }
        return 0
    }
    RtssHooksModule := module
    RtssHooksDllPath := dllPath
    RtssGetFlagsProc := getProc
    RtssSetFlagsProc := setProc
    RtssLoadProfileProc := loadProfileProc
    RtssGetProfilePropertyProc := getProfilePropertyProc
    RtssSetProfilePropertyProc := setProfilePropertyProc
    RtssSaveProfileProc := saveProfileProc
    RtssUpdateProfilesProc := updateProfilesProc
    RtssHooksLastFailure := ""
    LogLine("RTSS state: connected to RTSSHooks64.dll global flags"
        . (RtssFrameCapWritable() ? " (frame cap writable)." : "; frame cap is read-only."))
    return Map(
        "get", getProc,
        "set", setProc,
        "loadProfile", loadProfileProc,
        "getProfileProperty", getProfilePropertyProc,
        "setProfileProperty", setProfilePropertyProc,
        "saveProfile", saveProfileProc,
        "updateProfiles", updateProfilesProc
    )
}

; These are RTSS-wide switches. Overlay means global OSD visibility; limiter
; means the global disable override is clear. It does not prove that a game's
; profile has OSD support or a non-zero frame cap configured.
GetRtssGlobalState() {
    global EnableRTSSIntegration, RtssUseDllIntegration
    if (!EnableRTSSIntegration || !RtssUseDllIntegration
        || !ProcessExist("RTSS.exe"))
        return 0
    api := GetRtssHooksApi()
    if !IsObject(api)
        return 0
    flags := 0
    try flags := DllCall(api["get"], "UInt")
    catch as err {
        LogLine("RTSS state: GetFlags failed: " err.Message, "Warning")
        return 0
    }
    return Map(
        "overlay", (flags & 0x1) != 0,       ; RTSSHOOKSFLAG_OSD_VISIBLE
        "limiter", (flags & 0x4) = 0,        ; RTSSHOOKSFLAG_LIMITER_DISABLED
        "flags", flags
    )
}

; Reads the cap from the profile applicable to the executable that owned the
; foreground before the Quick Menu opened. RTSS's LoadProfile contract falls
; back to the global profile when that application-specific profile is absent.
; An empty executable explicitly selects the global profile.
GetRtssFrameLimit(profileExe := "") {
    global EnableRTSSIntegration, RtssUseDllIntegration
    if (!EnableRTSSIntegration || !RtssUseDllIntegration
        || !ProcessExist("RTSS.exe"))
        return 0
    api := GetRtssHooksApi()
    if (!IsObject(api) || !api["loadProfile"] || !api["getProfileProperty"])
        return 0
    profileName := Trim(profileExe)
    if (profileName != "") {
        fileName := ""
        SplitPath(profileName, &fileName)
        if (fileName != "")
            profileName := fileName
    }
    value := Buffer(4, 0)
    try {
        DllCall(api["loadProfile"], "AStr", profileName)
        ok := DllCall(api["getProfileProperty"],
            "AStr", "FramerateLimit", "Ptr", value, "UInt", value.Size, "Int")
        if !ok
            return 0
        return Map(
            "fps", NumGet(value, 0, "UInt"),
            "profile", profileName != "" ? profileName : "Global"
        )
    } catch as err {
        LogLine("RTSS state: FramerateLimit query failed: " err.Message,
            "Warning")
        return 0
    }
}

NotifyRtssSettingsChanged() {
    hwnd := 0
    try hwnd := DllCall("User32\FindWindowW", "Ptr", 0, "WStr", "RTSS", "Ptr")
    if !hwnd
        try hwnd := DllCall("User32\FindWindowW", "Ptr", 0,
            "WStr", "RivaTuner Statistics Server", "Ptr")
    if hwnd
        try DllCall("User32\PostMessageW", "Ptr", hwnd,
            "UInt", 0x8064, "UPtr", 0, "Ptr", 0, "Int") ; WM_APP + 100
}

ApplyRtssGlobalState(feature, enabled) {
    if !EnsureRtssRunning() {
        SetStatus("RTSS was not found at the configured path", "Warning")
        return false
    }
    api := GetRtssHooksApi()
    if !IsObject(api)
        return false
    if (feature = "overlay") {
        andMask := 0xFFFFFFFE
        xorMask := enabled ? 0x1 : 0
        label := "overlay"
    } else {
        andMask := 0xFFFFFFFB
        xorMask := enabled ? 0 : 0x4
        label := "frame limiter"
    }
    try {
        DllCall(api["set"], "UInt", andMask, "UInt", xorMask, "UInt")
        NotifyRtssSettingsChanged()
        state := GetRtssGlobalState()
        if (IsObject(state) && state[feature] = enabled) {
            SetStatus("RTSS " label " " (enabled ? "enabled" : "disabled"))
            return true
        }
    } catch as err {
        LogLine("RTSS state: SetFlags failed: " err.Message, "Warning")
    }
    SetStatus("RTSS did not confirm the " label " change", "Warning")
    return false
}

SendRtssShortcut(shortcut, description) {
    global EnableRTSSIntegration
    if !EnableRTSSIntegration {
        SetStatus("Enable RTSS integration in Settings first", "Warning")
        return false
    }
    if (shortcut = "") {
        SetStatus("Configure the RTSS shortcut in Settings first", "Warning")
        return false
    }
    if !EnsureRtssRunning() {
        SetStatus("RTSS was not found at the configured path", "Warning")
        return false
    }
    SendChordSafe(shortcut)
    SetStatus(description)
    return true
}

ToggleRtssOverlay() {
    global RtssOverlayToggleShortcut
    state := GetRtssGlobalState()
    if IsObject(state) {
        ApplyRtssGlobalState("overlay", !state["overlay"])
        return
    }
    SendRtssShortcut(RtssOverlayToggleShortcut, "RTSS overlay toggled")
}

SetRtssOverlayState(enabled) {
    global RtssOverlayOnShortcut, RtssOverlayOffShortcut
    state := GetRtssGlobalState()
    if IsObject(state) {
        if (state["overlay"] = enabled) {
            SetStatus("RTSS overlay is already " (enabled ? "on" : "off"))
            return
        }
        ApplyRtssGlobalState("overlay", enabled)
        return
    }
    shortcut := enabled ? RtssOverlayOnShortcut : RtssOverlayOffShortcut
    SendRtssShortcut(shortcut, enabled ? "RTSS overlay enabled" : "RTSS overlay disabled")
}

ToggleRtssFrameLimiter() {
    global RtssCustomFrameCapShortcut
    state := GetRtssGlobalState()
    if IsObject(state) {
        ApplyRtssGlobalState("limiter", !state["limiter"])
        return
    }
    SendRtssShortcut(RtssCustomFrameCapShortcut, "RTSS frame limiter toggled")
}

SetRtssFrameLimiterState(enabled) {
    global RtssFrameLimiterOnShortcut, RtssFrameLimiterOffShortcut
    state := GetRtssGlobalState()
    if IsObject(state) {
        if (state["limiter"] = enabled) {
            SetStatus("RTSS frame limiter is already " (enabled ? "on" : "off"))
            return
        }
        ApplyRtssGlobalState("limiter", enabled)
        return
    }
    shortcut := enabled ? RtssFrameLimiterOnShortcut : RtssFrameLimiterOffShortcut
    SendRtssShortcut(shortcut,
        enabled ? "RTSS frame limiter enabled" : "RTSS frame limiter disabled")
}

; ==============================================================================
; Steam context actions
; ==============================================================================
; Steam's menu bindings only reach Steam when Steam owns the foreground. While a
; game is in front the equivalent is the in-game overlay, so the same action has
; to send a different shortcut depending on what is actually in front.
;
; The foreground must be sampled BEFORE the Quick Menu appears -- once it is up,
; the companion itself owns the foreground and every window would look like a
; game. ShowQuickMenu records it for that reason.
IsSteamProcess(exe) {
    exe := StrLower(Trim(exe))
    return exe = "steam.exe" || exe = "steamwebhelper.exe"
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

; Steam's in-game overlay hook can miss SendInput's effectively instantaneous
; Shift+Tab pulse even though ordinary desktop applications accept it. SendEvent
; honours SetKeyDelay's press duration, giving Steam a real modifier-down window
; in which to observe the second key. The configured shortcut is still used, so
; this is not hard-coded to Shift+Tab.
SendSteamOverlayChord() {
    global SteamOverlayShortcut, CompanionDisabled
    if CompanionDisabled
        return false
    foregroundHwnd := 0
    foregroundExe := ""
    try foregroundHwnd := WinExist("A")
    if foregroundHwnd
        try foregroundExe := WinGetProcessName("ahk_id " foregroundHwnd)
    LogLine("Steam overlay send: " SendToPretty(SteamOverlayShortcut)
        . ", foreground=" (foregroundExe != "" ? foregroundExe : "unknown")
        . ", hwnd=" foregroundHwnd ".")
    sent := false
    try {
        SendEvent("{Ctrl up}{Alt up}{Shift up}{LWin up}{RWin up}")
        ; Delay between events, then how long each key stays down.
        SetKeyDelay(35, 80)
        SendEvent(SteamOverlayShortcut)
        sent := true
    } catch as err {
        LogLine("Steam overlay send failed: " err.Message, "Warning")
    }
    ; Also runs after a partial failure so a modifier can never remain stuck.
    try SendEvent("{Ctrl up}{Alt up}{Shift up}{LWin up}{RWin up}")
    return sent
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
LogonTaskName() {
    return "SteamShell-XFE"
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

XmlEscape(text) {
    text := StrReplace(text, "&", "&amp;")
    text := StrReplace(text, "<", "&lt;")
    text := StrReplace(text, ">", "&gt;")
    return StrReplace(text, '"', "&quot;")
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
LogonTaskXml() {
    account := XmlEscape(LogonTaskAccount())
    if A_IsCompiled {
        command := XmlEscape(A_ScriptFullPath)
        arguments := ""
    } else {
        command := XmlEscape(A_AhkPath)
        arguments := "<Arguments>" XmlEscape('"' A_ScriptFullPath '"') "</Arguments>`r`n      "
    }
    workingDir := XmlEscape(A_ScriptDir)
    return ""
        . "<?xml version=" Chr(34) "1.0" Chr(34) " encoding=" Chr(34) "UTF-16" Chr(34) "?>`r`n"
        . "<Task version=" Chr(34) "1.2" Chr(34)
            . " xmlns=" Chr(34) "http://schemas.microsoft.com/windows/2004/02/mit/task" Chr(34) ">`r`n"
        . "  <RegistrationInfo>`r`n"
        . "    <Description>Starts the SteamShell XFE controller companion at logon.</Description>`r`n"
        . "  </RegistrationInfo>`r`n"
        . "  <Triggers>`r`n"
        . "    <LogonTrigger>`r`n"
        . "      <Enabled>true</Enabled>`r`n"
        . "      <UserId>" account "</UserId>`r`n"
        . "      <Delay>PT10S</Delay>`r`n"
        . "    </LogonTrigger>`r`n"
        . "  </Triggers>`r`n"
        . "  <Principals>`r`n"
        . "    <Principal id=" Chr(34) "Author" Chr(34) ">`r`n"
        . "      <UserId>" account "</UserId>`r`n"
        . "      <LogonType>InteractiveToken</LogonType>`r`n"
        . "      <RunLevel>LeastPrivilege</RunLevel>`r`n"
        . "    </Principal>`r`n"
        . "  </Principals>`r`n"
        ; Element order matches what Task Scheduler itself emits when exporting a
        ; task. The schema is order-sensitive and rejects the whole file with an
        ; unhelpful "task XML is malformed" if elements are rearranged, so this
        ; sequence is copied from a known-good export rather than chosen.
        . "  <Settings>`r`n"
        . "    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>`r`n"
        ; The two settings this whole XML exists for.
        . "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>`r`n"
        . "    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>`r`n"
        . "    <AllowHardTerminate>false</AllowHardTerminate>`r`n"
        . "    <StartWhenAvailable>false</StartWhenAvailable>`r`n"
        . "    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>`r`n"
        . "    <IdleSettings>`r`n"
        . "      <StopOnIdleEnd>false</StopOnIdleEnd>`r`n"
        . "      <RestartOnIdle>false</RestartOnIdle>`r`n"
        . "    </IdleSettings>`r`n"
        . "    <AllowStartOnDemand>true</AllowStartOnDemand>`r`n"
        . "    <Enabled>true</Enabled>`r`n"
        . "    <Hidden>false</Hidden>`r`n"
        . "    <RunOnlyIfIdle>false</RunOnlyIfIdle>`r`n"
        . "    <WakeToRun>false</WakeToRun>`r`n"
        ; PT0S is "no limit". The default is 72 hours, which would terminate the
        ; companion mid-session on a machine that stays logged in.
        . "    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>`r`n"
        . "    <Priority>7</Priority>`r`n"
        . "  </Settings>`r`n"
        . "  <Actions Context=" Chr(34) "Author" Chr(34) ">`r`n"
        . "    <Exec>`r`n"
        . "      <Command>" command "</Command>`r`n"
        . "      " arguments "<WorkingDirectory>" workingDir "</WorkingDirectory>`r`n"
        . "    </Exec>`r`n"
        . "  </Actions>`r`n"
        . "</Task>`r`n"
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
; Startup splash
; ==============================================================================
ResolveStartupSplashPath(path) {
    path := NormalizePath(path)
    if (path = "")
        return ""
    if !RegExMatch(path, "i)^(?:[A-Z]:\\|\\\\|[a-z][a-z0-9+.-]*://)")
        path := A_ScriptDir "\" path
    return path
}

GetPrimaryMonitorBounds(&left, &top, &right, &bottom) {
    index := 1
    try index := MonitorGetPrimary()
    try {
        MonitorGet(index, &left, &top, &right, &bottom)
        return
    }
    left := 0
    top := 0
    right := A_ScreenWidth
    bottom := A_ScreenHeight
}

StartupSplashSetOpacity(alpha) {
    global StartupSplashGui
    if !IsSet(StartupSplashGui)
        return
    try WinSetTransparent(
        Max(0, Min(255, alpha)), "ahk_id " StartupSplashGui.Hwnd)
}

CreateStartupSplashCover() {
    global StartupSplashGui
    if IsSet(StartupSplashGui) {
        try StartupSplashGui.Destroy()
        StartupSplashGui := unset
    }
    cover := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000000 +E0x20",
        "SteamShell XFE Startup Curtain")
    cover.BackColor := "000000"
    cover.Show("Hide w100 h100")
    GetPrimaryMonitorBounds(&left, &top, &right, &bottom)
    MoveWindowPhysical(cover.Hwnd, left, top, right - left, bottom - top)
    StartupSplashGui := cover
    StartupSplashSetOpacity(255)
    RevealWindow(cover, true)
    try WinSetAlwaysOnTop(1, "ahk_id " cover.Hwnd)
}

DestroyStartupSplashCover() {
    global StartupSplashGui
    if !IsSet(StartupSplashGui)
        return
    try StartupSplashGui.Destroy()
    StartupSplashGui := unset
}

StartStartupSplashVideo() {
    global StartupSplashMpvPath, StartupSplashVideoPath
    global StartupSplashMute, StartupSplashForceSdr
    global StartupSplashMpvPid, StartupSplashMpvHwnd
    mpv := ResolveStartupSplashPath(StartupSplashMpvPath)
    video := ResolveStartupSplashPath(StartupSplashVideoPath)
    if (mpv = "" || !FileExist(mpv)) {
        LogLine("Startup splash: MPV executable was not found"
            . (mpv != "" ? " at " mpv : "")
            . "; using black.", "Warning")
        return false
    }
    if (video = "" || (!InStr(video, "://") && !FileExist(video))) {
        LogLine("Startup splash: video was not found"
            . (video != "" ? " at " video : "")
            . "; using black.", "Warning")
        return false
    }
    args := "--fullscreen --screen=0 --fs-screen=0 --ontop --border=no --no-osc "
        . "--no-input-default-bindings --keep-open=no --really-quiet "
        . "--force-window=immediate"
    if StartupSplashForceSdr {
        args .= " --vo=gpu --gpu-api=d3d11 --d3d11-output-csp=srgb"
        args .= " --target-colorspace-hint=no --target-trc=bt.1886"
        args .= " --target-prim=bt.709 --tone-mapping=clip"
    }
    args .= (StartupSplashMute ? " --mute=yes" : " --mute=no")
    args .= ' "' video '"'
    StartupSplashMpvPid := 0
    StartupSplashMpvHwnd := 0
    try {
        Run('"' mpv '" ' args, , , &StartupSplashMpvPid)
    } catch as err {
        LogLine("Startup splash: MPV failed to start (" err.Message
            . "); using black.", "Warning")
        StartupSplashMpvPid := 0
        return false
    }
    if !StartupSplashMpvPid {
        LogLine("Startup splash: MPV returned no process ID; using black.",
            "Warning")
        return false
    }
    LogLine("Startup splash: video started with MPV.")
    return true
}

ArmStartupSplashClose(videoStarted) {
    global StartupSplashPlayFull, StartupSplashDurationMs
    global StartupSplashSafetyMaxMs
    if (videoStarted && StartupSplashPlayFull)
        SetTimer(CloseStartupSplash, -StartupSplashSafetyMaxMs)
    else
        SetTimer(CloseStartupSplash, -Max(1, StartupSplashDurationMs))
}

StartupSplashKeepOnTop() {
    global StartupSplashGui, StartupSplashMpvPid, StartupSplashMpvHwnd
    global StartupSplashClosing
    if StartupSplashClosing
        return
    if IsSet(StartupSplashGui)
        try WinSetAlwaysOnTop(1, "ahk_id " StartupSplashGui.Hwnd)
    if !StartupSplashMpvPid
        return
    if !ProcessExist(StartupSplashMpvPid) {
        CloseStartupSplash()
        return
    }
    if !StartupSplashMpvHwnd {
        windows := []
        try windows := WinGetList("ahk_pid " StartupSplashMpvPid)
        for _, hwnd in windows {
            visible := false
            try visible := DllCall(
                "IsWindowVisible", "Ptr", hwnd, "Int") != 0
            if !visible
                continue
            StartupSplashMpvHwnd := hwnd
            try WinSetAlwaysOnTop(1, "ahk_id " hwnd)
            ; The black curtain is created before MPV to prevent Xbox FSE or the
            ; desktop flashing through. Remove it only after MPV has a visible
            ; fullscreen window.
            DestroyStartupSplashCover()
            break
        }
    } else {
        try WinSetAlwaysOnTop(1, "ahk_id " StartupSplashMpvHwnd)
    }
}

CloseStartupSplash(immediate := false) {
    global StartupSplashGui, StartupSplashMpvPid, StartupSplashMpvHwnd
    global StartupSplashFadeOutMs, StartupSplashClosing
    if StartupSplashClosing
        return
    if (!StartupSplashMpvPid && !IsSet(StartupSplashGui))
        return
    StartupSplashClosing := true
    SetTimer(StartupSplashKeepOnTop, 0)
    SetTimer(CloseStartupSplash, 0)

    ; Cover the primary display before removing MPV so there is no one-frame
    ; flash of the desktop or Xbox FSE between the video and the fade.
    if StartupSplashMpvPid && !IsSet(StartupSplashGui)
        CreateStartupSplashCover()
    if StartupSplashMpvPid {
        windows := []
        try windows := WinGetList("ahk_pid " StartupSplashMpvPid)
        for _, hwnd in windows
            try PostMessage(0x0010, 0, 0, , "ahk_id " hwnd)
        try ProcessClose(StartupSplashMpvPid)
    }
    StartupSplashMpvPid := 0
    StartupSplashMpvHwnd := 0

    if (IsSet(StartupSplashGui) && !immediate
        && StartupSplashFadeOutMs > 0) {
        steps := 24
        sleepMs := Max(10, Min(60, Ceil(StartupSplashFadeOutMs / steps)))
        Loop steps {
            StartupSplashSetOpacity(
                255 - Round((A_Index / steps) * 255))
            Sleep(sleepMs)
        }
    }
    DestroyStartupSplashCover()
    StartupSplashClosing := false
    LogLine("Startup splash closed.")
}

StartStartupSplash() {
    global EnableStartupSplash, StartupSplashMode, StartupSplashClosing
    if !EnableStartupSplash
        return
    StartupSplashClosing := false
    CreateStartupSplashCover()
    videoStarted := false
    if (StartupSplashMode = "video")
        videoStarted := StartStartupSplashVideo()
    SetTimer(StartupSplashKeepOnTop, 200)
    ArmStartupSplashClose(videoStarted)
    LogLine("Startup splash opened in "
        . (videoStarted ? "Video" : "Black") " mode.")
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
    path := NormalizePath(path)
    if (path = "" || !FileExist(path)) {
        LogLine("Startup program not found: " path, "Warning")
        return false
    }
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
            Run('explorer.exe "' path '"', directory)
        else
            Run('"' path '"', directory, runOptions)
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
ApplyStartupWindowMode(fileName, mode, startedTick) {
    global CompanionDisabled
    static WINDOW_MS := 6000
    static SWEEP_MS := 400
    if CompanionDisabled
        return
    if (A_TickCount - startedTick > WINDOW_MS)
        return
    windows := []
    try windows := WinGetList("ahk_exe " fileName)
    for _, hwnd in windows {
        ; Never touch a window that is already in the requested state, and never
        ; touch one of ours -- the companion's own windows share no process name
        ; with a startup program, but the check costs nothing and documents it.
        if IsOurWindow(hwnd)
            continue
        try {
            if (mode = "hidden")
                WinHide(hwnd)
            else if !DllCall("IsIconic", "Ptr", hwnd, "Int")
                WinMinimize(hwnd)
        }
    }
    SetTimer(ApplyStartupWindowMode.Bind(fileName, mode, startedTick), -SWEEP_MS)
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
        exStyle := 0
        try exStyle := WinGetExStyle("ahk_id " hwnd)
        if ((exStyle & WS_EX_TOOLWINDOW) && !(exStyle & WS_EX_APPWINDOW))
            continue
        x := 0, y := 0, w := 0, h := 0
        try {
            WinGetPos(&posX, &posY, &posW, &posH, "ahk_id " hwnd)
            x := posX, y := posY, w := posW, h := posH
        }
        if (w <= 0 || h <= 0)
            continue
        items.Push(Map(
            "hwnd", hwnd, "title", title, "class", cls, "exe", StrLower(exe),
            "pid", pid, "x", x, "y", y, "w", w, "h", h,
            "ours", IsOurWindow(hwnd)))
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
AssistProcessCpuPercent(pid) {
    global AssistCpuSamples
    static PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    if !pid
        return 0
    handle := DllCall("OpenProcess", "UInt", PROCESS_QUERY_LIMITED_INFORMATION,
        "Int", 0, "UInt", pid, "Ptr")
    if !handle
        return 0
    creation := Buffer(8, 0), exitTime := Buffer(8, 0)
    kernel := Buffer(8, 0), user := Buffer(8, 0)
    ok := DllCall("GetProcessTimes", "Ptr", handle, "Ptr", creation, "Ptr", exitTime,
        "Ptr", kernel, "Ptr", user, "Int")
    DllCall("CloseHandle", "Ptr", handle)
    if !ok
        return 0
    ; FILETIME units are 100ns.
    total := (NumGet(kernel, 0, "Int64") + NumGet(user, 0, "Int64")) / 10000
    now := A_TickCount
    percent := 0
    if AssistCpuSamples.Has(pid) {
        previous := AssistCpuSamples[pid]
        elapsed := now - previous["tick"]
        if (elapsed > 0) {
            busy := total - previous["total"]
            cores := Max(1, EnvGet("NUMBER_OF_PROCESSORS") + 0)
            percent := Max(0, Min(100, (busy / elapsed) * 100 / cores))
        }
    }
    AssistCpuSamples[pid] := Map("total", total, "tick", now)
    return percent
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
AssistWindowLooksLikeGame(item) {
    global AssistProtectedProcesses, AssistLauncherProcesses
    static excluded := 0
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

; True when something game-like appears to be running, by window shape and, if
; the threshold is non-zero, by CPU activity.
AssistGameIsRunning(inventory) {
    global AssistCpuThresholdPercent
    for _, item in inventory {
        if !AssistWindowLooksLikeGame(item)
            continue
        if (AssistCpuThresholdPercent = 0)
            return true
        if (AssistProcessCpuPercent(item["pid"]) >= AssistCpuThresholdPercent)
            return true
        ; Shape alone is enough on the first pass, before a CPU delta exists.
        return true
    }
    return false
}

AssistFindGameWindow(inventory) {
    for _, item in inventory {
        if AssistWindowLooksLikeGame(item)
            return item
    }
    return 0
}

AssistFindSteamWindow(inventory) {
    for _, item in inventory {
        if (!item["ours"] && IsSteamProcess(item["exe"]) && item["title"] != "")
            return item
    }
    return 0
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
    return ProcessNameSetFromList(AssistIgnoreForegroundProcesses).Has(StrLower(exe))
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
    launcherSet := ProcessNameSetFromList(AssistLauncherProcesses)
    protectedSet := ProcessNameSetFromList(AssistProtectedProcesses)
    targets := Map()
    for _, item in inventory {
        exe := item["exe"]
        if (item["ours"] || !launcherSet.Has(exe) || protectedSet.Has(exe))
            continue
        targets[exe] := item["hwnd"]
    }
    ; Launchers that are running without a visible window still count.
    for exe in launcherSet {
        if (protectedSet.Has(exe) || targets.Has(exe))
            continue
        if ProcessExist(exe)
            targets[exe] := 0
    }
    if (targets.Count = 0)
        return 0
    closed := 0
    for exe, hwnd in targets {
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
    if AssistHardKill
        SetTimer(AssistHardKillLaunchers, -AssistGracefulCloseMs)
    return closed
}

AssistHardKillLaunchers() {
    global AssistLauncherProcesses, AssistProtectedProcesses
    launcherSet := ProcessNameSetFromList(AssistLauncherProcesses)
    protectedSet := ProcessNameSetFromList(AssistProtectedProcesses)
    for exe in launcherSet {
        if protectedSet.Has(exe)
            continue
        if ProcessExist(exe) {
            try ProcessClose(exe)
            LogLine("Assist: launcher cleanup force closed " exe ".", "Warning")
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
    gameRunning := IsObject(gameWindow) && AssistGameIsRunning(inventory)

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
        return "No windows"
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
        ; Cloaked windows are the invisible UWP shells Windows keeps around.
        ; Without this the list fills with entries that cannot be switched to.
        if IsCloakedWindow(hwnd)
            continue
        title := "", cls := "", exe := ""
        try title := WinGetTitle("ahk_id " hwnd)
        try cls := WinGetClass("ahk_id " hwnd)
        try exe := WinGetProcessName("ahk_id " hwnd)
        if (title = "" || SHELL_CLASSES.Has(cls))
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
        isSteamWindow := IsSteamProcess(exe)
        if ((exStyle & WS_EX_TOOLWINDOW) && !(exStyle & WS_EX_APPWINDOW)
            && !isSteamWindow)
            continue
        w := 0, h := 0
        try {
            WinGetPos(, , &posW, &posH, "ahk_id " hwnd)
            w := posW, h := posH
        }
        if (w < 120 || h < 80)
            continue
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

ShortenText(text, maxChars) {
    text := Trim(text)
    if (StrLen(text) <= maxChars)
        return text
    return SubStr(text, 1, Max(1, maxChars - 1)) "…"
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
            rows.Push(MenuRow("layoutPage", "Controller Layout", "View mappings", "page:LAYOUT"))
            rows.Push(MenuRow("tasksPage", "Task Switcher",
                GetSwitchableWindowsSummary(), "page:TASKS"))
            rows.Push(MenuRow("gameBar", "Game Bar", "Win + G", "gameBar"))
            rows.Push(MenuRow("settingsPage", "Settings", "Features & configuration",
                "page:SETTINGS"))
            rows.Push(MenuRow("systemPage", "System", "Power & diagnostics", "page:SYSTEM"))
        case "SETTINGS":
            ; The switches worth reaching from a controller. Everything else
            ; still lives in the full Settings window at the bottom of the page.
            rows.Push(MenuRow("back", "Back", "", "back"))
            for _, row in QuickMenuSettingsRows()
                rows.Push(row)
            rows.Push(MenuRow("settings", "All Settings…", "Open Settings window",
                "settings"))
        case "TASKS":
            rows.Push(MenuRow("back", "Back", "", "back"))
            QuickMenuTaskWindows := GetSwitchableWindows()
            if (QuickMenuTaskWindows.Length = 0) {
                rows.Push(MenuRow("noTasks", "No switchable windows", "", "none"))
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
                    ? "Disabled by Windows"
                    : "‹ " (hdr["enabled"] ? "ON" : "OFF") " ›"
                hdrAction := hdr["forceDisabled"] ? "none" : "hdr"
                rows.Push(MenuRow("hdr", "HDR", hdrValue, hdrAction,
                    !hdr["forceDisabled"]))
            } else {
                rows.Push(MenuRow("hdrUnavailable", "HDR",
                    IsObject(hdr) ? "Unsupported" : "Unavailable", "none"))
            }
            if (QuickMenuDisplayModes.Length = 0)
                QuickMenuDisplayModes := GetPrimaryDisplayModes()
            if (QuickMenuDisplayModes.Length = 0) {
                rows.Push(MenuRow("displayUnavailable", "No compatible modes reported", "", "none"))
            } else {
                EnsureDisplaySelection()
                rows.Push(MenuRow("displayResolution", "Resolution",
                    "‹ " DisplaySelectedWidth " × " DisplaySelectedHeight " ›",
                    "displayResolution", true))
                rows.Push(MenuRow("displayRefresh", "Refresh rate",
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
                } else if FileExist(NormalizePath(RtssPath)) {
                    rows.Push(MenuRow("rtssStart", "Start RTSS",
                        "Launch configured executable", "rtssStart"))
                } else {
                    rows.Push(MenuRow("rtssMissing", "RTSS",
                        "Executable not found", "none"))
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
                    rows.Push(MenuRow("rtssSaveProfile", "Save Limit to Profile",
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
                    value .= "  /  hold: " longValue
                rows.Push(MenuRow("layout:" button, button, value, "none"))
            }
        case "SYSTEM":
            rows.Push(MenuRow("back", "Back", "", "back"))
            rows.Push(MenuRow("sleep", "Sleep", "", "sleep"))
            rows.Push(MenuRow("restart", "Restart", "", "restart"))
            rows.Push(MenuRow("shutdown", "Shut Down", "", "shutdown"))
            rows.Push(MenuRow("exit", "Exit Companion", "", "exit"))
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
; live global, so it takes effect at once AND survives a restart -- except the
; explicitly labelled startup splash, which is a next-launch feature. The full
; Settings window's Save button is not involved.
QuickMenuToggleMeta(id) {
    global EnableGameFocusLite, EnableSteamAssistLite, EnableLauncherCleanupLite
    global AssistSuspendOnShellOverlay
    global EnableViewSteamActions, EnableViewTapAction, EnableViewHoldAction
    global EnableStartupSplash
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
                "label", "Pause assist on FSE switcher",
                "value", AssistSuspendOnShellOverlay)
        case "viewActions":
            return Map("section", "Steam", "key", "EnableViewButtonActions",
                "label", "View button Steam actions", "value", EnableViewSteamActions)
        case "viewTap":
            return Map("section", "Steam", "key", "EnableViewTapAction",
                "label", "View tap action", "value", EnableViewTapAction)
        case "viewHold":
            return Map("section", "Steam", "key", "EnableViewHoldAction",
                "label", "View hold action", "value", EnableViewHoldAction)
        case "startupSplash":
            return Map("section", "StartupSplash", "key", "Enable",
                "label", "Startup splash (next launch)",
                "value", EnableStartupSplash)
    }
    return 0
}

QuickMenuToggleSetting(id) {
    global EnableGameFocusLite, EnableSteamAssistLite, EnableLauncherCleanupLite
    global AssistSuspendOnShellOverlay
    global EnableViewSteamActions, EnableViewTapAction, EnableViewHoldAction
    global EnableStartupSplash
    global IniPath
    meta := QuickMenuToggleMeta(id)
    if !IsObject(meta)
        return
    next := !meta["value"]
    ; Persistence is the transaction boundary. Do not change the live state or
    ; claim success if the portable INI is read-only or otherwise unwritable.
    try {
        IniWrite(next ? "true" : "false",
            IniPath, meta["section"], meta["key"])
    } catch as err {
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
        case "startupSplash":
            EnableStartupSplash := next
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
        "viewActions", "viewTap", "viewHold", "startupSplash"] {
        meta := QuickMenuToggleMeta(id)
        rows.Push(MenuRow("toggle:" id, meta["label"], OnOffText(meta["value"]),
            "toggle:" id, true))
    }
    return rows
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
        return "Setup required"
    if ProcessExist("RTSS.exe") {
        if !RtssUseDllIntegration
            return "Running | Shortcuts"
        state := GetRtssGlobalState()
        if IsObject(state)
            return "Overlay " (state["overlay"] ? "On" : "Off")
                . " | Limiter " (state["limiter"] ? "On" : "Off")
        return "Running"
    }
    return FileExist(NormalizePath(RtssPath)) ? "RTSS ready" : "RTSS not found"
}

GetRtssAvailability() {
    global EnableRTSSIntegration, RtssPath
    if !EnableRTSSIntegration
        return "Setup required"
    if ProcessExist("RTSS.exe")
        return "Running"
    return FileExist(NormalizePath(RtssPath)) ? "Ready to start" : "Not found"
}

GetFrameCapLabel() {
    global RtssCustomFrameCap
    return RtssCustomFrameCap > 0 ? RtssCustomFrameCap " FPS preset" : "RTSS preset"
}

; ------------------------------------------------------------------------------
; Quick Menu frame cap
; ------------------------------------------------------------------------------
; RTSS exposes two independent mechanisms and the Quick Menu presents them as one
; row, because two rows that can each mean "no limiting" is a menu that fights
; itself:
;
;   limiter flag (global, bit 0x4 = DISABLED)  master on/off
;   FramerateLimit (per profile, DWORD)        the target, 0 = uncapped
;
; "Off" therefore maps to the FLAG and never to the value. Writing 0 would
; destroy the user's number, so turning the cap off and back on would silently
; forget 72 and come back uncapped. Clearing the flag leaves 72 in the profile
; and restores it on the way back.
;
; Everything here targets the GLOBAL profile only. Per-game profiles are the
; user's own tuning and are deliberately never written: a quick menu that edits
; whichever profile happens to be in the foreground is a menu that can silently
; change a game's configuration.
RtssFrameCapWritable() {
    global RtssSetProfilePropertyProc, RtssSaveProfileProc, RtssLoadProfileProc
    return RtssLoadProfileProc && RtssSetProfilePropertyProc && RtssSaveProfileProc
}

RtssGlobalFrameLimit() {
    global RtssFrameLimitCacheFps, RtssFrameLimitCacheTick
    static CACHE_MS := 400
    if (RtssFrameLimitCacheTick
        && A_TickCount - RtssFrameLimitCacheTick < CACHE_MS)
        return RtssFrameLimitCacheFps
    limit := GetRtssFrameLimit("")
    RtssFrameLimitCacheFps := IsObject(limit) ? limit["fps"] : 0
    RtssFrameLimitCacheTick := A_TickCount
    return RtssFrameLimitCacheFps
}

IsRtssFrameCapPreset(fps) {
    global RtssFrameCapPresets
    for _, preset in RtssFrameCapPresets {
        if (fps = preset)
            return true
    }
    return false
}

; Resolves the flag and the value into the single state the row displays:
;   "off"     limiter flag cleared, or flag set with no target
;   "preset"  a value from RtssFrameCapPresets
;   "custom"  any other non-zero value, or the user cycling to Custom
GetRtssFrameCapState() {
    global RtssFrameCapCustomMode
    state := GetRtssGlobalState()
    if !IsObject(state)
        return 0
    fps := RtssGlobalFrameLimit()
    if (!state["limiter"] || fps <= 0)
        return Map("mode", "off", "fps", fps, "limiter", state["limiter"])
    if (IsRtssFrameCapPreset(fps) && !RtssFrameCapCustomMode)
        return Map("mode", "preset", "fps", fps, "limiter", true)
    return Map("mode", "custom", "fps", fps, "limiter", true)
}

RtssFrameCapValueText() {
    state := GetRtssFrameCapState()
    if !IsObject(state)
        return "Unavailable"
    if !RtssFrameCapWritable()
        return state["mode"] = "off" ? "OFF (read-only)" : state["fps"] " FPS (read-only)"
    switch state["mode"] {
        case "off":
            return "‹ OFF ›"
        case "custom":
            return "‹ CUSTOM ›"
    }
    return "‹ " state["fps"] " FPS ›"
}

; Writes FramerateLimit into the global profile. SaveProfile persists it to
; RTSS's own configuration, so this is a real edit the user will see in RTSS --
; intended, but worth a log line rather than happening silently.
SetRtssGlobalFrameLimit(fps) {
    global RtssFrameLimitCacheTick
    if !EnsureRtssRunning()
        return false
    api := GetRtssHooksApi()
    if (!IsObject(api) || !RtssFrameCapWritable()) {
        SetStatus("This RTSS build cannot set the frame cap directly", "Warning")
        return false
    }
    fps := Max(0, Min(1000, fps))
    value := Buffer(4, 0)
    NumPut("UInt", fps, value, 0)
    try {
        DllCall(api["loadProfile"], "AStr", "")
        ok := DllCall(api["setProfileProperty"],
            "AStr", "FramerateLimit", "Ptr", value, "UInt", value.Size, "Int")
        if !ok {
            LogLine("RTSS FramerateLimit write was rejected.", "Warning")
            SetStatus("RTSS did not accept the frame cap", "Warning")
            return false
        }
        DllCall(api["saveProfile"], "AStr", "")
        if api["updateProfiles"]
            DllCall(api["updateProfiles"])
        NotifyRtssSettingsChanged()
        RtssFrameLimitCacheTick := 0
        LogLine("RTSS global FramerateLimit set to " fps ".")
        return true
    } catch as err {
        LogLine("RTSS FramerateLimit write failed: " err.Message, "Warning")
        SetStatus("RTSS did not accept the frame cap", "Warning")
        return false
    }
}

; Left/Right on the Frame Limit row. QuickMenuRender rebuilds the row list on
; every refresh here, so the Custom row appears and disappears on its own.
CycleRtssFrameCap(direction) {
    global RtssFrameCapPresets, RtssFrameCapCustomMode
    state := GetRtssFrameCapState()
    if !IsObject(state) {
        SetStatus("RTSS live state is unavailable", "Warning")
        return
    }
    if !RtssFrameCapWritable() {
        SetStatus("This RTSS build cannot set the frame cap directly", "Warning")
        return
    }

    ; Coming off "Off" restores the number the profile still holds instead of
    ; jumping to the first preset. This is the payoff for never writing 0: the
    ; user's 72 survives an off/on round trip untouched. Only applies when the
    ; flag is what turned it off; a flag that is on with no target has nothing
    ; to restore and falls through to the list below.
    if (direction > 0 && state["mode"] = "off"
        && !state["limiter"] && state["fps"] > 0) {
        RtssFrameCapCustomMode := false
        ApplyRtssGlobalState("limiter", true)
        return
    }

    ; Anything still being dialled in on the Custom row must not land after this.
    CancelPendingRtssFrameCap()

    ; One ordered list: Off, every preset, then Custom.
    entries := ["off"]
    for _, preset in RtssFrameCapPresets
        entries.Push(preset)
    entries.Push("custom")

    index := 1
    switch state["mode"] {
        case "custom":
            index := entries.Length
        case "preset":
            for entryIndex, entry in entries {
                if (entry = state["fps"]) {
                    index := entryIndex
                    break
                }
            }
    }
    index := Max(1, Min(entries.Length, index + direction))
    target := entries[index]

    if (target = "off") {
        RtssFrameCapCustomMode := false
        ; Value untouched on purpose -- see the header comment.
        ;
        ; Only written when the flag actually has to change. Left clamps to
        ; this entry at the end of the list, so without the guard every further
        ; press re-issued the SetFlags call and re-showed its notification.
        if state["limiter"]
            ApplyRtssGlobalState("limiter", false)
        return
    }
    if (target = "custom") {
        ; Seeds from whatever is live and applies nothing. Landing on Custom
        ; must never change the frame rate by itself.
        RtssFrameCapCustomMode := true
        if (!state["limiter"] || state["fps"] <= 0) {
            SetRtssGlobalFrameLimit(RtssFrameCapPresets[1])
            ApplyRtssGlobalState("limiter", true)
        }
        return
    }
    RtssFrameCapCustomMode := false
    SetRtssGlobalFrameLimit(target)
    if !state["limiter"]
        ApplyRtssGlobalState("limiter", true)
}

; The one place a per-game profile is written, and only ever on an explicit,
; confirmed request. Returns the executable this would target, or "" when there
; is nothing valid to save to.
;
; The name comes from QuickMenuPreviousExe -- what owned the screen BEFORE the
; menu opened; asking now would always answer SteamShell-XFE. Steam's own
; surfaces are excluded because a profile named steam.exe or steamwebhelper.exe
; caps the client rather than a game, which is never what this row means.
; A profile named steam.exe caps the Steam client rather than a game, and one
; named after the companion or Explorer is meaningless.
IsUsableProfileExe(exeName) {
    exeName := StrLower(Trim(exeName))
    if (exeName = "" || IsSteamProcess(exeName))
        return false
    return exeName != "steamshell-xfe.exe" && exeName != "explorer.exe"
}

; Two sources, in order of directness.
;
; What owned the screen before the menu opened is the best answer when it is
; usable. It is not always: a borderless game can sit behind a Steam surface, and
; Xbox FSE can return to Steam on its own -- in both cases the captured exe is
; steam.exe, which is excluded, and the row reads "No game in foreground" while a
; game is plainly running.
;
; So fall back to the last foreground that looked game-like, which the foreground
; observer already tracks and which survives Steam coming forward afterwards.
RtssProfileTargetExe() {
    global QuickMenuPreviousExe, LastObservedGameExe
    exeName := Trim(QuickMenuPreviousExe)
    if IsUsableProfileExe(exeName)
        return exeName
    exeName := Trim(LastObservedGameExe)
    if IsUsableProfileExe(exeName)
        return exeName
    return ""
}

; Names what it actually saw rather than reporting a bare negative. "Steam is in
; front and no game was detected" and "nothing is running" are different
; problems, and the row is the only place the difference is visible.
RtssSaveProfileValueText() {
    global QuickMenuPreviousExe
    if !RtssFrameCapWritable()
        return "Unavailable"
    exeName := RtssProfileTargetExe()
    if (exeName != "")
        return exeName
    previous := Trim(QuickMenuPreviousExe)
    if (previous != "" && IsSteamProcess(previous))
        return "Steam in front, no game detected"
    return "No game in foreground"
}

; Copies the current global frame cap into the foreground executable's own RTSS
; profile.
;
; Deliberately surgical: the target profile is loaded FIRST so that whatever
; else the user has tuned for that game survives, and only FramerateLimit is
; replaced. Cloning the global profile wholesale would be one call shorter and
; would silently overwrite that game's overlay and hotkey settings.
;
; RTSS applies a per-game profile automatically whenever that executable runs,
; so this is a persistent change the user will not see again until it surprises
; them. Hence the confirmation at the call site and the log line here.
SaveRtssFrameLimitToProfile() {
    global RtssFrameLimitCacheTick, QuickMenuPreviousExe, LastObservedGameExe
    exeName := RtssProfileTargetExe()
    if (exeName = "") {
        SetStatus("No foreground game to save a profile for", "Warning")
        return false
    }
    if !RtssFrameCapWritable() {
        SetStatus("This RTSS build cannot write profiles directly", "Warning")
        return false
    }
    if !EnsureRtssRunning()
        return false
    api := GetRtssHooksApi()
    if !IsObject(api)
        return false

    ; Flush anything still pending so the profile gets the value on screen.
    CommitRtssPendingFrameCap()
    fps := RtssGlobalFrameLimit()
    value := Buffer(4, 0)
    NumPut("UInt", fps, value, 0)
    try {
        ; Load the game's existing profile so unrelated properties are preserved.
        DllCall(api["loadProfile"], "AStr", exeName)
        ok := DllCall(api["setProfileProperty"],
            "AStr", "FramerateLimit", "Ptr", value, "UInt", value.Size, "Int")
        if !ok {
            LogLine("RTSS profile write was rejected for " exeName ".", "Warning")
            SetStatus("RTSS did not accept the profile write", "Warning")
            return false
        }
        DllCall(api["saveProfile"], "AStr", exeName)
        if api["updateProfiles"]
            DllCall(api["updateProfiles"])
        NotifyRtssSettingsChanged()
        ; The global profile was displaced by the LoadProfile above; restore it
        ; so the Frame Limit row keeps reading the value it is supposed to show.
        try DllCall(api["loadProfile"], "AStr", "")
        RtssFrameLimitCacheTick := 0
        LogLine("RTSS profile " exeName " saved with FramerateLimit " fps
            . " (foreground was '" QuickMenuPreviousExe "', last game '"
            . LastObservedGameExe "').")
        SetStatus(exeName ": " (fps > 0 ? fps " FPS" : "uncapped") " saved")
        return true
    } catch as err {
        LogLine("RTSS profile write failed for " exeName ": " err.Message, "Warning")
        SetStatus("RTSS did not accept the profile write", "Warning")
        try DllCall(api["loadProfile"], "AStr", "")
        RtssFrameLimitCacheTick := 0
        return false
    }
}

; Left/Right on the Custom FPS row.
;
; Quick Menu navigation is edge-triggered -- the poll loop reports
; `buttons & ~prevButtons` and nothing in the menu auto-repeats -- so a fixed
; step of 1 would need sixty presses to get from 60 to 120. Consecutive presses
; in the same direction therefore escalate 1 -> 5 -> 10, and any pause or
; reversal drops back to 1 so a single press is still a single frame.
; Cancels a value that was being dialled in but must not land.
;
; Needed because the commit is deferred: cycling from Custom to a preset while a
; pending value is still in flight would otherwise let the timer fire afterwards
; and overwrite the preset the user just chose.
CancelPendingRtssFrameCap() {
    global RtssPendingFrameCap
    RtssPendingFrameCap := 0
    SetTimer(CommitRtssPendingFrameCap, 0)
}

CommitRtssPendingFrameCap() {
    global RtssPendingFrameCap
    if (RtssPendingFrameCap <= 0)
        return
    value := RtssPendingFrameCap
    RtssPendingFrameCap := 0
    SetRtssGlobalFrameLimit(value)
}

; Left/Right on the Custom FPS row.
;
; Two things make naive stepping unpleasant, and they are separate problems.
;
; 1. WRITING ON EVERY PRESS. SetRtssGlobalFrameLimit is a LoadProfile plus a
;    SetProfileProperty plus a SaveProfile -- a disk write -- plus UpdateProfiles.
;    Doing that per press means the limiter is genuinely reconfigured a dozen
;    times while the user scrolls, and the frame rate chases the number. So the
;    value is held pending, the row shows it immediately, and RTSS is written
;    once the user stops.
;
; 2. ESCALATING OFF-GRID. Quick Menu navigation is edge-triggered with no
;    auto-repeat, so a fixed step of 1 needs sixty presses to cross 60->120 and
;    the step has to grow. But growing it from an arbitrary value lands on
;    arbitrary values: 63 stepping by 5 gives 68, 73, 78, and 60 or 90 become
;    unreachable without slowing down and creeping. Coarse steps therefore snap
;    to their own grid -- 63 by 5 goes to 65, then 70 -- so fast stepping lands
;    on round numbers and fine stepping still moves by exactly 1.
AdjustRtssCustomFrameCap(direction) {
    global RtssPendingFrameCap
    static COMMIT_DELAY_MS := 400

    if !RtssFrameCapWritable() {
        SetStatus("This RTSS build cannot set the frame cap directly", "Warning")
        return
    }
    current := RtssPendingFrameCap > 0 ? RtssPendingFrameCap : RtssGlobalFrameLimit()
    if (current <= 0)
        current := 60
    RtssPendingFrameCap := Max(10, Min(1000, current + direction))
    SetTimer(CommitRtssPendingFrameCap, -COMMIT_DELAY_MS)
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

; Hides the Quick Menu, then sends a shell shortcut once focus has settled.
;
; Sending immediately after Hide() delivers the keystroke while our window is
; still tearing down and focus is mid-transfer, which is why Game Bar could
; appear and be dismissed again straight away. The short delay lets the
; foreground application take focus back first so the shortcut lands on a
; stable target.
QuickMenuHideThenSend(keys, delayMs := 150) {
    HideQuickMenu()
    SetTimer(() => SendChordSafe(keys), -delayMs)
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
    global QuickMenuPreviousHwnd
    if IsSet(QuickMenuGui)
        try QuickMenuGui.Hide()
    QuickMenuVisible := false
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

; Breadcrumb, so the current page is always identifiable rather than the title
; simply being replaced.
QuickMenuTitle() {
    global QuickMenuPage
    titles := Map(
        "AUDIO", "Audio",
        "DISPLAY", "Display & HDR",
        "RTSS", "RTSS & Performance",
        "LAYOUT", "Controller Layout",
        "TASKS", "Task Switcher",
        "SETTINGS", "Settings",
        "SYSTEM", "System"
    )
    if !titles.Has(QuickMenuPage)
        return "SteamShell XFE"
    return "SteamShell XFE  ›  " titles[QuickMenuPage]
}

QuickMenuBuildGui() {
    global QuickMenuGui, QuickMenuTitleCtrl, QuickMenuStatusCtrl
    global QuickMenuLabelCtrls, QuickMenuValueCtrls
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
        QuickMenuLabelCtrls := []
        QuickMenuValueCtrls := []
        ; Two controls per row, adjacent, so one shared background paints a
        ; continuous highlight. Text is padded inward with spaces rather than by
        ; offsetting the controls, which would leave unhighlighted gaps.
        Loop 14 {
            index := A_Index
            y := QuickMenuRowTop() + ((index - 1) * QuickMenuRowHeight())
            menu.SetFont("s12 c" QM_LABEL " Norm", "Segoe UI")
            labelCtrl := menu.AddText(
                "x" inset " y" y " w" labelWidth " h32 +0x200 Background" QM_BG, "")
            labelCtrl.OnEvent("Click", QuickMenuMouseActivate.Bind(index))
            menu.SetFont("s11 c" QM_VALUE " Norm", "Segoe UI")
            valueCtrl := menu.AddText(
                "x" (inset + labelWidth) " y" y " w" (rowWidth - labelWidth)
                . " h32 Right +0x200 Background" QM_BG, "")
            valueCtrl.OnEvent("Click", QuickMenuMouseActivate.Bind(index))
            QuickMenuLabelCtrls.Push(labelCtrl)
            QuickMenuValueCtrls.Push(valueCtrl)
        }
        ; Bottom line carries the button hint, and transient status messages when
        ; there are any. Keeping it off the top leaves the title uncluttered.
        menu.SetFont("s9 c" QM_VALUE " Norm", "Segoe UI")
        QuickMenuStatusCtrl := menu.AddText(
            "x" (inset + 12) " y600 w" (rowWidth - 12) " h36 +Wrap", "")
        ; Escape mirrors B: back one page, and close from the main page.
        menu.OnEvent("Escape", (*) => QuickMenuGoBack())
        QuickMenuGui := menu
    }
    QuickMenuRender()
    ; Derive the height from the same figures that lay the content out, so the
    ; window finishes just below the status line. The previous constant left a
    ; fixed 53px of empty space under everything, which reads as a large unused
    ; margin now that the status line is usually blank.
    height := Min(QuickMenuStatusY(QuickMenuRows.Length) + QuickMenuStatusHeight()
        + QuickMenuBottomMargin(), 820)
    ; The show is deferred so the corners are already rounded when the window
    ; first appears. Applied afterwards, they are square for a frame -- part of
    ; what read as the menu assembling itself on screen.
    deferred := CenterGuiOnMonitorActual(QuickMenuGui, QuickMenuMonitorIndex,
        width, height, false, true)
    ; Reveal FIRST, then measure and shape.
    ;
    ; Everything below needs the window's real size, and a hidden window does not
    ; reliably report one. Sizing and shaping from a hidden measurement is what
    ; clipped the menu on a 4K display. The window appears and is shaped within the
    ; same message-pump turn, so nothing is visible in between.
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
    monitorIndex := Max(1, Min(MonitorGetCount(), QuickMenuMonitorIndex))
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

; Rounds the window corners. Applied after the window is sized and shown,
; because the region is expressed in real window pixels and the layout is
; specified in DPI-scaled units. It must be reapplied on every resize, so this
; runs on each page change rather than only at creation.
ApplyRoundedCorners(guiObj, radius) {
    ; Never shape a hidden window.
    ;
    ; WinSetRegion CLIPS the window to the region, and a window that is not yet on
    ; screen can report a size that is wrong -- the same hazard PositionGuiCentered
    ; already compensates for. Measured on a 4K television: the region came out at
    ; the logical height while the window was at the scaled height, so the menu was
    ; cut off with a clean rounded edge straight through a row. That is why every
    ; page change afterwards looked right: those measure a real, visible window.
    visible := false
    try visible := DllCall("IsWindowVisible", "Ptr", guiObj.Hwnd, "Int") != 0
    if !visible
        return
    try {
        WinGetPos(, , &realWidth, &realHeight, "ahk_id " guiObj.Hwnd)
        if (realWidth > 0 && realHeight > 0) {
            scaled := Round(radius * (A_ScreenDPI / 96.0))
            WinSetRegion("0-0 w" realWidth " h" realHeight
                . " R" scaled "-" scaled, "ahk_id " guiObj.Hwnd)
        }
    }
}

; Layout figures shared by the renderer and the height calculation. Keeping them
; in one place stops the window size and the content position drifting apart.
; Quick Menu geometry. Every position and the window height derive from these,
; so the layout cannot drift out of step with the window size.
QuickMenuWidth() {
    return 620
}

QuickMenuRowTop() {
    return 74
}

QuickMenuRowHeight() {
    return 40
}

; The highlight is inset from the window edge, and the row text is inset again
; inside the highlight, so the selected bar reads as a panel rather than a strip
; running edge to edge.
QuickMenuRowInset() {
    return 20
}

QuickMenuStatusY(rowCount) {
    return QuickMenuRowTop() + 8 + (rowCount * QuickMenuRowHeight())
}

QuickMenuStatusHeight() {
    return 36
}

QuickMenuBottomMargin() {
    return 16
}

QuickMenuRender() {
    global QuickMenuRows, QuickMenuSelected, QuickMenuTitleCtrl, QuickMenuStatusCtrl
    global QuickMenuLabelCtrls, QuickMenuValueCtrls
    global LastStatusText, LastStatusLevel, QuickMenuVisible
    global QM_BG, QM_ROW_SELECTED, QM_ACCENT, QM_LABEL, QM_LABEL_SELECTED, QM_VALUE
    if !QuickMenuVisible
        return
    QuickMenuRows := QuickMenuGetRows()
    if (QuickMenuRows.Length = 0)
        return
    QuickMenuSelected := Max(1, Min(QuickMenuRows.Length, QuickMenuSelected))
    QuickMenuTitleCtrl.Text := GuiSafeLabel(QuickMenuTitle())
    Loop QuickMenuLabelCtrls.Length {
        index := A_Index
        labelCtrl := QuickMenuLabelCtrls[index]
        valueCtrl := QuickMenuValueCtrls[index]
        if (index > QuickMenuRows.Length) {
            labelCtrl.Visible := false
            valueCtrl.Visible := false
            continue
        }
        row := QuickMenuRows[index]
        selected := index = QuickMenuSelected
        labelCtrl.Visible := true
        valueCtrl.Visible := true
        ; Setting a background changes the property but does not repaint what is
        ; already on screen, so the control is redrawn explicitly. Without this
        ; a row keeps the highlight it had when it was last selected.
        rowBackground := selected ? QM_ROW_SELECTED : QM_BG
        labelCtrl.Opt("+Background" rowBackground)
        valueCtrl.Opt("+Background" rowBackground)
        ; Padding is applied as text rather than by moving the controls, so the
        ; highlight stays continuous behind it.
        labelCtrl.Text := "  " GuiSafeLabel(row["label"])
        valueCtrl.Text := GuiSafeLabel(row["value"]) "  "
        labelCtrl.SetFont("s12 c"
            . (selected ? QM_LABEL_SELECTED " Bold" : QM_LABEL " Norm"), "Segoe UI")
        valueCtrl.SetFont("s11 c" (selected ? QM_ACCENT : QM_VALUE) " Norm",
            "Segoe UI")
        try labelCtrl.Redraw()
        try valueCtrl.Redraw()
    }
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
        return "D-pad move  •  A switch to  •  X close  •  B back"
    if (QuickMenuPage = "DISPLAY")
        return "D-pad move  •  Left/Right change  •  A select  •  B back"
    if (QuickMenuPage = "RTSS")
        return "D-pad move  •  Left/Right Off/On  •  A select  •  B back"
    if (QuickMenuPage = "SETTINGS")
        return "D-pad move  •  A or Left/Right toggle  •  B back"
    return "D-pad move  •  A select  •  B back"
}

QuickMenuRefresh() {
    global QuickMenuVisible
    if QuickMenuVisible
        QuickMenuRender()
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

QuickMenuGoBack() {
    global QuickMenuPage, QuickMenuSelected
    if (QuickMenuPage = "MAIN") {
        HideQuickMenu()
        return
    }
    QuickMenuPage := "MAIN"
    QuickMenuSelected := 1
    QuickMenuBuildGui()
}

QuickMenuConfirm(id, description) {
    global QuickMenuConfirmAction, QuickMenuConfirmUntilTick
    if (QuickMenuConfirmAction = id && A_TickCount < QuickMenuConfirmUntilTick) {
        QuickMenuConfirmAction := ""
        return true
    }
    QuickMenuConfirmAction := id
    QuickMenuConfirmUntilTick := A_TickCount + 5000
    SetStatus("Select again within 5 seconds to confirm " description, "Warning")
    return false
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
            CycleRtssFrameCap(1)
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
                nextVolume := Max(0, Min(100, Round(SoundGetVolume()) + direction * 5))
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
    }
    QuickMenuRefresh()
}

; Moves the selection, wrapping at both ends. Shared by the controller and the
; keyboard so the two can never drift apart.
QuickMenuMoveSelection(delta) {
    global QuickMenuRows, QuickMenuSelected
    if (QuickMenuRows.Length = 0)
        return
    QuickMenuSelected += delta
    if (QuickMenuSelected < 1)
        QuickMenuSelected := QuickMenuRows.Length
    if (QuickMenuSelected > QuickMenuRows.Length)
        QuickMenuSelected := 1
    QuickMenuRefresh()
}

; Keyboard equivalents for the Quick Menu.
;
; The menu has no focusable controls -- every row is a Text control -- so arrow
; keys never reach it as ordinary input. They are registered as hotkeys that are
; live only while the menu is both visible and focused, and they call the same
; action functions the controller does rather than duplicating any behaviour.
QuickMenuKeyboardActive(*) {
    global QuickMenuVisible, QuickMenuGui
    if (!QuickMenuVisible || !IsSet(QuickMenuGui))
        return false
    try return WinActive("ahk_id " QuickMenuGui.Hwnd) != 0
    return false
}

RegisterQuickMenuKeys() {
    HotIf QuickMenuKeyboardActive
    Hotkey("Up", (*) => QuickMenuMoveSelection(-1))
    Hotkey("Down", (*) => QuickMenuMoveSelection(1))
    Hotkey("Left", (*) => QuickMenuAdjustSelected(-1))
    Hotkey("Right", (*) => QuickMenuAdjustSelected(1))
    Hotkey("Enter", (*) => QuickMenuActivateSelected())
    Hotkey("NumpadEnter", (*) => QuickMenuActivateSelected())
    Hotkey("Space", (*) => QuickMenuActivateSelected())
    Hotkey("Backspace", (*) => QuickMenuGoBack())
    Hotkey("Delete", (*) => QuickMenuCloseSelected())
    Hotkey("Home", (*) => QuickMenuSelectFirst())
    Hotkey("End", (*) => QuickMenuSelectLast())
    HotIf
}

QuickMenuSelectFirst() {
    global QuickMenuSelected
    QuickMenuSelected := 1
    QuickMenuRefresh()
}

QuickMenuSelectLast() {
    global QuickMenuSelected, QuickMenuRows
    QuickMenuSelected := Max(1, QuickMenuRows.Length)
    QuickMenuRefresh()
}

; Rows whose value is a number the user dials, rather than a list they step
; through. Only these accept hold-to-repeat.
QuickMenuRowAcceptsRepeat() {
    global QuickMenuRows, QuickMenuSelected
    static ids := Map("rtssFrameLimitCustom", true, "volume", true)
    if (QuickMenuRows.Length = 0
        || QuickMenuSelected < 1 || QuickMenuSelected > QuickMenuRows.Length)
        return false
    return ids.Has(QuickMenuRows[QuickMenuSelected]["action"])
}

QuickMenuHandleController(pressed, lx, ly, buttons := 0) {
    global QuickMenuRows, QuickMenuSelected
    static holdDir := 0
    static holdSince := 0
    static lastRepeatTick := 0

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
    settings.AddText("x264 y96 w1 h455 +0x10")
    settings.SetFont("s16 Bold", "Segoe UI")
    SettingsCategoryTitleCtrl := settings.AddText("x286 y96 w610 h32", "General")
    settings.SetFont("s9 Norm", "Segoe UI")
    SettingsCategoryDescriptionCtrl := settings.AddText(
        "x286 y132 w610 h42 +Wrap",
        "Quick Menu, heartbeat, and the controls shown in the living-room interface.")

    ; General
    settings.SetFont("s10", "Segoe UI")
    control := settings.AddCheckbox("x300 y190 w550 h26", "Enable controller Quick Menu")
    SettingsRegisterField("General", "QuickMenu.Enable", control, "Click")
    SettingsAddEditRow(settings, "General", "QuickMenu.ChordHoldMs",
        "Quick Menu L3 + R3 hold (ms)", 230, true)
    SettingsAddEditRow(settings, "General", "Companion.HeartbeatSeconds",
        "Heartbeat log interval (seconds)", 270, true)
    control := settings.AddCheckbox("x300 y320 w550 h26", "Show audio controls")
    SettingsRegisterField("General", "Audio.EnableQuickControls", control, "Click")
    control := settings.AddCheckbox("x300 y356 w550 h26", "Show display and HDR controls")
    SettingsRegisterField("General", "Display.EnableQuickControls", control, "Click")
    control := settings.AddText("x300 y410 w570 h76 +Wrap",
        "Integration: configure AnyFSE to launch Steam Big Picture as the Home app, "
        . "add SteamShell-XFE.exe as a startup app, and leave “Exit FSE when Home app exits” off.")
    SettingsTrackControl("General", control)

    ; Controller & Cursor
    control := settings.AddCheckbox(
        "x300 y190 w570 h26", "Enable View/Back controller mappings and mouse mode")
    SettingsRegisterField(
        "Controller & Cursor", "Controller.EnableControllerMouseMode", control, "Click")
    ; The backend row uses the same label/control columns as the edit rows
    ; below it so the page reads as one aligned list.
    label := settings.AddText("x300 y222 w250 h24 +0x200", "Input backend")
    SettingsTrackControl("Controller & Cursor", label)
    backendDrop := settings.AddDropDownList("x570 y220 w150",
        ["Auto", "XInput", "GameInput", "RawInput"])
    SettingsRegisterField("Controller & Cursor", "Controller.Backend", backendDrop, "Change")
    control := settings.AddText("x300 y250 w570 h20",
        "Auto is recommended: RawInput works inside Xbox FSE, XInput on the desktop.")
    SettingsTrackControl("Controller & Cursor", control)
    SettingsAddEditRow(settings, "Controller & Cursor", "Controller.ControllerIndex",
        "Controller index (0–3)", 278, true)
    SettingsAddEditRow(settings, "Controller & Cursor", "Controller.ControllerDeadzone",
        "Stick deadzone", 312, true)
    SettingsAddEditRow(settings, "Controller & Cursor", "Controller.ControllerMouseSpeed",
        "Pointer speed", 346, true)
    SettingsAddEditRow(settings, "Controller & Cursor", "Controller.ControllerChordHoldMs",
        "Long-press threshold (ms)", 380, true)
    control := settings.AddCheckbox("x300 y414 w570 h26", "Hide the cursor after inactivity")
    SettingsRegisterField("Controller & Cursor", "Cursor.EnableAutoHide", control, "Click")
    SettingsAddEditRow(settings, "Controller & Cursor", "Cursor.HideDelayMs",
        "Cursor hide delay (ms)", 448, true)
    control := settings.AddCheckbox("x300 y482 w320 h26", "Park the cursor at startup")
    SettingsRegisterField("Controller & Cursor", "Cursor.ParkOnStartup", control, "Click")
    control := settings.AddCheckbox("x300 y510 w320 h26", "Park when a game enters fullscreen")
    SettingsRegisterField("Controller & Cursor", "Cursor.ParkOnGameStart", control, "Click")
    control := settings.AddCheckbox("x300 y538 w320 h26", "Park after returning to Steam")
    SettingsRegisterField("Controller & Cursor", "Cursor.ParkOnSteamReturn", control, "Click")
    ; Kept left of x650: the button column starts there, and this row shares a
    ; band with "Delete Learned Profile".
    label := settings.AddText("x300 y570 w170 h24 +0x200", "Park the cursor at")
    SettingsTrackControl("Controller & Cursor", label)
    parkEdgeDrop := settings.AddDropDownList("x480 y568 w150",
        ["Right edge", "Left edge"])
    SettingsRegisterField("Controller & Cursor", "Cursor.ParkEdge", parkEdgeDrop, "Change")
    mapButton := settings.AddButton("x650 y480 w220 h34", "Controller Mappings...")
    mapButton.OnEvent("Click", ShowMappingEditor)
    SettingsTrackControl("Controller & Cursor", mapButton)
    learnButton := settings.AddButton("x650 y518 w220 h34", "Learn Controller...")
    learnButton.OnEvent("Click", ShowControllerLearner)
    SettingsTrackControl("Controller & Cursor", learnButton)
    ; Its own row in the button column. At x430 it overlapped the "Park after
    ; returning to Steam" checkbox, which spans x300 to x620.
    deleteProfileButton := settings.AddButton("x650 y556 w220 h34",
        "Delete Learned Profile")
    deleteProfileButton.OnEvent("Click", DeleteControllerProfileForActiveDevice)
    SettingsTrackControl("Controller & Cursor", deleteProfileButton)

    ; Steam
    control := settings.AddText("x300 y180 w570 h48 +Wrap",
        "These shortcuts must match the bindings configured inside Steam itself. "
        . "The menu shortcuts only reach Steam while Steam owns the foreground.")
    SettingsTrackControl("Steam", control)
    SettingsAddShortcutAt(settings, "Steam", "Steam.MenuShortcut",
        "Menu", 300, 240, 400)
    SettingsAddShortcutAt(settings, "Steam", "Steam.QuickAccessShortcut",
        "Access", 300, 278, 400)
    SettingsAddShortcutAt(settings, "Steam", "Steam.OverlayShortcut",
        "Overlay", 300, 316, 400)
    viewGroup := settings.AddGroupBox("x290 y356 w595 h214", "View button")
    SettingsTrackControl("Steam", viewGroup)
    control := settings.AddCheckbox("x305 y386 w565 h24",
        "Enable View button Steam actions")
    SettingsRegisterField("Steam", "Steam.EnableViewButtonActions", control, "Click")
    ; Tap and hold are separate switches because they misfire differently: the
    ; hold is the one a game's own use of View can trigger by accident.
    control := settings.AddCheckbox("x325 y416 w545 h24",
        "Tap — Steam menu when Steam is in front, nothing in a game")
    SettingsRegisterField("Steam", "Steam.EnableViewTapAction", control, "Click")
    control := settings.AddCheckbox("x325 y444 w545 h24",
        "Hold — Steam Quick Access, or the overlay in a game")
    SettingsRegisterField("Steam", "Steam.EnableViewHoldAction", control, "Click")
    label := settings.AddText("x325 y478 w250 h24 +0x200", "Hold, Steam in front (ms)")
    SettingsTrackControl("Steam", label)
    edit := settings.AddEdit("x595 y476 w150 h26 Number")
    SettingsRegisterField("Steam", "Steam.ViewHoldMs", edit, "Change")
    label := settings.AddText("x325 y508 w250 h24 +0x200", "Hold, in a game (ms)")
    SettingsTrackControl("Steam", label)
    edit := settings.AddEdit("x595 y506 w150 h26 Number")
    SettingsRegisterField("Steam", "Steam.ViewHoldInGameMs", edit, "Change")
    control := settings.AddText("x325 y538 w545 h24 +Wrap",
        "Longer in a game: View is often the scoreboard button and gets held.")
    SettingsTrackControl("Steam", control)

    ; RTSS & Performance
    control := settings.AddCheckbox("x300 y180 w570 h26", "Enable RTSS integration")
    SettingsRegisterField("RTSS & Performance", "RTSS.EnableIntegration", control, "Click")
    label := settings.AddText("x300 y220 w125 h24 +0x200", "RTSS executable")
    SettingsTrackControl("RTSS & Performance", label)
    pathEdit := settings.AddEdit("x430 y218 w350 h26")
    SettingsRegisterField("RTSS & Performance", "RTSS.Path", pathEdit, "Change")
    browse := settings.AddButton("x790 y217 w90 h28", "Browse...")
    browse.OnEvent("Click", SettingsBrowseRtss)
    SettingsTrackControl("RTSS & Performance", browse)
    control := settings.AddCheckbox("x300 y254 w570 h24",
        "Use RTSSHooks64.dll for live state and direct control (recommended)")
    SettingsRegisterField("RTSS & Performance", "RTSS.UseDllIntegration",
        control, "Click")
    control := settings.AddText("x300 y280 w570 h38 +Wrap",
        "Loaded beside the configured RTSS.exe. Disable this to force the "
        . "shortcut controls and configured FPS cap label.")
    SettingsTrackControl("RTSS & Performance", control)
    overlayGroup := settings.AddGroupBox("x290 y325 w285 h270", "Overlay")
    SettingsTrackControl("RTSS & Performance", overlayGroup)
    label := settings.AddText("x305 y358 w75 h24 +0x200", "Mode")
    SettingsTrackControl("RTSS & Performance", label)
    overlayMode := settings.AddDropDownList(
        "x385 y356 w170 Choose1", ["Separate On / Off", "Toggle"])
    SettingsRegisterField(
        "RTSS & Performance", "RTSS.OverlayControlMode", overlayMode, "Change")
    SettingsAddShortcutAt(settings, "RTSS & Performance",
        "RTSS.OverlayOnShortcut", "On", 305, 400, 250)
    SettingsAddShortcutAt(settings, "RTSS & Performance",
        "RTSS.OverlayOffShortcut", "Off", 305, 446, 250)
    SettingsAddShortcutAt(settings, "RTSS & Performance",
        "RTSS.OverlayToggleShortcut", "Toggle", 305, 492, 250)

    limiterGroup := settings.AddGroupBox("x590 y325 w305 h270", "Frame Limiter")
    SettingsTrackControl("RTSS & Performance", limiterGroup)
    label := settings.AddText("x605 y358 w75 h24 +0x200", "Mode")
    SettingsTrackControl("RTSS & Performance", label)
    limiterMode := settings.AddDropDownList(
        "x685 y356 w190 Choose1", ["Separate On / Off", "Toggle"])
    SettingsRegisterField(
        "RTSS & Performance", "RTSS.FrameLimiterControlMode", limiterMode, "Change")
    label := settings.AddText("x605 y396 w120 h24 +0x200", "Cap label (FPS)")
    SettingsTrackControl("RTSS & Performance", label)
    capEdit := settings.AddEdit("x735 y394 w90 h26 Number")
    SettingsRegisterField("RTSS & Performance", "RTSS.CustomFrameCap", capEdit, "Change")
    SettingsAddShortcutAt(settings, "RTSS & Performance",
        "RTSS.FrameLimiterOnShortcut", "On", 605, 436, 270)
    SettingsAddShortcutAt(settings, "RTSS & Performance",
        "RTSS.FrameLimiterOffShortcut", "Off", 605, 482, 270)
    SettingsAddShortcutAt(settings, "RTSS & Performance",
        "RTSS.CustomFrameCapShortcut", "Toggle", 605, 528, 270)

    ; Startup Splash
    control := settings.AddCheckbox("x300 y182 w570 h26",
        "Show a startup curtain when the companion launches")
    SettingsRegisterField("Startup Splash", "StartupSplash.Enable",
        control, "Click")
    label := settings.AddText("x300 y220 w125 h24 +0x200", "Curtain mode")
    SettingsTrackControl("Startup Splash", label)
    splashModeDrop := settings.AddDropDownList(
        "x430 y218 w150", ["Black", "Video"])
    SettingsRegisterField("Startup Splash", "StartupSplash.Mode",
        splashModeDrop, "Change")
    label := settings.AddText("x300 y258 w125 h24 +0x200", "Startup video")
    SettingsTrackControl("Startup Splash", label)
    videoEdit := settings.AddEdit("x430 y256 w350 h26")
    SettingsRegisterField("Startup Splash", "StartupSplash.VideoPath",
        videoEdit, "Change")
    videoBrowse := settings.AddButton("x790 y255 w90 h28", "Browse...")
    videoBrowse.OnEvent("Click", SettingsBrowseStartupVideo)
    SettingsTrackControl("Startup Splash", videoBrowse)
    label := settings.AddText("x300 y296 w125 h24 +0x200", "MPV executable")
    SettingsTrackControl("Startup Splash", label)
    mpvEdit := settings.AddEdit("x430 y294 w350 h26")
    SettingsRegisterField("Startup Splash", "StartupSplash.MpvPath",
        mpvEdit, "Change")
    mpvBrowse := settings.AddButton("x790 y293 w90 h28", "Browse...")
    mpvBrowse.OnEvent("Click", SettingsBrowseStartupMpv)
    SettingsTrackControl("Startup Splash", mpvBrowse)
    control := settings.AddCheckbox("x300 y334 w270 h24",
        "Mute startup video audio")
    SettingsRegisterField("Startup Splash", "StartupSplash.Mute",
        control, "Click")
    control := settings.AddCheckbox("x590 y334 w280 h24",
        "Play the entire video")
    SettingsRegisterField("Startup Splash", "StartupSplash.PlayFullDuration",
        control, "Click")
    control := settings.AddCheckbox("x300 y366 w570 h24",
        "Force MPV to SDR output to avoid an HDR display-mode switch")
    SettingsRegisterField("Startup Splash", "StartupSplash.ForceSDR",
        control, "Click")
    SettingsAddEditRow(settings, "Startup Splash",
        "StartupSplash.DurationMs", "Black/timed video duration (ms)", 404, true)
    SettingsAddEditRow(settings, "Startup Splash",
        "StartupSplash.SafetyMaxMs", "Full-video safety timeout (ms)", 440, true)
    SettingsAddEditRow(settings, "Startup Splash",
        "StartupSplash.FadeOutMs", "Fade-out duration (ms)", 476, true)
    control := settings.AddText("x300 y522 w570 h58 +Wrap",
        "Video mode requires mpv.exe. Missing video or MPV files fall back to "
        . "the black curtain. Changes take effect on the next companion launch.")
    SettingsTrackControl("Startup Splash", control)

    ; Startup Programs
    control := settings.AddCheckbox("x300 y182 w570 h26",
        "Launch these programs shortly after the companion starts")
    SettingsRegisterField("Startup Programs", "StartupPrograms.Enable", control, "Click")
    StartupProgramsList := settings.AddListBox("x300 y216 w570 h190")
    SettingsTrackControl("Startup Programs", StartupProgramsList)
    addButton := settings.AddButton("x300 y416 w150 h32", "Add Program...")
    addButton.OnEvent("Click", SettingsAddStartupProgram)
    SettingsTrackControl("Startup Programs", addButton)
    removeButton := settings.AddButton("x460 y416 w150 h32", "Remove Selected")
    removeButton.OnEvent("Click", SettingsRemoveStartupProgram)
    SettingsTrackControl("Startup Programs", removeButton)
    SettingsAddEditRow(settings, "Startup Programs", "StartupPrograms.DelayMs",
        "Delay before first launch (ms)", 462, true)
    SettingsAddEditRow(settings, "Startup Programs", "StartupPrograms.StaggerMs",
        "Gap between launches (ms)", 496, true)
    label := settings.AddText("x300 y532 w250 h24 +0x200", "Launch window mode")
    SettingsTrackControl("Startup Programs", label)
    windowModeDrop := settings.AddDropDownList("x570 y530 w150",
        ["Normal", "Minimized", "Hidden"])
    SettingsRegisterField("Startup Programs", "StartupPrograms.WindowMode",
        windowModeDrop, "Change")
    control := settings.AddText("x300 y562 w570 h20",
        "Hidden suits background helpers that should never draw over Xbox FSE.")
    SettingsTrackControl("Startup Programs", control)
    control := settings.AddCheckbox("x300 y588 w570 h22",
        "Start them as the normal user when the companion is elevated")
    SettingsRegisterField("Startup Programs", "StartupPrograms.LaunchDeElevated",
        control, "Click")

    ; Assist
    control := settings.AddText("x300 y180 w570 h32 +Wrap",
        "Optional automatic help, all off by default. None of these ever resize, "
        . "centre or maximise anything — Xbox FSE keeps control of presentation.")
    SettingsTrackControl("Assist", control)
    control := settings.AddCheckbox("x300 y218 w570 h26",
        "Game Focus Lite — return a game to the foreground if something steals it")
    SettingsRegisterField("Assist", "Assist.EnableGameFocusLite", control, "Click")
    control := settings.AddCheckbox("x300 y248 w570 h26",
        "Steam Assist Lite — return to Steam when no game is running")
    SettingsRegisterField("Assist", "Assist.EnableSteamAssistLite", control, "Click")
    control := settings.AddCheckbox("x300 y278 w570 h26",
        "Launcher Cleanup Lite — close game launchers once nothing is playing")
    SettingsRegisterField("Assist", "Assist.EnableLauncherCleanupLite", control, "Click")
    control := settings.AddCheckbox("x300 y308 w570 h26",
        "Pause while the Xbox FSE switcher or another shell overlay is on screen")
    SettingsRegisterField("Assist", "Assist.SuspendOnShellOverlay", control, "Click")
    SettingsAddEditRow(settings, "Assist", "Assist.TickIntervalMs",
        "Check interval (ms)", 344, true)
    SettingsAddEditRow(settings, "Assist", "Assist.CpuThresholdPercent",
        "Game CPU threshold (%, 0 = window shape only)", 378, true)
    SettingsAddEditRow(settings, "Assist", "Assist.ForegroundStableSec",
        "Settle time before cleanup (s)", 412, true)
    SettingsAddEditRow(settings, "Assist", "Assist.CooldownSec",
        "Minimum time between cleanups (s)", 446, true)
    control := settings.AddCheckbox("x300 y480 w570 h26",
        "Force close launchers that ignore a polite close request")
    SettingsRegisterField("Assist", "Assist.HardKill", control, "Click")
    control := settings.AddText("x300 y512 w570 h40 +Wrap",
        "Process lists are edited in the INI under [Assist]. Assistance always "
        . "pauses while any SteamShell XFE window is in front. Use Quick Menu → "
        . "Advanced → Probe Screen to identify an overlay that is not being caught.")
    SettingsTrackControl("Assist", control)

    ; Advanced
    control := settings.AddText("x300 y182 w570 h44 +Wrap",
        "This companion contains no shell registration, Explorer control, taskbar "
        . "hiding, or window sizing. Xbox FSE keeps control of presentation.")
    SettingsTrackControl("Advanced", control)
    openIni := settings.AddButton("x300 y236 w175 h34", "Open INI")
    openIni.OnEvent("Click", (*) => Run(IniPath))
    SettingsTrackControl("Advanced", openIni)
    openLog := settings.AddButton("x490 y236 w175 h34", "Open Log")
    openLog.OnEvent("Click", (*) => Run(LogPath))
    SettingsTrackControl("Advanced", openLog)
    health := settings.AddButton("x680 y236 w175 h34", "Health Check")
    health.OnEvent("Click", ShowHealthCheck)
    SettingsTrackControl("Advanced", health)
    reloadButton := settings.AddButton("x300 y280 w175 h34", "Reload INI")
    reloadButton.OnEvent("Click", ReloadSettings)
    SettingsTrackControl("Advanced", reloadButton)
    parkButton := settings.AddButton("x490 y280 w175 h34", "Park Cursor Now")
    parkButton.OnEvent("Click", ParkCursor)
    SettingsTrackControl("Advanced", parkButton)
    exitButton := settings.AddButton("x680 y280 w175 h34", "Exit Companion")
    exitButton.OnEvent("Click", ExitCompanion)
    SettingsTrackControl("Advanced", exitButton)
    exportButton := settings.AddButton("x300 y324 w175 h34", "Diagnostic ZIP")
    exportButton.OnEvent("Click", ExportDiagnosticBundle)
    SettingsTrackControl("Advanced", exportButton)
    createTaskButton := settings.AddButton("x490 y324 w175 h34", "Create Logon Task")
    createTaskButton.OnEvent("Click", CreateLogonTask)
    SettingsTrackControl("Advanced", createTaskButton)
    removeTaskButton := settings.AddButton("x680 y324 w175 h34", "Remove Logon Task")
    removeTaskButton.OnEvent("Click", RemoveLogonTask)
    SettingsTrackControl("Advanced", removeTaskButton)
    probeButton := settings.AddButton("x300 y368 w175 h34", "Probe Screen")
    probeButton.OnEvent("Click", SettingsProbeScreen)
    SettingsTrackControl("Advanced", probeButton)
    checkTaskButton := settings.AddButton("x490 y368 w175 h34", "Check Logon Task")
    checkTaskButton.OnEvent("Click", SettingsCheckLogonTask)
    SettingsTrackControl("Advanced", checkTaskButton)
    rearmButton := settings.AddButton("x680 y368 w175 h34", "Re-arm Controller")
    rearmButton.OnEvent("Click", RearmControllerInput)
    SettingsTrackControl("Advanced", rearmButton)
    LogonTaskStatusCtrl := settings.AddText("x300 y410 w570 h20 +Wrap", "")
    SettingsTrackControl("Advanced", LogonTaskStatusCtrl)
    control := settings.AddCheckbox("x300 y432 w570 h24",
        "Log all XInput slots and GameInput on every change (diagnostic)")
    SettingsRegisterField("Advanced", "Controller.DiagnosticLogging", control, "Click")
    control := settings.AddCheckbox("x300 y458 w570 h24",
        "Log raw background HID gamepad reports (RawInput probe)")
    SettingsRegisterField("Advanced", "Controller.RawInputProbe", control, "Click")
    control := settings.AddText("x300 y488 w570 h72 +Wrap",
        "The heartbeat log proves whether the companion remains responsive while Xbox FSE is active. "
        . "Diagnostic logging compares every controller slot against GameInput and records the "
        . "foreground process, which reveals a virtualised pad forwarding only some buttons.")
    SettingsTrackControl("Advanced", control)

    settings.AddText("x24 y616 w430 h26 vSettingsStatus", "All changes saved")
    saveButton := settings.AddButton("x620 y610 w135 h34 Default", "Save && Apply")
    saveButton.OnEvent("Click", SaveSettings)
    closeButton := settings.AddButton("x770 y610 w110 h34", "Close")
    closeButton.OnEvent("Click", CloseSettings)
    settings.OnEvent("Close", CloseSettings)
    settings.OnEvent("Escape", CloseSettings)
    SettingsGui := settings
    SettingsVisible := true
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

SettingsTrackControl(category, control) {
    global SettingsCategoryControls
    SettingsCategoryControls[category].Push(control)
}

SettingsRegisterField(category, key, control, eventName := "Change") {
    global SettingsFields
    SettingsFields[key] := control
    SettingsTrackControl(category, control)
    control.OnEvent(eventName, SettingsMarkDirty)
}

SettingsAddEditRow(guiObj, category, key, labelText, y, numeric := false) {
    label := guiObj.AddText("x300 y" y " w250 h24 +0x200", labelText)
    SettingsTrackControl(category, label)
    options := "x570 y" (y - 2) " w150 h26"
    if numeric
        options .= " Number"
    edit := guiObj.AddEdit(options)
    SettingsRegisterField(category, key, edit, "Change")
}

SettingsAddShortcutAt(guiObj, category, key, labelText, x, y, totalWidth) {
    global SettingsFields
    label := guiObj.AddText("x" x " y" y " w55 h24 +0x200", labelText)
    SettingsTrackControl(category, label)
    editX := x + 58
    editWidth := totalWidth - 145
    edit := guiObj.AddEdit("x" editX " y" (y - 2) " w" editWidth " h26")
    SettingsRegisterField(category, key, edit, "Change")
    buttonX := editX + editWidth + 6
    button := guiObj.AddButton("x" buttonX " y" (y - 3) " w78 h28", "Record...")
    button.OnEvent("Click", SettingsRecordShortcut.Bind(key))
    SettingsTrackControl(category, button)
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
        ["Startup Splash",
            "Optional black curtain or MPV startup video on the primary display."],
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
    index := Max(1, Min(categories.Length, index))
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
    for category, controls in SettingsCategoryControls {
        visible := category = meta[1]
        for _, control in controls
            try control.Visible := visible
    }
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
    SetFieldValue("QuickMenu.ChordHoldMs", ReadInt("QuickMenu", "ChordHoldMs", 700, 250, 3000))
    SetFieldValue("Companion.HeartbeatSeconds",
        ReadInt("Companion", "HeartbeatSeconds", 60, 5, 3600))
    SetFieldValue("Audio.EnableQuickControls", ReadBool("Audio", "EnableQuickControls", true))
    SetFieldValue("Display.EnableQuickControls", ReadBool("Display", "EnableQuickControls", true))
    SetFieldValue("Controller.EnableControllerMouseMode",
        ReadBool("Controller", "EnableControllerMouseMode", true))
    SetBackendChoice("Controller.Backend", ReadText("Controller", "Backend", "xinput"))
    SetFieldValue("Controller.DiagnosticLogging",
        ReadBool("Controller", "DiagnosticLogging", false))
    SetFieldValue("Controller.RawInputProbe",
        ReadBool("Controller", "RawInputProbe", false))
    SetFieldValue("StartupPrograms.Enable", ReadBool("StartupPrograms", "Enable", false))
    SetFieldValue("StartupPrograms.DelayMs",
        ReadInt("StartupPrograms", "DelayMs", 4000, 0, 120000))
    SetFieldValue("StartupPrograms.StaggerMs",
        ReadInt("StartupPrograms", "StaggerMs", 1200, 0, 30000))
    SetWindowModeChoice("StartupPrograms.WindowMode",
        ReadText("StartupPrograms", "WindowMode", "Normal"))
    SetFieldValue("StartupPrograms.LaunchDeElevated",
        ReadBool("StartupPrograms", "LaunchDeElevated", true))
    SettingsRefreshStartupProgramsList()
    SettingsRefreshLogonTaskStatus()
    SetFieldValue("StartupSplash.Enable",
        ReadBool("StartupSplash", "Enable", false))
    SetStartupSplashModeChoice(
        "StartupSplash.Mode", ReadText("StartupSplash", "Mode", "Black"))
    SetFieldValue("StartupSplash.VideoPath",
        ReadText("StartupSplash", "VideoPath", ""))
    SetFieldValue("StartupSplash.MpvPath",
        ReadText("StartupSplash", "MpvPath", ""))
    SetFieldValue("StartupSplash.Mute",
        ReadBool("StartupSplash", "Mute", false))
    SetFieldValue("StartupSplash.PlayFullDuration",
        ReadBool("StartupSplash", "PlayFullDuration", true))
    SetFieldValue("StartupSplash.ForceSDR",
        ReadBool("StartupSplash", "ForceSDR", true))
    SetFieldValue("StartupSplash.DurationMs",
        ReadInt("StartupSplash", "DurationMs", 10000, 0, 60000))
    SetFieldValue("StartupSplash.SafetyMaxMs",
        ReadInt("StartupSplash", "SafetyMaxMs", 15000, 1000, 600000))
    SetFieldValue("StartupSplash.FadeOutMs",
        ReadInt("StartupSplash", "FadeOutMs", 300, 0, 5000))
    SetFieldValue("Assist.EnableGameFocusLite",
        ReadBool("Assist", "EnableGameFocusLite", false))
    SetFieldValue("Assist.EnableSteamAssistLite",
        ReadBool("Assist", "EnableSteamAssistLite", false))
    SetFieldValue("Assist.EnableLauncherCleanupLite",
        ReadBool("Assist", "EnableLauncherCleanupLite", false))
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
        ReadInt("Assist", "ForegroundStableSec", 20, 5, 600))
    SetFieldValue("Assist.CooldownSec",
        ReadInt("Assist", "CooldownSec", 300, 30, 7200))
    SetFieldValue("Assist.HardKill", ReadBool("Assist", "HardKill", false))
    SetFieldValue("Controller.ControllerIndex",
        ReadInt("Controller", "ControllerIndex", 0, 0, 3))
    SetFieldValue("Controller.ControllerDeadzone",
        ReadInt("Controller", "ControllerDeadzone", 4000, 1000, 16000))
    SetFieldValue("Controller.ControllerMouseSpeed",
        ReadInt("Controller", "ControllerMouseSpeed", 100, 10, 300))
    SetFieldValue("Controller.ControllerChordHoldMs",
        ReadInt("Controller", "ControllerChordHoldMs", 500, 200, 3000))
    SetFieldValue("Cursor.EnableAutoHide", ReadBool("Cursor", "EnableAutoHide", true))
    SetFieldValue("Cursor.HideDelayMs", ReadInt("Cursor", "HideDelayMs", 1000, 250, 10000))
    SetFieldValue("Cursor.ParkOnStartup", ReadBool("Cursor", "ParkOnStartup", true))
    SetFieldValue("Cursor.ParkOnGameStart", ReadBool("Cursor", "ParkOnGameStart", true))
    SetFieldValue("Cursor.ParkOnSteamReturn", ReadBool("Cursor", "ParkOnSteamReturn", true))
    SetParkEdgeChoice("Cursor.ParkEdge", ReadText("Cursor", "ParkEdge", "right"))
    SetFieldValue("RTSS.EnableIntegration", ReadBool("RTSS", "EnableIntegration", false))
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
    SetFieldValue("RTSS.CustomFrameCap", ReadInt("RTSS", "CustomFrameCap", 0, 0, 1000))
    SetFieldValue("RTSS.FrameLimiterOnShortcut",
        ReadText("RTSS", "FrameLimiterOnShortcut", "^+5"))
    SetFieldValue("RTSS.FrameLimiterOffShortcut",
        ReadText("RTSS", "FrameLimiterOffShortcut", "^+6"))
    SetFieldValue("RTSS.CustomFrameCapShortcut",
        ReadText("RTSS", "CustomFrameCapShortcut", "^+f"))
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

SetStartupSplashModeChoice(key, mode) {
    global SettingsFields
    if SettingsFields.Has(key)
        SettingsFields[key].Choose(
            StrLower(Trim(mode)) = "video" ? 2 : 1)
}

StartupSplashModeChoiceToValue(index) {
    return index = 2 ? "Video" : "Black"
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
        ["QuickMenu", "ChordHoldMs", GetFieldValue("QuickMenu.ChordHoldMs", 700)],
        ["Companion", "HeartbeatSeconds", GetFieldValue("Companion.HeartbeatSeconds", 60)],
        ["Audio", "EnableQuickControls",
            GetFieldValue("Audio.EnableQuickControls") ? "true" : "false"],
        ["Display", "EnableQuickControls",
            GetFieldValue("Display.EnableQuickControls") ? "true" : "false"],
        ["Controller", "EnableControllerMouseMode",
            GetFieldValue("Controller.EnableControllerMouseMode") ? "true" : "false"],
        ["Controller", "Backend",
            BackendChoiceToValue(GetFieldValue("Controller.Backend", 1))],
        ["Controller", "DiagnosticLogging",
            GetFieldValue("Controller.DiagnosticLogging") ? "true" : "false"],
        ["Controller", "RawInputProbe",
            GetFieldValue("Controller.RawInputProbe") ? "true" : "false"],
        ["StartupPrograms", "Enable",
            GetFieldValue("StartupPrograms.Enable") ? "true" : "false"],
        ["StartupPrograms", "DelayMs", GetFieldValue("StartupPrograms.DelayMs", 4000)],
        ["StartupPrograms", "StaggerMs", GetFieldValue("StartupPrograms.StaggerMs", 1200)],
        ["StartupPrograms", "WindowMode",
            WindowModeChoiceToValue(GetFieldValue("StartupPrograms.WindowMode", 1))],
        ["StartupPrograms", "LaunchDeElevated",
            GetFieldValue("StartupPrograms.LaunchDeElevated") ? "true" : "false"],
        ["StartupSplash", "Enable",
            GetFieldValue("StartupSplash.Enable") ? "true" : "false"],
        ["StartupSplash", "Mode",
            StartupSplashModeChoiceToValue(
                GetFieldValue("StartupSplash.Mode", 1))],
        ["StartupSplash", "VideoPath",
            GetFieldValue("StartupSplash.VideoPath")],
        ["StartupSplash", "MpvPath",
            GetFieldValue("StartupSplash.MpvPath")],
        ["StartupSplash", "Mute",
            GetFieldValue("StartupSplash.Mute") ? "true" : "false"],
        ["StartupSplash", "PlayFullDuration",
            GetFieldValue("StartupSplash.PlayFullDuration") ? "true" : "false"],
        ["StartupSplash", "ForceSDR",
            GetFieldValue("StartupSplash.ForceSDR") ? "true" : "false"],
        ["StartupSplash", "DurationMs",
            GetFieldValue("StartupSplash.DurationMs", 10000)],
        ["StartupSplash", "SafetyMaxMs",
            GetFieldValue("StartupSplash.SafetyMaxMs", 15000)],
        ["StartupSplash", "FadeOutMs",
            GetFieldValue("StartupSplash.FadeOutMs", 300)],
        ["Assist", "EnableGameFocusLite",
            GetFieldValue("Assist.EnableGameFocusLite") ? "true" : "false"],
        ["Assist", "EnableSteamAssistLite",
            GetFieldValue("Assist.EnableSteamAssistLite") ? "true" : "false"],
        ["Assist", "EnableLauncherCleanupLite",
            GetFieldValue("Assist.EnableLauncherCleanupLite") ? "true" : "false"],
        ["Assist", "TickIntervalMs", GetFieldValue("Assist.TickIntervalMs", 2000)],
        ["Assist", "CpuThresholdPercent", GetFieldValue("Assist.CpuThresholdPercent", 12)],
        ["Assist", "ForegroundStableSec", GetFieldValue("Assist.ForegroundStableSec", 20)],
        ["Assist", "CooldownSec", GetFieldValue("Assist.CooldownSec", 300)],
        ["Assist", "HardKill", GetFieldValue("Assist.HardKill") ? "true" : "false"],
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
        ["Controller", "ControllerDeadzone", GetFieldValue("Controller.ControllerDeadzone", 4000)],
        ["Controller", "ControllerMouseSpeed", GetFieldValue("Controller.ControllerMouseSpeed", 100)],
        ["Controller", "ControllerChordHoldMs",
            GetFieldValue("Controller.ControllerChordHoldMs", 500)],
        ["Cursor", "EnableAutoHide",
            GetFieldValue("Cursor.EnableAutoHide") ? "true" : "false"],
        ["Cursor", "HideDelayMs", GetFieldValue("Cursor.HideDelayMs", 1000)],
        ["Cursor", "ParkOnStartup",
            GetFieldValue("Cursor.ParkOnStartup") ? "true" : "false"],
        ["Cursor", "ParkOnGameStart",
            GetFieldValue("Cursor.ParkOnGameStart") ? "true" : "false"],
        ["Cursor", "ParkOnSteamReturn",
            GetFieldValue("Cursor.ParkOnSteamReturn") ? "true" : "false"],
        ["Cursor", "ParkEdge",
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
        ["RTSS", "CustomFrameCap", GetFieldValue("RTSS.CustomFrameCap", 0)],
        ["RTSS", "FrameLimiterOnShortcut", GetFieldValue("RTSS.FrameLimiterOnShortcut")],
        ["RTSS", "FrameLimiterOffShortcut", GetFieldValue("RTSS.FrameLimiterOffShortcut")],
        ["RTSS", "CustomFrameCapShortcut", GetFieldValue("RTSS.CustomFrameCapShortcut")]
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

SettingsBrowseStartupVideo(*) {
    global SettingsGui, SettingsDialogActive
    SettingsDialogActive := true
    path := TopmostFileSelect(
        1, , "Select startup video",
        "Video Files (*.mp4; *.mkv; *.webm; *.wmv; *.avi)")
    SettingsDialogActive := false
    if (path != "") {
        SetFieldValue("StartupSplash.VideoPath", path)
        SettingsMarkDirty()
    }
    try WinActivate("ahk_id " SettingsGui.Hwnd)
}

SettingsBrowseStartupMpv(*) {
    global SettingsGui, SettingsDialogActive
    SettingsDialogActive := true
    path := TopmostFileSelect(1, , "Select mpv.exe", "Programs (*.exe)")
    SettingsDialogActive := false
    if (path != "") {
        SetFieldValue("StartupSplash.MpvPath", path)
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
        "These actions run only while View/Back is held. "
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

RefreshMappingList() {
    global MappingList
    if !IsObject(MappingList)
        return
    MappingList.Delete()
    for _, key in ControllerMappingKeys()
        MappingList.Add("", key, ControllerBindingPretty(key))
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

; ==============================================================================
; Shortcut recorder
; ==============================================================================
GetPhysicalModsMap() {
    return Map(
        "Ctrl", GetKeyState("Ctrl", "P") || GetKeyState("LControl", "P")
            || GetKeyState("RControl", "P"),
        "Alt", GetKeyState("Alt", "P") || GetKeyState("LAlt", "P")
            || GetKeyState("RAlt", "P"),
        "Shift", GetKeyState("Shift", "P") || GetKeyState("LShift", "P")
            || GetKeyState("RShift", "P"),
        "Win", GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
    )
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

RecordShortcutCancel(*) {
    global _ShortcutCap
    if !IsObject(_ShortcutCap)
        return
    _ShortcutCap["cancelled"] := true
    try _ShortcutCap["input"].Stop()
    _ShortcutCap["done"] := true
}

NormalizeKeyForSend(keyName) {
    key := keyName
    if (key = "Escape")
        key := "Esc"
    if (key = "Return")
        key := "Enter"
    return StrLen(key) > 1 ? "{" key "}" : key
}

NormalizeKeyForDisplay(keyName) {
    if (keyName = "Escape")
        return "Esc"
    if (keyName = "Return")
        return "Enter"
    return keyName
}

; ==============================================================================
; Diagnostics
; ==============================================================================
; Replaces absolute paths with environment placeholders. A diagnostic bundle is
; meant to be handed to someone else, and the log and INI both contain the full
; profile path.
SanitizeDiagnosticText(text) {
    userProfile := EnvGet("USERPROFILE")
    localAppData := EnvGet("LOCALAPPDATA")
    if (userProfile != "")
        text := StrReplace(text, userProfile, "%USERPROFILE%", false)
    if (localAppData != "")
        text := StrReplace(text, localAppData, "%LOCALAPPDATA%", false)
    text := StrReplace(text, A_ScriptDir, "%XFE_DIR%", false)
    return text
}

GetLastLines(text, maxLines) {
    if (maxLines <= 0)
        return ""
    normalized := StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
    lines := StrSplit(normalized, "`n")
    start := Max(1, lines.Length - maxLines + 1)
    out := ""
    index := start
    while (index <= lines.Length) {
        out .= lines[index] "`r`n"
        index += 1
    }
    return out
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

ShowHealthCheck(*) {
    global AppVersion, IniPath, LogPath, ControllerIndex, ActiveControllerIndex, RtssPath
    global EnableRTSSIntegration, RtssUseDllIntegration
    global ControllerBackend, ActiveInputBackend
    global GameInputReady, GameInputFailed
    global RawInputProbeActive, RawInputLastReportTick
    controller := Buffer(16, 0)
    controllerText := ControllerReadState(&controller)
        ? (ActiveInputBackend = "rawinput"
            ? "PASS — controller reading through RawInput (works inside Xbox FSE)"
            : (ActiveInputBackend = "gameinput"
                ? "PASS — controller reading through GameInput"
                : "PASS — controller detected at XInput slot " ActiveControllerIndex))
        : "WARN — no controller detected on any backend"
    backendText := "INFO — backend setting: " ControllerBackend
        . ", active: " ActiveInputBackend
    rawInputText := !RawInputProbeActive
        ? "INFO — RawInput not registered"
        : (RawInputLastReportTick
            ? "PASS — RawInput registered and receiving HID reports"
            : "INFO — RawInput registered, no reports yet (expected outside Xbox FSE)")
    gameInputText := GameInputReady
        ? "PASS — GameInput initialised"
        : (GameInputFailed
            ? "WARN — GameInput unavailable; fallback in use"
            : "INFO — GameInput not requested")
    if !EnableRTSSIntegration {
        rtssText := "INFO — RTSS integration disabled"
    } else if !FileExist(NormalizePath(RtssPath)) {
        rtssText := "WARN — RTSS executable not found"
    } else if !ProcessExist("RTSS.exe") {
        rtssText := "INFO — RTSS installed but not running"
    } else if !RtssUseDllIntegration {
        rtssText := "INFO — RTSS running; DLL integration disabled, shortcut mode active"
    } else {
        rtssState := GetRtssGlobalState()
        rtssText := IsObject(rtssState)
            ? "PASS — RTSS state readable; overlay "
                . (rtssState["overlay"] ? "on" : "off") ", limiter "
                . (rtssState["limiter"] ? "on" : "off")
            : "WARN — RTSS running but global state is unavailable; shortcut fallback active"
    }
    displayScale := GetPrimaryDisplayScale()
    displayScaleText := IsObject(displayScale)
        ? "PASS — primary display scale " displayScale["percent"] "%"
        : "WARN — primary display scale control unavailable"
    hdr := GetPrimaryHdrState()
    hdrStateText := !IsObject(hdr)
        ? "WARN — primary display HDR state unavailable"
        : (!hdr["supported"]
            ? "INFO — primary display does not support HDR"
            : "PASS — primary display HDR " (hdr["enabled"] ? "on" : "off"))
    anyFseText := ProcessExist("AnyFSE.exe")
        ? "PASS — AnyFSE process detected"
        : "INFO — AnyFSE process not detected"
    lines := [
        "SteamShell XFE Companion " AppVersion,
        "",
        FileExist(IniPath) ? "PASS — settings file available" : "FAIL — settings file missing",
        controllerText,
        backendText,
        rawInputText,
        gameInputText,
        rtssText,
        displayScaleText,
        hdrStateText,
        anyFseText,
        ProcessExist("steam.exe") ? "PASS — Steam process detected" : "INFO — Steam not running",
        "",
        "Architecture: " (A_PtrSize = 8 ? "64-bit" : "32-bit"),
        "Administrator: " (A_IsAdmin ? "Yes" : "No (recommended)"),
        "Log: " LogPath,
        "",
        "The companion does not modify Winlogon Shell or manage Explorer/taskbar."
    ]
    message := ""
    for _, line in lines
        message .= line "`r`n"
    health := Gui("+AlwaysOnTop +ToolWindow", "SteamShell XFE Health Check")
    health.SetFont("s10", "Segoe UI")
    health.AddEdit("xm ym w650 h360 ReadOnly -Wrap", message)
    close := health.AddButton("xm y+10 w120 h32 Default", "Close")
    close.OnEvent("Click", (*) => health.Destroy())
    exportButton := health.AddButton("x+8 yp w190 h32", "Export Diagnostic ZIP")
    exportButton.OnEvent("Click", ExportDiagnosticBundle)
    health.OnEvent("Escape", (*) => health.Destroy())
    health.Show("AutoSize Center")
    SetStatus("Health check completed")
}

; ==============================================================================
; Controller poll loop
; ==============================================================================
ResetControllerHoldState(downTick, longFired, triggerDown, buttonDefinitions) {
    for definition in buttonDefinitions {
        name := definition[1]
        downTick[name] := 0
        longFired[name] := false
    }
    downTick["LT"] := 0
    downTick["RT"] := 0
    longFired["LT"] := false
    longFired["RT"] := false
    triggerDown["LT"] := false
    triggerDown["RT"] := false
}

PollController() {
    global EnableControllerMouseMode, ControllerIndex, ControllerDeadzone
    global ActiveControllerIndex, ActiveInputBackend
    global ControllerMouseSpeed, ControllerMouseFastMultiplier
    global ControllerScrollIntervalMs, ControllerScrollStep, ControllerChordHoldMs
    global QuickMenuVisible, EnableQuickMenu, QuickMenuChordHoldMs
    global SettingsVisible, SettingsDialogActive, LearnActive
    global CompanionDisabled, ControllerNeedsFreshBaseline

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
            ResetControllerHoldState(downTick, longFired, triggerDown,
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
            ResetControllerHoldState(downTick, longFired, triggerDown, buttonDefinitions)
            return
        }

        if !ControllerReadState(&state) {
            previousButtons := 0
            previousViewDown := false
            viewWasDown := false
            quickChordSince := 0
            quickChordFired := false
            ResetControllerHoldState(downTick, longFired, triggerDown, buttonDefinitions)
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
        if (pressed || released
            || currentDiagnosticLtDown != diagnosticLtDown
            || currentDiagnosticRtDown != diagnosticRtDown) {
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

        ; Settings owns right-stick pointer and RB click without requiring Back.
        if SettingsVisible {
            if (rx != 0 || ry != 0) {
                dx := Round((rx / 32767.0) * ControllerMouseSpeed)
                dy := Round((-ry / 32767.0) * ControllerMouseSpeed)
                if (dx != 0 || dy != 0)
                    try MouseMove(dx, dy, 0, "R")
            }
            if (ly != 0 && now - lastScroll >= ControllerScrollIntervalMs) {
                lastScroll := now
                try Send(ly > 0 ? "{WheelUp}" : "{WheelDown}")
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
            if !SettingsDialogActive {
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
            }
            previousViewDown := false
            viewWasDown := false
            ResetControllerHoldState(downTick, longFired, triggerDown, buttonDefinitions)
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
            ResetControllerHoldState(downTick, longFired, triggerDown, buttonDefinitions)
            return
        }

        if !viewDown {
            previousViewDown := false
            viewWasDown := false
            ResetControllerHoldState(downTick, longFired, triggerDown, buttonDefinitions)
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

        if (rx != 0 || ry != 0) {
            speed := rt > 30
                ? Round(ControllerMouseSpeed * ControllerMouseFastMultiplier)
                : ControllerMouseSpeed
            dx := Round((rx / 32767.0) * speed)
            dy := Round((-ry / 32767.0) * speed)
            if (dx != 0 || dy != 0)
                try MouseMove(dx, dy, 0, "R")
        }
        if (ly != 0 && now - lastScroll >= ControllerScrollIntervalMs) {
            lastScroll := now
            Loop ControllerScrollStep
                try Send(ly > 0 ? "{WheelUp}" : "{WheelDown}")
        }

        for definition in buttonDefinitions {
            name := definition[1]
            mask := definition[2]
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
EnsureSettingsFile()
LoadSettings()
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
LogLine("Started SteamShell XFE Companion " AppVersion
    . " (PID " ScriptPid ", " (A_IsAdmin ? "administrator" : "standard user") ").")
if EnableStartupSplash
    StartStartupSplash()
if ParkOnStartup
    SetTimer(ParkCursor, -1000)
if EnableStartupPrograms
    SetTimer(RunStartupPrograms, -StartupProgramDelayMs)

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
