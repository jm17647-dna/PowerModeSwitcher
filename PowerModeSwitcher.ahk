#Requires AutoHotkey v2.0
#SingleInstance Off
#include Lib\UIA.ahk

; ============================================================================
;  PowerModeSwitcher  v1.1
;  Windows 托盘小工具：一个快捷键 / 托盘左键单击，在 日常-游戏-静音 三档
;  电源模式间循环切换，并在鼠标所在显示器底部中央显示短暂 OSD。
;  v1.1 新增：可同步切换 GIGABYTE Control Center 的风扇模式（需管理员权限）
;  仅依赖 Windows 自带的 powercfg.exe，绿色便携。
; ============================================================================

; ---------------------------------------------------------------------------
; 0. 全局状态
; ---------------------------------------------------------------------------
global APP_NAME     := "PowerModeSwitcher"
global APP_TITLE    := "电源模式切换器"
global SCRIPT_DIR   := A_ScriptDir
global CONFIG_PATH  := A_ScriptDir . "\config.ini"
global LOG_DIR      := A_ScriptDir . "\logs"
global OSD_TITLE    := "PowerModeOSD_" . A_ScriptHwnd

global WM_TRAYICON  := 0x404
global WM_LBUTTONUP := 0x202

global CFG          := {}      ; [General] 段
global MODES        := []      ; 三个模式
global OSD_GUI      := 0
global OSD_TXT      := 0
global OSD_BG       := "1F1F1F"   ; 卡片底色：中性灰，不用蓝
global OSD_FG       := "F5F5F5"   ; 主文字
global OSD_MUTED    := "A3A3A3"   ; 副文字
global OSD_ACCENT_DEFAULT := "8A8A8A"
global OSD_RADIUS   := 8          ; Win11 原生圆角
global OSD_SUB      := 0      ; OSD 副标题（计划名 · 滑块状态）
global OSD_CNT      := 0      ; OSD 右侧档位序号（1 / 3）
global OSD_ACC      := 0      ; OSD 左侧模式强调条
global CUR_IDX      := 0       ; 当前模式序号（以系统实际计划为准）
global HOTKEY_OK    := false
global BUSY         := false   ; 防止连点重入
global FAN_TIP_SHOWN := false  ; 风扇联动跳过提示只弹一次
global ELEVATED_TASK := "PowerModeSwitcher_Elevated"
global ELEVATED_TASK_OK := -1  ; -1 未知 / 0 不存在 / 1 已存在

; ---- 电源滑块（overlay）联动状态 ----
global OVERLAY_OK           := false
global OVERLAY_ORIGINAL     := ""
global OVERLAY_MIN_GUID     := ""
global OVERLAY_LAST_APPLIED := ""
global OVERLAY_CFG_ENABLED  := true
global OVERLAY_ECO_IDX      := 3
global OVERLAY_NEEDS_ADMIN  := false   ; 实测 rc=5：非管理员改不了电源滑块
global SWITCH_DENIED := false          ; 本次切档是否因权限被拒
global OVERLAY_TIP_SHOWN    := false

; ---- 日志保留天数 ----
global LOG_KEEP_DAYS        := 14

; ---- OSD 淡入淡出令牌 ----
global OSD_FADE_TOKEN       := 0
global FADE_X               := 0
global FADE_X_FROM          := 0
global FADE_Y_FROM          := 0
global FADE_Y_TO            := 0
global FADE_BAR_X           := 0
global FADE_BAR_W           := 0
global FADE_BAR_H           := 0
global FADE_WIN_H           := 0

global SI_MUTEX := 0

global GUID_PATTERN := "i)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"

; 全局异常兜底：AHK 默认会给未捕获异常弹 MsgBox。开机自启时没人能点它，
; 于是就成了“每次开机一个错误弹窗”。这里一律改写成日志，绝不弹窗。
OnError(GlobalErrorHandler)
try {
    Main()
} catch as e {
    FatalLog("Main 顶层异常：" . e.Message . "（" . e.File . ":" . e.Line . "）")
    ExitApp 1
}


; 单实例守卫：已有实例就安静退出（不弹窗）。开机时启动文件夹快捷方式与提权计划
; 任务可能同时拉起两份，且低权限那份关不掉提权那份 —— 这正是那个弹窗的来源。
SingleInstanceGuard() {
    global SI_MUTEX, LOG_DIR, APP_NAME
    ; 注意：互斥体名只能有一个反斜杠，写 "Local\\..." 会得到 ERROR_INVALID_NAME(123)
    name := "Local\PowerModeSwitcher_" . A_UserName
    SI_MUTEX := DllCall("CreateMutexW", "Ptr", 0, "Int", 0, "WStr", name, "Ptr")
    err := A_LastError
    if (err = 183) {                                       ; ERROR_ALREADY_EXISTS
        try {
            logFile := LOG_DIR . "\" . FormatTime(A_Now, "yyyy-MM-dd") . ".log"
            FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") . " 已有实例在运行（" . name . "），本次启动直接退出。`n", logFile, "UTF-8")
        }
        if (SI_MUTEX)
            DllCall("CloseHandle", "Ptr", SI_MUTEX)
        return true
    }
    return false
}

; ---------------------------------------------------------------------------
; 1. 主流程
; ---------------------------------------------------------------------------
Main() {
    global CFG, MODES

    if !DirExist(LOG_DIR)
        DirCreate(LOG_DIR)

    ; 单实例：用命名互斥体自己判断，绝不做“关闭上一个实例”这种会被 UAC 拦下的动作
    if SingleInstanceGuard()
        ExitApp()

    LoadConfig()
    InitOverlay()                   ; 只读记录启动时的电源滑块值（不改电源状态）
    PruneLogs()                     ; 清理过期日志

    if (A_Args.Length >= 1 && A_Args[1] = "--selftest") {
        SelfTest()
        return
    }

    InitOSD()                       ; 预创建隐藏 OSD 窗口（之后只改文本/位置）

    if (A_Args.Length >= 1 && A_Args[1] = "--test") {
        MsgBox("PowerModeSwitcher 能正常启动。`n`n点确定后退出；正式使用时双击 start.cmd。", "启动自检", "Iconi")
        ExitApp()
    }

    if (A_Args.Length >= 1 && A_Args[1] = "--test-switch") {
        SwitchTo(1)                  ; 只跑一次切换，用来验证失败提示
        SetTimer(() => ExitApp(), -4000)
        Persistent()
        return
    }

    if (A_Args.Length >= 1 && A_Args[1] = "--demo-osd") {
        DemoOSD()                   ; 依次演示三档 OSD（不注册热键、不建托盘）
        return
    }

    RegisterHotkey()
    SetupTray()
    SyncFromSystem(true)            ; 读系统实际计划 -> 托盘图标，不弹提示
    ; 启动时用 OSD 报一次当前档：手动双击 start.cmd 时也能立刻看到"它活着"
    if (CFG.ShowOSDOnStart)
        ShowOSD(ModeLabel(CUR_IDX), MODES[CUR_IDX].name . OverlaySubtitleSuffix(),
                ModeAccentHex(CUR_IDX), (CUR_IDX . " / " . MODES.Length))
    if (CFG.StartWithWindows)
        EnsureStartupShortcut()

    Log("启动完成 | 当前=" . ModeLabel(CUR_IDX) . " | 系统计划=" . GetActivePlanGuid()
        . " | 热键=" . CFG.Hotkey . "(" . (HOTKEY_OK ? "已注册" : "注册失败") . ")")
    Persistent()
}

; ---------------------------------------------------------------------------
; 2. 配置解析（自实现 UTF-8 INI，避免 IniRead 按 ANSI 解码中文）
; ---------------------------------------------------------------------------
LoadConfig() {
    global CFG, MODES, CONFIG_PATH
    global OVERLAY_CFG_ENABLED, OVERLAY_ECO_IDX, OVERLAY_MIN_GUID, LOG_KEEP_DAYS

    text := ""
    if FileExist(CONFIG_PATH) {
        try
            text := FileRead(CONFIG_PATH, "UTF-8")
        catch as e {
            LogErr("读取 config.ini 失败：" . e.Message)
        }
    } else {
        LogErr("未找到 config.ini，使用内置默认值：" . CONFIG_PATH)
    }

    ini := ParseIni(text)

    CFG.Hotkey           := IniVal(ini, "General", "Hotkey", "Alt+Q")
    CFG.OSDDuration      := ToInt(IniVal(ini, "General", "OSD_Duration", "900"), 900)
    CFG.OSDOpacity       := Clamp(ToInt(IniVal(ini, "General", "OSD_Opacity", "191"), 191), 0, 255)
    CFG.OSDFontSize      := ToInt(IniVal(ini, "General", "OSD_FontSize", "15"), 15)
    CFG.OSDBottomMargin  := ToInt(IniVal(ini, "General", "OSD_BottomMargin", "80"), 80)
    CFG.StartWithWindows := ToInt(IniVal(ini, "General", "StartWithWindows", "1"), 1)
    CFG.TrayLeftClick    := ToInt(IniVal(ini, "General", "TrayLeftClick", "1"), 1)
    CFG.FanModeSync      := ToInt(IniVal(ini, "General", "FanModeSync", "0"), 0)
    CFG.OverlaySync      := ToInt(IniVal(ini, "General", "OverlaySync", "1"), 1)
    CFG.OverlayEcoMode   := Clamp(ToInt(IniVal(ini, "General", "OverlayEcoMode", "3"), 3), 1, 3)
    CFG.OverlayMinGuid   := StrLower(Trim(IniVal(ini, "General", "OverlayMinGuid", ""), " `t`r`n"))
    CFG.LogKeepDays      := ToInt(IniVal(ini, "General", "LogKeepDays", "14"), 14)
    CFG.ShowOSDOnStart   := ToInt(IniVal(ini, "General", "OSD_OnStart", "1"), 1)

    OVERLAY_CFG_ENABLED := (CFG.OverlaySync = 1)
    OVERLAY_ECO_IDX     := CFG.OverlayEcoMode
    OVERLAY_MIN_GUID    := CFG.OverlayMinGuid
    LOG_KEEP_DAYS       := CFG.LogKeepDays

    MODES := []
    MODES.Push(NewMode(1, ini, "日常", "平衡", "381b4222-f694-41f0-9685-ff5bb260df2e", "icon_balanced.ico"))
    MODES.Push(NewMode(2, ini, "游戏", "高性能", "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c", "icon_performance.ico"))
    MODES.Push(NewMode(3, ini, "静音", "节能", "a1841308-3541-4fab-bc81-f71556f20b4a", "icon_powersave.ico"))
}

NewMode(i, ini, defName, defPlan, defGuid, defIcon) {
    sec := "Mode" . i
    m := {}
    m.idx := i
    m.name := IniVal(ini, sec, "Name", defName)
    m.planName := IniVal(ini, sec, "PowerPlanName", defPlan)
    m.guid := StrLower(IniVal(ini, sec, "PowerPlanGuid", defGuid))
    m.nativeGuid := StrLower(IniVal(ini, sec, "NativeGuid", defGuid))
    m.icon := IniVal(ini, sec, "TrayIcon", defIcon)
    m.fanMode := Trim(IniVal(ini, sec, "FanMode", ""), " `t")
    m.resolved := false
    m.available := true
    if (m.guid = "")
        m.guid := defGuid
    if (m.nativeGuid = "")
        m.nativeGuid := m.guid
    return m
}

ParseIni(text) {
    ini := {}
    section := ""
    Loop Parse text, "`n", "`r" {
        line := Trim(A_LoopField, " `t`r")
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        if (SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]") {
            section := Trim(SubStr(line, 2, StrLen(line) - 2), " `t")
            if !ini.HasOwnProp(section)
                ini.%section% := {}
            continue
        }
        eq := InStr(line, "=")
        if (!eq || section = "")
            continue
        key := Trim(SubStr(line, 1, eq - 1), " `t")
        val := Trim(SubStr(line, eq + 1), " `t")
        if (key != "")
            ini.%section%.%key% := val
    }
    return ini
}

IniVal(ini, sec, key, def) {
    if (Type(ini) != "Object" || !ini.HasOwnProp(sec))
        return def
    if !ini.%sec%.HasOwnProp(key)
        return def
    v := ini.%sec%.%key%
    return (v = "") ? def : v
}

ToInt(s, def) {
    if (s = "" || !IsNumber(s))
        return def
    return Integer(s)
}

Clamp(v, lo, hi) {
    return v < lo ? lo : (v > hi ? hi : v)
}

; 只改写目标键所在行，保留注释、空行、换行风格与 BOM 状态
UpdateConfigValue(section, key, newValue) {
    global CONFIG_PATH
    if !FileExist(CONFIG_PATH) {
        LogErr("配置写回失败：config.ini 不存在")
        return false
    }
    raw := FileRead(CONFIG_PATH, "UTF-8")
    hasBOM := (SubStr(raw, 1, 1) = Chr(0xFEFF))
    body := hasBOM ? SubStr(raw, 2) : raw
    nl := InStr(body, "`r`n") ? "`r`n" : "`n"
    lines := StrSplit(StrReplace(body, "`r`n", "`n"), "`n")

    cur := "", done := false
    for i, line in lines {
        t := Trim(line, " `t")
        if (t = "" || SubStr(t, 1, 1) = ";")
            continue
        if (SubStr(t, 1, 1) = "[" && SubStr(t, -1) = "]") {
            cur := Trim(SubStr(t, 2, StrLen(t) - 2), " `t")
            continue
        }
        if (cur != section)
            continue
        eq := InStr(t, "=")
        if (eq && Trim(SubStr(t, 1, eq - 1), " `t") = key) {
            lines[i] := key . "=" . newValue
            done := true
            break
        }
    }
    if !done {
        LogErr("配置写回失败：未找到 " . section . "/" . key)
        return false
    }
    if !WriteAllText(CONFIG_PATH, JoinArray(lines, nl), hasBOM ? "UTF-8" : "UTF-8-RAW") {
        LogErr("配置写回失败：写入被拒绝")
        return false
    }
    Log("配置已更新：" . section . "/" . key . "=" . newValue)
    return true
}

JoinArray(arr, sep) {
    out := ""
    for i, v in arr
        out .= (i = 1 ? "" : sep) . v
    return out
}

WriteAllText(path, text, enc := "UTF-8") {
    try {
        f := FileOpen(path, "w", enc)
        if !f
            return false
        f.Write(text)
        f.Close()
        return true
    } catch as e {
        LogErr("WriteAllText 异常：" . e.Message)
        return false
    }
}

; ---------------------------------------------------------------------------
; 3. 日志 / 提示
; ---------------------------------------------------------------------------
Log(msg) {
    global LOG_DIR
    line := "[" . FormatTime(, "yyyy-MM-dd HH:mm:ss") . "] " . msg . "`n"
    try {
        if !DirExist(LOG_DIR)
            DirCreate(LOG_DIR)
        FileAppend(line, LOG_DIR . "\" . FormatTime(, "yyyy-MM-dd") . ".log", "UTF-8")
    } catch {
        FatalLog(msg)                      ; 日志目录不可写时的最后兜底
    }
}

LogErr(msg) {
    Log("ERROR " . msg)
}

; 最后兜底：连 logs 目录都写不进去时，退到脚本目录，绝不弹窗
FatalLog(msg) {
    global LOG_DIR
    line := "[" . FormatTime(, "yyyy-MM-dd HH:mm:ss") . "] FATAL " . msg . "`n"
    try {
        if !DirExist(LOG_DIR)
            DirCreate(LOG_DIR)
        FileAppend(line, LOG_DIR . "\" . FormatTime(, "yyyy-MM-dd") . ".log", "UTF-8")
    } catch {
        try FileAppend(line, A_ScriptDir . "\PowerModeSwitcher_fatal.log", "UTF-8")
    }
}

; OnError 回调：所有未捕获异常写日志，返回 true 抑制默认 MsgBox
GlobalErrorHandler(err, mode) {
    txt := ""
    try txt := err.Message . " @ " . err.File . ":" . err.Line . " [" . err.What . "]"
    catch
        txt := "无法读取异常详情"
    try LogErr("未捕获异常(mode=" . mode . ")：" . OneLine(txt, 300))
    catch
        FatalLog("未捕获异常(mode=" . mode . ")：" . txt)
    return true
}

; 按天保留日志：超过 LOG_KEEP_DAYS 天的 .log 自动删除
PruneLogs() {
    global LOG_DIR, LOG_KEEP_DAYS
    if (LOG_KEEP_DAYS <= 0 || !DirExist(LOG_DIR))
        return
    cutoff := DateAdd(A_Now, -LOG_KEEP_DAYS, "Days")
    removed := 0
    try {
        Loop Files, LOG_DIR . "\*.log", "F" {
            if (A_LoopFileTimeModified < cutoff) {
                try {
                    FileDelete A_LoopFileFullPath
                    removed += 1
                }
            }
        }
    } catch as e {
        LogErr("日志清理失败：" . e.Message)
    }
    if (removed > 0)
        Log("日志清理：删除 " . removed . " 个超过 " . LOG_KEEP_DAYS . " 天的日志")
}

Notify(text, isError := false) {
    ; 不弹托盘气泡（用户嫌弹窗多）：只进日志
    Log((isError ? "提示：" : "提示：") . text)
}

OneLine(s, maxLen := 160) {
    s := StrReplace(s, "`r", " ")
    s := StrReplace(s, "`n", " | ")
    s := Trim(s, " `t")
    if (StrLen(s) > maxLen)
        s := SubStr(s, 1, maxLen) . "…"
    return s
}

; ---------------------------------------------------------------------------
; 4. powercfg 封装
; ---------------------------------------------------------------------------
RunPowerCfg(args) {
    global SCRIPT_DIR
    q := Chr(34)
    tmp := A_Temp . "\pms_" . A_TickCount . "_" . Random(1000, 9999) . ".tmp"
    cmd := A_ComSpec . " /c powercfg.exe " . args . " > " . q . tmp . q . " 2>&1"
    code := RunWait(cmd, SCRIPT_DIR, "Hide")
    out := ""
    if FileExist(tmp) {
        try
            out := FileRead(tmp, "CP0")     ; 多数情况是系统 ANSI/OEM 代码页
        catch
            out := ""
        if (Trim(out, " `t`r`n") = "") {
            try out := FileRead(tmp, "UTF-16")   ; 被重定向时 powercfg 会写 UTF-16LE
            catch
                out := out
        }
        try FileDelete tmp
    }
    return { code: code, out: Trim(out, " `t`r`n") }
}

; 读当前电源计划：直接调 powrprof.dll（约 0.1ms），
; 只有 API 不可用时才退回 powercfg 进程（约 80ms）。
GetActivePlanGuid() {
    pGuid := 0
    r := DllCall("powrprof\PowerGetActiveScheme", "ptr", 0, "ptr*", &pGuid, "uint")
    if (r = 0 && pGuid) {
        guid := BufferToGuidStr(pGuid)
        DllCall("LocalFree", "ptr", pGuid, "ptr")
        if (guid != "")
            return guid
    }
    rr := RunPowerCfg("/getactivescheme")
    if RegExMatch(rr.out, GUID_PATTERN, &m)
        return StrLower(m[1])
    LogErr("解析当前电源计划失败 hr=" . r . " exit=" . rr.code . " out=" . OneLine(rr.out))
    return ""
}

; 切换电源计划：同样直调 API，失败再退回 powercfg。
SetActivePlan(guid) {
    buf := GuidStrToBuffer(guid)
    if (buf) {
        r := DllCall("powrprof\PowerSetActiveScheme", "ptr", 0, "ptr", buf, "uint")
        if (r = 0)
            return { code: 0, out: "PowerSetActiveScheme" }
        LogErr("PowerSetActiveScheme " . guid . " 返回 " . r . "，回退 powercfg")
    }
    r2 := RunPowerCfg("/setactive " . guid)
    if (r2.code != 0) {
        denied := RegExMatch(r2.out, "权限|拒绝访问|Access is denied") ? true : false
        LogErr("setactive " . guid . " 失败 exit=" . r2.code
            . " denied=" . (denied ? "1" : "0") . " out=" . OneLine(r2.out))
        return { code: r2.code, out: r2.out, denied: denied }
    }
    return r2
}

; "381b4222-f694-41f0-9685-ff5bb260df2e" -> 16 字节 GUID 结构
GuidStrToBuffer(guid) {
    p := StrSplit(StrLower(guid), "-")
    if (p.Length != 5 || StrLen(p[1]) != 8 || StrLen(p[2]) != 4 || StrLen(p[3]) != 4
        || StrLen(p[4]) != 4 || StrLen(p[5]) != 12)
        return 0
    buf := Buffer(16, 0)
    NumPut("uint",   Integer("0x" . p[1]), buf, 0)
    NumPut("ushort", Integer("0x" . p[2]), buf, 4)
    NumPut("ushort", Integer("0x" . p[3]), buf, 6)
    Loop 2
        NumPut("uchar", Integer("0x" . SubStr(p[4], A_Index * 2 - 1, 2)), buf, 7 + A_Index)
    Loop 6
        NumPut("uchar", Integer("0x" . SubStr(p[5], A_Index * 2 - 1, 2)), buf, 9 + A_Index)
    return buf
}

; 16 字节 GUID 结构 -> 字符串（小端）
BufferToGuidStr(p) {
    d1 := NumGet(p + 0, "uint")
    d2 := NumGet(p + 4, "ushort")
    d3 := NumGet(p + 6, "ushort")
    s := Format("{:08x}-{:04x}-{:04x}-", d1, d2, d3)
    Loop 2
        s .= Format("{:02x}", NumGet(p + 7 + A_Index, "uchar"))
    s .= "-"
    Loop 6
        s .= Format("{:02x}", NumGet(p + 9 + A_Index, "uchar"))
    return s
}

ListPlanGuids() {
    r := RunPowerCfg("/list")
    set := Map()
    pos := 1
    while (pos := RegExMatch(r.out, GUID_PATTERN, &m, pos)) {
        set[StrLower(m[1])] := true
        pos := m.Pos + m.Len
    }
    return set
}

DuplicateScheme(templateGuid) {
    r := RunPowerCfg("-duplicatescheme " . templateGuid)
    if (r.code != 0) {
        LogErr("duplicatescheme " . templateGuid . " 失败 exit=" . r.code . " out=" . OneLine(r.out))
        return ""
    }
    if RegExMatch(r.out, GUID_PATTERN, &m) {
        Log("duplicatescheme 成功：" . templateGuid . " -> " . m[1])
        return StrLower(m[1])
    }
    LogErr("duplicatescheme 输出中未找到新 GUID：" . OneLine(r.out))
    return ""
}

RenameScheme(guid, name) {
    q := Chr(34)
    r := RunPowerCfg("-changename " . guid . " " . q . name . q)
    if (r.code != 0) {
        LogErr("changename 失败 exit=" . r.code . " out=" . OneLine(r.out))
        return false
    }
    Log("changename 成功：" . guid . " -> " . name)
    return true
}

; ---------------------------------------------------------------------------
; 5. 模式解析与切换
; ---------------------------------------------------------------------------
IndexOfGuid(guid) {
    global MODES
    if (guid = "")
        return 0
    for i, m in MODES {
        if (m.guid = StrLower(guid))
            return i
    }
    return 0
}

ModeLabel(idx) {
    global MODES
    if (idx < 1 || idx > MODES.Length)
        return "未知"
    m := MODES[idx]
    return m.name . " · " . m.planName
}

; 首次解析某个模式：先试配置 GUID -> 试原生 GUID -> 基于原生模板复制并重命名
; 返回值表示“本模式是否可用”，成功时系统已切到该计划。
ResolveAndActivate(i) {
    global MODES
    m := MODES[i]

    r := SetActivePlan(m.guid)
    if (r.code = 0) {
        m.resolved := true, m.available := true
        Log("[" . m.name . "] 配置计划可激活：" . m.guid)
        return true
    }

    if (m.nativeGuid != "" && m.nativeGuid != m.guid) {
        r2 := SetActivePlan(m.nativeGuid)
        if (r2.code = 0) {
            Log("[" . m.name . "] 回退原生计划成功：" . m.nativeGuid)
            m.guid := m.nativeGuid
            m.resolved := true, m.available := true
            UpdateConfigValue("Mode" . i, "PowerPlanGuid", m.guid)
            return true
        }
    }

    tpl := (m.nativeGuid != "") ? m.nativeGuid : m.guid
    Log("[" . m.name . "] 原生计划不可激活，尝试基于模板 " . tpl . " 复制")
    newGuid := DuplicateScheme(tpl)
    if (newGuid = "") {
        m.resolved := true, m.available := false
        Notify(m.name . " 模式不可用：无法激活或复制对应电源计划（详见 logs）。", true)
        return false
    }

    RenameScheme(newGuid, m.planName)        ; 命名失败不影响可用性
    m.guid := newGuid
    m.resolved := true
    UpdateConfigValue("Mode" . i, "PowerPlanGuid", newGuid)

    r3 := SetActivePlan(newGuid)
    m.available := (r3.code = 0)
    if !m.available
        Notify(m.name . " 模式不可用：新建计划激活失败（详见 logs）。", true)
    else
        Log("[" . m.name . "] 已创建并启用新计划：" . newGuid)
    return m.available
}

ActivateMode(i) {
    global MODES
    m := MODES[i]
    if (!m.resolved)
        return ResolveAndActivate(i)
    if (!m.available)
        return false
    r := SetActivePlan(m.guid)
    if (r.code = 0)
        return true
    ; 计划被外部删除/改动：丢弃缓存，重新解析一次
    LogErr("[" . m.name . "] 缓存的计划失效，重新解析")
    m.resolved := false
    return ResolveAndActivate(i)
}

CycleMode(*) {
    global MODES, CUR_IDX, BUSY
    if BUSY
        return
    BUSY := true
    try {
        n := MODES.Length
        if (n = 0)
            return
        cur := GetActivePlanGuid()
        idx := IndexOfGuid(cur)
        if (idx = 0)
            idx := 1                      ; 不在三模式内 -> 视作“日常”

        attempts := 0
        Loop n - 1 {
            cand := Mod(idx + A_Index - 1, n) + 1
            if MODES[cand].resolved && !MODES[cand].available
                continue                  ; 已确认不可用，直接跳过
            if SwitchTo(cand)
                return
            global SWITCH_DENIED
            if SWITCH_DENIED {          ; 权限问题，试其它档也一样失败
                SWITCH_DENIED := false
                return
            }
            ; 切换失败：该模式已被标记不可用，继续试下一个
            attempts += 1
            if (attempts >= n - 1)
                return
        }
        ; 其它模式都不可用：原地确认当前模式，至少给出反馈
        SwitchTo(idx)
    } finally {
        BUSY := false
    }
}

SwitchTo(i) {
    global MODES, CUR_IDX
    m := MODES[i]
    if !ActivateMode(i) {
        global SWITCH_DENIED
        SWITCH_DENIED := true
        ShowOSD("切换失败", m.name . " · 权限不足，试试托盘菜单「免 UAC 提权启动」", "EF4444", "")
        Notify("切换失败：" . m.name . "（权限不足，详见 logs）", true)
        LogErr("切换失败：" . m.name)
        return false
    }
    actual := GetActivePlanGuid()
    realIdx := IndexOfGuid(actual)
    CUR_IDX := realIdx ? realIdx : i
    UpdateTrayVisual(CUR_IDX)
    ApplyOverlayForMode(CUR_IDX)     ; 节能档 -> 最佳能效，离开则恢复原值

    ; OSD 用 CUR_IDX（系统实际生效的档）而不是目标 i：
    ; 万一底层没切成功，图标和 OSD 也不会一个蓝一个粉地互相打架
    if (realIdx && realIdx != i)
        LogErr("注意：目标=" . ModeLabel(i) . " 但系统实际=" . ModeLabel(realIdx) . "，OSD 按实际显示")
    ShowOSD(ModeLabel(CUR_IDX), MODES[CUR_IDX].name . OverlaySubtitleSuffix(), ModeAccentHex(CUR_IDX)
        , (CUR_IDX . " / " . MODES.Length))
    Log("切换 -> " . ModeLabel(i) . " | 目标 GUID=" . m.guid . " | 系统实际=" . actual
        . (realIdx = i ? "" : " | 注意：实际计划与目标不一致"))

    ; 风扇联动放到异步，避免拖慢电源切换和 OSD
    if (m.fanMode != "")
        SetTimer(() => SyncExtras(i), -80)
    return true
}

; 外部联动：风扇（抢焦点约 300ms）
SyncExtras(idx) {
    global MODES
    m := MODES[idx]
    label := ModeLabel(idx)
    if (m.fanMode != "")
        ApplyGccFanMode(m.fanMode, label)
}

SelectMode(i, *) {
    global BUSY
    if BUSY
        return
    BUSY := true
    try SwitchTo(i)
    finally BUSY := false
}

; 以系统实际激活的计划为准，刷新托盘图标（不切换任何东西）
SyncFromSystem(quiet) {
    global CUR_IDX
    g := GetActivePlanGuid()
    idx := IndexOfGuid(g)
    if (idx = 0)
        idx := 1
    CUR_IDX := idx
    UpdateTrayVisual(idx)
    ApplyOverlayForMode(idx)
    Log("同步系统计划：" . g . " -> " . ModeLabel(idx) . (IndexOfGuid(g) ? "" : "（不在三模式内，按日常显示）"))
    if !quiet
        Notify("当前：" . ModeLabel(idx))
}

; ---------------------------------------------------------------------------
; 5b. 电源滑块（overlay）联动 —— powrprof.dll 直调，无 UI / 无管理员 / 0ms
; ---------------------------------------------------------------------------
; Windows 设置里的「电源模式」三档滑块底层是 overlay scheme。
; 节能档 -> 设为「最佳能效」；离开节能档 -> 恢复启动时记录的原值。
; 整个过程不创建窗口、不抢焦点，这就是“无感”的那一半。

OverlayBufToStr(buf) {
    s := Format("{:08x}-{:04x}-{:04x}-", NumGet(buf, 0, "uint"), NumGet(buf, 4, "ushort"), NumGet(buf, 6, "ushort"))
    Loop 2
        s .= Format("{:02x}", NumGet(buf, 7 + A_Index, "uchar"))
    s .= "-"
    Loop 6
        s .= Format("{:02x}", NumGet(buf, 9 + A_Index, "uchar"))
    return s
}

OverlayGetActual() {
    buf := Buffer(16, 0)
    rc := DllCall("powrprof\PowerGetActualOverlayScheme", "ptr", buf, "uint")
    if (rc != 0) {
        LogErr("PowerGetActualOverlayScheme 失败 rc=" . rc)
        return ""
    }
    return StrLower(OverlayBufToStr(buf))
}

OverlaySet(guid) {
    buf := GuidStrToBuffer(guid)
    if !buf
        return { ok: false, rc: -1 }
    rc := DllCall("powrprof\PowerSetActiveOverlayScheme", "ptr", buf, "uint")
    if (rc != 0) {
        LogErr("PowerSetActiveOverlayScheme(" . guid . ") 失败 rc=" . rc)
        return { ok: false, rc: rc }
    }
    return { ok: true, rc: 0 }
}

DiscoverOverlayMinGuid() {
    global OVERLAY_MIN_GUID
    if (OVERLAY_MIN_GUID != "")
        return OVERLAY_MIN_GUID        ; config.ini 显式指定优先
    ; 本机实测值；网上流传的 ...8177 在这台机器返回 rc=87
    OVERLAY_MIN_GUID := "961cc777-2547-4f9d-8174-7d86181b8a7a"
    return OVERLAY_MIN_GUID
}

InitOverlay() {
    global OVERLAY_OK, OVERLAY_ORIGINAL, OVERLAY_CFG_ENABLED, OVERLAY_MIN_GUID
    if !OVERLAY_CFG_ENABLED {
        Log("电源滑块联动：配置关闭（OverlaySync=0）")
        return
    }
    DiscoverOverlayMinGuid()
    OVERLAY_ORIGINAL := OverlayGetActual()
    if (OVERLAY_ORIGINAL = "") {
        OVERLAY_OK := false
        LogErr("电源滑块 API 不可用，联动已禁用（不影响电源计划切换）")
        return
    }
    OVERLAY_OK := true
    Log("电源滑块就绪（只读启动）| 原值=" . OVERLAY_ORIGINAL . " | 最佳能效=" . OVERLAY_MIN_GUID)
}

ApplyOverlayForMode(i) {
    global OVERLAY_OK, OVERLAY_ORIGINAL, OVERLAY_MIN_GUID, OVERLAY_LAST_APPLIED
    global OVERLAY_ECO_IDX, OVERLAY_CFG_ENABLED
    if (!OVERLAY_OK || !OVERLAY_CFG_ENABLED)
        return
    target := (i = OVERLAY_ECO_IDX) ? OVERLAY_MIN_GUID : OVERLAY_ORIGINAL
    if (target = "" || target = OVERLAY_LAST_APPLIED)
        return
    OVERLAY_LAST_APPLIED := target
    ; 异步：个别系统上电源服务可能短暂阻塞，不要卡住切档和 OSD
    SetTimer(ApplyOverlayAsync.Bind(target, i), -10)
}

ApplyOverlayAsync(target, i) {
    global OVERLAY_LAST_APPLIED, OVERLAY_ECO_IDX
    r := OverlaySet(target)
    if r.ok {
        Log("电源滑块 -> " . (i = OVERLAY_ECO_IDX ? "最佳能效" : "恢复原值")
            . " | 目标=" . target . " | 实际=" . OverlayGetActual())
    } else if (r.rc = 5) {
        ; ERROR_ACCESS_DENIED：本机实测非管理员无法改「电源模式」滑块
        global OVERLAY_NEEDS_ADMIN, OVERLAY_TIP_SHOWN
        OVERLAY_NEEDS_ADMIN := true
        LogErr("电源滑块需要管理员权限（rc=5），本次未改动；电源计划切换不受影响。"
            . "可在托盘菜单启用「免 UAC 提权启动」后重试。")
        if !OVERLAY_TIP_SHOWN {
            OVERLAY_TIP_SHOWN := true
            Notify("电源滑块需管理员权限，电源计划照常切换", true)
        }
        OVERLAY_LAST_APPLIED := ""     ; 允许下次重试
    } else {
        LogErr("电源滑块联动失败（rc=" . r.rc . "），电源计划切换不受影响 | 目标=" . target)
        OVERLAY_LAST_APPLIED := ""     ; 允许下次重试
    }
}

OverlayStatusLabel() {
    global OVERLAY_OK, OVERLAY_CFG_ENABLED, OVERLAY_LAST_APPLIED, OVERLAY_MIN_GUID, OVERLAY_ORIGINAL
    global OVERLAY_NEEDS_ADMIN
    if !OVERLAY_CFG_ENABLED
        return "电源滑块：联动已关闭"
    if !OVERLAY_OK
        return "电源滑块：API 不可用"
    if OVERLAY_NEEDS_ADMIN
        return "电源滑块：需管理员权限"
    if (OVERLAY_LAST_APPLIED = OVERLAY_MIN_GUID)
        return "电源滑块：最佳能效"
    return "电源滑块：原值 " . SubStr(OVERLAY_ORIGINAL, 1, 8)
}

; 副标题里更短的说法：OSD 只有一行副标题的空间，放得下才看得懂
OverlaySubtitleSuffix() {
    global OVERLAY_CFG_ENABLED, OVERLAY_OK, OVERLAY_LAST_APPLIED, OVERLAY_MIN_GUID, OVERLAY_NEEDS_ADMIN
    if !OVERLAY_CFG_ENABLED
        return ""
    if !OVERLAY_OK
        return " · 滑块 不可用"
    if OVERLAY_NEEDS_ADMIN
        return " · 滑块 需提权"
    if (OVERLAY_LAST_APPLIED = OVERLAY_MIN_GUID)
        return " · 滑块 最佳能效"
    return " · 滑块 原值"
}

; 三档的模式强调色（与托盘图标同一套语义：中性 / 琥珀 / 绿）
ModeAccentHex(i) {
    static cols := ["5393FF", "EC4899", "22C55E"]
    if (i >= 1 && i <= cols.Length)
        return cols[i]
    return "94A3B8"
}

; ---------------------------------------------------------------------------
; 6. 托盘
; ---------------------------------------------------------------------------
SetupTray() {
    global CFG
    A_IconTip := APP_NAME
    BuildTrayMenu()
    if (CFG.TrayLeftClick = 1)
        OnMessage(WM_TRAYICON, OnTrayMessage)
}

; 托盘图标回调：0x404 携带鼠标消息到 lParam
OnTrayMessage(wParam, lParam, msg, hwnd) {
    if (lParam = WM_LBUTTONUP) {
        CycleMode()
        return 0            ; 吞掉消息，阻止默认左键菜单
    }
    ; 其余（右键等）不拦截，交给 AHK 默认处理
}

UpdateTrayVisual(idx) {
    global MODES
    if (idx >= 1 && idx <= MODES.Length) {
        m := MODES[idx]
        iconPath := SCRIPT_DIR . "\" . m.icon
        if FileExist(iconPath)
            TraySetIcon(iconPath)
        else
            LogErr("图标文件不存在：" . iconPath)
        A_IconTip := APP_NAME . " · " . m.name . "（" . m.planName . "）"
    }
    BuildTrayMenu()
}

BuildTrayMenu() {
    global MODES, CUR_IDX, CFG
    t := A_TrayMenu
    t.Delete()

    curLabel := "当前：" . (CUR_IDX ? ModeLabel(CUR_IDX) : "未同步")
    t.Add(curLabel, (*) => 0)
    t.Disable(curLabel)
    hkLabel := "快捷键：" . CFG.Hotkey . (HOTKEY_OK ? "" : "（未生效）")
    t.Add(hkLabel, (*) => 0)
    t.Disable(hkLabel)

    fanState := !CFG.FanModeSync ? "已关闭"
              : (A_IsAdmin ? "已启用" : "待提权（当前非管理员）")
    fanLabel := "风扇联动：" . fanState
    t.Add(fanLabel, (*) => 0)
    t.Disable(fanLabel)

    ovLabel := OverlayStatusLabel()
    t.Add(ovLabel, (*) => 0)
    t.Disable(ovLabel)
    t.Add()

    for i, m in MODES {
        label := m.name . " · " . m.planName
        if (m.resolved && !m.available)
            label .= "（不可用）"
        t.Add(label, SelectMode.Bind(i))
        if (i = CUR_IDX)
            t.Check(label)
    }

    t.Add()
    t.Add("重新读取当前电源计划", (*) => SyncFromSystem(false))
    t.Add("恢复原生电源计划 GUID", RestoreNativeGuids)
    t.Add("打开配置文件", (*) => OpenPath(CONFIG_PATH))
    t.Add("打开日志目录", (*) => OpenPath(LOG_DIR))
    autoLabel := ElevatedTaskExistsCached()
        ? "开机自启：已启用（提权任务）"
        : ("开机自启：" . (FileExist(StartupLink()) ? "已启用" : "未启用"))
    t.Add(autoLabel, ToggleStartup)

    if (CFG.FanModeSync && !A_IsAdmin) {
        if ElevatedTaskExistsCached()
            t.Add("免 UAC 提权启动：已设置（点击取消）", DisableElevatedAutostart)
        else
            t.Add("启用免 UAC 提权启动…（会弹一次 UAC）", EnableElevatedAutostart)
    }
    t.Add()
    t.Add("退出", (*) => ExitApp())
}

; schtasks 查询有进程开销，缓存结果，避免每次重建菜单都查
ElevatedTaskExistsCached() {
    global ELEVATED_TASK_OK
    if (ELEVATED_TASK_OK = -1)
        ELEVATED_TASK_OK := ElevatedTaskExists() ? 1 : 0
    return (ELEVATED_TASK_OK = 1)
}

OpenPath(p) {
    if FileExist(p) || DirExist(p)
        Run p
    else
        Notify("路径不存在：" . p, true)
}

StartupLink() {
    global APP_NAME
    return A_Startup . "\" . APP_NAME . ".lnk"
}

RestoreNativeGuids(*) {
    global MODES
    changed := 0
    for i, m in MODES {
        if (m.nativeGuid != "" && m.guid != m.nativeGuid) {
            m.guid := m.nativeGuid
            m.resolved := false
            if UpdateConfigValue("Mode" . i, "PowerPlanGuid", m.nativeGuid)
                changed++
        }
    }
    Notify(changed ? "已恢复 " . changed . " 个原生 GUID，可重新测试切换。" : "配置中的 GUID 已是原生值。")
}

ToggleStartup(*) {
    link := StartupLink()
    if ElevatedTaskExistsCached() {
        Notify("开机自启现在由「免 UAC 提权启动」的计划任务负责；先取消它，才能切回普通快捷方式方式。", true)
        return
    }
    if FileExist(link) {
        try FileDelete link
        Notify("已取消开机自启。")
    } else {
        EnsureStartupShortcut(true)
    }
    BuildTrayMenu()
}

EnsureStartupShortcut(force := false) {
    link := StartupLink()
    ; 提权计划任务已经是 onlogon 触发的自启，再放一个启动文件夹快捷方式
    ; 就会在开机时同时拉起两份（低权限那份还会撞上那个“关不掉上个实例”的弹窗）。
    if ElevatedTaskExists() {
        if FileExist(link) {
            try FileDelete link
            Log("检测到提权自启任务，已移除重复的启动文件夹快捷方式")
        }
        return
    }
    if (!force && FileExist(link))
        return
    target := A_IsCompiled ? A_ScriptFullPath : A_AhkPath
    q := Chr(34)
    args   := A_IsCompiled ? "" : (q . A_ScriptFullPath . q)
    try {
        shell := ComObject("WScript.Shell")
        lnk := shell.CreateShortcut(link)
        lnk.TargetPath := target
        lnk.Arguments := args
        lnk.WorkingDirectory := SCRIPT_DIR
        lnk.IconLocation := SCRIPT_DIR . "\icon_balanced.ico"
        lnk.Description := "电源模式一键切换"
        lnk.Save()
        Log("已创建开机自启快捷方式：" . link)
        Notify("已启用开机自启。")
    } catch as e {
        LogErr("创建自启快捷方式失败：" . e.Message)
        Notify("创建开机自启失败：" . e.Message, true)
    }
}

; ---------------------------------------------------------------------------
; 7. 快捷键
; ---------------------------------------------------------------------------
RegisterHotkey() {
    global CFG, HOTKEY_OK
    hk := NormalizeHotkey(CFG.Hotkey)
    CFG.HotkeyEffective := hk
    try {
        Hotkey(hk, CycleMode)
        HOTKEY_OK := true
        Log("热键已注册：" . CFG.Hotkey . (hk = CFG.Hotkey ? "" : "（写法归一为 " . hk . "）"))
    } catch as e {
        HOTKEY_OK := false
        LogErr("热键注册失败 " . hk . "：" . e.Message)
        Notify("快捷键 " . CFG.Hotkey . " 注册失败（可能被占用），请在 config.ini 中修改后重启。托盘单击切换仍可用。", true)
    }
}

; AHK v2 的 Hotkey() 只认符号修饰键（^ ! + #），
; 这里把 "Alt+Q" / "Ctrl+Shift+M" 这类写法翻成符号写法。
NormalizeHotkey(s) {
    s := Trim(s, " `t")
    if (s = "")
        return ""
    low := StrLower(s)
    if !(InStr(low, "alt+") || InStr(low, "ctrl+") || InStr(low, "control+")
         || InStr(low, "shift+") || InStr(low, "win+") || InStr(low, "lwin+") || InStr(low, "rwin+"))
        return s                       ; 已是符号写法或单键名
    parts := StrSplit(s, "+")
    mods := "", key := ""
    for i, p in parts {
        p := Trim(p, " `t")
        if (i = parts.Length) {
            key := p
            break
        }
        pl := StrLower(p)
        if (pl = "ctrl" || pl = "control")
            mods .= "^"
        else if (pl = "alt")
            mods .= "!"
        else if (pl = "shift")
            mods .= "+"
        else if (pl = "win" || pl = "lwin" || pl = "rwin")
            mods .= "#"
        else
            return s                   ; 修饰键不认识，原样交给 AHK 报错
    }
    return mods . NormalizeKeyName(key)
}

NormalizeKeyName(k) {
    ; 注意：变量名不能叫 map，会遮蔽内置 Map 类导致构造失败
    static keyMap := Map("space","Space","esc","Esc","escape","Esc","enter","Enter","return","Enter","tab","Tab","backspace","Backspace","bs","Backspace","delete","Delete","del","Delete","insert","Insert","ins","Insert","home","Home","end","End","pgup","PgUp","pageup","PgUp","pgdn","PgDn","pagedown","PgDn","up","Up","down","Down","left","Left","right","Right","printscreen","PrintScreen","prtsc","PrintScreen","pause","Pause","scrolllock","ScrollLock","capslock","CapsLock","numlock","NumLock","appskey","AppsKey","menu","AppsKey")
    kl := StrLower(k)
    if (kl = "")
        return ""
    if keyMap.Has(kl)
        return keyMap[kl]
    if RegExMatch(kl, "^f([1-9]|1[0-9]|2[0-4])$")
        return kl
    if (StrLen(kl) = 1)
        return kl                     ; 字母/数字/符号：统一小写
    return k
}

; ---------------------------------------------------------------------------
; 8. OSD
; ---------------------------------------------------------------------------
InitOSD() {
    global OSD_GUI, OSD_TXT, OSD_SUB, OSD_CNT, OSD_ACC, OSD_TITLE
    ; +AlwaysOnTop 置顶 / -Caption +ToolWindow 无边框不占任务栏
    ; E0x20 = WS_EX_TRANSPARENT 点击穿透 / E0x08000000 = WS_EX_NOACTIVATE 不抢焦点
    ; -DPIScale = 关闭 AHK 自动 DPI 缩放，坐标与尺寸一律按物理像素计算（缩放由本脚本自控）
    OSD_GUI := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000 +E0x20", OSD_TITLE)
    OSD_GUI.BackColor := OSD_BG
    OSD_GUI.MarginX := 0
    OSD_GUI.MarginY := 0
    ; 左侧 3px 强调条：用模式色区分三档
    OSD_ACC := OSD_GUI.AddText("x0 y0 w1 h1 Background" . OSD_ACCENT_DEFAULT, "")
    ; 主标题：模式名，粗体高对比
    OSD_TXT := OSD_GUI.AddText("x0 y0 w1 h1 Background" . OSD_BG . " c" . OSD_FG . " Left +0x200", " ")
    OSD_TXT.SetFont("s15 w600", "Microsoft YaHei UI")
    ; 副标题：计划名 · 滑块状态，小一号、低对比
    OSD_SUB := OSD_GUI.AddText("x0 y0 w1 h1 Background" . OSD_BG . " c" . OSD_MUTED . " Left +0x200", " ")
    OSD_SUB.SetFont("s9 w400", "Microsoft YaHei UI")
    ; 右侧档位序号：1 / 3，右对齐，和副标题同号
    OSD_CNT := OSD_GUI.AddText("x0 y0 w1 h1 Background" . OSD_BG . " c" . OSD_MUTED . " Right +0x200", " ")
    OSD_CNT.SetFont("s9 w500", "Segoe UI Variable Display")
    OSD_GUI.Show("Hide")
}

ShowOSD(text, subtitle := "", accent := "", counter := "") {
    global OSD_GUI, OSD_TXT, OSD_SUB, OSD_CNT, OSD_ACC, CFG, OSD_FADE_TOKEN
    global OSD_BG, OSD_FG, OSD_ACCENT_DEFAULT
    global FADE_X, FADE_X_FROM, FADE_Y_FROM, FADE_Y_TO
    global FADE_BAR_X, FADE_BAR_W, FADE_BAR_H, FADE_WIN_H
    if !OSD_GUI
        return
    if (accent = "")
        accent := OSD_ACCENT_DEFAULT
    dpi   := GetDpiAtMouse()
    scale := dpi / 96
    pts   := CFG.OSDFontSize * dpi / A_ScreenDPI          ; 主标题字号（pt，已按目标 DPI 换算）
    subPts := Max(pts * 0.62, 7)                          ; 副标题：约 62% 字阶
    OSD_TXT.SetFont("s" . Round(pts * 10) / 10 . " w600", "Microsoft YaHei UI")
    OSD_TXT.Value := text
    tsz := MeasureTextSize(OSD_TXT, text)

    hasSub := (subtitle != "")
    hasCnt := (counter != "")
    sw := 0, sh := 0, cw := 0, ch := 0
    if hasSub {
        OSD_SUB.SetFont("s" . Round(subPts * 10) / 10 . " w400", "Microsoft YaHei UI")
        OSD_SUB.Value := subtitle
        ssz := MeasureTextSize(OSD_SUB, subtitle)
        sw := ssz.w, sh := ssz.h
    }
    if hasCnt {
        OSD_CNT.SetFont("s" . Round(subPts * 10) / 10 . " w500", "Segoe UI Variable Display")
        OSD_CNT.Value := counter
        csz := MeasureTextSize(OSD_CNT, counter)
        cw := csz.w, ch := csz.h
    }

    ; 栅格：内距 16 / 12，字阶之间 6，元素之间 12
    padX   := Round(16 * scale)
    padY   := Round(13 * scale)
    barW   := Max(Round(3 * scale), 2)
    gapX   := Round(12 * scale)
    gapY   := hasSub ? Round(6 * scale) : 0
    insetY := Round(10 * scale)

    textW := Max(tsz.w, sw) + Round(6 * scale)   ; 量宽余量，防止长标题压到序号
    winW  := padX * 2 + barW + gapX + textW
    if hasCnt
        winW += gapX + cw
    winH  := padY * 2 + tsz.h + gapY + sh

    MouseGetPos(&mx, &my)
    monIdx := MonitorIndexAtPoint(mx, my)
    MonitorGetWorkArea(monIdx, &wl, &wt, &wr, &wb)
    x := wl + ((wr - wl) - winW) // 2
    y := wb - winH - Round(CFG.OSDBottomMargin * scale)

    ; 卡片整块取模式色（压暗 45%，保证白字对比度）；色条与序号取同色提亮版
    barTint := MixHex(accent, "FFFFFF", 0.45)
    cardBg  := MixHex(OSD_BG, accent, 0.45)
    OSD_GUI.BackColor := cardBg
    OSD_TXT.Opt("Background" . cardBg)
    OSD_SUB.Opt("Background" . cardBg . " cE4E4E4")
    OSD_CNT.Opt("Background" . cardBg . " c" . barTint)

    ; 强调条：两端内缩，垂直居中，高度跟随内容
    accH := Max(winH - insetY * 2, 4)
    OSD_ACC.Opt("Background" . barTint)
    OSD_ACC.Move(padX, (winH - accH) // 2, barW, accH)

    tx := padX + barW + gapX
    OSD_TXT.Move(tx, padY, textW, tsz.h)
    if hasSub
        OSD_SUB.Move(tx, padY + tsz.h + gapY, textW, sh)
    if hasCnt
        ; 序号与主标题第一行对齐（视觉上跟着标题走，不跟着副标题）
        OSD_CNT.Move(winW - padX - cw, padY + (tsz.h - ch) // 2, cw, ch)

    ; 不做动画：直接出现在最终位置、最终不透明度（动画在低配/高刷屏上会掉帧）
    OSD_GUI.Move(x, y, winW, winH)
    ApplyRoundCorners(OSD_GUI.Hwnd, winW, winH, Round(OSD_RADIUS * scale))
    OSD_FADE_TOKEN += 1
    tok := OSD_FADE_TOKEN
    WinSetTransparent(CFG.OSDOpacity, OSD_GUI.Hwnd)
    OSD_GUI.Show("NA")
    SetTimer(FadeOutOSD.Bind(tok), -CFG.OSDDuration)
}

; 用控件当前字体量文字像素尺寸（比 Gui.AutoSize 可靠，隐藏窗口也能拿到正确值）
; 两个 "#RRGGBB" 按比例混合：base 为主，tint 占 mix 比例
MixHex(base, tint, mix) {
    b := Integer("0x" . base), t := Integer("0x" . tint)
    br := (b >> 16) & 0xFF, bg2 := (b >> 8) & 0xFF, bb := b & 0xFF
    tr := (t >> 16) & 0xFF, tg := (t >> 8) & 0xFF, tb := t & 0xFF
    r := Round(br + (tr - br) * mix)
    g := Round(bg2 + (tg - bg2) * mix)
    bl := Round(bb + (tb - bb) * mix)
    return Format("{:02X}{:02X}{:02X}", r, g, bl)
}

MeasureTextSize(ctl, text) {
    hfont := SendMessage(0x31, 0, 0, ctl.Hwnd)     ; WM_GETFONT
    hdc   := DllCall("GetDC", "ptr", 0, "ptr")
    hOld  := 0
    if (hfont)
        hOld := DllCall("SelectObject", "ptr", hdc, "ptr", hfont, "ptr")
    buf := Buffer(8, 0)
    DllCall("GetTextExtentPoint32W", "ptr", hdc, "wstr", text, "int", StrLen(text), "ptr", buf)
    w := NumGet(buf, 0, "int")
    h := NumGet(buf, 4, "int")
    if (hOld)
        DllCall("SelectObject", "ptr", hdc, "ptr", hOld, "ptr")
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    if (w < 10) {
        w := 10, h := 10
    }
    return { w: w, h: h }
}

HideOSD(*) {
    global OSD_GUI
    if OSD_GUI
        OSD_GUI.Hide()
}

; 把窗口不透明度逐步推向 target；tok 用于让旧动画自动失效（避免连按时闪烁）
; 淡入淡出：时间轴驱动 + ease-out cubic（起步快、收尾稳），进出场时长不同
FadeOSDTo(target, tok, hideAtEnd := false, durationMs := 190, dropPx := 0) {
    global OSD_GUI, OSD_FADE_TOKEN
    global FADE_FROM, FADE_TARGET, FADE_START, FADE_DUR, FADE_TOK, FADE_HIDE
    global FADE_X, FADE_Y_FROM, FADE_Y_TO
    if (!OSD_GUI || tok != OSD_FADE_TOKEN)
        return
    cur := 255
    try cur := WinGetTransparent(OSD_GUI.Hwnd)
    if (cur = "")
        cur := 255
    FADE_FROM := cur
    FADE_TARGET := target
    FADE_START := A_TickCount
    FADE_DUR := Max(durationMs, 1)
    FADE_TOK := tok
    FADE_HIDE := hideAtEnd
    if (dropPx != 0) {
        ; 退场：从当前位置再往下沉一点，和入场方向相反
        try {
            WinGetPos(&wx, &wy, , , OSD_GUI.Hwnd)
            FADE_X := wx
            FADE_X_FROM := wx
            FADE_Y_FROM := wy
            FADE_Y_TO := wy + dropPx
        }
    }
    FadeStep()
}

FadeStep() {
    global OSD_GUI, OSD_ACC, OSD_FADE_TOKEN
    global FADE_FROM, FADE_TARGET, FADE_START, FADE_DUR, FADE_TOK, FADE_HIDE
    global FADE_X, FADE_X_FROM, FADE_Y_FROM, FADE_Y_TO, FADE_BAR_X, FADE_BAR_W, FADE_BAR_H, FADE_WIN_H
    if (!OSD_GUI || FADE_TOK != OSD_FADE_TOKEN)
        return
    p := (A_TickCount - FADE_START) / FADE_DUR
    if (p > 1)
        p := 1
    e := 1 - (1 - p) ** 3
    a := Round(FADE_FROM + (FADE_TARGET - FADE_FROM) * e)
    ; 位移与透明度共用一条 ease-out 曲线，收尾同时停住
    yNow := Round(FADE_Y_FROM + (FADE_Y_TO - FADE_Y_FROM) * e)
    xNow := Round(FADE_X_FROM + (FADE_X - FADE_X_FROM) * e)
    try WinSetTransparent(a, OSD_GUI.Hwnd)
    try OSD_GUI.Move(xNow, yNow)
    if (FADE_BAR_H > 0 && OSD_ACC) {
        bh := Round(FADE_BAR_H * e)
        if (bh < 4)
            bh := 4
        try OSD_ACC.Move(FADE_BAR_X, (FADE_WIN_H - bh) // 2, FADE_BAR_W, bh)
    }
    if (p < 1) {
        SetTimer(FadeStep, -10)
    } else if (FADE_HIDE) {
        OSD_GUI.Hide()
    }
}

FadeOutOSD(tok) {
    global OSD_FADE_TOKEN
    if (tok != OSD_FADE_TOKEN)
        return
    global OSD_GUI
    OSD_GUI.Hide()
}

ApplyRoundCorners(hwnd, w, h, r) {
    if (w <= 0 || h <= 0)
        return
    try {
        hRgn := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", w + 1, "int", h + 1
                        , "int", r, "int", r, "ptr")
        if hRgn
            DllCall("SetWindowRgn", "ptr", hwnd, "ptr", hRgn, "int", true)
    }
}

MonitorIndexAtPoint(px, py) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (px >= l && px < r && py >= t && py < b)
            return A_Index
    }
    return MonitorGetPrimary()
}

GetDpiAtMouse() {
    MouseGetPos(&mx, &my)
    try {
        hMon := DllCall("MonitorFromPoint", "int64", (mx & 0xFFFFFFFF) | (my << 32), "uint", 2, "ptr")
        if !hMon
            return A_ScreenDPI
        dpiX := 96, dpiY := 96
        hr := DllCall("Shcore\GetDpiForMonitor", "ptr", hMon, "int", 0, "uint*", &dpiX, "uint*", &dpiY, "int")
        if (hr = 0 && dpiX >= 48)
            return dpiX
    }
    return A_ScreenDPI
}

; ---------------------------------------------------------------------------
; 9. GCC 风扇模式联动（GIGABYTE Control Center）
;    前提：本程序以管理员身份运行（GCC 是提权进程，UIPI 会挡住普通权限的 UIA 访问）
;    约束：不唤起、不最小化窗口；GCC 不在/最小化/卡死时直接跳过
; ---------------------------------------------------------------------------
FanAidFor(mode) {
    switch StrLower(Trim(mode, " `t")) {
        case "quiet", "silent", "静音":
            return "QuietModeToggleButton"
        case "performance", "normal", "正常", "性能":
            return "PerformanceModeToggleButton"
        case "fullspeed", "full", "max", "全速":
            return "FullSpeedModeToggleButton"
        case "custom", "manual", "手动":
            return "CustomModeToggleButton"
    }
    return ""
}

; 返回空串表示可以尝试切换；否则返回跳过原因
GccFanSkipReason() {
    global CFG
    if !CFG.FanModeSync
        return "disabled"
    if !A_IsAdmin
        return "not_admin"          ; 不提权读不到 GCC 的控件树

    h := WinExist("GIGABYTE CONTROL CENTER")
    if !h {
        ; WinExist 默认忽略隐藏窗口，这里再查一次以区分「没运行」和「收进托盘」
        DetectHiddenWindows true
        h := WinExist("GIGABYTE CONTROL CENTER")
        DetectHiddenWindows false
        if !h
            return "gcc_off"
        return "gcc_hidden"         ; 进程在，窗口隐藏了（托盘）
    }
    if !DllCall("IsWindowVisible", "ptr", h, "int")
        return "gcc_hidden"
    if DllCall("IsIconic", "ptr", h, "int")
        return "gcc_minimized"      ; 不主动还原窗口

    res := 0
    ok := DllCall("SendMessageTimeout", "ptr", h, "uint", 0, "ptr", 0, "ptr", 0
                  , "uint", 0x2, "uint", 150, "ptr*", &res, "ptr")
    if (!ok)
        return "gcc_hung"
    return ""
}

ApplyGccFanMode(mode, label, *) {
    reason := GccFanSkipReason()
    if (reason != "") {
        Log("风扇联动跳过：[" . label . " -> " . mode . "] 原因=" . reason)
        FanTipOnce(reason)
        return
    }
    aid := FanAidFor(mode)
    if (aid = "") {
        LogErr("风扇联动：无法识别的 FanMode=" . mode)
        return
    }
    h := WinExist("GIGABYTE CONTROL CENTER")
    try {
        root := UIA.ElementFromHandle(h)
        if !root {
            LogErr("风扇联动：拿不到 GCC 根元素")
            return
        }

        el := 0
        try el := root.FindElement({ AutomationId: aid })

        ; 风扇页是懒加载的：GCC 停在别的页面时，这四个按钮根本不存在
        if !el {
            nav := 0
            try nav := root.FindElement({ Name: "FAN Control" })
            if nav {
                try nav.Invoke()
                catch
                    try nav.TogglePattern.Toggle()
                Sleep 1500
                Log("风扇联调：已切到 GCC 风扇页")
            }
            try el := root.FindElement({ AutomationId: aid })
        }
        if !el {
            LogErr("风扇联动：找不到控件 " . aid . "（GCC 可能改了界面）")
            return
        }

        ; 先读状态：已经是目标模式就不动
        st := ""
        try st := el.ToggleState
        if (st = 1) {
            Log("风扇已是 " . mode . "，无需点击")
            return
        }

        ; ------------------------------------------------------------------
        ; 触发方式的选择（踩过三个坑，别改回去）：
        ;   el.ToggleState := 1        只改 WPF 依赖属性，GCC 逻辑不执行
        ;   el.TogglePattern.Toggle()  也只改 IsChecked，界面变了风扇不动
        ;   el.InvokePattern.Invoke()  这几个按钮接口是坏的（Invalid IUnknown）
        ;   el.LegacyIAccessible.DoDefaultAction()  调用成功但无效果
        ; 唯一有效：把焦点给按钮再发空格——走完整的 ButtonBase.OnClick 链路。
        ; ------------------------------------------------------------------
        prevFg := WinExist("A")

        ; 前台是全屏程序（游戏/播放器）时绝不抢焦点，否则会打断游戏
        if (prevFg && prevFg != h) {
            try {
                WinGetPos &fx, &fy, &fw, &fh, "ahk_id " . prevFg
                if (fw >= A_ScreenWidth && fh >= A_ScreenHeight) {
                    Log("风扇联动跳过：[ " . label . " ] 原因=前台全屏程序，不抢焦点")
                    return
                }
            }
        }

        try el.SetFocus()
        catch as e {
            LogErr("风扇联动：SetFocus 失败 " . e.Message)
            return
        }
        Sleep 140

        ; 焦点没切过去就千万别发按键，否则空格会漏到用户正在用的窗口里
        if (WinExist("A") != h) {
            Log("风扇联动跳过：焦点没能切到 GCC（可能被系统拒绝）")
            if (prevFg)
                try WinActivate "ahk_id " . prevFg
            return
        }

        Send "{Space}"

        ; 立刻把焦点还回去，减少打扰
        if (prevFg && prevFg != h)
            try WinActivate "ahk_id " . prevFg

        ; GCC 的风扇动作是异步的，轮询等状态真的落定
        ok := false
        waited := 0
        Loop 40 {                      ; 最多等 8 秒
            Sleep 200
            waited += 200
            s := ""
            try s := el.ToggleState
            if (s = 1) {
                ok := true
                break
            }
        }

        if ok {
            Sleep 400
            Log("风扇模式 -> " . mode . "（" . aid . "）状态确认耗时 " . waited . " ms")
        } else {
            LogErr("风扇联动：等待 " . waited . " ms 后仍未切到 " . mode)
        }
    } catch as e {
        LogErr("风扇联动失败：" . e.Message)
    }
}

FanTipOnce(reason) {
    global FAN_TIP_SHOWN
    if FAN_TIP_SHOWN
        return
    FAN_TIP_SHOWN := true
    msg := ""
    if (reason = "not_admin")
        msg := "风扇没跟着切：本程序不是管理员权限。托盘菜单可启用「免 UAC 提权启动」。"
    else if (reason = "gcc_off")
        msg := "风扇没跟着切：GCC 没在运行。"
    else if (reason = "gcc_hidden")
        msg := "风扇没跟着切：GCC 收在托盘里了。把它的窗口打开（不用置顶）才能联动。"
    else if (reason = "gcc_minimized")
        msg := "风扇没跟着切：GCC 最小化了。恢复窗口（不用置顶）才能联动。"
    if (msg != "")
        Notify(msg)
}

; ---------------------------------------------------------------------------
; 9b. 免 UAC 提权启动（计划任务，最高权限，登录时静默运行）
;     目的：GCC 是提权进程，只有本程序也提权，UIA 才读得到它的界面。
; ---------------------------------------------------------------------------
ElevatedTaskExists() {
    global ELEVATED_TASK
    q := Chr(34)
    try {
        rc := RunWait(A_ComSpec . " /c schtasks.exe /query /tn " . q . ELEVATED_TASK . q
                      . " >nul 2>&1", SCRIPT_DIR, "Hide")
        return (rc = 0)
    } catch as e {
        LogErr("查询计划任务失败：" . e.Message)
        return false
    }
}

EnableElevatedAutostart(*) {
    global ELEVATED_TASK, SCRIPT_DIR
    q := Chr(34)
    tr := q . A_AhkPath . q . " " . q . A_ScriptFullPath . q
    args := "/create /tn " . q . ELEVATED_TASK . q . " /tr " . q . tr . q
          . " /sc onlogon /rl highest /f"
    try {
        rc := RunWait("*RunAs " . A_ComSpec . " /c schtasks.exe " . args, SCRIPT_DIR, "Hide")
    } catch as e {
        LogErr("创建提权计划任务失败：" . e.Message)
        Notify("创建失败（可能取消了 UAC）：" . e.Message, true)
        return
    }
    if (rc = 0) {
        Log("已创建提权计划任务：" . ELEVATED_TASK)
        ELEVATED_TASK_OK := 1
        ; 计划任务和启动文件夹快捷方式会重复启动，删掉后者
        link := A_Startup . "\" . APP_NAME . ".lnk"
        if FileExist(link) {
            try FileDelete link
            Log("已移除启动文件夹快捷方式，改由计划任务启动")
        }
        Notify("已启用：下次登录起，本程序将以管理员身份静默启动，不再弹 UAC。")
    } else {
        LogErr("schtasks 返回 " . rc . "（多半是取消了 UAC）")
        ELEVATED_TASK_OK := -1
        Notify("没有创建成功（可能取消了 UAC 授权）。风扇联动仍可用，但每次需手动以管理员身份运行。", true)
    }
    BuildTrayMenu()
}

DisableElevatedAutostart(*) {
    global ELEVATED_TASK, SCRIPT_DIR
    q := Chr(34)
    try {
        rc := RunWait("*RunAs " . A_ComSpec . "/c schtasks.exe /delete /tn "
                      . q . ELEVATED_TASK . q . " /f", SCRIPT_DIR, "Hide")
        if (rc = 0) {
            Log("已删除提权计划任务")
            ELEVATED_TASK_OK := 0
            Notify("已取消免 UAC 提权启动。")
        }
    }
    BuildTrayMenu()
}

; 演示三档 OSD 动效（--demo-osd）：各显示一次，然后退出
DemoOSD() {
    global MODES, CFG
    Loop 6 {
        i := Mod(A_Index - 1, MODES.Length) + 1
        m := MODES[i]
        ShowOSD(ModeLabel(i), m.name . OverlaySubtitleSuffix(), ModeAccentHex(i), (i . " / " . MODES.Length))
        Sleep(1200)
    }
    ExitApp()
}

; ---------------------------------------------------------------------------
; 10. 自检（--selftest，不创建托盘/OSD，结果写入 logs\selftest.txt）
; ---------------------------------------------------------------------------
SelfTest() {
    global CFG, MODES

    L := []
    L.Push("=== PowerModeSwitcher 自检 " . FormatTime(, "yyyy-MM-dd HH:mm:ss") . " ===")
    L.Push("AHK版本 = " . A_AhkVersion . " | 64位 = " . (A_PtrSize = 8 ? "是" : "否") . " | 已编译 = " . (A_IsCompiled ? "是" : "否"))
    L.Push("脚本目录 = " . SCRIPT_DIR)
    L.Push("配置文件 = " . CONFIG_PATH . "（" . (FileExist(CONFIG_PATH) ? "存在" : "缺失") . "）")
    L.Push("[General] 热键=" . CFG.Hotkey . " 时长=" . CFG.OSDDuration . "ms 透明度=" . CFG.OSDOpacity
           . " 字号=" . CFG.OSDFontSize . " 底部留白=" . CFG.OSDBottomMargin
           . " 自启=" . CFG.StartWithWindows . " 左键切换=" . CFG.TrayLeftClick)
    for i, m in MODES {
        L.Push("Mode" . i . " = " . m.name . " · " . m.planName . " | guid=" . m.guid . " | native=" . m.nativeGuid
               . " | icon=" . m.icon . "（" . (FileExist(SCRIPT_DIR . "\" . m.icon) ? "存在" : "缺失") . "）")
    }

    L.Push("--- 系统电源计划 ---")
    L.Push("当前激活 = " . GetActivePlanGuid())
    set := ListPlanGuids()
    keys := []
    for k, v in set
        keys.Push(k)
    L.Push("powercfg /list 可见 GUID 数 = " . set.Count)
    L.Push("  " . JoinArray(keys, " "))
    for i, m in MODES
        L.Push("Mode" . i . " 在 /list 中 = " . (set.Has(m.guid) ? "是" : "否"))

    L.Push("--- 显示器 / DPI ---")
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &monL, &monT, &monR, &monB)
        MonitorGetWorkArea(A_Index, &wkL, &wkT, &wkR, &wkB)
        L.Push("显示器" . A_Index . " 全屏=" . monL . "," . monT . "," . monR . "," . monB
               . " 工作区=" . wkL . "," . wkT . "," . wkR . "," . wkB)
    }
    MouseGetPos(&mx, &my)
    L.Push("鼠标 = " . mx . "," . my . " | 所在显示器 = " . MonitorIndexAtPoint(mx, my)
           . " | 该显示器 DPI = " . GetDpiAtMouse() . " | A_ScreenDPI = " . A_ScreenDPI)

    L.Push("--- OSD ---")
    InitOSD()
    ShowOSD("游戏", "高性能 · 滑块 原值", ModeAccentHex(2), "2 / 3")
    OSD_GUI.GetPos(&ox, &oy, &ow, &oh)
    L.Push("OSD 窗口尺寸 = " . ow . "x" . oh . " | 左上角 = " . ox . "," . oy)
    L.Push("OSD 窗口标题 = " . OSD_TITLE . " | 存在 = " . (WinExist(OSD_TITLE) ? "是" : "否"))
    try {
        ex := WinGetExStyle(OSD_TITLE)
        L.Push("OSD 扩展样式 = 0x" . Format("{:X}", ex) . "（需含 0x80000 LAYERED / 0x20 TRANSPARENT / 0x8000000 NOACTIVATE）")
    } catch as e {
        L.Push("OSD 扩展样式读取失败：" . e.Message)
    }
    OSD_GUI.Hide()

    L.Push("--- 复制 / 重命名 / 删除 往返测试 ---")
    tpl := MODES[2].nativeGuid
    newG := DuplicateScheme(tpl)
    if (newG = "") {
        L.Push("duplicatescheme 失败（该模式下不可用）")
    } else {
        L.Push("duplicatescheme 成功 -> " . newG)
        okName := RenameScheme(newG, "PMSTest-副本")
        L.Push("changename = " . (okName ? "成功" : "失败"))
        L.Push("新计划出现在 /list = " . (ListPlanGuids().Has(newG) ? "是" : "否"))
        r := RunPowerCfg("-delete " . newG)
        L.Push("删除测试计划 exit = " . r.code)
        L.Push("删除后仍在 /list = " . (ListPlanGuids().Has(newG) ? "是" : "否"))
    }

    L.Push("--- 配置文件尾部校验 ---")
    if FileExist(CONFIG_PATH) {
        t2 := FileRead(CONFIG_PATH, "UTF-8")
        L.Push("config.ini 字数 = " . StrLen(t2) . " | 含“日常” = " . (InStr(t2, "日常") ? "是" : "否"))
    }

    if !DirExist(LOG_DIR)
        DirCreate(LOG_DIR)
    WriteAllText(LOG_DIR . "\selftest.txt", JoinArray(L, "`r`n") . "`r`n")
    ExitApp
}
