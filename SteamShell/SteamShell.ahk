; ==============================================================================
; SteamShell — BPM Kiosk Shell (AutoHotkey v2.0.19 compatible)
; ------------------------------------------------------------------------------
; Hotkeys:
; Ctrl+Alt+Shift+E => Exit to desktop (permanent restore)
; Ctrl+Alt+Shift+R => Reload INI settings
; Ctrl+Alt+Shift+G => Run Game Assist immediately (one-shot)
; Ctrl+Alt+Shift+P => Open Control Panel (session toggles / diagnostics)
; Ctrl+Alt+Shift+Q => Open the controller-first Quick Menu
; Ctrl+Alt+Shift+S => Open persistent Settings editor
; ==============================================================================
#Requires AutoHotkey v2.0.19 64-bit
#SingleInstance Force
global SteamShellVersion := "1.7.2"
; Declared `global` like every other script-scope variable here. Without it
; these are ordinary globals rather than super-globals, so a function that
; reads them without its own `global` declaration would silently get an empty
; local instead. Both current consumers do declare them; this removes the trap.
global DEFAULT_AUDIO_PEAK_THRESHOLD := 0.02  ; Default audio peak threshold (0.0–1.0). Can be overridden in INI.
global AudioPeakThreshold := DEFAULT_AUDIO_PEAK_THRESHOLD
SetTitleMatchMode 2
Persistent

; Prefer Input mode for synthetic keystrokes (more reliable for system chords)
SendMode "Input"
; Every cursor position in SteamShell is a desktop/screen coordinate. AutoHotkey
; otherwise defaults MouseGetPos to the active window's client area, which can
; make an unchanged pointer look as if it moved when the Quick Menu is repositioned.
CoordMode "Mouse", "Screen"


; ==============================================================================
; FILE PATHS
; ==============================================================================
global SettingsPath := A_ScriptDir "\SteamShellSettings.ini"
; Back-compat alias used by some helper functions
global IniPath := SettingsPath
global CurrentSettingsSchemaVersion := 12
global LogPath := A_ScriptDir "\SteamShell.log"
global ShellRegKey := "HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
global SteamShellRegKey := "HKEY_CURRENT_USER\Software\SteamShell"
global SteamShellLocalAppData := EnvGet("LOCALAPPDATA")
if (SteamShellLocalAppData = "")
 SteamShellLocalAppData := A_AppData
global SteamShellInstallDir := SteamShellLocalAppData "\SteamShell"
global SteamShellInstalledExe := SteamShellInstallDir "\SteamShell.exe"
global IntentionalExitMode := ""
global SafeMode := false
global SessionState := "STARTING"

; Cache our own PID once so window-management can reliably ignore this script's GUIs.
global ScriptPid := DllCall("GetCurrentProcessId", "UInt")
global LastRealFgHwnd := 0 ; last foreground window not owned by this script

; ==============================================================================
; DEFAULT SETTINGS (INI overrides these)
; ==============================================================================
global SteamPath := "C:\Program Files (x86)\Steam\Steam.exe"
global BpmTitle := "Steam Big Picture Mode"

; Feature toggles
global RunElevatedOnStartup := true
global EnableSplashScreen := true
global EnableTaskbarHiding := true
global EnableDesktopBlackout := true
global EnableWindowManagement := true
global EnableAutoHideCursor := true
global EnableSteamRefocusMode := true
global EnableGameForegroundAssist := true
global EnableAlwaysFocus := true
global EnableMouseParkOnBoot := true
global EnableMouseParkOnFocusChange := true
global EnableCursorHideOnBoot := true
global EnableCursorHideOnRefocus := true


; Controller-to-mouse (XInput / Xbox controller)
global EnableControllerMouseMode := true ; Enable controller mouse/keyboard mapping
global ControllerIndex := 0 ; 0 = first controller
global ControllerPollIntervalMs := 16 ; Poll rate (ms)
global ControllerDeadzone := 4000 ; Stick deadzone (0-32767)
global ControllerMouseSpeed := 100 ; Pixels per poll tick at full deflection
global ControllerMouseFastMultiplier:= 2.5 ; Multiplier when RT is held (fast move)
global ControllerScrollIntervalMs := 80 ; Min ms between scroll ticks
global ControllerScrollStep := 1 ; Wheel notches per scroll tick
global ControllerChordHoldMs := 500 ; Long-press threshold (ms) for View/Back + button secondary actions

; Controller mapping configuration (short/long press while holding View/Back)
global ControllerMap := Map() ; key => mapping string ("Builtin:..." or "Send:...")
global ControllerMapDisplay := Map() ; key => pretty display for Send: mappings
InitDefaultControllerMappings()

; SteamShell quick menu / notifications
global EnableQuickMenu := true
global QuickMenuChordHoldMs := 700
global TaskForceCloseHoldMs := 1200
global QuickMenuMainOrderRaw := "Audio|Display|RTSS|SteamMenu|SteamQuickAccess|Layout|Tasks|GameBar|Settings|System"
global QuickMenuHiddenItemsRaw := ""
global QuickMenuMainOrder := []
global QuickMenuHiddenItems := Map()
global QuickMenuLayoutGui := unset
global QuickMenuGui := unset
global QuickMenuRows := []
global QuickMenuSelected := 1
global QuickMenuVisible := false
global QuickMenuPreviousHwnd := 0
global QuickMenuPage := "MAIN"
global QuickMenuConfirmAction := ""
global QuickMenuConfirmUntilTick := 0
global FocusAssistancePaused := false
global QuickMenuDisplayModes := []
global QuickMenuAudioDevices := []
global QuickMenuTaskWindows := []
global QuickMenuTaskPage := 1
global QuickMenuTitleCtrl := 0
global QuickMenuSubtitleCtrl := 0
global QuickMenuFooterCtrl := 0
; Transient status shown in the Quick Menu footer in place of the button hint.
;
; ShowNotification is log-only by design -- the old bottom-corner overlay was
; distracting over the menu and was removed. But that left 50-odd warnings
; ("RTSS did not accept the frame cap", "Windows volume control is unavailable")
; visible only to someone who opens the log, which on a couch device is nobody.
; The footer is already on screen and already transient, so it costs no new
; surface. Matches XFE's SetStatus.
global LastStatusText := ""
global LastStatusLevel := ""
global LastStatusTick := 0
global StatusVisibleMs := 4000
global QuickMenuLabelCtrls := []
global QuickMenuValueCtrls := []
global SteamMenuShortcut := "^1"
global SteamQuickAccessShortcut := "^2"
global SteamOverlayShortcut := "+{Tab}"
global QM_BG := "171A21"
global QM_ROW_SELECTED := "222C3A"
global QM_ACCENT := "66C0F4"
global QM_LABEL := "C6CCD8"
global QM_LABEL_SELECTED := "FFFFFF"
global QM_VALUE := "7E8899"
global PinnedForegroundHwnd := 0
global PinnedForegroundTitle := ""
global PinnedForegroundExe := ""
global DisplayPendingOldMode := 0
global DisplayPendingOldScale := 0
global DisplayPendingUntilTick := 0
global DisplaySelectedWidth := 0
global DisplaySelectedHeight := 0
global DisplaySelectedFrequency := 0
global DisplaySelectedScalePercent := 0

; Persistent settings editor
global SettingsGui := unset
global SettingsEditorFields := []
global SettingsEditorCategoryControls := Map()
global SettingsEditorControlPositions := Map()
global SettingsEditorCategoryOffsets := Map()
global SettingsEditorCategories := []
global SettingsEditorDirty := false
global SettingsEditorUpdating := false
global SettingsEditorStatusCtrl := 0
global SettingsEditorContentTop := 145
global SettingsEditorContentBottom := 555
global SettingsEditorWindowHeight := 620
global SettingsEditorScrollBar := 0
global SettingsEditorFooterControls := []
global SettingsEditorDividerCtrl := 0
global SettingsEditorDialogActive := false
global SettingsStartupListView := 0
global SettingsStartupCommandEdit := 0
global SettingsStartupSelectedSlot := 1
global HealthCheckGui := unset
global HealthCheckResults := []
global SetupAssistantGui := unset

; Optional living-room integrations exposed by the quick menu
global EnableAudioQuickControls := true
global EnableDisplayQuickControls := true
global EnableRTSSIntegration := false
global RtssPath := "C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe"
global RtssUseDllIntegration := true
global RtssOverlayControlMode := "toggle"
global RtssOverlayToggleShortcut := "^+o"
global RtssOverlayOnShortcut := "^+1"
global RtssOverlayOffShortcut := "^+2"
global RtssFrameLimiterControlMode := "toggle"
global RtssCustomFrameCap := 0
global RtssCustomFrameCapShortcut := "^+f"
global RtssFrameLimiterOnShortcut := "^+5"
global RtssFrameLimiterOffShortcut := "^+6"
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
; Repaint cache for the global FramerateLimit read. GetRtssFrameCapState runs
; once per row per repaint and each miss costs a LoadProfile plus a
; GetProfileProperty round trip; the Quick Menu repaints on every keypress.
; Mirrors the reasoning behind IsSteamRunning's cache. Zeroed after any write
; so the row never shows a value it just replaced.
global RtssFrameLimitCacheFps := 0
global RtssFrameLimitCacheTick := 0
; Value the user is currently dialling in, before it reaches RTSS. 0 = nothing
; pending. See AdjustRtssCustomFrameCap.
global RtssPendingFrameCap := 0
; Launcher cleanup (optional)
global EnableLauncherCleanup := false ; Close selected launchers/services after Steam is foreground for N seconds
global LauncherCleanupSteamForegroundSec := 30 ; Required seconds Steam stays foreground before cleanup runs
global LauncherCleanupRequireNoGame := true ; Skip cleanup if a game-like fullscreen/borderless window is detected
global LauncherCleanupCooldownSec := 300 ; Minimum seconds between cleanup runs
global LauncherCleanupCheckIntervalMs := 2000 ; Timer interval for checking conditions
global LauncherCleanupGracefulCloseMs := 4000 ; Wait after WinClose before hard-killing
global LauncherCleanupHardKill := false ; If true, hard-kill any remaining launcher/service processes after GracefulCloseMs
global LauncherCleanupUseCpuAudio := true ; Use CPU/audio heuristics (more reliable than window size alone)
global LauncherCleanupCpuThreshold := 12 ; CPU % threshold to consider "game running" (0 disables CPU check)
global LauncherCleanupAudioPeakThreshold := 0.02 ; Audio peak threshold for Launcher Cleanup (0.0–1.0)
global LauncherCleanupDownloadGuard := false ; If true, skip cleanup while launchers appear busy (possible download/update)
global LauncherCleanupDownloadGuardMode := "Balanced" ; Off|Balanced|Strict (controls internal thresholds)

; Pipe-separated EXE lists (editable in INI)
global LauncherCleanupLauncherExeListRaw := "UbisoftConnect.exe|upc.exe|EpicGamesLauncher.exe|EADesktop.exe|EALauncher.exe|Origin.exe|Battle.net.exe|RockstarGamesLauncher.exe|GalaxyClient.exe|RiotClientServices.exe|RiotClientUx.exe|Heroic.exe"
global LauncherCleanupBackgroundExeListRaw := "UbisoftConnectService.exe|UplayWebCore.exe|UplayService.exe|EpicWebHelper.exe|EABackgroundService.exe|BlizzardUpdateAgent.exe|RockstarService.exe|SocialClubHelper.exe|GalaxyClientService.exe|GalaxyCommunication.exe|RiotClientUxRender.exe|legendary.exe|gogdl.exe|nile.exe"
global LauncherCleanupExcludeExeListRaw := "steam.exe|steamwebhelper.exe|SteamShell.exe"

; Parsed lists/sets
global LauncherCleanupLauncherList := []
global LauncherCleanupBackgroundList := []
global LauncherCleanupExcludeSet := Map()

; Launcher Cleanup — UI status (Control Panel)
; These are updated by CheckLauncherCleanup() so the Control Panel can explain
; why launchers are still running (cooldown, Steam not foreground, game detected, busy guard, etc.).
global LC_SteamFgSinceTick := 0
global LC_LastCleanupTick := 0
global LC_LastDecisionStamp := ""
global LC_LastDecisionText := "-"
global LC_FoundText := "-"          ; Launchers/helpers currently detected (by EXE list)
global LC_GateText := "-"           ; Current gating/why cleanup isn't running
global LC_ConfigText := "-"         ; One-line config summary (enabled/guard/hardkill)


global LC_LastGateCat := ""        ; Internal: last gate category recorded for LC Last
; Timings (ms)
global SplashScreenDuration := 10000

; Splash mode options
global SplashMode := "Black" ; "Black" or "Video"
global SplashVideoPath := "" ; Full path to video file (mp4/wmv)
global SplashVideoMute := true
global SplashVideoPlayFull := false ; If true, play full video duration (uses a monitor; still has a safety timeout)
global SplashVideoSafetyMaxMs := 60000 ; Safety timeout when PlayFull is enabled
global SplashFadeOutMs := 300 ; Fade-out duration in ms (0 = no fade)
global SplashTopmostGuardMs := 500 ; Re-assert topmost while splash is visible (0 disables)

global SplashDebugOverlay := false
global SplashForceSDR := true ; If true, forces MPV output to SDR to avoid HDR/DV mode switching ; If true, show why video fell back to black
global SplashMpvPath := "" ; Full path to mpv.exe (optional)
global SplashMpvPid := 0
global SplashMpvHwnd := 0
global SplashFailReason := ""
global SplashClosing := false


global SplashOverlayGui := unset

global MouseMonitorInterval := 250
global MouseHideDelay := 1000
global SteamRefocusDelay := 3000

; Coordinated window engine
global WindowEngineTickIntervalMs := 500
global WindowEngineFocusIntervalMs := 1000
global WindowEngineGeometryRetryMs := 1000
global WindowEngineGeometryMaxAttempts := 3
global WindowEngineCpuSampleIntervalMs := 1000
global ShellMonitorIntervalMs := 500
global WindowEngineSnapshot := []
global WindowEngineSnapshotByHwnd := Map()
global WindowEngineSnapshotBusy := false
global WindowEngineGeometryState := Map()
global WindowEngineCpuSamples := Map()
global WindowEngineLastSnapshotTick := 0
global WindowEngineLastFocusTick := 0
global WindowEngineLastDecision := "Starting"
global WindowEngineLastTickDurationMs := 0
global WindowEngineLastWindowCount := 0
global WindowEngineGeometryActions := 0
global WindowEngineFocusActions := 0

; Event-driven taskbar guard with a low-frequency safety check.
global TaskbarGuardActive := false
global TaskbarGuardHook := 0
global TaskbarGuardCallback := 0
global TaskbarGuardSafetyIntervalMs := 1000

; Desktop blackout. A bottom-most black window supplies the pixels while the
; Explorer desktop windows are hidden, so neither the wallpaper nor desktop
; icons show through in the gaps around Steam. Deliberately owns no system or
; registry state: everything it changes dies with the process or is undone by
; the Explorer restart that unexpected-exit recovery already performs.
global DesktopBlackoutActive := false
global DesktopBlackoutHook := 0
global DesktopBlackoutCallback := 0
global DesktopBackdropGui := unset
global DesktopBackdropHwnd := 0
global DesktopBackdropRect := ""

; Window management
global MinWidthPercent := 0.20
; Fraction of the screen a CAPTIONLESS window must cover in both dimensions
; before the engine treats it as an application window rather than a popup.
; Captioned windows ignore this: a small dialog has a title bar and is worth
; centring. Not an INI key -- it separates two categories rather than expressing
; a preference, and the settings schema would need a version bump to add it.
global MinCenterCoverage := 0.40

; Window management exclusion lists (INI-driven)
global WmExcludeExeListRaw := "" ; Pipe-separated EXEs to skip in auto center/max
global WmExcludeClassListRaw := "" ; Pipe-separated Win32 classes to skip in auto center/max
global WmExcludeExeSet := Map() ; Built from WmExcludeExeListRaw
global WmExcludeClassSet := Map() ; Built from WmExcludeClassListRaw

; Automatic mouse mode. While one of these executables owns the foreground, the
; View/Back mappings apply without holding View/Back -- the same mappings, not a
; second set, so there is nothing extra to learn or configure. Empty by default:
; naming an executable is the whole opt-in.
;
; EnableAutoMouseMode is a separate kill switch so the behaviour can be turned
; off for a session without discarding a curated list -- the list is the thing
; that took effort to build, and "is this feature causing what I am seeing?" is
; a question worth being able to answer without destroying it.
global EnableAutoMouseMode := true
global AutoMouseExeListRaw := ""
global AutoMouseExeSet := Map()

; AlwaysFocus list
global AlwaysFocusExeListRaw := "" ; Example: SplitSecond.exe|EADesktop.exe
global AlwaysFocusCooldownMs := 1000

; Game assist
global GameCPUThresholdPercent := 5.0
global FullscreenTolerance := 0.98
global FullscreenPosTolerancePx := 2
global GameForegroundCooldownMs := 1500
global GameAllowZeroCpuAsCandidate := true
global GameRequireSteamForeground := true
global GameAssistLogEvenWhenSkipped := false

; Scoring
global ScoreFullscreen := 70
global ScoreBorderlessLarge := 45
global ScoreTitleBonus := 10
global ScoreCpuAboveThreshold := 20
global ScoreCpuNonZeroBonus := 15
global GameMinScoreToActivate := 55

; Audio assist
global EnableAudioAssist := true
global ScoreAudioActive := 30

; Event-based mouse parking
global MouseParkRightOffsetPx := 50
global MouseParkYPercent := 0.50
global MouseParkEdge := "right"
global MouseParkFocusSettleMs := 500
global MouseParkVerifyDelayMs := 250

; Logging
global EnableGameScoreLogging := false
global GameLogMode := "OFF" ; OFF | ACTIVATIONS | TOPN | DIAGNOSTIC
global GameLogTopN := 3
global GameLogIntervalMs := 3000
global GameLogIncludeTitles := true
global GameLogRejectNearCandidates := true
global GameLogRejectMinAreaPercent := 0.85
global GameLogRotateMaxKB := 256
global GameLogRotateBackups := 2

; ==============================================================================
; INTERNAL STATE
; ==============================================================================
global ConfiguredShellValue := "explorer.exe"
global AllowExplorer := false
global SystemReady := false
; Desktop mode: Explorer owns the visible desktop again, but SteamShell stays
; resident so the notification-area icon, controller mouse, and Quick Menu keep
; working. Distinct from Safe Mode, which never enforced the shell at all.
global DesktopMode := false
global TaskbarCreatedMessage := 0
global SteamLaunched := false
global SteamLaunchAttemptTick := 0
global SteamObservedRunning := false
global SteamMissingSinceTick := 0
global SteamStartupGraceMs := 120000
global SteamExitConfirmMs := 8000
global SteamLaunchFailedReason := ""
; Latches the one-shot startup warning. Global rather than static inside
; MonitorShell so every fresh launch attempt -- including Retry from the
; recovery screen -- can clear it and earn a new warning.
global SteamStartupWarningLogged := false
; Fraction of its monitor a Steam window must cover before startup counts it as
; Big Picture. See SteamBpmSurfacePresent for why coverage, and not the window
; title, is the signal.
global SteamStartupSurfaceMinCoverage := 0.6
global StartupRecoveryGui := unset
; Desktop-restore failure dialog. Kept controller-navigable for the same reason
; the startup recovery screen is: it appears when Explorer may be dead, so there
; is no taskbar and no other application to reach for.
global DesktopRecoveryGui := unset
global DesktopRecoveryChoice := ""

global SplashGui := unset

global LastMouseX := 0
global LastMouseY := 0
global MouseHidden := false
global LastMouseMoveTick := 0
global MouseParkPendingHwnd := 0
global MouseParkExpectedX := 0
global MouseParkExpectedY := 0
global MouseParkScheduledInputTick := -1
global MouseParkObservedForegroundHwnd := 0
global MouseParkSawNonSteamForeground := false
global MouseParkLastResult := "Not run"

global SteamRefocusTimer := 0
global AlwaysFocusList := []
global LastAlwaysFocusTick := 0
global LastGameBringToFrontTick := 0
global _LastGameLogTick := 0

; Control Panel / timed disable / live log
global ControlGui := unset
global LiveLogGui := unset
global AlwaysFocusGui := unset
global TempDisables := Map() ; key -> Map("prev", bool, "until", tick)
global LiveLogSaved := Map() ; original logging settings when live logging enabled
global HandsOffUntilTick := 0 ; if > now: pause focus behaviors
global LastActionText := "Idle"
global LastBestCandidateText := "-"
global LastBestCandidateScore := -1
global LastBestCandidateProc := ""
global LastBestCandidateTitle := ""

; Status text control handles (avoid name-lookup edge cases)
;
; Rows 5-8 were added later and only ever declared inside the functions that
; use them, which made them ordinary globals while 1-4 were super-globals. The
; writes are inside `try` and the reads are guarded on CPStat1Ctrl alone, so an
; undeclared one would not have crashed -- it would have silently stopped
; updating. Declared here so all eight behave identically.
global CPStat1Ctrl := unset, CPStat2Ctrl := unset, CPStat3Ctrl := unset, CPStat4Ctrl := unset
global CPStat5Ctrl := unset, CPStat6Ctrl := unset, CPStat7Ctrl := unset, CPStat8Ctrl := unset
global LLStat1Ctrl := unset, LLStat2Ctrl := unset, LLStat3Ctrl := unset, LLStat4Ctrl := unset
global LLStat5Ctrl := unset, LLStat6Ctrl := unset, LLStat7Ctrl := unset, LLStat8Ctrl := unset
global CPCtlSpeedSliderCtrl := unset, CPCtlSpeedTextCtrl := unset

; Controller mapping editor handles, and the shortcut-capture state used by
; RecordShortcutChord. Same reasoning as the status handles above: they were
; created lazily by whichever function ran first.
global ControllerMapGui := unset
global g_ControllerMapUI := unset
global _ShortcutCap := ""

; tail viewer state
global PanelLogMaxLines := 200
global DetachedLogMaxLines := 300


; controller mouse mode state (XInput)
global XInputDll := ""
global ControllerDragLock := false
global ControllerTestGui := unset
global ControllerCalibrationUntil := 0
global ControllerCalibrationMax := 0
global ControllerSuggestedDeadzone := 0

QuoteWindowsCommandLineArg(value) {
 ; Follow Windows' command-line quoting rules so relaunch arguments survive
 ; spaces, embedded quotes, and trailing backslashes.
 value := value ""
 if (value = "")
     return '""'
 if !RegExMatch(value, '[\s"]')
     return value

 quoted := '"'
 backslashes := 0
 Loop Parse value {
     ch := A_LoopField
     if (ch = "\") {
         backslashes += 1
         continue
     }
     if (ch = '"') {
         quoted .= StrRepeat("\", (backslashes * 2) + 1) '"'
         backslashes := 0
         continue
     }
     if (backslashes > 0) {
         quoted .= StrRepeat("\", backslashes)
         backslashes := 0
     }
     quoted .= ch
 }
 if (backslashes > 0)
     quoted .= StrRepeat("\", backslashes * 2)
 return quoted '"'
}

BuildSteamShellElevationCommand() {
 commandLine := QuoteWindowsCommandLineArg(
     A_IsCompiled ? A_ScriptFullPath : A_AhkPath)
 commandLine .= " /restart"
 if !A_IsCompiled
     commandLine .= " " QuoteWindowsCommandLineArg(A_ScriptFullPath)
 for _, argument in A_Args
     commandLine .= " " QuoteWindowsCommandLineArg(argument)
 return commandLine
}

SteamShellElevationRestartRequested() {
 ; /restart is an AutoHotkey built-in switch and therefore is not included in
 ; A_Args. Inspect the original command line to prevent a RunAs loop on systems
 ; which accept the verb but do not produce an elevated token.
 fullCommandLine := DllCall("GetCommandLine", "Str")
 return RegExMatch(
     fullCommandLine, "i)(?:^|\s)/restart(?:\s|$)") != 0
}

EnsureSteamShellElevation() {
 global SessionState, RunElevatedOnStartup
 RunElevatedOnStartup := ReadSteamShellElevationPreference()
 if !RunElevatedOnStartup {
     if A_IsAdmin {
         try LogLine(
             "Administrator startup is disabled, but this process was already "
             . "launched elevated; its token cannot be lowered in place.")
     } else {
         SessionState := "DEGRADED"
         try LogLine(
             "Administrator startup is disabled in Settings; continuing "
             . "without access to elevated application windows.")
     }
     return A_IsAdmin
 }
 if A_IsAdmin
     return true

 if SteamShellElevationRestartRequested() {
     SessionState := "DEGRADED"
     try LogLine(
         "Administrator relaunch completed without an elevated token; "
         . "continuing with limited access to elevated windows.")
     return false
 }

 try {
     commandLine := BuildSteamShellElevationCommand()
     ; On success, AutoHotkey's /restart switch makes the replacement terminate
     ; this instance before RunWait returns. If the replacement fails or exits
     ; before taking over, RunWait returns and this instance safely continues.
     RunWait("*RunAs " commandLine, A_ScriptDir)
     SessionState := "DEGRADED"
     try LogLine(
         "The administrator replacement exited before taking over; "
         . "continuing without administrator rights.")
     return false
 } catch as err {
     ; Never strand the user without a shell if elevation is cancelled or
     ; unavailable. Continue with known limitations and surface them in Health.
     SessionState := "DEGRADED"
     try LogLine(
         "Elevation was unavailable; continuing without administrator rights: "
         . err.Message)
     return false
 }
}

ReadSteamShellElevationPreference() {
 global SettingsPath
 if !FileExist(SettingsPath)
     return true
 rawValue := "true"
 try rawValue := IniRead(
     SettingsPath, "Features", "RunElevatedOnStartup", "true")
 catch
     return true
 return ToBool(CleanIniValue(rawValue, "true"), true)
}

; ==============================================================================
; ADMIN + CAPTURE CURRENT SHELL
; ==============================================================================
try {
 ConfiguredShellValue := RegRead(ShellRegKey, "Shell")
} catch {
 ConfiguredShellValue := "explorer.exe"
}
if (Trim(ConfiguredShellValue) = "")
 ConfiguredShellValue := "explorer.exe"

; SteamShell 1.2/1.3 deliberately relaunched with *RunAs. Restoring that
; behavior keeps controller input and window management available for elevated
; Windows surfaces such as Task Manager.
EnsureSteamShellElevation()

; Register cleanup before any cursor, splash, process, or shell side effects.
OnExit(ExitCleanup)

; ==============================================================================
; HELPERS (v2.0.19 compatibility)
; ==============================================================================
StrRepeat(s, count) {
 if (count <= 0)
 return ""
 out := ""
 Loop count
 out .= s
 return out
}

NowStamp() {
 return FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
}

SetSessionState(newState, detail := "") {
 global SessionState
 newState := StrUpper(Trim(newState))
 if (newState = "" || newState = SessionState)
     return
 previousState := SessionState
 SessionState := newState
 LogLine("Session state: " previousState " -> " newState
     . (detail != "" ? " (" detail ")" : ""))
}


; Record LC Last based on gate state transitions (prevents constant updates during countdowns).
LC_RecordGateIfChanged(gateText, cat) {
    global LC_LastGateCat, LC_LastDecisionStamp, LC_LastDecisionText
    if (cat = "")
        return
    if (LC_LastGateCat != cat) {
        LC_LastGateCat := cat
        LC_LastDecisionStamp := NowStamp()
        LC_LastDecisionText := gateText
    }
}

GetLastLines(text, maxLines, newestFirst := false) {
 if (maxLines <= 0)
 return ""
 t := StrReplace(text, "`r`n", "`n")
 t := StrReplace(t, "`r", "`n")
 lines := StrSplit(t, "`n")
 total := lines.Length
 start := total - maxLines + 1
 if (start < 1)
 start := 1

 out := ""
 if (newestFirst) {
 i := total
 while (i >= start) {
 out .= lines[i] "`r`n"
 i--
 }
 } else {
 i := start
 while (i <= total) {
 out .= lines[i] "`r`n"
 i++
 }
 }
 return out
}

SecondsLeft(tickUntil) {
 ms := tickUntil - A_TickCount
 if (ms <= 0)
 return 0
 return Ceil(ms / 1000)
}

; ==============================================================================
; INI (create + load)
; ==============================================================================
GetDefaultSettingsIniText() {
 txt := "
(
; ==================================================================================================
; SteamShellSettings.ini (auto-generated)
; - Edit values, then reboot OR press Ctrl+Alt+Shift+R to reload.
; - Booleans: true / false
; - If you break things: delete this file and it will be recreated.
; - Comments start with ';' (everything after it is ignored by SteamShell).
; - Settings: Ctrl+Alt+Shift+S.
; - Control Panel: Ctrl+Alt+Shift+P.
; - Quick Menu: Ctrl+Alt+Shift+Q.
; ==================================================================================================

[SteamShell]
SettingsSchemaVersion=12                                   ; Internal schema used for safe settings upgrades

[Paths]
SteamPath=C:\Program Files (x86)\Steam\Steam.exe            ; Full path to Steam.exe

[BPM]
BpmTitle=Steam Big Picture Mode                             ; Big Picture window title (must match your BPM title)

[Steam]
MenuShortcut=^1                                            ; Steam Menu while Big Picture owns the foreground
QuickAccessShortcut=^2                                     ; Steam Quick Access shortcut
OverlayShortcut=+{Tab}                                     ; Steam overlay while a game owns the foreground

[Features]
RunElevatedOnStartup=true                                  ; Recommended; lets controller mouse/input reach elevated windows
EnableSplashScreen=true                                     ; Show a black splash overlay during boot
EnableTaskbarHiding=true                                    ; Hide taskbar & tray windows (kiosk feel)
EnableDesktopBlackout=true                                  ; Black backdrop instead of the wallpaper and desktop icons
EnableWindowManagement=true                                 ; Center windows; maximize large windows (skips OSK + Steam KB)
EnableAutoHideCursor=true                                   ; Hide cursor after MouseHideDelay inactivity
EnableAutoMouseMode=true                                    ; Allow AutoMouseExeList to act as a virtual View/Back hold (list still required)
EnableSteamRefocusMode=true                                 ; Refocus BPM after SteamRefocusDelay when nothing else is visible
EnableGameForegroundAssist=true                             ; Detect fullscreen-ish games and bring them to front
EnableAlwaysFocus=true                                      ; Allow specific apps (ExeList) to always win focus over Steam
EnableMouseParkOnBoot=true                                  ; Move pointer to the active display edge once during startup
EnableMouseParkOnFocusChange=true                           ; Park once when SteamShell actually changes the focused window

[Timing]
SplashScreenDuration=10000                                  ; Splash duration in milliseconds (0 disables fade)
MouseMonitorInterval=250                                    ; Mouse polling interval (ms)
MouseHideDelay=1000                                         ; Hide cursor after this many ms without movement
SteamRefocusDelay=3000                                      ; Wait this many ms before refocusing BPM (when no windows remain)
SteamStartupGraceMs=120000                                  ; Log startup warning after this delay; restore arms only after Steam is observed
SteamExitConfirmMs=8000                                     ; Steam must remain closed this long before automatic desktop restore (ms)

[Splash]
Mode=Black                                                  ; Black | Video
VideoPath=                                                  ; Full path to startup video (mp4/wmv). Leave blank for Black.
Mute=false                                                  ; Mute video audio
PlayFullDuration=true                                       ; If true, play full video before fading out (safety timeout still applies)
SafetyMaxMs=15000                                           ; Failsafe max time to keep splash up in Video+PlayFullDuration mode. Set LONGER than your video length.
FadeOutMs=300                                               ; Fade out duration in ms (0 = no fade)
TopmostGuardMs=500                                          ; Re-assert topmost while visible (0 disables)

MpvPath=                                                    ; Full path to mpv.exe (required when Mode=Video)
ForceSDR=true                                               ; Force MPV to output SDR (prevents HDR/Dolby Vision mode switching)
DebugOverlay=false                                          ; If true, shows the reason video failed on the splash screen


[WindowManagement]
MinWidthPercent=0.20                                        ; Only maximize windows wider than this % of screen width
ExcludeExeList=                                             ; Optional: Pipe-separated EXEs to skip (e.g. GameBar.exe|YourTool.exe)
ExcludeClassList=                                           ; Optional: Pipe-separated window classes to skip (e.g. UnityWndClass|Chrome_WidgetWin_1)

[AlwaysFocus]
ExeList=                                                    ; Pipe-separated EXEs: Example SplitSecond.exe|EADesktop.exe
AlwaysFocusCooldownMs=1000                                  ; Minimum time between re-activating an AlwaysFocus window

[GameForegroundAssist]
GameCPUThresholdPercent=5.0                                 ; CPU % that adds a score bonus
FullscreenTolerance=0.98                                    ; Window must be >= this % of screen size to count as fullscreen-ish
FullscreenPosTolerancePx=2                                  ; Window position must be within this many px of 0,0 for fullscreen-ish
AudioPeakThreshold=0.02                                     ; Advanced: audio peak (0.0–1.0) to treat as “active game audio”
GameForegroundCooldownMs=1500                               ; Minimum time between forced game activations
GameAllowZeroCpuAsCandidate=true                            ; If CPU samples 0, still allow candidate
GameRequireSteamForeground=true                             ; Only run game assist when Steam is foreground (safe default)
GameAssistLogEvenWhenSkipped=false                          ; Log candidates even when skipped due to Steam not foreground

EnableAudioAssist=true                                      ; Add score if the process is outputting audio
ScoreAudioActive=30                                         ; Score bonus when audio peak is detected

ScoreFullscreen=70                                          ; Base score when fullscreen-ish
ScoreBorderlessLarge=45                                     ; Base score when large borderless but not at 0,0
ScoreTitleBonus=10                                          ; Score bonus if window has a non-trivial title
ScoreCpuAboveThreshold=20                                   ; Score bonus if CPU >= GameCPUThresholdPercent
ScoreCpuNonZeroBonus=15                                     ; Score bonus if CPU > 0 but below threshold
GameMinScoreToActivate=55                                   ; Foreground sensitivity: Responsive=55, Balanced=60, Conservative=70

[Logging]
GameLogMode=OFF                                             ; OFF|ACTIVATIONS|TOPN|DIAGNOSTIC
GameLogTopN=3                                               ; When TOPN/DIAGNOSTIC, log this many top candidates
GameLogIntervalMs=3000                                      ; Rate limit for TOPN/DIAGNOSTIC logging
GameLogIncludeTitles=true                                   ; Include window titles in the log
GameLogRejectNearCandidates=true                            ; In DIAGNOSTIC, also log near-fullscreen rejects
GameLogRejectMinAreaPercent=0.85                            ; Only log rejects with >= this % of screen area
GameLogRotateMaxKB=256                                      ; Rotate log when it exceeds this many KB
GameLogRotateBackups=2                                      ; Keep this many rotated backups

[MousePark]
MouseParkEdge=Right                                        ; Right | Left vertical edge of the active display
MouseParkRightOffsetPx=50                                   ; Logical push toward the right edge (clamped to the target display)
MouseParkYPercent=0.50                                      ; Park cursor at this % of screen height

[StartupPrograms]
Enable=false                                                ; Start additional user-defined programs at boot (hidden)
DelayMs=2000                                                ; Wait this long after SteamShell starts before launching them
WindowMode=Hidden                                           ; Hidden | Minimized | Normal
; Define programs as Program1..Program20. Format:
; ProgramN="C:\Path\App.exe" --arg1 --arg2
; Quotes recommended if the path contains spaces. Everything after the exe is treated as arguments.
; Programs are started with Run(..., "Hide") and SteamShell will also attempt to hide any windows they create briefly.
Program1=
Program2=
Program3=
Program4=
Program5=
Program6=
Program7=
Program8=
Program9=
Program10=
Program11=
Program12=
Program13=
Program14=
Program15=
Program16=
Program17=
Program18=
Program19=
Program20=

[LauncherCleanup]
; Optional: automatically close common game launchers after you’ve returned to Steam.
; This runs only when Steam is in the foreground for SteamForegroundSec seconds.
; NOTE: Closing background services is aggressive. Use RequireNoGame=true for safety.

Enable=false
SteamForegroundSec=30
RequireNoGame=true
CooldownSec=300
CheckIntervalMs=2000
GracefulCloseMs=4000
HardKill=false


; Advanced (only used when RequireNoGame=true and UseCpuAudio=true)
UseCpuAudio=true
CpuThreshold=12
AudioPeakThreshold=0.02
; Busy guard (optional): skip cleanup if launchers appear to be actively downloading/updating
DownloadGuard=false
DownloadGuardMode=Balanced
; Pipe-separated EXEs (case-insensitive). If an entry has no .exe, it will be appended.
LauncherExeList=UbisoftConnect.exe|upc.exe|EpicGamesLauncher.exe|EADesktop.exe|EALauncher.exe|Origin.exe|Battle.net.exe|RockstarGamesLauncher.exe|GalaxyClient.exe|RiotClientServices.exe|RiotClientUx.exe|Heroic.exe
BackgroundExeList=UbisoftConnectService.exe|UplayWebCore.exe|UplayService.exe|EpicWebHelper.exe|EABackgroundService.exe|BlizzardUpdateAgent.exe|RockstarService.exe|SocialClubHelper.exe|GalaxyClientService.exe|GalaxyCommunication.exe|RiotClientUxRender.exe|legendary.exe|gogdl.exe|nile.exe

; Safety: never kill these
ExcludeExeList=steam.exe|steamwebhelper.exe|SteamShell.exe

[Controller]
EnableControllerMouseMode=true                              ; Enable controller mouse/keyboard mapping (hold View/Back)
ControllerIndex=0                                           ; 0=first controller
ControllerPollIntervalMs=16                                 ; Poll rate (ms)
ControllerDeadzone=4000                                     ; Stick deadzone (0-32767)
ControllerMouseSpeed=100                                    ; Pixels per poll tick at full deflection
ControllerMouseFastMultiplier=2.5                           ; Multiplier while RT is held
ControllerScrollIntervalMs=80                               ; Min ms between scroll ticks
ControllerScrollStep=1                                      ; Wheel notches per scroll tick
ControllerChordHoldMs=500                                   ; Long-press threshold (ms) for View/Back + button actions
AutoMouseExeList=                                           ; EXEs where the View/Back mappings apply WITHOUT holding View/Back

[QuickMenu]
Enable=true                                                 ; Hold L3+R3 to open/close the living-room quick menu
ChordHoldMs=700                                             ; Required L3+R3 hold time
TaskForceCloseHoldMs=1200                                   ; Hold X this long in Task Switcher to force-close a process
MainOrder=Audio|Display|RTSS|SteamMenu|SteamQuickAccess|Layout|Tasks|GameBar|Settings|System
HiddenItems=                                                ; Optional rows to hide; Settings and System stay available

[AudioQuickControls]
Enable=true                                                 ; Volume and mute controls in the quick menu

[DisplayQuickControls]
Enable=true                                                 ; Resolution/refresh/HDR controls when supported

[RTSS]
EnableIntegration=false                                     ; Enable after configuring RTSS and its HotkeyHandler shortcuts
Path=C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe
UseDllIntegration=true                                      ; Live state/direct control through RTSSHooks64.dll when available
OverlayControlMode=Toggle                                  ; Toggle | Separate
OverlayToggleShortcut=^+o                                   ; Ctrl+Shift+O - configure the same overlay hotkey in RTSS
OverlayOnShortcut=^+1                                      ; Separate mode: Ctrl+Shift+1 - Show OSD
OverlayOffShortcut=^+2                                     ; Separate mode: Ctrl+Shift+2 - Hide OSD
FrameLimiterControlMode=Toggle                             ; Toggle | Separate
CustomFrameCap=0                                           ; Your configured RTSS target FPS, e.g. 72, 117, or 141
CustomFrameCapShortcut=^+f                                 ; Toggle mode: Ctrl+Shift+F
FrameLimiterOnShortcut=^+5                                ; Separate mode: Ctrl+Shift+5 - enable limiter
FrameLimiterOffShortcut=^+6                               ; Separate mode: Ctrl+Shift+6 - disable limiter

[ControllerMap]
; Builtin actions also include QuickMenu and ControlPanel.
RB.Short=Builtin:LeftClick
RB.Long=Builtin:None
RT.Short=Builtin:RightClick
RT.Long=Builtin:None
LT.Short=Send:^+o
LT.Long=Send:^+f
LB.Short=Send:^!{Tab}
LB.Long=Builtin:TaskManager
A.Short=Builtin:Enter
A.Long=Builtin:None
B.Short=Builtin:Esc
B.Long=Builtin:AltF4
X.Short=Builtin:TabTip
X.Long=Builtin:OSK
Y.Short=Builtin:WinG
Y.Long=Builtin:None
Start.Short=Builtin:StartMenu
Start.Long=Builtin:Explorer
L3.Short=Builtin:None
L3.Long=Builtin:None
R3.Short=Builtin:None
R3.Long=Builtin:None

; Optional display labels for Send: bindings (UI only)
LT.Short.Display=Ctrl+Shift+O
LT.Long.Display=Ctrl+Shift+F
LB.Short.Display=Ctrl+Alt+Tab
)"
 return txt
}

EnsureSettingsIniExists() {
 global SettingsPath
 if FileExist(SettingsPath)
     return
 try FileAppend(GetDefaultSettingsIniText(), SettingsPath, "UTF-16")
}

EnsureSettingsIniUnicode() {
 global SettingsPath, ScriptPid
 if !FileExist(SettingsPath)
     return true

 isUtf16 := false
 try {
     rawFile := FileRead(SettingsPath, "RAW")
     isUtf16 := rawFile.Size >= 2 && NumGet(rawFile, 0, "UShort") = 0xFEFF
 }
 if (isUtf16)
     return true

 ; Preserve the original before converting legacy UTF-8/ANSI settings.
 backupPath := SettingsPath ".pre-unicode.bak"
 try {
     if !FileExist(backupPath)
         FileCopy(SettingsPath, backupPath, false)
     contents := FileRead(SettingsPath)
     tempPath := SettingsPath ".unicode-" ScriptPid ".tmp"
     if FileExist(tempPath)
         FileDelete(tempPath)
     FileAppend(contents, tempPath, "UTF-16")
     FileMove(tempPath, SettingsPath, true)
     return true
 } catch as err {
     try {
         if IsSet(tempPath) && FileExist(tempPath)
             FileDelete(tempPath)
     }
     LogLine("Settings encoding conversion failed: " err.Message)
     return false
 }
}

GetDefaultSettingsSchema() {
 schema := []
 section := ""

 for _, rawLine in StrSplit(GetDefaultSettingsIniText(), "`n", "`r") {
     line := Trim(rawLine)
     if (line = "" || SubStr(line, 1, 1) = ";")
         continue

     if RegExMatch(line, "^\[([^\]]+)\]$", &sectionMatch) {
         section := sectionMatch[1]
         continue
     }

     separatorPos := InStr(line, "=")
     if (section = "" || separatorPos <= 1)
         continue

     key := Trim(SubStr(line, 1, separatorPos - 1))
     value := Trim(SubStr(line, separatorPos + 1))
     commentPos := RegExMatch(value, "(^|\s)[;#]")
     if (commentPos) {
         value := commentPos = 1 ? "" : Trim(SubStr(value, 1, commentPos - 1))
     }
     schema.Push(Map("section", section, "key", key, "value", value))
 }
 return schema
}

TryReadIniRaw(section, key, &value) {
 global SettingsPath
 sentinel := "{SteamShell-Missing-7F3AA457-44A1-4B99}"
 value := sentinel
 try value := IniRead(SettingsPath, section, key, sentinel)
 return value != sentinel
}

GetRetiredIniKeys() {
 global SettingsPath
 retired := []

 if TryReadIniRaw("Features", "EnableMouseParkEveryRefocus", &legacyParkValue) {
     retired.Push(Map(
         "section", "Features",
         "key", "EnableMouseParkEveryRefocus",
         "value", legacyParkValue,
         "replacementSection", "Features",
         "replacementKey", "EnableMouseParkOnFocusChange"))
 }
 for _, cursorKey in ["EnableCursorHideOnBoot", "EnableCursorHideOnRefocus"] {
     if TryReadIniRaw("Features", cursorKey, &retiredCursorValue)
         retired.Push(Map("section", "Features", "key", cursorKey))
 }

 ; Schema 5 makes coordinated-engine timing and retry values safe internal
 ; defaults. Retire both the original independent timers and schema 4's
 ; low-level engine controls instead of carrying ineffective combinations.
 if TryReadIniRaw("Timing", "WindowCheckInterval", &legacyWindowTick) {
     retired.Push(Map(
         "section", "Timing",
         "key", "WindowCheckInterval"))
 }
 if TryReadIniRaw("Timing", "SteamRefocusPollingInterval", &legacyFocusTick) {
     retired.Push(Map(
         "section", "Timing",
         "key", "SteamRefocusPollingInterval"))
 }
 for _, engineKey in [
     "TickIntervalMs",
     "FocusIntervalMs",
     "GeometryRetryMs",
     "GeometryMaxAttempts",
     "CpuSampleIntervalMs"
 ] {
     if TryReadIniRaw("WindowEngine", engineKey, &retiredEngineValue)
         retired.Push(Map("section", "WindowEngine", "key", engineKey))
 }

 ; OFF is now the single logging disable state. The old boolean duplicated
 ; GameLogMode and could create contradictory combinations.
 if TryReadIniRaw("Logging", "EnableGameScoreLogging", &retiredLoggingToggle)
     retired.Push(Map("section", "Logging", "key", "EnableGameScoreLogging"))

 ; The old RTSS preset list was replaced by one user-configured frame cap.
 rtssSection := ""
 try rtssSection := IniRead(SettingsPath, "RTSS")
 for _, rawLine in StrSplit(rtssSection, "`n", "`r") {
     separatorPos := InStr(rawLine, "=")
     if (separatorPos <= 1)
         continue
     key := Trim(SubStr(rawLine, 1, separatorPos - 1))
     if RegExMatch(key, "i)^FrameCap(?:Options|0Shortcut|\d+Shortcut)$") {
         retired.Push(Map("section", "RTSS", "key", key))
     }
 }
 return retired
}

BackupSettingsBeforeMigration(sourceVersion) {
 global SettingsPath
 backupPath := SettingsPath ".pre-schema-" sourceVersion ".bak"
 if FileExist(backupPath)
     return true
 try FileCopy(SettingsPath, backupPath, false)
 return FileExist(backupPath)
}

SyncSettingsIniSchema() {
 global SettingsPath, IniPath, CurrentSettingsSchemaVersion, ScriptPid
 if !FileExist(SettingsPath)
     return

 schema := GetDefaultSettingsSchema()
 missing := []
 for _, option in schema {
     if !TryReadIniRaw(option["section"], option["key"], &existingValue)
         missing.Push(option)
 }

 retired := GetRetiredIniKeys()
 sourceVersion := 0
 if TryReadIniRaw("SteamShell", "SettingsSchemaVersion", &rawVersion)
     sourceVersion := Max(0, ToInt(CleanIniValue(rawVersion, "0"), 0))
 versionNeedsUpdate := sourceVersion < CurrentSettingsSchemaVersion

 if (missing.Length = 0 && retired.Length = 0 && !versionNeedsUpdate)
     return

 ; Do not touch the working settings file unless a recoverable snapshot exists.
 if !BackupSettingsBeforeMigration(sourceVersion)
     return

 livePath := SettingsPath
 workPath := livePath ".migration-" ScriptPid ".tmp"
 success := false
 try {
     if FileExist(workPath)
         FileDelete(workPath)
     FileCopy(livePath, workPath, true)
     SettingsPath := workPath
     IniPath := workPath

     ; Transfer legacy values before deleting their old keys. Existing
     ; replacement values always win, including deliberately blank values.
     for _, oldOption in retired {
         if !oldOption.Has("replacementKey")
             continue
         if TryReadIniRaw(oldOption["replacementSection"], oldOption["replacementKey"], &replacementValue)
             continue
         migratedValue := CleanIniValue(oldOption["value"], "true")
         IniWrite(migratedValue, workPath, oldOption["replacementSection"], oldOption["replacementKey"])
     }

     ; Schema 2 replaces retired Back+Start preview bindings while preserving
     ; any genuinely custom Start mappings.
     if (sourceVersion < 2) {
         if TryReadIniRaw("ControllerMap", "Start.Short", &startShortValue) {
             normalizedShort := StrLower(CleanIniValue(startShortValue, ""))
             if (normalizedShort = "builtin:none" || normalizedShort = "builtin:quickmenu")
                 IniWrite("Builtin:StartMenu", workPath, "ControllerMap", "Start.Short")
         }
         if TryReadIniRaw("ControllerMap", "Start.Long", &startLongValue) {
             normalizedLong := StrLower(CleanIniValue(startLongValue, ""))
             if (normalizedLong = "builtin:none" || normalizedLong = "builtin:controlpanel")
                 IniWrite("Builtin:Explorer", workPath, "ControllerMap", "Start.Long")
         }
     }

    ; Schema 5 lowers the controller deadzone default. Update only the exact
    ; former default so genuinely customized values remain untouched.
    if (sourceVersion < 5
        && TryReadIniRaw("Controller", "ControllerDeadzone", &oldDeadzone)
        && ToInt(CleanIniValue(oldDeadzone, "8000"), 8000) = 8000)
        IniWrite("4000", workPath, "Controller", "ControllerDeadzone")

    ; Schema 6 makes the Responsive foreground preset the default. Migrate only
    ; the former value of 60 so custom thresholds remain untouched.
    if (sourceVersion < 6
        && TryReadIniRaw(
            "GameForegroundAssist", "GameMinScoreToActivate", &oldFocusThreshold)
        && ToInt(CleanIniValue(oldFocusThreshold, "60"), 60) = 60)
        IniWrite(
            "55", workPath,
            "GameForegroundAssist", "GameMinScoreToActivate")

    ; Schema 8 replaces the standalone-only Focus/Return rows with XFE's
    ; controller-facing Steam Menu, Steam Quick Access, and Game Bar rows.
    ; Reset the order once so an existing schema-7 INI gets the same top-level
    ; layout as a fresh install. Preserve visibility choices for rows that still
    ; exist; the three new action rows intentionally start visible.
    if (sourceVersion < 8) {
        IniWrite(
            "Audio|Display|RTSS|SteamMenu|SteamQuickAccess|Layout|Tasks|GameBar|Settings|System",
            workPath, "QuickMenu", "MainOrder")
        migratedHidden := []
        preservedHidden := Map(
            "audio", true,
            "display", true,
            "rtss", true,
            "layout", true,
            "tasks", true)
        if TryReadIniRaw("QuickMenu", "HiddenItems", &oldHiddenItems) {
            for _, rawHiddenName in StrSplit(CleanIniValue(oldHiddenItems, ""), "|") {
                hiddenName := StrLower(Trim(rawHiddenName))
                if (hiddenName != "" && preservedHidden.Has(hiddenName))
                    migratedHidden.Push(hiddenName)
            }
        }
        IniWrite(JoinWith(migratedHidden, "|"), workPath, "QuickMenu", "HiddenItems")
    }

     for _, option in schema {
         if TryReadIniRaw(option["section"], option["key"], &existingValue)
             continue
         IniWrite(option["value"], workPath, option["section"], option["key"])
     }

     for _, oldOption in retired {
         canDelete := true
         if oldOption.Has("replacementKey") {
             canDelete := TryReadIniRaw(
                 oldOption["replacementSection"], oldOption["replacementKey"], &replacementValue)
         }
         if (canDelete)
             IniDelete(workPath, oldOption["section"], oldOption["key"])
     }
     if (sourceVersion < 5)
         try IniDelete(workPath, "WindowEngine")

     if (versionNeedsUpdate)
         IniWrite(CurrentSettingsSchemaVersion, workPath, "SteamShell", "SettingsSchemaVersion")
     success := true
 } catch as err {
     LogLine("Settings schema migration failed; original INI retained: " err.Message)
 } finally {
     SettingsPath := livePath
     IniPath := livePath
 }

 if (success) {
     try FileMove(workPath, livePath, true)
     catch as err {
         LogLine("Settings schema commit failed; original INI retained: " err.Message)
         success := false
     }
 }
 if (!success) {
     try {
         if FileExist(workPath)
             FileDelete(workPath)
     }
 }
}

CleanIniValue(v, default := "", blankUsesDefault := true) {
 v := Trim(v)
 if (v = "")
 return blankUsesDefault ? default : ""

 pos := RegExMatch(v, "(^|\s)[;#]")
 if (pos)
 v := pos = 1 ? "" : Trim(SubStr(v, 1, pos - 1))

 if (v = "")
 return blankUsesDefault ? default : ""

 return v
}

IniReadS(section, key, default := "") {
 if !TryReadIniRaw(section, key, &v)
     return default
 ; A present-but-empty value is intentional. Only a missing key receives the
 ; supplied default; this is important for optional shortcuts and paths.
 return CleanIniValue(v, "", false)
}

ToBool(v, default := false) {
    ; Always returns a true/false (numeric 1/0) result.
    ; Accepts common boolean strings: 1/0, true/false, yes/no, on/off.

    b := _TryParseBool(v)
    if (b != "")
        return b

    b := _TryParseBool(default)
    if (b != "")
        return b

    ; Fallback: if default is numeric/bool, coerce it; if it's any other non-empty string, treat as true.
    try return (default + 0) != 0
    catch {
        return Trim(default "") != ""
    }
}

_TryParseBool(x) {
    try {
        ; Numeric?
        if IsNumber(x)
            return (x + 0) != 0
    } catch {
        ; Ignore
    }

    s := StrLower(Trim(x ""))
    if (s = "1" || s = "true" || s = "yes" || s = "on")
        return true
    if (s = "0" || s = "false" || s = "no" || s = "off" || s = "")
        return false

    return ""  ; unknown token
}

ToInt(v, default := 0) {
 s := Trim(v)
 return RegExMatch(s, "^-?\d+$") ? (s + 0) : default
}

ToFloat(v, default := 0.0) {
 s := Trim(v)
 return RegExMatch(s, "^-?(?:\d+(?:\.\d*)?|\.\d+)$") ? (s + 0.0) : default
}

FormatSettingsFloat(value, maxDecimals := 6) {
 ; AutoHotkey can stringify a binary floating-point value as
 ; 0.20000000000000001. Store a bounded, human-readable decimal instead.
 text := Format("{:." maxDecimals "f}", value + 0.0)
 text := RegExReplace(text, "0+$")
 text := RegExReplace(text, "\.$")
 return text = "-0" ? "0" : text
}

ClampInt(v, lo, hi) {
 if (v < lo)
 return lo
 if (v > hi)
 return hi
 return v
}

ClampFloat(v, lo, hi) {
 if (v < lo)
 return lo
 if (v > hi)
 return hi
 return v
}

ParseExeListPipe(raw) {
 list := []

 raw := Trim(raw)

 ; Strip inline comments (helps if INI has: ExeList= ; Pipe-separated EXEs: example ...)
 if (raw != "") {
 sc := InStr(raw, ";")
 if (sc)
 raw := Trim(SubStr(raw, 1, sc - 1))
 hc := InStr(raw, "#")
 if (hc)
 raw := Trim(SubStr(raw, 1, hc - 1))
 }

 if (raw = "")
 return list

 for p in StrSplit(raw, "|") {
 token := Trim(p)
 if (token = "")
 continue
 if (SubStr(token, 1, 1) = ";" || SubStr(token, 1, 1) = "#")
 continue

 exe := StrLower(token)
 if !InStr(exe, ".exe")
 exe .= ".exe"
 if !RegExMatch(exe, "i)^[a-z0-9][a-z0-9_. -]*\.exe$")
     continue
 list.Push(exe)
 }
 return list
}

ParseClassListPipe(raw) {
 list := []

 raw := Trim(raw)

 ; Strip inline comments (helps if INI has: ExcludeClassList= ; example ...)
 if (raw != "") {
 sc := InStr(raw, ";")
 if (sc)
 raw := Trim(SubStr(raw, 1, sc - 1))
 hc := InStr(raw, "#")
 if (hc)
 raw := Trim(SubStr(raw, 1, hc - 1))
 }

 if (raw = "")
 return list

 for p in StrSplit(raw, "|") {
 token := Trim(p)
 if (token = "")
 continue
 if (SubStr(token, 1, 1) = ";" || SubStr(token, 1, 1) = "#")
 continue

 cls := StrLower(token)
 list.Push(cls)
 }
 return list
}


IsExeInList(exeLower, listObj) {
 for _, v in listObj {
 if (exeLower = v)
 return true
 }
 return false
}

JoinPipe(listObj) {
 out := ""
 for _, v in listObj {
 if (v = "")
 continue
 out .= (out = "" ? v : "|" v)
 }
 return out
}

JoinWith(listObj, delimiter := ", ") {
 out := ""
 for _, value in listObj
     out .= (out = "" ? "" : delimiter) value
 return out
}

CommitIniChanges(changes, deletes := 0) {
 global SettingsPath, ScriptPid
 static busy := false
 if (busy)
     return false
 busy := true
 workPath := SettingsPath ".update-" ScriptPid ".tmp"
 try {
     if FileExist(workPath)
         FileDelete(workPath)
     FileCopy(SettingsPath, workPath, true)
     for _, item in changes
         IniWrite(item["value"], workPath, item["section"], item["key"])
     if IsObject(deletes) {
         for _, item in deletes
             IniDelete(workPath, item["section"], item["key"])
     }
     FileMove(workPath, SettingsPath, true)
     return true
 } catch as err {
     try {
         if FileExist(workPath)
             FileDelete(workPath)
     }
     LogLine("Settings update failed; original INI retained: " err.Message)
     return false
 } finally {
     busy := false
 }
}

LoadSettings() {
    global AudioPeakThreshold, DEFAULT_AUDIO_PEAK_THRESHOLD
    AudioPeakThreshold := ClampFloat(ToFloat(IniReadS("GameForegroundAssist","AudioPeakThreshold","0.02"), DEFAULT_AUDIO_PEAK_THRESHOLD), 0.0, 1.0)
 global SteamPath, BpmTitle
 global RunElevatedOnStartup
 global EnableSplashScreen, EnableTaskbarHiding, EnableDesktopBlackout
 global EnableWindowManagement, EnableAutoHideCursor
 global EnableSteamRefocusMode, EnableGameForegroundAssist, EnableAlwaysFocus
 global EnableMouseParkOnBoot, EnableMouseParkOnFocusChange
 global EnableCursorHideOnBoot, EnableCursorHideOnRefocus
 global SplashScreenDuration, MouseMonitorInterval
 global WindowEngineTickIntervalMs, WindowEngineFocusIntervalMs
 global WindowEngineGeometryRetryMs, WindowEngineGeometryMaxAttempts
 global WindowEngineCpuSampleIntervalMs
 global SteamStartupGraceMs, SteamExitConfirmMs
 global SplashMode, SplashVideoPath, SplashVideoMute, SplashVideoPlayFull, SplashVideoSafetyMaxMs, SplashFadeOutMs, SplashTopmostGuardMs
 global SplashMpvPath, SplashDebugOverlay, SplashForceSDR, SplashMpvPid, SplashMpvHwnd, SplashFailReason
 global MouseHideDelay, SteamRefocusDelay
 global MinWidthPercent
 global WmExcludeExeListRaw, WmExcludeClassListRaw, WmExcludeExeSet, WmExcludeClassSet
 global EnableAutoMouseMode, AutoMouseExeListRaw, AutoMouseExeSet
 global AlwaysFocusExeListRaw, AlwaysFocusCooldownMs, AlwaysFocusList
 global GameCPUThresholdPercent, FullscreenTolerance, FullscreenPosTolerancePx, GameForegroundCooldownMs
 global GameAllowZeroCpuAsCandidate, GameRequireSteamForeground, GameAssistLogEvenWhenSkipped
 global ScoreFullscreen, ScoreBorderlessLarge, ScoreTitleBonus
 global ScoreCpuAboveThreshold, ScoreCpuNonZeroBonus, GameMinScoreToActivate
 global EnableAudioAssist, ScoreAudioActive
 global EnableGameScoreLogging, GameLogMode, GameLogTopN, GameLogIntervalMs, GameLogIncludeTitles
 global GameLogRejectNearCandidates, GameLogRejectMinAreaPercent, GameLogRotateMaxKB, GameLogRotateBackups
 global MouseParkRightOffsetPx, MouseParkYPercent, MouseParkEdge
 global EnableLauncherCleanup, LauncherCleanupSteamForegroundSec, LauncherCleanupRequireNoGame, LauncherCleanupUseCpuAudio, LauncherCleanupCpuThreshold, LauncherCleanupAudioPeakThreshold, LauncherCleanupDownloadGuard, LauncherCleanupDownloadGuardMode
 global LauncherCleanupCooldownSec, LauncherCleanupCheckIntervalMs, LauncherCleanupGracefulCloseMs, LauncherCleanupHardKill
 global LauncherCleanupLauncherExeListRaw, LauncherCleanupBackgroundExeListRaw, LauncherCleanupExcludeExeListRaw
 global LauncherCleanupLauncherList, LauncherCleanupBackgroundList, LauncherCleanupExcludeSet
 global EnableControllerMouseMode, ControllerIndex, ControllerPollIntervalMs, ControllerDeadzone, ControllerMouseSpeed, ControllerMouseFastMultiplier, ControllerScrollIntervalMs, ControllerScrollStep, ControllerChordHoldMs
 global EnableQuickMenu, QuickMenuChordHoldMs, TaskForceCloseHoldMs
 global QuickMenuMainOrderRaw, QuickMenuHiddenItemsRaw
 global QuickMenuMainOrder, QuickMenuHiddenItems
 global SteamMenuShortcut, SteamQuickAccessShortcut, SteamOverlayShortcut
 global EnableAudioQuickControls, EnableDisplayQuickControls
 global EnableRTSSIntegration, RtssPath, RtssUseDllIntegration, RtssOverlayControlMode
 global RtssOverlayToggleShortcut, RtssOverlayOnShortcut, RtssOverlayOffShortcut
 global RtssFrameLimiterControlMode, RtssCustomFrameCap, RtssCustomFrameCapShortcut
 global RtssFrameLimiterOnShortcut, RtssFrameLimiterOffShortcut

 SteamPath := IniReadS("Paths", "SteamPath", SteamPath)
 BpmTitle := IniReadS("BPM", "BpmTitle", BpmTitle)
 SteamMenuShortcut := IniReadS("Steam", "MenuShortcut", "^1")
 SteamQuickAccessShortcut := IniReadS("Steam", "QuickAccessShortcut", "^2")
 SteamOverlayShortcut := IniReadS("Steam", "OverlayShortcut", "+{Tab}")

 RunElevatedOnStartup := ToBool(
     IniReadS("Features", "RunElevatedOnStartup", "true"), true)
 EnableSplashScreen := ToBool(IniReadS("Features","EnableSplashScreen","true"), true)
 EnableTaskbarHiding := ToBool(IniReadS("Features","EnableTaskbarHiding","true"), true)
 EnableDesktopBlackout := ToBool(IniReadS("Features","EnableDesktopBlackout","true"), true)
 EnableWindowManagement := ToBool(IniReadS("Features","EnableWindowManagement","true"), true)
 EnableAutoHideCursor := ToBool(IniReadS("Features","EnableAutoHideCursor","true"), true)
 EnableSteamRefocusMode := ToBool(IniReadS("Features","EnableSteamRefocusMode","true"), true)
 EnableGameForegroundAssist := ToBool(IniReadS("Features","EnableGameForegroundAssist","true"), true)
 EnableAlwaysFocus := ToBool(IniReadS("Features","EnableAlwaysFocus","true"), true)
 legacyParkOnRefocus := IniReadS("Features","EnableMouseParkEveryRefocus","")
 EnableMouseParkOnBoot := ToBool(IniReadS("Features","EnableMouseParkOnBoot","true"), true)
 EnableMouseParkOnFocusChange := ToBool(
     IniReadS("Features","EnableMouseParkOnFocusChange", legacyParkOnRefocus != "" ? legacyParkOnRefocus : "true"), true)
 ; Cursor hiding does not generate input or reset Windows idle timers, so the
 ; boot/refocus helpers remain safe internal behavior under Auto Hide Cursor.
 EnableCursorHideOnBoot := true
 EnableCursorHideOnRefocus := true

 SplashScreenDuration := ClampInt(ToInt(IniReadS("Timing","SplashScreenDuration","10000"), 10000), 0, 60000)

 ; Splash (Black or Video)
 SplashMode := IniReadS("Splash","Mode","Black")
 SplashVideoPath := IniReadS("Splash","VideoPath","")
 SplashVideoMute := ToBool(IniReadS("Splash","Mute","false"), true)
 SplashVideoPlayFull := ToBool(IniReadS("Splash","PlayFullDuration","true"), false)
 SplashVideoSafetyMaxMs := ClampInt(ToInt(IniReadS("Splash","SafetyMaxMs","15000"), 60000), 1000, 600000)
 SplashFadeOutMs := ClampInt(ToInt(IniReadS("Splash","FadeOutMs","300"), 300), 0, 5000)
 SplashTopmostGuardMs := ClampInt(ToInt(IniReadS("Splash","TopmostGuardMs","500"), 500), 0, 5000)
 SplashMpvPath := IniReadS("Splash","MpvPath","")
 SplashDebugOverlay := ToBool(IniReadS("Splash","DebugOverlay","false"), false)
 SplashForceSDR := ToBool(IniReadS("Splash","ForceSDR","true"), true)

 ; Coordinated-engine cadence and retry limits are intentionally fixed. The
 ; previous editable values allowed combinations that could not take effect
 ; because every policy decision begins with the shared inventory tick.
 WindowEngineTickIntervalMs := 500
 WindowEngineFocusIntervalMs := 1000
 WindowEngineGeometryRetryMs := 1000
 WindowEngineGeometryMaxAttempts := 3
 WindowEngineCpuSampleIntervalMs := 1000
 MouseMonitorInterval := ClampInt(ToInt(IniReadS("Timing","MouseMonitorInterval","250"), 250), 50, 5000)
 MouseHideDelay := ClampInt(ToInt(IniReadS("Timing","MouseHideDelay","1000"), 1000), 0, 60000)
 SteamRefocusDelay := ClampInt(ToInt(IniReadS("Timing","SteamRefocusDelay","3000"), 3000), 0, 60000)
 SteamStartupGraceMs := ClampInt(ToInt(IniReadS("Timing","SteamStartupGraceMs","120000"), 120000), 10000, 600000)
 SteamExitConfirmMs := ClampInt(ToInt(IniReadS("Timing","SteamExitConfirmMs","8000"), 8000), 1000, 60000)

 MinWidthPercent := ClampFloat(ToFloat(IniReadS("WindowManagement","MinWidthPercent","0.20"), 0.20), 0.05, 1.00)

 ; Window-management exclusion lists (optional)
 WmExcludeExeListRaw := IniReadS("WindowManagement", "ExcludeExeList", "")
 WmExcludeClassListRaw := IniReadS("WindowManagement", "ExcludeClassList", "")

 WmExcludeExeSet := Map()
 for _, exe in ParseExeListPipe(WmExcludeExeListRaw)
 WmExcludeExeSet[exe] := true

 WmExcludeClassSet := Map()
 for _, cls in ParseClassListPipe(WmExcludeClassListRaw)
 WmExcludeClassSet[cls] := true

 ; Automatic mouse mode (optional). Both gates must pass: the toggle allows the
 ; feature, the list decides where it applies.
 EnableAutoMouseMode := ToBool(IniReadS("Features","EnableAutoMouseMode","true"), true)
 AutoMouseExeListRaw := IniReadS("Controller", "AutoMouseExeList", "")
 AutoMouseExeSet := Map()
 for _, exe in ParseExeListPipe(AutoMouseExeListRaw)
 AutoMouseExeSet[exe] := true

 AlwaysFocusExeListRaw := IniReadS("AlwaysFocus","ExeList","")
 AlwaysFocusCooldownMs := ClampInt(ToInt(IniReadS("AlwaysFocus","AlwaysFocusCooldownMs","1000"), 1000), 0, 60000)
 AlwaysFocusList := []
 if EnableAlwaysFocus {
     for _, alwaysExe in ParseExeListPipe(AlwaysFocusExeListRaw) {
         if (alwaysExe != "steam.exe" && alwaysExe != "steamwebhelper.exe")
             AlwaysFocusList.Push(alwaysExe)
     }
 }
 AlwaysFocusExeListRaw := JoinPipe(AlwaysFocusList)

 GameCPUThresholdPercent := ClampFloat(ToFloat(IniReadS("GameForegroundAssist","GameCPUThresholdPercent","5.0"), 5.0), 0.0, 100.0)
 FullscreenTolerance := ClampFloat(ToFloat(IniReadS("GameForegroundAssist","FullscreenTolerance","0.98"), 0.98), 0.50, 1.00)
 FullscreenPosTolerancePx := ClampInt(ToInt(IniReadS("GameForegroundAssist","FullscreenPosTolerancePx","2"), 2), 0, 200)
 GameForegroundCooldownMs := ClampInt(ToInt(IniReadS("GameForegroundAssist","GameForegroundCooldownMs","1500"), 1500), 0, 60000)
 GameAllowZeroCpuAsCandidate := ToBool(IniReadS("GameForegroundAssist","GameAllowZeroCpuAsCandidate","true"), true)
 GameRequireSteamForeground := ToBool(IniReadS("GameForegroundAssist","GameRequireSteamForeground","true"), true)
 GameAssistLogEvenWhenSkipped := ToBool(IniReadS("GameForegroundAssist","GameAssistLogEvenWhenSkipped","false"), false)

 EnableAudioAssist := ToBool(IniReadS("GameForegroundAssist","EnableAudioAssist","true"), true)
 ScoreAudioActive := ClampInt(ToInt(IniReadS("GameForegroundAssist","ScoreAudioActive","30"), 30), 0, 200)

 ScoreFullscreen := ClampInt(ToInt(IniReadS("GameForegroundAssist","ScoreFullscreen","70"), 70), 0, 200)
 ScoreBorderlessLarge := ClampInt(ToInt(IniReadS("GameForegroundAssist","ScoreBorderlessLarge","45"), 45), 0, 200)
 ScoreTitleBonus := ClampInt(ToInt(IniReadS("GameForegroundAssist","ScoreTitleBonus","10"), 10), 0, 100)
 ScoreCpuAboveThreshold := ClampInt(ToInt(IniReadS("GameForegroundAssist","ScoreCpuAboveThreshold","20"), 20), 0, 200)
 ScoreCpuNonZeroBonus := ClampInt(ToInt(IniReadS("GameForegroundAssist","ScoreCpuNonZeroBonus","15"), 15), 0, 200)
 GameMinScoreToActivate := ClampInt(ToInt(IniReadS("GameForegroundAssist","GameMinScoreToActivate","55"), 55), 0, 300)

 GameLogMode := StrUpper(IniReadS("Logging","GameLogMode","OFF"))
 if (GameLogMode != "OFF" && GameLogMode != "ACTIVATIONS"
     && GameLogMode != "TOPN" && GameLogMode != "DIAGNOSTIC")
     GameLogMode := "OFF"
 EnableGameScoreLogging := GameLogMode != "OFF"
 GameLogTopN := ClampInt(ToInt(IniReadS("Logging","GameLogTopN","3"), 3), 1, 10)
 GameLogIntervalMs := ClampInt(ToInt(IniReadS("Logging","GameLogIntervalMs","3000"), 3000), 250, 60000)
 GameLogIncludeTitles := ToBool(IniReadS("Logging","GameLogIncludeTitles","true"), true)
 GameLogRejectNearCandidates := ToBool(IniReadS("Logging","GameLogRejectNearCandidates","true"), true)
 GameLogRejectMinAreaPercent := ClampFloat(ToFloat(IniReadS("Logging","GameLogRejectMinAreaPercent","0.85"), 0.85), 0.10, 1.00)
 GameLogRotateMaxKB := ClampInt(ToInt(IniReadS("Logging","GameLogRotateMaxKB","256"), 256), 32, 8192)
 GameLogRotateBackups := ClampInt(ToInt(IniReadS("Logging","GameLogRotateBackups","2"), 2), 0, 10)

 MouseParkRightOffsetPx := ClampInt(ToInt(IniReadS("MousePark","MouseParkRightOffsetPx","50"), 50), 0, 5000)
 MouseParkYPercent := ClampFloat(ToFloat(IniReadS("MousePark","MouseParkYPercent","0.50"), 0.50), 0.0, 1.0)
 MouseParkEdge := StrLower(IniReadS("MousePark", "MouseParkEdge", "Right"))
 if (MouseParkEdge != "left" && MouseParkEdge != "right")
     MouseParkEdge := "right"

 ; Launcher cleanup (optional)
 EnableLauncherCleanup := ToBool(IniReadS("LauncherCleanup","Enable","false"), false)
 LauncherCleanupSteamForegroundSec := ClampInt(ToInt(IniReadS("LauncherCleanup","SteamForegroundSec","30"), 30), 1, 600)
 LauncherCleanupRequireNoGame := ToBool(IniReadS("LauncherCleanup","RequireNoGame","true"), true)
 LauncherCleanupCooldownSec := ClampInt(ToInt(IniReadS("LauncherCleanup","CooldownSec","300"), 300), 0, 86400)
 LauncherCleanupCheckIntervalMs := ClampInt(ToInt(IniReadS("LauncherCleanup","CheckIntervalMs","2000"), 2000), 200, 60000)
 LauncherCleanupGracefulCloseMs := ClampInt(ToInt(IniReadS("LauncherCleanup","GracefulCloseMs","4000"), 4000), 0, 60000)
 LauncherCleanupHardKill := ToBool(IniReadS("LauncherCleanup","HardKill","false"), false)

LauncherCleanupUseCpuAudio := ToBool(IniReadS("LauncherCleanup","UseCpuAudio","true"), true)
LauncherCleanupCpuThreshold := ClampInt(ToInt(IniReadS("LauncherCleanup","CpuThreshold","12"), 12), 0, 500)

LauncherCleanupAudioPeakThreshold := ClampFloat(ToFloat(IniReadS("LauncherCleanup","AudioPeakThreshold","0.02"), 0.02), 0.0, 1.0)
 LauncherCleanupDownloadGuard := ToBool(IniReadS("LauncherCleanup","DownloadGuard","false"), false)
 LauncherCleanupDownloadGuardMode := StrUpper(IniReadS("LauncherCleanup","DownloadGuardMode","Balanced"))
 if (LauncherCleanupDownloadGuardMode != "OFF" && LauncherCleanupDownloadGuardMode != "BALANCED" && LauncherCleanupDownloadGuardMode != "STRICT")
     LauncherCleanupDownloadGuardMode := "BALANCED"
 LauncherCleanupLauncherExeListRaw := IniReadS("LauncherCleanup","LauncherExeList", LauncherCleanupLauncherExeListRaw)
 LauncherCleanupBackgroundExeListRaw := IniReadS("LauncherCleanup","BackgroundExeList", LauncherCleanupBackgroundExeListRaw)
 LauncherCleanupExcludeExeListRaw := IniReadS("LauncherCleanup","ExcludeExeList", LauncherCleanupExcludeExeListRaw)

 LauncherCleanupLauncherList := ParseExeListPipe(LauncherCleanupLauncherExeListRaw)
 LauncherCleanupBackgroundList := ParseExeListPipe(LauncherCleanupBackgroundExeListRaw)

 ; Build exclude set (always includes Steam + SteamShell)
 LauncherCleanupExcludeSet := Map()
 for _, ex in ParseExeListPipe(LauncherCleanupExcludeExeListRaw)
 LauncherCleanupExcludeSet[ex] := true
 LauncherCleanupExcludeSet["steam.exe"] := true
 LauncherCleanupExcludeSet["steamwebhelper.exe"] := true
 LauncherCleanupExcludeSet["steamshell.exe"] := true

 ; Controller mouse mode (XInput / Xbox)
 EnableControllerMouseMode := ToBool(IniReadS("Controller","EnableControllerMouseMode","true"), true)
 ControllerIndex := ClampInt(ToInt(IniReadS("Controller","ControllerIndex","0"), 0), 0, 3)
 ControllerPollIntervalMs := ClampInt(ToInt(IniReadS("Controller","ControllerPollIntervalMs","16"), 16), 5, 200)
 ControllerDeadzone := ClampInt(ToInt(IniReadS("Controller","ControllerDeadzone","4000"), 4000), 0, 32000)
 ControllerMouseSpeed := ClampInt(ToInt(IniReadS("Controller","ControllerMouseSpeed","100"), 100), 1, 200)
 ControllerMouseFastMultiplier := ClampFloat(ToFloat(IniReadS("Controller","ControllerMouseFastMultiplier","2.5"), 2.5), 1.0, 10.0)
 ControllerScrollIntervalMs := ClampInt(ToInt(IniReadS("Controller","ControllerScrollIntervalMs","80"), 80), 10, 1000)
 ControllerScrollStep := ClampInt(ToInt(IniReadS("Controller","ControllerScrollStep","1"), 1), 1, 10)
 ControllerChordHoldMs := ClampInt(ToInt(IniReadS("Controller","ControllerChordHoldMs","500"), 500), 100, 2000)

 EnableQuickMenu := ToBool(IniReadS("QuickMenu","Enable","true"), true)
 QuickMenuChordHoldMs := ClampInt(ToInt(IniReadS("QuickMenu","ChordHoldMs","700"), 700), 300, 3000)
 TaskForceCloseHoldMs := ClampInt(ToInt(IniReadS("QuickMenu","TaskForceCloseHoldMs","1200"), 1200), 600, 3000)
 QuickMenuMainOrderRaw := IniReadS(
     "QuickMenu", "MainOrder",
     "Audio|Display|RTSS|SteamMenu|SteamQuickAccess|Layout|Tasks|GameBar|Settings|System")
 QuickMenuHiddenItemsRaw := IniReadS("QuickMenu", "HiddenItems", "")
 QuickMenuMainOrder := ParseQuickMenuMainOrder(QuickMenuMainOrderRaw)
 QuickMenuHiddenItems := Map()
 for _, itemName in StrSplit(QuickMenuHiddenItemsRaw, "|") {
     itemName := StrLower(Trim(itemName))
     if (itemName != "")
         QuickMenuHiddenItems[itemName] := true
 }
 EnableAudioQuickControls := ToBool(IniReadS("AudioQuickControls","Enable","true"), true)
 EnableDisplayQuickControls := ToBool(IniReadS("DisplayQuickControls","Enable","true"), true)

 EnableRTSSIntegration := ToBool(IniReadS("RTSS","EnableIntegration","false"), false)
 RtssPath := IniReadS("RTSS","Path","C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe")
 RtssUseDllIntegration := ToBool(IniReadS("RTSS", "UseDllIntegration", "true"), true)
 if !RtssUseDllIntegration
     ShutdownRtssHooksApi()
 RtssOverlayControlMode := StrLower(IniReadS("RTSS","OverlayControlMode","Toggle"))
 if (RtssOverlayControlMode != "toggle" && RtssOverlayControlMode != "separate")
     RtssOverlayControlMode := "toggle"
 RtssOverlayToggleShortcut := IniReadS("RTSS","OverlayToggleShortcut","^+o")
 RtssOverlayOnShortcut := IniReadS("RTSS","OverlayOnShortcut","^+1")
 RtssOverlayOffShortcut := IniReadS("RTSS","OverlayOffShortcut","^+2")
 RtssFrameLimiterControlMode := StrLower(IniReadS("RTSS","FrameLimiterControlMode","Toggle"))
 if (RtssFrameLimiterControlMode != "toggle" && RtssFrameLimiterControlMode != "separate")
     RtssFrameLimiterControlMode := "toggle"
 RtssCustomFrameCap := ClampInt(ToInt(IniReadS("RTSS","CustomFrameCap","0"), 0), 0, 1000)
 RtssCustomFrameCapShortcut := IniReadS("RTSS","CustomFrameCapShortcut","^+f")
 RtssFrameLimiterOnShortcut := IniReadS("RTSS","FrameLimiterOnShortcut","^+5")
 RtssFrameLimiterOffShortcut := IniReadS("RTSS","FrameLimiterOffShortcut","^+6")
 LoadControllerMappings()
}

ApplyRuntimeTimers() {
 global WindowEngineTickIntervalMs, ShellMonitorIntervalMs, MouseMonitorInterval
 global EnableAutoHideCursor, EnableTaskbarHiding
 global EnableLauncherCleanup, LauncherCleanupCheckIntervalMs
 global EnableControllerMouseMode, ControllerPollIntervalMs, EnableQuickMenu
 global SettingsGui, DesktopMode, EnableDesktopBlackout

 StopTaskbarGuard()
 StopDesktopBlackout()
 SetTimer(MonitorShell, 0)
 SetTimer(WindowEngineTick, 0)
 SetTimer(MouseWatch, 0)
 SetTimer(PollController, 0)
 SetTimer(CheckLauncherCleanup, 0)

 ResetWindowEngineState(false)

 ; Desktop mode leaves Explorer in charge of presentation. Shell monitoring,
 ; the window engine, the taskbar guard, cursor hiding, and launcher cleanup
 ; all stay disarmed; only controller input survives so the notification-area
 ; icon and Quick Menu remain usable on the normal desktop.
 if (!DesktopMode) {
     SetTimer(MonitorShell, ShellMonitorIntervalMs)
     SetTimer(WindowEngineTick, WindowEngineTickIntervalMs)

     if (EnableTaskbarHiding)
         StartTaskbarGuard()

     if (EnableDesktopBlackout)
         StartDesktopBlackout()

     if (EnableAutoHideCursor)
     SetTimer(MouseWatch, MouseMonitorInterval)

     if (EnableLauncherCleanup)
     SetTimer(CheckLauncherCleanup, LauncherCleanupCheckIntervalMs)
 }

 if (EnableControllerMouseMode || EnableQuickMenu || IsSet(SettingsGui))
 SetTimer(PollController, ControllerPollIntervalMs)
}

ReloadSettings() {
 global QuickMenuVisible, EnableAutoHideCursor, MouseHidden, SafeMode
 LoadSettings()
 if SafeMode
     ApplySafeModeOverrides()
 ApplyRuntimeTimers()
 if (!EnableAutoHideCursor && MouseHidden) {
     SystemCursor("Show")
     MouseHidden := false
 }
 SyncControlPanel()
 RefreshAlwaysFocusManagerLists()
 if (QuickMenuVisible)
     QuickMenuBuildGui()
 ShowNotification("SteamShell settings reloaded", "Success")
}

; ==============================================================================

InitDpiAwareness() {
 ; Make sizing math use real pixels across display scaling.
 ; Must be called before creating any GUIs.
 try {
 ; PER_MONITOR_AWARE_V2 = -4
 DllCall("User32\SetProcessDpiAwarenessContext", "ptr", -4, "ptr")
 return
 } catch {
 }

 ; Fallbacks
 try {
 DllCall("Shcore\SetProcessDpiAwareness", "int", 2) ; PROCESS_PER_MONITOR_DPI_AWARE
 return
 } catch {
 }

 try DllCall("User32\SetProcessDPIAware")
}

; ==============================================================================
; LOG-ONLY ACTION MESSAGES + TRAY ACTIONS
; ==============================================================================

ShowNotification(message, kind := "Info") {
 global LastStatusText, LastStatusLevel, LastStatusTick, StatusVisibleMs
 global QuickMenuVisible
 ; The former bottom-corner notification GUI was distracting over the Quick
 ; Menu and is not coming back. The log remains the record; the Quick Menu
 ; footer is the transient surface, used only when the menu is already open.
 if (Trim(message) = "")
     return
 try LogLine(message, kind)
 LastStatusText := message
 LastStatusLevel := kind
 LastStatusTick := A_TickCount
 if QuickMenuVisible {
     try QuickMenuRefresh()
     ; Repaint once the message expires so the hint returns on its own rather
     ; than whenever the menu next happens to redraw.
     SetTimer(QuickMenuRefresh, -(StatusVisibleMs + 100))
 }
}

TrayOpenQuickMenu(*) {
 global QuickMenuVisible, QuickMenuGui
 if QuickMenuVisible {
     try QuickMenuGui.Show()
     try WinActivate("ahk_id " QuickMenuGui.Hwnd)
     return
 }
 ShowQuickMenu()
}

TrayOpenSettings(*) {
 ShowSettingsEditor()
}

TrayExitToDesktop(*) {
 ExitToDesktop(false)
}

TrayReturnToShell(*) {
 ReturnToShellMode("notification-area request")
}

TrayLaunchSteam(*) {
 LaunchSteamAndReturnToShell()
}

TrayExitSteamShell(*) {
 ExitSteamShell()
}

ApplyTrayIconImage() {
 iconPath := A_ScriptDir "\assets\SteamShell.ico"
 if FileExist(iconPath)
     try TraySetIcon(iconPath)
}

; The notification area is owned by Explorer, and the desktop-restore path
; deliberately restarts Explorer. Every surviving process has to re-add its
; icon when Explorer broadcasts TaskbarCreated. AutoHotkey does this for its own
; icon, but SteamShell is the process that killed Explorer, so re-assert the
; icon explicitly rather than depending on that timing.
RegisterTaskbarCreatedListener() {
 global TaskbarCreatedMessage
 try TaskbarCreatedMessage := DllCall(
     "User32\RegisterWindowMessageW", "WStr", "TaskbarCreated", "UInt")
 ; Braces are required here: a bare `try` cannot be an if-body that an `else`
 ; attaches to.
 if (TaskbarCreatedMessage) {
     try OnMessage(TaskbarCreatedMessage, TaskbarCreatedHandler)
 } else {
     try LogLine("TaskbarCreated could not be registered; the tray icon may not survive an Explorer restart.")
 }
}

; The tray right-click shows the ordinary Windows menu, matching XFE.
;
; It previously did not. AutoHotkey will not launch a timer thread while a menu
; is displayed and the native menu runs a modal loop, so PollController stops for
; as long as it is open -- meaning a controller user could right-click the icon
; and then be unable to move the pointer onto the menu they had just opened. The
; right-click was taken over and the Quick Menu shown instead, which is an
; ordinary window and stays navigable.
;
; That reasoning had the context backwards. Reaching a tray icon at all means
; using a pointer, and a controller user opens the Quick Menu with L3+R3 or
; Ctrl+Alt+Shift+Q rather than steering a cursor to the notification area. The
; interception optimised for a case that barely occurs, at the cost of the case
; that occurs constantly: someone at a keyboard and mouse wanting a small, fast
; menu where they clicked.
;
; The freeze is real and is accepted, not forgotten. Anyone who does reach the
; menu by controller emulation dismisses it the same way any menu is dismissed --
; Escape, or a click elsewhere -- both of which are available to whatever pointer
; opened it. Double-click still opens the Quick Menu, via the menu's default
; item, so the controller-friendly surface is one gesture away.

TaskbarCreatedHandler(*) {
 ; Explorer is still building the tray when it sends this. Re-assert shortly
 ; after rather than inside the broadcast handler.
 SetTimer(ReassertTrayIcon, -750)
}

ReassertTrayIcon() {
 try {
     A_IconHidden := true
     A_IconHidden := false
 }
 ApplyTrayIconImage()
 RefreshTrayMenu()
 try LogLine("Notification-area icon re-asserted after an Explorer taskbar rebuild.")
}

RefreshTrayMenu() {
 global DesktopMode
 try A_TrayMenu.Delete()
 A_TrayMenu.Add("Open Quick Menu", TrayOpenQuickMenu)
 A_TrayMenu.Add("Open Settings", TrayOpenSettings)
 A_TrayMenu.Add("Open Diagnostics", ShowControlPanel)
 A_TrayMenu.Add()
 if (DesktopMode) {
     A_TrayMenu.Add("Launch Steam and Return to SteamShell", TrayLaunchSteam)
     A_TrayMenu.Add("Return to SteamShell", TrayReturnToShell)
 } else {
     A_TrayMenu.Add("Exit Steam to Desktop", TrayExitToDesktop)
 }
 A_TrayMenu.Add()
 A_TrayMenu.Add("Reload Settings", (*) => ReloadSettings())
 A_TrayMenu.Add("Exit SteamShell", TrayExitSteamShell)
 A_TrayMenu.Default := "Open Quick Menu"
 A_IconTip := DesktopMode
     ? "SteamShell — desktop mode"
     : "SteamShell"
}

InitializeTrayMenu() {
 ApplyTrayIconImage()
 RefreshTrayMenu()
 RegisterTaskbarCreatedListener()
}

; SPLASH
; ==============================================================================

NormalizeMediaPath(p) {
 ; Trim whitespace and optional surrounding quotes.
 p := Trim(p)
 if (p = "")
 return ""
 if (SubStr(p, 1, 1) = '"' && SubStr(p, -1) = '"')
 p := SubStr(p, 2, StrLen(p) - 2)
 p := Trim(p)

 ; Expand environment variables like %USERPROFILE%
 p := ExpandEnvVars(p)

 ; If relative, resolve against script dir
 if (!RegExMatch(p, "i)^[A-Z]:\\") && !InStr(p, "\\") && !InStr(p, "://")) {
 p := A_ScriptDir "\" p
 }
 return p
}

ExpandEnvVars(s) {
 ; Expands %VAR% tokens.
 out := ""
 pos := 1
 while (pos <= StrLen(s)) {
 p1 := InStr(s, "%", , pos)
 if (!p1) {
 out .= SubStr(s, pos)
 break
 }
 p2 := InStr(s, "%", , p1 + 1)
 if (!p2) {
 out .= SubStr(s, pos)
 break
 }
 out .= SubStr(s, pos, p1 - pos)
 var := SubStr(s, p1 + 1, p2 - p1 - 1)

 val := ""
 try {
 val := EnvGet(var)
 } catch {
 val := ""
 }

 out .= (val != "" ? val : "%" var "%")
 pos := p2 + 1
 }
 return out
}




ShowSplash() {
 global SplashGui, SplashMode, SplashVideoPath, SplashVideoMute, SplashVideoPlayFull
 global SplashTopmostGuardMs, SplashDebugOverlay, SplashFailReason
 global SplashMpvPath, SplashMpvPid

 SplashFailReason := ""

 mode := StrLower(Trim(SplashMode))
 vp := NormalizeMediaPath(SplashVideoPath)

 ; Only attempt video if requested and a path is provided.
 useVideo := (mode = "video") && (vp != "")

 if (!useVideo && mode = "video")
 SplashFailReason := "Splash video requested but VideoPath is blank."

 if (useVideo) {
 ; If it's a local file path, verify it exists. (URLs are allowed too.)
 if (!InStr(vp, "://") && !FileExist(vp)) {
 SplashFailReason := "VideoPath not found: " vp
 try LogLine("Splash: " SplashFailReason " (falling back to black)")
 useVideo := false
 }
 }

 if (useVideo) {
 if (StartSplashVideo_MPV(vp))
 return
 ; StartSplashVideo_MPV sets SplashFailReason when it fails.
 }

 ; Black overlay fallback / default (with optional debug text)
 SplashGui := Gui("-Caption +AlwaysOnTop +LastFound +E0x08000000 +E0x20")
 SplashGui.BackColor := "000000"

 if (SplashDebugOverlay && SplashFailReason != "") {
 msg := "Video splash fallback`n`n" SplashFailReason
 SplashGui.SetFont("s14 cFFFFFF", "Segoe UI")
 SplashGui.AddText("x40 y40 w" (A_ScreenWidth-80) " r6 +Center", msg)
 }

 try SetGuiTransparency(255, SplashGui)
 SplashGui.Show("x0 y0 w100 h100 NoActivate")
 try WinMaximize("ahk_id " SplashGui.Hwnd)
}

StartSplashVideo_MPV(vp) {
 global SplashMpvPath, SplashMpvPid, SplashVideoMute, SplashTopmostGuardMs, SplashVideoPlayFull, SplashFailReason

 mpv := NormalizeMediaPath(SplashMpvPath)
 if (mpv = "" || !FileExist(mpv)) {
 if (SplashFailReason = "")
 SplashFailReason := "MPV not configured (set [Splash] MpvPath=... to use MPV backend)."
 return false
 }

 ; Build mpv command line (fullscreen + ontop). MPV handles codecs internally.
 args := '--fullscreen --ontop --no-osc --no-input-default-bindings --keep-open=no --really-quiet'
 ; Optional: force SDR output to avoid display mode switching (HDR/Dolby Vision).
 if (SplashForceSDR) {
        ; Force SDR output to avoid triggering HDR/HDR10 mode switches on TVs.
        ; On Windows this is most reliable with D3D11 + an explicit SDR output colorspace.
        args .= ' --vo=gpu --gpu-api=d3d11 --d3d11-output-csp=srgb --target-colorspace-hint=no'
        args .= ' --target-trc=bt.1886 --target-prim=bt.709 --tone-mapping=clip'
    }
 if (SplashVideoMute)
 args .= ' --mute=yes'
 else
 args .= ' --mute=no'
 ; Ensure file path is quoted
 args .= ' "' vp '"'

 SplashMpvPid := 0
 SplashMpvHwnd := 0
 try {
 Run('"' mpv '" ' args, , , &SplashMpvPid)
 } catch {
 SplashFailReason := "Failed to run mpv.exe."
 SplashMpvPid := 0
 return false
 }

 if (SplashMpvPid) {
 ; Keep mpv on top while splash visible
 if (SplashTopmostGuardMs > 0)
 SetTimer(SplashKeepOnTop, SplashTopmostGuardMs)

 if (SplashVideoPlayFull)
 SetTimer(SplashMonitorExternalVideoEnd, 200)

 return true
 }

 SplashFailReason := "MPV started but no PID returned."
 return false
}

SplashMonitorExternalVideoEnd() {
 global SplashMpvPid, SplashMpvHwnd, SplashVideoPlayFull
 if (!SplashVideoPlayFull)
 return
 ; Prefer window-handle existence over PID (avoids rare PID reuse edge cases).
 if (SplashMpvHwnd) {
 if (!WinExist("ahk_id " SplashMpvHwnd)) {
 FadeOutSplash()
 }
 return
 }
 if (!SplashMpvPid)
 return
 if (!ProcessExist(SplashMpvPid)) {
 FadeOutSplash()
 }
}
; True while one of SteamShell's own interactive windows is on screen.
;
; The splash guard has to yield to these. Its job is covering Steam's startup
; flicker, not covering SteamShell. Both it and these windows are topmost, so
; whichever called SetWindowPos last wins -- and re-asserting twice a second
; means the curtain always wins, burying anything the user just opened within
; SplashTopmostGuardMs. That silently defeated the recovery screen and the
; controller Settings chord, which are the only ways out of a stuck curtain on
; a handheld with no keyboard.
ShellOwnedWindowVisible() {
 global SettingsGui, StartupRecoveryGui, ControllerTestGui, QuickMenuVisible
 if QuickMenuVisible
     return true
 for _, guiRef in [
     IsSet(SettingsGui) ? SettingsGui : 0,
     IsSet(StartupRecoveryGui) ? StartupRecoveryGui : 0,
     IsSet(ControllerTestGui) ? ControllerTestGui : 0] {
     if (IsObject(guiRef) && IsGuiVisible(guiRef))
         return true
 }
 return false
}

SplashKeepOnTop() {
 global SplashGui, SplashMpvPid, SplashMpvHwnd, SplashOverlayGui

 ; Yield the topmost band while the user is looking at one of our own windows.
 ; The curtain stays up and its close timer is untouched; it simply stops
 ; fighting for the front until that window goes away.
 if ShellOwnedWindowVisible()
     return

 ; Keep black splash GUI on top (if used)
 if IsSet(SplashGui) {
 try WinSetAlwaysOnTop(1, "ahk_id " SplashGui.Hwnd)
 }

 ; Keep persistent black cover on top (so Steam never flashes above it)
 if IsSet(SplashOverlayGui) {
 try WinSetAlwaysOnTop(1, "ahk_id " SplashOverlayGui.Hwnd)
 }

 ; Keep MPV window on top (if used)
 if (SplashMpvHwnd) {
 try WinSetAlwaysOnTop(1, "ahk_id " SplashMpvHwnd)
 return
 }

 if (SplashMpvPid) {
 try {
 for _, hwnd in WinGetList("ahk_pid " SplashMpvPid) {
 try WinSetAlwaysOnTop(1, "ahk_id " hwnd)
 }
 } catch {
 }
 }
}
SplashForceClose() {
 ; Safety timeout for PlayFullDuration video mode.
 FadeOutSplash()
}



SetGuiTransparency(alpha, guiObj) {
 ; WinSetTransparent works most reliably when targeting by HWND.
 try WinSetTransparent(alpha, "ahk_id " guiObj.Hwnd)
}

CreateSplashFadeOverlay() {
 global SplashOverlayGui
 ; A layered black overlay we can fade in to hide the video before destroying it.
 try {
 if IsSet(SplashOverlayGui)
 SplashOverlayGui.Destroy()
 } catch {
 }

 SplashOverlayGui := Gui("-Caption +AlwaysOnTop +LastFound +E0x08000000 +E0x20")
 SplashOverlayGui.BackColor := "000000"
 try SetGuiTransparency(0, SplashOverlayGui)
 SplashOverlayGui.Show("x0 y0 w100 h100 NoActivate")
 try WinMaximize("ahk_id " SplashOverlayGui.Hwnd)
}

FadeOutOverlay(ms) {
 global SplashOverlayGui
 if !IsSet(SplashOverlayGui)
 return
 if (ms <= 0) {
 try SetGuiTransparency(0, SplashOverlayGui)
 return
 }
 steps := 30
 sleepMs := Ceil(ms / steps)
 if (sleepMs < 10)
 sleepMs := 10
 if (sleepMs > 60)
 sleepMs := 60

 Loop steps {
 trans := 255 - Round((A_Index / steps) * 255)
 if (trans < 0)
 trans := 0
 try WinSetAlwaysOnTop(1, "ahk_id " SplashOverlayGui.Hwnd)
 try SetGuiTransparency(trans, SplashOverlayGui)
 Sleep(sleepMs)
 }
}


FadeOutSplash() {
 global SplashGui, EnableSplashScreen, SplashFadeOutMs
 global SplashOverlayGui, SplashMpvPid, SplashMpvHwnd, SplashClosing

 if (!EnableSplashScreen)
 return
 if (SplashClosing)
 return
 SplashClosing := true

 ; Stop any splash-related timers
 try SetTimer(SplashKeepOnTop, 0)
 try SetTimer(SplashMonitorExternalVideoEnd, 0)
 try SetTimer(SplashForceClose, 0)

 isMpvVideo := (SplashMpvPid != 0) || (SplashMpvHwnd != 0)

 if (isMpvVideo) {
 ; Ensure we have a black cover and make it fully opaque BEFORE Steam is allowed through.
 try {
 if !IsSet(SplashOverlayGui)
 CreateSplashFadeOverlay()
 try SetGuiTransparency(255, SplashOverlayGui)
 try WinSetAlwaysOnTop(1, "ahk_id " SplashOverlayGui.Hwnd)
 } catch {
 }

 ; Close mpv if still running
 if (SplashMpvPid) {
 try {
 for _, hwnd in WinGetList("ahk_pid " SplashMpvPid) {
 try PostMessage(0x0010, 0, 0, , "ahk_id " hwnd) ; WM_CLOSE
 }
 } catch {
 }
 try ProcessClose(SplashMpvPid)
 }
 SplashMpvPid := 0
 SplashMpvHwnd := 0

 ; Let Steam proceed while the black cover is still covering the screen.
 SetSystemReady()

 ; Fade the cover OUT to reveal Steam.
 try FadeOutOverlay(SplashFadeOutMs)

 try {
 if IsSet(SplashOverlayGui)
 SplashOverlayGui.Destroy()
 } catch {
 }
 SplashOverlayGui := unset

 SplashClosing := false
 return
 }

 ; Black splash: fade the GUI itself
 if !IsSet(SplashGui) {
 SetSystemReady()
 SplashClosing := false
 return
 }

 try {
 if (SplashFadeOutMs > 0) {
 steps := 30
 sleepMs := Ceil(SplashFadeOutMs / steps)
 if (sleepMs < 10)
 sleepMs := 10
 if (sleepMs > 60)
 sleepMs := 60

 Loop steps {
 trans := 255 - Round((A_Index / steps) * 255)
 if (trans < 0)
 trans := 0
 SetGuiTransparency(trans, SplashGui)
 Sleep(sleepMs)
 }
 }
 SplashGui.Destroy()
 } catch {
 }

 SplashGui := unset
 SetSystemReady()
 SplashClosing := false
}

SetSystemReady() {
 global SystemReady
 SystemReady := true
}

; ==============================================================================
; MOUSE
; ==============================================================================
GetMouseParkMonitorBounds(targetHwnd, &left, &top, &right, &bottom) {
 monitor := 0
 if (targetHwnd && DllCall("User32\IsWindow", "Ptr", targetHwnd, "Int"))
     monitor := DllCall(
         "User32\MonitorFromWindow", "Ptr", targetHwnd, "UInt", 2, "Ptr")
 if monitor {
     monitorInfo := Buffer(40, 0)
     NumPut("UInt", monitorInfo.Size, monitorInfo, 0)
     if DllCall(
         "User32\GetMonitorInfoW", "Ptr", monitor,
         "Ptr", monitorInfo.Ptr, "Int") {
         left := NumGet(monitorInfo, 4, "Int")
         top := NumGet(monitorInfo, 8, "Int")
         right := NumGet(monitorInfo, 12, "Int")
         bottom := NumGet(monitorInfo, 16, "Int")
         return right > left && bottom > top
     }
 }
 left := 0
 top := 0
 right := A_ScreenWidth
 bottom := A_ScreenHeight
 return right > left && bottom > top
}

GetWindowsLastInputTick() {
 info := Buffer(8, 0)
 NumPut("UInt", info.Size, info, 0)
 if !DllCall("User32\GetLastInputInfo", "Ptr", info.Ptr, "Int")
     return -1
 return NumGet(info, 4, "UInt")
}

ParkMouseRightEdge(targetHwnd := 0) {
 global MouseParkRightOffsetPx, MouseParkYPercent, MouseParkEdge
 global EnableAutoHideCursor, MouseHidden
 global LastMouseX, LastMouseY, LastMouseMoveTick
 global MouseParkExpectedX, MouseParkExpectedY, MouseParkLastResult
 if !targetHwnd {
     try targetHwnd := WinGetID("A")
 }
 GetMouseParkMonitorBounds(targetHwnd, &left, &top, &right, &bottom)
 ; Keep the pointer two pixels inside the chosen vertical edge. The inset avoids
 ; surfaces interpreting the exact boundary as a pointer-leave event, while
 ; explicit clamping prevents a multi-monitor setup from receiving the pointer.
 inset := 2
 if (MouseParkEdge = "left")
     x := Min(right - 1, left + inset)
 else {
     ; Retain the legacy offset as the amount of intentional push toward the
     ; right; all positive values resolve to the safe inset on that edge.
     desiredX := right + MouseParkRightOffsetPx
     x := Min(Max(desiredX, left), right - 1 - inset)
 }
 y := Min(
     Max(top + Round((bottom - top - 1) * MouseParkYPercent), top),
     bottom - 1)
 MouseParkExpectedX := x
 MouseParkExpectedY := y
 ; MouseMove uses SendInput and therefore advances Windows' last-input clock.
 ; SetCursorPos changes only the pointer location, preserving idle sleep while
 ; still clearing hover highlights after a managed focus transition.
 moved := false
 try moved := DllCall(
     "User32\SetCursorPos", "Int", x, "Int", y, "Int") != 0
 try MouseGetPos(&LastMouseX, &LastMouseY)
 verified := moved && LastMouseX = x && LastMouseY = y
 MouseParkLastResult := verified
     ? "Parked at " x "," y
     : "Failed; requested " x "," y " and found " LastMouseX "," LastMouseY
 LastMouseMoveTick := A_TickCount
 if (EnableAutoHideCursor && !MouseHidden) {
     SystemCursor("Hide")
     MouseHidden := true
 }
 return verified
}

MouseParkTargetStillActive(targetHwnd, &activeHwnd) {
 activeHwnd := 0
 if !targetHwnd
     return false
 try activeHwnd := WinGetID("A")
 if !activeHwnd
     return false
 if (activeHwnd = targetHwnd)
     return true

 ; Steam can change its foreground steamwebhelper surface while Big Picture is
 ; settling. Treat two Steam surfaces—or two windows from one process—as the
 ; same target, but never move the pointer after the user switches elsewhere.
 try {
     targetPid := WinGetPID("ahk_id " targetHwnd)
     activePid := WinGetPID("ahk_id " activeHwnd)
     if (targetPid && targetPid = activePid)
         return true
     targetProc := StrLower(WinGetProcessName("ahk_id " targetHwnd))
     activeProc := StrLower(WinGetProcessName("ahk_id " activeHwnd))
     targetIsSteam := targetProc = "steam.exe"
         || targetProc = "steamwebhelper.exe"
     activeIsSteam := activeProc = "steam.exe"
         || activeProc = "steamwebhelper.exe"
     return targetIsSteam && activeIsSteam
 } catch {
     return false
 }
}

CancelPendingMousePark() {
 global MouseParkPendingHwnd
 SetTimer(CommitPendingMousePark, 0)
 SetTimer(VerifyPendingMousePark, 0)
 MouseParkPendingHwnd := 0
}

ScheduleMouseParkAfterFocus(targetHwnd) {
 global EnableMouseParkOnFocusChange
 global MouseParkPendingHwnd, MouseParkScheduledInputTick
 global MouseParkFocusSettleMs
 if (!EnableMouseParkOnFocusChange || !targetHwnd)
     return false
 SetTimer(CommitPendingMousePark, 0)
 SetTimer(VerifyPendingMousePark, 0)
 MouseParkPendingHwnd := targetHwnd
 MouseParkScheduledInputTick := GetWindowsLastInputTick()
 SetTimer(CommitPendingMousePark, -MouseParkFocusSettleMs)
 return true
}

CommitPendingMousePark(*) {
 global EnableMouseParkOnFocusChange
 global MouseParkPendingHwnd, MouseParkScheduledInputTick
 global MouseParkVerifyDelayMs
 if (!EnableMouseParkOnFocusChange || !MouseParkPendingHwnd) {
     CancelPendingMousePark()
     return
 }
 currentInputTick := GetWindowsLastInputTick()
 if (MouseParkScheduledInputTick >= 0
     && currentInputTick >= 0
     && currentInputTick != MouseParkScheduledInputTick) {
     CancelPendingMousePark()
     return
 }
 if !MouseParkTargetStillActive(MouseParkPendingHwnd, &activeHwnd) {
     CancelPendingMousePark()
     return
 }
 MouseParkPendingHwnd := activeHwnd
 ParkMouseRightEdge(activeHwnd)
 SetTimer(VerifyPendingMousePark, -MouseParkVerifyDelayMs)
}

VerifyPendingMousePark(*) {
 global MouseParkPendingHwnd, MouseParkScheduledInputTick
 global MouseParkExpectedX, MouseParkExpectedY
 if !MouseParkPendingHwnd
     return
 currentInputTick := GetWindowsLastInputTick()
 if (MouseParkScheduledInputTick >= 0
     && currentInputTick >= 0
     && currentInputTick != MouseParkScheduledInputTick) {
     CancelPendingMousePark()
     return
 }
 if !MouseParkTargetStillActive(MouseParkPendingHwnd, &activeHwnd) {
     CancelPendingMousePark()
     return
 }
 mx := 0
 my := 0
 try MouseGetPos(&mx, &my)
 if (mx != MouseParkExpectedX || my != MouseParkExpectedY)
     ParkMouseRightEdge(activeHwnd)
 CancelPendingMousePark()
}

ObserveForegroundForMouseParking() {
 global EnableMouseParkOnFocusChange, ScriptPid
 global MouseParkObservedForegroundHwnd, MouseParkSawNonSteamForeground
 if !EnableMouseParkOnFocusChange
     return
 try {
     hwnd := WinGetID("A")
     if (!hwnd || WinGetPID("ahk_id " hwnd) = ScriptPid)
         return
     if (hwnd = MouseParkObservedForegroundHwnd)
         return
     MouseParkObservedForegroundHwnd := hwnd
     proc := StrLower(WinGetProcessName("ahk_id " hwnd))
     isSteam := proc = "steam.exe" || proc = "steamwebhelper.exe"
     if !isSteam {
         MouseParkSawNonSteamForeground := true
         return
     }
     if MouseParkSawNonSteamForeground {
         MouseParkSawNonSteamForeground := false
         ScheduleMouseParkAfterFocus(hwnd)
     }
 }
}

GetWindowsInputIdleMs() {
 lastInputTick := GetWindowsLastInputTick()
 if (lastInputTick < 0)
     return -1
 currentTick := DllCall("Kernel32\GetTickCount", "UInt")
 return (currentTick - lastInputTick) & 0xFFFFFFFF
}

HideCursorWithoutInput(forceNow := false) {
 global EnableAutoHideCursor, MouseHidden
 global LastMouseX, LastMouseY, LastMouseMoveTick, MouseHideDelay
 if (!EnableAutoHideCursor)
     return

 ; Snapshot the real pointer position without swallowing recent physical
 ; movement that MouseWatch has not seen yet.
 mx := LastMouseX
 my := LastMouseY
 try MouseGetPos(&mx, &my)
 if (!forceNow && (mx != LastMouseX || my != LastMouseY)) {
     LastMouseX := mx
     LastMouseY := my
     LastMouseMoveTick := A_TickCount
     if (MouseHidden) {
         SystemCursor("Show")
         MouseHidden := false
     }
     return
 }
 LastMouseX := mx
 LastMouseY := my
 if (!forceNow && A_TickCount - LastMouseMoveTick < MouseHideDelay)
     return
 if (!MouseHidden) {
     SystemCursor("Hide")
     MouseHidden := true
 }
}

MaybeHideCursorOnRefocus() {
 global EnableCursorHideOnRefocus
 if (EnableCursorHideOnRefocus)
     HideCursorWithoutInput(false)
}

HandleCursorAfterManagedFocus(hwnd, wasAlreadyActive := false) {
 global EnableMouseParkOnFocusChange, AllowExplorer
 ; Parking or hiding the pointer belongs to the Steam-first presentation. On the
 ; restored Explorer desktop the cursor is the user's primary input.
 if (AllowExplorer)
     return
 focusChanged := !wasAlreadyActive
 if (focusChanged && hwnd) {
     focusChanged := false
     try focusChanged := WinActive("ahk_id " hwnd) != 0
 }
 if (focusChanged && EnableMouseParkOnFocusChange)
     ScheduleMouseParkAfterFocus(hwnd)
 else
     MaybeHideCursorOnRefocus()
}

SystemCursor(mode := "Show") {
 static AndM := Buffer(128, 0xFF)
 static XorM := Buffer(128, 0)
 static Cursors := [32512,32513,32514,32515,32516,32640,32641,32642,32643,32644,32645,32646,32648,32649,32650,32651]
 if (mode = "Hide") {
 for _, id in Cursors {
 hCur := DllCall("CreateCursor","Ptr",0,"Int",0,"Int",0,"Int",32,"Int",32,"Ptr",AndM,"Ptr",XorM,"Ptr")
 DllCall("SetSystemCursor","Ptr",hCur,"Int",id)
 }
 } else {
 DllCall("SystemParametersInfo","UInt",0x57,"UInt",0,"Ptr",0,"UInt",0)
 }
}

MouseWatch() {
 global AllowExplorer, EnableAutoHideCursor, MouseHidden
 global LastMouseX, LastMouseY, LastMouseMoveTick, MouseHideDelay

 if (AllowExplorer || !EnableAutoHideCursor)
 return

 MouseGetPos(&mx, &my)
 if (mx != LastMouseX || my != LastMouseY) {
 LastMouseX := mx
 LastMouseY := my
 LastMouseMoveTick := A_TickCount
 if (MouseHidden) {
 SystemCursor("Show")
 MouseHidden := false
 }
 return
 }

 if (!MouseHidden && (A_TickCount - LastMouseMoveTick >= MouseHideDelay)) {
 SystemCursor("Hide")
 MouseHidden := true
 }
}


; ==============================================================================
; CONTROLLER MOUSE MODE (XInput / Xbox controller)
; - Hold View/Back to temporarily enable mouse mode.
; - While held:
; Left stick => mouse move (RT = fast)
; Right stick => scroll
; A => Left click
; B => Right click
; X => Enter
; Y => Win+G
; LB => Ctrl+Alt+Tab
; RB => Ctrl+Shift+Esc (Task Manager)
; LThumb => Toggle drag-lock (hold/release left button)
; RThumb => Touch keyboard (TabTip/OSK)
; D-Pad => Arrow keys
; ==============================================================================
InitXInput() {
 global XInputDll
 if (XInputDll != "")
 return true

 ; Prefer modern XInput, fall back as needed.
 for _, dll in ["xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"] {
 try {
 if (DllCall("GetModuleHandle", "Str", dll, "Ptr") || DllCall("LoadLibrary", "Str", dll, "Ptr")) {
 XInputDll := dll
 return true
 }
 } catch {
 }
 }
 XInputDll := ""
 return false
}

XInputGetState(index, &bufState) {
 global XInputDll
 if (XInputDll = "" && !InitXInput())
 return 1167 ; ERROR_DEVICE_NOT_CONNECTED-ish

 ; XINPUT_STATE is 16 bytes: DWORD packet + XINPUT_GAMEPAD (12 bytes)
 if !IsObject(bufState)
 bufState := Buffer(16, 0)

 ; Prefer the standard XInputGetState for maximum compatibility (View/Back, sticks, triggers).
 ; Best-effort: also OR in the Guide bit via XInputGetStateEx (ordinal 100) when available.
 try {
 rc := DllCall(XInputDll "\XInputGetState", "UInt", index, "Ptr", bufState, "UInt")
 if (rc = 0) {
 ; Try to read the Guide bit (0x0400) if Ex is available.
 try {
 ex := Buffer(16, 0)
 if (DllCall(XInputDll "\100", "UInt", index, "Ptr", ex, "UInt") = 0) {
 bEx := NumGet(ex, 4, "UShort")
 if (bEx & 0x0400) {
 b := NumGet(bufState, 4, "UShort")
 NumPut("UShort", b | 0x0400, bufState, 4)
 }
 }
 } catch {
 ; ignore Ex failures
 }
 }
 return rc
 } catch {
 ; Fall back: if standard export fails for any reason, try Ex directly.
 try {
 return DllCall(XInputDll "\100", "UInt", index, "Ptr", bufState, "UInt")
 } catch {
 ; If the DLL is weird, reset and retry next time.
 XInputDll := ""
 return 1
 }
 }
}

ControllerTestActive() {
 global ControllerTestGui
 if !IsSet(ControllerTestGui)
     return false
 try return IsGuiVisible(ControllerTestGui)
 return false
}

ControllerButtonNames(buttons) {
 names := []
 definitions := [
     ["D-pad Up", 0x0001], ["D-pad Down", 0x0002],
     ["D-pad Left", 0x0004], ["D-pad Right", 0x0008],
     ["Start", 0x0010], ["View / Back", 0x0020],
     ["L3", 0x0040], ["R3", 0x0080],
     ["LB", 0x0100], ["RB", 0x0200], ["Xbox", 0x0400],
     ["A", 0x1000], ["B", 0x2000], ["X", 0x4000], ["Y", 0x8000]
 ]
 for _, definition in definitions {
     if (buttons & definition[2])
         names.Push(definition[1])
 }
 return names.Length ? JoinWith(names, "  •  ") : "None"
}

UpdateControllerTest(buttons, lt, rt, lx, ly, rx, ry) {
 global ControllerTestGui, ControllerCalibrationUntil
 global ControllerCalibrationMax, ControllerSuggestedDeadzone
 if !ControllerTestActive()
     return

 try {
     ControllerTestGui["ControllerButtons"].Text := ControllerButtonNames(buttons)
     ControllerTestGui["ControllerTriggers"].Text :=
         "LT " lt " / 255        RT " rt " / 255"
     ControllerTestGui["ControllerAxes"].Text :=
         "Left stick     X " lx "     Y " ly
         . "`r`nRight stick   X " rx "     Y " ry
 }

 if (ControllerCalibrationUntil > 0) {
     ControllerCalibrationMax := Max(
         ControllerCalibrationMax, Abs(lx), Abs(ly), Abs(rx), Abs(ry))
     remainingMs := ControllerCalibrationUntil - A_TickCount
     if (remainingMs > 0) {
         try ControllerTestGui["ControllerCalibration"].Text :=
             "Sampling centered sticks… " Ceil(remainingMs / 1000) " sec"
     } else {
         ControllerCalibrationUntil := 0
         ControllerSuggestedDeadzone := ClampInt(
             ControllerCalibrationMax + 1500, 1000, 16000)
         try ControllerTestGui["ControllerCalibration"].Text :=
             "Maximum centered drift: " ControllerCalibrationMax
             . "     Suggested deadzone: " ControllerSuggestedDeadzone
     }
 }
}

StartControllerCenterSample(*) {
 global ControllerCalibrationUntil, ControllerCalibrationMax
 global ControllerSuggestedDeadzone
 ControllerCalibrationMax := 0
 ControllerSuggestedDeadzone := 0
 ControllerCalibrationUntil := A_TickCount + 3000
}

ApplyControllerSuggestedDeadzone(*) {
 global ControllerSuggestedDeadzone, ControllerDeadzone
 global ControllerTestGui, SettingsEditorUpdating
 if (ControllerSuggestedDeadzone <= 0) {
     try ControllerTestGui["ControllerCalibration"].Text :=
         "Run the three-second center sample before applying a recommendation."
     return
 }
 if !CommitIniChanges([
     Map(
         "section", "Controller",
         "key", "ControllerDeadzone",
         "value", ControllerSuggestedDeadzone)
 ]) {
     try ControllerTestGui["ControllerCalibration"].Text :=
         "SteamShell could not save the recommended deadzone."
     return
 }
 ControllerDeadzone := ControllerSuggestedDeadzone
 field := SettingsEditorFindField("Controller", "ControllerDeadzone")
 if IsObject(field) {
     SettingsEditorUpdating := true
     field["ctrl"].Value := ControllerDeadzone
     SettingsEditorUpdating := false
 }
 try ControllerTestGui["ControllerCalibration"].Text :=
     "Deadzone " ControllerDeadzone " saved and applied."
}

HideControllerTest(*) {
 global ControllerTestGui
 if IsSet(ControllerTestGui)
     try ControllerTestGui.Hide()
 ApplyRuntimeTimers()
}

ShowControllerTest(*) {
 global ControllerTestGui, ControllerDeadzone, ControllerPollIntervalMs
 if !IsSet(ControllerTestGui) {
     ControllerTestGui := Gui("+AlwaysOnTop +ToolWindow -Resize", "SteamShell Controller Test")
     ControllerTestGui.SetFont("s10", "Segoe UI")
     title := ControllerTestGui.AddText("xm ym w620 h30", "Controller Test and Calibration")
     title.SetFont("s17 Bold", "Segoe UI")
     ControllerTestGui.AddText(
         "xm y+2 w620 h38 +Wrap",
         "Inputs are captured by this window and are not sent through SteamShell mappings while the test is open.")
     ControllerTestGui.AddGroupBox("xm y+8 w620 h72", "Pressed buttons")
     ControllerTestGui.AddText(
         "xp+14 yp+27 w590 h30 vControllerButtons +Wrap", "Waiting for controller input…")
     ControllerTestGui.AddGroupBox("xm y+10 w620 h66", "Triggers")
     ControllerTestGui.AddText(
         "xp+14 yp+27 w590 h24 vControllerTriggers", "LT 0 / 255        RT 0 / 255")
     ControllerTestGui.AddGroupBox("xm y+10 w620 h92", "Raw stick axes")
     ControllerTestGui.AddText(
         "xp+14 yp+26 w590 h52 vControllerAxes",
         "Left stick     X 0     Y 0`r`nRight stick   X 0     Y 0")
     ControllerTestGui.AddText(
         "xm y+10 w620 h42 +Wrap",
         "Leave both sticks untouched, then sample their centered drift. Current deadzone: " ControllerDeadzone)
     ControllerTestGui.AddText(
         "xm y+2 w620 h28 vControllerCalibration", "No center sample has been recorded.")
     sampleButton := ControllerTestGui.AddButton("xm y+8 w205 h32", "Sample Center for 3 Seconds")
     sampleButton.OnEvent("Click", StartControllerCenterSample)
     applyButton := ControllerTestGui.AddButton("x+8 yp w205 h32", "Apply Suggested Deadzone")
     applyButton.OnEvent("Click", ApplyControllerSuggestedDeadzone)
     closeButton := ControllerTestGui.AddButton("x+8 yp w120 h32", "Close")
     closeButton.OnEvent("Click", HideControllerTest)
     ControllerTestGui.OnEvent("Close", HideControllerTest)
     ControllerTestGui.OnEvent("Escape", HideControllerTest)
 }
 ControllerTestGui.Show()
 CenterGuiOnTargetMonitor(ControllerTestGui)
 SetTimer(PollController, ControllerPollIntervalMs)
}

TryInvokeTouchKeyboard() {
 ; Windows 11 can keep TabTip/TextInputHost running without presenting the
 ; keyboard. Ask the same UI host used by the taskbar touch-keyboard button to
 ; toggle its visible pane instead of treating process launch as presentation.
 static clsidText := "{4CE576FA-83DC-4F88-951C-9D0782B4E376}"
 static iidText := "{37C994E7-432B-4834-A2F7-DCE1F13B834B}"
 clsid := Buffer(16, 0)
 iid := Buffer(16, 0)
 tip := 0

 if (DllCall("Ole32\CLSIDFromString", "WStr", clsidText, "Ptr", clsid.Ptr, "Int") != 0
     || DllCall("Ole32\CLSIDFromString", "WStr", iidText, "Ptr", iid.Ptr, "Int") != 0)
     return false

 ; CLSCTX_INPROC_SERVER | CLSCTX_LOCAL_SERVER
 hr := DllCall(
     "Ole32\CoCreateInstance",
     "Ptr", clsid.Ptr,
     "Ptr", 0,
     "UInt", 0x5,
     "Ptr", iid.Ptr,
     "Ptr*", &tip,
     "Int")
 if (hr < 0 || !tip)
     return false

 succeeded := false
 try {
     vtable := NumGet(tip, 0, "Ptr")
     toggleMethod := NumGet(vtable, 3 * A_PtrSize, "Ptr")
     desktopHwnd := DllCall("User32\GetDesktopWindow", "Ptr")
     hr := DllCall(toggleMethod, "Ptr", tip, "Ptr", desktopHwnd, "Int")
     succeeded := hr >= 0
 } catch as err {
     try LogLine("Touch keyboard presentation request failed: " err.Message)
 } finally {
     try {
         vtable := NumGet(tip, 0, "Ptr")
         releaseMethod := NumGet(vtable, 2 * A_PtrSize, "Ptr")
         DllCall(releaseMethod, "Ptr", tip, "UInt")
     }
 }
 return succeeded
}

RunViaDesktopShell(filePath, arguments := "", directory := "", show := 1) {
 ; ShellExecute through Explorer's desktop automation object so an elevated
 ; SteamShell does not force ordinary interactive utilities such as TabTip to
 ; inherit its administrator token.
 static VT_UI4 := 0x13
 static SWC_DESKTOP := ComValue(VT_UI4, 0x8)

 try {
     ComObject("Shell.Application").Windows.Item(SWC_DESKTOP).Document.Application
         .ShellExecute(filePath, arguments, directory, "open", show)
     return true
 } catch as err {
     try LogLine("Desktop-shell launch failed for " filePath ": " err.Message)
     return false
 }
}

OpenTouchKeyboard() {
 ; Present the modern touch keyboard without terminating Windows text-input
 ; processes. Killing TextInputHost can leave desktop/custom-shell systems
 ; unable to show a keyboard even though the taskbar button still works.
 static tabtip1 := A_ProgramFiles "\Common Files\microsoft shared\ink\TabTip.exe"
 static tabtip2 := ""

 if (tabtip2 = "") {
 try {
 pf86 := EnvGet("ProgramFiles(x86)")
 if (pf86 != "")
 tabtip2 := pf86 "\Common Files\microsoft shared\ink\TabTip.exe"
 }
 }

 ; If it's already present, just show/activate it.
 if WinExist("ahk_class IPTip_Main_Window") {
 try WinShow("ahk_class IPTip_Main_Window")
 try WinActivate("ahk_class IPTip_Main_Window")
 return
 }

 ; A successful request is equivalent to pressing the taskbar keyboard button.
 if TryInvokeTouchKeyboard()
     return

 tabtipPath := ""
 if FileExist(tabtip1)
     tabtipPath := tabtip1
 else if (tabtip2 != "" && FileExist(tabtip2))
     tabtipPath := tabtip2
 if (tabtipPath = "") {
     try LogLine("Touch keyboard executable was not found; opening classic OSK.")
     OpenOSK()
     return
 }
 SplitPath(tabtipPath, , &tabtipDir)

 ; Older builds may require TabTip to be started once before the presentation
 ; interface becomes available. Use Explorer's desktop token because
 ; SteamShell itself normally runs elevated for Task Manager compatibility.
 if !ProcessExist("TabTip.exe") {
     if !RunViaDesktopShell(tabtipPath, "", tabtipDir) {
         try LogLine("Touch keyboard desktop launch was unavailable; opening classic OSK.")
         OpenOSK()
         return
     }
 }
 Sleep 250

 if TryInvokeTouchKeyboard()
     return

 ; Microsoft documents /SeekDesktop for unusual interactive desktops. It is a
 ; final modern-keyboard fallback for the SteamShell custom-shell environment.
 ; Keep this request at the desktop shell's integrity level as well.
 if RunViaDesktopShell(tabtipPath, "/SeekDesktop", tabtipDir) {
     try LogLine("Touch keyboard /SeekDesktop fallback requested.")
 } else {
     try LogLine("Touch keyboard fallback was unavailable; opening classic OSK.")
     OpenOSK()
 }
}




OpenOSK() {
 ; Always open the classic On-Screen Keyboard.
 try Run("osk.exe")
}

; ==============================================================================
; CONTROLLER MAPPING (configurable short/long press)
; ==============================================================================

InitDefaultControllerMappings() {
 global ControllerMap, ControllerMapDisplay
 ControllerMap := Map()
 ControllerMapDisplay := Map()

 ; Defaults (while holding View/Back)
 ; Note: Sticks + D-pad behavior are fixed (mouse move / scroll / arrows).
 ControllerMap["RB.Short"] := "Builtin:LeftClick"
 ControllerMap["RB.Long"] := "Builtin:None"

 ControllerMap["RT.Short"] := "Builtin:RightClick"
 ControllerMap["RT.Long"] := "Builtin:None"

 ControllerMap["LT.Short"] := "Send:^+o"
 ControllerMapDisplay["LT.Short"] := "Ctrl+Shift+O"
 ControllerMap["LT.Long"] := "Send:^+f"
 ControllerMapDisplay["LT.Long"] := "Ctrl+Shift+F"

 ControllerMap["LB.Short"] := "Send:^!{Tab}"
 ControllerMapDisplay["LB.Short"] := "Ctrl+Alt+Tab"
 ControllerMap["LB.Long"] := "Builtin:TaskManager"

 ControllerMap["A.Short"] := "Builtin:Enter"
 ControllerMap["A.Long"] := "Builtin:None"

 ControllerMap["B.Short"] := "Builtin:Esc"
 ControllerMap["B.Long"] := "Builtin:AltF4"

 ControllerMap["X.Short"] := "Builtin:TabTip"
 ControllerMap["X.Long"] := "Builtin:OSK"

 ControllerMap["Y.Short"] := "Builtin:WinG"
 ControllerMap["Y.Long"] := "Builtin:None"


 ; While View/Back is held, tap Start for the Windows Start menu or hold it
 ; for File Explorer. Both remain fully customizable in the mapping editor.
 ControllerMap["Start.Short"] := "Builtin:StartMenu"
 ControllerMap["Start.Long"] := "Builtin:Explorer"


 ; Stick clicks (default: unassigned)
 ControllerMap["L3.Short"] := "Builtin:None"
 ControllerMap["L3.Long"] := "Builtin:None"
 ControllerMap["R3.Short"] := "Builtin:None"
 ControllerMap["R3.Long"] := "Builtin:None"
}

LoadControllerMappings() {
 global IniPath, ControllerMap, ControllerMapDisplay
 if !FileExist(IniPath) {
 InitDefaultControllerMappings()
 return
 }

 InitDefaultControllerMappings() ; start from defaults and override

 ; Buttons we support in the editor
 keys := [
 "A.Short","A.Long","B.Short","B.Long","X.Short","X.Long","Y.Short","Y.Long",
 "LB.Short","LB.Long","RB.Short","RB.Long","LT.Short","LT.Long","RT.Short","RT.Long",
 "Start.Short","Start.Long",
 "L3.Short","L3.Long","R3.Short","R3.Long"
 ]

 for k in keys {
 v := ""
 try v := IniRead(IniPath, "ControllerMap", k, "")
 if (v = "")
 continue

 if (SubStr(v, 1, 5) = "Send:") {
 send := SubStr(v, 6)
 ControllerMap[k] := v
 disp := ""
 try disp := IniRead(IniPath, "ControllerMap", k ".Display", "")
 if (disp = "")
 disp := SendToPretty(send)
 ControllerMapDisplay[k] := disp
 } else if (SubStr(v, 1, 8) = "Builtin:") {
 ControllerMap[k] := v
 } else {
 ; Back-compat: if user stored raw send string, treat as Send:
 ControllerMap[k] := "Send:" v
 ControllerMapDisplay[k] := SendToPretty(v)
 }
 }

 ; Fallback migration for a settings file that could not be schema-upgraded.
 if (ControllerMap["Start.Short"] = "Builtin:QuickMenu"
     && ControllerMap["Start.Long"] = "Builtin:ControlPanel") {
     ControllerMap["Start.Short"] := "Builtin:StartMenu"
     ControllerMap["Start.Long"] := "Builtin:Explorer"
     CommitIniChanges([
         Map("section", "ControllerMap", "key", "Start.Short", "value", "Builtin:StartMenu"),
         Map("section", "ControllerMap", "key", "Start.Long", "value", "Builtin:Explorer")
     ])
 }
}

SaveControllerMappingsToIni() {
 global ControllerMap, ControllerMapDisplay
 changes := []
 deletes := []
 for k, v in ControllerMap {
 changes.Push(Map("section", "ControllerMap", "key", k, "value", v))
 if (SubStr(v, 1, 5) = "Send:") {
 disp := ""
 try disp := ControllerMapDisplay[k]
 if (disp != "")
 changes.Push(Map("section", "ControllerMap", "key", k ".Display", "value", disp))
 } else {
 ; remove stale display values for builtins
 deletes.Push(Map("section", "ControllerMap", "key", k ".Display"))
 }
 }
 return CommitIniChanges(changes, deletes)
}

HasLongBinding(btnKey) {
 global ControllerMap
 v := ""
 try v := ControllerMap[btnKey ".Long"]
 return (v != "" && v != "Builtin:None")
}

GetBindingValue(key) {
 global ControllerMap
 try {
 return ControllerMap[key]
 } catch {
 return ""
 }
}


SendChordSafe(keys) {
 ; Helps avoid "stuck modifier" states and improves reliability for system chords.
 ; Note: This cannot generate secure sequences like Ctrl+Alt+Del.
 try SendInput("{Ctrl up}{Alt up}{Shift up}{LWin up}{RWin up}")
 try SendInput(keys)
}

; Steam's in-game overlay hook can miss SendInput's effectively instantaneous
; modifier pulse. SendEvent honours the press duration from SetKeyDelay, giving
; Steam a real Shift-down window in which to observe Tab. The configured
; shortcut is retained so custom overlay chords receive the same treatment.
SendSteamOverlayChord() {
 global SteamOverlayShortcut
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
     SetKeyDelay(35, 80)
     SendEvent(SteamOverlayShortcut)
     sent := true
 } catch as err {
     LogLine("Steam overlay send failed: " err.Message)
 }
 ; Always release modifiers, including after a partial send failure.
 try SendEvent("{Ctrl up}{Alt up}{Shift up}{LWin up}{RWin up}")
 return sent
}


ExecuteControllerBinding(key) {
 v := GetBindingValue(key)
 if (v = "" || v = "Builtin:None")
 return

 if (SubStr(v, 1, 5) = "Send:") {
 send := SubStr(v, 6)
 if (send != "")
 SendChordSafe(send)
 return
 }

 if (SubStr(v, 1, 8) != "Builtin:")
 return

 act := SubStr(v, 9)
 switch act {
 case "LeftClick":
 try Click("Left")
 case "RightClick":
 try Click("Right")
 case "Enter":
 try SendInput("{Enter}")
 case "Esc":
 try SendInput("{Esc}")
 case "AltF4":
 ; Use explicit chord send for reliability
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
 case "QuickMenu":
 ToggleQuickMenu()
 case "ControlPanel":
 ShowControlPanel()
 default:
 ; unknown builtin - ignore
 }
}

SendToPretty(sendStr) {
 ; Consume only the actual modifier prefix. Replacing "^" with "Ctrl+" and
 ; subsequently replacing every "+" made the inserted separator look like a
 ; Shift modifier, so "^1" was incorrectly displayed as "CtrlShift+1".
 static modifiers := Map("#", "Win+", "^", "Ctrl+", "!", "Alt+", "+", "Shift+")
 text := Trim(sendStr)
 prefix := ""
 while (text != "" && modifiers.Has(SubStr(text, 1, 1))) {
     prefix .= modifiers[SubStr(text, 1, 1)]
     text := SubStr(text, 2)
 }
 text := StrReplace(StrReplace(text, "{", ""), "}", "")
 return prefix text
}


GetPhysicalModsMap() {
 return Map(
 "Ctrl", (GetKeyState("Ctrl", "P") || GetKeyState("Control", "P") || GetKeyState("LControl", "P") || GetKeyState("RControl", "P")),
 "Alt", (GetKeyState("Alt", "P") || GetKeyState("Menu", "P") || GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P") || GetKeyState("LMenu", "P") || GetKeyState("RMenu", "P")),
 "Shift", (GetKeyState("Shift", "P") || GetKeyState("LShift", "P") || GetKeyState("RShift", "P")),
 "Win", (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
 )
}

RecordShortcutChord() {
 ; Records a single shortcut chord (modifiers + one key) without typing.
 ; Returns Map("ok", true/false, "send", "^!{Tab}", "display", "Ctrl+Alt+Tab")
 global _ShortcutCap
 res := Map("ok", false, "send", "", "display", "")

 cap := Gui("+AlwaysOnTop -MinimizeBox +ToolWindow", "Record Shortcut")
 cap.SetFont("s10")
 cap.AddText("xm", "Press your shortcut (modifiers + one key).")
 cap.AddText("xm y+4", "Click OK to accept. Esc cancels.")
 cap.SetFont("s10", "Consolas")
 txtCur := cap.AddText("xm y+8 w420 vtxtCur", "(none)")
 cap.SetFont("s10")
 btnOk := cap.AddButton("xm y+10 w90 Default", "OK")
 btnCancel := cap.AddButton("x+10 w90", "Cancel")

 _ShortcutCap := Map(
 "gui", cap,
 "txt", txtCur,
 "ih", 0,
 "mainKey", "",
 "liveMods", Map("Ctrl", false, "Alt", false, "Shift", false, "Win", false),
 "snapMods", Map("Ctrl", false, "Alt", false, "Shift", false, "Win", false),
 "done", false,
 "cancelled", false
 )

 btnOk.OnEvent("Click", RecordShortcutChord_Accept)
 btnCancel.OnEvent("Click", RecordShortcutChord_Cancel)
 cap.OnEvent("Close", RecordShortcutChord_Cancel)
 cap.OnEvent("Escape", RecordShortcutChord_Cancel)

 ; Suppress the chord while recording so Win, Alt, and application shortcuts
 ; do not execute behind this dialog.
 ih := InputHook()
 ih.NotifyNonText := true
 ih.KeyOpt("{All}", "NS")
 ih.OnKeyDown := RecordShortcutChord_OnKeyDown
 ih.OnKeyUp := RecordShortcutChord_OnKeyUp
 _ShortcutCap["ih"] := ih

 cap.Show("AutoSize Center")
 ih.Start()

 ; Wait until OK/Cancel
 while IsObject(_ShortcutCap) && !_ShortcutCap["done"] {
 Sleep 30
 }

 ; Finalize
 if !IsObject(_ShortcutCap)
 return res

 cancelled := _ShortcutCap["cancelled"]
 mainKey := _ShortcutCap["mainKey"]
 mods := _ShortcutCap["snapMods"]

 try {
 _ShortcutCap["ih"].Stop()
 } catch {
 }
 try {
 _ShortcutCap["gui"].Destroy()
 } catch {
 }

 _ShortcutCap := ""

 if (cancelled || mainKey = "")
 return res

 send := ""
 display := ""

 if (mods["Ctrl"]) {
 send .= "^"
 display .= "Ctrl+"
 }
 if (mods["Alt"]) {
 send .= "!"
 display .= "Alt+"
 }
 if (mods["Shift"]) {
 send .= "+"
 display .= "Shift+"
 }
 if (mods["Win"]) {
 send .= "#"
 display .= "Win+"
 }

 send .= NormalizeKeyForSend(mainKey)
 display .= NormalizeKeyForDisplay(mainKey)

 res["ok"] := true
 res["send"] := send
 res["display"] := display
 return res
}

RecordShortcutChord_OnKeyDown(ihObj, vk, sc) {
 global _ShortcutCap
 if !IsObject(_ShortcutCap)
 return

 keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
 if (keyName = "" || keyName = "Unknown")
 return

 ; Esc cancels
 if (keyName = "Escape") {
 RecordShortcutChord_Cancel()
 return
 }
 ; Track modifiers robustly (InputHook key names vary by system).
 if RecordShortcutChord_TrySetMod(keyName, true) {
 if (_ShortcutCap["mainKey"] = "")
 RecordShortcutChord_UpdatePreview()
 return
 }

 ; Snapshot modifiers at the moment the main key is pressed.
 _ShortcutCap["mainKey"] := keyName
 _ShortcutCap["snapMods"] := RecordShortcutChord_GetSnapshotMods()

 ; Update preview to show the recorded chord (even after user releases keys)
 RecordShortcutChord_UpdatePreview()
}


RecordShortcutChord_OnKeyUp(ihObj, vk, sc) {
 global _ShortcutCap
 if !IsObject(_ShortcutCap)
 return

 keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
 if (keyName = "" || keyName = "Unknown")
 return

 ; Update live modifier state for preview purposes.
 if RecordShortcutChord_TrySetMod(keyName, false) {
 if (_ShortcutCap["mainKey"] = "")
 RecordShortcutChord_UpdatePreview()
 return
 }
}

RecordShortcutChord_TrySetMod(keyName, isDown) {
 global _ShortcutCap
 if !IsObject(_ShortcutCap)
 return false

 mod := ""
 switch keyName {
 case "Ctrl", "Control", "LControl", "RControl", "LCtrl", "RCtrl":
 mod := "Ctrl"
 case "Alt", "LAlt", "RAlt", "Menu", "LMenu", "RMenu":
 mod := "Alt"
 case "Shift", "LShift", "RShift":
 mod := "Shift"
 case "Win", "LWin", "RWin":
 mod := "Win"
 default:
 return false
 }

 try {
 if !IsObject(_ShortcutCap["liveMods"])
 _ShortcutCap["liveMods"] := Map("Ctrl", false, "Alt", false, "Shift", false, "Win", false)
 _ShortcutCap["liveMods"][mod] := isDown
 } catch {
 return false
 }
 return true
}

RecordShortcutChord_GetLiveMods() {
 global _ShortcutCap
 m := Map("Ctrl", false, "Alt", false, "Shift", false, "Win", false)

 ; Prefer the live-mod state we maintain from InputHook events.
 lm := ""
 try {
 lm := _ShortcutCap["liveMods"]
 } catch {
 lm := ""
 }
 if IsObject(lm) {
 for k, v in lm {
 if v
 m[k] := true
 }
 }

 ; Also OR in the physical state as a fallback (some systems don't notify mod keys consistently).
 pm := ""
 try {
 pm := GetPhysicalModsMap()
 } catch {
 pm := ""
 }
 if IsObject(pm) {
 for k, v in pm {
 if v
 m[k] := true
 }
 }
 return m
}

RecordShortcutChord_GetSnapshotMods() {
 ; Snapshot "best effort" modifiers at the instant the main key is pressed.
 ; Uses both our live-mod tracking and physical key state.
 return RecordShortcutChord_GetLiveMods()
}

RecordShortcutChord_UpdatePreview() {
 global _ShortcutCap
 if !IsObject(_ShortcutCap)
 return

 mainKey := _ShortcutCap["mainKey"]

 s := ""

 if (mainKey != "") {
 ; After a main key is captured, show the snapped chord.
 mods := _ShortcutCap["snapMods"]
 if (mods["Ctrl"])
 s .= "Ctrl+"
 if (mods["Alt"])
 s .= "Alt+"
 if (mods["Shift"])
 s .= "Shift+"
 if (mods["Win"])
 s .= "Win+"
 s .= NormalizeKeyForDisplay(mainKey)
 } else {
 ; Before capture, show live modifiers as the user holds them.
 mods := RecordShortcutChord_GetLiveMods()
 if (mods["Ctrl"])
 s .= "Ctrl+"
 if (mods["Alt"])
 s .= "Alt+"
 if (mods["Shift"])
 s .= "Shift+"
 if (mods["Win"])
 s .= "Win+"
 if (s = "")
 s := "(none)"
 }

 try _ShortcutCap["txt"].Text := s
}

RecordShortcutChord_Accept(*) {
 global _ShortcutCap
 if !IsObject(_ShortcutCap)
 return

 ; Ensure we at least have a snapped mod map even if user never pressed a main key.
 if !IsObject(_ShortcutCap["snapMods"])
 _ShortcutCap["snapMods"] := Map("Ctrl", false, "Alt", false, "Shift", false, "Win", false)

 _ShortcutCap["done"] := true
}

RecordShortcutChord_Cancel(*) {
 global _ShortcutCap
 if !IsObject(_ShortcutCap)
 return
 _ShortcutCap["cancelled"] := true
 try _ShortcutCap["ih"].Stop()
 _ShortcutCap["done"] := true
}


NormalizeKeyForSend(keyName) {
 ; Convert key name to a Send-compatible token.
 ; For multi-character names, wrap in braces: {Tab}, {Esc}, {F1}, {Left}, etc.
 k := keyName
 if (k = "Escape")
 k := "Esc"
 if (k = "Return")
 k := "Enter"
 if (StrLen(k) > 1)
 return "{" k "}"
 return k
}

NormalizeKeyForDisplay(keyName) {
 k := keyName
 if (k = "Escape")
 return "Esc"
 if (k = "Return")
 return "Enter"
 return k
}

; ==============================================================================
; CONTROLLER-FIRST QUICK MENU
; ==============================================================================
ToggleQuickMenu(*) {
 global QuickMenuVisible, EnableQuickMenu
 if (!EnableQuickMenu) {
     ShowNotification("Quick Menu is disabled in SteamShellSettings.ini", "Warning")
     return
 }
 if (QuickMenuVisible)
     HideQuickMenu()
 else
     ShowQuickMenu()
}

ShowQuickMenu(*) {
 global QuickMenuVisible, QuickMenuPreviousHwnd, QuickMenuPage, QuickMenuSelected
 global QuickMenuGui, ScriptPid

 if (QuickMenuVisible)
     return

 QuickMenuPreviousHwnd := 0
 try {
     hwnd := WinGetID("A")
     pid := WinGetPID("ahk_id " hwnd)
     if (pid != ScriptPid)
         QuickMenuPreviousHwnd := hwnd
 }

 QuickMenuVisible := true
 QuickMenuPage := "MAIN"
 QuickMenuSelected := 1
 QuickMenuBuildGui()
 if IsSet(QuickMenuGui) {
     gotFocus := ForceForegroundWindow(QuickMenuGui.Hwnd)
     if !gotFocus {
         LogLine("Quick Menu was shown but did not initially acquire the "
             . "foreground. Held by: " DescribeForegroundWindow())
         SetTimer(QuickMenuEnsureForeground, -75)
     }
     HandleCursorAfterManagedFocus(QuickMenuGui.Hwnd, false)
 }
}

; Names what actually holds the foreground.
;
; "The handoff failed" is not actionable on its own. A game holding focus, Steam
; holding it, and a Windows surface holding it need completely different
; responses, and this log line is the only place the difference can be seen. The
; monitor-coverage note is there because an exclusive-fullscreen game is the
; usual reason the handoff is refused, and it cannot be told apart from a
; borderless one by process name.
DescribeForegroundWindow() {
 hwnd := 0
 try hwnd := DllCall("User32\GetForegroundWindow", "Ptr")
 if !hwnd
     return "nothing (no foreground window)"
 proc := "?"
 cls := "?"
 try proc := WinGetProcessName("ahk_id " hwnd)
 try cls := WinGetClass("ahk_id " hwnd)
 detail := proc " [class " cls "] hwnd 0x" Format("{:X}", hwnd)
 try {
     WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
     GetMouseParkMonitorBounds(hwnd, &left, &top, &right, &bottom)
     monitorW := right - left
     monitorH := bottom - top
     if (monitorW > 0 && monitorH > 0) {
         covers := (ww >= monitorW * 0.98 && wh >= monitorH * 0.98)
         detail .= " " ww "x" wh
             . (covers ? " (covers its monitor -- possibly exclusive fullscreen)" : "")
     }
 }
 return detail
}

; The handoff is verified once, at open. That proves the menu ACQUIRED the
; foreground; it does not prove it KEPT it.
;
; A game that re-asserts focus a moment later produces exactly the symptom the
; open-time check was meant to catch -- controller input reaching the game while
; the menu is up -- and produces it silently, because nothing looks again. Those
; are three different problems with three different answers:
;
;   never acquired   the two ShowQuickMenu/EnsureForeground lines
;   acquired, lost   this line
;   held throughout  neither -- the game is polling XInput while unfocused, which
;                    nothing in user mode can prevent
;
; Logged once per menu session rather than per poll: the poll runs at ~16 ms and
; this is a state, not an event.
QuickMenuWatchForegroundLoss() {
 global QuickMenuGui, QuickMenuVisible
 static reported := false
 static lastCheckTick := 0
 if (!QuickMenuVisible || !IsSet(QuickMenuGui)) {
     reported := false
     return
 }
 if (A_TickCount - lastCheckTick < 500)
     return
 lastCheckTick := A_TickCount
 foreground := 0
 try foreground := DllCall("User32\GetForegroundWindow", "Ptr")
 if (foreground = QuickMenuGui.Hwnd) {
     reported := false
     return
 }
 if reported
     return
 reported := true
 LogLine("Quick Menu lost the foreground while open; the game may be receiving "
     . "controller input. Foreground is held by: " DescribeForegroundWindow())
}

QuickMenuEnsureForeground() {
 global QuickMenuGui, QuickMenuVisible
 if (!QuickMenuVisible || !IsSet(QuickMenuGui))
     return
 if ForceForegroundWindow(QuickMenuGui.Hwnd)
     return
 ; Deliberately not retried further. The handoff is refused by rule, not by
 ; timing, so more attempts do not change the outcome -- and against a game that
 ; re-asserts itself they turn into a focus fight, which on an
 ; exclusive-fullscreen title means repeated minimise/restore churn. Report what
 ; is holding it instead.
 LogLine("Quick Menu foreground retry failed; the game may still receive "
     . "controller input. Foreground is held by: " DescribeForegroundWindow())
}

QuickMenuHideThenSend(shortcut, delayMs := 150) {
 HideQuickMenu()
 SetTimer(() => SendChordSafe(shortcut), -delayMs)
}

QuickMenuHideThenSteamMenu(steamInFront) {
 global SteamMenuShortcut
 HideQuickMenu()
 if steamInFront
     SetTimer(() => SendChordSafe(SteamMenuShortcut), -150)
 else
     SetTimer(SendSteamOverlayChord, -150)
}

HideQuickMenu(restorePrevious := true) {
 global QuickMenuGui, QuickMenuVisible, QuickMenuPreviousHwnd
 if (!QuickMenuVisible)
     return

 QuickMenuVisible := false
 if IsSet(QuickMenuGui)
     try QuickMenuGui.Hide()

 if (restorePrevious && QuickMenuPreviousHwnd && DllCall("IsWindow", "Ptr", QuickMenuPreviousHwnd)) {
     if ActivateWindowRobust(QuickMenuPreviousHwnd) {
         HandleCursorAfterManagedFocus(QuickMenuPreviousHwnd, false)
     }
 }
}

GetDefaultQuickMenuOrder() {
 return ["audio", "display", "rtss", "steammenu", "steamquickaccess",
     "layout", "tasks", "gamebar", "settings", "system"]
}

ParseQuickMenuMainOrder(raw) {
 allowed := Map()
 for _, itemName in GetDefaultQuickMenuOrder()
     allowed[itemName] := true
 result := []
 seen := Map()
 for _, rawName in StrSplit(raw, "|") {
     itemName := StrLower(Trim(rawName))
     if (!allowed.Has(itemName) || seen.Has(itemName))
         continue
     seen[itemName] := true
     result.Push(itemName)
 }
 for _, itemName in GetDefaultQuickMenuOrder() {
     if !seen.Has(itemName)
         result.Push(itemName)
 }
 return result
}

QuickMenuLayoutLabel(itemName) {
 switch StrLower(itemName) {
 case "audio": return "Audio"
 case "display": return "Display & HDR"
 case "rtss": return "RTSS & Performance"
 case "steammenu": return "Steam Menu"
 case "steamquickaccess": return "Steam Quick Access"
 case "layout": return "Controller Layout"
 case "tasks": return "Task Switcher"
 case "gamebar": return "Game Bar"
 case "settings": return "Settings"
 case "system": return "System"
 default: return itemName
 }
}

RefreshQuickMenuLayoutManager() {
 global QuickMenuLayoutGui, QuickMenuMainOrder, QuickMenuHiddenItems
 if !IsSet(QuickMenuLayoutGui)
     return
 try {
     listView := QuickMenuLayoutGui["QuickMenuLayoutList"]
     listView.Delete()
     for _, itemName in QuickMenuMainOrder {
         required := itemName = "settings" || itemName = "system"
         visibility := required ? "Always" : (QuickMenuHiddenItems.Has(itemName) ? "Hidden" : "Visible")
         listView.Add("", QuickMenuLayoutLabel(itemName), visibility, itemName)
     }
     listView.ModifyCol(1, 275)
     listView.ModifyCol(2, 100)
     listView.ModifyCol(3, 0)
     if listView.GetCount()
         listView.Modify(1, "Select Focus")
 }
}

QuickMenuLayoutMove(direction, *) {
 global QuickMenuLayoutGui
 if !IsSet(QuickMenuLayoutGui)
     return
 listView := QuickMenuLayoutGui["QuickMenuLayoutList"]
 row := listView.GetNext(0, "F")
 if (!row)
     row := listView.GetNext()
 target := row + direction
 if (!row || target < 1 || target > listView.GetCount())
     return
 first := [listView.GetText(row, 1), listView.GetText(row, 2), listView.GetText(row, 3)]
 second := [listView.GetText(target, 1), listView.GetText(target, 2), listView.GetText(target, 3)]
 listView.Modify(row, "", second*)
 listView.Modify(target, "Select Focus Vis", first*)
}

QuickMenuLayoutToggle(*) {
 global QuickMenuLayoutGui
 if !IsSet(QuickMenuLayoutGui)
     return
 listView := QuickMenuLayoutGui["QuickMenuLayoutList"]
 row := listView.GetNext(0, "F")
 if (!row)
     row := listView.GetNext()
 if (!row)
     return
 itemName := listView.GetText(row, 3)
 if (itemName = "settings" || itemName = "system") {
     QuickMenuLayoutGui["QuickMenuLayoutStatus"].Text :=
         "Settings and System remain visible as recovery paths."
     return
 }
 current := listView.GetText(row, 2)
 listView.Modify(row, "", listView.GetText(row, 1),
     current = "Hidden" ? "Visible" : "Hidden", itemName)
}

QuickMenuLayoutRestoreDefault(*) {
 global QuickMenuLayoutGui
 if !IsSet(QuickMenuLayoutGui)
     return
 listView := QuickMenuLayoutGui["QuickMenuLayoutList"]
 listView.Delete()
 for _, itemName in GetDefaultQuickMenuOrder()
     listView.Add("", QuickMenuLayoutLabel(itemName),
         itemName = "settings" || itemName = "system" ? "Always" : "Visible", itemName)
 listView.Modify(1, "Select Focus")
 QuickMenuLayoutGui["QuickMenuLayoutStatus"].Text :=
     "Default order restored in the editor. Choose Save Layout to apply it."
}

QuickMenuLayoutSave(*) {
 global QuickMenuLayoutGui, QuickMenuMainOrderRaw, QuickMenuHiddenItemsRaw
 global QuickMenuMainOrder, QuickMenuHiddenItems, QuickMenuVisible
 if !IsSet(QuickMenuLayoutGui)
     return
 listView := QuickMenuLayoutGui["QuickMenuLayoutList"]
 order := []
 hidden := []
 Loop listView.GetCount() {
     itemName := listView.GetText(A_Index, 3)
     order.Push(itemName)
     if (listView.GetText(A_Index, 2) = "Hidden")
         hidden.Push(itemName)
 }
 QuickMenuMainOrderRaw := JoinWith(order, "|")
 QuickMenuHiddenItemsRaw := JoinWith(hidden, "|")
 if !CommitIniChanges([
     Map("section", "QuickMenu", "key", "MainOrder", "value", QuickMenuMainOrderRaw),
     Map("section", "QuickMenu", "key", "HiddenItems", "value", QuickMenuHiddenItemsRaw)
 ]) {
     QuickMenuLayoutGui["QuickMenuLayoutStatus"].Text := "SteamShell could not save the layout."
     return
 }
 QuickMenuMainOrder := ParseQuickMenuMainOrder(QuickMenuMainOrderRaw)
 QuickMenuHiddenItems := Map()
 for _, itemName in hidden
     QuickMenuHiddenItems[itemName] := true
 QuickMenuLayoutGui["QuickMenuLayoutStatus"].Text := "Quick Menu layout saved and applied."
 if QuickMenuVisible
     QuickMenuBuildGui()
}

ShowQuickMenuLayoutManager(*) {
 global QuickMenuLayoutGui
 if !IsSet(QuickMenuLayoutGui) {
     QuickMenuLayoutGui := Gui("+AlwaysOnTop +ToolWindow -Resize", "Quick Menu Layout")
     QuickMenuLayoutGui.SetFont("s10", "Segoe UI")
     title := QuickMenuLayoutGui.AddText("xm ym w590 h30", "Quick Menu Layout")
     title.SetFont("s17 Bold", "Segoe UI")
     QuickMenuLayoutGui.AddText(
         "xm y+2 w590 h38 +Wrap",
         "Reorder the main menu and hide rows you do not use. Settings and System always remain available.")
     QuickMenuLayoutGui.AddListView(
         "xm y+8 w590 r10 -Multi vQuickMenuLayoutList", ["Section", "Visibility", "Key"])
     upButton := QuickMenuLayoutGui.AddButton("xm y+8 w105 h32", "Move Up")
     upButton.OnEvent("Click", QuickMenuLayoutMove.Bind(-1))
     downButton := QuickMenuLayoutGui.AddButton("x+8 yp w105 h32", "Move Down")
     downButton.OnEvent("Click", QuickMenuLayoutMove.Bind(1))
     toggleButton := QuickMenuLayoutGui.AddButton("x+8 yp w125 h32", "Show / Hide")
     toggleButton.OnEvent("Click", QuickMenuLayoutToggle)
     defaultButton := QuickMenuLayoutGui.AddButton("x+8 yp w125 h32", "Restore Default")
     defaultButton.OnEvent("Click", QuickMenuLayoutRestoreDefault)
     saveButton := QuickMenuLayoutGui.AddButton("x+8 yp w105 h32", "Save Layout")
     saveButton.OnEvent("Click", QuickMenuLayoutSave)
     QuickMenuLayoutGui.AddText("xm y+8 w460 h24 vQuickMenuLayoutStatus", "")
     closeButton := QuickMenuLayoutGui.AddButton("x+8 yp-5 w105 h30", "Close")
     closeButton.OnEvent("Click", (*) => QuickMenuLayoutGui.Hide())
     QuickMenuLayoutGui.OnEvent("Close", (*) => QuickMenuLayoutGui.Hide())
     QuickMenuLayoutGui.OnEvent("Escape", (*) => QuickMenuLayoutGui.Hide())
 }
 QuickMenuLayoutGui.Show()
 CenterGuiOnTargetMonitor(QuickMenuLayoutGui)
 RefreshQuickMenuLayoutManager()
}

QuickMenuGetDefinitions() {
 global QuickMenuPage, QuickMenuDisplayModes
 global QuickMenuTaskPage, QuickMenuTaskWindows, PinnedForegroundHwnd
 global EnableAudioQuickControls, EnableDisplayQuickControls
 global EnableRTSSIntegration, RtssPath
 global RtssOverlayControlMode, RtssFrameLimiterControlMode
 global QuickMenuMainOrder, QuickMenuHiddenItems, DesktopMode
 rows := []

 if (QuickMenuPage = "AUDIO") {
     rows.Push(Map("id", "audioBack", "label", "Back"))
     rows.Push(Map("id", "audioOutput", "label", "Output"))
     rows.Push(Map("id", "volume", "label", "Volume"))
     rows.Push(Map("id", "mute", "label", "Mute"))
     return rows
 }

 if (QuickMenuPage = "SYSTEM") {
     rows.Push(Map("id", "systemBack", "label", "Back to Quick Settings"))
     rows.Push(Map("id", "control", "label", "Diagnostics Control Panel"))
     rows.Push(Map("id", "health", "label", "SteamShell Health Check"))
     if (DesktopMode)
         rows.Push(Map("id", "returnShell", "label", "Return to SteamShell"))
     else
         rows.Push(Map("id", "desktop", "label", "Exit Steam to Desktop"))
     rows.Push(Map("id", "exitApp", "label", "Exit SteamShell"))
     rows.Push(Map("id", "sleep", "label", "Sleep"))
     rows.Push(Map("id", "restart", "label", "Restart PC"))
     rows.Push(Map("id", "shutdown", "label", "Shut Down"))
     return rows
 }

 if (QuickMenuPage = "SETTINGS") {
     rows.Push(Map("id", "settingsBack", "label", "Back to Quick Settings"))
     rows.Push(Map("id", "settingsGeneral", "label", "General + Startup"))
     rows.Push(Map("id", "settingsInput", "label", "Controller + Cursor"))
     rows.Push(Map("id", "settingsFocus", "label", "Focus + Window Engine"))
     rows.Push(Map("id", "settingsRtss", "label", "RTSS + Performance"))
     rows.Push(Map("id", "settingsEditor", "label", "Open Full Settings Editor"))
     rows.Push(Map("id", "settingsReload", "label", "Reload Settings"))
     return rows
 }

 if (QuickMenuPage = "SETTINGS_GENERAL") {
     rows.Push(Map("id", "settingsHome", "label", "Back to Settings"))
     rows.Push(Map("id", "qSplash", "label", "Startup Splash"))
     rows.Push(Map("id", "qTaskbar", "label", "Hide Taskbar in Shell"))
     rows.Push(Map("id", "qBlackout", "label", "Black Desktop Background"))
     rows.Push(Map("id", "qAudioControls", "label", "Quick Menu Audio"))
     rows.Push(Map("id", "qDisplayControls", "label", "Quick Menu Display"))
     return rows
 }

 if (QuickMenuPage = "SETTINGS_INPUT") {
     rows.Push(Map("id", "settingsHome", "label", "Back to Settings"))
     rows.Push(Map("id", "qControllerMouse", "label", "Controller Mouse"))
     rows.Push(Map("id", "qMouseSpeed", "label", "Controller Mouse Speed"))
     rows.Push(Map("id", "qAutoHideCursor", "label", "Auto-hide Cursor"))
     rows.Push(Map("id", "qMouseHideDelay", "label", "Cursor Hide Delay"))
     rows.Push(Map("id", "qParkBoot", "label", "Park Mouse on Boot"))
     rows.Push(Map("id", "qParkFocus", "label", "Park on Focus Change"))
     rows.Push(Map("id", "qParkEdge", "label", "Mouse Parking Edge"))
     rows.Push(Map("id", "qControllerMap", "label", "Edit Controller Mapping"))
     return rows
 }

 if (QuickMenuPage = "SETTINGS_FOCUS") {
     rows.Push(Map("id", "settingsHome", "label", "Back to Settings"))
     rows.Push(Map("id", "qSteamRefocus", "label", "Steam Refocus"))
     rows.Push(Map("id", "qGameAssist", "label", "Game Foreground Assist"))
     rows.Push(Map("id", "qAlwaysFocus", "label", "AlwaysFocus Support"))
     rows.Push(Map("id", "qWindowManagement", "label", "Window Management"))
     rows.Push(Map("id", "qFocusPaused", "label", "Focus Assistance Session"))
     return rows
 }

 if (QuickMenuPage = "SETTINGS_RTSS") {
     rows.Push(Map("id", "settingsHome", "label", "Back to Settings"))
     rows.Push(Map("id", "qRtssIntegration", "label", "RTSS Integration"))
     rows.Push(Map("id", "qOverlayMode", "label", "Overlay Controls"))
     rows.Push(Map("id", "qLimiterMode", "label", "Frame Limiter Controls"))
     rows.Push(Map("id", "qFrameCap", "label", "Fallback Frame Cap Label"))
     rows.Push(Map("id", "settingsEditor", "label", "Edit Paths + Shortcuts"))
     return rows
 }

 if (QuickMenuPage = "TASKS") {
     rows.Push(Map("id", "tasksBack", "label", "Back to Quick Settings"))
     if (PinnedForegroundHwnd && DllCall("IsWindow", "Ptr", PinnedForegroundHwnd))
         rows.Push(Map("id", "taskRelease", "label", "Release Focus Lock"))

     pageSize := 8
     pageCount := Max(1, Ceil(QuickMenuTaskWindows.Length / pageSize))
     QuickMenuTaskPage := ClampInt(QuickMenuTaskPage, 1, pageCount)
     firstIndex := ((QuickMenuTaskPage - 1) * pageSize) + 1
     lastIndex := Min(QuickMenuTaskWindows.Length, firstIndex + pageSize - 1)
     if (QuickMenuTaskWindows.Length = 0) {
         rows.Push(Map("id", "tasksUnavailable", "label", "No application windows found"))
     } else {
         Loop lastIndex - firstIndex + 1 {
             item := QuickMenuTaskWindows[firstIndex + A_Index - 1]
             rows.Push(Map(
                 "id", "taskWindow:" item["hwnd"],
                 "label", ShortenQuickMenuText(item["title"], 42)
             ))
         }
     }
     if (pageCount > 1) {
         rows.Push(Map("id", "taskPrev", "label", "Previous Page"))
         rows.Push(Map("id", "taskNext", "label", "Next Page"))
     }
     return rows
 }

 if (QuickMenuPage = "DISPLAY") {
     rows.Push(Map("id", "displayBack", "label", "Back"))
     hdrState := GetPrimaryHdrState()
     if (IsObject(hdrState) && hdrState["supported"] && !hdrState["forceDisabled"])
         rows.Push(Map("id", "hdr", "label", "HDR"))
     else
         rows.Push(Map("id", "hdrUnavailable", "label", "HDR"))
     if (QuickMenuDisplayModes.Length = 0)
         QuickMenuDisplayModes := GetPrimaryDisplayModes()
     if (QuickMenuDisplayModes.Length = 0) {
         rows.Push(Map("id", "displayUnavailable", "label", "No compatible modes reported"))
     } else {
         EnsureDisplaySelection()
         rows.Push(Map("id", "displayResolution", "label", "Resolution"))
         rows.Push(Map("id", "displayRefresh", "label", "Refresh rate"))
         if IsObject(EnsureDisplayScaleSelection())
             rows.Push(Map("id", "displayScale", "label", "Scale"))
         else
             rows.Push(Map("id", "displayScaleUnavailable", "label", "Scale"))
         rows.Push(Map("id", "displayApply", "label", "Apply"))
     }
     return rows
 }

 if (QuickMenuPage = "RTSS") {
     rows.Push(Map("id", "rtssBack", "label", "Back"))
     rtssRunning := ProcessExist("RTSS.exe") != 0
     if !rtssRunning {
         if !EnableRTSSIntegration
             rows.Push(Map("id", "rtssDisabled", "label", "RTSS Integration"))
         else if FileExist(NormalizeMediaPath(RtssPath))
             rows.Push(Map("id", "rtssStart", "label", "Start RTSS"))
         else
             rows.Push(Map("id", "rtssMissing", "label", "RTSS"))
     } else {
         liveState := GetRtssGlobalState()
         if IsObject(liveState) {
             rows.Push(Map("id", "rtssOverlayState", "label", "Overlay"))
             ; One row for the limiter flag and its target. The separate
             ; "Frame Limiter" row is gone here on purpose: with live DLL
             ; control, two rows that can each mean "no limiting" only fight
             ; each other. The shortcut fallback below still needs both,
             ; because without the DLL there is no value to fold in.
             rows.Push(Map("id", "rtssFrameLimit", "label", "Frame Limit"))
             capState := GetRtssFrameCapState()
             if (IsObject(capState) && capState["mode"] = "custom")
                 rows.Push(Map("id", "rtssFrameLimitCustom", "label", "Custom FPS"))
             ; Always present, even with nothing to save to: the value column
             ; explains why rather than the row disappearing, which would read
             ; as the feature being missing.
             rows.Push(Map("id", "rtssSaveProfile", "label", "Save Limit to Profile"))
         } else {
             if (RtssOverlayControlMode = "separate") {
                 rows.Push(Map("id", "overlayOn", "label", "Overlay On"))
                 rows.Push(Map("id", "overlayOff", "label", "Overlay Off"))
             } else {
                 rows.Push(Map("id", "overlayToggle", "label", "Toggle Overlay"))
             }
             if (RtssFrameLimiterControlMode = "separate") {
                 rows.Push(Map("id", "limiterOn", "label", "Frame Limiter On"))
                 rows.Push(Map("id", "limiterOff", "label", "Frame Limiter Off"))
             } else {
                 rows.Push(Map("id", "limiterToggle", "label", "Toggle Frame Limiter"))
             }
         }
     }
     rows.Push(Map("id", "rtssSettings", "label", "RTSS Settings"))
     return rows
 }

 if (QuickMenuPage = "LAYOUT") {
     rows.Push(Map("id", "layoutBack", "label", "Back to Quick Settings"))
     for _, buttonName in ["A","B","X","Y","LB","RB","LT","RT","Start","L3","R3"]
         rows.Push(Map("id", "layout:" buttonName, "label", "Back + " buttonName))
     return rows
 }

 available := Map(
     "audio", EnableAudioQuickControls ? Map("id", "audioMenu", "label", "Audio") : 0,
     "display", EnableDisplayQuickControls ? Map("id", "display", "label", "Display & HDR") : 0,
     "rtss", Map("id", "rtssMenu", "label", "RTSS & Performance"),
     "steammenu", Map("id", "steamMenu", "label",
         IsSteamRunning() ? "Steam Menu" : "Launch Steam"),
     "steamquickaccess", Map("id", "steamQuickAccess", "label", "Steam Quick Access"),
     "layout", Map("id", "layout", "label", "Controller Layout"),
     "tasks", Map("id", "tasks", "label", "Task Switcher"),
     "gamebar", Map("id", "gameBar", "label", "Game Bar"),
     "settings", Map("id", "settings", "label", "Settings"),
     "system", Map("id", "system", "label", "System"))
 added := Map()
 for _, itemName in QuickMenuMainOrder {
     if !available.Has(itemName) || !IsObject(available[itemName])
         continue
     if (QuickMenuHiddenItems.Has(itemName)
         && itemName != "settings" && itemName != "system")
         continue
     rows.Push(available[itemName])
     added[itemName] := true
 }
 ; Settings and System are recovery paths and can never be hidden or lost
 ; through a malformed order string.
 for _, requiredName in ["settings", "system"] {
     if !added.Has(requiredName)
         rows.Push(available[requiredName])
 }
 return rows
}

QuickMenuBuildGui() {
 global QuickMenuGui, QuickMenuRows, QuickMenuPage, QuickMenuVisible
 global QuickMenuTitleCtrl, QuickMenuFooterCtrl
 global QuickMenuLabelCtrls, QuickMenuValueCtrls
 global QuickMenuPreviousHwnd
 global QM_BG, QM_LABEL, QM_VALUE, QM_LABEL_SELECTED

 if !QuickMenuVisible
     return

 defs := QuickMenuGetDefinitions()
 menuW := QuickMenuWidth()
 rowInset := QuickMenuRowInset()
 rowWidth := menuW - (rowInset * 2)
 labelWidth := Round(rowWidth * 0.52)

 if !IsSet(QuickMenuGui) {
     ; Match XFE's final presentation: one persistent, borderless window and one
     ; persistent control pool. DWM backdrop/caption styling is deliberately not
     ; applied here because it adds the visible frame that XFE removed.
     QuickMenuGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "SteamShell Quick Menu")
     QuickMenuGui.BackColor := QM_BG
     QuickMenuGui.MarginX := rowInset
     QuickMenuGui.MarginY := 16
     QuickMenuGui.SetFont("s17 c" QM_LABEL_SELECTED " Bold", "Segoe UI")
     QuickMenuTitleCtrl := QuickMenuGui.AddText(
         "x" (rowInset + 12) " y20 w" (rowWidth - 12) " h30", "")
     QuickMenuLabelCtrls := []
     QuickMenuValueCtrls := []
     Loop 14 {
         index := A_Index
         y := QuickMenuRowTop() + ((index - 1) * QuickMenuRowHeight())
         QuickMenuGui.SetFont("s12 c" QM_LABEL " Norm", "Segoe UI")
         labelCtrl := QuickMenuGui.AddText(
             "x" rowInset " y" y " w" labelWidth " h32 +0x200 Background" QM_BG, "")
         QuickMenuGui.SetFont("s11 c" QM_VALUE " Norm", "Segoe UI")
         valueCtrl := QuickMenuGui.AddText(
             "x" (rowInset + labelWidth) " y" y
             . " w" (rowWidth - labelWidth) " h32 Right +0x200 Background" QM_BG, "")
         labelCtrl.OnEvent("Click", QuickMenuMouseSelect.Bind(index))
         valueCtrl.OnEvent("Click", QuickMenuMouseSelect.Bind(index))
         QuickMenuLabelCtrls.Push(labelCtrl)
         QuickMenuValueCtrls.Push(valueCtrl)
     }
     QuickMenuGui.SetFont("s9 c" QM_VALUE " Norm", "Segoe UI")
     QuickMenuFooterCtrl := QuickMenuGui.AddText(
         "x" (rowInset + 12) " y600 w" (rowWidth - 12) " h36 +Wrap", "")
     QuickMenuGui.OnEvent("Escape", (*) => QuickMenuGoBack())
 }

 ; Do not expose intermediate title, row, resize, or region changes. This is the
 ; standalone equivalent of XFE's repaint-in-place behavior.
 QuickMenuSetRedraw(false)
 try {
     QuickMenuTitleCtrl.Text := GuiLiteralText(QuickMenuTitleText())
     QuickMenuRows := []
     Loop QuickMenuLabelCtrls.Length {
         index := A_Index
         labelCtrl := QuickMenuLabelCtrls[index]
         valueCtrl := QuickMenuValueCtrls[index]
         if (index > defs.Length) {
             labelCtrl.Visible := false
             valueCtrl.Visible := false
             continue
         }
         def := defs[index]
         labelCtrl.Visible := true
         valueCtrl.Visible := true
         QuickMenuRows.Push(Map(
             "id", def["id"], "label", def["label"],
             "labelCtrl", labelCtrl, "valueCtrl", valueCtrl))
     }

     QuickMenuFooterCtrl.Move(
         rowInset + 12, QuickMenuStatusY(defs.Length),
         rowWidth - 12, QuickMenuStatusHeight())
     QuickMenuFooterCtrl.Text := GuiLiteralText(QuickMenuHintText())
     menuH := Min(
         QuickMenuStatusY(defs.Length) + QuickMenuStatusHeight()
             + QuickMenuBottomMargin(),
         820)
     QuickMenuRefresh()
     deferred := PositionQuickMenuOnTarget(
         QuickMenuGui, QuickMenuPreviousHwnd, menuW, menuH, true)
     if deferred
         RevealWindow(QuickMenuGui)
     QuickMenuEnsureContentFits()
     ApplyRoundedCorners(QuickMenuGui, 30)
 } finally {
     QuickMenuSetRedraw(true)
 }
}

QuickMenuTitleText() {
 global QuickMenuPage
 titles := Map(
     "AUDIO", "Audio",
     "DISPLAY", "Display & HDR",
     "RTSS", "RTSS & Performance",
     "LAYOUT", "Controller Layout",
     "TASKS", "Task Switcher",
     "SETTINGS", "Settings",
     "SETTINGS_GENERAL", "Settings  ›  General & Startup",
     "SETTINGS_INPUT", "Settings  ›  Controller & Cursor",
     "SETTINGS_FOCUS", "Settings  ›  Focus & Windows",
     "SETTINGS_RTSS", "Settings  ›  RTSS & Performance",
     "SYSTEM", "System")
 if !titles.Has(QuickMenuPage)
     return "SteamShell"
 return "SteamShell  ›  " titles[QuickMenuPage]
}

QuickMenuWidth() {
 return 620
}

QuickMenuRowTop() {
 return 74
}

QuickMenuRowHeight() {
 return 40
}

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

QuickMenuHintText() {
 global QuickMenuPage
 global LastStatusText, LastStatusTick, StatusVisibleMs
 ; A fresh message displaces the hint. The hint is always re-derivable; a
 ; warning that scrolls past unseen is not.
 if (LastStatusText != "" && A_TickCount - LastStatusTick < StatusVisibleMs)
     return LastStatusText
 if (QuickMenuPage = "TASKS")
     return "D-pad move  •  A switch  •  Y switch + lock  •  X close  •  Hold X force close  •  B back"
 if (QuickMenuPage = "DISPLAY")
     return "D-pad move  •  Left/Right change  •  A select  •  B back"
 if (QuickMenuPage = "RTSS")
     return "D-pad move  •  Left/Right change  •  A select  •  B back"
 if (SubStr(QuickMenuPage, 1, 8) = "SETTINGS")
     return "D-pad move  •  A or Left/Right toggle  •  B back"
 return "D-pad move  •  A select  •  B back"
}

QuickMenuSetRedraw(enabled) {
 global QuickMenuGui
 if !IsSet(QuickMenuGui)
     return
 try DllCall(
     "User32\SendMessageW", "Ptr", QuickMenuGui.Hwnd,
     "UInt", 0x000B, "Ptr", enabled ? 1 : 0, "Ptr", 0)
 if enabled {
     ; RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN
     try DllCall(
         "User32\RedrawWindow", "Ptr", QuickMenuGui.Hwnd,
         "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
 }
}

MoveWindowPhysical(hwnd, x, y, w := 0, h := 0) {
 static SWP_NOSIZE := 0x0001
 static SWP_NOZORDER := 0x0004
 static SWP_NOACTIVATE := 0x0010
 flags := SWP_NOZORDER | SWP_NOACTIVATE
 if (w <= 0 || h <= 0)
     flags |= SWP_NOSIZE
 result := 0
 try result := DllCall(
     "User32\SetWindowPos", "Ptr", hwnd, "Ptr", 0,
     "Int", x, "Int", y, "Int", w, "Int", h, "UInt", flags, "Int")
 return result != 0
}

RevealWindow(guiObj, noActivate := false) {
 static SW_SHOWNOACTIVATE := 4
 static SW_SHOW := 5
 try DllCall(
     "User32\ShowWindow", "Ptr", guiObj.Hwnd,
     "Int", noActivate ? SW_SHOWNOACTIVATE : SW_SHOW)
}

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

PositionQuickMenuOnTarget(guiObj, targetHwnd, width, height, deferShow := false) {
 wasVisible := false
 try wasVisible := DllCall(
     "User32\IsWindowVisible", "Ptr", guiObj.Hwnd, "Int") != 0
 if wasVisible
     guiObj.Show("NA w" width " h" height)
 else
     guiObj.Show("Hide w" width " h" height)

 actualWidth := width
 actualHeight := height
 try {
     WinGetPos(, , &measuredWidth, &measuredHeight, "ahk_id " guiObj.Hwnd)
     if (measuredWidth > 0)
         actualWidth := measuredWidth
     if (measuredHeight > 0)
         actualHeight := measuredHeight
 }
 GetTargetMonitorWorkArea(
     targetHwnd, &workLeft, &workTop, &workRight, &workBottom)
 CenteredPosition(
     workLeft, workTop, workRight, workBottom,
     actualWidth, actualHeight, &x, &y)
 MoveWindowPhysical(guiObj.Hwnd, x, y)

 ; A hidden high-DPI window can report an estimated size. Re-measure after the
 ; move and correct its center while redraw remains disabled.
 try {
     WinGetPos(&shownX, &shownY, &shownWidth, &shownHeight, "ahk_id " guiObj.Hwnd)
     if (shownWidth > 0 && shownHeight > 0) {
         CenteredPosition(
             workLeft, workTop, workRight, workBottom,
             shownWidth, shownHeight, &correctedX, &correctedY)
         if (Abs(shownX - correctedX) > 1 || Abs(shownY - correctedY) > 1)
             MoveWindowPhysical(guiObj.Hwnd, correctedX, correctedY)
     }
 }
 if (!wasVisible && !deferShow)
     RevealWindow(guiObj)
 return !wasVisible && deferShow
}

QuickMenuEnsureContentFits() {
 global QuickMenuGui, QuickMenuFooterCtrl, QuickMenuPreviousHwnd
 if (!IsSet(QuickMenuGui) || !IsObject(QuickMenuFooterCtrl))
     return

 statusY := 0
 statusHeight := 0
 clientHeight := 0
 winWidth := 0
 winHeight := 0
 try {
     ControlGetPos(
         , &measuredStatusY, , &measuredStatusHeight,
         QuickMenuFooterCtrl, QuickMenuGui)
     WinGetClientPos(
         , , , &measuredClientHeight, "ahk_id " QuickMenuGui.Hwnd)
     WinGetPos(
         , , &measuredWinWidth, &measuredWinHeight,
         "ahk_id " QuickMenuGui.Hwnd)
     statusY := measuredStatusY
     statusHeight := measuredStatusHeight
     clientHeight := measuredClientHeight
     winWidth := measuredWinWidth
     winHeight := measuredWinHeight
 }
 if (statusHeight <= 0 || clientHeight <= 0 || winWidth <= 0 || winHeight <= 0)
     return

 neededClientHeight := statusY + statusHeight + Round(statusHeight * 0.45)
 grow := Max(0, neededClientHeight - clientHeight)
 GetTargetMonitorWorkArea(
     QuickMenuPreviousHwnd, &workLeft, &workTop, &workRight, &workBottom)
 maxHeight := workBottom - workTop
 finalHeight := Min(winHeight + grow, maxHeight)
 CenteredPosition(
     workLeft, workTop, workRight, workBottom,
     winWidth, finalHeight, &x, &y)
 if (grow > 0 || finalHeight != winHeight)
     MoveWindowPhysical(QuickMenuGui.Hwnd, x, y, winWidth, finalHeight)
 else
     MoveWindowPhysical(QuickMenuGui.Hwnd, x, y)
}

ApplyRoundedCorners(guiObj, radius) {
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

GetTargetMonitorWorkArea(targetHwnd, &left, &top, &right, &bottom) {
 ; Choose the monitor containing the center of the window that was active
 ; before the menu opened. This handles secondary TVs and negative coordinates.
 if (targetHwnd && DllCall("IsWindow", "Ptr", targetHwnd)) {
     try {
         WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " targetHwnd)
         centerX := wx + (ww / 2)
         centerY := wy + (wh / 2)
         Loop MonitorGetCount() {
             MonitorGet(A_Index, &ml, &mt, &mr, &mb)
             if (centerX >= ml && centerX < mr && centerY >= mt && centerY < mb) {
                 MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
                 return
             }
         }
     }
 }

 try {
     primaryMonitor := MonitorGetPrimary()
     MonitorGetWorkArea(primaryMonitor, &left, &top, &right, &bottom)
 } catch {
     left := 0
     top := 0
     right := A_ScreenWidth
     bottom := A_ScreenHeight
 }
}

CenterGuiOnTargetMonitor(guiObj, targetHwnd := 0) {
 try {
     WinGetPos(,, &guiW, &guiH, "ahk_id " guiObj.Hwnd)
     GetTargetMonitorWorkArea(targetHwnd, &workLeft, &workTop, &workRight, &workBottom)
     workWidth := workRight - workLeft
     workHeight := workBottom - workTop
     x := guiW >= workWidth
         ? workLeft
         : Round(workLeft + ((workWidth - guiW) / 2))
     y := guiH >= workHeight
         ? workTop
         : Round(workTop + ((workHeight - guiH) / 2))
     WinMove(x, y,,, "ahk_id " guiObj.Hwnd)
 }
}

ShortenQuickMenuText(text, maxChars) {
 text := Trim(text)
 if (StrLen(text) <= maxChars)
     return text
 return SubStr(text, 1, Max(1, maxChars - 1)) "…"
}

GetAudioMenuSummary() {
 volumeText := ""
 outputName := ""
 try volumeText := Round(SoundGetVolume()) "%"
 try outputName := SoundGetName()
 if (volumeText = "")
     volumeText := "Unavailable"
 if (outputName = "")
     return volumeText
 ; The value column clips from the left, so keep the volume at the right edge
 ; just as XFE does. A long device name may shorten; the percentage stays clear.
 return ShortenQuickMenuText(outputName, 22) "  •  " volumeText
}

GetTaskSwitcherWindows() {
 windows := []
 for _, item in WindowEngineGetFreshSnapshot() {
     legacySurface := WindowEngineIsLegacyApplicationSurface(item, true)
     if (item["scriptOwned"] || item["desktop"])
         continue
     if (item["title"] = "" && !legacySurface)
         continue
     if ((item["exStyle"] & 0x00000080)
         && !(item["exStyle"] & 0x00040000)
         && !legacySurface)
         continue
     if ((item["w"] < 120 || item["h"] < 80)
         && !(legacySurface && item["minMax"] = -1))
         continue

     displayTitle := item["title"] != ""
         ? item["title"]
         : item["proc"] " (legacy fullscreen window)"
     windows.Push(Map(
         "hwnd", item["hwnd"],
         "title", displayTitle,
         "exe", item["proc"],
         "pid", item["pid"],
         "legacy", legacySurface
     ))
 }
 return windows
}

FindTaskSwitcherWindow(hwnd) {
 global QuickMenuTaskWindows
 for _, item in QuickMenuTaskWindows {
     if (item["hwnd"] = hwnd)
         return item
 }
 return 0
}

GetPinnedForegroundSummary() {
 global PinnedForegroundHwnd, PinnedForegroundTitle
 if (!PinnedForegroundHwnd) {
     count := GetTaskSwitcherWindows().Length
     return count ? count " window" (count = 1 ? "" : "s") : "No windows"
 }
 if !DllCall("IsWindow", "Ptr", PinnedForegroundHwnd) {
     ReleasePinnedForeground(false)
     count := GetTaskSwitcherWindows().Length
     return count ? count " window" (count = 1 ? "" : "s") : "No windows"
 }
 return "Locked  •  " ShortenQuickMenuText(PinnedForegroundTitle, 18)
}

ReleasePinnedForeground(showNotice := true) {
 global PinnedForegroundHwnd, PinnedForegroundTitle, PinnedForegroundExe
 hadLock := PinnedForegroundHwnd != 0
 PinnedForegroundHwnd := 0
 PinnedForegroundTitle := ""
 PinnedForegroundExe := ""
 if (showNotice && hadLock)
     ShowNotification("Task Switcher focus lock released", "Success")
}

GetRtssMenuStatus() {
 global EnableRTSSIntegration, RtssPath, RtssUseDllIntegration
 if (!EnableRTSSIntegration)
     return "Setup required"
 if ProcessExist("RTSS.exe") {
     if !RtssUseDllIntegration
         return "Running | Shortcuts"
     liveState := GetRtssGlobalState()
     if IsObject(liveState)
         return "Overlay " (liveState["overlay"] ? "On" : "Off")
             . " | Limiter " (liveState["limiter"] ? "On" : "Off")
     return "Running"
 }
 return FileExist(NormalizeMediaPath(RtssPath)) ? "RTSS ready" : "RTSS not found"
}

GetControllerLayoutText(buttonName) {
 shortBinding := ControllerBindingPretty(buttonName ".Short")
 longBinding := ControllerBindingPretty(buttonName ".Long")
 return shortBinding "  /  " longBinding
}

DistinctDisplayResolutions() {
 global QuickMenuDisplayModes
 seen := Map()
 resolutions := []
 for _, mode in QuickMenuDisplayModes {
     key := mode["width"] "x" mode["height"]
     if seen.Has(key)
         continue
     seen[key] := true
     resolutions.Push(Map("width", mode["width"], "height", mode["height"]))
 }
 return resolutions
}

FrequenciesForResolution(width, height) {
 global QuickMenuDisplayModes
 frequencies := []
 for _, mode in QuickMenuDisplayModes {
     if (mode["width"] = width && mode["height"] = height)
         frequencies.Push(mode["frequency"])
 }
 return frequencies
}

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
 frequencies := FrequenciesForResolution(
     DisplaySelectedWidth, DisplaySelectedHeight)
 if (frequencies.Length = 0)
     return
 for _, frequency in frequencies {
     if (frequency = DisplaySelectedFrequency)
         return
 }
 best := frequencies[1]
 for _, frequency in frequencies {
     if (frequency > best)
         best := frequency
 }
 DisplaySelectedFrequency := best
}

CycleDisplayResolution(direction) {
 global DisplaySelectedWidth, DisplaySelectedHeight
 resolutions := DistinctDisplayResolutions()
 if (resolutions.Length = 0)
     return
 selectedIndex := 1
 for index, resolution in resolutions {
     if (resolution["width"] = DisplaySelectedWidth
         && resolution["height"] = DisplaySelectedHeight) {
         selectedIndex := index
         break
     }
 }
 selectedIndex += direction
 if (selectedIndex < 1)
     selectedIndex := resolutions.Length
 if (selectedIndex > resolutions.Length)
     selectedIndex := 1
 DisplaySelectedWidth := resolutions[selectedIndex]["width"]
 DisplaySelectedHeight := resolutions[selectedIndex]["height"]
 EnsureDisplaySelection()
}

CycleDisplayFrequency(direction) {
 global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
 frequencies := FrequenciesForResolution(
     DisplaySelectedWidth, DisplaySelectedHeight)
 if (frequencies.Length = 0)
     return
 selectedIndex := 1
 for index, frequency in frequencies {
     if (frequency = DisplaySelectedFrequency) {
         selectedIndex := index
         break
     }
 }
 selectedIndex += direction
 if (selectedIndex < 1)
     selectedIndex := frequencies.Length
 if (selectedIndex > frequencies.Length)
     selectedIndex := 1
 DisplaySelectedFrequency := frequencies[selectedIndex]
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
 selectedIndex := 1
 for index, option in options {
     if (option = DisplaySelectedScalePercent) {
         selectedIndex := index
         break
     }
 }
 selectedIndex += direction
 if (selectedIndex < 1)
     selectedIndex := options.Length
 if (selectedIndex > options.Length)
     selectedIndex := 1
 DisplaySelectedScalePercent := options[selectedIndex]
}

GetDisplayApplyValue() {
 global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
 global DisplaySelectedScalePercent
 global DisplayPendingOldMode, DisplayPendingUntilTick
 if IsObject(DisplayPendingOldMode) {
     seconds := Max(0, Ceil((DisplayPendingUntilTick - A_TickCount) / 1000))
     return "Select to KEEP (" seconds "s)"
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
     ShowNotification("That display mode is no longer offered", "Warning")
     return
 }
 currentMode := GetPrimaryDisplayMode()
 if !IsObject(currentMode) {
     ShowNotification("Current display mode is unavailable", "Warning")
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
         ShowNotification(
             "Keep or revert the pending display change first", "Warning")
     return
 }
 if (modeSame && scaleSame)
     return
 if (DisplaySelectedScalePercent && !IsObject(currentScale)) {
     ShowNotification("Windows display scaling is unavailable", "Warning")
     return
 }
 modeChanged := false
 if !modeSame {
     if !ApplyPrimaryDisplayMode(candidate) {
         ShowNotification("Windows rejected that display mode", "Warning")
         return
     }
     modeChanged := true
 }
 if !scaleSame && !ApplyPrimaryDisplayScale(DisplaySelectedScalePercent) {
     modeRestored := !modeChanged || ApplyPrimaryDisplayMode(currentMode)
     scaleRestored := !IsObject(currentScale)
         || ApplyPrimaryDisplayScale(currentScale["percent"])
     QueueQuickMenuDisplayReflow()
     ShowNotification(
         modeRestored && scaleRestored
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
 ShowNotification(
     "Display changed. Select CURRENT again within 15 seconds to keep it.",
     "Warning")
}

GetRtssAvailability() {
 global EnableRTSSIntegration, RtssPath
 if !EnableRTSSIntegration
     return "Setup required"
 if ProcessExist("RTSS.exe")
     return "Running"
 return FileExist(NormalizeMediaPath(RtssPath))
     ? "Ready to start"
     : "Not found"
}

GetFrameCapLabel() {
 global RtssCustomFrameCap
 return RtssCustomFrameCap > 0
     ? RtssCustomFrameCap " FPS preset"
     : "RTSS preset"
}

QuickMenuMouseSelect(index, *) {
 global QuickMenuSelected
 QuickMenuSelected := index
 QuickMenuRefresh()
 QuickMenuActivateSelected()
}

QuickMenuValue(id) {
 global FocusAssistancePaused, RtssPath, RtssCustomFrameCap, RtssPendingFrameCap
 global EnableRTSSIntegration, RtssOverlayToggleShortcut
 global RtssOverlayOnShortcut, RtssOverlayOffShortcut
 global RtssCustomFrameCapShortcut, RtssFrameLimiterOnShortcut, RtssFrameLimiterOffShortcut
 global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
 global DisplaySelectedScalePercent
 global QuickMenuTaskPage, QuickMenuTaskWindows
 global QuickMenuConfirmAction, QuickMenuConfirmUntilTick
 global EnableSplashScreen, EnableTaskbarHiding, EnableDesktopBlackout
 global EnableAudioQuickControls, EnableDisplayQuickControls
 global EnableControllerMouseMode, ControllerMouseSpeed, EnableAutoHideCursor, MouseHideDelay
 global EnableMouseParkOnBoot, EnableMouseParkOnFocusChange, MouseParkEdge
 global EnableSteamRefocusMode, EnableGameForegroundAssist, EnableAlwaysFocus, EnableWindowManagement
 global RtssOverlayControlMode, RtssFrameLimiterControlMode
 global SteamMenuShortcut, SteamQuickAccessShortcut, SteamOverlayShortcut

 if (QuickMenuConfirmAction = id && A_TickCount < QuickMenuConfirmUntilTick)
     return "SELECT AGAIN TO CONFIRM"

 if (SubStr(id, 1, 7) = "layout:")
     return GetControllerLayoutText(SubStr(id, 8))
 if (SubStr(id, 1, 11) = "taskWindow:") {
     item := FindTaskSwitcherWindow(ToInt(SubStr(id, 12), 0))
     return IsObject(item) ? ShortenQuickMenuText(item["exe"], 20) : "CLOSED"
 }

 switch id {
 case "audioMenu":
     return GetAudioMenuSummary()
 case "audioOutput":
     try {
         return ShortenQuickMenuText(SoundGetName(), 34)
     } catch {
         return "Unavailable"
     }
 case "volume":
     try {
         return Round(SoundGetVolume()) "%"
     } catch {
         return "Unavailable"
     }
 case "mute":
     try {
         return SoundGetMute() ? "ON" : "OFF"
     } catch {
         return "Unavailable"
     }
 case "hdr":
     hdrState := GetPrimaryHdrState()
     if !IsObject(hdrState)
         return "Unavailable"
     return "‹ " (hdrState["enabled"] ? "ON" : "OFF") " ›"
 case "hdrUnavailable":
     hdrState := GetPrimaryHdrState()
     if !IsObject(hdrState)
         return "Unavailable"
     if !hdrState["supported"]
         return "Unsupported"
     return hdrState["forceDisabled"] ? "Disabled by Windows" : "Unavailable"
 case "displayResolution":
     return "‹ " DisplaySelectedWidth " × " DisplaySelectedHeight " ›"
 case "displayRefresh":
     return "‹ " DisplaySelectedFrequency " Hz ›"
 case "displayScale":
     return "‹ " DisplaySelectedScalePercent "% ›"
 case "displayScaleUnavailable":
     return "Unavailable"
 case "displayApply":
     return GetDisplayApplyValue()
 case "display":
     return GetCurrentDisplayModeText()
 case "displayUnavailable":
     return "UNAVAILABLE"
 case "taskPrev", "taskNext":
     pageCount := Max(1, Ceil(QuickMenuTaskWindows.Length / 8))
     return QuickMenuTaskPage " / " pageCount
 case "tasksUnavailable":
     return "NONE"
 case "tasks":
     return GetPinnedForegroundSummary()
 case "steamMenu":
     if !IsSteamRunning()
         return "Big Picture"
     shortcut := IsSteamProcess(GetQuickMenuPreviousExe())
         ? SteamMenuShortcut
         : SteamOverlayShortcut
     return SendToPretty(shortcut)
 case "steamQuickAccess":
     if !IsSteamRunning()
         return "Steam is not running"
     return SendToPretty(SteamQuickAccessShortcut)
 case "settingsReload":
     return "Re-read SteamShellSettings.ini"
 case "returnShell":
     return "Hide the desktop and resume Steam"
 case "exitApp":
     return "Close SteamShell"
 case "gameBar":
     return "Win + G"
 case "taskRelease":
     return "UNLOCK"
 case "rtssMenu":
     return GetRtssMenuStatus()
 case "rtssDisabled":
     return "Disabled"
 case "rtssStart":
     return "Launch configured executable"
 case "rtssMissing":
     return "Executable not found"
 case "rtssOverlayState":
     state := GetRtssGlobalState()
     return IsObject(state)
         ? "‹ " (state["overlay"] ? "ON" : "OFF") " ›"
         : "Unavailable"
 case "rtssFrameLimit":
     return RtssFrameCapValueText()
 case "rtssFrameLimitCustom":
     capState := GetRtssFrameCapState()
     if !IsObject(capState)
         return "Unavailable"
     ; A pending value is what the user is looking at and adjusting; the live
     ; one has not caught up yet by design.
     return "‹ " (RtssPendingFrameCap > 0 ? RtssPendingFrameCap : capState["fps"])
         . " FPS ›"
 case "rtssSaveProfile":
     return RtssSaveProfileValueText()
 case "overlayToggle", "overlayOn", "overlayOff", "limiterOff":
     return ""
 case "limiterToggle", "limiterOn":
     return GetFrameCapLabel()
 case "rtssSettings":
     return GetRtssAvailability()
 case "qSplash":
     return EnableSplashScreen ? "ON  •  NEXT BOOT" : "OFF  •  NEXT BOOT"
 case "qTaskbar":
     return EnableTaskbarHiding ? "ON  •  NEXT BOOT" : "OFF  •  NEXT BOOT"
 case "qBlackout":
     ; Unlike the taskbar toggle this applies at once, so it stays usable as an
     ; escape hatch if the backdrop ever misbehaves on a given machine.
     return EnableDesktopBlackout ? "ON" : "OFF"
 case "qAudioControls":
     return EnableAudioQuickControls ? "ON" : "OFF"
 case "qDisplayControls":
     return EnableDisplayQuickControls ? "ON" : "OFF"
 case "qControllerMouse":
     return EnableControllerMouseMode ? "ON" : "OFF"
 case "qMouseSpeed":
     return ControllerMouseSpeed
 case "qAutoHideCursor":
     return EnableAutoHideCursor ? "ON" : "OFF"
 case "qMouseHideDelay":
     return MouseHideDelay = 0 ? "IMMEDIATE" : Format("{:.1f} SEC", MouseHideDelay / 1000)
 case "qParkBoot":
     return EnableMouseParkOnBoot ? "ON" : "OFF"
 case "qParkFocus":
     return EnableMouseParkOnFocusChange ? "ON" : "OFF"
 case "qParkEdge":
     return StrUpper(MouseParkEdge)
 case "qSteamRefocus":
     return EnableSteamRefocusMode ? "ON" : "OFF"
 case "qGameAssist":
     return EnableGameForegroundAssist ? "ON" : "OFF"
 case "qAlwaysFocus":
     return EnableAlwaysFocus ? "ON" : "OFF"
 case "qWindowManagement":
     return EnableWindowManagement ? "ON  •  COORDINATED" : "OFF  •  COORDINATED"
 case "qFocusPaused":
     return FocusAssistancePaused ? "PAUSED" : "ACTIVE"
 case "qRtssIntegration":
     return EnableRTSSIntegration ? "ON" : "OFF"
 case "qOverlayMode":
     return StrUpper(RtssOverlayControlMode)
 case "qLimiterMode":
     return StrUpper(RtssFrameLimiterControlMode)
 case "qFrameCap":
     return RtssCustomFrameCap > 0 ? RtssCustomFrameCap " FPS" : "NOT SET"
 case "layout":
     return "View mappings"
 case "settings":
     return "Features & configuration"
 case "system":
     return "Power & diagnostics"
 case "settingsGeneral", "settingsInput", "settingsFocus", "settingsRtss", "settingsEditor", "qControllerMap":
     return "›"
 case "audioBack", "systemBack", "tasksBack", "displayBack", "rtssBack", "layoutBack", "settingsBack", "settingsHome":
     return "‹"
 default:
     return ""
 }
}

QuickMenuRefresh() {
 global QuickMenuRows, QuickMenuSelected, QuickMenuConfirmAction, QuickMenuConfirmUntilTick
 global QM_BG, QM_ROW_SELECTED, QM_ACCENT, QM_LABEL, QM_LABEL_SELECTED, QM_VALUE
 global QuickMenuFooterCtrl
 if (QuickMenuRows.Length = 0)
     return

 if (QuickMenuConfirmAction != "" && A_TickCount >= QuickMenuConfirmUntilTick)
     QuickMenuConfirmAction := ""

 if (QuickMenuSelected < 1)
     QuickMenuSelected := QuickMenuRows.Length
 if (QuickMenuSelected > QuickMenuRows.Length)
     QuickMenuSelected := 1

 try QuickMenuFooterCtrl.Text := GuiLiteralText(QuickMenuHintText())

 for index, row in QuickMenuRows {
     selected := (index = QuickMenuSelected)
     rowBackground := selected ? QM_ROW_SELECTED : QM_BG
     row["labelCtrl"].Opt("+Background" rowBackground)
     row["valueCtrl"].Opt("+Background" rowBackground)
     row["labelCtrl"].Text := "  " GuiLiteralText(row["label"])
     row["valueCtrl"].Text := GuiLiteralText(QuickMenuValue(row["id"])) "  "
     if (selected) {
         try row["labelCtrl"].SetFont("s12 Bold c" QM_LABEL_SELECTED, "Segoe UI")
         try row["valueCtrl"].SetFont("s11 Norm c" QM_ACCENT, "Segoe UI")
     } else {
         try row["labelCtrl"].SetFont("s12 Norm c" QM_LABEL, "Segoe UI")
         try row["valueCtrl"].SetFont("s11 Norm c" QM_VALUE, "Segoe UI")
     }
     try row["labelCtrl"].Redraw()
     try row["valueCtrl"].Redraw()
 }
}

QuickMenuKeyboardActive(*) {
 global QuickMenuVisible, QuickMenuGui
 if (!QuickMenuVisible || !IsSet(QuickMenuGui))
     return false
 try return WinActive("ahk_id " QuickMenuGui.Hwnd) != 0
 return false
}

QuickMenuMoveSelection(direction) {
 global QuickMenuSelected
 QuickMenuSelected += direction
 QuickMenuRefresh()
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

QuickMenuCloseSelected() {
 global QuickMenuPage
 if (QuickMenuPage = "TASKS") {
     hwnd := GetSelectedTaskSwitcherHwnd()
     if hwnd
         RequestCloseTaskSwitcherWindow(hwnd)
 }
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

; Rows whose value is a number the user dials, rather than a list they step
; through. Only these accept hold-to-repeat.
QuickMenuRowAcceptsRepeat() {
 global QuickMenuRows, QuickMenuSelected
 static ids := QuickMenuIdSet("rtssFrameLimitCustom|volume|qMouseSpeed")
 if (QuickMenuRows.Length = 0
     || QuickMenuSelected < 1 || QuickMenuSelected > QuickMenuRows.Length)
     return false
 return ids.Has(QuickMenuRows[QuickMenuSelected]["id"])
}

QuickMenuHandleController(pressed, released := 0, lx := 0, ly := 0, buttons := 0) {
 global QuickMenuSelected, QuickMenuPage, TaskForceCloseHoldMs
 global QuickMenuRows
 static stickDir := ""
 static lastStickTick := 0
 static holdDir := 0
 static holdSince := 0
 static lastRepeatTick := 0
 static taskXDownTick := 0
 static taskXHwnd := 0
 static taskXLongFired := false

 ; In Task Switcher, defer X until release so a tap can request a normal
 ; window close while a deliberate hold force-terminates the owning process.
 if (QuickMenuPage != "TASKS") {
     taskXDownTick := 0
     taskXHwnd := 0
     taskXLongFired := false
 } else {
     if (pressed & 0x8000) {
         lockHwnd := GetSelectedTaskSwitcherHwnd()
         if lockHwnd
             SelectTaskSwitcherWindow(lockHwnd, true)
         return
     }

     if (pressed & 0x4000) {
         taskXHwnd := GetSelectedTaskSwitcherHwnd()
         taskXDownTick := taskXHwnd ? A_TickCount : 0
         taskXLongFired := false
     }

     if (taskXDownTick && !taskXLongFired
         && !(released & 0x4000)
         && A_TickCount - taskXDownTick >= TaskForceCloseHoldMs) {
         taskXLongFired := true
         ForceCloseTaskSwitcherWindow(taskXHwnd)
         return
     }

     if (released & 0x4000) {
         closeHwnd := taskXHwnd
         requestNormalClose := taskXDownTick && !taskXLongFired
         taskXDownTick := 0
         taskXHwnd := 0
         taskXLongFired := false
         if (requestNormalClose)
             RequestCloseTaskSwitcherWindow(closeHwnd)
         return
     }

     if (pressed & 0x4000)
         return
 }

 ; Left-stick navigation with a short repeat delay for couch use.
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
 ; earlier design grew the step after several quick presses, which meant tapping
 ; quickly silently changed what a tap did -- the same gesture producing 1 or 5
 ; or 10 depending on timing the user could not see.
 ;
 ; Speed comes from holding instead, and it accelerates the REPEAT RATE rather
 ; than the step. Every change stays 1, so the value is always predictable and
 ; can be stopped exactly where wanted; holding simply delivers more of them.
 ; That also removes the need to snap to a grid, which only existed to make
 ; large steps land on round numbers.
 ;
 ; List-valued rows (audio output, resolution) are excluded: scrubbing those at
 ; 50 changes a second would be useless and would fire real device work per step.
 if (QuickMenuRowAcceptsRepeat()) {
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

 if (pressed & 0x0001) { ; D-pad up
     QuickMenuSelected -= 1
     QuickMenuRefresh()
     return
 }
 if (pressed & 0x0002) { ; D-pad down
     QuickMenuSelected += 1
     QuickMenuRefresh()
     return
 }
 if (pressed & 0x0004) { ; D-pad left
     QuickMenuAdjustSelected(-1)
     return
 }
 if (pressed & 0x0008) { ; D-pad right
     QuickMenuAdjustSelected(1)
     return
 }
 if (pressed & 0x1000) { ; A
     QuickMenuActivateSelected()
     return
 }
 if (pressed & 0x2000) { ; B
     if (QuickMenuPage != "MAIN")
         QuickMenuGoBack()
     else
         HideQuickMenu()
 }
}

QuickMenuGoBack() {
 global QuickMenuPage, QuickMenuSelected
 if (QuickMenuPage = "MAIN") {
     HideQuickMenu()
     return
 }
 if (SubStr(QuickMenuPage, 1, 9) = "SETTINGS_" )
     QuickMenuPage := "SETTINGS"
 else
     QuickMenuPage := "MAIN"
 QuickMenuSelected := 1
 QuickMenuBuildGui()
}

PersistQuickMenuSetting(section, key, value) {
 global EnableAutoHideCursor, MouseHidden
 if !CommitIniChanges([Map("section", section, "key", key, "value", value)]) {
     ShowNotification("The setting could not be saved", "Warning")
     return false
 }
 LoadSettings()
 ApplyRuntimeTimers()
 if (!EnableAutoHideCursor && MouseHidden) {
     SystemCursor("Show")
     MouseHidden := false
 }
 SyncControlPanel()
 return true
}

QuickMenuIdSet(pipeList) {
 result := Map()
 for _, name in StrSplit(pipeList, "|") {
     trimmed := Trim(name)
     if (trimmed != "")
         result[trimmed] := true
 }
 return result
}

; One source of truth for the Quick Menu's settings rows, shared by activation
; and left/right adjustment. These were duplicated `case` lists until AutoHotkey
; v2's hard limit of 20 parameters per `Case` rejected the longer one.
IsQuickMenuToggleSetting(id) {
 static ids := QuickMenuIdSet(
     "qSplash|qTaskbar|qBlackout|qAudioControls|qDisplayControls"
     . "|qControllerMouse|qAutoHideCursor|qParkBoot|qParkFocus|qParkEdge"
     . "|qSteamRefocus|qGameAssist|qAlwaysFocus|qWindowManagement|qFocusPaused"
     . "|qRtssIntegration|qOverlayMode|qLimiterMode")
 return ids.Has(id)
}

IsQuickMenuAdjustSetting(id) {
 static ids := QuickMenuIdSet("qMouseSpeed|qMouseHideDelay|qFrameCap")
 return ids.Has(id)
}

ToggleQuickMenuSetting(id) {
 global EnableSplashScreen, EnableTaskbarHiding, EnableDesktopBlackout
 global EnableAudioQuickControls, EnableDisplayQuickControls
 global EnableControllerMouseMode, EnableAutoHideCursor
 global EnableMouseParkOnBoot, EnableMouseParkOnFocusChange, MouseParkEdge
 global EnableSteamRefocusMode, EnableGameForegroundAssist, EnableAlwaysFocus, EnableWindowManagement
 global EnableRTSSIntegration, RtssOverlayControlMode, RtssFrameLimiterControlMode
 global FocusAssistancePaused

 switch id {
 case "qSplash":
     PersistQuickMenuSetting("Features", "EnableSplashScreen", EnableSplashScreen ? "false" : "true")
 case "qTaskbar":
     PersistQuickMenuSetting("Features", "EnableTaskbarHiding", EnableTaskbarHiding ? "false" : "true")
 case "qBlackout":
     PersistQuickMenuSetting("Features", "EnableDesktopBlackout", EnableDesktopBlackout ? "false" : "true")
 case "qAudioControls":
     PersistQuickMenuSetting("AudioQuickControls", "Enable", EnableAudioQuickControls ? "false" : "true")
 case "qDisplayControls":
     PersistQuickMenuSetting("DisplayQuickControls", "Enable", EnableDisplayQuickControls ? "false" : "true")
 case "qControllerMouse":
     PersistQuickMenuSetting("Controller", "EnableControllerMouseMode", EnableControllerMouseMode ? "false" : "true")
 case "qAutoHideCursor":
     PersistQuickMenuSetting("Features", "EnableAutoHideCursor", EnableAutoHideCursor ? "false" : "true")
 case "qParkBoot":
     PersistQuickMenuSetting("Features", "EnableMouseParkOnBoot", EnableMouseParkOnBoot ? "false" : "true")
 case "qParkFocus":
     PersistQuickMenuSetting("Features", "EnableMouseParkOnFocusChange", EnableMouseParkOnFocusChange ? "false" : "true")
 case "qParkEdge":
     PersistQuickMenuSetting("MousePark", "MouseParkEdge", MouseParkEdge = "right" ? "Left" : "Right")
 case "qSteamRefocus":
     PersistQuickMenuSetting("Features", "EnableSteamRefocusMode", EnableSteamRefocusMode ? "false" : "true")
 case "qGameAssist":
     PersistQuickMenuSetting("Features", "EnableGameForegroundAssist", EnableGameForegroundAssist ? "false" : "true")
 case "qAlwaysFocus":
     PersistQuickMenuSetting("Features", "EnableAlwaysFocus", EnableAlwaysFocus ? "false" : "true")
 case "qWindowManagement":
     PersistQuickMenuSetting("Features", "EnableWindowManagement", EnableWindowManagement ? "false" : "true")
 case "qFocusPaused":
     FocusAssistancePaused := !FocusAssistancePaused
 case "qRtssIntegration":
     PersistQuickMenuSetting("RTSS", "EnableIntegration", EnableRTSSIntegration ? "false" : "true")
 case "qOverlayMode":
     PersistQuickMenuSetting("RTSS", "OverlayControlMode"
         , RtssOverlayControlMode = "toggle" ? "Separate" : "Toggle")
 case "qLimiterMode":
     PersistQuickMenuSetting("RTSS", "FrameLimiterControlMode"
         , RtssFrameLimiterControlMode = "toggle" ? "Separate" : "Toggle")
 }
 QuickMenuRefresh()
}

AdjustQuickMenuSetting(id, direction) {
 global SettingsPath, ControllerMouseSpeed, MouseHideDelay, RtssCustomFrameCap
 switch id {
 case "qMouseSpeed":
     nextValue := ClampInt(ControllerMouseSpeed + (direction * 5), 5, 200)
     PersistQuickMenuSetting("Controller", "ControllerMouseSpeed", nextValue)
 case "qMouseHideDelay":
     choices := [0, 500, 1000, 2000, 3000, 5000, 10000]
     choiceIndex := 1
     smallestDistance := 0x7FFFFFFF
     for index, candidate in choices {
         distance := Abs(candidate - MouseHideDelay)
         if (distance < smallestDistance) {
             smallestDistance := distance
             choiceIndex := index
         }
     }
     choiceIndex := ClampInt(choiceIndex + direction, 1, choices.Length)
     PersistQuickMenuSetting("Timing", "MouseHideDelay", choices[choiceIndex])
 case "qFrameCap":
     nextValue := ClampInt(RtssCustomFrameCap + direction, 0, 1000)
     PersistQuickMenuSetting("RTSS", "CustomFrameCap", nextValue)
 default:
     ToggleQuickMenuSetting(id)
     return
 }
 QuickMenuRefresh()
}

QuickMenuAdjustSelected(direction) {
 global QuickMenuRows, QuickMenuSelected
 if (QuickMenuRows.Length = 0)
     return
 id := QuickMenuRows[QuickMenuSelected]["id"]

 switch id {
 case "audioOutput":
     CycleDefaultAudioOutput(direction)
 case "audioMenu", "volume":
     try {
         nextVol := ClampInt(Round(SoundGetVolume()) + (direction * 5), 0, 100)
         SoundSetVolume(nextVol)
         ShowNotification("Volume: " nextVol "%", "Success")
     } catch {
         ShowNotification("Windows volume control is unavailable", "Warning")
     }
 case "hdr":
     SetQuickMenuHdrState(direction > 0)
 case "displayResolution":
     CycleDisplayResolution(direction)
 case "displayRefresh":
     CycleDisplayFrequency(direction)
 case "displayScale":
     CycleDisplayScale(direction)
 case "rtssOverlayState":
     SetRtssOverlayState(direction > 0)
 case "rtssFrameLimit":
     ; Entering or leaving Custom adds or removes a row, and the row list is
     ; composed in QuickMenuGetDefinitions, which QuickMenuRefresh does not
     ; run. Rebuild only on that transition, never on every press.
     if CycleRtssFrameCap(direction) {
         QuickMenuBuildGui()
         return
     }
 case "rtssFrameLimitCustom":
     AdjustRtssCustomFrameCap(direction)
 case "taskPrev", "taskNext":
     ChangeQuickMenuTaskPage(direction)
 default:
     if (IsQuickMenuToggleSetting(id) || IsQuickMenuAdjustSetting(id))
         AdjustQuickMenuSetting(id, direction)
 }
 QuickMenuRefresh()
}

OpenQuickMenuDisplayPage() {
 global QuickMenuPage, QuickMenuSelected, QuickMenuDisplayModes
 global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
 global DisplaySelectedScalePercent
 QuickMenuDisplayModes := GetPrimaryDisplayModes()
 DisplaySelectedWidth := 0
 DisplaySelectedHeight := 0
 DisplaySelectedFrequency := 0
 DisplaySelectedScalePercent := 0
 EnsureDisplaySelection()
 EnsureDisplayScaleSelection()
 QuickMenuSelected := 1
 QuickMenuPage := "DISPLAY"
 QuickMenuBuildGui()
}

OpenQuickMenuTaskPage() {
 global QuickMenuPage, QuickMenuSelected, QuickMenuTaskPage, QuickMenuTaskWindows
 QuickMenuTaskWindows := GetTaskSwitcherWindows()
 QuickMenuTaskPage := 1
 QuickMenuPage := "TASKS"
 QuickMenuSelected := 1
 QuickMenuBuildGui()
}

ChangeQuickMenuTaskPage(direction) {
 global QuickMenuTaskPage, QuickMenuTaskWindows, QuickMenuSelected
 pageCount := Max(1, Ceil(QuickMenuTaskWindows.Length / 8))
 QuickMenuTaskPage += direction
 if (QuickMenuTaskPage < 1)
     QuickMenuTaskPage := pageCount
 if (QuickMenuTaskPage > pageCount)
     QuickMenuTaskPage := 1
 QuickMenuSelected := 1
 QuickMenuBuildGui()
}

SelectTaskSwitcherWindow(hwnd, lockFocus := false) {
 global PinnedForegroundHwnd, PinnedForegroundTitle, PinnedForegroundExe
 item := FindTaskSwitcherWindow(hwnd)
 if (!IsObject(item) || !DllCall("IsWindow", "Ptr", hwnd)) {
     ShowNotification("That window is no longer available", "Warning")
     OpenQuickMenuTaskPage()
     return
 }

 ; A is a one-shot switch. Y explicitly opts into the focus lock. Clear any
 ; previous lock before a normal switch so the focus engine cannot pull the old
 ; task back in front immediately.
 if !lockFocus
     ReleasePinnedForeground(false)
 HideQuickMenu(false)

 if ActivateWindowRobust(hwnd) {
     if lockFocus {
         PinnedForegroundHwnd := hwnd
         PinnedForegroundTitle := item["title"]
         PinnedForegroundExe := item["exe"]
     }
     HandleCursorAfterManagedFocus(hwnd, false)
     ShowNotification(
         (lockFocus ? "Focus lock: " : "Switched to: ")
             . ShortenQuickMenuText(item["title"], 36),
         "Success")
 } else {
     if lockFocus
         ReleasePinnedForeground(false)
     ShowNotification("Windows could not activate that window", "Warning")
 }
}

GetSelectedTaskSwitcherHwnd() {
 global QuickMenuRows, QuickMenuSelected
 if (QuickMenuRows.Length = 0 || QuickMenuSelected < 1
     || QuickMenuSelected > QuickMenuRows.Length)
     return 0
 id := QuickMenuRows[QuickMenuSelected]["id"]
 if (SubStr(id, 1, 11) != "taskWindow:")
     return 0
 return ToInt(SubStr(id, 12), 0)
}

RequestCloseTaskSwitcherWindow(hwnd) {
 global QuickMenuTaskWindows
 global PinnedForegroundHwnd

 item := FindTaskSwitcherWindow(hwnd)
 if (!IsObject(item) || !DllCall("IsWindow", "Ptr", hwnd)) {
     QuickMenuTaskWindows := GetTaskSwitcherWindows()
     QuickMenuBuildGui()
     return
 }

 if (PinnedForegroundHwnd = hwnd)
     ReleasePinnedForeground(false)

 try {
     ; WinClose sends a normal close request. It does not force-terminate the
     ; process, so applications may display their own save/confirmation dialog.
     WinClose("ahk_id " hwnd)
 } catch {
     ShowNotification("Windows could not request that window to close", "Warning")
     return
 }

 Sleep(200)
 if DllCall("IsWindow", "Ptr", hwnd) {
     ; The application may be showing a save/close confirmation. Get the
     ; always-on-top Quick Menu out of its way and return focus to the app.
     HideQuickMenu(false)
     if ActivateWindowRobust(hwnd) {
         HandleCursorAfterManagedFocus(hwnd, false)
     }
     return
 }
 QuickMenuTaskWindows := GetTaskSwitcherWindows()
 QuickMenuBuildGui()
}

ForceCloseTaskSwitcherWindow(hwnd) {
 global QuickMenuTaskWindows, PinnedForegroundHwnd
 item := FindTaskSwitcherWindow(hwnd)
 if (!IsObject(item) || !DllCall("IsWindow", "Ptr", hwnd)) {
     QuickMenuTaskWindows := GetTaskSwitcherWindows()
     QuickMenuBuildGui()
     return
 }

 if (PinnedForegroundHwnd = hwnd)
     ReleasePinnedForeground(false)

 pid := item["pid"]
 exeLower := StrLower(item["exe"])
 if IsProtectedTaskProcess(exeLower) {
     ShowNotification("That Windows or SteamShell process is protected from force-close", "Warning")
     return
 }
 try {
     ; This is intentionally stronger than WinClose and may discard unsaved
     ; work or close every window belonging to the same process.
     ProcessClose(pid)
 } catch {
     ShowNotification("Windows could not force-close that process", "Warning")
     return
 }

 Sleep(250)
 if ProcessExist(pid) {
     ShowNotification("The selected process is still running", "Warning")
     return
 }
 QuickMenuTaskWindows := GetTaskSwitcherWindows()
 QuickMenuBuildGui()
}

IsProtectedTaskProcess(exeName) {
 static protected := Map(
     "steamshell.exe", true,
     "explorer.exe", true,
     "steam.exe", true,
     "steamwebhelper.exe", true,
     "sihost.exe", true,
     "shellexperiencehost.exe", true,
     "startmenuexperiencehost.exe", true,
     "searchhost.exe", true,
     "applicationframehost.exe", true,
     "dwm.exe", true,
     "winlogon.exe", true,
     "csrss.exe", true,
     "lsass.exe", true,
     "services.exe", true
 )
 return protected.Has(StrLower(Trim(exeName)))
}

QuickMenuConfirm(id, label) {
 global QuickMenuConfirmAction, QuickMenuConfirmUntilTick
 if (QuickMenuConfirmAction = id && A_TickCount < QuickMenuConfirmUntilTick) {
     QuickMenuConfirmAction := ""
     return true
 }
 QuickMenuConfirmAction := id
 QuickMenuConfirmUntilTick := A_TickCount + 5000
 ShowNotification("Select again to confirm " label, "Warning")
 QuickMenuRefresh()
 return false
}

QuickMenuActivateSelected() {
 global QuickMenuRows, QuickMenuSelected, QuickMenuPage
 global SteamQuickAccessShortcut

 if (QuickMenuRows.Length = 0)
     return
 id := QuickMenuRows[QuickMenuSelected]["id"]

 if (SubStr(id, 1, 7) = "layout:")
     return
 if (SubStr(id, 1, 11) = "taskWindow:") {
     SelectTaskSwitcherWindow(ToInt(SubStr(id, 12), 0))
     return
 }

 switch id {
 case "audioMenu":
     QuickMenuPage := "AUDIO"
     QuickMenuSelected := 1
     QuickMenuBuildGui()
     return
 case "audioOutput":
     CycleDefaultAudioOutput(1)
 case "volume":
     QuickMenuAdjustSelected(1)
 case "mute":
     try {
         SoundSetMute(-1)
         muted := SoundGetMute()
         ShowNotification(muted ? "Audio muted" : "Audio unmuted", "Success")
     } catch {
         ShowNotification("Windows mute control is unavailable", "Warning")
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
 case "display":
     OpenQuickMenuDisplayPage()
     return
 case "tasks":
     OpenQuickMenuTaskPage()
     return
 case "taskPrev":
     ChangeQuickMenuTaskPage(-1)
     return
 case "taskNext":
     ChangeQuickMenuTaskPage(1)
     return
 case "taskRelease":
     ReleasePinnedForeground()
     OpenQuickMenuTaskPage()
     return
 case "rtssMenu":
     QuickMenuPage := "RTSS"
     QuickMenuSelected := 1
     QuickMenuBuildGui()
     return
 case "rtssStart":
     if !EnsureRtssRunning()
         ShowNotification("RTSS could not be started", "Warning")
     QuickMenuBuildGui()
     return
 case "rtssOverlayState", "overlayToggle":
     ToggleRtssOverlay()
 case "limiterToggle":
     ToggleRtssFrameLimiter()
 case "rtssFrameLimit":
     if CycleRtssFrameCap(1) {
         QuickMenuBuildGui()
         return
     }
 case "rtssFrameLimitCustom":
     AdjustRtssCustomFrameCap(1)
 case "rtssSaveProfile":
     ; Writes a file RTSS then applies to that game on every future launch,
     ; with nothing on screen afterwards to say it happened. Confirmed.
     if (RtssProfileTargetExe() = "") {
         ShowNotification("No foreground game to save a profile for", "Warning")
     } else if QuickMenuConfirm("rtssSaveProfile",
         "saving " RtssProfileTargetExe() " frame limit") {
         SaveRtssFrameLimitToProfile()
     }
 case "overlayOn":
     SetRtssOverlayState(true)
 case "overlayOff":
     SetRtssOverlayState(false)
 case "limiterOn":
     SetRtssFrameLimiterState(true)
 case "limiterOff":
     SetRtssFrameLimiterState(false)
 case "rtssSettings":
     HideQuickMenu(false)
     ShowSettingsEditorCategory("RTSS & Performance")
     return
 case "settings":
     QuickMenuPage := "SETTINGS"
     QuickMenuSelected := 1
     QuickMenuBuildGui()
     return
 case "settingsGeneral":
     QuickMenuPage := "SETTINGS_GENERAL"
     QuickMenuSelected := 1
     QuickMenuBuildGui()
     return
 case "settingsInput":
     QuickMenuPage := "SETTINGS_INPUT"
     QuickMenuSelected := 1
     QuickMenuBuildGui()
     return
 case "settingsFocus":
     QuickMenuPage := "SETTINGS_FOCUS"
     QuickMenuSelected := 1
     QuickMenuBuildGui()
     return
 case "settingsRtss":
     QuickMenuPage := "SETTINGS_RTSS"
     QuickMenuSelected := 1
     QuickMenuBuildGui()
     return
 case "settingsEditor":
     HideQuickMenu(false)
     ShowSettingsEditor()
     return
 case "settingsReload":
     ReloadSettings()
     return
 case "qControllerMap":
     HideQuickMenu(false)
     ShowControllerMappingWindow()
     return
 case "steamMenu":
     if !IsSteamRunning() {
         HideQuickMenu(false)
         LaunchSteamAndReturnToShell()
         return
     }
     QuickMenuHideThenSteamMenu(IsSteamProcess(GetQuickMenuPreviousExe()))
     return
 case "steamQuickAccess":
     if !IsSteamRunning()
         return
     QuickMenuHideThenSend(SteamQuickAccessShortcut)
     return
 case "gameBar":
     QuickMenuHideThenSend("#g")
     return
 case "layout":
     QuickMenuPage := "LAYOUT"
     QuickMenuSelected := 1
     QuickMenuBuildGui()
     return
 case "control":
     HideQuickMenu(false)
     ShowControlPanel()
 case "health":
     HideQuickMenu(false)
     ShowHealthCheck()
 case "desktop":
     if !QuickMenuConfirm("desktop", "exit Steam to desktop")
         return
     HideQuickMenu(false)
     ExitSteamAndRestoreDesktop()
 case "returnShell":
     if !QuickMenuConfirm("returnShell", "return to SteamShell")
         return
     HideQuickMenu(false)
     ReturnToShellMode("Quick Menu request")
 case "exitApp":
     if !QuickMenuConfirm("exitApp", "close SteamShell")
         return
     HideQuickMenu(false)
     ExitSteamShell()
 case "system":
     QuickMenuPage := "SYSTEM"
     QuickMenuSelected := 1
     QuickMenuBuildGui()
     return
 case "audioBack", "systemBack", "tasksBack", "displayBack", "rtssBack", "layoutBack", "settingsBack", "settingsHome":
     QuickMenuGoBack()
     return
 case "sleep":
     if !QuickMenuConfirm("sleep", "sleep")
         return
     HideQuickMenu(false)
     try {
         DllCall("PowrProf\SetSuspendState", "Int", 0, "Int", 0, "Int", 0)
     }
 case "restart":
     if !QuickMenuConfirm("restart", "restart")
         return
     HideQuickMenu(false)
     try {
         Shutdown(2)
     }
 case "shutdown":
     if !QuickMenuConfirm("shutdown", "shut down")
         return
     HideQuickMenu(false)
     try {
         Shutdown(1)
     }
 default:
     if IsQuickMenuToggleSetting(id)
         ToggleQuickMenuSetting(id)
     else if IsQuickMenuAdjustSetting(id)
         AdjustQuickMenuSetting(id, 1)
 }
 QuickMenuRefresh()
}

; ------------------------------------------------------------------------------
; Quick-menu integrations: display, HDR shortcut, and RTSS HotkeyHandler
; ------------------------------------------------------------------------------
GetActiveAudioOutputDevices() {
 devices := []
 iidDevice := "{D666063F-1587-4E43-81F1-B948E807363F}" ; IMMDevice

 Loop 32 {
     index := A_Index
     try {
         name := SoundGetName(, index)
     } catch {
         break
     }
     if (name = "")
         continue

     try {
         device := SoundGetInterface(iidDevice, , index)
         idPtr := 0
         ComCall(5, device, "Ptr*", &idPtr) ; IMMDevice::GetId
         id := idPtr ? StrGet(idPtr, "UTF-16") : ""
         if (idPtr)
             DllCall("Ole32\CoTaskMemFree", "Ptr", idPtr)
         if (id != "")
             devices.Push(Map("name", name, "id", id))
     } catch {
         ; Keep enumeration safe; unsupported devices are omitted.
     }
 }
 return devices
}

SetDefaultAudioEndpointId(endpointId) {
 if (endpointId = "")
     return false

 ; Windows exposes default-endpoint selection through the PolicyConfig COM
 ; interface used by the Sound control panel. Try the modern interface first,
 ; then the Vista-compatible interface retained by current Windows versions.
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
     ; Apply to console, multimedia, and communications roles.
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
 if (QuickMenuAudioDevices.Length = 0)
     QuickMenuAudioDevices := GetActiveAudioOutputDevices()
 if (QuickMenuAudioDevices.Length = 0) {
     ShowNotification("No active Windows audio outputs were found", "Warning")
     return
 }

 currentName := ""
 try currentName := SoundGetName()
 currentIndex := 0
 for index, device in QuickMenuAudioDevices {
     if (device["name"] = currentName) {
         currentIndex := index
         break
     }
 }
 if (currentIndex = 0)
     currentIndex := 1
 nextIndex := currentIndex + direction
 if (nextIndex < 1)
     nextIndex := QuickMenuAudioDevices.Length
 if (nextIndex > QuickMenuAudioDevices.Length)
     nextIndex := 1

 target := QuickMenuAudioDevices[nextIndex]
 if SetDefaultAudioEndpointId(target["id"]) {
     ShowNotification("Audio output: " target["name"], "Success")
 } else {
     ShowNotification("Windows could not switch the audio output", "Warning")
 }
 QuickMenuRefresh()
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

GetCurrentDisplayModeText() {
 global DisplayPendingOldMode, DisplayPendingUntilTick
 mode := GetPrimaryDisplayMode()
 if !IsObject(mode)
     return "Unavailable"
 text := mode["width"] "×" mode["height"] "  •  " mode["frequency"] " Hz"
 scale := GetPrimaryDisplayScale()
 if IsObject(scale)
     text .= "  •  " scale["percent"] "%"
 if IsObject(DisplayPendingOldMode) {
     seconds := Max(0, Ceil((DisplayPendingUntilTick - A_TickCount) / 1000))
     text .= "  KEEP? " seconds "s"
 }
 return text
}

GetPrimaryDisplayModes() {
 modes := []
 seen := Map()
 modeIndex := 0
 Loop 512 {
     dm := Buffer(220, 0)
     NumPut("UShort", 220, dm, 68)
     ok := false
     try ok := DllCall("User32\EnumDisplaySettingsW", "Ptr", 0, "UInt", modeIndex, "Ptr", dm, "Int")
     if (!ok)
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

 ; Stable insertion sort: resolution first, then refresh rate.
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
 NumPut("UInt", 0x580000, dm, 72) ; width | height | display frequency
 NumPut("UInt", mode["width"], dm, 172)
 NumPut("UInt", mode["height"], dm, 176)
 NumPut("UInt", mode["frequency"], dm, 184)
 try {
     result := DllCall("User32\ChangeDisplaySettingsExW"
         , "Ptr", 0, "Ptr", dm, "Ptr", 0, "UInt", 0, "Ptr", 0, "Int")
     return (result = 0)
 } catch {
     return false
 }
}

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

; Resolve the primary GDI display to its active DisplayConfig source and target.
; The target identity is what Windows' Advanced Color packets require.
GetPrimaryDisplayConfigSource() {
 primaryName := GetPrimaryDisplayDeviceName()
 if (primaryName = "")
     return 0
 flags := 0x2
 Loop 3 {
     pathCount := 0
     modeCount := 0
     result := -1
     try result := DllCall("User32\GetDisplayConfigBufferSizes",
         "UInt", flags, "UInt*", &pathCount, "UInt*", &modeCount, "Int")
     if (result != 0 || pathCount < 1)
         return 0
     paths := Buffer(pathCount * 72, 0)
     modes := Buffer(Max(1, modeCount) * 64, 0)
     try result := DllCall("User32\QueryDisplayConfig",
         "UInt", flags, "UInt*", &pathCount, "Ptr", paths,
         "UInt*", &modeCount, "Ptr", modes, "Ptr", 0, "Int")
     if (result = 122)
         continue
     if (result != 0)
         return 0
     Loop pathCount {
         pathOffset := (A_Index - 1) * 72
         adapterLow := NumGet(paths, pathOffset, "UInt")
         adapterHigh := NumGet(paths, pathOffset + 4, "Int")
         sourceId := NumGet(paths, pathOffset + 8, "UInt")
         sourceName := Buffer(84, 0)
         NumPut("UInt", 1, sourceName, 0)
         NumPut("UInt", 84, sourceName, 4)
         NumPut("UInt", adapterLow, sourceName, 8)
         NumPut("Int", adapterHigh, sourceName, 12)
         NumPut("UInt", sourceId, sourceName, 16)
         getResult := -1
         try getResult := DllCall(
             "User32\DisplayConfigGetDeviceInfo", "Ptr", sourceName, "Int")
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
                 "targetId", NumGet(paths, pathOffset + 28, "UInt"))
         }
     }
     return 0
 }
 return 0
}

DisplayScaleLevels() {
 return [100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500]
}

; Windows Settings uses private-but-stable DisplayConfig DPI packets for its
; per-display scale ladder. Failures are non-fatal and simply make the row
; unavailable while resolution, refresh, and HDR continue to work.
GetPrimaryDisplayScale() {
 static warned := false
 source := GetPrimaryDisplayConfigSource()
 if !IsObject(source)
     return 0
 packet := Buffer(32, 0)
 NumPut("UInt", 0xFFFFFFFD, packet, 0)
 NumPut("UInt", 32, packet, 4)
 NumPut("UInt", source["adapterLow"], packet, 8)
 NumPut("Int", source["adapterHigh"], packet, 12)
 NumPut("UInt", source["sourceId"], packet, 16)
 result := -1
 try result := DllCall(
     "User32\DisplayConfigGetDeviceInfo", "Ptr", packet, "Int")
 if (result != 0) {
     if !warned {
         warned := true
         LogLine("Display scale unavailable; GET_DPI_SCALE returned " result ".")
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
     || currentIndex < 1 || currentIndex > count)
     return 0
 warned := false
 options := []
 Loop count
     options.Push(levels[A_Index])
 return Map(
     "percent", options[currentIndex],
     "options", options,
     "minimum", minimum,
     "current", current,
     "maximum", maximum)
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
 NumPut("UInt", 0xFFFFFFFC, packet, 0)
 NumPut("UInt", 24, packet, 4)
 NumPut("UInt", source["adapterLow"], packet, 8)
 NumPut("Int", source["adapterHigh"], packet, 12)
 NumPut("UInt", source["sourceId"], packet, 16)
 NumPut("Int", info["minimum"] + selectedIndex - 1, packet, 20)
 result := -1
 try result := DllCall(
     "User32\DisplayConfigSetDeviceInfo", "Ptr", packet, "Int")
 if (result = 0)
     LogLine("Display scale: primary display set to " percent "%.")
 else
     LogLine("Display scale: SET_DPI_SCALE failed with error " result ".")
 return result = 0
}

QueueQuickMenuDisplayReflow() {
 SetTimer(QuickMenuDisplayReflow, -350)
}

QuickMenuDisplayReflow() {
 global QuickMenuVisible
 if QuickMenuVisible
     QuickMenuBuildGui()
}

GetPrimaryHdrState() {
 static warned := false
 path := GetPrimaryDisplayConfigSource()
 if !IsObject(path)
     return 0
 packet := Buffer(32, 0)
 NumPut("UInt", 9, packet, 0) ; DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO
 NumPut("UInt", 32, packet, 4)
 NumPut("UInt", path["targetAdapterLow"], packet, 8)
 NumPut("Int", path["targetAdapterHigh"], packet, 12)
 NumPut("UInt", path["targetId"], packet, 16)
 result := -1
 try result := DllCall(
     "User32\DisplayConfigGetDeviceInfo", "Ptr", packet, "Int")
 if (result != 0) {
     if !warned {
         warned := true
         LogLine("HDR live state unavailable; DisplayConfig returned " result ".")
     }
     return 0
 }
 warned := false
 flags := NumGet(packet, 20, "UInt")
 return Map(
     "supported", (flags & 0x1) != 0,
     "enabled", (flags & 0x2) != 0,
     "forceDisabled", (flags & 0x8) != 0)
}

ApplyPrimaryHdrState(enabled) {
 path := GetPrimaryDisplayConfigSource()
 if !IsObject(path)
     return false
 packet := Buffer(24, 0)
 NumPut("UInt", 10, packet, 0) ; DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE
 NumPut("UInt", 24, packet, 4)
 NumPut("UInt", path["targetAdapterLow"], packet, 8)
 NumPut("Int", path["targetAdapterHigh"], packet, 12)
 NumPut("UInt", path["targetId"], packet, 16)
 NumPut("UInt", enabled ? 1 : 0, packet, 20)
 result := -1
 try result := DllCall(
     "User32\DisplayConfigSetDeviceInfo", "Ptr", packet, "Int")
 if (result = 0)
     LogLine("HDR: primary display turned " (enabled ? "on." : "off."))
 else
     LogLine("HDR: SET_ADVANCED_COLOR_STATE failed with error " result ".")
 return result = 0
}

SetQuickMenuHdrState(enabled, allowToggleFallback := false) {
 current := GetPrimaryHdrState()
 if !IsObject(current) {
     if allowToggleFallback {
         ; Compatibility fallback for Windows/display drivers that do not expose
         ; Advanced Color state through DisplayConfig.
         SendChordSafe("#!b")
         ShowNotification("Windows HDR toggle requested; live state is unavailable", "Warning")
     } else {
         ShowNotification("Windows HDR state is unavailable; use A to toggle", "Warning")
     }
     return
 }
 if !current["supported"] {
     ShowNotification("The primary display does not report HDR support", "Warning")
     return
 }
 if current["forceDisabled"] {
     ShowNotification("HDR is disabled by Windows or the display driver", "Warning")
     return
 }
 if (current["enabled"] = enabled)
     return
 if ApplyPrimaryHdrState(enabled)
     ShowNotification("HDR turned " (enabled ? "on" : "off"), "Success")
 else
     ShowNotification("Windows could not turn HDR " (enabled ? "on" : "off"), "Warning")
 QuickMenuRefresh()
}

ToggleQuickMenuHdrState() {
 current := GetPrimaryHdrState()
 if !IsObject(current) {
     SetQuickMenuHdrState(true, true)
     return
 }
 SetQuickMenuHdrState(!current["enabled"])
}

ConfirmPrimaryDisplayMode() {
 global DisplayPendingOldMode, DisplayPendingOldScale, DisplayPendingUntilTick
 if !IsObject(DisplayPendingOldMode)
     return
 DisplayPendingOldMode := 0
 DisplayPendingOldScale := 0
 DisplayPendingUntilTick := 0
 SetTimer(DisplayChangeSafetyTick, 0)
 ShowNotification("Display settings kept", "Success")
 QuickMenuRefresh()
}

DisplayChangeSafetyTick() {
 global DisplayPendingOldMode, DisplayPendingOldScale, DisplayPendingUntilTick
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
         ShowNotification("Display settings reverted for safety", "Warning")
     else
         ShowNotification("Unable to restore all previous display settings", "Warning")
 }
 QuickMenuRefresh()
}

EnsureRtssRunning() {
 global RtssPath
 if ProcessExist("RTSS.exe")
     return true
 path := NormalizeMediaPath(RtssPath)
 if (path = "" || !FileExist(path)) {
     programFilesX86 := ""
     try programFilesX86 := EnvGet("ProgramFiles(x86)")
     defaultPath := programFilesX86 "\RivaTuner Statistics Server\RTSS.exe"
     if (programFilesX86 != "" && FileExist(defaultPath)) {
         path := defaultPath
         RtssPath := defaultPath
     }
 }
 if (path = "" || !FileExist(path))
     return false
 try {
     Run('"' path '"', , "Min")
     if ProcessWait("RTSS.exe", 3)
         return true
 } catch {
 }
 return false
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

; RTSS publishes its global overlay/limiter flags and profile properties through
; RTSSHooks64.dll. This is optional: older or unusual installations continue to
; use the configured HotkeyHandler shortcuts.
GetRtssHooksApi() {
 global RtssPath, RtssUseDllIntegration
 global RtssHooksModule, RtssHooksDllPath, RtssHooksLastFailure
 global RtssGetFlagsProc, RtssSetFlagsProc
 global RtssLoadProfileProc, RtssGetProfilePropertyProc
 global RtssSetProfilePropertyProc, RtssSaveProfileProc, RtssUpdateProfilesProc
 if !RtssUseDllIntegration
     return 0
 rtssExe := NormalizeMediaPath(RtssPath)
 installDir := ""
 if (rtssExe != "")
     SplitPath(rtssExe, , &installDir)
 dllPath := installDir != "" ? installDir "\RTSSHooks64.dll" : ""
 if (RtssHooksModule && RtssHooksDllPath = dllPath
     && RtssGetFlagsProc && RtssSetFlagsProc) {
     return Map(
         "get", RtssGetFlagsProc, "set", RtssSetFlagsProc,
         "loadProfile", RtssLoadProfileProc,
         "getProfileProperty", RtssGetProfilePropertyProc,
         "setProfileProperty", RtssSetProfilePropertyProc,
         "saveProfile", RtssSaveProfileProc,
         "updateProfiles", RtssUpdateProfilesProc)
 }
 if RtssHooksModule
     ShutdownRtssHooksApi()
 if (dllPath = "" || !FileExist(dllPath)) {
     if (RtssHooksLastFailure != dllPath) {
         RtssHooksLastFailure := dllPath
         LogLine("RTSS live state unavailable: RTSSHooks64.dll was not found; shortcut fallback remains available.")
     }
     return 0
 }
 module := 0
 try module := DllCall("Kernel32\LoadLibraryW", "WStr", dllPath, "Ptr")
 getProc := 0
 setProc := 0
 loadProfileProc := 0
 getProfilePropertyProc := 0
 setProfilePropertyProc := 0
 saveProfileProc := 0
 updateProfilesProc := 0
 if module {
     try getProc := DllCall(
         "Kernel32\GetProcAddress", "Ptr", module, "AStr", "GetFlags", "Ptr")
     try setProc := DllCall(
         "Kernel32\GetProcAddress", "Ptr", module, "AStr", "SetFlags", "Ptr")
     try loadProfileProc := DllCall(
         "Kernel32\GetProcAddress", "Ptr", module, "AStr", "LoadProfile", "Ptr")
     try getProfilePropertyProc := DllCall(
         "Kernel32\GetProcAddress", "Ptr", module,
         "AStr", "GetProfileProperty", "Ptr")
     ; Write path. Deliberately optional: an RTSS build without these still
     ; drives the overlay and limiter flags, and the frame-cap row degrades to
     ; read-only rather than taking the whole integration down with it.
     try setProfilePropertyProc := DllCall(
         "Kernel32\GetProcAddress", "Ptr", module,
         "AStr", "SetProfileProperty", "Ptr")
     try saveProfileProc := DllCall(
         "Kernel32\GetProcAddress", "Ptr", module, "AStr", "SaveProfile", "Ptr")
     try updateProfilesProc := DllCall(
         "Kernel32\GetProcAddress", "Ptr", module, "AStr", "UpdateProfiles", "Ptr")
 }
 if (!module || !getProc || !setProc) {
     if module
         try DllCall("Kernel32\FreeLibrary", "Ptr", module, "Int")
     if (RtssHooksLastFailure != dllPath) {
         RtssHooksLastFailure := dllPath
         LogLine("RTSS live state unavailable: required DLL exports were not found; shortcut fallback remains available.")
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
 LogLine("RTSS live state connected through RTSSHooks64.dll"
     . (RtssFrameCapWritable() ? " (frame cap writable)." : "; frame cap is read-only."))
 return Map(
     "get", getProc, "set", setProc,
     "loadProfile", loadProfileProc,
     "getProfileProperty", getProfilePropertyProc,
     "setProfileProperty", setProfilePropertyProc,
     "saveProfile", saveProfileProc,
     "updateProfiles", updateProfilesProc)
}

; True when every export the write path needs resolved. Checked before the
; Quick Menu offers a value the user cannot actually apply.
RtssFrameCapWritable() {
 global RtssSetProfilePropertyProc, RtssSaveProfileProc, RtssLoadProfileProc
 return RtssLoadProfileProc && RtssSetProfilePropertyProc && RtssSaveProfileProc
}

GetRtssGlobalState() {
 global EnableRTSSIntegration, RtssUseDllIntegration
 if (!EnableRTSSIntegration || !RtssUseDllIntegration || !ProcessExist("RTSS.exe"))
     return 0
 api := GetRtssHooksApi()
 if !IsObject(api)
     return 0
 try flags := DllCall(api["get"], "UInt")
 catch as err {
     LogLine("RTSS GetFlags failed: " err.Message)
     return 0
 }
 return Map(
     "overlay", (flags & 0x1) != 0,
     "limiter", (flags & 0x4) = 0,
     "flags", flags)
}

GetQuickMenuPreviousExe() {
 global QuickMenuPreviousHwnd
 if (QuickMenuPreviousHwnd && DllCall("IsWindow", "Ptr", QuickMenuPreviousHwnd, "Int"))
     try return WinGetProcessName("ahk_id " QuickMenuPreviousHwnd)
 return ""
}

; True while the foreground application is one the user has named for automatic
; mouse mode.
;
; The mechanism is deliberately "pretend View/Back is held" rather than a second
; input mode. The View mappings are already a complete desktop mouse by default --
; right stick moves, left stick scrolls, D-pad arrows, RB left-click, RT
; right-click, Start opens the Start menu -- so reusing them means nothing new to
; design, nothing new to configure, and no second keymap that can drift from the
; first. What happens automatically is exactly what holding View/Back does.
;
; Cached briefly: this is evaluated on every poll tick at ~16 ms, and the
; foreground process cannot change faster than a person can alt-tab.
AutoMouseModeActive() {
 global EnableAutoMouseMode, AutoMouseExeSet, ScriptPid
 static cachedResult := false
 static cachedTick := 0
 ; Checked ahead of the cache so turning the feature off in Settings takes
 ; effect on the next poll rather than up to 250 ms later.
 if (!EnableAutoMouseMode || AutoMouseExeSet.Count = 0)
     return false
 if (cachedTick && A_TickCount - cachedTick < 250)
     return cachedResult
 cachedTick := A_TickCount
 cachedResult := false
 try {
     hwnd := DllCall("User32\GetForegroundWindow", "Ptr")
     if (hwnd && WinGetPID("ahk_id " hwnd) != ScriptPid)
         cachedResult := AutoMouseExeSet.Has(StrLower(WinGetProcessName("ahk_id " hwnd)))
 }
 return cachedResult
}

IsSteamProcess(exeName) {
 exeName := StrLower(Trim(exeName))
 return exeName = "steam.exe" || exeName = "steamwebhelper.exe"
}

IsSteamRunning() {
 ; A single Quick Menu repaint asks about Steam once per row. ProcessExist walks
 ; a process snapshot, so cache the answer for long enough to cover one repaint
 ; while still reacting to Steam starting or closing within a keypress or two.
 static cachedResult := false
 static cachedTick := 0
 if (cachedTick && A_TickCount - cachedTick < 500)
     return cachedResult
 cachedResult := ProcessExist("steam.exe") != 0
 cachedTick := A_TickCount
 return cachedResult
}

GetRtssFrameLimit(profileExe := "") {
 global EnableRTSSIntegration, RtssUseDllIntegration
 if (!EnableRTSSIntegration || !RtssUseDllIntegration || !ProcessExist("RTSS.exe"))
     return 0
 api := GetRtssHooksApi()
 if (!IsObject(api) || !api["loadProfile"] || !api["getProfileProperty"])
     return 0
 profileName := Trim(profileExe)
 if (profileName != "") {
     fileName := ""
     SplitPath(profileName, &fileName)
     profileName := fileName
 }
 value := Buffer(4, 0)
 try {
     DllCall(api["loadProfile"], "AStr", profileName)
     ok := DllCall(api["getProfileProperty"],
         "AStr", "FramerateLimit", "Ptr", value, "UInt", value.Size, "Int")
     if !ok
         return 0
     return Map("fps", NumGet(value, 0, "UInt"))
 } catch as err {
     LogLine("RTSS FramerateLimit query failed: " err.Message)
     return 0
 }
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
 global RtssFrameCapPresets, RtssFrameCapCustomMode
 state := GetRtssGlobalState()
 if !IsObject(state)
     return 0
 fps := RtssGlobalFrameLimit()
 if (!state["limiter"] || fps <= 0)
     return Map("mode", "off", "fps", fps, "limiter", state["limiter"])
 for _, preset in RtssFrameCapPresets {
     if (fps = preset && !RtssFrameCapCustomMode)
         return Map("mode", "preset", "fps", fps, "limiter", true)
 }
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
     ShowNotification("This RTSS build cannot set the frame cap directly", "Warning")
     return false
 }
 fps := ClampInt(fps, 0, 1000)
 value := Buffer(4, 0)
 NumPut("UInt", fps, value, 0)
 try {
     DllCall(api["loadProfile"], "AStr", "")
     ok := DllCall(api["setProfileProperty"],
         "AStr", "FramerateLimit", "Ptr", value, "UInt", value.Size, "Int")
     if !ok {
         LogLine("RTSS FramerateLimit write was rejected.")
         ShowNotification("RTSS did not accept the frame cap", "Warning")
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
     LogLine("RTSS FramerateLimit write failed: " err.Message)
     ShowNotification("RTSS did not accept the frame cap", "Warning")
     return false
 }
}

; Left/Right on the Frame Limit row. Returns true when the row set changed, so
; the caller knows a full rebuild is needed rather than a repaint: the Custom
; row is composed in QuickMenuGetDefinitions, which QuickMenuRefresh never runs.
CycleRtssFrameCap(direction) {
 global RtssFrameCapPresets, RtssFrameCapCustomMode
 state := GetRtssFrameCapState()
 if !IsObject(state) {
     ShowNotification("RTSS live state is unavailable", "Warning")
     return false
 }
 if !RtssFrameCapWritable() {
     ShowNotification("This RTSS build cannot set the frame cap directly", "Warning")
     return false
 }

 ; Coming off "Off" restores the number the profile still holds instead of
 ; jumping to the first preset. This is the payoff for never writing 0: the
 ; user's 72 survives an off/on round trip untouched. Only applies when the
 ; flag is what turned it off; a flag that is on with no target has nothing to
 ; restore and falls through to the list below.
 if (direction > 0 && state["mode"] = "off"
     && !state["limiter"] && state["fps"] > 0) {
     RtssFrameCapCustomMode := false
     ApplyRtssGlobalState("limiter", true)
     return !IsRtssFrameCapPreset(state["fps"])
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
 index := ClampInt(index + direction, 1, entries.Length)
 target := entries[index]

 wasCustom := (state["mode"] = "custom")
 if (target = "off") {
     RtssFrameCapCustomMode := false
     ; Value untouched on purpose -- see the header comment.
     ;
     ; Only written when the flag actually has to change. Left clamps to this
     ; entry at the end of the list, so without the guard every further press
     ; re-issued the SetFlags call and re-showed its notification.
     if state["limiter"]
         ApplyRtssGlobalState("limiter", false)
     return wasCustom
 }
 if (target = "custom") {
     ; Seeds from whatever is live and applies nothing. Landing on Custom must
     ; never change the frame rate by itself.
     RtssFrameCapCustomMode := true
     if (!state["limiter"] || state["fps"] <= 0) {
         SetRtssGlobalFrameLimit(RtssFrameCapPresets[1])
         ApplyRtssGlobalState("limiter", true)
     }
     return !wasCustom
 }
 RtssFrameCapCustomMode := false
 SetRtssGlobalFrameLimit(target)
 if !state["limiter"]
     ApplyRtssGlobalState("limiter", true)
 return wasCustom
}

; The one place a per-game profile is written, and only ever on an explicit,
; confirmed request. Returns the executable this would target, or "" when there
; is nothing valid to save to.
;
; The name comes from what owned the screen BEFORE the menu opened; asking now
; would always answer SteamShell. Steam's own surfaces are excluded because a
; profile named steam.exe or steamwebhelper.exe caps the client rather than a
; game, which is never what this row means.
; A profile named steam.exe caps the Steam client rather than a game, and one
; named after the shell or Explorer is meaningless.
IsUsableProfileExe(exeName) {
 exeName := StrLower(Trim(exeName))
 if (exeName = "" || IsSteamProcess(exeName))
     return false
 return exeName != "steamshell.exe" && exeName != "explorer.exe"
}

; Two sources, in order of directness.
;
; What owned the screen before the menu opened is the best answer when it is
; usable. It is not always: the window engine's Steam refocus can pull Big
; Picture forward moments before the menu opens, and a borderless game can sit
; behind a Steam surface -- in both cases the raw foreground is steam.exe, which
; is excluded, and the row read "No game in foreground" while Task Switcher was
; still listing the game.
;
; So fall back to the window engine's detected game. That is the same detection
; driving Game Foreground Assist and the Task Switcher's view of what is running,
; which is precisely what a user looking at this row means by "the game".
RtssProfileTargetExe() {
 global LastBestCandidateProc
 exeName := Trim(GetQuickMenuPreviousExe())
 if IsUsableProfileExe(exeName)
     return exeName
 exeName := Trim(LastBestCandidateProc)
 if IsUsableProfileExe(exeName)
     return exeName
 return ""
}

; Names what it actually saw rather than reporting a bare negative. "Steam is in
; front and no game was detected" and "nothing is running" are different
; problems, and the row is the only place the difference is visible.
RtssSaveProfileValueText() {
 global LastBestCandidateProc
 if !RtssFrameCapWritable()
     return "Unavailable"
 exeName := RtssProfileTargetExe()
 if (exeName != "")
     return exeName
 previous := Trim(GetQuickMenuPreviousExe())
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
 global RtssFrameLimitCacheTick, LastBestCandidateProc
 exeName := RtssProfileTargetExe()
 if (exeName = "") {
     ShowNotification("No foreground game to save a profile for", "Warning")
     return false
 }
 if !RtssFrameCapWritable() {
     ShowNotification("This RTSS build cannot write profiles directly", "Warning")
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
 LogLine("RTSS profile target " exeName " (foreground was '"
     . GetQuickMenuPreviousExe() "', engine game '" LastBestCandidateProc "').")
 try {
     ; Load the game's existing profile so unrelated properties are preserved.
     DllCall(api["loadProfile"], "AStr", exeName)
     ok := DllCall(api["setProfileProperty"],
         "AStr", "FramerateLimit", "Ptr", value, "UInt", value.Size, "Int")
     if !ok {
         LogLine("RTSS profile write was rejected for " exeName ".")
         ShowNotification("RTSS did not accept the profile write", "Warning")
         return false
     }
     DllCall(api["saveProfile"], "AStr", exeName)
     if api["updateProfiles"]
         DllCall(api["updateProfiles"])
     NotifyRtssSettingsChanged()
     ; The global profile was displaced by the LoadProfile above; restore it so
     ; the Frame Limit row keeps reading the value it is supposed to show.
     try DllCall(api["loadProfile"], "AStr", "")
     RtssFrameLimitCacheTick := 0
     LogLine("RTSS profile " exeName " saved with FramerateLimit " fps ".")
     ShowNotification(exeName ": " (fps > 0 ? fps " FPS" : "uncapped") " saved", "Success")
     return true
 } catch as err {
     LogLine("RTSS profile write failed for " exeName ": " err.Message)
     ShowNotification("RTSS did not accept the profile write", "Warning")
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
     ShowNotification("This RTSS build cannot set the frame cap directly", "Warning")
     return
 }
 current := RtssPendingFrameCap > 0 ? RtssPendingFrameCap : RtssGlobalFrameLimit()
 if (current <= 0)
     current := 60
 RtssPendingFrameCap := ClampInt(current + direction, 10, 1000)
 SetTimer(CommitRtssPendingFrameCap, -COMMIT_DELAY_MS)
}

NotifyRtssSettingsChanged() {
 hwnd := 0
 try hwnd := DllCall("User32\FindWindowW", "Ptr", 0, "WStr", "RTSS", "Ptr")
 if !hwnd
     try hwnd := DllCall("User32\FindWindowW", "Ptr", 0,
         "WStr", "RivaTuner Statistics Server", "Ptr")
 if hwnd
     try DllCall("User32\PostMessageW", "Ptr", hwnd,
         "UInt", 0x8064, "UPtr", 0, "Ptr", 0, "Int")
}

ApplyRtssGlobalState(feature, enabled) {
 if !EnsureRtssRunning()
     return false
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
         ShowNotification("RTSS " label " " (enabled ? "enabled" : "disabled"), "Success")
         return true
     }
 } catch as err {
     LogLine("RTSS SetFlags failed: " err.Message)
 }
 ShowNotification("RTSS did not confirm the " label " change", "Warning")
 return false
}

ToggleRtssOverlay() {
 global EnableRTSSIntegration, RtssOverlayToggleShortcut
 if (!EnableRTSSIntegration) {
     ShowNotification("Set [RTSS] EnableIntegration=true to use RTSS controls", "Warning")
     return
 }
 state := GetRtssGlobalState()
 if IsObject(state) {
     ApplyRtssGlobalState("overlay", !state["overlay"])
     return
 }
 if !EnsureRtssRunning() {
     ShowNotification("RTSS was not found. Configure [RTSS] Path first.", "Warning")
     return
 }
 if (RtssOverlayToggleShortcut = "") {
     ShowNotification("Configure RTSS OverlayToggleShortcut first", "Warning")
     return
 }
 SendChordSafe(RtssOverlayToggleShortcut)
 ShowNotification("RTSS overlay toggled", "Success")
}

SetRtssOverlayState(showOverlay) {
 global EnableRTSSIntegration, RtssOverlayOnShortcut, RtssOverlayOffShortcut
 if (!EnableRTSSIntegration) {
     ShowNotification("Set [RTSS] EnableIntegration=true to use RTSS controls", "Warning")
     return
 }
 state := GetRtssGlobalState()
 if IsObject(state) {
     if (state["overlay"] != showOverlay)
         ApplyRtssGlobalState("overlay", showOverlay)
     return
 }
 shortcut := showOverlay ? RtssOverlayOnShortcut : RtssOverlayOffShortcut
 if (shortcut = "") {
     actionName := showOverlay ? "OverlayOnShortcut" : "OverlayOffShortcut"
     ShowNotification("Configure RTSS " actionName " first", "Warning")
     return
 }
 if !EnsureRtssRunning() {
     ShowNotification("RTSS was not found. Configure [RTSS] Path first.", "Warning")
     return
 }
 SendChordSafe(shortcut)
 ShowNotification(showOverlay ? "RTSS overlay show requested" : "RTSS overlay hide requested", "Success")
}

ToggleRtssFrameLimiter() {
 global EnableRTSSIntegration, RtssCustomFrameCapShortcut
 if (!EnableRTSSIntegration) {
     ShowNotification("Set [RTSS] EnableIntegration=true to use the frame limiter", "Warning")
     return
 }
 state := GetRtssGlobalState()
 if IsObject(state) {
     ApplyRtssGlobalState("limiter", !state["limiter"])
     return
 }
 if (RtssCustomFrameCapShortcut = "") {
     ShowNotification("Configure RTSS CustomFrameCapShortcut first", "Warning")
     return
 }
 if !EnsureRtssRunning() {
     ShowNotification("RTSS was not found. Configure [RTSS] Path first.", "Warning")
     return
 }
 SendChordSafe(RtssCustomFrameCapShortcut)
 ShowNotification("RTSS frame limiter toggled", "Success")
}

SetRtssFrameLimiterState(enableLimiter) {
 global EnableRTSSIntegration, RtssFrameLimiterOnShortcut, RtssFrameLimiterOffShortcut
 if (!EnableRTSSIntegration) {
     ShowNotification("Set [RTSS] EnableIntegration=true to use the frame limiter", "Warning")
     return
 }
 state := GetRtssGlobalState()
 if IsObject(state) {
     if (state["limiter"] != enableLimiter)
         ApplyRtssGlobalState("limiter", enableLimiter)
     return
 }
 shortcut := enableLimiter ? RtssFrameLimiterOnShortcut : RtssFrameLimiterOffShortcut
 if (shortcut = "") {
     actionName := enableLimiter ? "FrameLimiterOnShortcut" : "FrameLimiterOffShortcut"
     ShowNotification("Configure RTSS " actionName " first", "Warning")
     return
 }
 if !EnsureRtssRunning() {
     ShowNotification("RTSS was not found. Configure [RTSS] Path first.", "Warning")
     return
 }
 SendChordSafe(shortcut)
 ShowNotification(enableLimiter ? "RTSS frame limiter enable requested" : "RTSS frame limiter disable requested", "Success")
}


PollController() {
 global EnableControllerMouseMode, ControllerIndex, ControllerDeadzone
 global ControllerMouseSpeed, ControllerMouseFastMultiplier
 global ControllerScrollIntervalMs, ControllerScrollStep, ControllerChordHoldMs
 global QuickMenuVisible, EnableQuickMenu, QuickMenuChordHoldMs
 global SettingsEditorDialogActive
 global ControllerTestGui

 static state := Buffer(16, 0)
 static prevButtons := 0
 static lastScroll := 0
 static prevViewDown := false
 static quickChordSince := 0
 static quickChordFired := false
 static settingsChordSince := 0
 static settingsChordFired := false
 ; Per-button press tracking (to support Short/Long bindings) without ByRef locals.
 static downTick := Map()
 static longFired := Map()
 static prevTrigDown := Map("LT", false, "RT", false)
 static settingsPrevLtDown := false
 static settingsPrevRtDown := false


 static inPoll := false
 static btnDefs := [
 ["A", 0x1000],
 ["B", 0x2000],
 ["X", 0x4000],
 ["Y", 0x8000],
 ["LB", 0x0100],
 ["RB", 0x0200],
 ["Start", 0x0010],
 ["L3", 0x0040],
 ["R3", 0x0080],
 ]

 ; Ensure keys exist
 for def in btnDefs {
 name := def[1]
 if !downTick.Has(name)
 downTick[name] := 0
 if !longFired.Has(name)
 longFired[name] := false
 }
 if !downTick.Has("LT")
 downTick["LT"] := 0
 if !longFired.Has("LT")
 longFired["LT"] := false
 if !downTick.Has("RT")
 downTick["RT"] := 0
 if !longFired.Has("RT")
 longFired["RT"] := false

 if (inPoll)
 return
 inPoll := true
 try {

 settingsControllerActive := SettingsEditorControllerActive()
 settingsPrimaryActive := SettingsEditorPrimaryActive()
 isControllerTestActive := ControllerTestActive()
 if (!EnableControllerMouseMode && !EnableQuickMenu
     && !settingsControllerActive && !isControllerTestActive)
 return

 if (XInputGetState(ControllerIndex, &state) != 0) {
     if isControllerTestActive {
         try ControllerTestGui["ControllerButtons"].Text :=
             "No controller detected at configured index " (ControllerIndex + 1) "."
     }
     ; Discard all edge/hold state while disconnected. Otherwise reconnecting
     ; can synthesize stale releases or complete an old long-press.
     prevButtons := 0
     prevViewDown := false
     quickChordSince := 0
     quickChordFired := false
     settingsChordSince := 0
     settingsChordFired := false
     prevTrigDown["LT"] := false
     prevTrigDown["RT"] := false
     settingsPrevLtDown := false
     settingsPrevRtDown := false
     for def in btnDefs {
         downTick[def[1]] := 0
         longFired[def[1]] := false
     }
     downTick["LT"] := 0, longFired["LT"] := false
     downTick["RT"] := 0, longFired["RT"] := false
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

 ; The controller test owns all input while visible so calibration cannot
 ; accidentally launch mapped actions, open overlays, or navigate another app.
 if ControllerTestActive() {
     UpdateControllerTest(buttons, lt, rt, lx, ly, rx, ry)
     prevButtons := buttons
     prevViewDown := false
     quickChordSince := 0
     quickChordFired := false
     settingsChordSince := 0
     settingsChordFired := false
     for def in btnDefs {
         downTick[def[1]] := 0
         longFired[def[1]] := false
     }
     downTick["LT"] := 0, longFired["LT"] := false, prevTrigDown["LT"] := false
     downTick["RT"] := 0, longFired["RT"] := false, prevTrigDown["RT"] := false
     settingsPrevLtDown := false
     settingsPrevRtDown := false
     return
 }

 ; Deadzone
 if (Abs(lx) < ControllerDeadzone)
 lx := 0
 if (Abs(ly) < ControllerDeadzone)
 ly := 0
 if (Abs(rx) < ControllerDeadzone)
 rx := 0
 if (Abs(ry) < ControllerDeadzone)
 ry := 0


 ; Controller chord: LT+RT+LB+RB+L3+R3 opens Full Settings (works even without
 ; holding View/Back). This is the emergency route on a handheld with no
 ; keyboard, so it stays reachable from anywhere the poll still runs.
 ;
 ; Three rules, matching the Quick Menu chord below and XFE's equivalent:
 ;
 ; 1. It must be HELD. Firing on the press edge meant a stray grip during play
 ;    could throw Full Settings over a running game.
 ; 2. It yields to any consumer that already owns controller input. The gates
 ;    further down (recovery, Quick Menu, Settings) each return, so a chord
 ;    evaluated above them could open Settings while the Quick Menu kept
 ;    receiving every button -- a focused window that ignores input and a
 ;    background one that does not. Each of those surfaces already offers its
 ;    own route to Settings, so declining here loses nothing.
 ; 3. It returns once fired, so the same press cannot also drive whatever
 ;    opened.
 ;
 ; The triggers are readable here because standalone reads XInput directly. If
 ; a DirectInput or winmm backend is ever added they share one axis and cancel
 ; out; XFE's chord already drops them for exactly that reason.
 settingsComboNow := ((lt > 30) && (rt > 30)
     && (buttons & 0x0100) && (buttons & 0x0200)
     && (buttons & 0x0040) && (buttons & 0x0080))
 if (settingsComboNow
     && !QuickMenuVisible
     && !settingsControllerActive
     && !StartupRecoveryControllerActive()) {
     if (!settingsChordSince)
         settingsChordSince := now
     if (!settingsChordFired && (now - settingsChordSince >= QuickMenuChordHoldMs)) {
         settingsChordFired := true
         try LogLine("Controller Settings chord detected.")
         try ShowSettingsEditor()
         return
     }
 } else {
     settingsChordSince := 0
     settingsChordFired := false
 }

 pressed := buttons & ~prevButtons
 released := (~buttons) & prevButtons
 prevButtons := buttons

 ; Full Settings reserves the analog triggers for category changes. Track
 ; their edges here—even while View/Back is held—so releasing Back cannot
 ; create a stale category change. Ignore both together because both triggers
 ; are part of the Full Settings fallback chord.
 settingsLtDown := lt > 30
 settingsRtDown := rt > 30
 settingsCategoryDirection := 0
 if (settingsPrimaryActive
     && !SettingsEditorDialogActive
     && !(buttons & 0x0020)
     && !(settingsLtDown && settingsRtDown)) {
     if (settingsLtDown && !settingsPrevLtDown)
         settingsCategoryDirection := -1
     else if (settingsRtDown && !settingsPrevRtDown)
         settingsCategoryDirection := 1
 }
 settingsPrevLtDown := settingsLtDown
 settingsPrevRtDown := settingsRtDown

 if DesktopRecoveryControllerActive() {
     RecoveryDialogHandleController(pressed)
     return
 }
 if StartupRecoveryControllerActive() {
     RecoveryDialogHandleController(pressed)
     return
 }

 ; Hold L3+R3 without Back/Start, shoulders, or triggers to open/close the
 ; Quick Menu. Excluding the other buttons prevents overlap with Steam's
 ; Back+Start behavior and with the six-button Full Settings fallback chord.
 quickChordNow := (EnableQuickMenu
     && (buttons & 0x0040) && (buttons & 0x0080)
     && !(buttons & 0x0020) && !(buttons & 0x0010)
     && !(buttons & 0x0100) && !(buttons & 0x0200)
     && lt <= 30 && rt <= 30)
 if (quickChordNow) {
     if (!quickChordSince)
         quickChordSince := now
     if (!quickChordFired && (now - quickChordSince >= QuickMenuChordHoldMs)) {
         quickChordFired := true
         ToggleQuickMenu()
         return
     }
 } else {
     quickChordSince := 0
     quickChordFired := false
 }

 ; While the quick menu owns focus, route controller presses to it before
 ; evaluating the normal View/Back modifier mappings.
 if (QuickMenuVisible) {
     QuickMenuWatchForegroundLoss()
     QuickMenuHandleController(pressed, released, lx, ly, buttons)
     return
 }

 ; The full Settings editor has controller-first navigation and automatic
 ; right-stick mouse movement. Holding View/Back deliberately falls through
 ; to the normal configurable mappings so mapped clicks and shortcuts remain
 ; available inside Settings.
 if (settingsControllerActive) {
     if (SettingsEditorDialogActive || !(buttons & 0x0020)) {
         prevViewDown := false
         for def in btnDefs {
             name := def[1]
             downTick[name] := 0
             longFired[name] := false
         }
         downTick["LT"] := 0, longFired["LT"] := false, prevTrigDown["LT"] := false
         downTick["RT"] := 0, longFired["RT"] := false, prevTrigDown["RT"] := false
         if (SettingsEditorDialogActive || settingsPrimaryActive)
             SettingsEditorHandleController(
                 pressed, lx, ly, rx, ry, settingsCategoryDirection)
         else
             SettingsEditorHandlePointer(pressed, rx, ry)
         return
     }
 }

 ; Quick Menu and Settings navigation still require polling when normal
 ; controller mouse/mapping mode is disabled. Stop here before processing any
 ; View/Back mapping, stick movement, scrolling, or D-pad passthrough.
 if (!EnableControllerMouseMode) {
     prevViewDown := false
     for def in btnDefs {
         downTick[def[1]] := 0
         longFired[def[1]] := false
     }
     downTick["LT"] := 0, longFired["LT"] := false, prevTrigDown["LT"] := false
     downTick["RT"] := 0, longFired["RT"] := false, prevTrigDown["RT"] := false
     return
 }

; Automatic mouse mode is expressed as a virtual View/Back hold, so every branch
; below is reached identically whether the user is holding the button or the
; foreground application is on their list.
;
; Deliberately evaluated AFTER the Quick Menu and Settings chords above, which
; test the real button state. That is what keeps a misconfigured list
; recoverable: name a game by mistake and the controller becomes a mouse inside
; it, but L3+R3 still opens the Quick Menu and the Settings chord still opens
; Settings, so the list can be corrected without a keyboard.
autoMouse := AutoMouseModeActive()
if (autoMouse && MouseHidden) {
    ; Moving a pointer that cannot be seen is not a usable mode.
    SystemCursor("Show")
    MouseHidden := false
}
viewDown := (buttons & 0x0020) || autoMouse
if (!viewDown) {
 prevViewDown := false
 ; Reset press tracking so Short/Long doesn't misfire when View/Back is not held.
 for def in btnDefs {
 name := def[1]
 downTick[name] := 0
 longFired[name] := false
 }
 downTick["LT"] := 0, longFired["LT"] := false, prevTrigDown["LT"] := false
 downTick["RT"] := 0, longFired["RT"] := false, prevTrigDown["RT"] := false
 return
}

; If View/Back was just pressed, "adopt" any buttons already held so releasing them still triggers Short.
if (!prevViewDown) {
 for def in btnDefs {
 name := def[1]
 mask := def[2]
 if ((buttons & mask) && !downTick[name]) {
 downTick[name] := now
 longFired[name] := false
 }
 }
 if ((lt > 30) && !downTick["LT"]) {
 downTick["LT"] := now
 longFired["LT"] := false
 prevTrigDown["LT"] := true
 }
 if ((rt > 30) && !downTick["RT"]) {
 downTick["RT"] := now
 longFired["RT"] := false
 prevTrigDown["RT"] := true
 }
}
prevViewDown := true


 ; Right stick -> mouse move (RT can act as a "fast" modifier)
 if (rx != 0 || ry != 0) {
 speed := ControllerMouseSpeed
 if (rt > 30)
 speed := Round(speed * ControllerMouseFastMultiplier)
 dx := Round((rx / 32767.0) * speed)
 dy := Round((-ry / 32767.0) * speed) ; up is negative screen y
 if (dx != 0 || dy != 0)
 try MouseMove(dx, dy, 0, "R")
 }

 ; Left stick Y -> scroll wheel (rate-limited)
 if (ly != 0) {
 if (now - lastScroll >= ControllerScrollIntervalMs) {
 lastScroll := now
 steps := ControllerScrollStep
 if (ly > 0) {
 Loop steps
 try Send("{WheelUp}")
 } else {
 Loop steps
 try Send("{WheelDown}")
 }
 }
 }

 ; Configurable digital buttons (Short/Long) while holding View/Back
 for def in btnDefs {
 name := def[1]
 mask := def[2]

 if (pressed & mask) {
 downTick[name] := now
 longFired[name] := false
 }

 if ((buttons & mask) && !longFired[name] && downTick[name] && (now - downTick[name]) >= ControllerChordHoldMs) {
 if HasLongBinding(name) {
 longFired[name] := true
 ExecuteControllerBinding(name ".Long")
 }
 }

 if ((released & mask) && downTick[name]) {
 if (!longFired[name])
 ExecuteControllerBinding(name ".Short")
 downTick[name] := 0
 longFired[name] := false
 }
 }

 ; Triggers (analog) as configurable Short/Long while holding View/Back
 ; LT
 ltIsDown := (lt > 30)
 ltPressedEdge := (ltIsDown && !prevTrigDown["LT"])
 ltReleasedEdge := (!ltIsDown && prevTrigDown["LT"])
 prevTrigDown["LT"] := ltIsDown

 if (ltPressedEdge) {
 downTick["LT"] := now
 longFired["LT"] := false
 }
 if (ltIsDown && !longFired["LT"] && downTick["LT"] && (now - downTick["LT"]) >= ControllerChordHoldMs) {
 if HasLongBinding("LT") {
 longFired["LT"] := true
 ExecuteControllerBinding("LT.Long")
 }
 }
 if (ltReleasedEdge && downTick["LT"]) {
 if (!longFired["LT"])
 ExecuteControllerBinding("LT.Short")
 downTick["LT"] := 0
 longFired["LT"] := false
 }

 ; RT
 rtIsDown := (rt > 30)
 rtPressedEdge := (rtIsDown && !prevTrigDown["RT"])
 rtReleasedEdge := (!rtIsDown && prevTrigDown["RT"])
 prevTrigDown["RT"] := rtIsDown

 if (rtPressedEdge) {
 downTick["RT"] := now
 longFired["RT"] := false
 }
 if (rtIsDown && !longFired["RT"] && downTick["RT"] && (now - downTick["RT"]) >= ControllerChordHoldMs) {
 if HasLongBinding("RT") {
 longFired["RT"] := true
 ExecuteControllerBinding("RT.Long")
 }
 }
 if (rtReleasedEdge && downTick["RT"]) {
 if (!longFired["RT"])
 ExecuteControllerBinding("RT.Short")
 downTick["RT"] := 0
 longFired["RT"] := false
 }

 ; D-Pad arrows (one-shot per press)
 if (pressed & 0x0001)
 try SendInput("{Up}")
 if (pressed & 0x0002)
 try SendInput("{Down}")
 if (pressed & 0x0004)
 try SendInput("{Left}")
 if (pressed & 0x0008)
 try SendInput("{Right}")

 ; Best-effort: map Guide (if present) to Y.Short
 if (pressed & 0x0400)
 ExecuteControllerBinding("Y.Short")
 } finally {
 inPoll := false
 }
}
; ==============================================================================
; DWM CLOAK CHECK (skip UWP/hidden surfaces)
; ==============================================================================
IsCloaked(hwnd) {
 cloaked := 0
 try {
 hr := DllCall("dwmapi\DwmGetWindowAttribute"
 , "Ptr", hwnd
 , "UInt", 14
 , "UInt*", cloaked
 , "UInt", 4
 , "Int")
 return (hr = 0) && (cloaked != 0)
 } catch {
 return false
 }
}

; ==============================================================================
; EXCLUSIONS (never touch OSK or Steam Keyboard)
; ==============================================================================
IsExcludedForCenterMax(title, winClass, proc) {
 global WmExcludeExeSet, WmExcludeClassSet

 t := StrLower(title)
 c := StrLower(winClass)
 p := StrLower(proc)

 ; INI-driven exclusions for window-management (center/maximize)
 try {
 if (p != "" && IsObject(WmExcludeExeSet) && WmExcludeExeSet.Has(p))
 return true
 if (c != "" && IsObject(WmExcludeClassSet) && WmExcludeClassSet.Has(c))
 return true
 } catch {
 }

 ; Built-in exclusions (OSK + Steam Keyboard)
 if (p = "osk.exe")
 return true
 if (c = "oskmainclass")
 return true
 if InStr(t, "on-screen keyboard")
 return true
 if (p = "steam.exe" && InStr(t, "keyboard"))
 return true
 return false
}

; ==============================================================================
; COORDINATED WINDOW ENGINE
; One validated inventory feeds geometry, game detection, AlwaysFocus, pinned
; focus, and Steam fallback. Only the arbiter performs scheduled activation.
; ==============================================================================
ResetWindowEngineState(resetCpu := false) {
 global WindowEngineSnapshot, WindowEngineSnapshotByHwnd
 global WindowEngineGeometryState, WindowEngineCpuSamples
 global WindowEngineLastSnapshotTick, WindowEngineLastFocusTick
 global WindowEngineLastDecision
 global MouseParkObservedForegroundHwnd, MouseParkSawNonSteamForeground
 CancelPendingMousePark()
 WindowEngineSnapshot := []
 WindowEngineSnapshotByHwnd := Map()
 WindowEngineGeometryState := Map()
 WindowEngineLastSnapshotTick := 0
 WindowEngineLastFocusTick := 0
 WindowEngineLastDecision := "Engine reset"
 MouseParkObservedForegroundHwnd := 0
 MouseParkSawNonSteamForeground := false
 if resetCpu
     WindowEngineCpuSamples := Map()
}

WindowEngineTitleMatchesBpm(title) {
 global BpmTitle
 expected := Trim(BpmTitle)
 return expected != "" && InStr(title, expected, false) != 0
}

WindowEngineBuildSnapshot() {
 global WindowEngineSnapshot, WindowEngineSnapshotByHwnd
 global WindowEngineSnapshotBusy
 global WindowEngineLastSnapshotTick, WindowEngineLastWindowCount
 global ScriptPid, BpmTitle

 if WindowEngineSnapshotBusy
     return WindowEngineSnapshot
 WindowEngineSnapshotBusy := true
 snapshot := []
 byHwnd := Map()
 try {
 for hwnd in WinGetList() {
     if !DllCall("User32\IsWindow", "Ptr", hwnd, "Int")
         continue
     if IsCloaked(hwnd)
         continue

     id := "ahk_id " hwnd
     style := 0
     exStyle := 0
     try {
         style := WinGetStyle(id) + 0
     } catch {
         continue
     }
     try exStyle := WinGetExStyle(id) + 0
     if !(style & 0x10000000) ; WS_VISIBLE
         continue

     pid := 0
     title := ""
     winClass := ""
     proc := ""
     minMax := 0
     x := 0
     y := 0
     width := 0
     height := 0
     try {
         pid := WinGetPID(id)
         title := WinGetTitle(id)
         winClass := WinGetClass(id)
         proc := StrLower(WinGetProcessName(id))
         minMax := WinGetMinMax(id)
         WinGetPos(&x, &y, &width, &height, id)
     } catch {
         continue
     }

     classLower := StrLower(winClass)
     isDesktop := classLower = "progman"
         || classLower = "workerw"
         || classLower = "shell_traywnd"
         || classLower = "shell_secondarytraywnd"
     item := Map(
         "hwnd", hwnd,
         "pid", pid,
         "proc", proc,
         "title", title,
         "class", winClass,
         "classLower", classLower,
         "style", style,
         "exStyle", exStyle,
         "owner", DllCall(
             "User32\GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr"), ; GW_OWNER
         "minMax", minMax,
         "x", x,
         "y", y,
         "w", width,
         "h", height,
         "area", Max(0, width) * Max(0, height),
         "scriptOwned", pid = ScriptPid,
         "desktop", isDesktop,
         "steam", proc = "steam.exe" || proc = "steamwebhelper.exe",
         ; The pre-engine implementation used SetTitleMatchMode 2. Retain that
         ; proven partial-title behavior instead of requiring exact equality.
         "bpm", WindowEngineTitleMatchesBpm(title))
     snapshot.Push(item)
     byHwnd[hwnd] := item
 }
 WindowEngineSnapshot := snapshot
 WindowEngineSnapshotByHwnd := byHwnd
 WindowEngineLastSnapshotTick := A_TickCount
 WindowEngineLastWindowCount := snapshot.Length
 } finally {
     WindowEngineSnapshotBusy := false
 }
 return WindowEngineSnapshot
}

WindowEngineGetFreshSnapshot(maxAgeMs := 1500) {
 global WindowEngineSnapshot, WindowEngineLastSnapshotTick
 if (WindowEngineLastSnapshotTick > 0
     && A_TickCount - WindowEngineLastSnapshotTick <= maxAgeMs)
     return WindowEngineSnapshot
 return WindowEngineBuildSnapshot()
}

WindowEngineValidateItem(item) {
 if !IsObject(item)
     return false
 hwnd := item["hwnd"]
 if !DllCall("User32\IsWindow", "Ptr", hwnd, "Int")
     return false
 try {
     return WinGetPID("ahk_id " hwnd) = item["pid"]
 } catch {
     return false
 }
}

; Distinguishes an application window from a popup that merely happens to be one.
;
; Dropdown lists, menus, auto-complete lists and tooltips are all real top-level
; windows, and centring one is actively wrong rather than merely untidy: it is
; positioned relative to the control that opened it, so moving it to the middle
; of the screen detaches it from its parent and leaves it floating on its own.
; Reported from hardware on dropdown menus.
;
; Tested by structure rather than by name. A class blacklist cannot keep up --
; every UI framework invents its own popup class -- whereas the window styles
; that make something a popup are the same ones Windows itself uses to decide it
; is not a normal application window.
WindowEngineIsMovableAppWindow(item) {
 global MinCenterCoverage
 static WS_CHILD         := 0x40000000
 static WS_CAPTION       := 0x00C00000
 static WS_EX_TOOLWINDOW := 0x00000080
 static WS_EX_NOACTIVATE := 0x08000000
 static POPUP_CLASSES := Map(
     "#32768", true,                 ; menus, including combo and context menus
     "combolbox", true,              ; the list a combo box drops down
     "dropdown", true,
     "tooltips_class32", true,
     "auto-suggest dropdown", true)
 style := item["style"]
 exStyle := item["exStyle"]

 ; A child window's coordinates are relative to its parent's client area, not
 ; the screen, so "centre it on the screen" is not even a meaningful operation.
 if (style & WS_CHILD)
     return false
 ; A window that cannot be activated is by definition not the one being worked
 ; in. Menus and tooltips are the common case.
 if (exStyle & WS_EX_NOACTIVATE)
     return false
 ; A window with no title bar is either a popup or a deliberately borderless
 ; application window, and SIZE is what separates them. A dropdown is small; a
 ; borderless game or player fills most of the screen.
 ;
 ; The first attempt at this required the window to be OWNED as well, on the
 ; reasoning that a dialog is owned but keeps its caption. That caught Explorer's
 ; dropdowns and missed Qt's -- PCSX2's menus are unowned, so they passed
 ; straight through. Ownership turned out to be a framework detail; size is not.
 ;
 ; Captioned windows are exempt from the size test on purpose: a small dialog
 ; has a title bar and is worth centring, which is the case a bare size floor
 ; would wrongly skip.
 if !(style & WS_CAPTION) {
     if (item["w"] < A_ScreenWidth * MinCenterCoverage
         || item["h"] < A_ScreenHeight * MinCenterCoverage)
         return false
 }
 ; Tool windows are palettes, popups and notification surfaces. Older games that
 ; present a titled ToolWindow surface are still covered, because a game window
 ; passes the size test above and this one only rejects the small ones.
 if ((exStyle & WS_EX_TOOLWINDOW)
     && (item["w"] < A_ScreenWidth * MinCenterCoverage
         || item["h"] < A_ScreenHeight * MinCenterCoverage))
     return false
 return !POPUP_CLASSES.Has(item["classLower"])
}

WindowEngineIsGeometryCandidate(item) {
 if (item["scriptOwned"] || item["desktop"] || item["title"] = ""
     || item["bpm"] || item["minMax"] != 0)
     return false
 if !WindowEngineIsMovableAppWindow(item)
     return false
 return !IsExcludedForCenterMax(item["title"], item["class"], item["proc"])
}

WindowEngineGeometrySignature(item) {
 return item["x"] "," item["y"] "," item["w"] "," item["h"] "," item["style"] "," item["minMax"]
}

WindowEngineApplyGeometry(snapshot) {
 global EnableWindowManagement, MinWidthPercent
 global EnableGameScoreLogging, GameLogMode
 global WindowEngineGeometryState, WindowEngineGeometryRetryMs
 global WindowEngineGeometryMaxAttempts, WindowEngineGeometryActions
 if !EnableWindowManagement
     return false

 now := A_TickCount
 settleMs := 500
 seen := Map()
 changedAny := false
 for _, item in snapshot {
     if !WindowEngineIsGeometryCandidate(item)
         continue

     hwnd := item["hwnd"]
     seen[hwnd] := true
     signature := WindowEngineGeometrySignature(item)
     if !WindowEngineGeometryState.Has(hwnd)
         || WindowEngineGeometryState[hwnd]["pid"] != item["pid"] {
         WindowEngineGeometryState[hwnd] := Map(
             "pid", item["pid"],
             "signature", signature,
             "lastSeen", now,
             "nextAttempt", now + settleMs,
             "ignoreChangesUntil", 0,
             "actionWindowStart", now,
             "actions", 0,
             "suppressedUntil", 0)
     }
     state := WindowEngineGeometryState[hwnd]
     state["lastSeen"] := now

     if (state["signature"] != signature) {
         if (now >= state["ignoreChangesUntil"]) {
             ; The application changed its own window after creation or after
             ; a previous stable state. Let it settle, then give this new
             ; geometry episode a fresh bounded correction budget.
             state["actionWindowStart"] := now
             state["actions"] := 0
             state["suppressedUntil"] := 0
             state["nextAttempt"] := now + settleMs
         }
         state["signature"] := signature
     }

     if (now < state["nextAttempt"] || now < state["suppressedUntil"])
         continue
     if (now - state["actionWindowStart"] > 10000) {
         state["actionWindowStart"] := now
         state["actions"] := 0
     }
     if (state["actions"] >= WindowEngineGeometryMaxAttempts) {
         state["suppressedUntil"] := state["actionWindowStart"] + 10000
         continue
     }

     targetX := Round((A_ScreenWidth - item["w"]) / 2)
     targetY := Round((A_ScreenHeight - item["h"]) / 2)
     needsMove := Abs(item["x"] - targetX) > 2 || Abs(item["y"] - targetY) > 2
     canMaximize := (item["style"] & 0x00010000) || (item["style"] & 0x00040000)
     needsMaximize := item["w"] >= (A_ScreenWidth * MinWidthPercent) && canMaximize
     if (!needsMove && !needsMaximize) {
         state["nextAttempt"] := now + 5000
         continue
     }
     if !WindowEngineValidateItem(item)
         continue

     id := "ahk_id " hwnd
     actionSucceeded := false
     if needsMove {
         try {
             WinMove(targetX, targetY,,, id)
             actionSucceeded := true
         }
         ; Records exactly what was moved and why it qualified. Popups keep
         ; turning out to be real top-level windows that pass whatever filter is
         ; currently in place -- Explorer's, then Qt's -- and each round of that
         ; was diagnosed by guessing at the framework instead of reading the
         ; window. This makes the next one name itself.
         if (EnableGameScoreLogging && GameLogMode = "DIAGNOSTIC")
             LogLine("Geometry: centred " item["proc"] " [" item["class"] "] "
                 . item["w"] "x" item["h"] " style 0x" Format("{:08X}", item["style"])
                 . " exStyle 0x" Format("{:08X}", item["exStyle"])
                 . " owner " (item["owner"] ? "yes" : "no")
                 . " | " item["title"])
     }
     if needsMaximize {
         try {
             WinMaximize(id)
             actionSucceeded := true
         }
     }
     if actionSucceeded {
         state["actions"] += 1
         state["nextAttempt"] := now + WindowEngineGeometryRetryMs
         state["ignoreChangesUntil"] := now + Max(1000, WindowEngineGeometryRetryMs)
         WindowEngineGeometryActions += 1
         changedAny := true
     }
 }

 staleHwnds := []
 for hwnd, state in WindowEngineGeometryState {
     if !seen.Has(hwnd) && now - state["lastSeen"] > 10000
         staleHwnds.Push(hwnd)
 }
 for _, hwnd in staleHwnds
     WindowEngineGeometryState.Delete(hwnd)
 return changedAny
}

WindowEngineCleanupCpuSamples(snapshot) {
 global WindowEngineCpuSamples
 activePids := Map()
 for _, item in snapshot
     activePids[item["pid"]] := true
 stalePids := []
 for pid, sample in WindowEngineCpuSamples {
     if !activePids.Has(pid) && A_TickCount - sample["lastSeen"] > 30000
         stalePids.Push(pid)
 }
 for _, pid in stalePids
     WindowEngineCpuSamples.Delete(pid)
}

WindowEngineTick(*) {
 static inTick := false
 static lastErrorText := ""
 static lastErrorLogTick := 0
 global AllowExplorer, SystemReady
 global WindowEngineFocusIntervalMs, WindowEngineLastFocusTick
 global WindowEngineLastTickDurationMs, WindowEngineLastDecision
 if inTick
     return
 if (AllowExplorer || !SystemReady)
     return

 inTick := true
 started := A_TickCount
 try {
     snapshot := WindowEngineBuildSnapshot()
     ObserveForegroundForMouseParking()
     geometryChanged := WindowEngineApplyGeometry(snapshot)
     WindowEngineCleanupCpuSamples(snapshot)
     if (!geometryChanged
         && A_TickCount - WindowEngineLastFocusTick >= WindowEngineFocusIntervalMs) {
         WindowEngineLastFocusTick := A_TickCount
         WindowEngineApplyFocusPolicy(snapshot)
     } else if geometryChanged {
         WindowEngineLastDecision := "Geometry changed; focus deferred"
     }
 } catch as err {
     WindowEngineLastDecision := "Engine error: " err.Message
     if (err.Message != lastErrorText || A_TickCount - lastErrorLogTick >= 30000) {
         lastErrorText := err.Message
         lastErrorLogTick := A_TickCount
         try LogLine("Window engine tick failed: " err.Message)
     }
 } finally {
     WindowEngineLastTickDurationMs := A_TickCount - started
     inTick := false
 }
}

; ==============================================================================
; TASKBAR GUARD
; Explorer remains alive for Game Bar, touch keyboard, and shell services, so
; react to taskbar show events and keep a periodic safety check for missed or
; recreated taskbar windows.
; ==============================================================================
IsShellTaskbarWindow(hwnd) {
 if (!hwnd || !DllCall("User32\IsWindow", "Ptr", hwnd, "Int"))
     return false
 classBuffer := Buffer(128, 0)
 length := DllCall(
     "User32\GetClassNameW",
     "Ptr", hwnd,
     "Ptr", classBuffer.Ptr,
     "Int", classBuffer.Size // 2,
     "Int")
 if (length <= 0)
     return false
 className := StrGet(classBuffer, length, "UTF-16")
 return className = "Shell_TrayWnd"
     || className = "Shell_SecondaryTrayWnd"
}

HideShellTaskbars(*) {
 global TaskbarGuardActive, AllowExplorer, EnableTaskbarHiding
 if (!TaskbarGuardActive || AllowExplorer || !EnableTaskbarHiding)
     return
 for className in ["Shell_TrayWnd", "Shell_SecondaryTrayWnd"] {
     previousHwnd := 0
     Loop {
         hwnd := DllCall(
             "User32\FindWindowExW",
             "Ptr", 0,
             "Ptr", previousHwnd,
             "WStr", className,
             "Ptr", 0,
             "Ptr")
         if (!hwnd)
             break
         DllCall("User32\ShowWindow", "Ptr", hwnd, "Int", 0) ; SW_HIDE
         previousHwnd := hwnd
     }
 }
}

TaskbarGuardWinEvent(hook, event, hwnd, objectId, childId, eventThread, eventTime) {
 global TaskbarGuardActive, AllowExplorer, EnableTaskbarHiding
 static inCallback := false
 if inCallback
     return
 inCallback := true
 try {
     ; Callback DWORD/LONG arguments can contain undefined upper bits on x64.
     event := event & 0xFFFFFFFF
     objectId := objectId & 0xFFFFFFFF
     if (!TaskbarGuardActive || AllowExplorer || !EnableTaskbarHiding || !hwnd)
         return
     if (event != 0x8002 || objectId != 0) ; EVENT_OBJECT_SHOW / OBJID_WINDOW
         return
     if IsShellTaskbarWindow(hwnd)
         DllCall("User32\ShowWindow", "Ptr", hwnd, "Int", 0) ; SW_HIDE
 } finally {
     inCallback := false
 }
}

StartTaskbarGuard() {
 global TaskbarGuardActive, TaskbarGuardHook, TaskbarGuardCallback
 global TaskbarGuardSafetyIntervalMs, AllowExplorer, EnableTaskbarHiding
 if (AllowExplorer || !EnableTaskbarHiding)
     return false
 if TaskbarGuardActive {
     HideShellTaskbars()
     return true
 }

 TaskbarGuardActive := true
 if (!TaskbarGuardCallback) {
     try TaskbarGuardCallback := CallbackCreate(
         TaskbarGuardWinEvent, "", 7)
 }
 if (TaskbarGuardCallback && !TaskbarGuardHook) {
     ; Out-of-context hooks are delivered on SteamShell's message-loop thread.
     ; Skip our own process because it never owns an Explorer taskbar.
     try TaskbarGuardHook := DllCall(
         "User32\SetWinEventHook",
         "UInt", 0x8002, ; EVENT_OBJECT_SHOW
         "UInt", 0x8002,
         "Ptr", 0,
         "Ptr", TaskbarGuardCallback,
         "UInt", 0,
         "UInt", 0,
         "UInt", 0x2, ; WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
         "Ptr")
 }
 SetTimer(HideShellTaskbars, TaskbarGuardSafetyIntervalMs)
 HideShellTaskbars()
 if (!TaskbarGuardHook)
     try LogLine(
         "Taskbar Guard event hook was unavailable; periodic enforcement remains active.")
 return true
}

StopTaskbarGuard(releaseCallback := false) {
 global TaskbarGuardActive, TaskbarGuardHook, TaskbarGuardCallback
 TaskbarGuardActive := false
 SetTimer(HideShellTaskbars, 0)
 if (TaskbarGuardHook) {
     try DllCall("User32\UnhookWinEvent", "Ptr", TaskbarGuardHook, "Int")
     TaskbarGuardHook := 0
 }
 if (releaseCallback && TaskbarGuardCallback) {
     try CallbackFree(TaskbarGuardCallback)
     TaskbarGuardCallback := 0
 }
}

; ==============================================================================
; DESKTOP BLACKOUT (wallpaper and desktop icons)
; ==============================================================================
IsDesktopShellWindow(hwnd) {
 classBuffer := Buffer(128 * 2, 0)
 length := DllCall(
     "User32\GetClassNameW",
     "Ptr", hwnd,
     "Ptr", classBuffer.Ptr,
     "Int", classBuffer.Size // 2,
     "Int")
 if (length <= 0)
     return false
 className := StrLower(StrGet(classBuffer, length, "UTF-16"))
 return className = "progman" || className = "workerw"
}

EnsureDesktopBackdrop() {
 global DesktopBackdropGui, DesktopBackdropHwnd
 if (DesktopBackdropHwnd
     && DllCall("User32\IsWindow", "Ptr", DesktopBackdropHwnd, "Int"))
     return true
 try {
     ; -DPIScale because every position below is supplied in physical pixels
     ; from GetSystemMetrics. WS_EX_NOACTIVATE keeps it from ever taking focus.
     DesktopBackdropGui := Gui("-Caption +ToolWindow -DPIScale +E0x08000000")
     DesktopBackdropGui.BackColor := "000000"
     DesktopBackdropHwnd := DesktopBackdropGui.Hwnd
 } catch as err {
     DesktopBackdropHwnd := 0
     try LogLine("Desktop blackout: the backdrop window could not be created: " err.Message)
     return false
 }
 return true
}

GetVirtualScreenRect() {
 ; SM_XVIRTUALSCREEN / SM_YVIRTUALSCREEN / SM_CXVIRTUALSCREEN / SM_CYVIRTUALSCREEN
 return Map(
     "x", DllCall("User32\GetSystemMetrics", "Int", 76, "Int"),
     "y", DllCall("User32\GetSystemMetrics", "Int", 77, "Int"),
     "w", DllCall("User32\GetSystemMetrics", "Int", 78, "Int"),
     "h", DllCall("User32\GetSystemMetrics", "Int", 79, "Int"))
}

FitDesktopBackdrop(force := false) {
 global DesktopBackdropHwnd, DesktopBackdropRect
 if !DesktopBackdropHwnd
     return false
 rect := GetVirtualScreenRect()
 if (rect["w"] <= 0 || rect["h"] <= 0)
     return false
 signature := rect["x"] "," rect["y"] "," rect["w"] "," rect["h"]
 if (!force && signature = DesktopBackdropRect)
     return true
 ; HWND_BOTTOM with SWP_NOACTIVATE | SWP_SHOWWINDOW.
 ok := DllCall(
     "User32\SetWindowPos",
     "Ptr", DesktopBackdropHwnd,
     "Ptr", 1,
     "Int", rect["x"],
     "Int", rect["y"],
     "Int", rect["w"],
     "Int", rect["h"],
     "UInt", 0x0050,
     "Int")
 if (ok) {
     DesktopBackdropRect := signature
     return true
 }
 return false
}

SinkDesktopBackdrop() {
 global DesktopBackdropHwnd
 if !DesktopBackdropHwnd
     return
 ; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
 try DllCall(
     "User32\SetWindowPos",
     "Ptr", DesktopBackdropHwnd,
     "Ptr", 1,
     "Int", 0, "Int", 0, "Int", 0, "Int", 0,
     "UInt", 0x0013,
     "Int")
}

HideDesktopBackdrop() {
 global DesktopBackdropHwnd, DesktopBackdropRect
 DesktopBackdropRect := ""
 if !DesktopBackdropHwnd
     return
 try DllCall("User32\ShowWindow", "Ptr", DesktopBackdropHwnd, "Int", 0) ; SW_HIDE
}

HideDesktopShellWindows(*) {
 global DesktopBlackoutActive, AllowExplorer, EnableDesktopBlackout
 if (!DesktopBlackoutActive || AllowExplorer || !EnableDesktopBlackout)
     return
 for className in ["Progman", "WorkerW"] {
     previousHwnd := 0
     Loop {
         hwnd := DllCall(
             "User32\FindWindowExW",
             "Ptr", 0,
             "Ptr", previousHwnd,
             "WStr", className,
             "Ptr", 0,
             "Ptr")
         if (!hwnd)
             break
         DllCall("User32\ShowWindow", "Ptr", hwnd, "Int", 0) ; SW_HIDE
         previousHwnd := hwnd
     }
 }
}

ShowDesktopShellWindows() {
 for className in ["Progman", "WorkerW"] {
     try {
         for hwnd in WinGetList("ahk_class " className)
             WinShow("ahk_id " hwnd)
     }
 }
}

DesktopBlackoutWinEvent(hook, event, hwnd, objectId, childId, eventThread, eventTime) {
 global DesktopBlackoutActive, AllowExplorer, EnableDesktopBlackout
 static inCallback := false
 if inCallback
     return
 inCallback := true
 try {
     ; Callback DWORD/LONG arguments can contain undefined upper bits on x64.
     event := event & 0xFFFFFFFF
     objectId := objectId & 0xFFFFFFFF
     if (!DesktopBlackoutActive || AllowExplorer || !EnableDesktopBlackout || !hwnd)
         return
     if (event != 0x8002 || objectId != 0) ; EVENT_OBJECT_SHOW / OBJID_WINDOW
         return
     if IsDesktopShellWindow(hwnd)
         DllCall("User32\ShowWindow", "Ptr", hwnd, "Int", 0) ; SW_HIDE
 } finally {
     inCallback := false
 }
}

DesktopBlackoutTick() {
 global DesktopBlackoutActive, AllowExplorer, EnableDesktopBlackout
 global DesktopBackdropHwnd
 if (!DesktopBlackoutActive || AllowExplorer || !EnableDesktopBlackout)
     return
 if !EnsureDesktopBackdrop()
     return
 ; Re-fits only when the virtual screen actually changed, so resolution and
 ; monitor-layout changes are picked up without churn every second.
 FitDesktopBackdrop()

 ; Safety: the backdrop is WS_EX_NOACTIVATE and should never be able to reach
 ; the foreground. If it ever does, the user is looking at a black screen, so
 ; sink it immediately and say so in the log rather than leaving them stuck.
 if (DllCall("User32\GetForegroundWindow", "Ptr") = DesktopBackdropHwnd)
     try LogLine("Desktop blackout: the backdrop reached the foreground and was pushed back to the bottom.")
 SinkDesktopBackdrop()
 HideDesktopShellWindows()
}

StartDesktopBlackout() {
 global DesktopBlackoutActive, DesktopBlackoutHook, DesktopBlackoutCallback
 global TaskbarGuardSafetyIntervalMs, AllowExplorer, EnableDesktopBlackout
 if (AllowExplorer || !EnableDesktopBlackout)
     return false
 if !EnsureDesktopBackdrop()
     return false

 DesktopBlackoutActive := true
 ; Show the black pixels before hiding the desktop, otherwise there is a frame
 ; where neither is painting anything.
 FitDesktopBackdrop(true)
 SinkDesktopBackdrop()
 HideDesktopShellWindows()

 if (!DesktopBlackoutCallback) {
     try DesktopBlackoutCallback := CallbackCreate(
         DesktopBlackoutWinEvent, "", 7)
 }
 if (DesktopBlackoutCallback && !DesktopBlackoutHook) {
     try DesktopBlackoutHook := DllCall(
         "User32\SetWinEventHook",
         "UInt", 0x8002, ; EVENT_OBJECT_SHOW
         "UInt", 0x8002,
         "Ptr", 0,
         "Ptr", DesktopBlackoutCallback,
         "UInt", 0,
         "UInt", 0,
         "UInt", 0x2, ; WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
         "Ptr")
 }
 SetTimer(DesktopBlackoutTick, TaskbarGuardSafetyIntervalMs)
 if (!DesktopBlackoutHook)
     try LogLine(
         "Desktop blackout event hook was unavailable; periodic enforcement remains active.")
 return true
}

StopDesktopBlackout(releaseCallback := false) {
 global DesktopBlackoutActive, DesktopBlackoutHook, DesktopBlackoutCallback
 global DesktopBackdropGui, DesktopBackdropHwnd
 wasActive := DesktopBlackoutActive
 DesktopBlackoutActive := false
 SetTimer(DesktopBlackoutTick, 0)
 if (DesktopBlackoutHook) {
     try DllCall("User32\UnhookWinEvent", "Ptr", DesktopBlackoutHook, "Int")
     DesktopBlackoutHook := 0
 }

 ; Give the desktop back before removing the black pixels, so the transition
 ; never exposes an unpainted screen.
 if (wasActive)
     ShowDesktopShellWindows()
 HideDesktopBackdrop()

 if (releaseCallback) {
     if (DesktopBlackoutCallback) {
         try CallbackFree(DesktopBlackoutCallback)
         DesktopBlackoutCallback := 0
     }
     if IsSet(DesktopBackdropGui) {
         try DesktopBackdropGui.Destroy()
         DesktopBackdropGui := unset
     }
     DesktopBackdropHwnd := 0
 }
}

; ==============================================================================
; SHELL MONITOR (Steam lifecycle and desktop restoration)
; ==============================================================================
MonitorShell() {
 global AllowExplorer, SteamLaunched, DesktopMode
 global SteamLaunchAttemptTick, SteamObservedRunning, SteamMissingSinceTick
 global SteamStartupGraceMs, SteamExitConfirmMs, SteamLaunchFailedReason
 global SteamStartupWarningLogged

 ; The desktop has already been restored; there is no Steam lifecycle left to
 ; observe. ApplyRuntimeTimers stops this timer in desktop mode, so this is a
 ; guard against a stray reschedule re-entering the restore path.
 if (DesktopMode)
     return

 ; Deliberately unpooled: Steam-exit detection drives desktop restoration and
 ; must not observe a cached result.
 steamRunning := ProcessExist("steam.exe") != 0

 ; Startup and steady state are judged by deliberately different signals.
 ;
 ; Before Big Picture has been seen once, a running steam.exe proves nothing.
 ; On a Wi-Fi handheld the process appears almost immediately and then sits on
 ; a "Connecting", sign-in, or client-update window for as long as the network
 ; takes -- a wired HTPC wins that race and never reaches this state. Treating
 ; the bare process as success set SteamObservedRunning on the first tick,
 ; which put the whole startup grace check below permanently out of reach:
 ; every branch that could raise the recovery screen is nested under
 ; !SteamObservedRunning, so the screen could not appear at all, and with the
 ; startup curtain up the result was an indefinite black screen.
 ;
 ; After Big Picture HAS been seen, the process is the correct signal again and
 ; the surface must NOT be re-tested. A game covering, replacing, or minimizing
 ; Big Picture is ordinary behavior and must never re-open the startup path.
 ; SteamObservedRunning is therefore latched: it is set once and never cleared.
 if (!SteamObservedRunning) {
     if (steamRunning && SteamBpmSurfacePresent()) {
         SteamObservedRunning := true
         SteamMissingSinceTick := 0
         SteamStartupWarningLogged := false
         HideStartupRecovery()
         try LogLine("Shell monitor: Steam Big Picture observed; automatic exit monitoring is now armed.")
         SetSessionState("ACTIVE", "Steam Big Picture observed")
         return
     }
     if (!SteamLaunched)
         return
     launchElapsed := A_TickCount - SteamLaunchAttemptTick
     if (SteamLaunchAttemptTick > 0
         && launchElapsed >= SteamStartupGraceMs
         && !SteamStartupWarningLogged) {
         SteamStartupWarningLogged := true
         try LogLine(
             "Shell monitor: Steam Big Picture was not observed within the startup "
             . "grace period (steam.exe " (steamRunning ? "is" : "is not")
             . " running); keeping SteamShell active and automatic desktop "
             . "restoration disarmed.")
         reason := SteamLaunchFailedReason != ""
             ? SteamLaunchFailedReason
             : (steamRunning
                 ? "Steam is running, but Big Picture has not appeared. It may still "
                     . "be signing in or updating, which takes longer over Wi-Fi."
                 : "Steam was not detected within the configured startup period.")
         ShowStartupRecovery(reason)
     }
     return
 }

 if (steamRunning) {
     HideStartupRecovery()
     if (SteamMissingSinceTick)
         SetSessionState("ACTIVE", "Steam returned before exit confirmation")
     SteamMissingSinceTick := 0
     SteamStartupWarningLogged := false
 } else if (SteamLaunched) {
     if (SteamMissingSinceTick = 0) {
         SteamMissingSinceTick := A_TickCount
         SetSessionState("STEAM_EXIT_PENDING", "waiting for sustained Steam exit")
         try LogLine("Shell monitor: Steam process disappeared; waiting for a sustained exit.")
     } else if (A_TickCount - SteamMissingSinceTick >= SteamExitConfirmMs) {
         try LogLine("Shell monitor: Steam remained closed; restoring desktop.")
         ExitToDesktop()
         return
     }
 }

}

LaunchSteamBpm() {
 global SteamPath, SteamLaunched, SteamLaunchAttemptTick
 global SteamObservedRunning, SteamMissingSinceTick, SteamLaunchFailedReason
 global SteamStartupWarningLogged

 ; Every attempt earns a fresh warning, so Retry from the recovery screen can
 ; raise that screen again if the retry also fails to produce Big Picture.
 SteamStartupWarningLogged := false

 if ProcessExist("steam.exe") {
     SteamLaunched := true
     SteamMissingSinceTick := 0
     SteamLaunchFailedReason := ""
     ; A running steam.exe only counts as success once Big Picture is actually
     ; on screen. Latching observation on the bare process here would make the
     ; recovery screen's Retry button a trap: Steam stalled on sign-in or a
     ; client update satisfies ProcessExist, so Retry would mark the session
     ; ACTIVE, dismiss the recovery screen, and strand the user on the black
     ; screen with no way to raise it again.
     if SteamBpmSurfacePresent() {
         SteamObservedRunning := true
         SetSessionState("ACTIVE", "Steam already running")
         return true
     }
     SteamObservedRunning := false
     SteamLaunchAttemptTick := A_TickCount
     SetSessionState("STEAM_LAUNCHING", "Steam running; waiting for Big Picture")
     return true
 }

 SteamLaunched := true
 SteamLaunchAttemptTick := A_TickCount
 SteamObservedRunning := false
 SteamMissingSinceTick := 0
 SteamLaunchFailedReason := ""
 SetSessionState("STEAM_LAUNCHING")

 path := NormalizeMediaPath(SteamPath)
 if (path = "" || !FileExist(path)) {
     SteamLaunchFailedReason := "Steam.exe was not found. Open Settings and select the correct Steam executable."
     LogLine("Steam startup failed: " SteamLaunchFailedReason)
     SetSessionState("RECOVERY", "Steam executable missing")
     return false
 }

 cmd := '"' path '" -bigpicture -fulldesktopres -nobootstrapupdate'
 try {
     Run(cmd)
     LogLine("Steam startup: launch command accepted.")
     return true
 } catch as err {
     SteamLaunchFailedReason := "Windows could not start Steam: " err.Message
     LogLine("Steam startup failed: " SteamLaunchFailedReason)
     SetSessionState("RECOVERY", "Steam launch failed")
     return false
 }
}

ShowPendingStartupRecovery(*) {
 ; Presence of the process is not enough to dismiss this: a steam.exe stalled
 ; on sign-in or a client update satisfies ProcessExist while leaving the user
 ; with no navigable surface, which is exactly when recovery has to be offered.
 if SteamBpmSurfacePresent() {
     HideStartupRecovery()
     return
 }
 ShowStartupRecovery(SteamLaunchFailedReasonText())
}

ShowStartupRecovery(reason) {
 global StartupRecoveryGui, SteamShellVersion
 ; Matches ShowPendingStartupRecovery: only a real Big Picture surface proves
 ; there is something for the user to return to.
 if SteamBpmSurfacePresent() {
     HideStartupRecovery()
     return
 }
 SetSessionState("RECOVERY", reason)

 try {
     if IsSet(StartupRecoveryGui)
         StartupRecoveryGui.Destroy()
 }

 StartupRecoveryGui := Gui("+AlwaysOnTop +ToolWindow -MaximizeBox", "SteamShell Recovery")
 StartupRecoveryGui.Opt("+OwnDialogs")
 StartupRecoveryGui.SetFont("s11", "Segoe UI")
 StartupRecoveryGui.MarginX := 22
 StartupRecoveryGui.MarginY := 20
 title := StartupRecoveryGui.AddText("xm w560 Center", "STEAM DID NOT START")
 title.SetFont("s17 Bold", "Segoe UI")
 StartupRecoveryGui.AddText("xm y+12 w560 h56 +Wrap Center", reason)
 StartupRecoveryGui.AddText("xm y+6 w560 Center", "Choose an action below. The normal desktop has not been restored automatically.")
 retryButton := StartupRecoveryGui.AddButton("xm y+18 w170 h38 Default", "Retry Steam")
 settingsButton := StartupRecoveryGui.AddButton("x+12 yp w170 h38", "Open Settings")
 desktopButton := StartupRecoveryGui.AddButton("x+12 yp w196 h38", "Restore Desktop")
 retryButton.OnEvent("Click", RetrySteamFromRecovery)
 settingsButton.OnEvent("Click", OpenSettingsFromRecovery)
 desktopButton.OnEvent("Click", RestoreDesktopFromRecovery)
 StartupRecoveryGui.OnEvent("Close", (*) => 0)
 StartupRecoveryGui.OnEvent("Escape", (*) => 0)
 StartupRecoveryGui.Show("AutoSize Center")
 try retryButton.Focus()
 SystemCursor("Show")
 LogLine("Recovery screen shown: " reason)
}

; The desktop restore failed. Explorer may be dead, the taskbar is gone, and on a
; handheld there may be no keyboard -- so this must be operable with a controller
; alone. It replaces a native MsgBox, which the poll loop has no handling for and
; which therefore needed pointer emulation to answer.
;
; Blocks like the MsgBox it replaces, so ExitToDesktop's control flow is
; unchanged. Sleep still services timers, so controller polling keeps running
; while this waits.
ShowDesktopRestoreRecovery(reason) {
 global DesktopRecoveryGui, DesktopRecoveryChoice
 DesktopRecoveryChoice := ""
 try {
     if IsSet(DesktopRecoveryGui)
         DesktopRecoveryGui.Destroy()
 }
 DesktopRecoveryGui := Gui("+AlwaysOnTop +ToolWindow -MaximizeBox", "SteamShell Desktop Recovery")
 DesktopRecoveryGui.Opt("+OwnDialogs")
 DesktopRecoveryGui.SetFont("s11", "Segoe UI")
 DesktopRecoveryGui.MarginX := 22
 DesktopRecoveryGui.MarginY := 20
 title := DesktopRecoveryGui.AddText("xm w560 Center", "DESKTOP RESTORE FAILED")
 title.SetFont("s17 Bold", "Segoe UI")
 DesktopRecoveryGui.AddText("xm y+12 w560 h56 +Wrap Center", reason)
 DesktopRecoveryGui.AddText("xm y+6 w560 Center",
     "SteamShell is still running. Windows may have no visible shell until this succeeds.")
 retryButton := DesktopRecoveryGui.AddButton("xm y+18 w170 h38 Default", "Retry Restore")
 settingsButton := DesktopRecoveryGui.AddButton("x+12 yp w170 h38", "Open Settings")
 stayButton := DesktopRecoveryGui.AddButton("x+12 yp w196 h38", "Keep SteamShell Running")
 retryButton.OnEvent("Click", (*) => DesktopRecoveryChoice := "retry")
 settingsButton.OnEvent("Click", (*) => ShowSettingsEditor())
 stayButton.OnEvent("Click", (*) => DesktopRecoveryChoice := "stay")
 ; No Close/Escape dismissal: leaving with no choice made would drop the user on
 ; a shell-less desktop with nothing on screen explaining it.
 DesktopRecoveryGui.OnEvent("Close", (*) => 0)
 DesktopRecoveryGui.OnEvent("Escape", (*) => 0)
 DesktopRecoveryGui.Show("AutoSize Center")
 try retryButton.Focus()
 SystemCursor("Show")
 LogLine("Desktop recovery screen shown: " reason)

 while (DesktopRecoveryChoice = "")
     Sleep(50)
 choice := DesktopRecoveryChoice
 try DesktopRecoveryGui.Destroy()
 DesktopRecoveryGui := unset
 LogLine("Desktop recovery choice: " choice)
 return choice
}

DesktopRecoveryControllerActive() {
 global DesktopRecoveryGui
 if !IsSet(DesktopRecoveryGui)
     return false
 try {
     return DllCall("IsWindowVisible", "Ptr", DesktopRecoveryGui.Hwnd, "Int")
         && WinActive("ahk_id " DesktopRecoveryGui.Hwnd)
 } catch {
     return false
 }
}

HideStartupRecovery() {
 global StartupRecoveryGui
 try {
     if IsSet(StartupRecoveryGui)
         StartupRecoveryGui.Destroy()
 }
 StartupRecoveryGui := unset
}

StartupRecoveryControllerActive() {
 global StartupRecoveryGui
 if !IsSet(StartupRecoveryGui)
     return false
 try {
     return DllCall("IsWindowVisible", "Ptr", StartupRecoveryGui.Hwnd, "Int")
         && WinActive("ahk_id " StartupRecoveryGui.Hwnd)
 } catch {
     return false
 }
}

; Shared by both recovery dialogs. Tab/Shift-Tab across the button row, A to
; activate -- deliberately the simplest possible model, because these screens
; appear exactly when nothing else is working.
RecoveryDialogHandleController(pressed) {
 if (pressed & 0x0001) || (pressed & 0x0004) {
     try SendInput("+{Tab}")
     return
 }
 if (pressed & 0x0002) || (pressed & 0x0008) {
     try SendInput("{Tab}")
     return
 }
 if (pressed & 0x1000)
     try SendInput("{Enter}")
}

RetrySteamFromRecovery(*) {
 global SteamLaunchFailedReason
 HideStartupRecovery()
 if !LaunchSteamBpm() {
     SetTimer(ShowPendingStartupRecovery, -250)
     return
 }
 SteamLaunchFailedReason := ""
}

OpenSettingsFromRecovery(*) {
 ShowSettingsEditor()
}

RestoreDesktopFromRecovery(*) {
 ; A session restore, not a permanent one. Steam failing to start once should
 ; not deregister SteamShell as the Windows shell. The user lands on a working
 ; desktop with SteamShell still in the notification area, from which Settings
 ; offers the permanent restore if that is what they actually want.
 ExitToDesktop(false)
}

; ==============================================================================
; CPU + STEAM FOREGROUND
; ==============================================================================
CalculateProcessCpuPercent(cpuDelta100ns, elapsedMs) {
 if (elapsedMs <= 0 || cpuDelta100ns < 0)
     return 0.0
 return ClampFloat(
     (cpuDelta100ns / (elapsedMs * 10000.0)) * 100.0, 0.0, 10000.0)
}

GetProcessCpuSample(pid) {
 global WindowEngineCpuSamples, WindowEngineCpuSampleIntervalMs
 now := A_TickCount
 unknown := Map("usage", 0.0, "known", false, "lastSeen", now)
 if (!pid)
     return unknown

 if WindowEngineCpuSamples.Has(pid) {
     cached := WindowEngineCpuSamples[pid]
     cached["lastSeen"] := now
     if (now - cached["sampleTick"] < WindowEngineCpuSampleIntervalMs)
         return cached
 }

 ; PROCESS_QUERY_LIMITED_INFORMATION is sufficient for GetProcessTimes and
 ; avoids the WMI query that previously ran for every candidate process.
 hProcess := DllCall(
     "Kernel32\OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr")
 if (!hProcess)
     return unknown

 creationTime := Buffer(8, 0)
 exitTime := Buffer(8, 0)
 kernelTime := Buffer(8, 0)
 userTime := Buffer(8, 0)
 ok := false
 try ok := DllCall(
     "Kernel32\GetProcessTimes",
     "Ptr", hProcess,
     "Ptr", creationTime,
     "Ptr", exitTime,
     "Ptr", kernelTime,
     "Ptr", userTime,
     "Int")
 DllCall("Kernel32\CloseHandle", "Ptr", hProcess)
 if !ok
     return unknown

 creation := NumGet(creationTime, 0, "Int64")
 totalCpu100ns := NumGet(kernelTime, 0, "Int64") + NumGet(userTime, 0, "Int64")
 if WindowEngineCpuSamples.Has(pid) {
     previous := WindowEngineCpuSamples[pid]
     if (previous["creation"] = creation) {
         elapsedMs := now - previous["sampleTick"]
         cpuDelta := totalCpu100ns - previous["totalCpu100ns"]
         usage := elapsedMs > 0 && cpuDelta >= 0
             ? CalculateProcessCpuPercent(cpuDelta, elapsedMs)
             : previous["usage"]
         sample := Map(
             "usage", usage,
             "known", elapsedMs > 0,
             "creation", creation,
             "totalCpu100ns", totalCpu100ns,
             "sampleTick", now,
             "lastSeen", now)
         WindowEngineCpuSamples[pid] := sample
         return sample
     }
 }

 sample := Map(
     "usage", 0.0,
     "known", false,
     "creation", creation,
     "totalCpu100ns", totalCpu100ns,
     "sampleTick", now,
     "lastSeen", now)
 WindowEngineCpuSamples[pid] := sample
 return sample
}

CaptureLastRealForeground() {
 global ScriptPid, LastRealFgHwnd
 try {
 hwnd := WinGetID("A")
 id := "ahk_id " hwnd
 if (WinGetPID(id) != ScriptPid)
 LastRealFgHwnd := hwnd
 } catch {
 }
}

IsSteamForeground() {
 global ScriptPid, LastRealFgHwnd
 try {
 hwnd := WinGetID("A")
 id := "ahk_id " hwnd

 ; If one of our GUIs is foreground, report based on the last non-script foreground window.
 if (WinGetPID(id) = ScriptPid) {
 if !LastRealFgHwnd
 return false
 try {
 proc := StrLower(WinGetProcessName("ahk_id " LastRealFgHwnd))
 return (proc = "steam.exe" || proc = "steamwebhelper.exe")
 } catch {
 return false
 }
 }

 ; Foreground is not ours—update cache and report normally.
 LastRealFgHwnd := hwnd
 proc := StrLower(WinGetProcessName(id))
 return (proc = "steam.exe" || proc = "steamwebhelper.exe")
 } catch {
 return false
 }
}


; ==============================================================================
; AUDIO ASSIST (CoreAudio per-process peak)
; ==============================================================================
GuidBuf(guidStr) {
 buf := Buffer(16, 0)
 DllCall("ole32\CLSIDFromString", "WStr", guidStr, "Ptr", buf, "Int")
 return buf
}

GetActiveAudioPidPeaksCached() {
 static lastTick := 0
 static lastMap := Map()
 if (A_TickCount - lastTick < 750)
 return lastMap
 lastTick := A_TickCount
 lastMap := GetActiveAudioPidPeaks()
 return lastMap
}

GetActiveAudioPidPeaks() {
 pids := Map()
 static CLSID_MMDeviceEnumerator := "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
 static IID_IMMDeviceEnumerator := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
 static IID_IAudioSessionControl2:= "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}"
 static IID_IAudioMeterInformation:= "{C02216F6-8C67-4B5B-9D00-D008E73E0064}"

 eRender := 0
 eMultimedia := 1
 CLSCTX_ALL := 23

 pDevice := 0, pMgr := 0, pEnum := 0
 try {
 enum := ComObject(CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator)

 ComCall(4, enum, "UInt", eRender, "UInt", eMultimedia, "Ptr*", pDevice)
 if (!pDevice)
 return pids

 dev := ComValue(13, pDevice)
 iidMgr := GuidBuf("{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}") ; IAudioSessionManager2

 ComCall(3, dev, "Ptr", iidMgr, "UInt", CLSCTX_ALL, "Ptr", 0, "Ptr*", pMgr)
     if (!pMgr)
         return pids

 mgr := ComValue(13, pMgr)

 ComCall(5, mgr, "Ptr*", pEnum) ; GetSessionEnumerator
     if (!pEnum)
         return pids

 sesEnum := ComValue(13, pEnum)

 count := 0
 ComCall(3, sesEnum, "Int*", count) ; GetCount

 iidCtl2 := GuidBuf(IID_IAudioSessionControl2)
 iidMeter := GuidBuf(IID_IAudioMeterInformation)

 Loop count {
 idx := A_Index - 1
 pCtrl := 0
 ComCall(4, sesEnum, "Int", idx, "Ptr*", pCtrl) ; GetSession
 if (!pCtrl)
 continue

 ctrl := ComValue(13, pCtrl)

 pid := 0
 pCtrl2 := 0
 ComCall(0, ctrl, "Ptr", iidCtl2, "Ptr*", pCtrl2)
     if (pCtrl2) {
     ctrl2 := ComValue(13, pCtrl2)
     ComCall(14, ctrl2, "UInt*", pid) ; GetProcessId
     }

 peak := 0.0
 pMeter := 0
 ComCall(0, ctrl, "Ptr", iidMeter, "Ptr*", pMeter)
     if (pMeter) {
     meter := ComValue(13, pMeter)
     ComCall(3, meter, "Float*", peak) ; GetPeakValue
     }

 if (pid) {
 if (!pids.Has(pid))
 pids[pid] := peak
 else if (peak > pids[pid])
 pids[pid] := peak
 }

     }

     return pids
 } catch {
     ; Each non-null interface pointer is wrapped in ComValue immediately.
     ; Those wrappers own and release the pointers automatically.
     return pids
 }
}

; ==============================================================================
; LOGGING (fixed columns + truncate)
; ==============================================================================
RotateLogIfNeeded() {
 global LogPath, GameLogRotateMaxKB, GameLogRotateBackups
 if (GameLogRotateBackups <= 0)
 return
 if !FileExist(LogPath)
 return

 sz := 0
 try {
 sz := FileGetSize(LogPath)
 } catch {
 return
 }

 if (sz <= (GameLogRotateMaxKB * 1024))
 return

 Loop GameLogRotateBackups {
 idx := GameLogRotateBackups - A_Index + 1
 src := LogPath "." idx
 dst := LogPath "." (idx + 1)
 if (idx = GameLogRotateBackups) {
 if FileExist(src)
 try FileDelete(src)
 } else {
 if FileExist(src)
 try FileMove(src, dst, 1)
 }
 }
 try FileMove(LogPath, LogPath ".1", 1)
}

; Writes a line exactly as given, with no prefix.
;
; Only for the game-score diagnostic table. That table is columnar and formats
; its own leading timestamp, so a second prefix would misalign every row of it.
LogRawLine(line) {
 global LogPath
 RotateLogIfNeeded()
 try FileAppend(line "`r`n", LogPath, "UTF-8")
}

; Every operational line gets a timestamp and a level, matching XFE.
;
; Without the timestamp the log records what happened but not when, so two lines
; could be one second or one hour apart and nothing said which -- and elapsed
; time is exactly what a startup stall, a focus handoff, or a sustained-exit
; window has to be reasoned about in. Until now the only timestamped lines were
; the game-score rows, which stamped themselves.
LogLine(message, level := "Info") {
 LogRawLine(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " [" level "] " message)
}

ShouldLogRateLimited() {
 global _LastGameLogTick, GameLogIntervalMs
 if (A_TickCount - _LastGameLogTick >= GameLogIntervalMs) {
 _LastGameLogTick := A_TickCount
 return true
 }
 return false
}

TruncPad(s, width, leftAlign := true) {
 s := (s = "" ? "" : s)
 if (StrLen(s) > width) {
 if (width >= 2)
 s := SubStr(s, 1, width - 1) "…"
 else
 s := SubStr(s, 1, width)
 }
 pad := width - StrLen(s)
 if (pad <= 0)
 return s
 return leftAlign ? (s . StrRepeat(" ", pad)) : (StrRepeat(" ", pad) . s)
}

FmtPid(pid) {
 return pid ? TruncPad(pid "", 6, false) : "------"
}

FmtCpu(cpu, known := true) {
 return known ? TruncPad(Format("{:0.1f}", cpu + 0.0), 6, false) : TruncPad("---.-", 6, false)
}

FmtScore(score, known := true) {
 return known ? Format("{:03}", ClampInt(score, 0, 999)) : "---"
}

FmtHwnd(hwnd) {
 return hwnd ? TruncPad("0x" Format("{:08X}", hwnd), 10, true) : "----------"
}

FmtRect(x, y, w, h) {
 return (x "," y " " w "x" h)
}

LogRow(ts, evt, scoreStr, exe, pidStr, cpuStr, audChar, fsChar, rectStr, hwndStr, reason, title := "") {
 global GameLogIncludeTitles
 line :=
 TruncPad(ts, 19, true) " "
 . TruncPad(evt, 7, true) " "
 . TruncPad(scoreStr, 3, false) " "
 . TruncPad(exe, 24, true) " "
 . TruncPad(pidStr, 6, false) " "
 . TruncPad(cpuStr, 6, false) " "
 . TruncPad(audChar, 1, true) " "
 . TruncPad(fsChar, 1, true) " "
 . TruncPad(rectStr, 19, true) " "
 . TruncPad(hwndStr, 10, true) " "
 . TruncPad(reason, 22, true)

 if (GameLogIncludeTitles) {
 if (title = "")
 title := "-"
 line .= " " . TruncPad(title, 60, true)
 }
 return line
}

; ==============================================================================
; GAME ASSIST
; ==============================================================================
SortCandidatesByScoreAreaDesc(cands) {
 n := cands.Length
 if (n < 2)
 return
 Loop n - 1 {
 i := A_Index
 best := i
 bestScore := cands[i]["score"]
 bestArea := cands[i]["w"] * cands[i]["h"]
 j := i + 1
 while (j <= n) {
 s := cands[j]["score"]
 a := cands[j]["w"] * cands[j]["h"]
 if (s > bestScore) || (s = bestScore && a > bestArea) {
 best := j
 bestScore := s
 bestArea := a
 }
 j++
 }
 if (best != i) {
 tmp := cands[i]
 cands[i] := cands[best]
 cands[best] := tmp
 }
 }
}

ActivateWindowRobust(hwnd) {
 id := "ahk_id " hwnd
 try WinActivate(id)
 Sleep(60)
 try {
 if WinActive(id)
 return true
 } catch {
 }

 try WinShow(id)
 try {
 if (WinGetMinMax(id) = -1)
 WinRestore(id)
 } catch {
 }

 try WinActivate(id)
 Sleep(60)
 try {
 return WinActive(id)
 } catch {
 return false
 }
}

; Takes the foreground for one of SteamShell's own windows. A topmost window can
; be visible over Steam while Steam still owns focus and continues processing
; controller navigation. Temporarily joining the foreground thread's input
; queue permits the user-opened Quick Menu to become the real foreground window.
ForceForegroundWindow(hwnd) {
 if !hwnd
     return false
 try {
     if (DllCall("User32\GetForegroundWindow", "Ptr") = hwnd)
         return true
     currentForeground := DllCall("User32\GetForegroundWindow", "Ptr")
     ourThread := DllCall("Kernel32\GetCurrentThreadId", "UInt")
     foregroundThread := currentForeground
         ? DllCall(
             "User32\GetWindowThreadProcessId",
             "Ptr", currentForeground, "Ptr", 0, "UInt")
         : 0
     attached := false
     if (foregroundThread && foregroundThread != ourThread)
         attached := DllCall(
             "User32\AttachThreadInput",
             "UInt", ourThread, "UInt", foregroundThread, "Int", 1) != 0
     try {
         DllCall("User32\BringWindowToTop", "Ptr", hwnd)
         DllCall("User32\SetForegroundWindow", "Ptr", hwnd)
     } finally {
         if attached
             DllCall(
                 "User32\AttachThreadInput",
                 "UInt", ourThread, "UInt", foregroundThread, "Int", 0)
     }
     return DllCall("User32\GetForegroundWindow", "Ptr") = hwnd
 }
 return false
}

ForceGameAssistOnce() {
 snapshot := WindowEngineBuildSnapshot()
 return TryBringFullscreenCandidateToFront(true, true, snapshot)
}

WindowEngineEvaluateGame(snapshot, forceRun, &allowActivate, &skipReason) {
 global EnableGameForegroundAssist, GameForegroundCooldownMs, LastGameBringToFrontTick
 global FullscreenTolerance, FullscreenPosTolerancePx
 global GameCPUThresholdPercent, GameAllowZeroCpuAsCandidate
 global GameRequireSteamForeground, GameAssistLogEvenWhenSkipped
 global ScoreFullscreen, ScoreBorderlessLarge, ScoreTitleBonus, ScoreCpuAboveThreshold, ScoreCpuNonZeroBonus, GameMinScoreToActivate
 global EnableAudioAssist, ScoreAudioActive
 global EnableGameScoreLogging, GameLogMode, GameLogTopN, GameLogRejectNearCandidates, GameLogRejectMinAreaPercent
 global AudioPeakThreshold
 global LastActionText, LastBestCandidateScore, LastBestCandidateProc, LastBestCandidateTitle, LastBestCandidateText

 allowActivate := true
 skipReason := ""
 if (!EnableGameForegroundAssist)
     return 0
 if (!forceRun && A_TickCount - LastGameBringToFrontTick < GameForegroundCooldownMs) {
     allowActivate := false
     skipReason := "COOLDOWN"
 }

 if (!forceRun && GameRequireSteamForeground) {
     if !IsSteamForeground() {
         if (!GameAssistLogEvenWhenSkipped)
             return 0
         allowActivate := false
         skipReason := "STEAM_NOT_FOREGROUND"
     }
 }

 if forceRun {
     allowActivate := true
     skipReason := ""
 }

 screenArea := A_ScreenWidth * A_ScreenHeight
 rejectAreaMin := screenArea * GameLogRejectMinAreaPercent
 candidates := []
 rejects := []
 audioMap := 0

 for _, item in snapshot {
     minimizedLegacyGame := WindowEngineIsMinimizedLegacyGameSurface(item)
     legacySurface := WindowEngineIsLegacyApplicationSurface(item)
         || minimizedLegacyGame
     if (item["scriptOwned"] || item["desktop"] || item["steam"]
         || (item["minMax"] = -1 && !minimizedLegacyGame)
         || (item["title"] = "" && !legacySurface))
         continue

     title := item["title"]
     proc := item["proc"]
     winClass := item["class"]
     tLower := StrLower(title)
     if (proc = "osk.exe" || StrLower(winClass) = "oskmainclass"
         || InStr(tLower, "on-screen keyboard"))
         continue

     x := item["x"]
     y := item["y"]
     w := item["w"]
     h := item["h"]
     area := item["area"]
     nearFS := minimizedLegacyGame
         || (w >= (A_ScreenWidth * FullscreenTolerance)
             && h >= (A_ScreenHeight * FullscreenTolerance)
             && Abs(x) <= FullscreenPosTolerancePx
             && Abs(y) <= FullscreenPosTolerancePx)
     bigBorderless := !minimizedLegacyGame
         && w >= (A_ScreenWidth * 0.90)
         && h >= (A_ScreenHeight * 0.90)
     if (!nearFS && !bigBorderless) {
         if (EnableGameScoreLogging && GameLogMode = "DIAGNOSTIC"
             && GameLogRejectNearCandidates && area >= rejectAreaMin) {
             rejects.Push(LogRow(
                 NowStamp(), "REJ", "---", proc, FmtPid(item["pid"]),
                 FmtCpu(0, false), "-", "N",
                 FmtRect(x, y, w, h), FmtHwnd(item["hwnd"]),
                 "TOO_SMALL", title))
         }
         continue
     }

     score := nearFS ? ScoreFullscreen : ScoreBorderlessLarge
     if (StrLen(title) >= 3)
         score += ScoreTitleBonus

     cpuSample := GetProcessCpuSample(item["pid"])
     cpu := cpuSample["usage"]
     cpuKnown := cpuSample["known"]
     if cpuKnown {
         if (cpu >= GameCPUThresholdPercent)
             score += ScoreCpuAboveThreshold
         else if (cpu > 0)
             score += ScoreCpuNonZeroBonus
         else if (!GameAllowZeroCpuAsCandidate) {
             if (EnableGameScoreLogging && GameLogMode = "DIAGNOSTIC"
                 && GameLogRejectNearCandidates && area >= rejectAreaMin) {
                 rejects.Push(LogRow(
                     NowStamp(), "REJ", FmtScore(score, true), proc,
                     FmtPid(item["pid"]), FmtCpu(cpu, true), "-",
                     nearFS ? "Y" : "N", FmtRect(x, y, w, h),
                     FmtHwnd(item["hwnd"]), "CPU_ZERO_STRICT", title))
             }
             continue
         }
     }

     audioActive := false
     if (EnableAudioAssist && item["pid"]) {
         if (!IsObject(audioMap))
             audioMap := GetActiveAudioPidPeaksCached()
         if (audioMap.Has(item["pid"]) && audioMap[item["pid"]] > AudioPeakThreshold) {
             score += ScoreAudioActive
             audioActive := true
         }
     }

     candidate := Map()
     for key, value in item
         candidate[key] := value
     candidate["nearFS"] := nearFS
     candidate["cpu"] := cpu
     candidate["cpuKnown"] := cpuKnown
     candidate["audio"] := audioActive
     candidate["score"] := score
     candidates.Push(candidate)
 }

 if (candidates.Length > 1)
     SortCandidatesByScoreAreaDesc(candidates)

 if (candidates.Length > 0) {
     best := candidates[1]
     LastBestCandidateScore := best["score"]
     LastBestCandidateProc := best["proc"]
     LastBestCandidateTitle := best["title"]
     LastBestCandidateText := best["proc"] " score=" best["score"]
 } else {
     LastBestCandidateScore := -1
     LastBestCandidateProc := ""
     LastBestCandidateTitle := ""
     LastBestCandidateText := "-"
 }

 if (EnableGameScoreLogging && (GameLogMode = "TOPN" || GameLogMode = "DIAGNOSTIC") && ShouldLogRateLimited()) {
     if (candidates.Length = 0) {
         LogRawLine(LogRow(
             NowStamp(), "TOPN", "---", "-", "------", FmtCpu(0, false),
             "-", "-", "-", "----------", "NO_CANDIDATES", "-"))
     } else {
         header := "min=" GameMinScoreToActivate
         if (!allowActivate && skipReason != "")
             header := "SKIP_" skipReason " " header
         LogRawLine(LogRow(
             NowStamp(), "TOPN", "---", "-", "------", FmtCpu(0, false),
             "-", "-", "-", "----------", header, "-"))
         maxN := Min(candidates.Length, GameLogTopN)
         Loop maxN {
             candidate := candidates[A_Index]
             LogRawLine(LogRow(
                 NowStamp(), "CAND#" A_Index,
                 FmtScore(candidate["score"], true),
                 candidate["proc"], FmtPid(candidate["pid"]),
                 FmtCpu(candidate["cpu"], candidate["cpuKnown"]),
                 candidate["audio"] ? "Y" : "N",
                 candidate["nearFS"] ? "Y" : "N",
                 FmtRect(candidate["x"], candidate["y"], candidate["w"], candidate["h"]),
                 FmtHwnd(candidate["hwnd"]), "-", candidate["title"]))
         }
     }
     if (GameLogMode = "DIAGNOSTIC") {
         for _, line in rejects
             LogRawLine(line)
     }
 }
 return candidates.Length ? candidates[1] : 0
}

WindowEngineActivate(item, reason) {
 global WindowEngineFocusActions, WindowEngineLastDecision, LastActionText
 global EnableGameScoreLogging, GameLogMode, GameLogIncludeTitles
 if !WindowEngineValidateItem(item)
     return false
 wasAlreadyActive := WinActive("ahk_id " item["hwnd"]) != 0
 if wasAlreadyActive {
     WindowEngineLastDecision := reason " already active"
     return true
 }
 ok := ActivateWindowRobust(item["hwnd"])
 if ok {
     WindowEngineFocusActions += 1
     HandleCursorAfterManagedFocus(item["hwnd"], false)
     isGameActivation := InStr(reason, "Game ") = 1
         || InStr(reason, "Forced game ") = 1
     if (isGameActivation && EnableGameScoreLogging && GameLogMode != "OFF") {
         logText := NowStamp() " ACTIVATE " reason
         if (GameLogIncludeTitles && item["title"] != "")
             logText .= " | " item["title"]
         LogRawLine(logText)
     }
 }
 WindowEngineLastDecision := reason " " (ok ? "activated" : "failed")
 LastActionText := "WindowEngine: " WindowEngineLastDecision
 return ok
}

WindowEngineFindAlwaysFocus(snapshot) {
 global EnableAlwaysFocus, AlwaysFocusList
 if (!EnableAlwaysFocus || AlwaysFocusList.Length = 0)
     return 0
 best := 0
 bestArea := 0
 for _, item in snapshot {
     legacySurface := WindowEngineIsLegacyApplicationSurface(item, true)
     if (item["scriptOwned"] || item["desktop"] || item["steam"]
         || (item["title"] = "" && !legacySurface)
         || !IsExeInList(item["proc"], AlwaysFocusList))
         continue
     if (item["area"] > bestArea) {
         bestArea := item["area"]
         best := item
     }
 }
 return best
}

WindowEngineFindBpm(snapshot) {
 bestMatch := 0
 bestMatchArea := -1
 bestSteam := 0
 bestSteamArea := -1
 for _, item in snapshot {
     if (item["scriptOwned"] || item["desktop"] || item["title"] = "")
         continue
     if (item["bpm"] && item["area"] > bestMatchArea) {
         bestMatch := item
         bestMatchArea := item["area"]
     }
     ; If Steam changes the Big Picture title entirely, retain the old
     ; practical behavior by falling back to its largest visible surface.
     if (item["steam"] && item["minMax"] != -1
         && item["area"] >= 4096
         && !(item["exStyle"] & 0x08000000)
         && WindowEngineItemIntersectsMonitor(item)
         && item["area"] > bestSteamArea) {
         bestSteam := item
         bestSteamArea := item["area"]
     }
 }
 return IsObject(bestMatch) ? bestMatch : bestSteam
}

; Startup-strength Big Picture detection.
;
; WindowEngineFindBpm above is deliberately permissive: for refocus it only has
; to find "something Steam-ish worth activating", so its 4096 px floor (64x64)
; is the right bar. That bar is wrong for deciding whether Steam has FINISHED
; starting, because Steam's "Connecting", sign-in, and client-update windows all
; clear it and all belong to steam.exe or steamwebhelper.exe. On a Wi-Fi
; handheld those are precisely the windows a boot stalls on, so the permissive
; test would report a healthy session while the user is looking at a stalled
; one -- or, with the curtain up, at nothing at all.
;
; Coverage is the discriminator instead of the title. Big Picture fills its
; monitor and Steam's startup dialogs do not, and that stays true across client
; updates, a renamed or localized window title, and the
; steam.exe/steamwebhelper.exe ownership split -- none of which a title match
; survives on its own. BpmTitle is still consulted first by the permissive
; matcher; this test exists so a title that stops matching degrades to a
; geometry check rather than to a permanent "Steam never started".
SteamBpmSurfacePresent() {
 global SteamStartupSurfaceMinCoverage
 for _, item in WindowEngineGetFreshSnapshot() {
     if (item["scriptOwned"] || item["desktop"] || !item["steam"])
         continue
     ; Minimized, zero-sized, and non-activatable surfaces are not a shell.
     if (item["minMax"] = -1 || item["w"] <= 0 || item["h"] <= 0)
         continue
     if (item["exStyle"] & 0x08000000) ; WS_EX_NOACTIVATE
         continue
     ; Measured against the monitor the window is actually on, so a handheld
     ; docked to a second display is judged against the right dimensions.
     GetMouseParkMonitorBounds(item["hwnd"], &left, &top, &right, &bottom)
     monitorWidth := right - left
     monitorHeight := bottom - top
     if (monitorWidth <= 0 || monitorHeight <= 0)
         continue
     if (item["w"] >= monitorWidth * SteamStartupSurfaceMinCoverage
         && item["h"] >= monitorHeight * SteamStartupSurfaceMinCoverage)
         return true
 }
 return false
}

WindowEngineItemIntersectsMonitor(item) {
 x1 := item["x"]
 y1 := item["y"]
 x2 := x1 + item["w"]
 y2 := y1 + item["h"]
 if (x2 <= x1 || y2 <= y1)
     return false
 try {
     Loop MonitorGetCount() {
         MonitorGet(A_Index, &left, &top, &right, &bottom)
         if (x1 < right && x2 > left && y1 < bottom && y2 > top)
             return true
     }
     return false
 } catch {
     return x1 < A_ScreenWidth && x2 > 0
         && y1 < A_ScreenHeight && y2 > 0
 }
}

WindowEngineIsLegacyApplicationSurface(item, allowMinimized := false) {
 ; Older DirectX games sometimes expose an untitled top-level window or mark
 ; their main render surface as WS_EX_TOOLWINDOW. Accept only a substantial,
 ; unowned, on-screen surface that Windows is allowed to activate.
 if (item["scriptOwned"] || item["desktop"] || item["steam"]
     || item["proc"] = "")
     return false
 if (item["exStyle"] & 0x08000000) ; WS_EX_NOACTIVATE
     return false
 if (item["exStyle"] & 0x00000020) ; WS_EX_TRANSPARENT
     return false
 if (item["owner"] && !(item["exStyle"] & 0x00040000)) ; WS_EX_APPWINDOW
     return false
 if (item["minMax"] = -1) {
     ; Exclusive-fullscreen games often minimize themselves as soon as Steam
     ; wins focus. Task Switcher may still offer an activatable, unowned
     ; top-level surface so selecting it can restore the application.
     return allowMinimized
 }
 if (item["w"] < 320 || item["h"] < 200)
     return false
 minLegacyArea := Min(A_ScreenWidth * A_ScreenHeight * 0.10, 640 * 360)
 if (item["area"] < minLegacyArea)
     return false
 return WindowEngineItemIntersectsMonitor(item)
}

WindowEngineIsMinimizedLegacyGameSurface(item) {
 ; A minimized window has unusable geometry. Restrict automatic restoration
 ; to unowned, activatable WS_POPUP surfaces without a caption—the retained
 ; style signature of an exclusive-fullscreen game such as older DirectX
 ; titles. Ordinary minimized desktop applications remain Task-Switcher-only.
 if (!WindowEngineIsLegacyApplicationSurface(item, true)
     || item["minMax"] != -1)
     return false
 return (item["style"] & 0x80000000) ; WS_POPUP
     && !(item["style"] & 0x00C00000) ; WS_CAPTION
}

WindowEngineIsApplicationBlocker(item) {
 legacySurface := WindowEngineIsLegacyApplicationSurface(item)
 if (item["scriptOwned"] || item["desktop"] || item["steam"]
     || item["bpm"] || item["minMax"] = -1
     || (item["title"] = "" && !legacySurface))
     return false
 if (item["w"] < 64 || item["h"] < 64 || item["area"] < 4096)
     return false
 if (item["exStyle"] & 0x08000000) ; WS_EX_NOACTIVATE
     return false
 return WindowEngineItemIntersectsMonitor(item)
}

WindowEngineFindOpenApplication(snapshot) {
 for _, item in snapshot {
     if WindowEngineIsApplicationBlocker(item)
         return item
 }
 return 0
}

WindowEngineApplyFocusPolicy(snapshot) {
 global EnableSteamRefocusMode
 global AlwaysFocusCooldownMs, LastAlwaysFocusTick
 global SteamRefocusDelay, SteamRefocusTimer
 global GameMinScoreToActivate, GameForegroundCooldownMs, LastGameBringToFrontTick
 global PinnedForegroundHwnd, PinnedForegroundTitle, PinnedForegroundExe, ScriptPid
 global HandsOffUntilTick
 global QuickMenuVisible, FocusAssistancePaused
 global WindowEngineSnapshotByHwnd, WindowEngineLastDecision

 if (QuickMenuVisible || FocusAssistancePaused || A_TickCount < HandsOffUntilTick) {
     WindowEngineLastDecision := QuickMenuVisible
         ? "Quick Menu owns focus"
         : (FocusAssistancePaused ? "Focus assistance paused" : "Hands-off window")
     return false
 }

 activeHwnd := 0
 activePid := 0
 try {
     activeHwnd := WinGetID("A")
     activePid := WinGetPID("ahk_id " activeHwnd)
 }
 if (activePid = ScriptPid) {
     WindowEngineLastDecision := "SteamShell UI owns focus"
     return false
 }

 ; Priority 1: an explicit Task Switcher lock. Dialogs from the same process
 ; are accepted and never pulled behind their parent.
 if (PinnedForegroundHwnd) {
     pinned := 0
     if WindowEngineSnapshotByHwnd.Has(PinnedForegroundHwnd)
         pinned := WindowEngineSnapshotByHwnd[PinnedForegroundHwnd]
     else if DllCall("User32\IsWindow", "Ptr", PinnedForegroundHwnd, "Int") {
         pinnedPid := 0
         pinnedProc := ""
         try {
             pinnedPid := WinGetPID("ahk_id " PinnedForegroundHwnd)
             pinnedProc := StrLower(WinGetProcessName("ahk_id " PinnedForegroundHwnd))
         }
         if (pinnedPid && (PinnedForegroundExe = "" || pinnedProc = StrLower(PinnedForegroundExe))) {
             if (activePid = pinnedPid) {
                 WindowEngineLastDecision := "Pinned process dialog active"
                 return false
             }
             for _, candidate in snapshot {
                 if (candidate["pid"] = pinnedPid
                     && (!IsObject(pinned) || candidate["area"] > pinned["area"]))
                     pinned := candidate
             }
         }
     }
     if !IsObject(pinned) {
         ReleasePinnedForeground(false)
     } else {
         PinnedForegroundHwnd := pinned["hwnd"]
         PinnedForegroundTitle := pinned["title"] != ""
             ? pinned["title"]
             : pinned["proc"] " (legacy fullscreen window)"
         PinnedForegroundExe := pinned["proc"]
         if (activeHwnd = pinned["hwnd"] || activePid = pinned["pid"]) {
             WindowEngineLastDecision := "Pinned process active"
             return false
         }
         return WindowEngineActivate(pinned, "Pinned focus")
     }
 }

 ; Priority 2: explicit AlwaysFocus applications.
 alwaysItem := WindowEngineFindAlwaysFocus(snapshot)
 if IsObject(alwaysItem) {
     SteamRefocusTimer := A_TickCount
     if (activePid = alwaysItem["pid"]) {
         WindowEngineLastDecision := "AlwaysFocus process active"
         return false
     }
     if (A_TickCount - LastAlwaysFocusTick >= AlwaysFocusCooldownMs) {
         LastAlwaysFocusTick := A_TickCount
         return WindowEngineActivate(alwaysItem, "AlwaysFocus")
     }
     WindowEngineLastDecision := "AlwaysFocus cooldown"
     return false
 }

 ; Priority 3: a scored fullscreen or borderless game. Evaluation is read-only;
 ; the arbiter below is the only place allowed to activate the winner.
 allowGame := false
 gameSkipReason := ""
 gameItem := WindowEngineEvaluateGame(snapshot, false, &allowGame, &gameSkipReason)
 if IsObject(gameItem) {
     SteamRefocusTimer := A_TickCount
     if (activePid = gameItem["pid"]) {
         WindowEngineLastDecision := "Game process active"
         return false
     }
     if (allowGame && gameItem["score"] >= GameMinScoreToActivate
         && A_TickCount - LastGameBringToFrontTick >= GameForegroundCooldownMs) {
         LastGameBringToFrontTick := A_TickCount
         return WindowEngineActivate(
             gameItem, "Game " gameItem["proc"] " score=" gameItem["score"])
     }
 }

 ; Priority 4: return to Big Picture only after no other application window has
 ; remained open for the configured delay.
 blocker := WindowEngineFindOpenApplication(snapshot)
 if IsObject(blocker) {
     SteamRefocusTimer := A_TickCount
     if (IsObject(gameItem) && gameSkipReason != "") {
         WindowEngineLastDecision := "Game skipped: " gameSkipReason
     } else {
         blockerTitle := blocker["title"]
         if (StrLen(blockerTitle) > 48)
             blockerTitle := SubStr(blockerTitle, 1, 47) "…"
         WindowEngineLastDecision := "Application open: "
             blocker["proc"] " — " blockerTitle
     }
     return false
 }
 if (!EnableSteamRefocusMode) {
     WindowEngineLastDecision := "Steam refocus disabled"
     return false
 }
 if (A_TickCount - SteamRefocusTimer <= SteamRefocusDelay) {
     WindowEngineLastDecision := "Steam refocus delay"
     return false
 }
 bpmItem := WindowEngineFindBpm(snapshot)
 SteamRefocusTimer := A_TickCount
 if IsObject(bpmItem)
     return WindowEngineActivate(bpmItem, "Steam fallback")
 WindowEngineLastDecision := "Steam Big Picture not found"
 return false
}

TryBringFullscreenCandidateToFront(forceRun := false, forceActivate := false, snapshot := 0) {
 global GameMinScoreToActivate, LastGameBringToFrontTick
 if !IsObject(snapshot)
     snapshot := WindowEngineBuildSnapshot()
 allowActivate := false
 skipReason := ""
 candidate := WindowEngineEvaluateGame(
     snapshot, forceRun, &allowActivate, &skipReason)
 if !IsObject(candidate) || candidate["score"] < GameMinScoreToActivate
     return false
 if (!allowActivate && !forceActivate)
     return false
 LastGameBringToFrontTick := A_TickCount
 return WindowEngineActivate(
     candidate, (forceRun ? "Forced game " : "Game ")
         candidate["proc"] " score=" candidate["score"])
}

; ==============================================================================
; ALWAYSFOCUS MANAGER (Top 5 running apps → add/remove + write to INI)
; ==============================================================================
GetTopRunningApps(maxCount := 5) {
 items := []
 seen := Map()
 for _, item in WindowEngineGetFreshSnapshot() {
     if (items.Length >= maxCount)
         break
     legacySurface := WindowEngineIsLegacyApplicationSurface(item)
     if (item["scriptOwned"] || item["desktop"] || item["steam"]
         || (item["title"] = "" && !legacySurface) || item["proc"] = "")
         continue
     if seen.Has(item["proc"])
         continue
     seen[item["proc"]] := true
     displayTitle := item["title"] != ""
         ? item["title"]
         : item["proc"] " (legacy fullscreen window)"
     items.Push(Map(
         "exe", item["proc"], "title", displayTitle, "hwnd", item["hwnd"]))
 }
 return items
}

RefreshAlwaysFocusManagerLists() {
 global AlwaysFocusGui, AlwaysFocusList
 if !IsSet(AlwaysFocusGui)
 return

 try {
 lvRun := AlwaysFocusGui["LVRun"]
 lvAF := AlwaysFocusGui["LVAF"]

 lvRun.Delete()
 for _, item in GetTopRunningApps(5) {
 lvRun.Add("", item["exe"], item["title"])
 }
 lvRun.ModifyCol(1, 160)
 lvRun.ModifyCol(2, 420)

 lvAF.Delete()
 for _, exe in AlwaysFocusList {
 lvAF.Add("", exe)
 }
 lvAF.ModifyCol(1, 330)
 } catch {
 }
}

AF_SetStatus(message) {
 global AlwaysFocusGui
 if !IsSet(AlwaysFocusGui)
     return
 try AlwaysFocusGui["AFStatus"].Text := message
}

AF_SelectConfiguredExe(exe) {
 global AlwaysFocusGui
 if !IsSet(AlwaysFocusGui)
     return
 try {
     lvAF := AlwaysFocusGui["LVAF"]
     Loop lvAF.GetCount() {
         if (StrLower(lvAF.GetText(A_Index, 1)) = StrLower(exe)) {
             lvAF.Modify(A_Index, "Select Focus Vis")
             return
         }
     }
 }
}

AF_SelectExecutable(prompt) {
 global AlwaysFocusGui, SettingsGui, SettingsEditorDialogActive
 if !IsSet(AlwaysFocusGui)
     return ""

 settingsHwnd := 0
 try {
     AlwaysFocusGui.Opt("+OwnDialogs -AlwaysOnTop")
     WinSetAlwaysOnTop(0, "ahk_id " AlwaysFocusGui.Hwnd)
     if IsSet(SettingsGui) {
         settingsHwnd := SettingsGui.Hwnd
         try SettingsGui.Opt("-AlwaysOnTop")
         try WinSetAlwaysOnTop(0, "ahk_id " settingsHwnd)
     }
 }

 selectedPath := ""
 SettingsEditorDialogActive := true
 try selectedPath := FileSelect(1, A_ProgramFiles, prompt, "Programs (*.exe)")
 catch {
     selectedPath := ""
 } finally {
     SettingsEditorDialogActive := false
     if IsSet(SettingsGui) {
         try SettingsGui.Opt("+AlwaysOnTop")
         try WinSetAlwaysOnTop(1, "ahk_id " SettingsGui.Hwnd)
     }
     if IsSet(AlwaysFocusGui) {
         try AlwaysFocusGui.Opt("+AlwaysOnTop")
         try WinSetAlwaysOnTop(1, "ahk_id " AlwaysFocusGui.Hwnd)
         try WinActivate("ahk_id " AlwaysFocusGui.Hwnd)
     }
 }
 return selectedPath
}

AF_AddSelected(*) {
 global AlwaysFocusGui, AlwaysFocusList, EnableAlwaysFocus, AlwaysFocusExeListRaw
 if !IsSet(AlwaysFocusGui)
 return

 try {
 lvRun := AlwaysFocusGui["LVRun"]
 } catch {
 return
 }

 row := lvRun.GetNext(0, "F")
 if (!row)
 row := lvRun.GetNext()
 if (!row) {
 AF_SetStatus("Select a running application to add first.")
 return
 }

 exe := StrLower(Trim(lvRun.GetText(row, 1)))
 if (exe = "")
 return

 if !InStr(exe, ".exe")
 exe .= ".exe"

 if IsExeInList(exe, AlwaysFocusList) {
 AF_SetStatus(exe " is already in the AlwaysFocus list.")
 AF_SelectConfiguredExe(exe)
 return
 }
 AlwaysFocusList.Push(exe)

 EnableAlwaysFocus := true
 AlwaysFocusExeListRaw := JoinPipe(AlwaysFocusList)

 RefreshAlwaysFocusManagerLists()
 AF_SelectConfiguredExe(exe)
 AF_SetStatus("Added " exe ". Choose Write to INI to make it persistent.")
 SyncControlPanel()
}

AF_BrowseAddExe(*) {
 global AlwaysFocusList, EnableAlwaysFocus, AlwaysFocusExeListRaw

 selectedPath := AF_SelectExecutable("Add an executable to AlwaysFocus")
 if (selectedPath = "")
     return

 exe := ""
 try SplitPath(selectedPath, &exe)
 exe := StrLower(Trim(exe))
 if !RegExMatch(exe, "i)^[a-z0-9][a-z0-9_. -]*\.exe$") {
     AF_SetStatus("The selected file does not have a supported executable filename.")
     return
 }
 if (exe = "steam.exe" || exe = "steamwebhelper.exe") {
     AF_SetStatus("Steam is managed automatically and cannot be added to AlwaysFocus.")
     return
 }
 if IsExeInList(exe, AlwaysFocusList) {
     AF_SelectConfiguredExe(exe)
     AF_SetStatus(exe " is already in the AlwaysFocus list.")
     return
 }

 AlwaysFocusList.Push(exe)
 EnableAlwaysFocus := true
 AlwaysFocusExeListRaw := JoinPipe(AlwaysFocusList)
 RefreshAlwaysFocusManagerLists()
 AF_SelectConfiguredExe(exe)
 AF_SetStatus("Added " exe ". Choose Write to INI to make it persistent.")
 SyncControlPanel()
}

AF_RemoveSelected(*) {
 global AlwaysFocusGui, AlwaysFocusList, AlwaysFocusExeListRaw
 if !IsSet(AlwaysFocusGui)
 return

 try {
 lvAF := AlwaysFocusGui["LVAF"]
 } catch {
 return
 }

 row := lvAF.GetNext(0, "F")
 if (!row)
 row := lvAF.GetNext()
 if (!row) {
 AF_SetStatus("Select an AlwaysFocus executable to remove first.")
 return
 }

 exe := StrLower(Trim(lvAF.GetText(row, 1)))
 if (exe = "")
 return

 newList := []
 for _, v in AlwaysFocusList {
 if (v != exe)
 newList.Push(v)
 }
 AlwaysFocusList := newList
 AlwaysFocusExeListRaw := JoinPipe(AlwaysFocusList)

 RefreshAlwaysFocusManagerLists()
 AF_SetStatus("Removed " exe ". Choose Write to INI to make it persistent.")
 SyncControlPanel()
}

AF_WriteToIni(*) {
 global AlwaysFocusExeListRaw, EnableAlwaysFocus
 EnableAlwaysFocus := true
 if CommitIniChanges([
     Map("section", "Features", "key", "EnableAlwaysFocus", "value", "true"),
     Map("section", "AlwaysFocus", "key", "ExeList", "value", AlwaysFocusExeListRaw)
 ]) {
     AF_SetStatus("AlwaysFocus list saved to the INI.")
 } else {
     AF_SetStatus("SteamShell could not save the AlwaysFocus list.")
 }
}

ShowAlwaysFocusManager(*) {
 global AlwaysFocusGui
 if !IsSet(AlwaysFocusGui) {
 AlwaysFocusGui := Gui("+AlwaysOnTop +ToolWindow +Resize", "AlwaysFocus Manager")
 AlwaysFocusGui.SetFont("s10", "Segoe UI")

 AlwaysFocusGui.AddText(
     "xm ym w620",
     "Pick from visible applications. Steam is managed automatically and intentionally omitted.")

 ; Top: running visible apps
 lvRun := AlwaysFocusGui.AddListView("xm y+6 w620 r7 vLVRun", ["EXE", "Title"])
 lvRun.ModifyCol(1, 160), lvRun.ModifyCol(2, 420)

 ; Bottom-left: session AlwaysFocus list
 AlwaysFocusGui.AddText("xm y+10", "AlwaysFocus list (session):")
 ; Left: action buttons (single aligned column)
 btn := AlwaysFocusGui.AddButton("xm y+6 w240 h30 Section", "Refresh")
 btn.OnEvent("Click", (*) => RefreshAlwaysFocusManagerLists())

 btn := AlwaysFocusGui.AddButton("xs y+8 w240 h30", "Add Selected →")
 btn.OnEvent("Click", AF_AddSelected)

 btn := AlwaysFocusGui.AddButton("xs y+8 w240 h30", "Browse / Add EXE…")
 btn.OnEvent("Click", AF_BrowseAddExe)

 btn := AlwaysFocusGui.AddButton("xs y+8 w240 h30", "Remove Selected")
 btn.OnEvent("Click", AF_RemoveSelected)

 btn := AlwaysFocusGui.AddButton("xs y+8 w240 h30", "Write to INI")
 btn.OnEvent("Click", AF_WriteToIni)

 btn := AlwaysFocusGui.AddButton("xs y+8 w240 h30", "Close")
 btn.OnEvent("Click", (*) => AlwaysFocusGui.Hide())

 ; Session AlwaysFocus list (to the right of the buttons)
 lvAF := AlwaysFocusGui.AddListView("x+10 ys w370 r10 vLVAF", ["EXE"])
 lvAF.ModifyCol(1, 330)

 AlwaysFocusGui.AddText(
     "xm y+10 w620 h22 vAFStatus", "Changes remain in the current session until you choose Write to INI.")

 AlwaysFocusGui.OnEvent("Close", (*) => AlwaysFocusGui.Hide())
 AlwaysFocusGui.OnEvent("Escape", (*) => AlwaysFocusGui.Hide())
 }

 AlwaysFocusGui.Show()
 RefreshAlwaysFocusManagerLists()
}



; ==============================================================================
; CONTROL PANEL + LIVE LOG VIEWER
; ==============================================================================
SyncControlPanel() {
 global ControlGui
 global EnableGameForegroundAssist, EnableSteamRefocusMode, EnableWindowManagement
 global EnableGameScoreLogging, GameLogMode, GameLogIntervalMs
 global GameAssistLogEvenWhenSkipped
 global EnableControllerMouseMode
 global ControllerMouseSpeed, CPCtlSpeedTextCtrl, CPCtlSpeedSliderCtrl
 if !IsSet(ControlGui)
 return
 try {
 ControlGui["cbGame"].Value := EnableGameForegroundAssist ? 1 : 0
 ControlGui["cbSteam"].Value := EnableSteamRefocusMode ? 1 : 0
 ControlGui["cbMax"].Value := EnableWindowManagement ? 1 : 0
 liveOn := (EnableGameScoreLogging && (GameLogMode = "DIAGNOSTIC") && (GameLogIntervalMs <= 1000))
 ControlGui["cbLiveLog"].Value := liveOn ? 1 : 0
 ControlGui["cbSkipLog"].Value := GameAssistLogEvenWhenSkipped ? 1 : 0
 try ControlGui["cbCtlMouse"].Value := EnableControllerMouseMode ? 1 : 0
 try CPCtlSpeedSliderCtrl.Value := ClampInt(ControllerMouseSpeed, 5, 200)
 try CPCtlSpeedTextCtrl.Text := "Mouse speed: " ControllerMouseSpeed
 } catch {
 }
}


OnCtlMouseSpeedChanged(ctrl, *) {
 global ControllerMouseSpeed, CPCtlSpeedTextCtrl
 try {
 v := ClampInt(ctrl.Value, 1, 200)
 ControllerMouseSpeed := v
 try CPCtlSpeedTextCtrl.Text := "Mouse speed: " v
 } catch {
 }
}

GetGuiSeconds(guiObj) {
 secs := 30
 try secs := ToInt(guiObj["editSecs"].Text, 30)
 secs := ClampInt(secs, 1, 3600)
 return secs
}

SetLiveLogging(enable) {
 global EnableGameScoreLogging, GameLogMode, GameLogIntervalMs, GameLogTopN, LiveLogSaved
 if (Type(LiveLogSaved) != "Map")
 LiveLogSaved := Map()
 if (enable) {
 if (!LiveLogSaved.Has("saved")) {
 LiveLogSaved["saved"] := true
 LiveLogSaved["EnableGameScoreLogging"] := EnableGameScoreLogging
 LiveLogSaved["GameLogMode"] := GameLogMode
 LiveLogSaved["GameLogIntervalMs"] := GameLogIntervalMs
 LiveLogSaved["GameLogTopN"] := GameLogTopN
 }
 EnableGameScoreLogging := true
 GameLogMode := "DIAGNOSTIC"
 GameLogIntervalMs := 1000
 GameLogTopN := 3
 } else {
 if (LiveLogSaved.Has("saved")) {
 EnableGameScoreLogging := LiveLogSaved["EnableGameScoreLogging"]
 GameLogMode := LiveLogSaved["GameLogMode"]
 GameLogIntervalMs := LiveLogSaved["GameLogIntervalMs"]
 GameLogTopN := LiveLogSaved["GameLogTopN"]
 LiveLogSaved := Map()
 }
 }
}

UpdateStatusIndicators() {
 global ControlGui, LiveLogGui
 global HandsOffUntilTick, LastBestCandidateText, AlwaysFocusList
 global WindowEngineLastWindowCount, WindowEngineLastTickDurationMs
 global WindowEngineLastDecision, WindowEngineGeometryActions, WindowEngineFocusActions
 global CPStat1Ctrl, CPStat2Ctrl, CPStat3Ctrl, CPStat4Ctrl, CPStat5Ctrl, CPStat6Ctrl, CPStat7Ctrl, CPStat8Ctrl
 global LLStat1Ctrl, LLStat2Ctrl, LLStat3Ctrl, LLStat4Ctrl, LLStat5Ctrl, LLStat6Ctrl, LLStat7Ctrl, LLStat8Ctrl
 global EnableLauncherCleanup, LauncherCleanupDownloadGuard, LauncherCleanupDownloadGuardMode
 global LC_ConfigText, LC_FoundText, LC_GateText, LC_LastDecisionStamp, LC_LastDecisionText

 ; Status runs on a timer. It must never throw or spam errors.
 try {
 steamFg := "-"
 hands := "0s"
 afCount := 0

 ; Steam foreground (use cached "real" foreground logic inside IsSteamForeground()).
 try steamFg := (IsSteamForeground() ? "YES" : "NO")

 ; Hands-Off remaining
 tick := 0
 try tick := HandsOffUntilTick
 if (Type(tick) != "Integer" && Type(tick) != "Float")
 tick := 0
 if (A_TickCount < tick)
 hands := SecondsLeft(tick) "s"
 else
 hands := "0s"

 ; AlwaysFocus count (support Array or Map safely)
 if IsObject(AlwaysFocusList) {
 t := Type(AlwaysFocusList)
 if (t = "Array")
 afCount := AlwaysFocusList.Length
 else if (t = "Map")
 afCount := AlwaysFocusList.Count
 else {
 try afCount := AlwaysFocusList.Length
 }
 }

 ; Ensure display strings are strings (avoid object-to-string conversion errors)
 bestTxt := "-"
 try {
 if (!IsObject(LastBestCandidateText) && LastBestCandidateText != "")
 bestTxt := LastBestCandidateText
 } catch {
 bestTxt := "-"
 }

 txt1 := "Steam Foreground: " steamFg
 txt2 := "Hands-Off Remaining: " hands
 txt3 := "Best Candidate: " bestTxt " AlwaysFocus entries: " afCount
 txt4 := "Window Engine: " WindowEngineLastWindowCount " windows / "
     . WindowEngineLastTickDurationMs "ms — " WindowEngineLastDecision
     . " (geometry " WindowEngineGeometryActions ", focus " WindowEngineFocusActions ")"

 ; Launcher Cleanup status (populated by CheckLauncherCleanup)
 lc1 := "Launcher Cleanup: -"
 lc2 := "LC Found: -"
 lc3 := "LC Gate: -"
 lc4 := "LC Last: -"
 try {
     if (EnableLauncherCleanup)
         lc1 := (LC_ConfigText != "" && !IsObject(LC_ConfigText)) ? LC_ConfigText : "Launcher Cleanup: ON"
     else
         lc1 := "Launcher Cleanup: OFF"
 } catch {
     lc1 := "Launcher Cleanup: -"
 }
 try {
     if (LC_FoundText != "" && !IsObject(LC_FoundText))
         lc2 := "LC Found: " LC_FoundText
 } catch {
 }
 try {
     gate := (LC_GateText != "" && !IsObject(LC_GateText)) ? LC_GateText : "-"
     lastStamp := LC_LastDecisionStamp
     lastText  := LC_LastDecisionText
     lc3 := "LC Gate: " gate
     if (lastStamp != "" && lastText != "")
         lc4 := "LC Last: " lastStamp " — " lastText
     else
         lc4 := "LC Last: -"

 } catch {
 }

 ; Control Panel
 if (IsSet(CPStat1Ctrl) && IsObject(CPStat1Ctrl)) {
 try CPStat1Ctrl.Text := txt1
 try CPStat2Ctrl.Text := txt2
 try CPStat3Ctrl.Text := txt3
 try CPStat4Ctrl.Text := txt4
 try CPStat5Ctrl.Text := lc1
 try CPStat6Ctrl.Text := lc2
 try CPStat7Ctrl.Text := lc3
 try CPStat8Ctrl.Text := lc4
 } else if IsSet(ControlGui) {
 try ControlGui["stat1"].Text := txt1
 try ControlGui["stat2"].Text := txt2
 try ControlGui["stat3"].Text := txt3
 try ControlGui["stat4"].Text := txt4
 try ControlGui["stat5"].Text := lc1
 try ControlGui["stat6"].Text := lc2
 try ControlGui["stat7"].Text := lc3
 try ControlGui["stat8"].Text := lc4
 }

 ; Live Log window
 if (IsSet(LLStat1Ctrl) && IsObject(LLStat1Ctrl)) {
 try LLStat1Ctrl.Text := txt1
 try LLStat2Ctrl.Text := txt2
 try LLStat3Ctrl.Text := txt3
 try LLStat4Ctrl.Text := txt4
 try LLStat5Ctrl.Text := lc1
 try LLStat6Ctrl.Text := lc2
 try LLStat7Ctrl.Text := lc3
 try LLStat8Ctrl.Text := lc4
 } else if IsSet(LiveLogGui) {
 try LiveLogGui["stat1"].Text := txt1
 try LiveLogGui["stat2"].Text := txt2
 try LiveLogGui["stat3"].Text := txt3
 try LiveLogGui["stat4"].Text := txt4
 try LiveLogGui["stat5"].Text := lc1
 try LiveLogGui["stat6"].Text := lc2
 try LiveLogGui["stat7"].Text := lc3
 try LiveLogGui["stat8"].Text := lc4
 }
 } catch {
 return
 }
}



RefreshPanelLog(*) {
 global ControlGui, LiveLogGui, LogPath, PanelLogMaxLines, DetachedLogMaxLines

 if !(IsSet(ControlGui) || IsSet(LiveLogGui))
 return

 txt := ""
 try {
 if FileExist(LogPath)
 txt := FileRead(LogPath, "UTF-8")
 else
 txt := "(log file not found yet)"
 } catch {
 txt := "(unable to read log)"
 }

 ; Newest entries first
 outPanel := GetLastLines(txt, PanelLogMaxLines, true)
 outDet := GetLastLines(txt, DetachedLogMaxLines, true)

 if IsSet(ControlGui) {
 try ControlGui["logView"].Value := outPanel ; may not exist in newer layouts
 }
 if IsSet(LiveLogGui) {
 try LiveLogGui["detLogView"].Value := outDet
 }

 UpdateStatusIndicators()
}

OpenLogFile(*) {
 global LogPath
 if !FileExist(LogPath) {
 try FileAppend("", LogPath, "UTF-8")
 }
 try Run("notepad.exe " Chr(34) LogPath Chr(34))
}

ClearLogFile(*) {
 global LogPath
 try FileDelete(LogPath)
 try FileAppend("", LogPath, "UTF-8")
 RefreshPanelLog()
}

StartHandsOffFromGui(*) {
 global ControlGui, HandsOffUntilTick, LastActionText
 if !IsSet(ControlGui)
 return
 secs := GetGuiSeconds(ControlGui)
 HandsOffUntilTick := A_TickCount + (secs * 1000)
 LastActionText := "Hands-Off enabled (" secs "s)"
 UpdateStatusIndicators()
}

ResumeHandsOffNow(*) {
 global HandsOffUntilTick, LastActionText
 HandsOffUntilTick := 0
 LastActionText := "Hands-Off cleared"
 UpdateStatusIndicators()
}

ApplySessionFromGui(*) {
 global ControlGui
 global EnableGameForegroundAssist, EnableSteamRefocusMode, EnableWindowManagement
 global GameAssistLogEvenWhenSkipped, EnableControllerMouseMode, ControllerMouseSpeed
 if !IsSet(ControlGui)
 return

 EnableGameForegroundAssist := (ControlGui["cbGame"].Value = 1)
 EnableSteamRefocusMode := (ControlGui["cbSteam"].Value = 1)
 EnableWindowManagement := (ControlGui["cbMax"].Value = 1)

 GameAssistLogEvenWhenSkipped := (ControlGui["cbSkipLog"].Value = 1)

 try EnableControllerMouseMode := (ControlGui["cbCtlMouse"].Value = 1)

 try ControllerMouseSpeed := ClampInt(ControlGui["slCtlSpeed"].Value, 1, 200)
 live := (ControlGui["cbLiveLog"].Value = 1)
 SetLiveLogging(live)

 ApplyRuntimeTimers()
 SyncControlPanel()
 UpdateStatusIndicators()
 RefreshPanelLog()
}

RevertPanelToRuntime(*) {
 ; Discard any unchecked/checked edits in the panel and re-sync from current runtime variables.
 SyncControlPanel()
 UpdateStatusIndicators()
 RefreshPanelLog()
}




TimedDisableFromGui(*) {
 global ControlGui
 if !IsSet(ControlGui)
 return

 secs := GetGuiSeconds(ControlGui)

 if (ControlGui["cbGame"].Value = 1)
 TempDisableFeature("Game", secs)
 if (ControlGui["cbSteam"].Value = 1)
 TempDisableFeature("Steam", secs)
 if (ControlGui["cbMax"].Value = 1)
 TempDisableFeature("Max", secs)
 if (ControlGui["cbLiveLog"].Value = 1)
 TempDisableFeature("LiveLog", secs)


 if (ControlGui["cbSkipLog"].Value = 1)
 TempDisableFeature("SkipLog", secs)

 try {
 if (ControlGui["cbCtlMouse"].Value = 1)
 TempDisableFeature("CtlMouse", secs)
 }
 ApplyRuntimeTimers()
 SyncControlPanel()
 RefreshPanelLog()
}

WriteToIniFromGui(*) {
 global ControlGui
 global GameLogMode, GameLogIntervalMs, GameLogTopN
 global EnableControllerMouseMode, ControllerMouseSpeed
 global GameAssistLogEvenWhenSkipped

 if !IsSet(ControlGui)
 return

 changes := [
     Map("section", "Features", "key", "EnableGameForegroundAssist",
         "value", ControlGui["cbGame"].Value = 1 ? "true" : "false"),
     Map("section", "Features", "key", "EnableSteamRefocusMode",
         "value", ControlGui["cbSteam"].Value = 1 ? "true" : "false"),
     Map("section", "Features", "key", "EnableWindowManagement",
         "value", ControlGui["cbMax"].Value = 1 ? "true" : "false"),
     Map("section", "GameForegroundAssist", "key", "GameAssistLogEvenWhenSkipped",
         "value", ControlGui["cbSkipLog"].Value = 1 ? "true" : "false"),
     Map("section", "Controller", "key", "EnableControllerMouseMode",
         "value", ControlGui["cbCtlMouse"].Value = 1 ? "true" : "false"),
     Map("section", "Controller", "key", "ControllerMouseSpeed",
         "value", ControllerMouseSpeed)
 ]

 ; Live logging checkbox writes a DIAGNOSTIC preset for convenience.
 if (ControlGui["cbLiveLog"].Value = 1) {
 changes.Push(Map("section", "Logging", "key", "GameLogMode", "value", "DIAGNOSTIC"))
 changes.Push(Map("section", "Logging", "key", "GameLogIntervalMs", "value", "1000"))
 changes.Push(Map("section", "Logging", "key", "GameLogTopN", "value", "3"))
 } else {
 changes.Push(Map("section", "Logging", "key", "GameLogMode", "value", GameLogMode))
 changes.Push(Map("section", "Logging", "key", "GameLogIntervalMs", "value", GameLogIntervalMs))
 changes.Push(Map("section", "Logging", "key", "GameLogTopN", "value", GameLogTopN))
 }
 if !CommitIniChanges(changes) {
     MsgBox("SteamShell could not save the Control Panel settings.",
         "SteamShell Settings", "Iconx")
     return
 }

 ReloadSettings()
 RefreshPanelLog()
}



ReloadFromIniFromGui(*) {
 ReloadSettings()
 ApplyRuntimeTimers()
 SyncControlPanel()
 UpdateStatusIndicators()
 RefreshPanelLog()
}


GetFeatureState(feature) {
 global EnableGameForegroundAssist, EnableSteamRefocusMode, EnableWindowManagement
 global EnableGameScoreLogging, GameLogMode, GameLogIntervalMs
 global GameAssistLogEvenWhenSkipped
 global EnableControllerMouseMode
 switch feature {
 case "Game": return EnableGameForegroundAssist
 case "Steam": return EnableSteamRefocusMode
 case "Max": return EnableWindowManagement
 case "LiveLog": return (EnableGameScoreLogging && (GameLogMode = "DIAGNOSTIC") && (GameLogIntervalMs <= 1000))
 case "SkipLog": return GameAssistLogEvenWhenSkipped
 case "CtlMouse": return EnableControllerMouseMode
 default: return false
 }
}

SetFeatureState(feature, value) {
 global EnableGameForegroundAssist, EnableSteamRefocusMode, EnableWindowManagement
 global GameAssistLogEvenWhenSkipped, EnableControllerMouseMode
 switch feature {
 case "Game": EnableGameForegroundAssist := value
 case "Steam": EnableSteamRefocusMode := value
 case "Max": EnableWindowManagement := value
 case "CtlMouse": EnableControllerMouseMode := value
 case "LiveLog": SetLiveLogging(value)
 case "SkipLog": GameAssistLogEvenWhenSkipped := value
 }
}

TempDisableFeature(feature, seconds) {
 global TempDisables
 if !GetFeatureState(feature)
 return
 entry := Map()
 entry["prev"] := true
 entry["until"] := A_TickCount + (seconds * 1000)
 TempDisables[feature] := entry
 SetFeatureState(feature, false)
 SetTimer(CheckTempDisables, 250)
}

CheckTempDisables() {
 global TempDisables
 if (TempDisables.Count = 0) {
 SetTimer(CheckTempDisables, 0)
 return
 }
 now := A_TickCount
 restoreAny := false
 for feature, entry in TempDisables {
 if (now >= entry["until"]) {
 SetFeatureState(feature, entry["prev"])
 TempDisables.Delete(feature)
 restoreAny := true
 }
 }
 if (restoreAny) {
 ApplyRuntimeTimers()
 SyncControlPanel()
 }
 if (TempDisables.Count = 0)
 SetTimer(CheckTempDisables, 0)
}

; ==============================================================================
; PERSISTENT SETTINGS EDITOR
; ==============================================================================
GuiLiteralText(text) {
 ; Native Win32 controls interpret a single ampersand as an access-key marker.
 ; Double it whenever user-facing text should display the literal character.
 return StrReplace(text, "&", "&&")
}

SettingsEditorNormalizeWindow() {
 global SettingsGui
 if !IsSet(SettingsGui)
     return
 try {
     settingsHwnd := SettingsGui.Hwnd
     if (WinGetMinMax("ahk_id " settingsHwnd) != 0)
         WinRestore("ahk_id " settingsHwnd)
 }
}

SettingsEditorMsgBox(message, options := "OK", title := "SteamShell Settings") {
 global SettingsGui, SettingsEditorDialogActive
 SettingsEditorNormalizeWindow()
 dialogOptions := Trim(options)
 if IsSet(SettingsGui)
     dialogOptions .= " Owner" SettingsGui.Hwnd
 result := "Cancel"
 SettingsEditorDialogActive := true
 try {
     result := MsgBox(message, title, dialogOptions)
 } finally {
     SettingsEditorDialogActive := false
 }
 if IsSet(SettingsGui) {
     SettingsEditorNormalizeWindow()
     try WinActivate("ahk_id " SettingsGui.Hwnd)
 }
 return result
}

SettingsEditorFileSelect(options, startDir, prompt, filter) {
 global SettingsGui, SettingsEditorDialogActive
 settingsHwnd := 0
 if IsSet(SettingsGui) {
     settingsHwnd := SettingsGui.Hwnd
     try SettingsGui.Opt("+OwnDialogs -AlwaysOnTop")
     try WinSetAlwaysOnTop(0, "ahk_id " settingsHwnd)
 }
 selectedPath := ""
 SettingsEditorDialogActive := true
 try {
     selectedPath := FileSelect(options, startDir, prompt, filter)
 } catch {
     selectedPath := ""
 } finally {
     SettingsEditorDialogActive := false
     if IsSet(SettingsGui) {
         try SettingsGui.Opt("+AlwaysOnTop")
         try WinSetAlwaysOnTop(1, "ahk_id " SettingsGui.Hwnd)
         try WinActivate("ahk_id " SettingsGui.Hwnd)
     }
 }
 return selectedPath
}

SettingsEditorRegisterControl(category, ctrl) {
 global SettingsEditorCategoryControls, SettingsEditorControlPositions
 global SettingsEditorCategoryOffsets, SettingsEditorContentTop
 if !SettingsEditorCategoryControls.Has(category)
     SettingsEditorCategoryControls[category] := []
 SettingsEditorCategoryControls[category].Push(ctrl)
 if !SettingsEditorCategoryOffsets.Has(category)
     SettingsEditorCategoryOffsets[category] := 0
 try {
     ctrl.GetPos(&ctrlX, &ctrlY, &ctrlW, &ctrlH)
     SettingsEditorControlPositions[ctrl.Hwnd] := Map(
         "category", category,
         "x", ctrlX, "y", ctrlY, "w", ctrlW, "h", ctrlH,
         "scrollable", ctrlY >= SettingsEditorContentTop)
 }
 return ctrl
}

; Audits the original, unscrolled geometry for every Settings category. This
; runs once when the native controls exist, so it catches overlaps that a source
; regex cannot: font/DPI-aware control sizes, accidental duplicate placement,
; content crossing into the category list, and controls extending under the
; scrollbar. It reports rather than blocking Settings so recovery remains usable.
SettingsEditorAuditLayout() {
 global SettingsEditorCategories, SettingsEditorCategoryControls
 global SettingsEditorControlPositions
 issues := []
 contentLeft := 245
 contentRight := 945
 for _, category in SettingsEditorCategories {
     if !SettingsEditorCategoryControls.Has(category) {
         issues.Push(category ": category has no registered controls.")
         continue
     }
     controls := SettingsEditorCategoryControls[category]
     positioned := []
     for _, ctrl in controls {
         if !SettingsEditorControlPositions.Has(ctrl.Hwnd) {
             issues.Push(category ": control " ctrl.Hwnd
                 . " was not registered with a position.")
             continue
         }
         pos := SettingsEditorControlPositions[ctrl.Hwnd]
         if (pos["w"] <= 0 || pos["h"] <= 0) {
             issues.Push(category ": control " ctrl.Hwnd " has invalid dimensions.")
             continue
         }
         if (pos["scrollable"]
             && (pos["x"] < contentLeft || pos["x"] + pos["w"] > contentRight)) {
             issues.Push(category ": control " ctrl.Hwnd
                 . " crosses the Settings content boundary.")
         }
         for _, previous in positioned {
             other := previous["pos"]
             overlaps := pos["x"] < other["x"] + other["w"]
                 && pos["x"] + pos["w"] > other["x"]
                 && pos["y"] < other["y"] + other["h"]
                 && pos["y"] + pos["h"] > other["y"]
             if overlaps {
                 issues.Push(category ": controls " previous["hwnd"] " and "
                     . ctrl.Hwnd " overlap at their original positions.")
             }
         }
         positioned.Push(Map("hwnd", ctrl.Hwnd, "pos", pos))
     }
 }
 return issues
}

SettingsEditorReportLayoutAudit() {
 global SettingsEditorStatusCtrl
 issues := SettingsEditorAuditLayout()
 if (issues.Length = 0) {
     LogLine("Settings layout audit passed for all categories.")
     return true
 }
 summary := JoinWith(issues, " | ")
 LogLine("Settings layout audit found " issues.Length " issue(s): " summary)
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Layout warning recorded in SteamShell.log"
 return false
}

SettingsEditorAddHeading(category, title, description) {
 global SettingsGui
 titleCtrl := SettingsGui.AddText("x245 y78 w710 h28", GuiLiteralText(title))
 titleCtrl.SetFont("s15 Bold", "Segoe UI")
 descCtrl := SettingsGui.AddText("x245 y108 w710 h34 +Wrap", GuiLiteralText(description))
 descCtrl.SetFont("s9 Norm", "Segoe UI")
 SettingsEditorRegisterControl(category, titleCtrl)
 SettingsEditorRegisterControl(category, descCtrl)
}

SettingsEditorMarkDirty(*) {
 global SettingsEditorDirty, SettingsEditorUpdating, SettingsEditorStatusCtrl
 if (SettingsEditorUpdating)
     return
 SettingsEditorDirty := true
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Unsaved changes"
}

SettingsEditorAddCheckbox(category, section, key, label, &y, defaultValue := "false") {
 global SettingsGui, SettingsEditorFields
 ctrl := SettingsGui.AddCheckbox("x255 y" y " w690 h25", label)
 ctrl.Value := ToBool(IniReadS(section, key, defaultValue), ToBool(defaultValue, false))
 ctrl.OnEvent("Click", SettingsEditorMarkDirty)
 SettingsEditorRegisterControl(category, ctrl)
 field := Map(
     "category", category, "section", section, "key", key,
     "label", label, "type", "bool", "ctrl", ctrl,
     "controls", [ctrl])
 SettingsEditorFields.Push(field)
 y += 31
 return ctrl
}

SettingsEditorAddTextField(category, section, key, label, &y, defaultValue := ""
    , fieldType := "text", minValue := "", maxValue := "", rows := 1) {
 global SettingsGui, SettingsEditorFields
 labelCtrl := SettingsGui.AddText("x255 y" (y + 4) " w315 h24", label)
 options := "x575 y" y " w370"
 if (rows > 1)
     options .= " r" rows " WantTab"
 initialValue := IniReadS(section, key, defaultValue)
 if (fieldType = "percent") {
     storedDefault := ToFloat(defaultValue, 0.0)
     initialValue := FormatSettingsFloat(
         ToFloat(initialValue, storedDefault) * 100, 4)
 }
 ctrl := SettingsGui.AddEdit(options, initialValue)
 ctrl.OnEvent("Change", SettingsEditorMarkDirty)
 SettingsEditorRegisterControl(category, labelCtrl)
 SettingsEditorRegisterControl(category, ctrl)
 field := Map(
     "category", category, "section", section, "key", key,
     "label", label, "type", fieldType, "ctrl", ctrl,
     "min", minValue, "max", maxValue,
     "controls", [labelCtrl, ctrl])
 SettingsEditorFields.Push(field)
 y += rows > 1 ? (30 + rows * 20) : 34
 return field
}

SettingsEditorParseExeList(raw) {
 list := []
 seen := Map()
 raw := Trim(raw)
 if (raw = "")
     return list

 ; Match the runtime parser's comment handling while retaining the original
 ; filename capitalization for a friendlier settings display.
 commentPos := InStr(raw, ";")
 if (commentPos)
     raw := Trim(SubStr(raw, 1, commentPos - 1))
 commentPos := InStr(raw, "#")
 if (commentPos)
     raw := Trim(SubStr(raw, 1, commentPos - 1))

 for _, part in StrSplit(raw, "|") {
     exe := Trim(part)
     if (exe = "")
         continue
     if !RegExMatch(exe, "i)\.exe$")
         exe .= ".exe"
     if !RegExMatch(exe, "i)^[a-z0-9][a-z0-9_. -]*\.exe$")
         continue
     normalized := StrLower(exe)
     if seen.Has(normalized)
         continue
     seen[normalized] := true
     list.Push(exe)
 }
 return list
}

SettingsEditorAddExeListField(category, section, key, label, x, y, width := 335
    , defaultValue := "") {
 global SettingsGui, SettingsEditorFields

 labelCtrl := SettingsGui.AddText("x" x " y" y " w" width " h22", label)
 listCtrl := SettingsGui.AddListView(
     "x" x " y" (y + 24) " w" width " h132 -Multi", ["Executable"])
 for _, exe in SettingsEditorParseExeList(IniReadS(section, key, defaultValue))
     listCtrl.Add("", exe)
 listCtrl.ModifyCol(1, width - 24)

 buttonGap := 8
 buttonWidth := Floor((width - buttonGap) / 2)
 addButton := SettingsGui.AddButton(
     "x" x " y" (y + 164) " w" buttonWidth " h30", "Browse / Add…")
 removeButton := SettingsGui.AddButton(
     "x" (x + buttonWidth + buttonGap) " y" (y + 164)
     " w" buttonWidth " h30", "Remove Selected")

 field := Map(
     "category", category, "section", section, "key", key,
     "label", label, "type", "exe-list", "ctrl", listCtrl,
     "controls", [labelCtrl, listCtrl, addButton, removeButton])
 addButton.OnEvent("Click", SettingsEditorBrowseAddExe.Bind(field))
 removeButton.OnEvent("Click", SettingsEditorRemoveSelectedExe.Bind(field))

 SettingsEditorRegisterControl(category, labelCtrl)
 SettingsEditorRegisterControl(category, listCtrl)
 SettingsEditorRegisterControl(category, addButton)
 SettingsEditorRegisterControl(category, removeButton)
 SettingsEditorFields.Push(field)
 return field
}

SettingsEditorBrowseAddExe(field, *) {
 global SettingsEditorStatusCtrl
 static lastBrowseDirs := Map()

 fieldId := field["section"] "\" field["key"]
 startDir := lastBrowseDirs.Has(fieldId) ? lastBrowseDirs[fieldId] : A_ProgramFiles
 selectedPath := SettingsEditorFileSelect(
     1, startDir, "Add an executable to " field["label"], "Programs (*.exe)")
 if (selectedPath = "")
     return

 exe := ""
 selectedDir := ""
 try SplitPath(selectedPath, &exe, &selectedDir)
 exe := Trim(exe)
 if (selectedDir != "")
     lastBrowseDirs[fieldId] := selectedDir
 if !RegExMatch(exe, "i)^[a-z0-9][a-z0-9_. -]*\.exe$") {
     SettingsEditorMsgBox(
         "The selected file does not have a supported executable filename.", "Icon!")
     return
 }

 listCtrl := field["ctrl"]
 Loop listCtrl.GetCount() {
     if (StrLower(listCtrl.GetText(A_Index, 1)) = StrLower(exe)) {
         listCtrl.Modify(A_Index, "Select Focus Vis")
         if IsObject(SettingsEditorStatusCtrl)
             SettingsEditorStatusCtrl.Text := exe " is already in " field["label"]
         return
     }
 }

 row := listCtrl.Add("", exe)
 listCtrl.Modify(row, "Select Focus Vis")
 SettingsEditorMarkDirty()
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Added " exe " to " field["label"]
}

SettingsEditorRemoveSelectedExe(field, *) {
 global SettingsEditorStatusCtrl
 listCtrl := field["ctrl"]
 row := listCtrl.GetNext(0, "F")
 if (!row)
     row := listCtrl.GetNext()
 if (!row) {
     if IsObject(SettingsEditorStatusCtrl)
         SettingsEditorStatusCtrl.Text := "Select an executable to remove first"
     return
 }

 exe := listCtrl.GetText(row, 1)
 listCtrl.Delete(row)
 remainingRows := listCtrl.GetCount()
 if (remainingRows > 0)
     listCtrl.Modify(Min(row, remainingRows), "Select Focus Vis")
 SettingsEditorMarkDirty()
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Removed " exe " from " field["label"]
}

SettingsEditorGetExeListValues(field) {
 values := []
 if !IsObject(field) || !field.Has("ctrl")
     return values
 listCtrl := field["ctrl"]
 try {
     Loop listCtrl.GetCount() {
         exe := Trim(listCtrl.GetText(A_Index, 1))
         if (exe != "")
             values.Push(StrLower(exe))
     }
 }
 return values
}

SettingsEditorPreviewLauncherCleanup(*) {
 global LC_GateText, LC_ConfigText
 launcherField := SettingsEditorFindField("LauncherCleanup", "LauncherExeList")
 helperField := SettingsEditorFindField("LauncherCleanup", "BackgroundExeList")
 launchers := SettingsEditorGetExeListValues(launcherField)
 helpers := SettingsEditorGetExeListValues(helperField)
 runningLaunchers := []
 runningHelpers := []
 for _, exe in launchers {
     if ProcessExist(exe)
         runningLaunchers.Push(exe)
 }
 for _, exe in helpers {
     if ProcessExist(exe)
         runningHelpers.Push(exe)
 }
 report := "This is a read-only preview. No process will be closed.`n`n"
     . "Running launcher targets:`n"
     . (runningLaunchers.Length ? "  " JoinWith(runningLaunchers, "`n  ") : "  None")
     . "`n`nRunning background-helper targets:`n"
     . (runningHelpers.Length ? "  " JoinWith(runningHelpers, "`n  ") : "  None")
     . "`n`nCurrent cleanup status:`n  "
     . (LC_ConfigText != "" ? LC_ConfigText : "-")
     . "`n  " (LC_GateText != "" ? LC_GateText : "-")
 SettingsEditorMsgBox(report, "OK Iconi", "Launcher Cleanup Preview")
}

SettingsEditorAddChoice(category, section, key, label, choices, &y, defaultValue := "") {
 global SettingsGui, SettingsEditorFields
 labelCtrl := SettingsGui.AddText("x255 y" (y + 4) " w315 h24", label)
 ctrl := SettingsGui.AddDropDownList("x575 y" y " w320", choices)
 current := IniReadS(section, key, defaultValue)
 selectedIndex := 1
 for index, choice in choices {
     if (StrLower(choice) = StrLower(current)) {
         selectedIndex := index
         break
     }
 }
 ctrl.Choose(selectedIndex)
 ctrl.OnEvent("Change", SettingsEditorMarkDirty)
 SettingsEditorRegisterControl(category, labelCtrl)
 SettingsEditorRegisterControl(category, ctrl)
 field := Map(
     "category", category, "section", section, "key", key,
     "label", label, "type", "choice", "ctrl", ctrl,
     "choices", choices, "controls", [labelCtrl, ctrl])
 SettingsEditorFields.Push(field)
 y += 34
 return ctrl
}

SettingsEditorAddMappedChoice(category, section, key, label, choices, values, &y, defaultValue := "") {
 global SettingsGui, SettingsEditorFields
 labelCtrl := SettingsGui.AddText("x255 y" (y + 4) " w315 h24", label)
 displayChoices := []
 storedValues := []
 choiceCount := Min(choices.Length, values.Length)
 Loop choiceCount {
     displayChoices.Push(choices[A_Index])
     storedValues.Push(values[A_Index] "")
 }

 current := Trim(IniReadS(section, key, defaultValue))
 if (current = "")
     current := defaultValue ""
 selectedIndex := 0
 for index, storedValue in storedValues {
     if (StrLower(storedValue) = StrLower(current)) {
         selectedIndex := index
         break
     }
 }
 ; Preserve an advanced INI value instead of silently replacing it merely
 ; because the Settings window was opened and saved.
 if (!selectedIndex) {
     displayChoices.Push("Custom (" current ")")
     storedValues.Push(current)
     selectedIndex := displayChoices.Length
 }

 ctrl := SettingsGui.AddDropDownList("x575 y" y " w320", displayChoices)
 ctrl.Choose(selectedIndex)
 ctrl.OnEvent("Change", SettingsEditorMarkDirty)
 SettingsEditorRegisterControl(category, labelCtrl)
 SettingsEditorRegisterControl(category, ctrl)
 field := Map(
     "category", category, "section", section, "key", key,
     "label", label, "type", "mapped-choice", "ctrl", ctrl,
     "choices", displayChoices, "values", storedValues,
     "controls", [labelCtrl, ctrl])
 SettingsEditorFields.Push(field)
 y += 34
 return ctrl
}

SettingsEditorAddPathField(category, section, key, label, &y, prompt, filter, defaultValue := "") {
 global SettingsGui, SettingsEditorFields
 labelCtrl := SettingsGui.AddText("x255 y" (y + 4) " w180 h24", label)
 ctrl := SettingsGui.AddEdit("x440 y" y " w400", IniReadS(section, key, defaultValue))
 browseButton := SettingsGui.AddButton("x850 y" (y - 1) " w92 h27", "Browse…")
 field := Map(
     "category", category, "section", section, "key", key,
     "label", label, "type", "path", "ctrl", ctrl)
 ctrl.OnEvent("Change", SettingsEditorMarkDirty)
 browseButton.OnEvent("Click", SettingsEditorBrowsePath.Bind(field, prompt, filter))
 SettingsEditorRegisterControl(category, labelCtrl)
 SettingsEditorRegisterControl(category, ctrl)
 SettingsEditorRegisterControl(category, browseButton)
 SettingsEditorFields.Push(field)
 y += 35
 return field
}

SettingsEditorAddShortcutField(category, section, key, label, &y, defaultValue := "") {
 global SettingsGui, SettingsEditorFields
 labelCtrl := SettingsGui.AddText("x255 y" (y + 4) " w315 h24", label)
 ctrl := SettingsGui.AddEdit("x575 y" y " w245", IniReadS(section, key, defaultValue))
 recordButton := SettingsGui.AddButton("x830 y" (y - 1) " w112 h27", "Record…")
 field := Map(
     "category", category, "section", section, "key", key,
     "label", label, "type", "text", "ctrl", ctrl,
     "controls", [labelCtrl, ctrl, recordButton])
 ctrl.OnEvent("Change", SettingsEditorMarkDirty)
 recordButton.OnEvent("Click", SettingsEditorRecordShortcut.Bind(field))
 SettingsEditorRegisterControl(category, labelCtrl)
 SettingsEditorRegisterControl(category, ctrl)
 SettingsEditorRegisterControl(category, recordButton)
 SettingsEditorFields.Push(field)
 y += 34
 return field
}

SettingsEditorSetFieldEnabled(section, key, enabled) {
 field := SettingsEditorFindField(section, key)
 if !IsObject(field)
     return
 controls := field.Has("controls") ? field["controls"] : [field["ctrl"]]
 for _, ctrl in controls {
     try ctrl.Enabled := enabled
 }
}

SettingsEditorRefreshDependencies(*) {
 gameAssist := SettingsEditorFindField(
     "Features", "EnableGameForegroundAssist")
 gameAssistEnabled := !IsObject(gameAssist)
     || gameAssist["ctrl"].Value = 1
 SettingsEditorSetFieldEnabled(
     "GameForegroundAssist", "GameRequireSteamForeground",
     gameAssistEnabled)
 SettingsEditorSetFieldEnabled(
     "GameForegroundAssist", "GameMinScoreToActivate",
     gameAssistEnabled)

 windowManagement := SettingsEditorFindField(
     "Features", "EnableWindowManagement")
 windowManagementEnabled := !IsObject(windowManagement)
     || windowManagement["ctrl"].Value = 1
 SettingsEditorSetFieldEnabled(
     "WindowManagement", "MinWidthPercent", windowManagementEnabled)
 SettingsEditorSetFieldEnabled(
     "WindowManagement", "ExcludeExeList", windowManagementEnabled)

 rtssOverlayMode := SettingsEditorFindField("RTSS", "OverlayControlMode")
 rtssLimiterMode := SettingsEditorFindField("RTSS", "FrameLimiterControlMode")
 overlaySeparate := IsObject(rtssOverlayMode)
     && StrLower(rtssOverlayMode["ctrl"].Text) = "separate"
 limiterSeparate := IsObject(rtssLimiterMode)
     && StrLower(rtssLimiterMode["ctrl"].Text) = "separate"
 SettingsEditorSetFieldEnabled("RTSS", "OverlayToggleShortcut", !overlaySeparate)
 SettingsEditorSetFieldEnabled("RTSS", "OverlayOnShortcut", overlaySeparate)
 SettingsEditorSetFieldEnabled("RTSS", "OverlayOffShortcut", overlaySeparate)
 SettingsEditorSetFieldEnabled("RTSS", "CustomFrameCapShortcut", !limiterSeparate)
 SettingsEditorSetFieldEnabled("RTSS", "FrameLimiterOnShortcut", limiterSeparate)
 SettingsEditorSetFieldEnabled("RTSS", "FrameLimiterOffShortcut", limiterSeparate)

 requireNoGame := SettingsEditorFindField("LauncherCleanup", "RequireNoGame")
 useCpuAudio := SettingsEditorFindField("LauncherCleanup", "UseCpuAudio")
 downloadGuard := SettingsEditorFindField("LauncherCleanup", "DownloadGuard")
 noGameEnabled := IsObject(requireNoGame) && requireNoGame["ctrl"].Value = 1
 cpuAudioEnabled := noGameEnabled && IsObject(useCpuAudio)
     && useCpuAudio["ctrl"].Value = 1
 SettingsEditorSetFieldEnabled("LauncherCleanup", "UseCpuAudio", noGameEnabled)
 SettingsEditorSetFieldEnabled("LauncherCleanup", "CpuThreshold", cpuAudioEnabled)
 SettingsEditorSetFieldEnabled(
     "LauncherCleanup", "DownloadGuardMode",
     IsObject(downloadGuard) && downloadGuard["ctrl"].Value = 1)

 logModeField := SettingsEditorFindField("Logging", "GameLogMode")
 logMode := IsObject(logModeField) ? StrUpper(logModeField["ctrl"].Text) : "OFF"
 detailedLogging := logMode = "TOPN" || logMode = "DIAGNOSTIC"
 SettingsEditorSetFieldEnabled("Logging", "GameLogTopN", detailedLogging)
 SettingsEditorSetFieldEnabled("Logging", "GameLogIntervalMs", detailedLogging)
 SettingsEditorSetFieldEnabled("Logging", "GameLogIncludeTitles", logMode != "OFF")
 SettingsEditorSetFieldEnabled(
     "GameForegroundAssist", "GameAssistLogEvenWhenSkipped", detailedLogging)
}

SettingsEditorRecordShortcut(field, *) {
 global SettingsEditorStatusCtrl
 result := RecordShortcutChord()
 if !result["ok"]
     return
 field["ctrl"].Value := result["send"]
 SettingsEditorMarkDirty()
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Recorded " result["display"] " for " field["label"]
}

SettingsEditorAddActionButton(category, label, callback, x, y, width := 210) {
 global SettingsGui
 ctrl := SettingsGui.AddButton("x" x " y" y " w" width " h30", label)
 ctrl.OnEvent("Click", callback)
 SettingsEditorRegisterControl(category, ctrl)
 return ctrl
}

SettingsEditorBrowsePath(field, prompt, filter, *) {
 currentPath := NormalizeMediaPath(field["ctrl"].Value)
 startDir := A_ScriptDir
 if (currentPath != "") {
     fileName := ""
     candidateDir := ""
     try SplitPath(currentPath, &fileName, &candidateDir)
     if (candidateDir != "" && DirExist(candidateDir))
         startDir := candidateDir
 }
 selectedPath := SettingsEditorFileSelect(1, startDir, prompt, filter)
 if (selectedPath = "")
     return
 field["ctrl"].Value := selectedPath
 SettingsEditorMarkDirty()
}

SettingsEditorCategoryChanged(ctrl, *) {
 SettingsEditorShowCategory(ctrl.Value)
}

SettingsEditorShowCategory(categoryIndex) {
 global SettingsEditorCategories, SettingsGui
 categoryIndex := ClampInt(categoryIndex, 1, SettingsEditorCategories.Length)
 activeCategory := SettingsEditorCategories[categoryIndex]
 try SettingsGui["settingsCategoryList"].Choose(categoryIndex)
 SettingsEditorApplyCategoryLayout(activeCategory)
}

SettingsEditorResized(guiObj, minMax, newWidth, newHeight) {
 global SettingsGui, SettingsEditorCategories, SettingsEditorContentTop
 global SettingsEditorContentBottom, SettingsEditorWindowHeight
 global SettingsEditorScrollBar, SettingsEditorFooterControls
 global SettingsEditorStatusCtrl, SettingsEditorDividerCtrl
 if (minMax = -1 || !IsSet(SettingsGui) || guiObj.Hwnd != SettingsGui.Hwnd)
     return
 if (newHeight < 450 || SettingsEditorFooterControls.Length < 3)
     return

 SettingsEditorWindowHeight := newHeight
 dividerY := newHeight - 90
 buttonY := dividerY + 15
 SettingsEditorContentBottom := dividerY - 8

 try SettingsGui["settingsCategoryList"].Move(20, 82, 205, Max(100, dividerY - 98))
 try SettingsEditorDividerCtrl.Move(20, dividerY, 925, 1)
 try SettingsEditorFooterControls[1].Move(540, buttonY, 145, 34)
 try SettingsEditorFooterControls[2].Move(695, buttonY, 125, 34)
 try SettingsEditorFooterControls[3].Move(830, buttonY, 115, 34)
 try SettingsEditorStatusCtrl.Move(20, newHeight - 32, 925, 24)
 try SettingsEditorScrollBar.Move(
     954, SettingsEditorContentTop, 18, Max(40, SettingsEditorContentBottom - SettingsEditorContentTop))

 categoryIndex := ClampInt(
     SettingsGui["settingsCategoryList"].Value, 1, SettingsEditorCategories.Length)
 SettingsEditorApplyCategoryLayout(SettingsEditorCategories[categoryIndex])
}

SettingsEditorGetMaxScroll(category) {
 global SettingsEditorCategoryControls, SettingsEditorControlPositions, SettingsEditorContentBottom
 maxBottom := SettingsEditorContentBottom
 if !SettingsEditorCategoryControls.Has(category)
     return 0
 for _, ctrl in SettingsEditorCategoryControls[category] {
     if !SettingsEditorControlPositions.Has(ctrl.Hwnd)
         continue
     pos := SettingsEditorControlPositions[ctrl.Hwnd]
     if (pos["scrollable"])
         maxBottom := Max(maxBottom, pos["y"] + pos["h"])
 }
 return Max(0, maxBottom - SettingsEditorContentBottom)
}

SettingsEditorApplyCategoryLayout(activeCategory) {
 global SettingsEditorCategoryControls, SettingsEditorControlPositions
 global SettingsEditorCategoryOffsets, SettingsEditorContentTop, SettingsEditorContentBottom

 ; Batch all control movement while redraw is disabled. Without this, Windows can
 ; repaint controls between Move and Visible changes during thumb tracking,
 ; leaving trails or partially drawn controls in the settings viewport.
 SettingsEditorSetRedraw(false)
 try {
     offset := SettingsEditorCategoryOffsets.Has(activeCategory) ? SettingsEditorCategoryOffsets[activeCategory] : 0
     maxOffset := SettingsEditorGetMaxScroll(activeCategory)
     offset := ClampInt(offset, 0, maxOffset)
     SettingsEditorCategoryOffsets[activeCategory] := offset

     for category, controls in SettingsEditorCategoryControls {
         isActive := category = activeCategory
         for _, ctrl in controls {
             if !isActive {
                 try ctrl.Visible := false
                 continue
             }
             if !SettingsEditorControlPositions.Has(ctrl.Hwnd) {
                 try ctrl.Visible := true
                 continue
             }
             pos := SettingsEditorControlPositions[ctrl.Hwnd]
             if (!pos["scrollable"]) {
                 try ctrl.Move(pos["x"], pos["y"], pos["w"], pos["h"])
                 try ctrl.Visible := true
                 continue
             }
             newY := pos["y"] - offset
             isInside := newY >= SettingsEditorContentTop
                 && newY + pos["h"] <= SettingsEditorContentBottom
             try ctrl.Move(pos["x"], newY, pos["w"], pos["h"])
             try ctrl.Visible := isInside
         }
     }

     SettingsEditorUpdateScrollBar(offset, maxOffset)
 } finally {
     SettingsEditorSetRedraw(true)
     SettingsEditorRepaint()
 }
}

SettingsEditorSetRedraw(enabled) {
 global SettingsGui
 if !IsSet(SettingsGui) || !IsObject(SettingsGui)
     return
 try DllCall("User32\SendMessageW"
     , "Ptr", SettingsGui.Hwnd
     , "UInt", 0x000B ; WM_SETREDRAW
     , "Ptr", enabled ? 1 : 0
     , "Ptr", 0
     , "Ptr")
}

SettingsEditorRepaint() {
 global SettingsGui
 if !IsSet(SettingsGui) || !IsObject(SettingsGui)
     return
 ; RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW
 try DllCall("User32\RedrawWindow"
     , "Ptr", SettingsGui.Hwnd
     , "Ptr", 0
     , "Ptr", 0
     , "UInt", 0x0185
     , "Int")
}

SettingsEditorUpdateScrollBar(offset, maxOffset) {
 global SettingsEditorScrollBar, SettingsEditorContentTop, SettingsEditorContentBottom
 if !IsObject(SettingsEditorScrollBar)
     return
 if (maxOffset <= 0) {
     try SettingsEditorScrollBar.Visible := false
     return
 }

 viewportHeight := Max(1, SettingsEditorContentBottom - SettingsEditorContentTop)
 contentHeight := viewportHeight + maxOffset
 scrollInfo := Buffer(28, 0)
 NumPut("UInt", 28, scrollInfo, 0)
 NumPut("UInt", 0x7, scrollInfo, 4) ; SIF_RANGE | SIF_PAGE | SIF_POS
 NumPut("Int", 0, scrollInfo, 8)
 NumPut("Int", contentHeight - 1, scrollInfo, 12)
 NumPut("UInt", viewportHeight, scrollInfo, 16)
 NumPut("Int", offset, scrollInfo, 20)
 try DllCall("User32\SetScrollInfo"
     , "Ptr", SettingsEditorScrollBar.Hwnd
     , "Int", 2 ; SB_CTL
     , "Ptr", scrollInfo
     , "Int", true)
 try SettingsEditorScrollBar.Visible := true
}

SettingsEditorGetScrollTrackPosition() {
 global SettingsEditorScrollBar
 if !IsObject(SettingsEditorScrollBar)
     return 0
 scrollInfo := Buffer(28, 0)
 NumPut("UInt", 28, scrollInfo, 0)
 NumPut("UInt", 0x10, scrollInfo, 4) ; SIF_TRACKPOS
 try {
     if DllCall("User32\GetScrollInfo"
         , "Ptr", SettingsEditorScrollBar.Hwnd
         , "Int", 2 ; SB_CTL
         , "Ptr", scrollInfo)
         return NumGet(scrollInfo, 24, "Int")
 }
 return 0
}

SettingsEditorVerticalScroll(wParam, lParam, msg, hwnd) {
 global SettingsGui, SettingsEditorScrollBar, SettingsEditorCategories
 global SettingsEditorCategoryOffsets, SettingsEditorContentTop, SettingsEditorContentBottom
 if !IsSet(SettingsGui) || !IsObject(SettingsEditorScrollBar)
     return
 if (lParam != SettingsEditorScrollBar.Hwnd)
     return

 categoryIndex := ClampInt(SettingsGui["settingsCategoryList"].Value, 1, SettingsEditorCategories.Length)
 category := SettingsEditorCategories[categoryIndex]
 currentOffset := SettingsEditorCategoryOffsets.Has(category) ? SettingsEditorCategoryOffsets[category] : 0
 maxOffset := SettingsEditorGetMaxScroll(category)
 scrollCode := wParam & 0xFFFF
 lineStep := 34
 pageStep := Max(68, SettingsEditorContentBottom - SettingsEditorContentTop - 34)

 switch scrollCode {
 case 0: ; SB_LINEUP
     newOffset := currentOffset - lineStep
 case 1: ; SB_LINEDOWN
     newOffset := currentOffset + lineStep
 case 2: ; SB_PAGEUP
     newOffset := currentOffset - pageStep
 case 3: ; SB_PAGEDOWN
     newOffset := currentOffset + pageStep
 case 4, 5: ; SB_THUMBPOSITION / SB_THUMBTRACK
     newOffset := SettingsEditorGetScrollTrackPosition()
 case 6: ; SB_TOP
     newOffset := 0
 case 7: ; SB_BOTTOM
     newOffset := maxOffset
 default:
     return 0
 }

 SettingsEditorCategoryOffsets[category] := ClampInt(newOffset, 0, maxOffset)
 SettingsEditorApplyCategoryLayout(category)
 return 0
}

SettingsEditorScroll(direction, *) {
 global SettingsGui, SettingsEditorCategories, SettingsEditorCategoryOffsets
 if !IsSet(SettingsGui)
     return
 categoryIndex := SettingsGui["settingsCategoryList"].Value
 categoryIndex := ClampInt(categoryIndex, 1, SettingsEditorCategories.Length)
 category := SettingsEditorCategories[categoryIndex]
 currentOffset := SettingsEditorCategoryOffsets.Has(category) ? SettingsEditorCategoryOffsets[category] : 0
 maxOffset := SettingsEditorGetMaxScroll(category)
 SettingsEditorCategoryOffsets[category] := ClampInt(currentOffset + (direction * 68), 0, maxOffset)
 SettingsEditorApplyCategoryLayout(category)
}

SettingsEditorMouseWheel(wParam, lParam, msg, hwnd) {
 global SettingsGui
 if !IsSet(SettingsGui)
     return
 rootHwnd := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
 if (rootHwnd != SettingsGui.Hwnd)
     return
 controlClass := ""
 try controlClass := WinGetClass("ahk_id " hwnd)
 if (controlClass = "SysListView32")
     return
 delta := (wParam >> 16) & 0xFFFF
 if (delta & 0x8000)
     delta -= 0x10000
 if (delta != 0)
     SettingsEditorScroll(delta > 0 ? -1 : 1)
 return 0
}

SettingsEditorRevealControl(ctrl) {
 global SettingsEditorControlPositions, SettingsEditorCategoryOffsets
 global SettingsEditorContentTop, SettingsEditorContentBottom
 if !SettingsEditorControlPositions.Has(ctrl.Hwnd)
     return
 pos := SettingsEditorControlPositions[ctrl.Hwnd]
 if (!pos["scrollable"])
     return
 category := pos["category"]
 offset := SettingsEditorCategoryOffsets.Has(category) ? SettingsEditorCategoryOffsets[category] : 0
 visibleY := pos["y"] - offset
 if (visibleY < SettingsEditorContentTop)
     offset := pos["y"] - SettingsEditorContentTop
 else if (visibleY + pos["h"] > SettingsEditorContentBottom)
     offset := pos["y"] + pos["h"] - SettingsEditorContentBottom
 SettingsEditorCategoryOffsets[category] := ClampInt(offset, 0, SettingsEditorGetMaxScroll(category))
 SettingsEditorApplyCategoryLayout(category)
}

SettingsEditorControllerActive() {
 global SettingsGui, SettingsEditorDialogActive, ScriptPid
 if !IsSet(SettingsGui)
     return false
 if !IsGuiVisible(SettingsGui)
     return false
 activeHwnd := 0
 try activeHwnd := WinGetID("A")
 if !activeHwnd
     return false
 if SettingsEditorDialogActive
     return true
 if (activeHwnd = SettingsGui.Hwnd)
     return true
 try {
     if (WinGetPID("ahk_id " activeHwnd) = ScriptPid)
         return true
 }
 ; Native common dialogs may be hosted outside the script process. Accept an
 ; active window whose owner chain leads back to Settings.
 ownerHwnd := activeHwnd
 Loop 8 {
     ownerHwnd := DllCall(
         "User32\GetWindow", "Ptr", ownerHwnd, "UInt", 4, "Ptr") ; GW_OWNER
     if !ownerHwnd
         break
     if (ownerHwnd = SettingsGui.Hwnd)
         return true
 }
 return false
}

SettingsEditorPrimaryActive() {
 global SettingsGui
 if !IsSet(SettingsGui)
     return false
 try return IsGuiVisible(SettingsGui)
     && WinActive("ahk_id " SettingsGui.Hwnd)
 return false
}

SettingsEditorGetActiveCategory() {
 global SettingsGui, SettingsEditorCategories
 if !IsSet(SettingsGui)
     return ""
 categoryIndex := ClampInt(SettingsGui["settingsCategoryList"].Value, 1, SettingsEditorCategories.Length)
 return SettingsEditorCategories[categoryIndex]
}

SettingsEditorGetControllerFocusList() {
 global SettingsEditorCategoryControls, SettingsEditorFooterControls
 focusControls := []
 category := SettingsEditorGetActiveCategory()
 if (category != "" && SettingsEditorCategoryControls.Has(category)) {
     for _, ctrl in SettingsEditorCategoryControls[category] {
         if !DllCall("User32\IsWindowEnabled", "Ptr", ctrl.Hwnd, "Int")
             continue
         controlClass := ""
         try controlClass := WinGetClass("ahk_id " ctrl.Hwnd)
         if (controlClass = "Button"
             || controlClass = "Edit"
             || controlClass = "ComboBox"
             || controlClass = "SysListView32")
             focusControls.Push(ctrl)
     }
 }
 for _, ctrl in SettingsEditorFooterControls
     focusControls.Push(ctrl)
 return focusControls
}

SettingsEditorGetFocusedControllerControl() {
 focusHwnd := DllCall("User32\GetFocus", "Ptr")
 if (!focusHwnd)
     return 0
 for _, ctrl in SettingsEditorGetControllerFocusList() {
     if (ctrl.Hwnd = focusHwnd)
         return ctrl
 }
 return 0
}

SettingsEditorMoveControllerFocus(direction) {
 controls := SettingsEditorGetControllerFocusList()
 if (controls.Length = 0)
     return
 focusHwnd := DllCall("User32\GetFocus", "Ptr")
 currentIndex := 0
 for index, ctrl in controls {
     if (ctrl.Hwnd = focusHwnd) {
         currentIndex := index
         break
     }
 }
 if (!currentIndex)
     nextIndex := direction > 0 ? 1 : controls.Length
 else {
     nextIndex := currentIndex + direction
     if (nextIndex < 1)
         nextIndex := controls.Length
     else if (nextIndex > controls.Length)
         nextIndex := 1
 }
 targetCtrl := controls[nextIndex]
 SettingsEditorRevealControl(targetCtrl)
 try targetCtrl.Visible := true
 try targetCtrl.Focus()
}

SettingsEditorSwitchControllerCategory(direction) {
 global SettingsGui, SettingsEditorCategories
 if !IsSet(SettingsGui)
     return
 currentIndex := ClampInt(SettingsGui["settingsCategoryList"].Value, 1, SettingsEditorCategories.Length)
 nextIndex := currentIndex + direction
 if (nextIndex < 1)
     nextIndex := SettingsEditorCategories.Length
 else if (nextIndex > SettingsEditorCategories.Length)
     nextIndex := 1
 SettingsEditorShowCategory(nextIndex)
 SettingsEditorMoveControllerFocus(1)
}

SettingsEditorFindFieldByControl(ctrl) {
 global SettingsEditorFields
 if !IsObject(ctrl)
     return 0
 for _, field in SettingsEditorFields {
     if (field["ctrl"].Hwnd = ctrl.Hwnd)
         return field
 }
 return 0
}

SettingsEditorAdjustFocusedControl(direction) {
 ctrl := SettingsEditorGetFocusedControllerControl()
 if !IsObject(ctrl)
     return
 controlClass := ""
 try controlClass := WinGetClass("ahk_id " ctrl.Hwnd)

 if (controlClass = "SysListView32") {
     SettingsEditorMoveControllerFocus(direction)
     return
 }

 field := SettingsEditorFindFieldByControl(ctrl)
 if !IsObject(field)
     return
 fieldType := field["type"]
 if (fieldType = "choice" || fieldType = "mapped-choice") {
     choices := field["choices"]
     nextIndex := ClampInt(ctrl.Value + direction, 1, choices.Length)
     if (nextIndex != ctrl.Value) {
         ctrl.Choose(nextIndex)
         SettingsEditorMarkDirty()
     }
     return
 }
 if (fieldType != "integer" && fieldType != "float" && fieldType != "percent")
     return

 currentValue := Trim(ctrl.Value)
 if (fieldType = "integer" && !RegExMatch(currentValue, "^-?\d+$"))
     return
 if ((fieldType = "float" || fieldType = "percent")
     && !RegExMatch(currentValue, "^-?(?:\d+(?:\.\d*)?|\.\d+)$"))
     return
 step := 1
 if (fieldType = "float")
     step := 0.05
 else if (fieldType = "percent")
     step := 5
 else if InStr(StrLower(field["label"]), "(ms)") {
     valueSpan := (field["min"] != "" && field["max"] != "")
         ? field["max"] - field["min"] : 0
     if (valueSpan <= 500)
         step := 5
     else if (valueSpan <= 5000)
         step := 50
     else if (valueSpan <= 60000)
         step := 100
     else
         step := 1000
 }
 else if (field["key"] = "ControllerMouseSpeed")
     step := 5
 newValue := (currentValue + 0) + (direction * step)
 if (field["min"] != "")
     newValue := Max(newValue, field["min"])
 if (field["max"] != "")
     newValue := Min(newValue, field["max"])
 if (fieldType = "float" || fieldType = "percent")
     newValue := FormatSettingsFloat(Round(newValue, 2), 2)
 else
     newValue := Round(newValue)
 ctrl.Value := newValue
 SettingsEditorMarkDirty()
}

SettingsEditorActivateFocusedControl() {
 global SettingsEditorStatusCtrl
 ctrl := SettingsEditorGetFocusedControllerControl()
 if !IsObject(ctrl) {
     SettingsEditorMoveControllerFocus(1)
     return
 }
 controlClass := ""
 try controlClass := WinGetClass("ahk_id " ctrl.Hwnd)
 if (controlClass = "Button") {
     try SendInput("{Space}")
     return
 }
 if (controlClass = "ComboBox") {
     try SendInput("{F4}")
     return
 }
 if (controlClass = "Edit") {
     if IsObject(SettingsEditorStatusCtrl)
         SettingsEditorStatusCtrl.Text := "Windows keyboard opened for the selected field"
     OpenTouchKeyboard()
     return
 }
 if (controlClass = "SysListView32")
     SettingsEditorMoveControllerFocus(1)
}

SettingsEditorComboIsOpen(ctrl) {
 if !IsObject(ctrl)
     return false
 controlClass := ""
 try controlClass := WinGetClass("ahk_id " ctrl.Hwnd)
 if (controlClass != "ComboBox")
     return false
 try return SendMessage(0x157, 0, 0, ctrl) != 0 ; CB_GETDROPPEDSTATE
 return false
}

SettingsEditorHandlePointer(pressed, rx := 0, ry := 0) {
 global ControllerMouseSpeed
 if (rx != 0 || ry != 0) {
     speed := ControllerMouseSpeed
     dx := Round((rx / 32767.0) * speed)
     dy := Round((-ry / 32767.0) * speed)
     if (dx != 0 || dy != 0)
         try MouseMove(dx, dy, 0, "R")
 }

 ; RB uses its configured short action inside Settings (Left Click by
 ; default), allowing the right-stick pointer to operate every control.
 if (pressed & 0x0200) {
     ExecuteControllerBinding("RB.Short")
     return true
 }
 return false
}

SettingsEditorHandleController(pressed, lx := 0, ly := 0, rx := 0, ry := 0, settingsCategoryDirection := 0) {
 global SettingsEditorDirty, SettingsEditorStatusCtrl, SettingsEditorDialogActive
 static stickDir := ""
 static lastStickTick := 0

 ; Settings and every window opened from it retain automatic right-stick mouse
 ; movement and the configured RB pointer action.
 if SettingsEditorHandlePointer(pressed, rx, ry)
     return

 newDir := ""
 if (Abs(ly) > 18000)
     newDir := ly > 0 ? "UP" : "DOWN"
 else if (Abs(lx) > 18000)
     newDir := lx > 0 ? "RIGHT" : "LEFT"
 if (newDir = "")
     stickDir := ""
 else if (newDir != stickDir || A_TickCount - lastStickTick >= 280) {
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

 if (SettingsEditorDialogActive) {
     if (pressed & 0x0001) {
         try SendInput("{Left}")
         return
     }
     if (pressed & 0x0002) {
         try SendInput("{Right}")
         return
     }
     if (pressed & 0x0004) {
         try SendInput("{Left}")
         return
     }
     if (pressed & 0x0008) {
         try SendInput("{Right}")
         return
     }
     if (pressed & 0x1000) {
         try SendInput("{Enter}")
         return
     }
     if (pressed & 0x2000) {
         try SendInput("{Esc}")
         return
     }
     return
 }

 if (settingsCategoryDirection != 0) {
     SettingsEditorSwitchControllerCategory(settingsCategoryDirection)
     return
 }

 focusedCtrl := SettingsEditorGetFocusedControllerControl()
 if SettingsEditorComboIsOpen(focusedCtrl) {
     if (pressed & 0x0001) {
         try SendInput("{Up}")
         return
     }
     if (pressed & 0x0002) {
         try SendInput("{Down}")
         return
     }
     if (pressed & 0x1000) {
         try SendInput("{F4}")
         return
     }
     if (pressed & 0x2000) {
         try SendInput("{Esc}")
         return
     }
     return
 }

 focusedClass := ""
 if IsObject(focusedCtrl)
     try focusedClass := WinGetClass("ahk_id " focusedCtrl.Hwnd)
 if (focusedClass = "SysListView32") {
     if (pressed & 0x0001) {
         try SendInput("{Up}")
         return
     }
     if (pressed & 0x0002) {
         try SendInput("{Down}")
         return
     }
 }

 if (pressed & 0x0001) {
     SettingsEditorMoveControllerFocus(-1)
     return
 }
 if (pressed & 0x0002) {
     SettingsEditorMoveControllerFocus(1)
     return
 }
 if (pressed & 0x0004) {
     SettingsEditorAdjustFocusedControl(-1)
     return
 }
 if (pressed & 0x0008) {
     SettingsEditorAdjustFocusedControl(1)
     return
 }
 if (pressed & 0x1000) {
     SettingsEditorActivateFocusedControl()
     return
 }
 if (pressed & 0x8000) { ; Y
     SettingsEditorSave()
     return
 }
 if (pressed & 0x2000) { ; B
     if (SettingsEditorDirty) {
         if IsObject(SettingsEditorStatusCtrl)
             SettingsEditorStatusCtrl.Text := "Unsaved changes — press Y to save, or use Close to discard"
         return
     }
     SettingsEditorClose()
 }
}

SettingsEditorFindField(section, key) {
 global SettingsEditorFields
 for _, field in SettingsEditorFields {
     if (field["section"] = section && field["key"] = key)
         return field
 }
 return 0
}

SettingsEditorStartupSelectionChanged(listView, rowNumber, selected) {
 global SettingsStartupSelectedSlot, SettingsStartupCommandEdit, SettingsEditorUpdating
 if (!selected || rowNumber < 1)
     return

 if (SettingsStartupSelectedSlot >= 1 && IsObject(SettingsStartupCommandEdit)) {
     currentEdit := Trim(SettingsStartupCommandEdit.Value)
     currentStored := listView.GetText(SettingsStartupSelectedSlot, 2)
     if (currentEdit != currentStored) {
         listView.Modify(SettingsStartupSelectedSlot, "", SettingsStartupSelectedSlot, currentEdit)
         SettingsEditorMarkDirty()
     }
 }

 SettingsStartupSelectedSlot := rowNumber
 if IsObject(SettingsStartupCommandEdit) {
     SettingsEditorUpdating := true
     SettingsStartupCommandEdit.Value := listView.GetText(rowNumber, 2)
     SettingsEditorUpdating := false
 }
}

SettingsEditorSetStartupCommand(*) {
 global SettingsStartupListView, SettingsStartupCommandEdit, SettingsStartupSelectedSlot
 if (!IsObject(SettingsStartupListView) || !IsObject(SettingsStartupCommandEdit))
     return
 commandLine := Trim(SettingsStartupCommandEdit.Value)
 if (SettingsStartupListView.GetText(SettingsStartupSelectedSlot, 2) = commandLine)
     return
 SettingsStartupListView.Modify(SettingsStartupSelectedSlot, "", SettingsStartupSelectedSlot, commandLine)
 SettingsEditorMarkDirty()
}

SettingsEditorClearStartupCommand(*) {
 global SettingsStartupCommandEdit, SettingsEditorStatusCtrl, SettingsStartupSelectedSlot
 if IsObject(SettingsStartupCommandEdit)
     SettingsStartupCommandEdit.Value := ""
 SettingsEditorSetStartupCommand()
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Removed startup program from slot " SettingsStartupSelectedSlot
}

SettingsEditorAddStartupProgram(*) {
 global SettingsStartupListView, SettingsStartupCommandEdit, SettingsStartupSelectedSlot
 global SettingsEditorUpdating, SettingsEditorStatusCtrl
 if (!IsObject(SettingsStartupListView) || !IsObject(SettingsStartupCommandEdit))
     return

 startDir := A_ScriptDir
 currentCommand := SettingsStartupListView.GetText(SettingsStartupSelectedSlot, 2)
 currentTarget := ""
 currentParams := ""
 SplitTargetAndParams(currentCommand, &currentTarget, &currentParams)
 if (currentTarget != "") {
     fileName := ""
     candidateDir := ""
     try SplitPath(currentTarget, &fileName, &candidateDir)
     if (candidateDir != "" && DirExist(candidateDir))
         startDir := candidateDir
 }

 selectedPath := SettingsEditorFileSelect(
     1, startDir, "Add a startup program", "Programs (*.exe)")
 if (selectedPath = "")
     return

 targetSlot := 0
 if (Trim(SettingsStartupListView.GetText(SettingsStartupSelectedSlot, 2)) = "")
     targetSlot := SettingsStartupSelectedSlot
 else {
     Loop SettingsStartupListView.GetCount() {
         if (Trim(SettingsStartupListView.GetText(A_Index, 2)) = "") {
             targetSlot := A_Index
             break
         }
     }
 }
 if (!targetSlot) {
     SettingsEditorMsgBox(
         "All 20 startup-program slots are already in use. Remove a program before adding another.", "Icon!")
     return
 }

 commandLine := '"' selectedPath '"'
 SettingsStartupListView.Modify(targetSlot, "", targetSlot, commandLine)
 SettingsStartupSelectedSlot := targetSlot
 SettingsEditorUpdating := true
 SettingsStartupCommandEdit.Value := commandLine
 SettingsEditorUpdating := false
 SettingsStartupListView.Modify(targetSlot, "Select Focus Vis")
 SettingsEditorMarkDirty()
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Added startup program to slot " targetSlot
}

SettingsEditorBrowseStartupProgram(*) {
 global SettingsStartupCommandEdit, SettingsEditorStatusCtrl, SettingsStartupSelectedSlot
 currentCommand := SettingsStartupCommandEdit.Value
 currentTarget := ""
 currentParams := ""
 SplitTargetAndParams(currentCommand, &currentTarget, &currentParams)

 startDir := A_ScriptDir
 if (currentTarget != "") {
     fileName := ""
     candidateDir := ""
     try SplitPath(currentTarget, &fileName, &candidateDir)
     if (candidateDir != "" && DirExist(candidateDir))
         startDir := candidateDir
 }

 selectedPath := SettingsEditorFileSelect(
     1, startDir, "Select a startup program", "Programs (*.exe)")
 if (selectedPath = "")
     return
 commandLine := '"' selectedPath '"'
 if (currentParams != "")
     commandLine .= " " currentParams
 SettingsStartupCommandEdit.Value := commandLine
 SettingsEditorSetStartupCommand()
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Updated startup program in slot " SettingsStartupSelectedSlot
}

SettingsEditorMoveStartupProgram(direction, *) {
 global SettingsStartupListView, SettingsStartupCommandEdit, SettingsStartupSelectedSlot
 global SettingsEditorUpdating, SettingsEditorStatusCtrl
 SettingsEditorSetStartupCommand()
 if !IsObject(SettingsStartupListView)
     return
 targetSlot := SettingsStartupSelectedSlot + direction
 if (targetSlot < 1 || targetSlot > SettingsStartupListView.GetCount())
     return
 currentCommand := SettingsStartupListView.GetText(SettingsStartupSelectedSlot, 2)
 targetCommand := SettingsStartupListView.GetText(targetSlot, 2)
 SettingsStartupListView.Modify(
     SettingsStartupSelectedSlot, "", SettingsStartupSelectedSlot, targetCommand)
 SettingsStartupListView.Modify(targetSlot, "Select Focus Vis", targetSlot, currentCommand)
 SettingsStartupSelectedSlot := targetSlot
 SettingsEditorUpdating := true
 SettingsStartupCommandEdit.Value := currentCommand
 SettingsEditorUpdating := false
 SettingsEditorMarkDirty()
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Moved startup command to slot " targetSlot
}

SettingsEditorTestStartupProgram(*) {
 global SettingsStartupListView, SettingsStartupSelectedSlot, SettingsEditorStatusCtrl
 SettingsEditorSetStartupCommand()
 if !IsObject(SettingsStartupListView)
     return
 commandLine := Trim(SettingsStartupListView.GetText(SettingsStartupSelectedSlot, 2))
 if (commandLine = "") {
     if IsObject(SettingsEditorStatusCtrl)
         SettingsEditorStatusCtrl.Text := "The selected startup slot is empty"
     return
 }
 SplitTargetAndParams(commandLine, &target, &params)
 if (target = "" || !FileExist(target)) {
     SettingsEditorMsgBox("The selected startup executable could not be found.", "Icon!")
     return
 }
 if RunStartupCommandLine(commandLine, "Normal")
     SettingsEditorStatusCtrl.Text := "Test-launched startup slot " SettingsStartupSelectedSlot
 else
     SettingsEditorMsgBox("Windows could not test-launch the selected startup command.", "Iconx")
}

SettingsEditorValidateField(field, &value, &message) {
 ctrl := field["ctrl"]
 fieldType := field["type"]
 value := ""
 message := ""

 if (fieldType = "bool") {
     value := ctrl.Value = 1 ? "true" : "false"
     return true
 }
 if (fieldType = "choice") {
     value := ctrl.Text
     return value != ""
 }
 if (fieldType = "mapped-choice") {
     selectedIndex := ctrl.Value
     if (selectedIndex < 1 || selectedIndex > field["values"].Length) {
         message := field["label"] " has no selected value."
         return false
     }
     value := field["values"][selectedIndex]
     return true
 }
 if (fieldType = "exe-list") {
     executables := []
     Loop ctrl.GetCount() {
         exe := Trim(ctrl.GetText(A_Index, 1))
         if !RegExMatch(exe, "i)^[a-z0-9][a-z0-9_. -]*\.exe$") {
             message := field["label"] " contains an invalid executable filename: " exe
             return false
         }
         executables.Push(exe)
     }
     value := JoinPipe(executables)
     return true
 }

 value := Trim(ctrl.Value)
 if (fieldType = "integer") {
     if !RegExMatch(value, "^-?\d+$") {
         message := field["label"] " must be a whole number."
         return false
     }
     number := value + 0
     if (field["min"] != "" && number < field["min"]) {
         message := field["label"] " must be at least " field["min"] "."
         return false
     }
     if (field["max"] != "" && number > field["max"]) {
         message := field["label"] " must be no greater than " field["max"] "."
         return false
     }
     value := number
 }
 if (fieldType = "float") {
     if !RegExMatch(value, "^-?(?:\d+(?:\.\d*)?|\.\d+)$") {
         message := field["label"] " must be a number."
         return false
     }
     number := value + 0.0
     if (field["min"] != "" && number < field["min"]) {
         message := field["label"] " must be at least " field["min"] "."
         return false
     }
     if (field["max"] != "" && number > field["max"]) {
         message := field["label"] " must be no greater than " field["max"] "."
         return false
     }
     value := FormatSettingsFloat(number)
 }
 if (fieldType = "percent") {
     if !RegExMatch(value, "^-?(?:\d+(?:\.\d*)?|\.\d+)$") {
         message := field["label"] " must be a percentage."
         return false
     }
     number := value + 0.0
     if (field["min"] != "" && number < field["min"]) {
         message := field["label"] " must be at least " field["min"] "%."
         return false
     }
     if (field["max"] != "" && number > field["max"]) {
         message := field["label"] " must be no greater than " field["max"] "%."
         return false
     }
     value := FormatSettingsFloat(number / 100)
 }
 return true
}

SettingsEditorSave(*) {
 global SettingsPath, ScriptPid, SettingsEditorFields, SettingsEditorCategories
 global SettingsEditorDirty, SettingsEditorStatusCtrl, SettingsStartupListView
 SettingsEditorSetStartupCommand()
 pendingWrites := []
 for _, field in SettingsEditorFields {
     if !SettingsEditorValidateField(field, &value, &message) {
         for index, category in SettingsEditorCategories {
             if (category = field["category"]) {
                 SettingsEditorShowCategory(index)
                 break
             }
         }
         SettingsEditorRevealControl(field["ctrl"])
         try field["ctrl"].Focus()
         SettingsEditorMsgBox(message, "Icon!")
         return false
     }
     pendingWrites.Push(Map(
         "section", field["section"], "key", field["key"], "value", value))
 }

 workPath := SettingsPath ".save-" ScriptPid ".tmp"
 try {
     if FileExist(workPath)
         FileDelete(workPath)
     FileCopy(SettingsPath, workPath, true)
     for _, item in pendingWrites
         IniWrite(item["value"], workPath, item["section"], item["key"])
     if IsObject(SettingsStartupListView) {
         Loop 20 {
             commandLine := SettingsStartupListView.GetText(A_Index, 2)
             IniWrite(commandLine, workPath, "StartupPrograms", "Program" A_Index)
         }
     }
     FileMove(workPath, SettingsPath, true)
 } catch as err {
     try {
         if FileExist(workPath)
             FileDelete(workPath)
     }
     SettingsEditorMsgBox(
         "SteamShell could not save the settings file.`n`n" err.Message, "Iconx")
     return false
 }

 ReloadSettings()
 SettingsEditorDirty := false
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Saved and applied. Startup-only changes apply next launch."
 return true
}

SettingsEditorReloadFromIni(*) {
 global SettingsEditorDirty, SettingsGui
 if (SettingsEditorDirty) {
     result := SettingsEditorMsgBox(
         "Discard unsaved changes and reload the INI?", "YesNo Icon?")
     if (result != "Yes")
         return
 }
 try SettingsGui.Destroy()
 SettingsGui := unset
 ReloadSettings()
 ShowSettingsEditor()
}

SettingsEditorClose(*) {
 global SettingsEditorDirty, SettingsGui, LastRealFgHwnd
 if (SettingsEditorDirty) {
     result := SettingsEditorMsgBox(
         "Save your settings before closing?", "YesNoCancel Icon?")
     if (result = "Cancel")
         return
     if (result = "Yes" && !SettingsEditorSave())
         return
 }
 SettingsEditorDirty := false
 try SettingsGui.Destroy()
 SettingsGui := unset
 ApplyRuntimeTimers()
 if (LastRealFgHwnd && DllCall("IsWindow", "Ptr", LastRealFgHwnd)) {
     if ActivateWindowRobust(LastRealFgHwnd)
         HandleCursorAfterManagedFocus(LastRealFgHwnd, false)
 }
}

SettingsEditorOpenIni(*) {
 global SettingsPath, SettingsGui
 if IsSet(SettingsGui)
     try WinSetAlwaysOnTop(0, "ahk_id " SettingsGui.Hwnd)
 try Run("notepad.exe " Chr(34) SettingsPath Chr(34))
}

SettingsEditorOpenRtss(*) {
 field := SettingsEditorFindField("RTSS", "Path")
 path := IsObject(field) ? NormalizeMediaPath(field["ctrl"].Value) : ""
 if (path = "" || !FileExist(path)) {
     SettingsEditorMsgBox("Select a valid RTSS.exe path first.", "Icon!")
     return
 }
 try Run(Chr(34) path Chr(34))
}

SettingsEditorToggleFocusPause(*) {
 global FocusAssistancePaused, SettingsEditorStatusCtrl
 FocusAssistancePaused := !FocusAssistancePaused
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := FocusAssistancePaused ? "Session focus assistance paused" : "Session focus assistance active"
}

SettingsEditorRunGameAssist(*) {
 global SettingsEditorStatusCtrl
 ForceGameAssistOnce()
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Game Foreground Assist requested"
}

SettingsEditorReloadRuntime(*) {
 global SettingsEditorStatusCtrl
 ReloadSettings()
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Runtime settings reloaded from the INI"
}

CreateSettingsBackup(reason := "manual") {
 global SettingsPath
 if !FileExist(SettingsPath)
     return ""
 SplitPath(SettingsPath, &settingsName, &settingsDir, &settingsExt, &settingsStem)
 safeReason := RegExReplace(StrLower(reason), "[^a-z0-9_-]+", "-")
 backupPath := settingsDir "\" settingsStem ".backup-"
     . FormatTime(A_Now, "yyyyMMdd-HHmmss") "-" safeReason ".ini"
 if FileExist(backupPath)
     backupPath := settingsDir "\" settingsStem ".backup-"
         . FormatTime(A_Now, "yyyyMMdd-HHmmss") "-" safeReason "-" A_TickCount ".ini"
 try {
     FileCopy(SettingsPath, backupPath, false)
     return FileExist(backupPath) ? backupPath : ""
 } catch {
     return ""
 }
}

SettingsEditorReloadAfterFileChange() {
 global SettingsGui, SettingsEditorDirty
 SettingsEditorDirty := false
 try SettingsGui.Destroy()
 SettingsGui := unset
 EnsureSettingsIniUnicode()
 SyncSettingsIniSchema()
 ReloadSettings()
 ShowSettingsEditor()
}

SettingsEditorCreateBackup(*) {
 global SettingsEditorStatusCtrl
 backupPath := CreateSettingsBackup("manual")
 if (backupPath = "") {
     SettingsEditorMsgBox("SteamShell could not create a settings backup.", "Iconx")
     return
 }
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Backup created: " backupPath
 SettingsEditorMsgBox("Settings backup created:`n`n" backupPath, "Iconi")
}

SettingsEditorExportSettings(*) {
 global SettingsPath, SettingsEditorStatusCtrl
 exportPath := SettingsEditorFileSelect(
     "S16", A_Desktop, "Export SteamShell settings", "INI Files (*.ini)")
 if (exportPath = "")
     return
 if !RegExMatch(exportPath, "i)\.ini$")
     exportPath .= ".ini"
 try {
     FileCopy(SettingsPath, exportPath, true)
 } catch as err {
     SettingsEditorMsgBox("Settings export failed.`n`n" err.Message, "Iconx")
     return
 }
 if IsObject(SettingsEditorStatusCtrl)
     SettingsEditorStatusCtrl.Text := "Settings exported to " exportPath
}

SettingsFileLooksValid(path, &reason) {
 reason := ""
 if (path = "" || !FileExist(path)) {
     reason := "The selected settings file does not exist."
     return false
 }
 try contents := FileRead(path)
 catch as err {
     reason := "The selected file could not be read: " err.Message
     return false
 }
 if !RegExMatch(contents, "im)^\s*\[(SteamShell|Paths|Features)\]\s*$") {
     reason := "The selected file does not appear to be a SteamShell settings file."
     return false
 }
 return true
}

SettingsEditorImportSettings(*) {
 global SettingsPath, ScriptPid
 importPath := SettingsEditorFileSelect(
     1, A_Desktop, "Import or restore SteamShell settings", "INI Files (*.ini)")
 if (importPath = "")
     return
 if !SettingsFileLooksValid(importPath, &validationError) {
     SettingsEditorMsgBox(validationError, "Iconx")
     return
 }
 result := SettingsEditorMsgBox(
     "Replace the current settings with the selected file?`n`n"
     . "SteamShell will create a backup first.", "YesNo Icon?")
 if (result != "Yes")
     return
 backupPath := CreateSettingsBackup("before-import")
 if (backupPath = "") {
     SettingsEditorMsgBox(
         "A safety backup could not be created, so the import was cancelled.", "Iconx")
     return
 }
 workPath := SettingsPath ".import-" ScriptPid ".tmp"
 try {
     if FileExist(workPath)
         FileDelete(workPath)
     FileCopy(importPath, workPath, true)
     FileMove(workPath, SettingsPath, true)
 } catch as err {
     try {
         if FileExist(workPath)
             FileDelete(workPath)
     }
     SettingsEditorMsgBox(
         "Settings import failed. The previous settings remain in:`n"
         . backupPath "`n`n" err.Message, "Iconx")
     return
 }
 SettingsEditorReloadAfterFileChange()
}

SettingsEditorResetCategory(*) {
 global SettingsEditorFields, SettingsStartupListView
 category := SettingsEditorGetActiveCategory()
 if (category = "")
     return
 result := SettingsEditorMsgBox(
     "Reset every setting shown in " category " to its built-in default?`n`n"
     . "A backup will be created first.", "YesNo Icon?")
 if (result != "Yes")
     return

 defaults := Map()
 for _, option in GetDefaultSettingsSchema()
     defaults[option["section"] Chr(31) option["key"]] := option["value"]
 changes := []
 for _, field in SettingsEditorFields {
     if (field["category"] != category)
         continue
     lookupKey := field["section"] Chr(31) field["key"]
     if defaults.Has(lookupKey) {
         changes.Push(Map(
             "section", field["section"], "key", field["key"],
             "value", defaults[lookupKey]))
     }
 }
 if (category = "Startup Programs") {
     Loop 20 {
         key := "Program" A_Index
         lookupKey := "StartupPrograms" Chr(31) key
         changes.Push(Map(
             "section", "StartupPrograms", "key", key,
             "value", defaults.Has(lookupKey) ? defaults[lookupKey] : ""))
     }
 }
 if (category = "General") {
     for _, key in ["MainOrder", "HiddenItems"] {
         lookupKey := "QuickMenu" Chr(31) key
         if defaults.Has(lookupKey) {
             changes.Push(Map(
                 "section", "QuickMenu", "key", key,
                 "value", defaults[lookupKey]))
         }
     }
 }
 if (changes.Length = 0) {
     SettingsEditorMsgBox("This category has no resettable settings.", "Icon!")
     return
 }
 if (CreateSettingsBackup("before-category-reset") = "") {
     SettingsEditorMsgBox("A safety backup could not be created. Reset cancelled.", "Iconx")
     return
 }
 if !CommitIniChanges(changes) {
     SettingsEditorMsgBox("SteamShell could not reset this category.", "Iconx")
     return
 }
 SettingsEditorReloadAfterFileChange()
}

SettingsEditorResetAll(*) {
 global SettingsPath, ScriptPid
 result := SettingsEditorMsgBox(
     "Reset every SteamShell setting to its built-in default?`n`n"
     . "Your current INI will be backed up first.", "YesNo Icon?")
 if (result != "Yes")
     return
 backupPath := CreateSettingsBackup("before-full-reset")
 if (backupPath = "") {
     SettingsEditorMsgBox("A safety backup could not be created. Reset cancelled.", "Iconx")
     return
 }
 workPath := SettingsPath ".reset-" ScriptPid ".tmp"
 try {
     if FileExist(workPath)
         FileDelete(workPath)
     FileAppend(GetDefaultSettingsIniText(), workPath, "UTF-16")
     FileMove(workPath, SettingsPath, true)
 } catch as err {
     try {
         if FileExist(workPath)
             FileDelete(workPath)
     }
     SettingsEditorMsgBox(
         "The reset failed. Your previous settings remain in:`n"
         . backupPath "`n`n" err.Message, "Iconx")
     return
 }
 SettingsEditorReloadAfterFileChange()
}

HealthResult(results, status, checkName, detail) {
 results.Push(Map(
     "status", StrUpper(status),
     "name", checkName,
     "detail", detail))
}

GetSteamShellHealthResults() {
 global SteamPath, SettingsPath, CurrentSettingsSchemaVersion
 global ShellRegKey, SteamShellInstalledExe, SteamShellVersion
 global EnableRTSSIntegration, RtssPath, RtssOverlayControlMode
 global RtssOverlayToggleShortcut, RtssOverlayOnShortcut, RtssOverlayOffShortcut
 global RtssFrameLimiterControlMode, RtssCustomFrameCapShortcut
 global RtssFrameLimiterOnShortcut, RtssFrameLimiterOffShortcut
 global EnableLauncherCleanup, LauncherCleanupHardKill
 global LauncherCleanupLauncherExeListRaw, LauncherCleanupExcludeExeListRaw
 global LauncherCleanupBackgroundExeListRaw, ControllerIndex, SafeMode, SessionState
 global ControllerMap
 global WindowEngineTickIntervalMs, WindowEngineFocusIntervalMs
 global WindowEngineLastWindowCount, WindowEngineLastTickDurationMs
 global WindowEngineLastSnapshotTick, WindowEngineLastDecision
 global EnableTaskbarHiding, TaskbarGuardActive, TaskbarGuardHook
 global EnableDesktopBlackout, DesktopBlackoutActive, DesktopBlackoutHook
 global DesktopBackdropHwnd
 global EnableMouseParkOnFocusChange, MouseParkLastResult
 global RunElevatedOnStartup, DesktopMode

 results := []
 HealthResult(results, "info", "Session state", SessionState)
 HealthResult(results, "info", "Presentation mode",
     DesktopMode
         ? "Desktop mode: Explorer owns the desktop and SteamShell is resident for the notification area, controller mouse, and Quick Menu."
         : (SafeMode
             ? "Safe Mode: shell enforcement and automation are disabled for this session."
             : "Shell mode: SteamShell owns presentation and the taskbar is guarded."))
 HealthResult(results, A_IsAdmin ? "pass" : "warn", "Runtime privileges",
     A_IsAdmin
         ? "SteamShell is running with administrator privileges."
         : (RunElevatedOnStartup
             ? "SteamShell is not elevated; the administrator handoff may have been cancelled or unavailable."
             : "Administrator startup is disabled; Windows may block controller mouse control of elevated applications."))
 steamExe := NormalizeMediaPath(SteamPath)
 HealthResult(results, FileExist(steamExe) ? "pass" : "fail", "Steam executable",
     FileExist(steamExe) ? steamExe : "Not found: " steamExe)

 if !FileExist(SettingsPath) {
     HealthResult(results, "fail", "Settings file", "SteamShellSettings.ini is missing.")
 } else {
     attributes := ""
     try attributes := FileGetAttrib(SettingsPath)
     HealthResult(results, InStr(attributes, "R") ? "warn" : "pass", "Settings file",
         InStr(attributes, "R") ? "The INI is read-only." : SettingsPath)
 }

 schemaVersion := ToInt(IniReadS("SteamShell", "SettingsSchemaVersion", "0"), 0)
 HealthResult(results,
     schemaVersion = CurrentSettingsSchemaVersion ? "pass" : "warn",
     "Settings schema",
     "File: " schemaVersion "  Built-in: " CurrentSettingsSchemaVersion)

 currentShell := ""
 try currentShell := RegRead(ShellRegKey, "Shell")
 shellLower := StrLower(Trim(currentShell))
 shellStatus := InStr(shellLower, "steamshell") || shellLower = "explorer.exe" ? "pass" : "warn"
 HealthResult(results, shellStatus, "Windows shell registration",
     currentShell = "" ? "No per-user shell value was found." : currentShell)

 if (StrLower(A_ScriptFullPath) = StrLower(SteamShellInstalledExe))
     installDetail := "Running from the installed per-user location."
 else if A_IsCompiled
     installDetail := "Running as a portable compiled EXE."
 else
     installDetail := "Running the uncompiled AutoHotkey script."
 HealthResult(results, "info", "Runtime mode", installDetail)

 engineStatus := WindowEngineLastSnapshotTick = 0
     ? "info"
     : (WindowEngineLastTickDurationMs <= WindowEngineTickIntervalMs ? "pass" : "warn")
 HealthResult(results, engineStatus, "Coordinated window engine",
     "Tick " WindowEngineTickIntervalMs "ms; focus " WindowEngineFocusIntervalMs
     "ms; last scan " WindowEngineLastWindowCount " windows in "
     WindowEngineLastTickDurationMs "ms; " WindowEngineLastDecision)

 inputIdleMs := GetWindowsInputIdleMs()
 HealthResult(results, inputIdleMs >= 0 ? "info" : "warn", "Windows input idle clock",
     inputIdleMs >= 0
         ? "Last input event was " Round(inputIdleMs / 1000) " seconds ago. "
             . "Cursor parking uses SetCursorPos and does not inject mouse input."
         : "Windows did not return its last-input timestamp.")
 HealthResult(results, "info", "Mouse parking",
     EnableMouseParkOnFocusChange
         ? MouseParkLastResult ". Foreground transitions use a one-shot settle and verification."
         : "Parking after focus changes is disabled.")

 taskbarHwnd := DllCall("User32\FindWindowW", "WStr", "Shell_TrayWnd", "Ptr", 0, "Ptr")
 taskbarVisible := false
 if (taskbarHwnd)
     taskbarVisible := DllCall(
         "User32\IsWindowVisible", "Ptr", taskbarHwnd, "Int") != 0
 HealthResult(results, ProcessExist("explorer.exe") ? "pass" : "warn", "Explorer process",
     ProcessExist("explorer.exe") ? "explorer.exe is running." : "explorer.exe is not running.")
 if (EnableTaskbarHiding) {
     guardStatus := TaskbarGuardActive && taskbarHwnd && !taskbarVisible
         ? "pass" : "warn"
     guardMode := TaskbarGuardHook
         ? "event hook + periodic safety"
         : "periodic safety only"
     HealthResult(results, guardStatus, "Taskbar Guard",
         "Active: " (TaskbarGuardActive ? "yes" : "no")
         "; primary taskbar: "
         (taskbarHwnd ? (taskbarVisible ? "visible" : "hidden") : "not found")
         "; mode: " guardMode ".")
 } else {
     HealthResult(results, "info", "Taskbar Guard",
         "Taskbar hiding is disabled; primary taskbar is "
         (taskbarHwnd ? (taskbarVisible ? "visible." : "hidden.") : "not found."))
 }

 desktopHwnd := DllCall("User32\FindWindowW", "WStr", "Progman", "Ptr", 0, "Ptr")
 desktopVisible := desktopHwnd
     && DllCall("User32\IsWindowVisible", "Ptr", desktopHwnd, "Int") != 0
 backdropAlive := DesktopBackdropHwnd
     && DllCall("User32\IsWindow", "Ptr", DesktopBackdropHwnd, "Int") != 0
 if (EnableDesktopBlackout) {
     blackoutStatus := DesktopBlackoutActive && backdropAlive && !desktopVisible
         ? "pass" : "warn"
     HealthResult(results, blackoutStatus, "Desktop blackout",
         "Active: " (DesktopBlackoutActive ? "yes" : "no")
         "; backdrop: " (backdropAlive ? "present" : "missing")
         "; desktop: " (desktopHwnd ? (desktopVisible ? "visible" : "hidden") : "not found")
         "; mode: " (DesktopBlackoutHook ? "event hook + periodic safety" : "periodic safety only") ".")
 } else {
     HealthResult(results, "info", "Desktop blackout",
         "Desktop blackout is disabled; the wallpaper and desktop icons are "
         (desktopVisible ? "visible." : "hidden."))
 }

 startupEnabled := ToBool(IniReadS("StartupPrograms", "Enable", "false"), false)
 invalidStartup := []
 configuredStartup := 0
 Loop 20 {
     commandLine := Trim(IniReadS("StartupPrograms", "Program" A_Index, ""))
     if (commandLine = "")
         continue
     configuredStartup += 1
     SplitTargetAndParams(commandLine, &target, &params)
     if (target = "" || !FileExist(target))
         invalidStartup.Push("Program" A_Index)
 }
 startupStatus := invalidStartup.Length ? "warn" : "pass"
 startupDetail := configuredStartup " configured"
     . (startupEnabled ? ", startup enabled" : ", startup disabled")
 if invalidStartup.Length
     startupDetail .= "; missing: " JoinWith(invalidStartup, ", ")
 HealthResult(results, startupStatus, "Startup programs", startupDetail)

 if EnableRTSSIntegration {
     rtssMissing := !FileExist(NormalizeMediaPath(RtssPath))
     overlayMissing := RtssOverlayControlMode = "separate"
         ? RtssOverlayOnShortcut = "" || RtssOverlayOffShortcut = ""
         : RtssOverlayToggleShortcut = ""
     limiterMissing := RtssFrameLimiterControlMode = "separate"
         ? RtssFrameLimiterOnShortcut = "" || RtssFrameLimiterOffShortcut = ""
         : RtssCustomFrameCapShortcut = ""
     HealthResult(results,
         rtssMissing || overlayMissing || limiterMissing ? "warn" : "pass",
         "RTSS integration",
         rtssMissing ? "RTSS.exe was not found."
             : (overlayMissing || limiterMissing ? "One or more required shortcuts are blank."
                 : "Executable and shortcut fields are configured."))
 } else {
     HealthResult(results, "info", "RTSS integration", "Disabled.")
 }

 state := Buffer(16, 0)
 controllerResult := XInputGetState(ControllerIndex, &state)
 HealthResult(results, controllerResult = 0 ? "pass" : "warn", "Controller",
     controllerResult = 0
         ? "XInput controller " (ControllerIndex + 1) " is connected."
         : "No controller was detected at configured index " (ControllerIndex + 1) ".")

 bindingOwners := Map()
 duplicateBindings := []
 for mappingKey, bindingValue in ControllerMap {
     normalizedBinding := StrLower(Trim(bindingValue))
     if (normalizedBinding = "" || normalizedBinding = "builtin:none")
         continue
     if bindingOwners.Has(normalizedBinding)
         duplicateBindings.Push(bindingOwners[normalizedBinding] " + " mappingKey)
     else
         bindingOwners[normalizedBinding] := mappingKey
 }
 HealthResult(results, duplicateBindings.Length ? "warn" : "pass", "Controller mappings",
     duplicateBindings.Length
         ? "Shared actions: " JoinWith(duplicateBindings, ", ")
         : "No duplicate mapped actions were found.")

 rawLauncherCount := SettingsEditorParseExeList(LauncherCleanupLauncherExeListRaw).Length
 rawBackgroundCount := SettingsEditorParseExeList(LauncherCleanupBackgroundExeListRaw).Length
 rawExcludeCount := SettingsEditorParseExeList(LauncherCleanupExcludeExeListRaw).Length
 cleanupStatus := EnableLauncherCleanup && LauncherCleanupHardKill ? "warn" : "pass"
 HealthResult(results, cleanupStatus, "Launcher Cleanup",
     (EnableLauncherCleanup ? "Enabled" : "Disabled")
     . "; " rawLauncherCount " launchers, " rawBackgroundCount " helpers, "
     . rawExcludeCount " protected EXEs"
     . (LauncherCleanupHardKill ? "; force termination enabled" : ""))

 restoreAvailable := A_IsCompiled && FileExist(A_ScriptFullPath)
 HealthResult(results, restoreAvailable ? "pass" : "info", "Desktop recovery",
     restoreAvailable
         ? A_ScriptFullPath " /restore"
         : "Compile SteamShell to enable the single-EXE /restore command.")

 if SafeMode
     HealthResult(results, "info", "Safe Mode", "Safe Mode overrides are active for this session.")
 return results
}

FormatHealthReport(results := 0) {
 global SteamShellVersion
 if !IsObject(results)
     results := GetSteamShellHealthResults()
 report := "SteamShell " SteamShellVersion " Health Check`r`n"
     . "Generated: " NowStamp() "`r`n`r`n"
 for _, item in results
     report .= "[" item["status"] "] " item["name"] "`r`n  " item["detail"] "`r`n"
 return report
}

RefreshHealthCheck(*) {
 global HealthCheckGui, HealthCheckResults
 HealthCheckResults := GetSteamShellHealthResults()
 if !IsSet(HealthCheckGui)
     return
 try {
     listView := HealthCheckGui["HealthResults"]
     listView.Delete()
     counts := Map("PASS", 0, "WARN", 0, "FAIL", 0, "INFO", 0)
     for _, item in HealthCheckResults {
         listView.Add("", item["status"], item["name"], item["detail"])
         if counts.Has(item["status"])
             counts[item["status"]] += 1
     }
     listView.ModifyCol(1, 75)
     listView.ModifyCol(2, 185)
     listView.ModifyCol(3, 555)
     HealthCheckGui["HealthSummary"].Text :=
         counts["PASS"] " passed   •   " counts["WARN"] " warnings   •   "
         . counts["FAIL"] " failed   •   " counts["INFO"] " informational"
 }
}

CopyHealthReport(*) {
 global HealthCheckResults
 A_Clipboard := FormatHealthReport(HealthCheckResults)
}

SanitizeDiagnosticText(text) {
 global SettingsPath
 userProfile := EnvGet("USERPROFILE")
 localAppData := EnvGet("LOCALAPPDATA")
 if (userProfile != "")
     text := StrReplace(text, userProfile, "%USERPROFILE%", false)
 if (localAppData != "")
     text := StrReplace(text, localAppData, "%LOCALAPPDATA%", false)
 text := StrReplace(text, A_ScriptDir, "%STEAMSHELL_DIR%", false)
 return text
}

ExportDiagnosticBundle(*) {
 global HealthCheckResults, SettingsPath, LogPath, SteamShellVersion, ShellRegKey
 global HealthCheckGui, SettingsEditorStatusCtrl
 stamp := FormatTime(A_Now, "yyyyMMdd-HHmmss")
 tempDir := A_Temp "\SteamShell-Diagnostics-" stamp
 zipPath := A_Desktop "\SteamShell-Diagnostics-" stamp ".zip"
 try {
     DirCreate(tempDir)
     results := GetSteamShellHealthResults()
     HealthCheckResults := results
     FileAppend(
         SanitizeDiagnosticText(FormatHealthReport(results)),
         tempDir "\HealthCheck.txt", "UTF-8")

     currentShell := ""
     try currentShell := RegRead(ShellRegKey, "Shell")
     systemInfo := "SteamShellVersion=" SteamShellVersion "`r`n"
         . "Generated=" NowStamp() "`r`n"
         . "OSVersion=" A_OSVersion "`r`n"
         . "Is64BitOS=" (A_Is64bitOS ? "true" : "false") "`r`n"
         . "Compiled=" (A_IsCompiled ? "true" : "false") "`r`n"
         . "ScriptPath=" A_ScriptFullPath "`r`n"
         . "CurrentShell=" currentShell "`r`n"
     FileAppend(
         SanitizeDiagnosticText(systemInfo),
         tempDir "\SystemInfo.txt", "UTF-8")

     if FileExist(SettingsPath)
         FileAppend(
             SanitizeDiagnosticText(FileRead(SettingsPath)),
             tempDir "\SteamShellSettings-sanitized.ini", "UTF-8")
     if FileExist(LogPath)
         FileAppend(
             SanitizeDiagnosticText(GetLastLines(FileRead(LogPath), 2000)),
             tempDir "\SteamShell-log-tail.txt", "UTF-8")

     psPath := StrReplace(tempDir "\*", "'", "''")
     psZip := StrReplace(zipPath, "'", "''")
     psCommand := "Compress-Archive -Path '" psPath
         . "' -DestinationPath '" psZip "' -Force"
     exitCode := RunWait(
         'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "'
         . psCommand . '"', , "Hide")
     if (exitCode != 0 || !FileExist(zipPath))
         throw Error("PowerShell could not create the ZIP archive.")
     try DirDelete(tempDir, true)
     if IsSet(HealthCheckGui)
         try HealthCheckGui["HealthSummary"].Text := "Diagnostic bundle exported to " zipPath
     if IsObject(SettingsEditorStatusCtrl)
         try SettingsEditorStatusCtrl.Text := "Diagnostic bundle exported to " zipPath
     try Run('explorer.exe /select,"' zipPath '"')
 } catch as err {
     if IsSet(HealthCheckGui) && IsGuiVisible(HealthCheckGui) {
         try MsgBox(
             "The diagnostic bundle could not be exported.`n`n" err.Message,
             "SteamShell Health Check", "Owner" HealthCheckGui.Hwnd " Iconx")
     } else {
         SettingsEditorMsgBox(
             "The diagnostic bundle could not be exported.`n`n" err.Message, "Iconx")
     }
 }
}

ShowHealthCheck(*) {
 global HealthCheckGui, SteamShellVersion
 if !IsSet(HealthCheckGui) {
     HealthCheckGui := Gui("+AlwaysOnTop +ToolWindow -Resize", "SteamShell Health Check")
     HealthCheckGui.Opt("+OwnDialogs")
     HealthCheckGui.SetFont("s10", "Segoe UI")
     title := HealthCheckGui.AddText("xm ym w850 h30", "SteamShell Health Check")
     title.SetFont("s17 Bold", "Segoe UI")
     HealthCheckGui.AddText(
         "xm y+2 w850 h36 +Wrap",
         "Read-only checks for paths, recovery, shell registration, integrations, and safety settings.")
     HealthCheckGui.AddListView(
         "xm y+8 w850 r13 -Multi vHealthResults", ["Status", "Check", "Details"])
     HealthCheckGui.AddText("xm y+8 w850 h24 vHealthSummary", "")
     refreshButton := HealthCheckGui.AddButton("xm y+8 w145 h32", "Refresh")
     refreshButton.OnEvent("Click", RefreshHealthCheck)
     copyButton := HealthCheckGui.AddButton("x+8 yp w145 h32", "Copy Report")
     copyButton.OnEvent("Click", CopyHealthReport)
     exportButton := HealthCheckGui.AddButton("x+8 yp w190 h32", "Export Diagnostic ZIP")
     exportButton.OnEvent("Click", ExportDiagnosticBundle)
     closeButton := HealthCheckGui.AddButton("x+8 yp w120 h32", "Close")
     closeButton.OnEvent("Click", (*) => HealthCheckGui.Hide())
     HealthCheckGui.OnEvent("Close", (*) => HealthCheckGui.Hide())
     HealthCheckGui.OnEvent("Escape", (*) => HealthCheckGui.Hide())
 }
 HealthCheckGui.Show()
 CenterGuiOnTargetMonitor(HealthCheckGui)
 RefreshHealthCheck()
}

SetupAssistantSetStatus(message) {
 global SetupAssistantGui
 if !IsSet(SetupAssistantGui)
     return
 try SetupAssistantGui["SetupStatus"].Text := message
}

SetupAssistantSelectExecutable(prompt) {
 global SetupAssistantGui, SettingsGui, SettingsEditorDialogActive
 if !IsSet(SetupAssistantGui)
     return ""
 try {
     SetupAssistantGui.Opt("+OwnDialogs -AlwaysOnTop")
     WinSetAlwaysOnTop(0, "ahk_id " SetupAssistantGui.Hwnd)
     if IsSet(SettingsGui) {
         try SettingsGui.Opt("-AlwaysOnTop")
         try WinSetAlwaysOnTop(0, "ahk_id " SettingsGui.Hwnd)
     }
 }
 selectedPath := ""
 SettingsEditorDialogActive := true
 try selectedPath := FileSelect(1, A_ProgramFiles, prompt, "Programs (*.exe)")
 catch {
     selectedPath := ""
 } finally {
     SettingsEditorDialogActive := false
     if IsSet(SettingsGui) {
         try SettingsGui.Opt("+AlwaysOnTop")
         try WinSetAlwaysOnTop(1, "ahk_id " SettingsGui.Hwnd)
     }
     if IsSet(SetupAssistantGui) {
         try SetupAssistantGui.Opt("+AlwaysOnTop")
         try WinSetAlwaysOnTop(1, "ahk_id " SetupAssistantGui.Hwnd)
         try WinActivate("ahk_id " SetupAssistantGui.Hwnd)
     }
 }
 return selectedPath
}

SetupAssistantChooseSteam(*) {
 global SteamPath
 selectedPath := SetupAssistantSelectExecutable("Select Steam.exe")
 if (selectedPath = "")
     return
 if (StrLower(SplitPathName(selectedPath)) != "steam.exe") {
     SetupAssistantSetStatus("Select Steam.exe, not " SplitPathName(selectedPath) ".")
     return
 }
 if CommitIniChanges([
     Map("section", "Paths", "key", "SteamPath", "value", selectedPath)
 ]) {
     SteamPath := selectedPath
     SetupAssistantSetStatus("Steam path saved: " selectedPath)
 }
}

SetupAssistantChooseRtss(*) {
 global RtssPath
 selectedPath := SetupAssistantSelectExecutable("Select RTSS.exe")
 if (selectedPath = "")
     return
 if (StrLower(SplitPathName(selectedPath)) != "rtss.exe") {
     SetupAssistantSetStatus("Select RTSS.exe, not " SplitPathName(selectedPath) ".")
     return
 }
 if CommitIniChanges([
     Map("section", "RTSS", "key", "Path", "value", selectedPath)
 ]) {
     RtssPath := selectedPath
     SetupAssistantSetStatus("RTSS path saved. Integration remains disabled until its shortcuts are configured.")
 }
}

SplitPathName(path) {
 fileName := ""
 try SplitPath(path, &fileName)
 return fileName
}

SetupAssistantInstall(*) {
 if InstallOrRepairSteamShell(false, true)
     SetupAssistantSetStatus("SteamShell is installed for the current user. Sign out and back in when ready.")
}

SetupAssistantPortable(*) {
 SetupAssistantSetStatus(
     "Portable mode selected. Keep the EXE and INI together; Windows shell registration was not changed.")
}

ShowSetupAssistant(*) {
 global SetupAssistantGui, SteamShellVersion
 if !IsSet(SetupAssistantGui) {
     SetupAssistantGui := Gui("+AlwaysOnTop +ToolWindow -Resize", "SteamShell Setup Assistant")
     SetupAssistantGui.Opt("+OwnDialogs")
     SetupAssistantGui.SetFont("s10", "Segoe UI")
     title := SetupAssistantGui.AddText("xm ym w650 h30", "SteamShell Setup Assistant")
     title.SetFont("s17 Bold", "Segoe UI")
     SetupAssistantGui.AddText(
         "xm y+2 w650 h38 +Wrap",
         "Prepare paths, input, recovery, and installation without requiring a separate installer.")

     SetupAssistantGui.AddGroupBox("xm y+10 w650 h86", "1. Required application")
     SetupAssistantGui.AddText("xp+14 yp+26 w430 h42 +Wrap", "Select Steam.exe and verify it with Health Check.")
     steamButton := SetupAssistantGui.AddButton("x+8 yp-2 w170 h32", "Select Steam.exe…")
     steamButton.OnEvent("Click", SetupAssistantChooseSteam)

     SetupAssistantGui.AddGroupBox("xm y+10 w650 h86", "2. Optional performance integration")
     SetupAssistantGui.AddText(
         "xp+14 yp+26 w430 h42 +Wrap",
         "Select RTSS.exe if used. Shortcut configuration can be completed later in Settings.")
     rtssButton := SetupAssistantGui.AddButton("x+8 yp-2 w170 h32", "Select RTSS.exe…")
     rtssButton.OnEvent("Click", SetupAssistantChooseRtss)

     SetupAssistantGui.AddGroupBox("xm y+10 w650 h92", "3. Verify this PC")
     controllerButton := SetupAssistantGui.AddButton(
         "xp+14 yp+30 w190 h32", "Test / Calibrate Controller")
     controllerButton.OnEvent("Click", ShowControllerTest)
     healthButton := SetupAssistantGui.AddButton("x+10 yp w170 h32", "Run Health Check")
     healthButton.OnEvent("Click", ShowHealthCheck)
     settingsButton := SetupAssistantGui.AddButton("x+10 yp w190 h32", "Open Full Settings")
     settingsButton.OnEvent("Click", ShowSettingsEditor)

     SetupAssistantGui.AddGroupBox("xm y+10 w650 h92", "4. Choose deployment")
     portableButton := SetupAssistantGui.AddButton("xp+14 yp+30 w190 h32", "Keep Portable")
     portableButton.OnEvent("Click", SetupAssistantPortable)
     installButton := SetupAssistantGui.AddButton("x+10 yp w210 h32", "Install as Windows Shell")
     installButton.OnEvent("Click", SetupAssistantInstall)
     restoreButton := SetupAssistantGui.AddButton("x+10 yp w180 h32", "Restore Desktop")
     restoreButton.OnEvent("Click", SettingsEditorRestoreDesktop)

     SetupAssistantGui.AddText(
         "xm y+10 w650 h44 +Wrap vSetupStatus",
         "Nothing is installed until you explicitly choose Install as Windows Shell.")
     closeButton := SetupAssistantGui.AddButton("x510 y+4 w140 h34", "Close")
     closeButton.OnEvent("Click", (*) => SetupAssistantGui.Hide())
     SetupAssistantGui.OnEvent("Close", (*) => SetupAssistantGui.Hide())
     SetupAssistantGui.OnEvent("Escape", (*) => SetupAssistantGui.Hide())
 }
 SetupAssistantGui.Show()
 CenterGuiOnTargetMonitor(SetupAssistantGui)
}

ShowSettingsEditorCategory(categoryName) {
 global SettingsGui, SettingsEditorCategories
 ShowSettingsEditor()
 if !IsSet(SettingsGui)
     return
 for index, candidate in SettingsEditorCategories {
     if (candidate = categoryName) {
         SettingsEditorShowCategory(index)
         return
     }
 }
}

ShowSettingsEditor(*) {
 global SettingsGui, SettingsEditorFields, SettingsEditorCategoryControls
 global SettingsEditorControlPositions, SettingsEditorCategoryOffsets
 global SettingsEditorCategories, SettingsEditorDirty, SettingsEditorUpdating, SettingsEditorStatusCtrl
 global SettingsEditorContentTop, SettingsEditorContentBottom, SettingsEditorWindowHeight
 global SettingsEditorScrollBar, SettingsEditorFooterControls, SettingsEditorDividerCtrl
 global SettingsStartupListView, SettingsStartupCommandEdit, SettingsStartupSelectedSlot
 global SteamShellVersion, LastRealFgHwnd, ControllerPollIntervalMs

 CaptureLastRealForeground()
 if IsSet(SettingsGui) {
     try {
         SettingsGui.Show()
         WinActivate("ahk_id " SettingsGui.Hwnd)
         SetTimer(PollController, ControllerPollIntervalMs)
         return
     }
 }

 SettingsEditorFields := []
 SettingsEditorCategoryControls := Map()
 SettingsEditorControlPositions := Map()
 SettingsEditorCategoryOffsets := Map()
 SettingsEditorFooterControls := []
 SettingsEditorCategories := [
     "General",
     "Startup & Splash",
     "Startup Programs",
     "Controller & Cursor",
     "Focus & Windows",
     "RTSS & Performance",
     "Launcher Cleanup",
     "Advanced & Logging"
 ]
 SettingsEditorDirty := false
 SettingsEditorUpdating := false
 SettingsStartupSelectedSlot := 1

 SettingsGui := Gui(
     "+AlwaysOnTop +Resize +MinimizeBox -MaximizeBox +MinSize980x450 +MaxSize980x660",
     "SteamShell " SteamShellVersion " Settings")
 SettingsGui.Opt("+OwnDialogs")
 SettingsGui.SetFont("s10", "Segoe UI")
 SettingsGui.MarginX := 18
 SettingsGui.MarginY := 16
 SettingsGui.OnEvent("Close", SettingsEditorClose)
 SettingsGui.OnEvent("Size", SettingsEditorResized)

 GetTargetMonitorWorkArea(LastRealFgHwnd, &workLeft, &workTop, &workRight, &workBottom)
 ; A Chromium/Steam foreground window can report 96 DPI even while the native
 ; AutoHotkey GUI is being scaled for a 4K television. Trust the process/native
 ; GUI DPI as the safe floor; using Steam's virtualized DPI made an 800-logical-
 ; pixel Settings window exceed the physical work area at 300% scaling.
 windowDpi := Max(96, A_ScreenDPI)
 try windowDpi := Max(
     windowDpi,
     DllCall("User32\GetDpiForWindow", "Ptr", SettingsGui.Hwnd, "UInt"))
 if (windowDpi <= 0)
     windowDpi := 96
 availableLogicalHeight := Floor(((workBottom - workTop) - 64) * 96 / windowDpi)
 SettingsEditorWindowHeight := ClampInt(availableLogicalHeight, 450, 660)
 dividerY := SettingsEditorWindowHeight - 90
 buttonY := dividerY + 15
 SettingsEditorContentTop := 145
 SettingsEditorContentBottom := dividerY - 8

 titleCtrl := SettingsGui.AddText("x20 y16 w940 h34", "SteamShell Settings")
 titleCtrl.SetFont("s18 Bold", "Segoe UI")
 SettingsGui.AddText("x22 y49 w930 h22"
     , "D-pad navigate • A activate • LT/RT categories • Right stick mouse • RB pointer action • Y save")

 categoryList := SettingsGui.AddListBox(
     "x20 y82 w205 h" (dividerY - 98) " vsettingsCategoryList", SettingsEditorCategories)
 categoryList.OnEvent("Change", SettingsEditorCategoryChanged)

 ; General
 category := "General"
 SettingsEditorAddHeading(category, "General"
     , "Core shell behavior and which modules appear in the living-room Quick Menu.")
 y := 150
 SettingsEditorAddCheckbox(category, "Features", "EnableTaskbarHiding", "Hide the Windows taskbar while SteamShell is active", &y, "true")
 SettingsEditorAddCheckbox(category, "Features", "EnableDesktopBlackout", "Show a black background instead of the wallpaper and desktop icons", &y, "true")
 SettingsEditorAddCheckbox(category, "QuickMenu", "Enable", "Enable the controller-first Quick Menu", &y, "true")
 SettingsEditorAddCheckbox(category, "AudioQuickControls", "Enable", "Show Audio controls in the Quick Menu", &y, "true")
 SettingsEditorAddCheckbox(category, "DisplayQuickControls", "Enable", "Show Display and HDR controls in the Quick Menu", &y, "true")
 SettingsEditorAddTextField(category, "QuickMenu", "ChordHoldMs", "Quick Menu L3+R3 hold time (ms)", &y, "700", "integer", 300, 3000)
 SettingsEditorAddTextField(category, "QuickMenu", "TaskForceCloseHoldMs", "Task Switcher force-close hold time (ms)", &y, "1200", "integer", 600, 3000)
 SettingsEditorAddTextField(category, "BPM", "BpmTitle", "Steam Big Picture window title", &y, "Steam Big Picture Mode")
 SettingsEditorAddShortcutField(category, "Steam", "MenuShortcut", "Steam Menu shortcut", &y, "^1")
 SettingsEditorAddShortcutField(category, "Steam", "QuickAccessShortcut", "Steam Quick Access shortcut", &y, "^2")
 SettingsEditorAddShortcutField(category, "Steam", "OverlayShortcut", "In-game Steam overlay shortcut", &y, "+{Tab}")
 SettingsEditorAddActionButton(category, "Customize Quick Menu…", ShowQuickMenuLayoutManager, 255, y + 6, 240)

 ; Startup and splash
 category := "Startup & Splash"
 SettingsEditorAddHeading(category, "Startup & Splash"
     , "Changes take effect next launch. If administrator startup is off, Windows can block controller mouse control in elevated apps.")
 y := 150
 SettingsEditorAddCheckbox(
     category, "Features", "RunElevatedOnStartup",
     "Run SteamShell as administrator on startup (recommended)", &y, "true")
 SettingsEditorAddPathField(category, "Paths", "SteamPath", "Steam executable", &y
     , "Select Steam.exe", "Programs (*.exe)", "C:\Program Files (x86)\Steam\Steam.exe")
 SettingsEditorAddCheckbox(category, "Features", "EnableSplashScreen", "Show the SteamShell startup splash", &y, "true")
 SettingsEditorAddChoice(category, "Splash", "Mode", "Splash mode", ["Black", "Video"], &y, "Black")
 SettingsEditorAddPathField(category, "Splash", "VideoPath", "Startup video", &y
     , "Select a startup video", "Video Files (*.mp4; *.mkv; *.webm; *.wmv; *.avi)")
 SettingsEditorAddPathField(category, "Splash", "MpvPath", "MPV executable", &y
     , "Select mpv.exe", "Programs (*.exe)")
 SettingsEditorAddCheckbox(category, "Splash", "Mute", "Mute startup video audio", &y, "false")
 SettingsEditorAddCheckbox(category, "Splash", "PlayFullDuration", "Play the entire startup video", &y, "true")
 SettingsEditorAddCheckbox(category, "Splash", "ForceSDR", "Force MPV to SDR output", &y, "true")
 SettingsEditorAddTextField(category, "Timing", "SplashScreenDuration", "Black/timed splash duration (ms)", &y, "10000", "integer", 0, 60000)
 SettingsEditorAddTextField(category, "Splash", "SafetyMaxMs", "Video safety timeout (ms)", &y, "15000", "integer", 1000, 600000)
 SettingsEditorAddTextField(category, "Splash", "FadeOutMs", "Splash fade duration (ms)", &y, "300", "integer", 0, 5000)

 ; Startup programs
 category := "Startup Programs"
 SettingsEditorAddHeading(category, "Startup Programs"
     , "Add up to 20 programs to launch hidden. Select a row to edit its command or optional arguments.")
 y := 150
 SettingsEditorAddCheckbox(category, "StartupPrograms", "Enable", "Launch configured startup programs with SteamShell", &y, "false")
 SettingsEditorAddTextField(category, "StartupPrograms", "DelayMs", "Launch delay (ms)", &y, "2000", "integer", 0, 600000)
 SettingsEditorAddChoice(
     category, "StartupPrograms", "WindowMode", "Launch window mode",
     ["Hidden", "Minimized", "Normal"], &y, "Hidden")
 startupListY := y + 6
 SettingsStartupListView := SettingsGui.AddListView(
     "x255 y" startupListY " w690 h150 -Multi", ["Slot", "Command"])
 SettingsStartupListView.ModifyCol(1, 55)
 SettingsStartupListView.ModifyCol(2, 610)
 Loop 20
     SettingsStartupListView.Add("", A_Index, IniReadS("StartupPrograms", "Program" A_Index, ""))
 SettingsStartupListView.OnEvent("ItemSelect", SettingsEditorStartupSelectionChanged)
 SettingsEditorRegisterControl(category, SettingsStartupListView)
 startupCommandLabel := SettingsGui.AddText(
     "x255 y" (startupListY + 158) " w690 h20", "Selected command and optional arguments")
 SettingsEditorRegisterControl(category, startupCommandLabel)
 SettingsStartupCommandEdit := SettingsGui.AddEdit(
     "x255 y" (startupListY + 180) " w690", IniReadS("StartupPrograms", "Program1", ""))
 SettingsStartupCommandEdit.OnEvent("Change", SettingsEditorMarkDirty)
 SettingsEditorRegisterControl(category, SettingsStartupCommandEdit)
 startupButtonY := startupListY + 220
 SettingsEditorAddActionButton(category, "Add Program…", SettingsEditorAddStartupProgram, 255, startupButtonY, 155)
 SettingsEditorAddActionButton(category, "Browse Selected…", SettingsEditorBrowseStartupProgram, 420, startupButtonY, 175)
 SettingsEditorAddActionButton(category, "Apply Command", SettingsEditorSetStartupCommand, 605, startupButtonY, 155)
 SettingsEditorAddActionButton(category, "Remove Selected", SettingsEditorClearStartupCommand, 770, startupButtonY, 175)
 SettingsEditorAddActionButton(
     category, "Test Launch", SettingsEditorTestStartupProgram, 255, startupButtonY + 38, 155)
 SettingsEditorAddActionButton(
     category, "Move Up", SettingsEditorMoveStartupProgram.Bind(-1), 420, startupButtonY + 38, 155)
 SettingsEditorAddActionButton(
     category, "Move Down", SettingsEditorMoveStartupProgram.Bind(1), 585, startupButtonY + 38, 155)
 SettingsStartupListView.Modify(1, "Select Focus Vis")

 ; Controller and cursor
 category := "Controller & Cursor"
 SettingsEditorAddHeading(category, "Controller & Cursor"
     , "Controller navigation and cursor behavior. Controller mapping opens the existing dedicated mapping editor.")
 y := 150
 SettingsEditorAddCheckbox(category, "Controller", "EnableControllerMouseMode", "Enable controller mouse mode while holding View/Back", &y, "true")
 SettingsEditorAddChoice(category, "Controller", "ControllerIndex", "Controller index", ["0", "1", "2", "3"], &y, "0")
 SettingsEditorAddTextField(category, "Controller", "ControllerMouseSpeed", "Controller mouse speed", &y, "100", "integer", 1, 200)
 SettingsEditorAddTextField(category, "Controller", "ControllerDeadzone", "Stick deadzone", &y, "4000", "integer", 0, 32000)
 SettingsEditorAddTextField(category, "Controller", "ControllerChordHoldMs", "Mapping long-press threshold (ms)", &y, "500", "integer", 100, 2000)
 SettingsEditorAddCheckbox(category, "Features", "EnableAutoHideCursor", "Automatically hide an idle mouse cursor", &y, "true")
 SettingsEditorAddTextField(category, "Timing", "MouseHideDelay", "Cursor hide delay (ms)", &y, "1000", "integer", 0, 60000)
 SettingsEditorAddCheckbox(category, "Features", "EnableMouseParkOnBoot", "Park the mouse at the display edge once during startup", &y, "true")
 SettingsEditorAddCheckbox(category, "Features", "EnableMouseParkOnFocusChange", "Park once after a managed focus change", &y, "true")
 SettingsEditorAddChoice(category, "MousePark", "MouseParkEdge", "Mouse parking edge", ["Right", "Left"], &y, "Right")
 SettingsEditorAddCheckbox(category, "Features", "EnableAutoMouseMode", "Automatic mouse mode in the applications listed below", &y, "true")
 SettingsEditorAddActionButton(category, "Open Controller Mapping…", ShowControllerMappingWindow, 255, y + 5, 260)
 SettingsEditorAddActionButton(category, "Test / Calibrate Controller…", ShowControllerTest, 525, y + 5, 260)
 autoMouseY := y + 48
 SettingsEditorAddExeListField(
     category, "Controller", "AutoMouseExeList",
     "Automatic mouse mode for these EXEs", 255, autoMouseY, 690)

 ; Focus
 category := "Focus & Windows"
 SettingsEditorAddHeading(category, "Focus & Windows"
     , "One coordinated engine inventories windows, applies bounded geometry corrections, and selects one focus winner.")
 y := 150
 SettingsEditorAddCheckbox(category, "Features", "EnableSteamRefocusMode", "Refocus Steam Big Picture when no application remains", &y, "true")
 SettingsEditorAddTextField(category, "Timing", "SteamRefocusDelay", "Steam refocus delay (ms)", &y, "3000", "integer", 0, 60000)
 gameAssistCtrl := SettingsEditorAddCheckbox(category, "Features", "EnableGameForegroundAssist", "Bring the active fullscreen-style game forward", &y, "true")
 gameAssistCtrl.OnEvent("Click", SettingsEditorRefreshDependencies)
 SettingsEditorAddCheckbox(category, "GameForegroundAssist", "GameRequireSteamForeground", "Run game assistance only while Steam is foreground", &y, "true")
 SettingsEditorAddMappedChoice(
     category, "GameForegroundAssist", "GameMinScoreToActivate",
     "Foreground sensitivity",
     ["Responsive (55)", "Balanced (60)", "Conservative (70)"],
     ["55", "60", "70"], &y, "55")
 SettingsEditorAddCheckbox(category, "Features", "EnableAlwaysFocus", "Enable the AlwaysFocus executable list", &y, "true")
 windowManagementCtrl := SettingsEditorAddCheckbox(category, "Features", "EnableWindowManagement", "Center windows and maximize large windows", &y, "true")
 windowManagementCtrl.OnEvent("Click", SettingsEditorRefreshDependencies)
 SettingsEditorAddTextField(
     category, "WindowManagement", "MinWidthPercent",
     "Maximize width threshold (%)", &y, "0.20", "percent", 5, 100)
 exclusionY := y + 8
 SettingsEditorAddExeListField(
     category, "WindowManagement", "ExcludeExeList",
     "Never center or maximize these EXEs", 255, exclusionY, 690)
 SettingsEditorAddActionButton(
     category, "Open AlwaysFocus Manager…", ShowAlwaysFocusManager, 255, exclusionY + 204, 260)

 ; RTSS
 category := "RTSS & Performance"
 SettingsEditorAddHeading(category, "RTSS & Performance"
     , "Live RTSS state is used when available; configured shortcuts remain the compatibility fallback.")
 y := 150
 SettingsEditorAddCheckbox(category, "RTSS", "EnableIntegration", "Enable RTSS integration in the Quick Menu", &y, "false")
 SettingsEditorAddPathField(category, "RTSS", "Path", "RTSS executable", &y
     , "Select RTSS.exe", "Programs (*.exe)", "C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe")
 SettingsEditorAddCheckbox(category, "RTSS", "UseDllIntegration", "Use RTSSHooks64.dll for live state and direct control (recommended)", &y, "true")
 rtssOverlayModeCtrl := SettingsEditorAddChoice(
     category, "RTSS", "OverlayControlMode",
     "Overlay control mode", ["Toggle", "Separate"], &y, "Toggle")
 rtssOverlayModeCtrl.OnEvent("Change", SettingsEditorRefreshDependencies)
 SettingsEditorAddShortcutField(category, "RTSS", "OverlayToggleShortcut", "Overlay toggle shortcut", &y, "^+o")
 SettingsEditorAddShortcutField(category, "RTSS", "OverlayOnShortcut", "Overlay on shortcut", &y, "^+1")
 SettingsEditorAddShortcutField(category, "RTSS", "OverlayOffShortcut", "Overlay off shortcut", &y, "^+2")
 rtssLimiterModeCtrl := SettingsEditorAddChoice(
     category, "RTSS", "FrameLimiterControlMode",
     "Frame limiter control mode", ["Toggle", "Separate"], &y, "Toggle")
 rtssLimiterModeCtrl.OnEvent("Change", SettingsEditorRefreshDependencies)
 SettingsEditorAddTextField(
     category, "RTSS", "CustomFrameCap",
     "Frame cap configured in RTSS (FPS)", &y, "0", "integer", 0, 1000)
 SettingsEditorAddShortcutField(category, "RTSS", "CustomFrameCapShortcut", "Frame limiter toggle shortcut", &y, "^+f")
 SettingsEditorAddShortcutField(category, "RTSS", "FrameLimiterOnShortcut", "Frame limiter on shortcut", &y, "^+5")
 SettingsEditorAddShortcutField(category, "RTSS", "FrameLimiterOffShortcut", "Frame limiter off shortcut", &y, "^+6")
 SettingsEditorAddActionButton(category, "Launch Selected RTSS", SettingsEditorOpenRtss, 255, y + 4, 220)

 ; Launcher cleanup
 category := "Launcher Cleanup"
 SettingsEditorAddHeading(category, "Launcher Cleanup"
     , "Optional cleanup after returning to Steam. EXE lists are saved automatically in the required pipe-separated format.")
 y := 150
 SettingsEditorAddCheckbox(category, "LauncherCleanup", "Enable", "Enable launcher cleanup", &y, "false")
 requireNoGameCtrl := SettingsEditorAddCheckbox(
     category, "LauncherCleanup", "RequireNoGame",
     "Require SteamShell to detect that no game is running", &y, "true")
 requireNoGameCtrl.OnEvent("Click", SettingsEditorRefreshDependencies)
 SettingsEditorAddCheckbox(category, "LauncherCleanup", "HardKill", "Force-close remaining launcher processes after the grace period", &y, "false")
 SettingsEditorAddTextField(category, "LauncherCleanup", "SteamForegroundSec", "Steam foreground time before cleanup (sec)", &y, "30", "integer", 1, 600)
 SettingsEditorAddTextField(category, "LauncherCleanup", "CooldownSec", "Cleanup cooldown (sec)", &y, "300", "integer", 0, 86400)
 SettingsEditorAddTextField(category, "LauncherCleanup", "GracefulCloseMs", "Graceful-close wait (ms)", &y, "4000", "integer", 0, 60000)
 useCpuAudioCtrl := SettingsEditorAddCheckbox(
     category, "LauncherCleanup", "UseCpuAudio",
     "Use CPU and audio activity for the no-game safety check", &y, "true")
 useCpuAudioCtrl.OnEvent("Click", SettingsEditorRefreshDependencies)
 SettingsEditorAddTextField(category, "LauncherCleanup", "CpuThreshold", "CPU activity threshold", &y, "12", "integer", 0, 500)
 downloadGuardCtrl := SettingsEditorAddCheckbox(
     category, "LauncherCleanup", "DownloadGuard",
     "Skip cleanup during possible downloads or updates", &y, "false")
 downloadGuardCtrl.OnEvent("Click", SettingsEditorRefreshDependencies)
 SettingsEditorAddChoice(category, "LauncherCleanup", "DownloadGuardMode", "Download guard sensitivity", ["Off", "Balanced", "Strict"], &y, "Balanced")
 listY := y + 8
 SettingsEditorAddExeListField(
     category, "LauncherCleanup", "LauncherExeList", "Launcher EXEs to close", 255, listY)
 SettingsEditorAddExeListField(
     category, "LauncherCleanup", "ExcludeExeList", "Never close these EXEs", 610, listY)
 helperListY := listY + 210
 SettingsEditorAddExeListField(
     category, "LauncherCleanup", "BackgroundExeList",
     "Background helper EXEs to close", 255, helperListY, 690)
 SettingsEditorAddActionButton(
     category, "Preview Running Cleanup Targets…",
     SettingsEditorPreviewLauncherCleanup, 255, helperListY + 204, 300)
 y := helperListY + 242

 ; Advanced and logging
 category := "Advanced & Logging"
 SettingsEditorAddHeading(category, "Advanced & Logging"
     , "Common diagnostics are available here. Open the Diagnostics Panel for timed overrides and detailed status.")
 y := 150
 gameLogModeCtrl := SettingsEditorAddChoice(
     category, "Logging", "GameLogMode",
     "Game log detail", ["OFF", "ACTIVATIONS", "TOPN", "DIAGNOSTIC"], &y, "OFF")
 gameLogModeCtrl.OnEvent("Change", SettingsEditorRefreshDependencies)
 SettingsEditorAddTextField(category, "Logging", "GameLogTopN", "Candidates recorded in TOPN/DIAGNOSTIC", &y, "3", "integer", 1, 10)
 SettingsEditorAddTextField(category, "Logging", "GameLogIntervalMs", "Diagnostic logging interval (ms)", &y, "3000", "integer", 250, 60000)
 SettingsEditorAddCheckbox(category, "Logging", "GameLogIncludeTitles", "Include window titles in diagnostic logs", &y, "true")
 SettingsEditorAddCheckbox(category, "GameForegroundAssist", "GameAssistLogEvenWhenSkipped", "Log candidates even when game assistance is skipped", &y, "false")
 SettingsEditorAddTextField(category, "Timing", "SteamStartupGraceMs", "Steam startup warning delay (ms)", &y, "120000", "integer", 10000, 600000)
 SettingsEditorAddTextField(category, "Timing", "SteamExitConfirmMs", "Steam exit confirmation period (ms)", &y, "8000", "integer", 1000, 60000)
 actionY := y + 12
 actionLeft := 255
 actionRight := 610
 actionWidth := 335
 SettingsEditorAddActionButton(category, "Pause / Resume Focus", SettingsEditorToggleFocusPause, actionLeft, actionY, actionWidth)
 SettingsEditorAddActionButton(category, "Run Game Assist", SettingsEditorRunGameAssist, actionRight, actionY, actionWidth)
 SettingsEditorAddActionButton(category, "Reload Runtime", SettingsEditorReloadRuntime, actionLeft, actionY + 38, actionWidth)
 SettingsEditorAddActionButton(category, "Open INI in Notepad", SettingsEditorOpenIni, actionRight, actionY + 38, actionWidth)
 SettingsEditorAddActionButton(category, "Open Live Log", ShowLiveLogWindow, actionLeft, actionY + 76, actionWidth)
 SettingsEditorAddActionButton(category, "Diagnostics Panel…", ShowControlPanel, actionRight, actionY + 76, actionWidth)
 SettingsEditorAddActionButton(category, "Install Managed Copy as Shell", SettingsEditorInstallSteamShell, actionLeft, actionY + 114, actionWidth)
 SettingsEditorAddActionButton(category, "Repair Managed Installation", SettingsEditorRepairSteamShell, actionRight, actionY + 114, actionWidth)
 SettingsEditorAddActionButton(category, "Register Current EXE as Shell", SettingsEditorRegisterCurrentShell, actionLeft, actionY + 152, actionWidth)
 SettingsEditorAddActionButton(category, "Permanently Restore Explorer", SettingsEditorRestoreDesktop, actionRight, actionY + 152, actionWidth)
 SettingsEditorAddActionButton(category, "Health Check…", ShowHealthCheck, actionLeft, actionY + 190, actionWidth)
 SettingsEditorAddActionButton(category, "Export Diagnostic ZIP", ExportDiagnosticBundle, actionRight, actionY + 190, actionWidth)
 SettingsEditorAddActionButton(category, "Create Settings Backup", SettingsEditorCreateBackup, actionLeft, actionY + 228, actionWidth)
 SettingsEditorAddActionButton(category, "Export Settings…", SettingsEditorExportSettings, actionRight, actionY + 228, actionWidth)
 SettingsEditorAddActionButton(category, "Import / Restore…", SettingsEditorImportSettings, actionLeft, actionY + 266, actionWidth)
 SettingsEditorAddActionButton(category, "Restore Category Defaults…", SettingsEditorResetCategory, actionRight, actionY + 266, actionWidth)
 SettingsEditorAddActionButton(category, "Reset All Settings…", SettingsEditorResetAll, actionLeft, actionY + 304, actionWidth)
 SettingsEditorAddActionButton(category, "Restart in Safe Mode", RestartSteamShellInSafeMode, actionRight, actionY + 304, actionWidth)
 SettingsEditorAddActionButton(category, "Setup Assistant…", ShowSetupAssistant, actionLeft, actionY + 342, actionWidth)

 ; Common bottom controls
 SettingsEditorDividerCtrl := SettingsGui.AddText("x20 y" dividerY " w925 h1 0x10")
 saveButton := SettingsGui.AddButton("x540 y" buttonY " w145 h34 Default", "Save && Apply")
 saveButton.OnEvent("Click", SettingsEditorSave)
 reloadButton := SettingsGui.AddButton("x695 y" buttonY " w125 h34", "Reload INI")
 reloadButton.OnEvent("Click", SettingsEditorReloadFromIni)
 closeButton := SettingsGui.AddButton("x830 y" buttonY " w115 h34", "Close")
 closeButton.OnEvent("Click", SettingsEditorClose)
 SettingsEditorFooterControls := [saveButton, reloadButton, closeButton]
 SettingsEditorStatusCtrl := SettingsGui.AddText(
     "x20 y" (SettingsEditorWindowHeight - 32) " w925 h24", "No unsaved changes")
 scrollBarHeight := SettingsEditorContentBottom - SettingsEditorContentTop
 SettingsEditorScrollBar := SettingsGui.Add(
     "Custom", "ClassScrollBar x954 y" SettingsEditorContentTop " w18 h" scrollBarHeight " 0x1")
 OnMessage(0x020A, SettingsEditorMouseWheel)
 OnMessage(0x0115, SettingsEditorVerticalScroll)

 SettingsEditorReportLayoutAudit()
 SettingsEditorRefreshDependencies()
 SettingsEditorShowCategory(1)
 SettingsGui.Show("w980 h" SettingsEditorWindowHeight)
 CenterGuiOnTargetMonitor(SettingsGui, LastRealFgHwnd)
 HandleCursorAfterManagedFocus(SettingsGui.Hwnd, false)
 SetTimer(PollController, ControllerPollIntervalMs)
}

ShowControlPanel(*) {
 global ControlGui, SettingsPath
 global ControllerMouseSpeed
 global SteamShellVersion

 CaptureLastRealForeground()

 ; Compute layout values every time (so sizing works even when the GUI already exists).
 mx := 12
 my := 12
 colGap := 20

 ; Fit 2 columns within the screen (helps with DPI scaling so nothing gets clipped).
 availW := A_ScreenWidth - (mx*2) - 40
 colW := Floor((availW - colGap) / 2)
 if (colW < 320)
 colW := 320
 if (colW > 460)
 colW := 460

 x1 := mx
 x2 := x1 + colW + colGap
 fullW := colW*2 + colGap

 if !IsSet(ControlGui) {
 ControlGui := Gui("+AlwaysOnTop +ToolWindow +Resize", "SteamShell " SteamShellVersion " Control Panel")
 ControlGui.SetFont("s10", "Segoe UI")

 ; Layout: two columns. Live log opens in a separate window (button lives in right column).
 ControlGui.MarginX := mx
 ControlGui.MarginY := my

 ; ----------------------------
 ; LEFT COLUMN
 ; ----------------------------
 ControlGui.SetFont("s10 Bold")
 ControlGui.AddText("x" x1 " ym", "Feature toggles (runtime)")
 ControlGui.SetFont("s9 Norm")
 ControlGui.AddText("x" x1 " y+2 w" colW " h42 +Wrap"
 , "Tip: Use “Apply (runtime only)” for temporary changes. Use “Save to INI” to persist after reboot.")
 ControlGui.SetFont("s10 Norm")

 ControlGui.AddCheckbox("x" x1 " y+10 vcbGame", "Game focusing (fullscreen game assist)")
 ControlGui.AddCheckbox("x" x1 " y+6 vcbSteam", "Steam focusing (refocus Big Picture when idle)")
 ControlGui.AddCheckbox("x" x1 " y+6 vcbMax", "Window management (maximize/center when needed)")

 ControlGui.AddText("x" x1 " y+10", "Logging / diagnostics:")
 ControlGui.AddCheckbox("x" x1 " y+6 vcbLiveLog", "Live focus logging (DIAGNOSTIC mode)")
 ControlGui.AddCheckbox("x" x1 " y+6 vcbSkipLog", "Log candidates even when skipped (Steam not foreground)")

 ControlGui.AddText("x" x1 " y+12", "AlwaysFocus list:")
 ControlGui.AddButton("x" x1 " y+6 w" colW, "Open AlwaysFocus manager…").OnEvent("Click", ShowAlwaysFocusManager)

 ControlGui.AddText("x" x1 " y+14", "Timed actions duration (seconds):")
 ControlGui.AddEdit("x" x1 " y+6 w120 veditSecs", "30")
 ControlGui.SetFont("s9 Norm")
 ControlGui.AddText("x+10 yp+3 w" (colW-140) " +Wrap", "Used by timed disable + Hands-Off")
 ControlGui.SetFont("s10 Norm")

 halfW := Floor((colW - 20) / 2)
 btnApply := ControlGui.AddButton("x" x1 " y+12 w" halfW, "Apply (runtime only)")
 btnApply.OnEvent("Click", ApplySessionFromGui)
 btnRevert := ControlGui.AddButton("x+20 yp w" halfW, "Revert (to runtime)")
 btnRevert.OnEvent("Click", RevertPanelToRuntime)

 btnTimed := ControlGui.AddButton("x" x1 " y+10 w" colW, "Temporarily disable CHECKED items")
 btnTimed.OnEvent("Click", TimedDisableFromGui)

 ControlGui.SetFont("s10 Bold")
 ControlGui.AddText("x" x1 " y+16", "INI configuration")
 ControlGui.SetFont("s9 Norm")
 ControlGui.AddText("x" x1 " y+2 w" colW " h24 +Wrap", "INI file: " SettingsPath)
 ControlGui.SetFont("s10 Norm")

 btnLoad := ControlGui.AddButton("x" x1 " y+8 w" halfW, "Load from INI")
 btnLoad.OnEvent("Click", ReloadFromIniFromGui)
 btnSave := ControlGui.AddButton("x+20 yp w" halfW, "Save to INI")
 btnSave.OnEvent("Click", WriteToIniFromGui)

 lastLeftCtrl := btnSave

 ; ----------------------------
 ; RIGHT COLUMN
 ; ----------------------------
 ControlGui.SetFont("s10 Bold")
 ControlGui.AddText("x" x2 " ym", "Hands-Off mode")
 ControlGui.SetFont("s9 Norm")
 ControlGui.AddText("x" x2 " y+2 w" colW " h46 +Wrap"
 , "Pauses ALL focus behavior temporarily (game + steam + window management). Useful if SteamShell is fighting you while launching/closing things.")
 ControlGui.SetFont("s10 Norm")

 btnHOStart := ControlGui.AddButton("x" x2 " y+8 w" halfW, "Start Hands-Off (timed)")
 btnHOStart.OnEvent("Click", StartHandsOffFromGui)
 btnHOStop := ControlGui.AddButton("x+20 yp w" halfW, "Resume now")
 btnHOStop.OnEvent("Click", ResumeHandsOffNow)

 ; ----------------------------
 ; Live Log (button moved into right column)
 ; ----------------------------
 ControlGui.SetFont("s10 Bold")
 ControlGui.AddText("x" x2 " y+18", "Live log")
 ControlGui.SetFont("s9 Norm")
 ControlGui.AddText("x" x2 " y+2 w" colW " h24 +Wrap", "Opens a separate log window (newest entries first, auto-refresh).")
 ControlGui.SetFont("s10 Norm")
 ControlGui.AddButton("x" x2 " y+8 w" colW, "Open Live Log Window…").OnEvent("Click", ShowLiveLogWindow)

 ; ----------------------------
 ; Controller mouse mode (optional)
 ; ----------------------------
 ControlGui.SetFont("s10 Bold")
 ControlGui.AddText("x" x2 " y+18", "Controller mouse mode")
 ControlGui.SetFont("s10 Norm")
 ControlGui.AddCheckbox("x" x2 " y+8 vcbCtlMouse", "Enable controller mouse mode (hold View/Back)")

 ; Mouse speed slider (runtime)
 spTxt := ControlGui.AddText("x" x2 " y+8 vtxtCtlSpeed", "Mouse speed: " ControllerMouseSpeed)
 spSl := ControlGui.AddSlider("x" x2 " y+6 w" colW " Range5-200 ToolTip vslCtlSpeed")
 spSl.Value := ClampInt(ControllerMouseSpeed, 5, 200)
 spSl.OnEvent("Change", OnCtlMouseSpeedChanged)

 ControlGui.AddButton("x" x2 " y+10 w" halfW, "Open Quick Menu").OnEvent("Click", ToggleQuickMenu)
 ControlGui.AddButton("x+20 yp w" halfW, "Controller Mapping…").OnEvent("Click", ShowControllerMappingWindow)

 ; Keep direct handles for reliability
 global CPCtlSpeedTextCtrl, CPCtlSpeedSliderCtrl
 CPCtlSpeedTextCtrl := spTxt
 CPCtlSpeedSliderCtrl := spSl

 ControlGui.SetFont("s10 Bold")
 ControlGui.AddText("x" x2 " y+18", "Status")
 ControlGui.SetFont("s10 Norm")
 stat1 := ControlGui.AddText("x" x2 " y+6 w" colW " vstat1", "Steam Foreground: -")
 stat2 := ControlGui.AddText("x" x2 " y+2 w" colW " vstat2", "Hands-Off Remaining: -")
 stat3 := ControlGui.AddText("x" x2 " y+2 w" colW " vstat3", "Best Candidate: -")
 stat4 := ControlGui.AddText("x" x2 " y+2 w" colW " vstat4", "Last Action: -")

 ; Launcher Cleanup status (why launchers are still running / what was detected)
 stat5 := ControlGui.AddText("x" x2 " y+8 w" colW " vstat5 +Wrap", "Launcher Cleanup: -")
 stat6 := ControlGui.AddText("x" x2 " y+2 w" colW " vstat6 +Wrap", "LC Found: -")
 stat7 := ControlGui.AddText("x" x2 " y+2 w" colW " vstat7 +Wrap", "LC Gate: -")
stat8 := ControlGui.AddText("x" x2 " y+2 w" colW " vstat8 +Wrap", "LC Last: -")

 ; Keep direct handles for reliability (no dependence on name lookup)
 global CPStat1Ctrl, CPStat2Ctrl, CPStat3Ctrl, CPStat4Ctrl
 global CPStat5Ctrl, CPStat6Ctrl, CPStat7Ctrl, CPStat8Ctrl
 CPStat1Ctrl := stat1
 CPStat2Ctrl := stat2
 CPStat3Ctrl := stat3
 CPStat4Ctrl := stat4
 CPStat5Ctrl := stat5
 CPStat6Ctrl := stat6
 CPStat7Ctrl := stat7
 CPStat8Ctrl := stat8

 btnClose := ControlGui.AddButton("x" x2 " y+14 w" colW, "Close")
 btnClose.OnEvent("Click", (*) => HideControlPanel())
 ControlGui.OnEvent("Close", (*) => HideControlPanel())

 ControlGui.OnEvent("Escape", (*) => HideControlPanel())
 lastRightCtrl := btnClose

 ; Stash these for later sizing updates.
 ControlGui.__lastLeftCtrl := lastLeftCtrl
 ControlGui.__lastRightCtrl := lastRightCtrl
 } else {
 ; Retrieve stored bottom controls for sizing.
 try lastLeftCtrl := ControlGui.__lastLeftCtrl
 try lastRightCtrl := ControlGui.__lastRightCtrl
 }

 ; Ensure the panel always reflects current runtime state when opened.
 SyncControlPanel()
 UpdateStatusIndicators()

 ; Size the panel to the content while staying on-screen.
 try {
 lastLeftCtrl.GetPos(&lx, &ly, &lw, &lh)
 lastRightCtrl.GetPos(&rx, &ry, &rw, &rh)
 bottom := (ly + lh > ry + rh) ? (ly + lh) : (ry + rh)

 w := fullW + (mx*2)
 h := bottom + (my*2) + 8

 maxW := A_ScreenWidth - 40
 maxH := A_ScreenHeight - 80
 if (w > maxW)
 w := maxW
 if (h > maxH)
 h := maxH

 ControlGui.Show("w" w " h" h " Center")
 } catch {
 ControlGui.Show("Center")
 }

 EnsureLogRefreshTimer()
 EnsureStatusRefreshTimer()
 UpdateStatusIndicators()
}


HideControlPanel() {
 global ControlGui
 if IsSet(ControlGui) {
 try ControlGui.Hide()
 }
 EnsureLogRefreshTimer()
 EnsureStatusRefreshTimer()
}

IsGuiVisible(guiObj) {
 try {
 return DllCall("IsWindowVisible", "Ptr", guiObj.Hwnd, "Int")
 } catch {
 return 0
 }
}

EnsureLogRefreshTimer() {
 global ControlGui, LiveLogGui
 if ((IsSet(ControlGui) && IsGuiVisible(ControlGui)) || (IsSet(LiveLogGui) && IsGuiVisible(LiveLogGui))) {
 SetTimer(RefreshPanelLog, 500)
 } else {
 SetTimer(RefreshPanelLog, 0)
 }
}


EnsureStatusRefreshTimer() {
 global ControlGui, LiveLogGui
 if ((IsSet(ControlGui) && IsGuiVisible(ControlGui)) || (IsSet(LiveLogGui) && IsGuiVisible(LiveLogGui))) {
 SetTimer(UpdateStatusIndicators, 500)
 UpdateStatusIndicators()
 } else {
 SetTimer(UpdateStatusIndicators, 0)
 }
}


ShowLiveLogWindow(*) {
 global LiveLogGui, LogPath, DetachedLogMaxLines

 CaptureLastRealForeground()

 if !IsSet(LiveLogGui) {
 LiveLogGui := Gui("+AlwaysOnTop +ToolWindow +Resize", "SteamShell Live Log")
 LiveLogGui.SetFont("s10", "Segoe UI")
 LiveLogGui.MarginX := 12
 LiveLogGui.MarginY := 12

 LiveLogGui.SetFont("s10 Bold")
 LiveLogGui.AddText("xm ym", "Live log viewer (newest first)")
 LiveLogGui.SetFont("s9 Norm")
 LiveLogGui.AddText("xm y+2 w860 h34 +Wrap", "Source: " LogPath " (auto-refresh)")

 LiveLogGui.SetFont("s10 Norm")
 ll1 := LiveLogGui.AddText("xm y+10 w860 vstat1", "Steam Foreground: -")
 ll2 := LiveLogGui.AddText("xm y+2 w860 vstat2", "Hands-Off Remaining: -")
 ll3 := LiveLogGui.AddText("xm y+2 w860 vstat3", "Best Candidate: -")
 ll4 := LiveLogGui.AddText("xm y+2 w860 vstat4", "Last Action: -")

 ; Launcher Cleanup status (why launchers are still running / what was detected)
 ll5 := LiveLogGui.AddText("xm y+8 w860 vstat5 +Wrap", "Launcher Cleanup: -")
 ll6 := LiveLogGui.AddText("xm y+2 w860 vstat6 +Wrap", "LC Found: -")
 ll7 := LiveLogGui.AddText("xm y+2 w860 vstat7 +Wrap", "LC Gate: -")
ll8 := LiveLogGui.AddText("xm y+2 w860 vstat8 +Wrap", "LC Last: -")

 ; Keep direct handles for reliability (no dependence on name lookup)
 global LLStat1Ctrl, LLStat2Ctrl, LLStat3Ctrl, LLStat4Ctrl
 global LLStat5Ctrl, LLStat6Ctrl, LLStat7Ctrl, LLStat8Ctrl
 LLStat1Ctrl := ll1
 LLStat2Ctrl := ll2
 LLStat3Ctrl := ll3
 LLStat4Ctrl := ll4
 LLStat5Ctrl := ll5
 LLStat6Ctrl := ll6
 LLStat7Ctrl := ll7
 LLStat8Ctrl := ll8

 LiveLogGui.AddEdit("xm y+10 w860 r16 ReadOnly -Wrap vdetLogView", "")

 LiveLogGui.AddButton("xm y+10 w110", "Refresh").OnEvent("Click", RefreshPanelLog)
 LiveLogGui.AddButton("x+10 yp w110", "Copy").OnEvent("Click", CopyDetachedLog)
 LiveLogGui.AddButton("x+10 yp w110", "Open Log").OnEvent("Click", OpenLogFile)
 LiveLogGui.AddButton("x+10 yp w110", "Clear Log").OnEvent("Click", ClearLogFile)
 LiveLogGui.AddButton("x+10 yp w110", "Close").OnEvent("Click", (*) => HideLiveLogWindow())

 LiveLogGui.OnEvent("Close", (*) => HideLiveLogWindow())
 LiveLogGui.OnEvent("Escape", (*) => HideLiveLogWindow())
 }

 try {
 h := (A_ScreenHeight < 800) ? 460 : (A_ScreenHeight < 900) ? 520 : 600
 LiveLogGui.Show("w900 h" h)
 } catch {
 LiveLogGui.Show()
 }

 RefreshPanelLog()
 EnsureLogRefreshTimer()
 EnsureStatusRefreshTimer()
 UpdateStatusIndicators()
}

ShowControllerMappingWindow(*) {
 global ControllerMapGui, ControllerChordHoldMs
 global ControllerMap, ControllerMapDisplay
 global g_ControllerMapUI

 CaptureLastRealForeground()

 ; Rebuild each time so the editor stays consistent.
 try {
 if IsSet(ControllerMapGui)
 ControllerMapGui.Destroy()
 } catch {
 }

 ControllerMapGui := Gui("+AlwaysOnTop +ToolWindow", "Controller Mapping")
 ControllerMapGui.SetFont("s10", "Segoe UI")
 ControllerMapGui.MarginX := 12
 ControllerMapGui.MarginY := 12

 ControllerMapGui.AddText("xm", "Hold View/Back to activate mappings. Long-press threshold: " ControllerChordHoldMs " ms")
 ControllerMapGui.SetFont("s9", "Segoe UI")
 ControllerMapGui.AddText(
     "xm y+3 w640",
     "Default: hold L3+R3 for the Quick Menu. The fallback six-button chord opens Full Settings.")
 ControllerMapGui.SetFont("s10", "Segoe UI")

 lv := ControllerMapGui.AddListView("xm y+10 w640 r10 -Multi +LV0x10000", ["Button", "Short press", "Long press"])
 lv.ModifyCol(1, 70)
 lv.ModifyCol(2, 270)
 lv.ModifyCol(3, 270)

 buttons := ["A","B","X","Y","LB","RB","LT","RT","Start","L3","R3"]
 for btn in buttons {
 lv.Add("", btn, ControllerBindingPretty(btn ".Short"), ControllerBindingPretty(btn ".Long"))
 }
 lv.Modify(1, "Select Focus")

 ; Editor (below list, avoids width overflow/overlap)
 ControllerMapGui.SetFont("s10 Bold")
 ControllerMapGui.AddText("xm y+12", "Edit selected button")
 ControllerMapGui.SetFont("s10 Norm")

 ControllerMapGui.AddText("xm y+10 w70", "Selected:")
 txtSel := ControllerMapGui.AddText("x+8 yp w80", "-")

 choices := [
 "None",
 "Left click",
 "Right click",
 "Enter",
 "Esc",
 "Alt+F4",
 "Win+G",
 "Ctrl+Alt+Tab",
 "Task Manager",
 "Open Windows Start",
 "Open File Explorer",
 "Open Quick Menu",
 "Open Control Panel",
 "Open touch keyboard",
 "Open OSK",
 "Custom shortcut…"
 ]

 ; Short row
 ControllerMapGui.AddText("xm y+10 w70", "Short:")
 cbShort := ControllerMapGui.AddComboBox("x+8 yp w330", choices)
 btnRecShort := ControllerMapGui.AddButton("x+8 yp w90", "Record…")
 btnClrShort := ControllerMapGui.AddButton("x+8 yp w70", "Clear")
 txtCustomShort := ControllerMapGui.AddText("xm y+6 w640", "")

 ; Long row
 ControllerMapGui.AddText("xm y+10 w70", "Long:")
 cbLong := ControllerMapGui.AddComboBox("x+8 yp w330", choices)
 btnRecLong := ControllerMapGui.AddButton("x+8 yp w90", "Record…")
 btnClrLong := ControllerMapGui.AddButton("x+8 yp w70", "Clear")
 txtCustomLong := ControllerMapGui.AddText("xm y+6 w640", "")

 ; Bottom buttons
 btnSave := ControllerMapGui.AddButton("xm y+14 w140", "Save to INI")
 btnRevert := ControllerMapGui.AddButton("x+10 yp w140", "Revert")
 btnClose := ControllerMapGui.AddButton("x+10 yp w140", "Close")

 ; Store UI refs
 g_ControllerMapUI := Map()
 g_ControllerMapUI["gui"] := ControllerMapGui
 g_ControllerMapUI["lv"] := lv
 g_ControllerMapUI["buttons"] := buttons
 g_ControllerMapUI["txtSel"] := txtSel
 g_ControllerMapUI["cbShort"] := cbShort
 g_ControllerMapUI["cbLong"] := cbLong
 g_ControllerMapUI["txtCustomShort"] := txtCustomShort
 g_ControllerMapUI["txtCustomLong"] := txtCustomLong
 g_ControllerMapUI["selectedBtn"] := "A"

 ; Wire events
 lv.OnEvent("ItemSelect", ControllerMapUI_OnItemSelect)

 cbShort.OnEvent("Change", ControllerMapUI_OnShortChange)
 cbLong.OnEvent("Change", ControllerMapUI_OnLongChange)

 btnRecShort.OnEvent("Click", ControllerMapUI_OnRecShort)
 btnRecLong.OnEvent("Click", ControllerMapUI_OnRecLong)

 btnClrShort.OnEvent("Click", ControllerMapUI_OnClrShort)
 btnClrLong.OnEvent("Click", ControllerMapUI_OnClrLong)

 btnSave.OnEvent("Click", (*) => (SaveControllerMappingsToIni(), ControllerMapGui.Hide()))
 btnRevert.OnEvent("Click", (*) => (LoadControllerMappings(), ControllerMapUI_RefreshLv(), ControllerMapUI_UpdateEditor()))
 btnClose.OnEvent("Click", (*) => ControllerMapGui.Hide())

 ControllerMapGui.OnEvent("Close", (*) => ControllerMapGui.Hide())

 ControllerMapGui.OnEvent("Escape", (*) => ControllerMapGui.Hide())
 ; Initialize editor for first item
 ControllerMapUI_UpdateEditor()

 ControllerMapGui.Show("w680 Center")
}

; ==============================================================================
; Controller Mapping UI helpers (config window)
; ==============================================================================

ControllerMapUI_OnItemSelect(ctrl, item, selected) {
 try {
 global g_ControllerMapUI
 if !IsSet(g_ControllerMapUI)
 return
 if !selected
 return

 try g_ControllerMapUI["selectedBtn"] := ctrl.GetText(item, 1)
 ControllerMapUI_UpdateEditor()

 } catch {
 return
 }
}

ControllerMapUI_RefreshLv(*) {
 try {
 global g_ControllerMapUI
 if !IsSet(g_ControllerMapUI)
 return

 lv := g_ControllerMapUI["lv"]
 buttons := g_ControllerMapUI["buttons"]

 lv.Delete()
 for btn in buttons {
 lv.Add("", btn, ControllerBindingPretty(btn ".Short"), ControllerBindingPretty(btn ".Long"))
 }

 ; Reselect current button if possible
 sel := g_ControllerMapUI["selectedBtn"]
 row := 0
 Loop lv.GetCount() {
 if (lv.GetText(A_Index, 1) = sel) {
 row := A_Index
 break
 }
 }
 if (row = 0)
 row := 1
 lv.Modify(row, "Select Focus")

 } catch {
 return
 }
}

ControllerMapUI_UpdateEditor(*) {
 try {
 global g_ControllerMapUI
 if !IsSet(g_ControllerMapUI)
 return

 sel := g_ControllerMapUI["selectedBtn"]
 g_ControllerMapUI["txtSel"].Text := sel

 g_ControllerMapUI["cbShort"].Text := ControllerBindingChoice(sel ".Short")
 g_ControllerMapUI["cbLong"].Text := ControllerBindingChoice(sel ".Long")

 g_ControllerMapUI["txtCustomShort"].Text := ControllerCustomLine(sel ".Short", "Short")
 g_ControllerMapUI["txtCustomLong"].Text := ControllerCustomLine(sel ".Long", "Long")

 } catch {
 return
 }
}


; ----- Controller Mapping UI event wrappers (avoid .Bind / #Warn issues) -----
ControllerMapUI_OnShortChange(*) {
 try ControllerMapUI_ApplyChoice("Short")
}
ControllerMapUI_OnLongChange(*) {
 try ControllerMapUI_ApplyChoice("Long")
}
ControllerMapUI_OnRecShort(*) {
 try ControllerMapUI_Record("Short")
}
ControllerMapUI_OnRecLong(*) {
 try ControllerMapUI_Record("Long")
}
ControllerMapUI_OnClrShort(*) {
 try ControllerMapUI_Clear("Short")
}
ControllerMapUI_OnClrLong(*) {
 try ControllerMapUI_Clear("Long")
}
; --------------------------------------------------------------------------

ControllerMapUI_ApplyChoice(which, *) {
 try {
 global g_ControllerMapUI, ControllerMap, ControllerMapDisplay
 if !IsSet(g_ControllerMapUI)
 return

 sel := g_ControllerMapUI["selectedBtn"]
 key := sel "." which
 cb := (which = "Short") ? g_ControllerMapUI["cbShort"] : g_ControllerMapUI["cbLong"]
 choice := cb.Text

 if (choice = "Custom shortcut…") {
 res := RecordShortcutChord()
 if !res["ok"] {
 ; Revert selection to current binding
 cb.Text := ControllerBindingChoice(key)
 return
 }
 ControllerMap[key] := "Send:" res["send"]
 ControllerMapDisplay[key] := res["display"]
 } else {
 ControllerMap[key] := ChoiceToBinding(choice)
 try ControllerMapDisplay.Delete(key)
 }

 ControllerMapUI_RefreshLv()
 ControllerMapUI_UpdateEditor()

 } catch {
 return
 }
}

ControllerMapUI_Record(which, *) {
 try {
 global g_ControllerMapUI, ControllerMap, ControllerMapDisplay
 if !IsSet(g_ControllerMapUI)
 return

 sel := g_ControllerMapUI["selectedBtn"]
 key := sel "." which

 res := RecordShortcutChord()
 if !res["ok"]
 return

 ControllerMap[key] := "Send:" res["send"]
 ControllerMapDisplay[key] := res["display"]

 ; Keep dropdown consistent
 if (which = "Short")
 g_ControllerMapUI["cbShort"].Text := "Custom shortcut…"
 else
 g_ControllerMapUI["cbLong"].Text := "Custom shortcut…"

 ControllerMapUI_RefreshLv()
 ControllerMapUI_UpdateEditor()

 } catch {
 return
 }
}

ControllerMapUI_Clear(which, *) {
 try {
 global g_ControllerMapUI, ControllerMap, ControllerMapDisplay
 if !IsSet(g_ControllerMapUI)
 return

 sel := g_ControllerMapUI["selectedBtn"]
 key := sel "." which

 ControllerMap[key] := "Builtin:None"
 try ControllerMapDisplay.Delete(key)

 if (which = "Short")
 g_ControllerMapUI["cbShort"].Text := "None"
 else
 g_ControllerMapUI["cbLong"].Text := "None"

 ControllerMapUI_RefreshLv()
 ControllerMapUI_UpdateEditor()

 } catch {
 return
 }
}


ControllerBindingPretty(key) {
 global ControllerMap, ControllerMapDisplay
 v := GetBindingValue(key)
 if (v = "" || v = "Builtin:None")
 return "None"

 if (SubStr(v, 1, 5) = "Send:") {
 disp := ""
 disp := ""
 try disp := ControllerMapDisplay[key]
 if (disp = "")
 disp := SendToPretty(SubStr(v, 6))
 return "Shortcut: " disp
 }

 if (SubStr(v, 1, 8) = "Builtin:") {
 act := SubStr(v, 9)
 switch act {
 case "LeftClick": return "Left click"
 case "RightClick": return "Right click"
 case "Enter": return "Enter"
 case "Esc": return "Esc"
 case "AltF4": return "Alt+F4"
 case "WinG": return "Win+G"
 case "CtrlAltTab": return "Ctrl+Alt+Tab"
 case "TaskManager": return "Task Manager"
 case "StartMenu": return "Open Windows Start"
 case "Explorer": return "Open File Explorer"
 case "QuickMenu": return "Open Quick Menu"
 case "ControlPanel": return "Open Control Panel"
 case "TabTip": return "Open touch keyboard"
 case "OSK": return "Open OSK"
 case "None": return "None"
 default: return act
 }
 }
 return v
}

ControllerBindingChoice(key) {
 v := GetBindingValue(key)
 if (SubStr(v,1,5) = "Send:")
 return "Custom shortcut…"
 return ControllerBindingPretty(key)
}

ControllerCustomLine(key, which) {
 global ControllerMap, ControllerMapDisplay
 v := GetBindingValue(key)
 if (SubStr(v,1,5) != "Send:")
 return ""
 disp := ""
 disp := ""
 try disp := ControllerMapDisplay[key]
 if (disp = "")
 disp := SendToPretty(SubStr(v, 6))
 return which " shortcut: " disp
}

ChoiceToBinding(choice) {
 switch choice {
 case "None": return "Builtin:None"
 case "Left click": return "Builtin:LeftClick"
 case "Right click": return "Builtin:RightClick"
 case "Enter": return "Builtin:Enter"
 case "Esc": return "Builtin:Esc"
 case "Alt+F4": return "Builtin:AltF4"
 case "Win+G": return "Builtin:WinG"
 case "Ctrl+Alt+Tab": return "Builtin:CtrlAltTab"
 case "Task Manager": return "Builtin:TaskManager"
 case "Open Windows Start": return "Builtin:StartMenu"
 case "Open File Explorer": return "Builtin:Explorer"
 case "Open Quick Menu": return "Builtin:QuickMenu"
 case "Open Control Panel": return "Builtin:ControlPanel"
 case "Open touch keyboard":return "Builtin:TabTip"
 case "Open OSK": return "Builtin:OSK"
 default: return "Builtin:None"
 }
}


HideLiveLogWindow() {
 global LiveLogGui
 if IsSet(LiveLogGui) {
 try LiveLogGui.Hide()
 }
 EnsureLogRefreshTimer()
 EnsureStatusRefreshTimer()
}

CopyDetachedLog(*) {
 global LiveLogGui
 if !IsSet(LiveLogGui)
 return
 try A_Clipboard := LiveLogGui["detLogView"].Value
}

; ==============================================================================
; EXIT / RESTORE SHELL
; ==============================================================================
PrepareForDesktopRestore() {
 global AllowExplorer, QuickMenuVisible, MouseHidden
 AllowExplorer := true
 StopTaskbarGuard()
 ; Hands the wallpaper and desktop icons back before Explorer is restarted.
 StopDesktopBlackout()
 SystemCursor("Show")
 MouseHidden := false
 ReleasePinnedForeground(false)

 ; Stop anything that can hide, refocus, or manage Explorer while the normal
 ; Windows desktop is being brought back.
 SetTimer(MonitorShell, 0)
 SetTimer(WindowEngineTick, 0)
 SetTimer(MouseWatch, 0)
 SetTimer(PollController, 0)
 SetTimer(CheckLauncherCleanup, 0)

 if (QuickMenuVisible)
     HideQuickMenu(false)
}

ShowDesktopTaskbars() {
 for className in ["Shell_TrayWnd", "Shell_SecondaryTrayWnd"] {
     try {
         for hwnd in WinGetList("ahk_class " className)
             WinShow("ahk_id " hwnd)
     }
 }
}

ExitSteamAndRestoreDesktop() {
 global SteamPath

 steamPid := ProcessExist("steam.exe")
 if (!steamPid) {
     ExitToDesktop(false)
     return
 }

 steamExe := NormalizeMediaPath(SteamPath)
 if (steamExe = "" || !FileExist(steamExe)) {
     try steamExe := ProcessGetPath(steamPid)
 }
 ; These branches abandon the restore while the taskbar is still hidden, so they
 ; have to be visible. ShowNotification is log-only.
 if (steamExe = "" || !FileExist(steamExe)) {
     ShowNotification("Steam's executable could not be found. Desktop restore was cancelled.", "Warning")
     MsgBox(
         "Steam's executable could not be found, so it could not be asked to close.`n`n"
         . "Open Settings and select the correct Steam executable, or use System ▸ Exit SteamShell.",
         "SteamShell", "Iconx 262144")
     return
 }

 try {
     Run('"' steamExe '" -shutdown')
 } catch {
     ShowNotification("Steam could not be asked to close. Desktop restore was cancelled.", "Warning")
     MsgBox("Steam could not be asked to close. The desktop was not restored.",
         "SteamShell", "Iconx 262144")
     return
 }

 ShowNotification("Closing Steam and restoring the desktop…")
 deadline := A_TickCount + 20000
 while (ProcessExist("steam.exe") && A_TickCount < deadline)
     Sleep(250)

 if ProcessExist("steam.exe") {
     ShowNotification("Steam did not close within 20 seconds.", "Warning")
     result := MsgBox(
         "Steam did not close within 20 seconds.`n`n"
         . "Restore the Windows desktop anyway? Steam will be left running.",
         "SteamShell", "YesNo Icon! 262144")
     if (result != "Yes")
         return
 }

 ; MonitorShell normally reaches this same routine as soon as Steam closes.
 ; Call it directly as a fallback in case its timer has not run yet.
 ExitToDesktop(false)
}

DisarmSteamLifecycle() {
 ; Shell monitoring restores the desktop once Steam has stayed closed. After a
 ; restore that lifecycle has already been consumed, so clear it rather than
 ; relying on a stopped timer: re-arming it would immediately re-trigger.
 global SteamLaunched, SteamObservedRunning, SteamMissingSinceTick
 global SteamLaunchAttemptTick, SteamLaunchFailedReason
 SteamLaunched := false
 SteamObservedRunning := false
 SteamMissingSinceTick := 0
 SteamLaunchAttemptTick := 0
 SteamLaunchFailedReason := ""
}

EnterDesktopMode(reason := "") {
 global DesktopMode, QuickMenuVisible
 DesktopMode := true
 DisarmSteamLifecycle()
 HideStartupRecovery()
 ApplyRuntimeTimers()
 ReassertTrayIcon()
 SetSessionState("DESKTOP", reason != "" ? reason : "Explorer verified")
 LogLine(
     "Desktop mode active: Explorer owns the desktop and SteamShell remains "
     . "available from the notification area.")
 if (QuickMenuVisible)
     QuickMenuBuildGui()
}

ReturnToShellMode(reason := "") {
 global DesktopMode, AllowExplorer, SafeMode, SystemReady, QuickMenuVisible
 global SteamLaunched
 if (SafeMode) {
     ShowNotification(
         "Safe Mode keeps the Explorer desktop available. Restart SteamShell normally to resume the shell.",
         "Warning")
     return false
 }
 if (!DesktopMode)
     return true

 DesktopMode := false
 AllowExplorer := false
 SystemReady := true
 ; Nothing mutated the persisted feature flags, so re-arming is simply a
 ; question of rescheduling: ApplyRuntimeTimers restarts shell monitoring, the
 ; window engine, and the Taskbar Guard, which hides the taskbar immediately.
 ApplyRuntimeTimers()
 RefreshTrayMenu()
 SetSessionState("ACTIVE", reason != "" ? reason : "returned to SteamShell")
 LogLine("Returned to SteamShell presentation ("
     . (reason != "" ? reason : "user request") . ").")
 if (QuickMenuVisible)
     QuickMenuBuildGui()

 ; The taskbar is hidden again. If no Steam launch is in flight there is nothing
 ; for shell monitoring to observe, so offer the recovery screen rather than
 ; leaving the user on an empty guarded desktop.
 if (!SteamLaunched && !ProcessExist("steam.exe"))
     ShowStartupRecovery("Steam is not running. SteamShell has resumed its own presentation.")
 return true
}

LaunchSteamAndReturnToShell() {
 ; Re-arming is deliberately limited to a Steam launch SteamShell performed
 ; itself. Steam started by hand from the restored desktop leaves the user in
 ; desktop mode until they ask to go back.
 global DesktopMode
 if (!DesktopMode)
     return LaunchSteamBpm()
 if !LaunchSteamBpm() {
     failureReason := SteamLaunchFailedReasonText()
     DisarmSteamLifecycle()
     SetSessionState("DESKTOP", "Steam launch failed")
     ShowNotification("Steam could not be started. " . failureReason, "Warning")
     MsgBox(
         "Steam could not be started.`n`n" . failureReason
         . "`n`nSteamShell has stayed on the Windows desktop.",
         "SteamShell", "Iconx 262144")
     return false
 }
 ReturnToShellMode("Steam launched from SteamShell")
 return true
}

SteamLaunchFailedReasonText() {
 global SteamLaunchFailedReason
 return SteamLaunchFailedReason != ""
     ? SteamLaunchFailedReason
     : "Steam did not start successfully."
}

ExitSteamShell() {
 ; Never terminate while SteamShell still owns presentation: that would leave
 ; the user with a hidden taskbar and no shell. Restore the desktop first and
 ; exit as part of that same guarded transaction.
 global DesktopMode, IntentionalExitMode
 if (!DesktopMode) {
     ExitToDesktop(false, true)
     return
 }
 IntentionalExitMode := "session-desktop"
 LogLine("SteamShell exited by user request from desktop mode.")
 ExitApp()
}

ExitToDesktop(PermanentRestore := false, ExitAfterRestore := false) {
 global IntentionalExitMode
 static restoring := false
 if (restoring)
     return false
 restoring := true
 SetSessionState("RESTORING_DESKTOP", PermanentRestore ? "permanent" : "session")

 PrepareForDesktopRestore()
 if RestoreExplorerDesktop(PermanentRestore, &restoreMessage) {
     LogLine("Desktop restore completed: " restoreMessage)
     ; A permanent restore has deregistered SteamShell as the Windows shell, so
     ; the process has nothing left to own and exits. A session restore keeps
     ; SteamShell resident for its notification-area icon, controller mouse,
     ; and Quick Menu.
     if (PermanentRestore || ExitAfterRestore) {
         SetSessionState("DESKTOP", "Explorer verified")
         IntentionalExitMode := PermanentRestore ? "permanent-desktop" : "session-desktop"
         restoring := false
         ExitApp()
         return true
     }
     EnterDesktopMode("Explorer verified")
     restoring := false
     return true
 }

 restoring := false
 SetSessionState("RECOVERY", "desktop restore failed")
 LogLine("Desktop restore failed: " restoreMessage)
 ; Explorer may be dead here. Restore controller input so the Quick Menu and
 ; pointer emulation stay reachable while the user decides what to do.
 ResumeControllerPolling()
 if (ShowDesktopRestoreRecovery(restoreMessage) = "retry")
     return ExitToDesktop(PermanentRestore, ExitAfterRestore)
 return false
}

ResumeControllerPolling() {
 global EnableControllerMouseMode, EnableQuickMenu, ControllerPollIntervalMs
 global SettingsGui
 if (EnableControllerMouseMode || EnableQuickMenu || IsSet(SettingsGui))
     SetTimer(PollController, ControllerPollIntervalMs)
}

WriteAndVerifyShellValue(value, &errorMessage) {
 global ShellRegKey
 errorMessage := ""
 try {
     RegWrite(value, "REG_SZ", ShellRegKey, "Shell")
     actual := RegRead(ShellRegKey, "Shell")
     if (StrLower(Trim(actual)) != StrLower(Trim(value))) {
         errorMessage := "Windows did not retain the requested shell registry value."
         return false
     }
     return true
 } catch as err {
     errorMessage := "The shell registry value could not be written: " err.Message
     return false
 }
}

RestoreExplorerDesktop(PermanentRestore, &resultMessage) {
 global ConfiguredShellValue
 resultMessage := ""

 ; Set Explorer as the next shell before terminating or restarting anything.
 ; If the process dies during restoration, the next sign-in still has a safe
 ; path back to the standard Windows desktop.
 if !WriteAndVerifyShellValue("explorer.exe", &shellError) {
     resultMessage := shellError
     return false
 }

 try RunWait(A_ComSpec " /d /c taskkill /F /IM explorer.exe", , "Hide")
 taskbarReady := false
 launchError := ""
 Loop 3 {
     try {
         Run('"' A_WinDir '\explorer.exe"')
     } catch as err {
         launchError := err.Message
     }
     try taskbarReady := WinWait("ahk_class Shell_TrayWnd", , 8) != 0
     if (taskbarReady)
         break
     LogLine("Desktop restore: Explorer attempt " A_Index " did not create a taskbar.")
     try RunWait(A_ComSpec " /d /c taskkill /F /IM explorer.exe", , "Hide")
     Sleep(500)
 }

 if (!taskbarReady) {
     resultMessage := "Explorer did not create a taskbar after three attempts."
     if (launchError != "")
         resultMessage .= "`nLast launch error: " launchError
     return false
 }

 ShowDesktopTaskbars()
 Sleep(750)

 if (!PermanentRestore) {
     nextShell := Trim(ConfiguredShellValue) != "" ? ConfiguredShellValue : "explorer.exe"
     if !WriteAndVerifyShellValue(nextShell, &nextShellError) {
         ; The desktop is usable and Explorer remains the safe next-login shell.
         resultMessage := "Explorer is ready, but SteamShell could not restore the next-login shell setting. "
             . "Windows will start the normal desktop at the next sign-in. " nextShellError
         LogLine("Desktop restore warning: " resultMessage)
         return true
     }
 }

 resultMessage := PermanentRestore
     ? "Explorer is ready and remains the registered Windows shell."
     : "Explorer is ready; the configured SteamShell value is retained for the next sign-in."
 return true
}

ExitCleanup(ExitReason, ExitCode) {
 global IntentionalExitMode, DesktopMode, SafeMode
 global DisplayPendingOldMode, DisplayPendingOldScale, DisplayPendingUntilTick
 global ShellRegKey
 StopTaskbarGuard(true)
 ; Unhides Progman/WorkerW. An End Task cannot reach this, but that case is
 ; already covered: the unexpected-exit recovery below restarts Explorer, which
 ; recreates the desktop windows from scratch.
 StopDesktopBlackout(true)
 ShutdownRtssHooksApi()
 SystemCursor("Show")
 if IsObject(DisplayPendingOldMode) {
     oldMode := DisplayPendingOldMode
     oldScale := DisplayPendingOldScale
     DisplayPendingOldMode := 0
     DisplayPendingOldScale := 0
     DisplayPendingUntilTick := 0
     try ApplyPrimaryDisplayMode(oldMode)
     if IsObject(oldScale)
         try ApplyPrimaryDisplayScale(oldScale["percent"])
 }

 ; OnExit is not a substitute for a watchdog and cannot run after End Task.
 ; For ordinary unexpected exits, however, leave Windows with Explorer as the
 ; registered shell and make a best-effort attempt to start it.
 ;
 ; Desktop mode is excluded deliberately. There, Explorer is already the
 ; visible, healthy shell and the registry already holds the value the user
 ; asked for. Running the recovery would kill the desktop the user is working
 ; on and silently drop SteamShell as the next-sign-in shell.
 if (IntentionalExitMode = "" && !DesktopMode && !SafeMode
     && ExitReason != "Shutdown" && ExitReason != "Logoff"
     && ExitReason != "Single" && ExitReason != "Reload") {
     try RegWrite("explorer.exe", "REG_SZ", ShellRegKey, "Shell")
     ; Explorer may already be running in hidden "ghost" mode, so merely
     ; checking its process is insufficient. Restart it to recreate the taskbar.
     try RunWait(A_ComSpec " /d /c taskkill /F /IM explorer.exe", , "Hide")
     try Run('"' A_WinDir '\explorer.exe"')
     try LogLine("Unexpected SteamShell exit (" ExitReason "); Explorer recovery requested.")
 }
}

GetSteamShellCommandMode() {
 for _, arg in A_Args {
     value := StrLower(Trim(arg))
     if (value = "/install" || value = "--install")
         return "install"
     if (value = "/repair" || value = "--repair")
         return "repair"
     if (value = "/restore" || value = "--restore")
         return "restore"
     if (value = "/uninstall" || value = "--uninstall")
         return "uninstall"
     if (value = "/selftest" || value = "--selftest")
         return "selftest"
 }
 return ""
}

HasSteamShellArgument(argumentName) {
 target := StrLower(Trim(argumentName))
 for _, arg in A_Args {
     value := StrLower(Trim(arg))
     if (value = "/" target || value = "--" target)
         return true
 }
 return false
}

ApplySafeModeOverrides() {
 global SafeMode, AllowExplorer, SystemReady
 global EnableSplashScreen, EnableTaskbarHiding, EnableWindowManagement
 global EnableDesktopBlackout
 global EnableAutoHideCursor, EnableSteamRefocusMode, EnableGameForegroundAssist
 global EnableAlwaysFocus, EnableMouseParkOnBoot, EnableMouseParkOnFocusChange
 global EnableCursorHideOnBoot, EnableCursorHideOnRefocus
 global EnableLauncherCleanup, MouseHidden

 SafeMode := true
 AllowExplorer := true
 SystemReady := true
 EnableSplashScreen := false
 EnableTaskbarHiding := false
 EnableDesktopBlackout := false
 EnableWindowManagement := false
 EnableAutoHideCursor := false
 EnableSteamRefocusMode := false
 EnableGameForegroundAssist := false
 EnableAlwaysFocus := false
 EnableMouseParkOnBoot := false
 EnableMouseParkOnFocusChange := false
 EnableCursorHideOnBoot := false
 EnableCursorHideOnRefocus := false
 EnableLauncherCleanup := false
 if MouseHidden {
     SystemCursor("Show")
     MouseHidden := false
 }
}

StartSafeModeSession() {
 global AllowExplorer
 ApplySafeModeOverrides()
 SetSessionState("SAFE_MODE")
 AllowExplorer := true
 StopTaskbarGuard()
 StopDesktopBlackout()
 ShowDesktopTaskbars()
 if !ProcessExist("explorer.exe")
     try Run('"' A_WinDir '\explorer.exe"')
 LogLine("Safe Mode started: shell enforcement, startup programs, splash, focus automation, and cleanup are disabled.")
}

RestartSteamShellInSafeMode(*) {
 global IntentionalExitMode, SettingsEditorDirty
 if SettingsEditorDirty {
     saveResult := SettingsEditorMsgBox(
         "Save current changes before restarting in Safe Mode?",
         "YesNoCancel Icon?")
     if (saveResult = "Cancel")
         return
     if (saveResult = "Yes" && !SettingsEditorSave())
         return
 }
 result := SettingsEditorMsgBox(
     "Restart SteamShell in Safe Mode?`n`n"
     . "The Explorer desktop will remain available and automation modules will be disabled for this session.",
     "YesNo Icon?")
 if (result != "Yes")
     return
 commandLine := A_IsCompiled
     ? '"' A_ScriptFullPath '" /safe'
     : '"' A_AhkPath '" "' A_ScriptFullPath '" /safe'
 try {
     IntentionalExitMode := "safe-restart"
     Run(commandLine)
     ExitApp()
 } catch as err {
     IntentionalExitMode := ""
     SettingsEditorMsgBox("SteamShell could not restart in Safe Mode.`n`n" err.Message, "Iconx")
 }
}

RunSteamShellSelfTests(showResult := true) {
 global CurrentSettingsSchemaVersion
 failures := []

 normalizedExeList := ParseExeListPipe(
     "Steam.exe|Example App|STEAM.EXE|bad\path.exe|# ignored")
 if (normalizedExeList.Length != 3
     || normalizedExeList[1] != "steam.exe"
     || normalizedExeList[2] != "example app.exe"
     || normalizedExeList[3] != "steam.exe")
     failures.Push("ParseExeListPipe normalization")

 editorExeList := SettingsEditorParseExeList("One.exe|one.EXE|Two")
 if (editorExeList.Length != 2
     || StrLower(editorExeList[2]) != "two.exe")
     failures.Push("Settings EXE-list de-duplication")

 order := ParseQuickMenuMainOrder("System|Audio|Audio|Bogus")
 if (order.Length != 10 || order[1] != "system" || order[2] != "audio")
     failures.Push("Quick Menu order normalization")
 if (SendToPretty("^1") != "Ctrl+1"
     || SendToPretty("^2") != "Ctrl+2"
     || SendToPretty("+{Tab}") != "Shift+Tab")
     failures.Push("Shortcut display formatting")

 SplitTargetAndParams(
     '"C:\Program Files\Example\App.exe" --test value',
     &testTarget, &testParams)
 if (testTarget != "C:\Program Files\Example\App.exe"
     || testParams != "--test value")
     failures.Push("Startup command parsing")

 cpuPercent := CalculateProcessCpuPercent(5000000, 1000)
 if (Abs(cpuPercent - 50.0) > 0.01)
     failures.Push("GetProcessTimes CPU delta calculation")

 schema := GetDefaultSettingsSchema()
 seenSchema := Map()
 for _, option in schema {
     schemaKey := option["section"] Chr(31) option["key"]
     if seenSchema.Has(schemaKey)
         failures.Push("Duplicate embedded setting: " option["section"] "." option["key"])
     seenSchema[schemaKey] := true
 }
 if (schema.Length < 149)
     failures.Push("Embedded settings schema unexpectedly small")
 schemaVersion := 0
 for _, option in schema {
     if (option["section"] = "SteamShell" && option["key"] = "SettingsSchemaVersion")
         schemaVersion := ToInt(option["value"], 0)
 }
 if (schemaVersion != CurrentSettingsSchemaVersion)
     failures.Push("Embedded schema version mismatch")

 report := failures.Length
     ? "SteamShell self-test FAILED (" failures.Length ").`n`n- "
         . JoinWith(failures, "`n- ")
     : "SteamShell self-test passed.`n`n"
         . schema.Length " settings keys and core parser/recovery invariants were checked."
 if (showResult)
     MsgBox(report, "SteamShell Self-Test", failures.Length ? "Iconx" : "Iconi")
 return failures.Length = 0
}

InstallOrRepairSteamShell(isRepair := false, showResult := true) {
 global SettingsPath, SteamShellInstallDir, SteamShellInstalledExe
 global SteamShellRegKey, ShellRegKey, ConfiguredShellValue

 if !A_IsCompiled {
     if (showResult)
         MsgBox("Compile SteamShell first, then run the compiled EXE with /install.",
             "SteamShell Setup", "Icon!")
     return false
 }

 try {
     DirCreate(SteamShellInstallDir)

     if (StrLower(A_ScriptFullPath) != StrLower(SteamShellInstalledExe))
         FileCopy(A_ScriptFullPath, SteamShellInstalledExe, true)
     if !FileExist(SteamShellInstalledExe) || FileGetSize(SteamShellInstalledExe) <= 0
         throw Error("The installed SteamShell.exe could not be verified.")

     installedIni := SteamShellInstallDir "\SteamShellSettings.ini"
     if FileExist(SettingsPath) && !FileExist(installedIni)
         FileCopy(SettingsPath, installedIni, false)

     currentShell := "explorer.exe"
     try currentShell := RegRead(ShellRegKey, "Shell")
     if !InStr(StrLower(currentShell), "steamshell") {
         if (Trim(currentShell) = "")
             currentShell := "explorer.exe"
         RegWrite(currentShell, "REG_SZ", SteamShellRegKey, "PreviousShell")
     }

     installedCommand := '"' SteamShellInstalledExe '"'
     if !WriteAndVerifyShellValue(installedCommand, &shellError)
         throw Error(shellError)
     ConfiguredShellValue := installedCommand
     RegWrite(SteamShellInstalledExe, "REG_SZ", SteamShellRegKey, "InstalledPath")

     restoreShortcut := A_Programs "\Restore Windows Desktop.lnk"
     shortcutCreated := false
     try {
         FileCreateShortcut(
             SteamShellInstalledExe, restoreShortcut,
             SteamShellInstallDir, "/restore", "Permanently restore the Windows desktop")
         shortcutCreated := FileExist(restoreShortcut)
     }

     if (showResult) {
         action := isRepair ? "repaired" : "installed"
         shortcutText := shortcutCreated
             ? "An emergency Restore Windows Desktop shortcut was added to the Start menu."
             : "The Start menu recovery shortcut could not be created. You can still run:`n"
                 . SteamShellInstalledExe " /restore"
         MsgBox(
             "SteamShell was " action " successfully.`n`n"
             . "Installed location:`n" SteamShellInstalledExe
             . "`n`nThe change takes effect at the next sign-in. "
             . shortcutText,
             "SteamShell Setup", "Iconi")
     }
     if (!shortcutCreated)
         LogLine("SteamShell setup warning: Restore Windows Desktop shortcut was not created.")
     LogLine("SteamShell " (isRepair ? "repair" : "install") " completed: " SteamShellInstalledExe)
     return true
 } catch as err {
     if (showResult)
         MsgBox("SteamShell setup failed.`n`n" err.Message, "SteamShell Setup", "Iconx")
     LogLine("SteamShell setup failed: " err.Message)
     return false
 }
}

RemoveSteamShellRegistration(showResult := true) {
 global SteamShellRegKey
 if !RestoreExplorerDesktop(true, &restoreMessage) {
     if (showResult)
         MsgBox("SteamShell could not restore Explorer.`n`n" restoreMessage,
             "SteamShell Recovery", "Iconx")
     return false
 }

 try FileDelete(A_Programs "\Restore Windows Desktop.lnk")
 try RegDelete(SteamShellRegKey)
 if (showResult)
     MsgBox(
         "The normal Windows desktop has been restored permanently.`n`n"
         . "SteamShell's files were left in place so your settings and EXE are not deleted.",
         "SteamShell Recovery", "Iconi")
 return true
}

HandleSteamShellCommandMode() {
 global IntentionalExitMode
 mode := GetSteamShellCommandMode()
 if (mode = "")
     return false

 if (mode = "install")
     InstallOrRepairSteamShell(false, true)
 else if (mode = "repair")
     InstallOrRepairSteamShell(true, true)
 else if (mode = "restore")
     RemoveSteamShellRegistration(true)
 else if (mode = "uninstall")
     RemoveSteamShellRegistration(true)
 else if (mode = "selftest")
     RunSteamShellSelfTests(true)

 IntentionalExitMode := "command"
 ExitApp()
 return true
}

SettingsEditorInstallSteamShell(*) {
 InstallOrRepairSteamShell(false, true)
}

SettingsEditorRepairSteamShell(*) {
 InstallOrRepairSteamShell(true, true)
}

RegisterCurrentSteamShellAsShell(showResult := true) {
 global SteamShellRegKey, ShellRegKey, ConfiguredShellValue

 if !A_IsCompiled {
     if (showResult)
         SettingsEditorMsgBox(
             "Compile SteamShell first. The current script cannot be registered as the Windows shell.",
             "Icon!", "SteamShell Shell Registration")
     return false
 }

 currentExe := A_ScriptFullPath
 try {
     previousShell := "explorer.exe"
     try previousShell := RegRead(ShellRegKey, "Shell")
     if !InStr(StrLower(previousShell), "steamshell") {
         if (Trim(previousShell) = "")
             previousShell := "explorer.exe"
         RegWrite(previousShell, "REG_SZ", SteamShellRegKey, "PreviousShell")
     }

     shellCommand := '"' currentExe '"'
     if !WriteAndVerifyShellValue(shellCommand, &shellError)
         throw Error(shellError)
     ConfiguredShellValue := shellCommand
     RegWrite(currentExe, "REG_SZ", SteamShellRegKey, "RegisteredPath")

     restoreShortcut := A_Programs "\Restore Windows Desktop.lnk"
     shortcutCreated := false
     try {
         FileCreateShortcut(
             currentExe, restoreShortcut,
             A_ScriptDir, "/restore", "Permanently restore the Windows desktop")
         shortcutCreated := FileExist(restoreShortcut)
     }

     if (showResult) {
         shortcutText := shortcutCreated
             ? "An emergency Restore Windows Desktop shortcut was added to the Start menu."
             : "The recovery shortcut could not be created. You can still run:`n"
                 . currentExe " /restore"
         SettingsEditorMsgBox(
             "The current SteamShell EXE is now registered as the Windows shell.`n`n"
             . "Registered location:`n" currentExe
             . "`n`nThe change takes effect at the next sign-in. Do not move or delete this EXE while it is registered.`n`n"
             . shortcutText,
             "Iconi", "SteamShell Shell Registration")
     }
     if (!shortcutCreated)
         LogLine("Shell registration warning: Restore Windows Desktop shortcut was not created.")
     LogLine("Current EXE registered as Windows shell: " currentExe)
     return true
 } catch as err {
     if (showResult)
         SettingsEditorMsgBox(
             "SteamShell shell registration failed.`n`n" err.Message,
             "Iconx", "SteamShell Shell Registration")
     LogLine("Current-EXE shell registration failed: " err.Message)
     return false
 }
}

SettingsEditorRegisterCurrentShell(*) {
 result := SettingsEditorMsgBox(
     "Register this exact SteamShell EXE as the Windows shell?`n`n"
     . A_ScriptFullPath
     . "`n`nThis matches a direct Winlogon Shell registry file. "
     . "The EXE must remain at this location until Explorer is permanently restored.",
     "YesNo Icon?", "Register Current SteamShell EXE")
 if (result = "Yes")
     RegisterCurrentSteamShellAsShell(true)
}

SettingsEditorRestoreDesktop(*) {
 result := SettingsEditorMsgBox(
     "Permanently restore Explorer as the Windows shell?`n`n"
     . "SteamShell will close, and the normal desktop will be used at future sign-ins.",
     "YesNo Icon?")
 if (result = "Yes")
     ExitToDesktop(true)
}

; ==============================================================================

; ==============================================================================
; USER STARTUP PROGRAMS (HIDDEN)
; ==============================================================================
KickUserStartupPrograms() {
 global SettingsPath
 ; Optional user-defined hidden programs to start with the shell.
 enable := ToBool(IniReadS("StartupPrograms", "Enable", "false"), false)
 if (!enable)
 return

 delayMs := ToInt(IniReadS("StartupPrograms", "DelayMs", "2000"), 2000)
 delayMs := ClampInt(delayMs, 0, 600000)

 if (delayMs > 0) {
 SetTimer(StartUserStartupProgramsNow, -delayMs)
 } else {
 StartUserStartupProgramsNow()
 }
}

StartUserStartupProgramsNow() {
 global SettingsPath
 static started := false
 if (started)
 return
 started := true

 windowMode := IniReadS("StartupPrograms", "WindowMode", "Hidden")
 Loop 20 {
 k := "Program" A_Index
 cmdline := Trim(IniReadS("StartupPrograms", k, ""))
 if (cmdline = "")
 continue
 RunStartupCommandLine(cmdline, windowMode)
 }
}
; LAUNCHER CLEANUP (Optional)
; ==============================================================================
CheckLauncherCleanup() {
 global EnableLauncherCleanup, LauncherCleanupSteamForegroundSec, LauncherCleanupRequireNoGame, LauncherCleanupUseCpuAudio, LauncherCleanupDownloadGuard, LauncherCleanupDownloadGuardMode
 global LauncherCleanupCooldownSec, LauncherCleanupGracefulCloseMs, LauncherCleanupHardKill
 global LauncherCleanupLauncherList, LauncherCleanupBackgroundList, LauncherCleanupExcludeSet
 global LC_SteamFgSinceTick, LC_LastCleanupTick, LC_ConfigText, LC_FoundText, LC_GateText, LC_LastDecisionStamp, LC_LastDecisionText

 static inRun := false

 ; Build a one-line config summary for the Control Panel
 try {
     guardTxt := (LauncherCleanupDownloadGuard && LauncherCleanupDownloadGuardMode != "OFF") ? LauncherCleanupDownloadGuardMode : "Off"
     hkTxt := LauncherCleanupHardKill ? "true" : "false"
     LC_ConfigText := EnableLauncherCleanup ? ("Launcher Cleanup: ON (Guard=" guardTxt ", HardKill=" hkTxt ")") : "Launcher Cleanup: OFF"
 } catch {
     LC_ConfigText := EnableLauncherCleanup ? "Launcher Cleanup: ON" : "Launcher Cleanup: OFF"
 }

 ; Detect which launchers/helpers are currently running (by EXE lists)
 lProc := 0, lExe := 0, bProc := 0, bExe := 0
 launchTxt := GetRunningExeCountsText(LauncherCleanupLauncherList, &lProc, &lExe)
 backTxt := GetRunningExeCountsText(LauncherCleanupBackgroundList, &bProc, &bExe)
 LC_FoundText := "Launchers: " launchTxt " | Helpers: " backTxt

 anyTargets := ((lProc + bProc) > 0)

 if (!EnableLauncherCleanup) {
     LC_GateText := anyTargets ? "Disabled (targets running)" : "Disabled"
     return
 }

 if inRun {
     LC_GateText := "Running cleanup..."
    LC_RecordGateIfChanged("Running cleanup...", "running")
     return
 }

 if !IsSteamForeground() {
     LC_SteamFgSinceTick := 0
     LC_GateText := anyTargets ? "Waiting: Steam not foreground" : "Idle: no targets running"
    if (anyTargets)
        LC_RecordGateIfChanged("Waiting: Steam not foreground", "steam_not_fg")
    else
        LC_RecordGateIfChanged("Idle: no targets running", "idle_no_targets")
     return
 }

 if (!LC_SteamFgSinceTick) {
     LC_SteamFgSinceTick := A_TickCount
     LC_GateText := "Waiting: Steam foreground " LauncherCleanupSteamForegroundSec "s"
    LC_RecordGateIfChanged("Waiting: Steam foreground timer", "steam_fg_wait")
     return
 }

 needMs := LauncherCleanupSteamForegroundSec * 1000
 elapsed := A_TickCount - LC_SteamFgSinceTick
 if (elapsed < needMs) {
     rem := Ceil((needMs - elapsed) / 1000)
     LC_GateText := "Waiting: Steam foreground " rem "s remaining"
    LC_RecordGateIfChanged("Waiting: Steam foreground timer", "steam_fg_wait")
     return
 }

 if (LauncherCleanupCooldownSec > 0 && LC_LastCleanupTick && (A_TickCount - LC_LastCleanupTick) < (LauncherCleanupCooldownSec * 1000)) {
     rem := Ceil(((LauncherCleanupCooldownSec * 1000) - (A_TickCount - LC_LastCleanupTick)) / 1000)
     LC_GateText := "Cooldown: " rem "s remaining"
    LC_RecordGateIfChanged("Cooldown active", "cooldown")
     return
 }

 ; Nothing to close
 if (!anyTargets) {
     LC_GateText := "No launcher/helper processes detected"
    LC_RecordGateIfChanged("No launcher/helper processes detected", "no_targets")
     return
 }

 ; Optional gate: skip cleanup when a game appears to be running
 if (LauncherCleanupRequireNoGame) {
     try {
         if (LauncherCleanupUseCpuAudio) {
             ; CPU/Audio only gate (avoids "game-like window" false positives in Steam/BPM/launchers)
             if HasGameRunningRobust(LauncherCleanupExcludeSet, false) {
                 LC_GateText := "Blocked: game detected (CPU/audio)"
                 LC_LastDecisionStamp := NowStamp()
                 LC_LastDecisionText := "Skip (game detected)"
                 return
             }
         } else {
             if HasGameLikeWindow(LauncherCleanupExcludeSet) {
                 LC_GateText := "Blocked: game-like window detected"
                 LC_LastDecisionStamp := NowStamp()
                 LC_LastDecisionText := "Skip (game window)"
                 return
             }
         }
     } catch {
         ; Be conservative: if detection fails, skip cleanup.
         LC_GateText := "Blocked: game detection error"
         LC_LastDecisionStamp := NowStamp()
         LC_LastDecisionText := "Skip (detection error)"
         return
     }
 }

 ; Optional: skip cleanup if launchers appear busy (possible download/update)
 if (LauncherCleanupDownloadGuard && LauncherCleanupDownloadGuardMode != "OFF") {
     try {
         if LauncherCleanupBusyGuard(LauncherCleanupDownloadGuardMode, LauncherCleanupLauncherList, LauncherCleanupBackgroundList) {
             LC_GateText := "Blocked: launcher busy (download/update)"
             LC_LastDecisionStamp := NowStamp()
             LC_LastDecisionText := "Skip (busy guard)"
             return
         }
     } catch {
         LC_GateText := "Blocked: busy guard error"
         LC_LastDecisionStamp := NowStamp()
         LC_LastDecisionText := "Skip (busy guard error)"
         return
     }
 }

 ; Run cleanup
 LC_GateText := "Running cleanup..."
 inRun := true
 try {
     ; If any service-backed helpers are running, attempt to stop their services first (best-effort).
     needles := []
     for _, ex in LauncherCleanupBackgroundList {
         exl := StrLower(ex)
         ; Most service-backed helpers include "service" in the exe name (e.g., UbisoftConnectService.exe, EABackgroundService.exe)
         if InStr(exl, "service")
             needles.Push(exl)
     }
     if (needles.Length)
         StopRunningServicesByExeNeedles(needles)

     ; Close/kills summary counters (for Status panel last-action details)
     launcherRemovedTotal := 0
     helperRemovedTotal := 0
     launcherDetails := []
     helperDetails := []

     ; Close launcher UI processes first (graceful then optional kill)
     for _, exe in LauncherCleanupLauncherList {
         exl := StrLower(exe)
         removedThis := 0

         res := CloseExeProcesses(exe, true, LauncherCleanupGracefulCloseMs, LauncherCleanupHardKill, LauncherCleanupExcludeSet)
         if (IsObject(res) && res.Has("removed"))
             removedThis += res["removed"]

         ; EA App is notorious for "close-to-tray"/fast respawn. A couple extra passes help it stick.
         if (exl = "eadesktop.exe") {
             Sleep(400)
             res2 := CloseExeProcesses(exe, true, 0, LauncherCleanupHardKill, LauncherCleanupExcludeSet)
             if (IsObject(res2) && res2.Has("removed"))
                 removedThis += res2["removed"]

             Sleep(400)
             res3 := CloseExeProcesses(exe, false, 0, LauncherCleanupHardKill, LauncherCleanupExcludeSet)
             if (IsObject(res3) && res3.Has("removed"))
                 removedThis += res3["removed"]
         }

         if (removedThis > 0) {
             launcherRemovedTotal += removedThis
             launcherDetails.Push(exe " x" removedThis)
         }
     }

     ; Then close background service/helper processes (typically no windows)
     for _, exe in LauncherCleanupBackgroundList {
         removedThis := 0
         res := CloseExeProcesses(exe, false, 0, LauncherCleanupHardKill, LauncherCleanupExcludeSet)
         if (IsObject(res) && res.Has("removed"))
             removedThis += res["removed"]

         if (removedThis > 0) {
             helperRemovedTotal += removedThis
             helperDetails.Push(exe " x" removedThis)
         }
     }

LC_LastCleanupTick := A_TickCount
     LC_LastDecisionStamp := NowStamp()
LC_LastDecisionText := "Cleanup: removed L=" launcherRemovedTotal ", H=" helperRemovedTotal
try {
    det := ""
    if (launcherDetails.Length) {
        det := "L: " JoinDetails(launcherDetails, 3)
    }
    if (helperDetails.Length) {
        if (det != "")
            det .= "; "
        det .= "H: " JoinDetails(helperDetails, 3)
    }
    if (det != "")
        LC_LastDecisionText .= " [" det "]"
} catch {
}

     ; Refresh detection text after cleanup so the panel shows what remains.
     lProc2 := 0, lExe2 := 0, bProc2 := 0, bExe2 := 0
     launchTxt2 := GetRunningExeCountsText(LauncherCleanupLauncherList, &lProc2, &lExe2)
     backTxt2 := GetRunningExeCountsText(LauncherCleanupBackgroundList, &bProc2, &bExe2)
     LC_FoundText := "Launchers: " launchTxt2 " | Helpers: " backTxt2

     if ((lProc2 + bProc2) > 0)
         LC_GateText := "Cleanup ran, but some processes remain"
     else
         LC_GateText := "Cleanup completed (no targets running)"

     removedTotal := launcherRemovedTotal + helperRemovedTotal
     if (removedTotal > 0)
         ShowNotification("Launcher cleanup removed " removedTotal " process" (removedTotal = 1 ? "" : "es"), "Success")
 } finally {
     inRun := false
 }
}


HasGameLikeWindow(excludeSet) {
 global FullscreenTolerance, FullscreenPosTolerancePx
 global LauncherCleanupLauncherList, LauncherCleanupBackgroundList

 ; Build an ignore set (lowercase exe names) so we don't treat Steam/launchers as "games"
 ignore := Map()
 if (IsObject(excludeSet)) {
     for k, _ in excludeSet
         ignore[k] := true
 }
 ; Also ignore the launchers/helpers we intend to close
 if (IsObject(LauncherCleanupLauncherList)) {
     for _, ex in LauncherCleanupLauncherList
         ignore[StrLower(ex)] := true
 }
 if (IsObject(LauncherCleanupBackgroundList)) {
     for _, ex in LauncherCleanupBackgroundList
         ignore[StrLower(ex)] := true
 }

 ; Always ignore Steam + overlay + ourself
 ignore["steam.exe"] := true
 ignore["steamwebhelper.exe"] := true
 ignore["gameoverlayui.exe"] := true
 ignore["steamshell.exe"] := true

 for _, item in WindowEngineGetFreshSnapshot() {
     minimizedLegacyGame := WindowEngineIsMinimizedLegacyGameSurface(item)
     legacySurface := WindowEngineIsLegacyApplicationSurface(item)
         || minimizedLegacyGame
     if (item["scriptOwned"] || item["desktop"] || item["bpm"]
         || (item["minMax"] = -1 && !minimizedLegacyGame)
         || (item["title"] = "" && !legacySurface)
         || item["proc"] = "" || ignore.Has(item["proc"]))
         continue
     nearFS := minimizedLegacyGame
         || (item["w"] >= (A_ScreenWidth * FullscreenTolerance)
             && item["h"] >= (A_ScreenHeight * FullscreenTolerance)
             && Abs(item["x"]) <= FullscreenPosTolerancePx
             && Abs(item["y"]) <= FullscreenPosTolerancePx)
     bigBorderless := !minimizedLegacyGame
         && item["w"] >= (A_ScreenWidth * 0.90)
         && item["h"] >= (A_ScreenHeight * 0.90)
     if (nearFS || bigBorderless)
         return true
 }
 return false
}

HasGameRunningRobust(excludeSet, useWindowHeuristic := true) {
 ; More reliable "game running" detection for Launcher Cleanup:
 ; 1) Fast window-size check (fullscreen / big borderless)
 ; 2) Active audio session (peak meter) from non-launcher, non-Steam processes
 ; 3) CPU usage threshold from non-launcher, non-Steam processes

 global LauncherCleanupCpuThreshold, LauncherCleanupAudioPeakThreshold
 global LauncherCleanupLauncherList, LauncherCleanupBackgroundList

 ; Optional fast path: fullscreen/borderless window present
 if (useWindowHeuristic && HasGameLikeWindow(excludeSet))
     return true

 ; Build a unified ignore set by EXE name (lowercase)
 ignore := Map()
 if IsObject(excludeSet) {
 for k, _ in excludeSet
 ignore[k] := true
 }

 for _, ex in LauncherCleanupLauncherList
     ignore[StrLower(ex)] := true
 for _, ex in LauncherCleanupBackgroundList
     ignore[StrLower(ex)] := true

 ; Always ignore Steam + ourself + audio engine
 ignore["steam.exe"] := true
 ignore["steamwebhelper.exe"] := true
 ignore["steamshell.exe"] := true
 ignore["audiodg.exe"] := true

 audioMap := 0
 try audioMap := GetActiveAudioPidPeaksCached()
 catch {
     audioMap := 0
 }

 ; Audio heuristic: any non-ignored pid with peak above threshold means "something game-like is still active"
 if (IsObject(audioMap) && LauncherCleanupAudioPeakThreshold > 0) {
     for pid, peak in audioMap {
         if (pid <= 0)
             continue
         if ((peak + 0) < LauncherCleanupAudioPeakThreshold)
             continue

         proc := ""
         try proc := StrLower(ProcessGetName(pid))
         catch {
             proc := ""
         }

         if (proc = "" || ignore.Has(proc))
             continue

         return true
     }
 }

 ; CPU heuristic: any non-ignored pid above threshold means "something heavy is still active"
 if (LauncherCleanupCpuThreshold <= 0)
 return false

 pids := Map()

 ; Collect pids from visible windows (covers most games even if minimized)
 for _, item in WindowEngineGetFreshSnapshot() {
     if item["pid"]
         pids[item["pid"]] := true
 }

 ; Also include audio pids (covers some cases where window is hidden/minimized)
 if IsObject(audioMap) {
 for pid, _ in audioMap
 if (pid)
 pids[pid] := true
 }

 for pid, _ in pids {
 proc := ""
 try proc := StrLower(ProcessGetName(pid))
 catch {
     proc := ""
 }

 if (proc = "" || ignore.Has(proc))
 continue

 cpuSample := GetProcessCpuSample(pid)
 ; A first sample has no delta yet. Treat it as busy for one cleanup cycle
 ; rather than risk closing a launcher while a game process is still active.
 if !cpuSample["known"] {
     if cpuSample.Has("creation")
         return true
     continue
 }
 if (cpuSample["usage"] >= LauncherCleanupCpuThreshold)
     return true
 }

 return false
}


; Attempt to stop any running Windows services whose PathName contains any of the provided exe substrings.
; Best-effort; may require admin/service permissions. "needles" should be lowercase exe names, e.g. ["eabackgroundservice.exe"].
StopRunningServicesByExeNeedles(needles) {
 if !IsObject(needles)
     return 0
 if (needles.Length = 0)
     return 0

 stopped := 0
 try {
     wmi := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
     svcs := wmi.ExecQuery("SELECT * FROM Win32_Service WHERE State='Running'")
     for svc in svcs {
         path := ""
         try path := svc.PathName ""
         catch {
             path := ""
         }
         if (path = "")
             continue

         pl := StrLower(path)
         hit := false
         for _, needle in needles {
             if (needle != "" && InStr(pl, needle)) {
                 hit := true
                 break
             }
         }
         if !hit
             continue

         try {
             svc.StopService()
             stopped += 1
         } catch {
             ; ignore
         }
     }
 } catch {
     return stopped
 }

 if (stopped)
     Sleep(750)

 return stopped
}







JoinDetails(arr, maxItems := 3) {
 if (!IsObject(arr) || arr.Length = 0)
     return ""
 out := ""
 lim := Min(arr.Length, maxItems)
 Loop lim {
     if (A_Index > 1)
         out .= ", "
     out .= arr[A_Index]
 }
 if (arr.Length > maxItems)
     out .= ", +" (arr.Length - maxItems) " more"
 return out
}

CloseExeProcesses(exeName, tryWinClose := true, gracefulMs := 2000, hardKill := true, excludeSet := 0) {
 if (exeName = "")
     return Map("before", 0, "after", 0, "removed", 0)

 exe := StrLower(Trim(exeName))
 if !InStr(exe, ".exe")
     exe .= ".exe"

 if (IsObject(excludeSet) && excludeSet.Has(exe))
     return Map("before", 0, "after", 0, "removed", 0)

 ; Track process count before attempting to close/kill (for status summaries)
 beforeCount := 0
 try {
     beforeCount := GetPidsByExeName(exe).Length
 } catch {
     beforeCount := 0
 }

 ; Try to close any windows first (best-effort)
 if (tryWinClose) {
     try {
         for hwnd in WinGetList("ahk_exe " exe) {
             try WinClose("ahk_id " hwnd)
         }
     } catch {
     }
     if (gracefulMs > 0)
         Sleep(gracefulMs)
 }

 if (!hardKill) {
     ; Report what changed just from WinClose (best-effort)
     afterCount := 0
     try afterCount := GetPidsByExeName(exe).Length
     catch {
     afterCount := 0
 }
     removed := beforeCount - afterCount
     if (removed < 0)
         removed := 0
     return Map("before", beforeCount, "after", afterCount, "removed", removed)
 }

 ; Best-effort: stop known services before killing service-backed executables.
 if (exe = "ubisoftconnectservice.exe") {
     try RunWait(A_ComSpec " /c sc stop UbisoftConnectService", , "Hide")
     Sleep(750)
 } else if (exe = "eabackgroundservice.exe") {
     try RunWait(A_ComSpec " /c sc stop EABackgroundService", , "Hide")
     Sleep(750)
 }

 ; Kill remaining processes by name (best-effort)
 for _, pid in GetPidsByExeName(exe) {
     try ProcessClose(pid)

     ; EA App can respawn quickly; PID-based taskkill helps ensure it actually exits.
     if (exe = "eadesktop.exe" || exe = "ealauncher.exe" || exe = "origin.exe") {
         try RunWait(A_ComSpec " /c taskkill /F /T /PID " pid, , "Hide")
     }
 }

 ; Last resort: taskkill by image name (handles cases where PID enumeration fails)
 try RunWait(A_ComSpec " /c taskkill /F /T /IM " exe, , "Hide")

 ; Compute how many remain after close/kill (best-effort)
 afterCount := 0
 try {
     afterCount := GetPidsByExeName(exe).Length
 } catch {
     afterCount := 0
 }
 removed := beforeCount - afterCount
 if (removed < 0)
     removed := 0
 return Map("before", beforeCount, "after", afterCount, "removed", removed)
}


GetPidsByExeName(exeName) {
 pids := []
 exe := StrLower(Trim(exeName))
 if (exe = "")
     return pids
 if !InStr(exe, ".exe")
     exe .= ".exe"

 ; Prefer Toolhelp snapshot enumeration (more reliable than WMI for some launchers)
 snap := DllCall("CreateToolhelp32Snapshot", "UInt", 0x00000002, "UInt", 0, "Ptr") ; TH32CS_SNAPPROCESS
 if (snap = -1 || snap = 0)
     return pids

 size := (A_PtrSize = 8) ? 568 : 556 ; PROCESSENTRY32W
 pe := Buffer(size, 0)
 NumPut("UInt", size, pe, 0)

 if !DllCall("Process32FirstW", "Ptr", snap, "Ptr", pe) {
     DllCall("CloseHandle", "Ptr", snap)
     return pids
 }

 loop {
     pid := NumGet(pe, 8, "UInt")
     name := StrLower(StrGet(pe.Ptr + ((A_PtrSize = 8) ? 44 : 36), "UTF-16"))
     if (name = exe)
         pids.Push(pid)
     if !DllCall("Process32NextW", "Ptr", snap, "Ptr", pe)
         break
 }

 DllCall("CloseHandle", "Ptr", snap)
 return pids
}


GetRunningExeCountsText(exeList, &procCount, &exeCount, maxItems := 4) {
    procCount := 0
    exeCount := 0
    if (!IsObject(exeList))
        return "None"

    parts := []
    for _, ex in exeList {
        pids := []
        try {
            pids := GetPidsByExeName(ex)
        } catch {
            pids := []
        }

        c := 0
        try {
            c := (IsObject(pids) ? pids.Length : 0)
        } catch {
            c := 0
        }

        if (c > 0) {
            exeCount += 1
            procCount += c
            if (parts.Length < maxItems)
                parts.Push(ex " (" c ")")
        }
    }

    if (exeCount <= 0)
        return "None"

    out := ""
    for i, p in parts
        out .= (i > 1 ? ", " : "") p
    if (exeCount > maxItems)
        out .= ", +" (exeCount - maxItems) " more"
    return out
}


; ==============================================================================
; Launcher Cleanup — Download/Update Guard (Disk I/O heuristic)
; ------------------------------------------------------------------------------
; If enabled, SteamShell will skip Launcher Cleanup when launcher/helper processes
; appear to be actively downloading/updating (sustained write I/O).
; ==============================================================================
LauncherCleanupBusyGuard(mode, launcherList, backgroundList) {
    global LauncherCleanupCheckIntervalMs

    static lastWrite := Map()     ; pid -> last WriteTransferCount (bytes)
    static lastTick  := Map()     ; pid -> last sample tick
    static busySec   := Map()     ; pid -> consecutive "busy" seconds
    static lastLogTick := 0

    ; Normalize mode
    m := StrUpper(Trim(mode))
    if (m = "" || m = "OFF")
        return false

    ; Internal presets (keep user-facing settings simple)
    ; Balanced: catch real installs/downloads without being overly sensitive
    ; Strict:   more conservative (more likely to skip cleanup)
    thresholdBps := (m = "STRICT") ? (64 * 1024) : (256 * 1024)  ; bytes/sec
    windowSec    := (m = "STRICT") ? 10 : 6                      ; required sustained busy time

    ; Collect current PIDs for launcher + helpers
    pids := Map()
    if (IsObject(launcherList)) {
        for _, exe in launcherList {
            for _, pid in GetPidsByExeName(exe)
                pids[pid] := true
        }
    }
    if (IsObject(backgroundList)) {
        for _, exe in backgroundList {
            for _, pid in GetPidsByExeName(exe)
                pids[pid] := true
        }
    }

    ; Nothing to guard against
    if (pids.Count = 0)
        return false

    now := A_TickCount
    needWarmup := false
    anyReadable := false
    isBusy := false

    ; Remove stale PIDs from state maps
    stale := []
    for pid, _ in lastWrite {
        if !pids.Has(pid)
            stale.Push(pid)
    }
    for _, pid in stale {
        try lastWrite.Delete(pid)
        try lastTick.Delete(pid)
        try busySec.Delete(pid)
    }

    ; Sample each PID once (non-blocking)
    for pid, _ in pids {
        w := GetProcessWriteTransferBytes(pid)
        if (w < 0) {
            ; Can't read this process (permissions, exited, etc.) — don't block cleanup.
            continue
        }
        anyReadable := true

        if (!lastWrite.Has(pid) || !lastTick.Has(pid)) {
            ; First observation — set baseline, delay cleanup until next check.
            lastWrite[pid] := w
            lastTick[pid] := now
            busySec[pid] := 0
            needWarmup := true
            continue
        }

        prevW := lastWrite[pid]
        prevT := lastTick[pid]
        dt := (now - prevT) / 1000.0
        if (dt <= 0)
            dt := (LauncherCleanupCheckIntervalMs > 0) ? (LauncherCleanupCheckIntervalMs / 1000.0) : 2.0
        if (dt > 30)
            dt := 2.0

        delta := w - prevW
        if (delta < 0)
            delta := 0

        bps := delta / dt

        lastWrite[pid] := w
        lastTick[pid] := now

        if (bps >= thresholdBps) {
            busySec[pid] := busySec.Has(pid) ? (busySec[pid] + dt) : dt
            if (busySec[pid] >= windowSec) {
                isBusy := true
                break
            }
        } else {
            busySec[pid] := 0
        }
    }

    ; A safety guard must fail closed. If process counters are inaccessible,
    ; defer cleanup rather than guessing that a download is not active.
    if (!anyReadable)
        return true

    ; If we need warmup (first baseline), delay cleanup briefly but don't spam logs.
    if (needWarmup)
        return true

    if (isBusy) {
        if ((now - lastLogTick) > 15000) {
            LogLine("LauncherCleanup: skipped (launcher busy: possible download/update)")
            lastLogTick := now
        }
        return true
    }

    return false
}

GetProcessWriteTransferBytes(pid) {
    ; Returns WriteTransferCount (bytes) from GetProcessIoCounters(), or -1 on failure.
    static PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    static PROCESS_QUERY_INFORMATION := 0x0400

    h := DllCall("OpenProcess", "UInt", PROCESS_QUERY_LIMITED_INFORMATION, "Int", false, "UInt", pid, "Ptr")
    if (!h)
        h := DllCall("OpenProcess", "UInt", PROCESS_QUERY_INFORMATION, "Int", false, "UInt", pid, "Ptr")
    if (!h)
        return -1

    buf := Buffer(48, 0) ; IO_COUNTERS = 6 * ULONGLONG
    ok := DllCall("GetProcessIoCounters", "Ptr", h, "Ptr", buf, "Int")
    DllCall("CloseHandle", "Ptr", h)

    if (!ok)
        return -1

    ; Offsets: 0 ReadOps, 8 WriteOps, 16 OtherOps, 24 ReadBytes, 32 WriteBytes, 40 OtherBytes
    return NumGet(buf, 32, "UInt64")
}


RunStartupCommandLine(cmdline, windowMode := "Hidden") {
 target := ""
 params := ""
 SplitTargetAndParams(cmdline, &target, &params)

 ; Build a safe command line. Quote the exe path so spaces are handled.
 runCmd := ""
 if (target != "") {
 runCmd := '"' target '"'
 if (params != "")
 runCmd .= " " params
 } else {
 runCmd := cmdline
 }

 normalizedMode := StrLower(Trim(windowMode))
 runOptions := normalizedMode = "normal"
     ? "" : (normalizedMode = "minimized" ? "Min" : "Hide")
 pid := 0
 try {
 Run(runCmd, , runOptions, &pid)
 } catch {
 ; Fallback: try as-is (Windows will parse it).
 try Run(cmdline, , runOptions, &pid)
 }

 if (pid && normalizedMode = "hidden")
 SetTimer(() => HideWindowsForPid(pid), -200)
 return pid != 0
}

SplitTargetAndParams(cmdline, &target, &params) {
 ; Parses: "C:\Path To\App.exe" args... OR C:\Path\App.exe args...
 s := Trim(cmdline)
 target := s
 params := ""

 if (s = "")
 return

 if (SubStr(s, 1, 1) = '"') {
 q := InStr(s, '"', , 2)
 if (q > 1) {
 target := SubStr(s, 2, q - 2)
 params := Trim(SubStr(s, q + 1))
 return
 }
 }

 sp := InStr(s, " ")
 if (sp > 0) {
 target := SubStr(s, 1, sp - 1)
 params := Trim(SubStr(s, sp + 1))
 }
}

HideWindowsForPid(pid) {
 ; Some apps ignore Run(..., "Hide"). Try to hide any visible top-level windows for a short time.
 try {
 Loop 10 {
 for _, hwnd in WinGetList("ahk_pid " pid) {
 try WinHide(hwnd)
 }
 Sleep(150)
 }
 } catch {
 }
}


ArmSplashAutoClose() {
 global EnableSplashScreen, SplashScreenDuration, SplashMode, SplashVideoPlayFull, SplashVideoSafetyMaxMs
 if (!EnableSplashScreen)
 return

 mode := StrLower(Trim(SplashMode))
 if (mode = "video" && SplashVideoPlayFull) {
 ; Let SplashMonitorExternalVideoEnd close it; also schedule a safety timeout.
 SetTimer(SplashMonitorExternalVideoEnd, 200)
 SetTimer(SplashForceClose, -SplashVideoSafetyMaxMs)
 return
 }

 ; Timed close (Black mode or timed video)
 SetTimer(FadeOutSplash, -SplashScreenDuration)
}
; STARTUP SEQUENCE
; ==============================================================================
SafeMode := HasSteamShellArgument("safe")
if HandleSteamShellCommandMode()
 return

InitDpiAwareness()
EnsureSettingsIniExists()
EnsureSettingsIniUnicode()
SyncSettingsIniSchema()
LoadSettings()

; Registered before Explorer is started so the TaskbarCreated broadcast that
; accompanies the first taskbar is never missed. Winlogon starts SteamShell
; before any shell exists, so the icon's first Shell_NotifyIcon attempt always
; fails and the broadcast is what actually places it.
InitializeTrayMenu()

if SafeMode {
 StartSafeModeSession()
} else {
 KickUserStartupPrograms()

 LastMouseMoveTick := A_TickCount
 try MouseGetPos(&LastMouseX, &LastMouseY)
 SteamRefocusTimer := A_TickCount

 if (EnableMouseParkOnBoot) {
  ParkMouseRightEdge()
 } else if (EnableCursorHideOnBoot) {
  HideCursorWithoutInput(true)
 }

 if (EnableSplashScreen)
  ShowSplash()
 else
  SetSystemReady()

 ; Launch Explorer if not running (Game Bar hooks)
 if !ProcessExist("explorer.exe")
  try Run("explorer.exe")

 ; Launch Steam BPM. A failed launch remains in SteamShell and presents a
 ; controller-friendly recovery screen after the splash is out of the way.
 if (!SteamLaunched && !LaunchSteamBpm()) {
  recoveryDelay := EnableSplashScreen
      ? Min(SteamStartupGraceMs, SplashScreenDuration + SplashFadeOutMs + 750)
      : 250
  SetTimer(ShowPendingStartupRecovery, -Max(250, recoveryDelay))
 }

 if (EnableSplashScreen)
  ArmSplashAutoClose()
}

ApplyRuntimeTimers()

; Hotkeys (registered dynamically so they never break if code is refactored into functions)
Hotkey("^!+e", (*) => ExitToDesktop(true))
Hotkey("^!+r", (*) => ReloadSettings())
Hotkey("^!+g", (*) => ForceGameAssistOnce())
Hotkey("^!+p", (*) => ShowControlPanel())
Hotkey("^!+q", (*) => ToggleQuickMenu())
Hotkey("^!+s", (*) => ShowSettingsEditor())
RegisterQuickMenuKeys()

if SafeMode
 SetTimer(ShowSettingsEditor, -400)
