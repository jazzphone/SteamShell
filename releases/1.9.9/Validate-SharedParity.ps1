param(
    [string]$StandalonePath = "",
    [string]$CompanionPath = "",
    [string]$ManifestPath = "",
    [switch]$Quiet
)

# Verifies that the functions shared by SteamShell and SteamShell-XFE are still
# identical in both trees.
#
# The two are parallel trees, not a reference and a copy. Changes belonging to
# both are supposed to be designed once and applied to both in the same pass,
# and for a long time that was an intention with nothing enforcing it: an audit
# in August 2026 found that of 143 shared function names, only 42 were actually
# identical once indentation was normalized, and several of the differences were
# defects rather than deliberate divergence.
#
# This runs from either tree's validator and is skipped when the sibling tree is
# absent, which is the normal case inside a frozen releases/ snapshot -- a
# snapshot has nothing to compare against.

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($StandalonePath)) {
    $StandalonePath = Join-Path $scriptRoot "SteamShell\SteamShell.ahk"
}
if ([string]::IsNullOrWhiteSpace($CompanionPath)) {
    $CompanionPath = Join-Path $scriptRoot "SteamShell-XFE\SteamShell-XFE.ahk"
}
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $scriptRoot "SHARED_FUNCTIONS.txt"
}

foreach ($required in @($StandalonePath, $CompanionPath, $ManifestPath)) {
    if (-not (Test-Path $required)) {
        throw "Shared-parity check cannot run: '$required' was not found."
    }
}

# Top-level functions only: a header at column zero whose body ends at the first
# line that is exactly "}". That is the whole file's convention, and keeping the
# parser this dumb means it cannot disagree with a human reading the same text.
function Get-TopLevelFunctions {
    param([string]$Path)
    $lines = [System.IO.File]::ReadAllLines($Path)
    $functions = @{}
    $index = 0
    while ($index -lt $lines.Count) {
        $header = [regex]::Match(
            $lines[$index], '^([A-Za-z_][A-Za-z0-9_]*)\([^\r\n{}]*\)\s*\{\s*$')
        if ($header.Success) {
            $body = New-Object System.Collections.Generic.List[string]
            $body.Add($lines[$index])
            $scan = $index + 1
            $closed = $false
            while ($scan -lt $lines.Count) {
                $body.Add($lines[$scan])
                if ($lines[$scan] -eq '}') {
                    $closed = $true
                    break
                }
                $scan++
            }
            if ($closed) {
                $functions[$header.Groups[1].Value] = ($body -join "`n")
                $index = $scan + 1
                continue
            }
        }
        $index++
    }
    return $functions
}

$standalone = Get-TopLevelFunctions $StandalonePath
$companion = Get-TopLevelFunctions $CompanionPath

$manifest = @(
    Get-Content -LiteralPath $ManifestPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }
)

$missing = @()
$drifted = @()
foreach ($name in $manifest) {
    if (-not $standalone.ContainsKey($name)) {
        $missing += "$name (absent from SteamShell.ahk)"
        continue
    }
    if (-not $companion.ContainsKey($name)) {
        $missing += "$name (absent from SteamShell-XFE.ahk)"
        continue
    }
    if ($standalone[$name] -cne $companion[$name]) {
        $drifted += $name
    }
}

if ($missing.Count -gt 0) {
    throw (
        "Shared functions listed in SHARED_FUNCTIONS.txt no longer exist in both trees: " +
        ($missing -join ", ") +
        ". If a function was deliberately removed or renamed, update the manifest in the same commit.")
}

if ($drifted.Count -gt 0) {
    throw (
        "Shared functions have drifted between SteamShell and SteamShell-XFE: " +
        ($drifted -join ", ") +
        ". Apply the change to both trees, or drop the name from " +
        "SHARED_FUNCTIONS.txt to record the divergence as deliberate.")
}

# Advisory only. A function that has become identical is a candidate for the
# manifest, but adding it is a decision, not something a validator should make.
$candidates = @(
    $standalone.Keys |
        Where-Object {
            $companion.ContainsKey($_) -and
            $manifest -notcontains $_ -and
            $standalone[$_] -ceq $companion[$_]
        } |
        Sort-Object
)

if (-not $Quiet) {
    Write-Host (
        "Shared parity: {0} manifest functions identical across both trees ({1} names shared in total)." -f
        $manifest.Count,
        @($standalone.Keys | Where-Object { $companion.ContainsKey($_) }).Count)
    if ($candidates.Count -gt 0) {
        Write-Host (
            "  Now identical and not yet in SHARED_FUNCTIONS.txt: " +
            ($candidates -join ", "))
    }
}
