# -*- coding: utf-8 -*-
"""打包整理：内置运行时、start.cmd、README 编码、清理临时文件。"""
import shutil
from pathlib import Path

PROJ = Path(r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher")
DEV = PROJ / "dev"

# 1. 内置运行时
shutil.copy2(DEV / "ahk" / "AutoHotkey64.exe", PROJ / "AutoHotkey64.exe")
print("runtime ->", (PROJ / "AutoHotkey64.exe").stat().st_size, "bytes")

# 2. start.cmd（纯 ASCII + CRLF）
bat = (
    "@echo off\r\n"
    "rem PowerModeSwitcher launcher\r\n"
    'start "" "%~dp0AutoHotkey64.exe" "%~dp0PowerModeSwitcher.ahk"\r\n'
)
(PROJ / "start.cmd").write_bytes(bat.encode("ascii"))
print("start.cmd written")

# 3. README.txt：UTF-8 BOM + CRLF（老记事本/部分编辑器友好）
rd = PROJ / "README.txt"
text = rd.read_bytes().decode("utf-8-sig").replace("\r\n", "\n")
rd.write_bytes(b"\xef\xbb\xbf" + text.replace("\n", "\r\n").encode("utf-8"))
print("README.txt: BOM + CRLF ->", rd.stat().st_size, "bytes")

# 4. dev 脚本里的运行时路径改指向根目录
for py in DEV.glob("*.py"):
    s = py.read_text(encoding="utf-8")
    if 'dev" / "ahk" / "AutoHotkey64.exe"' in s:
        s = s.replace('PROJ / "AutoHotkey64.exe"', 'PROJ / "AutoHotkey64.exe"')
        py.write_text(s, encoding="utf-8")
        print("path fixed:", py.name)

# 5. 清理临时文件
junk = [
    "ahk-v2.zip", "probe.py", "mkver.py", "ver.ahk", "ver_out.txt", "t2.ahk", "t2.txt",
    "enc.ahk", "enc.txt", "enc2.ahk", "enc2.txt", "enc3.ahk", "enc3.txt", "config_bom.ini",
    "hk.ahk", "hk.txt", "st.ahk", "static.txt", "split.ahk", "split.txt",
    "validate.ps1", "run_ahk.py", "shot.png", "shot_crop.png", "ahkver.txt", "pip.txt",
    "pm_enc.ahk", "pm_enc.txt", "probe_run.py",
]
for name in junk:
    p = DEV / name
    if p.exists():
        p.unlink()
        print("removed", name)

shutil.rmtree(DEV / "ahk", ignore_errors=True)
print("dev/ahk removed:", not (DEV / "ahk").exists())

print("\n=== 最终目录 ===")
for p in sorted(PROJ.iterdir()):
    kind = "DIR " if p.is_dir() else "FILE"
    size = "" if p.is_dir() else f"{p.stat().st_size:>9,d}"
    print(f"  {kind} {size}  {p.name}")
