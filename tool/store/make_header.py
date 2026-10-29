"""Store art from the app's own world: a darkroom wall under the safelight,
prints drying on a line, the films and cameras on a walnut desk, and the
name on a strip of masking tape.

    python3 tool/store/make_header.py OUT_DIR [W H ...]   (Pillow + numpy)
    SAFE=0.14 python3 tool/store/make_header.py OUT 3840 1646 5244 2950 3840 2560

Writes header_WxH.png for each size (default 1024x500, Play's feature
graphic). Apple (App Store Connect, product page header / search
results): 3840x1646 (21:9), 5244x2950 (16:9, PNG only), 3840x2560 (3:2
search); PNG, no transparency, key art in the centre (SAFE). Each is
drawn at its own size from a 1024x500 layout; taller ones get more wall,
wider ones a longer line and desk. The prints are
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


def print_card(kind, w, h, seed, rot, k=1.0):
    """A print on a peg: returns (image, grip) where grip is the image point
    that sits on the line."""
    w, h = int(w * k), int(h * k)
    border = int(w * 0.07)
    card = Image.new('RGBA', (w, h), (244, 240, 230, 255))
    # the picture is drawn at its 1x size and scaled, so its detail stays the same at any size
    pw, ph = w - 2 * border, h - 2 * border - int(h * 0.06)
    card.paste(photo(kind, max(8, int(pw / k)), max(8, int(ph / k)), seed).resize((pw, ph), Image.LANCZOS), (border, border))
    # paper isn't perfectly flat: a faint shading across it
    shade = Image.linear_gradient('L').rotate(90).resize((w, h))
    card.alpha_composite(Image.merge('RGBA', [Image.new('L', (w, h), 0)] * 3 + [shade.point(lambda v: v // 14)]))
    pad = int(30 * k)
    sh = Image.new('RGBA', (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 150), (pad + int(6 * k), pad + int(10 * k), pad + w + int(6 * k), pad + h + int(10 * k)))
    sh = sh.filter(ImageFilter.GaussianBlur(9 * k))
    sh.alpha_composite(card, (pad, pad))
    # a wooden peg, its jaw on the line at (cx, grip)
    d = ImageDraw.Draw(sh)
    cx, grip = pad + w // 2, pad - int(12 * k)
    q = lambda v: v * k  # noqa: E731
    d.rounded_rectangle([cx - q(6), grip - q(12), cx + q(6), pad + q(16)], radius=q(3), fill=(196, 160, 112, 255))
    d.rounded_rectangle([cx - q(6), grip - q(12), cx - q(2), pad + q(16)], radius=q(2), fill=(222, 190, 140, 255))
    d.line([(cx - q(6), grip), (cx + q(6), grip)], fill=(120, 92, 60, 255), width=max(1, int(q(2))))
    d.rectangle([cx - q(8), pad - q(4), cx + q(8), pad], fill=(150, 150, 155, 255))
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


def bottle(w, h, glass, label, text, capped=True, tilt=0.0):
    """A chemistry bottle: shouldered glass, black cap (or open, the neck's
    mouth showing), a paper label put on a little crooked."""
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
    if capped:
        d.rounded_rectangle([w / 2 - neck / 2 - w * 0.05, 0, w / 2 + neck / 2 + w * 0.05, h * 0.11], radius=w * 0.07,
                            fill=(24, 22, 22, 255))
        d.rectangle([w / 2 - neck / 2 - w * 0.05, h * 0.02, w / 2 - neck / 2 + w * 0.07, h * 0.1], fill=(60, 58, 56, 255))
    else:
        # the open mouth: a lip and the dark inside
        d.ellipse([w / 2 - neck / 2 - 1, h * 0.06, w / 2 + neck / 2 + 1, h * 0.11], fill=(150, 90, 50, 255))
        d.ellipse([w / 2 - neck / 2 + w * 0.04, h * 0.07, w / 2 + neck / 2 - w * 0.04, h * 0.1], fill=(30, 16, 10, 255))
    # a dribble dried down the side under the mouth
    if not capped:
        d.line([(w * 0.62, h * 0.2), (w * 0.64, h * 0.33), (w * 0.63, h * 0.44)], fill=tuple(int(c * 1.2) for c in glass) + (200,),
               width=max(1, int(w * 0.04)))
    ly0, ly1 = int(h * 0.48), int(h * 0.82)
    lab = shaded(int(w * 0.84), ly1 - ly0, [c * 0.7 for c in label], label, hi=0.35)
    lim = Image.fromarray(lab.clip(0, 255).astype(np.uint8)).convert('RGBA')
    ld = ImageDraw.Draw(lim)
    f = ImageFont.truetype(LABEL, max(6, int((ly1 - ly0) * 0.5)))
    ld.text((lim.width / 2, lim.height * 0.45), text, font=f, fill=(30, 26, 24, 255), anchor='mm')
    fs = ImageFont.truetype(LABEL, max(6, int((ly1 - ly0) * 0.18)))
    ld.text((lim.width / 2, lim.height * 0.82), 'DARKROOM', font=fs, fill=(80, 70, 60, 255), anchor='mm')
    # a faint stain where a drip ran over the label (only on the open one)
    if not capped:
        stain = Image.new('RGBA', lim.size, (0, 0, 0, 0))
        ImageDraw.Draw(stain).ellipse([lim.width * 0.6, -lim.height * 0.1, lim.width * 0.9, lim.height * 0.5], fill=(150, 110, 60, 45))
        lim.alpha_composite(stain)
    lim = lim.rotate(tilt, resample=Image.BICUBIC)
    im.alpha_composite(lim, (int(w * 0.08), ly0))
    return im


def cap(w):
    """A bottle cap lying on its side: a short ribbed cylinder."""
    h = int(w * 0.62)
    im = Image.fromarray(shaded(w, h, (10, 10, 10), (70, 66, 64), hi=0.5).transpose(1, 0, 2)[:h, :w].clip(0, 255).astype(np.uint8)
                         if False else shaded(h, w, (10, 10, 10), (74, 70, 66), hi=0.35).transpose(1, 0, 2).clip(0, 255).astype(np.uint8))
    im = Image.fromarray(np.ascontiguousarray(im)).convert('RGBA').resize((w, h))
    d = ImageDraw.Draw(im)
    for x in range(2, w - 2, max(2, w // 9)):
        d.line([(x, 1), (x, h - 2)], fill=(14, 14, 14, 180), width=1)
    d.ellipse([w - w * 0.22, 0, w + w * 0.18, h - 1], fill=(36, 34, 32, 255))  # its open end, facing out
    return im


def _coeffs(dst, src):
    """PIL perspective coefficients mapping output points dst to input src."""
    m = []
    for (x, y), (u, v) in zip(dst, src):
        m.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        m.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    a = np.array(m, float)
    b = np.array([c for p in src for c in p], float)
    return np.linalg.solve(a, b).tolist()


def tray(w, h, colour, print_kind, k=1.0):
    """A developing tray seen from a little above: rim, the bath, a print
    lying in it in the same perspective, its front face, a pair of tongs."""
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    top = h * 0.72
    inset = w * 0.06
    rim = [(inset, 0), (w - inset, 0), (w, top), (0, top)]
    d.polygon(rim, fill=tuple(colour) + (255,))
    b = 5 * k
    bath = [(inset + b, b), (w - inset - b, b), (w - b * 1.4, top - b), (b * 1.4, top - b)]
    d.polygon(bath, fill=(74, 52, 40, 255))
    # the print: a card warped onto the bath's floor (narrower at the back)

    def on_floor(u, v):
        # u, v in 0..1 across / back-to-front of the bath's floor
        y = bath[0][1] + (bath[3][1] - bath[0][1]) * v
        left = bath[0][0] + (bath[3][0] - bath[0][0]) * v
        right = bath[1][0] + (bath[2][0] - bath[1][0]) * v
        return (left + (right - left) * u, y)

    pw, ph = 300, 220
    pic = photo(print_kind, pw - 16, ph - 16, 77).convert('RGBA')
    px = np.array(pic, float)
    px[..., :3] = px[..., :3] * 0.8 + 255 * 0.14  # coming up
    card = Image.new('RGBA', (pw, ph), (236, 232, 220, 255))
    card.alpha_composite(Image.fromarray(px.clip(0, 255).astype(np.uint8)), (8, 8))
    quad = [on_floor(0.22, 0.12), on_floor(0.8, 0.16), on_floor(0.78, 0.9), on_floor(0.18, 0.86)]
    warped = card.transform((w, h), Image.PERSPECTIVE, _coeffs(quad, [(0, 0), (pw, 0), (pw, ph), (0, ph)]), Image.BICUBIC)
    im.alpha_composite(warped)
    sheen = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).polygon(bath, fill=(255, 150, 120, 46))
    # a ripple of light across the liquid
    ImageDraw.Draw(sheen).line([on_floor(0.05, 0.3), on_floor(0.5, 0.22), on_floor(0.95, 0.34)], fill=(255, 220, 200, 60),
                               width=max(1, int(2 * k)))
    im.alpha_composite(sheen)
    face = [(0, top), (w, top), (w - 3 * k, h), (3 * k, h)]
    d.polygon(face, fill=tuple(int(c * 0.72) for c in colour) + (255,))
    d.line([(0, top), (w, top)], fill=tuple(min(255, int(c * 1.15)) for c in colour) + (255,), width=max(1, int(2 * k)))
    # bamboo tongs resting across the rim, rubber tips in the bath
    t0, t1 = (w * 0.86, -h * 0.1), on_floor(0.62, 0.45)
    for off in (0, 4 * k):
        d.line([(t0[0] + off, t0[1]), (t1[0] + off, t1[1])], fill=(214, 186, 128, 255), width=max(1, int(3 * k)))
    d.line([(t1[0] - 2 * k, t1[1]), (t1[0] + 6 * k, t1[1] + 4 * k)], fill=(170, 40, 30, 255), width=max(1, int(4 * k)))
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
    d.text((w / 2, h * 0.52), 'SD', font=ImageFont.truetype(LABEL, int(w * 0.3)), fill=(28, 52, 110, 255), anchor='mm')
    d.text((w / 2, h * 0.74), '128MB', font=ImageFont.truetype(LABEL, int(w * 0.16)), fill=(60, 60, 70, 255), anchor='mm')
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
    d.text((w / 2, w * 0.62), 'holiday 99', font=ImageFont.truetype(FONT, int(w * 0.14)), fill=(40, 60, 140, 255), anchor='mm')
    for y in (0.8, 0.9):
        d.line([(w * 0.18, w * y), (w * 0.82, w * y)], fill=(170, 160, 150, 255), width=max(1, w // 120))
    return im


# --- the room --------------------------------------------------------------

def walnut(w, h, seed, base, along=False, k=1.0):
    r = np.random.default_rng(seed)
    yy, xx = (np.mgrid[0:h, 0:w].astype(float)) / k
    if along:
        xx, yy = yy, xx
    warp = np.sin(yy / 41 + r.random() * 6) * 9 + np.sin(yy / 13 + r.random() * 6) * 2
    lines = (np.sin((xx + warp) / 4.5 + r.random() * 6) * 0.5 + 0.5) ** 3
    bands = np.sin((xx + warp * 2.2) / 23 + r.random() * 6) * 0.5 + 0.5
    g = 0.55 * lines * (0.5 + bands) + 0.45 * bands
    return np.array(base, float) + g[..., None] * np.array([13, 8, 4]) + r.normal(0, 1.6, (h, w, 1))


def foot_of(a):
    """The bottom of the object itself in a render (below it is only its
    soft contact shadow)."""
    al = np.array(a.split()[-1])
    rows = np.where((al > 200).sum(axis=1) > al.shape[1] * 0.05)[0]
    return int(rows[-1]) if len(rows) else a.height


def stage(OW, OH, safe=0.0):
    """The scene at OW x OH pixels: laid out on a stage 1024 units wide (more
    if the picture is wider than 2.05:1) and 500 tall (more if taller), the
    desk along the bottom, the extra room going to the wall and the line.
    [safe] (0..1) keeps that much of the width as margin round the scene, so
    nothing that matters sits near an edge (Apple crops its art per device);
    the extra height then goes half above, half below."""
    Lw = max(1024.0, 500.0 * OW / OH) / (1 - safe)
    Lh = Lw * OH / OW
    k = OW / Lw
    ox, oy = (Lw - 1024) / 2, (Lh - 500) * (0.5 if safe else 1.0)
    X = lambda v: (v + ox) * k  # noqa: E731
    Y = lambda v: (v + oy) * k  # noqa: E731
    K = lambda v: v * k  # noqa: E731
    W, H = OW, OH
    desk_y, front = Y(360), Y(440)

    wall = np.zeros((H, W, 3))
    plank = max(1, int(K(120)))
    for i in range(0, W, plank):
        wall[:, i:i + plank] = walnut(min(plank, W - i), H, i, (34, 22, 14), k=k) * (0.9 + 0.12 * ((i // plank) % 3 == 1))
        wall[:, i:i + max(1, int(K(2)))] *= 0.5
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt(((xx - X(120)) / 1.3) ** 2 + (yy - Y(-40)) ** 2) / k
    glow = np.clip(1 - d / 900, 0, 1) ** 1.6
    wall = wall * (0.45 + 0.55 * glow[..., None]) + glow[..., None] * np.array([120, 18, 10]) * 0.55
    img = Image.fromarray(wall.clip(0, 255).astype(np.uint8)).convert('RGBA')

    # the safelight, hanging top left on its cord
    lamp = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lamp)
    ld.line([(X(120), 0), (X(120), Y(10))], fill=(20, 18, 18, 255), width=max(1, int(K(3))))
    ld.polygon([(X(78), Y(10)), (X(162), Y(10)), (X(176), Y(42)), (X(64), Y(42))], fill=(34, 30, 28, 255))
    ld.polygon([(X(78), Y(10)), (X(96), Y(10)), (X(82), Y(42)), (X(64), Y(42))], fill=(52, 46, 42, 255))
    ld.rounded_rectangle([X(70), Y(38), X(170), Y(50)], radius=K(4), fill=(255, 70, 46, 255))
    halo = Image.new('L', (W, H), 0)
    ImageDraw.Draw(halo).ellipse([X(10), Y(0), X(230), Y(120)], fill=170)
    halo = halo.filter(ImageFilter.GaussianBlur(K(28)))
    red = Image.new('RGBA', (W, H), (255, 60, 40, 0))
    red.putalpha(halo)
    img.alpha_composite(red)
    img.alpha_composite(lamp)

    # the drying line: tied to a nail at each end, sagging between them
    x0, x1 = 360.0, (990.0 if safe else Lw - ox - 34)
    line_y = lambda x: 58 + 28 * math.sin(math.pi * (x - x0) / (x1 - x0))  # noqa: E731
    d2 = ImageDraw.Draw(img)
    d2.line([(X(x), Y(line_y(x))) for x in np.linspace(x0, x1, 120)], fill=(200, 190, 170, 255), width=max(1, int(K(2))))
    for nx in (x0, x1):
        cxn, cyn = X(nx), Y(line_y(nx))
        d2.ellipse([cxn - K(5), cyn - K(5), cxn + K(5), cyn + K(5)], fill=(150, 120, 70, 255))  # nail head
        d2.ellipse([cxn - K(3), cyn - K(4), cxn + K(1), cyn], fill=(220, 190, 130, 255))
        # the knot and its loose tail
        d2.line([(cxn, cyn + K(2)), (cxn + K(3 if nx == x0 else -3), cyn + K(16))], fill=(190, 180, 160, 255), width=max(1, int(K(2))))
    span = x1 - x0
    for i, (kind, f, rot) in enumerate([('sea', 0.07, 3), ('lake', 0.28, -4), ('city', 0.5, 2),
                                         ('hills', 0.71, -3), ('palms', 0.92, 4)]):
        x = x0 + span * f
        c = print_card(kind, 116, 142, 40 + i, rot, k)
        img.alpha_composite(c, (int(X(x) - c.width / 2), int(Y(line_y(x)) - c.height / 2)))

    # the desk: its top running back to the wall, then its front edge
    th, fh = int(front - desk_y), H - int(front)
    top = walnut(W, th, 7, (92, 60, 36), along=True, k=k) * np.linspace(0.7, 1.12, th)[:, None, None]
    img.alpha_composite(Image.fromarray(top.clip(0, 255).astype(np.uint8)).convert('RGBA'), (0, int(desk_y)))
    edge = walnut(W, fh, 9, (60, 38, 22), along=True, k=k) * np.linspace(1.0, 0.55, fh)[:, None, None]
    img.alpha_composite(Image.fromarray(edge.clip(0, 255).astype(np.uint8)).convert('RGBA'), (0, int(front)))
    d2 = ImageDraw.Draw(img)
    d2.rectangle([0, desk_y, W, desk_y + K(2)], fill=(20, 12, 8, 255))
    d2.rectangle([0, front, W, front + K(2)], fill=(170, 120, 78, 255))
    # wear on the desk: a mug ring, a drip of chemistry, a few scratches
    wear = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wear)
    wd.ellipse([X(600), Y(420), X(648), Y(434)], outline=(40, 22, 12, 90), width=max(1, int(K(2))))
    wd.ellipse([X(395), Y(422), X(425), Y(430)], fill=(60, 30, 14, 70))
    r = np.random.default_rng(5)
    for _ in range(14):
        sx, sy = r.uniform(0, 1024), r.uniform(366, 436)
        wd.line([(X(sx), Y(sy)), (X(sx + r.uniform(8, 30)), Y(sy + r.uniform(-2, 2)))], fill=(160, 120, 80, 50), width=1)
    img.alpha_composite(wear)
    pool = Image.new('L', (W, H), 0)
    ImageDraw.Draw(pool).ellipse([X(200), Y(320), X(900), Y(470)], fill=80)
    pool = pool.filter(ImageFilter.GaussianBlur(K(50)))
    warm = Image.new('RGBA', (W, H), (255, 170, 90, 0))
    warm.putalpha(pool)
    img.alpha_composite(warm)

    base = 418.0

    def shadow(x, w, y, depth=12, foot=None):
        # a soft shadow tucked under the thing, and a tight dark line where
        # it actually touches the desk (the part that sells "resting on it")
        m = Image.new('L', (W, H), 0)
        md = ImageDraw.Draw(m)
        md.ellipse([X(x) - w * 0.52, Y(y - depth), X(x) + w * 0.52, Y(y + 4)], fill=120)
        m = m.filter(ImageFilter.GaussianBlur(K(6)))
        c = Image.new('L', (W, H), 0)
        fw = (foot or w * 0.9) / 2
        ImageDraw.Draw(c).rounded_rectangle([X(x) - fw, Y(y) - K(3), X(x) + fw, Y(y) + K(2.5)], radius=K(2), fill=235)
        c = c.filter(ImageFilter.GaussianBlur(K(1.6)))
        m = Image.fromarray(np.maximum(np.array(m), np.array(c)))
        sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        sh.putalpha(m)
        img.alpha_composite(sh)

    def lit(a):
        # the room's light: a touch of the safelight's red, and the lower
        # part of everything a little darker (the desk shades it)
        px = np.array(a, float)
        px[..., :3] = px[..., :3] * np.array([1.0, 0.86, 0.82]) + np.array([14, 0, 0])
        ramp = np.clip((np.arange(a.height) / max(1, a.height) - 0.7) / 0.3, 0, 1) * 0.18
        px[..., :3] *= (1 - ramp)[:, None, None]
        return Image.fromarray(px.clip(0, 255).astype(np.uint8))

    def foot_width(a, foot):
        al = np.array(a.split()[-1])
        cols = np.where(al[max(0, foot - 2)] > 200)[0]
        return (cols[-1] - cols[0]) if len(cols) else a.width * 0.9

    def stand(a, x, y=base, foot=None):
        foot = a.height if foot is None else foot
        shadow(x, a.width, y, foot=foot_width(a, foot) if foot < a.height else None)
        img.alpha_composite(lit(a), (int(X(x) - a.width / 2), int(Y(y) - foot + K(1))))

    def render(name, h, x, y=base, turn=0):
        """A rendered thing, [h] tall from its foot to its top (true scale:
        the instant camera ~10 cm = 120, a film canister ~5 cm = 62)."""
        a = art(name)
        if turn:
            a = a.rotate(turn, resample=Image.BICUBIC, expand=True)
            a = a.crop(a.getbbox())
        f = foot_of(a)
        s = K(h) / f
        a = a.resize((max(1, int(a.width * s)), max(1, int(a.height * s))), Image.LANCZOS)
        stand(a, x, y, int(f * s))

    # left: the instant camera, a roll standing and one lying beside it
    render('polaroid600', 144, 112)
    render('portra400', 74, 246, base + 2)
    render('gold200', 48, 304, base + 14, turn=88)
    # the chemistry: three bottles at the back, DEV opened, its cap set
    # down right beside it
    bh, bw = 154, 50
    for x, glass, text, capped, tilt in [(386, (120, 60, 20), 'DEV', False, 2), (440, (110, 56, 22), 'STOP', True, -1),
                                         (494, (120, 60, 20), 'FIX', True, 3)]:
        stand(bottle(int(K(bw)), int(K(bh)), glass, (236, 228, 210), text, capped, tilt), x, base - 30)
    lid = Image.new('RGBA', (int(K(bw * 0.44)), int(K(bh * 0.11))), (0, 0, 0, 0))
    ldr = ImageDraw.Draw(lid)
    ldr.rounded_rectangle([0, 0, lid.width - 1, lid.height - 1], radius=K(3), fill=(24, 22, 22, 255))
    ldr.rectangle([0, lid.height * 0.18, K(5), lid.height * 0.9], fill=(60, 58, 56, 255))
    stand(lid, 346, base - 28)
    stand(tray(int(K(222)), int(K(68)), (186, 66, 54), 'sea', k), 472, base + 18)
    # right: the single-use camera, the digital camera and its media, a roll
    render('superia400', 72, 644, base + 4)
    render('floppy99', 100, 816)
    render('cinestill800t', 74, 972, base - 6)
    for im, x, y in [(flat(sd_card(int(K(36))), 0.45, -20), 718, base + 20), (flat(floppy(int(K(84))), 0.42, 10), 906, base + 22)]:
        shadow(x, im.width, y, 4)
        img.alpha_composite(lit(im), (int(X(x) - im.width / 2), int(Y(y) - im.height)))

    # the name on masking tape, stuck to the wall
    tw_, th_ = int(K(300)), int(K(92))
    tw = np.array(Image.new('RGB', (tw_, th_), (232, 220, 186)), float) + rng.normal(0, 5, (th_, tw_, 1))
    edge = Image.fromarray(tw.clip(0, 255).astype(np.uint8)).convert('RGBA')
    mask = Image.new('L', (tw_, th_), 0)
    pts = [(0, K(6))] + [(K(x), K(6 + rng.integers(-3, 4))) for x in range(20, 300, 20)] + [(K(300), K(6)), (K(296), K(46))]
    pts += [(K(300), K(88))] + [(K(x), K(86 + rng.integers(-3, 4))) for x in range(280, 0, -20)] + [(0, K(88)), (K(4), K(46))]
    ImageDraw.Draw(mask).polygon(pts, fill=235)
    edge.putalpha(mask)
    tape = Image.new('RGBA', (tw_, th_), (0, 0, 0, 0))
    tape.alpha_composite(edge)
    ImageDraw.Draw(tape).text((K(150), K(44)), 'Darkroom', font=ImageFont.truetype(FONT, int(K(70))), fill=(28, 26, 30, 255), anchor='mm')
    tape = tape.rotate(-3, resample=Image.BICUBIC, expand=True)
    tsh = Image.new('RGBA', tape.size, (0, 0, 0, 0))
    tsh.putalpha(tape.split()[-1].point(lambda v: int(v * 0.5)))
    tsh = tsh.filter(ImageFilter.GaussianBlur(K(5)))
    img.alpha_composite(tsh, (int(X(44)), int(Y(80))))
    img.alpha_composite(tape, (int(X(40)), int(Y(74))))
    ImageDraw.Draw(img).text((X(60), Y(176)), TAGLINE, font=ImageFont.truetype(FONT, int(K(32))), fill=(238, 222, 200, 230))
    # the finish: a soft vignette and a whisper of grain over everything
    out = np.array(img.convert('RGB'), float)
    yy, xx = np.mgrid[0:H, 0:W]
    v = ((xx / W - 0.5) ** 2 * 1.2 + (yy / H - 0.45) ** 2 * 1.6)
    out *= (1 - np.clip(v * 0.55, 0, 0.35))[..., None]
    out += np.random.default_rng(3).normal(0, 2.2, (H, W, 1))
    return Image.fromarray(out.clip(0, 255).astype(np.uint8))


TAGLINE = 'Photos worth waiting for.'


if __name__ == '__main__':
    out = sys.argv[1]
    sizes = [int(v) for v in sys.argv[2:]] or [1024, 500]
    os.makedirs(out, exist_ok=True)
    safe = float(os.environ.get('SAFE', '0'))
    for w, h in zip(sizes[::2], sizes[1::2]):
        stage(w, h, safe).save(os.path.join(out, f'header_{w}x{h}.png'), optimize=True)
        print(f'header_{w}x{h}.png')
