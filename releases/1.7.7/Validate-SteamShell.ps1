param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePath = Join-Path $projectRoot "SteamShell.ahk"
$samplePath = Join-Path $projectRoot "SteamShellSettings_SAMPLE.ini"
$iconPath = Join-Path $projectRoot "assets\SteamShell.ico"
$buildLauncherPath = Join-Path $projectRoot "Build-SteamShell.cmd"

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
Assert-True (Test-Path $iconPath) "The standalone SteamShell icon is missing."
Assert-True (Test-Path $buildLauncherPath) "The double-clickable build launcher is missing."

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

# The schema version is derived from the source and cross-checked against the
# sample, rather than compared with a literal. A hardcoded expected version has
# to be hand-edited on every bump and, until it is, fails as a false alarm that
# says nothing about whether the schema is actually consistent.
$schemaVersion = $runtimeSchemaMatch.Groups[1].Value
$sampleSchemaMatch = [regex]::Match(
    $sample,
    '(?m)^SettingsSchemaVersion\s*=\s*(\d+)')
Assert-True $sampleSchemaMatch.Success (
    "The sample INI does not declare a settings schema version.")
Assert-True ($sampleSchemaMatch.Groups[1].Value -eq $schemaVersion) (
    "The sample INI declares settings schema " +
    $sampleSchemaMatch.Groups[1].Value + " but the source is at " +
    $schemaVersion + ".")
Write-Host "Settings schema version: $schemaVersion"
Assert-True (
    $embeddedSchema.Contains("MousePark`0MouseParkEdge") -and
    $embeddedSchema.Contains("RTSS`0UseDllIntegration") -and
    $embeddedSchema.Contains("Features`0RunElevatedOnStartup") -and
    $embeddedSchema.Contains("Features`0EnableDesktopBlackout") -and
    $embeddedSchema.Contains("Steam`0MenuShortcut") -and
    $embeddedSchema.Contains("Steam`0QuickAccessShortcut") -and
    $embeddedSchema.Contains("Steam`0OverlayShortcut") -and
    $embeddedSchema.Contains("Controller`0AutoMouseExeList") -and
    $embeddedSchema.Contains("Features`0EnableAutoMouseMode") -and
    $embeddedSchema.Contains("Features`0EnableDesktopAutoMouseMode") -and
    $embeddedSchema.Contains("Controller`0EnablePersistentMouseMode") -and
    $embeddedSchema.Contains("Controller`0DesktopAutoMouseExcludeExeList") -and
    $embeddedSchema.Contains("QuickMenu`0AccentColor") -and
    $embeddedSchema.Contains("QuickMenu`0AccentColorCustom")) (
    "Elevation, mouse parking, live RTSS, or Steam Quick Menu options are absent from the settings schema.")
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
        '(?m)^ControllerDeadzone=3000(?:\s*;.*)?$') (
    "The embedded controller deadzone default is not 3000.")
Assert-True (
    $sample -match '(?m)^ControllerDeadzone=3000(?:\s*;.*)?$') (
    "The sample controller deadzone default is not 3000.")
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
        '(?s)sourceVersion\s*<\s*6.*?GameMinScoreToActivate.*?=\s*60.*?' +
        'IniWrite\(\s*"55"') (
    "The schema-6 foreground-sensitivity migration is missing.")
Assert-True (
    $source -match
        '(?s)sourceVersion\s*<\s*8.*?' +
        'Audio\|Display\|RTSS\|SteamMenu\|SteamQuickAccess\|Layout\|Tasks\|GameBar\|Settings\|System.*?' +
        'HiddenItems') (
    "The schema-8 XFE Quick Menu layout migration is missing.")
Assert-True (
    $source -match
        '(?s)sourceVersion\s*<\s*15.*?MigrateQuickMenuOrderForSchema15.*?' +
        'hiddenName\s*!=\s*"layout"') (
    "The schema-15 Quick Menu row migration is missing.")
Assert-True (
    $source -match
        '(?s)sourceVersion\s*<\s*16.*?PresetFrameCap.*?CustomFrameCap.*?' +
        'IniWrite\(.*?"RTSS",\s*"PresetFrameCap"' -and
    $defaultMatch.Groups[1].Value -match '(?m)^PresetFrameCap=158' -and
    $sample -match '(?m)^PresetFrameCap=158') (
    "The schema-16 RTSS Preset/Custom split or its defaults are missing.")
Assert-True (
    $source -match
        '(?s)SettingsEditorAddMappedChoice\(\s*category,\s*' +
        '"GameForegroundAssist",\s*"GameMinScoreToActivate".*?' +
        '"Responsive \(55\)".*?"Balanced \(60\)".*?"Conservative \(70\)"') (
    "Full Settings foreground-sensitivity presets are incomplete.")
$windowManagementEditorFields = [regex]::Matches(
    $source,
    '(?s)SettingsEditorAddCheckbox\(\s*category,\s*"Features",\s*' +
    '"EnableWindowManagement"')
Assert-True ($windowManagementEditorFields.Count -eq 1) (
    "Full Settings must expose exactly one Window Management toggle.")
Assert-True (
    $source -match
        '(?s)"WindowManagement",\s*"MinWidthPercent",\s*' +
        '"Maximize width threshold \(%\)".*?"percent",\s*5,\s*100') (
    "The maximize-width percentage control is not configured correctly.")
Assert-True (
    $source -match
        '(?s)if\s*\(fieldType\s*=\s*"float"\).*?' +
        'value\s*:=\s*FormatSettingsFloat\(number\)') (
    "Float settings are not normalized before serialization.")

# Every persistent field exposed by the full settings editor must have a
# corresponding embedded/sample INI key. This catches renamed keys that would
# otherwise appear to save successfully and then silently reload a default.
$editorFieldMatches = [regex]::Matches(
    $source,
    '(?s)SettingsEditorAdd(?:Checkbox|TextField|NumberField|Choice|MappedChoice|PathField|ShortcutField|ExeListField)\(\s*category,\s*"([^"]+)"\s*,\s*"([^"]+)"')
$duplicateEditorBindings = $editorFieldMatches |
    Group-Object {
        $_.Groups[1].Value.ToLowerInvariant() + "." +
        $_.Groups[2].Value.ToLowerInvariant()
    } |
    Where-Object Count -gt 1
Assert-True ($duplicateEditorBindings.Count -eq 0) (
    "Settings editor contains duplicate persistent bindings: " +
    (($duplicateEditorBindings | ForEach-Object Name) -join ", "))
foreach ($match in $editorFieldMatches) {
    $schemaKey = $match.Groups[1].Value + "`0" + $match.Groups[2].Value
    Assert-True $embeddedSchema.Contains($schemaKey) (
        "Settings editor field is absent from the INI schema: " +
        $match.Groups[1].Value + "." + $match.Groups[2].Value)
}
$settingsCategoryListMatch = [regex]::Match(
    $source,
    '(?s)ShowSettingsEditor\([^)]*\)\s*\{.*?' +
    'SettingsEditorCategories\s*:=\s*\[(.*?)\]')
Assert-True $settingsCategoryListMatch.Success (
    "The Full Settings category list could not be extracted.")
$settingsCategoryNames = @(
    [regex]::Matches($settingsCategoryListMatch.Groups[1].Value, '"([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value }
)
Assert-True (
    $settingsCategoryNames.Count -eq 8 -and
    @($settingsCategoryNames | Sort-Object -Unique).Count -eq 8) (
    "Full Settings must declare exactly eight unique categories.")
foreach ($categoryName in $settingsCategoryNames) {
    Assert-True (
        $source -match (
            'category\s*:=\s*"' +
            [regex]::Escape($categoryName) + '"')) (
        "Full Settings category has no constructed panel: $categoryName")
}
Assert-True (
    $source -match
        '(?s)SettingsEditorAuditLayout\(\)\s*\{.*?overlaps\s*:=' -and
    $source -match
        '(?s)ShowSettingsEditor\([^)]*\)\s*\{.*?' +
        'SettingsEditorReportLayoutAudit\(\).*?' +
        'SettingsEditorRefreshDependencies\(\)') (
    "The all-category Settings geometry audit is missing or disconnected.")

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
    "RegisterCurrentSteamShellAsShell",
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
    "ResolveRtssExecutablePath",
    "ShellCommandExecutablePath",
    "ResolveSavedPreviousShell",
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

# AutoHotkey v2 rejects declaring the same global more than once inside a
# function. Inspect each function-sized source slice so this fails during the
# readable static-validation phase instead of as an opaque interpreter error.
$duplicateFunctionGlobals = @()
$topLevelFunctionCloseRegex = [regex]'(?m)^}'
for ($functionIndex = 0; $functionIndex -lt $functionMatches.Count; $functionIndex++) {
    $functionMatch = $functionMatches[$functionIndex]
    $functionStart = $functionMatch.Index
    $functionCloseMatch = $topLevelFunctionCloseRegex.Match(
        $source, $functionStart)
    Assert-True $functionCloseMatch.Success (
        "Could not locate the closing brace for function: " +
        $functionMatch.Groups[1].Value)
    $functionEnd = $functionCloseMatch.Index + $functionCloseMatch.Length
    $functionText = $source.Substring(
        $functionStart, $functionEnd - $functionStart)
    $declaredGlobals = @(
        [regex]::Matches($functionText, '(?m)^\s+global\s+([^\r\n]+)$') |
            ForEach-Object {
                $_.Groups[1].Value -split ',' |
                    ForEach-Object {
                        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)') {
                            $Matches[1].ToLowerInvariant()
                        }
                    }
            }
    )
    $globalDuplicates = @(
        $declaredGlobals |
            Group-Object |
            Where-Object Count -gt 1 |
            ForEach-Object Name
    )
    foreach ($globalName in $globalDuplicates) {
        $duplicateFunctionGlobals += (
            $functionMatch.Groups[1].Value + "." + $globalName)
    }
}
Assert-True ($duplicateFunctionGlobals.Count -eq 0) (
    "Duplicate global declarations inside functions: " +
    ($duplicateFunctionGlobals -join ", "))

# AutoHotkey v2 rejects an else whose matching if-body is a bare single-statement
# try: the else has nothing to attach to and the script fails to load. Braces are
# required in that shape. Loop/While/For are deliberately not checked here
# because v2 gives those their own legitimate Else clause.
$sourceLines = $source -split '\r?\n'
$danglingElseLines = @()
for ($i = 0; $i -lt $sourceLines.Count; $i++) {
    $current = $sourceLines[$i].Trim()
    if ($current -notmatch '^else\b') {
        continue
    }
    $j = $i - 1
    while ($j -ge 0) {
        $candidate = $sourceLines[$j].Trim()
        if ($candidate -ne "" -and $candidate -notmatch '^;') {
            break
        }
        $j--
    }
    if ($j -lt 0) {
        continue
    }
    $previous = $sourceLines[$j].Trim()
    if ($previous -match '^try\b' -and $previous -notmatch '\{$') {
        $danglingElseLines += ($j + 1).ToString() + '/' + ($i + 1).ToString()
    }
}
Assert-True ($danglingElseLines.Count -eq 0) (
    'A bare "try" is used as an if-body followed by "else", which AutoHotkey v2 ' +
    'cannot parse. Add braces. Body/else line pairs: ' +
    ($danglingElseLines -join ', '))

# AutoHotkey v2 rejects a Case with more than 20 values. Long dispatch lists must
# move to a shared predicate instead of being extended one value at a time.
$overlongCaseLines = @()
for ($i = 0; $i -lt $sourceLines.Count; $i++) {
    $current = $sourceLines[$i].Trim()
    if ($current -notmatch '^case\s+"') {
        continue
    }
    $valueCount = ([regex]::Matches($current, '"[^"]*"')).Count
    if ($valueCount -gt 20) {
        $overlongCaseLines += ($i + 1).ToString() + " (" + $valueCount + ")"
    }
}
Assert-True ($overlongCaseLines.Count -eq 0) (
    'A "Case" carries more than the 20 values AutoHotkey v2 allows. ' +
    'Line (count): ' + ($overlongCaseLines -join ', '))

foreach ($required in $requiredFunctions) {
    Assert-True $functionNames.ContainsKey($required.ToLowerInvariant()) (
        "Required recovery function is missing: $required")
}
Assert-True (
    $source -match
        '(?s)RegisterCurrentSteamShellAsShell\([^)]*\)\s*\{.*?A_IsCompiled.*?A_ScriptFullPath.*?PreviousShell.*?WriteAndVerifyShellValue.*?RegisteredPath' -and
    $source -match
        '(?s)"Register Current EXE as Shell".*?SettingsEditorRegisterCurrentShell') (
    "Direct current-EXE shell registration is missing or disconnected from Full Settings.")

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
Assert-True (
    $source -match '(?m)^CoordMode\s+"Mouse",\s*"Screen"\s*$' -and
    $parkFunctionMatch.Value -match 'MouseParkEdge\s*=\s*"left"') (
    "Screen-coordinate or selectable-edge cursor parking has regressed.")
Assert-True (
    $source -match
        '(?s)QuickMenuBuildGui\(\)\s*\{.*?if\s+!QuickMenuVisible.*?' +
        'QuickMenuRowsCtrl\s*:=\s*QuickMenuGui\.AddText.*?QuickMenuSetRedraw\(false\).*?' +
        'PositionQuickMenuOnTarget.*?RevealWindow.*?' +
        'ApplyRoundedCorners.*?QuickMenuSetRedraw\(true\)' -and
    $source -notmatch
        '(?s)QuickMenuBuildGui\(\)\s*\{.*?' +
        '(?:QuickMenuGui\.Destroy\(\)|ApplyModernWindowStyle\()') (
    "The open Quick Menu is no longer borderless or repaint-in-place across page changes.")

# The rows are one painted surface, not a pool of Static controls. A Win32
# static cannot draw a rounded corner, an outline or a glow, which is why the
# pool was replaced rather than restyled.
Assert-True (
    $source -match '(?s)QuickMenuRefresh\(\)\s*\{.*?QuickMenuPaintRows\(\)' -and
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

# Recovery reasons can include API error text and must determine their own
# wrapped height. A fixed 56-pixel control clipped the final line on hardware.
Assert-True (
    $source -notmatch 'w560 h56 \+Wrap Center' -and
    $source -match '(?s)ShowStartupRecovery\([^)]*\).*?w620 \+Wrap Center.*?reason' -and
    $source -match '(?s)ShowDesktopRestoreRecovery\([^)]*\).*?w620 \+Wrap Center.*?reason' -and
    $source -match
        '(?s)ShowStartupRecovery\([^)]*\).*?SetFont\("s17 Bold".*?' +
        'AddText\("xm w620 Center",\s*"STEAM DID NOT START"\).*?' +
        'SetFont\("s11 Norm"' -and
    $source -match
        '(?s)ShowDesktopRestoreRecovery\([^)]*\).*?SetFont\("s17 Bold".*?' +
        'AddText\("xm w620 Center",\s*"DESKTOP RESTORE FAILED"\).*?' +
        'SetFont\("s11 Norm"') (
    "A recovery dialog has returned to a fixed-height, clipping message control.")
Assert-True (
    $source -match
        '(?s)GetDefaultQuickMenuOrder\(\)\s*\{.*?' +
        '"audio".*?"display".*?"rtss".*?"steammenu".*?' +
        '"steamquickaccess".*?"tasks".*?"gamebar".*?"keyboard".*?"mousemode".*?' +
        '"settings".*?"system"' -and
    $source -match
        '(?s)"Steam Menu".*?"Steam Quick Access".*?"Task Switcher".*?' +
        '"Game Bar".*?"Open Keyboard".*?"Mouse Mode".*?"Settings".*?"System"' -and
    $source -match
        '(?s)case\s+"settings":\s*return\s+"Features & Configuration".*?' +
        'case\s+"system":\s*return\s+"Power & Diagnostics"') (
    "The Quick Menu main page no longer matches the XFE row set and descriptions.")
Assert-True (
    $source -match
        '(?s)"gamebar",\s*Map\("id",\s*"gameBar".*?' +
        '"keyboard",\s*Map\("id",\s*"openKeyboard".*?' +
        '"mousemode",\s*Map\("id",\s*"qPersistentMouse"' -and
    $source -match
        '(?s)case\s+"openKeyboard":.*?HideQuickMenu\(false\).*?' +
        'SetTimer\(OpenTouchKeyboard,\s*-100\)' -and
    $source -match
        '(?s)case\s+"qPersistentMouse":.*?EnablePersistentMouseMode.*?' +
        'CommitIniChanges\(changes\)' -and
    $source -match
        '(?s)AutoMouseModeActive\(\).*?if EnablePersistentMouseMode\s*\r?\n\s*return true') (
    "Open Keyboard or persistent Mouse Mode is not wired safely on the main Quick Menu.")
Assert-True (
    $source -match
        '(?s)QuickMenuHandleController\([^)]*\).*?buttons\s*&\s*0x8000.*?' +
        'QuickMenuPage\s*:=\s*"LAYOUT".*?QuickMenuBuildGui\(\)' -and
    $source -match
        '(?s)if\s*\(QuickMenuPage\s*=\s*"LAYOUT"\).*?' +
        '"setControllerMappings".*?"Set Controller Mappings".*?return rows' -and
    $source -match
        '(?s)case\s+"setControllerMappings":.*?' +
        'SetTimer\(ShowControllerMappingWindow,\s*-100\)' -and
    $source -notmatch 'Map\("id",\s*"layout"' -and
    $source -notmatch 'Map\("id",\s*"qControllerMap"') (
    "Holding Y must open the Quick Settings mapping page and its editor action.")
Assert-True (
    $source -match 'Hold Y for Controller Mappings') (
    "The main-page controller mapping hint is incomplete.")
Assert-True (
    $source -match
        '(?s)SettingsEditorControllerActive\(\).*?ControllerMapGui.*?' +
        'rootHwnds\.Push\(guiRef\.Hwnd\)' -and
    $source -match
        '(?s)if\s*\(settingsControllerActive\).*?SystemCursor\("Show"\).*?' +
        'SettingsEditorHandlePointer' -and
    $source -match
        '(?s)ShowControllerMappingWindow\(\*\).*?' +
        'SetTimer\(PollController,\s*ControllerPollIntervalMs\)') (
    "SteamShell settings/editor windows no longer receive automatic controller mouse mode.")
Assert-True (
    $source -match
        '(?s)HideQuickMenu\([^)]*\).*?ControllerNeedsFreshBaseline\s*:=\s*true' -and
    $source -match
        '(?s)if ControllerNeedsFreshBaseline.*?downTick\[def\[1\]\]\s*:=\s*0.*?return') (
    "Closing Quick Settings can leak its final button release into persistent mappings.")
Assert-True (
    $source -match
        '(?s)if\s*\(QuickMenuPage\s*=\s*"SETTINGS"\).*?' +
        '"windowsSettings".*?"Windows Settings".*?return rows' -and
    $source -match
        '(?s)case\s+"windowsSettings":.*?HideQuickMenu\(false\).*?' +
        'SetTimer\(OpenWindowsSettings,\s*-100\)' -and
    $source -notmatch '"settingsReload",\s*"label",\s*"Reload Settings"') (
    "The Settings submenu does not expose Windows Settings or still exposes Reload Settings.")
Assert-True (
    $source -match '(?s)if\s*\(QuickMenuPage\s*=\s*"SYSTEM"\).*?return rows' -and
    $source -notmatch '"control",\s*"label",\s*"Diagnostics Control Panel"' -and
    $source -notmatch '"health",\s*"label",\s*"SteamShell Health Check"') (
    "The System submenu still exposes removed diagnostic rows.")
Assert-True (
    $source -match
        '(?s)if\s*\(QuickMenuPage\s*=\s*"AUDIO"\).*?' +
        '"Back".*?"audioOutput".*?"Output".*?"volume".*?"Volume".*?' +
        '"mute".*?"Mute".*?return rows' -and
    $source -match
        '(?s)if\s*\(QuickMenuPage\s*=\s*"DISPLAY"\).*?' +
        '"Back".*?"HDR".*?"displayResolution".*?"Resolution".*?' +
        '"displayRefresh".*?"Refresh Rate".*?"displayScale".*?"Scale".*?' +
        '"displayApply".*?"Apply".*?return rows' -and
    $source -match
        '(?s)EnsureDisplaySelection\(\).*?CycleDisplayResolution.*?' +
        'CycleDisplayFrequency.*?ApplyDisplaySelection' -and
    $source -match
        '(?s)if\s*\(QuickMenuPage\s*=\s*"RTSS"\).*?' +
        '"Back".*?"rtssStart".*?"Start RTSS".*?"rtssOverlayState".*?' +
        '"rtssFrameLimit".*?"Frame Limit".*?"rtssFrameLimitCustom".*?' +
        '"Custom FPS".*?"rtssSaveProfile".*?"Save Limit To Profile".*?' +
        '"rtssSettings".*?"RTSS Settings".*?return rows') (
    "Audio, Display, or RTSS Quick Menu submenus no longer match XFE.")
Assert-True (
    $source -match
        '(?s)CycleRtssFrameCap\(direction\).*?entries\.Push\("configured"\).*?' +
        'SetRtssGlobalFrameLimit\(customFps\).*?' +
        'SetRtssGlobalFrameLimit\(RtssPresetFrameCap\)' -and
    $source -match
        'RtssPresetFrameCap > 0 && !IsRtssFrameCapPreset\(RtssPresetFrameCap\)' -and
    $source -match
        '(?s)CommitRtssPendingFrameCap\(\).*?' +
        'PersistRtssCustomFrameCap\(value\)' -and
    $source -match 'PRESET · .*? FPS') (
    "RTSS Preset selection or retained Custom FPS persistence is incomplete.")
Assert-True (
    $source -match
        '(?s)SendToPretty\(sendStr\)\s*\{.*?' +
        'while\s*\(text\s*!=\s*""\s*&&\s*modifiers\.Has.*?' +
        'return prefix text' -and
    $source -notmatch
        '(?s)SendToPretty\(sendStr\)\s*\{.*?' +
        'StrReplace\([^,]+,\s*"\+",\s*"Shift\+"' -and
    $source -match '(?m)^MenuShortcut=\^1(?:\s*;.*)?$' -and
    $source -match '(?m)^QuickAccessShortcut=\^2(?:\s*;.*)?$') (
    "Steam shortcuts must remain Ctrl+1/Ctrl+2 and format without a false Shift modifier.")
Assert-True (
    $source -match
        '(?s)SendSteamOverlayChord\(\)\s*\{.*?' +
        'SetKeyDelay\(35,\s*80\).*?SendEvent\(SteamOverlayShortcut\)' -and
    $source -match
        '(?s)QuickMenuHideThenSteamMenu\(steamInFront\)\s*\{.*?' +
        'SetTimer\(SendSteamOverlayChord,\s*-150\)' -and
    $source -match
        '(?s)case\s+"steamMenu":\s*' +
        'if\s*!IsSteamRunning\(\).*?' +
        'QuickMenuHideThenSteamMenu\(IsSteamProcess\(GetQuickMenuPreviousExe\(\)\)\)') (
    "The in-game Steam overlay is no longer using XFE's paced SendEvent path.")
Assert-True (
    $source -match
        '(?s)SelectTaskSwitcherWindow\(hwnd,\s*lockFocus\s*:=\s*false\).*?' +
        'if\s*!lockFocus\s*.*?ReleasePinnedForeground\(false\).*?' +
        'if\s*lockFocus\s*\{.*?PinnedForegroundHwnd\s*:=\s*hwnd' -and
    $source -match
        '(?s)if\s*\(pressed\s*&\s*0x8000\).*?' +
        'SelectTaskSwitcherWindow\(lockHwnd,\s*true\)' -and
    $source -match
        'A switch\s+.*?Y switch \+ lock.*?Hold X force close') (
    "Task Switcher must use A for one-shot activation and Y for activation with focus lock.")
Assert-True (
    $source -match
        '(?s)ShowQuickMenu\(\*?\)\s*\{.*?' +
        'ForceForegroundWindow\(QuickMenuGui\.Hwnd\).*?' +
        'SetTimer\(QuickMenuEnsureForeground,\s*-75\)' -and
    $source -match
        '(?s)ForceForegroundWindow\(hwnd\)\s*\{.*?' +
        'AttachThreadInput.*?SetForegroundWindow.*?AttachThreadInput') (
    "Quick Menu no longer guarantees foreground ownership over Steam.")
Assert-True (
    $source -match
        '(?s)\+MaxSize980x660.*?windowDpi\s*:=\s*Max\(96,\s*A_ScreenDPI\).*?' +
        'ClampInt\(availableLogicalHeight,\s*450,\s*660\)' -and
    $source -match
        '(?s)actionLeft\s*:=\s*255.*?actionRight\s*:=\s*610.*?' +
        'actionWidth\s*:=\s*335') (
    "Full Settings is no longer work-area bounded or using the aligned Advanced action grid.")
Assert-True (
    $source -match
        '(?s)SettingsGui\s*:=\s*Gui\(\s*"' +
        '\+AlwaysOnTop \+Resize \+MinimizeBox -MaximizeBox ' +
        '\+MinSize980x450 \+MaxSize980x660"' -and
    $source -notmatch
        '(?s)SettingsGui\s*:=\s*Gui\(\s*"[^"]*\+ToolWindow') (
    "Full Settings must use standard window chrome with Minimize enabled and Maximize disabled.")
Assert-True (
    $source -match
        '(?s)QuickMenuKeyboardActive\([^)]*\)\s*\{.*?' +
        'QuickMenuVisible.*?WinActive\("ahk_id "\s*QuickMenuGui\.Hwnd\)' -and
    $source -match
        '(?s)RegisterQuickMenuKeys\(\)\s*\{.*?' +
        'HotIf\s+QuickMenuKeyboardActive.*?' +
        'Hotkey\("Up".*?QuickMenuMoveSelection\(-1\).*?' +
        'Hotkey\("Down".*?QuickMenuMoveSelection\(1\).*?' +
        'Hotkey\("Left".*?QuickMenuAdjustSelected\(-1\).*?' +
        'Hotkey\("Right".*?QuickMenuAdjustSelected\(1\).*?' +
        'Hotkey\("Enter".*?QuickMenuActivateSelected.*?' +
        'Hotkey\("Space".*?QuickMenuActivateSelected.*?' +
        'Hotkey\("Backspace".*?QuickMenuGoBack.*?' +
        'Hotkey\("Delete".*?QuickMenuCloseSelected.*?' +
        'Hotkey\("Home".*?QuickMenuSelectFirst.*?' +
        'Hotkey\("End".*?QuickMenuSelectLast') (
    "Quick Menu focus-gated keyboard navigation is incomplete.")
Assert-True (
    $source -match
        'Hotkey\("\^!\+q",\s*\(\*\)\s*=>\s*ToggleQuickMenu\(\)\)' -and
    $source -match
        'Hotkey\("\^!\+p",\s*\(\*\)\s*=>\s*ShowControlPanel\(\)\)' -and
    $source -match
        'Hotkey\("\^!\+s",\s*\(\*\)\s*=>\s*ShowSettingsEditor\(\)\)' -and
    $source -notmatch
        'Hotkey\("\^!\+p",\s*\(\*\)\s*=>\s*ShowSettingsEditor\(\)\)') (
    "Global Quick Menu or Settings shortcut routing has regressed.")
Assert-True (
    $source -match
        '(?s)GetRtssHooksApi\(\)\s*\{.*?RTSSHooks64\.dll.*?' +
        'GetFlags.*?SetFlags' -and
    $source -match
        '(?s)GetRtssFrameLimit\([^)]*\)\s*\{.*?FramerateLimit' -and
    $source -match
        '(?s)ToggleRtssOverlay\(\)\s*\{.*?GetRtssGlobalState') (
    "Live RTSS state/control or its profile frame-limit query is incomplete.")
Assert-True (
    $source -match
        '(?s)GetPrimaryDisplayScale\(\)\s*\{.*?GET_DPI_SCALE' -and
    $source -match
        '(?s)ApplyDisplaySelection\(\)\s*\{.*?' +
        'ApplyPrimaryDisplayMode.*?ApplyPrimaryDisplayScale.*?' +
        'DisplayChangeSafetyTick' -and
    $source -match
        '(?s)GetPrimaryHdrState\(\)\s*\{.*?' +
        'DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO' -and
    $source -match
        '(?s)ToggleQuickMenuHdrState\(\)\s*\{.*?SetQuickMenuHdrState') (
    "Windows Scale or live HDR parity has regressed.")
Assert-True (
    $source -match
        '(?s)GetPrimaryDisplayModes\(\)\s*\{.*?Loop\s*\{.*?' +
        'EnumDisplaySettingsW.*?if\s*\(!ok\)\s*\r?\n\s*break' -and
    $source -notmatch
        '(?s)GetPrimaryDisplayModes\(\)\s*\{.*?Loop\s+512') (
    "Display mode enumeration must continue until Windows reports the true end of the driver list.")
Assert-True (
    $source -match
        '(?s)ApplyTrayIconImage\(\)\s*\{.*?SteamShell\.ico' -and
    $source -match
        '(?s)InitializeTrayMenu\(\)\s*\{.*?ApplyTrayIconImage\(\).*?' +
        'RefreshTrayMenu\(\).*?RegisterTaskbarCreatedListener\(\)') (
    "The standalone notification-area menu or icon is incomplete.")
# The tray right-click shows the ordinary Windows menu. The interception that
# replaced it with the Quick Menu is deliberately gone -- reaching a tray icon
# means using a pointer, and a controller user opens the Quick Menu by chord or
# hotkey. Asserted negatively so it cannot quietly return.
Assert-True (
    $source -notmatch 'OnMessage\(0x404' -and
    $source -notmatch 'TrayIconNotify') (
    "The tray right-click interception has returned; it should show the native menu.")
# Automatic mouse mode is a virtual View/Back hold, deliberately reusing the
# existing mappings rather than introducing a second keymap that could drift from
# them. It must also be evaluated after the escape chords, which read the real
# button state, so a misconfigured list stays recoverable without a keyboard.
Assert-True (
    $source -match
        '(?s)viewDown\s*:=\s*\(buttons\s*&\s*0x0020\)\s*\|\|\s*autoMouse' -and
    $source -match
        '(?s)quickChordNow\s*:=.*?autoMouse\s*:=\s*AutoMouseModeActive\(\)') (
    "Automatic mouse mode is not a virtual View hold evaluated after the escape chords.")

# PollController both reads and writes MouseHidden when automatic mouse mode
# engages. AutoHotkey v2 therefore requires an explicit global declaration;
# without it, the read fails because the later assignment makes the name local.
Assert-True (
    $source -match
        '(?s)PollController\(\)\s*\{.*?global\s+MouseHidden.*?static\s+state' -and
    $source -match
        '(?s)if\s*\(autoMouse\s*&&\s*MouseHidden\).*?MouseHidden\s*:=\s*false') (
    "PollController no longer declares MouseHidden global for automatic mouse mode.")

# The feature must be disableable without discarding the EXE list, and the
# toggle must be read ahead of the result cache or turning it off would linger.
Assert-True (
    $source -match
        '(?s)AutoMouseModeActive\(\)\s*\{.*?if\s*!EnableAutoMouseMode\s*\r?\n\s*return false.*?' +
        'if\s*\(!DesktopMode\s*&&\s*AutoMouseExeSet\.Count\s*=\s*0\)' -and
    $source -match
        '(?s)EnableAutoMouseMode\s*:=\s*ToBool\(IniReadS\("Features","EnableAutoMouseMode"') (
    "Automatic mouse mode has no working kill switch independent of its EXE list.")
Assert-True (
    $source -match
        '(?s)AutoMouseProcessMatches\(exeName\)\s*\{.*?' +
        'AutoMouseExeSet\.Has\("explorer\.exe"\).*?' +
        '"startmenuexperiencehost\.exe".*?' +
        '"shellexperiencehost\.exe".*?' +
        '"searchhost\.exe".*?' +
        '"searchui\.exe"' -and
    $source -match
        '(?s)AutoMouseModeActive\(\).*?' +
        'foregroundExe\s*:=\s*StrLower\(WinGetProcessName\("ahk_id " hwnd\)\).*?' +
        'AutoMouseProcessMatches\(foregroundExe\)') (
    "The explorer.exe automatic-mouse opt-in no longer covers Start and Search shell hosts.")
Assert-True (
    $source -match
        '(?s)AutoMouseModeActive\(\).*?if\s*\(DesktopMode\s*&&\s*!EnableDesktopAutoMouseMode\).*?' +
        'DesktopMode\s*\?\s*!DesktopAutoMouseExcludeExeSet\.Has\(foregroundExe\)' -and
    $source -match
        '(?s)LoadSettings\(\).*?EnableDesktopAutoMouseMode\s*:=\s*ToBool.*?' +
        'DesktopAutoMouseExcludeExeList.*?DesktopAutoMouseExcludeExeSet\s*:=\s*Map\(\)' -and
    $source -match
        '(?s)TrayToggleDesktopAutoMouse\([^)]*\).*?CommitIniChanges.*?' +
        'EnableDesktopAutoMouseMode.*?RefreshTrayMenu\(\)' -and
    $source -match
        '(?s)RefreshTrayMenu\(\).*?Automatic Mouse Throughout Desktop.*?' +
        'A_TrayMenu\.Check' -and
    $source -match
        '(?s)SettingsEditorAddCheckbox\(\s*category,\s*"Features",\s*' +
        '"EnableDesktopAutoMouseMode"' -and
    $source -match
        '(?s)SettingsEditorAddExeListField\(\s*category,\s*"Controller",\s*' +
        '"DesktopAutoMouseExcludeExeList"') (
    "Desktop-wide automatic mouse mode, exclusions, Settings, or tray control are disconnected.")

# The selected-row fill must stay DERIVED from the accent. Storing it separately
# is what would let a green accent sit on a blue-grey fill, which is the exact
# mismatch the derivation exists to prevent.
Assert-True (
    $source -match
        '(?s)QM_ROW_SELECTED\s*:=\s*BlendHexColor\(QM_BG,\s*hex,\s*QM_ACCENT_BLEND\)') (
    "The Quick Menu selected-row fill is no longer derived from the accent color.")

# A malformed custom hex or an unknown preset must fall back to a readable
# default rather than reaching the painter.
Assert-True (
    $source -match '(?s)NormalizeHexColor\(value\)\s*\{.*?return ""' -and
    $source -match
        '(?s)QuickMenuApplyAccent\(.*?if\s*\(hex\s*=\s*""\)\s*\{.*?QuickMenuAccentPresetHex\("Purple"\)') (
    "An invalid Quick Menu accent color no longer falls back to the default.")

# Reload remains available through the keyboard shortcut, but intentionally no
# longer consumes a couch-facing Settings row.
Assert-True (
    $source -match 'ReloadSettings\(' -and
    $source -notmatch '"settingsReload",\s*"label",\s*"Reload Settings"') (
    "Reload Settings returned to the Quick Menu or lost its non-menu recovery path.")
Assert-True (
    $source -match
        '(?s)RefreshTrayMenu\(\)\s*\{.*?Open Quick Menu.*?' +
        'if\s*\(DesktopMode\).*?Return to SteamShell.*?' +
        'Exit Steam to Desktop.*?Exit SteamShell') (
    "The notification-area menu is no longer context-aware for desktop mode.")
# The desktop-restore path restarts Explorer, which destroys every existing
# notification-area icon. Losing the TaskbarCreated re-assert would silently
# make SteamShell unreachable after exiting to the desktop.
Assert-True (
    $source -match
        '(?s)RegisterTaskbarCreatedListener\(\)\s*\{.*?' +
        'RegisterWindowMessageW".*?"TaskbarCreated".*?' +
        'OnMessage\(TaskbarCreatedMessage,\s*TaskbarCreatedHandler\)' -and
    $source -match
        '(?s)TaskbarCreatedHandler\(\*\)\s*\{.*?SetTimer\(ReassertTrayIcon' -and
    $source -match
        '(?s)ReassertTrayIcon\(\)\s*\{.*?A_IconHidden\s*:=\s*true.*?' +
        'A_IconHidden\s*:=\s*false.*?ApplyTrayIconImage\(\)') (
    "The tray icon is no longer re-asserted after an Explorer taskbar rebuild.")
$trayInitCall = [regex]::Match($source, '(?m)^InitializeTrayMenu\(\)\s*$')
$explorerBoot = [regex]::Match($source, '; Launch Explorer if not running')
Assert-True (
    $trayInitCall.Success -and $explorerBoot.Success -and
    $trayInitCall.Index -lt $explorerBoot.Index) (
    "The tray must be initialised before Explorer starts so TaskbarCreated is not missed.")

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

$trailingWhitespace = [regex]::Matches($source, '(?m)[ \t]+$')
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
$blankValueIds = @("desktop", "restart", "shutdown", "sleep")
$unavailableActionIds = @(
    "displayScaleUnavailable", "displayUnavailable", "hdrUnavailable",
    "rtssDisabled", "rtssMissing", "tasksUnavailable"
)
# Settings rows are dispatched through shared predicates rather than named cases,
# because AutoHotkey v2 caps a Case at 20 values. Their pipe-separated id lists
# count as activation coverage.
$predicateActionIds = @{}
foreach ($predicateName in @('IsQuickMenuToggleSetting', 'IsQuickMenuAdjustSetting')) {
    $predicateMatch = [regex]::Match(
        $source,
        ('(?ms)^' + $predicateName + '\([^)]*\)\s*\{.*?^\}\s*$'))
    Assert-True $predicateMatch.Success (
        "The Quick Menu settings dispatch predicate is missing: $predicateName")
    foreach ($literal in [regex]::Matches($predicateMatch.Value, '"([^"]*)"')) {
        foreach ($part in ($literal.Groups[1].Value -split '\|')) {
            $trimmedId = $part.Trim()
            if ($trimmedId) {
                $predicateActionIds[$trimmedId] = $true
            }
        }
    }
}
# Both switches must actually consult the predicates, or the ids above would be
# counted as covered while nothing dispatched them.
Assert-True (
    ([regex]::Matches($source, 'IsQuickMenuToggleSetting\(id\)')).Count -ge 2 -and
    ([regex]::Matches($source, 'IsQuickMenuAdjustSetting\(id\)')).Count -ge 2) (
    "Quick Menu activation or adjustment no longer consults the settings predicates.")
foreach ($id in $quickMenuIds) {
    if ($blankValueIds -notcontains $id) {
        Assert-True ($valuesText.Contains('"' + $id + '"')) (
            "Quick Menu row has no value mapping: $id")
    }
    if ($unavailableActionIds -notcontains $id) {
        Assert-True (
            $actionsText.Contains('"' + $id + '"') -or
            $predicateActionIds.ContainsKey($id)) (
            "Quick Menu row has no activation mapping: $id")
    }
}
# The reverse direction: a predicate id with no row means a setting was renamed
# or removed and its dispatch entry was left behind.
foreach ($predicateId in $predicateActionIds.Keys) {
    Assert-True ($quickMenuIds -contains $predicateId) (
        "Quick Menu settings dispatch references a row that no longer exists: $predicateId")
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
    $source -match 'global\s+DesktopRestorePending\s*:=\s*false' -and
    $source -match
        '(?s)ShowQuickMenu\([^)]*\)\s*\{.*?DesktopRestorePending.*?' +
        'if\s*\(QuickMenuVisible\s*\|\|\s*DesktopRestorePending\)' -and
    $source -match
        '(?s)ExitSteamAndRestoreDesktop\(\)\s*\{.*?' +
        'DesktopRestorePending\s*:=\s*true.*?DestroyQuickMenuForSurfaceTransition\(\)') (
    "The Steam shutdown wait can reopen the Quick Menu during desktop restoration.")
Assert-True (
    $source -match
        '(?s)HideQuickMenu\(restorePrevious\s*:=\s*true\)\s*\{.*?' +
        'QuickMenuVisible\s*:=\s*false.*?ShowWindow.*?QuickMenuGui\.Hwnd.*?"Int",\s*0.*?' +
        'QuickMenuDestroyWindow\(\)' -and
    $source -match
        '(?s)QuickMenuDestroyWindow\(\)\s*\{.*?' +
        'SendMessage\(0x0172,\s*0,\s*0,\s*QuickMenuRowsCtrl\).*?' +
        'QuickMenuGui\.Destroy\(\).*?QuickMenuGui\s*:=\s*unset') (
    "A closed Quick Menu can retain a hidden compositor surface across game transitions.")
Assert-True (
    $source -match
        '(?s)DestroyQuickMenuForSurfaceTransition\(\)\s*\{.*?' +
        'HideQuickMenu\(false\).*?DwmFlush') (
    "Desktop restoration no longer destroys and flushes the Quick Menu compositor surface.")
Assert-True (
    $source -match
        '(?s)ExitSteamAndRestoreDesktop\(\)\s*\{.*?ExitToDesktop\(false\)') (
    "Steam shutdown is no longer linked to the temporary desktop restore.")
Assert-True (
    $source -match
        '(?s)RestoreExplorerDesktop\(PermanentRestore,\s*&resultMessage\)\s*\{.*?WriteAndVerifyShellValue\("explorer\.exe".*?if\s*\(!PermanentRestore\).*?WriteAndVerifyShellValue\(nextShell') (
    "Temporary desktop restoration no longer verifies Explorer and restores the next-login shell.")

# Desktop mode: a session restore hands the desktop back to Explorer but keeps
# SteamShell resident. A permanent restore has deregistered the shell and must
# still terminate.
Assert-True (
    $source -match
        '(?s)ExitToDesktop\(PermanentRestore\s*:=\s*false,\s*ExitAfterRestore\s*:=\s*false\)\s*\{.*?' +
        'if\s*\(PermanentRestore\s*\|\|\s*ExitAfterRestore\)\s*\{.*?ExitApp\(\).*?' +
        'EnterDesktopMode\(') (
    "A session desktop restore must keep SteamShell running while a permanent restore still exits.")
Assert-True (
    $source -match
        '(?s)EnterDesktopMode\(reason\s*:=\s*""\)\s*\{.*?DesktopMode\s*:=\s*true.*?' +
        'DisarmSteamLifecycle\(\).*?ApplyRuntimeTimers\(\).*?ReassertTrayIcon\(\)') (
    "Entering desktop mode no longer disarms the Steam lifecycle or re-asserts the tray icon.")
# Without this, MonitorShell observes Steam as still-launched-but-absent and
# immediately re-enters the restore path on every tick.
Assert-True (
    $source -match
        '(?s)DisarmSteamLifecycle\(\)\s*\{.*?SteamLaunched\s*:=\s*false.*?' +
        'SteamObservedRunning\s*:=\s*false.*?SteamMissingSinceTick\s*:=\s*0' -and
    $source -match
        '(?s)MonitorShell\(\)\s*\{.*?if\s*\(DesktopMode\)\s*\r?\n\s*return') (
    "Shell monitoring is no longer disarmed in desktop mode.")
# Desktop mode leaves Explorer visibly in charge; the guard, window engine, and
# shell monitor must not be rescheduled behind it, but controller input must.
Assert-True (
    $source -match
        '(?s)ApplyRuntimeTimers\(\)\s*\{.*?if\s*\(!DesktopMode\)\s*\{.*?' +
        'SetTimer\(MonitorShell,\s*ShellMonitorIntervalMs\).*?' +
        'StartTaskbarGuard\(\).*?\}\s*\r?\n\s*\r?\n\s*if\s*\(EnableControllerMouseMode') (
    "Desktop mode no longer isolates shell enforcement from controller polling.")
Assert-True (
    $source -match
        '(?s)ReturnToShellMode\(reason\s*:=\s*""\)\s*\{.*?if\s*\(SafeMode\).*?' +
        'DesktopMode\s*:=\s*false.*?AllowExplorer\s*:=\s*false.*?ApplyRuntimeTimers\(\)' -and
    $source -match
        '(?s)LaunchSteamAndReturnToShell\(\)\s*\{.*?LaunchSteamBpm\(\).*?' +
        'ReturnToShellMode\("Steam launched from SteamShell"\)') (
    "Returning to SteamShell presentation, or the launch-initiated re-arm, has regressed.")
Assert-True (
    $source -match
        '(?s)case\s+"returnShell":.*?LaunchSteamAndReturnToShell\(\)' -and
    $source -match
        '(?s)TrayReturnToShell\([^)]*\)\s*\{\s*LaunchSteamAndReturnToShell\(\)' -and
    $source -match
        '(?s)LaunchSteamAndReturnToShell\(\)\s*\{.*?' +
        'DestroyQuickMenuForSurfaceTransition\(\).*?LaunchSteamBpm\(\)' -and
    $source -notmatch 'Launch Steam and Return to SteamShell",\s*TrayLaunchSteam') (
    "Return to SteamShell no longer launches Steam or safely tears down the menu surface.")
# Killing SteamShell while Explorer legitimately owns the desktop must not
# restart Explorer or rewrite the user's shell registration.
Assert-True (
    $source -match
        '(?s)if\s*\(IntentionalExitMode\s*=\s*""\s*&&\s*!DesktopMode\s*&&\s*!SafeMode') (
    "Unexpected-exit Explorer recovery is no longer suppressed in desktop and safe modes.")
Assert-True (
    $source -match
        '(?s)ExitSteamShell\(\)\s*\{.*?if\s*\(!DesktopMode\)\s*\{.*?' +
        'ExitToDesktop\(false,\s*true\)') (
    "A full exit from shell mode must restore the desktop instead of leaving the user without a shell.")

# Desktop blackout. The backdrop must never be able to take focus, and the
# desktop windows it hides must be given back on every path that hands
# presentation to Explorer.
Assert-True (
    $source -match
        '(?s)EnsureDesktopBackdrop\(\)\s*\{.*?Gui\("-Caption \+ToolWindow -DPIScale \+E0x08000000"\).*?' +
        'BackColor\s*:=\s*"000000"') (
    "The blackout backdrop is no longer a non-activating, DPI-neutral black window.")
Assert-True (
    $source -match
        '(?s)StartDesktopBlackout\(\)\s*\{.*?if\s*\(AllowExplorer\s*\|\|\s*!EnableDesktopBlackout\).*?' +
        'FitDesktopBackdrop\(true\).*?SinkDesktopBackdrop\(\).*?HideDesktopShellWindows\(\)' -and
    $source -match
        '(?s)StopDesktopBlackout\(releaseCallback\s*:=\s*false\)\s*\{.*?' +
        'if\s*\(wasActive\)\s*\r?\n\s*ShowDesktopShellWindows\(\).*?HideDesktopBackdrop\(\)') (
    "Blackout start/stop no longer paints before hiding, or no longer restores the desktop windows first.")
# Every path that gives the desktop back to Explorer must stop the blackout,
# otherwise the user is left with a hidden Progman and no black pixels.
foreach ($blackoutRelease in @(
    'PrepareForDesktopRestore', 'ExitCleanup', 'StartSafeModeSession', 'ApplyRuntimeTimers')) {
    $releaseMatch = [regex]::Match(
        $source,
        ('(?ms)^' + $blackoutRelease + '\([^)]*\)\s*\{.*?^}\s*$'))
    Assert-True (
        $releaseMatch.Success -and
        $releaseMatch.Value -match 'StopDesktopBlackout\(') (
        "Desktop blackout is not released in $blackoutRelease.")
}
Assert-True (
    $source -match
        '(?s)ApplySafeModeOverrides\(\)\s*\{.*?EnableDesktopBlackout\s*:=\s*false') (
    "Safe Mode no longer disables the desktop blackout.")
Assert-True (
    $source -match
        '(?s)DesktopBlackoutTick\(\)\s*\{.*?GetForegroundWindow.*?DesktopBackdropHwnd.*?' +
        'SinkDesktopBackdrop\(\).*?HideDesktopShellWindows\(\)') (
    "The blackout safety tick no longer re-sinks the backdrop or re-hides the desktop.")
# The blackout must stay switchable from the controller, because a misbehaving
# backdrop is exactly the situation where no other input is reachable.
Assert-True (
    $source -match '"qBlackout",\s*"label",\s*"Black Desktop Background"' -and
    $source -match
        '(?s)case\s+"qBlackout":\s*\r?\n\s*PersistQuickMenuSetting\(\s*"Features",\s*"EnableDesktopBlackout"') (
    "The desktop blackout is no longer toggleable from the Quick Menu.")
Assert-True (
    $source -match
        'SettingsEditorSwitchControllerCategory\(settingsCategoryDirection\)') (
    "Full Settings is no longer using trigger-edge category navigation.")
Assert-True (
    $source -match
        'ExecuteControllerBinding\("RB\.Short"\)') (
    "Full Settings no longer exposes RB's configured pointer action.")
Assert-True (
    $source -match
        '(?s)SettingsEditorControllerActive\(\)\s*\{.*?' +
        'WinGetPID.*?ScriptPid.*?GetWindow.*?GW_OWNER' -and
    $source -match
        '(?s)SettingsEditorFileSelect\(.*?' +
        'SettingsEditorDialogActive\s*:=\s*true.*?' +
        'FileSelect\(.*?finally.*?' +
        'SettingsEditorDialogActive\s*:=\s*false' -and
    $source -match
        '(?s)if\s*\(SettingsEditorDialogActive\s*\|\|\s*settingsPrimaryActive\).*?' +
        'SettingsEditorHandleController.*?else\s*' +
        'SettingsEditorHandlePointer' -and
    $source -match
        '(?s)SettingsEditorHandlePointer\(.*?' +
        'MouseMove\(.*?ExecuteControllerBinding\("RB\.Short"\)') (
    "Settings automatic controller pointer no longer follows dialogs and companion windows.")
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
        '(?s)StartTaskbarGuard\(\)\s*\{.*?SetWinEventHook.*?' +
        '0x8002.*?SetTimer\(HideShellTaskbars,\s*' +
        'TaskbarGuardSafetyIntervalMs\)') (
    "Taskbar Guard is missing its show-event hook or periodic safety check.")
Assert-True (
    $source -match
        '(?s)TaskbarGuardWinEvent\([^\)]*\)\s*\{.*?' +
        'static\s+inCallback\s*:=\s*false.*?' +
        'event\s*:=\s*event\s*&\s*0xFFFFFFFF.*?finally.*?' +
        'inCallback\s*:=\s*false') (
    "Taskbar Guard's event callback is missing its x64 argument normalization or re-entrancy guard.")
Assert-True (
    $source -match
        'CallbackCreate\(\s*TaskbarGuardWinEvent,\s*"",\s*7\)' -and
    $source -notmatch
        'CallbackCreate\(\s*TaskbarGuardWinEvent,\s*"Fast"') (
    "Taskbar Guard must use a normal AutoHotkey callback thread, not Fast mode.")
Assert-True (
    $source -match
        '(?s)PrepareForDesktopRestore\(\)\s*\{.*?' +
        'DestroyQuickMenuForSurfaceTransition\(\).*?' +
        'AllowExplorer\s*:=\s*true.*?StopTaskbarGuard\(\)') (
    "Desktop restoration does not stop Taskbar Guard before rebuilding Explorer.")
Assert-True (
    $source -match
        '(?s)ExitCleanup\(ExitReason,\s*ExitCode\)\s*\{.*?' +
        'StopTaskbarGuard\(true\)') (
    "Process cleanup does not release the Taskbar Guard event callback.")
Assert-True (
    $source -match
        '(?s)WindowEngineTitleMatchesBpm\(title\)\s*\{.*?' +
        'InStr\(title,\s*expected,\s*false\)') (
    "Big Picture title matching is no longer using partial-title behavior.")
Assert-True (
    $source -match
        '(?s)WindowEngineFindBpm\(snapshot\)\s*\{.*?' +
        'item\["steam"\].*?item\["minMax"\]\s*!=\s*-1.*?' +
        '0x08000000.*?WindowEngineItemIntersectsMonitor\(item\)') (
    "The title-change Steam fallback can select an off-screen or non-activating helper window.")
Assert-True (
    $source -match
        '(?s)WindowEngineIsLegacyApplicationSurface\(item,\s*allowMinimized\s*:=\s*false\)\s*\{.*?' +
        'item\["proc"\].*?item\["owner"\].*?0x00040000.*?' +
        'WindowEngineItemIntersectsMonitor\(item\)') (
    "Legacy game-window detection is missing ownership or activation safeguards.")
Assert-True (
    $source -match
        '(?s)GetTaskSwitcherWindows\(\)\s*\{.*?' +
        'WindowEngineIsLegacyApplicationSurface\(item,\s*true\).*?' +
        'item\["minMax"\]\s*=\s*-1.*?' +
        'legacy fullscreen window') (
    "Task Switcher no longer includes safe untitled legacy game surfaces.")
Assert-True (
    $source -match
        '(?s)WindowEngineIsMinimizedLegacyGameSurface\(item\)\s*\{.*?' +
        'WindowEngineIsLegacyApplicationSurface\(item,\s*true\).*?' +
        '0x80000000.*?0x00C00000') (
    "Minimized legacy-game restoration is missing its popup/caption safeguards.")
Assert-True (
    $source -match
        '(?s)WindowEngineEvaluateGame\(snapshot.*?' +
        'WindowEngineIsMinimizedLegacyGameSurface\(item\).*?' +
        'WindowEngineIsLegacyApplicationSurface\(item\).*?' +
        'item\["title"\]\s*=\s*""\s*&&\s*!legacySurface') (
    "Game Foreground Assist no longer accepts safe untitled legacy surfaces.")
Assert-True (
    $source -match
        '(?s)WindowEngineIsApplicationBlocker\(item\)\s*\{.*?' +
        'item\["steam"\].*?item\["minMax"\]\s*=\s*-1.*?' +
        '0x08000000.*?WindowEngineItemIntersectsMonitor\(item\)') (
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
        '(?s)EnsureSteamShellElevation\(\)\s*\{.*?if\s+A_IsAdmin.*?' +
        'SteamShellElevationRestartRequested\(\).*?' +
        'BuildSteamShellElevationCommand\(\).*?RunWait\("\*RunAs\s+".*?' +
        'catch\s+as\s+err') (
    "SteamShell's guarded administrator handoff is incomplete.")
Assert-True (
    $source -match
        '(?s)ReadSteamShellElevationPreference\(\)\s*\{.*?' +
        'RunElevatedOnStartup.*?"true".*?return ToBool' -and
    $source -match
        '(?s)EnsureSteamShellElevation\(\)\s*\{.*?' +
        'ReadSteamShellElevationPreference\(\).*?' +
        'if\s*!RunElevatedOnStartup.*?return A_IsAdmin' -and
    $source -match
        '(?s)SettingsEditorAddCheckbox\(\s*category,\s*"Features",\s*' +
        '"RunElevatedOnStartup".*?"true"') (
    "The default-on administrator startup setting is missing or disconnected.")
Assert-True (
    $source -match
        '(?s)BuildSteamShellElevationCommand\(\)\s*\{.*?A_IsCompiled.*?' +
        'A_ScriptFullPath.*?A_AhkPath.*?/restart.*?' +
        'for\s+_,\s*argument\s+in\s+A_Args') (
    "The administrator handoff no longer preserves runtime mode and arguments.")
Assert-True (
    $source -match
        '(?s)SteamShellElevationRestartRequested\(\)\s*\{.*?' +
        'GetCommandLine.*?/restart') (
    "The administrator handoff no longer guards against a non-elevating RunAs loop.")
Assert-True (
    $source -match
        'HealthResult\(results,\s*A_IsAdmin\s*\?\s*"pass"\s*:\s*"warn",\s*' +
        '"Runtime privileges"') (
    "Health Check no longer reports SteamShell's runtime privilege state.")

# The recorded pre-SteamShell shell must actually be read back somewhere. It was
# written by both registration paths and read by nothing for several releases,
# so the uninstall silently replaced a custom shell with explorer.exe and then
# deleted the only record of it.
Assert-True (
    $source -match
        '(?s)ResolveSavedPreviousShell\(\)\s*\{.*?RegRead\([^)]*"PreviousShell"\).*?' +
        'ShellCommandExecutablePath') (
    "The saved PreviousShell value is no longer read back and verified.")
Assert-True (
    $source -match
        '(?s)RemoveSteamShellRegistration\([^)]*restorePreviousShell[^)]*\)\s*\{.*?' +
        'ResolveSavedPreviousShell.*?WriteAndVerifyShellValue') (
    "Uninstall no longer reinstates the shell registered before SteamShell.")
Assert-True (
    $source -match
        '(?s)RemoveSteamShellRegistration\([^)]*\)\s*\{.*?' +
        'could not be reinstated.*?PreviousShell metadata were retained.*?' +
        'return false.*?try FileDelete.*?RegDelete') (
    "A failed PreviousShell restore no longer retains recovery metadata before returning.")
Assert-True (
    $source -match
        '(?s)ShellCommandExecutablePath\(command\)\s*\{.*?' +
        'RegExMatch\(command.*?\\\.exe.*?SearchPathW') (
    "Winlogon shell commands no longer resolve unquoted paths with spaces and PATH executables.")
Assert-True (
    $source -match
        '(?s)ResolveRtssExecutablePath\(\)\s*\{.*?ProgramFiles\(x86\).*?' +
        'RivaTuner Statistics Server\\RTSS\.exe' -and
    $source -match
        '(?s)EnsureRtssRunning\(\)\s*\{\s*path\s*:=\s*ResolveRtssExecutablePath\(\)' -and
    $source -match
        '(?s)GetRtssHooksApi\(\)\s*\{.*?ResolveRtssExecutablePath\(\)') (
    "RTSS discovery is no longer centralized across launch, status, and DLL lookup paths.")
# /restore is the emergency path and must stay pinned to explorer.exe.
Assert-True (
    $source -match
        '\(mode\s*=\s*"restore"\)\s*\r?\n\s*RemoveSteamShellRegistration\(true,\s*false\)' -and
    $source -match
        '\(mode\s*=\s*"uninstall"\)\s*\r?\n\s*RemoveSteamShellRegistration\(true,\s*true\)') (
    "The /restore and /uninstall shell-restoration split has regressed.")

# Win+Alt+B is a toggle, so it can only ever serve the toggle entry point. It
# must not be reachable from an explicit On or Off request, where the requested
# state would be silently discarded.
Assert-True (
    $source -match '(?s)RequestHdrToggleFallback\(\)\s*\{[^}]*#!b' -and
    $source -match
        '(?s)ToggleQuickMenuHdrState\(\)\s*\{.*?RequestHdrToggleFallback' -and
    $source -notmatch '(?s)SetQuickMenuHdrState\([^)]*allowToggleFallback') (
    "The HDR toggle fallback is reachable from an explicit On/Off request again.")

# Every INI default must equal its own parse-failure fallback. When they differ,
# a malformed value silently produces the opposite of the documented default.
$defaultFallbackMismatches = @(
    [regex]::Matches(
        $source,
        'To(?:Int|Float|Bool)\(\s*IniRead\w*\(\s*"[^"]*"\s*,\s*"[^"]*"\s*,\s*"([^"]*)"\s*\)\s*,\s*([^),]+)\)') |
        Where-Object {
            $declared = $_.Groups[1].Value.Trim()
            $fallback = $_.Groups[2].Value.Trim()
            # Only literal-versus-literal disagreement is a defect. A named
            # constant as the fallback is a deliberate choice, not a typo.
            if ($fallback -notmatch '^(?:true|false|-?\d+(?:\.\d+)?)$') {
                $false
            } elseif ($declared -match '^-?\d+(?:\.\d+)?$' -and
                      $fallback -match '^-?\d+(?:\.\d+)?$') {
                [double]$declared -ne [double]$fallback
            } else {
                $declared -ne $fallback
            }
        } |
        ForEach-Object { $_.Value }
)
Assert-True ($defaultFallbackMismatches.Count -eq 0) (
    "INI defaults disagree with their parse-failure fallbacks: " +
    ($defaultFallbackMismatches -join "; "))

# The log must not grow without bound, and the rotation check must not cost a
# filesystem call on every line written.
Assert-True (
    $source -match
        '(?s)RotateLogIfNeeded\(\s*pendingBytes[^)]*\)\s*\{.*?static estimatedSize.*?FileGetSize' -and
    $source -match 'RotateLogIfNeeded\(StrLen\(line\)') (
    "Log rotation is missing or measures the file on every written line.")

# Cross-tree parity. Skipped when the sibling tree is absent, which is the normal
# case inside a frozen releases/ snapshot: there is nothing to compare against.
$sharedParityScript = Join-Path (Split-Path -Parent $projectRoot) "Validate-SharedParity.ps1"
$companionSource = Join-Path (Split-Path -Parent $projectRoot) "SteamShell-XFE\SteamShell-XFE.ahk"
if (Test-Path $companionSource) {
    Assert-True (Test-Path $sharedParityScript) (
        "The sibling SteamShell-XFE tree exists, but Validate-SharedParity.ps1 is missing.")
    & $sharedParityScript -Quiet:$Quiet
} elseif (-not $Quiet) {
    Write-Host "Shared parity: skipped (the SteamShell-XFE tree is not beside this one)."
}

if (-not $Quiet) {
    $callbackCount = @($callbackReferences | Sort-Object -Unique).Count
    Write-Host (
        "Static validation passed: {0} functions, {1} settings keys, {2} Quick Menu rows, {3} named callbacks." -f
        $functionNames.Count,
        $embeddedSchema.Count,
        $quickMenuIds.Count,
        $callbackCount)
}
