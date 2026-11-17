# 把安装这件事交给 Agent

三种写法，按 Agent 的能力挑一种。

---

## 一、一句话版（丢给 WorkBuddy / Claude Code / Cursor / Copilot 都行）

```
帮我装 PowerModeSwitcher，一个 Windows 电源模式一键切换工具。步骤：
1. 下载 https://github.com/jm17647-dna/PowerModeSwitcher/archive/refs/heads/main.zip 并解压
2. 把解压出来的 PowerModeSwitcher-main 目录里的文件复制到 %LOCALAPPDATA%\PowerModeSwitcher
3. 下载 https://www.autohotkey.com/download/ahk-v2.zip，解压后把 AutoHotkey64.exe 复制到同一目录
4. 用该目录下的 AutoHotkey64.exe 启动 PowerModeSwitcher.ahk
5. 确认进程名 AutoHotkey64 有且只有一个，然后把 %LOCALAPPDATA%\PowerModeSwitcher\logs 下最新日志的最后两行发给我
```

Agent 有 PowerShell 权限的话，跑完大约 40 秒。

---

## 二、命令版（Agent 直接执行；你自己在 PowerShell 里粘也行）

```powershell
$d = "$env:LOCALAPPDATA\PowerModeSwitcher"
$t = "$env:TEMP\pms_setup"
New-Item -ItemType Directory -Force -Path $d, $t | Out-Null

Invoke-WebRequest 'https://github.com/jm17647-dna/PowerModeSwitcher/archive/refs/heads/main.zip' -OutFile "$t\repo.zip" -UseBasicParsing
Expand-Archive "$t\repo.zip" "$t\repo" -Force
Copy-Item "$t\repo\PowerModeSwitcher-main\*" $d -Recurse -Force

Invoke-WebRequest 'https://www.autohotkey.com/download/ahk-v2.zip' -OutFile "$t\ahk.zip" -UseBasicParsing
Expand-Archive "$t\ahk.zip" "$t\ahk" -Force
Copy-Item (Get-ChildItem "$t\ahk" -Recurse -Filter AutoHotkey64.exe | Select-Object -First 1).FullName $d -Force

Get-ChildItem $d -File | ForEach-Object { Unblock-File $_.FullName }
Start-Process "$d\AutoHotkey64.exe" -ArgumentList "`"$d\PowerModeSwitcher.ahk`"" -WorkingDirectory $d
Start-Sleep 3
Get-Process AutoHotkey64 | Select-Object Id, WorkingSet64
Get-Content (Get-ChildItem "$d\logs\*.log" | Sort-Object LastWriteTime | Select-Object -Last 1) -Tail 2
```

---

## 三、脚本版（仓库里已有 `install.ps1`，带参数）

```powershell
$s = "$env:TEMP\pms-install.ps1"
Invoke-WebRequest 'https://github.com/jm17647-dna/PowerModeSwitcher/raw/main/install.ps1' -OutFile $s -UseBasicParsing
powershell -NoProfile -ExecutionPolicy Bypass -File $s
```

参数：

| 参数 | 作用 |
| :--- | :--- |
| `-Dir <路径>` | 装到指定目录，默认 `%LOCALAPPDATA%\PowerModeSwitcher` |
| `-NoLaunch` | 只装不启动 |
| `-NoStartup` | 不注册开机自启（把 config.ini 的 StartWithWindows 改 0） |
| `-Mirror 'https://ghproxy.net/'` | GitHub 慢时挂镜像前缀 |

---

## 装完让 Agent 自检这几条

1. `%LOCALAPPDATA%\PowerModeSwitcher` 下有 6 个文件：`PowerModeSwitcher.ahk`、`config.ini`、`AutoHotkey64.exe`、三个 `.ico`
2. 进程列表里 `AutoHotkey64` 只有 1 个（单实例设计）
3. `logs\当天.log` 里有 `热键已注册：Alt+Q` 和 `启动完成`
4. 按 `Alt+Q` 一次，`powercfg /getactivescheme` 的 GUID 变了
5. 屏幕底部闪出一条 0.9 秒的提示

一条命令跑完自检：

```powershell
powercfg /getactivescheme
Get-Content "$env:LOCALAPPDATA\PowerModeSwitcher\logs\$(Get-Date -Format yyyy-MM-dd).log" -Tail 3
```

---

## 排错

| 现象 | 原因 / 处理 |
| :--- | :--- |
| `raw.githubusercontent.com` 超时 | 国内常见。改用上面的 **命令版**（走 `github.com/.../archive` 和 `codeload.github.com`，通常可通），或给 install.ps1 加 `-Mirror` |
| `无法加载文件，因为在此系统上禁止运行脚本` | 执行策略。用 `powershell -NoProfile -ExecutionPolicy Bypass -File xxx.ps1`，别直接双击 |
| 脚本里中文变乱码、报"意外的标记" | PowerShell 5.1 按 ANSI 读无 BOM 的 UTF-8。仓库里那份**带 BOM**，下载后别用编辑器另存 |
| SmartScreen / 杀软拦截 AutoHotkey64.exe | AHK 运行时未签名，官方原版也会被误报。加白名单，或改用本机已装的 AHK v2 |
| 装完按 Alt+Q 没反应 | 看日志有没有"热键已注册"。没有就是键位冲突，改 `config.ini` 的 `Hotkey=` |
| 想卸载 | 托盘右键退出 → 删掉 `%LOCALAPPDATA%\PowerModeSwitcher` → 删掉启动文件夹里的 `PowerModeSwitcher.lnk` |

---

## 为什么不用 `irm ... | iex`

`Invoke-RestMethod` 拿回来的是字符串，管道给 `iex` 会丢掉 BOM、也拿不到 `$PSScriptRoot`，中文脚本大概率炸。老老实实下载成文件再 `-File` 执行，或者直接用上面的命令版。
