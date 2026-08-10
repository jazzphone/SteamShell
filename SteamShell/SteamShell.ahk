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
; Ctrl+Alt+Shift+I => Re-arm controller input after a backend stall
; Ctrl+Alt+Shift+D => Delete the learned controller profile for this device
; ==============================================================================
#Requires AutoHotkey v2.0.19 64-bit
#SingleInstance Force

; Shared function definitions, compiled into both trees. See the file header
; for the rules and for the per-tree seam it depends on.
#Include SteamShell-Common.ahk
#Include SteamShell-Shared.ahk
;@Ahk2Exe-SetName SteamShell
;@Ahk2Exe-SetDescription Steam Big Picture living-room Windows shell
;@Ahk2Exe-SetVersion 2.0.1.0
global SteamShellVersion := "2.0.1"
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
global ShellRegKey := "HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
global SteamShellRegKey := "HKEY_CURRENT_USER\Software\SteamShell"
global SteamShellProgramData := EnvGet("PROGRAMDATA")
if (SteamShellProgramData = "")
    SteamShellProgramData := A_AppDataCommon
global SteamShellInstallDir := A_ProgramFiles "\SteamShell"
global SteamShellInstalledExe := SteamShellInstallDir "\SteamShell.exe"
global SteamShellDataDir := A_ScriptDir "\SteamShell"
global SteamShellInstallationMode := "Portable"
global SteamShellManagedPathMatched := false

; A managed installation records its writable data directory in HKCU. Only
; trust that record when it belongs to this exact executable; otherwise a
; portable/test copy must remain isolated from the installed shell's settings.
try {
    recordedExe := RegRead(SteamShellRegKey, "InstalledPath")
    recordedDataDir := RegRead(SteamShellRegKey, "DataPath")
    if (recordedExe != "" && recordedDataDir != ""
        && StrLower(recordedExe) = StrLower(A_ScriptFullPath)) {
        SteamShellInstalledExe := recordedExe
        SteamShellInstallDir := RegExReplace(recordedExe, "\\[^\\]+$")
        SteamShellDataDir := recordedDataDir
        SteamShellInstallationMode := RegRead(
            SteamShellRegKey, "InstallationMode", "Standard")
        SteamShellManagedPathMatched := true
    }
}

; Preserve the original beside-the-EXE layout until the user deliberately runs
; Setup Assistant. New portable installs use the SteamShell sidecar directory.
if !SteamShellManagedPathMatched
    && !FileExist(A_ScriptDir "\SteamShell\SteamShellSettings.ini")
    && FileExist(A_ScriptDir "\SteamShellSettings.ini") {
    SteamShellDataDir := A_ScriptDir
    SteamShellInstallationMode := "Legacy Portable"
}
try DirCreate(SteamShellDataDir)
try DirCreate(SteamShellDataDir "\logs")
try DirCreate(SteamShellDataDir "\backups")
global SettingsPath := SteamShellDataDir "\SteamShellSettings.ini"
; Back-compat alias used by some helper functions
global IniPath := SettingsPath
global CurrentSettingsSchemaVersion := 23
global LogPath := SteamShellDataDir "\logs\SteamShell.log"
global IntentionalExitMode := ""
global SafeMode := false
global FirstRunSetupMode := false
global SessionState := "STARTING"
global ElevatedHelperPath := ""
global ElevatedHelperPid := 0
global ElevatedHelperAvailable := false
global ElevatedHelperLastError := "Not started"
global ElevatedHelperExpectedVersion := "2.0.1.1"
; SteamShell.exe installs either product, so it embeds the XFE companion the same
; way it embeds the elevated helper. "Standalone" replaces the Windows shell;
; "XFE" runs alongside Xbox Full Screen Experience at normal integrity.
global XfeExpectedVersion := "2.0.1.0"
global SteamShellProduct := "Standalone"
global ElevatedGeometryEventHandle := 0
; Publishes AutoMouseModeActive() to the elevated helper. See
; SetElevatedAutoMouseRuntimeEnabled for why the helper cannot work it out.
global ElevatedAutoMouseEventHandle := 0
global ElevatedRtssEventHandle := 0
global ElevatedRtssDoneEventHandle := 0
global RtssElevatedRequestSeq := 0

; SteamShell itself remains at the interactive user's normal integrity so its
; Quick Menu and settings windows correctly take controller focus away from
; Steam. A separate, narrowly scoped elevated helper handles controller input
; and window geometry that UIPI blocks on High/System-integrity applications.
global ExpectedInteractiveUserSid := ""
global ExpectedInteractiveSessionId := -1
global StandardLaunchLastRoute := "Not used"
global StandardLaunchLastError := ""
global StandardLaunchSuccessCount := 0
global StandardLaunchFailureCount := 0
global StandardLaunchTrackedProcesses := Map()

; Cache our own PID once so window-management can reliably ignore this script's GUIs.
global ScriptPid := DllCall("GetCurrentProcessId", "UInt")
global LastRealFgHwnd := 0 ; last foreground window not owned by this script

; ==============================================================================
; DEFAULT SETTINGS (INI overrides these)
; ==============================================================================
global SteamPath := "C:\Program Files (x86)\Steam\Steam.exe"
global BpmTitle := "Steam Big Picture Mode"

; Feature toggles
global EnableElevatedInputHelper := true
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
global EnablePersistentMouseMode := false ; Apply mappings without holding View/Back
global ControllerNeedsFreshBaseline := false
global ControllerIndex := 0 ; 0 = first controller
; The slot a controller last actually answered on, or -1 for none. Distinct from
; ControllerIndex, which is what the user asked for: Steam Input and Xbox mode
; move a pad between slots without restarting anything, so the configured index
; is a starting guess and this is the answer. Read by XInputResolveController.
global ActiveControllerIndex := -1
global ControllerPollIntervalMs := 15 ; Poll rate (ms). 15 fires on every Windows timer tick; 16 waits for the next
global ControllerDeadzone := 3000 ; Stick deadzone (0-32767)
global ControllerMouseSpeed := 3200 ; Cursor pixels per SECOND at full deflection
global ControllerMouseFastMultiplier:= 2.5 ; Multiplier when RT is held (fast move)
global ControllerScrollIntervalMs := 80 ; Min ms between scroll ticks
global ControllerScrollStep := 1 ; Wheel notches per scroll tick
global ControllerChordHoldMs := 500 ; Long-press threshold (ms) for View/Back + button secondary actions

; Controller mapping configuration (View/Back modifier or persistent Mouse Mode)
global ControllerMap := Map() ; key => mapping string ("Builtin:..." or "Send:...")
global ControllerMapDisplay := Map() ; key => pretty display for Send: mappings
InitDefaultControllerMappings()

; SteamShell quick menu / notifications
global EnableQuickMenu := true
global QuickMenuChordHoldMs := 500
global TaskForceCloseHoldMs := 1200
global QuickMenuMainOrderRaw := "Audio|Display|RTSS|SteamMenu|SteamQuickAccess|Tasks|GameBar|Keyboard|MouseMode|Settings|System"
global QuickMenuHiddenItemsRaw := ""
global QuickMenuMainOrder := []
global QuickMenuHiddenItems := Map()
global QuickMenuLayoutGui := unset
global QuickMenuGui := unset
global QuickMenuRows := []
global QuickMenuSelected := 1
; Declared so SendChordSafe and SendSteamOverlayChord can be defined once.
; Standalone has no companion to disable, so the guard never fires; the
; alternative was keeping both functions in two copies to avoid the name.
global CompanionDisabled := false
; Controller Learner state. The wizard lives in SteamShell-Shared.ahk; these
; are the globals it drives, declared here because a shared function cannot
; declare a global into a tree that never names it.
global EnableControllerDiagnostics := false
; 50 ms, matching the companion. Fast enough to catch a button that appears in
; one slot and not another, and it only runs while the diagnostic is on.
global ControllerDiagnosticIntervalMs := 50
global LearnActive := false
global LearnAnalogBytes := Map()
global LearnAnalogValues := Map()
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
global LearnAxisSamples := []
global LearnAxisStarted := false
global LearnBaseline := 0
global LearnCaptureUntil := 0
global LearnCountdownCtrl := unset
global LearnDetailCtrl := unset
global LearnDevice := 0
global LearnDeviceKey := ""
global LearnDpadRetries := 0
global LearnExcursion := 0
global LearnGui := unset
global LearnHatValues := Map()
global LearnIdentifyDevices := Map()
global LearnIdentifyReady := false
global LearnLastAccepted := ""
global LearnLength := 0
global LearnPeak := 0
global LearnProgressCtrl := unset
global LearnPromptCtrl := unset
; The control that chose the device, held until it is let go. Rest cannot be
; measured while it is down, because "rest" would then include it.
global LearnIdentifyHoldMask := 0
; The last report seen while the identifying control settles. On a pad that
; reports only on change it is the sole evidence of rest -- see
; ControllerLearnBeginSteps.
global LearnIdleSample := 0
global LearnIdleSampleSeen := false
global LearnIdentifyHoldOffset := -1
global LearnReleaseMask := 0
global LearnReleaseOffset := -1
global LearnReleaseUntil := 0
global LearnRestCount := 0
global LearnRestNoise := 0
global LearnRestSampling := false
global LearnResultAxes := Map()
global LearnResultButtons := []
global LearnStepIndex := 0
global LearnStepReports := 0
; Seeded with every axis it reads, not left empty. ControllerProfileRestCheck
; reads RestCheckPeak[name] for all six unguarded, and an empty Map answers that
; with "Item has no value" -- an uncaught error, from a timer, on the path taken
; immediately after a controller profile is applied. Only
; ControllerProfileRestCheckBegin fills it today, so the reads are safe by
; sequence rather than by construction; this makes them safe either way.
global RestCheckPeak := Map("LX", 0, "LY", 0, "RX", 0, "RY", 0, "LT", 0, "RT", 0)
global RestCheckSamples := 0
; "auto" (default), "rawinput" or "xinput".
;
; Auto reads RawInput whenever HID reports are arriving and XInput otherwise, so
; a machine whose controller already worked is unaffected: RawInput stays silent
; and XInput answers exactly as it did. A controller XInput cannot see -- which
; is every pad that does not speak it -- now has a path that reaches this
; program instead of leaving the shell with no input at all.
global ControllerBackend := "auto"
; Which backend last ANSWERED, as opposed to which one the setting asks for.
;
; The two are not the same and the difference is the whole diagnostic: "auto"
; with a pad on RawInput and "auto" with a pad on XInput are the same setting and
; very different machines. This tree selected a backend exactly as the companion
; does and then discarded which one won, so neither its log nor its Health Check
; could say. Recorded through the shared SetActiveBackend.
global ActiveInputBackend := "none"
; Logs raw HID gamepad reports as they arrive. Diagnostic use only.
global EnableRawInputProbe := false
global RawInputProbeActive := false
; Reports arrive as WM_INPUT and are decoded into this XINPUT_STATE-shaped
; buffer for the poll loop to read.
global RawInputState := Buffer(16, 0)
global RawInputLastReportTick := 0
global RawInputDevice := 0
global RawInputStaleMs := 5000

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
global QuickMenuStatusCtrl := 0
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
global QuickMenuRowsCtrl := 0
global QuickMenuRowsBitmap := 0
global QuickMenuRedrawSuspended := false
global GdiPlusToken := 0
global GdiPlusModule := 0
global SteamMenuShortcut := "^1"
global SteamQuickAccessShortcut := "^2"
global SteamOverlayShortcut := "+{Tab}"
; The View/Back button's OWN action, on a press that was not used as the mapping
; modifier. Shared with the companion, which has had it since it was written --
; see ViewButtonReleased in SteamShell-Shared.ahk. The two hold thresholds are
; separate because View is commonly the scoreboard or map button inside a game
; and gets held on purpose there.
; OFF by default in the shell, unlike the companion. View/Back is this
; product's mapping modifier and the button reached for constantly, so giving a
; bare press a new meaning is opt-in here. The sub-toggles below stay on, so
; enabling this one gives the whole feature rather than a half of it.
global EnableViewSteamActions := false
global EnableViewTapAction := true
global EnableViewHoldAction := true
global ViewHoldMs := 500
global ViewHoldInGameMs := 1000
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
global SettingsDialogActive := false
global SettingsStartupListView := 0
global SettingsStartupCommandEdit := 0
global SettingsStartupSelectedSlot := 1
global HealthCheckGui := unset
global HealthCheckResults := []
global SetupAssistantGui := unset
global SetupAssistantControls := []
global SetupAssistantControlPositions := Map()
global SetupAssistantScrollBar := 0
global SetupAssistantScrollOffset := 0
global SetupAssistantContentHeight := 0
global SetupAssistantViewportHeight := 0
global AutoLogonGui := unset
global SetupCompletionGui := unset
global SetupCompletionChoice := "later"
global ProductRemovalGui := unset
global ProductRemovalChoice := "cancel"
global SetupAssistantExternalPid := 0
global SetupAssistantExternalStartedTick := 0

; Optional living-room integrations exposed by the quick menu
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
global RtssElevatedFrameCapWrites := true
; The Frame Limit selection SteamShell last applied. RTSS persists only the
; FPS number in its global profile; the limiter on/off flag is runtime state
; in its shared memory, and "Custom" is a SteamShell concept RTSS never sees.
; Without these two keys, none of the selection survives an RTSS restart.
global RtssLastFrameCapMode := ""
global RtssLastFrameCapFps := 0
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
; The last RTSS flag word seen, so a CHANGE can be logged without logging every
; read. -1 is "nothing seen yet"; 0 is a real flag word.
global RtssLastFlagsSeen := -1
; The window after a startup restore during which the limiter flag is held
; against RTSS re-asserting its own saved state. See RtssFrameLimitHoldTick.
global RtssFrameLimitHoldUntil := 0
global RtssFrameLimitHoldRetries := 0
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
global EnableLauncherCleanup := true ; Close selected launchers/services after Steam is foreground for N seconds
global LauncherCleanupSteamForegroundSec := 30 ; Required seconds Steam stays foreground before cleanup runs
global LauncherCleanupRequireNoGame := true ; Skip cleanup if a game-like fullscreen/borderless window is detected
global LauncherCleanupCooldownSec := 300 ; Minimum seconds between cleanup runs
global LauncherCleanupCheckIntervalMs := 2000 ; Timer interval for checking conditions
global LauncherCleanupGracefulCloseMs := 4000 ; Wait after WinClose before hard-killing
global LauncherCleanupHardKill := true ; If true, hard-kill any remaining launcher/service processes after GracefulCloseMs
global LauncherCleanupUseCpuAudio := true ; Use CPU/audio heuristics (more reliable than window size alone)
global LauncherCleanupCpuThreshold := 12 ; CPU % threshold to consider "game running" (0 disables CPU check)
global LauncherCleanupAudioPeakThreshold := 0.02 ; Audio peak threshold for Launcher Cleanup (0.0–1.0)
global LauncherCleanupDownloadGuard := true ; If true, skip cleanup while launchers appear busy (possible download/update)
global LauncherCleanupDownloadGuardMode := "Balanced" ; Off|Balanced|Strict (controls internal thresholds)

; Pipe-separated EXE lists (editable in INI)
global LauncherCleanupLauncherExeListRaw := "UbisoftConnect.exe|upc.exe|EpicGamesLauncher.exe|EADesktop.exe|EALauncher.exe|Origin.exe|Battle.net.exe|RockstarGamesLauncher.exe|GalaxyClient.exe|RiotClientServices.exe|RiotClientUx.exe|wgc.exe|Heroic.exe"
global LauncherCleanupBackgroundExeListRaw := "UbisoftConnectService.exe|UplayWebCore.exe|UplayService.exe|EpicWebHelper.exe|EABackgroundService.exe|BlizzardUpdateAgent.exe|Agent.exe|RockstarService.exe|SocialClubHelper.exe|GalaxyClientService.exe|GalaxyCommunication.exe|RiotClientUxRender.exe|legendary.exe|gogdl.exe|nile.exe"
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
global SteamRefocusDelay := 1000

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
global MinWidthPercent := 0.30
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
global AutoMouseExeListRaw := DefaultAutoMouseExeList()
global AutoMouseExeSet := Map()
; Desktop mode is an explicit request to operate Windows rather than a game.
; Make controller mouse automatic across ordinary apps there, with a user-owned
; exclusion list for games or applications where controller input must stay raw.
global EnableDesktopAutoMouseMode := true
global DesktopAutoMouseExcludeExeListRaw := ""
global DesktopAutoMouseExcludeExeSet := Map()

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
global GameAssistLogEvenWhenSkipped := true

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
global LogRotateMaxKB := 256
global LogRotateBackups := 2

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
; True from the moment a desktop-restore action is committed until Explorer is
; ready (or the attempt is cancelled). It prevents controller/tray input from
; reopening the Quick Menu while Steam's fullscreen surface is disappearing.
global DesktopRestorePending := false
global TaskbarCreatedMessage := 0
global SteamLaunched := false
global SteamLaunchAttemptTick := 0
global SteamObservedRunning := false
global SteamMissingSinceTick := 0
global SteamStartupGraceMs := 120000
global SteamExitConfirmMs := 4000
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
; The scored candidate table from the most recent window-engine pass.
;
; Everything here is already computed to pick a game; only the winner used to
; survive the function. Keeping the losers is what lets the Quick Menu answer
; "why did it pick that window?" on the device, instead of the question becoming
; a log request and a round trip.
;
; Trimmed and capped rather than held whole: these are read once a poll and the
; page shows a handful of rows.
global LastGameCandidates := []
global GameScoreMaxRows := 8
global EnableGameDetectionMenu := true
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

; QuoteWindowsCommandLineArg, StrRepeat, and the process-token identity helpers
; (GetTokenInformationBuffer, OpenCurrentProcessToken, GetTokenUserSidString,
; GetTokenSessionId, GetCurrentProcessUserSid, GetCurrentProcessSessionId,
; GetProcessTokenSecurity) moved to SteamShell-Shared.ahk when XFE gained its
; opt-in RTSS helper: verifying that the helper process has a High-integrity
; token belonging to the same user and session is the same question in both
; programs, asked of the same payload.
;
; InitializeExpectedInteractiveIdentity stayed here. It reads this tree's
; bootstrap --steamshell-user-sid/--steamshell-session-id arguments, which exist
; because standalone re-launches itself across the elevation boundary; XFE never
; does and records its own token directly.

IsSteamShellIdentityArgument(argument) {
    value := StrLower(Trim(argument))
    return InStr(value, "--steamshell-user-sid=") = 1
        || InStr(value, "--steamshell-session-id=") = 1
}

InitializeExpectedInteractiveIdentity() {
    global ExpectedInteractiveUserSid, ExpectedInteractiveSessionId

    passedSid := ""
    passedSession := -1
    identityArgumentsPresent := false
    if A_IsAdmin {
        for _, argument in A_Args {
            if IsSteamShellIdentityArgument(argument)
                identityArgumentsPresent := true
            if RegExMatch(argument, "i)^--steamshell-user-sid=(S-[0-9-]+)$", &sidMatch) {
                passedSid := sidMatch[1]
            } else if RegExMatch(
                argument, "i)^--steamshell-session-id=([0-9]+)$", &sessionMatch) {
                passedSession := Integer(sessionMatch[1])
            }
        }
    }

    ; An unelevated bootstrap is authoritative. Ignore injected identity
    ; arguments and measure its own token immediately before RunAs. A process
    ; started elevated without a bootstrap records itself. If bootstrap
    ; identity arguments are present but malformed or incomplete, retain the
    ; invalid state so standard-user launches fail closed instead of silently
    ; switching to over-the-shoulder administrator credentials.
    if !A_IsAdmin || !identityArgumentsPresent {
        if !GetCurrentProcessUserSid(&passedSid, &sidError)
            passedSid := ""
        if !GetCurrentProcessSessionId(&passedSession)
            passedSession := -1
    }

    ExpectedInteractiveUserSid := passedSid
    ExpectedInteractiveSessionId := passedSession
}

GetLinkedStandardUserToken(&linkedToken, &reason) {
    global ExpectedInteractiveUserSid, ExpectedInteractiveSessionId
    static TOKEN_QUERY := 0x0008
    linkedToken := 0
    reason := ""

    if !A_IsAdmin {
        reason := "SteamShell is already running at standard integrity."
        return false
    }
    if !OpenCurrentProcessToken(TOKEN_QUERY, &currentToken, &errorCode) {
        reason := "OpenProcessToken failed (" errorCode ")."
        return false
    }
    try {
        ; TOKEN_ELEVATION_TYPE: Default=1, Full=2, Limited=3. Only a full
        ; split token can provide the matching standard-user linked token.
        if !GetTokenInformationBuffer(currentToken, 18, &elevationInfo, &errorCode) {
            reason := "TokenElevationType query failed (" errorCode ")."
            return false
        }
        if (NumGet(elevationInfo, 0, "UInt") != 2) {
            reason := "Windows did not provide a full split token; UAC may be disabled."
            return false
        }
        if !GetTokenInformationBuffer(currentToken, 19, &linkedInfo, &errorCode) {
            reason := "TokenLinkedToken query failed (" errorCode ")."
            return false
        }
        candidate := NumGet(linkedInfo, 0, "Ptr")
        if !candidate {
            reason := "Windows returned an empty linked token."
            return false
        }

        if !GetTokenUserSidString(candidate, &candidateSid, &errorCode) {
            reason := "Linked-token user query failed (" errorCode ")."
            DllCall("Kernel32\CloseHandle", "Ptr", candidate, "Int")
            return false
        }
        if !GetTokenSessionId(candidate, &candidateSession, &errorCode) {
            reason := "Linked-token session query failed (" errorCode ")."
            DllCall("Kernel32\CloseHandle", "Ptr", candidate, "Int")
            return false
        }
        if (ExpectedInteractiveUserSid = ""
            || StrLower(candidateSid) != StrLower(ExpectedInteractiveUserSid)
            || ExpectedInteractiveSessionId < 0
            || candidateSession != ExpectedInteractiveSessionId) {
            reason := "Linked-token identity mismatch; refusing to launch as a different user or session."
            DllCall("Kernel32\CloseHandle", "Ptr", candidate, "Int")
            return false
        }

        ; Normalize the linked handle into an explicit primary token. Passing
        ; the raw TOKEN_LINKED_TOKEN handle worked after Explorer had already
        ; brokered a launch, but failed at cold boot with
        ; ERROR_BAD_IMPERSONATION_LEVEL (1346). DuplicateTokenEx gives the
        ; process API the token type and impersonation level it requires.
        static MAXIMUM_ALLOWED := 0x02000000
        static SecurityImpersonation := 2
        static TokenPrimary := 1
        primaryToken := 0
        if !DllCall(
            "Advapi32\DuplicateTokenEx",
            "Ptr", candidate,
            "UInt", MAXIMUM_ALLOWED,
            "Ptr", 0,
            "Int", SecurityImpersonation,
            "Int", TokenPrimary,
            "Ptr*", &primaryToken,
            "Int") {
            reason := "DuplicateTokenEx failed (" A_LastError ")."
            DllCall("Kernel32\CloseHandle", "Ptr", candidate, "Int")
            return false
        }
        DllCall("Kernel32\CloseHandle", "Ptr", candidate, "Int")
        linkedToken := primaryToken
        return true
    } finally {
        DllCall("Kernel32\CloseHandle", "Ptr", currentToken, "Int")
    }
}

StandardLaunchShowValue(windowMode) {
    normalized := StrLower(Trim(windowMode))
    if (normalized = "hidden" || normalized = "hide")
        return 0 ; SW_HIDE
    if (normalized = "minimized" || normalized = "min")
        return 2 ; SW_SHOWMINIMIZED
    return 1 ; SW_SHOWNORMAL
}

ResolveStandardExecutablePath(target) {
    target := Trim(target, " `t`r`n" Chr(34))
    if (target = "")
        return ""
    attributes := FileExist(target)
    if (attributes != "" && !InStr(attributes, "D")) {
        required := DllCall(
            "Kernel32\GetFullPathNameW",
            "WStr", target,
            "UInt", 0,
            "Ptr", 0,
            "Ptr", 0,
            "UInt")
        if (required > 0) {
            fullPath := Buffer(required * 2, 0)
            if DllCall(
                "Kernel32\GetFullPathNameW",
                "WStr", target,
                "UInt", required,
                "Ptr", fullPath.Ptr,
                "Ptr", 0,
                "UInt")
                return StrGet(fullPath, "UTF-16")
        }
        return target
    }

    required := DllCall(
        "Kernel32\SearchPathW",
        "Ptr", 0,
        "WStr", target,
        "Ptr", 0,
        "UInt", 0,
        "Ptr", 0,
        "Ptr", 0,
        "UInt")
    if (required <= 0)
        return ""
    resolved := Buffer((required + 1) * 2, 0)
    if !DllCall(
        "Kernel32\SearchPathW",
        "Ptr", 0,
        "WStr", target,
        "Ptr", 0,
        "UInt", required + 1,
        "Ptr", resolved.Ptr,
        "Ptr", 0,
        "UInt")
        return ""
    return StrGet(resolved, "UTF-16")
}

PrepareStandardExecutable(target, arguments, &executable, &preparedArguments) {
    executable := ""
    preparedArguments := arguments
    SplitPath(target, , , &extension)
    extension := StrLower(extension)

    if (extension = "cmd" || extension = "bat") {
        executable := ResolveStandardExecutablePath(A_ComSpec)
        if (executable = "")
            return false
        scriptCommand := QuoteWindowsCommandLineArg(target)
        if (arguments != "")
            scriptCommand .= " " arguments
        preparedArguments := '/d /s /c "' scriptCommand '"'
        return true
    }
    if (extension != "" && extension != "exe" && extension != "com")
        return false

    executable := ResolveStandardExecutablePath(target)
    return executable != ""
}

EnableProcessTokenPrivilege(privilegeName, &reason) {
    static TOKEN_QUERY := 0x0008
    static TOKEN_ADJUST_PRIVILEGES := 0x0020
    static SE_PRIVILEGE_ENABLED := 0x00000002
    reason := ""
    if !OpenCurrentProcessToken(
        TOKEN_QUERY | TOKEN_ADJUST_PRIVILEGES, &processToken, &errorCode) {
        reason := "OpenProcessToken for " privilegeName " failed (" errorCode ")."
        return false
    }
    try {
        luid := Buffer(8, 0)
        if !DllCall(
            "Advapi32\LookupPrivilegeValueW",
            "Ptr", 0,
            "WStr", privilegeName,
            "Ptr", luid.Ptr,
            "Int") {
            reason := "LookupPrivilegeValue failed for " privilegeName
                . " (" A_LastError ")."
            return false
        }
        tokenPrivileges := Buffer(16, 0)
        NumPut("UInt", 1, tokenPrivileges, 0)
        NumPut("Int64", NumGet(luid, 0, "Int64"), tokenPrivileges, 4)
        NumPut("UInt", SE_PRIVILEGE_ENABLED, tokenPrivileges, 12)
        DllCall("Kernel32\SetLastError", "UInt", 0)
        if !DllCall(
            "Advapi32\AdjustTokenPrivileges",
            "Ptr", processToken,
            "Int", false,
            "Ptr", tokenPrivileges.Ptr,
            "UInt", 0,
            "Ptr", 0,
            "Ptr", 0,
            "Int") {
            reason := "AdjustTokenPrivileges failed for " privilegeName
                . " (" A_LastError ")."
            return false
        }
        adjustmentError := A_LastError
        if (adjustmentError = 1300) {
            reason := privilegeName " is not assigned to the SteamShell token."
            return false
        }
        return true
    } finally {
        DllCall("Kernel32\CloseHandle", "Ptr", processToken, "Int")
    }
}

CreateProcessWithStandardToken(
    token, executable, arguments, directory, windowMode, &pid, &reason) {
    static CREATE_UNICODE_ENVIRONMENT := 0x00000400
    static STARTF_USESHOWWINDOW := 0x00000001
    pid := 0
    reason := ""
    environment := 0

    if !EnableProcessTokenPrivilege("SeImpersonatePrivilege", &reason)
        return false

    if !DllCall(
        "Userenv\CreateEnvironmentBlock",
        "Ptr*", &environment,
        "Ptr", token,
        "Int", false,
        "Int") {
        reason := "CreateEnvironmentBlock failed (" A_LastError ")."
        return false
    }

    commandLine := QuoteWindowsCommandLineArg(executable)
    if (arguments != "")
        commandLine .= " " arguments
    commandBuffer := Buffer((StrLen(commandLine) + 1) * 2, 0)
    StrPut(commandLine, commandBuffer, "UTF-16")

    if (directory = "")
        SplitPath(executable, , &directory)
    attributes := directory != "" ? FileExist(directory) : ""
    if (attributes = "" || !InStr(attributes, "D")) {
        DllCall("Userenv\DestroyEnvironmentBlock", "Ptr", environment, "Int")
        reason := "Working directory is unavailable: " directory
        return false
    }

    ; #Requires pins this script to 64-bit AutoHotkey. STARTUPINFOW is 104
    ; bytes and PROCESS_INFORMATION is 24 bytes in that ABI.
    startupInfo := Buffer(104, 0)
    NumPut("UInt", startupInfo.Size, startupInfo, 0)
    NumPut("UInt", STARTF_USESHOWWINDOW, startupInfo, 60)
    NumPut("UShort", StandardLaunchShowValue(windowMode), startupInfo, 64)
    processInfo := Buffer(24, 0)

    created := DllCall(
        "Advapi32\CreateProcessWithTokenW",
        "Ptr", token,
        "UInt", 0,
        "WStr", executable,
        "Ptr", commandBuffer.Ptr,
        "UInt", CREATE_UNICODE_ENVIRONMENT,
        "Ptr", environment,
        "WStr", directory,
        "Ptr", startupInfo.Ptr,
        "Ptr", processInfo.Ptr,
        "Int")
    createError := created ? 0 : A_LastError
    DllCall("Userenv\DestroyEnvironmentBlock", "Ptr", environment, "Int")
    if !created {
        reason := "CreateProcessWithTokenW failed (" createError ")."
        return false
    }

    processHandle := NumGet(processInfo, 0, "Ptr")
    threadHandle := NumGet(processInfo, A_PtrSize, "Ptr")
    pid := NumGet(processInfo, A_PtrSize * 2, "UInt")
    if threadHandle
        DllCall("Kernel32\CloseHandle", "Ptr", threadHandle, "Int")
    if processHandle
        DllCall("Kernel32\CloseHandle", "Ptr", processHandle, "Int")
    return pid != 0
}

GetVerifiedDesktopShellPid(&shellPid, &reason) {
    global ExpectedInteractiveUserSid, ExpectedInteractiveSessionId
    shellPid := 0
    reason := ""
    taskbar := DllCall(
        "User32\FindWindowW", "WStr", "Shell_TrayWnd", "Ptr", 0, "Ptr")
    if !taskbar {
        reason := "The Explorer desktop shell is not available."
        return false
    }
    DllCall(
        "User32\GetWindowThreadProcessId",
        "Ptr", taskbar,
        "UInt*", &shellPid,
        "UInt")
    if !shellPid || !GetProcessTokenSecurity(
        shellPid, &shellSid, &shellSession, &shellIntegrity, &securityError) {
        reason := shellPid ? securityError : "The Explorer shell PID was unavailable."
        return false
    }
    if (StrLower(shellSid) != StrLower(ExpectedInteractiveUserSid)
        || shellSession != ExpectedInteractiveSessionId
        || StrLower(shellIntegrity) != "medium") {
        reason := "Explorer is not a matching medium-integrity desktop shell."
        return false
    }
    return true
}

DesktopShellMatchesInteractiveUser(&reason) {
    return GetVerifiedDesktopShellPid(&shellPid, &reason)
}

BootstrapVerifiedDesktopShell(&shellPid, &reason) {
    static inProgress := false
    shellPid := 0
    reason := ""
    if GetVerifiedDesktopShellPid(&shellPid, &reason)
        return true
    if inProgress {
        reason := "A standard Explorer bootstrap is already in progress."
        return false
    }

    ; Explorer owns Windows' supported cold-boot escape hatch: when started by
    ; an elevated process it creates/runs CreateExplorerShellUnelevatedTask,
    ; exits, and is replaced by a normal Explorer. Do not trust that behavior
    ; blindly -- accept the result only after its taskbar PID, SID, session and
    ; Medium integrity all pass GetVerifiedDesktopShellPid.
    inProgress := true
    bootstrapPid := 0
    try {
        try Run(
            QuoteWindowsCommandLineArg(A_WinDir "\explorer.exe"),
            A_WinDir, "", &bootstrapPid)
        catch as err {
            reason := "Explorer bootstrap request failed: " err.Message
            return false
        }
        Loop 40 {
            Sleep 200
            if GetVerifiedDesktopShellPid(&shellPid, &reason)
                return true
        }
        reason := "Explorer bootstrap did not produce a matching Medium-integrity shell. "
            . reason
        return false
    } finally {
        inProgress := false
    }
}

; Windows holds an exclusive write lock on a running image, so a file can be
; gone from the process list and still be unopenable for a moment afterwards
; while the last handle is released. Probing the lock directly is what makes the
; wait honest: a fixed Sleep is a guess, and this asks the actual question the
; caller is about to ask.
WaitForReplaceableFile(path, timeoutMs := 5000) {
    if (path = "" || !FileExist(path))
        return true
    deadline := A_TickCount + Max(0, timeoutMs)
    Loop {
        handle := 0
        ; "rw" opens for read/write without truncating. A running image denies
        ; write sharing, so this succeeds exactly when a replace would.
        try handle := FileOpen(path, "rw")
        if IsObject(handle) {
            try handle.Close()
            return true
        }
        if (A_TickCount >= deadline)
            return false
        Sleep(100)
    }
}

; Setup replaces SteamShell-XFE.exe and SteamShell-Helper.exe in place, and
; nothing stopped either one first. On an XFE machine the logon task starts the
; companion at sign-in, so the file was always locked and FileMove always failed
; -- meaning Setup could essentially never apply, not merely that upgrades were
; awkward. It surfaced as "The XFE companion could not be deployed" carrying a
; bare [Win32 32], which named neither the cause nor the remedy.
;
; Three rules, in this order:
;
; 1. IDENTITY BEFORE ANYTHING IS CLOSED. Only a process whose image path is
;    exactly the target counts, and it must belong to the interactive user in
;    this session. A process carrying the right path with the wrong owner is a
;    reason to STOP, not to kill: Setup cannot account for it, and terminating
;    processes it cannot account for is not Setup's job. It fails closed and
;    says so.
; 2. WM_CLOSE FIRST. Both targets are AutoHotkey scripts, so WM_CLOSE on the
;    script's main window runs OnExit. XFE keeps its INI, learned controller
;    profiles and log beside its executable; a hard kill mid-write is not the
;    opening move. TerminateProcess is the fallback, not the plan.
; 3. WAIT FOR THE LOCK, not for the process. See WaitForReplaceableFile.
StopRunningSteamShellExecutable(executablePath, &stoppedPids, &failureReason) {
    stoppedPids := []
    failureReason := ""
    if (executablePath = "" || !FileExist(executablePath))
        return true
    running := CaptureExecutablePidSet(executablePath)
    if (running.Count = 0)
        return true

    foreign := []
    targets := []
    for pid, _ in running {
        if SteamShellSetupProcessMatchesIdentity(pid)
            targets.Push(pid)
        else
            foreign.Push(pid)
    }
    if (foreign.Length > 0) {
        failureReason := "A process at " executablePath " (PID "
            . foreign[1] ") does not belong to the signed-in user in this "
            . "session, so Setup did not close it. Close it manually and apply "
            . "again."
        LogLine("Setup refused to close an unaccounted process at "
            . executablePath ": PID " foreign[1] ".", "Warning")
        return false
    }

    for _, pid in targets {
        ; CloseSteamShellProcessForSetup already does WM_CLOSE-then-terminate,
        ; and does it correctly: it posts to the script's hidden main window
        ; with DetectHiddenWindows enabled. An open-coded WinClose here would
        ; find nothing, because another process's AutoHotkey main window is
        ; hidden and this script does not detect hidden windows by default --
        ; so it would silently skip the graceful path and always terminate.
        if !CloseSteamShellProcessForSetup(pid, true) {
            failureReason := "PID " pid " at " executablePath
                . " could not be closed. Close it manually and apply again."
            LogLine("Setup could not close PID " pid " at " executablePath ".",
                "Warning")
            return false
        }
        stoppedPids.Push(pid)
        LogLine("Setup closed PID " pid " at " executablePath
            . " before replacing it.")
    }

    if !WaitForReplaceableFile(executablePath, 5000) {
        failureReason := executablePath
            . " is still locked after the processes using it exited. "
            . "Sign out and back in, then apply again."
        LogLine("Setup: " executablePath
            . " stayed locked after every owning process exited.", "Warning")
        return false
    }
    return true
}

RecordStandardLaunch(purpose, target, route, pid := 0, errorText := "") {
    global StandardLaunchLastRoute, StandardLaunchLastError
    global StandardLaunchSuccessCount, StandardLaunchFailureCount
    global StandardLaunchTrackedProcesses
    label := purpose != "" ? purpose : target
    if (errorText = "") {
        StandardLaunchSuccessCount += 1
        StandardLaunchLastRoute := route " — " label
        StandardLaunchLastError := ""
        if pid
            StandardLaunchTrackedProcesses[pid] := Map(
                "purpose", label,
                "target", target,
                "route", route)
        try LogLine(
            "Standard-user launch: " label " via " route
            . (pid ? " (PID " pid ")." : "."))
    } else {
        StandardLaunchFailureCount += 1
        StandardLaunchLastError := label ": " errorText
        try LogLine("Standard-user launch failed: " StandardLaunchLastError, "Warning")
    }
}

LaunchInteractiveApp(
    target, arguments := "", directory := "", windowMode := "Normal", &pid := 0,
    purpose := "") {
    global StandardLaunchLastError
    pid := 0
    target := Trim(target, " `t`r`n" Chr(34))
    if (target = "") {
        RecordStandardLaunch(purpose, target, "none", 0, "The target was blank.")
        return false
    }
    if (directory = "" && FileExist(target))
        SplitPath(target, , &directory)

    if !A_IsAdmin {
        commandLine := QuoteWindowsCommandLineArg(target)
        if (arguments != "")
            commandLine .= " " arguments
        options := StandardLaunchShowValue(windowMode) = 0
            ? "Hide" : (StandardLaunchShowValue(windowMode) = 2 ? "Min" : "")
        try {
            Run(commandLine, directory, options, &pid)
            RecordStandardLaunch(purpose, target, "direct standard token", pid)
            return true
        } catch as err {
            RecordStandardLaunch(purpose, target, "direct standard token", 0, err.Message)
            return false
        }
    }

    if PrepareStandardExecutable(target, arguments, &executable, &preparedArguments) {
        if GetLinkedStandardUserToken(&standardToken, &tokenReason) {
            try {
                if CreateProcessWithStandardToken(
                    standardToken, executable, preparedArguments, directory,
                    windowMode, &pid, &createReason) {
                    RecordStandardLaunch(
                        purpose, executable, "verified linked token", pid)
                    return true
                }
                tokenReason := createReason
            } finally {
                DllCall("Kernel32\CloseHandle", "Ptr", standardToken, "Int")
            }
        }
    } else {
        executable := ""
        tokenReason := "The target requires a desktop-shell file association."
    }

    showValue := StandardLaunchShowValue(windowMode)
    shellPid := 0
    if !DesktopShellMatchesInteractiveUser(&shellReason)
        && BootstrapVerifiedDesktopShell(&shellPid, &bootstrapReason) {
        if (executable != ""
            && StrLower(executable) = StrLower(A_WinDir "\explorer.exe")) {
            pid := shellPid
            RecordStandardLaunch(
                purpose, executable, "verified Explorer bootstrap", pid)
            return true
        }
    } else if (shellReason != "") {
        try LogLine(
            "Standard Explorer bootstrap unavailable: " bootstrapReason,
            "Warning")
    }
    if (executable != "" && tokenReason != "")
        try LogLine(
            "Native standard-user route was unavailable for " executable
            . "; trying verified Explorer: " tokenReason,
            "Warning")
    existingPids := CaptureExecutablePidSet(executable)
    if RunViaDesktopShell(target, arguments, directory, showValue) {
        pid := WaitForNewExecutablePid(executable, existingPids)
        RecordStandardLaunch(
            purpose, target, "verified Explorer shell", pid)
        return true
    }

    ; With UAC disabled Windows does not create a medium linked token at all.
    ; There is no lower-integrity identity SteamShell can launch as, so preserve
    ; a usable shell and make the degraded route explicit in logging/Health.
    if InStr(tokenReason, "UAC may be disabled") {
        commandLine := QuoteWindowsCommandLineArg(target)
        if (arguments != "")
            commandLine .= " " arguments
        options := showValue = 0 ? "Hide" : (showValue = 2 ? "Min" : "")
        try {
            Run(commandLine, directory, options, &pid)
            RecordStandardLaunch(
                purpose, target, "inherited token; no split token", pid)
            StandardLaunchLastError :=
                "Windows has no standard linked token; launched with inherited privileges."
            try LogLine(StandardLaunchLastError, "Warning")
            return true
        } catch as err {
            tokenReason .= " Inherited fallback also failed: " err.Message
        }
    }

    RecordStandardLaunch(
        purpose, target, "standard-user routes", 0,
        tokenReason != "" ? tokenReason : "No verified standard-user route was available.")
    return false
}

AdministratorSetupRequestMarkerPath() {
    global SteamShellDataDir
    return SteamShellDataDir "\setup-admin-requested.tmp"
}

WriteAdministratorSetupRequestMarker() {
    global ExpectedInteractiveUserSid, ExpectedInteractiveSessionId
    markerPath := AdministratorSetupRequestMarkerPath()
    try {
        SplitPath(markerPath, , &markerDirectory)
        if (markerDirectory != "")
            DirCreate(markerDirectory)
        if FileExist(markerPath)
            FileDelete(markerPath)
        FileAppend(
            "UserSid=" ExpectedInteractiveUserSid "`r`n"
            . "SessionId=" ExpectedInteractiveSessionId "`r`n",
            markerPath, "UTF-8")
        return true
    } catch as err {
        try LogLine(
            "Administrator Setup request marker could not be written: "
            . err.Message, "Warning")
        return false
    }
}

ConsumeAdministratorSetupRequestMarker(&requested, &failureReason) {
    global ExpectedInteractiveUserSid, ExpectedInteractiveSessionId
    requested := false
    failureReason := ""
    markerPath := AdministratorSetupRequestMarkerPath()
    if !FileExist(markerPath)
        return true
    markerText := ""
    try markerText := FileRead(markerPath, "UTF-8")
    catch as err {
        failureReason := "The administrator Setup request could not be read. " err.Message
        return false
    }
    try FileDelete(markerPath)
    if FileExist(markerPath) {
        failureReason :=
            "The one-time administrator Setup request could not be removed after it was read. Check access to the SteamShell data folder and try again."
        return false
    }
    markerSid := ""
    markerSession := -1
    if RegExMatch(markerText, "im)^UserSid=(S-[0-9-]+)\s*$", &sidMatch)
        markerSid := sidMatch[1]
    if RegExMatch(markerText, "im)^SessionId=([0-9]+)\s*$", &sessionMatch)
        markerSession := Integer(sessionMatch[1])
    if (markerSid = ""
        || StrLower(markerSid) != StrLower(ExpectedInteractiveUserSid)
        || markerSession < 0
        || markerSession != ExpectedInteractiveSessionId) {
        failureReason :=
            "The elevated process does not match the user and Windows session that requested Setup. Sign in with an administrator account and use that same account's Run as administrator option."
        return false
    }
    requested := true
    return true
}

EnsureExplorerAvailableForSetupExit(allowLaunch := true) {
    StopTaskbarGuard(true)
    StopDesktopBlackout(true)
    ShowDesktopTaskbars()
    SystemCursor("Show")
    if allowLaunch && !ProcessExist("explorer.exe") {
        explorerPid := 0
        LaunchInteractiveApp(
            A_WinDir "\explorer.exe", "", A_WinDir,
            "Normal", &explorerPid, "Administrator Setup handoff")
    }
}

PromptForAdministratorSetupAndExit() {
    global IntentionalExitMode, SetupAssistantGui
    markerWritten := WriteAdministratorSetupRequestMarker()
    message :=
        "Please Start SteamShell As Administrator for First Install or Upgrade.`n`n"
        . "Click OK to close this SteamShell instance. Then right-click SteamShell.exe and select Run as administrator."
    if !markerWritten
        message .= "`n`nThe automatic Setup request could not be saved. After relaunching, open Setup Assistant manually."
    SteamShellMsgBox(
        message, "OK Icon!", "SteamShell Administrator Setup Required")
    IntentionalExitMode := "setup-admin-required"
    try LogLine(
        "SteamShell is exiting because installation or upgrade requires an administrator launch; marker="
        . (markerWritten ? "written" : "unavailable") ".")
    EnsureExplorerAvailableForSetupExit(true)
    ExitApp()
}

SteamShellSetupProcessMatchesIdentity(pid) {
    global ExpectedInteractiveUserSid, ExpectedInteractiveSessionId, ScriptPid
    if !pid || pid = ScriptPid
        return false
    if !GetProcessTokenSecurity(
        pid, &processSid, &processSession, &processIntegrity, &processError)
        return false
    return processSession = ExpectedInteractiveSessionId
        && StrLower(processSid) = StrLower(ExpectedInteractiveUserSid)
}

OtherSteamShellSetupProcessExists() {
    global ScriptPid
    for _, executableName in ["SteamShell.exe", "SteamShell-Helper.exe"] {
        for _, pid in GetPidsByExeName(executableName) {
            if (pid != ScriptPid && SteamShellSetupProcessMatchesIdentity(pid))
                return true
        }
    }
    return false
}

ElevatedSetupMatchesInteractiveDesktop(&failureReason) {
    global ExpectedInteractiveUserSid, ExpectedInteractiveSessionId
    failureReason := ""
    sawCurrentSessionDesktop := false
    for _, pid in GetPidsByExeName("explorer.exe") {
        if !GetProcessTokenSecurity(
            pid, &desktopSid, &desktopSession,
            &desktopIntegrity, &desktopError)
            continue
        if (desktopSession != ExpectedInteractiveSessionId
            || StrLower(desktopIntegrity) != "medium")
            continue
        sawCurrentSessionDesktop := true
        if (StrLower(desktopSid) = StrLower(ExpectedInteractiveUserSid))
            return true
    }
    failureReason := sawCurrentSessionDesktop
        ? "The administrator credentials belong to a different user than the signed-in Windows desktop. SteamShell Setup must be elevated with the signed-in account's own administrator token."
        : "SteamShell could not verify a normal-integrity Explorer desktop for this Windows session. Return to the desktop and start SteamShell as administrator again."
    return false
}

CloseSteamShellProcessForSetup(pid, graceful := false) {
    global ScriptPid
    if !pid || pid = ScriptPid || !ProcessExist(pid)
        return true
    if graceful {
        previousHiddenWindows := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            for _, hwnd in WinGetList("ahk_pid " pid) {
                windowClass := ""
                try windowClass := WinGetClass("ahk_id " hwnd)
                if (StrLower(windowClass) = "autohotkey")
                    try PostMessage(0x0010, 0, 0, , "ahk_id " hwnd)
            }
        }
        DetectHiddenWindows(previousHiddenWindows)
        gracefulDeadline := A_TickCount + 2500
        while ProcessExist(pid) && A_TickCount < gracefulDeadline
            Sleep(50)
    }
    if ProcessExist(pid) {
        try ProcessClose(pid)
        closeDeadline := A_TickCount + 1500
        while ProcessExist(pid) && A_TickCount < closeDeadline
            Sleep(50)
    }
    return !ProcessExist(pid)
}

CloseExistingSteamShellInstancesForElevatedSetup(&detail) {
    global ScriptPid
    detail := ""
    if !A_IsAdmin {
        detail := "The Setup takeover process is not elevated."
        return false
    }
    mainClosed := 0
    companionClosed := 0
    helperClosed := 0
    failures := []
    for _, pid in GetPidsByExeName("SteamShell.exe") {
        if (pid = ScriptPid || !SteamShellSetupProcessMatchesIdentity(pid))
            continue
        if CloseSteamShellProcessForSetup(pid, true)
            mainClosed += 1
        else
            failures.Push("SteamShell.exe PID " pid)
    }
    ; The companion was missing from this list entirely, and it is the one that
    ; is ALWAYS running: its logon task starts it at sign-in on every XFE
    ; machine. Setup then tried to replace a locked image and failed, so on an
    ; XFE machine Setup could essentially never apply -- not merely that
    ; upgrading was awkward. Graceful, because XFE keeps its INI, learned
    ; controller profiles and log beside its executable.
    for _, pid in GetPidsByExeName("SteamShell-XFE.exe") {
        if !SteamShellSetupProcessMatchesIdentity(pid)
            continue
        if CloseSteamShellProcessForSetup(pid, true)
            companionClosed += 1
        else
            failures.Push("SteamShell-XFE.exe PID " pid)
    }

    ; Helpers normally observe their parent exit and leave on their own. Give
    ; them that graceful path first, then close only verified same-identity
    ; leftovers so the embedded helper can be replaced safely.
    helperDeadline := A_TickCount + 1500
    while A_TickCount < helperDeadline {
        matchingHelperFound := false
        for _, pid in GetPidsByExeName("SteamShell-Helper.exe") {
            if SteamShellSetupProcessMatchesIdentity(pid) {
                matchingHelperFound := true
                break
            }
        }
        if !matchingHelperFound
            break
        Sleep(50)
    }
    for _, pid in GetPidsByExeName("SteamShell-Helper.exe") {
        if !SteamShellSetupProcessMatchesIdentity(pid)
            continue
        if CloseSteamShellProcessForSetup(pid, false)
            helperClosed += 1
        else
            failures.Push("SteamShell-Helper.exe PID " pid)
    }
    detail := "closed main=" mainClosed "; closed companion=" companionClosed
        . "; closed helper leftovers=" helperClosed
    if failures.Length {
        detail .= "; still running=" JoinWith(failures, ", ")
        return false
    }
    return true
}

AbortAdministratorSetup(message) {
    global IntentionalExitMode
    SteamShellMsgBox(
        message "`n`nSteamShell Setup will now close.",
        "OK Iconx", "SteamShell Administrator Setup")
    IntentionalExitMode := "setup-admin-aborted"
    try LogLine("Administrator Setup aborted: " message, "Error")
    ; A rejected over-the-shoulder administrator must not create an Explorer
    ; process under the wrong account. Keep an existing desktop visible, but
    ; only the normal requesting process is allowed to bootstrap Explorer.
    EnsureExplorerAvailableForSetupExit(false)
    ExitApp()
}

ReadElevatedHelperPreference() {
    global SettingsPath
    if !FileExist(SettingsPath)
        return true
    rawValue := "true"
    try rawValue := IniRead(
        SettingsPath, "Features", "EnableElevatedInputHelper", "true")
    catch
        return true
    return ToBool(CleanIniValue(rawValue, "true"), true)
}

; The elevated helper lives in Program Files in EVERY installation mode, and it
; is the one part of SteamShell that is deliberately not portable.
;
; It used to sit beside the executable, which for a Portable install meant a
; directory the interactive user holds Modify on -- and Modify includes
; FILE_DELETE_CHILD, so the user could delete the hardened bin despite its own
; ACL, recreate it, and drop in their own binary. That is why Portable and
; Custom were refused the on-demand scheduled task: without a protected ancestor
; chain the task is an unprompted elevation to a file anyone can replace.
;
; The binary carries no user state -- it is a fixed payload extracted from
; SteamShell.exe -- so nothing about it needs to travel with a portable install.
; Only the INI, logs and backups do, and they still sit beside the executable.
; XFE already did exactly this; this is the shell adopting it.
;
; The consequence, stated in Setup: a portable copy is no longer self-contained
; on disk, and moving the folder to another machine needs Setup run again. That
; was already true of the scheduled task and the registry record.
SteamShellElevatedHelperDirectory() {
    global SteamShellInstallationMode, SettingsPath
    ; A Portable install may keep the helper beside the executable, but only
    ; because Setup either PROVED the folder is administrator-only-writable or
    ; the user chose it knowing the trade. The choice is recorded rather than
    ; re-derived, so a folder whose permissions change later cannot silently
    ; move the helper out from under an already-registered task.
    if (InStr(StrLower(Trim(SteamShellInstallationMode)), "portable")
        && StrLower(Trim(IniReadS("Setup", "PortableHelperLocation", "ProgramFiles")))
            = "portable")
        return A_ScriptDir "\SteamShell\bin"
    return A_ProgramFiles "\SteamShell\bin"
}

; Both places a helper can be, so uninstall and cleanup never depend on which
; was chosen -- or on the record still being readable.
; Both places a helper can be, so uninstall never depends on which was chosen --
; or on the [Setup] record still being readable.
;
; installDirectory MUST be passed when uninstalling. A_ScriptDir is only the
; install folder when the running executable is the installed one, and the whole
; point of the registry record is that an uninstall can be driven by a freshly
; downloaded SteamShell.exe sitting in Downloads. Defaulting to A_ScriptDir
; there would look for the portable helper beside the DOWNLOAD and quietly find
; nothing, leaving an administrator-protected directory and a scheduled task
; behind for a product the user believes is gone.
SteamShellElevatedHelperDirectories(installDirectory := "") {
    directories := [A_ProgramFiles "\SteamShell\bin"]
    base := RTrim(Trim(installDirectory), "\/")
    if (base = "")
        base := A_ScriptDir
    directories.Push(base "\SteamShell\bin")
    return directories
}

GetElevatedHelperPath() {
    return SteamShellElevatedHelperDirectory() "\SteamShell-Helper.exe"
}

; Turns a thrown file error into something a log reader can act on.
;
; AutoHotkey's file commands throw with the bare message "Failed", so the raw
; err.Message names neither what was being written nor why it was refused.
; Win32 5 is the one that matters here: it is what an unelevated write into an
; Administrators-only directory looks like, and it must not read the same as a
; missing payload.
; Only Win32 5 was ever named, and 32 is the one an upgrade actually hits: a
; running image cannot be replaced, and that failure used to render as a bare
; "[Win32 32]" for the single most likely reason a deployment fails. Setup now
; closes the owning process first, so reaching this line means that did not
; work -- which makes naming the cause more important, not less.
DescribeFileFailure(err, lastError, targetPath) {
    static WIN32_REASONS := Map(
        5, ": access denied",
        32, ": the file is in use by a running process",
        33, ": the file is locked by another process",
        1224, ": the file is open as a running image")
    detail := err.Message
    if (err.HasProp("Extra") && err.Extra != "")
        detail .= " (" err.Extra ")"
    if lastError
        detail .= " [Win32 " lastError
            . (WIN32_REASONS.Has(lastError) ? WIN32_REASONS[lastError] : "") "]"
    return detail " Target: " targetPath "."
}

ExtractEmbeddedElevatedHelper(targetPath, &failureReason, forceReplace := false) {
    global ScriptPid, ElevatedHelperExpectedVersion
    failureReason := ""
    if !A_IsCompiled {
        failureReason := "The elevated helper is embedded only in the compiled SteamShell.exe."
        return false
    }
    targetDirectory := ""
    SplitPath(targetPath, , &targetDirectory)
    stagedPath := targetPath ".extract-" ScriptPid ".tmp"
    try {
        DirCreate(targetDirectory)
        existingVersion := ""
        if FileExist(targetPath)
            try existingVersion := FileGetVersion(targetPath)
        if (!forceReplace
            && existingVersion = ElevatedHelperExpectedVersion)
            return true
        if FileExist(stagedPath)
            FileDelete(stagedPath)
        ; Ahk2Exe embeds this build-time helper payload into SteamShell.exe.
        FileInstall "build\SteamShell-Helper.exe", stagedPath, true
        if !FileExist(stagedPath) || FileGetSize(stagedPath) <= 0
            throw Error("The embedded helper payload could not be extracted.")
        extractedVersion := ""
        try extractedVersion := FileGetVersion(stagedPath)
        if (extractedVersion != ElevatedHelperExpectedVersion)
            throw Error(
                "The extracted helper version was "
                . (extractedVersion != "" ? extractedVersion : "unavailable")
                . "; expected " ElevatedHelperExpectedVersion ".")
        FileMove(stagedPath, targetPath, true)
        if !FileExist(targetPath)
            || FileGetVersion(targetPath) != ElevatedHelperExpectedVersion
            throw Error("The installed helper could not be verified.")
        return true
    } catch as err {
        ; A_LastError is read FIRST: the cleanup below issues its own file calls
        ; and would overwrite the code that explains the failure.
        lastError := A_LastError
        try {
            if FileExist(stagedPath)
                FileDelete(stagedPath)
        }
        ; err.Message alone is not diagnosable. AutoHotkey's file commands throw
        ; with the bare message "Failed", so a real install produced the log line
        ; "Extraction failed: Failed Run SteamShell as administrator ..." --
        ; naming neither the path nor the reason, and giving advice the user had
        ; already followed. Access denied writing into an Administrators-only
        ; directory is the expected failure for an unelevated run, and it has to
        ; be distinguishable from a missing payload at a glance.
        failureReason := DescribeFileFailure(err, lastError, targetPath)
        return false
    }
}

; SteamShellPathIsAdminOnlyWritable and ElevatedHelperLocationIsProtected used to
; be defined here. They now live in SteamShell-Shared.ahk, because XFE's opt-in
; RTSS helper has to ask the same two questions about the same payload, and
; neither function knows anything about a shell replacement: they take a path and
; an expected version and inspect owner, DACL and readability.
;
; The deployment half stayed here on purpose. Setup Assistant, the embedded
; payload, the installation modes and the protected on-demand task are all
; standalone concepts; only the GATE is shared. See XFE_PARITY_NOTES.md, which
; previously recorded that these two would never be shared and now records why
; that was reversed.

; Applied to the component bin directory in every installation mode, including
; portable, where the surrounding folder is deliberately user-writable for the
; INI, logs, and backups. Only bin is locked down, so the writable data layout is
; unchanged and only the elevated payload becomes administrator-owned.
HardenElevatedHelperDirectory(binDirectory, &failureReason) {
    failureReason := ""
    if !A_IsAdmin {
        failureReason := "Administrator approval is required to secure the helper directory."
        return false
    }
    icaclsPath := A_WinDir "\System32\icacls.exe"
    ownerCommandLine := QuoteWindowsCommandLineArg(icaclsPath)
        . " " QuoteWindowsCommandLineArg(binDirectory)
        . " /setowner " QuoteWindowsCommandLineArg("*S-1-5-32-544")
        . " /T /C"
    try ownerExitCode := RunWait(ownerCommandLine, A_WinDir, "Hide")
    catch as err {
        failureReason := err.Message
        return false
    }
    if (ownerExitCode != 0) {
        failureReason := "icacls /setowner returned exit code " ownerExitCode "."
        return false
    }
    ; The grant applies to the DIRECTORY ONLY -- deliberately no /T.
    ;
    ; (OI) and (CI) are inheritance flags and mean nothing on a file. Running
    ; this same string with /T made icacls apply it to SteamShell-Helper.exe as
    ; well, where the flags are invalid, so the grant was rejected for the file
    ; -- but /inheritance:r had already stripped the ACEs it would otherwise
    ; have inherited. The file was left with an EMPTY DACL, which denies
    ; everyone everything including Administrators, and /C suppressed the error
    ; while the process still exited 0 so Setup recorded a success.
    ;
    ; Observed on hardware 2026-08-02: the directory listed all three ACEs
    ; correctly while `icacls` on the helper listed none at all. The helper
    ; could not be launched, and could not even be READ -- which is what made
    ; the main process believe it was missing and try to re-extract it into a
    ; directory only administrators can write, producing an "extraction failed"
    ; log line for a file that was sitting right there.
    commandLine := QuoteWindowsCommandLineArg(icaclsPath)
        . " " QuoteWindowsCommandLineArg(binDirectory)
        . " /inheritance:r"
        . " /grant:r " QuoteWindowsCommandLineArg("*S-1-5-18:(OI)(CI)F")
        . " " QuoteWindowsCommandLineArg("*S-1-5-32-544:(OI)(CI)F")
        . " " QuoteWindowsCommandLineArg("*S-1-5-32-545:(OI)(CI)RX")
    try exitCode := RunWait(commandLine, A_WinDir, "Hide")
    catch as err {
        failureReason := err.Message
        return false
    }
    if (exitCode != 0) {
        failureReason := "icacls returned exit code " exitCode "."
        return false
    }
    ; Now make the contents inherit what the directory just got. /reset replaces
    ; a child's ACL with the inherited default, which is the effective,
    ; non-inheritable form of the three ACEs above -- the thing the flagged
    ; grant could never produce on a file.
    ;
    ; A non-zero exit here is not fatal: the wildcard matches nothing when the
    ; directory is still empty, which is the normal case on the first pass,
    ; before the payload is extracted. The verification after deployment is what
    ; decides whether the result is acceptable.
    resetCommandLine := QuoteWindowsCommandLineArg(icaclsPath)
        . " " QuoteWindowsCommandLineArg(binDirectory "\*")
        . " /reset /T /C /Q"
    try RunWait(resetCommandLine, A_WinDir, "Hide")
    return true
}

; ==============================================================================
; PRODUCT SELECTION (SteamShell shell replacement vs SteamShell-XFE companion)
; ==============================================================================
; SteamShell.exe is the installer for both products. Which one a machine has is a
; single recorded fact, because every later decision depends on it: whether the
; Windows shell was registered, whether an elevated helper exists, and what an
; uninstall has to undo. Asking the user is the fallback for a missing or
; contradicted record, not the normal path -- a question the installer should be
; able to answer itself is a question that collects wrong answers.
SteamShellProductIsXfe(product) {
    return StrLower(Trim(product)) = "xfe"
}

NormalizeSteamShellProduct(product) {
    return SteamShellProductIsXfe(product) ? "XFE" : "Standalone"
}

; The product this machine actually has, resolved from the recorded value and
; cross-checked against what is on disk. Returns "" when the two disagree or
; nothing is recorded, which is the only case that justifies asking.
ResolveInstalledSteamShellProduct(&product, &detail) {
    global SteamShellRegKey
    product := ""
    detail := ""
    recorded := ""
    try recorded := RegRead(SteamShellRegKey, "Product")
    recorded := NormalizeSteamShellProduct(recorded)
    recordedIsPresent := false
    try recordedIsPresent := RegRead(SteamShellRegKey, "Product") != ""

    xfePath := ""
    try xfePath := RegRead(SteamShellRegKey, "XfeInstalledPath")
    xfeOnDisk := xfePath != "" && FileExist(xfePath) != ""
    shellPath := ""
    try shellPath := RegRead(SteamShellRegKey, "InstalledPath")
    shellOnDisk := shellPath != "" && FileExist(shellPath) != ""

    if !recordedIsPresent {
        ; No record. Infer from what is REGISTERED, and only when exactly one
        ; product is.
        ;
        ; This used to infer from executables on disk, which both uninstalls
        ; deliberately leave behind. After removing either product the file
        ; stayed, so "exactly one installed" was answered from residue: a
        ; machine that had run both reported an ambiguity that never resolved,
        ; and one that had removed XFE still reported XFE.
        xfeRegistered := SteamShellXfeLogonTaskExists()
        if !xfeRegistered {
            try xfeRegistered := ToBool(
                RegRead(SteamShellRegKey, "XfeLogonTaskRegistered", "false"), false)
        }
        shellRegistered := SteamShellIsRegisteredWindowsShell()
        if !shellRegistered {
            recordedShellPath := ""
            try recordedShellPath := RegRead(SteamShellRegKey, "RegisteredPath")
            shellRegistered := Trim(recordedShellPath) != ""
        }
        if (xfeRegistered && !shellRegistered) {
            product := "XFE"
            detail := "No product was recorded; only XFE is registered to start."
            return true
        }
        if (shellRegistered && !xfeRegistered) {
            product := "Standalone"
            detail := "No product was recorded; only the shell is registered."
            return true
        }
        detail := xfeRegistered && shellRegistered
            ? "No product was recorded and both a shell and an XFE registration were found."
            : "No product was recorded and nothing is registered to start."
        return false
    }

    if (SteamShellProductIsXfe(recorded) && !xfeOnDisk) {
        detail := "XFE is recorded, but " (xfePath != "" ? xfePath : "its executable")
            . " is missing."
        return false
    }
    if (!SteamShellProductIsXfe(recorded) && !shellOnDisk) {
        detail := "A shell installation is recorded, but "
            . (shellPath != "" ? shellPath : "its executable") " is missing."
        return false
    }
    product := recorded
    detail := "Recorded product: " recorded "."
    return true
}

GetXfeInstalledPath() {
    global SteamShellRegKey
    recorded := ""
    try recorded := RegRead(SteamShellRegKey, "XfeInstalledPath")
    return Trim(recorded)
}

ExtractEmbeddedXfe(targetPath, &failureReason, forceReplace := false) {
    global ScriptPid, XfeExpectedVersion
    failureReason := ""
    if !A_IsCompiled {
        failureReason := "The XFE companion is embedded only in the compiled SteamShell.exe."
        return false
    }
    targetDirectory := ""
    SplitPath(targetPath, , &targetDirectory)
    stagedPath := targetPath ".extract-" ScriptPid ".tmp"
    try {
        DirCreate(targetDirectory)
        existingVersion := ""
        if FileExist(targetPath)
            try existingVersion := FileGetVersion(targetPath)
        if (!forceReplace && existingVersion = XfeExpectedVersion)
            return true
        if FileExist(stagedPath)
            FileDelete(stagedPath)
        ; Ahk2Exe embeds this build-time companion payload into SteamShell.exe.
        FileInstall "build\SteamShell-XFE.exe", stagedPath, true
        if !FileExist(stagedPath) || FileGetSize(stagedPath) <= 0
            throw Error("The embedded XFE payload could not be extracted.")
        extractedVersion := ""
        try extractedVersion := FileGetVersion(stagedPath)
        if (extractedVersion != XfeExpectedVersion)
            throw Error(
                "The extracted XFE version was "
                . (extractedVersion != "" ? extractedVersion : "unavailable")
                . "; expected " XfeExpectedVersion ".")
        FileMove(stagedPath, targetPath, true)
        if !FileExist(targetPath)
            || FileGetVersion(targetPath) != XfeExpectedVersion
            throw Error("The installed XFE companion could not be verified.")
        return true
    } catch as err {
        ; A_LastError is read FIRST: the cleanup below issues its own file calls
        ; and would overwrite the code that explains the failure.
        lastError := A_LastError
        try {
            if FileExist(stagedPath)
                FileDelete(stagedPath)
        }
        ; err.Message alone is not diagnosable. AutoHotkey's file commands throw
        ; with the bare message "Failed", so a real install produced the log line
        ; "Extraction failed: Failed Run SteamShell as administrator ..." --
        ; naming neither the path nor the reason, and giving advice the user had
        ; already followed. Access denied writing into an Administrators-only
        ; directory is the expected failure for an unelevated run, and it has to
        ; be distinguishable from a missing payload at a glance.
        failureReason := DescribeFileFailure(err, lastError, targetPath)
        return false
    }
}

; XFE's startup route. Deliberately NOT the helper's HighestAvailable task:
; XFE is a normal-integrity companion and must stay that way, so the principal
; runs at LeastPrivilege. Elevating it would hand it the exact privilege the
; whole two-product split exists to avoid.
RegisterXfeLogonTask(xfePath, &failureReason) {
    global ExpectedInteractiveUserSid, ScriptPid
    failureReason := ""
    if !A_IsAdmin {
        failureReason := "Task registration requires administrator approval."
        return false
    }
    sidText := ExpectedInteractiveUserSid
    if (sidText = "" && !GetCurrentProcessUserSid(&sidText, &sidError)) {
        failureReason := "The task user SID could not be determined (" sidError ")."
        return false
    }
    SplitPath(xfePath, , &xfeDirectory)
    ; Built by SteamShell-Common.ahk, which the companion also uses. Setup used
    ; to emit its own XML with no logon delay, so a Setup-installed companion
    ; raced Xbox FSE at sign-in while the documentation promised it would not.
    taskXml := XfeLogonTaskXml(sidText, xfePath, "", xfeDirectory)
    xmlPath := A_Temp "\SteamShell-xfe-task-" ScriptPid ".xml"
    try {
        if FileExist(xmlPath)
            FileDelete(xmlPath)
        FileAppend(taskXml, xmlPath, "UTF-16")
        ; Drop the name the companion used to register under before creating
        ; ours, so the two routes converge on one task.
        legacyDelete := QuoteWindowsCommandLineArg(A_WinDir "\System32\schtasks.exe")
            . " /delete /tn " QuoteWindowsCommandLineArg(XfeLogonTaskLegacyName())
            . " /f"
        try RunWait(legacyDelete, A_WinDir, "Hide")
        taskCommand := QuoteWindowsCommandLineArg(A_WinDir "\System32\schtasks.exe")
            . " /create /tn " QuoteWindowsCommandLineArg(XfeLogonTaskName())
            . " /xml " QuoteWindowsCommandLineArg(xmlPath) " /f"
        exitCode := RunWait(taskCommand, A_WinDir, "Hide")
        if (exitCode != 0)
            throw Error("schtasks /create returned exit code " exitCode ".")
        return true
    } catch as err {
        failureReason := err.Message
        return false
    } finally {
        try {
            if FileExist(xmlPath)
                FileDelete(xmlPath)
        }
    }
}

; The companion registers this lazily the first time elevated RTSS writes are
; used, so an uninstall has to clear it even though Setup never created it.
RemoveXfeElevatedHelperTask() {
    taskCommand := QuoteWindowsCommandLineArg(A_WinDir "\System32\schtasks.exe")
        . " /delete /tn "
        . QuoteWindowsCommandLineArg("SteamShell XFE Elevated RTSS Helper") " /f"
    try return RunWait(taskCommand, A_WinDir, "Hide") = 0
    return false
}

RemoveXfeLogonTask() {
    ; Both names: a machine may carry the one the companion used to register
    ; under, and leaving it behind would keep starting XFE after an uninstall.
    ;
    ; Success means the task is not there afterwards, not that a deletion ran.
    ; schtasks /delete exits non-zero when the task does not exist, and this used
    ; to report that as failure: RemoveSteamShellXfeInstallation returns this
    ; value, so an uninstall that had nothing to remove told the user "the
    ; installation could not be fully removed" while every other part of it had
    ; in fact succeeded.
    ;
    ; It is reachable two ways. An install whose logon task was declined has no
    ; task to delete. And the product prompt is reached precisely because nothing
    ; is registered, so the hand-picked XFE removal would always have said it
    ; failed.
    failed := false
    for _, name in [XfeLogonTaskName(), XfeLogonTaskLegacyName()] {
        taskCommand := QuoteWindowsCommandLineArg(A_WinDir "\System32\schtasks.exe")
            . " /delete /tn " QuoteWindowsCommandLineArg(name) " /f"
        deleted := false
        try deleted := RunWait(taskCommand, A_WinDir, "Hide") = 0
        if (deleted)
            continue
        ; Non-zero is ambiguous: absent, or present and undeletable. Only the
        ; second is a failure worth reporting.
        if SteamShellXfeLogonTaskExists(name) {
            LogLine("Uninstall: the XFE logon task " name
                . " still exists after a delete attempt.", "Warning")
            failed := true
        }
    }
    return !failed
}

ElevatedHelperTaskName() {
    return "SteamShell Elevated Input Helper"
}

RegisterElevatedHelperTask(helperPath, mainPath, settingsFile, helperLog, &failureReason) {
    global ExpectedInteractiveUserSid, ScriptPid
    failureReason := ""
    if !A_IsAdmin {
        failureReason := "Task registration requires administrator approval."
        return false
    }
    sidText := ExpectedInteractiveUserSid
    if (sidText = "" && !GetCurrentProcessUserSid(&sidText, &sidError)) {
        failureReason := "The task user SID could not be determined (" sidError ")."
        return false
    }
    ; --product is explicit even though standalone is the helper's default. The
    ; helper treats any unrecognised value as standalone precisely so a
    ; standalone user never silently gets the narrower XFE helper, and naming it
    ; here means the task XML records which product registered the task.
    taskArguments := SharedElevatedHelperArguments(
        "standalone", 0, mainPath, settingsFile, helperLog)
    SplitPath(helperPath, , &helperDirectory)
    ; Built by SteamShell-Common.ahk; the companion registers the same shape of
    ; task for its own helper and the two used to be written out separately.
    SplitPath(helperPath, , &helperDirectory)
    taskXml := ElevatedHelperTaskXml(
        sidText, helperPath, taskArguments, helperDirectory)
    xmlPath := A_Temp "\SteamShell-helper-task-" ScriptPid ".xml"
    try {
        if FileExist(xmlPath)
            FileDelete(xmlPath)
        FileAppend(taskXml, xmlPath, "UTF-16")
        taskCommand := QuoteWindowsCommandLineArg(A_WinDir "\System32\schtasks.exe")
            . " /create /tn " QuoteWindowsCommandLineArg(ElevatedHelperTaskName())
            . " /xml " QuoteWindowsCommandLineArg(xmlPath) " /f"
        exitCode := RunWait(taskCommand, A_WinDir, "Hide")
        if (exitCode != 0)
            throw Error("schtasks /create returned exit code " exitCode ".")
        return true
    } catch as err {
        failureReason := err.Message
        return false
    } finally {
        try {
            if FileExist(xmlPath)
                FileDelete(xmlPath)
        }
    }
}

StartElevatedHelperTask(helperPath, &helperPid, &failureReason) {
    helperPid := 0
    failureReason := ""
    existingPids := CaptureExecutablePidSet(helperPath)
    taskCommand := QuoteWindowsCommandLineArg(A_WinDir "\System32\schtasks.exe")
        . " /run /tn " QuoteWindowsCommandLineArg(ElevatedHelperTaskName())
    try exitCode := RunWait(taskCommand, A_WinDir, "Hide")
    catch as err {
        failureReason := err.Message
        return false
    }
    if (exitCode != 0) {
        failureReason := "schtasks /run returned exit code " exitCode "."
        return false
    }
    helperPid := WaitForNewExecutablePid(helperPath, existingPids, 5000)
    if !helperPid {
        failureReason := "The task ran but no new helper process was observed."
        return false
    }
    return true
}

RemoveElevatedHelperTask() {
    taskCommand := QuoteWindowsCommandLineArg(A_WinDir "\System32\schtasks.exe")
        . " /delete /tn " QuoteWindowsCommandLineArg(ElevatedHelperTaskName())
        . " /f"
    try return RunWait(taskCommand, A_WinDir, "Hide") = 0
    return false
}

ElevatedGeometryEventName() {
    global ScriptPid
    return "Local\SteamShellGeometry-" ScriptPid
}

EnsureElevatedGeometryEvent() {
    global ElevatedGeometryEventHandle
    if ElevatedGeometryEventHandle
        return true
    ElevatedGeometryEventHandle := DllCall(
        "Kernel32\CreateEventW",
        "Ptr", 0,
        "Int", true,  ; manual reset: the runtime mode persists until changed
        "Int", false,
        "WStr", ElevatedGeometryEventName(),
        "Ptr")
    if !ElevatedGeometryEventHandle
        LogLine(
            "The elevated-geometry coordination event could not be created ("
            . A_LastError ").", "Warning")
    return ElevatedGeometryEventHandle != 0
}

; ------------------------------------------------------------------------------
; Elevated RTSS frame cap request -- per-tree half
; ------------------------------------------------------------------------------
; The request channel lives entirely in SteamShell-Shared.ahk now, including
; ElevatedRtssRequestPath(). "The two programs keep their data in different
; places" was the reason this last piece stayed per-tree, and it was a reason to
; ask the product for its directory rather than to write the function twice --
; the two copies differed in SteamShellDataDir against A_ScriptDir and in
; nothing else. ProductDataDir() is that question; see the seam below.

SetElevatedGeometryRuntimeEnabled(enabled) {
    global ElevatedGeometryEventHandle
    if !EnsureElevatedGeometryEvent()
        return false
    functionName := enabled ? "SetEvent" : "ResetEvent"
    return DllCall(
        "Kernel32\" functionName,
        "Ptr", ElevatedGeometryEventHandle,
        "Int") != 0
}

; ------------------------------------------------------------------------------
; Automatic mouse mode, published to the elevated helper
; ------------------------------------------------------------------------------
; Both processes gate controller input on the same question -- "is the controller
; a mouse right now?" -- and they used to answer it independently. They could
; not agree, because the answer depends on DesktopMode, which is shell state the
; helper has no way to observe.
;
; So the helper had a hardcoded four-name allowlist standing in for it. In
; desktop mode this tree answers "everything except the exclusion list", and the
; helper answered "taskmgr, mmc, control, systemsettingsadminflows" -- which
; means that for EVERY elevated window outside those four, one process thought
; automatic mouse mode was on and the other thought it was off. The user got the
; five normal-integrity builtins this tree keeps (on-screen keyboard, touch
; keyboard, Explorer, Quick Menu, Control Panel) and no cursor movement, no
; scrolling and no click from the helper to use them with. An elevated installer
; or regedit is the ordinary case.
;
; The fix is not a better list. It is that there is only one answer and this
; process owns it: AutoMouseModeActive() is authoritative, and its result is
; published on the same tick it is computed. Manual reset, exactly like the
; geometry event -- the mode persists until this process changes it.
;
; Only the automatic half crosses. The helper reads the physical View/Back
; button from the same controller and ORs it in itself, so a held button still
; works even if this event never arrives.



StartElevatedInputHelper() {
    global EnableElevatedInputHelper, ElevatedHelperPath, ElevatedHelperPid
    global ElevatedHelperAvailable, ElevatedHelperLastError
    global SettingsPath, ScriptPid, SteamShellInstallationMode
    global ElevatedHelperExpectedVersion

    EnableElevatedInputHelper := ReadElevatedHelperPreference()
    ElevatedHelperAvailable := false
    ElevatedHelperPid := 0
    if !EnableElevatedInputHelper {
        ElevatedHelperLastError := "Disabled in Settings."
        LogLine("Elevated helper is disabled in Settings.")
        return false
    }
    if A_IsAdmin {
        ElevatedHelperLastError :=
            "SteamShell itself was launched elevated; helper isolation is unavailable."
        LogLine(ElevatedHelperLastError, "Warning")
        return false
    }
    ; Created by the Medium-integrity parent and opened by the verified helper.
    ; It lets desktop/safe mode disable geometry without also losing elevated
    ; controller input, and fails closed until ApplyRuntimeTimers signals it.
    SetElevatedGeometryRuntimeEnabled(false)

    ElevatedHelperPath := GetElevatedHelperPath()
    ; Do not even attempt the write when it cannot possibly succeed.
    ;
    ; The helper's directory is administrator-only by design, so an unelevated
    ; session can never extract into it. Trying anyway produced an access-denied
    ; failure reported as "Extraction failed", which reads like a broken or
    ; missing payload and sent debugging in the wrong direction -- especially
    ; when the real cause was that the deployed helper could not be READ, so its
    ; version came back empty and looked like a mismatch. Name the actual
    ; remedy instead.
    if !A_IsAdmin {
        installedVersion := ""
        try installedVersion := FileGetVersion(ElevatedHelperPath)
        if (installedVersion != ElevatedHelperExpectedVersion) {
            ElevatedHelperLastError := installedVersion = ""
                ? "The installed helper is missing or cannot be read by this account. "
                    . "Run Setup from an elevated SteamShell session to repair it."
                : "The installed helper is version " installedVersion "; this build "
                    . "expects " ElevatedHelperExpectedVersion ". Run Setup from an "
                    . "elevated SteamShell session to replace it."
            LogLine("Elevated helper: " ElevatedHelperLastError, "Warning")
            return false
        }
    }
    ; Expected on the first normal start after the main EXE is replaced by hand:
    ; the installed helper is the previous version and the directory holding it is
    ; administrator-only, which is the point. Setup is the supported way to
    ; replace it, so say so rather than reporting a bare file error.
    if !ExtractEmbeddedElevatedHelper(ElevatedHelperPath, &extractError) {
        ElevatedHelperLastError := "Extraction failed: " extractError
            . " Run SteamShell as administrator and apply Setup to install the matching helper."
        LogLine("Elevated helper " ElevatedHelperLastError, "Warning")
        return false
    }
    ; Fail closed. Setup secures this directory in every installation mode, so a
    ; failure here means the helper was deployed by an older build or the folder
    ; was relocated by hand. Elevating it anyway is the one thing this whole
    ; split-integrity design exists to prevent.
    if !ElevatedHelperLocationIsProtected(ElevatedHelperPath, &protectionError) {
        ElevatedHelperLastError :=
            "The installed helper is not administrator-protected, so it was not elevated. "
            . protectionError
            . " Run SteamShell as administrator and apply Setup again to re-secure it."
        LogLine("Elevated helper: " ElevatedHelperLastError, "Warning")
        return false
    }
    ; Beside the helper rather than in the writable data directory: an elevated
    ; process appending to a path the interactive user controls invites a
    ; reparse-point redirection onto a file it should never have touched.
    SplitPath(ElevatedHelperPath, , &helperDirectory)
    helperLog := helperDirectory "\SteamShell-Helper.log"
    helperArguments := SharedElevatedHelperArguments(
        "standalone", ScriptPid, "", SettingsPath, helperLog)
    commandLine := "*RunAs " QuoteWindowsCommandLineArg(ElevatedHelperPath)
        . " " helperArguments
    ; The gate is the security property, not the installation mode.
    ;
    ; It used to be `mode = "standard"`, which was a proxy for "the helper sits
    ; somewhere a non-administrator cannot replace it". Now that the helper is
    ; always in Program Files the proxy is unnecessary, and asking the real
    ; question also covers a Custom install that happens to be protected.
    ;
    ; A scheduled task is an UNPROMPTED elevation to whatever binary sits at its
    ; action path, so it is only ever safe when that path cannot be replaced by
    ; the interactive user. Fail closed: if the check cannot be completed, use
    ; explicit UAC.
    taskEligible := ElevatedHelperLocationIsProtected(
        ElevatedHelperPath, &taskProtectionError)
    if !taskEligible
        LogLine("Elevated helper: no scheduled task will be used because the "
            . "helper location is not administrator-protected ("
            . taskProtectionError "); elevation will prompt.", "Warning")
    if (taskEligible
        && StartElevatedHelperTask(
            ElevatedHelperPath, &taskHelperPid, &taskError)) {
        if WaitForVerifiedElevatedHelper(
            taskHelperPid, &taskVerificationError, 2000) {
            ElevatedHelperPid := taskHelperPid
            ElevatedHelperAvailable := true
            ElevatedHelperLastError :=
                "Running as PID " ElevatedHelperPid
                . " through the protected scheduled task."
            LogLine("Elevated helper: " ElevatedHelperLastError)
            return true
        }
        taskError := "Task process verification failed: " taskVerificationError
        ; A task process that did not verify is usually one Windows started with
        ; a normal token. Close it rather than leaving it behind while the direct
        ; route starts a second helper.
        if (taskHelperPid && ProcessExist(taskHelperPid))
            try ProcessClose(taskHelperPid)
    }
    if (taskEligible && taskError != "")
        LogLine(
            "Elevated helper scheduled task unavailable; requesting UAC directly: "
            . taskError, "Warning")
    try {
        Run(commandLine, A_ScriptDir, , &ElevatedHelperPid)
        ElevatedHelperAvailable := WaitForVerifiedElevatedHelper(
            ElevatedHelperPid, &directVerificationError, 2500)
        ElevatedHelperLastError := ElevatedHelperAvailable
            ? "Running as PID " ElevatedHelperPid "."
            : "The elevated helper could not be verified: " directVerificationError
        LogLine("Elevated helper: " ElevatedHelperLastError)
        return ElevatedHelperAvailable
    } catch as err {
        ElevatedHelperLastError := "Elevation was cancelled or failed: " err.Message
        LogLine("Elevated helper unavailable: " ElevatedHelperLastError, "Warning")
        return false
    }
}

; EnableElevatedInputHelper is a security control, and a security control that
; only takes effect at the next boot is not one. Turning it off used to leave the
; elevated process injecting for the rest of the session while Health Check
; happily reported it running.
SyncElevatedInputHelperWithSettings() {
    global EnableElevatedInputHelper, ElevatedHelperAvailable, ElevatedHelperPid
    global ElevatedHelperLastError, FirstRunSetupMode, SafeMode
    EnableElevatedInputHelper := ReadElevatedHelperPreference()
    if !EnableElevatedInputHelper {
        if (ElevatedHelperPid || ElevatedHelperAvailable)
            return StopElevatedHelper("disabled in Settings")
        ElevatedHelperLastError := "Disabled in Settings."
        return true
    }
    if (FirstRunSetupMode || SafeMode || A_IsAdmin)
        return false
    if (ElevatedHelperAvailable && ElevatedHelperPid
        && ProcessExist(ElevatedHelperPid))
        return true
    return StartElevatedInputHelper()
}

ElevatedHelperIsVerified() {
    global ElevatedHelperAvailable, ElevatedHelperPid, ElevatedHelperLastError
    static lastVerifiedPid := 0
    static lastVerificationTick := 0
    if !ElevatedHelperAvailable || !ElevatedHelperPid
        return false
    if !ProcessExist(ElevatedHelperPid) {
        ElevatedHelperAvailable := false
        ElevatedHelperLastError := "The helper process exited."
        return false
    }
    if (lastVerifiedPid != ElevatedHelperPid
        || A_TickCount - lastVerificationTick >= 1000) {
        lastVerificationTick := A_TickCount
        lastVerifiedPid := ElevatedHelperPid
        if !VerifyElevatedHelperProcess(ElevatedHelperPid, &verificationError) {
            ElevatedHelperAvailable := false
            ElevatedHelperLastError :=
                "Runtime verification failed: " verificationError
            return false
        }
    }
    return true
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

; Record the interactive identity for Health Check and verified application
; launches. The main shell is deliberately not elevated; the input helper owns
; the narrow elevated-window path.
InitializeExpectedInteractiveIdentity()

; Register cleanup before any cursor, splash, process, or shell side effects.
OnExit(ExitCleanup)

OnError(HandleUncaughtError)
; Armed once, unconditionally, and never disarmed.
;
; NOT inside ApplyRuntimeTimers: that function stops every timer and re-arms the
; ones the current mode wants, so the watchdog would be cancelled exactly when
; the poll loop was cancelled -- and a poll loop that has stopped is precisely
; the case this exists to cover. Safe mode, desktop mode and a disabled
; controller all reach that path.
SetTimer(ControllerMouseSafetyTick, 5000)

; ==============================================================================
; HELPERS (v2.0.19 compatibility)
; ==============================================================================

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
SettingsSchemaVersion=23                                   ; Internal schema used for safe settings upgrades

[Setup]
SetupState=Pending                                         ; Pending | InProgress | Complete
SetupVersion=1                                             ; Setup workflow version completed by this installation
Product=Standalone                                         ; Standalone (replaces the Windows shell) | XFE (companion beside Xbox FSE)
InstallationMode=Portable                                  ; Standard | Custom | Portable
InstallDirectory=                                          ; Directory containing SteamShell.exe after Setup completes
DataDirectory=                                             ; Writable settings, logs, backups, and support data

[Paths]
SteamPath=C:\Program Files (x86)\Steam\Steam.exe            ; Full path to Steam.exe

[BPM]
BpmTitle=Steam Big Picture Mode                             ; Big Picture window title (must match your BPM title)

[Steam]
MenuShortcut=^1                                            ; Steam Menu while Big Picture owns the foreground
QuickAccessShortcut=^2                                     ; Steam Quick Access shortcut
OverlayShortcut=+{Tab}                                     ; Steam overlay while a game owns the foreground
EnableViewButtonActions=false                              ; View/Back tap/hold action when not used as the mapping modifier; off by default in the shell
EnableViewTapAction=true                                   ; Tap with Steam in front -> Steam Menu
EnableViewHoldAction=true                                  ; Hold -> Quick Access (Steam) or overlay (in game)
ViewHoldMs=500                                             ; Hold threshold with Steam in front (200-5000)
ViewHoldInGameMs=1000                                      ; Hold threshold inside a game (200-5000)

[Features]
EnableElevatedInputHelper=true                             ; Launch the separate elevated window helper; applies immediately on reload; SteamShell.exe remains normal integrity
EnableSplashScreen=true                                     ; Show a black splash overlay during boot
EnableTaskbarHiding=true                                    ; Hide taskbar & tray windows (kiosk feel)
EnableDesktopBlackout=true                                  ; Black backdrop instead of the wallpaper and desktop icons
EnableWindowManagement=true                                 ; Center windows; maximize large windows (skips OSK + Steam KB)
EnableAutoHideCursor=true                                   ; Hide cursor after MouseHideDelay inactivity
EnableAutoMouseMode=true                                    ; Allow AutoMouseExeList to act as a virtual View/Back hold (list still required)
EnableDesktopAutoMouseMode=true                             ; Automatically use controller mouse in all desktop-mode apps except exclusions
EnableSteamRefocusMode=true                                 ; Refocus BPM after SteamRefocusDelay when nothing else is visible
EnableGameForegroundAssist=true                             ; Detect fullscreen-ish games and bring them to front
EnableAlwaysFocus=true                                      ; Allow specific apps (ExeList) to always win focus over Steam
EnableMouseParkOnBoot=true                                  ; Move pointer to the active display edge once during startup
EnableMouseParkOnFocusChange=true                           ; Park once when SteamShell actually changes the focused window

[Timing]
SplashScreenDuration=10000                                  ; Splash duration in milliseconds (0 disables fade)
MouseMonitorInterval=250                                    ; Mouse polling interval (ms)
MouseHideDelay=1000                                         ; Hide cursor after this many ms without movement
SteamRefocusDelay=1000                                      ; Wait this many ms before refocusing BPM (when no windows remain)
SteamStartupGraceMs=120000                                  ; Log startup warning after this delay; restore arms only after Steam is observed
SteamExitConfirmMs=4000                                     ; Steam must remain closed this long before automatic desktop restore (ms)

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
MinWidthPercent=0.30                                        ; Only maximize windows wider than this % of screen width
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
GameAssistLogEvenWhenSkipped=true                           ; Log candidates even when skipped due to Steam not foreground

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
LogRotateMaxKB=256                                          ; Rotate log when it exceeds this many KB
LogRotateBackups=2                                          ; Keep this many rotated backups

[MousePark]
MouseParkEdge=Right                                        ; Right | Left vertical edge of the active display
MouseParkRightOffsetPx=50                                   ; Logical push toward the right edge (clamped to the target display)
MouseParkYPercent=0.50                                      ; Park cursor at this % of screen height

[StartupPrograms]
Enable=true                                                 ; Start additional user-defined programs at boot (hidden)
DelayMs=2000                                                ; Wait this long after SteamShell starts before launching them
StaggerMs=1200                                              ; Gap between each program launch
WindowMode=Hidden                                           ; Hidden | Minimized | Normal
; Define programs as Program1..Program20. Format:
; ProgramN="C:\Path\App.exe" --arg1 --arg2
; Quotes recommended if the path contains spaces. Everything after the exe is treated as arguments.
; Programs use the verified standard-user token; Hidden mode also sweeps away windows they create briefly.
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

Enable=true
SteamForegroundSec=30
RequireNoGame=true
CooldownSec=300
CheckIntervalMs=2000
GracefulCloseMs=4000
HardKill=true

; Advanced (only used when RequireNoGame=true and UseCpuAudio=true)
UseCpuAudio=true
CpuThreshold=12
AudioPeakThreshold=0.02
; Busy guard (optional): skip cleanup if launchers appear to be actively downloading/updating
DownloadGuard=true
DownloadGuardMode=Balanced
; Pipe-separated EXEs (case-insensitive). If an entry has no .exe, it will be appended.
LauncherExeList=UbisoftConnect.exe|upc.exe|EpicGamesLauncher.exe|EADesktop.exe|EALauncher.exe|Origin.exe|Battle.net.exe|RockstarGamesLauncher.exe|GalaxyClient.exe|RiotClientServices.exe|RiotClientUx.exe|wgc.exe|Heroic.exe
BackgroundExeList=UbisoftConnectService.exe|UplayWebCore.exe|UplayService.exe|EpicWebHelper.exe|EABackgroundService.exe|BlizzardUpdateAgent.exe|Agent.exe|RockstarService.exe|SocialClubHelper.exe|GalaxyClientService.exe|GalaxyCommunication.exe|RiotClientUxRender.exe|legendary.exe|gogdl.exe|nile.exe

; Safety: never kill these
ExcludeExeList=steam.exe|steamwebhelper.exe|SteamShell.exe

[Controller]
; auto reads RawInput whenever HID reports are arriving and XInput otherwise, so
; a controller XInput already handles is unaffected. Set rawinput to isolate the
; HID path for diagnosis -- it deliberately does NOT fall back.
Backend=auto                                                ; auto | rawinput | xinput
RawInputProbe=false                                         ; Log raw HID reports; diagnostic only
DiagnosticLogging=false                                     ; Log backend/slot detail on change; diagnostic only
RawInputStaleMs=5000                                        ; Treat RawInput as silent after this gap
EnableControllerMouseMode=true                              ; Enable controller mouse/keyboard mapping (hold View/Back)
EnablePersistentMouseMode=false                             ; Apply controller mouse/mappings without holding View/Back
ControllerIndex=0                                           ; 0=first controller
ControllerPollIntervalMs=15                                 ; Poll rate (ms). 15 fires every Windows timer tick; 16 waits for the next
ControllerDeadzone=3000                                     ; Stick deadzone (0-32767)
ControllerMouseSpeed=3200                                   ; Cursor pixels per SECOND at full deflection
ControllerMouseFastMultiplier=2.5                           ; Multiplier while RT is held
ControllerScrollIntervalMs=80                               ; Min ms between scroll ticks
ControllerScrollStep=1                                      ; Wheel notches per scroll tick
ControllerChordHoldMs=500                                   ; Long-press threshold (ms) for View/Back + button actions
AutoMouseExeList=explorer.exe|brave.exe|chrome.exe|msedge.exe|firefox.exe|notepad.exe|taskmgr.exe  ; EXEs where the View/Back mappings apply WITHOUT holding View/Back
DesktopAutoMouseExcludeExeList=                             ; Games/apps where desktop-wide automatic mouse must stay disabled

[QuickMenu]
Enable=true                                                 ; Hold L3+R3 to open/close the living-room quick menu
ChordHoldMs=500                                             ; Required L3+R3 hold time
TaskForceCloseHoldMs=1200                                   ; Hold X this long in Task Switcher to force-close a process
MainOrder=Audio|Display|RTSS|SteamMenu|SteamQuickAccess|Tasks|GameBar|Keyboard|MouseMode|Settings|System
HiddenItems=                                                ; Optional rows to hide; Settings and System stay available
ShowGameDetection=true                                      ; Game Detection row under System: what the window engine scored and why
GameScoreMaxRows=8                                          ; How many scored candidates the Game Detection page lists (1-20)
AccentColor=Purple                                          ; Steam Blue|Blue|Purple|Magenta|Red|Orange|Yellow|Green|Teal|Custom
AccentColorCustom=107C10                                    ; RRGGBB used when AccentColor=Custom; invalid values fall back to Purple

[RTSS]
EnableIntegration=true                                      ; Enabled by default; the menu reports setup required when RTSS is unavailable
Path=C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe
UseDllIntegration=true                                      ; Live state/direct control through RTSSHooks64.dll when available
OverlayControlMode=Separate                                ; Toggle | Separate
OverlayToggleShortcut=^+o                                   ; Ctrl+Shift+O - configure the same overlay hotkey in RTSS
OverlayOnShortcut=^+1                                      ; Separate mode: Ctrl+Shift+1 - Show OSD
OverlayOffShortcut=^+2                                     ; Separate mode: Ctrl+Shift+2 - Hide OSD
FrameLimiterControlMode=Separate                           ; Toggle | Separate
PresetFrameCap=158                                         ; Named Preset entry in the live Frame Limit cycle
CustomFrameCap=158                                         ; Last Custom FPS value; updated when Custom is adjusted
RestoreFrameLimitOnStartup=true                            ; Reapply the last Frame Limit selection once RTSS is running
EnableElevatedFrameCapWrites=true                          ; Let the elevated helper write the cap when RTSS is under Program Files
LastFrameCapMode=                                          ; Written by SteamShell: off | preset | configured | custom
LastFrameCapFps=0                                          ; Written by SteamShell: FPS of the last selection, kept while Off
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
    settingsDir := ""
    try SplitPath(SettingsPath, , &settingsDir)
    if (settingsDir != "")
        try DirCreate(settingsDir)
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

    if TryReadIniRaw("Features", "RunElevatedOnStartup", &legacyElevationValue) {
        retired.Push(Map(
            "section", "Features",
            "key", "RunElevatedOnStartup",
            "value", legacyElevationValue,
            "replacementSection", "Features",
            "replacementKey", "EnableElevatedInputHelper"))
    }

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

    ; Schema 22 drops the "Game" prefix from the two rotation keys. Rotation was
    ; never game-log-specific -- the same two values size and count the backups
    ; of the shell's own log and the elevated helper's log, neither of which is a
    ; game log. XFE had already named them without the prefix, so the products
    ; and the helper disagreed about what one setting was called, and the helper
    ; carried a branch on --product= for no reason but the spelling.
    for _, rotateKey in ["RotateMaxKB", "RotateBackups"] {
        if TryReadIniRaw("Logging", "GameLog" rotateKey, &legacyRotateValue) {
            retired.Push(Map(
                "section", "Logging",
                "key", "GameLog" rotateKey,
                "value", legacyRotateValue,
                "replacementSection", "Logging",
                "replacementKey", "Log" rotateKey))
        }
    }

    ; OFF is now the single logging disable state. The old boolean duplicated
    ; GameLogMode and could create contradictory combinations.
    if TryReadIniRaw("Logging", "EnableGameScoreLogging", &retiredLoggingToggle)
        retired.Push(Map("section", "Logging", "key", "EnableGameScoreLogging"))

    ; Row visibility moved to [QuickMenu] HiddenItems, which the Quick Menu
    ; layout manager edits. These two said the same thing for two of the eleven
    ; rows, so a user could hide Audio in one place and show it in the other.
    for _, retiredSection in ["AudioQuickControls", "DisplayQuickControls"] {
        if TryReadIniRaw(retiredSection, "Enable", &retiredQuickControl)
            retired.Push(Map("section", retiredSection, "key", "Enable"))
    }

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
    global SteamShellDataDir, SteamShellInstallationMode
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

    ; Schema 15 removes the old Controller Layout row and introduces Open
    ; Keyboard plus persistent Mouse Mode immediately after Game Bar. Preserve
    ; the user's remaining row order and visibility choices.
    if (sourceVersion < 15) {
        oldOrder := IniRead(workPath, "QuickMenu", "MainOrder", "")
        IniWrite(MigrateQuickMenuOrderForSchema15(oldOrder),
            workPath, "QuickMenu", "MainOrder")
        oldHidden := IniRead(workPath, "QuickMenu", "HiddenItems", "")
        migratedHidden := []
        for _, rawHiddenName in StrSplit(CleanIniValue(oldHidden, ""), "|") {
            hiddenName := StrLower(Trim(rawHiddenName))
            if (hiddenName != "" && hiddenName != "layout"
                && hiddenName != "keyboard" && hiddenName != "mousemode")
                migratedHidden.Push(hiddenName)
        }
        IniWrite(JoinWith(migratedHidden, "|"),
            workPath, "QuickMenu", "HiddenItems")
    }

    ; Schema 16 turns the old fallback-label value into a real Preset entry and
    ; gives Custom its own retained value. Seed Preset from the user's existing
    ; CustomFrameCap so an established cap such as 158 survives the split.
    if (sourceVersion < 16
        && !TryReadIniRaw("RTSS", "PresetFrameCap", &existingPresetCap)
        && TryReadIniRaw("RTSS", "CustomFrameCap", &legacyConfiguredCap)) {
        IniWrite(
            CleanIniValue(legacyConfiguredCap, "158"),
            workPath, "RTSS", "PresetFrameCap")
    }

    ; Setup state is new in schema 17. Any settings file old enough to need this
    ; migration already represents a working installation, including schema-0
    ; hand-authored files, so do not force established users through first-run.
    ; A genuinely new file is created at the current schema with Pending.
    if (sourceVersion < 17
        && !TryReadIniRaw("Setup", "SetupState", &legacySetupState)) {
        IniWrite("Complete", workPath, "Setup", "SetupState")
        IniWrite("1", workPath, "Setup", "SetupVersion")
        IniWrite(SteamShellInstallationMode,
            workPath, "Setup", "InstallationMode")
        IniWrite(A_ScriptDir, workPath, "Setup", "InstallDirectory")
        IniWrite(SteamShellDataDir, workPath, "Setup", "DataDirectory")
    }

    ; Schema 23 changes ControllerMouseSpeed's UNIT, so every value migrates --
    ; not only the former default. A stored 100 meant "100 pixels per poll tick";
    ; it now means "100 pixels per second", which is a cursor that barely moves.
    ; Leaving custom values alone would silently break exactly the users who had
    ; tuned it.
    ;
    ; x32, because 32 Hz is the rate the poll ACTUALLY ran at, not the 62.5 Hz the
    ; 16 ms setting implied. Windows quantises timers to about 15.625 ms and
    ; nothing raised the resolution, so a 16 ms request could not fire before
    ; 31.25 ms. The conversion preserves the speed the user has been living with
    ; rather than the speed the old setting claimed -- those differed by two, and
    ; the observed one is the one their thumb is calibrated to.
    if (sourceVersion < 23
        && TryReadIniRaw("Controller", "ControllerMouseSpeed", &oldMouseSpeed)) {
        convertedSpeed := ToInt(CleanIniValue(oldMouseSpeed, "100"), 100) * 32
        IniWrite(ClampInt(convertedSpeed, 200, 12000) "",
            workPath, "Controller", "ControllerMouseSpeed")
    }

    ; And the interval that caused it. 16 sat 0.375 ms past a 15.625 ms boundary,
    ; so it waited for the next one and halved the poll rate; 15 fires on every
    ; boundary. Only the exact former default moves, because a deliberately
    ; chosen interval is a deliberate choice. Safe to change now only because
    ; speed no longer depends on the tick rate.
    if (sourceVersion < 23
        && TryReadIniRaw("Controller", "ControllerPollIntervalMs", &oldPollInterval)
        && ToInt(CleanIniValue(oldPollInterval, "16"), 16) = 16)
        IniWrite("15", workPath, "Controller", "ControllerPollIntervalMs")

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

; CleanIniValue now lives in SteamShell-Common.ahk, because XFE and the elevated
; helper each had their own partial copy of it and XFE's could not strip a
; comment at all.

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

; The notification half of the shared seam. Standalone shows a toast; XFE writes
; to its status line. Shared code calls SharedNotify and neither tree has to know
; about the other's surface -- this is what let the display selection, safety
; revert and HDR control become one definition instead of two that drifted.

; Per-tree seam required by SteamShell-Shared.ahk.
;
; Takes an array of Map("section", "key", "value") and applies them as one unit.
; Standalone stages a copy and replaces the live INI only after every write
; succeeds, because it is the registered Windows shell and a half-written
; settings file is a machine that signs in to nothing. XFE implements the same
; name with direct writes, which is right for an ordinary application. Shared
; code calls this and does not have to know which.
; Per-tree seam required by SteamShell-Shared.ahk: does a learning wizard want
; this report instead of the decoder?
;
; While the wizard is open it consumes reports, because decoding as well would
; fire mappings from the very buttons being pressed to teach the layout.
; Single entry point for controller state.
;
; RawInput first, and it yields by itself: RawInputReadState answers false
; whenever no report has arrived inside RawInputStaleMs, so a machine whose
; controller XInput already handles never takes this path and behaves exactly as
; it did before the backend existed.
;
; An explicit "rawinput" does NOT fall back. The setting exists to isolate the
; backend for diagnosis, and a silent fallback makes it behave identically to
; auto -- which is what made a companion-side sleep test inconclusive once:
; input still worked, which looked like RawInput recovering when it was XInput
; the whole time.
ControllerReadState(&state) {
    global ControllerBackend, ActiveInputBackend
    wanted := StrLower(ControllerBackend)
    if (wanted = "rawinput" || wanted = "auto") {
        if RawInputReadState(&state) {
            SetActiveBackend("rawinput")
            return true
        }
        if (wanted = "rawinput") {
            SetActiveBackend("none")
            return false
        }
    }
    ; Every slot, not just the configured one -- see XInputResolveController.
    ; This asked XInput for the configured index and nothing else, so a pad that
    ; Steam Input moved to another slot mid-session simply stopped answering.
    ; (The old call is not quoted here on purpose: the rule that forbids it is a
    ; -notmatch over this file, and a comment quoting it would fail the build.)
    ;
    ; The buffer allocation that stood here is gone with it: XInputGetState
    ; already creates one when it is handed something that is not a Buffer, so
    ; the guard was a second answer to a question the callee had settled.
    if XInputResolveController(&state) {
        SetActiveBackend("xinput")
        return true
    }
    SetActiveBackend("none")
    return false
}

; Per-tree seam required by SteamShell-Shared.ahk: a modal dialog is up, so
; controller input must not also drive the shell behind it.
SharedPersistSettings(changes) {
    return CommitIniChanges(changes)
}

; Per-tree seam required by SteamShell-Shared.ahk. See the header above
; VerifyElevatedHelperProcess there for why this exists.
; A click on a Quick Menu row SELECTS it here; XFE activates it. Deliberate:
; the shell's menu is driven from the couch and a stray click should not fire an
; action, while XFE's is used at a desk with a pointer already in hand.
QuickMenuMouseChoose(index) {
    QuickMenuMouseSelect(index)
}

ProductIdentity() {
    static identity := Map(
        "name", "SteamShell",
        "exe", "steamshell.exe",
        "dirToken", "STEAMSHELL_DIR",
        "helperLabel", "Elevated helper",
        ; Shown at the top of the Quick Menu. Separate from "name", which is
        ; prose used inside sentences.
        "title", "SteamShell",
        ; Tray icon filename under assets\. Read by the shared
        ; ApplyTrayIconImage so the icon lifecycle has no per-tree copy.
        "icon", "SteamShell.ico")
    return identity
}

; Both of these are three-line wrappers binding this program's settings path and
; PID to the single staged-commit implementation in SteamShell-Common.ahk. The
; reasoning that used to live here went with the code; the companion now runs the
; same two functions instead of its own unstaged loop.
SweepAbandonedSettingsUpdates() {
    global SettingsPath, ScriptPid
    SweepAbandonedIniUpdates(SettingsPath, ScriptPid)
}

CommitIniChanges(changes, deletes := 0) {
    global SettingsPath, ScriptPid
    return CommitIniChangesAt(SettingsPath, ScriptPid, changes, deletes)
}

LoadSettings() {
    global AudioPeakThreshold, DEFAULT_AUDIO_PEAK_THRESHOLD
    AudioPeakThreshold := ReadNumber("GameForegroundAssist", "AudioPeakThreshold", DEFAULT_AUDIO_PEAK_THRESHOLD, 0.0, 1.0)
    global SteamPath, BpmTitle
    global EnableElevatedInputHelper
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
    global EnableDesktopAutoMouseMode, DesktopAutoMouseExcludeExeListRaw
    global DesktopAutoMouseExcludeExeSet
    global AlwaysFocusExeListRaw, AlwaysFocusCooldownMs, AlwaysFocusList
    global GameCPUThresholdPercent, FullscreenTolerance, FullscreenPosTolerancePx, GameForegroundCooldownMs
    global GameAllowZeroCpuAsCandidate, GameRequireSteamForeground, GameAssistLogEvenWhenSkipped
    global ScoreFullscreen, ScoreBorderlessLarge, ScoreTitleBonus
    global ScoreCpuAboveThreshold, ScoreCpuNonZeroBonus, GameMinScoreToActivate
    global EnableAudioAssist, ScoreAudioActive
    global EnableGameScoreLogging, GameLogMode, GameLogTopN, GameLogIntervalMs, GameLogIncludeTitles
    global GameLogRejectNearCandidates, GameLogRejectMinAreaPercent, LogRotateMaxKB, LogRotateBackups
    global ControllerBackend, EnableRawInputProbe, RawInputStaleMs
    global EnableControllerDiagnostics
    global MouseParkRightOffsetPx, MouseParkYPercent, MouseParkEdge
    global EnableLauncherCleanup, LauncherCleanupSteamForegroundSec, LauncherCleanupRequireNoGame, LauncherCleanupUseCpuAudio, LauncherCleanupCpuThreshold, LauncherCleanupAudioPeakThreshold, LauncherCleanupDownloadGuard, LauncherCleanupDownloadGuardMode
    global LauncherCleanupCooldownSec, LauncherCleanupCheckIntervalMs, LauncherCleanupGracefulCloseMs, LauncherCleanupHardKill
    global LauncherCleanupLauncherExeListRaw, LauncherCleanupBackgroundExeListRaw, LauncherCleanupExcludeExeListRaw
    global LauncherCleanupLauncherList, LauncherCleanupBackgroundList, LauncherCleanupExcludeSet
    global EnableControllerMouseMode, EnablePersistentMouseMode, ControllerIndex, ControllerPollIntervalMs, ControllerDeadzone, ControllerMouseSpeed, ControllerMouseFastMultiplier, ControllerScrollIntervalMs, ControllerScrollStep, ControllerChordHoldMs
    global EnableQuickMenu, EnableGameDetectionMenu, GameScoreMaxRows, QuickMenuChordHoldMs, TaskForceCloseHoldMs
    global QuickMenuMainOrderRaw, QuickMenuHiddenItemsRaw
    global QuickMenuMainOrder, QuickMenuHiddenItems
    global SteamMenuShortcut, SteamQuickAccessShortcut, SteamOverlayShortcut
    global EnableRTSSIntegration, RtssPath, RtssUseDllIntegration, RtssOverlayControlMode
    global RtssOverlayToggleShortcut, RtssOverlayOnShortcut, RtssOverlayOffShortcut
    global RtssFrameLimiterControlMode, RtssPresetFrameCap, RtssCustomFrameCap
    global RtssCustomFrameCapShortcut, RtssRestoreFrameLimitOnStartup
    global RtssElevatedFrameCapWrites, RtssFrameCapWriteBlocked
    global RtssLastFrameCapMode, RtssLastFrameCapFps
    global RtssFrameLimiterOnShortcut, RtssFrameLimiterOffShortcut
    global EnableViewSteamActions, EnableViewTapAction, EnableViewHoldAction
    global ViewHoldMs, ViewHoldInGameMs

    SteamPath := IniReadS("Paths", "SteamPath", SteamPath)
    BpmTitle := IniReadS("BPM", "BpmTitle", BpmTitle)
    SteamMenuShortcut := IniReadS("Steam", "MenuShortcut", "^1")
    SteamQuickAccessShortcut := IniReadS("Steam", "QuickAccessShortcut", "^2")
    SteamOverlayShortcut := IniReadS("Steam", "OverlayShortcut", "+{Tab}")
    ; Same keys, same defaults and same bounds as the companion, because it is
    ; the same feature reading the same section of the same-shaped file.
    EnableViewSteamActions := ReadBool("Steam", "EnableViewButtonActions", false)
    ; The keys both products read identically -- same global, reader,
    ; default and range. See LoadSharedSettings in SteamShell-Shared.ahk.
    LoadSharedSettings()

    EnableElevatedInputHelper := ReadBool("Features", "EnableElevatedInputHelper", true)
    EnableSplashScreen := ReadBool("Features", "EnableSplashScreen", true)
    EnableTaskbarHiding := ReadBool("Features", "EnableTaskbarHiding", true)
    EnableDesktopBlackout := ReadBool("Features", "EnableDesktopBlackout", true)
    EnableWindowManagement := ReadBool("Features", "EnableWindowManagement", true)
    EnableAutoHideCursor := ReadBool("Features", "EnableAutoHideCursor", true)
    EnableSteamRefocusMode := ReadBool("Features", "EnableSteamRefocusMode", true)
    EnableGameForegroundAssist := ReadBool("Features", "EnableGameForegroundAssist", true)
    EnableAlwaysFocus := ReadBool("Features", "EnableAlwaysFocus", true)
    legacyParkOnRefocus := IniReadS("Features","EnableMouseParkEveryRefocus","")
    EnableMouseParkOnBoot := ReadBool("Features", "EnableMouseParkOnBoot", true)
    EnableMouseParkOnFocusChange := ToBool(
        IniReadS("Features","EnableMouseParkOnFocusChange", legacyParkOnRefocus != "" ? legacyParkOnRefocus : "true"), true)
    ; Cursor hiding does not generate input or reset Windows idle timers, so the
    ; boot/refocus helpers remain safe internal behavior under Auto Hide Cursor.
    EnableCursorHideOnBoot := true
    EnableCursorHideOnRefocus := true

    SplashScreenDuration := ReadInt("Timing", "SplashScreenDuration", 10000, 0, 60000)

    ; Splash (Black or Video)
    SplashMode := IniReadS("Splash","Mode","Black")
    SplashVideoPath := IniReadS("Splash","VideoPath","")
    ; The INI default and the parse-failure fallback are deliberately the same
    ; value in each pair. When they disagreed, a malformed entry produced the
    ; opposite of the documented default rather than falling back to it.
    SplashVideoMute := ReadBool("Splash", "Mute", false)
    SplashVideoPlayFull := ReadBool("Splash", "PlayFullDuration", true)
    SplashVideoSafetyMaxMs := ReadInt("Splash", "SafetyMaxMs", 15000, 1000, 600000)
    SplashFadeOutMs := ReadInt("Splash", "FadeOutMs", 300, 0, 5000)
    SplashTopmostGuardMs := ReadInt("Splash", "TopmostGuardMs", 500, 0, 5000)
    SplashMpvPath := IniReadS("Splash","MpvPath","")
    SplashDebugOverlay := ReadBool("Splash", "DebugOverlay", false)
    SplashForceSDR := ReadBool("Splash", "ForceSDR", true)

    ; Coordinated-engine cadence and retry limits are intentionally fixed. The
    ; previous editable values allowed combinations that could not take effect
    ; because every policy decision begins with the shared inventory tick.
    WindowEngineTickIntervalMs := 500
    WindowEngineFocusIntervalMs := 1000
    WindowEngineGeometryRetryMs := 1000
    WindowEngineGeometryMaxAttempts := 3
    WindowEngineCpuSampleIntervalMs := 1000
    MouseMonitorInterval := ReadInt("Timing", "MouseMonitorInterval", 250, 50, 5000)
    MouseHideDelay := ReadInt("Timing", "MouseHideDelay", 1000, 0, 60000)
    SteamRefocusDelay := ReadInt("Timing", "SteamRefocusDelay", 1000, 0, 60000)
    SteamStartupGraceMs := ReadInt("Timing", "SteamStartupGraceMs", 120000, 10000, 600000)
    SteamExitConfirmMs := ReadInt("Timing", "SteamExitConfirmMs", 4000, 1000, 60000)

    MinWidthPercent := ReadNumber("WindowManagement", "MinWidthPercent", 0.30, 0.05, 1.00)

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
    EnableAutoMouseMode := ReadBool("Features", "EnableAutoMouseMode", true)
    EnableDesktopAutoMouseMode := ReadBool("Features", "EnableDesktopAutoMouseMode", true)
    AutoMouseExeListRaw := IniReadS("Controller", "AutoMouseExeList",
        DefaultAutoMouseExeList())
    AutoMouseExeSet := Map()
    for _, exe in ParseExeListPipe(AutoMouseExeListRaw)
        AutoMouseExeSet[exe] := true
    DesktopAutoMouseExcludeExeListRaw := IniReadS(
        "Controller", "DesktopAutoMouseExcludeExeList", "")
    DesktopAutoMouseExcludeExeSet := Map()
    for _, exe in ParseExeListPipe(DesktopAutoMouseExcludeExeListRaw)
        DesktopAutoMouseExcludeExeSet[exe] := true

    AlwaysFocusExeListRaw := IniReadS("AlwaysFocus","ExeList","")
    AlwaysFocusCooldownMs := ReadInt("AlwaysFocus", "AlwaysFocusCooldownMs", 1000, 0, 60000)
    AlwaysFocusList := []
    if EnableAlwaysFocus {
        for _, alwaysExe in ParseExeListPipe(AlwaysFocusExeListRaw) {
            if (alwaysExe != "steam.exe" && alwaysExe != "steamwebhelper.exe")
                AlwaysFocusList.Push(alwaysExe)
        }
    }
    AlwaysFocusExeListRaw := JoinPipe(AlwaysFocusList)

    GameCPUThresholdPercent := ReadNumber("GameForegroundAssist", "GameCPUThresholdPercent", 5.0, 0.0, 100.0)
    FullscreenTolerance := ReadNumber("GameForegroundAssist", "FullscreenTolerance", 0.98, 0.50, 1.00)
    FullscreenPosTolerancePx := ReadInt("GameForegroundAssist", "FullscreenPosTolerancePx", 2, 0, 200)
    GameForegroundCooldownMs := ReadInt("GameForegroundAssist", "GameForegroundCooldownMs", 1500, 0, 60000)
    GameAllowZeroCpuAsCandidate := ReadBool("GameForegroundAssist", "GameAllowZeroCpuAsCandidate", true)
    GameRequireSteamForeground := ReadBool("GameForegroundAssist", "GameRequireSteamForeground", true)
    GameAssistLogEvenWhenSkipped := ReadBool("GameForegroundAssist", "GameAssistLogEvenWhenSkipped", true)

    EnableAudioAssist := ReadBool("GameForegroundAssist", "EnableAudioAssist", true)
    ScoreAudioActive := ReadInt("GameForegroundAssist", "ScoreAudioActive", 30, 0, 200)

    ScoreFullscreen := ReadInt("GameForegroundAssist", "ScoreFullscreen", 70, 0, 200)
    ScoreBorderlessLarge := ReadInt("GameForegroundAssist", "ScoreBorderlessLarge", 45, 0, 200)
    ScoreTitleBonus := ReadInt("GameForegroundAssist", "ScoreTitleBonus", 10, 0, 100)
    ScoreCpuAboveThreshold := ReadInt("GameForegroundAssist", "ScoreCpuAboveThreshold", 20, 0, 200)
    ScoreCpuNonZeroBonus := ReadInt("GameForegroundAssist", "ScoreCpuNonZeroBonus", 15, 0, 200)
    GameMinScoreToActivate := ReadInt("GameForegroundAssist", "GameMinScoreToActivate", 55, 0, 300)

    GameLogMode := NormalizeGameLogMode(IniReadS("Logging", "GameLogMode", "OFF"))
    EnableGameScoreLogging := GameLogMode != "OFF"
    GameLogRejectNearCandidates := ReadBool("Logging", "GameLogRejectNearCandidates", true)
    GameLogRejectMinAreaPercent := ReadNumber("Logging", "GameLogRejectMinAreaPercent", 0.85, 0.10, 1.00)
    LogRotateMaxKB := ReadInt("Logging", "LogRotateMaxKB", 256, 32, 8192)
    LogRotateBackups := ReadInt("Logging", "LogRotateBackups", 2, 0, 10)

    MouseParkRightOffsetPx := ReadInt("MousePark", "MouseParkRightOffsetPx", 50, 0, 5000)
    MouseParkYPercent := ReadNumber("MousePark", "MouseParkYPercent", 0.50, 0.0, 1.0)
    MouseParkEdge := StrLower(IniReadS("MousePark", "MouseParkEdge", "Right"))
    if (MouseParkEdge != "left" && MouseParkEdge != "right")
        MouseParkEdge := "right"

    ; Launcher cleanup (optional)
    EnableLauncherCleanup := ReadBool("LauncherCleanup", "Enable", true)
    LauncherCleanupSteamForegroundSec := ReadInt("LauncherCleanup", "SteamForegroundSec", 30, 1, 600)
    LauncherCleanupRequireNoGame := ReadBool("LauncherCleanup", "RequireNoGame", true)
    LauncherCleanupCooldownSec := ReadInt("LauncherCleanup", "CooldownSec", 300, 0, 86400)
    LauncherCleanupCheckIntervalMs := ReadInt("LauncherCleanup", "CheckIntervalMs", 2000, 200, 60000)
    LauncherCleanupGracefulCloseMs := ReadInt("LauncherCleanup", "GracefulCloseMs", 4000, 0, 60000)
    LauncherCleanupHardKill := ReadBool("LauncherCleanup", "HardKill", true)

LauncherCleanupUseCpuAudio := ReadBool("LauncherCleanup", "UseCpuAudio", true)
LauncherCleanupCpuThreshold := ReadInt("LauncherCleanup", "CpuThreshold", 12, 0, 500)

LauncherCleanupAudioPeakThreshold := ReadNumber("LauncherCleanup", "AudioPeakThreshold", 0.02, 0.0, 1.0)
    LauncherCleanupDownloadGuard := ReadBool("LauncherCleanup", "DownloadGuard", true)
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
    ControllerBackend := StrLower(ReadText("Controller", "Backend", "auto"))
    if (ControllerBackend != "xinput" && ControllerBackend != "rawinput"
        && ControllerBackend != "auto") {
        LogLine("Unknown controller backend '" ControllerBackend
            . "'; using auto.", "Warning")
        ControllerBackend := "auto"
    }
    ; ControllerPollIntervalMs, ControllerScrollIntervalMs and
    ; ControllerMouseFastMultiplier are read by LoadSharedSettings now, on these
    ; exact bounds -- the companion's were narrower and were widened to match.
    TaskForceCloseHoldMs := ReadInt("QuickMenu", "TaskForceCloseHoldMs", 1200, 600, 3000)
    QuickMenuMainOrderRaw := IniReadS(
        "QuickMenu", "MainOrder",
        "Audio|Display|RTSS|SteamMenu|SteamQuickAccess|Tasks|GameBar|Keyboard|MouseMode|Settings|System")
    QuickMenuHiddenItemsRaw := IniReadS("QuickMenu", "HiddenItems", "")
    ; Resolved through QuickMenuApplyAccent so an unknown preset or malformed hex
    ; falls back to the default instead of reaching the painter.
    QuickMenuApplyAccent(
        IniReadS("QuickMenu", "AccentColor", "Purple"),
        IniReadS("QuickMenu", "AccentColorCustom", "107C10"))
    QuickMenuMainOrder := ParseQuickMenuMainOrder(QuickMenuMainOrderRaw)
    QuickMenuHiddenItems := Map()
    for _, itemName in StrSplit(QuickMenuHiddenItemsRaw, "|") {
        itemName := StrLower(Trim(itemName))
        if (itemName != "")
            QuickMenuHiddenItems[itemName] := true
    }

    RtssPath := IniReadS("RTSS","Path","C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe")
    if !RtssUseDllIntegration
        ShutdownRtssHooksApi()
    RtssOverlayControlMode := StrLower(IniReadS("RTSS","OverlayControlMode","Separate"))
    if (RtssOverlayControlMode != "toggle" && RtssOverlayControlMode != "separate")
        RtssOverlayControlMode := "separate"
    RtssOverlayToggleShortcut := IniReadS("RTSS","OverlayToggleShortcut","^+o")
    RtssOverlayOnShortcut := IniReadS("RTSS","OverlayOnShortcut","^+1")
    RtssOverlayOffShortcut := IniReadS("RTSS","OverlayOffShortcut","^+2")
    RtssFrameLimiterControlMode := StrLower(IniReadS("RTSS","FrameLimiterControlMode","Separate"))
    if (RtssFrameLimiterControlMode != "toggle" && RtssFrameLimiterControlMode != "separate")
        RtssFrameLimiterControlMode := "separate"
    ; Reloading settings re-arms the frame cap.
    ;
    ; RtssFrameCapWriteBlocked latches on the first failed write so the row
    ; stops accepting presses it cannot honour. That is right during a session
    ; and wrong across a settings change: turning the elevated write back on, or
    ; correcting [RTSS] Path, would otherwise leave the row read-only until the
    ; next sign-in with no way to tell why. The latch costs one failed write to
    ; re-establish, so clearing it here is cheap and reloading settings is
    ; exactly the moment the answer may have changed.
    RtssFrameCapWriteBlocked := false
    RtssLastFrameCapMode := StrLower(Trim(IniReadS("RTSS","LastFrameCapMode","")))
    if !RtssFrameCapModeIsKnown(RtssLastFrameCapMode)
        RtssLastFrameCapMode := ""
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
    global SettingsGui, DesktopMode, SafeMode, EnableDesktopBlackout
    global EnableControllerDiagnostics, ControllerDiagnosticIntervalMs

    StopTaskbarGuard()
    StopDesktopBlackout()
    SetTimer(MonitorShell, 0)
    SetTimer(WindowEngineTick, 0)
    SetTimer(MouseWatch, 0)
    SetTimer(PollController, 0)
    SetTimer(ControllerDiagnosticTick, 0)
    SetTimer(CheckLauncherCleanup, 0)

    ResetWindowEngineState(false)
    SetElevatedGeometryRuntimeEnabled(!DesktopMode && !SafeMode)

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

    ; Armed outside the DesktopMode guard, and outside the controller-mouse
    ; condition above. A diagnostic the user has just switched on has to sample
    ; whatever state the program is actually in -- including desktop mode, where
    ; "my pad does nothing" is a question that gets asked.
    if EnableControllerDiagnostics {
        SetTimer(ControllerDiagnosticTick, ControllerDiagnosticIntervalMs)
        LogLine("Controller diagnostic logging is enabled (all XInput slots).")
    }

    ; Outside every guard above, and on its own timer rather than inside the
    ; window engine's.
    ;
    ; The history exists to be READ from the Settings window, and Settings is
    ; reachable in desktop mode and in Safe Mode -- both of which stop
    ; WindowEngineTick, where this tree's other foreground observer lives. A tick
    ; that stopped with the window engine would leave the picker empty in exactly
    ; the modes where somebody is working out which application to add to a list.
    SetTimer(RecentAppsTick, RecentAppsIntervalMs())
}

ReloadSettings() {
    global QuickMenuVisible, EnableAutoHideCursor, MouseHidden, SafeMode
    LoadSettings()
    if SafeMode
        ApplySafeModeOverrides()
    SyncElevatedInputHelperWithSettings()
    ApplyRuntimeTimers()
    if (!EnableAutoHideCursor && MouseHidden) {
        SystemCursor("Show")
        MouseHidden := false
    }
    SyncControlPanel()
    RefreshAlwaysFocusManagerLists()
    BuildProductTrayMenu()
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

TrayOpenSettings(*) {
    ShowSettingsEditor()
}

TrayExitToDesktop(*) {
    ExitToDesktop(false)
}

TrayReturnToShell(*) {
    LaunchSteamAndReturnToShell()
}

TrayToggleDesktopAutoMouse(*) {
    global EnableAutoMouseMode, EnableDesktopAutoMouseMode
    nextValue := !(EnableAutoMouseMode && EnableDesktopAutoMouseMode)
    changes := [Map(
        "section", "Features", "key", "EnableDesktopAutoMouseMode",
        "value", nextValue ? "true" : "false")]
    ; A checked tray item must mean active. If the master automatic-mouse switch
    ; was off, explicitly enabling desktop-wide mode turns that prerequisite on.
    if (nextValue && !EnableAutoMouseMode)
        changes.Push(Map(
            "section", "Features", "key", "EnableAutoMouseMode", "value", "true"))
    if !CommitIniChanges(changes) {
        ShowNotification("Desktop automatic mouse setting could not be saved", "Warning")
        return
    }
    if nextValue
        EnableAutoMouseMode := true
    EnableDesktopAutoMouseMode := nextValue
    BuildProductTrayMenu()
    ShowNotification(
        "Automatic mouse throughout the Windows desktop "
            . (nextValue ? "enabled" : "disabled"),
        "Success")
}

TrayExitSteamShell(*) {
    ExitSteamShell()
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

; Seam for SteamShell-Shared.ahk. The entries this product offers, in order;
; anything that is not a Map is a separator.
ProductTrayItems() {
    global DesktopMode, EnableAutoMouseMode, EnableDesktopAutoMouseMode
    global SteamShellDataDir, SteamShellInstallationMode
    items := []
    ; Offered, never forced. A record that disagrees with reality must not reach
    ; SetupAssistantRequired(), which decides whether the shell starts at all --
    ; a stale path in a settings file leaving a machine with nothing to log in to
    ; would be far worse than the wrong path it was reporting.
    if (InstallationRecordAlert(
        A_ScriptDir, SteamShellDataDir, SteamShellInstallationMode) != "") {
        items.Push(Map(
            "label", "Installation moved — open Setup Assistant",
            "handler", ShowSetupAssistant))
        items.Push("")
    }
    items.Push(Map("label", "Open Quick Menu", "handler", TrayOpenQuickMenu))
    items.Push(Map("label", "Open Settings", "handler", TrayOpenSettings))
    items.Push(Map("label", "Open Diagnostics", "handler", ShowControlPanel))
    ; Reachable from the tray rather than only from Settings, because the user
    ; who needs it is the one whose controller does not work yet -- so it cannot
    ; require a controller to get to.
    items.Push(Map("label", "Learn Controller…", "handler", ShowControllerLearner))
    ; Its undo, by the same argument and more so. A profile learned wrongly does
    ; not merely fail to help -- it reads as a stick held over, so the pointer
    ; runs off and Settings becomes hard to reach with the very device the
    ; profile broke. The tray is reachable with a keyboard alone.
    items.Push(Map("label", "Delete Learned Profile",
        "handler", DeleteControllerProfileForActiveDevice))
    items.Push("")
    if (DesktopMode) {
        items.Push(Map(
            "label", "Automatic Mouse Throughout Desktop",
            "handler", TrayToggleDesktopAutoMouse,
            "checked", EnableAutoMouseMode && EnableDesktopAutoMouseMode))
        items.Push("")
        items.Push(Map("label", "Return to SteamShell", "handler", TrayReturnToShell))
    } else {
        items.Push(Map("label", "Exit Steam to Desktop", "handler", TrayExitToDesktop))
    }
    items.Push("")
    items.Push(Map("label", "Reload Settings", "handler", (*) => ReloadSettings()))
    items.Push(Map("label", "Exit SteamShell", "handler", TrayExitSteamShell))
    return items
}

ProductTrayBaseTip() {
    global DesktopMode, SteamShellDataDir, SteamShellInstallationMode
    return (DesktopMode ? "SteamShell — desktop mode" : "SteamShell")
        . (InstallationRecordAlert(
            A_ScriptDir, SteamShellDataDir, SteamShellInstallationMode) != ""
            ? " — installation moved" : "")
}

; SPLASH
; ==============================================================================

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
    global SplashForceSDR, SplashMpvHwnd

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
    SplitPath(mpv, , &mpvDirectory)
    if !LaunchInteractiveApp(
        mpv, args, mpvDirectory, "Normal", &SplashMpvPid, "MPV splash") {
        SplashFailReason := "Failed to run mpv.exe as the standard user."
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
    global ControllerMapGui, AlwaysFocusGui, ControlGui, LiveLogGui
    global SetupAssistantGui, AutoLogonGui, SetupCompletionGui
    global HealthCheckGui, QuickMenuLayoutGui
    if QuickMenuVisible
        return true
    for _, guiRef in [
        IsSet(SettingsGui) ? SettingsGui : 0,
        IsSet(StartupRecoveryGui) ? StartupRecoveryGui : 0,
        IsSet(ControllerTestGui) ? ControllerTestGui : 0,
        IsSet(ControllerMapGui) ? ControllerMapGui : 0,
        IsSet(AlwaysFocusGui) ? AlwaysFocusGui : 0,
        IsSet(ControlGui) ? ControlGui : 0,
        IsSet(LiveLogGui) ? LiveLogGui : 0,
        IsSet(SetupAssistantGui) ? SetupAssistantGui : 0,
        IsSet(AutoLogonGui) ? AutoLogonGui : 0,
        IsSet(SetupCompletionGui) ? SetupCompletionGui : 0,
        IsSet(HealthCheckGui) ? HealthCheckGui : 0,
        IsSet(QuickMenuLayoutGui) ? QuickMenuLayoutGui : 0] {
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

; Seams for the shared MouseWatch. The two products suppress cursor hiding for
; different reasons and -- this is the part that matters -- at different points,
; so they are two questions rather than one.
;
; This tree stops the whole pass while Explorer is allowed: with the desktop
; shell up, the cursor is Explorer's to manage, and even the position tracking
; should not run. The companion instead lets movement keep re-showing the cursor
; and only declines to hide it. Collapsing these into one gate would change
; behaviour in one product or the other, which is a hardware-testable change and
; not what sharing the body is for.
MouseWatchDisabled() {
    global AllowExplorer, EnableAutoHideCursor
    return AllowExplorer || !EnableAutoHideCursor
}

; The Settings window holds the cursor visible, because it is driven by one.
;
; This returned false, on the stated grounds that this tree holds the cursor
; visible for nothing. That was not true: the full Settings editor is pointer
; driven -- SettingsEditorHandlePointer moves the pointer with the right stick,
; and the window has Browse buttons and text fields that need a mouse. Sitting
; still in it for MouseHideDelay took the cursor away mid-edit.
;
; With a controller connected it was worse than losing the cursor. The poll's
; Settings branch shows it again on the very next tick, and the mouse has still
; not moved, so the hide condition is still true when the watch next runs: the
; two fought each other and the cursor blinked for as long as the user sat still.
;
; Visible rather than active, deliberately: the Quick Menu opens over Settings
; and takes the foreground with it, and the window underneath is still the reason
; a pointer is wanted.
MouseWatchHoldsCursorVisible() {
    global SettingsGui
    if !IsSet(SettingsGui)
        return false
    try return IsGuiVisible(SettingsGui) ? true : false
    return false
}

; The controller test and calibration window is in SteamShell-Shared.ahk now,
; defined once for both products.

OpenWindowsSettings() {
    pid := 0
    LaunchInteractiveApp(
        "ms-settings:", "", "", "Normal", &pid, "Windows Settings")
}

OpenOSK() {
    ; Always open the classic On-Screen Keyboard.
    pid := 0
    LaunchInteractiveApp(
        A_WinDir "\System32\osk.exe", "", A_WinDir "\System32",
        "Normal", &pid, "On-Screen Keyboard")
}

; ==============================================================================
; CONTROLLER MAPPING (configurable short/long press)
; ==============================================================================

LoadControllerMappings() {
    global ControllerMap
    LoadControllerMappingsFromIni()
    ; Standalone only, and one-time. Older settings files bound Start to the Quick
    ; Menu and Control Panel; schema 4 moved them to the Windows Start menu and
    ; File Explorer. Rewritten in place so the change survives, and only when BOTH
    ; still hold the old pair -- a user who has since rebound either one is left
    ; alone. The companion never shipped the old defaults and must not do this.
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

; The builtins that must run at SteamShell's own integrity: three that start a
; process and two that raise a SteamShell window. The elevated helper implements
; every other builtin as a fixed keystroke and deliberately declines these, so
; the two sets partition the builtin list with no overlap and no gap.

; Runs while a High/System-integrity window owns the foreground and the helper is
; handling everything else. Keeps its own press/hold state because the caller
; clears the shared trackers on this path, and fires nothing but the bindings
; above, so a button cannot be serviced by both processes.

; Per-tree seam required by SteamShell-Shared.ahk: what this product can add to
; a controller diagnostic tick.
;
; Nothing, and that is the honest answer rather than a gap. The companion's
; version of this reports GameInput alongside XInput and names a second active
; backend; GameInput reads all zeros outside Xbox FSE, so this product cannot
; offer it, and there is no second backend here to name. Returning empty strings
; leaves the log line exactly as short as the information behind it.
ProductControllerDiagnosticProbe() {
    return Map("suffix", "", "detail", "", "signature", "")
}

; Per-tree seam required by SteamShell-Shared.ahk: the builtin actions only
; this product has.
;
; Explorer goes through LaunchInteractiveApp for the same reason
; OpenTouchKeyboard does. This program can end up elevated -- Setup takeover,
; or the user's own choice -- and a child launched from an elevated shell
; INHERITS that token. An elevated File Explorer is a privilege escalation the
; user never asked for and cannot see, so the launch is de-elevated rather than
; convenient. The companion runs at normal integrity and has nothing to drop.
ProductControllerBindingAction(action) {
    switch action {
        case "Explorer":
            pid := 0
            LaunchInteractiveApp(
                A_WinDir "\explorer.exe", "", A_WinDir,
                "Normal", &pid, "File Explorer")
        case "ControlPanel":
            ShowControlPanel()
    }
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
    RecordShortcutCancel()
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

; ==============================================================================
; CONTROLLER-FIRST QUICK MENU
; ==============================================================================
; Seam for the shared ToggleQuickMenu: why this product will not open the menu
; right now, or "" if it will. Standalone has two reasons; the companion has
; none, which is what made the two copies look like different routines.
ProductQuickMenuBlockedReason() {
    global EnableQuickMenu, DesktopRestorePending
    if DesktopRestorePending
        return "Quick Menu is unavailable while the desktop is being restored"
    if !EnableQuickMenu
        return "Quick Menu is disabled in SteamShellSettings.ini"
    return ""
}

ShowQuickMenu(*) {
    global QuickMenuVisible, QuickMenuPreviousHwnd, QuickMenuPage, QuickMenuSelected
    global QuickMenuGui, ScriptPid, DesktopRestorePending

    if (QuickMenuVisible || DesktopRestorePending)
        return

    QuickMenuPreviousHwnd := 0
    try {
        hwnd := WinGetID("A")
        pid := WinGetPID("ahk_id " hwnd)
        if (pid != ScriptPid)
            QuickMenuPreviousHwnd := hwnd
    }

    ; Visible before the page, not after: QuickMenuGoToPage builds, and
    ; QuickMenuBuildGui returns immediately while this flag is false.
    QuickMenuVisible := true
    QuickMenuGoToPage("MAIN")
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
    global ControllerNeedsFreshBaseline
    wasVisible := QuickMenuVisible
    QuickMenuVisible := false
    ; Cancel a pending foreground retry before hiding. ShowWindow(SW_HIDE) is the
    ; parent-window-level backstop: child Static controls cannot remain painted as
    ; separate title/rows/footer islands when Steam's fullscreen surface vanishes.
    SetTimer(QuickMenuEnsureForeground, 0)
    if IsSet(QuickMenuGui) {
        try DllCall("User32\ShowWindow", "Ptr", QuickMenuGui.Hwnd, "Int", 0)
        try QuickMenuGui.Hide()
    }

    ; A hidden persistent HWND can leave its last child surfaces in DWM across a
    ; fullscreen game transition. Tear down every closed menu session; page changes
    ; while the menu is open still use the atomic repaint path.
    QuickMenuDestroyWindow()
    if wasVisible
        ControllerNeedsFreshBaseline := true

    if (wasVisible && restorePrevious && QuickMenuPreviousHwnd
        && DllCall("IsWindow", "Ptr", QuickMenuPreviousHwnd)) {
        if ActivateWindowRobust(QuickMenuPreviousHwnd) {
            HandleCursorAfterManagedFocus(QuickMenuPreviousHwnd, false)
        }
    }
}

; Surface-changing operations also wait for DWM to retire the destroyed HWND
; before Steam or Explorer supplies the next fullscreen frame.
DestroyQuickMenuForSurfaceTransition() {
    HideQuickMenu(false)
    ; Complete removal from the current composition frame before Steam's window
    ; disappears and Explorer supplies the next one.
    try DllCall("dwmapi\DwmFlush")
}

MigrateQuickMenuOrderForSchema15(raw) {
    ; Parse supplies any missing supported rows. Pull the two new rows back out,
    ; then insert them together directly after Game Bar while retaining every
    ; other user-selected position.
    parsed := ParseQuickMenuMainOrder(raw)
    migrated := []
    inserted := false
    for _, itemName in parsed {
        if (itemName = "keyboard" || itemName = "mousemode")
            continue
        migrated.Push(itemName)
        if (itemName = "gamebar") {
            migrated.Push("keyboard")
            migrated.Push("mousemode")
            inserted := true
        }
    }
    if !inserted {
        migrated.Push("keyboard")
        migrated.Push("mousemode")
    }
    return JoinWith(migrated, "|")
}

QuickMenuGetDefinitions() {
    global EnableGameDetectionMenu, LastGameCandidates
    global QuickMenuPage, QuickMenuDisplayModes
    global QuickMenuTaskPage, QuickMenuTaskWindows, PinnedForegroundHwnd
    global EnableRTSSIntegration, RtssPath
    global RtssOverlayControlMode, RtssFrameLimiterControlMode
    global QuickMenuMainOrder, QuickMenuHiddenItems, DesktopMode
    rows := []

    if (QuickMenuPage = "AUDIO") {
        rows.Push(Map("id", "back", "label", "Back", "back", true))
        rows.Push(Map("id", "audioOutput", "label", "Output"))
        rows.Push(Map("id", "volume", "label", "Volume"))
        rows.Push(Map("id", "mute", "label", "Mute"))
        return rows
    }

    if (QuickMenuPage = "SYSTEM") {
        rows.Push(Map("id", "back", "label", "Back To Quick Settings", "back", true))
        if (DesktopMode)
            rows.Push(Map("id", "returnShell", "label", "Return To SteamShell"))
        else
            rows.Push(Map("id", "desktop", "label", "Exit Steam To Desktop"))
        if EnableGameDetectionMenu
            rows.Push(Map("id", "gameDetection", "label", "Game Detection"))
        ; Beside Game Detection, not folded into it. That page is a read-only
        ; explanation of what the scorer decided; this one WRITES settings, and a
        ; user should not have to enter a diagnostic to configure something.
        rows.Push(Map("id", "currentApp", "label", "Current Application"))
        rows.Push(Map("id", "exitApp", "label", "Exit SteamShell"))
        rows.Push(Map("id", "sleep", "label", "Sleep"))
        rows.Push(Map("id", "restart", "label", "Restart PC"))
        rows.Push(Map("id", "shutdown", "label", "Shut Down"))
        return rows
    }

    ; Read-only. Every number here was already computed in order to choose a
    ; game; this page only shows the losers alongside the winner, which is the
    ; difference between "it picked the wrong window" and a report somebody can
    ; act on without asking for a log.
    ;
    ; Ids carry a colon, like the LAYOUT page's rows, because the list is built
    ; from whatever the last pass found rather than from a fixed set.
    if (QuickMenuPage = "GAMESCORE") {
        rows.Push(Map("id", "gameScoreBack", "label", "Back To System"))
        if (LastGameCandidates.Length = 0) {
            rows.Push(Map("id", "gameScoreEmpty", "label", "No candidates scored yet"))
            return rows
        }
        for _, rowId in QuickMenuGameScoreIds()
            rows.Push(Map("id", rowId, "label", QuickMenuGameScoreLabel(rowId)))
        return rows
    }

    ; The destinations are decided in SteamShell-Shared.ahk; only the row shape
    ; is this tree's. Same split as GAMESCORE above.
    if (QuickMenuPage = "CURRENTAPP") {
        rows.Push(Map("id", "currentAppBack", "label", "Back To System"))
        reason := QuickMenuCurrentAppBlockedReason()
        if (reason != "") {
            rows.Push(Map("id", "currentAppBlocked", "label", reason))
            return rows
        }
        for _, rowId in QuickMenuAppTargetIds("standalone")
            rows.Push(Map("id", rowId,
                "label", QuickMenuAppTargetLabel(rowId, "standalone")))
        return rows
    }

    if (QuickMenuPage = "SETTINGS") {
        rows.Push(Map("id", "back", "label", "Back To Quick Settings", "back", true))
        rows.Push(Map("id", "settingsGeneral", "label", "General + Startup", "page", "SETTINGS_GENERAL"))
        rows.Push(Map("id", "settingsInput", "label", "Controller + Cursor", "page", "SETTINGS_INPUT"))
        rows.Push(Map("id", "settingsFocus", "label", "Focus + Window Engine", "page", "SETTINGS_FOCUS"))
        rows.Push(Map("id", "settingsRtss", "label", "RTSS + Performance", "page", "SETTINGS_RTSS"))
        rows.Push(Map("id", "windowsSettings", "label", "Windows Settings"))
        rows.Push(Map("id", "settingsEditor", "label", "Open Full Settings Editor"))
        return rows
    }

    if (QuickMenuPage = "SETTINGS_GENERAL") {
        rows.Push(Map("id", "back", "label", "Back To Settings", "back", true))
        rows.Push(Map("id", "qSplash", "label", "Startup Splash"))
        rows.Push(Map("id", "qTaskbar", "label", "Hide Taskbar In Shell"))
        rows.Push(Map("id", "qBlackout", "label", "Black Desktop Background"))
        rows.Push(Map("id", "qAccentColor", "label", "Quick Menu Accent"))
        return rows
    }

    if (QuickMenuPage = "SETTINGS_INPUT") {
        rows.Push(Map("id", "back", "label", "Back To Settings", "back", true))
        rows.Push(Map("id", "qControllerMouse", "label", "Controller Mouse"))
        rows.Push(Map("id", "qMouseSpeed", "label", "Controller Mouse Speed"))
        rows.Push(Map("id", "qAutoHideCursor", "label", "Auto-Hide Cursor"))
        rows.Push(Map("id", "qMouseHideDelay", "label", "Cursor Hide Delay"))
        rows.Push(Map("id", "qParkBoot", "label", "Park Mouse On Boot"))
        rows.Push(Map("id", "qParkFocus", "label", "Park On Focus Change"))
        rows.Push(Map("id", "qParkEdge", "label", "Mouse Parking Edge"))
        return rows
    }

    if (QuickMenuPage = "SETTINGS_FOCUS") {
        rows.Push(Map("id", "back", "label", "Back To Settings", "back", true))
        rows.Push(Map("id", "qSteamRefocus", "label", "Steam Refocus"))
        rows.Push(Map("id", "qGameAssist", "label", "Game Foreground Assist"))
        rows.Push(Map("id", "qAlwaysFocus", "label", "AlwaysFocus Support"))
        rows.Push(Map("id", "qWindowManagement", "label", "Window Management"))
        rows.Push(Map("id", "qFocusPaused", "label", "Focus Assistance Session"))
        return rows
    }

    if (QuickMenuPage = "SETTINGS_RTSS") {
        rows.Push(Map("id", "back", "label", "Back To Settings", "back", true))
        rows.Push(Map("id", "qRtssIntegration", "label", "RTSS Integration"))
        rows.Push(Map("id", "qOverlayMode", "label", "Overlay Controls"))
        rows.Push(Map("id", "qLimiterMode", "label", "Frame Limiter Controls"))
        rows.Push(Map("id", "qFrameCap", "label", "Preset Frame Cap"))
        rows.Push(Map("id", "settingsEditor", "label", "Edit Paths + Shortcuts"))
        return rows
    }

    if (QuickMenuPage = "TASKS") {
        rows.Push(Map("id", "back", "label", "Back To Quick Settings", "back", true))
        if (PinnedForegroundHwnd && DllCall("IsWindow", "Ptr", PinnedForegroundHwnd))
            rows.Push(Map("id", "taskRelease", "label", "Release Focus Lock"))

        QuickMenuTaskSlice(QuickMenuTaskWindows.Length,
            &firstIndex, &lastIndex, &pageCount)
        if (QuickMenuTaskWindows.Length = 0) {
            rows.Push(Map("id", "tasksUnavailable", "label", "No Application Windows Found"))
        } else {
            Loop lastIndex - firstIndex + 1 {
                item := QuickMenuTaskWindows[firstIndex + A_Index - 1]
                rows.Push(Map(
                    "id", "taskWindow:" item["hwnd"],
                    "label", ShortenText(item["title"], 42)
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
        rows.Push(Map("id", "back", "label", "Back", "back", true))
        hdrState := GetPrimaryHdrState()
        if (IsObject(hdrState) && hdrState["supported"] && !hdrState["forceDisabled"])
            rows.Push(Map("id", "hdr", "label", "HDR"))
        else
            rows.Push(Map("id", "hdrUnavailable", "label", "HDR"))
        if (QuickMenuDisplayModes.Length = 0)
            QuickMenuDisplayModes := GetPrimaryDisplayModes()
        if (QuickMenuDisplayModes.Length = 0) {
            rows.Push(Map("id", "displayUnavailable", "label", "No Compatible Modes Reported"))
        } else {
            EnsureDisplaySelection()
            rows.Push(Map("id", "displayResolution", "label", "Resolution"))
            rows.Push(Map("id", "displayRefresh", "label", "Refresh Rate"))
            if IsObject(EnsureDisplayScaleSelection())
                rows.Push(Map("id", "displayScale", "label", "Scale"))
            else
                rows.Push(Map("id", "displayScaleUnavailable", "label", "Scale"))
            rows.Push(Map("id", "displayApply", "label", "Apply"))
        }
        return rows
    }

    if (QuickMenuPage = "RTSS") {
        rows.Push(Map("id", "back", "label", "Back", "back", true))
        rtssRunning := ProcessExist("RTSS.exe") != 0
        if !rtssRunning {
            if !EnableRTSSIntegration
                rows.Push(Map("id", "rtssDisabled", "label", "RTSS Integration"))
            else if ResolveRtssExecutablePath() != ""
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
                rows.Push(Map("id", "rtssSaveProfile", "label", "Save Limit To Profile"))
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
        rows.Push(Map("id", "back", "label", "Back To Quick Settings", "back", true))
        for _, buttonName in ["A","B","X","Y","LB","RB","LT","RT","Start","L3","R3"]
            rows.Push(Map("id", "layout:" buttonName, "label", "Back + " buttonName))
        rows.Push(Map("id", "setControllerMappings", "label", "Set Controller Mappings"))
        return rows
    }

    available := Map(
        "audio", Map("id", "audioMenu", "label", "Audio", "page", "AUDIO"),
        "display", Map("id", "display", "label", "Display & HDR"),
        "rtss", Map("id", "rtssMenu", "label", "RTSS & Performance", "page", "RTSS"),
        "steammenu", Map("id", "steamMenu", "label",
            IsSteamRunning() ? "Steam Menu" : "Launch Steam"),
        "steamquickaccess", Map("id", "steamQuickAccess", "label", "Steam Quick Access"),
        "tasks", Map("id", "tasks", "label", "Task Switcher"),
        "gamebar", Map("id", "gameBar", "label", "Game Bar"),
        "keyboard", Map("id", "openKeyboard", "label", "Open Keyboard"),
        "mousemode", Map("id", "qPersistentMouse", "label", "Mouse Mode"),
        "settings", Map("id", "settings", "label", "Settings", "page", "SETTINGS"),
        "system", Map("id", "system", "label", "System", "page", "SYSTEM"))
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

; ---------------------------------------------------------------------------
; Quick Menu accent resolution.
;
; This block is character-for-character identical in SteamShell-XFE apart from
; indentation and the two settings reads, which use each tree's own INI helper.
; Keeping it that way is deliberate: the accent is one design applied to both,
; so a fix to the blend or the fallback should be a copy, not a re-derivation.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; Quick Menu row painter (GDI+).
;
; The rows used to be 28 Static controls whose only styling lever was a flat
; background colour, which is why they could never have rounded corners, an
; outline or a glow -- a Win32 static has no way to draw one. They are now a
; single bitmap painted with GDI+ and shown in one control.
;
; Deliberately NOT a layered window. The Quick Menu's whole job is appearing
; over a running game, that works today, and per-pixel alpha over fullscreen
; D3D is exactly where overlays historically fail. Painting into an opaque
; bitmap keeps the existing window composition untouched.
;
; The bitmap is built at the control's PHYSICAL pixel size rather than at
; AutoHotkey's logical size, so nothing is stretched on a high-DPI handheld.
; Because the surface is opaque, text can still use ClearType.
;
; This block is character-for-character identical in SteamShell-XFE apart from
; indentation.
; ---------------------------------------------------------------------------

; The one line of the painter that differs between the two trees, isolated so
; the rest can stay identical: standalone resolves a row's value live, while XFE
; rebuilds its whole row list per repaint and already carries it.
QuickMenuBuildGui() {
    global QuickMenuGui, QuickMenuRows, QuickMenuPage, QuickMenuVisible
    global QuickMenuTitleCtrl, QuickMenuStatusCtrl
    global QuickMenuRowsCtrl
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
        ; Match XFE's final presentation during an open session: one borderless
        ; window and one reusable control surface. The window is destroyed on close
        ; so DWM cannot resurrect it after a fullscreen transition.
        QuickMenuGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "SteamShell Quick Menu")
        QuickMenuGui.BackColor := QM_BG
        QuickMenuGui.MarginX := rowInset
        QuickMenuGui.MarginY := 16
        QuickMenuGui.SetFont("s17 c" QM_LABEL_SELECTED " Bold", "Segoe UI")
        QuickMenuTitleCtrl := QuickMenuGui.AddText(
            "x" (rowInset + 12) " y20 w" (rowWidth - 12) " h30", "")
        ; One painted surface replaces the 28 Static controls the rows used to be.
        ; 0x0E is SS_BITMAP, 0x40 is SS_REALSIZECONTROL so the static keeps the
        ; size we gave it instead of resizing itself to the bitmap, and 0x100 is
        ; SS_NOTIFY so it still reports clicks.
        QuickMenuRowsCtrl := QuickMenuGui.AddText(
            "x0 y" (QuickMenuRowTop() - QuickMenuGlowPadding())
            . " w" menuW " h" ((14 * QuickMenuRowHeight()) + (2 * QuickMenuGlowPadding())), "")
        QuickMenuRowsCtrl.Opt("+0x14E")
        QuickMenuRowsCtrl.OnEvent("Click", QuickMenuRowsClick)
        QuickMenuGui.SetFont("s9 c" QM_VALUE " Norm", "Segoe UI")
        QuickMenuStatusCtrl := QuickMenuGui.AddText(
            "x" (rowInset + 12) " y600 w" (rowWidth - 12) " h36 +Wrap", "")
        QuickMenuGui.OnEvent("Escape", (*) => QuickMenuGoBack())
    }

    ; Do not expose intermediate title, row, resize, or region changes. This is the
    ; standalone equivalent of XFE's repaint-in-place behavior.
    QuickMenuSetRedraw(false)
    try {
        QuickMenuTitleCtrl.Text := GuiLiteralText(QuickMenuTitleText())
        QuickMenuRows := []
        Loop Min(defs.Length, 14) {
            ; The descriptor itself, not a copy of two of its keys. Rows now
            ; carry their own navigation -- "page" and "back" -- and rebuilding
            ; a bare id/label pair here dropped exactly the fields that make a
            ; row able to say what it does without a switch knowing its name.
            QuickMenuRows.Push(defs[A_Index])
        }
        ; The painted band is sized to the rows actually on this page, so a short
        ; page leaves no dead surface for a glow to spill onto.
        QuickMenuRowsCtrl.Move(0, QuickMenuRowTop() - QuickMenuGlowPadding(), menuW
            , (Max(1, QuickMenuRows.Length) * QuickMenuRowHeight())
                + (2 * QuickMenuGlowPadding()))

        QuickMenuStatusCtrl.Move(
            rowInset + 12, QuickMenuStatusY(defs.Length),
            rowWidth - 12, QuickMenuStatusHeight())
        QuickMenuStatusCtrl.Text := GuiLiteralText(QuickMenuHintText())
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

QuickMenuHintText() {
    global QuickMenuPage
    global LastStatusText, LastStatusTick, StatusVisibleMs
    ; A fresh message displaces the hint. The hint is always re-derivable; a
    ; warning that scrolls past unseen is not.
    if (LastStatusText != "" && A_TickCount - LastStatusTick < StatusVisibleMs)
        return LastStatusText
    if (QuickMenuPage = "TASKS")
        return "D-Pad Move  •  A Switch  •  Y Switch + Lock  •  X Close  •  Hold X Force Close  •  B Back"
    if (QuickMenuPage = "DISPLAY")
        return "D-Pad Move  •  Left/Right Change  •  A Select  •  B Back"
    if (QuickMenuPage = "RTSS")
        return "D-Pad Move  •  Left/Right Change  •  A Select  •  B Back"
    if (SubStr(QuickMenuPage, 1, 8) = "SETTINGS")
        return "D-Pad Move  •  A Or Left/Right Toggle  •  B Back"
    if (QuickMenuPage = "MAIN")
        return "D-Pad Move  •  A Select  •  Hold Y for Controller Mappings  •  B Back"
    return "D-Pad Move  •  A Select  •  B Back"
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
    global QuickMenuGui, QuickMenuStatusCtrl, QuickMenuPreviousHwnd
    if (!IsSet(QuickMenuGui) || !IsObject(QuickMenuStatusCtrl))
        return
    ; The monitor of the window that was in front before the menu opened, which
    ; is the per-tree half: this product re-centres onto it unconditionally, so
    ; the menu follows the foreground window across displays.
    GetTargetMonitorWorkArea(
        QuickMenuPreviousHwnd, &workLeft, &workTop, &workRight, &workBottom)
    QuickMenuFitContent(
        QuickMenuGui, QuickMenuStatusCtrl,
        workLeft, workTop, workRight, workBottom, true)
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

GetSafeTargetWindowDpi(targetHwnd := 0, fallbackHwnd := 0) {
    ; Take the highest credible DPI report. Undersizing a scrollable assistant is
    ; harmless; underestimating DPI is what lets its physical height exceed a TV's
    ; work area. GetDpiForWindow is per-monitor aware, while GetDpiForMonitor
    ; covers a hidden GUI that has not completed its first monitor transition.
    dpi := Max(96, A_ScreenDPI)
    for hwnd in [targetHwnd, fallbackHwnd] {
        if !hwnd || !DllCall("User32\IsWindow", "Ptr", hwnd, "Int")
            continue
        try dpi := Max(
            dpi, DllCall("User32\GetDpiForWindow", "Ptr", hwnd, "UInt"))
        monitor := 0
        try monitor := DllCall(
            "User32\MonitorFromWindow", "Ptr", hwnd,
            "UInt", 2, "Ptr") ; MONITOR_DEFAULTTONEAREST
        if monitor {
            monitorDpiX := 0
            monitorDpiY := 0
            try {
                if DllCall(
                    "Shcore\GetDpiForMonitor",
                    "Ptr", monitor,
                    "Int", 0, ; MDT_EFFECTIVE_DPI
                    "UInt*", &monitorDpiX,
                    "UInt*", &monitorDpiY,
                    "Int") = 0
                    dpi := Max(dpi, monitorDpiX, monitorDpiY)
            }
        }
    }
    return Max(96, dpi)
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
    return ShortenText(outputName, 22) "  •  " volumeText
}

FindTaskSwitcherWindow(hwnd) {
    global QuickMenuTaskWindows
    for _, item in QuickMenuTaskWindows {
        if (item["hwnd"] = hwnd)
            return item
    }
    return 0
}

; A ROW VALUE, so this runs on every Quick Menu repaint. It takes the cached
; inventory; the task PAGE, which is the list the user then acts on, does not.
GetPinnedForegroundSummary() {
    global PinnedForegroundHwnd, PinnedForegroundTitle
    if (!PinnedForegroundHwnd) {
        count := SharedTaskSwitcherWindows(1000).Length
        return count ? count " Window" (count = 1 ? "" : "s") : "No Windows"
    }
    if !DllCall("IsWindow", "Ptr", PinnedForegroundHwnd) {
        ReleasePinnedForeground(false)
        count := SharedTaskSwitcherWindows(1000).Length
        return count ? count " Window" (count = 1 ? "" : "s") : "No Windows"
    }
    return "Locked  •  " ShortenText(PinnedForegroundTitle, 18)
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

GetControllerLayoutText(buttonName) {
    shortBinding := ControllerBindingPretty(buttonName ".Short")
    longBinding := ControllerBindingPretty(buttonName ".Long")
    return shortBinding "  /  " longBinding
}

QuickMenuMouseSelect(index, *) {
    global QuickMenuSelected
    QuickMenuSelected := index
    QuickMenuNormalizeSelection()
    QuickMenuRefresh()
    QuickMenuActivateSelected()
}

QuickMenuValue(id) {
    global FocusAssistancePaused, RtssPath, RtssPresetFrameCap, RtssPendingFrameCap
    global EnableRTSSIntegration, RtssOverlayToggleShortcut
    global RtssOverlayOnShortcut, RtssOverlayOffShortcut
    global RtssCustomFrameCapShortcut, RtssFrameLimiterOnShortcut, RtssFrameLimiterOffShortcut
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    global DisplaySelectedScalePercent
    global QuickMenuTaskPage, QuickMenuTaskWindows
    global LastGameCandidates, LastBestCandidateProc, LastBestCandidateScore
    global QuickMenuConfirmAction, QuickMenuConfirmUntilTick
    global EnableSplashScreen, EnableTaskbarHiding, EnableDesktopBlackout
    global EnableControllerMouseMode, EnablePersistentMouseMode, ControllerMouseSpeed, EnableAutoHideCursor, MouseHideDelay
    global EnableMouseParkOnBoot, EnableMouseParkOnFocusChange, MouseParkEdge
    global EnableSteamRefocusMode, EnableGameForegroundAssist, EnableAlwaysFocus, EnableWindowManagement
    global RtssOverlayControlMode, RtssFrameLimiterControlMode
    global SteamMenuShortcut, SteamQuickAccessShortcut, SteamOverlayShortcut
    global QuickMenuAccentName, QM_ACCENT

    if (QuickMenuConfirmAction = id && A_TickCount < QuickMenuConfirmUntilTick)
        return "SELECT AGAIN TO CONFIRM"

    ; The settings rows both products build -- plain on/off from the table, plus
    ; the numbers and named states beside them. Shell-only rows fall through.
    sharedValue := QuickMenuSettingValueText(id)
    if (sharedValue != "")
        return sharedValue

    if (SubStr(id, 1, 7) = "layout:")
        return GetControllerLayoutText(SubStr(id, 8))
    if (SubStr(id, 1, 10) = "gamescore:")
        return QuickMenuGameScoreValue(id)
    if (SubStr(id, 1, 11) = "currentapp:")
        return "Add"
    if (id = "currentApp")
        return QuickMenuCurrentAppValue()
    if (id = "currentAppBack")
        return "‹"
    ; Back To System. Not a "back" row -- QuickMenuGoBack would leave GAMESCORE
    ; for MAIN rather than for the page it came from -- so it keeps its own case
    ; and states the glyph here, which is what every other back row displays.
    if (id = "gameScoreBack")
        return "‹"
    if (SubStr(id, 1, 11) = "taskWindow:") {
        item := FindTaskSwitcherWindow(ToInt(SubStr(id, 12), 0))
        return IsObject(item) ? ShortenText(item["exe"], 20) : "CLOSED"
    }

    switch id {
        case "audioMenu":
            return GetAudioMenuSummary()
        case "audioOutput":
            try {
                return ShortenText(SoundGetName(), 34)
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
        case "gameDetection":
            return QuickMenuGameDetectionValue()
        ; Both rows say everything they have to say in the label -- "nothing
        ; scored yet", or why the current application cannot be added -- so the
        ; value column is deliberately empty. The companion says the same thing
        ; by passing "" as the row's value; this is that, on this side.
        case "gameScoreEmpty", "currentAppBlocked":
            return ""
        case "hdrUnavailable":
            hdrState := GetPrimaryHdrState()
            if !IsObject(hdrState)
                return "Unavailable"
            if !hdrState["supported"]
                return "Not Supported"
            return hdrState["forceDisabled"] ? "Disabled By Windows" : "Unavailable"
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
                return "Steam Is Not Running"
            return SendToPretty(SteamQuickAccessShortcut)
        case "returnShell":
            return "Hide The Desktop And Resume Steam"
        case "exitApp":
            return "Close SteamShell"
        case "gameBar":
            return "Win + G"
        case "openKeyboard":
            return "Open Touch Keyboard"
        case "windowsSettings":
            return "Open Windows Settings"
        case "taskRelease":
            return "UNLOCK"
        case "rtssMenu":
            return GetRtssMenuStatus()
        case "rtssDisabled":
            return "Disabled"
        case "rtssStart":
            return "Launch Configured Executable"
        case "rtssMissing":
            return "Executable Not Found"
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
        case "qWindowManagement":
            return EnableWindowManagement ? "ON  •  COORDINATED" : "OFF  •  COORDINATED"
        case "qFocusPaused":
            return FocusAssistancePaused ? "PAUSED" : "ACTIVE"
        case "settings":
            return "Features & Configuration"
        case "system":
            return "Power & Diagnostics"
        case "settingsGeneral", "settingsInput", "settingsFocus", "settingsRtss", "settingsEditor", "setControllerMappings":
            return "›"
        default:
            return ""
    }
}

QuickMenuRefresh() {
    global QuickMenuRows, QuickMenuSelected, QuickMenuConfirmAction, QuickMenuConfirmUntilTick
    global QM_BG, QM_ROW_SELECTED, QM_ACCENT, QM_LABEL, QM_LABEL_SELECTED, QM_VALUE
    global QuickMenuStatusCtrl, QuickMenuRedrawSuspended
    resumeRedraw := !QuickMenuRedrawSuspended
    if resumeRedraw
        QuickMenuSetRedraw(false)
    try {
        ; Normalized before the empty-page return, not after it, so the index is
        ; never left out of range for the next reader.
        QuickMenuNormalizeSelection()
        if (QuickMenuRows.Length = 0)
            return

        if (QuickMenuConfirmAction != "" && A_TickCount >= QuickMenuConfirmUntilTick)
            QuickMenuConfirmAction := ""

        try QuickMenuStatusCtrl.Text := GuiLiteralText(QuickMenuHintText())

        ; Every row is one bitmap, so selection, value text and colour all change in a
        ; single repaint rather than by touching 28 controls individually.
        QuickMenuPaintRows()
    } finally {
        if resumeRedraw
            QuickMenuSetRedraw(true)
    }
}

QuickMenuCloseSelected() {
    global QuickMenuPage
    if (QuickMenuPage = "TASKS") {
        hwnd := GetSelectedTaskSwitcherHwnd()
        if hwnd
            RequestCloseTaskSwitcherWindow(hwnd)
    }
}

QuickMenuHandleController(pressed, released := 0, lx := 0, ly := 0, buttons := 0) {
    global QuickMenuSelected, QuickMenuPage, TaskForceCloseHoldMs, ControllerChordHoldMs
    global QuickMenuRows
    static stickDir := ""
    static lastStickTick := 0
    static holdDir := 0
    static holdSince := 0
    static lastRepeatTick := 0
    static taskXDownTick := 0
    static taskXHwnd := 0
    static taskXLongFired := false
    static mainYDownTick := 0
    static mainYLongFired := false

    ; Controller mappings moved off the main row list. Holding Y opens the
    ; styled Quick Settings reference page without making a tap do anything.
    if (QuickMenuPage != "MAIN") {
        mainYDownTick := 0
        mainYLongFired := false
    } else if (buttons & 0x8000) {
        if !mainYDownTick
            mainYDownTick := A_TickCount
        if (!mainYLongFired
            && A_TickCount - mainYDownTick >= ControllerChordHoldMs) {
            mainYLongFired := true
            QuickMenuGoToPage("LAYOUT")
        }
        return
    } else {
        mainYDownTick := 0
        mainYLongFired := false
    }

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
        QuickMenuMoveSelection(-1)
        return
    }
    if (pressed & 0x0002) { ; D-pad down
        QuickMenuMoveSelection(1)
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
        ; QuickMenuGoBack already hides on MAIN -- that test is its first three
        ; lines. Guarding the call with the same test restated the decision in a
        ; second place; the two agreed, so this is a de-duplication rather than a
        ; fix, and it leaves one copy to keep correct instead of two. The
        ; companion has always called it bare.
        QuickMenuGoBack()
        return
    }
}

; Per-tree seam required by SteamShell-Shared.ahk: persist one Quick Menu
; setting AND make it live. The shell stages a copy and swaps the INI in only
; once every write succeeded; the companion writes directly. Both are correct
; for their program, and the shared settings rows must not care which.
ProductApplyQuickMenuSetting(section, key, value) {
    return PersistQuickMenuSetting(section, key, value)
}

PersistQuickMenuSetting(section, key, value) {
    global EnableAutoHideCursor, MouseHidden
    if !CommitIniChanges([Map("section", section, "key", key, "value", value)]) {
        ShowNotification("The setting could not be saved", "Warning")
        return false
    }
    LoadSettings()
    ApplyRuntimeTimers()
    ; If the full Settings window is open behind the Quick Menu, move its control
    ; too, or a later Save there writes the stale value back over this.
    SettingsEditorSyncFieldControl(section, key)
    if (!EnableAutoHideCursor && MouseHidden) {
        SystemCursor("Show")
        MouseHidden := false
    }
    SyncControlPanel()
    return true
}

; One source of truth for the Quick Menu's settings rows, shared by activation
; and left/right adjustment. These were duplicated `case` lists until AutoHotkey
; v2's hard limit of 20 parameters per `Case` rejected the longer one.
; The live value behind a QuickMenuToggleTable row, by ROW ID.
;
; The one thing a shared caller genuinely cannot do. AutoHotkey v2 has no way to
; read a global by a name held in a variable, so the table can carry the section
; and the key but not the current state -- and the alternative, keeping every
; setting in a Map instead of its own global, would touch every reader in the
; program. One lookup is the floor, and this is it.
;
; Keyed on the row id rather than on the setting key, and it stays that way even
; though the pair that forced it -- two rows both writing a key literally named
; "Enable", in different sections -- has since been retired. A setting key is
; not unique across sections, so the id is the only safe lookup.
ProductSettingBool(id) {
    global EnableDesktopBlackout
    global EnableControllerMouseMode, EnableAutoHideCursor
    global EnableMouseParkOnBoot, EnableMouseParkOnFocusChange
    global EnableSteamRefocusMode, EnableGameForegroundAssist, EnableAlwaysFocus
    global EnableRTSSIntegration
    switch id {
        case "qBlackout": return EnableDesktopBlackout
        case "qControllerMouse": return EnableControllerMouseMode
        case "qAutoHideCursor": return EnableAutoHideCursor
        case "qParkBoot": return EnableMouseParkOnBoot
        case "qParkFocus": return EnableMouseParkOnFocusChange
        case "qSteamRefocus": return EnableSteamRefocusMode
        case "qGameAssist": return EnableGameForegroundAssist
        case "qAlwaysFocus": return EnableAlwaysFocus
        case "qRtssIntegration": return EnableRTSSIntegration
    }
    return false
}

IsQuickMenuToggleSetting(id) {
    static ids := QuickMenuIdSet(
        "qSplash|qTaskbar|qBlackout"
        . "|qControllerMouse|qPersistentMouse|qAutoHideCursor|qParkBoot|qParkFocus|qParkEdge"
        . "|qSteamRefocus|qGameAssist|qAlwaysFocus|qWindowManagement|qFocusPaused"
        . "|qRtssIntegration|qOverlayMode|qLimiterMode")
    return ids.Has(id)
}

IsQuickMenuAdjustSetting(id) {
    static ids := QuickMenuIdSet("qMouseSpeed|qMouseHideDelay|qFrameCap|qAccentColor")
    return ids.Has(id)
}

ToggleQuickMenuSetting(id) {
    ; Same table, other direction. The value above and the write below used to
    ; be two `case` lists over the same eleven ids.
    if QuickMenuToggleTable().Has(id) {
        entry := QuickMenuToggleTable()[id]
        PersistQuickMenuSetting(entry["section"], entry["key"],
            ProductSettingBool(id) ? "false" : "true")
        return
    }
    ; The rows that flip between two named states rather than on and off.
    if QuickMenuCycleSharedSetting(id)
        return
    global EnableSplashScreen, EnableTaskbarHiding, EnableDesktopBlackout
    global EnableControllerMouseMode, EnablePersistentMouseMode, EnableAutoHideCursor
    global EnableMouseParkOnBoot, EnableMouseParkOnFocusChange, MouseParkEdge
    global EnableSteamRefocusMode, EnableGameForegroundAssist, EnableAlwaysFocus, EnableWindowManagement
    global EnableRTSSIntegration, RtssOverlayControlMode, RtssFrameLimiterControlMode
    global FocusAssistancePaused

    switch id {
        case "qSplash":
            PersistQuickMenuSetting("Features", "EnableSplashScreen", EnableSplashScreen ? "false" : "true")
        case "qTaskbar":
            PersistQuickMenuSetting("Features", "EnableTaskbarHiding", EnableTaskbarHiding ? "false" : "true")
        case "qPersistentMouse":
            next := !EnablePersistentMouseMode
            changes := [Map("section", "Controller", "key", "EnablePersistentMouseMode",
                "value", next ? "true" : "false")]
            if (next && !EnableControllerMouseMode)
                changes.InsertAt(1, Map("section", "Controller",
                    "key", "EnableControllerMouseMode", "value", "true"))
            if !CommitIniChanges(changes) {
                ShowNotification("Mouse Mode could not be saved", "Warning")
                return
            }
            LoadSettings()
            ApplyRuntimeTimers()
            SyncControlPanel()
            ShowNotification("Mouse Mode: " (next ? "On" : "Off"), "Success")
        case "qWindowManagement":
            PersistQuickMenuSetting("Features", "EnableWindowManagement", EnableWindowManagement ? "false" : "true")
        case "qFocusPaused":
            FocusAssistancePaused := !FocusAssistancePaused
    }
    QuickMenuRefresh()
}

AdjustQuickMenuSetting(id, direction) {
    ; Every adjustable settings row is shared; the shell has no numeric row of
    ; its own. Anything else is a plain toggle, and Left/Right flip it the same
    ; way A does.
    if !QuickMenuAdjustSharedSetting(id, direction) {
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
    global QuickMenuDisplayModes
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    global DisplaySelectedScalePercent
    QuickMenuDisplayModes := GetPrimaryDisplayModes()
    DisplaySelectedWidth := 0
    DisplaySelectedHeight := 0
    DisplaySelectedFrequency := 0
    DisplaySelectedScalePercent := 0
    EnsureDisplaySelection()
    EnsureDisplayScaleSelection()
    QuickMenuGoToPage("DISPLAY")
}

OpenQuickMenuTaskPage() {
    global QuickMenuTaskPage, QuickMenuTaskWindows
    QuickMenuTaskWindows := SharedTaskSwitcherWindows()
    QuickMenuTaskPage := 1
    QuickMenuGoToPage("TASKS")
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
                . ShortenText(item["title"], 36),
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
        QuickMenuTaskWindows := SharedTaskSwitcherWindows()
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
    QuickMenuTaskWindows := SharedTaskSwitcherWindows()
    QuickMenuBuildGui()
}

ForceCloseTaskSwitcherWindow(hwnd) {
    global QuickMenuTaskWindows, PinnedForegroundHwnd
    item := FindTaskSwitcherWindow(hwnd)
    if (!IsObject(item) || !DllCall("IsWindow", "Ptr", hwnd)) {
        QuickMenuTaskWindows := SharedTaskSwitcherWindows()
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
    QuickMenuTaskWindows := SharedTaskSwitcherWindows()
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

QuickMenuActivateSelected() {
    global QuickMenuRows, QuickMenuSelected, QuickMenuPage
    global SteamQuickAccessShortcut

    if (QuickMenuRows.Length = 0)
        return
    row := QuickMenuRows[QuickMenuSelected]
    id := row["id"]

    ; Navigation is a property of the row, not a name the switch below has to
    ; recognise. Sixteen ids used to reach two identical bodies here -- eight
    ; calling QuickMenuGoBack, eight setting a page and rebuilding -- and every
    ; new page meant remembering to add its id in three places.
    ;
    ; Rows that do setup work before navigating (display, tasks) keep their
    ; cases below, because they are not just a page change.
    if row.Has("back") {
        QuickMenuGoBack()
        return
    }
    if row.Has("page") {
        QuickMenuGoToPage(row["page"])
        return
    }

    if (SubStr(id, 1, 7) = "layout:")
        return
    if (SubStr(id, 1, 11) = "taskWindow:") {
        SelectTaskSwitcherWindow(ToInt(SubStr(id, 12), 0))
        return
    }
    ; The destination rows on CURRENTAPP. The write, the duplicate check and the
    ; refusal all live in SteamShell-Shared.ahk, so this tree names the product
    ; and nothing else.
    ;
    ; Rebuild rather than repaint, for the reason spelled out at the four
    ; navigation cases below: "(already added)" is part of the row's LABEL, and
    ; labels are composed in QuickMenuGetDefinitions. A repaint would redraw the
    ; label the page was built with, so the add would appear to have done
    ; nothing until the page was left and re-entered.
    if (SubStr(id, 1, 11) = "currentapp:") {
        QuickMenuAddCurrentAppTo(id, "standalone")
        QuickMenuBuildGui()
        return
    }

    ; Actions both products implement identically.
    if QuickMenuActivateShared(id) {
        QuickMenuRefresh()
        return
    }
    switch id {
        case "mute":
            try {
                SoundSetMute(-1)
                muted := SoundGetMute()
                ShowNotification(muted ? "Audio muted" : "Audio unmuted", "Success")
            } catch {
                ShowNotification("Windows mute control is unavailable", "Warning")
            }
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
        case "rtssStart":
            if !EnsureRtssRunning()
                ShowNotification("RTSS could not be started", "Warning")
            QuickMenuBuildGui()
            return
        case "rtssFrameLimit":
            ; Wraps: A is the only control on this row for a user who never
            ; discovers Left/Right, so it has to be able to reach every entry.
            if CycleRtssFrameCap(1, true) {
                QuickMenuBuildGui()
                return
            }
        case "rtssSaveProfile":
            ; Writes a file RTSS then applies to that game on every future launch,
            ; with nothing on screen afterwards to say it happened. Confirmed.
            if (RtssProfileTargetExe() = "") {
                ShowNotification("No foreground game to save a profile for", "Warning")
            } else if QuickMenuConfirm("rtssSaveProfile",
                "saving " RtssProfileTargetExe() " frame limit") {
                SaveRtssFrameLimitToProfile()
            }
        case "rtssSettings":
            HideQuickMenu(false)
            ShowSettingsEditorCategory("RTSS & Performance")
            return
        case "settingsEditor":
            HideQuickMenu(false)
            ShowSettingsEditor()
            return
        case "windowsSettings":
            HideQuickMenu(false)
            SetTimer(OpenWindowsSettings, -100)
            return
        case "setControllerMappings":
            HideQuickMenu(false)
            SetTimer(ShowControllerMappingWindow, -100)
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
        case "openKeyboard":
            HideQuickMenu(false)
            SetTimer(OpenTouchKeyboard, -100)
            return
        case "desktop":
            if !QuickMenuConfirm("desktop", "exit Steam to desktop")
                return
            HideQuickMenu(false)
            ExitSteamAndRestoreDesktop()
        case "returnShell":
            if !QuickMenuConfirm("returnShell", "return to SteamShell")
                return
            LaunchSteamAndReturnToShell()
        case "exitApp":
            if !QuickMenuConfirm("exitApp", "close SteamShell")
                return
            HideQuickMenu(false)
            ExitSteamShell()
        ; These four navigate from the switch rather than from the row, because
        ; each does something the row-carried path cannot: a guard, or a return
        ; to a NAMED page rather than wherever QuickMenuGoBack would land. What
        ; they no longer do is spell the navigation -- that is QuickMenuGoToPage,
        ; in the shared file, and these four spelling it by hand is exactly how
        ; all four came to end in a repaint instead of a rebuild.
        case "gameDetection":
            QuickMenuGoToPage("GAMESCORE")
            return
        case "currentApp":
            ; Nothing to offer, and the row already says why. Opening a page of
            ; destinations that would all refuse is worse than not opening one.
            if !QuickMenuCurrentAppSelectable() {
                ShowNotification(QuickMenuCurrentAppBlockedReason(), "Warning")
                return
            }
            QuickMenuGoToPage("CURRENTAPP")
            return
        case "currentAppBack":
            QuickMenuGoToPage("SYSTEM")
            return
        case "gameScoreBack":
            QuickMenuGoToPage("SYSTEM")
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

GetCurrentDisplayModeText() {
    global DisplayPendingOldMode, DisplayPendingUntilTick
    text := SharedDisplayModeText()
    ; Shell-only: a mode change is staged and reverts unless confirmed, and the
    ; countdown belongs on the row the user is looking at.
    if IsObject(DisplayPendingOldMode) {
        seconds := Max(0, Ceil((DisplayPendingUntilTick - A_TickCount) / 1000))
        text .= "  KEEP? " seconds "s"
    }
    return text
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


PollController() {
    global LearnActive
    global EnableControllerMouseMode, ControllerIndex, ControllerDeadzone
    global ControllerNeedsFreshBaseline
    global ControllerMouseSpeed, ControllerMouseFastMultiplier
    global ControllerScrollIntervalMs, ControllerScrollStep, ControllerChordHoldMs
    global QuickMenuVisible, EnableQuickMenu, QuickMenuChordHoldMs
    global MouseHidden
    global SettingsDialogActive
    global ControllerTestGui
    global ControllerPollIntervalMs

    static state := Buffer(16, 0)
    static previousButtons := 0
    static lastScroll := 0
    static previousViewDown := false
    ; The View button's own press, tracked apart from previousViewDown: that one
    ; follows the mapping gate and so is true throughout automatic mouse mode,
    ; which is not a press anybody made.
    static viewWasDown := false
    static viewPressTick := 0
    static viewUsedAsModifier := false
    static quickChordSince := 0
    static quickChordFired := false
    static settingsChordSince := 0
    static settingsChordFired := false
    ; Per-button press tracking (to support Short/Long bindings) without ByRef locals.
    static downTick := Map()
    static longFired := Map()
    static triggerDown := Map("LT", false, "RT", false)
    static settingsLtDown := false
    static settingsRtDown := false

    static inPoll := false
    static buttonDefinitions := [
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

    ControllerPrimeHoldTables(downTick, longFired, buttonDefinitions)

    if (inPoll)
        return
    ; Before the reentrancy guard: this is a wall-clock check, not controller
    ; work, and it must still run on the tick where a resume is first noticed.
    ;
    ; This is the shell's ONLY resume detection. WM_POWERBROADCAST is registered
    ; as well, but an ROG Ally sleeps into modern standby, where it is not
    ; reliably delivered -- which the companion established on the hardware.
    ControllerResumeGapCheck(ControllerPollIntervalMs / 1000)
    inPoll := true
    try {

    ; The learner owns the controller while its wizard is open. It reads the pad
    ; itself through WM_INPUT, so standing this poll down costs it nothing and
    ; stops everything else acting on the same buttons.
    ;
    ; Not just the automatic mouse. ControllerSettingsSurfaceActive() answers true
    ; for ANY window this process owns that is active, which is deliberate and
    ; which the learner's window satisfies -- so the poll treated the wizard as a
    ; surface to navigate: the right stick drove the pointer across it and the
    ; D-pad moved focus between its own buttons, while the wizard was asking for
    ; a D-pad direction. It could not be completed.
    ;
    ; The chords are the same story. It asks for L3 and R3 by name and L3+R3 is
    ; the Quick Menu chord, so it can throw the Quick Menu on top of itself while
    ; asking for the buttons that do it. The companion has had this guard since
    ; it wrote the wizard; the shell only just gained the wizard and not the
    ; guard with it.
    ;
    ; Edge state is cleared rather than left, or every button held when the
    ; wizard opened fires its mapping the moment it closes.
    ;
    ; A fresh baseline is REQUESTED rather than previousButtons being zeroed. Zeroing
    ; it produces the exact misfire this paragraph promises to prevent: the next
    ; poll computes pressed as buttons & ~0, so every button still held when the
    ; wizard closes arrives as a press edge and fires its mapping. The wizard
    ; ends on a button press more often than not -- Save is reached by pressing
    ; something -- so this is the common case, not the corner. Asking for a
    ; baseline instead makes the first poll after the wizard sample the pad as it
    ; actually is and discard that sample's edges, which is what "cleared" was
    ; meant to mean.
    if LearnActive {
        ControllerNeedsFreshBaseline := true
        quickChordSince := 0
        quickChordFired := false
        settingsChordSince := 0
        settingsChordFired := false
        ResetControllerHoldState(
            &previousViewDown, downTick, longFired, triggerDown, buttonDefinitions,
            &viewWasDown)
        return
    }
    settingsControllerActive := ControllerSettingsSurfaceActive()
    settingsMainActive := SettingsPrimaryActive()
    isControllerTestActive := ControllerTestActive()
    if (!EnableControllerMouseMode && !EnableQuickMenu
        && !settingsControllerActive && !isControllerTestActive)
        return

    if !ControllerReadState(&state) {
        if isControllerTestActive {
            ; Not "at configured index N" any more. Every slot is tried now, so
            ; naming the configured one sent the reader to a setting that was
            ; not the problem and could not be the fix.
            try ControllerTestGui["ControllerButtons"].Text :=
                "No controller detected on any XInput slot."
        }
        ; Discard all edge/hold state while disconnected. Otherwise reconnecting
        ; can synthesize stale releases or complete an old long-press.
        previousButtons := 0
        quickChordSince := 0
        quickChordFired := false
        settingsChordSince := 0
        settingsChordFired := false
        settingsLtDown := false
        settingsRtDown := false
        ResetControllerHoldState(
            &previousViewDown, downTick, longFired, triggerDown, buttonDefinitions,
            &viewWasDown)
        return
    }

    now := A_TickCount

    ControllerDecodeState(state, &buttons, &lt, &rt, &lx, &ly, &rx, &ry)

    ; The controller test owns all input while visible so calibration cannot
    ; accidentally launch mapped actions, open overlays, or navigate another app.
    if ControllerTestActive() {
        UpdateControllerTest(buttons, lt, rt, lx, ly, rx, ry)
        previousButtons := buttons
        quickChordSince := 0
        quickChordFired := false
        settingsChordSince := 0
        settingsChordFired := false
        settingsLtDown := false
        settingsRtDown := false
        ResetControllerHoldState(
            &previousViewDown, downTick, longFired, triggerDown, buttonDefinitions,
            &viewWasDown)
        return
    }

    ControllerApplyStickDeadzone(&lx, &ly, &rx, &ry, ControllerDeadzone)

    ; Controller chord: LB+RB+L3+R3 opens Full Settings (works even without
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
    ; Settings chord: LB + RB + L3 + R3, held. The triggers are deliberately NOT
    ; part of this test.
    ;
    ; This required LT and RT as well, which is unreachable on the controllers
    ; the RawInput backend exists for: they report both triggers on ONE combined
    ; axis, where pressing both cancels out, so "LT and RT are both down" can
    ; never be true. It is the only keyboardless route to Full Settings, so on
    ; the very controller the port was made for, Full Settings became
    ; unreachable.
    ;
    ; XFE_PARITY_NOTES.md said so before the port was made -- "if it is taken,
    ; standalone's chord MUST be ported to XFE's at the same time" -- and the
    ; port was made without it. This is that.
    ;
    ; Pressing the old six-button combination still satisfies this one: the
    ; triggers are ignored rather than forbidden. The hold requirement is what
    ; keeps the looser chord from firing during play.
    settingsComboNow := ((buttons & 0x0100) && (buttons & 0x0200)
        && (buttons & 0x0040) && (buttons & 0x0080))
    ; The gates are folded into the held-ness rather than wrapped around it, so
    ; a surface taking ownership mid-hold CLEARS the measurement instead of
    ; freezing it -- which is what the old else-branch did by hand.
    settingsChordEligible := (settingsComboNow
        && !QuickMenuVisible
        && !settingsControllerActive
        && !StartupRecoveryControllerActive())
    if ControllerChordFired(settingsChordEligible, QuickMenuChordHoldMs, now,
        &settingsChordSince, &settingsChordFired) {
        try LogLine("Controller Settings chord detected.")
        try ShowSettingsEditor()
        return
    }

    ControllerButtonEdges(buttons, &previousButtons, &pressed, &released)

    ; One line per button edge and per trigger crossing, while DiagnosticLogging
    ; is on. This product read that setting and logged nothing per report, so
    ; the same row promised less here than in the companion -- and the half that
    ; was missing is the half that matters when a controller is unreadable,
    ; which on the Windows shell means a machine nobody can drive.
    ControllerLogInputChange(buttons, lt, rt, pressed, released)

    ; Full Settings reserves the analog triggers for category changes. Track
    ; their edges here—even while View/Back is held—so releasing Back cannot
    ; create a stale category change. Ignore both together because both triggers
    ; are part of the Full Settings fallback chord.
    ;
    ; Evaluated BEFORE the fresh-baseline return below, so that an edge-free
    ; sample is edge-free for the triggers too. It ran after, which left the
    ; trigger trackers holding whatever they held before the interruption while
    ; every other tracker was reset: close the Quick Menu or the learner with a
    ; trigger held and the poll after the baseline one saw a rising edge that
    ; never happened and changed the Settings category on its own. The direction
    ; computed on a baseline poll is discarded with the rest of that sample.
    ; THIS SAMPLE is currentLtDown/currentRtDown; the PREVIOUS one is the two
    ; statics. Both halves are needed -- a category change is a rising edge, not
    ; a held trigger -- and giving them the same name is what broke this once
    ; already: the statics were settingsPrevLtDown/settingsPrevRtDown until they
    ; were renamed onto the sample locals, which left the edge tests reading
    ; `settingsLtDown && !settingsLtDown` and the commit-back reading
    ; `settingsLtDown := settingsLtDown`. Both are valid AHK, neither changes a
    ; reference count, so the build stayed green while settingsCategoryDirection
    ; was permanently 0 and the triggers did nothing in Full Settings.
    ;
    ; The names here are the companion's, at SteamShell-XFE.ahk's settings
    ; surface: persistent state keeps settingsLtDown/settingsRtDown, the sample
    ; is current*. Same two roles, same two names, in both products.
    currentLtDown := lt > 30
    currentRtDown := rt > 30
    settingsCategoryDirection := 0
    if (settingsMainActive
        && !SettingsDialogActive
        && !(buttons & 0x0020)
        && !(currentLtDown && currentRtDown)) {
        if (currentLtDown && !settingsLtDown)
            settingsCategoryDirection := -1
        else if (currentRtDown && !settingsRtDown)
            settingsCategoryDirection := 1
    }
    settingsLtDown := currentLtDown
    settingsRtDown := currentRtDown

    ; A menu-selection button can still be physically down when the menu is
    ; destroyed. Establish one edge-free sample and clear every hold tracker so
    ; its later release cannot also fire the normal persistent mapping.
    if ControllerNeedsFreshBaseline {
        ResetControllerHoldState(
            &previousViewDown, downTick, longFired, triggerDown, buttonDefinitions,
            &viewWasDown)
        ControllerNeedsFreshBaseline := false
        return
    }

    ; These three surfaces own the controller and return before the View
    ; tracking below ever runs, so a View held as one of them opens would still
    ; be "down" when it closes -- and the release would report a hold lasting as
    ; long as the dialog was up, firing the hold action over whatever came next.
    ; Dropped rather than carried: a press the user made to reach a dialog is not
    ; a press meant for Steam.
    if DesktopRecoveryControllerActive() {
        viewWasDown := false
        RecoveryDialogHandleController(pressed)
        return
    }
    if StartupRecoveryControllerActive() {
        viewWasDown := false
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
    if ControllerChordFired(quickChordNow, QuickMenuChordHoldMs, now,
        &quickChordSince, &quickChordFired) {
        ToggleQuickMenu()
        return
    }

    ; While the quick menu owns focus, route controller presses to it before
    ; evaluating the normal View/Back modifier mappings.
    if (QuickMenuVisible) {
        QuickMenuWatchForegroundLoss()
        viewWasDown := false
        QuickMenuHandleController(pressed, released, lx, ly, buttons)
        return
    }

    ; The full Settings editor has controller-first navigation and automatic
    ; right-stick mouse movement. Holding View/Back deliberately falls through
    ; to the normal configurable mappings so mapped clicks and shortcuts remain
    ; available inside Settings.
    if (settingsControllerActive) {
        if (SettingsDialogActive || !(buttons & 0x0020)) {
            if MouseHidden {
                SystemCursor("Show")
                MouseHidden := false
            }
            ResetControllerHoldState(
                &previousViewDown, downTick, longFired, triggerDown, buttonDefinitions,
                &viewWasDown)
            if (SettingsDialogActive || settingsMainActive)
                SettingsEditorHandleController(
                    pressed, lx, ly, rx, ry, settingsCategoryDirection)
            else
                SettingsEditorHandlePointer(pressed, rx, ry)
            return
        }
    }

    ; A High/System-integrity application owns the foreground. The elevated
    ; helper reads the same physical controller and settings for this narrow
    ; interval; stop here so cursor motion and releases cannot be handled twice.
    ; Quick Menu, recovery, and Settings were evaluated first, allowing their
    ; chords to bring a normal-integrity SteamShell surface forward immediately.
    ;
    ; Not a clean return, though. The helper refuses to start processes or raise
    ; SteamShell windows from a High-integrity token, so yielding everything left
    ; TabTip, OSK, Explorer, Quick Menu, and Control Panel handled by neither
    ; process -- with Task Manager focused there was no way to reach the on-screen
    ; keyboard and type into it. Those five stay here, at normal integrity, and
    ; are exactly the ones the helper's builtin switch declines.
    if ElevatedHelperOwnsForeground() {
        ControllerHandleElevatedForeground(
            buttons, lt, rt, pressed, released, now,
            quickChordNow || settingsComboNow)
        ResetControllerHoldState(
            &previousViewDown, downTick, longFired, triggerDown, buttonDefinitions,
            &viewWasDown)
        return
    }

    ; The View button's own tap/hold action, tracked BEFORE the controller-mouse
    ; gate so it works whether or not mouse mode is enabled -- the same placement
    ; and the same reason as the companion.
    ;
    ; This is the modifier button, and that is not a conflict: any other input
    ; during the hold marks the press as a modifier use and its own action is
    ; dropped on release. "Hold View, press A" therefore fires the A mapping and
    ; nothing else.
    viewPhysical := ControllerTrackViewButton(buttons, lt, rt, lx, ly, rx, ry, now,
        &viewWasDown, &viewPressTick, &viewUsedAsModifier)

    ; Quick Menu and Settings navigation still require polling when normal
    ; controller mouse/mapping mode is disabled. Stop here before processing any
    ; View/Back mapping, stick movement, scrolling, or D-pad passthrough.
    if (!EnableControllerMouseMode) {
        ResetControllerHoldState(
            &previousViewDown, downTick, longFired, triggerDown, buttonDefinitions,
            &viewWasDown)
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
        ; The PHYSICAL button and the mapping gate are two different things, and they are
        ; named separately now: viewPhysical above drives the tap/hold action, this drives
        ; the mappings. Reading one variable for both would make automatic mouse mode --
        ; which is a permanent virtual hold -- look like a button the user is holding
        ; down, and every release of it like a tap.
        viewDown := viewPhysical || autoMouse
        if (!viewDown) {
            ; Reset press tracking so Short/Long doesn't misfire when View/Back is not held.
            ResetControllerHoldState(
                &previousViewDown, downTick, longFired, triggerDown, buttonDefinitions,
                &viewWasDown)
            return
        }

        ; Everything from here is ControllerPollFrame in SteamShell-Shared.ahk: adopt
        ; held buttons, cursor, wheel, Short/Long for buttons and triggers, D-pad,
        ; Guide. It was the same routine in both products; the heads above it are
        ; not, and stay here.
        ControllerPollFrame(buttons, pressed, released, lt, rt, rx, ry, ly, now,
            buttonDefinitions, downTick, longFired, triggerDown,
            &previousViewDown, &lastScroll)
    } finally {
        inPoll := false
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

; The shell's view of the shared inventory: everything it enumerates, in the
; order it enumerated it, plus the hwnd index and the Big Picture flag.
;
; NO FILTERING HERE, deliberately. This engine keeps desktop and shell windows in
; the snapshot and marks them, because AlwaysFocus and the Explorer guard both
; need to see them; the companion drops them on the way out of its own wrapper.
; That difference used to be buried in two separate enumerations.
;
; "bpm" is filled in here rather than in the shared builder because BpmTitle is a
; shell setting. Partial matching, still: the pre-engine implementation used
; SetTitleMatchMode 2 and titles carry suffixes.
WindowEngineBuildSnapshot() {
    global WindowEngineSnapshot, WindowEngineSnapshotByHwnd
    global WindowEngineSnapshotBusy
    global WindowEngineLastSnapshotTick, WindowEngineLastWindowCount

    if WindowEngineSnapshotBusy
        return WindowEngineSnapshot
    WindowEngineSnapshotBusy := true
    try {
        snapshot := SharedWindowInventoryBuild()
        byHwnd := Map()
        for _, item in snapshot {
            item["bpm"] := WindowEngineTitleMatchesBpm(item["title"])
            byHwnd[item["hwnd"]] := item
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

WindowEngineGeometryHandledByHelper(item) {
    if !ElevatedHelperIsVerified()
        return false
    if !GetProcessTokenSecurity(
        item["pid"], &targetSid, &targetSession,
        &integrityName, &integrityError)
        return false
    return integrityName = "High" || integrityName = "System"
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
        ; The normal-integrity engine cannot reliably move a High-integrity
        ; Task Manager or administrative surface. The verified helper reads the
        ; same geometry settings and owns those targets exclusively.
        if WindowEngineGeometryHandledByHelper(item)
            continue
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
        actionAttempted := needsMove || needsMaximize
        if needsMove {
            try {
                WinMove(targetX, targetY,,, id)
                actionSucceeded := true
                ; Log only after WinMove returned successfully. The former
                ; unconditional diagnostic claimed an elevated window was
                ; centred even when UIPI rejected the operation.
                if (EnableGameScoreLogging && GameLogMode = "DIAGNOSTIC")
                    LogLine("Geometry: centred " item["proc"] " [" item["class"] "] "
                        . item["w"] "x" item["h"] " style 0x" Format("{:08X}", item["style"])
                        . " exStyle 0x" Format("{:08X}", item["exStyle"])
                        . " owner " (item["owner"] ? "yes" : "no")
                        . " | " item["title"])
            }
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
        } else if actionAttempted {
            ; Count failed attempts too. Without this branch an inaccessible
            ; target was retried every engine tick forever despite the documented
            ; bounded retry budget.
            state["actions"] += 1
            state["nextAttempt"] := now + WindowEngineGeometryRetryMs
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
    SharedPruneCpuSamples(WindowEngineCpuSamples, snapshot)
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
    ;
    ; Still unpooled. ProcessRunningByHandle caches a HANDLE, not an answer -- it
    ; asks the kernel whether that exact process has exited, every call, and only
    ; skips re-walking the process table to find it again. That is a stronger
    ; signal than the name lookup it replaces, which could not tell a still-running
    ; Steam from a Steam that exited and was relaunched under a new PID.
    steamRunning := ProcessRunningByHandle("steam.exe")

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

    SplitPath(path, , &steamDirectory)
    steamPid := 0
    try {
        if !LaunchInteractiveApp(
            path,
            "-bigpicture -fulldesktopres -nobootstrapupdate",
            steamDirectory,
            "Normal",
            &steamPid,
            "Steam Big Picture")
            throw Error("No verified standard-user launch route was available.")
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
    ; Set the large font before constructing the control so AutoHotkey measures
    ; its height from the actual glyphs. Enlarging an existing s11 control leaves
    ; the old one-line height and clips the title vertically at high DPI.
    StartupRecoveryGui.SetFont("s17 Bold", "Segoe UI")
    StartupRecoveryGui.AddText("xm w620 Center", "STEAM DID NOT START")
    StartupRecoveryGui.SetFont("s11 Norm", "Segoe UI")
    StartupRecoveryGui.AddText("xm y+12 w620 +Wrap Center", reason)
    StartupRecoveryGui.AddText("xm y+6 w620 +Wrap Center", "Choose an action below. The normal desktop has not been restored automatically.")
    retryButton := StartupRecoveryGui.AddButton("xm y+18 w180 h38 Default", "Retry Steam")
    settingsButton := StartupRecoveryGui.AddButton("x+12 yp w180 h38", "Open Settings")
    desktopButton := StartupRecoveryGui.AddButton("x+12 yp w236 h38", "Restore Desktop")
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
    DesktopRecoveryGui.SetFont("s17 Bold", "Segoe UI")
    DesktopRecoveryGui.AddText("xm w620 Center", "DESKTOP RESTORE FAILED")
    DesktopRecoveryGui.SetFont("s11 Norm", "Segoe UI")
    DesktopRecoveryGui.AddText("xm y+12 w620 +Wrap Center", reason)
    DesktopRecoveryGui.AddText("xm y+6 w620 +Wrap Center",
        "SteamShell is still running. Windows may have no visible shell until this succeeds.")
    retryButton := DesktopRecoveryGui.AddButton("xm y+18 w180 h38 Default", "Retry Restore")
    settingsButton := DesktopRecoveryGui.AddButton("x+12 yp w180 h38", "Open Settings")
    stayButton := DesktopRecoveryGui.AddButton("x+12 yp w236 h38", "Keep SteamShell Running")
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
    return GuiVisibleAndActive(DesktopRecoveryGui)
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
    return GuiVisibleAndActive(StartupRecoveryGui)
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


GetProcessCpuSample(pid) {
    global WindowEngineCpuSamples, WindowEngineCpuSampleIntervalMs
    return SharedProcessCpuSample(
        pid, WindowEngineCpuSamples, WindowEngineCpuSampleIntervalMs)
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

; The name shared code asks by, bound to this tree's foreground cache.
;
; SteamShell-Shared.ahk's ViewButtonReleased needs to know whether Steam is in
; front, and both products already answered that -- under two names, over two
; different caches. The companion resolves it through CurrentForegroundExe and
; LastObservedForegroundExe; this tree keeps LastRealFgHwnd and tests the process
; name itself. Both deliberately look past our OWN windows, which is the part
; that makes the question worth caching at all.
;
; A two-line binding rather than a merge: the caches are real per-tree state and
; folding them together would mean changing how one product observes the
; foreground to satisfy a name.
SteamIsInFront() {
    return IsSteamForeground()
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
; GAME ASSIST
; ==============================================================================

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

ForceGameAssistOnce() {
    snapshot := WindowEngineBuildSnapshot()
    return TryBringFullscreenCandidateToFront(true, true, snapshot)
}

; The tunables the shared scorer needs, gathered in one place so both the
; evaluate loop and any future caller pass exactly the same set.
;
; borderlessRatio was a bare 0.90 written inline in the scoring loop, with no
; setting behind it and no name. It keeps that value here; naming it was the
; only way to hand it to a shared function without inventing a setting the
; product never had.
WindowEngineScoreWeights() {
    global FullscreenTolerance, FullscreenPosTolerancePx
    global ScoreFullscreen, ScoreBorderlessLarge, ScoreTitleBonus
    global GameCPUThresholdPercent, ScoreCpuAboveThreshold, ScoreCpuNonZeroBonus
    global GameAllowZeroCpuAsCandidate
    ; Carried in the weights map for parity with the companion; the evaluate
    ; loop adds this bonus itself, once a candidate has survived the CPU verdict.
    global ScoreAudioActive
    return Map(
        "fullscreenTolerance", FullscreenTolerance,
        "positionTolerancePx", FullscreenPosTolerancePx,
        "borderlessRatio", 0.90,
        "fullscreen", ScoreFullscreen,
        "borderlessLarge", ScoreBorderlessLarge,
        "titleBonus", ScoreTitleBonus,
        "cpuThresholdPercent", GameCPUThresholdPercent,
        "cpuAboveThreshold", ScoreCpuAboveThreshold,
        "cpuNonZeroBonus", ScoreCpuNonZeroBonus,
        "allowZeroCpu", GameAllowZeroCpuAsCandidate,
        ; Carried for parity with the companion's weights map. The evaluate loop
        ; still adds this bonus itself, because it only builds the audio map once
        ; a candidate has survived the CPU verdict.
        "audioActive", ScoreAudioActive)
}

; What this product excludes before a window is even scored.
;
; A callback rather than a shared filter, because the companion's exclusions are
; a different set and folding either into the other would change what each
; product detects as a game. Untitled is allowed through for a legacy surface:
; older DirectX games publish one, and rejecting them here is how a fullscreen
; game goes unnoticed.
WindowEngineSkipForGameScore(item) {
    minimizedLegacyGame := WindowEngineIsMinimizedLegacyGameSurface(item)
    legacySurface := WindowEngineIsLegacyApplicationSurface(item)
        || minimizedLegacyGame
    if (item["desktop"] || item["steam"]
        || (item["minMax"] = -1 && !minimizedLegacyGame)
        || (item["title"] = "" && !legacySurface))
        return true
    ; Never the on-screen keyboard, which is large, titled and always up.
    winClass := StrLower(item["class"])
    return item["proc"] = "osk.exe" || winClass = "oskmainclass"
        || InStr(StrLower(item["title"]), "on-screen keyboard")
}

; One reject row for the diagnostic score table, in this product's format.
;
; The shared scorer collects rejects as FACTS and leaves the formatting here,
; because the companion has no such table. The shape stage reports "---" for a
; score it never computed and "N" for nearFS, which is what this table has always
; printed for that stage.
WindowEngineRejectRow(reject) {
    item := reject["item"]
    shapeStage := reject["stage"] = "shape"
    return LogRow(
        NowStamp(), "REJ",
        shapeStage ? "---" : FmtScore(reject["score"], true),
        item["proc"], FmtPid(item["pid"]),
        FmtCpu(reject["cpu"], !shapeStage),
        "-",
        (!shapeStage && reject["nearFS"]) ? "Y" : "N",
        FmtRect(item["x"], item["y"], item["w"], item["h"]),
        FmtHwnd(item["hwnd"]), reject["reason"], item["title"])
}

WindowEngineEvaluateGame(snapshot, forceRun, &allowActivate, &skipReason) {
    global EnableGameForegroundAssist, GameForegroundCooldownMs, LastGameBringToFrontTick
    global GameRequireSteamForeground, GameAssistLogEvenWhenSkipped
    global GameMinScoreToActivate
    global EnableAudioAssist, AudioPeakThreshold
    global EnableGameScoreLogging, GameLogMode, GameLogRejectNearCandidates
    global GameLogRejectMinAreaPercent
    global LastBestCandidateScore, LastBestCandidateProc
    global LastBestCandidateTitle, LastBestCandidateText
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

    ; Zero means do not collect rejects at all, which folds the three logging
    ; switches into the one number the scorer needs.
    rejectMinArea := (EnableGameScoreLogging && GameLogMode = "DIAGNOSTIC"
        && GameLogRejectNearCandidates)
        ? A_ScreenWidth * A_ScreenHeight * GameLogRejectMinAreaPercent
        : 0
    scored := SharedScoreGameCandidates(
        snapshot, WindowEngineScoreWeights(), GetProcessCpuSample,
        WindowEngineSkipForGameScore,
        EnableAudioAssist, AudioPeakThreshold, rejectMinArea)
    candidates := scored["candidates"]

    rejects := []
    for _, reject in scored["rejects"]
        rejects.Push(WindowEngineRejectRow(reject))

    CaptureGameCandidates(candidates)
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
    headerNote := "min=" GameMinScoreToActivate
    if (!allowActivate && skipReason != "")
        headerNote := "SKIP_" skipReason " " headerNote
    LogGameCandidateTable(candidates, rejects, headerNote)
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
    global AlwaysFocusGui, SettingsGui, SettingsDialogActive
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
    SettingsDialogActive := true
    try selectedPath := FileSelect(1, A_ProgramFiles, prompt, "Programs (*.exe)")
    catch {
        selectedPath := ""
    } finally {
        SettingsDialogActive := false
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

; Adds an application from the shared recent-application history.
;
; Routed through the same AF_AddExe body as the live list, so the two entry
; points cannot disagree about deduplication, about enabling AlwaysFocus, or
; about the reminder that nothing is persistent until Write to INI.
AF_AddRecent(*) {
    ShowApplicationPicker(
        "Add a recently used application to the AlwaysFocus list.", AF_AddExe)
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

    AF_AddExe(lvRun.GetText(row, 1))
}

; The half of adding to the AlwaysFocus list that does not care where the name
; came from -- the live list, the recent-application picker, or a file browse.
AF_AddExe(exe) {
    global AlwaysFocusGui, AlwaysFocusList, EnableAlwaysFocus, AlwaysFocusExeListRaw
    if !IsSet(AlwaysFocusGui)
        return

    exe := StrLower(Trim(exe))
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

    ; The list above is LIVE, and this is the same list with a memory. Both are
    ; useful and neither replaces the other: the live one can offer a window that
    ; has no history yet, and this one can offer an application that was closed
    ; before the manager was opened -- which is the ordinary case, because
    ; somebody comes here after noticing a focus problem, not during one.
    btn := AlwaysFocusGui.AddButton("xs y+8 w240 h30", "Add Recent App…")
    btn.OnEvent("Click", AF_AddRecent)

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
    pid := 0
    LaunchInteractiveApp(
        A_WinDir "\System32\notepad.exe",
        QuoteWindowsCommandLineArg(LogPath),
        A_WinDir "\System32", "Normal", &pid, "SteamShell log")
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
        SteamShellMsgBox("SteamShell could not save the Control Panel settings.",
            "Iconx", "SteamShell Settings")
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
    ; Over a CLONE, because the body deletes from the map it is walking.
    ; AutoHotkey does not support modifying an object while it is being
    ; enumerated, and both of the other places this codebase prunes a map during
    ; a walk -- AssistCpuSamples in the companion, held in
    ; ReleaseControllerMouseButtons -- already clone for exactly this reason.
    ; This one did not.
    for feature, entry in TempDisables.Clone() {
    if (now >= entry["until"]) {
    SetFeatureState(feature, entry["prev"])
    if TempDisables.Has(feature)
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
    global SettingsGui, SettingsDialogActive
    SettingsEditorNormalizeWindow()
    dialogOptions := Trim(options)
    ; Not "SettingsGui if it exists": it may be hidden, and a dialog opened from
    ; a window Settings itself opened belongs above THAT window.
    ownerHwnd := SteamShellDialogOwnerHwnd()
    dialogOptions .= ownerHwnd ? " Owner" ownerHwnd : " 262144"
    result := "Cancel"
    SettingsDialogActive := true
    try {
        result := MsgBox(message, title, dialogOptions)
    } finally {
        SettingsDialogActive := false
    }
    if IsSet(SettingsGui) {
        SettingsEditorNormalizeWindow()
        try WinActivate("ahk_id " SettingsGui.Hwnd)
    }
    return result
}

SettingsEditorFileSelect(options, startDir, prompt, filter) {
    global SettingsGui, SettingsDialogActive
    settingsHwnd := 0
    if IsSet(SettingsGui) {
        settingsHwnd := SettingsGui.Hwnd
        try SettingsGui.Opt("+OwnDialogs -AlwaysOnTop")
        try WinSetAlwaysOnTop(0, "ahk_id " settingsHwnd)
    }
    selectedPath := ""
    SettingsDialogActive := true
    try {
        selectedPath := FileSelect(options, startDir, prompt, filter)
    } catch {
        selectedPath := ""
    } finally {
        SettingsDialogActive := false
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
; This product's state and content column, handed to the shared audit.
;
; contentLeft is 245 here and 286 in the companion, and the right edge is the
; content column's width where the companion's is its scrollbar. Two numbers, so
; two arguments -- the algorithm above them was identical.
SettingsEditorAuditLayout() {
    global SettingsEditorCategories, SettingsEditorCategoryControls
    global SettingsEditorControlPositions
    ; From the layout, not restated. This was 945 written out, which happened to
    ; be right and would silently stop being right the moment a column moved.
    layout := SettingsLayout()
    return SharedAuditSettingsLayout(
        SettingsEditorCategories, SettingsEditorCategoryControls,
        SettingsEditorControlPositions,
        245, layout["contentX"] + layout["contentWidth"])
}

SettingsEditorShowLayoutWarning(text) {
    global SettingsEditorStatusCtrl
    if IsObject(SettingsEditorStatusCtrl)
        SettingsEditorStatusCtrl.Text := text
}

SettingsEditorReportLayoutAudit() {
    return SharedReportSettingsLayoutAudit(
        SettingsEditorAuditLayout(), SettingsEditorShowLayoutWarning)
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

; Draws the shared definition of a category with this tree's builders.
;
; The rows come from SettingsCategoryRows in SteamShell-Shared.ahk; only the
; drawing is here. Unifying the drawing is the next step, and it is checkable
; precisely because the same table has to produce the same rows through it.
; Fills every registered field from the INI, after the pages are built.
;
; The builders used to read as they created each control, which is why the same
; setting was named twice on the way in -- once to build the row, once to read
; it -- and why a builder could not be shared with the companion, whose rows are
; filled by a loop. They create and register now; this fills.
;
; movedFrom is honoured for rows that carry it: schema migrations moved several
; settings between sections, and a read-only portable INI never gets migrated,
; so the old section still has to be consulted.
;
; mapped-choice and exe-list are NOT here, and cannot be. Both SHAPE the control
; from the stored value -- one adds a "Custom (x)" entry when the value matches
; no preset, the other builds a list item per entry -- so both are filled when
; they are built.
;
; That used to end "and are the two builders this product does not share", which
; conflated two different things and was half wrong within one pass. Shaping the
; control from the value is why they skip this loop; it was never why they could
; not be shared. The exe-list builder IS shared now: the CALLER reads the value
; and passes it in, each product with its own reader, and the builder does what
; the others do. mapped-choice stays here for a reason of its own -- one row uses
; it, and its key is a shell responsibility the companion's validator forbids by
; name -- which has nothing to do with when it reads.
; One field's control, loaded from the INI.
;
; Split out of the loop below so a single field can be refreshed on its own --
; see SettingsEditorSyncFieldControl.
SettingsEditorPopulateField(field) {
    if (field["type"] = "mapped-choice" || field["type"] = "exe-list")
        return
    if !field.Has("default")
        return
    ; movedFrom is NOT consulted here. It records where a setting used to
    ; live in the COMPANION -- schema 13 moved several out of [Cursor] --
    ; and this product has always kept them where they are now. Reading the
    ; companion's old section from the shell's INI would find nothing and
    ; return the default over a value the user had set.
    section := field["section"]
    ctrl := field["ctrl"]
    if (field["type"] = "bool")
        ctrl.Value := ReadBool(section, field["key"],
            ToBool(field["default"], false))
    else if (field["type"] = "choice")
        SettingsSelectChoiceByText(ctrl,
            IniReadS(section, field["key"], field["default"]),
            field["choices"])
    else if (field["type"] = "percent")
        ; STORED as a fraction, SHOWN as a percentage. The conversion existed in
        ; one direction only: SettingsEditorValidateField divides by 100 on save,
        ; and nothing multiplied by 100 on the way back in, so this branch used to
        ; fall through to the raw read below and put 0.3 into a field whose own
        ; validator demands 5 to 100.
        ;
        ; That made the window unsaveable on open and gave no way out that
        ; stuck: 0.3 failed validation, typing 30 saved correctly as 0.3, and the
        ; next open showed 0.3 again. Every Save the user attempted was blocked
        ; by a value the window itself had just put there.
        ;
        ; Rounded because 0.3 * 100 is 30.000000000000004 in binary floating
        ; point, and FormatSettingsFloat would faithfully render the tail.
        ctrl.Value := FormatSettingsFloat(
            Round(ToFloat(IniReadS(section, field["key"], field["default"]),
                ToFloat(field["default"], 0)) * 100, 4))
    else
        ctrl.Value := IniReadS(section, field["key"], field["default"])
    ; Sliders carry a separate value readout, and assigning .Value in code does
    ; NOT raise Change -- only the user dragging the track does. Cheap enough to
    ; run per field: it walks one entry per slider on screen.
    SettingsRefreshSliderReadouts()
}

SettingsEditorPopulateFields() {
    global SettingsEditorFields
    for _, field in SettingsEditorFields
        SettingsEditorPopulateField(field)
}

; Re-reads ONE field's control after that setting was changed somewhere else.
;
; The Quick Menu opens over the Settings window -- its chord is evaluated before
; the branch that hands input to Settings, deliberately, so the menu stays
; reachable from in there. Change a setting from the menu and the INI, the
; globals and the menu row all move; the Settings control behind it does not.
; SettingsEditorSave then writes EVERY field it holds, not only the edited ones,
; so pressing Save afterwards put the stale value straight back over the change
; the user had just made. The companion has had a guard for exactly this since
; it wrote its own Quick Menu; the shell never did.
;
; One field, not a full repopulate: the window may hold edits the user has not
; saved yet, and refreshing all of it would discard them.
;
; Read back from the INI rather than taking the value passed in, which also
; sidesteps the trap the companion had to write its way around -- these arrive
; as the words written to the file, and in AutoHotkey v2 the string "false" is a
; non-empty string and therefore true, so handing it to a checkbox ticks the box
; it was meant to clear. ReadBool already answers that question correctly.
SettingsEditorSyncFieldControl(section, key) {
    global SettingsGui, SettingsEditorFields
    if !IsSet(SettingsGui)
        return
    try {
        if !IsGuiVisible(SettingsGui)
            return
    } catch
        return
    for _, field in SettingsEditorFields {
        if (field["section"] = section && field["key"] = key) {
            try SettingsEditorPopulateField(field)
            return
        }
    }
}


; Per-tree seams required by SteamShell-Shared.ahk's row builders: what a Browse
; or Record button does. Both reach product-specific machinery -- this tree's
; file dialog and its own shortcut recorder, which DIVERGENT_FUNCTIONS.txt
; records as genuinely different from the companion's.
SettingsProductBrowsePath(field, prompt, filter, *) {
    SettingsEditorBrowsePath(field, prompt, filter)
}

SettingsProductRecordShortcut(field, *) {
    SettingsEditorRecordShortcut(field)
}

; Per-tree seam required by SteamShell-Shared.ahk: record a field the shared row
; builders just created, and make its controls follow their category.
SettingsRegisterBuiltField(category, field) {
    global SettingsEditorFields
    SettingsEditorFields.Push(field)
    for _, ctrl in field["controls"]
        SettingsProductTrackControl(category, ctrl)
}

; Per-tree seam: a control belongs to a category, and shows and hides with it.
SettingsProductTrackControl(category, ctrl) {
    SettingsEditorRegisterControl(category, ctrl)
}

; Per-tree seam: what this product calls "the settings changed".
SettingsProductMarkDirty(*) {
    SettingsEditorMarkDirty()
}

; Per-tree seams for the shared adapter: this product greys dependent rows from
; a switch, and has no in-page section heading.
SettingsProductWireDependency(ctrl, eventName) {
    ctrl.OnEvent(eventName, SettingsEditorRefreshDependencies)
}

SettingsProductAddSectionRow(guiObj, category, title, &y) {
    ; The shell has no section-break row; its pages are separated by category.
}

; Per-tree seams required by SteamShell-Shared.ahk's exe-list field. All three
; reach machinery this tree has and the companion answers differently: a file
; dialog that owns itself to the Settings window, a message box that does the
; same, and a status line that is a control here and a function there.
SettingsProductSelectExe(prompt, startDir) {
    return SettingsEditorFileSelect(1, startDir, prompt, "Programs (*.exe)")
}

SettingsProductFieldMessage(message) {
    SettingsEditorMsgBox(message, "Icon!")
}

SettingsProductSetStatus(text) {
    global SettingsEditorStatusCtrl
    if IsObject(SettingsEditorStatusCtrl)
        SettingsEditorStatusCtrl.Text := text
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


SettingsEditorAddMappedChoice(category, section, key, label, choices, values, &y, defaultValue := "") {
    global SettingsGui, SettingsEditorFields
    layout := SettingsLayout()
    labelCtrl := SettingsGui.AddText("x" layout["contentX"] " y" (y + 4) " w315 h24", label)
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

    ctrl := SettingsGui.AddDropDownList("x" layout["controlX"] " y" y " w320", displayChoices)
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

        SettingsUpdateScrollBar(offset, maxOffset)
    } finally {
        SettingsEditorSetRedraw(true)
        SettingsEditorRepaint()
    }
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
    if !SettingsWheelNotch(wParam, hwnd, SettingsGui.Hwnd, &notch)
        return
    if notch
        SettingsEditorScroll(notch)
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

; SettingsEditorControllerActive and SettingsEditorPrimaryActive are
; ControllerSettingsSurfaceActive and SettingsPrimaryActive in
; SteamShell-Shared.ahk now, defined once for both products. This tree's owner
; chain walk went with them, so the companion has it too.

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
    ; A row that declares its own step wins. Sliders carry one because their
    ; range is chosen for dragging, not for stepping: ControllerMouseSpeed spans
    ; 200..12000, and the hard-coded 5 that used to sit here -- correct when the
    ; setting was 1..300 pixels per tick -- would now need 2360 presses to cross
    ; it. Reading the step from the spec means the two cannot disagree again.
    if field.Has("step")
        step := field["step"]
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
    ; Assigning .Value does not raise Change, so a slider's readout would keep the
    ; number it had before the controller moved it.
    SettingsRefreshSliderReadouts()
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
    ; No fast modifier here: the triggers change Settings category, so RT is not
    ; free to mean "move faster" on this surface.
    ApplyControllerMouseMove(rx, ry, ControllerMouseSpeed)

    ; RB uses its configured short action inside Settings (Left Click by
    ; default), allowing the right-stick pointer to operate every control.
    if (pressed & 0x0200) {
        ExecuteControllerBinding("RB.Short")
        return true
    }
    return false
}

SettingsEditorHandleController(pressed, lx := 0, ly := 0, rx := 0, ry := 0, settingsCategoryDirection := 0) {
    global SettingsEditorDirty, SettingsEditorStatusCtrl, SettingsDialogActive
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

    if (SettingsDialogActive) {
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
        ; Through the shared reader, which the companion's save path also asks.
        ; Two copies of "what is in this ListView" would be two answers the day
        ; one of them learned something the other did not.
        value := SettingsExeListValue(ctrl, &problem)
        if (problem != "") {
            message := field["label"] " contains an invalid executable filename: " problem
            return false
        }
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
    pid := 0
    LaunchInteractiveApp(
        A_WinDir "\System32\notepad.exe",
        QuoteWindowsCommandLineArg(SettingsPath),
        A_WinDir "\System32", "Normal", &pid, "SteamShell settings file")
}

SettingsEditorOpenRtss(*) {
    field := SettingsEditorFindField("RTSS", "Path")
    path := IsObject(field) ? NormalizeMediaPath(field["ctrl"].Value) : ""
    if (path = "" || !FileExist(path)) {
        SettingsEditorMsgBox("Select a valid RTSS.exe path first.", "Icon!")
        return
    }
    SplitPath(path, , &directory)
    pid := 0
    LaunchInteractiveApp(path, "", directory, "Normal", &pid, "RTSS")
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
        ; Reset preferences without turning a verified installation back into
        ; first-run. Setup Assistant owns these deployment records.
        for _, setupKey in [
            "SetupState", "SetupVersion", "InstallationMode",
            "InstallDirectory", "DataDirectory"] {
            setupDefault := setupKey = "SetupState"
                ? "Complete" : (setupKey = "SetupVersion" ? "1" : "")
            setupValue := IniRead(
                SettingsPath, "Setup", setupKey,
                setupDefault)
            IniWrite(setupValue, workPath, "Setup", setupKey)
        }
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

AppendProcessIntegrityHealth(results, checkName, pid, expectedIntegrity := "Medium") {
    global ExpectedInteractiveUserSid, ExpectedInteractiveSessionId
    if !pid {
        HealthResult(results, "info", checkName, "Process is not running.")
        return
    }
    if !GetProcessTokenSecurity(
        pid, &sidText, &sessionId, &integrityName, &errorText) {
        HealthResult(results, "warn", checkName,
            "PID " pid "; token could not be inspected: " errorText)
        return
    }
    identityMatches := ExpectedInteractiveUserSid != ""
        && StrLower(sidText) = StrLower(ExpectedInteractiveUserSid)
        && sessionId = ExpectedInteractiveSessionId
    integrityMatches := StrLower(integrityName) = StrLower(expectedIntegrity)
    HealthResult(results,
        identityMatches && integrityMatches ? "pass" : "warn",
        checkName,
        "PID " pid "; " integrityName " integrity; session " sessionId
        . (identityMatches ? "; interactive user matches."
            : "; interactive user or session does not match."))
}

; Seam for SteamShell-Shared.ahk: this tree's own checks. The harness around them
; -- the window, the list, the report text, Copy and Refresh -- is shared.
ProductHealthResults() {
    global ControllerBackend, RawInputLastReportTick, ActiveControllerIndex
    global SteamPath, SettingsPath, CurrentSettingsSchemaVersion
    global ShellRegKey, SteamShellInstalledExe, SteamShellVersion
    global SteamShellDataDir, SteamShellInstallationMode
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
    global EnableElevatedInputHelper, DesktopMode
    global ElevatedHelperAvailable, ElevatedHelperPid, ElevatedHelperLastError
    global ElevatedHelperPath
    global StandardLaunchLastRoute, StandardLaunchLastError
    global StandardLaunchSuccessCount, StandardLaunchFailureCount
    global StandardLaunchTrackedProcesses
    global ExpectedInteractiveUserSid, ExpectedInteractiveSessionId

    results := []
    ; A_ScriptDir rather than SteamShellInstallDir: the question is where this
    ; executable is running from, not where the record says it was put.
    AddInstallationRecordHealthRow(
        results, A_ScriptDir, SteamShellDataDir, SteamShellInstallationMode)
    HealthResult(results, "info", "Session state", SessionState)
    HealthResult(results, "info", "Presentation mode",
        DesktopMode
            ? "Desktop mode: Explorer owns the desktop and SteamShell is resident for the notification area, controller mouse, and Quick Menu."
            : (SafeMode
                ? "Safe Mode: shell enforcement and automation are disabled for this session."
                : "Shell mode: SteamShell owns presentation and the taskbar is guarded."))
    HealthResult(results, A_IsAdmin ? "warn" : "pass", "Main shell privileges",
        A_IsAdmin
            ? "SteamShell.exe is elevated; Quick Menu focus isolation from Steam may not work correctly. Launch it normally."
            : "SteamShell.exe is running at normal integrity as designed.")
    helperVerificationError := ""
    helperRunning := ElevatedHelperAvailable && ElevatedHelperPid
        && VerifyElevatedHelperProcess(ElevatedHelperPid, &helperVerificationError)
    if (ElevatedHelperAvailable && !helperRunning)
        ElevatedHelperLastError :=
            "Runtime verification failed: " helperVerificationError
    helperStatus := !EnableElevatedInputHelper ? "info" : (helperRunning ? "pass" : "warn")
    helperDetail := !EnableElevatedInputHelper
        ? "Disabled in Settings; elevated windows will not receive mapped controller input or automatic geometry."
        : (helperRunning
            ? "SteamShell-Helper.exe is running as PID " ElevatedHelperPid
                . "; input activates only for High/System foreground windows, and geometry follows Shell mode."
            : ElevatedHelperLastError)
    HealthResult(results, helperStatus, "Elevated helper", helperDetail)
    ; Reported separately from "is it running" because this is the property that
    ; makes elevating it safe at all, and it is the one a hand-moved or
    ; pre-1.9.9.2 installation silently loses.
    helperBinaryPath := ElevatedHelperPath != ""
        ? ElevatedHelperPath : GetElevatedHelperPath()
    if !EnableElevatedInputHelper {
        HealthResult(results, "info", "Elevated helper protection",
            "Not evaluated because the helper is disabled in Settings.")
    } else if !FileExist(helperBinaryPath) {
        HealthResult(results, "warn", "Elevated helper protection",
            "The helper is not installed yet: " helperBinaryPath)
    } else if ElevatedHelperLocationIsProtected(
        helperBinaryPath, &helperProtectionDetail) {
        HealthResult(results, "pass", "Elevated helper protection",
            "The helper and its directory have trusted owners, and only SYSTEM and Administrators can write " helperBinaryPath ".")
    } else {
        HealthResult(results, "fail", "Elevated helper protection",
            helperProtectionDetail
            . " SteamShell refuses to elevate it. Run SteamShell as administrator and apply Setup again.")
    }
    if !A_IsAdmin {
        standardCapabilityStatus := "pass"
        standardCapabilityDetail :=
            "SteamShell itself is standard integrity; child applications launch directly."
    } else if GetLinkedStandardUserToken(&healthToken, &standardCapabilityDetail) {
        DllCall("Kernel32\CloseHandle", "Ptr", healthToken, "Int")
        standardCapabilityStatus := "pass"
        standardCapabilityDetail :=
            "A linked standard-user token matches the recorded interactive user and session."
    } else {
        standardCapabilityStatus := "warn"
    }
    HealthResult(results, standardCapabilityStatus,
        "Standard-user launch capability", standardCapabilityDetail)
    launchDetail := StandardLaunchSuccessCount " successful; "
        . StandardLaunchFailureCount " failed; last route: " StandardLaunchLastRoute "."
    if (StandardLaunchLastError != "")
        launchDetail .= " Last warning: " StandardLaunchLastError
    HealthResult(results,
        StandardLaunchFailureCount = 0 && StandardLaunchLastError = ""
            ? "pass" : "warn",
        "External application launches", launchDetail)
    steamExe := NormalizeMediaPath(SteamPath)
    HealthResult(results, FileExist(steamExe) ? "pass" : "fail", "Steam executable",
        FileExist(steamExe) ? steamExe : "Not found: " steamExe)
    AppendProcessIntegrityHealth(
        results, "Steam process integrity", ProcessExist("steam.exe"))

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
    setupState := IniReadS("Setup", "SetupState", "Pending")
    HealthResult(results,
        StrLower(setupState) = "complete" ? "pass" : "warn",
        "Setup state",
        setupState "; mode " SteamShellInstallationMode
        . "; data " SteamShellDataDir)

    currentShell := ""
    try currentShell := RegRead(ShellRegKey, "Shell")
    shellLower := StrLower(Trim(currentShell))
    shellStatus := InStr(shellLower, "steamshell") || shellLower = "explorer.exe" ? "pass" : "warn"
    HealthResult(results, shellStatus, "Windows shell registration",
        currentShell = "" ? "No per-user shell value was found." : currentShell)

    if (StrLower(A_ScriptFullPath) = StrLower(SteamShellInstalledExe))
        installDetail := "Running from the " SteamShellInstallationMode
            . " installation; writable data is " SteamShellDataDir "."
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
    explorerPid := 0
    if taskbarHwnd
        DllCall("User32\GetWindowThreadProcessId", "Ptr", taskbarHwnd,
            "UInt*", &explorerPid, "UInt")
    AppendProcessIntegrityHealth(results, "Explorer shell integrity", explorerPid)
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

    startupEnabled := ReadBool("StartupPrograms", "Enable", true)
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
        rtssMissing := ResolveRtssExecutablePath() = ""
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
    AppendProcessIntegrityHealth(
        results, "RTSS process integrity", ProcessExist("RTSS.exe"))

    trackedRunning := 0
    trackedElevated := []
    for trackedPid, trackedLaunch in StandardLaunchTrackedProcesses {
        if !ProcessExist(trackedPid)
            continue
        runningPath := ""
        try runningPath := ProcessGetPath(trackedPid)
        if (runningPath != "" && trackedLaunch["target"] != ""
            && StrLower(runningPath) != StrLower(trackedLaunch["target"]))
            continue
        trackedRunning += 1
        if GetProcessTokenSecurity(
            trackedPid, &trackedSid, &trackedSession, &trackedIntegrity, &trackedError) {
            if (StrLower(trackedIntegrity) != "medium"
                || StrLower(trackedSid) != StrLower(ExpectedInteractiveUserSid)
                || trackedSession != ExpectedInteractiveSessionId)
                trackedElevated.Push(
                    trackedLaunch["purpose"] " (" trackedIntegrity
                    ", session " trackedSession ")")
        } else
            trackedElevated.Push(
                trackedLaunch["purpose"] " (inspection failed: " trackedError ")")
    }
    HealthResult(results, trackedElevated.Length ? "warn" : "pass",
        "Tracked external processes",
        trackedRunning " tracked process(es) still running"
        . (trackedElevated.Length
            ? "; unexpected integrity: " JoinWith(trackedElevated, ", ")
            : "; none are known to be elevated."))

    state := Buffer(16, 0)
    ; Asked through the backend, not through XInput. Reporting "no controller
    ; detected" to somebody whose pad is working over RawInput would be wrong
    ; for exactly the user RawInput exists to serve -- and it is the first place
    ; they would look.
    ;
    ; Detection stays HERE because ControllerReadState is the one part that
    ; still differs per product: the companion tries a GameInput backend this
    ; one does not offer, for the reason the Backend setting's own note gives.
    ; The four rows it feeds -- Controller, Input backend, RawInput and
    ; Controller mappings -- are the same in both products and are built in
    ; SteamShell-Shared.ahk.
    ;
    ; The backend named there is the one that ANSWERED, recorded by
    ; SetActiveBackend. This tree used to infer it from "is RawInput registered
    ; and has it ever reported", which is a different question and answered
    ; RawInput for a pad XInput was reading.
    SharedControllerHealthRows(results, ControllerReadState(&state))

    rawLauncherCount := SettingsParseExeList(LauncherCleanupLauncherExeListRaw).Length
    rawBackgroundCount := SettingsParseExeList(LauncherCleanupBackgroundExeListRaw).Length
    rawExcludeCount := SettingsParseExeList(LauncherCleanupExcludeExeListRaw).Length
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

ExportDiagnosticBundle(*) {
    global HealthCheckResults, SettingsPath, LogPath, SteamShellVersion, ShellRegKey
    global ControllerBackend, ActiveControllerIndex
    global RawInputProbeActive, RawInputDevice, RawInputLastReportTick
    global HealthCheckGui, SettingsEditorStatusCtrl
    stamp := FormatTime(A_Now, "yyyyMMdd-HHmmss")
    tempDir := A_Temp "\SteamShell-Diagnostics-" stamp
    zipPath := A_Desktop "\SteamShell-Diagnostics-" stamp ".zip"
    results := ProductHealthResults()
    HealthCheckResults := results

    currentShell := ""
    try currentShell := RegRead(ShellRegKey, "Shell")
        ; Display and input state, which this bundle did not carry and the
        ; companion's always has.
        ;
        ; The asymmetry was backwards: this is the product that replaces the
        ; Windows shell, so an input failure here is a machine the user cannot
        ; drive, and the bundle collected for exactly that situation said nothing
        ; about the input stack. It now answers the first three questions anyone
        ; would ask after a post-resume failure -- which backend was live, which
        ; slot answered, and whether RawInput was still registered.
        displayScale := GetPrimaryDisplayScale()
        displayScaleText := IsObject(displayScale)
            ? displayScale["percent"] "%"
            : "unavailable"
        hdr := GetPrimaryHdrState()
        hdrText := !IsObject(hdr)
            ? "unavailable"
            : (!hdr["supported"] ? "unsupported" : (hdr["enabled"] ? "on" : "off"))
        rawInputAge := RawInputLastReportTick
            ? (A_TickCount - RawInputLastReportTick) "ms ago"
            : "never"
        systemInfo := "SteamShellVersion=" SteamShellVersion "`r`n"
            . "Generated=" NowStamp() "`r`n"
            . "OSVersion=" A_OSVersion "`r`n"
            . "Is64BitOS=" (A_Is64bitOS ? "true" : "false") "`r`n"
            . "Compiled=" (A_IsCompiled ? "true" : "false") "`r`n"
            . "Elevated=" (A_IsAdmin ? "true" : "false") "`r`n"
            . "Screen=" A_ScreenWidth "x" A_ScreenHeight "`r`n"
            . "ScreenDPI=" A_ScreenDPI " (" Round(A_ScreenDPI / 96.0 * 100) "%)`r`n"
            . "PrimaryDisplayScale=" displayScaleText "`r`n"
            . "PrimaryDisplayHDR=" hdrText "`r`n"
            . "BackendSetting=" ControllerBackend "`r`n"
            . "XInputSlot=" ActiveControllerIndex "`r`n"
            . "RawInputRegistered=" (RawInputProbeActive ? "true" : "false") "`r`n"
            . "RawInputDevice=0x" Format("{:X}", RawInputDevice) "`r`n"
            . "RawInputLastReport=" rawInputAge "`r`n"
            . "ScriptPath=" A_ScriptFullPath "`r`n"
            . "CurrentShell=" currentShell "`r`n"

    files := Map()
    files["HealthCheck.txt"] := FormatHealthReport(results)
    files["SystemInfo.txt"] := systemInfo
    if FileExist(SettingsPath)
        files["SteamShellSettings-sanitized.ini"] := FileRead(SettingsPath)
    if FileExist(LogPath)
        files["SteamShell-log-tail.txt"] := GetLastLines(FileRead(LogPath), 2000)

    failureReason := ""
    zipPath := ExportDiagnosticArchive("SteamShell", files, &failureReason)
    if (zipPath = "") {
        if IsSet(HealthCheckGui) && IsGuiVisible(HealthCheckGui) {
            try MsgBox(
                "The diagnostic bundle could not be exported.`n`n" failureReason,
                "SteamShell Health Check", "Owner" HealthCheckGui.Hwnd " Iconx")
        } else {
            SettingsEditorMsgBox(
                "The diagnostic bundle could not be exported.`n`n" failureReason, "Iconx")
        }
        return
    }
    if IsSet(HealthCheckGui)
        try HealthCheckGui["HealthSummary"].Text := "Diagnostic bundle exported to " zipPath
    if IsObject(SettingsEditorStatusCtrl)
        try SettingsEditorStatusCtrl.Text := "Diagnostic bundle exported to " zipPath
    explorerPid := 0
    LaunchInteractiveApp(
        A_WinDir "\explorer.exe",
        '/select,' QuoteWindowsCommandLineArg(zipPath),
        A_WinDir, "Normal", &explorerPid, "Diagnostic bundle location")
}

; The window a dialog must sit above, or 0 when none is showing.
;
; Almost every SteamShell window is +AlwaysOnTop, because this is a kiosk shell
; that has to stay in front of Steam and games. The consequence is that an
; unowned MsgBox opens BEHIND whichever of them is up, and the user is left with
; a frozen window and nothing to click -- there is no taskbar to find the dialog
; on either. An owned window is always drawn above its owner, so ownership is the
; fix; this is the one place that decides who the owner is.
;
; Ordered innermost first: a dialog raised from the Controller Test belongs above
; the Controller Test, not above the Settings window behind it.
SteamShellDialogOwnerHwnd() {
    global ScriptPid
    ; The window the dialog must appear above is the one the user is looking at,
    ; which is the active window. Asking that directly beats an ordered list of
    ; every window in the application, which cannot express "innermost" any
    ; better and has to be maintained forever.
    ;
    ; Returning 0 when the active window is not ours is deliberate: a dialog
    ; owned by a SteamShell window that is itself behind a fullscreen game would
    ; be behind the game too. The caller adds MB_TOPMOST instead.
    ;
    ; The splash, splash overlay, and desktop backdrop cannot be selected here
    ; because all three are WS_EX_NOACTIVATE and never become active.
    activeHwnd := 0
    try activeHwnd := WinGetID("A")
    if !activeHwnd
        return 0
    try {
        if (WinGetPID("ahk_id " activeHwnd) = ScriptPid)
            return activeHwnd
    }
    return 0
}

; The default MsgBox for this application.
;
; Owns the dialog to whatever is on top, and when nothing is showing adds
; MB_TOPMOST (262144) instead -- SteamShell hides the taskbar, so a message with
; neither an owner nor topmost can end up behind a fullscreen game with no way
; to reach it.
SteamShellMsgBox(message, options := "OK", title := "SteamShell") {
    global SettingsDialogActive
    dialogOptions := Trim(options)
    ownerHwnd := SteamShellDialogOwnerHwnd()
    dialogOptions .= ownerHwnd ? " Owner" ownerHwnd : " 262144"
    SettingsDialogActive := true
    try return MsgBox(message, title, dialogOptions)
    finally {
        SettingsDialogActive := false
        if ownerHwnd
            try WinActivate("ahk_id " ownerHwnd)
    }
}

SetupAssistantMsgBox(message, options := "OK", title := "SteamShell Setup") {
    global SetupAssistantGui, SettingsGui, SettingsDialogActive
    dialogOptions := Trim(options)
    ownerHwnd := SteamShellDialogOwnerHwnd()
    if ownerHwnd
        dialogOptions .= " Owner" ownerHwnd
    else
        dialogOptions .= " 262144"
    SettingsDialogActive := true
    try return MsgBox(message, title, dialogOptions)
    finally {
        SettingsDialogActive := false
        if ownerHwnd
            try WinActivate("ahk_id " ownerHwnd)
    }
}

SetupAssistantProgramFilesX86() {
    programFilesX86 := EnvGet("ProgramFiles(x86)")
    return programFilesX86 != "" ? programFilesX86 : A_ProgramFiles
}

SetupAssistantFirstExistingExecutable(candidates, expectedName) {
    seen := Map()
    for _, candidate in candidates {
        candidate := NormalizeMediaPath(candidate)
        if (candidate = "" || seen.Has(StrLower(candidate)))
            continue
        seen[StrLower(candidate)] := true
        if FileExist(candidate)
            && StrLower(SplitPathName(candidate)) = StrLower(expectedName)
            return candidate
    }
    return ""
}

SetupAssistantDiscoverSteamPath() {
    global SteamPath
    candidates := [
        SteamPath,
        SetupAssistantProgramFilesX86() "\Steam\steam.exe",
        A_ProgramFiles "\Steam\steam.exe"]
    for _, registrySpec in [
        ["HKEY_CURRENT_USER\Software\Valve\Steam", "SteamExe"],
        ["HKEY_CURRENT_USER\Software\Valve\Steam", "SteamPath"],
        ["HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath"],
        ["HKEY_LOCAL_MACHINE\SOFTWARE\Valve\Steam", "InstallPath"]] {
        registryValue := ""
        try registryValue := RegRead(registrySpec[1], registrySpec[2])
        if (registryValue = "")
            continue
        registryValue := StrReplace(registryValue, "/", "\")
        candidates.Push(
            RegExMatch(registryValue, "i)\\steam\.exe$")
                ? registryValue : RTrim(registryValue, "\") "\steam.exe")
    }
    return SetupAssistantFirstExistingExecutable(candidates, "steam.exe")
}

SetupAssistantDiscoverRtssPath() {
    global RtssPath
    return SetupAssistantFirstExistingExecutable([
        RtssPath,
        SetupAssistantProgramFilesX86()
            "\RivaTuner Statistics Server\RTSS.exe",
        A_ProgramFiles "\RivaTuner Statistics Server\RTSS.exe"], "rtss.exe")
}

SetupAssistantRefreshApplicationPaths() {
    global SetupAssistantGui, SteamPath, RtssPath
    if !IsSet(SetupAssistantGui)
        return
    steamDisplay := FileExist(SteamPath) ? SteamPath : "Not found — select Steam.exe"
    rtssDisplay := FileExist(RtssPath) ? RtssPath : "Not found — RTSS is optional"
    try SetupAssistantGui["SetupSteamPath"].Text := steamDisplay
    try SetupAssistantGui["SetupRtssPath"].Text := rtssDisplay
}

SetupAssistantDetectInstalledApplications() {
    global SteamPath, RtssPath
    changes := []
    detectedSteam := SetupAssistantDiscoverSteamPath()
    if (detectedSteam != "" && StrLower(detectedSteam) != StrLower(SteamPath)) {
        SteamPath := detectedSteam
        changes.Push(Map(
            "section", "Paths", "key", "SteamPath", "value", detectedSteam))
    }
    detectedRtss := SetupAssistantDiscoverRtssPath()
    if (detectedRtss != "" && StrLower(detectedRtss) != StrLower(RtssPath)) {
        RtssPath := detectedRtss
        changes.Push(Map(
            "section", "RTSS", "key", "Path", "value", detectedRtss))
    }
    if changes.Length
        CommitIniChanges(changes)
    SetupAssistantRefreshApplicationPaths()
}

SetupAssistantRestoreAfterExternal(*) {
    global SetupAssistantGui, SetupAssistantExternalPid
    global SetupAssistantExternalStartedTick
    if !IsSet(SetupAssistantGui) {
        SetTimer(SetupAssistantRestoreAfterExternal, 0)
        return
    }
    if (A_TickCount - SetupAssistantExternalStartedTick < 1500)
        return
    if SetupAssistantExternalPid && ProcessExist(SetupAssistantExternalPid)
        return
    SetTimer(SetupAssistantRestoreAfterExternal, 0)
    SetupAssistantExternalPid := 0
    try SetupAssistantGui.Opt("+AlwaysOnTop")
    try WinRestore("ahk_id " SetupAssistantGui.Hwnd)
    try WinActivate("ahk_id " SetupAssistantGui.Hwnd)
}

SetupAssistantLaunchExternal(target, arguments, directory, purpose) {
    global SetupAssistantGui, SetupAssistantExternalPid
    global SetupAssistantExternalStartedTick
    if IsSet(SetupAssistantGui) {
        try SetupAssistantGui.Opt("-AlwaysOnTop")
        try WinSetAlwaysOnTop(0, "ahk_id " SetupAssistantGui.Hwnd)
        try WinMinimize("ahk_id " SetupAssistantGui.Hwnd)
    }
    launchedPid := 0
    if !LaunchInteractiveApp(
        target, arguments, directory, "Normal", &launchedPid, purpose) {
        SetupAssistantExternalPid := 0
        SetupAssistantExternalStartedTick := 0
        SetupAssistantRestoreAfterExternal()
        return false
    }
    SetupAssistantExternalPid := launchedPid
    SetupAssistantExternalStartedTick := A_TickCount
    SetTimer(SetupAssistantRestoreAfterExternal, 300)
    return true
}

SetupAssistantSetStatus(message) {
    global SetupAssistantGui
    if !IsSet(SetupAssistantGui)
        return
    try SetupAssistantGui["SetupStatus"].Text := message
}

SetupAssistantSelectExecutable(prompt, currentPath := "") {
    global SetupAssistantGui, SettingsGui, SettingsDialogActive
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
    SettingsDialogActive := true
    startDirectory := SetupAssistantProgramFilesX86()
    if (currentPath != "") {
        candidateDirectory := ""
        try SplitPath(currentPath, , &candidateDirectory)
        if DirExist(candidateDirectory)
            startDirectory := candidateDirectory
    }
    try selectedPath := FileSelect(1, startDirectory, prompt, "Programs (*.exe)")
    catch {
        selectedPath := ""
    } finally {
        SettingsDialogActive := false
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
    selectedPath := SetupAssistantSelectExecutable("Select Steam.exe", SteamPath)
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
        SetupAssistantRefreshApplicationPaths()
        SetupAssistantSetStatus("Steam path saved: " selectedPath)
    }
}

SetupAssistantChooseRtss(*) {
    global RtssPath
    selectedPath := SetupAssistantSelectExecutable("Select RTSS.exe", RtssPath)
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
        SetupAssistantRefreshApplicationPaths()
        SetupAssistantSetStatus("RTSS path saved. Configure matching shortcuts if DLL integration is unavailable.")
    }
}

SplitPathName(path) {
    fileName := ""
    try SplitPath(path, &fileName)
    return fileName
}

SetupAssistantSelectDirectory(prompt, initialDirectory := "") {
    global SetupAssistantGui, SettingsDialogActive
    if !IsSet(SetupAssistantGui)
        return ""
    if (initialDirectory = "" || !DirExist(initialDirectory))
        initialDirectory := A_ProgramFiles
    selectedDirectory := ""
    SettingsDialogActive := true
    try {
        ; +OwnDialogs is per-thread in AutoHotkey, so it has to be set again
        ; here rather than relying on the one applied when the GUI was created.
        SetupAssistantGui.Opt("+OwnDialogs -AlwaysOnTop")
        WinSetAlwaysOnTop(0, "ahk_id " SetupAssistantGui.Hwnd)
        selectedDirectory := FileSelect("D", initialDirectory, prompt)
    } catch {
        selectedDirectory := ""
    } finally {
        SettingsDialogActive := false
        try SetupAssistantGui.Opt("+AlwaysOnTop")
        try WinSetAlwaysOnTop(1, "ahk_id " SetupAssistantGui.Hwnd)
        try WinActivate("ahk_id " SetupAssistantGui.Hwnd)
    }
    return selectedDirectory
}

SetupAssistantBrowseInstall(*) {
    global SetupAssistantGui
    currentDirectory := ""
    try currentDirectory := Trim(SetupAssistantGui["SetupInstallPath"].Text)
    selectedDirectory := SetupAssistantSelectDirectory(
        "Choose the folder that will contain SteamShell.exe", currentDirectory)
    if (selectedDirectory = "")
        return
    SetupAssistantGui["SetupInstallPath"].Text := selectedDirectory
    SetupAssistantGui["SetupBrowse"].Value := 1
    SetupAssistantRefreshDeployment()
}

; The XFE logon task, queried rather than inferred from the registry record.
;
; The task is the thing that actually makes XFE start, so it is the honest
; answer to "is XFE installed here" even when the HKCU record was lost, written
; by a different profile, or never made it (a failed registration still leaves a
; working manual installation behind).
SteamShellXfeLogonTaskExists(name := "") {
    ; Defaults to the current name so existing detection callers are unchanged;
    ; RemoveXfeLogonTask passes the legacy name too, to confirm its own work.
    if (Trim(name) = "")
        name := XfeLogonTaskName()
    taskCommand := QuoteWindowsCommandLineArg(A_WinDir "\System32\schtasks.exe")
        . " /query /tn " QuoteWindowsCommandLineArg(name)
    try return RunWait(taskCommand, A_WinDir, "Hide") = 0
    return false
}

; True when SteamShell is the shell Winlogon will actually start. Read from
; Winlogon rather than from SteamShell's own record, for the same reason: the
; registry value is the thing with the effect.
SteamShellIsRegisteredWindowsShell() {
    global ShellRegKey
    configured := ""
    try configured := RegRead(ShellRegKey, "Shell")
    return InStr(StrLower(configured), "steamshell") > 0
}

; Where the installed shell actually lives, from whichever record still exists.
;
; InstalledPath is written only for MANAGED installs -- a portable copy is
; deliberately self-describing through its sidecar and must not overwrite a
; managed installation's record -- so a portable installation registered as the
; shell has no InstalledPath at all. Detection recognised it as Standalone, since
; registration says so, and then had nowhere to point: Setup Assistant could not
; preselect the folder it was being asked to upgrade.
;
; RegisteredPath is the record that covers it. It is written whenever the shell
; is registered, portable or not, because it is written inside the "if
; registerShell" branch rather than the "if !portableMode" one. The Winlogon
; value itself is the last resort, and the most authoritative of the three: it is
; what Windows will actually launch.
; Whether the installed shell is a portable copy.
;
; Inferred from the absence of InstalledPath rather than from InstallationMode,
; because InstallationMode is written by the same "if !portableMode" branch that
; writes InstalledPath -- a portable installation records neither. What it does
; record, when it is the registered shell, is RegisteredPath. So "registered but
; no InstalledPath" is exactly the shape of a portable installation, and it is
; the shape the deploy code guarantees rather than one inferred from a name.
InstalledShellIsPortable() {
    global SteamShellRegKey
    recorded := ""
    try recorded := RegRead(SteamShellRegKey, "InstalledPath")
    if (Trim(recorded) != "")
        return false
    registered := ""
    try registered := RegRead(SteamShellRegKey, "RegisteredPath")
    return Trim(registered) != "" || SteamShellIsRegisteredWindowsShell()
}

ResolveInstalledShellExecutable() {
    global SteamShellRegKey, ShellRegKey
    candidates := []
    recorded := ""
    try recorded := RegRead(SteamShellRegKey, "InstalledPath")
    candidates.Push(Trim(recorded))
    registered := ""
    try registered := RegRead(SteamShellRegKey, "RegisteredPath")
    candidates.Push(Trim(registered))
    configured := ""
    try configured := RegRead(ShellRegKey, "Shell")
    ; Stored as a quoted command, so it needs the same parsing a saved previous
    ; shell gets rather than being treated as a bare path.
    candidates.Push(ShellCommandExecutablePath(configured))
    for _, candidate in candidates {
        if (candidate != "" && FileExist(candidate) != "")
            return candidate
    }
    return ""
}

; What is already on this PC, so Setup can open on the answer instead of the
; default. Detection is deliberately evidence-first -- the Winlogon value and the
; scheduled task -- and resolves the install directory from whichever record
; survives, which for a portable install is not InstalledPath.
DetectExistingSteamShellInstallation(&product, &directory, &registeredAsShell, &xfeStartsAtLogon) {
    global SteamShellRegKey
    product := ""
    directory := ""
    registeredAsShell := SteamShellIsRegisteredWindowsShell()
    xfeStartsAtLogon := SteamShellXfeLogonTaskExists()

    xfePath := GetXfeInstalledPath()

    ; INSTALLED means REGISTERED TO START, not "a file is present".
    ;
    ; Both uninstalls deliberately leave the executable and its settings on disk
    ; -- they say so to the user in as many words -- so file presence outlives
    ; the installation it was standing in for. Testing it made an uninstalled
    ; product report itself installed for the rest of the machine's life, and
    ; because XFE is checked first, it did so over a shell installation that was
    ; genuinely there.
    ;
    ; What does not outlive an uninstall is the registration: the logon task and
    ; its flag for XFE, the Winlogon shell value and RegisteredPath for the
    ; shell. Those are removed by the code that removes the installation, which
    ; is what makes them the honest question to ask.
    xfeRegisteredFlag := false
    try xfeRegisteredFlag := ToBool(
        RegRead(SteamShellRegKey, "XfeLogonTaskRegistered", "false"), false)
    shellRegisteredPath := ""
    try shellRegisteredPath := RegRead(SteamShellRegKey, "RegisteredPath")

    ; XFE is the more specific claim and is still tested first, but now on
    ; evidence that an uninstall actually clears.
    if (xfeStartsAtLogon || xfeRegisteredFlag) {
        product := "XFE"
        if (xfePath != "" && FileExist(xfePath) != "")
            SplitPath(xfePath, , &directory)
        return true
    }
    if (registeredAsShell || Trim(shellRegisteredPath) != "") {
        product := "Standalone"
        installedExe := ResolveInstalledShellExecutable()
        if (installedExe != "")
            SplitPath(installedExe, , &directory)
        return true
    }
    return false
}

; Opens Setup on what is already installed rather than on the defaults, so an
; upgrade does not depend on the user reproducing choices they made months ago.
; Everything remains editable; this only changes where the dialog starts.
SetupAssistantPreselectExistingInstallation() {
    global SetupAssistantGui
    if !IsSet(SetupAssistantGui)
        return false
    if !DetectExistingSteamShellInstallation(
        &product, &directory, &registeredAsShell, &xfeStartsAtLogon)
        return false

    isXfe := SteamShellProductIsXfe(product)
    try SetupAssistantGui["SetupProductStandalone"].Value := isXfe ? 0 : 1
    try SetupAssistantGui["SetupProductXfe"].Value := isXfe ? 1 : 0
    SetupAssistantRefreshProductMode()

    ; Braced deliberately: AutoHotkey v2 cannot parse a bare "try" as an if-body
    ; when an else follows it.
    if isXfe {
        try SetupAssistantGui["SetupRegisterXfeStartup"].Value := xfeStartsAtLogon ? 1 : 0
    } else {
        try SetupAssistantGui["SetupRegisterShell"].Value := registeredAsShell ? 1 : 0
    }

    if (directory != "") {
        standardDirectory := isXfe
            ? SetupAssistantXfeStandardDirectory()
            : A_ProgramFiles "\SteamShell"
        if (StrLower(RTrim(directory, "\/")) = StrLower(RTrim(standardDirectory, "\/"))) {
            try SetupAssistantGui["SetupStandard"].Value := 1
        } else if (StrLower(RTrim(directory, "\/")) = StrLower(RTrim(A_ScriptDir, "\/"))) {
            try SetupAssistantGui["SetupCurrent"].Value := 1
        } else {
            try SetupAssistantGui["SetupBrowse"].Value := 1
            try SetupAssistantGui["SetupInstallPath"].Text := directory
        }
    }
    ; Restored, not left at its default. Without this an upgrade of a portable
    ; installation came back as "Custom": the browse radio was selected and this
    ; box was clear, and SetupAssistantGetDeployment reads exactly those two
    ; things. Applying would then have demanded administrator approval and moved
    ; the data into ProgramData -- converting a portable install into a managed
    ; one because a checkbox was never ticked back.
    if (!isXfe && InstalledShellIsPortable())
        try SetupAssistantGui["SetupPortable"].Value := 1

    SetupAssistantRefreshDeployment()

    detail := isXfe
        ? "Existing SteamShell-XFE installation detected"
            . (directory != "" ? " at " directory : "")
            . (xfeStartsAtLogon ? " with a sign-in logon task." : " (no logon task).")
        : "Existing SteamShell installation detected"
            . (directory != "" ? " at " directory : "")
            . (registeredAsShell
                ? " and it is the registered Windows shell."
                : " (not currently the registered Windows shell).")
    SetupAssistantSetStatus(detail " Apply upgrades it; every option below can still be changed.")
    return true
}

; ==============================================================================
; OPTIONAL FILE REMOVAL
; ==============================================================================
; Setup records where everything went, so finding the files is not the problem.
; The problem is that an install DIRECTORY is not necessarily ours. A portable
; EXE dropped into a folder of other tools, a "use current location" install, a
; browsed directory the user already had -- deleting any of those wholesale
; destroys files that have nothing to do with SteamShell.
;
; So the rule is: remove a directory only when SteamShell chose the path itself
; and created it. Everywhere else, remove only the exact files this installer
; wrote and leave the directory alone. That is why the plan below is a list the
; user can read before agreeing to it, rather than a folder path and a promise.

; The registry record is a claim, not proof. It is written by whichever copy ran
; Setup, it survives a manual delete, and a freshly downloaded EXE inherits it
; wholesale. Before removing a directory, confirm it still contains something
; SteamShell actually put there -- a folder that no longer holds any of these is
; no longer demonstrably ours, whatever HKCU says about it.
SteamShellDirectoryContainsOurArtifacts(path) {
    static MARKERS := [
        "SteamShell.exe",
        "SteamShell-XFE.exe",
        "SteamShellSettings.ini",
        "SteamShell-XFE.ini",
        "SteamShell-XFE-Controllers.ini",
        "bin\SteamShell-Helper.exe",
        "components\bin\SteamShell-Helper.exe",
        "SteamShell\SteamShellSettings.ini",
        "SteamShell-Helper.exe",
        "SteamShell\bin\SteamShell-Helper.exe",
        "logs\SteamShell.log",
        "logs\SteamShell-Helper.log"]
    path := RTrim(Trim(path), "\/")
    if (path = "")
        return false
    for _, marker in MARKERS {
        if FileExist(path "\" marker)
            return true
    }
    ; A data directory that has been emptied of logs still counts when it holds
    ; the backup folder Setup creates, which nothing else would put there.
    return DirExist(path "\backups") && FileExist(path "\backups\*.bak")
}

; Independent evidence of where the shell installation is: the Winlogon value is
; the path Windows will actually run, so it does not depend on SteamShell's own
; bookkeeping being intact.
SteamShellRegisteredShellDirectory() {
    global ShellRegKey
    configured := ""
    try configured := RegRead(ShellRegKey, "Shell")
    if !InStr(StrLower(configured), "steamshell")
        return ""
    resolved := ShellCommandExecutablePath(configured)
    if (resolved = "")
        return ""
    SplitPath(GetAbsoluteSteamShellPath(resolved), , &directory)
    return directory
}

; The same for XFE, read out of the logon task's own action. Failure is treated
; as "no second opinion available", never as an error.
SteamShellXfeLogonTaskDirectory() {
    global ScriptPid
    xmlPath := A_Temp "\SteamShell-xfe-query-" ScriptPid ".xml"
    try {
        if FileExist(xmlPath)
            FileDelete(xmlPath)
        command := A_ComSpec ' /d /c '
            . QuoteWindowsCommandLineArg(A_WinDir "\System32\schtasks.exe")
            . " /query /tn " QuoteWindowsCommandLineArg(XfeLogonTaskName())
            . " /xml ONE > " QuoteWindowsCommandLineArg(xmlPath)
        RunWait(command, A_WinDir, "Hide")
        if !FileExist(xmlPath)
            return ""
        text := ""
        try text := FileRead(xmlPath, "UTF-16")
        if (Trim(text) = "")
            try text := FileRead(xmlPath, "UTF-8")
        if !RegExMatch(text, "is)<Command>(.*?)</Command>", &commandMatch)
            return ""
        exePath := Trim(commandMatch[1])
        exePath := StrReplace(StrReplace(exePath, "&quot;", Chr(34)), "&amp;", "&")
        exePath := Trim(ExpandEnvVars(Trim(exePath, " `t`r`n" Chr(34))))
        if (exePath = "" || !FileExist(exePath))
            return ""
        SplitPath(GetAbsoluteSteamShellPath(exePath), , &directory)
        return directory
    } catch {
        return ""
    } finally {
        try {
            if FileExist(xmlPath)
                FileDelete(xmlPath)
        }
    }
}

; Directories SteamShell picked and created, and can therefore remove whole.
SteamShellRemovableDirectoryKind(path, installDirectory, product) {
    path := RTrim(GetAbsoluteSteamShellPath(path), "\/")
    installDirectory := RTrim(GetAbsoluteSteamShellPath(installDirectory), "\/")
    if (path = "")
        return ""
    lower := StrLower(path)
    ; Locations SteamShell chose, not the user.
    if (lower = StrLower(RTrim(SteamShellProgramData "\SteamShell", "\/")))
        return "SteamShell's writable data directory"
    if (!SteamShellProductIsXfe(product)
        && lower = StrLower(RTrim(A_ProgramFiles "\SteamShell", "\/")))
        return "the Program Files installation directory"
    if (SteamShellProductIsXfe(product)
        && lower = StrLower(RTrim(SetupAssistantXfeStandardDirectory(), "\/")))
        return "the recommended XFE installation directory"
    ; The elevated helper's bin directory, in either of the two places it can be.
    ;
    ; Without this it fell through to "not a folder SteamShell created, so only
    ; its own files are removed" -- untrue, and it left an administrator-owned
    ; directory behind that the user cannot delete themselves, for a product
    ; they had just uninstalled.
    if (lower = StrLower(RTrim(A_ProgramFiles "\SteamShell\bin", "\/"))
        || lower = StrLower(RTrim(A_ProgramFiles "\SteamShell-XFE\bin", "\/")))
        return "the protected elevated helper folder"
    if (installDirectory != ""
        && lower = StrLower(RTrim(installDirectory "\SteamShell\bin", "\/")))
        return "the protected elevated helper folder beside the application"
    ; Fixed-name subdirectories SteamShell creates inside whatever install
    ; directory was chosen. The name alone is not enough -- it must also sit
    ; directly beneath the install directory we know about.
    if (installDirectory != "") {
        SplitPath(path, &leaf, &parent)
        if (StrLower(RTrim(parent, "\/")) = StrLower(installDirectory)) {
            if (StrLower(leaf) = "steamshell")
                return "the portable data folder beside the application"
            if (StrLower(leaf) = "components")
                return "the installed component folder"
        }
    }
    return ""
}

; Refuses anything that is not a plain, non-reparse directory under a drive, and
; anything containing the executable currently running. Mirrors the guards the
; upgrade-sidecar cleanup already uses, for the same reason.
SteamShellRemovalPathIsSafe(path, &reason) {
    reason := ""
    path := RTrim(GetAbsoluteSteamShellPath(path), "\/")
    if (path = "" || !RegExMatch(path, "i)^[A-Z]:\\.+")) {
        reason := "the path is not an absolute local directory"
        return false
    }
    if RegExMatch(path, "i)^[A-Z]:\\?$") {
        reason := "the path is a drive root"
        return false
    }
    for _, protectedPath in [A_WinDir, A_ProgramFiles, SteamShellProgramData,
        EnvGet("ProgramFiles(x86)"), EnvGet("USERPROFILE"), EnvGet("LOCALAPPDATA")] {
        if (protectedPath != ""
            && StrLower(path) = StrLower(RTrim(protectedPath, "\/"))) {
            reason := "the path is a protected system location"
            return false
        }
    }
    if SteamShellPathUsesLinkOrJunction(path) {
        reason := "the path uses a link or junction"
        return false
    }
    if (InStr(StrLower(GetAbsoluteSteamShellPath(A_ScriptFullPath)),
        StrLower(path) "\") = 1) {
        reason := "it contains the SteamShell executable that is running now"
        return false
    }
    return true
}

; The concrete list of what deletion would remove, so it can be shown before it
; happens. Never guesses: every entry comes from what Setup recorded.
; Deletes the registry record for ONE product, and the key only when empty.
;
; This replaced RegDeleteKey on the whole SteamShell key, which was wrong on any
; machine that has run both products. Removing XFE took the shell's
; InstalledPath, DataPath and InstallationMode with it -- exactly the three that
; RemoveSteamShellRegistration deliberately preserves so a retained managed EXE
; can still find its ProgramData -- and PreviousShell, which is what a later
; restore needs to put the user's original shell back.
;
; The shell's location records ARE deleted here, unlike in an ordinary uninstall,
; because this path is only reached when the user has separately confirmed that
; the files themselves should go. A pointer to a deleted installation is not
; worth keeping; a pointer to a retained one is.
RemoveSteamShellRegistryRecordForProduct(product) {
    global SteamShellRegKey
    values := SteamShellProductIsXfe(product)
        ? ["Product", "XfeInstalledPath", "XfeLogonTaskRegistered", "XfeHelperDeployed"]
        : ["Product", "InstalledPath", "DataPath", "InstallationMode",
           "RegisteredPath", "PreviousShell", "HelperTaskRegistered"]
    for _, name in values
        try RegDelete(SteamShellRegKey, name)
    ; Omitting both K and V from Loop Reg enumerates values only, which is the
    ; question being asked: is anything of the other product's still recorded?
    remaining := 0
    try {
        Loop Reg, SteamShellRegKey
            remaining += 1
    }
    if (remaining = 0)
        try RegDeleteKey(SteamShellRegKey)
    return remaining = 0
}

BuildSteamShellRemovalPlan(product, &items, &retained) {
    global SteamShellRegKey
    items := []
    retained := []
    isXfe := SteamShellProductIsXfe(product)

    exePath := ""
    try exePath := RegRead(
        SteamShellRegKey, isXfe ? "XfeInstalledPath" : "InstalledPath")
    exePath := Trim(exePath)
    if (exePath != "" && !FileExist(exePath)) {
        retained.Push(exePath " — recorded, but nothing is there now")
        exePath := ""
    }
    installDirectory := ""
    if (exePath != "")
        SplitPath(GetAbsoluteSteamShellPath(exePath), , &installDirectory)

    ; Second opinion, from the thing that actually has the effect: Winlogon's
    ; shell value, or the logon task's own action. This is what makes an
    ; uninstall work from a freshly downloaded EXE that has no record of its
    ; own, and what catches a record that has gone stale.
    evidenceDirectory := isXfe
        ? SteamShellXfeLogonTaskDirectory()
        : SteamShellRegisteredShellDirectory()
    evidenceDirectory := RTrim(Trim(evidenceDirectory), "\/")
    if (installDirectory = "" && evidenceDirectory != "") {
        installDirectory := evidenceDirectory
    } else if (installDirectory != "" && evidenceDirectory != ""
        && StrLower(RTrim(installDirectory, "\/")) != StrLower(evidenceDirectory)) {
        ; Two sources, two answers. Deleting on a coin toss is exactly the
        ; mistake this whole path exists to avoid, so nothing is offered.
        retained.Push(
            "Everything — the recorded location (" installDirectory
            . ") and the one actually in use (" evidenceDirectory
            . ") disagree, so no files are offered for deletion")
        items := []
        return false
    }

    directories := []
    if !isXfe {
        dataPath := ""
        try dataPath := RegRead(SteamShellRegKey, "DataPath")
        if (Trim(dataPath) != "")
            directories.Push(Trim(dataPath))
        if (installDirectory != "")
            directories.Push(installDirectory "\components")
    }
    ; The elevated helper may be in Program Files OR beside a portable install,
    ; and an uninstall cannot read the [Setup] record that says which: it is
    ; routinely driven by a freshly downloaded SteamShell.exe whose own INI
    ; describes nothing. So both candidates are offered, derived from the
    ; installDirectory resolved above rather than from A_ScriptDir -- which is
    ; the Downloads folder in exactly that case.
    ;
    ; Program Files is included even when the record says "Portable", because a
    ; user who reinstalled and changed the answer would otherwise leave the old
    ; one behind: an administrator-protected directory and a scheduled task for
    ; a product they believe is gone.
    helperDirectories := isXfe
        ? [XfeElevatedHelperDirectory()]
        : SteamShellElevatedHelperDirectories(installDirectory)
    for _, helperDirectory in helperDirectories {
        if DirExist(helperDirectory)
            directories.Push(helperDirectory)
    }
    if (installDirectory != "")
        directories.Push(installDirectory)

    seen := Map()
    for _, candidate in directories {
        resolved := RTrim(GetAbsoluteSteamShellPath(candidate), "\/")
        if (resolved = "" || seen.Has(StrLower(resolved)) || !DirExist(resolved))
            continue
        seen[StrLower(resolved)] := true
        kind := SteamShellRemovableDirectoryKind(resolved, installDirectory, product)
        if (kind = "") {
            retained.Push(resolved " — not a folder SteamShell created, so only its own files are removed")
            continue
        }
        ; Proof, not just provenance. The path may be right and the folder may
        ; still have been emptied and reused since.
        if !SteamShellDirectoryContainsOurArtifacts(resolved) {
            retained.Push(
                resolved " — no SteamShell files are in it any more, so it is not removed")
            continue
        }
        if !SteamShellRemovalPathIsSafe(resolved, &unsafeReason) {
            retained.Push(resolved " — kept because " unsafeReason)
            continue
        }
        items.Push(Map("path", resolved, "kind", "directory", "detail", kind))
    }

    ; Files are removed even from directories that are not ours, because the
    ; file itself unambiguously is.
    if (exePath != "" && FileExist(exePath)) {
        alreadyCovered := false
        for _, item in items {
            if (InStr(StrLower(GetAbsoluteSteamShellPath(exePath)),
                StrLower(item["path"]) "\") = 1)
                alreadyCovered := true
        }
        if !alreadyCovered {
            if (StrLower(GetAbsoluteSteamShellPath(exePath))
                = StrLower(GetAbsoluteSteamShellPath(A_ScriptFullPath)))
                retained.Push(exePath " — cannot delete the executable that is running now")
            else
                items.Push(Map("path", exePath, "kind", "file", "detail", "the installed application"))
        }
    }
    return items.Length > 0
}

; The executables an uninstall can find resident, resolved from the removal plan
; itself rather than from a guessed install path: whichever directories and files
; the plan already decided are ours are the only places worth looking. Returns
; the paths that could NOT be stopped, so the caller can log them without being
; blocked by them.
;
; SteamShell.exe is deliberately absent. Uninstall runs from it, so the copy
; holding the lock is this process -- the removal planner already records that
; as a retained item rather than pretending it can delete itself.
StopResidentSteamShellExecutablesForRemoval(items) {
    static RESIDENT_NAMES := [
        "SteamShell-XFE.exe",
        "SteamShell-Helper.exe",
        "bin\SteamShell-Helper.exe",
        "components\bin\SteamShell-Helper.exe",
        "SteamShell\bin\SteamShell-Helper.exe"]
    unstopped := []
    seen := Map()
    candidates := []
    for _, item in items {
        if (item["kind"] = "directory") {
            for _, relative in RESIDENT_NAMES
                candidates.Push(RTrim(item["path"], "\/") "\" relative)
        } else {
            SplitPath(item["path"], &itemName)
            if (StrLower(itemName) = "steamshell-xfe.exe"
                || StrLower(itemName) = "steamshell-helper.exe")
                candidates.Push(item["path"])
        }
    }
    for _, candidate in candidates {
        key := StrLower(candidate)
        if (seen.Has(key) || !FileExist(candidate))
            continue
        seen[key] := true
        if !StopRunningSteamShellExecutable(
            candidate, &stoppedPids, &stopFailure)
            unstopped.Push(candidate " — " stopFailure)
    }
    return unstopped
}

ExecuteSteamShellRemovalPlan(items, &removedCount, &failures) {
    removedCount := 0
    failures := []
    ; Uninstall had the same lock problem as install, and it was quieter: a
    ; running companion or helper made DirDelete fail partway, leaving a
    ; half-removed installation reported as a failure list. Stop the two
    ; executables that can be resident before removing anything, using the same
    ; identity-checked, WM_CLOSE-first path Setup uses. Best effort by design --
    ; a stop failure must not block an uninstall the user has confirmed, and the
    ; per-item failures below still report anything that survives.
    for _, resident in StopResidentSteamShellExecutablesForRemoval(items) {
        LogLine("Uninstall could not stop " resident ", so removal of it may "
            . "fail.", "Warning")
    }
    for _, item in items {
        path := item["path"]
        try {
            if (item["kind"] = "directory") {
                if !SteamShellRemovalPathIsSafe(path, &recheckReason)
                    throw Error("Refused: " recheckReason)
                DirDelete(path, true)
                if DirExist(path)
                    throw Error("The folder still exists after deletion.")
            } else {
                FileDelete(path)
                if FileExist(path)
                    throw Error("The file still exists after deletion.")
            }
            removedCount += 1
            LogLine("Uninstall removed " item["kind"] ": " path)
        } catch as err {
            failures.Push(path " — " err.Message)
            LogLine("Uninstall could not remove " path ": " err.Message, "Warning")
        }
    }
    return failures.Length = 0
}

; Uninstall from inside the assistant.
;
; The fallback for a user who cannot reach a command line -- which on a machine
; where SteamShell is the shell and something has gone wrong is not a rare
; position to be in. It removes registration and automatic startup and leaves
; every file and setting alone, which is what makes it safe to offer here.
SetupAssistantUninstall(*) {
    global SteamShellRegKey
    chosenByHand := false
    if !DetectExistingSteamShellInstallation(
        &product, &directory, &registeredAsShell, &xfeStartsAtLogon) {
        ; Nothing REGISTERED is not the same as nothing installed, and this path
        ; used to end here with "nothing was detected" and no way forward.
        ;
        ; The cases are real: an XFE install whose logon task was declined, a
        ; shell whose Winlogon value was already put back by hand or by a
        ; half-finished uninstall, and the documented workflow of running
        ; uninstall from a freshly downloaded SteamShell.exe against a registry
        ; that has been partly cleaned. Detection became stricter when it stopped
        ; accepting a leftover file as proof, which makes reaching this more
        ; likely rather than less.
        ;
        ; ChooseSteamShellProductToRemove already existed for exactly this and
        ; was reachable only from /uninstall on the command line. Setup Assistant
        ; now reaches it too, so a user looking at the window can say what is
        ; there when the machine cannot.
        ResolveInstalledSteamShellProduct(&recordedProduct, &resolveDetail)
        choice := ChooseSteamShellProductToRemove(
            "Nothing is currently registered to start on this PC. "
            . (Trim(resolveDetail) != "" ? resolveDetail " " : "")
            . "Files may still be present from an installation that was only "
            . "partly removed, or removed from a different copy of SteamShell. "
            . "Choose which one to unwind, or cancel to change nothing.")
        if (choice = "cancel") {
            SetupAssistantSetStatus(
                "Uninstall was cancelled. Nothing was changed.")
            return
        }
        product := (choice = "xfe") ? "XFE" : "Standalone"
        directory := ""
        chosenByHand := true
        LogLine("Uninstall: nothing was registered; the user chose " product
            . " at the product prompt.")
    }
    isXfe := SteamShellProductIsXfe(product)
    summary := isXfe
        ? "SteamShell-XFE will stop starting at sign-in. Its logon task is removed."
        : "SteamShell will be removed as the Windows shell and Explorer will be restored for the next sign-in."
    ; Held in locals rather than written inline. A continued line whose first
    ; character is "(" starts a continuation SECTION in v2, so an inline ternary
    ; wrapped that way is read as continuation options instead of an expression.
    confirmHeading := chosenByHand
        ? "Remove the installation you chose?"
        : "Remove the detected installation?"
    confirmNote := chosenByHand
        ? "`n`nNothing was registered to start, so this unwinds whatever is "
            . "left of that product. Anything already gone is skipped."
        : ""
    confirm := SetupAssistantMsgBox(
        confirmHeading
        . "`n`n"
        . (isXfe ? "SteamShell-XFE" : "SteamShell")
        . (directory != "" ? "`n" directory : "")
        . "`n`n" summary
        . confirmNote
        . "`n`nFiles and settings are left in place, so nothing you configured is lost."
        . "`n`nContinue?",
        "YesNo Icon!")
    if (confirm != "Yes") {
        SetupAssistantSetStatus("Uninstall was cancelled. Nothing was changed.")
        return
    }
    if !RemoveSteamShellInstallationForProduct(true, true, product) {
        SetupAssistantSetStatus(
            "The installation could not be fully removed. Check the SteamShell log for details.")
        return
    }
    productName := isXfe ? "SteamShell-XFE" : "SteamShell"
    SetupAssistantSetStatus(
        productName " was removed. Its files and settings were left in place.")

    ; Offered only after the registration is gone, and only as a second,
    ; separate decision. Deleting files is the one part of this that cannot be
    ; undone, so it is never bundled into the first confirmation.
    if !BuildSteamShellRemovalPlan(product, &removalItems, &retainedNotes) {
        ; Nothing offered is a result, not a non-event. Say why, so a user who
        ; expected a cleanup knows whether it found nothing or refused to guess.
        if retainedNotes.Length {
            skippedText := ""
            for _, note in retainedNotes
                skippedText .= "`n    " note
            SetupAssistantMsgBox(
                productName " was unregistered. No files were offered for deletion:"
                . skippedText
                . "`n`nAnything you want removed can be deleted by hand.",
                "OK Iconi")
        }
        SetupAssistantPreselectExistingInstallation()
        return
    }
    planText := ""
    for _, item in removalItems
        planText .= "`n    " item["path"] "  (" item["detail"] ")"
    retainedText := ""
    for _, note in retainedNotes
        retainedText .= "`n    " note
    deleteChoice := SetupAssistantMsgBox(
        productName " is no longer registered. Delete its files as well?`n`n"
        . "This would permanently remove:" planText
        . (retainedText != ""
            ? "`n`nThese are kept:" retainedText
            : "")
        . "`n`nSteamShell only deletes folders it created itself. Anything else — a "
        . "folder you chose, or one holding other files — keeps only its own files removed."
        . "`n`nThis cannot be undone. Delete these files?",
        "YesNo Iconx")
    if (deleteChoice != "Yes") {
        SetupAssistantSetStatus(
            productName " was unregistered. Its files were kept.")
        SetupAssistantPreselectExistingInstallation()
        return
    }
    if ExecuteSteamShellRemovalPlan(removalItems, &removedCount, &removalFailures) {
        keyRemoved := RemoveSteamShellRegistryRecordForProduct(product)
        SetupAssistantSetStatus(
            productName " was removed along with " removedCount " item(s) and its registry record."
            . (keyRemoved
                ? ""
                : " The other product's record was left in place."))
    } else {
        failureText := ""
        for _, failure in removalFailures
            failureText .= "`n    " failure
        SetupAssistantMsgBox(
            "Some files could not be deleted. " removedCount " item(s) were removed."
            . "`n`nRemaining:" failureText
            . "`n`nA file that is still in use usually means the application is running. "
            . "Close it, or sign out and back in, then try again.",
            "OK Icon!")
        SetupAssistantSetStatus(
            productName " was unregistered, but some files could not be deleted.")
    }
    SetupAssistantPreselectExistingInstallation()
}

; Closing Setup Assistant in first-run mode exits SteamShell.
;
; In that mode SteamShell is an installer, not the shell: it is running from
; wherever the user happened to launch it, Explorer owns the desktop, and it has
; deliberately suppressed Steam, the splash, the blackout, and taskbar hiding.
; Leaving it resident after the window closes means a copy of the shell running
; out of a downloads folder or a network share with no visible window and no
; reason to be there -- which is exactly what happened once, and is not
; recoverable by any means the user can see.
;
; On a completed installation the assistant is just a settings window, and
; SteamShell IS the running shell, so closing it only hides the window.
SetupAssistantCloseRequested(*) {
    global SetupAssistantGui, FirstRunSetupMode, IntentionalExitMode
    if IsSet(SetupAssistantGui)
        try SetupAssistantGui.Hide()
    if !FirstRunSetupMode
        return
    IntentionalExitMode := "setup-closed"
    try LogLine(
        "Setup Assistant was closed during first-run setup; SteamShell is exiting "
        . "rather than staying resident as an unconfigured shell.")
    EnsureExplorerAvailableForSetupExit(true)
    ExitApp()
}

SetupAssistantSelectedProduct() {
    global SetupAssistantGui
    if !IsSet(SetupAssistantGui)
        return "Standalone"
    selected := false
    try selected := SetupAssistantGui["SetupProductXfe"].Value = 1
    return selected ? "XFE" : "Standalone"
}

; XFE has no Windows-shell registration and no elevated helper, so the controls
; that only mean something for the shell product are disabled rather than left
; enabled and ignored. A control that does nothing is a promise the installer
; does not keep.
SetupAssistantRefreshProductMode(*) {
    global SetupAssistantGui
    if !IsSet(SetupAssistantGui)
        return
    isXfe := SetupAssistantSelectedProduct() = "XFE"
    try SetupAssistantGui["SetupRegisterShell"].Enabled := !isXfe
    try SetupAssistantGui["SetupRegisterXfeStartup"].Enabled := isXfe
    ; Each branch sets BOTH boxes: the selected product's registration on, the
    ; other product's off. Clearing only one left the other showing a tick it had
    ; carried since the controls were created, so shell mode displayed "Start
    ; SteamShell-XFE automatically at sign-in" as ticked. Disabling alone is not
    ; enough -- a ticked box reads as something that is going to happen, whether
    ; or not it can be clicked.
    if isXfe {
        try SetupAssistantGui["SetupRegisterShell"].Value := 0
        try SetupAssistantGui["SetupRegisterXfeStartup"].Value := 1
        SetupAssistantSetStatus(
            "XFE mode: the companion installs to the selected location, starts at sign-in through a "
            . "normal logon task, and never registers itself as the Windows shell or elevates.")
    } else {
        try SetupAssistantGui["SetupRegisterShell"].Value := 1
        try SetupAssistantGui["SetupRegisterXfeStartup"].Value := 0
        SetupAssistantSetStatus(
            "Shell mode: SteamShell is registered as the Windows shell and the elevated input helper is installed.")
    }
    SetupAssistantRefreshDeployment()
}

; XFE keeps its INI, controller profiles, and log beside its own executable, and
; Setup makes that directory writable by the signed-in user. Program Files is
; therefore the wrong recommended location for it -- a user-writable Program
; Files subdirectory is poor hygiene even when nothing in it is ever elevated.
; A per-user Programs directory is where an ordinary application of this shape
; belongs.
SetupAssistantXfeStandardDirectory() {
    return EnvGet("LOCALAPPDATA") "\Programs\SteamShell-XFE"
}

SetupAssistantRefreshDeployment(*) {
    global SetupAssistantGui, SteamShellProgramData
    if !IsSet(SetupAssistantGui)
        return
    isXfe := SetupAssistantSelectedProduct() = "XFE"
    browseSelected := SetupAssistantGui["SetupBrowse"].Value = 1
    currentSelected := SetupAssistantGui["SetupCurrent"].Value = 1
    SetupAssistantGui["SetupInstallPath"].Enabled := browseSelected
    SetupAssistantGui["SetupBrowseButton"].Enabled := browseSelected
    ; Portable is a shell-layout concept: it decides whether the writable data
    ; sits beside the EXE or in ProgramData. XFE has no such choice -- its data
    ; is always beside it -- so the checkbox would be a control that does nothing.
    SetupAssistantGui["SetupPortable"].Enabled := browseSelected && !isXfe
    if isXfe
        SetupAssistantGui["SetupPortable"].Value := 0

    if isXfe {
        if SetupAssistantGui["SetupStandard"].Value = 1
            xfeDirectory := SetupAssistantXfeStandardDirectory()
        else if currentSelected
            xfeDirectory := A_ScriptDir
        else
            xfeDirectory := Trim(SetupAssistantGui["SetupInstallPath"].Text)
        existingXfe := xfeDirectory != ""
            && FileExist(xfeDirectory "\SteamShell-XFE.exe")
        SetupAssistantGui["SetupLocationSummary"].Text := existingXfe
            ? "Existing XFE installation: " xfeDirectory
                . "`r`nApply replaces SteamShell-XFE.exe; its settings are preserved."
            : "Companion: " (xfeDirectory != "" ? xfeDirectory : "Choose a directory")
                . "`r`nSettings, controller profiles, and log stay beside it. No Windows shell change."
        return
    }

    if SetupAssistantGui["SetupStandard"].Value = 1 {
        standardDirectory := A_ProgramFiles "\SteamShell"
        standardHelper := standardDirectory
            . "\components\bin\SteamShell-Helper.exe"
        summary := FileExist(standardHelper)
            ? "Existing Standard installation: " standardDirectory
                . "`r`nApply upgrades the EXE and helper; settings are preserved."
            : "Program: " standardDirectory
                . "`r`nWritable data: " SteamShellProgramData "\SteamShell"
    } else if currentSelected {
        currentHelper := A_ScriptDir "\SteamShell\bin\SteamShell-Helper.exe"
        currentIni := A_ScriptDir "\SteamShell\SteamShellSettings.ini"
        summary := FileExist(currentHelper) && FileExist(currentIni)
            ? "Existing portable installation: " A_ScriptDir
                . "`r`nApply upgrades the EXE and helper; settings are preserved."
            : "Program: " A_ScriptDir
                . "`r`nWritable data: " A_ScriptDir "\SteamShell (portable)"
    } else {
        chosenDirectory := Trim(SetupAssistantGui["SetupInstallPath"].Text)
        isPortable := SetupAssistantGui["SetupPortable"].Value = 1
        existingPortable := isPortable && chosenDirectory != ""
            && FileExist(chosenDirectory "\SteamShell\SteamShellSettings.ini")
            && FileExist(chosenDirectory "\SteamShell\bin\SteamShell-Helper.exe")
        summary := existingPortable
            ? "Existing portable installation: " chosenDirectory
                . "`r`nApply upgrades the EXE and helper; settings are preserved."
            : "Program: " (chosenDirectory != "" ? chosenDirectory : "Choose a directory")
                . "`r`nWritable data: "
                . (isPortable
                    ? chosenDirectory "\SteamShell (portable)"
                    : SteamShellProgramData "\SteamShell")
    }
    SetupAssistantGui["SetupLocationSummary"].Text := summary
}

SetupAssistantGetDeployment(&targetDirectory, &portableMode, &installationMode) {
    global SetupAssistantGui
    targetDirectory := ""
    portableMode := false
    installationMode := ""
    if !IsSet(SetupAssistantGui)
        return false

    if SetupAssistantGui["SetupStandard"].Value = 1 {
        ; The recommended location differs by product. See
        ; SetupAssistantXfeStandardDirectory for why XFE does not go in
        ; Program Files.
        targetDirectory := SetupAssistantSelectedProduct() = "XFE"
            ? SetupAssistantXfeStandardDirectory()
            : A_ProgramFiles "\SteamShell"
        installationMode := "Standard"
    } else if SetupAssistantGui["SetupCurrent"].Value = 1 {
        targetDirectory := A_ScriptDir
        portableMode := true
        installationMode := "Portable"
    } else {
        targetDirectory := Trim(SetupAssistantGui["SetupInstallPath"].Text)
        portableMode := SetupAssistantGui["SetupPortable"].Value = 1
        installationMode := portableMode ? "Portable" : "Custom"
    }

    targetDirectory := ExpandEnvVars(
        Trim(targetDirectory, " `t`r`n" Chr(34)))
    if !RegExMatch(targetDirectory, "i)^[A-Z]:\\$")
        targetDirectory := RTrim(targetDirectory, "\/")
    if (targetDirectory = "") {
        SetupAssistantSetStatus("Choose an installation directory before applying setup.")
        return false
    }
    if FileExist(targetDirectory) && !DirExist(targetDirectory) {
        SetupAssistantSetStatus("The selected installation location is a file, not a directory.")
        return false
    }
    return true
}

SetupAssistantApply(*) {
    global SetupAssistantGui, SteamPath, RtssPath
    ; Read by InstallationRecordAlert; an undeclared global would resolve to an
    ; empty local here and report a consistent installation as moved.
    global SteamShellDataDir, SteamShellInstallationMode
    if !A_IsAdmin {
        PromptForAdministratorSetupAndExit()
        return
    }
    if (!FileExist(SteamPath)
        || StrLower(SplitPathName(SteamPath)) != "steam.exe") {
        SetupAssistantSetStatus(
            "Setup was not applied because the required Steam.exe path is invalid.")
        SetupAssistantMsgBox(
            "Select a valid Steam.exe before applying Setup.`n`nCurrent path:`n"
            . SteamPath, "OK Icon!")
        return
    }
    if !SetupAssistantGetDeployment(
        &targetDirectory, &portableMode, &installationMode)
        return

    ; The product branch. XFE shares the application discovery, the location
    ; choice, Auto-Login, and the UAC guidance above; everything below this point
    ; is shell-specific and is skipped entirely for it.
    if (SetupAssistantSelectedProduct() = "XFE") {
        registerXfeStartup := SetupAssistantGui["SetupRegisterXfeStartup"].Value = 1
        SetupAssistantSetStatus("Installing the SteamShell-XFE companion…")
        if DeploySteamShellXfe(targetDirectory, registerXfeStartup, true) {
            SetupAssistantSetStatus(
                "SteamShell-XFE is installed and "
                . (registerXfeStartup
                    ? "will start at sign-in through a normal logon task. "
                    : "will not start automatically; launch it when you want it. ")
                . "SteamShell.exe was not registered as the Windows shell.")
            MarkSteamShellSetupCompleteForXfe(targetDirectory)
        }
        return
    }

    registerShell := SetupAssistantGui["SetupRegisterShell"].Value = 1
    SetupAssistantSetStatus(
        "Applying and verifying the selected installation…"
        . (!FileExist(RtssPath) ? " RTSS was not detected and will remain optional." : ""))
    if DeploySteamShell(
        targetDirectory, portableMode, registerShell, false, true,
        installationMode) {
        ; Setup has just rewritten the record it would otherwise be judged by.
        CachedInstallationVerdict(
            A_ScriptDir, SteamShellDataDir, SteamShellInstallationMode, true)
        BuildProductTrayMenu()
        SetupAssistantSetStatus(
            "Setup is complete. "
            . (registerShell
                ? "Sign out and back in to start SteamShell as the Windows shell."
                : "Launch SteamShell.exe from the selected directory when ready."))
    }
}

BuildLsaUnicodeString(value, &textBuffer, &lsaString) {
    byteLength := StrLen(value) * 2
    textBuffer := Buffer(byteLength + 2, 0)
    StrPut(value, textBuffer, "UTF-16")
    ; 64-bit SteamShell: USHORT Length, USHORT MaximumLength, padding, PWSTR.
    lsaString := Buffer(16, 0)
    NumPut("UShort", byteLength, lsaString, 0)
    NumPut("UShort", byteLength + 2, lsaString, 2)
    NumPut("Ptr", textBuffer.Ptr, lsaString, 8)
}

StoreWindowsAutoLogonSecret(password, clearSecret, &failureReason) {
    static POLICY_CREATE_SECRET := 0x00000020
    failureReason := ""
    objectAttributes := Buffer(48, 0)
    policyHandle := 0
    status := DllCall(
        "Advapi32\LsaOpenPolicy",
        "Ptr", 0,
        "Ptr", objectAttributes,
        "UInt", POLICY_CREATE_SECRET,
        "Ptr*", &policyHandle,
        "UInt")
    if (status != 0) {
        winError := DllCall(
            "Advapi32\LsaNtStatusToWinError", "UInt", status, "UInt")
        failureReason := "LsaOpenPolicy failed (" winError ")."
        return false
    }
    passwordBuffer := 0
    try {
        BuildLsaUnicodeString("DefaultPassword", &nameBuffer, &nameString)
        dataPointer := 0
        if !clearSecret {
            BuildLsaUnicodeString(password, &passwordBuffer, &passwordString)
            dataPointer := passwordString.Ptr
        }
        status := DllCall(
            "Advapi32\LsaStorePrivateData",
            "Ptr", policyHandle,
            "Ptr", nameString.Ptr,
            "Ptr", dataPointer,
            "UInt")
        if (status != 0) {
            winError := DllCall(
                "Advapi32\LsaNtStatusToWinError", "UInt", status, "UInt")
            failureReason := "LsaStorePrivateData failed (" winError ")."
            return false
        }
        return true
    } finally {
        ; RtlSecureZeroMemory is an inline function in winnt.h, not an export of
        ; kernel32 or anything else, so the DllCall that used to be here threw on
        ; every call and a bare try swallowed it -- the plaintext password was
        ; never actually wiped. RtlZeroMemory is genuinely exported. No try:
        ; failing to clear a password in an elevated process is not a detail to
        ; discard silently.
        if IsObject(passwordBuffer)
            DllCall(
                "Kernel32\RtlZeroMemory",
                "Ptr", passwordBuffer.Ptr,
                "UPtr", passwordBuffer.Size)
        DllCall("Advapi32\LsaClose", "Ptr", policyHandle, "UInt")
    }
}

ValidateWindowsLogonCredentials(userName, domainName, password, &failureReason) {
    failureReason := ""
    tokenHandle := 0
    domainPointer := domainName != "" ? StrPtr(domainName) : 0
    if !DllCall(
        "Advapi32\LogonUserW",
        "WStr", userName,
        "Ptr", domainPointer,
        "WStr", password,
        "UInt", 2, ; LOGON32_LOGON_INTERACTIVE
        "UInt", 0, ; LOGON32_PROVIDER_DEFAULT
        "Ptr*", &tokenHandle,
        "Int") {
        failureReason := "Windows rejected the supplied credentials (" A_LastError ")."
        return false
    }
    DllCall("Kernel32\CloseHandle", "Ptr", tokenHandle, "Int")
    return true
}

ConfigureWindowsAutoLogon(userName, domainName, password, &failureReason) {
    static winlogonKey :=
        "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    failureReason := ""
    if !A_IsAdmin {
        failureReason := "Administrator approval is required to configure Auto-Login."
        return false
    }
    userName := Trim(userName)
    domainName := Trim(domainName)
    if (userName = "" || password = "") {
        failureReason := "Enter both the Windows user name and password."
        return false
    }
    if !ValidateWindowsLogonCredentials(
        userName, domainName, password, &failureReason)
        return false
    try {
        ; AutoAdminLogon is written last. A partial operation therefore remains
        ; disabled instead of enabling logon without a matching protected secret.
        RegWrite("0", "REG_SZ", winlogonKey, "AutoAdminLogon")
        RegWrite(userName, "REG_SZ", winlogonKey, "DefaultUserName")
        RegWrite(domainName, "REG_SZ", winlogonKey, "DefaultDomainName")
        try RegDelete(winlogonKey, "DefaultPassword")
        if !StoreWindowsAutoLogonSecret(password, false, &failureReason)
            return false
        RegWrite("1", "REG_SZ", winlogonKey, "AutoAdminLogon")
        return true
    } catch as err {
        try RegWrite("0", "REG_SZ", winlogonKey, "AutoAdminLogon")
        ; If the final enable write fails after LsaStorePrivateData succeeded,
        ; roll the protected secret back as well. Disabled Auto-Login should not
        ; retain a password solely because setup was interrupted partway through.
        try StoreWindowsAutoLogonSecret("", true, &rollbackError)
        failureReason := err.Message
        return false
    }
}

DisableWindowsAutoLogon(&failureReason) {
    static winlogonKey :=
        "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    failureReason := ""
    if !A_IsAdmin {
        failureReason := "Administrator approval is required to disable Auto-Login."
        return false
    }
    registryError := ""
    try {
        RegWrite("0", "REG_SZ", winlogonKey, "AutoAdminLogon")
        try RegDelete(winlogonKey, "DefaultPassword")
    } catch as err {
        registryError := err.Message
    }
    secretCleared := StoreWindowsAutoLogonSecret("", true, &secretError)
    if (registryError != "" || !secretCleared) {
        failureReason := registryError
        if !secretCleared
            failureReason .= (failureReason != "" ? " " : "") secretError
        return false
    }
    return true
}

AutoLogonDialogMessage(message, options := "OK", title := "SteamShell Auto-Login") {
    global AutoLogonGui, SettingsDialogActive
    dialogOptions := Trim(options)
    ; Owner when the Auto-Login window exists, MB_TOPMOST when it does not.
    ;
    ; The fallback was missing: with no AutoLogonGui this asked for neither, so
    ; the dialog took ordinary z-order and could open behind whatever was in
    ; front. Every other dialog helper here picks one or the other, and this one
    ; is reached during sign-in configuration, where a prompt nobody can see is
    ; a machine that appears to have stopped.
    if IsSet(AutoLogonGui)
        dialogOptions .= " Owner" AutoLogonGui.Hwnd
    else
        dialogOptions .= " 262144"
    SettingsDialogActive := true
    try return MsgBox(message, title, dialogOptions)
    finally SettingsDialogActive := false
}

AutoLogonDialogClose(*) {
    global AutoLogonGui
    if !IsSet(AutoLogonGui)
        return
    try AutoLogonGui["AutoLogonPassword"].Value := ""
    try AutoLogonGui.Destroy()
    AutoLogonGui := unset
}

AutoLogonDialogEnable(*) {
    global AutoLogonGui
    if !IsSet(AutoLogonGui)
        return
    userName := Trim(AutoLogonGui["AutoLogonUser"].Value)
    domainName := Trim(AutoLogonGui["AutoLogonDomain"].Value)
    password := AutoLogonGui["AutoLogonPassword"].Value
    confirmation := AutoLogonDialogMessage(
        "Enabling Auto-Login allows anyone with physical access to start this PC "
        . "and enter this Windows account. The password is stored as a protected "
        . "Windows LSA secret, but another administrator can still retrieve it.`n`n"
        . "Enable Auto-Login for " domainName "\" userName "?",
        "YesNo Icon!")
    if (confirmation != "Yes") {
        password := ""
        AutoLogonGui["AutoLogonPassword"].Value := ""
        return
    }
    AutoLogonGui["AutoLogonStatus"].Text := "Validating credentials and updating Windows…"
    if ConfigureWindowsAutoLogon(
        userName, domainName, password, &failureReason) {
        password := ""
        AutoLogonGui["AutoLogonPassword"].Value := ""
        LogLine("Windows Auto-Login was enabled through Setup Assistant.")
        AutoLogonDialogMessage(
            "Auto-Login is enabled for " domainName "\" userName ".`n`n"
            . "Hold Shift during sign-in to bypass automatic logon for that boot.",
            "OK Iconi")
        AutoLogonDialogClose()
        SetupAssistantSetStatus("Windows Auto-Login is enabled for " domainName "\" userName ".")
        return
    }
    password := ""
    AutoLogonGui["AutoLogonPassword"].Value := ""
    AutoLogonGui["AutoLogonStatus"].Text := "Auto-Login was not changed. " failureReason
}

AutoLogonDialogDisable(*) {
    global AutoLogonGui
    if !IsSet(AutoLogonGui)
        return
    if (AutoLogonDialogMessage(
        "Disable Windows Auto-Login and remove its protected password secret?",
        "YesNo Icon!") != "Yes")
        return
    if DisableWindowsAutoLogon(&failureReason) {
        LogLine("Windows Auto-Login was disabled through Setup Assistant.")
        AutoLogonDialogMessage(
            "Windows Auto-Login is disabled and its protected password secret was removed.",
            "OK Iconi")
        AutoLogonDialogClose()
        SetupAssistantSetStatus("Windows Auto-Login is disabled.")
        return
    }
    AutoLogonGui["AutoLogonStatus"].Text :=
        "Auto-Login could not be completely disabled. " failureReason
}

SetupAssistantConfigureAutoLogon(*) {
    global SetupAssistantGui, AutoLogonGui, SettingsDialogActive
    if !A_IsAdmin {
        SetupAssistantMsgBox(
            "Auto-Login configuration requires administrator approval. "
            . "Open SteamShell's first-run Setup Assistant or run the compiled "
            . "SteamShell.exe as administrator, then open Setup Assistant again.",
            "OK Icon!")
        return
    }
    if IsSet(AutoLogonGui) {
        try WinActivate("ahk_id " AutoLogonGui.Hwnd)
        return
    }
    winlogonKey :=
        "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    currentUser := A_UserName
    currentDomain := A_ComputerName
    autoEnabled := false
    try currentUser := RegRead(winlogonKey, "DefaultUserName", currentUser)
    try currentDomain := RegRead(winlogonKey, "DefaultDomainName", currentDomain)
    try autoEnabled := RegRead(winlogonKey, "AutoAdminLogon", "0") = "1"

    AutoLogonGui := Gui(
        "+Owner" SetupAssistantGui.Hwnd " +AlwaysOnTop +ToolWindow -Resize",
        "SteamShell Auto-Login")
    AutoLogonGui.Opt("+OwnDialogs")
    AutoLogonGui.SetFont("s10", "Segoe UI")
    heading := AutoLogonGui.AddText("xm ym w560 h28", "Configure Windows Auto-Login")
    heading.SetFont("s16 Bold")
    AutoLogonGui.AddText(
        "xm y+4 w560 h55 +Wrap",
        "Credentials are validated with Windows and the password is stored only as "
        . "the protected DefaultPassword LSA secret. It is never saved in SteamShell settings or logs.")
    AutoLogonGui.AddText("xm y+12 w125 h24", "Windows user name")
    AutoLogonGui.AddEdit("x+8 yp-2 w410 vAutoLogonUser", currentUser)
    AutoLogonGui.AddText("xm y+10 w125 h24", "Domain / computer")
    AutoLogonGui.AddEdit("x+8 yp-2 w410 vAutoLogonDomain", currentDomain)
    AutoLogonGui.AddText("xm y+10 w125 h24", "Windows password")
    AutoLogonGui.AddEdit("x+8 yp-2 w410 Password vAutoLogonPassword", "")
    AutoLogonGui.AddText(
        "xm y+12 w560 h54 +Wrap",
        "Security warning: automatic login gives anyone with physical access this "
        . "account's desktop. Administrators can retrieve LSA secrets. Use only on a physically secured gaming PC.")
    AutoLogonGui.AddText(
        "xm y+8 w560 h42 +Wrap vAutoLogonStatus",
        autoEnabled ? "Current Windows status: Auto-Login is enabled."
            : "Current Windows status: Auto-Login is disabled.")
    enableButton := AutoLogonGui.AddButton("xm y+8 w150 h34 Default", "Enable Auto-Login")
    enableButton.OnEvent("Click", AutoLogonDialogEnable)
    disableButton := AutoLogonGui.AddButton("x+10 yp w150 h34", "Disable Auto-Login")
    disableButton.OnEvent("Click", AutoLogonDialogDisable)
    cancelButton := AutoLogonGui.AddButton("x+110 yp w140 h34", "Cancel")
    cancelButton.OnEvent("Click", AutoLogonDialogClose)
    AutoLogonGui.OnEvent("Close", AutoLogonDialogClose)
    AutoLogonGui.OnEvent("Escape", AutoLogonDialogClose)
    SettingsDialogActive := true
    AutoLogonGui.Show()
    CenterGuiOnTargetMonitor(AutoLogonGui)
    SettingsDialogActive := false
}

SetupAssistantOpenUacSettings(*) {
    uacPath := A_WinDir "\System32\UserAccountControlSettings.exe"
    SetupAssistantSetStatus("Opening Windows UAC Settings…")
    if !SetupAssistantLaunchExternal(
        uacPath, "", A_WinDir, "Windows UAC Settings") {
        SetupAssistantSetStatus("Windows UAC Settings could not be opened. Check the SteamShell log for details.")
        return
    }
    SetupAssistantSetStatus(
        "Windows UAC Settings opened. Keeping UAC enabled is recommended for privilege separation.")
}

SetupAssistantOpenAutologonGuidance(*) {
    url := "https://learn.microsoft.com/sysinternals/downloads/autologon"
    SetupAssistantSetStatus("Opening Microsoft's Auto-Login documentation…")
    if !SetupAssistantLaunchExternal(
        url, "", "", "Microsoft Autologon guidance") {
        SetupAssistantSetStatus("Microsoft Autologon guidance could not be opened. Check the SteamShell log for details.")
        return
    }
    SetupAssistantSetStatus(
        "Microsoft's Autologon guidance opened. SteamShell never stores your Windows password.")
}

SetupAssistantInitializeScrolling() {
    global SetupAssistantGui, SetupAssistantControls
    global SetupAssistantControlPositions, SetupAssistantScrollBar
    global SetupAssistantContentHeight, SetupAssistantScrollOffset
    SetupAssistantControls := []
    SetupAssistantControlPositions := Map()
    SetupAssistantContentHeight := 0
    SetupAssistantScrollOffset := 0
    for ctrl in SetupAssistantGui {
        ctrl.GetPos(&ctrlX, &ctrlY, &ctrlW, &ctrlH)
        SetupAssistantControls.Push(ctrl)
        SetupAssistantControlPositions[ctrl.Hwnd] := Map(
            "x", ctrlX, "y", ctrlY, "w", ctrlW, "h", ctrlH)
        SetupAssistantContentHeight := Max(
            SetupAssistantContentHeight, ctrlY + ctrlH + 12)
    }
    SetupAssistantScrollBar := SetupAssistantGui.Add(
        "Custom", "ClassScrollBar x738 y8 w18 h340 0x1")
    OnMessage(0x0115, SetupAssistantVerticalScroll)
    OnMessage(0x020A, SetupAssistantMouseWheel)
}

SetupAssistantSetRedraw(enabled) {
    global SetupAssistantGui
    if !IsSet(SetupAssistantGui)
        return
    try DllCall(
        "User32\SendMessageW", "Ptr", SetupAssistantGui.Hwnd,
        "UInt", 0x000B, "Ptr", enabled ? 1 : 0, "Ptr", 0, "Ptr")
}

SetupAssistantMaxScroll() {
    global SetupAssistantContentHeight, SetupAssistantViewportHeight
    return Max(0, SetupAssistantContentHeight - SetupAssistantViewportHeight)
}

SetupAssistantUpdateScrollBar() {
    global SetupAssistantScrollBar, SetupAssistantScrollOffset
    global SetupAssistantContentHeight, SetupAssistantViewportHeight
    if !IsObject(SetupAssistantScrollBar)
        return
    maxOffset := SetupAssistantMaxScroll()
    if (maxOffset <= 0) {
        try SetupAssistantScrollBar.Visible := false
        return
    }
    scrollInfo := Buffer(28, 0)
    NumPut("UInt", 28, scrollInfo, 0)
    NumPut("UInt", 0x7, scrollInfo, 4)
    NumPut("Int", 0, scrollInfo, 8)
    NumPut("Int", SetupAssistantContentHeight - 1, scrollInfo, 12)
    NumPut("UInt", Max(1, SetupAssistantViewportHeight), scrollInfo, 16)
    NumPut("Int", SetupAssistantScrollOffset, scrollInfo, 20)
    try DllCall(
        "User32\SetScrollInfo", "Ptr", SetupAssistantScrollBar.Hwnd,
        "Int", 2, "Ptr", scrollInfo, "Int", true)
    try SetupAssistantScrollBar.Visible := true
}

SetupAssistantApplyScroll() {
    global SetupAssistantControls, SetupAssistantControlPositions
    global SetupAssistantScrollOffset, SetupAssistantGui
    SetupAssistantScrollOffset := ClampInt(
        SetupAssistantScrollOffset, 0, SetupAssistantMaxScroll())
    SetupAssistantSetRedraw(false)
    try {
        for _, ctrl in SetupAssistantControls {
            if !SetupAssistantControlPositions.Has(ctrl.Hwnd)
                continue
            pos := SetupAssistantControlPositions[ctrl.Hwnd]
            try ctrl.Move(
                pos["x"], pos["y"] - SetupAssistantScrollOffset,
                pos["w"], pos["h"])
        }
        SetupAssistantUpdateScrollBar()
    } finally {
        SetupAssistantSetRedraw(true)
        try DllCall(
            "User32\RedrawWindow", "Ptr", SetupAssistantGui.Hwnd,
            "Ptr", 0, "Ptr", 0, "UInt", 0x0185, "Int")
    }
}

SetupAssistantScrollTrackPosition() {
    global SetupAssistantScrollBar
    scrollInfo := Buffer(28, 0)
    NumPut("UInt", 28, scrollInfo, 0)
    NumPut("UInt", 0x10, scrollInfo, 4)
    try {
        if DllCall(
            "User32\GetScrollInfo", "Ptr", SetupAssistantScrollBar.Hwnd,
            "Int", 2, "Ptr", scrollInfo)
            return NumGet(scrollInfo, 24, "Int")
    }
    return 0
}

SetupAssistantVerticalScroll(wParam, lParam, msg, hwnd) {
    global SetupAssistantGui, SetupAssistantScrollBar
    global SetupAssistantScrollOffset, SetupAssistantViewportHeight
    if !IsSet(SetupAssistantGui) || !IsObject(SetupAssistantScrollBar)
        return
    if (lParam != SetupAssistantScrollBar.Hwnd)
        return
    maxOffset := SetupAssistantMaxScroll()
    scrollCode := wParam & 0xFFFF
    switch scrollCode {
        case 0:
            newOffset := SetupAssistantScrollOffset - 40
        case 1:
            newOffset := SetupAssistantScrollOffset + 40
        case 2:
            newOffset := SetupAssistantScrollOffset - Max(80, SetupAssistantViewportHeight - 50)
        case 3:
            newOffset := SetupAssistantScrollOffset + Max(80, SetupAssistantViewportHeight - 50)
        case 4, 5:
            newOffset := SetupAssistantScrollTrackPosition()
        case 6:
            newOffset := 0
        case 7:
            newOffset := maxOffset
        default:
            return 0
    }
    SetupAssistantScrollOffset := ClampInt(newOffset, 0, maxOffset)
    SetupAssistantApplyScroll()
    return 0
}

SetupAssistantMouseWheel(wParam, lParam, msg, hwnd) {
    global SetupAssistantGui, SetupAssistantScrollOffset
    if !IsSet(SetupAssistantGui)
        return
    rootHwnd := DllCall("User32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    if (rootHwnd != SetupAssistantGui.Hwnd)
        return
    delta := (wParam >> 16) & 0xFFFF
    if (delta & 0x8000)
        delta -= 0x10000
    if (delta != 0) {
        SetupAssistantScrollOffset += delta > 0 ? -80 : 80
        SetupAssistantApplyScroll()
    }
    return 0
}

SetupAssistantResized(guiObj, minMax, newWidth, newHeight) {
    global SetupAssistantGui, SetupAssistantScrollBar
    global SetupAssistantViewportHeight
    if (minMax = -1 || !IsSet(SetupAssistantGui)
        || guiObj.Hwnd != SetupAssistantGui.Hwnd)
        return
    SetupAssistantViewportHeight := Max(1, newHeight)
    if IsObject(SetupAssistantScrollBar)
        try SetupAssistantScrollBar.Move(
            Max(1, newWidth - 22), 8, 18, Max(40, newHeight - 16))
    SetupAssistantApplyScroll()
}

ShowSetupAssistant(*) {
    global SetupAssistantGui, SteamShellVersion, FirstRunSetupMode
    global SetupAssistantScrollOffset, SetupAssistantViewportHeight
    ; Read by InstallationRecordAlert; an undeclared global would resolve to an
    ; empty local here and report a consistent installation as moved.
    global SteamShellDataDir, SteamShellInstallationMode
    if !IsSet(SetupAssistantGui) {
        SetupAssistantGui := Gui(
            "+AlwaysOnTop +ToolWindow +Resize",
            "SteamShell Setup Assistant")
        SetupAssistantGui.Opt("+MinSize760x300")
        SetupAssistantGui.Opt("+OwnDialogs")
        SetupAssistantGui.SetFont("s10", "Segoe UI")
        title := SetupAssistantGui.AddText("xm ym w720 h30", "SteamShell Setup Assistant")
        title.SetFont("s17 Bold", "Segoe UI")
        SetupAssistantGui.AddText(
            "xm y+2 w720 h38 +Wrap",
            "Prepare a recoverable SteamShell installation. First-run setup keeps Explorer available and does not launch Steam or enable kiosk presentation.")

        ; The first question, because every later one depends on the answer.
        SetupAssistantGui.AddGroupBox("xm y+10 w720 h128", "1. What are you setting up?")
        ; The two radios are created back to back on purpose. AutoHotkey groups
        ; radio buttons that are created CONSECUTIVELY, so a control added
        ; between them ends the run and the pair stops being mutually exclusive:
        ; both render selected and Apply reads whichever it feels like. The
        ; per-option descriptions are therefore positioned afterwards, from the
        ; radios' own measured positions, rather than interleaved.
        shellModeRadio := SetupAssistantGui.AddRadio(
            "xp+14 yp+26 w680 h24 vSetupProductStandalone Group Checked",
            "Replace the Windows shell — SteamShell owns the desktop and launches Steam Big Picture")
        xfeModeRadio := SetupAssistantGui.AddRadio(
            "xp y+24 w680 h24 vSetupProductXfe",
            "Work alongside Xbox Full Screen Experience — install the SteamShell-XFE companion")
        shellModeRadio.GetPos(&productRadioX, &shellRadioY, , &productRadioH)
        xfeModeRadio.GetPos( , &xfeRadioY)
        SetupAssistantGui.AddText(
            "x" (productRadioX + 22) " y" (shellRadioY + productRadioH + 1) " w650 h20 +Wrap",
            "Registers SteamShell as the Windows shell and installs the elevated input helper.")
        SetupAssistantGui.AddText(
            "x" (productRadioX + 22) " y" (xfeRadioY + productRadioH + 1) " w650 h20 +Wrap",
            "Never becomes the Windows shell and never elevates. Starts at sign-in through a normal logon task.")
        for _, productControl in [shellModeRadio, xfeModeRadio]
            productControl.OnEvent("Click", SetupAssistantRefreshProductMode)

        SetupAssistantGui.AddGroupBox("xm y+14 w720 h128", "2. Applications")
        SetupAssistantGui.AddText(
            "xp+14 yp+25 w680 h24 +Wrap",
            "Steam is required. RTSS is optional. Default Program Files locations are detected.")
        SetupAssistantGui.AddText("xp y+9 w55 h24", "Steam")
        SetupAssistantGui.AddEdit(
            "x+8 yp-3 w480 h27 ReadOnly vSetupSteamPath", "")
        steamButton := SetupAssistantGui.AddButton(
            "x+8 yp-1 w120 h29", "Select…")
        steamButton.OnEvent("Click", SetupAssistantChooseSteam)
        SetupAssistantGui.AddText("xp-551 y+10 w55 h24", "RTSS")
        SetupAssistantGui.AddEdit(
            "x+8 yp-3 w480 h27 ReadOnly vSetupRtssPath", "")
        rtssButton := SetupAssistantGui.AddButton(
            "x+8 yp-1 w120 h29", "Select…")
        rtssButton.OnEvent("Click", SetupAssistantChooseRtss)

        SetupAssistantGui.AddGroupBox("xm y+10 w720 h230", "3. Installation location")
        standardRadio := SetupAssistantGui.AddRadio(
            "xp+14 yp+26 w680 h24 vSetupStandard Group Checked",
            "Standard installation (recommended) — Program Files with writable data in ProgramData")
        currentRadio := SetupAssistantGui.AddRadio(
            "xp yp+32 w680 h24 vSetupCurrent",
            "Use current location — keep SteamShell.exe here and use a portable sidecar folder")
        browseRadio := SetupAssistantGui.AddRadio(
            "xp yp+32 w680 h24 vSetupBrowse", "Choose another location")
        pathEdit := SetupAssistantGui.AddEdit(
            "xp+24 yp+30 w510 h26 vSetupInstallPath Disabled", A_ScriptDir "\SteamShell-Install")
        browseButton := SetupAssistantGui.AddButton(
            "x+8 yp-1 w120 h28 vSetupBrowseButton Disabled", "Browse…")
        browseButton.OnEvent("Click", SetupAssistantBrowseInstall)
        portableCheck := SetupAssistantGui.AddCheckbox(
            "xp-518 y+10 w500 h24 vSetupPortable Disabled",
            "Portable installation — keep settings, logs, and backups beside the application")
        SetupAssistantGui.AddText(
            "xp y+7 w640 h46 +Wrap vSetupLocationSummary", "")
        for _, deploymentControl in [standardRadio, currentRadio, browseRadio, portableCheck]
            deploymentControl.OnEvent("Click", SetupAssistantRefreshDeployment)
        pathEdit.OnEvent("Change", SetupAssistantRefreshDeployment)

        SetupAssistantGui.AddGroupBox("xm y+10 w720 h186", "4. Windows integration and sign-in")
        ; One startup registration per product, and only the relevant one is
        ; enabled. Both are optional for the same reason: a user may already
        ; start the application their own way, and an installer that silently
        ; creates an automatic-start entry is one that is hard to undo.
        registerCheck := SetupAssistantGui.AddCheckbox(
            "xp+14 yp+26 w460 h24 vSetupRegisterShell Checked",
            "Register the selected SteamShell.exe as the Windows shell")
        xfeStartupCheck := SetupAssistantGui.AddCheckbox(
            "xp y+6 w460 h24 vSetupRegisterXfeStartup Checked",
            "Start SteamShell-XFE automatically at sign-in (logon task)")
        uacButton := SetupAssistantGui.AddButton(
            "xp y+32 w180 h30", "Open UAC Settings")
        uacButton.OnEvent("Click", SetupAssistantOpenUacSettings)
        autologonButton := SetupAssistantGui.AddButton(
            "x+10 yp w200 h30", "Configure Auto-Login…")
        autologonButton.OnEvent("Click", SetupAssistantConfigureAutoLogon)
        guidanceButton := SetupAssistantGui.AddButton(
            "x+10 yp w190 h30", "Microsoft Information")
        guidanceButton.OnEvent("Click", SetupAssistantOpenAutologonGuidance)
        SetupAssistantGui.AddText(
            "xp-400 y+8 w620 h36 +Wrap",
            "Auto-Login uses Windows' protected LSA secret. SteamShell never writes the password to its INI or log.")

        SetupAssistantGui.AddGroupBox("xm y+10 w720 h70", "5. Verify this PC")
        controllerButton := SetupAssistantGui.AddButton(
            "xp+14 yp+28 w210 h32", "Test / Calibrate Controller")
        controllerButton.OnEvent("Click", ShowControllerTest)
        healthButton := SetupAssistantGui.AddButton("x+10 yp w170 h32", "Run Health Check")
        healthButton.OnEvent("Click", ShowHealthCheck)
        settingsButton := SetupAssistantGui.AddButton("x+10 yp w180 h32", "Open Full Settings")
        settingsButton.OnEvent("Click", ShowSettingsEditor)

        SetupAssistantGui.AddGroupBox("xm y+10 w720 h96", "6. Remove an installation")
        SetupAssistantGui.AddText(
            "xp+14 yp+24 w680 h34 +Wrap",
            "Retires the detected installation's Windows shell registration or sign-in task. "
            . "Files and settings are left in place, so nothing you configured is lost.")
        uninstallButton := SetupAssistantGui.AddButton(
            "xp y+6 w260 h32", "Uninstall Detected Installation…")
        uninstallButton.OnEvent("Click", SetupAssistantUninstall)

        SetupAssistantGui.AddText(
            "xm y+10 w720 h42 +Wrap vSetupStatus",
            "Nothing is copied or registered until you select Apply Setup.")
        applyButton := SetupAssistantGui.AddButton("xm y+4 w170 h34 vSetupApply Default", "Apply Setup")
        applyButton.OnEvent("Click", SetupAssistantApply)
        restoreButton := SetupAssistantGui.AddButton("x+10 yp w170 h34", "Restore Desktop")
        restoreButton.OnEvent("Click", SettingsEditorRestoreDesktop)
        closeButton := SetupAssistantGui.AddButton("x+200 yp w160 h34", "Close Setup")
        closeButton.OnEvent("Click", SetupAssistantCloseRequested)
        SetupAssistantGui.OnEvent("Close", SetupAssistantCloseRequested)
        SetupAssistantGui.OnEvent("Escape", SetupAssistantCloseRequested)
        SetupAssistantGui.OnEvent("Size", SetupAssistantResized)
        SetupAssistantInitializeScrolling()
    }
    SetupAssistantDetectInstalledApplications()
    ; Open on what is already installed. Falls through to the first-run message
    ; and plain defaults when nothing is detected.
    preselected := SetupAssistantPreselectExistingInstallation()
    recordAlert := InstallationRecordAlert(
        A_ScriptDir, SteamShellDataDir, SteamShellInstallationMode)
    ; Product mode must be applied even when nothing was preselected. Its only
    ; other callers are the product radios and the preselect above, and preselect
    ; returns early on a PC with nothing installed -- so on a clean machine the
    ; sign-in checkboxes kept the state they were created with: both ticked, and
    ; both enabled. It runs BEFORE the first-run message because it sets a status
    ; line of its own, and it calls SetupAssistantRefreshDeployment itself.
    if !preselected
        SetupAssistantRefreshProductMode()
    if (FirstRunSetupMode && !preselected)
        SetupAssistantSetStatus(
            "First-run Setup Mode is active. Explorer remains available until setup is completed.")
    ; Last, because both branches above set a status of their own and this is the
    ; more urgent thing to say: the paths on screen were read from a record that
    ; describes a different location.
    if (recordAlert != "")
        SetupAssistantSetStatus(recordAlert)
    targetHwnd := 0
    try targetHwnd := WinExist("A")
    if (targetHwnd = SetupAssistantGui.Hwnd)
        targetHwnd := 0
    GetTargetMonitorWorkArea(
        targetHwnd, &workLeft, &workTop, &workRight, &workBottom)
    setupDpi := GetSafeTargetWindowDpi(targetHwnd, SetupAssistantGui.Hwnd)
    workHeightPhysical := Max(1, workBottom - workTop)
    ; Use at most 80% of the physical work area and cap the client at 620
    ; logical pixels. The remaining 20% covers non-client chrome, the taskbar,
    ; display overscan, and measurement differences during the first DPI move.
    availableLogicalHeight := Floor(
        workHeightPhysical * 0.80 * 96 / setupDpi)
    setupHeight := ClampInt(availableLogicalHeight, 300, 620)
    minimumHeight := Min(360, setupHeight)
    SetupAssistantGui.Opt(
        "+MinSize760x" minimumHeight " +MaxSize760x" setupHeight)
    SetupAssistantScrollOffset := 0
    SetupAssistantViewportHeight := setupHeight
    ; Measure once while hidden. If Windows' non-client/DPI conversion still
    ; produces an outer window above the 88% safety ceiling, reduce the logical
    ; client height by the measured excess before revealing it.
    SetupAssistantGui.Show("Hide w760 h" setupHeight)
    try {
        WinGetPos(, , , &measuredOuterHeight, "ahk_id " SetupAssistantGui.Hwnd)
        safeOuterHeight := Floor(workHeightPhysical * 0.88)
        if (measuredOuterHeight > safeOuterHeight) {
            excessLogical := Ceil(
                (measuredOuterHeight - safeOuterHeight) * 96 / setupDpi)
            setupHeight := Max(300, setupHeight - excessLogical)
            minimumHeight := Min(360, setupHeight)
            SetupAssistantGui.Opt(
                "+MinSize760x" minimumHeight " +MaxSize760x" setupHeight)
            SetupAssistantViewportHeight := setupHeight
            SetupAssistantGui.Show("Hide w760 h" setupHeight)
        }
    }
    SetupAssistantGui.Show()
    SetupAssistantApplyScroll()
    CenterGuiOnTargetMonitor(SetupAssistantGui, targetHwnd)
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
        "Steam",
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
    ; Audio and Display row visibility is NOT edited here. "Customize Quick
    ; Menu..." at the bottom of this page owns which MAIN rows appear, and it
    ; already lists Audio and Display & HDR alongside the other nine. Two
    ; controls for one outcome is how they end up disagreeing.
    ;
    ; The [AudioQuickControls]/[DisplayQuickControls] Enable keys still exist and
    ; the Quick Menu's own Settings page still toggles them, which is the part
    ; reachable from a controller; the layout manager is a desktop window.
    ;
    ; ShowGameDetection above stays, because the layout manager covers MAIN rows
    ; and that row lives under System.
    SettingsAddRowsForCategory(SettingsGui, category, "standalone", &y)
    SettingsEditorAddActionButton(category, "Customize Quick Menu…", ShowQuickMenuLayoutManager, 255, y + 6, 240)

    ; Startup and splash
    category := "Startup & Splash"
    SettingsEditorAddHeading(category, "Startup & Splash"
        , "SteamShell stays at normal integrity. The optional helper provides controller input and window geometry for administrator windows.")
    y := 150
    SettingsAddRowsForCategory(SettingsGui, category, "standalone", &y)

    ; Startup programs
    category := "Startup Programs"
    SettingsEditorAddHeading(category, "Startup Programs"
        , "Add up to 20 standard-user programs. Select a row to edit its command or optional arguments.")
    y := 150
    SettingsAddRowsForCategory(SettingsGui, category, "standalone", &y)
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
    ; On the grid, not by hand. These were 155, 175, 155 and 175 wide on the
    ; first line and three of 155 on the second, from columns that did not line
    ; up with each other -- the second line also stopped 205 pixels short of the
    ; right edge. Seven buttons over three derived columns instead.
    startupButtonY := startupListY + 220
    SettingsAddButtonRow(SettingsGui, category, [
        ["Add Program…", SettingsEditorAddStartupProgram],
        ["Browse Selected…", SettingsEditorBrowseStartupProgram],
        ["Apply Command", SettingsEditorSetStartupCommand],
        ["Remove Selected", SettingsEditorClearStartupCommand],
        ["Test Launch", SettingsEditorTestStartupProgram],
        ["Move Up", SettingsEditorMoveStartupProgram.Bind(-1)],
        ["Move Down", SettingsEditorMoveStartupProgram.Bind(1)]], &startupButtonY)
    SettingsStartupListView.Modify(1, "Select Focus Vis")

    ; Controller and cursor
    category := "Controller & Cursor"
    SettingsEditorAddHeading(category, "Controller & Cursor"
        , "Shell mode uses an allowlist; Windows desktop mode can cover every app except your exclusions.")
    y := 150
    ; The rows themselves are defined once, in SteamShell-Shared.ahk, so this
    ; page and the companion's cannot describe the same settings differently.
    SettingsAddRowsForCategory(SettingsGui, category, "standalone", &y)
    ; Three across the content width, not two-plus-one hanging off the edge.
    ; 255 + 690 is where the content ends, so 260-wide buttons at 255, 525 and
    ; 795 put the third one 75 pixels past the window.
    SettingsEditorAddActionButton(category, "Open Controller Mapping…", ShowControllerMappingWindow, 255, y + 5, 220)
    SettingsEditorAddActionButton(category, "Test / Calibrate Controller…", ShowControllerTest, 490, y + 5, 220)
    SettingsEditorAddActionButton(category, "Learn Controller…", ShowControllerLearner, 725, y + 5, 220)
    ; A second row rather than a fourth button on the first. The three above are
    ; 220 wide at 255, 490 and 725, which ends at 945 -- exactly the content
    ; right edge -- so there is no fourth slot, and SharedAuditSettingsLayout
    ; fails a control that crosses that boundary rather than letting it hang off
    ; the window the way the two-plus-one layout used to.
    ;
    ; 43 px below the row above, the same gap that row keeps from the fields
    ; below it, so a 30 px button clears both by 13.
    ;
    ; It sits under Learn Controller because it undoes exactly what Learn
    ; Controller does. This product offers the learner in two places and offered
    ; no way to undo it: a mis-learned axis reads as permanently deflected, the
    ; pointer runs across the screen, and this is the Windows shell, so there is
    ; no desktop to fall back to while you fix it. Also on Ctrl+Alt+Shift+D, for
    ; the case where the pointer is exactly what you have lost.
    SettingsEditorAddActionButton(category, "Delete Learned Profile",
        DeleteControllerProfileForActiveDevice, 725, y + 48, 220)
    autoMouseY := y + 91
    ; The value is read HERE rather than inside the builder, which is what let
    ; the builder move to SteamShell-Shared.ahk: this tree reads with IniReadS
    ; and the companion with ReadText, and neither has to be the other's.
    SettingsAddExeListField(SettingsGui,
        category, "Controller", "AutoMouseExeList",
        "Shell-mode automatic mouse allowlist", 255, autoMouseY, 335,
        IniReadS("Controller", "AutoMouseExeList", ""))
    SettingsAddExeListField(SettingsGui,
        category, "Controller", "DesktopAutoMouseExcludeExeList",
        "Desktop-mode exclusions (games/apps)", 610, autoMouseY, 335,
        IniReadS("Controller", "DesktopAutoMouseExcludeExeList", ""))

    ; Steam
    ;
    ; This page did not exist here. The [Steam] section has always been read by
    ; this product -- the three shortcuts, and now the View button's own action
    ; -- but none of it was reachable from the Settings window, so the rows the
    ; shared table defines for it were built for a page nothing drew. A setting
    ; that can only be changed by hand-editing the INI is not a setting most
    ; users have.
    category := "Steam"
    SettingsEditorAddHeading(category, "Steam"
        , "What the View/Back button does on a press that was not used to reach a mapping.")
    y := 150
    SettingsAddRowsForCategory(SettingsGui, category, "standalone", &y)

    ; Focus
    category := "Focus & Windows"
    SettingsEditorAddHeading(category, "Focus & Windows"
        , "One coordinated engine inventories windows, applies bounded geometry corrections, and selects one focus winner.")
    y := 150
    SettingsAddRowsForCategory(SettingsGui, category, "standalone", &y)
    ; Hand-placed, and the only settings row that is. The companion compiles
    ; SteamShell-Shared.ahk and forbids this key by name -- it is a shell
    ; responsibility, and a name in a string still counts. So the row stays here
    ; rather than the boundary being widened to admit it.
    ;
    ; It draws after the shared rows, which is where it sat before: last in the
    ; flowing block, above the exclusion list.
    SettingsEditorAddMappedChoice(
        category, "GameForegroundAssist", "GameMinScoreToActivate",
        "Foreground sensitivity",
        ["Responsive (55)", "Balanced (60)", "Conservative (70)"],
        ["55", "60", "70"], &y, "55")
    exclusionY := y + 8
    SettingsAddExeListField(SettingsGui,
        category, "WindowManagement", "ExcludeExeList",
        "Never center or maximize these EXEs", 255, exclusionY, 690,
        IniReadS("WindowManagement", "ExcludeExeList", ""))
    SettingsEditorAddActionButton(
        category, "Open AlwaysFocus Manager…", ShowAlwaysFocusManager, 255, exclusionY + 204, 260)

    ; RTSS
    category := "RTSS & Performance"
    SettingsEditorAddHeading(category, "RTSS & Performance"
        , "Live RTSS state is used when available; configured shortcuts remain the compatibility fallback.")
    y := 150
    SettingsAddRowsForCategory(SettingsGui, category, "standalone", &y)
    SettingsEditorAddActionButton(category, "Launch Selected RTSS", SettingsEditorOpenRtss, 255, y + 4, 220)

    ; Launcher cleanup
    category := "Launcher Cleanup"
    SettingsEditorAddHeading(category, "Launcher Cleanup"
        , "Optional cleanup after returning to Steam. EXE lists are saved automatically in the required pipe-separated format.")
    y := 150
    SettingsAddRowsForCategory(SettingsGui, category, "standalone", &y)
    listY := y + 8
    SettingsAddExeListField(SettingsGui,
        category, "LauncherCleanup", "LauncherExeList", "Launcher EXEs to close",
        255, listY, 335, IniReadS("LauncherCleanup", "LauncherExeList", ""))
    SettingsAddExeListField(SettingsGui,
        category, "LauncherCleanup", "ExcludeExeList", "Never close these EXEs",
        610, listY, 335, IniReadS("LauncherCleanup", "ExcludeExeList", ""))
    helperListY := listY + 210
    SettingsAddExeListField(SettingsGui,
        category, "LauncherCleanup", "BackgroundExeList",
        "Background helper EXEs to close", 255, helperListY, 690,
        IniReadS("LauncherCleanup", "BackgroundExeList", ""))
    SettingsEditorAddActionButton(
        category, "Preview Running Cleanup Targets…",
        SettingsEditorPreviewLauncherCleanup, 255, helperListY + 204, 300)
    y := helperListY + 242

    ; Advanced and logging
    category := "Advanced & Logging"
    SettingsEditorAddHeading(category, "Advanced & Logging"
        , "Common diagnostics are available here. Open the Diagnostics Panel for timed overrides and detailed status.")
    y := 150
    SettingsAddRowsForCategory(SettingsGui, category, "standalone", &y)
    actionY := y + 12
    ; Shell registration first, then everything else.
    ;
    ; These four were rows four and five of a ten-row grid, interleaved with
    ; diagnostics, backup and export. "Permanently Restore Explorer" was the
    ; tenth of nineteen buttons -- it is the escape hatch for a program that has
    ; taken over the Windows shell, reached for when the machine is misbehaving
    ; and the desktop is wanted back, and it was sitting between "Register
    ; Current EXE as Shell" and "Health Check".
    ;
    ; Paired by intent rather than by name: the top row is the two ways to BECOME
    ; the shell, the second is repair and undo. That also stops Register and
    ; Restore -- opposite outcomes, similar labels -- sitting side by side, which
    ; is how they were.
    ;
    ; TWO columns, not the default three: "Install Managed Copy as Shell" does
    ; not fit in a third of the content width. The width itself is derived, so
    ; these no longer carry a hand-typed 335 that stops being right when the
    ; content area moves.
    SettingsAddButtonRow(SettingsGui, category, [
        ["Install Managed Copy as Shell", SettingsEditorInstallSteamShell],
        ["Register Current EXE as Shell", SettingsEditorRegisterCurrentShell],
        ["Repair Managed Installation", SettingsEditorRepairSteamShell],
        ["Permanently Restore Explorer", SettingsEditorRestoreDesktop],
        ["Pause / Resume Focus", SettingsEditorToggleFocusPause],
        ["Run Game Assist", SettingsEditorRunGameAssist],
        ["Reload Runtime", SettingsEditorReloadRuntime],
        ["Open INI in Notepad", SettingsEditorOpenIni],
        ["Open Live Log", ShowLiveLogWindow],
        ["Diagnostics Panel…", ShowControlPanel],
        ["Health Check…", ShowHealthCheck],
        ["Export Diagnostic ZIP", ExportDiagnosticBundle],
        ["Create Settings Backup", SettingsEditorCreateBackup],
        ["Export Settings…", SettingsEditorExportSettings],
        ["Import / Restore…", SettingsEditorImportSettings],
        ["Restore Category Defaults…", SettingsEditorResetCategory],
        ["Reset All Settings…", SettingsEditorResetAll],
        ["Restart in Safe Mode", RestartSteamShellInSafeMode],
        ; Diagnostic, not recovery, and placed accordingly: a user whose
        ; controller has stopped answering cannot navigate here with it. What it
        ; buys is a one-click answer to WHICH failure happened -- if input returns,
        ; the problem was the stale device handle or the RawInput registration
        ; rather than the backend -- while you still have a mouse to press it with.
        ["Re-arm Controller Input", RearmControllerInput],
        ["Setup Assistant…", ShowSetupAssistant]], &actionY, 2)

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

    ; Before the dependency pass, which decides what is greyed out from what the
    ; fields now hold. Running it against empty controls would grey the wrong
    ; rows until something changed.
    SettingsEditorPopulateFields()
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


; ==============================================================================
; Controller Mapping UI helpers (config window)
; ==============================================================================




; ----- Controller Mapping UI event wrappers (avoid .Bind / #Warn issues) -----
; --------------------------------------------------------------------------




; The builtin actions this product offers, and what it calls them.
;
; One table, read in both directions through SharedBindingLabelFor and
; SharedBindingActionFor. It used to be two -- this list and ChoiceToBinding's
; switch -- which could disagree without anything noticing.
;
; Windows' own names, because this product IS the Windows shell and a user
; reading "Alt+F4" here has just read it in Windows. The companion names the
; same actions the way Xbox FSE does.
ControllerBindingLabels() {
    static labels := [
        ["None", "None"],
        ["LeftClick", "Left click"],
        ["RightClick", "Right click"],
        ["Enter", "Enter"],
        ["Esc", "Esc"],
        ["AltF4", "Alt+F4"],
        ["WinG", "Win+G"],
        ["CtrlAltTab", "Ctrl+Alt+Tab"],
        ["TaskManager", "Task Manager"],
        ["StartMenu", "Open Windows Start"],
        ["Explorer", "Open File Explorer"],
        ["QuickMenu", "Open Quick Menu"],
        ["ControlPanel", "Open Control Panel"],
        ["TabTip", "Open touch keyboard"],
        ["OSK", "Open OSK"]]
    return labels
}

ControllerBindingPretty(key) {
    global ControllerMapDisplay
    value := GetBindingValue(key)
    if (value = "" || value = "Builtin:None")
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
    global AllowExplorer, MouseHidden, DesktopRestorePending
    DesktopRestorePending := true
    ; Destroy first, before Explorer/taskbar/compositor ownership changes. Merely
    ; hiding the persistent HWND can leave its last child surfaces as a DWM ghost.
    DestroyQuickMenuForSurfaceTransition()
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
    SetTimer(ControllerDiagnosticTick, 0)
    SetTimer(CheckLauncherCleanup, 0)
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
    global SteamPath, DesktopRestorePending, DesktopMode

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
        ; Owner when SteamShell has an active window, MB_TOPMOST when it does
        ; not -- the helper picks. A bare 262144 is above everything EXCEPT a
        ; topmost fullscreen game, which is precisely when a restore prompt goes
        ; unseen and the user thinks the shell has hung.
        SetupAssistantMsgBox(
            "Steam's executable could not be found, so it could not be asked to close.`n`n"
            . "Open Settings and select the correct Steam executable, or use System ▸ Exit SteamShell.",
            "Iconx", "SteamShell")
        return
    }

    DesktopRestorePending := true
    DestroyQuickMenuForSurfaceTransition()
    SplitPath(steamExe, , &steamDirectory)
    shutdownPid := 0
    if !LaunchInteractiveApp(
        steamExe, "-shutdown", steamDirectory, "Normal", &shutdownPid,
        "Steam shutdown") {
        DesktopRestorePending := false
        ShowNotification("Steam could not be asked to close. Desktop restore was cancelled.", "Warning")
        SetupAssistantMsgBox(
            "Steam could not be asked to close. The desktop was not restored.",
            "Iconx", "SteamShell")
        return
    }

    ShowNotification("Closing Steam and restoring the desktop…")
    deadline := A_TickCount + 20000
    while (ProcessExist("steam.exe") && A_TickCount < deadline)
        Sleep(250)

    if ProcessExist("steam.exe") {
        ShowNotification("Steam did not close within 20 seconds.", "Warning")
        result := SetupAssistantMsgBox(
            "Steam did not close within 20 seconds.`n`n"
            . "Restore the Windows desktop anyway? Steam will be left running.",
            "YesNo Icon!", "SteamShell")
        if (result != "Yes") {
            DesktopRestorePending := false
            return
        }
    }

    ; MonitorShell can complete the restore while the shutdown wait yields to
    ; timers. Do not run the transaction a second time in that case.
    if DesktopMode
        return true

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
    global DesktopMode, QuickMenuVisible, DesktopRestorePending
    DesktopMode := true
    DesktopRestorePending := false
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
    BuildProductTrayMenu()
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
    ; Returning changes the complete presentation surface. Destroy the persistent
    ; menu before launching so its last bitmap cannot survive as a compositor
    ; ghost behind Steam or a startup-recovery window.
    DestroyQuickMenuForSurfaceTransition()
    if !LaunchSteamBpm() {
        failureReason := SteamLaunchFailedReasonText()
        DisarmSteamLifecycle()
        SetSessionState("DESKTOP", "Steam launch failed")
        ShowNotification("Steam could not be started. " . failureReason, "Warning")
        ; Owner when there is one, MB_TOPMOST otherwise. A bare 262144 is above
        ; everything except a topmost fullscreen window, and this fires on the
        ; shell desktop where the user has nothing else to read.
        SetupAssistantMsgBox(
            "Steam could not be started.`n`n" . failureReason
            . "`n`nSteamShell has stayed on the Windows desktop.",
            "Iconx", "SteamShell")
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
    global IntentionalExitMode, DesktopRestorePending
    static restoring := false
    if (restoring)
        return false
    restoring := true
    DesktopRestorePending := true
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
    DesktopRestorePending := false
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
        explorerPid := 0
        if !LaunchInteractiveApp(
            A_WinDir "\explorer.exe", "", A_WinDir,
            "Normal", &explorerPid, "Windows desktop restore")
            launchError := "No verified standard-user Explorer route was available."
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
    ; Before anything else: a held button must not outlive the process.
    ReleaseControllerMouseButtons()
    global IntentionalExitMode, DesktopMode, SafeMode
    global ElevatedGeometryEventHandle, ElevatedAutoMouseEventHandle
    global DisplayPendingOldMode, DisplayPendingOldScale, DisplayPendingUntilTick
    global ShellRegKey
    StopTaskbarGuard(true)
    ; Unhides Progman/WorkerW. An End Task cannot reach this, but that case is
    ; already covered: the unexpected-exit recovery below restarts Explorer, which
    ; recreates the desktop windows from scratch.
    StopDesktopBlackout(true)
    ShutdownRtssHooksApi()
    ; The shared teardown, directly. ReleaseQuickMenuPaintResources was one name
    ; for two different routines -- here it deleted QuickMenuRowsBitmap and shut
    ; GDI+ down, in the companion it called this. Deleting the bitmap was the
    ; weaker of the two: the Static control is still holding that handle, and the
    ; one the control had swapped in earlier was never freed at all, so the tidier
    ; of the two names did the less complete job. QuickMenuDestroyWindow detaches
    ; the image from the control first, frees both handles, and then shuts GDI+
    ; down.
    QuickMenuDestroyWindow()
    if ElevatedGeometryEventHandle {
        try DllCall(
            "Kernel32\CloseHandle", "Ptr", ElevatedGeometryEventHandle, "Int")
        ElevatedGeometryEventHandle := 0
    }
    if ElevatedAutoMouseEventHandle {
        try DllCall(
            "Kernel32\CloseHandle", "Ptr", ElevatedAutoMouseEventHandle, "Int")
        ElevatedAutoMouseEventHandle := 0
    }
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
        explorerPid := 0
        LaunchInteractiveApp(
            A_WinDir "\explorer.exe", "", A_WinDir,
            "Normal", &explorerPid, "Unexpected-exit desktop recovery")
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
    if !ProcessExist("explorer.exe") {
        explorerPid := 0
        LaunchInteractiveApp(
            A_WinDir "\explorer.exe", "", A_WinDir,
            "Normal", &explorerPid, "Safe Mode desktop")
    }
    LogLine("Safe Mode started: shell enforcement, startup programs, splash, focus automation, and cleanup are disabled.")
}

SetupAssistantRequired() {
    setupState := StrLower(Trim(IniReadS("Setup", "SetupState", "Pending")))
    setupVersion := ToInt(IniReadS("Setup", "SetupVersion", "0"), 0)
    ; A machine configured for XFE must never have SteamShell.exe start the shell
    ; runtime. There it is the installer and the uninstaller, not the product.
    if SteamShellProductIsXfe(IniReadS("Setup", "Product", "Standalone"))
        return true
    return setupState != "complete" || setupVersion < 1
}

StartFirstRunSetupSession() {
    global FirstRunSetupMode, DesktopMode, AllowExplorer, SystemReady
    global ControllerPollIntervalMs
    FirstRunSetupMode := true
    DesktopMode := true
    AllowExplorer := true
    SystemReady := true
    SetSessionState("SETUP", "first-run configuration is incomplete")
    StopTaskbarGuard()
    StopDesktopBlackout()
    ShowDesktopTaskbars()
    SystemCursor("Show")
    if !ProcessExist("explorer.exe") {
        explorerPid := 0
        LaunchInteractiveApp(
            A_WinDir "\explorer.exe", "", A_WinDir,
            "Normal", &explorerPid, "First-run Setup desktop")
    }
    SetTimer(PollController, ControllerPollIntervalMs)
    SetTimer(ShowSetupAssistant, -300)
    LogLine(
        "First-run Setup Mode started: Explorer is available and Steam, splash, "
        . "taskbar hiding, desktop blackout, window automation, and startup programs are disabled.")
}

RestartSteamShellInSafeMode(*) {
    global IntentionalExitMode, SettingsEditorDirty
    global ExpectedInteractiveUserSid, ExpectedInteractiveSessionId
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
    commandLine .= " --steamshell-user-sid=" ExpectedInteractiveUserSid
    commandLine .= " --steamshell-session-id=" ExpectedInteractiveSessionId
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

    if !IsSteamShellIdentityArgument(
        "--steamshell-user-sid=S-1-5-21-1")
        || !IsSteamShellIdentityArgument("--steamshell-session-id=1")
        || IsSteamShellIdentityArgument("--safe")
        failures.Push("Elevation identity argument classification")
    if (StandardLaunchShowValue("Hidden") != 0
        || StandardLaunchShowValue("Minimized") != 2
        || StandardLaunchShowValue("Normal") != 1)
        failures.Push("Standard-user launch show-state mapping")

    normalizedExeList := ParseExeListPipe(
        "Steam.exe|Example App|STEAM.EXE|bad\path.exe|# ignored")
    if (normalizedExeList.Length != 3
        || normalizedExeList[1] != "steam.exe"
        || normalizedExeList[2] != "example app.exe"
        || normalizedExeList[3] != "steam.exe")
        failures.Push("ParseExeListPipe normalization")

    editorExeList := SettingsParseExeList("One.exe|one.EXE|Two")
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
        SteamShellMsgBox(
            report, failures.Length ? "Iconx" : "Iconi", "SteamShell Self-Test")
    return failures.Length = 0
}

WriteSetupStateToIni(iniFile, setupState, installationMode, installDirectory, dataDirectory, product := "Standalone", portableHelperLocation := "ProgramFiles") {
    IniWrite(setupState, iniFile, "Setup", "SetupState")
    IniWrite("1", iniFile, "Setup", "SetupVersion")
    IniWrite(NormalizeSteamShellProduct(product), iniFile, "Setup", "Product")
    IniWrite(installationMode, iniFile, "Setup", "InstallationMode")
    IniWrite(installDirectory, iniFile, "Setup", "InstallDirectory")
    IniWrite(dataDirectory, iniFile, "Setup", "DataDirectory")
    ; Recorded, not re-derived. A folder whose permissions change after Setup
    ; must not silently move the helper out from under an already-registered
    ; task; the location is a decision made once, with the evidence available.
    IniWrite(portableHelperLocation, iniFile, "Setup", "PortableHelperLocation")
}

; After an XFE install, SteamShell.exe has done its job as an installer. Record
; that so a later launch opens Setup instead of starting the shell runtime on a
; machine the user deliberately configured not to have a replaced shell.
MarkSteamShellSetupCompleteForXfe(targetDirectory) {
    global SettingsPath
    try {
        WriteSetupStateToIni(
            SettingsPath, "Complete", "XFE", targetDirectory, targetDirectory, "XFE")
        return true
    } catch as err {
        LogLine("The XFE product state could not be recorded: " err.Message, "Warning")
        return false
    }
}

GrantSteamShellDataAccess(dataDirectory, &failureReason) {
    global ExpectedInteractiveUserSid
    failureReason := ""
    sidText := ExpectedInteractiveUserSid
    if (sidText = "" && !GetCurrentProcessUserSid(&sidText, &sidError)) {
        failureReason := "The interactive user SID could not be determined (" sidError ")."
        return false
    }
    icaclsPath := A_WinDir "\System32\icacls.exe"
    permissionSpec := "*" sidText ":(OI)(CI)M"
    commandLine := QuoteWindowsCommandLineArg(icaclsPath)
        . " " QuoteWindowsCommandLineArg(dataDirectory)
        . " /inheritance:e /grant:r " QuoteWindowsCommandLineArg(permissionSpec)
        . " /T /C"
    try exitCode := RunWait(commandLine, A_WinDir, "Hide")
    catch as err {
        failureReason := err.Message
        return false
    }
    if (exitCode != 0) {
        failureReason := "icacls returned exit code " exitCode "."
        return false
    }
    return true
}

SteamShellInstallLocationNeedsWarning(targetDirectory) {
    if (SubStr(targetDirectory, 1, 2) = "\\")
        return "a network path"
    if RegExMatch(targetDirectory, "i)^([A-Z]:\\)", &driveMatch) {
        driveType := ""
        try driveType := DriveGetType(driveMatch[1])
        if (StrLower(driveType) = "removable")
            return "a removable drive"
        if (StrLower(driveType) = "network")
            return "a network drive"
    }
    tempDirectory := EnvGet("TEMP")
    if (tempDirectory != ""
        && InStr(StrLower(targetDirectory), StrLower(tempDirectory)) = 1)
        return "a temporary directory"
    return ""
}

GetAbsoluteSteamShellPath(path) {
    path := ExpandEnvVars(Trim(path, " `t`r`n" Chr(34)))
    if (path = "")
        return ""
    required := DllCall(
        "Kernel32\GetFullPathNameW",
        "WStr", path,
        "UInt", 0,
        "Ptr", 0,
        "Ptr", 0,
        "UInt")
    if (required <= 0)
        return path
    resolved := Buffer((required + 1) * 2, 0)
    if !DllCall(
        "Kernel32\GetFullPathNameW",
        "WStr", path,
        "UInt", required + 1,
        "Ptr", resolved.Ptr,
        "Ptr", 0,
        "UInt")
        return path
    absolutePath := StrGet(resolved, "UTF-16")
    if FileExist(absolutePath) {
        longRequired := DllCall(
            "Kernel32\GetLongPathNameW",
            "WStr", absolutePath,
            "Ptr", 0,
            "UInt", 0,
            "UInt")
        if (longRequired > 0) {
            longPath := Buffer((longRequired + 1) * 2, 0)
            if DllCall(
                "Kernel32\GetLongPathNameW",
                "WStr", absolutePath,
                "Ptr", longPath.Ptr,
                "UInt", longRequired + 1,
                "UInt")
                absolutePath := StrGet(longPath, "UTF-16")
        }
    }
    return absolutePath
}

SteamShellPathUsesLinkOrJunction(path) {
    candidate := RTrim(GetAbsoluteSteamShellPath(path), "\/")
    Loop 128 {
        if (candidate = "")
            break
        if FileExist(candidate) {
            try {
                if InStr(FileGetAttrib(candidate), "L")
                    return true
            }
        }
        parentDirectory := ""
        try SplitPath(candidate, , &parentDirectory)
        if (parentDirectory = ""
            || StrLower(parentDirectory) = StrLower(candidate))
            break
        candidate := RTrim(parentDirectory, "\/")
    }
    return false
}

CleanupTemporaryUpgradeSidecar(sourceDataDirectory, sourceSettingsPath, targetDataDirectory, &removed, &detail) {
    removed := false
    detail := ""
    sourceDataDirectory := RTrim(
        GetAbsoluteSteamShellPath(sourceDataDirectory), "\/")
    sourceSettingsPath := GetAbsoluteSteamShellPath(sourceSettingsPath)
    targetDataDirectory := RTrim(
        GetAbsoluteSteamShellPath(targetDataDirectory), "\/")
    expectedTemporarySidecar := RTrim(
        GetAbsoluteSteamShellPath(A_ScriptDir "\SteamShell"), "\/")
    expectedSourceSettings := sourceDataDirectory "\SteamShellSettings.ini"
    if (sourceDataDirectory = "" || !DirExist(sourceDataDirectory))
        return true
    if (StrLower(sourceDataDirectory) != StrLower(expectedTemporarySidecar)
        || StrLower(sourceSettingsPath) != StrLower(expectedSourceSettings)) {
        detail := "Only a temporary beside-the-upgrader SteamShell folder is eligible for removal; other source data was retained."
        return true
    }
    if (StrLower(sourceDataDirectory) = StrLower(targetDataDirectory)) {
        detail := "The selected target SteamShell folder contains the live installation and was retained."
        return true
    }
    if (SteamShellPathUsesLinkOrJunction(sourceDataDirectory)
        || SteamShellPathUsesLinkOrJunction(targetDataDirectory)) {
        detail := "The source or target path uses a link or junction, so the temporary sidecar was retained."
        return true
    }

    ; Never recursively delete a directory that contains the completed target.
    ; This also protects unusual browse choices nested under the upgrader folder.
    sourcePrefix := StrLower(sourceDataDirectory) "\"
    targetLower := StrLower(targetDataDirectory)
    if (InStr(targetLower "\", sourcePrefix) = 1) {
        detail := "The temporary sidecar contains the selected target and was retained."
        return true
    }
    if !FileExist(sourceSettingsPath) {
        detail := "The source sidecar had no Setup-state INI and was retained."
        return true
    }
    sourceSetupState := ""
    try sourceSetupState := StrLower(Trim(
        IniRead(sourceSettingsPath, "Setup", "SetupState", "")))
    if (sourceSetupState != "pending" && sourceSetupState != "inprogress") {
        detail := "The source sidecar is a completed configuration and was retained."
        return true
    }
    try {
        DirDelete(sourceDataDirectory, true)
        removed := !DirExist(sourceDataDirectory)
        detail := removed
            ? "The temporary upgrader SteamShell folder was removed."
            : "The temporary upgrader SteamShell folder could not be verified as removed."
        return removed
    } catch as err {
        detail := "The temporary upgrader SteamShell folder could not be removed: "
            . err.Message
        return false
    }
}

SetupCompletionSelect(choice, *) {
    global SetupCompletionGui, SetupCompletionChoice
    SetupCompletionChoice := choice
    if IsSet(SetupCompletionGui) {
        try SetupCompletionGui.Destroy()
        SetupCompletionGui := unset
    }
}

ShowSetupCompletionDialog(action, targetExe, dataDirectory, registerShell, helperDetail, cleanupDetail := "") {
    global SetupCompletionGui, SetupCompletionChoice
    global SetupAssistantGui, SettingsGui
    SetupCompletionChoice := "later"
    ownerHwnd := 0
    if IsSet(SetupAssistantGui) && IsGuiVisible(SetupAssistantGui)
        ownerHwnd := SetupAssistantGui.Hwnd
    else if IsSet(SettingsGui) && IsGuiVisible(SettingsGui)
        ownerHwnd := SettingsGui.Hwnd
    options := "+AlwaysOnTop +ToolWindow -Resize"
    if ownerHwnd
        options .= " +Owner" ownerHwnd
    SetupCompletionGui := Gui(options, "SteamShell Setup Complete")
    SetupCompletionGui.Opt("+OwnDialogs")
    SetupCompletionGui.SetFont("s10", "Segoe UI")
    heading := SetupCompletionGui.AddText(
        "xm ym w600 h30", "SteamShell Was " StrTitle(action))
    heading.SetFont("s17 Bold", "Segoe UI")
    completionMessage := registerShell
        ? "Setup finished successfully. Restart Windows to load the installed SteamShell and its verified elevated helper."
        : "Setup finished successfully. Windows shell registration was not changed, so restarting is optional."
    SetupCompletionGui.AddText(
        "xm y+4 w600 h40 +Wrap", completionMessage)
    SetupCompletionGui.AddText(
        "xm y+8 w600 h72 +Wrap",
        "Program:`n" targetExe "`n`nData:`n" dataDirectory)
    detailText := registerShell
        ? "SteamShell is registered as the Windows shell for the next sign-in. "
        : "Windows shell registration was not changed. "
    detailText .= helperDetail
    if (cleanupDetail != "")
        detailText .= "`n" cleanupDetail
    SetupCompletionGui.AddText("xm y+8 w600 h78 +Wrap", detailText)
    restartButton := SetupCompletionGui.AddButton(
        "xm y+12 w180 h36 Default", "Restart Now")
    restartButton.OnEvent(
        "Click", (*) => SetupCompletionSelect("restart"))
    laterButton := SetupCompletionGui.AddButton(
        "x+12 yp w180 h36", "Restart Later")
    laterButton.OnEvent("Click", (*) => SetupCompletionSelect("later"))
    SetupCompletionGui.OnEvent(
        "Close", (*) => SetupCompletionSelect("later"))
    SetupCompletionGui.OnEvent(
        "Escape", (*) => SetupCompletionSelect("later"))
    completionHwnd := SetupCompletionGui.Hwnd
    SetupCompletionGui.Show("AutoSize")
    CenterGuiOnTargetMonitor(SetupCompletionGui, ownerHwnd)
    WinWaitClose("ahk_id " completionHwnd)
    return SetupCompletionChoice
}

RequestSteamShellRestart(&failureReason) {
    failureReason := ""
    shutdownPath := A_WinDir "\System32\shutdown.exe"
    try {
        exitCode := RunWait('"' shutdownPath '" /r /t 0', A_WinDir, "Hide")
        if (exitCode != 0) {
            failureReason := "shutdown.exe returned exit code " exitCode "."
            return false
        }
        return true
    } catch as err {
        failureReason := err.Message
        return false
    }
}

DeploySteamShell(targetDirectory, portableMode := false, registerShell := true, isRepair := false, showResult := true, requestedMode := "") {
    global SettingsPath, IniPath, LogPath, SteamShellProgramData
    global SteamShellInstallDir, SteamShellInstalledExe, SteamShellDataDir
    global SteamShellInstallationMode, SteamShellRegKey, ShellRegKey
    global ConfiguredShellValue, ScriptPid, IntentionalExitMode

    if !A_IsCompiled {
        if showResult
            SetupAssistantMsgBox(
                "Compile SteamShell before applying an installation.", "Icon!")
        return false
    }
    if !A_IsAdmin {
        if showResult
            PromptForAdministratorSetupAndExit()
        return false
    }

    targetDirectory := ExpandEnvVars(Trim(targetDirectory))
    if !RegExMatch(targetDirectory, "i)^[A-Z]:\\$")
        targetDirectory := RTrim(targetDirectory, "\/")
    targetDirectory := GetAbsoluteSteamShellPath(targetDirectory)
    targetExe := targetDirectory "\SteamShell.exe"
    dataDirectory := portableMode
        ? targetDirectory "\SteamShell"
        : SteamShellProgramData "\SteamShell"
    componentDirectory := portableMode
        ? dataDirectory
        : targetDirectory "\components"
    installationMode := requestedMode != ""
        ? requestedMode
        : (portableMode ? "Portable"
            : (StrLower(targetDirectory) = StrLower(A_ProgramFiles "\SteamShell")
                ? "Standard" : "Custom"))

    ; Where the elevated helper goes for a Portable install.
    ;
    ; CHECKED, not asked. A scheduled task is an unprompted elevation to whatever
    ; binary sits at its action path, so the question is whether the interactive
    ; user can replace that binary -- and that is answerable directly. A folder
    ; the user cannot write is as safe as Program Files, and keeping the helper
    ; there costs nothing and keeps the install genuinely self-contained.
    ;
    ; Only when the folder IS user-writable is there a trade, and then it is the
    ; user's to make: full portability, or an unprompted elevation path that
    ; anything running as them could hijack.
    portableHelperChoice := "ProgramFiles"
    if portableMode {
        portableFolderProtected := SteamShellPathIsAdminOnlyWritable(
            targetDirectory, &portableGrantedTo, &portableAclError)
        if portableFolderProtected {
            portableHelperChoice := "Portable"
            LogLine("Portable install: " targetDirectory " is "
                . "administrator-only-writable, so the elevated helper stays "
                . "beside the executable and the install remains self-contained.")
        } else {
            reason := portableAclError != ""
                ? "its permissions could not be read (" portableAclError ")"
                : "it can be written by " portableGrantedTo
            keepPortable := SetupAssistantMsgBox(
                "Where should the elevated input helper go?`n`n"
                . "This folder is not protected — " reason ".`n`n"
                . "PROGRAM FILES (recommended)`n"
                . "Choose Yes. The helper is installed to`n"
                . A_ProgramFiles "\SteamShell\bin`n"
                . "where your account cannot replace it. SteamShell can then use "
                . "a scheduled task to start it, so Windows never asks for "
                . "administrator approval — which matters because that prompt "
                . "appears on a secure desktop a controller cannot answer.`n"
                . "The cost: this copy is not self-contained, and moving the "
                . "folder to another machine needs Setup run there again.`n`n"
                . "THIS FOLDER (fully portable)`n"
                . "Choose No. Everything stays together. Because anything running "
                . "as your account can replace files here, it could also replace "
                . "the helper and use that task to gain administrator rights "
                . "without a prompt. Reasonable on a machine only you use; not on "
                . "a shared one.`n`n"
                . "Install the helper to Program Files?",
                "YesNo Icon?", "SteamShell Setup — helper location")
            portableHelperChoice := (keepPortable = "No") ? "Portable" : "ProgramFiles"
            LogLine("Portable install: helper location chosen by the user: "
                . portableHelperChoice " (" reason ").")
        }
    }

    if registerShell && portableMode {
        portableWarning := SetupAssistantMsgBox(
            "Portable mode keeps the executable and writable data together. "
            . "Only register it as the Windows shell when this is a trusted, permanent directory whose SteamShell.exe cannot be replaced by another user.`n`n"
            . targetExe
            . "`n`n" (portableHelperChoice = "ProgramFiles"
                ? "The elevated input helper is installed to`n"
                    . A_ProgramFiles "\SteamShell\bin`nrather than beside the "
                    . "executable, so this copy is not self-contained. Moving the "
                    . "folder to another machine needs Setup run there again, "
                    . "which was already true of the scheduled task and the "
                    . "registry record."
                : "The elevated input helper stays in this folder, so the install "
                    . "is fully self-contained.")
            . " Uninstall from Setup Assistant removes it either way.`n`n"
            . "Continue with portable shell registration?",
            "YesNo Icon!")
        if (portableWarning != "Yes")
            return false
    }

    if registerShell && StrLower(installationMode) = "custom" {
        customWarning := SetupAssistantMsgBox(
            "A Custom installation can be below a user-writable parent directory. "
            . "SteamShell secures the helper's own bin directory, but it cannot safely register an independently invokable elevated task for an arbitrary ancestor chain.`n`n"
            . targetExe
            . "`n`nWindows will therefore ask for administrator approval each time the elevated helper starts, including at sign-in. "
            . "Use the recommended Standard location to avoid that prompt.`n`n"
            . "Continue with Custom shell registration?",
            "YesNo Icon!")
        if (customWarning != "Yes")
            return false
    }

    warningKind := SteamShellInstallLocationNeedsWarning(targetDirectory)
    if registerShell && warningKind != "" {
        warningResult := SetupAssistantMsgBox(
            "The selected SteamShell executable would be registered from " warningKind ":`n`n"
            . targetExe
            . "`n`nIf that location is unavailable at sign-in, Windows may not have a usable shell. Continue?",
            "YesNo Icon!")
        if (warningResult != "Yes")
            return false
    }

    targetIni := dataDirectory "\SteamShellSettings.ini"
    targetLog := dataDirectory "\logs\SteamShell.log"
    sourceDataDirectory := SteamShellDataDir
    sourceSettingsPath := SettingsPath
    sourceExecutable := GetAbsoluteSteamShellPath(A_ScriptFullPath)
    existingTargetExe := FileExist(targetExe) != ""
    sourceDiffersFromTarget := StrLower(sourceExecutable) != StrLower(targetExe)
    upgradeDetected := existingTargetExe && sourceDiffersFromTarget
    stagedExe := targetExe ".setup-" ScriptPid ".tmp"
    try {
        DirCreate(targetDirectory)
        DirCreate(dataDirectory)
        ; The chosen location, not the runtime one: SteamShellInstallationMode
        ; and the INI still describe the PREVIOUS install at this point.
        helperBinDirectory := portableHelperChoice = "Portable"
            ? dataDirectory "\bin"
            : A_ProgramFiles "\SteamShell\bin"
        DirCreate(helperBinDirectory)
        DirCreate(dataDirectory "\logs")
        DirCreate(dataDirectory "\backups")

        if !portableMode {
            if !A_IsAdmin
                throw Error(
                    "A managed installation requires administrator approval to secure Program Files and make ProgramData writable. Open Setup from an elevated SteamShell session and try again.")
            if !GrantSteamShellDataAccess(dataDirectory, &permissionError)
                throw Error("Writable data permissions could not be applied. " permissionError)
        }

        ; Preserve an existing target configuration during repair. A new target
        ; inherits the current configuration, including the Steam path selected
        ; earlier in this assistant.
        if !FileExist(targetIni) {
            if FileExist(SettingsPath)
                FileCopy(SettingsPath, targetIni, false)
            else
                FileAppend(GetDefaultSettingsIniText(), targetIni, "UTF-16")
        }
        WriteSetupStateToIni(
            targetIni, "InProgress", installationMode,
            targetDirectory, dataDirectory, "Standalone", portableHelperChoice)

        if sourceDiffersFromTarget {
            if FileExist(stagedExe)
                FileDelete(stagedExe)
            FileCopy(A_ScriptFullPath, stagedExe, true)
            if !FileExist(stagedExe)
                || FileGetSize(stagedExe) != FileGetSize(A_ScriptFullPath)
                throw Error("The staged SteamShell.exe copy could not be verified.")
            FileMove(stagedExe, targetExe, true)
        }
        if !FileExist(targetExe) || FileGetSize(targetExe) <= 0
            throw Error("The installed SteamShell.exe could not be verified.")

        ; A helper from an earlier session can still be resident and holding its
        ; image open. Stopped BEFORE the directory is hardened, for the same
        ; reason as the XFE path: hardening a locked file secures a directory
        ; around a stale binary. This one is High integrity, so only an elevated
        ; Setup can close it -- which is exactly the context this runs in.
        deployedHelper := helperBinDirectory "\SteamShell-Helper.exe"
        if !StopRunningSteamShellExecutable(
            deployedHelper, &stoppedHelperPids, &helperStopError)
            throw Error("A running elevated helper could not be closed, so the "
                . "helper was not installed. " helperStopError)
        ; Every mode, not just Program Files. Only bin is restricted, so a
        ; portable layout keeps its writable INI, logs, and backups beside it
        ; while the payload SteamShell elevates stops being user-replaceable.
        if !HardenElevatedHelperDirectory(
            helperBinDirectory, &helperHardenError)
            throw Error(
                "The elevated helper directory could not be secured, so the helper was not installed. "
                . helperHardenError)
        ; Never bless a pre-existing file merely because it carries the expected
        ; version resource. Lock the directory first, then replace the payload
        ; from the embedding unconditionally while only administrators can write
        ; there.
        if !ExtractEmbeddedElevatedHelper(
            deployedHelper, &helperDeployError, true)
            throw Error("The elevated helper could not be deployed. " helperDeployError)
        ; Harden a second time, now that the payload exists.
        ;
        ; The first pass locks the directory so the write above cannot be raced.
        ; It cannot set the owner of a file that is not there yet, and Windows
        ; takes a new file's owner from the creating token: the "default owner
        ; for objects created by members of the Administrators group" policy has
        ; defaulted to the object creator since XP SP2, so the freshly extracted
        ; helper is owned by the installing administrator's own SID rather than
        ; Administrators. The verification below checks the file as well as the
        ; directory and would correctly refuse it, failing every install.
        if !HardenElevatedHelperDirectory(
            helperBinDirectory, &helperOwnerError)
            throw Error(
                "The deployed elevated helper could not be secured. "
                . helperOwnerError)
        if !ElevatedHelperLocationIsProtected(deployedHelper, &helperProtectionError)
            throw Error(
                "The elevated helper directory did not verify as administrator-protected. "
                . helperProtectionError)
        helperTaskRegistered := false
        ; Only Standard has a known protected ancestor chain. Custom and
        ; Portable paths may sit below a user-writable parent that can replace
        ; the whole secured bin directory, so they must not get an independently
        ; invokable auto-elevation task.
        if (StrLower(installationMode) = "standard") {
            helperTaskRegistered := RegisterElevatedHelperTask(
                deployedHelper, targetExe, targetIni, targetLog,
                &helperTaskError)
            RegWrite(helperTaskRegistered ? "true" : "false",
                "REG_SZ", SteamShellRegKey, "HelperTaskRegistered")
            if !helperTaskRegistered
                LogLine(
                    "Elevated helper task registration failed; direct UAC fallback will be used: "
                    . helperTaskError, "Warning")
        } else {
            ; A previous Standard installation may have left an on-demand task
            ; pointing at its protected helper. Portable/Custom deployment uses
            ; explicit UAC instead and must not retain that stale launch route.
            try RemoveElevatedHelperTask()
            try RegDelete(SteamShellRegKey, "HelperTaskRegistered")
        }

        if (StrLower(LogPath) != StrLower(targetLog)
            && FileExist(LogPath) && !FileExist(targetLog))
            FileCopy(LogPath, targetLog, false)

        ; Managed copies need metadata before first start so they can locate
        ; ProgramData. Portable copies are self-describing through their
        ; sidecar and must not overwrite another managed installation's record.
        if !portableMode {
            RegWrite(targetExe, "REG_SZ", SteamShellRegKey, "InstalledPath")
            RegWrite(dataDirectory, "REG_SZ", SteamShellRegKey, "DataPath")
            RegWrite(installationMode, "REG_SZ", SteamShellRegKey, "InstallationMode")
        }

        if registerShell {
            currentShell := "explorer.exe"
            try currentShell := RegRead(ShellRegKey, "Shell")
            if !InStr(StrLower(currentShell), "steamshell") {
                if (Trim(currentShell) = "")
                    currentShell := "explorer.exe"
                RegWrite(currentShell, "REG_SZ", SteamShellRegKey, "PreviousShell")
            }
            installedCommand := '"' targetExe '"'
            if !WriteAndVerifyShellValue(installedCommand, &shellError)
                throw Error(shellError)
            ConfiguredShellValue := installedCommand
            RegWrite(targetExe, "REG_SZ", SteamShellRegKey, "RegisteredPath")
        }

        restoreShortcut := A_Programs "\Restore Windows Desktop.lnk"
        shortcutCreated := false
        try {
            FileCreateShortcut(
                targetExe, restoreShortcut, targetDirectory, "/restore",
                "Permanently restore the Windows desktop")
            shortcutCreated := FileExist(restoreShortcut)
        }

        ; Complete is deliberately last. If copying, permissions, or registry
        ; registration fails, the deployed EXE starts in Explorer-backed Setup
        ; Mode instead of enforcing a partial install. Shortcut failure remains
        ; a warning because the same EXE always supports the /restore command.
        WriteSetupStateToIni(
            targetIni, "Complete", installationMode,
            targetDirectory, dataDirectory, "Standalone", portableHelperChoice)
        if (StrLower(IniRead(targetIni, "Setup", "SetupState", "")) != "complete")
            throw Error("The completed setup state could not be verified.")

        SteamShellInstallDir := targetDirectory
        SteamShellInstalledExe := targetExe
        SteamShellDataDir := dataDirectory
        SteamShellInstallationMode := installationMode
        SettingsPath := targetIni
        IniPath := targetIni
        LogPath := targetLog

        cleanupRemoved := false
        cleanupDetail := ""
        cleanupSucceeded := true
        if upgradeDetected {
            cleanupSucceeded := CleanupTemporaryUpgradeSidecar(
                sourceDataDirectory, sourceSettingsPath, dataDirectory,
                &cleanupRemoved, &cleanupDetail)
            if !cleanupSucceeded
                LogLine("SteamShell upgrade cleanup warning: " cleanupDetail, "Warning")
        }

        if !shortcutCreated
            LogLine("SteamShell setup warning: Restore Windows Desktop shortcut was not created.")
        operation := isRepair ? "repair" : (upgradeDetected ? "upgrade" : "setup")
        LogLine("SteamShell " operation
            . " completed: " targetExe "; data=" dataDirectory
            . "; mode=" installationMode
            . "; shell=" (registerShell ? "registered" : "unchanged")
            . "; source-sidecar-removed=" (cleanupRemoved ? "yes" : "no"))

        if showResult {
            action := isRepair ? "repaired" : (upgradeDetected ? "upgraded" : "configured")
            shortcutText := shortcutCreated
                ? "The emergency Restore Windows Desktop shortcut was verified."
                : "The recovery shortcut could not be created. Recovery remains available with:`n"
                    . targetExe " /restore"
            helperText := (StrLower(installationMode) = "standard")
                ? (helperTaskRegistered
                    ? "The helper directory was secured for administrators only and the protected elevated-helper task was registered. "
                    : "The helper directory was secured for administrators only, but the helper task was unavailable, so Windows will request UAC when the helper starts. ")
                : ((StrLower(installationMode) = "custom")
                    ? "The Custom helper was version-verified and its directory was secured for administrators only. Its arbitrary parent path is not eligible for an auto-elevation task, so Windows will request UAC when the helper starts. "
                    : "The portable helper was version-verified and its directory was secured for administrators only. Windows will request UAC when the helper starts. ")
            completionChoice := ShowSetupCompletionDialog(
                action, targetExe, dataDirectory, registerShell,
                helperText . shortcutText, cleanupDetail)
            if (completionChoice = "restart") {
                IntentionalExitMode := "setup-restart"
                if RequestSteamShellRestart(&restartError) {
                    ExitApp()
                    return true
                }
                IntentionalExitMode := ""
                SetupAssistantMsgBox(
                    "Windows could not be restarted automatically.`n`n"
                    . restartError
                    . "`n`nSave your work and restart Windows manually.",
                    "OK Iconx")
            }
            if upgradeDetected {
                IntentionalExitMode := "upgrade-complete"
                ExitApp()
                return true
            }
        }
        return true
    } catch as err {
        try {
            if FileExist(stagedExe)
                FileDelete(stagedExe)
        }
        if showResult
            SetupAssistantMsgBox("SteamShell setup failed safely.`n`n" err.Message
                . "`n`nSetup remains incomplete and Explorer will remain available.",
                "Iconx")
        LogLine("SteamShell setup failed: " err.Message)
        return false
    }
}

; Where XFE's opt-in elevated RTSS helper is installed.
;
; Fixed, and deliberately NOT inside the XFE install directory. Setup grants the
; signed-in user write access to that directory -- XFE keeps its INI, learned
; controller profiles and log beside its executable -- and a user-writable
; parent can be deleted and recreated whole, which is exactly why standalone
; refuses to give its Custom and Portable layouts an independently invokable
; helper task. Program Files supplies the protected ancestor chain that makes
; the payload's own ACL mean something.
;
; A_ProgramFiles is read here in an ADMINISTRATOR process during Setup, and
; XfeElevatedHelperPath() in the XFE tree resolves the same string at normal
; integrity. Neither is trusted on its own: XFE verifies owner, DACL and
; readability through ElevatedHelperLocationIsProtected before launching it, so
; a redirected environment pointing somewhere the user can write fails closed.
XfeElevatedHelperDirectory() {
    return A_ProgramFiles "\SteamShell-XFE\bin"
}

; Installs the XFE companion instead of the shell.
;
; Deliberately narrower than DeploySteamShell: XFE never becomes the Windows
; shell, never registers a shell-integrity component directory beside itself,
; and never gets the protected on-demand helper task, because it is an ordinary
; normal-integrity application started from a desktop that already exists.
; Everything this does not do is the point.
;
; It DOES deploy the elevated helper payload, dormant. XFE has no embedded
; payload and no administrator rights, so a user who later opts in from XFE's
; own Settings would otherwise be told to re-run an installer they have already
; run. A binary on disk is not an elevated process: nothing starts it until
; [RTSS] EnableElevatedFrameCapWrites is turned on -- which now defaults to ON
; in both products, so in practice the helper is started the first time a frame
; cap needs a write RTSS's own location will not allow.
DeploySteamShellXfe(targetDirectory, registerStartup := true, showResult := true) {
    global SteamShellRegKey, ScriptPid, IntentionalExitMode, SteamShellProduct
    global ShellRegKey

    if !A_IsCompiled {
        if showResult
            SetupAssistantMsgBox(
                "Compile SteamShell before applying an installation.", "Icon!")
        return false
    }
    if !A_IsAdmin {
        if showResult
            PromptForAdministratorSetupAndExit()
        return false
    }

    targetDirectory := ExpandEnvVars(Trim(targetDirectory))
    if !RegExMatch(targetDirectory, "i)^[A-Z]:\\$")
        targetDirectory := RTrim(targetDirectory, "\/")
    targetDirectory := GetAbsoluteSteamShellPath(targetDirectory)
    targetExe := targetDirectory "\SteamShell-XFE.exe"
    stagedExe := targetExe ".setup-" ScriptPid ".tmp"

    try {
        DirCreate(targetDirectory)
        ; The companion is running on every XFE machine that has signed in, so
        ; this is the normal case rather than the awkward one. Recorded, because
        ; a companion Setup stopped is one the user expects back afterwards.
        if !StopRunningSteamShellExecutable(
            targetExe, &stoppedXfePids, &xfeStopError)
            throw Error("The running XFE companion could not be closed. "
                . xfeStopError)
        xfeWasRunning := stoppedXfePids.Length > 0
        if !ExtractEmbeddedXfe(targetExe, &xfeDeployError, true)
            throw Error("The XFE companion could not be deployed. " xfeDeployError)

        ; XFE keeps its INI, controller profiles, and log beside its executable,
        ; so the install directory must stay writable by the signed-in user.
        ; That is safe here for the same reason it is not for the helper: nothing
        ; in this layout is ever handed an elevated token.
        if !GrantSteamShellDataAccess(targetDirectory, &permissionError)
            throw Error(
                "Writable permissions could not be applied to the XFE directory. "
                . permissionError)

        ; The opt-in elevated RTSS helper, deployed dormant.
        ;
        ; Same ordering as the shell path, for the same reason it exists there:
        ; harden the directory FIRST so the write below cannot be raced, then
        ; replace the payload unconditionally while only administrators can
        ; write there, then harden AGAIN. The second pass is not redundant --
        ; icacls cannot set the owner of a file that does not exist yet, and
        ; Windows takes a new file's owner from the creating token, so the
        ; freshly extracted helper is owned by the installing administrator's
        ; own SID rather than by Administrators. XFE's runtime gate checks the
        ; file as well as the directory and would correctly refuse it, which
        ; would fail every install. An earlier revision of the shell path ran
        ; /setowner once, before the payload existed, and had exactly that bug.
        helperDeployed := false
        helperDeployFailure := ""
        helperBinDirectory := XfeElevatedHelperDirectory()
        deployedHelper := helperBinDirectory "\SteamShell-Helper.exe"
        try {
            DirCreate(helperBinDirectory)
            ; Stopped BEFORE the directory is hardened, not after. Once bin is
            ; administrator-only the payload still cannot be replaced while a
            ; process holds the image open, so hardening a locked file would
            ; produce a secured directory around a stale binary.
            if !StopRunningSteamShellExecutable(
                deployedHelper, &stoppedXfeHelperPids, &helperStopError)
                throw Error("The running XFE elevated helper could not be "
                    . "closed. " helperStopError)
            if !HardenElevatedHelperDirectory(
                helperBinDirectory, &helperHardenError)
                throw Error(helperHardenError)
            if !ExtractEmbeddedElevatedHelper(
                deployedHelper, &helperExtractError, true)
                throw Error(helperExtractError)
            if !HardenElevatedHelperDirectory(
                helperBinDirectory, &helperOwnerError)
                throw Error(helperOwnerError)
            if !ElevatedHelperLocationIsProtected(
                deployedHelper, &helperProtectionError)
                throw Error(helperProtectionError)
            helperDeployed := true
        } catch as helperError {
            helperDeployFailure := helperError.Message
        }
        ; NOT fatal, and this is a deliberate difference from the shell path.
        ; The shell needs its helper to reach elevated windows at all; XFE needs
        ; it only for a frame cap the user has not asked for yet. Refusing to
        ; install the whole companion over a dormant optional payload would be
        ; the wrong trade. It is reported rather than swallowed.
        if !helperDeployed
            LogLine(
                "The optional XFE elevated RTSS helper was not deployed; the "
                . "frame cap will stay read-only where RTSS needs administrator "
                . "rights: " helperDeployFailure, "Warning")
        RegWrite(helperDeployed ? "true" : "false",
            "REG_SZ", SteamShellRegKey, "XfeHelperDeployed")

        startupRegistered := false
        if registerStartup {
            startupRegistered := RegisterXfeLogonTask(targetExe, &xfeTaskError)
            if !startupRegistered
                LogLine(
                    "XFE logon task registration failed; the companion must be started manually: "
                    . xfeTaskError, "Warning")
        } else {
            try RemoveXfeLogonTask()
        }

        ; A machine can only have one of the two products configured at a time.
        ; Retiring the shell registration here is what makes switching to XFE a
        ; supported move rather than something that leaves Winlogon pointing at
        ; an executable the user has stopped using.
        shellRetired := ""
        try {
            currentShell := RegRead(ShellRegKey, "Shell")
            if InStr(StrLower(currentShell), "steamshell") {
                if RestoreExplorerDesktop(true, &restoreMessage) {
                    shellRetired :=
                        "SteamShell was removed as the Windows shell and Explorer was restored."
                    try RemoveElevatedHelperTask()
                    try RegDelete(SteamShellRegKey, "HelperTaskRegistered")
                    try RegDelete(SteamShellRegKey, "RegisteredPath")
                } else {
                    throw Error(
                        "SteamShell is currently registered as the Windows shell and could not be "
                        . "returned to Explorer, so XFE was not installed. " restoreMessage)
                }
            }
        }

        RegWrite(targetExe, "REG_SZ", SteamShellRegKey, "XfeInstalledPath")
        RegWrite("XFE", "REG_SZ", SteamShellRegKey, "Product")
        RegWrite(startupRegistered ? "true" : "false",
            "REG_SZ", SteamShellRegKey, "XfeLogonTaskRegistered")
        SteamShellProduct := "XFE"

        ; Put back what Setup stopped. The logon task would start it at the next
        ; sign-in anyway, but leaving a mid-session user without their companion
        ; because they applied an update is a regression the user did not ask
        ; for -- and one they would reasonably read as the update having broken
        ; something.
        ;
        ; Through Explorer's desktop automation object, never Run: this process
        ; is elevated, and a child of it would inherit an administrator token.
        ; XFE is normal-integrity by design, and an accidentally elevated
        ; companion is the one outcome its whole architecture exists to avoid.
        xfeRestarted := false
        if xfeWasRunning {
            xfeRestarted := RunViaDesktopShell(targetExe, "", targetDirectory)
            LogLine(xfeRestarted
                ? "Setup restarted the XFE companion it stopped to apply the update."
                : "Setup stopped the XFE companion to apply the update and could "
                    . "not restart it; it will start at the next sign-in.",
                xfeRestarted ? "Info" : "Warning")
        }

        LogLine("SteamShell-XFE companion installed: " targetExe
            . "; startup=" (startupRegistered ? "logon task" : "manual")
            . "; elevated RTSS helper=" (helperDeployed ? "deployed (off by default)" : "not deployed")
            . (shellRetired != "" ? "; " shellRetired : ""))

        if showResult {
            startupText := registerStartup
                ? (startupRegistered
                    ? "It will start automatically at sign-in through a normal-integrity logon task."
                    : "The logon task could not be registered, so start it manually or add it to your startup programs.")
                : "Automatic startup was not requested, so start it manually when you want it."
            ; Stated plainly, because a user chooses XFE precisely to avoid an
            ; elevated process and is entitled to know one was placed on disk.
            helperText := helperDeployed
                ? "An optional elevated RTSS helper was installed to " helperBinDirectory
                    . " and is TURNED OFF. XFE runs with nothing elevated unless you enable "
                    . "it in Settings under RTSS & Performance, which it needs only to set the "
                    . "frame cap when RTSS is installed under Program Files."
                : "The optional elevated RTSS helper was not installed, so the frame cap "
                    . "stays read-only where RTSS needs administrator rights."
            ; Only mentioned when Setup actually stopped something, so a first
            ; install says nothing about a companion that was never running.
            restartText := !xfeWasRunning ? ""
                : xfeRestarted
                    ? "`n`nThe running companion was closed to replace it and has been restarted."
                    : "`n`nThe running companion was closed to replace it and could not be "
                        . "restarted automatically. Start it from " targetExe
                        . ", or sign out and back in."
            SetupAssistantMsgBox(
                "SteamShell-XFE was installed.`n`n" targetExe "`n`n"
                . startupText
                . "`n`n" helperText
                . restartText
                . (shellRetired != "" ? "`n`n" shellRetired : "")
                . "`n`nXFE runs alongside Xbox Full Screen Experience and never replaces the Windows shell, "
                . "so no restart is required.",
                "OK Iconi")
        }
        return true
    } catch as err {
        try {
            if FileExist(stagedExe)
                FileDelete(stagedExe)
        }
        if showResult
            SetupAssistantMsgBox(
                "The XFE companion could not be installed.`n`n" err.Message
                . "`n`nNothing was registered as the Windows shell and Explorer remains available.",
                "Iconx")
        LogLine("SteamShell-XFE install failed: " err.Message, "Error")
        return false
    }
}

RemoveSteamShellXfeInstallation(showResult := true) {
    global SteamShellRegKey, SteamShellProduct
    taskRemoved := RemoveXfeLogonTask()
    ; Registered lazily by the companion the first time elevated RTSS writes are
    ; used, so Setup never created it and must still clear it. A stale
    ; HighestAvailable task pointing at a removed binary is the worst artefact an
    ; uninstall can leave behind.
    try RemoveXfeElevatedHelperTask()
    try RegDelete(SteamShellRegKey, "XfeLogonTaskRegistered")
    try RegDelete(SteamShellRegKey, "Product")
    ; The location records go too, and this is not housekeeping.
    ;
    ; The companion's executable is deliberately left on disk, so a surviving
    ; XfeInstalledPath still points at a file that still exists -- and that pair
    ; is exactly what product detection used to read as "XFE is installed". A
    ; machine that had XFE removed reported XFE forever after, so an uninstall
    ; offered to remove the thing that was already gone while the shell
    ; installation beside it went unseen.
    ;
    ; Nothing needs these afterwards. XFE reads its settings from beside its own
    ; executable rather than from a recorded path, and XfeHelperDeployed is
    ; written and never read at all. Standalone's InstalledPath/DataPath/
    ; InstallationMode are deliberately NOT treated this way: its startup matches
    ; the recorded EXE against the running one to find its ProgramData, so
    ; deleting those would strand a retained installation's settings.
    try RegDelete(SteamShellRegKey, "XfeInstalledPath")
    try RegDelete(SteamShellRegKey, "XfeHelperDeployed")
    SteamShellProduct := "Standalone"
    ; The executable and its settings are left in place, matching what the shell
    ; uninstall does: retiring the automatic startup is reversible, deleting a
    ; user's configuration is not.
    ;
    ; The elevated helper is left too, and that is worth saying out loud rather
    ; than leaving for someone to find. It is an administrator-owned binary in an
    ; administrator-only directory that nothing starts on its own: with the
    ; companion no longer running there is no parent to ask it for anything, and
    ; it exits when its parent does. Deleting it would mean an elevated recursive
    ; delete of a Program Files path during an uninstall, which is a larger risk
    ; than the dormant file it removes.
    helperDirectory := XfeElevatedHelperDirectory()
    helperPresent := FileExist(helperDirectory "\SteamShell-Helper.exe") != ""
    LogLine("SteamShell-XFE startup registration removed; logon task removed="
        . (taskRemoved ? "yes" : "no")
        . "; elevated helper left in place=" (helperPresent ? "yes" : "no") ".")
    if showResult {
        SetupAssistantMsgBox(
            "The SteamShell-XFE companion will no longer start automatically at sign-in."
            . (taskRemoved
                ? ""
                : "`n`nThe logon task could not be removed. Check Task Scheduler for '"
                    . XfeLogonTaskName() "'.")
            . "`n`nIts files and settings were left in place so nothing you configured is lost."
            . (helperPresent
                ? "`n`nThe optional elevated helper in " helperDirectory
                    . " was also left in place. Nothing starts it once the companion is gone; "
                    . "delete that folder as an administrator if you want it removed."
                : ""),
            taskRemoved ? "Iconi" : "Icon!", "SteamShell-XFE")
    }
    return taskRemoved
}

InstallOrRepairSteamShell(isRepair := false, showResult := true) {
    return DeploySteamShell(
        A_ProgramFiles "\SteamShell", false, true,
        isRepair, showResult, "Standard")
}

; Resolves the executable a Winlogon Shell value refers to, or "" if it cannot
; be found. The value is a command line, so it may be quoted and may carry
; arguments; a bare name such as "explorer.exe" is resolved through Windows'
; executable search path rather than against two hardcoded directories.
ShellCommandExecutablePath(command) {
    command := Trim(command)
    if (command = "")
        return ""
    if (SubStr(command, 1, 1) = '"') {
        closing := InStr(command, '"', false, 2)
        exePath := closing ? SubStr(command, 2, closing - 2) : SubStr(command, 2)
    } else if RegExMatch(command, "i)^(.+?\.exe)(?:\s|$)", &match) {
        ; An unquoted Winlogon command can contain spaces. Capture through the
        ; executable suffix before treating the rest as arguments.
        exePath := match[1]
    } else {
        space := InStr(command, " ")
        exePath := space ? SubStr(command, 1, space - 1) : command
    }
    exePath := Trim(ExpandEnvVars(Trim(exePath)))
    if (exePath = "")
        return ""
    if (InStr(exePath, "\") || InStr(exePath, "/")) {
        attributes := FileExist(exePath)
        return (attributes != "" && !InStr(attributes, "D")) ? exePath : ""
    }
    capacity := 32768
    resolved := Buffer(capacity * 2, 0)
    length := DllCall("Kernel32\SearchPathW",
        "Ptr", 0, "WStr", exePath, "WStr", ".exe",
        "UInt", capacity, "Ptr", resolved.Ptr, "Ptr", 0, "UInt")
    if (length > 0 && length < capacity)
        return StrGet(resolved, "UTF-16")
    return ""
}

; The shell value that was registered before SteamShell took over.
;
; InstallOrRepairSteamShell and RegisterCurrentSteamShellAsShell both record
; this, and until now nothing ever read it back: every restore path wrote a
; literal "explorer.exe" and the uninstall then deleted the key holding the only
; record. A user whose shell was something else lost it silently and
; unrecoverably. Returns "" whenever the saved value cannot be verified, which
; leaves explorer.exe as the fallback.
ResolveSavedPreviousShell() {
    global SteamShellRegKey, SteamShellInstalledExe
    saved := ""
    try saved := RegRead(SteamShellRegKey, "PreviousShell")
    saved := Trim(saved)
    if (saved = "")
        return ""
    ; An unverifiable target is worse than explorer.exe: it would be registered
    ; as the shell and then fail to start, leaving the user with no desktop.
    resolved := ShellCommandExecutablePath(saved)
    if (resolved = "")
        return ""
    ; Never hand the shell back to ourselves. Compare the resolved executable,
    ; rather than rejecting an otherwise-valid path whose directory merely
    ; contains the word "SteamShell".
    SplitPath(resolved, &resolvedName)
    if (StrLower(resolvedName) = "steamshell.exe"
        || StrLower(resolved) = StrLower(A_ScriptFullPath)
        || (SteamShellInstalledExe != ""
            && StrLower(resolved) = StrLower(SteamShellInstalledExe)))
        return ""
    return saved
}

; restorePreviousShell distinguishes a deliberate uninstall from an emergency
; restore. The Start-menu "Restore Windows Desktop" shortcut and /restore are
; emergencies: when the session is already broken, a known-good explorer.exe
; beats a faithful reinstatement of a shell that may itself be the problem.
; /uninstall is not an emergency, so it puts back what it found.
RemoveSteamShellRegistration(showResult := true, restorePreviousShell := false) {
    global SteamShellRegKey
    ; Captured before RestoreExplorerDesktop writes its explorer.exe baseline and
    ; before the key holding it is deleted below.
    previousShell := restorePreviousShell ? ResolveSavedPreviousShell() : ""

    if !RestoreExplorerDesktop(true, &restoreMessage) {
        if (showResult)
            SetupAssistantMsgBox(
                "SteamShell could not restore Explorer.`n`n" restoreMessage,
                "Iconx", "SteamShell Recovery")
        return false
    }

    restoredPrevious := ""
    if (previousShell != "" && StrLower(previousShell) != "explorer.exe") {
        if WriteAndVerifyShellValue(previousShell, &previousShellError) {
            restoredPrevious := previousShell
            LogLine("Uninstall: the pre-SteamShell shell " previousShell
                . " was reinstated for the next sign-in.")
        } else {
            LogLine("Uninstall: the pre-SteamShell shell " previousShell
                . " could not be reinstated; Explorer remains registered. "
                . previousShellError, "Warning")
            if (showResult) {
                SetupAssistantMsgBox(
                    "Explorer was restored, but the shell that was registered before SteamShell "
                    . "could not be reinstated for the next sign-in.`n`n"
                    . previousShellError "`n`n"
                    . "SteamShell's recovery shortcut and PreviousShell metadata were retained "
                    . "so the restore can be retried safely.",
                    "Icon!", "SteamShell Recovery")
            }
            return false
        }
    }

    try FileDelete(A_Programs "\Restore Windows Desktop.lnk")
    ; Attempted unconditionally, not gated on HelperTaskRegistered.
    ;
    ; That flag is written by Setup, so anything that created the task without
    ; reaching the end of Setup -- an interrupted install, a hand-edited
    ; registry, an upgrade from a build that did not record it -- left the task
    ; behind on uninstall with nothing to notice. A stale HighestAvailable task
    ; pointing at a binary is the worst artefact an uninstall can leave, which is
    ; why the XFE path has always removed its equivalent without asking first.
    ; schtasks simply reports failure when there is no such task.
    helperTaskWasRegistered := false
    try helperTaskWasRegistered := ToBool(
        RegRead(SteamShellRegKey, "HelperTaskRegistered", "false"), false)
    if (!RemoveElevatedHelperTask() && helperTaskWasRegistered)
        LogLine(
            "Desktop restore warning: the on-demand elevated helper task could not be removed.",
            "Warning")
    ; Keep InstalledPath/DataPath/InstallationMode so a deliberately retained
    ; managed EXE can still find its ProgramData configuration if launched
    ; manually after restore. Only registration/recovery state is retired.
    try RegDelete(SteamShellRegKey, "PreviousShell")
    try RegDelete(SteamShellRegKey, "RegisteredPath")
    try RegDelete(SteamShellRegKey, "HelperTaskRegistered")
    if (showResult) {
        shellText := restoredPrevious != ""
            ? "`n`nThe shell that was registered before SteamShell has been put back "
                . "and takes effect at the next sign-in:`n" restoredPrevious
            : ""
        ; Named rather than left for someone to find, which is what the XFE path
        ; has always done for its own helper. The binary is administrator-owned
        ; in an administrator-only directory and nothing starts it once the shell
        ; is gone -- it watches its parent and exits with it -- so it is dormant
        ; rather than dangerous. That is a reason to say where it is, not a
        ; reason to stay quiet about it.
        helperDirectory := ""
        try helperDirectory := SteamShellElevatedHelperDirectory()
        helperText := (helperDirectory != ""
            && FileExist(helperDirectory "\SteamShell-Helper.exe") != "")
            ? "`n`nThe elevated helper in " helperDirectory " was also left in "
                . "place. Nothing starts it once SteamShell is no longer the "
                . "shell; delete that folder as an administrator if you want it "
                . "removed."
            : ""
        SetupAssistantMsgBox(
            "The normal Windows desktop has been restored permanently.`n`n"
            . "SteamShell's files were left in place so your settings and EXE are not deleted."
            . shellText . helperText,
            "Iconi", "SteamShell Recovery")
    }
    return true
}

; Product-aware uninstall/restore.
;
; The two products need opposite things undone: the shell install has to give
; Windows its shell back, while the XFE install only has to stop starting itself
; at sign-in. Doing the wrong one is not harmless -- running the shell restore on
; an XFE machine would rewrite a Winlogon value SteamShell never set.
;
; The recorded product answers this. The dialog is the fallback for a missing or
; contradicted record, because a question the installer should be able to answer
; itself is a question that collects wrong answers.
ProductRemovalSelect(choice, *) {
    global ProductRemovalGui, ProductRemovalChoice
    ProductRemovalChoice := choice
    if IsSet(ProductRemovalGui) {
        try ProductRemovalGui.Destroy()
        ProductRemovalGui := unset
    }
}

; Asks which product to remove using buttons that name the products.
;
; This replaced a Yes/No/Cancel message box where Yes meant SteamShell and No
; meant SteamShell-XFE, which is not a question anyone can answer correctly from
; the buttons. It is also an owned window: the Setup Assistant is always-on-top,
; so an unowned dialog opens behind it and the user is left with a frozen
; assistant and nothing to click.
ChooseSteamShellProductToRemove(detail) {
    global ProductRemovalGui, ProductRemovalChoice
    global SetupAssistantGui, SettingsGui
    ProductRemovalChoice := "cancel"
    ownerHwnd := 0
    if IsSet(SetupAssistantGui) && IsGuiVisible(SetupAssistantGui)
        ownerHwnd := SetupAssistantGui.Hwnd
    else if IsSet(SettingsGui) && IsGuiVisible(SettingsGui)
        ownerHwnd := SettingsGui.Hwnd
    options := "+AlwaysOnTop +ToolWindow -Resize"
    if ownerHwnd
        options .= " +Owner" ownerHwnd
    ProductRemovalGui := Gui(options, "SteamShell Uninstall")
    ProductRemovalGui.Opt("+OwnDialogs")
    ProductRemovalGui.SetFont("s10", "Segoe UI")
    heading := ProductRemovalGui.AddText(
        "xm ym w620 h30", "Which installation should be removed?")
    heading.SetFont("s14 Bold", "Segoe UI")
    ProductRemovalGui.AddText("xm y+4 w620 h40 +Wrap", detail)

    shellButton := ProductRemovalGui.AddButton("xm y+14 w220 h36", "SteamShell")
    shellButton.OnEvent("Click", (*) => ProductRemovalSelect("standalone"))
    ProductRemovalGui.AddText(
        "x+14 yp+2 w380 h34 +Wrap",
        "The Windows shell replacement. Unregisters it and restores Explorer for the next sign-in.")

    xfeButton := ProductRemovalGui.AddButton("xm y+12 w220 h36", "SteamShell-XFE")
    xfeButton.OnEvent("Click", (*) => ProductRemovalSelect("xfe"))
    ProductRemovalGui.AddText(
        "x+14 yp+2 w380 h34 +Wrap",
        "The companion that runs alongside Xbox Full Screen Experience. Stops it starting at sign-in.")

    cancelButton := ProductRemovalGui.AddButton(
        "xm y+12 w220 h36 Default", "Cancel")
    cancelButton.OnEvent("Click", (*) => ProductRemovalSelect("cancel"))
    ProductRemovalGui.AddText(
        "x+14 yp+2 w380 h34 +Wrap",
        "Nothing is changed. No files or settings are removed either way.")

    ProductRemovalGui.OnEvent("Close", (*) => ProductRemovalSelect("cancel"))
    ProductRemovalGui.OnEvent("Escape", (*) => ProductRemovalSelect("cancel"))
    removalHwnd := ProductRemovalGui.Hwnd
    ProductRemovalGui.Show("AutoSize")
    CenterGuiOnTargetMonitor(ProductRemovalGui, ownerHwnd)
    WinWaitClose("ahk_id " removalHwnd)
    if ownerHwnd
        try WinActivate("ahk_id " ownerHwnd)
    return ProductRemovalChoice
}

RemoveSteamShellInstallationForProduct(showResult := true, restorePreviousShell := false, knownProduct := "") {
    ; A caller that has already identified the product says so, rather than
    ; letting this resolve it a second way and possibly reach a different answer.
    ; Setup Assistant detects from the Winlogon value and the scheduled task;
    ; re-deriving from the HKCU record here could fail where that succeeded and
    ; put an ambiguity prompt in front of a user who was never ambiguous.
    if (Trim(knownProduct) != "") {
        LogLine("Uninstall using the caller's resolved product: " knownProduct ".")
        return SteamShellProductIsXfe(knownProduct)
            ? RemoveSteamShellXfeInstallation(showResult)
            : RemoveSteamShellRegistration(showResult, restorePreviousShell)
    }
    if ResolveInstalledSteamShellProduct(&product, &detail) {
        LogLine("Uninstall resolved the installed product: " detail)
        return SteamShellProductIsXfe(product)
            ? RemoveSteamShellXfeInstallation(showResult)
            : RemoveSteamShellRegistration(showResult, restorePreviousShell)
    }
    ; Second opinion before giving up: the Winlogon value and the logon task are
    ; evidence the HKCU record is not.
    if DetectExistingSteamShellInstallation(
        &evidenceProduct, &evidenceDirectory, &evidenceShell, &evidenceTask) {
        LogLine(
            "Uninstall resolved the installed product from live evidence: "
            . evidenceProduct ".")
        return SteamShellProductIsXfe(evidenceProduct)
            ? RemoveSteamShellXfeInstallation(showResult)
            : RemoveSteamShellRegistration(showResult, restorePreviousShell)
    }

    LogLine("The installed product could not be resolved: " detail, "Warning")
    if !showResult {
        ; Unattended and ambiguous. Do nothing rather than guess at which of two
        ; system-level registrations to unwind.
        return false
    }
    choice := ChooseSteamShellProductToRemove(
        "SteamShell could not determine which product is installed on this PC. "
        . detail)
    if (choice = "standalone")
        return RemoveSteamShellRegistration(showResult, restorePreviousShell)
    if (choice = "xfe")
        return RemoveSteamShellXfeInstallation(showResult)
    LogLine("Uninstall was cancelled at the product prompt.")
    return false
}

HandleSteamShellCommandMode() {
    global IntentionalExitMode
    mode := GetSteamShellCommandMode()
    if (mode = "")
        return false

    if (mode = "install" || mode = "repair") {
        if !A_IsAdmin {
            PromptForAdministratorSetupAndExit()
            return true
        }
        commandSetupRequested := false
        if !ConsumeAdministratorSetupRequestMarker(
            &commandSetupRequested, &commandSetupError) {
            AbortAdministratorSetup(commandSetupError)
            return true
        }
        if (!commandSetupRequested
            && !ElevatedSetupMatchesInteractiveDesktop(&commandDesktopError)) {
            AbortAdministratorSetup(commandDesktopError)
            return true
        }
        if !CloseExistingSteamShellInstancesForElevatedSetup(&commandTakeoverDetail) {
            AbortAdministratorSetup(
                "SteamShell could not close every existing main/helper process. "
                . commandTakeoverDetail)
            return true
        }
        LogLine("Elevated command Setup takeover completed: " commandTakeoverDetail ".")
    }

    if (mode = "install")
        InstallOrRepairSteamShell(false, true)
    else if (mode = "repair")
        InstallOrRepairSteamShell(true, true)
    else if (mode = "restore")
        ; An emergency restore is always about the shell: it is the command a
        ; user reaches for when the desktop is gone, which cannot happen on an
        ; XFE machine. It stays product-independent on purpose.
        RemoveSteamShellRegistration(true, false)
    else if (mode = "uninstall")
        RemoveSteamShellInstallationForProduct(true, true)
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
    enable := ReadBool("StartupPrograms", "Enable", true)
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
    ; Once per session. The companion has no equivalent guard; its entry point is
    ; a single one-shot timer, so it does not need one today, and the asymmetry
    ; is now visible rather than implicit in two loop bodies.
    static started := false
    if (started)
        return
    started := true
    windowMode := NormalizeStartupWindowMode(
        IniReadS("StartupPrograms", "WindowMode", "Hidden"))
    staggerMs := ReadInt("StartupPrograms", "StaggerMs", 1200, 0, 30000)
    programs := ReadStartupProgramList(
        (key) => IniReadS("StartupPrograms", key, ""))
    SharedLaunchWithStagger(
        programs, staggerMs, (entry) => RunStartupCommandLine(entry, windowMode))
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
    ; The fullscreen tolerances moved into WindowEngineScoreWeights() with the
    ; shape test itself, so they are no longer read here.
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

    ; Hoisted for the same reason as the scoring loop's: nothing in the weights
    ; map can change while this loop runs.
    weights := WindowEngineScoreWeights()
    for _, item in WindowEngineGetFreshSnapshot() {
        minimizedLegacyGame := WindowEngineIsMinimizedLegacyGameSurface(item)
        legacySurface := WindowEngineIsLegacyApplicationSurface(item)
            || minimizedLegacyGame
        if (item["scriptOwned"] || item["desktop"] || item["bpm"]
            || (item["minMax"] = -1 && !minimizedLegacyGame)
            || (item["title"] = "" && !legacySurface)
            || item["proc"] = "" || ignore.Has(item["proc"]))
            continue
        ; Same shape verdict the scoring loop uses. This test was a second copy
        ; of those two expressions, constants and all, so a tolerance changed in
        ; one place silently disagreed with the other about what a game is.
        ; Only the shape matters here -- no score is computed, so no CPU or
        ; audio is sampled and the fast path stays fast.
        if GameWindowShapeVerdict(
            GameShapeFactsForWindow(item, minimizedLegacyGame),
            weights)["accepted"]
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

    ; This name is concatenated into a cmd.exe command line below, so it is
    ; re-validated here rather than trusted. Every current caller passes a name
    ; that ParseExeListPipe already checked against this same pattern; the point
    ; of repeating it is that the guarantee then belongs to this function instead
    ; of to the habits of its callers.
    if !RegExMatch(exe, "i)^[a-z0-9][a-z0-9_. -]*\.exe$") {
        LogLine("Launcher cleanup: refused an unsafe process name '" exeName "'.",
            "Warning")
        return Map("before", 0, "after", 0, "removed", 0)
    }

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
    try RunWait(A_ComSpec ' /c taskkill /F /T /IM "' exe '"', , "Hide")

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
    if !SharedPrepareStartupProgram(cmdline, &target, &params, &exeName, &directory)
        return false
    mode := NormalizeStartupWindowMode(windowMode)
    ; Through LaunchInteractiveApp, not Run: this product can be running
    ; elevated, and a child launched from an elevated shell INHERITS that token.
    pid := 0
    launched := LaunchInteractiveApp(
        target, params, "", mode, &pid, "Startup program: " target)
    if (launched && mode != "normal" && exeName != "")
        StartupWindowModeSweep(exeName, mode, A_TickCount + 6000)
    return launched
}

; Re-arms itself until the deadline. The old code made a single attempt 200 ms
; after launch, and only for "hidden" -- so "minimized" was a setting the editor
; offered, saved, and never applied.
StartupWindowModeSweep(exeName, mode, deadlineTick) {
    if !ApplyStartupWindowModeOnce(exeName, mode, deadlineTick)
        return
    SetTimer(() => StartupWindowModeSweep(exeName, mode, deadlineTick), -400)
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
SweepAbandonedSettingsUpdates()
EnsureSettingsIniUnicode()
SyncSettingsIniSchema()
LoadSettings()
; Read, compared and logged -- never acted on. InstallationMode, InstallDirectory
; and DataDirectory were written by Setup and consumed by nothing, so the record
; described the installation without ever being able to contradict it. A
; disagreement is worth a log line and is never worth refusing to start over:
; this is the Windows shell, and a stale path in a settings file must not be able
; to leave a machine with nothing to log in to.
LogSteamShellSetupRecordDrift(
    A_ScriptDir, SteamShellDataDir, SteamShellInstallationMode)
administratorSetupRequested := false
administratorSetupRequestError := ""
administratorSetupMarkerPresent := FileExist(
    AdministratorSetupRequestMarkerPath()) != ""
if A_IsAdmin && !ConsumeAdministratorSetupRequestMarker(
    &administratorSetupRequested, &administratorSetupRequestError) {
    AbortAdministratorSetup(administratorSetupRequestError)
    return
}
elevatedSetupTakeoverRequested := A_IsAdmin
    && OtherSteamShellSetupProcessExists()
FirstRunSetupMode := SetupAssistantRequired()
    || administratorSetupRequested
    || administratorSetupMarkerPresent
    || elevatedSetupTakeoverRequested

; Installation and upgrade are deliberate administrator-only maintenance
; sessions. A normal launch explains the required relaunch and exits instead of
; silently promoting the shell. The elevated replacement verifies the desktop
; identity, closes any same-user SteamShell/main-helper pair, and then opens the
; Explorer-backed Setup Assistant without starting the ordinary shell runtime.
if FirstRunSetupMode {
    if !A_IsAdmin {
        PromptForAdministratorSetupAndExit()
        return
    }
    if (!administratorSetupRequested
        && !ElevatedSetupMatchesInteractiveDesktop(&desktopIdentityError)) {
        AbortAdministratorSetup(desktopIdentityError)
        return
    }
    if !CloseExistingSteamShellInstancesForElevatedSetup(&takeoverDetail) {
        AbortAdministratorSetup(
            "SteamShell could not close every existing main/helper process. "
            . takeoverDetail
            . " Close the listed process in Task Manager and try again.")
        return
    }
    LogLine("Elevated Setup takeover completed: " takeoverDetail ".")
}

; Registered before Explorer is started so the TaskbarCreated broadcast that
; accompanies the first taskbar is never missed. Winlogon starts SteamShell
; before any shell exists, so the icon's first Shell_NotifyIcon attempt always
; fails and the broadcast is what actually places it.
InitializeTrayMenu()

if FirstRunSetupMode {
    StartFirstRunSetupSession()
} else if SafeMode {
    StartSafeModeSession()
} else {
    StartElevatedInputHelper()
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

    ; Establish a medium-integrity desktop shell only after the startup cover is
    ; present, but before any optional startup entry can require file association
    ; or protocol handling. Direct EXEs use the verified linked-token route and
    ; do not depend on Explorer.
    if !ProcessExist("explorer.exe") {
        explorerPid := 0
        LaunchInteractiveApp(
            A_WinDir "\explorer.exe", "", A_WinDir,
            "Normal", &explorerPid, "Background Explorer shell")
    }

    KickUserStartupPrograms()

    ; Armed after the startup entries that usually bring RTSS up. The tick polls
    ; for RTSS rather than launching it, and stops on the first successful
    ; restore or at its own deadline.
    SetTimer(RestoreRtssFrameLimitTick, 2000)

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

if !FirstRunSetupMode
    ApplyRuntimeTimers()

; Hotkeys (registered dynamically so they never break if code is refactored into functions)
Hotkey("^!+e", (*) => ExitToDesktop(true))
Hotkey("^!+r", (*) => ReloadSettings())
Hotkey("^!+g", (*) => ForceGameAssistOnce())
Hotkey("^!+p", (*) => ShowControlPanel())
Hotkey("^!+q", (*) => ToggleQuickMenu())
Hotkey("^!+s", (*) => ShowSettingsEditor())
; Same chord the companion uses. This is the re-arm path that is actually
; reachable when the thing that broke is the controller: the Settings button
; needs navigating to, and on a handheld there is nothing but the pad to navigate
; with. A keyboard is not always present either, but when one is, this is one
; keystroke instead of a restart.
Hotkey("^!+i", RearmControllerInput)
; The escape hatch for a bad learned controller profile, on the chord
; SteamShell-Shared.ahk's own comment beside DeleteControllerProfileForActiveDevice
; already states it is on. That function is defined in the shared file and
; compiled into both products, and the companion bound it here and in its
; Settings; this tree bound neither, so the only way to reach it was the
; automatic rest-check prompt.
;
; It matters MORE here than in the companion. A mis-learned axis reads as
; permanently deflected and the pointer runs across the screen, and this product
; is the Windows shell -- there is no desktop, no taskbar and no other
; application to fall back to. Both surfaces that CREATE such a profile, the
; tray's "Learn Controller…" and the Settings button, are offered by this tree.
Hotkey("^!+d", DeleteControllerProfileForActiveDevice)
RegisterQuickMenuKeys()

; Registers for WM_INPUT and starts decoding HID reports. Safe to call whichever
; backend is configured: it declines and says so when RawInput is not wanted,
; and when it is, RawInput still yields to XInput on its own if no reports
; arrive. A controller that already worked keeps working.
RawInputProbeStart()

; Sleep and resume. Registered unconditionally, like RawInputProbeStart above:
; PowerBroadcastMessage only resets a device lock and re-registers RawInput, both
; of which are no-ops when RawInput was never armed.
;
; This tree had no resume path of any kind -- the handler, the lock reset and the
; re-registration were all written in the companion and none of them were ever
; called here. The shell got by on RawInputClaimDevice's handover, which re-locks
; on the first report from a re-enumerated device; that covers a stale handle and
; does nothing at all for a registration that did not come back.
;
; Not sufficient on its own, and deliberately not the only trigger: an ROG Ally
; sleeps into modern standby, where this message is not reliably delivered. The
; wall-clock detector in PollController is the one that actually fires there.
OnMessage(0x0218, PowerBroadcastMessage)

; Device arrival and removal, so a controller plugged in while the XInput sweep
; is backed off is picked up on the next poll rather than up to 250ms later.
; Purely an accelerator: if the broadcast never arrives the backoff expires by
; itself and nothing depends on this having worked.
OnMessage(0x0219, DeviceChangeMessage)

if SafeMode && !FirstRunSetupMode
    SetTimer(ShowSettingsEditor, -400)

; Seam for SteamShell-Shared.ahk. The window engine's scored best candidate is
; this tree's answer to "what game is running".
ProductBestGameExe() {
    global LastBestCandidateProc
    return LastBestCandidateProc
}

; Seam for SteamShell-Shared.ahk: where this product keeps files it writes.
;
; Read live rather than captured, because this one moves. Setup's takeover
; rewrites it from the installation record, a portable run points it at
; A_ScriptDir, and choosing a data directory during installation reassigns it
; again -- so a shared caller asking mid-run has to get the current answer.
ProductDataDir() {
    global SteamShellDataDir
    return SteamShellDataDir
}

; Seams for the shared health harness.
ProductVersionText() {
    global SteamShellVersion
    return SteamShellVersion
}

ProductCenterGui(guiObj) {
    CenterGuiOnTargetMonitor(guiObj)
}

; Seam for SteamShell-Shared.ahk. This tree checks the process exists AND
; re-verifies its identity on a one-second cache, which is stronger than the
; companion needs but is what this product already had.
ProductElevatedHelperAlive() {
    return ElevatedHelperIsVerified()
}

; Seams for the shared controller mapping editor.
;
; This tree stages a batch through CommitIniChanges, which writes into a copy and
; moves it over the original, so a failure part-way leaves the old file intact.
ProductSaveControllerMappings() {
    return SaveControllerMappingsToIni()
}

; Shell bookkeeping: which real window was in front before one of ours took the
; foreground. The companion has no equivalent and needs none.
ProductCaptureLastRealForeground() {
    CaptureLastRealForeground()
}

; Seams for the shared settings scrollbar. This tree keeps the content bounds
; in two globals; the companion computes them from SettingsLayout().
ProductSettingsScrollBar() {
    global SettingsEditorScrollBar
    return IsObject(SettingsEditorScrollBar) ? SettingsEditorScrollBar : ""
}

ProductSettingsViewportHeight() {
    global SettingsEditorContentTop, SettingsEditorContentBottom
    return Max(1, SettingsEditorContentBottom - SettingsEditorContentTop)
}

RunViaDesktopShell(filePath, arguments := "", directory := "", show := 1) {
    ; ShellExecute through Explorer's desktop automation object so an elevated
    ; SteamShell does not force ordinary interactive utilities such as TabTip to
    ; inherit its administrator token.
    static VT_UI4 := 0x13
    static SWC_DESKTOP := ComValue(VT_UI4, 0x8)
    static DESKTOP_BROKER_TIMEOUT_MS := 10000
    startedTick := A_TickCount
    attempts := 0
    lastError := "Explorer's desktop automation object was unavailable."

    ; Shell_TrayWnd can exist shortly before Explorer publishes its desktop COM
    ; automation object during a cold boot. Keep verifying the broker identity
    ; while that object finishes initializing instead of treating this normal
    ; readiness gap as a Steam launch failure.
    Loop {
        if !DesktopShellMatchesInteractiveUser(&shellReason) {
            try LogLine(
                "Desktop-shell launch rejected for " filePath ": " shellReason,
                "Warning")
            return false
        }

        attempts += 1
        try {
            desktopWindow := ComObject("Shell.Application").Windows.Item(SWC_DESKTOP)
            desktopApplication := desktopWindow.Document.Application
            desktopApplication.ShellExecute(
                filePath, arguments, directory, "open", show)
            if (attempts > 1) {
                try LogLine(
                    "Desktop-shell broker became ready after "
                    . (A_TickCount - startedTick) " ms for " filePath ".")
            }
            return true
        } catch as err {
            lastError := err.Message
        }

        if (A_TickCount - startedTick >= DESKTOP_BROKER_TIMEOUT_MS)
            break
        Sleep 200
    }

    try LogLine(
        "Desktop-shell launch failed for " filePath " after " attempts
        . " attempts: " lastError,
        "Warning")
    return false
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

; Seam for the shared EnsureRtssRunning. This tree starts RTSS through
; LaunchInteractiveApp so that IF the shell has been started elevated the token
; is not inherited; the companion has no such contingency and simply Runs it.
; That was the whole of the difference between the two copies.
ProductLaunchMinimized(path, directory) {
    pid := 0
    return LaunchInteractiveApp(path, "", directory, "Minimized", &pid, "RTSS")
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
    btnCancel.OnEvent("Click", RecordShortcutCancel)
    cap.OnEvent("Close", RecordShortcutCancel)
    cap.OnEvent("Escape", RecordShortcutCancel)

    ; Suppress the chord while recording so Win, Alt, and application shortcuts
    ; do not execute behind this dialog.
    ih := InputHook()
    ih.NotifyNonText := true
    ih.KeyOpt("{All}", "NS")
    ih.OnKeyDown := RecordShortcutChord_OnKeyDown
    ih.OnKeyUp := RecordShortcutChord_OnKeyUp
    _ShortcutCap["input"] := ih

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
    _ShortcutCap["input"].Stop()
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

AutoMouseModeActive() {
    global EnableAutoMouseMode, EnablePersistentMouseMode, AutoMouseExeSet, ScriptPid, DesktopMode
    global EnableDesktopAutoMouseMode, DesktopAutoMouseExcludeExeSet
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
    if (DesktopMode && !EnableDesktopAutoMouseMode)
        return false
    if (!DesktopMode && AutoMouseExeSet.Count = 0)
        return false
    if (cachedTick && A_TickCount - cachedTick < 250)
        return cachedResult
    cachedTick := A_TickCount
    cachedResult := false
    try {
        hwnd := DllCall("User32\GetForegroundWindow", "Ptr")
        if (hwnd && WinGetPID("ahk_id " hwnd) != ScriptPid) {
            foregroundExe := StrLower(WinGetProcessName("ahk_id " hwnd))
            cachedResult := DesktopMode
                ? !DesktopAutoMouseExcludeExeSet.Has(foregroundExe)
                : AutoMouseProcessMatches(foregroundExe)
        }
    }
    return cachedResult
}
