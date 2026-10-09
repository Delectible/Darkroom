"""Composites whole-body renders like the app does, for checking alignment.

    python3 whole_mock.py OUT film|digital out.png [--states menu=down,...] [--yaw 30]
"""
import argparse
import json

from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument('src')
ap.add_argument('mode')
ap.add_argument('out')
ap.add_argument('--states', default='')
ap.add_argument('--yaw', type=int)
ap.add_argument('--px', type=float, default=1.5)
a = ap.parse_args()
man = json.load(open(f'{a.src}/manifest.json'))
d = man['design']
W, H, PX = d['w'], d['h'], a.px
m = man[a.mode]


def put(canvas, info, origin=(0, 0)):
    im = Image.open(f"{a.src}/{info['path']}").convert('RGBA')
    x, y, w, h = info['rect']
    im = im.resize((max(1, round(w * PX)), max(1, round(h * PX))), Image.LANCZOS)
    canvas.alpha_composite(im, (round((x - origin[0]) * PX), round((y - origin[1]) * PX)))


if a.yaw is None:
    img = Image.new('RGBA', (round(W * PX), round(H * PX)), (16, 13, 11, 255))
    put(img, m['rest'])
    states = dict(s.split('=') for s in a.states.split(',') if s)
    shutter = states.pop('shutter', 'shutter')
    for name in m.get('layers', {}):
        base = name.split('-')[0]
        if base in ('aspecttop', 'release', 'lever', 'run', 'rec', 'shutter') and base != shutter:
            continue
        if base in ('aspecttop', 'release', 'lever'):
            continue
        st = name[len(base) + 1:] or None
        want = states.get(base)
        default = {'menu': 'up', 'shutter': 'up', 'run': 'up', 'rec': 'up', 'pill': 'up', 'pillwide': 'up',
                   'pillsmall': 'up', 'rocker': 'mid'}.get(base)
        if st is not None and st != (want or default):
            continue
        import os
        if os.path.exists(f"{a.src}/{m['layers'][name]['path']}"): put(img, m['layers'][name])
else:
    t = m['turns'][str(a.yaw)]
    ox, oy = (W - 700) / 2, (H - 1300) / 2
    img = Image.new('RGBA', (round(700 * PX), round(1300 * PX)), (16, 13, 11, 255))
    put(img, t, (ox, oy))
    sh = (t.get('shutters') or {}).get(a.states or ('shutter'))
    if sh:
        put(img, sh, (ox, oy))
img.convert('RGB').save(a.out)
print('saved', a.out, img.size)
