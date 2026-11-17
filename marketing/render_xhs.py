# -*- coding: utf-8 -*-
"""PowerModeSwitcher 小红书卡片 v3 —— 电竞 / PC 玩家向。

1080x1440 竖版，7 张 + 预览。视觉语言：纯黑底、斜切卡片、HUD 括角、
霓虹光带、扫描线、发光字。
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

PROJ = Path(r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher")
IMG = PROJ / "docs" / "images"
OUT = PROJ / "marketing" / "xiaohongshu"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 1080, 1440
M = 84
CW = W - 2 * M

C_BG = (7, 7, 11)
C_PANEL = (16, 16, 23)
C_PANEL2 = (22, 22, 31)
C_LINE = (52, 54, 70)
C_TXT = (245, 246, 250)
C_SUB = (156, 160, 178)
C_BODY = (200, 202, 214)
C_DIM = (104, 108, 126)

C_RED = (255, 59, 78)
C_CYAN = (0, 224, 255)
C_BLUE = (58, 132, 248)
C_GREEN = (48, 214, 140)
C_MAGENTA = (176, 82, 255)
C_YELLOW = (255, 196, 74)

FDIR = Path(r"C:\Windows\Fonts")


def _f(name, size):
    for c in (FDIR / name, FDIR / "msyh.ttc", FDIR / "simhei.ttf"):
        if c.exists():
            try:
                return ImageFont.truetype(str(c), size)
            except OSError:
                continue
    raise SystemExit("缺中文字体")


def bold(s):
    return _f("msyhbd.ttc", s)


def reg(s):
    return _f("msyh.ttc", s)


# ------------------------------------------------------------------ 背景与装饰
def base(bg=None, veil=0.58):
    if bg:
        im = Image.open(OUT / f"_ai_bg_{bg}.jpg").convert("RGB")
        im = im.resize((W, H), Image.LANCZOS)
        img = Image.blend(im, Image.new("RGB", (W, H), C_BG), veil)

        # 底部渐变压暗：盖住 AI 水印，托住 footer
        mask = Image.new("L", (W, H), 0)
        md = ImageDraw.Draw(mask)
        for y in range(H):
            if y > H - 340:
                a = int(255 * ((y - (H - 340)) / 340) ** 0.9)
                md.line([(0, y), (W, y)], fill=a)
        img.paste(Image.new("RGB", (W, H), C_BG), (0, 0), mask)
        # footer 带直接填实黑，彻底压住水印
        ImageDraw.Draw(img).rectangle([0, H - 112, W, H], fill=C_BG)

        # 顶部轻微压暗，保证 kicker 可读
        mask2 = Image.new("L", (W, H), 0)
        md2 = ImageDraw.Draw(mask2)
        for y in range(170):
            md2.line([(0, y), (W, y)], fill=int(120 * (1 - y / 170)))
        img.paste(Image.new("RGB", (W, H), C_BG), (0, 0), mask2)
    else:
        img = Image.new("RGB", (W, H), C_BG)
        d = ImageDraw.Draw(img)
        for x in range(0, W + 72, 72):
            d.line([(x, 0), (x, H)], fill=(15, 15, 22))
        for y in range(0, H + 72, 72):
            d.line([(0, y), (W, y)], fill=(15, 15, 22))
    return img


def streak(img, p1, p2, color, width=110, alpha=70):
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    ImageDraw.Draw(layer).line([p1, p2], fill=color, width=width)
    layer = layer.filter(ImageFilter.GaussianBlur(width // 2))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).line([p1, p2], fill=alpha, width=width)
    img.paste(layer, (0, 0), mask.filter(ImageFilter.GaussianBlur(width // 2)))


def halo(img, c, r, color, alpha=60):
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    ImageDraw.Draw(layer).ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=color)
    layer = layer.filter(ImageFilter.GaussianBlur(r // 2))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=alpha)
    img.paste(layer, (0, 0), mask.filter(ImageFilter.GaussianBlur(r // 2)))


def scanlines(img, step=5, alpha=26):
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    for y in range(0, H, step):
        md.line([(0, y), (W, y)], fill=alpha)
    img.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), mask)


def chamfer(d, box, cut=20, fill=None, outline=None, width=2):
    x1, y1, x2, y2 = box
    pts = [(x1 + cut, y1), (x2, y1), (x2, y2 - cut), (x2 - cut, y2), (x1, y2), (x1, y1 + cut)]
    if fill:
        d.polygon(pts, fill=fill)
    if outline:
        d.line(pts + [pts[0]], fill=outline, width=width, joint="curve")


def hud(img, box, size=30, color=C_RED, w=4, alpha=200):
    """四角 HUD 括角。"""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x1, y1, x2, y2 = box
    col = color + (alpha,)
    for (cx, cy, dx, dy) in ((x1, y1, 1, 1), (x2, y1, -1, 1), (x1, y2, 1, -1), (x2, y2, -1, -1)):
        d.line([(cx, cy), (cx + dx * size, cy)], fill=col, width=w)
        d.line([(cx, cy), (cx, cy + dy * size)], fill=col, width=w)
    img.paste(layer, (0, 0), layer)


def tx(d, xy, s, font, fill=C_TXT, anchor="la", spacing=0, stroke=0, stroke_fill=None):
    if spacing == 0:
        d.text(xy, s, font=font, fill=fill, anchor=anchor,
               stroke_width=stroke, stroke_fill=stroke_fill)
        return
    x, y = xy
    for ch in s:
        d.text((x, y), ch, font=font, fill=fill, anchor=anchor,
               stroke_width=stroke, stroke_fill=stroke_fill)
        x += font.getlength(ch) + spacing


def tokens(s):
    out, buf = [], ""
    for ch in s:
        if ch.isascii() and ch not in " ,.;:!?()（）「」，。：；！？—+":
            buf += ch
        else:
            if buf:
                out.append(buf)
                buf = ""
            out.append(ch)
    if buf:
        out.append(buf)
    return out


PUNCT_TAIL = "，。：；！？、）」』…—"


def wrap(s, font, max_w):
    """换行：CJK 逐字、拉丁词整块；标点优先跟随上一行，放不下才悬挂。"""
    lines, cur = [], ""
    for tk in tokens(s):
        if tk in PUNCT_TAIL and cur:
            if font.getlength(cur + tk) <= max_w:
                cur += tk
            else:
                lines.append(cur + tk)      # 悬挂：允许溢出一点，避免孤字
                cur = ""
            continue
        if font.getlength(cur + tk) <= max_w or not cur:
            cur += tk
        else:
            lines.append(cur)
            cur = tk.lstrip()
    if cur:
        lines.append(cur)
    return lines


def para(d, x, y, s, font, fill=C_BODY, max_w=None, lh=1.55):
    for ln in wrap(s, font, max_w or CW):
        tx(d, (x, y), ln, font, fill)
        y += int(font.size * lh)
    return y


def para_h(s, font, max_w=None, lh=1.55):
    return len(wrap(s, font, max_w or CW)) * int(font.size * lh)


def tag(d, x, y, label, color=C_RED, font=None, cut=12, pady=12, padx=22, solid=False):
    font = font or reg(28)
    tw = font.getlength(label)
    h = font.size + pady * 2
    w = int(tw + padx * 2)
    if solid:
        chamfer(d, [x, y, x + w, y + h], cut, fill=color)
        tx(d, (x + padx, y + h / 2 + 1), label, font, (12, 12, 16), anchor="lm")
    else:
        chamfer(d, [x, y, x + w, y + h], cut, fill=(22, 22, 30), outline=color, width=2)
        tx(d, (x + padx, y + h / 2 + 1), label, font, color, anchor="lm")
    return w, h


def keycap(d, x, y, label, font, w=None, h=94, color=C_RED):
    w = w or int(font.getlength(label) + 52)
    chamfer(d, [x, y, x + w, y + h], 16, fill=(34, 34, 46), outline=(96, 96, 124), width=3)
    chamfer(d, [x + 5, y + 5, x + w - 5, y + h - 10], 12, fill=(46, 46, 62), outline=color, width=2)
    tx(d, (x + w / 2, y + h / 2 - 3), label, font, C_TXT, anchor="mm")
    return w


def load_shot(path, tw=None, th=None, crop=None, radius=14):
    im = Image.open(path).convert("RGB")
    if crop:
        im = im.crop(crop)
    s = (th / im.height) if (th and (not tw or im.height / im.width > th / tw)) else (tw / im.width)
    im = im.resize((max(int(im.width * s), 1), max(int(im.height * s), 1)), Image.LANCZOS)
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=radius, fill=255)
    return im, mask


def shot(img, path, xy, tw=None, th=None, crop=None, radius=14, frame=(74, 76, 96)):
    im, mask = load_shot(path, tw, th, crop, radius)
    fr = Image.new("RGB", (im.width + 16, im.height + 16), frame)
    fm = Image.new("L", fr.size, 0)
    ImageDraw.Draw(fm).rounded_rectangle([0, 0, fr.width - 1, fr.height - 1], radius=radius + 6, fill=255)
    img.paste(fr, (xy[0] - 8, xy[1] - 8), fm)
    img.paste(im, xy, mask)
    return im.size


def auto_crop_light(path, thresh=200):
    im = Image.open(path).convert("RGB")
    px = im.load()
    xs, ys = [], []
    for y in range(0, im.height, 2):
        for x in range(0, im.width, 2):
            r, g, b = px[x, y]
            if r > thresh and g > thresh and b > thresh:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return (max(min(xs) - 4, 0), max(min(ys) - 4, 0),
            min(max(xs) + 6, im.width), min(max(ys) + 6, im.height))


def osd_strip():
    paths = [PROJ / "dev" / "shots" / f"osd_{i}.png" for i in (1, 2, 3)]
    if not all(p.exists() for p in paths):
        return IMG / "osd-three-modes.png"
    ims = []
    for p in paths:
        im = Image.open(p).convert("RGB")
        mask = Image.new("L", im.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=10, fill=255)
        ims.append((im, mask))
    h = max(i.height for i, _ in ims) + 22
    gap = 20
    tw = sum(i.width for i, _ in ims) + gap * 2 + 12
    strip = Image.new("RGB", (tw, h), (14, 14, 20))
    x = 6
    for im, mask in ims:
        strip.paste(im, (x, (h - im.height) // 2), mask)
        x += im.width + gap
    out = OUT / "_osd_strip.png"
    strip.save(out)
    return out


def footer(d, i, total):
    d.line([M, H - 96, W - M, H - 96], fill=(38, 38, 50), width=2)
    tx(d, (M, H - 66), "POWER MODE SWITCHER", reg(22), C_DIM, spacing=3)
    tx(d, (W - M, H - 66), f"{i:02d} / {total:02d}", reg(22), C_DIM, anchor="ra", spacing=2)


def kicker(d, y, s, color=C_RED):
    w = int(reg(24).getlength(s) * 1.14)
    d.rectangle([M, y + 6, M + 10, y + 28], fill=color)
    tx(d, (M + 26, y), s, reg(24), (150, 154, 172), spacing=4)


# ------------------------------------------------------------------ 卡片
def icon_badge(size=210):
    """托盘图标转成带发光的 PNG，用作封面装饰。"""
    src = PROJ / "icon_performance.ico"
    im = Image.open(src).convert("RGBA")
    big = max(im.size)
    im = im.resize((size * 2, size * 2), Image.LANCZOS)
    out = OUT / "_icon_badge.png"
    im.save(out)
    return out


def card1(total):
    img = base("red", veil=0.42)
    d = ImageDraw.Draw(img)

    hud(img, (26, 26, W - 26, H - 26), 44, C_RED, 4, 130)
    kicker(d, 86, "W I N D O W S   1 1   ·   开 源 免 费")

    # 客群标识：封面第一大字，红底斜切
    bw, bh = tag(d, M, 126, "PC 玩家", C_RED, bold(104), cut=22, pady=16, padx=26, solid=True)
    tx(d, (M + bw + 22, 126 + bh / 2 - 2), "专属", bold(72), C_RED, anchor="lm",
       stroke=0)

    tx(d, (M, 322), "开黑前，别再翻五层菜单", bold(46), (150, 154, 172), spacing=1)

    tx(d, (M, 404), "一个键", bold(122), C_TXT, spacing=4, stroke=2, stroke_fill=(10, 10, 14))
    tx(d, (M, 546), "切性能", bold(122), C_RED, spacing=4, stroke=3, stroke_fill=(60, 8, 14))

    tx(d, (M, 714), "打游戏切高性能，挂机切静音。", reg(31), C_BODY)
    tx(d, (M, 756), "台式机、笔记本，都用一个键换挡。", reg(31), C_BODY)

    kf = bold(36)
    x = M
    x += keycap(d, x, 822, "Alt", kf) + 14
    tx(d, (x + 14, 869), "+", bold(38), C_DIM, anchor="mm")
    x += 56
    x += keycap(d, x, 822, "Q", kf, w=90) + 40
    tx(d, (x, 869), "循环换档", reg(30), C_DIM, anchor="lm")

    y = 960
    for label, color in (("日常 · 平衡", C_BLUE), ("游戏 · 高性能", C_RED), ("静音 · 节能", C_GREEN)):
        tag(d, M, y, label, color, reg(28), cut=14, pady=13)
        y += 62

    # 顶部 kicker 已标注"开源免费"，这里不再重复

    # 右上角产品图标（红闪电），带柔光
    ic = Image.open(icon_badge(200)).convert("RGBA").resize((200, 200), Image.LANCZOS)
    gmask = Image.new("L", (W, H), 0)
    ipos = (W - M - 200, 296)
    gmask.paste(ic.split()[3].point(lambda v: int(v * 0.55)), ipos)
    gmask = gmask.filter(ImageFilter.GaussianBlur(26))
    img.paste(Image.new("RGB", (W, H), (200, 40, 50)), (0, 0), gmask)
    img.paste(ic, ipos, ic)
    footer(d, 1, total)
    scanlines(img)
    return img


def card2(total):
    img = base("red", veil=0.62)
    d = ImageDraw.Draw(img)
    hud(img, (26, 26, W - 26, H - 26), 40, (70, 72, 92), 3, 120)
    kicker(d, 104, "P A I N   0 1")

    tx(d, (M, 172), "游戏在「平衡」里", bold(74), C_TXT, spacing=2)
    tx(d, (M, 262), "跑了一整晚", bold(74), C_RED, spacing=2, stroke=2, stroke_fill=(50, 8, 12))

    tx(d, (M, 386), "笔记本有 Fn 键一键切，台式机呢？", reg(29), C_SUB)

    # 笔记本 vs 台式机对比条
    cy = 438
    cw = (CW - 16) // 2
    chamfer(d, [M, cy, M + cw, cy + 96], 14, fill=(14, 24, 20), outline=C_GREEN, width=2)
    tx(d, (M + 22, cy + 16), "笔记本", reg(24), C_GREEN)
    tx(d, (M + 22, cy + 46), "Fn 一键切", bold(34), C_TXT)
    chamfer(d, [M + cw + 16, cy, W - M, cy + 96], 14, fill=(24, 14, 16), outline=C_RED, width=2)
    tx(d, (M + cw + 38, cy + 16), "台式机", reg(24), C_RED)
    tx(d, (M + cw + 38, cy + 46), "翻五层菜单", bold(34), C_TXT)

    blocks = [
        ("掉 帧", "计划卡在平衡，CPU 降频，明明能跑满的帧数白丢。", C_RED),
        ("风 扇", "切了高性能忘记切回来，深夜机箱起飞，队友听你吹风。", C_YELLOW),
        ("五 步", "右键桌面 → 显示设置 → 电源和睡眠 → 其他电源设置 → 选计划。", C_CYAN),
    ]
    y = 570
    bf = reg(29)
    for title, body, color in blocks:
        bh = para_h(body, bf, CW - 84, 1.5)
        h = 100 + bh + 42
        chamfer(d, [M, y, W - M, y + h], 18, fill=C_PANEL, outline=(44, 46, 60), width=2)
        d.polygon([(M, y + 24), (M + 6, y + 24), (M + 6, y + h - 24), (M, y + h - 24)], fill=color)
        tx(d, (M + 34, y + 28), title, bold(36), color)
        para(d, M + 40, y + 92, body, bf, (176, 178, 196), CW - 84, 1.5)
        y += h + 24

    tx(d, (M, y + 26), "每次切一下五步，一天几遍。", reg(28), (92, 96, 112))
    footer(d, 2, total)
    scanlines(img)
    return img


def card3(total):
    img = base("blue", veil=0.6)
    d = ImageDraw.Draw(img)
    hud(img, (26, 26, W - 26, H - 26), 40, (70, 72, 92), 3, 120)
    kicker(d, 104, "O N E   K E Y   0 2")

    tx(d, (M, 172), "按一下，", bold(78), C_TXT, spacing=2)
    tx(d, (M, 268), "底部给你确认", bold(78), C_RED, spacing=2, stroke=2, stroke_fill=(50, 8, 12))

    tag(d, M + 1, 362, "全程无感 · 不抢焦点", C_GREEN, reg(24), cut=10, pady=9, padx=18)

    top = 416
    w, h = shot(img, osd_strip(), (M, top), tw=CW, th=470, radius=12, frame=(86, 88, 110))

    y = top + h + 64
    for t in ["切换瞬间浮出，0.9 秒自动消失",
              "点击穿透、不抢焦点，不打断手上的操作",
              "跟随鼠标所在屏幕，副屏也显示在正确位置"]:
        d.polygon([(M, y + 12), (M + 12, y + 18), (M, y + 24)], fill=C_GREEN)
        y = para(d, M + 30, y, t, reg(34), C_BODY, CW - 30, 1.5) + 20

    footer(d, 3, total)
    scanlines(img)
    return img


def card4(total):
    img = base("purple", veil=0.62)
    d = ImageDraw.Draw(img)
    hud(img, (26, 26, W - 26, H - 26), 40, (70, 72, 92), 3, 120)
    kicker(d, 104, "C O N T R O L   0 3")

    tx(d, (M, 172), "左键切，右键挑", bold(76), C_TXT, spacing=2)

    w1, h1 = shot(img, IMG / "tray-icon-tooltip.png", (M, 306), tw=CW, th=210, radius=12, frame=(86, 88, 110))
    tx(d, (M, 306 + h1 + 22), "图标颜色 = 当前模式：红 = 游戏，蓝 = 日常，绿 = 静音", reg(26), C_DIM)

    my = 306 + h1 + 92
    crop = auto_crop_light(IMG / "tray-menu.png")
    menu_w = 424
    w2, h2 = shot(img, IMG / "tray-menu.png", (M, my), tw=menu_w, crop=crop, radius=12, frame=(86, 88, 110))

    bx = M + menu_w + 48
    rw = W - M - bx
    items = [("左键单击", "直接跳到下一档", C_RED),
             ("右键菜单", "看当前状态，任意挑一档", C_BLUE),
             ("菜单里还有", "关自启、改配置、看日志", C_GREEN)]
    y = my + 4
    for k, v, color in items:
        d.rectangle([bx, y + 8, bx + 6, y + 24], fill=color)
        tx(d, (bx + 18, y), k, bold(30), C_TXT)
        y = para(d, bx + 18, y + 44, v, reg(26), (184, 186, 200), rw - 18, 1.45) + 30

    footer(d, 4, total)
    scanlines(img)
    return img


def card_light(total):
    img = base("blue", veil=0.6)
    d = ImageDraw.Draw(img)
    hud(img, (26, 26, W - 26, H - 26), 40, (70, 72, 92), 3, 120)
    kicker(d, 104, "L I G H T W E I G H T   0 4")

    tx(d, (M, 172), "30 KB，", bold(80), C_TXT, spacing=2)
    tx(d, (M, 268), "开机就在", bold(80), C_CYAN, spacing=2, stroke=2, stroke_fill=(4, 40, 52))

    stats = [("30 KB", "整个程序就一个脚本文件", C_RED),
             ("17 MB", "常驻内存，私有内存仅 4 MB", C_CYAN),
             ("CPU ≈ 0%", "待机不占，切换瞬间也无压力", C_YELLOW),
             ("开机自启", "托盘一键开关，登录即在", C_GREEN)]
    y = 404
    for i, (big, small, color) in enumerate(stats):
        col = i % 2
        row = i // 2
        x = M + col * (CW // 2 + 8)
        top = y + row * 268
        wblock = CW // 2 - 8
        chamfer(d, [x, top, x + wblock, top + 248], 16, fill=C_PANEL, outline=(46, 48, 64), width=2)
        tx(d, (x + 26, top + 26), big, bold(34 if len(big) > 4 else 52), color)
        para(d, x + 26, top + 106, small, reg(26), (168, 170, 188), wblock - 52, 1.45)

    yy = y + 2 * 268 + 10
    chamfer(d, [M, yy, W - M, yy + 196], 14, fill=(12, 12, 18), outline=(52, 54, 70), width=2)
    tx(d, (M + 30, yy + 28), "不装驱动、不起服务、不留后台进程。", reg(29), C_BODY)
    tx(d, (M + 30, yy + 74), "关掉就是关掉，进程表里立刻消失。", reg(29), C_BODY)
    tx(d, (M + 30, yy + 134), "按下到切完仅 206ms，只用系统电源接口，不碰注册表。", reg(26), C_DIM)

    footer(d, 5, total)
    scanlines(img)
    return img


def card5(total):
    img = base("blue", veil=0.62)
    d = ImageDraw.Draw(img)
    hud(img, (26, 26, W - 26, H - 26), 40, (70, 72, 92), 3, 120)
    kicker(d, 104, "U S E   C A S E   0 5")

    tx(d, (M, 172), "三档，三种战场", bold(76), C_TXT, spacing=2)

    scenes = [
        ("游戏 · 高性能", "MODE 01", C_RED,
         "开黑、渲染、跑分。全核不降频，帧数稳，风扇随你。"),
        ("日常 · 平衡", "MODE 02", C_BLUE,
         "写稿、开会、刷网页。安静省电，该降频就降频。"),
        ("静音 · 节能", "MODE 03", C_GREEN,
         "深夜挂下载、通宵编译。机箱不叫，室友不敲墙。"),
    ]
    y = 300
    bf = reg(29)
    for name, en, color, body in scenes:
        bh = para_h(body, bf, CW - 60, 1.5)
        h = 126 + bh + 48
        chamfer(d, [M, y, W - M, y + h], 18, fill=C_PANEL, outline=(44, 46, 60), width=2)
        chamfer(d, [M, y, M + 176, y + 44], 0, fill=color)
        tx(d, (M + 14, y + 8), en, reg(24), (14, 14, 18), spacing=2)
        tx(d, (M + 34, y + 58), name, bold(38), C_TXT, spacing=1)
        para(d, M + 34, y + 116, body, bf, (178, 180, 198), CW - 60, 1.5)
        y += h + 28

    tx(d, (M, y + 30), "技术上也诚实：切换前后都问系统真实状态，", reg(27), C_DIM)
    tx(d, (M, y + 66), "系统藏了高性能就按原模板复制，绝不拿平衡改名冒充。", reg(27), C_DIM)

    footer(d, 6, total)
    scanlines(img)
    return img


def card6(total):
    img = base("purple", veil=0.55)
    d = ImageDraw.Draw(img)
    hud(img, (26, 26, W - 26, H - 26), 40, (70, 72, 92), 3, 120)
    kicker(d, 104, "A G E N T   I N S T A L L   0 6")

    tx(d, (M, 172), "一句话，", bold(78), C_TXT, spacing=2)
    tx(d, (M, 268), "让 AI 帮你装", bold(78), C_RED, spacing=2, stroke=2, stroke_fill=(50, 8, 12))

    # 三步流程条
    fy = 372
    tag(d, M, fy, "复制  →  粘贴  →  回车  ·  30 秒装完", C_GREEN, reg(26), cut=12, pady=11, padx=22)

    # 对话框：这是"你对 Agent 说的话"
    bx1, by1, bx2 = M, 458, W - M
    pf, prompt = reg(29), ("帮我装 PowerModeSwitcher，一个 Windows 电源模式切换工具。"
                           "从 GitHub 下 jm17647-dna PowerModeSwitcher 的 main 分支，"
                           "解压到 %LOCALAPPDATA%\\PowerModeSwitcher，"
                           "再下 AutoHotkey v2 便携版，把 AutoHotkey64.exe 放进同目录。"
                           "装完启动，确认托盘有图标、Alt+Q 能切电源计划。")
    p_h = para_h(prompt, pf, (bx2 - bx1) - 64, 1.62)
    box_h = 84 + p_h + 34
    chamfer(d, [bx1, by1, bx2, by1 + box_h], 20, fill=(15, 15, 21), outline=(62, 64, 82), width=2)
    d.rectangle([bx1 + 26, by1 + 30, bx1 + 34, by1 + 58], fill=C_RED)
    tx(d, (bx1 + 48, by1 + 26), "把这段发给 Agent", reg(26), (150, 154, 172))
    para(d, bx1 + 32, by1 + 82, prompt, pf, (216, 218, 232), (bx2 - bx1) - 64, 1.62)

    tips = [("能跑命令就行", "WorkBuddy / Claude Code / Cursor / Copilot 都可以"),
            ("仓库里带 install.ps1", "Agent 直接执行，或照上面的步骤手动走"),
            ("不写系统目录", "装在用户目录，删掉文件夹就是卸载"),
            ("Windows 10 / 11 都能跑", "只调系统自带的电源接口，不装驱动")]
    y = by1 + box_h + 44
    for k, v in tips:
        d.polygon([(M, y + 12), (M + 12, y + 18), (M, y + 24)], fill=C_GREEN)
        tx(d, (M + 30, y), k, bold(29), C_TXT)
        y = para(d, M + 30, y + 38, v, reg(26), (168, 170, 186), CW - 30, 1.42) + 22

    footer(d, 7, total)
    scanlines(img)
    return img


def card_agent(total):
    """Agent 指令全文，一屏可抄。"""
    img = base("purple", veil=0.62)
    d = ImageDraw.Draw(img)
    hud(img, (26, 26, W - 26, H - 26), 40, (70, 72, 92), 3, 120)
    kicker(d, 104, "C O P Y   &   P A S T E   0 7")

    tx(d, (M, 168), "把这段丢给它", bold(74), C_TXT, spacing=2)

    lines = [
        ("", "帮我装 PowerModeSwitcher（Windows 电源模式切换工具），照做："),
        ("1", "下载仓库 main 分支的 zip 并解压"),
        ("", "github.com/jm17647-dna/PowerModeSwitcher"),
        ("2", "放到 %LOCALAPPDATA%\\PowerModeSwitcher"),
        ("3", "下载 autohotkey.com/download/ahk-v2.zip"),
        ("", "把 AutoHotkey64.exe 放进同一目录"),
        ("4", "启动 PowerModeSwitcher.ahk"),
        ("5", "确认托盘出现图标、Alt+Q 能切电源计划"),
        ("", "把 logs 里最新一行回报给我"),
    ]

    top = 290
    _rows_h = 0
    for _num, _line in lines:
        _rows_h += 62 if _num else len(wrap(_line, reg(28), CW - 110)) * 48 + 8
    box_h = 78 + _rows_h + 40
    chamfer(d, [M, top, W - M, top + box_h], 18, fill=(11, 11, 16), outline=(58, 60, 78), width=2)
    d.rectangle([M, top + 46, W - M, top + 48], fill=(40, 42, 56))
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        d.ellipse([M + 26 + i * 26, top + 20, M + 26 + i * 26 + 14, top + 34], fill=c)
    tx(d, (W - M - 26, top + 18), "agent-prompt.txt", reg(22), (96, 100, 118), anchor="ra")

    nf, cf, bf = bold(30), reg(28), reg(28)
    y = top + 78
    for num, line in lines:
        if num:
            tx(d, (M + 30, y), num, nf, C_RED)
            tx(d, (M + 70, y + 1), line, bf, (222, 224, 238))
            y += 62
        else:
            is_url = line.startswith("github.com") or line.startswith("autohotkey.com")
            col = (120, 200, 255) if is_url else (168, 170, 188)
            for seg in wrap(line, cf, CW - 110):
                tx(d, (M + 70, y + 1), seg, cf, col)
                y += 48
            y += 8

    tx(d, (M, top + box_h + 30), "也可以直接让它跑仓库里的 install.ps1", reg(26), C_DIM)

    ty = top + box_h + 92
    chamfer(d, [M, ty, W - M, ty + 150], 14, fill=(16, 16, 22), outline=(56, 58, 74), width=2)
    tx(d, (M + 28, ty + 24), "装完想换键？", reg(26), C_DIM)
    tx(d, (M + 28, ty + 64), "改 config.ini 里的 Hotkey= 一行，重启程序生效。", reg(27), (206, 208, 222))
    tx(d, (M + 28, ty + 106), "Alt+Q / Ctrl+Shift+M / F9 都行。", reg(25), (140, 144, 162))

    footer(d, 8, total)
    scanlines(img)
    return img


def card7(total):
    img = base("red", veil=0.5)
    d = ImageDraw.Draw(img)
    hud(img, (26, 26, W - 26, H - 26), 44, C_RED, 4, 140)
    kicker(d, 104, "O P E N   S O U R C E   0 8")

    tx(d, (M, 176), "仓库在这，", bold(84), C_TXT, spacing=2)
    tx(d, (M, 282), "随便拿", bold(84), C_RED, spacing=2, stroke=3, stroke_fill=(60, 8, 14))

    y = 420
    chamfer(d, [M, y, W - M, y + 250], 18, fill=C_PANEL, outline=(58, 60, 78), width=2)
    tx(d, (M + 34, y + 28), "GITHUB", reg(24), C_DIM, spacing=3)
    tx(d, (M + 34, y + 66), "jm17647-dna / PowerModeSwitcher", bold(34), C_TXT)
    tx(d, (M + 34, y + 128), "MIT 协议 · 840 行 · 30 KB · 零依赖", reg(27), C_SUB)
    tag(d, M + 34, y + 176, "求个 Star", C_YELLOW, reg(26), cut=10, pady=11)

    tx(d, (M, 730), "适合谁", bold(40), C_TXT, spacing=2)
    y = 800
    for t in ["台式游戏机：开黑切性能，深夜切静音",
              "笔记本：插电游戏 vs 电池续航，一个键换挡",
              "看主板控制中心不爽的所有人"]:
        d.polygon([(M, y + 12), (M + 12, y + 18), (M, y + 24)], fill=C_DIM)
        y = para(d, M + 30, y, t, reg(32), C_BODY, CW - 30, 1.5) + 18

    chamfer(d, [M, 1128, W - M, 1256], 16, fill=(26, 18, 22), outline=(96, 40, 48), width=2)
    tx(d, (M + 30, 1152), "你一天切几次电源？", bold(34), C_TXT)
    tx(d, (M + 30, 1202), "评论区报个数，顺手点个 Star。", reg(27), C_SUB)

    footer(d, 9, total)
    scanlines(img)
    return img


def main():
    cards = [card1, card2, card3, card4, card_light, card5, card6, card_agent, card7]
    n = len(cards)
    files = []
    for i, fn in enumerate(cards, 1):
        im = fn(n)
        p = OUT / f"{i:02d}.png"
        im.save(p)
        files.append(p)
        print("wrote", p.name, f"{p.stat().st_size / 1024:.0f}KB")

    tw, th, cols = 360, 480, 4
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * th), (0, 0, 0))
    for i, p in enumerate(files):
        im = Image.open(p).resize((tw - 10, th - 10), Image.LANCZOS)
        sheet.paste(im, ((i % cols) * tw + 5, (i // cols) * th + 5))
    sheet.save(OUT / "preview.png")
    print("preview ok")


if __name__ == "__main__":
    main()
