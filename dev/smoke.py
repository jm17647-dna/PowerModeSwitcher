# -*- coding: utf-8 -*-
"""交付形态冒烟测试：完全走 start.cmd 启动，验证托盘、热键、OSD、自启快捷方式。"""
import ctypes
import ctypes.wintypes as wt
import re
import subprocess
import time
from pathlib import Path

from PIL import Image, ImageGrab

PROJ = Path(r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher")
SHOTS = PROJ / "dev" / "shots"
LNK = Path(r"C:\Users\Mjh10\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\PowerModeSwitcher.lnk")

user32 = ctypes.WinDLL("user32", use_last_error=True)
user32.GetWindowTextW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)


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


def osd_rect():
    res = []

    def cb(h, _):
        buf = ctypes.create_unicode_buffer(512)
        user32.GetWindowTextW(h, buf, 512)
        if buf.value.startswith("PowerModeOSD") and user32.IsWindowVisible(h):
            r = wt.RECT()
            user32.GetWindowRect(h, ctypes.byref(r))
            res.append((r.left, r.top, r.right, r.bottom))
        return True

    user32.EnumWindows(EnumWindowsProc(cb), 0)
    return res[0] if res else None


if LNK.exists():
    LNK.unlink()
subprocess.run(["powercfg", "/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e"])
time.sleep(0.3)

subprocess.Popen(["cmd", "/c", str(PROJ / "start.cmd")])
time.sleep(2.8)

print("AutoHotkey64 进程数 =", subprocess.run(
    ["powershell", "-NoProfile", "-Command",
     "(Get-Process AutoHotkey64 -ErrorAction SilentlyContinue | Measure-Object).Count"],
    capture_output=True, text=True).stdout.strip())
print("启动后计划未变 =", plan() == "381b4222-f694-41f0-9685-ff5bb260df2e")
print("自启快捷方式已创建 =", LNK.exists())

alt_q()
rect, t0 = None, time.time()
while time.time() - t0 < 2.0:
    rect = osd_rect()
    if rect:
        break
    time.sleep(0.015)
print("切换后计划 =", plan(), "| OSD 出现 =", bool(rect), "| rect =", rect)
if rect:
    img = ImageGrab.grab()
    box = (int(rect[0] * 1.5) - 30, int(rect[1] * 1.5) - 30,
           int(rect[2] * 1.5) + 30, int(rect[3] * 1.5) + 30)
    img.crop(box).save(SHOTS / "smoke_osd.png")

time.sleep(0.6)
subprocess.run(["taskkill", "/IM", "AutoHotkey64.exe", "/F"], capture_output=True)
subprocess.run(["powercfg", "/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e"])
print("smoke done")
