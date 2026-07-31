param(
    [string]$OutputPath = "",
    [string]$IconPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePath = Join-Path $projectRoot "SteamShell-XFE.ahk"
$validatorPath = Join-Path $projectRoot "Validate-SteamShell-XFE.ps1"

if (-not (Test-Path $sourcePath)) {
    throw "SteamShell-XFE.ahk was not found beside this build script."
}
if (-not (Test-Path $validatorPath)) {
    throw "Validate-SteamShell-XFE.ps1 was not found beside this build script."
}

Write-Host "Running SteamShell XFE static validation..."
& $validatorPath

$autoHotkeyRoots = @(
    (Join-Path $env:ProgramFiles "AutoHotkey"),
    (Join-Path ${env:ProgramFiles(x86)} "AutoHotkey"),
    (Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey")
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$compiler = @(
    $autoHotkeyRoots |
        ForEach-Object { Join-Path $_ "Compiler\Ahk2Exe.exe" } |
        Where-Object { Test-Path $_ }
)
$base = @(
    $autoHotkeyRoots |
        ForEach-Object { Join-Path $_ "v2\AutoHotkey64.exe" } |
        Where-Object { Test-Path $_ }
)

if ($compiler.Count -eq 0) {
    throw "Ahk2Exe was not found. Install AutoHotkey v2 with its compiler."
}
if ($base.Count -eq 0) {
    throw "AutoHotkey v2 64-bit was not found."
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $dist = Join-Path $projectRoot "dist"
    New-Item -ItemType Directory -Path $dist -Force | Out-Null
    $OutputPath = Join-Path $dist "SteamShell-XFE.exe"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectRoot $OutputPath
}

Write-Host "Validating with: $($base[0])"
& $base[0] "/Validate" "/ErrorStdOut=UTF-8" $sourcePath
if ($LASTEXITCODE -ne 0) {
    throw "AutoHotkey syntax validation failed. Compilation was not attempted."
}

$arguments = @(
    "/in", $sourcePath,
    "/out", $OutputPath,
    "/base", $base[0],
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

Write-Host "Compiling SteamShell-XFE.exe..."
& $compiler[0] @arguments
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $OutputPath)) {
    throw "Ahk2Exe did not produce the expected executable."
}
Write-Host "Built: $OutputPath"
