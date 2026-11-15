# -*- coding: utf-8 -*-
"""验证配置写回：只改目标行，其余字节保持不变（二进制读写，避免换行转换干扰）。"""
import ctypes
import shutil
import subprocess
import time
from pathlib import Path

PROJ = Path(r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher")
AHK = PROJ / "AutoHotkey64.exe"
SCRIPT = PROJ / "PowerModeSwitcher.ahk"
CFG = PROJ / "config.ini"
BEFORE = PROJ / "dev" / "cfg_before.ini"
CLEAN = PROJ / "dev" / "cfg_clean_crlf.ini"

user32 = ctypes.WinDLL("user32")
BOGUS = "00000000-0000-0000-0000-000000000001"


def rb(p):
    return p.read_bytes().decode("utf-8-sig")


def wb(p, s):
    p.write_bytes(s.encode("utf-8"))


def norm(s):
    return s.replace("\r\n", "\n").replace("\r", "\n")


def set_cfg(sec, key, val):
    lines = norm(rb(CFG)).split("\n")
    cur = None
    for i, ln in enumerate(lines):
        s = ln.strip()
        if s.startswith("[") and s.endswith("]"):
            cur = s[1:-1]
        elif cur == sec and s.split("=")[0].strip() == key and "=" in s:
            lines[i] = f"{key}={val}"
    wb(CFG, "\r\n".join(lines))


def alt_q():
    user32.keybd_event(0x12, 0, 0, 0)
    user32.keybd_event(0x51, 0, 0, 0)
    user32.keybd_event(0x51, 0, 2, 0)
    user32.keybd_event(0x12, 0, 2, 0)


# 归一：UTF-8 无 BOM + CRLF
wb(CFG, "\r\n".join(norm(rb(CFG)).split("\n")))
CLEAN.write_bytes(CFG.read_bytes())
set_cfg("Mode2", "PowerPlanGuid", BOGUS)
BEFORE.write_bytes(CFG.read_bytes())
print("改前行数 =", len(rb(CFG).splitlines()), "| 前3行 =", rb(CFG).splitlines()[:3])

subprocess.run(["powercfg", "/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e"])
time.sleep(0.3)
subprocess.Popen([str(AHK), str(SCRIPT)])
time.sleep(2.2)
alt_q()
time.sleep(1.2)
subprocess.run(["taskkill", "/IM", "AutoHotkey64.exe", "/F"], capture_output=True)

a = rb(BEFORE).splitlines()
b = rb(CFG).splitlines()
print(f"行数：改前 {len(a)} / 改后 {len(b)}")
diff = [(i + 1, x, y) for i, (x, y) in enumerate(zip(a, b)) if x != y]
print(f"差异行数 = {len(diff)}（期望 1）")
for i, x, y in diff:
    print(f"  第{i}行：{x!r} -> {y!r}")
raw = CFG.read_bytes()
print("是否有 BOM =", raw.startswith(b"\xef\xbb\xbf"), "| 是否只有单 CR =", b"\r\r" not in raw)
print("写回后前 6 行 =", rb(CFG).splitlines()[:6])

# 还原
CFG.write_bytes(CLEAN.read_bytes())
set_cfg("Mode2", "PowerPlanGuid", "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c")
subprocess.run(["powercfg", "/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e"])
print("已还原 config.ini")
