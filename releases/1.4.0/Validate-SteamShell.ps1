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

$requiredFunctions = @(
    "RestoreExplorerDesktop",
    "GetSteamShellHealthResults",
    "CreateSettingsBackup",
    "ApplySafeModeOverrides",
    "ShowControllerTest",
    "SettingsEditorSetRedraw"
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

$trailingWhitespace = [regex]::Matches($source, '(?m)[ `t]+$')
Assert-True ($trailingWhitespace.Count -eq 0) "SteamShell.ahk contains trailing whitespace."
Assert-True ($source -match 'GuiLiteralText\(title\)') (
    "Settings headings are not using literal-ampersand rendering.")

if (-not $Quiet) {
    Write-Host (
        "Static validation passed: {0} functions, {1} settings keys." -f
        $functionNames.Count,
        $embeddedSchema.Count)
}
