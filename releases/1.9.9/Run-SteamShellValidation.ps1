<#
    End-to-end validation harness for both trees. Run on Windows in Windows
    PowerShell 5.1, from a session where this repository is reachable.

        powershell -ExecutionPolicy Bypass -File Run-SteamShellValidation.ps1
        powershell -ExecutionPolicy Bypass -File Run-SteamShellValidation.ps1 -Root "Z:\"

    This exists because Validate-*.ps1 can only inspect text. Only AutoHotkey
    itself can say whether the source parses, and only a real build can say
    whether it compiles. Run this after any substantial edit, and always after a
    mechanical or repo-wide transformation.

    NON-DESTRUCTIVE to the source trees: writes only to each tree's dist\ folder,
    a transactionally published root current\ folder (all excluded by
    .gitignore), and a temporary directory it removes afterwards. The existing
    current\ folder is not changed unless every validation and negative test
    passes and both new EXEs have been verified.

    It NEVER runs the produced executables, and neither should you on a machine
    you care about. SteamShell.exe is a Winlogon shell replacement: it rewrites
    the shell registry value, terminates explorer.exe on its restore paths, and
    takes over the session.

    What this CANNOT tell you: anything behavioural. Quick Menu painting, the HDR
    fallback, log rotation actually rolling, PreviousShell restore -- all of that
    needs an interactive desktop session on hardware you can snapshot.
#>
param(
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$standaloneDir = Join-Path $Root "SteamShell"
$companionDir  = Join-Path $Root "SteamShell-XFE"
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Step, [string]$Status, [string]$Detail = "")
    $results.Add([PSCustomObject]@{ Step = $Step; Status = $Status; Detail = $Detail })
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 78)
    Write-Host "  $Title"
    Write-Host ("=" * 78)
}

# Reliable exit code for GUI-subsystem executables. Deliberately the same
# mechanism the build scripts use, because trustworthy exit codes are the
# precondition for testing anything here.
function Invoke-Native {
    param([string]$FilePath, [string[]]$Arguments)
    $o = [System.IO.Path]::GetTempFileName()
    $e = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $o -RedirectStandardError $e
        $text = ([System.IO.File]::ReadAllText($o) + [System.IO.File]::ReadAllText($e)).Trim()
        return [PSCustomObject]@{ ExitCode = $p.ExitCode; Output = $text }
    } finally {
        Remove-Item -LiteralPath $o, $e -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------- 1. environment
Write-Section "1. Environment"

Write-Host "PowerShell edition : $($PSVersionTable.PSEdition)"
Write-Host "PowerShell version : $($PSVersionTable.PSVersion)"
if ($PSVersionTable.PSVersion.Major -ne 5) {
    Write-Warning "Not Windows PowerShell 5.1. Section 5a measures a 5.1-specific behaviour and will not be meaningful here."
}
Write-Host "Root               : $Root"

foreach ($d in @($standaloneDir, $companionDir)) {
    if (-not (Test-Path $d)) { throw "Not found: $d  (pass -Root if the trees are elsewhere)" }
}
Write-Host "Both source trees found."

$autoHotkeyRoots = @(
    (Join-Path $env:ProgramFiles "AutoHotkey"),
    (Join-Path ${env:ProgramFiles(x86)} "AutoHotkey"),
    (Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey")
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$ahk = @($autoHotkeyRoots | ForEach-Object { Join-Path $_ "v2\AutoHotkey64.exe" } |
    Where-Object { Test-Path $_ })
$ahk2exe = @($autoHotkeyRoots | ForEach-Object { Join-Path $_ "Compiler\Ahk2Exe.exe" } |
    Where-Object { Test-Path $_ })

if ($ahk.Count -eq 0) {
    throw "AutoHotkey64.exe (v2, 64-bit) was not found. Note that a per-user install lives under %LOCALAPPDATA%\Programs\AutoHotkey and is only visible to that user's own session."
}
if ($ahk2exe.Count -eq 0) { throw "Ahk2Exe.exe was not found." }

$ahkVersion = (Get-Item -LiteralPath $ahk[0]).VersionInfo.FileVersion
Write-Host "Interpreter        : $($ahk[0])"
Write-Host "  version          : $ahkVersion"
Write-Host "Compiler           : $($ahk2exe[0])"
Add-Result "Environment" "OK" "PS $($PSVersionTable.PSVersion), AHK $ahkVersion"

# ------------------------------------------------- 2. syntax validation (the big one)
Write-Section "2. AutoHotkey syntax validation  <-- the result that matters most"

$sources = @(
    @{ Name = "SteamShell-Helper.ahk"; Path = Join-Path $standaloneDir "SteamShell-Helper.ahk" },
    @{ Name = "SteamShell-XFE.ahk"; Path = Join-Path $companionDir  "SteamShell-XFE.ahk" }
)
foreach ($s in $sources) {
    Write-Host ""
    Write-Host "--- $($s.Name)"
    $r = Invoke-Native $ahk[0] @("/ErrorStdOut=UTF-8", "/Validate", "`"$($s.Path)`"")
    Write-Host "exit code: $($r.ExitCode)"
    if ($r.Output) { Write-Host "output:"; Write-Host $r.Output }
    if ($r.ExitCode -eq 0) {
        Write-Host "PASS - parses cleanly." -ForegroundColor Green
        Add-Result "Syntax: $($s.Name)" "PASS"
    } else {
        Write-Host "FAIL" -ForegroundColor Red
        Add-Result "Syntax: $($s.Name)" "FAIL" $r.Output
    }
}
Write-Host ""
Write-Host "SteamShell.ahk is validated in section 4 after its freshly compiled"
Write-Host "FileInstall helper payload exists. This keeps clean release snapshots buildable."

# ------------------------------------------------------------- 3. static validators
Write-Section "3. Static validators (each also runs the cross-tree parity check)"

$validators = @(
    @{ Name = "Validate-SteamShell.ps1";     Path = Join-Path $standaloneDir "Validate-SteamShell.ps1" },
    @{ Name = "Validate-SteamShell-XFE.ps1"; Path = Join-Path $companionDir  "Validate-SteamShell-XFE.ps1" }
)
foreach ($v in $validators) {
    Write-Host ""
    Write-Host "--- $($v.Name)"
    try {
        & $v.Path
        Write-Host "PASS" -ForegroundColor Green
        Add-Result "Validator: $($v.Name)" "PASS"
    } catch {
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
        Add-Result "Validator: $($v.Name)" "FAIL" $_.Exception.Message
    }
}

# --------------------------------------------------------------------- 4. builds
Write-Section "4. Full builds (produces and verifies dist EXEs; nothing is executed)"

$builds = @(
    @{
        Name = "Build-SteamShell.ps1"
        Path = Join-Path $standaloneDir "Build-SteamShell.ps1"
        ProjectDir = $standaloneDir
        SourceName = "SteamShell.ahk"
        ExeName = "SteamShell.exe"
        ExpectedVersion = "1.9.9.0"
        ValidatesMainSource = $true
    },
    @{
        Name = "Build-SteamShell-XFE.ps1"
        Path = Join-Path $companionDir "Build-SteamShell-XFE.ps1"
        ProjectDir = $companionDir
        SourceName = "SteamShell-XFE.ahk"
        ExeName = "SteamShell-XFE.exe"
        ExpectedVersion = "1.9.9.0"
        ValidatesMainSource = $false
    }
)
$builtOutputs = New-Object System.Collections.Generic.List[object]
foreach ($b in $builds) {
    Write-Host ""
    Write-Host "--- $($b.Name)"
    try {
        & $b.Path

        $distExe = Join-Path (Join-Path $b.ProjectDir "dist") $b.ExeName
        if (-not (Test-Path -LiteralPath $distExe -PathType Leaf)) {
            throw "Expected build output was not found: $distExe"
        }
        $distVersion = (Get-Item -LiteralPath $distExe).VersionInfo.FileVersion
        if ($distVersion -ne $b.ExpectedVersion) {
            throw "Expected $($b.ExeName) version $($b.ExpectedVersion); found '$distVersion'."
        }

        $builtOutputs.Add([PSCustomObject]@{
            SourcePath = $distExe
            ExeName = $b.ExeName
        })

        Write-Host "PASS" -ForegroundColor Green
        if ($b.ValidatesMainSource) {
            Add-Result "Syntax: SteamShell.ahk" "PASS" "validated after fresh helper compilation"
        }
        Add-Result "Build: $($b.Name)" "PASS" "verified version $distVersion dist output"
    } catch {
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
        Add-Result "Build: $($b.Name)" "FAIL" $_.Exception.Message
    }
}

# ------------------------------------------------- 5. the build gate, tested directly
Write-Section "5. Does the build gate actually reject bad output?"

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("ss-validate-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$lock = $null
try {
    # -- 5a. exit-code mechanism, measured rather than assumed -------------------
    #
    # The August 2026 audit claimed the old call-operator form could miss a
    # non-zero exit from a GUI-subsystem executable. Measured on PS 5.1.26100 /
    # AHK 2.0.26 that did NOT reproduce: the old form pipes through
    # ForEach-Object, and draining that pipeline synchronizes on process exit.
    # Both mechanisms returning non-zero is therefore the EXPECTED result here.
    # This stays in the harness so the assumption keeps being checked rather than
    # inherited -- a future PowerShell or AutoHotkey build may behave differently.
    $broken = Join-Path $temp "Broken.ahk"
    Copy-Item -LiteralPath (Join-Path $standaloneDir "SteamShell.ahk") -Destination $broken
    Add-Content -LiteralPath $broken -Value "`r`nthis is not valid autohotkey ][ {{{"

    Write-Host ""
    Write-Host "5a. Exit-code mechanism comparison on a deliberately broken source"
    Write-Host ""

    # Under Windows PowerShell 5.1, redirecting a native program's stderr into
    # the success stream creates NativeCommandError records. The script-wide
    # ErrorActionPreference=Stop is correct for the harness, but this one call is
    # deliberately expected to fail and must be allowed to finish so its exit
    # code can be measured. Restore strict handling immediately afterwards.
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $null = & $ahk[0] "/ErrorStdOut=UTF-8" "/Validate" $broken 2>&1 |
            ForEach-Object { "$_" }
        $viaCallOperator = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    $viaStartProcess = (Invoke-Native $ahk[0] @("/ErrorStdOut=UTF-8", "/Validate", "`"$broken`"")).ExitCode

    Write-Host "    old (call operator + `$LASTEXITCODE) : $viaCallOperator"
    Write-Host "    new (Start-Process -Wait -PassThru)  : $viaStartProcess"
    Write-Host ""
    if ($viaStartProcess -eq 0) {
        Write-Host "    UNEXPECTED - the current mechanism missed a broken source." -ForegroundColor Red
        Add-Result "Exit-code mechanism" "UNEXPECTED" "old=$viaCallOperator new=$viaStartProcess"
    } elseif ($viaCallOperator -eq 0) {
        Write-Host "    The old mechanism missed it here; the current one caught it." -ForegroundColor Yellow
        Write-Host "    Worth recording -- this environment DOES reproduce the original concern." -ForegroundColor Yellow
        Add-Result "Exit-code mechanism" "OK" "old=$viaCallOperator new=$viaStartProcess (old missed it)"
    } else {
        Write-Host "    Both caught it, as expected on current toolchains." -ForegroundColor Green
        Add-Result "Exit-code mechanism" "OK" "old=$viaCallOperator new=$viaStartProcess (both caught)"
    }

    # -- 5b. broken source must not reach either compiler ------------------------
    Write-Host ""
    Write-Host "5b. End-to-end: each build script against a broken copy of its tree"
    foreach ($b in $builds) {
        $projectName = [System.IO.Path]::GetFileNameWithoutExtension($b.ExeName)
        $brokenTree = Join-Path $temp ("BrokenTree-" + $projectName)
        Copy-Item -LiteralPath $b.ProjectDir -Destination $brokenTree -Recurse
        Remove-Item -LiteralPath (Join-Path $brokenTree "dist") -Recurse -Force -ErrorAction SilentlyContinue
        Add-Content -LiteralPath (Join-Path $brokenTree $b.SourceName) -Value "`r`nthis is not valid autohotkey ][ {{{"

        $threw = $false
        $message = ""
        $buildScript = Join-Path $brokenTree ([System.IO.Path]::GetFileName($b.Path))
        try { & $buildScript | Out-Null }
        catch { $threw = $true; $message = $_.Exception.Message }
        $producedExe = Test-Path (Join-Path (Join-Path $brokenTree "dist") $b.ExeName)

        Write-Host "    $($b.ExeName): threw=$threw producedExe=$producedExe"
        if ($message) { Write-Host "      message: $message" }
        if ($threw -and -not $producedExe) {
            Write-Host "      PASS - broken source cannot reach the compiler." -ForegroundColor Green
            Add-Result "Broken source rejected: $($b.ExeName)" "PASS"
        } else {
            Write-Host "      FAIL - broken source got past the gate." -ForegroundColor Red
            Add-Result "Broken source rejected: $($b.ExeName)" "FAIL" "threw=$threw exe=$producedExe"
        }
    }

    # -- 5c. stale output must not satisfy the build -----------------------------
    #
    # The source is left VALID here on purpose. An earlier version of this
    # harness reused 5b's broken tree, so the build threw on the syntax error and
    # never reached the freshness check -- the test passed while proving nothing.
    # The compiler is made to fail instead by holding an exclusive lock on the
    # output file, which is also the real scenario the build's own diagnostic
    # hint mentions.
    Write-Host ""
    Write-Host "5c. Stale-output detection for both builds (source valid; output locked)"
    foreach ($b in $builds) {
        $projectName = [System.IO.Path]::GetFileNameWithoutExtension($b.ExeName)
        $cleanTree = Join-Path $temp ("CleanTree-" + $projectName)
        Copy-Item -LiteralPath $b.ProjectDir -Destination $cleanTree -Recurse
        Remove-Item -LiteralPath (Join-Path $cleanTree "dist") -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path (Join-Path $cleanTree "dist") -Force | Out-Null

        $outPath = Join-Path (Join-Path $cleanTree "dist") $b.ExeName
        Set-Content -LiteralPath $outPath -Value "stale placeholder from an earlier build"
        (Get-Item -LiteralPath $outPath).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-7)
        $staleStamp = (Get-Item -LiteralPath $outPath).LastWriteTimeUtc

        $lock = [System.IO.File]::Open(
            $outPath, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

        $staleThrew = $false
        $staleMessage = ""
        $buildScript = Join-Path $cleanTree ([System.IO.Path]::GetFileName($b.Path))
        try { & $buildScript | Out-Null }
        catch { $staleThrew = $true; $staleMessage = $_.Exception.Message }

        $lock.Close(); $lock = $null
        $stillStale = (Test-Path -LiteralPath $outPath) -and
            ((Get-Item -LiteralPath $outPath).LastWriteTimeUtc -eq $staleStamp)

        Write-Host "    $($b.ExeName): threw=$staleThrew stillStale=$stillStale"
        if ($staleMessage) { Write-Host "      message: $staleMessage" }
        if ($staleThrew -and $stillStale) {
            if ($staleMessage -match "left over from an earlier") {
                Write-Host "      PASS - correctly rejected as a leftover artefact." -ForegroundColor Green
                Add-Result "Stale output rejected: $($b.ExeName)" "PASS" "freshness branch reached"
            } else {
                Write-Host "      PASS - rejected through the compiler exit-code branch." -ForegroundColor Yellow
                Add-Result "Stale output rejected: $($b.ExeName)" "PASS" "exit-code branch"
            }
        } else {
            Write-Host "      FAIL - a stale output was accepted." -ForegroundColor Red
            Add-Result "Stale output rejected: $($b.ExeName)" "FAIL" "threw=$staleThrew stillStale=$stillStale"
        }
    }
} finally {
    if ($lock) { $lock.Close() }
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------- 6. transactional publish
Write-Section "6. Publish both verified EXEs to root current"

$prePublishFailures = @($results | Where-Object { $_.Status -notin @("OK", "PASS") })
if ($prePublishFailures.Count -gt 0 -or $builtOutputs.Count -ne $builds.Count) {
    Write-Host "SKIPPED - validation failed; the existing current folder was not changed." -ForegroundColor Yellow
    Add-Result "Publish current" "SKIPPED" "validation failed; existing current was preserved"
} else {
    $transactionId = [guid]::NewGuid().ToString("N")
    $currentDir = Join-Path $Root "current"
    $stageDir = Join-Path $Root ("current.staging-" + $transactionId)
    $backupDir = Join-Path $Root ("current.backup-" + $transactionId)
    $hadCurrent = Test-Path -LiteralPath $currentDir
    try {
        New-Item -ItemType Directory -Path $stageDir | Out-Null
        foreach ($output in $builtOutputs) {
            $stagedExe = Join-Path $stageDir $output.ExeName
            Copy-Item -LiteralPath $output.SourcePath -Destination $stagedExe
            $sourceHash = (Get-FileHash -LiteralPath $output.SourcePath -Algorithm SHA256).Hash
            $stagedHash = (Get-FileHash -LiteralPath $stagedExe -Algorithm SHA256).Hash
            if ($sourceHash -ne $stagedHash) {
                throw "Hash verification failed while staging $($output.ExeName)."
            }
        }

        if ($hadCurrent) {
            Move-Item -LiteralPath $currentDir -Destination $backupDir
        }
        Move-Item -LiteralPath $stageDir -Destination $currentDir
        if (Test-Path -LiteralPath $backupDir) {
            try {
                Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Warning "The new current folder is valid, but its transaction backup could not be removed: $backupDir"
            }
        }
        Write-Host "PASS - current now contains both verified EXEs." -ForegroundColor Green
        Add-Result "Publish current" "PASS" "both EXEs promoted as one directory transaction"
    } catch {
        $publishError = $_.Exception.Message
        Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
        try {
            if (-not (Test-Path -LiteralPath $currentDir) -and
                (Test-Path -LiteralPath $backupDir)) {
                Move-Item -LiteralPath $backupDir -Destination $currentDir
            }
        } catch {
            $publishError += " Rollback also failed; recover the prior folder from '$backupDir'. $($_.Exception.Message)"
        }
        Write-Host "FAIL: $publishError" -ForegroundColor Red
        Add-Result "Publish current" "FAIL" $publishError
    }
}

# -------------------------------------------------------------------- 7. summary
Write-Section "7. Summary"
$results | Format-Table -AutoSize Step, Status, Detail
$bad = @($results | Where-Object { $_.Status -notin @("OK", "PASS", "SKIPPED") })
Write-Host ""
if ($bad.Count -eq 0) {
    Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
} else {
    Write-Host "$($bad.Count) CHECK(S) FAILED" -ForegroundColor Red
}
Write-Host ""
Write-Host "Neither produced EXE was run. SteamShell.exe replaces the Windows shell;"
Write-Host "do not launch it on a machine you are not prepared to restore."
if ($bad.Count -gt 0) {
    exit 1
}
exit 0
