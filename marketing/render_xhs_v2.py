# -*- coding: utf-8 -*-
"""小红书宣传图 v2 —— 电竞 / PC 玩家 / 三档配色。PIL 直接出图，1080x1440。"""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJ, "marketing", "xiaohongshu")
os.makedirs(OUT, exist_ok=True)

W, H = 1080, 1440
M = 92                      # 版心边距
CW = W - M * 2              # 内容宽 896

BG     = (5, 7, 12)
INK    = (9, 12, 19)
PANEL  = (13, 17, 26)
LINE   = (32, 40, 56)
TXT    = (233, 238, 247)
MUT    = (124, 135, 155)
DIM    = (86, 96, 114)
BLUE   = (83, 147, 255)
PINK   = (236, 72, 153)
GREEN  = (34, 197, 94)
WHITE  = (255, 255, 255)

FONTS = {
    "cn":   r"C:\Windows\Fonts\msyhbd.ttc",
    "cnr":  r"C:\Windows\Fonts\msyh.ttc",
    "disp": r"C:\Windows\Fonts\bahnschrift.ttf",
    "mono": r"C:\Windows\Fonts\consolab.ttf",
    "monor":r"C:\Windows\Fonts\consola.ttf",
}
_cache = {}
def F(kind, size):
    key = (kind, size)
    if key not in _cache:
        _cache[key] = ImageFont.truetype(FONTS[kind], size)
    return _cache[key]

def fit(d, s, font, max_w):
    if d.textlength(s, font=font) <= max_w:
        return s
    lo, hi = 0, len(s)
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if d.textlength(s[:mid] + "…", font=font) <= max_w:
            lo = mid
        else:
            hi = mid - 1
    return s[:lo] + "…"

def tw(d, s, font):
    return d.textlength(s, font=font)

def track_text(d, xy, s, font, fill, tracking=0, anchor_y="la"):
    x, y = xy
    for ch in s:
        d.text((x, y), ch, font=font, fill=fill)
        x += d.textlength(ch, font=font) + tracking
    return x

def glow(img, draw_fn, color, radius=26, alpha=120):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    draw_fn(ld, color + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(radius))
    img.alpha_composite(layer)

def canvas(bg=None):
    img = Image.new("RGBA", (W, H), (bg or BG) + (255,))
    d = ImageDraw.Draw(img)
    # 细网格
    g = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(g)
    step = 54
    for x in range(0, W + step, step):
        gd.line([(x, 0), (x, H)], fill=(120, 150, 200, 7), width=1)
    for y in range(0, H + step, step):
        gd.line([(0, y), (W, y)], fill=(120, 150, 200, 7), width=1)
    img.alpha_composite(g)
    # 顶部冷光
    top = Image.new("RGBA", (W, 520), (0, 0, 0, 0))
    td = ImageDraw.Draw(top)
    td.ellipse([-260, -420, W + 260, 320], fill=(60, 110, 200, 40))
    img.alpha_composite(top.filter(ImageFilter.GaussianBlur(90)), (0, 0))
    return img, d

def corner_marks(d, color=(70, 82, 104), length=34, w=2, inset=40):
    for (x, y, dx, dy) in [(inset, inset, 1, 1), (W - inset, inset, -1, 1),
                           (inset, H - inset, 1, -1), (W - inset, H - inset, -1, -1)]:
        d.line([(x, y), (x + dx * length, y)], fill=color, width=w)
        d.line([(x, y), (x, y + dy * length)], fill=color, width=w)

def chrome(d, idx, total, accent=BLUE):
    d.line([(M, 118), (W - M, 118)], fill=LINE, width=1)
    d.rectangle([M, 110, M + 22, 114], fill=accent)
    d.text((M + 34, 100), "POWER MODE SWITCHER", font=F("mono", 15), fill=DIM)
    s = "%02d / %02d" % (idx, total)
    d.text((W - M - tw(d, s, F("mono", 15)), 100), s, font=F("mono", 15), fill=DIM)
    d.line([(M, H - 102), (W - M, H - 102)], fill=LINE, width=1)
    d.text((M, H - 82), "WINDOWS 10 / 11 · 免费开源", font=F("cnr", 17), fill=DIM)
    tag = "ALT + Q"
    d.text((W - M - tw(d, tag, F("mono", 15)), H - 82), tag, font=F("mono", 15), fill=DIM)

def kicker(d, x, y, s, color=BLUE):
    d.rectangle([x, y + 4, x + 6, y + 22], fill=color)
    track_text(d, (x + 18, y), s, F("mono", 16), color, tracking=2)


def rich_line(d, x, y, segs, font):
    cx = x
    for text, color in segs:
        d.text((cx, y), text, font=font, fill=color)
        cx += tw(d, text, font)
    return cx

def headline(d, x, y, lines, size=112, lead_ratio=1.06, color=TXT):
    f = F("cn", size)
    lh = int(size * lead_ratio)
    for i, (s, c) in enumerate(lines):
        d.text((x, y + i * lh), s, font=f, fill=c or color)
    return y + len(lines) * lh

def body(d, x, y, s, size=24, color=MUT, max_w=CW, lh=1.62, font="cnr"):
    f = F(font, size)
    line, cury = "", y
    for ch in s:
        if tw(d, line + ch, f) > max_w:
            d.text((x, cury), line, font=f, fill=color)
            line, cury = ch, cury + int(size * lh)
        else:
            line += ch
    if line:
        d.text((x, cury), line, font=f, fill=color)
        cury += int(size * lh)
    return cury

def keycap(d, x, y, label, w=None, h=104, color=BLUE, size=34):
    f = F("disp", size)
    w = w or int(max(tw(d, label, f) + 64, 104))
    poly = [(x + 14, y), (x + w, y), (x + w, y + h - 14), (x + w - 14, y + h), (x, y + h), (x, y + 14)]
    d.polygon(poly, fill=(18, 23, 34, 255), outline=color + (255,))
    d.line(poly + [poly[0]], fill=color + (170,), width=2)
    d.text((x + w / 2, y + h / 2 - 4), label, font=f, fill=TXT, anchor="mm")
    return w

def chip(d, x, y, label, color, h=44, size=18):
    f = F("cn", size)
    w = int(tw(d, label, f) + 34)
    d.rounded_rectangle([x, y, x + w, y + h], radius=6, fill=color + (30,), outline=color + (150,))
    d.text((x + w / 2, y + h / 2 - 1), label, font=f, fill=color, anchor="mm")
    return w

def osd_card(img, x, y, w, mode_name, plan, sub, accent, idx, total):
    """按真实 OSD 规格绘制：底色 = 中性灰与档位色混合 45%，左侧色条提亮 45%。"""
    h = 118
    def mix(a, b, t):
        return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))
    card = mix((31, 31, 31), accent, 0.45)
    bar = mix(accent, WHITE, 0.45)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.rounded_rectangle([0, 0, w - 1, h - 1], radius=12, fill=card + (235,))
    ld.rounded_rectangle([22, 26, 26, h - 26], radius=2, fill=bar + (255,))
    ld.text((44, 24), mode_name, font=F("cn", 34), fill=(245, 245, 245, 255))
    ld.text((44, 72), sub, font=F("cnr", 20), fill=(228, 228, 228, 255))
    t = "%d / %d" % (idx, total)
    ld.text((w - 26 - tw(ld, t, F("disp", 18)), 30), t, font=F("disp", 18), fill=bar + (255,))
    img.alpha_composite(layer, (x, y))


def bottom_band(d, label, text, accent=BLUE, y=1128):
    d.line([(M, y), (W - M, y)], fill=LINE, width=1)
    d.rectangle([M, y + 26, M + 18, y + 30], fill=accent)
    d.text((M + 30, y + 18), label, font=F("mono", 14), fill=DIM)
    d.text((M, y + 54), text, font=F("cn", 27), fill=TXT)
    return y + 110

def card_cover(total):
    img, d = canvas()
    corner_marks(d)
    d.text((M, 168), "PC 玩家专属", font=F("cn", 30), fill=MUT)
    d.text((M, 212), "WINDOWS 10 / 11 · 一个键切三档", font=F("cnr", 20), fill=DIM)
    y = 292
    fh = F("cn", 136)
    lh = int(136 * 1.06)
    d.text((M, y), "一个键，", font=fh, fill=TXT)
    rich_line(d, M, y + lh, [("切", TXT), ("性能", PINK)], fh)
    y = y + lh * 2
    body(d, M, y + 34, "团战前调高性能、写文档换平衡、挂机下载切节能——不用翻五层菜单，按一下就换。", 24, MUT, CW - 90)
    # 键帽
    kx = M
    kx += keycap(d, kx, 726, "Alt", color=BLUE) + 20
    d.text((kx, 762), "+", font=F("disp", 46), fill=DIM)
    kx += 56
    keycap(d, kx, 726, "Q", w=132, color=PINK)
    d.text((M, 862), "循环三档 · 托盘左键也能切", font=F("cnr", 20), fill=DIM)
    # 三档
    cy = 966
    trio = [("日常 · 平衡", BLUE, "写文档 / 刷网页"), ("游戏 · 高性能", PINK, "开黑 / 渲染"), ("静音 · 节能", GREEN, "挂机 / 深夜")]
    for i, (name, c, use) in enumerate(trio):
        col_x = M + i * 300
        d.rectangle([col_x, cy, col_x + 4, cy + 92], fill=c)
        d.text((col_x + 20, cy + 4), name, font=F("cn", 26), fill=TXT)
        d.text((col_x + 20, cy + 48), use, font=F("cnr", 18), fill=DIM)
    # 右下光晕
    glow(img, lambda ld, c: ld.ellipse([W - 380, H - 520, W + 60, H - 60], fill=c), PINK, 80, 60)
    chrome(d, 1, total)
    return img

def card_pain(total):
    img, d = canvas()
    corner_marks(d)
    kicker(d, M, 176, "PAIN POINT", PINK)
    headline(d, M, 214, [("系统在替你省电，", TXT), ("也在替你掉帧", PINK)], size=84)
    body(d, M, 430, "你并不缺性能，缺的是「切过去」这个动作。", 24, MUT, CW - 80)
    items = [
        ("团战从 120 帧掉到 40", "电源计划还挂在「平衡」，CPU 频率被压在 65%", PINK),
        ("风扇一夜起飞", "挂着下载、开着网页，系统不降频，散热器一直吼", BLUE),
        ("切一次要五步", "右键桌面 → 电源选项 → 更多设置 → 选计划 → 关窗口", GREEN),
    ]
    y = 520
    for title, desc, c in items:
        d.rectangle([M, y, M + 3, y + 118], fill=c)
        d.text((M + 26, y + 6), title, font=F("cn", 34), fill=TXT)
        body(d, M + 26, y + 58, desc, 20, MUT, CW - 60, 1.5)
        d.text((W - M - 40, y + 6), "×", font=F("disp", 34), fill=c)
        y += 168
    d.line([(M, 1080), (W - M, 1080)], fill=LINE, width=1)
    body(d, M, 1108, "每次切一下五步，一天几遍。你练的是手速，不是耐心。", 22, TXT, CW - 40)
    bottom_band(d, "WHY IT HAPPENS", "不是硬件不行，是电源计划没跟着场景走。", PINK)
    chrome(d, 2, total, PINK)
    return img

def card_speed(total):
    img, d = canvas()
    corner_marks(d)
    kicker(d, M, 176, "ONE KEY · < 200ms", BLUE)
    headline(d, M, 214, [("按下的瞬间，", TXT), ("已经切完", BLUE)], size=92)
    body(d, M, 430, "不弹窗、不抢焦点、不打断游戏。提示条 0.9 秒后自己收起。", 24, MUT, CW - 60)
    # 大键帽
    bx, by = M + 90, 540
    glow(img, lambda ld, c: ld.rounded_rectangle([bx - 30, by - 20, bx + 470, by + 200], radius=28, fill=c), BLUE, 60, 70)
    keycap(d, bx, by, "Alt", w=250, h=180, color=BLUE, size=62)
    d.text((bx + 270, by + 52), "+", font=F("disp", 64), fill=DIM)
    keycap(d, bx + 330, by, "Q", w=180, h=180, color=PINK, size=62)
    stats = [("切换生效", "< 200 ms"), ("提示停留", "0.9 s"), ("弹窗 / 抢焦点", "0")]
    y = 800
    for label, val in stats:
        d.text((M, y), label, font=F("cnr", 21), fill=MUT)
        d.text((W - M - tw(d, val, F("disp", 30)), y - 8), val, font=F("disp", 30), fill=TXT)
        d.line([(M, y + 52), (W - M, y + 52)], fill=(26, 33, 46), width=1)
        y += 86
    body(d, M, y + 16, "提示条是顶层但不抢焦点：全屏游戏里也不会被切出去，副屏同样居中。", 20, DIM, CW - 40)
    bottom_band(d, "NO INTERRUPTION", "全屏游戏里切档，也不会把你弹回桌面。", BLUE)
    chrome(d, 3, total, BLUE)
    return img

def card_modes(total):
    img, d = canvas()
    corner_marks(d)
    kicker(d, M, 176, "THREE LOADOUTS", GREEN)
    headline(d, M, 214, [("三档，", TXT), ("三种战场", GREEN)], size=92)
    body(d, M, 424, "每档对应一个电源计划，也对应托盘上一种颜色。", 22, MUT, CW - 60)
    rows = [
        ("日常 · 平衡", "平衡", "写文档、开会、刷网页 —— 不烫、不吵、够快", BLUE, 1),
        ("游戏 · 高性能", "高性能", "开黑、渲染、跑分 —— 全核放开，帧率稳住", PINK, 2),
        ("静音 · 节能", "节能", "挂机、下载、深夜 —— 风扇安静，电费友好", GREEN, 3),
    ]
    y = 500
    for name, plan, use, c, i in rows:
        osd_card(img, M, y, CW, name, plan, use, c, i, 3)
        y += 152
    d.line([(M, 1030), (W - M, 1030)], fill=LINE, width=1)
    body(d, M, 1058, "切档后 OSD 卡片直接取该档的图标色，颜色即状态，不用读字。", 21, MUT, CW - 40)
    bottom_band(d, "COLOR = STATE", "托盘、OSD、图标三处同色，扫一眼就知道当前档。", GREEN)
    chrome(d, 4, total, GREEN)
    return img

def card_light(total):
    img, d = canvas()
    corner_marks(d)
    kicker(d, M, 176, "LIGHTWEIGHT", GREEN)
    headline(d, M, 214, [("30 KB，", TXT), ("开机就在", GREEN)], size=92)
    body(d, M, 440, "一个脚本，不带服务、不带驱动、不带 Electron。", 23, MUT, CW - 60)
    grid = [("30 KB", "整个程序"), ("0", "第三方依赖"), ("~4 MB", "常驻内存"), ("< 1%", "空闲 CPU")]
    for i, (big, label) in enumerate(grid):
        cx = M + (i % 2) * 452
        cy = 520 + (i // 2) * 172
        d.rectangle([cx, cy, cx + 420, cy + 148], fill=(15, 19, 28, 255), outline=(30, 38, 52, 255))
        d.text((cx + 26, cy + 22), big, font=F("disp", 46), fill=TXT)
        d.text((cx + 26, cy + 92), label, font=F("cnr", 20), fill=MUT)
    # 体积对比
    y = 900
    d.text((M, y), "体积对比（启动器类工具常见量级）", font=F("cnr", 19), fill=DIM)
    bars = [("PowerModeSwitcher", 30, BLUE, "30 KB"), ("常见 Electron 启动器", 17000, (66, 74, 92), "~17 MB")]
    by = y + 36
    maxv = 17000
    barw = CW - 120
    for name, val, c, label in bars:
        d.text((M, by), name, font=F("cnr", 18), fill=MUT)
        d.text((W - M - tw(d, label, F("disp", 20)), by - 2), label, font=F("disp", 20), fill=TXT)
        bw = max(int((val / maxv) * barw), 10)
        d.rectangle([M, by + 30, M + bw, by + 48], fill=c)
        d.rectangle([M, by + 30, M + barw, by + 48], outline=(28, 35, 48), width=1)
        by += 96
    body(d, M, by + 10, "关机不残留、卸载就是删文件夹；改配置只动 config.ini。", 20, DIM, CW - 40)
    chrome(d, 5, total, GREEN)
    return img

def card_compare(total):
    img, d = canvas()
    corner_marks(d)
    kicker(d, M, 176, "BEFORE / AFTER", PINK)
    headline(d, M, 214, [("以前五步，", TXT), ("现在一下", PINK)], size=88)
    col_w = (CW - 28) // 2
    y = 430
    d.rectangle([M, y, M + col_w, y + 62], fill=(24, 20, 28, 255))
    d.text((M + 24, y + 14), "以前", font=F("cn", 26), fill=(170, 150, 165))
    d.rectangle([M + col_w + 28, y, W - M, y + 62], fill=(16, 26, 22, 255))
    d.text((M + col_w + 52, y + 14), "装了它", font=F("cn", 26), fill=(120, 220, 165))
    left = ["右键桌面 → 电源选项", "→ 更多电源设置", "→ 选计划 → 关窗口", "游戏里切=掉出全屏", "忘了切=风扇整夜转"]
    right = ["Alt + Q", "底部 0.9 秒确认", "不抢焦点，不切出游戏", "三档颜色一眼就知道", "切完即走，没别的动作"]
    yy = y + 96
    for a, b in zip(left, right):
        d.text((M + 24, yy), a, font=F("cnr", 21), fill=MUT)
        d.text((M + col_w + 52, yy), b, font=F("cnr", 21), fill=TXT)
        yy += 54
    d.line([(M + col_w + 14, 520), (M + col_w + 14, yy - 10)], fill=LINE, width=1)
    bottom = 826
    d.rectangle([M, bottom, W - M, bottom + 150], fill=(12, 16, 24, 255), outline=(32, 40, 56, 255))
    d.text((M + 28, bottom + 18), "真实失败也会说清楚", font=F("cn", 24), fill=TXT)
    body(d, M + 28, bottom + 60, "没管理员权限时，切档会在 OSD 上写明「权限不足」并给出提权入口，不会静默失败。", 19, MUT, CW - 70, 1.45)
    chrome(d, 6, total, PINK)
    return img

def card_install(total):
    img, d = canvas()
    corner_marks(d)
    kicker(d, M, 176, "GET IT", BLUE)
    headline(d, M, 214, [("下载，解压，", TXT), ("双击就能用", BLUE)], size=88)
    body(d, M, 420, "包里自带 AutoHotkey 运行时，不用装环境。", 23, MUT, CW - 60)
    steps = [("01", "下载 zip", "Releases 页 → PowerModeSwitcher-portable-v1.1.0.zip"),
             ("02", "解压到任意目录", "建议放在 D 盘工具目录，别放桌面"),
             ("03", "双击 启动.vbs", "托盘出现小图标，按 Alt+Q 开始用")]
    y = 500
    for num, title, desc in steps:
        d.text((M, y - 6), num, font=F("disp", 34), fill=DIM)
        d.text((M + 76, y - 8), title, font=F("cn", 30), fill=TXT)
        body(d, M + 76, y + 38, desc, 19, MUT, CW - 130, 1.45)
        y += 138
    d.line([(M, y + 6), (W - M, y + 6)], fill=LINE, width=1)
    d.text((M, y + 34), "github.com/jm17647-dna/PowerModeSwitcher/releases", font=F("mono", 18), fill=BLUE)
    body(d, M, y + 80, "Win11 默认把新图标收进任务栏右侧的 ^ 里，拖出来就能常驻。", 19, DIM, CW - 40)
    chrome(d, 7, total, BLUE)
    return img

def card_config(total):
    img, d = canvas()
    corner_marks(d)
    kicker(d, M, 176, "TUNABLE", GREEN)
    headline(d, M, 214, [("想改？", TXT), ("一个 ini 就够", GREEN)], size=88)
    body(d, M, 414, "热键、停留时长、不透明度、图标、开机自启，全在 config.ini 里。", 22, MUT, CW - 60)
    # 代码块
    bx, by = M, 500
    bw, bh = CW, 330
    d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=10, fill=(11, 14, 21, 255), outline=(30, 38, 52, 255))
    d.rectangle([bx, by, bx + bw, by + 44], fill=(17, 22, 32, 255))
    d.text((bx + 18, by + 12), "config.ini", font=F("mono", 17), fill=MUT)
    lines = [
        "[General]", "Hotkey=Alt+Q", "OSD_Duration=900", "OSD_Opacity=235",
        "StartWithWindows=1", "; tray icons", "TrayIcon=icon_sets\\G_filled\\icon_balanced_g6.ico",
    ]
    yy = by + 62
    for i, ln in enumerate(lines):
        c = GREEN if ln.startswith(";") else (TXT if ln.startswith("[") else (170, 200, 255))
        d.text((bx + 24, yy), ln, font=F("monor", 18), fill=c)
        yy += 36
    body(d, M, 872, "托盘右键还有：重新读取当前计划、恢复原生 GUID、打开配置 / 日志、开机自启开关。", 20, MUT, CW - 40, 1.5)
    bottom_band(d, "PLAIN TEXT ALL THE WAY", "高级选项一律不用图形界面：改错了，把 .bak 改回去就行。", GREEN)
    chrome(d, 8, total, GREEN)
    return img

def card_cta(total):
    img, d = canvas()
    corner_marks(d)
    kicker(d, M, 176, "OPEN SOURCE", PINK)
    headline(d, M, 214, [("仓库在这，", TXT), ("随便拿", PINK)], size=96)
    body(d, M, 448, "MIT 协议，代码全在 GitHub。觉得有用，给个 Star 就够。", 23, MUT, CW - 60)
    d.line([(M, 548), (W - M, 548)], fill=LINE, width=1)
    d.text((M, 574), "github.com/jm17647-dna/PowerModeSwitcher", font=F("mono", 22), fill=TXT)
    d.text((M, 622), "PowerModeSwitcher-portable-v1.1.0.zip", font=F("mono", 18), fill=BLUE)
    # 三色条
    for i, c in enumerate([BLUE, PINK, GREEN]):
        d.rectangle([M + i * 60, 706, M + i * 60 + 48, 712], fill=c)
    rows = [("适合谁", "台式游戏机 / 笔记本 / 有主板厂商自建计划的机器"),
            ("不适合谁", "想调风扇曲线、超频、改功耗墙的，它不管这些"),
            ("它只做一件事", "把电源计划切过去，并且让你知道切成了")]
    y = 766
    for k, v in rows:
        d.text((M, y), k, font=F("cnr", 17), fill=DIM)
        body(d, M, y + 30, v, 21, TXT, CW - 60, 1.45)
        y += 140
    # 结尾
    d.line([(M, 1168), (W - M, 1168)], fill=LINE, width=1)
    d.text((M, 1192), "一天切几次电源？", font=F("cn", 32), fill=TXT)
    d.text((M, 1244), "按一下试试就知道了。", font=F("cnr", 22), fill=MUT)
    glow(img, lambda ld, c: ld.ellipse([W - 460, 980, W + 20, H - 60], fill=c), BLUE, 90, 55)
    chrome(d, 9, total, PINK)
    return img

def main():
    cards = [card_cover, card_pain, card_speed, card_modes, card_light,
             card_compare, card_install, card_config, card_cta]
    total = len(cards)
    images = []
    for i, fn in enumerate(cards, 1):
        img = fn(total).convert("RGB")
        p = os.path.join(OUT, "%02d.png" % i)
        img.save(p, quality=95)
        images.append(img)
        print("saved", p)
    # 预览拼图 3x3
    gap = 18
    pw = 1440
    cw = (pw - gap * 4) // 3
    chh = int(cw * H / W)
    sheet = Image.new("RGB", (pw, gap * 4 + chh * 3), (10, 12, 18))
    for i, im in enumerate(images):
        t = im.resize((cw, chh), Image.LANCZOS)
        x = gap + (i % 3) * (cw + gap)
        y = gap + (i // 3) * (chh + gap)
        sheet.paste(t, (x, y))
    sheet.save(os.path.join(OUT, "preview.png"))
    print("preview ok")

if __name__ == "__main__":
    main()
