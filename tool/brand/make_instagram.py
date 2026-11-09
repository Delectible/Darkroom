import math, os, numpy as np
from PIL import Image, ImageDraw, ImageFilter
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'make_mockups.py')).read().split('opts = []')[0])
N = 1080

def icon_close(bg, h=0.74, dy=0.04, tilt=0, glow=0.0, crt=False, eyes=None):
    S = N
    cx, cy, D = mi._glyph_frame(S, S*h)
    rgb, al = mi.mark(S, cx, cy + S*dy, D, bust=False)
    a = bg * (1 - al[..., None]) + rgb
    if eyes is not None:
        e = mi._mask(S, cx, cy + S*dy, D, eyes_only=True)[..., None]
        a = a * (1 - e) + np.array(eyes) * e
    if glow:
        g = np.asarray(Image.fromarray((al*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(30))).astype(np.float32)/255
        a = a + g[..., None] * np.array([255, 255, 255]) * glow * (1 - al[..., None])
    img = to_img(a)
    if crt:
        # tube: bulged vignette, stronger scanlines over everything
        ar = np.asarray(img).astype(np.float32)
        yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
        vig = 1 - np.clip(np.hypot(xx-0.5, yy-0.5) / 0.72, 0, 1) ** 2.2
        lines = np.where((np.arange(S) % 6) < 2, 0.82, 1.0)[:, None]
        ar = ar * vig[..., None] * lines[..., None]
        img = to_img(ar)
    if tilt:
        img = img.rotate(tilt, resample=Image.BICUBIC, fillcolor=tuple(int(v) for v in bg[0, 0]))
    return img

def stamp(paper_in, paper_out, ink, top, bottom, rot=0, wear=0.07, double=True, center_ink=None, stars=True, seed=5):
    paper = radial(N, N*0.4, N*0.35, N*0.9, paper_in, paper_out)
    img = to_img(paper)
    d = ImageDraw.Draw(img)
    d.ellipse((N*0.06, N*0.06, N*0.94, N*0.94), outline=ink, width=int(N*0.02))
    if double:
        d.ellipse((N*0.095, N*0.095, N*0.905, N*0.905), outline=ink, width=int(N*0.006))
    d.ellipse((N*0.24, N*0.24, N*0.76, N*0.76), outline=ink, width=int(N*0.008))
    m = rabbit(N, N*0.32)
    ar = np.asarray(img).astype(np.float32)
    ar = ar * (1 - m[..., None]) + m[..., None] * np.array(center_ink or ink)
    img = to_img(ar)
    f = font(int(N*0.072))
    def arc(text, mid, r0, bottom_side):
        n = len(text); span = math.radians(min(150, n * 13))
        for i, ch in enumerate(text):
            t = (i + 0.5) / n - 0.5
            ang = mid + (-t if bottom_side else t) * span
            ci = Image.new('L', (int(N*0.1), int(N*0.1)), 0)
            ImageDraw.Draw(ci).text((N*0.05, N*0.05), ch, fill=255, font=f, anchor='mm')
            rot_deg = -math.degrees(ang + math.pi/2) + (180 if bottom_side else 0)
            ci = ci.rotate(rot_deg, resample=Image.BICUBIC)
            x = N/2 + r0*math.cos(ang) - ci.width/2; y = N/2 + r0*math.sin(ang) - ci.height/2
            img.paste(Image.new('RGB', ci.size, ink), (int(x), int(y)), ci)
    arc(top, -math.pi/2, N*0.335, False)
    arc(bottom, math.pi/2, N*0.335, True)
    if stars:
        dd = ImageDraw.Draw(img)
        for side in (-1, 1):
            cx = N/2 + side * N*0.335; cy = N/2
            pts = [(cx + math.cos(math.pi/2 + k*math.pi*2/5*2) * N*0.022 * (1), cy - math.sin(math.pi/2 + k*math.pi*2/5*2) * N*0.022) for k in range(5)]
            dd.polygon(pts, fill=ink)
    # broken-up ink
    ar = np.asarray(img).astype(np.float32)
    pa = np.asarray(to_img(paper)).astype(np.float32)
    inked = np.abs(ar - pa).sum(-1) > 40
    noise = np.random.default_rng(seed).random((N, N)) < wear
    blot = np.asarray(Image.fromarray((np.random.default_rng(seed+1).random((N//8, N//8))*255).astype(np.uint8)).resize((N, N), Image.BICUBIC)).astype(np.float32)/255
    fade = (blot < 0.22) & (np.random.default_rng(seed+2).random((N, N)) < 0.5)
    ar[(noise | fade) & inked] = pa[(noise | fade) & inked]
    img = grain(to_img(ar), 5)
    if rot:
        img = img.rotate(rot, resample=Image.BICUBIC, fillcolor=tuple(int(v) for v in paper[0, 0]))
    return img


img = stamp((196, 158, 112), (150, 112, 72), (34, 26, 20), 'DARKROOM', 'FILM LAB', rot=6, wear=0.1)
img.save(f'{OUT}/darkroom_instagram_1080.png')
C = 540
mask = Image.new('L', (C*4, C*4), 0); ImageDraw.Draw(mask).ellipse((0, 0, C*4, C*4), fill=255); mask = mask.resize((C, C), Image.LANCZOS)
prev = Image.new('RGB', (C + 120, C + 120), (18, 18, 20))
prev.paste(img.resize((C, C), Image.LANCZOS), (60, 60), mask)
small = img.resize((110, 110), Image.LANCZOS)
m2 = mask.resize((110, 110), Image.LANCZOS)
prev.paste(small, (C + 120 - 130, C + 120 - 130), m2)
prev.save(f'{OUT}/darkroom_instagram_preview.png')
print('ok')
