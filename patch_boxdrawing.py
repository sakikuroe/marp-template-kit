# 罫線グリフ (U+2500-257F) を半角化する.
# Rounded Mgen+ 1m は罫線を全角 (1em) で収録しており, 半角の英数字と混在すると桁がずれる.
# X 方向に 0.5 倍へ縮小し, 送り幅を半角 (0.5em) に揃える.
import sys
from fontTools.ttLib import TTFont

src, dst = sys.argv[1], sys.argv[2]
font = TTFont(src)
cmap = font.getBestCmap()
glyf = font["glyf"]
hmtx = font["hmtx"]
half = font["head"].unitsPerEm // 2

for cp in range(0x2500, 0x2580):
    name = cmap.get(cp)
    if name is None:
        continue
    glyph = glyf[name]
    if glyph.numberOfContours > 0:
        glyph.coordinates.transform(((0.5, 0), (0, 1)))
        glyph.recalcBounds(glyf)
    adv, lsb = hmtx[name]
    hmtx[name] = (half, int(lsb * 0.5))

font.save(dst)
