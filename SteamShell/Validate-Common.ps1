# Scaffolding shared by Validate-SteamShell.ps1 and Validate-SteamShell-XFE.ps1.
#
# MECHANISM ONLY. No product rules live here, and that boundary is deliberate.
#
# The two validators enforce rules that are INVERTED between the products:
# RegWrite(, RegDelete(, WinMaximize(, SetWinEventHook, RestoreExplorerDesktop
# and HideShellTaskbars are forbidden in SteamShell-XFE.ahk and are what
# SteamShell.ahk is built out of -- 45 call sites between them. That is the
# check keeping XFE from quietly growing into a shell, and it works because each
# validator runs against exactly one source. Merging the two into one script
# would turn every architecture assertion into one that has to name its own
# scope, and a mis-scoped rule does not fail -- it silently stops applying.
#
# So what is shared is the plumbing every static validator needs: reading a
# source with its #Includes resolved, and the structural scans that are true of
# any AutoHotkey file. Dot-source this, then write the product's rules.

$ErrorActionPreference = "Stop"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

# Reads a source as AutoHotkey actually sees it, with #Include inlined at the
# point the directive appears.
#
# Both trees compile SteamShell-Shared.ahk in, so reading a tree file on its own
# would silently pass every assertion about a function that moved out of it --
# which is the failure this whole validator exists to prevent.
#
# Get-Content -Raw, deliberately, and not [System.IO.File]::ReadAllLines. This
# has to reproduce what the assertions already saw, not improve on it:
#
#   Line endings. These sources are LF-only. ReadAllLines drops the original
#   terminators and StringBuilder.AppendLine writes CRLF, and .NET's (?m)$
#   matches before \n -- so every '^...$' assertion breaks on the \r.
#
#   Encoding. Windows PowerShell's Get-Content decodes a BOM-less file as ANSI,
#   while ReadAllLines decodes it as UTF-8. Patterns containing a non-ASCII
#   character match only because the pattern and the source are decoded the same
#   way. Decoding the source "correctly" breaks them.
#
# A LATENT ENCODING LANDMINE, recorded here rather than in a status document
# because this is the file it goes off in.
#
# Assertions that contain a non-ASCII character -- the `PRESET · … FPS` row text
# is the one to remember -- pass *because* PowerShell mis-decodes the validator
# script and the AutoHotkey source in the same way. The mistake cancels out.
# Save EITHER file with a UTF-8 BOM and those assertions start failing for
# reasons that look nothing like the cause.
#
# Left alone deliberately: fixing it properly means re-checking every non-ASCII
# assertion in both validators, which is a pass of its own. But it should be
# cleaned up on purpose one day rather than discovered by someone whose editor
# helpfully added a BOM.
#
# The same trap catches anyone reproducing these assertions offline on a
# non-Windows machine: decode the sources as cp1252 and match case-INSENSITIVELY,
# or the replay reports failures that do not exist.
function Get-EffectiveSource {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 0
    )
    if ($Depth -gt 8) {
        throw "#Include nesting is too deep at '$Path'."
    }
    $directory = Split-Path -Parent $Path
    $text = Get-Content -LiteralPath $Path -Raw
    $pattern = '(?m)^[ \t]*#Include[ \t]+(?:\*i[ \t]+)?(.+?)[ \t]*\r?$'
    while ($true) {
        $match = [regex]::Match($text, $pattern)
        if (-not $match.Success) {
            break
        }
        $included = $match.Groups[1].Value.Trim('"')
        if (-not [System.IO.Path]::IsPathRooted($included)) {
            $included = Join-Path $directory $included
        }
        if (-not (Test-Path -LiteralPath $included)) {
            throw "#Include target was not found: $included"
        }
        # Fully resolved by the recursion, so the replacement never reintroduces
        # a directive and this loop always terminates.
        $replacement = Get-EffectiveSource -Path $included -Depth ($Depth + 1)
        $text = $text.Substring(0, $match.Index) + $replacement +
            $text.Substring($match.Index + $match.Length)
    }
    return $text
}

# Every top-level function in a source, as name / body / line / wrapped.
#
# A header at column zero is the whole project's convention, so the parser stays
# dumb enough that it cannot disagree with a human reading the same text. What it
# is NOT any more is single-line-only.
#
# The previous version required the entire header -- name, parameter list and
# brace -- on one line. Seven real definitions wrap their parameter lists, and
# every one of them was invisible to ALL of the checks built on this: the
# duplicate scan, the shadow scan, the manifest scans, and the cross-tree
# reachability check that exists because an unresolved call is a LOAD-time hang.
# Two of the seven are CreateProcessWithStandardToken and LaunchInteractiveApp,
# which is to say the privilege boundary was the least-checked part of the tree.
#
# Column-zero CALLS in the auto-execute section (SetTimer(...), OnExit(...))
# are not definitions and must not be collected. They are told apart by the only
# thing that actually distinguishes them: a definition's balanced header is
# followed by "{" and a call's is not.
function Get-AhkFunctionMap {
    param([Parameter(Mandatory = $true)][string]$Text)
    $lines = $Text -split "`n"
    $functions = New-Object System.Collections.Generic.List[object]
    $index = 0
    while ($index -lt $lines.Count) {
        $start = [regex]::Match($lines[$index], '^([A-Za-z_][A-Za-z0-9_]*)\(')
        if (-not $start.Success) {
            $index++
            continue
        }
        # The overwhelmingly common case, kept on its own fast path: the whole
        # header on one line. Only a line that opens a parameter list and does
        # NOT close it this way is worth accumulating, which keeps the scan below
        # off 20,000 lines of SteamShell.ahk.
        $scan = $index
        if ($lines[$index] -notmatch '^[A-Za-z_][A-Za-z0-9_]*\([^\r\n{}]*\)\s*\{\s*$') {
            # Accumulate until the header's parentheses balance. Bounded so a
            # stray "(" at column zero cannot swallow the rest of the file.
            $header = ""
            $balanced = $false
            while ($scan -lt $lines.Count -and ($scan - $index) -le 8) {
                $header += $(if ($scan -eq $index) { $lines[$scan] } else { " " + $lines[$scan].Trim() })
                # Count parentheses in CODE only. A default value like
                # `prefix := "("` or a trailing comment would otherwise unbalance
                # a header that is perfectly well formed. Strings first, then
                # comments -- a ";" inside a literal is not a comment.
                $bare = $header -replace '"(?:[^"`]|`.)*"', '""'
                $bare = $bare -replace '(?<!`);.*$', ''
                $depth = ($bare -replace '[^(]', '').Length -
                         ($bare -replace '[^)]', '').Length
                if ($depth -le 0) { $balanced = $true; break }
                $scan++
            }
            if (-not ($balanced -and $header -match '\)\s*\{\s*$')) {
                $index++
                continue
            }
        }
        $body = New-Object System.Collections.Generic.List[string]
        for ($copy = $index; $copy -le $scan; $copy++) { $body.Add($lines[$copy]) }
        $cursor = $scan + 1
        $closed = $false
        while ($cursor -lt $lines.Count) {
            $body.Add($lines[$cursor])
            if ($lines[$cursor] -eq '}') { $closed = $true; break }
            $cursor++
        }
        if ($closed) {
            $functions.Add([pscustomobject]@{
                Name    = $start.Groups[1].Value
                Body    = ($body -join "`n")
                Line    = $index + 1
                Wrapped = ($scan -gt $index)
            })
            $index = $cursor + 1
            continue
        }
        $index++
    }
    return $functions
}

function Get-AhkFunctionNames {
    param([Parameter(Mandatory = $true)][string]$Text)
    return @(Get-AhkFunctionMap -Text $Text | ForEach-Object { $_.Name })
}

# Two structural faults that are true of any AutoHotkey source and that the
# compiler will not report.
#
# A duplicate definition silently wins over the earlier one. A local named after
# a function is worse: AutoHotkey identifiers are case-insensitive, so
# `buffer := Buffer(...)` resolves the right-hand side to the unassigned local
# and throws at run time. That one shipped, and reached a user as a modal error
# dialog on the shell desktop.
function Assert-AhkStructure {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $names = Get-AhkFunctionNames -Text $Text
    $duplicates = @($names |
        Group-Object { $_.ToLowerInvariant() } |
        Where-Object Count -gt 1)
    Assert-True ($duplicates.Count -eq 0) (
        "Duplicate top-level functions in ${Label}: " +
        (($duplicates | ForEach-Object Name) -join ", "))

    # A local that shadows something callable, checked per FUNCTION rather than
    # per file.
    #
    # The rule is that a name cannot be both assigned as a local and called as
    # "name(" in the same body. In AutoHotkey the assignment makes it a local, so
    # the call resolves to that local instead of to the function or class it
    # looks like, and throws.
    #
    # The previous version compared assignments against the names of functions
    # DEFINED IN THIS PROJECT, which is why it never saw the bug it was written
    # for: `buffer := Buffer(...)` shadows a BUILT-IN class, and no builtin is
    # defined in any of these files. Both XFE RawInput sites sat there, throwing
    # into a bare try on every device, for as long as the check existed.
    #
    # Scoping it per function also removes the need for a list of builtin names
    # to keep up to date -- a list that would have failed the build on ordinary
    # locals like `send := SubStr(v, 6)`, which shadows Send() harmlessly because
    # nothing in that function calls it. The signal is the collision, not the name.
    $shadowed = @()
    foreach ($function in (Get-AhkFunctionMap -Text $Text)) {
        # Strings BEFORE comments: a ";" inside a string literal would otherwise
        # truncate the line and hide whatever follows it on that line.
        $code = $function.Body -replace '"(?:[^"`]|`.)*"', '""'
        $code = ($code -split "`n" |
            ForEach-Object { $_ -replace '(?<!`);.*$', '' }) -join "`n"
        $assigned = @{}
        foreach ($match in [regex]::Matches($code, '(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:=')) {
            $assigned[$match.Groups[1].Value.ToLowerInvariant()] = $match.Groups[1].Value
        }
        foreach ($match in [regex]::Matches($code, '(?<![.\w])([A-Za-z_][A-Za-z0-9_]*)\s*\(')) {
            $called = $match.Groups[1].Value.ToLowerInvariant()
            # Recursion is a name calling itself, not a local shadowing anything.
            if ($called -eq $function.Name.ToLowerInvariant()) { continue }
            if ($assigned.ContainsKey($called)) {
                $shadowed += ("$($function.Name)() at line $($function.Line): " +
                    "local '$($assigned[$called])' shadows the call '$($assigned[$called])('")
            }
        }
    }
    $shadowed = @($shadowed | Sort-Object -Unique)
    Assert-True ($shadowed.Count -eq 0) (
        "A local shadows something called in the same function in ${Label}, " +
        "which resolves the call to the local and throws at run time: " +
        ($shadowed -join "; "))

    # A wrapped expression must not put "(" first on its line.
    #
    # In v2 a line whose first non-whitespace character is "(" begins a
    # continuation SECTION, and the rest of that line is parsed as continuation
    # OPTIONS rather than as code. Wrapping a ternary as
    #
    #     value := Foo(
    #         (condition
    #             ? "a"
    #             : "b")
    #
    # therefore fails to load with "Invalid option. Specifically: condition" --
    # a load-time error, so nothing in the file runs. It reads as ordinary
    # formatting and survives review; only the AutoHotkey parser rejects it.
    #
    # A "(" line that closes on the same line is an expression and is fine, which
    # is why most wrapped parentheses here are unaffected. A bare "(" opening a
    # deliberate multi-line string is also fine. What is flagged is the case that
    # is neither: content after the "(" with no matching ")" on the line.
    $sectionLines = @()
    $lineNumber = 0
    foreach ($line in ($Text -split "`n")) {
        $lineNumber++
        if ($line -notmatch '^\s*\(\s*\S') { continue }
        $bare = $line -replace '"(?:[^"`]|`.)*"', '""'
        $bare = $bare -replace '(?<!`);.*$', ''
        $opens = [regex]::Matches($bare, '\(').Count
        $closes = [regex]::Matches($bare, '\)').Count
        if ($opens -le $closes) { continue }
        # A DELIBERATE continuation section may carry options on its opening
        # line -- "(LTrim", "(Join`s", "(Comments" and so on. Those are correct
        # and must not fail the build; only content that is not an option list
        # is the mistake this looks for.
        $after = ($bare -replace '^\s*\(', '').Trim()
        $isOptions = $true
        foreach ($token in ($after -split '\s+' | Where-Object { $_ -ne '' })) {
            if ($token -notmatch '^(?i)(Join.*|R?LTrim0?|RTrim0?|Comments?|Com|C|Quotes?|Q|`.)$') {
                $isOptions = $false
                break
            }
        }
        if (-not $isOptions) {
            $sectionLines += ("line ${lineNumber}: " + $line.Trim())
        }
    }
    Assert-True ($sectionLines.Count -eq 0) (
        "A line in ${Label} starts with '(' and does not close it on the same " +
        "line, so AutoHotkey reads it as a continuation section and parses the " +
        "rest of the line as options. Assign it to a local first: " +
        ($sectionLines -join "; "))
}

# Top-level functions as name -> body, for the shared-parity check. A body runs
# from the header to the first line that is exactly "}".
#
# Get-Content -Raw, not [System.IO.File]::ReadAllLines, for the reasons set out
# above Get-EffectiveSource. These are the same files, read for the same
# purpose, and there is no argument for decoding them one way here and the other
# way there -- the bodies this returns are regex-matched against patterns that
# were written for the Get-Content decoding.
function Get-AhkFunctionBodies {
    param([Parameter(Mandatory = $true)][string]$Path)
    $functions = @{}
    foreach ($function in (Get-AhkFunctionMap -Text (Get-Content -LiteralPath $Path -Raw))) {
        $functions[$function.Name] = $function.Body
    }
    return $functions
}

# Verifies that the functions both programs share are defined exactly once, in
# SteamShell-Shared.ahk, and nowhere else.
#
# The two trees are parallel programs, not a reference and a copy. This used to
# compare two copies and fail when they drifted -- a net that catches falls. The
# shared functions now live in one file that both trees #Include, which removes
# the edge instead: there is no second copy to drift from. What is left to check
# is that nobody puts one back. A function pasted into a tree shadows the shared
# definition and compiles perfectly, which is exactly the kind of failure this
# project cannot detect at run time.
#
# Everything it needs is now in one folder, so there is no "skip when the
# sibling tree is absent" path any more. That skip existed only because a frozen
# release snapshot held one tree; a snapshot is the whole folder now, and a
# silent skip is the last thing this check should be capable of.
# Reports same-named functions in both trees whose difference is only naming and
# formatting -- the drift that a raw similarity score hides.
#
# Raw text comparison is dominated by indentation and local variable names.
# XInputGetState scored 0.70 against its twin while being one algorithm with
# identical DllCalls: the distance was bufState against state, bEx against
# exButtons, and one tree indented. Six functions sat above 0.90 once those were
# normalised away, and every one of them was a duplicate nobody had decided on.
#
# This reports rather than fails. A high structural score is evidence, not a
# verdict -- SettingsEditorMouseWheel and its twin are deliberately separate, and
# a check that failed the build on similarity would be demanding they merge. The
# point is that new drift becomes visible in the same pass that would otherwise
# bury it.
function Report-StructuralDrift {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [double]$Threshold = 0.90,
        [switch]$Quiet
    )
    $a = Get-AhkFunctionBodies -Path (Join-Path $ProjectRoot "SteamShell.ahk")
    $b = Get-AhkFunctionBodies -Path (Join-Path $ProjectRoot "SteamShell-XFE.ahk")

    # Strip comments and blank lines, fold the alias pairs that exist only because
    # the two trees named the same concept differently, then replace every token
    # that is not a keyword or a known shared name with a placeholder.
    function Get-StructuralForm {
        param([string]$Body)
        $lines = @()
        foreach ($line in ($Body -split "`n")) {
            $code = ($line -replace '(?<!`);.*$', '').Trim()
            if ($code) { $lines += $code }
        }
        $text = $lines -join "`n"
        $text = $text -replace '\bShowNotification\b', 'NOTIFY'
        $text = $text -replace '\bSetStatus\b', 'NOTIFY'
        $text = $text -replace '"(?:[^"`]|`.)*"', 'STR'
        $text = $text -replace '\b\d+(?:\.\d+)?\b', 'NUM'
        return $text
    }

    $hits = @()
    foreach ($name in $a.Keys) {
        if (-not $b.ContainsKey($name)) { continue }
        $formA = Get-StructuralForm -Body $a[$name]
        $formB = Get-StructuralForm -Body $b[$name]
        if ($formA -eq $formB) {
            $hits += [pscustomobject]@{ Name = $name; Score = 1.0 }
            continue
        }
        # Cheap ratio: shared line count over the larger body. Enough to rank,
        # and it avoids a full diff over hundreds of pairs.
        $linesA = $formA -split "`n"
        $linesB = $formB -split "`n"
        $setB = @{}
        foreach ($l in $linesB) { $setB[$l] = $true }
        $common = 0
        foreach ($l in $linesA) { if ($setB.ContainsKey($l)) { $common++ } }
        $max = [Math]::Max($linesA.Count, $linesB.Count)
        if ($max -eq 0) { continue }
        $score = $common / $max
        if ($score -ge $Threshold) {
            $hits += [pscustomobject]@{ Name = $name; Score = [Math]::Round($score, 2) }
        }
    }
    if (-not $Quiet) {
        if ($hits.Count -eq 0) {
            Write-Host "Structural drift: none above $Threshold."
        } else {
            $list = ($hits | Sort-Object -Property Score -Descending |
                ForEach-Object { "$($_.Name) ($($_.Score))" }) -join ", "
            Write-Host ("Structural drift: {0} function(s) at or above {1} once naming and formatting are ignored -- {2}" -f $hits.Count, $Threshold, $list)
        }
    }
    return $hits
}

# A naming- and comment-blind signature for a function body: the ordered
# sequence of calls it makes, plus its DllCall targets.
#
# WHY NOT COMPARE THE TEXT. Because text is exactly what changes when a copy is
# tidied. The advisory check this replaced compared bodies with -ceq and had
# found nothing for months, while an audit that measured *text* similarity
# scored ControllerBindingPretty at 0.26 and GetLastLines at 0.49 -- both of
# which have an IDENTICAL call sequence. One is a switch against a Map; the
# other is the same function with a parameter deleted. Thirty-four such pairs
# were being read as intentional divergence because nothing could see past the
# renaming.
#
# [regex]::Matches, not -match: the [A-Z] below has to stay case-SENSITIVE to
# pick out call sites rather than keywords, and PowerShell's -match operator is
# case-insensitive. .NET's static methods are not, which is the behaviour the
# Python replay in Replay-Validation.py also relies on. The two must compute the
# same number or the gate means nothing.
function Get-AhkCallFingerprint {
    param([Parameter(Mandatory = $true)][string]$Body)
    $sequence = New-Object System.Collections.Generic.List[string]
    $lines = $Body -split "`n"
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        # Read DllCall targets from the RAW line, before string literals are
        # blanked -- the target IS a string literal, so stripping first erases
        # the most informative token in the whole body.
        foreach ($m in [regex]::Matches($line, 'DllCall\(\s*"([^"]+)"')) {
            $target = ($m.Groups[1].Value -split '\\')[-1]
            $sequence.Add("dll:" + $target.ToLowerInvariant())
        }
        $bare = $line -replace '"(?:[^"`]|`.)*"', '""'
        $bare = $bare -replace '(?<!`);.*$', ''
        $bare = $bare -replace 'DllCall\([^)]*', ''
        foreach ($m in [regex]::Matches($bare, '(?<![.\w"])([A-Z][A-Za-z0-9_]{3,})\s*\(')) {
            if ($m.Groups[1].Value -ne "DllCall") {
                $sequence.Add($m.Groups[1].Value.ToLowerInvariant())
            }
        }
    }
    return , $sequence.ToArray()
}

# 2*LCS/(len+len). Written out longhand rather than pulled from a library so the
# Python replay can compute the identical value; a gate the two harnesses
# disagree about is worse than no gate at all.
function Get-SequenceSimilarity {
    param([string[]]$Left, [string[]]$Right)
    if ($Left.Count -eq 0 -and $Right.Count -eq 0) { return 1.0 }
    if ($Left.Count -eq 0 -or $Right.Count -eq 0) { return 0.0 }
    $previous = New-Object 'int[]' ($Right.Count + 1)
    $current = New-Object 'int[]' ($Right.Count + 1)
    foreach ($x in $Left) {
        $current[0] = 0
        for ($j = 0; $j -lt $Right.Count; $j++) {
            if ($x -ceq $Right[$j]) {
                $current[$j + 1] = $previous[$j] + 1
            } else {
                $current[$j + 1] = [Math]::Max($current[$j], $previous[$j + 1])
            }
        }
        $swap = $previous; $previous = $current; $current = $swap
    }
    return 2.0 * $previous[$Right.Count] / ($Left.Count + $Right.Count)
}

function Test-IsSubsequence {
    param([string[]]$Small, [string[]]$Big)
    $index = 0
    foreach ($item in $Big) {
        if ($index -lt $Small.Count -and $item -ceq $Small[$index]) { $index++ }
    }
    return $index -eq $Small.Count
}

# The text between a function's braces, by name. Empty when undefined.
function Get-AhkFunctionBody {
    param([string]$Source, [string]$Name)
    $match = [regex]::Match($Source, "(?m)^" + [regex]::Escape($Name) + "\(")
    if (-not $match.Success) { return "" }
    $i = $Source.IndexOf("{", $match.Index) + 1
    $depth = 1
    $j = $i
    while ($depth -gt 0 -and $j -lt $Source.Length) {
        if ($Source[$j] -eq "{") { $depth++ }
        elseif ($Source[$j] -eq "}") { $depth-- }
        $j++
    }
    return $Source.Substring($i, $j - $i - 1)
}

# Every `Name(...)` call, arguments split on top-level commas with quote state
# and paren depth tracked.
#
# The Python replay computes this identically and must keep doing so. A regex
# that stopped at the first ")" reported 18 handlers as unreachable, every one a
# false alarm from a call wrapped across lines -- and an assertion that cries
# wolf 18 times gets switched off rather than fixed.
function Get-AhkCallArguments {
    param([string]$Source, [string]$Name)
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($m in [regex]::Matches($Source, "\b" + [regex]::Escape($Name) + "\(")) {
        $i = $m.Index + $m.Length
        $depth = 1
        $j = $i
        $inString = $false
        while ($depth -gt 0 -and $j -lt $Source.Length) {
            $c = $Source[$j]
            if ($c -eq '"') { $inString = -not $inString }
            elseif (-not $inString) {
                if ($c -eq "(") { $depth++ }
                elseif ($c -eq ")") { $depth-- }
            }
            $j++
        }
        # Not $args: that is an automatic variable holding the function's own
        # unbound arguments, and assigning to it here would be shadowing a
        # reserved name for no reason.
        $argumentText = $Source.Substring($i, $j - $i - 1)
        $parts = New-Object System.Collections.Generic.List[string]
        $depth = 0
        $inString = $false
        $current = ""
        foreach ($c in $argumentText.ToCharArray()) {
            if ($c -eq '"') { $inString = -not $inString }
            if (-not $inString) {
                if ($c -eq "(" -or $c -eq "[") { $depth++ }
                elseif ($c -eq ")" -or $c -eq "]") { $depth-- }
                elseif ($c -eq "," -and $depth -eq 0) {
                    $parts.Add($current.Trim()); $current = ""; continue
                }
            }
            $current += $c
        }
        $parts.Add($current.Trim())
        $results.Add($parts.ToArray())
    }
    # Comma operator: PowerShell UNROLLS a collection on return, so a bare
    # `return $results.ToArray()` hands back the elements rather than the array.
    # Get-AhkCallFingerprint above already carries this for the same reason.
    return , $results.ToArray()
}

function Get-AhkStringLiteral {
    param([string]$Argument)
    $a = $Argument.Trim()
    if ($a.Length -gt 1 -and $a[0] -eq '"' -and $a[-1] -eq '"' -and
        -not $a.Substring(1, $a.Length - 2).Contains('"')) {
        return $a.Substring(1, $a.Length - 2)
    }
    return $null
}

function Get-AhkSwitchCaseLabels {
    param([string]$Body)
    $out = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($Body, "(?m)^\s*case\s+([^:\n]+):")) {
        foreach ($s in [regex]::Matches($m.Groups[1].Value, '"([^"]+)"')) {
            [void]$out.Add($s.Groups[1].Value)
        }
    }
    # Comma operator, or PowerShell unrolls the HashSet into an Object[] and the
    # caller's .Add() fails with "Collection was of a fixed size."
    return , $out
}

# Every Quick Menu row reaches behaviour, and every behaviour has a row.
#
# The fingerprint gate cannot see the Quick Menu: the two trees build rows
# differently, which drags every QuickMenu* function below the 0.75 threshold,
# so twelve functions and about 1,150 lines sit unmeasured in the one part of
# the program a user drives directly. Nothing about a broken row fails to
# compile -- a `case` that no longer exists falls through, so the row renders,
# selects, and does nothing.
#
# Checked in the ACTIVATE direction specifically. Accepting "reaches any
# handler" passes a row that still shows its value but no longer acts, which is
# the exact failure this exists to catch.
function Assert-QuickMenuRows {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $manifestPath = Join-Path $ProjectRoot "QUICKMENU_ROWS.txt"
    Assert-True (Test-Path -LiteralPath $manifestPath) (
        "QUICKMENU_ROWS.txt is missing; it is the row inventory this check enforces.")
    if (-not (Test-Path -LiteralPath $manifestPath)) { return }

    $recorded = @{}
    $dynamic = @{}
    foreach ($line in (Get-Content -LiteralPath $manifestPath)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
        $space = $trimmed.IndexOf(" ")
        if ($space -lt 1) { continue }
        $product = $trimmed.Substring(0, $space)
        $name = $trimmed.Substring($space + 1).Trim()
        if ($name.StartsWith("dynamic:")) {
            if (-not $dynamic.ContainsKey($product)) {
                $dynamic[$product] = New-Object System.Collections.Generic.HashSet[string]
            }
            [void]$dynamic[$product].Add($name.Substring(8))
        } else {
            if (-not $recorded.ContainsKey($product)) {
                $recorded[$product] = New-Object System.Collections.Generic.HashSet[string]
            }
            [void]$recorded[$product].Add($name)
        }
    }

    $families = @("layout:", "taskWindow:", "gamescore:", "toggle:", "page:")
    $sharedText = Get-Content -LiteralPath (Join-Path $ProjectRoot "SteamShell-Shared.ahk") -Raw
    $inert = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches(
        (Get-AhkFunctionBody -Source $sharedText -Name "QuickMenuRowIsInert"),
        '"([^"]+)",\s*true')) {
        [void]$inert.Add($m.Groups[1].Value)
    }

    foreach ($pair in @(
        @{ Product = "standalone"; File = "SteamShell.ahk"; Builder = "QuickMenuGetDefinitions" },
        @{ Product = "xfe";        File = "SteamShell-XFE.ahk"; Builder = "QuickMenuGetRows" })) {
        $text = Get-Content -LiteralPath (Join-Path $ProjectRoot $pair.File) -Raw
        $rowsBody = Get-AhkFunctionBody -Source $text -Name $pair.Builder
        Assert-True ($rowsBody -ne "") (
            "$($pair.File) defines no $($pair.Builder)(); the Quick Menu row inventory cannot be checked.")
        if ($rowsBody -eq "") { continue }

        # The two builders spell a row differently, and the extraction respects
        # that: treating MenuRow's "first argument is the id" rule as general
        # read standalone's Map("audio", ...) grouping key as a row id.
        $built = New-Object System.Collections.Generic.HashSet[string]
        $rowAction = @{}
        foreach ($a in (Get-AhkCallArguments -Source $rowsBody -Name "MenuRow")) {
            if ($a.Count -lt 1) { continue }
            $id = Get-AhkStringLiteral $a[0]
            if ($null -eq $id) { continue }
            [void]$built.Add($id)
            if ($a.Count -gt 3) { $rowAction[$id] = Get-AhkStringLiteral $a[3] }
        }
        # A row declaring "page" or "back" carries its own navigation and needs
        # no case at all. That is the point of the field: sixteen ids used to
        # reach two identical bodies.
        $navigating = New-Object System.Collections.Generic.HashSet[string]
        foreach ($a in (Get-AhkCallArguments -Source $rowsBody -Name "Map")) {
            if ($a.Count -gt 1 -and (Get-AhkStringLiteral $a[0]) -eq "id") {
                $id = Get-AhkStringLiteral $a[1]
                if ($null -ne $id) {
                    [void]$built.Add($id)
                    for ($k = 0; $k -lt $a.Count; $k += 2) {
                        $key = Get-AhkStringLiteral $a[$k]
                        if ($key -eq "page" -or $key -eq "back") {
                            [void]$navigating.Add($id)
                        }
                    }
                }
            }
        }
        $filtered = New-Object System.Collections.Generic.HashSet[string]
        foreach ($candidate in @($built)) {
            $isFamily = $false
            foreach ($prefix in $families) {
                if ($candidate.StartsWith($prefix)) { $isFamily = $true; break }
            }
            if (-not $isFamily) { [void]$filtered.Add($candidate) }
        }
        $built = $filtered

        $known = $recorded[$pair.Product]
        if ($null -eq $known) { $known = New-Object System.Collections.Generic.HashSet[string] }
        foreach ($gone in @($known | Where-Object { -not $built.Contains($_) } | Sort-Object)) {
            Assert-True $false (
                "$($pair.File): the Quick Menu row '$gone' is in QUICKMENU_ROWS.txt but no " +
                "longer built. If that is deliberate, delete the line in the same commit; a " +
                "row that vanishes silently is what this file exists to catch.")
        }
        foreach ($added in @($built | Where-Object { -not $known.Contains($_) } | Sort-Object)) {
            Assert-True $false (
                "$($pair.File): the Quick Menu builds a row '$added' that QUICKMENU_ROWS.txt " +
                "does not record. Add it, so the inventory stays the list of rows that exist.")
        }

        $handlers = Get-AhkSwitchCaseLabels (
            Get-AhkFunctionBody -Source $text -Name "QuickMenuActivateSelected")
        foreach ($label in (Get-AhkSwitchCaseLabels (
            Get-AhkFunctionBody -Source $text -Name "QuickMenuAdjustSelected"))) {
            [void]$handlers.Add($label)
        }
        foreach ($fn in @("IsQuickMenuToggleSetting", "IsQuickMenuAdjustSetting")) {
            foreach ($m in [regex]::Matches(
                (Get-AhkFunctionBody -Source $text -Name $fn), "[A-Za-z]\w*")) {
                [void]$handlers.Add($m.Value)
            }
        }
        # Actions both products implement identically live in Shared now, so a
        # row can reach its behaviour without either tree naming it.
        foreach ($label in (Get-AhkSwitchCaseLabels (
            Get-AhkFunctionBody -Source $sharedText -Name "QuickMenuActivateShared"))) {
            [void]$handlers.Add($label)
        }

        foreach ($row in @($built | Sort-Object)) {
            if ($rowAction.ContainsKey($row)) {
                $action = $rowAction[$row]
                if ($null -eq $action -or $action -eq "none" -or
                    ($families | Where-Object { $action.StartsWith($_) }) -or
                    $handlers.Contains($action)) { continue }
                Assert-True $false (
                    "$($pair.File): the Quick Menu row '$row' carries action '$action', which " +
                    "no handler implements. It would render and do nothing when selected.")
                continue
            }
            if ($handlers.Contains($row) -or $inert.Contains($row) -or
                $navigating.Contains($row)) { continue }
            Assert-True $false (
                "$($pair.File): the Quick Menu row '$row' reaches no activate, adjust or " +
                "toggle handler and is not declared inert. It would render and do nothing " +
                "when selected. If it is display-only, add it to QuickMenuRowIsInert so that " +
                "is stated rather than inferred from a missing case.")
        }

        $rowActions = New-Object System.Collections.Generic.HashSet[string]
        foreach ($v in $rowAction.Values) { if ($null -ne $v) { [void]$rowActions.Add($v) } }
        $allowed = New-Object System.Collections.Generic.HashSet[string]
        foreach ($s in @($built) + @($inert)) { [void]$allowed.Add($s) }
        if ($dynamic.ContainsKey($pair.Product)) {
            foreach ($s in $dynamic[$pair.Product]) { [void]$allowed.Add($s) }
        }
        foreach ($fn in @("QuickMenuActivateSelected", "QuickMenuAdjustSelected")) {
            foreach ($label in @((Get-AhkSwitchCaseLabels (
                Get-AhkFunctionBody -Source $text -Name $fn)) | Sort-Object)) {
                if ($families | Where-Object { $label.StartsWith($_) }) { continue }
                if ($allowed.Contains($label) -or $rowActions.Contains($label)) { continue }
                Assert-True $false (
                    "$($pair.File): $fn handles '$label', which no Quick Menu row builds. " +
                    "Delete the case, or record it in QUICKMENU_ROWS.txt as 'dynamic:' if a " +
                    "variable reaches it.")
            }
        }
    }

    if (-not $Quiet) {
        # Parenthesised because -f binds tighter than +: without them the format
        # operator applied to the SECOND string, which has no placeholders, and
        # the line printed the literal "{0}" and "{1}" it was meant to fill.
        $rowTotal = (@($recorded.Values | ForEach-Object { $_.Count }) |
            Measure-Object -Sum).Sum
        Write-Host (("Quick Menu rows: {0} recorded across {1} products; every row " +
            "reaches an activate path and every handler has a row.") -f
            $rowTotal, $recorded.Count)
    }
}

function Assert-SharedParity {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $standalonePath = Join-Path $ProjectRoot "SteamShell.ahk"
    $companionPath = Join-Path $ProjectRoot "SteamShell-XFE.ahk"
    $helperPath = Join-Path $ProjectRoot "SteamShell-Helper.ahk"
    $sharedPath = Join-Path $ProjectRoot "SteamShell-Shared.ahk"
    $manifestPath = Join-Path $ProjectRoot "SHARED_FUNCTIONS.txt"
    $commonPath = Join-Path $ProjectRoot "SteamShell-Common.ahk"
    $commonManifestPath = Join-Path $ProjectRoot "COMMON_FUNCTIONS.txt"
    $divergentPath = Join-Path $ProjectRoot "DIVERGENT_FUNCTIONS.txt"
    foreach ($required in @(
        $standalonePath, $companionPath, $helperPath,
        $sharedPath, $manifestPath, $commonPath, $commonManifestPath,
        $divergentPath)) {
        Assert-True (Test-Path -LiteralPath $required) (
            "Shared-parity check cannot run: '$required' was not found.")
    }

    $standalone = Get-AhkFunctionBodies -Path $standalonePath
    $companion = Get-AhkFunctionBodies -Path $companionPath
    $helper = Get-AhkFunctionBodies -Path $helperPath
    $shared = Get-AhkFunctionBodies -Path $sharedPath
    $common = Get-AhkFunctionBodies -Path $commonPath
    $manifest = @(
        Get-Content -LiteralPath $manifestPath |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }
    )
    $commonManifest = @(
        Get-Content -LiteralPath $commonManifestPath |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }
    )

    # SteamShell-Common.ahk is the half all THREE programs include, and the
    # invariant below is the only reason that is possible. AutoHotkey resolves a
    # call to an undefined function at LOAD time and #Include is all-or-nothing,
    # so one reference out of this file into a tree stops the helper compiling.
    # It is also what keeps the High-integrity binary from silently depending on
    # state it does not have.
    #
    # Checked mechanically rather than trusted, because SteamShell-Shared.ahk
    # documented a two-function seam and had quietly grown to eight before
    # anything noticed -- the validator only ever pinned the two it named.
    $commonText = Get-Content -LiteralPath $commonPath -Raw
    $commonGlobals = @(
        [regex]::Matches($commonText, '(?m)^\s*global\s+(\w+)') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    Assert-True ($commonGlobals.Count -eq 0) (
        "SteamShell-Common.ahk declares globals, so it can no longer be included " +
        "by every program: " + ($commonGlobals -join ", ") +
        ". Move the function to SteamShell-Shared.ahk, or pass the value in.")
    # Full-line comments are stripped first. A comment naming a shared function --
    # "this moved here because QuickMenuRowAcceptsRepeat moved" -- explains the
    # boundary rather than crossing it, and the raw text scan counted it as a
    # dependency. Code and strings are still scanned, because those can act.
    $commonCode = (($commonText -split "`n") |
        Where-Object { $_ -notmatch '^\s*;' }) -join "`n"
    $commonEscapes = @(
        $shared.Keys | Where-Object {
            $commonCode -match ('(?<![.\w])' + [regex]::Escape($_) + '\b') })
    Assert-True ($commonEscapes.Count -eq 0) (
        "SteamShell-Common.ahk reaches into SteamShell-Shared.ahk, which stops " +
        "SteamShell-Helper.ahk compiling at all: " + ($commonEscapes -join ", ") + ".")

    # The seam, as an ALLOWLIST rather than as prose.
    #
    # SteamShell-Shared.ahk documented two permitted callbacks and had grown to
    # eight before anyone noticed, because nothing enumerated what actually left
    # the file. This enumerates: every call in SteamShell-Common.ahk that is not
    # defined there and is not an AutoHotkey builtin must be on this list.
    $commonSeamAllowed = @("LogLine")
    $commonCode = ($commonText -split "`n" |
        ForEach-Object { $_ -replace '(?<!`);.*$', '' }) -join "`n"
    $commonCode = $commonCode -replace '"(?:[^"`]|`.)*"', '""'
    $commonCalled = @(
        [regex]::Matches($commonCode, '(?<![.\w])([A-Za-z_]\w*)\s*\(') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    # EVERY call in each program must resolve after #Include.
    #
    # AutoHotkey resolves an unknown function at LOAD time, so a call into a
    # function that lives in the other tree does not fail at run time -- the
    # script fails to parse. `/Validate` then reports it in a modal dialog, and
    # the harness, which waits on the process, hangs instead of failing. That
    # happened: the companion's new scheduled-task path called
    # CaptureExecutablePidSet and WaitForNewExecutablePid, which existed only in
    # SteamShell.ahk, and the build stopped dead with no error text at all.
    #
    # A hang is the worst failure mode a check can have, so this is checked here
    # where it produces a message.
    # Checked for all THREE programs against ALL the files they do not compile.
    #
    # The previous version asked one question -- "does XFE or the helper call
    # something that exists only in SteamShell.ahk?" -- which left three routes
    # to the same load-time failure unchecked: SteamShell.ahk calling into the
    # helper, either tree calling the other's private functions, and the helper
    # reaching for anything in SteamShell-Shared.ahk, which it deliberately does
    # not include. Enumerating the compiled set per program covers all of them
    # and cannot go stale when a fourth file appears; it only has to be listed.
    $definitionsBy = @{
        "SteamShell.ahk"        = $standalone
        "SteamShell-XFE.ahk"    = $companion
        "SteamShell-Helper.ahk" = $helper
        "SteamShell-Shared.ahk" = $shared
        "SteamShell-Common.ahk" = $common
    }
    $compiles = @{
        "SteamShell.ahk"        = @("SteamShell.ahk", "SteamShell-Shared.ahk", "SteamShell-Common.ahk")
        "SteamShell-XFE.ahk"    = @("SteamShell-XFE.ahk", "SteamShell-Shared.ahk", "SteamShell-Common.ahk")
        "SteamShell-Helper.ahk" = @("SteamShell-Helper.ahk", "SteamShell-Common.ahk")
    }
    $crossTreeLeaks = @()
    foreach ($program in @("SteamShell.ahk", "SteamShell-XFE.ahk", "SteamShell-Helper.ahk")) {
        $included = $compiles[$program]
        $reachable = @{}
        $callText = ""
        foreach ($file in $included) {
            foreach ($k in $definitionsBy[$file].Keys) { $reachable[$k] = $true }
            $callText += ($definitionsBy[$file].Values -join "`n") + "`n"
        }
        # Comments and string bodies removed. Tolerable while only `Name(` was
        # matched; not tolerable once a bare name counts, because every comment
        # that MENTIONS a function would be reported as a missing callback.
        $callCode = (($callText -split "`n") |
            ForEach-Object { $_ -replace '"(?:[^"`]|`.)*"', '""' } |
            ForEach-Object { $_ -replace '(?<!`);.*$', '' }) -join "`n"
        foreach ($file in $definitionsBy.Keys) {
            if ($included -contains $file) { continue }
            foreach ($name in $definitionsBy[$file].Keys) {
                if ($reachable.ContainsKey($name)) { continue }
                if ($callCode -match ('(?<![.\w])' + [regex]::Escape($name) + '\s*\(')) {
                    $crossTreeLeaks +=
                        "$program calls '$name', which is defined only in $file and is not compiled into it"
                }
                # A callback is passed by NAME, with no parentheses:
                #
                #   btnOk.OnEvent("Click", RecordShortcutChord_Accept)
                #
                # The pattern above cannot see that, so a shared function naming
                # standalone's handler shipped into the companion, where
                # AutoHotkey read the name as a local that is never assigned and
                # wired the OK button to nothing. That is worse than a missing
                # call: nothing fails to load, and one control silently does not
                # work.
                #
                # Skipped when the name is ASSIGNED anywhere in the compiled set,
                # because then it is an ordinary variable that happens to share a
                # name with a function in the other tree -- AutoHotkey
                # identifiers are case-insensitive, and standalone's local
                # `settingsPrimaryActive` collides with the companion's
                # SettingsPrimaryActive(). A callback is never assigned to.
                elseif (($callCode -match
                            ('(?<![.\w$])' + [regex]::Escape($name) + '(?![\w(])')) -and
                        -not ($callCode -match
                            ('(?<![.\w])' + [regex]::Escape($name) + '\s*(?::=|\+=|-=|\.=)'))) {
                    $crossTreeLeaks +=
                        "$program references '$name' as a callback, and it is defined only " +
                        "in $file, so the handler is silently never wired up"
                }
            }
        }
    }
    $crossTreeLeaks = @($crossTreeLeaks | Sort-Object -Unique)
    Assert-True ($crossTreeLeaks.Count -eq 0) (
        "A program calls a function it cannot see, which is a LOAD-time failure " +
        "in AutoHotkey, not a run-time one: " + ($crossTreeLeaks -join "; ") +
        ". Move the callee into SteamShell-Common.ahk.")

    $commonLeaks = @(
        $commonCalled | Where-Object {
            -not $common.ContainsKey($_) -and
            $commonSeamAllowed -notcontains $_ -and
            ($standalone.ContainsKey($_) -or $companion.ContainsKey($_) -or
             $helper.ContainsKey($_) -or $shared.ContainsKey($_)) })
    Assert-True ($commonLeaks.Count -eq 0) (
        "SteamShell-Common.ahk calls out to functions that are not on its seam " +
        "allowlist (" + ($commonSeamAllowed -join ", ") + "): " +
        ($commonLeaks -join ", ") +
        ". Move the callee in, pass the value as a parameter, or widen the " +
        "allowlist deliberately.")
    foreach ($name in $commonSeamAllowed) {
        foreach ($pair in @(
            @{ Name = "SteamShell.ahk"; Table = $standalone },
            @{ Name = "SteamShell-XFE.ahk"; Table = $companion },
            @{ Name = "SteamShell-Helper.ahk"; Table = $helper })) {
            Assert-True ($pair.Table.ContainsKey($name)) (
                "$($pair.Name) does not define '$name', which " +
                "SteamShell-Common.ahk depends on. AutoHotkey resolves that at " +
                "load time, so the program would not start.")
        }
    }

    $commonMissing = @($commonManifest | Where-Object { -not $common.ContainsKey($_) })
    Assert-True ($commonMissing.Count -eq 0) (
        "Functions listed in COMMON_FUNCTIONS.txt are not defined in " +
        "SteamShell-Common.ahk: " + ($commonMissing -join ", ") + ".")
    $commonUnlisted = @(
        $common.Keys | Where-Object { $commonManifest -notcontains $_ } | Sort-Object)
    Assert-True ($commonUnlisted.Count -eq 0) (
        "SteamShell-Common.ahk defines functions COMMON_FUNCTIONS.txt does not " +
        "list: " + ($commonUnlisted -join ", ") + ". Add them in the same commit.")
    $commonShadowed = @()
    foreach ($pair in @(
        @{ Name = "SteamShell.ahk"; Table = $standalone },
        @{ Name = "SteamShell-XFE.ahk"; Table = $companion },
        @{ Name = "SteamShell-Helper.ahk"; Table = $helper },
        @{ Name = "SteamShell-Shared.ahk"; Table = $shared })) {
        foreach ($name in $commonManifest) {
            if ($pair.Table.ContainsKey($name)) {
                $commonShadowed += "$name (also defined in $($pair.Name))"
            }
        }
    }
    Assert-True ($commonShadowed.Count -eq 0) (
        "Common functions are redefined elsewhere, which shadows the shared " +
        "definition and still compiles: " + ($commonShadowed -join ", ") + ".")

    # All THREE must include it. This is the assertion that turns "the helper
    # happens to have similar code" into "the helper genuinely shares it".
    foreach ($program in @($standalonePath, $companionPath, $helperPath)) {
        $text = Get-Content -LiteralPath $program -Raw
        Assert-True ($text -match '(?m)^#Include\s+SteamShell-Common\.ahk\s*$') (
            "$([System.IO.Path]::GetFileName($program)) does not #Include " +
            "SteamShell-Common.ahk, so it carries its own copy of shared logic.")
    }
    # ...and the helper must NOT include the tree-coupled half, which reaches
    # into eight tree functions and would not compile there.
    $helperText = Get-Content -LiteralPath $helperPath -Raw
    Assert-True (-not ($helperText -match '(?m)^#Include\s+SteamShell-Shared\.ahk\s*$')) (
        "SteamShell-Helper.ahk includes SteamShell-Shared.ahk, which is the " +
        "tree-coupled half and cannot resolve from the helper.")

    # The two ends of the elevated RTSS channel must agree on their event names.
    #
    # The helper cannot include SteamShell-Shared.ahk, so these two names are
    # necessarily written out twice, in files that share no code. Nothing related
    # them until now. Getting them out of step does not fail to compile and does
    # not log anything useful: main simply waits out its timeout on an event
    # nobody will ever set, once per button press, with Critical on.
    $sharedText = Get-Content -LiteralPath $sharedPath -Raw
    foreach ($channel in @(
        @{ Label = "request"; Name = "SteamShellRtssApply" },
        @{ Label = "completion"; Name = "SteamShellRtssDone" })) {
        # One backslash. PowerShell single quotes do not process escapes, so
        # 'Local\\' would be two of them and could never match the source.
        $literal = 'Local\' + $channel.Name + '-'
        Assert-True ($sharedText -match [regex]::Escape($literal)) (
            "SteamShell-Shared.ahk no longer names the elevated RTSS " +
            "$($channel.Label) event 'Local\$($channel.Name)-'. Both ends of " +
            "that channel are literals in files that share no code.")
        Assert-True ($helperText -match [regex]::Escape($literal)) (
            "SteamShell-Helper.ahk no longer names the elevated RTSS " +
            "$($channel.Label) event 'Local\$($channel.Name)-', so it and " +
            "SteamShell-Shared.ahk are pointing at different objects. Main " +
            "would wait out its timeout on every frame cap write.")
    }

    # The same requirement for automatic mouse mode, which crosses from
    # SteamShell.ahk rather than from the shared file.
    #
    # This one is worth stating as a rule because of what it replaced. Both
    # processes used to decide independently whether the controller was a mouse,
    # and could not agree: the real answer depends on DesktopMode, which the
    # helper cannot observe. If this event stops being published or stops being
    # read, that divergence comes back silently -- automatic mouse mode simply
    # stops engaging over elevated windows, which looks like a controller
    # problem and not like a name.
    $standaloneText = Get-Content -LiteralPath $standalonePath -Raw
    foreach ($end in @(
        @{ File = "SteamShell.ahk"; Text = $standaloneText; Role = "publishes" },
        @{ File = "SteamShell-Helper.ahk"; Text = $helperText; Role = "reads" })) {
        Assert-True ($end.Text -match [regex]::Escape('Local\SteamShellAutoMouse-')) (
            "$($end.File) no longer names the automatic-mouse event " +
            "'Local\SteamShellAutoMouse-', which it $($end.Role). Both ends are " +
            "literals in files that share no code, and a mismatch presents as " +
            "automatic mouse mode never engaging over an elevated window.")
    }
    # ...and the helper must not grow a second answer of its own again.
    Assert-True ($helperText -match '(?m)^\s*autoMouse\s*:=\s*ParentAutoMouseModeActive\(\)') (
        "SteamShell-Helper.ahk no longer takes automatic mouse mode from " +
        "ParentAutoMouseModeActive(). Deriving it from the settings here is what " +
        "made the two processes disagree for every elevated window outside a " +
        "hardcoded four-name list.")

    $missing = @()
    $shadowed = @()
    foreach ($name in $manifest) {
        if (-not $shared.ContainsKey($name)) {
            $missing += $name
            continue
        }
        if ($standalone.ContainsKey($name)) {
            $shadowed += "$name (also defined in SteamShell.ahk)"
        }
        if ($companion.ContainsKey($name)) {
            $shadowed += "$name (also defined in SteamShell-XFE.ahk)"
        }
    }
    Assert-True ($missing.Count -eq 0) (
        "Functions listed in SHARED_FUNCTIONS.txt are not defined in " +
        "SteamShell-Shared.ahk: " + ($missing -join ", ") +
        ". If a function was deliberately moved back into both trees, remove it " +
        "from the manifest in the same commit.")
    Assert-True ($shadowed.Count -eq 0) (
        "Shared functions are redefined inside a tree, which shadows the shared " +
        "definition and still compiles: " + ($shadowed -join ", ") +
        ". Delete the copy, or move the function out of SteamShell-Shared.ahk " +
        "and drop it from the manifest to record the divergence.")

    # Anything defined in the shared file has to be listed. Otherwise the file
    # accumulates functions nobody has decided are shared, and the manifest
    # stops being the record it exists to be.
    $unlisted = @(
        $shared.Keys | Where-Object { $manifest -notcontains $_ } | Sort-Object)
    Assert-True ($unlisted.Count -eq 0) (
        "SteamShell-Shared.ahk defines functions that SHARED_FUNCTIONS.txt does " +
        "not list: " + ($unlisted -join ", ") +
        ". Add them to the manifest in the same commit.")

    # Both trees must include the shared file, or one silently loses every
    # function in it and fails at run time rather than at build time.
    foreach ($tree in @($standalonePath, $companionPath)) {
        $text = Get-Content -LiteralPath $tree -Raw
        Assert-True ($text -match '(?m)^#Include\s+SteamShell-Shared\.ahk\s*$') (
            "$([System.IO.Path]::GetFileName($tree)) does not #Include " +
            "SteamShell-Shared.ahk, so the shared functions are missing from it.")
    }

    # THE SHARED SEAM, AS AN ALLOWLIST rather than as prose.
    #
    # SteamShell-Common.ahk has had one of these since the day its invariant was
    # written, and the comment beside it says why: the shared file "documented
    # two permitted callbacks and had grown to eight before anyone noticed,
    # because nothing enumerated what actually left the file."
    #
    # It then grew to 28 -- while its own header still described three. The
    # failure the Common allowlist was built to prevent had already happened
    # again, in the file the comment was written about, because only Common ever
    # got the mechanism. This is that mechanism, applied where it was needed.
    #
    # Two assertions, and both matter. Every name here must be defined in BOTH
    # trees, because a missing one is not a compile error in AutoHotkey -- it is
    # an empty call at run time. And nothing may leave the shared file that is
    # not on this list, because that is the half that keeps the seam from
    # growing back.
    # Every offerable binding must do something, and everything it does must
    # have a name.
    #
    # ControllerBindingPretty is what the binding UI lists. An action it labels
    # but nothing executes is a choice the user can make that silently does
    # nothing -- the same shape as the Quick Menu row whose action no handler
    # answered. An action that executes but has no label shows the user its raw
    # internal name instead of words.
    #
    # Both directions, because they fail differently and neither is visible in a
    # build: the first is a dead binding, the second is a cosmetic leak, and the
    # only thing either costs at compile time is nothing at all.
    $sharedText = Get-Content -LiteralPath (
        Join-Path $projectRoot "SteamShell-Shared.ahk") -Raw
    $sharedActionBody = [regex]::Match(
        $sharedText,
        '(?ms)^ControllerBindingSharedAction\(action\)\s*\{.*?^\}\s*$').Value
    $sharedActions = @([regex]::Matches($sharedActionBody, 'case\s+"(\w+)"') |
        ForEach-Object { $_.Groups[1].Value })
    Assert-True ($sharedActions.Count -ge 10) (
        "ControllerBindingSharedAction could not be read; every controller " +
        "binding would be reported as unreachable.")
    foreach ($tree in @("SteamShell.ahk", "SteamShell-XFE.ahk")) {
        $treeText = Get-Content -LiteralPath (Join-Path $projectRoot $tree) -Raw
        $seamBody = [regex]::Match(
            $treeText,
            '(?ms)^ProductControllerBindingAction\(action\)\s*\{.*?^\}\s*$').Value
        Assert-True ($seamBody -ne "") (
            "$tree defines no ProductControllerBindingAction; the actions only " +
            "it implements would be unreachable.")
        $executable = @($sharedActions) +
            @([regex]::Matches($seamBody, 'case\s+"(\w+)"') |
                ForEach-Object { $_.Groups[1].Value }) + @("None")
        $prettyBody = [regex]::Match(
            $treeText,
            '(?ms)^ControllerBindingPretty\(key\)\s*\{.*?^\}\s*$').Value
        Assert-True ($prettyBody -ne "") (
            "$tree defines no ControllerBindingPretty; binding labels cannot be checked.")
        foreach ($action in ($executable | Sort-Object -Unique)) {
            Assert-True ($prettyBody -match ('"' + [regex]::Escape($action) + '"')) (
                "$tree executes controller binding '$action' but " +
                "ControllerBindingPretty gives it no label, so the binding UI " +
                "would show its raw internal name.")
        }
        # The reverse. Labelled actions are the KEYS: standalone writes them as
        # `case "X":` and the companion as the odd-numbered entries of a Map, so
        # each is read the way that tree actually spells them.
        if ($tree -eq "SteamShell.ahk") {
            $labelled = @([regex]::Matches($prettyBody, 'case\s+"(\w+)"') |
                ForEach-Object { $_.Groups[1].Value })
        } else {
            $labelMap = [regex]::Match($prettyBody, '(?s)labels\s*:=\s*Map\((.*?)\n\s*\)').Groups[1].Value
            $tokens = @([regex]::Matches($labelMap, '"([^"]*)"') |
                ForEach-Object { $_.Groups[1].Value })
            $labelled = @(for ($i = 0; $i -lt $tokens.Count; $i += 2) { $tokens[$i] })
        }
        Assert-True ($labelled.Count -ge 10) (
            "${tree}: the ControllerBindingPretty label set could not be read, so " +
            "a label with no action behind it would go unnoticed.")
        foreach ($label in ($labelled | Sort-Object -Unique)) {
            Assert-True ($executable -contains $label) (
                "$tree offers controller binding '$label' in " +
                "ControllerBindingPretty, but nothing executes it: choosing it " +
                "would bind a button that does nothing.")
        }
    }

    # A shared Quick Menu row steps these, so both trees must accept the same
    # range. A bound only one tree has makes the row lie: it shows the value it
    # just wrote while the other tree's reader clamps it away on the next reload,
    # which looks like a setting that will not stick rather than like a bug.
    # Derived from the shared page table rather than listed, so a row added there
    # is covered without anybody remembering to add it here too.
    #
    # A numeric Settings row states the range it accepts. If a tree's own read
    # clamps harder, the row accepts a value the next reload throws away -- the
    # user types it, it saves, and it comes back different, with nothing
    # failing. Five rows disagreed this way at once when the table was written,
    # including one range that no tree allowed at all.
    #
    # Where the two trees genuinely disagreed the union was taken, never the
    # intersection: widening accepts every value somebody has already
    # configured, narrowing silently reduces it.
    $sharedText = Get-Content -LiteralPath (
        Join-Path $projectRoot "SteamShell-Shared.ahk") -Raw
    $tableStart = $sharedText.IndexOf("SettingsCategoryRows(category) {")
    $tableEnd = $sharedText.IndexOf("return table.Has(category)", $tableStart)
    $tableText = $sharedText.Substring($tableStart, $tableEnd - $tableStart)
    # Bounded to ONE row. A lazy .{0,300} runs past the end of a row that has no
    # bounds and picks up the next row's, which reported the controller-index
    # dropdown as if it offered 1-300.
    $boundedRows = [regex]::Matches(
        $tableText,
        '(?s)"product", "(\w+)",(?:(?!Map\("product").)*?' +
        '"section", "(\w+)", "key", "(\w+)",(?:(?!Map\("product").)*?' +
        '"min", (\d+), "max", (\d+)')
    Assert-True ($boundedRows.Count -ge 10) (
        "The shared page table's numeric rows could not be read, so a Settings " +
        "row accepting a value its own product clamps away would go unnoticed.")
    foreach ($row in $boundedRows) {
        $product = $row.Groups[1].Value
        $section = $row.Groups[2].Value
        $key = $row.Groups[3].Value
        $low = $row.Groups[4].Value
        $high = $row.Groups[5].Value
        foreach ($tree in @("SteamShell.ahk", "SteamShell-XFE.ahk")) {
            if ($product -eq "standalone" -and $tree -ne "SteamShell.ahk") { continue }
            if ($product -eq "xfe" -and $tree -ne "SteamShell-XFE.ahk") { continue }
            $treeText = Get-Content -LiteralPath (Join-Path $projectRoot $tree) -Raw
            $flat = $treeText -replace '\s+', ' '
            # EVERY read of the key, not the first. A tree reads most settings
            # twice -- once into its globals at load, once to fill the Settings
            # window -- and checking only the first let two of them drift apart
            # inside the same tree, which is the same failure wearing a
            # different hat.
            $reads = [regex]::Matches(
                $flat,
                'ReadInt\( ?(?:MovedSettingSection\([^)]*\)|"' + [regex]::Escape($section) +
                '") ?, ?"' + [regex]::Escape($key) + '" ?, ?[^,]+, ?(\d+) ?, ?(\d+)\)')
            foreach ($read in $reads) {
                Assert-True (
                    $read.Groups[1].Value -eq $low -and $read.Groups[2].Value -eq $high) (
                    "${tree}: $section.$key is read with bounds " +
                    "$($read.Groups[1].Value)-$($read.Groups[2].Value) but its Settings row " +
                    "offers $low-$high. The row would accept a value the next reload clamps away.")
            }
        }
    }

    $sharedSeamAllowed = @(
        "LogLine", "SharedPersistSettings",
        "HideQuickMenu", "ShowQuickMenu",
        "ProductLaunchMinimized", "ProductQuickMenuBlockedReason",
        "MouseWatchDisabled", "MouseWatchHoldsCursorVisible",
        "PersistRtssCustomFrameCap", "ProductBestGameExe",
        "ProductCenterGui", "ProductDataDir", "ProductElevatedHelperAlive",
        "ProductHealthResults", "ProductIdentity",
        "OpenOSK", "OpenTouchKeyboard",
        "ProductApplyQuickMenuSetting", "ProductControllerBindingAction",
        "ProductControllerLearnConsumesReport", "ProductSetDialogActive",
        ; Only SettingsRegisterBuiltField is CALLED from the shared file. The
        ; browse, record and mark-dirty seams are passed as callbacks, and the
        ; reachability check covers those by requiring a bare reference to
        ; resolve in both trees -- which is the check that caught the shell's
        ; own browse handler being wired into a companion that does not define it.
        "SettingsProductAddSectionRow", "SettingsProductWireDependency",
        "SettingsRegisterBuiltField",
        "RevealWindow",
        "ProductSettingBool",
        "ProductSettingsScrollBar", "ProductSettingsViewportHeight",
        "ProductTrayBaseTip", "ProductTrayItems", "ProductVersionText",
        "QuickMenuActivateSelected", "QuickMenuAdjustSelected",
        "QuickMenuBuildGui", "QuickMenuCloseSelected",
        "QuickMenuMouseChoose", "QuickMenuNormalizeSelection",
        "QuickMenuRefresh", "QuickMenuValue")
    foreach ($name in $sharedSeamAllowed) {
        foreach ($pair in @(
            @{ Name = "SteamShell.ahk"; Table = $standalone },
            @{ Name = "SteamShell-XFE.ahk"; Table = $companion })) {
            Assert-True ($pair.Table.ContainsKey($name)) (
                "$($pair.Name) does not define '$name', which SteamShell-Shared.ahk " +
                "depends on. Shared code calls it and AutoHotkey will not fail the build.")
        }
    }
    # Full-line comments stripped first, for the same reason the Common scan
    # strips them: a comment naming a tree function explains the boundary rather
    # than crossing it.
    $sharedCode = (($sharedText -split "`n") |
        Where-Object { $_ -notmatch '^\s*;' }) -join "`n"
    $sharedCode = $sharedCode -replace '"(?:[^"`]|`.)*"', '""'
    $sharedLeaks = @(
        [regex]::Matches($sharedCode, '(?<![.\w])([A-Za-z_]\w*)\s*\(') |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique |
            Where-Object {
                -not $shared.ContainsKey($_) -and
                -not $common.ContainsKey($_) -and
                $sharedSeamAllowed -notcontains $_ -and
                ($standalone.ContainsKey($_) -or $companion.ContainsKey($_) -or
                 $helper.ContainsKey($_)) })
    Assert-True ($sharedLeaks.Count -eq 0) (
        "SteamShell-Shared.ahk calls into a tree through functions that are not " +
        "on its seam allowlist: " + ($sharedLeaks -join ", ") +
        ". Move the callee into the shared file, pass the value as a parameter, " +
        "or widen `$sharedSeamAllowed deliberately -- the point of the list is " +
        "that widening it is a decision somebody made.")

    # Every global the shared file touches must exist in BOTH trees.
    #
    # Its own header states this rule and nothing enforced it: HealthCheckGui
    # and HealthCheckResults are declared at the top of SteamShell.ahk and
    # nowhere at all in SteamShell-XFE.ahk. It survives only because
    # ShowHealthCheck happens to call RefreshHealthCheck before the Copy Report
    # button can be reached, so the variable is always assigned before it is
    # read. Move that one line and the companion throws on a button the shell
    # handles fine.
    $sharedGlobalNames = @(
        [regex]::Matches($sharedText, '(?m)^\s+global\s+([^\r\n]+)') |
            ForEach-Object { $_.Groups[1].Value -split ',' } |
            ForEach-Object { ($_ -replace ':=.*', '').Trim() } |
            Where-Object { $_ -match '^[A-Za-z_]\w*$' } |
            Sort-Object -Unique)
    foreach ($pair in @(
        @{ Name = "SteamShell.ahk"; Path = $standalonePath },
        @{ Name = "SteamShell-XFE.ahk"; Path = $companionPath })) {
        $treeText = Get-Content -LiteralPath $pair.Path -Raw
        $declared = @{}
        foreach ($m in [regex]::Matches($treeText, '(?m)^\s*global\s+([^\r\n]+)')) {
            foreach ($piece in ($m.Groups[1].Value -split ',')) {
                $bare = ($piece -replace ':=.*', '').Trim()
                if ($bare -match '^[A-Za-z_]\w*$') { $declared[$bare] = $true }
            }
        }
        $undeclared = @($sharedGlobalNames | Where-Object { -not $declared.ContainsKey($_) })
        Assert-True ($undeclared.Count -eq 0) (
            "SteamShell-Shared.ahk references globals that $($pair.Name) never " +
            "declares: " + ($undeclared -join ", ") + ". AutoHotkey resolves a " +
            "read of an unassigned variable to an error at run time, in whichever " +
            "product forgot it.")
    }

    # In-function global blocks must list everything they touch.
    #
    # Every one of these names is a SUPER-GLOBAL -- declared at depth zero, which
    # AutoHotkey makes readable and writable inside every function with no
    # declaration at all. The ~1,100 in-function `global` lines are therefore
    # documentation rather than a requirement, and nothing checked them, so they
    # were free to be wrong. They were: WindowEngineScoreWeights declared nine
    # and read a tenth, and the companion's LoadSettings omitted sixteen.
    #
    # Deleting them was the other option. They are kept because they are the only
    # statement of what state a function touches in a tree with 600 of them, and
    # this is what makes keeping them worth anything.
    $blockFailures = @()
    foreach ($pair in @(
        @{ Name = "SteamShell.ahk"; Path = $standalonePath },
        @{ Name = "SteamShell-XFE.ahk"; Path = $companionPath })) {
        $treeText = Get-Content -LiteralPath $pair.Path -Raw
        $supers = @{}
        foreach ($m in [regex]::Matches($treeText, '(?m)^global\s+([^\r\n]+)')) {
            $bare = $m.Groups[1].Value -replace '(?<!`);.*$', ''
            foreach ($piece in ($bare -split ',')) {
                if ($piece -match '^\s*([A-Za-z_]\w*)') {
                    $supers[$Matches[1].ToLowerInvariant()] = $true
                }
            }
        }
        # Built once per tree. Compiled, because it is applied ~840 times.
        if ($supers.Count -eq 0) { continue }
        $superMatcher = New-Object System.Text.RegularExpressions.Regex(
            ('\b(?:' + (($supers.Keys | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'),
            ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
             [System.Text.RegularExpressions.RegexOptions]::Compiled))
        foreach ($fn in (Get-AhkFunctionMap -Text $treeText)) {
            $declared = @{}
            foreach ($m in [regex]::Matches($fn.Body, '(?m)^\s+global\s+([^\r\n]+)')) {
                $bare = $m.Groups[1].Value -replace '(?<!`);.*$', ''
                foreach ($piece in ($bare -split ',')) {
                    if ($piece -match '^\s*([A-Za-z_]\w*)') {
                        $declared[$Matches[1].ToLowerInvariant()] = $true
                    }
                }
            }
            if ($declared.Count -eq 0) { continue }
            # One pass over the body against an alternation of the super-global
            # names, rather than tokenising every line and testing each word.
            #
            # The obvious version ran a \b(\w+)\b match per line across ~37,000
            # lines and did a hashtable lookup per token. That is minutes in
            # Windows PowerShell, and a check that appears to hang is the failure
            # mode this file warns about elsewhere -- nobody waits for it twice,
            # and then nobody runs the validator at all.
            $used = @{}
            $clean = $fn.Body -replace '"(?:[^"`]|`.)*"', '""'
            $clean = ($clean -split "`n" |
                ForEach-Object { $_ -replace '(?<!`);.*$', '' }) -join "`n"
            foreach ($m in $superMatcher.Matches($clean)) {
                $used[$m.Value.ToLowerInvariant()] = $true
            }
            $omitted = @($used.Keys | Where-Object { -not $declared.ContainsKey($_) } | Sort-Object)
            if ($omitted.Count -gt 0) {
                $blockFailures +=
                    "$($pair.Name):$($fn.Line) $($fn.Name)() omits " + ($omitted -join ", ")
            }
        }
    }
    Assert-True ($blockFailures.Count -eq 0) (
        "Functions declare a global block that does not list every super-global " +
        "they touch: " + ($blockFailures -join "; ") +
        ". The block is the only record of what state a function reaches; an " +
        "incomplete one is worse than none.")

    # THE FINGERPRINT GATE.
    #
    # This replaced an advisory that compared bodies with -ceq and reported
    # candidates to share. It found nothing, ever, because two copies of one
    # routine are never textually identical once either has been touched -- and
    # "0 identical duplicates" then read as evidence the consolidation was
    # complete. On a call-sequence comparison, 34 of the 67 functions defined in
    # both trees turned out to be the same routine written twice, about 526
    # lines. Six of the eight strict-subset pairs are XFE-inside-SS, which is not
    # two programs growing apart; it is one program copied and trimmed.
    #
    # It FAILS rather than advises, because an advisory nobody acts on is how
    # this got to 34. Divergence is now something declared in
    # DIVERGENT_FUNCTIONS.txt with a stated reason, not something drifted into.
    # A name listed TWICE fails here too. Five names once carried a PENDING
    # reason under one heading and a contradictory PERMANENT one under another,
    # and because the entries land in a hashtable the later silently won. The
    # PENDING half was the file's entire consolidation worklist, and neither
    # harness could see it. A file whose stated purpose is to make a count go
    # down cannot hold two answers for the same name.
    $divergent = @{}
    if (Test-Path -LiteralPath $divergentPath) {
        foreach ($line in (Get-Content -LiteralPath $divergentPath)) {
            $trimmed = $line.Trim()
            if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
            $split = $trimmed.IndexOf(":")
            if ($split -lt 0) {
                $key = $trimmed.ToLowerInvariant()
                $reason = ""
            } else {
                $key = $trimmed.Substring(0, $split).Trim().ToLowerInvariant()
                $reason = $trimmed.Substring($split + 1).Trim()
            }
            Assert-True (-not $divergent.ContainsKey($key)) (
                "DIVERGENT_FUNCTIONS.txt lists '$key' more than once. Only the " +
                "last entry counts, so the others are reasons no harness reads. " +
                "Keep one, and delete the entry entirely once the two copies " +
                "are merged.")
            $divergent[$key] = $reason
        }
    }
    $flagged = @{}
    $gateFailures = @()
    foreach ($name in ($standalone.Keys | Sort-Object)) {
        if (-not $companion.ContainsKey($name)) { continue }
        $left = Get-AhkCallFingerprint -Body $standalone[$name]
        $right = Get-AhkCallFingerprint -Body $companion[$name]
        $score = Get-SequenceSimilarity -Left $left -Right $right
        $subset = $false
        if ($left.Count -gt 0 -and $right.Count -gt 0 -and
            (($left -join "|") -cne ($right -join "|"))) {
            $subset = (Test-IsSubsequence -Small $left -Big $right) -or
                      (Test-IsSubsequence -Small $right -Big $left)
        }
        if ($score -lt 0.75 -and -not $subset) { continue }
        $key = $name.ToLowerInvariant()
        $flagged[$key] = $true
        if (-not $divergent.ContainsKey($key)) {
            $why = if ($subset) {
                "one is a strict subset of the other"
            } else {
                "call-sequence similarity {0:N2}" -f $score
            }
            $gateFailures +=
                "'$name' is defined in both trees and $why. Share it, or add it " +
                "to DIVERGENT_FUNCTIONS.txt with the reason it must differ"
        } elseif ($divergent[$key] -eq "") {
            $gateFailures +=
                "DIVERGENT_FUNCTIONS.txt lists '$name' with no reason after the " +
                "colon. The reason is the entire value of that file"
        }
    }
    Assert-True ($gateFailures.Count -eq 0) (
        "Functions defined in both trees are the same routine written twice: " +
        ($gateFailures -join "; ") + ".")

    # A stale entry fails too, so the allowlist cannot quietly become a list
    # nobody reads. Deleting the entry is part of merging the two copies.
    # An entry also earns its place by covering a Helper/Shared name collision,
    # which the gate above never sees: it compares the two TREES only.
    #
    # SteamShell-Helper.ahk cannot #Include SteamShell-Shared.ahk, so ReadBool,
    # ReadInt, InitXInput, HasLongBinding and SendChordSafe necessarily exist in
    # both. They are no longer two implementations -- each is a three-line
    # wrapper binding its own global to one definition in
    # SteamShell-Common.ahk -- but the NAME is still duplicated, and that is what
    # the entry records.
    #
    # This exemption existed in Replay-Validation.py and not here, so the two
    # harnesses disagreed: clean on the development machine, five failures on
    # Windows. That is the exact hazard the header of that file warns about, and
    # the reason both sides implement the fingerprint identically.
    $helperWrappers = @{}
    foreach ($name in $helper.Keys) {
        if ($shared.ContainsKey($name)) { $helperWrappers[$name.ToLowerInvariant()] = $true }
    }
    $staleDivergent = @(
        $divergent.Keys |
            Where-Object {
                -not $flagged.ContainsKey($_) -and -not $helperWrappers.ContainsKey($_) } |
            Sort-Object)
    Assert-True ($staleDivergent.Count -eq 0) (
        "DIVERGENT_FUNCTIONS.txt lists functions whose two copies no longer " +
        "diverge, or which are no longer defined in both trees: " +
        ($staleDivergent -join ", ") + ". Remove the entries.")

    if (-not $Quiet) {
        # Parenthesised before -f on purpose: the format operator binds tighter
        # than string concatenation, so without these the format is applied to
        # the second fragment alone and "{0}" is printed literally.
        Write-Host ((
            "Shared parity: {0} functions defined once in SteamShell-Shared.ahk " +
            "(two trees) and {1} in SteamShell-Common.ahk (all three programs); " +
            "no tree redefines any of them.") -f $manifest.Count, $commonManifest.Count)
        Write-Host ((
            "  Fingerprint gate: {0} of the {1} functions defined in both trees " +
            "are declared divergent in DIVERGENT_FUNCTIONS.txt.") -f
            $flagged.Count, @($standalone.Keys | Where-Object { $companion.ContainsKey($_) }).Count)
    }
}
