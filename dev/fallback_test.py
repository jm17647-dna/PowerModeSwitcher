# -*- coding: utf-8 -*-
"""验证 3 条硬要求：原生回退 + 配置写回 + 不可用模式跳过；顺带抓托盘右键菜单截图。"""
import ctypes
import ctypes.wintypes as wt
import re
import shutil
import subprocess
import time
from pathlib import Path

from PIL import ImageGrab

PROJ = Path(r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher")
AHK = PROJ / "AutoHotkey64.exe"
SCRIPT = PROJ / "PowerModeSwitcher.ahk"
CFG = PROJ / "config.ini"
BAK = PROJ / "dev" / "config.bak.ini"
SHOTS = PROJ / "dev" / "shots"
BOGUS = "00000000-0000-0000-0000-000000000001"
NATIVE_HP = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
NATIVE_SAVER = "a1841308-3541-4fab-bc81-f71556f20b4a"

user32 = ctypes.WinDLL("user32", use_last_error=True)
user32.GetWindowTextW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]


def plan():
    out = subprocess.run(["powercfg", "/getactivescheme"], capture_output=True,
                         text=True, encoding="gbk", errors="replace").stdout
    m = re.search(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})", out, re.I)
    return m.group(1).lower() if m else "?"


def alt_q():
    user32.keybd_event(0x12, 0, 0, 0)
    user32.keybd_event(0x51, 0, 0, 0)
    user32.keybd_event(0x51, 0, 2, 0)
    user32.keybd_event(0x12, 0, 2, 0)


def set_cfg(section, key, value):
    text = CFG.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")
    lines = text.split("\n")
    cur = None
    for i, ln in enumerate(lines):
        s = ln.strip()
        if s.startswith("[") and s.endswith("]"):
            cur = s[1:-1]
        elif cur == section and s.split("=")[0].strip() == key and "=" in s:
            lines[i] = f"{key}={value}"
    CFG.write_text("\r\n".join(lines), encoding="utf-8")


def get_cfg(section, key):
    text = CFG.read_text(encoding="utf-8", errors="replace")
    cur = None
    for ln in text.splitlines():
        s = ln.strip()
        if s.startswith("[") and s.endswith("]"):
            cur = s[1:-1]
        elif cur == section and s.split("=")[0].strip() == key and "=" in s:
            return s.split("=", 1)[1].strip()
    return None


def main_hwnd():
    hits = []

    def cb(h, _):
        buf = ctypes.create_unicode_buffer(512)
        user32.GetWindowTextW(h, buf, 512)
        cls = ctypes.create_unicode_buffer(256)
        user32.GetClassNameW(h, cls, 256)
        if cls.value == "AutoHotkey" and "PowerModeSwitcher.ahk" in buf.value:
            hits.append(h)
        return True

    user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)(cb), 0)
    return hits[0] if hits else 0


def kill():
    subprocess.run(["taskkill", "/IM", "AutoHotkey64.exe", "/F"], capture_output=True)
    time.sleep(0.4)


lines = []
def log(s):
    print(s)
    lines.append(s)


shutil.copy2(CFG, BAK)
try:
    # ---------- 场景 A：配置里是无效 GUID，但原生 GUID 有效 ----------
    log("=== A：PowerPlanGuid 无效 -> 应回退原生并写回配置 ===")
    set_cfg("Mode2", "PowerPlanGuid", BOGUS)
    log(f"改动前 Mode2/PowerPlanGuid = {get_cfg('Mode2', 'PowerPlanGuid')}")
    subprocess.run(["powercfg", "/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e"])
    time.sleep(0.3)
    subprocess.Popen([str(AHK), str(SCRIPT)])
    time.sleep(2.2)
    alt_q()
    time.sleep(1.0)
    p = plan()
    log(f"切换后实际计划 = {p} | 期望 {NATIVE_HP} | {'OK' if p == NATIVE_HP else 'FAIL'}")
    log(f"切换后 Mode2/PowerPlanGuid = {get_cfg('Mode2', 'PowerPlanGuid')} | 期望被写回原生 GUID")
    kill()

    # ---------- 场景 B：三个模式里“静音”彻底不可用 ----------
    log("")
    log("=== B：静音模式 GUID 全部无效 -> 应跳过而不是冒充 ===")
    set_cfg("Mode3", "PowerPlanGuid", BOGUS)
    set_cfg("Mode3", "NativeGuid", BOGUS)
    subprocess.run(["powercfg", "/setactive", NATIVE_HP])
    time.sleep(0.3)
    subprocess.Popen([str(AHK), str(SCRIPT)])
    time.sleep(2.2)
    alt_q()          # 游戏 -> 下一个是静音（不可用）-> 应跳到 日常
    time.sleep(1.0)
    p = plan()
    log(f"从“游戏”按一次 Alt+Q 后 = {p} | 期望 381b4222（跳到日常，而非节能）| {'OK' if p.lower().startswith('381b4222') else 'FAIL'}")
    log("--- 日志尾部 ---")
    loglines = sorted((PROJ / "logs").glob("*.log"))
    if loglines:
        tail = loglines[-1].read_text(encoding="utf-8", errors="replace").splitlines()[-8:]
        for t in tail:
            log("  " + t)
    kill()

    # ---------- 场景 C：托盘右键菜单 ----------
    log("")
    log("=== C：托盘右键菜单 ===")
    shutil.copy2(BAK, CFG)
    subprocess.Popen([str(AHK), str(SCRIPT)])
    time.sleep(2.2)
    h = main_hwnd()
    log(f"主窗口 = {h}")
    if h:
        user32.SetCursorPos(1800, 100)
        user32.PostMessageW(h, 0x404, 1, 0x205)      # WM_RBUTTONUP
        time.sleep(0.8)
        img = ImageGrab.grab()
        img.save(SHOTS / "tray_menu_full.png")
        # 菜单通常在鼠标附近弹出，取左侧中部一块
        img.crop((1150, 0, 2100, 700)).save(SHOTS / "tray_menu.png")
        log("已抓取托盘菜单截图")
        user32.keybd_event(0x1B, 0, 0, 0)            # ESC 关闭菜单
        user32.keybd_event(0x1B, 0, 2, 0)
    kill()
finally:
    shutil.copy2(BAK, CFG)
    subprocess.run(["powercfg", "/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e"])
    log("")
    log("config.ini 已还原，电源计划已还原为平衡")

path = PROJ / "dev" / "fallback_report.txt"
path.write_text("\n".join(lines), encoding="utf-8")
print("report ->", path)
