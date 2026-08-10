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

# Every source read once per process, and the cost of doing so reported.
#
# THE CACHE SAVED NOTHING, AND THE COUNTER IS WHY THIS SAYS SO. Measured on the
# UNC root this project is developed from:
#
#     15 file reads (92 served from cache) in 508 ms
#
# Half a second out of a twenty-six second validator. Ninety-two avoided reads,
# worth about two percent. The harness total moved 231.2s -> 235.9s, which is
# run-to-run noise.
#
# So file I/O was never the cost, over SMB or otherwise, and the two guesses that
# preceded this measurement -- first that the network dominated, then that the
# repeated reads did -- were both wrong. What is left is CPU: .NET regex, roughly
# 1,100 assertions, most of them (?s) patterns with .*? scanning an effective
# source of about 1.5 MB once the includes are inlined. Making that faster means
# running assertions against extracted function bodies instead of the whole file,
# which is a rewrite of all 1,100, not a tuning pass.
#
# THE CACHE STAYS ANYWAY, and not out of sunk cost: it is correct, it costs
# nothing, and the counter it carries is the record that stops the next person
# re-running this experiment. Optimising I/O here is finished. If the number in
# that line ever grows into seconds, something changed and it is worth looking
# again.
#
# Single-shot processes, so there is no staleness question: nothing writes to a
# source while a validator is reading it.
$script:sourceCache = @{}
$script:readCount = 0
$script:readHits = 0
$script:readMs = 0.0

function Get-SourceText {
    param([Parameter(Mandatory = $true)][string]$Path)
    $key = "R:" + $Path
    if ($script:sourceCache.ContainsKey($key)) {
        $script:readHits++
        return $script:sourceCache[$key]
    }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $text = Get-Content -LiteralPath $Path -Raw
    $script:readMs += $clock.Elapsed.TotalMilliseconds
    $script:readCount++
    $script:sourceCache[$key] = $text
    return $text
}

function Get-SourceLines {
    param([Parameter(Mandatory = $true)][string]$Path)
    $key = "L:" + $Path
    if ($script:sourceCache.ContainsKey($key)) {
        $script:readHits++
        return $script:sourceCache[$key]
    }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $lines = Get-Content -LiteralPath $Path
    $script:readMs += $clock.Elapsed.TotalMilliseconds
    $script:readCount++
    # Always an array. Get-Content returns a bare string for a one-line file and
    # $null for an empty one, and a caller doing .Count on either gets an answer
    # it did not mean.
    $script:sourceCache[$key] = @($lines)
    return $script:sourceCache[$key]
}

function Get-ReadStats {
    return ("{0} file reads ({1} served from cache) in {2:N0} ms" -f
        $script:readCount, $script:readHits, $script:readMs)
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
    # Cached whole, not just its reads. Resolving a tree means substring surgery
    # on 750 KB with Shared and Common spliced in, and each validator asks for
    # the same effective source three times.
    $cacheKey = "E:" + $Path
    if ($script:sourceCache.ContainsKey($cacheKey)) {
        $script:readHits++
        return $script:sourceCache[$cacheKey]
    }
    $directory = Split-Path -Parent $Path
    $text = Get-SourceText $Path
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
    $script:sourceCache[$cacheKey] = $text
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
    foreach ($function in (Get-AhkFunctionMap -Text (Get-SourceText $Path))) {
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
# The per-product seam: functions SteamShell-Shared.ahk calls that each tree
# answers for itself.
#
# SCRIPT SCOPE, not a local of Assert-SharedParity, because it now has two
# readers -- the fingerprint gate down there and Report-StructuralDrift just
# below. Both need the same list, and the alternative was a second copy, which is
# how the counts in this project keep going wrong. Assert-SharedParity holds the
# assertions ABOUT the list; the list itself lives here.
#
# Both Python replays read it out of this file by regex, so keep the literal
# `$sharedSeamAllowed = @(` and `$sharedSeamExpectedCount = N` spellings.
$sharedSeamAllowed = @(
    "SharedPersistSettings",
    # Each tree answers over its own foreground cache -- the companion
    # through CurrentForegroundExe, the shell through LastRealFgHwnd --
    # and ViewButtonReleased has to ask the question from the shared
    # file. Widened deliberately when that function stopped being the
    # companion's alone.
    "SteamIsInFront",
    "HideQuickMenu", "ShowQuickMenu",
    "ProductLaunchMinimized", "ProductQuickMenuBlockedReason",
    "MouseWatchDisabled", "MouseWatchHoldsCursorVisible",
    "ProductBestGameExe",
    "ProductCenterGui", "ProductDataDir", "ProductElevatedHelperAlive",
    "ProductHealthResults", "ProductIdentity",
    "OpenOSK", "OpenTouchKeyboard",
    "ProductApplyQuickMenuSetting", "ProductControllerBindingAction",
    # Widened for ControllerDiagnosticTick, which became shared when the shell
    # turned out to have the DiagnosticLogging row and no tick behind it. The
    # companion's half of the tick reports GameInput and a second backend name,
    # neither of which the shell has; a seam is the honest way to say so.
    "ProductControllerDiagnosticProbe",
    # Widened for the controller test and calibration window, which moved to
    # SteamShell-Shared.ahk when it turned out to be standalone-only for no
    # recorded reason rather than for a product one.
    #
    # Neither of these is a Product* name, and both are genuinely per-tree: the
    # two poll heads differ in which flags stand them down, which is the last
    # honest divergence in PollController, and ApplyRuntimeTimers arms a
    # different set of timers in each product. The window needs exactly two
    # things from its host -- "start polling the pad" and "put the timers back
    # the way the settings say" -- and asking through the pair each tree already
    # defines beats inventing a Product* wrapper over each that would do nothing
    # but forward.
    #
    # ShowControllerTest arms PollController unconditionally, which is what makes
    # the window work in the companion while the companion is DISABLED and its
    # poll timer cancelled. HideControllerTest hands that back to
    # ApplyRuntimeTimers, which cancels it again if it should be.
    "ApplyRuntimeTimers", "PollController",
    # Widened for the elevated-foreground input path, which moved to
    # SteamShell-Shared.ahk when the companion gained it. Automatic mouse
    # mode is a per-product question -- each tree matches the foreground
    # against its own list -- and the shared handler PUBLISHES the answer to
    # the helper on the tick it is computed, so both processes act on one
    # answer instead of two that could disagree.
    "AutoMouseModeActive",
    # Widened for the controller mapping editor, which became one window in
    # SteamShell-Shared.ahk instead of two. Four of these are the binding
    # VOCABULARY and its persistence, which are genuinely per product: the
    # companion speaks Xbox FSE's names and offers actions the shell does not,
    # and the two trees write their INI differently. The other two are the new
    # pair the editor needed -- saving a whole map, and the shell-only
    # bookkeeping of what was in front before one of our windows took over.
    "ControllerBindingLabels", "ControllerBindingPretty",
    "LoadControllerMappings", "RecordShortcutChord",
    "ProductSaveControllerMappings", "ProductCaptureLastRealForeground",
    # Only SettingsRegisterBuiltField is CALLED from the shared file. The
    # browse, record and mark-dirty seams are passed as CALLBACKS --
    # OnEvent("Click", SettingsProductBrowsePath.Bind(...)) -- and they are on
    # this list because the leak scan below now reads bare references as well as
    # calls. They were left off while it read only calls, which made the header's
    # "nothing may leave this file that is not on it" untrue of four names and
    # meant widening the seam here was not the decision it is supposed to be.
    #
    # The cross-tree reachability check still catches ONE tree dropping such a
    # handler. It cannot catch both dropping it; the leak scan can.
    "SettingsProductAddSectionRow", "SettingsProductTrackControl",
    "SettingsProductWireDependency",
    "SettingsProductBrowsePath", "SettingsProductMarkDirty",
    "SettingsProductRecordShortcut",
    "SettingsRegisterBuiltField",
    # Widened for the exe-list field, the last shell-only field builder, which
    # moved here when the reason recorded for the companion not having one
    # turned out to say only that it did not have one. The companion's single
    # exe list was a pipe-separated Edit the user punctuated by hand.
    #
    # Three, and each is a surface the two products genuinely answer for
    # themselves: a file dialog (the shell owns its to the Settings window, the
    # companion promotes it to topmost), a message box (the same difference),
    # and the status line, which is a CONTROL in the shell and a FUNCTION in the
    # companion. Everything above them -- validate, de-duplicate, insert,
    # remove, join for the INI -- is now written once.
    "SettingsProductSelectExe", "SettingsProductFieldMessage",
    "SettingsProductSetStatus",
    # Widened for the Live Log window, which moved here when the reason it was
    # the shell's alone turned out to be, in PRODUCT_SURFACES.txt's own words,
    # that portability "has not been asked". Asked; the answer was yes.
    #
    # ONE seam, and it is the half that is genuinely per product. The viewer is
    # about a log file and both products want the same one. The status block
    # above it is not: four of the shell's eight lines name Hands-Off, the
    # AlwaysFocus list and the window engine, and the companion has zero lines of
    # any of them, while Launcher Cleanup it has twenty-eight of. So each product
    # names its own lines and the window counts them.
    "ProductLiveLogStatusLines",
    # Widened for the same window's Open Log button, and this one is a boundary
    # rather than a preference. SteamShell IS the Windows shell, so a child it
    # starts inherits its token unless the launch crosses the standard-user
    # boundary through LaunchInteractiveApp; the companion is an ordinary user
    # process with nothing to leak and opens the file with Run. The shared
    # window must not choose between them, and the assertion list further down
    # this file names the shell's side of it by function.
    "ProductOpenLogFile",
    # Widened for the shared Settings chrome. The hint under the title names
    # the CONTROLS, and the two products do not bind the same ones -- RB is a
    # pointer action in the shell and a click in the companion, and only the
    # companion offers the on-screen keyboard here.
    "ProductSettingsHintLine",
    # Reached the same way, from the Health Check's Export button.
    "ExportDiagnosticBundle",
    "ProductSettingBool",
    "ProductSettingsScrollBar", "ProductSettingsViewportHeight",
    "ProductTrayBaseTip", "ProductTrayItems", "ProductVersionText",
    "QuickMenuActivateSelected", "QuickMenuAdjustSelected",
    "QuickMenuBuildGui", "QuickMenuCloseSelected",
    "QuickMenuMouseChoose",
    "QuickMenuRefresh", "QuickMenuValue")
# The seam's SIZE is asserted, not just its contents.
#
# Both file headers used to state a count in prose -- "three", then "24" --
# while the list itself grew to 28 and then 36. Twice the number was wrong,
# and the second time the Common header actively promised "the check that
# fails when it is wrong", which did not exist. Nothing read those numbers,
# so nothing could contradict them.
#
# Restated here, next to the list, and asserted in Assert-SharedParity: changing
# one without the other fails the build. Update the expectation in the same
# commit that changes the list, and say in the message why the seam moved.
$sharedSeamExpectedCount = 55

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
#
# THE SEAM IS EXEMPT FROM THE REPORT, for the same reason it is exempt from the
# gate a thousand lines below: $sharedSeamAllowed IS the record that these
# functions differ per product, so reporting them as drift asks for a decision
# that has already been made.
#
# It was not academic. Every green build printed `Structural drift: 1
# function(s) ... ProductIdentity (1)`, and it was a false positive twice over:
# both bodies are a static Map and a return, so the normalised forms match and
# score 1.00, and the two can never be shared because answering differently per
# product is the whole point of the function. A permanent warning-shaped line in
# a passing run teaches you to skip the section it lives in.
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

    $seamExempt = @{}
    foreach ($seamName in $script:sharedSeamAllowed) {
        $seamExempt[$seamName.ToLowerInvariant()] = $true
    }

    $hits = @()
    foreach ($name in $a.Keys) {
        if (-not $b.ContainsKey($name)) { continue }
        if ($seamExempt.ContainsKey($name.ToLowerInvariant())) { continue }
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
    foreach ($line in (Get-SourceLines $manifestPath)) {
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

    $families = @("layout:", "taskWindow:", "gamescore:", "toggle:", "page:",
        "currentapp:")
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    $inert = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches(
        (Get-AhkFunctionBody -Source $sharedText -Name "QuickMenuRowIsInert"),
        '"([^"]+)",\s*true')) {
        [void]$inert.Add($m.Groups[1].Value)
    }

    foreach ($pair in @(
        @{ Product = "standalone"; File = "SteamShell.ahk"; Builder = "QuickMenuGetDefinitions" },
        @{ Product = "xfe";        File = "SteamShell-XFE.ahk"; Builder = "QuickMenuGetRows" })) {
        $text = Get-SourceText (Join-Path $ProjectRoot $pair.File)
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

# Two ways an assertion stops checking anything without failing.
#
# KEPT IN STEP WITH check_validator_assertion_shapes in Replay-Validation.py.
#
# When code moves, an assertion that NAMES the moved function fails loudly and
# gets fixed. That case needs no help. The two that hurt keep passing:
#
# UNBOUNDED FORWARD SCANS. `(?s)Name\(\)\s*\{.*?Thing` reads as "Thing appears
# inside Name" and does not mean it: `.*?` runs to the end of the file, so once
# Thing moves out of Name the pattern finds it in a later function and the
# assertion passes for the wrong reason. Two real cases were found by writing
# this: the shell's untitled-legacy-surface rule, where deleting the rule did not
# fail the build, and the companion's assist-timer rule, which named a function
# that has never re-applied the timers. The bounded form is
# `(?:(?!\n\})[\s\S])*?`, already used widely here.
#
# A pattern terminating on `^}` bounds itself and is left alone -- combining the
# two makes the body scan stop before the newline the `^}` needs, which broke ten
# extractors when this rule was first applied indiscriminately.
#
# VACUOUS BODY CONSTRAINTS. `-notmatch '(?sm)^Name\(\)\s*\{...X'` says "Name's
# body must not contain X", and if the subject does not define Name it is true
# forever. Asserting a function is ABSENT is legitimate and reads as
# `-notmatch '(?m)^Name\('` with nothing after it; that form is not flagged.
#
# VACUOUS NEGATIVES. `$x = [regex]::Matches($subject, P)` with `$x.Count -eq 0`
# says "P must find nothing". Zero is also what P returns when it can no longer
# match anything at all, and from the outside those are the same green. This one
# bit: $strayViewDownResets counts open-coded `previousViewDown := false` resets,
# a variable rename took the name out from under it, and it went on passing while
# checking nothing. So the pattern must stay ANCHORED -- see
# Get-CountedPatternLiterals below.

# Every window a TREE builds must be named in PRODUCT_SURFACES.txt.
#
# KEPT IN STEP WITH check_product_surfaces in Replay-Validation.py.
#
# An INVENTORY, not a similarity measure, and that is the point. The fingerprint
# gate needs the same name in both trees, so a surface only one tree has never
# enters it -- the controller test sat in the shell for its whole life and
# nothing ever asked whether the companion should have it. The cross-name
# detector is the backstop for a surface both trees have under different names,
# and for the mapping editor it does not reach: 0.33 on call sequence with three
# shared calls is what two hand-written UIs over one data model look like.
#
# A Gui built in SteamShell-Shared.ahk needs no entry. Its absence is what says
# the surface is already shared, so this file shrinks as the products converge.
function Assert-ProductSurfaces {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $path = Join-Path $ProjectRoot "PRODUCT_SURFACES.txt"
    if (-not (Test-Path $path)) {
        Assert-True $false (
            "PRODUCT_SURFACES.txt is missing; every window a tree builds is " +
            "recorded there with the reason it is not built once.")
        return
    }
    $manifest = @{}
    $lineNumber = 0
    foreach ($line in (Get-SourceText $path) -split "`n") {
        $lineNumber++
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
        $split = $trimmed.IndexOf(":")
        if ($split -lt 1 -or $trimmed.Substring($split + 1).Trim() -eq "") {
            Assert-True $false (
                "PRODUCT_SURFACES.txt:${lineNumber} lists a surface with no " +
                "reason. A bare name is the state this file exists to end.")
            continue
        }
        $manifest[$trimmed.Substring(0, $split).Trim().ToLowerInvariant()] = $true
    }
    $built = @{}
    foreach ($tree in @("SteamShell.ahk", "SteamShell-XFE.ahk")) {
        $text = Get-SourceText (Join-Path $ProjectRoot $tree)
        foreach ($function in (Get-AhkFunctionMap -Text $text)) {
            $code = $function.Body -replace '"(?:[^"`]|`.)*"', '""'
            $code = ($code -split "`n" |
                ForEach-Object { $_ -replace '(?<!`);.*$', '' }) -join "`n"
            if ($code -match '(?<![.\w])Gui\(') {
                $key = $function.Name.ToLowerInvariant()
                if (-not $built.ContainsKey($key)) {
                    $built[$key] = "${tree}:$($function.Line)"
                }
            }
        }
    }
    foreach ($key in ($built.Keys | Sort-Object)) {
        if (-not $manifest.ContainsKey($key)) {
            Assert-True $false (
                "$($built[$key]) builds a Gui in ${key}(), which " +
                "PRODUCT_SURFACES.txt does not list. A window one product has " +
                "and the other does not is a decision -- record why this tree " +
                "builds its own, or move it to SteamShell-Shared.ahk so both " +
                "get it.")
        }
    }
    foreach ($key in ($manifest.Keys | Sort-Object)) {
        if (-not $built.ContainsKey($key)) {
            Assert-True $false (
                "PRODUCT_SURFACES.txt lists '${key}', which no longer builds a " +
                "Gui in either tree. Remove the entry -- a stale one turns this " +
                "file into a list nobody revisits, which is what it exists to " +
                "prevent.")
        }
    }
    if (-not $Quiet) {
        Write-Host ("Product surfaces: $($built.Count) windows built per tree, " +
            "each recorded with the reason it is not built once.")
    }
}

# What a counted pattern needs the subject to still contain.
#
# KEPT IN STEP WITH counted_pattern_literals in Replay-Validation.py.
#
# Returns Required -- every identifier named outside an alternation -- and
# Alternations, one branch-set per `|` group, of which at least ONE branch must
# be present. The split matters: the shell's composed-read ban is
# `(?:ClampInt|ClampFloat)\(...IniReadS\(`, and ClampFloat is defined in
# SteamShell-Common.ahk but never called in SteamShell.ahk. Requiring every name
# would flag that branch as dead when it deliberately bans a form nobody has
# written yet.
#
# Regex syntax is stripped first -- group prefixes, character classes, then
# escapes -- so `\s` and `[^\r\n]` contribute nothing. Identifiers shorter than
# four characters go with them, which is what makes a pure shape ban like
# `"x\d+ y\d+` name nothing and be skipped.
function Get-AssertionWords {
    param([string]$Text)
    $keywords = @(
        "static", "global", "local", "true", "false", "return", "else", "case",
        "while", "loop", "break", "continue", "catch", "finally", "throw", "then")
    $words = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in [regex]::Matches($Text, '[A-Za-z_]\w{3,}')) {
        if ($keywords -notcontains $m.Value.ToLowerInvariant()) {
            [void]$words.Add($m.Value)
        }
    }
    return , $words
}

function Get-CountedPatternLiterals {
    param([string]$Pattern)
    $text = [regex]::Replace($Pattern, '\(\?[a-zA-Z]*[:=!<]*', '(')
    $text = [regex]::Replace($text, '\[(?:[^\]\\]|\\.)*\]', ' ')
    $text = [regex]::Replace($text, '\\.', ' ')
    $groups = @()
    $depth = 0
    $start = 0
    for ($i = 0; $i -lt $text.Length; $i++) {
        if ($text[$i] -eq '(') {
            if ($depth -eq 0) { $start = $i }
            $depth++
        } elseif ($text[$i] -eq ')' -and $depth -gt 0) {
            $depth--
            if ($depth -eq 0) { $groups += , @($start, $i) }
        }
    }
    $alternations = @()
    $outside = ""
    $last = 0
    foreach ($g in $groups) {
        $outside += $text.Substring($last, $g[0] - $last)
        $last = $g[1] + 1
        $inner = $text.Substring($g[0] + 1, $g[1] - $g[0] - 1)
        if ($inner.Contains("|")) {
            $branches = @()
            $empty = $false
            foreach ($branch in $inner.Split("|")) {
                $words = Get-AssertionWords -Text $branch
                if ($words.Count -eq 0) { $empty = $true }
                $branches += , $words
            }
            # A branch naming nothing means the group imposes no requirement.
            if (-not $empty) { $alternations += , $branches }
        } else {
            $outside += " " + $inner + " "
        }
    }
    $outside += $text.Substring($last)
    return @{
        Required = Get-AssertionWords -Text $outside
        Alternations = $alternations
    }
}

function Assert-ValidatorAssertionShapes {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $definition = '([A-Za-z_]\w*)\\\((?:\[\^\)\]\*|)\\\)\\s\*\\\{'
    $checked = 0
    $counted = 0
    foreach ($pair in @(
        @{ Validator = "Validate-SteamShell.ps1";     Tree = "SteamShell.ahk" },
        @{ Validator = "Validate-SteamShell-XFE.ps1"; Tree = "SteamShell-XFE.ahk" })) {
        $text = Get-SourceText (Join-Path $ProjectRoot $pair.Validator)
        # $source is the EFFECTIVE source; $rawSource is the tree's own text.
        $subjects = @{
            "source" = Get-EffectiveSource -Path (Join-Path $ProjectRoot $pair.Tree)
            "rawsource" = Get-SourceText (Join-Path $ProjectRoot $pair.Tree)
            "commonsource" = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Common.ahk")
            "helpersource" = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Helper.ahk")
            "sharedsource" = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
        }
        foreach ($m in [regex]::Matches(
            $text,
            "\`$(\w+)(?:\.\w+)*\s+-(not)?match\s+((?:\s*(?:\+\s*)?'(?:[^']|'')*'\s*)+)")) {
            $subject = $m.Groups[1].Value.ToLowerInvariant()
            $negated = $m.Groups[2].Success
            $pattern = ""
            foreach ($piece in [regex]::Matches($m.Groups[3].Value, "'((?:[^']|'')*)'")) {
                $pattern += $piece.Groups[1].Value.Replace("''", "'")
            }
            $line = ($text.Substring(0, $m.Index) -split "`n").Count
            $found = [regex]::Match($pattern, $definition)
            if (-not $found.Success) { continue }
            $checked++
            $name = $found.Groups[1].Value
            $rest = $pattern.Substring($found.Index + $found.Length)
            if ($rest.StartsWith(".*?") -and $rest -notmatch '\^\\?\}') {
                Assert-True $false (
                    "$($pair.Validator):${line} anchors to $name()'s body and then " +
                    "scans forward with .*?, which runs past the end of it. Once " +
                    "the thing it looks for moves out of that function the " +
                    "assertion passes against some later one. Use " +
                    "(?:(?!``n``})[``s``S])*? to bound it to the body.")
            }
            if ($negated -and $rest.Trim() -ne "" -and $subjects.ContainsKey($subject) -and
                $subjects[$subject] -notmatch ("(?m)^" + [regex]::Escape($name) + "\(")) {
                Assert-True $false (
                    "$($pair.Validator):${line} constrains $name()'s body with " +
                    "-notmatch, but `$$($m.Groups[1].Value) does not define $name " +
                    "-- so it is true whatever the code does. Assert against a " +
                    "subject that has the function, or, if the point is that the " +
                    "function must not exist, drop the body constraint.")
            }
        }
        # The vacuous negative. Collect the variables whose Count is asserted to
        # be zero first, then check only the ones a [regex]::Matches feeds.
        $zeroed = @{}
        foreach ($m in [regex]::Matches($text, "\`$(\w+)\.Count\s+-eq\s+0")) {
            $zeroed[$m.Groups[1].Value] = $true
        }
        foreach ($m in [regex]::Matches(
            $text,
            "(?s)\`$(\w+)\s*=\s*@?\(?\s*\[regex\]::Matches\(\s*\`$(\w+)\s*,\s*" +
            "((?:\s*(?:\+\s*)?'(?:[^']|'')*'\s*)+)")) {
            $variable = $m.Groups[1].Value
            $subject = $m.Groups[2].Value.ToLowerInvariant()
            if (-not $zeroed.ContainsKey($variable)) { continue }
            if (-not $subjects.ContainsKey($subject)) { continue }
            $pattern = ""
            foreach ($piece in [regex]::Matches($m.Groups[3].Value, "'((?:[^']|'')*)'")) {
                $pattern += $piece.Groups[1].Value.Replace("''", "'")
            }
            $literals = Get-CountedPatternLiterals -Pattern $pattern
            $body = $subjects[$subject]
            $missing = @()
            foreach ($name in $literals.Required) {
                if (-not $body.Contains($name)) { $missing += $name }
            }
            foreach ($branches in $literals.Alternations) {
                $live = $false
                foreach ($branch in $branches) {
                    $all = $true
                    foreach ($name in $branch) {
                        if (-not $body.Contains($name)) { $all = $false }
                    }
                    if ($all) { $live = $true }
                }
                if (-not $live) {
                    # One representative name per branch, lexicographically
                    # smallest so the Python side words this identically.
                    $names = @()
                    foreach ($branch in $branches) {
                        $names += @($branch | Sort-Object)[0]
                    }
                    $missing += (($names | Sort-Object) -join "|")
                }
            }
            if ($missing.Count -gt 0) {
                $line = ($text.Substring(0, $m.Index) -split "`n").Count
                Assert-True $false (
                    "$($pair.Validator):${line} asserts `$$variable.Count -eq 0, " +
                    "but its pattern names " + (($missing | Sort-Object) -join ", ") +
                    ", which `$$($m.Groups[2].Value) no longer contains -- so it " +
                    "counts zero because it can no longer match anything, not " +
                    "because the thing it forbids is absent. Re-point the pattern " +
                    "at the name the code uses now.")
            }
            $counted++
        }
    }
    if (-not $Quiet) {
        Write-Host ("Validator assertions: $checked anchored to a function body; " +
            "all bounded to it and all against a subject that defines it. " +
            "$counted counted to zero; all still anchored to a name the tree has.")
    }
}

# The shared mapping tail of the controller poll, and the two things it resolved.
#
# KEPT IN STEP WITH check_controller_poll_frame in Replay-Validation.py.
#
# Both poll loops end in the same routine -- adopt buttons already held, move the
# cursor, scroll, Short/Long for buttons and triggers, D-pad, Guide -- and that
# is ControllerPollFrame. The heads above it stay per-product and genuinely
# differ. Two of the differences in the tail were not cosmetic and both resolved
# toward the shell's version; they are pinned here because they are invisible in
# use until a specific sequence of presses, and a tidy could undo either.
function Assert-ControllerPollFrame {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $body = Get-AhkFunctionBody `
        -Source (Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")) `
        -Name "ControllerPollFrame"
    Assert-True ($body -ne "") (
        "SteamShell-Shared.ahk defines no ControllerPollFrame(); both poll loops " +
        "would have to carry the mapping tail again.")
    if ($body -eq "") { return }

    # A button already being timed keeps its clock when the modifier goes down.
    Assert-True ($body -match '\(buttons & mask\) && !downTick\[name\]') (
        "ControllerPollFrame adopts a held button without checking " +
        "!downTick[name]. A hold already being timed restarts its clock the " +
        "moment the modifier goes down.")

    # An adopted trigger clears its long-fired flag, or a trigger that fired a
    # Long in an earlier hold never fires one again.
    foreach ($trigger in @("LT", "RT")) {
        $low = $trigger.ToLowerInvariant()
        Assert-True ($body -match "\($low > 30\) && !downTick\[""$trigger""\]") (
            "ControllerPollFrame adopts $trigger without checking " +
            "!downTick[""$trigger""].")
        $adopt = [regex]::Match(
            $body, "!downTick\[""$trigger""\]\)\s*\{(?<block>[\s\S]*?)\n        \}")
        Assert-True (
            $adopt.Success -and
            $adopt.Groups["block"].Value -match "longFired\[""$trigger""\] := false") (
            "ControllerPollFrame adopts $trigger without clearing " +
            "longFired[""$trigger""]. A trigger that fired a Long in an earlier " +
            "hold would never fire one again.")
    }

    # Ordering, per loop. Checked in EACH of the two rather than across the whole
    # body: one scan is satisfied by the trigger loop's copy even when the button
    # loop's has gone, which is how the first version of this passed a mutation
    # that deleted one of them.
    $halves = $body -split [regex]::Escape('for _, triggerName in ["LT", "RT"]')
    Assert-True ($halves.Count -eq 2) (
        "ControllerPollFrame no longer has one button loop and one trigger " +
        "loop; the ordering below cannot be checked.")
    if ($halves.Count -ne 2) { return }
    foreach ($pair in @(
        @{ Text = $halves[0]; What = "button" },
        @{ Text = $halves[1]; What = "trigger" })) {
        $hold = $pair.Text.IndexOf("ControllerBindingHoldsMouseButton(")
        $longTest = $pair.Text.IndexOf("HasLongBinding(")
        Assert-True ($hold -ge 0 -and $longTest -ge 0 -and $hold -lt $longTest) (
            "ControllerPollFrame's $($pair.What) loop no longer decides " +
            "hold-to-drag before Short and Long timing, so a drag binding would " +
            "also accrue a hold and fire an action on release.")
    }
    if (-not $Quiet) {
        Write-Host "Controller poll frame: shared, with its adopt and ordering rules intact."
    }
}

# The flags the trees build must be exactly the ones the helper parses.
#
# KEPT IN STEP WITH check_elevated_helper_protocol in Replay-Validation.py.
#
# SteamShell-Helper.exe is one binary serving both products, and its command line
# is a contract between three programs. It used to be written out by hand in four
# places, with nothing defining it and nothing comparing it against the helper.
#
# The failure that invites is quiet in the worst way: rename a flag in the helper
# and the callers still build the old spelling, so the helper starts, falls back
# to its default for the argument it did not recognise, and runs. For --product
# that default is "standalone", so an XFE helper silently becomes a shell helper
# with elevated input and geometry enabled.
function Assert-ElevatedHelperProtocol {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $builder = Get-AhkFunctionBody `
        -Source (Get-SourceText (Join-Path $ProjectRoot "SteamShell-Common.ahk")) `
        -Name "SharedElevatedHelperArguments"
    Assert-True ($builder -ne "") (
        "SteamShell-Common.ahk defines no SharedElevatedHelperArguments(); the " +
        "helper command line would have no single definition.")
    if ($builder -eq "") { return }

    # `" --parent-pid="` -- the separator lives inside the literal.
    $built = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($builder, '"\s*--([a-z-]+)=')) {
        [void]$built.Add($m.Groups[1].Value)
    }
    $helperText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Helper.ahk")
    $parsed = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($helperText, 'ReadArgument\(\s*"([a-z-]+)"')) {
        [void]$parsed.Add($m.Groups[1].Value)
    }
    Assert-True ($parsed.Count -ge 4) (
        "Only $($parsed.Count) ReadArgument calls were read from " +
        "SteamShell-Helper.ahk; the scan is not seeing them.")
    if ($parsed.Count -lt 4) { return }

    foreach ($flag in @($built | Where-Object { -not $parsed.Contains($_) } | Sort-Object)) {
        Assert-True $false (
            "SharedElevatedHelperArguments builds --$flag= and " +
            "SteamShell-Helper.ahk never reads it. The helper would ignore it " +
            "and start anyway.")
    }
    foreach ($flag in @($parsed | Where-Object { -not $built.Contains($_) } | Sort-Object)) {
        Assert-True $false (
            "SteamShell-Helper.ahk reads --$flag= and " +
            "SharedElevatedHelperArguments never builds it. The helper falls " +
            "back to its default, which for --product is the WRONG product.")
    }

    # Nobody may go around the builder. Comments go, string bodies STAY: the
    # flags being looked for ARE string literals, so blanking them would make
    # this pass on the very thing it exists to catch.
    foreach ($tree in @("SteamShell.ahk", "SteamShell-XFE.ahk")) {
        $lines = @()
        foreach ($line in (Get-SourceLines (Join-Path $ProjectRoot $tree))) {
            $lines += ($line -replace '(?<!`);.*$', '')
        }
        $code = $lines -join "`n"
        foreach ($m in [regex]::Matches($code, '--([a-z-]+)=')) {
            $flag = $m.Groups[1].Value
            if (-not $parsed.Contains($flag)) { continue }
            Assert-True $false (
                "$tree spells --$flag= itself instead of calling " +
                "SharedElevatedHelperArguments. Four hand-written copies of this " +
                "command line is what that function exists to end.")
        }
    }
    if (-not $Quiet) {
        Write-Host ("Elevated helper protocol: $($built.Count) flags, built in one " +
            "place and all read by the helper.")
    }
}

# The Quick Menu's Current Application page.
#
# Three contracts:
#
# 1. EVERY DESTINATION WRITES SOMEWHERE ITS PRODUCT READS. A row that appends to
#    a section and key nothing consumes would report success, write the value,
#    and change nothing -- and the user would have watched it say "added". The
#    table is product-tagged, so the check follows the tag: a "standalone" row is
#    held against the shell's reads, an "xfe" row against the companion's, and a
#    "both" row against both.
#
# 2. THE STORE-APP REFUSAL STAYS. A packaged UWP application's visible window
#    belongs to ApplicationFrameHost.exe, so adding "the current application"
#    when one is in front would write the name of a HOST shared by Settings,
#    Photos, Calculator and the Store into a list meant to name one program.
#    The picker avoids this by filtering the host out of its history; this page
#    cannot, because the user is pointing at the window, so it refuses and says
#    why. Removing the refusal is how that decision gets quietly undone.
#
# 3. BOTH PRODUCTS OFFER THE PAGE AND HANDLE ITS ROWS. The table, the write and
#    the refusal are all shared; a tree that stops building the row or stops
#    dispatching "currentapp:" leaves working code with no way in.
function Assert-CurrentApplicationTargets {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    $blocked = Get-AhkFunctionBody `
        -Source $sharedText -Name "QuickMenuCurrentAppBlockedReason"
    Assert-True ($blocked -match '(?i)applicationframehost\.exe') (
        "QuickMenuCurrentAppBlockedReason no longer refuses " +
        "applicationframehost.exe. Every windowed Store app's visible window " +
        "belongs to that process, so Current Application would write one name " +
        "into an exe list that silently stands for all of them.")

    $table = Get-AhkFunctionBody -Source $sharedText -Name "QuickMenuAppTargets"
    $targets = @([regex]::Matches($table,
        '"product",\s*"(\w+)",\s*"section",\s*"(\w+)",\s*"key",\s*"(\w+)"'))
    Assert-True ($targets.Count -ge 4) (
        "Only $($targets.Count) Current Application destinations were read from " +
        "QuickMenuAppTargets, and there are at least four. The scan is not " +
        "seeing the table, which would make every check below it vacuous.")

    # Section/key pairs each product NAMES anywhere. String bodies are kept --
    # the names being looked for are themselves string literals.
    $namedBy = @{}
    foreach ($pair in @(
        @{ Product = "standalone"; Files = @("SteamShell.ahk", "SteamShell-Shared.ahk") },
        @{ Product = "xfe";        Files = @("SteamShell-XFE.ahk", "SteamShell-Shared.ahk") })) {
        $seen = @{}
        foreach ($file in $pair.Files) {
            foreach ($line in (Get-SourceLines (Join-Path $ProjectRoot $file))) {
                $code = $line -replace '(?<!`);.*$', ''
                foreach ($m in [regex]::Matches(
                    $code, '"([A-Za-z][\w &]*)"\s*,\s*"([A-Za-z]\w*)"')) {
                    $seen["$($m.Groups[1].Value).$($m.Groups[2].Value)"] = $true
                }
            }
        }
        $namedBy[$pair.Product] = $seen
    }

    foreach ($m in $targets) {
        $product = $m.Groups[1].Value
        $setting = "$($m.Groups[2].Value).$($m.Groups[3].Value)"
        foreach ($who in @("standalone", "xfe")) {
            if ($product -ne "both" -and $product -ne $who) { continue }
            Assert-True ($namedBy[$who].ContainsKey($setting)) (
                "Current Application offers '$setting' to $who, and $who never " +
                "reads it. The row would append the executable, report success, " +
                "and change nothing.")
        }
    }

    foreach ($pair in @(
        @{ Name = "SteamShell.ahk";     Product = "standalone" },
        @{ Name = "SteamShell-XFE.ahk"; Product = "xfe" })) {
        $code = (((Get-SourceLines (Join-Path $ProjectRoot $pair.Name)) |
            ForEach-Object { $_ -replace '(?<!`);.*$', '' }) -join "`n")
        Assert-True ($code -match '"currentApp"') (
            "$($pair.Name) never builds the Current Application row, so the " +
            "shared destination table has no way in on this product.")
        Assert-True ($code -match
            ('QuickMenuAddCurrentAppTo\([^)]*"' + $pair.Product + '"')) (
            "$($pair.Name) never dispatches currentapp: rows to " +
            "QuickMenuAddCurrentAppTo with its own product name. Its " +
            "destination rows would render and do nothing, or offer the other " +
            "product's list.")
        # "(already added)" is part of the LABEL, and labels are composed where
        # the rows are. A repaint after the write redraws the label the page was
        # built with, so a successful add looks like nothing happened.
        $dispatch = [regex]::Match($code,
            '(?s)QuickMenuAddCurrentAppTo\([^)]*\)(.{0,200})')
        Assert-True ($dispatch.Success -and
            $dispatch.Groups[1].Value -match 'QuickMenuBuildGui\(\)') (
            "$($pair.Name) does not rebuild the menu after adding the current " +
            "application. '(already added)' is part of the row label and " +
            "labels are composed in the row builder, so the row would keep " +
            "inviting the same add until the page was left and re-entered.")
    }
    if (-not $Quiet) {
        Write-Host ("Current Application: $($targets.Count) destinations, all " +
            "read by the product offered them, Store apps refused.")
    }
}

# Changing the Quick Menu's page must REBUILD it, not repaint it -- and neither
# tree is allowed to say so in its own words.
#
# The distinction is invisible in the source and total in use. QuickMenuRefresh
# (the shell) and QuickMenuRender (the companion) redraw the rows already in
# QuickMenuRows; the rows themselves come from the row builder, which only
# QuickMenuBuildGui calls -- the companion's renderer says so in its own comment,
# because it used to rebuild on every repaint and re-enumerated the desktop each
# time the D-pad moved.
#
# So `QuickMenuPage := "SOMEWHERE"` followed by a repaint changes which page the
# menu THINKS it is on while leaving the previous page's rows on screen. The
# symptom is "selecting the row does nothing", and the state is worse than that:
# the next keypress is read against a page the user cannot see.
#
# This shipped, in four shell cases -- Game Detection, Current Application, and
# the two Back To System rows -- while the companion had the identical four-line
# shape correct, so there was nothing in a diff to notice.
#
# THE CHECK IS THEREFORE NOT "did you follow the assignment with the right
# call". That rule can be obeyed in eleven places and broken in the twelfth. The
# rule is that the assignment happens in ONE place: QuickMenuGoToPage, in
# SteamShell-Shared.ahk, which both products call. A tree that assigns
# QuickMenuPage at all has re-created the shape this bug lived in, whatever it
# does on the next line.
function Assert-QuickMenuPageChangesRebuild {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedPath = Join-Path $ProjectRoot "SteamShell-Shared.ahk"
    $navigator = Get-AhkFunctionBody -Source (Get-SourceText $sharedPath) `
        -Name "QuickMenuGoToPage"
    Assert-True ($navigator -ne "" -and $navigator -match 'QuickMenuPage\s*:=' -and
        $navigator -match 'QuickMenuBuildGui\(\)') (
        "QuickMenuGoToPage in SteamShell-Shared.ahk no longer sets the page and " +
        "rebuilds. It is the only navigator both products have; without it each " +
        "tree is back to spelling the shape by hand, which is how four of them " +
        "came to repaint instead.")
    Assert-True ($navigator -notmatch 'QuickMenuRefresh\(\)|QuickMenuRender\(\)') (
        "QuickMenuGoToPage repaints. A repaint redraws the rows the page was " +
        "built with, so every page change in both products would leave the " +
        "previous page on screen.")

    $callers = 0
    foreach ($file in @("SteamShell.ahk", "SteamShell-XFE.ahk")) {
        # Comments stripped. The paragraph above spells the forbidden assignment
        # in full, and a comment quoting it would otherwise fail the build.
        $lines = @((Get-SourceLines (Join-Path $ProjectRoot $file)) |
            ForEach-Object { $_ -replace '(?<!`);.*$', '' })
        for ($i = 0; $i -lt $lines.Count; $i++) {
            # The one-time declaration is the variable coming into existence, not
            # a navigation. Every other assignment is one.
            if ($lines[$i] -match '^\s*global\s+QuickMenuPage\b') { continue }
            $callers += ([regex]::Matches($lines[$i], 'QuickMenuGoToPage\(')).Count
            Assert-True ($lines[$i] -notmatch '(?<!\w)QuickMenuPage\s*:=') (
                "${file}:$($i + 1) assigns QuickMenuPage. Navigation belongs to " +
                "QuickMenuGoToPage in SteamShell-Shared.ahk, which sets the page " +
                "and rebuilds; a tree that sets it directly can pair it with a " +
                "repaint, which leaves the previous page's rows on screen and " +
                "selectable while the menu believes it has moved.")
        }
    }
    Assert-True ($callers -ge 8) (
        "Only $callers calls to QuickMenuGoToPage were found across both trees, " +
        "and there are at least eight. Either the scan is not seeing them -- " +
        "which makes the rule above vacuous -- or navigation has moved somewhere " +
        "this check is not looking.")
    if (-not $Quiet) {
        Write-Host ("Quick Menu navigation: one shared navigator, $callers calls " +
            "across 2 products, and no page assignment in either tree.")
    }
}

# A setting both products read identically is read in one place.
#
# LoadSharedSettings holds the twenty-seven keys whose global name, reader,
# default and clamp range are the same in both trees. A tree that reads one of
# them again would not fail anything: the value would simply be assigned twice,
# and whichever ran last would win. That is drift with no symptom until the two
# defaults disagree, which is precisely what this removed.
#
# Checked as "no tree reads these keys itself", not as "the function exists",
# because the second is satisfied by a function nobody calls.
function Assert-SharedSettingsReadOnce {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    $body = Get-AhkFunctionBody -Source $sharedText -Name "LoadSharedSettings"
    Assert-True ($body -ne "") (
        "LoadSharedSettings is gone; the settings both products read the same " +
        "way are back to being read twice.")
    $keys = @([regex]::Matches($body,
        '(\w+)\s*:=\s*Read(?:Bool|Int|Text|Number)\(') |
        ForEach-Object { $_.Groups[1].Value })
    Assert-True ($keys.Count -ge 20) (
        "Only $($keys.Count) shared settings reads were found in " +
        "LoadSharedSettings, and there are twenty-seven. The scan is not " +
        "seeing them, which makes the rule below vacuous.")
    foreach ($pair in @(
        @{ File = "SteamShell.ahk"; Product = "the shell" },
        @{ File = "SteamShell-XFE.ahk"; Product = "the companion" })) {
        $text = Get-SourceText (Join-Path $ProjectRoot $pair.File)
        $load = Get-AhkFunctionBody -Source $text -Name "LoadSettings"
        Assert-True ($load -match 'LoadSharedSettings\(\)') (
            "$($pair.File): LoadSettings does not call LoadSharedSettings, so " +
            "every shared key is left at its startup default in $($pair.Product).")
        foreach ($name in $keys) {
            Assert-True ($load -notmatch
                ('(?m)^\s*' + [regex]::Escape($name) + '\s*:=\s*Read')) (
                "$($pair.File): LoadSettings reads '$name' itself, and " +
                "LoadSharedSettings already does. Two reads of one key differ " +
                "only when somebody edits one of them, which is the drift this " +
                "consolidation removed.")
        }
    }
    if (-not $Quiet) {
        Write-Host ("Shared settings: $($keys.Count) keys read once, in " +
            "LoadSharedSettings, and by neither tree directly.")
    }
}


# No function may be truncated by a closing brace at column zero.
#
# Assertions all over this project bound themselves to a function with
# `(?ms)^Name\(\)\s*\{.*?^\}\s*$`, and that pattern ends at the FIRST `}` in
# column zero. A `}` written at column zero inside a function therefore ends the
# match early, and every check anchored to that function silently reads a prefix
# of it and reports on the rest by not looking.
#
# This was not hypothetical. PollController in SteamShell.ahk had forty lines
# written at column zero, so every range-bounded read of the shell's input loop
# saw about nine tenths of it. A rename driven by that extraction stopped at the
# truncation point and left two by-ref arguments pointing at statics that had
# just been renamed -- an uninitialised reference in the input path of a Windows
# shell replacement, invisible to every structural check because the structure
# is exactly what was being hidden.
#
# Assert-NoAmbiguousDeindentedBlocks does not cover this. It asks whether a
# BRACELESS body is ambiguous; these blocks all had braces, and were unambiguous
# to a reader and to AutoHotkey. Only the regexes were fooled.
function Assert-NoTruncatingBraces {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $checked = 0
    foreach ($file in @("SteamShell.ahk", "SteamShell-XFE.ahk",
                        "SteamShell-Shared.ahk", "SteamShell-Common.ahk",
                        "SteamShell-Helper.ahk")) {
        $path = Join-Path $ProjectRoot $file
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $lines = @(Get-SourceLines $path)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -notmatch '^[A-Za-z_]\w*\([^)]*\)\s*\{') { continue }
            $checked++
            $depth = 0
            for ($j = $i; $j -lt $lines.Count; $j++) {
                # Strings before comments: a `;` inside a literal is not a
                # comment, and a brace inside one is not a brace.
                $code = $lines[$j] -replace '"(?:[^"]|"")*"', '""'
                $code = $code -replace '(?<!`);.*$', ''
                $depth += ([regex]::Matches($code, '\{')).Count
                $depth -= ([regex]::Matches($code, '\}')).Count
                if ($j -gt $i -and $depth -eq 0) { break }
                if ($j -gt $i -and $lines[$j] -match '^\}') {
                    Assert-True $false (
                        "${file}:$($j + 1) closes a block at column zero inside " +
                        "a function that is still open. Every assertion bounded " +
                        "with '^Name(...) {.*?^}' stops here instead of at the " +
                        "end of the function, so the rest of it is checked by " +
                        "nobody. Indent it to its real depth.")
                }
            }
            $i = $j
        }
    }
    Assert-True ($checked -ge 900) (
        "Only $checked function bodies were scanned for truncating braces, and " +
        "there are over nine hundred. The scan is not finding them, which makes " +
        "this check vacuous.")
    if (-not $Quiet) {
        Write-Host ("Function extents: $checked bodies, none truncated by a " +
            "brace at column zero.")
    }
}


# Every input backend must reach the elevated helper, not just XInput.
#
# The helper drives the pointer while a High-integrity window owns the
# foreground. Its only input source was XInputGetState, so a pad that answers
# only RawInput -- which is what the RawInput backend and the whole learning
# wizard exist for -- lost the pointer the instant Task Manager came forward,
# while working everywhere else. From a user's side that is one input mode being
# second-class; it was never a decision anyone made for this product, only the
# XFE reasoning ("the remedy here is XInput") inherited by a product it was not
# written about.
#
# The decode therefore lives in SteamShell-Common.ahk, which all three programs
# compile. That placement is the rule worth holding: moved back into
# SteamShell-Shared.ahk it would compile into the two trees and silently vanish
# from the helper again, and nothing about that reads as a regression.
#
# Four things, and the last two are the ones a reimplementation gets wrong --
# main's handler carries both rules with their reasons, and a helper that
# disagreed with either would be a second opinion rather than the same decoder.
function Assert-ElevatedHelperReadsEveryBackend {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $commonText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Common.ahk")
    $helperText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Helper.ahk")
    foreach ($name in @("RawInputProfileDecodeInto", "LoadControllerProfileFrom",
                        "RawInputDeviceKey", "ControllerProfilePathFor",
                        "ControllerProfileLengthKey")) {
        Assert-True ($commonText -match ('(?m)^' + $name + '\(')) (
            "$name is not in SteamShell-Common.ahk. The elevated helper only " +
            "compiles Common, so moving it out takes RawInput away from the " +
            "one process that needs it to read a learned pad over an elevated " +
            "window -- and nothing about that change looks like a regression.")
    }
    Assert-True ($helperText -match 'RegisterRawInputDevices') (
        "The elevated helper no longer registers for RawInput, so a pad that " +
        "XInput does not expose has no pointer over an elevated window.")
    Assert-True ($helperText -match 'RIDEV_INPUTSINK') (
        "The elevated helper's RawInput registration is not INPUTSINK. It " +
        "reads the pad precisely when another window owns the foreground, " +
        "which is the only thing INPUTSINK provides.")

    $handler = Get-AhkFunctionBody -Source $helperText -Name "HelperRawInputMessage"
    Assert-True ($handler -ne "") (
        "HelperRawInputMessage is gone; nothing decodes RawInput in the helper.")
    Assert-True ($handler -match 'ControllerProfileLengthKey\(') (
        "The helper no longer falls back to a length-keyed profile. A device " +
        "whose identity Windows withholds saves its profile under that key, so " +
        "it would work in main and not over an elevated window -- the exact " +
        "asymmetry this exists to remove.")
    Assert-True ($handler -match '\(size - \(HEADER_SIZE \+ 8\)\) // sizeHid') (
        "The helper trusts the packet header for its report count. count and " +
        "sizeHid come out of the packet and are used to index straight into " +
        "memory; in a High-integrity process that bound is not optional.")
    Assert-True ($handler -match '(?s)Loop\s+Min\(count,\s*Max\(0,\s*available\)\)') (
        "The helper decodes fewer than all the reports in a packet. Windows " +
        "coalesces them under load, and on a change-only pad -- which is most " +
        "of the pads needing a learned profile -- a coalesced press is not a " +
        "late press, it is a press that never arrives.")

    $read = Get-AhkFunctionBody -Source $helperText -Name "HelperRawInputRead"
    Assert-True ($read -match 'STALE_MS') (
        "The helper's RawInput state has no staleness rule. RawInput is " +
        "event-driven, so an untouched pad stops reporting and the last stick " +
        "position would drive the cursor forever over an elevated window.")
    $poll = Get-AhkFunctionBody -Source $helperText -Name "PollController"
    Assert-True ($poll -match 'HelperRawInputRead\(&state\)[\s\S]{0,80}GetXInputState\(&state\)') (
        "PollController no longer tries RawInput before XInput, or has lost " +
        "the XInput fallback. Both matter: RawInput only answers for a pad " +
        "with a learned profile, and XInput is what every other pad uses.")
    if (-not $Quiet) {
        Write-Host ("Elevated helper input: RawInput and XInput, one shared " +
            "decoder, every report in a packet.")
    }
}


# The startup limiter hold must stay bounded, and must never defend "off".
#
# RTSS applies its own saved runtime state while it finishes starting, which
# overwrites the limiter flag the startup restore had already set AND already
# verified -- the read-back happens while the value is still ours. So the restore
# re-checks after RTSS settles and re-applies if it reverted.
#
# That is a program writing a setting the user did not just ask it to write, and
# the only thing keeping it honest is that it stops. Two bounds and one
# exclusion, all three of which a tidy could remove without any test noticing:
#
#   - a deadline, so it cannot run for the session
#   - a retry cap, so it cannot fight in a loop inside the deadline
#   - never for mode "off", because re-applying THAT means writing the disabled
#     bit over a user who has just turned the limiter on in RTSS's own UI
function Assert-RtssFrameLimitHoldIsBounded {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    $hold = Get-AhkFunctionBody -Source $sharedText -Name "RtssFrameLimitHoldTick"
    Assert-True ($hold -ne "") (
        "RtssFrameLimitHoldTick is gone. Without it the startup restore is " +
        "confirmed by a read-back that happens before RTSS has finished " +
        "applying its own state, so a reverted limiter is never noticed.")
    Assert-True ($hold -match 'RtssLastFrameCapMode\s*=\s*"off"') (
        "The RTSS limiter hold no longer excludes the 'off' selection. It " +
        "would write the disabled bit back over a user who has just turned the " +
        "limiter on in RTSS itself.")
    Assert-True ($hold -match 'A_TickCount\s*>\s*RtssFrameLimitHoldUntil') (
        "The RTSS limiter hold has no deadline and would run for the session.")
    Assert-True ($hold -match 'RtssFrameLimitHoldRetries\s*>=\s*MAX_RETRIES') (
        "The RTSS limiter hold has no retry cap. Inside its deadline it could " +
        "re-enable the limiter every tick against a user turning it off.")
    Assert-True ($hold -match 'fps\s*!=\s*RtssLastFrameCapFps') (
        "The RTSS limiter hold no longer checks the cap it is defending. If " +
        "RTSS came back holding a different number this would enable the " +
        "limiter at an FPS the user never chose.")
    $arm = Get-AhkFunctionBody -Source $sharedText -Name "ArmRtssFrameLimitHold"
    Assert-True ($arm -ne "" -and $arm -match 'RtssFrameLimitHoldRetries\s*:=\s*0') (
        "ArmRtssFrameLimitHold is missing or does not reset the retry count, " +
        "so a later restore in the same session would start already exhausted.")
    if (-not $Quiet) {
        Write-Host ("RTSS limiter hold: bounded by deadline and retries, and " +
            "never applied to an 'off' selection.")
    }
}


# "Could not read the cap" must never render as "the limiter is off".
#
# GetRtssFrameLimit returns 0 for six different reasons and only one of them is
# "uncapped": integration disabled, DLL integration disabled, RTSS not running,
# the API unavailable, GetProfileProperty returning false, or an exception. That
# was harmless until GetRtssFrameCapState read the 0 as a STATE -- it reports
# mode "off" when fps <= 0 -- so a failed profile read displayed "OFF" on the
# Quick Menu row while GetFlags, in the same pass, was reporting the limiter ON.
#
# Reported as intermittent and boot-clustered, which is exactly the shape: RTSS's
# shared memory answers as soon as the process is alive, while its profile store
# can fail to answer for a moment longer during startup. The two data sources
# come up at different times and the row believed the one that had not.
#
# The same 0 also reached PersistRtssFrameCapStateNow, which records the live
# state as the user's remembered selection -- so a failed read could persist
# "off" and there would be nothing left to restore on the next boot. That is the
# "does SteamShell turn it off?" report, and it is a write, not a toggle.
#
# Three rules, none of which a diff makes obvious:
#   1. The distinguishing read exists and returns a success flag.
#   2. GetRtssFrameCapState uses it and returns unavailable, not "off".
#   3. A failed read is not cached, or the wrong answer outlives the fault.
function Assert-RtssUnreadableIsNotOff {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    $read = Get-AhkFunctionBody -Source $sharedText -Name "RtssGlobalFrameLimitRead"
    Assert-True ($read -ne "") (
        "RtssGlobalFrameLimitRead is gone. It is the only thing that tells a " +
        "failed RTSS profile read apart from a genuine zero, and without it the " +
        "Quick Menu reports the limiter off whenever the read fails.")
    Assert-True ($read -match 'return\s+false') (
        "RtssGlobalFrameLimitRead no longer reports failure to its caller.")
    # The failure path must return before the cache is written. Anchored on the
    # order of the two, because caching a failure holds the wrong reading for
    # the full cache window past the moment RTSS became readable.
    Assert-True ($read -match
        '(?s)if\s*!IsObject\(limit\)\s*\{[^}]*return\s+false[^}]*\}(?:(?!\n\})[\s\S])*?RtssFrameLimitCacheTick\s*:=') (
        "RtssGlobalFrameLimitRead caches the result before it has established " +
        "the read succeeded. A cached failure keeps reporting 'off' for the " +
        "whole cache window after RTSS became readable.")

    $state = Get-AhkFunctionBody -Source $sharedText -Name "GetRtssFrameCapState"
    Assert-True ($state -match 'if\s*!RtssGlobalFrameLimitRead\(&fps\)') (
        "GetRtssFrameCapState no longer distinguishes an unreadable cap from " +
        "zero. It reports mode 'off' when fps <= 0, so an unreadable cap would " +
        "again display as a limiter that is off -- and would be persisted as " +
        "the user's selection by PersistRtssFrameCapStateNow.")
    Assert-True ($state -notmatch 'fps\s*:=\s*RtssGlobalFrameLimit\(\)') (
        "GetRtssFrameCapState reads the cap through the number-only helper " +
        "again, which cannot report a failed read.")

    # The two profile writes must refuse a failed read rather than write 0 over
    # the profile the user is populating.
    $save = Get-AhkFunctionBody -Source $sharedText -Name "SaveRtssFrameLimitToProfile"
    if ($save -ne "") {
        Assert-True (([regex]::Matches($save,
            'if\s*!RtssGlobalFrameLimitRead\(&fps\)')).Count -ge 2) (
            "Save Limit to Profile no longer refuses an unreadable cap on both " +
            "its paths. A failed read is 0, so it would write 'uncapped' over " +
            "the game profile it was asked to populate and report success.")
    }
    if (-not $Quiet) {
        Write-Host ("RTSS frame cap: an unreadable cap reports unavailable, " +
            "is never cached, and is never written to a profile.")
    }
}


# The learner must not measure rest while the identifying button is still down.
#
# The wizard picks the device from the first report where a bit changed, and for
# almost every pad that is the button going DOWN. Two things then have to be true
# and neither is visible in a diff:
#
# 1. The resting baseline is the PRE-PRESS idle report, which the identification
#    loop already keeps in order to measure idle noise. Copying the report that
#    completed identification instead makes "that button held" the resting state:
#    it reads as permanently pressed for the rest of the wizard, is saved into
#    the profile's neutral, and the controller comes out of the wizard with a
#    button stuck down. That is what shipped in 2.0.0 and what a user reported.
#
# 2. Nothing is measured until the control comes back up. Without the gate the
#    rest window opens while the user is mid-press -- the prompt changes from
#    "press a button" to "hands off" underneath their thumb -- and either the
#    press lands in the baseline (stuck button) or the release lands in
#    LearnRestNoise, where that bit is skipped by every later step, silently.
#
# The step captures have always had this rule; see LearnReleaseOffset, "a held
# button cannot answer the next prompt". Identification is the one prompt whose
# answer the user is still holding when the next prompt appears, and it was the
# one place the rule was missing.
#
# Checked against SteamShell-Shared.ahk, because both products compile it and
# neither can fix or break this on its own. KEPT IN STEP WITH
# test_identifying_press_never_becomes_the_resting_state in
# Test-ControllerProfiles.py, which models the same sequence report by report.
# Both Settings windows are PLACED the same way.
#
# They were not, and the difference was visible from the couch: standalone's
# opened in the top-left corner while the companion's centred, on the same
# machine and the same display. Standalone asked Gui.Show for a SIZE and no
# position -- so Windows chose one, and its choice is the top-left cascade --
# then corrected with a single WinGetPos and WinMove. The companion sized and
# positioned in one shared call and then re-measured the window once it was
# VISIBLE, correcting it in physical pixels through SetWindowPos.
#
# RecenterVisibleGuiOnMonitorActual is that correction, and its own comment
# described the symptom before anybody went looking: a hidden GUI's measurements
# can omit the scaled non-client frame and title bar, so a position computed
# from them is an estimate. Every other link in the chain was already shared. It
# was the one piece that was not, so only one product had it.
#
# The re-open path is checked too. Standalone's positioned nothing at all on a
# second open, which is fine right up until the first open put the window
# somewhere wrong.
function Assert-SettingsWindowPlacement {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    Assert-True (
        (Get-AhkFunctionBody -Source $sharedText `
            -Name "RecenterVisibleGuiOnMonitorActual") -ne "") (
        "RecenterVisibleGuiOnMonitorActual is not in SteamShell-Shared.ahk. It " +
        "corrects a window's position from its REAL outer rectangle once it is " +
        "visible, and while it lived in one tree only that product's Settings " +
        "window centred.")

    foreach ($pair in @(
        @{ File = "SteamShell.ahk";     Name = "ShowSettingsEditor" },
        @{ File = "SteamShell-XFE.ahk"; Name = "ShowSettings" })) {
        $text = Get-SourceText (Join-Path $ProjectRoot $pair.File)
        $body = Get-AhkFunctionBody -Source $text -Name $pair.Name
        Assert-True ($body -ne "") (
            "$($pair.File): $($pair.Name) could not be read, so the Settings " +
            "window's placement is not checked.")
        Assert-True ($body -match 'CenterGuiOnMonitorActual\(') (
            "$($pair.File): the Settings window is not sized and positioned " +
            "through CenterGuiOnMonitorActual. Asking Gui.Show for a size and " +
            "no position lets Windows choose, and it chooses the top-left.")
        Assert-True ($body -match 'RecenterVisibleGuiOnMonitorActual\(') (
            "$($pair.File): the Settings window is never re-measured once " +
            "visible, so its position rests on an estimate taken while it was " +
            "hidden.")
        # SHOWN IS NOT IN FRONT. Windows refuses a foreground change from a
        # process that does not already own the foreground, and something else
        # can re-assert itself in the moment after ours appears. Standalone had
        # no retry and its Settings window opened behind whatever was there,
        # from all three entry points, needing a mouse click to reach.
        # ONE WINDOW, BUILT FROM ONE PLACE. The frame -- how tall it may be, the
        # header, the category list, the page heading, the divider, the status
        # line, the footer buttons and the scrollbar -- is shared, and the
        # companion adopted the shell's. Without this a product can quietly go
        # back to building its own and the two drift again, which is exactly how
        # they came to differ in six visible ways.
        foreach ($builder in @(
            "SettingsWindowGeometry", "SettingsBuildWindowChrome",
            "SettingsBuildWindowFooter")) {
            Assert-True ($body -match ($builder + '\(')) (
                "$($pair.File): the Settings window does not build its frame " +
                "through $builder. Both products draw the same window from the " +
                "same code; a hand-built frame is how they drifted apart.")
        }
        Assert-True ($body -match 'GuiForegroundRetry\(') (
            "$($pair.File): the Settings window is shown but never made the " +
            "foreground. A single activation request is one Windows is " +
            "entitled to refuse, so the window opens behind whatever is there.")
    }
    # AND EVERY WINDOW SETTINGS OPENS IS PLACED THE SAME WAY.
    #
    # They are all +AlwaysOnTop, as Settings is, so they stack above it once
    # activated -- that part was never in doubt. Placement was: the controller
    # mapping editor used Gui's own "Center", which centres on the PRIMARY
    # monitor rather than the one Settings is on, and the AlwaysFocus manager
    # placed itself not at all. Both are reachable from a Settings button.
    #
    # Gui "Center" is banned outright rather than fixed case by case. It is the
    # wrong answer on any multi-monitor machine and it is indistinguishable from
    # the right one on a single-display test bench, which is how it survived.
    foreach ($file in @("SteamShell.ahk", "SteamShell-XFE.ahk", "SteamShell-Shared.ahk")) {
        $text = Get-SourceText (Join-Path $ProjectRoot $file)
        $code = (($text -split "`n") | Where-Object { $_ -notmatch '^\s*;' }) -join "`n"
        # BOUNDED BY THE CALL, not by the first string literal. The first version of
        # this read .Show(" followed by Center inside that one literal, and
        # missed .Show("w" w " h" h " Center") -- a live instance, in the
        # Control Panel, sitting behind the ban that was supposed to catch it.
        Assert-True ($code -notmatch '\.Show\([^)]*\bCenter\b') (
            "$file places a window with Gui's own Center option, which centres " +
            "on the primary monitor rather than the one the window was opened " +
            "from. Use the shared placement helpers.")
    }

    if (-not $Quiet) {
        Write-Host "Settings window: both products size, centre and re-measure the same way."
    }
}

# Every Product* name SteamShell-Shared.ahk reaches must exist in BOTH trees.
#
# The leak scan above asks whether a name the shared file reaches is on the seam
# allowlist, but it only considers names that are DEFINED somewhere in a tree --
# a name defined nowhere is filtered out before it is judged. So a seam that was
# invented and never written slipped through every static check and surfaced as
# an AutoHotkey load-time warning on the build machine:
#
#     Warning: This local variable appears to never be assigned a value.
#     Specifically: ProductSettingsHintLine
#
# AutoHotkey reads an undefined function call as an unassigned variable, which is
# why it presents as a variable warning rather than a missing function. It cost a
# build, and the rule that would have caught it is one line of convention this
# project already follows: Product* is the seam prefix, and a seam has two sides.
function Assert-SharedSeamsExistInBothTrees {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    $sharedCode = (($sharedText -split "`n") |
        Where-Object { $_ -notmatch '^\s*;' }) -join "`n"
    $shell = Get-SourceText (Join-Path $ProjectRoot "SteamShell.ahk")
    $companion = Get-SourceText (Join-Path $ProjectRoot "SteamShell-XFE.ahk")
    $names = @([regex]::Matches($sharedCode, '\b(Product[A-Za-z0-9_]*)\s*[\(.]') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $orphans = @()
    foreach ($name in $names) {
        $pattern = '(?m)^' + [regex]::Escape($name) + '\('
        $inShell = $shell -match $pattern
        $inCompanion = $companion -match $pattern
        if (-not ($inShell -and $inCompanion)) {
            $where = if ($inShell) { "the shell only" }
                elseif ($inCompanion) { "the companion only" }
                else { "NEITHER tree" }
            $orphans += "$name (defined in $where)"
        }
    }
    Assert-True ($orphans.Count -eq 0) (
        "SteamShell-Shared.ahk reaches seam names that are not defined in both " +
        "trees: " + ($orphans -join ", ") + ". A seam has two sides; one that " +
        "exists nowhere is an AutoHotkey load-time warning on the build machine " +
        "and nothing here.")
    if (-not $Quiet) {
        Write-Host ("Shared seams: " + $names.Count +
            " Product* names, every one answered by both trees.")
    }
}

# A SETTING A PRODUCT READS MUST BE REACHABLE IN THAT PRODUCT'S SETTINGS.
#
# Reported as "why does standalone's Advanced & Logging have way more things
# than the companion's". Ten rows against three, and the answer was worth
# having: three of the extras are genuinely shell-only -- zero mentions of
# GameAssistLogEvenWhenSkipped, SteamStartupGraceMs or SteamExitConfirmMs
# anywhere in the companion -- but FIVE were settings the companion reads in its
# own LoadSettings, writes into its own INI defaults, and could not reach from
# its own Settings window: GameLogMode, GameLogTopN, GameLogIntervalMs,
# GameLogIncludeTitles and RawInputStaleMs. The companion even normalises
# GameLogMode through the same NormalizeGameLogMode and feeds the shared
# LogGameCandidateTable with the result.
#
# This project already has the sentence, written about the Steam page: "A
# setting that can only be changed by hand-editing the INI is not a setting most
# users have." This is the general form of it, checked rather than remembered.
#
# The test is deliberately narrow: a row marked for ONE product, whose key the
# OTHER product reads through its own INI readers. That is a settings row with
# the wrong product on it, which is a different thing from a key one product
# merely mentions in a migration table or a comment.
function Assert-SettingsRowsReachTheirReaders {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    $trees = @{
        "standalone" = Get-SourceText (Join-Path $ProjectRoot "SteamShell-XFE.ahk")
        "xfe"        = Get-SourceText (Join-Path $ProjectRoot "SteamShell.ahk")
    }
    $names = @{ "standalone" = "the companion"; "xfe" = "the shell" }
    # WHICH PRODUCTS CAN REACH EACH KEY. A key may carry TWO rows, one per
    # product, with different sections, labels and defaults -- CooldownSec,
    # HardKill and EnableViewButtonActions all do, deliberately. The first
    # version of this compared keys alone and reported all three as unreachable
    # when both products reach them perfectly well.
    $rows = @()
    $reachable = @{}
    foreach ($m in [regex]::Matches($sharedText,
            '(?s)Map\("product", "(both|standalone|xfe)"(.{0,400}?)"key", "(\w+)"')) {
        $product = $m.Groups[1].Value
        $key = $m.Groups[3].Value
        $rows += [pscustomobject]@{ Product = $product; Key = $key }
        $targets = if ($product -eq "both") { @("standalone", "xfe") } else { @($product) }
        foreach ($t in $targets) {
            if (-not $reachable.ContainsKey($key)) { $reachable[$key] = @{} }
            $reachable[$key][$t] = $true
        }
    }
    $unreachable = @()
    foreach ($row in $rows) {
        if ($row.Product -eq "both") { continue }
        $missing = if ($row.Product -eq "standalone") { "xfe" } else { "standalone" }
        if ($reachable[$row.Key].ContainsKey($missing)) { continue }
        if ($trees[$row.Product] -match
                ('Read(?:Text|Int|Bool|Number)\([^)]*"' + [regex]::Escape($row.Key) + '"')) {
            $unreachable += "$($row.Key) (row is $($row.Product)-only, but $($names[$row.Product]) reads it)"
        }
    }
    Assert-True ($unreachable.Count -eq 0) (
        "Settings rows are marked for one product while the other reads the " +
        "same key and has no row of its own: " +
        (($unreachable | Sort-Object -Unique) -join ", ") + ". A setting that " +
        "can only be changed by hand-editing the INI is not a setting most " +
        "users have -- mark the row `"both`", give the other product its own " +
        "row, or stop reading the key.")
    if (-not $Quiet) {
        Write-Host "Settings rows: every key a product reads is reachable in that product's Settings."
    }
}

# The Live Log window is shared, and its status lines are not.
#
# It was the shell's alone, and PRODUCT_SURFACES.txt recorded why in the only
# honest way available: portability "has not been asked. Recorded so that it
# gets asked rather than assumed." It was asked. The answer was yes, and the
# entry is gone because the surface is no longer one-sided.
#
# The SPLIT is the part worth pinning, because collapsing it is the tempting
# tidy. The viewer is about a log file and both products want the same one. The
# status block is not: four of the shell's eight lines name Hands-Off, the
# AlwaysFocus list and the window engine, none of which exist in the companion,
# while Launcher Cleanup exists in both. A future pass that hard-codes eight
# lines into the shared window, or that pushes the shell's set into the
# companion, puts back the thing that kept this window in one product.
#
# Each product must ANSWER the seam and REACH the window: a shared viewer nobody
# can open is worse than no viewer, and that is the state the companion was in.
function Assert-LiveLogShared {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    foreach ($name in @("ShowLiveLogWindow", "HideLiveLogWindow", "LiveLogRefresh")) {
        Assert-True ((Get-AhkFunctionBody -Source $sharedText -Name $name) -ne "") (
            "SteamShell-Shared.ahk defines no $name(); the Live Log window is " +
            "no longer shared and this check cannot see what replaced it.")
    }
    $show = Get-AhkFunctionBody -Source $sharedText -Name "ShowLiveLogWindow"
    $refresh = Get-AhkFunctionBody -Source $sharedText -Name "LiveLogRefresh"
    Assert-True ($show -match 'ProductLiveLogStatusLines\(\)') (
        "The shared Live Log window does not build its status lines from the " +
        "seam, so one product's set is hard-coded into both.")
    Assert-True ($refresh -match 'ProductLiveLogStatusLines\(\)') (
        "The shared Live Log window never refreshes its status lines from the " +
        "seam, so they show whatever they held when it was built.")
    # Its own timer, so it needs no seam for the host's -- the shell has two and
    # the companion has neither.
    Assert-True ($show -match 'SetTimer\(LiveLogRefresh,' -and
        (Get-AhkFunctionBody -Source $sharedText -Name "HideLiveLogWindow") -match
            'SetTimer\(LiveLogRefresh, 0\)') (
        "The Live Log window must arm and cancel its own refresh timer; " +
        "borrowing the host's needs a seam neither product should have to grow.")

    foreach ($pair in @(
        @{ File = "SteamShell.ahk";     Product = "the shell" },
        @{ File = "SteamShell-XFE.ahk"; Product = "the companion" })) {
        $text = Get-SourceText (Join-Path $ProjectRoot $pair.File)
        Assert-True (
            (Get-AhkFunctionBody -Source $text -Name "ProductLiveLogStatusLines") -ne "") (
            "$($pair.File) does not answer ProductLiveLogStatusLines, so the " +
            "shared Live Log window has no lines to show in $($pair.Product).")
        $code = (($text -split "`n") | Where-Object { $_ -notmatch '^\s*;' }) -join "`n"
        Assert-True ($code -match 'ShowLiveLogWindow') (
            "$($pair.File) offers no way to open the Live Log window. A shared " +
            "viewer nobody can reach is worse than none, and that is exactly " +
            "the state the companion was in.")
    }
    if (-not $Quiet) {
        Write-Host "Live log: one shared viewer, each product naming its own status lines."
    }
}

# The layout audit's own bounds must come from the layout.
#
# The companion's said 286 -- its content column before the pages adopted the
# shared row builders and started placing themselves at contentX, 255. Every
# scrollable control on every page was then 31 pixels outside the boundary, so
# the audit reported 86 crossings on a window with nothing wrong with it. An
# audit that cries wolf 86 times is one nobody reads, which is worse than not
# having it: the shell's copy carries a comment warning about exactly this trap,
# written when its RIGHT edge was a literal, while its left edge stayed one.
#
# Both edges of both products are derived now. A literal here is always a number
# that is right today.
function Assert-SettingsAuditBoundsDerived {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    foreach ($pair in @(
        @{ File = "SteamShell.ahk";     Name = "SettingsEditorAuditLayout" },
        @{ File = "SteamShell-XFE.ahk"; Name = "SettingsAuditLayout" })) {
        $text = Get-SourceText (Join-Path $ProjectRoot $pair.File)
        $body = Get-AhkFunctionBody -Source $text -Name $pair.Name
        Assert-True ($body -ne "") (
            "$($pair.File): $($pair.Name) could not be read, so the layout " +
            "audit's bounds are not checked.")
        Assert-True ($body -match 'SharedAuditSettingsLayout\((?s).*?layout\["contentX"\]\s*-\s*10') (
            "$($pair.File): the layout audit's LEFT bound is not derived from " +
            "the layout. A literal is a number that is right today: the " +
            "companion's said 286 after its column moved to 255, and every " +
            "control on every page was reported as crossing the boundary.")
        Assert-True ($body -notmatch 'SharedAuditSettingsLayout\((?s).*?,\s*\d{3}\s*,') (
            "$($pair.File): the layout audit is passed a hard-coded bound.")
    }
    if (-not $Quiet) {
        Write-Host "Settings layout audit: both products derive their bounds from the layout."
    }
}

function Assert-ControllerLearnerIdentifyRelease {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    $report = Get-AhkFunctionBody -Source $sharedText -Name "ControllerLearnReport"
    Assert-True ($report -ne "") (
        "ControllerLearnReport could not be read, so nothing below it is checked.")

    # THE RULE NOW SPANS TWO FUNCTIONS, so the check follows it rather than
    # staying pinned to the body it was written against.
    #
    # ControllerLearnAdoptDevice was extracted when the stale-hold deferral gave
    # identification a second arrival path, and it took the baseline copy and the
    # hold record with it. Bounding this to ControllerLearnReport alone would
    # have failed a correct refactor -- and, worse, a later edit that put the
    # copy back inside ControllerLearnReport reading `data` would have satisfied
    # the old -match while reintroducing the exact bug it exists to prevent.
    #
    # So: the CALLER passes the pre-press idle report, the CALLEE copies its
    # parameter, and neither may copy the live one.
    $adopt = Get-AhkFunctionBody -Source $sharedText -Name "ControllerLearnAdoptDevice"
    Assert-True ($adopt -ne "") (
        "ControllerLearnAdoptDevice could not be read; the learner's baseline " +
        "rule is checked across it and ControllerLearnReport.")
    Assert-True ($report -match 'ControllerLearnAdoptDevice\((?s).*?baseline,') (
        "ControllerLearnReport no longer hands the pre-press idle report to " +
        "ControllerLearnAdoptDevice. Identification fires on the button going " +
        "DOWN, so any other report saves that button as the resting state: it " +
        "reads as held for the rest of the wizard and stays held in the saved " +
        "profile.")
    Assert-True ($adopt -match 'LearnBaseline\s*:=\s*ControllerLearnCopyReport\(\s*idleReport\s*,') (
        "ControllerLearnAdoptDevice no longer takes its resting baseline from " +
        "the idle report its caller passed.")
    Assert-True (
        $report -notmatch 'LearnBaseline\s*:=\s*ControllerLearnCopyReport\(\s*data\s*,' -and
        $adopt -notmatch 'LearnBaseline\s*:=\s*ControllerLearnCopyReport\(\s*data\s*,') (
        "The learner copies the live report into LearnBaseline at " +
        "identification. That report is the identifying PRESS, which is exactly " +
        "the state that must not become rest.")
    Assert-True ($adopt -match 'LearnIdentifyHoldOffset\s*:=\s*holdOffset') (
        "The learner no longer records which control identified the device, so " +
        "it cannot wait for that control to be released before measuring rest.")

    # THE PAD THAT REPORTS ONLY ON CHANGE IS WHERE THIS WIZARD HANGS.
    #
    # Found by the user, not the code: the same pad completes the run in
    # DirectInput mode and hangs during the button steps in XInput mode. The
    # discriminator is not the gyro and not the mode -- it is whether rest
    # sampling receives anything. A streaming pad feeds the rest loop, which
    # rewrites LearnBaseline from every rest report, so a control held when the
    # window opened is corrected away. A change-only pad feeds it nothing, and
    # whatever the baseline holds stays.
    #
    # What it holds is the pre-press report, and the wizard is opened by pressing
    # A, so that press is usually still down in it. The identifying control then
    # reads as permanently pressed: learned inverted, and thereafter its bit is
    # in the changed mask of every report, wins the lowest-set-bit tie-break, and
    # is rejected as already claimed -- so every later step is dead. Two logs,
    # two pads, stuck immediately after the control that had identified it.
    #
    # For a change-only pad, no report means nothing moved, so the last report
    # seen IS the resting state. Keeping an older one is indefensible on any pad.
    $begin = Get-AhkFunctionBody -Source $sharedText -Name "ControllerLearnBeginSteps"
    Assert-True ($begin -ne "" -and
        $begin -match '(?s)if\s*\(LearnRestCount = 0\)(?:(?!\n\})[\s\S])*?' +
            'LearnBaseline\s*:=\s*ControllerLearnCopyReport\(\s*\r?\n?\s*LearnIdleSample') (
        "ControllerLearnBeginSteps no longer adopts the last report seen when " +
        "rest sampling received nothing. On a pad that reports only on change " +
        "that is the only rest sample there is, and without it the identifying " +
        "control stays pressed in the baseline and every step after it is dead.")
    Assert-True ($report -match '(?s)if \(LearnIdentifyHoldOffset >= 0\)(?:(?!\n\})[\s\S])*?LearnIdleSampleSeen := true') (
        "ControllerLearnReport no longer records the last report seen while the " +
        "identifying control settles, so ControllerLearnBeginSteps has nothing " +
        "to fall back on when the pad says nothing at rest.")
    # A BUTTON CHANGES A BIT; AN ANALOGUE BYTE CHANGES MOST OF THEM. Reported
    # from hardware: in DirectInput mode the identification step completed
    # without the user touching anything, and the log named byte 18 bit 0xF8 --
    # the high byte of a gyro axis parked at -60, flipping 0xFF to 0x00 on every
    # zero crossing, eight bits at once against a resting mask of 0x07.
    #
    # A longer noise window cannot fix it: an axis parked near zero may not cross
    # while it is being measured. The shape of the change can, on the first
    # report. The scan must also CONTINUE past a candidate it rejects -- stopping
    # at the first changed byte is what let a stick nudged during the press win
    # over the button, since byte 2 comes long before byte 8.
    Assert-True (
        $report -match 'allowed := \(A_Index = 1\) \? 1 : MAX_IDENTIFY_BITS' -and
        $report -match 'if \(bits > allowed\)\s*\r?\n\s*continue' -and
        $report -match '(?s)if !changed\s*\r?\n\s*continue(?:(?!\n\})[\s\S])*?identified := true') (
        "Identification accepts a change of any shape, so an analogue byte " +
        "crossing a boundary answers the prompt before the user touches " +
        "anything -- and it stops at the first byte that moved, so a nudged " +
        "stick outranks the button being pressed.")
    Assert-True ($report -match '(?s)if\s*\(LearnIdentifyHoldOffset\s*>=\s*0\)') (
        "ControllerLearnReport no longer holds off while the identifying " +
        "control is down. Rest would be measured from reports in which it is " +
        "still held.")

    $released = Get-AhkFunctionBody -Source $sharedText `
        -Name "ControllerLearnIdentifyReleased"
    Assert-True ($released -ne "" -and
        $released -match 'LearnRestSampling\s*:=\s*true' -and
        $released -match 'ControllerLearnBeginSteps') (
        "ControllerLearnIdentifyReleased is missing or no longer starts the " +
        "rest phase. It is the single entry point to rest measurement; without " +
        "it the wizard either never measures rest or measures it too early.")
    $timeout = Get-AhkFunctionBody -Source $sharedText `
        -Name "ControllerLearnIdentifyHoldTimeout"
    Assert-True ($timeout -ne "" -and $timeout -match 'ControllerLearnIdentifyReleased') (
        "The identify hold has no timeout. A pad whose release report is lost " +
        "would leave the wizard waiting forever on a prompt already answered, " +
        "with no way forward but Cancel.")

    # The rest phase must have exactly one entry point. This is where it used to
    # start -- on identification, which is the press.
    $ui = Get-AhkFunctionBody -Source $sharedText -Name "ControllerLearnUpdateUi"
    Assert-True ($ui -ne "" -and $ui -notmatch 'LearnRestSampling\s*:=\s*true') (
        "ControllerLearnUpdateUi starts rest sampling again. It runs the moment " +
        "the device is identified, which is the moment the button went down, so " +
        "rest would once more be measured with it held.")
    if (-not $Quiet) {
        Write-Host ("Controller learner: rest is measured from the pre-press " +
            "idle report, and only after the identifying control is released.")
    }
}


# The recent-application history, and the picker that reads it.
#
# Four things, none of which fails to compile and none of which a user can tell
# apart from "the list is just empty":
#
# 1. BOTH trees run RecentAppsTick. It is a shared function with no caller of its
#    own -- a timer is the only thing that drives it -- so a tree that stops
#    arming it gets a picker that is permanently empty, and an empty picker looks
#    like a feature that has nothing to offer rather than one that is unwired.
#
# 2. It is armed OUTSIDE the conditional blocks. The shell's other foreground
#    observer runs inside WindowEngineTick, which stops in desktop mode; the
#    companion's ApplyRuntimeTimers returns early when disabled. Arming the
#    history inside either would leave a hole in it in exactly the state a user
#    is in when they go looking for the setting.
#
# 3. The picker is REACHABLE in both products. It is defined in the shared file
#    and compiled into both, which is not the same as being on a button.
#
# 4. ApplicationFrameHost stays excluded. Every windowed Store app's visible
#    window belongs to it, so admitting it would put one entry into the picker
#    that silently stands for Settings, Photos, Calculator and the Store at once
#    -- and the exe lists this feeds would then match all of them. It is kept out
#    until the hosted process can be resolved, and this is what stops it being
#    "fixed" back in.
function Assert-RecentApplicationPicker {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    foreach ($name in @("RecentAppsTick", "RecentAppsRecord", "RecentAppsGet",
                        "RecentAppsExcluded", "ShowApplicationPicker")) {
        Assert-True ((Get-AhkFunctionBody -Source $sharedText -Name $name) -ne "") (
            "SteamShell-Shared.ahk defines no $name(); the recent-application " +
            "picker is no longer shared and this check cannot see what replaced it.")
    }

    $excluded = Get-AhkFunctionBody -Source $sharedText -Name "RecentAppsExcluded"
    Assert-True ($excluded -match '(?i)"applicationframehost\.exe",\s*true') (
        "RecentAppsExcluded no longer excludes applicationframehost.exe. Every " +
        "windowed Store app's visible window belongs to that process, so the " +
        "picker would offer one entry that stands for all of them and write it " +
        "into an exe list as if it named a single application.")

    # THE SECOND ROUTE TO THE PICKER, which is now the companion's only one.
    #
    # This check used to require the tree's OWN file to name ShowApplicationPicker,
    # which was right while each tree wired its own Recent… button. The exe-list
    # field moved to SteamShell-Shared.ahk and took the button with it, so the
    # companion reaches the picker by BUILDING A FIELD -- and the check read that
    # as the picker being dead, when it is on a button in both products.
    #
    # Reachable still means WIRED, so the whole chain is verified here rather than
    # the field's name being accepted as a promise: the builder puts
    # SettingsExeListAddRecent on a button, and that function opens the picker. A
    # tree that builds one of these fields has the picker on a button by
    # construction. Break any link and this route stops counting, which is what
    # keeps it from being a hole in the check.
    $exeListBuilder = Get-AhkFunctionBody -Source $sharedText -Name "SettingsAddExeListField"
    $exeListRecent = Get-AhkFunctionBody -Source $sharedText -Name "SettingsExeListAddRecent"
    $sharedFieldRoute =
        ($exeListBuilder -match 'OnEvent\("Click",\s*SettingsExeListAddRecent\.Bind\(') -and
        ($exeListRecent -match 'ShowApplicationPicker\(')

    foreach ($pair in @(
        @{ Name = "SteamShell.ahk";     Product = "the shell" },
        @{ Name = "SteamShell-XFE.ahk"; Product = "the companion" })) {
        $treeText = Get-SourceText (Join-Path $ProjectRoot $pair.Name)
        $timers = Get-AhkFunctionBody -Source $treeText -Name "ApplyRuntimeTimers"
        Assert-True ($timers -match 'SetTimer\(RecentAppsTick,\s*RecentAppsIntervalMs\(\)\)') (
            "$($pair.Name): ApplyRuntimeTimers never arms RecentAppsTick, so " +
            "$($pair.Product) records no application history and its picker is " +
            "permanently empty.")

        # Armed at the function's own indent level, not inside an if or a block.
        # Anything more deeply indented is conditional on something, and the
        # whole point is that this one is not.
        Assert-True ($timers -match '(?m)^    SetTimer\(RecentAppsTick,') (
            "$($pair.Name) arms RecentAppsTick inside a conditional block. The " +
            "history has to be recorded in every mode -- desktop mode in the " +
            "shell, disabled in the companion -- because those are the states " +
            "somebody is in when they open Settings to work out what to add.")

        # Reachable means WIRED. Comments naming it are not a route to it.
        $code = (((Get-SourceLines (Join-Path $ProjectRoot $pair.Name)) |
            ForEach-Object { $_ -replace '(?<!`);.*$', '' }) -join "`n")
        Assert-True (
            ($code -match 'ShowApplicationPicker\(') -or
            ($sharedFieldRoute -and $code -match 'SettingsAddExeListField\(')) (
            "$($pair.Name) never opens ShowApplicationPicker, directly or by " +
            "building a shared exe-list field. It is compiled into " +
            "$($pair.Product) from the shared file and would be dead: the " +
            "history would be recorded and never offered to anybody.")
    }
    if (-not $Quiet) {
        Write-Host ("Recent applications: history armed unconditionally and a " +
            "picker reachable in both products.")
    }
}

# The shipped AutoMouseExeList is one list, not nine.
#
# DefaultAutoMouseExeList in SteamShell-Common.ahk is the single source, and
# every CODE path calls it. Three copies cannot: the shell's embedded default INI
# text and the two shipped sample INIs are literal text a user reads and edits.
# Those are held to the function here.
#
# This is the version-string trap in another key. The 2.0.0 bump missed five of
# that literal's copies because one spelling was escaped and the grep only found
# the other; a default duplicated across two products, a text blob and
# two samples drifts exactly the same way, and the failure is quiet -- a user
# whose INI came from the sample gets a different allowlist from a user who let
# the shell write its own.
#
# It also catches the direction that matters most: a NEW entry added to the
# function and not to the samples, so the feature works on a fresh install and
# not for anyone who started from the shipped file.
function Assert-AutoMouseDefaults {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $commonText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Common.ahk")
    $body = Get-AhkFunctionBody -Source $commonText -Name "DefaultAutoMouseExeList"
    Assert-True ($body -ne "") (
        "SteamShell-Common.ahk defines no DefaultAutoMouseExeList(); the shipped " +
        "automatic-mouse allowlist has no single source and this check is blind.")
    if ($body -eq "") { return }

    # The return is a concatenation across lines, so join every literal in it.
    $expected = -join ([regex]::Matches($body, '"([^"]*)"') |
        ForEach-Object { $_.Groups[1].Value })
    Assert-True ($expected -match '^[a-z0-9.|_-]+$' -and $expected.Contains("|")) (
        "DefaultAutoMouseExeList() did not read as a pipe-separated list of " +
        "executables; it came out as '$expected'. The scan cannot check the " +
        "copies against something it has misread.")

    foreach ($copy in @(
        @{ File = "SteamShell.ahk";                What = "the shell's embedded default INI text" },
        @{ File = "SteamShellSettings_SAMPLE.ini"; What = "the shell's sample INI" },
        @{ File = "SteamShell-XFE_SAMPLE.ini";     What = "the companion's sample INI" })) {
        $path = Join-Path $ProjectRoot $copy.File
        Assert-True (Test-Path -LiteralPath $path) (
            "$($copy.File) is missing; it carries a copy of the automatic-mouse " +
            "allowlist that has to match DefaultAutoMouseExeList().")
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $found = @([regex]::Matches(
            (Get-SourceText $path), '(?m)^AutoMouseExeList=([^\s;\r\n]*)'))
        Assert-True ($found.Count -ge 1) (
            "$($copy.File) states no AutoMouseExeList=; $($copy.What) has lost " +
            "the allowlist, so a user starting from it gets an empty one.")
        foreach ($m in $found) {
            Assert-True ($m.Groups[1].Value -eq $expected) (
                "$($copy.File) ships AutoMouseExeList=$($m.Groups[1].Value) but " +
                "DefaultAutoMouseExeList() is $expected. $($copy.What) has " +
                "drifted from the code, so what a user gets depends on whether " +
                "their INI came from the sample or from the shell writing one.")
        }
    }

    # Nobody may restate the default instead of calling the function.
    #
    # Two traps here, both met before this settled.
    #
    # The string next to "AutoMouseExeList" is usually the row's LABEL --
    # "Shell-mode automatic mouse allowlist", "Automatic mouse applications
    # (pipe-separated)" -- or the following Map key, so asserting on the quoted
    # neighbour failed three legitimate call sites. A DEFAULT is told apart by
    # naming an executable, which no label does.
    #
    # And the call WRAPS, so the default can be two lines below the key. The
    # obvious pattern for that -- `(?:[^\n]|\n[ \t]+){0,300}?` -- backtracks
    # catastrophically and does not finish. A LINE WINDOW is used instead: the
    # key's line and the two after it, joined. That is linear, cannot hang, and
    # is wide enough for every wrapped form in either tree. A hang is the worst
    # failure mode a check can have, which is why this is not a cleverer regex.
    foreach ($tree in @("SteamShell.ahk", "SteamShell-XFE.ahk")) {
        $lines = @((Get-SourceLines (Join-Path $ProjectRoot $tree)) |
            ForEach-Object { $_ -replace '(?<!`);.*$', '' })
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -notmatch '"AutoMouseExeList"') { continue }
            $window = ($lines[$i..([Math]::Min($i + 2, $lines.Count - 1))] -join " ")
            $literal = [regex]::Match($window, '"([^"]*\.exe[^"]*)"')
            Assert-True (-not $literal.Success) (
                "$tree line $($i + 1) passes a literal " +
                "'$($literal.Groups[1].Value)' as the AutoMouseExeList default " +
                "instead of calling DefaultAutoMouseExeList(). One more copy is " +
                "how the other nine got out of step.")
        }
    }
    if (-not $Quiet) {
        Write-Host ("Automatic-mouse allowlist: one default, matched by both " +
            "samples and the embedded INI text.")
    }
}

# The controller surface both products present, and the wiring behind it.
#
# Three contracts, none of which fails to compile and none of which a user can
# tell apart from "the controller is just like that on this machine":
#
# 1. BOTH health reports build the shared controller rows. They were the
#    companion's alone; the shell inferred its backend from the wrong question
#    and reported neither the backend setting nor RawInput at all. A tree that
#    stops calling SharedControllerHealthRows loses four rows silently, on the
#    report a user is asked to send when their controller does not work.
#
# 2. BOTH trees record which backend answered. ActiveInputBackend is written only
#    by SetActiveBackend, so a ControllerReadState that stops calling it leaves
#    the global at its initial "none" -- and the shared row then reports
#    "Active: none" beside a controller that is plainly working. Nothing throws;
#    the report just quietly lies.
#
# 3. The learned-profile escape hatch is REACHABLE in both. The function is in
#    SteamShell-Shared.ahk and compiled into both products, and the shell bound
#    it to nothing at all for as long as it existed -- so a mis-learned axis,
#    which reads as a stick held over and sends the pointer off the screen, had
#    no undo on the product that replaces the Windows shell. Being defined is not
#    being reachable, which is the whole point of this check.
function Assert-ControllerSurfaceParity {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    foreach ($name in @("SharedControllerHealthRows", "SetActiveBackend",
                        "DeleteControllerProfileForActiveDevice")) {
        Assert-True ((Get-AhkFunctionBody -Source $sharedText -Name $name) -ne "") (
            "SteamShell-Shared.ahk defines no $name(); the controller surface " +
            "is no longer shared and this check cannot see what replaced it.")
    }
    foreach ($pair in @(
        @{ Name = "SteamShell.ahk";     Product = "the shell" },
        @{ Name = "SteamShell-XFE.ahk"; Product = "the companion" })) {
        $treeText = Get-SourceText (Join-Path $ProjectRoot $pair.Name)
        $health = Get-AhkFunctionBody -Source $treeText -Name "ProductHealthResults"
        Assert-True ($health -match 'SharedControllerHealthRows\(') (
            "$($pair.Name): ProductHealthResults does not build the shared " +
            "controller rows. $($pair.Product) would report nothing about the " +
            "backend, RawInput, or duplicate mappings.")

        $read = Get-AhkFunctionBody -Source $treeText -Name "ControllerReadState"
        Assert-True ($read -match 'SetActiveBackend\(') (
            "$($pair.Name): ControllerReadState never calls SetActiveBackend, so " +
            "ActiveInputBackend stays 'none' and the shared Health Check row " +
            "reports no active backend while the controller works.")

        # Reachable means WIRED: a hotkey, a tray entry or a control. A bare
        # mention in a comment is not a route to it, so comments come out first.
        $code = (((Get-SourceLines (Join-Path $ProjectRoot $pair.Name)) |
            ForEach-Object { $_ -replace '(?<!`);.*$', '' }) -join "`n")
        $routes = @([regex]::Matches(
            $code, 'DeleteControllerProfileForActiveDevice')).Count
        Assert-True ($routes -ge 1) (
            "$($pair.Name) never reaches DeleteControllerProfileForActiveDevice. " +
            "It is compiled into this product from SteamShell-Shared.ahk and " +
            "would be dead: a badly learned controller profile could not be " +
            "undone without hand-editing the profile file.")
    }
    if (-not $Quiet) {
        Write-Host ("Controller surface: shared health rows, recorded backend " +
            "and a reachable profile reset in both products.")
    }
}

# The two products' score-weight tables must offer the same KEYS.
#
# KEPT IN STEP WITH check_game_score_weight_keys in Replay-Validation.py.
#
# XfeGameScoreWeights and WindowEngineScoreWeights are correctly two functions:
# each fills the same shaped Map from its own settings namespace, and passing
# eleven values across a boundary to rebuild a Map the caller already holds would
# be longer and no safer.
#
# The KEY NAMES are not per-product. GameWindowShapeVerdict and
# GameWindowCpuVerdict index them by name for both, so a key renamed on one side
# does not fail to compile and does not throw -- AutoHotkey returns nothing for a
# missing Map key and the verdict quietly scores against an empty weight. The
# product that still has the key keeps working, which is what makes it hard to
# notice. This is the only thing asserting that contract.
function Assert-GameScoreWeightKeys {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $tables = @{}
    foreach ($pair in @(
        @{ Tree = "SteamShell.ahk";     Function = "WindowEngineScoreWeights" },
        @{ Tree = "SteamShell-XFE.ahk"; Function = "XfeGameScoreWeights" })) {
        $body = Get-AhkFunctionBody `
            -Source (Get-SourceText (Join-Path $ProjectRoot $pair.Tree)) `
            -Name $pair.Function
        Assert-True ($body -ne "") (
            "$($pair.Tree) defines no $($pair.Function)(); the shared scorers " +
            "index its keys.")
        if ($body -eq "") { return }
        $keys = New-Object System.Collections.Generic.HashSet[string]
        foreach ($m in [regex]::Matches($body, '"(\w+)"\s*,')) {
            [void]$keys.Add($m.Groups[1].Value)
        }
        Assert-True ($keys.Count -ge 8) (
            "$($pair.Tree): only $($keys.Count) weight keys were read from " +
            "$($pair.Function); the scan is not seeing the table.")
        if ($keys.Count -lt 8) { return }
        $tables[$pair.Function] = $keys
    }
    foreach ($side in @(
        @{ Has = "WindowEngineScoreWeights"; Missing = "XfeGameScoreWeights"; Product = "companion" },
        @{ Has = "XfeGameScoreWeights"; Missing = "WindowEngineScoreWeights"; Product = "shell" })) {
        foreach ($key in @($tables[$side.Has] |
            Where-Object { -not $tables[$side.Missing].Contains($_) } | Sort-Object)) {
            Assert-True $false (
                "$($side.Has) offers the weight '$key' and $($side.Missing) does " +
                "not. The shared scorers index weights by name for both products, " +
                "so the $($side.Product) scores against an empty value with " +
                "nothing thrown.")
        }
    }
    if (-not $Quiet) {
        Write-Host ("Game score weights: $($tables['WindowEngineScoreWeights'].Count) " +
            "keys, identical in both products.")
    }
}

# Each product's controller-binding table, and the two things it must be.
#
# KEPT IN STEP WITH check_binding_label_tables in Replay-Validation.py.
#
# One table per product now answers three questions -- the label for an action,
# the action for a label, and the list the Settings dropdown offers -- which
# collapsed six hand-maintained copies into two. That puts two requirements on
# the table that nothing else would notice breaking.
#
# UNIQUE LABELS, because the reverse lookup takes the first pair whose label
# matches. Two actions sharing a label makes one unreachable: the user picks it,
# the other is saved, nothing is thrown and nothing is logged.
#
# AN ARRAY, NOT A MAP, because the same table supplies the dropdown's ORDER.
# AutoHotkey promises no enumeration order for a Map, so a table written as one
# would reorder the menu into whatever the implementation chose -- and it would
# read as a cosmetic regression rather than a data-structure one.
function Assert-BindingLabelTables {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    $sharedActions = Get-AhkSwitchCaseLabels (
        Get-AhkFunctionBody -Source $sharedText -Name "ControllerBindingSharedAction")

    $total = 0
    foreach ($tree in @("SteamShell.ahk", "SteamShell-XFE.ahk")) {
        $text = Get-SourceText (Join-Path $ProjectRoot $tree)
        $body = Get-AhkFunctionBody -Source $text -Name "ControllerBindingLabels"
        Assert-True ($body -ne "") (
            "$tree defines no ControllerBindingLabels(); the binding vocabulary " +
            "would have no single source.")
        if ($body -eq "") { continue }
        Assert-True ($body -match 'static\s+labels\s*:=\s*\[') (
            "${tree}: ControllerBindingLabels must be an ARRAY of [action, label] " +
            "pairs. A Map has no promised enumeration order, and this table " +
            "supplies the Settings dropdown's order.")
        if ($body -notmatch 'static\s+labels\s*:=\s*\[') { continue }

        $pairs = [regex]::Matches($body, '\[\s*"([^"]+)"\s*,\s*"([^"]*)"\s*\]')
        Assert-True ($pairs.Count -ge 10) (
            "${tree}: only $($pairs.Count) binding labels were read from " +
            "ControllerBindingLabels; the scan is not seeing the table.")
        if ($pairs.Count -lt 10) { continue }
        $total += $pairs.Count

        # Dispatch is two steps: the shared actions, then the product's seam.
        # Both have to be consulted or every shared action reads as missing.
        $productActions = Get-AhkSwitchCaseLabels (
            Get-AhkFunctionBody -Source $text -Name "ProductControllerBindingAction")

        foreach ($column in 1, 2) {
            $what = $(if ($column -eq 1) { "action" } else { "label" })
            $seen = @{}
            foreach ($pair in $pairs) {
                $value = $pair.Groups[$column].Value
                $key = $value.ToLowerInvariant()
                Assert-True (-not $seen.ContainsKey($key)) (
                    "${tree}: ControllerBindingLabels repeats the $what '$value'. " +
                    "The reverse lookup takes the first match, so one of the two " +
                    "is unreachable from the Settings dropdown -- picked by the " +
                    "user, saved as the other, with nothing thrown.")
                $seen[$key] = $true
            }
        }
        foreach ($pair in $pairs) {
            $action = $pair.Groups[1].Value
            if ($action -eq "None") { continue }
            Assert-True (
                $productActions.Contains($action) -or $sharedActions.Contains($action)) (
                "${tree}: ControllerBindingLabels offers '$action', which neither " +
                "ProductControllerBindingAction nor ControllerBindingSharedAction " +
                "implements. The dropdown would offer it and selecting it would " +
                "do nothing.")
        }
    }
    if (-not $Quiet) {
        Write-Host ("Controller binding labels: $total actions across 2 products; " +
            "each label unique, ordered, and reaching an implementation.")
    }
}

# The same routine in both trees under two DIFFERENT names.
#
# KEPT IN STEP WITH check_cross_name_anchors in Replay-Validation.py. See its
# docstring for the argument; the short version is that the check this replaces
# scored similarity above two hand-tuned thresholds and, across nine pairs
# eventually found, found none of them -- and lived in Python alone, so it never
# ran here at all.
#
# An ANCHOR is something in a body that means something to this project: a Win32
# export it calls, a string it puts on screen or writes to the log. Two functions
# sharing several anchors almost nothing else uses are doing one job, whatever
# they are called and however far their bodies have drifted. What comes out is
# evidence rather than a score, and the allowlist is where judgement goes.
function Assert-CrossNameAnchors {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    # Ubiquitous exports carry no information about what a function is for.
    $ubiquitous = @("closehandle", "getlasterror", "getforegroundwindow",
        "iswindow", "getwindow")
    # How many tree-only functions an anchor may appear in before it stops
    # meaning anything. Two budgets, because a Win32 export is rarer than a short
    # string and worth more when shared.
    $budget = @{ "api" = 4; "str" = 3 }
    # The shared anchors must also cover this much of the LARGER function. Without
    # it, a table naming every settings key pairs with every small function that
    # names two of them -- the companion's DefaultSettings matched six unrelated
    # shell functions that way. The only ratio here, and it measures how much of a
    # function the evidence covers, not how alike two bodies are.
    $coverage = 0.20

    $standalone = Get-AhkFunctionBodies -Path (Join-Path $ProjectRoot "SteamShell.ahk")
    $companion = Get-AhkFunctionBodies -Path (Join-Path $ProjectRoot "SteamShell-XFE.ahk")

    function Get-FunctionAnchors {
        param([string]$Body)
        $found = @{}
        $lines = @()
        foreach ($line in ($Body -split "`n")) {
            $lines += ($line -replace '(?<!`);.*$', '')
        }
        # Whole-body for DllCall: the target routinely sits on the line after the
        # opening paren in these sources, and a per-line scan misses those. It
        # missed the one pair here that a Win32 export identifies outright.
        $joined = $lines -join "`n"
        foreach ($m in [regex]::Matches($joined, 'DllCall\(\s*"((?:[^"`]|`.)*)"')) {
            $target = ($m.Groups[1].Value -split '\\')[-1].ToLowerInvariant()
            if ($target -and $ubiquitous -notcontains $target -and
                $target -notmatch '^\d+$') {
                $found["api:$target"] = $true
            }
        }
        # Strings per line, because an AutoHotkey literal cannot span one.
        # Scanning the joined body pairs one string's closing quote with the
        # next one's opening quote and turns the CODE BETWEEN THEM into an
        # anchor -- which the first draft did, convincingly.
        foreach ($line in $lines) {
            foreach ($m in [regex]::Matches($line, '"((?:[^"`\n]|`.)*)"')) {
                $text = $m.Groups[1].Value
                if ($text.Length -ge 6 -and $text -match '[A-Za-z]') {
                    $found["str:" + $text.ToLowerInvariant()] = $true
                }
            }
        }
        return $found
    }

    $shellAnchors = @{}
    foreach ($name in $standalone.Keys) {
        if ($companion.ContainsKey($name)) { continue }
        $shellAnchors[$name] = Get-FunctionAnchors -Body $standalone[$name]
    }
    $xfeAnchors = @{}
    foreach ($name in $companion.Keys) {
        if ($standalone.ContainsKey($name)) { continue }
        $xfeAnchors[$name] = Get-FunctionAnchors -Body $companion[$name]
    }

    $seen = @{}
    foreach ($table in @($shellAnchors, $xfeAnchors)) {
        foreach ($set in $table.Values) {
            foreach ($anchor in $set.Keys) {
                $seen[$anchor] = 1 + $(if ($seen.ContainsKey($anchor)) { $seen[$anchor] } else { 0 })
            }
        }
    }
    function Select-Distinctive {
        param($Set)
        $out = @{}
        foreach ($anchor in $Set.Keys) {
            if ($seen[$anchor] -le $budget[$anchor.Substring(0, 3)]) { $out[$anchor] = $true }
        }
        return $out
    }
    foreach ($name in @($shellAnchors.Keys)) {
        $shellAnchors[$name] = Select-Distinctive -Set $shellAnchors[$name]
    }
    foreach ($name in @($xfeAnchors.Keys)) {
        $xfeAnchors[$name] = Select-Distinctive -Set $xfeAnchors[$name]
    }

    $accepted = @{}
    $manifest = Join-Path $ProjectRoot "CROSS_NAME_DUPLICATES.txt"
    if (Test-Path -LiteralPath $manifest) {
        foreach ($line in (Get-SourceLines $manifest)) {
            $trimmed = $line.Trim()
            if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
            $split = $trimmed.IndexOf(":")
            if ($split -lt 0) { continue }
            $accepted[$trimmed.Substring(0, $split).Trim().ToLowerInvariant()] =
                $trimmed.Substring($split + 1).Trim()
        }
    }

    $failures = @()
    $queued = 0
    foreach ($x in ($xfeAnchors.Keys | Sort-Object)) {
        foreach ($s in ($shellAnchors.Keys | Sort-Object)) {
            $shared = @($xfeAnchors[$x].Keys | Where-Object { $shellAnchors[$s].ContainsKey($_) })
            if ($shared.Count -lt 2) { continue }
            $larger = [Math]::Max($shellAnchors[$s].Count, $xfeAnchors[$x].Count)
            if ($shared.Count -lt $coverage * $larger) { continue }
            $key = ("$x=$s").ToLowerInvariant()
            if ($accepted.ContainsKey($key)) {
                if ($accepted[$key] -eq "") {
                    $failures += "CROSS_NAME_DUPLICATES.txt lists '$key' with no reason"
                } elseif ($accepted[$key].ToUpperInvariant().StartsWith("QUEUED")) {
                    $queued++
                }
                continue
            }
            $evidence = (($shared | Sort-Object | Select-Object -First 4) -join "; ")
            $failures +=
                ("SteamShell-XFE.ahk's '$x' and SteamShell.ahk's '$s' share " +
                 "$($shared.Count) distinctive anchors and may be one routine " +
                 "under two names ($evidence). Give them one name and share it, " +
                 "or record the pair in CROSS_NAME_DUPLICATES.txt as '${key}: why'")
        }
    }
    Assert-True ($failures.Count -eq 0) (
        "Cross-name duplicate candidates: " + ($failures -join "; ") + ".")

    if (-not $Quiet) {
        # QUEUED entries are debt, not decisions, and are counted so the
        # allowlist cannot quietly become where work goes to be forgotten.
        Write-Host ("Cross-name anchors: no unrecorded candidates; $queued pair(s) " +
            "recorded as QUEUED and awaiting a decision.")
    }
}

# A braceless control statement whose body is not indented under it.
#
# AutoHotkey does not care about indentation, so this is legal and means exactly
# what the braces would mean -- one statement. The problem is that it does not
# READ that way when the next statement sits at the same indent:
#
#     if (sc)
#     raw := Trim(SubStr(raw, 1, sc - 1))   ; guarded
#     hc := InStr(raw, "#")                 ; NOT guarded, reads as though it is
#
# That pair is real, from the shell's INI parsing, next door to a truncation bug
# fixed in the same pass. It also breaks tools: `sed -n '/^Func/,/^}/p'`
# truncates on these sources because a `}` can appear at column 0 INSIDE a
# function, and that nearly produced a report of a PollController bug that did
# not exist.
#
# ONLY THE AMBIGUOUS ONES. A braceless body at the same indent that ENDS its
# block reads fine, and there are roughly 150 of those in the oldest file;
# reformatting them is a large diff for no gain. The rule needs a third
# statement at the same indent after the body -- the case where a reader
# genuinely cannot tell where the body stops.
function Assert-NoAmbiguousDeindentedBlocks {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$File,
        [switch]$Quiet
    )
    $raw = Get-SourceLines (Join-Path $ProjectRoot $File)

    # Continuation sections are literal text, not code.
    $code = New-Object System.Collections.Generic.List[string]
    $literal = $false
    foreach ($line in $raw) {
        $trimmed = $line.Trim()
        if (-not $literal -and $trimmed -eq "(") { $literal = $true; $code.Add($null); continue }
        if ($literal) {
            if ($trimmed.StartsWith(")")) { $literal = $false }
            $code.Add($null)
            continue
        }
        $code.Add(($line -replace '(?<!`);.*$', ''))
    }
    $live = @()
    for ($i = 0; $i -lt $code.Count; $i++) {
        if ($null -ne $code[$i] -and $code[$i].Trim() -ne "") { $live += $i }
    }

    $found = @()
    for ($p = 0; $p -lt $live.Count - 2; $p++) {
        $line = $code[$live[$p]]
        $head = [regex]::Match(
            $line, '^(\s*)(if|else\s+if|else|while|for|loop|try|catch|finally)\b(.*)$',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $head.Success) { continue }
        $indent = $head.Groups[1].Value.Length
        $keyword = $head.Groups[2].Value.ToLowerInvariant() -replace '\s+', ''
        $rest = $head.Groups[3].Value.TrimEnd()
        if ($rest.EndsWith("{")) { continue }

        # Does the statement already carry its body on the same line?
        $inline = $false
        $body = $rest.Trim()
        if ($keyword -in @("try", "else", "finally")) {
            $inline = $body -ne ""
        } elseif ($keyword -eq "catch") {
            # `catch Error as e` is still a header, not a body.
            $inline = $body -ne "" -and $body -notmatch '^[\w.]+(\s+as\s+\w+)?$'
        } elseif ($keyword -in @("if", "elseif", "while")) {
            if ($body.StartsWith("(")) {
                $depth = 0
                for ($c = 0; $c -lt $body.Length; $c++) {
                    if ($body[$c] -eq "(") { $depth++ }
                    elseif ($body[$c] -eq ")") {
                        $depth--
                        if ($depth -eq 0) {
                            $inline = $body.Substring($c + 1).Trim() -ne ""
                            break
                        }
                    }
                }
            }
        }
        # for/loop headers have no bracketing to strip, so no claim is made.
        #
        # Asked of the FIRST line only, and before the walk below. `try Foo("a"`
        # continued by `. "b")` is one statement whose argument list wraps, and
        # walking its parentheses would read the line after it as a body.
        if ($inline) { continue }

        # A CONDITION SPANNING LINES IS STILL THE HEADER, not the body. The first
        # version of this check read the `&& ...` continuation of a multi-line
        # `if` as the statement being guarded -- harmless, since AutoHotkey joins
        # a line beginning with an operator whatever its indent, but the wrong
        # reason. Walking to where the parentheses balance also finds the real
        # cases hidden behind those headers, one of them in the controller poll.
        # $q, not $p: reassigning the loop variable would advance the outer scan
        # as a side effect, and the Python mirror's `for` does not work that way.
        $q = $p
        $depth = ([regex]::Matches($rest, '\(')).Count - ([regex]::Matches($rest, '\)')).Count
        $wrapped = $depth -gt 0
        while ($depth -gt 0 -and $q + 1 -lt $live.Count) {
            $q++
            $rest = $code[$live[$q]].TrimEnd()
            $depth += ([regex]::Matches($rest, '\(')).Count - ([regex]::Matches($rest, '\)')).Count
        }
        if ($depth -gt 0) { continue }
        if ($rest.EndsWith("{")) { continue }
        # The balancing ')' is on this line, so anything after it is a one-liner
        # body: `... && b) return`.
        if ($wrapped -and -not $rest.TrimEnd().EndsWith(")")) { continue }
        if ($q + 2 -ge $live.Count) { continue }

        $bodyLine = $code[$live[$q + 1]]
        $afterLine = $code[$live[$q + 2]]
        if ($bodyLine.TrimStart().StartsWith("{")) { continue }
        if (($bodyLine.Length - $bodyLine.TrimStart().Length) -ne $indent) { continue }
        if (($afterLine.Length - $afterLine.TrimStart().Length) -ne $indent) { continue }
        if ($afterLine -match '^\s*(\}|else\b|catch\b|finally\b)') { continue }
        $found += (
            "${File}:$($live[$p] + 1) $keyword has no brace and its body sits at the " +
            "same indent, with another statement after it at that indent: " +
            "`"$($bodyLine.Trim())`" then `"$($afterLine.Trim())`"")
    }

    Assert-True ($found.Count -eq 0) (
        "Only the first statement is guarded, and nothing on the page says so. " +
        "Indent the body or brace the block: " + ($found -join "; "))

    if (-not $Quiet) {
        Write-Host "Braceless blocks in ${File}: none whose body is ambiguous."
    }
}

# Every Settings row reaches something that reads it.
#
# The Quick Menu half of this question has been checked since the rows moved
# into one table; the Settings half never was, and Settings is the larger
# surface. A row is four independent facts -- it is drawn, it is saved, it is
# read back, and something acts on the value -- and only the first two fail
# visibly. A row whose key nothing reads renders, accepts input, writes the INI,
# and changes nothing, in a window whose whole promise is that it changes things.
#
# TWO STEPS, because they fail differently:
#
#   1. The key is READ, by one of the section/key readers, somewhere in the set
#      the product actually compiles -- its own tree plus Shared plus Common.
#      This catches a row wired to a key nobody consumes, including the common
#      case of a key renamed on one side of the read.
#
#   2. The variable the read lands in is REFERENCED somewhere other than its
#      `global` declaration and its own assignment. A read into a global nothing
#      ever looks at is the same dead control with an extra step.
#
# WHAT THIS DOES NOT CATCH, stated because the gap is easy to mistake for
# coverage. It proves the value is consumed; it cannot prove the consumer is the
# one the label promises. DiagnosticLogging passed both steps in the shell while
# doing nothing it claimed: it was read, and consumed -- by PositionGuiCentered,
# which logs window centring, not the XInput slots the label offers. Telling that
# apart from RtssOverlayToggleShortcut, which is also consumed only in Shared and
# is entirely correct, needs the label's meaning, and no static check has that.
#
# The scan is over the COMPILED set on purpose. Counting only a tree's own file
# reports nine RTSS rows whose sole consumer is Shared -- which is where those
# features live for both products, so the asymmetry is the architecture working.
function Assert-SettingsRowsReachConsumers {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Quiet
    )
    $sharedText = Get-SourceText (Join-Path $ProjectRoot "SteamShell-Shared.ahk")
    $tableStart = $sharedText.IndexOf("SettingsCategoryRows(category) {")
    $tableEnd = $sharedText.IndexOf("return table.Has(category)", [Math]::Max($tableStart, 0))
    Assert-True ($tableStart -ge 0 -and $tableEnd -gt $tableStart) (
        "SettingsCategoryRows could not be read, so no Settings row would be checked " +
        "for a consumer. A scan that sees no rows passes on nothing.")
    if ($tableStart -lt 0 -or $tableEnd -le $tableStart) { return }
    $table = $sharedText.Substring($tableStart, $tableEnd - $tableStart)

    # section+key+product per row. A row with no key is a note or a section
    # header and has nothing to read.
    $rows = @()
    foreach ($m in [regex]::Matches($table, '(?s)Map\((?:[^()]|\([^()]*\))*?\)')) {
        $text = $m.Value
        $key = [regex]::Match($text, '"key"\s*,\s*"([^"]+)"')
        $section = [regex]::Match($text, '"section"\s*,\s*"([^"]+)"')
        if (-not $key.Success -or -not $section.Success) { continue }
        $product = [regex]::Match($text, '"product"\s*,\s*"(\w+)"')
        $rows += [pscustomobject]@{
            Key = $key.Groups[1].Value
            Section = $section.Groups[1].Value
            Product = $(if ($product.Success) { $product.Groups[1].Value } else { "both" })
        }
    }
    Assert-True ($rows.Count -ge 90) (
        "Only $($rows.Count) Settings rows were read from the shared table. The " +
        "extraction is not seeing it, and a scan over nothing passes.")

    # The readers that take (section, key, ...). Nothing else can turn a row's
    # key into a value.
    $readers = "(?:ReadText|ReadNumber|ReadBool|ReadInt|ReadFloat|IniReadS|ReadIniBool|ReadIniInt)"

    $checked = 0
    foreach ($pair in @(
        @{ Product = "standalone"; Tree = "SteamShell.ahk" },
        @{ Product = "xfe";        Tree = "SteamShell-XFE.ahk" })) {
        # CONTINUATION SECTIONS ARE DROPPED, and step 2 is worth nothing without
        # that. GetDefaultSettingsIniText() holds the whole default INI as one
        # literal, so `MouseParkEdge=Right` sits in the shell's source as text --
        # and since most globals are named after their key, nearly every setting
        # in the shell looked consumed by the file that documents it. There is
        # exactly one such section in these sources, opened by a bare `(` line.
        $lines = @()
        foreach ($file in @($pair.Tree, "SteamShell-Shared.ahk", "SteamShell-Common.ahk")) {
            $raw = Get-SourceLines (Join-Path $ProjectRoot $file)
            $literal = $false
            for ($i = 0; $i -lt $raw.Count; $i++) {
                $trimmed = $raw[$i].Trim()
                if (-not $literal -and $trimmed -eq "(") { $literal = $true; continue }
                if ($literal) {
                    if ($trimmed.StartsWith(")")) { $literal = $false }
                    continue
                }
                # A full-line comment naming a setting explains it rather than
                # reading it, and an end-of-line one is worse -- `; MouseHideDelay
                # is read above` would answer for the code.
                $lines += ($raw[$i] -replace '(?<!`);.*$', '')
            }
        }
        $flat = ($lines -join "`n") -replace '\s+', ' '
        # Hoisted: one scan for every assignment fed by a reader, then each row
        # looks itself up in the result. Re-running it per row is the same regex
        # over a megabyte and a half, two hundred times.
        $readSites = [regex]::Matches(
            $flat, '(\w+)\s*:=\s*(?:\w+\(\s*)*' + $readers + '\(')
        # Every identifier that appears in a READING position, collected in one
        # pass. A line contributes every identifier it mentions except the one it
        # assigns to, and a `global` line contributes nothing.
        #
        # STRING BODIES BLANKED here and not in the key scan above. Step 1 looks
        # for a key, which IS a literal; step 2 looks for a variable, and most
        # globals are named after their key -- so `"replacementKey",
        # "EnableMouseParkOnFocusChange"` in a migration table, and the row's own
        # entry in the shared spec, answered for code that had been deleted.
        #
        # A SET, not a scan per row: the per-row form is two hundred rows against
        # thirty thousand lines, and a validator nobody waits for is one nobody
        # runs.
        $consumers = @{}
        foreach ($line in $lines) {
            $trimmed = ($line -replace '"(?:[^"`]|`.)*"', '""').Trim()
            if ($trimmed -eq "" -or $trimmed -match '^global\b') { continue }
            $assigned = [regex]::Match($trimmed, '^(\w+)\s*(?::=|\+=|-=|\.=)')
            $skip = $(if ($assigned.Success) { $assigned.Groups[1].Value.ToLowerInvariant() } else { "" })
            foreach ($word in [regex]::Matches($trimmed, '(?<![.\w])([A-Za-z_]\w*)(?![\w])')) {
                $lower = $word.Groups[1].Value.ToLowerInvariant()
                if ($lower -eq $skip) { continue }
                $consumers[$lower] = $true
            }
        }

        foreach ($row in $rows) {
            if ($row.Product -ne "both" -and $row.Product -ne $pair.Product) { continue }
            $checked++

            # Step 1: something reads the key.
            #
            # Matched against the FLATTENED text because a read spans two lines
            # whenever MovedSettingSection() is involved, and those are exactly
            # the rows most likely to have drifted.
            $quoted = '"' + [regex]::Escape($row.Key) + '"'
            $binding = $null
            $found = $false
            foreach ($site in $readSites) {
                # Bounded by the next assignment, not by a character count. A
                # fixed window reaches into the NEXT read -- these arrive in runs
                # of one per line -- and binds the row to the variable above it.
                $next = $flat.IndexOf(":=", $site.Index + $site.Length)
                $end = $(if ($next -gt 0) { $next } else { [Math]::Min($flat.Length, $site.Index + $site.Length + 240) })
                $window = $flat.Substring($site.Index + $site.Length,
                    $end - $site.Index - $site.Length)
                if ($window -match $quoted) {
                    $binding = $site.Groups[1].Value
                    $found = $true
                    break
                }
            }
            if (-not $found) {
                # A read that is not assigned anywhere -- passed straight into a
                # call -- is consumed by definition, so look for the bare form
                # before failing.
                $found = $flat -match ($readers + '\((?:[^()]|\([^()]*\))*?' + $quoted)
            }
            Assert-True $found (
                "The $($pair.Product) Settings window offers [$($row.Section)] " +
                "$($row.Key), and nothing in the set it compiles reads that key back. " +
                "The row draws, accepts input and writes the INI, and changes nothing.")
            if (-not $binding) { continue }

            # Step 2: the value reaches something.
            Assert-True ($consumers.ContainsKey($binding.ToLowerInvariant())) (
                "The $($pair.Product) Settings window offers [$($row.Section)] " +
                "$($row.Key), which is read into '$binding', and nothing ever reads " +
                "'$binding' back. The setting is stored and never acted on.")
        }
    }

    if (-not $Quiet) {
        # Parenthesised, for the reason written out over Assert-QuickMenuRows'
        # summary line and then walked into anyway three functions later: -f
        # binds tighter than +, so without the inner parentheses the format
        # operator applies to the SECOND string, which has no placeholder, and
        # the line prints a literal "{0}".
        Write-Host (("Settings rows: {0} row-product pairs checked; every key is read " +
            "back and every value reaches a consumer.") -f $checked)
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
        Get-SourceLines $manifestPath |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }
    )
    $commonManifest = @(
        Get-SourceLines $commonManifestPath |
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
    $commonText = Get-SourceText $commonPath
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
    # Declared here rather than beside its own check below, because this check
    # needs it too.
    #
    # The seam names are EXEMPT from the escape scan. This asks "does Common name
    # anything SteamShell-Shared.ahk defines", and the answer became yes the
    # moment LogLine stopped being three per-program copies and became one shared
    # definition -- which broke the build for a dependency that is satisfied:
    # both trees resolve LogLine through the include of SteamShell-Shared.ahk,
    # and SteamShell-Helper.ahk defines its own. Nothing about that stops the
    # helper compiling, which is the only thing this rule exists to prevent.
    #
    # The guarantee is not dropped, it is moved to the check that is shaped for
    # it: every allowlisted seam name must be RESOLVABLE by all three programs
    # across their include closures, asserted below. A name on this list is one
    # this file has already promised every program can reach.
    $commonSeamAllowed = @("LogLine")
    $commonEscapes = @(
        $shared.Keys | Where-Object {
            $commonSeamAllowed -notcontains $_ -and
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
    # $commonSeamAllowed is declared above, where the escape scan also needs it.
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
    # Across the INCLUDE CLOSURE, not the one file. What has to be true is that
    # the program can RESOLVE the seam at load time, and #Include is how three
    # files become one program -- so a seam function living in
    # SteamShell-Shared.ahk satisfies both trees exactly as a per-tree copy did.
    # Checking the tree's own table alone demanded a copy in every tree, which is
    # the duplication the rest of this file exists to drive out: it failed the
    # moment LogLine stopped being two identical copies and became one.
    foreach ($name in $commonSeamAllowed) {
        foreach ($pair in @(
            @{ Name = "SteamShell.ahk"; Tables = @($standalone, $shared, $common) },
            @{ Name = "SteamShell-XFE.ahk"; Tables = @($companion, $shared, $common) },
            @{ Name = "SteamShell-Helper.ahk"; Tables = @($helper, $common) })) {
            $resolvable = $false
            foreach ($table in $pair.Tables) {
                if ($table.ContainsKey($name)) {
                    $resolvable = $true
                    break
                }
            }
            Assert-True $resolvable (
                "$($pair.Name) cannot resolve '$name', which " +
                "SteamShell-Common.ahk depends on, from any file it compiles. " +
                "AutoHotkey resolves that at load time, so the program would " +
                "not start.")
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
        $text = Get-SourceText $program
        Assert-True ($text -match '(?m)^#Include\s+SteamShell-Common\.ahk\s*$') (
            "$([System.IO.Path]::GetFileName($program)) does not #Include " +
            "SteamShell-Common.ahk, so it carries its own copy of shared logic.")
    }
    # ...and the helper must NOT include the tree-coupled half, which reaches
    # into eight tree functions and would not compile there.
    $helperText = Get-SourceText $helperPath
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
    $sharedText = Get-SourceText $sharedPath
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

    # The same requirement for automatic mouse mode.
    #
    # It used to cross from SteamShell.ahk, and this check named that file. The
    # publisher moved to SteamShell-Shared.ahk when elevated input became shared
    # -- the companion needed the same channel -- so the pairing is now the same
    # one the RTSS channels above use, shared file against helper.
    #
    # This one is worth stating as a rule because of what it replaced. Both
    # processes used to decide independently whether the controller was a mouse,
    # and could not agree: the real answer depends on DesktopMode, which the
    # helper cannot observe. If this event stops being published or stops being
    # read, that divergence comes back silently -- automatic mouse mode simply
    # stops engaging over elevated windows, which looks like a controller
    # problem and not like a name.
    foreach ($end in @(
        @{ File = "SteamShell-Shared.ahk"; Text = $sharedText; Role = "publishes" },
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
        $text = Get-SourceText $tree
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
    $sharedText = Get-SourceText (
        Join-Path $projectRoot "SteamShell-Shared.ahk")
    $sharedActionBody = [regex]::Match(
        $sharedText,
        '(?ms)^ControllerBindingSharedAction\(action\)\s*\{.*?^\}\s*$').Value
    $sharedActions = @([regex]::Matches($sharedActionBody, 'case\s+"(\w+)"') |
        ForEach-Object { $_.Groups[1].Value })
    Assert-True ($sharedActions.Count -ge 10) (
        "ControllerBindingSharedAction could not be read; every controller " +
        "binding would be reported as unreachable.")
    foreach ($tree in @("SteamShell.ahk", "SteamShell-XFE.ahk")) {
        $treeText = Get-SourceText (Join-Path $projectRoot $tree)
        $seamBody = [regex]::Match(
            $treeText,
            '(?ms)^ProductControllerBindingAction\(action\)\s*\{.*?^\}\s*$').Value
        Assert-True ($seamBody -ne "") (
            "$tree defines no ProductControllerBindingAction; the actions only " +
            "it implements would be unreachable.")
        $executable = @($sharedActions) +
            @([regex]::Matches($seamBody, 'case\s+"(\w+)"') |
                ForEach-Object { $_.Groups[1].Value }) + @("None")
        # ONE TABLE PER PRODUCT NOW, in one shape. This used to read
        # ControllerBindingPretty and had to know that the shell wrote its labels
        # as `case "X":` and the companion as a Map, because the vocabulary lived
        # in the resolver. It is ControllerBindingLabels -- an ordered array of
        # [action, label] pairs -- for both, and the resolver is shared.
        $labelBody = [regex]::Match(
            $treeText,
            '(?ms)^ControllerBindingLabels\(\)\s*\{.*?^\}\s*$').Value
        Assert-True ($labelBody -ne "") (
            "$tree defines no ControllerBindingLabels; binding labels cannot be checked.")
        $labelled = @([regex]::Matches($labelBody, '\[\s*"([^"]+)"\s*,\s*"[^"]*"\s*\]') |
            ForEach-Object { $_.Groups[1].Value })
        Assert-True ($labelled.Count -ge 10) (
            "${tree}: the ControllerBindingLabels table could not be read, so a " +
            "label with no action behind it would go unnoticed.")
        foreach ($action in ($executable | Sort-Object -Unique)) {
            Assert-True ($labelled -contains $action) (
                "$tree executes controller binding '$action' but " +
                "ControllerBindingLabels gives it no label, so the binding UI " +
                "would show its raw internal name.")
        }
        # The reverse: a label with nothing behind it would bind a button to
        # nothing. Assert-BindingLabelTables makes the same check against the
        # dispatchers; this one comes at it from the executable side, and the two
        # together close the loop in both directions.
        foreach ($label in ($labelled | Sort-Object -Unique)) {
            Assert-True ($executable -contains $label) (
                "$tree offers controller binding '$label' in " +
                "ControllerBindingLabels, but nothing executes it: choosing it " +
                "would bind a button that does nothing.")
        }
    }

    # The View button's own tap/hold action exists in BOTH products.
    #
    # It was the companion's alone, and the reason given was that the shell uses
    # View/Back as its mapping modifier and so has no bare press to give meaning
    # to. The companion uses it as a modifier too -- same mappings, same
    # automatic mouse mode, expressed the same way -- so that reason described
    # neither product. What made it possible in one and not the other was only
    # that one had been given the tracking.
    #
    # Three things have to hold in each tree, and the third is the one that makes
    # the other two safe: the press must be marked as a modifier use the moment
    # any other input arrives during the hold, or "hold View, press A" fires a
    # Steam shortcut underneath the mapping.
    # The tracker is ControllerTrackViewButton in SteamShell-Shared.ahk now, so
    # the three rules are checked once where they live, and each tree is checked
    # for still calling it -- which is the half that could silently go away and
    # take both actions with it.
    $viewTracker = Get-AhkFunctionBody `
        -Source (Get-SourceText (Join-Path $projectRoot "SteamShell-Shared.ahk")) `
        -Name "ControllerTrackViewButton"
    Assert-True (
        $viewTracker -ne "" -and
        $viewTracker -match 'ViewButtonReleased\(\s*\r?\n?\s*now - pressTick, usedAsModifier\)' -and
        $viewTracker -match '(?s)if !wasDown \{[\s\S]{0,200}?pressTick := now' -and
        $viewTracker -match
            '(?s)\|\| lt > 30 \|\| rt > 30[\s\S]{0,120}?usedAsModifier := true') (
        "ControllerTrackViewButton must record the press tick and mark the press " +
        "as a modifier use as soon as anything else is touched during the hold, " +
        "then report the hold to ViewButtonReleased.")
    foreach ($tree in @("SteamShell.ahk", "SteamShell-XFE.ahk")) {
        Assert-True (
            (Get-SourceText (Join-Path $projectRoot $tree)) -match
                'ControllerTrackViewButton\(') (
            "${tree} no longer tracks the View button's own press, so its tap " +
            "and hold actions can never fire.")
    }

    # ...and the page those rows live on has to be one the product DRAWS.
    #
    # The rows were tagged for the shell and were still invisible, because they
    # sit in the shared table's "Steam" category and the shell's Settings window
    # had no Steam page -- it read the whole [Steam] section and offered none of
    # it. A row built for a page nothing draws is the quietest way to ship a
    # setting nobody can reach, and it looks exactly like the feature not
    # working.
    $shellText = Get-SourceText (
        Join-Path $projectRoot "SteamShell.ahk")
    # The page list is SettingsCategoryDefinitions now, not an array written out
    # in the shell, so the first half asks the shared table whether standalone
    # gets a Steam page and the second still asks the shell whether it draws it.
    $sharedCategoryText = Get-SourceText (
        Join-Path $projectRoot "SteamShell-Shared.ahk")
    Assert-True (
        $sharedCategoryText -match '"name", "Steam", "product", "(both|standalone)"' -and
        $shellText -match
            '(?s)category := "Steam"[\s\S]{0,400}?' +
            'SettingsAddRowsForCategory\(SettingsGui, category, "standalone"') (
        "SteamShell.ahk defines Steam settings rows but does not draw a Steam " +
        "category, so they cannot be reached from the Settings window.")

    # ...and it is OFF by default in the shell, ON in the companion.
    #
    # A deliberate asymmetry, which is the kind most at risk of being tidied away
    # by someone normalising the two. It is also stated in four places per
    # product -- the global, the LoadSettings fallback, the settings-spec row and
    # the sample INI -- and the spec row is the one that bites silently:
    # SettingsPopulateFields reads it as the fallback when the key is absent, so
    # a spec saying true against a LoadSettings saying false shows the user a
    # window claiming the feature is on while the program runs with it off.
    $sharedSpecText = Get-SourceText (
        Join-Path $projectRoot "SteamShell-Shared.ahk")
    Assert-True (
        $sharedSpecText -match
            '(?s)"product", "standalone"[^)]*?"key", "EnableViewButtonActions"' +
            '[^)]*?"default", false' -and
        $sharedSpecText -match
            '(?s)"product", "xfe"[^)]*?"key", "EnableViewButtonActions"' +
            '[^)]*?"default", true' -and
        (Get-SourceText (Join-Path $projectRoot "SteamShell.ahk")) -match
            'ReadBool\("Steam", "EnableViewButtonActions", false\)' -and
        (Get-SourceText (Join-Path $projectRoot "SteamShell-XFE.ahk")) -match
            'ReadBool\("Steam", "EnableViewButtonActions", true\)') (
        "The View button action must default OFF in the shell and ON in the " +
        "companion, and each tree's settings-spec row must carry the same " +
        "default its LoadSettings uses.")

    # Restoring the frame cap must re-enable the limiter even when the FPS write
    # fails.
    #
    # The FPS is a property of RTSS's Global profile on disk and cannot be saved
    # unelevated against a stock Program Files install; the limiter flag goes
    # through RTSS's shared memory and works either way. Returning on the failed
    # write skipped the flag, so whether the limiter survived a reboot was
    # decided by whether RTSS happened to already hold the recorded FPS -- and
    # when it did not, the cause was usually that an earlier write had been
    # blocked too, so it stayed broken.
    #
    # Expressed as ORDER, because that is what the defect was: the flag must be
    # applied before any early return that reports the FPS could not be written.
    # NOT $shared: that name already holds the function-body table this whole
    # function indexes with .ContainsKey, and reusing it here replaced the table
    # with a string. Everything above this line had already run, so the failure
    # surfaced hundreds of lines later as "[System.String] does not contain a
    # method named 'ContainsKey'" -- nowhere near the assignment that caused it.
    $sharedRtssText = Get-SourceText (
        Join-Path $projectRoot "SteamShell-Shared.ahk")
    Assert-True (
        $sharedRtssText -match
            '(?ms)^RestoreRtssFrameLimitTick\([^)]*\)\s*\{[\s\S]*?' +
            'fpsRestored := SetRtssGlobalFrameLimit\(' +
            '(?:(?!\n\})[\s\S])*?ApplyRtssGlobalState\("limiter", true\)' +
            '(?:(?!\n\})[\s\S])*?if !fpsRestored') (
        "RestoreRtssFrameLimitTick must re-enable the RTSS limiter before it " +
        "gives up on a failed FPS write; otherwise the limiter silently does " +
        "not survive a reboot whenever RTSS holds a different frame cap.")

    # The controller poll stands down entirely while the learner is open.
    #
    # The wizard reads the pad through WM_INPUT, so it loses nothing -- and every
    # button it asks for has a meaning to the poll. It asks for L3 and R3 by
    # name, and L3+R3 is the Quick Menu chord, so without this the wizard throws
    # the Quick Menu on top of itself while asking for the buttons that do it.
    #
    # Edge state must be cleared on the way out, or every button held when the
    # wizard opened fires its mapping the moment it closes.
    #
    # The block is bounded by what it must NOT contain rather than by how far it
    # is indented. Bounding it by '\n    }' assumed standalone's four spaces, and
    # XFE's guard sits a level deeper inside a try, so on XFE the boundary never
    # bound: the pattern ran on past the guard and found a reset belonging to
    # some later branch. Deleting XFE's reset outright still satisfied it. What
    # actually matters is that no 'return' comes between the guard opening and
    # the reset, which is the same statement without reference to layout.
    #
    # Each fragment is anchored to the start of a line so that a comment
    # MENTIONING one of these statements cannot satisfy or break the rule -- the
    # guard's own comments name both of them.
    $learnGuard =
        '(?ms)^PollController\(\)\s*\{(?:(?!\n\})[\s\S])*?\n[ \t]*if LearnActive \{'
    foreach ($tree in @("SteamShell.ahk", "SteamShell-XFE.ahk")) {
        $treeText = Get-SourceText (Join-Path $projectRoot $tree)
        Assert-True (
            $treeText -match ($learnGuard +
                '(?:(?!\breturn\b)[\s\S])*?\n[ \t]*Reset\w*State\(' +
                '(?:(?!\n\})[\s\S])*?\n[ \t]*return\b')) (
            "${tree}: the controller poll must stand down while the learner is " +
            "open, and clear its edge state on the way out.")

        # ...and the way it clears that state is by asking for a baseline, NOT by
        # zeroing the previous-button word. Zeroing it means the next poll
        # computes pressed as buttons & ~0, so every button still held when the
        # wizard closes arrives as a press edge and fires its mapping -- which is
        # the misfire the guard above is there to prevent. Both trees shipped the
        # zeroing, both under a comment claiming the opposite, so the rule names
        # the wrong shape as well as the right one.
        Assert-True (
            $treeText -match ($learnGuard +
                '(?:(?!\breturn\b)[\s\S])*?\n[ \t]*ControllerNeedsFreshBaseline := true')) (
            "${tree}: the learner guard must request a fresh controller " +
            "baseline, so the first poll after the wizard closes is edge-free.")
        Assert-True (
            -not ($treeText -match ($learnGuard +
                '(?:(?!\breturn\b)[\s\S])*?\n[ \t]*prev\w*Buttons := 0'))) (
            "${tree}: the learner guard must not zero the previous-button " +
            "word -- that turns every button held at close into a press edge.")
    }

    # A learning session stands the automatic mouse down, in both products.
    #
    # The wizard asks for one button at a time and reads the controller itself.
    # Anything else acting on the same pad fights it: the pointer moves under
    # the user, or a mapping fires from the very button being taught.
    #
    # The guard must come FIRST, before the persistent-mode check.
    # AutoMouseModeActive returns true unconditionally when Mouse Mode is on, so
    # a guard placed after it is unreachable in exactly the configuration where
    # this was reported.
    foreach ($tree in @("SteamShell.ahk", "SteamShell-XFE.ahk")) {
        $treeText = Get-SourceText (Join-Path $projectRoot $tree)
        Assert-True (
            $treeText -match
                '(?ms)^AutoMouseModeActive\(\)\s*\{(?:(?!\n\})[\s\S])*?' +
                'if LearnActive\s*\r?\n\s*return false(?:(?!\n\})[\s\S])*?' +
                'if EnablePersistentMouseMode') (
            "${tree}: AutoMouseModeActive must stand down while the controller " +
            "learner is open, and must test that before persistent Mouse Mode, " +
            "which returns true unconditionally.")
    }

    # Every field handed to SettingsRegisterBuiltField must list its controls.
    #
    # The seam iterates field["controls"] to bind each control to its category.
    # A field Map without that key does not degrade -- AutoHotkey throws "Item
    # has no value" and the Settings window fails to open. That is exactly what
    # happened when the shell's builders moved to the shared file and the path
    # field's Map, which never had a "controls" entry because the old code
    # registered its three controls one at a time, was left to be iterated.
    #
    # And a control that is never tracked never hides, so it survives the page
    # it was drawn on and lands on top of the next one. The note row lost its
    # tracking the same way and failed silently rather than loudly.
    $sharedBuilders = [regex]::Matches(
        $sharedText,
        '(?ms)^(SettingsAdd\w+)\((?:(?!\n\})[\s\S])*?\n\}')
    Assert-True ($sharedBuilders.Count -ge 6) (
        "The shared Settings row builders could not be read, so a field that " +
        "registers no controls would go unnoticed.")
    foreach ($builder in $sharedBuilders) {
        $body = $builder.Groups[0].Value
        $name = $builder.Groups[1].Value
        if ($body -notmatch 'SettingsRegisterBuiltField\(') {
            # Not a field row. It still draws something, so it must hand that
            # something to the category tracker.
            if ($body -match 'guiObj\.Add') {
                Assert-True ($body -match 'SettingsProductTrackControl\(') (
                    "Settings builder ${name} draws a control and never tracks " +
                    "it against its category; it would survive its own page.")
            }
            continue
        }
        Assert-True ($body -match '"controls", \[') (
            "Settings builder ${name} registers a field with no ""controls"" " +
            "entry. SettingsRegisterBuiltField iterates it, so the Settings " +
            "window throws on openrather than degrading.")
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
    $sharedText = Get-SourceText (
        Join-Path $projectRoot "SteamShell-Shared.ahk")
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
            $treeText = Get-SourceText (Join-Path $projectRoot $tree)
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

    # The list and its expected size both live at the top of this file, beside
    # Report-StructuralDrift, which is the second reader. Only ONE copy of the
    # number exists; restating it here is what produced two wrong headers.
    $sharedSeamAllowed = $script:sharedSeamAllowed
    $sharedSeamExpectedCount = $script:sharedSeamExpectedCount
    Assert-True ($sharedSeamAllowed.Count -eq $sharedSeamExpectedCount) (
        "The shared seam has $($sharedSeamAllowed.Count) entries but " +
        "`$sharedSeamExpectedCount says $sharedSeamExpectedCount. If the seam " +
        "genuinely needed to change, update the expectation in the same commit " +
        "and record why in the message. If it did not, a tree function has been " +
        "added to the allowlist that should have stayed out of SteamShell-Shared.ahk.")
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
    # CALLS AND CALLBACKS BOTH COUNT.
    #
    # This matched `Name(` only, and the file's own header promises something
    # wider: "nothing may leave this file that is not on it". Four names left it
    # anyway, as bare references rather than calls --
    #
    #   exportButton.OnEvent("Click", ExportDiagnosticBundle)
    #   browseButton.OnEvent("Click", SettingsProductBrowsePath.Bind(...))
    #
    # -- so the allowlist was not the record it claims to be, and widening it was
    # not the decision somebody had to make. The cross-tree reachability check
    # above does cover the case where ONE tree drops such a handler, because the
    # name is then still defined in the other file. It cannot cover both trees
    # dropping it: there is no file left holding the name, nothing to iterate,
    # and Shared goes on naming an identifier AutoHotkey reads as an unassigned
    # local. Nothing fails to load and one control silently does nothing, which
    # is the failure this seam exists to make impossible.
    #
    # A bare word is not automatically a callback. Shared has locals that
    # collide with tree function names case-insensitively, so a name ASSIGNED
    # anywhere in the shared file is excluded -- the same test, and the same
    # reason, as the cross-tree scan above.
    #
    # FILTERED BEFORE THE ASSIGNMENT TEST, not after. The bare-word scan matches
    # tens of thousands of identifiers, and testing each one against a 1.5 MB
    # source would add minutes to a run this project has already measured as
    # regex-bound. Only a word that is otherwise about to be REPORTED is worth
    # the second scan, and there are a handful of those.
    $sharedRefs = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($sharedCode, '(?<![.\w])([A-Za-z_]\w*)\s*\(')) {
        [void]$sharedRefs.Add($m.Groups[1].Value)
    }
    foreach ($m in [regex]::Matches($sharedCode, '(?<![.\w$])([A-Za-z_]\w*)(?![\w(])')) {
        [void]$sharedRefs.Add($m.Groups[1].Value)
    }
    $sharedLeaks = @(
        $sharedRefs |
            Sort-Object -Unique |
            Where-Object {
                -not $shared.ContainsKey($_) -and
                -not $common.ContainsKey($_) -and
                $sharedSeamAllowed -notcontains $_ -and
                ($standalone.ContainsKey($_) -or $companion.ContainsKey($_) -or
                 $helper.ContainsKey($_)) } |
            Where-Object {
                -not ($sharedCode -match
                    ('(?<![.\w])' + [regex]::Escape($_) + '\s*(?::=|\+=|-=|\.=)')) })
    Assert-True ($sharedLeaks.Count -eq 0) (
        "SteamShell-Shared.ahk reaches into a tree through functions that are " +
        "not on its seam allowlist: " + ($sharedLeaks -join ", ") +
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
        $treeText = Get-SourceText $pair.Path
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
        $treeText = Get-SourceText $pair.Path
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
        foreach ($line in (Get-SourceLines $divergentPath)) {
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
    # The seam is exempt, and has to be once the bar is this low.
    #
    # $sharedSeamAllowed IS the record that these differ per product -- that is
    # the entire mechanism, asserted in both directions a few hundred lines above.
    # At 0.75 the gate happened not to reach most of them; at 0.45 it demands a
    # second declaration in DIVERGENT_FUNCTIONS.txt for HideQuickMenu,
    # QuickMenuRefresh, QuickMenuValue, QuickMenuActivateSelected,
    # QuickMenuAdjustSelected and ProductSettingsViewportHeight, all of which
    # Shared calls precisely so the two products can answer differently.
    #
    # Double-booking one fact in two lists is how the counts in this project keep
    # going wrong. One list, checked where it is used.
    $seamExempt = @{}
    foreach ($seamName in $sharedSeamAllowed) { $seamExempt[$seamName.ToLowerInvariant()] = $true }

    $gateFailures = @()
    foreach ($name in ($standalone.Keys | Sort-Object)) {
        if (-not $companion.ContainsKey($name)) { continue }
        if ($seamExempt.ContainsKey($name.ToLowerInvariant())) { continue }
        $left = Get-AhkCallFingerprint -Body $standalone[$name]
        $right = Get-AhkCallFingerprint -Body $companion[$name]
        $score = Get-SequenceSimilarity -Left $left -Right $right
        $subset = $false
        if ($left.Count -gt 0 -and $right.Count -gt 0 -and
            (($left -join "|") -cne ($right -join "|"))) {
            $subset = (Test-IsSubsequence -Small $left -Big $right) -or
                      (Test-IsSubsequence -Small $right -Big $left)
        }
        # 0.45, lowered from 0.75.
        #
        # 0.75 was chosen to keep the gate quiet, and quiet is what it was about
        # the drift that mattered. TrayOpenQuickMenu scored 0.50: nine lines, in
        # which the shell raised the Quick Menu with WinActivate while the
        # companion used ForceForegroundWindow -- the hardened primitive this tree
        # uses in every other Quick Menu path, and the one that wins against the
        # foreground lock a fullscreen game holds. An unported fix, invisible for
        # as long as the bar sat above it.
        #
        # A LOW SCORE IS NOT EVIDENCE OF INTENT. This file's own header already
        # makes that argument about text similarity; it applies just as well to
        # the call sequence, which is only a better proxy, not a true one. Two
        # copies of one routine drift apart in structure as well as in text, so
        # the longer a duplicate goes unmerged the LOWER it scores -- the metric
        # loses confidence exactly as the problem gets worse.
        #
        # 0.45 is where the remaining pairs separate into "same routine, renamed"
        # and "different routine, same name". PollController sits at 0.61 and is
        # 350 lines of one input loop written twice; ReadSettings-style pairs sit
        # near 0.26 and genuinely are two different functions. Below 0.45 the
        # matches were all the second kind, so the bar goes where the evidence
        # changes character rather than where the output is comfortable.
        if ($score -lt 0.45 -and -not $subset) { continue }
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
    # An entry is stale when the PAIR is gone, not when the pair scores low.
    #
    # This used to require membership in $flagged, which is only populated for
    # pairs at or above the threshold -- so documenting a genuinely divergent pair
    # that happens to score below it FAILED as stale. That is stricter than the
    # message this assertion prints, which says "no longer diverge, or ... no
    # longer defined in both trees", and it made the file unable to hold exactly
    # the knowledge that is hardest to recover: OpenWindowsSettings scores 0.00
    # because a privilege-boundary divergence shares no calls at all, and was
    # therefore the one kind of entry the file rejected.
    #
    # Required and permitted are now separate questions. The threshold decides
    # what MUST be explained; being a real pair in both trees decides what MAY be.
    $treePairNames = @{}
    foreach ($name in $standalone.Keys) {
        if ($companion.ContainsKey($name)) { $treePairNames[$name.ToLowerInvariant()] = $true }
    }
    $staleDivergent = @(
        $divergent.Keys |
            Where-Object {
                -not $treePairNames.ContainsKey($_) -and
                -not $helperWrappers.ContainsKey($_) } |
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
