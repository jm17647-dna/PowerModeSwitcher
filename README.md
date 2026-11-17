# PowerModeSwitcher

> 一个不到 1000 行的 Windows 托盘小工具：按一次 `Alt+Q`，在 **日常 / 游戏 / 静音** 三档电源模式之间循环切换，屏幕底部闪一条 0.9 秒的提示。

<p>
  <img alt="platform" src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6?logo=windows&logoColor=white">
  <img alt="ahk" src="https://img.shields.io/badge/AutoHotkey-v2.0%2B-334455?logo=autohotkey&logoColor=white">
  <img alt="size" src="https://img.shields.io/badge/script-30%20KB-brightgreen">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="deps" src="https://img.shields.io/badge/dependencies-0-success">
</p>

`PowerModeSwitcher` 只做一件事：用 Windows 自带的 `powercfg` 切电源计划，给高频操作配一个键。

**它不做什么**：不碰风扇曲线、不调显卡功耗墙、不改进程优先级、不注入游戏。就是一个电源计划开关。

---

## 下载即用（推荐）

到 [Releases](https://github.com/jm17647-dna/PowerModeSwitcher/releases) 下载 `PowerModeSwitcher-portable-v1.1.0.zip`，解压到任意目录，双击 `启动.vbs` 即可，**不用装 AutoHotkey**（便携运行时已随包附带）。

解压后目录长这样：

```
PowerModeSwitcher/
├── 启动.vbs                  ← 双击这个
├── start.cmd                 ← 命令行版启动（可看报错）
├── PowerModeSwitcher.ahk     ← 主程序
├── config.ini                ← 配置（改热键、时长、图标都在这）
├── AutoHotkey64.exe          ← 便携运行时（GPLv2）
├── Lib\UIA.ahk               ← 风扇联动用的 UI 自动化库
├── icon_sets\G_filled\       ← 三档托盘图标
└── 第三方组件说明.txt          ← 运行时与图标的许可证来源
```

启动后托盘出现一个小图标（Win11 默认收进 `^` 溢出区，可拖出来常驻），按 `Alt+Q` 循环切换。

---

## 界面

一次切换会在鼠标所在屏幕的底部中央浮出一条提示（点击穿透、不抢焦点）：

![三档 OSD](docs/images/osd-three-modes.png)

托盘图标跟随实际电源计划变色，悬停显示当前模式：

![托盘图标与提示](docs/images/tray-icon-tooltip.png)

右键是控制面板：当前状态、快捷键状态、三档直选、以及几个维护项。

![托盘右键菜单](docs/images/tray-menu.png)

首次启动会自动注册开机自启，并给一条气泡确认：

![开机自启提示](docs/images/traytip-autostart.png)

---

## 功能

| 能力 | 说明 |
| :--- | :--- |
| 一键循环 | `Alt+Q`（可改）在 日常 → 游戏 → 静音 → 日常 之间轮转 |
| 托盘左键 | 单击图标即切换，不用键盘 |
| 状态不说谎 | 每次切换前用 `powercfg /getactivescheme` 回读系统实际状态，不信内部计数器；你在 Windows 设置里手动改过计划，下一次切换依然正确 |
| OSD 反馈 | 预创建窗口，切换时只改文本和位置；92% 不透明、圆角、同色系卡片、900 ms 自动消失、点击穿透、不抢焦点 |
| 多显示器 | OSD 出现在鼠标所在显示器的工作区底部居中，按该屏 DPI 缩放字号 |
| 隐藏计划自救 | Win11 把「高性能/节能」藏起来时，先试原生 GUID；失败则按**对应的原生模板**复制并重命名，把新 GUID 写回配置——绝不用「平衡」复制后改名冒充 |
| 单实例 | 重复启动只会替换旧实例，不会出现两个托盘图标 |
| 零依赖 | 只用 `powercfg.exe` 和系统 API，不装驱动、不联网 |
| 风扇联动 | 切电源档时同步切 GIGABYTE Control Center 的风扇模式（需管理员权限，见下） |
| 可诊断 | `logs/YYYY-MM-DD.log` 记录每次切换、退出码、`powercfg` 原始输出；`--selftest` 一键输出环境自检 |

---

## 快速开始

### 方式一：装了 AutoHotkey 的话

1. 安装 [AutoHotkey v2](https://www.autohotkey.com/)（装 v2，不是 v1）。
2. 下载本仓库，双击 `PowerModeSwitcher.ahk`。
3. 托盘出现图标即可用。

### 方式二：绿色便携包

把 `PowerModeSwitcher.ahk`、`config.ini`、三个 `.ico` 与官方 `AutoHotkey64.exe`（v2 便携版）放进同一个目录，双击 `start.cmd`。

> 本仓库不提交 AHK 运行时二进制（1.2 MB，GPLv2），请自行从官网下载，或用已安装的 v2 打开脚本。

### 默认对应关系

| 模式 | 电源计划 | 原生 GUID |
| :--- | :--- | :--- |
| 日常 | 平衡 | `381b4222-f694-41f0-9685-ff5bb260df2e` |
| 游戏 | 高性能 | `8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c` |
| 静音 | 节能 | `a1841308-3541-4fab-bc81-f71556f20b4a` |

循环方向固定为 **日常 → 游戏 → 静音 → 日常**。当前激活的计划不属于这三者时（比如主板厂商自建的计划），按「日常」对待。

---

## 使用

| 操作 | 效果 |
| :--- | :--- |
| `Alt+Q` | 切到下一档 |
| 左键单击托盘图标 | 同上 |
| 右键单击托盘图标 | 打开菜单 |
| 菜单 · 三个模式 | 直接跳到某一档，当前项带勾 |
| 菜单 · 重新读取当前电源计划 | 手动在系统设置改过之后，同步图标与状态 |
| 菜单 · 恢复原生电源计划 GUID | 把配置里被改写的 GUID 还原成 Windows 原生的，用于重测 |
| 菜单 · 开机自启 | 一键开关 `shell:startup` 快捷方式 |
| 菜单 · 打开配置文件 / 日志目录 | 直达 |

改完 `config.ini` 要重启程序才生效（托盘 → 退出 → 重新双击）。

---

## 配置

```ini
[General]
Hotkey=Alt+Q          ; 支持 Alt+Q 与 ^!q 两种写法
OSD_Duration=900      ; 停留毫秒
OSD_Opacity=191       ; 0-255，191 ≈ 75%
OSD_FontSize=15       ; 96 DPI 基准点数，按屏幕 DPI 自动缩放
OSD_BottomMargin=80   ; 距屏幕底部留白（96 DPI 基准像素）
StartWithWindows=1    ; 1 开 / 0 关
TrayLeftClick=1       ; 1 = 左键切换；0 = 左键弹菜单

[Mode1]
Name=日常              ; OSD 前半段
PowerPlanName=平衡     ; OSD 后半段
PowerPlanGuid=…        ; 实际调用的计划，程序在创建副本后会自动改写这一行
NativeGuid=…           ; 复制计划时的模板来源，一般不用动
TrayIcon=icon_balanced.ico
```

热键同时接受 `Alt+Q`（人类写法）和 `^!q`（AHK 符号写法：`^`Ctrl `!`Alt `+`Shift `#`Win），程序内部会归一化——因为 AHK 的 `Hotkey()` 只认符号，直接写 `Alt+Q` 会报 `Invalid hotkey`。

---

## 工作原理

```
按下 Alt+Q
   │
   ├─ PowerGetActiveScheme (powrprof.dll)  ── 直接读真实状态，约 0.1 ms
   ├─ 计算下一档（跳过已确认不可用的档位）
   ├─ PowerSetActiveScheme <GUID>
   │     └─ 失败 → powercfg /setactive <GUID>
   │              └─ 仍失败 → powercfg -duplicatescheme <原生模板>
   │                       ├─ powercfg -changename <新GUID> "高性能"
   │                       ├─ 写回 config.ini
   │                       └─ 再激活；仍失败则标记该档不可用
   ├─ PowerGetActiveScheme  ── 再回读一次，校验是否真的切过去了
   ├─ 换托盘图标 + 重建菜单
   └─ OSD：改文本 → 量文字尺寸 → 移到目标屏幕底部居中 → 显示 → 900 ms 后隐藏
```

读状态和切状态都走 `powrprof.dll` 的接口，只有"复制计划 / 重命名 / 枚举"这类边缘操作才起 `powercfg` 进程。

早期版本全用 `powercfg`，一次切换要 spawn 三个进程，实测中位数 **302 ms**；改成直调 API 后降到 **≈206 ms**。剩下那 0.2 秒是 Windows 自己应用电源策略的耗时（`PowerSetActiveScheme` 调用本身就要 30–210 ms，返回后系统还要 0–280 ms 才真正生效），换任何实现都绕不过去。

几个刻意的设计决定：

**1. 状态永远来自系统，不来自内存。** 内部只缓存「某档是否可用」，从不缓存「当前是哪档」。所以你用系统设置、主板工具、`powercfg` 命令行改了计划，程序下一次切换依然基于真实状态计算。

**2. 启动阶段不动电源计划。** 常见写法是在启动时把三档各 `setactive` 一次来探测可用性——那会让每次开机都把计划乱切三遍、最后停在「节能」。本实现改为**惰性解析**：某个档位第一次被切到时才做「激活 → 回退原生 → 复制模板」的探测，结果缓存到本次运行结束。启动时只读不写。

**3. 复制计划必须用对应模板。** 如果「高性能」真的不可用，用「平衡」复制一份改名成「高性能」是自欺欺人——功耗行为完全不同。所以模板永远取该档自己的 `NativeGuid`，取不到就判定该档不可用并在循环里跳过，而不是拿别的东西糊上去。

**4. OSD 窗口只创建一次。** 启动时建好隐藏窗口，切换时只改文本、量尺寸、移动、显示。每次新建窗口会带来可见的闪烁和 GC 抖动。

**5. `powercfg` 的退出码和输出都要落盘。** 失败不静默：解析不了当前计划、激活失败、复制失败、重命名失败，全都有日志行，含退出码和原始输出片段。

---

## 风扇联动（GIGABYTE Control Center）

切电源档时，顺手把 GCC 的风扇模式也切过去。默认映射：

| PowerModeSwitcher | GCC 风扇模式 | AutomationId |
| :--- | :--- | :--- |
| 游戏 · 高性能 | 全速 | `FullSpeedModeToggleButton` |
| 日常 · 平衡 | 正常 | `PerformanceModeToggleButton` |
| 静音 · 节能 | 静音 | `QuietModeToggleButton` |

GCC 还有第四档「手动」(`CustomModeToggleButton`)，在 `config.ini` 里写 `FanMode=Custom` 即可用上。

### 为什么必须管理员权限

GCC 是以**提权进程**运行的。Windows 的 UIPI 隔离决定了：普通权限进程的 UIA 连它的控件树都读不到（实测 `GetChildren` 返回 0 个元素）。所以风扇联动有一个硬前提——**本程序也得提权**。

三种启动方式：

| 方式 | 风扇联动 | 代价 |
| :--- | :--- | :--- |
| 双击 `start.cmd`（普通权限） | ❌ 跳过并提示 | 无 |
| 右键 → 以管理员身份运行 | ✅ | 每次弹 UAC |
| 托盘菜单 →「启用免 UAC 提权启动」 | ✅ 登录自动静默启动 | 一次性 UAC，会创建一个计划任务 |

免 UAC 那条路的做法：注册 `PowerModeSwitcher_Elevated` 计划任务（`/sc onlogon /rl highest`），登录时以最高权限静默拉起，同时删掉 `shell:startup` 里的快捷方式避免双开。取消就在同一菜单项再点一次。

### 不做的事

- **不逆向命名管道**。确实存在 `\\.\pipe\SmartGuardianFanControlCoordinateSystemPort.<guid>`，普通权限也能连上，但协议是私有序列化格式，且发错命令可能让风扇失控。
- **不碰 `GSA1_ACPIMethod`**。技嘉的 ACPI 方法入口，参数全靠猜，写错同样有硬件风险。
- **不写 `Fan\setupmode.xml`**。那是 GCC 的输出文件（`Users` 只有读权限），不是输入。
- **不改风扇曲线数值**，只切模式。
- **不唤起窗口**。GCC 最小化或没运行时直接跳过，不会为了切个模式把窗口弹出来。

### 降级行为

| 情况 | 行为 |
| :--- | :--- |
| 本程序非管理员 | 跳过 + 首次弹一次提示，日志写 `原因=not_admin` |
| GCC 没运行 | 跳过 + 提示，日志 `原因=gcc_off` |
| GCC 收进托盘（窗口隐藏） | 跳过 + 提示，日志 `原因=gcc_hidden` |
| GCC 最小化 | 跳过（不唤起），日志 `原因=gcc_minimized` |
| GCC 卡死（150ms 无响应） | 跳过，日志 `原因=gcc_hung` |
| 前台是全屏程序 | 跳过，避免抢焦点打断游戏，日志 `原因=前台全屏程序` |
| 控制名找不到（GCC 改版） | 只写日志，不弹错，电源切换不受影响 |

### 为什么必须"抢一下焦点"

UIA 提供的三种"程序化点击"对 GCC 的风扇按钮**全都无效**——试过并留有证据：

| 方式 | 结果 |
| :--- | :--- |
| `element.ToggleState := 1` | 改了 WPF 依赖属性，`setupmode.xml` 不动 |
| `element.TogglePattern.Toggle()` | 只改 IsChecked，界面高亮变了，风扇不动 |
| `InvokePattern.Invoke()` | 报 `Invalid IUnknown interface pointer`（接口本身是坏的） |
| `LegacyIAccessible.DoDefaultAction()` | 调用成功，但状态无变化 |

**唯一有效**：把 UIA 焦点设到按钮上，再发一个空格——走完整的 `ButtonBase.OnClick` 链路，GCC 才会真正下发 EC 命令。副作用是切换瞬间 GCC 会拿到焦点约 200–400ms，然后立刻还回去。

所以当前台是全屏程序（游戏、全屏播放器）时，本程序会主动跳过风扇切换，不抢焦点。

### 试过但无效的"后台"方案

想做到完全不抢焦点，这四条路都走不通，别再试了：

| 方案 | 结果 |
| :--- | :--- |
| `PostMessage` 投递 `WM_LBUTTONDOWN/UP` 到窗口 | 焦点不抢，但 WPF 不认，状态为零变化 |
| `SetWindowPos(TOPMOST\|NOACTIVATE)` + 真实点击 | 点击生效（`setupmode.xml` 确实被改写），但窗口仍被激活 |
| 再叠加 `WS_EX_NOACTIVATE` | 焦点不抢了，但点击完全失效——窗口不接收输入事件 |
| `UIA element.Click()` | 走 `SetCursorPos` + 真实输入，同样需要窗口可激活 |

原因很简单：**Windows 要在后台窗口上产生一次真实点击，这个窗口必须可激活**。这是输入模型决定的，不是实现问题。

---

> **重要**：风扇联动的前提是 GCC 窗口处于「打开但不最小化」状态（可以被其他窗口遮挡）。如果你习惯把 GCC 收进托盘，那它永远不满足条件——这是「不弹窗口」换来的代价。想让它生效，把 GCC 窗口开着丢到后台就行，不需要置顶。

风扇切换走 `SetTimer` 异步执行，不占电源切换和 OSD 的那 200ms。

---

## 常见问题

**按了 `Alt+Q` 没反应？**
看 `logs/` 当天文件里有没有「热键已注册」。没有就是键位写法无效，换成 `Alt+Q` 或 `^!q`。

**快捷键和别的软件冲突怎么办？**
AHK 走键盘钩子而不是 `RegisterHotKey`，第三方抢同一个组合时本程序通常察觉不到（表现为两个程序都被触发）。换一个组合即可，程序只会在**写法无效**时报警。

**切换后图标和实际计划不一致？**
程序每次切换后会再回读一次并写日志。出现「实际计划与目标不一致」，说明有别的软件（主板厂商控制中心之类）在抢着改电源计划，去那边关掉自动切换。

**OSD 看不到？**
独占全屏游戏、部分播放器全屏、UAC 安全桌面下不显示，这是设计限制，不保证覆盖。

**系统里多出「高性能 (2)」「节能 (2)」？**
说明原生计划不可激活，程序按规则复制了对应模板。想回原生：托盘右键 →「恢复原生电源计划 GUID」，然后重启程序。

**杀软/SmartScreen 报警？**
AHK 脚本本身不签名，部分杀软对 AHK 敏感。本仓库不提交任何 exe，自己装的官方 AHK 运行时也在白名单范围内。

**会不会和主板厂商的工具打架？**
会。GIGABYTE Control Center、Armoury Crate、MSI Center 之类都会写电源计划。要么关掉它们的自动切换，要么别同时用。

---

## 目录结构

```
PowerModeSwitcher/
├─ PowerModeSwitcher.ahk   主程序（单文件，840 行）
├─ config.ini              配置
├─ icon_balanced.ico       日常（环形 / 蓝）
├─ icon_performance.ico    游戏（闪电 / 红）
├─ icon_powersave.ico      静音（月牙 / 灰绿）
├─ start.cmd               便携包启动器（配合 AutoHotkey64.exe）
├─ docs/images/            README 用图
├─ logs/                   运行时生成
└─ dev/                    开发与验收脚本
   ├─ make_icons.py        多尺寸 ICO 生成（Pillow）
   ├─ drive_test.py        端到端验收：真按键 + 截图 + powercfg 核对
   ├─ fallback_test.py     原生回退 / 配置写回 / 不可用跳过
   ├─ cfg_write_test.py    写回只改目标行
   ├─ osd_shot.py          OSD 取证书
   ├─ menu_test.py         托盘菜单截图
   ├─ smoke.py             交付形态冒烟测试
   └─ shot.py / crop.py    截图工具
```

---

## 开发与测试

验收不是"看着像能用"，而是脚本驱动的：

```bash
# 环境自检：AHK 版本、配置解析、计划可见性、DPI、OSD 几何、复制/重命名/删除往返
AutoHotkey64.exe PowerModeSwitcher.ahk --selftest   # 结果写入 logs/selftest.txt

# 端到端：发真实键盘事件，逐次回读 powercfg 校验，切换瞬间截图取证
python dev/drive_test.py
```

实测记录（Windows 11 Insider 26300，3840×2160 @150%）：

- 启动不改动电源计划
- 连续 4 次 `Alt+Q`：平衡 → 高性能 → 节能 → 平衡，逐次核对系统实际计划
- OSD 物理尺寸 247×80，底部居中，连按 3 次只有 1 个 OSD 窗口（不叠层），1.2 s 后隐藏
- 托盘左键切换成功且不弹菜单（`0x404 + WM_LBUTTONUP` 被吞掉）
- 把某档 GUID 改成无效值 → 回退原生并写回 `config.ini`，42 行文件只改 1 行
- 把某档两个 GUID 都改坏 → 该档标记不可用，循环自动跳过去切下一档

踩过的 AHK v2 坑（都写在代码注释里）：`Map` 类被同名变量遮蔽导致静默不赋值、`static x := <多行>` 不生效、变量名大小写不敏感（`L` 与 `&l` 是同一个变量）、`Gui` 自动 DPI 缩放只缩宽高不缩坐标。

---

## 兼容性

- Windows 10 / 11（x64）。不依赖 Win11 专有 API。
- AutoHotkey v2.0+（v1 不兼容）。
- 已在 Win11 Insider 26300 + 3840×2160@150% 单屏实机验证；多屏与混合 DPI 的逻辑已实现并做了坐标换算，但没有多屏硬件可测，欢迎反馈 issue。

---

## 许可

[MIT](LICENSE) —— 代码随意取用。

仓库不含 AutoHotkey 运行时。AutoHotkey 本体为 GPLv2，从 [autohotkey.com](https://www.autohotkey.com/) 获取。
