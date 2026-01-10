; ==============================================================================
; SteamShell — BPM Kiosk Shell (AutoHotkey v2.0.19 compatible)
; ------------------------------------------------------------------------------
; Hotkeys:
; Ctrl+Alt+Shift+E => Exit to desktop (permanent restore)
; Ctrl+Alt+Shift+R => Reload INI settings
; Ctrl+Alt+Shift+G => Run Game Assist immediately (one-shot)
; Ctrl+Alt+Shift+P => Open Control Panel (session toggles / timed disable / live log viewer)
; ==============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
DEFAULT_AUDIO_PEAK_THRESHOLD := 0.02  ; Default audio peak threshold (0.0–1.0). Can be overridden in INI.
AudioPeakThreshold := DEFAULT_AUDIO_PEAK_THRESHOLD
SetTitleMatchMode 2
Persistent

; Prefer Input mode for synthetic keystrokes (more reliable for system chords)
SendMode "Input"


; ==============================================================================
; FILE PATHS
; ==============================================================================
global SettingsPath := A_ScriptDir "\SteamShellSettings.ini"
; Back-compat alias used by some helper functions
global IniPath := SettingsPath
global LogPath := A_ScriptDir "\SteamShell.log"
global ShellRegKey := "HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"

; Cache our own PID once so window-management can reliably ignore this script's GUIs.
global ScriptPid := DllCall("GetCurrentProcessId", "UInt")
global LastRealFgHwnd := 0 ; last foreground window not owned by this script

; ==============================================================================
; DEFAULT SETTINGS (INI overrides these)
; ==============================================================================
global SteamPath := "C:\Program Files (x86)\Steam\Steam.exe"
global BpmTitle := "Steam Big Picture Mode"

; Feature toggles
global EnableSplashScreen := true
global EnableTaskbarHiding := true
global EnableWindowManagement := true
global EnableAutoHideCursor := true
global EnableSteamRefocusMode := true
global EnableGameForegroundAssist := true
global EnableAlwaysFocus := true
global EnableMouseParkOnBoot := true
global EnableMouseParkEveryRefocus := true


; Controller-to-mouse (XInput / Xbox controller)
global EnableControllerMouseMode := true ; Enable controller mouse/keyboard mapping
global ControllerIndex := 0 ; 0 = first controller
global ControllerPollIntervalMs := 16 ; Poll rate (ms)
global ControllerDeadzone := 8000 ; Stick deadzone (0-32767)
global ControllerMouseSpeed := 100 ; Pixels per poll tick at full deflection
global ControllerMouseFastMultiplier:= 2.5 ; Multiplier when RT is held (fast move)
global ControllerScrollIntervalMs := 80 ; Min ms between scroll ticks
global ControllerScrollStep := 1 ; Wheel notches per scroll tick
global ControllerChordHoldMs := 500 ; Long-press threshold (ms) for View/Back + button secondary actions

; Controller mapping configuration (short/long press while holding View/Back)
global ControllerMap := Map() ; key => mapping string ("Builtin:..." or "Send:...")
global ControllerMapDisplay := Map() ; key => pretty display for Send: mappings
InitDefaultControllerMappings()
; Launcher cleanup (optional)
global EnableLauncherCleanup := false ; Close selected launchers/services after Steam is foreground for N seconds
global LauncherCleanupSteamForegroundSec := 30 ; Required seconds Steam stays foreground before cleanup runs
global LauncherCleanupRequireNoGame := true ; Skip cleanup if a game-like fullscreen/borderless window is detected
global LauncherCleanupCooldownSec := 300 ; Minimum seconds between cleanup runs
global LauncherCleanupCheckIntervalMs := 2000 ; Timer interval for checking conditions
global LauncherCleanupGracefulCloseMs := 4000 ; Wait after WinClose before hard-killing
global LauncherCleanupHardKill := true ; If true, hard-kill any remaining launcher/service processes after GracefulCloseMs
global LauncherCleanupUseCpuAudio := true ; Use CPU/audio heuristics (more reliable than window size alone)
global LauncherCleanupCpuThreshold := 12 ; CPU % threshold to consider "game running" (0 disables CPU check)
global LauncherCleanupAudioPeakThreshold := 0.02 ; Audio peak threshold for Launcher Cleanup (0.0–1.0)
global LauncherCleanupDownloadGuard := false ; If true, skip cleanup while launchers appear busy (possible download/update)
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

global WindowCheckInterval := 500
global SteamRefocusPollingInterval := 1000
global MouseMonitorInterval := 250
global MouseHideDelay := 1000
global SteamRefocusDelay := 3000

; Window management
global MinWidthPercent := 0.20

; Window management exclusion lists (INI-driven)
global WmExcludeExeListRaw := "" ; Pipe-separated EXEs to skip in auto center/max
global WmExcludeClassListRaw := "" ; Pipe-separated Win32 classes to skip in auto center/max
global WmExcludeExeSet := Map() ; Built from WmExcludeExeListRaw
global WmExcludeClassSet := Map() ; Built from WmExcludeClassListRaw

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
global GameMinScoreToActivate := 60

; Audio assist
global EnableAudioAssist := true
global ScoreAudioActive := 30

; Mouse park
global MouseParkRightOffsetPx := 50
global MouseParkYPercent := 0.50

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
global OriginalShell := "explorer.exe"
global AllowExplorer := false
global SystemReady := false
global SteamLaunched := false

global SplashGui := unset

global LastMouseX := 0
global LastMouseY := 0
global MouseHidden := false
global LastMouseMoveTick := 0

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
global CPStat1Ctrl := unset, CPStat2Ctrl := unset, CPStat3Ctrl := unset, CPStat4Ctrl := unset
global LLStat1Ctrl := unset, LLStat2Ctrl := unset, LLStat3Ctrl := unset, LLStat4Ctrl := unset

; tail viewer state
global PanelLogMaxLines := 200
global DetachedLogMaxLines := 300


; controller mouse mode state (XInput)
global XInputDll := ""
global ControllerDragLock := false
; ==============================================================================
; ADMIN + CAPTURE CURRENT SHELL
; ==============================================================================
try {
 OriginalShell := RegRead(ShellRegKey, "Shell")
} catch {
 OriginalShell := A_ScriptFullPath
}

if !A_IsAdmin {
 try Run("*RunAs " A_ScriptFullPath)
 ExitApp()
}

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
EnsureSettingsIniExists() {
 global SettingsPath
 if FileExist(SettingsPath)
 return

 txt := "
(
; ==================================================================================================
; SteamShellSettings.ini (auto-generated)
; - Edit values, then reboot OR press Ctrl+Alt+Shift+R to reload.
; - Booleans: true / false
; - If you break things: delete this file and it will be recreated.
; - Comments start with ';' (everything after it is ignored by SteamShell).
; - Control Panel: Ctrl+Alt+Shift+P (session toggles / timed disable / live log viewer).
; ==================================================================================================

[Paths]
SteamPath=C:\Program Files (x86)\Steam\Steam.exe            ; Full path to Steam.exe

[BPM]
BpmTitle=Steam Big Picture Mode                             ; Big Picture window title (must match your BPM title)

[Features]
EnableSplashScreen=true                                     ; Show a black splash overlay during boot
EnableTaskbarHiding=true                                    ; Hide taskbar & tray windows (kiosk feel)
EnableWindowManagement=true                                 ; Center windows; maximize large windows (skips OSK + Steam KB)
EnableAutoHideCursor=true                                   ; Hide cursor after MouseHideDelay inactivity
EnableSteamRefocusMode=true                                 ; Refocus BPM after SteamRefocusDelay when nothing else is visible
EnableGameForegroundAssist=true                             ; Detect fullscreen-ish games and bring them to front
EnableAlwaysFocus=true                                      ; Allow specific apps (ExeList) to always win focus over Steam
EnableMouseParkOnBoot=true                                  ; Park cursor off-screen to the right at startup
EnableMouseParkEveryRefocus=true                            ; Park cursor off-screen whenever SteamShell activates a window

[Timing]
SplashScreenDuration=10000                                  ; Splash duration in milliseconds (0 disables fade)
WindowCheckInterval=500                                     ; How often to center/maximize new windows (ms)
SteamRefocusPollingInterval=1000                            ; How often to run focus checks (ms)
MouseMonitorInterval=250                                    ; Mouse polling interval (ms)
MouseHideDelay=1000                                         ; Hide cursor after this many ms without movement
SteamRefocusDelay=3000                                      ; Wait this many ms before refocusing BPM (when no windows remain)


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
GameMinScoreToActivate=60                                   ; Minimum score required to activate the best candidate

[Logging]
EnableGameScoreLogging=false                                ; Write scoring/decisions to SteamShell.log
GameLogMode=OFF                                             ; OFF|ACTIVATIONS|TOPN|DIAGNOSTIC
GameLogTopN=3                                               ; When TOPN/DIAGNOSTIC, log this many top candidates
GameLogIntervalMs=3000                                      ; Rate limit for TOPN/DIAGNOSTIC logging
GameLogIncludeTitles=true                                   ; Include window titles in the log
GameLogRejectNearCandidates=true                            ; In DIAGNOSTIC, also log near-fullscreen rejects
GameLogRejectMinAreaPercent=0.85                            ; Only log rejects with >= this % of screen area
GameLogRotateMaxKB=256                                      ; Rotate log when it exceeds this many KB
GameLogRotateBackups=2                                      ; Keep this many rotated backups

[MousePark]
MouseParkRightOffsetPx=50                                   ; Park cursor this many px beyond the right edge
MouseParkYPercent=0.50                                      ; Park cursor at this % of screen height



[StartupPrograms]
Enable=false                                                ; Start additional user-defined programs at boot (hidden)
DelayMs=2000                                                ; Wait this long after SteamShell starts before launching them
; Define programs as Program1..Program20. Format:
; ProgramN="C:\Path\App.exe" --arg1 --arg2
; Quotes recommended if the path contains spaces. Everything after the exe is treated as arguments.
; Programs are started with Run(..., "Hide") and SteamShell will also attempt to hide any windows they create briefly.
Program1=
Program2=

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
HardKill=true


; Advanced (only used when RequireNoGame=true and UseCpuAudio=true)
UseCpuAudio=true
CpuThreshold=12
AudioPeakThreshold=0.02
; Busy guard (optional): skip cleanup if launchers appear to be actively downloading/updating
DownloadGuard=false
DownloadGuardMode=Balanced
; Pipe-separated EXEs (case-insensitive). If an entry has no .exe, it will be appended.
LauncherExeList=UbisoftConnect.exe|upc.exe|EpicGamesLauncher.exe|EADesktop.exe|EALauncher.exe|Origin.exe|Battle.net.exe|RockstarGamesLauncher.exe|GalaxyClient.exe|RiotClientServices.exe|RiotClientUx.exe|wgc.exe|Heroic.exe
BackgroundExeList=UbisoftConnectService.exe|UplayWebCore.exe|UplayService.exe|EpicWebHelper.exe|EABackgroundService.exe|BlizzardUpdateAgent.exe|Agent.exe|RockstarService.exe|SocialClubHelper.exe|GalaxyClientService.exe|GalaxyCommunication.exe|RiotClientUxRender.exe|legendary.exe|gogdl.exe|nile.exe

; Safety: never kill these
ExcludeExeList=steam.exe|steamwebhelper.exe|SteamShell.exe

[Controller]
EnableControllerMouseMode=true                              ; Enable controller mouse/keyboard mapping (hold View/Back)
ControllerIndex=0                                           ; 0=first controller
ControllerPollIntervalMs=16                                 ; Poll rate (ms)
ControllerDeadzone=8000                                     ; Stick deadzone (0-32767)
ControllerMouseSpeed=100                                    ; Pixels per poll tick at full deflection
ControllerMouseFastMultiplier=2.5                           ; Multiplier while RT is held
ControllerScrollIntervalMs=80                               ; Min ms between scroll ticks
ControllerScrollStep=1                                      ; Wheel notches per scroll tick
ControllerChordHoldMs=500                                   ; Long-press threshold (ms) for B/X/Y secondary actions
)"
 try FileAppend(txt, SettingsPath, "UTF-8")
}

CleanIniValue(v, default := "") {
 v := Trim(v)
 if (v = "")
 return default

 pos := RegExMatch(v, "\s[;#]")
 if (pos)
 v := Trim(SubStr(v, 1, pos - 1))

 if (v = "")
 return default

 return v
}

IniReadS(section, key, default := "") {
 global SettingsPath
 v := default
 try {
 v := IniRead(SettingsPath, section, key, default)
 } catch {
 v := default
 }
 return CleanIniValue(v, default)
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
 return RegExMatch(s, "^-?\d+(\.\d+)?$") ? (s + 0.0) : default
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

WriteBoolIni(section, key, b) {
 global SettingsPath
 try IniWrite(b ? "true" : "false", SettingsPath, section, key)
}

LoadSettings() {
    global AudioPeakThreshold, DEFAULT_AUDIO_PEAK_THRESHOLD
    AudioPeakThreshold := ClampFloat(ToFloat(IniReadS("GameForegroundAssist","AudioPeakThreshold","0.02"), DEFAULT_AUDIO_PEAK_THRESHOLD), 0.0, 1.0)
 global SteamPath, BpmTitle
 global EnableSplashScreen, EnableTaskbarHiding, EnableWindowManagement, EnableAutoHideCursor
 global EnableSteamRefocusMode, EnableGameForegroundAssist, EnableAlwaysFocus
 global EnableMouseParkOnBoot, EnableMouseParkEveryRefocus
 global SplashScreenDuration, WindowCheckInterval, SteamRefocusPollingInterval, MouseMonitorInterval
 global SplashMode, SplashVideoPath, SplashVideoMute, SplashVideoPlayFull, SplashVideoSafetyMaxMs, SplashFadeOutMs, SplashTopmostGuardMs
 global SplashMpvPath, SplashDebugOverlay, SplashForceSDR, SplashMpvPid, SplashMpvHwnd, SplashFailReason
 global MouseHideDelay, SteamRefocusDelay
 global MinWidthPercent
 global WmExcludeExeListRaw, WmExcludeClassListRaw, WmExcludeExeSet, WmExcludeClassSet
 global AlwaysFocusExeListRaw, AlwaysFocusCooldownMs, AlwaysFocusList
 global GameCPUThresholdPercent, FullscreenTolerance, FullscreenPosTolerancePx, GameForegroundCooldownMs
 global GameAllowZeroCpuAsCandidate, GameRequireSteamForeground, GameAssistLogEvenWhenSkipped
 global ScoreFullscreen, ScoreBorderlessLarge, ScoreTitleBonus
 global ScoreCpuAboveThreshold, ScoreCpuNonZeroBonus, GameMinScoreToActivate
 global EnableAudioAssist, ScoreAudioActive
 global EnableGameScoreLogging, GameLogMode, GameLogTopN, GameLogIntervalMs, GameLogIncludeTitles
 global GameLogRejectNearCandidates, GameLogRejectMinAreaPercent, GameLogRotateMaxKB, GameLogRotateBackups
 global MouseParkRightOffsetPx, MouseParkYPercent
 global EnableLauncherCleanup, LauncherCleanupSteamForegroundSec, LauncherCleanupRequireNoGame, LauncherCleanupUseCpuAudio, LauncherCleanupCpuThreshold, LauncherCleanupAudioPeakThreshold, LauncherCleanupDownloadGuard, LauncherCleanupDownloadGuardMode
 global LauncherCleanupCooldownSec, LauncherCleanupCheckIntervalMs, LauncherCleanupGracefulCloseMs, LauncherCleanupHardKill
 global LauncherCleanupLauncherExeListRaw, LauncherCleanupBackgroundExeListRaw, LauncherCleanupExcludeExeListRaw
 global LauncherCleanupLauncherList, LauncherCleanupBackgroundList, LauncherCleanupExcludeSet
global EnableControllerMouseMode, ControllerIndex, ControllerPollIntervalMs, ControllerDeadzone, ControllerMouseSpeed, ControllerMouseFastMultiplier, ControllerScrollIntervalMs, ControllerScrollStep

 SteamPath := IniReadS("Paths", "SteamPath", SteamPath)
 BpmTitle := IniReadS("BPM", "BpmTitle", BpmTitle)

 EnableSplashScreen := ToBool(IniReadS("Features","EnableSplashScreen","true"), true)
 EnableTaskbarHiding := ToBool(IniReadS("Features","EnableTaskbarHiding","true"), true)
 EnableWindowManagement := ToBool(IniReadS("Features","EnableWindowManagement","true"), true)
 EnableAutoHideCursor := ToBool(IniReadS("Features","EnableAutoHideCursor","true"), true)
 EnableSteamRefocusMode := ToBool(IniReadS("Features","EnableSteamRefocusMode","true"), true)
 EnableGameForegroundAssist := ToBool(IniReadS("Features","EnableGameForegroundAssist","true"), true)
 EnableAlwaysFocus := ToBool(IniReadS("Features","EnableAlwaysFocus","true"), true)
 EnableMouseParkOnBoot := ToBool(IniReadS("Features","EnableMouseParkOnBoot","true"), true)
 EnableMouseParkEveryRefocus := ToBool(IniReadS("Features","EnableMouseParkEveryRefocus","true"), true)

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

 WindowCheckInterval := ClampInt(ToInt(IniReadS("Timing","WindowCheckInterval","500"), 500), 50, 5000)
 SteamRefocusPollingInterval := ClampInt(ToInt(IniReadS("Timing","SteamRefocusPollingInterval","1000"), 1000), 100, 10000)
 MouseMonitorInterval := ClampInt(ToInt(IniReadS("Timing","MouseMonitorInterval","250"), 250), 50, 5000)
 MouseHideDelay := ClampInt(ToInt(IniReadS("Timing","MouseHideDelay","1000"), 1000), 0, 60000)
 SteamRefocusDelay := ClampInt(ToInt(IniReadS("Timing","SteamRefocusDelay","3000"), 3000), 0, 60000)

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

 AlwaysFocusExeListRaw := IniReadS("AlwaysFocus","ExeList","")
 AlwaysFocusCooldownMs := ClampInt(ToInt(IniReadS("AlwaysFocus","AlwaysFocusCooldownMs","1000"), 1000), 0, 60000)
 AlwaysFocusList := EnableAlwaysFocus ? ParseExeListPipe(AlwaysFocusExeListRaw) : []

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
 GameMinScoreToActivate := ClampInt(ToInt(IniReadS("GameForegroundAssist","GameMinScoreToActivate","60"), 60), 0, 300)

 EnableGameScoreLogging := ToBool(IniReadS("Logging","EnableGameScoreLogging","false"), false)
 GameLogMode := StrUpper(IniReadS("Logging","GameLogMode","OFF"))
 GameLogTopN := ClampInt(ToInt(IniReadS("Logging","GameLogTopN","3"), 3), 1, 10)
 GameLogIntervalMs := ClampInt(ToInt(IniReadS("Logging","GameLogIntervalMs","3000"), 3000), 250, 60000)
 GameLogIncludeTitles := ToBool(IniReadS("Logging","GameLogIncludeTitles","true"), true)
 GameLogRejectNearCandidates := ToBool(IniReadS("Logging","GameLogRejectNearCandidates","true"), true)
 GameLogRejectMinAreaPercent := ClampFloat(ToFloat(IniReadS("Logging","GameLogRejectMinAreaPercent","0.85"), 0.85), 0.10, 1.00)
 GameLogRotateMaxKB := ClampInt(ToInt(IniReadS("Logging","GameLogRotateMaxKB","256"), 256), 32, 8192)
 GameLogRotateBackups := ClampInt(ToInt(IniReadS("Logging","GameLogRotateBackups","2"), 2), 0, 10)

 MouseParkRightOffsetPx := ClampInt(ToInt(IniReadS("MousePark","MouseParkRightOffsetPx","50"), 50), 0, 5000)
 MouseParkYPercent := ClampFloat(ToFloat(IniReadS("MousePark","MouseParkYPercent","0.50"), 0.50), 0.0, 1.0)

 ; Launcher cleanup (optional)
 EnableLauncherCleanup := ToBool(IniReadS("LauncherCleanup","Enable","false"), false)
 LauncherCleanupSteamForegroundSec := ClampInt(ToInt(IniReadS("LauncherCleanup","SteamForegroundSec","30"), 30), 1, 600)
 LauncherCleanupRequireNoGame := ToBool(IniReadS("LauncherCleanup","RequireNoGame","true"), true)
 LauncherCleanupCooldownSec := ClampInt(ToInt(IniReadS("LauncherCleanup","CooldownSec","300"), 300), 0, 86400)
 LauncherCleanupCheckIntervalMs := ClampInt(ToInt(IniReadS("LauncherCleanup","CheckIntervalMs","2000"), 2000), 200, 60000)
 LauncherCleanupGracefulCloseMs := ClampInt(ToInt(IniReadS("LauncherCleanup","GracefulCloseMs","4000"), 4000), 0, 60000)
 LauncherCleanupHardKill := ToBool(IniReadS("LauncherCleanup","HardKill","true"), true)

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
 ControllerDeadzone := ClampInt(ToInt(IniReadS("Controller","ControllerDeadzone","8000"), 8000), 0, 32000)
 ControllerMouseSpeed := ClampInt(ToInt(IniReadS("Controller","ControllerMouseSpeed","35"), 35), 1, 200)
 ControllerMouseFastMultiplier := ClampFloat(ToFloat(IniReadS("Controller","ControllerMouseFastMultiplier","2.5"), 2.5), 1.0, 10.0)
 ControllerScrollIntervalMs := ClampInt(ToInt(IniReadS("Controller","ControllerScrollIntervalMs","80"), 80), 10, 1000)
 ControllerScrollStep := ClampInt(ToInt(IniReadS("Controller","ControllerScrollStep","1"), 1), 1, 10)
 ControllerChordHoldMs := ClampInt(ToInt(IniReadS("Controller","ControllerChordHoldMs","500"), 500), 100, 2000)
 LoadControllerMappings()
}

ApplyRuntimeTimers() {
 global WindowCheckInterval, SteamRefocusPollingInterval, MouseMonitorInterval
 global EnableWindowManagement, EnableAutoHideCursor
 global EnableSteamRefocusMode, EnableGameForegroundAssist, EnableAlwaysFocus
  global EnableLauncherCleanup, LauncherCleanupCheckIntervalMs
global EnableControllerMouseMode, ControllerPollIntervalMs

 SetTimer(MonitorShell, 0)
 SetTimer(CheckWindows, 0)
 SetTimer(MouseWatch, 0)
 SetTimer(SteamRefocusPolling, 0)
 SetTimer(PollController, 0)
 SetTimer(CheckLauncherCleanup, 0)

 SetTimer(MonitorShell, WindowCheckInterval)

 if (EnableWindowManagement)
 SetTimer(CheckWindows, WindowCheckInterval)

 if (EnableAutoHideCursor)
 SetTimer(MouseWatch, MouseMonitorInterval)

 if (EnableSteamRefocusMode || EnableGameForegroundAssist || EnableAlwaysFocus)
 SetTimer(SteamRefocusPolling, SteamRefocusPollingInterval)

 if (EnableControllerMouseMode)
 SetTimer(PollController, ControllerPollIntervalMs)

 if (EnableLauncherCleanup)
 SetTimer(CheckLauncherCleanup, LauncherCleanupCheckIntervalMs)
}

ReloadSettings() {
 LoadSettings()
 ApplyRuntimeTimers()
 SyncControlPanel()
 RefreshAlwaysFocusManagerLists()
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




GetClientRectPx(hwnd, &w, &h) {
 ; Returns client size in physical pixels.
 w := 0, h := 0
 rc := Buffer(16, 0)
 if DllCall("User32\GetClientRect", "ptr", hwnd, "ptr", rc, "int") {
 w := NumGet(rc, 8, "int")
 h := NumGet(rc, 12, "int")
 }
}

GetPrimaryMonitorRect(&L, &T, &R, &B) {
 ; Returns the full bounds of the primary monitor in screen coordinates.
 try {
 MonitorGet(1, &L, &T, &R, &B)
 } catch {
 L := 0, T := 0, R := A_ScreenWidth, B := A_ScreenHeight
 }
}

ForceGuiFullscreen(guiObj) {
 ; Moves/resizes a GUI to exactly cover the primary monitor.
 GetPrimaryMonitorRect(&L, &T, &R, &B)
 try WinMove(L, T, R - L, B - T, "ahk_id " guiObj.Hwnd)
}

GetGuiClientSize(guiObj, &W, &H) {
 ; Get client size (usable area) in pixels for a GUI window.
 W := 0, H := 0
 try {
 WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " guiObj.Hwnd)
 W := cw, H := ch
 } catch {
 ; fallback: use monitor size
 GetPrimaryMonitorRect(&L, &T, &R, &B)
 W := R - L, H := B - T
 }
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
SplashKeepOnTop() {
 global SplashGui, SplashMpvPid, SplashMpvHwnd, SplashOverlayGui

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
FadeInOverlay(ms) {
 global SplashOverlayGui
 if !IsSet(SplashOverlayGui)
 return
 if (ms <= 0) {
 try SetGuiTransparency(255, SplashOverlayGui)
 return
 }
 steps := 30
 sleepMs := Ceil(ms / steps)
 if (sleepMs < 10)
 sleepMs := 10
 if (sleepMs > 60)
 sleepMs := 60

 Loop steps {
 trans := Round((A_Index / steps) * 255)
 if (trans > 255)
 trans := 255
 try SetGuiTransparency(trans, SplashOverlayGui)
 Sleep(sleepMs)
 }
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
ParkMouseRightEdge() {
 global MouseParkRightOffsetPx, MouseParkYPercent
 x := A_ScreenWidth + MouseParkRightOffsetPx
 y := Round(A_ScreenHeight * MouseParkYPercent)
 MouseMove(x, y, 0)
}

MaybeParkMouseOnRefocus() {
 global EnableMouseParkEveryRefocus
 if (EnableMouseParkEveryRefocus)
 ParkMouseRightEdge()
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

OpenTouchKeyboard() {
 ; Force-open the modern touch keyboard (TabTip).
 ; On many systems TabTip/TextInputHost stays running after first use and won't re-show.
 ; This implementation:
 ; 1) Activates it if already visible
 ; 2) Otherwise, restarts TabTip/TextInputHost and launches TabTip again
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

 ; Some builds keep TabTip/TextInputHost running but invisible and ignore relaunch.
 ; Cleanest user-requested behavior: restart them before launching.
 try ProcessClose("TabTip.exe")
 try ProcessClose("TextInputHost.exe")
 Sleep 150

 ; Try launching TabTip (with quotes for paths).
 try {
 if FileExist(tabtip1) {
 cmd := '"' tabtip1 '"'
 Run(cmd)
 } else if (tabtip2 != "" && FileExist(tabtip2)) {
 cmd := '"' tabtip2 '"'
 Run(cmd)
 } else {
 Run("osk.exe")
 return
 }
 } catch {
 try Run("osk.exe")
 return
 }

 ; If it appeared, ensure it's visible.
 if WinWait("ahk_class IPTip_Main_Window", , 1) {
 try WinShow("ahk_class IPTip_Main_Window")
 try WinActivate("ahk_class IPTip_Main_Window")
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


 ; Start/Menu (default: unassigned)
 ControllerMap["Start.Short"] := "Builtin:None"
 ControllerMap["Start.Long"] := "Builtin:None"


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
}

SaveControllerMappingsToIni() {
 global IniPath, ControllerMap, ControllerMapDisplay
 for k, v in ControllerMap {
 try IniWrite(v, IniPath, "ControllerMap", k)
 if (SubStr(v, 1, 5) = "Send:") {
 disp := ""
 disp := ""
 try disp := ControllerMapDisplay[k]
 if (disp != "")
 try IniWrite(disp, IniPath, "ControllerMap", k ".Display")
 } else {
 ; remove stale display values for builtins
 try IniDelete(IniPath, "ControllerMap", k ".Display")
 }
 }
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
 case "CtrlAltTab":
 SendChordSafe("^!{Tab}")
 case "TaskManager":
 SendChordSafe("^+{Esc}")
 default:
 ; unknown builtin - ignore
 }
}

SendToPretty(sendStr) {
 ; Best-effort human-friendly label for common chords.
 s := sendStr
 s := StrReplace(s, "#", "Win+")
 s := StrReplace(s, "^", "Ctrl+")
 s := StrReplace(s, "!", "Alt+")
 s := StrReplace(s, "+", "Shift+")
 s := RegExReplace(s, "\{Tab\}", "Tab")
 s := RegExReplace(s, "\{Esc\}", "Esc")
 s := RegExReplace(s, "\{Escape\}", "Esc")
 s := RegExReplace(s, "\{Enter\}", "Enter")
 s := RegExReplace(s, "\{F4\}", "F4")
 ; Collapse duplicates like Ctrl+Alt+Tab (from replacements)
 return s
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

 ih := InputHook("V")
 ih.NotifyNonText := true
 ih.KeyOpt("{All}", "N")
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


PollController() {
 global EnableControllerMouseMode, ControllerIndex, ControllerDeadzone
 global ControllerMouseSpeed, ControllerMouseFastMultiplier
 global ControllerScrollIntervalMs, ControllerScrollStep, ControllerChordHoldMs

 static state := Buffer(16, 0)
 static prevButtons := 0
 static lastScroll := 0


 static prevViewDown := false
 ; Per-button press tracking (to support Short/Long bindings) without ByRef locals.
 static downTick := Map()
 static longFired := Map()
 static prevTrigDown := Map("LT", false, "RT", false)


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

 if (!EnableControllerMouseMode)
 return

 if (XInputGetState(ControllerIndex, &state) != 0)
 return

 now := A_TickCount

 buttons := NumGet(state, 4, "UShort")
 lt := NumGet(state, 6, "UChar")
 rt := NumGet(state, 7, "UChar")
 lx := NumGet(state, 8, "Short")
 ly := NumGet(state, 10, "Short")
 rx := NumGet(state, 12, "Short")
 ry := NumGet(state, 14, "Short")

 ; Deadzone
 if (Abs(lx) < ControllerDeadzone)
 lx := 0
 if (Abs(ly) < ControllerDeadzone)
 ly := 0
 if (Abs(rx) < ControllerDeadzone)
 rx := 0
 if (Abs(ry) < ControllerDeadzone)
 ry := 0


 ; Controller chord: LT+RT+LB+RB+L3+R3 opens the Control Panel (works even without holding View/Back).
 static cpComboWasDown := false
 cpComboNow := ((lt > 30) && (rt > 30) && (buttons & 0x0100) && (buttons & 0x0200) && (buttons & 0x0040) && (buttons & 0x0080))
 if (cpComboNow && !cpComboWasDown) {
 try ShowControlPanel()
 }
 cpComboWasDown := cpComboNow

 pressed := buttons & ~prevButtons
 released := (~buttons) & prevButtons
 prevButtons := buttons

 
viewDown := (buttons & 0x0020)
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
; WINDOW MANAGEMENT (center + maximize)
; ==============================================================================
CheckWindows() {
 ; Prevent timer re-entrancy (a new tick starting before the prior one finishes).
 ; If a tick is missed while we're busy, we run one extra pass immediately afterward.
 static inTick := false, pending := false
 global AllowExplorer, SystemReady, EnableWindowManagement
 global MinWidthPercent, BpmTitle
 global ScriptPid

 if inTick {
 pending := true
 return
 }

 inTick := true
 try {
 while true {
 pending := false

 if (AllowExplorer || !SystemReady || !EnableWindowManagement)
 break

 for hwnd in WinGetList() {
 if !DllCall("IsWindow", "Ptr", hwnd)
 continue
 if IsCloaked(hwnd)
 continue

 id := "ahk_id " hwnd

 ; Skip windows owned by this script (Control Panel, Live Log, managers, etc.)
 ; Prevents the auto-maximize/window-management loop from maximizing our own GUIs.
 try {
 if (WinGetPID(id) = ScriptPid)
 continue
 } catch {
 }

 style := 0
 try {
 style := WinGetStyle(id) + 0
 } catch {
 continue
 }

 if !(style & 0x10000000)
 continue

 title := "", winClass := ""
 try {
 title := WinGetTitle(id)
 winClass := WinGetClass(id)
 } catch {
 continue
 }

 if (title = "" || title = BpmTitle)
 continue
 if (winClass = "Progman" || winClass = "WorkerW" || winClass = "Shell_TrayWnd")
 continue

 proc := ""
 try {
 proc := WinGetProcessName(id)
 } catch {
 proc := ""
 }

 if IsExcludedForCenterMax(title, winClass, proc)
 continue

 try {
 if (WinGetMinMax(id) != 0)
 continue
 } catch {
 continue
 }

 wW := 0, wH := 0
 try {
 WinGetPos(,, &wW, &wH, id)
 } catch {
 continue
 }

 try WinMove((A_ScreenWidth/2)-(wW/2), (A_ScreenHeight/2)-(wH/2),,, id)

 if (wW >= (A_ScreenWidth * MinWidthPercent)) {
 if (style & 0x00010000) || (style & 0x00040000) {
 try WinMaximize(id)
 }
 }
 }

 if !pending
 break
 }
 } finally {
 inTick := false
 }
}

; ==============================================================================
; SHELL MONITOR (hide taskbar + exit when Steam closes)
; ==============================================================================
MonitorShell() {
 global AllowExplorer, EnableTaskbarHiding, SteamLaunched
 if (SteamLaunched && !ProcessExist("steam.exe")) {
 ExitToDesktop()
 return
 }
 if (AllowExplorer || !EnableTaskbarHiding)
 return

 try {
 if WinExist("ahk_class Shell_TrayWnd")
 WinHide("ahk_class Shell_TrayWnd")
 if WinExist("ahk_class Shell_SecondaryTrayWnd")
 WinHide("ahk_class Shell_SecondaryTrayWnd")
 } catch {
 }
}

; ==============================================================================
; CPU + STEAM FOREGROUND
; ==============================================================================
GetWmiCimv2Service(reset := false) {
 static svc := 0
 if (reset)
 svc := 0
 if IsObject(svc)
 return svc
 try {
 svc := ComObjGet("winmgmts:root\cimv2")
 } catch {
 svc := 0
 }
 return svc
}

GetCPUUsage(pid) {
 cpu := 0
 if (!pid)
 return 0

 try {
 wmi := GetWmiCimv2Service()
 if !IsObject(wmi)
 return 0
 items := wmi.ExecQuery("SELECT PercentProcessorTime FROM Win32_PerfFormattedData_PerfProc_Process WHERE IDProcess=" pid)
 for item in items {
 cpu := item.PercentProcessorTime
 break
 }
 } catch {
 ; If WMI hiccups, reset the cached service and retry once.
 try {
 GetWmiCimv2Service(true)
 wmi := GetWmiCimv2Service()
 if IsObject(wmi) {
 items := wmi.ExecQuery("SELECT PercentProcessorTime FROM Win32_PerfFormattedData_PerfProc_Process WHERE IDProcess=" pid)
 for item in items {
 cpu := item.PercentProcessorTime
 break
 }
 }
 } catch {
 cpu := 0
 }
 }

 return cpu + 0
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
 if (!pMgr) {
 ObjRelease(pDevice)
 return pids
 }

 mgr := ComValue(13, pMgr)

 ComCall(5, mgr, "Ptr*", pEnum) ; GetSessionEnumerator
 if (!pEnum) {
 ObjRelease(pMgr), ObjRelease(pDevice)
 return pids
 }

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
 ObjRelease(pCtrl2)
 }

 peak := 0.0
 pMeter := 0
 ComCall(0, ctrl, "Ptr", iidMeter, "Ptr*", pMeter)
 if (pMeter) {
 meter := ComValue(13, pMeter)
 ComCall(3, meter, "Float*", peak) ; GetPeakValue
 ObjRelease(pMeter)
 }

 if (pid) {
 if (!pids.Has(pid))
 pids[pid] := peak
 else if (peak > pids[pid])
 pids[pid] := peak
 }

 ObjRelease(pCtrl)
 }

 ObjRelease(pEnum)
 ObjRelease(pMgr)
 ObjRelease(pDevice)
 return pids
 } catch {
 if (pEnum)
 try ObjRelease(pEnum)
 if (pMgr)
 try ObjRelease(pMgr)
 if (pDevice)
 try ObjRelease(pDevice)
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

LogLine(line) {
 global EnableGameScoreLogging, LogPath
 if (!EnableGameScoreLogging)
 return
 RotateLogIfNeeded()
 try FileAppend(line "`r`n", LogPath, "UTF-8")
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

ForceGameAssistOnce() {
 TryBringFullscreenCandidateToFront(true, true)
}

TryBringFullscreenCandidateToFront(forceRun := false, forceActivate := false) {
 global EnableGameForegroundAssist, GameForegroundCooldownMs, LastGameBringToFrontTick
 global FullscreenTolerance, FullscreenPosTolerancePx
 global GameCPUThresholdPercent, GameAllowZeroCpuAsCandidate
 global GameRequireSteamForeground, GameAssistLogEvenWhenSkipped
 global ScoreFullscreen, ScoreBorderlessLarge, ScoreTitleBonus, ScoreCpuAboveThreshold, ScoreCpuNonZeroBonus, GameMinScoreToActivate
 global EnableAudioAssist, ScoreAudioActive
 global EnableGameScoreLogging, GameLogMode, GameLogTopN, GameLogRejectNearCandidates, GameLogRejectMinAreaPercent
 global BpmTitle
 global LastActionText, LastBestCandidateScore, LastBestCandidateProc, LastBestCandidateTitle, LastBestCandidateText

 if (!EnableGameForegroundAssist)
 return false

 if (!forceRun && (A_TickCount - LastGameBringToFrontTick < GameForegroundCooldownMs))
 return false

 allowActivate := true
 skipReason := ""

 if (!forceRun && GameRequireSteamForeground) {
 if !IsSteamForeground() {
 if (!GameAssistLogEvenWhenSkipped)
 return false
 allowActivate := false
 skipReason := "STEAM_NOT_FOREGROUND"
 }
 }

 if (forceRun && forceActivate) {
 allowActivate := true
 skipReason := ""
 }

 screenArea := A_ScreenWidth * A_ScreenHeight
 rejectAreaMin := screenArea * GameLogRejectMinAreaPercent

 candidates := []
 rejects := []
 audioMap := 0

 for hwnd in WinGetList() {
 if !DllCall("IsWindow", "Ptr", hwnd)
 continue
 if IsCloaked(hwnd)
 continue

 id := "ahk_id " hwnd

 style := 0
 try {
 style := WinGetStyle(id) + 0
 } catch {
 continue
 }

 if !(style & 0x10000000)
 continue

 try {
 if (WinGetMinMax(id) = -1)
 continue
 } catch {
 }

 title := "", winClass := ""
 try {
 title := WinGetTitle(id)
 winClass := WinGetClass(id)
 } catch {
 continue
 }

 if (title = "" || title = BpmTitle)
 continue
 if (winClass = "Progman" || winClass = "WorkerW" || winClass = "Shell_TrayWnd")
 continue

 proc := ""
 try {
 proc := StrLower(WinGetProcessName(id))
 } catch {
 proc := ""
 }

 tLower := StrLower(title)

 if (proc = "steam.exe")
 continue
 if (proc = "osk.exe" || winClass = "OSKMainClass" || InStr(tLower, "on-screen keyboard"))
 continue
 if (proc = "steam.exe" && InStr(tLower, "keyboard"))
 continue

 x := 0, y := 0, w := 0, h := 0
 try {
 WinGetPos(&x, &y, &w, &h, id)
 } catch {
 continue
 }

 area := w * h
 rectStr := FmtRect(x, y, w, h)

 nearFS := (w >= (A_ScreenWidth * FullscreenTolerance)
 && h >= (A_ScreenHeight * FullscreenTolerance)
 && Abs(x) <= FullscreenPosTolerancePx
 && Abs(y) <= FullscreenPosTolerancePx)

 bigBorderless := (w >= (A_ScreenWidth * 0.90) && h >= (A_ScreenHeight * 0.90))

 if (!nearFS && !bigBorderless) {
 if (EnableGameScoreLogging && GameLogMode = "DIAGNOSTIC" && GameLogRejectNearCandidates && area >= rejectAreaMin && ShouldLogRateLimited()) {
 rejects.Push(LogRow(NowStamp(), "REJ", "---", proc, "------", FmtCpu(0, false), "-", "N", rectStr, FmtHwnd(hwnd), "TOO_SMALL", title))
 }
 continue
 }

 score := 0
 score += nearFS ? ScoreFullscreen : ScoreBorderlessLarge
 if (StrLen(title) >= 3)
 score += ScoreTitleBonus

 pid := 0
 try {
 pid := WinGetPID(id)
 } catch {
 pid := 0
 }

 cpu := 0
 cpuKnown := false
 if (pid) {
 cpu := GetCPUUsage(pid)
 cpuKnown := true
 if (cpu >= GameCPUThresholdPercent)
 score += ScoreCpuAboveThreshold
 else if (cpu > 0)
 score += ScoreCpuNonZeroBonus
 else if (!GameAllowZeroCpuAsCandidate) {
 if (EnableGameScoreLogging && GameLogMode = "DIAGNOSTIC" && GameLogRejectNearCandidates && area >= rejectAreaMin && ShouldLogRateLimited()) {
 rejects.Push(LogRow(NowStamp(), "REJ", FmtScore(score, true), proc, FmtPid(pid), FmtCpu(cpu, true), "-", (nearFS ? "Y" : "N"), rectStr, FmtHwnd(hwnd), "CPU_ZERO_STRICT", title))
 }
 continue
 }
 }

 audioActive := false
 if (EnableAudioAssist && pid) {
 if (!IsObject(audioMap))
 audioMap := GetActiveAudioPidPeaksCached()
 if (audioMap.Has(pid) && audioMap[pid] > AudioPeakThreshold) {
 score += ScoreAudioActive
 audioActive := true
 }
 }

 candidates.Push(Map(
 "hwnd", hwnd, "proc", proc, "pid", pid,
 "x", x, "y", y, "w", w, "h", h,
 "nearFS", nearFS,
 "cpu", cpu, "cpuKnown", cpuKnown,
 "audio", audioActive,
 "score", score,
 "title", title
 ))
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
 LogLine(LogRow(NowStamp(), "TOPN", "---", "-", "------", FmtCpu(0, false), "-", "-", "-", "----------", "NO_CANDIDATES", "-"))
 } else {
 hdr := "min=" GameMinScoreToActivate
 if (!allowActivate && skipReason != "")
 hdr := "SKIP_" skipReason " " hdr
 LogLine(LogRow(NowStamp(), "TOPN", "---", "-", "------", FmtCpu(0, false), "-", "-", "-", "----------", hdr, "-"))

 maxN := candidates.Length < GameLogTopN ? candidates.Length : GameLogTopN
 Loop maxN {
 c := candidates[A_Index]
 LogLine(LogRow(
 NowStamp()
 , "CAND#" A_Index
 , FmtScore(c["score"], true)
 , c["proc"]
 , FmtPid(c["pid"])
 , FmtCpu(c["cpu"], c["cpuKnown"])
 , (c["audio"] ? "Y" : "N")
 , (c["nearFS"] ? "Y" : "N")
 , FmtRect(c["x"], c["y"], c["w"], c["h"])
 , FmtHwnd(c["hwnd"])
 , "-"
 , c["title"]
 ))
 }
 }

 if (GameLogMode = "DIAGNOSTIC" && rejects.Length > 0) {
 for _, line in rejects
 LogLine(line)
 }
 }

 if (allowActivate && candidates.Length > 0) {
 best := candidates[1]
 if (best["score"] >= GameMinScoreToActivate) {
 ok := ActivateWindowRobust(best["hwnd"])
 LastGameBringToFrontTick := A_TickCount
 MaybeParkMouseOnRefocus()

 LastActionText := "GameActivate: " best["proc"] " (score " best["score"] ") " (ok ? "ok" : "fail")

 if (EnableGameScoreLogging && GameLogMode != "OFF") {
 LogLine(LogRow(
 NowStamp()
 , (forceRun ? "ACT(F)" : "ACT")
 , FmtScore(best["score"], true)
 , best["proc"]
 , FmtPid(best["pid"])
 , FmtCpu(best["cpu"], best["cpuKnown"])
 , (best["audio"] ? "Y" : "N")
 , (best["nearFS"] ? "Y" : "N")
 , FmtRect(best["x"], best["y"], best["w"], best["h"])
 , FmtHwnd(best["hwnd"])
 , (ok ? "ok=1" : "ok=0")
 , best["title"]
 ))
 }
 return ok
 }
 }

 if (!allowActivate && skipReason != "")
 LastActionText := "GameScan: skipped (" skipReason ")"
 else if (candidates.Length = 0)
 LastActionText := "GameScan: no candidates"
 else
 LastActionText := "GameScan: best score " candidates[1]["score"] " (< min " GameMinScoreToActivate ")"

 return false
}

; ==============================================================================
; STEAM BPM REFOCUS + ALWAYSFOCUS
; ==============================================================================
SteamRefocusPolling() {
 global EnableGameForegroundAssist, EnableAlwaysFocus, EnableSteamRefocusMode
 global AlwaysFocusList, AlwaysFocusCooldownMs, LastAlwaysFocusTick
 global SteamRefocusDelay, SteamRefocusTimer
 global BpmTitle
 global HandsOffUntilTick, LastActionText

 if (A_TickCount < HandsOffUntilTick)
 return

 if (EnableGameForegroundAssist) {
 if TryBringFullscreenCandidateToFront()
 SteamRefocusTimer := A_TickCount
 }

 if (EnableAlwaysFocus && AlwaysFocusList.Length > 0) {
 best := 0
 bestArea := 0
 bestProc := ""

 for hwnd in WinGetList() {
 if !DllCall("IsWindow", "Ptr", hwnd)
 continue
 if IsCloaked(hwnd)
 continue

 id := "ahk_id " hwnd

 style := 0
 try {
 style := WinGetStyle(id) + 0
 } catch {
 continue
 }

 if !(style & 0x10000000)
 continue

 title := "", winClass := "", proc := ""
 try {
 title := WinGetTitle(id)
 winClass := WinGetClass(id)
 } catch {
 continue
 }

 if (title = "" || title = BpmTitle)
 continue
 if (winClass = "Progman" || winClass = "WorkerW" || winClass = "Shell_TrayWnd")
 continue

 try {
 proc := StrLower(WinGetProcessName(id))
 } catch {
 proc := ""
 }

 if (proc = "" || !IsExeInList(proc, AlwaysFocusList))
 continue

 w := 0, h := 0
 try {
 WinGetPos(,, &w, &h, id)
 } catch {
 continue
 }

 area := w * h
 if (area > bestArea) {
 bestArea := area
 best := hwnd
 bestProc := proc
 }
 }

 if (best) {
 SteamRefocusTimer := A_TickCount
 if (A_TickCount - LastAlwaysFocusTick >= AlwaysFocusCooldownMs) {
 try WinActivate("ahk_id " best)
 MaybeParkMouseOnRefocus()
 LastAlwaysFocusTick := A_TickCount
 LastActionText := "AlwaysFocus: " bestProc
 }
 return
 }
 }

 if (!EnableSteamRefocusMode)
 return

 anyOpen := false
 for hwnd in WinGetList() {
 if !DllCall("IsWindow", "Ptr", hwnd)
 continue
 if IsCloaked(hwnd)
 continue

 id := "ahk_id " hwnd

 style := 0
 try {
 style := WinGetStyle(id) + 0
 } catch {
 continue
 }

 if !(style & 0x10000000)
 continue

 title := "", winClass := ""
 try {
 title := WinGetTitle(id)
 winClass := WinGetClass(id)
 } catch {
 continue
 }

 if (title != "" && title != BpmTitle
 && winClass != "Progman" && winClass != "WorkerW" && winClass != "Shell_TrayWnd") {
 anyOpen := true
 break
 }
 }

 if (!anyOpen) {
 if (A_TickCount - SteamRefocusTimer > SteamRefocusDelay) {
 hBpm := WinExist(BpmTitle)
 if (hBpm && DllCall("IsWindow", "Ptr", hBpm)) {
 try WinActivate("ahk_id " hBpm)
 MaybeParkMouseOnRefocus()
 LastActionText := "SteamRefocus: BPM"
 }
 SteamRefocusTimer := A_TickCount
 }
 } else {
 SteamRefocusTimer := A_TickCount
 }
}

; ==============================================================================
; ALWAYSFOCUS MANAGER (Top 5 running apps → add/remove + write to INI)
; ==============================================================================
GetTopRunningApps(maxCount := 5) {
 global BpmTitle
 items := []
 seen := Map()

 for hwnd in WinGetList() {
 if (items.Length >= maxCount)
 break
 if !DllCall("IsWindow", "Ptr", hwnd)
 continue
 if IsCloaked(hwnd)
 continue

 id := "ahk_id " hwnd

 style := 0
 try {
 style := WinGetStyle(id) + 0
 } catch {
 continue
 }
 if !(style & 0x10000000)
 continue

 title := "", winClass := "", proc := ""
 try {
 title := WinGetTitle(id)
 winClass := WinGetClass(id)
 } catch {
 continue
 }

 if (title = "" || title = BpmTitle)
 continue
 if (winClass = "Progman" || winClass = "WorkerW" || winClass = "Shell_TrayWnd")
 continue

 try {
 proc := StrLower(WinGetProcessName(id))
 } catch {
 proc := ""
 }

 if (proc = "" || proc = "steam.exe")
 continue

 if (seen.Has(proc))
 continue
 seen[proc] := true

 items.Push(Map("exe", proc, "title", title, "hwnd", hwnd))
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
 lvAF.ModifyCol(1, 220)
 } catch {
 }
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
 if (!row)
 return

 exe := StrLower(Trim(lvRun.GetText(row, 1)))
 if (exe = "")
 return

 if !InStr(exe, ".exe")
 exe .= ".exe"

 if !IsExeInList(exe, AlwaysFocusList) {
 AlwaysFocusList.Push(exe)
 }

 EnableAlwaysFocus := true
 AlwaysFocusExeListRaw := JoinPipe(AlwaysFocusList)

 RefreshAlwaysFocusManagerLists()
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
 if (!row)
 return

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
 SyncControlPanel()
}

AF_WriteToIni(*) {
 global SettingsPath, AlwaysFocusExeListRaw, EnableAlwaysFocus
 EnableAlwaysFocus := true
 try {
 WriteBoolIni("Features", "EnableAlwaysFocus", true)
 IniWrite(AlwaysFocusExeListRaw, SettingsPath, "AlwaysFocus", "ExeList")
 } catch {
 }
}

ShowAlwaysFocusManager(*) {
 global AlwaysFocusGui
 if !IsSet(AlwaysFocusGui) {
 AlwaysFocusGui := Gui("+AlwaysOnTop +ToolWindow +Resize", "AlwaysFocus Manager")
 AlwaysFocusGui.SetFont("s10", "Segoe UI")

 AlwaysFocusGui.AddText("xm ym", "Pick from the top running apps (visible windows):")

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

 btn := AlwaysFocusGui.AddButton("xs y+8 w240 h30", "Remove Selected")
 btn.OnEvent("Click", AF_RemoveSelected)

 btn := AlwaysFocusGui.AddButton("xs y+8 w240 h30", "Write to INI")
 btn.OnEvent("Click", AF_WriteToIni)

 btn := AlwaysFocusGui.AddButton("xs y+8 w240 h30", "Close")
 btn.OnEvent("Click", (*) => AlwaysFocusGui.Hide())

 ; Session AlwaysFocus list (to the right of the buttons)
 lvAF := AlwaysFocusGui.AddListView("x+10 ys w370 r7 vLVAF", ["EXE"])
 lvAF.ModifyCol(1, 330)


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
 global HandsOffUntilTick, LastActionText, LastBestCandidateText, AlwaysFocusList
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
 actTxt := "-"
 try {
 if (!IsObject(LastBestCandidateText) && LastBestCandidateText != "")
 bestTxt := LastBestCandidateText
 } catch {
 bestTxt := "-"
 }
 try {
 if (!IsObject(LastActionText) && LastActionText != "")
 actTxt := LastActionText
 } catch {
 actTxt := "-"
 }

 txt1 := "Steam Foreground: " steamFg
 txt2 := "Hands-Off Remaining: " hands
 txt3 := "Best Candidate: " bestTxt " AlwaysFocus entries: " afCount
 txt4 := "Last Action: " actTxt

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

CopyPanelLog(*) {
 global ControlGui
 if !IsSet(ControlGui)
 return
 try A_Clipboard := ControlGui["logView"].Value
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

ForceSteamFocusNow(*) {
 global BpmTitle, LastActionText
 h := WinExist(BpmTitle)
 if (h && DllCall("IsWindow", "Ptr", h)) {
 try WinActivate("ahk_id " h)
 MaybeParkMouseOnRefocus()
 LastActionText := "Manual: BPM focus"
 } else {
 LastActionText := "Manual: BPM not found"
 }
 UpdateStatusIndicators()
}

ForceGameAssistNow(*) {
 ForceGameAssistOnce()
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
 global ControlGui, SettingsPath
 global EnableGameScoreLogging, GameLogMode, GameLogIntervalMs, GameLogTopN
 global EnableControllerMouseMode, ControllerMouseSpeed
 global GameAssistLogEvenWhenSkipped

 if !IsSet(ControlGui)
 return

 try {
 WriteBoolIni("Features", "EnableGameForegroundAssist", (ControlGui["cbGame"].Value = 1))
 WriteBoolIni("Features", "EnableSteamRefocusMode", (ControlGui["cbSteam"].Value = 1))
 WriteBoolIni("Features", "EnableWindowManagement", (ControlGui["cbMax"].Value = 1))

 WriteBoolIni("GameForegroundAssist", "GameAssistLogEvenWhenSkipped", (ControlGui["cbSkipLog"].Value = 1))

 try WriteBoolIni("Controller", "EnableControllerMouseMode", (ControlGui["cbCtlMouse"].Value = 1))

 try IniWrite(ControllerMouseSpeed, SettingsPath, "Controller", "ControllerMouseSpeed")
 ; Live logging checkbox writes a DIAGNOSTIC preset for convenience.
 if (ControlGui["cbLiveLog"].Value = 1) {
 WriteBoolIni("Logging", "EnableGameScoreLogging", true)
 IniWrite("DIAGNOSTIC", SettingsPath, "Logging", "GameLogMode")
 IniWrite("1000", SettingsPath, "Logging", "GameLogIntervalMs")
 IniWrite("3", SettingsPath, "Logging", "GameLogTopN")
 } else {
 WriteBoolIni("Logging", "EnableGameScoreLogging", EnableGameScoreLogging)
 IniWrite(GameLogMode, SettingsPath, "Logging", "GameLogMode")
 IniWrite(GameLogIntervalMs, SettingsPath, "Logging", "GameLogIntervalMs")
 IniWrite(GameLogTopN, SettingsPath, "Logging", "GameLogTopN")
 }
 } catch {
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

ShowControlPanel(*) {
 global ControlGui, SettingsPath
 global ControllerMouseSpeed

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
 ControlGui := Gui("+AlwaysOnTop +ToolWindow +Resize", "SteamShell Control Panel")
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

 ControlGui.AddButton("x" x2 " y+10 w" colW, "Controller Mapping…").OnEvent("Click", ShowControllerMappingWindow)

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

 lv := ControllerMapGui.AddListView("xm y+8 w640 r10 -Multi +LV0x10000", ["Button", "Short press", "Long press"])
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
ExitToDesktop(PermanentRestore := false) {
 global AllowExplorer, ShellRegKey, OriginalShell
 AllowExplorer := true
 SystemCursor("Show")

 try RegWrite("explorer.exe", "REG_SZ", ShellRegKey, "Shell")
 RunWait(A_ComSpec " /c taskkill /F /IM explorer.exe", , "Hide")
 Run("explorer.exe")
 WinWait("ahk_class Shell_TrayWnd", , 10)
 Sleep(2500)

 if (!PermanentRestore) {
 try RegWrite(OriginalShell, "REG_SZ", ShellRegKey, "Shell")
 }
 ExitApp()
}

ExitCleanup(ExitReason, ExitCode) {
 SystemCursor("Show")
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

 Loop 20 {
 k := "Program" A_Index
 cmdline := Trim(IniReadS("StartupPrograms", k, ""))
 if (cmdline = "")
 continue
 RunHiddenCommandLine(cmdline)
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
 } finally {
     inRun := false
 }
}


HasGameLikeWindow(excludeSet) {
 global FullscreenTolerance, FullscreenPosTolerancePx, ScriptPid, BpmTitle
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


 for hwnd in WinGetList() {
     if !DllCall("IsWindow", "Ptr", hwnd)
         continue
     if IsCloaked(hwnd)
         continue

     id := "ahk_id " hwnd

     try {
         style := WinGetStyle(id)
         if !(style & 0x10000000)
             continue
     } catch {
         continue
     }

     try {
         if (WinGetMinMax(id) = -1)
             continue
     } catch {
     }

     proc := ""
     try proc := StrLower(WinGetProcessName(id))
     catch {
         proc := ""
     }

     if (proc = "" || ignore.Has(proc))
         continue

     ; Ignore our own GUI windows
     try {
         if (WinGetPID(id) = ScriptPid)
             continue
     } catch {
     }

     title := ""
     try title := WinGetTitle(id)
     catch {
         title := ""
     }

     if (title = "" || title = BpmTitle)
         continue

     x := 0, y := 0, w := 0, h := 0
     try WinGetPos(&x, &y, &w, &h, id)
     catch {
         continue
     }
     nearFS := (w >= (A_ScreenWidth * FullscreenTolerance)
         && h >= (A_ScreenHeight * FullscreenTolerance)
         && Abs(x) <= FullscreenPosTolerancePx
         && Abs(y) <= FullscreenPosTolerancePx)

     bigBorderless := (w >= (A_ScreenWidth * 0.90) && h >= (A_ScreenHeight * 0.90))

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
 try {
 for hwnd in WinGetList() {
 if !DllCall("IsWindow", "Ptr", hwnd)
 continue
 id := "ahk_id " hwnd
 pid := 0
 try pid := WinGetPID(id)
 catch {
     pid := 0
 }
 if (pid)
 pids[pid] := true
 }
 } catch {
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

 cpu := 0
 try cpu := GetCPUUsage(pid)
 catch {
     cpu := 0
 }

 if ((cpu + 0) >= LauncherCleanupCpuThreshold)
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

    ; If we couldn't read any relevant process counters, don't block cleanup.
    if (!anyReadable)
        return false

    ; If we need warmup (first baseline), delay cleanup briefly but don't spam logs.
    if (needWarmup)
        return true

    if (isBusy) {
        if ((now - lastLogTick) > 15000) {
            Log("LauncherCleanup: skipped (launcher busy: possible download/update)")
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


RunHiddenCommandLine(cmdline) {
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

 ; Start hidden if possible.
 pid := 0
 try {
 Run(runCmd, , "Hide", &pid)
 } catch {
 ; Fallback: try as-is (Windows will parse it).
 try Run(cmdline, , "Hide", &pid)
 }

 if (pid)
 SetTimer(() => HideWindowsForPid(pid), -200)
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
InitDpiAwareness()
EnsureSettingsIniExists()
LoadSettings()
KickUserStartupPrograms()

LastMouseMoveTick := A_TickCount
SteamRefocusTimer := A_TickCount

if (EnableMouseParkOnBoot)
 ParkMouseRightEdge()

if (EnableSplashScreen)
 ShowSplash()

; Launch Explorer if not running (Game Bar hooks)
if !ProcessExist("explorer.exe")
 try Run("explorer.exe")

; Launch Steam BPM
if (!SteamLaunched) {
 SteamLaunched := true
 if (SteamPath != "" && FileExist(SteamPath)) {
 cmd := '"' SteamPath '" -bigpicture -fulldesktopres -nobootstrapupdate'
 try Run(cmd)
 }
}

if (EnableSplashScreen)
 ArmSplashAutoClose()

ApplyRuntimeTimers()
OnExit(ExitCleanup)

; Hotkeys (registered dynamically so they never break if code is refactored into functions)
Hotkey("^!+e", (*) => ExitToDesktop(true))
Hotkey("^!+r", (*) => ReloadSettings())
Hotkey("^!+g", (*) => ForceGameAssistOnce())
Hotkey("^!+p", (*) => ShowControlPanel())
