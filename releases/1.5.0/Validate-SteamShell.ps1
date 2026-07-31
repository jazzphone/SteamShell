param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePath = Join-Path $projectRoot "SteamShell.ahk"
$samplePath = Join-Path $projectRoot "SteamShellSettings_SAMPLE.ini"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Get-IniSchema {
    param([string]$Text)

    $section = ""
    $schema = [ordered]@{}
    foreach ($rawLine in ($Text -split "`r?`n")) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith(";")) {
            continue
        }
        if ($line -match '^\[([^\]]+)\]$') {
            $section = $Matches[1]
            continue
        }
        $separator = $line.IndexOf("=")
        if (-not $section -or $separator -lt 1) {
            continue
        }
        $key = $line.Substring(0, $separator).Trim()
        $schema["$section`0$key"] = $true
    }
    return $schema
}

Assert-True (Test-Path $sourcePath) "SteamShell.ahk is missing."
Assert-True (Test-Path $samplePath) "SteamShellSettings_SAMPLE.ini is missing."

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

$defaultMatch = [regex]::Match(
    $source,
    '(?s)GetDefaultSettingsIniText\(\)\s*\{\s*txt\s*:=\s*"\s*\(\s*(.*?)\r?\n\)"')
Assert-True $defaultMatch.Success "The embedded default INI could not be extracted."

$embeddedSchema = Get-IniSchema $defaultMatch.Groups[1].Value
$sampleSchema = Get-IniSchema $sample
$missingFromSample = @($embeddedSchema.Keys | Where-Object { -not $sampleSchema.Contains($_) })
$extraInSample = @($sampleSchema.Keys | Where-Object { -not $embeddedSchema.Contains($_) })
Assert-True ($missingFromSample.Count -eq 0) (
    "Sample INI is missing schema keys: " + ($missingFromSample -join ", "))
Assert-True ($extraInSample.Count -eq 0) (
    "Sample INI has keys absent from the embedded schema: " + ($extraInSample -join ", "))

$runtimeSchemaMatch = [regex]::Match(
    $source,
    '(?m)^global CurrentSettingsSchemaVersion\s*:=\s*(\d+)\s*$')
$defaultSchemaMatch = [regex]::Match(
    $defaultMatch.Groups[1].Value,
    '(?m)^SettingsSchemaVersion\s*=\s*(\d+)')
Assert-True ($runtimeSchemaMatch.Success -and $defaultSchemaMatch.Success) (
    "The runtime or embedded settings schema version could not be read.")
Assert-True (
    $runtimeSchemaMatch.Groups[1].Value -eq
    $defaultSchemaMatch.Groups[1].Value) (
    "The runtime and embedded settings schema versions do not match.")
Assert-True (-not $embeddedSchema.Contains("WindowEngine`0TickIntervalMs")) (
    "Low-level Window Engine timing controls must remain internal.")
Assert-True (-not $embeddedSchema.Contains("Logging`0EnableGameScoreLogging")) (
    "The retired duplicate logging toggle has returned.")
Assert-True (
    -not $embeddedSchema.Contains("Features`0EnableCursorHideOnBoot") -and
    -not $embeddedSchema.Contains("Features`0EnableCursorHideOnRefocus")) (
    "Safe internal cursor-hide behavior has returned to the public settings schema.")
Assert-True (
    $defaultMatch.Groups[1].Value -match
        '(?m)^ControllerDeadzone=4000(?:\s*;.*)?$') (
    "The embedded controller deadzone default is not 4000.")
Assert-True (
    $sample -match '(?m)^ControllerDeadzone=4000(?:\s*;.*)?$') (
    "The sample controller deadzone default is not 4000.")
Assert-True (
    $source -match
        '(?s)sourceVersion\s*<\s*5.*?ControllerDeadzone.*?=\s*8000.*?IniWrite\("4000"') (
    "The schema-5 controller deadzone migration is missing.")
Assert-True (
    $defaultMatch.Groups[1].Value -match
        '(?m)^GameMinScoreToActivate=55(?:\s*;.*)?$') (
    "The embedded foreground-sensitivity default is not 55.")
Assert-True (
    $sample -match
        '(?m)^GameMinScoreToActivate=55(?:\s*;.*)?$') (
    "The sample foreground-sensitivity default is not 55.")
Assert-True (
    $source -match
        '(?s)sourceVersion\s*<\s*6.*?GameMinScoreToActivate.*?=\s*60.*?'
        + 'IniWrite\(\s*"55"') (
    "The schema-6 foreground-sensitivity migration is missing.")
Assert-True (
    $source -match
        '(?s)SettingsEditorAddMappedChoice\(\s*category,\s*'
        + '"GameForegroundAssist",\s*"GameMinScoreToActivate".*?'
        + '"Responsive \(55\)".*?"Balanced \(60\)".*?"Conservative \(70\)"') (
    "Full Settings foreground-sensitivity presets are incomplete.")
$windowManagementEditorFields = [regex]::Matches(
    $source,
    '(?s)SettingsEditorAddCheckbox\(\s*category,\s*"Features",\s*'
    + '"EnableWindowManagement"')
Assert-True ($windowManagementEditorFields.Count -eq 1) (
    "Full Settings must expose exactly one Window Management toggle.")
Assert-True (
    $source -match
        '(?s)"WindowManagement",\s*"MinWidthPercent",\s*'
        + '"Maximize width threshold \(%\)".*?"percent",\s*5,\s*100') (
    "The maximize-width percentage control is not configured correctly.")
Assert-True (
    $source -match
        '(?s)if\s*\(fieldType\s*=\s*"float"\).*?'
        + 'value\s*:=\s*FormatSettingsFloat\(number\)') (
    "Float settings are not normalized before serialization.")

# Every persistent field exposed by the full settings editor must have a
# corresponding embedded/sample INI key. This catches renamed keys that would
# otherwise appear to save successfully and then silently reload a default.
$editorFieldMatches = [regex]::Matches(
    $source,
    '(?s)SettingsEditorAdd(?:Checkbox|TextField|NumberField|Choice|MappedChoice|PathField|ShortcutField|ExeListField)\(\s*category,\s*"([^"]+)"\s*,\s*"([^"]+)"')
foreach ($match in $editorFieldMatches) {
    $schemaKey = $match.Groups[1].Value + "`0" + $match.Groups[2].Value
    Assert-True $embeddedSchema.Contains($schemaKey) (
        "Settings editor field is absent from the INI schema: " +
        $match.Groups[1].Value + "." + $match.Groups[2].Value)
}

# Quick Menu settings use the same persistent schema as the full editor.
$quickWriteMatches = [regex]::Matches(
    $source,
    '(?s)PersistQuickMenuSetting\(\s*"([^"]+)"\s*,\s*"([^"]+)"')
foreach ($match in $quickWriteMatches) {
    $schemaKey = $match.Groups[1].Value + "`0" + $match.Groups[2].Value
    Assert-True $embeddedSchema.Contains($schemaKey) (
        "Quick Menu setting is absent from the INI schema: " +
        $match.Groups[1].Value + "." + $match.Groups[2].Value)
}

$requiredFunctions = @(
    "RestoreExplorerDesktop",
    "GetSteamShellHealthResults",
    "CreateSettingsBackup",
    "ApplySafeModeOverrides",
    "ShowControllerTest",
    "TryInvokeTouchKeyboard",
    "RunViaDesktopShell",
    "FormatSettingsFloat",
    "GetWindowsInputIdleMs",
    "HideShellTaskbars",
    "TaskbarGuardWinEvent",
    "StartTaskbarGuard",
    "StopTaskbarGuard",
    "WindowEngineTitleMatchesBpm",
    "WindowEngineItemIntersectsMonitor",
    "WindowEngineIsLegacyApplicationSurface",
    "WindowEngineIsMinimizedLegacyGameSurface",
    "WindowEngineIsApplicationBlocker",
    "WindowEngineFindOpenApplication",
    "QuoteWindowsCommandLineArg",
    "BuildSteamShellElevationCommand",
    "SteamShellElevationRestartRequested",
    "EnsureSteamShellElevation",
    "SettingsEditorSetRedraw",
    "SettingsEditorRefreshDependencies",
    "WindowEngineTick",
    "GetProcessCpuSample"
)
$functionNames = @{}
foreach ($match in $functionMatches) {
    $functionNames[$match.Groups[1].Value.ToLowerInvariant()] = $true
}

# AutoHotkey identifiers are case-insensitive. A local assignment such as
# `controllerTestActive := ControllerTestActive()` shadows the function and
# fails before the call can be evaluated.
$assignmentMatches = [regex]::Matches(
    $source,
    '(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:=')
$nameCollisions = @(
    $assignmentMatches |
        Where-Object {
            $functionNames.ContainsKey(
                $_.Groups[1].Value.ToLowerInvariant())
        } |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
)
Assert-True ($nameCollisions.Count -eq 0) (
    "Variables shadow AutoHotkey function names: " +
    ($nameCollisions -join ", "))

foreach ($required in $requiredFunctions) {
    Assert-True $functionNames.ContainsKey($required.ToLowerInvariant()) (
        "Required recovery function is missing: $required")
}

Assert-True (
    $source -match
        '(?s)OpenTouchKeyboard\(\).*?RunViaDesktopShell\(tabtipPath,\s*"",\s*tabtipDir\).*?RunViaDesktopShell\(tabtipPath,\s*"/SeekDesktop",\s*tabtipDir\)') (
    "Touch-keyboard fallbacks are not both routed through the desktop shell.")
Assert-True (
    $source -notmatch
        '(?s)OpenTouchKeyboard\(\).*?Run\(''\"''\s*tabtipPath') (
    "OpenTouchKeyboard still launches TabTip directly from elevated SteamShell.")
$parkFunctionMatch = [regex]::Match(
    $source,
    '(?ms)^ParkMouseRightEdge\([^)]*\)\s*\{.*?^}\s*(?=^[A-Za-z_][A-Za-z0-9_]*\s*\()')
Assert-True (
    $parkFunctionMatch.Success -and
    $parkFunctionMatch.Value -match 'SetCursorPos' -and
    $parkFunctionMatch.Value -notmatch 'MouseMove\(') (
    "Cursor parking must move the pointer without injecting idle-resetting mouse input.")
Assert-True (
    $source -match
        '(?s)GetWindowsLastInputTick\(\)\s*\{.*?GetLastInputInfo' -and
    $source -match
        '(?s)GetWindowsInputIdleMs\(\)\s*\{.*?GetWindowsLastInputTick.*?GetTickCount') (
    "Health diagnostics can no longer inspect Windows' last-input clock.")
Assert-True (
    $source -match
        '(?s)ObserveForegroundForMouseParking\(\)\s*\{.*?ScheduleMouseParkAfterFocus' -and
    $source -match
        '(?s)WindowEngineTick\([^)]*\)\s*\{.*?ObserveForegroundForMouseParking\(\)' -and
    $source -match
        '(?s)CommitPendingMousePark\([^)]*\)\s*\{.*?ParkMouseRightEdge') (
    "Foreground-transition mouse parking is no longer connected to the window engine.")

# Resolve named GUI, timer, and Windows-message callbacks. Inline lambdas and
# the deliberately variable `callback` argument are not included here.
$callbackReferences = @()
$callbackReferences += [regex]::Matches(
    $source,
    '\.OnEvent\(\s*"[^"]+"\s*,\s*([A-Za-z_][A-Za-z0-9_]*)') |
    ForEach-Object { $_.Groups[1].Value }
$callbackReferences += [regex]::Matches(
    $source,
    'SetTimer\(\s*([A-Za-z_][A-Za-z0-9_]*)') |
    ForEach-Object { $_.Groups[1].Value }
$callbackReferences += [regex]::Matches(
    $source,
    'OnMessage\(\s*[^,]+,\s*([A-Za-z_][A-Za-z0-9_]*)') |
    ForEach-Object { $_.Groups[1].Value }
$callbackReferences += [regex]::Matches(
    $source,
    'CallbackCreate\(\s*([A-Za-z_][A-Za-z0-9_]*)') |
    ForEach-Object { $_.Groups[1].Value }
$missingCallbacks = @(
    $callbackReferences |
        Where-Object {
            $_ -ne "callback" -and
            -not $functionNames.ContainsKey($_.ToLowerInvariant())
        } |
        Sort-Object -Unique
)
Assert-True ($missingCallbacks.Count -eq 0) (
    "Named callbacks without matching functions: " +
    ($missingCallbacks -join ", "))

$trailingWhitespace = [regex]::Matches($source, '(?m)[ `t]+$')
Assert-True ($trailingWhitespace.Count -eq 0) "SteamShell.ahk contains trailing whitespace."
Assert-True ($source -match 'GuiLiteralText\(title\)') (
    "Settings headings are not using literal-ampersand rendering.")

# Make sure each static Quick Menu row remains connected to its value display
# and activation dispatcher. Unavailable rows intentionally have no action;
# several self-explanatory action rows intentionally display a blank value.
$definitionsStart = $source.IndexOf("QuickMenuGetDefinitions() {")
$definitionsEnd = $source.IndexOf("QuickMenuBuildGui() {", $definitionsStart)
$valuesStart = $source.IndexOf("QuickMenuValue(id) {")
$valuesEnd = $source.IndexOf("QuickMenuRefresh() {", $valuesStart)
$actionsStart = $source.IndexOf("QuickMenuActivateSelected() {")
$actionsEnd = $source.IndexOf("GetActiveAudioOutputDevices() {", $actionsStart)
Assert-True (
    $definitionsStart -ge 0 -and $definitionsEnd -gt $definitionsStart -and
    $valuesStart -ge 0 -and $valuesEnd -gt $valuesStart -and
    $actionsStart -ge 0 -and $actionsEnd -gt $actionsStart) (
    "The Quick Menu dispatch sections could not be extracted.")
$definitionsText = $source.Substring(
    $definitionsStart, $definitionsEnd - $definitionsStart)
$valuesText = $source.Substring($valuesStart, $valuesEnd - $valuesStart)
$actionsText = $source.Substring($actionsStart, $actionsEnd - $actionsStart)
$quickMenuIds = @(
    [regex]::Matches($definitionsText, 'Map\("id",\s*"([^":]+)"') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
)
$blankValueIds = @(
    "control", "desktop", "game", "health",
    "restart", "shutdown", "sleep", "steam"
)
$unavailableActionIds = @("displayUnavailable", "tasksUnavailable")
foreach ($id in $quickMenuIds) {
    if ($blankValueIds -notcontains $id) {
        Assert-True ($valuesText.Contains('"' + $id + '"')) (
            "Quick Menu row has no value mapping: $id")
    }
    if ($unavailableActionIds -notcontains $id) {
        Assert-True ($actionsText.Contains('"' + $id + '"')) (
            "Quick Menu row has no activation mapping: $id")
    }
}

$fullWindowScans = [regex]::Matches($source, 'WinGetList\(\)')
Assert-True ($fullWindowScans.Count -eq 1) (
    "Only WindowEngineBuildSnapshot may perform an unfiltered full-window enumeration.")
Assert-True ($source -notmatch 'Win32_PerfFormattedData_PerfProc_Process') (
    "The retired WMI process-CPU query has returned.")
Assert-True ($source -notmatch 'SetTimer\((CheckWindows|SteamRefocusPolling)') (
    "A legacy window/focus timer is still being scheduled.")
$focusPolicyCalls = [regex]::Matches(
    $source,
    'WindowEngineApplyFocusPolicy\(')
Assert-True ($focusPolicyCalls.Count -eq 2) (
    "The focus policy must have exactly one definition and one runtime call.")
Assert-True (
    $source -notmatch '(?m)^(CheckWindows|MaintainPinnedForeground|SteamRefocusPolling)\s*\(') (
    "A retired window/focus entry point has returned.")
Assert-True ($source -match 'SetTimer\(MonitorShell,\s*ShellMonitorIntervalMs\)') (
    "Shell monitoring is no longer independently scheduled.")
Assert-True (
    $source -match
        '(?s)case\s+"desktop":.*?ExitSteamAndRestoreDesktop\(\)') (
    "The Quick Menu desktop action is no longer linked to Steam shutdown.")
Assert-True (
    $source -match
        '(?s)ExitSteamAndRestoreDesktop\(\)\s*\{.*?ExitToDesktop\(false\)') (
    "Steam shutdown is no longer linked to the temporary desktop restore.")
Assert-True (
    $source -match
        '(?s)RestoreExplorerDesktop\(PermanentRestore,\s*&resultMessage\)\s*\{.*?WriteAndVerifyShellValue\("explorer\.exe".*?if\s*\(!PermanentRestore\).*?WriteAndVerifyShellValue\(nextShell') (
    "Temporary desktop restoration no longer verifies Explorer and restores the next-login shell.")
Assert-True (
    $source -match
        'SettingsEditorSwitchControllerCategory\(settingsCategoryDirection\)') (
    "Full Settings is no longer using trigger-edge category navigation.")
Assert-True (
    $source -match
        'ExecuteControllerBinding\("RB\.Short"\)') (
    "Full Settings no longer exposes RB's configured pointer action.")
Assert-True (
    $source -notmatch
        'ProcessClose\("(?:TabTip|TextInputHost)\.exe"\)') (
    "Touch-keyboard invocation must not terminate Windows text-input hosts.")
Assert-True (
    $source -match
        '"nextAttempt",\s*now\s*\+\s*settleMs') (
    "Window geometry corrections no longer wait for initial layout stability.")
Assert-True (
    $source -match
        '(?s)StartTaskbarGuard\(\)\s*\{.*?SetWinEventHook.*?'
        + '0x8002.*?SetTimer\(HideShellTaskbars,\s*'
        + 'TaskbarGuardSafetyIntervalMs\)') (
    "Taskbar Guard is missing its show-event hook or periodic safety check.")
Assert-True (
    $source -match
        '(?s)TaskbarGuardWinEvent\([^\)]*\)\s*\{.*?'
        + 'static\s+inCallback\s*:=\s*false.*?'
        + 'event\s*:=\s*event\s*&\s*0xFFFFFFFF.*?finally.*?'
        + 'inCallback\s*:=\s*false') (
    "Taskbar Guard's event callback is missing its x64 argument normalization or re-entrancy guard.")
Assert-True (
    $source -match
        'CallbackCreate\(\s*TaskbarGuardWinEvent,\s*"",\s*7\)' -and
    $source -notmatch
        'CallbackCreate\(\s*TaskbarGuardWinEvent,\s*"Fast"') (
    "Taskbar Guard must use a normal AutoHotkey callback thread, not Fast mode.")
Assert-True (
    $source -match
        '(?s)PrepareForDesktopRestore\(\)\s*\{.*?'
        + 'AllowExplorer\s*:=\s*true.*?StopTaskbarGuard\(\)') (
    "Desktop restoration does not stop Taskbar Guard before rebuilding Explorer.")
Assert-True (
    $source -match
        '(?s)ExitCleanup\(ExitReason,\s*ExitCode\)\s*\{.*?'
        + 'StopTaskbarGuard\(true\)') (
    "Process cleanup does not release the Taskbar Guard event callback.")
Assert-True (
    $source -match
        '(?s)WindowEngineTitleMatchesBpm\(title\)\s*\{.*?'
        + 'InStr\(title,\s*expected,\s*false\)') (
    "Big Picture title matching is no longer using partial-title behavior.")
Assert-True (
    $source -match
        '(?s)WindowEngineFindBpm\(snapshot\)\s*\{.*?'
        + 'item\["steam"\].*?item\["minMax"\]\s*!=\s*-1.*?'
        + '0x08000000.*?WindowEngineItemIntersectsMonitor\(item\)') (
    "The title-change Steam fallback can select an off-screen or non-activating helper window.")
Assert-True (
    $source -match
        '(?s)WindowEngineIsLegacyApplicationSurface\(item,\s*allowMinimized\s*:=\s*false\)\s*\{.*?'
        + 'item\["proc"\].*?item\["owner"\].*?0x00040000.*?'
        + 'WindowEngineItemIntersectsMonitor\(item\)') (
    "Legacy game-window detection is missing ownership or activation safeguards.")
Assert-True (
    $source -match
        '(?s)GetTaskSwitcherWindows\(\)\s*\{.*?'
        + 'WindowEngineIsLegacyApplicationSurface\(item,\s*true\).*?'
        + 'item\["minMax"\]\s*=\s*-1.*?'
        + 'legacy fullscreen window') (
    "Task Switcher no longer includes safe untitled legacy game surfaces.")
Assert-True (
    $source -match
        '(?s)WindowEngineIsMinimizedLegacyGameSurface\(item\)\s*\{.*?'
        + 'WindowEngineIsLegacyApplicationSurface\(item,\s*true\).*?'
        + '0x80000000.*?0x00C00000') (
    "Minimized legacy-game restoration is missing its popup/caption safeguards.")
Assert-True (
    $source -match
        '(?s)WindowEngineEvaluateGame\(snapshot.*?'
        + 'WindowEngineIsMinimizedLegacyGameSurface\(item\).*?'
        + 'WindowEngineIsLegacyApplicationSurface\(item\).*?'
        + 'item\["title"\]\s*=\s*""\s*&&\s*!legacySurface') (
    "Game Foreground Assist no longer accepts safe untitled legacy surfaces.")
Assert-True (
    $source -match
        '(?s)WindowEngineIsApplicationBlocker\(item\)\s*\{.*?'
        + 'item\["steam"\].*?item\["minMax"\]\s*=\s*-1.*?'
        + '0x08000000.*?WindowEngineItemIntersectsMonitor\(item\)') (
    "Steam fallback blocker filtering is incomplete.")
Assert-True (
    $source -notmatch 'WindowEngineHasOpenApplication') (
    "The indiscriminate legacy Steam fallback blocker has returned.")
Assert-True (
    $source -match
        'HealthResult\(results,\s*guardStatus,\s*"Taskbar Guard"') (
    "Health Check no longer reports Taskbar Guard status.")
Assert-True (
    $source -match
        '(?s)case\s+"TaskManager":\s*SendChordSafe\("\^\+\{Esc\}"\)') (
    "The controller Task Manager action no longer uses Windows' native shortcut.")
Assert-True (
    $source -match
        '(?s)EnsureSteamShellElevation\(\)\s*\{.*?if\s+A_IsAdmin.*?'
        + 'SteamShellElevationRestartRequested\(\).*?'
        + 'BuildSteamShellElevationCommand\(\).*?RunWait\("\*RunAs\s+".*?'
        + 'catch\s+as\s+err') (
    "SteamShell's guarded administrator handoff is incomplete.")
Assert-True (
    $source -match
        '(?s)BuildSteamShellElevationCommand\(\)\s*\{.*?A_IsCompiled.*?'
        + 'A_ScriptFullPath.*?A_AhkPath.*?/restart.*?'
        + 'for\s+_,\s*argument\s+in\s+A_Args') (
    "The administrator handoff no longer preserves runtime mode and arguments.")
Assert-True (
    $source -match
        '(?s)SteamShellElevationRestartRequested\(\)\s*\{.*?'
        + 'GetCommandLine.*?/restart') (
    "The administrator handoff no longer guards against a non-elevating RunAs loop.")
Assert-True (
    $source -match
        'HealthResult\(results,\s*A_IsAdmin\s*\?\s*"pass"\s*:\s*"warn",\s*'
        + '"Runtime privileges"') (
    "Health Check no longer reports SteamShell's runtime privilege state.")

if (-not $Quiet) {
    $callbackCount = @($callbackReferences | Sort-Object -Unique).Count
    Write-Host (
        "Static validation passed: {0} functions, {1} settings keys, {2} Quick Menu rows, {3} named callbacks." -f
        $functionNames.Count,
        $embeddedSchema.Count,
        $quickMenuIds.Count,
        $callbackCount)
}
