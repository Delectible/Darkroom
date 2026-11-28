"""The two plain camera icons people can pick instead of the rabbit
(Settings: "Want a different look?"): Instant, a white instant camera, and
Lens, a lens seen head-on. Drawn on a 0..1 design square (the visible icon)
so the same drawing makes every size and shape: the full icon, Android's
adaptive layers, the themed (monochrome) glyph and the notification glyph.
Plain, generic objects: no stripes, no maker's marks."""
from PIL import Image, ImageDraw

LOOKS = ('instant', 'lens')

# Background gradients (top, bottom).
BG = {
    'instant': ((246, 244, 238), (226, 222, 214)),
    'lens': ((240, 236, 228), (214, 208, 198)),
}


def background(look, S):
    top, bot = BG[look]
    im = Image.new('RGB', (S, S))
    d = ImageDraw.Draw(im)
    for y in range(S):
        t = y / max(1, S - 1)
        d.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bot)))
    return im


def _drawer(S, scale, ox, oy):
    """Maps the design square (0..1) onto an S canvas: [scale] of S wide,
    its corner at (ox, oy) as a share of S."""
    def P(x, y):
        return ((ox + x * scale) * S, (oy + y * scale) * S)

    def L(v):
        return v * scale * S
    return P, L


def foreground(look, S, scale=1.0, ox=0.0, oy=0.0, glyph=False):
    """The object on transparent. [glyph]: one flat white silhouette (holes
    cut through) for Android's themed icon and the status bar."""
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    P, L = _drawer(S, scale, ox, oy)
    W = (255, 255, 255, 255)
    CUT = (0, 0, 0, 0)

    def rr(x0, y0, x1, y1, r, fill, outline=None, width=0):
        d.rounded_rectangle([*P(x0, y0), *P(x1, y1)], radius=L(r), fill=fill, outline=outline,
                            width=round(L(width)) if width else 0)

    def circle(cx, cy, r, fill):
        d.ellipse([*P(cx - r, cy - r), *P(cx + r, cy + r)], fill=fill)

    if look == 'instant':
        if glyph:
            rr(0.16, 0.22, 0.84, 0.80, 0.09, W)
            circle(0.5, 0.50, 0.15, CUT)
            circle(0.5, 0.50, 0.09, W)
            rr(0.22, 0.28, 0.34, 0.36, 0.02, CUT)
            rr(0.28, 0.71, 0.72, 0.75, 0.01, CUT)
        else:
            rr(0.16, 0.22, 0.84, 0.80, 0.09, (250, 250, 248, 255), (200, 196, 188, 255), 0.006)
            circle(0.5, 0.50, 0.15, (40, 40, 44, 255))
            circle(0.5, 0.50, 0.09, (20, 24, 32, 255))
            circle(0.47, 0.47, 0.025, (170, 190, 210, 255))
            rr(0.22, 0.28, 0.34, 0.36, 0.02, (40, 40, 44, 255))
            circle(0.74, 0.32, 0.03, (230, 70, 60, 255))
            rr(0.28, 0.72, 0.72, 0.75, 0.01, (60, 60, 64, 255))
    else:  # lens
        if glyph:
            circle(0.5, 0.5, 0.38, W)
            circle(0.5, 0.5, 0.31, CUT)
            circle(0.5, 0.5, 0.20, W)
            circle(0.42, 0.42, 0.055, CUT)
        else:
            for r, c in ((0.38, (30, 30, 34)), (0.33, (70, 70, 76)), (0.30, (20, 20, 24)), (0.20, (34, 46, 78)),
                         (0.12, (20, 26, 46))):
                circle(0.5, 0.5, r, c + (255,))
            circle(0.42, 0.42, 0.06, (150, 110, 200, 255))
            circle(0.58, 0.60, 0.025, (120, 200, 190, 255))
    return im


def full(look, px, SS=4):
    """Square full-bleed icon (iOS, before the system masks it)."""
    S = px * SS
    im = background(look, S).convert('RGBA')
    im.alpha_composite(foreground(look, S))
    return im.convert('RGB').resize((px, px), Image.LANCZOS)


def dark(look, px, SS=4):
    """iOS dark appearance: the object alone (iOS puts it on its dark backing)."""
    S = px * SS
    return foreground(look, S).resize((px, px), Image.LANCZOS)


def tinted(look, px, SS=4):
    """iOS tinted appearance: greyscale on black; the system adds the tint."""
    S = px * SS
    g = foreground(look, S, glyph=True)
    out = Image.new('RGB', (S, S), (0, 0, 0))
    out.paste(g, (0, 0), g)
    return out.resize((px, px), Image.LANCZOS)


def legacy_round(look, px, SS=4):
    """Round icon for Android 7.x (no adaptive icons)."""
    S = px * SS
    D = S * 44 / 48
    im = background(look, S).convert('RGBA')
    im.alpha_composite(foreground(look, S))
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).ellipse(((S - D) / 2, (S - D) / 2, (S + D) / 2, (S + D) / 2), fill=255)
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out.resize((px, px), Image.LANCZOS)


def adaptive_background(look, px):
    return background(look, px)


def adaptive_foreground(look, px, SS=4):
    """108 dp canvas; the design square fills the 72 dp the mask shows."""
    S = px * SS
    k = 72 / 108
    return foreground(look, S, k, (1 - k) / 2, (1 - k) / 2).resize((px, px), Image.LANCZOS)


def monochrome(look, px, SS=4):
    """Android 13+ themed icon: a white glyph inside the 66 dp safe zone."""
    S = px * SS
    k = 60 / 108
    return foreground(look, S, k, (1 - k) / 2, (1 - k) / 2, glyph=True).resize((px, px), Image.LANCZOS)


def status_glyph(look, px, SS=4):
    """Notification icon: white glyph on 24 dp."""
    S = px * SS
    k = 26 / 24  # the drawing has its own margin; this makes it ~20 dp
    return foreground(look, S, k, (1 - k) / 2, (1 - k) / 2, glyph=True).resize((px, px), Image.LANCZOS)
