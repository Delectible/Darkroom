import sys, os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
R = '/home/user/Darkroom'
sys.path.insert(0, R + '/tool/icon')
import make_icons as mi
OUT = os.path.dirname(os.path.abspath(__file__))
N = 720  # each mockup, square

def rabbit(S, h, bust=False, eyes=False):
    cx, cy, D = mi._glyph_frame(S, h)
    m = mi._mask(S, cx, cy, D, bust=bust)
    if not eyes:
        e = mi._mask(S, cx, cy, D, eyes_only=True)
        m = m * (1 - e)
    return m

def to_img(a): return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
def radial(S, cx, cy, r, inner, outer, power=1.6):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    t = np.clip(np.hypot(xx - cx, yy - cy) / r, 0, 1) ** power
    a, b = np.array(inner, np.float32), np.array(outer, np.float32)
    return a + (b - a) * t[..., None]
def grain(img, amt=10, seed=1):
    rng = np.random.default_rng(seed)
    a = np.asarray(img).astype(np.float32)
    a += rng.normal(0, amt, a.shape[:2])[..., None]
    return to_img(a)
font = lambda size, bold=True: ImageFont.truetype(R + ('/assets/fonts/BarlowSemiCondensed-Medium.ttf'), size)

opts = []

# 1 Safelight silhouette: black rabbit against a red bulb's glow
bg = radial(N, N*0.5, N*0.36, N*0.75, (232, 46, 30), (40, 4, 4), 0.9)
m = rabbit(N, N*0.62, bust=True)[..., None]
a = bg * (1 - m) + np.array([10, 2, 2]) * m
rim = np.asarray(Image.fromarray((m[...,0]*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6))).astype(np.float32)/255
edge = np.clip(rim - m[...,0], 0, 1)[..., None]
a = a + edge * np.array([255, 90, 60]) * 0.5
opts.append(('Safelight', grain(to_img(a), 7)))

# 2 Neon rabbit glowing safelight-red on black
m = rabbit(N, N*0.6)
glow = np.asarray(Image.fromarray((m*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(28))).astype(np.float32)/255
outline = np.asarray(Image.fromarray((m*255).astype(np.uint8)).filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(7))).astype(np.float32)/255
base = radial(N, N/2, N/2, N*0.8, (26, 8, 8), (6, 3, 3))
a = base + glow[..., None] * np.array([255, 40, 30]) * 0.9 + outline[..., None] * np.array([255, 120, 100])
opts.append(('Red neon', to_img(a)))

# 3 The icon, bigger and closer (head fills the circle)
S = N
cx, cy, D = mi._glyph_frame(S, S*0.74)
rgb, al = mi.mark(S, cx, cy + S*0.04, D, bust=False)
bg = mi._background(S)
a = bg * (1 - al[..., None]) + rgb
opts.append(('Icon, close', to_img(a)))

# 4 Instant print of the sunset, the rabbit inked in its strip, on cork
cork = Image.open(R + '/assets/corkboard/room_wall.webp').convert('RGB') if False else None
bgc = radial(N, N/2, N/2, N*0.8, (176, 132, 86), (110, 78, 48))
img = grain(to_img(bgc), 16, 3)
pw = int(N*0.6); ph = int(pw*1.22)
pr = Image.new('RGB', (pw, ph), (236, 234, 228))
pic = Image.open(R + '/assets/samples/sunset.jpg').convert('RGB')
s = int(pw*0.88); side = min(pic.size)
pic = pic.crop(((pic.width-side)//2, 0, (pic.width-side)//2+side, side)).resize((s, s), Image.LANCZOS)
pr.paste(pic, ((pw-s)//2, int(pw*0.06)))
rm = rabbit(int(ph*0.2), ph*0.16)
ink = Image.new('RGB', rm.shape[::-1], (31, 42, 68))
pr.paste(ink, ((pw-rm.shape[1])//2, int(pw*0.06)+s+int(ph*0.015)), Image.fromarray((rm*255).astype(np.uint8)))
pr = pr.convert('RGBA').rotate(-6, expand=True, resample=Image.BICUBIC)
sh = Image.new('RGBA', pr.size, (0,0,0,0)); sh.putalpha(pr.split()[3].point(lambda v: v*0.55))
sh = Image.merge('RGBA', (*[Image.new('L', pr.size, 0)]*3, sh.split()[3])).filter(ImageFilter.GaussianBlur(10))
img = img.convert('RGBA')
ox, oy = (N-pr.width)//2, (N-pr.height)//2
img.alpha_composite(sh, (ox+8, oy+14)); img.alpha_composite(pr, (ox, oy))
opts.append(('Instant on cork', img.convert('RGB')))

# 5 Developing tray: the rabbit surfacing on a blue-grey sheet under red light
a = np.zeros((N, N, 3), np.float32) + np.array([60, 10, 10])
sheet = (int(N*0.12), int(N*0.16), int(N*0.88), int(N*0.86))
img = to_img(radial(N, N*0.45, N*0.4, N*0.9, (120, 24, 20), (25, 4, 4)))
d = ImageDraw.Draw(img)
d.rounded_rectangle((N*0.04, N*0.06, N*0.96, N*0.95), 28, fill=(34, 10, 10), outline=(70, 22, 20), width=6)
d.rectangle(sheet, fill=(150, 160, 172))
m = rabbit(N, N*0.5, bust=True)
ar = np.asarray(img).astype(np.float32)
ar = ar * (1 - m[..., None]*0.6) + m[..., None] * np.array([20, 16, 22]) * 0.6
# the red light over everything, and a ripple's sheen
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
ar = ar * np.array([1.25, 0.55, 0.5])
sheen = (np.sin((xx*0.6 + yy) / N * 22) * 0.5 + 0.5) ** 8 * 28
ar += sheen[..., None] * np.array([1, 0.4, 0.35])
opts.append(('In the tray', grain(to_img(ar), 6)))

# 6 The Golden canister on warm orange
can = Image.open(R + '/assets/artwork/gold200.webp').convert('RGBA')
img = to_img(radial(N, N*0.4, N*0.35, N*0.9, (247, 168, 72), (196, 92, 34))).convert('RGBA')
c = can.resize((int(N*0.92), int(N*0.92)), Image.LANCZOS).rotate(12, resample=Image.BICUBIC)
sh = Image.merge('RGBA', (*[Image.new('L', c.size, 0)]*3, c.split()[3].point(lambda v: v*0.45))).filter(ImageFilter.GaussianBlur(14))
img.alpha_composite(sh, ((N-c.width)//2+14, (N-c.height)//2+18)); img.alpha_composite(c, ((N-c.width)//2, (N-c.height)//2))
opts.append(('Golden canister', img.convert('RGB')))

# 7 A negative: the rabbit as one frame on orange-base film, sprockets
img = Image.new('RGB', (N, N), (180, 96, 46))
d = ImageDraw.Draw(img)
for y0 in (int(N*0.06), int(N*0.86)):
    for i in range(9):
        x = int(N*0.02 + i*N*0.115)
        d.rounded_rectangle((x, y0, x+int(N*0.06), y0+int(N*0.08)), 6, fill=(20, 12, 8))
fr = (int(N*0.1), int(N*0.2), int(N*0.9), int(N*0.8))
d.rectangle(fr, fill=(214, 140, 80))
m = rabbit(N, N*0.5)
ar = np.asarray(img).astype(np.float32)
inside = np.zeros((N, N), np.float32); inside[fr[1]:fr[3], fr[0]:fr[2]] = 1
ar = ar * (1 - (m*inside)[..., None]) + (m*inside)[..., None] * np.array([92, 40, 18])
d2 = ImageDraw.Draw(img := to_img(ar))
d2.text((N*0.5, N*0.175), 'DARKROOM   1A', fill=(250, 200, 120), font=font(int(N*0.04)), anchor='mm')
opts.append(('Negative', grain(img, 8)))

# 8 Lab stamp: the rabbit and DARKROOM round it, inked on cream paper
img = to_img(radial(N, N*0.4, N*0.35, N*0.9, (244, 238, 224), (222, 212, 190)))
d = ImageDraw.Draw(img)
ink = (156, 52, 40)
d.ellipse((N*0.07, N*0.07, N*0.93, N*0.93), outline=ink, width=int(N*0.018))
d.ellipse((N*0.17, N*0.17, N*0.83, N*0.83), outline=ink, width=int(N*0.008))
m = rabbit(N, N*0.36, bust=False, eyes=False)
ar = np.asarray(img).astype(np.float32)
ar = ar * (1 - m[..., None]) + m[..., None] * np.array(ink)
img = to_img(ar)
d = ImageDraw.Draw(img)
f = font(int(N*0.075))
txt = 'DARKROOM · FILM LAB · '
r0 = N*0.375
for i, ch in enumerate(txt * 1):
    ang = -math.pi/2 + i * 2*math.pi/len(txt)
    ci = Image.new('L', (int(N*0.1), int(N*0.1)), 0)
    ImageDraw.Draw(ci).text((N*0.05, N*0.05), ch, fill=255, font=f, anchor='mm')
    ci = ci.rotate(-math.degrees(ang + math.pi/2), resample=Image.BICUBIC)
    x = N/2 + r0*math.cos(ang) - ci.width/2; y = N/2 + r0*math.sin(ang) - ci.height/2
    img.paste(Image.new('RGB', ci.size, ink), (int(x), int(y)), ci)
# stamp texture: the ink broken up
noise = np.random.default_rng(5).random((N, N)) < 0.07
ar = np.asarray(img).astype(np.float32)
paper = np.asarray(to_img(radial(N, N*0.4, N*0.35, N*0.9, (244, 238, 224), (222, 212, 190)))).astype(np.float32)
inked = (np.abs(ar - paper).sum(-1) > 40)
ar[noise & inked] = paper[noise & inked]
opts.append(('Lab stamp', grain(to_img(ar), 5)))

# sheet: each in Instagram's circle, labelled
C = 330; pad = 34
sheet = Image.new('RGB', (4*(C+pad)+pad, 2*(C+pad+50)+pad), (18, 18, 20))
d = ImageDraw.Draw(sheet)
mask = Image.new('L', (C*4, C*4), 0); ImageDraw.Draw(mask).ellipse((0, 0, C*4, C*4), fill=255); mask = mask.resize((C, C), Image.LANCZOS)
for i, (name, im) in enumerate(opts):
    im.save(f'{OUT}/ig_{i+1}.png')
    x = pad + (i % 4) * (C + pad); y = pad + (i // 4) * (C + pad + 50)
    sheet.paste(im.resize((C, C), Image.LANCZOS), (x, y), mask)
    d.text((x + C/2, y + C + 22), f'{i+1}  {name}', fill=(235, 230, 220), font=font(26), anchor='mm')
sheet.save(f'{OUT}/ig_sheet.png')
print('ok')
