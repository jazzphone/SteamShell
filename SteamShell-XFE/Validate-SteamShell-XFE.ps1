param([switch]$Quiet)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePath = Join-Path $projectRoot "SteamShell-XFE.ahk"
$samplePath = Join-Path $projectRoot "SteamShell-XFE_SAMPLE.ini"
$controllerSimulationPath = Join-Path $projectRoot "Test-ControllerProfiles.py"
$iconPath = Join-Path $projectRoot "assets\SteamShell-XFE.ico"
$iconPreviewPath = Join-Path $projectRoot "assets\SteamShell-XFE-icon.png"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path $sourcePath) "SteamShell-XFE.ahk is missing."
Assert-True (Test-Path $samplePath) "SteamShell-XFE_SAMPLE.ini is missing."
Assert-True (Test-Path $controllerSimulationPath) (
    "The learned-controller simulation is missing.")
Assert-True (Test-Path $iconPath) "The SteamShell XFE Windows icon is missing."
Assert-True (Test-Path $iconPreviewPath) "The SteamShell XFE icon preview is missing."
$source = Get-Content -LiteralPath $sourcePath -Raw
$sample = Get-Content -LiteralPath $samplePath -Raw

$functionMatches = [regex]::Matches(
    $source,
    '(?m)^([A-Za-z_][A-Za-z0-9_]*)\([^\r\n{}]*\)\s*\{')
$duplicates = $functionMatches |
    Group-Object { $_.Groups[1].Value.ToLowerInvariant() } |
    Where-Object Count -gt 1
Assert-True ($duplicates.Count -eq 0) (
    "Duplicate top-level functions: " +
    (($duplicates | ForEach-Object Name) -join ", "))

$functionNames = @{}
foreach ($match in $functionMatches) {
    $functionNames[$match.Groups[1].Value.ToLowerInvariant()] = $true
}
$assignments = [regex]::Matches(
    $source,
    '(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:=')
$collisions = @(
    $assignments |
        Where-Object {
            $functionNames.ContainsKey($_.Groups[1].Value.ToLowerInvariant())
        } |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
)
Assert-True ($collisions.Count -eq 0) (
    "Variables shadow AutoHotkey function names: " + ($collisions -join ", "))

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
    "EnsureRtssRunning",
    "StartRtssFromQuickMenu",
    "GetRtssHooksApi",
    "GetRtssGlobalState",
    "GetRtssFrameLimit",
    "GetRtssAvailability",
    "ApplyRtssGlobalState",
    "InitializeTrayMenu",
    "SetCompanionDisabled",
    "StartStartupSplash",
    "StartStartupSplashVideo",
    "CloseStartupSplash",
    "SendSteamOverlayChord",
    "ShowHealthCheck"
)
foreach ($required in $requiredFunctions) {
    Assert-True $functionNames.ContainsKey($required.ToLowerInvariant()) (
        "Required companion function is missing: $required")
}

Assert-True ($source -match '(?m)^#Requires AutoHotkey v2\.0\.19 64-bit$') (
    "The 64-bit AutoHotkey v2 requirement is missing.")
Assert-True ($source -match '(?m)^#SingleInstance Ignore$') (
    "The XFE companion must not replace a surviving instance during re-entry.")
Assert-True ($source -notmatch '(?m)^#NoTrayIcon$') (
    "The notification-area control requires the tray icon to remain visible.")
Assert-True (
    $source -match 'A_TrayMenu\.Add\("Open Quick Menu", TrayOpenQuickMenu\)' -and
    $source -match 'A_TrayMenu\.Add\("Open Settings", TrayOpenSettings\)' -and
    $source -match 'A_TrayMenu\.Add\("Disable", ToggleCompanionDisabled\)' -and
    $source -match 'A_TrayMenu\.Add\("Exit", ExitCompanion\)' -and
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
$runAsMatches = [regex]::Matches($source, '(?i)\*RunAs\s+([^\s''"]+)')
foreach ($match in $runAsMatches) {
    Assert-True ($match.Groups[1].Value -ieq 'schtasks.exe') (
        "Only schtasks.exe may be elevated; found: " + $match.Groups[1].Value)
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
foreach ($pattern in $forbidden) {
    Assert-True ($source -notmatch $pattern) (
        "Forbidden shell/geometry responsibility detected: $pattern")
}

# Startup Programs has one deliberately bounded presentation exception:
# applying the user's explicit Minimized choice for a few seconds after launch.
# WinMinimize is still forbidden everywhere else so this cannot grow back into
# a general-purpose window geometry engine.
$startupWindowModeMatch = [regex]::Match(
    $source,
    '(?ms)^ApplyStartupWindowMode\([^)]*\)\s*\{.*?^}')
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
Assert-True (
    $source -match '(?s)ApplyDisplaySelection\(\).*?DisplayPendingOldScale\s*:=\s*currentScale' -and
    $source -match '(?s)DisplayChangeSafetyTick\(\).*?ApplyPrimaryDisplayMode\(oldMode\).*?ApplyPrimaryDisplayScale\(oldScale\["percent"\]\)' -and
    $source -match '(?s)OnCompanionExit\([^)]*\).*?ApplyPrimaryDisplayMode\(DisplayPendingOldMode\).*?ApplyPrimaryDisplayScale\(DisplayPendingOldScale\["percent"\]\)') (
    "Display scale must share the mode transaction, safety revert, and exit rollback.")
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
    $source -match '(?s)case "RTSS":.*?MenuRow\("rtssOverlayState", "Overlay".*?MenuRow\("rtssFrameLimit", "Frame Limit".*?MenuRow\("rtssSaveProfile", "Save Limit to Profile"') (
    "RTSS global Overlay/Limiter state discovery or Quick Menu rows are incomplete.")
Assert-True (
    $source -match '(?s)case "RTSS":.*?MenuRow\("rtssStart", "Start RTSS".*?"rtssStart"' -and
    $source -match '(?s)QuickMenuActivateSelected\(\).*?case "rtssStart":\s*\r?\n\s*StartRtssFromQuickMenu\(\)' -and
    $source -match '(?s)StartRtssFromQuickMenu\(\).*?EnsureRtssRunning\(\).*?SetTimer\(RefreshQuickMenuAfterRtssStart,\s*-600\)') (
    "The RTSS page must offer and refresh after its couch-friendly start action.")
Assert-True (
    $source -match '(?s)GetRtssSummary\(\).*?"Overlay ".*?" \| Limiter "' -and
    $source -match '(?s)GetRtssAvailability\(\).*?if ProcessExist\("RTSS\.exe"\)\s*\r?\n\s*return "Running"' -and
    $source -match 'MenuRow\("rtssSettings", "RTSS Settings", GetRtssAvailability\(\),\s*\r?\n\s*"rtssSettings"\)' -and
    $source -match '(?s)case "rtssSettings":.*?ShowSettingsCategory\("RTSS & Performance"\)') (
    "RTSS main summary and Settings availability row must remain distinct.")
Assert-True (
    $source -match 'RTSS\.UseDllIntegration' -and
    $source -match 'Use RTSSHooks64\.dll for live state and direct control' -and
    $source -match '(?s)GetRtssHooksApi\(\).*?if !RtssUseDllIntegration\s*\r?\n\s*return 0' -and
    $source -match '(?s)GetRtssSummary\(\).*?return "Running \| Shortcuts"') (
    "The user-selectable RTSS DLL/forced-shortcut mode is incomplete.")
Assert-True (
    $source -match 'StartupSplash\.Enable' -and
    $source -match 'StartupSplash\.Mode' -and
    $source -match 'StartupSplash\.VideoPath' -and
    $source -match 'StartupSplash\.MpvPath' -and
    $source -match '(?s)StartStartupSplash\(\).*?CreateStartupSplashCover\(\).*?StartStartupSplashVideo\(\).*?ArmStartupSplashClose' -and
    $source -match '(?s)StartupSplashKeepOnTop\(\).*?DestroyStartupSplashCover\(\)' -and
    $source -match '(?s)CloseStartupSplash\([^)]*\).*?CreateStartupSplashCover\(\).*?ProcessClose\(StartupSplashMpvPid\).*?DestroyStartupSplashCover\(\)') (
    "The primary-display black/video startup curtain is incomplete.")
Assert-True (
    $source -match '(?s)OnCompanionExit\([^)]*\).*?CloseStartupSplash\(true\)' -and
    $source -match '(?s)SetCompanionDisabled\([^)]*\).*?CloseStartupSplash\(true\)' -and
    $source -match '(?s)Started SteamShell XFE Companion.*?if EnableStartupSplash\s*\r?\n\s*StartStartupSplash\(\)') (
    "The startup curtain must start, disable, and exit with the companion lifecycle.")
Assert-True (
    $source -match '(?s)QuickMenuActivateSelected\(\).*?case "rtssOverlayState":\s*\r?\n\s*ToggleRtssOverlay\(\).*?case "rtssFrameLimit":\s*\r?\n\s*CycleRtssFrameCap\(1\)' -and
    $source -match '(?s)QuickMenuAdjustSelected\([^)]*\).*?case "rtssOverlayState":\s*\r?\n\s*SetRtssOverlayState\(direction > 0\).*?case "rtssFrameLimit":\s*\r?\n\s*CycleRtssFrameCap\(direction\)') (
    "RTSS state rows must support A toggle and Left/Right cycling.")
Assert-True (
    $source -match '(?s)QuickMenuRefresh\(\)\s*\{.*?QuickMenuRender\(\)' -and
    $source -notmatch '(?s)QuickMenuRefresh\(\)\s*\{.*?QuickMenuGui\.Destroy\(') (
    "Quick Menu selection refresh must update persistent controls without rebuilding the GUI.")
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
        '(?s)QuickMenuPaintRows\(\).*?GetClientRect.*?scale\s*:=\s*width\s*/\s*QuickMenuWidth\(\)') (
    "The Quick Menu row surface is no longer built at physical pixel size.")

Assert-True (
    $source -match '(?s)GetSwitchableWindows\(\).*?isSteamWindow\s*:=\s*IsSteamProcess\(exe\).*?WS_EX_TOOLWINDOW.*?&&\s*!isSteamWindow') (
    "The task switcher must retain Steam Big Picture when Steam publishes it as a tool window.")
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
    $source -match '(?s)case "SYSTEM":.*?MenuRow\("sleep".*?MenuRow\("restart".*?MenuRow\("shutdown".*?MenuRow\("exit"') (
    "The System Quick Menu must stay limited to power and companion-exit actions.")
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
Assert-True (
    $source -match 'OnMessage\(0x0218, PowerBroadcastMessage\)' -and
    $source -match '(?s)Heartbeat\(\)\s*\{.*?LastHeartbeatStamp.*?RawInputReregister') (
    "Resume recovery must have a heartbeat-gap fallback, not only the power broadcast.")
Assert-True ($source -match 'RearmControllerInput') (
    "A manual controller re-arm path must exist for when input is dead and the Quick Menu cannot be opened.")

# Test-ControllerProfiles.py MIRRORS the learning heuristic rather than executing
# it, which is the only way to test this off Windows -- but it means the two can
# drift silently, and a mirror that agrees only with itself proves nothing. The
# tuning constants are where drift would actually happen, so they are compared
# directly.
if (Test-Path $controllerSimulationPath) {
    $simulation = Get-Content -LiteralPath $controllerSimulationPath -Raw
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
    $source -match '(?s)PollController\(\)\s*\{.*?if LearnActive\s*\{.*?ResetControllerHoldState[^\r\n]*\r?\n\s*return.*?if !ControllerReadState') (
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
Assert-True (
    $source -match 'Gui\("-Resize \+AlwaysOnTop \+MinSize900x600"') (
    "The Settings window must be always-on-top or it renders behind Xbox FSE.")
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
    $source -match '(?s)case "settings":\s*\r?\n\s*HideQuickMenuForOwnWindow\(\)') (
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
# A control the driver swallows -- the Guide button, typically -- must not stall the
# steps that follow it.
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
Assert-True (
    $source -match 'LearnDetailCtrl\.Text := "Detected: "' -and
    $source -match 'Last detected:') (
    "The learner must keep visible feedback showing which byte/bit was accepted.")
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
    $source -match '(?ms)^ApplyRoundedCorners\([^)]*\)\s*\{.*?IsWindowVisible.*?^}') (
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
    $source -match '(?s)QuickMenuToggleSetting\([^)]*\)\s*\{.*?try\s*\{\s*IniWrite\(.*?\}\s*catch as err.*?SetFieldValue\(meta\["section"\] "\." meta\["key"\], next\)') (
    "Quick Menu toggles must persist transactionally and sync the full Settings control.")
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
# The probe exists to find windows the inventory filters out, so it must
# enumerate every top-level window rather than reusing the inventory.
$probeMatch = [regex]::Match($source, '(?ms)^RunScreenProbe\(\)\s*\{.*?^}')
Assert-True (
    $probeMatch.Success -and
    $probeMatch.Value -match 'WinGetList\(\)') (
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
Assert-True ($source -notmatch '/create /f /sc onlogon') (
    "The logon task must not be created with schtasks defaults; they refuse to start on battery.")
Assert-True ($source -match '<RunLevel>LeastPrivilege</RunLevel>' -and
    $source -notmatch 'HighestAvailable') (
    "The logon task must stay at least privilege; elevation is a rejected design decision.")

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
    $source -match '(?ms)^ControllerLearnRejectAxis\([^)]*\)\s*\{.*?LearnResultAxes\.Delete\(') (
    "A rejected axis must delete its provisional entry so it cannot reach the profile.")
Assert-True (
    $resolveMatch.Success -and
    $resolveMatch.Value -notmatch '(?m)^\s*return false\s*$') (
    "Axis resolve failures must go through ControllerLearnRejectAxis so the reason is recorded and the provisional entry is cleared.")
Assert-True (
    $source -match '(?ms)^ControllerLearnSkip\(\)\s*\{.*?LearnResultAxes\.Delete\(') (
    "Skipping an axis step must discard its provisional answer.")

# Startup window mode. On the de-elevated route explorer.exe starts the program
# and chooses the show state itself, so Run's argument never reaches the child --
# the post-launch sweep is the only thing that enforces Hidden or Minimized
# there, and it must match by process name because Run returns explorer's PID.
$windowModeMatch = [regex]::Match(
    $source, '(?ms)^ApplyStartupWindowMode\([^)]*\)\s*\{.*?^}')
Assert-True (
    $windowModeMatch.Success -and
    $windowModeMatch.Value -match 'WinGetList\("ahk_exe " fileName\)') (
    "The startup window-mode sweep must match by process name; the de-elevated route returns explorer's PID.")
Assert-True (
    $windowModeMatch.Success -and
    $windowModeMatch.Value -match 'A_TickCount - startedTick > WINDOW_MS') (
    "The startup window-mode sweep must stop after a bounded window, or it re-hides a program the user deliberately opened.")
Assert-True ($sample -match '(?m)^WindowMode=Normal$') (
    "The sample startup window mode must default to Normal.")

# Cursor parking. The right edge is the default because a cursor that briefly
# reappears is least visible there on a TV.
Assert-True ($sample -match '(?m)^ParkEdge=right$') (
    "The sample cursor park edge must default to the right.")
Assert-True ($sample -match '(?m)^ParkOnGameStart=true$') (
    "Game-entry cursor parking must be enabled by default.")
Assert-True (
    $source -match '(?ms)^ParkCursor\(\*\)\s*\{.*?ParkEdge = "left"') (
    "ParkCursor must honour the configured park edge.")
Assert-True (
    $source -match '(?s)ForegroundWindowLooksGameLike\(.*?AssistWindowLooksLikeGame\(' -and
    $source -match '(?s)ObserveForeground\(\).*?ParkOnGameStart.*?ParkCursorIfStillForeground\.Bind\(hwnd') (
    "Foreground game/fullscreen transitions must park safely against the window that triggered them.")

$schemaVersion = [regex]::Match(
    $source, '(?m)^global SettingsSchemaVersion\s*:=\s*(\d+)$')
Assert-True $schemaVersion.Success "Runtime settings schema version is missing."
Assert-True (
    $sample -match "(?m)^SettingsSchemaVersion=$($schemaVersion.Groups[1].Value)$") (
    "Sample and runtime settings schema versions do not match.")
# The accent is one design applied to both trees. The selected-row fill must
# stay DERIVED from it: storing the fill separately is what would let a green
# accent sit on a blue-grey fill, the exact mismatch the derivation prevents.
Assert-True (
    $source -match
        '(?s)QM_ROW_SELECTED\s*:=\s*BlendHexColor\(QM_BG,\s*hex,\s*QM_ACCENT_BLEND\)') (
    "The Quick Menu selected-row fill is no longer derived from the accent color.")

# A malformed custom hex or an unknown preset must fall back to a readable
# default rather than reaching the painter.
Assert-True (
    $source -match '(?s)NormalizeHexColor\(value\)\s*\{.*?return ""' -and
    $source -match
        '(?s)QuickMenuApplyAccent\(.*?if\s*\(hex\s*=\s*""\)\s*\{.*?QuickMenuAccentPresetHex\("Steam Blue"\)') (
    "An invalid Quick Menu accent color no longer falls back to the default.")

# Persisting is the transaction boundary: the palette must not repaint in a
# color the portable INI could not record.
Assert-True (
    $source -match
        '(?s)CycleQuickMenuAccent\(direction\)\s*\{.*?try\s*\{\s*\r?\n\s*IniWrite\(chosen,.*?catch as err.*?return\s*\r?\n\s*\}\s*\r?\n\s*QuickMenuApplyAccent\(') (
    "The Quick Menu accent repaints before confirming it was persisted.")

Assert-True ($sample -match '(?m)^AccentColor=Steam Blue') (
    "The sample settings file is missing the Quick Menu accent default.")

Assert-True ($sample -match '(?m)^ControllerDeadzone=4000$') (
    "The sample controller deadzone default must remain 4000.")

if (-not $Quiet) {
    Write-Host "SteamShell XFE static validation passed."
}
