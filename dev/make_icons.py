# -*- coding: utf-8 -*-
"""生成 PowerModeSwitcher 三套托盘图标（多尺寸 .ico）。"""
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher")
PREVIEW = OUT / "dev" / "icons_preview.png"
BASE = 1024  # 超采样画布


def circle(draw, cx, cy, r, fill=None, outline=None, width=1):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=width)


def make(color, rim, glyph):
    img = Image.new("RGBA", (BASE, BASE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = BASE / 2
    R = BASE * 0.478
    circle(d, c, c, R, fill=rim)                    # 外圈深色描边
    circle(d, c, c, R * 0.93, fill=color)           # 主色圆
    # 顶部柔和高光
    hl = Image.new("RGBA", (BASE, BASE), (0, 0, 0, 0))
    dh = ImageDraw.Draw(hl)
    circle(dh, c, c - R * 0.30, R * 0.80, fill=(255, 255, 255, 26))
    img = Image.alpha_composite(img, hl)
    d = ImageDraw.Draw(img)

    W = (255, 255, 255, 255)
    if glyph == "bolt":
        pts = [(0.640, 0.120), (0.288, 0.560), (0.452, 0.560),
               (0.368, 0.880), (0.712, 0.430), (0.548, 0.430)]
        d.polygon([(x * BASE, y * BASE) for x, y in pts], fill=W)
    elif glyph == "ring":
        r_out = BASE * 0.205
        circle(d, c, c, r_out, outline=W, width=int(BASE * 0.072))
    elif glyph == "moon":
        tmp = Image.new("RGBA", (BASE, BASE), (0, 0, 0, 0))
        dt = ImageDraw.Draw(tmp)
        circle(dt, c - BASE * 0.012, c, BASE * 0.215, fill=W)
        cut = Image.new("RGBA", (BASE, BASE), (0, 0, 0, 0))
        dc = ImageDraw.Draw(cut)
        circle(dc, c + BASE * 0.098, c - BASE * 0.055, BASE * 0.183, fill=(255, 255, 255, 255))
        # 用 cut 抠掉月牙缺口
        from PIL import ImageChops
        alpha = tmp.split()[3]
        cutmask = cut.split()[3]
        alpha = ImageChops.subtract(alpha, cutmask)
        tmp.putalpha(alpha)
        img = Image.alpha_composite(img, tmp)
    return img


def main():
    specs = [
        ("icon_performance.ico", (229, 72, 77, 255), (150, 40, 44, 255), "bolt"),
        ("icon_balanced.ico", (46, 124, 246, 255), (28, 78, 168, 255), "ring"),
        ("icon_powersave.ico", (108, 138, 122, 255), (66, 92, 79, 255), "moon"),
    ]
    sizes = [(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64), (128, 128), (256, 256)]
    previews = []
    for name, color, rim, glyph in specs:
        big = make(color, rim, glyph)
        big.save(OUT / name, format="ICO", sizes=sizes)
        previews.append(big.resize((256, 256), Image.LANCZOS))
        # 16px 实际渲染检查
        small = big.resize((16, 16), Image.LANCZOS).resize((128, 128), Image.NEAREST)
        previews.append(small)
        print("wrote", name, (OUT / name).stat().st_size, "bytes")

    sheet = Image.new("RGBA", (256 * 6, 256), (20, 20, 22, 255))
    for i, p in enumerate(previews):
        sheet.alpha_composite(p, (i * 256, 0)) if p.size == (256, 256) else sheet.paste(p, (i * 256, 0))
    sheet.save(PREVIEW)
    print("preview", PREVIEW)


if __name__ == "__main__":
    main()
