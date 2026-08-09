param([switch]$Quiet)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Assert-True, Get-EffectiveSource and the structural scans live in
# Validate-Common.ps1, beside this script. Only mechanism is shared. The
# architecture-boundary rules below are this validator's alone and several are
# the exact inverse of SteamShell's -- RegWrite(, RegDelete(, WinMaximize(,
# SetWinEventHook, RestoreExplorerDesktop and HideShellTaskbars are forbidden
# here and are what the shell is built out of. That is why there are two
# validators and not one.
. (Join-Path $projectRoot "Validate-Common.ps1")

$sourcePath = Join-Path $projectRoot "SteamShell-XFE.ahk"
$samplePath = Join-Path $projectRoot "SteamShell-XFE_SAMPLE.ini"
$controllerSimulationPath = Join-Path $projectRoot "Test-ControllerProfiles.py"
$iconPath = Join-Path $projectRoot "assets\SteamShell-XFE.ico"
$iconPreviewPath = Join-Path $projectRoot "assets\SteamShell-XFE-icon.png"
$buildLauncherPath = Join-Path $projectRoot "Build-SteamShell.cmd"
$buildScriptPath = Join-Path $projectRoot "Build-SteamShell.ps1"

Assert-True (Test-Path $sourcePath) "SteamShell-XFE.ahk is missing."
Assert-True (Test-Path $samplePath) "SteamShell-XFE_SAMPLE.ini is missing."
Assert-True (Test-Path $controllerSimulationPath) (
    "The learned-controller simulation is missing.")
Assert-True (Test-Path $iconPath) "The SteamShell XFE Windows icon is missing."
Assert-True (Test-Path $iconPreviewPath) "The SteamShell XFE icon preview is missing."
Assert-True (Test-Path $buildLauncherPath) "The double-clickable build launcher is missing."
Assert-True (Test-Path $buildScriptPath) "Build-SteamShell.ps1 is missing."
$source = Get-EffectiveSource -Path $sourcePath
# The tree file WITHOUT its #Includes resolved. Assertions that forbid something
# need this: $source now contains SteamShell-Common.ahk, where the very
# constants a re-implementation would use legitimately live, so a -notmatch
# against $source can never be satisfied and would pin nothing.
$rawSource = Get-SourceText $sourcePath
$commonSourcePath = Join-Path $projectRoot "SteamShell-Common.ahk"
Assert-True (Test-Path $commonSourcePath) "SteamShell-Common.ahk is missing."
$commonSource = Get-SourceText $commonSourcePath
$sample = Get-SourceText $samplePath
$buildScript = Get-SourceText $buildScriptPath

Assert-True (
    $source -match '@Ahk2Exe-SetVersion 2\.0\.0\.0' -and
    $source -match 'AppVersion\s*:=\s*"2\.0\.0"' -and
    $buildScript -match 'SteamShell-XFE version verification failed.*?2\.0\.0\.0' -and
    # The companion is compiled by the one build script in this folder, and its
    # syntax is checked before the compiler is started.
    $buildScript -match '/in", \$xfeSourcePath') (
    "SteamShell-XFE 2.0.0 version metadata is inconsistent.")

Assert-AhkStructure -Text $source -Label "SteamShell-XFE.ahk"
$functionMatches = [regex]::Matches(
    $source,
    '(?m)^([A-Za-z_][A-Za-z0-9_]*)\([^\r\n{}]*\)\s*\{')
$functionNames = @{}
foreach ($match in $functionMatches) {
    $functionNames[$match.Groups[1].Value.ToLowerInvariant()] = $true
}

$requiredFunctions = @(
    "PollController",
    "XInputResolveController",
    "ShowQuickMenu",
    "QuickMenuRender",
    "ShowSettings",
    "SettingsShowCategory",
    "ShowMappingEditor",
    "OpenTouchKeyboard",
    "ParkCursor",
    "ObserveForeground",
    "GetPrimaryDisplayModes",
    "ApplyPrimaryDisplayMode",
    "GetPrimaryDisplayScale",
    "ApplyPrimaryDisplayScale",
    "GetPrimaryHdrState",
    "ApplyPrimaryHdrState",
    "SetDefaultAudioEndpointId",
    "ResolveRtssExecutablePath",
    "EnsureRtssRunning",
    "StartRtssFromQuickMenu",
    "GetRtssHooksApi",
    "GetRtssGlobalState",
    "GetRtssFrameLimit",
    "GetRtssAvailability",
    "ApplyRtssGlobalState",
    "InitializeTrayMenu",
    "SetCompanionDisabled",
    "SendSteamOverlayChord",
    "ShowHealthCheck",
    "RotateLogIfNeeded",
    "XfeElevatedHelperPath",
    "XfeInitializeInteractiveIdentity",
    "ElevatedRtssRequestPath",
    "VerifyElevatedHelperProcess",
    "StartElevatedRtssHelper",
    "StopElevatedHelper",
    "EnsureElevatedRtssHelperAlive",
    "SyncElevatedRtssHelperWithSettings",
    "SettingsLayout",
    "SettingsFirstRowY",
    "SettingsGetMaxScroll",
    "SettingsApplyCategoryLayout",
    "SettingsUpdateScrollBar",
    "SettingsVerticalScroll",
    "SettingsMouseWheel",
    "SettingsScroll",
    "SettingsAuditLayout",
    "SettingsReportLayoutAudit"
)
foreach ($required in $requiredFunctions) {
    Assert-True $functionNames.ContainsKey($required.ToLowerInvariant()) (
        "Required companion function is missing: $required")
}

Assert-True (
    $source -match
        '(?s)LoadSettings\(\)\s*\{.*?global[^\r\n]*LogRotateMaxKB[^\r\n]*LogRotateBackups.*?' +
        'LogRotateMaxKB\s*:=.*?LogRotateBackups\s*:=' ) (
    "LoadSettings no longer writes log-rotation settings to their declared globals.")
Assert-True (
    $source -match
        '(?s)ResolveRtssExecutablePath\(\)\s*\{.*?ProgramFiles\(x86\).*?' +
        'RivaTuner Statistics Server\\RTSS\.exe' -and
    $source -match
        '(?s)EnsureRtssRunning\(\)\s*\{\s*path\s*:=\s*ResolveRtssExecutablePath\(\)' -and
    $source -match
        '(?s)GetRtssHooksApi\(\)\s*\{.*?ResolveRtssExecutablePath\(\)') (
    "RTSS discovery is no longer centralized across launch, status, and DLL lookup paths.")

Assert-True ($source -match '(?m)^#Requires AutoHotkey v2\.0\.19 64-bit$') (
    "The 64-bit AutoHotkey v2 requirement is missing.")
Assert-True ($source -match '(?m)^#SingleInstance Ignore$') (
    "The XFE companion must not replace a surviving instance during re-entry.")
Assert-True ($source -notmatch '(?m)^#NoTrayIcon$') (
    "The notification-area control requires the tray icon to remain visible.")
Assert-True (
    # Declared rather than added imperatively: the menu is now built from
    # ProductTrayItems on every refresh instead of created once and mutated with
    # Rename. That is what lets a conditional entry exist at all -- a menu that is
    # never rebuilt cannot gain or lose one.
    $source -match '"label", "Open Quick Menu", "handler", TrayOpenQuickMenu' -and
    $source -match '"label", "Open Settings", "handler", TrayOpenSettings' -and
    $source -match '"label", CompanionDisabled \? "Enable" : "Disable"' -and
    $source -match '"label", "Exit", "handler", ExitCompanion' -and
    $source -match 'TraySetIcon\(iconPath\)') (
    "The SteamShell XFE notification-area menu or icon is incomplete.")
Assert-True (
    $source -match '(?s)SetCompanionDisabled\([^)]*\).*?ApplyRuntimeTimers\(\).*?SetCompanionHotkeysEnabled\(false\)' -and
    $source -match '(?s)SetCompanionDisabled\([^)]*\).*?SetCompanionHotkeysEnabled\(true\).*?ApplyRuntimeTimers\(\)' -and
    $source -match '(?s)ApplyRuntimeTimers\(\).*?if CompanionDisabled\s*\r?\n\s*return') (
    "Disable/Enable must pause and restore companion timers and global hotkeys.")
# Elevation: the companion must never relaunch ITSELF elevated, because that
# would raise a UAC prompt on every boot when a non-elevated parent starts it.
# Elevating schtasks.exe once, at the user's request, to register an optional
# logon task is permitted and is the supported way to get elevation at boot.
#
# There is now a SECOND permitted target, and the old rule had to be rewritten
# rather than merely relaxed. The previous assertion enumerated the literal after
# *RunAs and required it to be schtasks.exe -- and its character class excluded
# the quote character, so `"*RunAs " QuoteWindowsCommandLineArg(path)` matched
# nothing at all and the rule would have passed while saying nothing about the
# new elevation. Anchored to the two permitted forms instead, so a third one
# fails.
$runAsSites = [regex]::Matches($source, '(?i)\*RunAs[^\r\n]*')
foreach ($match in $runAsSites) {
    $line = $match.Value
    $isSchtasks = $line -imatch 'schtasks\.exe'
    $isVerifiedHelper =
        $line -match 'QuoteWindowsCommandLineArg\(ElevatedHelperPath\)'
    Assert-True ($isSchtasks -or $isVerifiedHelper) (
        "Only schtasks.exe and the verified elevated helper may be elevated; found: " +
        $line)
}
Assert-True ($source -notmatch '(?i)\*RunAs[^\r\n]*A_ScriptFullPath') (
    "The companion must not relaunch itself elevated.")

# Architecture boundary: these responsibilities belong to Windows Xbox FSE.
#
# The window inventory and game detection from SteamShell 1.5 ARE used, to drive
# the optional assist features. What must never come across is the geometry
# layer: Xbox FSE owns presentation, so nothing here may size, centre, maximise
# or restore a window it does not own.
$forbidden = @(
    'CurrentVersion\\Winlogon',
    'RegWrite\s*\(',
    'RegDelete\s*\(',
    'HideShellTaskbars',
    'TaskbarGuard',
    'RestoreExplorerDesktop',
    'SetWinEventHook',
    'WindowEngineApplyGeometry',
    'WindowEngineIsGeometryCandidate',
    'GameMinScoreToActivate',
    'WinMaximize\s*\('
)
# Full-line comments are stripped first.
#
# This list names RESPONSIBILITIES, and a comment explaining why this product
# does NOT have one is exactly the documentation the boundary needs -- the entry
# above that says the shell's activation threshold is a different question from
# naming a profile is the reason the companion has no such threshold. Forbidding
# the word left the codebase unable to describe its own limits.
#
# Only whole comment lines go: string literals are still scanned, because a
# registry path in a string can act, and a trailing comment cannot hide a call
# that is already on the line before it.
$forbiddenScope = (($source -split "`n") |
    Where-Object { $_ -notmatch '^\s*;' }) -join "`n"
foreach ($pattern in $forbidden) {
    Assert-True ($forbiddenScope -notmatch $pattern) (
        "Forbidden shell/geometry responsibility detected: $pattern")
}

# Startup Programs has one deliberately bounded presentation exception:
# applying the user's explicit Minimized choice for a few seconds after launch.
# WinMinimize is still forbidden everywhere else so this cannot grow back into
# a general-purpose window geometry engine.
#
# The bounded body moved into SteamShell-Common.ahk as
# ApplyStartupWindowModeOnce when the two programs stopped each having their own
# idea of what "Minimized" means and how long to keep trying. $source is
# include-resolved, so it now contains that body -- the exception is the same
# one, in a place both programs share, and the "nowhere else" half is unchanged.
$startupWindowModeBodies = ""
foreach ($fn in @("ApplyStartupWindowModeOnce", "ApplyStartupWindowMode")) {
    $m = [regex]::Match($source, '(?ms)^' + $fn + '\([^)]*\)\s*\{.*?^}')
    if ($m.Success) { $startupWindowModeBodies += $m.Value }
}
$startupWindowModeMatch = [PSCustomObject]@{
    Success = ($startupWindowModeBodies -ne "")
    Value = $startupWindowModeBodies
}
$allWinMinimize = [regex]::Matches($source, 'WinMinimize\s*\(')
$startupWinMinimize = if ($startupWindowModeMatch.Success) {
    [regex]::Matches($startupWindowModeMatch.Value, 'WinMinimize\s*\(')
} else {
    @()
}
Assert-True (
    $startupWindowModeMatch.Success -and
    $startupWinMinimize.Count -ge 1 -and
    $allWinMinimize.Count -eq $startupWinMinimize.Count) (
    "WinMinimize is permitted only inside the bounded Startup Programs presentation helper.")

$parkFunctionMatch = [regex]::Match(
    $source,
    '(?ms)^ParkCursor\([^)]*\)\s*\{.*?^}\s*(?=^[A-Za-z_][A-Za-z0-9_]*\s*\()')
Assert-True (
    $parkFunctionMatch.Success -and
    $parkFunctionMatch.Value -match 'SetCursorPos' -and
    $parkFunctionMatch.Value -notmatch 'MouseMove\(') (
    "Cursor parking must use SetCursorPos so it does not reset Windows idle time.")
Assert-True (
    $source -match '(?s)DisplayPendingUntilTick\s*:=\s*A_TickCount\s*\+\s*15000' -and
    $source -match 'DisplayChangeSafetyTick') (
    "The 15-second display-mode safety revert is missing.")
Assert-True (
    $source -match 'DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE' -and
    $source -match 'DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE' -and
    $source -match 'DisplayConfigSetDeviceInfo' -and
    $source -match 'DisplaySelectedScalePercent') (
    "Primary-display scale selection is incomplete.")
# The companion already had the one-helper shape; what it lacked was naming the
# specific setting. Six shortcut settings exist and the message has to say which.
Assert-True (
    $source -match
        '(?sm)^SendRtssShortcut\(shortcut, description, settingName\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?EnableRTSSIntegration' +
        '(?:(?!\n\})[\s\S])*?"Configure RTSS " settingName' +
        '(?:(?!\n\})[\s\S])*?EnsureRtssRunning\(\)' -and
    $source -match 'OverlayToggleShortcut"' -and
    $source -match 'CustomFrameCapShortcut"' -and
    $source -notmatch 'Configure the RTSS shortcut in Settings first') (
    "The companion's RTSS shortcut failure must name the exact setting.")

Assert-True (
    $source -match '(?s)ApplyDisplaySelection\(\).*?DisplayPendingOldScale\s*:=\s*currentScale' -and
    $source -match '(?s)DisplayChangeSafetyTick\(\).*?ApplyPrimaryDisplayMode\(oldMode\).*?ApplyPrimaryDisplayScale\(oldScale\["percent"\]\)' -and
    $source -match '(?s)OnCompanionExit\([^)]*\).*?ApplyPrimaryDisplayMode\(DisplayPendingOldMode\).*?ApplyPrimaryDisplayScale\(DisplayPendingOldScale\["percent"\]\)') (
    "Display scale must share the mode transaction, safety revert, and exit rollback.")
# KEEP must be answered before anything is re-derived, and without a condition.
# Gating the confirm on the live state still matching the selection is what made
# the row refuse presses intermittently: the enumerated mode list and
# ENUM_CURRENT_SETTINGS disagree by 1 Hz on 59.94 modes, and QueryDisplayConfig
# can return nothing while the topology settles after the change being confirmed.
# Body-bounded on purpose; the same pin exists in the standalone validator.
Assert-True (
    $source -match
        '(?sm)^ApplyDisplaySelection\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if IsObject\(DisplayPendingOldMode\)\s*\{\s*\r?\n' +
        '\s*ConfirmPrimaryDisplayMode\(\)\s*\r?\n\s*return\s*\r?\n\s*\}' -and
    $source -notmatch 'Keep or revert the pending display change first' -and
    $source -match
        '(?sm)^ApplyDisplaySelection\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if IsObject\(DisplayPendingOldMode\)(?:(?!\n\})[\s\S])*?' +
        'QuickMenuDisplayModes\b' -and
    $source -match 'Select KEEP within 15 seconds') (
    "Keeping a pending display change must be unconditional and answered first.")
# The Apply row reads the same in both programs. It said "Select To Apply" in one
# and "Select to apply" in the other purely because it was typed twice -- the
# smallest possible symptom of the duplication, and the one a user actually sees.
Assert-True (
    $source -match '"Select To KEEP \(" \w+ "s\)"' -and
    $source -match '"Select To Apply"') (
    "The display Apply row label must match between the two programs.")

Assert-True (
    $source -match 'MenuRow\("displayScale", "Scale"' -and
    $source -match '(?s)QuickMenuAdjustSelected\([^)]*\).*?case "displayScale":\s*\r?\n\s*CycleDisplayScale\(direction\)') (
    "The Quick Menu Scale row or its Left/Right adjustment is missing.")
Assert-True (
    $source -match '(?s)QueueQuickMenuDisplayReflow\(\)\s*\{.*?SetTimer\(QuickMenuDisplayReflow,\s*-350\)' -and
    $source -match '(?s)QuickMenuDisplayReflow\(\)\s*\{.*?QuickMenuBuildGui\(\)' -and
    $source -match '(?s)ApplyDisplaySelection\(\).*?DisplayPendingUntilTick\s*:=\s*A_TickCount\s*\+\s*15000.*?QueueQuickMenuDisplayReflow\(\)' -and
    $source -match '(?s)DisplayChangeSafetyTick\(\).*?ApplyPrimaryDisplayScale\(oldScale\["percent"\]\).*?QueueQuickMenuDisplayReflow\(\)') (
    "Display apply and revert must reflow the Quick Menu after Windows DPI settles.")
Assert-True (
    $source -match 'GET_ADVANCED_COLOR_INFO' -and
    $source -match 'SET_ADVANCED_COLOR_STATE' -and
    $source -match '(?s)GetPrimaryDisplayConfigSource\(\).*?"targetAdapterLow".*?"targetAdapterHigh".*?"targetId"' -and
    $source -match '(?s)GetPrimaryHdrState\(\).*?DisplayConfigGetDeviceInfo' -and
    $source -match '(?s)ApplyPrimaryHdrState\([^)]*\).*?DisplayConfigSetDeviceInfo') (
    "Primary-display HDR state discovery or explicit control is incomplete.")
Assert-True (
    $source -match '(?s)case "DISPLAY":.*?MenuRow\("hdr", "HDR".*?"hdr"' -and
    $source -match '(?s)QuickMenuActivateSelected\(\).*?case "hdr":\s*\r?\n\s*ToggleQuickMenuHdrState\(\)' -and
    $source -match '(?s)QuickMenuAdjustSelected\([^)]*\).*?case "hdr":\s*\r?\n\s*SetQuickMenuHdrState\(direction > 0\)' -and
    $source -notmatch 'SendChordSafe\("#!b"\)') (
    "HDR must show live state and provide explicit Off/On control, not a blind shortcut.")
Assert-True (
    $source -match 'RTSSHOOKSFLAG_OSD_VISIBLE' -and
    $source -match 'RTSSHOOKSFLAG_LIMITER_DISABLED' -and
    $source -match '(?s)GetRtssHooksApi\(\).*?GetProcAddress.*?"GetFlags".*?GetProcAddress.*?"SetFlags"' -and
    $source -match '(?s)GetRtssHooksApi\(\).*?GetProcAddress.*?"LoadProfile".*?GetProcAddress.*?"GetProfileProperty"' -and
    $source -match '(?s)GetRtssFrameLimit\([^)]*\).*?"FramerateLimit"' -and
    $source -match '(?s)NotifyRtssSettingsChanged\(\).*?0x8064' -and
    $source -match '(?s)case "RTSS":.*?MenuRow\("rtssOverlayState", "Overlay".*?MenuRow\("rtssFrameLimit", "Frame Limit".*?MenuRow\("rtssSaveProfile", "Save Limit To Profile"') (
    "RTSS global Overlay/Limiter state discovery or Quick Menu rows are incomplete.")
Assert-True (
    $source -match '(?s)case "RTSS":.*?MenuRow\("rtssStart", "Start RTSS".*?"rtssStart"' -and
    $source -match '(?s)QuickMenuActivateSelected\(\).*?case "rtssStart":\s*\r?\n\s*StartRtssFromQuickMenu\(\)' -and
    $source -match '(?s)StartRtssFromQuickMenu\(\).*?EnsureRtssRunning\(\).*?SetTimer\(RefreshQuickMenuAfterRtssStart,\s*-600\)') (
    "The RTSS page must offer and refresh after its couch-friendly start action.")
Assert-True (
    $source -match '(?s)GetRtssMenuStatus\(\).*?"Overlay ".*?" \| Limiter "' -and
    $source -match '(?s)GetRtssAvailability\(\).*?if ProcessExist\("RTSS\.exe"\)\s*\r?\n\s*return "Running"' -and
    $source -match 'MenuRow\("rtssSettings", "RTSS Settings", "", "rtssSettings"\)' -and
    $source -match '(?s)case "rtssSettings": return GetRtssAvailability\(\)' -and
    $source -match '(?s)case "rtssSettings":.*?ShowSettingsCategory\("RTSS & Performance"\)') (
    "RTSS main summary and Settings availability row must remain distinct.")
Assert-True (
    $source -match '"section", "RTSS", "key", "UseDllIntegration"' -and
    $source -match 'Use RTSSHooks64\.dll for live state and direct control' -and
    $source -match '(?s)GetRtssHooksApi\(\).*?if !RtssUseDllIntegration\s*\r?\n\s*return 0' -and
    $source -match '(?s)GetRtssMenuStatus\(\).*?return "Running \| Shortcuts"') (
    "The user-selectable RTSS DLL/forced-shortcut mode is incomplete.")
Assert-True (
    $source -notmatch 'StartupSplash\.Enable' -and
    $source -notmatch '(?m)^(?:StartStartupSplash|StartStartupSplashVideo|CloseStartupSplash|CreateStartupSplashCover)\(' -and
    $source -notmatch '"Startup Splash"' -and
    $sample -notmatch '(?m)^\[StartupSplash\]$' -and
    $source -match '(?s)RetireStartupSplashSettings\(\).*?\.pre-schema-6\.bak.*?IniDelete\(IniPath, "StartupSplash"\)') (
    "XFE must retire and migrate the late startup curtain instead of exposing or running it.")
Assert-True (
    # The A-press half moved into QuickMenuActivateShared when the fourteen
    # identical actions stopped being written twice; rtssFrameLimit stayed
    # per-tree because standalone rebuilds the page and the companion does not.
    $source -match '(?s)QuickMenuActivateShared\(id\).*?case "rtssOverlayState", "overlayToggle":\s*\r?\n\s*ToggleRtssOverlay\(\)' -and
    # Both now rebuild on the Custom transition, because a repaint no longer
    # re-composes the rows and that transition adds or removes one.
    $source -match '(?s)QuickMenuActivateSelected\(\).*?case "rtssFrameLimit":\s*\r?\n(?:\s*;[^\r\n]*\r?\n)*\s*if CycleRtssFrameCap\(1, true\) \{' -and
    $source -match '(?s)QuickMenuAdjustSelected\([^)]*\).*?case "rtssOverlayState":\s*\r?\n\s*SetRtssOverlayState\(direction > 0\).*?case "rtssFrameLimit":\s*\r?\n(?:\s*;[^\r\n]*\r?\n)*\s*if CycleRtssFrameCap\(direction\) \{') (
    "RTSS state rows must support A toggle and Left/Right cycling.")
Assert-True (
    $source -match
        '(?s)MigrateRtssPresetFrameCap\(\).*?CustomFrameCap.*?' +
        'IniWrite\(custom,\s*IniPath,\s*"RTSS",\s*"PresetFrameCap"\)' -and
    $sample -match '(?m)^PresetFrameCap=158(?:\s*;.*)?$' -and
    $source -match
        '(?s)CycleRtssFrameCap\(direction, wrap := false\).*?entries\.Push\("configured"\).*?' +
        'SetRtssGlobalFrameLimit\(customFps\).*?' +
        'SetRtssGlobalFrameLimit\(RtssPresetFrameCap\)' -and
    $source -match
        'RtssPresetFrameCap > 0 && !IsRtssFrameCapPreset\(RtssPresetFrameCap\)' -and
    $source -match
        '(?s)CommitRtssPendingFrameCap\(\).*?' +
        'PersistRtssCustomFrameCap\(value\)') (
    "The schema-8 RTSS Preset entry or retained Custom FPS behavior is incomplete.")

# The A button has no reverse, so it cannot use the clamped cycler Left/Right
# uses. It did, and the row was reported unusable: activate dead-ended on the
# last entry, and the Off shortcut jumped straight to the configured Preset near
# the end of the list. A user who only pressed A therefore saw OFF, PRESET and
# CUSTOM and could never reach 30/40/60/90/120 at all -- every standard cap was
# behind a Left press they had no reason to try.
Assert-True (
    $source -match '(?m)^CycleRtssFrameCap\(direction, wrap := false\) \{' -and
    $source -match
        '(?sm)^CycleRtssFrameCap\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if \(!wrap && direction > 0 && state\["mode"\] = "off"' -and
    $source -match
        '(?sm)^CycleRtssFrameCap\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if wrap \{(?:(?!\n\})[\s\S])*?index := entries\.Length' +
        '(?:(?!\n\})[\s\S])*?index := 1' -and
    $source -match 'CycleRtssFrameCap\(1, true\)') (
    "The Frame Limit row's A button no longer wraps, so part of its list is unreachable.")

# The frame cap can fail for two unrelated reasons and they need different
# answers. RTSSHooks64.dll is loaded into SteamShell's own process, so
# SaveProfile writes with SteamShell's token -- and against RTSS's default
# Program Files install an unelevated write is refused SILENTLY:
# SetProfileProperty succeeds against the in-memory copy, SaveProfile fails,
# UpdateProfiles reloads the old value, and every read afterwards returns the
# number that was already there. Confirmed on hardware 2026-08-02: the row
# logged a successful write on every press while the on-disk Global profile
# never changed, and running as administrator fixed it outright. The row must
# therefore stop claiming the RTSS BUILD is at fault, and must stop accepting
# presses it cannot honour.
Assert-True (
    $source -match
        '(?sm)^RtssFrameCapBlockedReason\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'This RTSS build cannot set the frame cap directly(?:(?!\n\})[\s\S])*?' +
        'if RtssFrameCapWriteBlocked(?:(?!\n\})[\s\S])*?' +
        'RTSS profile writes need administrator rights' -and
    $source -match
        '(?sm)^RtssFrameCapWritable\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'return RtssFrameCapBlockedReason\(\) = ""' -and
    $source -match '(?m)^global RtssFrameCapWriteBlocked := false$' -and
    $source -match
        '(?sm)^SetRtssGlobalFrameLimit\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'readBack := RtssGlobalFrameLimit\(\)(?:(?!\n\})[\s\S])*?' +
        'RtssFrameCapWriteBlocked := true' -and
    $source -notmatch
        '(?:ShowNotification|SetStatus)\("This RTSS build cannot set the frame cap directly"') (
    "A frame-cap write that RTSS accepts but discards is not detected, or is still blamed on the RTSS build.")


# A refresh re-derives the row list here, unlike standalone where the rows are
# fixed at build time. Until QuickMenuResizeToRows was reachable from the
# refresh path, a page whose row count grew mid-session kept the old window
# height and painted the new rows below its bottom edge. The RTSS page is where
# that showed, because its rows are composed from live RTSS state.
Assert-True (
    $source -match
        '(?sm)^QuickMenuRefresh\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'QuickMenuRows\.Length != QuickMenuSizedRowCount(?:(?!\n\})[\s\S])*?' +
        'QuickMenuResizeToRows\(\)' -and
    $source -match
        '(?sm)^QuickMenuResizeToRows\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'QuickMenuSizedRowCount := QuickMenuRows\.Length(?:(?!\n\})[\s\S])*?' +
        'QuickMenuEnsureContentFits\(\)' -and
    $source -match
        '(?sm)^QuickMenuBuildGui\(\)\s*\{(?:(?!\n\})[\s\S])*?QuickMenuResizeToRows\(\)') (
    "A Quick Menu refresh that changes the row count no longer resizes the window.")
# XFE had TWO hand-rolled copies of the controller-mouse arithmetic -- the poll
# loop and the Settings pointer surface -- and both are gone. The constant is
# what a re-implementation would have to contain, so its absence is the check.
Assert-True (
    $rawSource -notmatch '32767\.0' -and
    $source -match 'ApplyControllerMouseMove\(rx, ry,' -and
    $source -match 'ApplyControllerMouseScroll\(ly, ControllerScrollStep\)' -and
    $source -match 'ApplyControllerMouseScroll\(ly, 1\)' -and
    $source -match 'ResetControllerEdgeState\(' -and
    $source -notmatch '(?m)^ResetControllerHoldState\(') (
    "XFE must take controller-mouse movement, scroll and the hold reset from SteamShell-Common.ahk.")
# Hold-to-drag. Left click ONLY, and decided in the poll loop, never inside a
# binding executor.
#
# ExecuteControllerBinding has press-only callers -- standalone's Settings
# pointer fires RB.Short on press with nothing that will ever see the release --
# so a button-down issued there would never be lifted, inside the Settings
# window, which is the one place a user has no other pointer. The -notmatch is
# what keeps that true.
Assert-True (
    # The predicate itself lives in SteamShell-Common.ahk and is pinned by the
    # standalone validator, including that it does NOT cover right click. Only
    # XFE's own use of it is asserted here -- XFE contains 'Builtin:RightClick'
    # legitimately, in its defaults and its editor's builtin table.
    $source -match
        '(?sm)^ControllerBindingHoldsMouseButton\(bindingValue\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?"builtin:leftclick"' -and
    $rawSource -match 'ControllerBindingHoldsMouseButton\(' -and
    $rawSource -match 'HoldControllerMouseButton\("LButton"\)' -and
    $rawSource -notmatch
        '(?sm)^ExecuteControllerBinding\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?HoldControllerMouseButton') (
    "Hold-to-drag must be Left click only and decided in the poll loop, not in the binding executor.")

# XFE's editor is a flat key list, so the reserved row is a .Long whose matching
# .Short is Left click. It must be shown as reserved AND refuse to be set --
# accepting a binding that can never fire is the failure being prevented.
Assert-True (
    $source -match 'Reserved for mouse \(hold to drag\)' -and
    $source -match
        '(?sm)^MappingKeyIsReservedForMouse\(key\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ControllerBindingHoldsMouseButton\(GetBindingValue\(shortKey\)\)' -and
    ([regex]::Matches($source, 'if MappingKeyIsReservedForMouse\(key\) \{').Count -ge 2)) (
    "XFE's mapping editor must show a reserved Long slot and refuse to set it.")
# The companion must release a held mouse button on EVERY route out, and must arm the
# watchdog at top level. The watchdog is deliberately not beside the poll timer:
# a poll loop that has stopped is exactly the case it covers, so anything that
# cancels the poll must not cancel this.
Assert-True (
    $rawSource -match
        '(?sm)^OnCompanionExit\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?ReleaseControllerMouseButtons\(\)' -and
    # $source for the BODY, $rawSource for the REGISTRATION, and both are needed.
    #
    # The handler moved into SteamShell-Common.ahk once it turned out to be the
    # same function in both trees under two names. That makes the body assertion
    # a $source question -- but it also means a tree could stop calling OnError
    # entirely and the body would STILL be found, because Common supplies it.
    # Installing the handler is per-tree wiring and has to be asserted as such,
    # or the shared definition quietly covers for a program that never registers
    # it. Nothing asserted this before; only the elevated helper's equivalent was
    # pinned.
    $source -match
        '(?sm)^HandleUncaughtError\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?ReleaseControllerMouseButtons\(\)' -and
    $rawSource -match '(?m)^OnError\(HandleUncaughtError\)\s*$' -and
    $rawSource -match '(?m)^SetTimer\(ControllerMouseSafetyTick, 5000\)' -and
    # $source, not $rawSource: the watchdog itself moved into
    # SteamShell-Shared.ahk once it was byte-identical in both trees, so it is
    # only visible with #Includes resolved. The two assertions either side of
    # this one stay on $rawSource deliberately -- ARMING it at top level, and
    # not arming it from ApplyRuntimeTimers, are properties of this tree.
    $source -match
        '(?sm)^ControllerMouseSafetyTick\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ExpireControllerMouseButtons\(30000\)' -and
    $rawSource -notmatch
        '(?sm)^ApplyRuntimeTimers\(\)\s*\{(?:(?!\n\})[\s\S])*?ControllerMouseSafetyTick') (
    "The companion must release held mouse buttons on exit and on an uncaught error, and arm the watchdog unconditionally.")


# Automatic mouse mode is a master switch and an allowlist, and nothing else.
#
# It used to have a second gate standing in for standalone's DesktopMode: an
# "everywhere except these" mode whose exclusion list named Xbox FSE's shell
# processes. That list was a guess at someone else's shell, kept current by
# hand, standing in for a question -- "am I inside Xbox FSE right now?" -- that
# Windows gives no way to ask. Schema 11 removed it.
#
# Asserted in BOTH directions on purpose. Pinning only the allowlist would let
# the removed mode be reintroduced silently; the -notmatch half is what makes
# bringing it back a decision someone has to take deliberately.
Assert-True (
    $source -match '(?m)^global EnableAutoMouseMode := true$' -and
    $source -match '(?m)^global AutoMouseExeListRaw := "explorer\.exe"$' -and
    $source -notmatch 'EnableDesktopAutoMouseMode\s*:=' -and
    $source -notmatch 'DesktopAutoMouseExcludeExeSet' -and
    $source -match
        '(?sm)^AutoMouseModeActive\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if !EnableAutoMouseMode\s*\r?\n\s*return false\s*\r?\n' +
        '\s*if \(AutoMouseExeSet\.Count = 0\)\s*\r?\n\s*return false' +
        '(?:(?!\n\})[\s\S])*?' +
        'cachedResult := AutoMouseProcessMatches\(foregroundExe\)' -and
    $sample -match '(?m)^EnableAutoMouseMode=true$' -and
    $sample -match '(?m)^AutoMouseExeList=explorer\.exe(?:\s*;.*)?$' -and
    $sample -notmatch '(?m)^DesktopAutoMouseExcludeExeList=') (
    "XFE automatic mouse mode must be the master switch and AutoMouseExeList alone.")
# The retired keys have to be actively removed from an existing INI, not merely
# ignored. A value left sitting in the file the user edits reads as live
# configuration, which is the exact failure mode this removal exists to end.
Assert-True (
    $source -match
        '(?sm)^RetireDesktopAutoMouseSettings\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'IniDelete\(IniPath, "Controller", "EnableDesktopAutoMouseMode"\)' +
        '(?:(?!\n\})[\s\S])*?' +
        'IniDelete\(IniPath, "Controller", "DesktopAutoMouseExcludeExeList"\)' -and
    $source -match
        '(?sm)^EnsureSettingsFile\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RetireDesktopAutoMouseSettings\(\)') (
    "The retired automatic-mouse keys must be removed during settings migration.")
Assert-True (
    $source -match
        '(?s)ControllerSettingsSurfaceActive\(\).*?SettingsDialogActive.*?' +
        'IsOurWindow\(hwnd\)' -and
    $source -match
        '(?s)settingsSurfaceActive\s*:=\s*ControllerSettingsSurfaceActive\(\).*?' +
        'SystemCursor\("Show"\).*?MouseMove.*?Click\("Left"\)') (
    "XFE settings/editor windows no longer receive automatic controller mouse mode.")
# Both halves are bounded to the function body. The -notmatch in particular was
# unbounded, so it read "QuickMenuGui.Destroy( appears nowhere after this point
# in the resolved file" -- far broader than intended, and satisfied only because
# QuickMenuDestroyWindow lives in SteamShell-Shared.ahk, which #Include pulls in
# ABOVE this function. Reordering the includes would have failed the build
# without anything being wrong with the code.
Assert-True (
    $source -match
        '(?sm)^QuickMenuRefresh\(\)\s*\{(?:(?!\n\})[\s\S])*?QuickMenuRender\(\)' -and
    $source -notmatch
        '(?sm)^QuickMenuRefresh\(\)\s*\{(?:(?!\n\})[\s\S])*?QuickMenuGui\.Destroy\(') (
    "Quick Menu selection refresh must update the open session without rebuilding the GUI.")
# The rows are one painted surface, not a pool of Static controls. A Win32
# static cannot draw a rounded corner, an outline or a glow, which is why the
# pool was replaced rather than restyled.
Assert-True (
    $source -match '(?s)QuickMenuRender\(\)\s*\{.*?QuickMenuPaintRows\(\)' -and
    $source -notmatch 'QuickMenuLabelCtrls' -and
    $source -notmatch 'QuickMenuValueCtrls') (
    "The Quick Menu rows are no longer painted as a single GDI+ surface.")

# Painting must stay OPAQUE and non-layered. The menu's job is appearing over a
# running game; per-pixel alpha over fullscreen D3D is where overlays fail.
Assert-True (
    $source -notmatch 'UpdateLayeredWindow' -and
    $source -match '(?s)QuickMenuPaintRows\(\).*?GdipSetTextRenderingHint.*?"Int",\s*5') (
    "Quick Menu painting is layered, or has given up ClearType text.")

# STM_SETIMAGE hands back the bitmap it replaced. The menu repaints on every
# keypress, so failing to delete it leaks a bitmap per press.
Assert-True (
    $source -match
        '(?s)replaced\s*:=\s*SendMessage\(0x0172.*?if\s*\(replaced\s*&&\s*replaced\s*!=\s*bitmap\).*?DeleteObject') (
    "The Quick Menu row painter leaks the bitmap it replaces.")

# The surface is built at the control's physical size. Building it at
# AutoHotkey's logical size would stretch every row on a high-DPI handheld.
Assert-True (
    $source -match
        '(?s)QuickMenuPaintRows\(\).*?GetClientRect.*?(?:' +
        'scale\s*:=\s*width\s*/\s*QuickMenuWidth\(\)' + '|' +
        'logicalWidth\s*:=\s*QuickMenuWidth\(\).*?scale\s*:=\s*width\s*/\s*logicalWidth' +
        ')') (
    "The Quick Menu row surface is no longer built at physical pixel size.")

# The reference design uses neutral charcoal, a visible glow with room outside
# the first/last row, and no native or DWM-drawn outer frame.
Assert-True (
    $source -match 'QM_BG\s*:=\s*"242424"' -and
    $source -match '(?s)ApplyRoundedCorners\([^)]*\).*?guiObj\.Opt\("-Border"\)' -and
    $source -match
        '(?s)ApplyRoundedCorners\([^)]*\).*?NumPut\("UInt",\s*0xFFFFFFFE,\s*borderColor.*?' +
        '"UInt",\s*34,\s*"Ptr",\s*borderColor' -and
    $source -match 'QM_LABEL\s*:=\s*"D8D8D8"' -and
    $source -match 'QM_VALUE\s*:=\s*"A0A0A0"' -and
    $source -notmatch 'DwmExtendFrameIntoClientArea' -and
    $source -match '(?s)QuickMenuGlowPadding\(\)\s*\{\s*return\s+8' -and
    $source -match '(?s)QuickMenuDrawGlow\([^\r\n]*\r?\n\s*,\s*QM_ACCENT,\s*8,\s*120') (
    "The Quick Menu neutral palette, visible-glow, or borderless design has regressed.")

# Bitmap changes must be atomic and redraw without an erase pass. Erasing the
# Static or parent window between frames produces a visible flash on navigation.
Assert-True (
    $source -match
        '(?s)QuickMenuPaintRows\(\).*?0x000B.*?SendMessage\(0x0172.*?' +
        '0x000B.*?0x0121' -and
    $source -match '(?s)QuickMenuSetRedraw\([^)]*\).*?0x01A1') (
    "Quick Menu bitmap swaps or page redraws can erase between frames and flicker.")

# The HWND is deliberately persistent only while the menu is open. Keeping a
# hidden window alive lets DWM resurrect its child surfaces after a fullscreen
# presentation transition, producing a scrambled, noninteractive ghost menu.
Assert-True (
    $source -match '(?s)HideQuickMenu\([^)]*\).*?ShowWindow.*?QuickMenuGui\.Hide\(\).*?QuickMenuDestroyWindow\(\)' -and
    $source -match
        '(?s)QuickMenuDestroyWindow\(\).*?SendMessage\(0x0172,\s*0,\s*0,\s*QuickMenuRowsCtrl\).*?' +
        'QuickMenuGui\.Destroy\(\).*?QuickMenuGui\s*:=\s*unset') (
    "Closing the Quick Menu must destroy its HWND and detach its owned bitmap.")

# ONE enumeration, matching the rule the shell's validator has always enforced.
#
# This product had three -- the assist inventory, the screen probe and the task
# switcher -- each with its own filter, and the filters had drifted apart. They
# all read SharedWindowInventoryBuild now, and the count is what stops a fourth
# appearing. Measured over the effective source, so it covers Shared.
$fullWindowScans = [regex]::Matches($source, 'WinGetList\(\)')
Assert-True ($fullWindowScans.Count -eq 1) (
    "Only SharedWindowInventoryBuild may perform an unfiltered full-window " +
    "enumeration; found $($fullWindowScans.Count).")

Assert-True (
    $source -match
        '(?s)SharedTaskSwitcherWindows\([^)]*\)\s*\{.*?' +
        'steam\s*:=\s*item\["steam"\].*?' +
        'item\["cloaked"\]\s*&&\s*!steam.*?' +
        'item\["title"\]\s*=\s*""\s*&&\s*!steam.*?' +
        'item\["toolWindow"\]\s*&&\s*!steam') (
    "The task switcher must retain Steam Big Picture when Steam publishes it as a " +
    "cloaked, untitled tool window under Xbox FSE.")
Assert-True (
    $source -match '(?s)AssistInventoryBuild\(\).*?item\["toolWindow"\].*?&&\s*!item\["steam"\]' -and
    $source -match '(?s)AssistFindSteamWindow\([^)]*\).*?IsSteamProcess\(item\["exe"\]\).*?area\s*:=\s*item\["w"\]\s*\*\s*item\["h"\].*?area\s*>\s*bestArea') (
    "Steam Assist must retain Steam Big Picture tool windows and choose the largest Steam surface.")

$assistGameRunning = [regex]::Match(
    $source, '(?ms)^AssistGameIsRunning\([^)]*\)\s*\{.*?^\}')
Assert-True (
    $assistGameRunning.Success -and
    $assistGameRunning.Value -match 'AssistWindowLooksLikeGame\(item\)\s*\r?\n\s*return true' -and
    $assistGameRunning.Value -match 'pids\[item\["pid"\]\]' -and
    $assistGameRunning.Value -match 'AssistProcessCpuSample\(pid\)' -and
    $assistGameRunning.Value -match 'sample\["known"\]' -and
    $source -match 'gameRunning\s*:=\s*AssistGameIsRunning\(inventory\)' -and
    $source -notmatch 'AssistProcessCpuPercent\(') (
    "Game-running detection must combine the shape fast path with known CPU samples from non-fullscreen processes.")

# The per-game RTSS target is the SCORED answer and nothing else.
#
# A per-game cap is keyed on an executable NAME, so a misidentification does not
# degrade gracefully: the cap lands in another program's RTSS profile and is
# reported as saved.
#
# There is no LastObservedGameExe fallback any more, and its absence is the thing
# pinned here. That global is set by ObserveForeground from the FOREGROUND WINDOW
# ONLY and holds a stored name that outlives the process it names -- which is how
# a cap reached a profile for a game that had already exited. It existed to cover
# a minimized game, which the scorer could not see; the shared
# WindowEngineIsMinimizedLegacyGameSurface detector means it can, so the stand-in
# is gone rather than demoted.
Assert-True (
    $rawSource -match
        '(?sm)^ProductBestGameExe\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'return XfeBestGameWindow\(\)' -and
    $rawSource -notmatch
        '(?sm)^ProductBestGameExe\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'return LastObservedGameExe' -and
    # ...and the scorer must actually ask about minimized surfaces, or removing
    # the fallback would have lost the case it covered.
    $rawSource -match
        '(?sm)^XfeBestGameWindow\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'minimizedLegacy := WindowEngineIsMinimizedLegacyGameSurface\(item\)' -and
    $rawSource -notmatch
        '(?sm)^XfeBestGameWindow\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"minimizedLegacy", false') (
    "The per-game RTSS target has a foreground-observation fallback again, or " +
    "the scorer stopped recognising a minimized game, which is what that " +
    "fallback used to stand in for.")

# The scorer weighs CPU and audio, and both are sampled lazily.
Assert-True (
    $rawSource -match
        '(?sm)^XfeBestGameWindow\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'GameWindowShapeVerdict\((?:(?!\n\})[\s\S])*?' +
        'AssistProcessCpuSample\((?:(?!\n\})[\s\S])*?' +
        'GameWindowCpuVerdict\((?:(?!\n\})[\s\S])*?' +
        'GetActiveAudioPidPeaksCached\((?:(?!\n\})[\s\S])*?' +
        'SortCandidatesByScoreAreaDesc\(' -and
    # The ordering above is necessary but not sufficient: an EXTRA sample added
    # ahead of the shape test leaves that sequence intact while destroying the
    # laziness it exists to protect. These forbid the earlier call outright.
    $rawSource -notmatch
        '(?sm)^XfeBestGameWindow\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'AssistProcessCpuSample\((?:(?!\n\})[\s\S])*?GameWindowShapeVerdict\(' -and
    $rawSource -notmatch
        '(?sm)^XfeBestGameWindow\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'GetActiveAudioPidPeaksCached\((?:(?!\n\})[\s\S])*?GameWindowCpuVerdict\(') (
    "The game scorer no longer runs shape then CPU then audio in order, which " +
    "is what keeps the expensive signals off windows that were already rejected.")

# No score floor on the RTSS naming path, matching the shell.
#
# A floor here was worse than none. Falling below it returned LastObservedGameExe
# -- the foreground-only observation the scorer exists to replace -- so a low
# score discarded a scored answer in favour of an unscored one. The shell sets
# LastBestCandidateProc from its best candidate unconditionally; its
# GameMinScoreToActivate governs pulling FOCUS to a game, which is a disruptive
# act and a different question from naming a profile.
Assert-True (
    $rawSource -match
        '(?sm)^XfeBestGameWindow\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'return candidates\[1\]\["exe"\]' -and
    $rawSource -notmatch 'XfeGameMinScore' -and
    $rawSource -notmatch '(?sm)^XfeBestGameWindow\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'score"\] <') (
    "A score floor is back on the RTSS naming path, which sends a low-scoring " +
    "but scored candidate back to the unscored foreground observation.")

# The assist shape test is NOT the scorer and must stay as it was.
Assert-True (
    $rawSource -match
        '(?sm)^AssistWindowLooksLikeGame\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'item\["w"\] >= monitorWidth \* 0\.85') (
    "AssistWindowLooksLikeGame changed. It drives Game Focus and Launcher " +
    "Cleanup; the scorer is a separate question and must not alter it.")
Assert-True (
    $source -match '(?s)AssistForegroundIsProtected\([^)]*\).*?exe\s*=\s*"explorer\.exe"' -and
    $sample -match '(?m)^IgnoreForegroundProcesses=explorer\.exe\|') (
    "Assist must never take focus away from Explorer-owned Windows shell surfaces.")

$assistHardKill = [regex]::Match(
    $source, '(?ms)^AssistHardKillLaunchers\(\)\s*\{.*?^\}')
Assert-True (
    $assistHardKill.Success -and
    $assistHardKill.Value -match 'CompanionDisabled.*?!EnableLauncherCleanupLite.*?!AssistHardKill' -and
    $assistHardKill.Value -match 'AssistGameIsRunning\(inventory\)' -and
    $assistHardKill.Value -match 'for pid, expected in pending' -and
    $assistHardKill.Value -match 'launcherSet\.Has\(expected\["exe"\]\)' -and
    $assistHardKill.Value -match 'protectedSet\.Has\(expected\["exe"\]\)' -and
    $assistHardKill.Value -match 'expected\["creation"\]' -and
    $assistHardKill.Value -match 'ProcessClose\(pid\)' -and
    $assistHardKill.Value -notmatch 'ProcessClose\(exe\)' -and
    $source -match '(?s)ApplyRuntimeTimers\(\).*?SetTimer\(AssistHardKillLaunchers,\s*0\).*?AssistPendingHardKillPids\s*:=\s*Map\(\)') (
    "Delayed launcher force-close must revalidate state and target only the original process identities.")
Assert-True (
    $source -match '(?s)SendSteamOverlayChord\(\).*?SetKeyDelay\(35,\s*80\).*?SendEvent\(SteamOverlayShortcut\)' -and
    $source -match '(?s)ViewButtonReleased\([^)]*\).*?else\s*\r?\n\s*SendSteamOverlayChord\(\)' -and
    $source -match '(?s)QuickMenuHideThenSteamMenu\([^)]*\).*?SetTimer\(SendSteamOverlayChord,\s*-150\)' -and
    $source -match '(?s)case "steamMenu":.*?QuickMenuHideThenSteamMenu\(IsSteamProcess\(QuickMenuPreviousExe\)\)') (
    "Both in-game Steam overlay actions must use the held-key overlay sender.")
Assert-True (
    $source -notmatch 'MenuRow\("health", "Run Health Check"' -and
    $source -notmatch 'MenuRow\("screenProbe", "Probe Screen"' -and
    $source -notmatch 'MenuRow\("rearmInput", "Re-arm Controller Input"' -and
    $source -match '(?s)case "SYSTEM":.*?MenuRow\("sleep".*?MenuRow\("restart".*?MenuRow\("shutdown".*?MenuRow\("exitApp"') (
    "The System Quick Menu must stay limited to power and companion-exit actions.")
Assert-True (
    $source -match
        '(?s)case\s+"MAIN":.*?MenuRow\("gameBar".*?' +
        'MenuRow\("openKeyboard",\s*"Open Keyboard".*?' +
        'MenuRow\("qPersistentMouse",\s*"Mouse Mode".*?' +
        'MenuRow\("settings".*?' +
        'MenuRow\("system"' -and
    # The value text moved into QuickMenuValue when rows stopped carrying it.
    $source -match 'case "settings": return "Features & Configuration"' -and
    $source -match 'case "system": return "Power & Diagnostics"' -and
    $source -notmatch 'MenuRow\("layoutPage"') (
    "The main Quick Menu rows, order, or title capitalization have regressed.")
# Every settings row must render its value, and Back must render its arrow.
#
# QuickMenuRowValueText resolved values only the shell's way -- QuickMenuValue by
# row id -- and this tree's settings rows carry ids like "toggle:qParkEdge" that
# it has no case for. The whole Quick Menu settings page therefore showed labels
# with an empty column beside them, on the page a user opens in order to READ the
# current setting. Back rows were worse: the arrow is drawn from a "back" field
# on the row Map, which MenuRow does not create, so no page showed one.
#
# Both halves are pinned because neither fails anything at build time, and the
# row inventory cannot see either: it records ids, and these are values.
Assert-True (
    $source -match '(?s)QuickMenuSettingRow\(id, label\)\s*\{(?:(?!\n\})[\s\S])*?QuickMenuSettingValueText\(id\)' -and
    $source -match '(?s)QuickMenuRowValueText\(row\)\s*\{(?:(?!\n\})[\s\S])*?row\.Has\("value"\)(?:(?!\n\})[\s\S])*?QuickMenuValue\(id\)' -and
    $source -match '(?s)QuickMenuRowValueText\(row\)\s*\{(?:(?!\n\})[\s\S])*?id = "back"') (
    "Quick Menu rows must render a value: settings rows must state theirs, " +
    "QuickMenuRowValueText must believe a row that does and ask only when it " +
    "does not, and a Back row must be recognised by id as well as by field.")

# The value column says what the setting IS, and nothing else.
#
# A plain on/off row reads "ON", not "< ON >". The shell wraps a value in arrows
# where it chooses to -- HDR, the display modes, the live RTSS state -- and those
# rows say so themselves. Wrapping every steppable row made a whole settings page
# read "< ON >" and did not match the shell, which is the product this one
# follows.
Assert-True (
    $source -notmatch 'QuickMenuSettingIsSteppable' -and
    $source -notmatch '(?s)QuickMenuRowValueText\(row\)\s*\{(?:(?!\n\})[\s\S])*?"‹ " text') (
    "Quick Menu values must not be wrapped in arrows by the renderer; a row that " +
    "wants them says so itself, as the shell does.")

# The task switcher must PAGE, not truncate.
#
# It used to build `Loop Min(QuickMenuTaskWindows.Length, 13)` to fit the row
# control pool. That is not a shortened list, it is a list with no end marker: a
# fourteenth window could not be reached and nothing on screen said one existed.
# The failure is silent by construction, which is why the truncating form is
# forbidden by name rather than the paging form merely being required.
Assert-True (
    $source -match '(?s)case\s+"TASKS":(?:(?!\n\s{8}case )[\s\S])*?QuickMenuTaskSlice\(' -and
    $source -match '(?s)case\s+"TASKS":(?:(?!\n\s{8}case )[\s\S])*?"taskPrev"' -and
    $source -match '(?s)case\s+"TASKS":(?:(?!\n\s{8}case )[\s\S])*?"taskNext"' -and
    $source -notmatch 'Loop Min\(QuickMenuTaskWindows\.Length' -and
    # Both page rows must reach the pager from both A and Left/Right, or one of
    # them renders as a row that does nothing -- the exact shape the Mouse Mode
    # row failed in.
    $source -match '(?s)case\s+"taskPrev":\s*\r?\n\s*ChangeQuickMenuTaskPage\(-1\)' -and
    $source -match '(?s)case\s+"taskNext":\s*\r?\n\s*ChangeQuickMenuTaskPage\(1\)' -and
    $source -match '(?s)case\s+"taskPrev",\s*"taskNext":\s*\r?\n\s*ChangeQuickMenuTaskPage\(direction\)') (
    "The companion task switcher must page through its windows rather than " +
    "truncate the list at the size of the control pool.")

Assert-True (
    $source -match
        '(?s)case\s+"openKeyboard":.*?HideQuickMenu\(\).*?' +
        'SetTimer\(OpenTouchKeyboard,\s*-100\)' -and
    $source -match
        '(?s)case\s+"windowsSettings":.*?HideQuickMenu\(\).*?' +
        'SetTimer\(OpenWindowsSettings,\s*-100\)' -and
    $source -match
        '(?s)case\s+"SETTINGS":.*?MenuRow\("windowsSettings",\s*"Windows Settings"') (
    "Keyboard or Windows Settings does not dismiss the Quick Menu before opening.")
Assert-True (
    $source -match
        '(?s)QuickMenuTogglePersistentMouse\(label\)\s*\{.*?' +
        'EnablePersistentMouseMode' -and
    $source -match
        '(?s)QuickMenuTogglePersistentMouse\(label\)\s*\{.*?enabledControllerMaster.*?' +
        'EnableControllerMouseMode' -and
    $source -match
        '(?s)mappingActive\s*:=\s*viewDown\s*\|\|\s*autoMouse.*?' +
        'if\s*!mappingActive' -and
    # Persistent mode reaches the poll loop through AutoMouseModeActive now, so
    # the short-circuit that makes it unconditional is what has to be asserted.
    $source -match
        '(?s)AutoMouseModeActive\(\)\s*\{.*?if EnablePersistentMouseMode\s*\r?\n\s*return true') (
    "Persistent Mouse Mode is not persisted or connected to controller polling.")
Assert-True (
    $source -match
        '(?s)QuickMenuHandleController\([^)]*\).*?buttons\s*&\s*0x8000.*?' +
        'QuickMenuPage\s*:=\s*"LAYOUT".*?QuickMenuBuildGui\(\)' -and
    $source -match
        '(?s)case\s+"LAYOUT":.*?MenuRow\("setControllerMappings",\s*' +
        '"Set Controller Mappings".*?"setControllerMappings"\)' -and
    $source -match
        '(?s)case\s+"setControllerMappings":.*?' +
        'SetTimer\(ShowMappingEditor,\s*-100\)') (
    "Holding Y must open the Quick Settings mapping page and its editor action.")
Assert-True (
    $source -match 'Hold Y for Controller Mappings') (
    "The main-page controller mapping hint is incomplete.")
Assert-True (
    $source -match
        '(?s)HideQuickMenu\([^)]*\).*?ControllerNeedsFreshBaseline\s*:=\s*true' -and
    $source -match
        '(?s)if\s*\(wasDisabled\s*\|\|\s*ControllerNeedsFreshBaseline\).*?' +
        'ResetControllerEdgeState\(downTick,\s*longFired,\s*triggerDown') (
    "Closing Quick Settings can leak its final button release into persistent mappings.")
Assert-True ($source -notmatch 'Add\(\s*"Tab3"') (
    "The overlapping tabbed Settings layout has returned.")
Assert-True (
    $source -match 'SettingsCategoryList' -and
    $source -match 'SettingsChangeCategory\(') (
    "The sidebar Settings category navigation is incomplete.")
# A `&` output parameter is left UNSET when the call fails, which beats any
# initialisation done beforehand. So a BARE `try WinGetPos(&x, ...)` followed by a
# use of x crashes the moment the window disappears mid-call. This was fixed once
# in 0.1.2 for `actualWidth`, and the guard named that one variable -- so the same
# bug came straight back as `finalX`. The rule is now about the SHAPE: measure
# inside a braced try and copy out only on success.
$bareTryWinGetPos = [regex]::Matches($source, '(?m)^\s*try\s+WinGetPos\s*\(')
Assert-True ($bareTryWinGetPos.Count -eq 0) (
    "Found $($bareTryWinGetPos.Count) bare 'try WinGetPos(...)' call(s). Use a braced " +
    "try and copy the outputs only on success; a failed call leaves them unset.")
Assert-True (
    $source -match '(?s)CenterGuiOnMonitorActual\([^)]*\).*?WinGetPos\(&measuredX,\s*&measuredY,\s*&measuredWidth,\s*&measuredHeight' -and
    $source -notmatch 'WinGetPos\([^)]*&actualWidth') (
    "GUI centering must not allow a failed ByRef measurement to unset its fallback dimensions.")
Assert-True (
    $source -match '(?s)XInputResolveController\([^)]*\).*?Loop\s+4' -and
    $source -match 'No XInput controller detected on slots 0') (
    "Automatic four-slot XInput discovery or its diagnostic logging is missing.")

# RAWINPUTHEADER.hDevice handles are not stable across sleep/resume: the same
# controller returns with a new handle. A permanent device lock therefore rejects
# every report the controller sends after a wake, silently and forever.
$claimMatch = [regex]::Match(
    $source, '(?ms)^RawInputClaimDevice\([^)]*\)\s*\{.*?^}')
Assert-True (
    $claimMatch.Success -and
    $claimMatch.Value -match 'DEVICE_HANDOVER_MS' -and
    $claimMatch.Value -notmatch 'if \(RawInputDevice && device != RawInputDevice\)\s*\r?\n\s*return false') (
    "The RawInput device lock must be handed over when the locked device goes quiet.")
# Resume must be detected without relying on WM_POWERBROADCAST, which is not
# reliably delivered under modern standby -- the state a handheld sleeps into.
#
# This used to assert the SHAPE the detector happened to have: a Heartbeat body
# mentioning LastHeartbeatStamp and RawInputReregister. The detector moved into
# ControllerResumeGapCheck in SteamShell-Shared.ahk and is now driven from
# PollController in both products, so the old pattern failed while the guarantee
# was intact and had in fact got stronger -- it fires within about 30 seconds
# instead of 150, and the shell gained it, having previously had no wall-clock
# resume detection at all.
#
# So the assertion is rewritten against the GUARANTEE rather than the shape, and
# it is stricter than what it replaces on the one point that actually matters:
#
#   WALL CLOCK, NOT A_TickCount. The tick counter does not advance through
#   suspend, so a gap check written on ticks sees nothing and silently reports
#   that the machine never slept. The old assertion did not test this at all --
#   a rewrite to A_TickCount would have kept it passing and killed the feature.
#
# Also asserts the detector is CALLED. A resume detector that is defined and
# never driven is the same as not having one, and #Include means a stale call
# site fails nothing at load time.
$resumeGap = [regex]::Match(
    $source, '(?ms)^ControllerResumeGapCheck\([^)]*\)\s*\{.*?^}')
Assert-True (
    $source -match 'OnMessage\(0x0218, PowerBroadcastMessage\)' -and
    $resumeGap.Success -and
    $resumeGap.Value -match 'A_Now' -and
    $resumeGap.Value -match 'DateDiff' -and
    $resumeGap.Value -match 'RawInputReregister' -and
    $source -match
        '(?ms)^PollController\(\)\s*\{(?:(?!\n\})[\s\S])*?ControllerResumeGapCheck\(') (
    "Resume recovery must have a wall-clock gap fallback driven from the " +
    "controller poll, not only the power broadcast. ControllerResumeGapCheck " +
    "must compare A_Now via DateDiff -- A_TickCount does not advance through " +
    "suspend -- and must re-register RawInput.")
Assert-True ($source -match 'RearmControllerInput') (
    "A manual controller re-arm path must exist for when input is dead and the Quick Menu cannot be opened.")

# Test-ControllerProfiles.py MIRRORS the learning heuristic rather than executing
# it, which is the only way to test this off Windows -- but it means the two can
# drift silently, and a mirror that agrees only with itself proves nothing. The
# tuning constants are where drift would actually happen, so they are compared
# directly.
if (Test-Path $controllerSimulationPath) {
    $simulation = Get-SourceText $controllerSimulationPath
    $sharedConstants = @{
        'MIN_NORMALISED_DELTA' = '(?m)^\s*static MIN_NORMALISED_DELTA\s*:=\s*([0-9.]+)'
        'MIN_BYTE_EXCURSION'   = '(?m)^\s*static MIN_BYTE_EXCURSION\s*:=\s*([0-9.]+)'
        'MIN_PAIR_BALANCE'     = '(?m)^\s*static MIN_PAIR_BALANCE\s*:=\s*([0-9.]+)'
    }
    foreach ($name in $sharedConstants.Keys) {
        $ahkMatch = [regex]::Match($source, $sharedConstants[$name])
        $pyMatch = [regex]::Match($simulation, "(?m)^$name\s*=\s*([0-9.]+)")
        Assert-True ($ahkMatch.Success -and $pyMatch.Success) (
            "Shared learning constant $name must exist in both the source and the simulation.")
        Assert-True ($ahkMatch.Groups[1].Value -eq $pyMatch.Groups[1].Value) (
            "Learning constant $name has drifted: source=" +
            $ahkMatch.Groups[1].Value + " simulation=" + $pyMatch.Groups[1].Value)
    }
    Assert-True (
        $simulation -match 'test_analog_scan_protects_stick_click_steps') (
        "The simulation must cover a stick nudged during a stick-click step.")
    # The two magic ratios inside the width decision, checked the same way.
    foreach ($ratio in @('0\.55', '0\.45')) {
        Assert-True (
            ($source -match $ratio) -and ($simulation -match $ratio)) (
            "The axis width-selection ratio $ratio must appear in both the source and the simulation.")
    }
}

# The learning wizard diverts only the RawInput path, so the poll loop would keep
# reading the same pad through XInput and firing its normal mappings at every
# prompt. Measured: B ran Builtin:Esc and closed the wizard; A, X, Y and Start all
# had side effects too. The whole pipeline must be inert while learning.
Assert-True (
    $source -match '(?s)PollController\(\)\s*\{.*?global[^\r\n]*LearnActive' -and
    $source -match '(?s)PollController\(\)\s*\{.*?if LearnActive\s*\{.*?ResetControllerEdgeState[^\r\n]*\r?\n\s*return.*?if !ControllerReadState') (
    "PollController must ignore controller input entirely while the learning wizard is open.")
# With the controller inert, Skip is unreachable from the couch, so a digital step
# that never sees its control has to advance by itself.
Assert-True (
    $source -match '(?s)ControllerLearnTick\(\).*?if \(step\["kind"\] != "axis"\) \{.*?ControllerLearnNextStep') (
    "Button and D-pad steps must time out and skip themselves; the controller is suppressed while learning.")

# Analogue bytes are identified before any button step, and excluded from button
# and D-pad detection. At rest an axis low byte is 0x00, so nudging the stick sets
# bits that were clear at rest -- exactly the test a button has to pass. It bites
# hardest on L3/R3, where the stick must be touched to click it in.
Assert-True (
    $source -match 'ControllerLearnClassifyAnalog\(' -and
    $source -match '"kind", "wiggle"' -and
    $source -match '(?s)if \(kind = "button"\).*?if \(LearnAnalogBytes\.Has\(offset\)\)' -and
    $source -match '(?s)if \(kind = "dpad"\).*?if \(LearnAnalogBytes\.Has\(offset\)\)') (
    "Button and D-pad detection must ignore bytes the analogue scan identified.")
# The Quick Menu must fit its own content. Computing the height in logical units
# and trusting AutoHotkey to scale it the same way as the controls failed on a 4K
# television: the first show came out short and the bottom rows were cut off.
Assert-True (
    $source -match 'QuickMenuEnsureContentFits\(' -and
    $source -match '(?s)QuickMenuEnsureContentFits\([^)]*\)\s*\{.*?ControlGetPos\(') (
    "The Quick Menu must verify its height against the measured control positions.")
# WinSetRegion CLIPS the window, and a hidden window can report a wrong size. A
# region built from a hidden measurement cut the menu off with a rounded edge
# straight through a row, so shaping a hidden window is banned outright.
$roundedMatch = [regex]::Match($source, '(?ms)^ApplyRoundedCorners\([^)]*\)\s*\{.*?^}')
Assert-True (
    $roundedMatch.Success -and
    $roundedMatch.Value -match 'IsWindowVisible' -and
    $roundedMatch.Value -match 'if !visible\s*\r?\n\s*return') (
    "Rounded corners must never be applied to a hidden window; the region would clip it.")
# The window must be revealed before it is measured and shaped.
Assert-True (
    $source -match '(?s)if deferred\s*\r?\n\s*RevealWindow\(QuickMenuGui\).*?QuickMenuEnsureContentFits\(\).*?ApplyRoundedCorners\(QuickMenuGui, 30\)') (
    "The Quick Menu must be revealed before its size is verified and its corners applied.")
# A learned profile that reads as deflected at rest makes the pointer run away,
# which also makes it hard to reach the UI to undo. It must be checked and
# removable without the pointer.
Assert-True (
    $source -match 'ControllerProfileRestCheck\(' -and
    $source -match 'DeleteControllerProfileForActiveDevice\(' -and
    $source -match 'Hotkey\("\^!\+d", DeleteControllerProfileForActiveDevice\)') (
    "A saved controller profile must be rest-checked and removable by hotkey.")
# Inside Xbox FSE the first foreground grab loses to FSE re-asserting its window.
Assert-True (
    $source -match 'SettingsForegroundRetry\(') (
    "The Settings window must retry taking the foreground.")
# The Quick Menu value column is right-aligned, so overlong text is clipped from
# the LEFT. Anything that must survive has to come last. The volume used to be
# first and was the part being cut, which read as a broken volume.
$audioSummary = [regex]::Match($source, '(?ms)^GetAudioSummary\(\)\s*\{.*?^}')
Assert-True (
    $audioSummary.Success -and
    $audioSummary.Value -match 'GetVolumeText\(\)\s*$' -or
    $audioSummary.Value -match 'GetAudioOutputName\(\)[^\r\n]*GetVolumeText\(\)') (
    "The audio summary must end with the volume; the value column clips from the left.")

# Volume must render a number or say why not, never a bare percent sign.
Assert-True (
    $source -notmatch '(?m)^\s*try return Round\(SoundGetVolume\(\)\) "%"') (
    "Volume text must validate the reading before formatting it.")

# Xbox FSE is a fullscreen window, so a normal window can hold the foreground and
# still render behind it. Settings was focused but invisible until the task
# switcher revealed it; no amount of retrying SetForegroundWindow fixes z-order.
#
# Pinned on the OPTION, not on the whole string. It used to name the minimum
# size too, so widening the window to the shell's 980 failed a rule that has
# nothing to say about width.
Assert-True (
    $source -match 'Gui\("-Resize \+AlwaysOnTop \+MinSize\d+x\d+"') (
    "The Settings window must be always-on-top or it renders behind Xbox FSE.")
# The columns are the shell's, so the window has to be wide enough for them:
# content starts at 255 and runs 690 wide, and the scrollbar sits at 954.
Assert-True (
    $source -match 'MinSize9[89]\dx' -and
    $source -match '"contentX", 255, "contentWidth", 690' -and
    $source -match '"scrollBarX", 954') (
    "The Settings window is narrower than the columns it draws; content or the " +
    "scrollbar would fall outside it.")
# A hidden/pre-show measurement can omit the scaled title bar and frame, leaving
# Settings visibly too low and its bottom outside the monitor work area. Correct
# it from the actual visible outer rectangle after Gui.Show has sized it.
Assert-True (
    $source -match 'CenterGuiOnMonitorActual\(settings,\s*monitorIndex,\s*920,\s*660\)' -and
    $source -match 'RecenterVisibleGuiOnMonitorActual\(settings,\s*monitorIndex\)' -and
    $source -match '(?s)RecenterVisibleGuiOnMonitorActual\([^)]*\)\s*\{.*?WinGetPos\(&visibleX,\s*&visibleY,\s*&visibleW,\s*&visibleH.*?CenteredPosition\(.*?MoveWindowPhysical\(') (
    "Settings must be recentered from its actual visible outer size.")
Assert-True (
    $simulation -match 'test_settings_layout_has_no_overlaps') (
    "The simulation must check the Settings layout for overlapping controls.")

# Mouse coordinates must be screen-relative. AutoHotkey v2 defaults Mouse to
# Client, which made the cursor reappear every time the Quick Menu moved: the
# origin shifted, so an unmoved pointer read as having moved.
Assert-True ($source -match '(?m)^CoordMode "Mouse", "Screen"$') (
    "CoordMode Mouse must be set to Screen in the auto-execute section.")
# Opening one of our own windows from the Quick Menu must not hand the foreground
# back first; Xbox FSE re-asserts it and the new window never comes forward.
Assert-True (
    $source -match 'HideQuickMenuForOwnWindow\(' -and
    $source -match '(?s)case "settingsEditor":\s*\r?\n\s*HideQuickMenuForOwnWindow\(\)') (
    "Opening Settings from the Quick Menu must suppress the focus hand-back.")
# Window resizing must be done by Gui.Show, not by a predicted physical size: a
# mismatch does not wobble the window, it sizes it wrong and cuts content off.
Assert-True (
    $source -match '(?s)PositionGuiCentered\(.*?if wasVisible \{.*?Show\("NA w" width " h" height\)') (
    "A visible window must be resized by Gui.Show rather than a predicted DPI size.")

# USB HID specifies little-endian for multi-byte fields, so the learner must never
# guess big-endian. Offering it doubled the search space for something that does
# not exist, and produced a stick pinned at +19300 that sent the pointer flying.
# The DECODER keeps u16be so a hand-written profile can use it.
$resolveMatch = [regex]::Match(
    $source, '(?ms)^ControllerLearnResolveAxis\([^)]*\)\s*\{.*?^}')
Assert-True (
    $resolveMatch.Success -and
    $resolveMatch.Value -notmatch 'ControllerLearnAxisStats\([^)]*"u16be"') (
    "The learner must not offer big-endian candidates; HID multi-byte fields are little-endian.")
Assert-True ($source -match '"u16be"') (
    "The decoder must still understand u16be for hand-written profiles.")
# A self-centring stick cannot rest away from the middle of its range, and two
# sticks cannot share bytes. Both were violated by profiles learned on hardware.
Assert-True (
    $resolveMatch.Success -and
    $resolveMatch.Value -match 'STICK_NAMES' -and
    $resolveMatch.Value -match 'centreFraction') (
    "Stick axes must be rejected when their rest value is not near the centre of range.")
Assert-True (
    $resolveMatch.Success -and
    $resolveMatch.Value -match 'static STICKS :=') (
    "A stick must not be allowed to reuse bytes already claimed by another stick.")

# The four D-pad directions only mean anything as a set. A single diagonal press
# records the diagonal hat value, which breaks the even spacing AND collides in the
# bit fallback, quietly ruining the whole D-pad.
Assert-True (
    $source -match 'ControllerLearnValidateDpad\(' -and
    $source -match '(?s)ControllerLearnNextStep\(\).*?ControllerLearnValidateDpad\(' -and
    $source -match 'LearnDpadRetries') (
    "The four D-pad directions must be validated as a set, with a bounded retry.")
# A control the driver swallows must not stall the steps that follow it.
#
# No step declares "optional" now -- it was the Guide button's, and that step is
# gone. The mechanism is still asserted so it cannot be deleted as dead code:
# removing it would make the next such step silently wait the full window.
Assert-True (
    $source -match 'step\.Has\("optional"\)') (
    "Optional steps must use a shorter capture window so they cannot block later steps.")
# "Nothing registers" has two causes that look identical without a report count.
Assert-True (
    $source -match 'LearnStepReports' -and
    $source -match '" report"') (
    "The wizard must show how many reports each step has seen.")

# Identity lookups run from the WM_INPUT handler on every report, so a device that
# can never be identified must not repeat the full fallback chain -- five syscalls
# plus a byte-at-a-time descriptor hash -- at over 100 Hz.
Assert-True (
    $source -match '(?s)RawInputDeviceKey\([^)]*\)\s*\{.*?failedUntil' -and
    $source -match 'A_TickCount < failedUntil\[hDevice\]') (
    "Failed controller identity lookups must back off instead of retrying on every report.")

# Learned RawInput profiles must remain additive, bounded, and capable of
# representing the report shapes the wizard claims to support.
Assert-True (
    $source -match '(?s)RawInputDecodeReport\([^)]*\).*?deviceKey := RawInputDeviceKey\(device\).*?LoadControllerProfile\(deviceKey\)' -and
    $source -match 'LoadControllerProfile\(ControllerProfileLengthKey\(length\)\)' -and
    $source -match 'ControllerProfilePath\(\)' -and
    $source -match 'ShowControllerLearner\(') (
    "The learned-controller profile path or wizard integration is incomplete.")
Assert-True (
    $source -match '(?s)LoadControllerProfile\([^)]*\).*?offset \+ width > length' -and
    $source -match 'validAxisSizes := Map\("u8".*"u16le".*"u16be"') (
    "Learned profile fields must be bounds-checked and support 8-bit, little-endian, and big-endian axes.")
Assert-True (
    $source -match '(?s)RawInputProfileDecode\([^)]*\).*?\(value & button\["mask"\]\) = button\["pressed"\]' -and
    $source -match '(?s)RawInputProfileDecode\([^)]*\).*?hat\["offset"\].*?hat\["mask"\]' -and
    $source -match 'ControllerLearnDpadButtons\(') (
    "Learned buttons and D-pad bits must preserve active-high or active-low pressed state.")
Assert-True (
    $source -match 'LearnAxisSamples' -and
    $source -match 'ControllerLearnHighByteQuality\(' -and
    $source -match 'LearnAxisStarted' -and
    $source -match 'ControllerLearnReportAxisActive\(' -and
    $source -match 'ControllerLearnCompleteAxis\(' -and
    $source -match 'pathAtPeak' -and
    $source -match 'then RELEASE' -and
    $source -match '"extent", Max\(1, chosen\["extent"\]\)') (
    "Axis learning must use an outward-and-release gesture, resolve the peak path, and save measured travel.")
Assert-True (
    $source -match 'LearnIdentifyDevices' -and
    $source -match 'LearnIdentifyReady' -and
    $source -match 'ControllerLearnIdentificationReady\(' -and
    $source -match '"noise", Buffer\(length, 0\)') (
    "Controller selection must measure per-device idle noise before accepting an identifying press.")
Assert-True (
    $source -match 'RawInputDeviceKey\(hDevice, refresh := false\)' -and
    $source -match 'RIDI_DEVICEINFO' -and
    $source -match 'RIDI_PREPARSEDDATA' -and
    $source -match 'HID_DESC_' -and
    $source -match '(?s)if \(key != ""\) \{\s*cache\[hDevice\] := key' -and
    $source -match 'RawInputDeviceKey\(LearnDevice, true\)' -and
    $source -match 'base\[1\] != key' -and
    $source -match '"key", section') (
    "Profile saving must retry identity lookup, fall back through HID VID/PID and descriptor identity, and reload a base profile from a later specific device path.")
Assert-True ($source -notmatch 'LearnCandidate') (
    "Digital learning must not require duplicate held reports; change-only controllers send one press report.")
Assert-True (
    $source -match 'LearnBaseline := ControllerLearnCopyReport\(data, base, length\)' -and
    $source -notmatch 'LearnBaseline := ControllerLearnCopyReport\(baseline, 0, length\)') (
    "A change-only controller must start rest sampling from the identifying release report, not its first-seen pressed report.")
# Visible confirmation after every detection, in words -- and the byte, mask and
# neutral value still written to the log.
#
# This used to require the byte/bit ON SCREEN, which is how the window came to
# say 'A = byte 8 bit 0x01 active-high' to somebody mapping a gamepad. Both
# halves are now asserted separately, because dropping either is a real loss:
# without the on-screen line the user cannot tell a detection from a hang, and
# without the logged detail today's gyro and trigger faults could not have been
# diagnosed.
Assert-True (
    # Patterns stay ASCII on purpose: the strings they match contain an em dash,
    # and a non-ASCII literal in a validator is the encoding trap this project
    # has already been bitten by once.
    $source -match 'LearnDetailCtrl\.Text := "Got it' -and
    $source -match 'LearnLastFriendly \. "\."|Got it[^"]*" LearnLastFriendly' -and
    $source -match 'Last one:[^"]*" LearnLastFriendly' -and
    $source -match 'ControllerLearnFriendlyName\(name\)') (
    "The learner must confirm each detection on screen in plain language.")
Assert-True (
    $source -match '(?s)ControllerLearnAccept\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?LogLine\("Learn: " detail' -and
    $source -match 'name " = byte " offset " bit 0x"') (
    "The learner must still log the byte and mask it accepted; the plain-language " +
    "text on screen replaces that detail in the window, not in the log.")
Assert-True (
    $source -notmatch 'LearnMoved|LearnAxis8|LearnAxis16|LearnLastReport|LearnRestSet') (
    "Interrupted controller-learner state from the earlier axis draft is still referenced.")
Assert-True ($source -notmatch 'Learn Controller teaches an unrecognised pad') (
    "The Controller page helper text overlaps the fixed Settings footer at display scaling.")

# A window must never be shown before its final position and shape are settled.
# Showing first and correcting afterwards is visible as the Quick Menu snapping
# into place, and as square corners for a frame.
$positionMatch = [regex]::Match(
    $source, '(?ms)^PositionGuiCentered\([^)]*\)\s*\{.*?^}')
Assert-True (
    $positionMatch.Success -and
    $positionMatch.Value -match 'Show\("Hide w" width " h" height\)' -and
    $positionMatch.Value -notmatch 'Show\(\(noActivate') (
    "A first show must stay hidden through the whole centering calculation.")
# The Quick Menu is revealed BEFORE it is measured and shaped. This inverts what
# this rule used to demand, and the old order is why the menu appeared clipped on
# a 4K display: WinSetRegion clips rather than masks, and a hidden window does not
# reliably report its size, so shaping first shaped it against a wrong measurement.
# Reveal and shape happen in one message-pump turn, so nothing is visible between.
Assert-True (
    $source -match '(?s)if deferred\s*\r?\n\s*RevealWindow\(QuickMenuGui\)\s*\r?\n\s*QuickMenuEnsureContentFits\(\)\s*\r?\n\s*ApplyRoundedCorners\(QuickMenuGui, 30\)') (
    "The Quick Menu must be revealed before it is measured and shaped; shaping a hidden window clips it.")
# The same rule stated as an invariant of the shaping helper itself, so it holds
# for every caller and not only the Quick Menu.
Assert-True (
    # Bounded to the body instead of anchored on the closing brace. The old
    # form ended '.*?^}', which a body bound cannot be combined with: the
    # bound stops just before the newline that precedes the brace, where '^'
    # can no longer match. Confining the gap says the same thing more directly.
    $source -match
        '(?ms)^ApplyRoundedCorners\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?IsWindowVisible') (
    "ApplyRoundedCorners must refuse to shape a window that is not visible.")

# The Settings category table must stay the single source of truth. LT/RT
# wrapping was hard-coded to 4 while the table held 6, so the controller could
# not reach the last two categories at all.
Assert-True (
    $source -match 'SettingsCategoryTable\(\)' -and
    $source -match '(?s)SettingsChangeCategory\(direction\)\s*\{.*?SettingsCategoryCount\(\)' -and
    $source -notmatch '(?s)SettingsChangeCategory\(direction\)\s*\{.*?nextCategory\s*:=\s*4') (
    "Settings category navigation must derive its wrap point from the category table.")

# Quick Menu toggles must persist. Writing only the live global would make a
# setting appear to work and then silently revert on the next start.
Assert-True (
    $source -match '(?s)ProductApplyQuickMenuSetting\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?SharedPersistSettings\((?:(?!\n\})[\s\S])*?SetFieldValue\(section "\." key' -and
    # AutoHotkey v2 reads the STRING "false" as a non-empty string, so it is
    # TRUE. Handing the persisted word straight to a checkbox would tick every
    # box it had just cleared, and the Quick Menu would look right while the
    # Settings window behind it disagreed.
    $source -match '(?s)SetFieldValue\(section "\." key,\s*\r?\n?\s*value = "true" \? true : \(value = "false" \? false : value\)\)') (
    "Quick Menu toggles must persist transactionally and sync the full Settings control.")

# ...and the file that was just written is what the live globals are re-read
# from. The toggle used to write the INI and then hand-assign each global in a
# second `switch` over the same row ids, so every new row cost two edits in two
# places -- and the failure when the second was forgotten was silent: the row
# toggled, persisted, logged "-> ON" and changed nothing until the next start.
# LoadSettings() re-reads every global from disk, which is what Reload and
# Save & Apply already do, so the id list exists exactly once.
Assert-True (
    $source -match '(?s)ProductApplyQuickMenuSetting\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?LoadSettings\(\)' -and
    $source -match '(?s)QuickMenuTogglePersistentMouse\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?LoadSettings\(\)' -and
    $source -notmatch '(?s)QuickMenuToggleSetting\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?case\s+"gameFocus":') (
    "Quick Menu toggles must re-read their live values from the INI they just " +
    "wrote, not hand-assign each global a second time.")

# Every toggle row's action must be its own id.
#
# The Mouse Mode row on MAIN carried the action "toggle:mouseMode" while the
# handler answered to "qPersistentMouse". Nothing failed: the lookup returned
# nothing, the toggle returned early, and the row rendered and selected and did
# nothing at all. QUICKMENU_ROWS.txt could not see it because it records row IDS
# and dispatch happens on row ACTIONS -- so the id is what the action must be
# built from, and any literal toggle action naming something that is neither a
# table id nor qPersistentMouse is the bug coming back.
$toggleActions = [regex]::Matches($source, 'MenuRow\([^)]*?"(toggle:[A-Za-z]+)"') |
    ForEach-Object { $_.Groups[1].Value.Substring(7) } | Sort-Object -Unique
foreach ($toggleAction in $toggleActions) {
    Assert-True (
        $toggleAction -eq 'qPersistentMouse' -or
        $source -match ('"' + [regex]::Escape($toggleAction) + '", Map\("section"')) (
        "Quick Menu toggle action '$toggleAction' reaches no handler: it is " +
        "neither qPersistentMouse nor a QuickMenuToggleTable id.")
}
Assert-True (
    $source -match '(?s)QuickMenuToggleSetting\([^)]*\)\s*\{.*?ApplyRuntimeTimers\(\)') (
    "Toggling an assist feature must re-apply the timers so it starts or stops.")

# The View tap and hold actions are independently switchable, and a disabled
# hold must not fall through to the tap action.
Assert-True (
    $source -match 'EnableViewTapAction' -and
    $source -match 'EnableViewHoldAction' -and
    $source -match '(?s)if\s*\(heldMs\s*>=\s*threshold\)\s*\{\s*if\s*!EnableViewHoldAction\s*\r?\n\s*return') (
    "A disabled View hold action must return rather than fall through to the tap action.")

# The screen probe only reads. It exists to identify a window, never to act on
# one, so it must not activate or close anything.
$probeMatch = [regex]::Match(
    $source, '(?ms)^RunScreenProbe\(\)\s*\{.*?^}')
Assert-True (
    $probeMatch.Success -and
    $probeMatch.Value -notmatch 'WinActivate\(' -and
    $probeMatch.Value -notmatch 'WinClose\(' -and
    $probeMatch.Value -notmatch 'ProcessClose\(') (
    "The screen probe must only read and log; it may not activate or close windows.")

# Shell-overlay suspension must stay bounded, or a single listed background
# window would disable assistance permanently.
$overlayMatch = [regex]::Match(
    $source, '(?ms)^AssistShellOverlayVisible\([^)]*\)\s*\{.*?^}')
Assert-True (
    $overlayMatch.Success -and
    $overlayMatch.Value -match 'WS_EX_TOPMOST' -and
    $overlayMatch.Value -match 'MonitorGet\(') (
    "Shell-overlay detection must require a topmost/foreground window covering its monitor.")
# The Xbox FSE switcher is a tool window, and the assist inventory drops tool
# windows on purpose -- so it is never in the inventory. Detection must inspect
# the foreground window directly, or it silently matches nothing.
Assert-True (
    $overlayMatch.Success -and
    $overlayMatch.Value -match 'WinExist\("A"\)') (
    "Shell-overlay detection must inspect the foreground window directly; the FSE switcher is a tool window and never appears in the assist inventory.")
Assert-True (
    $source -match 'class:XamlExplorerHostIslandWindow') (
    "The measured Xbox FSE switcher window class must stay in the default overlay list.")
# The probe exists to find windows the inventory filters out, so it must see
# every top-level window rather than the assist inventory's filtered view.
#
# It used to have its own WinGetList() and this asserted that. There is one
# enumeration now, so what has to be true instead is that the probe asks for the
# UNFILTERED form of it -- SharedWindowInventoryBuild(true), the includeHidden
# argument. Asserting the call without the argument would pass on exactly the
# regression this exists to catch: a probe over the filtered list reports
# "1 window, Steam" while the Xbox FSE switcher, a cloaked tool window, fills
# the screen.
$probeMatch = [regex]::Match($source, '(?ms)^RunScreenProbe\(\)\s*\{.*?^}')
Assert-True (
    $probeMatch.Success -and
    $probeMatch.Value -match 'SharedWindowInventoryBuild\(true\)') (
    "The screen probe must enumerate all top-level windows, not just the assist inventory.")

# The logon task must be registered from XML with the power conditions set
# explicitly. `schtasks /create /sc onlogon` inherits Task Scheduler's defaults,
# which include DisallowStartIfOnBatteries -- so the task registers cleanly,
# looks healthy, and never starts on a handheld running on battery.
Assert-True (
    $source -match 'LogonTaskXml\(\)' -and
    $source -match '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>' -and
    $source -match '<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>' -and
    $source -match '/create /f /tn "[^"]*" /xml') (
    "The logon task must be registered from XML that disables the AC-power condition.")
# The companion must take the task name and XML from SteamShell-Common.ahk --
# Setup Assistant registers the same task, and the two used to disagree on the
# name, the logon delay and AllowHardTerminate.
Assert-True (
    $rawSource -notmatch '<LogonTrigger>' -and
    $rawSource -match 'XfeLogonTaskXml\(' -and
    $rawSource -match '(?sm)^LogonTaskName\(\)\s*\{(?:(?!\n\})[\s\S])*?XfeLogonTaskName\(\)' -and
    $rawSource -match 'XfeLogonTaskLegacyName\(\)' -and
    $rawSource -notmatch '(?m)^XmlEscape\(') (
    "The companion must register the shared logon task, not its own.")

Assert-True ($source -notmatch '/create /f /sc onlogon') (
    "The logon task must not be created with schtasks defaults; they refuse to start on battery.")
# Anchored to the XML element, not to the bare word.
#
# This assertion used to read `$source -notmatch 'HighestAvailable'`, and the
# first comment in the tree that explained WHY XFE does not get a
# HighestAvailable task failed the build. That is the documented weakness of an
# unanchored -notmatch: a bare word matches your own prose. The rule being
# protected is about the task XML, so the pattern is now about the task XML.
#
# NARROWED DELIBERATELY. The rule is about the LOGON task -- the companion must
# never start elevated at sign-in, which is the whole point of choosing it.
#
# The opt-in RTSS helper task is a different thing and IS HighestAvailable by
# necessity: it exists to start an already-elevated helper without a UAC prompt,
# because a consent dialog runs on the secure desktop where a controller cannot
# answer it. It is registered lazily, only once the opt-in is used, and only
# when the helper sits below a Program Files path the user cannot write.
#
# So the assertion now reads the logon XML specifically rather than the whole
# file, and separately pins that the helper task is the ONLY HighestAvailable
# thing here.
Assert-True (
    $commonSource -match
        '(?sm)^XfeLogonTaskXml\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '<RunLevel>LeastPrivilege</RunLevel>' -and
    $commonSource -notmatch
        '(?sm)^XfeLogonTaskXml\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '<RunLevel>HighestAvailable</RunLevel>' -and
    # $rawSource, not $source: the resolved source now contains
    # SteamShell-Common.ahk, where the opt-in helper task's HighestAvailable XML
    # legitimately lives. The rule is that the COMPANION does not write one.
    $rawSource -notmatch '<RunLevel>HighestAvailable</RunLevel>' -and
    $rawSource -match
        '(?sm)^EnsureXfeElevatedHelperTask\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ElevatedHelperLocationIsProtected\(') (
    "The logon task must stay at least privilege; only the opt-in helper task may elevate.")

# Every window here is +AlwaysOnTop, because that is the only thing that puts a
# window over Xbox FSE. A non-topmost dialog cannot rise above a topmost window
# even when that window is its own owner, so a plain MsgBox or FileSelect opens
# BEHIND the Settings window -- focused, holding the keyboard, and invisible.
#
# Written against the shape, not the sites: any new bare MsgBox or FileSelect
# reintroduces the bug, so none are allowed outside the two wrappers.
$bareMsgBox = [regex]::Matches($source, '(?<![\w])MsgBox\(')
Assert-True ($bareMsgBox.Count -eq 1) (
    "MsgBox must be called through TopmostMsgBox; a plain message box opens behind its always-on-top owner. Found $($bareMsgBox.Count) bare calls, expected only the one inside the wrapper.")
$bareFileSelect = [regex]::Matches($source, '(?<![\w])FileSelect\(')
Assert-True ($bareFileSelect.Count -eq 1) (
    "FileSelect must be called through TopmostFileSelect. Found $($bareFileSelect.Count) bare calls, expected only the one inside the wrapper.")
Assert-True (
    $source -match 'return MsgBox\(text, title, Trim\(options " 4096"\)\)') (
    "TopmostMsgBox must add MB_SYSTEMMODAL (4096); that is what makes the message box topmost.")
$promoteMatch = [regex]::Match(
    $source, '(?ms)^PromoteDialogsToTopmost\(\)\s*\{.*?^}')
Assert-True (
    $promoteMatch.Success -and
    $promoteMatch.Value -match 'ahk_class #32770 ahk_pid " ScriptPid' -and
    $promoteMatch.Value -match 'WinSetAlwaysOnTop\(1') (
    "Dialog promotion must target this process's own common dialogs and set them topmost.")
# Dropping the owner's topmost bit is the wrong fix: inside FSE that hides the
# owner behind FSE, taking the dialog with it.
Assert-True (
    $source -notmatch 'WinSetAlwaysOnTop\(0, "ahk_id " SettingsGui') (
    "The Settings window must not drop its topmost bit to show a dialog; inside FSE that hides both.")

# The axis resolver runs on EVERY report of a gesture, not once at the end, and
# each run writes its provisional answer into LearnResultAxes. The stick-claiming
# loop must therefore skip the step's own entry, or the field becomes unavailable
# to itself and every stick fails with "not enough travel" however far it moves.
# Measured on hardware 2026-07-26.
$resolveMatch = [regex]::Match(
    $source, '(?ms)^ControllerLearnResolveAxis\([^)]*\)\s*\{.*?^}')
Assert-True (
    $resolveMatch.Success -and
    $resolveMatch.Value -match 'name\s*=\s*step\["name"\]') (
    "The stick-claiming loop must exclude the current step's own provisional axis.")
# A rejected axis must leave nothing behind: a provisional entry measured from a
# partial sweep has the wrong neutral and extent, which is what sends the pointer
# across the screen.
Assert-True (
    $source -match '(?ms)^ControllerLearnRejectAxis\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?LearnResultAxes\.Delete\(') (
    "A rejected axis must delete its provisional entry so it cannot reach the profile.")
Assert-True (
    $resolveMatch.Success -and
    $resolveMatch.Value -notmatch '(?m)^\s*return false\s*$') (
    "Axis resolve failures must go through ControllerLearnRejectAxis so the reason is recorded and the provisional entry is cleared.")
Assert-True (
    $source -match '(?ms)^ControllerLearnSkip\(\)\s*\{(?:(?!\n\})[\s\S])*?LearnResultAxes\.Delete\(') (
    "Skipping an axis step must discard its provisional answer.")

# Startup window mode. On the de-elevated route explorer.exe starts the program
# and chooses the show state itself, so Run's argument never reaches the child --
# the post-launch sweep is the only thing that enforces Hidden or Minimized
# there, and it must match by process name because Run returns explorer's PID.
#
# The sweep body is shared with the shell now, so both rules are checked against
# the wrapper AND the shared body ($startupWindowModeBodies, built above). The
# rules themselves are unchanged -- match by NAME, and stop after a bounded
# window -- only the parameter names and how the bound is expressed have moved.
Assert-True (
    $startupWindowModeMatch.Success -and
    $startupWindowModeMatch.Value -match 'WinGetList\("ahk_exe " (?:exeName|fileName)\)') (
    "The startup window-mode sweep must match by process name; the de-elevated route returns explorer's PID.")
Assert-True (
    $startupWindowModeMatch.Success -and
    $startupWindowModeMatch.Value -match 'A_TickCount > deadlineTick' -and
    $startupWindowModeMatch.Value -match 'startedTick \+ 6000') (
    "The startup window-mode sweep must stop after a bounded window, or it re-hides a program the user deliberately opened.")
Assert-True ($sample -match '(?m)^WindowMode=Hidden$') (
    "The sample startup window mode must default to Hidden.")

# Cursor parking. The right edge is the default because a cursor that briefly
# reappears is least visible there on a TV.
# MouseParkEdge since schema 13, which is standalone's name for the same
# setting; the global carries that name too, which the ParkCursor assertion
# below pins.
Assert-True ($sample -match '(?m)^MouseParkEdge=right(?:\s*;.*)?$') (
    "The sample cursor park edge must default to the right.")
Assert-True ($sample -match '(?m)^ParkOnGameStart=true$') (
    "Game-entry cursor parking must be enabled by default.")
# The park edge is a STRING, and that is the assertion -- not the spelling of the
# comparison.
#
# This rule used to match only the text `ParkEdge = "left"` inside ParkCursor. It
# passed for as long as the setting was stored as `StrLower(...) = "left"`, which
# assigns the RESULT of that comparison: the variable held 1 or 0, every later
# test against "left" compared a number to a word, and the cursor parked on the
# right edge whatever the user chose. A rule that matches a spelling cannot see a
# type, so both halves are pinned now.
Assert-True (
    $source -match '(?ms)^ParkCursor\(\*\)\s*\{(?:(?!\n\})[\s\S])*?MouseParkEdge = "left"' -and
    $source -match '(?s)MouseParkEdge\s*:=\s*StrLower\(' -and
    $source -match 'MouseParkEdge != "left" && MouseParkEdge != "right"' -and
    $source -notmatch 'MouseParkEdge\s*:=[^\r\n]*\)\s*=\s*"left"') (
    "ParkCursor must honour the configured park edge, and the edge must be stored " +
    "as the word rather than as the result of comparing it to one.")
Assert-True (
    $source -match '(?s)ForegroundWindowLooksGameLike\(.*?AssistWindowLooksLikeGame\(' -and
    $source -match '(?s)ObserveForeground\(\).*?ParkOnGameStart.*?ParkCursorIfStillForeground\.Bind\(hwnd') (
    "Foreground game/fullscreen transitions must park safely against the window that triggered them.")

$schemaVersion = [regex]::Match(
    $source, '(?m)^global SettingsSchemaVersion\s*:=\s*(\d+)$')
Assert-True $schemaVersion.Success "Runtime settings schema version is missing."
Assert-True (
    $sample -match "(?m)^SettingsSchemaVersion=$($schemaVersion.Groups[1].Value)(?:\s*;.*)?$") (
    "Sample and runtime settings schema versions do not match.")
Assert-True (
    $sample -match '(?m)^EnablePersistentMouseMode=false(?:\s*;.*)?$' -and
    $source -match '"EnablePersistentMouseMode",\s*"false"') (
    "Persistent Mouse Mode is missing from the runtime or sample settings schema.")

# The log lives beside the EXE and nothing else truncates it, so rotation is the
# only thing standing between a long session and an unbounded file. LogLine must
# route through it rather than appending directly.
Assert-True (
    $source -match
        '(?s)RotateLogIfNeeded\(\s*pendingBytes[^)]*\)\s*\{.*?static estimatedSize.*?' +
        'FileGetSize.*?FileMove\(LogPath' -and
    $source -match
        '(?s)LogLine\([^)]*\)\s*\{[^}]*?LogRawLine\(' -and
    $source -match
        '(?s)LogRawLine\([^)]*\)\s*\{.*?RotateLogIfNeeded\(StrLen\(line\).*?FileAppend') (
    "Log rotation is missing, or LogLine reaches the file without consulting it.")

# Per-edge controller logging is a diagnostic, not a lifecycle record. Ungated
# it emits a line per button press and was the largest writer to the log.
Assert-True (
    $source -match
        '(?s)if\s*\(EnableControllerDiagnostics\s*\r?\n\s*&&\s*\(pressed\s*\|\|\s*released') (
    "Per-edge controller logging is no longer behind the diagnostic flag.")
# The accent is one design applied to both trees. The selected-row fill must
# stay DERIVED from it: storing the fill separately is what would let a green
# accent sit on a blue-grey fill, the exact mismatch the derivation prevents.
Assert-True (
    $source -match
        '(?s)QM_ROW_SELECTED\s*:=\s*BlendHexColor\(QM_BG,\s*hex,\s*QM_ACCENT_BLEND\)') (
    "The Quick Menu selected-row fill is no longer derived from the accent color.")

# Drivers may expose more than 512 low-resolution/refresh combinations before
# reaching their 1440p and 4K modes. EnumDisplaySettings itself defines the end.
Assert-True (
    $source -match
        # The intent is the boundary, not the brace style: the loop must stop
        # when Windows says the list has ended, never at a fixed ceiling. The
        # unified body in SteamShell-Common.ahk kept the shell's 'if (!ok)'.
        '(?s)GetPrimaryDisplayModes\(\)\s*\{.*?Loop\s*\{.*?' +
        'EnumDisplaySettingsW.*?if\s*\(?!ok\)?\s*\r?\n\s*break' -and
    $source -notmatch
        '(?s)GetPrimaryDisplayModes\(\)\s*\{.*?Loop\s+512') (
    "Display mode enumeration must continue until Windows reports the true end of the driver list.")

# A malformed custom hex or an unknown preset must fall back to a readable
# default rather than reaching the painter.
Assert-True (
    $source -match '(?s)NormalizeHexColor\(value\)\s*\{.*?return ""' -and
    $source -match
        '(?s)QuickMenuApplyAccent\(.*?if\s*\(hex\s*=\s*""\)\s*\{.*?QuickMenuAccentPresetHex\("Purple"\)') (
    "An invalid Quick Menu accent color no longer falls back to the default.")

# Persisting is the transaction boundary: the palette must not repaint in a
# color the portable INI could not record.
#
# The boundary moved rather than disappeared. Cycling the accent is a shared
# qAccentColor settings row now, so the write goes through
# ProductApplyQuickMenuSetting, which returns early when SharedPersistSettings
# reports failure and only then calls LoadSettings() -- and LoadSettings is
# where QuickMenuApplyAccent is reached. Both halves are pinned, because the
# repaint being a consequence of the reload is exactly what makes the ordering
# hold without a second explicit call.
Assert-True (
    $source -match
        '(?s)ProductApplyQuickMenuSetting\([^)]*\)\s*\{\s*\r?\n\s*if !SharedPersistSettings\((?:(?!\n\})[\s\S])*?return false\s*\r?\n\s*\}\s*\r?\n\s*LoadSettings\(\)' -and
    $source -match
        '(?sm)^LoadSettings\(\)\s*\{(?:(?!\n\})[\s\S])*?QuickMenuApplyAccent\(') (
    "The Quick Menu accent repaints before confirming it was persisted.")

Assert-True ($sample -match '(?m)^AccentColor=Purple') (
    "The sample settings file is missing the Quick Menu accent default.")

Assert-True ($sample -match '(?m)^ControllerDeadzone=3000(?:\s*;.*)?$') (
    "The sample controller deadzone default must remain 3000.")

# The Frame Limit selection is restored by shared code, but the wiring that feeds
# it is per-tree and has to be asserted here too. XFE lost the selection across a
# reboot for the same reason standalone did: RTSS keeps the FPS number in its
# global profile, but the limiter flag is runtime state in its shared memory and
# "Custom" is a concept RTSS never sees.
Assert-True (
    $source -match 'RtssRestoreFrameLimitOnStartup\s*:=\s*ReadBool\(\s*"RTSS",\s*"RestoreFrameLimitOnStartup"' -and
    $source -match 'RtssLastFrameCapFps\s*:=\s*ReadInt\("RTSS",\s*"LastFrameCapFps"' -and
    $source -match '"RestoreFrameLimitOnStartup",\s*"true"' -and
    $sample -match '(?m)^RestoreFrameLimitOnStartup=true$' -and
    $sample -match '(?m)^LastFrameCapMode=(?:\s*;.*)?$' -and
    $sample -match '(?m)^LastFrameCapFps=0(?:\s*;.*)?$') (
    "The XFE Frame Limit restore settings are missing or not read.")

Assert-True (
    $source -match
        '(?s)CycleRtssFrameCap\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'PersistRtssFrameCapSelection\(\s*\r?\n?\s*RtssFrameCapModeForFps' -and
    $source -match 'PersistRtssFrameCapSelection\("off",\s*state\["fps"\]\)' -and
    $source -match 'PersistRtssFrameCapSelection\("custom",\s*customFps\)' -and
    $source -match 'PersistRtssFrameCapSelection\("configured",\s*RtssPresetFrameCap\)' -and
    $source -match 'PersistRtssFrameCapSelection\("preset",\s*target\)' -and
    $source -match
        '(?s)PersistRtssCustomFrameCap\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'PersistRtssFrameCapSelection\("custom",\s*value\)' -and
    $source -match
        '(?s)ToggleRtssFrameLimiter\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'PersistRtssFrameCapStateNow' -and
    $source -match
        '(?s)SetRtssFrameLimiterState\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'PersistRtssFrameCapStateNow' -and
    $source -match
        '(?s)CycleRtssFrameCap\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if\s*!SetRtssGlobalFrameLimit\(target\).*?return.*?' +
        '!ApplyRtssGlobalState\("limiter",\s*true\).*?return.*?' +
        'PersistRtssFrameCapSelection\("preset",\s*target\)' -and
    $source -match
        '(?s)CycleRtssFrameCap\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '!ApplyRtssGlobalState\("limiter",\s*false\).*?return.*?' +
        'PersistRtssFrameCapSelection\("off",\s*state\["fps"\]\)' -and
    $source -match 'SetTimer\(RestoreRtssFrameLimitTick,\s*2000\)' -and
    $source -match '"section", "RTSS", "key", "RestoreFrameLimitOnStartup"') (
    "An XFE Frame Limit path no longer records what it applied, or the restore is not armed.")

# ==============================================================================
# OPT-IN ELEVATED RTSS HELPER
# ==============================================================================
# XFE_PARITY_NOTES.md recorded for a long time that XFE would never have an
# elevated helper. That reversed, for one reason and one reason only:
# RTSSHooks64.dll is loaded into the CALLING process, so on a stock Program
# Files RTSS install an unelevated companion cannot set the FPS value or save a
# per-game profile at all. Elevated INPUT was NOT ported and must not be -- see
# the assertion below that pins the --product argument.
#
# Every assertion in this section was mutation-tested by breaking the behaviour
# it names and confirming the build fails.

# Default OFF, in all three places that decide the default: the embedded
# defaults, the reader, and the shipped sample. A user chooses XFE because
# nothing about it is elevated; the opt-in is the feature.
Assert-True (
    $source -match '"EnableElevatedFrameCapWrites",\s*"false"' -and
    $source -match
        'RtssElevatedFrameCapWrites\s*:=\s*ReadBool\(\s*\r?\n?\s*' +
        '"RTSS",\s*"EnableElevatedFrameCapWrites",\s*false\)' -and
    $sample -match '(?m)^EnableElevatedFrameCapWrites=false$') (
    "The elevated RTSS helper is no longer opt-in and off by default.")

# Nothing is elevated until it has been proved administrator-protected.
#
# Matching the expected file version proves only that SOME file carrying that
# version resource sits at the expected path; a version resource is metadata
# anyone can stamp onto anything. If the interactive user can write the binary
# or its directory, elevating it is a local privilege escalation. Both checks
# must appear, and both must appear BEFORE the *RunAs.
Assert-True (
    $source -match
        '(?sm)^StartElevatedRtssHelper\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'FileGetVersion\(ElevatedHelperPath\)(?:(?!\n\})[\s\S])*?' +
        'ElevatedHelperExpectedVersion(?:(?!\n\})[\s\S])*?' +
        'ElevatedHelperLocationIsProtected\((?:(?!\n\})[\s\S])*?' +
        '\*RunAs') (
    "The XFE helper can be elevated without proving it is administrator-protected.")

# --product=xfe is the whole difference between an RTSS helper and a second
# elevated input engine. Without it the same binary polls the controller at High
# integrity, centres elevated windows, and looks for steamshell.exe as its
# parent -- none of which XFE asked for, and the input half would work only for
# XInput controllers, which is precisely the case XFE exists to handle
# differently.
Assert-True (
    $source -match
        '(?sm)^StartElevatedRtssHelper\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'commandLine := "\*RunAs "(?:(?!\n\})[\s\S])*?' +
        '\. " --product=xfe"') (
    "The XFE helper is no longer launched in RTSS-only mode.")

# XFE never deploys, extracts, or hardens the helper. It has no embedded payload
# and no administrator rights; SteamShell.exe Setup owns deployment. Anchored to
# call forms, because a bare word matches these comments.
Assert-True (
    $source -notmatch 'FileInstall\s' -and
    $source -notmatch 'ExtractEmbeddedElevatedHelper\(' -and
    $source -notmatch 'HardenElevatedHelperDirectory\(' -and
    $source -notmatch 'RegisterElevatedHelperTask\(') (
    "XFE must not deploy or harden the elevated helper; Setup does that.")

# Straight to the helper, never a local write first.
#
# This is the rule standalone paid for twice. The helper exists only in an
# unelevated session -- StartElevatedRtssHelper declines under an admin token --
# which is exactly the session where SaveProfile fails silently, so trying
# locally first cannot succeed. For per-game profiles it was actively harmful:
# verifying a named profile re-reads the copy SetProfileProperty just wrote, so
# the check PASSED while nothing had been saved and the helper was never asked.
#
# The ordering is the assertion. A helper branch that sits after the local write
# still matches "both appear", which is why the indexes are compared.
$globalCapBody = [regex]::Match(
    $source,
    '(?sm)^SetRtssGlobalFrameLimit\(fps\)\s*\{(?:(?!\n\})[\s\S])*\n\}')
Assert-True ($globalCapBody.Success) (
    "SetRtssGlobalFrameLimit could not be located for the elevated-write check.")
$globalHelperIndex = $globalCapBody.Value.IndexOf('return ApplyElevatedRtssFrameLimit(fps)')
$globalWriteIndex = $globalCapBody.Value.IndexOf('api["setProfileProperty"]')
Assert-True (
    $globalHelperIndex -ge 0 -and
    $globalWriteIndex -ge 0 -and
    $globalHelperIndex -lt $globalWriteIndex -and
    $globalCapBody.Value -match
        'ProductElevatedHelperAlive\(\)\s*&&\s*ElevatedRtssWritesAvailable\(\)') (
    "The global frame cap no longer goes straight to the elevated helper.")

$profileSaveBody = [regex]::Match(
    $source,
    '(?sm)^SaveRtssFrameLimitToProfile\(\)\s*\{(?:(?!\n\})[\s\S])*\n\}')
Assert-True ($profileSaveBody.Success) (
    "SaveRtssFrameLimitToProfile could not be located for the elevated-write check.")
$profileHelperIndex = $profileSaveBody.Value.IndexOf('ApplyElevatedRtssProfileFrameLimit(exeName, fps)')
$profileWriteIndex = $profileSaveBody.Value.IndexOf('api["setProfileProperty"]')
Assert-True (
    $profileHelperIndex -ge 0 -and
    $profileWriteIndex -ge 0 -and
    $profileHelperIndex -lt $profileWriteIndex) (
    "The per-game profile save no longer goes straight to the elevated helper.")

# A latched RtssFrameCapWriteBlocked must NOT send a per-game save home before
# it reaches the helper. The two conditions behind RtssFrameCapWritable have
# different causes: a build without the profile exports is a dead end, while a
# failed in-process write is a privilege problem and is precisely what the
# helper is for.
Assert-True (
    $profileSaveBody.Value -match
        'blockedReason\s*!=\s*""\s*&&\s*!RtssFrameCapWriteBlocked') (
    "A latched write-blocked flag now refuses per-game saves before the helper is asked.")

# The per-game save must prove itself. It reported success unconditionally, and
# unelevated it was reporting it for a write that never happened: SaveProfile
# fails silently against a Program Files install, so every standard user got a
# "saved" status line for a profile RTSS never received.
$profileReadBackIndex = $profileSaveBody.Value.IndexOf('saved := GetRtssFrameLimit(exeName)')
$profileSuccessIndex = $profileSaveBody.Value.IndexOf(
    'LogLine("RTSS profile " exeName " saved with FramerateLimit "')
Assert-True (
    $profileReadBackIndex -ge 0 -and
    $profileSuccessIndex -ge 0 -and
    $profileReadBackIndex -lt $profileSuccessIndex) (
    "The per-game profile save reports success without reading the profile back.")

# The global cap must not log a cap it has not proved either. The line used to
# sit above the read-back, so every change recorded success twice, once falsely.
$globalReadBackIndex = $globalCapBody.Value.IndexOf('readBack := RtssGlobalFrameLimit()')
$globalSuccessIndex = $globalCapBody.Value.IndexOf(
    'LogLine("RTSS global FramerateLimit set to "')
Assert-True (
    $globalReadBackIndex -ge 0 -and
    $globalSuccessIndex -ge 0 -and
    $globalReadBackIndex -lt $globalSuccessIndex) (
    "The global frame cap logs success before the read-back proves it.")

# Turning the setting off has to take effect now, not at the next sign-in. An
# elevated process the user has just asked to stop, which keeps running while
# Health Check reports it as fine, is not a control. Both Settings paths must
# reach it: Save & Apply is the one this setting is actually toggled from.
Assert-True (
    $source -match
        '(?sm)^SyncElevatedRtssHelperWithSettings\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if\s*!RtssElevatedFrameCapWrites(?:(?!\n\})[\s\S])*?' +
        'StopElevatedHelper\(' -and
    $source -match
        '(?sm)^ReloadSettings\(\*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SyncElevatedRtssHelperWithSettings\(\)' -and
    $source -match
        '(?sm)^SaveSettings\(\*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SyncElevatedRtssHelperWithSettings\(\)') (
    "The elevated helper no longer starts and stops with the setting.")

# Health Check has to be able to say why the frame cap is still read-only after
# opting in, which is a different answer from "you did not opt in".
#
# Pinned as two SEPARATE rows rather than by their prose, which changed when the
# checks became Map rows for the shared harness. The claim is the structure --
# a disabled helper and an enabled-but-not-running helper are distinct rows with
# distinct statuses -- not the sentences describing them.
Assert-True (
    $source -match
        '(?sm)^ProductHealthResults\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if !RtssElevatedFrameCapWrites \{(?:(?!\n\})[\s\S])*?' +
        'HealthResult\(results, "INFO", "Elevated RTSS helper"' -and
    $source -match
        '(?sm)^ProductHealthResults\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'HealthResult\(results, "WARN", "Elevated RTSS helper"' -and
    $source -match
        '(?sm)^ProductHealthResults\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"Elevated helper protection"') (
    "Health Check no longer reports the elevated RTSS helper state as separate " +
    "rows for 'not enabled' and 'enabled but unavailable'.")

# The installation record is READ, and reading it is the whole point.
#
# InstallationMode, InstallDirectory and DataDirectory were written by Setup,
# documented in the sample INI as though they meant something, and consumed by
# nothing -- a record that could never contradict the installation it described.
#
# It is advisory and must stay that way. This runs on a Windows shell
# replacement, and a stale path in a settings file must never be able to leave a
# machine with nothing to log in to, so the drift check logs and returns and no
# caller branches on it.
Assert-True (
    $source -match
        '(?sm)^SteamShellSetupRecord\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"InstallationMode"(?:(?!\n\})[\s\S])*?' +
        '"InstallDirectory"(?:(?!\n\})[\s\S])*?"DataDirectory"' -and
    $source -match
        '(?sm)^SteamShellSetupRecordDrift\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if \(Trim\(record\["state"\]\) = ""\)(?:(?!\n\})[\s\S])*?return drift' -and
    $rawSource -match 'LogSteamShellSetupRecordDrift\(') (
    "The installation record is not read at startup, or a fresh install with no " +
    "record can report itself as drifted.")

# The tray icon survives an Explorer restart.
#
# Explorer rebuilds the notification area and broadcasts TaskbarCreated; an icon
# that does not re-add itself is gone until the program restarts. The shell
# handled this because it manages Explorer. The companion did not, and needed it
# just as much -- an Explorer crash took its icon away permanently, and with it
# the only route to Settings, Disable and Exit that does not need a controller.
#
# Both now register through the same shared listener, so neither can lose it
# without the other noticing.
Assert-True (
    $source -match
        '(?sm)^RegisterTaskbarCreatedListener\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"WStr", "TaskbarCreated"(?:(?!\n\})[\s\S])*?OnMessage\(' -and
    $source -match
        '(?sm)^TaskbarCreatedHandler\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SetTimer\(ReassertTrayIcon' -and
    $source -match
        '(?sm)^ReassertTrayIcon\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'A_IconHidden(?:(?!\n\})[\s\S])*?ApplyTrayIconImage\(\)(?:(?!\n\})[\s\S])*?' +
        'BuildProductTrayMenu\(\)' -and
    $source -match
        '(?sm)^InitializeTrayMenu\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RegisterTaskbarCreatedListener\(\)') (
    "The tray icon no longer re-asserts itself after an Explorer restart, which " +
    "loses it permanently until the program is restarted.")

# ...and the verdict reaches the Health Check, with only a mismatch as a warning.
#
# A "new" or "older" record is a fact about the installation, not a fault in it:
# a fresh machine has nothing recorded yet and an older Setup workflow is what an
# upgrade looks like. Marking either as WARN would train the user to ignore the
# row that matters.
#
# "moved" is checked before the version on purpose. A copy carried between
# machines is usually stale in both respects at once, and reporting the version
# first would bury the path mismatch underneath it.
Assert-True (
    $source -match
        '(?sm)^SteamShellInstallationVerdict\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"verdict", "moved"(?:(?!\n\})[\s\S])*?"verdict", "older"' -and
    $source -match
        '(?sm)^AddInstallationRecordHealthRow\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"moved" \? "WARN" : "INFO"' -and
    # \s* because the shell wraps this call after the opening parenthesis.
    $rawSource -match 'AddInstallationRecordHealthRow\(\s*results,') (
    "The installation verdict is missing from Health Check, orders the version " +
    "check before the path check, or warns about a record that is merely new.")

# Every Settings field must be both populated and saved.
#
# Structural, not a list, because the failure it catches is invisible by
# inspection: RTSS.RestoreFrameLimitOnStartup was registered as a field and
# neither populated nor saved, so the checkbox always drew unchecked and
# clearing it did nothing. Nothing in the window looked wrong.
#
# Read from the BUILDER CALL SITES *and* from the shared page table, because a
# field's key can now live in either.
#
# The earlier version matched SettingsRegisterField with a literal category, and
# the row helpers passed the category as a variable -- so it silently covered 37
# of the 61 fields there were at the time. Anchoring on the builders fixed that;
# there are 58 today, counted across both sources;
# then most rows moved into SettingsCategoryRows and the same hole reopened from
# the other side. The floor below is what caught it: the scan found too few
# fields to be trustworthy and said so, rather than passing while checking a
# third of the window.
#
# Table rows are keyed Section.Key, which is exactly how this tree looks a field
# up now -- the row, the populate and the save all say the same string.
$registeredFieldKeys = [regex]::Matches(
    $source,
    'Settings(?:AddCheckboxRow|AddEditRow|AddChoiceRow|AddShortcutRow|AddPathRow)' +
    '\(\s*\r?\n?\s*settings,\s*category,\s*\r?\n?\s*"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value }
$tableRows = [regex]::Matches(
    $source,
    'Map\("product", "(both|xfe)", "type", "(?!note|section)(\w+)",\s*\r?\n\s*' +
    '"section", "([^"]+)", "key", "([^"]+)"')
$registeredFieldKeys += @($tableRows | ForEach-Object {
    $_.Groups[3].Value + "." + $_.Groups[4].Value
})
$registeredFieldKeys = @($registeredFieldKeys | Sort-Object -Unique)
Assert-True ($registeredFieldKeys.Count -gt 55) (
    "The Settings field scan found too few fields to be trustworthy.")
# Populating is a loop over specs now, so "is this field populated?" is "does
# this field have a spec?". SettingsPopulateFields walks SettingsAllFieldSpecs,
# which is the shared page table plus SettingsCompanionFieldSpecs -- so the two
# spec sources together ARE the populate body for this purpose.
#
# The question has not changed and neither has the failure it catches: a field
# the window builds and nothing fills draws its default every time and quietly
# discards what the user set. RTSS.RestoreFrameLimitOnStartup was exactly that.
Assert-True (
    $source -match '(?sm)^SettingsPopulate\(\)\s*\{(?:(?!\n\})[\s\S])*?SettingsPopulateFields\(\)' -and
    $source -match '(?sm)^SettingsPopulateFields\(\)\s*\{(?:(?!\n\})[\s\S])*?SettingsAllFieldSpecs\(\)') (
    "SettingsPopulate must fill the window from the field specs; a hand-written " +
    "read per field is the duplication that let a row and its read disagree.")
$populateBody = ([regex]::Match(
    $source, '(?sm)^SettingsCompanionFieldSpecs\(\)\s*\{[\s\S]*?\n    \]').Value +
    [regex]::Match(
        $source, '(?sm)^SettingsCategoryRows\(category\)\s*\{[\s\S]*?return table').Value)
# Saving is a loop over the same specs, so "is this field saved?" is again "does
# it have a spec?" -- and it is the SAME spec that populates it, which is the
# point: a field cannot now be filled from one place and written from another.
Assert-True (
    $source -match '(?sm)^SaveSettings\(\*\)\s*\{(?:(?!\n\})[\s\S])*?pairs := SettingsFieldPairs\(\)' -and
    $source -match '(?sm)^SettingsFieldPairs\(\)\s*\{(?:(?!\n\})[\s\S])*?SettingsAllFieldSpecs\(\)') (
    "SaveSettings must build its pairs from the field specs; a hand-written " +
    "triple per field is the list that let a key and the field it reads drift.")
# A checkbox's .Value is its state and its .Text is its LABEL; a dropdown is the
# other way round. Reading a control without knowing its type would write labels
# into the INI for every checkbox at once, silently. The TYPE must come from the
# spec, which is why this pins the branch rather than trusting it.
Assert-True (
    $source -match '(?s)SettingsFieldPairs\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'row\["type"\] = "checkbox"(?:(?!\n\})[\s\S])*?GetFieldValue\(key\) \? "true" : "false"' -and
    $source -match '(?s)SettingsFieldPairs\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'row\["type"\] = "choice"(?:(?!\n\})[\s\S])*?GetFieldText\(key, default\)') (
    "SettingsFieldPairs must read a checkbox by value and a choice by text; " +
    "either one read the other way writes the wrong thing for every such row.")
$saveBody = $populateBody
$unpopulated = @(
    $registeredFieldKeys | Where-Object {
        $parts = $_ -split '\.', 2
        -not ($populateBody -match
            ('"section", "' + [regex]::Escape($parts[0]) + '", "key", "' +
             [regex]::Escape($parts[1]) + '"')) })
$unsaved = @(
    $registeredFieldKeys | Where-Object {
        $parts = $_ -split '\.', 2
        -not ($saveBody -match
            ('"section", "' + [regex]::Escape($parts[0]) + '", "key", "' +
             [regex]::Escape($parts[1]) + '"')) })
Assert-True ($unpopulated.Count -eq 0) (
    "Settings fields are registered but never populated: " + ($unpopulated -join ", "))
Assert-True ($unsaved.Count -eq 0) (
    "Settings fields are registered but never saved: " + ($unsaved -join ", "))

# ==============================================================================
# SETTINGS: FLOWING ROWS AND A SCROLLING VIEWPORT
# ==============================================================================
# The pages used to carry a literal y on every control, so adding a row meant
# re-flowing the page by hand -- which is why two pages grew sideways into a
# hand-placed second column instead of downwards. Rows now place themselves from
# a cursor and the content area scrolls, matching standalone.
#
# Every assertion in this section was mutation-tested.

# No literal coordinates in the pages. This is the assertion that keeps the port
# from being undone one control at a time: a single hand-placed control fails it.
#
# Bounded to the page bodies, which start at the "Pages" banner and end at the
# footer, so the frame around them -- title, category list, footer, scrollbar --
# is free to keep the fixed coordinates it must have.
$settingsPageBody = [regex]::Match(
    $source,
    '(?s); -+\r?\n\s*; Pages\r?\n(.*?)\r?\n\s*settings\.AddText\("x24 y616')
Assert-True ($settingsPageBody.Success) (
    "The Settings page section could not be located.")
$literalCoordinates = [regex]::Matches(
    $settingsPageBody.Groups[1].Value, '"x\d+ y\d+')
Assert-True ($literalCoordinates.Count -eq 0) (
    "A Settings row is hand-placed again; rows must flow from the page cursor. " +
    "Found " + $literalCoordinates.Count + " literal coordinate(s).")

# Every page starts its cursor from the one shared constant, so a page cannot
# begin halfway down the viewport or underneath the page description.
$pageCursorStarts = [regex]::Matches(
    $settingsPageBody.Groups[1].Value, 'y := SettingsFirstRowY\(\)')
$pageCategoryAssignments = [regex]::Matches(
    $settingsPageBody.Groups[1].Value, '(?m)^\s*category := "')
# Derived from the category table, not restated. "Seven" was a number that had
# to be remembered, and adding the Launcher Cleanup page made it wrong; the
# property is that EVERY page in the table names its category and resets the
# cursor, whatever the table's length happens to be.
$categoryTableBody = [regex]::Match(
    $source, '(?s)static categories := \[(.*?)\n    \]')
Assert-True $categoryTableBody.Success (
    "The companion's Settings category table could not be extracted.")
$categoryTableCount = @(
    [regex]::Matches($categoryTableBody.Groups[1].Value, '(?m)^\s+\["[^"]+",')).Count
Assert-True (
    $categoryTableCount -gt 0 -and
    $pageCategoryAssignments.Count -eq $categoryTableCount -and
    $pageCursorStarts.Count -eq $categoryTableCount) (
    "Every Settings page must name its category and reset the row cursor. " +
    "Table lists $categoryTableCount page(s); found " +
    $pageCategoryAssignments.Count + " category assignment(s) and " +
    $pageCursorStarts.Count + " cursor reset(s).")

# The row builders take the cursor BY REFERENCE and advance it. Passing it by
# value compiles perfectly and silently stacks every row on the same line.
# Six of these live in SteamShell-Shared.ahk now and are the shell's builders,
# adopted whole; SectionRow and ButtonRow are still this tree's own. The rule is
# the same for all of them, and so is the failure.
foreach ($builder in @(
    "SettingsAddCheckbox", "SettingsAddTextField", "SettingsAddChoice",
    "SettingsAddShortcutField", "SettingsAddPathField", "SettingsAddNote",
    "SettingsAddSliderField",
    "SettingsAddSectionRow", "SettingsAddButtonRow")) {
    Assert-True (
        $source -match "(?m)^$builder\([^\r\n]*&y") (
        "Settings row builder $builder no longer takes the page cursor by reference.")
    # The signature may wrap: SettingsAddTextField takes ten parameters and
    # continues on a second line, so requiring the closing parenthesis before
    # the first newline reported a builder that advances perfectly well.
    Assert-True (
        $source -match
            "(?sm)^$builder\((?:(?!\n\})[\s\S])*?\)\s*\{(?:(?!\n\})[\s\S])*?y \+= ") (
        "Settings row builder $builder no longer advances the page cursor.")
}

# The scrolling viewport, and the four things that have to be true for it to
# work at all.
Assert-True (
    # Positions are captured once, from the real controls.
    $source -match
        '(?sm)^SettingsTrackControl\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'control\.GetPos\(&ctrlX, &ctrlY, &ctrlW, &ctrlH\)(?:(?!\n\})[\s\S])*?' +
        'SettingsControlPositions\[control\.Hwnd\]' -and
    # The scroll extent is measured from what the page actually built.
    $source -match
        '(?sm)^SettingsGetMaxScroll\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'pos\["y"\] \+ pos\["h"\]' -and
    # Showing a category goes through the scrolling layout, not a bare loop.
    $source -match
        '(?sm)^SettingsShowCategory\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SettingsApplyCategoryLayout\(meta\[1\]\)' -and
    # Both scroll inputs are hooked.
    $source -match 'OnMessage\(0x020A, SettingsMouseWheel\)' -and
    $source -match 'OnMessage\(0x0115, SettingsVerticalScroll\)' -and
    $source -match 'ClassScrollBar x" layout\["scrollBarX"\]') (
    "The scrolling Settings viewport is incomplete.")

# Redraw must be suspended across the whole move-and-hide pass. Without it
# Windows repaints between Move and Visible during thumb tracking and leaves
# trails and half-drawn controls.
Assert-True (
    $source -match
        '(?sm)^SettingsApplyCategoryLayout\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SettingsEditorSetRedraw\(false\)(?:(?!\n\})[\s\S])*?' +
        'finally \{(?:(?!\n\})[\s\S])*?SettingsEditorSetRedraw\(true\)') (
    "Settings scrolling no longer batches its control movement behind WM_SETREDRAW.")

# Recorded positions must be cleared with the window that produced them.
# CloseSettings destroys the GUI, so a retained HWND would be looked up against
# a control that no longer exists.
Assert-True (
    $source -match
        '(?sm)^ShowSettings\(\*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SettingsControlPositions := Map\(\)(?:(?!\n\})[\s\S])*?' +
        'SettingsCategoryOffsets := Map\(\)') (
    "Settings control positions survive the window that recorded them.")

# The layout audit runs on the real controls, before anything is shown. Font and
# DPI decide a row's real size, so an overlap can exist that no source-level
# check can see.
$auditIndex = $source.IndexOf('SettingsReportLayoutAudit()')
$showCategoryIndex = $source.IndexOf('SettingsShowCategory(1)')
Assert-True (
    $auditIndex -ge 0 -and
    $showCategoryIndex -ge 0 -and
    $auditIndex -lt $showCategoryIndex -and
    $source -match
        '(?sm)^SettingsAuditLayout\(\)\s*\{(?:(?!\n\})[\s\S])*?overlap') (
    "The Settings layout audit is missing or does not run before the window is shown.")

# ==============================================================================
# THE FOUR CATEGORY NAMES SHARED WITH STANDALONE
# ==============================================================================
# General, Controller & Cursor, RTSS & Performance and Startup Programs exist in
# both trees and now present the settings that exist in BOTH in standalone's
# order. The other three pages have no standalone counterpart and are ordered
# for their own sake -- standalone's Startup & Splash, Focus & Windows and
# Launcher Cleanup do jobs XFE deliberately leaves to Xbox FSE, and inventing
# XFE settings to match them would be worse than the difference.

# General leads with the settings standalone's General also has, in standalone's
# order, before the companion-only heartbeat row.
#
# Audio.EnableQuickControls and Display.EnableQuickControls used to sit between
# QuickMenu.Enable and the accent rows. They are gone from BOTH trees: hiding a
# MAIN row is what [QuickMenu] HiddenItems does, and the layout manager that
# edits it is shared now, so the pair of Enable keys was a second way of saying
# the same thing. The button that replaced them is pinned below.
Assert-True (
    # Order comes from the shared page table now, so the two products cannot
    # order the same settings differently -- which is what this was checking by
    # hand, one product at a time.
    $source -match
        '(?s)"key", "Enable",[\s\S]*?"key", "ShowGameDetection",[\s\S]*?' +
        '"key", "AccentColor",[\s\S]*?"key", "AccentColorCustom",[\s\S]*?' +
        '"key", "ChordHoldMs",[\s\S]*?"key", "HeartbeatSeconds"') (
    "The General page no longer matches standalone's order for the settings both have.")
# The companion reaches the shared layout manager, or it has no way at all to
# hide a MAIN row -- which is the state retiring the Enable keys would leave it
# in if this button were ever dropped.
#
# Scoped to BEHAVIOUR, not to the word. A blanket -notmatch on
# 'EnableQuickControls' also caught RetireQuickControlSettings, which has to name
# the key in order to delete it -- the same trap as a validator comment quoting
# the rule it replaced. What must not come back is the key being READ as a live
# setting or WRITTEN as a default.
Assert-True (
    $source -match 'ShowQuickMenuLayoutManager' -and
    $source -match '(?s)RetireQuickControlSettings\(\).*?IniDelete\(IniPath, retiredSection, "EnableQuickControls"\)' -and
    $source -notmatch 'ReadBool\(\s*"(?:Audio|Display)",\s*"EnableQuickControls"' -and
    $source -notmatch '"EnableQuickControls",\s*"true"') (
    "The companion must offer the shared Quick Menu layout manager, must retire " +
    "the per-row Enable keys, and must not read or default them again.")

# The automatic-mouse controls sit in the left column below the parking rows,
# which is where standalone keeps them. They lived in a free right-hand column
# only because absolute layout left no room below. Two rows since schema 11.
Assert-True (
    # Order comes from the shared page table now, so it is pinned there once
    # rather than in each tree's copy of the page.
    $source -match
        '(?s)"key", "MouseParkEdge"[\s\S]*?"key", "EnableAutoMouseMode"' -and
    $source -match
        '(?s)SettingsAddRowsForCategory\(settings, category, "xfe", &y\)\s*\r?\n\s*' +
        'SettingsAddTextField\(settings, category, "Controller", "AutoMouseExeList"') (
    "The automatic mouse controls are not in standalone's position on the Controller page.")

# The RTSS page is one flowing list, like standalone's. Its two side-by-side
# group boxes are what forced the whole page into hand-placed columns: a group
# box needs its height before the rows inside it exist, so it cannot flow.
Assert-True (
    $source -notmatch 'AddGroupBox\(') (
    "A Settings group box has returned; group boxes cannot flow and force hand placement.")
Assert-True (
    # Section breaks come from the shared page table now, as companion-only
    # rows: the shell has no builder for one, so it omits them rather than
    # having a layout invented for it blind.
    $source -match
        '(?s)"product", "xfe", "type", "section", "label", "Overlay"' +
        '[\s\S]*?"product", "xfe", "type", "section", "label", "Frame Limiter"' -and
    $source -match
        '(?s)SettingsAddRowsForCategory\([^)]*\)\s*\{[\s\S]*?' +
        'case "section":[\s\S]{0,120}?SettingsProductAddSectionRow\(' -and
    $source -match
        '(?s)SettingsProductAddSectionRow\(guiObj, category, title, &y\)\s*\{[\s\S]{0,160}?SettingsAddSectionRow\(') (
    "The RTSS page lost the section breaks that replaced its group boxes.")

# Choice lists derive their stored value from the selected INDEX, so reordering
# one to match standalone's wording would invert the setting. The order is
# pinned here rather than left to the next person to notice.
Assert-True (
    # The order no longer decides anything: choice rows are selected and saved
    # by TEXT in both trees. What must hold is that NOTHING reads a choice back
    # as an index again, which is the shape that made two opposite lists
    # dangerous to merge.
    $source -notmatch 'GetFieldValue\("[^"]*"\s*(?:,\s*\d+\s*)?\)\s*=\s*\d' -and
    $source -notmatch 'ChoiceToValue\(' -and
    $source -match '(?s)SelectChoiceByText\(key, value, choices\)' -and
    # The shell's order, per standing guidance, and safe to adopt only because
    # nothing reads a choice back as an index any more.
    $source -match
        '(?s)"key", "WindowMode",[\s\S]{0,200}?"choices", \["Hidden", "Minimized", "Normal"\]' -and
    # The park edge is a shared row now. Its stored value still comes from the
    # INDEX -- populate Chooses 1 or 2, save reads 1 or 2 -- so the ORDER in the
    # shared table is what must not move, whatever the two entries are called.
    $source -match
        '(?s)"key", "MouseParkEdge",[\s\S]{0,200}?"choices", \["Right", "Left"\]') (
    "A Settings choice list was reordered; its stored value comes from the index.")

# The seam SteamShell-Shared.ahk calls back into. AutoHotkey resolves a missing
# function at run time, not build time, so this cannot be left to the compiler.
#
# It must go through the STAGED commit in SteamShell-Common.ahk. This asserted
# the body contained IniWrite, which described the unstaged per-key loop that
# used to live here: it wrote each key straight into the live file and returned
# false at the first failure without undoing the keys already written. Naming
# IniWrite would now pin the defect rather than the requirement.
Assert-True (
    $source -match
        '(?s)SharedPersistSettings\(changes\)\s*\{(?:(?!\n\})[\s\S])*?CommitIniChangesAt\(') (
    "XFE no longer provides SharedPersistSettings over the staged commit, " +
    "which shared code depends on.")

# The dependency seam must actually wire something, and the pass must run once
# on open.
#
# Two of the rows the shared spec marks with "dependency" are "product", "both"
# -- the RTSS overlay and frame-limiter control modes -- so they reach THIS
# window. While SettingsProductWireDependency was an empty body they did nothing
# here: choosing Toggle left the separate On/Off shortcut rows editable, and
# choosing Separate left the single Toggle shortcut editable, so a shortcut could
# be typed and saved into a field the selected mode ignores.
#
# Running it after SettingsPopulateFields is half the rule. Wiring the drivers
# alone only greys rows once the user touches a driver, so the window would still
# OPEN showing rows the saved mode already ignores.
Assert-True (
    $source -match
        '(?s)SettingsProductWireDependency\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'OnEvent\([^)]*SettingsRefreshDependencies' -and
    $source -match
        '(?s)SettingsRefreshDependencies\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RTSS\.OverlayToggleShortcut(?:(?!\n\})[\s\S])*?RTSS\.FrameLimiterOffShortcut' -and
    $source -match
        '(?s)SettingsPopulateFields\(\)\s*\r?\n(?:(?!\n\})[\s\S])*?SettingsRefreshDependencies\(\)') (
    "The companion's Settings dependency pass is missing, no longer covers the " +
    "shared RTSS control-mode rows, or does not run when the window opens.")

# Staging leaves the occasional abandoned file, so the sweep has to run. Adopting
# the commit without it trades one kind of litter for another, beside the INI.
Assert-True (
    $source -match '(?m)^SweepAbandonedSettingsUpdates\(\)\s*$') (
    "XFE stages its settings writes but never sweeps abandoned staging files.")

# Cross-tree parity. Both trees and the shared file are in this folder, so there
# is no "skipped when the sibling is absent" path any more -- that existed only
# because a frozen release snapshot used to hold one tree. A snapshot is the
# whole folder now, and a silent skip is the last thing this check should be
# capable of.
# The shared Quick Menu dispatcher is called with the variable THIS tree names.
#
# Standalone reads the row id into `id`; the companion dispatches on the
# `action` a row carries and has no `id` in that function. Pasting one tree's
# call into the other names a local that is never assigned, which AutoHotkey
# does not refuse to compile -- it hands QuickMenuActivateShared an empty value
# and every shared row silently stops responding. That happened during the
# consolidation and no existing check saw it: the function existed, the
# manifests agreed, and the row inventory was satisfied. This pins the argument.
Assert-True (
    $source -match '(?m)^\s*if QuickMenuActivateShared\(action\) \{') (
    "QuickMenuActivateSelected must pass its own action to QuickMenuActivateShared; " +
    "the other tree's variable name is an unassigned local here.")
Assert-SharedParity -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-QuickMenuRows -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-SettingsRowsReachConsumers -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-NoAmbiguousDeindentedBlocks -ProjectRoot $projectRoot -File "SteamShell-XFE.ahk" -Quiet:$Quiet
Assert-NoAmbiguousDeindentedBlocks -ProjectRoot $projectRoot -File "SteamShell-Shared.ahk" -Quiet:$Quiet
Assert-NoAmbiguousDeindentedBlocks -ProjectRoot $projectRoot -File "SteamShell-Common.ahk" -Quiet:$Quiet
# Reports only. See Report-StructuralDrift in Validate-Common.ps1 for why a
# high structural score is evidence rather than a verdict.
Report-StructuralDrift -ProjectRoot $projectRoot -Quiet:$Quiet | Out-Null

if (-not $Quiet) {
    Write-Host "SteamShell XFE static validation passed."
    Write-Host ("  " + (Get-ReadStats))
}

# A row that only reports state must not be reachable with the D-pad.
#
# Landing on one gives a highlighted row that does nothing when pressed and says
# nothing about why. "HDR - Not Supported" reads the same whether or not it can
# be selected, so skipping it costs the user nothing and removes a dead end.
#
# The loop is bounded by the row count and restores the original selection when
# every row is inert, which is the only reason a page of nothing but status rows
# terminates at all. Both products do this; they differ only in clamping versus
# wrapping, which they always have.
Assert-True (
    $source -match '(?sm)^QuickMenuRowIsInert\([^)]*\)\s*\{' -and
    $source -match
        '(?sm)^QuickMenuMoveSelection\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'Loop QuickMenuRows\.Length(?:(?!\n\})[\s\S])*?' +
        '!QuickMenuRowIsInert\(QuickMenuSelected\)(?:(?!\n\})[\s\S])*?' +
        'QuickMenuSelected := start') (
    "Quick Menu navigation can land on a row that does nothing again.")

# The same words in both products for a display that cannot do HDR.
#
# -cnotmatch, case-sensitively, on purpose. The support-bundle info block uses a
# lowercase "unsupported" as a machine-readable field value alongside "on",
# "off" and "unavailable"; that is not menu text and must not be swept up here.
# What is forbidden is the old Title Case row wording.
Assert-True (
    $source -match '"Not Supported"' -and
    $source -cnotmatch '"Unsupported"') (
    "The unsupported-HDR wording has drifted from the other product's.")
