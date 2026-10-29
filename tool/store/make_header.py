"""Store art from the app's own world: a darkroom wall under the safelight,
prints drying on a line, the films and cameras on a walnut desk, and the
name on a strip of masking tape.

    python3 tool/store/make_header.py OUT_DIR [W H ...]   (Pillow + numpy)

Writes header_WxH.png for each size (default 1024x500, Play's feature
graphic). Everything is laid out on a 1024x500 stage and scaled; taller
or wider sizes get more wall / desk round the same scene. The prints are
drawn here (sunset sea, hills, a city at dusk...), not anyone's photos.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
ART = os.path.join(ROOT, 'assets', 'artwork')
FONT = os.path.join(ROOT, 'assets', 'fonts', 'Caveat-SemiBold.ttf')
rng = np.random.default_rng(1998)


def art(name):
    im = Image.open(os.path.join(ART, f'{name}.webp')).convert('RGBA')
    return im.crop(im.getbbox())


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# --- the prints ------------------------------------------------------------

def sky(w, h, top, bottom):
    a = np.zeros((h, w, 3))
    t = np.linspace(0, 1, h)[:, None]
    a[:] = np.array(top) * (1 - t)[..., None][:, :, 0:1] + np.array(bottom) * t[..., None][:, :, 0:1]
    return a


def photo(kind, w, h, seed):
    r = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    if kind == 'sea':
        a = sky(w, h, (60, 70, 120), (250, 170, 110))
        sun = np.exp(-(((xx - 0.62) * w) ** 2 + ((yy - 0.5) * h) ** 2) / (2 * (0.09 * w) ** 2))
        a += sun[..., None] * np.array([255, 200, 120]) * 0.9
        sea = yy > 0.58
        a[sea] = (np.array([40, 60, 90]) + (yy[sea, None] - 0.58) * np.array([-30, -30, -40]))
        glint = sea & (abs(xx - 0.62) < 0.06 * (1 + (yy - 0.58) * 3)) & (r.random((h, w)) > 0.55)
        a[glint] = [250, 200, 140]
    elif kind == 'hills':
        a = sky(w, h, (150, 190, 220), (235, 225, 200))
        for k, (base, col) in enumerate([(0.55, (110, 130, 110)), (0.68, (70, 100, 60)), (0.82, (45, 70, 40))]):
            ridge = base + 0.06 * np.sin(xx * (5 + k * 3) + seed + k) + 0.03 * np.sin(xx * 17 + k)
            a[yy > ridge] = col
    elif kind == 'city':
        a = sky(w, h, (30, 30, 70), (220, 120, 120))
        x = 0
        while x < w:
            bw = int(r.integers(8, 20) * w / 120)
            bh = r.uniform(0.25, 0.6)
            a[int(h * (1 - bh)):, x:x + bw] = [25, 22, 35]
            for wy in range(int(h * (1 - bh)) + 4, h - 4, 6):
                for wx in range(x + 2, min(w, x + bw) - 2, 5):
                    if r.random() < 0.35:
                        a[wy:wy + 2, wx:wx + 2] = [255, 210, 120]
            x += bw + 1
    elif kind == 'portrait':
        a = sky(w, h, (200, 170, 140), (120, 90, 70))
        head = ((xx - 0.5) * w) ** 2 / (0.2 * w) ** 2 + ((yy - 0.42) * h) ** 2 / (0.2 * h) ** 2 < 1
        a[head] = [205, 160, 130]
        body = (yy > 0.62) & (abs(xx - 0.5) < 0.28 + (yy - 0.62) * 0.6)
        a[body] = [60, 80, 110]
        hair = head & (yy < 0.36)
        a[hair] = [60, 40, 30]
    elif kind == 'lake':
        a = sky(w, h, (120, 160, 210), (230, 210, 190))
        ridge = 0.42 - 0.12 * np.sin(xx * 5.5 + 0.8) - 0.05 * np.sin(xx * 13 + 2)
        a[(yy > ridge) & (yy < 0.6)] = [70, 80, 100]
        snow = (yy > ridge) & (yy < ridge + 0.04)
        a[snow] = [235, 235, 240]
        lake = yy >= 0.6
        a[lake] = a[(1.2 - yy[lake] * 1.0).clip(0, 0.59).__mul__(h).astype(int), (xx[lake] * w).astype(int)] * 0.75 + np.array([10, 20, 30])
    else:  # palms
        a = sky(w, h, (90, 150, 200), (250, 200, 150))
        a[yy > 0.8] = [220, 190, 140]
        for px in (0.3, 0.72):
            trunk = (abs(xx - px - (0.8 - yy) * 0.08) < 0.015) & (yy > 0.3) & (yy < 0.82)
            a[trunk] = [40, 35, 30]
            for ang in range(0, 360, 45):
                t = np.linspace(0, 0.18, 40)
                fx = px + 0.05 + np.cos(math.radians(ang)) * t
                fy = 0.3 + np.sin(math.radians(ang)) * t * 0.6 + t * t * 3
                for x0, y0 in zip(fx, fy):
                    xi, yi = int(x0 * w), int(y0 * h)
                    if 0 <= xi < w - 1 and 0 <= yi < h - 1:
                        a[yi:yi + 2, xi:xi + 2] = [35, 50, 35]
    # film: lifted blacks, warm, a little grain
    a = a * 0.9 + np.array([18, 14, 10])
    a += r.normal(0, 7, (h, w, 1))
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def print_card(kind, w, h, seed, rot):
    border = int(w * 0.07)
    card = Image.new('RGBA', (w, h), (244, 240, 230, 255))
    card.paste(photo(kind, w - 2 * border, h - 2 * border - int(h * 0.06), seed), (border, border))
    # a soft drop shadow, then the slight swing on its peg
    pad = 30
    sh = Image.new('RGBA', (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 150), (pad + 6, pad + 10, pad + w + 6, pad + h + 10))
    sh = sh.filter(ImageFilter.GaussianBlur(9))
    sh.alpha_composite(card, (pad, pad))
    # a wooden peg at the top, gripping the line at (cx, grip)
    d = ImageDraw.Draw(sh)
    cx, grip = pad + w // 2, pad - 12
    d.rounded_rectangle([cx - 6, grip - 12, cx + 6, pad + 16], radius=3, fill=(196, 160, 112, 255))
    d.rounded_rectangle([cx - 6, grip - 12, cx - 2, pad + 16], radius=2, fill=(222, 190, 140, 255))
    d.line([(cx - 6, grip), (cx + 6, grip)], fill=(120, 92, 60, 255), width=2)  # the jaw on the line
    d.rectangle([cx - 8, pad - 4, cx + 8, pad], fill=(150, 150, 155, 255))
    # swing it about the grip: a square canvas centred on that point
    side = 2 * int(math.hypot(max(cx, sh.width - cx), max(grip, sh.height - grip))) + 2
    big = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    big.alpha_composite(sh, (side // 2 - cx, side // 2 - grip))
    return big.rotate(rot, resample=Image.BICUBIC)


# --- things on the desk, drawn ---------------------------------------------

LABEL = os.path.join(ROOT, 'assets', 'fonts', 'BarlowCondensed-SemiBold.ttf')


def shaded(w, h, dark, light, hi=0.3):
    """A cylinder's horizontal shading, dark edges, a highlight at [hi]."""
    x = np.linspace(0, 1, w)
    k = np.clip(np.sin(np.pi * x), 0, 1) ** 0.6 * 0.8 + 0.2
    spec = np.exp(-((x - hi) ** 2) / 0.003) * 0.6
    row = np.array(dark) + (np.array(light) - np.array(dark)) * k[:, None] + spec[:, None] * 255
    return np.repeat(row[None], h, axis=0)


def bottle(w, h, glass, label, text):
    """A chemistry bottle: shouldered glass, black cap, a paper label."""
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    body = Image.fromarray(shaded(w, h, [c * 0.35 for c in glass], glass).clip(0, 255).astype(np.uint8)).convert('RGBA')
    mask = Image.new('L', (w, h), 0)
    md = ImageDraw.Draw(mask)
    neck = w * 0.34
    md.rounded_rectangle([0, h * 0.28, w - 1, h - 1], radius=int(w * 0.12), fill=255)
    md.polygon([(0, h * 0.34), (w / 2 - neck / 2, h * 0.16), (w / 2 + neck / 2, h * 0.16), (w - 1, h * 0.34)], fill=255)
    md.rectangle([w / 2 - neck / 2, h * 0.08, w / 2 + neck / 2, h * 0.2], fill=255)
    im.paste(body, (0, 0), mask)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([w / 2 - neck / 2 - 2, 0, w / 2 + neck / 2 + 2, h * 0.11], radius=3, fill=(24, 22, 22, 255))
    d.rectangle([w / 2 - neck / 2 - 2, h * 0.02, w / 2 - neck / 2 + 3, h * 0.1], fill=(60, 58, 56, 255))
    # the label, a little curved by the shading under it
    ly0, ly1 = int(h * 0.48), int(h * 0.82)
    lab = shaded(int(w * 0.84), ly1 - ly0, [c * 0.7 for c in label], label, hi=0.35)
    lim = Image.fromarray(lab.clip(0, 255).astype(np.uint8)).convert('RGBA')
    ld = ImageDraw.Draw(lim)
    f = ImageFont.truetype(LABEL, int((ly1 - ly0) * 0.5))
    ld.text((lim.width / 2, lim.height * 0.45), text, font=f, fill=(30, 26, 24, 255), anchor='mm')
    fs = ImageFont.truetype(LABEL, max(8, int((ly1 - ly0) * 0.18)))
    ld.text((lim.width / 2, lim.height * 0.82), 'DARKROOM', font=fs, fill=(80, 70, 60, 255), anchor='mm')
    im.alpha_composite(lim, (int(w * 0.08), ly0))
    return im


def tray(w, h, colour, print_kind):
    """A developing tray seen from a little above: rim, the bath, a print
    coming up in it, its front face."""
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    top = h * 0.72  # the rim's depth on screen
    inset = w * 0.06
    rim = [(inset, 0), (w - inset, 0), (w, top), (0, top)]
    d.polygon(rim, fill=tuple(int(c * 1.0) for c in colour) + (255,))
    # the bath inside the rim
    b = 5
    bath = [(inset + b, b), (w - inset - b, b), (w - b * 1.4, top - b), (b * 1.4, top - b)]
    d.polygon(bath, fill=(74, 52, 40, 255))
    # the print, coming up: a pale card with the picture half there
    pw, ph = int(w * 0.46), int(top * 0.7)
    pic = photo(print_kind, pw, ph, 77).convert('RGBA')
    px = np.array(pic, float)
    px[..., :3] = px[..., :3] * 0.8 + 255 * 0.14  # coming up
    pic = Image.fromarray(px.clip(0, 255).astype(np.uint8))
    card = Image.new('RGBA', (pw + 8, ph + 8), (236, 232, 220, 255))
    card.alpha_composite(pic, (4, 4))
    # squash it into the bath's perspective
    card = card.resize((card.width, int(card.height * 0.9)))
    im.alpha_composite(card, (int(w / 2 - card.width / 2), int(top / 2 - card.height / 2)))
    # liquid sheen over it
    sheen = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).polygon(bath, fill=(255, 150, 120, 46))
    im.alpha_composite(sheen)
    # the front face below the rim
    face = [(0, top), (w, top), (w - 3, h), (3, h)]
    d.polygon(face, fill=tuple(int(c * 0.72) for c in colour) + (255,))
    d.line([(0, top), (w, top)], fill=tuple(min(255, int(c * 1.15)) for c in colour) + (255,), width=2)
    return im


def flat(im, squash=0.42, turn=0):
    """Something lying on the desk: turned, then seen at a low angle."""
    im = im.rotate(turn, resample=Image.BICUBIC, expand=True)
    return im.resize((im.width, max(1, int(im.height * squash))), Image.LANCZOS)


def sd_card(w):
    h = int(w * 1.33)
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cut = w * 0.22
    d.polygon([(0, 0), (w - cut, 0), (w, cut), (w, h), (0, h)], fill=(28, 52, 110, 255))
    d.rectangle([w * 0.1, h * 0.36, w * 0.9, h * 0.86], fill=(232, 232, 236, 255))
    f = ImageFont.truetype(LABEL, int(w * 0.3))
    d.text((w / 2, h * 0.52), 'SD', font=f, fill=(28, 52, 110, 255), anchor='mm')
    f2 = ImageFont.truetype(LABEL, int(w * 0.16))
    d.text((w / 2, h * 0.74), '128MB', font=f2, fill=(60, 60, 70, 255), anchor='mm')
    for i in range(6):
        d.rectangle([w * 0.12 + i * w * 0.12, h * 0.04, w * 0.12 + i * w * 0.12 + w * 0.07, h * 0.16], fill=(200, 170, 80, 255))
    return im


def floppy(w):
    im = Image.new('RGBA', (w, w), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, w - 1, w - 1], radius=int(w * 0.03), fill=(30, 30, 34, 255))
    d.rectangle([w * 0.22, 0, w * 0.74, w * 0.3], fill=(170, 172, 178, 255))  # the metal shutter
    d.rectangle([w * 0.52, w * 0.04, w * 0.64, w * 0.26], fill=(40, 40, 44, 255))
    d.rectangle([w * 0.12, w * 0.42, w * 0.88, w], fill=(236, 232, 220, 255))  # the label
    f = ImageFont.truetype(FONT, int(w * 0.14))
    d.text((w / 2, w * 0.62), 'holiday 99', font=f, fill=(40, 60, 140, 255), anchor='mm')
    for y in (0.8, 0.9):
        d.line([(w * 0.18, w * y), (w * 0.82, w * y)], fill=(170, 160, 150, 255), width=1)
    return im


# --- the room# --- the room --------------------------------------------------------------

def walnut(w, h, seed, base, along=False):
    r = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    if along:
        xx, yy = yy, xx
    warp = np.sin(yy / 41 + r.random() * 6) * 9 + np.sin(yy / 13 + r.random() * 6) * 2
    lines = (np.sin((xx + warp) / 4.5 + r.random() * 6) * 0.5 + 0.5) ** 3
    bands = np.sin((xx + warp * 2.2) / 23 + r.random() * 6) * 0.5 + 0.5
    g = 0.55 * lines * (0.5 + bands) + 0.45 * bands
    return np.array(base, float) + g[..., None] * np.array([13, 8, 4]) + r.normal(0, 1.6, (h, w, 1))


def stage():
    W, H = 1024, 500
    desk_y, front = 360, 440
    # wall: dark walnut planks
    wall = np.zeros((H, W, 3))
    plank = 120
    for i in range(0, W, plank):
        wall[:, i:i + plank] = walnut(min(plank, W - i), H, i, (34, 22, 14)) * (0.9 + 0.12 * ((i // plank) % 3 == 1))
        wall[:, i:i + 2] *= 0.5
    # safelight: deep red wash from the lamp top left, falling off
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt(((xx - 120) / 1.3) ** 2 + (yy + 40) ** 2)
    glow = np.clip(1 - d / 900, 0, 1) ** 1.6
    wall = wall * (0.45 + 0.55 * glow[..., None]) + glow[..., None] * np.array([120, 18, 10]) * 0.55
    img = Image.fromarray(wall.clip(0, 255).astype(np.uint8)).convert('RGBA')

    # the safelight itself, hanging top left: a dark hood, a glowing red face
    lamp = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lamp)
    ld.line([(120, 0), (120, 10)], fill=(20, 18, 18, 255), width=3)
    ld.polygon([(78, 10), (162, 10), (176, 42), (64, 42)], fill=(34, 30, 28, 255))
    ld.polygon([(78, 10), (96, 10), (82, 42), (64, 42)], fill=(52, 46, 42, 255))
    ld.rounded_rectangle([70, 38, 170, 50], radius=4, fill=(255, 70, 46, 255))
    halo = Image.new('L', (W, H), 0)
    ImageDraw.Draw(halo).ellipse([10, 0, 230, 120], fill=170)
    halo = halo.filter(ImageFilter.GaussianBlur(28))
    red = Image.new('RGBA', (W, H), (255, 60, 40, 0))
    red.putalpha(halo)
    img.alpha_composite(red)
    img.alpha_composite(lamp)

    # the drying line with prints
    line_y = lambda x: 70 + 26 * math.sin(math.pi * (x - 360) / (W + 40 - 360))  # noqa: E731
    d2 = ImageDraw.Draw(img)
    pts = [(x, line_y(x)) for x in range(360, W + 40, 8)]
    d2.line(pts, fill=(200, 190, 170, 255), width=2)
    for i, (kind, x, rot) in enumerate([('sea', 400, 3), ('lake', 548, -4), ('city', 690, 2),
                                         ('hills', 830, -3), ('palms', 960, 4)]):
        c = print_card(kind, 116, 142, 40 + i, rot)
        img.alpha_composite(c, (int(x - c.width / 2), int(line_y(x) - c.height / 2)))

    # the desk: its top running back to the wall, then its front edge
    top = walnut(W, front - desk_y, 7, (92, 60, 36), along=True)
    top *= np.linspace(0.7, 1.12, front - desk_y)[:, None, None]
    img.alpha_composite(Image.fromarray(top.clip(0, 255).astype(np.uint8)).convert('RGBA'), (0, desk_y))
    edge = walnut(W, H - front, 9, (60, 38, 22), along=True) * np.linspace(1.0, 0.55, H - front)[:, None, None]
    img.alpha_composite(Image.fromarray(edge.clip(0, 255).astype(np.uint8)).convert('RGBA'), (0, front))
    d2 = ImageDraw.Draw(img)
    d2.rectangle([0, desk_y, W, desk_y + 2], fill=(20, 12, 8, 255))  # where it meets the wall
    d2.rectangle([0, front, W, front + 2], fill=(170, 120, 78, 255))  # the lit front edge
    # a warm pool of lamp light on the desk
    pool = Image.new('L', (W, H), 0)
    ImageDraw.Draw(pool).ellipse([200, desk_y - 40, 900, front + 30], fill=80)
    pool = pool.filter(ImageFilter.GaussianBlur(50))
    warm = Image.new('RGBA', (W, H), (255, 170, 90, 0))
    warm.putalpha(pool)
    img.alpha_composite(warm)

    # the things on it: films and the instant camera on the left, the
    # chemistry in the middle (bottles behind a tray with a print coming
    # up), the digital camera and its media on the right
    base = desk_y + 58

    def shadow(x, w, y=base, depth=18):
        m = Image.new('L', (W, H), 0)
        ImageDraw.Draw(m).ellipse([x - w * 0.48, y - depth, x + w * 0.48, y + 2], fill=230)
        m = m.filter(ImageFilter.GaussianBlur(8))
        sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        sh.putalpha(m)
        img.alpha_composite(sh)

    def lit(a):
        # lit by the room: a little of the safelight's red on everything
        px = np.array(a, float)
        px[..., :3] = px[..., :3] * np.array([1.0, 0.86, 0.82]) + np.array([14, 0, 0])
        return Image.fromarray(px.clip(0, 255).astype(np.uint8))

    def stand(a, x, y=base):
        shadow(x, a.width, y)
        img.alpha_composite(lit(a), (int(x - a.width / 2), y - a.height))

    def sized(name, h):
        a = art(name)
        return a.resize((int(a.width * h / a.height), h), Image.LANCZOS)

    stand(sized('polaroid600', 150), 120)
    stand(sized('portra400', 136), 268)
    stand(sized('gold200', 136), 340)
    # chemistry: three bottles at the back, the tray in front of them
    for x, glass, text in [(450, (120, 60, 20), 'DEV'), (500, (110, 56, 22), 'STOP'), (550, (120, 60, 20), 'FIX')]:
        stand(bottle(42, 118, glass, (236, 228, 210), text), x, base - 22)
    stand(tray(190, 72, (186, 66, 54), 'sea'), 500, base + 16)
    stand(sized('flipphone', 146), 668)
    stand(sized('floppy99', 104), 800)
    # its media, lying on the desk in front
    for im, x, y in [(flat(floppy(74), 0.42, 12), 922, base + 18), (flat(sd_card(34), 0.45, -24), 742, base + 20)]:
        shadow(x, im.width, y, 10)
        img.alpha_composite(lit(im), (int(x - im.width / 2), y - im.height))

    # the name on masking tape, stuck to the wall
    tape = Image.new('RGBA', (300, 92), (0, 0, 0, 0))
    td = ImageDraw.Draw(tape)
    tw = np.array(Image.new('RGB', (300, 92), (232, 220, 186)), float)
    tw += rng.normal(0, 5, (92, 300, 1))
    edge = Image.fromarray(tw.clip(0, 255).astype(np.uint8)).convert('RGBA')
    mask = Image.new('L', (300, 92), 0)
    md = ImageDraw.Draw(mask)
    pts = [(0, 6)] + [(x, 6 + rng.integers(-3, 4)) for x in range(20, 300, 20)] + [(300, 6), (296, 46)]
    pts += [(300, 88)] + [(x, 86 + rng.integers(-3, 4)) for x in range(280, 0, -20)] + [(0, 88), (4, 46)]
    md.polygon(pts, fill=235)
    edge.putalpha(mask)
    tape.alpha_composite(edge)
    font = ImageFont.truetype(FONT, 70)
    td.text((150, 44), 'Darkroom', font=font, fill=(28, 26, 30, 255), anchor='mm')
    tape = tape.rotate(-3, resample=Image.BICUBIC, expand=True)
    tsh = Image.new('RGBA', tape.size, (0, 0, 0, 0))
    tsh.putalpha(tape.split()[-1].point(lambda v: int(v * 0.5)))
    tsh = tsh.filter(ImageFilter.GaussianBlur(5))
    img.alpha_composite(tsh, (40 + 4, 74 + 6))
    img.alpha_composite(tape, (40, 74))
    # the line under it, in chalk-ish handwriting
    small = ImageFont.truetype(FONT, 30)
    ImageDraw.Draw(img).text((58, 176), 'shoot it, develop it, pin it up.', font=small, fill=(238, 222, 200, 230))
    return img.convert('RGB')


def fit(scene, w, h):
    """The stage scaled to cover w x h, centred (cropping the long side)."""
    s = max(w / scene.width, h / scene.height)
    big = scene.resize((round(scene.width * s), round(scene.height * s)), Image.LANCZOS)
    x, y = (big.width - w) // 2, (big.height - h) // 2
    return big.crop((x, y, x + w, y + h))


if __name__ == '__main__':
    out = sys.argv[1]
    sizes = [int(v) for v in sys.argv[2:]] or [1024, 500]
    os.makedirs(out, exist_ok=True)
    scene = stage()
    for w, h in zip(sizes[::2], sizes[1::2]):
        fit(scene, w, h).save(os.path.join(out, f'header_{w}x{h}.png'))
        print(f'header_{w}x{h}.png')
