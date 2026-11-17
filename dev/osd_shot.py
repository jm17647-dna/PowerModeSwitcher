# -*- coding: utf-8 -*-
"""三档 OSD 取证：每次切换后轮询到 OSD 可见再截图，输出 3 张紧裁剪。"""
import ctypes
import ctypes.wintypes as wt
import subprocess
import time
from pathlib import Path

from PIL import Image, ImageGrab

PROJ = Path(r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher")
AHK = PROJ / "AutoHotkey64.exe"
SCRIPT = PROJ / "PowerModeSwitcher.ahk"
OUT = PROJ / "dev" / "shots"

user32 = ctypes.WinDLL("user32", use_last_error=True)
user32.GetWindowTextW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)


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


def alt_q():
    user32.keybd_event(0x12, 0, 0, 0)
    user32.keybd_event(0x51, 0, 0, 0)
    user32.keybd_event(0x51, 0, 2, 0)
    user32.keybd_event(0x12, 0, 2, 0)


subprocess.run(["powercfg", "/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e"])
time.sleep(0.4)
subprocess.Popen([str(AHK), str(SCRIPT)])
time.sleep(2.3)

tiles = []
for i in range(1, 4):
    alt_q()
    rect, t0 = None, time.time()
    while time.time() - t0 < 2.0:
        rect = osd_rect()
        if rect:
            break
        time.sleep(0.015)
    img = ImageGrab.grab()
    sc = 1.5  # 144 DPI
    box = (int(rect[0] * sc) - 30, int(rect[1] * sc) - 30,
           int(rect[2] * sc) + 30, int(rect[3] * sc) + 30)
    tile = img.crop(box)
    tile.save(OUT / f"osd_{i}.png")
    tiles.append(tile)
    print(f"第{i}次：rect={rect} -> osd_{i}.png")
    time.sleep(1.1)   # 等隐藏，避免叠层

if tiles:
    w = max(t.width for t in tiles)
    h = sum(t.height for t in tiles)
    sheet = Image.new("RGB", (w, h), (24, 24, 26))
    y = 0
    for t in tiles:
        sheet.paste(t, (0, y))
        y += t.height
    sheet.save(OUT / "osd_all.png")
    print("汇总 ->", OUT / "osd_all.png")

subprocess.run(["taskkill", "/IM", "AutoHotkey64.exe", "/F"], capture_output=True)
subprocess.run(["powercfg", "/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e"])
print("done")
