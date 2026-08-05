; ==============================================================================
; SteamShell shared functions
;
; Included verbatim at compile time by BOTH SteamShell.ahk and
; SteamShell-XFE.ahk. This file is the single definition of every function the
; two programs genuinely have in common.
;
; Why this exists
; ---------------
; The two trees are parallel programs, not a reference and a copy, and for a
; long time "apply the change to both" was an intention with nothing enforcing
; it. SHARED_FUNCTIONS.txt plus the parity check in Validate-Common.ps1 turned
; that into a build failure, which is a net that catches falls. Defining each function once
; removes the edge: a shared function can no longer drift, because there is no
; second copy to drift from.
;
; Rules
; -----
; 1. FUNCTIONS ONLY. No top-level executable statements and no global
;    initializers. This file is textually inserted into two different
;    auto-execute sections, so anything that runs would run in both, twice over,
;    at a point neither script chose.
; 2. Anything here must be behaviourally identical in both programs. A function
;    that needs to differ does not belong in this file -- move it back into both
;    trees and drop its name from SHARED_FUNCTIONS.txt in the same commit, which
;    is how a divergence gets recorded rather than discovered.
; 3. Globals referenced here must exist in both trees. AutoHotkey resolves a
;    missing global to an empty value at run time rather than failing to
;    compile, so the validators assert the ones that matter.
;
; The per-tree seam
; -----------------
; Shared code calls back into the trees through 24 functions, and each tree MUST
; define every one. THE LIST IS NOT HERE. It is $sharedSeamAllowed in
; Validate-Common.ps1, and it is enforced in both directions: every name on it
; must exist in both trees, and nothing may leave this file that is not on it.
;
; This paragraph used to name three functions. The real number was 28. That is
; not a documentation slip -- it is the same failure SteamShell-Common.ahk's
; header describes happening to THIS file once already ("documented two
; permitted callbacks and had grown to eight before anyone noticed, because
; nothing enumerated what actually left the file"). It was written about this
; file, the remedy was applied only to Common, and the growth resumed. Prose
; cannot hold a list that changes; a check can. So the list lives where it is
; executed, and this paragraph says where to look instead of guessing.
;
; SharedNotify was on that three-name list as something "each tree MUST define".
; It is defined HERE, and neither tree defines it. The trees each have a
; one-line alias -- ShowNotification in standalone, SetStatus in the companion --
; which is why the mistake read as true for as long as it did.
;
; The two seam functions worth understanding rather than looking up:
;
;   LogLine(message, level)                 diagnostic log line
;   SharedPersistSettings(changes)          apply Map("section","key","value")
;                                           entries as one unit, return bool
;
; SharedPersistSettings exists because the two trees write settings differently
; and both ways are correct for their program: standalone stages a copy and
; replaces the live INI only after every write succeeds, because it is the
; Windows shell and a half-written settings file is a machine that boots into
; nothing. XFE writes directly, because it is an ordinary application. The
; shared logic should not have to know which.
; ==============================================================================

; Whether a foreground executable is on the user's automatic-mouse list.
;
; Shared because the list means the same thing in both programs; only the
; decision to consult it differs, which is why AutoMouseModeActive stays in each
; tree. See the globals beside it there.
AutoMouseProcessMatches(exeName) {
    global AutoMouseExeSet
    exeName := StrLower(Trim(exeName))
    if AutoMouseExeSet.Has(exeName)
        return true
    ; Explorer owns the desktop and taskbar, but modern Windows moves Start and
    ; its search surface into separate system processes. Treat those implementation
    ; details as one Explorer shell family so the user's single explorer.exe opt-in
    ; keeps working across Windows 10 and 11.
    if !AutoMouseExeSet.Has("explorer.exe")
        return false
    static explorerShellHosts := Map(
        "startmenuexperiencehost.exe", true,
        "shellexperiencehost.exe", true,
        "searchhost.exe", true,
        "searchui.exe", true)
    return explorerShellHosts.Has(exeName)
}

EnsureDisplayScaleSelection() {
    global DisplaySelectedScalePercent
    info := GetPrimaryDisplayScale()
    if !IsObject(info) {
        DisplaySelectedScalePercent := 0
        return 0
    }
    if DisplaySelectedScalePercent {
        for _, option in info["options"] {
            if (option = DisplaySelectedScalePercent)
                return info
        }
    }
    DisplaySelectedScalePercent := info["percent"]
    return info
}

EnsureGdiPlus() {
    global GdiPlusToken, GdiPlusModule
    if (GdiPlusToken)
        return true
    ; The handle is kept so ShutdownGdiPlus can release it. The Quick Menu starts
    ; and shuts GDI+ down once per open/close cycle, so a LoadLibrary with no
    ; matching FreeLibrary added one module reference every time the menu was
    ; opened.
    if !GdiPlusModule
        GdiPlusModule := DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    if !GdiPlusModule
        return false
    ; GdiplusStartupInput: version, then a pointer and two BOOLs.
    input := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("UInt", 1, input, 0)
    token := 0
    if (DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", input, "Ptr", 0, "UInt") != 0)
        return false
    GdiPlusToken := token
    return true
}

QueueQuickMenuDisplayReflow() {
    SetTimer(QuickMenuDisplayReflow, -350)
}

QuickMenuAccentPresetHex(name) {
    global QM_ACCENT_PRESETS
    wanted := StrLower(Trim(name))
    for _, pair in QM_ACCENT_PRESETS {
        if (StrLower(pair[1]) = wanted)
            return pair[2]
    }
    return ""
}

QuickMenuAccentPresetNames() {
    global QM_ACCENT_PRESETS
    names := []
    for _, pair in QM_ACCENT_PRESETS
        names.Push(pair[1])
    return names
}

; Custom shows the hex actually in use, so a malformed value is visible as the
; Purple fallback rather than silently looking like it applied.
QuickMenuAccentValueText() {
    global QuickMenuAccentName, QM_ACCENT
    return (StrLower(QuickMenuAccentName) = "custom")
        ? "Custom · " QM_ACCENT
        : QuickMenuAccentName
}

; Resolves the configured accent into the live palette. Safe to call repeatedly;
; the Quick Menu calls it whenever the setting changes so the change is visible
; without a restart.
QuickMenuApplyAccent(presetName, customHex) {
    global QM_ACCENT, QM_ROW_SELECTED, QM_BG, QM_ACCENT_BLEND
    global QuickMenuAccentName, QuickMenuAccentCustomHex
    name := Trim(presetName)
    custom := NormalizeHexColor(customHex)
    hex := (StrLower(name) = "custom")
        ? custom
        : NormalizeHexColor(QuickMenuAccentPresetHex(name))
    if (hex = "") {
        ; An unknown preset or a malformed custom hex falls back to the default
        ; rather than leaving the menu unreadable. The configured name is kept as
        ; the user wrote it so Settings still shows what they chose.
        hex := QuickMenuAccentPresetHex("Purple")
    }
    QuickMenuAccentName := (name != "") ? name : "Purple"
    QuickMenuAccentCustomHex := (custom != "") ? custom : "107C10"
    QM_ACCENT := hex
    QM_ROW_SELECTED := BlendHexColor(QM_BG, hex, QM_ACCENT_BLEND)
}

QuickMenuDisplayReflow() {
    global QuickMenuVisible
    if QuickMenuVisible
        QuickMenuBuildGui()
}

QuickMenuKeyboardActive(*) {
    global QuickMenuVisible, QuickMenuGui
    if (!QuickMenuVisible || !IsSet(QuickMenuGui))
        return false
    try return WinActive("ahk_id " QuickMenuGui.Hwnd) != 0
    return false
}

; Paints every row into one bitmap and hands it to the row control. Called on
; each refresh; there is no partial repaint, because composing the whole band is
; already well under a frame and a partial one would have to reason about which
; neighbours a glow spills onto.
QuickMenuPaintRows() {
    global QuickMenuRowsCtrl, QuickMenuRowsBitmap, QuickMenuRows, QuickMenuSelected
    global QuickMenuRedrawSuspended
    global QM_BG, QM_ROW_SELECTED, QM_ACCENT, QM_LABEL, QM_LABEL_SELECTED, QM_VALUE
    static warnedNoBitmap := false
    if (!IsSet(QuickMenuRowsCtrl) || !QuickMenuRowsCtrl)
        return
    if !EnsureGdiPlus()
        return

    ; Physical pixels. AutoHotkey scales the control from logical units, so asking
    ; the control itself is the only way to match the surface to the screen.
    clientRect := Buffer(16, 0)
    if !DllCall("GetClientRect", "Ptr", QuickMenuRowsCtrl.Hwnd, "Ptr", clientRect)
        return
    width := NumGet(clientRect, 8, "Int")
    height := NumGet(clientRect, 12, "Int")
    if (width < 1 || height < 1)
        return
    rowCount := QuickMenuRows.Length
    if (rowCount < 1)
        return

    ; One scale factor derived from the control itself, so every measurement below
    ; is in logical units and DPI is handled in exactly one place.
    ; Guarded because every measurement below divides through it, and this is the
    ; one input to the painter that is not read from the control. Everything else
    ; here already refuses a degenerate value -- the client rect, the row count,
    ; the bitmap -- and a zero would take the whole page out with a divide error
    ; rather than the blank rows those other guards produce.
    logicalWidth := QuickMenuWidth()
    if (logicalWidth < 1)
        return
    scale := width / logicalWidth
    px(value) => value * scale

    screenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
    memDC := DllCall("CreateCompatibleDC", "Ptr", screenDC, "Ptr")
    header := Buffer(40, 0)
    NumPut("UInt", 40, header, 0)
    NumPut("Int", width, header, 4)
    NumPut("Int", -height, header, 8) ; top-down, so y grows downward as drawn
    NumPut("UShort", 1, header, 12)
    NumPut("UShort", 32, header, 14)
    bits := 0
    bitmap := DllCall("CreateDIBSection", "Ptr", memDC, "Ptr", header, "UInt", 0
        , "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
    ; Without this the painter carries on into the DC's default 1x1 monochrome
    ; bitmap and then hands the control a null image, which blanks the rows with
    ; no error anywhere. An empty menu reads as a rendering fault rather than as
    ; the GDI handle exhaustion it actually is.
    if !bitmap {
        if !warnedNoBitmap {
            warnedNoBitmap := true
            LogLine("Quick Menu: CreateDIBSection failed for a "
                . width "x" height " row surface; the page cannot be painted. "
                . "This usually means GDI handle exhaustion.", "Warning")
        }
        DllCall("DeleteDC", "Ptr", memDC)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", screenDC)
        return
    }
    previous := DllCall("SelectObject", "Ptr", memDC, "Ptr", bitmap, "Ptr")
    graphics := 0
    DllCall("gdiplus\GdipCreateFromHDC", "Ptr", memDC, "Ptr*", &graphics)
    if graphics {
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", graphics, "Int", 4)
        ; The surface is opaque, so ClearType is available and text quality does
        ; not regress against the Static controls this replaced.
        DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", graphics, "Int", 5)
        QuickMenuFillRounded(graphics, 0, 0, width, height, 0, QuickMenuArgb(QM_BG))

        labelFont := QuickMenuMakeFont(px(16), false)
        labelFontBold := QuickMenuMakeFont(px(16), true)
        valueFont := QuickMenuMakeFont(px(14.7), false)
        rowHeight := QuickMenuRowHeight()
        glowPad := QuickMenuGlowPadding()
        inset := QuickMenuRowInset()
        rowWidth := QuickMenuWidth() - (inset * 2)
        radius := px(10)
        textPad := px(16)
        barWidth := px(4)

        boxHeight := px(rowHeight - 6)
        left := px(inset)
        boxWidth := px(rowWidth)
        ; Paint selection decoration before any text. The stronger glow extends
        ; into neighbouring slots; drawing it inside the row loop would haze text
        ; belonging to an earlier row whenever a middle/lower row was selected.
        if (QuickMenuSelected >= 1 && QuickMenuSelected <= QuickMenuRows.Length) {
            selectedTop := px(glowPad + ((QuickMenuSelected - 1) * rowHeight) + 3)
            QuickMenuDrawGlow(graphics, left, selectedTop, boxWidth, boxHeight, radius
                , QM_ACCENT, 8, 120, px(1))
            QuickMenuFillRounded(graphics, left, selectedTop, boxWidth, boxHeight, radius
                , QuickMenuArgb(QM_ROW_SELECTED))
            QuickMenuStrokeRounded(graphics, left, selectedTop, boxWidth, boxHeight, radius
                , QuickMenuArgb(QM_ACCENT), px(2))
            QuickMenuFillRounded(graphics
                , left + px(6), selectedTop + px(7), barWidth, boxHeight - px(14)
                , barWidth / 2, QuickMenuArgb(QM_ACCENT))
        }

        for index, row in QuickMenuRows {
            selected := (index = QuickMenuSelected)
            top := px(glowPad + ((index - 1) * rowHeight) + 3)
            labelLeft := left + textPad + (selected ? px(10) : 0)
            labelWidth := (boxWidth * 0.52) - textPad
            QuickMenuDrawText(graphics, row["label"]
                , selected ? labelFontBold : labelFont
                , QuickMenuArgb(selected ? QM_LABEL_SELECTED : QM_LABEL)
                , labelLeft, top, labelWidth, boxHeight, 0)
            valueLeft := left + (boxWidth * 0.52)
            QuickMenuDrawText(graphics, QuickMenuRowValueText(row), valueFont
                , QuickMenuArgb(selected ? QM_ACCENT : QM_VALUE)
                , valueLeft, top, (boxWidth * 0.48) - textPad, boxHeight, 2)
        }

        if labelFont
            DllCall("gdiplus\GdipDeleteFont", "Ptr", labelFont)
        if labelFontBold
            DllCall("gdiplus\GdipDeleteFont", "Ptr", labelFontBold)
        if valueFont
            DllCall("gdiplus\GdipDeleteFont", "Ptr", valueFont)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
    }

    DllCall("SelectObject", "Ptr", memDC, "Ptr", previous)
    DllCall("DeleteDC", "Ptr", memDC)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", screenDC)

    ; Suppress the Static control's erase/paint between images. STM_SETIMAGE
    ; invalidates the control; without this atomic swap Windows briefly exposes its
    ; background before drawing the new bitmap, which reads as a flash on each move.
    replaced := 0
    try DllCall("User32\SendMessageW", "Ptr", QuickMenuRowsCtrl.Hwnd
        , "UInt", 0x000B, "Ptr", 0, "Ptr", 0)
    handedOver := false
    try {
        replaced := SendMessage(0x0172, 0, bitmap, QuickMenuRowsCtrl)
        handedOver := true
    } catch as err {
        ; try/finally with no catch RE-THROWS, and every line below that frees a
        ; bitmap sits after this block. An STM_SETIMAGE that throws therefore
        ; leaked the surface it had just composed AND left QuickMenuRowsBitmap
        ; pointing at the previous one -- once per repaint, on a menu that
        ; repaints on every keypress. The code twenty lines up already treats GDI
        ; handle exhaustion as a real state worth naming; this is the path that
        ; would cause it.
        try LogLine("Quick Menu: the row bitmap could not be handed to the "
            . "control: " err.Message, "Warning")
    } finally {
        try DllCall("User32\SendMessageW", "Ptr", QuickMenuRowsCtrl.Hwnd
            , "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
        if !QuickMenuRedrawSuspended {
            ; RDW_INVALIDATE | RDW_NOERASE | RDW_UPDATENOW
            try DllCall("User32\RedrawWindow", "Ptr", QuickMenuRowsCtrl.Hwnd
                , "Ptr", 0, "Ptr", 0, "UInt", 0x0121)
        }
    }
    ; The control never took it, so this function still owns it. Free it here or
    ; it is unreachable the moment the local goes out of scope.
    if !handedOver {
        try DllCall("DeleteObject", "Ptr", bitmap)
        return
    }
    ; STM_SETIMAGE returns the bitmap it replaced. Not deleting it leaks one
    ; bitmap per repaint, and the menu repaints on every keypress.
    if (replaced && replaced != bitmap)
        try DllCall("DeleteObject", "Ptr", replaced)
    if (QuickMenuRowsBitmap && QuickMenuRowsBitmap != bitmap && QuickMenuRowsBitmap != replaced)
        try DllCall("DeleteObject", "Ptr", QuickMenuRowsBitmap)
    QuickMenuRowsBitmap := bitmap
}

QuickMenuSelectFirst() {
    global QuickMenuSelected
    QuickMenuSelected := 1
    QuickMenuRefresh()
}

QuickMenuSelectLast() {
    global QuickMenuSelected, QuickMenuRows
    QuickMenuSelected := Max(1, QuickMenuRows.Length)
    QuickMenuRefresh()
}

RegisterQuickMenuKeys() {
    HotIf QuickMenuKeyboardActive
    Hotkey("Up", (*) => QuickMenuMoveSelection(-1))
    Hotkey("Down", (*) => QuickMenuMoveSelection(1))
    Hotkey("Left", (*) => QuickMenuAdjustSelected(-1))
    Hotkey("Right", (*) => QuickMenuAdjustSelected(1))
    Hotkey("Enter", (*) => QuickMenuActivateSelected())
    Hotkey("NumpadEnter", (*) => QuickMenuActivateSelected())
    Hotkey("Space", (*) => QuickMenuActivateSelected())
    Hotkey("Backspace", (*) => QuickMenuGoBack())
    Hotkey("Delete", (*) => QuickMenuCloseSelected())
    Hotkey("Home", (*) => QuickMenuSelectFirst())
    Hotkey("End", (*) => QuickMenuSelectLast())
    HotIf
}

ShutdownGdiPlus() {
    global GdiPlusToken, GdiPlusModule
    if GdiPlusToken {
        try DllCall("gdiplus\GdiplusShutdown", "Ptr", GdiPlusToken)
        GdiPlusToken := 0
    }
    if GdiPlusModule {
        try DllCall("FreeLibrary", "Ptr", GdiPlusModule)
        GdiPlusModule := 0
    }
}

ShutdownRtssHooksApi() {
    global RtssHooksModule, RtssHooksDllPath
    global RtssGetFlagsProc, RtssSetFlagsProc
    global RtssLoadProfileProc, RtssGetProfilePropertyProc
    global RtssSetProfilePropertyProc, RtssSaveProfileProc, RtssUpdateProfilesProc
    if RtssHooksModule
        try DllCall("Kernel32\FreeLibrary", "Ptr", RtssHooksModule, "Int")
    RtssHooksModule := 0
    RtssHooksDllPath := ""
    RtssGetFlagsProc := 0
    RtssSetFlagsProc := 0
    RtssLoadProfileProc := 0
    RtssGetProfilePropertyProc := 0
    RtssSetProfilePropertyProc := 0
    RtssSaveProfileProc := 0
    RtssUpdateProfilesProc := 0
}

; ------------------------------------------------------------------------------
; RTSS frame cap
; ------------------------------------------------------------------------------
; The model these functions implement is documented in full beside the frame-cap
; code that remains in each tree. The short version, because it is load-bearing
; here: RTSS exposes a global limiter FLAG (bit 0x4 = disabled) and a per-profile
; FramerateLimit value, and "Off" maps to the flag, never to the value. Writing 0
; would destroy the user's number.
;
; RTSS persists the value in its own global profile but not the flag, which is
; runtime state in its shared memory -- and "Custom" is a SteamShell concept RTSS
; never sees at all. That is why the selection is recorded and restored here
; rather than being read back from RTSS.
; ------------------------------------------------------------------------------

; Cancels a value that was being dialled in but must not land.
;
; Needed because the commit is deferred: cycling from Custom to a preset while a
; pending value is still in flight would otherwise let the timer fire afterwards
; and overwrite the preset the user just chose.
CancelPendingRtssFrameCap() {
    global RtssPendingFrameCap
    RtssPendingFrameCap := 0
    SetTimer(CommitRtssPendingFrameCap, 0)
}

CommitRtssPendingFrameCap() {
    global RtssPendingFrameCap
    if (RtssPendingFrameCap <= 0)
        return
    value := RtssPendingFrameCap
    RtssPendingFrameCap := 0
    if SetRtssGlobalFrameLimit(value)
        PersistRtssCustomFrameCap(value)
}

GetRtssAvailability() {
    global EnableRTSSIntegration, RtssPath
    if !EnableRTSSIntegration
        return "Setup Required"
    if ProcessExist("RTSS.exe")
        return "Running"
    return ResolveRtssExecutablePath() != ""
        ? "Ready To Start"
        : "Not Found"
}

; Resolves the flag and the value into the single state the row displays:
;   "off"         limiter flag cleared, or flag set with no target
;   "preset"      a value from RtssFrameCapPresets
;   "configured"  the separately configured Preset value
;   "custom"      any other non-zero value, or the user cycling to Custom
GetRtssFrameCapState() {
    global RtssPresetFrameCap, RtssFrameCapCustomMode
    state := GetRtssGlobalState()
    if !IsObject(state)
        return 0
    fps := RtssGlobalFrameLimit()
    if (!state["limiter"] || fps <= 0)
        return Map("mode", "off", "fps", fps, "limiter", state["limiter"])
    if RtssFrameCapCustomMode
        return Map("mode", "custom", "fps", fps, "limiter", true)
    if IsRtssFrameCapPreset(fps)
        return Map("mode", "preset", "fps", fps, "limiter", true)
    ; A configured Preset that duplicates a standard cap is deliberately shown
    ; as that standard cap. RTSS stores only the number, so treating identical
    ; values as two distinct entries would make the next cycle jump over every
    ; standard cap between them.
    if (RtssPresetFrameCap > 0 && fps = RtssPresetFrameCap)
        return Map("mode", "configured", "fps", fps, "limiter", true)
    return Map("mode", "custom", "fps", fps, "limiter", true)
}

IsRtssFrameCapPreset(fps) {
    global RtssFrameCapPresets
    for _, preset in RtssFrameCapPresets {
        if (fps = preset)
            return true
    }
    return false
}

RtssFrameCapValueText() {
    state := GetRtssFrameCapState()
    if !IsObject(state)
        return "Unavailable"
    if !RtssFrameCapWritable()
        return state["mode"] = "off" ? "OFF (read-only)" : state["fps"] " FPS (read-only)"
    switch state["mode"] {
        case "off":
            return "‹ OFF ›"
        case "configured":
            return "‹ PRESET · " state["fps"] " FPS ›"
        case "custom":
            return "‹ CUSTOM ›"
    }
    return "‹ " state["fps"] " FPS ›"
}

; True when the frame cap can actually be applied. Checked before the Quick Menu
; offers a value the user cannot make stick.
;
; Two separate conditions, because they have different causes and different
; answers -- see RtssFrameCapBlockedReason.
RtssFrameCapWritable() {
    return RtssFrameCapBlockedReason() = ""
}

; Why the frame cap cannot be written, or "" when it can.
;
; The second condition is not a build limitation, it is a privilege one, and it
; is invisible through the API. RTSSHooks64.dll is loaded into OUR process, so
; SaveProfile writes with OUR token. RTSS installs under Program Files by
; default, which a standard user can read but not write -- and nothing reports
; the failure: SetProfileProperty succeeds against the in-memory copy,
; SaveProfile fails silently, and UpdateProfiles reloads the old value over the
; top. Every read afterwards returns the number that was already there.
;
; Measured 2026-08-02. Running unelevated, cycling the Frame Limit row logged a
; successful write on every press while the on-disk Global profile never
; changed; the row therefore never left the entry matching that stale number, so
; the standard caps looked unreachable and Custom looked like it reverted.
; Running SteamShell as administrator fixed it outright. The limiter flag worked
; throughout, because SetFlags goes through RTSS's shared memory and not a file.
;
; This is detected from a real failed write rather than by probing, because the
; honest test -- creating a file in RTSS's Profiles directory -- risks leaving a
; stray file somewhere RTSS enumerates profiles from.
RtssFrameCapBlockedReason() {
    global RtssSetProfilePropertyProc, RtssSaveProfileProc, RtssLoadProfileProc
    global RtssFrameCapWriteBlocked
    if !(RtssLoadProfileProc && RtssSetProfilePropertyProc && RtssSaveProfileProc)
        return "This RTSS build cannot set the frame cap directly"
    if RtssFrameCapWriteBlocked
        return "RTSS profile writes need administrator rights"
    return ""
}

RtssGlobalFrameLimit() {
    global RtssFrameLimitCacheFps, RtssFrameLimitCacheTick
    static CACHE_MS := 400
    if (RtssFrameLimitCacheTick
        && A_TickCount - RtssFrameLimitCacheTick < CACHE_MS)
        return RtssFrameLimitCacheFps
    limit := GetRtssFrameLimit("")
    RtssFrameLimitCacheFps := IsObject(limit) ? limit["fps"] : 0
    RtssFrameLimitCacheTick := A_TickCount
    return RtssFrameLimitCacheFps
}

; Which entry of the cycle a bare FPS number corresponds to. Used when the
; limiter is re-enabled from Off, where the number is all RTSS retained.
RtssFrameCapModeForFps(fps) {
    global RtssPresetFrameCap
    if (fps <= 0)
        return "off"
    if IsRtssFrameCapPreset(fps)
        return "preset"
    if (RtssPresetFrameCap > 0 && fps = RtssPresetFrameCap)
        return "configured"
    return "custom"
}

; Records the selection so it can be reapplied after RTSS restarts.
;
; RTSS keeps the FPS number in its global profile but nothing keeps the rest:
; the limiter on/off state is the runtime flag bit 0x4 in RTSS shared memory,
; and "Custom" exists only in RtssFrameCapCustomMode here. After a reboot the
; flag comes back cleared and the mode comes back false, so a selection the user
; made yesterday was gone with nothing to restore it from.
;
; The FPS is deliberately stored even for "off", for the same reason the Off
; entry never writes 0 into the profile: the number is what makes turning the
; limiter back on land where the user left it.
PersistRtssFrameCapSelection(mode, fps) {
    global RtssLastFrameCapMode, RtssLastFrameCapFps
    mode := StrLower(Trim(mode))
    if !RtssFrameCapModeIsKnown(mode)
        return false
    fps := ClampInt(fps, 0, 1000)
    if (RtssLastFrameCapMode = mode && RtssLastFrameCapFps = fps)
        return true
    ; Both keys or neither. A recorded mode that disagrees with its recorded FPS
    ; would restore something the user never selected.
    if !SharedPersistSettings([
        Map("section", "RTSS", "key", "LastFrameCapMode", "value", mode),
        Map("section", "RTSS", "key", "LastFrameCapFps", "value", fps)
    ])
        return false
    RtssLastFrameCapMode := mode
    RtssLastFrameCapFps := fps
    return true
}

; Records the current live state without assuming what it should be. For the two
; limiter toggles, which flip the flag and leave the number alone.
PersistRtssFrameCapStateNow() {
    global RtssLastFrameCapFps
    state := GetRtssFrameCapState()
    if !IsObject(state)
        return false
    fps := state["fps"] > 0 ? state["fps"] : RtssLastFrameCapFps
    return PersistRtssFrameCapSelection(state["mode"], fps)
}

; Reapplies the recorded selection once RTSS is available.
;
; Never starts RTSS. SteamShell restoring a frame cap is not a reason to launch
; a program the user did not ask for, and RTSS usually arrives a little later
; through Steam or a startup entry -- which is exactly why this is a polling
; tick with a deadline rather than a one-shot at startup.
RestoreRtssFrameLimitTick(*) {
    global EnableRTSSIntegration, RtssRestoreFrameLimitOnStartup
    global RtssUseDllIntegration
    global RtssLastFrameCapMode, RtssLastFrameCapFps, RtssFrameCapCustomMode
    static deadlineTick := 0
    if !deadlineTick
        deadlineTick := A_TickCount + 120000

    if (!EnableRTSSIntegration || !RtssRestoreFrameLimitOnStartup
        || RtssLastFrameCapMode = "") {
        SetTimer(RestoreRtssFrameLimitTick, 0)
        return
    }
    ; The shortcut fallback can only toggle; it cannot select a specific FPS.
    ; Stop with an accurate reason rather than polling out to the deadline and
    ; reporting that RTSS never arrived.
    if !RtssUseDllIntegration {
        SetTimer(RestoreRtssFrameLimitTick, 0)
        LogLine(
            "Restoring the last Frame Limit selection requires [RTSS] UseDllIntegration; it was skipped.",
            "Warning")
        return
    }
    if (A_TickCount > deadlineTick) {
        SetTimer(RestoreRtssFrameLimitTick, 0)
        LogLine(
            "RTSS did not become available in time; the last Frame Limit selection ("
            . RtssLastFrameCapMode ") was not restored.", "Warning")
        return
    }
    if !ProcessExist("RTSS.exe")
        return
    state := GetRtssFrameCapState()
    if !IsObject(state)
        return
    if !RtssFrameCapWritable() {
        SetTimer(RestoreRtssFrameLimitTick, 0)
        LogLine(
            RtssFrameCapBlockedReason()
            . "; the last Frame Limit selection was not restored.",
            "Warning")
        return
    }

    SetTimer(RestoreRtssFrameLimitTick, 0)
    if (RtssLastFrameCapMode = "off") {
        RtssFrameCapCustomMode := false
        if (state["limiter"]
            && !ApplyRtssGlobalState("limiter", false)) {
            LogLine(
                "The last Frame Limit selection was OFF, but RTSS did not confirm disabling the limiter.",
                "Warning")
            return
        }
        LogLine("Restored the last Frame Limit selection: OFF.")
        return
    }
    if (RtssLastFrameCapFps <= 0) {
        LogLine(
            "The last Frame Limit selection (" RtssLastFrameCapMode
            . ") had no recorded FPS; nothing was restored.", "Warning")
        return
    }
    ; Only write when RTSS does not already agree. The profile write is a real
    ; edit to RTSS's own configuration, so it should not happen on every boot
    ; when RTSS kept the value on its own.
    applied := true
    if (state["fps"] != RtssLastFrameCapFps)
        applied := SetRtssGlobalFrameLimit(RtssLastFrameCapFps)
    if !applied {
        LogLine(
            "The last Frame Limit selection could not be written to RTSS.", "Warning")
        return
    }
    if (!state["limiter"]
        && !ApplyRtssGlobalState("limiter", true)) {
        LogLine(
            "The last Frame Limit FPS was restored, but RTSS did not confirm enabling the limiter.",
            "Warning")
        return
    }
    RtssFrameCapCustomMode := (RtssLastFrameCapMode = "custom")
    LogLine(
        "Restored the last Frame Limit selection: " StrUpper(RtssLastFrameCapMode)
        . " at " RtssLastFrameCapFps " FPS.")
}

; ==============================================================================
; PROCESS TOKEN IDENTITY AND COMMAND LINES
; ==============================================================================
; Shared because "is that process running as the same user, in the same session,
; at High integrity?" is the same question in both programs, asked of the same
; payload: standalone verifies its elevated helper before using it, and XFE
; verifies the identical binary before using its opt-in RTSS helper.
;
; Deliberately NOT here: InitializeExpectedInteractiveIdentity, which reads
; standalone's bootstrap identity arguments. Standalone re-launches itself
; across the elevation boundary and has to carry the pre-elevation identity
; forward; XFE never does, and records its own token directly. Both trees must
; define the ExpectedInteractiveUserSid and ExpectedInteractiveSessionId globals
; that the verification below compares against.

; ==============================================================================
; ELEVATED RTSS FRAME CAP REQUEST CHANNEL
; ==============================================================================
; Shared because both trees ask the same elevated helper for the same thing, in
; the same words: a bounded FPS number and, for a per-game save, a profile name.
; Standalone routes every frame-cap write through it; XFE routes them through it
; only when the user has opted in to its helper.
;
; Each tree must define ElevatedRtssRequestPath(), which is the only part that
; differs -- the two programs keep their data in different places -- plus the
; globals below: ElevatedRtssEventHandle, ElevatedRtssDoneEventHandle,
; RtssElevatedRequestSeq, ElevatedHelperAvailable, RtssElevatedFrameCapWrites
; and RtssFrameLimitCacheTick.

; ------------------------------------------------------------------------------
; Elevated RTSS frame cap request
; ------------------------------------------------------------------------------
; RTSSHooks64.dll is loaded into THIS process, so SaveProfile writes with this
; account's token, and RTSS's default install is under Program Files. Everything
; else about the frame cap works unelevated -- reads, the limiter flag, the
; cycling -- so the elevated helper is asked for exactly one thing: put this
; number in RTSS's global profile. See ApplyElevatedRtssFrameLimit for why the
; result is verified here rather than reported back from there.
ElevatedRtssEventName() {
    global ScriptPid
    return "Local\SteamShellRtssApply-" ScriptPid
}

; The completion event's name, as a function for the same reason the request
; event's name is one.
;
; This half of the channel used to be an inline literal in two files at once --
; here and in SteamShell-Helper.ahk -- with nothing relating them. The helper
; cannot include this file, so its copy is still a literal, but it is now pinned
; against this one by Assert-SharedParity: an edit to either without the other
; would leave main waiting on an event nobody ever sets, which presents as the
; frame cap silently timing out rather than as anything nameable.
ElevatedRtssDoneEventName() {
    global ScriptPid
    return "Local\SteamShellRtssDone-" ScriptPid
}

; Signalled by the helper when it has finished a request, so this process can
; stay completely out of RTSS until then.
;
; Without it, main polled RtssGlobalFrameLimit while the helper was mid-sequence
; -- and that calls LoadProfile, which reloads RTSS's shared profile state from
; disk. Two processes were interleaving calls into the same state, so a poll
; could reload the old value on top of the helper's SetProfileProperty before
; its SaveProfile ran. That is why a cap sometimes took several presses: nothing
; was wrong with the write, it was being trampled by the checking.
EnsureElevatedRtssDoneEvent() {
    global ElevatedRtssDoneEventHandle
    if ElevatedRtssDoneEventHandle
        return true
    ElevatedRtssDoneEventHandle := DllCall(
        "Kernel32\CreateEventW",
        "Ptr", 0,
        "Int", false,  ; auto-reset: one completion is one request
        "Int", false,
        "WStr", ElevatedRtssDoneEventName(),
        "Ptr")
    if !ElevatedRtssDoneEventHandle
        LogLine(
            "The elevated RTSS completion event could not be created ("
            . A_LastError ").", "Warning")
    return ElevatedRtssDoneEventHandle != 0
}

EnsureElevatedRtssEvent() {
    global ElevatedRtssEventHandle
    if ElevatedRtssEventHandle
        return true
    ElevatedRtssEventHandle := DllCall(
        "Kernel32\CreateEventW",
        "Ptr", 0,
        "Int", false,  ; auto-reset: one signal is one request
        "Int", false,
        "WStr", ElevatedRtssEventName(),
        "Ptr")
    if !ElevatedRtssEventHandle
        LogLine(
            "The elevated RTSS request event could not be created ("
            . A_LastError ").", "Warning")
    return ElevatedRtssEventHandle != 0
}

; profileName is "" for the global profile, or a bare executable name for a
; per-game one. The helper refuses anything that is not a plain executable name
; naming a process that is currently running, so this is a request rather than
; an instruction -- see the header comment in SteamShell-Helper.ahk.
RequestElevatedRtssFrameLimit(fps, profileName := "") {
    global ElevatedRtssEventHandle, ElevatedRtssDoneEventHandle
    global RtssElevatedRequestSeq
    global ElevatedHelperAvailable, RtssElevatedFrameCapWrites
    if !RtssElevatedFrameCapWrites
        return false
    if !ElevatedHelperAvailable
        return false
    if !EnsureElevatedRtssEvent()
        return false
    requestPath := ElevatedRtssRequestPath()
    RtssElevatedRequestSeq += 1
    try {
        ; Everything else first, Seq last. The helper acts on a sequence number
        ; it has not seen before, so ordering these is what makes a torn read
        ; impossible.
        IniWrite(fps, requestPath, "Request", "Fps")
        IniWrite(profileName, requestPath, "Request", "Profile")
        ; Cleared with the rest, before Seq. The completion the wait below
        ; accepts is identified by this value, and a Result left in the file by a
        ; PREVIOUS run of this process could otherwise match the sequence number
        ; this run is about to reach -- both counters start from one.
        IniWrite(-1, requestPath, "Result", "Seq")
        IniWrite(RtssElevatedRequestSeq, requestPath, "Request", "Seq")
    } catch as err {
        LogLine("The RTSS frame cap request could not be written: " err.Message,
            "Warning")
        return false
    }
    ; Cleared before the request, not after the wait: a completion left over
    ; from a timed-out earlier request would otherwise satisfy this one instantly.
    if EnsureElevatedRtssDoneEvent()
        DllCall("Kernel32\ResetEvent", "Ptr", ElevatedRtssDoneEventHandle, "Int")
    if !DllCall("Kernel32\SetEvent", "Ptr", ElevatedRtssEventHandle, "Int") {
        LogLine("The RTSS frame cap request could not be signalled ("
            . A_LastError ").", "Warning")
        return false
    }
    return true
}

; Hands one number to the helper, then proves the outcome from RTSS instead of
; believing the helper.
;
; Nothing is reported back from the elevated process on purpose. The question
; worth answering is not "did the helper think it succeeded" but "does RTSS's
; configuration now hold the right number", and only the second is worth acting
; on. LoadProfile re-reads the profile from disk -- the same mechanism that used
; to reload the OLD value over an unelevated write is exactly what makes the
; elevated one visible here.
; Blocks until the helper reports the request finished, or the deadline passes.
;
; A kernel wait rather than a polling loop, specifically so this process makes
; NO RTSS calls while the helper is working -- see EnsureElevatedRtssDoneEvent
; for what that cost when it did.
WaitForElevatedRtssRequest() {
    global ElevatedRtssDoneEventHandle, RtssElevatedRequestSeq
    static TIMEOUT_MS := 3000
    if !EnsureElevatedRtssDoneEvent()
        return false
    deadline := A_TickCount + TIMEOUT_MS
    Loop {
        remaining := deadline - A_TickCount
        if (remaining <= 0)
            return false
        if (DllCall(
            "Kernel32\WaitForSingleObject",
            "Ptr", ElevatedRtssDoneEventHandle,
            "UInt", remaining,
            "UInt") != 0) ; anything but WAIT_OBJECT_0
            return false
        ; WHICH request finished?
        ;
        ; Resetting this event before issuing a request does not make a stale
        ; completion impossible, because the stale one arrives AFTER the reset:
        ; a request that timed out here at three seconds and finished in the
        ; helper a moment later signalled the next request's wait instead. This
        ; process then read RTSS while the helper was mid-sequence on the new
        ; request -- the interleaving this whole event exists to prevent -- and
        ; reported a write that was about to succeed as a failure.
        ;
        ; So the completion has to identify itself. Anything else is somebody
        ; else's, and waiting out the remaining time is the right answer rather
        ; than believing it.
        completed := -1
        try completed := Integer(Trim(
            IniRead(ElevatedRtssRequestPath(), "Result", "Seq", "-1")))
        if (completed = RtssElevatedRequestSeq)
            return true
        LogLine("Ignored an RTSS completion for request " completed
            . " while waiting for request " RtssElevatedRequestSeq ".")
    }
}

ApplyElevatedRtssFrameLimit(fps) {
    global RtssFrameLimitCacheTick
    if !RequestElevatedRtssFrameLimit(fps)
        return false
    ; Nothing may repaint the Frame Limit row while this is in flight.
    ;
    ; The wait yields, and AutoHotkey will run the Quick Menu's refresh timer
    ; during it. That timer paints the row from RTSS's CURRENT value, which is
    ; still the OLD one until the helper is done -- so a Custom value dialled in
    ; with Left/Right visibly jumped back to the previous number and then
    ; forward again. The value was never wrong, only briefly stale, but a number
    ; that moves on its own is indistinguishable from one that did not take.
    previousCritical := Critical("On")
    try {
        if !WaitForElevatedRtssRequest() {
            LogLine("The elevated helper did not finish the RTSS frame cap "
                . fps " in time. See SteamShell-Helper.log for the reason.",
                "Warning")
            return false
        }
        ; Only now is it safe to touch RTSS: the helper has finished its own
        ; LoadProfile/SetProfileProperty/SaveProfile/UpdateProfiles sequence,
        ; and this read would otherwise have reloaded the profile underneath it.
        RtssFrameLimitCacheTick := 0
        if (RtssGlobalFrameLimit() != fps) {
            LogLine("The elevated helper reported the RTSS frame cap " fps
                . " finished, but RTSS still reports something else.", "Warning")
            return false
        }
        NotifyRtssSettingsChanged()
        RtssFrameLimitCacheTick := 0
        LogLine("RTSS global FramerateLimit set to " fps
            . " through the elevated helper.")
        return true
    } finally {
        Critical(previousCritical)
    }
}

; True when the elevated helper is the right way to write RTSS, which is also
; exactly when writing from this process cannot work.
;
; The two conditions are the same condition. StartElevatedInputHelper refuses to
; run when A_IsAdmin, so a helper exists only in an unelevated session -- and an
; unelevated session is precisely the one where SaveProfile fails silently
; against a Program Files install. There is therefore no case where trying
; in-process first is worth doing: it either cannot work, or there is no helper
; to fall back to.
;
; This matters most for per-game profiles, where trying first was actively
; harmful. Verifying a named profile re-reads the copy SetProfileProperty just
; wrote, so the check PASSED while SaveProfile had silently done nothing, and
; the save was reported as succeeding without the helper ever being asked. The
; global cap escaped that only by accident: UpdateProfiles reloads from disk and
; clobbers the in-memory value, which is what made its read-back honest.
ElevatedRtssWritesAvailable() {
    global ElevatedHelperAvailable, RtssElevatedFrameCapWrites
    return ElevatedHelperAvailable && RtssElevatedFrameCapWrites
}

; The per-game equivalent of ApplyElevatedRtssFrameLimit.
;
; Kept separate rather than folded in with a parameter because the two verify
; different things: the global cap is confirmed through RtssGlobalFrameLimit,
; which is cached and drives the Quick Menu row, while this reads a named
; profile that nothing else looks at. Sharing a function would have meant a
; branch in the middle of the wait loop for no saving.
ApplyElevatedRtssProfileFrameLimit(exeName, fps) {
    if !RequestElevatedRtssFrameLimit(fps, exeName)
        return false
    previousCritical := Critical("On")
    try {
        if !WaitForElevatedRtssRequest() {
            LogLine("The elevated helper did not finish the RTSS profile "
                . exeName " in time. See SteamShell-Helper.log for the reason.",
                "Warning")
            return false
        }
        saved := GetRtssFrameLimit(exeName)
        if (!IsObject(saved) || saved["fps"] != fps) {
            LogLine("The elevated helper reported the RTSS profile " exeName
                . " finished, but it does not hold " fps ".", "Warning")
            return false
        }
        NotifyRtssSettingsChanged()
        LogLine("RTSS profile " exeName " saved with FramerateLimit " fps
            . " through the elevated helper.")
        return true
    } finally {
        Critical(previousCritical)
    }
}

; Waits for a just-launched helper to satisfy VerifyElevatedHelperProcess.
;
; Shared, and moved here because the parity check reported it as having
; become identical in both trees -- which is exactly the job that checker was
; kept for after the shared file removed the drift it used to guard against.
; VerifyElevatedHelperProcess has since joined it here; the claim that used to
; sit on this line, that the two trees compared different helper paths, was not
; true of the code -- both read the same global, and only the failure message
; named its own product.
WaitForVerifiedElevatedHelper(pid, &failureReason, timeoutMs := 2500) {
    deadline := A_TickCount + Max(0, timeoutMs)
    Loop {
        if VerifyElevatedHelperProcess(pid, &failureReason)
            return true
        if !pid || !ProcessExist(pid) || A_TickCount >= deadline
            break
        Sleep 100
    }
    return false
}

; ==============================================================================
; ELEVATED HELPER PROTECTION GATE
; ==============================================================================
; The two functions below decide whether a binary is safe to hand a
; High-integrity token. They were standalone-only until XFE gained its opt-in
; RTSS helper, and XFE_PARITY_NOTES.md previously recorded that they never would
; be shared. That entry has been reversed there rather than quietly dropped.
;
; They ask a question about a path and an expected version, and nothing about
; either program: no shell registration, no installation mode, no Setup. That is
; precisely why they are the part of the privilege architecture that CAN be
; shared while the deployment half stays per-product.
;
; Both trees must define the global ElevatedHelperExpectedVersion, and both must
; agree on its value: the payload is one file, embedded once in SteamShell.exe
; and deployed by one Setup Assistant.

; Both the helper binary and its directory must pass. Write access to the
; directory is enough to delete and replace the binary inside it.
;
; The write check alone is NOT sufficient, and trusting it shipped a broken
; install. It asks only "can anyone outside SYSTEM/Administrators write here?",
; which an empty DACL satisfies perfectly -- nobody can write to a file nobody
; can touch. A helper left with no ACEs at all therefore passed every check
; while being impossible to read, launch, or replace. Hardening has to prove the
; binary is still USABLE as well as unwritable, so the readability test below is
; part of the gate rather than a diagnostic.
ElevatedHelperLocationIsProtected(helperPath, &failureReason) {
    global ElevatedHelperExpectedVersion
    failureReason := ""
    helperDirectory := ""
    SplitPath(helperPath, , &helperDirectory)
    for _, target in [helperDirectory, helperPath] {
        if (target = "")
            continue
        if !SteamShellPathIsAdminOnlyWritable(target, &grantedTo, &checkError) {
            failureReason := grantedTo != ""
                ? target " is writable by " grantedTo
                    . ", so it cannot be trusted with an elevated token."
                : checkError
            return false
        }
    }
    ; Reading the version resource needs FILE_READ_DATA, which is exactly what an
    ; over-restrictive ACL takes away. Cheap, and it fails in the same direction
    ; as everything else here: no proof of a usable helper means no elevation.
    readVersion := ""
    try readVersion := FileGetVersion(helperPath)
    if (readVersion = "") {
        failureReason := helperPath " cannot be read by this account, so its "
            . "permissions are too restrictive to launch it. Re-run Setup to "
            . "repair the helper directory."
        return false
    }
    if (readVersion != ElevatedHelperExpectedVersion) {
        failureReason := helperPath " reports version " readVersion
            . "; expected " ElevatedHelperExpectedVersion "."
        return false
    }
    return true
}

; ==============================================================================
; Display selection, and the RTSS reads that go with it
; ==============================================================================
; These hold the selection the user is cycling through and tell them what
; happened, so they touch per-tree globals and the notification surface -- which
; is why they live here rather than in SteamShell-Common.ahk, and why the helper
; does not get them. The Windows API calls underneath them ARE in Common.
;
; They were duplicated, and the duplication is what let the KEEP bug be fixed
; twice and the Apply row read "Select To Apply" in one program and
; "Select to apply" in the other. Notifications go through SharedNotify.

DistinctDisplayResolutions() {
    global QuickMenuDisplayModes
    seen := Map()
    resolutions := []
    for _, mode in QuickMenuDisplayModes {
        key := mode["width"] "x" mode["height"]
        if seen.Has(key)
            continue
        seen[key] := true
        resolutions.Push(Map("width", mode["width"], "height", mode["height"]))
    }
    return resolutions
}

FrequenciesForResolution(width, height) {
    global QuickMenuDisplayModes
    frequencies := []
    for _, mode in QuickMenuDisplayModes {
        if (mode["width"] = width && mode["height"] = height)
            frequencies.Push(mode["frequency"])
    }
    return frequencies
}

EnsureDisplaySelection() {
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    if (!DisplaySelectedWidth || !DisplaySelectedHeight) {
        current := GetPrimaryDisplayMode()
        if IsObject(current) {
            DisplaySelectedWidth := current["width"]
            DisplaySelectedHeight := current["height"]
            DisplaySelectedFrequency := current["frequency"]
        } else {
            resolutions := DistinctDisplayResolutions()
            if (resolutions.Length = 0)
                return
            DisplaySelectedWidth := resolutions[1]["width"]
            DisplaySelectedHeight := resolutions[1]["height"]
            DisplaySelectedFrequency := 0
        }
    }
    frequencies := FrequenciesForResolution(
        DisplaySelectedWidth, DisplaySelectedHeight)
    if (frequencies.Length = 0)
        return
    for _, frequency in frequencies {
        if (frequency = DisplaySelectedFrequency)
            return
    }
    best := frequencies[1]
    for _, frequency in frequencies {
        if (frequency > best)
            best := frequency
    }
    DisplaySelectedFrequency := best
}

CycleDisplayResolution(direction) {
    global DisplaySelectedWidth, DisplaySelectedHeight
    resolutions := DistinctDisplayResolutions()
    if (resolutions.Length = 0)
        return
    selectedIndex := 1
    for index, resolution in resolutions {
        if (resolution["width"] = DisplaySelectedWidth
            && resolution["height"] = DisplaySelectedHeight) {
            selectedIndex := index
            break
        }
    }
    selectedIndex += direction
    if (selectedIndex < 1)
        selectedIndex := resolutions.Length
    if (selectedIndex > resolutions.Length)
        selectedIndex := 1
    DisplaySelectedWidth := resolutions[selectedIndex]["width"]
    DisplaySelectedHeight := resolutions[selectedIndex]["height"]
    EnsureDisplaySelection()
}

CycleDisplayFrequency(direction) {
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    frequencies := FrequenciesForResolution(
        DisplaySelectedWidth, DisplaySelectedHeight)
    if (frequencies.Length = 0)
        return
    selectedIndex := 1
    for index, frequency in frequencies {
        if (frequency = DisplaySelectedFrequency) {
            selectedIndex := index
            break
        }
    }
    selectedIndex += direction
    if (selectedIndex < 1)
        selectedIndex := frequencies.Length
    if (selectedIndex > frequencies.Length)
        selectedIndex := 1
    DisplaySelectedFrequency := frequencies[selectedIndex]
}

CycleDisplayScale(direction) {
    global DisplaySelectedScalePercent
    info := EnsureDisplayScaleSelection()
    if !IsObject(info)
        return
    options := info["options"]
    selectedIndex := 1
    for index, option in options {
        if (option = DisplaySelectedScalePercent) {
            selectedIndex := index
            break
        }
    }
    selectedIndex += direction
    if (selectedIndex < 1)
        selectedIndex := options.Length
    if (selectedIndex > options.Length)
        selectedIndex := 1
    DisplaySelectedScalePercent := options[selectedIndex]
}

GetDisplayApplyValue() {
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    global DisplaySelectedScalePercent
    global DisplayPendingOldMode, DisplayPendingUntilTick
    if IsObject(DisplayPendingOldMode) {
        seconds := Max(0, Ceil((DisplayPendingUntilTick - A_TickCount) / 1000))
        return "Select To KEEP (" seconds "s)"
    }
    current := GetPrimaryDisplayMode()
    scale := GetPrimaryDisplayScale()
    scaleSame := !DisplaySelectedScalePercent
        || (IsObject(scale) && scale["percent"] = DisplaySelectedScalePercent)
    if (IsObject(current) && scaleSame
        && current["width"] = DisplaySelectedWidth
        && current["height"] = DisplaySelectedHeight
        && current["frequency"] = DisplaySelectedFrequency)
        return "CURRENT"
    return "Select To Apply"
}

ApplyDisplaySelection() {
    global QuickMenuDisplayModes
    global DisplaySelectedWidth, DisplaySelectedHeight, DisplaySelectedFrequency
    global DisplaySelectedScalePercent
    global DisplayPendingOldMode, DisplayPendingOldScale, DisplayPendingUntilTick
    ; KEEP is answered first, and unconditionally.
    ;
    ; Keeping a change is a state operation -- discard the saved old mode and
    ; stop the revert timer -- and it used to be gated on re-deriving the live
    ; display state and finding it still equal to the selection. That gave the
    ; press four ways to be refused through no fault of the user:
    ;
    ;   - the mode lookup below fails when the driver stops offering the entry;
    ;   - GetPrimaryDisplayMode can fail outright;
    ;   - EnumDisplaySettings(ENUM_CURRENT_SETTINGS) routinely reports 59 Hz for
    ;     a mode enumerated as 60 (59.94), so KEEP silently never worked for
    ;     those modes and always worked for others -- the reported symptom;
    ;   - GetPrimaryDisplayScale goes through QueryDisplayConfig, which can
    ;     return nothing at all while the topology is still settling after the
    ;     very change being confirmed.
    ;
    ; In every one of those cases the 15-second timer kept running and reverted
    ; the change the user had just asked to keep, while the row still read
    ; "Select To KEEP" -- GetDisplayApplyValue has always reported that
    ; unconditionally whenever a change is pending. The label was right and the
    ; handler was wrong.
    if IsObject(DisplayPendingOldMode) {
        ConfirmPrimaryDisplayMode()
        return
    }
    candidate := 0
    for _, mode in QuickMenuDisplayModes {
        if (mode["width"] = DisplaySelectedWidth
            && mode["height"] = DisplaySelectedHeight
            && mode["frequency"] = DisplaySelectedFrequency) {
            candidate := mode
            break
        }
    }
    if !IsObject(candidate) {
        SharedNotify("That display mode is no longer offered", "Warning")
        return
    }
    currentMode := GetPrimaryDisplayMode()
    if !IsObject(currentMode) {
        SharedNotify("Current display mode is unavailable", "Warning")
        return
    }
    currentScale := GetPrimaryDisplayScale()
    modeSame := candidate["width"] = currentMode["width"]
        && candidate["height"] = currentMode["height"]
        && candidate["frequency"] = currentMode["frequency"]
    scaleSame := !DisplaySelectedScalePercent
        || (IsObject(currentScale)
            && currentScale["percent"] = DisplaySelectedScalePercent)
    if (modeSame && scaleSame)
        return
    if (DisplaySelectedScalePercent && !IsObject(currentScale)) {
        SharedNotify("Windows display scaling is unavailable", "Warning")
        return
    }
    modeChanged := false
    if !modeSame {
        if !ApplyPrimaryDisplayMode(candidate) {
            SharedNotify("Windows rejected that display mode", "Warning")
            return
        }
        modeChanged := true
    }
    if !scaleSame && !ApplyPrimaryDisplayScale(DisplaySelectedScalePercent) {
        modeRestored := !modeChanged || ApplyPrimaryDisplayMode(currentMode)
        scaleRestored := !IsObject(currentScale)
            || ApplyPrimaryDisplayScale(currentScale["percent"])
        QueueQuickMenuDisplayReflow()
        SharedNotify(
            modeRestored && scaleRestored
                ? "Windows rejected that display scale; the old settings were restored"
                : "Windows rejected that display scale; not all old settings restored",
            "Warning")
        return
    }
    DisplayPendingOldMode := currentMode
    DisplayPendingOldScale := currentScale
    DisplayPendingUntilTick := A_TickCount + 15000
    SetTimer(DisplayChangeSafetyTick, 500)
    QueueQuickMenuDisplayReflow()
    ; Names the row the user is looking at. It reads "Select To KEEP (Ns)" while
    ; a change is pending, not "CURRENT".
    SharedNotify(
        "Display changed. Select KEEP within 15 seconds or it reverts.",
        "Warning")
}

ConfirmPrimaryDisplayMode() {
    global DisplayPendingOldMode, DisplayPendingOldScale, DisplayPendingUntilTick
    if !IsObject(DisplayPendingOldMode)
        return
    DisplayPendingOldMode := 0
    DisplayPendingOldScale := 0
    DisplayPendingUntilTick := 0
    SetTimer(DisplayChangeSafetyTick, 0)
    SharedNotify("Display settings kept", "Success")
    QuickMenuRefresh()
}

DisplayChangeSafetyTick() {
    global DisplayPendingOldMode, DisplayPendingOldScale
    global DisplayPendingUntilTick, QuickMenuVisible
    if !IsObject(DisplayPendingOldMode) {
        SetTimer(DisplayChangeSafetyTick, 0)
        return
    }
    if (A_TickCount >= DisplayPendingUntilTick) {
        oldMode := DisplayPendingOldMode
        oldScale := DisplayPendingOldScale
        DisplayPendingOldMode := 0
        DisplayPendingOldScale := 0
        DisplayPendingUntilTick := 0
        SetTimer(DisplayChangeSafetyTick, 0)
        modeRestored := ApplyPrimaryDisplayMode(oldMode)
        scaleRestored := !IsObject(oldScale)
            || ApplyPrimaryDisplayScale(oldScale["percent"])
        QueueQuickMenuDisplayReflow()
        if (modeRestored && scaleRestored)
            SharedNotify("Display settings reverted for safety", "Warning")
        else
            SharedNotify("Unable to restore all previous display settings", "Warning")
    }
    ; This is a one-second timer that runs for the whole 15-second revert window,
    ; and the countdown it repaints is only visible while the menu is open.
    if QuickMenuVisible
        QuickMenuRefresh()
}

SetQuickMenuHdrState(enabled) {
    current := GetPrimaryHdrState()
    if !IsObject(current) {
        ; Says only what is true in BOTH trees.
        ;
        ; This used to end "; use A to toggle", which is good advice in
        ; standalone -- A falls back to the Win+Alt+B chord -- and a dead end in
        ; XFE, where A reports the very condition that told the user to press it.
        ; XFE deliberately has no blind-toggle fallback: its validator forbids
        ; the chord outright, because a toggle that cannot report what it did is
        ; how the HDR row behaved before 0.1.14. The behaviours are meant to
        ; differ; the shared MESSAGE was promising one of them everywhere.
        SharedNotify("Windows HDR state is unavailable", "Warning")
        return
    }
    if !current["supported"] {
        SharedNotify("The primary display does not report HDR support", "Warning")
        return
    }
    if current["forceDisabled"] {
        SharedNotify("HDR is disabled by Windows or the display driver", "Warning")
        return
    }
    if (current["enabled"] = enabled) {
        SharedNotify("HDR is already " (enabled ? "on" : "off"))
        return
    }
    if ApplyPrimaryHdrState(enabled) {
        SharedNotify("HDR turned " (enabled ? "on" : "off"), "Success")
        ; The display can blank briefly and Windows updates the reported state
        ; asynchronously. Reuse the display reflow timer to refresh the row from
        ; the authoritative state once that transition has settled.
        QueueQuickMenuDisplayReflow()
    } else {
        SharedNotify("Windows could not turn HDR " (enabled ? "on" : "off"), "Warning")
    }
}

; Reads the cap from the profile applicable to the executable that owned the
; foreground before the Quick Menu opened. RTSS's LoadProfile contract falls
; back to the global profile when that application-specific profile is absent.
; An empty executable explicitly selects the global profile.
GetRtssFrameLimit(profileExe := "") {
    global EnableRTSSIntegration, RtssUseDllIntegration
    if (!EnableRTSSIntegration || !RtssUseDllIntegration
        || !ProcessExist("RTSS.exe"))
        return 0
    api := GetRtssHooksApi()
    if (!IsObject(api) || !api["loadProfile"] || !api["getProfileProperty"])
        return 0
    profileName := Trim(profileExe)
    if (profileName != "") {
        fileName := ""
        SplitPath(profileName, &fileName)
        if (fileName != "")
            profileName := fileName
    }
    value := Buffer(4, 0)
    try {
        DllCall(api["loadProfile"], "AStr", profileName)
        ok := DllCall(api["getProfileProperty"],
            "AStr", "FramerateLimit", "Ptr", value, "UInt", value.Size, "Int")
        if !ok
            return 0
        return Map(
            "fps", NumGet(value, 0, "UInt"),
            "profile", profileName != "" ? profileName : "Global"
        )
    } catch as err {
        LogLine("RTSS state: FramerateLimit query failed: " err.Message,
            "Warning")
        return 0
    }
}

ResolveRtssExecutablePath() {
    global RtssPath
    path := NormalizeMediaPath(RtssPath)
    attributes := path != "" ? FileExist(path) : ""
    ; Fall back to the stock install location before giving up. Without this a
    ; user with an ordinary RTSS install and no [RTSS] Path set gets "RTSS was
    ; not found at the configured path" on every row, even though RTSS is
    ; sitting exactly where its installer put it. The discovered path is adopted
    ; so the rest of the session, and the DLL lookup beside RTSS.exe, use it.
    ;
    ; The companion had this fallback and the shell did not. Unifying the two
    ; gave the shell a fix rather than costing the companion one -- and gave the
    ; companion %VAR% expansion in [RTSS] Path, which its own normaliser lacked.
    if (attributes = "" || InStr(attributes, "D")) {
        programFilesX86 := ""
        try programFilesX86 := EnvGet("ProgramFiles(x86)")
        defaultPath := programFilesX86 "\RivaTuner Statistics Server\RTSS.exe"
        if (programFilesX86 != "" && FileExist(defaultPath)) {
            path := defaultPath
            RtssPath := defaultPath
            attributes := FileExist(defaultPath)
            LogLine("RTSS: adopted the default install path " defaultPath ".")
        }
    }
    return (attributes != "" && !InStr(attributes, "D")) ? path : ""
}

; Left/Right on the Custom FPS row.
;
; Two things make naive stepping unpleasant, and they are separate problems.
;
; 1. WRITING ON EVERY PRESS. SetRtssGlobalFrameLimit is a LoadProfile plus a
;    SetProfileProperty plus a SaveProfile -- a disk write -- plus UpdateProfiles.
;    Doing that per press means the limiter is genuinely reconfigured a dozen
;    times while the user scrolls, and the frame rate chases the number. So the
;    value is held pending, the row shows it immediately, and RTSS is written
;    once the user stops.
;
; 2. ESCALATING OFF-GRID. Quick Menu navigation is edge-triggered with no
;    auto-repeat, so a fixed step of 1 needs sixty presses to cross 60->120 and
;    the step has to grow. But growing it from an arbitrary value lands on
;    arbitrary values: 63 stepping by 5 gives 68, 73, 78, and 60 or 90 become
;    unreachable without slowing down and creeping. Coarse steps therefore snap
;    to their own grid -- 63 by 5 goes to 65, then 70 -- so fast stepping lands
;    on round numbers and fine stepping still moves by exactly 1.
AdjustRtssCustomFrameCap(direction) {
    global RtssPendingFrameCap, RtssCustomFrameCap
    static COMMIT_DELAY_MS := 400

    blockedReason := RtssFrameCapBlockedReason()
    if (blockedReason != "") {
        SharedNotify(blockedReason, "Warning")
        return
    }
    ; Adjust from what the row is SHOWING, not from the persisted setting.
    ; The value column reads the live cap and falls back to the pending value;
    ; starting the arithmetic at RtssCustomFrameCap instead meant that whenever
    ; the two had drifted apart the first press jumped to a number unrelated to
    ; the one on screen. RtssCustomFrameCap remains the fallback, for the case
    ; where RTSS reports nothing to start from.
    current := RtssPendingFrameCap
    if (current <= 0) {
        liveState := GetRtssFrameCapState()
        current := (IsObject(liveState) && liveState["fps"] > 0)
            ? liveState["fps"]
            : RtssCustomFrameCap
    }
    RtssPendingFrameCap := ClampInt(current + direction, 10, 1000)
    SetTimer(CommitRtssPendingFrameCap, -COMMIT_DELAY_MS)
}

; These are RTSS-wide switches. Overlay means global OSD visibility; limiter
; means the global disable override is clear. It does not prove that a game's
; profile has OSD support or a non-zero frame cap configured.
GetRtssGlobalState() {
    global EnableRTSSIntegration, RtssUseDllIntegration
    if (!EnableRTSSIntegration || !RtssUseDllIntegration
        || !ProcessExist("RTSS.exe"))
        return 0
    api := GetRtssHooksApi()
    if !IsObject(api)
        return 0
    flags := 0
    try flags := DllCall(api["get"], "UInt")
    catch as err {
        LogLine("RTSS state: GetFlags failed: " err.Message, "Warning")
        return 0
    }
    return Map(
        "overlay", (flags & 0x1) != 0,       ; RTSSHOOKSFLAG_OSD_VISIBLE
        "limiter", (flags & 0x4) = 0,        ; RTSSHOOKSFLAG_LIMITER_DISABLED
        "flags", flags
    )
}

; ==============================================================================
; RTSS TOGGLES AND THE CONTROLLER MOUSE FAILSAFE
; ==============================================================================
; Byte-identical in both trees for as long as the parity advisory has been
; reporting them, which is exactly what that advisory is for. Each reads the
; live RTSS state first and falls back to the configured shortcut only when it
; is unavailable; the failsafe releases a synthetic mouse button that outlived
; the poll loop. None of that is a shell concern or a companion concern.
;
; ApplyRtssGlobalState and SendRtssShortcut stay per-tree: they end in a
; notification, and that surface genuinely differs.

ToggleRtssOverlay() {
    global RtssOverlayToggleShortcut
    state := GetRtssGlobalState()
    if IsObject(state) {
        ApplyRtssGlobalState("overlay", !state["overlay"])
        return
    }
    SendRtssShortcut(RtssOverlayToggleShortcut, "RTSS overlay toggled",
        "OverlayToggleShortcut")
}

ToggleRtssFrameLimiter() {
    global RtssCustomFrameCapShortcut
    state := GetRtssGlobalState()
    if IsObject(state) {
        ApplyRtssGlobalState("limiter", !state["limiter"])
        PersistRtssFrameCapStateNow()
        return
    }
    SendRtssShortcut(RtssCustomFrameCapShortcut, "RTSS frame limiter toggled",
        "CustomFrameCapShortcut")
}

; ==============================================================================
; PRODUCT IDENTITY, AND THE THREE FUNCTIONS THAT ONLY DIFFERED BY IT
; ==============================================================================
; Each tree must define ProductIdentity(), returning a Map of:
;
;   name       what to call this program in a message to the user
;   exe        this program's own executable name, lower case
;   dirToken   the placeholder its own directory is redacted to in diagnostics
;
; It exists because three functions below were duplicated for years while
; differing by ONE string each: an error message, a redaction token, and an
; executable name. That is not two products needing different behaviour, it is
; the same behaviour written twice with the product's name baked into the middle
; of it -- and each copy is a place a fix can land on one side and not the other.
;
; Deliberately one function returning a Map rather than three accessors. The
; seam this file is allowed to call back into is enumerated and checked, so it
; is worth keeping small; and a product that grows a fourth identity string
; should not need a fourth seam entry to carry it.

; Whether a running helper process is the verified installed helper, at High
; integrity, owned by the same interactive user and session as this program.
;
; SHARED_FUNCTIONS.txt used to record this as staying per-tree because
; "standalone compares against its own installed-helper path and XFE against a
; different one". Both trees read that path from the same global, so there was
; never a difference to keep -- only the closing message named its own product.
; The justification had outlived the code it described.
VerifyElevatedHelperProcess(pid, &failureReason) {
    global ElevatedHelperPath
    global ExpectedInteractiveUserSid, ExpectedInteractiveSessionId
    failureReason := ""
    if !pid || !ProcessExist(pid) {
        failureReason := "The helper process is not running."
        return false
    }
    processPath := ""
    try processPath := ProcessGetPath(pid)
    catch as err {
        failureReason := "The helper executable path could not be read: " err.Message
        return false
    }
    if (processPath = ""
        || StrLower(processPath) != StrLower(ElevatedHelperPath)) {
        failureReason := "The observed helper path did not match the verified installed helper."
        return false
    }
    if !GetProcessTokenSecurity(
        pid, &helperSid, &helperSession, &helperIntegrity, &tokenError) {
        failureReason := "The helper token could not be verified: " tokenError
        return false
    }
    if (helperIntegrity != "High") {
        failureReason := "The helper has " helperIntegrity
            . " integrity instead of High integrity."
        return false
    }
    if (ExpectedInteractiveUserSid = ""
        || StrLower(helperSid) != StrLower(ExpectedInteractiveUserSid)
        || helperSession != ExpectedInteractiveSessionId) {
        failureReason := "The helper user or interactive session does not match "
            . ProductIdentity()["name"] "."
        return false
    }
    return true
}

; Removes the paths that identify a machine before text reaches a log or a
; support bundle. The directory token names the product so two bundles from the
; same machine stay tellable apart.
SanitizeDiagnosticText(text) {
    userProfile := EnvGet("USERPROFILE")
    localAppData := EnvGet("LOCALAPPDATA")
    if (userProfile != "")
        text := StrReplace(text, userProfile, "%USERPROFILE%", false)
    if (localAppData != "")
        text := StrReplace(text, localAppData, "%LOCALAPPDATA%", false)
    text := StrReplace(text, A_ScriptDir, "%" ProductIdentity()["dirToken"] "%", false)
    return text
}

; Whether an executable is a sensible target for a per-game RTSS profile.
;
; Steam's own surfaces are excluded because a profile named steam.exe caps the
; client rather than a game; Explorer and this program itself are excluded
; because neither is a game at all.
IsUsableProfileExe(exeName) {
    exeName := StrLower(Trim(exeName))
    if (exeName = "" || IsSteamProcess(exeName))
        return false
    return exeName != ProductIdentity()["exe"] && exeName != "explorer.exe"
}

; ==============================================================================
; LOG ROTATION, QUICK MENU TEARDOWN, CONFIRMATION AND ROW CLICKS
; ==============================================================================
; Four functions that were duplicated while differing by nothing a user could
; observe: two local variable names, a line wrap in a global declaration, a
; notification surface, and what a mouse click on a row does.
;
; The first three are now literally one definition. The fourth keeps its real
; difference behind a seam -- QuickMenuMouseChoose -- because clicking a row
; SELECTS it in standalone and ACTIVATES it in XFE, and that is a deliberate
; product decision rather than drift. Everything above the choice, which is all
; the DPI-scaled hit-testing arithmetic, is identical and is what was worth
; sharing.

RotateLogIfNeeded(pendingBytes := 0) {
    global LogPath, LogRotateMaxKB, LogRotateBackups
    static estimatedSize := -1
    if (LogRotateBackups <= 0)
        return
    if !FileExist(LogPath) {
        estimatedSize := 0
        return
    }

    threshold := LogRotateMaxKB * 1024
    if (estimatedSize < 0) {
        ; First call of the session, or a measurement that previously failed.
        try estimatedSize := FileGetSize(LogPath)
        catch {
            estimatedSize := -1
            return
        }
    }
    estimatedSize += pendingBytes
    if (estimatedSize <= threshold)
        return

    ; The estimate says we are over. Confirm against the real size before doing
    ; anything destructive -- the file may have been truncated or replaced.
    try estimatedSize := FileGetSize(LogPath)
    catch
        return
    if (estimatedSize <= threshold)
        return
    estimatedSize := 0

    Loop LogRotateBackups {
        index := LogRotateBackups - A_Index + 1
        source := LogPath "." index
        destination := LogPath "." (index + 1)
        if (index = LogRotateBackups) {
            if FileExist(source)
                try FileDelete(source)
        } else {
            if FileExist(source)
                try FileMove(source, destination, 1)
        }
    }
    try FileMove(LogPath, LogPath ".1", 1)
}

QuickMenuDestroyWindow() {
    global QuickMenuGui, QuickMenuTitleCtrl, QuickMenuStatusCtrl
    global QuickMenuRowsCtrl, QuickMenuRowsBitmap, QuickMenuRedrawSuspended

    detachedBitmap := 0
    if (IsSet(QuickMenuRowsCtrl) && IsObject(QuickMenuRowsCtrl)) {
        try detachedBitmap := SendMessage(0x0172, 0, 0, QuickMenuRowsCtrl)
    }
    if IsSet(QuickMenuGui) {
        try QuickMenuGui.Destroy()
        QuickMenuGui := unset
    }
    if detachedBitmap
        try DllCall("DeleteObject", "Ptr", detachedBitmap)
    if (QuickMenuRowsBitmap && QuickMenuRowsBitmap != detachedBitmap)
        try DllCall("DeleteObject", "Ptr", QuickMenuRowsBitmap)
    QuickMenuRowsBitmap := 0
    QuickMenuTitleCtrl := 0
    QuickMenuRowsCtrl := 0
    QuickMenuStatusCtrl := 0
    QuickMenuRedrawSuspended := false
    ShutdownGdiPlus()
}

QuickMenuConfirm(id, description) {
    global QuickMenuConfirmAction, QuickMenuConfirmUntilTick
    if (QuickMenuConfirmAction = id && A_TickCount < QuickMenuConfirmUntilTick) {
        QuickMenuConfirmAction := ""
        return true
    }
    QuickMenuConfirmAction := id
    QuickMenuConfirmUntilTick := A_TickCount + 5000
    SharedNotify("Select again within 5 seconds to confirm " description, "Warning")
    ; Standalone's notification surface does not repaint the menu; XFE's does,
    ; so this is one redundant refresh there and a necessary one here. Both are
    ; batched behind WM_SETREDRAW.
    QuickMenuRefresh()
    return false
}

QuickMenuRowsClick(*) {
    global QuickMenuRowsCtrl, QuickMenuRows
    if (!IsSet(QuickMenuRowsCtrl) || !QuickMenuRowsCtrl || QuickMenuRows.Length = 0)
        return
    point := Buffer(8, 0)
    if !DllCall("GetCursorPos", "Ptr", point)
        return
    if !DllCall("ScreenToClient", "Ptr", QuickMenuRowsCtrl.Hwnd, "Ptr", point)
        return
    clientRect := Buffer(16, 0)
    if !DllCall("GetClientRect", "Ptr", QuickMenuRowsCtrl.Hwnd, "Ptr", clientRect)
        return
    height := NumGet(clientRect, 12, "Int")
    if (height < 1)
        return
    y := NumGet(point, 4, "Int")
    scale := NumGet(clientRect, 8, "Int") / QuickMenuWidth()
    glowPad := Round(QuickMenuGlowPadding() * scale)
    rowBandHeight := height - (2 * glowPad)
    y -= glowPad
    if (rowBandHeight < 1 || y < 0 || y >= rowBandHeight)
        return
    index := Floor((y / rowBandHeight) * QuickMenuRows.Length) + 1
    QuickMenuMouseChoose(ClampInt(index, 1, QuickMenuRows.Length))
}

; Toggles HDR from its live state, or reports that the state cannot be read.
;
; SHARED SINCE THE BRANCH THAT DIVERGED TURNED OUT TO BE UNREACHABLE.
;
; Standalone used to send the Win+Alt+B chord here when GetPrimaryHdrState
; returned nothing, and XFE reported Unavailable instead -- recorded for a long
; time as a deliberate product divergence. It was not doing anything. Both trees
; build a DIFFERENT row, id "hdrUnavailable", when the state cannot be read, and
; that row is display-only in both: standalone handles it in the value-text
; switch and in neither the adjust nor the activate switch, and XFE gives it
; action "none". So a user who cannot read HDR state never gets an actionable
; HDR row, and the blind toggle could only ever fire if the state became
; unreadable BETWEEN the menu being built and the button being pressed.
;
; The chord is gone rather than ported. XFE's validator forbids it anywhere in
; that tree, on the evidence that 0.1.9 drove this row with the chord alone and
; no live state; keeping the rule and deleting the unreachable path satisfies
; both that rule and the reason it exists.
ToggleQuickMenuHdrState() {
    current := GetPrimaryHdrState()
    if !IsObject(current) {
        SharedNotify("Windows HDR state is unavailable", "Warning")
        return
    }
    SetQuickMenuHdrState(!current["enabled"])
}

; Moves the Quick Menu selection, stepping over rows that only report state.
;
; Two per-tree seams, and they are the only things that ever differed:
;
;   QuickMenuNormalizeSelection   puts an out-of-range index back in range --
;                                 standalone clamps, XFE wraps. That is a
;                                 long-standing product difference in how the
;                                 menu feels, not drift.
;   QuickMenuRowIsInert           answers "does this row do anything?" from
;                                 whatever the tree's row model can answer it
;                                 with: standalone from a list of row ids
;                                 because its rows carry no action field, XFE
;                                 from action = "none".
;
; The part worth writing once is between them. Landing on an inert row gives a
; highlighted row that does nothing when pressed and says nothing about why --
; "HDR   Not Supported" reads the same whether or not it can be selected, so
; skipping it costs the user nothing and removes a dead end.
;
; The loop is bounded by the row count, and the selection is restored when every
; row is inert. That restore is the only reason a page of nothing but status
; rows terminates instead of spinning at a boundary.
;
; Proved by exhausting every layout of 1-7 rows in both directions against both
; seams: movement from a usable row never lands on an inert one, always
; terminates, and always stays in range.
QuickMenuMoveSelection(direction) {
    global QuickMenuRows, QuickMenuSelected
    if (QuickMenuRows.Length = 0)
        return
    start := QuickMenuSelected
    Loop QuickMenuRows.Length {
        QuickMenuSelected += direction
        QuickMenuNormalizeSelection()
        if !QuickMenuRowIsInert(QuickMenuSelected)
            break
    }
    if QuickMenuRowIsInert(QuickMenuSelected)
        QuickMenuSelected := start
    QuickMenuRefresh()
}

; ==============================================================================
; STOPPING THE ELEVATED HELPER, AND CANCELLING A SHORTCUT CAPTURE
; ==============================================================================
; STARTING the helper stays per-tree and SHARED_FUNCTIONS.txt records why:
; standalone passes --product=standalone and may use a protected on-demand task,
; XFE passes --product=xfe and only ever uses explicit UAC. STOPPING it is not
; like that. Closing a process by PID and waiting for it to go is the same
; operation either way, and the only thing that ever differed was what the log
; line calls the helper -- which is now the helperLabel field of ProductIdentity.
;
; The shortcut-capture cancel was kept apart by one Map key: standalone stored
; the InputHook under "ih" and XFE under "input". Nothing else.

StopElevatedHelper(reason) {
    global ElevatedHelperPid, ElevatedHelperAvailable, ElevatedHelperLastError
    if !ElevatedHelperPid {
        ElevatedHelperAvailable := false
        return true
    }
    stoppedPid := ElevatedHelperPid
    ; The helper watches its parent and leaves on its own, but nothing here is
    ; exiting, so it has to be closed explicitly.
    if ProcessExist(stoppedPid) {
        try ProcessClose(stoppedPid)
        deadline := A_TickCount + 2000
        while ProcessExist(stoppedPid) && A_TickCount < deadline
            Sleep(50)
    }
    stopped := !ProcessExist(stoppedPid)
    ElevatedHelperAvailable := false
    ElevatedHelperPid := 0
    ElevatedHelperLastError := stopped
        ? "Stopped: " reason
        : "PID " stoppedPid " could not be closed after: " reason
    LogLine(ProductIdentity()["helperLabel"] ": " ElevatedHelperLastError,
        stopped ? "Info" : "Warning")
    return stopped
}

RecordShortcutCancel(*) {
    global _ShortcutCap
    if !IsObject(_ShortcutCap)
    return
    _ShortcutCap["cancelled"] := true
    try _ShortcutCap["input"].Stop()
    _ShortcutCap["done"] := true
}

; ==============================================================================
; TYPED SETTINGS READERS
; ==============================================================================
; One default per setting, bounds as parameters. Shared because both programs
; now read their INI this way, and because the shape is the point: the composed
; form standalone used states the default TWICE --
;
;     ClampInt(ToInt(IniReadS("Timing","MouseHideDelay","1000"), 1000), 0, 60000)
;
; once as the absent-key default and once as the parse-failure fallback, with
; nothing forcing them to agree. Three pairs had already drifted apart:
; [Splash] Mute documented false and fell back true, PlayFullDuration the
; reverse, and SafetyMaxMs quadrupled its own ceiling. A validator assertion
; catches that today; this makes it unwriteable, which is the stronger fix.
;
; Both trees keep IniPath pointing at their own settings file, and standalone
; reassigns it in lockstep with SettingsPath at every site that moves the file --
; a pairing its validator now pins, because these readers depend on it.
;
; The elevated helper has its own near-copies of these. It cannot include this
; file, and it reads a path it is handed on the command line rather than a
; global, so that duplication is structural rather than drift.

; ------------------------------------------------------------------------------
; Typed settings readers
; ------------------------------------------------------------------------------
; One default per setting, bounds as parameters. That shape is why this tree has
; never had the "default stated twice and the two disagree" class of bug that
; standalone needed a validator assertion to catch.
;
; What it DID have, until this pass, was no comment handling at all. IniRead
; returns everything after the "=", so `EnableAutoMouseMode=true  ; note` was
; read as the string "true  ; note" -- which is not "true", so the setting came
; back false. With 45 settings here defaulting to true, documenting this tree's
; INI would have silently switched them off one by one. That is why XFE's sample
; documented 3 settings out of 104 while standalone's documents 122 of 174: not
; a writing job that was skipped, a reader that could not survive it.
;
; Every reader now goes through CleanIniValue in SteamShell-Common.ahk, which is
; the function standalone has always used. A present-but-empty value stays empty
; rather than taking the default -- optional shortcuts and paths depend on the
; difference between "unset" and "deliberately blank".
ReadText(section, key, fallback := "") {
    global IniPath
    value := fallback
    try value := CleanIniValue(IniRead(IniPath, section, key, fallback), "", false)
    return Trim(value)
}

ReadNumber(section, key, fallback, minimum, maximum) {
    global IniPath
    value := fallback
    try value := CleanIniValue(IniRead(IniPath, section, key, fallback), fallback) + 0
    catch
        value := fallback
    return ClampFloat(value, minimum, maximum)
}

; ==============================================================================
; Transient status
; ==============================================================================
; The momentary surface in BOTH products is the Quick Menu status line. The shell
; called this ShowNotification and the companion SetStatus, which read as two
; designs; they were the same nineteen lines against the same five globals. The
; shell's name is a leftover from a bottom-corner toast it removed for being
; distracting over the Quick Menu -- the log is the permanent record, this is the
; momentary one.
;
; The seam used to point the other way: SharedNotify was defined in each tree and
; delegated outward, so the implementation stayed duplicated and free to drift.
; It did -- the companion lost the empty-message guard and logged before setting
; the globals. Each tree now keeps a one-line alias so its own call sites are
; unchanged, and there is no second copy to diverge.
SharedNotify(message, kind := "Info") {
    global LastStatusText, LastStatusLevel, LastStatusTick, StatusVisibleMs
    global QuickMenuVisible
    if (Trim(message) = "")
        return
    LastStatusText := message
    LastStatusLevel := kind
    LastStatusTick := A_TickCount
    try LogLine(message, kind)
    if QuickMenuVisible {
        try QuickMenuRefresh()
        ; Repaint once the message expires so the hint returns on its own rather
        ; than whenever the menu next happens to redraw.
        SetTimer(QuickMenuRefresh, -(StatusVisibleMs + 100))
    }
}

; ==============================================================================
; RTSS shortcut fallback and XInput reads
; ==============================================================================

; The keystroke path, used when the DLL integration is unavailable. Both trees
; held this; the entire difference was the notify call and its wording, which
; SharedNotify now resolves. The shell's messages are kept because they name the
; INI keys to change rather than pointing at a Settings window the companion has
; and the shell does not.
SendRtssShortcut(shortcut, description, settingName) {
    global EnableRTSSIntegration
    if !EnableRTSSIntegration {
        SharedNotify(
            "Set [RTSS] EnableIntegration=true to use RTSS controls", "Warning")
        return false
    }
    if (shortcut = "") {
        SharedNotify("Configure RTSS " settingName " first", "Warning")
        return false
    }
    if !EnsureRtssRunning() {
        SharedNotify(
            "RTSS was not found. Configure [RTSS] Path first.", "Warning")
        return false
    }
    ; SendChordSafe, not Send: it is what releases any modifier the user is
    ; still holding before the chord goes out. Both trees define their own, so
    ; this is a seam like LogLine.
    SendChordSafe(shortcut)
    SharedNotify(description, "Success")
    return true
}

; The shell's version is kept: on an unexpected failure of the standard export it
; retries through the Ex ordinal before giving up, where the companion reset the
; DLL handle and returned. Everything else that separated them was indentation
; and local names -- bufState/ex/bEx against state/extended/exButtons -- which is
; why the raw similarity read 0.70 for what is one algorithm.
XInputGetState(index, &bufState) {
    global XInputDll
    if (XInputDll = "" && !InitXInput())
        return 1167 ; ERROR_DEVICE_NOT_CONNECTED-ish

    ; XINPUT_STATE is 16 bytes: DWORD packet + XINPUT_GAMEPAD (12 bytes)
    if !IsObject(bufState)
        bufState := Buffer(16, 0)

    ; Prefer the standard XInputGetState for maximum compatibility (View/Back,
    ; sticks, triggers). Best-effort: also OR in the Guide bit via
    ; XInputGetStateEx (ordinal 100) when available.
    try {
        rc := DllCall(XInputDll "\XInputGetState", "UInt", index, "Ptr", bufState, "UInt")
        if (rc = 0) {
            try {
                ex := Buffer(16, 0)
                if (DllCall(XInputDll "\100", "UInt", index, "Ptr", ex, "UInt") = 0) {
                    bEx := NumGet(ex, 4, "UShort")
                    if (bEx & 0x0400) {
                        b := NumGet(bufState, 4, "UShort")
                        NumPut("UShort", b | 0x0400, bufState, 4)
                    }
                }
            } catch {
                ; ignore Ex failures
            }
        }
        return rc
    } catch {
        ; Fall back: if the standard export fails for any reason, try Ex directly.
        try {
            return DllCall(XInputDll "\100", "UInt", index, "Ptr", bufState, "UInt")
        } catch {
            ; If the DLL is weird, reset and retry next time.
            XInputDll := ""
            return 1
        }
    }
}

; ==============================================================================
; RTSS per-game profile target
; ==============================================================================

; Derived live from the window handle, never from a stored name.
;
; The companion kept a QuickMenuPreviousExe string captured when the menu opened
; and read that instead. It already tracked the handle on the very next line, so
; this costs it no new state and fixes a real case: a game that exits while the
; Quick Menu is open left the snapshot holding its name, and a per-game frame cap
; would then be written to a profile for a process that is gone. Reading through
; the handle returns "" once the window dies, which is the honest answer.
GetQuickMenuPreviousExe() {
    global QuickMenuPreviousHwnd
    if (QuickMenuPreviousHwnd && DllCall("IsWindow", "Ptr", QuickMenuPreviousHwnd, "Int"))
        try return WinGetProcessName("ahk_id " QuickMenuPreviousHwnd)
    return ""
}

; The window in front of the Quick Menu first, then whatever the tree's own
; detection thinks is running. ProductBestGameExe is the seam: the shell answers
; from its window engine's scored candidate, the companion from XfeBestGameWindow
; with its foreground observation as a fallback.
RtssProfileTargetExe() {
    exeName := Trim(GetQuickMenuPreviousExe())
    if IsUsableProfileExe(exeName)
        return exeName
    exeName := Trim(ProductBestGameExe())
    if IsUsableProfileExe(exeName)
        return exeName
    return ""
}

; Title Case in the companion and sentence case in the shell was the only thing
; separating these. The shell's casing is kept; the companion's Quick Menu shows
; the same rows.
RtssSaveProfileValueText() {
    if !RtssFrameCapWritable()
        return "Unavailable"
    exeName := RtssProfileTargetExe()
    if (exeName != "")
        return exeName
    previous := Trim(GetQuickMenuPreviousExe())
    if (previous != "" && IsSteamProcess(previous))
        return "Steam in front, no game detected"
    return "No game in foreground"
}

; ==============================================================================
; Audio output and frame-cap cycling
; ==============================================================================

; Moved verbatim from the shell. The companion's copy differed only in the
; notify name, one equivalent index initialisation, and a trailing
; QuickMenuRefresh the shell keeps -- SharedNotify already repaints, so it is
; redundant rather than wrong, and removing it is a behaviour change this move
; deliberately does not make.
CycleDefaultAudioOutput(direction) {
    global QuickMenuAudioDevices
    if (QuickMenuAudioDevices.Length = 0)
        QuickMenuAudioDevices := GetActiveAudioOutputDevices()
    if (QuickMenuAudioDevices.Length = 0) {
        SharedNotify("No active Windows audio outputs were found", "Warning")
        return
    }

    currentName := ""
    try currentName := SoundGetName()
    currentIndex := 0
    for index, device in QuickMenuAudioDevices {
        if (device["name"] = currentName) {
            currentIndex := index
            break
        }
    }
    if (currentIndex = 0)
        currentIndex := 1
    nextIndex := currentIndex + direction
    if (nextIndex < 1)
        nextIndex := QuickMenuAudioDevices.Length
    if (nextIndex > QuickMenuAudioDevices.Length)
        nextIndex := 1

    target := QuickMenuAudioDevices[nextIndex]
    if SetDefaultAudioEndpointId(target["id"]) {
        SharedNotify("Audio output: " target["name"], "Success")
    } else {
        SharedNotify("Windows could not switch the audio output", "Warning")
    }
    QuickMenuRefresh()
}

; The shell's version, which RETURNS a value. Its callers branch on it
; ("if CycleRtssFrameCap(direction)"); the companion's bare "return" made its
; own callers unable to. Those callers ignore the result today and keep
; working unchanged, but the information is now there for them.
; Left/Right on the Frame Limit row. Returns true when the row set changed, so
; the caller knows a full rebuild is needed rather than a repaint: the Custom
; row is composed in QuickMenuGetDefinitions, which QuickMenuRefresh never runs.
;
; "wrap" is for the A button, which has no reverse. Left/Right clamps at both
; ends because the list is an ascending scale and stopping at each end reads
; correctly there; A cannot stop, because a user who only presses A would reach
; the last entry and never get back. See the two guards below for what that
; cost before this parameter existed.
CycleRtssFrameCap(direction, wrap := false) {
    global RtssFrameCapPresets, RtssPresetFrameCap, RtssCustomFrameCap
    global RtssFrameCapCustomMode
    state := GetRtssFrameCapState()
    if !IsObject(state) {
        SharedNotify("RTSS live state is unavailable", "Warning")
        return false
    }
    blockedReason := RtssFrameCapBlockedReason()
    if (blockedReason != "") {
        SharedNotify(blockedReason, "Warning")
        return false
    }

    ; Coming off "Off" restores the number the profile still holds instead of
    ; jumping to the first preset. This is the payoff for never writing 0: the
    ; user's 72 survives an off/on round trip untouched. Only applies when the
    ; flag is what turned it off; a flag that is on with no target has nothing to
    ; restore and falls through to the list below.
    ;
    ; Never on the wrapping path. The retained number is usually the configured
    ; Preset or a Custom value, both of which sit at the far end of the list, so
    ; jumping to it skips every standard cap in between -- survivable with
    ; Left/Right, which can walk back down, and fatal with A, which cannot.
    if (!wrap && direction > 0 && state["mode"] = "off"
        && !state["limiter"] && state["fps"] > 0) {
        if !ApplyRtssGlobalState("limiter", true)
            return false
        RtssFrameCapCustomMode := false
        PersistRtssFrameCapSelection(
            RtssFrameCapModeForFps(state["fps"]), state["fps"])
        return !IsRtssFrameCapPreset(state["fps"])
            && state["fps"] != RtssPresetFrameCap
    }

    ; Anything still being dialled in on the Custom row must not land after this.
    CancelPendingRtssFrameCap()

    ; One ordered list: Off, standard caps, the user-configured Preset, then
    ; the separately retained Custom value.
    entries := ["off"]
    for _, preset in RtssFrameCapPresets
        entries.Push(preset)
    if (RtssPresetFrameCap > 0 && !IsRtssFrameCapPreset(RtssPresetFrameCap))
        entries.Push("configured")
    entries.Push("custom")

    index := 1
    switch state["mode"] {
        case "custom":
            index := entries.Length
        case "configured":
            for entryIndex, entry in entries {
                if (entry = "configured") {
                    index := entryIndex
                    break
                }
            }
        case "preset":
            for entryIndex, entry in entries {
                if (entry = state["fps"]) {
                    index := entryIndex
                    break
                }
            }
    }
    index += direction
    if wrap {
        if (index < 1)
            index := entries.Length
        else if (index > entries.Length)
            index := 1
    } else {
        index := ClampInt(index, 1, entries.Length)
    }
    target := entries[index]
    ; One line per press, naming where the cycle started and what it resolved
    ; to. Without it, "the row will not leave PRESET" cannot be told apart from
    ; "the row never picked 60 in the first place" -- and those have different
    ; causes in different functions.
    LogLine("Frame Limit cycle: " state["mode"] " at " state["fps"] " FPS"
        . " (limiter " (state["limiter"] ? "on" : "off") ")"
        . " -> entry " index " of " entries.Length " = " target
        . (wrap ? " [wrap]" : " [clamp]") ".")

    wasCustom := (state["mode"] = "custom")
    if (target = "off") {
        ; Value untouched on purpose -- see the header comment.
        ;
        ; Only written when the flag actually has to change. Left clamps to this
        ; entry at the end of the list, so without the guard every further press
        ; re-issued the SetFlags call and re-showed its notification.
        if (state["limiter"]
            && !ApplyRtssGlobalState("limiter", false))
            return false
        RtssFrameCapCustomMode := false
        ; The number is kept alongside "off" so re-enabling lands where the user
        ; left it, matching the profile value this branch deliberately preserves.
        PersistRtssFrameCapSelection("off", state["fps"])
        return wasCustom
    }
    if (target = "custom") {
        ; Restore the last Custom value instead of inheriting whichever preset
        ; happened to be selected immediately before it.
        customFps := ClampInt(RtssCustomFrameCap, 10, 1000)
        if !SetRtssGlobalFrameLimit(customFps)
            return false
        if (!state["limiter"]
            && !ApplyRtssGlobalState("limiter", true))
            return false
        RtssFrameCapCustomMode := true
        PersistRtssFrameCapSelection("custom", customFps)
        return !wasCustom
    }
    if (target = "configured") {
        if !SetRtssGlobalFrameLimit(RtssPresetFrameCap)
            return false
        if (!state["limiter"]
            && !ApplyRtssGlobalState("limiter", true))
            return false
        RtssFrameCapCustomMode := false
        PersistRtssFrameCapSelection("configured", RtssPresetFrameCap)
        return wasCustom
    }
    if !SetRtssGlobalFrameLimit(target)
        return false
    if (!state["limiter"]
        && !ApplyRtssGlobalState("limiter", true))
        return false
    RtssFrameCapCustomMode := false
    PersistRtssFrameCapSelection("preset", target)
    return wasCustom
}

; ==============================================================================
; Game-score diagnostics
; ==============================================================================
; Why a window was chosen as the game, written as a table.
;
; The companion gained the scorer but not this, so when it picked the wrong
; window for a per-game RTSS cap -- a cap keyed on an executable NAME, where a
; wrong pick is written to another program's profile -- there was no way to see
; what it had considered. The shell could answer that and the companion could
; not, for the same decision made by the same code.
LogRow(ts, evt, scoreStr, exe, pidStr, cpuStr, audChar, fsChar, rectStr, hwndStr, reason, title := "") {
    global GameLogIncludeTitles
    line :=
    TruncPad(ts, 19, true) " "
    . TruncPad(evt, 7, true) " "
    . TruncPad(scoreStr, 3, false) " "
    . TruncPad(exe, 24, true) " "
    . TruncPad(pidStr, 6, false) " "
    . TruncPad(cpuStr, 6, false) " "
    . TruncPad(audChar, 1, true) " "
    . TruncPad(fsChar, 1, true) " "
    . TruncPad(rectStr, 19, true) " "
    . TruncPad(hwndStr, 10, true) " "
    . TruncPad(reason, 22, true)

    if (GameLogIncludeTitles) {
    if (title = "")
    title := "-"
    line .= " " . TruncPad(title, 60, true)
    }
    return line
}

; Writes a line exactly as given, with no prefix.
;
; Only for the game-score diagnostic table. That table is columnar and formats
; its own leading timestamp, so a second prefix would misalign every row of it.
LogRawLine(line) {
    global LogPath
    ; StrLen undercounts multi-byte UTF-8, which is fine: the estimate only has to
    ; be close enough to decide when to measure for real.
    RotateLogIfNeeded(StrLen(line) + 2)
    try FileAppend(line "`r`n", LogPath, "UTF-8")
}

ShouldLogRateLimited() {
    global _LastGameLogTick, GameLogIntervalMs
    if (A_TickCount - _LastGameLogTick >= GameLogIntervalMs) {
    _LastGameLogTick := A_TickCount
    return true
    }
    return false
}

; One table per evaluation: a header carrying the activation threshold and any
; skip reason, then the top N candidates, then the rejected near-misses when the
; mode asks for them. Callers pass their own already-scored list, so this makes
; no judgement about which window won -- it only reports.
LogGameCandidateTable(candidates, rejects, headerNote) {
    global EnableGameScoreLogging, GameLogMode, GameLogTopN
    if (!EnableGameScoreLogging)
        return
    if (GameLogMode != "TOPN" && GameLogMode != "DIAGNOSTIC")
        return
    if !ShouldLogRateLimited()
        return
    if (candidates.Length = 0) {
        LogRawLine(LogRow(
            NowStamp(), "TOPN", "---", "-", "------", FmtCpu(0, false),
            "-", "-", "-", "----------", "NO_CANDIDATES", "-"))
    } else {
        LogRawLine(LogRow(
            NowStamp(), "TOPN", "---", "-", "------", FmtCpu(0, false),
            "-", "-", "-", "----------", headerNote, "-"))
        maxN := Min(candidates.Length, GameLogTopN)
        Loop maxN {
            candidate := candidates[A_Index]
            LogRawLine(LogRow(
                NowStamp(), "CAND#" A_Index,
                FmtScore(candidate["score"], true),
                candidate["proc"], FmtPid(candidate["pid"]),
                FmtCpu(candidate["cpu"], candidate["cpuKnown"]),
                candidate["audio"] ? "Y" : "N",
                candidate["nearFS"] ? "Y" : "N",
                FmtRect(candidate["x"], candidate["y"], candidate["w"], candidate["h"]),
                FmtHwnd(candidate["hwnd"]), "-", candidate["title"]))
        }
    }
    if (GameLogMode = "DIAGNOSTIC") {
        for _, line in rejects
            LogRawLine(line)
    }
}

; ==============================================================================
; Health check
; ==============================================================================
; The harness, not the checks. Which conditions matter is entirely
; product-specific -- the shell tests Winlogon registration and standard-user
; launch capability, the companion tests controller backends and AnyFSE -- but
; presenting them is not.
;
; The companion built its whole report inline as flat "PASS - text" strings and
; showed them in a read-only edit box. That left it unable to copy the report,
; unable to refresh without reopening, and rebuilding the same text a second time
; inside its export bundle. Sharing the harness gives it a sortable list, a Copy
; button and a Refresh button, and leaves one definition of the report format.
;
; ProductHealthResults() is the seam: an array of Map("status", "name", "detail")
; where status is PASS, WARN, FAIL or INFO.


; One row. Kept as the shell wrote it -- push onto a passed array rather than
; return a Map -- because 40-odd call sites already read that way and changing
; the shape to suit a second caller would be the tail wagging the dog.
HealthResult(results, status, checkName, detail) {
    results.Push(Map(
        "status", StrUpper(status),
        "name", checkName,
        "detail", detail))
}

FormatHealthReport(results := 0) {
    if !IsObject(results)
        results := ProductHealthResults()
    report := ProductIdentity()["name"] " " ProductVersionText() " Health Check`r`n"
        . "Generated: " NowStamp() "`r`n`r`n"
    for _, item in results
        report .= "[" item["status"] "] " item["name"] "`r`n  " item["detail"] "`r`n"
    return report
}

CopyHealthReport(*) {
    global HealthCheckResults
    A_Clipboard := FormatHealthReport(HealthCheckResults)
}

RefreshHealthCheck(*) {
    global HealthCheckGui, HealthCheckResults
    HealthCheckResults := ProductHealthResults()
    if !IsSet(HealthCheckGui)
        return
    try {
        listView := HealthCheckGui["HealthResults"]
        listView.Delete()
        counts := Map("PASS", 0, "WARN", 0, "FAIL", 0, "INFO", 0)
        for _, item in HealthCheckResults {
            listView.Add("", item["status"], item["name"], item["detail"])
            if counts.Has(item["status"])
                counts[item["status"]] += 1
        }
        listView.ModifyCol(1, 75)
        listView.ModifyCol(2, 185)
        listView.ModifyCol(3, 555)
        HealthCheckGui["HealthSummary"].Text :=
            counts["PASS"] " passed   •   " counts["WARN"] " warnings   •   "
            . counts["FAIL"] " failed   •   " counts["INFO"] " informational"
    }
}

ShowHealthCheck(*) {
    global HealthCheckGui
    if !IsSet(HealthCheckGui) {
        HealthCheckGui := Gui("+AlwaysOnTop +ToolWindow -Resize",
            ProductIdentity()["name"] " Health Check")
        HealthCheckGui.Opt("+OwnDialogs")
        HealthCheckGui.SetFont("s10", "Segoe UI")
        title := HealthCheckGui.AddText("xm ym w850 h30",
            ProductIdentity()["name"] " Health Check")
        title.SetFont("s17 Bold", "Segoe UI")
        HealthCheckGui.AddText(
            "xm y+2 w850 h36 +Wrap",
            "Read-only checks. Nothing here changes a setting, a file or a registration.")
        HealthCheckGui.AddListView(
            "xm y+8 w850 r13 -Multi vHealthResults", ["Status", "Check", "Details"])
        HealthCheckGui.AddText("xm y+8 w850 h24 vHealthSummary", "")
        refreshButton := HealthCheckGui.AddButton("xm y+8 w145 h32", "Refresh")
        refreshButton.OnEvent("Click", RefreshHealthCheck)
        copyButton := HealthCheckGui.AddButton("x+8 yp w145 h32", "Copy Report")
        copyButton.OnEvent("Click", CopyHealthReport)
        exportButton := HealthCheckGui.AddButton("x+8 yp w190 h32", "Export Diagnostic ZIP")
        exportButton.OnEvent("Click", ExportDiagnosticBundle)
        closeButton := HealthCheckGui.AddButton("x+8 yp w120 h32", "Close")
        closeButton.OnEvent("Click", (*) => HealthCheckGui.Hide())
        HealthCheckGui.OnEvent("Close", (*) => HealthCheckGui.Hide())
        HealthCheckGui.OnEvent("Escape", (*) => HealthCheckGui.Hide())
    }
    HealthCheckGui.Show()
    ProductCenterGui(HealthCheckGui)
    RefreshHealthCheck()
}

; ==============================================================================
; Installation record
; ==============================================================================
; What this installation believes it is, kept in the settings file beside the
; registry record.
;
; The registry is the better source while it exists, but it is exactly what does
; not survive a move: copy an installation to another PC and HKCU is empty while
; the settings file still describes the old machine. The file travels with the
; installation, so it is the only record that can say "this came from somewhere
; else".
;
; SetupState, SetupVersion and Product were already being read. InstallationMode,
; InstallDirectory and DataDirectory were written, documented in the sample INI
; as though they meant something, and read by nothing -- a record that validated
; nothing. Reading them is what makes the record real; acting on the result is a
; separate decision and deliberately not taken here.

SteamShellSetupRecord() {
    return Map(
        "state", ReadText("Setup", "SetupState", ""),
        "version", ReadText("Setup", "SetupVersion", ""),
        "product", ReadText("Setup", "Product", ""),
        "mode", ReadText("Setup", "InstallationMode", ""),
        "installDir", ReadText("Setup", "InstallDirectory", ""),
        "dataDir", ReadText("Setup", "DataDirectory", ""))
}

; Differences between what the record claims and what is actually running, as
; human-readable lines. Empty means consistent, or means there is no record yet
; -- a fresh installation has nothing to disagree with and must not be reported
; as drifted.
;
; Paths are compared case-insensitively with trailing separators removed, since
; neither is meaningful on Windows and both vary by how the value was produced.
SteamShellSetupRecordDrift(record, liveInstallDir, liveDataDir, liveMode) {
    drift := []
    if (Trim(record["state"]) = "")
        return drift
    same(a, b) {
        return StrLower(RTrim(Trim(a), "\/")) = StrLower(RTrim(Trim(b), "\/"))
    }
    if (record["installDir"] != "" && !same(record["installDir"], liveInstallDir))
        drift.Push("Recorded install directory " record["installDir"]
            . " but running from " liveInstallDir)
    if (record["dataDir"] != "" && !same(record["dataDir"], liveDataDir))
        drift.Push("Recorded data directory " record["dataDir"]
            . " but using " liveDataDir)
    if (record["mode"] != "" && liveMode != "" && !same(record["mode"], liveMode))
        drift.Push("Recorded installation mode " record["mode"]
            . " but running as " liveMode)
    return drift
}

; Advisory only, and that is the whole design.
;
; This is a Windows shell replacement. A record that disagrees with reality is
; worth knowing about and is never worth refusing to start over -- a stale path
; in a settings file must not be able to leave a machine with no shell. It logs,
; and the Health Check reads the same record for its own row.
LogSteamShellSetupRecordDrift(liveInstallDir, liveDataDir, liveMode) {
    drift := SteamShellSetupRecordDrift(
        SteamShellSetupRecord(), liveInstallDir, liveDataDir, liveMode)
    if !drift.Length
        return false
    for _, line in drift
        LogLine("Installation record: " line ".", "Warning")
    LogLine("Installation record: this usually means the installation was moved "
        . "or copied. Nothing was changed; run Setup Assistant to re-record it.",
        "Warning")
    return true
}

; A single classification of what this installation looks like, so the log line,
; the Health Check row and anything added later all say the same thing.
;
; Deliberately built from built-ins only: ToInt, ToBool and
; NormalizeSteamShellProduct are standalone-only, and a shared function that
; quietly required them would fail to load in the companion.
;
; "moved" outranks "older" on purpose. A record whose paths do not match is the
; more urgent thing to say, and a copy carried between machines is usually stale
; in both respects at once -- reporting the version first would bury it.
SteamShellInstallationVerdict(liveInstallDir, liveDataDir, liveMode, expectedSetupVersion := 1) {
    record := SteamShellSetupRecord()
    if (Trim(record["state"]) = "")
        return Map("verdict", "new",
            "detail", "No installation is recorded in the settings file yet.")
    drift := SteamShellSetupRecordDrift(
        record, liveInstallDir, liveDataDir, liveMode)
    if drift.Length {
        detail := ""
        for _, line in drift
            detail .= (detail = "" ? "" : "  ") line "."
        return Map("verdict", "moved", "detail", detail
            . "  The installation was probably moved or copied.")
    }
    version := 0
    try version := Integer(Trim(record["version"]))
    if (version < expectedSetupVersion)
        return Map("verdict", "older",
            "detail", "Recorded by Setup workflow version "
                . (version ? version : "none") "; this build expects "
                . expectedSetupVersion ".")
    return Map("verdict", "consistent",
        "detail", "Recorded as "
            . (record["product"] != "" ? record["product"] : "an installation")
            . (record["mode"] != "" ? ", " record["mode"] : "")
            . (record["installDir"] != "" ? ", in " record["installDir"] : "") ".")
}

; The Health Check row, so both products report this the same way and neither
; has to know how the verdict is reached.
AddInstallationRecordHealthRow(results, liveInstallDir, liveDataDir, liveMode, expectedSetupVersion := 1) {
    verdict := SteamShellInstallationVerdict(
        liveInstallDir, liveDataDir, liveMode, expectedSetupVersion)
    ; Only a mismatch is a warning. A new or older record is a fact about the
    ; installation, not a fault in it.
    status := verdict["verdict"] = "consistent"
        ? "PASS"
        : (verdict["verdict"] = "moved" ? "WARN" : "INFO")
    HealthResult(results, status, "Installation record", verdict["detail"])
}

; The verdict, evaluated once per session.
;
; The record is written by Setup and by first-run self-recording, neither of
; which happens while the program is doing anything else, so the answer cannot
; change under a running session. The tray menu is rebuilt whenever presentation
; mode changes, and reading the settings file on every rebuild would be a file
; read per rebuild for an answer that is already known.
;
; refresh exists for the one caller that legitimately invalidates it: Setup
; Assistant, which has just rewritten the record it is about to be judged by.
CachedInstallationVerdict(liveInstallDir, liveDataDir, liveMode, refresh := false) {
    static cached := ""
    if (refresh || !IsObject(cached))
        cached := SteamShellInstallationVerdict(liveInstallDir, liveDataDir, liveMode)
    return cached
}

; A short line for the tray and for Setup Assistant's status area, or "" when
; there is nothing to say.
;
; Only "moved" produces text. "new" and "older" are ordinary states -- a machine
; before Setup has run, and an installation predating the current Setup workflow
; -- and putting either in front of the user as an alert would make the one that
; matters indistinguishable from noise.
InstallationRecordAlert(liveInstallDir, liveDataDir, liveMode) {
    verdict := CachedInstallationVerdict(liveInstallDir, liveDataDir, liveMode)
    if (verdict["verdict"] != "moved")
        return ""
    return "This installation was moved or copied. Re-run Setup Assistant to "
        . "re-record where it lives."
}

; ==============================================================================
; Notification-area icon and menu
; ==============================================================================
; The menus differ; the machinery around them did not.
;
; Both products opened with the same two entries calling the same two handler
; names, ended with an exit entry, defaulted to the Quick Menu and composed a
; tooltip from a base plus suffixes. What separated them was strategy: the shell
; rebuilt the whole menu on every refresh, while the companion built it once and
; then mutated it with Rename and Enable.
;
; That was not a style difference. A menu that is never rebuilt cannot gain or
; lose an entry, which is why the companion could only show a moved installation
; in its tooltip while the shell offered a menu entry for it. Building from a
; declarative list gives both the rebuild, and with it conditional entries.
;
; ProductTrayItems() is the seam: an array where each element is either a Map
; describing an entry or anything else for a separator.

ApplyTrayIconImage() {
    iconPath := A_ScriptDir "\assets\" ProductIdentity()["icon"]
    if FileExist(iconPath)
        try TraySetIcon(iconPath)
}

BuildProductTrayMenu() {
    try A_TrayMenu.Delete()
    for _, item in ProductTrayItems() {
        if !IsObject(item) {
            A_TrayMenu.Add()
            continue
        }
        A_TrayMenu.Add(item["label"], item["handler"])
        if (item.Has("checked") && item["checked"])
            try A_TrayMenu.Check(item["label"])
        if (item.Has("disabled") && item["disabled"])
            try A_TrayMenu.Disable(item["label"])
    }
    ; Both products default to the Quick Menu, and a product that omitted the
    ; entry would otherwise throw here rather than simply having no default.
    try A_TrayMenu.Default := "Open Quick Menu"
    A_IconTip := ProductTrayBaseTip()
}

; Explorer rebuilds the notification area and broadcasts TaskbarCreated; an icon
; that does not re-add itself is gone until the program restarts.
;
; The shell handled this because it manages Explorer. The companion did not, and
; it needs to just as much: an Explorer crash or a Windows update took its icon
; away permanently, and with it the only route to Settings, Disable and Exit that
; does not need a controller.
RegisterTaskbarCreatedListener() {
    global TaskbarCreatedMessage
    try TaskbarCreatedMessage := DllCall(
        "User32\RegisterWindowMessageW", "WStr", "TaskbarCreated", "UInt")
    ; Braces are required here: a bare `try` cannot be an if-body that an `else`
    ; attaches to.
    if (TaskbarCreatedMessage) {
        try OnMessage(TaskbarCreatedMessage, TaskbarCreatedHandler)
    } else {
        try LogLine("TaskbarCreated could not be registered; the tray icon may not survive an Explorer restart.")
    }
}

TaskbarCreatedHandler(*) {
    ; Explorer is still building the tray when it sends this. Re-assert shortly
    ; after rather than inside the broadcast handler.
    SetTimer(ReassertTrayIcon, -750)
}

ReassertTrayIcon() {
    try {
        A_IconHidden := true
        A_IconHidden := false
    }
    ApplyTrayIconImage()
    BuildProductTrayMenu()
    try LogLine("Notification-area icon re-asserted after an Explorer taskbar rebuild.")
}

InitializeTrayMenu() {
    ApplyTrayIconImage()
    BuildProductTrayMenu()
    RegisterTaskbarCreatedListener()
}

; ==============================================================================
; RTSS DLL integration and global flags
; ==============================================================================
; Moved from the shell verbatim. The companion's copies were the same code: the
; DLL binding differed only in where its lines wrapped and the order of a global
; declaration, and the flag writer differed only in which notify alias it called.
; Raw similarity read 0.70 and 0.94 respectively, which is what wrapping and a
; renamed call will do to a text comparison of identical behaviour.
;
; The one deliberate change is that the "exports not found" line now names the
; DLL it looked in, which the companion's copy did and the shell's did not.

; RTSS publishes its global overlay/limiter flags and profile properties through
; RTSSHooks64.dll. This is optional: older or unusual installations continue to
; use the configured HotkeyHandler shortcuts.
GetRtssHooksApi() {
    global RtssPath, RtssUseDllIntegration
    global RtssHooksModule, RtssHooksDllPath, RtssHooksLastFailure
    global RtssGetFlagsProc, RtssSetFlagsProc
    global RtssLoadProfileProc, RtssGetProfilePropertyProc
    global RtssSetProfilePropertyProc, RtssSaveProfileProc, RtssUpdateProfilesProc
    if !RtssUseDllIntegration
        return 0
    rtssExe := ResolveRtssExecutablePath()
    installDir := ""
    if (rtssExe != "")
        SplitPath(rtssExe, , &installDir)
    dllPath := installDir != "" ? installDir "\RTSSHooks64.dll" : ""
    if (RtssHooksModule && RtssHooksDllPath = dllPath
        && RtssGetFlagsProc && RtssSetFlagsProc) {
        return Map(
            "get", RtssGetFlagsProc, "set", RtssSetFlagsProc,
            "loadProfile", RtssLoadProfileProc,
            "getProfileProperty", RtssGetProfilePropertyProc,
            "setProfileProperty", RtssSetProfilePropertyProc,
            "saveProfile", RtssSaveProfileProc,
            "updateProfiles", RtssUpdateProfilesProc)
    }
    if RtssHooksModule
        ShutdownRtssHooksApi()
    if (dllPath = "" || !FileExist(dllPath)) {
        if (RtssHooksLastFailure != dllPath) {
            RtssHooksLastFailure := dllPath
            LogLine("RTSS live state unavailable: RTSSHooks64.dll was not found; shortcut fallback remains available.")
        }
        return 0
    }
    module := 0
    try module := DllCall("Kernel32\LoadLibraryW", "WStr", dllPath, "Ptr")
    getProc := 0
    setProc := 0
    loadProfileProc := 0
    getProfilePropertyProc := 0
    setProfilePropertyProc := 0
    saveProfileProc := 0
    updateProfilesProc := 0
    if module {
        try getProc := DllCall(
            "Kernel32\GetProcAddress", "Ptr", module, "AStr", "GetFlags", "Ptr")
        try setProc := DllCall(
            "Kernel32\GetProcAddress", "Ptr", module, "AStr", "SetFlags", "Ptr")
        try loadProfileProc := DllCall(
            "Kernel32\GetProcAddress", "Ptr", module, "AStr", "LoadProfile", "Ptr")
        try getProfilePropertyProc := DllCall(
            "Kernel32\GetProcAddress", "Ptr", module,
            "AStr", "GetProfileProperty", "Ptr")
        ; Write path. Deliberately optional: an RTSS build without these still
        ; drives the overlay and limiter flags, and the frame-cap row degrades to
        ; read-only rather than taking the whole integration down with it.
        try setProfilePropertyProc := DllCall(
            "Kernel32\GetProcAddress", "Ptr", module,
            "AStr", "SetProfileProperty", "Ptr")
        try saveProfileProc := DllCall(
            "Kernel32\GetProcAddress", "Ptr", module, "AStr", "SaveProfile", "Ptr")
        try updateProfilesProc := DllCall(
            "Kernel32\GetProcAddress", "Ptr", module, "AStr", "UpdateProfiles", "Ptr")
    }
    if (!module || !getProc || !setProc) {
        if module
            try DllCall("Kernel32\FreeLibrary", "Ptr", module, "Int")
        if (RtssHooksLastFailure != dllPath) {
            RtssHooksLastFailure := dllPath
            LogLine("RTSS live state unavailable: required DLL exports were not "
            . "found in " dllPath "; shortcut fallback remains available.")
        }
        return 0
    }
    RtssHooksModule := module
    RtssHooksDllPath := dllPath
    RtssGetFlagsProc := getProc
    RtssSetFlagsProc := setProc
    RtssLoadProfileProc := loadProfileProc
    RtssGetProfilePropertyProc := getProfilePropertyProc
    RtssSetProfilePropertyProc := setProfilePropertyProc
    RtssSaveProfileProc := saveProfileProc
    RtssUpdateProfilesProc := updateProfilesProc
    RtssHooksLastFailure := ""
    LogLine("RTSS live state connected through RTSSHooks64.dll"
        . (RtssFrameCapWritable() ? " (frame cap writable)." : "; frame cap is read-only."))
    return Map(
        "get", getProc, "set", setProc,
        "loadProfile", loadProfileProc,
        "getProfileProperty", getProfilePropertyProc,
        "setProfileProperty", setProfilePropertyProc,
        "saveProfile", saveProfileProc,
        "updateProfiles", updateProfilesProc)
}

ApplyRtssGlobalState(feature, enabled) {
    ; Say so rather than returning silently. Selecting an RTSS row with RTSS
    ; missing or mis-pathed did nothing at all and gave no reason, which on a
    ; couch UI with no keyboard is indistinguishable from the menu being broken.
    ; The companion has told the user this all along.
    if !EnsureRtssRunning() {
        SharedNotify("RTSS was not found at the configured path", "Warning")
        return false
    }
    api := GetRtssHooksApi()
    if !IsObject(api)
        return false
    if (feature = "overlay") {
        andMask := 0xFFFFFFFE
        xorMask := enabled ? 0x1 : 0
        label := "overlay"
    } else {
        andMask := 0xFFFFFFFB
        xorMask := enabled ? 0 : 0x4
        label := "frame limiter"
    }
    try {
        DllCall(api["set"], "UInt", andMask, "UInt", xorMask, "UInt")
        NotifyRtssSettingsChanged()
        state := GetRtssGlobalState()
        if (IsObject(state) && state[feature] = enabled) {
            SharedNotify("RTSS " label " " (enabled ? "enabled" : "disabled"), "Success")
            return true
        }
    } catch as err {
        LogLine("RTSS SetFlags failed: " err.Message)
    }
    SharedNotify("RTSS did not confirm the " label " change", "Warning")
    return false
}

; ==============================================================================
; RTSS frame-cap writes
; ==============================================================================
; The shell's versions, which the companion's differed from in four ways and no
; others: the notify alias, log wording and level, which per-tree function tests
; that the elevated helper is alive, and the product's own name in one message.
;
; ProductElevatedHelperAlive is the seam that difference needed. The shell's
; check re-verifies the helper's identity on a one-second cache as well as
; testing that the process exists; the companion's only does the latter. Both are
; right for their program, and neither is a reason to keep 143 lines twice.
;
; The foreground-game names in the diagnostic line come from GetQuickMenuPreviousExe
; and ProductBestGameExe, which already answer that question for both products.

; Writes FramerateLimit into the global profile. SaveProfile persists it to
; RTSS's own configuration, so this is a real edit the user will see in RTSS --
; intended, but worth a log line rather than happening silently.
SetRtssGlobalFrameLimit(fps) {
    global RtssFrameLimitCacheTick, RtssFrameCapWriteBlocked
    if !EnsureRtssRunning()
        return false
    api := GetRtssHooksApi()
    if (!IsObject(api) || !RtssFrameCapWritable()) {
        blockedReason := RtssFrameCapBlockedReason()
        SharedNotify(
            blockedReason != "" ? blockedReason : "RTSS live state is unavailable",
            "Warning")
        return false
    }
    fps := ClampInt(fps, 0, 1000)
    ; Straight to the helper when there is one. Attempting the write here first
    ; cannot succeed in the session where a helper exists, and it logged a
    ; "set to N" line before proving anything -- so every cap change recorded
    ; success twice, once falsely, which is exactly the habit the per-game path
    ; was just cured of.
    ;
    ; ProductElevatedHelperAlive() first, because ElevatedRtssWritesAvailable()
    ; reads two FLAGS. A helper that has since exited leaves them both set, so
    ; this posted a request nothing was listening for and then blocked for the
    ; full three-second WaitForElevatedRtssRequest timeout -- under Critical("On"),
    ; so the whole UI froze -- before failing. Never having had a helper was
    ; always handled: RequestElevatedRtssFrameLimit returns false immediately.
    ; It is the helper that dies mid-session that costs the freeze.
    if (ProductElevatedHelperAlive() && ElevatedRtssWritesAvailable())
        return ApplyElevatedRtssFrameLimit(fps)
    value := Buffer(4, 0)
    NumPut("UInt", fps, value, 0)
    try {
        DllCall(api["loadProfile"], "AStr", "")
        ok := DllCall(api["setProfileProperty"],
            "AStr", "FramerateLimit", "Ptr", value, "UInt", value.Size, "Int")
        if !ok {
            LogLine("RTSS FramerateLimit write was rejected.")
            SharedNotify("RTSS did not accept the frame cap", "Warning")
            return false
        }
        DllCall(api["saveProfile"], "AStr", "")
        if api["updateProfiles"]
            DllCall(api["updateProfiles"])
        NotifyRtssSettingsChanged()
        RtssFrameLimitCacheTick := 0
        ; Read it straight back, past the cache the line above just cleared.
        ;
        ; A write RTSS ACCEPTS but does not apply is indistinguishable from a
        ; working one everywhere else: SetProfileProperty reports success, the
        ; row re-reads the old number, and the menu simply looks stuck. That is
        ; a different fault from a rejected write and needs a different fix, so
        ; it is recorded here rather than inferred later from a menu that will
        ; not move.
        readBack := RtssGlobalFrameLimit()
        if (readBack != fps) {
            ; The in-memory write landed and SaveProfile could not persist it,
            ; which is a privilege problem and not an RTSS one. Hand the single
            ; number to the elevated helper before giving up: that is the only
            ; part of this operation needing a token this process does not have.
            ;
            ; Gated for the same reason as the fast path above, and this site
            ; mattered more: it had no gate at all, so a session whose helper had
            ; died paid the three-second timeout HERE as well -- twice in one
            ; call, six seconds of frozen UI for a single frame-cap change.
            if (ProductElevatedHelperAlive() && ElevatedRtssWritesAvailable()
                && ApplyElevatedRtssFrameLimit(fps))
                return true
            ; One failed write is enough to know. Latching it stops the row
            ; accepting presses it cannot honour, and stops this log line
            ; repeating on every press for the rest of the session.
            RtssFrameCapWriteBlocked := true
            ; Names which of the three things actually happened, because they
            ; have different fixes -- and because the elevated write is gated
            ; above, "could not apply it either" would be a false claim in the
            ; two cases where no usable helper was there to be tried.
            helperNote := ElevatedRtssWritesAvailable()
                ? (ProductElevatedHelperAlive()
                    ? " The elevated helper could not apply it either."
                    : " The elevated helper is not running, so it was not tried.")
                : " Elevated frame-cap writes are switched off "
                    . "([RTSS] EnableElevatedFrameCapWrites), so the helper was "
                    . "not tried."
            LogLine("RTSS accepted FramerateLimit " fps " but reports " readBack
                . " immediately afterwards. RTSSHooks is loaded into this process, so "
                . "SaveProfile writes with this account's token"
                . (A_IsAdmin ? "" : ", and " ProductIdentity()["name"] " is NOT running as administrator")
                . "." helperNote
                . " The frame cap is now reported as read-only.", "Warning")
            ; This branch latches the row read-only for the rest of the session
            ; and said nothing to the user while doing it, so the Frame Limit row
            ; simply stopped responding with no reason given anywhere on screen.
            SharedNotify(
                "RTSS did not keep the frame cap"
                . (ElevatedRtssWritesAvailable()
                    ? ". The frame cap is now read-only."
                    : ". Enable elevated frame cap writes in Settings if RTSS is "
                        . "installed under Program Files."),
                "Warning")
            return false
        }
        LogLine("RTSS global FramerateLimit set to " fps ".")
        return true
    } catch as err {
        LogLine("RTSS FramerateLimit write failed: " err.Message)
        SharedNotify("RTSS did not accept the frame cap", "Warning")
        return false
    }
}

; Copies the current global frame cap into the foreground executable's own RTSS
; profile.
;
; Deliberately surgical: the target profile is loaded FIRST so that whatever
; else the user has tuned for that game survives, and only FramerateLimit is
; replaced. Cloning the global profile wholesale would be one call shorter and
; would silently overwrite that game's overlay and hotkey settings.
;
; RTSS applies a per-game profile automatically whenever that executable runs,
; so this is a persistent change the user will not see again until it surprises
; them. Hence the confirmation at the call site and the log line here.
SaveRtssFrameLimitToProfile() {
    global RtssFrameLimitCacheTick
    global RtssFrameCapWriteBlocked
    exeName := RtssProfileTargetExe()
    if (exeName = "") {
        SharedNotify("No foreground game to save a profile for", "Warning")
        return false
    }
    ; Two very different reasons hide behind RtssFrameCapWritable, and treating
    ; them the same killed this feature for a whole session at a time.
    ;
    ; A build without the profile exports is a real dead end. RtssFrameCapWriteBlocked
    ; is NOT: it means an in-process write did not persist, which is precisely
    ; the situation the elevated helper exists for. The old gate refused on
    ; either, so one failed global cap write latched the flag and every
    ; subsequent per-game save returned here -- before reaching the helper,
    ; leaving nothing in its log -- while blaming the RTSS build for a privilege
    ; problem.
    blockedReason := RtssFrameCapBlockedReason()
    if (blockedReason != "" && !RtssFrameCapWriteBlocked) {
        SharedNotify(blockedReason, "Warning")
        return false
    }
    ; Already known not to persist from this process, so do not spend a write
    ; proving it again -- and do not "verify" it either, because verifying a
    ; named profile re-reads the copy SetProfileProperty just wrote and says yes.
    if (ProductElevatedHelperAlive() && ElevatedRtssWritesAvailable()) {
        CommitRtssPendingFrameCap()
        fps := RtssGlobalFrameLimit()
        if ApplyElevatedRtssProfileFrameLimit(exeName, fps) {
            SharedNotify(
                exeName ": " (fps > 0 ? fps " FPS" : "uncapped") " saved",
                "Success")
            return true
        }
        SharedNotify(exeName ": profile not saved", "Warning")
        return false
    }
    if !EnsureRtssRunning()
        return false
    api := GetRtssHooksApi()
    if !IsObject(api)
        return false

    ; Flush anything still pending so the profile gets the value on screen.
    CommitRtssPendingFrameCap()
    fps := RtssGlobalFrameLimit()
    value := Buffer(4, 0)
    NumPut("UInt", fps, value, 0)
    LogLine("RTSS profile target " exeName " (foreground was '"
        . GetQuickMenuPreviousExe() "', engine game '" ProductBestGameExe() "').")
    try {
        ; Load the game's existing profile so unrelated properties are preserved.
        DllCall(api["loadProfile"], "AStr", exeName)
        ok := DllCall(api["setProfileProperty"],
            "AStr", "FramerateLimit", "Ptr", value, "UInt", value.Size, "Int")
        if !ok {
            LogLine("RTSS profile write was rejected for " exeName ".")
            SharedNotify("RTSS did not accept the profile write", "Warning")
            return false
        }
        DllCall(api["saveProfile"], "AStr", exeName)
        if api["updateProfiles"]
            DllCall(api["updateProfiles"])
        NotifyRtssSettingsChanged()
        ; The global profile was displaced by the LoadProfile above; restore it so
        ; the Frame Limit row keeps reading the value it is supposed to show.
        try DllCall(api["loadProfile"], "AStr", "")
        RtssFrameLimitCacheTick := 0
        ; Prove it, exactly as the global cap does.
        ;
        ; This used to report success unconditionally, and unelevated it was
        ; reporting it for a write that had not happened: SaveProfile fails
        ; silently against a Program Files install, so every standard user got a
        ; green "saved" notification and a log line for a profile RTSS never
        ; received. The global cap learned this lesson first; there was no
        ; reason for the per-game path to keep believing itself.
        saved := GetRtssFrameLimit(exeName)
        if (!IsObject(saved) || saved["fps"] != fps) {
            ; Gated like the other three elevated-write sites: ungated, a helper
            ; that had exited cost a three-second frozen wait on every per-game
            ; save that failed its read-back.
            if (ProductElevatedHelperAlive() && ElevatedRtssWritesAvailable()
                && ApplyElevatedRtssProfileFrameLimit(exeName, fps)) {
                SharedNotify(
                    exeName ": " (fps > 0 ? fps " FPS" : "uncapped") " saved",
                    "Success")
                return true
            }
            LogLine("RTSS profile " exeName " did not keep FramerateLimit " fps
                . "; the write was not persisted.", "Warning")
            SharedNotify(exeName ": profile not saved", "Warning")
            return false
        }
        LogLine("RTSS profile " exeName " saved with FramerateLimit " fps ".")
        SharedNotify(exeName ": " (fps > 0 ? fps " FPS" : "uncapped") " saved", "Success")
        return true
    } catch as err {
        LogLine("RTSS profile write failed for " exeName ": " err.Message)
        SharedNotify("RTSS did not accept the profile write", "Warning")
        try DllCall(api["loadProfile"], "AStr", "")
        RtssFrameLimitCacheTick := 0
        return false
    }
}

; ==============================================================================
; Settings scrollbar
; ==============================================================================
; Scroll maths is scroll maths. The two copies read 0.82 and differed only in the
; name of the scrollbar global and where the viewport bounds came from -- two
; globals in the shell, SettingsLayout() in the companion. Neither is a reason to
; keep the SetScrollInfo call twice.
;
; Found by comparing six-line BLOCKS rather than whole functions: the names differ
; and the whole-function score sat below the cross-name threshold, so a
; function-level scan could not see it.

SettingsUpdateScrollBar(offset, maxOffset) {
    scrollBar := ProductSettingsScrollBar()
    if !IsObject(scrollBar)
        return
    if (maxOffset <= 0) {
        try scrollBar.Visible := false
        return
    }

    viewportHeight := ProductSettingsViewportHeight()
    contentHeight := viewportHeight + maxOffset
    scrollInfo := Buffer(28, 0)
    NumPut("UInt", 28, scrollInfo, 0)
    NumPut("UInt", 0x7, scrollInfo, 4) ; SIF_RANGE | SIF_PAGE | SIF_POS
    NumPut("Int", 0, scrollInfo, 8)
    NumPut("Int", contentHeight - 1, scrollInfo, 12)
    NumPut("UInt", viewportHeight, scrollInfo, 16)
    NumPut("Int", offset, scrollInfo, 20)
    try DllCall("User32\SetScrollInfo"
        , "Ptr", scrollBar.Hwnd
        , "Int", 2 ; SB_CTL
        , "Ptr", scrollInfo
        , "Int", true)
    try scrollBar.Visible := true
}

; ==============================================================================
; Quick Menu title
; ==============================================================================
; One page-to-title map. The two copies differed by the product name and by four
; SETTINGS_* pages the companion does not have -- harmless entries for a page it
; never sets, and cheaper than a second map.
;
; ProductIdentity carries a separate "title" because its "name" is prose used in
; sentences ("the companion"), which is not what belongs at the top of a menu.

QuickMenuTitleText() {
    global QuickMenuPage
    titles := Map(
        "AUDIO", "Audio",
        "DISPLAY", "Display & HDR",
        "RTSS", "RTSS & Performance",
        "LAYOUT", "Controller Mappings",
        "TASKS", "Task Switcher",
        "SETTINGS", "Settings",
        "SETTINGS_GENERAL", "Settings  ›  General & Startup",
        "SETTINGS_INPUT", "Settings  ›  Controller & Cursor",
        "SETTINGS_FOCUS", "Settings  ›  Focus & Windows",
        "SETTINGS_RTSS", "Settings  ›  RTSS & Performance",
        "SYSTEM", "System")
    if !titles.Has(QuickMenuPage)
        return ProductIdentity()["title"]
    return ProductIdentity()["title"] "  ›  " titles[QuickMenuPage]
}

; Rows that repeat while the d-pad is held.
;
; Matched on the row's id in both products. The companion matched on "action"
; instead, which happened to work because MenuRow sets action equal to id for
; every adjustable row but one -- so the two were never really testing different
; things, and id is the more robust of the two.
;
; qMouseSpeed exists only in the shell. Naming it here costs nothing: a row the
; companion never builds cannot be the selected row.

; Rows whose value is a number the user dials, rather than a list they step
; through. Only these accept hold-to-repeat.
QuickMenuRowAcceptsRepeat() {
    global QuickMenuRows, QuickMenuSelected
    static ids := QuickMenuIdSet("rtssFrameLimitCustom|volume|qMouseSpeed")
    if (QuickMenuRows.Length = 0
        || QuickMenuSelected < 1 || QuickMenuSelected > QuickMenuRows.Length)
        return false
    return ids.Has(QuickMenuRows[QuickMenuSelected]["id"])
}

; ==============================================================================
; Consolidated by the fingerprint gate
; ==============================================================================
; Each of these was defined in both trees with an identical call sequence and
; different text -- renamed parameters, rewrapped calls, an if-chain against a
; ternary. A text diff scored some of them as low as 0.26 and they were read as
; intentional divergence for that reason. They were not intentional; nothing
; could see past the renaming until DIVERGENT_FUNCTIONS.txt and the gate in
; Validate-Common.ps1 started comparing what the code CALLS.
; ==============================================================================

IsSteamProcess(exeName) {
    exeName := StrLower(Trim(exeName))
    return exeName = "steam.exe" || exeName = "steamwebhelper.exe"
}

QuickMenuHideThenSend(shortcut, delayMs := 150) {
    HideQuickMenu()
    SetTimer(() => SendChordSafe(shortcut), -delayMs)
}

GetFrameCapLabel() {
    global RtssPresetFrameCap
    return RtssPresetFrameCap > 0
        ? RtssPresetFrameCap " FPS Preset"
        : "RTSS Preset"
}

NormalizeKeyForSend(keyName) {
    ; Convert key name to a Send-compatible token.
    ; For multi-character names, wrap in braces: {Tab}, {Esc}, {F1}, {Left}, etc.
    k := keyName
    if (k = "Escape")
    k := "Esc"
    if (k = "Return")
    k := "Enter"
    if (StrLen(k) > 1)
    return "{" k "}"
    return k
}

GetLastLines(text, maxLines, newestFirst := false) {
    if (maxLines <= 0)
    return ""
    t := StrReplace(text, "`r`n", "`n")
    t := StrReplace(t, "`r", "`n")
    lines := StrSplit(t, "`n")
    total := lines.Length
    start := total - maxLines + 1
    if (start < 1)
    start := 1

    out := ""
    if (newestFirst) {
    i := total
    while (i >= start) {
    out .= lines[i] "`r`n"
    i--
    }
    } else {
    i := start
    while (i <= total) {
    out .= lines[i] "`r`n"
    i++
    }
    }
    return out
}

GetBindingValue(key) {
    global ControllerMap
    try {
    return ControllerMap[key]
    } catch {
    return ""
    }
}

QuickMenuRowIsInert(index) {
    global QuickMenuRows
    static inert := Map(
        "hdrUnavailable", true,
        "displayUnavailable", true,
        "displayScaleUnavailable", true,
        "tasksUnavailable", true,
        "rtssMissing", true,
        "rtssDisabled", true)
    if (index < 1 || index > QuickMenuRows.Length)
        return false
    return inert.Has(QuickMenuRows[index]["id"])
}

SystemCursor(mode := "Show") {
    static AndM := Buffer(128, 0xFF)
    static XorM := Buffer(128, 0)
    static Cursors := [32512,32513,32514,32515,32516,32640,32641,32642,32643,32644,32645,32646,32648,32649,32650,32651]
    if (mode = "Hide") {
    for _, id in Cursors {
    hCur := DllCall("CreateCursor","Ptr",0,"Int",0,"Int",0,"Int",32,"Int",32,"Ptr",AndM,"Ptr",XorM,"Ptr")
    DllCall("SetSystemCursor","Ptr",hCur,"Int",id)
    }
    } else {
    DllCall("SystemParametersInfo","UInt",0x57,"UInt",0,"Ptr",0,"UInt",0)
    }
}

TryInvokeTouchKeyboard() {
    ; Windows 11 can keep TabTip/TextInputHost running without presenting the
    ; keyboard. Ask the same UI host used by the taskbar touch-keyboard button to
    ; toggle its visible pane instead of treating process launch as presentation.
    static clsidText := "{4CE576FA-83DC-4F88-951C-9D0782B4E376}"
    static iidText := "{37C994E7-432B-4834-A2F7-DCE1F13B834B}"
    clsid := Buffer(16, 0)
    iid := Buffer(16, 0)
    tip := 0

    if (DllCall("Ole32\CLSIDFromString", "WStr", clsidText, "Ptr", clsid.Ptr, "Int") != 0
        || DllCall("Ole32\CLSIDFromString", "WStr", iidText, "Ptr", iid.Ptr, "Int") != 0)
        return false

    ; CLSCTX_INPROC_SERVER | CLSCTX_LOCAL_SERVER
    hr := DllCall(
        "Ole32\CoCreateInstance",
        "Ptr", clsid.Ptr,
        "Ptr", 0,
        "UInt", 0x5,
        "Ptr", iid.Ptr,
        "Ptr*", &tip,
        "Int")
    if (hr < 0 || !tip)
        return false

    succeeded := false
    try {
        vtable := NumGet(tip, 0, "Ptr")
        toggleMethod := NumGet(vtable, 3 * A_PtrSize, "Ptr")
        desktopHwnd := DllCall("User32\GetDesktopWindow", "Ptr")
        hr := DllCall(toggleMethod, "Ptr", tip, "Ptr", desktopHwnd, "Int")
        succeeded := hr >= 0
    } catch as err {
        try LogLine("Touch keyboard presentation request failed: " err.Message)
    } finally {
        try {
            vtable := NumGet(tip, 0, "Ptr")
            releaseMethod := NumGet(vtable, 2 * A_PtrSize, "Ptr")
            DllCall(releaseMethod, "Ptr", tip, "UInt")
        }
    }
    return succeeded
}

; ------------------------------------------------------------------------------
; Quick-menu integrations: display, HDR shortcut, and RTSS HotkeyHandler
; ------------------------------------------------------------------------------
GetActiveAudioOutputDevices() {
    devices := []
    iidDevice := "{D666063F-1587-4E43-81F1-B948E807363F}" ; IMMDevice

    Loop 32 {
        index := A_Index
        try {
            name := SoundGetName(, index)
        } catch {
            break
        }
        if (name = "")
            continue

        try {
            device := SoundGetInterface(iidDevice, , index)
            idPtr := 0
            ComCall(5, device, "Ptr*", &idPtr) ; IMMDevice::GetId
            id := idPtr ? StrGet(idPtr, "UTF-16") : ""
            if (idPtr)
                DllCall("Ole32\CoTaskMemFree", "Ptr", idPtr)
            if (id != "")
                devices.Push(Map("name", name, "id", id))
        } catch {
            ; Keep enumeration safe; unsupported devices are omitted.
        }
    }
    return devices
}

; ==============================================================================
; Shortcut recorder
; ==============================================================================
GetPhysicalModsMap() {
    return Map(
        "Ctrl", GetKeyState("Ctrl", "P") || GetKeyState("LControl", "P")
            || GetKeyState("RControl", "P"),
        "Alt", GetKeyState("Alt", "P") || GetKeyState("LAlt", "P")
            || GetKeyState("RAlt", "P"),
        "Shift", GetKeyState("Shift", "P") || GetKeyState("LShift", "P")
            || GetKeyState("RShift", "P"),
        "Win", GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
    )
}

QuickMenuGoBack() {
    global QuickMenuPage, QuickMenuSelected
    if (QuickMenuPage = "MAIN") {
        HideQuickMenu()
        return
    }
    if (SubStr(QuickMenuPage, 1, 9) = "SETTINGS_" )
        QuickMenuPage := "SETTINGS"
    else
        QuickMenuPage := "MAIN"
    QuickMenuSelected := 1
    QuickMenuBuildGui()
}

QuickMenuSetRedraw(enabled) {
    global QuickMenuGui, QuickMenuRedrawSuspended
    ; Set the flag BEFORE the early return, not after.
    ;
    ; Returning first leaves the flag stuck at whatever it was if the window has
    ; gone: suspend, lose the GUI, resume, and QuickMenuRedrawSuspended is still
    ; true -- after which QuickMenuPaintRows composes each new bitmap and never
    ; invalidates the control, so the menu shows the page before last. Only
    ; QuickMenuDestroyWindow resetting the flag independently keeps that off the
    ; screen today, which is a second mechanism covering for this one.
    QuickMenuRedrawSuspended := !enabled
    if !IsSet(QuickMenuGui)
        return
    try DllCall(
        "User32\SendMessageW", "Ptr", QuickMenuGui.Hwnd,
        "UInt", 0x000B, "Ptr", enabled ? 1 : 0, "Ptr", 0)
    if enabled {
        ; RDW_INVALIDATE | RDW_NOERASE | RDW_ALLCHILDREN | RDW_UPDATENOW
        try DllCall(
            "User32\RedrawWindow", "Ptr", QuickMenuGui.Hwnd,
            "Ptr", 0, "Ptr", 0, "UInt", 0x01A1)
    }
}

; Thin wrappers over the definitions in SteamShell-Common.ahk. The state each
; one needs is a global here and a parameter there, which is what lets a single
; definition serve all three programs.
ReadBool(section, key, fallback := false) {
    global IniPath
    return ReadIniBool(IniPath, section, key, fallback)
}

ReadInt(section, key, fallback, minimum, maximum) {
    global IniPath
    return ReadIniInt(IniPath, section, key, fallback, minimum, maximum)
}

HasLongBinding(buttonName) {
    global ControllerMap
    return ControllerBindingHasLong(ControllerMap, buttonName)
}

InitXInput() {
    global XInputDll
    if (XInputDll != "")
        return true
    XInputDll := ResolveXInputDll()
    return XInputDll != ""
}

; ============================================================================
; Consolidated once the state each needed existed in both programs
; ============================================================================
; CompanionDisabled and the three Desktop* globals below are declared as
; constants in the program that has no such concept, rather than the function
; being kept in two copies to avoid naming them. A guard that can never fire is
; cheaper than a second implementation that can drift.
;
; SetRtssFrameLimiterState and SetRtssOverlayState differed by one call:
; ShowNotification in standalone against SetStatus in the companion. Both were
; already one-line aliases for SharedNotify, so calling it directly changes
; nothing at run time and removes the last reason these existed twice.
; ============================================================================

SendChordSafe(keys) {
    global CompanionDisabled
    if CompanionDisabled
        return false
    SendChordReleasingModifiers(keys)
    return true
}

; Steam's in-game overlay hook can miss SendInput's effectively instantaneous
; Shift+Tab pulse even though ordinary desktop applications accept it. SendEvent
; honours SetKeyDelay's press duration, giving Steam a real modifier-down window
; in which to observe the second key. The configured shortcut is still used, so
; this is not hard-coded to Shift+Tab.
SendSteamOverlayChord() {
    global SteamOverlayShortcut, CompanionDisabled
    if CompanionDisabled
        return false
    foregroundHwnd := 0
    foregroundExe := ""
    try foregroundHwnd := WinExist("A")
    if foregroundHwnd
        try foregroundExe := WinGetProcessName("ahk_id " foregroundHwnd)
    LogLine("Steam overlay send: " SendToPretty(SteamOverlayShortcut)
        . ", foreground=" (foregroundExe != "" ? foregroundExe : "unknown")
        . ", hwnd=" foregroundHwnd ".")
    sent := false
    try {
        SendEvent("{Ctrl up}{Alt up}{Shift up}{LWin up}{RWin up}")
        ; Delay between events, then how long each key stays down.
        SetKeyDelay(35, 80)
        SendEvent(SteamOverlayShortcut)
        sent := true
    } catch as err {
        LogLine("Steam overlay send failed: " err.Message, "Warning")
    }
    ; Also runs after a partial failure so a modifier can never remain stuck.
    try SendEvent("{Ctrl up}{Alt up}{Shift up}{LWin up}{RWin up}")
    return sent
}

; True while the foreground application is eligible for automatic mouse mode:
; the explicit allowlist in SteamShell presentation, or any non-excluded app in
; Windows desktop mode.
;
; The mechanism is deliberately "pretend View/Back is held" rather than a second
; input mode. The View mappings are already a complete desktop mouse by default --
; right stick moves, left stick scrolls, D-pad arrows, RB left-click, RT
; right-click, Start opens the Start menu -- so reusing them means nothing new to
; design, nothing new to configure, and no second keymap that can drift from the
; first. What happens automatically is exactly what holding View/Back does.
;
; Cached briefly: this is evaluated on every poll tick at ~16 ms, and the
; foreground process cannot change faster than a person can alt-tab.

SetRtssFrameLimiterState(enableLimiter) {
    global RtssFrameLimiterOnShortcut, RtssFrameLimiterOffShortcut
    state := GetRtssGlobalState()
    if IsObject(state) {
        ; Returns BEFORE persisting. The old code fell through to
        ; PersistRtssFrameCapStateNow even when the limiter already matched and
        ; nothing had been applied, so a button press that did nothing still
        ; wrote the settings file.
        if (state["limiter"] = enableLimiter) {
            SharedNotify(
                "RTSS frame limiter is already " (enableLimiter ? "on" : "off"))
            return
        }
        ApplyRtssGlobalState("limiter", enableLimiter)
        PersistRtssFrameCapStateNow()
        return
    }
    SendRtssShortcut(
        enableLimiter ? RtssFrameLimiterOnShortcut : RtssFrameLimiterOffShortcut,
        enableLimiter ? "RTSS frame limiter enable requested"
                      : "RTSS frame limiter disable requested",
        enableLimiter ? "FrameLimiterOnShortcut" : "FrameLimiterOffShortcut")
}

SetRtssOverlayState(showOverlay) {
    global RtssOverlayOnShortcut, RtssOverlayOffShortcut
    state := GetRtssGlobalState()
    if IsObject(state) {
        ; Say so rather than doing nothing. Selecting "Overlay ON" when it is
        ; already on used to produce no toast at all, and on a couch UI with no
        ; keyboard "nothing happened" is indistinguishable from "this is broken".
        if (state["overlay"] = showOverlay) {
            SharedNotify("RTSS overlay is already " (showOverlay ? "on" : "off"))
            return
        }
        ApplyRtssGlobalState("overlay", showOverlay)
        return
    }
    SendRtssShortcut(
        showOverlay ? RtssOverlayOnShortcut : RtssOverlayOffShortcut,
        showOverlay ? "RTSS overlay show requested" : "RTSS overlay hide requested",
        showOverlay ? "OverlayOnShortcut" : "OverlayOffShortcut")
}
