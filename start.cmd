@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

if not exist "%~dp0AutoHotkey64.exe" (
    echo [错误] 找不到 AutoHotkey64.exe，请确认整个文件夹是完整的。
    pause
    exit /b 1
)
if not exist "%~dp0PowerModeSwitcher.ahk" (
    echo [错误] 找不到 PowerModeSwitcher.ahk。
    pause
    exit /b 1
)

echo 正在启动 PowerModeSwitcher ...
start "" "%~dp0AutoHotkey64.exe" "%~dp0PowerModeSwitcher.ahk"

rem 等它起来，确认进程在，再提示怎么看效果
timeout /t 2 /nobreak >nul
tasklist /fi "imagename eq AutoHotkey64.exe" 2>nul | find /i "AutoHotkey64.exe" >nul
if errorlevel 1 (
    echo [提示] 进程没起来。日志在：%~dp0logs
    pause
    exit /b 1
)

echo.
echo 已启动。它没有主窗口，只在右下角托盘区（^ 里）有个小图标。
echo   - 按 Alt+Q 切换三档
echo   - 左下角会弹出一个彩色小卡片，那就是效果
echo   - 托盘图标可以左键切换、右键打开菜单
echo.
timeout /t 6 /nobreak >nul
exit /b 0