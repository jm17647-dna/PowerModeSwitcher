# -*- coding: utf-8 -*-
import sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
box = [int(x) for x in sys.argv[3:7]]
img = Image.open(src).crop(box)
if len(sys.argv) > 7:
    f = float(sys.argv[7])
    img = img.resize((int(img.width * f), int(img.height * f)), Image.LANCZOS)
img.save(dst)
print("saved", dst, img.size)
