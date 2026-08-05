param(
    [string]$OutputPath = "",
    [string]$IconPath = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePath = Join-Path $projectRoot "SteamShell.ahk"
$helperSourcePath = Join-Path $projectRoot "SteamShell-Helper.ahk"
$validatorPath = Join-Path $projectRoot "Validate-SteamShell.ps1"

if (-not (Test-Path $sourcePath)) {
    throw "SteamShell.ahk was not found beside this build script."
}
if (-not (Test-Path $helperSourcePath)) {
    throw "SteamShell-Helper.ahk was not found beside this build script."
}
if (-not (Test-Path $validatorPath)) {
    throw "Validate-SteamShell.ps1 was not found beside this build script."
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

# Runs a GUI-subsystem executable and returns its real exit code plus output.
#
# AutoHotkey64.exe and Ahk2Exe.exe are both GUI-subsystem executables. Windows
# PowerShell does not reliably wait for those when they are invoked with the
# call operator, so $LASTEXITCODE can be stale or zero even when the process
# failed. That matters more here than almost anywhere else: SteamShell is the
# registered Winlogon shell, so a build that silently ships a broken EXE is a
# machine that signs in to nothing. Start-Process -Wait -PassThru gives a
# Process object whose ExitCode is the actual one.
function Invoke-BuildProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $stdOutPath = [System.IO.Path]::GetTempFileName()
    $stdErrPath = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $Arguments `
            -Wait `
            -PassThru `
            -NoNewWindow `
            -RedirectStandardOutput $stdOutPath `
            -RedirectStandardError $stdErrPath
        $output = (
            [System.IO.File]::ReadAllText(
                $stdOutPath, [System.Text.Encoding]::UTF8) +
            [System.IO.File]::ReadAllText(
                $stdErrPath, [System.Text.Encoding]::UTF8)
        ).Trim()
        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            Output   = $output
        }
    } finally {
        Remove-Item -LiteralPath $stdOutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stdErrPath -Force -ErrorAction SilentlyContinue
    }
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

Write-Host "64-bit interpreter: $($baseCandidates[0])"
$interpreterVersion = (Get-Item -LiteralPath $baseCandidates[0]).VersionInfo.FileVersion
if (-not [string]::IsNullOrWhiteSpace($interpreterVersion)) {
    Write-Host "Interpreter version: $interpreterVersion"
}
Write-Host "Validating SteamShell elevated helper syntax with AutoHotkey v2..."
$helperSyntaxResult = Invoke-BuildProcess `
    -FilePath $baseCandidates[0] `
    -Arguments @(
        "/ErrorStdOut=UTF-8",
        "/Validate",
        (ConvertTo-NativeArgument $helperSourcePath)
    )
if (-not [string]::IsNullOrWhiteSpace($helperSyntaxResult.Output)) {
    Write-Host "AutoHotkey helper validation output:"
    Write-Host $helperSyntaxResult.Output
}
if ($helperSyntaxResult.ExitCode -ne 0) {
    throw (
        "SteamShell-Helper syntax validation failed with exit code " +
        $helperSyntaxResult.ExitCode + ". The compiler was not started.")
}

# Compile the narrowly scoped elevated helper first. SteamShell.ahk embeds this
# exact payload with FileInstall, leaving the published distribution as one EXE.
$helperEmbedDirectory = Join-Path $projectRoot "build"
$helperOutputPath = Join-Path $helperEmbedDirectory "SteamShell-Helper.exe"
New-Item -ItemType Directory -Path $helperEmbedDirectory -Force | Out-Null
$helperArguments = @(
    "/in", $helperSourcePath,
    "/out", $helperOutputPath,
    "/base", $baseCandidates[0],
    "/compress", "0",
    "/silent", "verbose"
)
if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
    $helperArguments += @("/icon", $IconPath)
}
$helperCompileStartedUtc = [DateTime]::UtcNow.AddSeconds(-1)
Write-Host "Compiling embedded elevated window helper..."
Write-Host "Helper output: $helperOutputPath"
$helperCompileResult = Invoke-BuildProcess `
    -FilePath $compilerCandidates[0] `
    -Arguments @($helperArguments | ForEach-Object { ConvertTo-NativeArgument ([string]$_) })
if (-not [string]::IsNullOrWhiteSpace($helperCompileResult.Output)) {
    Write-Host "Ahk2Exe helper output:"
    Write-Host $helperCompileResult.Output
}
$helperOutputExists = Test-Path -LiteralPath $helperOutputPath -PathType Leaf
$helperOutputIsFresh = $helperOutputExists -and
    ((Get-Item -LiteralPath $helperOutputPath).LastWriteTimeUtc -ge $helperCompileStartedUtc)
if ($helperCompileResult.ExitCode -ne 0 -or -not $helperOutputIsFresh) {
    throw (
        "SteamShell-Helper compilation failed with exit code " +
        $helperCompileResult.ExitCode + ". A fresh helper payload was not produced.")
}
$helperVersion = (Get-Item -LiteralPath $helperOutputPath).VersionInfo.FileVersion
if ($helperVersion -ne "1.9.9.1") {
    throw "SteamShell-Helper version verification failed. Expected 1.9.9.1; found '$helperVersion'."
}
Write-Host "Verified embedded helper version: $helperVersion"

# Validate the main source only after the FileInstall payload exists. Depending
# on AutoHotkey version, /Validate may resolve FileInstall sources as well as
# parsing them, so this ordering is part of the build contract.
Write-Host "Validating SteamShell syntax with AutoHotkey v2..."
$syntaxResult = Invoke-BuildProcess `
    -FilePath $baseCandidates[0] `
    -Arguments @(
        "/ErrorStdOut=UTF-8",
        "/Validate",
        (ConvertTo-NativeArgument $sourcePath)
    )
if (-not [string]::IsNullOrWhiteSpace($syntaxResult.Output)) {
    Write-Host "AutoHotkey validation output:"
    Write-Host $syntaxResult.Output
}
if ($syntaxResult.ExitCode -ne 0) {
    $diagnosticHint = if ([string]::IsNullOrWhiteSpace($syntaxResult.Output)) {
        " AutoHotkey returned no diagnostic text; run the displayed interpreter with /ErrorStdOut=UTF-8 /Validate and the source path."
    } else {
        ""
    }
    throw (
        "AutoHotkey syntax validation failed with exit code " +
        $syntaxResult.ExitCode + ". The compiler was not started." + $diagnosticHint)
}

Write-Host "Compiling SteamShell with AutoHotkey v2..."
Write-Host "Compiler: $($compilerCandidates[0])"
Write-Host "Base executable: $($baseCandidates[0])"
Write-Host "Output: $OutputPath"
if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
    Write-Host "Icon: $IconPath"
}

# Recorded before the compiler starts so a stale EXE left in dist by an earlier
# build cannot satisfy the existence check below. Test-Path alone would report
# success for last week's binary.
$compileStartedUtc = [DateTime]::UtcNow.AddSeconds(-1)

$compilerResult = Invoke-BuildProcess `
    -FilePath $compilerCandidates[0] `
    -Arguments @($arguments | ForEach-Object { ConvertTo-NativeArgument ([string]$_) })
if (-not [string]::IsNullOrWhiteSpace($compilerResult.Output)) {
    Write-Host "Ahk2Exe output:"
    Write-Host $compilerResult.Output
}

$outputExists = Test-Path $OutputPath
$outputIsFresh = $outputExists -and
    ((Get-Item -LiteralPath $OutputPath).LastWriteTimeUtc -ge $compileStartedUtc)

if ($compilerResult.ExitCode -ne 0 -or -not $outputIsFresh) {
    $outputState = if (-not $outputExists) {
        "The output file was not created."
    } elseif (-not $outputIsFresh) {
        "The output file exists but was not rewritten by this build; it is left over from an earlier one."
    } else {
        "The output file exists, but Ahk2Exe reported failure."
    }
    $diagnosticHint = if ([string]::IsNullOrWhiteSpace($compilerResult.Output)) {
        " Ahk2Exe returned no diagnostic text; verify that the output is not running or locked and that security software did not quarantine it."
    } else {
        ""
    }
    throw (
        "Ahk2Exe failed with exit code " + $compilerResult.ExitCode + ". " +
        $outputState + $diagnosticHint)
}

$mainVersion = (Get-Item -LiteralPath $OutputPath).VersionInfo.FileVersion
if ($mainVersion -ne "1.9.9.0") {
    throw "SteamShell version verification failed. Expected 1.9.9.0; found '$mainVersion'."
}
Write-Host "Verified SteamShell version: $mainVersion"
Write-Host "Built: $OutputPath"
