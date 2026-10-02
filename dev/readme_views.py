"""README picture: island snapshots (from dev/views.sh) flush in the top-right
corner of a calm backdrop, two per row.   python3 dev/readme_views.py OUT a.png b.png ..."""
import sys
from PIL import Image

out, paths = sys.argv[1], sys.argv[2:]
TW, TH, GAP = 520, 250, 16


def backdrop():
    # a soft vertical gradient, like a wallpaper behind the island
    bg = Image.new("RGB", (TW, TH))
    top, bot = (58, 74, 104), (122, 138, 160)
    for y in range(TH):
        t = y / (TH - 1)
        bg.paste(tuple(int(a + (b - a) * t) for a, b in zip(top, bot)), (0, y, TW, y + 1))
    return bg


tiles = []
for p in paths:
    im = Image.open(p).convert("RGBA")
    x0, y0, x1, y1 = im.getchannel("A").getbbox()
    im = im.crop((x0, 0, x1, y1))  # keep the top edge: the island hangs from it
    tile = backdrop()
    tile.paste(im, (TW - im.width, 0), im)
    tiles.append(tile)

cols = 2
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (cols * TW + (cols - 1) * GAP, rows * TH + (rows - 1) * GAP), "white")
for i, t in enumerate(tiles):
    sheet.paste(t, ((i % cols) * (TW + GAP), (i // cols) * (TH + GAP)))
sheet.save(out)
