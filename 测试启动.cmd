@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo 正在做启动自检：如果能看到一个"启动自检"对话框，说明程序本身没问题。
echo.
"%~dp0AutoHotkey64.exe" "%~dp0PowerModeSwitcher.ahk" --test
echo.
echo 上面没有弹出对话框的话，把这句话告诉我。
timeout /t 12 /nobreak >nul
exit /b 0