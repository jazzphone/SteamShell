; ==============================================================================
; SteamShell Common
; ==============================================================================
; The self-contained half of what the three programs share, and the only file
; all THREE of them #Include: SteamShell.ahk, SteamShell-XFE.ahk and
; SteamShell-Helper.ahk.
;
; The invariant, and the whole reason this file is separate:
;
;   NOTHING IN HERE MAY DECLARE A GLOBAL, OR CALL OR REFERENCE ANY FUNCTION
;   THAT IS NOT DEFINED IN THIS FILE OR BUILT IN TO AUTOHOTKEY -- EXCEPT
;   LogLine, WHICH ALL THREE PROGRAMS DEFINE.
;
; LogLine is the one permitted seam, and it is permitted because moving the
; logging out to callers would duplicate it three ways for no gain. It is
; enforced as an ALLOWLIST, not as prose: the parity check enumerates every call
; that leaves this file and fails on anything that is not LogLine. That is
; deliberately stricter than the older SteamShell-Shared.ahk rule, which asserted
; only that its two named seam functions existed -- and so never noticed the file
; quietly growing to eight.
;
; That is not a style rule. AutoHotkey resolves a call to an undefined function
; at LOAD time, and #Include is all-or-nothing, so a single reference out of
; this file into a tree stops the helper compiling at all. It is also what makes
; the file safe to put inside the one binary that runs with a High-integrity
; token: nothing here can silently depend on state the helper does not have.
;
; SteamShell-Shared.ahk remains the tree-coupled half -- RTSS orchestration,
; Quick Menu painting, elevated-helper lifecycle -- and is #Included by the two
; trees only. It reaches into the trees through the functions enumerated in
; $sharedSeamAllowed, and cannot be shared further without dragging those
; concerns into the helper. That boundary is the finding, not a compromise:
; roughly half of what looked shareable orchestrates tree state, and half
; genuinely does not.
;
; This sentence said "eight" for as long as the shared file's own header said
; "three", while the true count was 28. The sentence above then said "24" while
; the list grew to 36, which is the same defect a second time.
;
; It also promised "the check that fails when it is wrong", and no such check
; existed -- which is exactly why nobody noticed the second drift. So the counts
; are gone from both headers rather than corrected a third time, and
; Assert-SharedParity now fails when the seam list changes size without the
; expectation beside it being updated. A number in prose is a number nothing
; reads; the same number in the checker is a build failure.
;
; Functions only. No top-level code: this is inserted into three different
; auto-execute sections.
;
; COMMON_FUNCTIONS.txt is the manifest, and Assert-SharedParity enforces both
; the manifest and the invariant above.
; ==============================================================================

ApplyRoundedCorners(guiObj, radius) {
    ; Never shape a hidden window.
    ;
    ; WinSetRegion CLIPS the window to the region, and a window that is not yet on
    ; screen can report a size that is wrong -- the same hazard the centering path
    ; already compensates for. Measured on a 4K television: the region came out at
    ; the logical height while the window was at the scaled height, so the menu was
    ; cut off with a clean rounded edge straight through a row. That is why every
    ; page change afterwards looked right: those measure a real, visible window.
    visible := false
    try visible := DllCall("IsWindowVisible", "Ptr", guiObj.Hwnd, "Int") != 0
    if !visible
        return
    ; Windows 11 rounds the window itself, antialiased and composited by DWM.
    ; DWMWA_WINDOW_CORNER_PREFERENCE is 33, DWMWCP_ROUND is 2. The region path
    ; below is a 1-bit mask with visibly stepped corners, so it is now only the
    ; Windows 10 fallback rather than what everyone sees.
    try {
        ; DWMWA_BORDER_COLOR (34) with DWMWA_COLOR_NONE suppresses the thin
        ; system-drawn frame while retaining DWM's antialiased rounded corners.
        borderColor := Buffer(4, 0)
        NumPut("UInt", 0xFFFFFFFE, borderColor, 0)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd
            , "UInt", 34, "Ptr", borderColor, "UInt", 4, "UInt")
        preference := Buffer(4, 0)
        NumPut("Int", 2, preference, 0)
        if (DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd
            , "UInt", 33, "Ptr", preference, "UInt", 4, "UInt") = 0) {
            ; A region set by an earlier call would clip the rounded corners DWM
            ; is now drawing, so it has to be cleared.
            try WinSetRegion("", "ahk_id " guiObj.Hwnd)
            return
        }
    }
    try {
        ; Windows 10 has no border-color attribute. Remove the native border before
        ; applying its region fallback; on Windows 11 we retain the structural
        ; frame and suppress only its drawing so DWM can still round the window.
        try guiObj.Opt("-Border")
        WinGetPos(, , &realWidth, &realHeight, "ahk_id " guiObj.Hwnd)
        if (realWidth > 0 && realHeight > 0) {
            scaled := Round(radius * (A_ScreenDPI / 96.0))
            WinSetRegion("0-0 w" realWidth " h" realHeight
                . " R" scaled "-" scaled, "ahk_id " guiObj.Hwnd)
        }
    }
}

; Linear per-channel blend. Not gamma-correct, which is the right call here:
; the original QM_ROW_SELECTED was picked by eye in sRGB, so matching it means
; blending the same way it was chosen.
BlendHexColor(baseHex, mixHex, ratio) {
    out := ""
    Loop 3 {
        base := HexColorChannel(baseHex, A_Index)
        mix := HexColorChannel(mixHex, A_Index)
        value := Round(base + ((mix - base) * ratio))
        out .= Format("{:02X}", ClampInt(value, 0, 255))
    }
    return out
}

CenteredPosition(left, top, right, bottom, windowWidth, windowHeight, &x, &y) {
    x := left + Floor(((right - left) - windowWidth) / 2)
    y := top + Floor(((bottom - top) - windowHeight) / 2)
    if (windowWidth < right - left)
        x := ClampInt(x, left, right - windowWidth)
    else
        x := left
    if (windowHeight < bottom - top)
        y := ClampInt(y, top, bottom - windowHeight)
    else
        y := top
}

ClampFloat(v, lo, hi) {
    if (v < lo)
        return lo
    if (v > hi)
        return hi
    return v
}

ClampInt(v, lo, hi) {
    if (v < lo)
        return lo
    if (v > hi)
        return hi
    return v
}

DisplayScaleLevels() {
    ; Windows' fixed scale ladder. The source DPI packet reports min/current/max
    ; as positions relative to the recommended step; min therefore anchors the
    ; first supported entry in this list.
    return [100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500]
}

GetPrimaryDisplayDeviceName() {
    Loop 16 {
        device := Buffer(840, 0)
        NumPut("UInt", 840, device, 0)
        ok := false
        try ok := DllCall("User32\EnumDisplayDevicesW", "Ptr", 0,
            "UInt", A_Index - 1, "Ptr", device, "UInt", 0, "Int")
        if !ok
            break
        stateFlags := NumGet(device, 324, "UInt")
        if (stateFlags & 0x4)
            return StrGet(device.Ptr + 4, 32, "UTF-16")
    }
    return ""
}

GetPrimaryDisplayMode() {
    dm := Buffer(220, 0)
    NumPut("UShort", 220, dm, 68)
    try {
        if !DllCall("User32\EnumDisplaySettingsW", "Ptr", 0, "Int", -1, "Ptr", dm, "Int")
            return 0
    } catch {
        return 0
    }
    return Map(
        "width", NumGet(dm, 172, "UInt"),
        "height", NumGet(dm, 176, "UInt"),
        "frequency", NumGet(dm, 184, "UInt")
    )
}

HexColorChannel(hex, index) {
    return Integer("0x" SubStr(hex, (index * 2) - 1, 2))
}

MoveWindowPhysical(hwnd, x, y, w := 0, h := 0) {
    static SWP_NOSIZE := 0x0001
    static SWP_NOZORDER := 0x0004
    static SWP_NOACTIVATE := 0x0010
    flags := SWP_NOZORDER | SWP_NOACTIVATE
    if (w <= 0 || h <= 0)
        flags |= SWP_NOSIZE
    result := 0
    try result := DllCall(
        "User32\SetWindowPos", "Ptr", hwnd, "Ptr", 0,
        "Int", x, "Int", y, "Int", w, "Int", h, "UInt", flags, "Int")
    return result != 0
}

; Accepts "RRGGBB", "#RRGGBB" or "0xRRGGBB" and returns a bare uppercase
; "RRGGBB", or "" if the value is not a color. Returning "" rather than a
; guessed color is what lets the caller fall back visibly instead of painting
; the menu an unreadable shade.
NormalizeHexColor(value) {
    text := Trim(value)
    if (SubStr(text, 1, 1) = "#")
        text := SubStr(text, 2)
    else if (StrLower(SubStr(text, 1, 2)) = "0x")
        text := SubStr(text, 3)
    if !RegExMatch(text, "^[0-9A-Fa-f]{6}$")
        return ""
    return StrUpper(text)
}

; Four arcs and a close. GDI+ has no rounded-rectangle primitive.
QuickMenuAddRoundedPath(path, x, y, w, h, radius) {
    radius := Min(radius, Min(w, h) / 2)
    if (radius <= 0) {
        DllCall("gdiplus\GdipAddPathRectangle", "Ptr", path
            , "Float", x, "Float", y, "Float", w, "Float", h)
        return
    }
    d := radius * 2
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y
        , "Float", d, "Float", d, "Float", 180, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x + w - d, "Float", y
        , "Float", d, "Float", d, "Float", 270, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x + w - d, "Float", y + h - d
        , "Float", d, "Float", d, "Float", 0, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y + h - d
        , "Float", d, "Float", d, "Float", 90, "Float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
}

QuickMenuArgb(hex, alpha := 255) {
    return (alpha << 24) | Integer("0x" hex)
}

QuickMenuBottomMargin() {
    return 16
}

; The same margin, in whatever units the caller MEASURED the status control in.
;
; QuickMenuEnsureContentFits compares a measured client height against a
; requirement it has to reconstruct, because the layout is authored in logical
; units and AutoHotkey scales the controls on the way to the screen. Both trees
; reconstructed it by rounding 0.45 of the measured status height, and 0.45 is
; 16/36 -- this margin over that height -- rounded up and frozen as a literal.
;
; The expression is deliberately not written out here. Both validators assert it
; is absent from the effective source, and that source includes comments: naming
; it would satisfy the check it is meant to fail, which is the trap the shared
; file's own header records happening the other way round.
;
; THAT ONE DIGIT LOGGED A WARNING ON EVERY QUICK MENU OPEN. At 300% scale the
; layout leaves 16 * 3 = 48 physical pixels, and the check demands
; Round(108 * 0.45) = Round(48.6) = 49. One pixel short, deterministically, so
; the menu grew by a pixel and re-centred every time it was drawn and wrote a
; Warning line saying so. Ten of them in two minutes of ordinary use, on the
; product where the log is the only way to see that a row was clipped -- which
; is the failure the warning was added to make visible, drowned by itself.
;
; It only shows at scales where 0.45 and 16/36 round apart, which is why it
; survived: at 100% both give 16.
;
; Derived from the two layout functions now, so the check cannot disagree with
; the layout it is checking. The ratio is applied to the MEASURED height, so it
; carries whatever scaling was applied without this having to know what that was.
QuickMenuMeasuredBottomMargin(measuredStatusHeight) {
    if (QuickMenuStatusHeight() <= 0)
        return QuickMenuBottomMargin()
    return Round(
        measuredStatusHeight * QuickMenuBottomMargin() / QuickMenuStatusHeight())
}

; ==============================================================================
; CPU + STEAM FOREGROUND
; ==============================================================================
CalculateProcessCpuPercent(cpuDelta100ns, elapsedMs) {
    if (elapsedMs <= 0 || cpuDelta100ns < 0)
        return 0.0
    return ClampFloat(
        (cpuDelta100ns / (elapsedMs * 10000.0)) * 100.0, 0.0, 10000.0)
}

; The command line SteamShell-Helper.exe is started with.
;
; NOT A DUPLICATE PAIR -- A WIRE PROTOCOL, and that is why it is here rather than
; in either tree. One helper binary serves both products and parses exactly five
; flags in its ReadArgument calls. Those five were written out by hand in FOUR
; places: each product registers a scheduled task with one shape and requests
; elevation directly with another. Nothing defined them, and nothing compared
; them against the helper.
;
; The failure that invites is quiet in the worst way. Rename a flag in the helper
; and three call sites still build the old spelling; the helper starts, reads its
; default for the argument it did not recognise, and runs. For --product that
; default is "standalone", so an XFE helper would silently become a shell helper
; with elevated input and geometry enabled. Nothing throws, and the process is
; there in Task Manager looking correct.
;
; Empty or zero values are OMITTED rather than passed blank, because the helper
; distinguishes an absent argument (use the default) from an empty one.
;
; --product is always named even though the helper defaults to standalone. The
; helper treats any unrecognised value as standalone on purpose -- so a
; standalone user never silently gets the narrower XFE helper -- and naming it
; means a registered task's XML records which product registered it.
SharedElevatedHelperArguments(product, parentPid := 0, mainPath := "",
        settingsPath := "", logPath := "") {
    arguments := "--product=" product
    if parentPid
        arguments .= " --parent-pid=" parentPid
    if (mainPath != "")
        arguments .= " --main-path=" QuoteWindowsCommandLineArg(mainPath)
    if (settingsPath != "")
        arguments .= " --settings=" QuoteWindowsCommandLineArg(settingsPath)
    if (logPath != "")
        arguments .= " --log=" QuoteWindowsCommandLineArg(logPath)
    return arguments
}

; Rolling CPU usage for one process, as a percentage of one core-equivalent.
;
; WRITTEN TWICE AND DRIFTED APART, which is the reason it is here rather than the
; duplication. Both bodies opened the process, read GetProcessTimes, compared
; against the previous total for the same creation time and stored the result.
; The store, the Map key spellings and an optional rate limit differed, and so
; did one thing that is not cosmetic:
;
;   "known" now requires BOTH a positive elapsed time and a NON-NEGATIVE delta.
;   The companion asked only about elapsed time, so a negative delta -- which
;   happens when a PID is reused, or a counter resets -- was reported as a KNOWN
;   sample carrying the previous usage figure, to a detector whose whole question
;   is whether a game is running. The shell already required both; this is that
;   fix, ported.
;
; The store is a PARAMETER, which is what lets this live in Common: the two
; products keep their sample Maps in differently-named globals and neither
; crosses the boundary. minIntervalMs of 0 means sample every call, which is what
; the companion did.
SharedProcessCpuSample(pid, store, minIntervalMs := 0) {
    static PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    now := A_TickCount
    unknown := Map("usage", 0.0, "known", false, "lastSeen", now)
    if !pid
        return unknown

    if store.Has(pid) {
        cached := store[pid]
        ; lastSeen is refreshed even when the cached value is returned, because
        ; it is what the prune reads to decide the entry is still wanted.
        cached["lastSeen"] := now
        if (minIntervalMs > 0 && now - cached["sampleTick"] < minIntervalMs)
            return cached
    }

    handle := DllCall("Kernel32\OpenProcess",
        "UInt", PROCESS_QUERY_LIMITED_INFORMATION, "Int", false, "UInt", pid, "Ptr")
    if !handle
        return unknown
    creationTime := Buffer(8, 0)
    exitTime := Buffer(8, 0)
    kernelTime := Buffer(8, 0)
    userTime := Buffer(8, 0)
    ok := false
    try ok := DllCall("Kernel32\GetProcessTimes",
        "Ptr", handle, "Ptr", creationTime, "Ptr", exitTime,
        "Ptr", kernelTime, "Ptr", userTime, "Int")
    DllCall("Kernel32\CloseHandle", "Ptr", handle)
    if !ok
        return unknown

    creation := NumGet(creationTime, 0, "Int64")
    totalCpu100ns := NumGet(kernelTime, 0, "Int64") + NumGet(userTime, 0, "Int64")
    if store.Has(pid) {
        previous := store[pid]
        ; The creation time is what makes a PID safe to compare against itself.
        ; Windows reuses PIDs; without this a new process inherits the old one's
        ; baseline and reports a nonsense delta.
        if (previous["creation"] = creation) {
            elapsedMs := now - previous["sampleTick"]
            cpuDelta := totalCpu100ns - previous["totalCpu100ns"]
            usable := elapsedMs > 0 && cpuDelta >= 0
            sample := Map(
                "usage", usable
                    ? CalculateProcessCpuPercent(cpuDelta, elapsedMs)
                    : previous["usage"],
                "known", usable,
                "creation", creation,
                "totalCpu100ns", totalCpu100ns,
                "sampleTick", now,
                "lastSeen", now)
            store[pid] := sample
            return sample
        }
    }
    ; First sight of this process: a baseline with nothing to compare against, so
    ; not yet known.
    sample := Map(
        "usage", 0.0,
        "known", false,
        "creation", creation,
        "totalCpu100ns", totalCpu100ns,
        "sampleTick", now,
        "lastSeen", now)
    store[pid] := sample
    return sample
}

; Forget samples for processes that are no longer around.
;
; THE GRACE PERIOD IS THE POINT, and the companion did not have one: it deleted a
; PID's sample the moment that PID was absent from one pass of the inventory. The
; inventory is the FILTERED list, so a game that minimises, or whose window is
; briefly cloaked or tool-window-styled, drops out for a tick, loses its
; baseline, and comes back as known=false with a usage of zero -- to the detector
; whose entire question is whether a game is running. Thirty seconds is the
; shell's figure and long enough to cover any of those.
SharedPruneCpuSamples(store, liveInventory, graceMs := 30000) {
    live := Map()
    for _, item in liveInventory
        live[item["pid"]] := true
    stale := []
    for pid, sample in store {
        if (!live.Has(pid) && A_TickCount - sample["lastSeen"] > graceMs)
            stale.Push(pid)
    }
    for _, pid in stale
        store.Delete(pid)
    return stale.Length
}

; XINPUT_GAMEPAD, unpacked.
;
; The byte layout of the struct, in ONE place. It was written out in both poll
; loops and a third time, partially, in the companion's fresh-baseline path,
; which re-reads offsets 4, 6 and 7 to seed its edge state. Three copies of a
; layout that is fixed by Windows and silently wrong everywhere at once if it is
; wrong anywhere.
;
; Offsets are from the start of XINPUT_STATE: 0 is the packet number, which
; nothing here uses, then the gamepad struct from 4.
ControllerDecodeState(state, &buttons, &lt, &rt, &lx, &ly, &rx, &ry) {
    buttons := NumGet(state, 4, "UShort")
    lt := NumGet(state, 6, "UChar")
    rt := NumGet(state, 7, "UChar")
    lx := NumGet(state, 8, "Short")
    ly := NumGet(state, 10, "Short")
    rx := NumGet(state, 12, "Short")
    ry := NumGet(state, 14, "Short")
}

; Which buttons went down and which came up since the previous tick.
;
; previousButtons is the caller's static, updated here, because forgetting to
; update it is the failure this hides: edges then fire on every tick for as long
; as a button is held.
ControllerButtonEdges(buttons, &previousButtons, &pressed, &released) {
    pressed := buttons & ~previousButtons
    released := (~buttons) & previousButtons
    previousButtons := buttons
}

; A chord that must be HELD, and fires once.
;
; FOUR COPIES OF THIS EXISTED -- the Quick Menu chord and the Settings chord, in
; each product -- and the three rules they implement were written out in prose in
; one of them and described as "equivalent" in the others:
;
;   1. It must be HELD. Firing on the press edge meant a stray grip during play
;      could throw a window over a running game.
;   2. It fires ONCE per hold. Without `fired`, the action repeats every tick
;      past the threshold.
;   3. Releasing clears both, so the next hold starts a fresh measurement.
;
; The caller keeps the gates that decide whether the chord is eligible at all --
; those are per-product, because they name each product's own surfaces -- and
; returns when this returns true, which is rule 3 of the caller's own contract:
; the press that opened something must not also drive it.
;
; `since` and `fired` are the caller's statics, by reference.
ControllerChordFired(isHeld, holdMs, now, &since, &fired) {
    if !isHeld {
        since := 0
        fired := false
        return false
    }
    if !since
        since := now
    if (!fired && now - since >= holdMs) {
        fired := true
        return true
    }
    return false
}

; A startup entry turned into something launchable, or a logged reason it is not.
;
; The three checks either side of the split were the same in both products, down
; to the log wording -- parse the command line, refuse an entry that cannot be
; parsed, skip one whose executable is already running. What comes AFTER differs
; for real: the shell launches through LaunchInteractiveApp because it may be
; running elevated and must not hand its token to a child, the companion runs
; directly or by way of explorer.exe.
;
; THE EXISTENCE CHECK IS THE HALF THE SHELL DID NOT HAVE. The companion
; normalised the path and rejected a target that is not there by name; the shell
; passed whatever it read straight to the launcher, so a stale entry failed
; further in with a message about the launch rather than about the entry. Both
; get it now, which is the point of the check being in one place.
SharedPrepareStartupProgram(commandLine, &target, &arguments, &exeName, &directory) {
    target := "", arguments := "", exeName := "", directory := ""
    if !SplitStartupCommandLine(commandLine, &target, &arguments) {
        LogLine("Startup program entry could not be parsed: " commandLine, "Warning")
        return false
    }
    target := NormalizeMediaPath(target)
    if (target = "" || !FileExist(target)) {
        LogLine("Startup program not found: " target, "Warning")
        return false
    }
    SplitPath(target, &exeName, &directory)
    if (exeName != "" && ProcessExist(exeName)) {
        LogLine("Startup program already running, skipped: " exeName)
        return false
    }
    return true
}

; Launch a list with a growing delay between entries: the first immediately, the
; rest on one-shot timers.
;
; The stagger exists because a handful of programs starting at once on a handheld
; makes the first thirty seconds of a session unusable. `launcher` is a callable
; taking one entry, so each product keeps its own launch path and whatever it
; needs bound into it.
SharedLaunchWithStagger(entries, staggerMs, launcher) {
    if (entries.Length = 0)
        return 0
    LogLine("Launching " entries.Length " startup program(s).")
    delay := 0
    for _, entry in entries {
        if (delay = 0)
            launcher(entry)
        else
            SetTimer(launcher.Bind(entry), -delay)
        delay += staggerMs
    }
    return entries.Length
}

; Every registered Settings control checked against its page: does it exist, is
; it a real rectangle, does it stay inside the content column, does it overlap a
; sibling.
;
; The state is FIVE PARAMETERS rather than six globals, which is the whole reason
; this can live here. Both products kept their categories, their per-category
; control lists and their recorded positions in differently-named globals, and
; that -- plus a different content column and slightly different wording -- was
; the entire difference between two copies of this algorithm.
;
; The bounds come from each product's own layout: the content column starts
; further right in the companion and its right edge is the scrollbar rather than
; a content width. Those are two numbers, so they are two arguments.
;
; Messages carry the control handle, which was the shell's wording and not the
; companion's. "A control has no recorded position" cannot be acted on; "control
; 0x1A03C2 was not registered" can be found in a window spy.
SharedAuditSettingsLayout(categories, controlsByCategory, positions,
        contentLeft, contentRight) {
    issues := []
    for _, category in categories {
        if (!controlsByCategory.Has(category)
            || controlsByCategory[category].Length = 0) {
            issues.Push(category ": page has no registered controls.")
            continue
        }
        positioned := []
        for _, control in controlsByCategory[category] {
            if !positions.Has(control.Hwnd) {
                issues.Push(category ": control " control.Hwnd
                    . " was not registered with a position.")
                continue
            }
            pos := positions[control.Hwnd]
            if (pos["w"] <= 0 || pos["h"] <= 0) {
                issues.Push(category ": control " control.Hwnd
                    . " has invalid dimensions.")
                continue
            }
            ; Only a scrollable control is held to the content column. The fixed
            ; furniture -- the category list, the footer -- lives outside it by
            ; design.
            if (pos["scrollable"]
                && (pos["x"] < contentLeft
                    || pos["x"] + pos["w"] > contentRight)) {
                issues.Push(category ": control " control.Hwnd
                    . " crosses the Settings content boundary.")
            }
            ; Against the ORIGINAL positions, not the scrolled ones: two controls
            ; that overlap only after scrolling are one control off-screen, which
            ; is the scroll working.
            for _, previous in positioned {
                other := previous["pos"]
                overlaps := pos["x"] < other["x"] + other["w"]
                    && pos["x"] + pos["w"] > other["x"]
                    && pos["y"] < other["y"] + other["h"]
                    && pos["y"] + pos["h"] > other["y"]
                if overlaps {
                    issues.Push(category ": controls " previous["hwnd"] " and "
                        . control.Hwnd " overlap at their original positions.")
                }
            }
            positioned.Push(Map("hwnd", control.Hwnd, "pos", pos))
        }
    }
    return issues
}

; Run the audit and say what it found, in the log and on the product's own
; status line.
;
; A FAILED AUDIT IS A WARNING IN BOTH PRODUCTS NOW. The shell logged it at the
; default level while the companion logged "Warning" -- so on the product where
; the Settings window can be the only thing on screen, a page with overlapping
; or clipped controls produced a line indistinguishable from routine chatter.
; The two copies were never decided to differ; one of them was just written
; second.
;
; `report` is how each product shows a warning to the user, passed in because
; that genuinely differs: a status control here, a notification there.
SharedReportSettingsLayoutAudit(issues, report) {
    if (issues.Length = 0) {
        LogLine("Settings layout audit passed for all categories.")
        return true
    }
    LogLine("Settings layout audit found " issues.Length " issue(s): "
        . JoinWith(issues, " | "), "Warning")
    report("Layout warning recorded in the log")
    return false
}

; The controller-binding vocabulary, read three ways from ONE ordered table.
;
; SIX HAND-MAINTAINED COPIES became two. Each product had a forward table
; (ControllerBindingPretty: Builtin:Esc -> a label), a separate backward one
; (ChoiceToBinding in the shell, MappingBuiltinValue in the companion), and a
; third hardcoded list of the same labels for its Settings dropdown. Three per
; product, in three shapes: a switch, a Map, an array.
;
; They agreed, and nothing enforced it. Add an action to the forward table only
; and the label resolves but the dropdown never offers it; add it to the dropdown
; only and picking it saves Builtin:None -- the user chooses, saves, reopens and
; finds something else. Nothing throws and nothing logs.
;
; AN ARRAY OF PAIRS, NOT A MAP, and that is not a style choice. AutoHotkey does
; not promise an enumeration order for a Map, so deriving the dropdown from one
; would reorder both products' menus into whatever the implementation felt like.
; The array is the display order, and the two lookups are a scan of seventeen
; entries in a handler that runs when a dropdown changes.
;
; The tables stay per-product, and correctly: the companion speaks Xbox FSE's
; vocabulary and offers actions the shell does not. What is shared is the lookup,
; not the words.
SharedBindingLabelFor(action, labels) {
    for _, pair in labels {
        if (pair[1] = action)
            return pair[2]
    }
    return action
}

; Label -> "Builtin:<action>", off the same table, so the two directions cannot
; disagree because there are not two of them.
SharedBindingActionFor(label, labels) {
    for _, pair in labels {
        if (pair[2] = label)
            return "Builtin:" pair[1]
    }
    return "Builtin:None"
}

; The labels in table order, for a Settings dropdown to offer. Anything the
; product wants to add that is not an action -- the shell's "Custom shortcut…" --
; is the caller's to append, because it does not resolve to a binding.
SharedBindingLabelList(labels) {
    out := []
    for _, pair in labels
        out.Push(pair[2])
    return out
}

; The current display mode as one line: resolution, refresh rate, scale.
;
; Both products put this in front of the user and both built the string the same
; way, down to the two-space bullet separator and the multiplication sign. What
; differs is what each appends afterwards -- the shell adds a KEEP? countdown
; while a mode change waits to be confirmed, which is state the companion does
; not have -- and appending is the caller's business.
;
; "Unavailable" when the mode cannot be read, which both already returned. The
; word reaches a Quick Menu row and a Settings line, so it is a product string
; and not a diagnostic.
SharedDisplayModeText() {
    mode := GetPrimaryDisplayMode()
    if !IsObject(mode)
        return "Unavailable"
    text := mode["width"] "×" mode["height"] "  •  " mode["frequency"] " Hz"
    scale := GetPrimaryDisplayScale()
    if IsObject(scale)
        text .= "  •  " scale["percent"] "%"
    return text
}

; One wheel notch for the Settings window, or a refusal to handle the message.
;
; TRI-STATE ON PURPOSE, and it is the whole reason this takes a ByRef instead of
; returning the step count. OnMessage reads the handler's return value: 0 means
; "handled, stop", and returning nothing means "not handled, carry on to the
; default". The original bodies distinguished three outcomes -- not our window
; (nothing), a control that scrolls itself (nothing), and our window with a zero
; delta (0, handled) -- and a helper that returned 0 for both kinds of "no
; scroll" would silently start swallowing wheel messages meant for a ListBox.
;
; A list box owns its own wheel: scrolling the page out from under the list
; while the user is picking a row is not helpful. The companion means its
; startup-program list, the shell its category list.
;
; ListBox was once missing from the shell's copy and present in the companion's,
; and that difference was written down as deliberate -- "XFE also excludes the
; ListBox class" -- when the shell has a category ListBox of its own and
; scrolling over it moved the settings page instead. One copy cannot drift from
; the other now, which is most of the reason this is here.
SettingsWheelNotch(wParam, hwnd, rootHwnd, &notch) {
    notch := 0
    if (DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != rootHwnd)
        return false
    controlClass := ""
    try controlClass := WinGetClass("ahk_id " hwnd)
    if (controlClass = "ListBox" || controlClass = "SysListView32")
        return false
    ; WM_MOUSEWHEEL packs a signed delta in the high word of wParam.
    delta := (wParam >> 16) & 0xFFFF
    if (delta & 0x8000)
        delta -= 0x10000
    if (delta != 0)
        notch := delta > 0 ? -1 : 1
    return true
}

; Grow the Quick Menu window if its content does not fit, and re-centre it.
;
; WRITTEN TWICE UNTIL THE ONE-PIXEL BUG ABOVE HAD TO BE FIXED IN BOTH COPIES.
; DIVERGENT_FUNCTIONS.txt scored the pair at 0.70 and recorded a reason that did
; not survive being read again: the "real difference" was where the work area
; comes from -- the shell asks the monitor of QuickMenuPreviousHwnd, the
; companion its stored QuickMenuMonitorIndex. That is four numbers. The shared
; file's own header names the remedy for exactly this shape: move the callee in,
; PASS THE VALUE AS A PARAMETER, or widen the seam. Nobody had asked whether it
; could be a parameter.
;
; The second difference was real and is kept as one: the companion returns once
; the content fits, while the shell re-centres unconditionally, because that
; unconditional move is how its menu follows the foreground window's monitor. One
; boolean, decided by the caller.
;
; What that left duplicated was the measurement, the requirement, the work-area
; clamp, the centring and the log -- and every one of those is where the bug was.
;
; IN COMMON RATHER THAN SHARED, which the invariant allows because this touches
; no global: the window, the control and the work area all arrive as arguments,
; and CenteredPosition, MoveWindowPhysical and QuickMenuMeasuredBottomMargin are
; all defined here. LogLine is the one permitted seam.
QuickMenuFitContent(guiObj, statusCtrl,
        workLeft, workTop, workRight, workBottom, recentreWhenItFits) {
    statusY := 0
    statusHeight := 0
    clientHeight := 0
    winWidth := 0
    winHeight := 0
    try {
        ControlGetPos(
            , &measuredStatusY, , &measuredStatusHeight, statusCtrl, guiObj)
        WinGetClientPos(, , , &measuredClientHeight, "ahk_id " guiObj.Hwnd)
        WinGetPos(
            , , &measuredWinWidth, &measuredWinHeight, "ahk_id " guiObj.Hwnd)
        statusY := measuredStatusY
        statusHeight := measuredStatusHeight
        clientHeight := measuredClientHeight
        winWidth := measuredWinWidth
        winHeight := measuredWinHeight
    }
    ; winWidth is in the gate, which was the shell's rule and not the
    ; companion's. Proceeding with a zero width would centre a zero-width window
    ; rather than decline to touch a window that cannot be measured, so the
    ; stricter of the two is the correct one for both.
    if (statusHeight <= 0 || clientHeight <= 0 || winWidth <= 0 || winHeight <= 0)
        return

    needed := statusY + statusHeight + QuickMenuMeasuredBottomMargin(statusHeight)
    grow := Max(0, needed - clientHeight)
    ; A single pixel of shortfall is the two roundings disagreeing, not a clipped
    ; row. AutoHotkey scales each control coordinate independently, so the layout
    ; and this reconstruction can land a pixel apart at some scales however the
    ; margin is derived -- and growing the window by one pixel to fix a one-pixel
    ; miscount is the loop this used to be stuck in.
    if (grow <= 1)
        grow := 0
    if (grow = 0 && !recentreWhenItFits)
        return

    ; Never grow past the screen. If the content genuinely does not fit, a window
    ; the size of the work area is the honest outcome; growing beyond it would
    ; just move the clipping off-screen where it cannot be seen.
    maxHeight := workBottom - workTop
    finalHeight := Min(winHeight + grow, maxHeight)
    CenteredPosition(
        workLeft, workTop, workRight, workBottom, winWidth, finalHeight, &x, &y)
    if (grow > 0 || finalHeight != winHeight)
        MoveWindowPhysical(guiObj.Hwnd, x, y, winWidth, finalHeight)
    else
        MoveWindowPhysical(guiObj.Hwnd, x, y)

    ; Only when it GREW. A re-centre below a grow of zero is not worth a line --
    ; it is how the menu follows the foreground window's monitor, and it happens
    ; on every refresh. A Quick Menu that silently resizes itself is the one
    ; surface where a clipped row has no other diagnostic: on a shell replacement
    ; it may be the only interface on screen.
    if (grow > 0)
        LogLine("Quick Menu: content needed " grow "px more than the window had "
            . "(client " clientHeight ", status ends " (statusY + statusHeight)
            . "); grew to " winWidth "x" finalHeight " and re-centred."
            . (finalHeight < winHeight + grow ? " Clamped to the work area." : ""),
            "Warning")
}

; GDI+ has no blur. The glow is concentric strokes stepping outward with
; falling alpha, which is cheap, needs no second surface, and at these radii is
; visually indistinguishable from a real one.
QuickMenuDrawGlow(graphics, x, y, w, h, radius, hex, steps, maxAlpha, scale) {
    Loop steps {
        spread := A_Index * scale
        fade := (steps - A_Index + 1) / steps
        alpha := Round(maxAlpha * fade * fade)
        if (alpha < 2)
            continue
        QuickMenuStrokeRounded(graphics
            , x - spread, y - spread, w + (spread * 2), h + (spread * 2)
            , radius + spread, QuickMenuArgb(hex, alpha), 2.2 * scale)
    }
}

; align: 0 near, 1 centre, 2 far. Vertically centred and never wrapped, with an
; ellipsis when a value is too long -- the old Static controls clipped instead,
; which read as a rendering fault rather than as truncation.
QuickMenuDrawText(graphics, text, font, argb, x, y, w, h, align) {
    if (text = "" || !font)
        return
    layout := Buffer(16, 0)
    NumPut("Float", x, layout, 0)
    NumPut("Float", y, layout, 4)
    NumPut("Float", w, layout, 8)
    NumPut("Float", h, layout, 12)
    format := 0
    DllCall("gdiplus\GdipCreateStringFormat", "Int", 0, "Int", 0, "Ptr*", &format)
    if !format
        return
    DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", format, "Int", align)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", format, "Int", 1)
    DllCall("gdiplus\GdipSetStringFormatTrimming", "Ptr", format, "Int", 3)
    DllCall("gdiplus\GdipSetStringFormatFlags", "Ptr", format, "Int", 0x1000)
    brush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &brush)
    if brush {
        DllCall("gdiplus\GdipDrawString", "Ptr", graphics, "Str", text, "Int", -1
            , "Ptr", font, "Ptr", layout, "Ptr", format, "Ptr", brush)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    }
    DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", format)
}

QuickMenuFillRounded(graphics, x, y, w, h, radius, argb) {
    path := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)
    if !path
        return
    QuickMenuAddRoundedPath(path, x, y, w, h, radius)
    brush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &brush)
    if brush {
        DllCall("gdiplus\GdipFillPath", "Ptr", graphics, "Ptr", brush, "Ptr", path)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

; Space around the row band for the selected-row glow. Without this, the first
; and last rows clip the effect at the Static control's bitmap boundary.
QuickMenuGlowPadding() {
    return 8
}

QuickMenuMakeFont(pixelSize, bold) {
    family := 0
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "Str", "Segoe UI", "Ptr", 0, "Ptr*", &family)
    if !family
        return 0
    font := 0
    DllCall("gdiplus\GdipCreateFont", "Ptr", family, "Float", pixelSize
        , "Int", bold ? 1 : 0, "Int", 2, "Ptr*", &font)
    DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", family)
    return font
}

QuickMenuRowHeight() {
    return 40
}

QuickMenuRowInset() {
    return 20
}

QuickMenuRowTop() {
    return 74
}

QuickMenuStatusHeight() {
    return 36
}

QuickMenuStatusY(rowCount) {
    return QuickMenuRowTop() + 8 + (rowCount * QuickMenuRowHeight())
}

QuickMenuStrokeRounded(graphics, x, y, w, h, radius, argb, width) {
    path := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)
    if !path
        return
    QuickMenuAddRoundedPath(path, x, y, w, h, radius)
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", argb, "Float", width, "Int", 2, "Ptr*", &pen)
    if pen {
        DllCall("gdiplus\GdipDrawPath", "Ptr", graphics, "Ptr", pen, "Ptr", path)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

QuickMenuWidth() {
    return 620
}

SetDefaultAudioEndpointId(endpointId) {
    if (endpointId = "")
        return false
    ; Windows exposes default-endpoint selection through the PolicyConfig COM
    ; interface used by the Sound control panel. Try the modern interface first,
    ; then the Vista-compatible interface retained by current Windows versions.
    policy := 0
    try policy := ComObject(
        "{870AF99C-171D-4F9E-AF0D-E63DF40C2BC9}",
        "{F8679F50-850A-41CF-9C72-430F290290C8}")
    catch {
        try policy := ComObject(
            "{294935CE-F637-4E7C-A41B-AB255460B862}",
            "{568B9108-44BF-40B4-9006-86AFE5B5A620}")
    }
    if !IsObject(policy)
        return false

    try {
        ; Apply to console, multimedia, and communications roles.
        ComCall(13, policy, "WStr", endpointId, "Int", 0)
        ComCall(13, policy, "WStr", endpointId, "Int", 1)
        ComCall(13, policy, "WStr", endpointId, "Int", 2)
        return true
    } catch {
        return false
    }
}

; Posts WM_APP+100 to RTSS's window.
;
; MEASURED 2026-08-02, two observations that have to be read together:
;
;   Elevated, in-process     RTSS's window followed the change in real time.
;   Helper writes the file   RTSS's window kept the previous number until its
;                            profile selection was changed and changed back.
;
; In both cases the frame rate was limited correctly and Profiles\Global on disk
; was correct. So RTSS's display CAN follow a change -- an earlier note here
; concluded it could not, from the second observation alone, and that was wrong.
;
; The difference is not this message; it is SetProfileProperty. The elevated
; path ran SetProfileProperty -> SaveProfile -> UpdateProfiles, and the GUI
; appears to observe the profile state that SetProfileProperty writes. The
; helper path changes the FILE and then only LoadProfile/UpdateProfiles, so
; nothing ever touches the state the window is watching.
;
; Pushing SetProfileProperty from the unelevated process after the helper's file
; write was tried, and did not work either. The sequence cannot be split: the
; helper now runs LoadProfile / SetProfileProperty / SaveProfile /
; UpdateProfiles in its own process, which is what an elevated SteamShell always
; did. See ApplyHelperRtssFrameLimit in SteamShell-Helper.ahk.
;
; This message itself is kept because it is harmless and correctly ordered, not
; because it is known to do anything: nothing in this project's history records
; where WM_APP+100 came from or what it was ever observed to achieve. Do not
; cite it as the reason RTSS's UI agrees with SteamShell.
NotifyRtssSettingsChanged() {
    hwnd := 0
    try hwnd := DllCall("User32\FindWindowW", "Ptr", 0, "WStr", "RTSS", "Ptr")
    if !hwnd
        try hwnd := DllCall("User32\FindWindowW", "Ptr", 0,
            "WStr", "RivaTuner Statistics Server", "Ptr")
    if hwnd
        try DllCall("User32\PostMessageW", "Ptr", hwnd,
            "UInt", 0x8064, "UPtr", 0, "Ptr", 0, "Int") ; WM_APP + 100
}

RtssFrameCapModeIsKnown(mode) {
    static KNOWN := Map("off", true, "preset", true, "configured", true, "custom", true)
    return KNOWN.Has(StrLower(Trim(mode)))
}

; [Logging] GameLogMode, normalized to one of the four names the game-candidate
; logger understands. Anything else -- a typo, a value from an older build, an
; empty key -- reads as OFF, because a logging mode nobody recognizes should log
; nothing rather than something arbitrary.
;
; Shared because the derived switch is shared. LogGameCandidateTable gates on
; EnableGameScoreLogging AND on this mode, and the two trees used to arrive at
; those from different places: the shell normalized here and derived the bool,
; the companion read an independent [Logging] EnableGameScoreLogging bool and
; took the mode raw. So in the companion the pair could disagree -- GameLogMode
; TOPN with the bool unset logged nothing at all, silently, which is the failure
; this ends. Both trees now normalize here and derive the bool from the result.
NormalizeGameLogMode(raw) {
    static KNOWN := Map("OFF", true, "ACTIVATIONS", true, "TOPN", true, "DIAGNOSTIC", true)
    mode := StrUpper(Trim(raw))
    return KNOWN.Has(mode) ? mode : "OFF"
}

GetTokenInformationBuffer(token, informationClass, &informationBuffer, &errorCode) {
    needed := 0
    DllCall(
        "Advapi32\GetTokenInformation",
        "Ptr", token,
        "Int", informationClass,
        "Ptr", 0,
        "UInt", 0,
        "UInt*", &needed,
        "Int")
    if (needed <= 0) {
        errorCode := A_LastError
        informationBuffer := Buffer(0)
        return false
    }
    informationBuffer := Buffer(needed, 0)
    if !DllCall(
        "Advapi32\GetTokenInformation",
        "Ptr", token,
        "Int", informationClass,
        "Ptr", informationBuffer.Ptr,
        "UInt", informationBuffer.Size,
        "UInt*", &needed,
        "Int") {
        errorCode := A_LastError
        return false
    }
    errorCode := 0
    return true
}

OpenCurrentProcessToken(desiredAccess, &token, &errorCode) {
    token := 0
    if !DllCall(
        "Advapi32\OpenProcessToken",
        "Ptr", DllCall("Kernel32\GetCurrentProcess", "Ptr"),
        "UInt", desiredAccess,
        "Ptr*", &token,
        "Int") {
        errorCode := A_LastError
        return false
    }
    errorCode := 0
    return true
}

GetTokenUserSidString(token, &sidText, &errorCode) {
    sidText := ""
    if !GetTokenInformationBuffer(token, 1, &userInfo, &errorCode)
        return false
    sid := NumGet(userInfo, 0, "Ptr")
    sidStringPtr := 0
    if !sid || !DllCall(
        "Advapi32\ConvertSidToStringSidW",
        "Ptr", sid,
        "Ptr*", &sidStringPtr,
        "Int") {
        errorCode := A_LastError
        return false
    }
    try {
        sidText := StrGet(sidStringPtr, "UTF-16")
    } finally {
        DllCall("Kernel32\LocalFree", "Ptr", sidStringPtr, "Ptr")
    }
    errorCode := 0
    return sidText != ""
}

GetTokenSessionId(token, &sessionId, &errorCode) {
    sessionId := -1
    if !GetTokenInformationBuffer(token, 12, &sessionInfo, &errorCode)
        return false
    sessionId := NumGet(sessionInfo, 0, "UInt")
    return true
}

GetCurrentProcessUserSid(&sidText, &errorCode) {
    static TOKEN_QUERY := 0x0008
    sidText := ""
    if !OpenCurrentProcessToken(TOKEN_QUERY, &token, &errorCode)
        return false
    try {
        return GetTokenUserSidString(token, &sidText, &errorCode)
    } finally {
        DllCall("Kernel32\CloseHandle", "Ptr", token, "Int")
    }
}

GetCurrentProcessSessionId(&sessionId) {
    sessionId := -1
    return DllCall(
        "Kernel32\ProcessIdToSessionId",
        "UInt", DllCall("Kernel32\GetCurrentProcessId", "UInt"),
        "UInt*", &sessionId,
        "Int") != 0
}

GetProcessTokenSecurity(pid, &sidText, &sessionId, &integrityName, &errorText) {
    static PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    static TOKEN_QUERY := 0x0008
    sidText := ""
    sessionId := -1
    integrityName := "Unknown"
    errorText := ""

    processHandle := DllCall(
        "Kernel32\OpenProcess",
        "UInt", PROCESS_QUERY_LIMITED_INFORMATION,
        "Int", false,
        "UInt", pid,
        "Ptr")
    if !processHandle {
        errorText := "OpenProcess failed (" A_LastError ")."
        return false
    }
    token := 0
    try {
        if !DllCall(
            "Advapi32\OpenProcessToken",
            "Ptr", processHandle,
            "UInt", TOKEN_QUERY,
            "Ptr*", &token,
            "Int") {
            errorText := "OpenProcessToken failed (" A_LastError ")."
            return false
        }
        if !GetTokenUserSidString(token, &sidText, &errorCode) {
            errorText := "Token user query failed (" errorCode ")."
            return false
        }
        if !GetTokenSessionId(token, &sessionId, &errorCode) {
            errorText := "Token session query failed (" errorCode ")."
            return false
        }
        if !GetTokenInformationBuffer(token, 25, &integrityInfo, &errorCode) {
            errorText := "Token integrity query failed (" errorCode ")."
            return false
        }
        integritySid := NumGet(integrityInfo, 0, "Ptr")
        countPointer := integritySid
            ? DllCall(
                "Advapi32\GetSidSubAuthorityCount",
                "Ptr", integritySid,
                "Ptr")
            : 0
        if !countPointer {
            errorText := "The integrity SID was invalid."
            return false
        }
        subAuthorityCount := NumGet(countPointer, 0, "UChar")
        if (subAuthorityCount <= 0) {
            errorText := "The integrity SID had no sub-authorities."
            return false
        }
        ridPointer := DllCall(
            "Advapi32\GetSidSubAuthority",
            "Ptr", integritySid,
            "UInt", subAuthorityCount - 1,
            "Ptr")
        if !ridPointer {
            errorText := "The integrity RID was unavailable."
            return false
        }
        rid := NumGet(ridPointer, 0, "UInt")
        integrityName := rid < 0x1000 ? "Untrusted"
            : (rid < 0x2000 ? "Low"
            : (rid < 0x3000 ? "Medium"
            : (rid < 0x4000 ? "High" : "System")))
        return true
    } finally {
        if token
            DllCall("Kernel32\CloseHandle", "Ptr", token, "Int")
        DllCall("Kernel32\CloseHandle", "Ptr", processHandle, "Int")
    }
}

StrRepeat(s, count) {
    if (count <= 0)
        return ""
    out := ""
    Loop count
        out .= s
    return out
}

QuoteWindowsCommandLineArg(value) {
    ; Follow Windows' command-line quoting rules so relaunch arguments survive
    ; spaces, embedded quotes, and trailing backslashes.
    value := value ""
    if (value = "")
        return '""'
    if !RegExMatch(value, '[\s"]')
        return value

    quoted := '"'
    backslashes := 0
    Loop Parse value {
        ch := A_LoopField
        if (ch = "\") {
            backslashes += 1
            continue
        }
        if (ch = '"') {
            quoted .= StrRepeat("\", (backslashes * 2) + 1) '"'
            backslashes := 0
            continue
        }
        if (backslashes > 0) {
            quoted .= StrRepeat("\", backslashes)
            backslashes := 0
        }
        quoted .= ch
    }
    if (backslashes > 0)
        quoted .= StrRepeat("\", backslashes * 2)
    return quoted '"'
}

; True when nothing outside SYSTEM/Administrators/TrustedInstaller can write to
; path.
;
; This is the gate that makes the helper safe to elevate. Matching the expected
; file version proves only that some file with that version resource is sitting
; at the expected path -- a version resource is metadata anyone can stamp onto
; anything. If the interactive user can write the helper binary, or the directory
; holding it, they can put arbitrary code where the main process then hands it a
; High-integrity token, which is a local privilege escalation dressed up as a
; feature. Program Files installs got this from inherited ACLs; portable and
; browsed-custom targets never did.
;
; It is also what makes a path derived from A_ProgramFiles acceptable. That
; expands an environment variable this process inherited from whoever started
; it, so it is not evidence of anything on its own -- but a redirected value
; pointing at a directory the user controls fails the owner test below, and the
; helper is not launched.
;
; Deny ACEs are not consulted. A deny that happens to cover a writable grant
; would make this report "writable" when the effective answer is "not writable",
; which fails toward refusing to elevate.
SteamShellPathIsAdminOnlyWritable(path, &grantedTo, &failureReason) {
    static SE_FILE_OBJECT := 1
    static DACL_SECURITY_INFORMATION := 0x00000004
    static OWNER_SECURITY_INFORMATION := 0x00000001
    static ACCESS_ALLOWED_ACE_TYPE := 0x00
    static ACCESS_ALLOWED_CALLBACK_ACE_TYPE := 0x09
    static INHERIT_ONLY_ACE := 0x08
    ; FILE_WRITE_DATA/ADD_FILE, FILE_APPEND_DATA/ADD_SUBDIRECTORY, FILE_WRITE_EA,
    ; FILE_DELETE_CHILD, FILE_WRITE_ATTRIBUTES, DELETE, WRITE_DAC, WRITE_OWNER,
    ; GENERIC_WRITE, GENERIC_ALL.
    static WRITE_ACCESS_MASK := 0x00000002 | 0x00000004 | 0x00000010 | 0x00000040
        | 0x00000100 | 0x00010000 | 0x00040000 | 0x00080000 | 0x40000000
        | 0x10000000
    static TRUSTED_SIDS := Map(
        "s-1-5-18", true,                    ; Local System
        "s-1-5-32-544", true,                ; Administrators
        "s-1-3-0", true,                     ; CREATOR OWNER; inert on an existing object
        "s-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464", true)
    static TRUSTED_OWNER_SIDS := Map(
        "s-1-5-18", true,                    ; Local System
        "s-1-5-32-544", true,                ; Administrators
        "s-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464", true)
    grantedTo := ""
    failureReason := ""
    if (Trim(path) = "") {
        failureReason := "An empty path cannot be verified."
        return false
    }
    ownerPointer := 0
    daclPointer := 0
    descriptorPointer := 0
    status := DllCall(
        "Advapi32\GetNamedSecurityInfoW",
        "WStr", path,
        "Int", SE_FILE_OBJECT,
        "UInt", DACL_SECURITY_INFORMATION | OWNER_SECURITY_INFORMATION,
        "Ptr*", &ownerPointer,
        "Ptr", 0,
        "Ptr*", &daclPointer,
        "Ptr", 0,
        "Ptr*", &descriptorPointer,
        "UInt")
    if (status != 0) {
        failureReason := "The security descriptor for " path
            . " could not be read (" status ")."
        return false
    }
    try {
        ; The owner implicitly has WRITE_DAC even when no ACE grants it. A
        ; user-owned directory with an apparently read-only DACL is therefore
        ; still user-reclaimable and is not a safe elevation target.
        if !ownerPointer {
            failureReason := "The owner of " path " could not be read."
            return false
        }
        ownerStringSid := 0
        if !DllCall(
            "Advapi32\ConvertSidToStringSidW",
            "Ptr", ownerPointer,
            "Ptr*", &ownerStringSid,
            "Int") || !ownerStringSid {
            failureReason := "The owner SID for " path " could not be converted."
            return false
        }
        ownerSidText := ""
        try ownerSidText := StrGet(ownerStringSid, "UTF-16")
        finally DllCall("Kernel32\LocalFree", "Ptr", ownerStringSid, "Ptr")
        if !TRUSTED_OWNER_SIDS.Has(StrLower(ownerSidText)) {
            grantedTo := ownerSidText " (owner)"
            return false
        }
        ; A present-but-NULL DACL grants everyone full control.
        if !daclPointer {
            grantedTo := "Everyone (no access control list)"
            return false
        }
        aceCount := NumGet(daclPointer, 4, "UShort")
        Loop aceCount {
            acePointer := 0
            if !DllCall(
                "Advapi32\GetAce",
                "Ptr", daclPointer,
                "UInt", A_Index - 1,
                "Ptr*", &acePointer,
                "Int") || !acePointer {
                failureReason := "ACE " (A_Index - 1) " on " path
                    . " could not be read."
                return false
            }
            aceType := NumGet(acePointer, 0, "UChar")
            aceFlags := NumGet(acePointer, 1, "UChar")
            if (aceType != ACCESS_ALLOWED_ACE_TYPE
                && aceType != ACCESS_ALLOWED_CALLBACK_ACE_TYPE)
                continue
            if (aceFlags & INHERIT_ONLY_ACE)
                continue
            accessMask := NumGet(acePointer, 4, "UInt")
            if !(accessMask & WRITE_ACCESS_MASK)
                continue
            stringSid := 0
            if !DllCall(
                "Advapi32\ConvertSidToStringSidW",
                "Ptr", acePointer + 8,
                "Ptr*", &stringSid,
                "Int") || !stringSid {
                failureReason := "The SID for ACE " (A_Index - 1)
                    . " on " path " could not be converted."
                return false
            }
            sidText := ""
            try sidText := StrGet(stringSid, "UTF-16")
            finally DllCall("Kernel32\LocalFree", "Ptr", stringSid, "Ptr")
            if TRUSTED_SIDS.Has(StrLower(sidText))
                continue
            grantedTo := sidText
            return false
        }
        return true
    } finally {
        DllCall("Kernel32\LocalFree", "Ptr", descriptorPointer, "Ptr")
    }
}

; ==============================================================================
; Controller-as-mouse primitives
; ==============================================================================
; The three programs read three different input sources -- standalone reads
; XInput, XFE reads RawInput through learned profiles, the helper reads XInput
; from a High-integrity token -- and that is why they are three programs. What
; they do with the RESULT was identical in all three, written out three times.
;
; Everything is a parameter. Nothing here reads a global, which is what lets the
; helper compile against it; the speed choice, the scroll rate limit and the
; gating all stay with the caller, because those genuinely differ.

; Discard every press/hold tracker, so a button held across an interruption
; cannot complete a Short or Long the user never finished.
;
; Iterates a fixed definition list rather than enumerating downTick, matching the
; decision already recorded in standalone's elevated-foreground handler: assigning
; to existing keys while enumerating a Map is legal in AutoHotkey, but a list
; cannot be got wrong later by someone adding a key.
;
; The per-tree edge scalars stay at the call sites on purpose. Standalone clears
; prevViewDown everywhere, XFE clears previousViewDown and viewWasDown at some
; sites and neither at others, and the helper clears previousButtons. Folding any
; of them in here would change behaviour at the sites that deliberately do not
; reset them.
; The hold tables start every poll with a key for every button.
;
; Both loops ran on EVERY tick and did the same thing in a different order --
; standalone primed downTick and longFired inside one loop and then the two
; triggers in four separate ifs, XFE in the same loop and then two pairs. The
; poll runs twenty times a second in both, so this is the most-executed
; duplicate in the codebase and the least interesting one.
;
; It stays a "prime if absent" rather than an assignment, because these Maps are
; static across ticks: overwriting would discard the press timestamps that Short
; and Long bindings are measured from.
ControllerPrimeHoldTables(downTick, longFired, buttonDefinitions) {
    for definition in buttonDefinitions {
        name := definition[1]
        if !downTick.Has(name)
            downTick[name] := 0
        if !longFired.Has(name)
            longFired[name] := false
    }
    for _, trigger in ["LT", "RT"] {
        if !downTick.Has(trigger)
            downTick[trigger] := 0
        if !longFired.Has(trigger)
            longFired[trigger] := false
    }
}

; Stick deflection below the deadzone reads as no deflection.
;
; ByRef rather than a returned Map, because the callers carry these as four
; plain locals through several hundred lines each and the point of this is to
; delete eight identical lines, not to restructure the poll around them.
;
; TRIGGERS ARE NOT INCLUDED, deliberately. Both trees read LT and RT with their
; own threshold (> 30) at several points, and the companion logs the RAW trigger
; values in its per-edge diagnostic. A deadzone applied here would silently
; change both.
ControllerApplyStickDeadzone(&lx, &ly, &rx, &ry, deadzone) {
    if (Abs(lx) < deadzone)
        lx := 0
    if (Abs(ly) < deadzone)
        ly := 0
    if (Abs(rx) < deadzone)
        rx := 0
    if (Abs(ry) < deadzone)
        ry := 0
}

ResetControllerEdgeState(downTick, longFired, triggerDown, buttonDefinitions) {
    ; Every abort path already calls this, which is exactly the set of places a
    ; held mouse button must not survive. Wiring the release in here rather than
    ; at the call sites is the whole reason the seven hand-copied blocks in
    ; standalone were collapsed into one body first.
    ReleaseControllerMouseButtons()
    for definition in buttonDefinitions {
        name := definition[1]
        downTick[name] := 0
        longFired[name] := false
    }
    downTick["LT"] := 0, longFired["LT"] := false, triggerDown["LT"] := false
    downTick["RT"] := 0, longFired["RT"] := false, triggerDown["RT"] := false
}

; Right stick -> relative cursor movement. Returns true if the cursor was asked
; to move, so a caller can tell "no input" from "input too small to register".
;
; The caller applies its own deadzone before calling and decides `speed`,
; including whether a trigger is acting as the fast modifier -- all three read
; that multiplier from their own settings.
; Moves the cursor for one poll tick. `pixelsPerSecond` is the speed at full
; deflection -- a VELOCITY, not a per-tick distance, and that is the fix.
;
; This used to be `Round((stick / 32767) * speed)` with speed meaning "pixels per
; poll tick", which made the cursor's speed depend on how often the timer happened
; to fire. Two things followed, and together they are the whole of the jitter:
;
; 1. WINDOWS TIMERS ARE QUANTISED TO ~15.625 ms unless a process raises the
;    resolution, and nothing here does. A timer fires on the first tick boundary
;    at or after its interval, so the old 16 ms request -- 0.375 ms past a
;    boundary -- could not fire at 15.625 and waited for 31.25. The poll ran at
;    about 32 Hz while the setting said 62.5, and any scheduling noise flipped it
;    between one boundary and two.
;
; 2. A fixed distance PER TICK turns uneven timing into uneven distance. Ticks
;    arriving 15.6, 31.2, 31.2, 15.6 ms apart moved the cursor the same amount
;    each time, so it visibly stepped along the path rather than travelling it.
;
; Scaling by measured elapsed time fixes both: a late tick moves proportionally
; further, so on-screen velocity stays constant no matter how the timer behaves,
; and the poll interval becomes a smoothness control rather than a speed control.
;
; The sub-pixel carry is what makes the smaller per-tick distances usable. Deltas
; now land well under a pixel at low deflection, and rounding each tick
; independently would throw that away and re-quantise the motion this function
; exists to smooth. The remainder is kept and added to the next tick instead.
;
; Carry is per-axis and is DROPPED when the stick centres, so a fraction left over
; from the last movement cannot leak into the first pixel of the next one.
ApplyControllerMouseMove(stickX, stickY, pixelsPerSecond) {
    static lastTick := 0
    static carryX := 0.0
    static carryY := 0.0
    now := A_TickCount
    elapsedMs := lastTick ? now - lastTick : 0
    lastTick := now
    if (stickX = 0 && stickY = 0) {
        carryX := 0.0
        carryY := 0.0
        return false
    }
    ; A first tick, a clock that went backwards, or a gap left by a dialog, a
    ; suspend or a stalled message loop. Translating an absence of any length into
    ; one proportional jump is exactly the behaviour being removed, so the step is
    ; capped rather than trusted.
    if (elapsedMs <= 0 || elapsedMs > 100)
        elapsedMs := 16
    seconds := elapsedMs / 1000.0
    carryX += (stickX / 32767.0) * pixelsPerSecond * seconds
    ; Screen Y grows downward and the stick's Y grows upward.
    carryY += (-stickY / 32767.0) * pixelsPerSecond * seconds
    deltaX := Round(carryX)
    deltaY := Round(carryY)
    carryX -= deltaX
    carryY -= deltaY
    if (deltaX = 0 && deltaY = 0)
        return false
    try MouseMove(deltaX, deltaY, 0, "R")
    return true
}

; Left stick Y -> wheel. The RATE LIMIT stays with the caller: each program keeps
; its own last-scroll tick, and passing that state in would be more plumbing than
; the two lines it saves.
ApplyControllerMouseScroll(stickY, steps) {
    if (stickY = 0)
        return false
    Loop steps
        try Send(stickY > 0 ? "{WheelUp}" : "{WheelDown}")
    return true
}

; ==============================================================================
; Synthetic mouse button ledger
; ==============================================================================
; Hold-to-drag needs a mouse button to stay DOWN across many poll ticks, which
; means the process is carrying state the user cannot see. A stuck LButton in a
; Winlogon shell replacement is unrecoverable without a keyboard, so the ledger
; exists to make "release everything" a single call that any abort path can make
; without knowing what is held.
;
; The ledger is a static inside a function rather than a global, because this
; file may not declare globals -- that invariant is what lets the helper include
; it. A Map is an object, so every caller mutates the same one.
;
; Nothing here logs. Common calls nothing outside itself, so the release
; functions REPORT what they released and the caller writes it to its own log in
; its own format.
ControllerHeldMouseButtons() {
    static held := Map()
    return held
}

; Press a synthetic mouse button and record when. Idempotent: pressing something
; already held changes nothing, so a poll loop can call it every tick.
HoldControllerMouseButton(button) {
    held := ControllerHeldMouseButtons()
    if held.Has(button)
        return false
    try SendInput("{" button " down}")
    held[button] := A_TickCount
    return true
}

; Release everything recorded, and return a comma-separated list of what was
; released ("" if nothing). Idempotent and safe to call from anywhere, including
; an exit handler or an uncaught-error handler.
;
; The ledger entry is removed BEFORE the SendInput, so a throw inside SendInput
; cannot leave a name recorded as held forever and make every later release a
; no-op. Releasing a button that was not down is harmless; believing a button is
; held when nothing will release it is not.
ReleaseControllerMouseButtons() {
    held := ControllerHeldMouseButtons()
    if (held.Count = 0)
        return ""
    names := []
    for button, _ in held.Clone() {
        held.Delete(button)
        names.Push(button)
        try SendInput("{" button " up}")
    }
    result := ""
    for _, name in names
        result .= (result = "" ? "" : ", ") name
    return result
}

; The failsafe, and it is deliberately not the same mechanism as the abort paths.
;
; ResetControllerEdgeState covers every path THROUGH the poll loop. It does not
; cover the poll loop stopping -- a suspended timer, a thread that never returns,
; a settings reload that throws. Each program arms this on an independent timer
; so a held button has a bound on its lifetime no matter what happens to the
; loop that pressed it. Returns what it released, or "".
ExpireControllerMouseButtons(maxHeldMs) {
    held := ControllerHeldMouseButtons()
    if (held.Count = 0)
        return ""
    now := A_TickCount
    expired := []
    for button, pressedTick in held.Clone() {
        if (now - pressedTick < maxHeldMs)
            continue
        held.Delete(button)
        expired.Push(button)
        try SendInput("{" button " up}")
    }
    result := ""
    for _, name in expired
        result .= (result = "" ? "" : ", ") name
    return result
}

; Which binding turns a button into a press-and-hold rather than a tap.
;
; Left click only. Nobody drags with the right button, and leaving it atomic
; halves the surface of a change whose worst failure is a mouse button stuck
; down. The rule follows the BINDING, not the button, so moving Left click to
; another button moves drag with it.
;
; This is asked in the poll loop, never inside a binding executor. Those have
; press-only callers -- standalone's Settings pointer fires RB.Short on press
; with nothing that would ever see the release -- so a button-down issued there
; would never be lifted, inside the Settings window, which is the one place a
; user has no other pointer.
ControllerBindingHoldsMouseButton(bindingValue) {
    return StrLower(Trim(bindingValue)) = "builtin:leftclick"
}

; ==============================================================================
; Primary display: modes, DisplayConfig, scale and HDR
; ==============================================================================
; Windows API plumbing with no product opinion in it. It was written twice and
; drifted -- not in behaviour anyone chose, but in log severity, log wording and
; how much it bothered to say when something failed. The companion's copies had
; the better diagnostics and the correct Warning severity; those are the ones
; kept, so unifying these fixed four small gaps rather than only deleting lines.
;
; Everything the CALLER decides -- which mode is selected, what to tell the user,
; when to reflow a menu -- stays with the caller. These only ask Windows.

GetPrimaryDisplayModes() {
    modes := []
    seen := Map()
    modeIndex := 0
    ; Drivers commonly enumerate low-resolution/refresh combinations first. A
    ; fixed 512-entry ceiling cut modern TV/GPU mode tables off around 1280x1024,
    ; before their 1440p and 4K entries were reached. EnumDisplaySettings returns
    ; zero at the real end of the list, so let the API define the boundary.
    Loop {
        dm := Buffer(220, 0)
        NumPut("UShort", 220, dm, 68)
        ok := false
        try ok := DllCall("User32\EnumDisplaySettingsW", "Ptr", 0, "UInt", modeIndex, "Ptr", dm, "Int")
        if (!ok)
            break
        modeIndex += 1

        width := NumGet(dm, 172, "UInt")
        height := NumGet(dm, 176, "UInt")
        frequency := NumGet(dm, 184, "UInt")
        bpp := NumGet(dm, 168, "UInt")
        if (width < 640 || height < 480 || frequency < 24 || bpp < 24)
            continue

        key := width "x" height "@" frequency
        if seen.Has(key)
            continue
        seen[key] := true
        modes.Push(Map("width", width, "height", height, "frequency", frequency))
    }

    LogLine("Display modes: Windows reported " modeIndex
        . " entries; SteamShell retained " modes.Length " compatible combinations.")

    ; Stable insertion sort: resolution first, then refresh rate.
    sorted := []
    for _, mode in modes {
        insertAt := sorted.Length + 1
        for pos, existing in sorted {
            lhs := mode["width"] * mode["height"]
            rhs := existing["width"] * existing["height"]
            if (lhs < rhs || (lhs = rhs && mode["frequency"] < existing["frequency"])) {
                insertAt := pos
                break
            }
        }
        sorted.InsertAt(insertAt, mode)
    }
    return sorted
}

ApplyPrimaryDisplayMode(mode) {
    if !IsObject(mode)
        return false
    dm := Buffer(220, 0)
    NumPut("UShort", 220, dm, 68)
    NumPut("UInt", 0x580000, dm, 72) ; width | height | display frequency
    NumPut("UInt", mode["width"], dm, 172)
    NumPut("UInt", mode["height"], dm, 176)
    NumPut("UInt", mode["frequency"], dm, 184)
    try {
        result := DllCall("User32\ChangeDisplaySettingsExW"
            , "Ptr", 0, "Ptr", dm, "Ptr", 0, "UInt", 0, "Ptr", 0, "Int")
        return (result = 0)
    } catch {
        return false
    }
}

; Resolves the primary GDI display to its active DisplayConfig source. The
; source adapter LUID and id are required by the per-display scale packets.
GetPrimaryDisplayConfigSource() {
    primaryName := GetPrimaryDisplayDeviceName()
    if (primaryName = "")
        return 0
    flags := 0x2 ; QDC_ONLY_ACTIVE_PATHS
    Loop 3 {
        pathCount := 0
        modeCount := 0
        result := -1
        try result := DllCall("User32\GetDisplayConfigBufferSizes",
            "UInt", flags, "UInt*", &pathCount, "UInt*", &modeCount, "Int")
        if (result != 0 || pathCount < 1)
            return 0
        ; DISPLAYCONFIG_PATH_INFO is 72 bytes and DISPLAYCONFIG_MODE_INFO is 64
        ; bytes in this required 64-bit build.
        paths := Buffer(pathCount * 72, 0)
        modes := Buffer(Max(1, modeCount) * 64, 0)
        try result := DllCall("User32\QueryDisplayConfig",
            "UInt", flags, "UInt*", &pathCount, "Ptr", paths,
            "UInt*", &modeCount, "Ptr", modes, "Ptr", 0, "Int")
        if (result = 122) ; ERROR_INSUFFICIENT_BUFFER: topology changed; retry.
            continue
        if (result != 0)
            return 0
        Loop pathCount {
            pathOffset := (A_Index - 1) * 72
            adapterLow := NumGet(paths, pathOffset, "UInt")
            adapterHigh := NumGet(paths, pathOffset + 4, "Int")
            sourceId := NumGet(paths, pathOffset + 8, "UInt")
            ; DISPLAYCONFIG_SOURCE_DEVICE_NAME: 20-byte header + WCHAR[32].
            sourceName := Buffer(84, 0)
            NumPut("UInt", 1, sourceName, 0) ; GET_SOURCE_NAME
            NumPut("UInt", 84, sourceName, 4)
            NumPut("UInt", adapterLow, sourceName, 8)
            NumPut("Int", adapterHigh, sourceName, 12)
            NumPut("UInt", sourceId, sourceName, 16)
            getResult := -1
            try getResult := DllCall("User32\DisplayConfigGetDeviceInfo",
                "Ptr", sourceName, "Int")
            if (getResult != 0)
                continue
            gdiName := StrGet(sourceName.Ptr + 20, 32, "UTF-16")
            if (StrLower(gdiName) = StrLower(primaryName)) {
                return Map(
                    "adapterLow", adapterLow,
                    "adapterHigh", adapterHigh,
                    "sourceId", sourceId,
                    "targetAdapterLow", NumGet(paths, pathOffset + 20, "UInt"),
                    "targetAdapterHigh", NumGet(paths, pathOffset + 24, "Int"),
                    "targetId", NumGet(paths, pathOffset + 28, "UInt"),
                    "name", gdiName
                )
            }
        }
        return 0
    }
    return 0
}

; Reads the scale range used by Windows Settings for the primary display.
;
; The CCD header and DisplayConfig calls are public, but Windows does not publish
; the GET_DPI_SCALE (-3) and SET_DPI_SCALE (-4) packet definitions in the SDK.
; They are used defensively here: any unsupported/error response simply removes
; the Scale row and leaves resolution/refresh controls working as before.
GetPrimaryDisplayScale() {
    static warned := false
    source := GetPrimaryDisplayConfigSource()
    if !IsObject(source) {
        if !warned {
            warned := true
            LogLine("Display scale: primary DisplayConfig source is unavailable.",
                "Warning")
        }
        return 0
    }
    packet := Buffer(32, 0)
    NumPut("UInt", 0xFFFFFFFD, packet, 0) ; DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE
    NumPut("UInt", 32, packet, 4)
    NumPut("UInt", source["adapterLow"], packet, 8)
    NumPut("Int", source["adapterHigh"], packet, 12)
    NumPut("UInt", source["sourceId"], packet, 16)
    result := -1
    try result := DllCall("User32\DisplayConfigGetDeviceInfo",
        "Ptr", packet, "Int")
    if (result != 0) {
        if !warned {
            warned := true
            LogLine("Display scale: Windows rejected GET_DPI_SCALE (error "
                . result ").", "Warning")
        }
        return 0
    }
    minimum := NumGet(packet, 20, "Int")
    current := NumGet(packet, 24, "Int")
    maximum := NumGet(packet, 28, "Int")
    levels := DisplayScaleLevels()
    count := maximum - minimum + 1
    currentIndex := current - minimum + 1
    if (count < 1 || count > levels.Length
        || currentIndex < 1 || currentIndex > count) {
        if !warned {
            warned := true
            LogLine("Display scale: Windows returned an unsupported range "
                . minimum ".." maximum " with current " current ".", "Warning")
        }
        return 0
    }
    warned := false
    options := []
    Loop count
        options.Push(levels[A_Index])
    return Map(
        "percent", options[currentIndex],
        "options", options,
        "minimum", minimum,
        "current", current,
        "maximum", maximum
    )
}

ApplyPrimaryDisplayScale(percent) {
    info := GetPrimaryDisplayScale()
    if !IsObject(info)
        return false
    selectedIndex := 0
    for index, option in info["options"] {
        if (option = percent) {
            selectedIndex := index
            break
        }
    }
    if !selectedIndex
        return false
    source := GetPrimaryDisplayConfigSource()
    if !IsObject(source)
        return false
    packet := Buffer(24, 0)
    NumPut("UInt", 0xFFFFFFFC, packet, 0) ; DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE
    NumPut("UInt", 24, packet, 4)
    NumPut("UInt", source["adapterLow"], packet, 8)
    NumPut("Int", source["adapterHigh"], packet, 12)
    NumPut("UInt", source["sourceId"], packet, 16)
    NumPut("Int", info["minimum"] + selectedIndex - 1, packet, 20)
    result := -1
    try result := DllCall("User32\DisplayConfigSetDeviceInfo",
        "Ptr", packet, "Int")
    if (result = 0)
        LogLine("Display scale: primary display set to " percent "%.")
    else
        LogLine("Display scale: SET_DPI_SCALE failed with error " result ".",
            "Warning")
    return result = 0
}

; Reads the primary target's documented Advanced Color state. On Windows 10/11,
; advancedColorSupported identifies an HDR-capable path and
; advancedColorEnabled is the live "Use HDR" state.
GetPrimaryHdrState() {
    static warned := false
    path := GetPrimaryDisplayConfigSource()
    if !IsObject(path)
        return 0
    ; DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO:
    ; 20-byte header, 4-byte flags, color encoding, bits per color channel.
    packet := Buffer(32, 0)
    NumPut("UInt", 9, packet, 0) ; GET_ADVANCED_COLOR_INFO
    NumPut("UInt", 32, packet, 4)
    NumPut("UInt", path["targetAdapterLow"], packet, 8)
    NumPut("Int", path["targetAdapterHigh"], packet, 12)
    NumPut("UInt", path["targetId"], packet, 16)
    result := -1
    try result := DllCall("User32\DisplayConfigGetDeviceInfo",
        "Ptr", packet, "Int")
    if (result != 0) {
        if !warned {
            warned := true
            LogLine("HDR: GET_ADVANCED_COLOR_INFO failed with error "
                . result ".", "Warning")
        }
        return 0
    }
    warned := false
    flags := NumGet(packet, 20, "UInt")
    return Map(
        "supported", (flags & 0x1) != 0,
        "enabled", (flags & 0x2) != 0,
        "wideColorEnforced", (flags & 0x4) != 0,
        "forceDisabled", (flags & 0x8) != 0
    )
}

ApplyPrimaryHdrState(enabled) {
    path := GetPrimaryDisplayConfigSource()
    if !IsObject(path)
        return false
    ; DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE:
    ; 20-byte header followed by the enableAdvancedColor bit.
    packet := Buffer(24, 0)
    NumPut("UInt", 10, packet, 0) ; SET_ADVANCED_COLOR_STATE
    NumPut("UInt", 24, packet, 4)
    NumPut("UInt", path["targetAdapterLow"], packet, 8)
    NumPut("Int", path["targetAdapterHigh"], packet, 12)
    NumPut("UInt", path["targetId"], packet, 16)
    NumPut("UInt", enabled ? 1 : 0, packet, 20)
    result := -1
    try result := DllCall("User32\DisplayConfigSetDeviceInfo",
        "Ptr", packet, "Int")
    if (result = 0)
        LogLine("HDR: primary display turned " (enabled ? "on." : "off."))
    else
        LogLine("HDR: SET_ADVANCED_COLOR_STATE failed with error "
            . result ".", "Warning")
    return result = 0
}

; ==============================================================================
; INI VALUE CLEANING
; ==============================================================================
; AutoHotkey's IniRead returns everything after the "=", including any trailing
; comment. So a documented settings file needs this before the value is parsed,
; or `EnableAutoMouseMode=true  ; turns it on` reads as the string
; "true  ; turns it on", which is not "true".
;
; All three programs had their own copy. Standalone's was the only complete one,
; which is why standalone's sample INI can document 122 of its 174 settings and
; XFE's could document 3 of 104 -- the comments were not the problem, the reader
; was. One definition now, in the file every program compiles.
;
; A ";" or "#" only starts a comment at the start of the value or after
; whitespace. That is deliberate: it keeps paths, pipe-separated lists and
; Send: bindings that contain those characters intact.
;
; blankUsesDefault distinguishes "the key is missing" from "the key is present
; and deliberately empty". Optional shortcuts and paths rely on the second
; meaning something, so a present-but-empty value must be allowed to stay empty.
; "Is a process with this name running", answered from a held handle instead of a
; walk of the process table.
;
; ProcessExist(name) enumerates every process on the machine to return one
; boolean. That is fine occasionally and it was being asked twice a second
; forever, against a table of several hundred entries on a normal desktop.
;
; The handle path is O(1) AND strictly more accurate. A SYNCHRONIZE handle to a
; known PID signals the moment that exact process exits; the name walk can only
; say whether SOMETHING called steam.exe exists, which is a different question the
; instant Steam restarts. Windows will not recycle a PID while a handle to it is
; open, so the handle cannot silently come to mean a different process.
;
; FALLS BACK ON ANY DOUBT. OpenProcess can be refused, and a caller that drives
; something as disruptive as restoring the desktop shell must not read a refusal
; as an exit. Every path that is not a clean, positive answer from the handle ends
; at ProcessExist, which is the behaviour this replaces -- so the worst case is
; the old cost, not a wrong answer.
;
; No globals, no calls outside this file: the handle lives in a static, keyed by
; name so a second caller cannot disturb the first.
ProcessRunningByHandle(exeName) {
    static SYNCHRONIZE := 0x00100000
    static WAIT_TIMEOUT := 0x00000102
    static handles := Map()

    exeName := StrLower(Trim(exeName))
    if (exeName = "")
        return false

    if handles.Has(exeName) {
        entry := handles[exeName]
        waitResult := -1
        try waitResult := DllCall("Kernel32\WaitForSingleObject",
            "Ptr", entry["handle"], "UInt", 0, "UInt")
        ; Still running: the only fast path, and the common one.
        if (waitResult = WAIT_TIMEOUT)
            return true
        ; Signalled means exited. Anything else means the handle can no longer be
        ; trusted. Both end the same way -- drop it and re-resolve below.
        try DllCall("Kernel32\CloseHandle", "Ptr", entry["handle"])
        handles.Delete(exeName)
    }

    pid := 0
    try pid := ProcessExist(exeName)
    if !pid
        return false

    handle := 0
    try handle := DllCall("Kernel32\OpenProcess",
        "UInt", SYNCHRONIZE, "Int", false, "UInt", pid, "Ptr")
    ; The process is running either way -- ProcessExist just said so. Failing to
    ; open it only costs the optimisation, so say true and try again next time.
    if handle
        handles[exeName] := Map("handle", handle, "pid", pid)
    return true
}

CleanIniValue(v, default := "", blankUsesDefault := true) {
    v := Trim(v)
    if (v = "")
        return blankUsesDefault ? default : ""
    ; `;` starts a trailing comment anywhere; `#` only at the start of the value.
    ;
    ; The pattern was "(^|\s)[;#]", which treated any whitespace-preceded # as a
    ; comment and truncated the value there. That is fine for an INI line written
    ; by hand and wrong for the values this product actually stores: window titles
    ; and executable lists. "Portal #2" in an Always Focus or whitelist entry was
    ; silently saved and re-read as "Portal", matching a window that does not
    ; exist. A leading # is still honoured, because that is a real convention and
    ; costs nothing to keep.
    pos := RegExMatch(v, "(^|\s);|^#")
    if (pos)
        v := pos = 1 ? "" : Trim(SubStr(v, 1, pos - 1))
    if (v = "")
        return blankUsesDefault ? default : ""
    return v
}

NormalizeKeyForDisplay(keyName) {
    k := keyName
    if (k = "Escape")
        return "Esc"
    if (k = "Return")
        return "Enter"
    return k
}

; Path normalisation, shared because RTSS path resolution needs it and both
; programs had a version. They were NOT equivalent: the companion's only trimmed
; whitespace and quotes, while this one also expands %VAR% tokens and resolves a
; relative path against the script directory. The more capable one wins, so the
; companion gains environment-variable support in [RTSS] Path that it never had.

ExpandEnvVars(s) {
    ; Expands %VAR% tokens.
    out := ""
    pos := 1
    while (pos <= StrLen(s)) {
    p1 := InStr(s, "%", , pos)
    if (!p1) {
    out .= SubStr(s, pos)
    break
    }
    p2 := InStr(s, "%", , p1 + 1)
    if (!p2) {
    out .= SubStr(s, pos)
    break
    }
    out .= SubStr(s, pos, p1 - pos)
    var := SubStr(s, p1 + 1, p2 - p1 - 1)

    val := ""
    try {
    val := EnvGet(var)
    } catch {
    val := ""
    }

    out .= (val != "" ? val : "%" var "%")
    pos := p2 + 1
    }
    return out
}

NormalizeMediaPath(p) {
    ; Trim whitespace and optional surrounding quotes.
    p := Trim(p)
    if (p = "")
        return ""
    if (SubStr(p, 1, 1) = '"' && SubStr(p, -1) = '"')
        p := SubStr(p, 2, StrLen(p) - 2)
    p := Trim(p)

    ; Expand environment variables like %USERPROFILE%
    p := ExpandEnvVars(p)

    ; If relative, resolve against script dir
    if (!RegExMatch(p, "i)^[A-Z]:\\") && !InStr(p, "\\") && !InStr(p, "://")) {
    p := A_ScriptDir "\" p
    }
    return p
}

; ==============================================================================
; The XFE logon task
; ==============================================================================
; ONE definition, because there were two and they disagreed.
;
; Setup Assistant registered "SteamShell XFE Companion" with no logon delay;
; XFE's own Settings -> Advanced registered "SteamShell-XFE" with a 10-second
; delay. Different names, so they were different tasks, with four consequences:
;
;   - After a Setup install, XFE's "Check Logon Task" queried its own name,
;     found nothing, and reported no task registered while one existed.
;   - Pressing "Create Logon Task" then made a SECOND task, and two companions
;     started at sign-in.
;   - "Remove Logon Task" deleted only XFE's own; Setup's survived, so "removed"
;     did not remove.
;   - README-XFE documents a 10-second logon delay to let the shell and Xbox FSE
;     come up first. Setup's task had none -- and Setup is the recommended route,
;     so the documented behaviour was false for most installs.
;
; The name kept is Setup Assistant's, matching "SteamShell Elevated Input
; Helper". The XML kept is XFE's, because its differences are the ones with
; stated reasons: the logon delay, AllowHardTerminate=false, and an element
; order copied from a real Task Scheduler export.
XfeLogonTaskName() {
    return "SteamShell XFE Companion"
}

; The name XFE used to register under. Both programs delete it whenever they
; register or remove, so a machine that has been through either route converges
; on one task instead of accumulating two.
XfeLogonTaskLegacyName() {
    return "SteamShell-XFE"
}

; "Elevated Input Helper", matching the shell's task, because that is what the
; helper IS in both products.
;
; It was "Elevated RTSS Helper", from when this product's helper did the frame
; cap and nothing else. That stopped being true when the helper gained elevated
; controller input: SteamShell-Helper.ahk's --product=xfe branch sets
; HelperGeometryEnabled := false and NOTHING else, so input runs here exactly as
; it does for the shell. A registered task's name is the one place a user sees
; what the thing does, and this one named a third of it.
XfeElevatedHelperTaskName() {
    return "SteamShell XFE Elevated Input Helper"
}

; The name registered before that correction. Machines already carry it, so
; every registration deletes it first -- the same shape XfeLogonTaskLegacyName
; exists for, and for the same reason: leaving it behind means an orphaned
; HighestAvailable task pointing at a helper nothing will ever start through it.
XfeElevatedHelperTaskLegacyName() {
    return "SteamShell XFE Elevated RTSS Helper"
}

; account may be a SID or DOMAIN\User; both callers resolve a SID first because
; it survives a user rename. arguments is "" for a compiled build.
XfeLogonTaskXml(account, command, arguments, workingDirectory) {
    accountXml := XmlEscapeText(account)
    argumentsXml := arguments != ""
        ? "<Arguments>" XmlEscapeText(arguments) "</Arguments>`r`n      "
        : ""
    return ""
        . "<?xml version=" Chr(34) "1.0" Chr(34) " encoding=" Chr(34) "UTF-16" Chr(34) "?>`r`n"
        . "<Task version=" Chr(34) "1.2" Chr(34)
            . " xmlns=" Chr(34) "http://schemas.microsoft.com/windows/2004/02/mit/task" Chr(34) ">`r`n"
        . "  <RegistrationInfo>`r`n"
        . "    <Description>Starts the SteamShell XFE controller companion at logon.</Description>`r`n"
        . "  </RegistrationInfo>`r`n"
        . "  <Triggers>`r`n"
        . "    <LogonTrigger>`r`n"
        . "      <Enabled>true</Enabled>`r`n"
        . "      <UserId>" accountXml "</UserId>`r`n"
        ; Ten seconds so the shell and Xbox FSE are up first. Documented in
        ; README-XFE; Setup Assistant's own copy of this XML omitted it, which is
        ; the defect that prompted merging the two.
        . "      <Delay>PT10S</Delay>`r`n"
        . "    </LogonTrigger>`r`n"
        . "  </Triggers>`r`n"
        . "  <Principals>`r`n"
        . "    <Principal id=" Chr(34) "Author" Chr(34) ">`r`n"
        . "      <UserId>" accountXml "</UserId>`r`n"
        . "      <LogonType>InteractiveToken</LogonType>`r`n"
        . "      <RunLevel>LeastPrivilege</RunLevel>`r`n"
        . "    </Principal>`r`n"
        . "  </Principals>`r`n"
        ; Element order matches what Task Scheduler itself emits when exporting a
        ; task. The schema is order-sensitive and rejects the whole file with an
        ; unhelpful "task XML is malformed" if elements are rearranged, so this
        ; sequence is copied from a known-good export rather than chosen.
        . "  <Settings>`r`n"
        . "    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>`r`n"
        ; The two settings this whole XML exists for: the shorthand
        ; schtasks /sc onlogon form inherits defaults that refuse to start on
        ; battery, which on a handheld means the task never runs undocked.
        . "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>`r`n"
        . "    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>`r`n"
        . "    <AllowHardTerminate>false</AllowHardTerminate>`r`n"
        . "    <StartWhenAvailable>false</StartWhenAvailable>`r`n"
        . "    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>`r`n"
        . "    <IdleSettings>`r`n"
        . "      <StopOnIdleEnd>false</StopOnIdleEnd>`r`n"
        . "      <RestartOnIdle>false</RestartOnIdle>`r`n"
        . "    </IdleSettings>`r`n"
        . "    <AllowStartOnDemand>true</AllowStartOnDemand>`r`n"
        . "    <Enabled>true</Enabled>`r`n"
        . "    <Hidden>false</Hidden>`r`n"
        . "    <RunOnlyIfIdle>false</RunOnlyIfIdle>`r`n"
        . "    <WakeToRun>false</WakeToRun>`r`n"
        ; PT0S is "no limit". The default is 72 hours, which would terminate the
        ; companion mid-session on a machine that stays logged in.
        . "    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>`r`n"
        . "    <Priority>7</Priority>`r`n"
        . "  </Settings>`r`n"
        . "  <Actions Context=" Chr(34) "Author" Chr(34) ">`r`n"
        . "    <Exec>`r`n"
        . "      <Command>" XmlEscapeText(command) "</Command>`r`n"
        . "      " argumentsXml "<WorkingDirectory>"
            . XmlEscapeText(workingDirectory) "</WorkingDirectory>`r`n"
        . "    </Exec>`r`n"
        . "  </Actions>`r`n"
        . "</Task>`r`n"
}

; XML escaping for the task definitions. The companion's copy escaped four
; entities and the shell's five -- the apostrophe was missing from one of
; them, which a user name containing one would have exposed.
XmlEscapeText(value) {
    value := StrReplace(value, "&", "&amp;")
    value := StrReplace(value, "<", "&lt;")
    value := StrReplace(value, ">", "&gt;")
    value := StrReplace(value, Chr(34), "&quot;")
    value := StrReplace(value, "'", "&apos;")
    return value
}

; An on-demand, no-trigger task that starts the elevated helper without a UAC
; prompt. Both products register one; the security precondition is identical and
; is checked by the CALLER before this is ever written to disk.
;
; A UAC consent dialog runs on the secure desktop, where no user-mode process
; can inject input -- so on a controller-only handheld a prompt is not an
; annoyance, it is unanswerable. That is the entire reason this exists.
;
; It is safe only because the helper is installed below a Program Files path the
; interactive user cannot write. A task is an UNPROMPTED elevation to whatever
; binary sits at its action path; put that path somewhere replaceable and the
; task becomes a local privilege escalation.
ElevatedHelperTaskXml(account, command, arguments, workingDirectory) {
    accountXml := XmlEscapeText(account)
    argumentsXml := arguments != ""
        ? "<Arguments>" XmlEscapeText(arguments) "</Arguments>`r`n      "
        : ""
    return ""
        . "<?xml version=" Chr(34) "1.0" Chr(34) " encoding=" Chr(34) "UTF-16" Chr(34) "?>`r`n"
        . "<Task version=" Chr(34) "1.2" Chr(34)
            . " xmlns=" Chr(34) "http://schemas.microsoft.com/windows/2004/02/mit/task" Chr(34) ">`r`n"
        . "  <RegistrationInfo>`r`n"
        . "    <Description>Runs the protected SteamShell elevated helper on demand.</Description>`r`n"
        . "  </RegistrationInfo>`r`n"
        . "  <Triggers />`r`n"
        . "  <Principals>`r`n"
        . "    <Principal id=" Chr(34) "Author" Chr(34) ">`r`n"
        . "      <UserId>" accountXml "</UserId>`r`n"
        . "      <LogonType>InteractiveToken</LogonType>`r`n"
        . "      <RunLevel>HighestAvailable</RunLevel>`r`n"
        . "    </Principal>`r`n"
        . "  </Principals>`r`n"
        . "  <Settings>`r`n"
        . "    <MultipleInstancesPolicy>StopExisting</MultipleInstancesPolicy>`r`n"
        . "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>`r`n"
        . "    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>`r`n"
        . "    <AllowHardTerminate>true</AllowHardTerminate>`r`n"
        . "    <StartWhenAvailable>true</StartWhenAvailable>`r`n"
        . "    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>`r`n"
        . "    <IdleSettings>`r`n"
        . "      <StopOnIdleEnd>false</StopOnIdleEnd>`r`n"
        . "      <RestartOnIdle>false</RestartOnIdle>`r`n"
        . "    </IdleSettings>`r`n"
        . "    <AllowStartOnDemand>true</AllowStartOnDemand>`r`n"
        . "    <Enabled>true</Enabled>`r`n"
        . "    <Hidden>true</Hidden>`r`n"
        . "    <RunOnlyIfIdle>false</RunOnlyIfIdle>`r`n"
        . "    <WakeToRun>false</WakeToRun>`r`n"
        . "    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>`r`n"
        . "    <Priority>5</Priority>`r`n"
        . "  </Settings>`r`n"
        . "  <Actions Context=" Chr(34) "Author" Chr(34) ">`r`n"
        . "    <Exec>`r`n"
        . "      <Command>" XmlEscapeText(command) "</Command>`r`n"
        . "      " argumentsXml "<WorkingDirectory>"
            . XmlEscapeText(workingDirectory) "</WorkingDirectory>`r`n"
        . "    </Exec>`r`n"
        . "  </Actions>`r`n"
        . "</Task>`r`n"
}

; ==============================================================================
; Startup programs
; ==============================================================================
; Both programs launch a user's list at startup, and both grew capabilities the
; other lacked: the shell could pass command-line arguments and the companion
; could not; the companion staggered launches, skipped programs already running,
; and actually enforced the window mode, and the shell did none of those. Every
; one of those differences was an accident of writing the feature twice.
;
; The POLICY is shared. The launch primitive is not: the shell launches through
; its verified de-elevating path because it IS the shell, and the companion uses
; a plain Run. Each passes its own launcher in.

; Split "C:\path\app.exe --flag" into target and arguments, honouring quotes.
; The companion had no equivalent, so any entry with arguments failed its
; FileExist check and was silently skipped.
SplitStartupCommandLine(commandLine, &target, &arguments) {
    commandLine := Trim(commandLine)
    target := "", arguments := ""
    if (commandLine = "")
        return false
    if (SubStr(commandLine, 1, 1) = '"') {
        closing := InStr(commandLine, '"', , 2)
        if !closing {
            target := Trim(SubStr(commandLine, 2))
            return target != ""
        }
        target := SubStr(commandLine, 2, closing - 2)
        arguments := Trim(SubStr(commandLine, closing + 1))
        return target != ""
    }
    ; Unquoted: the longest leading run that names a file that exists wins, so a
    ; path with spaces and no quotes still resolves. Falls back to the first
    ; token, which is what a bare "notepad.exe --x" needs.
    parts := StrSplit(commandLine, " ")
    candidate := ""
    Loop parts.Length {
        candidate := candidate = "" ? parts[1] : candidate " " parts[A_Index]
        if FileExist(candidate) {
            target := candidate
            arguments := Trim(SubStr(commandLine, StrLen(candidate) + 1))
            return true
        }
    }
    target := parts[1]
    arguments := Trim(SubStr(commandLine, StrLen(target) + 1))
    return target != ""
}

; How many startup programs either product offers. ONE NUMBER, and it is the
; answer to a question that had four different ones.
;
; The count used to be 40 here and 20 in every other place the shell mentions a
; startup slot -- its Settings editor, its Health Check validation, its category
; reset and the Program1..Program20 block in the INI it ships. So the shell
; LAUNCHED forty and could only show, check or reset twenty: an entry at slot 21
; ran at every boot while being invisible to the editor, absent from the health
; report and untouched by "Restore Category Defaults".
;
; Twenty is the number, chosen by the user: it is what the shipped INI documents,
; what the shell has always presented, and more startup programs than a
; living-room machine has any business launching at sign-in. The companion
; offered forty and now offers twenty; StartupProgramsBeyondSlotCount below is
; what keeps that from being a silent loss.
StartupProgramSlotCount() {
    return 20
}


; Read the configured list, packed: blanks are skipped, so slot numbering is a
; display convenience rather than an order the launcher depends on.
ReadStartupProgramList(readValue) {
    programs := []
    Loop StartupProgramSlotCount() {
        entry := Trim(readValue("Program" A_Index))
        if (entry != "")
            programs.Push(entry)
    }
    return programs
}


; Entries stored past the last slot, which nothing will launch.
;
; The companion accepted up to forty, so an existing settings file can hold
; entries this build no longer reaches. They are NOT deleted -- a saved settings
; file is the user's, and quietly dropping five programs on the first save after
; an update is not a thing a program should do. They are reported instead, by
; name, so the log says what happened and the file can be edited by hand.
;
; The ceiling is the companion's old count. Nothing ever wrote beyond it.
;
; THE MESSAGE IS HERE TOO, not in each product's loader. Both trees reported
; this, in the same words, over lists read the same way -- which is two copies of
; one sentence, and the duplicate check paired them on it within a minute of the
; second one being written.
ReportStartupProgramsBeyondSlotCount(readValue) {
    beyond := []
    index := StartupProgramSlotCount() + 1
    while (index <= 40) {
        if (Trim(readValue("Program" index)) != "")
            beyond.Push("Program" index)
        index += 1
    }
    if (beyond.Length = 0)
        return beyond
    LogLine("Startup programs beyond slot " StartupProgramSlotCount()
        . " are no longer launched and are not shown in Settings: "
        . JoinWith(beyond, ", ")
        . ". They are still in the settings file; move one into a free slot to "
        . "use it.", "Warning")
    return beyond
}

; "hidden" | "minimized" | "normal", from whatever the INI says.
NormalizeStartupWindowMode(mode) {
    mode := StrLower(Trim(mode))
    if (mode = "hidden" || mode = "hide")
        return "hidden"
    if (mode = "minimized" || mode = "min" || mode = "minimised")
        return "minimized"
    return "normal"
}

; Enforce the window mode for a short window after launch.
;
; A single shot immediately after Run is not enough: a program usually creates
; its window well after the launch call returns, and some create a second one.
; The shell had one 200 ms attempt for "hidden" only, so "minimized" did nothing
; at all there. Sweeping until deadlineTick covers both.
;
; Returns true while it still has work to do, so the caller can re-arm its own
; timer without this file owning one.
ApplyStartupWindowModeOnce(exeName, mode, deadlineTick) {
    if (exeName = "" || mode = "normal" || A_TickCount > deadlineTick)
        return false
    windows := []
    try windows := WinGetList("ahk_exe " exeName)
    for _, hwnd in windows {
        state := 0
        try state := WinGetMinMax("ahk_id " hwnd)
        if (mode = "hidden") {
            ; Never touch a window that is already hidden, so a program that
            ; deliberately shows itself later is not fought over repeatedly.
            if DllCall("User32\IsWindowVisible", "Ptr", hwnd, "Int")
                try WinHide("ahk_id " hwnd)
        } else if (mode = "minimized" && state != -1) {
            try WinMinimize("ahk_id " hwnd)
        }
    }
    return true
}

; ==============================================================================
; Process enumeration
; ==============================================================================
; Finding a process by image name, and telling a NEW one from the copies that
; were already running. Both programs now start their elevated helper through a
; scheduled task, and `schtasks /run` reports only whether the task launched --
; not which process it produced -- so the pid has to be found by watching for
; one that was not there a moment ago.
;
; These lived in SteamShell.ahk. The companion's new task path called them and
; they were not in scope, which in AutoHotkey is a LOAD-TIME error: the script
; did not fail to run, it failed to parse, and the validator hung on the modal
; dialog reporting it.

GetPidsByExeName(exeName) {
    pids := []
    exe := StrLower(Trim(exeName))
    if (exe = "")
        return pids
    if !InStr(exe, ".exe")
        exe .= ".exe"

    ; Prefer Toolhelp snapshot enumeration (more reliable than WMI for some launchers)
    snap := DllCall("CreateToolhelp32Snapshot", "UInt", 0x00000002, "UInt", 0, "Ptr") ; TH32CS_SNAPPROCESS
    if (snap = -1 || snap = 0)
        return pids

    size := (A_PtrSize = 8) ? 568 : 556 ; PROCESSENTRY32W
    pe := Buffer(size, 0)
    NumPut("UInt", size, pe, 0)

    if !DllCall("Process32FirstW", "Ptr", snap, "Ptr", pe) {
        DllCall("CloseHandle", "Ptr", snap)
        return pids
    }

    loop {
        pid := NumGet(pe, 8, "UInt")
        name := StrLower(StrGet(pe.Ptr + ((A_PtrSize = 8) ? 44 : 36), "UTF-16"))
        if (name = exe)
            pids.Push(pid)
        if !DllCall("Process32NextW", "Ptr", snap, "Ptr", pe)
            break
    }

    DllCall("CloseHandle", "Ptr", snap)
    return pids
}

CaptureExecutablePidSet(executable) {
    existing := Map()
    if (executable = "")
        return existing
    SplitPath(executable, &exeName)
    if (exeName = "")
        return existing
    pids := []
    try pids := GetPidsByExeName(exeName)
    for _, existingPid in pids {
        processPath := ""
        try processPath := ProcessGetPath(existingPid)
        if (processPath != ""
            && StrLower(processPath) = StrLower(executable))
            existing[existingPid] := true
    }
    return existing
}

WaitForNewExecutablePid(executable, existingPids, timeoutMs := 2500) {
    if (executable = "")
        return 0
    SplitPath(executable, &exeName)
    if (exeName = "")
        return 0
    deadline := A_TickCount + Max(0, timeoutMs)
    Loop {
        pids := []
        try pids := GetPidsByExeName(exeName)
        for _, candidatePid in pids {
            processPath := ""
            try processPath := ProcessGetPath(candidatePid)
            if (!existingPids.Has(candidatePid)
                && processPath != ""
                && StrLower(processPath) = StrLower(executable))
                return candidatePid
        }
        if (A_TickCount >= deadline)
            break
        Sleep 100
    }
    return 0
}

; ==============================================================================
; TWO HELPERS THAT WERE THE SAME FUNCTION UNDER TWO NAMES
; ==============================================================================
; Found by cross-comparing standalone-only against XFE-only functions for the
; same LOGIC under different NAMES -- the one direction the parity checks never
; looked, because they match on name first. Both bodies were byte-identical;
; only "QuickMenuText" versus "Text", and "SteamShell" versus "Companion",
; had kept them apart.

ShortenText(text, maxChars) {
    text := Trim(text)
    if (StrLen(text) <= maxChars)
        return text
    return SubStr(text, 1, Max(1, maxChars - 1)) "…"
}

; Releases a held synthetic mouse button before anything else, because an
; uncaught error must not leave a button down in the Windows shell with no
; keyboard. Returns 0 so AutoHotkey still handles the error as it would have.
;
; The elevated helper deliberately does NOT use this one: its own handler exits
; the process and returns 1 to suppress AutoHotkey's dialog, because a modal
; error box on a shell desktop cannot be dismissed with a controller.
HandleUncaughtError(thrown, mode) {
    try ReleaseControllerMouseButtons()
    message := "an unknown error"
    try message := thrown.Message " (" thrown.File ":" thrown.Line ")"
    try LogLine("Uncaught error: " message, "Error")
    return 0 ; let AutoHotkey handle it as it would have, but not with a button down
}

; ==============================================================================
; Game window scoring
; ==============================================================================
; The arbiter that decides which visible window is the game, shared so both
; products answer that question the same way.
;
; Standalone scored candidates across every window using shape, CPU and audio;
; the companion asked only whether the FOREGROUND window was at least 85% x 80%
; of its monitor. That mattered beyond focus assistance: a per-game RTSS frame
; cap is keyed on the executable name, so a misidentification writes the cap to
; the wrong profile and says it succeeded. A fullscreen launcher, a video player
; or a browser all pass a shape-only test; CPU and audio are what disagree.
;
; Deliberately split into two verdicts rather than one call taking every signal.
; The tree samples CPU only for windows that pass the shape test and samples
; audio only for windows that pass the CPU test, because GetProcessCpuSample
; mutates a per-PID cache and the audio map is built lazily on first use. A
; single function taking pre-gathered signals would force both to be collected
; for windows that are about to be discarded -- on every engine tick.
;
; No globals and no window handling of any kind: this reads numbers already
; measured and returns a verdict. The geometry layer stays out of the companion,
; which is the boundary XFE was built to keep.

; facts:   w, h, x, y, screenW, screenH, titleLength, minimizedLegacy
; weights: fullscreenTolerance, positionTolerancePx, borderlessRatio,
;          fullscreen, borderlessLarge, titleBonus
GameWindowShapeVerdict(facts, weights) {
    nearFS := facts["minimizedLegacy"]
        || (facts["w"] >= (facts["screenW"] * weights["fullscreenTolerance"])
            && facts["h"] >= (facts["screenH"] * weights["fullscreenTolerance"])
            && Abs(facts["x"]) <= weights["positionTolerancePx"]
            && Abs(facts["y"]) <= weights["positionTolerancePx"])
    bigBorderless := !facts["minimizedLegacy"]
        && facts["w"] >= (facts["screenW"] * weights["borderlessRatio"])
        && facts["h"] >= (facts["screenH"] * weights["borderlessRatio"])
    if (!nearFS && !bigBorderless)
        return Map("accepted", false, "reject", "TOO_SMALL",
            "score", 0, "nearFS", false)
    score := nearFS ? weights["fullscreen"] : weights["borderlessLarge"]
    if (facts["titleLength"] >= 3)
        score += weights["titleBonus"]
    return Map("accepted", true, "reject", "", "score", score, "nearFS", nearFS)
}

; weights: cpuThresholdPercent, cpuAboveThreshold, cpuNonZeroBonus, allowZeroCpu
;
; An unknown reading is not evidence either way and never rejects: a process
; whose CPU cannot be read yet -- the first observation of it -- would otherwise
; be discarded for being new.
GameWindowCpuVerdict(baseScore, cpu, cpuKnown, weights) {
    score := baseScore
    if !cpuKnown
        return Map("accepted", true, "reject", "", "score", score)
    if (cpu >= weights["cpuThresholdPercent"])
        score += weights["cpuAboveThreshold"]
    else if (cpu > 0)
        score += weights["cpuNonZeroBonus"]
    else if (!weights["allowZeroCpu"])
        return Map("accepted", false, "reject", "CPU_ZERO_STRICT", "score", score)
    return Map("accepted", true, "reject", "", "score", score)
}

; Highest score first, larger window breaking a tie, lowest hwnd breaking that.
;
; Selection sort, kept as it was written: these lists are a handful of windows.
; The comment here used to justify the choice by saying an unstable sort "would
; make the chosen game flap between two equal candidates" -- but selection sort
; with a swap IS unstable. Swapping cands[i] with cands[best] reorders everything
; between them, so for candidates tied on score AND area the winner depended on an
; input order this very loop was permuting, and the property the comment claimed
; was the one thing it did not have.
;
; Rather than correct the comment, the tie is made total. hwnd is unique, stable
; for the lifetime of a window, and already carried on every candidate, so the
; ordering is now fully determined by the candidates themselves and the sort's
; instability stops being observable. The claim above is true as written.
SortCandidatesByScoreAreaDesc(cands) {
    n := cands.Length
    if (n < 2)
        return
    Loop n - 1 {
        i := A_Index
        best := i
        bestScore := cands[i]["score"]
        bestArea := cands[i]["w"] * cands[i]["h"]
        bestHwnd := cands[i]["hwnd"]
        j := i + 1
        while (j <= n) {
            s := cands[j]["score"]
            a := cands[j]["w"] * cands[j]["h"]
            hw := cands[j]["hwnd"]
            if (s > bestScore) || (s = bestScore && a > bestArea)
                || (s = bestScore && a = bestArea && hw < bestHwnd) {
                best := j
                bestScore := s
                bestArea := a
                bestHwnd := hw
            }
            j++
        }
        if (best != i) {
            tmp := cands[i]
            cands[i] := cands[best]
            cands[best] := tmp
        }
    }
}


; ==============================================================================
; Per-process audio activity
; ==============================================================================
; A game that is making sound is a game, which is the signal that separates it
; from a fullscreen browser or a launcher sitting at the same size. Moved here
; whole from the standalone tree so the companion's scorer weighs the same
; evidence; it touches no product state, only WASAPI.

; ==============================================================================
; AUDIO ASSIST (CoreAudio per-process peak)
; ==============================================================================
GuidBuf(guidStr) {
    buf := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "WStr", guidStr, "Ptr", buf, "Int")
    return buf
}

GetActiveAudioPidPeaks() {
    pids := Map()
    static CLSID_MMDeviceEnumerator := "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
    static IID_IMMDeviceEnumerator := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
    static IID_IAudioSessionControl2:= "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}"
    static IID_IAudioMeterInformation:= "{C02216F6-8C67-4B5B-9D00-D008E73E0064}"

    eRender := 0
    eMultimedia := 1
    CLSCTX_ALL := 23

    pDevice := 0, pMgr := 0, pEnum := 0
    try {
    enum := ComObject(CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator)

    ComCall(4, enum, "UInt", eRender, "UInt", eMultimedia, "Ptr*", pDevice)
    if (!pDevice)
        return pids

    dev := ComValue(13, pDevice)
    iidMgr := GuidBuf("{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}") ; IAudioSessionManager2

    ComCall(3, dev, "Ptr", iidMgr, "UInt", CLSCTX_ALL, "Ptr", 0, "Ptr*", pMgr)
        if (!pMgr)
            return pids

    mgr := ComValue(13, pMgr)

    ComCall(5, mgr, "Ptr*", pEnum) ; GetSessionEnumerator
        if (!pEnum)
            return pids

    sesEnum := ComValue(13, pEnum)

    count := 0
    ComCall(3, sesEnum, "Int*", count) ; GetCount

    iidCtl2 := GuidBuf(IID_IAudioSessionControl2)
    iidMeter := GuidBuf(IID_IAudioMeterInformation)

    Loop count {
    idx := A_Index - 1
    pCtrl := 0
    ComCall(4, sesEnum, "Int", idx, "Ptr*", pCtrl) ; GetSession
    if (!pCtrl)
        continue

    ctrl := ComValue(13, pCtrl)

    pid := 0
    pCtrl2 := 0
    ComCall(0, ctrl, "Ptr", iidCtl2, "Ptr*", pCtrl2)
        if (pCtrl2) {
        ctrl2 := ComValue(13, pCtrl2)
        ComCall(14, ctrl2, "UInt*", pid) ; GetProcessId
        }

    peak := 0.0
    pMeter := 0
    ComCall(0, ctrl, "Ptr", iidMeter, "Ptr*", pMeter)
        if (pMeter) {
        meter := ComValue(13, pMeter)
        ComCall(3, meter, "Float*", peak) ; GetPeakValue
        }

    if (pid) {
    if (!pids.Has(pid))
    pids[pid] := peak
    else if (peak > pids[pid])
    pids[pid] := peak
    }

        }

        return pids
    } catch {
        ; Each non-null interface pointer is wrapped in ComValue immediately.
        ; Those wrappers own and release the pointers automatically.
        return pids
    }
}

GetActiveAudioPidPeaksCached() {
    static lastTick := 0
    static lastMap := Map()
    if (A_TickCount - lastTick < 750)
        return lastMap
    lastTick := A_TickCount
    lastMap := GetActiveAudioPidPeaks()
    return lastMap
}

; ==============================================================================
; Shortcut display and foreground forcing
; ==============================================================================
; Both trees carried these twice. Normalising indentation and local names showed
; SendToPretty structurally identical and ForceForegroundWindow 0.98 -- the raw
; text scored 0.28 and 0.33, which is what naming and wrapping alone will do to a
; similarity number.

; Consume only the actual modifier prefix. Replacing "^" with "Ctrl+" and
; subsequently replacing every "+" made the inserted separator look like a Shift
; modifier, so "^1" was incorrectly displayed as "CtrlShift+1".
SendToPretty(sendStr) {
    static modifiers := Map("#", "Win+", "^", "Ctrl+", "!", "Alt+", "+", "Shift+")
    text := Trim(sendStr)
    prefix := ""
    while (text != "" && modifiers.Has(SubStr(text, 1, 1))) {
        prefix .= modifiers[SubStr(text, 1, 1)]
        text := SubStr(text, 2)
    }
    ; Key names arrive braced, e.g. {Tab}; the braces are noise on screen.
    text := StrReplace(StrReplace(text, "{", ""), "}", "")
    return prefix text
}

; The shell's version is the one kept, for two reasons the companion's lacked.
;
; The detach runs in a finally: AttachThreadInput must be undone even when
; SetForegroundWindow throws, and the companion detached inline, so a throw left
; this process's input queue attached to another thread's for the rest of the
; session. Explicit User32\ prefixes are also kept -- an unqualified DllCall
; resolves by search order, which is not something a focus primitive should
; depend on.
ForceForegroundWindow(hwnd) {
    if !hwnd
        return false
    try {
        if (DllCall("User32\GetForegroundWindow", "Ptr") = hwnd)
            return true
        currentForeground := DllCall("User32\GetForegroundWindow", "Ptr")
        ourThread := DllCall("Kernel32\GetCurrentThreadId", "UInt")
        foregroundThread := currentForeground
            ? DllCall(
                "User32\GetWindowThreadProcessId",
                "Ptr", currentForeground, "Ptr", 0, "UInt")
            : 0
        attached := false
        if (foregroundThread && foregroundThread != ourThread)
            attached := DllCall(
                "User32\AttachThreadInput",
                "UInt", ourThread, "UInt", foregroundThread, "Int", 1) != 0
        try {
            DllCall("User32\BringWindowToTop", "Ptr", hwnd)
            DllCall("User32\SetForegroundWindow", "Ptr", hwnd)
        } finally {
            if attached
                DllCall(
                    "User32\AttachThreadInput",
                    "UInt", ourThread, "UInt", foregroundThread, "Int", 0)
        }
        return DllCall("User32\GetForegroundWindow", "Ptr") = hwnd
    }
    return false
}

; Is this Gui's window actually on screen right now?
;
; ASKS THE WINDOW, rather than reading a flag that says what the window ought to
; be doing. That distinction is the reason this is here at all: the shell tested
; its Settings window this way and the companion tested a SettingsVisible
; boolean it maintains by hand, and only one of those can be shared, because
; SettingsVisible is declared in the companion alone. A shared function may name
; a global only when both trees declare it, so the window-state form is the one
; that survives -- and it is also the one that cannot go stale when a show or
; hide path forgets to update the flag.
;
; The try is not decoration. Reading .Hwnd on a destroyed Gui throws, and this is
; called from a poll, where a throw is the difference between a missed frame and
; an unusable machine.
IsGuiVisible(guiObj) {
    try return DllCall("User32\IsWindowVisible", "Ptr", guiObj.Hwnd, "Int")
    return 0
}

; "This Gui is on screen AND has the foreground" -- the question every
; controller-ownership predicate in both products was asking, written out by
; hand each time.
;
; There were four copies: the shell's two recovery predicates, which are
; character-identical to each other apart from which global they read, its
; Settings predicate, and the companion's. Nothing had noticed, because the
; cross-tree duplicate detector compares the two TREES and these sat three-in-one
; tree and one in the other; it only spoke up when an unrelated change dropped
; the shell's IsWindowVisible count past its distinctiveness threshold and paired
; a recovery predicate with the companion's game-detection heuristic, which it
; resembles not at all. The real duplication was the thing the false pairing was
; standing next to.
;
; The IsSet() guard stays with the CALLER. This takes the Gui object, so an
; unset global cannot be passed in without throwing first, and only the caller
; knows the name to test.
GuiVisibleAndActive(guiObj) {
    try return IsGuiVisible(guiObj) && WinActive("ahk_id " guiObj.Hwnd)
    return false
}

; ==============================================================================
; Game-score log formatting
; ==============================================================================
; Fixed-width columns for the candidate table. Pure formatting -- no state, no
; file access -- so the companion can render the same table now that it scores
; windows the same way.
TruncPad(s, width, leftAlign := true) {
    s := (s = "" ? "" : s)
    if (StrLen(s) > width) {
    if (width >= 2)
    s := SubStr(s, 1, width - 1) "…"
    else
    s := SubStr(s, 1, width)
    }
    pad := width - StrLen(s)
    if (pad <= 0)
        return s
    return leftAlign ? (s . StrRepeat(" ", pad)) : (StrRepeat(" ", pad) . s)
}

NowStamp() {
    return FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
}

FmtPid(pid) {
    return pid ? TruncPad(pid "", 6, false) : "------"
}

FmtCpu(cpu, known := true) {
    return known ? TruncPad(Format("{:0.1f}", cpu + 0.0), 6, false) : TruncPad("---.-", 6, false)
}

FmtScore(score, known := true) {
    return known ? Format("{:03}", ClampInt(score, 0, 999)) : "---"
}

FmtHwnd(hwnd) {
    return hwnd ? TruncPad("0x" Format("{:08X}", hwnd), 10, true) : "----------"
}

FmtRect(x, y, w, h) {
    return (x "," y " " w "x" h)
}

; ==============================================================================
; Legacy and minimized game surfaces
; ==============================================================================
; An exclusive-fullscreen game often minimizes itself the moment Steam takes
; focus, and a minimized window has unusable geometry -- so a shape test cannot
; see it and it scores as nothing.
;
; The companion passed a hardcoded false for this and covered the gap with its
; last-observed foreground executable, which is a staler answer standing in for a
; capability rather than an equivalent one. These read only fields already in
; both inventories, so both products can now recognise the same surfaces.
;
; Note what this does NOT bring across: the shell uses these to decide whether a
; window may be RESTORED, which is an activation concern the companion excludes
; by design. Here they answer only "is this a game", for naming an RTSS profile.
WindowEngineItemIntersectsMonitor(item) {
    x1 := item["x"]
    y1 := item["y"]
    x2 := x1 + item["w"]
    y2 := y1 + item["h"]
    if (x2 <= x1 || y2 <= y1)
        return false
    try {
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &left, &top, &right, &bottom)
            if (x1 < right && x2 > left && y1 < bottom && y2 > top)
                return true
        }
        return false
    } catch {
        return x1 < A_ScreenWidth && x2 > 0
            && y1 < A_ScreenHeight && y2 > 0
    }
}

WindowEngineIsLegacyApplicationSurface(item, allowMinimized := false) {
    ; Older DirectX games sometimes expose an untitled top-level window or mark
    ; their main render surface as WS_EX_TOOLWINDOW. Accept only a substantial,
    ; unowned, on-screen surface that Windows is allowed to activate.
    if (item["scriptOwned"] || item["desktop"] || item["steam"]
        || item["proc"] = "")
        return false
    if (item["exStyle"] & 0x08000000) ; WS_EX_NOACTIVATE
        return false
    if (item["exStyle"] & 0x00000020) ; WS_EX_TRANSPARENT
        return false
    if (item["owner"] && !(item["exStyle"] & 0x00040000)) ; WS_EX_APPWINDOW
        return false
    if (item["minMax"] = -1) {
        ; Exclusive-fullscreen games often minimize themselves as soon as Steam
        ; wins focus. Task Switcher may still offer an activatable, unowned
        ; top-level surface so selecting it can restore the application.
        return allowMinimized
    }
    if (item["w"] < 320 || item["h"] < 200)
        return false
    minLegacyArea := Min(A_ScreenWidth * A_ScreenHeight * 0.10, 640 * 360)
    if (item["area"] < minLegacyArea)
        return false
    return WindowEngineItemIntersectsMonitor(item)
}

WindowEngineIsMinimizedLegacyGameSurface(item) {
    ; A minimized window has unusable geometry. Restrict automatic restoration
    ; to unowned, activatable WS_POPUP surfaces without a caption—the retained
    ; style signature of an exclusive-fullscreen game such as older DirectX
    ; titles. Ordinary minimized desktop applications remain Task-Switcher-only.
    if (!WindowEngineIsLegacyApplicationSurface(item, true)
        || item["minMax"] != -1)
        return false
    return (item["style"] & 0x80000000) ; WS_POPUP
        && !(item["style"] & 0x00C00000) ; WS_CAPTION
}

; A pipe-delimited id list as a lookup. No globals and no state, so it belongs
; here rather than in the shared file -- it moved because QuickMenuRowAcceptsRepeat
; moved and would otherwise have failed to load in the companion, which never
; defined it.
QuickMenuIdSet(pipeList) {
    result := Map()
    for _, name in StrSplit(pipeList, "|") {
        trimmed := Trim(name)
        if (trimmed != "")
            result[trimmed] := true
    }
    return result
}

; ============================================================================
; Shared with the elevated helper, which cannot see SteamShell-Shared.ahk
; ============================================================================
; These four existed twice -- once in SteamShell-Shared.ahk for the two trees and
; once in SteamShell-Helper.ahk -- because the helper deliberately does not
; #Include the tree-coupled half. Nothing related the copies, and they had
; already drifted: the helper truncated with Integer() where the shared side
; rounded, so a hand-typed 60.7 was 60 to one process and 61 to the other, out of
; the SAME settings file.
;
; They take their state as PARAMETERS rather than reading a global, because this
; file may not declare one. That is what lets the single definition live where
; all three programs can reach it.
; ============================================================================

ReadIniBool(path, section, key, fallback) {
    value := fallback ? "true" : "false"
    try value := CleanIniValue(IniRead(path, section, key, value), value)
    value := StrLower(value)
    if (value = "true" || value = "yes" || value = "on" || value = "1")
        return true
    if (value = "false" || value = "no" || value = "off" || value = "0")
        return false
    return fallback
}

; Round(), not Integer(). Round() is what two of the three programs already did,
; and truncation is the more surprising answer for a value somebody typed.
ReadIniInt(path, section, key, fallback, minimum, maximum) {
    value := fallback
    ; Round() throws on anything non-numeric, which is what routes a malformed
    ; value to the fallback rather than to zero.
    try value := Round(CleanIniValue(IniRead(path, section, key, fallback), fallback))
    catch
        value := fallback
    return ClampInt(value, minimum, maximum)
}

; Applies a batch of INI changes as ONE replacement, or none of them.
;
; Both products had a function for this and only one of them was safe. Standalone
; staged a copy, wrote into the copy and moved it over the original, so a failure
; anywhere left the settings file exactly as it was. The companion wrote each key
; straight into the live file in a loop and returned false at the first error --
; which does not undo the keys it had already written. A three-key save that
; failed on the third left the file holding two of them and told the caller
; nothing had been saved, and the caller's in-memory state was then reloaded from
; a file that agreed with neither.
;
; That is the whole argument for this being one function: the companion's intent
; -- persist these settings -- is served completely by standalone's
; implementation, and there is nothing the loop did that the staged commit does
; not do better. Parameterised on path and PID because this file may not declare
; a global; each product binds its own in a three-line wrapper, the same shape
; ReadIniBool and ReadIniInt above already use.
;
; The staging file carries the owner's PID so SweepAbandonedIniUpdates can tell an
; abandoned one from a live one.
CommitIniChangesAt(iniPath, ownerPid, changes, deletes := 0) {
    static busy := false
    if (busy) {
        ; A refusal is not a failure, and the two used to be indistinguishable:
        ; both returned false and only the catch below logged anything. Staging
        ; is deliberately not reentrant -- a second commit would copy a settings
        ; file that is mid-replacement -- so the caller still gets false. What is
        ; new is that the dropped write is on the record instead of vanishing.
        LogLine("A settings write was refused because another commit was already "
            . "in progress; " changes.Length " change(s) were not applied.",
            "Warning")
        return false
    }
    busy := true
    workPath := iniPath ".update-" ownerPid ".tmp"
    try {
        if FileExist(workPath)
            FileDelete(workPath)
        ; A target that does not exist yet is staged from nothing rather than
        ; failing. FileCopy throws on a missing source, and the settings file
        ; always exists so that never showed -- but the controller profile file
        ; does not exist until the first profile is saved, and refusing to write
        ; it would be refusing to save the very first one.
        if FileExist(iniPath)
            FileCopy(iniPath, workPath, true)
        else
            FileAppend("", workPath, "UTF-8")
        for _, item in changes
            IniWrite(item["value"], workPath, item["section"], item["key"])
        if IsObject(deletes) {
            ; A key that is already absent satisfies "make sure this is not
            ; here", so a delete that finds nothing must not abandon the batch
            ; the caller's other changes are riding on. Every caller pushes
            ; deletes speculatively -- the mapping editor clears a .Display key
            ; that may never have existed, the companion's startup save clears
            ; every slot past the end of the list -- and a genuine permission or
            ; disk fault still fails at the FileCopy or FileMove bracketing this.
            for _, item in deletes
                try IniDelete(workPath, item["section"], item["key"])
        }
        FileMove(workPath, iniPath, true)
        return true
    } catch as err {
        try {
            if FileExist(workPath)
                FileDelete(workPath)
        }
        LogLine("Settings update failed; original INI retained: " err.Message)
        return false
    } finally {
        busy := false
    }
}

; Removes staging files left behind by runs that ended mid-commit.
;
; FileMove replaces the original, so an exit between the copy and the move leaves
; the copy behind. The name carries the PID that wrote it, which is what makes
; them safe to delete: the caller has just started, so any file named after a PID
; that is not its own and is no longer running belongs to a run that ended.
;
; A shell replacement is killed rather than closed often enough -- End Task,
; power loss, a failed sign-in -- that these accumulate beside the settings file
; the user is expected to be able to read. Shared with the commit above rather
; than left behind with it: a product that stages without sweeping trades one
; kind of litter for another.
;
; MATCHES THE CONVENTION, NOT ONE SUFFIX. This swept "<ini>.update-<pid>.tmp"
; only -- the name the commit above happens to use -- while standalone stages
; under four more of its own: .unicode-, .migration-, .import- and .reset-, none
; of which were ever cleaned up. The sweeper had been tidying after the one path
; that could not litter without the others being noticed. Any
; "<ini>.<word>-<pid>.tmp" beside the settings file is a staging file by this
; project's naming, so that is what it looks for, and a fifth suffix invented
; later is swept without anyone having to remember this function exists.
SweepAbandonedIniUpdates(iniPath, ownerPid) {
    settingsDirectory := ""
    settingsName := ""
    SplitPath(iniPath, &settingsName, &settingsDirectory)
    if (settingsDirectory = "" || settingsName = "")
        return 0
    removed := 0
    try {
        Loop Files, settingsDirectory "\" settingsName ".*.tmp" {
            if !RegExMatch(A_LoopFileName, "\.[A-Za-z]+-(\d+)\.tmp$", &match)
                continue
            abandonedPid := Integer(match[1])
            ; Never touch a live commit -- the caller's, or a second instance's.
            if (abandonedPid = ownerPid || ProcessExist(abandonedPid))
                continue
            try {
                FileDelete(A_LoopFilePath)
                removed += 1
            }
        }
    }
    if removed
        LogLine("Removed " removed " abandoned settings staging file(s) left by "
            . "a previous run.")
    return removed
}

; Returns the XInput DLL that loaded, or "" if none did. The CALLER assigns its
; own global; this file cannot hold that state itself.
ResolveXInputDll() {
    for _, dllName in ["xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"] {
        try {
            if DllCall("GetModuleHandle", "Str", dllName, "Ptr")
                || DllCall("LoadLibrary", "Str", dllName, "Ptr")
                return dllName
        }
    }
    return ""
}

; Whether a button has a Long binding worth firing. The bindings map is passed
; in for the same reason as the INI path above.
ControllerBindingHasLong(bindings, buttonName) {
    value := ""
    try value := bindings.Has(buttonName ".Long") ? bindings[buttonName ".Long"] : ""
    return value != "" && StrLower(value) != "builtin:none"
}

; The failsafe for a held synthetic mouse button, on a timer INDEPENDENT of the
; controller poll. The poll loop's abort paths already release through
; ResetControllerEdgeState; this covers the poll loop itself stopping -- a
; suspended timer, a thread that never returns, a reload that throws.
;
; Thirty seconds because a real drag is a few seconds and this must never end one
; that is still happening.
ControllerMouseSafetyTick() {
    released := ExpireControllerMouseButtons(30000)
    if (released != "")
        LogLine("Released a synthetic mouse button held past the safety limit: "
            . released . ". The controller poll loop may have stopped.", "Warning")
}

; Sends a chord with every modifier released first.
;
; Existed in all THREE programs, identically, because the helper cannot see
; SteamShell-Shared.ahk. It holds no state at all, which is what makes it safe
; here -- the two callers that DO have state (the companion, which declines
; while disabled) keep that decision in their own wrapper.
SendChordReleasingModifiers(keys) {
    try SendInput("{Ctrl up}{Alt up}{Shift up}{LWin up}{RWin up}")
    try SendInput(keys)
}

; ==============================================================================
; Game-detection candidate presentation
; ==============================================================================
; Both products score every candidate window to choose a game, using the same
; sort (SortCandidatesByScoreAreaDesc, below) and the same log table
; (LogGameCandidateTable, in SteamShell-Shared.ahk). Only the entry point and the
; setting names differ. These three take the candidate data as PARAMETERS and
; hold nothing, which is what lets the presentation be written once here rather
; than twice in the trees.
; ==============================================================================

; A capped, trimmed copy carrying only what the page shows. The scorer's own
; candidate maps carry window handles and geometry that a menu has no use for
; and that should not be kept alive between polls.
TrimGameCandidates(candidates, maxRows) {
    trimmed := []
    for _, entry in candidates {
        if (trimmed.Length >= maxRows)
            break
        trimmed.Push(Map(
            "proc", entry.Has("proc") ? entry["proc"] : "",
            "title", entry.Has("title") ? entry["title"] : "",
            "score", entry.Has("score") ? entry["score"] : 0,
            "cpu", entry.Has("cpu") ? entry["cpu"] : 0,
            "cpuKnown", entry.Has("cpuKnown") ? entry["cpuKnown"] : false,
            "audio", entry.Has("audio") ? entry["audio"] : false,
            "nearFS", entry.Has("nearFS") ? entry["nearFS"] : false))
    }
    return trimmed
}

; The score WITH the evidence behind it. The number alone does not say which
; rule produced it, and "why did it pick that window" is the only question this
; page exists to answer.
GameCandidateEvidenceText(entry) {
    if !IsObject(entry)
        return ""
    parts := [entry["score"] ""]
    if entry["nearFS"]
        parts.Push("fullscreen")
    parts.Push(entry["cpuKnown"] ? "cpu " Round(entry["cpu"]) "%" : "cpu ?")
    if entry["audio"]
        parts.Push("audio")
    return JoinWith(parts, " | ")
}

; The winner is marked rather than merely sorted first, because a list ordered
; by a number the reader is still deciding whether to trust does not say which
; row won.
GameCandidateLabel(entry, index) {
    if !IsObject(entry)
        return ""
    return (index = 1 ? "> " : "   ") entry["proc"]
}

; ==============================================================================
; Small conversions
; ==============================================================================
; Moved out of SteamShell.ahk when the game-detection presentation above needed
; them: a function in this file may only call what is defined here, and shared
; code may only call what BOTH trees have. Either rule alone would have been
; satisfied by copying them; together they say define them once, here, where all
; three programs can reach them.
; ==============================================================================

ToInt(v, default := 0) {
    s := Trim(v)
    return RegExMatch(s, "^-?\d+$") ? (s + 0) : default
}

JoinWith(listObj, delimiter := ", ") {
    out := ""
    for _, value in listObj
        out .= (out = "" ? "" : delimiter) value
    return out
}

; The out-of-the-box AutoMouseExeList, stated ONCE.
;
; This literal had twelve homes: two globals, two read defaults, a settings-row
; default, a defaults Map, a schema spec, the shell's embedded default INI text
; and two shipped sample INIs. That is the shape the version string was in when
; the 2.0.0 bump missed five of its copies, because one spelling was escaped and
; the grep only found the other -- so the code paths all call this, and
; Assert-AutoMouseDefaults holds the three text copies to it.
;
; What belongs here is a pointer-driven application a living-room user will
; actually open from the couch, where reaching for View/Back before every click
; is the friction the allowlist exists to remove.
;
; What does NOT belong here, and why, because each looks like an omission:
;
;   Windows Control Panel   already covered. Its window is CabinetWClass owned by
;                           EXPLORER, not by control.exe -- control.exe launches
;                           it and exits -- so explorer.exe below is what matches.
;   SteamShell's own windows
;                           never reach this test. AutoMouseModeActive skips a
;                           foreground window whose PID is ours; the Quick Menu,
;                           Settings and Control Panel carry their own controller
;                           handling.
;   Windows Settings        cannot be named by its own executable. ms-settings:
;                           opens a UWP window owned by ApplicationFrameHost.exe,
;                           so SystemSettings.exe would never match a foreground
;                           lookup and would be a list entry that does nothing.
;
; explorer.exe additionally covers Start and Search through the shell-family
; expansion in AutoMouseProcessMatches.
DefaultAutoMouseExeList() {
    return "explorer.exe|brave.exe|chrome.exe|msedge.exe|firefox.exe"
        . "|notepad.exe|taskmgr.exe"
}

; The one entry the COMPANION must never carry on that allowlist.
;
; Its own function for the same reason the list above is one: Assert-
; AutoMouseDefaults holds three text copies to the default, and the companion's
; sample is now a fourth shape -- the default minus this name. The validator
; derives that shape from these two functions rather than restating either, so
; there is still one place to change the list and one place to change what the
; companion drops from it.
AutoMouseExeExcludedFromCompanion() {
    return "explorer.exe"
}

; The allowlist as a given product may actually use it.
;
; The Xbox FSE task/application switcher is an explorer.exe window of class
; XamlExplorerHostIslandWindow, and -- measured 2026-07-25, recorded beside
; SuspendOnShellOverlay in SteamShell-XFE_SAMPLE.ini -- it DOES own the
; foreground while it is open. With explorer.exe on the list the companion turns
; the stick into a pointer over the switcher itself, which is the one surface the
; user is trying to drive with the D-pad, so switching applications in Xbox Mode
; stops working.
;
; GENUINELY PER PRODUCT, which is rare enough in this codebase to be worth
; stating. Standalone REPLACES Explorer as the Windows shell, so explorer.exe in
; the foreground there is a File Explorer or Control Panel window the user opened
; deliberately -- exactly the couch-browsing case the allowlist exists for. The
; companion runs beside a live Explorer that owns the desktop, the taskbar and
; the switcher, so the same name means something else entirely.
;
; Applied to the USER'S list and not only to the default, because the default is
; not where most companion users will have got it: every companion INI written
; before this build carries explorer.exe straight from the shipped sample, so a
; filter that cleaned only the default would fix nobody who already has one.
AutoMouseExeListFor(product, rawList) {
    if (StrLower(Trim(product)) != "xfe")
        return rawList
    excluded := StrLower(AutoMouseExeExcludedFromCompanion())
    kept := []
    for _, entry in StrSplit(rawList, "|") {
        name := Trim(entry)
        if (name = "" || StrLower(name) = excluded)
            continue
        kept.Push(name)
    }
    return JoinWith(kept, "|")
}

DefaultAutoMouseExeListFor(product) {
    return AutoMouseExeListFor(product, DefaultAutoMouseExeList())
}

; Says so, once per load, when a product drops an entry it will not honour.
;
; Nothing is rewritten: the key stays in the INI exactly as the user left it, and
; the Settings field shows the filtered list, so saving there is what removes it.
; Silence was the alternative and it is the worse one -- a list entry that is
; visible in the file the user edits and quietly does nothing is the same defect
; as a settings row wired to nothing.
;
; Membership is tested directly rather than by comparing the filtered list with
; the raw one: the filter also trims and drops blanks, so a list the user spaced
; out differs from its filtered form without anything having been excluded.
ReportAutoMouseExeListExclusion(product, rawList) {
    if (StrLower(Trim(product)) != "xfe")
        return false
    excluded := StrLower(AutoMouseExeExcludedFromCompanion())
    for _, entry in StrSplit(rawList, "|") {
        if (StrLower(Trim(entry)) != excluded)
            continue
        LogLine("The automatic-mouse allowlist names "
            . AutoMouseExeExcludedFromCompanion() ", which this product does not "
            . "honour: Explorer owns the Xbox FSE task switcher, and making the "
            . "stick a pointer over that window is what stops application "
            . "switching working. The entry is ignored and has been left in the "
            . "settings file; clear it in Settings to silence this.", "Warning")
        return true
    }
    return false
}

; MB_SYSTEMMODAL. Despite the name, its actual effect here is to make the message
; box topmost, which is exactly what is needed and needs no timer.
TopmostMsgBox(text, title := "", options := "") {
    return MsgBox(text, title, Trim(options " 4096"))
}

ToFloat(v, default := 0.0) {
    s := Trim(v)
    return RegExMatch(s, "^-?(?:\d+(?:\.\d*)?|\.\d+)$") ? (s + 0.0) : default
}


FormatSettingsFloat(value, maxDecimals := 6) {
    ; AutoHotkey can stringify a binary floating-point value as
    ; 0.20000000000000001. Store a bounded, human-readable decimal instead.
    text := Format("{:." maxDecimals "f}", value + 0.0)
    text := RegExReplace(text, "0+$")
    text := RegExReplace(text, "\.$")
    return text = "-0" ? "0" : text
}


; ==============================================================================
; RawInput controller identity and profile decoding
; ==============================================================================
; Moved here from SteamShell-Shared.ahk so the ELEVATED HELPER can compile it.
;
; The helper's only input source was XInputGetState, so a pad that answers only
; RawInput -- which is the entire reason the RawInput backend and the learning
; wizard exist -- lost the pointer the moment an elevated window came forward.
; Everywhere else it worked. From the user's side that is one input mode being
; second-class, not a design decision, so the decoder had to reach the one
; process that could not see it.
;
; It qualifies for this file because every function below was ALREADY pure: no
; globals, and nothing called outside itself except LogLine, which is the one
; permitted seam. What was tree-coupled was not the decoding but the two pieces
; of state around it -- where the profile file lives, and which buffer the
; decoded report is written into -- so those became parameters and the two thin
; wrappers that supply them stayed behind in SteamShell-Shared.ahk.
; ==============================================================================

; The XInput button bit for each name the learner knows.
ControllerButtonBits() {
    static bits := Map(
        "Up", 0x0001, "Down", 0x0002, "Left", 0x0004, "Right", 0x0008,
        "Menu", 0x0010, "View", 0x0020, "L3", 0x0040, "R3", 0x0080,
        "LB", 0x0100, "RB", 0x0200, "Guide", 0x0400,
        "A", 0x1000, "B", 0x2000, "X", 0x4000, "Y", 0x8000)
    return bits
}




; The section name used when Windows will not identify a device at all.
;
; Keying a profile on report length is less precise than VID/PID, but it is
; exactly as precise as the built-in layout it replaces -- that already matches on
; nothing but `length = 16`. So this is not a new risk, it is the existing one
; made writable, and it is what lets a controller whose metadata Windows withholds
; still be taught.
ControllerProfileLengthKey(length) {
    return "LEN_" length
}




; Reads one axis field out of a report.
ControllerProfileAxisRaw(data, base, axis) {
    offset := base + axis["offset"]
    if (axis["size"] = "u8")
        return NumGet(data, offset, "UChar")
    if (axis["size"] = "u16be") {
        high := NumGet(data, offset, "UChar")
        return (high << 8) | NumGet(data, offset + 1, "UChar")
    }
    return NumGet(data, offset, "UShort")
}




; Full scale of an axis field, used to normalise to XInput's ranges.
ControllerProfileAxisSpan(axis) {
    return axis["size"] = "u8" ? 255 : 65535
}




RawInputAxis(raw) {
    value := raw - 0x8000
    if (value < -32767)
        return -32767
    return value > 32767 ? 32767 : value
}




; A stable identity for a RawInput device.
;
; hDevice handles change across sleep and re-plugging, so they cannot key a saved
; profile. The device interface path does contain a stable identity -- the USB
; vendor and product IDs, plus the interface and collection when a device exposes
; several -- so that is what is extracted. If the driver withholds both the path
; and numeric IDs, the HID preparsed descriptor is hashed as a final stable
; layout identity.
RawInputDeviceKey(hDevice, refresh := false) {
    static RIDI_DEVICENAME := 0x20000007
    static RIDI_DEVICEINFO := 0x2000000B
    static RIDI_PREPARSEDDATA := 0x20000005
    static cache := Map()
    ; Identity lookups that failed recently, and when they may be retried.
    ;
    ; Failure must not be cached permanently -- a metadata query can fail while
    ; the HID stack is still settling, and Save needs a later attempt to be able
    ; to succeed. But it must not be retried on every report either: this runs
    ; from the WM_INPUT handler at over 100 Hz, and the fallback chain below costs
    ; five syscalls plus a byte-at-a-time hash of the entire HID descriptor. For a
    ; device that can never be identified, that is pure waste on the input hot
    ; path of a handheld. So failure backs off for a couple of seconds instead.
    static failedUntil := Map()
    static IDENTITY_RETRY_MS := 2000
    ; Map.Delete THROWS when the key is absent. The cache line below got that
    ; right and this one did not, one line apart.
    ;
    ; It surfaced from the rest check: a profile that reads as pegged offers to
    ; delete itself, DeleteControllerProfileForActiveDevice asks for the device
    ; key with refresh := true, and this threw "Item has no value" out of a timer
    ; -- so answering Yes to "delete the bad profile?" crashed instead of
    ; deleting it, leaving the user with the runaway pointer they had just asked
    ; to be rid of.
    if (refresh && cache.Has(hDevice))
        cache.Delete(hDevice)
    if (refresh && failedUntil.Has(hDevice))
        failedUntil.Delete(hDevice)
    if cache.Has(hDevice)
        return cache[hDevice]
    if (failedUntil.Has(hDevice) && A_TickCount < failedUntil[hDevice])
        return ""
    ; Captured for the diagnostic at the end of this function.
    infoVid := 0
    infoPid := 0
    infoResult := "not tried"
    descriptorBytes := 0
    descriptorResult := "not tried"
    name := ""
    size := 0
    nameError := ""
    ; NOT named "buffer", and the catch is not optional.
    ;
    ; AutoHotkey identifiers are case-insensitive, so a local called buffer IS
    ; the Buffer class: the constructor on the right resolved to the unassigned
    ; local and threw before it ever ran. Inside the bare try that used to be
    ; here that throw was swallowed, so RIDI_DEVICENAME appeared to fail on every
    ; device on every machine -- which silently removed the &MI_/&Col suffixes
    ; below, collapsing every collection of a composite gamepad onto one profile
    ; key, and made the DEV_ checksum fallback unreachable. The failure is
    ; carried to the once-per-device diagnostic at the end of this function
    ; rather than logged here, because this runs from WM_INPUT above 100 Hz.
    ;
    ; ElevatedRtssFinalPath in SteamShell-Helper.ahk carries the same note.
    try {
        DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", RIDI_DEVICENAME,
            "Ptr", 0, "UInt*", &size)
        if size {
            nameBuffer := Buffer(size * 2 + 2, 0)
            if (DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", RIDI_DEVICENAME,
                "Ptr", nameBuffer, "UInt*", &size, "UInt") != 0xFFFFFFFF)
                name := StrGet(nameBuffer, "UTF-16")
        }
    } catch as err {
        nameError := err.Message
    }
    key := ""
    if RegExMatch(name, "i)VID_([0-9A-F]{4})&PID_([0-9A-F]{4})", &match) {
        key := "VID_" StrUpper(match[1]) "_PID_" StrUpper(match[2])
        ; A composite device exposes several collections; the gamepad is only one
        ; of them, so the interface and collection numbers are part of the identity.
        if RegExMatch(name, "i)&MI_([0-9A-F]{2})", &mi)
            key .= "_MI_" StrUpper(mi[1])
        if RegExMatch(name, "i)&Col([0-9]{2})", &col)
            key .= "_Col" col[1]
    } else if (name != "") {
        ; No VID/PID in the path. Fall back to a checksum of it, which is still
        ; stable for this device on this machine.
        sum := 0
        Loop Parse name
            sum := Mod(sum * 31 + Ord(A_LoopField), 0xFFFFFFF)
        key := "DEV_" Format("{:07X}", sum)
    }
    if (key = "") {
        ; Some HID stacks deliver reports but do not return an interface path
        ; for RIDI_DEVICENAME. RIDI_DEVICEINFO carries the numeric HID VID/PID
        ; independently, so use it before declaring the device unidentifiable.
        try {
            info := Buffer(32, 0)
            NumPut("UInt", 32, info, 0)
            infoSize := 32
            infoResult := DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt",
                RIDI_DEVICEINFO, "Ptr", info, "UInt*", &infoSize, "UInt")
            infoVid := NumGet(info, 8, "UInt") & 0xFFFF
            infoPid := NumGet(info, 12, "UInt") & 0xFFFF
            if (infoResult != 0xFFFFFFFF) {
                vid := NumGet(info, 8, "UInt")
                pid := NumGet(info, 12, "UInt")
                if (vid || pid)
                    key := "VID_" Format("{:04X}", vid & 0xFFFF)
                        . "_PID_" Format("{:04X}", pid & 0xFFFF)
            }
        }
    }
    if (key = "") {
        ; RawInput cannot deliver HID reports without preparsed descriptor data.
        ; Some virtualised/filtered Ally drivers expose that data while
        ; returning neither a device path nor usable RID_DEVICE_INFO IDs. Hash
        ; the descriptor so the learned layout still survives handle changes.
        try {
            descriptorSize := 0
            result := DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt",
                RIDI_PREPARSEDDATA, "Ptr", 0, "UInt*", &descriptorSize, "UInt")
            descriptorResult := result
            descriptorBytes := descriptorSize
            if (result != 0xFFFFFFFF && descriptorSize > 0) {
                descriptor := Buffer(descriptorSize, 0)
                result := DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice,
                    "UInt", RIDI_PREPARSEDDATA, "Ptr", descriptor,
                    "UInt*", &descriptorSize, "UInt")
                if (result != 0xFFFFFFFF && descriptorSize > 0) {
                    hash := 2166136261
                    Loop descriptorSize
                        hash := Mod((hash ^ NumGet(descriptor,
                            A_Index - 1, "UChar")) * 16777619, 0x100000000)
                    key := "HID_DESC_" Format("{:08X}", hash)
                        . "_" descriptorSize
                }
            }
        }
    }
    ; Record what each route actually returned the first time a device cannot be
    ; identified. "No identity available" is unactionable on its own, and this
    ; failed on real hardware -- the Ally's own controller -- so the three return
    ; values are the diagnosis.
    static reported := Map()
    if (key = "" && !reported.Has(hDevice)) {
        reported[hDevice] := true
        LogLine("RawInput identity: device 0x" Format("{:X}", hDevice)
            . " unidentifiable. RIDI_DEVICENAME chars=" size
            . " path='" (name != "" ? name : "(none)") "'"
            ; Without this, a throw inside the path lookup was indistinguishable
            ; from the HID stack returning a size and no path, and pointed the
            ; diagnosis at the driver instead of at this function.
            . (nameError != "" ? " pathError='" nameError "'" : "")
            . ", RIDI_DEVICEINFO vid=0x" Format("{:04X}", infoVid)
            . " pid=0x" Format("{:04X}", infoPid) " rc=" infoResult
            . ", RIDI_PREPARSEDDATA bytes=" descriptorBytes
            . " rc=" descriptorResult ".", "Warning")
    }
    ; Success caches permanently; failure only backs off. See failedUntil above.
    if (key != "") {
        cache[hDevice] := key
        ; Guarded for the same reason: a device that identifies on its first
        ; attempt was never in failedUntil, and deleting a key that is not there
        ; throws.
        if failedUntil.Has(hDevice)
            failedUntil.Delete(hDevice)
    } else {
        failedUntil[hDevice] := A_TickCount + IDENTITY_RETRY_MS
    }
    return key
}


LoadControllerProfileFrom(path, key, refresh := false) {
    static cache := Map()
    if (key = "")
        return 0
    ; Saving a VID/PID-only fallback must invalidate any previously cached miss
    ; for the same device's more-specific MI/collection key.
    if refresh
        cache := Map()
    if cache.Has(key)
        return cache[key]
    if !FileExist(path) {
        cache[key] := 0
        return 0
    }
    section := key
    length := 0
    try length := Integer(IniRead(path, section, "ReportLength", "0"))
    ; A device path may be available on one boot and unavailable on another.
    ; Profiles saved from numeric RIDI_DEVICEINFO therefore use VID/PID only;
    ; allow a later, more-specific MI/collection key to find that base profile.
    if (length <= 0
        && RegExMatch(key, "i)^(VID_[0-9A-F]{4}_PID_[0-9A-F]{4})", &base)
        && base[1] != key) {
        section := base[1]
        try length := Integer(IniRead(path, section, "ReportLength", "0"))
    }
    if (length <= 0) {
        cache[key] := 0
        return 0
    }
    profile := Map("length", length, "buttons", [], "hat", 0, "axes", Map(),
        "name", "", "key", section)
    try profile["name"] := IniRead(path, section, "Name", "")

    buttonText := ""
    try buttonText := IniRead(path, section, "Buttons", "")
    bits := ControllerButtonBits()
    for _, entry in StrSplit(buttonText, "|") {
        parts := StrSplit(Trim(entry), ":")
        if (parts.Length < 3 || !bits.Has(parts[1]))
            continue
        try {
            offset := Integer(parts[2])
            mask := Integer(parts[3])
            pressed := parts.Length >= 4 ? Integer(parts[4]) : mask
            if (offset < 0 || offset >= length || mask < 1 || mask > 255)
                continue
            profile["buttons"].Push(Map(
                "bit", bits[parts[1]],
                "offset", offset,
                "mask", mask,
                "pressed", pressed & mask))
        }
    }

    hatText := ""
    try hatText := IniRead(path, section, "Hat", "")
    parts := StrSplit(Trim(hatText), ":")
    ; Current: offset : mask : released : N : NE : E : SE : S : SW : W : NW
    ; Early profiles omitted mask; 0xFF preserves their whole-byte behaviour.
    if (parts.Length >= 10) {
        try {
            offset := Integer(parts[1])
            hasMask := parts.Length >= 11
            mask := hasMask ? Integer(parts[2]) : 0xFF
            releasedIndex := hasMask ? 3 : 2
            firstDirectionIndex := hasMask ? 4 : 3
            released := Integer(parts[releasedIndex])
            if (offset < 0 || offset >= length || mask < 1 || mask > 255
                || released < 0 || released > 255)
                throw Error("Invalid hat")
            directions := Map()
            ; Same clockwise-from-north order the built-in layout uses.
            order := [0x0001, 0x0001 | 0x0008, 0x0008, 0x0002 | 0x0008,
                0x0002, 0x0002 | 0x0004, 0x0004, 0x0001 | 0x0004]
            Loop 8 {
                value := Integer(parts[firstDirectionIndex + A_Index - 1])
                if (value < 0 || value > 255)
                    throw Error("Invalid hat")
                directions[value] := order[A_Index]
            }
            profile["hat"] := Map("offset", offset,
                "mask", mask, "released", released, "directions", directions)
        }
    }

    axisText := ""
    try axisText := IniRead(path, section, "Axes", "")
    validAxisNames := Map("LX", true, "LY", true, "RX", true, "RY", true,
        "LT", true, "RT", true)
    validAxisSizes := Map("u8", true, "u16le", true, "u16be", true)
    for _, entry in StrSplit(axisText, "|") {
        parts := StrSplit(Trim(entry), ":")
        if (parts.Length < 5)
            continue
        try {
            name := parts[1]
            offset := Integer(parts[2])
            size := parts[3]
            neutral := Integer(parts[4])
            direction := Integer(parts[5])
            extent := parts.Length >= 6 ? Integer(parts[6]) : 0
            width := size = "u8" ? 1 : 2
            fullScale := size = "u8" ? 255 : 65535
            if (!validAxisNames.Has(name) || !validAxisSizes.Has(size)
                || offset < 0 || offset + width > length
                || neutral < 0 || neutral > fullScale
                || (direction != -1 && direction != 1)
                || extent < 0 || extent > fullScale)
                continue
            profile["axes"][name] := Map(
                "offset", offset,
                "size", size,
                "neutral", neutral,
                "direction", direction,
                "extent", extent)
        }
    }
    if (profile["buttons"].Length = 0 && !IsObject(profile["hat"])
        && profile["axes"].Count = 0) {
        cache[key] := 0
        return 0
    }
    cache[key] := profile
    return profile
}




RawInputProfileDecodeInto(profile, data, base, length, stateBuffer) {
    if (length != profile["length"])
        return false

    buttons := 0
    for _, button in profile["buttons"] {
        value := NumGet(data, base + button["offset"], "UChar")
        if ((value & button["mask"]) = button["pressed"])
            buttons |= button["bit"]
    }
    hat := profile["hat"]
    if IsObject(hat) {
        value := NumGet(data, base + hat["offset"], "UChar") & hat["mask"]
        if (value != hat["released"] && hat["directions"].Has(value))
            buttons |= hat["directions"][value]
    }

    lt := 0
    rt := 0
    axes := profile["axes"]
    ; A shared trigger axis is not a special case here: LT and RT simply resolve
    ; to the same offset with opposite directions, which is how the learner
    ; records what it observed.
    for _, name in ["LT", "RT"] {
        if !axes.Has(name)
            continue
        axis := axes[name]
        raw := ControllerProfileAxisRaw(data, base, axis)
        delta := (raw - axis["neutral"]) * axis["direction"]
        if (delta <= 0)
            continue
        ; The travel is only ever one side of neutral, and which side depends on
        ; the direction, so the divisor has to follow it. Using the full span
        ; would halve a trigger that rests at mid-scale -- which a shared trigger
        ; axis does.
        span := axis["extent"]
        if (span <= 0) {
            span := (axis["direction"] > 0)
                ? ControllerProfileAxisSpan(axis) - axis["neutral"]
                : axis["neutral"]
        }
        value := Min(255, Round(delta * 255 / Max(1, span)))
        if (name = "LT")
            lt := value
        else
            rt := value
    }

    thumbs := Map("LX", 8, "LY", 10, "RX", 12, "RY", 14)
    NumPut("UInt", 0, stateBuffer, 0)
    NumPut("UShort", buttons, stateBuffer, 4)
    NumPut("UChar", lt, stateBuffer, 6)
    NumPut("UChar", rt, stateBuffer, 7)
    for name, stateOffset in thumbs {
        value := 0
        if axes.Has(name) {
            axis := axes[name]
            raw := ControllerProfileAxisRaw(data, base, axis)
            offsetFromRest := raw - axis["neutral"]
            ; Each side of neutral is scaled by its own travel, so an axis whose
            ; rest point is not exactly mid-scale still reaches full deflection
            ; both ways instead of clipping one side and falling short on the
            ; other.
            span := axis["extent"]
            if (span <= 0) {
                span := (offsetFromRest >= 0)
                    ? ControllerProfileAxisSpan(axis) - axis["neutral"]
                    : axis["neutral"]
            }
            scaled := Round(offsetFromRest * 32767 / Max(1, span))
            value := ClampFloat(scaled * axis["direction"], -32767, 32767)
        }
        NumPut("Short", value, stateBuffer, stateOffset)
    }
    return true
}


; Where a product's learned controller profiles live, derived from its settings
; file. One spelling, because the helper derives the same path from the settings
; path it was handed and a second copy of this rule would be a second answer.
ControllerProfilePathFor(iniPath) {
    return RegExReplace(iniPath, "\.ini$", "") "-Controllers.ini"
}
