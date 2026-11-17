@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "OUT=%~dp0logs\切档测试.txt"
if not exist "%~dp0logs" mkdir "%~dp0logs"
> "%OUT%" echo [切档测试] %date% %time%
>>"%OUT%" echo 用户: %USERNAME%
>>"%OUT%" echo.
>>"%OUT%" echo -- 尝试切到「高性能」 --
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >>"%OUT%" 2>&1
>>"%OUT%" echo exit=%errorlevel%
>>"%OUT%" echo.
>>"%OUT%" echo -- 尝试切到「平衡」 --
powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e >>"%OUT%" 2>&1
>>"%OUT%" echo exit=%errorlevel%
>>"%OUT%" echo.
>>"%OUT%" echo -- 当前方案 --
powercfg /getactivescheme >>"%OUT%" 2>&1
echo 完成，结果在 logs\切档测试.txt
timeout /t 8 /nobreak >nul
exit /b 0