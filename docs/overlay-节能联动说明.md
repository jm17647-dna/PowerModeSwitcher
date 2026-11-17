# v1.1-overlay：优雅的节能联动方案

## 文件

- `PowerModeSwitcher_v11_overlay.ahk` —— 基于 git HEAD 的干净 v1.0（865 行），只新增了 Overlay 联动模块。不依赖 UIA 库，不需要管理员，不动 v1.1，不碰 git。

## 它解决的问题

旧方案（v1.1 的 `ApplyEnergySaver`，**现已从主程序砍除**）是「弹快速设置面板 → UIA 找叶子图标 → 发空格 → Esc」。它弹面板遮挡屏幕、抢焦点、全屏程序要跳过、按钮名称/AutomationId 写死（11-17 日志实证"找不到按钮"）——已弃用。

根本原因：Win11 的「节能模式」叶子开关**没有公开的即时切换 API**——只能改注册表（要重启）或模拟点击 UI，都不优雅。所以主程序不再自动点它，节能联动改由本 overlay 版用下面的方式实现。

## 新方案：Overlay（电源模式滑块）

Windows 的电源模式滑块（最佳能效 / 平衡 / 最佳性能）底层是 `powrprof.dll` 的 Overlay Scheme，有底层 API：

| 函数 | 作用 |
|---|---|
| `PowerGetActualOverlayScheme` | 读当前滑块 GUID |
| `PowerSetActiveOverlayScheme` | 设滑块 GUID，即时生效 |

**优点**：一次 DllCall、0ms、无 UI、无焦点抢占、无需管理员、无需 UIA。和 v1.0 已在用的 `PowerSetActiveScheme` 是同一套 DLL、同一种调用风格。

**本机实测（2026-11-17）**：设「最佳能效」rc=0 且立即生效，设「平衡」rc=0，恢复原值 rc=0，注册表 `ActiveOverlayAcPowerScheme` 同步更新。

## 行为

- **启动**：只读记录当前滑块值（不修改任何电源状态）。
- **切到「静音 · 节能」档**：滑块 → 最佳能效。
- **离开该档**：滑块 → 恢复启动时记录的原值（不覆盖你手动调整过的偏好）。
- **失败**：只写日志，绝不影响电源计划切换本身。
- 设置走 `SetTimer` 异步，不阻塞切换和 OSD。

## 关键坑（别踩）

1. **GUID 不能照抄网上值**。网传「最佳能效」GUID 第四段是 `8177`，本机实际是 `8174`：
   - 错：`961cc777-2547-4f9d-`**`8177`**`-4d86181b8a7a`（本机返回 rc=87 参数无效）
   - 对：`961cc777-2547-4f9d-`**`8174`**`-7d86181b8a7a`
   - 代码里用 `config.ini` 的 `OverlayMinGuid` 可覆盖。
2. **AHK v2 的 `for` 循环里用 `A_Index`**（已改用循环变量 i，更稳妥）；`static x := <多行数组>` 不生效。
3. **不要在启动时试探性 Set overlay**（会与别的电源工具抢锁导致阻塞）——只读启动即可。

## 取舍（必须知情）

Overlay 切的是「电源模式滑块到最佳能效」，**不是**严格意义上的「节能模式」叶子开关。两者在 Win11 24H2+ 效果高度重合（都降亮度、压后台活动、降刷新率）。你是台式机无电池，快速设置里那个叶子按钮本来就可能不显示，所以 Overlay 这条路反而更可靠。

如果你坚持要真正切那个叶子开关，只能改注册表 `HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergySaverState`（1=开/2=关），但要管理员权限且重启才生效，做不到一键即时——这就是没选它的原因。

## 配置（config.ini 新增，全部可选，留空即用默认值）

```ini
[General]
OverlaySync=1        ; 1=启用联动（默认），0=关闭
OverlayEcoMode=3     ; 哪一档视作节能：1=日常 2=游戏 3=静音（默认）
OverlayMinGuid=      ; 最佳能效 GUID；留空用本机实测值 961cc777-...-8174-7d86181b8a7a
```

托盘右键菜单会多一行「电源滑块：最佳能效 / 原值 xxxxxxxx」，方便确认状态。

## 验证

```bash
AutoHotkey64.exe PowerModeSwitcher_v11_overlay.ahk --selftest
# 结果写入 logs/selftest.txt 的「电源模式滑块 Overlay」段
```

手动验证：设系统为「静音 · 节能」→ 看注册表 `ActiveOverlayAcPowerScheme` 是否变成 MIN；切回「日常」→ 是否恢复原值。
