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
; Shared code calls back into the trees through a fixed set of functions, and
; each tree MUST define every one. THE LIST IS NOT HERE, AND NEITHER IS ITS
; LENGTH. Both are $sharedSeamAllowed in Validate-Common.ps1, and it is enforced
; in both directions: every name on it must exist in both trees, and nothing may
; leave this file that is not on it.
;
; This paragraph has now carried a wrong number twice. It named three functions
; when the real count was 28; it was corrected to 24 and the list grew to 36. That
; is not a documentation slip -- it is the same failure SteamShell-Common.ahk's
; header describes happening to THIS file once already ("documented two
; permitted callbacks and had grown to eight before anyone noticed, because
; nothing enumerated what actually left the file"). It was written about this
; file, the remedy was applied only to Common, and the growth resumed.
;
; Prose cannot hold a number that changes, and the second correction proved that
; writing the CURRENT number down just resets the clock. So no count appears here
; at all: the list lives where it is executed, and this paragraph says where to
; look instead of guessing.
;
; SharedNotify was on that three-name list as something "each tree MUST define".
; It is defined HERE, and neither tree defines it. The trees USED to reach it
; through a one-line alias each -- ShowNotification in standalone, SetStatus in
; the companion -- which is why the mistake read as true for as long as it did.
;
; Both aliases are gone. ShowNotification is defined in this file and called by
; both trees; nothing named SetStatus exists any more. This paragraph said
; otherwise for long enough that a caller was written against SetStatus and did
; not resolve -- the third time a sentence in one of these headers has described
; a shape the code had already left.
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
    static warnedNoCompose := false
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
    ; Declared before the try so the finally can free whichever ones were reached.
    labelFont := 0
    labelFontBold := 0
    valueFont := 0
    composed := false
    ; The handoff below was hardened against a throw leaking one bitmap per
    ; repaint. Composition was not, and it is the larger surface: a throw between
    ; the SelectObject above and the release below abandoned the screen DC, the
    ; memory DC, the DIB section, the GDI+ graphics and three fonts -- six
    ; handles, on a menu that repaints on every keypress. The code twenty lines
    ; up already names GDI handle exhaustion as a state this program reaches; a
    ; page whose row Map is missing a key is all it takes to get there, and that
    ; is a page-builder bug expressing itself as an unrelated rendering collapse
    ; several minutes later.
    try {
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

            composed := true
        }
    } catch as err {
        ; Once. A composition that throws will throw again on the next repaint,
        ; and the repaint rate is the keypress rate.
        if !warnedNoCompose {
            warnedNoCompose := true
            try LogLine("Quick Menu: the row surface could not be composed: "
                . err.Message, "Warning")
        }
    } finally {
        if labelFont
            DllCall("gdiplus\GdipDeleteFont", "Ptr", labelFont)
        if labelFontBold
            DllCall("gdiplus\GdipDeleteFont", "Ptr", labelFontBold)
        if valueFont
            DllCall("gdiplus\GdipDeleteFont", "Ptr", valueFont)
        if graphics
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        DllCall("SelectObject", "Ptr", memDC, "Ptr", previous)
        DllCall("DeleteDC", "Ptr", memDC)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", screenDC)
    }

    ; Nothing was painted, so there is nothing worth handing to the control.
    ; Returning leaves it showing its last good frame, which is what the
    ; CreateDIBSection failure above settles for as well; handing over an
    ; unpainted DIB instead is the blank-rows outcome that path exists to avoid.
    if !composed {
        try DllCall("DeleteObject", "Ptr", bitmap)
        return
    }

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

; ------------------------------------------------------------------------------
; Quick Menu frame cap
; ------------------------------------------------------------------------------
; RTSS exposes two independent mechanisms and the Quick Menu presents them as one
; row, because two rows that can each mean "no limiting" is a menu that fights
; itself:
;
;   limiter flag (global, bit 0x4 = DISABLED)  master on/off
;   FramerateLimit (per profile, DWORD)        the target, 0 = uncapped
;
; "Off" therefore maps to the FLAG and never to the value. Writing 0 would
; destroy the user's number, so turning the cap off and back on would silently
; forget 72 and come back uncapped. Clearing the flag leaves 72 in the profile
; and restores it on the way back.
;
; Everything here targets the GLOBAL profile only. Per-game profiles are the
; user's own tuning and are deliberately never written: a quick menu that edits
; whichever profile happens to be in the foreground is a menu that can silently
; change a game's configuration.
;
; This banner was left behind in SteamShell.ahk, above an unrelated function,
; once the last frame-cap function it described had moved here.
; ------------------------------------------------------------------------------

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
    ; A cap that could not be READ is not a cap that is off. Returning 0 here
    ; renders as "Unavailable", which is the honest answer and the one every
    ; caller already handles; reporting mode "off" instead is what put "‹ OFF ›"
    ; on the row while the limiter was on, and what let
    ; PersistRtssFrameCapStateNow record "off" as the user's selection.
    fps := 0
    if !RtssGlobalFrameLimitRead(&fps)
        return 0
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

; The global cap, with "could not read it" kept separate from "it is zero".
;
; THIS IS THE DIFFERENCE THAT MADE THE LIMITER LOOK OFF WHEN IT WAS ON.
; GetRtssFrameLimit returns 0 for six different reasons -- integration off, DLL
; integration off, RTSS not running, the API unavailable, GetProfileProperty
; returning false, or an exception -- and only one of them means "uncapped".
; Collapsing all six into 0 was fine until something read that 0 as a STATE:
; GetRtssFrameCapState reports mode "off" when fps <= 0, so a failed profile
; read displayed as a limiter that is off, while GetFlags in the very same pass
; was reporting the limiter on.
;
; That is why it was intermittent and why it clustered around boot. GetFlags and
; the profile store come up at different times: shared memory answers as soon as
; RTSS is alive, while LoadProfile/GetProfileProperty can fail for a moment
; longer while RTSS is still initialising. The window is short, which is exactly
; what makes it look like a flicker rather than a fault.
;
; A failure is deliberately NOT cached. Caching it would hold the wrong reading
; for 400 ms past the moment RTSS became readable, turning a one-report glitch
; into a visible one.
RtssGlobalFrameLimitRead(&fps) {
    global RtssFrameLimitCacheFps, RtssFrameLimitCacheTick
    static CACHE_MS := 400
    if (RtssFrameLimitCacheTick
        && A_TickCount - RtssFrameLimitCacheTick < CACHE_MS) {
        fps := RtssFrameLimitCacheFps
        return true
    }
    limit := GetRtssFrameLimit("")
    if !IsObject(limit) {
        fps := 0
        return false
    }
    RtssFrameLimitCacheFps := limit["fps"]
    RtssFrameLimitCacheTick := A_TickCount
    fps := RtssFrameLimitCacheFps
    return true
}

; The number alone, for callers that only compare it. A failed read is 0 here,
; which is the behaviour every one of them already had; the callers that must
; not confuse the two use RtssGlobalFrameLimitRead.
RtssGlobalFrameLimit() {
    fps := 0
    RtssGlobalFrameLimitRead(&fps)
    return fps
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
; Retains a hand-typed Custom FPS, and records that Custom is now the selection.
;
; One definition as of this pass. The two copies had already converged on
; everything that matters and differed only in how they reached the settings
; file: standalone through its staged commit, the companion through a bare
; IniWrite. Routing both through the SharedPersistSettings seam -- which every
; other setting in both products already uses -- left the bodies identical, and
; identical bodies in two trees are what this file exists to end.
PersistRtssCustomFrameCap(value) {
    global RtssCustomFrameCap
    value := ClampInt(value, 10, 1000)
    if !SharedPersistSettings([
        Map("section", "RTSS", "key", "CustomFrameCap", "value", value)
    ]) {
        ShowNotification("The Custom FPS value could not be retained", "Warning")
        return false
    }
    RtssCustomFrameCap := value
    ; Committing a Custom value is also a selection of Custom at that value.
    ; Recorded here rather than in the caller: CommitRtssPendingFrameCap is
    ; shared too, so it cannot carry a tree-specific call.
    PersistRtssFrameCapSelection("custom", value)
    return true
}

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

; Opens the hold window. Thirty seconds, which is comfortably longer than RTSS
; takes to finish starting and comfortably shorter than a user settling in.
ArmRtssFrameLimitHold() {
    global RtssFrameLimitHoldUntil, RtssFrameLimitHoldRetries
    RtssFrameLimitHoldUntil := A_TickCount + 30000
    RtssFrameLimitHoldRetries := 0
    SetTimer(RtssFrameLimitHoldTick, 3000)
}


; Holds the limiter on for a short window after the startup restore.
;
; THE RESTORE WAS BEING UNDONE, NOT FAILING. ApplyRtssGlobalState confirms its
; own write by re-reading the flag word immediately, and it confirmed -- the log
; said "Restored the last Frame Limit selection: CONFIGURED at 158 FPS". By the
; time the user opened the Quick Menu, bit 0x4 was set again and the machine was
; running uncapped. The row was right; the write had not stuck.
;
; The restore fires as soon as RTSS answers, and answering is not the same as
; having finished starting. RTSS applies its own saved runtime state during
; initialisation, and anything written into the flag word before that point is
; overwritten by it. An immediate read-back cannot see this: it happens while
; the value is still ours.
;
; So the write is verified again after RTSS has settled, and re-applied if it
; reverted. Bounded on both axes -- a short window and a small number of
; attempts -- because the one thing this must never become is a loop that fights
; the user. Turning the limiter off in RTSS's own UI during the first half
; minute after boot is rare; a program that silently turns it back on forever
; would be much worse than the fault being fixed.
;
; A change made through SteamShell stops it immediately and needs no check here:
; the Quick Menu's own writes go through PersistRtssFrameCapStateNow, which
; records mode "off" and fails the guard below on the next tick.
RtssFrameLimitHoldTick(*) {
    global RtssLastFrameCapMode, RtssLastFrameCapFps
    global RtssFrameLimitHoldUntil, RtssFrameLimitHoldRetries
    static MAX_RETRIES := 3
    ; "off" is the one selection this must not defend. Re-applying it would mean
    ; writing the disabled bit back over a user who has just turned the limiter
    ; on in RTSS.
    if (RtssLastFrameCapMode = "" || RtssLastFrameCapMode = "off"
        || A_TickCount > RtssFrameLimitHoldUntil
        || RtssFrameLimitHoldRetries >= MAX_RETRIES) {
        SetTimer(RtssFrameLimitHoldTick, 0)
        return
    }
    state := GetRtssGlobalState()
    if !IsObject(state)
        return
    if state["limiter"]
        return
    ; The number is checked too. If RTSS came back with a different cap entirely
    ; then this is not our write being reverted, it is a different state, and
    ; re-enabling the limiter would cap at a number the user never chose.
    fps := 0
    if !RtssGlobalFrameLimitRead(&fps)
        return
    if (fps != RtssLastFrameCapFps) {
        SetTimer(RtssFrameLimitHoldTick, 0)
        LogLine("RTSS holds " fps " FPS rather than the restored "
            . RtssLastFrameCapFps "; leaving the limiter alone.", "Warning")
        return
    }
    RtssFrameLimitHoldRetries += 1
    LogLine("The RTSS limiter was disabled again after the startup restore"
        . " (attempt " RtssFrameLimitHoldRetries " of " MAX_RETRIES
        . "); re-enabling it at " fps " FPS.", "Warning")
    ApplyRtssGlobalState("limiter", true)
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
    fpsRestored := true
    if (state["fps"] != RtssLastFrameCapFps)
        fpsRestored := SetRtssGlobalFrameLimit(RtssLastFrameCapFps)

    ; A failed FPS write does NOT stop the limiter being re-enabled.
    ;
    ; These are two different mechanisms with two different failure modes, and
    ; only one of them needs a privilege this process usually lacks. The FPS is a
    ; property of RTSS's Global profile ON DISK, so with a stock Program Files
    ; install it cannot be saved unelevated -- the header above
    ; RtssFrameCapBlockedReason records that measurement. The limiter flag goes
    ; through RTSS's shared memory and works either way.
    ;
    ; This returned on a failed FPS write, before ever reaching the flag, and
    ; that is why the limiter "sometimes" did not survive a reboot. The two
    ; outcomes were decided by something the user cannot see:
    ;
    ;   RTSS already holds the recorded FPS -> no write attempted, flag enabled,
    ;                                          the limiter comes back on
    ;   RTSS holds a different FPS          -> write attempted, write fails,
    ;                                          return, flag never enabled
    ;
    ; and the second case is self-perpetuating, because the reason RTSS holds a
    ; different number is usually that an earlier write was blocked too. The
    ; recorded FPS is the one the user picked; RTSS's is the one that stuck.
    ;
    ; Capping at RTSS's own number is much closer to what the user asked for than
    ; not capping at all, so the flag goes on regardless and the log says which
    ; half was restored.
    if (!state["limiter"]
        && !ApplyRtssGlobalState("limiter", true)) {
        LogLine(
            "The last Frame Limit selection could not be restored: RTSS did not "
            . "confirm enabling the limiter.", "Warning")
        return
    }
    if !fpsRestored {
        ; Deliberately not recorded as the live selection. The cap in force is
        ; RTSS's number, not the one that was chosen, and overwriting the record
        ; with it would lose what the user actually asked for -- which is the
        ; value the next boot should still be trying to restore.
        LogLine(
            "Re-enabled the RTSS limiter, but the last Frame Limit FPS ("
            . RtssLastFrameCapFps ") could not be written: "
            . RtssFrameCapBlockedReason() ". It is capping at RTSS's own "
            . state["fps"] " FPS instead.", "Warning")
        return
    }
    RtssFrameCapCustomMode := (RtssLastFrameCapMode = "custom")
    LogLine(
        "Restored the last Frame Limit selection: " StrUpper(RtssLastFrameCapMode)
        . " at " RtssLastFrameCapFps " FPS.")
    ; And watch that it stays restored. RTSS applies its own saved runtime state
    ; while it finishes starting, which can overwrite the flag this just set --
    ; after the read-back that confirmed it.
    ArmRtssFrameLimitHold()
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

; Where the request file is written. The two products keep their data in
; different places -- the shell under a directory Setup can relocate, the
; companion beside its own executable because it is portable -- and that is the
; whole of what used to differ between two copies of this function. It is a
; question to ask the product, not a routine to write twice.
;
; Deliberately NOT the settings file. This is a request, not a setting: it has
; no meaning once serviced, it must not be staged through CommitIniChanges
; beside the user's real configuration, and keeping it separate means the whole
; of what crosses into the elevated process is two integers and a name in a file
; that contains nothing else.
ElevatedRtssRequestPath() {
    return ProductDataDir() "\rtss-request.ini"
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
    global EnableRTSSIntegration, RtssUseDllIntegration, RtssLastFlagsSeen
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
    ; Logged when it CHANGES, not when it is read -- this runs on every repaint
    ; of the RTSS page, so logging each read would be several lines a second and
    ; would say nothing.
    ;
    ; A change is exactly what is worth seeing. The row reports the limiter from
    ; bit 0x4, and the open question is whether something clears that bit after
    ; the startup restore has set it: RTSS re-hooking, a profile reload, another
    ; tool, or one of this program's own writes. Without a timestamped record of
    ; the word itself there is nothing to tell those apart afterwards, and the
    ; fault is intermittent enough that it has to be caught rather than
    ; reproduced.
    if (RtssLastFlagsSeen != flags) {
        LogLine("RTSS flags: 0x" Format("{:08X}", flags)
            . " (overlay " ((flags & 0x1) != 0 ? "on" : "off")
            . ", limiter " ((flags & 0x4) = 0 ? "on" : "OFF")
            . ", global FramerateLimit " RtssGlobalFrameLimit() ")"
            . (RtssLastFlagsSeen = -1
                ? ""
                : " -- was 0x" Format("{:08X}", RtssLastFlagsSeen)))
        RtssLastFlagsSeen := flags
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

; Stages a diagnostic bundle and zips it, for both products.
;
; The ENVELOPE was written twice: timestamped staging directory under %TEMP%,
; sanitised text files, Compress-Archive through PowerShell, delete the staging
; directory on the way out of BOTH paths. What legitimately differs is the file
; NAMES and their contents, so those arrive as a Map and the caller reports
; success its own way -- the shell into the Health Check and Settings status
; lines, the companion through a notification.
;
; Duplicating the envelope is how the two bundles drifted in the first place. The
; companion collected display scale, HDR, the active input backend, the XInput
; slot and the RawInput registration state for months while the shell collected
; none of it -- on the product where an unreadable controller means a machine the
; user cannot drive. Sharing the envelope does not by itself keep the CONTENTS in
; step, but it removes the reason they were ever edited separately.
;
; SANITISATION HAPPENS HERE, not in the callers. Every file written goes through
; SanitizeDiagnosticText on the way in, so a new file added to the map cannot
; forget it and put a user's paths into an archive they are about to send someone.
;
; Returns the zip path, or "" with the reason in failureReason.
ExportDiagnosticArchive(namePrefix, files, &failureReason) {
    failureReason := ""
    stamp := FormatTime(A_Now, "yyyyMMdd-HHmmss")
    tempDir := A_Temp "\\" namePrefix "-Diagnostics-" stamp
    zipPath := A_Desktop "\\" namePrefix "-Diagnostics-" stamp ".zip"
    try {
        DirCreate(tempDir)
        for name, text in files {
            if (text = "")
                continue
            FileAppend(SanitizeDiagnosticText(text), tempDir "\\" name, "UTF-8")
        }
        psPath := StrReplace(tempDir "\\*", "'", "''")
        psZip := StrReplace(zipPath, "'", "''")
        psCommand := "Compress-Archive -Path '" psPath
            . "' -DestinationPath '" psZip . "' -Force"
        exitCode := RunWait('powershell -NoProfile -NonInteractive -Command "'
            . psCommand . '"', , "Hide")
        if (exitCode != 0 || !FileExist(zipPath))
            throw Error("PowerShell could not create the ZIP archive.")
        try DirDelete(tempDir, true)
        return zipPath
    } catch as err {
        ; The staging directory goes on the FAILURE path too. Only the success
        ; path used to delete it, and the throw above -- the most likely way out
        ; of here on a machine with a problem worth bundling -- left the
        ; sanitised settings and two thousand lines of log in %TEMP%, once per
        ; attempt, while telling the user nothing had been exported.
        try DirDelete(tempDir, true)
        failureReason := err.Message
        return ""
    }
}

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

; Brings the selection back into range, wrapping at both ends.
;
; One definition as of this pass. Both trees implemented this seam and both
; wrapped, so the products already agreed on the behaviour -- but the shell's
; also answered for an EMPTY row list and the companion's did not: with no rows,
; the companion left the selection pointing at row 1 of nothing, which is a
; throw at the next subscript rather than a wrong highlight. QuickMenuMoveSelection
; below happens to refuse an empty list before it ever calls this, which is why
; that never showed; a guard that is only correct because of its one caller is
; the kind that stops being correct when a second caller appears.
;
; The shell reached this through a second name, QuickMenuClampSelection, whose
; body wrapped rather than clamped. Both names are gone.
QuickMenuNormalizeSelection() {
    global QuickMenuRows, QuickMenuSelected
    if (QuickMenuRows.Length = 0) {
        QuickMenuSelected := 1
        return
    }
    if (QuickMenuSelected < 1)
        QuickMenuSelected := QuickMenuRows.Length
    if (QuickMenuSelected > QuickMenuRows.Length)
        QuickMenuSelected := 1
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
; Finds the controller, wherever XInput has put it this time.
;
; Steam Input and Xbox mode reorder physical and virtual controllers while the
; process is running: launching a game through Steam Input adds a virtual pad and
; the physical one shifts slot. Reading only the configured index therefore stops
; working mid-session, with the pad still connected and still lit.
;
; That was standalone's behaviour until this pass, and standalone is the product
; running AS THE WINDOWS SHELL on a machine with no keyboard -- so the recovery
; it offered was "open Settings and change Controller Index" using the controller
; that had just stopped working. The companion has scanned since it was written.
; Nothing about the scan is companion-specific, which is the whole reason this
; sat in one tree for as long as it did: it reads as a piece of that product's
; backend work rather than as the general answer it is.
;
; Order matters. The last slot that answered comes first, so a settled session
; costs one call; then the configured index, so an explicit choice still wins on
; a cold start; then the rest, so it is found regardless. The slot is logged when
; it changes, because "the controller moved" is otherwise indistinguishable from
; "the controller broke" in a log.
; Rate limiter for the all-slots XInput sweep, and the way to cancel it.
;
; XInputGetState against a slot with nothing in it is the expensive call in this
; program. It does not return from a cached state -- it goes down to the device
; stack -- and Microsoft's own guidance is not to poll empty slots every frame.
; The sweep below runs only when the slot that answered last time has stopped
; answering, which sounds rare and is not: with no controller attached it is
; EVERY poll, so a 16 ms timer was making 250 of those calls a second, all of
; them returning "not connected".
;
; 250 ms is chosen against the bug the sweep exists to fix rather than against the
; saving. The comment in each tree's ControllerReadState records that a pad Steam
; Input moved to another slot "simply stopped answering" until the sweep was
; added -- and a slot move is precisely the case where the fast path fails and the
; sweep is what recovers it. So the cost of this limiter is dead input for up to
; one interval after a slot move. A quarter second is under the threshold where
; that reads as anything at all, and it still removes 98% of the calls.
;
; Reset cancels the wait outright, so an event that means "the hardware changed"
; does not have to wait out a backoff measured for the case where nothing has.
XInputScanGate(reset := false) {
    static nextAllowedTick := 0
    static FULL_SCAN_INTERVAL_MS := 250
    if reset {
        nextAllowedTick := 0
        return true
    }
    if (nextAllowedTick && A_TickCount < nextAllowedTick)
        return false
    nextAllowedTick := A_TickCount + FULL_SCAN_INTERVAL_MS
    return true
}


; Device arrival or removal. Cancels the sweep backoff so a controller that was
; just plugged in is picked up on the next poll instead of up to 250 ms later.
;
; DBT_DEVNODES_CHANGED is broadcast to top-level windows without
; RegisterDeviceNotification, so this needs no setup beyond the OnMessage. If it
; never arrives -- a message-only window would not receive a broadcast -- nothing
; breaks: the limiter simply expires on its own, which is why this is an
; optimisation for the common case and not a mechanism anything depends on.
DeviceChangeMessage(wParam, lParam, msg, hwnd) {
    static DBT_DEVNODES_CHANGED := 0x0007
    if (wParam = DBT_DEVNODES_CHANGED)
        XInputScanGate(true)
    return true
}


XInputResolveController(&state) {
    global ControllerIndex, ActiveControllerIndex
    static lastMissingLogTick := 0
    static lastScanLogTick := 0

    ; The slot that answered last time, every tick, ahead of the limiter. A
    ; connected controller therefore costs exactly one call and is unaffected by
    ; any of the above.
    if (ActiveControllerIndex >= 0 && ActiveControllerIndex <= 3) {
        if (XInputGetState(ActiveControllerIndex, &state) = 0)
            return true
    }

    ; The fast path missed, so this is the sweep -- the expensive branch, and the
    ; one that is rate-limited. Reporting false here means "no reading this tick",
    ; which the callers already handle: RawInputReadState returns false the same
    ; way whenever reports have gone stale.
    if !XInputScanGate()
        return false

    candidates := []
    seen := Map()
    if (ActiveControllerIndex >= 0 && ActiveControllerIndex <= 3) {
        candidates.Push(ActiveControllerIndex)
        seen[ActiveControllerIndex] := true
    }
    if !seen.Has(ControllerIndex) {
        candidates.Push(ControllerIndex)
        seen[ControllerIndex] := true
    }
    Loop 4 {
        index := A_Index - 1
        if !seen.Has(index)
            candidates.Push(index)
    }

    ; What the sweep actually costs, on the record and rate-limited to once a
    ; minute. Inferring this from the source is how it went unnoticed: the call
    ; count is the poll rate times the candidate list, and neither number appears
    ; anywhere near the other.
    if (!lastScanLogTick || A_TickCount - lastScanLogTick >= 60000) {
        lastScanLogTick := A_TickCount
        LogLine("XInput: sweeping " candidates.Length " slot(s); the cached slot "
            . "did not answer. At most one sweep every 250ms.", "Info")
    }

    for _, index in candidates {
        if (XInputGetState(index, &state) = 0) {
            if (ActiveControllerIndex != index) {
                oldIndex := ActiveControllerIndex
                ActiveControllerIndex := index
                if (oldIndex < 0)
                    LogLine("XInput controller connected on slot " index ".")
                else
                    LogLine("XInput controller moved from slot " oldIndex " to slot " index ".")
            }
            return true
        }
    }

    if (ActiveControllerIndex >= 0) {
        LogLine("XInput controller disconnected from slot " ActiveControllerIndex ".", "Warning")
        ActiveControllerIndex := -1
        lastMissingLogTick := A_TickCount
    } else if (!lastMissingLogTick || A_TickCount - lastMissingLogTick >= 30000) {
        LogLine("No XInput controller detected on slots 0–3.", "Warning")
        lastMissingLogTick := A_TickCount
    }
    return false
}

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

; XINPUT_CAPABILITIES: type, subtype, flags, then the gamepad struct. Static per
; device, so the diagnostic reports it once per slot rather than every tick.
XInputGetCapabilities(index, &caps) {
    global XInputDll
    if (XInputDll = "" && !InitXInput())
        return 1167
    if !IsObject(caps)
        caps := Buffer(20, 0)
    try {
        return DllCall(XInputDll "\XInputGetCapabilities", "UInt", index,
            "UInt", 0, "Ptr", caps, "UInt")
    } catch {
        return 1
    }
}

; ==============================================================================
; Controller diagnostics
; ==============================================================================
; Samples EVERY XInput slot on one tick and logs the combined state whenever it
; changes.
;
; The normal poll stops at the first slot that answers, which cannot tell a
; genuinely filtered pad from a virtualised one. When something captures a
; physical controller and re-publishes a partial copy, the giveaway is two
; devices present at once where one forwards only a subset of the buttons. The
; reported capabilities (type/subtype/flags) also tend to differ between real
; and synthesised devices. Logging the foreground process alongside them shows
; which application owned focus at the moment a button went missing.
;
; SHARED, and it was not. The DiagnosticLogging row has shipped in BOTH products
; since the settings spec was unified -- drawn in both Settings windows, read
; into EnableControllerDiagnostics in both trees, labelled "Log all XInput slots
; on every change" in both. Only the companion had a tick. In the shell the flag
; reached exactly one consumer: PositionGuiCentered, which logs window centring.
; A control that promises one thing and does another is worse than a missing
; one, because it is evidence -- someone turns it on, sees no slot lines, and
; concludes the pad is not being sampled.
;
; The per-product half is behind ProductControllerDiagnosticProbe(). The
; companion has GameInput to compare XInput against and a second backend name to
; report; the shell has neither, and inventing a placeholder for it would put
; the fabrication in the log where the missing feature used to be.
ControllerDiagnosticTick() {
    global EnableControllerDiagnostics, ControllerBackend
    static lastSignature := ""
    static capsLogged := Map()
    static lastKeepaliveTick := 0

    if !EnableControllerDiagnostics
        return

    slotText := ""
    signature := ""
    Loop 4 {
        index := A_Index - 1
        slotState := Buffer(16, 0)
        if (XInputGetState(index, &slotState) != 0) {
            slotText .= " s" index "=-"
            signature .= "-|"
            continue
        }
        buttons := NumGet(slotState, 4, "UShort")
        lt := NumGet(slotState, 6, "UChar")
        rt := NumGet(slotState, 7, "UChar")
        slotText .= " s" index "=0x" Format("{:04X}", buttons)
        if (lt > 30 || rt > 30)
            slotText .= "(LT" lt "/RT" rt ")"
        signature .= buttons "," lt "," rt "|"
        ; Capabilities are static per device, so report them once per slot.
        if !capsLogged.Has(index) {
            capsLogged[index] := true
            caps := Buffer(20, 0)
            if (XInputGetCapabilities(index, &caps) = 0) {
                LogLine("Diag slot " index " capabilities:"
                    . " type=" NumGet(caps, 0, "UChar")
                    . " subtype=" NumGet(caps, 1, "UChar")
                    . " flags=0x" Format("{:04X}", NumGet(caps, 2, "UShort"))
                    . " buttonmask=0x" Format("{:04X}", NumGet(caps, 4, "UShort")))
            } else {
                LogLine("Diag slot " index " capabilities unavailable.")
            }
        }
    }

    probe := ProductControllerDiagnosticProbe()
    signature .= probe["signature"]

    ; Change-only logging cannot distinguish a process reading constant zeros
    ; from one that has been suspended or killed: both go silent. An unconditional
    ; keepalive line every few seconds makes silence unambiguous evidence that the
    ; program stopped running, rather than something needing interpretation.
    unchanged := signature = lastSignature
    if (unchanged && lastKeepaliveTick && A_TickCount - lastKeepaliveTick < 5000)
        return
    lastKeepaliveTick := A_TickCount
    lastSignature := signature

    foreground := "unknown"
    try foreground := WinGetProcessName("A")
    LogLine("Diag " (unchanged ? "(alive) " : "") ControllerBackend probe["suffix"]
        . slotText probe["detail"] " | fg=" foreground)
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

; Every operational line gets a timestamp and a level.
;
; Without the timestamp the log records what happened but not when, so two lines
; could be one second or one hour apart and nothing said which -- and elapsed
; time is exactly what a startup stall, a focus handoff, or a sustained-exit
; window has to be reasoned about in.
;
; One definition as of this pass. The companion had inlined the whole of
; LogRawLine below rather than calling it -- the same rotate-then-append, with
; the newline moved inside the length estimate instead of added to it -- so the
; single busiest function in either product was two copies of four lines, and the
; rotation call that keeps a shell's log from growing without bound sat in both
; of them. SteamShell-Helper.ahk still defines its own, because it cannot see
; this file; that copy is on the record in DIVERGENT_FUNCTIONS.txt.
LogLine(message, level := "Info") {
    LogRawLine(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " [" level "] " message)
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
; ==============================================================================
; RECENTLY USED APPLICATIONS
; ==============================================================================
; The applications the user has actually had in front, most recent first.
;
; WHY A HISTORY AND NOT A LIVE LIST. Every exe-list setting in both products is
; edited from the Settings window, and by the time that window is open SETTINGS
; IS THE FOREGROUND APPLICATION. "What is in front right now" is therefore always
; the wrong answer to "which application did you mean" -- the app the user wants
; to name stopped being current the moment they went looking for the setting.
; The AlwaysFocus Manager's existing picker reads live and has exactly this
; problem; it works only because that window is opened while the target is still
; running, and it still cannot offer something closed five minutes ago.
;
; Sampled on its OWN timer rather than from either tree's foreground observer.
; The companion has ObserveForeground and the shell has
; ObserveForegroundForMouseParking, but the shell's runs inside WindowEngineTick,
; which stops in desktop mode -- so the history would be silently empty in one
; mode of one product. A history with a hole in it is worse than no history,
; because nothing about it looks broken.
;
; In memory, deliberately not persisted. It survives as long as the process,
; which for a shell is the whole login session, and that covers the case this
; exists for. Writing it down would mean an INI that grows, a pruning rule, and a
; record of every application the user has opened sitting inside a diagnostic
; bundle they are asked to send to somebody.

; How many entries the picker offers.
RecentAppsMax() {
    return 5
}

; One second. Fast enough that an application the user alt-tabbed through is
; caught, slow enough to be free: the tick reads ONE window, not an inventory --
; a foreground handle, its PID, class and title -- against the 500 ms sweep of
; the whole desktop that the window engine already runs.
;
; A function rather than a global for the same reason RecentAppsMax is one:
; neither tree has to declare it, so neither can declare it differently.
RecentAppsIntervalMs() {
    return 1000
}

; The store.
;
; A static here rather than a global, for the same reason SharedWindowInventoryGet
; keeps its cache in one: this is shared-file state with no per-tree meaning, and
; a global would have to be declared in both trees to satisfy the parity check.
; Arrays are by reference, so the recorder mutates what this returns.
RecentAppsAll() {
    static list := []
    return list
}

; Everything that is a window but not an APPLICATION the user chose to use.
;
; ApplicationFrameHost.exe is excluded, which excludes every windowed Store app
; with it. That is deliberate and it is the same decision the shipped
; automatic-mouse allowlist records: a UWP app's visible window belongs to the
; frame host, so offering it here would put `applicationframehost.exe` into an
; exe list -- one entry that silently matches Settings, Photos, Calculator, the
; Store and everything else of that shape. A picker makes that one click instead
; of a deliberate typo, so the entry it would produce is kept out of reach until
; the hosted process behind the frame can be resolved properly.
RecentAppsExcluded(exe, windowClass) {
    static excludedExe := Map(
        "", true,
        ; The UWP frame host. See above.
        "applicationframehost.exe", true,
        ; Shell surfaces, not applications: Start, Search, the touch keyboard
        ; and the lock screen are things Windows shows, not things a user ran.
        "searchhost.exe", true,
        "searchui.exe", true,
        "startmenuexperiencehost.exe", true,
        "shellexperiencehost.exe", true,
        "textinputhost.exe", true,
        "lockapp.exe", true)
    static excludedClass := Map(
        "progman", true, "workerw", true,
        "shell_traywnd", true, "shell_secondarytraywnd", true,
        "windowsdashboard", true)
    return excludedExe.Has(exe) || excludedClass.Has(windowClass)
}

; Records one application, most recent first, deduped by executable.
;
; Deduped by EXE and not by window: the lists this feeds name executables, so a
; browser with six windows is one entry. The title is refreshed on each sighting
; so the row shows what the user last saw rather than the first thing that
; application happened to be called.
RecentAppsRecord(exe, title) {
    if (exe = "")
        return
    list := RecentAppsAll()
    index := 0
    for position, item in list {
        if (item["exe"] = exe) {
            index := position
            break
        }
    }
    if index
        list.RemoveAt(index)
    list.InsertAt(1, Map("exe", exe, "title", title != "" ? title : exe))
    while (list.Length > RecentAppsMax())
        list.RemoveAt(list.Length)
}

; A copy, so a caller iterating the picker cannot reorder the history under the
; timer that maintains it.
RecentAppsGet() {
    return RecentAppsAll().Clone()
}

RecentAppsTick() {
    global ScriptPid
    hwnd := 0
    try hwnd := WinExist("A")
    if !hwnd
        return
    exe := ""
    windowClass := ""
    title := ""
    try {
        ; Our own Settings window is the single most common foreground while
        ; this list is being read. Recording it would push a real entry out of a
        ; five-deep history every time somebody opened Settings.
        if (WinGetPID("ahk_id " hwnd) = ScriptPid)
            return
        exe := StrLower(WinGetProcessName("ahk_id " hwnd))
        windowClass := StrLower(WinGetClass("ahk_id " hwnd))
        title := WinGetTitle("ahk_id " hwnd)
    } catch {
        return
    }
    if RecentAppsExcluded(exe, windowClass)
        return
    RecentAppsRecord(exe, title)
}

; Choose one recently used application, and hand its executable to the caller.
;
; CALLBACK, NOT A RETURN VALUE. AutoHotkey GUIs are not modal, so a picker that
; returned a choice would have to spin waiting for its own window to close --
; inside a Settings window that is itself driving timers. The caller supplies
; what to do with the answer instead, which is also what lets the two products
; share this at all: the shell adds a row to a ListView field, the companion
; appends to a pipe-separated edit, and neither shape has to be known here.
;
; Each call owns its own window, held in a LOCAL that the two nested handlers
; close over. Deliberately not a static or a global: a nested function assigning
; to an enclosing function's static is the one piece of AutoHotkey scoping here
; that could not be settled by reading, and the guard it would buy -- stopping a
; second dialog if somebody clicks the button twice -- is worth less than being
; sure the first one closes.
ShowApplicationPicker(promptText, onChosen) {
    recent := RecentAppsGet()

    pickerGui := Gui("+AlwaysOnTop +ToolWindow", "Choose an application")
    pickerGui.SetFont("s10", "Segoe UI")
    pickerGui.AddText("xm ym w520", promptText)
    ; The history is short by design, so the list is sized to it rather than
    ; scrolling: RecentAppsMax rows, plus one so an empty list still has a row
    ; to put its explanation in.
    listView := pickerGui.AddListView(
        "xm y+8 w520 r" (RecentAppsMax() + 1) " -Multi", ["Application", "Last window title"])
    for _, item in recent
        listView.Add("", item["exe"], item["title"])
    if (recent.Length = 0) {
        ; Not an error, and said as such. A freshly started shell has no history
        ; yet, and "nothing here" with no reason reads as a broken dialog.
        listView.Add("", "(nothing yet)",
            "Applications appear here once you have used them.")
    }
    listView.ModifyCol(1, 160)
    listView.ModifyCol(2, 340)
    if (recent.Length > 0)
        listView.Modify(1, "Select Focus")

    ; Fat-arrow closures over two top-level helpers, which is how every other
    ; GUI in these files wires an event.
    ;
    ; A NAMED NESTED FUNCTION would read better and cannot be used. Nested
    ; functions are legitimate callbacks in AutoHotkey, but the shell validator's
    ; named-callback rule resolves a bare handler name against top-level
    ; definitions and the enclosing function's parameters, so a nested name reads
    ; to it as a handler that resolves to nothing -- which is the exact bug that
    ; rule exists to catch, and it caught this. An arrow is not a bare name, so
    ; it is checked at the call inside it instead.
    ;
    ; That rule scans the source WITH ITS COMMENTS, so the handler-wiring syntax
    ; is described here rather than quoted: writing it out named a callback that
    ; does not exist and failed the build a second time.
    hasEntries := recent.Length > 0
    listView.OnEvent("DoubleClick",
        (*) => ApplicationPickerChoose(pickerGui, listView, hasEntries, onChosen))
    addButton := pickerGui.AddButton("xm y+10 w150 h30 Default", "Add")
    addButton.OnEvent("Click",
        (*) => ApplicationPickerChoose(pickerGui, listView, hasEntries, onChosen))
    cancelButton := pickerGui.AddButton("x+10 yp w150 h30", "Cancel")
    cancelButton.OnEvent("Click", (*) => ApplicationPickerClose(pickerGui))
    pickerGui.OnEvent("Close", (*) => ApplicationPickerClose(pickerGui))
    pickerGui.OnEvent("Escape", (*) => ApplicationPickerClose(pickerGui))
    ; Shown before centring: both products' ProductCenterGui centre at whatever
    ; size the window already is, and a window that has never been shown has none.
    pickerGui.Show()
    ProductCenterGui(pickerGui)
}

; Hands the selected executable to whoever opened the picker.
;
; The window is destroyed BEFORE the callback runs, so a callback that opens
; something of its own is not fighting this dialog for the foreground.
ApplicationPickerChoose(pickerGui, listView, hasEntries, onChosen) {
    if !hasEntries
        return
    row := listView.GetNext()
    if !row
        return
    exe := listView.GetText(row, 1)
    try pickerGui.Destroy()
    onChosen(exe)
}

ApplicationPickerClose(pickerGui) {
    try pickerGui.Destroy()
}

HealthResult(results, status, checkName, detail) {
    results.Push(Map(
        "status", StrUpper(status),
        "name", checkName,
        "detail", detail))
}

; Records which backend answered, and says so in the log the first time each one
; does.
;
; The poll runs every ~16 ms, so repeat changes are throttled to keep a flapping
; backend from burying the button diagnostics.
;
; The FIRST time each backend becomes active is always logged, even inside the
; throttle window. Suppressing it once cost a whole test cycle: the switch to
; GameInput happened seconds after startup, was throttled away, and the log gave
; no indication which backend produced the button readings that followed.
;
; Shared because "which backend is answering" is the same question in both
; products, and the shell could not answer it at all: it selected a backend the
; same way and then threw the answer away, so its log and its Health Check could
; only report the SETTING. DIVERGENT_FUNCTIONS.txt names this function as one of
; the four things ControllerReadState needs in both trees before it can be shared
; outright; the other three are the GameInput backend itself, which stays the
; companion's until somebody can put hardware behind it.
SetActiveBackend(backend) {
    global ActiveInputBackend
    static lastLoggedBackend := ""
    static lastLogTick := 0
    static everLogged := Map()
    if (ActiveInputBackend = backend)
        return
    ActiveInputBackend := backend
    if (backend = lastLoggedBackend)
        return
    if (everLogged.Has(backend) && lastLogTick && A_TickCount - lastLogTick < 5000)
        return
    everLogged[backend] := true
    lastLoggedBackend := backend
    lastLogTick := A_TickCount
    LogLine("Controller backend is now " backend ".")
}

; The four controller rows every product can answer, in one place.
;
; THE UNION OF WHAT THE TWO REPORTS HAD, not a copy of either. Each product knew
; something the other did not, and neither gap was visible from inside one tree:
;
;   - the companion RECORDED which backend answered and reported it; the shell
;     INFERRED it from "is RawInput registered and has it ever reported", which
;     is a different question and answers "RawInput" for a pad XInput is actually
;     reading. It now reports the recorded answer, through SetActiveBackend;
;   - the shell reported the slot that ANSWERED alongside the one configured,
;     which is the gap slot discovery exists to close; the companion printed the
;     raw index and never mentioned the configured one;
;   - the shell checked the mapping table for two actions bound to one input; the
;     companion did not, though it has the same table and the same failure;
;   - the companion had the backend and RawInput rows; the shell had neither.
;
; The slot is shown for XInput ONLY. ActiveControllerIndex is written by
; XInputResolveController and by nothing else, so while RawInput is answering it
; holds whatever XInput last left there -- the shell printed that stale slot
; beside a RawInput reading, which is the one combination that would send someone
; looking at the wrong device.
;
; Slots are reported 1-based, as the shell did. XInput numbers them 0-3
; internally and every user-facing thing in Windows calls the first one
; "controller 1"; the companion printed the raw index, so the same pad was "slot
; 0" in one product and "slot 1" in the other.
;
; `detected` is passed in rather than probed here so this stays a formatter.
; ControllerReadState is the one part that genuinely still differs per product --
; the companion tries a GameInput backend the shell deliberately does not offer --
; so each tree does its own detection and hands over the answer.
;
; GameInput has no row here for the same reason. The Backend setting offers it in
; the companion only ("it reads all zeros outside Xbox FSE, so it is not an option
; the shell could offer honestly"), and a row reporting a backend that cannot
; exist would be noise in the shell's report. The companion appends its own.
SharedControllerHealthRows(results, detected) {
    global ControllerBackend, ActiveInputBackend, ActiveControllerIndex
    global ControllerIndex, ControllerMap
    global RawInputProbeActive, RawInputLastReportTick
    if detected {
        via := ActiveInputBackend = "rawinput"
            ? "RawInput"
            : (ActiveInputBackend = "gameinput" ? "GameInput" : "XInput")
        slot := ""
        if (ActiveInputBackend != "rawinput" && ActiveInputBackend != "gameinput"
            && ActiveControllerIndex >= 0) {
            slot := " on slot " (ActiveControllerIndex + 1)
                . (ActiveControllerIndex != ControllerIndex
                    ? " (configured: " (ControllerIndex + 1) ")" : "")
        }
        HealthResult(results, "PASS", "Controller",
            via " controller is connected" slot ".")
    } else {
        HealthResult(results, "WARN", "Controller",
            "No controller was detected on any backend.")
    }
    HealthResult(results, "INFO", "Input backend",
        "Setting: " ControllerBackend ". Active: " ActiveInputBackend ".")
    HealthResult(results,
        !RawInputProbeActive ? "INFO" : (RawInputLastReportTick ? "PASS" : "INFO"),
        "RawInput",
        !RawInputProbeActive
            ? "Not registered."
            : (RawInputLastReportTick
                ? "Registered and receiving HID reports."
                : "Registered, no reports yet. Expected outside Xbox FSE."))

    ; Two actions on one input is silent: the second binding simply never fires,
    ; and the button looks broken rather than double-booked.
    bindingOwners := Map()
    duplicateBindings := []
    for mappingKey, bindingValue in ControllerMap {
        normalizedBinding := StrLower(Trim(bindingValue))
        if (normalizedBinding = "" || normalizedBinding = "builtin:none")
            continue
        if bindingOwners.Has(normalizedBinding)
            duplicateBindings.Push(bindingOwners[normalizedBinding] " + " mappingKey)
        else
            bindingOwners[normalizedBinding] := mappingKey
    }
    HealthResult(results, duplicateBindings.Length ? "WARN" : "PASS",
        "Controller mappings",
        duplicateBindings.Length
            ? "Shared actions: " JoinWith(duplicateBindings, ", ")
            : "No duplicate mapped actions were found.")
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
        ; A failed read must not be written. "Save Limit to Profile" copies the
        ; global cap into the game's own profile, and a read that failed reports
        ; 0 -- which would write "uncapped" over the profile the user was trying
        ; to populate, and report success for it.
        fps := 0
        if !RtssGlobalFrameLimitRead(&fps) {
            SharedNotify(exeName ": RTSS did not report the current cap", "Warning")
            return false
        }
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
    ; Same refusal as the elevated path above, for the same reason.
    fps := 0
    if !RtssGlobalFrameLimitRead(&fps) {
        SharedNotify(exeName ": RTSS did not report the current cap", "Warning")
        return false
    }
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

; ONE definition, for both products, as of this pass. It lived only in the
; companion, and the reason recorded for that -- that the shell uses View/Back as
; its mapping modifier and so has no bare press to give meaning to -- was wrong:
; the companion uses it as a modifier too, for exactly the same mappings and the
; same automatic mouse mode, and expresses that the same way
; (mappingActive := viewDown || autoMouse). The two poll loops are the same shape
; here. What made the feature possible in one and "impossible" in the other was
; not architecture, it was that only one of them had been given the tracking.
;
; usedAsModifier is the whole mechanism: any other input during the hold means
; View was being used to reach a mapping or drive the pointer, so its own action
; is dropped on release.

; Resolves the View button's own action, on release.
;
; View is also the mapping modifier, so this only runs when nothing else was
; touched during the hold -- otherwise "hold View, press A" would fire a Steam
; shortcut underneath the mapping. Resolving on release rather than at a timer
; is what makes that possible.
;
;   Steam in front   tap  -> Steam menu        hold -> Steam Quick Access
;   Game in front    tap  -> nothing           hold -> Steam overlay
;
; The tap doing nothing in a game is deliberate: the companion never blocks
; input, so the game receives View normally and keeps its own use of it.
ViewButtonReleased(heldMs, usedAsModifier) {
    global EnableViewSteamActions, EnableViewTapAction, EnableViewHoldAction
    global ViewHoldMs, ViewHoldInGameMs
    global SteamMenuShortcut, SteamQuickAccessShortcut, SteamOverlayShortcut
    if (!EnableViewSteamActions || usedAsModifier)
        return
    steamFront := SteamIsInFront()
    ; In a game the threshold is longer: View is commonly the scoreboard or map
    ; button there and gets held on purpose, so a short threshold would keep
    ; throwing the Steam overlay up during play.
    threshold := steamFront ? ViewHoldMs : ViewHoldInGameMs
    ; Tap and hold are switched independently. A disabled hold still counts as a
    ; hold rather than falling through to the tap action -- releasing after a
    ; long press must never send the shortcut the short press would have.
    if (heldMs >= threshold) {
        if !EnableViewHoldAction
            return
        shortcut := steamFront ? SteamQuickAccessShortcut : SteamOverlayShortcut
        LogLine("View held " heldMs "ms (threshold " threshold ") -> "
            . (steamFront ? "Steam Quick Access" : "Steam overlay")
            . " (" SendToPretty(shortcut) ").")
        if steamFront
            SendChordSafe(shortcut)
        else
            SendSteamOverlayChord()
        return
    }
    if (!EnableViewTapAction || !steamFront)
        return
    LogLine("View tapped -> Steam Menu (" SendToPretty(SteamMenuShortcut) ").")
    SendChordSafe(SteamMenuShortcut)
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
    ; StrSplit("", "`n") yields one empty element, not none, so an empty log came
    ; back as a single blank line -- a log viewer showing one blank row instead of
    ; nothing, and a support bundle with a line in it that was never logged.
    if (text = "")
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

; The out-of-the-box controller map, for both products.
;
; Defaults apply while holding View/Back. Sticks and the D-pad are fixed --
; mouse move, scroll and arrows -- so they are not in the table.
;
; One definition as of this pass, and the pair that got here was invisible to
; all three manifests at once. The shell called it InitDefaultControllerMappings
; and wrote 22 subscript assignments; the companion called it
; DefaultControllerMappings and wrote one Map() literal. Same 22 bindings, same
; three display overrides, verified key by key -- one routine under two names,
; which is the case CROSS_NAME_DUPLICATES.txt exists for and did not catch: that
; check compares CALL SEQUENCES, and neither body calls anything worth comparing.
; A pair of pure-data functions is the shape both the name-keyed gate and the
; call-keyed one are blind to.
;
; The literal form survives because a table is what this is.

; Reads the saved controller mappings over the defaults.
;
; The LOOP is shared; the migration is not. Both trees seeded the defaults and
; then walked the same twenty-two Button.Short/Button.Long keys, normalising a
; bare value to "Send:" and filling ControllerMapDisplay from the .Display key or
; SendToPretty. Two copies of one reader, differing in whitespace and local names.
;
; The companion's version is the one kept, because it is the more correct of the
; two: for a BARE value the shell never consulted .Display and always derived the
; label, so a display name stored against an unprefixed mapping was silently
; ignored. Sharing it fixes that in the shell.
;
; Each tree keeps a thin LoadControllerMappings wrapper -- the shell's carries a
; one-time Start.Short/Start.Long migration that the companion never shipped and
; must not perform. That is the same shape as the ReadBool and ReadInt wrappers
; recorded in DIVERGENT_FUNCTIONS.txt: the name stays in both, the behaviour
; cannot drift, because there is only one reader.
LoadControllerMappingsFromIni() {
    global IniPath, ControllerMap, ControllerMapDisplay
    InitDefaultControllerMappings()
    keys := [
        "A.Short", "A.Long", "B.Short", "B.Long", "X.Short", "X.Long",
        "Y.Short", "Y.Long", "LB.Short", "LB.Long", "RB.Short", "RB.Long",
        "LT.Short", "LT.Long", "RT.Short", "RT.Long", "Start.Short",
        "Start.Long", "L3.Short", "L3.Long", "R3.Short", "R3.Long"
    ]
    for key in keys {
        value := ""
        try value := IniRead(IniPath, "ControllerMap", key, "")
        if (value = "")
            continue
        if (SubStr(value, 1, 5) != "Send:" && SubStr(value, 1, 8) != "Builtin:")
            value := "Send:" value
        ControllerMap[key] := value
        if (SubStr(value, 1, 5) = "Send:") {
            display := ""
            try display := IniRead(IniPath, "ControllerMap", key ".Display", "")
            ControllerMapDisplay[key] := display != "" ? display : SendToPretty(SubStr(value, 6))
        }
    }
}

InitDefaultControllerMappings() {
    global ControllerMap, ControllerMapDisplay
    ControllerMap := Map(
        "RB.Short", "Builtin:LeftClick", "RB.Long", "Builtin:None",
        "RT.Short", "Builtin:RightClick", "RT.Long", "Builtin:None",
        "LT.Short", "Send:^+o", "LT.Long", "Send:^+f",
        "LB.Short", "Send:^!{Tab}", "LB.Long", "Builtin:TaskManager",
        "A.Short", "Builtin:Enter", "A.Long", "Builtin:None",
        "B.Short", "Builtin:Esc", "B.Long", "Builtin:AltF4",
        "X.Short", "Builtin:TabTip", "X.Long", "Builtin:OSK",
        "Y.Short", "Builtin:WinG", "Y.Long", "Builtin:None",
        ; Tap Start for the Windows Start menu, hold it for File Explorer. Both
        ; remain fully customizable in the mapping editor.
        "Start.Short", "Builtin:StartMenu", "Start.Long", "Builtin:Explorer",
        ; Stick clicks are unassigned by default.
        "L3.Short", "Builtin:None", "L3.Long", "Builtin:None",
        "R3.Short", "Builtin:None", "R3.Long", "Builtin:None"
    )
    ControllerMapDisplay := Map(
        "LT.Short", "Ctrl+Shift+O",
        "LT.Long", "Ctrl+Shift+F",
        "LB.Short", "Ctrl+Alt+Tab"
    )
}

GetBindingValue(key) {
    global ControllerMap
    try {
    return ControllerMap[key]
    } catch {
    return ""
    }
}

; Open or close the Quick Menu, unless the product says it cannot right now.
;
; The two copies of this differed only in that standalone refuses while the
; desktop is being restored or when the menu is switched off, and the companion
; has neither state. That is a question to ask the product, not a reason to
; write the routine twice.

; Open the Quick Menu from the notification area, or raise it if it is already up.
;
; Was defined in both trees and scored 1.00 -- IDENTICAL call sequences -- once the
; drift it had been hiding was removed. The shell raised the menu with WinActivate
; while the companion used ForceForegroundWindow, which is the hardened primitive
; this project keeps in SteamShell-Common.ahk precisely because WinActivate loses
; to the foreground lock a fullscreen game holds. That is the situation somebody
; reaching for the tray icon is in, so the shell had the wrong one in the one place
; it mattered.
;
; CompanionDisabled is checked here rather than left to a per-tree wrapper. The
; shell declares it false and never assigns it -- the global exists there only
; because shared code references it and the seam rule requires it in both trees --
; so the guard is a no-op for the shell and the whole function becomes one copy.
TrayOpenQuickMenu(*) {
    global CompanionDisabled, QuickMenuVisible, QuickMenuGui
    if CompanionDisabled
        return
    if QuickMenuVisible {
        try QuickMenuGui.Show()
        try ForceForegroundWindow(QuickMenuGui.Hwnd)
        return
    }
    ShowQuickMenu()
}

ToggleQuickMenu(*) {
    global QuickMenuVisible
    reason := ProductQuickMenuBlockedReason()
    if (reason != "") {
        ShowNotification(reason, "Warning")
        return
    }
    if QuickMenuVisible
        HideQuickMenu()
    else
        ShowQuickMenu()
}

; Start RTSS if it is not already running, minimized, and wait for it to appear.
;
; The two copies differed only in HOW they launched it -- standalone through
; LaunchInteractiveApp so an elevated shell cannot pass its token on, the
; companion through a plain Run. ProductLaunchMinimized is that difference and
; nothing else.
EnsureRtssRunning() {
    path := ResolveRtssExecutablePath()
    if ProcessExist("RTSS.exe")
        return true
    if (path = "")
        return false
    SplitPath(path, , &directory)
    if !ProductLaunchMinimized(path, directory)
        return false
    return ProcessWait("RTSS.exe", 3) != 0
}

; ==============================================================================
; Functions that were the same routine under two names
; ==============================================================================
; Each existed in both trees spelled differently -- SetStatus against
; ShowNotification, GuiSafeLabel against GuiLiteralText, SettingsRepaint against
; SettingsEditorRepaint -- so no check could see them. The fingerprint gate and
; DIVERGENT_FUNCTIONS.txt both compare functions BY NAME, which makes a rename
; the one form of duplication this project was structurally blind to.
;
; GetRtssMenuStatus is the one to remember: its two copies differed in a local
; variable name and nothing else, yet an earlier audit counted the RTSS row as
; DISPLAYING different text in the two products, because it compared the two
; call expressions as strings and the companion's name was different.
;
; The companion's old name is deliberately NOT written out here. The product
; validators match against raw source, comments included, so naming a retired
; function in a comment can SATISFY an assertion that was meant to find it in
; code -- which is exactly what happened while this block was being written.
; ==============================================================================

ShowNotification(message, kind := "Info") {
    SharedNotify(message, kind)
}

GuiLiteralText(text) {
    ; Native Win32 controls interpret a single ampersand as an access-key marker.
    ; Double it whenever user-facing text should display the literal character.
    return StrReplace(text, "&", "&&")
}

IsCloaked(hwnd) {
    cloaked := 0
    try {
    hr := DllCall("dwmapi\DwmGetWindowAttribute"
    , "Ptr", hwnd
    , "UInt", 14
    , "UInt*", cloaked
    , "UInt", 4
    , "Int")
    return (hr = 0) && (cloaked != 0)
    } catch {
    return false
    }
}

; ==============================================================================
; The window inventory
; ==============================================================================
; ONE enumeration of the visible top-level windows, with every fact either
; product asks about each one attached to it.
;
; THIS IS THE LAYER THE CONSOLIDATION MISSED, and everything above it was built
; twice as a result. The JUDGEMENT was shared -- GameWindowShapeVerdict,
; GameWindowCpuVerdict, SortCandidatesByScoreAreaDesc and
; WindowEngineIsLegacyApplicationSurface all live in SteamShell-Common.ahk --
; while the inventory those functions judge stayed per-tree, as
; WindowEngineBuildSnapshot in the shell and AssistInventoryBuild in the
; companion. The two items were 21 keys each and 19 of them identical; the
; companion already carried "proc" and "scriptOwned" as aliases of its own "exe"
; and "ours", written in specifically so the shared detectors would accept them.
; That is what a missing layer looks like from above.
;
; It also explains the Task Switcher existing twice under names that share no
; word, and the companion enumerating windows three times per pass -- assist,
; screen probe, switcher -- where the shell enumerates once and hands the result
; to ten consumers.
;
; THE SUPERSET, NOT EITHER PRODUCT'S FILTERED VIEW. The two builders disagreed
; about membership, not just about key names: the shell keeps desktop and shell
; windows and marks them, the companion dropped them; the companion dropped tool
; windows and degenerate rectangles, the shell kept them. Picking one of those
; would silently change the other product. So the enumeration keeps everything
; that is a visible, uncloaked top-level window and RECORDS the distinctions --
; "desktop", "toolWindow", "degenerate" -- and each caller filters on the way
; out. The filter is then a visible, testable line in the caller rather than a
; difference buried in two enumerations nobody reads side by side.
;
; "bpm" is deliberately absent and defaults false. Big Picture matching needs
; BpmTitle, which is a shell setting the companion does not have, and the shell's
; wrapper fills it in afterwards through WindowEngineTitleMatchesBpm. A seam
; would also have worked; a key the caller owns is cheaper and says the same
; thing.
;
; includeHidden KEEPS THE WINDOWS THE DEFAULT DROPS, flagged rather than
; filtered, and two callers need it for opposite reasons. The screen probe exists
; precisely to report the windows an inventory scan cannot see, with the reason
; each was excluded -- the Xbox FSE switcher is a cloaked tool window, so a probe
; over the filtered list says "1 window, Steam" while the switcher fills the
; screen. The Task Switcher needs it because Windows cloaks Steam Big Picture
; while Xbox FSE owns the display, which is exactly when somebody wants to switch
; to it.
;
; "visible" and "cloaked" are recorded either way, so a caller never has to ask
; the window a second time to find out why it is or is not in the list.
SharedWindowInventoryBuild(includeHidden := false) {
    global ScriptPid
    static WS_VISIBLE := 0x10000000
    static WS_EX_TOOLWINDOW := 0x00000080
    static WS_EX_APPWINDOW := 0x00040000
    static SHELL_CLASSES := Map(
        "progman", true, "workerw", true,
        "shell_traywnd", true, "shell_secondarytraywnd", true)

    items := []
    for hwnd in WinGetList() {
        if !DllCall("User32\IsWindow", "Ptr", hwnd, "Int")
            continue
        cloaked := IsCloaked(hwnd)
        if (cloaked && !includeHidden)
            continue

        id := "ahk_id " hwnd
        style := 0
        exStyle := 0
        ; The style read is the liveness test. A window that dies between
        ; WinGetList and here throws, and there is nothing useful to record
        ; about it.
        try {
            style := WinGetStyle(id) + 0
        } catch {
            continue
        }
        try exStyle := WinGetExStyle(id) + 0
        visible := (style & WS_VISIBLE) != 0
        if (!visible && !includeHidden)
            continue

        pid := 0
        title := ""
        winClass := ""
        proc := ""
        minMax := 0
        x := 0
        y := 0
        width := 0
        height := 0
        try {
            pid := WinGetPID(id)
            title := WinGetTitle(id)
            winClass := WinGetClass(id)
            proc := StrLower(WinGetProcessName(id))
            minMax := WinGetMinMax(id)
            WinGetPos(&x, &y, &width, &height, id)
        } catch {
            continue
        }

        classLower := StrLower(winClass)
        ; Both spellings of the two keys the trees named differently. Dropping
        ; either one means auditing every consumer in both products for which
        ; name it happened to use, and the aliases cost one Map entry each.
        items.Push(Map(
            "hwnd", hwnd,
            "pid", pid,
            "proc", proc,
            "exe", proc,
            "title", title,
            "class", winClass,
            "classLower", classLower,
            "style", style,
            "exStyle", exStyle,
            "owner", DllCall(
                "User32\GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr"), ; GW_OWNER
            "minMax", minMax,
            "x", x,
            "y", y,
            "w", width,
            "h", height,
            "area", Max(0, width) * Max(0, height),
            "scriptOwned", pid = ScriptPid,
            "ours", pid = ScriptPid,
            "visible", visible,
            "cloaked", cloaked,
            "desktop", SHELL_CLASSES.Has(classLower),
            "steam", IsSteamProcess(proc),
            ; A tool window that does not also declare itself an app window is a
            ; palette or an overlay. Recorded rather than dropped: Steam Big
            ; Picture is one of these under Xbox FSE, and the Task Switcher has
            ; to keep it.
            "toolWindow", (exStyle & WS_EX_TOOLWINDOW) && !(exStyle & WS_EX_APPWINDOW),
            ; A MINIMIZED window reports off-screen coordinates, not a zero
            ; rectangle, so this flag is about genuinely degenerate windows and
            ; must not be widened to mean minimized. "minMax" is that question.
            "degenerate", width <= 0 || height <= 0,
            "bpm", false))
    }
    return items
}

; The inventory, reused if it is fresh enough.
;
; The shell's Task Switcher used to read WindowEngineGetFreshSnapshot, which
; serves a cached snapshot up to 1500 ms old. Moving it onto the shared builder
; silently dropped that: GetPinnedForegroundSummary is the "tasks" row's VALUE,
; so every Quick Menu repaint -- every D-pad press, held or not -- ran a full
; enumeration where it used to read a cache. That is a regression the shared
; version introduced, not a difference between the products.
;
; Keyed by variant, because the includeHidden inventory is a different list and
; sharing one slot would serve the wrong one.
SharedWindowInventoryGet(maxAgeMs := 1000, includeHidden := false) {
    static cached := Map()
    static stamped := Map()
    key := includeHidden ? "hidden" : "visible"
    if (maxAgeMs <= 0 || !stamped.Has(key)
        || A_TickCount - stamped[key] > maxAgeMs) {
        cached[key] := SharedWindowInventoryBuild(includeHidden)
        stamped[key] := A_TickCount
    }
    return cached[key]
}

; The View/Back button's own press, tracked apart from its use as a modifier.
;
; In SteamShell-Shared.ahk rather than Common because it calls ViewButtonReleased,
; which is the seam each product answers for itself -- Steam's menu here, Xbox
; FSE's there.
;
; THE MODIFIER RULE IS THE WHOLE OF IT. View is both a button with an action and
; the modifier every mapping is held with, so any other input during the hold
; marks the press as a modifier use and drops its own action on release. "Hold
; View, press A" fires the A mapping and nothing else.
;
; Returns whether View is physically down, which both callers need for their own
; gating; the tracking state is theirs, by reference, because it lives across
; ticks.
ControllerTrackViewButton(buttons, lt, rt, lx, ly, rx, ry, now,
        &wasDown, &pressTick, &usedAsModifier) {
    isDown := (buttons & 0x0020) != 0
    if isDown {
        if !wasDown {
            wasDown := true
            pressTick := now
            usedAsModifier := false
        }
        if ((buttons & ~0x0020) || lt > 30 || rt > 30
            || lx != 0 || ly != 0 || rx != 0 || ry != 0)
            usedAsModifier := true
    } else if wasDown {
        wasDown := false
        ViewButtonReleased(now - pressTick, usedAsModifier)
        usedAsModifier := false
    }
    return isDown
}

; One tick of controller MAPPING, once the product has decided the mappings are
; live: stick to cursor, stick to wheel, then Short/Long for every button and
; both triggers, then the D-pad and Guide.
;
; ITEM G, THE HALF THAT WAS SAFE TO MOVE. The two poll loops are ~330 lines each
; and their HEADS are genuinely two programs -- the shell gates on the controller
; test, the settings editor, two recovery dialogs and an elevated foreground; the
; companion gates on CompanionDisabled and its own fresh-baseline path. Their
; TAILS, from "the modifier is held, so mappings apply" to the end, were the same
; routine written twice, differing only in local names, comma-chained assignments
; against braces, and two things that were not cosmetic. Both of those are
; resolved toward the shell's version, which was the more careful:
;
;   ADOPTING BUTTONS ALREADY HELD when the modifier goes down is guarded on
;   `!downTick[name]` here. The companion overwrote unconditionally, so a hold
;   already being timed restarted its clock at the moment View was pressed.
;
;   THE TRIGGERS ALSO CLEAR longFired when they are adopted. The companion set
;   downTick and the down-flag but left longFired alone, so a trigger that had
;   fired a Long in an earlier hold could be adopted with the flag still set and
;   would not fire again.
;
; NEITHER HAS BEEN RUN ON HARDWARE. They are small, they are in the direction of
; the more careful implementation, and they are exactly the kind of change that
; shows up as "that button sometimes does nothing" rather than as a crash.
;
; modifierWasDown and lastScroll are the caller's statics, by reference: they
; live across ticks and each product owns its own.
ControllerPollFrame(buttons, pressed, released, lt, rt, rx, ry, ly, now,
        buttonDefinitions, downTick, longFired, triggerDown,
        &modifierWasDown, &lastScroll) {
    global ControllerMouseSpeed, ControllerMouseFastMultiplier
    global ControllerScrollIntervalMs, ControllerScrollStep, ControllerChordHoldMs

    ; If the modifier was just pressed, adopt any button already held so that
    ; releasing it still triggers its Short.
    if !modifierWasDown {
        for definition in buttonDefinitions {
            name := definition[1]
            mask := definition[2]
            if ((buttons & mask) && !downTick[name]) {
                downTick[name] := now
                longFired[name] := false
            }
        }
        if ((lt > 30) && !downTick["LT"]) {
            downTick["LT"] := now
            longFired["LT"] := false
            triggerDown["LT"] := true
        }
        if ((rt > 30) && !downTick["RT"]) {
            downTick["RT"] := now
            longFired["RT"] := false
            triggerDown["RT"] := true
        }
    }
    modifierWasDown := true

    ; Right stick to cursor. RT is the fast modifier, and the speed is a
    ; velocity: ApplyControllerMouseMove scales it by measured elapsed time.
    ApplyControllerMouseMove(rx, ry,
        rt > 30 ? Round(ControllerMouseSpeed * ControllerMouseFastMultiplier)
                : ControllerMouseSpeed)

    ; Left stick Y to the wheel, rate-limited: a wheel notch is a discrete
    ; event and the poll runs twenty times a second.
    if (ly != 0 && now - lastScroll >= ControllerScrollIntervalMs) {
        lastScroll := now
        ApplyControllerMouseScroll(ly, ControllerScrollStep)
    }

    for definition in buttonDefinitions {
        name := definition[1]
        mask := definition[2]
        ; A binding that HOLDS a mouse button is press-and-hold, so it can drag.
        ; Down on the press edge, up on the release, and no Short/Long timing.
        if ControllerBindingHoldsMouseButton(GetBindingValue(name ".Short")) {
            if (pressed & mask)
                HoldControllerMouseButton("LButton")
            if (released & mask)
                ReleaseControllerMouseButtons()
            downTick[name] := 0
            longFired[name] := false
            continue
        }
        if (pressed & mask) {
            downTick[name] := now
            longFired[name] := false
        }
        ; Long fires while still held, once the threshold passes -- not on
        ; release, so the user gets the action at the moment it is earned.
        if ((buttons & mask) && !longFired[name] && downTick[name]
            && (now - downTick[name]) >= ControllerChordHoldMs) {
            if HasLongBinding(name) {
                longFired[name] := true
                ExecuteControllerBinding(name ".Long")
            }
        }
        if ((released & mask) && downTick[name]) {
            if (!longFired[name])
                ExecuteControllerBinding(name ".Short")
            downTick[name] := 0
            longFired[name] := false
        }
    }

    ; The triggers are analogue, so their edges are derived from a threshold
    ; rather than read from a button word.
    for _, triggerName in ["LT", "RT"] {
        isDown := (triggerName = "LT" ? lt : rt) > 30
        pressedEdge := (isDown && !triggerDown[triggerName])
        releasedEdge := (!isDown && triggerDown[triggerName])
        triggerDown[triggerName] := isDown
        if ControllerBindingHoldsMouseButton(GetBindingValue(triggerName ".Short")) {
            if (pressedEdge)
                HoldControllerMouseButton("LButton")
            if (releasedEdge)
                ReleaseControllerMouseButtons()
            downTick[triggerName] := 0
            longFired[triggerName] := false
            continue
        }
        if (pressedEdge) {
            downTick[triggerName] := now
            longFired[triggerName] := false
        }
        if (isDown && !longFired[triggerName] && downTick[triggerName]
            && (now - downTick[triggerName]) >= ControllerChordHoldMs) {
            if HasLongBinding(triggerName) {
                longFired[triggerName] := true
                ExecuteControllerBinding(triggerName ".Long")
            }
        }
        if (releasedEdge && downTick[triggerName]) {
            if (!longFired[triggerName])
                ExecuteControllerBinding(triggerName ".Short")
            downTick[triggerName] := 0
            longFired[triggerName] := false
        }
    }

    ; D-pad arrows, one shot per press. Not bindable: they are navigation, and
    ; every surface either product puts on screen expects them to move a
    ; selection.
    if (pressed & 0x0001)
        try SendInput("{Up}")
    if (pressed & 0x0002)
        try SendInput("{Down}")
    if (pressed & 0x0004)
        try SendInput("{Left}")
    if (pressed & 0x0008)
        try SendInput("{Right}")

    ; Guide, where the pad reports it at all, maps to Y's Short.
    if (pressed & 0x0400)
        ExecuteControllerBinding("Y.Short")
}

; Score an inventory and return the game candidates, best first.
;
; ONE SCORER FOR BOTH PRODUCTS, which the earlier passes had already made almost
; true without finishing it. Every step this takes was shared already --
; GameShapeFactsForWindow, GameWindowShapeVerdict, GameWindowCpuVerdict,
; SortCandidatesByScoreAreaDesc, GetActiveAudioPidPeaksCached, and since the CPU
; sampler moved, that too. What was left duplicated was the loop holding them in
; order, and the two copies of it agreed on every step.
;
; They even agreed on the audio bonus by accident: the shell added the global
; ScoreAudioActive and the companion added weights["audioActive"], which is the
; same number, because that is the key the shell's own weights table fills from
; that global.
;
; THE FILTER IS A CALLBACK, and that is deliberate rather than lazy. The two
; products exclude genuinely different things -- the shell drops desktop and
; Steam windows, minimized surfaces that are not legacy games, and the on-screen
; keyboard; the companion drops its protected and launcher process lists -- and
; folding either set into the other would change what each product detects as a
; game. Only "never our own window" is common enough to live here.
;
; REJECTS ARE COLLECTED AS FACTS, not formatted. The shell writes them into its
; diagnostic score table and the companion has no such table, so the caller
; formats. rejectMinArea of 0 means do not collect at all, which is the
; companion's case and the shell's whenever diagnostic logging is off.
SharedScoreGameCandidates(inventory, weights, sampleCpu, skip,
        audioEnabled, audioThreshold, rejectMinArea := 0) {
    candidates := []
    rejects := []
    audioMap := 0
    for _, item in inventory {
        ; Never a game, in either product, and the one exclusion both agreed on.
        if item["scriptOwned"]
            continue
        if (skip && skip(item))
            continue

        minimizedLegacy := WindowEngineIsMinimizedLegacyGameSurface(item)
        shapeVerdict := GameWindowShapeVerdict(
            GameShapeFactsForWindow(item, minimizedLegacy), weights)
        nearFS := shapeVerdict["nearFS"]
        if !shapeVerdict["accepted"] {
            if (rejectMinArea > 0 && item["area"] >= rejectMinArea) {
                rejects.Push(Map("item", item, "stage", "shape",
                    "score", 0, "cpu", 0.0, "cpuKnown", false,
                    "nearFS", nearFS, "reason", "TOO_SMALL"))
            }
            continue
        }

        ; A pid of 0 cannot be sampled; the sampler answers "unknown" for it
        ; anyway, and asking is a wasted OpenProcess on every pass.
        score := shapeVerdict["score"]
        cpu := 0.0
        cpuKnown := false
        if item["pid"] {
            sample := sampleCpu(item["pid"])
            if IsObject(sample) {
                cpu := sample["usage"]
                cpuKnown := sample["known"]
            }
        }
        cpuVerdict := GameWindowCpuVerdict(score, cpu, cpuKnown, weights)
        score := cpuVerdict["score"]
        if !cpuVerdict["accepted"] {
            if (rejectMinArea > 0 && item["area"] >= rejectMinArea) {
                rejects.Push(Map("item", item, "stage", "cpu",
                    "score", score, "cpu", cpu, "cpuKnown", cpuKnown,
                    "nearFS", nearFS, "reason", cpuVerdict["reject"]))
            }
            continue
        }

        ; The audio map is built at most once per pass, and only if something
        ; got this far -- enumerating audio sessions is not free.
        audioActive := false
        if (audioEnabled && item["pid"]) {
            if !IsObject(audioMap)
                audioMap := GetActiveAudioPidPeaksCached()
            if (audioMap.Has(item["pid"]) && audioMap[item["pid"]] > audioThreshold) {
                score += weights["audioActive"]
                audioActive := true
            }
        }

        candidate := Map()
        for key, value in item
            candidate[key] := value
        candidate["nearFS"] := nearFS
        candidate["cpu"] := cpu
        candidate["cpuKnown"] := cpuKnown
        candidate["audio"] := audioActive
        candidate["score"] := score
        candidates.Push(candidate)
    }
    if (candidates.Length > 1)
        SortCandidatesByScoreAreaDesc(candidates)
    return Map("candidates", candidates, "rejects", rejects)
}

; The windows the Task Switcher offers, for both products.
;
; IT EXISTED TWICE, under names sharing no word -- GetTaskSwitcherWindows in the
; shell against GetSwitchableWindows in the companion, with
; SelectTaskSwitcherWindow / RequestCloseTaskSwitcherWindow against
; ActivateSwitchableWindow / CloseSwitchableWindow around them. Same Quick Menu
; row, same page:TASKS, same question. The fingerprint gate compares functions
; DEFINED IN BOTH TREES UNDER THE SAME NAME, so it could not see the pair, and a
; grep for the shell's identifier reported the feature missing from the companion
; entirely -- which is how a whole architectural justification once got built on
; top of an absence that was really a naming difference.
;
; NEITHER FILTER WAS ADOPTED WHOLESALE, because each carried something the other
; lacked.
;
; From the companion: STEAM IS RESOLVED FIRST and waives the gates below it.
; Steam Big Picture vanished from the switcher under Xbox FSE, and there was
; already a tool-window exception for it -- but it sat at the END of the chain
; and three earlier gates rejected Steam before it was reached. Windows cloaks
; Steam while Xbox FSE owns the screen, which is exactly when the user wants to
; switch to it; a cloaked window frequently reports no title; and frequently no
; usable size either. Losing that re-breaks a bug somebody spent real time
; finding.
;
; From the shell: the legacy-surface waiver. An older DirectX game can publish an
; untitled, tool-window-styled or minimized render surface, and
; WindowEngineIsLegacyApplicationSurface is what tells one of those from an
; overlay. The companion had no equivalent and simply dropped them.
;
; THE SHELL GAINS THE CLOAKING WAIVER by sharing this, and that is a fix rather
; than a side effect. Windows cloaks windows for reasons beyond Xbox FSE, so the
; shell had the same latent bug and only triggered it less often. It is kept
; narrow -- Steam only -- because relaxing it generally would bring back every
; virtual desktop's worth of hidden windows.
;
; maxAgeMs SEPARATES THE LIST FROM THE COUNT. The list a user is about to act on
; is enumerated fresh, which is the default; the number in the Quick Menu's
; "tasks" row is allowed to be a second old, because that row is re-evaluated on
; every repaint and enumerating the desktop per D-pad press is what the shell's
; old 1500 ms snapshot cache existed to avoid.
;
; It cannot read WindowEngineGetFreshSnapshot's cache instead: that one drops
; cloaked windows on the way in, which is precisely the case the Steam waiver
; below exists for.
SharedTaskSwitcherWindows(maxAgeMs := 0) {
    windows := []
    for _, item in SharedWindowInventoryGet(maxAgeMs, true) {
        if (item["scriptOwned"] || item["desktop"])
            continue
        ; The Xbox game bar's host surface. Never a thing to switch to, and it
        ; is not one of the four shell classes.
        if (item["classLower"] = "windowsdashboard")
            continue
        if !item["visible"]
            continue

        steam := item["steam"]
        legacy := WindowEngineIsLegacyApplicationSurface(item, true)
        ; Deliberately Steam only. A legacy game surface that is cloaked is not
        ; on screen for any reason worth offering.
        if (item["cloaked"] && !steam)
            continue
        if (item["title"] = "" && !steam && !legacy)
            continue
        if (item["toolWindow"] && !steam && !legacy)
            continue
        ; A minimized legacy surface reports off-screen geometry, so the size
        ; gate has to let it through or an exclusive-fullscreen game that
        ; minimized itself can never be restored.
        if ((item["w"] < 120 || item["h"] < 80)
            && !steam && !(legacy && item["minMax"] = -1))
            continue

        ; A cloaked Steam window reports no title, and an untitled legacy surface
        ; has none to report. Either way the row gets something readable rather
        ; than a blank entry.
        displayTitle := item["title"]
        if (displayTitle = "") {
            displayTitle := steam
                ? item["proc"] " (Steam)"
                : item["proc"] " (legacy fullscreen window)"
        }
        windows.Push(Map(
            "hwnd", item["hwnd"],
            "title", displayTitle,
            "exe", item["proc"],
            "pid", item["pid"],
            "legacy", legacy))
    }
    return windows
}

SettingsEditorRepaint() {
    global SettingsGui
    if !IsSet(SettingsGui) || !IsObject(SettingsGui)
        return
    ; RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW
    try DllCall("User32\RedrawWindow"
        , "Ptr", SettingsGui.Hwnd
        , "Ptr", 0
        , "Ptr", 0
        , "UInt", 0x0185
        , "Int")
}

SettingsEditorSetRedraw(enabled) {
    global SettingsGui
    if !IsSet(SettingsGui) || !IsObject(SettingsGui)
        return
    try DllCall("User32\SendMessageW"
        , "Ptr", SettingsGui.Hwnd
        , "UInt", 0x000B ; WM_SETREDRAW
        , "Ptr", enabled ? 1 : 0
        , "Ptr", 0
        , "Ptr")
}

SettingsEditorGetScrollTrackPosition() {
    scrollBar := ProductSettingsScrollBar()
    if !IsObject(scrollBar)
        return 0
    scrollInfo := Buffer(28, 0)
    NumPut("UInt", 28, scrollInfo, 0)
    NumPut("UInt", 0x10, scrollInfo, 4) ; SIF_TRACKPOS
    try {
        if DllCall("User32\GetScrollInfo"
            , "Ptr", scrollBar.Hwnd
            , "Int", 2 ; SB_CTL
            , "Ptr", scrollInfo)
            return NumGet(scrollInfo, 24, "Int")
    }
    return 0
}

GetRtssMenuStatus() {
    global EnableRTSSIntegration, RtssPath, RtssUseDllIntegration
    if (!EnableRTSSIntegration)
        return "Setup Required"
    if ProcessExist("RTSS.exe") {
        if !RtssUseDllIntegration
            return "Running | Shortcuts"
        liveState := GetRtssGlobalState()
        if IsObject(liveState)
            return "Overlay " (liveState["overlay"] ? "On" : "Off")
                . " | Limiter " (liveState["limiter"] ? "On" : "Off")
        return "Running"
    }
    return ResolveRtssExecutablePath() != "" ? "RTSS Ready" : "RTSS Not Found"
}

; ==============================================================================
; Quick Menu layout manager
; ==============================================================================
; Which rows the MAIN page shows and in what order, and the window that edits
; it. Shared because the two products offer the SAME eleven sections -- Audio,
; Display & HDR, RTSS, Steam Menu, Steam Quick Access, Task Switcher, Game Bar,
; Open Keyboard, Mouse Mode, Settings, System -- and there was never a reason
; for only one of them to be able to reorder or hide them.
;
; The companion had no layout manager at all, so its only way to hide the Audio
; and Display rows was a pair of Enable keys that duplicated what this window
; does everywhere else. Sharing this is what let those keys be retired rather
; than reimplemented a second time.
;
; Two seams keep it product-neutral, and both already existed:
;   ProductCenterGui      -- the shell centres on its target monitor, the
;                            companion on its own
;   SharedPersistSettings -- the shell stages through CommitIniChanges, the
;                            companion writes its portable INI directly
; ==============================================================================

GetDefaultQuickMenuOrder() {
    return ["audio", "display", "rtss", "steammenu", "steamquickaccess",
        "tasks", "gamebar", "keyboard", "mousemode", "settings", "system"]
}

ParseQuickMenuMainOrder(raw) {
    allowed := Map()
    for _, itemName in GetDefaultQuickMenuOrder()
        allowed[itemName] := true
    result := []
    seen := Map()
    for _, rawName in StrSplit(raw, "|") {
        itemName := StrLower(Trim(rawName))
        if (!allowed.Has(itemName) || seen.Has(itemName))
            continue
        seen[itemName] := true
        result.Push(itemName)
    }
    for _, itemName in GetDefaultQuickMenuOrder() {
        if !seen.Has(itemName)
            result.Push(itemName)
    }
    return result
}

QuickMenuLayoutLabel(itemName) {
    switch StrLower(itemName) {
        case "audio": return "Audio"
        case "display": return "Display & HDR"
        case "rtss": return "RTSS & Performance"
        case "steammenu": return "Steam Menu"
        case "steamquickaccess": return "Steam Quick Access"
        case "tasks": return "Task Switcher"
        case "gamebar": return "Game Bar"
        case "keyboard": return "Open Keyboard"
        case "mousemode": return "Mouse Mode"
        case "settings": return "Settings"
        case "system": return "System"
        default: return itemName
    }
}

RefreshQuickMenuLayoutManager() {
    global QuickMenuLayoutGui, QuickMenuMainOrder, QuickMenuHiddenItems
    if !IsSet(QuickMenuLayoutGui)
        return
    try {
        listView := QuickMenuLayoutGui["QuickMenuLayoutList"]
        listView.Delete()
        for _, itemName in QuickMenuMainOrder {
            required := itemName = "settings" || itemName = "system"
            visibility := required ? "Always" : (QuickMenuHiddenItems.Has(itemName) ? "Hidden" : "Visible")
            listView.Add("", QuickMenuLayoutLabel(itemName), visibility, itemName)
        }
        listView.ModifyCol(1, 275)
        listView.ModifyCol(2, 100)
        listView.ModifyCol(3, 0)
        if listView.GetCount()
            listView.Modify(1, "Select Focus")
    }
}

QuickMenuLayoutMove(direction, *) {
    global QuickMenuLayoutGui
    if !IsSet(QuickMenuLayoutGui)
        return
    listView := QuickMenuLayoutGui["QuickMenuLayoutList"]
    row := listView.GetNext(0, "F")
    if (!row)
        row := listView.GetNext()
    target := row + direction
    if (!row || target < 1 || target > listView.GetCount())
        return
    first := [listView.GetText(row, 1), listView.GetText(row, 2), listView.GetText(row, 3)]
    second := [listView.GetText(target, 1), listView.GetText(target, 2), listView.GetText(target, 3)]
    listView.Modify(row, "", second*)
    listView.Modify(target, "Select Focus Vis", first*)
}

QuickMenuLayoutToggle(*) {
    global QuickMenuLayoutGui
    if !IsSet(QuickMenuLayoutGui)
        return
    listView := QuickMenuLayoutGui["QuickMenuLayoutList"]
    row := listView.GetNext(0, "F")
    if (!row)
        row := listView.GetNext()
    if (!row)
        return
    itemName := listView.GetText(row, 3)
    if (itemName = "settings" || itemName = "system") {
        QuickMenuLayoutGui["QuickMenuLayoutStatus"].Text :=
            "Settings and System remain visible as recovery paths."
        return
    }
    current := listView.GetText(row, 2)
    listView.Modify(row, "", listView.GetText(row, 1),
        current = "Hidden" ? "Visible" : "Hidden", itemName)
}

QuickMenuLayoutRestoreDefault(*) {
    global QuickMenuLayoutGui
    if !IsSet(QuickMenuLayoutGui)
        return
    listView := QuickMenuLayoutGui["QuickMenuLayoutList"]
    listView.Delete()
    for _, itemName in GetDefaultQuickMenuOrder()
        listView.Add("", QuickMenuLayoutLabel(itemName),
            itemName = "settings" || itemName = "system" ? "Always" : "Visible", itemName)
    listView.Modify(1, "Select Focus")
    QuickMenuLayoutGui["QuickMenuLayoutStatus"].Text :=
        "Default order restored in the editor. Choose Save Layout to apply it."
}

QuickMenuLayoutSave(*) {
    global QuickMenuLayoutGui, QuickMenuMainOrderRaw, QuickMenuHiddenItemsRaw
    global QuickMenuMainOrder, QuickMenuHiddenItems, QuickMenuVisible
    if !IsSet(QuickMenuLayoutGui)
        return
    listView := QuickMenuLayoutGui["QuickMenuLayoutList"]
    order := []
    hidden := []
    Loop listView.GetCount() {
        itemName := listView.GetText(A_Index, 3)
        order.Push(itemName)
        if (listView.GetText(A_Index, 2) = "Hidden")
            hidden.Push(itemName)
    }
    QuickMenuMainOrderRaw := JoinWith(order, "|")
    QuickMenuHiddenItemsRaw := JoinWith(hidden, "|")
    if !SharedPersistSettings([
        Map("section", "QuickMenu", "key", "MainOrder", "value", QuickMenuMainOrderRaw),
        Map("section", "QuickMenu", "key", "HiddenItems", "value", QuickMenuHiddenItemsRaw)
    ]) {
        QuickMenuLayoutGui["QuickMenuLayoutStatus"].Text := "The layout could not be saved."
        return
    }
    QuickMenuMainOrder := ParseQuickMenuMainOrder(QuickMenuMainOrderRaw)
    QuickMenuHiddenItems := Map()
    for _, itemName in hidden
        QuickMenuHiddenItems[itemName] := true
    QuickMenuLayoutGui["QuickMenuLayoutStatus"].Text := "Quick Menu layout saved and applied."
    if QuickMenuVisible
        QuickMenuBuildGui()
}

ShowQuickMenuLayoutManager(*) {
    global QuickMenuLayoutGui
    if !IsSet(QuickMenuLayoutGui) {
        QuickMenuLayoutGui := Gui("+AlwaysOnTop +ToolWindow -Resize", "Quick Menu Layout")
        QuickMenuLayoutGui.SetFont("s10", "Segoe UI")
        title := QuickMenuLayoutGui.AddText("xm ym w590 h30", "Quick Menu Layout")
        title.SetFont("s17 Bold", "Segoe UI")
        QuickMenuLayoutGui.AddText(
            "xm y+2 w590 h38 +Wrap",
            "Reorder the main menu and hide rows you do not use. Settings and System always remain available.")
        QuickMenuLayoutGui.AddListView(
            "xm y+8 w590 r10 -Multi vQuickMenuLayoutList", ["Section", "Visibility", "Key"])
        upButton := QuickMenuLayoutGui.AddButton("xm y+8 w105 h32", "Move Up")
        upButton.OnEvent("Click", QuickMenuLayoutMove.Bind(-1))
        downButton := QuickMenuLayoutGui.AddButton("x+8 yp w105 h32", "Move Down")
        downButton.OnEvent("Click", QuickMenuLayoutMove.Bind(1))
        toggleButton := QuickMenuLayoutGui.AddButton("x+8 yp w125 h32", "Show / Hide")
        toggleButton.OnEvent("Click", QuickMenuLayoutToggle)
        defaultButton := QuickMenuLayoutGui.AddButton("x+8 yp w125 h32", "Restore Default")
        defaultButton.OnEvent("Click", QuickMenuLayoutRestoreDefault)
        saveButton := QuickMenuLayoutGui.AddButton("x+8 yp w105 h32", "Save Layout")
        saveButton.OnEvent("Click", QuickMenuLayoutSave)
        QuickMenuLayoutGui.AddText("xm y+8 w460 h24 vQuickMenuLayoutStatus", "")
        closeButton := QuickMenuLayoutGui.AddButton("x+8 yp-5 w105 h30", "Close")
        closeButton.OnEvent("Click", (*) => QuickMenuLayoutGui.Hide())
        QuickMenuLayoutGui.OnEvent("Close", (*) => QuickMenuLayoutGui.Hide())
        QuickMenuLayoutGui.OnEvent("Escape", (*) => QuickMenuLayoutGui.Hide())
    }
    QuickMenuLayoutGui.Show()
    ProductCenterGui(QuickMenuLayoutGui)
    RefreshQuickMenuLayoutManager()
}

; Which setting each plain on/off Quick Menu row writes. Data, not code.
;
; These eleven ids used to appear twice in standalone as near-identical `case`
; bodies -- once in the value resolver returning "ON"/"OFF", once in the toggle
; writing the INI -- so adding a switch meant remembering two places, and the
; ids were baked into two product-specific switches that shared code could not
; enter. As a table the rows are the same shape for both products, and the only
; thing left that a shared caller cannot do is read the live global by name,
; which is what ProductSettingBool exists for.
;
; Deliberately only the rows whose value really is a plain "ON"/"OFF". The ones
; that read "ON  *  NEXT BOOT", "PAUSED"/"ACTIVE" or cycle through named modes
; keep their own cases: their text is per-row vocabulary, not a boolean with a
; skin on it, and folding them in here would mean encoding label text as data
; for no gain.
QuickMenuToggleTable() {
    static table := Map(
        ; Unlike the taskbar toggle this applies at once, so it stays usable
        ; as an escape hatch if the backdrop ever misbehaves on a given machine.
        "qBlackout", Map("section", "Features", "key", "EnableDesktopBlackout"),
        "qControllerMouse", Map("section", "Controller", "key", "EnableControllerMouseMode"),
        "qAutoHideCursor", Map("section", "Features", "key", "EnableAutoHideCursor"),
        "qParkBoot", Map("section", "Features", "key", "EnableMouseParkOnBoot"),
        "qParkFocus", Map("section", "Features", "key", "EnableMouseParkOnFocusChange"),
        "qSteamRefocus", Map("section", "Features", "key", "EnableSteamRefocusMode"),
        "qGameAssist", Map("section", "Features", "key", "EnableGameForegroundAssist"),
        "qAlwaysFocus", Map("section", "Features", "key", "EnableAlwaysFocus"),
        "qRtssIntegration", Map("section", "RTSS", "key", "EnableIntegration"),
        ; The companion's own rows. They were a separate table under a separate
        ; name -- section, key, label and live value returned together from one
        ; `switch` -- which is the same routine this is, so neither the
        ; fingerprint gate nor DIVERGENT_FUNCTIONS.txt could see the pair.
        ;
        ; Only the plain booleans are here. qPersistentMouse is not, in either
        ; product: turning it on has to turn the controller-mouse master on with
        ; it, and a row that writes two keys is not a row this table describes.
        "gameFocus", Map("section", "Assist", "key", "EnableGameFocusLite"),
        "steamAssist", Map("section", "Assist", "key", "EnableSteamAssistLite"),
        "launcherCleanup", Map("section", "Assist", "key", "EnableLauncherCleanupLite"),
        "shellOverlay", Map("section", "Assist", "key", "SuspendOnShellOverlay"),
        "viewActions", Map("section", "Steam", "key", "EnableViewButtonActions"),
        "viewTap", Map("section", "Steam", "key", "EnableViewTapAction"),
        "viewHold", Map("section", "Steam", "key", "EnableViewHoldAction"))
    return table
}

; The builtin controller actions both products perform identically.
;
; Twelve of the sixteen. What is left is not refactoring residue: the companion
; has TaskView, WindowsDesktop and Settings, the shell has its own Control
; Panel, and Explorer differs in HOW rather than whether -- which is the whole
; reason the action set stayed per-product until there was a table to hold it.
;
; SendChordSafe for anything Windows itself interprets; SendInput for a keystroke
; the focused window interprets.
;
; The rule used to be "SendInput for a single key, SendChordSafe for anything with
; a modifier", which put StartMenu on the wrong side of it. Win is a single key
; and it is also a SYSTEM activation: with Shift or Ctrl still physically down it
; is not the Start menu, and the key the user is holding does not have to be part
; of the binding to be down when the binding fires. Enter and Esc are the other
; case -- they go to whatever has focus, and Shift+Enter is what someone holding
; Shift is asking for, so releasing modifiers there would DISCARD intent rather
; than protect it.
;
; StartMenu was also the one action where this file and SteamShell-Helper.ahk
; disagreed. The helper answers the same action for an elevated foreground and
; had always used SendChordSafe, so the same button behaved differently depending
; on whether the window in front happened to be elevated -- a distinction no user
; can see or predict. Both paths now send it the same way.
;
; LeftClick and RightClick stay Click(): not keystrokes, no modifier state to
; inherit.
;
; Returns true when the action was handled.
ControllerBindingSharedAction(action) {
    switch action {
        case "LeftClick":
            try Click("Left")
        case "RightClick":
            try Click("Right")
        case "Enter":
            try SendInput("{Enter}")
        case "Esc":
            try SendInput("{Esc}")
        case "StartMenu":
            SendChordSafe("{LWin}")
        case "AltF4":
            SendChordSafe("!{F4}")
        case "WinG":
            SendChordSafe("#g")
        case "CtrlAltTab":
            SendChordSafe("^!{Tab}")
        case "TaskManager":
            SendChordSafe("^+{Esc}")
        case "TabTip":
            OpenTouchKeyboard()
        case "OSK":
            OpenOSK()
        case "QuickMenu":
            ToggleQuickMenu()
        default:
            return false
    }
    return true
}

; Run whatever a controller button is bound to.
;
; The parsing skeleton -- empty, Builtin:None, a Send: shortcut, a Builtin:
; action -- was duplicated in both trees and is the same in both. Only the
; action SET differed, so only the action set is asked per-product now.
;
; An unknown action is ignored rather than logged. Bindings are hand-editable
; and a typo should cost a button that does nothing, not a log line on every
; press of it.
ExecuteControllerBinding(key) {
    value := GetBindingValue(key)
    if (value = "" || value = "Builtin:None")
        return
    if (SubStr(value, 1, 5) = "Send:") {
        shortcut := SubStr(value, 6)
        if (shortcut != "")
            SendChordSafe(shortcut)
        return
    }
    if (SubStr(value, 1, 8) != "Builtin:")
        return
    action := SubStr(value, 9)
    if ControllerBindingSharedAction(action)
        return
    ProductControllerBindingAction(action)
}

; How many task-switcher rows fit on one page.
;
; Eight rather than "as many as the control pool holds". The pool is 14 and the
; companion used to fill it -- Loop Min(count, 13) -- which is not paging but
; truncation: a fourteenth window simply could not be reached, and nothing said
; so. Eight leaves room for Back and the two page rows on every page, so the
; count never depends on which page you are looking at.
QuickMenuTaskPageSize() {
    return 8
}

; The slice of QuickMenuTaskWindows the current page shows.
;
; Clamps the page as it reads it: windows close while the menu is open, so the
; page a user was on can stop existing between one repaint and the next.
QuickMenuTaskSlice(total, &firstIndex, &lastIndex, &pageCount) {
    global QuickMenuTaskPage
    pageSize := QuickMenuTaskPageSize()
    pageCount := Max(1, Ceil(total / pageSize))
    QuickMenuTaskPage := ClampInt(QuickMenuTaskPage, 1, pageCount)
    firstIndex := ((QuickMenuTaskPage - 1) * pageSize) + 1
    lastIndex := Min(total, firstIndex + pageSize - 1)
}

; Wraps at both ends, like the accent list: with two page rows on screen there
; is no affordance for "this one does nothing now", so a dead Next reads as a
; broken row rather than as the end of the list.
ChangeQuickMenuTaskPage(direction) {
    global QuickMenuTaskPage, QuickMenuTaskWindows, QuickMenuSelected
    pageCount := Max(1, Ceil(QuickMenuTaskWindows.Length / QuickMenuTaskPageSize()))
    QuickMenuTaskPage += direction
    if (QuickMenuTaskPage < 1)
        QuickMenuTaskPage := pageCount
    if (QuickMenuTaskPage > pageCount)
        QuickMenuTaskPage := 1
    QuickMenuSelected := 1
    QuickMenuBuildGui()
}

; The value column for the settings rows both products build.
;
; These read globals directly rather than through a seam because every one of
; them exists under the SAME NAME in both trees: they are one setting each, not
; two products' versions of an idea. The plain booleans go through
; ProductSettingBool, which is the one lookup shared code genuinely cannot do.
;
; Returns "" for an id it does not own, so each product falls through to its own
; rows -- the shell's qSplash and qTaskbar read globals the companion does not
; have, and naming them here would declare them into a tree that never assigns
; them.
QuickMenuSettingValueText(id) {
    global ControllerMouseSpeed, MouseHideDelay, MouseParkEdge
    global RtssOverlayControlMode, RtssFrameLimiterControlMode, RtssPresetFrameCap
    global EnablePersistentMouseMode
    if QuickMenuToggleTable().Has(id)
        return ProductSettingBool(id) ? "ON" : "OFF"
    switch id {
        case "qPersistentMouse":
            return EnablePersistentMouseMode ? "ON" : "OFF"
        case "qMouseSpeed":
            return ControllerMouseSpeed " PX/S"
        case "qMouseHideDelay":
            return MouseHideDelay = 0 ? "IMMEDIATE" : Format("{:.1f} SEC", MouseHideDelay / 1000)
        case "qParkEdge":
            return StrUpper(MouseParkEdge)
        case "qOverlayMode":
            return StrUpper(RtssOverlayControlMode)
        case "qLimiterMode":
            return StrUpper(RtssFrameLimiterControlMode)
        case "qFrameCap":
            return RtssPresetFrameCap > 0 ? RtssPresetFrameCap " FPS" : "NOT SET"
        case "qAccentColor":
            return QuickMenuAccentValueText()
    }
    return ""
}

; The three settings rows that flip between two named states rather than on and
; off. Not in QuickMenuToggleTable: that table's rows all write "true"/"false",
; and these write a word the value column shows back.
;
; Returns true when the id was handled.
QuickMenuCycleSharedSetting(id) {
    global MouseParkEdge, RtssOverlayControlMode, RtssFrameLimiterControlMode
    switch id {
        case "qParkEdge":
            return ProductApplyQuickMenuSetting("MousePark", "MouseParkEdge",
                MouseParkEdge = "right" ? "Left" : "Right")
        case "qOverlayMode":
            return ProductApplyQuickMenuSetting("RTSS", "OverlayControlMode",
                RtssOverlayControlMode = "toggle" ? "Separate" : "Toggle")
        case "qLimiterMode":
            return ProductApplyQuickMenuSetting("RTSS", "FrameLimiterControlMode",
                RtssFrameLimiterControlMode = "toggle" ? "Separate" : "Toggle")
    }
    return false
}

; Left/Right on a settings row that holds a number or a list position.
;
; Returns true when the id was handled.
QuickMenuAdjustSharedSetting(id, direction) {
    global ControllerMouseSpeed, MouseHideDelay, RtssPresetFrameCap
    global QuickMenuAccentName
    switch id {
        case "qAccentColor":
            ; Wraps at both ends. A color list has no meaningful first or last,
            ; and stopping at Teal would make the default feel like a dead end.
            names := QuickMenuAccentPresetNames()
            index := 1
            for candidateIndex, candidateName in names {
                if (StrLower(candidateName) = StrLower(QuickMenuAccentName)) {
                    index := candidateIndex
                    break
                }
            }
            index += direction
            if (index < 1)
                index := names.Length
            else if (index > names.Length)
                index := 1
            return ProductApplyQuickMenuSetting("QuickMenu", "AccentColor", names[index])
        case "qMouseSpeed":
            ; Step and bounds follow the setting's unit, which is now pixels per
            ; SECOND rather than pixels per poll tick. A step of 5 was about 5%
            ; of the old range; 200 is about the same proportion of the new one,
            ; so a press moves the slider by a comparable amount.
            return ProductApplyQuickMenuSetting("Controller", "ControllerMouseSpeed",
                ClampInt(ControllerMouseSpeed + (direction * 200), 200, 12000))
        case "qMouseHideDelay":
            ; Snap to the nearest listed value first. The setting accepts any
            ; number -- the full Settings window and a hand-edited INI can both
            ; produce one that is not on this list -- and stepping from wherever
            ; it happens to be would otherwise move by an unpredictable amount.
            choices := [0, 500, 1000, 2000, 3000, 5000, 10000]
            choiceIndex := 1
            smallestDistance := 0x7FFFFFFF
            for index, candidate in choices {
                distance := Abs(candidate - MouseHideDelay)
                if (distance < smallestDistance) {
                    smallestDistance := distance
                    choiceIndex := index
                }
            }
            choiceIndex := ClampInt(choiceIndex + direction, 1, choices.Length)
            return ProductApplyQuickMenuSetting("Timing", "MouseHideDelay",
                choices[choiceIndex])
        case "qFrameCap":
            return ProductApplyQuickMenuSetting("RTSS", "PresetFrameCap",
                ClampInt(RtssPresetFrameCap + direction, 0, 1000))
    }
    return false
}

; The Quick Menu actions both products implement identically.
;
; Fourteen of the thirty ids both trees handle had byte-identical bodies; these
; are those. The other sixteen are not refactoring decisions -- they differ in
; how each product notifies (ShowNotification against SetStatus), in what it
; calls its own settings window, and in real behaviour, like standalone
; launching Steam when steamMenu is chosen and Steam is not running. Those stay
; per-tree until somebody decides the product question underneath them.
;
; Every case here falls through to the caller's QuickMenuRefresh(), which is why
; this reports whether it handled the id rather than refreshing itself: gameBar
; returns early in both trees and deliberately is NOT in this list.
;
; Returns true when the id was handled.
QuickMenuActivateShared(id) {
    switch id {
        case "audioOutput":
            CycleDefaultAudioOutput(1)
        case "volume":
            QuickMenuAdjustSelected(1)
        case "hdr":
            ToggleQuickMenuHdrState()
        case "displayResolution":
            CycleDisplayResolution(1)
        case "displayRefresh":
            CycleDisplayFrequency(1)
        case "displayScale":
            CycleDisplayScale(1)
        case "displayApply":
            ApplyDisplaySelection()
        case "rtssOverlayState", "overlayToggle":
            ToggleRtssOverlay()
        case "limiterToggle":
            ToggleRtssFrameLimiter()
        case "rtssFrameLimitCustom":
            AdjustRtssCustomFrameCap(1)
        case "overlayOn":
            SetRtssOverlayState(true)
        case "overlayOff":
            SetRtssOverlayState(false)
        case "limiterOn":
            SetRtssFrameLimiterState(true)
        case "limiterOff":
            SetRtssFrameLimiterState(false)
        default:
            return false
    }
    return true
}

; The value column for a row, asked of the ROW rather than of its id.
;
; A row that declares itself a back row answers with the glyph directly, which
; is what let eight standalone ids stop sharing one `case` that existed purely
; to return it. The companion builds no row carrying "back", so that branch
; simply does not fire there and its back rows keep the empty value they had.
;
; QuickMenuValue itself stays per-product: it is the label map, and the two
; products genuinely word 19 of their 35 shared rows differently.
; The value column for one row.
;
; The two trees build rows differently -- the shell stores id and label and
; resolves the value later, the companion carries the value on the row -- and
; this asked ONLY the shell's way. Every id QuickMenuValue has no case for
; therefore rendered blank, which is every "toggle:" settings row the companion
; builds: the whole Quick Menu settings page showed labels and no values, and
; there is nothing about a blank value column that fails.
;
; So a row that states its value is believed, and a row that does not is asked.
;
; No arrows are added here. The shell wraps a value in them where IT decides to
; -- HDR, the display modes, the live RTSS state -- and leaves a plain ON or OFF
; bare. Adding them to every steppable row made a settings page read "< ON >"
; throughout, which is not what the shell does and not what anyone asked for.
QuickMenuRowValueText(row) {
    id := row["id"]
    ; By id as well as by field. The shell marks a back row with a "back" key on
    ; the row Map; the companion's MenuRow has no such field, so its back rows
    ; asked QuickMenuValue("back"), got nothing, and displayed no glyph at all --
    ; every page in the companion had a Back row with an empty value column where
    ; the shell shows the arrow.
    if (row.Has("back") || id = "back")
        return "‹"
    text := row.Has("value") && row["value"] != ""
        ? row["value"]
        : QuickMenuValue(id)
    if (text = "")
        return ""
    return text
}

QuickMenuRowIsInert(index) {
    global QuickMenuRows
    static inert := Map(
        "hdrUnavailable", true,
        "displayUnavailable", true,
        "displayScaleUnavailable", true,
        "tasksUnavailable", true,
        "rtssMissing", true,
        "rtssDisabled", true,
        ; Declared rather than assumed. This row reports that nothing has been
        ; scored yet, and selecting it has never done anything -- but standalone
        ; expressed that by having no case for it, which is indistinguishable
        ; from a case somebody deleted. The companion already said so out loud
        ; by giving it action "none".
        "gameScoreEmpty", true,
        ; Says why the current application cannot be added -- a Store app, or
        ; nothing in front. Selecting it does nothing on purpose, and saying so
        ; here is what tells that apart from a handler somebody deleted.
        "currentAppBlocked", true)
    if (index < 1 || index > QuickMenuRows.Length)
        return false
    return inert.Has(QuickMenuRows[index]["id"])
}

; The idle-cursor pass, on a timer in both products: track the pointer, re-show
; the cursor the moment it moves, hide it again once it has been still for
; MouseHideDelay.
;
; The two copies of this had an identical call sequence and differed in three
; things: a global spelled MouseHideDelayMs on one side, and two suppression
; gates asked at two different points. The name was drift and is now one name.
; The gates are real -- see MouseWatchDisabled and MouseWatchHoldsCursorVisible
; in each tree -- so they stayed per-product, asked from here at exactly the
; points their own copies asked them, which is what keeps this a consolidation
; rather than a cursor-behaviour change nobody tested on hardware.
MouseWatch() {
    global MouseHidden, LastMouseX, LastMouseY, LastMouseMoveTick, MouseHideDelay

    if MouseWatchDisabled()
        return

    MouseGetPos(&mx, &my)
    if (mx != LastMouseX || my != LastMouseY) {
        LastMouseX := mx
        LastMouseY := my
        LastMouseMoveTick := A_TickCount
        if MouseHidden {
            SystemCursor("Show")
            MouseHidden := false
        }
        return
    }

    if MouseWatchHoldsCursorVisible()
        return

    if (!MouseHidden && (A_TickCount - LastMouseMoveTick >= MouseHideDelay)) {
        SystemCursor("Hide")
        MouseHidden := true
    }
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

; THE ONLY PLACE EITHER PRODUCT CHANGES THE QUICK MENU'S PAGE.
;
; Three lines, and one of them is the whole feature: QuickMenuBuildGui composes
; the rows from the product's row builder, and nothing else does. The repaint
; routines -- QuickMenuRefresh in the shell, QuickMenuRender in the companion --
; redraw the rows that are ALREADY in QuickMenuRows, which is what makes them
; cheap and what makes them wrong here.
;
; Eleven sites spelled these three lines by hand, and four of them (all in the
; shell: Game Detection, Current Application, and the two Back To System rows)
; ended in a repaint. The page variable moved, the previous page's rows stayed on
; screen, and the row read as dead -- while the next keypress was dispatched
; against a page the user could not see. The companion had the same four lines
; correct, so there was nothing in a diff to notice.
;
; The point of this function is not that it is shorter. It is that "set the page
; and repaint" is now unspellable: there is no page assignment left outside this
; file for anyone to get wrong, and Assert-QuickMenuPageChangesRebuild fails the
; build if one comes back.
;
; ORDER TRAP, for anyone routing a new caller through this. BuildGui returns
; immediately when QuickMenuVisible is false, in BOTH trees. A caller that is
; opening the menu must set QuickMenuVisible before calling this, not after --
; the companion's ShowQuickMenu set the page first and the flag second, which
; was harmless only because its BuildGui call came after both.
QuickMenuGoToPage(page) {
    global QuickMenuPage, QuickMenuSelected
    QuickMenuPage := page
    QuickMenuSelected := 1
    QuickMenuBuildGui()
}

QuickMenuGoBack() {
    global QuickMenuPage
    if (QuickMenuPage = "MAIN") {
        HideQuickMenu()
        return
    }
    QuickMenuGoToPage(
        SubStr(QuickMenuPage, 1, 9) = "SETTINGS_" ? "SETTINGS" : "MAIN")
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

; ==============================================================================
; Game-detection snapshot
; ==============================================================================
; Called by each product's scorer at the point it already records the winner.
; The trees differ in which scorer that is -- WindowEngineEvaluateGame in the
; shell, XfeBestGameWindow in the companion -- and in nothing else, which is why
; only the call site is per-tree.
; ==============================================================================

CaptureGameCandidates(candidates) {
    global LastGameCandidates, GameScoreMaxRows
    LastGameCandidates := TrimGameCandidates(candidates, GameScoreMaxRows)
}

; The summary shown on the row that opens the page.
QuickMenuGameDetectionValue() {
    global LastBestCandidateProc, LastBestCandidateScore
    return LastBestCandidateProc != ""
        ? LastBestCandidateProc " (" LastBestCandidateScore ")"
        : "Nothing detected"
}

; Rows for the page: a back row, then one per candidate. Ids carry a colon, like
; the task and layout rows, because the list comes from whatever the last pass
; found rather than from a fixed set.
; ==============================================================================
; CURRENT APPLICATION
; ==============================================================================
; Add the application that was in front when the Quick Menu opened to one of the
; executable lists, without typing its name.
;
; WHY THIS WORKS HERE AND NOT IN THE SETTINGS WINDOW. The Settings editor cannot
; offer "the current application", because by the time it is open SETTINGS is the
; current application -- which is why the picker over there offers a HISTORY
; instead. The Quick Menu is the one surface that knows: both trees snapshot
; QuickMenuPreviousHwnd in ShowQuickMenu, before the menu takes the foreground.
; The two features are complements, not duplicates: this one names what you are
; looking at, the picker names what you closed five minutes ago.
;
; Everything below is shared. Each tree contributes only the row SHAPE -- the
; shell builds Map("id", ...), the companion builds MenuRow(...) -- exactly as
; the Game Detection page above already does, and the ids, labels, values,
; eligibility and the write are decided once, here.

; Where an application can be added, and who offers each destination.
;
; A table with a product tag, the same shape and the same rule as
; SettingsCategoryRows, so a destination one product does not have is DATA
; rather than a second code path. SettingsRowAppliesTo does the filtering for
; both.
;
; The two "protect from cleanup" rows are one destination under two spellings.
; The shell keeps its protected list at LauncherCleanup\ExcludeExeList and the
; companion at Assist\ProtectedProcesses; that is a real difference in where each
; product has always stored it, and inventing a third location to make this table
; shorter would break both products' existing settings files.
QuickMenuAppTargets() {
    static table := [
        Map("product", "both", "section", "Controller", "key", "AutoMouseExeList",
            "label", "Automatic Mouse"),
        Map("product", "standalone", "section", "AlwaysFocus", "key", "ExeList",
            "label", "Always In Focus"),
        Map("product", "standalone", "section", "LauncherCleanup", "key", "ExcludeExeList",
            "label", "Protect From Cleanup"),
        Map("product", "xfe", "section", "Assist", "key", "ProtectedProcesses",
            "label", "Protect From Cleanup"),
        Map("product", "standalone", "section", "Controller",
            "key", "DesktopAutoMouseExcludeExeList",
            "label", "Exclude From Desktop Mouse")]
    return table
}

QuickMenuAppTargetsFor(product) {
    targets := []
    for _, target in QuickMenuAppTargets() {
        if SettingsRowAppliesTo(target, product)
            targets.Push(target)
    }
    return targets
}

QuickMenuAppTargetIds(product) {
    ids := []
    for index, _ in QuickMenuAppTargetsFor(product)
        ids.Push("currentapp:" index)
    return ids
}

QuickMenuAppTargetFromId(id, product) {
    targets := QuickMenuAppTargetsFor(product)
    index := ToInt(SubStr(id, 12), 0)
    if (index < 1 || index > targets.Length)
        return 0
    return targets[index]
}

; The executable that was in front when the menu opened.
;
; From the snapshot both trees already take, not from a live read: by the time a
; row on this page is selected the Quick Menu itself has been the foreground for
; several seconds.
QuickMenuCurrentAppExe() {
    global QuickMenuPreviousHwnd
    if (!QuickMenuPreviousHwnd
        || !DllCall("User32\IsWindow", "Ptr", QuickMenuPreviousHwnd, "Int"))
        return ""
    exe := ""
    try exe := StrLower(WinGetProcessName("ahk_id " QuickMenuPreviousHwnd))
    return exe
}

; Why this application cannot be added, or "" when it can.
;
; THE STORE-APP CASE IS THE REASON THIS FUNCTION EXISTS. A packaged UWP
; application's visible window belongs to ApplicationFrameHost.exe, so the name
; behind it is not the name of the application -- it is the name of a host shared
; by Settings, Photos, Calculator, the Store and everything else of that shape.
; Writing it into one of these lists would silently match all of them.
;
; The recent-application picker avoids this by filtering the host out of its
; history. Here the user is pointing AT the window, so filtering would look like
; the feature being broken; it says so instead. Both refusals are the same
; decision, recorded in RecentAppsExcluded and here.
QuickMenuCurrentAppBlockedReason() {
    exe := QuickMenuCurrentAppExe()
    if (exe = "")
        return "No application was in front"
    if (exe = "applicationframehost.exe")
        return "Store app — cannot be added by name"
    if !RegExMatch(exe, "i)^[a-z0-9][a-z0-9_. -]*\.exe$")
        return "Unrecognised executable name"
    return ""
}

; What the System page's row shows: the application, or why there is nothing to
; offer. Selecting the row is pointless in the second case, and the row says so
; rather than opening a page of destinations that would all refuse.
QuickMenuCurrentAppValue() {
    reason := QuickMenuCurrentAppBlockedReason()
    return reason != "" ? reason : QuickMenuCurrentAppExe()
}

QuickMenuCurrentAppSelectable() {
    return QuickMenuCurrentAppBlockedReason() = ""
}

; A destination row's label, with whether the application is already on it.
;
; Read live rather than cached, so a second visit to the page after adding shows
; the result instead of inviting the same add again.
QuickMenuAppTargetLabel(id, product) {
    target := QuickMenuAppTargetFromId(id, product)
    if !IsObject(target)
        return ""
    exe := QuickMenuCurrentAppExe()
    if (exe != "" && SharedExeListContains(
        ReadText(target["section"], target["key"], ""), exe))
        return target["label"] " (already added)"
    return target["label"]
}

; Whether a pipe-separated executable list already names an executable.
;
; Case-insensitive on both sides, because these lists are hand-edited and the
; products lower-case them only when they build their lookup sets.
SharedExeListContains(rawList, exe) {
    exe := StrLower(Trim(exe))
    if (exe = "")
        return false
    for _, entry in StrSplit(rawList, "|") {
        if (StrLower(Trim(entry)) = exe)
            return true
    }
    return false
}

; Appends an executable to a pipe-separated list setting, through the product's
; own persistence.
;
; ProductApplyQuickMenuSetting is the seam every other Quick Menu write already
; uses, so this inherits the shell's staged-copy write and the companion's direct
; one without knowing which it got. Read-modify-write, because the seam takes a
; whole value.
SharedAppendExeToListSetting(section, key, exe) {
    current := Trim(ReadText(section, key, ""))
    if SharedExeListContains(current, exe)
        return true
    return ProductApplyQuickMenuSetting(
        section, key, current = "" ? exe : current "|" exe)
}

; Adds the current application to the destination a row names.
;
; Shared, and reached from both trees' activate switches through the
; "currentapp:" prefix, so neither tree spells the write, the duplicate check or
; the notification.
QuickMenuAddCurrentAppTo(id, product) {
    reason := QuickMenuCurrentAppBlockedReason()
    if (reason != "") {
        SharedNotify(reason, "Warning")
        return
    }
    target := QuickMenuAppTargetFromId(id, product)
    if !IsObject(target) {
        return
    }
    exe := QuickMenuCurrentAppExe()
    if SharedExeListContains(
        ReadText(target["section"], target["key"], ""), exe) {
        SharedNotify(exe " is already in " target["label"])
        return
    }
    if !SharedAppendExeToListSetting(target["section"], target["key"], exe) {
        LogLine("Quick Menu: could not add " exe " to " target["section"] "\\"
            . target["key"] ".", "Warning")
        SharedNotify("Could not save " target["label"], "Warning")
        return
    }
    LogLine("Quick Menu: added " exe " to " target["section"] "\\" target["key"] ".")
    SharedNotify(exe " added to " target["label"])
}

QuickMenuGameScoreIds() {
    global LastGameCandidates
    ids := []
    for index, _ in LastGameCandidates
        ids.Push("gamescore:" index)
    return ids
}

; Evidence text for a "gamescore:N" row id.
QuickMenuGameScoreValue(id) {
    global LastGameCandidates
    if (SubStr(id, 1, 10) != "gamescore:")
        return ""
    index := ToInt(SubStr(id, 11), 0)
    if (index < 1 || index > LastGameCandidates.Length)
        return ""
    return GameCandidateEvidenceText(LastGameCandidates[index])
}

QuickMenuGameScoreLabel(id) {
    global LastGameCandidates
    index := ToInt(SubStr(id, 11), 0)
    if (index < 1 || index > LastGameCandidates.Length)
        return ""
    return GameCandidateLabel(LastGameCandidates[index], index)
}

; ==============================================================================
; RawInput controller backend
; ==============================================================================
; Reads gamepads straight from the HID stack as WM_INPUT messages, decoding each
; report into the XINPUT_STATE-shaped buffer the rest of both programs already
; consumes -- so mappings, chords and the controller mouse are identical on
; every backend.
;
; This was the companion's, written because XInput and GameInput both read all
; zeros inside Xbox FSE. That is why it was BUILT, and it is not the limit of
; what it DOES: registration passes RIDEV_INPUTSINK, so reports arrive whether
; or not this program owns the foreground, and both the gamepad and joystick
; usages are registered because controllers vary in which one they report.
;
; Which makes it the answer to a problem the shell has and the companion does
; not. XInput covers Xbox-compatible pads and nothing else, so a controller that
; does not speak it left the SHELL with no input at all -- on a machine where
; there is no taskbar and no Start menu to fall back to, because the shell is
; what SteamShell replaced. The companion at least still had Xbox FSE.
;
; Backend selection stays per-product: it yields to XInput by itself whenever no
; reports are arriving, so a machine whose controller already worked keeps
; working exactly as before.

; ==============================================================================
; RawInput probe
; ==============================================================================
; Answers exactly one question: do controller HID reports reach this background
; process inside Xbox FSE?
;
; XInput and GameInput have been shown to report byte-identical state at every
; sample, including all-zero inside FSE, which means they share a layer and no
; choice between them can help. RawInput is a different mechanism: HID reports
; delivered as WM_INPUT messages straight from the HID stack, and RIDEV_INPUTSINK
; explicitly requests delivery while the process is NOT in the foreground.
;
; This began as a diagnostic probe. The registration and WM_INPUT handler now
; serve three consumers: optional raw-byte logging, the normal RawInput decoder,
; and the controller learner. Logging remains independently switchable.
RawInputProbeStart() {
    global EnableRawInputProbe, RawInputProbeActive, ControllerBackend
    static RIDEV_INPUTSINK := 0x00000100
    static USAGE_PAGE_GENERIC := 0x01
    static USAGE_GAMEPAD := 0x05
    static USAGE_JOYSTICK := 0x04

    if RawInputProbeActive
        return false
    ; Register whenever RawInput is either the input source or being logged.
    backend := StrLower(ControllerBackend)
    needed := EnableRawInputProbe || backend = "rawinput" || backend = "auto"
    ; Say so explicitly when not needed. Returning in silence made a setting that
    ; never reached the application look identical to a probe that ran and found
    ; nothing, which cost a full test cycle.
    if !needed {
        LogLine("RawInput: not registered (backend=" backend
            . ", probe=" (EnableRawInputProbe ? "on" : "off") ").")
        return false
    }
    hwnd := A_ScriptHwnd
    if !hwnd {
        LogLine("RawInput probe: no script window available.", "Warning")
        return false
    }

    ; Two RAWINPUTDEVICE entries, 16 bytes each on x64. Gamepad and joystick are
    ; both registered because controllers vary in which usage they report.
    devices := Buffer(32, 0)
    NumPut("UShort", USAGE_PAGE_GENERIC, devices, 0)
    NumPut("UShort", USAGE_GAMEPAD, devices, 2)
    NumPut("UInt", RIDEV_INPUTSINK, devices, 4)
    NumPut("Ptr", hwnd, devices, 8)
    NumPut("UShort", USAGE_PAGE_GENERIC, devices, 16)
    NumPut("UShort", USAGE_JOYSTICK, devices, 18)
    NumPut("UInt", RIDEV_INPUTSINK, devices, 20)
    NumPut("Ptr", hwnd, devices, 24)

    ok := false
    try ok := DllCall("RegisterRawInputDevices", "Ptr", devices, "UInt", 2,
        "UInt", 16, "Int") != 0
    if !ok {
        LogLine("RawInput probe: RegisterRawInputDevices failed (err "
            . A_LastError ").", "Warning")
        return false
    }
    OnMessage(0x00FF, RawInputProbeMessage)
    RawInputProbeActive := true
    LogLine("RawInput: registered for background gamepad/joystick reports.")
    RawInputProbeEnumerate()
    return true
}


; Forgets the locked device and clears the cached report.
;
; Called on a deliberate power transition rather than on every device change: it
; also clears RawInputLastReportTick, which the automatic backend selection reads,
; so resetting it casually would make `auto` flip to XInput mid-session.
RawInputResetDeviceLock(reason) {
    global RawInputDevice, RawInputLastReportTick, RawInputState
    if (!RawInputDevice && !RawInputLastReportTick)
        return
    LogLine("RawInput: releasing device lock 0x" Format("{:X}", RawInputDevice)
        . " (" reason "). The next matching report re-locks.")
    RawInputDevice := 0
    RawInputLastReportTick := 0
    NumPut("UInt", 0, RawInputState, 0)
    NumPut("UInt", 0, RawInputState, 4)
    NumPut("UInt", 0, RawInputState, 8)
    NumPut("UInt", 0, RawInputState, 12)
}


; Re-asserts the RawInput registration after a resume.
;
; The registration is per-window and should survive a suspend, since the window
; does. Re-asserting it is cheap and removes the possibility that it did not,
; which is the one failure mode device adoption cannot recover from: adoption
; needs a WM_INPUT to react to, and there is nothing to adopt if registration is
; gone.
RawInputReregister() {
    global RawInputProbeActive
    RawInputProbeActive := false
    if RawInputProbeStart()
        SetTimer(RawInputResumeVerify, -10000)
}


; Sleep and resume.
;
; The controller is re-enumerated across a suspend and returns with a new device
; handle, so the decoder is told to forget the one it locked onto before the
; machine slept.
;
; Shared, and it was companion-only until now. The shell registered RawInput once
; from its auto-execute section and had NO resume path at all -- no power handler,
; no lock reset, no re-registration, not one caller of either recovery function.
; It survived on RawInputClaimDevice's handover, which re-locks on the first
; report from a re-enumerated device and genuinely does cover the stale handle.
; What handover cannot cover is a registration that did not come back, which is
; the failure RawInputResumeVerify was written to name.
;
; Nothing in here is per-product: it drives three functions that were already in
; this file. Copying it into the shell would have created a divergent pair the day
; it was written, so it moves instead.
PowerBroadcastMessage(wParam, lParam, msg, hwnd) {
    static PBT_APMSUSPEND := 0x04
    static PBT_APMRESUMESUSPEND := 0x07
    static PBT_APMRESUMEAUTOMATIC := 0x12
    if (wParam = PBT_APMSUSPEND) {
        LogLine("Power: system suspending.")
        RawInputResetDeviceLock("system suspending")
        return true
    }
    if (wParam = PBT_APMRESUMESUSPEND || wParam = PBT_APMRESUMEAUTOMATIC) {
        LogLine("Power: resumed from sleep; re-arming controller input.")
        RawInputResetDeviceLock("system resumed")
        ; A resume is a hardware change by any reasonable definition, so the
        ; XInput sweep should not sit out a backoff interval measured for a
        ; machine where nothing moved.
        XInputScanGate(true)
        ; XInput re-resolves its own slot on the next poll, so only RawInput needs
        ; help here. Delayed, because the HID stack is still re-enumerating at the
        ; moment the resume notification arrives.
        SetTimer(RawInputReregister, -2500)
        return true
    }
    return true
}


; Forces controller input to be re-acquired: RawInput forgets its device handle
; and re-registers, and XInput re-resolves its slot on the next poll.
;
; Exposed manually as well as automatically because it is the fastest way to
; confirm what a post-sleep failure actually was. If this restores input, the
; problem is the stale device handle or the registration -- not the backend.
;
; Shared rather than ported. It was companion-only, and the shell -- which has no
; desktop to fall back to and no keyboard on a handheld -- had no way to ask for
; this at all short of a restart. Copying it would have created a divergent pair
; over a body that names nothing per-product.
;
; Reaching it is the honest limitation, and the reason this is a diagnostic rather
; than a recovery: a user whose controller has stopped answering cannot navigate
; to a button with the controller. It earns its place by telling you WHICH failure
; you had, in one click, while you still have input -- not by rescuing a session
; that has already lost it.
RearmControllerInput(*) {
    global ActiveControllerIndex
    LogLine("Controller: manual re-arm requested.")
    RawInputResetDeviceLock("manual re-arm")
    ; -1 makes XInputResolveController rescan all four slots rather than trusting
    ; the slot it last succeeded on, and the gate reset stops that rescan waiting
    ; out a backoff the user has just explicitly asked to skip.
    ActiveControllerIndex := -1
    XInputScanGate(true)
    RawInputReregister()
    ShowNotification("Controller input re-armed")
}


; Infers a resume from a gap in the wall clock, for callers already on a timer.
;
; WM_POWERBROADCAST is handled above and is NOT enough on its own. The companion
; found that out on the hardware both products target: an ROG Ally sleeps into
; modern standby, where the broadcast is not reliably delivered. A resume detector
; that depends on being told is a detector that does not fire on the one device
; this matters most on.
;
; WALL CLOCK, NOT A_TickCount, and that is the whole trick. The tick counter does
; not advance through suspend, so tick arithmetic sees no gap at all and reports
; that nothing happened. A_Now keeps counting because it is the actual date.
;
; Rate-limited on ticks so a caller polling every few milliseconds does not run a
; DateDiff each time. After a resume the limiter costs at most one interval before
; the check runs, which is well inside the 2500 ms the re-registration already
; waits for the HID stack.
;
; Threshold is expectedIntervalSeconds * 2 + 30, carried over from the companion's
; heartbeat: twice the cadence absorbs ordinary scheduling jitter, and the 30
; seconds means a machine merely under heavy load is never mistaken for one that
; slept.
ControllerResumeGapCheck(expectedIntervalSeconds) {
    static lastStamp := ""
    static lastCheckTick := 0
    if (A_TickCount - lastCheckTick < 5000 && lastStamp != "")
        return false
    lastCheckTick := A_TickCount
    now := A_Now
    if (lastStamp = "") {
        lastStamp := now
        return false
    }
    elapsed := 0
    try elapsed := DateDiff(now, lastStamp, "Seconds")
    lastStamp := now
    if (elapsed <= expectedIntervalSeconds * 2 + 30)
        return false
    LogLine("Power: wall-clock gap of " elapsed "s (expected about "
        . expectedIntervalSeconds "s). Treating this as a resume and re-arming "
        . "controller input.")
    RawInputResetDeviceLock("resume inferred from wall-clock gap")
    SetTimer(RawInputReregister, -1000)
    return true
}


; Reports whether controller reports actually resumed.
;
; Without this, a failed recovery is silent, and silence has already cost several
; test cycles on this backend.
RawInputResumeVerify() {
    global RawInputLastReportTick, RawInputDevice, ControllerBackend
    if RawInputLastReportTick {
        LogLine("RawInput: reports resumed on device 0x"
            . Format("{:X}", RawInputDevice) ".")
        return
    }
    LogLine("RawInput: NO reports since resume after 10s. Press a button; if this"
        . " persists, RawInput did not recover and the backend is effectively "
        . (StrLower(ControllerBackend) = "rawinput" ? "dead until restart"
            : "XInput only"), "Warning")
}


; Lists what RawInput actually knows about. Registration succeeds even when no
; matching device exists, so a successful register followed by silence proves
; nothing on its own. This reports whether a HID gamepad/joystick collection
; exists at all -- Xbox pads on the XUSB driver are known not to publish one,
; which would explain silence without any filtering being involved.
RawInputProbeEnumerate() {
    static RIDI_DEVICEINFO := 0x2000000B
    static RIM_TYPEHID := 2
    static LIST_ENTRY_SIZE := 16

    count := 0
    try {
        if (DllCall("GetRawInputDeviceList", "Ptr", 0, "UInt*", &count,
            "UInt", LIST_ENTRY_SIZE, "UInt") = 0xFFFFFFFF || !count) {
            LogLine("RawInput probe: device list unavailable.", "Warning")
            return
        }
        list := Buffer(count * LIST_ENTRY_SIZE, 0)
        got := count
        if (DllCall("GetRawInputDeviceList", "Ptr", list, "UInt*", &got,
            "UInt", LIST_ENTRY_SIZE, "UInt") = 0xFFFFFFFF) {
            LogLine("RawInput probe: device list read failed.", "Warning")
            return
        }
        hidCount := 0
        Loop got {
            offset := (A_Index - 1) * LIST_ENTRY_SIZE
            hDevice := NumGet(list, offset, "Ptr")
            if (NumGet(list, offset + 8, "UInt") != RIM_TYPEHID)
                continue
            hidCount++
            info := Buffer(32, 0)
            NumPut("UInt", 32, info, 0)
            size := 32
            if (DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", RIDI_DEVICEINFO,
                "Ptr", info, "UInt*", &size, "UInt") = 0xFFFFFFFF)
                continue
            LogLine("RawInput HID: vid=0x" Format("{:04X}", NumGet(info, 8, "UInt"))
                . " pid=0x" Format("{:04X}", NumGet(info, 12, "UInt"))
                . " usagePage=0x" Format("{:02X}", NumGet(info, 20, "UShort"))
                . " usage=0x" Format("{:02X}", NumGet(info, 22, "UShort")))
        }
        LogLine("RawInput probe: " got " devices enumerated, " hidCount " of them HID."
            . (hidCount ? "" : " No HID collection exists for RawInput to deliver."))
    }
    ; A bare try here swallowed the one diagnostic that says whether Windows has
    ; any HID collection to deliver at all. Losing it turns "RawInput sees no
    ; controller" into a question with no evidence either way, which is the state
    ; this whole function exists to prevent.
    ;
    ; Not rate-limited, unlike the WM_INPUT handler: this runs once, from
    ; RawInputProbeStart.
    catch as err {
        LogLine("RawInput probe: device enumeration failed -- " err.Message
            . " (" err.File ":" err.Line "). The probe cannot report which HID "
            . "collections exist; controller detection may still work.", "Warning")
    }
}


RawInputProbeMessage(wParam, lParam, msg, hwnd) {
    global EnableRawInputProbe, CompanionDisabled
    static RID_INPUT := 0x10000003
    static HEADER_SIZE := 24
    static RIM_TYPEHID := 2
    static lastHex := ""
    static lastTick := 0
    static arrivals := 0
    static lastArrivalLog := 0
    static failures := 0
    static lastFailureLogTick := 0
    if CompanionDisabled
        return 0

    ; Count arrivals BEFORE any filtering. Without this, a message that is
    ; received and then discarded during parsing is indistinguishable from a
    ; message that never arrived.
    ;
    ; COUNTED always, LOGGED only when the probe is switched on. A controller
    ; sends these at over 100 Hz, so a line every two seconds is a line every
    ; two seconds forever -- which is what it became once the shell started
    ; registering for RawInput by default, burying everything else in the log.
    arrivals++
    if (EnableRawInputProbe && A_TickCount - lastArrivalLog >= 2000) {
        lastArrivalLog := A_TickCount
        LogLine("RawInput probe: " arrivals " WM_INPUT message(s) received so far.")
    }

    size := 0
    try {
        if (DllCall("GetRawInputData", "Ptr", lParam, "UInt", RID_INPUT,
            "Ptr", 0, "UInt*", &size, "UInt", HEADER_SIZE) = 0xFFFFFFFF || !size)
            return
        data := Buffer(size, 0)
        if (DllCall("GetRawInputData", "Ptr", lParam, "UInt", RID_INPUT,
            "Ptr", data, "UInt*", &size, "UInt", HEADER_SIZE) = 0xFFFFFFFF)
            return
        if (NumGet(data, 0, "UInt") != RIM_TYPEHID)
            return
        device := NumGet(data, 8, "Ptr")
        sizeHid := NumGet(data, HEADER_SIZE, "UInt")
        count := NumGet(data, HEADER_SIZE + 4, "UInt")
        if (!sizeHid || !count)
            return
        ; Report the first report only, and cap the byte count: this identifies
        ; presses without turning a 125 Hz stream into an unreadable log.
        limit := Min(sizeHid, 20)
        hex := ""
        Loop limit
            hex .= Format("{:02X}", NumGet(data, HEADER_SIZE + 8 + A_Index - 1, "UChar")) " "
        hex := RTrim(hex)

        ; Decode EVERY report, before any log rate-limiting. The cached state is
        ; what the poll loop reads, so dropping reports here would drop input.
        ;
        ; That sentence was already here, and the code under it decoded only the
        ; FIRST report. RAWINPUT carries `count` reports of `sizeHid` bytes each
        ; and Windows coalesces them under load, so every report after the first
        ; in a batch was read out of the header, used to size the hex log, and
        ; thrown away.
        ;
        ; It bites hardest on exactly the devices this decoder is built around.
        ; RawInputDecodeReport notes that the Ally "sends no duplicate reports
        ; while a digital control is held" -- so on a change-only device a
        ; coalesced press is not a late press, it is a press that never arrives.
        ; The learner reads the same stream and lost presses the same way, which
        ; is a wizard that sits there while the user presses the button.
        ;
        ; The hex log stays on the first report only. That cap is deliberate and
        ; is about log volume, not about decoding.
        ; Trust the buffer, not the header. `count` and `sizeHid` are read out of
        ; the packet, and the decoders index straight into memory from them, so
        ; the number of reports is bounded by what was actually delivered.
        available := (size - (HEADER_SIZE + 8)) // sizeHid
        Loop Min(count, Max(0, available)) {
            reportBase := HEADER_SIZE + 8 + (A_Index - 1) * sizeHid
            ; The learning wizard sees reports first and consumes them: while it
            ; is open, decoding as well would fire mappings from the very buttons
            ; being pressed to teach the layout.
            if !ControllerLearnConsumesReport(data, reportBase, sizeHid, device)
                RawInputDecodeReport(data, reportBase, sizeHid, device)
        }

        if !EnableRawInputProbe
            return
        ; Log on change, rate-limited, so a held button cannot flood the log.
        if (hex = lastHex || A_TickCount - lastTick < 60)
            return
        lastHex := hex
        lastTick := A_TickCount
        foreground := "unknown"
        try foreground := WinGetProcessName("A")
        LogLine("RawHID dev=0x" Format("{:X}", device)
            . " len=" sizeHid " n=" count " [" hex "] fg=" foreground)
    }
    ; THE CATCH IS NOT OPTIONAL, for the same reason it is not optional in
    ; RawInputDeviceKey below: this whole body was a bare `try`, and a bare try
    ; SWALLOWS. Nothing above can see a throw here either -- the caller is the
    ; Windows message pump -- so a failure in GetRawInputData, a bad offset, or a
    ; decoder fault stopped every controller report with no record anywhere. That
    ; is the exact shape of the RIDI_DEVICENAME bug documented further down, which
    ; made a device lookup appear to fail on every machine for as long as nobody
    ; thought to question it.
    ;
    ; Rate-limited to once a minute rather than logged per report, because this
    ; runs from WM_INPUT above 100 Hz and an unrated line here would bury the log
    ; it is meant to make readable. The first failure is always logged; the count
    ; carries how many followed.
    catch as err {
        failures++
        if (!lastFailureLogTick || A_TickCount - lastFailureLogTick >= 60000) {
            LogLine("RawInput: report handling threw -- " err.Message
                . " (" err.File ":" err.Line "). Controller input from this "
                . "backend is degraded or stopped. Total failures: " failures ".",
                "Error")
            lastFailureLogTick := A_TickCount
        }
    }
}


; Decodes one HID gamepad report into the XINPUT_STATE-shaped buffer the rest of
; the companion consumes, so mappings, chords and the controller mouse are
; identical on every backend.
;
; Layout verified against hardware (device 0x10062, 16-byte report):
;   1-2 LX, 3-4 LY, 5-6 RX, 7-8 RY   16-bit LE, 0x8000 centre, 0x0000 = left/up
;   9-10  combined trigger axis      0x8000 neutral, above = LT, below = RT
;   11    A B X Y LB RB View Menu    bits 0..7
;   12    L3 R3 Guide                bits 0..2
;   13    D-pad hat, 1..8 clockwise from north, 0 = released
; Decides whether this device is the one whose reports we decode.
;
; The lock is not permanent, and must not be. RawInputDevice holds a
; RAWINPUTHEADER.hDevice handle, and those handles are NOT stable for the life of
; the process: Windows re-enumerates HID devices across sleep/resume and the same
; controller comes back with a DIFFERENT handle. A permanent lock then rejects
; every report the controller sends -- silently, because rejecting a report from
; another device is normal behaviour. Measured symptom: input works, the Ally
; sleeps, and input never returns inside FSE, while the desktop keeps working
; because `auto` falls back to XInput, which re-resolves its slot on its own.
;
; So the lock is handed over when the locked device has gone quiet and a different
; one is producing usable reports. A device that is actively reporting is never
; displaced, which is what keeps a headset or remote out of the decoder -- the
; reason the lock exists at all.
RawInputClaimDevice(device) {
    global RawInputDevice, RawInputLastReportTick
    static DEVICE_HANDOVER_MS := 1000
    if (RawInputDevice && device != RawInputDevice) {
        if (RawInputLastReportTick
            && A_TickCount - RawInputLastReportTick < DEVICE_HANDOVER_MS)
            return false
        LogLine("RawInput: device 0x" Format("{:X}", RawInputDevice) " went quiet; "
            . "adopting 0x" Format("{:X}", device)
            . " (re-enumerated, most likely across sleep).")
        RawInputDevice := device
        return true
    }
    if !RawInputDevice {
        RawInputDevice := device
        LogLine("RawInput: decoding reports from device 0x" Format("{:X}", device) ".")
    }
    return true
}


RawInputDecodeReport(data, base, length, device) {
    global RawInputState, RawInputLastReportTick, RawInputDevice
    static EXPECTED_LENGTH := 16
    static warnedDevices := Map()
    static announcedProfile := Map()

    ; Only accept the report shape this decoder was verified against, and stay
    ; with the first device that produces one. Other HID devices (headsets,
    ; remotes) also raise WM_INPUT and would decode into nonsense.
    ;
    ; The byte layout below is NOT generic HID -- it is the layout of the ROG
    ; Ally's built-in controller, read off the hardware. A controller with any
    ; other report shape is rejected here, which is the safe outcome on the
    ; desktop (XInput takes over) and a dead controller inside Xbox FSE, where
    ; XInput reads zeros. Logged per device rather than once, because "some
    ; other controller was ignored" is the whole diagnosis.
    ; A learned profile takes precedence, and is tried before the length check --
    ; the whole point of learning a controller is that its reports are a shape
    ; this built-in layout would reject.
    deviceKey := RawInputDeviceKey(device)
    profile := LoadControllerProfile(deviceKey)
    ; No identity available, so fall back to a profile keyed on report length.
    if (!IsObject(profile) && deviceKey = "")
        profile := LoadControllerProfile(ControllerProfileLengthKey(length))
    ; Both suppression maps key on the STABLE identity, not the hDevice.
    ;
    ; RawInputDeviceKey's own header explains that handles change across sleep and
    ; re-plugging, and RawInputClaimDevice exists entirely to cope with that. Keyed
    ; on the handle, these two maps gained an entry per re-enumeration for the life
    ; of the process, and the "ignoring N-byte reports" warning fired again after
    ; every resume -- noise in the log from the map whose job is to suppress it.
    identity := deviceKey != "" ? deviceKey : ControllerProfileLengthKey(length)
    if (IsObject(profile) && profile["length"] = length) {
        if !RawInputClaimDevice(device)
            return false
        if !announcedProfile.Has(identity) {
            announcedProfile[identity] := true
            LogLine("RawInput: decoding device 0x" Format("{:X}", device)
                . " with learned profile '" profile["key"] "'.")
        }
        return RawInputProfileDecode(profile, data, base, length)
    }

    if (length != EXPECTED_LENGTH) {
        if !warnedDevices.Has(identity) {
            warnedDevices[identity] := true
            LogLine("RawInput: ignoring " length "-byte reports from device 0x"
                . Format("{:X}", device) " (" RawInputDeviceKey(device) "). The "
                . "built-in layout only understands " EXPECTED_LENGTH "-byte "
                . "reports (the ROG Ally controller). Use Settings -> Controller "
                . "& Cursor -> Learn Controller to teach this one, or it will work on the "
                . "desktop through XInput but not inside Xbox FSE.", "Warning")
        }
        return false
    }
    if !RawInputClaimDevice(device)
        return false

    buttons := 0
    face := NumGet(data, base + 11, "UChar")
    extra := NumGet(data, base + 12, "UChar")
    hat := NumGet(data, base + 13, "UChar")
    if (face & 0x01)
        buttons |= 0x1000        ; A
    if (face & 0x02)
        buttons |= 0x2000        ; B
    if (face & 0x04)
        buttons |= 0x4000        ; X
    if (face & 0x08)
        buttons |= 0x8000        ; Y
    if (face & 0x10)
        buttons |= 0x0100        ; LB
    if (face & 0x20)
        buttons |= 0x0200        ; RB
    if (face & 0x40)
        buttons |= 0x0020        ; View
    if (face & 0x80)
        buttons |= 0x0010        ; Menu
    if (extra & 0x01)
        buttons |= 0x0040        ; L3
    if (extra & 0x02)
        buttons |= 0x0080        ; R3
    if (extra & 0x04)
        buttons |= 0x0400        ; Guide
    switch hat {
        case 1:
            buttons |= 0x0001
        case 2:
            buttons |= 0x0001 | 0x0008
        case 3:
            buttons |= 0x0008
        case 4:
            buttons |= 0x0002 | 0x0008
        case 5:
            buttons |= 0x0002
        case 6:
            buttons |= 0x0002 | 0x0004
        case 7:
            buttons |= 0x0004
        case 8:
            buttons |= 0x0001 | 0x0004
    }

    ; Combined trigger axis. LT and RT cancel when held together, so a chord can
    ; never require both at once on this backend.
    trigger := NumGet(data, base + 9, "UShort")
    lt := 0
    rt := 0
    if (trigger > 0x8000)
        lt := Min(255, (trigger - 0x8000) // 128)
    else if (trigger < 0x8000)
        rt := Min(255, (0x8000 - trigger) // 128)

    NumPut("UInt", 0, RawInputState, 0)
    NumPut("UShort", buttons, RawInputState, 4)
    NumPut("UChar", lt, RawInputState, 6)
    NumPut("UChar", rt, RawInputState, 7)
    NumPut("Short", RawInputAxis(NumGet(data, base + 1, "UShort")), RawInputState, 8)
    ; HID reports up as 0x0000; XInput expects up to be positive.
    NumPut("Short", -RawInputAxis(NumGet(data, base + 3, "UShort")), RawInputState, 10)
    NumPut("Short", RawInputAxis(NumGet(data, base + 5, "UShort")), RawInputState, 12)
    NumPut("Short", -RawInputAxis(NumGet(data, base + 7, "UShort")), RawInputState, 14)
    RawInputLastReportTick := A_TickCount
    return true
}


ControllerProfilePath() {
    global IniPath
    return ControllerProfilePathFor(IniPath)
}


; The human-readable device path, recorded beside a learned profile so the INI
; can be read by a person. Called once per Save, not on the input path.
;
; NOT named "buffer" -- see the note in RawInputDeviceKey. This copy had the
; same defect, so every profile ever saved recorded an empty Name.
RawInputDeviceName(hDevice) {
    static RIDI_DEVICENAME := 0x20000007
    name := ""
    size := 0
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
        LogLine("RawInput: the device path for 0x" Format("{:X}", hDevice)
            . " could not be read: " err.Message, "Warning")
    }
    return name
}


; Loads a profile, or 0 when the device has none.
;
; Returns a Map of: length, buttons (array of name/offset/mask/pressed), hat
; (Map or 0), axes (Map of name -> offset/size/neutral/direction/extent).
;
; The optional fourth button field and sixth axis field were added after the
; first profile draft. Missing fields retain the original active-high and
; full-range behaviour, so hand-written or early profiles remain valid.
; The profile for a device key, from THIS product's controller-profile file.
;
; The lookup, the fallback to a VID/PID-only base profile and the parsing are all
; in SteamShell-Common.ahk now, so the elevated helper can do the same lookup
; against the same file. What stayed here is the one thing the helper resolves
; differently: where that file is.
LoadControllerProfile(key, refresh := false) {
    return LoadControllerProfileFrom(ControllerProfilePath(), key, refresh)
}
; Decodes a report using a learned profile.
;
; Produces exactly the same XINPUT_STATE-shaped buffer as the built-in decoder,
; so every mapping, chord and the controller mouse behave identically no matter
; how the layout was obtained.
; Decodes one report into this process's shared RawInput state buffer.
;
; The decode itself is in SteamShell-Common.ahk and writes into whatever buffer
; it is handed, because the helper keeps its own. The buffer and the freshness
; stamp are the only parts that were ever tree state.
RawInputProfileDecode(profile, data, base, length) {
    global RawInputState, RawInputLastReportTick
    if !RawInputProfileDecodeInto(profile, data, base, length, RawInputState)
        return false
    RawInputLastReportTick := A_TickCount
    return true
}
RawInputRegistered() {
    global RawInputProbeActive
    return RawInputProbeActive
}


; RawInput is event-driven, so the poll loop reads the most recent decoded
; report. Reports stop arriving entirely outside Xbox FSE, so a stale cache is
; cleared to neutral rather than left holding a button down forever.
RawInputReadState(&state) {
    global RawInputState, RawInputLastReportTick, RawInputStaleMs
    if !RawInputLastReportTick
        return false
    if (A_TickCount - RawInputLastReportTick > RawInputStaleMs) {
        if (NumGet(RawInputState, 4, "UShort") || NumGet(RawInputState, 6, "UChar")
            || NumGet(RawInputState, 7, "UChar")) {
            NumPut("UInt", 0, RawInputState, 0)
            NumPut("UInt", 0, RawInputState, 4)
            NumPut("UInt", 0, RawInputState, 8)
            NumPut("UInt", 0, RawInputState, 12)
        }
        return false
    }
    if !IsObject(state)
        state := Buffer(16, 0)
    Loop 16
        NumPut("UChar", NumGet(RawInputState, A_Index - 1, "UChar"), state, A_Index - 1)
    return true
}

; ==============================================================================
; Settings page definition
; ==============================================================================
; Selects the entry in a choice control whose WORDS match the stored value.
;
; Both products need this and neither may use the index. A list's order lives
; somewhere other than the value it stores, so selecting by position ties the
; two together and they drift -- which is exactly how the companion's control
; modes ended up inverted from the shell's, and why the controller index
; dropdown wrote 1-4 into a setting that means 0-3.
;
; Case-insensitive, falling back to the first entry, because the INI is
; hand-editable and a value matching no entry has to land somewhere predictable.
SettingsSelectChoiceByText(ctrl, value, choices) {
    wanted := StrLower(Trim(value))
    for _, choice in choices {
        if (StrLower(choice) = wanted) {
            try ctrl.Text := choice
            return
        }
    }
    try ctrl.Choose(1)
}

; Where every Settings control sits, for both products.
;
; The shell's numbers, in the companion's table. The companion used its own --
; label at 300, control at 570, content 570 wide in a 900-pixel window -- and
; the shell's are label 255, control 575, content 690 wide in 980. Two Settings
; windows the same family ships should not be different shapes.
;
; A table rather than numbers typed into each builder, which is the companion's
; model and the better one: a builder asks where the column is instead of
; stating it, so moving a column is one edit rather than sixty. The shell stated
; them per control, which is why it carried sixty-odd literal coordinates.
;
; One definition means the two windows cannot drift apart by a pixel, which is
; what has to be true before a row builder can serve both.
SettingsLayout() {
    static layout := Map(
        "labelX", 255, "labelWidth", 310,
        "controlX", 575, "controlWidth", 370,
        "contentX", 255, "contentWidth", 690,
        "contentRight", 945,
        "contentTop", 190, "contentBottom", 600,
        "scrollBarX", 954, "scrollBarWidth", 18,
        ; The shell's remaining columns, which had no entry because only it has
        ; these controls: a path field's edit is narrower to leave room for a
        ; Browse button, and a shortcut field carries a Record button.
        "pathX", 440, "pathWidth", 400,
        "pathButtonX", 850, "recordButtonX", 830)
    return layout
}

; What a Settings page CONTAINS, defined once for both products.
;
; EVERY page, from both products, with "product" deciding who draws each row.
;
; One exception, and it is a row rather than a page. The companion COMPILES this
; file, so every string here ships inside it, and Validate-SteamShell-XFE.ps1
; forbids a list of shell and geometry responsibilities BY NAME -- scanning
; string literals deliberately, because a responsibility named in a string can
; act. Exactly one settings row names one: the shell's foreground-sensitivity
; choice, keyed GameMinScoreToActivate. That row stays hand-placed in the shell,
; the way the ExeList rows do, and the boundary stays as written rather than
; being widened to admit it.
;
; The two Settings windows are separate implementations -- ProductSettingsScrollBar
; records why -- and separate implementations of the same screen drift. They had:
; rows one product offered and the other did not, the same setting under
; different words, and a backend row whose comment still said the shell had no
; backend to choose. Every one of those was found by looking, which is the
; problem.
;
; This is the CONTENT half. Each tree still draws the rows with its own builders;
; it just no longer decides what they are. The drawing halves are the next step,
; and doing content first is what makes that one checkable: the same table has to
; produce the same rows before and after.
;
; Section and key are given ONCE and both the read and the write derive from
; them. That is the shell's model and it is the better one: the companion names a
; field in three places -- the row, the populate and the save -- so
; "Cursor.EnableAutoHide" is a row id that matches neither the section nor the
; key it actually reads and writes, and keeping three names in step by hand is
; how a setting silently stops saving.
;
;   product   "both", "standalone" or "xfe" -- who shows the row
;   type      checkbox | choice | edit | note
SettingsCategoryRows(category) {
    static table := Map(
        ; Category names follow the shell's. The companion calls its logging page
        ; "Advanced"; the shell calls it "Advanced & Logging" and that is the key
        ; here, with the companion passing it explicitly while its own list keeps
        ; the shorter name until category structure is unified too.
        "Startup & Splash", [
            Map("product", "standalone", "type", "checkbox",
                "section", "Features", "key", "EnableElevatedInputHelper",
                "label", "Enable elevated helper for administrator windows",
                "default", "true"),
            Map("product", "standalone", "type", "path",
                "section", "Paths", "key", "SteamPath",
                "label", "Steam executable",
                "prompt", "Select Steam.exe", "filter", "Programs (*.exe)", "default", "C:\Program Files (x86)\Steam\Steam.exe"),
            Map("product", "standalone", "type", "checkbox",
                "section", "Features", "key", "EnableSplashScreen",
                "label", "Show the SteamShell startup splash",
                "default", "true"),
            Map("product", "standalone", "type", "choice",
                "section", "Splash", "key", "Mode",
                "label", "Splash mode",
                "choices", ["Black", "Video"], "default", "Black"),
            Map("product", "standalone", "type", "path",
                "section", "Splash", "key", "VideoPath",
                "label", "Startup video",
                "prompt", "Select a startup video", "filter", "Video Files (*.mp4; *.mkv; *.webm; *.wmv; *.avi)", "default", ""),
            Map("product", "standalone", "type", "path",
                "section", "Splash", "key", "MpvPath",
                "label", "MPV executable",
                "prompt", "Select mpv.exe", "filter", "Programs (*.exe)", "default", ""),
            Map("product", "standalone", "type", "checkbox",
                "section", "Splash", "key", "Mute",
                "label", "Mute startup video audio",
                "default", "false"),
            Map("product", "standalone", "type", "checkbox",
                "section", "Splash", "key", "PlayFullDuration",
                "label", "Play the entire startup video",
                "default", "true"),
            Map("product", "standalone", "type", "checkbox",
                "section", "Splash", "key", "ForceSDR",
                "label", "Force MPV to SDR output",
                "default", "true"),
            Map("product", "standalone", "type", "edit",
                "section", "Timing", "key", "SplashScreenDuration",
                "label", "Black/timed splash duration (ms)",
                "default", "10000",
                "fieldType", "integer", "min", 0, "max", 60000),
            Map("product", "standalone", "type", "edit",
                "section", "Splash", "key", "SafetyMaxMs",
                "label", "Video safety timeout (ms)",
                "default", "15000",
                "fieldType", "integer", "min", 1000, "max", 600000),
            Map("product", "standalone", "type", "edit",
                "section", "Splash", "key", "FadeOutMs",
                "label", "Splash fade duration (ms)",
                "default", "300",
                "fieldType", "integer", "min", 0, "max", 5000)],
        "Focus & Windows", [
            Map("product", "standalone", "type", "checkbox",
                "section", "Features", "key", "EnableSteamRefocusMode",
                "label", "Refocus Steam Big Picture when no application remains",
                "default", "true"),
            Map("product", "standalone", "type", "edit",
                "section", "Timing", "key", "SteamRefocusDelay",
                "label", "Steam refocus delay (ms)",
                "default", "1000",
                "fieldType", "integer", "min", 0, "max", 60000),
            Map("product", "standalone", "type", "checkbox",
                "section", "Features", "key", "EnableGameForegroundAssist",
                "label", "Bring the active fullscreen-style game forward",
                "default", "true", "dependency", true),
            Map("product", "standalone", "type", "checkbox",
                "section", "GameForegroundAssist", "key", "GameRequireSteamForeground",
                "label", "Run game assistance only while Steam is foreground",
                "default", "true"),
            Map("product", "standalone", "type", "checkbox",
                "section", "Features", "key", "EnableAlwaysFocus",
                "label", "Enable the AlwaysFocus executable list",
                "default", "true"),
            Map("product", "standalone", "type", "checkbox",
                "section", "Features", "key", "EnableWindowManagement",
                "label", "Center windows and maximize large windows",
                "default", "true", "dependency", true),
            Map("product", "standalone", "type", "edit",
                "section", "WindowManagement", "key", "MinWidthPercent",
                "label", "Maximize width threshold (%)",
                "default", "0.30",
                "fieldType", "percent", "min", 5, "max", 100)],
        "Launcher Cleanup", [
            Map("product", "standalone", "type", "checkbox",
                "section", "LauncherCleanup", "key", "Enable",
                "label", "Enable launcher cleanup",
                "default", "true"),
            Map("product", "standalone", "type", "checkbox",
                "section", "LauncherCleanup", "key", "RequireNoGame",
                "label", "Require SteamShell to detect that no game is running",
                "default", "true", "dependency", true),
            Map("product", "standalone", "type", "checkbox",
                "section", "LauncherCleanup", "key", "HardKill",
                "label", "Force-close remaining launcher processes after the grace period",
                "default", "true"),
            Map("product", "standalone", "type", "edit",
                "section", "LauncherCleanup", "key", "SteamForegroundSec",
                "label", "Steam foreground time before cleanup (sec)",
                "default", "30",
                "fieldType", "integer", "min", 1, "max", 600),
            Map("product", "standalone", "type", "edit",
                "section", "LauncherCleanup", "key", "CooldownSec",
                "label", "Cleanup cooldown (sec)",
                "default", "300",
                "fieldType", "integer", "min", 0, "max", 86400),
            Map("product", "standalone", "type", "edit",
                "section", "LauncherCleanup", "key", "GracefulCloseMs",
                "label", "Graceful-close wait (ms)",
                "default", "4000",
                "fieldType", "integer", "min", 0, "max", 60000),
            Map("product", "standalone", "type", "checkbox",
                "section", "LauncherCleanup", "key", "UseCpuAudio",
                "label", "Use CPU and audio activity for the no-game safety check",
                "default", "true", "dependency", true),
            Map("product", "standalone", "type", "edit",
                "section", "LauncherCleanup", "key", "CpuThreshold",
                "label", "CPU activity threshold",
                "default", "12",
                "fieldType", "integer", "min", 0, "max", 500),
            Map("product", "standalone", "type", "checkbox",
                "section", "LauncherCleanup", "key", "DownloadGuard",
                "label", "Skip cleanup during possible downloads or updates",
                "default", "true", "dependency", true),
            Map("product", "standalone", "type", "choice",
                "section", "LauncherCleanup", "key", "DownloadGuardMode",
                "label", "Download guard sensitivity",
                "choices", ["Off", "Balanced", "Strict"], "default", "Balanced"),
            ; The companion's launcher cleanup. Its own rows rather than the
            ; shell's, because the two clamp differently -- CooldownSec is
            ; 30..7200 here and 0..86400 there, GracefulCloseMs 500..30000
            ; against 0..60000 -- and a shared row would offer one product values
            ; its own LoadSettings rounds away.
            ;
            ; movedFrom records that these keys used to sit in [Assist]; the
            ; companion resolves whichever section actually holds them, and the
            ; shell ignores the field entirely.
            ;
            ; RequireNoGame and GracefulCloseMs are NEW controls, not moved ones:
            ; this product has read both on every load since the assist work
            ; landed and offered neither, so the only way to change them was to
            ; edit the INI.
            Map("product", "xfe", "type", "checkbox",
                "section", "Assist", "key", "EnableLauncherCleanupLite",
                "label", "Launcher Cleanup Lite — close game launchers once nothing is playing",
                "default", true),
            Map("product", "xfe", "type", "checkbox",
                "section", "LauncherCleanup", "key", "RequireNoGame",
                "label", "Only clean up when no game appears to be running",
                "default", true, "movedFrom", "Assist"),
            Map("product", "xfe", "type", "edit",
                "section", "Assist", "key", "ForegroundStableSec",
                "label", "Settle time before cleanup (s)",
                "default", 30, "min", 5, "max", 600),
            Map("product", "xfe", "type", "edit",
                "section", "LauncherCleanup", "key", "CooldownSec",
                "label", "Minimum time between cleanups (s)",
                "default", 300, "min", 30, "max", 7200, "movedFrom", "Assist"),
            Map("product", "xfe", "type", "edit",
                "section", "LauncherCleanup", "key", "GracefulCloseMs",
                "label", "Graceful-close wait before a force close (ms)",
                "default", 4000, "min", 500, "max", 30000, "movedFrom", "Assist"),
            Map("product", "xfe", "type", "checkbox",
                "section", "LauncherCleanup", "key", "HardKill",
                "label", "Force close launchers that ignore a polite close request",
                "default", true, "movedFrom", "Assist")],
        "Steam", [
            ; "both" as of the pass that gave the shell a Steam page. It read
            ; all three of these already, out of the same section, with the same
            ; keys and the same defaults -- they were simply unreachable from its
            ; Settings window. Leaving them companion-only would have shipped a
            ; page whose own feature SENDS these shortcuts while offering no way
            ; to correct them, which matters because they are the user's Steam
            ; keybinds and Steam lets those be changed.
            Map("product", "both", "type", "shortcut",
                "section", "Steam", "key", "MenuShortcut",
                "label", "Steam Menu shortcut",
                "default", "^1"),
            Map("product", "both", "type", "shortcut",
                "section", "Steam", "key", "QuickAccessShortcut",
                "label", "Steam Quick Access shortcut",
                "default", "^2"),
            Map("product", "both", "type", "shortcut",
                "section", "Steam", "key", "OverlayShortcut",
                "label", "In-game Steam overlay shortcut",
                "default", "+{Tab}"),
            ; The Big Picture window title is a Steam fact, not a general
            ; one. It sat on General because that is where this product's
            ; odds and ends went before it had a Steam page.
            Map("product", "standalone", "type", "edit",
                "section", "BPM", "key", "BpmTitle",
                "label", "Steam Big Picture window title",
                "default", "Steam Big Picture Mode"),
            ; The one row of this group whose DEFAULT differs by product, so it
            ; is written twice rather than once with a default that would be
            ; wrong for one of them. Everything below it is shared: those only
            ; matter once this is on, and they behave the same in both.
            ;
            ; A spec default is not decoration -- SettingsPopulateFields reads it
            ; as the fallback when the key is absent, so one shared "true" here
            ; would have the shell's Settings window showing the feature enabled
            ; while LoadSettings ran with it off.
            ;
            ; Off in the shell because it is the SHELL: View/Back is its mapping
            ; modifier and the button people reach for constantly, so giving a
            ; bare press a new meaning is opt-in there. On in the companion,
            ; which has shipped it that way since it was written and where Xbox
            ; FSE owns the surface the shortcut lands on.
            Map("product", "standalone", "type", "checkbox",
                "section", "Steam", "key", "EnableViewButtonActions",
                "label", "Enable View button Steam actions",
                "default", false),
            Map("product", "xfe", "type", "checkbox",
                "section", "Steam", "key", "EnableViewButtonActions",
                "label", "Enable View button Steam actions",
                "default", true),
            Map("product", "both", "type", "checkbox",
                "section", "Steam", "key", "EnableViewTapAction",
                "label", "Tap — Steam menu when Steam is in front, nothing in a game",
                "default", true),
            Map("product", "both", "type", "checkbox",
                "section", "Steam", "key", "EnableViewHoldAction",
                "label", "Hold — Steam Quick Access, or the overlay in a game",
                "default", true),
            Map("product", "both", "type", "edit",
                "section", "Steam", "key", "ViewHoldMs",
                "label", "Hold, Steam in front (ms)",
                "default", 500, "min", 200, "max", 5000),
            Map("product", "both", "type", "edit",
                "section", "Steam", "key", "ViewHoldInGameMs",
                "label", "Hold, in a game (ms)",
                "default", 1000, "min", 200, "max", 5000)],
        "Assist", [
            Map("product", "xfe", "type", "checkbox",
                "section", "Assist", "key", "EnableGameFocusLite",
                "label", "Game Focus Lite — return a game to the foreground if something steals it",
                "default", true),
            Map("product", "xfe", "type", "checkbox",
                "section", "Assist", "key", "EnableSteamAssistLite",
                "label", "Steam Assist Lite — return to Steam when no game is running",
                "default", true),
            Map("product", "xfe", "type", "checkbox",
                "section", "Assist", "key", "SuspendOnShellOverlay",
                "label", "Pause while the Xbox FSE switcher or another shell overlay is on screen",
                "default", true),
            Map("product", "xfe", "type", "edit",
                "section", "Assist", "key", "TickIntervalMs",
                "label", "Check interval (ms)",
                "default", 2000, "min", 500, "max", 30000),
            Map("product", "xfe", "type", "edit",
                "section", "Assist", "key", "CpuThresholdPercent",
                "label", "Game CPU threshold (%, 0 = window shape only)",
                "default", 12, "min", 0, "max", 100),
],
        "General", [
            Map("product", "standalone", "type", "checkbox",
                "section", "Features", "key", "EnableTaskbarHiding",
                "label", "Hide the Windows taskbar while SteamShell is active",
                "default", "true"),
            Map("product", "standalone", "type", "checkbox",
                "section", "Features", "key", "EnableDesktopBlackout",
                "label", "Show a black background instead of the wallpaper and desktop icons",
                "default", "true"),
            Map("product", "both", "type", "checkbox",
                "section", "QuickMenu", "key", "Enable",
                "label", "Enable the controller-first Quick Menu",
                "default", "true"),
            Map("product", "both", "type", "checkbox",
                "section", "QuickMenu", "key", "ShowGameDetection",
                "label", "Show Game Detection under System (what the window engine scored, and why)",
                "default", "true"),
            ; The preset list is shared and can grow, so it is asked for rather
            ; than written out in two places that would then disagree.
            Map("product", "both", "type", "choice",
                "section", "QuickMenu", "key", "AccentColor",
                "label", "Quick Menu accent color",
                "choicesFrom", "accent", "default", "Purple"),
            Map("product", "both", "type", "edit",
                "section", "QuickMenu", "key", "AccentColorCustom",
                "label", "Custom accent (RRGGBB)", "default", "107C10"),
            Map("product", "both", "type", "edit",
                "section", "QuickMenu", "key", "ChordHoldMs",
                "label", "Quick Menu L3+R3 hold time (ms)",
                "default", "500", "fieldType", "integer", "min", 250, "max", 3000),
            Map("product", "standalone", "type", "edit",
                "section", "QuickMenu", "key", "TaskForceCloseHoldMs",
                "label", "Task Switcher force-close hold time (ms)",
                "default", "1200", "fieldType", "integer", "min", 600, "max", 3000)],
            ; The three Steam shortcuts used to be repeated here for the shell,
            ; because the companion kept them on its own Steam page and the shell
            ; had no such page. The note that stood here said "two placements
            ; until the categories themselves merge" -- they have merged: the
            ; shell draws a Steam page now, so the rows are defined once, over
            ; there, next to the View-button action that SENDS them.
        "Startup Programs", [
            Map("product", "both", "type", "checkbox",
                "section", "StartupPrograms", "key", "Enable",
                "label", "Launch configured startup programs with SteamShell",
                "xfeLabel", "Launch configured startup programs with the companion",
                "default", "true"),
            Map("product", "both", "type", "edit",
                "section", "StartupPrograms", "key", "DelayMs",
                "label", "Launch delay (ms)",
                "default", "2000", "fieldType", "integer", "min", 0, "max", 600000),
            ; "both". The shell reads this on every startup run -- same key,
            ; same 1200 default, same 0..30000 bounds, same meaning: the gap
            ; between one program launching and the next. It was tagged for the
            ; companion only, so the shell honoured a setting it gave no way to
            ; change.
            Map("product", "both", "type", "edit",
                "section", "StartupPrograms", "key", "StaggerMs",
                "label", "Gap between launches (ms)",
                "default", "1200", "fieldType", "integer", "min", 0, "max", 30000),
            Map("product", "both", "type", "choice",
                "section", "StartupPrograms", "key", "WindowMode",
                "label", "Launch window mode",
                "choices", ["Hidden", "Minimized", "Normal"], "default", "Hidden"),
            ; The companion can drop its own token when launching. The shell
            ; reaches the same outcome through LaunchInteractiveApp, which it
            ; needs anyway because it can be started elevated.
            Map("product", "xfe", "type", "checkbox",
                "section", "StartupPrograms", "key", "LaunchDeElevated",
                "label", "Start them as the normal user when the companion is elevated",
                "default", "true")],
        "Advanced & Logging", [
            ; A diagnostic cadence, not a living-room control. It was on
            ; General beside the Quick Menu rows.
            Map("product", "xfe", "type", "edit",
                "section", "Companion", "key", "HeartbeatSeconds",
                "label", "Heartbeat log interval (seconds)",
                "default", "60", "fieldType", "integer", "min", 5, "max", 3600),
            Map("product", "standalone", "type", "choice",
                "section", "Logging", "key", "GameLogMode",
                "label", "Game log detail",
                "choices", ["OFF", "ACTIVATIONS", "TOPN", "DIAGNOSTIC"],
                "default", "OFF", "dependency", true),
            Map("product", "standalone", "type", "edit",
                "section", "Logging", "key", "GameLogTopN",
                "label", "Candidates recorded in TOPN/DIAGNOSTIC",
                "default", "3", "fieldType", "integer", "min", 1, "max", 10),
            Map("product", "standalone", "type", "edit",
                "section", "Logging", "key", "GameLogIntervalMs",
                "label", "Diagnostic logging interval (ms)",
                "default", "3000", "fieldType", "integer", "min", 250, "max", 60000),
            Map("product", "standalone", "type", "checkbox",
                "section", "Logging", "key", "GameLogIncludeTitles",
                "label", "Include window titles in diagnostic logs",
                "default", "true"),
            Map("product", "standalone", "type", "checkbox",
                "section", "GameForegroundAssist",
                "key", "GameAssistLogEvenWhenSkipped",
                "label", "Log candidates even when game assistance is skipped",
                "default", "true"),
            Map("product", "standalone", "type", "edit",
                "section", "Timing", "key", "SteamStartupGraceMs",
                "label", "Steam startup warning delay (ms)",
                "default", "120000", "fieldType", "integer", "min", 10000, "max", 600000),
            Map("product", "standalone", "type", "edit",
                "section", "Timing", "key", "SteamExitConfirmMs",
                "label", "Steam exit confirmation period (ms)",
                "default", "4000", "fieldType", "integer", "min", 1000, "max", 60000),
            ; GameInput is named only in the companion's wording because only the
            ; companion has it to compare against.
            Map("product", "both", "type", "checkbox",
                "section", "Controller", "key", "DiagnosticLogging",
                "label", "Log all XInput slots on every change (diagnostic)",
                "xfeLabel", "Log all XInput slots and GameInput on every change (diagnostic)",
                "default", "false"),
            Map("product", "both", "type", "checkbox",
                "section", "Controller", "key", "RawInputProbe",
                "label", "Log raw background HID gamepad reports (RawInput probe)",
                "default", "false"),
            Map("product", "standalone", "type", "edit",
                "section", "Controller", "key", "RawInputStaleMs",
                "label", "Treat RawInput as silent after (ms)",
                "default", "5000", "fieldType", "integer", "min", 500, "max", 60000)],
        "RTSS & Performance", [
            Map("product", "both", "type", "checkbox",
                "section", "RTSS", "key", "EnableIntegration",
                "label", "Enable RTSS integration in the Quick Menu",
                "default", "true"),
            Map("product", "both", "type", "path",
                "section", "RTSS", "key", "Path", "label", "RTSS executable",
                "prompt", "Select RTSS.exe", "filter", "Programs (*.exe)",
                "default", "C:\\Program Files (x86)\\RivaTuner Statistics Server\\RTSS.exe"),
            Map("product", "both", "type", "checkbox",
                "section", "RTSS", "key", "UseDllIntegration",
                "label", "Use RTSSHooks64.dll for live state and direct control (recommended)",
                "default", "true"),
            Map("product", "both", "type", "note",
                "text", "Loaded beside the configured RTSS.exe. Disable this to "
                    . "force the shortcut controls and configured FPS cap label."),
            Map("product", "xfe", "type", "section", "label", "Overlay"),
            ; The shell's order and the shell's words. The companion listed
            ; these the other way round and read the SELECTED INDEX, so merging
            ; the lists would have inverted its setting -- which is why the
            ; companion now selects and saves choice rows by TEXT, as the shell
            ; always has. Fixing the mechanism rather than bending the list to it
            ; is what makes this order safe to state once.
            Map("product", "both", "type", "choice",
                "section", "RTSS", "key", "OverlayControlMode",
                "label", "Overlay control mode",
                "choices", ["Toggle", "Separate"], "default", "Separate",
                "dependency", true),
            Map("product", "both", "type", "shortcut",
                "section", "RTSS", "key", "OverlayToggleShortcut",
                "label", "Overlay toggle shortcut", "default", "^+o"),
            Map("product", "both", "type", "shortcut",
                "section", "RTSS", "key", "OverlayOnShortcut",
                "label", "Overlay on shortcut", "default", "^+1"),
            Map("product", "both", "type", "shortcut",
                "section", "RTSS", "key", "OverlayOffShortcut",
                "label", "Overlay off shortcut", "default", "^+2"),
            Map("product", "xfe", "type", "section", "label", "Frame Limiter"),
            Map("product", "both", "type", "choice",
                "section", "RTSS", "key", "FrameLimiterControlMode",
                "label", "Frame limiter control mode",
                "choices", ["Toggle", "Separate"], "default", "Separate",
                "dependency", true),
            Map("product", "both", "type", "edit",
                "section", "RTSS", "key", "PresetFrameCap",
                "label", "Preset Frame Cap (FPS)",
                "default", "158", "fieldType", "integer", "min", 0, "max", 1000),
            Map("product", "both", "type", "checkbox",
                "section", "RTSS", "key", "RestoreFrameLimitOnStartup",
                "label", "Restore the last Frame Limit selection when RTSS starts",
                "default", "true"),
            ; Different default AND different words, both deliberate. The
            ; companion is chosen precisely because nothing in it is elevated, so
            ; it defaults OFF and its label leads with what the setting costs.
            Map("product", "both", "type", "checkbox",
                "section", "RTSS", "key", "EnableElevatedFrameCapWrites",
                "label", "Use the elevated helper to set the Frame Limit "
                    . "(needed when RTSS is in Program Files)",
                "xfeLabel", "Use an elevated helper to set the Frame Limit — "
                    . "needed when RTSS is in Program Files, and asks for UAC at startup",
                "default", "true", "xfeDefault", "false"),
            Map("product", "both", "type", "shortcut",
                "section", "RTSS", "key", "CustomFrameCapShortcut",
                "label", "Frame limiter toggle shortcut", "default", "^+f"),
            Map("product", "both", "type", "shortcut",
                "section", "RTSS", "key", "FrameLimiterOnShortcut",
                "label", "Frame limiter on shortcut", "default", "^+5"),
            Map("product", "both", "type", "shortcut",
                "section", "RTSS", "key", "FrameLimiterOffShortcut",
                "label", "Frame limiter off shortcut", "default", "^+6")],
        "Controller & Cursor", [
            Map("product", "both", "type", "checkbox",
                "section", "Controller", "key", "EnableControllerMouseMode",
                "label", "Enable controller mouse mode while holding View/Back",
                "default", "true"),
            ; Auto, RawInput and XInput in both. GameInput is the companion's
            ; alone -- it reads all zeros outside Xbox FSE, so it is not an
            ; option the shell could offer honestly.
            Map("product", "both", "type", "choice",
                "section", "Controller", "key", "Backend",
                "label", "Input backend",
                "choices", ["Auto", "RawInput", "XInput"],
                "xfeChoices", ["Auto", "XInput", "GameInput", "RawInput"],
                "default", "Auto"),
            Map("product", "both", "type", "note",
                "text", "Auto is recommended. XInput covers Xbox-compatible "
                    . "pads; RawInput reads any HID gamepad and is what makes a "
                    . "controller XInput cannot see usable at all. Learn "
                    . "Controller teaches RawInput an unknown pad."),
            Map("product", "both", "type", "choice",
                "section", "Controller", "key", "ControllerIndex",
                "label", "Controller index",
                "choices", ["0", "1", "2", "3"], "default", "0"),
            ; A slider, not an edit box. The useful information here is the
            ; RANGE -- an edit box asks the user to already know that 3200 is
            ; normal and 400 is a crawl, and the only way to find out was to
            ; type a number, save, and try it.
            Map("product", "both", "type", "slider",
                "section", "Controller", "key", "ControllerMouseSpeed",
                "label", "Controller mouse speed",
                "default", "3200", "min", 200, "max", 12000,
                "step", 100, "suffix", " px/s"),
            Map("product", "both", "type", "edit",
                "section", "Controller", "key", "ControllerDeadzone",
                "label", "Stick deadzone",
                "default", "3000", "fieldType", "integer", "min", 0, "max", 32000),
            Map("product", "both", "type", "edit",
                "section", "Controller", "key", "ControllerChordHoldMs",
                "label", "Mapping long-press threshold (ms)",
                "default", "500", "fieldType", "integer", "min", 100, "max", 3000),
            ; Schema 13 moved these out of [Cursor] and the companion's field
            ; ids did not follow, so it looked them up under names that matched
            ; neither the section nor the key. They match now, in both trees.
            Map("product", "both", "type", "checkbox",
                "section", "Features", "key", "EnableAutoHideCursor",
                "movedFrom", "Cursor",
                "label", "Automatically hide an idle mouse cursor",
                "default", "true"),
            Map("product", "both", "type", "edit",
                "section", "Timing", "key", "MouseHideDelay",
                "movedFrom", "Cursor",
                "label", "Cursor hide delay (ms)",
                "default", "1000", "fieldType", "integer", "min", 0, "max", 60000),
            Map("product", "both", "type", "checkbox",
                "section", "Features", "key", "EnableMouseParkOnBoot",
                "movedFrom", "Cursor",
                "label", "Park the mouse at the display edge once during startup",
                "default", "true"),
            ; The companion parks on events the shell has no equivalent for, and
            ; the shell parks on a focus change the companion does not track.
            ; Different rules, not one rule under two names -- the migration
            ; table says so too.
            Map("product", "xfe", "type", "checkbox",
                "section", "Cursor", "key", "ParkOnGameStart",
                "label", "Park when a game enters fullscreen", "default", "true"),
            Map("product", "xfe", "type", "checkbox",
                "section", "Cursor", "key", "ParkOnSteamReturn",
                "label", "Park after returning to Steam", "default", "true"),
            Map("product", "standalone", "type", "checkbox",
                "section", "Features", "key", "EnableMouseParkOnFocusChange",
                "label", "Park once after a managed focus change",
                "default", "true"),
            Map("product", "both", "type", "choice",
                "section", "MousePark", "key", "MouseParkEdge",
                "movedFrom", "Cursor",
                "label", "Mouse parking edge",
                "choices", ["Right", "Left"], "default", "Right"),
            Map("product", "both", "type", "checkbox",
                "section", "Features", "key", "EnableAutoMouseMode",
                "movedFrom", "Controller",
                "label", "Enable automatic mouse mode (master switch)",
                "default", "true"),
            ; The shell can put the whole Windows desktop in automatic mouse
            ; mode. The companion has no desktop mode at all, and that is an
            ; architectural rule its validator enforces by name.
            Map("product", "standalone", "type", "checkbox",
                "section", "Features", "key", "EnableDesktopAutoMouseMode",
                "label", "Automatic mouse throughout Windows desktop mode",
                "default", "true")])
    return table.Has(category) ? table[category] : []
}

; The choice list for a row, asked for when it is not a fixed list.
;
; The accent presets are shared and can grow, so writing them out in the table
; would create a third copy to keep in step with the two that already agree.
SettingsRowChoices(row) {
    if (row.Has("choicesFrom") && row["choicesFrom"] = "accent")
        return QuickMenuAccentPresetNames()
    return row["choices"]
}

; The label and default this product shows for a shared row.
;
; Both differ for real reasons in at least one row -- the elevated frame-cap
; write defaults OFF in the companion and its label leads with the cost, because
; the companion is chosen precisely because nothing in it is elevated. A single
; label would have to be wrong for one of them.
SettingsRowLabel(row, product) {
    return (product = "xfe" && row.Has("xfeLabel")) ? row["xfeLabel"] : row["label"]
}

SettingsRowDefault(row, product) {
    if (product = "xfe" && row.Has("xfeDefault"))
        return row["xfeDefault"]
    return row.Has("default") ? row["default"] : ""
}

; Whether a row belongs to the product being compiled.
SettingsRowAppliesTo(row, product) {
    return row["product"] = "both" || row["product"] = product
}

; ==============================================================================
; Controller Learner
; ==============================================================================
; Teaches the RawInput decoder one controller's report layout, by asking for a
; button at a time and watching which bytes move.
;
; It is not a separate feature from the backend above; it is the half that makes
; it general. The built-in layout covers 16-byte reports from one device, so
; without a learned profile RawInput reaches a pad and then cannot read it. For
; the shell that is the difference between a controller that works and a machine
; the user cannot drive.
;
; Shared whole, wizard included: it is a self-contained dialog rather than a page
; of either product's Settings window, so nothing about it belongs to one tree.

; Lets the wizard take a RawInput report before the decoder sees it.
;
; This was a per-tree seam named ProductControllerLearnConsumesReport, and the
; two copies were byte-identical. The reason recorded for keeping them said the
; QUESTION belonged to the shared file but the STATE belonged to the tree,
; because this file cannot read a global it does not declare into both trees.
;
; That is not so, and this file is where it is disproved: the learner is defined
; here in its entirety and reads LearnActive in seven other functions, including
; the ControllerLearnReport this one calls. A global declared by both trees is
; readable from here -- that is the arrangement the whole Quick Menu painter,
; the RTSS orchestration and the wizard itself already run on. The seam was
; costing two identical copies to answer a question this file could ask directly.
ControllerLearnConsumesReport(data, base, length, device) {
    global LearnActive
    if !LearnActive
        return false
    ControllerLearnReport(data, base, length, device)
    return true
}

CloseControllerLearner(*) {
    global LearnActive, LearnGui, SettingsDialogActive
    global LearnSettleDeadline, LearnSettleDone
    LearnActive := false
    SettingsDialogActive := false
    SetTimer(ControllerLearnTick, 0)
    SetTimer(ControllerLearnBeginSteps, 0)
    SetTimer(ControllerLearnNextStep, 0)
    SetTimer(ControllerLearnStartCapture, 0)
    SetTimer(ControllerLearnSettleTick, 0)
    LearnSettleDeadline := 0
    LearnSettleDone := false
    SetTimer(ControllerLearnIdentificationReady, 0)
    SetTimer(ControllerLearnIdentifyHoldTimeout, 0)
    if IsSet(LearnGui) {
        try LearnGui.Destroy()
        LearnGui := unset
    }
    LogLine("Learn: wizard closed.")
}


; What a control is CALLED, for the person doing the mapping.
;
; The wizard has one string per detection and it was being shown on screen as
; well as written to the log -- so the window said "A = byte 8 bit 0x01
; active-high" and "LX = byte 2 u8 neutral 127 direction 1". That is the right
; amount of detail for diagnosing a pad and the wrong amount for using one.
;
; The log keeps every byte, mask and neutral value: today's gyro and trigger
; faults were found from exactly those numbers. This is only what the window
; shows.
ControllerLearnFriendlyName(name) {
    static names := Map(
        "A", "the A button", "B", "the B button",
        "X", "the X button", "Y", "the Y button",
        "LB", "the left bumper", "RB", "the right bumper",
        "View", "the View button", "Menu", "the Menu button",
        "Guide", "the Guide button",
        "L3", "the left stick click", "R3", "the right stick click",
        "Up", "D-pad up", "Right", "D-pad right",
        "Down", "D-pad down", "Left", "D-pad left",
        "LX", "the left stick", "LY", "the left stick",
        "RX", "the right stick", "RY", "the right stick",
        "LT", "the left trigger", "RT", "the right trigger",
        "Analogue scan", "the sticks and triggers")
    return names.Has(name) ? names[name] : name
}


; Records a detected button or D-pad direction, then waits for it to be RELEASED
; before moving on.
;
; A fixed delay is not enough here. Detection happens on press, so with a blind
; timer the next prompt can appear while the control is still held -- and the next
; step looks for any bit differing from rest, which the still-held control
; satisfies. The result is the next button being learned as the previous one's
; bit. Releasing is therefore part of the step, and the prompts say so.
ControllerLearnAccept(detail, offset := -1, mask := 0, friendly := "") {
    global LearnDetailCtrl, LearnCaptureUntil, LearnLastAccepted
    global LearnReleaseOffset, LearnReleaseMask, LearnReleaseUntil
    global LearnLastFriendly
    LearnLastAccepted := detail
    LearnLastFriendly := friendly != "" ? friendly : detail
    try LearnDetailCtrl.Text := "Got it — " LearnLastFriendly ". Let go."
    LogLine("Learn: " detail ".")
    LearnCaptureUntil := 0
    if (offset < 0) {
        SetTimer(ControllerLearnNextStep, -600)
        return
    }
    LearnReleaseOffset := offset
    LearnReleaseMask := mask
    ; Bounded, so a latching or sticky control cannot strand the wizard. The
    ; timeout advances anyway and the log records that the release was not seen.
    LearnReleaseUntil := A_TickCount + 6000
}


; Measures the farthest point of the outward sweep and how directly it got there.
; Correct endianness produces a nearly monotonic path (coherence near 1);
; interpreting the same bytes backwards wraps repeatedly and scores poorly.
ControllerLearnAxisStats(offset, size) {
    global LearnAxisSamples, LearnBaseline
    neutral := ControllerLearnBufferAxisRaw(LearnBaseline, offset, size)
    previous := neutral
    path := 0
    pathAtPeak := 0
    peakRaw := neutral
    peakIndex := 0
    extent := 0
    for index, report in LearnAxisSamples {
        raw := ControllerLearnBufferAxisRaw(report, offset, size)
        path += Abs(raw - previous)
        previous := raw
        sampleExtent := Abs(raw - neutral)
        if (sampleExtent > extent) {
            extent := sampleExtent
            peakRaw := raw
            peakIndex := index
            pathAtPeak := path
        }
    }
    scale := size = "u8" ? 256 : 1
    delta := extent * scale
    coherence := extent / Max(1, pathAtPeak)
    score := delta * (0.20 + 0.80 * coherence)
    if (size != "u8") {
        highOffset := size = "u16le" ? offset + 1 : offset
        ; The high byte of a real 16-bit field changes progressively as the
        ; control travels. Under the wrong byte order it is the wrapping low
        ; byte instead. Weighting that path prevents one final 0xFF sample from
        ; making the reversed interpretation look like a 65,000-count sweep.
        score *= ControllerLearnHighByteQuality(highOffset, peakIndex)
    }
    return Map(
        "offset", offset,
        "size", size,
        "neutral", neutral,
        "raw", peakRaw,
        "extent", extent,
        "delta", delta,
        "coherence", coherence,
        "score", score)
}


; Ends rest sampling and starts prompting.
;
; The resting measurement matters more than anything else here. Every detection
; is a difference from it, and the set of bits seen at rest is what stops a
; jittering analogue axis from being learned as a button.
ControllerLearnBeginSteps() {
    global LearnActive, LearnStepIndex, LearnRestSampling, LearnRestCount
    global LearnRestNoise, LearnLength
    if !LearnActive
        return
    LearnRestSampling := false
    noisy := 0
    Loop LearnLength {
        if NumGet(LearnRestNoise, A_Index - 1, "UChar")
            noisy += 1
    }
    ; The OFFSETS, not just how many. A run where the button bytes are in this
    ; list is a run where something was held during the countdown, and every bit
    ; in it is skipped by every later step -- silently, which is what made it
    ; look like the wizard was ignoring the controller.
    noisyList := ""
    Loop LearnLength {
        if NumGet(LearnRestNoise, A_Index - 1, "UChar")
            noisyList .= (noisyList != "" ? "," : "") (A_Index - 1)
    }
    LogLine("Learn: rest sampled from " LearnRestCount " report"
        . (LearnRestCount = 1 ? "" : "s") "; " noisy " of " LearnLength
        . " bytes changed during rest"
        . (noisyList != "" ? " (bytes " noisyList ")" : "") ".")
    if (LearnRestCount = 0) {
        ; Some controllers only report on change, so silence at rest is normal
        ; and the idle report captured before the identifying press is retained.
        ; Worth recording, because it also means a missed press produces no
        ; report to examine.
        ;
        ; This sentence used to be false. The baseline had been overwritten with
        ; the report that identified the device -- the press -- so "the
        ; pre-selection idle report" was exactly what it was NOT using. It is
        ; now, which is what makes a change-only pad safe here.
        LogLine("Learn: no reports while at rest; this controller reports only "
            . "on change. Using the pre-selection idle report as the baseline.")
    }
    LearnStepIndex := 1
    ControllerLearnStartCapture()
    SetTimer(ControllerLearnTick, 100)
}


ControllerLearnBufferAxisRaw(report, offset, size) {
    if (size = "u8")
        return NumGet(report, offset, "UChar")
    if (size = "u16be")
        return (NumGet(report, offset, "UChar") << 8)
            | NumGet(report, offset + 1, "UChar")
    return NumGet(report, offset, "UShort")
}


; Chooses the field the axis actually occupies, once the whole movement has been
; seen, and converts the observed direction into XInput's convention.
; True when a byte was still moving while the user was holding nothing.
;
; A stick resting at centre jitters in its lowest one or two bits, which is why
; LearnRestNoise exists at all. A motion sensor is different in kind: it streams
; continuously and saturates the whole byte. Counting bits separates the two
; without needing to know which controller this is.
ControllerLearnByteFreeRunning(offset) {
    global LearnRestNoise
    static MIN_FREE_RUNNING_BITS := 4
    mask := NumGet(LearnRestNoise, offset, "UChar")
    bits := 0
    Loop 8 {
        if (mask & (1 << (A_Index - 1)))
            bits += 1
    }
    return bits >= MIN_FREE_RUNNING_BITS
}


; Turns the value census into the set of analogue bytes.
;
; Two conditions, both needed. A wide spread alone would also match a byte that
; happened to hold two far-apart button masks; a large distinct count alone could
; match a counter or timestamp field, which some reports carry. Requiring a byte
; to take many different values ACROSS a wide range is what isolates a real
; analogue control.
ControllerLearnClassifyAnalog() {
    global LearnAnalogValues, LearnAnalogBytes, LearnBaseline
    static MIN_DISTINCT_VALUES := 6
    static MIN_RANGE := 32
    LearnAnalogBytes := Map()
    described := ""
    for offset, values in LearnAnalogValues {
        if (values.Count < MIN_DISTINCT_VALUES)
            continue
        low := 255
        high := 0
        for value in values {
            low := Min(low, value)
            high := Max(high, value)
        }
        if (high - low < MIN_RANGE)
            continue
        LearnAnalogBytes[offset] := true
        described .= (described != "" ? ", " : "") offset
            . " (" values.Count " values, " low "-" high ")"
    }
    LogLine("Learn: analogue bytes = "
        . (described != "" ? described : "none detected")
        . ". Button steps will ignore them.")
    return LearnAnalogBytes.Count
}


ControllerLearnCompleteAxis(step) {
    global LearnCaptureUntil, LearnResultAxes, LearnLastAccepted
    global LearnDetailCtrl, LearnPeak, LearnAxisRejection, LearnLastFriendly
    LearnCaptureUntil := 0
    if ControllerLearnResolveAxis(step) {
        axis := LearnResultAxes[step["name"]]
        LearnLastAccepted := step["name"] " = byte " axis["offset"] " "
            . axis["size"] " neutral " axis["neutral"] " direction "
            . axis["direction"]
        LearnLastFriendly := ControllerLearnFriendlyName(step["name"])
        try LearnDetailCtrl.Text := "Got it — " LearnLastFriendly "."
        LogLine("Learn: " LearnLastAccepted ".")
        SetTimer(ControllerLearnNextStep, -700)
    } else {
        LearnLastAccepted := step["name"] " not detected"
        try LearnDetailCtrl.Text := "Did not see that. Let go of everything, "
            . "then move it as far as it goes and hold it there for a moment."
        LogLine("Learn: " step["name"] " not detected -- "
            . (LearnAxisRejection != "" ? LearnAxisRejection : "no reason recorded")
            . ". Retrying.", "Warning")
        SetTimer(ControllerLearnStartCapture, -900)
    }
}


ControllerLearnCopyReport(data, base, length) {
    report := Buffer(length, 0)
    Loop length
        NumPut("UChar", NumGet(data, base + A_Index - 1, "UChar"),
            report, A_Index - 1)
    return report
}


; Returns four active-high or active-low button entries when the D-pad is made
; from independent bits. A non-regular hat is not guessed into bits: doing so can
; map several directions to the same lowest bit and is worse than leaving it
; explicitly unmapped.
ControllerLearnDpadButtons() {
    global LearnHatValues, LearnResultButtons
    buttons := []
    used := Map()
    for _, button in LearnResultButtons
        used[button["offset"] ":" button["mask"]] := true
    for _, name in ["Up", "Right", "Down", "Left"] {
        if !LearnHatValues.Has(name)
            return 0
        entry := LearnHatValues[name]
        changed := (entry["value"] ^ entry["released"]) & 0xFF
        if (!changed || (changed & (changed - 1)))
            return 0
        key := entry["offset"] ":" changed
        if used.Has(key)
            return 0
        used[key] := true
        buttons.Push(Map(
            "name", name,
            "offset", entry["offset"],
            "mask", changed,
            "pressed", entry["value"] & changed))
    }
    return buttons
}


; Compares one report against the baseline for the current step.
ControllerLearnExamine(data, base, length) {
    global LearnBaseline, LearnStepIndex, LearnResultButtons, LearnResultAxes
    global LearnHatValues, LearnPeak, LearnDetailCtrl, LearnRestNoise
    global LearnAnalogBytes, LearnAnalogValues
    global LearnExcursion, LearnAxisSamples, LearnAxisStarted
    global LearnNoiseBlamed
    step := ControllerLearnSteps()[LearnStepIndex]
    kind := step["kind"]

    ; Census of the values each byte takes while the analogue controls are swept.
    if (kind = "wiggle") {
        Loop length {
            offset := A_Index - 1
            value := NumGet(data, base + offset, "UChar")
            if !LearnAnalogValues.Has(offset)
                LearnAnalogValues[offset] := Map()
            LearnAnalogValues[offset][value] := true
        }
        return
    }

    if (kind = "dpad") {
        ; A D-pad is either four bits or one hat byte, and which it is CANNOT be
        ; decided from a single direction. On a hat, "up" is just a value in a
        ; byte, and its low bit is indistinguishable from a button bit -- on the
        ; ROG Ally itself, hat=1 for up would otherwise be learned as a button at
        ; byte 13 bit 0, and then right (hat=3) would learn the same bit again.
        ;
        ; So each direction is recorded as an (offset, value) pair and the
        ; decision is deferred until all four are known. ControllerLearnHatText
        ; makes it: evenly spaced values on one byte are a hat, anything else
        ; falls back to one bit per direction.
        Loop length {
            offset := A_Index - 1
            now := NumGet(data, base + offset, "UChar")
            was := NumGet(LearnBaseline, offset, "UChar")
            if (now = was)
                continue
            ; Skip bits that were already moving while at rest, and any byte the
            ; opening scan identified as analogue.
            if (LearnAnalogBytes.Has(offset))
                continue
            if ((now ^ was) & NumGet(LearnRestNoise, offset, "UChar"))
                continue
            for _, existing in LearnHatValues {
                if (existing["offset"] = offset && existing["value"] = now)
                    return
            }
            LearnHatValues[step["name"]] := Map("offset", offset, "value", now,
                "released", was)
            ; Mask 0: the whole hat byte must return to its resting value.
            ControllerLearnAccept(step["name"] " = byte " offset " value " now,
                offset, 0, ControllerLearnFriendlyName(step["name"]))
            return
        }
        return
    }

    if (kind = "button") {
        ; A bit whose state differs now and NEVER changed during rest.
        ;
        ; Comparing against the resting transition mask is what keeps analogue
        ; jitter out while still allowing buttons whose pressed state is zero.
        Loop length {
            offset := A_Index - 1
            ; An analogue byte is never a button, however convincing it looks.
            ; A stick nudged during this step changes bits that were clear at
            ; rest, which is precisely the test below -- and on L3/R3 the stick
            ; has to be touched, so this is the common case, not an edge one.
            if (LearnAnalogBytes.Has(offset))
                continue
            now := NumGet(data, base + offset, "UChar")
            was := NumGet(LearnBaseline, offset, "UChar")
            restNoise := NumGet(LearnRestNoise, offset, "UChar")
            changed := (now ^ was) & ~restNoise & 0xFF
            if !changed {
                ; Movement that the rest mask swallowed whole. Reported once per
                ; step, because otherwise this is indistinguishable from a
                ; controller that is not sending anything: the user presses the
                ; button, the wizard sits there, and nothing anywhere says why.
                ;
                ; It happens when a control was held or pressed during the "let
                ; go of everything" countdown -- its bits are recorded as moving
                ; at rest, and every later step skips them for the whole session.
                if ((now ^ was) && !LearnNoiseBlamed) {
                    LearnNoiseBlamed := true
                    LogLine("Learn: byte " offset " moved for " step["name"]
                        . " but every changed bit is masked as rest noise "
                        . "(mask 0x" Format("{:02X}", restNoise) "). Something "
                        . "was held during the rest countdown. Press Start Over "
                        . "and keep hands off the controller until prompted.",
                        "Warning")
                }
                continue
            }
            ; Take the lowest set bit, so a byte carrying several changes at once
            ; still yields one unambiguous mask.
            mask := changed & -changed
            ; Accept the press report itself. The Ally and other change-only
            ; devices send no duplicate reports while a digital control is held.
            ; Rest sampling already removed bits that jitter without a press.
            pressed := now & mask
            ControllerLearnRecordButton(step["name"], offset, mask, pressed)
            return
        }
        return
    }

    ; Axis capture is a gesture: move outward, then return to neutral. Finishing
    ; on the return report gives the next prompt a clean baseline and prevents a
    ; held stick or trigger from spilling into the next reading.
    report := ControllerLearnCopyReport(data, base, length)
    active := ControllerLearnReportAxisActive(report, LearnAxisStarted ? 6 : 12)
    if !LearnAxisStarted {
        if !active
            return
        LearnAxisStarted := true
        try LearnDetailCtrl.Text := "Good — now let it return to the middle."
    } else if !active {
        ControllerLearnCompleteAxis(step)
        return
    }

    LearnAxisSamples.Push(report)
    Loop length {
        offset := A_Index - 1
        delta := Abs(NumGet(report, offset, "UChar")
            - NumGet(LearnBaseline, offset, "UChar"))
        if (delta > NumGet(LearnExcursion, offset, "UChar"))
            NumPut("UChar", delta, LearnExcursion, offset)
    }
    peak := 0
    Loop length
        peak := Max(peak, NumGet(LearnExcursion, A_Index - 1, "UChar") * 256)
    if (peak > LearnPeak) {
        LearnPeak := peak
        try LearnDetailCtrl.Text := "Good — now let it return to the middle."
    }
    ; Once enough travel exists, remember the likely field. This lets the
    ; release test use the decoded 8/16-bit value rather than being fooled by a
    ; wrapping low byte near a 16-bit axis's centre.
    ControllerLearnResolveAxis(step)
}


ControllerLearnFinish() {
    global LearnPromptCtrl, LearnDetailCtrl, LearnProgressCtrl, LearnCaptureUntil
    global LearnResultButtons, LearnResultAxes, LearnHatValues
    LearnCaptureUntil := 0
    SetTimer(ControllerLearnTick, 0)
    try LearnPromptCtrl.Text := "Done — review and save"
    learnedButtons := LearnResultButtons.Length + Min(4, LearnHatValues.Count)
    try LearnProgressCtrl.Text := learnedButtons " buttons and "
        . LearnResultAxes.Count " sticks/triggers set up"
    try LearnDetailCtrl.Text := "Save to start using this controller straight away."
}


; Builds the hat line, or "" when the D-pad was learned as ordinary bits.
;
; The eight-way table is derived from the four cardinals that were observed:
; hats number their positions clockwise from north, so once north and east are
; known the diagonals follow. A hat whose four cardinals are not evenly spaced is
; not one this can describe, and is rejected rather than guessed at.
ControllerLearnHatText() {
    global LearnHatValues
    for _, name in ["Up", "Right", "Down", "Left"] {
        if !LearnHatValues.Has(name)
            return ""
    }
    offset := LearnHatValues["Up"]["offset"]
    released := LearnHatValues["Up"]["released"]
    for _, name in ["Right", "Down", "Left"] {
        if (LearnHatValues[name]["offset"] != offset
            || LearnHatValues[name]["released"] != released)
            return ""
    }
    up := LearnHatValues["Up"]["value"]
    right := LearnHatValues["Right"]["value"]
    down := LearnHatValues["Down"]["value"]
    left := LearnHatValues["Left"]["value"]
    step := right - up
    if (step <= 0 || down - up != step * 2 || left - up != step * 3)
        return ""
    values := []
    mask := 0
    Loop 8 {
        value := up + Round((A_Index - 1) * step / 2)
        if (value < 0 || value > 255)
            return ""
        values.Push(value)
        mask |= value ^ released
    }
    if !mask
        return ""
    ; Store only the hat bits. Many common HID reports put a four-bit hat and
    ; face buttons in the same byte; whole-byte matching would make the D-pad
    ; disappear whenever one of those buttons was held.
    text := offset ":" mask ":" (released & mask)
    for _, value in values
        text .= ":" (value & mask)
    return text
}


ControllerLearnHighByteQuality(offset, sampleCount) {
    global LearnAxisSamples, LearnBaseline
    previous := NumGet(LearnBaseline, offset, "UChar")
    path := 0
    transitions := 0
    endpoint := previous
    Loop sampleCount {
        report := LearnAxisSamples[A_Index]
        value := NumGet(report, offset, "UChar")
        if (value != previous)
            transitions += 1
        path += Abs(value - previous)
        previous := value
        endpoint := value
    }
    endpoint := Abs(endpoint - NumGet(LearnBaseline, offset, "UChar"))
    coherence := endpoint / Max(1, path)
    activity := transitions / Max(1, sampleCount)
    return (0.25 + 0.75 * coherence) * (0.25 + 0.75 * activity)
}


ControllerLearnIdentificationReady() {
    global LearnActive, LearnDevice, LearnIdentifyReady
    global LearnPromptCtrl, LearnDetailCtrl
    if (!LearnActive || LearnDevice)
        return
    LearnIdentifyReady := true
    try LearnPromptCtrl.Text := "Press and release any button to choose the controller"
    try LearnDetailCtrl.Text := "This selects the device; button mapping starts after rest measurement."
}


ControllerLearnLargestExcursion() {
    global LearnExcursion, LearnLength
    largest := 0
    Loop LearnLength
        largest := Max(largest, NumGet(LearnExcursion, A_Index - 1, "UChar"))
    return largest
}


ControllerLearnNextStep() {
    global LearnActive, LearnStepIndex
    if !LearnActive
        return
    steps := ControllerLearnSteps()
    finished := LearnStepIndex
    LearnStepIndex += 1
    ; The four D-pad directions are only meaningful as a set, so they are checked
    ; once the last one is in rather than individually.
    if (finished >= 1 && finished <= steps.Length
        && steps[finished]["kind"] = "dpad"
        && (LearnStepIndex > steps.Length
            || steps[LearnStepIndex]["kind"] != "dpad")) {
        if !ControllerLearnValidateDpad()
            return
    }
    ControllerLearnStartCapture()
}


ControllerLearnRecordButton(name, offset, mask, pressed) {
    global LearnResultButtons
    for _, existing in LearnResultButtons {
        if (existing["name"] = name)
            return
        if (existing["offset"] = offset && existing["mask"] = mask) {
            ; The previous prompt is probably still being held. Do not map two
            ; logical buttons to one physical bit; keep waiting for a new answer.
            return
        }
    }
    LearnResultButtons.Push(Map(
        "name", name, "offset", offset, "mask", mask, "pressed", pressed))
    ControllerLearnAccept(name " = byte " offset " bit 0x"
        . Format("{:02X}", mask) (pressed ? " active-high" : " active-low"),
        offset, mask, ControllerLearnFriendlyName(name))
}


; A failed resolve must leave nothing behind.
;
; This function runs on every report of the gesture, so a provisional answer from
; an earlier report is already sitting in LearnResultAxes when a later one fails.
; Saving that entry would write a field the learner had since REJECTED into the
; profile -- with a neutral and extent measured from a partial sweep, which is a
; direct route to a pointer that will not sit still.
ControllerLearnRejectAxis(step, reason) {
    global LearnResultAxes, LearnAxisRejection
    LearnAxisRejection := reason
    if LearnResultAxes.Has(step["name"])
        LearnResultAxes.Delete(step["name"])
    return false
}


; The identifying control came back up -- or ran out of patience. Either way the
; hold is over and rest measurement can start.
;
; Both routes go through here so the rest phase has exactly one entry point. The
; timeout is not a nicety: a pad that reports only on change and whose release
; report is lost would otherwise leave the wizard waiting forever on a prompt
; that has already been answered, with no clock on screen and no way forward but
; Cancel.
ControllerLearnIdentifyReleased(reason) {
    global LearnActive, LearnIdentifyHoldOffset, LearnIdentifyHoldMask
    global LearnRestSampling, LearnRestCount
    if !LearnActive
        return
    if (LearnIdentifyHoldOffset < 0)
        return
    SetTimer(ControllerLearnIdentifyHoldTimeout, 0)
    LogLine("Learn: identifying control " reason "; measuring rest.")
    LearnIdentifyHoldOffset := -1
    LearnIdentifyHoldMask := 0
    LearnRestSampling := true
    LearnRestCount := 0
    ControllerLearnUpdateUi()
    SetTimer(ControllerLearnBeginSteps, -1800)
}


; The identifying control never came back up. Proceed anyway, and say so.
;
; Measuring rest with it still held is the original defect, so this does not
; pretend the reading is good: it warns, and the rest window that follows will
; record the eventual release as noise exactly as before. That is a worse
; outcome than waiting and a much better one than a wizard that cannot be
; finished.
ControllerLearnIdentifyHoldTimeout() {
    global LearnActive, LearnIdentifyHoldOffset
    if (!LearnActive || LearnIdentifyHoldOffset < 0)
        return
    LogLine("Learn: the identifying control was still held after 4 seconds. "
        . "Measuring rest anyway; let go if the steps behave oddly.", "Warning")
    ControllerLearnIdentifyReleased("timed out while held")
}


; Watches for the accepted control to return to its resting state.
ControllerLearnReleaseCheck(data, base, length) {
    global LearnBaseline, LearnReleaseOffset, LearnReleaseMask, LearnReleaseUntil
    offset := LearnReleaseOffset
    if (offset < 0 || offset >= length)
        return
    now := NumGet(data, base + offset, "UChar")
    was := NumGet(LearnBaseline, offset, "UChar")
    ; A mask of 0 means the whole byte matters, which is the hat case.
    if LearnReleaseMask {
        if ((now & LearnReleaseMask) != (was & LearnReleaseMask))
            return
    } else if (now != was) {
        return
    }
    LearnReleaseOffset := -1
    LearnReleaseMask := 0
    LearnReleaseUntil := 0
    SetTimer(ControllerLearnNextStep, -150)
}


; Feeds one report to the learner. Called from the WM_INPUT handler ahead of the
; normal decode, and only while the wizard is open.
ControllerLearnReport(data, base, length, device) {
    global LearnActive, LearnDevice, LearnDeviceKey, LearnLength, LearnBaseline
    global LearnStepIndex, LearnCaptureUntil, LearnPeak
    global LearnRestNoise, LearnRestSampling, LearnRestCount
    global LearnIdentifyDevices, LearnIdentifyReady
    global LearnIdentifyHoldOffset, LearnIdentifyHoldMask
    global LearnReleaseOffset, LearnStepReports
    global LearnSettleDeadline, LearnLastMotionTick, LearnSettlePrev
    if !LearnActive
        return
    ; The settle gate's clock. While ControllerLearnAwaitQuiet is waiting, every
    ; report is compared with the PREVIOUS one and any difference restarts the
    ; clock; bytes that were already noisy at rest are skipped, because a motion
    ; sensor never stops and waiting for one to go still waits forever.
    ;
    ; The report is not fed to the step machine while this is running. That is
    ; the point: a press made before the prompt settles is discarded rather than
    ; captured as the answer to a step that had not started asking.
    if (LearnSettleDeadline && LearnDevice) {
        if (!LearnSettlePrev || LearnSettlePrev.Size != length) {
            LearnSettlePrev := ControllerLearnCopyReport(data, base, length)
            LearnLastMotionTick := A_TickCount
            return
        }
        Loop length {
            offset := A_Index - 1
            if (IsObject(LearnRestNoise)
                && offset < LearnRestNoise.Size
                && NumGet(LearnRestNoise, offset, "UChar"))
                continue
            if (NumGet(data, base + offset, "UChar")
                != NumGet(LearnSettlePrev, offset, "UChar")) {
                LearnLastMotionTick := A_TickCount
                break
            }
        }
        LearnSettlePrev := ControllerLearnCopyReport(data, base, length)
        return
    }
    ; Select the controller that the user actually operates. RawInput gamepads
    ; often publish idle reports continuously, so locking to the first hDevice
    ; seen makes the prompt meaningless when more than one pad is connected.
    if !LearnDevice {
        if !LearnIdentifyDevices.Has(device) {
            LearnIdentifyDevices[device] := Map(
                "length", length,
                "baseline", ControllerLearnCopyReport(data, base, length),
                "noise", Buffer(length, 0))
            return
        }
        known := LearnIdentifyDevices[device]
        if (known["length"] != length) {
            LearnIdentifyDevices[device] := Map(
                "length", length,
                "baseline", ControllerLearnCopyReport(data, base, length),
                "noise", Buffer(length, 0))
            return
        }
        baseline := known["baseline"]
        noise := known["noise"]
        if !LearnIdentifyReady {
            ; First learn which bits move while every controller is idle. This
            ; prevents 16-bit stick low-byte jitter from selecting the first pad
            ; that happens to publish reports.
            Loop length {
                offset := A_Index - 1
                now := NumGet(data, base + offset, "UChar")
                changed := now ^ NumGet(baseline, offset, "UChar")
                NumPut("UChar", NumGet(noise, offset, "UChar") | changed,
                    noise, offset)
                NumPut("UChar", now, baseline, offset)
            }
            return
        }
        identified := false
        holdOffset := -1
        holdMask := 0
        Loop length {
            offset := A_Index - 1
            now := NumGet(data, base + offset, "UChar")
            was := NumGet(baseline, offset, "UChar")
            changed := (now ^ was) & ~NumGet(noise, offset, "UChar") & 0xFF
            if changed {
                identified := true
                holdOffset := offset
                holdMask := changed
                break
            }
        }
        ; Some controllers publish only on state changes: one press report, then
        ; silence while the button remains held. Idle noise was measured before
        ; the prompt, so the first clean change is the only reliable selector.
        if !identified
            return
        LearnDevice := device
        LearnDeviceKey := RawInputDeviceKey(device)
        LearnLength := length
        ; THE IDLE REPORT, not the one that completed identification.
        ;
        ; Identification fires on the report where something CHANGED, and for
        ; almost every pad that is the button going DOWN. Copying that report
        ; made "the identifying button held" the resting state: it then differed
        ; from rest in every later report, so it read as permanently pressed for
        ; the rest of the wizard, was saved into the profile's neutral, and the
        ; controller came out of the wizard with a button stuck down. On a pad
        ; that does report at rest the release instead landed in LearnRestNoise,
        ; which is quieter and just as wrong -- that bit is then skipped by every
        ; later step, silently.
        ;
        ; `baseline` is the idle report this device was publishing before the
        ; press. It stopped being updated the moment LearnIdentifyReady was set,
        ; so it is exactly the pre-press state, and it was already being kept for
        ; the noise measurement. It was there the whole time; it was simply
        ; thrown away in favour of the report that happened to arrive last.
        LearnBaseline := ControllerLearnCopyReport(baseline, 0, length)
        LearnRestNoise := Buffer(length, 0)
        ; And nothing is measured until that control comes back up. The step
        ; captures have always done this -- see LearnReleaseOffset, "a held
        ; button cannot answer the next prompt" -- and identification is the one
        ; place the same rule was never applied, even though it is the only
        ; prompt whose answer the user is still holding when the next one
        ; appears.
        LearnIdentifyHoldOffset := holdOffset
        LearnIdentifyHoldMask := holdMask
        SetTimer(ControllerLearnIdentifyHoldTimeout, -4000)
        LogLine("Learn: capturing from device 0x" Format("{:X}", device)
            . " key=" (LearnDeviceKey != "" ? LearnDeviceKey : "unknown")
            . " reportLength=" length "; waiting for byte " holdOffset
            . " bit 0x" Format("{:02X}", holdMask) " to be released.")
        ControllerLearnUpdateUi()
        return
    }
    if (device != LearnDevice || length != LearnLength)
        return
    ; The identifying control has to come back up before anything is measured.
    ; Until it does, every report is one where it is still held, and rest is the
    ; one thing that must not be measured from those.
    if (LearnIdentifyHoldOffset >= 0) {
        if (LearnIdentifyHoldOffset < length) {
            now := NumGet(data, base + LearnIdentifyHoldOffset, "UChar")
            was := NumGet(LearnBaseline, LearnIdentifyHoldOffset, "UChar")
            if ((now & LearnIdentifyHoldMask) != (was & LearnIdentifyHoldMask))
                return
        }
        ControllerLearnIdentifyReleased("released")
        return
    }
    ; Rest sampling. The baseline is every detection's reference point, so it is
    ; taken while the user has explicitly let go, not from the report that
    ; happened to identify the device -- that one arrived with a button held.
    if LearnRestSampling {
        LearnRestCount += 1
        Loop length {
            offset := A_Index - 1
            value := NumGet(data, base + A_Index - 1, "UChar")
            ; The first explicit rest report refreshes the earlier idle
            ; baseline. Only later rest-to-rest changes are noise.
            if (LearnRestCount > 1) {
                changed := value ^ NumGet(LearnBaseline, offset, "UChar")
                NumPut("UChar", NumGet(LearnRestNoise, offset, "UChar") | changed,
                    LearnRestNoise, offset)
            }
            NumPut("UChar", value, LearnBaseline, offset)
        }
        return
    }
    ; A detected control is waiting to be released; nothing else is examined until
    ; it is, so a held button cannot answer the next prompt.
    if (LearnReleaseOffset >= 0) {
        ControllerLearnReleaseCheck(data, base, length)
        return
    }
    if (LearnStepIndex < 1 || !LearnCaptureUntil)
        return
    LearnStepReports += 1
    ControllerLearnExamine(data, base, length)
}


; True while the current analogue control is away from rest. A resolved 16-bit
; field is checked as a whole because its low byte can wrap at centre. For an
; 8-bit or not-yet-resolved field, clean unclaimed byte movement is safer: an
; early low-byte candidate must not look released merely because it wrapped
; through its resting value halfway across a 16-bit sweep.
ControllerLearnReportAxisActive(report, byteThreshold) {
    global LearnBaseline, LearnResultButtons, LearnResultAxes, LearnHatValues
    global LearnRestNoise, LearnStepIndex, LearnLength
    step := ControllerLearnSteps()[LearnStepIndex]
    if LearnResultAxes.Has(step["name"]) {
        axis := LearnResultAxes[step["name"]]
        if (axis["size"] != "u8") {
            raw := ControllerLearnBufferAxisRaw(
                report, axis["offset"], axis["size"])
            return Abs(raw - axis["neutral"]) >= 1500
        }
    }

    claimed := Map()
    for _, button in LearnResultButtons
        claimed[button["offset"]] := true
    for _, hat in LearnHatValues
        claimed[hat["offset"]] := true
    Loop LearnLength {
        offset := A_Index - 1
        if claimed.Has(offset)
            continue
        now := NumGet(report, offset, "UChar")
        was := NumGet(LearnBaseline, offset, "UChar")
        cleanChange := (now ^ was)
            & ~NumGet(LearnRestNoise, offset, "UChar") & 0xFF
        if (cleanChange && Abs(now - was) >= byteThreshold)
            return true
    }
    return false
}


; allowRestNoisy is set only by this function's own single retry -- see the
; rejection path at the end.
ControllerLearnResolveAxis(step, allowRestNoisy := false) {
    global LearnAxisUnresolvable
    global LearnAxisSamples, LearnExcursion, LearnLength
    global LearnResultAxes, LearnResultButtons, LearnHatValues, LearnPeak
    global LearnAxisRejection
    static MIN_NORMALISED_DELTA := 4000
    static MIN_BYTE_EXCURSION := 8
    static MIN_PAIR_BALANCE := 0.20

    LearnAxisRejection := ""
    if (LearnAxisSamples.Length = 0)
        return ControllerLearnRejectAxis(step, "no reports were captured")

    ; Buttons and the D-pad own their bytes. Excluding them prevents an
    ; accidentally held button from looking like a full-scale 8-bit trigger.
    claimed := Map()
    for _, button in LearnResultButtons
        claimed[button["offset"]] := true
    for _, hat in LearnHatValues
        claimed[hat["offset"]] := true
    ; Motion sensors own their bytes too, and they never stop moving. On an
    ; 8BitDo Ultimate 2 the 34-byte report carries six 16-bit motion axes that
    ; stream at ~1 kHz, so twelve bytes sweep their full range continuously
    ; whatever the user does. They out-travel the real stick on every step and
    ; were winning the score: measured on hardware, all four sticks failed with
    ; "byte 22 rests at 0% of range", and RT was learned onto that same motion
    ; byte because a trigger legitimately rests at an end of range and so had no
    ; equivalent sanity check to save it.
    ;
    ; Excluded rather than down-ranked because a motion byte can beat a stick on
    ; any score built from travel alone.
    excludedNoisy := 0
    if !allowRestNoisy {
        Loop LearnLength {
            offset := A_Index - 1
            if (!claimed.Has(offset) && ControllerLearnByteFreeRunning(offset)) {
                claimed[offset] := true
                excludedNoisy += 1
            }
        }
    }
    ; A stick cannot share bytes with another stick. Without this the four stick
    ; steps were resolved independently and could land on overlapping fields --
    ; measured once as LX=1, LY=2, RX=4, RY=3, which cannot describe any real
    ; report. Triggers are deliberately exempt: a shared trigger axis is a real
    ; layout, and LT and RT resolving to the same offset is the right answer.
    ;
    ; The step's OWN entry must be excluded. This function runs again on every
    ; report of the gesture, and each run writes its answer into LearnResultAxes
    ; so that ControllerLearnReportAxisActive can watch the decoded field rather
    ; than raw bytes. Without this skip, the second report claimed the very bytes
    ; the first report had just chosen, so the field became unavailable to itself:
    ; every stick then failed with "Not enough travel" no matter how far it was
    ; pushed. Triggers were unaffected, because they are exempt below -- which is
    ; exactly the pattern that was reported from hardware.
    static STICKS := Map("LX", true, "LY", true, "RX", true, "RY", true)
    if STICKS.Has(step["name"]) {
        for name, learned in LearnResultAxes {
            if (!STICKS.Has(name) || name = step["name"])
                continue
            claimed[learned["offset"]] := true
            if (learned["size"] != "u8")
                claimed[learned["offset"] + 1] := true
        }
    }

    best8 := 0
    Loop LearnLength {
        offset := A_Index - 1
        if claimed.Has(offset)
            continue
        if (NumGet(LearnExcursion, offset, "UChar") < MIN_BYTE_EXCURSION)
            continue
        candidate := ControllerLearnAxisStats(offset, "u8")
        if (candidate["delta"] < MIN_NORMALISED_DELTA)
            continue
        if (!IsObject(best8) || candidate["score"] > best8["score"])
            best8 := candidate
    }

    best16 := 0
    if (LearnLength >= 2) {
        Loop LearnLength - 1 {
            offset := A_Index - 1
            if (claimed.Has(offset) || claimed.Has(offset + 1))
                continue
            firstExcursion := NumGet(LearnExcursion, offset, "UChar")
            secondExcursion := NumGet(LearnExcursion, offset + 1, "UChar")
            if (firstExcursion < MIN_BYTE_EXCURSION
                || secondExcursion < MIN_BYTE_EXCURSION)
                continue
            ; Two adjacent 8-bit axes can both drift a little. A real 16-bit
            ; field moves both bytes materially over a full sweep.
            balance := Min(firstExcursion, secondExcursion)
                / Max(firstExcursion, secondExcursion)
            if (balance < MIN_PAIR_BALANCE)
                continue
            ; LITTLE-ENDIAN ONLY. USB HID specifies little-endian for multi-byte
            ; fields, so a big-endian gamepad axis is not a thing that exists --
            ; and offering it as a candidate was actively harmful. Measured on
            ; hardware: at rest the low bytes of every stick jitter constantly
            ; while the high bytes sit still, so a big-endian read promotes that
            ; jitter to the high byte. RX was learned as u16be with a neutral of
            ; 21884 against an actual rest value of 128, which pinned the right
            ; stick at about +19300 and sent the pointer across the screen.
            ;
            ; RawInputProfileDecode still UNDERSTANDS u16be, so a hand-written
            ; profile can use it. The learner simply never guesses it.
            candidate := ControllerLearnAxisStats(offset, "u16le")
            if (candidate["delta"] < MIN_NORMALISED_DELTA
                || candidate["coherence"] < 0.55)
                continue
            if (!IsObject(best16) || candidate["score"] > best16["score"])
                best16 := candidate
        }
    }

    ; Prefer a coherent 16-bit field even when one constituent byte has a larger
    ; endpoint delta. That is normal at 0xFFFF: the low byte moved 255 counts,
    ; while the actual 16-bit field moved about half its range.
    chosen := 0
    if (IsObject(best16)
        && (!IsObject(best8) || best16["score"] >= best8["score"] * 0.45)) {
        chosen := best16
    } else if IsObject(best8) {
        chosen := best8
    }
    if !IsObject(chosen) {
        ; Preference, not prohibition -- FOR STICKS. If nothing survives the
        ; motion filter, try once more with those bytes allowed back in: a
        ; controller whose sticks really do jitter across several bits at rest
        ; must still be learnable.
        ;
        ; A TRIGGER never gets that retry, and the reason is written twenty lines
        ; up: a stick is saved by the rest-at-centre check, because a
        ; self-centring stick cannot rest anywhere else, so a motion byte that
        ; wins on travel is still thrown out for resting at 0% of range. A
        ; trigger legitimately rests at an end of range and so has no equivalent
        ; sanity check. Re-admitting motion bytes for a trigger hands it the one
        ; step where nothing downstream can catch the mistake.
        ;
        ; Measured on an 8BitDo Ultimate 2 in DirectInput mode, where the gyro is
        ; live: 12 of 34 bytes moved at rest, 11 were correctly excluded, LT had
        ; no candidate outside them, and the retry bound LT to byte 25 -- a
        ; motion axis, recorded as u16le neutral 65522. The profile saved, and
        ; the rest check immediately reported LT pegged at 255 with nothing
        ; touched, which is a pointer that runs across the screen.
        ;
        ; Refusing is the better failure. An unlearned trigger is one missing
        ; control that the user can retry or map elsewhere; a trigger bound to a
        ; gyro is a profile that cannot be used at all.
        isTrigger := (step["name"] = "LT" || step["name"] = "RT")
        if (!allowRestNoisy && excludedNoisy > 0 && !isTrigger) {
            LogLine("Learn: no candidate outside the " excludedNoisy
                . " free-running byte(s); retrying with them included.")
            return ControllerLearnResolveAxis(step, true)
        }
        if (!allowRestNoisy && excludedNoisy > 0 && isTrigger) {
            LearnAxisUnresolvable := true
            LogLine("Learn: " step["name"] " has no candidate outside the "
                . excludedNoisy . " free-running byte(s). NOT retrying with them "
                . "included -- a trigger rests at an end of range, so a motion "
                . "byte bound here would read as fully pressed and could not be "
                . "detected as wrong. Skip this step or re-run it holding the "
                . "controller still.", "Warning")
        }
        return ControllerLearnRejectAxis(step,
            "no unclaimed field moved far enough (largest byte excursion "
            . ControllerLearnLargestExcursion() " counts)")
    }
    ; "want" is the sign XInput uses for the direction that was asked for. If the
    ; hardware moves the same way, the multiplier is +want; if it counts the
    ; other way, -want.
    ; A stick rests at the CENTRE of its range. That is physics, not a heuristic:
    ; a self-centring stick cannot rest anywhere else. Measured on hardware, all
    ; four sticks and the shared trigger sat between 47.6% and 50.4% of full scale
    ; at rest. So a candidate field whose rest value is nowhere near the middle is
    ; not the field this axis lives in -- most often it means a neighbouring
    ; axis's bytes were picked up instead.
    ;
    ; Triggers are exempt: a separate trigger legitimately rests at zero, and only
    ; a shared one rests at mid-scale.
    static STICK_NAMES := Map("LX", true, "LY", true, "RX", true, "RY", true)
    if STICK_NAMES.Has(step["name"]) {
        fullScale := chosen["size"] = "u8" ? 255 : 65535
        centreFraction := chosen["neutral"] / fullScale
        if (centreFraction < 0.35 || centreFraction > 0.65) {
            return ControllerLearnRejectAxis(step,
                "byte " chosen["offset"] " " chosen["size"] " rests at "
                . Round(centreFraction * 100) "% of range, and a stick rests at "
                . "the centre")
        }
    }
    ; decoded = (raw - neutral) * k, and at the prompted extreme that must carry
    ; the sign `want`. (raw - neutral) has sign s there, so k = want * s.
    want := step["want"]
    direction := (chosen["raw"] < chosen["neutral"]) ? -want : want
    LearnResultAxes[step["name"]] := Map(
        "offset", chosen["offset"],
        "size", chosen["size"],
        "neutral", chosen["neutral"],
        "direction", direction,
        "extent", Max(1, chosen["extent"]))
    LearnPeak := chosen["delta"]
    return true
}


ControllerLearnRestart() {
    global LearnDevice, LearnDeviceKey, LearnLength, LearnBaseline
    global LearnIdentifyHoldOffset, LearnIdentifyHoldMask
    global LearnRestNoise, LearnRestSampling, LearnRestCount
    global LearnStepIndex, LearnResultButtons, LearnResultAxes
    global LearnHatValues, LearnCaptureUntil
    global LearnLastAccepted, LearnLastFriendly
    global LearnIdentifyDevices, LearnIdentifyReady
    global LearnAnalogBytes, LearnAnalogValues, LearnDpadRetries
    global LearnSettleDeadline, LearnSettleDone
    LearnAnalogBytes := Map()
    LearnAnalogValues := Map()
    LearnDpadRetries := 0
    LearnDevice := 0
    LearnDeviceKey := ""
    LearnLength := 0
    LearnBaseline := 0
    LearnRestNoise := 0
    LearnRestSampling := false
    LearnRestCount := 0
    LearnStepIndex := 0
    LearnResultButtons := []
    LearnResultAxes := Map()
    LearnHatValues := Map()
    LearnLastAccepted := ""
    LearnLastFriendly := ""
    LearnCaptureUntil := 0
    LearnIdentifyDevices := Map()
    LearnIdentifyReady := false
    LearnIdentifyHoldOffset := -1
    LearnIdentifyHoldMask := 0
    SetTimer(ControllerLearnTick, 0)
    SetTimer(ControllerLearnBeginSteps, 0)
    SetTimer(ControllerLearnNextStep, 0)
    ; Start Over is most often pressed DURING one of the pauses that arms this,
    ; so leaving it pending meant the old step restarting on top of the fresh
    ; session -- or firing at LearnStepIndex 0 and throwing.
    SetTimer(ControllerLearnStartCapture, 0)
    SetTimer(ControllerLearnSettleTick, 0)
    LearnSettleDeadline := 0
    LearnSettleDone := false
    SetTimer(ControllerLearnIdentificationReady, -1200)
    ControllerLearnUpdateUi()
}


; Writes the learned profile and refreshes the decoder cache immediately.
ControllerLearnSave() {
    global LearnDeviceKey, LearnLength, LearnResultButtons, LearnResultAxes
    global LearnHatValues, LearnDevice, LearnPromptCtrl, LearnDetailCtrl
    ; Both trees declare ScriptPid; the staged commit names its work file after
    ; it so an abandoned one can be told from a live one.
    global ScriptPid
    if (LearnLength <= 0 || !LearnDevice) {
        TopmostMsgBox("No controller was identified yet.", "Learn controller", "Iconx")
        return
    }
    if (LearnDeviceKey = "")
        LearnDeviceKey := RawInputDeviceKey(LearnDevice, true)
    ; Windows will not identify this device by any of the three routes. Rather than
    ; discard a completed wizard, save the profile keyed on report length -- the
    ; same thing the built-in layout matches on, so nothing is made less safe.
    identityFallback := false
    if (LearnDeviceKey = "") {
        LogLine("Learn: reports were captured from device 0x"
            . Format("{:X}", LearnDevice)
            . ", but Windows returned no device path, HID VID/PID, or "
            . "preparsed descriptor. Saving keyed on the "
            . LearnLength "-byte report length instead.",
            "Warning")
        LearnDeviceKey := ControllerProfileLengthKey(LearnLength)
        identityFallback := true
    }
    if (LearnResultButtons.Length = 0 && LearnResultAxes.Count = 0
        && LearnHatValues.Count = 0) {
        TopmostMsgBox("Nothing was learned, so there is no profile to save.",
            "Learn controller", "Iconx")
        return
    }
    path := ControllerProfilePath()
    ; A hat is only written when the four directions form an evenly spaced
    ; sequence on one byte. Otherwise the D-pad is bits, and the values recorded
    ; per direction become ordinary button entries.
    hatText := ControllerLearnHatText()
    buttons := LearnResultButtons.Clone()
    if (hatText = "") {
        dpadButtons := ControllerLearnDpadButtons()
        if IsObject(dpadButtons) {
            for _, button in dpadButtons
                buttons.Push(button)
        } else if (LearnHatValues.Count > 0) {
            LogLine("Learn: D-pad values were neither a regular hat nor four "
                . "independent bits; leaving the D-pad unmapped.", "Warning")
        }
    }
    buttonText := ""
    for _, button in buttons {
        buttonText .= (buttonText != "" ? "|" : "")
            . button["name"] ":" button["offset"] ":" button["mask"]
            . ":" button["pressed"]
    }
    axisText := ""
    for name, axis in LearnResultAxes {
        axisText .= (axisText != "" ? "|" : "")
            . name ":" axis["offset"] ":" axis["size"] ":" axis["neutral"]
            . ":" axis["direction"] ":" axis["extent"]
    }
    ; SIX keys or none. These were six separate IniWrite calls, and a profile is
    ; only meaningful as a set: ReportLength decides whether it is even
    ; consulted, and Buttons, Axes and Hat are what it decodes with. A failure
    ; partway left a profile carrying some of them, which the loader accepts as
    ; long as any one of buttons, hat or axes survived -- so the controller comes
    ; back with, say, its buttons and no sticks, or sticks and no triggers, and
    ; behaves strangely for a reason nothing reports.
    ;
    ; Staged through the same commit the settings file uses: it writes into a
    ; copy and moves it over the original, so the profile on disk is either the
    ; one that was just learned or the one that was there before.
    if !CommitIniChangesAt(path, ScriptPid, [
        Map("section", LearnDeviceKey, "key", "ReportLength",
            "value", LearnLength),
        Map("section", LearnDeviceKey, "key", "Name",
            "value", ShortenText(RawInputDeviceName(LearnDevice), 120)),
        Map("section", LearnDeviceKey, "key", "Buttons", "value", buttonText),
        Map("section", LearnDeviceKey, "key", "Axes", "value", axisText),
        Map("section", LearnDeviceKey, "key", "Hat", "value", hatText),
        ; Recorded so a length-keyed profile is identifiable as the fallback it is.
        Map("section", LearnDeviceKey, "key", "IdentityFallback",
            "value", identityFallback ? "length" : "device")]) {
        TopmostMsgBox("The profile could not be saved. Nothing was changed — the "
            . "controller is still using whatever it used before.`n`nThe log has "
            . "the reason.", "Learn controller", "Iconx")
        return
    }
    LogLine("Learn: saved profile '" LearnDeviceKey "' with " buttons.Length
        . " buttons, " LearnResultAxes.Count " axes, D-pad as "
        . (hatText != "" ? "a hat" : "bits") ".")
    if !IsObject(LoadControllerProfile(LearnDeviceKey, true)) {
        TopmostMsgBox("The profile was written but did not pass validation. Check "
            . ControllerProfilePath() " and the log before trying again.",
            "Learn controller", "Iconx")
        return
    }
    RawInputResetDeviceLock("controller profile saved")
    CloseControllerLearner()
    ; A bad axis reading does not fail quietly -- it drives the pointer across the
    ; screen and makes the machine hard to use. Verify the profile against the
    ; controller at rest before leaving the user with it.
    ControllerProfileRestCheckBegin()
    TopmostMsgBox("Profile saved and activated for " LearnDeviceKey ".",
        "Learn controller", "Iconi")
}


ControllerLearnSkip() {
    global LearnActive, LearnStepIndex, LearnLastAccepted, LearnResultAxes
    ; The upper bound matters as much as the lower one. ControllerLearnNextStep
    ; increments unconditionally, so after the final step LearnStepIndex sits one
    ; past the end while the wizard finishes and saves. Skip is a GUI button and
    ; can be clicked inside that window, which indexed the step array out of
    ; range and threw "Invalid index" on a controller whose last steps were being
    ; skipped anyway.
    if (!LearnActive || LearnStepIndex < 1
        || LearnStepIndex > ControllerLearnSteps().Length)
        return
    LogLine("Learn: step " LearnStepIndex " skipped.")
    step := ControllerLearnSteps()[LearnStepIndex]
    ; Skipping mid-gesture must discard the provisional answer too. It was
    ; measured from an incomplete sweep, so its neutral and extent are both wrong,
    ; and a wrong extent is what sends the pointer across the screen.
    if (step["kind"] = "axis" && LearnResultAxes.Has(step["name"]))
        LearnResultAxes.Delete(step["name"])
    LearnLastAccepted := step["name"] " skipped"
    ControllerLearnNextStep()
}


; Wait for the pad to actually stop before opening a capture window.
;
; EVERY OTHER PAUSE IN THIS WIZARD IS A FIXED DELAY, and they are wildly uneven:
; 1800ms after the identifying control is released, 700 after an axis completes,
; 600 after the analogue scan, 150 between digital steps. Not one of them asks
; whether the controller has stopped moving -- each is a guess about how fast a
; person lets go, and the 600 after the analogue scan is the tightest guess in
; front of the one step where both thumbs are demonstrably still moving and a
; sprung stick is still returning to centre. Reported from hardware: press A too
; soon after that step and the run is spoiled; pause first and it completes.
;
; A settled pad is a fact this code can read, so it reads it instead of guessing.
;
; Quiet is measured against the PREVIOUS REPORT rather than the baseline, and
; bytes already known to be noisy at rest are ignored -- LearnRestNoise exists
; because a motion sensor never stops streaming, and waiting for one of those to
; go still would wait forever.
;
; The clock is wall time since the last CHANGE, not a count of quiet reports.
; Many pads report only on change, so "no report at all" is the quietest a pad
; can be and counting arrivals would never advance for them.
;
; Bounded, like every other wait here: after LEARN_SETTLE_LIMIT_MS it proceeds
; anyway and says so in the log, because a wizard that cannot be finished is
; worse than one that captures a slightly noisy step.
ControllerLearnAwaitQuiet() {
    global LearnSettleDeadline, LearnLastMotionTick, LearnSettleDone
    global LearnSettlePrev, LearnSettleNoisy, LearnDetailCtrl, LearnLength
    static LEARN_SETTLE_LIMIT_MS := 2500
    if LearnSettleDone {
        LearnSettleDone := false
        if LearnSettleNoisy {
            LearnSettleNoisy := false
            LogLine("Learn: the controller never went quiet; capturing anyway. "
                . "If this step misreads, let go of everything and retry it.",
                "Warning")
        }
        return false
    }
    LearnSettlePrev := 0
    LearnLastMotionTick := A_TickCount
    LearnSettleDeadline := A_TickCount + LEARN_SETTLE_LIMIT_MS
    try LearnDetailCtrl.Text := "Let go of everything — waiting for the "
        . "controller to settle…"
    SetTimer(ControllerLearnSettleTick, 60)
    return true
}


; Polls the quiet clock ControllerLearnReport keeps, and opens the capture window
; when it has run long enough -- or when the bound is reached.
ControllerLearnSettleTick() {
    global LearnActive, LearnLastMotionTick, LearnSettleDeadline
    global LearnSettleDone, LearnSettleNoisy
    static LEARN_QUIET_MS := 450
    if !LearnActive {
        SetTimer(ControllerLearnSettleTick, 0)
        return
    }
    timedOut := A_TickCount >= LearnSettleDeadline
    if (A_TickCount - LearnLastMotionTick < LEARN_QUIET_MS && !timedOut)
        return
    SetTimer(ControllerLearnSettleTick, 0)
    LearnSettleNoisy := timedOut
    LearnSettleDone := true
    ControllerLearnStartCapture()
}


ControllerLearnStartCapture() {
    global LearnCaptureUntil, LearnPeak, LearnPromptCtrl, LearnProgressCtrl
    global LearnStepIndex, LearnDetailCtrl, LearnLength
    global LearnExcursion, LearnAxisSamples, LearnAxisStarted, LearnResultAxes
    global LearnLastAccepted, LearnAxisUnresolvable, LearnNoiseBlamed
    global LearnLastFriendly
    global LearnReleaseOffset, LearnReleaseMask, LearnReleaseUntil
    global LearnStepReports, LearnActive
    ; This runs from a one-shot timer armed 900 to 1500 ms earlier -- after an
    ; axis completes, after a step times out, after the D-pad retry. Any of
    ; those can be outlived by Start Over or by the window closing, and both of
    ; those set LearnStepIndex back to 0, which makes steps[LearnStepIndex] an
    ; invalid index rather than a missing one.
    ;
    ; Both callers cancel the timer now, but the guard stays: the next person to
    ; arm this from somewhere new should not have to remember a fourth cancel.
    if (!LearnActive || LearnStepIndex < 1)
        return
    steps := ControllerLearnSteps()
    if (LearnStepIndex > steps.Length) {
        ControllerLearnFinish()
        return
    }
    ; Before anything is armed, and before the prompt changes: a prompt that
    ; appears while the sticks are still moving is the invitation to answer it
    ; too early. ControllerLearnSettleTick re-enters here when the pad is quiet.
    if ControllerLearnAwaitQuiet()
        return
    step := steps[LearnStepIndex]
    LearnPeak := 0
    ; Per step, not per wizard: a refusal that cannot be retried belongs to the
    ; step that earned it, and Start Over must clear it.
    LearnAxisUnresolvable := false
    LearnNoiseBlamed := false
    ; Any release the previous step was waiting on is no longer relevant; Skip and
    ; Start Over both arrive here.
    LearnReleaseOffset := -1
    LearnReleaseMask := 0
    LearnReleaseUntil := 0
    LearnStepReports := 0
    LearnExcursion := Buffer(Max(1, LearnLength), 0)
    LearnAxisSamples := []
    LearnAxisStarted := false
    if (step["kind"] = "axis" && LearnResultAxes.Has(step["name"]))
        LearnResultAxes.Delete(step["name"])
    ; The axis deadline is only a retry watchdog. Normal completion happens when
    ; the requested control returns to neutral.
    ; The scan is a fixed observation window rather than something that can be
    ; "answered", so it runs on a timer of its own.
    if (step["kind"] = "wiggle") {
        LearnCaptureUntil := A_TickCount + 12000
    } else if (step["kind"] = "axis") {
        LearnCaptureUntil := A_TickCount + 30000
    } else if step.Has("optional") {
        ; A control many pads simply do not have gets a shorter window, so it
        ; cannot stall the steps after it.
        ;
        ; NO STEP DECLARES THIS TODAY. It existed for the Guide button, which has
        ; been removed -- Windows usually swallows that press, and when it does
        ; not it opens Game Bar over the wizard. The mechanism is kept because it
        ; is four lines and the next control of that kind will want it; without
        ; it, such a step would silently take the full twenty seconds.
        LearnCaptureUntil := A_TickCount + 8000
    } else {
        LearnCaptureUntil := A_TickCount + 20000
    }
    try LearnPromptCtrl.Text := step["prompt"]
    try LearnProgressCtrl.Text := "Step " LearnStepIndex " of " steps.Length
    ; Braces required: a braceless `if` body that is a `try` lets the following
    ; `else` bind to the try, which is a syntax error without a catch.
    if (step["kind"] = "axis") {
        try LearnDetailCtrl.Text := "Move it as far as it goes, then let it spring back."
    } else {
        detail := LearnLastFriendly != "" ? "Last one: " LearnLastFriendly
            : "Waiting for you to press it..."
        try LearnDetailCtrl.Text := detail
    }
}


; The prompts, in order. Buttons first: they are unambiguous and confirm the
; report is being read correctly before anything subtler is attempted.
ControllerLearnSteps() {
    static steps := [
        ; Analogue bytes are found FIRST, and every later button step ignores
        ; them.
        ;
        ; Without this, a stick that moves even slightly during a button step is
        ; read as the button. At rest LX is 0x8000, so its low byte is 0x00; nudge
        ; the stick and that byte becomes something like 0x40 -- a bit that was
        ; never set at rest, which is exactly the test a button has to pass. It is
        ; worst on L3 and R3, where the stick must be touched to click it in.
        Map("kind", "wiggle", "name", "Analogue scan",
            "prompt", "Roll BOTH sticks around their full range, squeeze BOTH "
                . "triggers, then let go of everything"),
        Map("kind", "button", "name", "A", "prompt", "Press and release the A button"),
        Map("kind", "button", "name", "B", "prompt", "Press and release the B button"),
        Map("kind", "button", "name", "X", "prompt", "Press and release the X button"),
        Map("kind", "button", "name", "Y", "prompt", "Press and release the Y button"),
        Map("kind", "button", "name", "LB", "prompt", "Press and release the LEFT bumper"),
        Map("kind", "button", "name", "RB", "prompt", "Press and release the RIGHT bumper"),
        Map("kind", "button", "name", "View", "prompt", "Press and release the View / Back button"),
        Map("kind", "button", "name", "Menu", "prompt", "Press and release the Menu / Start button"),
        Map("kind", "button", "name", "L3",
            "prompt", "Click the LEFT stick in, then release"),
        Map("kind", "button", "name", "R3",
            "prompt", "Click the RIGHT stick in, then release"),
        ; NO GUIDE STEP. Asking for it did more harm than the mapping was worth.
        ;
        ; Windows usually swallows the Guide/Xbox button before it reaches the HID
        ; report, so the step normally learned nothing and simply waited. When the
        ; press DOES get through to Windows it opens Game Bar or the Xbox app over
        ; the wizard, which takes the foreground away mid-mapping -- the wizard is
        ; asking for a button whose most likely effect is to interrupt it.
        ;
        ; Nothing is lost that was working: the button is consumed as bit 0x0400
        ; and mapped to Y.Short, and XInput still supplies that bit through
        ; XInputGetStateEx for pads that report it. Only the RawInput path stops
        ; learning it, and that is the path where it was rarely captured anyway.
        ;
        ; The 0x0400 entry in the name-to-bit table stays: profiles learned before
        ; this still carry a Guide line and must keep decoding.
        Map("kind", "dpad", "name", "Up", "prompt", "Press and release the D-pad UP"),
        Map("kind", "dpad", "name", "Right", "prompt", "Press and release the D-pad RIGHT"),
        Map("kind", "dpad", "name", "Down", "prompt", "Press and release the D-pad DOWN"),
        Map("kind", "dpad", "name", "Left", "prompt", "Press and release the D-pad LEFT"),
        ; "want" is the sign XInput expects for the direction being asked for, so
        ; the learned multiplier lands in XInput's convention whichever way the
        ; hardware happens to count. Sticks are asked for LEFT, where XInput is
        ; negative, and UP, where XInput is positive -- opposite signs for what
        ; feels like the same question, which is exactly the sort of thing worth
        ; writing down rather than rediscovering.
        Map("kind", "axis", "name", "LX", "want", -1,
            "prompt", "Move the LEFT stick fully LEFT, then RELEASE it"),
        Map("kind", "axis", "name", "LY", "want", 1,
            "prompt", "Move the LEFT stick fully UP, then RELEASE it"),
        Map("kind", "axis", "name", "RX", "want", -1,
            "prompt", "Move the RIGHT stick fully LEFT, then RELEASE it"),
        Map("kind", "axis", "name", "RY", "want", 1,
            "prompt", "Move the RIGHT stick fully UP, then RELEASE it"),
        Map("kind", "axis", "name", "LT", "want", 1,
            "prompt", "Squeeze the LEFT trigger fully, then RELEASE it"),
        Map("kind", "axis", "name", "RT", "want", 1,
            "prompt", "Squeeze the RIGHT trigger fully, then RELEASE it")
    ]
    return steps
}


; Analogue steps normally finish on release. This timer only recovers from an
; incomplete gesture instead of silently advancing with a held value.
ControllerLearnTick() {
    global LearnActive, LearnCaptureUntil, LearnStepIndex
    global LearnLastAccepted, LearnDetailCtrl, LearnProgressCtrl
    global LearnAxisUnresolvable
    global LearnReleaseOffset, LearnReleaseMask, LearnReleaseUntil
    global LearnStepReports, LearnCountdownCtrl
    if !LearnActive
        return
    ; The countdown, and live evidence that reports are arriving at all. Without
    ; the latter, a step that rejects everything looks identical to a controller
    ; that has gone silent.
    if LearnCaptureUntil {
        try LearnCountdownCtrl.Text := Max(0,
            Round((LearnCaptureUntil - A_TickCount) / 1000))
    } else {
        try LearnCountdownCtrl.Text := ""
    }
    if (LearnStepIndex >= 1 && LearnCaptureUntil) {
        steps := ControllerLearnSteps()
        if (LearnStepIndex <= steps.Length) {
            ; The raw report count is the only live proof the controller is
            ; talking to us at all, so it stays -- worded as listening rather
            ; than as a protocol detail.
            try LearnProgressCtrl.Text := "Step " LearnStepIndex " of "
                . steps.Length (LearnStepReports > 0
                    ? "  -  controller is responding" : "  -  waiting...")
        }
    }
    ; A release we never saw. Advance anyway rather than stranding the wizard on a
    ; latching control, and say so, because the next step may misread the still
    ; active input.
    if (LearnReleaseOffset >= 0) {
        if (LearnReleaseUntil && A_TickCount >= LearnReleaseUntil) {
            LogLine("Learn: release of byte " LearnReleaseOffset " was never seen; "
                . "continuing anyway.", "Warning")
            LearnReleaseOffset := -1
            LearnReleaseMask := 0
            LearnReleaseUntil := 0
            SetTimer(ControllerLearnNextStep, -150)
        }
        return
    }
    if (!LearnCaptureUntil || A_TickCount < LearnCaptureUntil)
        return
    steps := ControllerLearnSteps()
    if (LearnStepIndex < 1 || LearnStepIndex > steps.Length)
        return
    step := steps[LearnStepIndex]
    if (step["kind"] = "wiggle") {
        LearnCaptureUntil := 0
        found := ControllerLearnClassifyAnalog()
        LearnLastAccepted := found " analogue byte" (found = 1 ? "" : "s") " found"
        try LearnDetailCtrl.Text := (found > 0
            ? "Sticks and triggers found. Button steps will ignore them from now on."
            : "No sticks or triggers seen — carrying on with the buttons.")
        SetTimer(ControllerLearnNextStep, -600)
        return
    }
    ; A digital step that never saw its control moves on by itself.
    ;
    ; The controller is deliberately inert while the wizard is open, so Skip can
    ; only be reached with a mouse or the touchscreen. Without this, a control the
    ; pad does not have -- a Guide button hidden by its driver, say -- would stall
    ; the whole wizard for anyone holding only a controller.
    ; A refusal that retrying cannot fix is skipped on the same terms as a control
    ; the pad does not have. Retrying it would restart the same step forever.
    if (step["kind"] = "axis" && LearnAxisUnresolvable) {
        LearnCaptureUntil := 0
        LearnLastAccepted := step["name"] " could not be told apart from motion"
        try LearnDetailCtrl.Text := "Skipping " ControllerLearnFriendlyName(step["name"])
            . " — only the motion sensor moved, so this cannot be told apart "
            . "from it. Everything else still works."
        LogLine("Learn: " step["name"] " skipped; every candidate was a "
            . "free-running byte and a trigger cannot be sanity-checked against "
            . "one.", "Warning")
        SetTimer(ControllerLearnNextStep, -400)
        return
    }
    if (step["kind"] != "axis") {
        LearnCaptureUntil := 0
        LearnLastAccepted := step["name"] " not detected"
        try LearnDetailCtrl.Text := "Did not see " ControllerLearnFriendlyName(step["name"])
            . " — skipping it. Your controller may not have one."
        LogLine("Learn: " step["name"] " timed out; skipped.", "Warning")
        SetTimer(ControllerLearnNextStep, -400)
        return
    }
    LearnCaptureUntil := 0
    LearnLastAccepted := step["name"] " timed out"
    try LearnDetailCtrl.Text := "Let go of everything and we will try this one again."
    LogLine("Learn: " step["name"] " timed out before returning to rest. Retrying.",
        "Warning")
    SetTimer(ControllerLearnStartCapture, -1200)
}


; Once a device has been identified, the steps begin.
ControllerLearnUpdateUi() {
    global LearnDevice, LearnStepIndex, LearnPromptCtrl, LearnDetailCtrl
    global LearnLength, LearnDeviceKey, LearnIdentifyReady
    global LearnRestSampling, LearnRestCount, LearnIdentifyHoldOffset
    if !LearnDevice {
        if LearnIdentifyReady {
            try LearnPromptCtrl.Text := "Press any button on the controller you want to set up"
            try LearnDetailCtrl.Text := "This tells us which controller to listen to. "
                . "Press and release one button."
        } else {
            try LearnPromptCtrl.Text := "Hands off the controller for a moment"
            try LearnDetailCtrl.Text := "Checking what the controller sends when "
                . "nothing is being touched. This takes a second."
        }
        return
    }
    ; Two states share LearnStepIndex = 0, and they used to be one. The rest
    ; countdown started here, the moment the device was identified -- which is
    ; the moment the identifying button was pressed, not released. The wizard
    ; asked for hands off while the user was still mid-press, and measured rest
    ; from it. Rest now starts from ControllerLearnIdentifyReleased, and this
    ; only describes whichever of the two the wizard is actually in.
    if (LearnStepIndex = 0) {
        if (LearnIdentifyHoldOffset >= 0) {
            try LearnPromptCtrl.Text := "Let go of that button"
            try LearnDetailCtrl.Text := "Got the controller. Release the button "
                . "you just pressed and we will measure what resting looks like."
            return
        }
        try LearnPromptCtrl.Text := "Hands off — do not touch anything yet"
        try LearnDetailCtrl.Text := "Learning what resting looks like. Anything "
            . "you hold now will be ignored for the rest of the wizard, so let "
            . "go until the next prompt."
    }
}


; Checks the four D-pad directions as a set, and retries them once if they do not
; describe a real D-pad.
;
; A slightly diagonal press is the failure this catches. On a hat, up-and-right
; reads as the diagonal value rather than the cardinal -- so "Up" gets recorded as
; 2 instead of 1, the four values stop being evenly spaced, the hat is rejected,
; and the bit fallback then collides because 3 and 5 share their lowest bit. One
; imprecise press quietly ruins the whole D-pad, so it is worth detecting and
; simply asking again.
;
; Returns true to carry on, false when it has rewound for a retry.
ControllerLearnValidateDpad() {
    global LearnHatValues, LearnStepIndex, LearnDpadRetries
    global LearnDetailCtrl, LearnPromptCtrl
    static DIRECTIONS := ["Up", "Right", "Down", "Left"]
    ; A clean hat is the best outcome and needs no further checking.
    if (ControllerLearnHatText() != "")
        return true
    ; Otherwise it must be four distinct single bits, which is the other real
    ; D-pad shape.
    seen := Map()
    distinctBits := 0
    for _, name in DIRECTIONS {
        if !LearnHatValues.Has(name)
            continue
        entry := LearnHatValues[name]
        mask := entry["value"] & ~entry["released"] & 0xFF
        ; Exactly one bit set.
        if (!mask || (mask & (mask - 1)))
            continue
        key := entry["offset"] ":" mask
        if seen.Has(key)
            continue
        seen[key] := true
        distinctBits += 1
    }
    if (distinctBits = DIRECTIONS.Length)
        return true
    if (LearnDpadRetries >= 1) {
        LogLine("Learn: D-pad still inconsistent after a retry; saving whatever "
            . "was captured. Check the Hat and Buttons lines in the profile.",
            "Warning")
        return true
    }
    LearnDpadRetries += 1
    ; Guarded: a direction that timed out was never recorded, and Map.Delete
    ; throws on a key that is not there. The retry exists precisely because the
    ; four directions did not come out right, so an incomplete set is the
    ; expected input here, not an unlikely one.
    for _, name in DIRECTIONS {
        if LearnHatValues.Has(name)
            LearnHatValues.Delete(name)
    }
    ; Rewind to the first D-pad step. StartCapture is called from the timer below.
    steps := ControllerLearnSteps()
    Loop steps.Length {
        if (steps[A_Index]["kind"] = "dpad") {
            LearnStepIndex := A_Index
            break
        }
    }
    LogLine("Learn: the four D-pad directions do not describe a hat or four "
        . "distinct bits, most likely a diagonal press. Retrying them.", "Warning")
    try LearnPromptCtrl.Text := "Let us try the D-pad again"
    try LearnDetailCtrl.Text := "Press each direction straight on. Catching two at "
        . "once (like up-and-right) confuses it."
    SetTimer(ControllerLearnStartCapture, -1500)
    return false
}


ControllerProfileRestCheck() {
    global RawInputState, RawInputLastReportTick, ControllerDeadzone
    global RestCheckPeak, RestCheckSamples
    static WINDOW_SAMPLES := 12          ; ~1.4 s at the 120 ms tick
    if !RawInputLastReportTick {
        SetTimer(ControllerProfileRestCheck, 0)
        return
    }
    RestCheckSamples += 1
    for name, offset in Map("LX", 8, "LY", 10, "RX", 12, "RY", 14) {
        value := Abs(NumGet(RawInputState, offset, "Short"))
        if (value > RestCheckPeak[name])
            RestCheckPeak[name] := value
    }
    for name, offset in Map("LT", 6, "RT", 7) {
        value := NumGet(RawInputState, offset, "UChar")
        if (value > RestCheckPeak[name])
            RestCheckPeak[name] := value
    }
    if (RestCheckSamples < WINDOW_SAMPLES)
        return
    SetTimer(ControllerProfileRestCheck, 0)

    ; Generous: this is looking for an axis that is pegged, not for drift.
    limit := Max(ControllerDeadzone * 2, 12000)
    offenders := ""
    for _, name in ["LX", "LY", "RX", "RY"] {
        if (RestCheckPeak[name] > limit)
            offenders .= (offenders != "" ? ", " : "") name "=" RestCheckPeak[name]
    }
    for _, name in ["LT", "RT"] {
        if (RestCheckPeak[name] > 80)
            offenders .= (offenders != "" ? ", " : "") name "=" RestCheckPeak[name]
    }
    if (offenders = "") {
        LogLine("Controller profile: rest check passed over " RestCheckSamples
            . " samples; all axes read neutral.")
        return
    }
    LogLine("Controller profile: rest check FAILED over " RestCheckSamples
        . " samples. Peak with nothing touched: " offenders
        . ". The pointer will drift or run away.", "Error")
    answer := TopmostMsgBox("The saved controller profile reads as if the controller is "
        . "being held, with nothing touched:`n`n" offenders "`n`n"
        . "This makes the pointer run across the screen. Delete the profile and "
        . "go back to the built-in layout?`n`n"
        . "Choose No to keep it and re-learn the sticks yourself.",
        "Controller profile looks wrong", "YesNo Icon!")
    if (answer = "Yes")
        DeleteControllerProfileForActiveDevice()
}


; Checks a freshly saved profile decodes to neutral while nothing is touched.
;
; An axis learned with the wrong neutral, direction or extent reads as permanently
; deflected, and the controller mouse then flies across the screen -- which also
; makes it hard to reach Settings to undo. If any stick is pegged with the
; controller at rest this says so plainly and offers to delete the profile there
; and then.
;
; Sampled over a WINDOW rather than at one instant. A statically mis-learned axis
; reads wrong in every report, so one sample would find it -- but an axis
; mis-bound to a motion sensor oscillates, and a single sample can catch it as it
; passes through neutral. That is not hypothetical: the 8BitDo Ultimate 2 that
; motivated the free-running filter had RT bound to a gyro byte, and the axis a
; motion sensor is bound to is exactly the axis that will not hold still. Peak
; magnitude across the window is what a pegged axis cannot hide from.
ControllerProfileRestCheckBegin() {
    global RestCheckPeak, RestCheckSamples
    RestCheckPeak := Map("LX", 0, "LY", 0, "RX", 0, "RY", 0, "LT", 0, "RT", 0)
    RestCheckSamples := 0
    SetTimer(ControllerProfileRestCheck, 120)
}


; ------------------------------------------------------------------------------
; Learning wizard UI
; ------------------------------------------------------------------------------
ShowControllerLearner(*) {
    global LearnGui, LearnActive, LearnDevice, LearnDeviceKey, LearnLength
    global LearnBaseline, LearnRestNoise, LearnRestSampling, LearnRestCount
    global LearnIdentifyHoldOffset, LearnIdentifyHoldMask
    global LearnStepIndex, LearnResultButtons, LearnResultAxes, LearnHatValues
    global LearnPromptCtrl, LearnDetailCtrl, LearnProgressCtrl, LearnCaptureUntil
    global LearnLastAccepted, LearnLastFriendly
    global LearnIdentifyDevices, LearnIdentifyReady
    global MouseHidden, SettingsDialogActive
    global LearnAnalogBytes, LearnAnalogValues, LearnDpadRetries
    global LearnCountdownCtrl
    ; An active wizard has a window, and this brings it forward. If it does not
    ; have one, the flag is left over from a build that failed below and there is
    ; nothing to bring forward -- so returning here returns into a state nothing
    ; will ever clear. That state stands the controller poll down, so the pad is
    ; dead, and this function is the only route back to the wizard that would
    ; cancel it. Clear it and open a new one instead.
    if LearnActive {
        if IsSet(LearnGui) {
            try WinActivate("ahk_id " LearnGui.Hwnd)
            return
        }
        LogLine("Learn: session was active with no window; clearing it.")
        CloseControllerLearner()
    }
    ; RawInput has to be listening or there is nothing to learn from.
    if !RawInputProbeStart() {
        if !RawInputRegistered() {
            TopmostMsgBox("RawInput is not registered, so no controller reports can be "
                . "read.`n`nSet Input backend to Auto or RawInput, then try again.",
                "Learn controller", "Iconx")
            return
        }
    }
    ; The normal decoder is paused while reports are consumed by the learner.
    ; Clear its cached state first so a pre-wizard held button cannot remain
    ; logically pressed until the stale timeout expires.
    RawInputResetDeviceLock("controller learner opened")
    LearnActive := true
    LearnDevice := 0
    LearnDeviceKey := ""
    LearnLength := 0
    LearnBaseline := 0
    LearnRestNoise := 0
    LearnRestSampling := false
    LearnRestCount := 0
    LearnStepIndex := 0
    LearnAnalogBytes := Map()
    LearnAnalogValues := Map()
    LearnDpadRetries := 0
    LearnResultButtons := []
    LearnResultAxes := Map()
    LearnHatValues := Map()
    LearnLastAccepted := ""
    LearnLastFriendly := ""
    LearnCaptureUntil := 0
    LearnIdentifyDevices := Map()
    LearnIdentifyReady := false
    LearnIdentifyHoldOffset := -1
    LearnIdentifyHoldMask := 0
    ; The pointer is needed for the buttons on this window.
    if MouseHidden {
        SystemCursor("Show")
        MouseHidden := false
    }
    ; Treated as a dialog so the assist features stay out of the way and the
    ; controller's own mappings do not fire while it is being pressed for
    ; learning.
    SettingsDialogActive := true

    ; Everything from LearnActive above to LearnGui below is state the rest of
    ; the process reads, committed before the window that owns it exists. If the
    ; build throws in between -- a font, a monitor query, a control -- the
    ; session is left active with no window, and that is not a cosmetic leak: the
    ; controller poll stands down on LearnActive, so the pad goes inert, and the
    ; wizard is the thing that would have cancelled it. On a handheld with no
    ; keyboard that is the whole machine. Hand the failure back to the one
    ; function that clears all of it.
    try {
    learn := Gui("+AlwaysOnTop -MinimizeBox", "Learn Controller")
    learn.Opt("+OwnDialogs")
    learn.MarginX := 24
    learn.MarginY := 18
    learn.SetFont("s14 Bold", "Segoe UI")
    LearnPromptCtrl := learn.AddText("x24 y20 w480 h60 +Wrap",
        "Release every controller for a moment")
    ; A large, always-visible countdown. Several steps are observation windows
    ; that end on a timer, and without a clock the wizard looks like it has hung
    ; rather than like it is waiting for you.
    learn.SetFont("s34 Bold", "Segoe UI")
    LearnCountdownCtrl := learn.AddText("x516 y16 w108 h64 +Right", "")
    learn.SetFont("s10 Norm", "Segoe UI")
    ; THREE lines, wrapped. This was h24 -- one line -- and the messages it
    ; carries were rewritten into plain English, which made several of them two
    ; lines. A Static clips at its own height rather than growing, so the second
    ; line was simply cut in half on screen: "Anything you hold now will be
    ; ignored for the rest of the wizard, so l"
    ;
    ; Sized from the longest string it can hold rather than from the one it is
    ; created with, and given a third line of headroom because the friendly
    ; control names are substituted in at run time and a wider font or a higher
    ; DPI buys fewer characters per line than this was measured at.
    LearnDetailCtrl := learn.AddText("x24 y88 w600 h54 +Wrap",
        "Checking what the controller sends when nothing is being touched.")
    LearnProgressCtrl := learn.AddText("x24 y146 w600 h24", "")
    learn.AddText("x24 y178 w600 h56 +Wrap",
        "Press each button once. For sticks and triggers, move fully as prompted, "
        . "then release. Skip anything this controller does not have.")
    skip := learn.AddButton("x24 y244 w130 h34", "Skip")
    skip.OnEvent("Click", (*) => ControllerLearnSkip())
    restart := learn.AddButton("x164 y244 w130 h34", "Start Over")
    restart.OnEvent("Click", (*) => ControllerLearnRestart())
    save := learn.AddButton("x374 y244 w120 h34", "Save")
    save.OnEvent("Click", (*) => ControllerLearnSave())
    cancel := learn.AddButton("x504 y244 w120 h34", "Cancel")
    cancel.OnEvent("Click", (*) => CloseControllerLearner())
    learn.OnEvent("Close", (*) => CloseControllerLearner())
    learn.OnEvent("Escape", (*) => CloseControllerLearner())
    LearnGui := learn
    foreground := 0
    try foreground := WinExist("A")
    CenterGuiOnMonitorActual(learn, GetMonitorIndexForWindow(foreground), 648, 298)
    try ForceForegroundWindow(learn.Hwnd)
    SetTimer(ControllerLearnIdentificationReady, -1200)
    LogLine("Learn: wizard opened.")
    } catch as err {
        ; CloseControllerLearner clears LearnActive, the dialog flag, and every
        ; timer, and destroys a partly built window if LearnGui was reached. It
        ; is deliberately called before the message box: the box is modal, and
        ; the controller must not still be inert behind it.
        CloseControllerLearner()
        LogLine("Learn: wizard could not be opened: " err.Message)
        TopmostMsgBox("The Learn Controller window could not be opened."
            . "`n`n" err.Message, "Learn controller", "Iconx")
    }
}


; Removes the profile in use for the device currently being decoded.
;
; The escape hatch for a bad profile. It has to work without the pointer, because
; a bad profile is precisely what takes the pointer away, so it is also on
; Ctrl+Alt+Shift+D.
DeleteControllerProfileForActiveDevice(*) {
    global RawInputDevice
    key := ""
    if RawInputDevice
        key := RawInputDeviceKey(RawInputDevice, true)
    path := ControllerProfilePath()
    removed := ""
    ; Both the identity key and the length-keyed fallback are candidates, and the
    ; fallback is the one a device Windows will not identify ended up under.
    for _, candidate in [key, ControllerProfileLengthKey(16)] {
        if (candidate = "")
            continue
        length := 0
        try length := Integer(IniRead(path, candidate, "ReportLength", "0"))
        if (length <= 0)
            continue
        try {
            IniDelete(path, candidate)
            removed .= (removed != "" ? ", " : "") candidate
        }
    }
    if (removed = "") {
        ShowNotification("No controller profile to delete")
        LogLine("Controller profile: nothing to delete.")
        return
    }
    LogLine("Controller profile: deleted " removed ". Reloading.", "Warning")
    Reload()
}


CenterGuiOnMonitorActual(guiObj, monitorIndex, width, height, noActivate := false,
        deferShow := false) {
    monitorIndex := ClampInt(monitorIndex, 1, MonitorGetCount())
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    return PositionGuiCentered(guiObj, left, top, right, bottom, width, height,
        noActivate, deferShow)
}


GetMonitorIndexForWindow(hwnd) {
    if hwnd {
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            centerX := wx + Floor(ww / 2)
            centerY := wy + Floor(wh / 2)
            count := MonitorGetCount()
            Loop count {
                MonitorGet(A_Index, &left, &top, &right, &bottom)
                if (centerX >= left && centerX < right
                    && centerY >= top && centerY < bottom)
                    return A_Index
            }
        }
    }
    MouseGetPos(&mx, &my)
    return GetMonitorWorkAreaForPoint(mx, my, &left, &top, &right, &bottom)
}


; The facts map GameWindowShapeVerdict scores, with geometry made relative to the
; monitor the window is actually on.
;
; This existed only in the companion, guarded by a comment reasoning that "the
; shell can assume the game is on A_Screen*; a companion under Xbox FSE cannot".
; The shell cannot assume that either. It centres its own GUIs per monitor, it
; resolves a monitor index for the foreground window, and its Always Focus list
; is not restricted to the primary display -- so a fullscreen game on a second
; monitor was measured against the FIRST monitor's size at an origin of (1920, 0).
; Abs(x) <= positionTolerancePx then fails, nearFS comes out false, and the game
; drops from the fullscreen score to the borderless one or is rejected TOO_SMALL
; outright when the second monitor is the larger of the two.
;
; So the divergence was recorded as deliberate but was really an unported fix.
; Defining the normalisation once is what stops that recurring: the shared verdict
; is only shared if the numbers reaching it are built the same way, and a shared
; arbiter fed by two private argument builders is a duplicate with extra steps.
;
; Requires the geometry keys both inventories carry: hwnd, x, y, w, h, title.
;
; A monitor that cannot be read falls back to the primary rather than dropping the
; window. The companion used to `continue` here, which turns an unreadable monitor
; into an invisible game -- the strictly worse of the two failures, and the one
; that is silent.
GameShapeFactsForWindow(item, minimizedLegacy) {
    left := 0
    top := 0
    screenW := A_ScreenWidth
    screenH := A_ScreenHeight
    ; An exclusive-fullscreen game that minimized itself when Steam took focus.
    ; Its geometry is meaningless -- GameWindowShapeVerdict treats minimizedLegacy
    ; as nearFS -- and the monitor lookup would be answering about coordinates
    ; that are off-screen by design.
    if !minimizedLegacy {
        try {
            MonitorGet(GetMonitorIndexForWindow(item["hwnd"]),
                &monLeft, &monTop, &monRight, &monBottom)
            if (monRight - monLeft > 0 && monBottom - monTop > 0) {
                left := monLeft
                top := monTop
                screenW := monRight - monLeft
                screenH := monBottom - monTop
            }
        }
    }
    return Map(
        "w", item["w"], "h", item["h"],
        "x", item["x"] - left, "y", item["y"] - top,
        "screenW", screenW, "screenH", screenH,
        "titleLength", StrLen(item["title"]),
        "minimizedLegacy", minimizedLegacy)
}


; Sizes and centres a window, never showing it at an intermediate position.
;
; The whole calculation happens while the window is HIDDEN on a first show. That
; is the point of the sequence: the size is measured, the position computed, then
; re-measured and corrected, and none of those intermediate states reach the
; screen. Showing the window first and correcting afterwards is what made the
; Quick Menu visibly snap into place as it opened.
;
; With deferShow, the window is left hidden and the caller reveals it with
; RevealWindow once anything else that depends on the final size is done --
; rounded corners, in the Quick Menu's case, which otherwise appear square for a
; frame. Returns true when a show was deferred.
; Makes visible a window that PositionGuiCentered was asked to leave hidden.
;
; ShowWindow rather than Gui.Show, because Gui.Show with no coordinates
; re-auto-sizes and re-centres the window -- undoing the placement the sequence
; above just computed.
;
; One definition as of this pass, and it was already only one function: the two
; copies were the same five lines, differing in whether the DllCall named its
; DLL and in where the line was wrapped. The gate could not see that, because it
; reads the DllCall TARGET as part of the call sequence and "User32\ShowWindow"
; is not the string "ShowWindow" -- so a pair with identical behaviour scored
; 0.00 and was never flagged once. Spelling the DLL is the better habit and is
; what survives here.
RevealWindow(guiObj, noActivate := false) {
    static SW_SHOWNOACTIVATE := 4
    static SW_SHOW := 5
    try DllCall(
        "User32\ShowWindow", "Ptr", guiObj.Hwnd,
        "Int", noActivate ? SW_SHOWNOACTIVATE : SW_SHOW)
}

PositionGuiCentered(guiObj, left, top, right, bottom, width, height,
        noActivate := false, deferShow := false) {
    global EnableControllerDiagnostics
    wasVisible := false
    try wasVisible := DllCall("IsWindowVisible", "Ptr", guiObj.Hwnd, "Int") != 0

    scale := 1.0
    try scale := A_ScreenDPI / 96.0
    actualWidth := width
    actualHeight := height

    if wasVisible {
        ; Already on screen, so it cannot be hidden to be measured: hiding and
        ; re-showing blinks the menu on every page change and churns activation,
        ; which is exactly what keeping the menu alive was meant to avoid.
        ;
        ; Instead the physical size is predicted -- the same multiplication
        ; Gui.Show does the RESIZE, and the move follows separately.
        ;
        ; An earlier version predicted the physical size as width * A_ScreenDPI/96
        ; and did resize and move in one SetWindowPos, to avoid a frame showing
        ; the new size at the old position. That prediction is only as good as
        ; A_ScreenDPI matching whatever AutoHotkey used when it laid the controls
        ; out, and a mismatch does not cost a wobble -- it sizes the window wrong
        ; and cuts the content off. Letting Gui.Show size it means the window and
        ; the controls inside it are always scaled by the same thing.
        guiObj.Show("NA w" width " h" height)
        try {
            WinGetPos(&resizedX, &resizedY, &resizedWidth, &resizedHeight,
                "ahk_id " guiObj.Hwnd)
            if (resizedWidth > 0 && resizedHeight > 0) {
                actualWidth := resizedWidth
                actualHeight := resizedHeight
            }
        }
        CenteredPosition(left, top, right, bottom, actualWidth, actualHeight, &x, &y)
        MoveWindowPhysical(guiObj.Hwnd, x, y)
    } else {
        ; Realise and size the window while it stays hidden.
        guiObj.Show("Hide w" width " h" height)
        try {
            WinGetPos(&measuredX, &measuredY, &measuredWidth, &measuredHeight,
                "ahk_id " guiObj.Hwnd)
            if (measuredWidth > 0)
                actualWidth := measuredWidth
            if (measuredHeight > 0)
                actualHeight := measuredHeight
        }
        ; A window measured before it is really on screen can report the LOGICAL
        ; size it was asked for rather than the physical size it will occupy. At
        ; 150% scaling a 720x518 request becomes a 1082x779 window, and centring
        ; the smaller figure pushes it down and right by half the difference.
        ; Getting back exactly what was requested is the signature of that case.
        if (scale != 1.0 && actualWidth = width && actualHeight = height) {
            actualWidth := Round(width * scale)
            actualHeight := Round(height * scale)
        }
        CenteredPosition(left, top, right, bottom, actualWidth, actualHeight, &x, &y)
        MoveWindowPhysical(guiObj.Hwnd, x, y)
    }

    ; Measure the real window and re-centre from the true size. This is what
    ; makes the result correct at any scaling; the estimate above only has to be
    ; close enough. On a first show this correction is free, because the window
    ; is still hidden.
    try {
        WinGetPos(&shownX, &shownY, &shownWidth, &shownHeight, "ahk_id " guiObj.Hwnd)
        if (shownWidth > 0 && shownHeight > 0) {
            actualWidth := shownWidth
            actualHeight := shownHeight
            CenteredPosition(left, top, right, bottom, shownWidth, shownHeight,
                &correctedX, &correctedY)
            if (Abs(shownX - correctedX) > 1 || Abs(shownY - correctedY) > 1) {
                MoveWindowPhysical(guiObj.Hwnd, correctedX, correctedY)
                x := correctedX
                y := correctedY
            }
        }
    }

    deferred := false
    if !wasVisible {
        if deferShow
            deferred := true
        else
            RevealWindow(guiObj, noActivate)
    }

    ; Report every input to the calculation and the position actually achieved.
    ; Centering has been guessed at twice; this makes a miss readable instead of
    ; something to theorise about.
    if EnableControllerDiagnostics {
        ; Measured into separate variables and copied only on success.
        ;
        ; A `&` output parameter is left UNSET when the call fails, which beats
        ; the := 0 initialisation -- so a bare `try WinGetPos(&finalX, ...)`
        ; followed by a use of finalX crashes with "this local variable has not
        ; been assigned a value" the moment the window goes away mid-call. That
        ; is exactly the 0.1.2 `actualWidth` bug, recurring under a new name
        ; because the guard against it named one variable.
        finalX := 0, finalY := 0, finalW := 0, finalH := 0
        try {
            WinGetPos(&measuredFinalX, &measuredFinalY, &measuredFinalW,
                &measuredFinalH, "ahk_id " guiObj.Hwnd)
            finalX := measuredFinalX, finalY := measuredFinalY
            finalW := measuredFinalW, finalH := measuredFinalH
        }
        LogLine("Center: work=" left "," top ".." right "," bottom
            . " requested=" width "x" height
            . " measured=" actualWidth "x" actualHeight
            . " target=" x "," y
            . " final=" finalX "," finalY " " finalW "x" finalH
            . (wasVisible ? " (resize in place)" : "")
            . (deferred ? " (show deferred)" : ""))
    }
    return deferred
}

GetMonitorWorkAreaForPoint(x, y, &left, &top, &right, &bottom) {
    count := MonitorGetCount()
    Loop count {
        MonitorGetWorkArea(A_Index, &ml, &mt, &mr, &mb)
        if (x >= ml && x < mr && y >= mt && y < mb) {
            left := ml, top := mt, right := mr, bottom := mb
            return A_Index
        }
    }
    MonitorGetWorkArea(1, &left, &top, &right, &bottom)
    return 1
}

; A row of buttons, laid out on the content grid rather than by hand.
;
; Columns are DERIVED from the layout, not stated. The companion's copy carried
; the scar that teaches this: it used to be [300, 496, 692] with 178-wide
; buttons, correct for a 900-pixel window whose content began at 300, and
; silently wrong the moment the content moved to 255 and widened to 690.
;
; Shared as of this pass, because the shell had no equivalent -- every button on
; its pages carried a hand-typed x and width, and they had drifted apart. Its
; Startup Programs page was the clearest case: four buttons of 155, 175, 155 and
; 175 on one line, then three of 155 on the next, starting from columns that did
; not line up with the row above. Nothing was wrong with any single number; they
; were simply never derived from anything.
;
; columns is a parameter because label length decides it, not taste. Three fits
; the companion's short labels and the shell's list controls; the shell's
; Advanced page needs two, because "Install Managed Copy as Shell" does not fit
; in a third of the content width.
SettingsAddButtonRow(guiObj, category, entries, &y, columns := 3) {
    layout := SettingsLayout()
    gap := 15
    if (columns < 1)
        columns := 1
    buttonWidth := (layout["contentWidth"] - gap * (columns - 1)) // columns
    LINE_HEIGHT := 42
    index := 0
    for _, entry in entries {
        column := Mod(index, columns)
        if (column = 0 && index > 0)
            y += LINE_HEIGHT
        button := guiObj.AddButton(
            "x" (layout["contentX"] + (buttonWidth + gap) * column)
            . " y" y " w" buttonWidth " h34", entry[1])
        button.OnEvent("Click", entry[2])
        SettingsProductTrackControl(category, button)
        index += 1
    }
    if (index > 0)
        y += LINE_HEIGHT
    return y
}

; Draws a category from the shared definition, for whichever product asked.
;
; This was two adapters that the cross-name gate scored 0.88 on calls and 0.84
; on body -- the same walk over the same table, differing only in which product
; string they filtered by. That is a parameter, not a second function.
;
; tableKey existed for ONE case: the companion called its logging page
; "Advanced" while the shell called it "Advanced & Logging", so the rows were
; keyed by the shell's name and the companion passed it explicitly. The companion
; uses the shell's name now, and nothing passes tableKey. It is kept, unused,
; because two products drawing one table will not always agree on a page name and
; the parameter is the seam for that -- but a caller passing it today is a page
; name that could simply be corrected instead.
SettingsAddRowsForCategory(guiObj, category, product, &y, tableKey := "") {
    for _, row in SettingsCategoryRows(tableKey != "" ? tableKey : category) {
        if !SettingsRowAppliesTo(row, product)
            continue
        ; A note carries "text", not "label", so asking every row for a label
        ; before knowing its type throws on the first note. Only ask for what a
        ; row actually has.
        label := row.Has("label") ? SettingsRowLabel(row, product) : ""
        value := SettingsRowDefault(row, product)
        switch row["type"] {
            case "checkbox":
                ctrl := SettingsAddCheckbox(guiObj, category, row["section"],
                    row["key"], label, &y, value)
                if (row.Has("dependency") && row["dependency"])
                    SettingsProductWireDependency(ctrl, "Click")
            case "choice":
                choices := (product = "xfe" && row.Has("xfeChoices"))
                    ? row["xfeChoices"]
                    : SettingsRowChoices(row)
                ctrl := SettingsAddChoice(guiObj, category, row["section"],
                    row["key"], label, choices, &y, value)
                if (row.Has("dependency") && row["dependency"])
                    SettingsProductWireDependency(ctrl, "Change")
            case "edit":
                SettingsAddTextField(guiObj, category, row["section"],
                    row["key"], label, &y, value,
                    row.Has("fieldType") ? row["fieldType"] : "text",
                    row.Has("min") ? row["min"] : "",
                    row.Has("max") ? row["max"] : "")
            case "slider":
                SettingsAddSliderField(guiObj, category, row["section"],
                    row["key"], label, &y, value,
                    row.Has("min") ? row["min"] : 0,
                    row.Has("max") ? row["max"] : 100,
                    row.Has("step") ? row["step"] : 1,
                    row.Has("suffix") ? row["suffix"] : "")
            case "shortcut":
                SettingsAddShortcutField(guiObj, category, row["section"],
                    row["key"], label, &y, value)
            case "path":
                SettingsAddPathField(guiObj, category, row["section"],
                    row["key"], label, &y, row["prompt"], row["filter"], value)
            ; No "mappedchoice" case. The one row of that kind -- the shell's
            ; foreground sensitivity -- is hand-placed, because the companion
            ; forbids its key by name and compiles this file. A case here would
            ; call a builder that exists in neither tree, and AutoHotkey resolves
            ; that when the program STARTS, not when it compiles.
            case "note":
                ; Height from the words. A fixed height fitted the note it was
                ; written for and clipped the next one that was longer.
                SettingsAddNote(guiObj, category, row["text"], &y,
                    Max(22, Ceil(StrLen(row["text"]) / 95) * 20 + 4))
            case "section":
                SettingsProductAddSectionRow(guiObj, category, label, &y)
        }
    }
}

; ==============================================================================
; Settings row builders
; ==============================================================================
; One set of builders for both Settings windows.
;
; These are the SHELL's, moved rather than merged. Two implementations that were
; 0.42 to 0.69 alike could have been reconciled into a third thing neither
; product had been running; moving the mature one instead means the shell's
; Settings window is unchanged by construction and the companion adopts what has
; the bench time behind it.
;
; Two edits made them serve both: the window is passed in rather than read from
; a global, and registration goes through a seam. Everything else -- the percent
; scaling, the WantTab on multi-row edits, the pre-selected choice, the Browse
; and Record buttons -- is the shell's code, untouched.
;
; They CREATE and REGISTER; they do not read the INI. Filling happens afterwards,
; from the field specs, in both products.

SettingsAddCheckbox(guiObj, category, section, key, label, &y, defaultValue := "false") {
    layout := SettingsLayout()
    ctrl := guiObj.AddCheckbox("x" layout["contentX"] " y" y " w690 h25", label)
    ctrl.OnEvent("Click", SettingsProductMarkDirty)
    field := Map(
        "category", category, "section", section, "key", key,
        "label", label, "type", "bool", "default", defaultValue, "ctrl", ctrl,
        "controls", [ctrl])
    SettingsRegisterBuiltField(category, field)
    y += 31
    return ctrl
}


SettingsAddChoice(guiObj, category, section, key, label, choices, &y, defaultValue := "") {
    layout := SettingsLayout()
    labelCtrl := guiObj.AddText("x" layout["contentX"] " y" (y + 4) " w315 h24", label)
    ctrl := guiObj.AddDropDownList("x" layout["controlX"] " y" y " w320", choices)
    current := defaultValue
    selectedIndex := 1
    for index, choice in choices {
        if (StrLower(choice) = StrLower(current)) {
            selectedIndex := index
            break
        }
    }
    ctrl.Choose(selectedIndex)
    ctrl.OnEvent("Change", SettingsProductMarkDirty)
    field := Map(
        "category", category, "section", section, "key", key,
        "label", label, "type", "choice", "default", defaultValue, "ctrl", ctrl,
        "choices", choices, "controls", [labelCtrl, ctrl])
    SettingsRegisterBuiltField(category, field)
    y += 34
    return ctrl
}


; Slider handle -> its value readout, for the refresh below.
SettingsSliderReadoutRegistry() {
    static registry := Map()
    return registry
}


; Repaints every slider's value readout from its slider.
;
; Needed because assigning .Value in code does NOT raise Change in AutoHotkey --
; only the user dragging the track does. Without this the number beside a slider
; keeps whatever it was built with while the slider itself moves to the loaded
; value, which is worse than showing no number at all.
;
; Called after the populate pass in both products, and by the sliders' own Change
; handler. Entries whose window has been destroyed are pruned as they are found,
; so reopening the Settings window cannot accumulate dead controls.
SettingsRefreshSliderReadouts() {
    registry := SettingsSliderReadoutRegistry()
    dead := []
    for hwnd, entry in registry {
        refreshed := false
        try {
            entry["readout"].Text := entry["slider"].Value entry["suffix"]
            refreshed := true
        }
        if !refreshed
            dead.Push(hwnd)
    }
    for _, hwnd in dead
        registry.Delete(hwnd)
}


; A bounded numeric setting, as a track bar with its range written at each end.
;
; For values where the RANGE is the useful information and the exact number is
; not. Controller mouse speed is the case that prompted it: an edit box asks the
; user to know that 3200 is reasonable and 200 is a crawl, and the only way to
; find out is to type, save, and try. A slider shows the whole span at once and
; the readout updates as it moves.
;
; Registered as a normal field with type "integer", so save, dirty-tracking,
; defaults and category reset all treat it exactly like the edit box it replaces
; and neither product needed a new save path. The registered control is the
; SLIDER, so ProductSettingsScrollBar and the focus list see one control per row.
;
; The value readout is a plain Text, deliberately not an Edit: two writable views
; of one setting is a synchronisation problem, and the Quick Menu already offers
; stepped adjustment for anyone who wants a precise number.
SettingsAddSliderField(guiObj, category, section, key, label, &y, defaultValue := ""
    , minValue := 0, maxValue := 100, step := 1, suffix := "") {
    layout := SettingsLayout()
    labelCtrl := guiObj.AddText("x" layout["contentX"] " y" (y + 4) " w315 h24", label)
    ; The readout is sized for the widest value the range can produce, plus the
    ; suffix, so the slider does not shift as the number gains a digit.
    readoutWidth := 46 + (StrLen(maxValue "") * 9) + (StrLen(suffix) * 8)
    trackWidth := layout["controlWidth"] - readoutWidth - 8
    slider := guiObj.AddSlider(
        "x" layout["controlX"] " y" (y + 2) " w" trackWidth " h26"
        . " Range" minValue "-" maxValue " Page" (step * 10) " Line" step
        . " NoTicks", ToInt(defaultValue, minValue))
    readout := guiObj.AddText(
        "x" (layout["controlX"] + trackWidth + 8) " y" (y + 6)
        . " w" readoutWidth " h22", slider.Value suffix)
    slider.OnEvent("Change", (*) => SettingsRefreshSliderReadouts())
    slider.OnEvent("Change", SettingsProductMarkDirty)
    ; Registered centrally rather than through a per-field callback, because the
    ; two products hold their field registries differently -- the shell keeps an
    ; array of field Maps, the companion a Map from Section.Key to the control --
    ; and only one of them could carry a closure. One registry keyed on the
    ; slider's own handle is reachable from both.
    SettingsSliderReadoutRegistry()[slider.Hwnd] := Map(
        "slider", slider, "readout", readout, "suffix", suffix)
    field := Map(
        "category", category, "section", section, "key", key,
        "label", label, "type", "integer", "default", defaultValue, "ctrl", slider,
        "min", minValue, "max", maxValue,
        ; Carried so controller stepping matches the slider's own granularity
        ; rather than a constant chosen for some other row's range.
        "step", step,
        "controls", [labelCtrl, slider, readout])
    SettingsRegisterBuiltField(category, field)
    y += 34
    return field
}

SettingsAddTextField(guiObj, category, section, key, label, &y, defaultValue := ""
    , fieldType := "text", minValue := "", maxValue := "", rows := 1) {
    layout := SettingsLayout()
    labelCtrl := guiObj.AddText("x" layout["contentX"] " y" (y + 4) " w315 h24", label)
    options := "x" layout["controlX"] " y" y " w" layout["controlWidth"]
    if (rows > 1)
        options .= " r" rows " WantTab"
    initialValue := ""
    if (fieldType = "percent") {
        storedDefault := ToFloat(defaultValue, 0.0)
        initialValue := FormatSettingsFloat(
            ToFloat(initialValue, storedDefault) * 100, 4)
    }
    ctrl := guiObj.AddEdit(options, initialValue)
    ctrl.OnEvent("Change", SettingsProductMarkDirty)
    field := Map(
        "category", category, "section", section, "key", key,
        "label", label, "type", fieldType, "default", defaultValue, "ctrl", ctrl,
        "min", minValue, "max", maxValue,
        "controls", [labelCtrl, ctrl])
    SettingsRegisterBuiltField(category, field)
    y += rows > 1 ? (30 + rows * 20) : 34
    return field
}


SettingsAddPathField(guiObj, category, section, key, label, &y, prompt, filter, defaultValue := "") {
    layout := SettingsLayout()
    labelCtrl := guiObj.AddText("x" layout["contentX"] " y" (y + 4) " w180 h24", label)
    ctrl := guiObj.AddEdit("x" layout["pathX"] " y" y " w" layout["pathWidth"], "")
    browseButton := guiObj.AddButton("x" layout["pathButtonX"] " y" (y - 1) " w92 h27", "Browse…")
    field := Map(
        "category", category, "section", section, "key", key,
        "label", label, "type", "path", "default", defaultValue, "ctrl", ctrl,
        "controls", [labelCtrl, ctrl, browseButton])
    ctrl.OnEvent("Change", SettingsProductMarkDirty)
    browseButton.OnEvent("Click", SettingsProductBrowsePath.Bind(field, prompt, filter))
    SettingsRegisterBuiltField(category, field)
    y += 35
    return field
}


SettingsAddShortcutField(guiObj, category, section, key, label, &y, defaultValue := "") {
    layout := SettingsLayout()
    labelCtrl := guiObj.AddText("x" layout["contentX"] " y" (y + 4) " w315 h24", label)
    ctrl := guiObj.AddEdit("x" layout["controlX"] " y" y " w245", "")
    recordButton := guiObj.AddButton("x" layout["recordButtonX"] " y" (y - 1) " w112 h27", "Record…")
    field := Map(
        "category", category, "section", section, "key", key,
        "label", label, "type", "text", "default", defaultValue, "ctrl", ctrl,
        "controls", [labelCtrl, ctrl, recordButton])
    ctrl.OnEvent("Change", SettingsProductMarkDirty)
    recordButton.OnEvent("Click", SettingsProductRecordShortcut.Bind(field))
    SettingsRegisterBuiltField(category, field)
    y += 34
    return field
}


; Explanatory text under a control, not bound to any setting.
;
; Registered with its category like every other control, so it shows and hides
; with the page rather than surviving on top of the next one.
SettingsAddNote(guiObj, category, text, &y, height := 34) {
    layout := SettingsLayout()
    ctrl := guiObj.AddText("x" layout["contentX"] " y" y
        . " w" layout["contentWidth"] " h" height " +Wrap", text)
    ; Tracked, though it is not a field. A control that belongs to no category
    ; never hides, so it survives the page it was drawn on and sits on top of
    ; the next one.
    SettingsProductTrackControl(category, ctrl)
    y += height + 6
    return ctrl
}


; ==============================================================================
; Controller test and calibration
; ==============================================================================
; A diagnostic window over the controller stack both products already share --
; the same decoder, the same poll frame, the same settings on the same clamps.
; It was standalone's alone for no reason anyone had written down, which is what
; being absent from DIVERGENT_FUNCTIONS.txt means: that file records functions
; defined in BOTH trees, so a surface only one tree has never comes up for a
; decision at all.
;
; Nothing here is product-shaped. The last thing that looked it -- writing the
; calibrated deadzone back -- turned out to be a call path that went around
; ProductApplyQuickMenuSetting rather than through it, and now goes through it.
; The window and the button are per product only in the sense every window is:
; ProductCenterGui places it and ProductIdentity titles it.

ControllerTestActive() {
    global ControllerTestGui
    if !IsSet(ControllerTestGui)
        return false
    try return IsGuiVisible(ControllerTestGui)
    return false
}

ControllerButtonNames(buttons) {
    names := []
    definitions := [
        ["D-pad Up", 0x0001], ["D-pad Down", 0x0002],
        ["D-pad Left", 0x0004], ["D-pad Right", 0x0008],
        ["Start", 0x0010], ["View / Back", 0x0020],
        ["L3", 0x0040], ["R3", 0x0080],
        ["LB", 0x0100], ["RB", 0x0200], ["Xbox", 0x0400],
        ["A", 0x1000], ["B", 0x2000], ["X", 0x4000], ["Y", 0x8000]
    ]
    for _, definition in definitions {
        if (buttons & definition[2])
            names.Push(definition[1])
    }
    return names.Length ? JoinWith(names, "  •  ") : "None"
}

; Called with the DECODED sample and, deliberately, BEFORE the deadzone is
; applied -- the axis readout says "Raw stick axes" and has to mean it. A
; deadzoned sample would report perfect centring on a stick that drifts, which is
; the one thing this window exists to measure.
UpdateControllerTest(buttons, lt, rt, lx, ly, rx, ry) {
    global ControllerTestGui, ControllerCalibrationUntil
    global ControllerCalibrationMax, ControllerSuggestedDeadzone
    if !ControllerTestActive()
        return

    try {
        ControllerTestGui["ControllerButtons"].Text := ControllerButtonNames(buttons)
        ControllerTestGui["ControllerTriggers"].Text :=
            "LT " lt " / 255        RT " rt " / 255"
        ControllerTestGui["ControllerAxes"].Text :=
            "Left stick     X " lx "     Y " ly
            . "`r`nRight stick   X " rx "     Y " ry
    }

    if (ControllerCalibrationUntil > 0) {
        ControllerCalibrationMax := Max(
            ControllerCalibrationMax, Abs(lx), Abs(ly), Abs(rx), Abs(ry))
        remainingMs := ControllerCalibrationUntil - A_TickCount
        if (remainingMs > 0) {
            try ControllerTestGui["ControllerCalibration"].Text :=
                "Sampling centered sticks… " Ceil(remainingMs / 1000) " sec"
        } else {
            ControllerCalibrationUntil := 0
            ControllerSuggestedDeadzone := ClampInt(
                ControllerCalibrationMax + 1500, 1000, 16000)
            try ControllerTestGui["ControllerCalibration"].Text :=
                "Maximum centered drift: " ControllerCalibrationMax
                . "     Suggested deadzone: " ControllerSuggestedDeadzone
        }
    }
}

StartControllerCenterSample(*) {
    global ControllerCalibrationUntil, ControllerCalibrationMax
    global ControllerSuggestedDeadzone
    ControllerCalibrationMax := 0
    ControllerSuggestedDeadzone := 0
    ControllerCalibrationUntil := A_TickCount + 3000
}

; THROUGH ProductApplyQuickMenuSetting, which is the seam every other write of a
; setting already uses. This wrote the INI itself and then reached into the
; shell's Settings field registry by hand, which is what made a calibration look
; like it belonged to one product -- and it was the worse of the two paths: no
; check that the Settings window was still visible before assigning to one of its
; controls, a raw .Value where the seam repopulates by field type, and no
; SyncControlPanel, so the shell's Control Panel kept showing the old deadzone.
;
; LoadSettings inside the seam re-reads ControllerDeadzone, so nothing assigns it
; here, and the value reported back is the one that survived the clamp rather
; than the one that was suggested.
ApplyControllerSuggestedDeadzone(*) {
    global ControllerSuggestedDeadzone, ControllerDeadzone, ControllerTestGui
    if (ControllerSuggestedDeadzone <= 0) {
        try ControllerTestGui["ControllerCalibration"].Text :=
            "Run the three-second center sample before applying a recommendation."
        return
    }
    if !ProductApplyQuickMenuSetting(
        "Controller", "ControllerDeadzone", ControllerSuggestedDeadzone) {
        try ControllerTestGui["ControllerCalibration"].Text :=
            "The recommended deadzone could not be saved."
        return
    }
    try ControllerTestGui["ControllerCalibration"].Text :=
        "Deadzone " ControllerDeadzone " saved and applied."
}

HideControllerTest(*) {
    global ControllerTestGui
    if IsSet(ControllerTestGui)
        try ControllerTestGui.Hide()
    ; Hands the poll timer back to whatever the settings say it should be. In the
    ; companion that includes cancelling it again if the companion is disabled,
    ; which is the state ShowControllerTest below deliberately overrides.
    ApplyRuntimeTimers()
}

ShowControllerTest(*) {
    global ControllerTestGui, ControllerDeadzone, ControllerPollIntervalMs
    if !IsSet(ControllerTestGui) {
        ControllerTestGui := Gui("+AlwaysOnTop +ToolWindow -Resize",
            ProductIdentity()["title"] " Controller Test")
        ControllerTestGui.SetFont("s10", "Segoe UI")
        title := ControllerTestGui.AddText("xm ym w620 h30", "Controller Test and Calibration")
        title.SetFont("s17 Bold", "Segoe UI")
        ControllerTestGui.AddText(
            "xm y+2 w620 h38 +Wrap",
            "Inputs are captured by this window and are not sent through "
            . ProductIdentity()["title"] " mappings while the test is open.")
        ControllerTestGui.AddGroupBox("xm y+8 w620 h72", "Pressed buttons")
        ControllerTestGui.AddText(
            "xp+14 yp+27 w590 h30 vControllerButtons +Wrap", "Waiting for controller input…")
        ControllerTestGui.AddGroupBox("xm y+10 w620 h66", "Triggers")
        ControllerTestGui.AddText(
            "xp+14 yp+27 w590 h24 vControllerTriggers", "LT 0 / 255        RT 0 / 255")
        ControllerTestGui.AddGroupBox("xm y+10 w620 h92", "Raw stick axes")
        ControllerTestGui.AddText(
            "xp+14 yp+26 w590 h52 vControllerAxes",
            "Left stick     X 0     Y 0`r`nRight stick   X 0     Y 0")
        ControllerTestGui.AddText(
            "xm y+10 w620 h42 +Wrap",
            "Leave both sticks untouched, then sample their centered drift. Current deadzone: " ControllerDeadzone)
        ControllerTestGui.AddText(
            "xm y+2 w620 h28 vControllerCalibration", "No center sample has been recorded.")
        sampleButton := ControllerTestGui.AddButton("xm y+8 w205 h32", "Sample Center for 3 Seconds")
        sampleButton.OnEvent("Click", StartControllerCenterSample)
        applyButton := ControllerTestGui.AddButton("x+8 yp w205 h32", "Apply Suggested Deadzone")
        applyButton.OnEvent("Click", ApplyControllerSuggestedDeadzone)
        closeButton := ControllerTestGui.AddButton("x+8 yp w120 h32", "Close")
        closeButton.OnEvent("Click", HideControllerTest)
        ControllerTestGui.OnEvent("Close", HideControllerTest)
        ControllerTestGui.OnEvent("Escape", HideControllerTest)
    }
    ControllerTestGui.Show()
    ProductCenterGui(ControllerTestGui)
    ; Arms the poll unconditionally, which is what makes the window work in the
    ; companion when the companion is DISABLED -- the state its poll timer is
    ; normally cancelled in, and the state somebody testing a pad is most likely
    ; to be in. The poll's own test branch runs ahead of its disabled stand-down
    ; for the same reason, and on the same precedent as RecentAppsTick: being
    ; switched off stops the companion ACTING, and this only observes.
    SetTimer(PollController, ControllerPollIntervalMs)
}



; ==============================================================================
; Elevated foreground: input over a High-integrity window
; ==============================================================================
; A High or System integrity window owns the foreground, so this process cannot
; reach it -- UIPI blocks synthetic input from a lower integrity level. The
; elevated helper can, and does, for everything in its own closed switch.
;
; SHARED, and it was the shell's alone. The helper's --product=xfe mode turned
; input off, on two recorded grounds that had both stopped being true: that the
; binary looks for steamshell.exe as its parent, which it has not since
; MainImageName was parameterised, and that its input half is XInput-only, which
; ended when the helper gained RawInput. The second was the load-bearing one --
; it argued the port would help every pad EXCEPT the ones the companion exists
; for -- and it is the one that is now false.
;
; WHAT IS STILL TRUE, and is the whole shape of this: the two processes handle
; DISJOINT sets and between them drop nothing. The helper takes the fixed
; keystrokes. Main keeps the five -- six, with the companion's Settings -- that
; start processes or raise our own windows, because the helper refuses to do
; either from a High-integrity token. ControllerBindingIsNormalIntegrityOnly is
; main's half of that split and the helper's switch is the other; a binding
; missing from both is the failure, and porting this found three of them.
;
; Geometry is NOT shared. Centring elevated windows stays shell-only.

ElevatedAutoMouseEventName() {
    global ScriptPid
    return "Local\SteamShellAutoMouse-" ScriptPid
}

EnsureElevatedAutoMouseEvent() {
    global ElevatedAutoMouseEventHandle
    if ElevatedAutoMouseEventHandle
        return true
    ElevatedAutoMouseEventHandle := DllCall(
        "Kernel32\CreateEventW",
        "Ptr", 0,
        "Int", true,  ; manual reset: the runtime mode persists until changed
        "Int", false,
        "WStr", ElevatedAutoMouseEventName(),
        "Ptr")
    if !ElevatedAutoMouseEventHandle
        LogLine(
            "The automatic-mouse coordination event could not be created ("
            . A_LastError "). The elevated helper will fall back to the "
            . "physical View/Back button.", "Warning")
    return ElevatedAutoMouseEventHandle != 0
}

SetElevatedAutoMouseRuntimeEnabled(enabled) {
    global ElevatedAutoMouseEventHandle
    if !EnsureElevatedAutoMouseEvent()
        return false
    functionName := enabled ? "SetEvent" : "ResetEvent"
    return DllCall(
        "Kernel32\" functionName,
        "Ptr", ElevatedAutoMouseEventHandle,
        "Int") != 0
}

ControllerBindingIsNormalIntegrityOnly(key) {
    static NORMAL_INTEGRITY_ACTIONS := Map(
        "builtin:tabtip", true,
        "builtin:osk", true,
        "builtin:explorer", true,
        "builtin:quickmenu", true,
        "builtin:controlpanel", true,
        ; Companion-only, and the same class as quickmenu
        ; above: it raises one of our own windows.
        "builtin:settings", true)
    return NORMAL_INTEGRITY_ACTIONS.Has(StrLower(GetBindingValue(key)))
}

ElevatedHelperOwnsForeground() {
    if !ProductElevatedHelperAlive()
        return false
    foregroundHwnd := 0
    try foregroundHwnd := WinExist("A")
    if !foregroundHwnd
        return false
    foregroundPid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", foregroundHwnd,
        "UInt*", &foregroundPid)
    if !foregroundPid
        return false
    if !GetProcessTokenSecurity(
        foregroundPid, &foregroundSid, &foregroundSession,
        &integrityName, &integrityError)
        return false
    return integrityName = "High" || integrityName = "System"
}

ControllerHandleElevatedForeground(buttons, lt, rt, pressed, released, now, chordActive) {
    global ControllerChordHoldMs
    static btnDefs := [
        ["A", 0x1000], ["B", 0x2000], ["X", 0x4000], ["Y", 0x8000],
        ["LB", 0x0100], ["RB", 0x0200], ["Start", 0x0010],
        ["L3", 0x0040], ["R3", 0x0080]]
    static downTick := Map(
        "A", 0, "B", 0, "X", 0, "Y", 0, "LB", 0, "RB", 0,
        "Start", 0, "L3", 0, "R3", 0, "LT", 0, "RT", 0)
    static longFired := Map(
        "A", false, "B", false, "X", false, "Y", false,
        "LB", false, "RB", false, "Start", false,
        "L3", false, "R3", false, "LT", false, "RT", false)
    static prevTrigDown := Map("LT", false, "RT", false)
    ; A fixed list rather than enumerating downTick, so the reset never mutates
    ; a Map while iterating it.
    static trackedNames := [
        "A", "B", "X", "Y", "LB", "RB", "Start", "L3", "R3", "LT", "RT"]
    static lastCallTick := 0

    ; This runs only while an elevated window is foreground, so between episodes
    ; it is not called at all and its trackers freeze mid-press. Without this, a
    ; button held as Task Manager lost focus and released after it regained focus
    ; would fire a mapping the user never completed.
    resumed := lastCallTick = 0 || (now - lastCallTick) > 250
    lastCallTick := now

    ; Mirrors the helper's own suppression: while the Quick Menu or Settings
    ; chord is physically held, main is timing it and its buttons are not
    ; mappings.
    ;
    ; The automatic half is PUBLISHED to the helper here, on the same tick it is
    ; computed, so the two processes act on one answer instead of two that could
    ; not agree. This is the only place it needs publishing, because an elevated
    ; window being foreground is the only time the helper reads it.
    autoMouse := AutoMouseModeActive()
    SetElevatedAutoMouseRuntimeEnabled(autoMouse)
    viewDown := (buttons & 0x0020) || autoMouse
    if (resumed || chordActive || !viewDown) {
        for _, name in trackedNames {
            downTick[name] := 0
            longFired[name] := false
        }
        prevTrigDown["LT"] := false
        prevTrigDown["RT"] := false
        return
    }

    for def in btnDefs {
        name := def[1]
        mask := def[2]
        if (pressed & mask) {
            downTick[name] := now
            longFired[name] := false
        }
        if ((buttons & mask) && !longFired[name] && downTick[name]
            && (now - downTick[name]) >= ControllerChordHoldMs
            && ControllerBindingIsNormalIntegrityOnly(name ".Long")) {
            longFired[name] := true
            ExecuteControllerBinding(name ".Long")
        }
        if ((released & mask) && downTick[name]) {
            if (!longFired[name]
                && ControllerBindingIsNormalIntegrityOnly(name ".Short"))
                ExecuteControllerBinding(name ".Short")
            downTick[name] := 0
            longFired[name] := false
        }
    }

    for _, trigger in ["LT", "RT"] {
        triggerDown := (trigger = "LT") ? (lt > 30) : (rt > 30)
        triggerPressed := triggerDown && !prevTrigDown[trigger]
        triggerReleased := !triggerDown && prevTrigDown[trigger]
        prevTrigDown[trigger] := triggerDown
        if (triggerPressed) {
            downTick[trigger] := now
            longFired[trigger] := false
        }
        if (triggerDown && !longFired[trigger] && downTick[trigger]
            && (now - downTick[trigger]) >= ControllerChordHoldMs
            && ControllerBindingIsNormalIntegrityOnly(trigger ".Long")) {
            longFired[trigger] := true
            ExecuteControllerBinding(trigger ".Long")
        }
        if (triggerReleased && downTick[trigger]) {
            if (!longFired[trigger]
                && ControllerBindingIsNormalIntegrityOnly(trigger ".Short"))
                ExecuteControllerBinding(trigger ".Short")
            downTick[trigger] := 0
            longFired[trigger] := false
        }
    }
}

; Does this process own the given window?
;
; SHARED because ScriptPid is declared in both trees, which is the whole rule for
; naming a global in this file. It lived in the companion, where eight call sites
; used it, while the shell open-coded the same WinGetPID comparison inside the
; predicate below.
IsOurWindow(hwnd) {
    global ScriptPid
    if !hwnd
        return false
    pid := 0
    try pid := WinGetPID("ahk_id " hwnd)
    return pid = ScriptPid
}


; Does a Settings-family surface own the controller right now?
;
; Every window this process owns is a surface the user has to be able to move
; around, so this asks that question directly instead of naming windows. An
; enumerated list was tried in the shell and went stale, which is what lists of
; window names do.
;
; ONE FUNCTION FROM TWO, and the shell's was the more capable: it walks the OWNER
; CHAIN, and the companion only tested the active window's own PID. Native common
; dialogs -- a file picker, a colour chooser -- may be hosted OUTSIDE this
; process while being owned by one of our windows, so the companion answered
; false with a file picker on screen and the controller stopped being a pointer
; at the moment the pointer was the only way to finish the dialog. Taking the
; shell's version fixes that for the companion rather than preserving it as a
; difference.
;
; SettingsDialogActive still short-circuits: a native dialog's process may not be
; ours and may not be owned by us either, so the flag covers what the walk
; cannot. That flag had two names until the previous commit, and that is the only
; reason this function could not be shared before.
ControllerSettingsSurfaceActive() {
    global SettingsDialogActive
    if SettingsDialogActive
        return true
    activeHwnd := 0
    try activeHwnd := WinGetID("A")
    if !activeHwnd
        return false
    if IsOurWindow(activeHwnd)
        return true
    ownerHwnd := activeHwnd
    Loop 8 {
        ownerHwnd := DllCall(
            "User32\GetWindow", "Ptr", ownerHwnd, "UInt", 4, "Ptr") ; GW_OWNER
        if !ownerHwnd
            break
        if IsOurWindow(ownerHwnd)
            return true
    }
    return false
}


; Is the main Settings window itself the active window?
;
; Narrower than the predicate above deliberately: that one is true for any of our
; windows, this one only for the Settings window proper, which is what the
; category triggers and the controller-first navigation key off.
;
; ASKS THE WINDOW. The companion gated this on a SettingsVisible boolean it
; maintains by hand; the shell asked the window. Only the second can be shared,
; because SettingsVisible is declared in the companion alone and a shared
; function may name a global only when both trees declare it -- so the
; architecture chose here, and it chose the form that cannot go stale when a show
; or hide path forgets to set the flag. SettingsVisible remains in the companion
; for its other uses.
SettingsPrimaryActive() {
    global SettingsGui
    if !IsSet(SettingsGui)
        return false
    return GuiVisibleAndActive(SettingsGui)
}


; The stand-down, in one place.
;
; ResetControllerEdgeState clears the button and trigger tables; this adds the
; two View-button flags, and that pairing is what every stand-down in both
; products actually wants. It was a wrapper in the shell and four inline lines
; in the companion -- the same mechanism written twice, which is the whole
; reason the poll loops looked less alike than they are.
;
; The companion also cleared viewPressTick and viewUsedAsModifier at one of its
; stand-downs and the shell cleared them nowhere, and that difference is NOT
; carried here because it cannot matter: ControllerTrackViewButton writes
; pressTick and usedAsModifier on the rising edge of View, and reads pressTick
; only while wasDown is true -- which nothing but that same edge sets. Clearing
; wasDown, as this does, is therefore sufficient; a stale pressTick is
; unreachable until it has been overwritten.
; Discard every press/hold tracker, so a button held across an interruption
; cannot complete a Short or Long the user never finished.
;
; This existed as SEVEN hand-copied blocks inside PollController -- the same four
; statements written four slightly different ways, at every early return. XFE has
; had one function for this since it was written; standalone never got one, and a
; reset that has to be remembered seven times is a reset that will eventually be
; forgotten once. That matters more than tidiness: the hold-to-drag work adds
; "release any synthetic mouse button" to exactly this set, and a missed site
; there leaves a button held down in the Windows shell with no keyboard.
;
; previousViewDown is by reference because it is a plain Boolean; the Maps and
; the definition array are objects and already carry through. XFE sets its own
; copy separately at each call site, which is the same duplication one variable
; smaller -- aligning the two signatures is what lets this move into the shared
; input file rather than being written a third time for the helper.
ResetControllerHoldState(
        &previousViewDown, downTick, longFired, triggerDown, buttonDefinitions,
        &viewWasDown) {
    previousViewDown := false
    ; The View button's own press is a hold tracker too, so it is discarded here
    ; with the rest rather than at each call site. Left standing, a View held
    ; when the poll stood down -- the learner opening, the controller
    ; disconnecting, mouse mode being switched off -- is still "down" when the
    ; poll resumes, and the release after it reports a hold of however long the
    ; interruption lasted. That fires the hold action, which throws the Steam
    ; overlay up over whatever the user was doing.
    viewWasDown := false
    ResetControllerEdgeState(downTick, longFired, triggerDown, buttonDefinitions)
}


; One line per button edge and per trigger crossing, while DiagnosticLogging is
; on. The right granularity for diagnosing a pad, and far too much for an
; ordinary session -- which is why it is behind the flag that already exists for
; exactly this, and why the timer-driven ControllerDiagnosticTick is gated the
; same way.
;
; SHARED, and it was not. Both products ship the DiagnosticLogging row and both
; read it into EnableControllerDiagnostics; only the companion logged anything
; per report. So the same setting promised different things in the two products,
; and the half that was missing is the half that matters when a controller is
; unreadable -- which on the shell means a machine nobody can drive. Same shape
; as the XInput-slot row that shipped in both and had a tick behind it in one.
;
; The trigger edges are STATIC HERE rather than passed in. Each product compiles
; its own copy of this file into its own process, so a static in it is per
; program, which is exactly the lifetime the two per-tree pairs had -- and it
; removes them from both poll loops instead of moving them.
ControllerLogInputChange(buttons, lt, rt, pressed, released) {
    global EnableControllerDiagnostics, ActiveInputBackend, ActiveControllerIndex
    static ltDown := false
    static rtDown := false
    currentLt := lt > 30
    currentRt := rt > 30
    if (EnableControllerDiagnostics
        && (pressed || released || currentLt != ltDown || currentRt != rtDown)) {
        LogLine(
            "Controller input [" ActiveInputBackend "]"
            . (ActiveInputBackend = "xinput" ? " slot " ActiveControllerIndex : "")
            . ": buttons=0x" Format("{:04X}", buttons)
            . ", LT=" lt ", RT=" rt ".")
    }
    ltDown := currentLt
    rtDown := currentRt
}


; The settings BOTH products read identically, in one place.
;
; Twenty-seven keys, each of which was written out twice with the same global
; name, the same reader, the same default and the same clamp range -- so the two
; copies could only ever differ by one of them being edited and the other not,
; which is the definition of drift with no upside.
;
; A shared reader is possible here for the reason ProductSettingBool documents
; as the wall: these globals are declared in BOTH trees under the same names, so
; this file may name them. That is also the limit of it. A key that exists in
; one product only, or under a different global, stays in that product's own
; LoadSettings; there is nowhere shared to put a value whose home is per-tree.
;
; ReadBool/ReadInt/ReadNumber resolve to each tree's own wrapper, which binds its
; own settings path. That is the existing seam and the reason this works without
; knowing which product compiled it.
;
; ONE COMMON KEY IS DELIBERATELY NOT HERE, because unifying it would change
; behaviour rather than remove duplication:
;
;   EnableViewButtonActions        default false in the shell, true in the
;                                  companion
;
; It is a DEFAULT, and a default is a product's answer to "what should this do
; before anyone says otherwise". The two products answer differently for good
; reason, and an INI that sets the key explicitly is unaffected either way.
;
; EnableElevatedFrameCapWrites was the second of that pair and has joined the
; list above. The reason recorded for keeping it apart was that the companion is
; the unelevated product, so switching the helper on should be the user's
; decision -- and it did not survive checking what the installer already does.
; XFE's deployment writes the elevated helper payload to disk DORMANT and always
; has, so the binary was never the line the flag was defending. What the flag
; bought instead was a frame cap that silently did nothing whenever RTSS sits
; under Program Files, which is where RTSS installs itself, behind a checkbox on
; a page most people never open. The privilege boundary is untouched: elevated
; INPUT is still not ported to the companion, and a payload on disk is not a
; process until something needs a write only it can make.
;
; Three more used to be listed here -- ControllerPollIntervalMs,
; ControllerScrollIntervalMs and ControllerMouseFastMultiplier, same default in
; both trees and different CLAMPS. That is a different thing from a default: a
; clamp decides what an EXISTING user's INI is bounded to, so it was left for
; the maintainer rather than unified on the grounds that it looked like drift.
; It was drift, it has been decided, and the three moved into this function on
; the shell's wider bounds. See the note beside them below.
LoadSharedSettings() {
    global ControllerChordHoldMs, ControllerDeadzone, ControllerIndex
    global ControllerMouseFastMultiplier, ControllerMouseSpeed
    global ControllerPollIntervalMs, ControllerScrollIntervalMs
    global ControllerScrollStep
    global EnableControllerDiagnostics, EnableControllerMouseMode
    global EnableGameDetectionMenu, EnablePersistentMouseMode
    global EnableQuickMenu, EnableRTSSIntegration, EnableRawInputProbe
    global EnableViewHoldAction, EnableViewTapAction, GameLogIncludeTitles
    global GameLogIntervalMs, GameLogTopN, GameScoreMaxRows
    global QuickMenuChordHoldMs, RawInputStaleMs, RtssCustomFrameCap
    global RtssLastFrameCapFps, RtssPresetFrameCap
    global RtssElevatedFrameCapWrites
    global RtssRestoreFrameLimitOnStartup, RtssUseDllIntegration
    global ViewHoldInGameMs, ViewHoldMs
    EnableViewTapAction := ReadBool("Steam", "EnableViewTapAction", true)
    EnableViewHoldAction := ReadBool("Steam", "EnableViewHoldAction", true)
    ViewHoldMs := ReadInt("Steam", "ViewHoldMs", 500, 200, 5000)
    ViewHoldInGameMs := ReadInt("Steam", "ViewHoldInGameMs", 1000, 200, 5000)
    GameLogTopN := ReadInt("Logging", "GameLogTopN", 3, 1, 10)
    GameLogIntervalMs := ReadInt("Logging", "GameLogIntervalMs", 3000, 250, 60000)
    GameLogIncludeTitles := ReadBool("Logging", "GameLogIncludeTitles", true)
    EnableControllerMouseMode := ReadBool("Controller", "EnableControllerMouseMode", true)
    EnablePersistentMouseMode := ReadBool("Controller", "EnablePersistentMouseMode", false)
    EnableRawInputProbe := ReadBool("Controller", "RawInputProbe", false)
    EnableControllerDiagnostics := ReadBool("Controller", "DiagnosticLogging", false)
    RawInputStaleMs := ReadInt("Controller", "RawInputStaleMs", 5000, 500, 60000)
    ControllerIndex := ReadInt("Controller", "ControllerIndex", 0, 0, 3)
    ControllerDeadzone := ReadInt("Controller", "ControllerDeadzone", 3000, 0, 32000)
    ControllerMouseSpeed := ReadInt("Controller", "ControllerMouseSpeed", 3200, 200, 12000)
    ControllerScrollStep := ReadInt("Controller", "ControllerScrollStep", 1, 1, 10)
    ControllerChordHoldMs := ReadInt("Controller", "ControllerChordHoldMs", 500, 100, 3000)
    ; These three had the same default in both trees and DIFFERENT clamps -- 5-200
    ; against 8-100, 10-1000 against 20-500, 1.0-10.0 against 1-6. The companion
    ; already carried a comment saying its bounds matched the shell's deliberately
    ; and gave the reason, and the bounds did not match; the reason is right and
    ; is why they are the shell's wider pair here rather than the companion's:
    ;
    ; This is ONE setting and the Quick Menu row that steps it is SHARED. A range
    ; the row can step outside of, or one the row cannot reach, makes the row lie
    ; -- it shows a value that the next reload clamps away.
    ;
    ; Widened rather than narrowed, which is the only direction that cannot
    ; change what an existing INI already means: every value the narrow range
    ; accepted the wide one accepts unchanged, so nobody's configuration moves
    ; under them. Narrowing would have silently reduced a shell user's poll
    ; interval of 5 to 8.
    ControllerPollIntervalMs := ReadInt("Controller", "ControllerPollIntervalMs", 15, 5, 200)
    ControllerScrollIntervalMs := ReadInt("Controller", "ControllerScrollIntervalMs", 80, 10, 1000)
    ControllerMouseFastMultiplier := ReadNumber(
        "Controller", "ControllerMouseFastMultiplier", 2.5, 1.0, 10.0)
    EnableQuickMenu := ReadBool("QuickMenu", "Enable", true)
    EnableGameDetectionMenu := ReadBool("QuickMenu", "ShowGameDetection", true)
    GameScoreMaxRows := ReadInt("QuickMenu", "GameScoreMaxRows", 8, 1, 20)
    QuickMenuChordHoldMs := ReadInt("QuickMenu", "ChordHoldMs", 500, 250, 3000)
    EnableRTSSIntegration := ReadBool("RTSS", "EnableIntegration", true)
    RtssUseDllIntegration := ReadBool("RTSS", "UseDllIntegration", true)
    RtssPresetFrameCap := ReadInt("RTSS", "PresetFrameCap", 158, 0, 1000)
    RtssCustomFrameCap := ReadInt("RTSS", "CustomFrameCap", 158, 10, 1000)
    RtssRestoreFrameLimitOnStartup := ReadBool("RTSS", "RestoreFrameLimitOnStartup", true)
    ; Defaulted TRUE in both products now. The companion defaulted it false on
    ; the grounds that it is the unelevated product and switching the helper on
    ; should be a decision -- but its installer already writes the helper payload
    ; to disk dormant, so the binary was never the line the flag was defending.
    ; What the flag actually bought was a frame cap that silently does nothing
    ; whenever RTSS sits under Program Files, which is where RTSS installs
    ; itself, behind a checkbox on a page most people never open.
    RtssElevatedFrameCapWrites := ReadBool("RTSS", "EnableElevatedFrameCapWrites", true)
    RtssLastFrameCapFps := ReadInt("RTSS", "LastFrameCapFps", 0, 0, 1000)
}
