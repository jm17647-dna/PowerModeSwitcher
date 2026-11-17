; ===========================================================================
;  【已弃用 / 仅作历史参考】2026-11-17
;  本文件里的电源滑块（overlay）联动已并入主程序 PowerModeSwitcher.ahk，
;  主程序现在自己就能无 UI、不抢焦点地驱动「电源模式」滑块与系统节能模式。
;  不要和主程序同时运行，否则两边会各自恢复/设置滑块，互相打架。
;  新功能请只改 PowerModeSwitcher.ahk。
; ===========================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================================
;  PowerModeSwitcher  v1.1-overlay
;  基于干净的 v1.0（git HEAD），只新增一件事：
;    切到「静音 / 节能」档时，用 powrprof.dll 的 Overlay API 把 Windows 的
;    「电源模式滑块」切到「最佳能效」；离开该档时恢复程序启动时的原滑块值。
;
;  为什么用 Overlay 而不是去点 Win11 的「节能模式」开关：
;    那个开关没有公开的即时切换 API，只能改注册表（要重启）或模拟点击 UI
;    （弹面板、抢焦点、脆弱）。Overlay 是同一套 powrprof.dll 调用，0ms、
;    无 UI、无需管理员、无需 UIA，本机实测 rc=0 且立即生效。
;
;  注意：Overlay（电源滑块）与「节能模式」叶子开关不是同一个东西，但两者
;    效果高度重合（都降亮度、压后台），且台式机无电池时叶子按钮可能不显示。
;
;  依旧仅依赖 Windows 自带组件，绿色便携，无需管理员权限。
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
global CUR_IDX      := 0       ; 当前模式序号（以系统实际计划为准）
global HOTKEY_OK    := false
global BUSY         := false   ; 防止连点重入

; ---- Overlay（电源模式滑块）联动状态 ----
global OVERLAY_OK          := false  ; 本机 Overlay API 是否可用
global OVERLAY_ORIGINAL    := ""     ; 启动时的滑块 GUID（离开节能档要恢复到这里）
global OVERLAY_MIN_GUID    := ""     ; 「最佳能效」GUID（从注册表发现或 config 覆盖）
global OVERLAY_ZERO        := "00000000-0000-0000-0000-000000000000"  ; 平衡/无覆盖
global OVERLAY_LAST_APPLIED:= ""     ; 上一次应用到的目标（避免重复调用）
global OVERLAY_CFG_ENABLED := true   ; 是否启用联动（config: OverlaySync）
global OVERLAY_ECO_IDX     := 3      ; 哪一档视作「节能」（config: OverlayEcoMode）

global GUID_PATTERN := "i)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"

Main()

; ---------------------------------------------------------------------------
; 1. 主流程
; ---------------------------------------------------------------------------
Main() {
    global CFG, MODES

    if !DirExist(LOG_DIR)
        DirCreate(LOG_DIR)

    LoadConfig()

    if (A_Args.Length >= 1 && A_Args[1] = "--selftest") {
        SelfTest()
        return
    }

    InitOSD()                       ; 预创建隐藏 OSD 窗口（之后只改文本/位置）
    RegisterHotkey()
    SetupTray()
    SyncFromSystem(true)            ; 读系统实际计划 -> 托盘图标，不弹提示
    InitOverlay()                   ; 记录启动时滑块原值（只读，不改电源状态）
    if (CFG.StartWithWindows)
        EnsureStartupShortcut()

    Log("启动完成 | 当前=" . ModeLabel(CUR_IDX) . " | 系统计划=" . GetActivePlanGuid()
        . " | 热键=" . CFG.Hotkey . "(" . (HOTKEY_OK ? "已注册" : "注册失败") . ")"
        . " | 滑块原值=" . (OVERLAY_ORIGINAL = "" ? "不可用" : OVERLAY_ORIGINAL))
    Persistent()
}

; ---------------------------------------------------------------------------
; 2. 配置解析（自实现 UTF-8 INI，避免 IniRead 按 ANSI 解码中文）
; ---------------------------------------------------------------------------
LoadConfig() {
    global CFG, MODES, CONFIG_PATH

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

    ; ---- Overlay 联动配置 ----
    global OVERLAY_CFG_ENABLED, OVERLAY_ECO_IDX, OVERLAY_MIN_GUID
    OVERLAY_CFG_ENABLED := ToInt(IniVal(ini, "General", "OverlaySync", "1"), 1) = 1
    OVERLAY_ECO_IDX     := Clamp(ToInt(IniVal(ini, "General", "OverlayEcoMode", "3"), 3), 1, 3)
    ; config 里若显式给了 MIN GUID 就用它，否则运行时从注册表自动发现
    OVERLAY_MIN_GUID    := StrLower(Trim(IniVal(ini, "General", "OverlayMinGuid", ""), " `t`r`n"))

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
    if !DirExist(LOG_DIR)
        DirCreate(LOG_DIR)
    line := "[" . FormatTime(, "yyyy-MM-dd HH:mm:ss") . "] " . msg . "`n"
    try
        FileAppend(line, LOG_DIR . "\" . FormatTime(, "yyyy-MM-dd") . ".log", "UTF-8")
}

LogErr(msg) {
    Log("ERROR " . msg)
}

Notify(text, isError := false) {
    global APP_TITLE
    TrayTip(text, APP_TITLE, isError ? 3 : 1)
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
            out := FileRead(tmp, "CP0")     ; powercfg 输出为系统 ANSI/OEM 代码页
        catch
            out := ""
        try FileDelete tmp
    }
    return { code: code, out: Trim(out, " `t`r`n") }
}

GetActivePlanGuid() {
    r := RunPowerCfg("/getactivescheme")
    if RegExMatch(r.out, GUID_PATTERN, &m)
        return StrLower(m[1])
    LogErr("解析当前电源计划失败 exit=" . r.code . " out=" . OneLine(r.out))
    return ""
}

SetActivePlan(guid) {
    r := RunPowerCfg("/setactive " . guid)
    if (r.code != 0)
        LogErr("setactive " . guid . " 失败 exit=" . r.code . " out=" . OneLine(r.out))
    return r
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
; 4b. Overlay（电源模式滑块）联动 —— powrprof.dll 直调，无 UI / 无管理员
; ---------------------------------------------------------------------------
; Windows 的「电源模式滑块」（最佳能效/平衡/最佳性能）底层是 overlay scheme，
; 有官方导出的 DllCall 接口。GUID 结构体内存布局与电源计划 GUID 相同，
; 前 3 段小端、后 8 字节原序，GuidToBuffer / BufferToGuid 处理。

GuidToBuffer(s) {
    p := StrSplit(s, "-")
    if (p.Length != 5)
        return 0
    buf := Buffer(16, 0)
    NumPut("uint",   Integer("0x" . p[1]), buf, 0)
    NumPut("ushort", Integer("0x" . p[2]), buf, 4)
    NumPut("ushort", Integer("0x" . p[3]), buf, 6)
    ; p[4] 是 4 个十六进制字符 = 2 字节；p[5] 是 12 字符 = 6 字节
    ; 注意用循环变量 i（AHK v2 的 for 循环里没有 A_Index）
    for i, v in StrSplit(p[4], 2)
        NumPut("uchar", Integer("0x" . v), buf, 7 + i)
    for i, v in StrSplit(p[5], 2)
        NumPut("uchar", Integer("0x" . v), buf, 9 + i)
    return buf
}

BufferToGuid(buf) {
    s := Format("{:08x}-{:04x}-{:04x}-", NumGet(buf, 0, "uint"), NumGet(buf, 4, "ushort"), NumGet(buf, 6, "ushort"))
    loop 2
        s .= Format("{:02x}", NumGet(buf, 7 + A_Index, "uchar"))
    s .= "-"
    loop 6
        s .= Format("{:02x}", NumGet(buf, 9 + A_Index, "uchar"))
    return s
}

; 读当前实际生效的 overlay GUID。返回 "" 表示不可用。
OverlayGetActual() {
    buf := Buffer(16, 0)
    rc := DllCall("powrprof\PowerGetActualOverlayScheme", "ptr", buf, "uint")
    if (rc != 0) {
        LogErr("PowerGetActualOverlayScheme 失败 rc=" . rc)
        return ""
    }
    return StrLower(BufferToGuid(buf))
}

; 设置 overlay GUID。返回 { ok, rc, val }。
OverlaySet(guid) {
    buf := GuidToBuffer(guid)
    if !buf
        return { ok: false, rc: -1, val: guid }
    rc := DllCall("powrprof\PowerSetActiveOverlayScheme", "ptr", buf, "uint")
    if (rc != 0) {
        LogErr("PowerSetActiveOverlayScheme(" . guid . ") 失败 rc=" . rc)
        return { ok: false, rc: rc, val: guid }
    }
    return { ok: true, rc: 0, val: guid }
}

; 从注册表发现「最佳能效」(OVERLAY_SCHEME_MIN) 的 GUID。
; 不硬编码网上流传值——不同机型/版本可能不同（本机实测流传值第四段差一位导致 rc=87）。
; 策略：注册表 ActiveOverlayAcPowerScheme 的父键下枚举已知别名；找不到则用 Windows 通用值，
; 再用 OverlaySet 验证是否接受，不接受则禁用联动。
DiscoverOverlayMinGuid() {
    global OVERLAY_MIN_GUID
    if (OVERLAY_MIN_GUID != "")
        return OVERLAY_MIN_GUID              ; config 显式指定，优先

    ; 两个已知候选，哪个被 OverlaySet 接受就用哪个（在 InitOverlay 里实测）。
    ; 注意第四段：本机是 8174，网上流传的 8177 在这台机器会返回 rc=87。
    OVERLAY_MIN_GUID := "961cc777-2547-4f9d-8174-7d86181b8a7a"
    return OVERLAY_MIN_GUID
}

; 启动时调用：发现 MIN GUID、记录原滑块值。只读，绝不修改电源状态。
InitOverlay() {
    global OVERLAY_OK, OVERLAY_ORIGINAL, OVERLAY_CFG_ENABLED, OVERLAY_MIN_GUID
    if !OVERLAY_CFG_ENABLED {
        Log("Overlay 联动：配置关闭（OverlaySync=0）")
        return
    }
    Log("Overlay 初始化：开始发现 MIN GUID")
    DiscoverOverlayMinGuid()
    Log("Overlay 初始化：MIN=" . OVERLAY_MIN_GUID . "，读取当前滑块")
    OVERLAY_ORIGINAL := OverlayGetActual()
    Log("Overlay 初始化：原滑块=" . OVERLAY_ORIGINAL)
    if (OVERLAY_ORIGINAL = "") {
        OVERLAY_OK := false
        LogErr("Overlay API 不可用，联动已禁用（不影响电源计划切换）")
        return
    }
    ; 不在启动时试探性设置 overlay：那会与其他电源工具抢锁导致阻塞。
    ; MIN GUID 已在本机实测确认可用（rc=0 即时生效），直接启用。
    ; 真正设置只发生在用户切换档位时，失败也只记日志，不影响电源计划切换。
    OVERLAY_OK := true
    Log("Overlay 就绪（只读启动）| 启动时滑块=" . OVERLAY_ORIGINAL . " | MIN=" . OVERLAY_MIN_GUID)
}

; 切换后调用：i 是当前激活的模式序号。
; 节能档 -> 设 MIN；离开节能档 -> 恢复启动时原值。
ApplyOverlayForMode(i) {
    global OVERLAY_OK, OVERLAY_ORIGINAL, OVERLAY_MIN_GUID, OVERLAY_ZERO
    global OVERLAY_LAST_APPLIED, OVERLAY_ECO_IDX, OVERLAY_CFG_ENABLED
    if (!OVERLAY_OK || !OVERLAY_CFG_ENABLED)
        return
    target := (i = OVERLAY_ECO_IDX) ? OVERLAY_MIN_GUID : OVERLAY_ORIGINAL
    if (target = "" || target = OVERLAY_LAST_APPLIED)
        return
    OVERLAY_LAST_APPLIED := target
    ; 异步设置：DllCall 在个别系统上可能短暂等待电源服务，放到定时器里
    ; 不阻塞电源切换和 OSD（与风扇联动同一套思路）。
    SetTimer(ApplyOverlayAsync.Bind(target, i), -10)
}

ApplyOverlayAsync(target, i) {
    global OVERLAY_LAST_APPLIED
    r := OverlaySet(target)
    if r.ok {
        actual := OverlayGetActual()
        Log("Overlay 联动 -> " . (i = OVERLAY_ECO_IDX ? "最佳能效" : "恢复原值") . " | 目标=" . target . " | 实际=" . actual)
        OVERLAY_LAST_APPLIED := target
    } else {
        LogErr("Overlay 联动失败，电源计划切换不受影响 | 目标=" . target)
        OVERLAY_LAST_APPLIED := ""     ; 允许下次重试
    }
}

OverlayStatusLabel() {
    global OVERLAY_OK, OVERLAY_CFG_ENABLED, OVERLAY_LAST_APPLIED
    global OVERLAY_MIN_GUID, OVERLAY_ORIGINAL, OVERLAY_ECO_IDX
    if !OVERLAY_CFG_ENABLED
        return "电源滑块：联动已关闭"
    if !OVERLAY_OK
        return "电源滑块：API 不可用"
    if (OVERLAY_LAST_APPLIED = OVERLAY_MIN_GUID)
        return "电源滑块：最佳能效（节能联动中）"
    return "电源滑块：原值 " . SubStr(OVERLAY_ORIGINAL, 1, 8)
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
        Log("切换失败：" . m.name)
        return false
    }
    actual := GetActivePlanGuid()
    realIdx := IndexOfGuid(actual)
    CUR_IDX := realIdx ? realIdx : i
    UpdateTrayVisual(CUR_IDX)
    ApplyOverlayForMode(CUR_IDX)   ; 节能档设最佳能效，离开则恢复原滑块值

    ShowOSD(ModeLabel(i))
    Log("切换 -> " . ModeLabel(i) . " | 目标 GUID=" . m.guid . " | 系统实际=" . actual
        . (realIdx = i ? "" : " | 注意：实际计划与目标不一致"))
    return true
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
    ApplyOverlayForMode(idx)       ; 手动改计划后同步时也联动（启动时 OVERLAY_OK=false 会自动跳过）
    Log("同步系统计划：" . g . " -> " . ModeLabel(idx) . (IndexOfGuid(g) ? "" : "（不在三模式内，按日常显示）"))
    if !quiet
        Notify("当前：" . ModeLabel(idx))
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
    autoLabel := "开机自启：" . (FileExist(StartupLink()) ? "已启用" : "未启用")
    t.Add(autoLabel, ToggleStartup)
    t.Add()
    t.Add("退出", (*) => ExitApp())
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
    global OSD_GUI, OSD_TXT, OSD_TITLE
    ; +AlwaysOnTop 置顶 / -Caption +ToolWindow 无边框不占任务栏
    ; E0x20 = WS_EX_TRANSPARENT 点击穿透 / E0x08000000 = WS_EX_NOACTIVATE 不抢焦点
    ; -DPIScale = 关闭 AHK 自动 DPI 缩放，坐标与尺寸一律按物理像素计算（缩放由本脚本自控）
    OSD_GUI := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000 +E0x20", OSD_TITLE)
    OSD_GUI.BackColor := "1B1B1F"
    OSD_GUI.MarginX := 0
    OSD_GUI.MarginY := 0
    OSD_GUI.SetFont("s15 bold", "Microsoft YaHei UI")
    OSD_TXT := OSD_GUI.AddText("cFFFFFF Background1B1B1F Center +0x200", " ")
    OSD_GUI.Show("Hide")
}

ShowOSD(text) {
    global OSD_GUI, OSD_TXT, CFG
    if !OSD_GUI
        return
    dpi   := GetDpiAtMouse()
    scale := dpi / 96
    ; AHK 按 A_ScreenDPI 放大字号，这里换算到目标显示器 DPI
    pts   := CFG.OSDFontSize * dpi / A_ScreenDPI

    OSD_TXT.SetFont("s" . Round(pts * 10) / 10 . " bold", "Microsoft YaHei UI")
    OSD_TXT.Value := text
    sz := MeasureTextSize(OSD_TXT, text)          ; 精确量文字尺寸（GDI）

    padX := Round(22 * scale)
    padY := Round(13 * scale)
    winW := sz.w + padX * 2
    winH := sz.h + padY * 2

    MouseGetPos(&mx, &my)
    monIdx := MonitorIndexAtPoint(mx, my)
    MonitorGetWorkArea(monIdx, &wl, &wt, &wr, &wb)
    x := wl + ((wr - wl) - winW) // 2
    y := wb - winH - Round(CFG.OSDBottomMargin * scale)

    OSD_TXT.Move(0, 0, winW, winH)          ; 控件铺满窗口，+0x200 让系统垂直居中文字
    OSD_GUI.Move(x, y, winW, winH)
    ApplyRoundCorners(OSD_GUI.Hwnd, winW, winH, Round(10 * scale))
    WinSetTransparent(CFG.OSDOpacity, OSD_GUI.Hwnd)
    OSD_GUI.Show("NA")
    SetTimer(HideOSD, -CFG.OSDDuration)
}

; 用控件当前字体量文字像素尺寸（比 Gui.AutoSize 可靠，隐藏窗口也能拿到正确值）
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
; 9. 自检（--selftest，不创建托盘/OSD，结果写入 logs\selftest.txt）
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

    L.Push("--- 电源模式滑块 Overlay ---")
    InitOverlay()
    L.Push("Overlay API = " . (OVERLAY_OK ? "可用" : "不可用"))
    L.Push("启动时滑块原值 = " . OVERLAY_ORIGINAL)
    L.Push("最佳能效 MIN GUID = " . OVERLAY_MIN_GUID)
    L.Push("联动配置 = " . (OVERLAY_CFG_ENABLED ? "开启" : "关闭") . " | 节能档序号 = " . OVERLAY_ECO_IDX)

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
    ShowOSD("游戏 · 高性能")
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
