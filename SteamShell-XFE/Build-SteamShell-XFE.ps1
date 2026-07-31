param(
    [string]$OutputPath = "",
    [string]$IconPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePath = Join-Path $projectRoot "SteamShell-XFE.ahk"
$validatorPath = Join-Path $projectRoot "Validate-SteamShell-XFE.ps1"
if ([string]::IsNullOrWhiteSpace($IconPath)) {
    $IconPath = Join-Path $projectRoot "assets\SteamShell-XFE.ico"
}

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

function ConvertTo-NativeArgument {
    param([string]$Value)
    if ($Value -match '[\s"]') {
        # Windows paths cannot contain a quote, so quoting the complete argument
        # is sufficient for the file paths passed to AutoHotkey and Ahk2Exe.
        return '"' + $Value.Replace('"', '\"') + '"'
    }
    return $Value
}

Write-Host "Validating with: $($base[0])"
$validationStdOutPath = [System.IO.Path]::GetTempFileName()
$validationStdErrPath = [System.IO.Path]::GetTempFileName()
$validationOutput = ""
$validationExitCode = -1
try {
    $validationArguments = @(
        "/ErrorStdOut=UTF-8",
        "/Validate",
        (ConvertTo-NativeArgument $sourcePath)
    )
    # AutoHotkey64.exe is a GUI-subsystem executable. Windows PowerShell does
    # not reliably set $LASTEXITCODE for it, so explicitly wait for the process
    # and read the ExitCode from the returned Process object.
    $validationProcess = Start-Process `
        -FilePath $base[0] `
        -ArgumentList $validationArguments `
        -Wait `
        -PassThru `
        -NoNewWindow `
        -RedirectStandardOutput $validationStdOutPath `
        -RedirectStandardError $validationStdErrPath
    $validationExitCode = $validationProcess.ExitCode
    $validationOutput = (
        [System.IO.File]::ReadAllText(
            $validationStdOutPath,
            [System.Text.Encoding]::UTF8
        ) +
        [System.IO.File]::ReadAllText(
            $validationStdErrPath,
            [System.Text.Encoding]::UTF8
        )
    ).Trim()
} finally {
    Remove-Item -LiteralPath $validationStdOutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $validationStdErrPath -Force -ErrorAction SilentlyContinue
}
if (-not [string]::IsNullOrWhiteSpace($validationOutput)) {
    Write-Host "AutoHotkey validation output:"
    Write-Host $validationOutput
}
if ($validationExitCode -ne 0) {
    throw "AutoHotkey syntax validation failed with exit code $validationExitCode. Compilation was not attempted."
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
$compilerArguments = @(
    $arguments | ForEach-Object { ConvertTo-NativeArgument ([string]$_) }
)
$compilerProcess = Start-Process `
    -FilePath $compiler[0] `
    -ArgumentList $compilerArguments `
    -Wait `
    -PassThru `
    -NoNewWindow
if ($compilerProcess.ExitCode -ne 0 -or -not (Test-Path $OutputPath)) {
    throw "Ahk2Exe did not produce the expected executable."
}
Write-Host "Built: $OutputPath"
