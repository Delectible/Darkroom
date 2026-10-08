"""Lays rendered body sprites out like the app's camera screen (Pixel 9 Pro,
412 x 915 dp), for judging the look without a phone.

    python3 mockup.py SPRITES_DIR film|digital out.png
"""
import json
import sys

from PIL import Image, ImageDraw, ImageFont

src, mode, out = sys.argv[1:4]
man = json.load(open(f'{src}/manifest.json'))
PX = man['px']
W, H, TOP, BOT = 412, 915, 48, 24
img = Image.new('RGBA', (round(W * PX), round(H * PX)), (20, 16, 13, 255))


def load(part, state=None, yaw=0):
    p = man['parts'][mode][part]
    st = state or (p.get('states') or [None])[0]
    im = Image.open(f"{src}/{mode}/{part}{'-' + st if st else ''}-a{yaw}.webp").convert('RGBA')
    px = p.get('px', PX)
    if px != PX:
        im = im.resize((round(im.width * PX / px), round(im.height * PX / px)), Image.LANCZOS)
    return im, p


def put(part, cx, cy, state=None):
    im, _ = load(part, state)
    img.alpha_composite(im, (round(cx * PX - im.width / 2), round(cy * PX - im.height / 2)))


def nine(part, x0, y0, x1, y1):
    """9-slice (or 3-slice) the part round the dp box (x0, y0)-(x1, y1)."""
    im, p = load(part)
    cw, ch = p['canvas']
    bw, bh = p.get('box', p['canvas'])
    mx, my = (cw - bw) / 2, (ch - bh) / 2
    sx = p.get('sliceX') or p.get('slice') or 0
    sy = 0 if p.get('sliceX') else p.get('slice') or 0
    k = im.width / cw
    tw, th = round((x1 - x0 + 2 * mx) * PX), round((y1 - y0 + 2 * my) * PX)
    a, b = round(sx * k), round(sy * k)
    ta, tb = round(sx * PX), round(sy * PX)
    out_ = Image.new('RGBA', (tw, th))
    xs = [(0, a, 0, ta), (a, im.width - a, ta, tw - ta), (im.width - a, im.width, tw - ta, tw)]
    ys = [(0, b, 0, tb), (b, im.height - b, tb, th - tb), (im.height - b, im.height, th - tb, th)]
    for sx0, sx1, dx0, dx1 in xs:
        for sy0, sy1, dy0, dy1 in ys:
            if sx1 <= sx0 or sy1 <= sy0 or dx1 <= dx0 or dy1 <= dy0:
                continue
            tile = im.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.LANCZOS)
            out_.alpha_composite(tile, (dx0, dy0))
    img.alpha_composite(out_, (round((x0 - mx) * PX), round((y0 - my) * PX)))


def rect(x0, y0, x1, y1, fill):
    ImageDraw.Draw(img).rectangle([x0 * PX, y0 * PX, x1 * PX, y1 * PX], fill=fill)


# surface
panel, _ = load('panel')
panel = panel.resize((img.width, round(panel.height * img.width / panel.width)), Image.LANCZOS)
img.alpha_composite(panel.crop((0, 0, img.width, img.height)))
if mode == 'film':
    pt, p = load('plate-top')
    edge = TOP + 58
    img.alpha_composite(pt, (0, round((edge + p['edge']) * PX) - pt.height))
    pb, p = load('plate-bot')
    img.alpha_composite(pb, (0, round((H - BOT - 12 - p['edge']) * PX)))

# viewfinder
rect(23, 109, 389, 691, (12, 11, 10, 255))
try:
    photo = Image.open(f'{src}/../photo.png').convert('RGBA').resize((round(366 * PX), round(582 * PX)))
    img.alpha_composite(photo, (round(23 * PX), round(109 * PX)))
except FileNotFoundError:
    pass
nine('frame', 14, 100, 398, 700)

# top bar (y 56..92)
cy = 74
if mode == 'film':
    put('flash', 50, cy)
    put('flashtab', 50 - 27, cy + 6)
    put('aspect', 128, cy)
    put('menu', 378, cy)
else:
    put('pill', 50, cy)
    put('pillwide', 128, cy)
    put('pillsmall', 378, cy)
put('lens', 328, cy)
put('lensdot', 328, cy)

# under the viewfinder
if mode == 'film':
    rect(27, 731, 385, 767, (241, 235, 221, 255))
    nine('memo', 20, 725, 392, 773)
else:
    rect(27, 731, 230, 767, (166, 176, 146, 255))
    nine('lcd', 20, 724, 238, 774)
    put('rocker', 330, 745)

# bottom row
put('print' if mode == 'film' else 'review', 56, 830)
put('shutter', 206 + (8 if mode == 'film' else 0), 830)
put('tray', 356, 830)
img.convert('RGB').save(out)
print('saved', out, img.size)
