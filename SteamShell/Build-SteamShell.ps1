param(
    [string]$OutputPath = "",
    [string]$IconPath = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePath = Join-Path $projectRoot "SteamShell.ahk"
$validatorPath = Join-Path $projectRoot "Validate-SteamShell.ps1"

if (-not (Test-Path $sourcePath)) {
    throw "SteamShell.ahk was not found beside this build script."
}
if (-not (Test-Path $validatorPath)) {
    throw "Validate-SteamShell.ps1 was not found beside this build script."
}

Write-Host "Running SteamShell static validation..."
& $validatorPath

$autoHotkeyRoots = @(
    (Join-Path $env:ProgramFiles "AutoHotkey"),
    (Join-Path ${env:ProgramFiles(x86)} "AutoHotkey"),
    (Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey")
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$compilerCandidates = @(
    $autoHotkeyRoots |
        ForEach-Object { Join-Path $_ "Compiler\Ahk2Exe.exe" } |
        Where-Object { Test-Path $_ }
)

$baseCandidates = @(
    $autoHotkeyRoots |
        ForEach-Object { Join-Path $_ "v2\AutoHotkey64.exe" } |
        Where-Object { Test-Path $_ }
)

if ($compilerCandidates.Count -eq 0) {
    throw "Ahk2Exe was not found. Install AutoHotkey v2 and include its compiler."
}
if ($baseCandidates.Count -eq 0) {
    throw "An AutoHotkey v2 64-bit base executable was not found."
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $distPath = Join-Path $projectRoot "dist"
    New-Item -ItemType Directory -Path $distPath -Force | Out-Null
    $OutputPath = Join-Path $distPath "SteamShell.exe"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectRoot $OutputPath
}

$arguments = @(
    "/in", $sourcePath,
    "/out", $OutputPath,
    "/base", $baseCandidates[0],
    "/compress", "0",
    "/silent", "verbose"
)

if ([string]::IsNullOrWhiteSpace($IconPath)) {
    $defaultIconPath = Join-Path $projectRoot "assets\SteamShell.ico"
    if (Test-Path $defaultIconPath) {
        $IconPath = $defaultIconPath
    }
}

if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
    if (-not [System.IO.Path]::IsPathRooted($IconPath)) {
        $IconPath = Join-Path $projectRoot $IconPath
    }
    if (-not (Test-Path $IconPath)) {
        throw "Icon file not found: $IconPath"
    }
    $arguments += @("/icon", $IconPath)
}

Write-Host "Validating SteamShell syntax with AutoHotkey v2..."
Write-Host "64-bit interpreter: $($baseCandidates[0])"
$interpreterVersion = (Get-Item -LiteralPath $baseCandidates[0]).VersionInfo.FileVersion
if (-not [string]::IsNullOrWhiteSpace($interpreterVersion)) {
    Write-Host "Interpreter version: $interpreterVersion"
}
$syntaxOutput = @(
    & $baseCandidates[0] "/ErrorStdOut=UTF-8" "/Validate" $sourcePath 2>&1 |
        ForEach-Object { "$_" }
)
$syntaxExitCode = $LASTEXITCODE
if ($syntaxOutput.Count -gt 0) {
    $syntaxOutput | ForEach-Object { Write-Host $_ }
}
if ($syntaxExitCode -ne 0) {
    $diagnosticHint = if ($syntaxOutput.Count -eq 0) {
        " AutoHotkey returned no diagnostic text; run the displayed interpreter with /ErrorStdOut=UTF-8 /Validate and the source path."
    } else {
        ""
    }
    throw (
        "AutoHotkey syntax validation failed with exit code " +
        $syntaxExitCode + ". The compiler was not started." + $diagnosticHint)
}

Write-Host "Compiling SteamShell with AutoHotkey v2..."
Write-Host "Compiler: $($compilerCandidates[0])"
Write-Host "Base executable: $($baseCandidates[0])"
Write-Host "Output: $OutputPath"
if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
    Write-Host "Icon: $IconPath"
}
$compilerOutput = @(
    & $compilerCandidates[0] @arguments 2>&1 |
        ForEach-Object { "$_" }
)
$compilerExitCode = $LASTEXITCODE
if ($compilerOutput.Count -gt 0) {
    $compilerOutput | ForEach-Object { Write-Host $_ }
}

if ($compilerExitCode -ne 0 -or -not (Test-Path $OutputPath)) {
    $outputState = if (Test-Path $OutputPath) {
        "The output file exists, but Ahk2Exe reported failure."
    } else {
        "The output file was not created."
    }
    $diagnosticHint = if ($compilerOutput.Count -eq 0) {
        " Ahk2Exe returned no diagnostic text; verify that the output is not running or locked and that security software did not quarantine it."
    } else {
        ""
    }
    throw (
        "Ahk2Exe failed with exit code " + $compilerExitCode + ". " +
        $outputState + $diagnosticHint)
}

Write-Host "Built: $OutputPath"
