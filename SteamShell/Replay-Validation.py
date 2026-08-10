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

import collections
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


def read_shared_seam(ps_text):
    """The $sharedSeamAllowed names and the count asserted beside them.

    ONE parser for both readers below, and bounded by the NAME that follows the
    list rather than by a closing parenthesis.

    `@\\((.*?)\\)` stops at the first ")" in the block, which for as long as the
    comments in that list happened to contain none read the whole thing. Adding
    a comment that illustrates a callback seam --

        OnEvent("Click", ExportDiagnosticBundle)

    -- silently truncated the list to its first two entries, and every name
    after the truncation was then reported as an unlisted seam leak. Eighteen
    failures from a comment. $sharedSeamExpectedCount is the real terminator and
    cannot appear inside the list, so it is what bounds the scan.

    ANCHORED TO COLUMN ZERO, because the comment above the list quotes both
    spellings verbatim -- "keep the literal `$sharedSeamAllowed = @(` and
    `$sharedSeamExpectedCount = N` spellings" -- and an unanchored search finds
    the COMMENT first. That match only ever looked right because the real list
    happened to contain no ")" for the old pattern to stop at; the assignment is
    the only one of the two at column zero, so that is what is matched.

    Returns (names, expected) with names lowercased; expected is None when the
    literal is absent.
    """
    block = re.search(
        r"(?m)^\$sharedSeamAllowed = @\((.*?)^\$sharedSeamExpectedCount",
        ps_text, re.S)
    if not block:
        return set(), None
    body = re.sub(r"(?m)^\s*#.*$", "", block.group(1))
    names = {n.lower() for n in re.findall(r'"([A-Za-z_]\w*)"', body)}
    expected = re.search(r"(?m)^\$sharedSeamExpectedCount = (\d+)", ps_text)
    return names, (int(expected.group(1)) if expected else None)


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


_DIVERGENT_CACHE = []


def read_divergent():
    """Names allowed to differ between the trees, with the reason recorded beside
    each. Format: `Name: why it is allowed to differ`. An entry with no reason is
    itself a failure -- the reason is the whole value of the file.

    A name listed TWICE is also a failure. This is not tidiness. Five names once
    carried a PENDING reason under one heading and a contradictory PERMANENT one
    under another, and because the entries land in a dict the later silently won.
    The PENDING half was the file's entire consolidation worklist, and no harness
    could see it. A file whose stated purpose is to make a count go down cannot
    hold two answers for the same name."""
    # Parsed once: one call site sits inside a loop, and a file-level fault
    # reported once per iteration reads as many faults instead of one.
    if _DIVERGENT_CACHE:
        return _DIVERGENT_CACHE[0]
    path = ROOT / "DIVERGENT_FUNCTIONS.txt"
    if not path.exists():
        _DIVERGENT_CACHE.append({})
        return _DIVERGENT_CACHE[0]
    out = {}
    for line in decode_like_powershell(path.read_bytes()).split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, _, reason = line.partition(":")
        key = name.strip().lower()
        if key in out:
            fail(f"DIVERGENT_FUNCTIONS.txt lists '{name.strip()}' more than once. "
                 "Only the last entry counts, so the others are reasons no harness "
                 "reads. Keep one, and delete the entry entirely once the two "
                 "copies are merged.")
        out[key] = reason.strip()
    _DIVERGENT_CACHE.append(out)
    return out


def function_body(text, name):
    """The text between a function's braces, by name. Empty when undefined."""
    m = re.search(r"(?m)^" + re.escape(name) + r"\(", text)
    if not m:
        return ""
    i = text.index("{", m.end() - 1) + 1
    depth, j = 1, i
    while depth > 0 and j < len(text):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
        j += 1
    return text[i:j - 1]


def call_arguments(text, fname):
    """Every `fname(...)` call in text, arguments split on top-level commas.

    Regex alone is not enough here and the difference is not cosmetic. A first
    attempt matched `MenuRow\\(...\\)` with a non-greedy pattern and reported 18
    handlers as unreachable, every one of them a false alarm from a call that
    wrapped across lines or computed an argument inline. An assertion that cries
    wolf 18 times gets switched off, so this tracks quote state and paren depth
    and returns the arguments as written."""
    out = []
    for m in re.finditer(r"\b" + re.escape(fname) + r"\(", text):
        i, depth, j, in_string = m.end(), 1, m.end(), False
        while depth > 0 and j < len(text):
            c = text[j]
            if c == '"':
                in_string = not in_string
            elif not in_string:
                if c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1
            j += 1
        args, parts, depth, in_string, current = text[i:j - 1], [], 0, False, ""
        for c in args:
            if c == '"':
                in_string = not in_string
            if not in_string:
                if c in "([":
                    depth += 1
                elif c in ")]":
                    depth -= 1
                elif c == "," and depth == 0:
                    parts.append(current.strip())
                    current = ""
                    continue
            current += c
        parts.append(current.strip())
        out.append(parts)
    return out


def _string_literal(argument):
    argument = argument.strip()
    if len(argument) > 1 and argument[0] == '"' and argument[-1] == '"' \
            and '"' not in argument[1:-1]:
        return argument[1:-1]
    return None


def switch_case_labels(body):
    """Every string label in every `case` in a switch body, including the
    comma-separated multi-label form."""
    out = set()
    for m in re.findall(r"(?m)^\s*case\s+([^:\n]+):", body):
        out.update(re.findall(r'"([^"]+)"', m))
    return out


# Row ids whose behaviour is reached through a prefix rather than a case label.
# Each is checked with SubStr in the resolver, so the literal id never appears
# as a `case`.
ROW_ID_FAMILIES = ("layout:", "taskWindow:", "gamescore:", "toggle:", "page:",
                   "currentapp:")


def read_quickmenu_manifest():
    """QUICKMENU_ROWS.txt -- the Quick Menu's row inventory, per product.

    Format: `product id` per line, plus `product dynamic:name` for a handler
    reached through a variable rather than a literal row."""
    path = ROOT / "QUICKMENU_ROWS.txt"
    if not path.exists():
        fail("QUICKMENU_ROWS.txt is missing; it is the row inventory the Quick "
             "Menu check enforces.")
        return {}, {}
    rows, dynamic = {}, {}
    for line in decode_like_powershell(path.read_bytes()).split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        product, _, name = line.partition(" ")
        name = name.strip()
        if name.startswith("dynamic:"):
            dynamic.setdefault(product, set()).add(name[len("dynamic:"):])
        else:
            rows.setdefault(product, set()).add(name)
    return rows, dynamic


def check_quickmenu_rows(sources):
    """Every Quick Menu row reaches behaviour, and every behaviour has a row.

    The fingerprint gate cannot see this. The two trees build rows differently,
    which drags every QuickMenu* function below the 0.75 threshold, so the whole
    family sits unmeasured -- and a row whose handler is deleted does not fail
    to compile. It renders, selects, and does nothing.

    Two directions, because each catches a different mistake:
      - a row id with no handler is a dead row the user can select;
      - a handler with no row is a case kept alive after its row went away,
        which is what makes a switch grow without anyone deciding to.
    """
    manifest, dynamic = read_quickmenu_manifest()
    shared = sources["SteamShell-Shared.ahk"]
    inert = set(re.findall(
        r'"([^"]+)",\s*true', function_body(shared, "QuickMenuRowIsInert")))

    for product, filename, builder in (
            ("standalone", "SteamShell.ahk", "QuickMenuGetDefinitions"),
            ("xfe", "SteamShell-XFE.ahk", "QuickMenuGetRows")):
        text = sources[filename]
        rows_body = function_body(text, builder)
        if not rows_body:
            fail(f"{filename} defines no {builder}(); the Quick Menu row "
                 "inventory cannot be checked.")
            continue

        # The two builders spell a row differently and the extraction has to
        # respect that. Treating MenuRow's "first argument is the id" rule as
        # general read standalone's `Map("audio", ...)` grouping key as a row id.
        built, navigating = set(), set()
        for args in call_arguments(rows_body, "MenuRow"):
            if args:
                built.add(_string_literal(args[0]))
        for args in call_arguments(rows_body, "Map"):
            if len(args) > 1 and _string_literal(args[0]) == "id":
                row_id = _string_literal(args[1])
                built.add(row_id)
                # A row that declares "page" or "back" carries its own
                # navigation and needs no case at all. That is the point of the
                # field: sixteen ids used to reach two identical bodies.
                keys = {_string_literal(a) for a in args[0::2]}
                if row_id is not None and ({"page", "back"} & keys):
                    navigating.add(row_id)
        built = {r for r in built
                 if r is not None and not r.startswith(ROW_ID_FAMILIES)}

        # What each row states as its own value. A literal "" states nothing and
        # falls back to QuickMenuValue; anything else -- a literal or an
        # expression like QuickMenuSettingValueText(id) -- is the row answering
        # for itself.
        row_states_value = {}
        row_nav = {}
        for args in call_arguments(rows_body, "MenuRow"):
            if not args:
                continue
            row_id = _string_literal(args[0])
            if row_id is None:
                continue
            if len(args) < 3:
                row_states_value[row_id] = False
                continue
            literal = _string_literal(args[2])
            row_states_value[row_id] = not (literal is not None and literal == "")
            action = _string_literal(args[3]) if len(args) > 3 else None
            row_nav[row_id] = bool(action) and (
                action.startswith("page:") or action == "back")

        recorded = manifest.get(product, set())
        for gone in sorted(recorded - built):
            fail(f"{filename}: the Quick Menu row '{gone}' is in "
                 "QUICKMENU_ROWS.txt but no longer built. If that is "
                 "deliberate, delete the line in the same commit; a row that "
                 "vanishes silently is what this file exists to catch.")
        for added in sorted(built - recorded):
            fail(f"{filename}: the Quick Menu builds a row '{added}' that "
                 "QUICKMENU_ROWS.txt does not record. Add it, so the inventory "
                 "stays the list of rows that actually exist.")

        # Direction 0: every row has a VALUE mapping.
        #
        # Added because its absence cost a Windows build. Validate-SteamShell.ps1
        # has always checked this; the replay did not, so moving seven settings
        # cases out of QuickMenuValue and into the shared file looked green here
        # and failed there with "Quick Menu row has no value mapping:
        # qAccentColor".
        #
        # The shape of that bug is worth keeping in mind: the PowerShell check
        # slices QuickMenuValue's BODY out of the file, so an answer that moves
        # into SteamShell-Shared.ahk leaves the slice while never leaving
        # $source. Consolidation therefore reads as regression unless the check
        # is told where the answer went -- which is why the shared value
        # function is consulted here explicitly rather than by scanning
        # everything.
        #
        # The companion too, since QuickMenuRowValueText answers for both now.
        #
        # It resolved values ONLY the shell's way -- QuickMenuValue(row id) -- so
        # every companion row whose id has no case there rendered with an empty
        # value column. That was every "toggle:" settings row it builds: labels
        # with nothing beside them, on the page a user goes to in order to read
        # the current setting. Nothing about a blank column fails, and this check
        # existed for the shell and simply did not run for the companion.
        if (product == "xfe"):
            # Rows whose value column is deliberately empty: they DO something
            # rather than hold a setting. Listed rather than inferred, so a row
            # that loses its value by accident cannot hide among them -- the
            # shell's copy of this check names its four the same way.
            action_rows = {"back", "desktop", "restart", "shutdown", "sleep",
                           "exitApp", "returnShell", "overlayOn", "overlayOff",
                           "overlayToggle", "limiterOn", "limiterOff",
                           "limiterToggle", "rtssStart", "rtssSaveProfile",
                           "windowsSettings", "setControllerMappings"}
            # The companion carries navigation in the ACTION, not in a row field,
            # so its hub rows are not in `navigating`.
            answerable = switch_case_labels(function_body(text, "QuickMenuValue"))
            answerable |= switch_case_labels(
                function_body(shared, "QuickMenuSettingValueText"))
            answerable |= set(re.findall(
                r'"(\w+)",\s*Map\("section",', shared))
            for row_id, states_value in row_states_value.items():
                if states_value:
                    continue
                base = row_id[7:] if row_id.startswith("toggle:") else row_id
                if base in answerable or row_id in answerable:
                    continue
                if row_id in inert or row_id in navigating or row_id in action_rows:
                    continue
                if row_nav.get(row_id):
                    continue
                if row_id.startswith(ROW_ID_FAMILIES):
                    continue
                fail(f"{filename}: the Quick Menu row '{row_id}' renders no "
                     "value. It carries none of its own and QuickMenuValue has "
                     "no case for it, so the row shows a label and an empty "
                     "column.")

        # Standalone only. The companion resolves each row's value when it
        # builds the row, so there is no separate mapping to be missing.
        if (product == "standalone"):
            # Containment rather than case labels, matching the PowerShell
            # rule: not every answer in QuickMenuValue is a `case`. gameScoreBack
            # is an `if` with a comment explaining why it cannot be a back row,
            # and a labels-only version of this check reported it as missing.
            values_text = function_body(text, "QuickMenuValue")
            value_ids = switch_case_labels(
                function_body(shared, "QuickMenuSettingValueText"))
            value_ids |= set(re.findall(
                r'"(q\w+)",\s*Map\("section",', shared))
            # Rows whose value column is deliberately empty.
            value_ids |= {"desktop", "restart", "shutdown", "sleep"}
            for row in sorted(built):
                if f'"{row}"' in values_text:
                    continue
                if row in value_ids or row in navigating or row in inert:
                    continue
                if row.startswith(ROW_ID_FAMILIES):
                    continue
                fail(f"{filename}: the Quick Menu row '{row}' has no value "
                     "mapping. It would render with an empty value column. "
                     "Answer it in QuickMenuValue, in the shared "
                     "QuickMenuSettingValueText, or from QuickMenuToggleTable.")

        # Direction 1: every row reaches an ACTIVATE path.
        #
        # Deliberately not "reaches any handler". Coverage as an OR across the
        # value and activate switches passes a row that still shows its value
        # but no longer does anything when pressed -- which is exactly the
        # failure described above, and a first draft of this check let a deleted
        # activate case through because the value case was still there.
        handlers = switch_case_labels(function_body(text, "QuickMenuActivateSelected"))
        handlers |= switch_case_labels(function_body(text, "QuickMenuAdjustSelected"))
        # Actions both products implement identically live in Shared now, so a
        # row can reach its behaviour without either tree naming it.
        handlers |= switch_case_labels(
            function_body(shared, "QuickMenuActivateShared"))
        # The q* rows are reached by set membership, not by a case label.
        for fn in ("IsQuickMenuToggleSetting", "IsQuickMenuAdjustSetting"):
            handlers |= set(re.findall(r"[A-Za-z]\w*", function_body(text, fn)))
        # A row reaches its behaviour by one of two routes, and which one
        # depends on the tree. Standalone switches on the row's ID. The
        # companion carries an ACTION on the row and switches on that, so a
        # companion row is covered when its own action is handled -- not when
        # its id happens to appear somewhere.
        row_action = {}
        for args in call_arguments(rows_body, "MenuRow"):
            if args and len(args) > 3:
                row_id = _string_literal(args[0])
                if row_id is not None:
                    row_action[row_id] = _string_literal(args[3])
        row_actions = {a for a in row_action.values() if a}
        for row in sorted(built):
            if row in row_action:
                action = row_action[row]
                # None means the action is computed; the handler direction
                # below still pins whatever it resolves to.
                if action is None or action == "none" \
                        or action.startswith(ROW_ID_FAMILIES) or action in handlers:
                    continue
                fail(f"{filename}: the Quick Menu row '{row}' carries action "
                     f"'{action}', which no handler implements. It would render "
                     "and do nothing when selected.")
                continue
            if row in handlers or row in inert or row in navigating:
                continue
            fail(f"{filename}: the Quick Menu row '{row}' reaches no activate, "
                 "adjust or toggle handler and is not declared inert. It would "
                 "render and do nothing when selected. If it is display-only, "
                 "add it to QuickMenuRowIsInert so that is stated rather than "
                 "inferred from a missing case.")

        # Direction 2: every handler has a row. Dynamic ids are exempted by
        # name so the exemption is a decision, not a hole.
        allowed = built | inert | dynamic.get(product, set())
        for fn in ("QuickMenuActivateSelected", "QuickMenuAdjustSelected"):
            for label in sorted(switch_case_labels(function_body(text, fn))):
                if label.startswith(ROW_ID_FAMILIES) or label in allowed:
                    continue
                if label in row_actions:
                    continue
                fail(f"{filename}: {fn} handles '{label}', which no Quick Menu "
                     "row builds. Delete the case, or record it in "
                     "QUICKMENU_ROWS.txt as 'dynamic:' if a variable reaches it.")


# Keywords, plus the statements AutoHotkey allows without parentheses. A
# parenless `Sleep 200` or a bare `Loop` reads as an identifier to any scanner
# that only knows about expressions.
def _body_tokens(body):
    """A comment- and whitespace-blind token stream for a function body."""
    text = "\n".join(body) if isinstance(body, list) else body
    text = "\n".join(strip_comments(l) for l in text.split("\n"))
    return [tok for tok in re.findall(r"[A-Za-z_]\w*|[^\s\w]", text) if tok]


# Anchors: the things in a function body that MEAN something to this project --
# a Win32 export it calls, a string it puts on screen or in the log.
#
# Deliberately not a similarity metric. See check_cross_name_anchors.
CROSS_NAME_UBIQUITOUS_APIS = frozenset({
    "closehandle", "getlasterror", "getforegroundwindow", "iswindow", "getwindow",
})
# How many tree-only functions an anchor may appear in before it stops carrying
# information. Separate budgets because the two kinds have different densities:
# a Win32 export is rare and meaningful, a short string much less so.
CROSS_NAME_ANCHOR_BUDGET = {"api": 4, "str": 3}
# The shared anchors must also be this fraction of the LARGER function's anchor
# set. Without it, a table that names every settings key pairs with every small
# function that happens to name two of them -- XFE's DefaultSettings matched six
# unrelated shell functions that way. This is the only ratio in the check, and it
# is about how much of a function the evidence covers, not how alike two bodies
# are.
CROSS_NAME_ANCHOR_COVERAGE = 0.20


def _function_anchors(body):
    lines = [re.sub(r"(?<!`);.*$", "", l)
             for l in (body if isinstance(body, list) else body.split("\n"))]
    found = set()
    # Whole-body, because a DllCall's target routinely sits on the line after the
    # opening paren in these sources. A per-line scan misses those, and it missed
    # the one pair in this tree that a Win32 export identifies outright.
    for match in re.finditer(r'DllCall\(\s*"((?:[^"`]|`.)*)"', "\n".join(lines)):
        target = match.group(1).split("\\")[-1].lower()
        if target and target not in CROSS_NAME_UBIQUITOUS_APIS and not target.isdigit():
            found.add("api:" + target)
    # Strings per line, because an AutoHotkey literal cannot span one. Scanning
    # the joined body pairs the closing quote of one string with the opening
    # quote of the next and turns the CODE BETWEEN THEM into an anchor -- which
    # the first draft of this did, and it produced convincing nonsense.
    for line in lines:
        for match in re.finditer(r'"((?:[^"`\n]|`.)*)"', line):
            text = match.group(1)
            if len(text) >= 6 and re.search(r"[A-Za-z]", text):
                found.add("str:" + text.lower())
    return found


def check_cross_name_anchors(sources):
    """The same routine in both trees under two DIFFERENT names.

    KEPT IN STEP WITH Assert-CrossNameAnchors in Validate-Common.ps1.

    THIS REPLACES A CHECK THAT NEVER FOUND ANYTHING. The previous version scored
    call-sequence and body-token similarity between every tree-only pair and
    failed above two hand-set thresholds. Its record, from the file it feeds:
    the seven original pairs existed BEFORE it was written and it was fitted to
    them; the eighth is recorded there as "not found BY this check, and it could
    not have been"; the ninth -- the whole Task Switcher -- was found by grepping
    for a Quick Menu page constant; and four more surfaced only when someone who
    already knew the answer lowered its thresholds. It also lived in Python
    alone, so it never ran on Windows at all.

    That is not bad luck. Validate-Common.ps1's own header argues the point
    against the same-name gate: a low score is not evidence of intent, and two
    copies of one routine drift apart in structure as well as text, so the metric
    loses confidence exactly as the problem gets worse. A duplicate that has
    drifted is the only kind worth finding and the kind similarity is worst at --
    and thresholds with no principled value get tuned to whatever is already
    known.

    SO THIS ASKS A DIFFERENT QUESTION. Not "how alike are these two bodies" but
    "do these two functions share something that means something": a Win32 export
    they both call, a message they both put on screen, a log line they both
    write, an action name they both spell. Two functions that both DllCall
    GetProcessTimes and OpenProcess are doing one job, whatever they are called
    and however far their bodies have drifted.

    What it reports is EVIDENCE, not a number. "Both contain 'that window is no
    longer available'" can be judged in seconds; "0.80" cannot. It found the Task
    Switcher pair cold, on two of its own user-facing strings, and it finds the
    two duplicated DATA tables that the call-fingerprint approach is documented
    as structurally unable to see -- a pure-data function has no call sequence.

    ITS OWN LIMIT, stated because it is not the same as the old one: shared
    vocabulary is not proof of a duplicate. Two functions can both open a process
    handle and do unrelated things with it, and one such pair is recorded in
    CROSS_NAME_DUPLICATES.txt for exactly that reason. This produces candidates
    for a person to judge, and the allowlist is where the judgement goes.
    """
    accepted = {}
    path = ROOT / "CROSS_NAME_DUPLICATES.txt"
    if path.exists():
        for line in decode_like_powershell(path.read_bytes()).split("\n"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            pair, _, reason = line.partition(":")
            accepted[pair.strip().lower()] = reason.strip()

    a = function_map(sources["SteamShell.ahk"])
    b = function_map(sources["SteamShell-XFE.ahk"])
    shell = {n: _function_anchors(a[n][1]) for n in a if n not in b}
    companion = {n: _function_anchors(b[n][1]) for n in b if n not in a}

    seen = collections.Counter()
    for group in (shell, companion):
        for anchors in group.values():
            for anchor in anchors:
                seen[anchor] += 1

    def distinctive(anchors):
        return {x for x in anchors
                if seen[x] <= CROSS_NAME_ANCHOR_BUDGET[x[:3]]}

    shell = {n: distinctive(s) for n, s in shell.items()}
    companion = {n: distinctive(s) for n, s in companion.items()}

    queued = []
    for x in sorted(companion):
        for s in sorted(shell):
            shared = companion[x] & shell[s]
            if len(shared) < 2:
                continue
            if len(shared) < CROSS_NAME_ANCHOR_COVERAGE * max(
                    len(shell[s]), len(companion[x])):
                continue
            key = f"{x}={s}"
            if key in accepted:
                if not accepted[key]:
                    fail(f"CROSS_NAME_DUPLICATES.txt lists '{key}' with no reason. "
                         "The reason is the entire value of that file.")
                elif accepted[key].upper().startswith("QUEUED"):
                    queued.append(key)
                continue
            evidence = "; ".join(sorted(shared)[:4])
            fail(f"SteamShell-XFE.ahk's '{x}' and SteamShell.ahk's '{s}' share "
                 f"{len(shared)} distinctive anchors and may be one routine under "
                 f"two names ({evidence}). Give them one name and share it, or "
                 f"record the pair in CROSS_NAME_DUPLICATES.txt as '{key}: why' "
                 "with the reason they stay separate.")

    # QUEUED entries are debt, not decisions, and are counted so the allowlist
    # cannot quietly become the place work goes to be forgotten.
    if queued:
        print(f"  cross-name candidates: {len(queued)} recorded as QUEUED in "
              "CROSS_NAME_DUPLICATES.txt, awaiting a decision")


def check_schema_versions():
    """The settings schema version each program writes must equal the one it
    reads back.

    Not replayed from the validators, and that is the point. Standalone's rule
    compares two regex CAPTURES rather than matching a source, and the
    companion's matches against $sample with the version interpolated into a
    double-quoted pattern -- and this file only replays single-quoted literals
    asserted against a subject whose variable name contains "source". Both rules
    were therefore invisible here, and both were FAILING: two commits bumped the
    runtime version for the Game Detection settings and left the templates
    behind, so every check below reported green on a tree Windows rejected.

    A local harness that passes what the build fails is worse than no local
    harness, so this is checked directly rather than inferred."""
    standalone = read_source("SteamShell.ahk")
    runtime = re.search(
        r"(?m)^global CurrentSettingsSchemaVersion\s*:=\s*(\d+)\s*$", standalone)
    embedded = re.search(r"(?m)^SettingsSchemaVersion=(\d+)", standalone)
    sample = re.search(
        r"(?m)^SettingsSchemaVersion=(\d+)",
        decode_like_powershell((ROOT / "SteamShellSettings_SAMPLE.ini").read_bytes()))
    for label, found in (("runtime", runtime), ("embedded default", embedded),
                         ("sample INI", sample)):
        if not found:
            fail(f"SteamShell: the {label} settings schema version could not be read.")
    if runtime and embedded and sample:
        versions = {"runtime": runtime.group(1),
                    "embedded default": embedded.group(1),
                    "sample INI": sample.group(1)}
        if len(set(versions.values())) != 1:
            fail("SteamShell settings schema versions disagree: "
                 + ", ".join(f"{k}={v}" for k, v in versions.items())
                 + ". A fresh install writes the template's number and the "
                 "runtime then migrates it on every start.")

    companion = read_source("SteamShell-XFE.ahk")
    xruntime = re.search(r"(?m)^global SettingsSchemaVersion\s*:=\s*(\d+)$", companion)
    xdefault = re.search(r'"SettingsSchemaVersion",\s*(\d+)', companion)
    xsample = re.search(
        r"(?m)^SettingsSchemaVersion=(\d+)",
        decode_like_powershell((ROOT / "SteamShell-XFE_SAMPLE.ini").read_bytes()))
    for label, found in (("runtime", xruntime), ("DefaultSettings", xdefault),
                         ("sample INI", xsample)):
        if not found:
            fail(f"SteamShell-XFE: the {label} settings schema version could not be read.")
    if xruntime and xdefault and xsample:
        versions = {"runtime": xruntime.group(1),
                    "DefaultSettings": xdefault.group(1),
                    "sample INI": xsample.group(1)}
        if len(set(versions.values())) != 1:
            fail("SteamShell-XFE settings schema versions disagree: "
                 + ", ".join(f"{k}={v}" for k, v in versions.items()) + ".")


# PowerShell reads "$name:" inside a double-quoted string as a SCOPED variable
# reference -- $env:, $script:, $global: -- and "$tree:" names a scope that does
# not exist, so the file fails to PARSE. Not to run: to parse, which takes the
# whole validator with it and every assertion in it.
#
# This exists because that reached a build. The check it broke had been
# simulated here in Python and its logic counter-tested in both directions, and
# all of that verified SEMANTICS while the defect was SYNTAX. There is no
# PowerShell on the machine this replay runs on, so the parser cannot be the
# check -- but this particular error is mechanical, and a lint for it costs
# nothing.
#
# Scope prefixes are real syntax and are allowed by name, so the exemption is a
# list rather than a guess.
POWERSHELL_SCOPES = ("env", "script", "global", "local", "using", "private",
                     "variable", "function")


ASSERTION_SHAPE_KEYWORDS = {
    "static", "global", "local", "true", "false", "return", "else", "case",
    "while", "loop", "break", "continue", "catch", "finally", "throw", "then",
}


def _assertion_words(text):
    return {w for w in re.findall(r"[A-Za-z_]\w{3,}", text)
            if w.lower() not in ASSERTION_SHAPE_KEYWORDS}


def counted_pattern_literals(pattern):
    r"""What a counted pattern needs the subject to still contain.

    KEPT IN STEP WITH Get-CountedPatternLiterals in Validate-Common.ps1.

    Returns (required, alternations). `required` is every identifier the pattern
    names outside an alternation; `alternations` is one branch-set per `|` group,
    of which at least ONE branch must be present. The split matters: the shell's
    composed-read ban is `(?:ClampInt|ClampFloat)\(...IniReadS\(`, and
    ClampFloat is defined in SteamShell-Common.ahk but never called in
    SteamShell.ahk. Requiring every name would flag that branch as dead when it
    is deliberately forward-looking -- it bans a form nobody has written yet.

    Regex syntax is stripped first -- group prefixes, character classes, then
    escapes -- so `\s`, `[^\r\n]` and the like contribute nothing. Identifiers
    shorter than four characters are dropped with them, which is what makes a
    pure shape ban like `"x\d+ y\d+` name nothing and be skipped.
    """
    text = re.sub(r"\(\?[a-zA-Z]*[:=!<]*", "(", pattern)
    text = re.sub(r"\[(?:[^\]\\]|\\.)*\]", " ", text)
    text = re.sub(r"\\.", " ", text)
    groups, depth, start = [], 0, None
    for index, char in enumerate(text):
        if char == "(":
            if depth == 0:
                start = index
            depth += 1
        elif char == ")" and depth:
            depth -= 1
            if depth == 0:
                groups.append((start, index))
    alternations, outside, last = [], "", 0
    for start, end in groups:
        outside += text[last:start]
        last = end + 1
        inner = text[start + 1:end]
        if "|" in inner:
            branches = [_assertion_words(b) for b in inner.split("|")]
            # A branch naming nothing means the group imposes no requirement.
            if all(branches):
                alternations.append(branches)
        else:
            outside += " " + inner + " "
    outside += text[last:]
    return _assertion_words(outside), alternations


def check_validator_assertion_shapes():
    r"""Three ways an assertion stops checking anything without failing.

    KEPT IN STEP WITH Assert-ValidatorAssertionShapes in Validate-Common.ps1.

    When code moves, an assertion that NAMES the moved function fails, loudly,
    and gets fixed -- that case needs no help. The two that hurt are the ones
    that keep passing:

    UNBOUNDED FORWARD SCANS. `(?s)Name\(\)\s*\{.*?Thing` reads as "Thing appears
    inside Name", and it does not: `.*?` runs to the end of the file, so once
    Thing moves out of Name the pattern finds it in some later function and the
    assertion passes for the wrong reason. It happened here -- the shell's rule
    about untitled legacy surfaces kept passing after the exclusions moved into
    another function, and deleting the rule outright did not fail the build. The
    bounded form these validators already use elsewhere is
    `(?:(?!\n\})[\s\S])*?`, which stops at the end of the body.

    A pattern that terminates on `^}` bounds itself and is left alone: combining
    the two makes the body scan stop before the newline the `^}` needs.

    VACUOUS BODY CONSTRAINTS. `$helperSource -notmatch '(?sm)^Name\(\)\s*\{...X'`
    says "Name's body must not contain X" -- but if the subject does not define
    Name at all, it is true no matter what, forever. Asserting that a function is
    ABSENT is a different and legitimate thing, and reads as `-notmatch
    '(?m)^Name\('` with nothing after it; that form is not flagged.

    VACUOUS NEGATIVES. `$x = [regex]::Matches($subject, P)` with `$x.Count -eq 0`
    says "P must find nothing". Zero is also what P returns when it can no longer
    match anything at all, and the two are indistinguishable from the outside --
    a passing count of zero is the same green whether the defect is absent or the
    assertion has lost its subject. This one bit: $strayViewDownResets counts
    open-coded `previousViewDown := false` resets, a variable rename took the
    name out from under it, and it stayed green while checking nothing.

    So a counted-to-zero pattern must still be ANCHORED: every identifier it
    names outside an alternation has to appear in the subject, and each
    alternation needs at least one live branch. That is deliberately weak -- a
    substring is enough, no structure is required -- because the failure being
    caught is total disconnection, and a weak rule that never cries wolf is one
    that survives in a build gate.
    """
    trees = {
        "Validate-SteamShell.ps1": "SteamShell.ahk",
        "Validate-SteamShell-XFE.ps1": "SteamShell-XFE.ahk",
    }
    # An anchor is a FUNCTION DEFINITION, not a call: a name followed by a
    # parameter list and an opening brace.
    definition = re.compile(r"([A-Za-z_]\w*)\\\((?:\[\^\)\]\*|)\\\)\\s\*\\\{")
    for validator, tree in trees.items():
        text = (ROOT / validator).read_text(encoding="utf-8", errors="replace")
        # $source is the EFFECTIVE source -- the tree with its #Includes
        # inlined -- and $rawSource is the tree's own text. Handing the tree file
        # to both is a bug this check made about itself on its first run, and it
        # reported every Shared function as absent.
        effective = "\n".join((read_source(tree),
                               read_source("SteamShell-Common.ahk"),
                               read_source("SteamShell-Shared.ahk")))
        subjects = {
            "source": effective,
            "rawsource": read_source(tree),
            "commonsource": read_source("SteamShell-Common.ahk"),
            "helpersource": read_source("SteamShell-Helper.ahk"),
            "sharedsource": read_source("SteamShell-Shared.ahk"),
        }
        for match in re.finditer(
                r"\$(\w+)(?:\.\w+)*\s+-(not)?match\s+"
                r"((?:\s*(?:\+\s*)?'(?:[^']|'')*'\s*)+)", text):
            subject, negated = match.group(1).lower(), bool(match.group(2))
            pattern = "".join(part.replace("''", "'") for part in
                              re.findall(r"'((?:[^']|'')*)'", match.group(3)))
            line = text[:match.start()].count("\n") + 1
            found = definition.search(pattern)
            if not found:
                continue
            name, rest = found.group(1), pattern[found.end():]
            if rest.startswith(".*?") and not re.search(r"\^\\?\}", rest):
                fail(f"{validator}:{line} anchors to {name}()'s body and then "
                     "scans forward with .*?, which runs past the end of it. "
                     "Once the thing it looks for moves out of that function the "
                     "assertion passes against some later one. Use "
                     "(?:(?!\\n\\})[\\s\\S])*? to bound it to the body.")
            if (negated and rest.strip() and subject in subjects
                    and not re.search(r"(?m)^" + re.escape(name) + r"\(",
                                      subjects[subject])):
                fail(f"{validator}:{line} constrains {name}()'s body with "
                     f"-notmatch, but ${match.group(1)} does not define {name} -- "
                     "so it is true whatever the code does. Assert against a "
                     "subject that has the function, or, if the point is that the "
                     "function must not exist, drop the body constraint.")
        # The vacuous negative. Collect the variables whose Count is asserted to
        # be zero first, then check only the ones a [regex]::Matches feeds.
        zeroed = set(re.findall(r"\$(\w+)\.Count\s+-eq\s+0", text))
        for match in re.finditer(
                r"\$(\w+)\s*=\s*@?\(?\s*\[regex\]::Matches\(\s*\$(\w+)\s*,\s*"
                r"((?:\s*(?:\+\s*)?'(?:[^']|'')*'\s*)+)", text, re.S):
            variable, subject = match.group(1), match.group(2).lower()
            if variable not in zeroed or subject not in subjects:
                continue
            pattern = "".join(part.replace("''", "'") for part in
                              re.findall(r"'((?:[^']|'')*)'", match.group(3)))
            required, alternations = counted_pattern_literals(pattern)
            body = subjects[subject]
            missing = sorted(n for n in required if n not in body)
            for branches in alternations:
                if not any(all(n in body for n in b) for b in branches):
                    # One representative name per branch, lexicographically
                    # smallest so the PowerShell side words this identically.
                    missing.append("|".join(sorted(min(b) for b in branches)))
            if missing:
                line = text[:match.start()].count("\n") + 1
                fail(f"{validator}:{line} asserts ${variable}.Count -eq 0, but "
                     f"its pattern names {', '.join(missing)}, which "
                     f"${match.group(2)} no longer contains -- so it counts zero "
                     "because it can no longer match anything, not because the "
                     "thing it forbids is absent. Re-point the pattern at the "
                     "name the code uses now.")


def check_powershell_variable_shapes():
    """A variable that holds a lookup TABLE must not be reassigned to TEXT.

    Both harnesses index the per-file function tables with .ContainsKey. Reusing
    one of those names for a Get-Content string replaces the table with a string,
    and PowerShell only notices at the next .ContainsKey -- which can be hundreds
    of lines further on, in an unrelated rule. The reported error names neither
    the variable nor the assignment that caused it.

    Cheap to check statically and impossible to see by reading, so it belongs
    here: the development machine cannot run PowerShell, and this exact mistake
    reached a Windows build.
    """
    table_rhs = re.compile(r"Get-Ahk\w*FunctionBodies|Read-\w*Manifest")
    text_rhs = re.compile(r"Get-Content|-Raw\b")
    for name in ("Validate-Common.ps1", "Validate-SteamShell.ps1",
                 "Validate-SteamShell-XFE.ps1", "Build-SteamShell.ps1"):
        path = ROOT / name
        if not path.exists():
            continue
        lines = decode_like_powershell(path.read_bytes()).splitlines()
        # Bound each function so a name reused in a DIFFERENT function is fine.
        bounds = []
        for index, line in enumerate(lines):
            if re.match(r"\s*function\s+[\w-]+", line):
                depth = 0
                for j in range(index, len(lines)):
                    code = re.sub(r'"(?:[^"`]|`.)*"', '""', lines[j])
                    code = re.sub(r"'[^']*'", "''", code)
                    code = re.sub(r"(^|\s)#.*$", r"\1", code)
                    depth += code.count("{") - code.count("}")
                    if depth == 0 and j > index:
                        bounds.append((index, j))
                        break
        for start, end in bounds:
            kinds = {}
            for offset, line in enumerate(lines[start:end + 1]):
                match = re.match(r"\s*\$(\w+)\s*=(?!=)\s*(.*)$", line)
                if not match:
                    continue
                variable, rhs = match.group(1), match.group(2)
                if table_rhs.search(rhs):
                    kind = "table"
                elif text_rhs.search(rhs):
                    kind = "text"
                else:
                    continue
                seen = kinds.setdefault(variable, {})
                seen.setdefault(kind, start + offset + 1)
            for variable, seen in sorted(kinds.items()):
                if len(seen) > 1:
                    where = ", ".join(f"{k} at line {v}" for k, v in sorted(seen.items()))
                    fail(f"{name}: ${variable} is assigned both a lookup table and "
                         f"raw text inside one function ({where}). The later "
                         "assignment wins, and every .ContainsKey on it afterwards "
                         "fails with a message naming neither the variable nor "
                         "this line.")


def check_powershell_scope_colons():
    for name in ("Validate-Common.ps1", "Validate-SteamShell.ps1",
                 "Validate-SteamShell-XFE.ps1", "Build-SteamShell.ps1"):
        path = ROOT / name
        if not path.exists():
            continue
        for number, line in enumerate(
                decode_like_powershell(path.read_bytes()).splitlines(), 1):
            for match in re.finditer(r'\$([A-Za-z_]\w*):', line):
                if match.group(1).lower() in POWERSHELL_SCOPES:
                    continue
                # Only inside a double-quoted string is the colon parsed this
                # way; a bare $x: in code is something else entirely.
                if line.count('"', 0, match.start()) % 2 == 0:
                    continue
                fail(f"{name}:{number} interpolates \"${match.group(1)}:\", which "
                     "PowerShell parses as a scoped variable reference and "
                     "rejects at PARSE time, taking the whole validator with "
                     f"it. Write \"${{{match.group(1)}}}:\" instead.")

            # A line starting with ";" is an AutoHotkey comment. PowerShell has
            # no such thing -- ";" is a statement separator -- so this file
            # silently stops being what its author meant, usually inside an
            # array literal where it takes the rest of the file with it.
            #
            # Easy to write because four of the five files here ARE AutoHotkey,
            # and the comment style is the only thing that differs at a glance.
            if line.lstrip().startswith(";"):
                fail(f"{name}:{number} begins with \";\", which is an "
                     "AutoHotkey comment. PowerShell reads it as a statement "
                     "separator and the parse fails from here to the end of "
                     "the file. Use \"#\".")

            # Assert-True declares [bool]$Condition, and PowerShell's parameter
            # binder will not coerce a String to Boolean -- it accepts only
            # booleans and numbers. So `Assert-True ($body)` where $body holds
            # the text of a regex match throws at RUN time, and because
            # Validate-Common.ps1 is dot-sourced by both validators it takes
            # every assertion in both down with it.
            #
            # A bare variable is flagged even when it genuinely holds a boolean.
            # The rule cannot know the type, and being explicit costs one
            # comparison while the alternative cost two build cycles.
            bare = re.search(r'Assert-True\s+\(\s*(\$[A-Za-z_]\w*)\s*\)', line)
            if bare:
                fail(f"{name}:{number} passes {bare.group(1)} to Assert-True "
                     "bare. Its -Condition is [bool], and the binder refuses to "
                     "convert a String, so this throws at run time and takes "
                     "both validators with it. Compare explicitly -- "
                     f'{bare.group(1)} -ne "", -gt 0, -eq $true.')


def _match_or_empty(pattern, text):
    """The matched span, or "" -- so a subject the validator builds by regex can
    be rebuilt here without a missing match becoming an exception."""
    found = re.search(pattern, text)
    return found.group() if found else ""



# A Settings row must carry the keys its own type is indexed by.
#
# Two crashes came from this shape in one build: a field Map with no "controls"
# for the seam to iterate, and a note row asked for a "label" it does not have.
# Neither degrades -- AutoHotkey throws "Item has no value" and the Settings
# window does not open -- and neither is visible by reading the table, because
# the missing key is only named somewhere else.
SETTINGS_ROW_KEYS = {
    "checkbox": ("section", "key", "label"),
    "choice": ("section", "key", "label"),
    "edit": ("section", "key", "label"),
    "shortcut": ("section", "key", "label"),
    "path": ("section", "key", "label", "prompt", "filter"),
    "note": ("text",),
    "section": ("label",),
}


def check_settings_row_keys(sources):
    shared = sources["SteamShell-Shared.ahk"]
    start = shared.find("SettingsCategoryRows(category) {")
    end = shared.find("return table.Has(category)", start)
    if start < 0 or end < 0:
        fail("SettingsCategoryRows could not be read; no Settings row would be "
             "checked for the keys its type is indexed by.")
        return
    rows = re.split(r"\n            (?=Map\(\"product\")", shared[start:end])
    checked = 0
    for row in rows:
        kind = re.search(r'"type", "(\w+)"', row)
        if not kind:
            continue
        checked += 1
        keys = set(re.findall(r'"(\w+)",', row))
        named = re.search(r'"key", "([^"]+)"', row)
        label = named.group(1) if named else kind.group(1)
        for required in SETTINGS_ROW_KEYS.get(kind.group(1), ()):
            if required not in keys:
                fail(f"Settings row '{label}' is a {kind.group(1)} and carries "
                     f"no \"{required}\". The row builder indexes it, so the "
                     "Settings window throws rather than drawing it wrong.")
        if kind.group(1) == "choice" and not (
                {"choices", "choicesFrom", "xfeChoices"} & keys):
            fail(f"Settings row '{label}' is a choice with no list of choices.")
    if checked < 90:
        fail(f"Only {checked} Settings rows were read from the shared table; "
             "the scan is not seeing the table and would pass on nothing.")


SETTINGS_READERS = (r"(?:ReadText|ReadNumber|ReadBool|ReadInt|ReadFloat"
                    r"|IniReadS|ReadIniBool|ReadIniInt)")


def settings_rows_with_keys(shared):
    """(product, section, key) for every Settings row that names a key.

    A row with no key is a note or a section header and has nothing to read.
    """
    start = shared.find("SettingsCategoryRows(category) {")
    end = shared.find("return table.Has(category)", max(start, 0))
    if start < 0 or end <= start:
        return None
    table = shared[start:end]
    rows = []
    for match in re.finditer(r"Map\((?:[^()]|\([^()]*\))*?\)", table, re.S):
        text = match.group(0)
        key = re.search(r'"key"\s*,\s*"([^"]+)"', text)
        section = re.search(r'"section"\s*,\s*"([^"]+)"', text)
        if not key or not section:
            continue
        product = re.search(r'"product"\s*,\s*"(\w+)"', text)
        rows.append(((product.group(1) if product else "both"),
                     section.group(1), key.group(1)))
    return rows


def check_settings_rows_reach_consumers(sources):
    """Every Settings row reaches something that reads it.

    KEPT IN STEP WITH Assert-SettingsRowsReachConsumers in Validate-Common.ps1.
    See the header there for why the check is in two steps and, more usefully,
    for what it cannot do -- it proves the value is consumed, never that the
    consumer is the one the label promises.

    Two steps: the key is read by one of the section/key readers somewhere in the
    set the product compiles, and the variable that read lands in is referenced
    somewhere other than its `global` line and its own assignment.
    """
    rows = settings_rows_with_keys(sources["SteamShell-Shared.ahk"])
    if rows is None:
        fail("SettingsCategoryRows could not be read, so no Settings row would be "
             "checked for a consumer. A scan that sees no rows passes on nothing.")
        return
    if len(rows) < 90:
        fail(f"Only {len(rows)} Settings rows were read from the shared table. "
             "The extraction is not seeing it, and a scan over nothing passes.")

    for product, tree in (("standalone", "SteamShell.ahk"),
                          ("xfe", "SteamShell-XFE.ahk")):
        # Comments stripped, string bodies kept: the keys being looked for ARE
        # string literals. A comment naming a setting explains it rather than
        # reading it, and an end-of-line one would answer for the code.
        #
        # CONTINUATION SECTIONS ARE DROPPED, and step 2 is worth nothing without
        # that. GetDefaultSettingsIniText() holds the whole default INI as one
        # literal, so `MouseParkEdge=Right` sits in the shell's source as text --
        # and since most globals are named after their key, nearly every setting
        # in the shell looked consumed by the file that documents it. There is
        # exactly one such section in these sources, opened by a bare `(` line.
        lines = []
        for name in (tree, "SteamShell-Shared.ahk", "SteamShell-Common.ahk"):
            literal = False
            for line in sources[name].split("\n"):
                if not literal and line.strip() == "(":
                    literal = True
                    continue
                if literal:
                    if line.strip().startswith(")"):
                        literal = False
                    continue
                lines.append(re.sub(r"(?<!`);.*$", "", line))
        flat = re.sub(r"\s+", " ", "\n".join(lines))
        sites = list(re.finditer(r"(\w+)\s*:=\s*(?:\w+\(\s*)*" + SETTINGS_READERS
                                 + r"\(", flat))
        # STRING BODIES BLANKED, once, for the consumer scan -- and not for the
        # key scan. Step 1 is looking for a key, which IS a literal; step 2 is
        # looking for a variable, and most globals are named after their key, so
        # `"replacementKey", "EnableMouseParkOnFocusChange"` in a migration table
        # answered for code that had been deleted.
        #
        # Collected as a SET in one pass rather than re-scanned per row. The
        # per-row form was 200 rows times 30,000 lines of regex and cost twelve
        # seconds on its own; a validator nobody waits for is a validator nobody
        # runs. A line contributes every identifier it mentions except the one it
        # assigns to, and `global` lines contribute nothing -- which is exactly
        # the per-row rule, hoisted.
        consumers = set()
        for line in lines:
            trimmed = re.sub(r'"(?:[^"`]|`.)*"', '""', line).strip()
            if not trimmed or trimmed.startswith("global "):
                continue
            assigned = re.match(r"(\w+)\s*(?::=|\+=|-=|\.=)", trimmed)
            for word in re.findall(r"(?<![.\w])([A-Za-z_]\w*)(?![\w])", trimmed):
                if assigned and word.lower() == assigned.group(1).lower():
                    continue
                consumers.add(word.lower())

        for row_product, section, key in rows:
            if row_product != "both" and row_product != product:
                continue
            quoted = '"' + key + '"'

            # Flattened, because a read spans two lines whenever
            # MovedSettingSection() is involved -- and those are the rows most
            # likely to have drifted.
            binding = None
            for site in sites:
                # Bounded by the next assignment, not by a character count. A
                # fixed window reaches into the NEXT read -- these arrive in runs
                # of one per line -- and binds the row to the variable above it.
                nxt = flat.find(":=", site.end())
                window = flat[site.end():nxt if nxt > 0 else site.end() + 240]
                if quoted in window:
                    binding = site.group(1)
                    break
            if binding is None:
                # A read that is not assigned anywhere -- passed straight into a
                # call -- is consumed by definition.
                if not re.search(SETTINGS_READERS + r"\((?:[^()]|\([^()]*\))*?"
                                 + re.escape(quoted), flat):
                    fail(f"The {product} Settings window offers [{section}] {key}, "
                         "and nothing in the set it compiles reads that key back. "
                         "The row draws, accepts input and writes the INI, and "
                         "changes nothing.")
                continue

            if binding.lower() not in consumers:
                fail(f"The {product} Settings window offers [{section}] {key}, which "
                     f"is read into '{binding}', and nothing ever reads '{binding}' "
                     "back. The setting is stored and never acted on.")


AHK_CONTROL = re.compile(
    r"^(\s*)(if|else\s+if|else|while|for|loop|try|catch|finally)\b(.*)$", re.I)


def _has_inline_body(keyword, rest):
    """Whether the control statement already carries its body on the same line."""
    word = keyword.lower().replace(" ", "")
    body = rest.strip()
    if word in ("try", "else", "finally"):
        return body != ""
    if word == "catch":
        # `catch Error as e` is still a header, not a body.
        return body != "" and not re.fullmatch(r"[\w.]+(\s+as\s+\w+)?", body, re.I)
    if word in ("if", "elseif", "while"):
        if not body.startswith("("):
            return False
        depth = 0
        for index, char in enumerate(body):
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    return body[index + 1:].strip() != ""
        return False
    # for/loop headers have no bracketing to strip, so no claim is made.
    return False


def check_required_functions(sources):
    """Every name in a validator's $requiredFunctions must still be defined.

    KEPT IN STEP WITH the $requiredFunctions loops in Validate-SteamShell.ps1
    and Validate-SteamShell-XFE.ps1.

    THE REPLAY COULD NOT SEE THESE. It works by re-evaluating the `-match`
    assertions it can parse out of the two validators, and a required-function
    list is neither -- it is a PowerShell array walked by a foreach. So a
    renamed function passed every check on the development machine and failed on
    Windows, which is the second time this session a Windows-only class has been
    the thing that caught a rename: ShowMappingEditor became
    ShowControllerMappingWindow when the two mapping editors merged, and the
    list still named the old one.

    Cheap to check here, and the whole point of two harnesses is that the slow
    one should not be the only one that knows.
    """
    trees = {
        "Validate-SteamShell.ps1": "SteamShell.ahk",
        "Validate-SteamShell-XFE.ps1": "SteamShell-XFE.ahk",
    }
    for validator, tree in trees.items():
        text = read_source(validator)
        match = re.search(r"\$requiredFunctions\s*=\s*@\((.*?)\n\)", text, re.S)
        if not match:
            fail(f"{validator} has no $requiredFunctions list; the check that "
                 "every named entry point still exists has gone with it.")
            continue
        # The effective source: the tree plus everything it #Includes, because a
        # required function may legitimately have moved into a shared file.
        effective = "\n".join((sources[tree], sources["SteamShell-Common.ahk"],
                               sources["SteamShell-Shared.ahk"]))
        defined = set(name.lower() for name, _, _ in function_list(effective))
        for name in re.findall(r'"(\w+)"', match.group(1)):
            if name.lower() not in defined:
                fail(f"{validator} requires {name}(), which nothing {tree} "
                     "compiles defines any more. Rename the entry in the list in "
                     "the same commit that renames the function, or drop it if "
                     "the entry point is genuinely gone.")


def check_product_surfaces(sources):
    """Every window a TREE builds must be named in PRODUCT_SURFACES.txt.

    KEPT IN STEP WITH Assert-ProductSurfaces in Validate-Common.ps1.

    An INVENTORY, not a similarity measure, and that is the point. The
    fingerprint gate needs the same name in both trees, so a surface only one
    tree has never enters it -- the controller test sat in the shell for its
    whole life and nothing ever asked whether the companion should have it. The
    cross-name detector is the backstop for a surface both trees have under
    different names, and for the mapping editor it does not reach: 0.33 on call
    sequence with three shared calls is what two hand-written UIs over one data
    model look like, and the threshold cannot come down that far without
    drowning the report.

    A Gui built in SteamShell-Shared.ahk needs no entry. Its absence is what
    says the surface is already shared, so the file shrinks as the products
    converge instead of growing.
    """
    manifest = {}
    path = ROOT / "PRODUCT_SURFACES.txt"
    if not path.exists():
        fail("PRODUCT_SURFACES.txt is missing; every window a tree builds is "
             "recorded there with the reason it is not built once.")
        return
    for index, line in enumerate(read_source("PRODUCT_SURFACES.txt").split("\n"), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, _, reason = line.partition(":")
        if not reason.strip():
            fail(f"PRODUCT_SURFACES.txt:{index} lists '{name.strip()}' with no "
                 "reason. A bare name is the state this file exists to end.")
            continue
        manifest[name.strip().lower()] = reason.strip()
    built = {}
    for tree in ("SteamShell.ahk", "SteamShell-XFE.ahk"):
        for name, line, body in function_list(sources[tree]):
            code = "\n".join(strip_comments(l) for l in body)
            if re.search(r"(?<![.\w])Gui\(", code):
                built.setdefault(name.lower(), []).append(f"{tree}:{line}")
    for name, places in sorted(built.items()):
        if name not in manifest:
            fail(f"{places[0]} builds a Gui in {name}(), which PRODUCT_SURFACES.txt "
                 "does not list. A window one product has and the other does not "
                 "is a decision -- record why this tree builds its own, or move it "
                 "to SteamShell-Shared.ahk so both get it.")
    for name in sorted(set(manifest) - set(built)):
        fail(f"PRODUCT_SURFACES.txt lists '{name}', which no longer builds a Gui "
             "in either tree. Remove the entry -- a stale one turns this file "
             "into a list nobody revisits, which is what it exists to prevent.")


def check_local_shadows_call(sources):
    """A local that shadows something callable, per FUNCTION rather than per file.

    KEPT IN STEP WITH the shadow scan in Assert-AhkFileSanity in
    Validate-Common.ps1.

    A name cannot be both assigned as a local and called as "name(" in the same
    body. In AutoHotkey the assignment makes it a local, so the call resolves to
    that local instead of the function or class it looks like, and throws.

    THE MAC HAD NO COPY OF THIS UNTIL A WINDOWS RUN CAUGHT WHAT IT WAS FOR.
    Moving the shell's SettingsEditorPrimaryActive into SteamShell-Shared.ahk as
    SettingsPrimaryActive collided with a local already called
    settingsPrimaryActive in PollController -- AutoHotkey identifiers are
    case-insensitive, so those are one name -- and the poll would have thrown on
    its first tick. Every local check here passed, because this check lived only
    in the PowerShell half. That is the failure mode the two harnesses exist to
    avoid, so it is ported rather than left as a Windows-only rule.

    Scoped per function deliberately. It costs no list of builtin names to keep
    current -- `send := SubStr(v, 6)` shadows Send() harmlessly when nothing in
    that function calls it, and a name list would have failed the build on it.
    The signal is the collision, not the name.
    """
    for name, text in sources.items():
        for function, line, body in function_list(text):
            code = "\n".join(strip_comments(l) for l in body)
            assigned = {}
            for match in re.finditer(
                    r"(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:=", code):
                assigned[match.group(1).lower()] = match.group(1)
            reported = set()
            for match in re.finditer(
                    r"(?<![.\w])([A-Za-z_][A-Za-z0-9_]*)\s*\(", code):
                called = match.group(1).lower()
                # Recursion is a name calling itself, not a local shadowing it.
                if called == function.lower() or called in reported:
                    continue
                if called in assigned:
                    reported.add(called)
                    fail(f"{name}: {function}() at line {line}: local "
                         f"'{assigned[called]}' shadows the call "
                         f"'{assigned[called]}(' -- AutoHotkey resolves the call "
                         "to the local and throws at run time.")


def check_ambiguous_deindented_blocks(sources):
    """A braceless control statement whose body is not indented under it.

    KEPT IN STEP WITH Assert-NoAmbiguousDeindentedBlocks in Validate-Common.ps1.

    AutoHotkey does not care about indentation, so this is legal and means what
    the braces would mean -- exactly one statement. The problem is that it does
    not READ that way when the next statement sits at the same indent:

        if (sc)
        raw := Trim(SubStr(raw, 1, sc - 1))   ; guarded
        hc := InStr(raw, "#")                 ; NOT guarded, reads as though it is

    That pair is real, from the shell's INI parsing, next door to a truncation
    bug fixed in the same pass. It also breaks tools: `sed -n '/^Func/,/^}/p'`
    truncates on these sources because a `}` can appear at column 0 INSIDE a
    function, and that nearly produced a report of a PollController bug that did
    not exist.

    ONLY THE AMBIGUOUS ONES. A braceless body at the same indent that ENDS its
    block reads fine, and there are roughly 150 of those in the oldest file;
    reformatting them is a large diff for no gain. The rule here needs a third
    statement at the same indent after the body -- the case where a reader
    genuinely cannot tell where the body stops.
    """
    for name in ALL_FILES:
        lines = sources[name].split("\n")
        # Continuation sections are literal text, not code.
        code = []
        literal = False
        for line in lines:
            if not literal and line.strip() == "(":
                literal = True
                code.append(None)
                continue
            if literal:
                if line.strip().startswith(")"):
                    literal = False
                code.append(None)
                continue
            code.append(re.sub(r"(?<!`);.*$", "", line))
        live = [i for i, text in enumerate(code) if text and text.strip()]

        for position, index in enumerate(live):
            match = AHK_CONTROL.match(code[index])
            if not match:
                continue
            indent, keyword, rest = match.group(1), match.group(2), match.group(3).rstrip()

            # Asked FIRST, of the first line only. `try Foo("a"` + `. "b")` is one
            # statement whose argument list wraps, and walking its parentheses
            # would read the line after it as a de-indented body.
            if _has_inline_body(keyword, rest):
                continue

            # A CONDITION SPANNING LINES IS STILL THE HEADER, not the body. The
            # first version of this check read the `&& ...` continuation of a
            # multi-line `if` as the statement being guarded and asked for it to
            # be indented -- harmless, since AutoHotkey joins a line beginning
            # with an operator whatever its indent, but the wrong reason. Walk to
            # where the parentheses balance and start from there. Doing so also
            # finds the real cases behind those headers, which the first version
            # skipped: four of them, one in the controller poll.
            depth = rest.count("(") - rest.count(")")
            wrapped = depth > 0
            while depth > 0 and position + 1 < len(live):
                position += 1
                rest = code[live[position]].rstrip()
                depth += rest.count("(") - rest.count(")")
            if depth > 0:
                continue
            if rest.endswith("{"):
                continue
            # The balancing ')' is on this line, so anything after it is a
            # one-liner body: `... && b) return`.
            if wrapped and not rest.rstrip().endswith(")"):
                continue
            if position + 2 >= len(live):
                continue
            body, after = code[live[position + 1]], code[live[position + 2]]
            if body.strip().startswith("{"):
                continue
            if len(body) - len(body.lstrip()) != len(indent):
                continue
            if len(after) - len(after.lstrip()) != len(indent):
                continue
            if re.match(r"^\s*(\}|else\b|catch\b|finally\b)", after):
                continue
            fail(f"{name}:{index + 1} {keyword} has no brace and its body sits at the "
                 f"same indent, with another statement after it at that indent: "
                 f"`{body.strip()}` then `{after.strip()}`. Only the first is "
                 "guarded, and nothing on the page says so. Indent the body or "
                 "brace the block.")


def check_elevated_helper_protocol(sources):
    """The flags the trees build must be exactly the ones the helper parses.

    KEPT IN STEP WITH Assert-ElevatedHelperProtocol in Validate-Common.ps1.

    SteamShell-Helper.exe is one binary serving both products, and its command
    line is a contract between three programs. It used to be written out by hand
    in four places -- each product registers a scheduled task with one shape and
    requests elevation directly with another -- with nothing defining it and
    nothing comparing it against the helper.

    The failure that invites is quiet in the worst way. Rename a flag in the
    helper and the callers still build the old spelling; the helper starts, falls
    back to its default for the argument it did not recognise, and runs. For
    --product that default is "standalone", so an XFE helper would silently
    become a shell helper with elevated input and geometry enabled -- present in
    Task Manager, looking correct, doing something nobody asked for.

    Both directions are checked. A flag built and not parsed is ignored; a flag
    parsed and never built is either dead or a caller that forgot it.
    """
    builder = function_body(sources["SteamShell-Common.ahk"],
                            "SharedElevatedHelperArguments")
    if not builder:
        fail("SteamShell-Common.ahk defines no SharedElevatedHelperArguments(); "
             "the helper command line would have no single definition.")
        return
    # `" --parent-pid="` -- the separator lives inside the literal.
    built = set(re.findall(r'"\s*--([a-z-]+)=', builder))
    parsed = set(re.findall(r'ReadArgument\(\s*"([a-z-]+)"',
                            sources["SteamShell-Helper.ahk"]))
    if len(parsed) < 4:
        fail(f"Only {len(parsed)} ReadArgument calls were read from "
             "SteamShell-Helper.ahk; the scan is not seeing them.")
        return
    for flag in sorted(built - parsed):
        fail(f"SharedElevatedHelperArguments builds --{flag}= and "
             "SteamShell-Helper.ahk never reads it. The helper would ignore it "
             "and start anyway.")
    for flag in sorted(parsed - built):
        fail(f"SteamShell-Helper.ahk reads --{flag}= and "
             "SharedElevatedHelperArguments never builds it. The helper falls "
             "back to its default, which for --product is the WRONG product.")

    # And nobody may go around the builder.
    #
    # Comments go, string bodies STAY -- and not strip_comments(), which blanks
    # both. The flags being looked for ARE string literals, so blanking them
    # makes this pass on the very thing it exists to catch. Found by the mutation
    # test below, which is the second time in this file that helper has been the
    # wrong one to reach for.
    for name in ("SteamShell.ahk", "SteamShell-XFE.ahk"):
        code = "\n".join(re.sub(r"(?<!`);.*$", "", l)
                         for l in sources[name].split("\n"))
        for flag in sorted(set(re.findall(r"--([a-z-]+)=", code))):
            if flag in parsed:
                fail(f"{name} spells --{flag}= itself instead of calling "
                     "SharedElevatedHelperArguments. Four hand-written copies of "
                     "this command line is what that function exists to end.")


def check_game_score_weight_keys(sources):
    """The two products' score-weight tables must offer the same KEYS.

    KEPT IN STEP WITH Assert-GameScoreWeightKeys in Validate-Common.ps1.

    XfeGameScoreWeights and WindowEngineScoreWeights are correctly two functions:
    each fills the same shaped Map from its own settings namespace, Assist* in
    one and bare names in the other, and passing eleven values across a boundary
    to rebuild a Map the caller already holds would be longer and no safer.

    What is NOT per-product is the key names. GameWindowShapeVerdict and
    GameWindowCpuVerdict in this file index them by name for both products, so a
    key renamed or dropped on one side does not fail to compile and does not
    throw -- AutoHotkey's Map returns nothing for a missing key and the verdict
    quietly scores against an empty weight. The product that still has the key
    keeps working, which is what makes it hard to notice.

    So the keys are the contract, and this is the only thing asserting it.
    """
    keys = {}
    for name, fn in (("SteamShell.ahk", "WindowEngineScoreWeights"),
                     ("SteamShell-XFE.ahk", "XfeGameScoreWeights")):
        body = function_body(sources[name], fn)
        if not body:
            fail(f"{name} defines no {fn}(); the shared scorers index its keys.")
            return
        keys[name] = set(re.findall(r'"(\w+)"\s*,', body))
        if len(keys[name]) < 8:
            fail(f"{name}: only {len(keys[name])} weight keys were read from "
                 f"{fn}; the scan is not seeing the table.")
            return
    only_shell = keys["SteamShell.ahk"] - keys["SteamShell-XFE.ahk"]
    only_xfe = keys["SteamShell-XFE.ahk"] - keys["SteamShell.ahk"]
    for key in sorted(only_shell):
        fail(f"WindowEngineScoreWeights offers the weight '{key}' and "
             f"XfeGameScoreWeights does not. The shared scorers index weights by "
             "name for both products, so the companion scores against an empty "
             "value with nothing thrown.")
    for key in sorted(only_xfe):
        fail(f"XfeGameScoreWeights offers the weight '{key}' and "
             f"WindowEngineScoreWeights does not. The shared scorers index "
             "weights by name for both products, so the shell scores against an "
             "empty value with nothing thrown.")


def check_binding_label_tables(sources):
    """Each product's controller-binding table, and why it must be an ordered
    array of unique labels.

    KEPT IN STEP WITH Assert-BindingLabelTables in Validate-Common.ps1.

    One table per product now answers three questions -- the label for an action,
    the action for a label, and the list a Settings dropdown offers. That
    collapsed six hand-maintained copies into two, and it puts two new
    requirements on the table that nothing else would notice breaking.

    UNIQUE LABELS, because the reverse lookup scans for the first pair whose
    label matches. Two actions sharing a label makes one of them unreachable
    from the dropdown: the user picks it and gets the other one saved, with
    nothing thrown and nothing logged.

    AN ARRAY, NOT A MAP, because the same table supplies the dropdown's ORDER.
    AutoHotkey does not promise an enumeration order for a Map, so a table
    written as one would reorder the menu into whatever the implementation chose
    -- and it would look like a cosmetic regression rather than a data-structure
    one.
    """
    for name in ("SteamShell.ahk", "SteamShell-XFE.ahk"):
        body = function_body(sources[name], "ControllerBindingLabels")
        if not body:
            fail(f"{name} defines no ControllerBindingLabels(); the binding "
                 "vocabulary would have no single source.")
            continue
        if not re.search(r"static\s+labels\s*:=\s*\[", body):
            fail(f"{name}: ControllerBindingLabels must be an ARRAY of "
                 "[action, label] pairs. A Map has no promised enumeration "
                 "order, and this table supplies the Settings dropdown's order.")
            continue
        pairs = re.findall(r'\[\s*"([^"]+)"\s*,\s*"([^"]*)"\s*\]', body)
        if len(pairs) < 10:
            fail(f"{name}: only {len(pairs)} binding labels were read from "
                 "ControllerBindingLabels; the scan is not seeing the table.")
            continue
        for column, what in ((0, "action"), (1, "label")):
            seen = {}
            for pair in pairs:
                key = pair[column].lower()
                if key in seen:
                    fail(f"{name}: ControllerBindingLabels repeats the {what} "
                         f"'{pair[column]}'. The reverse lookup takes the first "
                         "match, so one of the two is unreachable from the "
                         "Settings dropdown -- picked by the user, saved as the "
                         "other, with nothing thrown.")
                seen[key] = True
        # Every action must be one the product can actually execute.
        actions = switch_case_labels(
            function_body(sources[name], "ProductControllerBindingAction"))
        # Builtin: values are dispatched in two steps -- the shared actions
        # first, then the product's own seam. Both have to be consulted or every
        # shared action reads as unimplemented.
        shared = switch_case_labels(
            function_body(sources["SteamShell-Shared.ahk"],
                          "ControllerBindingSharedAction"))
        for action, _ in pairs:
            if action in ("None",) or action in actions or action in shared:
                continue
            fail(f"{name}: ControllerBindingLabels offers '{action}', which "
                 "neither ProductControllerBindingAction nor the shared "
                 "binding executor implements. The dropdown would offer it and "
                 "selecting it would do nothing.")


def check_controller_poll_frame(sources):
    """The shared mapping tail, and the two things it resolved.

    KEPT IN STEP WITH Assert-ControllerPollFrame in Validate-Common.ps1.

    Both poll loops end in the same routine -- adopt buttons already held, move
    the cursor, scroll, run Short/Long for buttons and triggers, D-pad, Guide --
    and it is ControllerPollFrame now. The heads above it stay per-product and
    genuinely differ.

    Two differences were not cosmetic, and both resolved toward the shell's
    version. They are asserted here because they are invisible in use until a
    specific sequence of presses, and a well-meaning tidy could undo either.

    ADOPTING IS GUARDED. A button already being timed keeps its clock when the
    modifier goes down; the companion overwrote unconditionally and restarted it.

    ADOPTED TRIGGERS CLEAR longFired. The companion set the timestamp and the
    down-flag but left the flag, so a trigger that had fired a Long in an earlier
    hold could be adopted with it still set and would never fire a Long again.

    Also the ordering, which is what keeps the expensive work off buttons that
    are not bound that way: the hold-to-drag test comes before any Short/Long
    timing, and Long fires while the button is still held rather than on release.
    """
    body = function_body(sources["SteamShell-Shared.ahk"], "ControllerPollFrame")
    if not body:
        fail("SteamShell-Shared.ahk defines no ControllerPollFrame(); both poll "
             "loops would have to carry the mapping tail again.")
        return
    if not re.search(r'\(buttons & mask\) && !downTick\[name\]', body):
        fail("ControllerPollFrame adopts a held button without checking "
             "!downTick[name]. A hold already being timed restarts its clock "
             "the moment the modifier goes down.")
    for trigger in ("LT", "RT"):
        if not re.search(r'\(%s > 30\) && !downTick\["%s"\]\s*\)?\s*\{'
                         % (trigger.lower(), trigger), body):
            fail(f"ControllerPollFrame adopts {trigger} without checking "
                 f'!downTick["{trigger}"].')
        adopt = re.search(r'!downTick\["%s"\]\)\s*\{(.*?)\n        \}'
                          % trigger, body, re.S)
        if not adopt or 'longFired["%s"] := false' % trigger not in adopt.group(1):
            fail(f"ControllerPollFrame adopts {trigger} without clearing "
                 f'longFired["{trigger}"]. A trigger that fired a Long in an '
                 "earlier hold would never fire one again.")
    # Ordering, per loop. Checked in EACH of the two rather than across the
    # whole body: a single scan is satisfied by the trigger loop's copy even
    # when the button loop's has gone, which is how the first version of this
    # passed a mutation that deleted one of them.
    halves = body.split('for _, triggerName in ["LT", "RT"]')
    if len(halves) != 2:
        fail("ControllerPollFrame no longer has one button loop and one trigger "
             "loop; the ordering below cannot be checked.")
        return
    for half, what in ((halves[0], "button"), (halves[1], "trigger")):
        hold = half.find("ControllerBindingHoldsMouseButton(")
        long_test = half.find("HasLongBinding(")
        if hold < 0 or long_test < 0 or hold > long_test:
            fail(f"ControllerPollFrame's {what} loop no longer decides "
                 "hold-to-drag before Short and Long timing, so a drag binding "
                 "would also accrue a hold and fire an action on release.")


def check_learner_guard(sources):
    """The controller poll's learner stand-down, in both trees.

    Replays the three Assert-SharedParity rules in Validate-Common.ps1. Written
    out here rather than read from there because those rules live in PowerShell
    code, not in the Assert-True table this script replays -- and the rule they
    encode is one a development machine can check as well as Windows can.

    The guard is bounded by what may not appear inside it, not by indentation:
    standalone's sits at one level and XFE's a level deeper inside a try, and an
    indentation-shaped boundary silently stopped bounding XFE's at all. Every
    fragment is anchored to the start of a line, so the guard's own comments --
    which name both the right statement and the wrong one -- cannot answer for
    the code.
    """
    guard = r"(?ms)^PollController\(\)\s*\{(?:(?!\n\})[\s\S])*?\n[ \t]*if LearnActive \{"
    for name in ("SteamShell.ahk", "SteamShell-XFE.ahk"):
        text = sources[name]
        if not re.search(
                guard
                + r"(?:(?!\breturn\b)[\s\S])*?\n[ \t]*Reset\w*State\("
                + r"(?:(?!\n\})[\s\S])*?\n[ \t]*return\b", text, re.I):
            fail(f"{name}: the controller poll must stand down while the learner "
                 "is open, and clear its edge state on the way out.")
        if not re.search(
                guard
                + r"(?:(?!\breturn\b)[\s\S])*?\n[ \t]*ControllerNeedsFreshBaseline := true",
                text, re.I):
            fail(f"{name}: the learner guard must request a fresh controller "
                 "baseline, so the first poll after the wizard closes is edge-free.")
        # Zeroing it makes the next poll compute pressed as buttons & ~0, so
        # every button still held when the wizard closes arrives as a press edge
        # and fires its mapping -- the misfire the guard exists to prevent. Both
        # trees shipped the zeroing, under a comment claiming the opposite.
        if re.search(
                guard + r"(?:(?!\breturn\b)[\s\S])*?\n[ \t]*prev\w*Buttons := 0",
                text, re.I):
            fail(f"{name}: the learner guard must not zero the previous-button "
                 "word -- that turns every button held at close into a press edge.")


def check_settings_category_extraction(sources):
    """The two validators' category extractors still find what they parse.

    Ported after it cost a build. Both validators pull the page list out of the
    source with a regex and then compare it against the pages each product
    actually builds -- a property-subject check this script cannot replay, so
    when SettingsCategoryDefinitions replaced the two literal lists, the Mac
    stayed green and Windows failed with "The Full Settings category list could
    not be extracted."

    The comparison itself is Windows'. What is checked here is the part that
    broke: that the extractor MATCHES, and that what it extracts agrees with the
    pages each product draws. Both validators read the EFFECTIVE source with
    #Include resolved, which is approximated here by concatenation.
    """
    table = re.compile(
        r"(?s)SettingsCategoryDefinitions\(\)\s*\{.*?static definitions := \[(.*?)\n    \]")
    shared = sources["SteamShell-Shared.ahk"] + "\n" + sources["SteamShell-Common.ahk"]

    shell = sources["SteamShell.ahk"] + "\n" + shared
    m = table.search(shell)
    if not m:
        fail("Validate-SteamShell.ps1 could not extract the Full Settings "
             "category list; SettingsCategoryDefinitions no longer matches the "
             "shape it parses.")
        return
    declared = re.findall(r'"name", "([^"]+)", "product", "(?:both|standalone)"',
                          m.group(1))
    panels = sorted(set(re.findall(r'(?m)^[ \t]*category := "([^"]+)"', shell)))
    if len(declared) != len(set(declared)):
        fail("The shared category table lists a standalone page twice.")
    if sorted(set(declared)) != panels:
        fail("The Full Settings category list and its constructed panels "
             f"disagree. Declared: {sorted(set(declared))}. Built: {panels}.")

    xfe = sources["SteamShell-XFE.ahk"] + "\n" + shared
    m2 = table.search(xfe)
    if not m2:
        fail("Validate-SteamShell-XFE.ps1 could not extract the companion's "
             "Settings category table.")
        return
    count = len(re.findall(r'"name", "[^"]+", "product", "(?:both|xfe)"', m2.group(1)))
    body = re.search(r"(?s)ShowSettings\(\*\)\s*\{(.*?)\n\}", xfe)
    if not body:
        fail("ShowSettings could not be read, so the companion's page count is "
             "not checked.")
        return
    assigns = len(re.findall(r'(?m)^\s*category := "', body.group(1)))
    cursors = len(re.findall(r"y := SettingsFirstRowY\(\)", body.group(1)))
    if not (count == assigns == cursors):
        fail("Every companion Settings page must name its category and reset the "
             f"row cursor. Table lists {count}; found {assigns} category "
             f"assignment(s) and {cursors} cursor reset(s).")


def check_settings_rows_reach_their_readers(sources):
    """A setting a product READS must be reachable in that product's Settings.

    "Why does standalone's Advanced & Logging have way more things than the
    companion's?" Ten rows against three -- three of the extras are genuinely
    shell-only, but five were settings the companion reads in its own
    LoadSettings, writes into its own INI defaults, and could not reach from its
    own Settings window.

    Narrow on purpose: a row marked for ONE product whose key the OTHER product
    reads through an INI reader. A key merely mentioned in a migration table or
    a comment is not this.
    """
    shared = sources["SteamShell-Shared.ahk"]
    other = {"standalone": sources["SteamShell-XFE.ahk"],
             "xfe": sources["SteamShell.ahk"]}
    label = {"standalone": "the companion", "xfe": "the shell"}
    rows = [(m.group(1), m.group(3)) for m in re.finditer(
        r'Map\("product", "(both|standalone|xfe)"(.{0,400}?)"key", "(\w+)"',
        shared, re.S)]
    # WHICH PRODUCTS CAN REACH EACH KEY. A key may carry TWO rows, one per
    # product, with different sections, labels and defaults -- CooldownSec,
    # HardKill and EnableViewButtonActions all do, deliberately. The first
    # version of this check compared keys alone and reported all three as
    # unreachable when both products can reach them perfectly well.
    reachable = {}
    for product, key in rows:
        targets = ("standalone", "xfe") if product == "both" else (product,)
        for t in targets:
            reachable.setdefault(key, set()).add(t)
    bad = []
    for product, key in rows:
        if product == "both":
            continue
        missing = "xfe" if product == "standalone" else "standalone"
        if missing in reachable.get(key, set()):
            continue
        if re.search(r'Read(?:Text|Int|Bool|Number)\([^)]*"' + re.escape(key) + '"',
                     other[product]):
            bad.append(f"{key} (row is {product}-only, but {label[product]} reads it)")
    if bad:
        fail("Settings rows are marked for one product while the other reads the "
             "same key and has no row of its own: " + ", ".join(sorted(set(bad)))
             + '. A setting that can only be changed by hand-editing the INI is '
             'not a setting most users have -- mark the row "both", give the '
             "other product its own row, or stop reading the key.")


def check_live_log_shared(sources):
    """One shared Live Log viewer, each product naming its own status lines.

    It was the shell's alone, and PRODUCT_SURFACES.txt said why in the only
    honest way available: portability "has not been asked". It was asked.

    The SPLIT is what this pins, because collapsing it is the tempting tidy. The
    viewer is about a log file and both products want the same one; the status
    block is not -- four of the shell's eight lines name subsystems the
    companion has zero lines of. Each product must both ANSWER the seam and have
    a way to OPEN the window: a shared viewer nobody can reach is worse than
    none, and that is the state the companion was in.
    """
    shared = sources["SteamShell-Shared.ahk"]
    for name in ("ShowLiveLogWindow", "HideLiveLogWindow", "LiveLogRefresh"):
        if not function_body(shared, name):
            fail(f"SteamShell-Shared.ahk defines no {name}(); the Live Log "
                 "window is no longer shared.")
    show = function_body(shared, "ShowLiveLogWindow")
    refresh = function_body(shared, "LiveLogRefresh")
    hide = function_body(shared, "HideLiveLogWindow")
    if not re.search(r"ProductLiveLogStatusLines\(\)", show):
        fail("The shared Live Log window does not build its status lines from "
             "the seam, so one product's set is hard-coded into both.")
    if not re.search(r"ProductLiveLogStatusLines\(\)", refresh):
        fail("The shared Live Log window never refreshes its status lines from "
             "the seam.")
    if not (re.search(r"SetTimer\(LiveLogRefresh,", show)
            and re.search(r"SetTimer\(LiveLogRefresh, 0\)", hide)):
        fail("The Live Log window must arm and cancel its own refresh timer.")

    for name, product in (("SteamShell.ahk", "the shell"),
                          ("SteamShell-XFE.ahk", "the companion")):
        if not function_body(sources[name], "ProductLiveLogStatusLines"):
            fail(f"{name} does not answer ProductLiveLogStatusLines, so the "
                 f"shared Live Log window has no lines to show in {product}.")
        code = strip_code_noise(sources[name])
        if not re.search(r"ShowLiveLogWindow", code):
            fail(f"{name} offers no way to open the Live Log window.")


def check_settings_window_placement(sources):
    """Both Settings windows are placed the same way.

    They were not, and it showed from the couch: standalone's opened in the
    top-left corner while the companion's centred, same machine, same display.
    Standalone asked Gui.Show for a SIZE and no position -- Windows then chooses,
    and it chooses the top-left cascade -- then corrected with one WinGetPos and
    one WinMove. The companion sized and positioned in one shared call and then
    re-measured the window once VISIBLE.

    RecenterVisibleGuiOnMonitorActual is that correction and every other link in
    the chain was already shared. It was the one piece that was not.
    """
    shared = sources["SteamShell-Shared.ahk"]
    if not function_body(shared, "RecenterVisibleGuiOnMonitorActual"):
        fail("RecenterVisibleGuiOnMonitorActual is not in SteamShell-Shared.ahk; "
             "while it lived in one tree only that product's Settings centred.")
    for name, fn in (("SteamShell.ahk", "ShowSettingsEditor"),
                     ("SteamShell-XFE.ahk", "ShowSettings")):
        body = function_body(sources[name], fn)
        if not body:
            fail(f"{name}: {fn} could not be read, so the Settings window's "
                 "placement is not checked.")
        if not re.search(r"CenterGuiOnMonitorActual\(", body):
            fail(f"{name}: the Settings window is not sized and positioned "
                 "through CenterGuiOnMonitorActual. Gui.Show with a size and no "
                 "position lets Windows choose, and it chooses the top-left.")
        if not re.search(r"RecenterVisibleGuiOnMonitorActual\(", body):
            fail(f"{name}: the Settings window is never re-measured once "
                 "visible, so its position rests on a hidden-window estimate.")
        # One window, built from one place: geometry, chrome and footer. Without
        # this a product can quietly go back to building its own frame.
        for builder in ("SettingsWindowGeometry", "SettingsBuildWindowChrome",
                        "SettingsBuildWindowFooter"):
            if not re.search(builder + r"\(", body):
                fail(f"{name}: the Settings window does not build its frame "
                     f"through {builder}; a hand-built frame is how the two "
                     "products drifted apart.")
        if not re.search(r"GuiForegroundRetry\(", body):
            fail(f"{name}: the Settings window is shown but never made the "
                 "foreground; one activation request is one Windows may refuse.")

    # Gui's own "Center" centres on the PRIMARY monitor, not the one the window
    # was opened from -- wrong on any multi-monitor machine and identical to the
    # right answer on a single-display bench, which is how it survived.
    for name in ("SteamShell.ahk", "SteamShell-XFE.ahk", "SteamShell-Shared.ahk"):
        code = "\n".join(line for line in sources[name].split("\n")
                         if not line.lstrip().startswith(";"))
        # Bounded by the CALL: the first version read only the leading string
        # literal and missed .Show("w" w " h" h " Center").
        if re.search(r'\.Show\([^)]*\bCenter\b', code):
            fail(f"{name} places a window with Gui's own Center option. Use the "
                 "shared placement helpers, which centre on the monitor the "
                 "window was opened from.")


def check_settings_audit_bounds(sources):
    """The layout audit's own bounds must come from the layout.

    Ported alongside the other two PowerShell-code checks, and for the same
    reason: this one had been quietly wrong for a whole convergence pass. The
    companion's left bound said 286 -- its content column before the pages
    adopted the shared row builders and moved to contentX, 255 -- so every
    scrollable control on every page was reported as crossing the boundary, 86
    of them in one log. An audit that cries wolf 86 times is one nobody reads.
    """
    for name, fn in (("SteamShell.ahk", "SettingsEditorAuditLayout"),
                     ("SteamShell-XFE.ahk", "SettingsAuditLayout")):
        body = function_body(sources[name], fn)
        if not body:
            fail(f"{name}: {fn} could not be read, so the audit bounds are "
                 "not checked.")
        if not re.search(r'SharedAuditSettingsLayout\(.*?layout\["contentX"\]\s*-\s*10',
                         body, re.S):
            fail(f"{name}: the layout audit's LEFT bound is not derived from the "
                 "layout. A literal is a number that is right today.")
        if re.search(r"SharedAuditSettingsLayout\(.*?,\s*\d{3}\s*,", body, re.S):
            fail(f"{name}: the layout audit is passed a hard-coded bound.")


def check_learner_identify_release(sources):
    """The learner's baseline rule, replayed from Assert-ControllerLearnerIdentifyRelease.

    Ported for the same reason as the picker below, and after the same kind of
    miss: that check lives in PowerShell code rather than in the Assert-True
    table, so the Mac cannot see it, and a refactor that moved the baseline copy
    into ControllerLearnAdoptDevice sailed through here while breaking two of its
    assertions. Eight rules that only Windows could run is eight rules nobody
    edits with confidence.

    The rule itself: identification fires on the report where a bit CHANGED,
    which for almost every pad is the button going DOWN. The resting baseline
    must therefore come from the pre-press idle report the identification loop
    already keeps -- never from the live one -- and rest must not be measured
    until the identifying control comes back up.
    """
    shared = sources["SteamShell-Shared.ahk"]
    report = function_body(shared, "ControllerLearnReport")
    adopt = function_body(shared, "ControllerLearnAdoptDevice")
    released = function_body(shared, "ControllerLearnIdentifyReleased")
    timeout = function_body(shared, "ControllerLearnIdentifyHoldTimeout")
    ui = function_body(shared, "ControllerLearnUpdateUi")
    for name, body in (("ControllerLearnReport", report),
                       ("ControllerLearnAdoptDevice", adopt),
                       ("ControllerLearnIdentifyReleased", released),
                       ("ControllerLearnIdentifyHoldTimeout", timeout)):
        if not body:
            fail(f"{name} could not be read, so the learner's baseline rule is "
                 "not checked.")

    # The chain: caller passes the idle report, callee copies its parameter,
    # neither copies the live one.
    if not re.search(r"ControllerLearnAdoptDevice\(.*?baseline,", report, re.S):
        fail("ControllerLearnReport no longer hands the pre-press idle report to "
             "ControllerLearnAdoptDevice; the identifying press would become rest.")
    if not re.search(r"LearnBaseline\s*:=\s*ControllerLearnCopyReport\(\s*idleReport\s*,",
                     adopt):
        fail("ControllerLearnAdoptDevice no longer takes its resting baseline "
             "from the idle report its caller passed.")
    for name, body in (("ControllerLearnReport", report),
                       ("ControllerLearnAdoptDevice", adopt)):
        if re.search(r"LearnBaseline\s*:=\s*ControllerLearnCopyReport\(\s*data\s*,", body):
            fail(f"{name} copies the live report into LearnBaseline. That report "
                 "is the identifying PRESS, the one state that must not be rest.")
    if not re.search(r"LearnIdentifyHoldOffset\s*:=\s*holdOffset", adopt):
        fail("The learner no longer records which control identified the device, "
             "so it cannot wait for it to be released before measuring rest.")
    # A button changes a bit; an analogue byte changes most of them. In
    # DirectInput the identification step completed untouched, on byte 18 bit
    # 0xF8 -- a gyro axis parked at -60 flipping 0xFF to 0x00 on every crossing.
    # The scan must also continue past a rejected candidate, or a stick nudged
    # during the press outranks the button: byte 2 comes long before byte 8.
    if not (re.search(r"allowed := \(A_Index = 1\) \? 1 : MAX_IDENTIFY_BITS", report)
            and re.search(r"if \(bits > allowed\)\s*\n\s*continue", report)):
        fail("Identification accepts a change of any shape, so an analogue byte "
             "crossing a boundary answers the prompt before the user touches "
             "anything.")
    if not re.search(r"if !changed\s*\n\s*continue.*?identified := true", report, re.S):
        fail("Identification stops at the first byte that moved, so a nudged "
             "stick outranks the button being pressed.")
    if not re.search(r"if\s*\(LearnIdentifyHoldOffset\s*>=\s*0\)", report, re.S):
        fail("ControllerLearnReport no longer holds off while the identifying "
             "control is down; rest would be measured with it held.")

    # THE CHANGE-ONLY PAD, which is where this wizard hangs. A streaming pad
    # feeds the rest loop and the baseline self-corrects; a change-only pad feeds
    # it nothing, so the pre-press report -- usually containing the A press that
    # OPENED the wizard -- stays, and the identifying control's bit then shadows
    # every later step until nothing can be learned at all.
    begin = function_body(shared, "ControllerLearnBeginSteps")
    if not begin:
        fail("ControllerLearnBeginSteps could not be read.")
    if not re.search(r"if\s*\(LearnRestCount = 0\).*?"
                     r"LearnBaseline\s*:=\s*ControllerLearnCopyReport\(\s*\n?\s*LearnIdleSample",
                     begin, re.S):
        fail("ControllerLearnBeginSteps no longer adopts the last report seen "
             "when rest sampling received nothing. On a pad that reports only on "
             "change that is the only rest sample there is.")
    if not re.search(r"if \(LearnIdentifyHoldOffset >= 0\).*?LearnIdleSampleSeen := true",
                     report, re.S):
        fail("ControllerLearnReport no longer records the last report seen while "
             "the identifying control settles.")

    # One entry point to rest measurement, and a bound on the wait.
    if not (re.search(r"LearnRestSampling\s*:=\s*true", released)
            and re.search(r"ControllerLearnBeginSteps", released)):
        fail("ControllerLearnIdentifyReleased no longer starts the rest phase; it "
             "is the single entry point to rest measurement.")
    if not re.search(r"ControllerLearnIdentifyReleased", timeout):
        fail("The identify hold has no timeout. A pad whose release report is "
             "lost would leave the wizard waiting forever.")
    if re.search(r"LearnRestSampling\s*:=\s*true", ui):
        fail("ControllerLearnUpdateUi starts rest sampling. It runs the moment "
             "the device is identified, which is the moment the button went down.")


def check_recent_application_picker(sources):
    """The recent-application picker is on a button in BOTH products.

    Replays Assert-RecentApplicationPicker's reachability half from
    Validate-Common.ps1. Ported after it caught a regression on Windows that
    this harness sat green through: the companion's only opener was deleted when
    the exe-list field moved to SteamShell-Shared.ahk, and nothing here noticed.
    The whole point of this script is that the Windows box is not the first
    place to find out, and a check living in PowerShell code rather than in the
    Assert-True table is exactly the kind this script has to restate.

    TWO ROUTES, because the button moved into the shared file. A tree may open
    the picker itself, or build a shared exe-list field -- whose Recent… button
    opens it. The second route verifies the CHAIN rather than accepting the
    field's name as a promise: the builder wires SettingsExeListAddRecent to a
    button, and that function opens the picker. Break a link and the route stops
    counting.

    Comments are stripped first. A function named in the sentence explaining why
    it is not called is not a call to it.
    """
    # Comment LINES dropped, string bodies kept. strip_code_noise blanks string
    # literals too, which is right for the call scan below and wrong here: the
    # wiring this looks for is OnEvent("Click", ...), and a blanked literal makes
    # the chain unmatchable and the route silently unavailable. That is how the
    # first draft of this check reported the companion as unreachable when it
    # was not. Whole-line drop is what the PowerShell leak scan does, and it
    # still keeps a commented-out wiring from answering for real code.
    shared = "\n".join(line for line in sources["SteamShell-Shared.ahk"].split("\n")
                       if not line.lstrip().startswith(";"))
    if not function_body(shared, "ShowApplicationPicker"):
        fail("SteamShell-Shared.ahk defines no ShowApplicationPicker(); the "
             "recent-application picker is no longer shared and this check "
             "cannot see what replaced it.")
    builder = function_body(shared, "SettingsAddExeListField")
    recent = function_body(shared, "SettingsExeListAddRecent")
    field_route = bool(
        re.search(r'OnEvent\("Click",\s*SettingsExeListAddRecent\.Bind\(', builder)
        and re.search(r"ShowApplicationPicker\(", recent))

    for name, product in (("SteamShell.ahk", "the shell"),
                          ("SteamShell-XFE.ahk", "the companion")):
        code = strip_code_noise(sources[name])
        direct = bool(re.search(r"ShowApplicationPicker\(", code))
        viaField = field_route and bool(re.search(r"SettingsAddExeListField\(", code))
        if not (direct or viaField):
            fail(f"{name} never opens ShowApplicationPicker, directly or by "
                 f"building a shared exe-list field. It is compiled into "
                 f"{product} from the shared file and would be dead: the "
                 "history would be recorded and never offered to anybody.")


def check_source_encoding():
    """Every source must still decode as UTF-8.

    These files are UTF-8 on disk and are read as cp1252 by BOTH harnesses on
    purpose -- the long note at the top of this file explains why the symmetry
    matters. What that arrangement cannot survive is a byte that is valid cp1252
    and invalid UTF-8 getting written INTO a source, because then the file is
    neither.

    It happened here: an edit wrote one em dash as cp1252 0x97 into a file whose
    other twelve are UTF-8. Nothing failed loudly. grep began treating the file
    as binary and silently returned no matches for text that was plainly there,
    which is a worse failure than a crash -- every subsequent search says "not
    found" and means "unreadable".
    """
    for name in ALL_FILES + ["SHARED_FUNCTIONS.txt", "COMMON_FUNCTIONS.txt",
                             "DIVERGENT_FUNCTIONS.txt", "CROSS_NAME_DUPLICATES.txt",
                             "PRODUCT_SURFACES.txt"]:
        path = ROOT / name
        if not path.exists():
            continue
        raw = path.read_bytes()
        try:
            raw.decode("utf-8")
        except UnicodeDecodeError as error:
            line = raw[:error.start].count(b"\n") + 1
            fail(f"{name}:{line} contains byte 0x{raw[error.start]:02X}, which is not "
                 "valid UTF-8. The sources are UTF-8; a cp1252-only byte makes the "
                 "file unreadable to tools that assume UTF-8 and they fail by "
                 "finding nothing rather than by complaining.")
            continue
        # U+FFFD is the OTHER half of the same story, and the half that ships.
        #
        # The check above catches a byte that never decoded. This catches one
        # that decoded LOSSILY and was then written back: the replacement
        # character is what a lossy decode leaves behind, it is valid UTF-8, and
        # so nothing downstream objects. Four of them reached a release --
        # `exits<FFFD>? off` in the companion's Settings and two in the shell's
        # own "Apply (runtime only)" tip -- all four the corpse of a right double
        # quote, all four on screen in front of a user.
        #
        # No source here ever wants one on purpose, which is what makes this
        # worth failing on rather than reporting.
        for index, line_text in enumerate(raw.decode("utf-8").split("\n"), 1):
            if "�" in line_text:
                fail(f"{name}:{index} contains U+FFFD, the Unicode replacement "
                     "character. It is what a lossy decode leaves behind, it is "
                     "valid UTF-8 so nothing else objects, and it renders as a "
                     "black diamond in whatever window shows the string. Restore "
                     "the character it replaced: " + line_text.strip()[:80])


def check_settings_row_placement(sources):
    """No product may build two controls for the same setting.

    Each product's Settings save walks every registered field and writes it, so
    two rows for one section+key means the later registration silently overwrites
    whatever the user typed on the other page -- and the two pages disagree on
    screen until something reloads.

    It happened: the three Steam shortcuts were defined for the shell on the
    General page and, when the shell gained a Steam page, again on that. Nothing
    caught it, because both rows were individually valid.

    Also checks the other half of "is this row reachable" -- a row must belong to
    a category the product actually draws. Those two questions are the whole of
    whether a settings row lands where it was meant to.
    """
    shared = sources["SteamShell-Shared.ahk"]
    match = re.search(r"(?ms)^SettingsCategoryRows\(category\)\s*\{(.*?)\n\}", shared)
    if not match:
        fail("SettingsCategoryRows could not be parsed to audit row placement.")
        return
    body = match.group(1)
    heads = [(m.start(), m.group(1))
             for m in re.finditer(r'\n\s{8}"([A-Za-z][\w &.\-]*)",\s*\[', body)]
    seen = {}
    for index, (start, page) in enumerate(heads):
        end = heads[index + 1][0] if index + 1 < len(heads) else len(body)
        for row in re.finditer(r"Map\((?:[^()]|\([^()]*\))*?\)", body[start:end], re.S):
            text = row.group(0)
            key = re.search(r'"key"\s*,\s*"([^"]+)"', text)
            section = re.search(r'"section"\s*,\s*"([^"]+)"', text)
            if not key or not section:
                continue
            product = re.search(r'"product"\s*,\s*"(\w+)"', text)
            product = product.group(1) if product else "both"
            for one in (("standalone", "xfe") if product == "both" else (product,)):
                seen.setdefault((one, section.group(1), key.group(1)), []).append(page)
    for (product, section, key), pages in sorted(seen.items()):
        if len(pages) > 1:
            fail(f"The {product} Settings window builds two controls for "
                 f"[{section}] {key}, on {' and '.join(sorted(set(pages)))}. Its save "
                 "writes every registered field, so one of them silently "
                 "overwrites the other.")


def check_view_button_actions(sources):
    """The View button's tap/hold action, in both trees.

    Replays the Assert-SharedParity rule of the same name. The third pattern is
    the one that makes the other two safe: a press must be marked as a modifier
    use the moment anything else is touched during the hold, or "hold View, press
    A" fires a Steam shortcut underneath the mapping.
    """
    # The tracker is ControllerTrackViewButton in SteamShell-Shared.ahk now, so
    # the rule is checked once, where it lives -- and each tree is checked for
    # still calling it, which is the half that could silently go away.
    tracker = function_body(sources["SteamShell-Shared.ahk"],
                            "ControllerTrackViewButton")
    ok = (tracker
          and re.search(r"ViewButtonReleased\(\s*\n?\s*now - pressTick, usedAsModifier\)", tracker)
          and re.search(r"(?s)if !wasDown \{[\s\S]{0,200}?pressTick := now", tracker)
          and re.search(r"(?s)\|\| lt > 30 \|\| rt > 30[\s\S]{0,120}?usedAsModifier := true", tracker))
    if not ok:
        fail("ControllerTrackViewButton must record the press tick and mark the "
             "press as a modifier use as soon as anything else is touched during "
             "the hold, then report the hold to ViewButtonReleased.")
    for name in ("SteamShell.ahk", "SteamShell-XFE.ahk"):
        if not re.search(r"ControllerTrackViewButton\(", sources[name]):
            fail(f"{name} no longer tracks the View button's own press, so its "
                 "tap and hold actions can never fire.")
    # The rows live in the shared table's "Steam" category, so the shell has to
    # DRAW a Steam page or they are unreachable however they are tagged. That is
    # how they shipped invisible the first time.
    shell = sources["SteamShell.ahk"]
    shared = sources["SteamShell-Shared.ahk"]
    # The page list is SettingsCategoryDefinitions now, not an array written out
    # in the shell -- so the first half asks the shared table whether standalone
    # gets a Steam page, and the second still asks the shell whether it draws it.
    if not (re.search(r'"name", "Steam", "product", "(both|standalone)"', shared)
            and re.search(r'(?s)category := "Steam"[\s\S]{0,400}?'
                          r'SettingsAddRowsForCategory\(SettingsGui, category, "standalone"', shell)):
        fail("SteamShell.ahk defines Steam settings rows but does not draw a Steam "
             "category, so they cannot be reached from the Settings window.")


def check_view_button_default_split(sources):
    """OFF in the shell, ON in the companion -- stated consistently.

    Replays the Assert-SharedParity rule of the same name. A deliberate
    asymmetry is the kind most at risk of being tidied away, and the default is
    stated in four places per product. The spec row is the one that bites
    silently: it is the Settings window's fallback when the key is absent, so a
    spec disagreeing with LoadSettings shows a window claiming the feature is on
    while the program runs with it off.
    """
    spec = sources["SteamShell-Shared.ahk"]
    checks = [
        (re.search(r'(?s)"product", "standalone"[^)]*?"key", "EnableViewButtonActions"'
                   r'[^)]*?"default", false', spec), "spec row for the shell"),
        (re.search(r'(?s)"product", "xfe"[^)]*?"key", "EnableViewButtonActions"'
                   r'[^)]*?"default", true', spec), "spec row for the companion"),
        (re.search(r'ReadBool\("Steam", "EnableViewButtonActions", false\)',
                   sources["SteamShell.ahk"]), "the shell's LoadSettings default"),
        (re.search(r'ReadBool\("Steam", "EnableViewButtonActions", true\)',
                   sources["SteamShell-XFE.ahk"]), "the companion's LoadSettings default"),
    ]
    missing = [label for ok, label in checks if not ok]
    if missing:
        fail("The View button action must default OFF in the shell and ON in the "
             "companion, and each tree's settings-spec row must carry the same "
             "default its LoadSettings uses. Wrong or missing: "
             + ", ".join(missing) + ".")


def check_rtss_limiter_restore(sources):
    """The limiter flag is re-enabled even when the FPS write fails.

    Replays the Assert-SharedParity rule of the same name.

    The frame cap is two mechanisms with two privilege requirements. The FPS is a
    property of RTSS's Global profile ON DISK and cannot be saved unelevated
    against a stock Program Files install; the limiter flag goes through RTSS's
    shared memory and works either way. Returning on the failed FPS write skipped
    the flag entirely, so whether the limiter survived a reboot was decided by
    whether RTSS happened to already hold the recorded FPS -- and when it did
    not, the cause was usually an earlier write that had been blocked too, so it
    stayed broken.

    Expressed as ORDER, because that is exactly what the defect was: the flag has
    to be applied before any early return that reports the FPS could not land.
    """
    text = sources["SteamShell-Shared.ahk"]
    if not re.search(
            r'(?ms)^RestoreRtssFrameLimitTick\([^)]*\)\s*\{[\s\S]*?'
            r'fpsRestored := SetRtssGlobalFrameLimit\('
            r'(?:(?!\n\})[\s\S])*?ApplyRtssGlobalState\("limiter", true\)'
            r'(?:(?!\n\})[\s\S])*?if !fpsRestored', text):
        fail("RestoreRtssFrameLimitTick must re-enable the RTSS limiter before it "
             "gives up on a failed FPS write; otherwise the limiter silently does "
             "not survive a reboot whenever RTSS holds a different frame cap.")


def main():
    sources = {name: read_source(name) for name in ALL_FILES}
    maps = {name: function_map(text) for name, text in sources.items()}
    check_powershell_scope_colons()
    check_powershell_variable_shapes()
    check_validator_assertion_shapes()
    check_binding_label_tables(sources)
    check_game_score_weight_keys(sources)
    check_elevated_helper_protocol(sources)
    check_controller_poll_frame(sources)
    check_learner_guard(sources)
    check_rtss_limiter_restore(sources)
    check_settings_category_extraction(sources)
    check_settings_rows_reach_their_readers(sources)
    check_live_log_shared(sources)
    check_settings_window_placement(sources)
    check_settings_audit_bounds(sources)
    check_learner_identify_release(sources)
    check_recent_application_picker(sources)
    check_source_encoding()
    check_settings_row_placement(sources)
    check_view_button_actions(sources)
    check_view_button_default_split(sources)
    check_settings_row_keys(sources)
    check_settings_rows_reach_consumers(sources)
    check_ambiguous_deindented_blocks(sources)
    check_local_shadows_call(sources)
    check_product_surfaces(sources)
    check_required_functions(sources)
    check_quickmenu_rows(sources)
    check_schema_versions()
    check_cross_name_anchors(sources)

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
    # Common must not NAME anything only SteamShell-Shared.ahk defines.
    #
    # Replays the escape scan in Validate-Common.ps1, which this script did not
    # have -- and the gap cost a Windows build. Moving LogLine into the shared
    # file made Common name a shared-defined function; the PowerShell scan failed
    # and this one passed, because the only check here was the CALL-shaped one
    # below, which subtracts the seam allowlist. Two harnesses disagreeing about
    # a gate is the thing this file's own header warns about, so the scan is
    # replayed here rather than left to the Windows run.
    #
    # By NAME, not by call, because a bare reference passed as a callback is a
    # dependency too and is exactly what the call-shaped check cannot see.
    shared_names = {n for n in maps["SteamShell-Shared.ahk"]}
    common_text = strip_code_noise(sources["SteamShell-Common.ahk"])
    for escaped in sorted(shared_names - common_defined - COMMON_SEAM_ALLOWED):
        if re.search(r"(?<![.\w])" + re.escape(escaped) + r"\b", common_text, re.I):
            fail(f"SteamShell-Common.ahk reaches into SteamShell-Shared.ahk, which stops "
                 f"SteamShell-Helper.ahk compiling at all: {escaped}.")

    for leak in sorted((called & everything_else) - common_defined - COMMON_SEAM_ALLOWED):
        fail(f"SteamShell-Common.ahk calls '{leak}', which is not on its seam allowlist "
             f"({', '.join(sorted(COMMON_SEAM_ALLOWED))}). Move the callee in, pass the "
             "value as a parameter, or widen the allowlist deliberately.")
    # Across the INCLUDE CLOSURE, not the one file. What has to be true is that
    # the program can resolve the seam at load time, and #Include is how three
    # files become one program -- so a seam function living in
    # SteamShell-Shared.ahk satisfies both trees exactly as a local copy did.
    # Checking maps[program] alone demanded a copy in every tree, which is the
    # duplication the rest of this harness exists to drive out: it failed the
    # moment LogLine stopped being two identical copies and became one.
    for required in sorted(COMMON_SEAM_ALLOWED):
        for program, included in COMPILES.items():
            if not any(required in maps[f] for f in included):
                fail(f"{program} cannot resolve '{required}', which SteamShell-Common.ahk "
                     "depends on, from any file it compiles. AutoHotkey resolves that at "
                     "load time, so it would not start.")

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
    # CALLS AND CALLBACKS, matching Assert-SharedParity.
    #
    # This counted `Name(` only, so the four seams Shared reaches as bare
    # references -- ExportDiagnosticBundle and the three SettingsProduct*
    # handlers passed to OnEvent -- were absent from the derived seam and
    # therefore reported as STALE entries the moment the PowerShell list grew to
    # admit them. Deriving one way here and enforcing another way there is the
    # drift this file's header warns about; both sides read both forms now.
    shared_code = strip_code_noise(sources["SteamShell-Shared.ahk"])
    shared_calls = set()
    for m in re.finditer(r"(?<![.\w])([A-Za-z_]\w*)\s*\(", shared_code):
        shared_calls.add(m.group(1).lower())
    for m in re.finditer(r"(?<![.\w$])([A-Za-z_]\w*)(?![\w(])", shared_code):
        shared_calls.add(m.group(1).lower())
    actual_seam = (shared_calls & tree_defs) - shared_defs - set(maps["SteamShell-Common.ahk"])
    # A bare word that is ASSIGNED in the shared file is an ordinary local that
    # happens to share a name with a tree function -- AutoHotkey identifiers are
    # case-insensitive -- not a callback. Tested only against the handful of
    # names that survive the intersection above; testing every identifier
    # against a 440 KB source is minutes of regex for the same answer.
    actual_seam = {
        name for name in actual_seam
        if not re.search(r"(?<![.\w])" + re.escape(name) + r"\s*(?::=|\+=|-=|\.=)",
                         shared_code, re.I)}
    ps = (ROOT / "Validate-Common.ps1").read_text(encoding="utf-8", errors="replace")
    listed, _expected = read_shared_seam(ps)
    if listed:
        for extra in sorted(listed - actual_seam):
            fail(f"$sharedSeamAllowed in Validate-Common.ps1 lists '{extra}', which "
                 "SteamShell-Shared.ahk no longer reaches out to. The entry asserts it "
                 "is defined in both trees; remove it.")
        for missing in sorted(actual_seam - listed):
            fail(f"SteamShell-Shared.ahk reaches '{missing}' in a tree, and "
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
    #
    # KEPT IN STEP WITH Validate-Common.ps1 BY HAND, which is the standing hazard
    # in this file: two implementations of one check, and only one of them runs on
    # Windows. This gate drifted once already -- the PowerShell moved to 0.45, grew
    # a seam exemption and changed its stale rule, and this replay was still at
    # 0.75 with the old rule, reporting ten failures on a tree Windows called
    # clean. Any edit to the gate over there belongs here in the same commit.
    #
    # 0.45, not 0.75: two copies of one routine drift apart in STRUCTURE as well as
    # text, so the longer a duplicate goes unmerged the lower it scores. The metric
    # loses confidence exactly as the problem gets worse.
    divergent = read_divergent()
    a, b = maps["SteamShell.ahk"], maps["SteamShell-XFE.ahk"]

    # The per-product seam is exempt. $sharedSeamAllowed is already the record that
    # those functions differ by design; making them declare it a second time here
    # is how the counts in this project keep going wrong.
    ps_gate = (ROOT / "Validate-Common.ps1").read_text(encoding="utf-8", errors="replace")
    seam_exempt, expected = read_shared_seam(ps_gate)
    if seam_exempt and expected is not None and len(seam_exempt) != expected:
        fail(f"The shared seam has {len(seam_exempt)} entries but "
             f"$sharedSeamExpectedCount says {expected}. Update the "
             "expectation in the same commit that changes the list.")

    flagged = []
    for name in sorted(set(a) & set(b)):
        if name.lower() in seam_exempt:
            continue
        fa, fb = fingerprint(a[name][1]), fingerprint(b[name][1])
        score = similarity(fa, fb)
        subset = bool(fa and fb and fa != fb and
                      (is_subsequence(fa, fb) or is_subsequence(fb, fa)))
        if score >= 0.45 or subset:
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
    #
    # An entry is stale when the PAIR is gone, not when the pair scores low. This
    # used to subtract `flagged`, which is only populated at or above the
    # threshold -- so documenting a genuinely divergent pair that scores BELOW it
    # failed as stale. OpenWindowsSettings scores 0.00 precisely because a
    # privilege-boundary divergence shares no calls at all, and was therefore the
    # one kind of entry the file could not hold. Required and permitted are
    # separate questions: the threshold decides what MUST be explained, being a
    # real pair decides what MAY be.
    helper_wrappers = set(maps["SteamShell-Helper.ahk"]) & set(maps["SteamShell-Shared.ahk"])
    tree_pairs = set(a) & set(b)
    stale = sorted(set(divergent) - tree_pairs - helper_wrappers)
    for name in stale:
        fail(f"DIVERGENT_FUNCTIONS.txt lists '{name}', which is no longer defined in both "
             "trees. Remove the entry.")

    # ---- file hygiene ------------------------------------------------------
    #
    # Not a regex assertion, so replaying the validators does not cover it, and
    # it reached Windows as a build failure over two lines of trailing space in
    # a comment block. Cheap to check here; the whole point of this file is that
    # the cheap ones should not need a round trip.
    for name in ALL_FILES:
        raw = read_source(name)
        offenders = [i + 1 for i, line in enumerate(raw.split("\n"))
                     if line != line.rstrip()]
        if offenders:
            shown = ", ".join(str(n) for n in offenders[:6])
            more = f" (+{len(offenders) - 6} more)" if len(offenders) > 6 else ""
            fail(f"{name} has trailing whitespace on line(s) {shown}{more}.")

    # ---- delimiters the validators slice sections with --------------------
    #
    # Not assertions, so replaying -match/-notmatch never saw them: the Quick
    # Menu checks locate a section with $source.IndexOf("SomeFunction() {") and
    # bound it with the name of whatever function happened to sit next in the
    # file. Move that neighbour and IndexOf returns -1, the section comes out
    # empty, and the failure reads "the dispatch sections could not be
    # extracted" -- which says nothing about the function that actually moved.
    #
    # Every literal searched for this way must still be findable.
    for vpath, spath in (("Validate-SteamShell.ps1", "SteamShell.ahk"),
                         ("Validate-SteamShell-XFE.ps1", "SteamShell-XFE.ahk")):
        if not (ROOT / vpath).exists():
            continue
        effective = _effective_source(spath)
        vtext = "\n".join(
            _strip_ps_comment(line)
            for line in decode_like_powershell((ROOT / vpath).read_bytes()).split("\n"))
        for m in re.finditer(r'\$\w*[Ss]ource\w*\.IndexOf\(\s*"([^"]+)"', vtext):
            needle = m.group(1)
            if needle not in effective:
                fail(f"{vpath}:{vtext[:m.start()].count(chr(10)) + 1} slices a section "
                     f'with IndexOf("{needle}"), which no longer appears in the '
                     f"effective {spath}. The section will come out empty and the "
                     "failure will name the section rather than the function that moved.")

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
    # Rules this cannot replay, COUNTED rather than silently dropped.
    #
    # The subject scan below matches `$name -match`, so a rule written against a
    # property -- `$probeMatch.Value -match ...`, the usual shape when a
    # validator has already extracted one function body -- is invisible to it,
    # including to the "every subject must be known" check that reports anything
    # it cannot read. That check's own comment claims EVERY subject; it did not
    # mean this one, and the gap cost a Windows-only failure on a tree this
    # script called clean.
    #
    # Reconstructing those subjects here means reimplementing each extraction,
    # which is the duplication this file already warns about. So the number is
    # printed instead: it is the size of what only Windows checks.
    unreplayable = 0
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
        sample_ini = ("SteamShellSettings_SAMPLE.ini"
                      if spath == "SteamShell.ahk" else "SteamShell-XFE_SAMPLE.ini")
        texts = {
            "source": source,
            "rawsource": read_source(spath),
            "helpersource": read_source("SteamShell-Helper.ahk"),
            "helpereffective": _effective_source("SteamShell-Helper.ahk"),
            "sharedsource": read_source("SteamShell-Shared.ahk"),
            "commonsource": read_source("SteamShell-Common.ahk"),
            # Neither of these has "source" in its name, which is exactly why
            # they went unreplayed: the subject scan below used to look only for
            # $*source*. Twenty-one rules read $sample and nine read
            # $buildScript, and one of the $sample rules -- the companion's
            # settings schema version -- was failing on Windows while this
            # harness reported green.
            "sample": decode_like_powershell((ROOT / sample_ini).read_bytes()),
            "buildscript": (decode_like_powershell(
                (ROOT / "Build-SteamShell.ps1").read_bytes())
                if (ROOT / "Build-SteamShell.ps1").exists() else ""),
            # The two spec sources concatenated, which is what the companion's
            # validator means by $populateBody now: filling the window is a loop
            # over specs, so "is this field populated?" is "does it have a spec?".
            # Built the same way there, so a rule reading it is replayed against
            # the same string rather than skipped.
            # Both halves of the field scan now ask the same question of the
            # same specs -- is this field described? -- so they read the same
            # string. Named separately because the validator names them
            # separately, and a subject it reads must be one this can rebuild.
            "savebody": (
                _match_or_empty(
                    r"(?sm)^SettingsCompanionFieldSpecs\(\)\s*\{[\s\S]*?\n    \]",
                    source)
                + _match_or_empty(
                    r"(?sm)^SettingsCategoryRows\(category\)\s*\{[\s\S]*?return table",
                    source)),
            "populatebody": (
                _match_or_empty(
                    r"(?sm)^SettingsCompanionFieldSpecs\(\)\s*\{[\s\S]*?\n    \]",
                    source)
                + _match_or_empty(
                    r"(?sm)^SettingsCategoryRows\(category\)\s*\{[\s\S]*?return table",
                    source)),
        }
        # Subjects that are loop-local values rather than a file: each is a
        # per-iteration string the validator built itself, so there is nothing
        # here to replay them against. Listed rather than ignored, so the next
        # subject that appears is reported instead of silently skipped.
        LOOP_LOCAL = {"previous", "fallback", "current", "line", "declared",
                      "candidate", "simulation", "forbiddenscope", "_",
                      "defline"}
        unreplayable += len(re.findall(
            r"\$\w+(?:\.\w+|\[[^\]]*\])+\s+-(?:not)?match", vtext))
        # EVERY subject NAMED DIRECTLY, not just $*source*. The old pattern could
        # not see a subject whose name lacked the word "source", so $sample and
        # $buildScript were outside the net without anything saying so. Property
        # subjects are still outside it, and are counted above rather than
        # pretended about.
        for subject_name in sorted(set(
                m.group(1).lower() for m in re.finditer(
                    r"\$(\w+)\s+-(?:not)?match", vtext))):
            if subject_name in LOOP_LOCAL:
                continue
            if subject_name not in texts:
                fail(f"{vpath} asserts against ${subject_name}, which "
                     "Replay-Validation.py does not know how to read. Every rule "
                     "written against it is going unchecked here. Add it to `texts`.")
        for op, want in (("-match", True), ("-notmatch", False)):
            for m in re.finditer(r"\$(\w+)\s+" + re.escape(op)
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
    print(f"                      {unreplayable} written against a property "
          "subject; only Windows checks those")
    if FAILURES:
        print(f"\nFAILED ({len(FAILURES)}):\n")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("\nAll structural checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
