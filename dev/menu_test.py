# -*- coding: utf-8 -*-
"""托盘菜单视觉取证：用主脚本副本 + 定时弹菜单，截图后清理。"""
import ctypes
import subprocess
import time
from pathlib import Path

from PIL import ImageGrab

PROJ = Path(r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher")
AHK = PROJ / "AutoHotkey64.exe"
SRC = PROJ / "PowerModeSwitcher.ahk"
TMP = PROJ / "PowerModeSwitcher_menutest.ahk"
SHOTS = PROJ / "dev" / "shots"

user32 = ctypes.WinDLL("user32")

tail = '''

; === 仅用于截图取证：启动后 1.5 秒弹出托盘菜单 ===
SetTimer(ShowTrayMenuForShot, -1500)
ShowTrayMenuForShot() {
    A_TrayMenu.Show()
}
'''

code = SRC.read_text(encoding="utf-8")
TMP.write_text(code + tail, encoding="utf-8")

subprocess.run(["taskkill", "/IM", "AutoHotkey64.exe", "/F"], capture_output=True)
time.sleep(0.4)
user32.SetCursorPos(1500, 700)
subprocess.Popen([str(AHK), str(TMP)])
time.sleep(3.2)
img = ImageGrab.grab()
img.save(SHOTS / "menu_full.png")
img.crop((1400, 620, 2400, 1520)).save(SHOTS / "menu.png")
user32.keybd_event(0x1B, 0, 0, 0)
user32.keybd_event(0x1B, 0, 2, 0)
time.sleep(0.4)
subprocess.run(["taskkill", "/IM", "AutoHotkey64.exe", "/F"], capture_output=True)
TMP.unlink(missing_ok=True)
print("menu shot saved; temp script removed:", not TMP.exists())
