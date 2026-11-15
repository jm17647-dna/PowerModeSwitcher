# -*- coding: utf-8 -*-
"""截图工具：用于读取 AHK 语法错误对话框。"""
import sys
from PIL import ImageGrab

out = sys.argv[1] if len(sys.argv) > 1 else r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher\dev\shot.png"
img = ImageGrab.grab()
img.save(out)
print("saved", out, img.size)
