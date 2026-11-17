@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "OUT=%~dp0logs\诊断.txt"
if not exist "%~dp0logs" mkdir "%~dp0logs"
> "%OUT%" echo [PowerModeSwitcher 诊断] %date% %time%
>>"%OUT%" echo 目录: %~dp0

>>"%OUT%" echo.
>>"%OUT%" echo == 1. 文件是否存在 ==
for %%F in (AutoHotkey64.exe PowerModeSwitcher.ahk config.ini icon_balanced.ico) do (
    if exist "%~dp0%%F" (>>"%OUT%" echo   有  %%F) else (>>"%OUT%" echo   缺  %%F)
)

>>"%OUT%" echo.
>>"%OUT%" echo == 2. 启动前是否已有实例 ==
tasklist /fi "imagename eq AutoHotkey64.exe" /fo csv /nh > "%~dp0logs\_tl1.txt" 2>nul
find /i "AutoHotkey64" "%~dp0logs\_tl1.txt" >nul
if errorlevel 1 (>>"%OUT%" echo   没有在跑) else (>>"%OUT%" echo   已有实例在跑)

>>"%OUT%" echo.
>>"%OUT%" echo == 3. 尝试启动，等 6 秒 ==
start "" "%~dp0AutoHotkey64.exe" /ErrorStdOut "%~dp0PowerModeSwitcher.ahk" 1> "%~dp0logs\_stdout.txt" 2> "%~dp0logs\_stderr.txt"
timeout /t 6 /nobreak >nul
tasklist /fi "imagename eq AutoHotkey64.exe" /fo csv /nh > "%~dp0logs\_tl2.txt" 2>nul
find /i "AutoHotkey64" "%~dp0logs\_tl2.txt" >nul
if errorlevel 1 (>>"%OUT%" echo   6 秒后：进程不存在 = 启动失败) else (>>"%OUT%" echo   6 秒后：进程存在 = 启动成功)
>>"%OUT%" echo   -- 该进程的窗口标题 --
>>"%OUT%" echo   -- stderr --
type "%~dp0logs\_stderr.txt" >>"%OUT%" 2>nul
>>"%OUT%" echo   -- stdout --
type "%~dp0logs\_stdout.txt" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo == 4. config.ini 关键项 ==
findstr /i /c:"Hotkey" /c:"OSD_OnStart" /c:"TrayIcon" /c:"OverlaySync" "%~dp0config.ini" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo == 5. 本次启动日志（最后 10 行） ==
powershell -NoProfile -Command "Get-Content '%~dp0logs\2026-11-17.log' -Tail 10 -ErrorAction SilentlyContinue" >>"%OUT%" 2>nul

>>"%OUT%" echo.
>>"%OUT%" echo == 6. 开机启动项 ==
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" 2>nul | find /i "PowerMode" >>"%OUT%" 2>nul
if errorlevel 1 >>"%OUT%" echo   Run 键里没有本程序
if exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\PowerModeSwitcher.lnk" (
    >>"%OUT%" echo   启动文件夹：有快捷方式
) else (
    >>"%OUT%" echo   启动文件夹：无快捷方式
)

>>"%OUT%" echo.
>>"%OUT%" echo == 7. 环境 ==
>>"%OUT%" echo   用户: %USERNAME%
ver >>"%OUT%" 2>nul
>>"%OUT%" echo 诊断结束
del "%~dp0logs\_tl1.txt" "%~dp0logs\_tl2.txt" >nul 2>&1
echo.
echo 诊断完成，结果写在：%OUT%
timeout /t 10 /nobreak >nul
exit /b 0