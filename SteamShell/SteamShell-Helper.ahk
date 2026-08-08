; ==============================================================================
; SteamShell Elevated Window Helper
; Handles controller mouse/mapped input and coordinated window geometry while
; a High/System-integrity application is involved. SteamShell.exe remains the
; normal-integrity shell and owns every visible SteamShell UI.
;
; ONE PAYLOAD, TWO PRODUCTS. --product selects how much of this file is live:
;
;   standalone (default)  everything: controller input, window geometry, and the
;                         RTSS frame cap.
;   xfe                   the RTSS frame cap and nothing else.
;
; The XFE helper is deliberately not the same helper with a different parent.
; Elevated input was left out of it because the remedy here is XInput, and XFE
; exists precisely because XInput is not enough for its users -- a controller in
; DirectInput mode is not an XInput device at all, so elevated input would have
; worked only for the people who did not need XFE. Elevated window geometry was
; left out because XFE never manages presentation; Xbox FSE does.
;
; What is left is the one thing that cannot work any other way: RTSSHooks64.dll
; loads into the calling process, so a per-game or global frame cap on a stock
; Program Files RTSS install needs a token XFE does not have.
; ==============================================================================
#Requires AutoHotkey v2.0.19 64-bit
#SingleInstance Force
#NoTrayIcon
;@Ahk2Exe-SetName SteamShell Elevated Window Helper
;@Ahk2Exe-SetDescription Elevated-window controller input and geometry for SteamShell
;@Ahk2Exe-SetVersion 1.9.9.4

Persistent
SendMode "Input"
CoordMode "Mouse", "Screen"

; The self-contained half of what the three programs share. Nothing in it
; declares a global or reaches outside itself, which is what makes it safe to
; compile into a High-integrity binary -- and what let this file drop its own
; second copy of the token, SID and session parsing. SteamShell-Shared.ahk is
; deliberately NOT included: it orchestrates RTSS and the Quick Menu and reaches
; into eight tree functions, so including it here would not compile.
#Include SteamShell-Common.ahk

global HelperVersion := "1.9.9"
; "standalone" or "xfe". Set once from --product and never re-read from the
; settings file: which product started this process is not a preference.
global HelperProduct := "standalone"
global MainImageName := "steamshell.exe"
global HelperInputEnabled := true
global HelperGeometryEnabled := true
global ParentPid := 0
global MainPath := ""
global SettingsPath := ""
global LogPath := ""
global LogMaxBytes := 256 * 1024
global LogBackups := 2
global ControllerIndex := 0
global PollIntervalMs := 15
global Deadzone := 3000
global MouseSpeed := 3200 ; Cursor pixels per SECOND at full deflection
global FastMultiplier := 2.5
global ScrollIntervalMs := 80
global ScrollStep := 1
global ChordHoldMs := 500
global EnableControllerMouse := true
global EnableQuickMenu := true
; Automatic mouse mode is DECIDED BY MAIN and published on a named event.
;
; This process deliberately keeps no copy of the settings behind it. It used to,
; and a second copy is exactly what let the two disagree: the real answer
; depends on DesktopMode, which is shell state this process cannot observe, so
; what stood in for it here was a hardcoded list of four executable names. For
; every elevated window outside those four, main ran automatic mouse mode and
; this process did not -- the user got main's five normal-integrity builtins and
; no cursor, no scrolling and no click to use them with.
global AutoMouseEventHandle := 0
global EnableWindowManagement := true
global MinWidthPercent := 0.30
global WmExcludeExeSet := Map()
global WmExcludeClassSet := Map()
global ElevatedGeometryState := Map()
global GeometryEventHandle := 0
global RtssApplyEventHandle := 0
global RtssDoneEventHandle := 0
global RtssRequestPath := ""
global RtssLastRequestSeq := -1
global EnableElevatedRtssFrameCap := true
global RtssHooksModule := 0
global RtssHooksProcs := 0
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


FindMainProcess() {
    global MainPath, MainImageName
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
            if (processName = StrLower(MainImageName)) {
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

OpenParentAutoMouseEvent() {
    global ParentPid, AutoMouseEventHandle
    if AutoMouseEventHandle
        return true
    if !ParentPid
        return false
    AutoMouseEventHandle := DllCall(
        "Kernel32\OpenEventW",
        "UInt", 0x00100000, ; SYNCHRONIZE
        "Int", false,
        "WStr", "Local\SteamShellAutoMouse-" ParentPid,
        "Ptr")
    return AutoMouseEventHandle != 0
}

; Whether MAIN currently has automatic mouse mode on, which is the only answer
; either process acts on. Carries no payload, exactly like the geometry event:
; it says "the controller is a mouse right now" and nothing about why.
;
; False when the event cannot be opened, which is the conservative direction --
; the physical View/Back button is read separately and still works, so the
; failure mode is "no automatic mouse mode", not "no input".
ParentAutoMouseModeActive() {
    global AutoMouseEventHandle
    if !AutoMouseEventHandle && !OpenParentAutoMouseEvent()
        return false
    return DllCall(
        "Kernel32\WaitForSingleObject",
        "Ptr", AutoMouseEventHandle,
        "UInt", 0,
        "UInt") = 0 ; WAIT_OBJECT_0
}

; ------------------------------------------------------------------------------
; Elevated RTSS frame cap
; ------------------------------------------------------------------------------
; RTSSHooks64.dll is loaded into the CALLING process, so main's SaveProfile runs
; with main's token. RTSS installs under Program Files, so an unelevated main
; writes nothing and is not told: SetProfileProperty succeeds against the
; in-memory copy, SaveProfile fails silently, and UpdateProfiles reloads the old
; value over the top. This is the one RTSS operation that genuinely needs a
; token main does not have.
;
; The helper therefore runs the WHOLE sequence -- LoadProfile,
; SetProfileProperty, SaveProfile, UpdateProfiles -- exactly as an elevated
; SteamShell used to. An earlier design had the helper write the profile FILE
; and left every API call in main. That persisted the global cap correctly and
; reproduced neither of the other two behaviours the elevated path had: RTSS's
; own window never updated, and per-game profile saves still silently did
; nothing. RTSS's window watches the profile state SetProfileProperty writes,
; not the file. Reproducing a sequence known to work beat continuing to reason
; about a third-party program's internals.
;
; WHAT THE REQUEST MAY CARRY, and nothing else:
;   Fps      a bounded integer, 0-1000
;   Profile  empty for the global profile, or a plain executable name
;
; The profile name is the only string that crosses, and it is not trusted. It
; cannot be derived here -- by the time a request arrives the Quick Menu is the
; foreground window, not the game -- so main sends it and this process
; corroborates it: it must look like a bare executable name
; (ProfileNameIsAcceptable, which no path separator or drive colon can satisfy)
; AND name a process that is running right now (HelperProcessImageIsRunning).
; A tampered settings file can therefore reach a profile named after a process
; the user is actually running, inside RTSS's own profile directory, and no
; further. That is the same principle as the Send: refusal: the channel selects
; among real things, it does not compose new ones.

; Auto-reset, created by the Medium-integrity parent. It carries no payload: it
; says only "there is a request to read", exactly as the geometry event says
; only "elevated geometry is allowed".
OpenParentRtssApplyEvent() {
    global ParentPid, RtssApplyEventHandle
    if RtssApplyEventHandle
        return true
    if !ParentPid
        return false
    RtssApplyEventHandle := DllCall(
        "Kernel32\OpenEventW",
        "UInt", 0x00100000, ; SYNCHRONIZE
        "Int", false,
        "WStr", "Local\SteamShellRtssApply-" ParentPid,
        "Ptr")
    return RtssApplyEventHandle != 0
}

; Opened for signalling only. Main waits on this instead of polling RTSS, so
; every exit path in ServiceElevatedRtssRequest has to reach it -- including the
; refusals, or main sits out its whole timeout for a request that was rejected
; in a microsecond.
SignalParentRtssRequestDone() {
    global ParentPid, RtssDoneEventHandle
    if (!RtssDoneEventHandle && ParentPid)
        RtssDoneEventHandle := DllCall(
            "Kernel32\OpenEventW",
            "UInt", 0x0002, ; EVENT_MODIFY_STATE
            "Int", false,
            "WStr", "Local\SteamShellRtssDone-" ParentPid,
            "Ptr")
    if RtssDoneEventHandle
        DllCall("Kernel32\SetEvent", "Ptr", RtssDoneEventHandle, "Int")
}

ParentRequestedRtssFrameCap() {
    global RtssApplyEventHandle
    if !RtssApplyEventHandle && !OpenParentRtssApplyEvent()
        return false
    ; WAIT_OBJECT_0, and the auto-reset consumes the signal here.
    return DllCall(
        "Kernel32\WaitForSingleObject",
        "Ptr", RtssApplyEventHandle,
        "UInt", 0,
        "UInt") = 0
}

; Read from HKLM rather than from the environment. This process inherits its
; environment from whoever started it, so %ProgramFiles% is not evidence of
; anything; the registry value is administrator-writable only.
ElevatedRtssProgramFilesRoots() {
    roots := []
    for _, valueName in ["ProgramFilesDir", "ProgramFilesDir (x86)"] {
        value := ""
        try value := RegRead(
            "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion",
            valueName)
        value := RTrim(Trim(value), "\")
        if (value != "")
            roots.Push(value)
    }
    return roots
}

; Resolves junctions, symbolic links and 8.3 names to the real path. Without
; this, a user-writable directory containing a junction named Profiles would
; redirect an elevated write to anywhere on the volume, and every check below it
; would still pass.
ElevatedRtssFinalPath(path) {
    static OPEN_EXISTING := 3
    static FILE_SHARE_ALL := 0x00000007
    static FILE_FLAG_BACKUP_SEMANTICS := 0x02000000 ; required to open a directory
    ; FILE_READ_ATTRIBUTES is the documented minimum for
    ; GetFinalPathNameByHandle. Asking for no access at all happens to work in
    ; some cases and is not what the API guarantees, and this is not a place to
    ; rely on that.
    static FILE_READ_ATTRIBUTES := 0x0080
    handle := DllCall("Kernel32\CreateFileW",
        "WStr", path,
        "UInt", FILE_READ_ATTRIBUTES,
        "UInt", FILE_SHARE_ALL,
        "Ptr", 0,
        "UInt", OPEN_EXISTING,
        "UInt", FILE_FLAG_BACKUP_SEMANTICS,
        "Ptr", 0,
        "Ptr")
    if (!handle || handle = -1)
        return ""
    try {
        length := DllCall("Kernel32\GetFinalPathNameByHandleW",
            "Ptr", handle, "Ptr", 0, "UInt", 0, "UInt", 0, "UInt")
        if !length
            return ""
        ; NOT named "buffer". AutoHotkey identifiers are case-insensitive, so a
        ; local called buffer IS the Buffer class: the right-hand side below
        ; would resolve to the unassigned local instead of the constructor and
        ; throw before it ever ran.
        pathBuffer := Buffer((length + 1) * 2, 0)
        if !DllCall("Kernel32\GetFinalPathNameByHandleW",
            "Ptr", handle, "Ptr", pathBuffer, "UInt", length + 1, "UInt", 0, "UInt")
            return ""
        resolved := RTrim(StrGet(pathBuffer, "UTF-16"), "\")
        ; \\?\C:\... becomes C:\... so it can be compared with the registry
        ; roots. A UNC result keeps its prefix and fails the Program Files test
        ; below, which is the correct answer for a network path.
        if (SubStr(resolved, 1, 4) = "\\?\" && SubStr(resolved, 6, 2) = ":\")
            resolved := SubStr(resolved, 5)
        return resolved
    } finally {
        DllCall("Kernel32\CloseHandle", "Ptr", handle)
    }
}

ElevatedRtssPathIsWithin(candidate, root) {
    if (candidate = "" || root = "")
        return false
    candidate := RTrim(candidate, "\")
    root := RTrim(root, "\")
    if (StrLower(candidate) = StrLower(root))
        return true
    return InStr(StrLower(candidate), StrLower(root) "\") = 1
}

; RTSS's install directory, or "" with a reason. Both the profiles and
; RTSSHooks64.dll are taken from it, so this one gate covers both.
;
; The configured [RTSS] Path IS honoured -- Setup Assistant establishes it, and a
; user who installed RTSS somewhere non-default should not silently lose the
; feature. But it is a hint, not an instruction: the settings file is
; user-writable in every installation mode, so the value is corroborated rather
; than trusted, the same way Setup corroborates a directory before removing it.
;
;   1. it has to name RTSS.exe
;   2. RTSS.exe has to actually be there
;   3. the real directory, junctions resolved, has to sit under a Program Files
;      root read from HKLM
;
; Rule 3 is the one carrying the weight, and it is what makes loading a DLL out
; of this directory acceptable. A directory under Program Files cannot be
; created or populated without administrator rights, so a redirected hint can
; only ever point somewhere the user already could not write -- it cannot name a
; directory of their own with a planted RTSS.exe beside a planted RTSSHooks64.
;
; The cost is that an RTSS installed outside Program Files is refused here. That
; costs nothing real: those installs are writable by the account main runs as,
; so main's own in-process write already works there; the helper exists only for
; the case main cannot do. Refusing is also the safer direction, since it fails
; towards "main reports the cap read-only" rather than towards an elevated write.
ResolveElevatedRtssInstallDirectory(&failureReason) {
    global SettingsPath
    failureReason := ""
    roots := ElevatedRtssProgramFilesRoots()
    if !roots.Length {
        failureReason := "The Program Files locations could not be read from HKLM."
        return ""
    }
    candidates := []
    hint := ""
    try hint := CleanIniValue(IniRead(SettingsPath, "RTSS", "Path", ""), "")
    if (hint != "") {
        hintName := ""
        hintDirectory := ""
        SplitPath(hint, &hintName, &hintDirectory)
        if (StrLower(hintName) = "rtss.exe" && hintDirectory != "")
            candidates.Push(hintDirectory)
    }
    for _, root in roots
        candidates.Push(root "\RivaTuner Statistics Server")
    lastReason := "No RTSS installation was found under Program Files."
    for _, directory in candidates {
        if !FileExist(directory "\RTSS.exe") {
            lastReason := "RTSS.exe was not found in " directory "."
            continue
        }
        installDirectory := ElevatedRtssFinalPath(directory)
        if (installDirectory = "") {
            lastReason := "The real path of " directory " could not be resolved."
            continue
        }
        underProgramFiles := false
        for _, root in roots {
            if ElevatedRtssPathIsWithin(installDirectory, root) {
                underProgramFiles := true
                break
            }
        }
        if !underProgramFiles {
            lastReason := installDirectory " is not under Program Files, so its"
                . " frame cap does not need an elevated write."
            continue
        }
        return installDirectory
    }
    failureReason := lastReason
    return ""
}

; RTSSHooks64.dll, loaded from the gated install directory above.
;
; This is the whole reason the helper exists in its current shape. RTSSHooks is
; loaded into the CALLING process, so every profile write runs with that
; process's token -- which is why an unelevated main could set a value in memory
; and never persist it. Running the identical sequence here, in the process that
; HAS the token, is what an elevated SteamShell used to do, and it is the only
; arrangement observed to update RTSS's own window and write per-game profiles.
;
; An earlier design had the helper write the profile FILE and left every API
; call in main. It persisted the global cap correctly and did not reproduce
; either of those two behaviours, because RTSS's window watches the profile
; state SetProfileProperty writes and not the file. Reproducing a sequence known
; to work beats reasoning about a third-party program's internals.
HelperRtssApi() {
    global RtssHooksModule, RtssHooksProcs
    if RtssHooksModule
        return RtssHooksProcs
    installDirectory := ResolveElevatedRtssInstallDirectory(&resolveFailure)
    if (installDirectory = "") {
        LogLine("RTSS integration is unavailable to the helper: " resolveFailure,
            "Warning")
        return 0
    }
    dllPath := installDirectory "\RTSSHooks64.dll"
    if !FileExist(dllPath) {
        LogLine("RTSSHooks64.dll was not found in " installDirectory ".",
            "Warning")
        return 0
    }
    ; Loaded by full path from the gated directory. Never by name: a bare
    ; LoadLibrary would consult the search path, which is not something this
    ; process should be resolving anything from.
    module := DllCall("Kernel32\LoadLibraryW", "WStr", dllPath, "Ptr")
    if !module {
        LogLine("RTSSHooks64.dll could not be loaded (" A_LastError ").",
            "Warning")
        return 0
    }
    procs := Map()
    for _, name in ["LoadProfile", "SetProfileProperty", "GetProfileProperty",
        "SaveProfile", "UpdateProfiles"] {
        procs[name] := DllCall("Kernel32\GetProcAddress",
            "Ptr", module, "AStr", name, "Ptr")
    }
    ; The first four are the write path. UpdateProfiles is optional in older
    ; builds, exactly as main treats it.
    if !(procs["LoadProfile"] && procs["SetProfileProperty"]
        && procs["SaveProfile"]) {
        LogLine("This RTSS build does not export the profile write functions.",
            "Warning")
        DllCall("Kernel32\FreeLibrary", "Ptr", module)
        return 0
    }
    RtssHooksModule := module
    RtssHooksProcs := procs
    LogLine("RTSS integration ready in the helper from " dllPath ".")
    return RtssHooksProcs
}

; True when a process with this image name is running right now.
;
; This is the corroboration that makes a per-game profile name safe to accept.
; The name cannot be derived here -- by the time the request arrives the Quick
; Menu is the foreground window, not the game -- so main sends it and this
; process checks it against reality instead of trusting it. Combined with the
; pattern check in ProfileNameIsAcceptable, the worst a tampered settings file
; can achieve is a profile named after a process the user is actually running,
; in RTSS's own profile directory.
HelperProcessImageIsRunning(exeName) {
    snapshot := DllCall(
        "CreateToolhelp32Snapshot", "UInt", 0x00000002, "UInt", 0, "Ptr")
    if (snapshot = -1 || snapshot = 0)
        return false
    entrySize := A_PtrSize = 8 ? 568 : 556
    entry := Buffer(entrySize, 0)
    NumPut("UInt", entrySize, entry, 0)
    try {
        if !DllCall("Process32FirstW", "Ptr", snapshot, "Ptr", entry)
            return false
        Loop {
            processName := StrGet(
                entry.Ptr + (A_PtrSize = 8 ? 44 : 36), "UTF-16")
            if (StrLower(processName) = StrLower(exeName))
                return true
            if !DllCall("Process32NextW", "Ptr", snapshot, "Ptr", entry)
                break
        }
    } finally {
        DllCall("CloseHandle", "Ptr", snapshot)
    }
    return false
}

; What a per-game profile name is allowed to look like.
;
; Stated as the characters that are REFUSED rather than the ones allowed. An
; allowlist of [A-Za-z0-9 ._-] was tried first and is wrong for this job: real
; game executables carry apostrophes, ampersands, brackets and non-ASCII
; letters, so an allowlist quietly refuses to save profiles for exactly the
; games most likely to need one -- and the refusal looks like the feature being
; broken rather than like a rule.
;
; What actually matters is that the name cannot leave RTSS's Profiles
; directory. These are the characters Windows forbids in a file name, so
; refusing them plus any control character, any form of relative path, and any
; trailing dot or space leaves a name that can only ever be a leaf inside that
; one directory. The running-process check in ServiceElevatedRtssRequest is the
; other half; neither stands alone.
ProfileNameIsAcceptable(name) {
    if (StrLen(name) < 5 || StrLen(name) > 64)
        return false
    if (StrLower(SubStr(name, -4)) != ".exe")
        return false
    ; Path separators, drive colon, wildcards, quoting and redirection.
    if RegExMatch(name, "[\\\\/:*?`"<>|]")
        return false
    ; Control characters, including anything that could truncate the name.
    if RegExMatch(name, "[\x00-\x1F\x7F]")
        return false
    ; Relative paths in any form, and names Windows normalises away.
    if (InStr(name, "..") || SubStr(name, 1, 1) = ".")
        return false
    trailing := SubStr(name, -1)
    if (trailing = " " || trailing = ".")
        return false
    return true
}

; The sequence an elevated SteamShell used to run, in the process that has the
; token: load the profile, set the property, save it, then apply.
;
; profileName is "" for the global profile. SaveProfile is the call that needs
; elevation and the one that silently did nothing in main; everything else is
; here because splitting the sequence across two processes is what stopped
; RTSS's window and the per-game profiles from working.
ApplyHelperRtssFrameLimit(profileName, fps, &failureReason) {
    failureReason := ""
    api := HelperRtssApi()
    if !IsObject(api) {
        failureReason := "RTSS integration is unavailable to the helper."
        return false
    }
    value := Buffer(4, 0)
    NumPut("UInt", fps, value, 0)
    try {
        ; Load the existing profile first so unrelated properties survive.
        DllCall(api["LoadProfile"], "AStr", profileName)
        if !DllCall(api["SetProfileProperty"],
            "AStr", "FramerateLimit", "Ptr", value, "UInt", value.Size, "Int") {
            failureReason := "RTSS rejected the FramerateLimit write."
            return false
        }
        DllCall(api["SaveProfile"], "AStr", profileName)
        if api["UpdateProfiles"]
            DllCall(api["UpdateProfiles"])
        ; Read it straight back. This is the same check main used to make and
        ; could no longer trust once the write moved out of process: a write
        ; RTSS accepts but does not persist is otherwise indistinguishable from
        ; a working one.
        readBack := Buffer(4, 0)
        DllCall(api["LoadProfile"], "AStr", profileName)
        if (api["GetProfileProperty"]
            && DllCall(api["GetProfileProperty"], "AStr", "FramerateLimit",
                "Ptr", readBack, "UInt", readBack.Size, "Int")) {
            actual := NumGet(readBack, 0, "UInt")
            if (actual != fps) {
                failureReason := "RTSS accepted FramerateLimit " fps
                    . " but reports " actual " immediately afterwards."
                return false
            }
        }
        ; A per-game save displaces the global profile as the loaded one, and
        ; main's Frame Limit row reads the global. Put it back.
        if (profileName != "")
            try DllCall(api["LoadProfile"], "AStr", "")
        return true
    } catch as err {
        failureReason := "The RTSS profile write failed: " err.Message
        if (profileName != "")
            try DllCall(api["LoadProfile"], "AStr", "")
        return false
    }
}

; Serviced when main signals. Nothing is reported back: the result is observable
; in RTSS's own configuration, and main confirming it there is a stronger
; statement than this process reporting its own success.
; Records WHICH request finished, then signals that it did.
;
; Main resets the completion event before issuing each request, and a reset
; cannot undo a completion that arrives after it. A request that timed out in
; main at three seconds and finished here at three-and-a-bit therefore satisfied
; the NEXT request's wait instantly: main resumed reading RTSS while this
; process was still mid-sequence on the new request -- the exact interleaving
; the completion event exists to prevent -- and reported the write it was about
; to make as a failure. The sequence number is what tells the two apart, so it
; is written BEFORE the event is set and never after.
CompleteElevatedRtssRequest(sequence) {
    global RtssRequestPath
    if (sequence >= 0 && RtssRequestPath != "") {
        try IniWrite(sequence, RtssRequestPath, "Result", "Seq")
        catch as err
            LogLine("The RTSS completion sequence " sequence
                . " could not be recorded: " err.Message, "Warning")
    }
    SignalParentRtssRequestDone()
}

ServiceElevatedRtssRequest() {
    global RtssRequestPath, RtssLastRequestSeq, EnableElevatedRtssFrameCap
    ; Read before any refusal, so that a refusal can still name the request it
    ; is refusing. Main is already blocked on the completion event by now.
    sequence := -1
    if (RtssRequestPath != "" && FileExist(RtssRequestPath)) {
        try sequence := Integer(CleanIniValue(
            IniRead(RtssRequestPath, "Request", "Seq", "-1"), "-1"))
    }
    ; Main signals the request event and then blocks on the completion event, so
    ; EVERY exit from here has to reach CompleteElevatedRtssRequest -- including
    ; the refusals, which return in a microsecond.
    ;
    ; Four of the five refusals used to return without signalling anything. The
    ; comment here claimed otherwise, and the cost was not theoretical: main
    ; waits 3000 ms with Critical on, so a helper that declined instantly froze
    ; the Windows shell for three seconds per button press. The most reachable
    ; case was the settings disagreeing for the up-to-one-second window between
    ; main reloading EnableElevatedFrameCapWrites and this process reloading it.
    ;
    ; Do not turn this back into a single signal at the end of the body.
    try {
        if !EnableElevatedRtssFrameCap {
            LogLine("An RTSS frame cap request arrived while elevated frame cap"
                . " writes are disabled; it was ignored.")
            return
        }
        if (RtssRequestPath = "" || !FileExist(RtssRequestPath)) {
            LogLine("An RTSS frame cap request arrived with no request file at '"
                . (RtssRequestPath != "" ? RtssRequestPath : "(no path)")
                . "'; it was ignored.", "Warning")
            return
        }
        if (sequence < 0) {
            LogLine("An RTSS frame cap request carried no readable sequence"
                . " number; it was ignored.", "Warning")
            return
        }
        ; Main writes every other field before Seq, so a sequence number that has
        ; moved is proof the values beside it belong to it.
        if (sequence = RtssLastRequestSeq) {
            LogLine("RTSS request " sequence " has already been serviced; it was"
                . " acknowledged again rather than repeated.")
            return
        }
        RtssLastRequestSeq := sequence
        HandleElevatedRtssRequest(sequence)
    } finally {
        CompleteElevatedRtssRequest(sequence)
    }
}

HandleElevatedRtssRequest(sequence) {
    global RtssRequestPath
    fps := -1
    try fps := Integer(CleanIniValue(
        IniRead(RtssRequestPath, "Request", "Fps", "-1"), "-1"))
    catch
        return
    ; A value outside the range RTSS accepts is discarded rather than clamped:
    ; out here it is a malformed request, not a user choosing something that
    ; needs rounding off.
    if (fps < 0 || fps > 1000) {
        LogLine("An out-of-range RTSS frame cap request (" fps
            . ") was discarded.", "Warning")
        return
    }
    profileName := ""
    try profileName := CleanIniValue(
        IniRead(RtssRequestPath, "Request", "Profile", ""), "")
    ; Empty means the global profile, which is the common case and needs no
    ; corroboration -- there is only one of it and its name is not a name.
    if (profileName != "") {
        if !ProfileNameIsAcceptable(profileName) {
            LogLine("An RTSS profile name that is not a plain executable name ("
                . profileName ") was refused.", "Warning")
            return
        }
        ; Sent by main because only main knows which game the Quick Menu was
        ; opened over; checked here because main's settings file is writable.
        if !HelperProcessImageIsRunning(profileName) {
            LogLine("The RTSS profile name " profileName
                . " does not match any running process and was refused.",
                "Warning")
            return
        }
    }
    target := profileName != "" ? profileName : "Global"
    writeFailure := ""
    if ApplyHelperRtssFrameLimit(profileName, fps, &writeFailure)
        LogLine("RTSS profile " target " written with FramerateLimit " fps
            . " for request " sequence ".")
    else
        LogLine("RTSS request " sequence " (" target ") was not applied: "
            . writeFailure, "Warning")
}

; CleanIni was this file's own copy of CleanIniValue, which now lives in
; SteamShell-Common.ahk. Identical behaviour at every call site here, because
; every one of them passed a fallback and therefore used blankUsesDefault.

ReadFloat(section, key, fallback, minimum, maximum) {
    value := fallback
    try value := Number(CleanIniValue(IniRead(SettingsPath, section, key, fallback), fallback))
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

; The main tree rotates its own log and this one used to grow without bound.
; Geometry actions append a line every time an administrator window is centered,
; so an ordinary install accumulates indefinitely without this.
RotateHelperLogIfNeeded(pendingBytes) {
    global LogPath, LogMaxBytes, LogBackups
    if (LogBackups <= 0 || LogMaxBytes <= 0)
        return
    currentSize := 0
    try currentSize := FileGetSize(LogPath)
    catch
        return
    if (currentSize + pendingBytes <= LogMaxBytes)
        return
    try {
        Loop LogBackups {
            index := LogBackups - A_Index + 1
            source := index = 1 ? LogPath : LogPath "." (index - 1)
            target := LogPath "." index
            if !FileExist(source)
                continue
            if FileExist(target)
                FileDelete(target)
            FileMove(source, target, true)
        }
    }
}

LogLine(message, level := "Info") {
    global LogPath
    if (LogPath = "")
        return
    try {
        SplitPath(LogPath, , &directory)
        if (directory != "")
            DirCreate(directory)
        line := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
            . " [" level "] " message "`r`n"
        RotateHelperLogIfNeeded(StrLen(line) + 2)
        FileAppend(line, LogPath, "UTF-8")
    }
}

LoadConfiguration() {
    global ControllerIndex, PollIntervalMs, Deadzone, MouseSpeed
    global FastMultiplier, ScrollIntervalMs, ScrollStep, ChordHoldMs
    global EnableControllerMouse, EnableQuickMenu, ControllerMap
    global EnableWindowManagement, MinWidthPercent
    global WmExcludeExeSet, WmExcludeClassSet, ElevatedGeometryState
    global LogMaxBytes, LogBackups, EnableElevatedRtssFrameCap
    global HelperProduct

    if !FileExist(SettingsPath)
        return false
    ; Same keys and bounds the main tree uses, so both logs rotate together.
    ; One read rather than a branch on --product=: the two trees used to keep
    ; these in different sections under differently-prefixed names, and reading
    ; one product's keys out of the other's INI would have fallen back to the
    ; defaults rather than honouring what the user configured. Both name them
    ; this way now, so there is nothing left to branch on. The old spellings are
    ; deliberately not written out here -- a retired name in a comment is still a
    ; match for a rule looking for it in code.
    LogMaxBytes := ReadInt("Logging", "LogRotateMaxKB", 256, 32, 8192) * 1024
    LogBackups := ReadInt("Logging", "LogRotateBackups", 2, 0, 10)
    ; Main owns the Quick Menu chord. When the user disables the menu those
    ; buttons stop being reserved there, so they must stop being reserved here.
    EnableQuickMenu := ReadBool("QuickMenu", "Enable", true)
    ; Read here rather than checked once at startup, so clearing the setting
    ; stops the writes without a restart -- the same reason the helper reloads
    ; everything else in this function.
    ;
    ; The FALLBACK differs by product, matching each tree's own default: on for
    ; standalone, off for XFE, where the whole helper is opt-in. Main stops this
    ; process when the XFE setting is cleared, so this fallback only decides what
    ; happens if the key is missing entirely -- and for XFE the safe answer to
    ; "the opt-in cannot be read" is that it was not opted in to.
    EnableElevatedRtssFrameCap := ReadBool(
        "RTSS", "EnableElevatedFrameCapWrites", HelperProduct != "xfe")
    EnableControllerMouse := ReadBool(
        "Controller", "EnableControllerMouseMode", true)
    ; EnablePersistentMouseMode, EnableAutoMouseMode, EnableDesktopAutoMouseMode,
    ; AutoMouseExeList and DesktopAutoMouseExcludeExeList are deliberately NOT
    ; read here any more. They are all inputs to one question -- is automatic
    ; mouse mode on? -- that main already answers and publishes; re-deriving it
    ; from the same settings gave two answers that could not agree, because the
    ; real one also depends on DesktopMode and this process cannot see that.
    ControllerIndex := ReadInt("Controller", "ControllerIndex", 0, 0, 3)
    PollIntervalMs := ReadInt(
        "Controller", "ControllerPollIntervalMs", 15, 8, 100)
    Deadzone := ReadInt("Controller", "ControllerDeadzone", 3000, 0, 20000)
    MouseSpeed := ReadInt("Controller", "ControllerMouseSpeed", 3200, 200, 12000)
    FastMultiplier := ReadFloat(
        "Controller", "ControllerMouseFastMultiplier", 2.5, 1.0, 10.0)
    ScrollIntervalMs := ReadInt(
        "Controller", "ControllerScrollIntervalMs", 80, 10, 1000)
    ScrollStep := ReadInt("Controller", "ControllerScrollStep", 1, 1, 10)
    ChordHoldMs := ReadInt(
        "Controller", "ControllerChordHoldMs", 500, 100, 2000)
    EnableWindowManagement := ReadBool(
        "Features", "EnableWindowManagement", true)
    MinWidthPercent := ReadFloat(
        "WindowManagement", "MinWidthPercent", 0.30, 0.05, 1.00)
    try WmExcludeExeSet := ParseExeSet(CleanIniValue(
        IniRead(SettingsPath, "WindowManagement", "ExcludeExeList", ""), ""))
    try WmExcludeClassSet := ParseClassSet(CleanIniValue(
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
        try value := CleanIniValue(IniRead(SettingsPath, "ControllerMap", key, fallback), fallback)
        if (SubStr(value, 1, 5) != "Send:" && SubStr(value, 1, 8) != "Builtin:")
            value := "Send:" value
        ControllerMap[key] := value
    }
    return true
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
        if !ProcessIsElevatedIntegrity(pid)
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
    ReleaseControllerMouseButtons()
    global GeometryEventHandle, RtssApplyEventHandle, RtssDoneEventHandle
    global AutoMouseEventHandle
    global RtssHooksModule, RtssHooksProcs
    if GeometryEventHandle {
        try DllCall("Kernel32\CloseHandle", "Ptr", GeometryEventHandle, "Int")
        GeometryEventHandle := 0
    }
    if AutoMouseEventHandle {
        try DllCall("Kernel32\CloseHandle", "Ptr", AutoMouseEventHandle, "Int")
        AutoMouseEventHandle := 0
    }
    if RtssApplyEventHandle {
        try DllCall("Kernel32\CloseHandle", "Ptr", RtssApplyEventHandle, "Int")
        RtssApplyEventHandle := 0
    }
    if RtssDoneEventHandle {
        try DllCall("Kernel32\CloseHandle", "Ptr", RtssDoneEventHandle, "Int")
        RtssDoneEventHandle := 0
    }
    ; RTSSHooks is third-party code mapped into a High-integrity process. It
    ; stays loaded for the session because resolving and loading it per request
    ; would mean repeating the Program Files gate on every button press, but it
    ; does not outlive the process.
    if RtssHooksModule {
        try DllCall("Kernel32\FreeLibrary", "Ptr", RtssHooksModule, "Int")
        RtssHooksModule := 0
        RtssHooksProcs := 0
    }
    LogLine("Elevated window helper stopped: " reason ".")
}

; "Elevated" is High or System integrity, which is the same question main asks
; in ElevatedHelperOwnsForeground -- and it has to be the SAME answer, because
; the two processes use it to decide which of them owns the controller. If they
; disagreed, a window would be handled twice or not at all.
;
; This used to be a second 38-line copy of the token walk, testing the raw RID
; against 0x3000 while main compared integrity NAMES. The two happened to agree,
; because GetProcessTokenSecurity maps >= 0x4000 to System and 0x3000..0x3FFF to
; High -- but "happened to agree" is not a property anyone was maintaining. One
; definition now, from SteamShell-Common.ahk.
ProcessIsElevatedIntegrity(pid) {
    if !GetProcessTokenSecurity(
        pid, &processSid, &processSession, &integrityName, &tokenError)
        return false
    return integrityName = "High" || integrityName = "System"
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
    return ProcessIsElevatedIntegrity(pid)
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
    ; Every case below is a fixed keystroke chosen from a closed set, so a
    ; writable INI can only select among them -- it cannot compose one. That is
    ; the distinction from Send: above, which is arbitrary text.
    ;
    ; TabTip, OSK, Explorer, QuickMenu, and ControlPanel are deliberately absent:
    ; they start processes or raise SteamShell's own windows and must stay at the
    ; main process's normal integrity. Main keeps handling exactly those while an
    ; elevated window is foreground, so the two sets do not overlap and no
    ; binding is dropped by both.
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
            SendChordSafe("!{F4}")
        case "taskmanager":
            SendChordSafe("^+{Esc}")
        case "startmenu":
            SendChordSafe("{LWin}")
        case "wing":
            SendChordSafe("#g")
        case "ctrlalttab":
            SendChordSafe("^!{Tab}")
    }
}

PollController() {
    global ParentPid, MainPath, EnableControllerMouse, EnableQuickMenu
    global Deadzone, MouseSpeed, FastMultiplier, ScrollIntervalMs, ScrollStep
    global ChordHoldMs, PollIntervalMs, HelperInputEnabled
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
            previousInterval := PollIntervalMs
            if LoadConfiguration() {
                LogLine("Controller configuration reloaded after settings changed.")
                ; The timer keeps its original period unless it is re-armed, so
                ; a changed poll rate would otherwise not reach this process.
                if (PollIntervalMs != previousInterval)
                    SetTimer(PollController, PollIntervalMs)
            }
        }
        lastSettingsStamp := settingsStamp
    }
    ; Checked on every tick and before the controller guards below, because a
    ; frame cap request has nothing to do with a controller being present or an
    ; elevated window being foreground. Costs one non-blocking wait when idle.
    if ParentRequestedRtssFrameCap()
        ServiceElevatedRtssRequest()
    ; Everything past this point is elevated INPUT, and an XFE helper does not
    ; have that job. Placed after the request service rather than around the
    ; timer, so the RTSS channel keeps its existing cadence and the standalone
    ; path is byte-for-byte the one confirmed working on hardware.
    if !HelperInputEnabled {
        previousButtons := 0
        ResetControllerEdgeState(
            downTick, longFired, previousTriggers, buttonDefinitions)
        return
    }
    if !EnableControllerMouse || !ElevatedForeground(&foregroundExe) {
        previousButtons := 0
        ResetControllerEdgeState(
            downTick, longFired, previousTriggers, buttonDefinitions)
        return
    }
    if !GetXInputState(&state) {
        previousButtons := 0
        ResetControllerEdgeState(
            downTick, longFired, previousTriggers, buttonDefinitions)
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

    ; Main's answer, not a second one derived here. See the note beside
    ; AutoMouseEventHandle for what the second one cost.
    autoMouse := ParentAutoMouseModeActive()
    viewDown := (buttons & 0x0020) || autoMouse
    pressed := buttons & ~previousButtons
    released := (~buttons) & previousButtons
    previousButtons := buttons
    ; Main SteamShell exclusively owns its Quick Menu and emergency Settings
    ; chords, even over an elevated foreground. Never let their constituent
    ; buttons become helper mappings while the main process is timing the hold.
    quickMenuChord := EnableQuickMenu
        && (buttons & 0x0040) && (buttons & 0x0080)
        && !(buttons & 0x0020) && !(buttons & 0x0010)
        && !(buttons & 0x0100) && !(buttons & 0x0200)
        && leftTrigger <= 30 && rightTrigger <= 30
    settingsChord := leftTrigger > 30 && rightTrigger > 30
        && (buttons & 0x0100) && (buttons & 0x0200)
        && (buttons & 0x0040) && (buttons & 0x0080)
    if quickMenuChord || settingsChord {
        ResetControllerEdgeState(
            downTick, longFired, previousTriggers, buttonDefinitions)
        return
    }
    if !viewDown {
        ResetControllerEdgeState(
            downTick, longFired, previousTriggers, buttonDefinitions)
        return
    }

    now := A_TickCount
    ApplyControllerMouseMove(rightX, rightY,
        rightTrigger > 30 ? Round(MouseSpeed * FastMultiplier) : MouseSpeed)
    if leftY != 0 && now - lastScrollTick >= ScrollIntervalMs {
        lastScrollTick := now
        ApplyControllerMouseScroll(leftY, ScrollStep)
    }

    for _, definition in buttonDefinitions {
        buttonName := definition[1]
        mask := definition[2]
        ; Left click is press-and-hold here too, so a drag works over an elevated
        ; window. The ledger and its release live in SteamShell-Common.ahk, so
        ; this process cannot disagree with the other two about what is held.
        if ControllerBindingHoldsMouseButton(
            ControllerMap.Has(buttonName ".Short")
                ? ControllerMap[buttonName ".Short"] : "") {
            if pressed & mask
                HoldControllerMouseButton("LButton")
            if released & mask
                ReleaseControllerMouseButtons()
            downTick[buttonName] := 0
            longFired[buttonName] := false
            continue
        }
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
        if ControllerBindingHoldsMouseButton(
            ControllerMap.Has(triggerName ".Short")
                ? ControllerMap[triggerName ".Short"] : "") {
            if triggerPressed
                HoldControllerMouseButton("LButton")
            if triggerReleased
                ReleaseControllerMouseButtons()
            downTick[triggerName] := 0
            longFired[triggerName] := false
            continue
        }
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

; "No UI, ever" was enforced only for the dialogs this file chooses to open.
; AutoHotkey's own response to an UNCAUGHT error is a modal dialog with Reload,
; ExitApp, Continue and Abort on it, and it does not ask -- so the one kind of
; dialog nobody wrote was the one that could appear. It did: a shadowed local
; named `buffer` threw inside the frame cap path and put that box on the shell
; desktop, in a High-integrity process the user has no other way to reach.
;
; Registered before anything else runs so it covers the argument parsing and
; identity checks below as well. LogLine tolerates an empty LogPath, so this is
; safe here even though the log destination is read on the next lines.
HandleUncaughtHelperError(thrown, mode) {
    try ReleaseControllerMouseButtons()
    message := "an unknown error"
    try message := thrown.Message " (" thrown.File ":" thrown.Line ")"
    LogLine("Uncaught error in the helper: " message "; helper stopping.",
        "Error")
    ExitApp(1)
    return 1 ; suppress the dialog, whatever happens above
}
OnError(HandleUncaughtHelperError)

ParentPid := Integer(ReadArgument("parent-pid", "0"))
MainPath := ReadArgument("main-path", "")
SettingsPath := ReadArgument("settings", "")
LogPath := ReadArgument("log", "")
; Anything that is not exactly "xfe" is the standalone shell helper. Stated in
; that direction on purpose: an unrecognised or absent value must not silently
; become the narrower product, because the narrower product does no elevated
; input and a standalone user would get a helper that appears to run and never
; reaches a single elevated window.
HelperProduct := StrLower(Trim(ReadArgument("product", "standalone"))) = "xfe"
    ? "xfe" : "standalone"
if (HelperProduct = "xfe") {
    MainImageName := "steamshell-xfe.exe"
    HelperInputEnabled := false
    HelperGeometryEnabled := false
}
identityError := ""
parentIdentityError := ""
; No UI, ever. A scheduled task registered as HighestAvailable resolves to a
; normal token for a non-administrator, and a modal dialog on a shell desktop
; with no taskbar and no keyboard is unrecoverable. Main reports the failure
; through its log and Health Check instead.
if !A_IsAdmin {
    LogLine(
        "The helper was started without a High-integrity token; helper stopping.",
        "Error")
    ExitApp()
}
if !ParentPid && MainPath != ""
    ParentPid := FindMainProcess()
if !ParentPid || !ProcessExist(ParentPid) || SettingsPath = "" {
    LogLine("Invalid helper launch arguments; helper stopping.", "Error")
    ExitApp()
}
selfPid := DllCall("Kernel32\GetCurrentProcessId", "UInt")
if (!GetProcessTokenSecurity(
        selfPid, &actualUserSid, &actualSessionId,
        &actualIntegrity, &identityError)
    || !GetProcessTokenSecurity(
        ParentPid, &parentUserSid, &parentSessionId,
        &parentIntegrity, &parentIdentityError)
    || StrLower(actualUserSid) != StrLower(parentUserSid)
    || actualSessionId != parentSessionId) {
    LogLine(
        "Helper identity/session did not match its parent; helper stopping. "
        . identityError " " parentIdentityError, "Error")
    ExitApp()
}
if (HelperGeometryEnabled && !OpenParentGeometryEvent())
    LogLine(
        "The parent geometry event could not be opened; elevated geometry is disabled.",
        "Warning")
; Opened here so the failure is reported once at startup rather than being
; inferred from automatic mouse mode never engaging. PollController retries, so
; this is a diagnostic and not the only chance to open it.
if (HelperInputEnabled && !OpenParentAutoMouseEvent())
    LogLine(
        "The parent automatic-mouse event could not be opened; only a physically"
        . " held View/Back will engage mouse mode over an elevated window.",
        "Warning")
; Derived from the settings path this process was given, never from the request
; itself. Main owns both and they live in the same writable data directory.
SplitPath(SettingsPath, , &settingsDirectory)
RtssRequestPath := settingsDirectory != ""
    ? settingsDirectory "\rtss-request.ini" : ""
if !OpenParentRtssApplyEvent()
    LogLine(
        "The parent RTSS request event could not be opened; elevated frame cap"
        . " writes are disabled.", "Warning")
if !LoadConfiguration() {
    LogLine("Settings could not be loaded: " SettingsPath, "Error")
    ExitApp()
}
LogLine("Elevated window helper " HelperVersion " started for parent PID "
    . ParentPid " (product " HelperProduct ", input "
    . (HelperInputEnabled ? "on" : "off") ", geometry "
    . (HelperGeometryEnabled ? "on" : "off") ").")
OnExit(HelperExitCleanup)
; PollController still runs for XFE: it owns the parent-liveness check, the
; settings reload, and the RTSS request wait. Its input half returns early.
SetTimer(PollController, PollIntervalMs)
SetTimer(ControllerMouseSafetyTick, 5000)
if HelperGeometryEnabled
    SetTimer(ElevatedWindowGeometryTick, 500)

; Thin wrappers over the definitions in SteamShell-Common.ahk. The state each
; one needs is a global here and a parameter there, which is what lets a single
; definition serve all three programs.
ReadBool(section, key, fallback := false) {
    global SettingsPath
    return ReadIniBool(SettingsPath, section, key, fallback)
}

ReadInt(section, key, fallback, minimum, maximum) {
    global SettingsPath
    return ReadIniInt(SettingsPath, section, key, fallback, minimum, maximum)
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

SendChordSafe(keys) {
    SendChordReleasingModifiers(keys)
}
