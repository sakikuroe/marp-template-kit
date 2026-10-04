# Unicode の East Asian Width が Ambiguous (A) に分類されるグリフを半角化する.
# 罫線 (Box Drawing), ブロック要素 (Block Elements), 幾何学記号 (Geometric Shapes) の一部などが該当する.
# ターミナルはこれらを Ambiguous として 1 カラム (半角) 扱いで描画するが,
# Rounded Mgen+ 1m はこれらを CJK と同じ全角 (1em) で収録しているため,
# 半角の英数字と混在すると桁がずれる. X 方向に 0.5 倍へ縮小し, 送り幅を半角 (0.5em) に揃える.
import sys
import unicodedata
from fontTools.ttLib import TTFont

src, dst = sys.argv[1], sys.argv[2]
font = TTFont(src)
cmap = font.getBestCmap()
glyf = font["glyf"]
hmtx = font["hmtx"]
upm = font["head"].unitsPerEm
half = upm // 2

for cp, name in cmap.items():
    if unicodedata.east_asian_width(chr(cp)) != "A":
        continue
    adv, lsb = hmtx[name]
    if adv != upm:
        continue
    glyph = glyf[name]
    if glyph.numberOfContours > 0:
        glyph.coordinates.transform(((0.5, 0), (0, 1)))
        glyph.recalcBounds(glyf)
    hmtx[name] = (half, int(lsb * 0.5))

font.save(dst)
