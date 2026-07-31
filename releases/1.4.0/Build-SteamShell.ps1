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

$compilerCandidates = @(
    (Join-Path $env:ProgramFiles "AutoHotkey\Compiler\Ahk2Exe.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "AutoHotkey\Compiler\Ahk2Exe.exe")
) | Where-Object { $_ -and (Test-Path $_) }

$baseCandidates = @(
    (Join-Path $env:ProgramFiles "AutoHotkey\v2\AutoHotkey64.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "AutoHotkey\v2\AutoHotkey64.exe")
) | Where-Object { $_ -and (Test-Path $_) }

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
& $baseCandidates[0] "/Validate" "/ErrorStdOut=UTF-8" $sourcePath
if ($LASTEXITCODE -ne 0) {
    throw "AutoHotkey syntax validation failed. The compiler was not started."
}

Write-Host "Compiling SteamShell with AutoHotkey v2..."
& $compilerCandidates[0] @arguments

if ($LASTEXITCODE -ne 0 -or -not (Test-Path $OutputPath)) {
    throw "Ahk2Exe did not produce the expected executable."
}

Write-Host "Built: $OutputPath"
