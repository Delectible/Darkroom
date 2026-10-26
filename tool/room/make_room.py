"""Draws the projector room: the wood-panelled wall and the hi-fi console.

    python3 tool/room/make_room.py        (needs Pillow + numpy)

Writes (3x, for ~1/3 dp per px):
  assets/corkboard/room_wall.webp     dark walnut panelling, tiles sideways
                                      and up/down (seamless both ways).
  assets/corkboard/room_console.webp  a low walnut hi-fi console on tapered
                                      legs: speaker cloth on the left,
                                      sliding doors with brass pulls on the
                                      right, a table lamp at the left end
                                      and a potted plant at the right.
                                      Transparent around it. The lamp's
                                      shade centre is at LAMP (fraction of
                                      the image), used by the app for its
                                      glow.
Lit from above-front by the screen: tops catch light, fronts fall off.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
OUT = os.path.join(ROOT, 'assets', 'corkboard')
LAMP = (0.105, 0.26)  # keep in sync with ProjectorRoom._lamp


def walnut(w, h, seed, base=(58, 36, 22), along=False, period=None):
    """Walnut veneer. Grain runs down the board, or [along] it (sideways);
    with [period] the grain repeats every [period] px along its run."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    if along:
        xx, yy = yy, xx
    run = period or 260
    k = 2 * math.pi / run
    # long lines that drift gently, in bands of tighter and looser figure
    warp = np.sin(yy * k + rng.random() * 6) * 9 + np.sin(yy * k * 3 + rng.random() * 6) * 2
    fine_lines = (np.sin((xx + warp) / 4.5 + rng.random() * 6) * 0.5 + 0.5) ** 3
    bands = np.sin((xx + warp * 2.2) / 23 + rng.random() * 6) * 0.5 + 0.5
    g = 0.55 * fine_lines * (0.5 + bands) + 0.45 * bands
    fine = rng.normal(0, 1, (h, w))
    fine = np.asarray(Image.fromarray(((fine + 3) * 40).clip(0, 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(0.6)), float) / 40 - 3
    a = np.array(base, float) + g[..., None] * np.array([13, 8, 4]) + fine[..., None] * 1.8
    return a


def wall():
    # 3 planks of 60 dp, 180 dp high, at 3x: tiles both ways.
    plank, n, h = 180, 3, 540
    w = plank * n
    a = np.zeros((h, w, 3))
    for i in range(n):
        tone = [0.92, 1.0, 0.86][i]
        p = walnut(plank, h, 10 + i, base=(30, 19, 12), period=h) * tone
        a[:, i * plank:(i + 1) * plank] = p
        # V-groove between planks: dark line with a lit edge
        a[:, i * plank:i * plank + 3] *= 0.45
        a[:, i * plank + 3:i * plank + 5] *= 1.25
    Image.fromarray(a.clip(0, 255).astype(np.uint8)).save(os.path.join(OUT, 'room_wall.webp'), quality=88)


def console():
    W, H = 1260, 640
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    bx0, bx1 = 40, W - 40
    top, bot, foot = 380, 550, 628
    bw, bh = bx1 - bx0, bot - top

    # tapered legs
    d = ImageDraw.Draw(im)
    for lx in (bx0 + 70, bx1 - 70):
        d.polygon([(lx - 14, bot), (lx + 14, bot), (lx + 5, foot), (lx - 5, foot)], fill=(34, 21, 13, 255))
        d.polygon([(lx - 14, bot), (lx - 6, bot), (lx - 2, foot), (lx - 5, foot)], fill=(52, 33, 20, 255))
    # brass ferrules
    for lx in (bx0 + 70, bx1 - 70):
        d.rectangle([lx - 6, foot - 14, lx + 6, foot], fill=(150, 112, 60, 255))

    body = walnut(bw, bh, 2, along=True)
    shade = np.linspace(1.12, 0.62, bh)[:, None, None]
    body *= shade
    # speaker cloth on the left
    gx0, gx1 = 26, int(bw * 0.46)
    gy0, gy1 = 22, bh - 22
    yy, xx = np.mgrid[0:gy1 - gy0, 0:gx1 - gx0]
    cloth = np.zeros((gy1 - gy0, gx1 - gx0, 3)) + np.array([60, 47, 35])
    weave = ((xx % 4 < 1) | (yy % 4 < 1)).astype(float)
    cloth -= weave[..., None] * 9
    cloth += np.sin(xx / 30.0)[..., None] * 2
    cloth *= np.linspace(1.0, 0.7, gy1 - gy0)[:, None, None]
    body[gy0:gy1, gx0:gx1] = cloth
    # recessed frame round the cloth
    body[gy0 - 4:gy0, gx0 - 4:gx1 + 4] *= 0.55
    body[gy1:gy1 + 4, gx0 - 4:gx1 + 4] *= 1.25
    body[gy0 - 4:gy1 + 4, gx0 - 4:gx0] *= 0.6
    body[gy0 - 4:gy1 + 4, gx1:gx1 + 4] *= 0.8
    # two sliding doors on the right
    dx0 = gx1 + 26
    mid = (dx0 + bw - 26) // 2
    for x in (dx0, mid, bw - 26):
        body[16:bh - 16, x - 2:x + 1] *= 0.5
        body[16:bh - 16, x + 1:x + 3] *= 1.2
    body[14:17, dx0:bw - 26] *= 0.55
    body[bh - 17:bh - 14, dx0:bw - 26] *= 1.2
    im.paste(Image.fromarray(body.clip(0, 255).astype(np.uint8)), (bx0, top))
    d = ImageDraw.Draw(im)
    # top board with a lit front edge, overhanging a little
    d.rectangle([bx0 - 10, top - 18, bx1 + 10, top], fill=(76, 50, 31, 255))
    d.rectangle([bx0 - 10, top - 4, bx1 + 10, top], fill=(110, 76, 48, 255))
    d.rectangle([bx0 - 10, top - 18, bx1 + 10, top - 15], fill=(96, 66, 42, 255))
    # brass pulls
    for px in (mid - 26, mid + 26):
        cy = top + bh // 2
        d.rounded_rectangle([px - 5, cy - 18, px + 5, cy + 18], radius=5, fill=(176, 134, 70, 255))
        d.rounded_rectangle([px - 5, cy - 18, px - 1, cy + 18], radius=3, fill=(214, 176, 108, 255))
    # plinth shadow
    d.rectangle([bx0, bot - 6, bx1, bot], fill=(26, 16, 10, 255))

    surf = top - 18
    # table lamp: brass stem on a round foot, cream drum shade (lit)
    lx = int(W * LAMP[0])
    d.ellipse([lx - 46, surf - 16, lx + 46, surf + 4], fill=(120, 88, 46, 255))
    d.ellipse([lx - 40, surf - 18, lx + 40, surf - 2], fill=(168, 128, 70, 255))
    d.rectangle([lx - 5, surf - 150, lx + 5, surf - 12], fill=(160, 122, 66, 255))
    d.rectangle([lx - 5, surf - 150, lx - 2, surf - 12], fill=(206, 166, 98, 255))
    st, sb = surf - 262, surf - 140
    shade_im = Image.new('RGBA', (180, sb - st), (0, 0, 0, 0))
    sa = np.zeros((sb - st, 180, 4))
    for y in range(sb - st):
        t = y / (sb - st)
        half = 56 + 30 * t
        for x in range(180):
            u = (x - 90) / half
            if abs(u) <= 1:
                glow = 1 - 0.35 * u * u
                sa[y, x] = [250 * glow, 214 * glow, 150 * glow, 255]
    shade_im = Image.fromarray(sa.clip(0, 255).astype(np.uint8), 'RGBA')
    im.alpha_composite(shade_im, (lx - 90, st))
    d = ImageDraw.Draw(im)
    d.line([lx - 86, sb, lx + 86, sb], fill=(255, 236, 190, 255), width=3)

    # potted plant on the right
    px = int(W * 0.885)
    pot_t, pot_b = surf - 96, surf
    d.polygon([(px - 52, pot_t), (px + 52, pot_t), (px + 40, pot_b), (px - 40, pot_b)], fill=(138, 74, 44, 255))
    d.polygon([(px - 52, pot_t), (px - 30, pot_t), (px - 22, pot_b), (px - 40, pot_b)], fill=(164, 92, 56, 255))
    d.rectangle([px - 56, pot_t - 12, px + 56, pot_t], fill=(150, 82, 50, 255))
    rng = np.random.default_rng(7)
    leaves = []
    for i in range(16):
        a = -math.pi / 2 + (rng.random() - 0.5) * 2.4
        length = 90 + rng.random() * 120
        leaves.append((a, length))
    leaves.sort(key=lambda v: v[1])
    for a, length in leaves:
        sx, sy = px, pot_t - 6
        ex, ey = sx + math.cos(a) * length, sy + math.sin(a) * length
        mx, my = (sx + ex) / 2 + math.cos(a + 1.2) * 12, (sy + ey) / 2 + math.sin(a + 1.2) * 12
        d.line([(sx, sy), (mx, my), (ex, ey)], fill=(34, 46, 24, 255), width=5)
        # an elongated leaf at the tip, darker underside
        ang = a
        lw, ll = 20, 46
        pts = []
        for k in range(13):
            t = k / 12 * math.pi * 2
            ux, uy = math.cos(t) * ll, math.sin(t) * lw * (1 - 0.3 * math.cos(t))
            pts.append((ex + ux * math.cos(ang) - uy * math.sin(ang), ey + ux * math.sin(ang) + uy * math.cos(ang)))
        tone = 0.7 + 0.5 * (1 - (ey - (pot_t - 220)) / 220)
        d.polygon(pts, fill=(int(40 * tone), int(64 * tone), int(30 * tone), 255))
        d.line([pts[0], pts[6]], fill=(int(58 * tone), int(84 * tone), int(42 * tone), 255), width=2)

    # contact shadow under the legs (soft)
    sh = Image.new('L', (W, H), 0)
    ImageDraw.Draw(sh).ellipse([bx0 - 20, foot - 14, bx1 + 20, foot + 12], fill=170)
    sh = sh.filter(ImageFilter.GaussianBlur(10))
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    shadow.putalpha(sh)
    out = Image.alpha_composite(shadow, im)
    out.save(os.path.join(OUT, 'room_console.webp'), quality=90, method=6)


if __name__ == '__main__':
    wall()
    console()
    print('room_wall.webp, room_console.webp')
