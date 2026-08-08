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

# One project folder. Both AutoHotkey trees, the shared file, the manifest, both
# validators and the one build script all live in it, so locking a release is a
# copy of this directory and nothing else.
$projectDir = Join-Path $Root "SteamShell"
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

if (-not (Test-Path $projectDir)) {
    throw "Not found: $projectDir  (pass -Root if the project is elsewhere)"
}
Write-Host "Project folder found (both trees, shared file, both validators, one build)."

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
    @{ Name = "SteamShell-Helper.ahk"; Path = Join-Path $projectDir "SteamShell-Helper.ahk" },
    @{ Name = "SteamShell-XFE.ahk"; Path = Join-Path $projectDir "SteamShell-XFE.ahk" }
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
    @{ Name = "Validate-SteamShell.ps1";     Path = Join-Path $projectDir "Validate-SteamShell.ps1" },
    @{ Name = "Validate-SteamShell-XFE.ps1"; Path = Join-Path $projectDir "Validate-SteamShell-XFE.ps1" }
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

# ----------------------------------------------------------------------------
# The two Python checks, which until now were never executed by anything.
#
# Both were written to be run and neither was. Validate-SteamShell-XFE.ps1
# asserts Test-ControllerProfiles.py EXISTS and greps its text for shared
# constants, but never starts it -- so it sat crashing on import for however long
# it took SettingsLayout() to move into SteamShell-Shared.ahk. Replay-Validation.py
# drifted from the PowerShell gate it mirrors and reported ten failures on a clean
# tree, which nobody saw either.
#
# Replay-Validation.py's own header says it: "A validator that is not run is not a
# validator." Running them is the whole fix; the rest was consequence.
#
# Skipped, not failed, when Python is absent: these run on the development machine
# as much as on Windows, and the build must not require a Python install to
# compile an AutoHotkey program.
$python = $null
foreach ($candidate in @("python3", "python", "py")) {
    $found = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($found) { $python = $found.Source; break }
}

$pythonChecks = @(
    @{ Name = "Test-ControllerProfiles.py"
       Path = Join-Path $projectDir "Test-ControllerProfiles.py"
       What = "learned-controller decoder and learning heuristic" },
    @{ Name = "Replay-Validation.py"
       Path = Join-Path $projectDir "Replay-Validation.py"
       What = "structural half of both validators, replayed without Windows" }
)
foreach ($c in $pythonChecks) {
    Write-Host ""
    Write-Host "--- $($c.Name)"
    if (-not $python) {
        Write-Host "SKIPPED - no Python interpreter found." -ForegroundColor Yellow
        Add-Result "Python: $($c.Name)" "SKIPPED" "no interpreter"
        continue
    }
    if (-not (Test-Path -LiteralPath $c.Path)) {
        Write-Host "FAIL: $($c.Name) is missing." -ForegroundColor Red
        Add-Result "Python: $($c.Name)" "FAIL" "missing"
        continue
    }
    $proc = Start-Process -FilePath $python -ArgumentList @($c.Path) `
        -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -eq 0) {
        Write-Host "PASS - $($c.What)." -ForegroundColor Green
        Add-Result "Python: $($c.Name)" "PASS"
    } else {
        Write-Host "FAIL: exit code $($proc.ExitCode)." -ForegroundColor Red
        Add-Result "Python: $($c.Name)" "FAIL" "exit code $($proc.ExitCode)"
    }
}

# --------------------------------------------------------------------- 4. builds
Write-Section "4. Full builds (produces and verifies dist EXEs; nothing is executed)"

# One build script, producing all three binaries in the only order that works:
# helper, then XFE, then SteamShell.exe embedding both. The two-script dance and
# the -XfePayloadPath hand-off it needed are gone.
$builds = @(
    @{
        Name = "Build-SteamShell.ps1"
        Path = Join-Path $projectDir "Build-SteamShell.ps1"
        ProjectDir = $projectDir
        SourceName = "SteamShell.ahk"
        ExeName = "SteamShell.exe"
        ExpectedVersion = "2.0.0.0"
        ValidatesMainSource = $true
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
    Copy-Item -LiteralPath (Join-Path $projectDir "SteamShell.ahk") -Destination $broken
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

    # Both harnesses below copy the WHOLE project folder into $temp and run its
    # build script from there.
    #
    # This used to copy one tree and then have to remember to place
    # SteamShell-Shared.ahk beside it, because the tree reached outside its own
    # directory for the include. Forgetting that made every build in 5b and 5c
    # fail on the missing #Include, which LOOKS like a pass -- the build did
    # reject the tree -- while proving nothing about the broken source or the
    # stale output each test exists to check. That trap is gone by construction
    # now that the folder is self-contained: there is nothing outside it to
    # forget.

    # -- 5b. broken source must not reach the compiler ---------------------------
    #
    # Every source the one build script compiles, one at a time. This is wider
    # than the two-tree version it replaces: SteamShell-Helper.ahk was never
    # covered before, and it is the payload that gets a High-integrity token.
    Write-Host ""
    Write-Host "5b. End-to-end: the build against a broken copy of each source"
    $negativeSources = @(
    "SteamShell.ahk", "SteamShell-XFE.ahk", "SteamShell-Helper.ahk",
    # Both shared files are sources too. Breaking one has to fail the build
    # for every program that includes it -- SteamShell-Common.ahk especially,
    # because it is the first file all three compile against and a silent
    # failure to include it would look exactly like everything working.
    "SteamShell-Shared.ahk", "SteamShell-Common.ahk")
    # A NEGATIVE TEST IS ONLY MEANINGFUL AGAINST A GREEN BASELINE.
    #
    # Every test below breaks something and asserts the build rejects it. If the
    # unmodified project ALREADY fails, the build rejects the broken copy for the
    # original reason, and all of them report PASS while proving nothing. That is
    # not hypothetical: it happened on a real run where a single stale validator
    # assertion was failing, and all seven negative tests printed PASS with that
    # same unrelated message underneath them.
    #
    # 5c's own comment records an earlier version of this same failure through a
    # different door. It is the recurring shape of bug in this harness, so it is
    # now checked rather than reasoned about.
    $baselineGreen = @($results | Where-Object {
        $_.Step -like "Validator:*" -or $_.Step -like "Build:*" }) |
        Where-Object { $_.Status -notin @("OK", "PASS") }
    if ($baselineGreen.Count -gt 0) {
        Write-Host ""
        Write-Host ("    INCONCLUSIVE - the unmodified project already fails " +
            "validation, so breaking it proves nothing.") -ForegroundColor Yellow
        Write-Host ("    Fix the baseline first: " +
            (($baselineGreen | ForEach-Object { $_.Step }) -join ", ")) -ForegroundColor Yellow
        foreach ($sourceName in $negativeSources) {
            Add-Result "Broken source rejected: $sourceName" "SKIPPED" "baseline already failing"
        }
        $skipNegative = $true
    } else {
        $skipNegative = $false
    }

    foreach ($sourceName in $(if ($skipNegative) { @() } else { $negativeSources })) {
        $label = [System.IO.Path]::GetFileNameWithoutExtension($sourceName)
        $brokenTree = Join-Path $temp ("BrokenTree-" + $label)
        Copy-Item -LiteralPath $projectDir -Destination $brokenTree -Recurse
        Remove-Item -LiteralPath (Join-Path $brokenTree "dist") -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $brokenTree "build") -Recurse -Force -ErrorAction SilentlyContinue
        Add-Content -LiteralPath (Join-Path $brokenTree $sourceName) -Value "`r`nthis is not valid autohotkey ][ {{{"

        $threw = $false
        $message = ""
        $buildScript = Join-Path $brokenTree "Build-SteamShell.ps1"
        try { & $buildScript | Out-Null }
        catch { $threw = $true; $message = $_.Exception.Message }
        $producedExe = Test-Path (Join-Path (Join-Path $brokenTree "dist") "SteamShell.exe")

        Write-Host "    broken $sourceName -> threw=$threw producedExe=$producedExe"
        if ($message) { Write-Host "      message: $message" }
        # "It threw" is not enough -- it has to throw about THIS file. A build
        # that rejects the tree for an unrelated reason looks identical from the
        # outside and tests nothing, which is exactly how a green run can hide a
        # gate that no longer works.
        #
        # "exit code" used to be one of these alternatives, and it undid the
        # other four. EVERY throw in Build-SteamShell.ps1 that reaches a
        # validator or the compiler carries that phrase -- seven of them do --
        # so the test collapsed back to "it threw", which is the exact assertion
        # this list was written to replace. The remaining patterns all describe
        # a PARSE rejection, which is what appending invalid AutoHotkey to a
        # source actually produces: every source here is /Validate'd before it is
        # compiled, so a syntax fault is reported as a validation failure and
        # never reaches the compiler's generic exit-code branch.
        $blamesThisSource =
            $message -match [regex]::Escape($sourceName) -or
            $message -match "not valid autohotkey" -or
            $message -match "syntax" -or
            $message -match "parse" -or
            $message -match "validation failed"
        if ($threw -and -not $producedExe -and $blamesThisSource) {
            Write-Host "      PASS - broken source cannot reach the compiler." -ForegroundColor Green
            Add-Result "Broken source rejected: $sourceName" "PASS"
        } elseif ($threw -and -not $producedExe) {
            Write-Host ("      INCONCLUSIVE - rejected, but not for the fault " +
                "injected here.") -ForegroundColor Yellow
            Add-Result "Broken source rejected: $sourceName" "FAIL" `
                "rejected for an unrelated reason; the gate was not exercised"
        } else {
            Write-Host "      FAIL - broken source got past the gate." -ForegroundColor Red
            Add-Result "Broken source rejected: $sourceName" "FAIL" "threw=$threw exe=$producedExe"
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
    #
    # Both freshness branches are covered: the embedded XFE payload in build\ and
    # the published installer in dist\. One build script has more than one such
    # gate, so testing only the last one would leave the first unproven.
    Write-Host ""
    Write-Host "5c. Stale-output detection (source valid; output locked)"
    $staleTargets = @(
        @{ Label = "build\SteamShell-XFE.exe"; Directory = "build"; ExeName = "SteamShell-XFE.exe" },
        @{ Label = "dist\SteamShell.exe";      Directory = "dist";  ExeName = "SteamShell.exe" }
    )
    if ($skipNegative) {
        Write-Host ("    INCONCLUSIVE - baseline already failing; a stale output " +
            "would be rejected for that reason instead.") -ForegroundColor Yellow
        foreach ($target in $staleTargets) {
            Add-Result "Stale output rejected: $($target.Label)" "SKIPPED" "baseline already failing"
        }
    }
    foreach ($target in $(if ($skipNegative) { @() } else { $staleTargets })) {
        $label = [System.IO.Path]::GetFileNameWithoutExtension($target.ExeName) + "-" + $target.Directory
        $cleanTree = Join-Path $temp ("CleanTree-" + $label)
        Copy-Item -LiteralPath $projectDir -Destination $cleanTree -Recurse
        foreach ($scratch in @("dist", "build")) {
            Remove-Item -LiteralPath (Join-Path $cleanTree $scratch) -Recurse -Force -ErrorAction SilentlyContinue
        }
        $outDir = Join-Path $cleanTree $target.Directory
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null

        $outPath = Join-Path $outDir $target.ExeName
        Set-Content -LiteralPath $outPath -Value "stale placeholder from an earlier build"
        (Get-Item -LiteralPath $outPath).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-7)
        $staleStamp = (Get-Item -LiteralPath $outPath).LastWriteTimeUtc

        $lock = [System.IO.File]::Open(
            $outPath, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

        $staleThrew = $false
        $staleMessage = ""
        $buildScript = Join-Path $cleanTree "Build-SteamShell.ps1"
        try { & $buildScript | Out-Null }
        catch { $staleThrew = $true; $staleMessage = $_.Exception.Message }

        $lock.Close(); $lock = $null
        $stillStale = (Test-Path -LiteralPath $outPath) -and
            ((Get-Item -LiteralPath $outPath).LastWriteTimeUtc -eq $staleStamp)

        Write-Host "    $($target.Label): threw=$staleThrew stillStale=$stillStale"
        if ($staleMessage) { Write-Host "      message: $staleMessage" }
        if ($staleThrew -and $stillStale) {
            if ($staleMessage -match "left over from an earlier") {
                Write-Host "      PASS - correctly rejected as a leftover artefact." -ForegroundColor Green
                Add-Result "Stale output rejected: $($target.Label)" "PASS" "freshness branch reached"
            } elseif ($staleMessage -match "exit code" -or
                      $staleMessage -match [regex]::Escape($target.ExeName)) {
                Write-Host "      PASS - rejected through the compiler exit-code branch." -ForegroundColor Yellow
                Add-Result "Stale output rejected: $($target.Label)" "PASS" "exit-code branch"
            } else {
                # It threw, but about something else entirely. Reporting this as
                # a pass is how the harness previously claimed to have exercised
                # "the compiler exit-code branch" on a run where the build never
                # reached the compiler at all.
                Write-Host ("      INCONCLUSIVE - rejected, but neither the " +
                    "freshness nor the compiler branch was reached.") -ForegroundColor Yellow
                Add-Result "Stale output rejected: $($target.Label)" "FAIL" `
                    "rejected for an unrelated reason; the gate was not exercised"
            }
        } else {
            Write-Host "      FAIL - a stale output was accepted." -ForegroundColor Red
            Add-Result "Stale output rejected: $($target.Label)" "FAIL" "threw=$staleThrew stillStale=$stillStale"
        }
    }
} finally {
    if ($lock) { $lock.Close() }
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------- 6. transactional publish
Write-Section "6. Publish the verified installer to root current"

$prePublishFailures = @($results | Where-Object { $_.Status -notin @("OK", "PASS") })
if ($prePublishFailures.Count -gt 0 -or $builtOutputs.Count -ne $builds.Count) {
    Write-Host "SKIPPED - validation failed; the existing current folder was not changed." -ForegroundColor Yellow
    Add-Result "Publish current" "SKIPPED" "validation failed; existing current was preserved"
} else {
    # SteamShell.exe ONLY. It carries both payloads and is the installer and the
    # uninstaller for both products, so a second SteamShell-XFE.exe beside it is
    # not a distributable -- it is an invitation to a hand-copied install with no
    # logon task, no writable companion directory, and no dormant helper. The
    # build still writes one to dist\ for developing XFE; it does not ship.
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
        Write-Host "PASS - current now contains the verified installer." -ForegroundColor Green
        Add-Result "Publish current" "PASS" "installer promoted as one directory transaction"
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
Write-Host "The produced EXE was not run. SteamShell.exe replaces the Windows shell;"
Write-Host "do not launch it on a machine you are not prepared to restore."
if ($bad.Count -gt 0) {
    exit 1
}
exit 0
