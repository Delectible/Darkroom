"""Generates every Darkroom launcher / notification icon from one drawing.

    python3 tool/icon/make_icons.py        (needs Pillow + numpy)

The mark: a rabbit with X'd-out eyes, split into red / green / blue copies
like a mis-converged CRT. Where the three overlap they add up to white.

Writes:
  Android  adaptive icon (background colour, foreground, monochrome for
           Android 13+ themed icons), legacy round icon for API 24-25,
           status-bar notification glyph.
  iOS      single-size 1024 AppIcon with the iOS 18+ Default / Dark /
           Tinted appearances (Xcode 16+).
  GitHub   docs/social_preview.png (1280x640), the repository's social
           preview: Settings > General > Social preview.
  Play     512 icon + 1024x500 feature graphic for the store listing
           (fastlane/metadata/android/en-AU/images).
"""
import json, os, shutil
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SS = 4                       # supersampling factor
BG = (14, 14, 18)            # #0E0E12, also the adaptive background colour
BG_TOP, BG_BOT = (24, 25, 31), (9, 9, 12)
SPLIT = 5                    # RGB offset in design units (design = 192 grid)
SCAN = 0.84                  # scanline brightness on the rabbit

# Design units: the mark is drawn on a 192 grid whose circle (r = 96) is
# the visible icon. Glyph-only variants use the head + ears bounding box.
GLYPH_BOX = (52, 29, 157, 158)


def _mask(S, cx, cy, D, dx=0.0, bust=True, eyes_only=False):
    """Rabbit silhouette (or just its X eyes) as a float mask 0..1."""
    u = D / 192
    m = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(m)
    P = lambda x, y: (cx + (x - 96 + dx) * u, cy + (y - 96) * u)

    def dot(p, r):
        d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=255)

    def stroke(pts, w):
        pts = [P(*p) for p in pts]
        d.line(pts, fill=255, width=max(1, round(w * u)))
        for p in pts:
            dot(p, w * u / 2)

    def ellipse(x, y, rx, ry):
        a, b = P(x - rx, y - ry), P(x + rx, y + ry)
        d.ellipse((a[0], a[1], b[0], b[1]), fill=255)

    if eyes_only:
        for ex, ey in ((80, 118), (108, 118)):
            stroke([(ex - 7, ey - 7), (ex + 7, ey + 7)], 5.5)
            stroke([(ex + 7, ey - 7), (ex - 7, ey + 7)], 5.5)
    else:
        stroke([(80, 104), (70, 40)], 22)                  # straight ear
        stroke([(110, 100), (120, 48), (146, 60)], 22)     # folded ear
        ellipse(94, 122, 42, 36)                           # head
        if bust:
            ellipse(96, 202, 72, 48)                       # shoulders
    return np.asarray(m, dtype=np.float32) / 255


def _glyph_frame(S, height):
    """cx, cy, D that centre the head + ears glyph at a given pixel height."""
    x0, y0, x1, y1 = GLYPH_BOX
    u = height / (y1 - y0)
    return S / 2 + (96 - (x0 + x1) / 2) * u, S / 2 + (96 - (y0 + y1) / 2) * u, 192 * u


def _scanlines(S, D):
    period = 4 * D / 192
    rows = (np.arange(S) % period) < period * 0.4
    return np.where(rows, SCAN, 1.0).astype(np.float32)[:, None, None]


def _background(S):
    t = np.linspace(0, 1, S, dtype=np.float32)[:, None, None]
    top, bot = np.array(BG_TOP, np.float32), np.array(BG_BOT, np.float32)
    img = np.broadcast_to(top + (bot - top) * t, (S, S, 3)).copy()
    # Material 2 "finish": a soft light from the top-left
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    img += (np.clip(1 - np.hypot(xx - 0.2, yy - 0.15) / 0.75, 0, 1) ** 2 * 18)[..., None]
    return img


def mark(S, cx, cy, D, bust=True):
    """The RGB-split rabbit as premultiplied colour (0..255) + alpha (0..1)."""
    r = _mask(S, cx, cy, D, -SPLIT, bust)
    g = _mask(S, cx, cy, D, 0, bust)
    b = _mask(S, cx, cy, D, SPLIT, bust)
    rgb = np.stack([r, g, b], -1) * 255 * _scanlines(S, D)
    alpha = np.maximum(np.maximum(r, g), b)
    eyes = _mask(S, cx, cy, D, eyes_only=True)
    return rgb * (1 - eyes)[..., None], alpha * (1 - eyes)


def _out(px, rgb, alpha=None):
    S = rgb.shape[0]
    if alpha is None:
        img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), 'RGB')
    else:   # un-premultiply for straight-alpha PNG
        a = np.clip(alpha, 0, 1)
        col = np.where(a[..., None] > 1e-4, rgb / np.maximum(a, 1e-4)[..., None], 0)
        img = Image.fromarray(np.dstack([np.clip(col, 0, 255), a * 255]).astype(np.uint8), 'RGBA')
    return img.resize((px, px), Image.LANCZOS) if S != px else img


def full_icon(px, shape='square', transparent=False):
    """Full-bleed icon: iOS / Play Store (square) or legacy Android (circle)."""
    S = px * SS
    D = S if shape == 'square' else S * 44 / 48
    rgb, a = mark(S, S / 2, S / 2, D)
    if transparent:
        return _out(px, rgb, a)
    bg = _background(S)
    img = bg * (1 - a[..., None]) + rgb          # additive light on black
    if shape == 'circle':
        cm = Image.new('L', (S, S), 0)
        r = D / 2
        ImageDraw.Draw(cm).ellipse((S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r), fill=255)
        cm = np.asarray(cm, np.float32) / 255
        return _out(px, img * cm[..., None], cm)
    return _out(px, img)


def tinted_icon(px):
    """iOS tinted appearance: greyscale, the system supplies the colour."""
    S = px * SS
    main = _mask(S, S / 2, S / 2, S)
    echo = np.maximum(_mask(S, S / 2, S / 2, S, -SPLIT), _mask(S, S / 2, S / 2, S, SPLIT))
    eyes = _mask(S, S / 2, S / 2, S, eyes_only=True)
    lum = np.maximum(main * 255, echo * 80) * (1 - eyes)
    return _out(px, np.repeat(lum[..., None], 3, -1))


def foreground(px):
    """Adaptive foreground: 108dp canvas, the 192 grid fills the 72dp mask."""
    S = px * SS
    rgb, a = mark(S, S / 2, S / 2, S * 72 / 108)
    return _out(px, rgb, a)


def monochrome(px):
    """Android 13+ themed icon: alpha only. Head + ears inside the safe zone,
    with faint offset echoes standing in for the colour split."""
    S = px * SS
    cx, cy, D = _glyph_frame(S, S * 44 / 108)
    main = _mask(S, cx, cy, D, bust=False)
    echo = np.maximum(_mask(S, cx, cy, D, -SPLIT, False), _mask(S, cx, cy, D, SPLIT, False))
    eyes = _mask(S, cx, cy, D, eyes_only=True)
    a = np.maximum(main, echo * 0.38) * (1 - eyes)
    return _out(px, np.full((S, S, 3), 255.0) * a[..., None], a)


def status_glyph(px):
    """Notification icon: white glyph, 24dp with ~2dp padding."""
    S = px * SS
    cx, cy, D = _glyph_frame(S, S * 20 / 24)
    a = _mask(S, cx, cy, D, bust=False) * (1 - _mask(S, cx, cy, D, eyes_only=True))
    return _out(px, np.full((S, S, 3), 255.0) * a[..., None], a)


def social_preview(w=1280, h=640):
    """Banner: the rabbit, the name in the app's pixel font with the same
    colour split, and the one-line pitch. 1280x640 for GitHub's social
    preview, 1024x500 for the Play Store feature graphic."""
    S = 2
    k = h / 640
    W, H = w * S, h * S
    t = np.linspace(0, 1, H, dtype=np.float32)[:, None, None]
    top, bot = np.array(BG_TOP, np.float32), np.array(BG_BOT, np.float32)
    img = np.broadcast_to(top + (bot - top) * t, (H, W, 3)).copy()

    # Rabbit (head + ears), left third. mark() works on a square canvas.
    side = H
    cx, cy, D = _glyph_frame(side, side * 0.62)
    rgb, a = mark(side, cx, cy, D, bust=False)
    x0 = round(W * 0.07)
    region = img[:, x0:x0 + side]
    img[:, x0:x0 + side] = region * (1 - a[..., None]) + rgb

    # Name: three offset copies of the text, added like light.
    font = ImageFont.truetype(os.path.join(ROOT, 'assets', 'fonts', 'DotGothic16-Regular.ttf'), round(150 * k * S))
    small = ImageFont.truetype(os.path.join(ROOT, 'assets', 'fonts', 'DotGothic16-Regular.ttf'), round(34 * k * S))
    tx, ty = round(W * 0.47), round(H * 0.30)

    def text_mask(txt, f, dx=0, dy=0):
        m = Image.new('L', (W, H), 0)
        ImageDraw.Draw(m).text((tx + dx, ty + dy), txt, font=f, fill=255)
        return np.asarray(m, np.float32) / 255

    off = round(4 * k * S)
    split = np.stack([text_mask('Darkroom', font, -off), text_mask('Darkroom', font),
                      text_mask('Darkroom', font, off)], -1)
    glow = split.max(-1)
    img = img * (1 - glow[..., None]) + split * 255 * _scanlines(H, D)[:, :, :1]
    lines = ['A camera app that makes you', 'wait for your photos.']
    for i, line in enumerate(lines):
        m = text_mask(line, small, round(6 * k * S), round(H * 0.33) + round(i * 48 * k * S))
        img = img * (1 - m[..., None]) + m[..., None] * np.array((200, 196, 188), np.float32)
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGB')
    return out.resize((w, h), Image.LANCZOS)


def save(img, *parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    return path


def main():
    res = ['android', 'app', 'src', 'main', 'res']
    dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for name, k in dens.items():
        save(full_icon(round(48 * k), 'circle'), *res, f'mipmap-{name}', 'ic_launcher.png')
        save(foreground(round(108 * k)), *res, f'mipmap-{name}', 'ic_launcher_foreground.png')
        save(monochrome(round(108 * k)), *res, f'mipmap-{name}', 'ic_launcher_monochrome.png')
        save(status_glyph(round(24 * k)), *res, f'drawable-{name}', 'ic_stat_darkroom.png')

    os.makedirs(os.path.join(ROOT, *res, 'mipmap-anydpi-v26'), exist_ok=True)
    with open(os.path.join(ROOT, *res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
''')
    with open(os.path.join(ROOT, *res, 'values', 'ic_launcher_background.xml'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#%02X%02X%02X</color>
</resources>
''' % BG)

    # iOS: one 1024 image per appearance; the system scales and masks it.
    ios = os.path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    shutil.rmtree(ios, ignore_errors=True)
    save(full_icon(1024), ios, 'AppIcon-1024.png')
    save(full_icon(1024, transparent=True), ios, 'AppIcon-Dark-1024.png')
    save(tinted_icon(1024), ios, 'AppIcon-Tinted-1024.png')
    entry = lambda f, look=None: dict(
        {'filename': f, 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'},
        **({'appearances': [{'appearance': 'luminosity', 'value': look}]} if look else {}))
    with open(os.path.join(ios, 'Contents.json'), 'w') as f:
        json.dump({'images': [entry('AppIcon-1024.png'), entry('AppIcon-Dark-1024.png', 'dark'),
                              entry('AppIcon-Tinted-1024.png', 'tinted')],
                   'info': {'version': 1, 'author': 'xcode'}}, f, indent=2)

    save(social_preview(), 'docs', 'social_preview.png')
    # Play Store listing images (published by .github/workflows/play-listing.yml).
    play = ['fastlane', 'metadata', 'android', 'en-AU', 'images']
    save(full_icon(512), *play, 'icon.png')
    save(social_preview(1024, 500), *play, 'featureGraphic.png')
    print('icons written')


if __name__ == '__main__':
    main()
