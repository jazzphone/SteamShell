param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Assert-True, Get-EffectiveSource and the structural scans live in
# Validate-Common.ps1, beside this script. Only mechanism is shared: the product
# rules below are this validator's alone, because several of them are the exact
# inverse of SteamShell-XFE's.
. (Join-Path $projectRoot "Validate-Common.ps1")

$sourcePath = Join-Path $projectRoot "SteamShell.ahk"
$helperSourcePath = Join-Path $projectRoot "SteamShell-Helper.ahk"
$samplePath = Join-Path $projectRoot "SteamShellSettings_SAMPLE.ini"
$iconPath = Join-Path $projectRoot "assets\SteamShell.ico"
$buildLauncherPath = Join-Path $projectRoot "Build-SteamShell.cmd"
$buildScriptPath = Join-Path $projectRoot "Build-SteamShell.ps1"

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
Assert-True (Test-Path $helperSourcePath) "SteamShell-Helper.ahk is missing."
Assert-True (Test-Path $samplePath) "SteamShellSettings_SAMPLE.ini is missing."
Assert-True (Test-Path $iconPath) "The standalone SteamShell icon is missing."
Assert-True (Test-Path $buildLauncherPath) "The double-clickable build launcher is missing."
Assert-True (Test-Path $buildScriptPath) "Build-SteamShell.ps1 is missing."

$source = Get-EffectiveSource -Path $sourcePath
# The tree file WITHOUT its #Includes resolved -- see the XFE validator for why a
# -notmatch has to read this rather than $source.
$rawSource = Get-SourceText $sourcePath
# Raw, NOT include-resolved. The point of several assertions below is what the
# helper file itself does and does not contain -- resolving its #Include would
# make every function in SteamShell-Common.ahk look like the helper's own, which
# is precisely the duplication those assertions exist to forbid.
$helperSource = Get-SourceText $helperSourcePath
# ...and the same file WITH its #Include resolved, for the handful of assertions
# that ask whether a BEHAVIOUR exists rather than where it is written. Keeping
# both is the point: a -notmatch forbidding duplication has to read the raw file,
# and a -match on a function that has since moved into SteamShell-Common.ahk has
# to read this one, or consolidating a function reads as deleting it.
$helperEffective = Get-EffectiveSource -Path $helperSourcePath
$commonSourcePath = Join-Path $projectRoot "SteamShell-Common.ahk"
Assert-True (Test-Path $commonSourcePath) "SteamShell-Common.ahk is missing."
$commonSource = Get-SourceText $commonSourcePath
$sample = Get-SourceText $samplePath

Assert-True (
    $source -match '@Ahk2Exe-SetVersion 2\.0\.1\.0' -and
    $source -match 'SteamShellVersion\s*:=\s*"2\.0\.1"' -and
    $helperSource -match '@Ahk2Exe-SetVersion 2\.0\.1\.1' -and
    $helperSource -match 'HelperVersion\s*:=\s*"2\.0\.1"' -and
    $source -match 'ElevatedHelperExpectedVersion\s*:=\s*"2\.0\.1\.1"') (
    "SteamShell 2.0.1 main/helper version metadata is inconsistent.")
$buildScript = Get-SourceText $buildScriptPath

# The helper version is DERIVED from the helper source, not written down a fourth
# time.
#
# It used to be a bare '1\.9\.9\.3' anywhere in the build script, which is two
# faults in one line: it does not say WHICH number it is checking, and it does
# not tie that number to anything. Bumping the helper to 1.9.9.4 updated the
# source, the expected-version global and the build's own gate, and left this
# clause behind -- so a correct, consistent tree failed the build with a message
# about embedding.
#
# Reading the version out of the helper's own @Ahk2Exe-SetVersion and then
# requiring the build to gate on exactly that string removes the copy entirely.
# The next bump cannot desynchronise it, because there is nothing left to forget.
$helperVersionMatch = [regex]::Match(
    $helperSource, '@Ahk2Exe-SetVersion (\d+\.\d+\.\d+\.\d+)')
Assert-True ($helperVersionMatch.Success) (
    "SteamShell-Helper.ahk does not declare a file version.")
$helperVersionPattern = [regex]::Escape($helperVersionMatch.Groups[1].Value)

# The SAME treatment for the other two binaries, and it should have been applied
# at the same time as the helper's.
#
# The comment above says "the next bump cannot desynchronise it, because there is
# nothing left to forget". That was true of the helper and false of everything
# else: one line below it sat a literal 1.9.9.0 for the main executable, and two
# more pairs further down for the companion and the helper's expected version.
# The 2.0.0 bump failed on exactly the fault this passage describes being fixed --
# a correct, consistent tree rejected with a message about embedding.
#
# RAW sources, not the #Include-resolved one, so the directive read is the file's
# own. And escaped, because these land inside -match patterns.
$mainVersionMatch = [regex]::Match(
    $rawSource, '@Ahk2Exe-SetVersion (\d+\.\d+\.\d+\.\d+)')
Assert-True ($mainVersionMatch.Success) (
    "SteamShell.ahk does not declare a file version.")
$mainVersionPattern = [regex]::Escape($mainVersionMatch.Groups[1].Value)

$xfeSourceForVersion = Get-SourceText (
    Join-Path $projectRoot "SteamShell-XFE.ahk")
$xfeVersionMatch = [regex]::Match(
    $xfeSourceForVersion, '@Ahk2Exe-SetVersion (\d+\.\d+\.\d+\.\d+)')
Assert-True ($xfeVersionMatch.Success) (
    "SteamShell-XFE.ahk does not declare a file version.")
$xfeVersionPattern = [regex]::Escape($xfeVersionMatch.Groups[1].Value)
Assert-True (
    $buildScript -match 'SteamShell-Helper\.ahk' -and
    $buildScript -match
        '(?s)helperEmbedDirectory.*?"build".*?' +
        'helperOutputPath.*?"SteamShell-Helper\.exe"' -and
    $buildScript -match "\`$helperVersion -ne `"$helperVersionPattern`"" -and
    $buildScript -match "SteamShell version verification failed.*?$mainVersionPattern") (
    "The build no longer compiles and version-checks the helper before embedding SteamShell.exe.")

Assert-AhkStructure -Text $source -Label "SteamShell.ahk"
$functionMatches = [regex]::Matches(
    $source,
    '(?m)^([A-Za-z_][A-Za-z0-9_]*)\([^\r\n{}]*\)\s*\{')

Assert-AhkStructure -Text $helperSource -Label "SteamShell-Helper.ahk"

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
    $embeddedSchema.Contains("Features`0EnableElevatedInputHelper") -and
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
    $embeddedSchema.Contains("QuickMenu`0AccentColorCustom") -and
    $embeddedSchema.Contains("Setup`0SetupState") -and
    $embeddedSchema.Contains("Setup`0InstallationMode") -and
    $embeddedSchema.Contains("Setup`0InstallDirectory") -and
    $embeddedSchema.Contains("Setup`0DataDirectory")) (
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
        '(?s)sourceVersion\s*<\s*17.*?SetupState.*?Complete' -and
    $defaultMatch.Groups[1].Value -match '(?m)^SetupState=Pending' -and
    $sample -match '(?m)^SetupState=Pending') (
    "The schema-17 first-run setup state or established-user migration is missing.")
Assert-True (
    $source -match
        '(?s)SettingsEditorAddMappedChoice\(\s*category,\s*' +
        '"GameForegroundAssist",\s*"GameMinScoreToActivate".*?' +
        '"Responsive \(55\)".*?"Balanced \(60\)".*?"Conservative \(70\)"') (
    "Full Settings foreground-sensitivity presets are incomplete.")
# Counted in the shared page table, which is where the row is defined now, and
# scoped to a SETTINGS row: the bare section/key pair also appears in
# QuickMenuToggleTable, which describes the same setting for the Quick Menu.
# Two rows for one switch is the failure this catches; one definition makes it
# hard to express, and the count keeps it that way.
$windowManagementEditorFields = [regex]::Matches(
    $source,
    '(?s)"type", "checkbox",\s*\r?\n\s*' +
    '"section", "Features", "key", "EnableWindowManagement"')
Assert-True ($windowManagementEditorFields.Count -eq 1) (
    "Full Settings must expose exactly one Window Management toggle.")
Assert-True (
    $source -match
        '(?s)"key", "MinWidthPercent",.*?"Maximize width threshold \(%\)".*?' +
        '"fieldType", "percent", "min", 5, "max", 100') (
    "The maximize-width percentage control is not configured correctly.")
Assert-True (
    $source -match
        '(?s)if\s*\(fieldType\s*=\s*"float"\).*?' +
        'value\s*:=\s*FormatSettingsFloat\(number\)') (
    "Float settings are not normalized before serialization.")

# Every persistent field exposed by the full settings editor must have a
# corresponding embedded/sample INI key. This catches renamed keys that would
# otherwise appear to save successfully and then silently reload a default.
# Both sources. Most rows are defined in the shared page table now, so matching
# only the literal builder calls dropped this from 88 bindings to 7 -- it would
# have kept passing while checking almost nothing, which is the failure mode this
# whole file exists to avoid.
#
# Rows carrying "standalone" or "both" are the ones this product draws; an "xfe"
# row is not a binding here and must not be counted as one.
$editorFieldMatches = @([regex]::Matches(
    $source,
    '(?s)SettingsEditorAdd(?:Checkbox|TextField|NumberField|Choice|MappedChoice|PathField|ShortcutField|ExeListField)\(\s*category,\s*"([^"]+)"\s*,\s*"([^"]+)"'))
$editorFieldMatches += @([regex]::Matches(
    $source,
    '(?s)"product", "(?:both|standalone)", "type", "(?!note|section)\w+",\s*\r?\n\s*' +
    '"section", "([^"]+)", "key", "([^"]+)"'))
Assert-True ($editorFieldMatches.Count -ge 80) (
    "The Settings binding scan found too few bindings to be trustworthy; it " +
    "reads the builder calls and the shared page table, and one of them stopped " +
    "matching.")
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
    '(?s)ShowSettingsEditor\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
    'SettingsEditorCategories\s*:=\s*\[(.*?)\]')
Assert-True $settingsCategoryListMatch.Success (
    "The Full Settings category list could not be extracted.")
$settingsCategoryNames = @(
    [regex]::Matches($settingsCategoryListMatch.Groups[1].Value, '"([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value }
)
# The declared list and the constructed panels must be the SAME SET.
#
# This asserted a count of eight, which is a number somebody has to remember to
# change and which says nothing about whether the pages are right. It was wrong
# within a day of a page being added, and it would have gone on passing if a
# page had been added to the list and never built.
#
# Both directions are checked now, because both have failed here: a panel with
# no list entry is a page nobody can select -- the Steam rows shipped invisible
# that way -- and a list entry with no panel is an empty page. Neither is
# expressible as a count.
$panelCategories = @(
    [regex]::Matches($source, '(?m)^[ \t]*category := "([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$declaredCategories = @($settingsCategoryNames | Sort-Object -Unique)
Assert-True (
    $declaredCategories.Count -gt 0 -and
    $settingsCategoryNames.Count -eq $declaredCategories.Count) (
    "Full Settings declares no categories, or a duplicate one: " +
    ($settingsCategoryNames -join ", "))
$categoryDifference = @(
    Compare-Object $declaredCategories $panelCategories -ErrorAction SilentlyContinue)
Assert-True ($categoryDifference.Count -eq 0) (
    "The Full Settings category list and its constructed panels disagree. " +
    "Declared: " + ($declaredCategories -join ", ") + ". Built: " +
    ($panelCategories -join ", ") + ".")
# A percent field is STORED as a fraction and SHOWN as a percentage, and both
# halves of that have to exist.
#
# Only the save half did. SettingsEditorValidateField divided by 100 and nothing
# multiplied back, so opening Settings put 0.3 into a field whose own validator
# demands 5 to 100 -- the window blocked its own Save, and typing 30 fixed
# nothing because it stored 0.3 again for the next open. A conversion with one
# direction implemented is worse than none: none would merely have been wrong,
# this was a loop the user could not leave.
Assert-True (
    $source -match
        '(?s)SettingsEditorPopulateField\(field\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'field\["type"\] = "percent"(?:(?!\n\})[\s\S])*?\* 100' -and
    $source -match
        '(?s)fieldType = "percent"(?:(?!\n\})[\s\S])*?FormatSettingsFloat\(number / 100\)') (
    "A percent settings field must convert in BOTH directions: multiplied by " +
    "100 when the control is populated, divided by 100 when it is saved.")
Assert-True (
    $source -match
        '(?s)SharedAuditSettingsLayout\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?overlaps\s*:=' -and
    $source -match
        '(?s)ShowSettingsEditor\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
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
    "ProductHealthResults",
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
    "AdministratorSetupRequestMarkerPath",
    "WriteAdministratorSetupRequestMarker",
    "ConsumeAdministratorSetupRequestMarker",
    "PromptForAdministratorSetupAndExit",
    "OtherSteamShellSetupProcessExists",
    "ElevatedSetupMatchesInteractiveDesktop",
    "CloseExistingSteamShellInstancesForElevatedSetup",
    "WaitForReplaceableFile",
    "StopRunningSteamShellExecutable",
    "StopResidentSteamShellExecutablesForRemoval",
    "AbortAdministratorSetup",
    "RtssFrameCapModeIsKnown",
    "RtssFrameCapModeForFps",
    "PersistRtssFrameCapSelection",
    "PersistRtssFrameCapStateNow",
    "RestoreRtssFrameLimitTick",
    "SteamShellProductIsXfe",
    "NormalizeSteamShellProduct",
    "ResolveInstalledSteamShellProduct",
    "ExtractEmbeddedXfe",
    "RegisterXfeLogonTask",
    "RemoveXfeLogonTask",
    "DeploySteamShellXfe",
    "RemoveSteamShellXfeInstallation",
    "RemoveSteamShellInstallationForProduct",
    "MarkSteamShellSetupCompleteForXfe",
    "SteamShellDialogOwnerHwnd",
    "SteamShellMsgBox",
    "SetupAssistantCloseRequested",
    "SetupAssistantSelectedProduct",
    "SetupAssistantRefreshProductMode",
    "SetupAssistantXfeStandardDirectory",
    "SteamShellXfeLogonTaskExists",
    "SteamShellIsRegisteredWindowsShell",
    "DetectExistingSteamShellInstallation",
    "SetupAssistantPreselectExistingInstallation",
    "SetupAssistantUninstall",
    "ProductRemovalSelect",
    "ChooseSteamShellProductToRemove",
    "SteamShellRemovableDirectoryKind",
    "SteamShellRemovalPathIsSafe",
    "BuildSteamShellRemovalPlan",
    "ExecuteSteamShellRemovalPlan",
    "SteamShellDirectoryContainsOurArtifacts",
    "SteamShellRegisteredShellDirectory",
    "SteamShellXfeLogonTaskDirectory",
    "GetElevatedHelperPath",
    "ExtractEmbeddedElevatedHelper",
    "RegisterElevatedHelperTask",
    "StartElevatedHelperTask",
    "RemoveElevatedHelperTask",
    "StartElevatedInputHelper",
    "StopElevatedHelper",
    "SyncElevatedInputHelperWithSettings",
    "ElevatedHelperOwnsForeground",
    "ElevatedHelperIsVerified",
    "SteamShellPathIsAdminOnlyWritable",
    "ElevatedHelperLocationIsProtected",
    "HardenElevatedHelperDirectory",
    "ControllerBindingIsNormalIntegrityOnly",
    "ControllerHandleElevatedForeground",
    "SetElevatedGeometryRuntimeEnabled",
    "ResolveRtssExecutablePath",
    "ShellCommandExecutablePath",
    "ResolveSavedPreviousShell",
    "SetupAssistantRequired",
    "StartFirstRunSetupSession",
    "SetupAssistantDetectInstalledApplications",
    "SetupAssistantMsgBox",
    "SetupAssistantLaunchExternal",
    "SetupAssistantVerticalScroll",
    "SetupAssistantMouseWheel",
    "GetSafeTargetWindowDpi",
    "SetupAssistantConfigureAutoLogon",
    "ConfigureWindowsAutoLogon",
    "DisableWindowsAutoLogon",
    "StoreWindowsAutoLogonSecret",
    "GetAbsoluteSteamShellPath",
    "SteamShellPathUsesLinkOrJunction",
    "CleanupTemporaryUpgradeSidecar",
    "ShowSetupCompletionDialog",
    "RequestSteamShellRestart",
    "DeploySteamShell",
    "GrantSteamShellDataAccess",
    "SettingsEditorSetRedraw",
    "SettingsEditorRefreshDependencies",
    "WindowEngineTick",
    "WindowEngineGeometryHandledByHelper",
    "GetProcessCpuSample"
)
$functionNames = @{}
foreach ($match in $functionMatches) {
    $functionNames[$match.Groups[1].Value.ToLowerInvariant()] = $true
}

# The duplicate-definition and function-name-shadowing scans ran here until they
# moved into Assert-AhkStructure, which is called above and again for the helper
# below. Both faults are true of any AutoHotkey source rather than of this
# product, which is what made them safe to share.

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
        '(?s)RegisterCurrentSteamShellAsShell\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?A_IsCompiled.*?A_ScriptFullPath.*?PreviousShell.*?WriteAndVerifyShellValue.*?RegisteredPath' -and
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
        '(?s)GetWindowsLastInputTick\(\)\s*\{(?:(?!\n\})[\s\S])*?GetLastInputInfo' -and
    $source -match
        '(?s)GetWindowsInputIdleMs\(\)\s*\{(?:(?!\n\})[\s\S])*?GetWindowsLastInputTick.*?GetTickCount') (
    "Health diagnostics can no longer inspect Windows' last-input clock.")
Assert-True (
    $source -match
        '(?sm)^ObserveForegroundForMouseParking\(\)\s*\{(?:(?!\n\})[\s\S])*?ScheduleMouseParkAfterFocus' -and
    $source -match
        '(?sm)^WindowEngineTick\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?ObserveForegroundForMouseParking\(\)' -and
    $source -match
        '(?sm)^CommitPendingMousePark\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?ParkMouseRightEdge') (
    "Foreground-transition mouse parking is no longer connected to the window engine.")
Assert-True (
    $source -match '(?m)^CoordMode\s+"Mouse",\s*"Screen"\s*$' -and
    $parkFunctionMatch.Value -match 'MouseParkEdge\s*=\s*"left"') (
    "Screen-coordinate or selectable-edge cursor parking has regressed.")
Assert-True (
    $source -match
        '(?sm)^QuickMenuBuildGui\(\)\s*\{(?:(?!\n\})[\s\S])*?if\s+!QuickMenuVisible(?:(?!\n\})[\s\S])*?' +
        'QuickMenuRowsCtrl\s*:=\s*QuickMenuGui\.AddText(?:(?!\n\})[\s\S])*?QuickMenuSetRedraw\(false\)(?:(?!\n\})[\s\S])*?' +
        'PositionQuickMenuOnTarget(?:(?!\n\})[\s\S])*?RevealWindow(?:(?!\n\})[\s\S])*?' +
        'ApplyRoundedCorners(?:(?!\n\})[\s\S])*?QuickMenuSetRedraw\(true\)' -and
    $source -notmatch
        '(?sm)^QuickMenuBuildGui\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '(?:QuickMenuGui\.Destroy\(\)|ApplyModernWindowStyle\()') (
    "The open Quick Menu is no longer borderless or repaint-in-place across page changes.")

# The rows are one painted surface, not a pool of Static controls. A Win32
# static cannot draw a rounded corner, an outline or a glow, which is why the
# pool was replaced rather than restyled.
Assert-True (
    $source -match '(?sm)^QuickMenuRefresh\(\)\s*\{(?:(?!\n\})[\s\S])*?QuickMenuPaintRows\(\)' -and
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
#
# Accepts the divisor inline or via a local, because the local exists to be
# guarded: every other input to the painter already refuses a degenerate value
# -- the client rect, the row count, the bitmap -- and QuickMenuWidth() was the
# one that could take the whole page out with a divide error instead. Pinning
# the exact expression made adding that guard look like a regression, which is
# the failure this file has had before: an assertion that describes today's
# spelling rather than the invariant will one day fail the fix for a real bug.
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
        '(?s)GetDefaultQuickMenuOrder\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
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
        'QuickMenuGoToPage\("LAYOUT"\)' -and
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
        '(?sm)^SettingsEditorControllerActive\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SettingsEditorDialogActive(?:(?!\n\})[\s\S])*?ScriptPid' -and
    $source -match
        '(?s)if\s*\(settingsControllerActive\).*?SystemCursor\("Show"\).*?' +
        'SettingsEditorHandlePointer' -and
    $source -match
        '(?s)ShowControllerMappingWindow\(\*\).*?' +
        'SetTimer\(PollController,\s*ControllerPollIntervalMs\)') (
    "SteamShell settings/editor windows no longer receive automatic controller mouse mode.")
# A menu-selection button can still be physically down when the menu is
# destroyed, so the baseline path has to discard every hold tracker before its
# release is seen.
#
# This used to read the reset inline as 'downTick[def[1]] := 0', which stopped
# matching the moment those seven hand-copied blocks became one
# ResetControllerHoldState call -- and it was one of the unbounded '(?s).*?'
# patterns, so it had been scanning the whole file from the branch rather than
# the branch itself. Bounded to the branch now, and it names the call, which is
# the thing that actually has to be there.
Assert-True (
    $source -match
        '(?s)HideQuickMenu\([^)]*\).*?ControllerNeedsFreshBaseline\s*:=\s*true' -and
    $source -match
        '(?m)^\s*if ControllerNeedsFreshBaseline \{\s*\r?\n' +
        '\s*ResetControllerHoldState\(\s*\r?\n' +
        '\s*&prevViewDown, downTick, longFired, prevTrigDown, btnDefs,\s*\r?\n' +
        '\s*&viewWasDown\)\s*\r?\n' +
        '\s*ControllerNeedsFreshBaseline := false\s*\r?\n\s*return\s*\r?\n\s*\}') (
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
        # Bounded to the function body. Unanchored, this matched the CALL site in
        # QuickMenuAdjustSelected and then ran on into the definition, which is
        # how it kept passing unchanged when the signature gained "wrap".
        '(?sm)^CycleRtssFrameCap\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'entries\.Push\("configured"\)(?:(?!\n\})[\s\S])*?' +
        'SetRtssGlobalFrameLimit\(customFps\)(?:(?!\n\})[\s\S])*?' +
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
        '(?s)SendSteamOverlayChord\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
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
        '(?sm)^SelectTaskSwitcherWindow\(hwnd,\s*lockFocus\s*:=\s*false\)(?:(?!\n\})[\s\S])*?' +
        'if\s*!lockFocus\s*(?:(?!\n\})[\s\S])*?ReleasePinnedForeground\(false\)(?:(?!\n\})[\s\S])*?' +
        'if\s*lockFocus\s*\{(?:(?!\n\})[\s\S])*?PinnedForegroundHwnd\s*:=\s*hwnd' -and
    $source -match
        '(?s)if\s*\(pressed\s*&\s*0x8000\).*?' +
        'SelectTaskSwitcherWindow\(lockHwnd,\s*true\)' -and
    $source -match
        'A switch\s+.*?Y switch \+ lock.*?Hold X force close') (
    "Task Switcher must use A for one-shot activation and Y for activation with focus lock.")
Assert-True (
    $source -match
        '(?sm)^ShowQuickMenu\(\*?\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ForceForegroundWindow\(QuickMenuGui\.Hwnd\)(?:(?!\n\})[\s\S])*?' +
        'SetTimer\(QuickMenuEnsureForeground,\s*-75\)' -and
    $source -match
        '(?sm)^ForceForegroundWindow\(hwnd\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'AttachThreadInput(?:(?!\n\})[\s\S])*?SetForegroundWindow(?:(?!\n\})[\s\S])*?AttachThreadInput') (
    "Quick Menu no longer guarantees foreground ownership over Steam.")
Assert-True (
    $source -match
        '(?s)\+MaxSize980x660.*?windowDpi\s*:=\s*Max\(96,\s*A_ScreenDPI\).*?' +
        'ClampInt\(availableLogicalHeight,\s*450,\s*660\)' -and
    # The Advanced actions go through the shared row builder, which DERIVES its
    # column positions and width from SettingsLayout. This used to pin the
    # literals 255, 610 and 335 -- the hand-typed grid those buttons carried --
    # which described one page's numbers rather than the property that matters,
    # and would have gone on passing while every other button row on every other
    # page drifted to a different width. Two columns because the labels are long.
    $source -match
        '(?s)SettingsAddButtonRow\(SettingsGui, category, \[' +
        '(?:(?!\]\], &)[\s\S])*?Permanently Restore Explorer' +
        '(?:(?!\]\], &)[\s\S])*?\]\], &actionY, 2\)' -and
    $source -notmatch 'actionWidth\s*:=\s*335') (
    "Full Settings is no longer work-area bounded, or its Advanced actions no " +
    "longer use the shared grid-derived button row.")
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
        '(?sm)^QuickMenuKeyboardActive\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'QuickMenuVisible(?:(?!\n\})[\s\S])*?WinActive\("ahk_id "\s*QuickMenuGui\.Hwnd\)' -and
    $source -match
        '(?sm)^RegisterQuickMenuKeys\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'HotIf\s+QuickMenuKeyboardActive(?:(?!\n\})[\s\S])*?' +
        'Hotkey\("Up"(?:(?!\n\})[\s\S])*?QuickMenuMoveSelection\(-1\)(?:(?!\n\})[\s\S])*?' +
        'Hotkey\("Down"(?:(?!\n\})[\s\S])*?QuickMenuMoveSelection\(1\)(?:(?!\n\})[\s\S])*?' +
        'Hotkey\("Left"(?:(?!\n\})[\s\S])*?QuickMenuAdjustSelected\(-1\)(?:(?!\n\})[\s\S])*?' +
        'Hotkey\("Right"(?:(?!\n\})[\s\S])*?QuickMenuAdjustSelected\(1\)(?:(?!\n\})[\s\S])*?' +
        'Hotkey\("Enter"(?:(?!\n\})[\s\S])*?QuickMenuActivateSelected(?:(?!\n\})[\s\S])*?' +
        'Hotkey\("Space"(?:(?!\n\})[\s\S])*?QuickMenuActivateSelected(?:(?!\n\})[\s\S])*?' +
        'Hotkey\("Backspace"(?:(?!\n\})[\s\S])*?QuickMenuGoBack(?:(?!\n\})[\s\S])*?' +
        'Hotkey\("Delete"(?:(?!\n\})[\s\S])*?QuickMenuCloseSelected(?:(?!\n\})[\s\S])*?' +
        'Hotkey\("Home"(?:(?!\n\})[\s\S])*?QuickMenuSelectFirst(?:(?!\n\})[\s\S])*?' +
        'Hotkey\("End"(?:(?!\n\})[\s\S])*?QuickMenuSelectLast') (
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
        '(?sm)^GetRtssHooksApi\(\)\s*\{(?:(?!\n\})[\s\S])*?RTSSHooks64\.dll(?:(?!\n\})[\s\S])*?' +
        'GetFlags(?:(?!\n\})[\s\S])*?SetFlags' -and
    $source -match
        '(?sm)^GetRtssFrameLimit\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?FramerateLimit' -and
    $source -match
        '(?sm)^ToggleRtssOverlay\(\)\s*\{(?:(?!\n\})[\s\S])*?GetRtssGlobalState') (
    "Live RTSS state/control or its profile frame-limit query is incomplete.")
Assert-True (
    $source -match
        '(?sm)^GetPrimaryDisplayScale\(\)\s*\{(?:(?!\n\})[\s\S])*?GET_DPI_SCALE' -and
    $source -match
        '(?sm)^ApplyDisplaySelection\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ApplyPrimaryDisplayMode(?:(?!\n\})[\s\S])*?ApplyPrimaryDisplayScale(?:(?!\n\})[\s\S])*?' +
        'DisplayChangeSafetyTick' -and
    $source -match
        '(?sm)^GetPrimaryHdrState\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO' -and
    $source -match
        '(?sm)^ToggleQuickMenuHdrState\(\)\s*\{(?:(?!\n\})[\s\S])*?SetQuickMenuHdrState') (
    "Windows Scale or live HDR parity has regressed.")
# The RTSS shortcut fallback asks three questions in one order, in one place.
#
# It used to be written out four times per program, and one of the four had
# drifted: ToggleRtssOverlay ran EnsureRtssRunning BEFORE checking the shortcut,
# so a user with no OverlayToggleShortcut got RTSS launched for them and was then
# told they could not use it. The ordering is the assertion.
#
# settingName is required, because "configure the RTSS shortcut" does not say
# which of the six it means.
# $rawSource for the DEFINITION, $source for the CALLERS and for the ordering
# rule, and the difference matters.
#
# SendRtssShortcut USED to end in a per-tree notification, which is why it lived
# in each tree and this was a $rawSource question. SharedNotify removed that
# reason -- the two copies differed only in which notify name they called and how
# the messages were worded -- so the function moved into SteamShell-Shared.ahk and
# this pin follows it to $source. Its callers were already a $source question:
# ToggleRtssOverlay and ToggleRtssFrameLimiter moved into
# SteamShell-Shared.ahk once they were byte-identical, taking two of the five
# call sites with them. Counting on $rawSource dropped to three and failed a
# rule nothing had actually broken.
#
# The last clause is the one to watch. On $rawSource it had become VACUOUS --
# ToggleRtssOverlay is no longer defined there, so a pattern anchored on its
# definition could never match and the assertion could never fail. It is the
# rule that exists because that function once ran EnsureRtssRunning before
# checking the shortcut, launching RTSS for a user who had configured nothing.
# On $source it can fail again, which is the entire point of it.
Assert-True (
    $source -match
        '(?sm)^SendRtssShortcut\(shortcut, description, settingName\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?EnableRTSSIntegration' +
        '(?:(?!\n\})[\s\S])*?shortcut = ""' +
        '(?:(?!\n\})[\s\S])*?settingName' +
        '(?:(?!\n\})[\s\S])*?EnsureRtssRunning\(\)' +
        '(?:(?!\n\})[\s\S])*?SendChordSafe\(shortcut\)' -and
    ([regex]::Matches($source, 'SendRtssShortcut\(').Count -ge 5) -and
    $source -notmatch
        '(?sm)^ToggleRtssOverlay\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'EnsureRtssRunning\(\)') (
    "The RTSS shortcut fallback must run integration, shortcut, then EnsureRtssRunning, from one helper.")
# Selecting a state RTSS is already in must SAY so. Doing nothing silently is
# indistinguishable from being broken on a couch UI with no keyboard.
#
# Reads $source, not $rawSource. Both functions now live in
# SteamShell-Shared.ahk -- they differed only by ShowNotification against
# SetStatus, and both of those were already one-line aliases for SharedNotify.
# $rawSource exists so a -notmatch can be scoped to the tree; using it for a
# -match asserted something the rule never claimed, that the behaviour lives in
# this file rather than that it exists at all.
Assert-True (
    $source -match
        '(?sm)^SetRtssOverlayState\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'is already " \((?:showOverlay|enabled) \? "on" : "off"\)' -and
    $source -match
        '(?sm)^SetRtssFrameLimiterState\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'is already " \((?:enableLimiter|enabled) \? "on" : "off"\)') (
    "Setting RTSS overlay or limiter to the state it already holds must report it.")

# KEEP must be answered before anything is re-derived, and without a condition.
# Gating the confirm on the live state still matching the selection is what made
# the row refuse presses intermittently: the enumerated mode list and
# ENUM_CURRENT_SETTINGS disagree by 1 Hz on 59.94 modes, and QueryDisplayConfig
# can return nothing while the topology settles after the change being confirmed.
# Body-bounded, and mutation-tested as falsifiable: re-introducing the guard, the
# old refusal message, or a lookup ahead of the pending check all fail this.
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
    $source -match
        '(?sm)^GetPrimaryDisplayModes\(\)\s*\{(?:(?!\n\})[\s\S])*?Loop\s*\{(?:(?!\n\})[\s\S])*?' +
        'EnumDisplaySettingsW(?:(?!\n\})[\s\S])*?if\s*\(!ok\)\s*\r?\n\s*break' -and
    $source -notmatch
        '(?sm)^GetPrimaryDisplayModes\(\)\s*\{(?:(?!\n\})[\s\S])*?Loop\s+512') (
    "Display mode enumeration must continue until Windows reports the true end of the driver list.")
Assert-True (
    $source -match
        # The filename moved into ProductIdentity so the icon lifecycle has no
        # per-tree copy; ApplyTrayIconImage reads it from there.
        '(?sm)^ProductIdentity\(\)\s*\{(?:(?!\n\})[\s\S])*?"icon", "SteamShell\.ico"' -and
    $source -match
        '(?sm)^ApplyTrayIconImage\(\)\s*\{(?:(?!\n\})[\s\S])*?ProductIdentity\(\)\["icon"\]' -and
    $source -match
        '(?sm)^InitializeTrayMenu\(\)\s*\{(?:(?!\n\})[\s\S])*?ApplyTrayIconImage\(\)(?:(?!\n\})[\s\S])*?' +
        'BuildProductTrayMenu\(\)(?:(?!\n\})[\s\S])*?RegisterTaskbarCreatedListener\(\)') (
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
        '(?sm)^PollController\(\)\s*\{(?:(?!\n\})[\s\S])*?global\s+MouseHidden(?:(?!\n\})[\s\S])*?static\s+state' -and
    $source -match
        '(?s)if\s*\(autoMouse\s*&&\s*MouseHidden\).*?MouseHidden\s*:=\s*false') (
    "PollController no longer declares MouseHidden global for automatic mouse mode.")
# The controller-as-mouse arithmetic is defined ONCE, in SteamShell-Common.ahk.
#
# The three programs read three different input sources -- XInput, RawInput
# through learned profiles, and XInput from a High-integrity token -- and that is
# why they are three programs. What they did with the result was byte-equivalent
# and written out FIVE times: once per program, plus a fourth and fifth copy on
# the Settings pointer surfaces of the two trees.
#
# The -notmatch is the real assertion. The constant is what a re-implementation
# would have to contain, so forbidding it outside the shared file is what stops
# a sixth copy appearing.
#
# The first half used to pin the BODY: the exact parameter name `speed`, and the
# exact expression `Round((stickX / 32767.0) * speed)`. That is an assertion about
# an implementation rather than about the rule this check exists to enforce, and
# it failed the moment the arithmetic was corrected -- while the rule itself was
# never in danger, because the constant stayed in one file the whole time.
#
# Rewritten against the properties that are load-bearing, which now includes the
# fix itself. Speed is a VELOCITY scaled by measured elapsed time, not a distance
# per poll tick. A per-tick distance makes cursor speed depend on how often the
# timer happens to fire, and Windows quantises timers to about 15.625 ms -- which
# is what made the cursor visibly step along its path for the life of the project.
# Reverting to per-tick would look like a simplification and would bring the
# jitter back, so A_TickCount and the sub-pixel carry are asserted by name.
Assert-True (
    $commonSource -match
        '(?sm)^ApplyControllerMouseMove\(stickX, stickY, pixelsPerSecond\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?A_TickCount' +
        '(?:(?!\n\})[\s\S])*?carryX \+= \(stickX / 32767\.0\)' +
        '(?:(?!\n\})[\s\S])*?MouseMove\(deltaX, deltaY, 0, "R"\)' -and
    $commonSource -match
        '(?sm)^ApplyControllerMouseScroll\(stickY, steps\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?Loop steps' +
        '(?:(?!\n\})[\s\S])*?WheelUp(?:(?!\n\})[\s\S])*?WheelDown' -and
    $rawSource -notmatch '32767\.0' -and
    $helperSource -notmatch '32767\.0' -and
    $source -match 'ApplyControllerMouseMove\(rx, ry,' -and
    $helperSource -match 'ApplyControllerMouseMove\(rightX, rightY,') (
    "The controller-mouse arithmetic must exist only in SteamShell-Common.ahk.")
# Likewise the press/hold reset. Standalone keeps a thin wrapper because it also
# clears prevViewDown at every one of its sites; XFE and the helper call the
# shared body directly, because which edge scalars they clear varies per site.
Assert-True (
    $commonSource -match
        '(?sm)^ResetControllerEdgeState\(downTick, longFired, triggerDown, buttonDefinitions\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?triggerDown\["RT"\] := false' -and
    $source -match
        '(?sm)^ResetControllerHoldState\(\s*\r?\n' +
        '\s*&previousViewDown, downTick, longFired, triggerDown, ' +
        'buttonDefinitions,\s*\r?\n\s*&viewWasDown\) \{' +
        '(?:(?!\n\})[\s\S])*?previousViewDown := false' +
        '(?:(?!\n\})[\s\S])*?viewWasDown := false' +
        '(?:(?!\n\})[\s\S])*?ResetControllerEdgeState\(' +
        'downTick, longFired, triggerDown, buttonDefinitions\)' -and
    $helperSource -match 'ResetControllerEdgeState\(' -and
    $helperSource -notmatch '(?m)^ResetInputState\(') (
    "The press/hold reset must come from the one shared body.")
# Hold-to-drag. Left click ONLY, and decided in the poll loop, never inside a
# binding executor.
#
# ExecuteControllerBinding has press-only callers -- standalone's Settings
# pointer fires RB.Short on press with nothing that will ever see the release --
# so a button-down issued there would never be lifted, inside the Settings
# window, which is the one place a user has no other pointer. The -notmatch is
# what keeps that true.
Assert-True (
    $commonSource -match
        '(?sm)^ControllerBindingHoldsMouseButton\(bindingValue\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?"builtin:leftclick"' -and
    $commonSource -notmatch 'builtin:rightclick' -and
    # Against the EFFECTIVE source: the poll loop's mapping tail is
    # ControllerPollFrame in SteamShell-Shared.ahk now. The -notmatch was
    # vacuous while it read $rawSource -- ExecuteControllerBinding is defined in
    # Shared and was never in a tree's own text, so "it is not in the executor"
    # was true by construction rather than by fact.
    $source -match 'ControllerBindingHoldsMouseButton\(' -and
    $source -match 'HoldControllerMouseButton\("LButton"\)' -and
    $source -notmatch
        '(?sm)^ExecuteControllerBinding\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?HoldControllerMouseButton') (
    "Hold-to-drag must be Left click only and decided in the poll loop, not in the binding executor.")
# The conflict is made unreachable rather than explained afterwards: a button
# whose Short is Left click cannot have a Long, because Short resolves on RELEASE
# and holding is the point. The editor disables the row and says why.
Assert-True (
    $rawSource -match 'Reserved for mouse \(hold to drag\)' -and
    $rawSource -match
        '(?sm)^ControllerMapUI_UpdateEditor\(\*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'holdsMouse := ControllerBindingHoldsMouseButton\((?:(?!\n\})[\s\S])*?' +
        '\["cbLong", "btnRecLong", "btnClrLong"\](?:(?!\n\})[\s\S])*?Enabled := !holdsMouse') (
    "The mapping editor must disable the Long slot when Short is Left click.")

# The same rule in the elevated helper. Left click ONLY, and decided in the poll loop, never inside a
# binding executor.
#
# ExecuteControllerBinding has press-only callers -- standalone's Settings
# pointer fires RB.Short on press with nothing that will ever see the release --
# so a button-down issued there would never be lifted, inside the Settings
# window, which is the one place a user has no other pointer. The -notmatch is
# what keeps that true.
Assert-True (
    $commonSource -match
        '(?sm)^ControllerBindingHoldsMouseButton\(bindingValue\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?"builtin:leftclick"' -and
    $commonSource -notmatch 'builtin:rightclick' -and
    $helperSource -match 'ControllerBindingHoldsMouseButton\(' -and
    $helperSource -match 'HoldControllerMouseButton\("LButton"\)' -and
    $helperSource -notmatch
        '(?sm)^ExecuteBinding\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?HoldControllerMouseButton') (
    "Hold-to-drag must be Left click only and decided in the poll loop, not in the binding executor.")

# The synthetic mouse button ledger, and the three places a held button must not
# survive. A stuck LButton in a Winlogon shell replacement is unrecoverable
# without a keyboard, so this is asserted rather than reviewed.
#
# The ordering inside ReleaseControllerMouseButtons is load-bearing: the ledger
# entry is deleted BEFORE the SendInput, so a throw inside SendInput cannot leave
# a name recorded as held forever and turn every later release into a no-op.
Assert-True (
    $commonSource -match
        '(?sm)^ControllerHeldMouseButtons\(\)\s*\{(?:(?!\n\})[\s\S])*?static held := Map\(\)' -and
    $commonSource -match
        '(?sm)^ReleaseControllerMouseButtons\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'held\.Delete\(button\)(?:(?!\n\})[\s\S])*?SendInput\("\{" button " up\}"\)' -and
    $commonSource -match
        '(?sm)^ExpireControllerMouseButtons\(maxHeldMs\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'now - pressedTick < maxHeldMs' -and
    $commonSource -match
        '(?sm)^ResetControllerEdgeState\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ReleaseControllerMouseButtons\(\)') (
    "The synthetic mouse button ledger or its release from the reset seam is incomplete.")

# SteamShell.exe must release a held mouse button on EVERY route out, and must arm the
# watchdog at top level. The watchdog is deliberately not beside the poll timer:
# a poll loop that has stopped is exactly the case it covers, so anything that
# cancels the poll must not cancel this.
Assert-True (
    $rawSource -match
        '(?sm)^ExitCleanup\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?ReleaseControllerMouseButtons\(\)' -and
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
    "SteamShell.exe must release held mouse buttons on exit and on an uncaught error, and arm the watchdog unconditionally.")

# The elevated helper must release a held mouse button on EVERY route out, and must arm the
# watchdog at top level. The watchdog is deliberately not beside the poll timer:
# a poll loop that has stopped is exactly the case it covers, so anything that
# cancels the poll must not cancel this.
Assert-True (
    $helperSource -match
        '(?sm)^HelperExitCleanup\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?ReleaseControllerMouseButtons\(\)' -and
    $helperSource -match
        '(?sm)^HandleUncaughtHelperError\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?ReleaseControllerMouseButtons\(\)' -and
    $helperSource -match '(?m)^SetTimer\(ControllerMouseSafetyTick, 5000\)' -and
    # $helperEffective, not $helperSource: the watchdog moved into
    # SteamShell-Common.ahk once it turned out to be byte-identical to the
    # shared copy, so it is only visible with the #Include resolved. The
    # assertions either side stay on the raw file deliberately -- ARMING it at
    # top level, and not arming it from ApplyRuntimeTimers, are properties of
    # this file and not of the behaviour. Exactly the split already made for the
    # standalone tree's copy of this rule a few assertions above.
    $helperEffective -match
        '(?sm)^ControllerMouseSafetyTick\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ExpireControllerMouseButtons\(30000\)' -and
    # The helper has no ApplyRuntimeTimers at all, so constraining its body was
    # true whatever the code did. What the sentence below actually promises is
    # that the watchdog is armed unconditionally, which is checkable: the arming
    # call must not sit inside an `if`.
    $helperSource -notmatch
        '(?m)^\s+if\b[^\r\n]*\r?\n\s+SetTimer\(ControllerMouseSafetyTick') (
    "The elevated helper must release held mouse buttons on exit and on an uncaught error, and arm the watchdog unconditionally.")


# ONE reset body, not seven.
#
# Discarding press/hold state at an early return used to be four statements
# hand-copied at every one of PollController's seven abort paths, in four
# slightly different arrangements. XFE has had a single function for this since
# it was written. A reset that must be remembered seven times is one that will
# eventually be forgotten once, and the hold-to-drag work adds "release any
# synthetic mouse button" to exactly this set -- where a missed site leaves a
# button held down in the Windows shell with no keyboard.
#
# The second half is the assertion that matters: prevViewDown may be assigned
# false in exactly ONE place, its own static declaration. Any other occurrence is
# a reset block that has grown back, which is how the seven appeared originally.
$holdResetCalls = [regex]::Matches(
    $source, 'ResetControllerHoldState\(\s*\r?\n\s*&prevViewDown, downTick, longFired, prevTrigDown, btnDefs,\s*\r?\n\s*&viewWasDown\)')
$strayViewDownResets = @(
    [regex]::Matches($source, '(?m)^(\s*)(static\s+)?prevViewDown := false') |
        Where-Object { -not $_.Groups[2].Success })
Assert-True (
    $source -match
        '(?sm)^ResetControllerHoldState\(\s*\r?\n' +
        '\s*&previousViewDown, downTick, longFired, triggerDown, buttonDefinitions,' +
        '\s*\r?\n\s*&viewWasDown\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?previousViewDown := false' +
        '(?:(?!\n\})[\s\S])*?ResetControllerEdgeState\(' -and
    # The tracker reset itself lives in SteamShell-Common.ahk now, so this body
    # must NOT contain a second copy of it.
    $source -notmatch
        '(?sm)^ResetControllerHoldState\(\s*\r?\n' +
        '\s*&previousViewDown[^\r\n]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?triggerDown\["RT"\] := false' -and
    $holdResetCalls.Count -ge 7 -and
    $strayViewDownResets.Count -eq 0) (
    "PollController must clear press/hold state through the one " +
    "ResetControllerHoldState body. Found " + $holdResetCalls.Count +
    " call sites and " + $strayViewDownResets.Count +
    " open-coded prevViewDown resets.")

# The feature must be disableable without discarding the EXE list, and the
# toggle must be read ahead of the result cache or turning it off would linger.
Assert-True (
    $source -match
        '(?sm)^AutoMouseModeActive\(\)\s*\{(?:(?!\n\})[\s\S])*?if\s*!EnableAutoMouseMode\s*\r?\n\s*return false(?:(?!\n\})[\s\S])*?' +
        'if\s*\(!DesktopMode\s*&&\s*AutoMouseExeSet\.Count\s*=\s*0\)' -and
    $source -match
        '(?s)EnableAutoMouseMode\s*:=\s*ReadBool\("Features",\s*"EnableAutoMouseMode"') (
    "Automatic mouse mode has no working kill switch independent of its EXE list.")
Assert-True (
    $source -match
        '(?sm)^AutoMouseProcessMatches\(exeName\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'AutoMouseExeSet\.Has\("explorer\.exe"\)(?:(?!\n\})[\s\S])*?' +
        '"startmenuexperiencehost\.exe"(?:(?!\n\})[\s\S])*?' +
        '"shellexperiencehost\.exe"(?:(?!\n\})[\s\S])*?' +
        '"searchhost\.exe"(?:(?!\n\})[\s\S])*?' +
        '"searchui\.exe"' -and
    $source -match
        '(?sm)^AutoMouseModeActive\(\)(?:(?!\n\})[\s\S])*?' +
        'foregroundExe\s*:=\s*StrLower\(WinGetProcessName\("ahk_id " hwnd\)\)(?:(?!\n\})[\s\S])*?' +
        'AutoMouseProcessMatches\(foregroundExe\)') (
    "The explorer.exe automatic-mouse opt-in no longer covers Start and Search shell hosts.")
Assert-True (
    $source -match
        '(?sm)^AutoMouseModeActive\(\)(?:(?!\n\})[\s\S])*?if\s*\(DesktopMode\s*&&\s*!EnableDesktopAutoMouseMode\)(?:(?!\n\})[\s\S])*?' +
        'DesktopMode\s*\?\s*!DesktopAutoMouseExcludeExeSet\.Has\(foregroundExe\)' -and
    $source -match
        '(?sm)^LoadSettings\(\)(?:(?!\n\})[\s\S])*?EnableDesktopAutoMouseMode\s*:=\s*ReadBool(?:(?!\n\})[\s\S])*?' +
        'DesktopAutoMouseExcludeExeList(?:(?!\n\})[\s\S])*?DesktopAutoMouseExcludeExeSet\s*:=\s*Map\(\)' -and
    $source -match
        '(?sm)^TrayToggleDesktopAutoMouse\([^)]*\)(?:(?!\n\})[\s\S])*?CommitIniChanges(?:(?!\n\})[\s\S])*?' +
        'EnableDesktopAutoMouseMode(?:(?!\n\})[\s\S])*?BuildProductTrayMenu\(\)' -and
    $source -match
        # The entry is declared with its checked state rather than added and then
        # Checked, so the pin is that the state still comes from the two flags.
        '(?sm)^ProductTrayItems\(\)(?:(?!\n\})[\s\S])*?Automatic Mouse Throughout Desktop(?:(?!\n\})[\s\S])*?' +
        '"checked", EnableAutoMouseMode && EnableDesktopAutoMouseMode' -and
    # Defined in the shared page table now, and marked standalone-only: the
    # companion has no desktop mode, which its own validator enforces by name.
    $source -match
        '(?s)"product", "standalone", "type", "checkbox",\s*\r?\n\s*' +
        '"section", "Features", "key", "EnableDesktopAutoMouseMode"' -and
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
    $source -match '(?sm)^NormalizeHexColor\(value\)\s*\{(?:(?!\n\})[\s\S])*?return ""' -and
    $source -match
        '(?sm)^QuickMenuApplyAccent\((?:(?!\n\})[\s\S])*?if\s*\(hex\s*=\s*""\)\s*\{(?:(?!\n\})[\s\S])*?QuickMenuAccentPresetHex\("Purple"\)') (
    "An invalid Quick Menu accent color no longer falls back to the default.")

# Reload remains available through the keyboard shortcut, but intentionally no
# longer consumes a couch-facing Settings row.
Assert-True (
    $source -match 'ReloadSettings\(' -and
    $source -notmatch '"settingsReload",\s*"label",\s*"Reload Settings"') (
    "Reload Settings returned to the Quick Menu or lost its non-menu recovery path.")
Assert-True (
    $source -match
        '(?sm)^ProductTrayItems\(\)\s*\{(?:(?!\n\})[\s\S])*?Open Quick Menu(?:(?!\n\})[\s\S])*?' +
        'if\s*\(DesktopMode\)(?:(?!\n\})[\s\S])*?Return to SteamShell(?:(?!\n\})[\s\S])*?' +
        'Exit Steam to Desktop(?:(?!\n\})[\s\S])*?Exit SteamShell') (
    "The notification-area menu is no longer context-aware for desktop mode.")
# The desktop-restore path restarts Explorer, which destroys every existing
# notification-area icon. Losing the TaskbarCreated re-assert would silently
# make SteamShell unreachable after exiting to the desktop.
Assert-True (
    $source -match
        '(?sm)^RegisterTaskbarCreatedListener\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RegisterWindowMessageW"(?:(?!\n\})[\s\S])*?"TaskbarCreated"(?:(?!\n\})[\s\S])*?' +
        'OnMessage\(TaskbarCreatedMessage,\s*TaskbarCreatedHandler\)' -and
    $source -match
        '(?sm)^TaskbarCreatedHandler\(\*\)\s*\{(?:(?!\n\})[\s\S])*?SetTimer\(ReassertTrayIcon' -and
    $source -match
        '(?sm)^ReassertTrayIcon\(\)\s*\{(?:(?!\n\})[\s\S])*?A_IconHidden\s*:=\s*true(?:(?!\n\})[\s\S])*?' +
        'A_IconHidden\s*:=\s*false(?:(?!\n\})[\s\S])*?ApplyTrayIconImage\(\)') (
    "The tray icon is no longer re-asserted after an Explorer taskbar rebuild.")
$trayInitCall = [regex]::Match($source, '(?m)^InitializeTrayMenu\(\)\s*$')
# Not anchored: this matches the CALL in the startup sequence, which is indented
# inside an if-block. Anchoring it to column 0 finds only the definition, whose
# parameter list does not continue "A_WinDir "\explorer.exe"" -- so the pattern
# matches nothing and the ordering check below silently has no operand.
$explorerBoot = [regex]::Match(
    $source,
    '(?s)LaunchInteractiveApp\(\s*' +
    'A_WinDir\s+"\\explorer\.exe",\s*"",\s*A_WinDir,\s*' +
    '"Normal",\s*&explorerPid,\s*"Background Explorer shell"\)')
Assert-True (
    $trayInitCall.Success -and $explorerBoot.Success -and
    $trayInitCall.Index -lt $explorerBoot.Index) (
    "The tray must be initialised before Explorer starts so TaskbarCreated is not missed.")

# Resolve named GUI, timer, and Windows-message callbacks. Inline lambdas and
# the deliberately variable `callback` argument are not included here.
# Name AND position: the position is what lets a reference be checked against
# the parameters of the function it sits in, below.
$callbackReferences = New-Object System.Collections.Generic.List[object]
foreach ($pattern in @(
    '\.OnEvent\(\s*"[^"]+"\s*,\s*([A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_\[])',
    'SetTimer\(\s*([A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_\[])',
    'OnMessage\(\s*[^,]+,\s*([A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_\[])',
    'CallbackCreate\(\s*([A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_\[])')) {
    foreach ($m in [regex]::Matches($source, $pattern)) {
        $callbackReferences.Add([PSCustomObject]@{
            Name = $m.Groups[1].Value
            Index = $m.Index
        })
    }
}
# A SUBSCRIPT is not a name. The patterns above reject an identifier followed by
# "[", because SettingsAddButtonRow wires its buttons with
# .OnEvent("Click", entry[2]) -- "entry" is the loop variable holding a
# [label, callback] pair, not a function. That function moved into
# SteamShell-Shared.ahk, which this validator's effective source includes, so a
# scan that had never seen it began reporting "entry" as a missing callback.
#
# The lookahead deliberately still allows "." so that SetTimer(Foo.Bind(...))
# keeps checking that Foo exists; only the subscript form is excluded.
#
# A PARAMETER HOLDING A FUNCTION is not a missing callback, and this used to be
# a one-name exception for "callback". That was a hand-kept list of parameter
# names, so the next shared helper to take one -- SharedLaunchWithStagger's
# `launcher` -- failed the build for doing the same legitimate thing.
#
# Derived now. A reference is excused when the name is a parameter of the
# function it appears IN, which is the actual rule the exception was standing in
# for. Bounded to the enclosing function rather than to the file: a parameter
# named `launcher` in one function must not excuse a genuinely missing
# `launcher` callback in another.
#
# The enclosing function is the last one whose header starts at column zero
# before the reference. Every function in these sources does.
$functionHeaders = [regex]::Matches(
    $source, '(?m)^([A-Za-z_]\w*)\(([^)]*)\)\s*\{')
$missingCallbacks = New-Object System.Collections.Generic.List[string]
foreach ($reference in $callbackReferences) {
    $name = $reference.Name
    if ($functionNames.ContainsKey($name.ToLowerInvariant())) { continue }
    $enclosing = $null
    foreach ($header in $functionHeaders) {
        if ($header.Index -gt $reference.Index) { break }
        $enclosing = $header
    }
    if ($enclosing) {
        $isParameter = $false
        foreach ($parameter in ($enclosing.Groups[2].Value -split ',')) {
            # `&byRef`, `name := default` and plain names all reduce to a word.
            $word = [regex]::Match($parameter, '[A-Za-z_]\w*')
            if ($word.Success -and $word.Value -eq $name) { $isParameter = $true; break }
        }
        if ($isParameter) { continue }
    }
    $missingCallbacks.Add($name)
}
$missingCallbacks = @($missingCallbacks | Sort-Object -Unique)
Assert-True ($missingCallbacks.Count -eq 0) (
    "Named callbacks without matching functions: " +
    ($missingCallbacks -join ", "))

# Named per FILE, not per program.
#
# $source is the effective source, so this also sees SteamShell-Shared.ahk and
# SteamShell-Common.ahk -- and reported both as "SteamShell.ahk contains
# trailing whitespace", which is a message that sends the reader to a file where
# grep finds nothing. The rule was right and only its wording was wrong, which is
# the most expensive kind of wrong in a diagnostic.
$trailingWhitespaceFiles = @()
foreach ($file in @("SteamShell.ahk", "SteamShell-Shared.ahk", "SteamShell-Common.ahk")) {
    $path = Join-Path $projectRoot $file
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $hits = [regex]::Matches((Get-SourceText $path), '(?m)[ \t]+$')
    if ($hits.Count -gt 0) {
        $trailingWhitespaceFiles += "$file ($($hits.Count))"
    }
}
Assert-True ($trailingWhitespaceFiles.Count -eq 0) (
    "Trailing whitespace in: " + ($trailingWhitespaceFiles -join ", ") + ".")
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
# Ends at the next top-level definition, not at a NAMED neighbour.
#
# This read `IndexOf("GetActiveAudioOutputDevices() {", $actionsStart)`, which
# said "the actions section ends where that function begins" -- true only while
# that function happened to sit next in the file. It moved into
# SteamShell-Shared.ahk, which the #Include inlines ABOVE this point, so the
# forward search returned -1 and the section could not be extracted at all.
#
# The actions section is the body of QuickMenuActivateSelected, so that is what
# is expressed here. The two sections above keep their named delimiters
# deliberately: the definitions section spans several functions, and
# ReleaseQuickMenuPaintResources sits inside it, so "the next definition" would
# quietly shrink what is being checked.
$actionsEnd = -1
if ($actionsStart -ge 0) {
    $afterHeader = $source.IndexOf("`n", $actionsStart) + 1
    $nextDefinition = [regex]::Match(
        $source.Substring($afterHeader), '(?m)^[A-Za-z_]\w*\(')
    if ($nextDefinition.Success) {
        $actionsEnd = $afterHeader + $nextDefinition.Index
    }
}
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
# Rows that dispatch through DATA rather than through a named case.
#
# A row carrying "page" or "back" navigates from the field itself --
# QuickMenuActivateSelected reads row.Has("back") / row["page"] before its
# switch -- so sixteen ids that used to need a case here no longer have one.
# Rows in QuickMenuToggleTable answer both their value and their write from that
# table, keyed on the row id, so they have no case in the value switch either.
#
# Without these two sets this check reads a deliberate consolidation as a
# regression, which is exactly what it did: "Quick Menu row has no activation
# mapping: audioMenu".
$fieldDispatchedIds = @()
$backDispatchedIds = @()
foreach ($defLine in ($definitionsText -split "`r?`n")) {
    $idMatch = [regex]::Match($defLine, 'Map\("id",\s*"([^":]+)"')
    if (-not $idMatch.Success) { continue }
    $rowId = $idMatch.Groups[1].Value
    if ($defLine -match '"back",\s*true') {
        $backDispatchedIds += $rowId
        $fieldDispatchedIds += $rowId
    } elseif ($defLine -match '"page",\s*"') {
        $fieldDispatchedIds += $rowId
    }
}
$tableDispatchedIds = @(
    [regex]::Matches($source, '"(q\w+)",\s*Map\("section",') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Assert-True ($fieldDispatchedIds.Count -ge 8 -and $tableDispatchedIds.Count -ge 8) (
    "The Quick Menu page/back fields or the toggle table could not be read; " +
    "this check would silently stop covering the rows they dispatch.")
# Read from QuickMenuRowIsInert rather than restated here. The two lists drifted
# the moment a row was declared inert in the shared file and this copy was not
# updated -- gameScoreEmpty, which has never done anything when selected.
$unavailableActionIds = @(
    [regex]::Matches(
        [regex]::Match($source, '(?ms)^QuickMenuRowIsInert\(index\)\s*\{.*?^\}\s*$').Value,
        '"([^"]+)",\s*true') | ForEach-Object { $_.Groups[1].Value })
foreach ($required in @(
    "displayScaleUnavailable", "displayUnavailable", "hdrUnavailable",
    "rtssDisabled", "rtssMissing", "tasksUnavailable")) {
    Assert-True ($unavailableActionIds -contains $required) (
        "QuickMenuRowIsInert no longer declares '$required' inert; either the " +
        "row gained an action or the inert list was read wrongly.")
}
# Actions both products implement identically live in QuickMenuActivateShared,
# which QuickMenuActivateSelected calls before its own switch. Those ids are
# dispatched, just not from the body this check reads.
$sharedActionIds = @(
    [regex]::Matches(
        [regex]::Match($source, '(?ms)^QuickMenuActivateShared\(id\)\s*\{.*?^\}\s*$').Value,
        '(?m)^\s*case\s+([^:\n]+):') |
        ForEach-Object { [regex]::Matches($_.Groups[1].Value, '"([^"]+)"') } |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Assert-True ($sharedActionIds.Count -ge 12) (
    "QuickMenuActivateShared could not be read; the rows it dispatches would " +
    "be reported as having no activation mapping.")
# The same, for the VALUE direction. QuickMenuSettingValueText answers the
# settings rows both products build -- the numbers and named states beside the
# plain on/off ones the toggle table already covers -- so its cases are value
# coverage exactly as QuickMenuActivateShared's are activation coverage.
#
# $valuesText is a SLICE of QuickMenuValue's body, not the whole file, so a case
# that moves into the shared file leaves that slice even though it never leaves
# $source. That is not a rule this check can be exempted from; it is a rule that
# has to learn where the answer moved to. Without this it reads a deliberate
# consolidation as a regression, which is what the note above the page/back sets
# already records happening once.
$sharedValueIds = @(
    [regex]::Matches(
        [regex]::Match($source, '(?ms)^QuickMenuSettingValueText\(id\)\s*\{.*?^\}\s*$').Value,
        '(?m)^\s*case\s+([^:\n]+):') |
        ForEach-Object { [regex]::Matches($_.Groups[1].Value, '"([^"]+)"') } |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Assert-True ($sharedValueIds.Count -ge 8) (
    "QuickMenuSettingValueText could not be read; the rows it answers for would " +
    "be reported as having no value mapping.")
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
    if ($blankValueIds -notcontains $id -and
        $backDispatchedIds -notcontains $id -and
        $tableDispatchedIds -notcontains $id -and
        $sharedValueIds -notcontains $id) {
        Assert-True ($valuesText.Contains('"' + $id + '"')) (
            "Quick Menu row has no value mapping: $id")
    }
    if ($unavailableActionIds -notcontains $id -and
        $fieldDispatchedIds -notcontains $id -and
        $tableDispatchedIds -notcontains $id -and
        $sharedActionIds -notcontains $id) {
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

# Counted over the EFFECTIVE source, so it covers SteamShell-Shared.ahk too --
# which is where the one enumeration now lives, as SharedWindowInventoryBuild.
# WindowEngineBuildSnapshot is its caller and the shell's only entry point to it.
$fullWindowScans = [regex]::Matches($source, 'WinGetList\(\)')
Assert-True ($fullWindowScans.Count -eq 1) (
    "Only SharedWindowInventoryBuild may perform an unfiltered full-window enumeration.")
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
        '(?sm)^ShowQuickMenu\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?DesktopRestorePending(?:(?!\n\})[\s\S])*?' +
        'if\s*\(QuickMenuVisible\s*\|\|\s*DesktopRestorePending\)' -and
    $source -match
        '(?sm)^ExitSteamAndRestoreDesktop\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'DesktopRestorePending\s*:=\s*true(?:(?!\n\})[\s\S])*?DestroyQuickMenuForSurfaceTransition\(\)') (
    "The Steam shutdown wait can reopen the Quick Menu during desktop restoration.")
Assert-True (
    $source -match
        '(?sm)^HideQuickMenu\(restorePrevious\s*:=\s*true\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'QuickMenuVisible\s*:=\s*false(?:(?!\n\})[\s\S])*?ShowWindow(?:(?!\n\})[\s\S])*?QuickMenuGui\.Hwnd(?:(?!\n\})[\s\S])*?"Int",\s*0(?:(?!\n\})[\s\S])*?' +
        'QuickMenuDestroyWindow\(\)' -and
    $source -match
        '(?sm)^QuickMenuDestroyWindow\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SendMessage\(0x0172,\s*0,\s*0,\s*QuickMenuRowsCtrl\)(?:(?!\n\})[\s\S])*?' +
        'QuickMenuGui\.Destroy\(\)(?:(?!\n\})[\s\S])*?QuickMenuGui\s*:=\s*unset') (
    "A closed Quick Menu can retain a hidden compositor surface across game transitions.")
Assert-True (
    $source -match
        '(?sm)^DestroyQuickMenuForSurfaceTransition\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'HideQuickMenu\(false\)(?:(?!\n\})[\s\S])*?DwmFlush') (
    "Desktop restoration no longer destroys and flushes the Quick Menu compositor surface.")
Assert-True (
    $source -match
        '(?sm)^ExitSteamAndRestoreDesktop\(\)\s*\{(?:(?!\n\})[\s\S])*?ExitToDesktop\(false\)') (
    "Steam shutdown is no longer linked to the temporary desktop restore.")
Assert-True (
    $source -match
        '(?sm)^RestoreExplorerDesktop\(PermanentRestore,\s*&resultMessage\)\s*\{(?:(?!\n\})[\s\S])*?WriteAndVerifyShellValue\("explorer\.exe"(?:(?!\n\})[\s\S])*?if\s*\(!PermanentRestore\)(?:(?!\n\})[\s\S])*?WriteAndVerifyShellValue\(nextShell') (
    "Temporary desktop restoration no longer verifies Explorer and restores the next-login shell.")

# Desktop mode: a session restore hands the desktop back to Explorer but keeps
# SteamShell resident. A permanent restore has deregistered the shell and must
# still terminate.
Assert-True (
    $source -match
        '(?sm)^ExitToDesktop\(PermanentRestore\s*:=\s*false,\s*ExitAfterRestore\s*:=\s*false\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if\s*\(PermanentRestore\s*\|\|\s*ExitAfterRestore\)\s*\{(?:(?!\n\})[\s\S])*?ExitApp\(\)(?:(?!\n\})[\s\S])*?' +
        'EnterDesktopMode\(') (
    "A session desktop restore must keep SteamShell running while a permanent restore still exits.")
Assert-True (
    $source -match
        '(?sm)^EnterDesktopMode\(reason\s*:=\s*""\)\s*\{(?:(?!\n\})[\s\S])*?DesktopMode\s*:=\s*true(?:(?!\n\})[\s\S])*?' +
        'DisarmSteamLifecycle\(\)(?:(?!\n\})[\s\S])*?ApplyRuntimeTimers\(\)(?:(?!\n\})[\s\S])*?ReassertTrayIcon\(\)') (
    "Entering desktop mode no longer disarms the Steam lifecycle or re-asserts the tray icon.")
# Without this, MonitorShell observes Steam as still-launched-but-absent and
# immediately re-enters the restore path on every tick.
Assert-True (
    $source -match
        '(?sm)^DisarmSteamLifecycle\(\)\s*\{(?:(?!\n\})[\s\S])*?SteamLaunched\s*:=\s*false(?:(?!\n\})[\s\S])*?' +
        'SteamObservedRunning\s*:=\s*false(?:(?!\n\})[\s\S])*?SteamMissingSinceTick\s*:=\s*0' -and
    $source -match
        '(?sm)^MonitorShell\(\)\s*\{(?:(?!\n\})[\s\S])*?if\s*\(DesktopMode\)\s*\r?\n\s*return') (
    "Shell monitoring is no longer disarmed in desktop mode.")
# Desktop mode leaves Explorer visibly in charge; the guard, window engine, and
# shell monitor must not be rescheduled behind it, but controller input must.
Assert-True (
    $source -match
        '(?sm)^ApplyRuntimeTimers\(\)\s*\{(?:(?!\n\})[\s\S])*?if\s*\(!DesktopMode\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SetTimer\(MonitorShell,\s*ShellMonitorIntervalMs\)(?:(?!\n\})[\s\S])*?' +
        'StartTaskbarGuard\(\)(?:(?!\n\})[\s\S])*?\}\s*\r?\n\s*\r?\n\s*if\s*\(EnableControllerMouseMode') (
    "Desktop mode no longer isolates shell enforcement from controller polling.")
Assert-True (
    $source -match
        '(?sm)^ReturnToShellMode\(reason\s*:=\s*""\)\s*\{(?:(?!\n\})[\s\S])*?if\s*\(SafeMode\)(?:(?!\n\})[\s\S])*?' +
        'DesktopMode\s*:=\s*false(?:(?!\n\})[\s\S])*?AllowExplorer\s*:=\s*false(?:(?!\n\})[\s\S])*?ApplyRuntimeTimers\(\)' -and
    $source -match
        '(?sm)^LaunchSteamAndReturnToShell\(\)\s*\{(?:(?!\n\})[\s\S])*?LaunchSteamBpm\(\)(?:(?!\n\})[\s\S])*?' +
        'ReturnToShellMode\("Steam launched from SteamShell"\)') (
    "Returning to SteamShell presentation, or the launch-initiated re-arm, has regressed.")
Assert-True (
    $source -match
        '(?s)case\s+"returnShell":.*?LaunchSteamAndReturnToShell\(\)' -and
    $source -match
        '(?sm)^TrayReturnToShell\([^)]*\)\s*\{\s*LaunchSteamAndReturnToShell\(\)' -and
    $source -match
        '(?sm)^LaunchSteamAndReturnToShell\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'DestroyQuickMenuForSurfaceTransition\(\)(?:(?!\n\})[\s\S])*?LaunchSteamBpm\(\)' -and
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
        '(?s)ExitSteamShell\(\)\s*\{(?:(?!\n\})[\s\S])*?if\s*\(!DesktopMode\)\s*\{.*?' +
        'ExitToDesktop\(false,\s*true\)') (
    "A full exit from shell mode must restore the desktop instead of leaving the user without a shell.")

# Desktop blackout. The backdrop must never be able to take focus, and the
# desktop windows it hides must be given back on every path that hands
# presentation to Explorer.
Assert-True (
    $source -match
        '(?s)EnsureDesktopBackdrop\(\)\s*\{(?:(?!\n\})[\s\S])*?Gui\("-Caption \+ToolWindow -DPIScale \+E0x08000000"\).*?' +
        'BackColor\s*:=\s*"000000"') (
    "The blackout backdrop is no longer a non-activating, DPI-neutral black window.")
Assert-True (
    $source -match
        '(?s)StartDesktopBlackout\(\)\s*\{(?:(?!\n\})[\s\S])*?if\s*\(AllowExplorer\s*\|\|\s*!EnableDesktopBlackout\).*?' +
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
        '(?s)ApplySafeModeOverrides\(\)\s*\{(?:(?!\n\})[\s\S])*?EnableDesktopBlackout\s*:=\s*false') (
    "Safe Mode no longer disables the desktop blackout.")
Assert-True (
    $source -match
        '(?s)DesktopBlackoutTick\(\)\s*\{(?:(?!\n\})[\s\S])*?GetForegroundWindow.*?DesktopBackdropHwnd.*?' +
        'SinkDesktopBackdrop\(\).*?HideDesktopShellWindows\(\)') (
    "The blackout safety tick no longer re-sinks the backdrop or re-hides the desktop.")
# The blackout must stay switchable from the controller, because a misbehaving
# backdrop is exactly the situation where no other input is reachable.
#
# The row is driven by QuickMenuToggleTable now rather than by a `case` of its
# own, so both halves are pinned: the table entry that says which setting it
# writes, and the ProductSettingBool arm that reads the live value back. Either
# one missing leaves the row present and inert, which is the failure this
# assertion has always been about.
Assert-True (
    $source -match '"qBlackout",\s*"label",\s*"Black Desktop Background"' -and
    $source -match
        '(?s)"qBlackout",\s*Map\(\s*"section",\s*"Features",\s*"key",\s*"EnableDesktopBlackout"\)' -and
    $source -match
        '(?s)case\s+"qBlackout":\s*return\s+EnableDesktopBlackout') (
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
        '(?sm)^SettingsEditorControllerActive\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'WinGetPID(?:(?!\n\})[\s\S])*?ScriptPid(?:(?!\n\})[\s\S])*?GetWindow(?:(?!\n\})[\s\S])*?GW_OWNER' -and
    $source -match
        '(?sm)^SettingsEditorFileSelect\((?:(?!\n\})[\s\S])*?' +
        'SettingsEditorDialogActive\s*:=\s*true(?:(?!\n\})[\s\S])*?' +
        'FileSelect\((?:(?!\n\})[\s\S])*?finally(?:(?!\n\})[\s\S])*?' +
        'SettingsEditorDialogActive\s*:=\s*false' -and
    $source -match
        '(?s)if\s*\(SettingsEditorDialogActive\s*\|\|\s*settingsPrimaryActive\).*?' +
        'SettingsEditorHandleController.*?else\s*' +
        'SettingsEditorHandlePointer' -and
    $source -match
        '(?sm)^SettingsEditorHandlePointer\((?:(?!\n\})[\s\S])*?' +
        'MouseMove\((?:(?!\n\})[\s\S])*?ExecuteControllerBinding\("RB\.Short"\)') (
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
        '(?sm)^StartTaskbarGuard\(\)\s*\{(?:(?!\n\})[\s\S])*?SetWinEventHook(?:(?!\n\})[\s\S])*?' +
        '0x8002(?:(?!\n\})[\s\S])*?SetTimer\(HideShellTaskbars,\s*' +
        'TaskbarGuardSafetyIntervalMs\)') (
    "Taskbar Guard is missing its show-event hook or periodic safety check.")
Assert-True (
    $source -match
        '(?sm)^TaskbarGuardWinEvent\([^\)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'static\s+inCallback\s*:=\s*false(?:(?!\n\})[\s\S])*?' +
        'event\s*:=\s*event\s*&\s*0xFFFFFFFF(?:(?!\n\})[\s\S])*?finally(?:(?!\n\})[\s\S])*?' +
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
        '(?s)PrepareForDesktopRestore\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
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
        '(?s)SharedTaskSwitcherWindows\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'WindowEngineIsLegacyApplicationSurface\(item,\s*true\).*?' +
        'item\["minMax"\]\s*=\s*-1.*?' +
        'legacy fullscreen window') (
    "Task Switcher no longer includes safe untitled legacy game surfaces.")
# The other half of the shared filter, asserted from the product that used to be
# missing it. Steam is resolved before the gates that reject it, not after: three
# of them -- cloaking, an empty title, no usable size -- rejected Steam Big
# Picture under Xbox FSE before the tool-window exception at the end of the chain
# was ever reached.
Assert-True (
    $source -match
        '(?s)SharedTaskSwitcherWindows\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'steam\s*:=\s*item\["steam"\].*?' +
        'item\["cloaked"\]\s*&&\s*!steam.*?' +
        'item\["title"\]\s*=\s*""\s*&&\s*!steam.*?' +
        'item\["toolWindow"\]\s*&&\s*!steam') (
    "Task Switcher no longer waives cloaking, an empty title and the tool-window " +
    "rule for Steam, which is how Big Picture vanished from it under Xbox FSE.")
Assert-True (
    $source -match
        '(?s)WindowEngineIsMinimizedLegacyGameSurface\(item\)\s*\{.*?' +
        'WindowEngineIsLegacyApplicationSurface\(item,\s*true\).*?' +
        '0x80000000.*?0x00C00000') (
    "Minimized legacy-game restoration is missing its popup/caption safeguards.")
# ANCHORED TO THE FUNCTION THAT HOLDS THE RULE, not to a forward scan from the
# scorer. When the exclusions moved into WindowEngineSkipForGameScore this
# assertion kept passing -- (?s) with .*? found the same three tokens further
# down the effective source, in unrelated functions -- so deleting the waiver
# outright did not fail the build. Bounded to one body now, and verified by
# deleting it again.
$skipBody = [regex]::Match(
    $source, '(?ms)^WindowEngineSkipForGameScore\(item\)\s*\{.*?^\}')
Assert-True (
    $skipBody.Success -and
    $skipBody.Value -match 'WindowEngineIsMinimizedLegacyGameSurface\(item\)' -and
    $skipBody.Value -match 'WindowEngineIsLegacyApplicationSurface\(item\)' -and
    $skipBody.Value -match 'item\["title"\]\s*=\s*""\s*&&\s*!legacySurface') (
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
        '(?sm)^ShowSetupAssistant\([^)]*\)(?:(?!\n\})[\s\S])*?\+Resize(?:(?!\n\})[\s\S])*?' +
        'SetupAssistantInitializeScrolling(?:(?!\n\})[\s\S])*?GetSafeTargetWindowDpi(?:(?!\n\})[\s\S])*?' +
        'workHeightPhysical\s*\*\s*0\.80(?:(?!\n\})[\s\S])*?measuredOuterHeight(?:(?!\n\})[\s\S])*?' +
        'safeOuterHeight(?:(?!\n\})[\s\S])*?SetupAssistantGui\.Show\("Hide w760 h"' -and
    $source -match
        '(?sm)^GetSafeTargetWindowDpi\([^)]*\)(?:(?!\n\})[\s\S])*?GetDpiForWindow(?:(?!\n\})[\s\S])*?' +
        'MonitorFromWindow(?:(?!\n\})[\s\S])*?GetDpiForMonitor' -and
    $source -match
        '(?sm)^SetupAssistantInitializeScrolling\(\)(?:(?!\n\})[\s\S])*?ClassScrollBar(?:(?!\n\})[\s\S])*?' +
        'SetupAssistantVerticalScroll(?:(?!\n\})[\s\S])*?SetupAssistantMouseWheel' -and
    $source -match 'vSetupSteamPath' -and
    $source -match 'vSetupRtssPath' -and
    $source -match
        '(?sm)^SetupAssistantProgramFilesX86\(\)(?:(?!\n\})[\s\S])*?ProgramFiles\(x86\)' -and
    $source -match
        '(?sm)^SetupAssistantDiscoverSteamPath\(\)(?:(?!\n\})[\s\S])*?' +
        'SetupAssistantProgramFilesX86(?:(?!\n\})[\s\S])*?' +
        '\\Steam\\steam\.exe(?:(?!\n\})[\s\S])*?Valve\\Steam' -and
    $source -match
        '(?sm)^SetupAssistantDiscoverRtssPath\(\)(?:(?!\n\})[\s\S])*?' +
        'SetupAssistantProgramFilesX86(?:(?!\n\})[\s\S])*?' +
        'RivaTuner Statistics Server\\RTSS\.exe') (
    "Setup Assistant scrolling, visible application paths, or default discovery is missing.")
Assert-True (
    $source -match
        '(?sm)^SetupAssistantRefreshDeployment\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'Existing portable installation:(?:(?!\n\})[\s\S])*?' +
        'Apply upgrades the EXE and helper; settings are preserved' -and
    $source -match
        '(?sm)^DeploySteamShell\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'existingTargetExe\s*:=\s*FileExist(?:(?!\n\})[\s\S])*?' +
        'upgradeDetected\s*:=\s*existingTargetExe\s*&&\s*sourceDiffersFromTarget(?:(?!\n\})[\s\S])*?' +
        'upgradeDetected\s*\?\s*"upgrade"(?:(?!\n\})[\s\S])*?' +
        'upgradeDetected\s*\?\s*"upgraded"') (
    "Setup Assistant no longer identifies and confirms portable helper upgrades.")
Assert-True (
    $source -match
        '(?sm)^CleanupTemporaryUpgradeSidecar\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'GetAbsoluteSteamShellPath(?:(?!\n\})[\s\S])*?' +
        'expectedTemporarySidecar\s*:=\s*RTrim\((?:(?!\n\})[\s\S])*?' +
        'GetAbsoluteSteamShellPath\(A_ScriptDir\s+"\\SteamShell"\)(?:(?!\n\})[\s\S])*?' +
        'expectedSourceSettings(?:(?!\n\})[\s\S])*?' +
        'sourceDataDirectory\)\s*=\s*StrLower\(targetDataDirectory\)(?:(?!\n\})[\s\S])*?' +
        'SteamShellPathUsesLinkOrJunction\(sourceDataDirectory\)(?:(?!\n\})[\s\S])*?' +
        'SteamShellPathUsesLinkOrJunction\(targetDataDirectory\)(?:(?!\n\})[\s\S])*?' +
        'InStr\(targetLower\s+"\\",\s*sourcePrefix\)\s*=\s*1(?:(?!\n\})[\s\S])*?' +
        'contains the selected target(?:(?!\n\})[\s\S])*?' +
        'SetupState(?:(?!\n\})[\s\S])*?pending(?:(?!\n\})[\s\S])*?inprogress(?:(?!\n\})[\s\S])*?' +
        'DirDelete\(sourceDataDirectory,\s*true\)' -and
    $source -match
        '(?sm)^SteamShellPathUsesLinkOrJunction\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'FileGetAttrib\(candidate\)(?:(?!\n\})[\s\S])*?"L"' -and
    $source -match
        '(?sm)^GetAbsoluteSteamShellPath\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'GetFullPathNameW(?:(?!\n\})[\s\S])*?GetLongPathNameW' -and
    $source -match
        '(?sm)^DeploySteamShell\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'if\s+upgradeDetected\s*\{(?:(?!\n\})[\s\S])*?' +
        'CleanupTemporaryUpgradeSidecar(?:(?!\n\})[\s\S])*?' +
        'ShowSetupCompletionDialog(?:(?!\n\})[\s\S])*?' +
        'if\s*\(completionChoice\s*=\s*"restart"\)(?:(?!\n\})[\s\S])*?' +
        'RequestSteamShellRestart(?:(?!\n\})[\s\S])*?' +
        'IntentionalExitMode\s*:=\s*"upgrade-complete"(?:(?!\n\})[\s\S])*?ExitApp' -and
    $source -match
        '(?sm)^ShowSetupCompletionDialog\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'Restart Now(?:(?!\n\})[\s\S])*?Restart Later' -and
    $source -match
        '(?sm)^RequestSteamShellRestart\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'System32\\shutdown\.exe(?:(?!\n\})[\s\S])*?/r /t 0') (
    "Upgrade cleanup, intentional updater exit, or Restart Now/Later completion flow is incomplete.")
Assert-True (
    $source -match
        '(?sm)^SetupAssistantMsgBox\([^)]*\)(?:(?!\n\})[\s\S])*?Owner(?:(?!\n\})[\s\S])*?SettingsEditorDialogActive' -and
    $source -match
        '(?sm)^DeploySteamShell\([^)]*\)(?:(?!\n\})[\s\S])*?SetupAssistantMsgBox' -and
    $source -match
        '(?sm)^SetupAssistantLaunchExternal\([^)]*\)(?:(?!\n\})[\s\S])*?-AlwaysOnTop(?:(?!\n\})[\s\S])*?' +
        'WinMinimize(?:(?!\n\})[\s\S])*?LaunchInteractiveApp(?:(?!\n\})[\s\S])*?SetupAssistantRestoreAfterExternal' -and
    $source -match
        '(?sm)^SetupAssistantOpenUacSettings\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'SetupAssistantLaunchExternal') (
    "Setup confirmations or external/UAC foreground handoff is disconnected.")
Assert-True (
    $source -match
        '(?sm)^StoreWindowsAutoLogonSecret\([^)]*\)(?:(?!\n\})[\s\S])*?LsaOpenPolicy(?:(?!\n\})[\s\S])*?' +
        'DefaultPassword(?:(?!\n\})[\s\S])*?LsaStorePrivateData(?:(?!\n\})[\s\S])*?RtlSecureZeroMemory' -and
    $source -match
        '(?sm)^ValidateWindowsLogonCredentials\([^)]*\)(?:(?!\n\})[\s\S])*?LogonUserW' -and
    $source -match
        '(?sm)^ConfigureWindowsAutoLogon\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'ValidateWindowsLogonCredentials(?:(?!\n\})[\s\S])*?DefaultUserName(?:(?!\n\})[\s\S])*?' +
        'DefaultDomainName(?:(?!\n\})[\s\S])*?StoreWindowsAutoLogonSecret(?:(?!\n\})[\s\S])*?' +
        'RegWrite\("1",\s*"REG_SZ"(?:(?!\n\})[\s\S])*?AutoAdminLogon' -and
    $source -match
        '(?s)catch\s+as\s+err.*?RegWrite\("0",\s*"REG_SZ".*?' +
        'StoreWindowsAutoLogonSecret\("",\s*true,\s*&rollbackError\)' -and
    $source -match
        '(?sm)^DisableWindowsAutoLogon\([^)]*\)(?:(?!\n\})[\s\S])*?AutoAdminLogon(?:(?!\n\})[\s\S])*?' +
        'RegDelete\(winlogonKey,\s*"DefaultPassword"\)(?:(?!\n\})[\s\S])*?' +
        'StoreWindowsAutoLogonSecret\("",\s*true' -and
    $source -match
        '(?sm)^SetupAssistantConfigureAutoLogon\([^)]*\)(?:(?!\n\})[\s\S])*?Password\s+' +
        'vAutoLogonPassword(?:(?!\n\})[\s\S])*?AutoLogonDialogEnable' -and
    $source -notmatch
        'RegWrite\([^\r\n]*"DefaultPassword"') (
    "The protected, transactional Auto-Login implementation is incomplete or writes a plaintext password.")
Assert-True (
    $source -match
        '(?sm)^ReadElevatedHelperPreference\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'EnableElevatedInputHelper(?:(?!\n\})[\s\S])*?"true"(?:(?!\n\})[\s\S])*?return ToBool' -and
    $source -match
        '(?sm)^StartElevatedInputHelper\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ReadElevatedHelperPreference\(\)(?:(?!\n\})[\s\S])*?' +
        'if\s*!EnableElevatedInputHelper(?:(?!\n\})[\s\S])*?return false(?:(?!\n\})[\s\S])*?' +
        'ExtractEmbeddedElevatedHelper(?:(?!\n\})[\s\S])*?\*RunAs' -and
    $source -match
        '(?s)"section", "Features", "key", "EnableElevatedInputHelper".*?' +
        '"default", "true"') (
    "The default-on elevated helper setting is missing or disconnected.")
Assert-True (
    $source -match
        '(?sm)^GetRetiredIniKeys\(\)(?:(?!\n\})[\s\S])*?RunElevatedOnStartup(?:(?!\n\})[\s\S])*?' +
        'EnableElevatedInputHelper' -and
    $defaultMatch.Groups[1].Value -match
        '(?m)^EnableElevatedInputHelper=true') (
    "The schema-18 elevation-setting migration is missing.")
Assert-True (
    $source -match 'FileInstall\s+"build\\SteamShell-Helper\.exe"' -and
    $source -match
        '(?sm)^ExtractEmbeddedElevatedHelper\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'FileGetVersion(?:(?!\n\})[\s\S])*?ElevatedHelperExpectedVersion(?:(?!\n\})[\s\S])*?FileMove' -and
    $source -match
        '(?sm)^DeploySteamShell\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'SteamShell-Helper\.exe(?:(?!\n\})[\s\S])*?ExtractEmbeddedElevatedHelper') (
    "The compiled helper is no longer embedded, version-verified, and deployed by Setup.")
Assert-True (
    # The XML moved to SteamShell-Common.ahk when the companion started
    # registering the same shape of task for its own helper. The rule is
    # unchanged; it is asserted where the XML now lives.
    $commonSource -match
        '(?sm)^ElevatedHelperTaskXml\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'InteractiveToken(?:(?!\n\})[\s\S])*?HighestAvailable' +
        '(?:(?!\n\})[\s\S])*?AllowStartOnDemand' -and
    $source -match
        '(?sm)^RegisterElevatedHelperTask\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'ElevatedHelperTaskXml\((?:(?!\n\})[\s\S])*?schtasks\.exe(?:(?!\n\})[\s\S])*?/create' -and
    $source -match
        '(?sm)^StartElevatedHelperTask\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'schtasks\.exe(?:(?!\n\})[\s\S])*?/run(?:(?!\n\})[\s\S])*?WaitForNewExecutablePid' -and
    # The task gate is the SECURITY PROPERTY, not the installation mode.
    #
    # It used to read `mode = "standard"`, a proxy for "the helper sits where a
    # non-administrator cannot replace it". The helper is now installed to
    # Program Files in every mode -- including Portable, which is why it is no
    # longer refused a task -- so the proxy is gone and the real question is
    # asked instead. A task is an unprompted elevation to whatever binary sits
    # at its action path; it must never be registered for a replaceable one.
    $source -match
        '(?sm)^StartElevatedInputHelper\(\)(?:(?!\n\})[\s\S])*?taskEligible\s*:=\s*' +
        'ElevatedHelperLocationIsProtected\((?:(?!\n\})[\s\S])*?' +
        'StartElevatedHelperTask' -and
    $source -notmatch 'taskEligible\s*:=\s*\(mode\s*=\s*"standard"\)' -and
    # ...and the helper is in Program Files in every mode, which is what makes
    # that check pass for a portable install.
    $source -match
        '(?sm)^SteamShellElevatedHelperDirectory\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'A_ProgramFiles "\\SteamShell\\bin"' -and
    $source -notmatch 'InStr\(mode, "portable"\)\s*\r?\n\s*\? A_ScriptDir "\\SteamShell"' -and
    $source -match
        '(?sm)^DeploySteamShell\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'StrLower\(installationMode\)\s*=\s*"custom"(?:(?!\n\})[\s\S])*?' +
        'independently invokable elevated task(?:(?!\n\})[\s\S])*?Continue with Custom shell registration' -and
    $source -match
        '(?sm)^VerifyElevatedHelperProcess\([^)]*\)(?:(?!\n\})[\s\S])*?ProcessGetPath(?:(?!\n\})[\s\S])*?' +
        'GetProcessTokenSecurity(?:(?!\n\})[\s\S])*?helperIntegrity\s*!=\s*"High"(?:(?!\n\})[\s\S])*?' +
        'ExpectedInteractiveUserSid(?:(?!\n\})[\s\S])*?ExpectedInteractiveSessionId' -and
    $source -match
        '(?sm)^StartElevatedInputHelper\(\)(?:(?!\n\})[\s\S])*?' +
        'WaitForVerifiedElevatedHelper(?:(?!\n\})[\s\S])*?ElevatedHelperAvailable' -and
    $source -match
        '(?sm)^StartElevatedInputHelper\(\)(?:(?!\n\})[\s\S])*?\*RunAs') (
    "The protected helper task, verified process boundary, or direct-UAC fallback is disconnected.")
Assert-True (
    $source -match
        'HealthResult\(results,\s*A_IsAdmin\s*\?\s*"warn"\s*:\s*"pass",\s*' +
        '"Main shell privileges"' -and
    $source -match
        'HealthResult\(results,\s*helperStatus,\s*"Elevated helper"' -and
    $source -match '"Elevated helper protection"') (
    "Health Check no longer reports the separated main/helper privilege state.")

# SteamShell.exe is the installer for both products, so it embeds the XFE
# companion the same way it embeds the elevated helper, and the build has to
# produce that payload before compiling.
Assert-True (
    # One build script produces all three binaries now. It must still run BOTH
    # validators, because a single EXE is compiled from two sources whose
    # product rules are separate and in places opposite.
    $buildScript -match '& \$validatorPath' -and
    $buildScript -match '& \$xfeValidatorPath' -and
    $buildScript -match
        '(?s)xfeEmbedPath.*?"SteamShell-XFE\.exe".*?' +
        '/in", \$xfeSourcePath.*?' +
        "xfeEmbedVersion\s+-ne\s+`"$xfeVersionPattern`"" -and
    $source -match 'FileInstall\s+"build\\SteamShell-XFE\.exe"' -and
    $source -match "XfeExpectedVersion\s*:=\s*`"$xfeVersionPattern`"" -and
    $source -match
        '(?sm)^ExtractEmbeddedXfe\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'FileGetVersion(?:(?!\n\})[\s\S])*?XfeExpectedVersion(?:(?!\n\})[\s\S])*?FileMove') (
    "The XFE companion is no longer built, embedded, and version-verified by SteamShell.")

# XFE must never be elevated and must never become the shell. Those two
# properties are the entire reason the second product exists.
Assert-True (
    # The XML moved to SteamShell-Common.ahk when Setup and the companion stopped
    # emitting two different ones. The rule is unchanged -- logon-triggered,
    # interactive token, LEAST privilege, never HighestAvailable -- so it is
    # asserted where the XML now lives, plus that Setup calls it.
    $commonSource -match
        '(?sm)^XfeLogonTaskXml\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'LogonTrigger(?:(?!\n\})[\s\S])*?InteractiveToken' +
        '(?:(?!\n\})[\s\S])*?LeastPrivilege' -and
    $commonSource -notmatch
        '(?sm)^XfeLogonTaskXml\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?HighestAvailable' -and
    $source -match
        '(?sm)^RegisterXfeLogonTask\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'XfeLogonTaskXml\(sidText, xfePath' -and
    $source -match
        '(?sm)^DeploySteamShellXfe\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ExtractEmbeddedXfe\(targetExe,\s*&xfeDeployError,\s*true\)' -and
    $source -match
        '(?sm)^DeploySteamShellXfe\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RegWrite\("XFE",\s*"REG_SZ",\s*SteamShellRegKey,\s*"Product"\)' -and
    $source -notmatch
        '(?sm)^DeploySteamShellXfe\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'WriteAndVerifyShellValue') (
    "The XFE install path no longer stays unelevated and shell-free.")
# ONE XFE logon task, one name, one XML.
#
# Setup Assistant registered "SteamShell XFE Companion" with no logon delay and
# XFE's own Advanced button registered "SteamShell-XFE" with a 10-second delay,
# so they were different tasks: Check Logon Task reported none after a Setup
# install, Create then made a second one and two companions started at sign-in,
# Remove deleted only one, and README-XFE's documented delay was absent from the
# route the documentation recommends.
#
# The delay is the assertion that matters -- it is the one the docs promise.
Assert-True (
    $commonSource -match
        '(?sm)^XfeLogonTaskName\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"SteamShell XFE Companion"' -and
    $commonSource -match
        '(?sm)^XfeLogonTaskLegacyName\(\)\s*\{(?:(?!\n\})[\s\S])*?"SteamShell-XFE"' -and
    $commonSource -match
        '(?sm)^XfeLogonTaskXml\(account, command, arguments, workingDirectory\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?<Delay>PT10S</Delay>' +
        '(?:(?!\n\})[\s\S])*?<RunLevel>LeastPrivilege</RunLevel>' +
        '(?:(?!\n\})[\s\S])*?<DisallowStartIfOnBatteries>false' +
        '(?:(?!\n\})[\s\S])*?<ExecutionTimeLimit>PT0S' -and
    # Neither program may build that XML itself any more.
    $rawSource -notmatch '<LogonTrigger>' -and
    $rawSource -match 'XfeLogonTaskXml\(' -and
    # Both routes clear the name the companion used to register under.
    $rawSource -match 'XfeLogonTaskLegacyName\(\)') (
    "The XFE logon task must come from one shared name and one shared XML, with the 10s delay.")


# Replacing a running image is a sharing violation, and Setup did it three times
# over: the companion, the elevated helper, and the uninstall directory delete.
# The companion is the one that mattered -- its logon task starts it at sign-in
# on every XFE machine, so the file was ALWAYS locked and Setup could
# essentially never apply.
#
# Ordering is the assertion, not merely presence. Each stop must come BEFORE the
# operation it protects, and for the helper before the directory is hardened as
# well: hardening a locked file secures a directory around a stale binary.
Assert-True (
    $source -match
        '(?sm)^DeploySteamShellXfe\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'StopRunningSteamShellExecutable\(\s*\r?\n\s*targetExe,' +
        '(?:(?!\n\})[\s\S])*?ExtractEmbeddedXfe\(targetExe,' -and
    $source -match
        '(?sm)^DeploySteamShellXfe\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'StopRunningSteamShellExecutable\(\s*\r?\n\s*deployedHelper,' +
        '(?:(?!\n\})[\s\S])*?HardenElevatedHelperDirectory\(' +
        '(?:(?!\n\})[\s\S])*?ExtractEmbeddedElevatedHelper\(' -and
    $source -match
        '(?sm)^DeploySteamShell\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'StopRunningSteamShellExecutable\(\s*\r?\n\s*deployedHelper,' +
        '(?:(?!\n\})[\s\S])*?HardenElevatedHelperDirectory\(' +
        '(?:(?!\n\})[\s\S])*?ExtractEmbeddedElevatedHelper\(') (
    "Setup must close a running executable before replacing it, and before hardening its directory.")
# Identity first, and a process it cannot account for stops the install rather
# than being terminated. Setup replacing a file is not a licence to kill
# arbitrary processes that happen to sit at that path.
Assert-True (
    $source -match
        '(?sm)^StopRunningSteamShellExecutable\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?SteamShellSetupProcessMatchesIdentity\(pid\)' +
        '(?:(?!\n\})[\s\S])*?CloseSteamShellProcessForSetup\(pid,\s*true\)' -and
    $source -match
        '(?sm)^StopRunningSteamShellExecutable\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?foreign(?:(?!\n\})[\s\S])*?return false' -and
    $source -match
        '(?sm)^StopRunningSteamShellExecutable\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?WaitForReplaceableFile\(executablePath' -and
    # The graceful path posts to a HIDDEN main window. An open-coded WinClose
    # without DetectHiddenWindows finds nothing and silently always terminates,
    # which is why this delegates rather than reimplements.
    $source -match
        '(?sm)^CloseSteamShellProcessForSetup\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?DetectHiddenWindows\(true\)' +
        '(?:(?!\n\})[\s\S])*?PostMessage\(0x0010') (
    "The running-executable stop must verify identity, fail closed on a foreign process, and close gracefully.")
# The companion was absent from the elevated takeover entirely, which is where
# the reported upgrade failure came from.
Assert-True (
    $source -match
        '(?sm)^CloseExistingSteamShellInstancesForElevatedSetup\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?GetPidsByExeName\("SteamShell-XFE\.exe"\)' +
        '(?:(?!\n\})[\s\S])*?CloseSteamShellProcessForSetup\(pid,\s*true\)' -and
    $source -match
        '(?sm)^ExecuteSteamShellRemovalPlan\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?StopResidentSteamShellExecutablesForRemoval\(items\)' +
        '(?:(?!\n\})[\s\S])*?DirDelete\(path,\s*true\)') (
    "The XFE companion must be closed by the elevated takeover and before an uninstall removes it.")
# A companion Setup stopped is one the user expects back, and it must come back
# UNELEVATED. Run from an elevated Setup would hand XFE an administrator token,
# which is the one outcome its architecture exists to avoid.
Assert-True (
    $source -match
        '(?sm)^DeploySteamShellXfe\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if xfeWasRunning \{\s*\r?\n\s*xfeRestarted := RunViaDesktopShell\(targetExe' -and
    $source -notmatch
        '(?sm)^DeploySteamShellXfe\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'Run\((?:targetExe|QuoteWindowsCommandLineArg\(targetExe)') (
    "A companion Setup stopped must be restarted through the desktop shell, never with Run.")
# Win32 32 is the failure an upgrade actually hits. Only 5 was ever named, so
# the most likely deployment failure rendered as a bare number.
Assert-True (
    $source -match
        '(?sm)^DescribeFileFailure\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '32,\s*": the file is in use by a running process"') (
    "DescribeFileFailure no longer names the sharing violation an upgrade hits.")

# Which product a machine has is a recorded fact, because the uninstall for one
# is wrong for the other. Asking is the fallback for a contradicted record.
Assert-True (
    $embeddedSchema.Contains("Setup`0Product") -and
    $source -match
        '(?sm)^ResolveInstalledSteamShellProduct\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'XfeInstalledPath(?:(?!\n\})[\s\S])*?InstalledPath' -and
    $source -match
        '(?sm)^RemoveSteamShellInstallationForProduct\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ResolveInstalledSteamShellProduct(?:(?!\n\})[\s\S])*?RemoveSteamShellXfeInstallation(?:(?!\n\})[\s\S])*?' +
        'RemoveSteamShellRegistration' -and
    $source -match
        '(?sm)^RemoveSteamShellInstallationForProduct\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if !showResult(?:(?!\n\})[\s\S])*?return false' -and
    $source -match
        '(?s)mode\s*=\s*"uninstall".*?RemoveSteamShellInstallationForProduct' -and
    $source -match
        '(?sm)^SetupAssistantRequired\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SteamShellProductIsXfe(?:(?!\n\})[\s\S])*?return true') (
    "The installed product is no longer recorded, resolved, or honoured by uninstall and startup.")

# The mode question, and the controls that only mean something for the shell.
Assert-True (
    $source -match '"1\. What are you setting up\?"' -and
    $source -match 'vSetupProductStandalone Group Checked' -and
    $source -match 'vSetupProductXfe' -and
    # The two radios must be created CONSECUTIVELY. AutoHotkey groups radios by
    # creation order, so a control between them ends the run and the pair stops
    # being mutually exclusive -- both render selected and Apply reads whichever
    # it likes. This shipped once; nothing but adjacency prevents it.
    $source -match
        '(?s)vSetupProductStandalone Group Checked",\s*\r?\n\s*"[^"]*"\s*\)\s*\r?\n\s*' +
        'xfeModeRadio\s*:=\s*SetupAssistantGui\.AddRadio\(' -and
    # The mode has to visibly reconfigure what follows it, or it is a question
    # whose answer does nothing.
    $source -match
        '(?sm)^SetupAssistantRefreshDeployment\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'isXfe\s*:=\s*SetupAssistantSelectedProduct\(\)\s*=\s*"XFE"' -and
    $source -match
        '(?sm)^SetupAssistantRefreshDeployment\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"SetupPortable"\]\.Enabled\s*:=\s*browseSelected\s*&&\s*!isXfe' -and
    $source -match
        '(?sm)^SetupAssistantGetDeployment\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SetupAssistantSelectedProduct\(\)\s*=\s*"XFE"\s*\r?\n\s*\?\s*' +
        'SetupAssistantXfeStandardDirectory\(\)' -and
    $source -match
        '(?sm)^SetupAssistantXfeStandardDirectory\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'LOCALAPPDATA' -and
    $source -notmatch
        '(?sm)^SetupAssistantXfeStandardDirectory\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'A_ProgramFiles' -and
    $source -match
        '(?sm)^SetupAssistantRefreshProductMode\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"SetupRegisterShell"\]\.Enabled\s*:=\s*!isXfe' -and
    $source -match
        '(?sm)^SetupAssistantApply\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SetupAssistantSelectedProduct\(\)\s*=\s*"XFE"(?:(?!\n\})[\s\S])*?DeploySteamShellXfe(?:(?!\n\})[\s\S])*?' +
        'MarkSteamShellSetupCompleteForXfe' -and
    # Each product's automatic-start registration is a choice, and only the one
    # that applies is enabled. DeploySteamShellXfe has always handled a declined
    # startup task; for a while nothing could reach that path, which made the
    # capability real in the code and absent from the product.
    $source -match 'vSetupRegisterXfeStartup Checked' -and
    $source -match
        '(?sm)^SetupAssistantRefreshProductMode\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"SetupRegisterXfeStartup"\]\.Enabled\s*:=\s*isXfe' -and
    $source -match
        '(?sm)^SetupAssistantApply\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'registerXfeStartup\s*:=\s*SetupAssistantGui\["SetupRegisterXfeStartup"\]\.Value\s*=\s*1' +
        '(?:(?!\n\})[\s\S])*?DeploySteamShellXfe\(targetDirectory,\s*registerXfeStartup') (
    "The Setup Assistant product question is missing or disconnected from Apply.")

# An upgrade should not depend on the user reproducing choices they made months
# ago. Detection is evidence-first -- the Winlogon value and the scheduled task
# are the things with the effect -- and falls back to SteamShell's own record
# only for the install directory, which nothing else stores.
Assert-True (
    $source -match
    # Two bounded checks rather than one chain: the single chain also required
    # XfeLogonTaskName to appear AFTER /query, which stopped being true when the
    # function gained an optional name and resolved its default up front. The
    # claim worth pinning is that it queries schtasks for the XFE task by name,
    # not the order those three read in.
        '(?sm)^SteamShellXfeLogonTaskExists\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'schtasks\.exe(?:(?!\n\})[\s\S])*?/query' -and
    $source -match
        '(?sm)^SteamShellXfeLogonTaskExists\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'XfeLogonTaskName' -and
    $source -match
        '(?sm)^SteamShellIsRegisteredWindowsShell\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RegRead\(ShellRegKey,\s*"Shell"\)(?:(?!\n\})[\s\S])*?steamshell' -and
    $source -match
        '(?sm)^DetectExistingSteamShellInstallation\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SteamShellIsRegisteredWindowsShell\(\)(?:(?!\n\})[\s\S])*?' +
        'SteamShellXfeLogonTaskExists\(\)' -and
    # XFE is the more specific claim and must still be tested first: a logon task
    # is not something a shell install produces.
    #
    # What changed is the OTHER half of each test. This used to accept
    # "xfeOnDisk" and "shellOnDisk" -- an executable being present -- which both
    # uninstalls deliberately leave behind, so a removed product went on
    # reporting itself installed forever. The evidence now has to be a
    # registration, because that is what an uninstall actually clears.
    $source -match
        '(?sm)^DetectExistingSteamShellInstallation\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'xfeStartsAtLogon \|\| xfeRegisteredFlag(?:(?!\n\})[\s\S])*?' +
        'registeredAsShell \|\| Trim\(shellRegisteredPath\) != ""' -and
    $source -match
        '(?sm)^SetupAssistantPreselectExistingInstallation\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'DetectExistingSteamShellInstallation(?:(?!\n\})[\s\S])*?' +
        '"SetupProductXfe"\](?:(?!\n\})[\s\S])*?SetupAssistantRefreshDeployment' -and
    $source -match
        '(?sm)^ShowSetupAssistant\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'preselected\s*:=\s*SetupAssistantPreselectExistingInstallation\(\)') (
    "Setup Assistant no longer detects an existing installation or no longer opens on it.")

# The uninstall fallback. On a machine where SteamShell is the shell and
# something has gone wrong, "open a command prompt" is not always available.
Assert-True (
    $source -match '"6\. Remove an installation"' -and
    $source -match 'uninstallButton\.OnEvent\("Click",\s*SetupAssistantUninstall\)' -and
    $source -match
        '(?sm)^SetupAssistantUninstall\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'DetectExistingSteamShellInstallation(?:(?!\n\})[\s\S])*?' +
        'SetupAssistantMsgBox(?:(?!\n\})[\s\S])*?' +
        'RemoveSteamShellInstallationForProduct' -and
    # It must confirm first, and a declined confirmation must change nothing.
    $source -match
        '(?sm)^SetupAssistantUninstall\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'confirm != "Yes"(?:(?!\n\})[\s\S])*?return') (
    "The Setup Assistant uninstall fallback is missing or does not confirm first.")

# The product prompt names the products on its buttons and is owned by the
# window that is on top. A Yes/No box where Yes meant SteamShell and No meant
# SteamShell-XFE is not answerable from the buttons, and an unowned dialog opens
# behind the always-on-top assistant where nobody can reach it.
Assert-True (
    $source -match
        '(?sm)^ChooseSteamShellProductToRemove\([^)]*\)\s*\{(?:(?!
\})[\s\S])*?' +
        'SetupAssistantGui\.Hwnd(?:(?!
\})[\s\S])*?\+Owner' -and
    $source -match
        '(?sm)^ChooseSteamShellProductToRemove\([^)]*\)\s*\{(?:(?!
\})[\s\S])*?' +
        'AddButton\([^)]*,\s*"SteamShell"\)(?:(?!
\})[\s\S])*?' +
        'AddButton\([^)]*,\s*"SteamShell-XFE"\)(?:(?!
\})[\s\S])*?' +
        'AddButton\([^)]*,\s*"Cancel"\)' -and
    $source -match
        '(?sm)^RemoveSteamShellInstallationForProduct\([^)]*\)\s*\{(?:(?!
\})[\s\S])*?' +
        'ChooseSteamShellProductToRemove' -and
    # Scoped to this function, not the whole file: YesNoCancel is right for the
    # save-changes prompts elsewhere. What it cannot express is "which of two
    # products", where the buttons carry no meaning.
    $source -notmatch
        '(?sm)^RemoveSteamShellInstallationForProduct\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?MsgBox\(' -and
    # A caller that already knows the product says so, instead of letting this
    # resolve it a second way and reach a different answer.
    $source -match
        'RemoveSteamShellInstallationForProduct\(showResult := true, ' +
        'restorePreviousShell := false, knownProduct := ""\)' -and
    $source -match
        '(?sm)^SetupAssistantUninstall\([^)]*\)\s*\{(?:(?!
\})[\s\S])*?' +
        'RemoveSteamShellInstallationForProduct\(true,\s*true,\s*product\)' -and
    $source -match
        '(?sm)^RemoveSteamShellInstallationForProduct\([^)]*\)\s*\{(?:(?!
\})[\s\S])*?' +
        'DetectExistingSteamShellInstallation' -and
    # Every dialog on this path is owned, or it opens behind the assistant.
    $source -notmatch
        '(?sm)^RemoveSteamShellRegistration\([^)]*\)\s*\{(?:(?!
\})[\s\S])*?[^t]MsgBox\(' -and
    $source -notmatch
        '(?sm)^RemoveSteamShellXfeInstallation\([^)]*\)\s*\{(?:(?!
\})[\s\S])*?[^t]MsgBox\(') (
    "The uninstall product prompt is unowned, unlabelled, or resolves the product twice.")

# Deleting files is the one irreversible thing this installer does. A directory
# is removed only when SteamShell chose the path itself and created it; a folder
# the user chose keeps everything except SteamShell's own files. The plan is
# shown before it runs, and the choice is separate from unregistering.
Assert-True (
    $source -match
        '(?sm)^SteamShellRemovableDirectoryKind\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SteamShellProgramData(?:(?!\n\})[\s\S])*?A_ProgramFiles(?:(?!\n\})[\s\S])*?' +
        'SetupAssistantXfeStandardDirectory' -and
    # A fixed-name subdirectory counts only directly beneath the recorded
    # install directory. The name on its own is not evidence.
    $source -match
        '(?sm)^SteamShellRemovableDirectoryKind\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'parent(?:(?!\n\})[\s\S])*?installDirectory(?:(?!\n\})[\s\S])*?' +
        '"steamshell"(?:(?!\n\})[\s\S])*?"components"' -and
    $source -match
        '(?sm)^SteamShellRemovalPathIsSafe\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'drive root(?:(?!\n\})[\s\S])*?protected system location(?:(?!\n\})[\s\S])*?' +
        'SteamShellPathUsesLinkOrJunction(?:(?!\n\})[\s\S])*?A_ScriptFullPath' -and
    # Re-checked at execution, not only when the plan was built.
    $source -match
        '(?sm)^ExecuteSteamShellRemovalPlan\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SteamShellRemovalPathIsSafe\(path,\s*&recheckReason\)(?:(?!\n\})[\s\S])*?' +
        'DirDelete' -and
    $source -match
        '(?sm)^BuildSteamShellRemovalPlan\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'cannot delete the executable that is running now' -and
    # Unregistering and deleting are two separate confirmations, and deletion
    # only runs after the first has already succeeded.
    $source -match
        '(?sm)^SetupAssistantUninstall\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RemoveSteamShellInstallationForProduct(?:(?!\n\})[\s\S])*?' +
        'BuildSteamShellRemovalPlan(?:(?!\n\})[\s\S])*?deleteChoice(?:(?!\n\})[\s\S])*?' +
        'deleteChoice != "Yes"(?:(?!\n\})[\s\S])*?return' -and
    $source -match
        '(?sm)^SetupAssistantUninstall\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'This cannot be undone') (
    "Optional file removal is missing its path proof, its re-check, or its separate confirmation.")

# The registry record is a claim, not proof: it is written by whichever copy ran
# Setup, survives a manual delete, and a freshly downloaded EXE inherits it. So a
# recorded directory is removed only when it still contains something SteamShell
# put there, and only when the independent evidence agrees about where the
# installation is.
Assert-True (
    $source -match
        '(?sm)^SteamShellDirectoryContainsOurArtifacts\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SteamShell\.exe(?:(?!\n\})[\s\S])*?SteamShell-Helper\.exe' -and
    $source -match
        '(?sm)^BuildSteamShellRemovalPlan\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SteamShellDirectoryContainsOurArtifacts\(resolved\)(?:(?!\n\})[\s\S])*?' +
        'not removed' -and
    # A recorded path that is simply gone is reported, not silently ignored.
    $source -match
        '(?sm)^BuildSteamShellRemovalPlan\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'recorded, but nothing is there now' -and
    # Independent evidence: the Winlogon value and the task action are what
    # actually have the effect, so they can stand in for a missing record.
    $source -match
        '(?sm)^SteamShellRegisteredShellDirectory\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RegRead\(ShellRegKey,\s*"Shell"\)(?:(?!\n\})[\s\S])*?ShellCommandExecutablePath' -and
    $source -match
        '(?sm)^SteamShellXfeLogonTaskDirectory\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'schtasks\.exe(?:(?!\n\})[\s\S])*?<Command>' -and
    $source -match
        '(?sm)^BuildSteamShellRemovalPlan\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'evidenceDirectory\s*:=\s*isXfe(?:(?!\n\})[\s\S])*?' +
        'SteamShellXfeLogonTaskDirectory\(\)(?:(?!\n\})[\s\S])*?' +
        'SteamShellRegisteredShellDirectory\(\)' -and
    # Two sources that disagree means nothing is offered at all.
    $source -match
        '(?sm)^BuildSteamShellRemovalPlan\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'disagree, so no files are offered for deletion(?:(?!\n\})[\s\S])*?' +
        'items := \[\](?:(?!\n\})[\s\S])*?return false' -and
    # And the refusal is reported rather than looking like "nothing found".
    $source -match
        '(?sm)^SetupAssistantUninstall\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'No files were offered for deletion') (
    "File removal no longer corroborates the recorded paths before trusting them.")

# Almost every SteamShell window is +AlwaysOnTop, because it is a kiosk shell
# that must stay in front of Steam and games. An unowned dialog therefore opens
# BEHIND whichever one is up, with no taskbar to find it on -- a frozen window
# and nothing to click. Every modal must be owned, or topmost when nothing is
# showing to own it.
Assert-True (
    $source -match
        '(?sm)^SteamShellMsgBox\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SteamShellDialogOwnerHwnd\(\)(?:(?!\n\})[\s\S])*?' +
        'ownerHwnd \? " Owner" ownerHwnd : " 262144"' -and
    $source -match
        '(?sm)^SetupAssistantMsgBox\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SteamShellDialogOwnerHwnd\(\)' -and
    $source -match
        '(?sm)^SettingsEditorMsgBox\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SteamShellDialogOwnerHwnd\(\)') (
    "Dialog ownership is no longer resolved centrally, so a modal can open behind an always-on-top window.")

# +OwnDialogs is per-THREAD in AutoHotkey, so applying it when the GUI is built
# does nothing for a later event handler. Each picker has to set it itself.
Assert-True (
    $source -match
        '(?sm)^SetupAssistantSelectExecutable\([^)]*\)\s*\{(?:(?!
\})[\s\S])*?' +
        'Opt\("\+OwnDialogs -AlwaysOnTop"\)' -and
    $source -match
        '(?sm)^SetupAssistantSelectDirectory\([^)]*\)\s*\{(?:(?!
\})[\s\S])*?' +
        'Opt\("\+OwnDialogs -AlwaysOnTop"\)' -and
    $source -match
        '(?sm)^SettingsEditorFileSelect\([^)]*\)\s*\{(?:(?!
\})[\s\S])*?' +
        'Opt\("\+OwnDialogs -AlwaysOnTop"\)' -and
    $source -match
        '(?sm)^AF_SelectExecutable\([^)]*\)\s*\{(?:(?!
\})[\s\S])*?' +
        'Opt\("\+OwnDialogs -AlwaysOnTop"\)') (
    "A file picker no longer re-applies +OwnDialogs, which is per-thread and does not survive from GUI creation.")

# Closing Setup during first-run leaves an unconfigured shell running out of
# whatever folder it was launched from, invisible and with no reason to exist.
Assert-True (
    $source -match
        '(?sm)^SetupAssistantCloseRequested\([^)]*\)\s*\{(?:(?!
\})[\s\S])*?' +
        'if !FirstRunSetupMode(?:(?!
\})[\s\S])*?return(?:(?!
\})[\s\S])*?' +
        'EnsureExplorerAvailableForSetupExit\(true\)(?:(?!
\})[\s\S])*?ExitApp\(\)' -and
    $source -match
        'closeButton\.OnEvent\("Click",\s*SetupAssistantCloseRequested\)' -and
    $source -match
        'SetupAssistantGui\.OnEvent\("Close",\s*SetupAssistantCloseRequested\)' -and
    $source -match
        'SetupAssistantGui\.OnEvent\("Escape",\s*SetupAssistantCloseRequested\)') (
    "Closing Setup Assistant during first-run setup no longer exits SteamShell.")

# Controller reach and dialog ownership are asked as questions, not maintained as
# lists. Both were enumerations of every window in the application; both went
# stale the moment a window was added. The justification for enumerating -- that
# standalone evaluates these before the Quick Menu branch, and that the splash
# and backdrop would wrongly qualify -- did not survive checking: PollController
# returns from the Quick Menu branch first, and all three presentation windows
# are WS_EX_NOACTIVATE and can never be the active window.
#
# This is now the same rule SteamShell-XFE uses, which is the point: two programs
# with the same requirement should not have two different answers to it.
Assert-True (
    $source -match
        '(?sm)^SettingsEditorControllerActive\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'WinGetPID\("ahk_id " activeHwnd\) = ScriptPid' -and
    $source -match
        '(?sm)^SettingsEditorControllerActive\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'GW_OWNER' -and
    # No window may be named here. A name is a list, and a list goes stale.
    $source -notmatch
        '(?sm)^SettingsEditorControllerActive\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'IsSet\([A-Za-z]\w*Gui\)' -and
    $source -match
        '(?sm)^SteamShellDialogOwnerHwnd\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'WinGetPID\("ahk_id " activeHwnd\) = ScriptPid(?:(?!\n\})[\s\S])*?' +
        'return activeHwnd' -and
    $source -notmatch
        '(?sm)^SteamShellDialogOwnerHwnd\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'IsSet\([A-Za-z]\w*Gui\)') (
    "Controller reach or dialog ownership has gone back to enumerating windows, which goes stale.")

# RTSS keeps only the FPS number across a restart. The limiter flag is runtime
# state in its shared memory and "Custom" is a SteamShell concept RTSS never
# sees, so every branch that changes the selection has to record it or the
# selection is gone at the next boot with nothing to restore it from.
Assert-True (
    $embeddedSchema.Contains("RTSS`0RestoreFrameLimitOnStartup") -and
    $embeddedSchema.Contains("RTSS`0LastFrameCapMode") -and
    $embeddedSchema.Contains("RTSS`0LastFrameCapFps") -and
    # Bounded to the function body with (?!\n\}). An unbounded (?s).*? here used
    # to reach 128,000 characters past the function and match a CommitIniChanges
    # somewhere else entirely, so it kept passing after the body stopped calling
    # it. A validator that cannot fail is not a validator.
    $source -match
        '(?sm)^PersistRtssFrameCapSelection\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'LastFrameCapMode(?:(?!\n\})[\s\S])*?LastFrameCapFps' -and
    $source -match
        '(?sm)^PersistRtssFrameCapSelection\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SharedPersistSettings\(\[' -and
    $source -match
        '(?s)CycleRtssFrameCap\([^)]*\).*?PersistRtssFrameCapSelection\(\s*\r?\n?\s*' +
        'RtssFrameCapModeForFps' -and
    $source -match
        'PersistRtssFrameCapSelection\("off",\s*state\["fps"\]\)' -and
    $source -match 'PersistRtssFrameCapSelection\("custom",\s*customFps\)' -and
    $source -match
        'PersistRtssFrameCapSelection\("configured",\s*RtssPresetFrameCap\)' -and
    $source -match 'PersistRtssFrameCapSelection\("preset",\s*target\)' -and
    $source -match
        '(?s)PersistRtssCustomFrameCap\([^)]*\).*?RtssCustomFrameCap\s*:=\s*value.*?' +
        'PersistRtssFrameCapSelection\("custom",\s*value\)' -and
    $source -match
        '(?s)ToggleRtssFrameLimiter\(\).*?ApplyRtssGlobalState\("limiter".*?' +
        'PersistRtssFrameCapStateNow' -and
    $source -match
        '(?s)SetRtssFrameLimiterState\([^)]*\).*?ApplyRtssGlobalState\("limiter".*?' +
        'PersistRtssFrameCapStateNow' -and
    $source -match
        '(?sm)^CycleRtssFrameCap\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if\s*!SetRtssGlobalFrameLimit\(target\)(?:(?!\n\})[\s\S])*?return false(?:(?!\n\})[\s\S])*?' +
        '!ApplyRtssGlobalState\("limiter",\s*true\)(?:(?!\n\})[\s\S])*?return false(?:(?!\n\})[\s\S])*?' +
        'PersistRtssFrameCapSelection\("preset",\s*target\)' -and
    $source -match
        '(?sm)^CycleRtssFrameCap\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '!ApplyRtssGlobalState\("limiter",\s*false\)(?:(?!\n\})[\s\S])*?return false(?:(?!\n\})[\s\S])*?' +
        'PersistRtssFrameCapSelection\("off",\s*state\["fps"\]\)') (
    "A Frame Limit selection path no longer records what it applied.")

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

# Hardening must leave the helper USABLE, not merely unwritable.
#
# Shipped broken and confirmed on hardware 2026-08-02. The grant string carries
# (OI)(CI), which are inheritance flags that mean nothing on a file; running it
# with /T applied it to SteamShell-Helper.exe too, where it was rejected --
# after /inheritance:r had already stripped what the file would have inherited.
# The binary was left with an EMPTY DACL, denying everyone including
# Administrators, while /C suppressed the error and the process still exited 0.
#
# Every existing check passed. SteamShellPathIsAdminOnlyWritable asks only
# whether anyone else can WRITE, and nobody can write a file nobody can touch,
# so an unlaunchable helper was certified as protected. The main process could
# not even read its version, concluded it was missing, and tried to re-extract
# it into an administrators-only directory -- logging "extraction failed" for a
# file that was present the whole time.
Assert-True (
    # The flagged grant goes to the directory alone: no /T on that command.
    $source -match
        '(?sm)^HardenElevatedHelperDirectory\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '/grant:r " QuoteWindowsCommandLineArg\("\*S-1-5-18:\(OI\)\(CI\)F"\)' +
        '(?:(?!\n\})[\s\S])*?\*S-1-5-32-545:\(OI\)\(CI\)RX"\)\s*\r?\n' +
        '\s*try exitCode :=' -and
    # Children are made to inherit it instead of being granted it directly.
    $source -match
        '(?sm)^HardenElevatedHelperDirectory\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'binDirectory "\\\*"\)(?:(?!\n\})[\s\S])*?/reset /T /C /Q' -and
    # And the gate proves the binary is readable, not just unwritable.
    $source -match
        '(?sm)^ElevatedHelperLocationIsProtected\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'try readVersion := FileGetVersion\(helperPath\)(?:(?!\n\})[\s\S])*?' +
        'cannot be read by this account' -and
    # An unelevated session must not attempt a write that cannot succeed.
    $source -match
        '(?sm)^StartElevatedInputHelper\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if !A_IsAdmin \{(?:(?!\n\})[\s\S])*?Run Setup from an elevated') (
    "The helper hardening can leave the binary unreadable, or the gate no longer proves it is usable.")



# ==============================================================================
# ONE HELPER PAYLOAD, TWO PRODUCTS
# ==============================================================================
# SteamShell-Helper.exe now serves XFE as well, in a strictly narrower shape:
# --product=xfe does the RTSS frame cap and nothing else -- no controller input,
# no window geometry. Elevated input was deliberately NOT given to XFE, because
# the implementation here is XInput and XFE exists precisely because XInput is
# not enough for its users.
#
# Every assertion below was mutation-tested by breaking the behaviour it names.

# An unrecognised or missing --product must resolve to STANDALONE, not to the
# narrower product. Stated in that direction because the failure modes are not
# symmetric: an XFE helper that behaves as standalone merely does more than it
# was asked to, while a standalone helper that behaves as XFE silently does no
# elevated input at all and looks for the wrong parent process.
Assert-True (
    $helperSource -match
        'HelperProduct\s*:=\s*StrLower\(Trim\(ReadArgument\("product",\s*"standalone"\)\)\)\s*=\s*"xfe"\s*\r?\n\s*\?\s*"xfe"\s*:\s*"standalone"' -and
    $helperSource -match
        '(?sm)^\s*if \(HelperProduct = "xfe"\) \{[\s\S]*?MainImageName := "steamshell-xfe\.exe"[\s\S]*?' +
        'HelperInputEnabled := false[\s\S]*?HelperGeometryEnabled := false') (
    "The helper no longer defaults to the standalone product, or --product=xfe does not narrow it.")

# The parent process name must come from --product, not from a literal. A helper
# still hunting for steamshell.exe would never find an XFE parent, would never
# notice it exiting, and would outlive it as an orphaned High-integrity process.
Assert-True (
    $helperSource -match
        '(?sm)^FindMainProcess\(\)\s*\{(?:(?!\n\})[\s\S])*?global MainPath, MainImageName' -and
    $helperSource -match 'processName = StrLower\(MainImageName\)' -and
    $helperSource -notmatch 'processName = "steamshell\.exe"') (
    "The helper still resolves its parent by a hardcoded executable name.")

# The RTSS request must be serviced BEFORE the input half returns, or the XFE
# helper would do nothing at all: it is the only work that product performs.
$helperPollBody = [regex]::Match(
    $helperSource,
    '(?sm)^PollController\(\)\s*\{(?:(?!\n\})[\s\S])*\n\}')
Assert-True ($helperPollBody.Success) (
    "PollController could not be located in the helper.")
$helperRtssIndex = $helperPollBody.Value.IndexOf('ServiceElevatedRtssRequest()')
$helperInputGateIndex = $helperPollBody.Value.IndexOf('if !HelperInputEnabled {')
$helperForegroundIndex = $helperPollBody.Value.IndexOf('ElevatedForeground(&foregroundExe)')
Assert-True (
    $helperRtssIndex -ge 0 -and
    $helperInputGateIndex -ge 0 -and
    $helperForegroundIndex -ge 0 -and
    $helperRtssIndex -lt $helperInputGateIndex -and
    $helperInputGateIndex -lt $helperForegroundIndex) (
    "The XFE helper either skips RTSS requests or still performs elevated input.")

# Window geometry is standalone's job. Xbox FSE owns presentation on an XFE
# machine, so the timer must not merely no-op -- it must not be armed.
Assert-True (
    $helperSource -match
        'if HelperGeometryEnabled\s*\r?\n\s*SetTimer\(ElevatedWindowGeometryTick,\s*500\)') (
    "The elevated geometry timer is armed regardless of product.")

# Standalone names its product explicitly on both launch routes, so the task XML
# on disk records which product registered it.
# The flags themselves are built in one place now, so what is asserted here is
# the PRODUCT each route names -- which is the part that is standalone's and
# cannot be delegated.
Assert-True (
    $source -match
        '(?sm)^RegisterElevatedHelperTask\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SharedElevatedHelperArguments\(\s*\r?\n?\s*"standalone"' -and
    $source -match
        '(?sm)^StartElevatedInputHelper\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SharedElevatedHelperArguments\(\s*\r?\n?\s*"standalone"') (
    "Standalone no longer identifies its product when launching the helper.")

# ==============================================================================
# XFE HELPER DEPLOYMENT (Setup Assistant)
# ==============================================================================
# Deployed dormant in XFE mode, so a user who later opts in from XFE's own
# Settings -- a normal-integrity application that cannot write an
# administrator-only directory -- does not have to re-run an installer.
#
# The ORDER is the whole assertion, and it is the order an earlier revision of
# the shell path got wrong: it ran /setowner once, before the payload existed,
# and Windows takes a new file's owner from the creating token, so the extracted
# helper was owned by the installing administrator's own SID and the file-level
# gate would have refused it -- failing every install. Harden, replace, harden
# again, verify.
$xfeDeployBody = [regex]::Match(
    $source,
    '(?sm)^DeploySteamShellXfe\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*\n\}')
Assert-True ($xfeDeployBody.Success) (
    "DeploySteamShellXfe could not be located.")
$xfeHardenMatches = [regex]::Matches(
    $xfeDeployBody.Value, 'HardenElevatedHelperDirectory\(')
Assert-True ($xfeHardenMatches.Count -eq 2) (
    "XFE helper deployment must harden twice: once before the payload exists and once after.")
$xfeFirstHarden = $xfeHardenMatches[0].Index
$xfeSecondHarden = $xfeHardenMatches[1].Index
$xfeExtract = $xfeDeployBody.Value.IndexOf('ExtractEmbeddedElevatedHelper(')
$xfeVerify = $xfeDeployBody.Value.IndexOf('ElevatedHelperLocationIsProtected(')
Assert-True (
    $xfeExtract -ge 0 -and
    $xfeVerify -ge 0 -and
    $xfeFirstHarden -lt $xfeExtract -and
    $xfeExtract -lt $xfeSecondHarden -and
    $xfeSecondHarden -lt $xfeVerify) (
    "The XFE helper deployment order is wrong; it must harden, replace, harden again, then verify.")

# The payload must NOT live inside XFE's own install directory. Setup grants the
# signed-in user write access there, and a user-writable parent can be deleted
# and recreated whole -- which is exactly why standalone refuses to give its
# Custom and Portable layouts an independently invokable helper task.
Assert-True (
    $source -match
        '(?sm)^XfeElevatedHelperDirectory\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'return A_ProgramFiles "\\SteamShell-XFE\\bin"' -and
    $xfeDeployBody.Value -match
        'helperBinDirectory := XfeElevatedHelperDirectory\(\)' -and
    $xfeDeployBody.Value -notmatch
        'helperBinDirectory := targetDirectory') (
    "The XFE elevated helper is no longer installed below a protected Program Files path.")

# XFE never gets the on-demand HighestAvailable task. That task can be invoked
# with schtasks /run without asking the companion to re-check anything, so it is
# only safe below a protected ancestor chain Setup established for the WHOLE
# path -- which is the reason it was removed from Custom installs.
#
# REVISED. Setup still must not register it -- the companion does that itself,
# lazily, the first time the opt-in is actually used, so a machine that never
# enables elevated frame-cap writes never carries a HighestAvailable task.
#
# What made it unsafe before was not the task but WHERE the binary lived. The
# helper is under %ProgramFiles%\SteamShell-XFE\bin, which the interactive user
# cannot write, so `schtasks /run` cannot be pointed at anything replaceable.
Assert-True (
    $xfeDeployBody.Value -notmatch 'RegisterElevatedHelperTask\(' -and
    $xfeDeployBody.Value -notmatch 'EnsureXfeElevatedHelperTask\(') (
    "Setup must not register the XFE helper task; the companion registers it on first use.")
# ...and an uninstall must clear it, because Setup never created it and a stale
# HighestAvailable task pointing at a removed binary is the worst artefact an
# uninstall can leave behind.
Assert-True (
    $source -match
        '(?sm)^RemoveSteamShellXfeInstallation\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?RemoveXfeElevatedHelperTask\(\)' -and
    $source -match
        '(?sm)^RemoveXfeElevatedHelperTask\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"SteamShell XFE Elevated RTSS Helper"') (
    "Uninstall must remove the companion's opt-in elevated helper task.")
# The elevated helper is offered for deletion in EVERY installation mode. It
# lives in Program Files even for a Portable install, so it is never under the
# install directory and would otherwise survive an uninstall.
Assert-True (
    $source -match
        '(?sm)^BuildSteamShellRemovalPlan\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'helperDirectories := isXfe(?:(?!\n\})[\s\S])*?' +
        'SteamShellElevatedHelperDirectories\(installDirectory\)' +
        '(?:(?!\n\})[\s\S])*?directories\.Push\(helperDirectory\)' -and
    # BOTH candidate locations, so an uninstall never depends on which was
    # chosen -- or on the [Setup] record still being readable.
    $source -match
        '(?sm)^SteamShellElevatedHelperDirectories\(installDirectory := ""\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?A_ProgramFiles "\\SteamShell\\bin"' +
        '(?:(?!\n\})[\s\S])*?base "\\SteamShell\\bin"') (
    "Uninstall must offer every helper location, whichever the install chose.")
# An uninstall is routinely driven by a freshly downloaded SteamShell.exe, whose
# A_ScriptDir is the Downloads folder and whose own INI describes nothing. The
# portable helper location therefore has to come from the RESOLVED install
# directory, never from A_ScriptDir, or the search looks beside the download and
# quietly finds nothing.
Assert-True (
    $source -match
        '(?sm)^SteamShellElevatedHelperDirectories\(installDirectory := ""\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?base := RTrim\(Trim\(installDirectory\)' -and
    $source -match
        '(?sm)^BuildSteamShellRemovalPlan\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SteamShellElevatedHelperDirectories\(installDirectory\)' -and
    # ...and both locations must be RECOGNISED, or they are merely listed as
    # "not a folder SteamShell created" and left behind -- an administrator-owned
    # directory the user cannot delete themselves.
    $source -match
        '(?sm)^SteamShellRemovableDirectoryKind\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'A_ProgramFiles "\\SteamShell\\bin"(?:(?!\n\})[\s\S])*?' +
        'the protected elevated helper folder' -and
    $source -match
        '(?sm)^SteamShellRemovableDirectoryKind\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'installDirectory "\\SteamShell\\bin"' -and
    $source -match
        '(?sm)^SteamShellDirectoryContainsOurArtifacts\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?"SteamShell-Helper\.exe"') (
    "The helper directory must be found and recognised when uninstalling from a different folder.")


# The restore must never start RTSS: reapplying a cap is not a reason to launch
# a program the user did not ask for. It polls instead, because RTSS usually
# arrives after SteamShell through Steam or a startup entry.
Assert-True (
    $source -match
        '(?s)RestoreRtssFrameLimitTick\([^)]*\).*?RtssRestoreFrameLimitOnStartup.*?' +
        'deadlineTick.*?ProcessExist\("RTSS\.exe"\).*?' +
        'SetTimer\(RestoreRtssFrameLimitTick,\s*0\)' -and
    $source -match
        '(?s)RestoreRtssFrameLimitTick\([^)]*\).*?' +
        'state\["fps"\]\s*!=\s*RtssLastFrameCapFps.*?SetRtssGlobalFrameLimit' -and
    $source -match
        '(?s)RestoreRtssFrameLimitTick\([^)]*\).*?RtssFrameCapCustomMode\s*:=\s*' +
        '\(RtssLastFrameCapMode\s*=\s*"custom"\)' -and
    $source -match
        '(?sm)^RestoreRtssFrameLimitTick\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'state\["limiter"\](?:(?!\n\})[\s\S])*?!ApplyRtssGlobalState\("limiter",\s*false\)(?:(?!\n\})[\s\S])*?' +
        'return(?:(?!\n\})[\s\S])*?!state\["limiter"\](?:(?!\n\})[\s\S])*?' +
        '!ApplyRtssGlobalState\("limiter",\s*true\)(?:(?!\n\})[\s\S])*?return' -and
    $source -match
        '(?s)KickUserStartupPrograms\(\).*?SetTimer\(RestoreRtssFrameLimitTick,\s*2000\)' -and
    $source -match
        '(?s)"section", "RTSS", "key", "RestoreFrameLimitOnStartup"') (
    "The Frame Limit restore is disconnected, launches RTSS, or is missing from Settings.")

# RTSSHooks64.dll is loaded into whichever process calls it, so every profile
# write runs with that process's token and RTSS's default install is under
# Program Files. The helper runs the WHOLE sequence in its own process, which is
# what an elevated SteamShell used to do.
#
# An earlier design split it -- helper wrote the profile file, main kept the API
# calls. That persisted the global cap and reproduced neither RTSS's live
# display nor per-game profile saves. These assertions pin the sequence being
# whole and in one place.
Assert-True (
    $embeddedSchema.Contains("RTSS`0EnableElevatedFrameCapWrites") -and
    $source -match
        '(?s)"section", "RTSS", "key", "EnableElevatedFrameCapWrites"' -and
    # Both write paths go STRAIGHT to the helper when one exists. Trying
    # in-process first cannot succeed in the only session where a helper
    # exists, and for per-game profiles it was actively harmful: the read-back
    # re-reads the copy SetProfileProperty just wrote, so it passed while
    # SaveProfile had silently done nothing and the helper was never asked.
    $source -match
        '(?sm)^ElevatedRtssWritesAvailable\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ElevatedHelperAvailable\s*&&\s*RtssElevatedFrameCapWrites' -and
    # The gate now also confirms the helper PROCESS is alive -- see the
    # ElevatedHelperIsVerified assertion below for why the flags alone were not
    # enough. The claim here is unchanged: when a usable helper exists, the write
    # goes straight to it rather than being attempted in-process first.
    $source -match
        '(?sm)^SetRtssGlobalFrameLimit\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if\s*\(ProductElevatedHelperAlive\(\)\s*&&\s*ElevatedRtssWritesAvailable\(\)\)\s*\r?\n\s*' +
        'return\s+ApplyElevatedRtssFrameLimit\(fps\)' -and
    $source -match
        '(?sm)^SaveRtssFrameLimitToProfile\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if\s*\(ProductElevatedHelperAlive\(\)\s*&&\s*ElevatedRtssWritesAvailable\(\)\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?' +
        'ApplyElevatedRtssProfileFrameLimit\(exeName,\s*fps\)' -and
    # A cap is not logged as set until it has been proved.
    $source -notmatch
        '(?sm)^SetRtssGlobalFrameLimit\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'LogLine\("RTSS global FramerateLimit set to " fps "\."\)' +
        '(?:(?!\n\})[\s\S])*?readBack\s*:=' -and
    # Main verifies from RTSS and does NOT run any part of the write sequence
    # itself. setProfileProperty appearing here would be the split design
    # returning, which is the thing that did not work.
    # Main must WAIT for the helper before touching RTSS at all. Polling
    # RtssGlobalFrameLimit during the write called LoadProfile from a second
    # process and reloaded the profile out from under the helper's
    # SetProfileProperty, which is why a cap sometimes took several presses.
    $source -match
        '(?sm)^ApplyElevatedRtssFrameLimit\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RequestElevatedRtssFrameLimit\(fps\)(?:(?!\n\})[\s\S])*?' +
        '!WaitForElevatedRtssRequest\(\)(?:(?!\n\})[\s\S])*?' +
        'RtssGlobalFrameLimit\(\)\s*!=\s*fps' -and
    $source -notmatch
        '(?sm)^ApplyElevatedRtssFrameLimit\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'api\[' -and
    # The wait is uninterruptible, or the Quick Menu repaints the row mid-write
    # from RTSS's not-yet-updated value and a dialled Custom number jumps.
    $source -match
        '(?sm)^ApplyElevatedRtssFrameLimit\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'previousCritical\s*:=\s*Critical\("On"\)(?:(?!\n\})[\s\S])*?' +
        'Critical\(previousCritical\)' -and
    # Per-game saves prove themselves too. This reported success
    # unconditionally, so every unelevated user was told a profile had been
    # saved that RTSS never received.
    # A latched RtssFrameCapWriteBlocked must not refuse a per-game save: it
    # means in-process writes do not persist, which is what the helper is for.
    $source -match
        '(?sm)^SaveRtssFrameLimitToProfile\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'blockedReason\s*!=\s*""\s*&&\s*!RtssFrameCapWriteBlocked' -and
    $source -match
        '(?sm)^SaveRtssFrameLimitToProfile\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'GetRtssFrameLimit\(exeName\)(?:(?!\n\})[\s\S])*?' +
        'ApplyElevatedRtssProfileFrameLimit\(exeName,\s*fps\)(?:(?!\n\})[\s\S])*?' +
        # The failure NOTIFICATION, not a bare return false -- the catch block
        # further down has one of those, and it absorbed the mutation that
        # deleted this branch. What matters is that the user is told.
        'SharedNotify\(exeName\s*":\s*profile not saved"' -and
    $source -match
        '(?sm)^ApplyElevatedRtssProfileFrameLimit\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RequestElevatedRtssFrameLimit\(fps,\s*exeName\)(?:(?!\n\})[\s\S])*?' +
        '!WaitForElevatedRtssRequest\(\)(?:(?!\n\})[\s\S])*?' +
        'saved\["fps"\]\s*!=\s*fps' -and
    # The read-only latch clears when settings reload, or turning the elevated
    # write back on leaves the row dead until the next sign-in.
    $source -match
        '(?sm)^LoadSettings\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ReadBool\("RTSS",\s*"EnableElevatedFrameCapWrites",\s*true\)' +
        '(?:(?!\n\})[\s\S])*?RtssFrameCapWriteBlocked\s*:=\s*false' -and
    # Everything else first, Seq last: the helper acts on a sequence it has not
    # seen, so this ordering is what makes a torn read impossible.
    $source -match
        '(?sm)^RequestElevatedRtssFrameLimit\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'IniWrite\(fps,\s*requestPath,\s*"Request",\s*"Fps"\)(?:(?!\n\})[\s\S])*?' +
        'IniWrite\(profileName,\s*requestPath,\s*"Request",\s*"Profile"\)' +
        '(?:(?!\n\})[\s\S])*?' +
        'IniWrite\(RtssElevatedRequestSeq,\s*requestPath,\s*"Request",\s*"Seq"\)' -and
    # The completion is matched to the request that is being waited on.
    #
    # Resetting the completion event before issuing a request does not make a
    # stale completion impossible: the stale one arrives AFTER the reset. So the
    # wait has to ask which request finished and keep waiting when the answer is
    # somebody else's, rather than believing the first signal it sees.
    $source -match
        '(?sm)^WaitForElevatedRtssRequest\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'WaitForSingleObject(?:(?!\n\})[\s\S])*?' +
        'IniRead\(ElevatedRtssRequestPath\(\),\s*"Result",\s*"Seq",\s*"-1"\)' +
        '(?:(?!\n\})[\s\S])*?completed\s*=\s*RtssElevatedRequestSeq' -and
    # A request is not a setting: it never goes through the settings file. The
    # builder is shared now and asks ProductDataDir() where to write; this tree's
    # answer to that is the directory Setup can relocate, so both halves are
    # pinned -- the shared one for the filename, this one for the location.
    $source -match
        '(?sm)^ElevatedRtssRequestPath\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ProductDataDir\(\)\s*"\\rtss-request\.ini"' -and
    $source -match
        '(?sm)^ProductDataDir\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'return\s+SteamShellDataDir') (
    "The elevated RTSS path is split across processes, unverified, or per-game saves still report success blindly.")

# What the helper is allowed to be told, and where it may write.
#
# The settings file is user-writable in every installation mode, so [RTSS] Path
# is a hint that has to be corroborated. The Program Files roots come from HKLM
# because the helper inherits its environment from whoever started it --
# %ProgramFiles% is not evidence. GetFinalPathNameByHandle is what stops a
# junction redirecting an elevated write while every other check still passes,
# and it is also what makes loading a DLL out of that directory acceptable.
Assert-True (
    $helperSource -match
        '(?sm)^ElevatedRtssProgramFilesRoots\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion' -and
    $helperSource -notmatch 'EnvGet\("ProgramFiles' -and
    $helperSource -match
        '(?sm)^ElevatedRtssFinalPath\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'GetFinalPathNameByHandleW' -and
    $helperSource -match
        '(?sm)^ResolveElevatedRtssInstallDirectory\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'StrLower\(hintName\)\s*=\s*"rtss\.exe"(?:(?!\n\})[\s\S])*?' +
        'FileExist\(directory\s*"\\RTSS\.exe"\)(?:(?!\n\})[\s\S])*?' +
        'ElevatedRtssPathIsWithin\(installDirectory,\s*root\)' -and
    # RTSSHooks is loaded by FULL PATH from the gated directory. A bare
    # LoadLibrary would consult the search path, which is not something a
    # High-integrity process should resolve anything from.
    $helperSource -match
        '(?sm)^HelperRtssApi\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'ResolveElevatedRtssInstallDirectory\(&resolveFailure\)' +
        '(?:(?!\n\})[\s\S])*?' +
        'dllPath\s*:=\s*installDirectory\s*"\\RTSSHooks64\.dll"' +
        '(?:(?!\n\})[\s\S])*?LoadLibraryW",\s*"WStr",\s*dllPath' -and
    # The whole sequence, in this process. SaveProfile is the call that needs
    # the token and the one that silently did nothing in main.
    $helperSource -match
        '(?sm)^ApplyHelperRtssFrameLimit\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'api\["LoadProfile"\](?:(?!\n\})[\s\S])*?' +
        'api\["SetProfileProperty"\](?:(?!\n\})[\s\S])*?' +
        'api\["SaveProfile"\](?:(?!\n\})[\s\S])*?' +
        'api\["UpdateProfiles"\]' -and
    # One bounded integer, and an out-of-range value is discarded not clamped.
    $helperSource -match
        '(?sm)^HandleElevatedRtssRequest\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'fps\s*<\s*0\s*\|\|\s*fps\s*>\s*1000' -and
    # EVERY exit signals completion, refusals included.
    #
    # This assertion used to pin `try HandleElevatedRtssRequest / finally
    # SignalParentRtssRequestDone` -- which is precisely the shape that had the
    # bug. It covered the one path that does the work and left FOUR refusals
    # returning without signalling anything, while the comment sitting above
    # them claimed all of them signalled. Main waits 3000 ms with Critical on,
    # so each of those refusals was a three-second freeze of the Windows shell,
    # once per button press.
    #
    # What is pinned now is the property that actually makes "every exit
    # signals" true: the try OPENS BEFORE THE FIRST REFUSAL. Requiring the
    # EnableElevatedRtssFrameCap check to sit inside it is what makes this
    # falsifiable -- move the try back down and this fails.
    $helperSource -match
        '(?sm)^ServiceElevatedRtssRequest\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'try\s*\{(?:(?!\n\})[\s\S])*?' +
        '!EnableElevatedRtssFrameCap(?:(?!\n\})[\s\S])*?' +
        'RtssLastRequestSeq\s*:=\s*sequence(?:(?!\n\})[\s\S])*?' +
        'HandleElevatedRtssRequest\(sequence\)(?:(?!\n\})[\s\S])*?' +
        '\}\s*finally\s*\{\s*\r?\n\s*CompleteElevatedRtssRequest\(sequence\)' -and
    # The completion says WHICH request finished, and records it BEFORE it
    # signals. Without that, a completion belonging to a request that already
    # timed out satisfies the NEXT request's wait instantly, and main resumes
    # reading RTSS while this process is still mid-sequence on the new one --
    # the exact interleaving the completion event exists to prevent.
    $helperSource -match
        '(?sm)^CompleteElevatedRtssRequest\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'IniWrite\(sequence,\s*RtssRequestPath,\s*"Result",\s*"Seq"\)' +
        '(?:(?!\n\})[\s\S])*?SignalParentRtssRequestDone\(\)' -and
    # A per-game profile name is corroborated, never trusted: it must look like
    # a bare executable name AND name a process running right now. Both checks,
    # and the request is refused rather than sanitised if either fails.
    # Stated as what is REFUSED. An allowlist of [A-Za-z0-9 ._-] was tried and
    # is wrong for this: real game executables carry apostrophes, ampersands,
    # brackets and non-ASCII letters, so it silently refused to save profiles
    # for the games most likely to want one.
    $helperSource -match
        '(?sm)^ProfileNameIsAcceptable\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'StrLower\(SubStr\(name,\s*-4\)\)\s*!=\s*"\.exe"(?:(?!\n\})[\s\S])*?' +
        'RegExMatch\(name,\s*"\[(?:(?!\n\})[\s\S])*?' +
        'InStr\(name,\s*"\.\."\)' -and
    $helperSource -match
        '(?sm)^HandleElevatedRtssRequest\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '!ProfileNameIsAcceptable\(profileName\)(?:(?!\n\})[\s\S])*?' +
        'return(?:(?!\n\})[\s\S])*?' +
        '!HelperProcessImageIsRunning\(profileName\)(?:(?!\n\})[\s\S])*?' +
        'return' -and
    # A local named after a built-in class IS that class -- identifiers are
    # case-insensitive -- so `buffer := Buffer(...)` resolves the right-hand
    # side to the unassigned local and throws. This shipped once and reached a
    # user as a modal dialog on the shell desktop.
    $helperSource -notmatch
        '(?m)^\s*(?:buffer|array|map|object|file|func|gui|menu|error)\s*:=' -and
    # AutoHotkey's own uncaught-error dialog is not something this file opts
    # into, so forbidding MsgBox never covered it. OnError does.
    $helperSource -match 'OnError\(HandleUncaughtHelperError\)' -and
    $helperSource -match
        '(?sm)^HandleUncaughtHelperError\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'LogLine\((?:(?!\n\})[\s\S])*?ExitApp\(1\)(?:(?!\n\})[\s\S])*?return\s+1' -and
    # Off by setting, without a restart, like every other helper control.
    $helperSource -match
        'ReadBool\(\s*\r?\n?\s*"RTSS",\s*"EnableElevatedFrameCapWrites"') (
    "The helper's RTSS write is ungated, trusts the environment, loads its DLL unsafely, or accepts an uncorroborated profile name.")

# The helper's expected file version proves only that some file with that
# version resource is at the expected path. Write access to the binary or its
# directory is what actually decides whether elevating it is safe, so the DACL
# check must stay in front of every launch and Setup must apply it in every
# installation mode -- portable included, where nothing used to.
Assert-True (
    $source -match
        '(?sm)^SteamShellPathIsAdminOnlyWritable\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?' +
        'GetNamedSecurityInfoW(?:(?!\n\})[\s\S])*?GetAce(?:(?!\n\})[\s\S])*?ConvertSidToStringSidW(?:(?!\n\})[\s\S])*?' +
        'TRUSTED_SIDS' -and
    $source -match
        '(?sm)^SteamShellPathIsAdminOnlyWritable\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?' +
        'OWNER_SECURITY_INFORMATION(?:(?!\n\})[\s\S])*?TRUSTED_OWNER_SIDS(?:(?!\n\})[\s\S])*?' +
        'ownerPointer(?:(?!\n\})[\s\S])*?ownerSidText' -and
    $source -match
        '(?sm)^SteamShellPathIsAdminOnlyWritable\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?' +
        'ACE(?:(?!\n\})[\s\S])*?could not be read(?:(?!\n\})[\s\S])*?return false(?:(?!\n\})[\s\S])*?' +
        'could not be converted(?:(?!\n\})[\s\S])*?return false' -and
    $source -match
        '(?sm)^SteamShellPathIsAdminOnlyWritable\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?' +
        's-1-5-18(?:(?!\n\})[\s\S])*?s-1-5-32-544' -and
    $source -match
        '(?sm)^ElevatedHelperLocationIsProtected\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'helperDirectory(?:(?!\n\})[\s\S])*?SteamShellPathIsAdminOnlyWritable' -and
    $source -match
        '(?sm)^HardenElevatedHelperDirectory\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?icacls\.exe(?:(?!\n\})[\s\S])*?' +
        '/setowner(?:(?!\n\})[\s\S])*?S-1-5-32-544(?:(?!\n\})[\s\S])*?/inheritance:r(?:(?!\n\})[\s\S])*?' +
        'S-1-5-32-544(?:(?!\n\})[\s\S])*?S-1-5-32-545:\(OI\)\(CI\)RX' -and
    $source -match
        '(?sm)^StartElevatedInputHelper\(\)(?:(?!\n\})[\s\S])*?ExtractEmbeddedElevatedHelper(?:(?!\n\})[\s\S])*?' +
        'ElevatedHelperLocationIsProtected(?:(?!\n\})[\s\S])*?return false' -and
    $source -match
        # Harden, replace, harden again, verify. The second harden is not
        # redundant: the first cannot set the owner of a file that does not
        # exist yet, and a new file's owner comes from the creating token, which
        # on the default policy is the installing administrator's own SID rather
        # than Administrators. Without it the verification below refuses every
        # freshly deployed helper.
        '(?sm)^DeploySteamShell\([^)]*\)\s*\{' +
        '(?:(?!\n\})[\s\S])*?HardenElevatedHelperDirectory\(\s*\r?\n\s*' +
        'helperBinDirectory(?:(?!\n\})[\s\S])*?ExtractEmbeddedElevatedHelper\((?:(?!\n\})[\s\S])*?' +
        'helperDeployError,\s*true\)(?:(?!\n\})[\s\S])*?HardenElevatedHelperDirectory\(\s*\r?\n\s*' +
        'helperBinDirectory(?:(?!\n\})[\s\S])*?ElevatedHelperLocationIsProtected') (
    "The elevated helper is no longer gated on an administrator-only location.")
# Where a Portable install puts the helper is CHECKED, and only asked when the
# check says there is a trade to make.
#
# A scheduled task is an unprompted elevation to whatever binary sits at its
# action path, so the question is whether the interactive user can replace that
# binary -- and that is answerable directly rather than by asking the user to
# promise. A folder they cannot write is as safe as Program Files and keeps the
# install self-contained, so it is used without a prompt.
Assert-True (
    $source -match
        '(?sm)^DeploySteamShell\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'portableHelperChoice := "ProgramFiles"(?:(?!\n\})[\s\S])*?' +
        'SteamShellPathIsAdminOnlyWritable\(\s*\r?\n\s*targetDirectory' +
        '(?:(?!\n\})[\s\S])*?portableHelperChoice := "Portable"' -and
    # The prompt is an OWNED, dialog-active MsgBox like every other Setup
    # dialog, so it layers correctly and the controller can answer it.
    $source -match
        '(?sm)^DeploySteamShell\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'keepPortable := SetupAssistantMsgBox\(' -and
    $source -notmatch
        '(?sm)^DeploySteamShell\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'keepPortable := MsgBox\(' -and
    # ...and the decision is recorded, not re-derived from permissions that may
    # change after a task has already been registered against the old answer.
    $source -match
        '(?sm)^WriteSetupStateToIni\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'IniWrite\(portableHelperLocation, iniFile, "Setup", "PortableHelperLocation"\)' -and
    $source -match
        '(?sm)^SteamShellElevatedHelperDirectory\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"Setup", "PortableHelperLocation"') (
    "The portable helper location must be checked, offered only when it is a real choice, and recorded.")

# The helper log used to live in the writable data directory, where an elevated
# appender is a redirection target, and it never rotated at all.
Assert-True (
    $source -match
        '(?sm)^StartElevatedInputHelper\(\)(?:(?!\n\})[\s\S])*?SplitPath\(ElevatedHelperPath[^)]*\)(?:(?!\n\})[\s\S])*?' +
        'helperLog\s*:=\s*helperDirectory\s*"\\SteamShell-Helper\.log"' -and
    $helperSource -match
        '(?sm)^RotateHelperLogIfNeeded\([^)]*\)(?:(?!\n\})[\s\S])*?LogBackups(?:(?!\n\})[\s\S])*?LogMaxBytes(?:(?!\n\})[\s\S])*?FileMove' -and
    $helperSource -match
        '(?sm)^LogLine\([^)]*\)(?:(?!\n\})[\s\S])*?RotateHelperLogIfNeeded(?:(?!\n\})[\s\S])*?FileAppend' -and
    $helperSource -match
        'LogMaxBytes\s*:=\s*ReadInt\("Logging",\s*"LogRotateMaxKB"') (
    "The elevated helper log is no longer beside the protected binary or no longer rotates.")

# One name for one setting, across both products and the helper.
#
# The helper serves both trees and used to branch on --product= to read the same
# two values under two spellings -- [Companion] LogRotateMaxKB for XFE, [Logging]
# GameLogRotateMaxKB here. A branch like that is only ever as correct as the
# spellings it hard-codes: rename either side and the helper silently falls back
# to its defaults instead of honouring what the user set, which shows up as a log
# that grows without bound rather than as anything that fails.
#
# So the absence of the branch is the assertion, not just the presence of the new
# key. Schema 22 here and schema 18 in XFE carry the old values across.
Assert-True (
    $helperSource -notmatch 'GameLogRotate' -and
    $helperSource -notmatch 'HelperProduct\s*=\s*"xfe"[\s\S]{0,400}?LogRotateMaxKB' -and
    $source -notmatch 'GameLogRotate' -and
    $source -match 'LogRotateMaxKB\s*:=\s*ReadInt\("Logging",\s*"LogRotateMaxKB"' -and
    $source -match 'LogRotateBackups\s*:=\s*ReadInt\("Logging",\s*"LogRotateBackups"') (
    "Log rotation must be one setting under one name -- [Logging] LogRotateMaxKB " +
    "and LogRotateBackups -- with no GameLog-prefixed survivor and no per-product " +
    "branch in the elevated helper.")

# A rename is worthless if it strands the user's configured value.
Assert-True (
    $source -match '(?s)GetRetiredIniKeys\(\)\s*\{[\s\S]*?"GameLog"\s+rotateKey[\s\S]*?' +
        '"replacementKey",\s*"Log"\s+rotateKey') (
    "Schema 22 must carry GameLogRotateMaxKB/GameLogRotateBackups into their " +
    "unprefixed replacements rather than dropping them.")

# EnableElevatedInputHelper is a security control. One that only takes effect at
# the next boot is not one.
Assert-True (
    $source -match
        '(?sm)^StopElevatedHelper\([^)]*\)(?:(?!\n\})[\s\S])*?ProcessClose(?:(?!\n\})[\s\S])*?' +
        'ElevatedHelperAvailable\s*:=\s*false' -and
    $source -match
        '(?sm)^SyncElevatedInputHelperWithSettings\(\)(?:(?!\n\})[\s\S])*?' +
        'ReadElevatedHelperPreference\(\)(?:(?!\n\})[\s\S])*?StopElevatedHelper(?:(?!\n\})[\s\S])*?' +
        'StartElevatedInputHelper' -and
    $source -match
        '(?sm)^ReloadSettings\(\)(?:(?!\n\})[\s\S])*?SyncElevatedInputHelperWithSettings\(\)') (
    "Toggling the elevated helper off no longer stops the running helper.")

# The helper declines process-starting and window-raising builtins from a High
# token; main must keep handling exactly those, or a focused Task Manager leaves
# the on-screen keyboard unreachable by controller.
Assert-True (
    $source -match
        '(?sm)^ControllerBindingIsNormalIntegrityOnly\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'builtin:tabtip(?:(?!\n\})[\s\S])*?builtin:osk(?:(?!\n\})[\s\S])*?builtin:explorer(?:(?!\n\})[\s\S])*?' +
        'builtin:quickmenu(?:(?!\n\})[\s\S])*?builtin:controlpanel' -and
    $source -match
        '(?s)if ElevatedHelperOwnsForeground\(\)\s*\{\s*' +
        'ControllerHandleElevatedForeground' -and
    $source -match
        '(?sm)^ControllerHandleElevatedForeground\([^)]*\)(?:(?!\n\})[\s\S])*?chordActive(?:(?!\n\})[\s\S])*?' +
        'ControllerBindingIsNormalIntegrityOnly(?:(?!\n\})[\s\S])*?ExecuteControllerBinding' -and
    $helperSource -match
        '(?sm)^ExecuteBinding\([^)]*\)(?:(?!\n\})[\s\S])*?case "taskmanager"(?:(?!\n\})[\s\S])*?case "startmenu"(?:(?!\n\})[\s\S])*?' +
        'case "wing"(?:(?!\n\})[\s\S])*?case "ctrlalttab"' -and
    $helperSource -notmatch 'case "tabtip"' -and
    $helperSource -notmatch 'case "explorer"') (
    "The builtin split between the elevated helper and normal-integrity main has drifted.")

# A modal dialog from a process with no tray icon, on a shell desktop that may
# have no taskbar and no keyboard, is unrecoverable.
Assert-True (
    $helperSource -notmatch 'MsgBox' -and
    $helperSource -match
        '(?s)if !A_IsAdmin \{\s*LogLine\([^)]*High-integrity token' -and
    $helperSource -match
        'EnableQuickMenu\s*:=\s*ReadBool\("QuickMenu",\s*"Enable"' -and
    $helperSource -match
        'quickMenuChord\s*:=\s*EnableQuickMenu' -and
    $helperSource -match
        '(?s)PollIntervalMs\s*!=\s*previousInterval\s*\)\s*' +
        'SetTimer\(PollController,\s*PollIntervalMs\)') (
    "The elevated helper regained UI, or lost its Quick Menu gate or poll-rate reload.")

# RtlSecureZeroMemory is an inline winnt.h function, not an export. The DllCall
# that used to be here threw every time and a bare try hid it, so the plaintext
# Auto-Login password was never cleared.
Assert-True (
    $source -notmatch 'DllCall\(\s*\r?\n?\s*"Kernel32\\RtlSecureZeroMemory"' -and
    $source -match
        '(?sm)^StoreWindowsAutoLogonSecret\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'if IsObject\(passwordBuffer\)\s*\r?\n\s*DllCall\(\s*\r?\n?\s*' +
        '"Kernel32\\RtlZeroMemory"') (
    "The Auto-Login password buffer is not being zeroed with an exported function.")
Assert-True (
    $source -match
        '(?sm)^InitializeExpectedInteractiveIdentity\(\)' -and
    $source -match
        '(?s)FirstRunSetupMode\s*\{.*?if\s*!A_IsAdmin\s*\{.*?' +
        'PromptForAdministratorSetupAndExit\(\).*?' +
        'CloseExistingSteamShellInstancesForElevatedSetup' -and
    $source -match
        '(?sm)^SetupAssistantApply\([^)]*\)(?:(?!\n\})[\s\S])*?if\s*!A_IsAdmin(?:(?!\n\})[\s\S])*?' +
        'PromptForAdministratorSetupAndExit\(\)' -and
    $source -match
        '(?sm)^DeploySteamShell\([^)]*\)(?:(?!\n\})[\s\S])*?if\s*!A_IsAdmin(?:(?!\n\})[\s\S])*?' +
        'PromptForAdministratorSetupAndExit\(\)' -and
    $source -match
        '(?sm)^PromptForAdministratorSetupAndExit\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'WriteAdministratorSetupRequestMarker(?:(?!\n\})[\s\S])*?' +
        'Please Start SteamShell As Administrator for First Install or Upgrade(?:(?!\n\})[\s\S])*?' +
        'IntentionalExitMode\s*:=\s*"setup-admin-required"(?:(?!\n\})[\s\S])*?ExitApp' -and
    $source -match
        '(?sm)^ConsumeAdministratorSetupRequestMarker\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'UserSid=(?:(?!\n\})[\s\S])*?SessionId=(?:(?!\n\})[\s\S])*?ExpectedInteractiveUserSid(?:(?!\n\})[\s\S])*?' +
        'ExpectedInteractiveSessionId' -and
    $source -match
        '(?sm)^ElevatedSetupMatchesInteractiveDesktop\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'explorer\.exe(?:(?!\n\})[\s\S])*?desktopIntegrity(?:(?!\n\})[\s\S])*?medium(?:(?!\n\})[\s\S])*?' +
        'ExpectedInteractiveUserSid' -and
    $source -match
        '(?sm)^CloseExistingSteamShellInstancesForElevatedSetup\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'SteamShell\.exe(?:(?!\n\})[\s\S])*?CloseSteamShellProcessForSetup\(pid,\s*true\)(?:(?!\n\})[\s\S])*?' +
        'SteamShell-Helper\.exe(?:(?!\n\})[\s\S])*?CloseSteamShellProcessForSetup\(pid,\s*false\)' -and
    $source -match
        '(?s)elevatedSetupTakeoverRequested\s*:=\s*A_IsAdmin.*?' +
        'OtherSteamShellSetupProcessExists\(\).*?' +
        'FirstRunSetupMode\s*:=.*?elevatedSetupTakeoverRequested' -and
    $source -match
        '(?s)else\s*\{\s*StartElevatedInputHelper\(\)' -and
    $source -match
        '(?sm)^PollController\(\)(?:(?!\n\})[\s\S])*?ElevatedHelperOwnsForeground\(\)(?:(?!\n\})[\s\S])*?return' -and
    $source -match
        '(?sm)^RestartSteamShellInSafeMode\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        '--steamshell-user-sid=(?:(?!\n\})[\s\S])*?--steamshell-session-id=' -and
    $source -match
        '(?sm)^GetLinkedStandardUserToken\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'TokenElevationType(?:(?!\n\})[\s\S])*?TokenLinkedToken(?:(?!\n\})[\s\S])*?identity mismatch') (
    "Main/helper startup ownership or explicit administrator Setup takeover is disconnected.")
Assert-True (
    $helperSource -match '#NoTrayIcon' -and
    $helperSource -match "@Ahk2Exe-SetVersion $helperVersionPattern" -and
    $source -match
        "ElevatedHelperExpectedVersion\s*:=\s*`"$helperVersionPattern`"" -and
    $helperSource -match 'if\s*!A_IsAdmin' -and
    $helperSource -match 'ProcessIsElevatedIntegrity\(pid\)' -and
    $helperSource -match 'ParentPid\s*&&\s*!ProcessExist\(ParentPid\)' -and
    $helperSource -match
        '(?sm)^ProcessIsElevatedIntegrity\(pid\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'GetProcessTokenSecurity\((?:(?!\n\})[\s\S])*?' +
        'integrityName = "High" \|\| integrityName = "System"' -and
    $helperSource -match
        '(?s)GetProcessTokenSecurity\(\s*\r?\n?\s*selfPid.*?' +
        'GetProcessTokenSecurity\(\s*\r?\n?\s*' +
        'ParentPid.*?parentUserSid.*?parentSessionId.*?ExitApp' -and
    $helperSource -notmatch '(?m)^ProcessIntegrityRid\(' -and
    $helperSource -notmatch '(?m)^GetProcessIdentity\(' -and
    $helperSource -match 'XInputGetState' -and
    $helperSource -match 'ElevatedForeground\(&foregroundExe\)' -and
    $helperSource -match
        '(?sm)^ExecuteBinding\(key\)(?:(?!\n\})[\s\S])*?SubStr\(value,\s*1,\s*5\)\s*=\s*"Send:"(?:(?!\n\})[\s\S])*?return' -and
    $helperSource -notmatch 'SendInput\(sendValue\)') (
    "The elevated helper is no longer scoped to a live parent and High/System foreground windows.")
# Main and the helper both decide "is the foreground elevated?", and they must
# reach the SAME answer -- that question is how they agree which of them owns the
# controller. If they disagreed, a window would be serviced twice or not at all.
#
# The helper used to carry its own 38-line token walk testing the raw RID against
# 0x3000 while main compared integrity NAMES. They agreed only because
# GetProcessTokenSecurity maps 0x3000..0x3FFF to High and >= 0x4000 to System.
# Agreement by coincidence is not a property anyone was maintaining, and the
# helper's 62-line GetProcessIdentity was a second copy of the SID and session
# walk on top of it. Both are gone; both processes now call the one definition in
# SteamShell-Common.ahk.
Assert-True (
    $source -match
        '(?sm)^ElevatedHelperOwnsForeground\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'GetProcessTokenSecurity\((?:(?!\n\})[\s\S])*?' +
        'integrityName = "High" \|\| integrityName = "System"' -and
    $commonSource -match
        '(?sm)^GetProcessTokenSecurity\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'rid < 0x3000 \? "Medium"(?:(?!\n\})[\s\S])*?' +
        'rid < 0x4000 \? "High" : "System"') (
    "Main and the helper must decide 'elevated foreground' from the one shared definition.")
Assert-True (
    $helperSource -match
        '(?sm)^LoadConfiguration\(\)(?:(?!\n\})[\s\S])*?EnableWindowManagement(?:(?!\n\})[\s\S])*?' +
        'MinWidthPercent(?:(?!\n\})[\s\S])*?ExcludeExeList(?:(?!\n\})[\s\S])*?ExcludeClassList' -and
    $helperSource -match
        '(?sm)^ElevatedGeometryBuildItem\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        '!ProcessIsElevatedIntegrity\(pid\)(?:(?!\n\})[\s\S])*?' +
        'WmExcludeExeSet(?:(?!\n\})[\s\S])*?WmExcludeClassSet(?:(?!\n\})[\s\S])*?POPUP_CLASSES' -and
    $helperSource -match
        '(?m)^\s*return item\["x"\].*?item\["style"\]\s*$' -and
    $helperSource -match
        '(?sm)^ElevatedWindowGeometryTick\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'ParentAllowsElevatedGeometry(?:(?!\n\})[\s\S])*?MAX_ATTEMPTS(?:(?!\n\})[\s\S])*?' +
        'WinMove(?:(?!\n\})[\s\S])*?WinMaximize(?:(?!\n\})[\s\S])*?ElevatedGeometryState' -and
    # Two assertions, not one, because this rule is about two functions.
    #
    # It used to be a single unbounded pattern anchored on
    # OpenParentGeometryEvent that ran on past the end of it to find
    # ParentAllowsElevatedGeometry and its WaitForSingleObject. Bounding it to
    # the function it names was the only one of 131 that changed result, which
    # is how the overrun was found: opening the event and waiting on it are
    # different functions and each deserves its own assertion.
    $helperSource -match
        '(?sm)^OpenParentGeometryEvent\(\)(?:(?!\n\})[\s\S])*?' +
        'OpenEventW(?:(?!\n\})[\s\S])*?Local\\SteamShellGeometry-' -and
    $helperSource -match
        '(?sm)^ParentAllowsElevatedGeometry\(\)(?:(?!\n\})[\s\S])*?' +
        'WaitForSingleObject' -and
    $helperSource -match
        'SetTimer\(ElevatedWindowGeometryTick,\s*500\)' -and
    $source -match
        '(?sm)^EnsureElevatedGeometryEvent\(\)(?:(?!\n\})[\s\S])*?CreateEventW' -and
    $source -match
        '(?sm)^SetElevatedGeometryRuntimeEnabled\(enabled\)(?:(?!\n\})[\s\S])*?' +
        'SetEvent(?:(?!\n\})[\s\S])*?ResetEvent' -and
    $source -match
        '(?sm)^ApplyRuntimeTimers\(\)(?:(?!\n\})[\s\S])*?' +
        'SetElevatedGeometryRuntimeEnabled\(!DesktopMode\s*&&\s*!SafeMode\)' -and
    $source -match
        '(?sm)^WindowEngineGeometryHandledByHelper\(item\)(?:(?!\n\})[\s\S])*?' +
        'ElevatedHelperIsVerified(?:(?!\n\})[\s\S])*?GetProcessTokenSecurity(?:(?!\n\})[\s\S])*?' +
        'integrityName\s*=\s*"High"(?:(?!\n\})[\s\S])*?integrityName\s*=\s*"System"' -and
    $source -match
        '(?sm)^WindowEngineApplyGeometry\(snapshot\)(?:(?!\n\})[\s\S])*?' +
        'WindowEngineGeometryHandledByHelper\(item\)(?:(?!\n\})[\s\S])*?continue') (
    "Elevated geometry is not exclusively routed through the verified helper.")
Assert-True (
    $source -match
        '(?sm)^CreateProcessWithStandardToken\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'CreateEnvironmentBlock(?:(?!\n\})[\s\S])*?STARTUPINFOW(?:(?!\n\})[\s\S])*?CreateProcessWithTokenW(?:(?!\n\})[\s\S])*?' +
        '"WStr",\s*executable(?:(?!\n\})[\s\S])*?DestroyEnvironmentBlock' -and
    $source -match
        '(?sm)^GetLinkedStandardUserToken\([^)]*\)(?:(?!\n\})[\s\S])*?DuplicateTokenEx(?:(?!\n\})[\s\S])*?' +
        'SecurityImpersonation(?:(?!\n\})[\s\S])*?TokenPrimary' -and
    $source -match
        '(?sm)^CreateProcessWithStandardToken\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'EnableProcessTokenPrivilege\("SeImpersonatePrivilege"(?:(?!\n\})[\s\S])*?' +
        'Working directory is unavailable(?:(?!\n\})[\s\S])*?"WStr",\s*directory' -and
    $source -match
        '(?sm)^LaunchInteractiveApp\([^)]*\)(?:(?!\n\})[\s\S])*?' +
        'GetLinkedStandardUserToken(?:(?!\n\})[\s\S])*?CreateProcessWithStandardToken(?:(?!\n\})[\s\S])*?' +
        'RunViaDesktopShell') (
    "The verified linked-token process launcher is incomplete.")
Assert-True (
    $source -match
        '(?sm)^GetTokenInformationBuffer\([^)]*&informationBuffer[^)]*\)(?:(?!\n\})[\s\S])*?' +
        'informationBuffer\s*:=\s*Buffer\(needed,\s*0\)' -and
    $source -notmatch
        '(?sm)^GetTokenInformationBuffer\([^)]*&buffer(?:\s|,|\))') (
    "The token-information output parameter shadows AutoHotkey's Buffer class.")
Assert-True (
    $source -match
        '(?s)GetVerifiedDesktopShellPid\([^)]*\).*?' +
        'Shell_TrayWnd.*?GetProcessTokenSecurity.*?medium' -and
    $source -match
        '(?s)BootstrapVerifiedDesktopShell\([^)]*\).*?' +
        'Run\(.*?explorer\.exe.*?GetVerifiedDesktopShellPid' -and
    $source -match
        '(?s)LaunchInteractiveApp\([^)]*\).*?' +
        'BootstrapVerifiedDesktopShell.*?CaptureExecutablePidSet.*?' +
        'RunViaDesktopShell.*?WaitForNewExecutablePid' -and
    $source -match
        '(?s)RunViaDesktopShell\([^)]*\).*?' +
        'DesktopShellMatchesInteractiveUser.*?ShellExecute') (
    "Desktop-shell fallback is no longer restricted to the matching medium-integrity Explorer shell.")
Assert-True (
    $source -match
        '(?s)RunViaDesktopShell\([^)]*\).*?' +
        'DESKTOP_BROKER_TIMEOUT_MS.*?Loop\s*\{.*?' +
        'DesktopShellMatchesInteractiveUser.*?ShellExecute.*?Sleep\s+200') (
    "The desktop-shell fallback no longer waits for Explorer COM readiness at cold boot.")
Assert-True (
    $source -match
        '(?s)LaunchSteamBpm\(\).*?LaunchInteractiveApp\(.*?Steam Big Picture' -and
    $source -match
        '(?s)RunStartupCommandLine\([^)]*\).*?LaunchInteractiveApp\(' -and
    $source -match
        '(?s)StartSplashVideo_MPV\([^)]*\).*?LaunchInteractiveApp\(.*?MPV splash' -and
    $source -match
        '(?s)EnsureRtssRunning\(\).*?LaunchInteractiveApp\(.*?RTSS' -and
    $source -match
        '(?s)RestoreExplorerDesktop\([^)]*\).*?LaunchInteractiveApp\(.*?' +
        'Windows desktop restore') (
    "One or more ordinary external application launch sites bypass the standard-user boundary.")
$standardLaunchOnlyFunctions = @(
    "LaunchSteamBpm",
    "RunStartupCommandLine",
    "StartSplashVideo_MPV",
    "EnsureRtssRunning",
    "RestoreExplorerDesktop",
    "ExitSteamAndRestoreDesktop",
    "OpenOSK",
    "OpenWindowsSettings",
    "OpenLogFile",
    "SettingsEditorOpenIni",
    "SettingsEditorOpenRtss"
)
foreach ($functionName in $standardLaunchOnlyFunctions) {
    $functionPattern = '(?ms)^' + [regex]::Escape($functionName) +
        '\([^\r\n]*\)\s*\{.*?^\}'
    $functionMatch = [regex]::Match($source, $functionPattern)
    Assert-True $functionMatch.Success (
        "Could not inspect standard-user launch function ${functionName}.")
    Assert-True (
        $functionMatch.Value -notmatch '(?m)^\s*(?:try\s+)?Run\s*\(') (
        "$functionName contains a direct Run() call that can inherit SteamShell elevation.")
}
Assert-True (
    $source -match
        '(?s)if SafeMode.*?Background Explorer shell.*?' +
        'KickUserStartupPrograms\(\)') (
    "The medium-integrity Explorer broker is no longer established before startup programs.")
Assert-True (
    $source -match
        '"Standard-user launch capability"' -and
    $source -match
        '"Steam process integrity"' -and
    $source -match
        '"Explorer shell integrity"' -and
    $source -match
        '"RTSS process integrity"') (
    "Health Check no longer reports external-launch capability and process integrity.")

# The recorded pre-SteamShell shell must actually be read back somewhere. It was
# written by both registration paths and read by nothing for several releases,
# so the uninstall silently replaced a custom shell with explorer.exe and then
# deleted the only record of it.
Assert-True (
    $source -match
        '(?s)ResolveSavedPreviousShell\(\)\s*\{(?:(?!\n\})[\s\S])*?RegRead\([^)]*"PreviousShell"\).*?' +
        'ShellCommandExecutablePath') (
    "The saved PreviousShell value is no longer read back and verified.")
Assert-True (
    $source -match
        '(?s)RemoveSteamShellRegistration\([^)]*restorePreviousShell[^)]*\)\s*\{.*?' +
        'ResolveSavedPreviousShell.*?WriteAndVerifyShellValue') (
    "Uninstall no longer reinstates the shell registered before SteamShell.")
Assert-True (
    $source -match
        '(?s)RemoveSteamShellRegistration\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
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
        '(?s)ResolveRtssExecutablePath\(\)\s*\{(?:(?!\n\})[\s\S])*?ProgramFiles\(x86\).*?' +
        'RivaTuner Statistics Server\\RTSS\.exe' -and
    $source -match
        '(?s)EnsureRtssRunning\(\)\s*\{\s*path\s*:=\s*ResolveRtssExecutablePath\(\)' -and
    $source -match
        '(?s)GetRtssHooksApi\(\)\s*\{(?:(?!\n\})[\s\S])*?ResolveRtssExecutablePath\(\)') (
    "RTSS discovery is no longer centralized across launch, status, and DLL lookup paths.")
# /restore is the emergency path and must stay pinned to explorer.exe, and must
# stay product-independent: it is what a user reaches for when the desktop is
# gone, which cannot happen on an XFE machine. /uninstall is not an emergency, so
# it resolves the installed product first -- running the shell restore on an XFE
# machine would rewrite a Winlogon value SteamShell never set.
Assert-True (
    $source -match
        '\(mode\s*=\s*"restore"\)(?:(?!\bmode\b)[\s\S])*?' +
        'RemoveSteamShellRegistration\(true,\s*false\)' -and
    $source -match
        '\(mode\s*=\s*"uninstall"\)(?:(?!\bmode\b)[\s\S])*?' +
        'RemoveSteamShellInstallationForProduct\(true,\s*true\)') (
    "The /restore and /uninstall shell-restoration split has regressed.")

# The Win+Alt+B blind toggle is gone from this tree too, which is what let
# ToggleQuickMenuHdrState become one shared definition.
#
# This assertion used to require the opposite -- that the fallback existed and
# was reachable only from the toggle entry point. It was guarding a path that
# could not run: an unreadable HDR state produces a DIFFERENT row, id
# "hdrUnavailable", which is display-only here (handled in the value-text switch
# and in neither the adjust nor the activate switch) and action "none" in XFE.
# The chord could only ever have fired if the state became unreadable between
# the menu being built and the button being pressed.
#
# XFE has forbidden the chord since 0.1.14, on the evidence that 0.1.9 drove
# this row with the chord alone and no live state. Both trees now hold that rule,
# so the shared file cannot reintroduce it for either of them.
Assert-True (
    $source -notmatch 'SendChordSafe\("#!b"\)' -and
    $source -notmatch 'RequestHdrToggleFallback' -and
    $source -match
        '(?sm)^ToggleQuickMenuHdrState\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'SetQuickMenuHdrState\(!current\["enabled"\]\)') (
    "The blind Win+Alt+B HDR toggle is back, or the HDR toggle no longer acts on the live state.")

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

# The rule above is now a net over an empty floor, and this is what replaced the
# floor.
#
# Every composed read has been migrated to a typed reader, so there is no longer
# a second place for a default to disagree with the first. That makes the rule
# above unable to fire rather than merely satisfied -- which is exactly the kind
# of assertion this project keeps having to notice has gone quiet. It is kept
# because the composed form is still WRITEABLE; what stops it coming back is
# this.
#
# The bare IniReadS sites are deliberately excluded. They read a string and
# state one default, so they never had the defect; migrating them is a separate
# judgement about bounds, not a correctness fix.
$composedNumeric = @(
    [regex]::Matches(
        $rawSource,
        '(?:ClampInt|ClampFloat)\(\s*To(?:Int|Float)\(\s*IniReadS\(') |
        ForEach-Object { $_.Value }
)
Assert-True ($composedNumeric.Count -eq 0) (
    "The composed ClampInt(ToInt(IniReadS(...))) form is back in " +
    $composedNumeric.Count + " place(s). Use ReadInt or ReadNumber, which state " +
    "each default once.")

# EXACTLY ONE composed boolean read survives, and it is named here so its
# survival is a decision rather than an oversight.
#
# EnableMouseParkOnFocusChange takes its default from a LEGACY KEY when one is
# present -- EnableMouseParkEveryRefocus, retired but still honoured -- so its
# "default" is a computed expression rather than a literal. A typed reader takes
# one default and cannot express "read that other key first". Migrating it needs
# a legacy-aware variant, which is a separate decision about how long retired
# keys are honoured, not a mechanical rewrite.
#
# It never had the defect this whole migration is about: there is one default
# expression, used once.
$composedBool = @(
    [regex]::Matches($rawSource, 'ToBool\(\s*\r?\n?\s*IniReadS\(\s*"([^"]*)"\s*,\s*"([^"]*)"') |
        ForEach-Object { $_.Groups[2].Value }
)
Assert-True (
    $composedBool.Count -le 1 -and
    ($composedBool.Count -eq 0 -or $composedBool[0] -eq 'EnableMouseParkOnFocusChange')) (
    "A composed ToBool(IniReadS(...)) read is back, or the one legacy-chain " +
    "exception has moved: " + ($composedBool -join ", "))

# The typed readers must strip a trailing comment before parsing, or a
# documented settings file silently changes what every value means. This is the
# defect XFE shipped with: 46 of its settings now carry an inline explanation
# that its old reader would have read as part of the value.
Assert-True (
    $source -match
        '(?sm)^ReadText\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?CleanIniValue\(' -and
    $source -match
        '(?sm)^ReadIniBool\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?CleanIniValue\(' -and
    $source -match
        '(?sm)^ReadIniInt\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?CleanIniValue\(' -and
    $source -match
        '(?sm)^ReadNumber\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?CleanIniValue\(') (
    "A typed settings reader no longer strips inline comments through CleanIniValue.")

# The readers take their path from IniPath, and this tree also keeps
# SettingsPath. Every site that moves the settings file must move BOTH, or reads
# and writes address different files. Three sites do; this is what keeps it so.
Assert-True (
    ([regex]::Matches($rawSource, '(?m)^\s*SettingsPath\s*:=').Count -eq
     [regex]::Matches($rawSource, '(?m)^\s*IniPath\s*:=').Count)) (
    "SettingsPath and IniPath are no longer reassigned in step. The typed " +
    "readers use IniPath; anything that moves the settings file must move both.")

# The log must not grow without bound, and the rotation check must not cost a
# filesystem call on every line written.
Assert-True (
    $source -match
        '(?s)RotateLogIfNeeded\(\s*pendingBytes[^)]*\)\s*\{.*?static estimatedSize.*?FileGetSize' -and
    $source -match 'RotateLogIfNeeded\(StrLen\(line\)') (
    "Log rotation is missing or measures the file on every written line.")

# The XInput slot is DISCOVERED, never assumed to be the configured one.
#
# Steam Input and Xbox mode move a pad between slots while the process runs, so
# reading XInputGetState(ControllerIndex) directly meant the controller stopped
# answering mid-session with nothing wrong with it. That is worse here than in
# the companion: this product is the shell, and the recovery it left the user was
# to change Controller Index in Settings using the controller that had just
# stopped working. The literal call is named as forbidden because it is the exact
# line that regressed to.
Assert-True (
    $source -match
        '(?s)ControllerReadState\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?XInputResolveController\(' -and
    $source -match '(?s)XInputResolveController\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?Loop\s+4' -and
    $source -notmatch 'XInputGetState\(ControllerIndex') (
    "Automatic four-slot XInput discovery is missing, or ControllerReadState " +
    "went back to reading only the configured index.")

# The four-slot sweep is RATE-LIMITED, and the fast path is not.
#
# XInputGetState against an empty slot goes down to the device stack rather than
# returning a cached state, and the sweep above runs on every poll where the
# cached slot does not answer -- which, with no controller attached, is every
# poll. At a 16 ms interval that was roughly 250 of those calls a second.
#
# Both halves are asserted because either one alone is a bug. Without the gate
# the cost comes back; without the fast path ahead of the gate, a CONNECTED
# controller would be throttled too, which would put input latency behind a
# backoff interval -- far worse than the cost this removes.
Assert-True (
    $source -match '(?ms)^XInputScanGate\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?nextAllowedTick' -and
    $source -match
        '(?ms)^XInputResolveController\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?XInputGetState\(ActiveControllerIndex(?:(?!\n\})[\s\S])*?XInputScanGate\(\)') (
    "The all-slots XInput sweep must be rate-limited by XInputScanGate, and the " +
    "cached-slot read must happen BEFORE the gate so a connected controller is " +
    "never throttled.")

# Resume must be detected without relying on WM_POWERBROADCAST, which is not
# reliably delivered under modern standby -- the state a handheld sleeps into.
#
# The same assertion the companion carries, and it is here because this tree had
# NO resume path at all: the power handler, the device-lock reset and the
# re-registration were written in the companion, and not one of them was ever
# called from the shell. It got by on RawInputClaimDevice's handover, which
# recovers a stale device handle and does nothing for a registration that did not
# come back.
#
# WALL CLOCK, NOT A_TickCount, is the load-bearing detail: the tick counter does
# not advance through suspend, so a gap check written on ticks silently reports
# that the machine never slept.
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
    $source -match '(?m)^\s*if QuickMenuActivateShared\(id\) \{') (
    "QuickMenuActivateSelected must pass its own id to QuickMenuActivateShared; " +
    "the other tree's variable name is an unassigned local here.")
Assert-SharedParity -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-QuickMenuRows -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-SettingsRowsReachConsumers -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-CrossNameAnchors -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-BindingLabelTables -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-GameScoreWeightKeys -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-ElevatedHelperProtocol -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-ControllerPollFrame -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-ControllerSurfaceParity -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-AutoMouseDefaults -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-RecentApplicationPicker -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-CurrentApplicationTargets -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-QuickMenuPageChangesRebuild -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-ControllerLearnerIdentifyRelease -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-RtssUnreadableIsNotOff -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-ValidatorAssertionShapes -ProjectRoot $projectRoot -Quiet:$Quiet
Assert-NoAmbiguousDeindentedBlocks -ProjectRoot $projectRoot -File "SteamShell.ahk" -Quiet:$Quiet
Assert-NoAmbiguousDeindentedBlocks -ProjectRoot $projectRoot -File "SteamShell-Shared.ahk" -Quiet:$Quiet
Assert-NoAmbiguousDeindentedBlocks -ProjectRoot $projectRoot -File "SteamShell-Common.ahk" -Quiet:$Quiet
# Reports only. See Report-StructuralDrift in Validate-Common.ps1 for why a
# high structural score is evidence rather than a verdict.
# The fit check must ask the LAYOUT for its bottom margin, not restate it.
#
# Both trees carried `Round(statusHeight * 0.45)` -- 16/36 rounded up and frozen
# as a constant. At 300% scale the layout leaves 48 physical pixels and that
# expression demands 49, so the Quick Menu grew a pixel, re-centred and logged a
# Warning on EVERY open. Ten in two minutes of ordinary use, drowning the signal
# the warning exists to carry.
#
# The guarantee is that the requirement is derived from the two functions that
# define the layout, so it cannot disagree with what the layout actually does.
Assert-True (
    $source -match
        '(?s)QuickMenuFitContent\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'QuickMenuMeasuredBottomMargin\(statusHeight\)' -and
    $source -notmatch 'statusHeight \* 0\.45') (
    "The Quick Menu fit check restates the layout's bottom margin instead of " +
    "deriving it, which logs a spurious grow-and-recentre at some DPI scales.")

Report-StructuralDrift -ProjectRoot $projectRoot -Quiet:$Quiet | Out-Null

if (-not $Quiet) {
    $callbackCount = @($callbackReferences | ForEach-Object { $_.Name } | Sort-Object -Unique).Count
    Write-Host (
        "Static validation passed: {0} functions, {1} settings keys, {2} Quick Menu rows, {3} named callbacks." -f
        $functionNames.Count,
        $embeddedSchema.Count,
        $quickMenuIds.Count,
        $callbackCount)
    # Sources read, and what that cost. Printed so the next round of harness
    # tuning has a number instead of an argument about whether this validator is
    # bound by file I/O or by regex.
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

# ==============================================================================
# UNINSTALL MUST NOT LEAVE THE MACHINE LOOKING INSTALLED
# ==============================================================================
# Both uninstalls deliberately keep the executable and its settings, and say so
# to the user. That makes file presence useless as a test of what is installed:
# a removed XFE left its recorded path pointing at a file that still existed,
# detection read the pair as "XFE is installed", and because XFE is tested first
# it reported XFE over a shell installation that was genuinely there. Setup then
# offered to remove the product that was already gone.
Assert-True (
    $rawSource -match
        '(?sm)^RemoveSteamShellXfeInstallation\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RegDelete\(SteamShellRegKey,\s*"XfeInstalledPath"\)' -and
    $rawSource -match
        '(?sm)^RemoveSteamShellXfeInstallation\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RegDelete\(SteamShellRegKey,\s*"XfeHelperDeployed"\)') (
    "XFE uninstall no longer clears its location records, so the machine will " +
    "report XFE as installed forever after.")

# Detection asks what is REGISTERED TO START, never what exists on disk.
Assert-True (
    $rawSource -match
        '(?sm)^DetectExistingSteamShellInstallation\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if\s*\(xfeStartsAtLogon\s*\|\|\s*xfeRegisteredFlag\)' -and
    $rawSource -notmatch
        '(?sm)^DetectExistingSteamShellInstallation\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if\s*\(xfeStartsAtLogon\s*\|\|\s*xfeOnDisk\)' -and
    $rawSource -match
        '(?sm)^ResolveInstalledSteamShellProduct\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'xfeRegistered\s*:=\s*SteamShellXfeLogonTaskExists\(\)') (
    "Product detection is reading file presence again. Both uninstalls leave " +
    "files behind, so that answers 'was this ever installed', not 'is it now'.")

# Standalone's on-demand helper task is removed unconditionally.
#
# It used to be gated on the HelperTaskRegistered flag, which Setup writes at the
# end. Anything that created the task without reaching that point left it
# behind, and a stale HighestAvailable task pointing at a binary is the worst
# artefact an uninstall can leave. schtasks reports failure harmlessly when
# there is no such task, so there is nothing to gate on.
Assert-True (
    $rawSource -match
        '(?sm)^RemoveSteamShellRegistration\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if\s*\(!RemoveElevatedHelperTask\(\)\s*&&\s*helperTaskWasRegistered\)') (
    "The elevated helper task removal is gated on a registry flag again; a task " +
    "created outside a completed Setup would survive uninstall.")

# The whole SteamShell key is only ever deleted once it is empty, and only from
# the product-scoped helper. Deleting it outright took the other product's
# InstalledPath, DataPath, InstallationMode and PreviousShell with it -- the last
# being what a later restore needs to put the user's original shell back.
Assert-True (
    ([regex]::Matches($rawSource, 'RegDeleteKey\(').Count -eq 1) -and
    $rawSource -match
        '(?sm)^RemoveSteamShellRegistryRecordForProduct\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'Loop Reg(?:(?!\n\})[\s\S])*?remaining = 0(?:(?!\n\})[\s\S])*?RegDeleteKey\(') (
    "The SteamShell registry key is being deleted outside the product-scoped " +
    "helper, or without first checking that nothing else is recorded in it.")

# Detection failing is not the same as nothing being installed, so Setup
# Assistant must offer the product prompt rather than dead-ending.
#
# ChooseSteamShellProductToRemove already existed for this and was reachable only
# from /uninstall on the command line; Setup Assistant answered a failed
# detection with "nothing was detected. Nothing was changed." and no way forward.
# Tightening detection to ask what is REGISTERED made that reachable in ordinary
# cases: an XFE install whose logon task was declined, a shell whose Winlogon
# value was already restored, and the documented workflow of uninstalling from a
# freshly downloaded EXE against a partly-cleaned registry.
Assert-True (
    $rawSource -match
        '(?sm)^SetupAssistantUninstall\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if !DetectExistingSteamShellInstallation\((?:(?!\n\})[\s\S])*?' +
        'ChooseSteamShellProductToRemove\(' -and
    $rawSource -notmatch
        '(?sm)^SetupAssistantUninstall\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'No installed SteamShell or SteamShell-XFE was detected') (
    "Setup Assistant dead-ends when detection fails instead of letting the user " +
    "say which product is installed.")

# Both sign-in checkboxes are set on BOTH product branches.
#
# Each branch used to set only its own product's box, so the other kept the
# "Checked" it was created with: shell mode showed "Start SteamShell-XFE
# automatically at sign-in" ticked. Disabling it is not sufficient -- a ticked
# box states an intention regardless of whether it can be clicked.
Assert-True (
    $rawSource -match
        '(?sm)^SetupAssistantRefreshProductMode\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if isXfe \{(?:(?!\n\})[\s\S])*?' +
        '"SetupRegisterShell"\]\.Value := 0(?:(?!\n\})[\s\S])*?' +
        '"SetupRegisterXfeStartup"\]\.Value := 1' -and
    $rawSource -match
        '(?sm)^SetupAssistantRefreshProductMode\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '\} else \{(?:(?!\n\})[\s\S])*?' +
        '"SetupRegisterShell"\]\.Value := 1(?:(?!\n\})[\s\S])*?' +
        '"SetupRegisterXfeStartup"\]\.Value := 0') (
    "A product branch in SetupAssistantRefreshProductMode leaves the other " +
    "product's sign-in checkbox at whatever it was, so both can show ticked.")

# ...and product mode is applied even when nothing was preselected.
#
# Its only other callers are the product radios and the preselect, and preselect
# returns early on a PC with nothing installed. Without this the FIRST-RUN case --
# the one every new user sees -- opened with both checkboxes ticked and enabled.
Assert-True (
    $rawSource -match
        'preselected := SetupAssistantPreselectExistingInstallation\(\)' +
        '(?:(?!\n\})[\s\S])*?if !preselected\s*\n\s*' +
        'SetupAssistantRefreshProductMode\(\)') (
    "Setup Assistant no longer applies the product mode when nothing was " +
    "preselected, so a clean PC opens with both products' checkboxes ticked.")

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

# A list box owns its own mouse wheel.
#
# This window has a category ListBox, and the wheel handler excluded only
# SysListView32 -- so hovering the category list and scrolling moved the settings
# page instead of the list. The companion had the exclusion and the difference
# was recorded as deliberate, which is how it survived.
#
# One handler for both products now, so this protects both. Against $source
# rather than $rawSource, because the body lives in SteamShell-Common.ahk.
Assert-True (
    $source -match
        '(?sm)^SettingsWheelNotch\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'controlClass = "ListBox" \|\| controlClass = "SysListView32"') (
    "The Settings wheel handler no longer excludes ListBox, so scrolling over " +
    "the category list moves the page instead of the list.")

# A portable installation can be upgraded.
#
# InstalledPath is written only by the "if !portableMode" branch, so a portable
# copy records neither it nor InstallationMode. What it does record, once it is
# the registered shell, is RegisteredPath -- written inside "if registerShell",
# which portable installs take. Detection therefore knew such an install was
# Standalone, from the registration, and had nowhere to point: Setup Assistant
# could not preselect the folder it was being asked to upgrade.
#
# The second half matters more than the first. Preselect never restored the
# Portable checkbox, and SetupAssistantGetDeployment reads exactly the browse
# radio and that box -- so an upgrade came back as "Custom", which demands
# administrator approval and moves the data into ProgramData. A portable
# installation would have been converted into a managed one because a checkbox
# was not ticked back.
Assert-True (
    $rawSource -match
        '(?sm)^ResolveInstalledShellExecutable\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '"InstalledPath"(?:(?!\n\})[\s\S])*?"RegisteredPath"(?:(?!\n\})[\s\S])*?' +
        'ShellCommandExecutablePath\(configured\)' -and
    $rawSource -match
        '(?sm)^DetectExistingSteamShellInstallation\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'installedExe := ResolveInstalledShellExecutable\(\)' -and
    $rawSource -match
        '(?sm)^InstalledShellIsPortable\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if \(Trim\(recorded\) != ""\)(?:(?!\n\})[\s\S])*?return false' -and
    $rawSource -match
        '(?sm)^SetupAssistantPreselectExistingInstallation\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'InstalledShellIsPortable\(\)(?:(?!\n\})[\s\S])*?' +
        '"SetupPortable"\]\.Value := 1(?:(?!\n\})[\s\S])*?' +
        'SetupAssistantRefreshDeployment\(\)') (
    "A portable installation cannot be upgraded in place: Setup Assistant either " +
    "cannot find where it lives, or comes back as Custom and converts it to a " +
    "managed install.")

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

# The verdict is OFFERED and never enforced, and this is the assertion that
# matters most in this area.
#
# SetupAssistantRequired decides whether the shell runtime starts at all. A
# record whose recorded path disagrees with reality must never reach it: a stale
# string in a settings file would then be able to leave a machine sitting in
# Setup with no shell, which is far worse than the wrong path it was reporting.
# It may read SetupState, SetupVersion and Product -- that is long-standing,
# deliberate behaviour -- and nothing else.
Assert-True (
    $rawSource -notmatch
        '(?sm)^SetupAssistantRequired\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        '(InstallationRecordAlert|CachedInstallationVerdict|SteamShellInstallationVerdict|SteamShellSetupRecordDrift)' -and
    $rawSource -match
        '(?sm)^SetupAssistantRequired\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'return setupState != "complete" \|\| setupVersion < 1' -and
    # ...and it is surfaced where a user can act on it without being forced to.
    # Declared in ProductTrayItems now rather than added imperatively. The claim
    # is unchanged: it is offered in the tray, where the user can ignore it.
    $rawSource -match '"label", "Installation moved') (
    "The installation verdict can now block the shell from starting, or is no " +
    "longer offered anywhere the user can act on it.")

# Every elevated RTSS write is gated on the helper PROCESS, not just the flags.
#
# ElevatedRtssWritesAvailable() is ElevatedHelperAvailable && RtssElevatedFrameCapWrites
# -- two flags. A helper that exits mid-session leaves both set, so the write was
# posted to nothing and WaitForElevatedRtssRequest burned its full 3000 ms under
# Critical("On"): a hard-frozen UI, and twice in one call on the global cap path,
# which had a gate on the fast path and none on the read-back fallback. Never
# having had a helper was always safe -- RequestElevatedRtssFrameLimit returns
# false immediately -- so it is specifically the death mid-session that this
# catches. ElevatedHelperIsVerified() already existed and does ProcessExist plus
# an identity re-check on a one-second cache.
Assert-True (
    # $source, not $rawSource: the four gated writes moved into
    # SteamShell-Shared.ahk when the two frame-cap functions were unified, and
    # counting the unresolved tree would find none of them.
    ([regex]::Matches($source,
        'ProductElevatedHelperAlive\(\)\s*&&\s*ElevatedRtssWritesAvailable\(\)').Count -eq 4) -and
    # The bare flag test must not come back as a gate of its own. The nested
    # ApplyElevatedRtssProfileFrameLimit call is NOT listed here: it sits inside
    # the gated block above, so requiring a gate on it too would be wrong.
    $rawSource -notmatch '(?m)^\s*if ElevatedRtssWritesAvailable\(\)' -and
    $rawSource -notmatch '(?m)^\s*if ApplyElevatedRtssFrameLimit\(fps\)') (
    "An elevated RTSS write is reachable without confirming the helper process " +
    "is alive, which costs a three-second frozen UI when it has exited.")

# RTSS being absent is reported, not swallowed.
Assert-True (
    $source -match
        '(?sm)^ApplyRtssGlobalState\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if !EnsureRtssRunning\(\) \{(?:(?!\n\})[\s\S])*?' +
        'SharedNotify\("RTSS was not found') (
    "Selecting an RTSS row with RTSS missing returns silently again, which on a " +
    "couch UI is indistinguishable from the menu being broken.")

# ...and so is the read-back failure that latches the row read-only.
Assert-True (
    $source -match
        '(?sm)^SetRtssGlobalFrameLimit\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'RtssFrameCapWriteBlocked := true(?:(?!\n\})[\s\S])*?' +
        'SharedNotify\((?:(?!\n\})[\s\S])*?"RTSS did not keep the frame cap"') (
    "The frame cap latches read-only for the session without telling the user, " +
    "so the row simply stops responding with no reason given on screen.")

# A hand-picked removal must not be described as a detected one.
Assert-True (
    $rawSource -match
        '(?sm)^SetupAssistantUninstall\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'chosenByHand(?:(?!\n\})[\s\S])*?Remove the installation you chose\?') (
    "The uninstall confirmation claims the installation was detected even when " +
    "the user picked it by hand.")

# Removing the XFE logon task succeeds when there is no task to remove.
#
# schtasks /delete exits non-zero for a task that does not exist, and this
# returned that as failure. RemoveSteamShellXfeInstallation returns the value
# straight through, so an uninstall with nothing to remove told the user it could
# not be fully removed while every other step had succeeded -- including the
# hand-picked path above, which is reached precisely because nothing is
# registered.
Assert-True (
    $rawSource -match
        '(?sm)^RemoveXfeLogonTask\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?' +
        'if SteamShellXfeLogonTaskExists\(name\)(?:(?!\n\})[\s\S])*?' +
        'failed := true(?:(?!\n\})[\s\S])*?return !failed' -and
    $rawSource -match
        '(?sm)^SteamShellXfeLogonTaskExists\(name := ""\)') (
    "RemoveXfeLogonTask reports failure when the task was simply absent, which " +
    "makes a successful uninstall look broken.")

# ==============================================================================
# EVERY DIALOG IS OWNED OR TOPMOST
# ==============================================================================
# A dialog that opens behind a fullscreen game is a machine that appears to have
# hung. Owning it to a SteamShell window is right when one is active; when none
# is, MB_TOPMOST is the only thing that puts it in front. Each helper must pick
# one -- AutoLogonDialogMessage asked for neither when its window did not exist.
foreach ($dialogHelper in @(
    "SettingsEditorMsgBox", "SteamShellMsgBox",
    "SetupAssistantMsgBox", "AutoLogonDialogMessage")) {
    Assert-True (
        $rawSource -match
            ('(?sm)^' + $dialogHelper + '\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?Owner') -and
        $rawSource -match
            ('(?sm)^' + $dialogHelper + '\([^)]*\)\s*\{(?:(?!\n\})[\s\S])*?262144')) (
        "$dialogHelper no longer chooses between an owner window and MB_TOPMOST, " +
        "so its dialog can open behind whatever is in front.")
}
# And no sixth way to open one. Five raw MsgBox calls exist: the four helpers
# above, plus the Health Check export which owns itself to a window it has
# already confirmed is visible.
Assert-True (
    ([regex]::Matches($rawSource, '(?<![A-Za-z])MsgBox\(').Count -eq 5)) (
    "A dialog is being opened outside the helpers that guarantee it appears in " +
    "front. Route it through SetupAssistantMsgBox or SettingsEditorMsgBox.")
