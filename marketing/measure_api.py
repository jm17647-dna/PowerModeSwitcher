# -*- coding: utf-8 -*-
"""隔离测试：只测 Windows 自己，PowerSetActiveScheme 调用耗时 vs 生效耗时。"""
import ctypes
import time
from ctypes import POINTER, byref

powrprof = ctypes.WinDLL("powrprof")
GUID = ctypes.c_byte * 16
PLANS = ["381b4222-f694-41f0-9685-ff5bb260df2e",
         "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c",
         "a1841308-3541-4fab-bc81-f71556f20b4a"]


def to_guid(s):
    p = s.split("-")
    g = GUID()
    d1 = int(p[0], 16).to_bytes(4, "little")
    d2 = int(p[1], 16).to_bytes(2, "little")
    d3 = int(p[2], 16).to_bytes(2, "little")
    raw = d1 + d2 + d3 + bytes.fromhex(p[3] + p[4])
    for i, b in enumerate(raw):
        g[i] = b - 256 if b > 127 else b
    return g


def current():
    p = POINTER(GUID)()
    if powrprof.PowerGetActiveScheme(None, byref(p)) != 0:
        return ""
    b = bytes(bytearray(p.contents))
    ctypes.windll.kernel32.LocalFree(p)
    d1 = int.from_bytes(b[0:4], "little")
    d2 = int.from_bytes(b[4:6], "little")
    d3 = int.from_bytes(b[6:8], "little")
    return f"{d1:08x}-{d2:04x}-{d3:04x}-{b[8:10].hex()}-{b[10:16].hex()}"


print("起始:", current())
for i in range(6):
    target = PLANS[(i + 1) % 3]
    g = to_guid(target)
    t0 = time.perf_counter()
    rc = powrprof.PowerSetActiveScheme(None, byref(g))
    t1 = time.perf_counter()
    while current() != target and time.perf_counter() - t1 < 3:
        time.sleep(0.002)
    t2 = time.perf_counter()
    print(f"{i+1}: rc={rc} 调用={1000*(t1-t0):6.2f}ms 生效={1000*(t2-t1):7.2f}ms -> {target[:8]}")

ctypes.windll.powrprof.PowerSetActiveScheme(None, byref(to_guid(PLANS[0])))
print("已还原")
