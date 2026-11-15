# -*- coding: utf-8 -*-
"""PowerModeSwitcher 运行时验收脚本。

做四件事：
1) 启动程序，模拟真实 Alt+Q 按键，逐次截图 OSD，并用 powercfg 核对系统实际计划；
2) 模拟托盘图标左键单击（PostMessage 0x404 / WM_LBUTTONUP），验证循环切换；
3) 验证单实例；
4) 结束后还原原始电源计划并结束进程。
"""
import ctypes
import ctypes.wintypes as wintypes
import subprocess
import sys
import time
from pathlib import Path

from PIL import ImageGrab

PROJ = Path(r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher")
AHK = PROJ / "AutoHotkey64.exe"
SCRIPT = PROJ / "PowerModeSwitcher.ahk"
SHOTS = PROJ / "dev" / "shots"
SHOTS.mkdir(parents=True, exist_ok=True)
REPORT = PROJ / "dev" / "runtime_report.txt"

user32 = ctypes.WinDLL("user32", use_last_error=True)

VK_MENU, VK_Q = 0x12, 0x51
KEYEVENTF_KEYUP = 0x0002


def active_plan() -> str:
    out = subprocess.run(
        ["powercfg", "/getactivescheme"],
        capture_output=True, text=True, encoding="gbk", errors="replace",
    ).stdout
    import re
    m = re.search(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})", out, re.I)
    return m.group(1).lower() if m else "?"


def send_alt_q():
    user32.keybd_event(VK_MENU, 0, 0, 0)
    time.sleep(0.03)
    user32.keybd_event(VK_Q, 0, 0, 0)
    time.sleep(0.03)
    user32.keybd_event(VK_Q, 0, KEYEVENTF_KEYUP, 0)
    time.sleep(0.03)
    user32.keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0)


def grab(name: str):
    img = ImageGrab.grab()
    p = SHOTS / name
    img.save(p)
    # 同时裁出底部中央区域便于肉眼核对
    img.crop((1400, 1800, 2440, 2010)).save(SHOTS / (name.replace(".png", "_crop.png")))
    return p


def find_window(title: str):
    """AHK 主窗口标题形如 'D:\\...\\PowerModeSwitcher.ahk - AutoHotkey v2.0.31'，
    用枚举 + 类名/标题包含关系查找，避开同名错误对话框。"""
    hits = []

    def cb(h, _):
        buf = ctypes.create_unicode_buffer(512)
        user32.GetWindowTextW(h, buf, 512)
        cls = ctypes.create_unicode_buffer(256)
        user32.GetClassNameW(h, cls, 256)
        if cls.value == "AutoHotkey" and title in buf.value:
            hits.append(h)
        return True

    user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)(cb), 0)
    return hits[0] if hits else 0


def post_tray_click(hwnd):
    """模拟托盘图标左键单击：0x404 消息 + lParam=WM_LBUTTONUP"""
    user32.PostMessageW(hwnd, 0x404, 1, 0x202)


def osd_windows():
    """返回当前可见的 OSD 窗口列表（用于验证不叠层 / 到时隐藏）。"""
    res = []

    def cb(h, _):
        buf = ctypes.create_unicode_buffer(512)
        user32.GetWindowTextW(h, buf, 512)
        if buf.value.startswith("PowerModeOSD") and user32.IsWindowVisible(h):
            res.append(h)
        return True

    user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)(cb), 0)
    return res


def main():
    lines = []
    def log(s):
        print(s)
        lines.append(s)

    original = active_plan()
    log(f"原始电源计划 = {original}")

    proc = subprocess.Popen([str(AHK), str(SCRIPT)])
    time.sleep(2.0)
    log(f"启动后进程存活 = {proc.poll() is None}")
    log(f"启动后系统计划 = {active_plan()}（应等于原始计划，启动不得切换）")
    grab("00_start.png")

    # 热键循环四次：以“系统实际计划”为起点推算期望值
    order = ["381b4222-f694-41f0-9685-ff5bb260df2e",
             "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c",
             "a1841308-3541-4fab-bc81-f71556f20b4a"]
    for i in range(1, 5):
        cur = active_plan()
        base = order.index(cur) if cur in order else 0
        exp = order[(base + 1) % 3]
        send_alt_q()
        time.sleep(0.28)
        shot = grab(f"{i:02d}_altq_{i}.png")
        got = active_plan()
        ok = "OK" if got == exp else "MISMATCH"
        log(f"第{i}次 Alt+Q：{cur[:8]} -> {got[:8]} | 期望 {exp[:8]} | {ok} | {shot.name}")
        time.sleep(0.9)   # 等 OSD 消失，避免叠层

    # 连续快速按三次，验证 OSD 不残留
    log("--- 连按三次（快速）---")
    for _ in range(3):
        send_alt_q()
        time.sleep(0.12)
    time.sleep(0.25)
    grab("05_burst.png")
    log(f"连按后可见 OSD 窗口数 = {len(osd_windows())}（期望 1，不叠层）")
    time.sleep(1.2)
    grab("06_burst_after.png")
    log(f"1.2s 后可见 OSD 窗口数 = {len(osd_windows())}（期望 0，已自动隐藏）")

    # 托盘左键
    hwnd = find_window("PowerModeSwitcher.ahk")
    log(f"主窗口句柄 = {hwnd}")
    if hwnd:
        before = active_plan()
        post_tray_click(hwnd)
        time.sleep(0.35)
        grab("07_tray_click.png")
        after = active_plan()
        log(f"托盘左键：{before} -> {after} | {'OK 已切换' if before != after else '未切换'}")
        # 是否弹出了菜单（类名 #32768）
        menu = user32.FindWindowW("#32768", None)
        log(f"左键后是否出现托盘菜单窗口 = {'是（未吞掉左键消息）' if menu else '否（点击穿透菜单，符合预期）'}")
    else:
        log("找不到主窗口，跳过托盘测试")

    # 单实例
    log("--- 单实例 ---")
    p2 = subprocess.Popen([str(AHK), str(SCRIPT)])
    time.sleep(1.8)
    cnt = subprocess.run(
        ["powershell", "-NoProfile", "-Command",
         "(Get-Process AutoHotkey64 -ErrorAction SilentlyContinue).Count"],
        capture_output=True, text=True).stdout.strip()
    log(f"再次启动后 AutoHotkey64 进程数 = {cnt}（期望 1）")
    log(f"原进程仍存活 = {proc.poll() is None} | 第二次进程已退出 = {p2.poll() is not None}")

    # 还原
    subprocess.run(["powercfg", "/setactive", original])
    time.sleep(0.3)
    log(f"已还原原始计划 = {active_plan()}")

    for p in subprocess.run(["powershell", "-NoProfile", "-Command",
                             "Get-Process AutoHotkey64 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id"],
                            capture_output=True, text=True).stdout.split():
        subprocess.run(["taskkill", "/PID", p, "/F"], capture_output=True)
    log("已结束测试进程")

    REPORT.write_text("\n".join(lines), encoding="utf-8")
    print("\nreport ->", REPORT)


if __name__ == "__main__":
    main()
