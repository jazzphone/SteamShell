#!/usr/bin/env python3
"""Replays the structural half of Validate-Common.ps1 without Windows.

WHY THIS EXISTS

  "A validator that is not run is not a validator." Four assertions in the
  0.1.9 pass had gone stale, and one of them was actively wrong -- it demanded
  the Quick Menu be rounded BEFORE it is revealed, which is the exact ordering
  that clipped the menu on a 4K display. Had the build been run, that assertion
  would have failed the fix that repaired the bug. The regex checks have been
  replayed in Python on the development machine ever since, but as ad-hoc
  scratch work that nobody could re-run. This is that practice, committed.

  It is NOT a second validator. It reproduces the structural checks in
  Validate-Common.ps1, and it REPLAYS -- rather than restates -- the ~895 regex
  assertions in Validate-SteamShell.ps1 and Validate-SteamShell-XFE.ps1, reading
  them out of those files at run time. There is one copy of every product rule
  and it is still the PowerShell one; this only fires it earlier.

  The replay was added after a consolidation pass broke four product assertions
  and the Windows run reported one, because Assert-True throws on the first.
  Both -match and -notmatch are replayed: the rule that mattered most was a
  -notmatch saying the companion has no desktop mode, and checking only -match
  would have missed it entirely.

THE ENCODING TRAP, WHICH THIS FILE IS ON THE WRONG SIDE OF BY DEFAULT

  Validate-Common.ps1 documents it at length and names this script's situation
  exactly: "decode the sources as cp1252 and match case-INSENSITIVELY, or the
  replay reports failures that do not exist."

  Windows PowerShell's Get-Content decodes a BOM-less file as ANSI, so every
  assertion containing a non-ASCII character -- the `PRESET | ... FPS` row text
  is the one to remember -- passes because the validator script and the
  AutoHotkey source are mis-decoded the SAME way. Reading either as UTF-8 here
  breaks the symmetry and invents failures. Hence CP1252 below, and hence the
  case-insensitive comparisons: AutoHotkey identifiers are case-insensitive and
  PowerShell's -match is too, so a case-sensitive replay disagrees with the
  build for reasons that have nothing to do with the code.

Run:  python3 Replay-Validation.py            (from anywhere)
      python3 Replay-Validation.py --dump     fingerprint scores, for the
                                              cross-check described below
Exit: 0 clean, 1 on failure, matching the PowerShell harness.

KEEPING THE TWO HARNESSES HONEST

  Get-AhkCallFingerprint / Get-SequenceSimilarity in Validate-Common.ps1 and
  fingerprint() / similarity() here must compute the SAME number. A gate the two
  disagree about is worse than no gate: the build would pass on Windows and fail
  on the development machine, or the reverse, and the first instinct would be to
  loosen whichever one complained.

  Both implement 2*LCS/(len+len) longhand for that reason -- no difflib, no
  library -- and both read DllCall targets from the raw line before string
  literals are blanked, because the target IS a string literal. `--dump` prints
  the per-function scores so the two can be diffed after any change to either.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent

# Windows PowerShell's view of a BOM-less file, reproduced byte for byte.
#
# The sources are valid UTF-8 and contain curly quotes in comments, so cp1252
# turns a `"` into three mojibake characters -- and mangles the validator's own
# patterns the same way, which is why the assertions pass. Reproducing that
# requires cp1252, but Python's codec is STRICTER than .NET's: cp1252 leaves
# 0x81/0x8D/0x8F/0x90/0x9D undefined and Python raises on them, while .NET's
# code page 1252 maps each to the C1 control of the same value. 0x9D is the
# third byte of a curly close-quote, so a strict decode dies on the first one it
# meets. Filling those five slots is the difference between a faithful replay
# and no replay at all.
_TABLE = "".join(
    bytes([b]).decode("cp1252") if b not in (0x81, 0x8D, 0x8F, 0x90, 0x9D) else chr(b)
    for b in range(256)
)


def decode_like_powershell(raw):
    return raw.decode("latin-1").translate(str.maketrans(
        "".join(chr(b) for b in range(256)), _TABLE))

# Which files each program actually compiles. A call that resolves in neither is
# a LOAD-time failure in AutoHotkey, not a run-time one -- the script fails to
# parse, /Validate reports it in a modal dialog, and a harness waiting on the
# process hangs instead of failing. A hang is the worst failure mode a check can
# have, which is why this is enumerated rather than assumed.
COMPILES = {
    "SteamShell.ahk": ["SteamShell.ahk", "SteamShell-Shared.ahk", "SteamShell-Common.ahk"],
    "SteamShell-XFE.ahk": ["SteamShell-XFE.ahk", "SteamShell-Shared.ahk", "SteamShell-Common.ahk"],
    "SteamShell-Helper.ahk": ["SteamShell-Helper.ahk", "SteamShell-Common.ahk"],
}
ALL_FILES = [
    "SteamShell.ahk",
    "SteamShell-XFE.ahk",
    "SteamShell-Helper.ahk",
    "SteamShell-Shared.ahk",
    "SteamShell-Common.ahk",
]

# SteamShell-Common.ahk is compiled into the one binary that runs with a High
# integrity token. Nothing in it may reach outside itself except this.
COMMON_SEAM_ALLOWED = {"logline"}

FAILURES = []


def fail(message):
    FAILURES.append(message)


def read_source(name):
    return decode_like_powershell((ROOT / name).read_bytes())


def _effective_source(name, depth=0):
    """#Include inlined, the way Get-EffectiveSource does it.

    The product assertions run against this, not against the tree file: both
    trees compile SteamShell-Shared.ahk in, so reading a tree on its own would
    silently pass every assertion about a function that has moved out of it --
    which is the failure the whole validator exists to prevent."""
    if depth > 8:
        raise RuntimeError(f"#Include nesting is too deep at '{name}'")
    text = read_source(name)
    while True:
        m = re.search(r"(?m)^[ \t]*#Include[ \t]+(?:\*i[ \t]+)?(.+?)[ \t]*\r?$", text)
        if not m:
            return text
        text = (text[:m.start()]
                + _effective_source(m.group(1).strip('"'), depth + 1)
                + text[m.end():])


def _strip_ps_comment(line):
    """A PowerShell line comment, but only where '#' is outside a quote.

    Blanket `#.*$` removal corrupts the very assertions being replayed: the
    helper rules match on '#NoTrayIcon', '#Include' and '#Requires', which are
    AutoHotkey directives written inside single-quoted regex literals. Cutting
    at the '#' left a dangling opening quote, the pattern scanner ran on into
    the following lines, and the result was a reported failure whose pattern
    printed as blank. Same over-aggressive stripping that made a comment
    mentioning SettingsLayout() look like a call to it.
    """
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1] != "`"):
            return line[:i]
    return line


def strip_comments(line):
    """Comments only. A ';' inside a string literal is not a comment, and neither
    is one escaped as `; -- both appear in these sources."""
    line = re.sub(r'"(?:[^"`]|`.)*"', '""', line)
    return re.sub(r"(?<!`);.*$", "", line)


def strip_code_noise(text):
    """Comments and string bodies removed, for scans that look for CALLS.

    Without this the reachability check reads a function NAMED in a comment as a
    call to it, and reports a load-time failure that does not exist -- which is
    how this harness first accused SteamShell.ahk of calling SettingsLayout(),
    a name that appears there only in the sentence explaining that the companion
    computes it. Two false alarms of that kind and nobody runs the check again.
    """
    return "\n".join(strip_comments(line) for line in text.split("\n"))


def function_list(text):
    """Every top-level definition, in order, as (name, line, body).

    Returned as a LIST rather than a map so duplicates survive to be counted. A
    duplicate definition silently wins over the earlier one, so it has to be
    detected here -- and it cannot be detected by grepping for '^Name(', because
    a column-zero CALL in the auto-execute section matches that too. There are
    fourteen such calls across the two trees, LoadSettings() at SteamShell.ahk
    line 18993 among them; counting those as definitions reported every one of
    them as a duplicate of the real thing.
    """
    return _parse(text)


def function_map(text):
    """Every top-level function as name -> (line, body).

    Mirrors Get-AhkFunctionMap, including the two things that parser learned the
    hard way: headers may wrap across up to eight lines (seven real definitions
    do, among them CreateProcessWithStandardToken and LaunchInteractiveApp --
    the privilege boundary was the least-checked part of the tree), and a
    column-zero CALL in the auto-execute section is not a definition. The only
    thing that tells them apart is that a definition's balanced header is
    followed by '{'.
    """
    return {name: (line, body) for name, line, body in _parse(text)}


def _parse(text):
    lines = text.split("\n")
    out = []
    i = 0
    while i < len(lines):
        start = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\(", lines[i])
        if not start:
            i += 1
            continue
        scan = i
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*\([^\r\n{}]*\)\s*\{\s*$", lines[i]):
            header = ""
            balanced = False
            while scan < len(lines) and (scan - i) <= 8:
                header += lines[scan] if scan == i else " " + lines[scan].strip()
                bare = strip_comments(header)
                if bare.count("(") - bare.count(")") <= 0:
                    balanced = True
                    break
                scan += 1
            if not (balanced and re.search(r"\)\s*\{\s*$", header)):
                i += 1
                continue
        body = lines[i:scan + 1]
        cursor = scan + 1
        closed = False
        while cursor < len(lines):
            body.append(lines[cursor])
            # A header at column zero is the whole project's convention, so the
            # closing brace at column zero is too. Staying this dumb is what
            # keeps the parser from disagreeing with a human reading the text.
            if lines[cursor] == "}":
                closed = True
                break
            cursor += 1
        if closed:
            out.append((start.group(1).lower(), i + 1, body))
            i = cursor + 1
            continue
        i += 1
    return out


def top_level_globals(text):
    """Super-globals: `global X := ...` at depth zero, which AutoHotkey makes
    visible for read AND write inside every function without redeclaration. The
    in-function `global` lines are documentation, not requirement -- which is
    exactly why they are allowed to go stale, and why Phase 3 asserts them."""
    return _declared_names(text, r"^global\s+(.*)")


def in_function_globals(text):
    return _declared_names(text, r"^\s+global\s+(.*)")


def _declared_names(text, pattern):
    """Comments stripped BEFORE splitting on commas.

    Splitting first meant a trailing comment that happened to contain a comma
    contributed its words as declared globals -- `global X := 80 ; min ms, per
    tick` yielded a global named `tick`. Harmless in the cross-tree check, which
    only asks whether a name is declared SOMEWHERE, and not harmless at all in
    the completeness check, which asks whether a block lists everything it
    touches and would have demanded three names that do not exist."""
    names = set()
    for line in text.split("\n"):
        m = re.match(pattern, strip_comments(line))
        if not m:
            continue
        for decl in m.group(1).split(","):
            n = re.match(r"\s*([A-Za-z_]\w*)", decl)
            if n:
                names.add(n.group(1).lower())
    return names


def fingerprint(body):
    """A naming- and comment-blind signature: the ordered sequence of calls the
    function makes, plus its DllCall targets.

    THIS IS THE POINT OF THE WHOLE FILE. Text similarity cannot see semantic
    duplication in this codebase, because text is precisely what gets changed
    when a copy is tidied: rename a parameter, rewrap a DllCall, swap a switch
    for a Map. Measured on the 67 functions defined in both trees, a text diff
    scored ControllerBindingPretty at 0.26 and GetLastLines at 0.49 -- and both
    have an IDENTICAL call sequence. Thirty-four such pairs were being read as
    intentional divergence.
    """
    seq = []
    for line in body[1:]:
        s = strip_comments(line)
        for m in re.finditer(r'DllCall\(\s*"([^"]+)"', line):
            seq.append("dll:" + m.group(1).split("\\")[-1].lower())
        s = re.sub(r"DllCall\([^)]*", "", s)
        for m in re.finditer(r'(?<![.\w"])([A-Z][A-Za-z0-9_]{3,})\s*\(', s):
            if m.group(1) != "DllCall":
                seq.append(m.group(1).lower())
    return seq


def similarity(a, b):
    """2*LCS/(len+len). Implemented longhand rather than with difflib so the
    PowerShell side can compute the identical number -- a gate the two harnesses
    disagree about is worse than no gate."""
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0]
        for j, y in enumerate(b):
            cur.append(prev[j] + 1 if x == y else max(cur[j], prev[j + 1]))
        prev = cur
    return 2.0 * prev[len(b)] / (len(a) + len(b))


def is_subsequence(small, big):
    it = iter(big)
    return all(x in it for x in small)


def read_manifest(name):
    path = ROOT / name
    if not path.exists():
        fail(f"{name} is missing; it is the manifest the parity check enforces.")
        return set()
    return {
        line.strip().lower()
        for line in decode_like_powershell(path.read_bytes()).split("\n")
        if line.strip() and not line.strip().startswith("#")
    }


def read_divergent():
    """Names allowed to differ between the trees, with the reason recorded beside
    each. Format: `Name: why it is allowed to differ`. An entry with no reason is
    itself a failure -- the reason is the whole value of the file."""
    path = ROOT / "DIVERGENT_FUNCTIONS.txt"
    if not path.exists():
        return {}
    out = {}
    for line in decode_like_powershell(path.read_bytes()).split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, _, reason = line.partition(":")
        out[name.strip().lower()] = reason.strip()
    return out


def main():
    sources = {name: read_source(name) for name in ALL_FILES}
    maps = {name: function_map(text) for name, text in sources.items()}

    # ---- duplicate definitions -------------------------------------------
    # A duplicate silently wins over the earlier one.
    for name, text in sources.items():
        seen = {}
        for fn, line, _ in function_list(text):
            seen.setdefault(fn, []).append(line)
        for fn, lines_at in seen.items():
            if len(lines_at) > 1:
                fail(f"{name} defines '{fn}' {len(lines_at)} times "
                     f"(lines {', '.join(str(n) for n in lines_at)}); "
                     "the later one silently wins.")

    # ---- manifests match their files -------------------------------------
    # Who actually SEES each shared file decides what counts as shadowing.
    # SteamShell-Helper.ahk deliberately does not #Include SteamShell-Shared.ahk
    # -- Shared orchestrates RTSS and the Quick Menu and reaches into the trees,
    # so including it would not compile -- which means a helper copy of a shared
    # function shadows nothing. It is still duplication worth reporting, but
    # calling it a shadow sends the reader looking for a bug that is not there.
    for manifest_name, source_name, shadow_scope in (
        ("SHARED_FUNCTIONS.txt", "SteamShell-Shared.ahk",
         ["SteamShell.ahk", "SteamShell-XFE.ahk"]),
        ("COMMON_FUNCTIONS.txt", "SteamShell-Common.ahk",
         ["SteamShell.ahk", "SteamShell-XFE.ahk", "SteamShell-Helper.ahk",
          "SteamShell-Shared.ahk"]),
    ):
        manifest = read_manifest(manifest_name)
        defined = set(maps[source_name])
        for missing in sorted(manifest - defined):
            fail(f"{manifest_name} lists '{missing}', which {source_name} does not define.")
        for unlisted in sorted(defined - manifest):
            fail(f"{source_name} defines '{unlisted}', which {manifest_name} does not list. "
                 "Add it in the same commit.")
        # A copy pasted back into a tree silently shadows the shared one.
        for other in shadow_scope:
            for shadowed in sorted(manifest & set(maps[other])):
                fail(f"'{shadowed}' is listed in {manifest_name} but also defined in "
                     f"{other}, which compiles {source_name} and so shadows it.")
        for other in set(ALL_FILES) - set(shadow_scope) - {source_name}:
            for duplicated in sorted(manifest & set(maps[other])):
                # A recorded wrapper is a duplicated NAME, not a duplicated
                # implementation; the reason is in DIVERGENT_FUNCTIONS.txt.
                if duplicated in read_divergent():
                    continue
                fail(f"'{duplicated}' is listed in {manifest_name} and defined again in "
                     f"{other}. That file does not compile {source_name}, so this is a "
                     "second copy free to drift, not a shadow.")

    # ---- Common's seam ----------------------------------------------------
    common_defined = set(maps["SteamShell-Common.ahk"])
    everything_else = set()
    for other in ALL_FILES:
        if other != "SteamShell-Common.ahk":
            everything_else |= set(maps[other])
    called = set()
    for line in sources["SteamShell-Common.ahk"].split("\n"):
        for m in re.finditer(r"(?<![.\w])([A-Za-z_]\w*)\s*\(", strip_comments(line)):
            called.add(m.group(1).lower())
    for leak in sorted((called & everything_else) - common_defined - COMMON_SEAM_ALLOWED):
        fail(f"SteamShell-Common.ahk calls '{leak}', which is not on its seam allowlist "
             f"({', '.join(sorted(COMMON_SEAM_ALLOWED))}). Move the callee in, pass the "
             "value as a parameter, or widen the allowlist deliberately.")
    for required in sorted(COMMON_SEAM_ALLOWED):
        for program in COMPILES:
            if required not in maps[program]:
                fail(f"{program} does not define '{required}', which SteamShell-Common.ahk "
                     "depends on. AutoHotkey resolves that at load time, so it would not start.")

    # ---- cross-tree reachability -----------------------------------------
    for program, included in COMPILES.items():
        reachable = set()
        call_text = ""
        for f in included:
            reachable |= set(maps[f])
            call_text += strip_code_noise(sources[f]) + "\n"
        for f in ALL_FILES:
            if f in included:
                continue
            for name in maps[f]:
                if name in reachable:
                    continue
                if re.search(r"(?<![.\w])" + re.escape(name) + r"\s*\(", call_text, re.I):
                    fail(f"{program} calls '{name}', defined only in {f} and not compiled "
                         "into it. AutoHotkey resolves that at LOAD time.")
                # A callback is passed by NAME, with no parentheses:
                #   btnOk.OnEvent("Click", RecordShortcutChord_Accept)
                #   SetTimer(PollController, 16)
                # The pattern above cannot see those, and neither could the
                # PowerShell check it mirrors. That is how a shared function
                # referencing standalone's handler name shipped into the
                # companion, where AutoHotkey read the name as a local variable
                # that is never assigned and warned at load. A callback that
                # silently resolves to nothing is worse than a missing call: the
                # program starts, and one button does nothing.
                elif (re.search(r"(?<![.\w$])" + re.escape(name) + r"(?![\w(])",
                                call_text, re.I)
                      # ...unless it is ASSIGNED somewhere in the compiled set, in
                      # which case it is an ordinary local that happens to share a
                      # name with a function in the other tree. AutoHotkey
                      # identifiers are case-insensitive, so standalone's local
                      # `settingsPrimaryActive` collides with the companion's
                      # SettingsPrimaryActive(). A callback reference is never
                      # assigned to; that is what tells the two apart.
                      and not re.search(r"(?<![.\w])" + re.escape(name)
                                        + r"\s*(?::=|\+=|-=|\.=)", call_text, re.I)):
                    fail(f"{program} references '{name}' as a callback, and it is defined "
                         f"only in {f}. AutoHotkey reads the name as an unassigned local, "
                         "so the handler is silently never wired up.")

    # ---- the Shared seam, kept in step with the PowerShell allowlist ------
    #
    # $sharedSeamAllowed in Validate-Common.ps1 is a hand-maintained list, and
    # consolidating a seam function INTO the shared file makes its entry wrong in
    # a way only Windows would notice: the entry asserts the name is defined in
    # both trees, and it no longer is. Five entries went stale exactly that way in
    # one afternoon. Deriving the real seam here and comparing keeps the list
    # honest on the machine where the edit happens.
    shared_defs = set(maps["SteamShell-Shared.ahk"])
    tree_defs = (set(maps["SteamShell.ahk"]) | set(maps["SteamShell-XFE.ahk"])
                 | set(maps["SteamShell-Helper.ahk"]))
    shared_calls = set()
    for line in strip_code_noise(sources["SteamShell-Shared.ahk"]).split("\n"):
        for m in re.finditer(r"(?<![.\w])([A-Za-z_]\w*)\s*\(", line):
            shared_calls.add(m.group(1).lower())
    actual_seam = (shared_calls & tree_defs) - shared_defs - set(maps["SteamShell-Common.ahk"])
    ps = (ROOT / "Validate-Common.ps1").read_text(encoding="utf-8", errors="replace")
    block = re.search(r"\$sharedSeamAllowed = @\((.*?)\)", ps, re.S)
    if block:
        listed = {n.lower() for n in re.findall(r'"([A-Za-z_]\w*)"', block.group(1))}
        for extra in sorted(listed - actual_seam):
            fail(f"$sharedSeamAllowed in Validate-Common.ps1 lists '{extra}', which "
                 "SteamShell-Shared.ahk no longer calls out to. The entry asserts it is "
                 "defined in both trees; remove it.")
        for missing in sorted(actual_seam - listed):
            fail(f"SteamShell-Shared.ahk calls '{missing}' in a tree, and "
                 "$sharedSeamAllowed does not list it. Widening the seam is meant to be "
                 "a decision somebody makes.")

    # ---- globals Shared uses must exist in both trees ---------------------
    shared_globals = in_function_globals(sources["SteamShell-Shared.ahk"])
    for tree in ("SteamShell.ahk", "SteamShell-XFE.ahk"):
        declared = top_level_globals(sources[tree]) | in_function_globals(sources[tree])
        for missing in sorted(shared_globals - declared):
            fail(f"SteamShell-Shared.ahk references global '{missing}', which {tree} never "
                 "declares. Reading it before assignment throws at run time.")

    # ---- global declaration blocks must be complete ----------------------
    #
    # Every name here is a SUPER-GLOBAL -- declared at depth zero, which makes it
    # readable and writable inside every function with no declaration at all. The
    # ~1,100 in-function `global` lines are therefore documentation, not a
    # requirement, and nothing checked them, so they were free to lie. They did:
    # WindowEngineScoreWeights declared nine and read a tenth.
    #
    # The choice was to delete them or to make them true. They are kept, because
    # they are the only statement of what state a function touches in a codebase
    # with 600-odd of them -- but an unchecked 1,100-line claim is worth less than
    # no claim, so this is what makes it worth keeping.
    for tree in ("SteamShell.ahk", "SteamShell-XFE.ahk"):
        supers = top_level_globals(sources[tree])
        for name, line, body in function_list(sources[tree]):
            declared = _declared_names("\n".join(body), r"^\s+global\s+(.*)")
            if not declared:
                continue
            used = set()
            for l in body[1:]:
                for m in re.finditer(r"\b([A-Za-z_]\w*)\b", strip_comments(l)):
                    if m.group(1).lower() in supers:
                        used.add(m.group(1).lower())
            missing = sorted(used - declared)
            if missing:
                fail(f"{tree}:{line} {name}() declares a global block that omits "
                     f"{', '.join(missing)}. The block is the only record of what "
                     "state the function touches; an incomplete one is worse than none.")

    # ---- the fingerprint gate --------------------------------------------
    divergent = read_divergent()
    a, b = maps["SteamShell.ahk"], maps["SteamShell-XFE.ahk"]
    flagged = []
    for name in sorted(set(a) & set(b)):
        fa, fb = fingerprint(a[name][1]), fingerprint(b[name][1])
        score = similarity(fa, fb)
        subset = bool(fa and fb and fa != fb and
                      (is_subsequence(fa, fb) or is_subsequence(fb, fa)))
        if score >= 0.75 or subset:
            flagged.append((name, score, subset, a[name][0], b[name][0]))
    for name, score, subset, la, lb in flagged:
        if name not in divergent:
            kind = "one is a strict subset of the other" if subset else f"call-sequence similarity {score:.2f}"
            fail(f"'{name}' is defined in both trees and {kind} "
                 f"(SteamShell.ahk:{la}, SteamShell-XFE.ahk:{lb}). Share it, or add it to "
                 "DIVERGENT_FUNCTIONS.txt with the reason it must differ.")
        elif not divergent[name]:
            fail(f"DIVERGENT_FUNCTIONS.txt lists '{name}' with no reason. The reason is the "
                 "entire value of that file.")
    # An entry also earns its place by covering a Helper/Shared name collision,
    # which the gate above never sees: it only compares the two TREES.
    helper_wrappers = set(maps["SteamShell-Helper.ahk"]) & set(maps["SteamShell-Shared.ahk"])
    stale = sorted(set(divergent) - {n for n, *_ in flagged} - helper_wrappers)
    for name in stale:
        if name in set(a) & set(b):
            fail(f"DIVERGENT_FUNCTIONS.txt lists '{name}', but the two copies no longer "
                 "diverge. Remove the entry.")
        else:
            fail(f"DIVERGENT_FUNCTIONS.txt lists '{name}', which is no longer defined in both "
                 "trees. Remove the entry.")

    # ---- replay the product validators' regex assertions ------------------
    #
    # The structural checks above are mechanism. These are the PRODUCT rules, and
    # they are the ones a consolidation actually breaks: they pin the shape of
    # specific functions, and moving a function is exactly what changes its
    # shape. Four of them broke in one pass and only the first was visible,
    # because Assert-True throws.
    #
    # Two are worth naming, because they are opposite lessons:
    #
    #   The Quick Menu scale assertion pinned `scale := width / QuickMenuWidth()`
    #   as a literal, so adding a divide-by-zero guard read as a regression. That
    #   assertion described a spelling, not an invariant.
    #
    #   The companion's `-notmatch 'EnableDesktopAutoMouseMode'` is the opposite:
    #   an architectural rule saying the companion has no desktop mode, written
    #   so that reintroducing it "is a decision someone has to take
    #   deliberately". Sharing a function required declaring that name in the
    #   companion. The rule was right and the change was wrong.
    #
    # Both halves are replayed, because only checking -match would have missed
    # the second entirely.
    replayed = 0
    for vpath, spath in (("Validate-SteamShell.ps1", "SteamShell.ahk"),
                         ("Validate-SteamShell-XFE.ps1", "SteamShell-XFE.ahk")):
        if not (ROOT / vpath).exists():
            continue
        source = _effective_source(spath)
        # Comments stripped FIRST. A validator comment quoting the assertion it
        # replaced -- "this used to read $source -notmatch 'HighestAvailable'" --
        # is prose about a rule, not the rule, and reading it as one reports a
        # violation that does not exist. The comment being misread here is itself
        # explaining that same trap.
        vtext = "\n".join(
            _strip_ps_comment(line)
            for line in decode_like_powershell((ROOT / vpath).read_bytes()).split("\n"))
        # $rawSource as well as $source, EACH AGAINST THE TEXT IT NAMES.
        #
        # $rawSource is the tree file without its #Includes resolved, and it
        # exists so a -notmatch can be scoped to the tree: '<LogonTrigger>' and
        # '<RunLevel>HighestAvailable</RunLevel>' are forbidden in the tree and
        # perfectly legal in SteamShell-Common.ahk, which builds the task XML.
        # Replaying a tree-scoped -notmatch against the effective source reports
        # five violations that do not exist, and a harness that cries wolf stops
        # being run -- which is the failure this whole file was written against.
        #
        # Replaying only $source was the other error: two -match assertions read
        # $rawSource, so moving the RTSS state-report functions into the shared
        # file broke them invisibly here and Windows found them instead.
        # Every subject the validators assert against, each mapped to the text it
        # names. Three of these were learned one Windows round-trip at a time --
        # $source, then $rawSource, then $helperSource -- so the unknown-subject
        # report below exists to make the fourth one visible here instead.
        texts = {
            "source": source,
            "rawsource": read_source(spath),
            "helpersource": read_source("SteamShell-Helper.ahk"),
            "helpereffective": _effective_source("SteamShell-Helper.ahk"),
            "sharedsource": read_source("SteamShell-Shared.ahk"),
            "commonsource": read_source("SteamShell-Common.ahk"),
        }
        for subject_name in sorted(set(
                m.group(1).lower() for m in re.finditer(
                    r"\$(\w*[Ss]ource\w*)\s+-(?:not)?match", vtext))):
            if subject_name not in texts:
                fail(f"{vpath} asserts against ${subject_name}, which "
                     "Replay-Validation.py does not know how to read. Every rule "
                     "written against it is going unchecked here. Add it to `texts`.")
        for op, want in (("-match", True), ("-notmatch", False)):
            for m in re.finditer(r"\$(\w*[Ss]ource\w*)\s+" + re.escape(op)
                                 + r"\s+((?:\s*(?:\+\s*)?'(?:[^']|'')*'\s*)+)", vtext):
                if m.group(1).lower() not in texts:
                    continue
                subject = texts[m.group(1).lower()]
                pattern = "".join(f.replace("''", "'")
                                  for f in re.findall(r"'((?:[^']|'')*)'", m.group(2)))
                line = vtext[:m.start()].count("\n") + 1
                try:
                    hit = bool(re.search(pattern, subject, re.I))
                except re.error:
                    continue  # .NET-only construct; the build will judge it
                replayed += 1
                if hit != want:
                    fail(f"{vpath}:{line} asserts {op} and it is no longer satisfied: "
                         f"{pattern[:110]}")

    if "--dump" in sys.argv:
        print(f"{'function':38s} {'score':>6}  subset")
        for name in sorted(set(a) & set(b)):
            fa, fb = fingerprint(a[name][1]), fingerprint(b[name][1])
            sub = bool(fa and fb and fa != fb and
                       (is_subsequence(fa, fb) or is_subsequence(fb, fa)))
            print(f"{name:38s} {similarity(fa, fb):6.2f}  {'yes' if sub else ''}")
        return 0

    # ---- report -----------------------------------------------------------
    both = len(set(a) & set(b))
    print(f"  files parsed      : {len(ALL_FILES)}")
    print(f"  functions         : " + ", ".join(
        f"{n.replace('SteamShell', 'SS').replace('.ahk', '')}={len(m)}" for n, m in maps.items()))
    print(f"  defined in both   : {both}")
    print(f"  fingerprint flags : {len(flagged)} ({len(divergent)} allowlisted)")
    print(f"  product assertions: {replayed} replayed from the two validators")
    if FAILURES:
        print(f"\nFAILED ({len(FAILURES)}):\n")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("\nAll structural checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
