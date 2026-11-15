# -*- coding: utf-8 -*-
"""验证快捷键被占用：应托盘提示 + 保留托盘单击切换可用。"""
import ctypes
import ctypes.wintypes as wt
import re
import subprocess
import time
from pathlib import Path

PROJ = Path(r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher")
AHK = PROJ / "AutoHotkey64.exe"
SCRIPT = PROJ / "PowerModeSwitcher.ahk"
HOG = PROJ / "dev" / "hotkey_hog.ahk"
LOG = PROJ / "logs"

HOG.write_text('#Requires AutoHotkey v2.0\nHotkey("!q", (*) => 0)\nPersistent()\n', encoding="utf-8")

user32 = ctypes.WinDLL("user32")


def plan():
    out = subprocess.run(["powercfg", "/getactivescheme"], capture_output=True,
                         text=True, encoding="gbk", errors="replace").stdout
    m = re.search(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})", out, re.I)
    return m.group(1).lower() if m else "?"


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


logfile = sorted(LOG.glob("*.log"))[-1]
before = logfile.read_text(encoding="utf-8", errors="replace").count("\n")

subprocess.run(["powercfg", "/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e"])
hog = subprocess.Popen([str(AHK), str(HOG)])
time.sleep(1.5)
app = subprocess.Popen([str(AHK), str(SCRIPT)])
time.sleep(2.5)

new = logfile.read_text(encoding="utf-8", errors="replace").splitlines()[before:]
print("新增日志：")
for ln in new:
    print("  " + ln)

h = main_hwnd()
print("主窗口 =", h)
if h:
    b = plan()
    user32.PostMessageW(h, 0x404, 1, 0x202)
    time.sleep(0.8)
    a = plan()
    print(f"热键被占用时托盘单击：{b[:8]} -> {a[:8]} | {'OK 仍可切换' if b != a else 'FAIL'}")

subprocess.run(["taskkill", "/IM", "AutoHotkey64.exe", "/F"], capture_output=True)
HOG.unlink(missing_ok=True)
subprocess.run(["powercfg", "/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e"])
print("done")
