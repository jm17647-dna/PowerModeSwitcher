# -*- coding: utf-8 -*-
"""实测三个卖点数字：按下到切换生效的耗时、常驻内存、进程数。"""
import ctypes
import ctypes.wintypes as wt
import subprocess
import time
from ctypes import POINTER, byref, c_void_p

PROJ = r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher"
AHK = PROJ + r"\AutoHotkey64.exe"
SCRIPT = PROJ + r"\PowerModeSwitcher.ahk"

user32 = ctypes.WinDLL("user32")
powrprof = ctypes.WinDLL("powrprof")
GUID = ctypes.c_byte * 16


def active_guid():
    p = POINTER(GUID)()
    if powrprof.PowerGetActiveScheme(None, byref(p)) != 0:
        return ""
    b = bytes(bytearray(p.contents))
    d1 = int.from_bytes(b[0:4], "little")
    d2 = int.from_bytes(b[4:6], "little")
    d3 = int.from_bytes(b[6:8], "little")
    rest = "".join(f"{x:02x}" for x in b[8:10])
    tail = "".join(f"{x:02x}" for x in b[10:16])
    return f"{d1:08x}-{d2:04x}-{d3:04x}-{rest}-{tail}"


def alt_q():
    user32.keybd_event(0x12, 0, 0, 0)
    user32.keybd_event(0x51, 0, 0, 0)
    user32.keybd_event(0x51, 0, 2, 0)
    user32.keybd_event(0x12, 0, 2, 0)


subprocess.run(["powercfg", "/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e"])
time.sleep(0.4)
proc = subprocess.Popen([AHK, SCRIPT])
time.sleep(2.5)

ws = subprocess.run(["powershell", "-NoProfile", "-Command",
                     f"(Get-Process -Id {proc.pid}).WorkingSet64"],
                    capture_output=True, text=True).stdout.strip()
priv = subprocess.run(["powershell", "-NoProfile", "-Command",
                       f"(Get-Process -Id {proc.pid}).PrivateMemorySize64"],
                      capture_output=True, text=True).stdout.strip()
print(f"WorkingSet = {int(ws)/1048576:.1f} MB")
print(f"PrivateMemory = {int(priv)/1048576:.1f} MB")

samples = []
for _ in range(6):
    before = active_guid()
    t0 = time.perf_counter()
    alt_q()
    while True:
        if active_guid() != before:
            break
        if time.perf_counter() - t0 > 3:
            break
        time.sleep(0.002)      # 别把 CPU 打满，否则会拖慢被测进程
    samples.append((time.perf_counter() - t0) * 1000)
    time.sleep(1.1)

samples_sorted = sorted(samples)
print("切换耗时 ms:", ", ".join(f"{s:.1f}" for s in samples))
print(f"中位数 {samples_sorted[len(samples)//2]:.1f} ms | 最小 {min(samples):.1f} | 最大 {max(samples):.1f}")

subprocess.run(["taskkill", "/IM", "AutoHotkey64.exe", "/F"], capture_output=True)
subprocess.run(["powercfg", "/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e"])
print("done")
