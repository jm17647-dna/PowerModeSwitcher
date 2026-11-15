<#
.SYNOPSIS
    PowerModeSwitcher 一键安装（绿色部署，内置 AutoHotkey v2 运行时）。

.EXAMPLE
    # 默认装到 %LOCALAPPDATA%\PowerModeSwitcher 并立刻启动
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
    # 只装不启动、不注册自启
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -NoLaunch -NoStartup

.EXAMPLE
    # GitHub 慢的话走镜像
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Mirror 'https://ghproxy.net/'
#>
[CmdletBinding()]
param(
    [string]$Dir = (Join-Path $env:LOCALAPPDATA 'PowerModeSwitcher'),
    [switch]$NoLaunch,
    [switch]$NoStartup,
    [string]$Mirror = '',
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

Say "== PowerModeSwitcher 安装 ==" 'Cyan'
Say "目标目录: $Dir"

$tmp = Join-Path $env:TEMP ('pms_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp, $Dir | Out-Null

try {
    # ---------- 1. AutoHotkey v2 运行时 ----------
    $ahkExe = $null
    foreach ($p in @(
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey.exe",
        "${env:ProgramFiles(x86)}\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")) {
        if (Test-Path $p) { $ahkExe = $p; break }
    }

    if ($ahkExe) {
        Say "[1/4] 本机已装 AutoHotkey v2，复用: $ahkExe" 'Green'
    } else {
        Say "[1/4] 下载 AutoHotkey v2 便携版 ..."
        $ahkZip = Join-Path $tmp 'ahk-v2.zip'
        Invoke-WebRequest 'https://www.autohotkey.com/download/ahk-v2.zip' -OutFile $ahkZip -UseBasicParsing
        Expand-Archive $ahkZip -DestinationPath (Join-Path $tmp 'ahk') -Force
        $exe = Get-ChildItem (Join-Path $tmp 'ahk') -Recurse -Filter 'AutoHotkey64.exe' | Select-Object -First 1
        if (-not $exe) { throw 'AHK 便携包里没找到 AutoHotkey64.exe' }
        $ahkExe = Join-Path $Dir 'AutoHotkey64.exe'
        Copy-Item $exe.FullName $ahkExe -Force
        Say "      运行时 -> $ahkExe"
    }

    # ---------- 2. 程序本体 ----------
    Say "[2/4] 下载程序文件 ..."
    $repoZip = Join-Path $tmp 'repo.zip'
    $repoUrl = "$($Mirror)https://github.com/jm17647-dna/PowerModeSwitcher/archive/refs/heads/$Branch.zip"
    Invoke-WebRequest $repoUrl -OutFile $repoZip -UseBasicParsing
    Expand-Archive $repoZip -DestinationPath (Join-Path $tmp 'repo') -Force
    $src = Get-ChildItem (Join-Path $tmp 'repo') -Directory | Select-Object -First 1
    if (-not $src) { throw '仓库压缩包解压失败' }

    foreach ($name in @('PowerModeSwitcher.ahk', 'config.ini', 'README.md', 'LICENSE')) {
        $f = Join-Path $src.FullName $name
        if (Test-Path $f) { Copy-Item $f $Dir -Force }
    }
    Get-ChildItem $src.FullName -Filter '*.ico' | ForEach-Object { Copy-Item $_.FullName $Dir -Force }

    # ---------- 3. 去锁定 + 配置 ----------
    Say "[3/4] 处理文件锁定与配置 ..."
    Get-ChildItem $Dir -File | ForEach-Object { try { Unblock-File $_.FullName } catch {} }

    $cfg = Join-Path $Dir 'config.ini'
    if ($NoStartup -and (Test-Path $cfg)) {
        $text = Get-Content $cfg -Raw -Encoding UTF8
        $text = $text -replace '(?m)^StartWithWindows=1', 'StartWithWindows=0'
        Set-Content $cfg -Value $text -Encoding UTF8 -NoNewline
        Say '      已关闭开机自启（-NoStartup）'
    }

    $missing = @()
    foreach ($need in @('PowerModeSwitcher.ahk', 'config.ini', 'icon_balanced.ico',
                        'icon_performance.ico', 'icon_powersave.ico')) {
        if (-not (Test-Path (Join-Path $Dir $need))) { $missing += $need }
    }
    if ($missing) { throw "缺少文件: $($missing -join ', ')" }
    if (-not (Test-Path (Join-Path $Dir 'AutoHotkey64.exe')) -and -not $ahkExe) { throw '运行时缺失' }

    # ---------- 4. 启动 ----------
    if ($NoLaunch) {
        Say "[4/4] 已跳过启动（-NoLaunch）" 'Yellow'
    } else {
        Say "[4/4] 启动 ..."
        $runner = if (Test-Path (Join-Path $Dir 'AutoHotkey64.exe')) { Join-Path $Dir 'AutoHotkey64.exe' } else { $ahkExe }
        Start-Process -FilePath $runner -ArgumentList "`"$(Join-Path $Dir 'PowerModeSwitcher.ahk')`"" -WorkingDirectory $Dir
        Start-Sleep -Seconds 2
        $proc = Get-Process AutoHotkey64 -ErrorAction SilentlyContinue
        if ($proc) { Say "      已在托盘运行（PID $($proc.Id -join ', ')）" 'Green' }
        else { Say '      进程没起来，请手动双击 PowerModeSwitcher.ahk 看报错' 'Red' }
    }

    Say ''
    Say '安装完成。' 'Cyan'
    Say "  目录    : $Dir"
    Say "  热键    : Alt+Q（改 config.ini 的 Hotkey=，改完重启程序）"
    Say "  退出    : 右键托盘图标 -> 退出"
    Say "  自启    : 首次启动会自动写入 shell:startup，可在托盘菜单关掉"
    Say "  日志    : $Dir\logs"
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
