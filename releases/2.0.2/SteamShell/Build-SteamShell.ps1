param(
    [string]$OutputPath = "",
    [string]$IconPath = "",
    # Skips publishing SteamShell-XFE.exe to dist. The companion is always
    # BUILT -- it is the payload SteamShell.exe embeds -- and this only controls
    # whether a second distributable is left beside the installer.
    [switch]$NoXfeDist,
    # FOR THE HARNESS, NOT FOR BUILDING. Skips the two static validators.
    #
    # Run-SteamShellValidation.ps1 builds this project nine times: once for real,
    # five times against a deliberately broken source, and twice against a locked
    # output. Those seven throwaway builds test the SYNTAX gate and the FRESHNESS
    # gate, both of which sit downstream of validation -- and every one of them
    # re-ran both validators over the same unchanged files first, eighteen full
    # scans per run where two carry signal. On a project served over SMB that is
    # most of the wall time.
    #
    # The harness still runs one throwaway build WITHOUT this switch, so
    # "validation happens inside a copied tree" stays proven rather than assumed.
    # Do not pass it by hand: a build that skips its own validation is not a
    # build anyone should publish.
    [switch]$SkipStaticValidation
)

# Builds all three binaries, in the only order that works:
#
#   1. SteamShell-Helper.exe  -> build\SteamShell-Helper.exe
#   2. SteamShell-XFE.exe     -> build\SteamShell-XFE.exe (and dist\)
#   3. SteamShell.exe         -> dist\SteamShell.exe, embedding both
#
# SteamShell.exe is the installer for both products, so it carries the companion
# exactly as it carries the helper, and its own syntax cannot be validated until
# both FileInstall payloads exist on disk.
#
# Everything this script touches is in this folder. That is what makes locking a
# release a copy of one directory.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePath = Join-Path $projectRoot "SteamShell.ahk"
$helperSourcePath = Join-Path $projectRoot "SteamShell-Helper.ahk"
$xfeSourcePath = Join-Path $projectRoot "SteamShell-XFE.ahk"
$validatorPath = Join-Path $projectRoot "Validate-SteamShell.ps1"
$xfeValidatorPath = Join-Path $projectRoot "Validate-SteamShell-XFE.ps1"

foreach ($required in @(
    $sourcePath, $helperSourcePath, $xfeSourcePath,
    $validatorPath, $xfeValidatorPath)) {
    if (-not (Test-Path $required)) {
        throw ("$([System.IO.Path]::GetFileName($required)) was not found " +
            "beside this build script.")
    }
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

# Both validators, before anything is compiled. They are separate scripts on
# purpose -- several of XFE's architecture rules are the exact inverse of the
# shell's -- but a build that produces one EXE from two sources has to satisfy
# both of them.
if ($SkipStaticValidation) {
    Write-Host "Static validation SKIPPED (-SkipStaticValidation). Harness use only."
} else {
    Write-Host "Running SteamShell static validation..."
    & $validatorPath
    Write-Host "Running SteamShell XFE static validation..."
    & $xfeValidatorPath
}

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
if ($helperVersion -ne "2.0.2.1") {
    throw "SteamShell-Helper version verification failed. Expected 2.0.2.1; found '$helperVersion'."
}
Write-Host "Verified embedded helper version: $helperVersion"

# The second embedded payload: SteamShell.exe is the installer for both products,
# so it has to carry the XFE companion the same way it carries the helper.
#
# Compiled here rather than by a separate script. XFE's own validator has
# already run above, so the payload still goes through its product rules; what
# is gone is the second build script that had to be kept in step with this one.
Write-Host "Validating SteamShell-XFE syntax with AutoHotkey v2..."
$xfeSyntaxResult = Invoke-BuildProcess `
    -FilePath $baseCandidates[0] `
    -Arguments @(
        "/ErrorStdOut=UTF-8",
        "/Validate",
        (ConvertTo-NativeArgument $xfeSourcePath)
    )
if (-not [string]::IsNullOrWhiteSpace($xfeSyntaxResult.Output)) {
    Write-Host "AutoHotkey XFE validation output:"
    Write-Host $xfeSyntaxResult.Output
}
if ($xfeSyntaxResult.ExitCode -ne 0) {
    throw (
        "SteamShell-XFE syntax validation failed with exit code " +
        $xfeSyntaxResult.ExitCode + ". The compiler was not started.")
}

$xfeEmbedPath = Join-Path $helperEmbedDirectory "SteamShell-XFE.exe"
$xfeIconPath = Join-Path $projectRoot "assets\SteamShell-XFE.ico"
$xfeArguments = @(
    "/in", $xfeSourcePath,
    "/out", $xfeEmbedPath,
    "/base", $baseCandidates[0],
    "/compress", "0",
    "/silent", "verbose"
)
if (Test-Path $xfeIconPath) {
    $xfeArguments += @("/icon", $xfeIconPath)
}
$xfeCompileStartedUtc = [DateTime]::UtcNow.AddSeconds(-1)
Write-Host "Compiling the embedded SteamShell-XFE companion payload..."
$xfeCompileResult = Invoke-BuildProcess `
    -FilePath $compilerCandidates[0] `
    -Arguments @($xfeArguments | ForEach-Object { ConvertTo-NativeArgument ([string]$_) })
if (-not [string]::IsNullOrWhiteSpace($xfeCompileResult.Output)) {
    Write-Host "Ahk2Exe XFE output:"
    Write-Host $xfeCompileResult.Output
}
# Freshness, not existence. Test-Path alone reports success for last week's
# binary, which is how a stale payload gets embedded and shipped.
$xfeOutputExists = Test-Path -LiteralPath $xfeEmbedPath -PathType Leaf
$xfeOutputIsFresh = $xfeOutputExists -and
    ((Get-Item -LiteralPath $xfeEmbedPath).LastWriteTimeUtc -ge $xfeCompileStartedUtc)
if ($xfeCompileResult.ExitCode -ne 0 -or -not $xfeOutputIsFresh) {
    $xfeOutputState = if (-not $xfeOutputExists) {
        "The output file was not created."
    } elseif (-not $xfeOutputIsFresh) {
        "The output file is left over from an earlier build."
    } else {
        "Ahk2Exe reported failure."
    }
    throw (
        "Ahk2Exe did not produce the expected executable (exit code " +
        $xfeCompileResult.ExitCode + "). " + $xfeOutputState)
}
$xfeEmbedVersion = (Get-Item -LiteralPath $xfeEmbedPath).VersionInfo.FileVersion
if ($xfeEmbedVersion -ne "2.0.2.0") {
    throw (
        "SteamShell-XFE version verification failed. Expected 2.0.2.0; " +
        "found '$xfeEmbedVersion'.")
}
Write-Host "Verified embedded XFE version: $xfeEmbedVersion"

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
if ($mainVersion -ne "2.0.2.0") {
    throw "SteamShell version verification failed. Expected 2.0.2.0; found '$mainVersion'."
}
Write-Host "Verified SteamShell version: $mainVersion"
Write-Host "Built: $OutputPath"

# The companion, copied out of build\ beside the installer.
#
# This is a convenience for developing XFE, not a distributable. Setup Assistant
# inside SteamShell.exe is the supported way to install either product: it
# registers the logon task, grants the companion's own directory to the
# signed-in user, and deploys the dormant elevated helper. A hand-copied
# SteamShell-XFE.exe gets none of that, which is why it is no longer published
# to the repository's current\ folder.
if (-not $NoXfeDist) {
    $xfeDistPath = Join-Path (Split-Path -Parent $OutputPath) "SteamShell-XFE.exe"
    Copy-Item -LiteralPath $xfeEmbedPath -Destination $xfeDistPath -Force
    Write-Host "Built: $xfeDistPath (development copy; install through Setup)"
}
