; ==============================================================================
; SteamShell Elevated Window Helper
; Handles controller mouse/mapped input and coordinated window geometry while
; a High/System-integrity application is involved. SteamShell.exe remains the
; normal-integrity shell and owns every visible SteamShell UI.
; ==============================================================================
#Requires AutoHotkey v2.0.19 64-bit
#SingleInstance Force
#NoTrayIcon
;@Ahk2Exe-SetName SteamShell Elevated Window Helper
;@Ahk2Exe-SetDescription Elevated-window controller input and geometry for SteamShell
;@Ahk2Exe-SetVersion 1.9.9.1

Persistent
SendMode "Input"
CoordMode "Mouse", "Screen"

global HelperVersion := "1.9.9"
global ParentPid := 0
global MainPath := ""
global SettingsPath := ""
global LogPath := ""
global ControllerIndex := 0
global PollIntervalMs := 16
global Deadzone := 3000
global MouseSpeed := 100
global FastMultiplier := 2.5
global ScrollIntervalMs := 80
global ScrollStep := 1
global ChordHoldMs := 500
global EnableControllerMouse := true
global PersistentMouseMode := false
global EnableAutoMouseMode := true
global EnableDesktopAutoMouseMode := true
global AutoMouseExeSet := Map()
global DesktopExcludeExeSet := Map()
global EnableWindowManagement := true
global MinWidthPercent := 0.30
global WmExcludeExeSet := Map()
global WmExcludeClassSet := Map()
global ElevatedGeometryState := Map()
global GeometryEventHandle := 0
global ElevatedSafeAutoExeSet := Map(
    "taskmgr.exe", true,
    "mmc.exe", true,
    "control.exe", true,
    "systemsettingsadminflows.exe", true)
global ControllerMap := Map()
global XInputDll := ""

ReadArgument(name, fallback := "") {
    prefix := "--" StrLower(name) "="
    for _, argument in A_Args {
        if (InStr(StrLower(argument), prefix) = 1)
            return SubStr(argument, StrLen(prefix) + 1)
    }
    return fallback
}

GetProcessIdentity(pid, &sidText, &sessionId, &failureReason) {
    static PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    static TOKEN_QUERY := 0x0008
    sidText := ""
    sessionId := -1
    failureReason := ""
    processHandle := DllCall(
        "Kernel32\OpenProcess",
        "UInt", PROCESS_QUERY_LIMITED_INFORMATION,
        "Int", false,
        "UInt", pid,
        "Ptr")
    if !processHandle {
        failureReason := "OpenProcess failed (" A_LastError ")."
        return false
    }
    tokenHandle := 0
    if !DllCall(
        "Advapi32\OpenProcessToken",
        "Ptr", processHandle,
        "UInt", TOKEN_QUERY,
        "Ptr*", &tokenHandle,
        "Int") {
        failureReason := "OpenProcessToken failed (" A_LastError ")."
        DllCall("Kernel32\CloseHandle", "Ptr", processHandle, "Int")
        return false
    }
    try {
        needed := 0
        DllCall("Advapi32\GetTokenInformation", "Ptr", tokenHandle,
            "Int", 1, "Ptr", 0, "UInt", 0, "UInt*", &needed, "Int")
        if (needed <= 0) {
            failureReason := "The token-user buffer size was unavailable."
            return false
        }
        tokenUser := Buffer(needed, 0)
        if !DllCall("Advapi32\GetTokenInformation", "Ptr", tokenHandle,
            "Int", 1, "Ptr", tokenUser, "UInt", tokenUser.Size,
            "UInt*", &needed, "Int") {
            failureReason := "The token user could not be read (" A_LastError ")."
            return false
        }
        sid := NumGet(tokenUser, 0, "Ptr")
        stringSid := 0
        if !sid || !DllCall(
            "Advapi32\ConvertSidToStringSidW", "Ptr", sid,
            "Ptr*", &stringSid, "Int") {
            failureReason := "The token SID could not be converted (" A_LastError ")."
            return false
        }
        try sidText := StrGet(stringSid, "UTF-16")
        finally DllCall("Kernel32\LocalFree", "Ptr", stringSid, "Ptr")
        if !DllCall("Kernel32\ProcessIdToSessionId", "UInt", pid,
            "UInt*", &sessionId, "Int") {
            failureReason := "The helper session could not be read (" A_LastError ")."
            return false
        }
        return sidText != "" && sessionId >= 0
    } finally {
        DllCall("Kernel32\CloseHandle", "Ptr", tokenHandle, "Int")
        DllCall("Kernel32\CloseHandle", "Ptr", processHandle, "Int")
    }
}

FindMainProcess() {
    global MainPath
    if (MainPath = "")
        return 0
    snapshot := DllCall(
        "CreateToolhelp32Snapshot", "UInt", 0x00000002, "UInt", 0, "Ptr")
    if (snapshot = -1 || snapshot = 0)
        return 0
    entrySize := A_PtrSize = 8 ? 568 : 556
    entry := Buffer(entrySize, 0)
    NumPut("UInt", entrySize, entry, 0)
    try {
        if !DllCall("Process32FirstW", "Ptr", snapshot, "Ptr", entry)
            return 0
        Loop {
            pid := NumGet(entry, 8, "UInt")
            processName := StrLower(StrGet(
                entry.Ptr + (A_PtrSize = 8 ? 44 : 36), "UTF-16"))
            if (processName = "steamshell.exe") {
                processPath := ""
                try processPath := ProcessGetPath(pid)
                if (processPath != ""
                    && StrLower(processPath) = StrLower(MainPath))
                    return pid
            }
            if !DllCall("Process32NextW", "Ptr", snapshot, "Ptr", entry)
                break
        }
    } finally {
        DllCall("CloseHandle", "Ptr", snapshot)
    }
    return 0
}

OpenParentGeometryEvent() {
    global ParentPid, GeometryEventHandle
    if GeometryEventHandle
        return true
    if !ParentPid
        return false
    GeometryEventHandle := DllCall(
        "Kernel32\OpenEventW",
        "UInt", 0x00100000, ; SYNCHRONIZE
        "Int", false,
        "WStr", "Local\SteamShellGeometry-" ParentPid,
        "Ptr")
    return GeometryEventHandle != 0
}

ParentAllowsElevatedGeometry() {
    global GeometryEventHandle
    if !GeometryEventHandle && !OpenParentGeometryEvent()
        return false
    return DllCall(
        "Kernel32\WaitForSingleObject",
        "Ptr", GeometryEventHandle,
        "UInt", 0,
        "UInt") = 0 ; WAIT_OBJECT_0
}

CleanIni(value, fallback := "") {
    value := Trim(value)
    commentPos := RegExMatch(value, "(^|\s)[;#]")
    if commentPos
        value := commentPos = 1 ? "" : Trim(SubStr(value, 1, commentPos - 1))
    return value = "" ? fallback : value
}

ReadBool(section, key, fallback := false) {
    value := fallback ? "true" : "false"
    try value := CleanIni(IniRead(SettingsPath, section, key, value), value)
    value := StrLower(value)
    if (value = "true" || value = "yes" || value = "on" || value = "1")
        return true
    if (value = "false" || value = "no" || value = "off" || value = "0")
        return false
    return fallback
}

ReadInt(section, key, fallback, minimum, maximum) {
    value := fallback
    try value := Integer(CleanIni(IniRead(SettingsPath, section, key, fallback), fallback))
    catch
        value := fallback
    return Min(maximum, Max(minimum, value))
}

ReadFloat(section, key, fallback, minimum, maximum) {
    value := fallback
    try value := Number(CleanIni(IniRead(SettingsPath, section, key, fallback), fallback))
    catch
        value := fallback
    return Min(maximum, Max(minimum, value))
}

ParseExeSet(value) {
    result := Map()
    for _, item in StrSplit(value, "|") {
        item := StrLower(Trim(item))
        if (item != "") {
            if !InStr(item, ".")
                item .= ".exe"
            result[item] := true
        }
    }
    return result
}

ParseClassSet(value) {
    result := Map()
    for _, item in StrSplit(value, "|") {
        item := StrLower(Trim(item))
        if (item != "")
            result[item] := true
    }
    return result
}

LogLine(message, level := "Info") {
    global LogPath
    if (LogPath = "")
        return
    try {
        SplitPath(LogPath, , &directory)
        if (directory != "")
            DirCreate(directory)
        FileAppend(
            FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " [" level "] " message "`r`n",
            LogPath, "UTF-8")
    }
}

LoadConfiguration() {
    global ControllerIndex, PollIntervalMs, Deadzone, MouseSpeed
    global FastMultiplier, ScrollIntervalMs, ScrollStep, ChordHoldMs
    global EnableControllerMouse, PersistentMouseMode
    global EnableAutoMouseMode, EnableDesktopAutoMouseMode
    global AutoMouseExeSet, DesktopExcludeExeSet, ControllerMap
    global EnableWindowManagement, MinWidthPercent
    global WmExcludeExeSet, WmExcludeClassSet, ElevatedGeometryState

    if !FileExist(SettingsPath)
        return false
    EnableControllerMouse := ReadBool(
        "Controller", "EnableControllerMouseMode", true)
    PersistentMouseMode := ReadBool(
        "Controller", "EnablePersistentMouseMode", false)
    EnableAutoMouseMode := ReadBool(
        "Features", "EnableAutoMouseMode", true)
    EnableDesktopAutoMouseMode := ReadBool(
        "Features", "EnableDesktopAutoMouseMode", true)
    ControllerIndex := ReadInt("Controller", "ControllerIndex", 0, 0, 3)
    PollIntervalMs := ReadInt(
        "Controller", "ControllerPollIntervalMs", 16, 8, 100)
    Deadzone := ReadInt("Controller", "ControllerDeadzone", 3000, 0, 20000)
    MouseSpeed := ReadInt("Controller", "ControllerMouseSpeed", 100, 1, 500)
    FastMultiplier := ReadFloat(
        "Controller", "ControllerMouseFastMultiplier", 2.5, 1.0, 10.0)
    ScrollIntervalMs := ReadInt(
        "Controller", "ControllerScrollIntervalMs", 80, 10, 1000)
    ScrollStep := ReadInt("Controller", "ControllerScrollStep", 1, 1, 10)
    ChordHoldMs := ReadInt(
        "Controller", "ControllerChordHoldMs", 500, 100, 2000)
    try AutoMouseExeSet := ParseExeSet(CleanIni(
        IniRead(SettingsPath, "Controller", "AutoMouseExeList", "explorer.exe"),
        "explorer.exe"))
    try DesktopExcludeExeSet := ParseExeSet(CleanIni(
        IniRead(SettingsPath, "Controller", "DesktopAutoMouseExcludeExeList", ""), ""))
    EnableWindowManagement := ReadBool(
        "Features", "EnableWindowManagement", true)
    MinWidthPercent := ReadFloat(
        "WindowManagement", "MinWidthPercent", 0.30, 0.05, 1.00)
    try WmExcludeExeSet := ParseExeSet(CleanIni(
        IniRead(SettingsPath, "WindowManagement", "ExcludeExeList", ""), ""))
    try WmExcludeClassSet := ParseClassSet(CleanIni(
        IniRead(SettingsPath, "WindowManagement", "ExcludeClassList", ""), ""))
    ElevatedGeometryState := Map()

    ControllerMap := Map()
    defaults := Map(
        "RB.Short", "Builtin:LeftClick", "RB.Long", "Builtin:None",
        "RT.Short", "Builtin:RightClick", "RT.Long", "Builtin:None",
        "LT.Short", "Send:^+o", "LT.Long", "Send:^+f",
        "LB.Short", "Send:^!{Tab}", "LB.Long", "Builtin:TaskManager",
        "A.Short", "Builtin:Enter", "A.Long", "Builtin:None",
        "B.Short", "Builtin:Esc", "B.Long", "Builtin:AltF4",
        "X.Short", "Builtin:TabTip", "X.Long", "Builtin:OSK",
        "Y.Short", "Builtin:WinG", "Y.Long", "Builtin:None",
        "Start.Short", "Builtin:StartMenu", "Start.Long", "Builtin:Explorer",
        "L3.Short", "Builtin:None", "L3.Long", "Builtin:None",
        "R3.Short", "Builtin:None", "R3.Long", "Builtin:None")
    for key, fallback in defaults {
        value := fallback
        try value := CleanIni(IniRead(SettingsPath, "ControllerMap", key, fallback), fallback)
        if (SubStr(value, 1, 5) != "Send:" && SubStr(value, 1, 8) != "Builtin:")
            value := "Send:" value
        ControllerMap[key] := value
    }
    return true
}

InitXInput() {
    global XInputDll
    for _, dllName in ["xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"] {
        try {
            if DllCall("GetModuleHandle", "Str", dllName, "Ptr")
                || DllCall("LoadLibrary", "Str", dllName, "Ptr") {
                XInputDll := dllName
                return true
            }
        }
    }
    return false
}

GetXInputState(&state) {
    global XInputDll, ControllerIndex
    if (XInputDll = "" && !InitXInput())
        return false
    try return DllCall(
        XInputDll "\XInputGetState", "UInt", ControllerIndex, "Ptr", state, "UInt") = 0
    catch {
        XInputDll := ""
        return false
    }
}

ProcessIntegrityRid(pid) {
    static PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    static TOKEN_QUERY := 0x0008
    processHandle := DllCall(
        "OpenProcess", "UInt", PROCESS_QUERY_LIMITED_INFORMATION,
        "Int", false, "UInt", pid, "Ptr")
    if !processHandle
        return 0
    tokenHandle := 0
    try {
        if !DllCall("Advapi32\OpenProcessToken", "Ptr", processHandle,
            "UInt", TOKEN_QUERY, "Ptr*", &tokenHandle, "Int")
            return 0
        needed := 0
        DllCall("Advapi32\GetTokenInformation", "Ptr", tokenHandle,
            "Int", 25, "Ptr", 0, "UInt", 0, "UInt*", &needed, "Int")
        if (needed <= 0)
            return 0
        tokenInfo := Buffer(needed, 0)
        if !DllCall("Advapi32\GetTokenInformation", "Ptr", tokenHandle,
            "Int", 25, "Ptr", tokenInfo, "UInt", tokenInfo.Size,
            "UInt*", &needed, "Int")
            return 0
        sid := NumGet(tokenInfo, 0, "Ptr")
        countPtr := DllCall("Advapi32\GetSidSubAuthorityCount", "Ptr", sid, "Ptr")
        if !countPtr
            return 0
        count := NumGet(countPtr, 0, "UChar")
        if (count <= 0)
            return 0
        ridPtr := DllCall(
            "Advapi32\GetSidSubAuthority", "Ptr", sid, "UInt", count - 1, "Ptr")
        return ridPtr ? NumGet(ridPtr, 0, "UInt") : 0
    } finally {
        if tokenHandle
            DllCall("CloseHandle", "Ptr", tokenHandle)
        DllCall("CloseHandle", "Ptr", processHandle)
    }
}

ElevatedGeometryIsCloaked(hwnd) {
    cloaked := 0
    try {
        return DllCall(
            "Dwmapi\DwmGetWindowAttribute",
            "Ptr", hwnd,
            "UInt", 14,
            "UInt*", &cloaked,
            "UInt", 4,
            "Int") = 0 && cloaked != 0
    } catch {
        return false
    }
}

ElevatedGeometryBuildItem(hwnd) {
    global WmExcludeExeSet, WmExcludeClassSet
    static WS_CHILD := 0x40000000
    static WS_CAPTION := 0x00C00000
    static WS_VISIBLE := 0x10000000
    static WS_EX_TOOLWINDOW := 0x00000080
    static WS_EX_NOACTIVATE := 0x08000000
    static MIN_CENTER_COVERAGE := 0.40
    static POPUP_CLASSES := Map(
        "#32768", true,
        "combolbox", true,
        "dropdown", true,
        "tooltips_class32", true,
        "auto-suggest dropdown", true)

    if !hwnd || !DllCall("User32\IsWindow", "Ptr", hwnd, "Int")
        || ElevatedGeometryIsCloaked(hwnd)
        return 0
    id := "ahk_id " hwnd
    try {
        style := WinGetStyle(id) + 0
        if !(style & WS_VISIBLE)
            return 0
        exStyle := WinGetExStyle(id) + 0
        pid := WinGetPID(id)
        if !pid || pid = DllCall("Kernel32\GetCurrentProcessId", "UInt")
            return 0
        if ProcessIntegrityRid(pid) < 0x3000
            return 0
        title := WinGetTitle(id)
        winClass := WinGetClass(id)
        proc := StrLower(WinGetProcessName(id))
        minMax := WinGetMinMax(id)
        WinGetPos(&x, &y, &width, &height, id)
    } catch {
        return 0
    }
    classLower := StrLower(winClass)
    titleLower := StrLower(title)
    if (title = "" || minMax != 0 || width <= 0 || height <= 0)
        return 0
    if WmExcludeExeSet.Has(proc) || WmExcludeClassSet.Has(classLower)
        return 0
    if (proc = "osk.exe" || classLower = "oskmainclass"
        || InStr(titleLower, "on-screen keyboard")
        || (proc = "steam.exe" && InStr(titleLower, "keyboard")))
        return 0
    if (style & WS_CHILD) || (exStyle & WS_EX_NOACTIVATE)
        return 0
    if !(style & WS_CAPTION) {
        if (width < A_ScreenWidth * MIN_CENTER_COVERAGE
            || height < A_ScreenHeight * MIN_CENTER_COVERAGE)
            return 0
    }
    if ((exStyle & WS_EX_TOOLWINDOW)
        && (width < A_ScreenWidth * MIN_CENTER_COVERAGE
            || height < A_ScreenHeight * MIN_CENTER_COVERAGE))
        return 0
    if POPUP_CLASSES.Has(classLower)
        return 0
    return Map(
        "hwnd", hwnd,
        "pid", pid,
        "proc", proc,
        "title", title,
        "class", winClass,
        "style", style,
        "x", x,
        "y", y,
        "w", width,
        "h", height)
}

ElevatedGeometrySignature(item) {
    return item["x"] "," item["y"] "," item["w"] "," item["h"] "," item["style"]
}

ElevatedWindowGeometryTick(*) {
    global ParentPid, MainPath, EnableWindowManagement, MinWidthPercent
    global ElevatedGeometryState
    static inTick := false
    static RETRY_MS := 1000
    static MAX_ATTEMPTS := 3
    static SETTLE_MS := 500
    if inTick
        return
    if !ParentPid && MainPath != ""
        ParentPid := FindMainProcess()
    if ParentPid && !ProcessExist(ParentPid) {
        LogLine("Parent SteamShell process exited; helper stopping.")
        ExitApp()
    }
    if !EnableWindowManagement || !ParentAllowsElevatedGeometry() {
        if ElevatedGeometryState.Count
            ElevatedGeometryState := Map()
        return
    }

    inTick := true
    try {
        now := A_TickCount
        seen := Map()
        for hwnd in WinGetList() {
            item := ElevatedGeometryBuildItem(hwnd)
            if !IsObject(item)
                continue
            seen[hwnd] := true
            signature := ElevatedGeometrySignature(item)
            if !ElevatedGeometryState.Has(hwnd)
                || ElevatedGeometryState[hwnd]["pid"] != item["pid"] {
                ElevatedGeometryState[hwnd] := Map(
                    "pid", item["pid"],
                    "signature", signature,
                    "lastSeen", now,
                    "nextAttempt", now + SETTLE_MS,
                    "ignoreChangesUntil", 0,
                    "actionWindowStart", now,
                    "attempts", 0,
                    "suppressedUntil", 0)
            }
            state := ElevatedGeometryState[hwnd]
            state["lastSeen"] := now
            if (state["signature"] != signature) {
                if (now >= state["ignoreChangesUntil"]) {
                    state["actionWindowStart"] := now
                    state["attempts"] := 0
                    state["suppressedUntil"] := 0
                    state["nextAttempt"] := now + SETTLE_MS
                }
                state["signature"] := signature
            }
            if (now < state["nextAttempt"] || now < state["suppressedUntil"])
                continue
            if (now - state["actionWindowStart"] > 10000) {
                state["actionWindowStart"] := now
                state["attempts"] := 0
            }
            if (state["attempts"] >= MAX_ATTEMPTS) {
                state["suppressedUntil"] := state["actionWindowStart"] + 10000
                continue
            }

            targetX := Round((A_ScreenWidth - item["w"]) / 2)
            targetY := Round((A_ScreenHeight - item["h"]) / 2)
            needsMove := Abs(item["x"] - targetX) > 2
                || Abs(item["y"] - targetY) > 2
            canMaximize := (item["style"] & 0x00010000)
                || (item["style"] & 0x00040000)
            needsMaximize := item["w"] >= A_ScreenWidth * MinWidthPercent
                && canMaximize
            if !needsMove && !needsMaximize {
                state["nextAttempt"] := now + 5000
                continue
            }
            if !DllCall("User32\IsWindow", "Ptr", hwnd, "Int")
                continue

            id := "ahk_id " hwnd
            moved := false
            maximized := false
            if needsMove {
                try {
                    WinMove(targetX, targetY,,, id)
                    moved := true
                }
            }
            if needsMaximize {
                try {
                    WinMaximize(id)
                    maximized := true
                }
            }
            state["attempts"] += 1
            state["nextAttempt"] := now + RETRY_MS
            state["ignoreChangesUntil"] := now + RETRY_MS
            if moved || maximized {
                LogLine(
                    "Elevated geometry: "
                    . (moved ? "centered" : "")
                    . (moved && maximized ? " and " : "")
                    . (maximized ? "maximized" : "")
                    . " " item["proc"] " [" item["class"] "] | " item["title"] ".")
            } else if (state["attempts"] = MAX_ATTEMPTS) {
                LogLine(
                    "Elevated geometry could not update " item["proc"]
                    . " [" item["class"] "] after " MAX_ATTEMPTS " attempts.",
                    "Warning")
            }
        }

        staleHwnds := []
        for hwnd, state in ElevatedGeometryState {
            if !seen.Has(hwnd) && now - state["lastSeen"] > 10000
                staleHwnds.Push(hwnd)
        }
        for _, hwnd in staleHwnds
            ElevatedGeometryState.Delete(hwnd)
    } catch as err {
        LogLine("Elevated geometry tick failed: " err.Message, "Warning")
    } finally {
        inTick := false
    }
}

HelperExitCleanup(reason, code) {
    global GeometryEventHandle
    if GeometryEventHandle {
        try DllCall("Kernel32\CloseHandle", "Ptr", GeometryEventHandle, "Int")
        GeometryEventHandle := 0
    }
    LogLine("Elevated window helper stopped: " reason ".")
}

ElevatedForeground(&exeName) {
    exeName := ""
    hwnd := DllCall("GetForegroundWindow", "Ptr")
    if !hwnd
        return false
    pid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
    if !pid || pid = DllCall("GetCurrentProcessId", "UInt")
        return false
    try exeName := StrLower(ProcessGetName(pid))
    return ProcessIntegrityRid(pid) >= 0x3000
}

HasLongBinding(buttonName) {
    global ControllerMap
    value := ControllerMap.Has(buttonName ".Long")
        ? ControllerMap[buttonName ".Long"] : ""
    return value != "" && StrLower(value) != "builtin:none"
}

ExecuteBinding(key) {
    global ControllerMap
    if !ControllerMap.Has(key)
        return
    value := ControllerMap[key]
    if (value = "" || StrLower(value) = "builtin:none")
        return
    if (SubStr(value, 1, 5) = "Send:") {
        ; A writable INI must never become an arbitrary high-integrity
        ; keystroke bridge. Custom Send: bindings remain main-process features
        ; and are intentionally ignored for elevated foreground windows.
        return
    }
    if (SubStr(value, 1, 8) != "Builtin:")
        return
    action := StrLower(SubStr(value, 9))
    switch action {
        case "leftclick":
            try Click("Left")
        case "rightclick":
            try Click("Right")
        case "enter":
            try SendInput("{Enter}")
        case "esc":
            try SendInput("{Esc}")
        case "altf4":
            try SendInput("!{F4}")
    }
}

ResetInputState(downTick, longFired, previousTriggers) {
    for buttonName, _ in downTick {
        downTick[buttonName] := 0
        longFired[buttonName] := false
    }
    previousTriggers["LT"] := false
    previousTriggers["RT"] := false
}

PollController() {
    global ParentPid, MainPath, EnableControllerMouse, PersistentMouseMode
    global EnableAutoMouseMode, EnableDesktopAutoMouseMode
    global AutoMouseExeSet, DesktopExcludeExeSet, ElevatedSafeAutoExeSet
    global Deadzone, MouseSpeed, FastMultiplier, ScrollIntervalMs, ScrollStep
    global ChordHoldMs
    static state := Buffer(16, 0)
    static previousButtons := 0
    static lastScrollTick := 0
    static downTick := Map(
        "A", 0, "B", 0, "X", 0, "Y", 0, "LB", 0, "RB", 0,
        "Start", 0, "L3", 0, "R3", 0, "LT", 0, "RT", 0)
    static longFired := Map(
        "A", false, "B", false, "X", false, "Y", false,
        "LB", false, "RB", false, "Start", false,
        "L3", false, "R3", false, "LT", false, "RT", false)
    static previousTriggers := Map("LT", false, "RT", false)
    static lastSettingsCheck := 0
    static lastSettingsStamp := ""
    static buttonDefinitions := [
        ["A", 0x1000], ["B", 0x2000], ["X", 0x4000], ["Y", 0x8000],
        ["LB", 0x0100], ["RB", 0x0200], ["Start", 0x0010],
        ["L3", 0x0040], ["R3", 0x0080]]

    if !ParentPid && MainPath != ""
        ParentPid := FindMainProcess()
    if ParentPid && !ProcessExist(ParentPid) {
        LogLine("Parent SteamShell process exited; helper stopping.")
        ExitApp()
    }
    if (A_TickCount - lastSettingsCheck >= 1000) {
        lastSettingsCheck := A_TickCount
        settingsStamp := ""
        try settingsStamp := FileGetTime(SettingsPath, "M")
        if (settingsStamp != "" && lastSettingsStamp != ""
            && settingsStamp != lastSettingsStamp) {
            if LoadConfiguration()
                LogLine("Controller configuration reloaded after settings changed.")
        }
        lastSettingsStamp := settingsStamp
    }
    if !EnableControllerMouse || !ElevatedForeground(&foregroundExe) {
        previousButtons := 0
        ResetInputState(downTick, longFired, previousTriggers)
        return
    }
    if !GetXInputState(&state) {
        previousButtons := 0
        ResetInputState(downTick, longFired, previousTriggers)
        return
    }

    buttons := NumGet(state, 4, "UShort")
    leftTrigger := NumGet(state, 6, "UChar")
    rightTrigger := NumGet(state, 7, "UChar")
    leftY := NumGet(state, 10, "Short")
    rightX := NumGet(state, 12, "Short")
    rightY := NumGet(state, 14, "Short")
    if Abs(leftY) < Deadzone
        leftY := 0
    if Abs(rightX) < Deadzone
        rightX := 0
    if Abs(rightY) < Deadzone
        rightY := 0

    autoMouse := PersistentMouseMode
        || (EnableAutoMouseMode && AutoMouseExeSet.Has(foregroundExe))
        || (EnableAutoMouseMode && EnableDesktopAutoMouseMode
            && ElevatedSafeAutoExeSet.Has(foregroundExe)
            && !DesktopExcludeExeSet.Has(foregroundExe))
    viewDown := (buttons & 0x0020) || autoMouse
    pressed := buttons & ~previousButtons
    released := (~buttons) & previousButtons
    previousButtons := buttons
    ; Main SteamShell exclusively owns its Quick Menu and emergency Settings
    ; chords, even over an elevated foreground. Never let their constituent
    ; buttons become helper mappings while the main process is timing the hold.
    quickMenuChord := (buttons & 0x0040) && (buttons & 0x0080)
        && !(buttons & 0x0020) && !(buttons & 0x0010)
        && !(buttons & 0x0100) && !(buttons & 0x0200)
        && leftTrigger <= 30 && rightTrigger <= 30
    settingsChord := leftTrigger > 30 && rightTrigger > 30
        && (buttons & 0x0100) && (buttons & 0x0200)
        && (buttons & 0x0040) && (buttons & 0x0080)
    if quickMenuChord || settingsChord {
        ResetInputState(downTick, longFired, previousTriggers)
        return
    }
    if !viewDown {
        ResetInputState(downTick, longFired, previousTriggers)
        return
    }

    now := A_TickCount
    if (rightX != 0 || rightY != 0) {
        speed := rightTrigger > 30 ? Round(MouseSpeed * FastMultiplier) : MouseSpeed
        deltaX := Round((rightX / 32767.0) * speed)
        deltaY := Round((-rightY / 32767.0) * speed)
        if (deltaX != 0 || deltaY != 0)
            try MouseMove(deltaX, deltaY, 0, "R")
    }
    if leftY != 0 && now - lastScrollTick >= ScrollIntervalMs {
        lastScrollTick := now
        Loop ScrollStep
            try SendInput(leftY > 0 ? "{WheelUp}" : "{WheelDown}")
    }

    for _, definition in buttonDefinitions {
        buttonName := definition[1]
        mask := definition[2]
        if pressed & mask {
            downTick[buttonName] := now
            longFired[buttonName] := false
        }
        if (buttons & mask) && !longFired[buttonName]
            && downTick[buttonName]
            && now - downTick[buttonName] >= ChordHoldMs
            && HasLongBinding(buttonName) {
            longFired[buttonName] := true
            ExecuteBinding(buttonName ".Long")
        }
        if released & mask && downTick[buttonName] {
            if !longFired[buttonName]
                ExecuteBinding(buttonName ".Short")
            downTick[buttonName] := 0
            longFired[buttonName] := false
        }
    }

    for _, triggerName in ["LT", "RT"] {
        triggerDown := triggerName = "LT" ? leftTrigger > 30 : rightTrigger > 30
        triggerPressed := triggerDown && !previousTriggers[triggerName]
        triggerReleased := !triggerDown && previousTriggers[triggerName]
        previousTriggers[triggerName] := triggerDown
        if triggerPressed {
            downTick[triggerName] := now
            longFired[triggerName] := false
        }
        if triggerDown && !longFired[triggerName]
            && downTick[triggerName]
            && now - downTick[triggerName] >= ChordHoldMs
            && HasLongBinding(triggerName) {
            longFired[triggerName] := true
            ExecuteBinding(triggerName ".Long")
        }
        if triggerReleased && downTick[triggerName] {
            if !longFired[triggerName]
                ExecuteBinding(triggerName ".Short")
            downTick[triggerName] := 0
            longFired[triggerName] := false
        }
    }

    if pressed & 0x0001
        try SendInput("{Up}")
    if pressed & 0x0002
        try SendInput("{Down}")
    if pressed & 0x0004
        try SendInput("{Left}")
    if pressed & 0x0008
        try SendInput("{Right}")
}

ParentPid := Integer(ReadArgument("parent-pid", "0"))
MainPath := ReadArgument("main-path", "")
SettingsPath := ReadArgument("settings", "")
LogPath := ReadArgument("log", "")
identityError := ""
parentIdentityError := ""
if !A_IsAdmin {
    MsgBox("SteamShell-Helper must run elevated.", "SteamShell Helper", "Iconx")
    ExitApp()
}
if !ParentPid && MainPath != ""
    ParentPid := FindMainProcess()
if !ParentPid || !ProcessExist(ParentPid) || SettingsPath = "" {
    LogLine("Invalid helper launch arguments; helper stopping.", "Error")
    ExitApp()
}
selfPid := DllCall("Kernel32\GetCurrentProcessId", "UInt")
if (!GetProcessIdentity(
        selfPid, &actualUserSid, &actualSessionId, &identityError)
    || !GetProcessIdentity(
        ParentPid, &parentUserSid, &parentSessionId, &parentIdentityError)
    || StrLower(actualUserSid) != StrLower(parentUserSid)
    || actualSessionId != parentSessionId) {
    LogLine(
        "Helper identity/session did not match its parent; helper stopping. "
        . identityError " " parentIdentityError, "Error")
    ExitApp()
}
if !OpenParentGeometryEvent()
    LogLine(
        "The parent geometry event could not be opened; elevated geometry is disabled.",
        "Warning")
if !LoadConfiguration() {
    LogLine("Settings could not be loaded: " SettingsPath, "Error")
    ExitApp()
}
LogLine("Elevated window helper " HelperVersion " started for parent PID " ParentPid ".")
OnExit(HelperExitCleanup)
SetTimer(PollController, PollIntervalMs)
SetTimer(ElevatedWindowGeometryTick, 500)
