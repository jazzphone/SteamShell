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
ROW_ID_FAMILIES = ("layout:", "taskWindow:", "gamescore:", "toggle:", "page:")


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


def check_cross_name_duplicates(sources):
    """The same routine in both trees under two DIFFERENT names.

    The blind spot this project was built without. Both the fingerprint gate and
    DIVERGENT_FUNCTIONS.txt compare functions BY NAME, so a rename hides a
    duplicate from every check there is -- SetStatus and ShowNotification were
    three identical lines apiece and appeared on no list anywhere, and an entire
    settings-UI subsystem was duplicated behind a Settings*/SettingsEditor*
    prefix split.

    Two measurements, because one is not enough. Call-sequence similarity alone
    scores every one-call function against every other one-call function at
    1.00, which produced pairings like NormalizePath against ToBool. The token
    stream of the body is what separates them: real pairs scored 0.75 and up,
    coincidences 0.68 and down, with nothing in between across the whole tree.
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
    fa = {n: fingerprint(a[n][1]) for n in a if n not in b}
    fb = {n: fingerprint(b[n][1]) for n in b if n not in a}
    fa = {n: f for n, f in fa.items() if f}
    fb = {n: f for n, f in fb.items() if f}
    ta = {n: _body_tokens(a[n][1]) for n in fa}
    tb = {n: _body_tokens(b[n][1]) for n in fb}
    for x in sorted(fb):
        best = None
        for s in fa:
            call_score = similarity(fb[x], fa[s])
            if call_score < 0.85:
                continue
            body_score = similarity(tb[x], ta[s])
            if body_score < 0.72:
                continue
            if best is None or (call_score, body_score) > (best[0], best[1]):
                best = (call_score, body_score, s)
        if not best:
            continue
        key = f"{x}={best[2]}"
        if key in accepted:
            if not accepted[key]:
                fail(f"CROSS_NAME_DUPLICATES.txt lists '{key}' with no reason. "
                     "The reason is the entire value of that file.")
            continue
        fail(f"SteamShell-XFE.ahk's '{x}' and SteamShell.ahk's '{best[2]}' are "
             f"the same routine under two names (calls {best[0]:.2f}, body "
             f"{best[1]:.2f}). Give them one name and share it, or record the "
             f"pair in CROSS_NAME_DUPLICATES.txt as '{key}: why' with the reason "
             "they must stay separate.")


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


def main():
    sources = {name: read_source(name) for name in ALL_FILES}
    maps = {name: function_map(text) for name, text in sources.items()}
    check_powershell_scope_colons()
    check_settings_row_keys(sources)
    check_quickmenu_rows(sources)
    check_schema_versions()
    check_cross_name_duplicates(sources)

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
        # EVERY subject, not just $*source*. The old pattern could not see a
        # subject whose name lacked the word "source", so $sample and
        # $buildScript were outside the net without anything saying so.
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
    if FAILURES:
        print(f"\nFAILED ({len(FAILURES)}):\n")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("\nAll structural checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
