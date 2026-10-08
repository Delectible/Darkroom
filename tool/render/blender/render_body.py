"""Renders the app's camera-body sprites with Blender Cycles (CPU, denoised).

    /opt/bpyenv/venv/bin/python render_body.py OUT [--mode film] [--part frame]
        [--yaw0] [--dry] [--px 3.5] [--ss 1.25]

Needs the `bpy` module (pip install bpy==4.5.*). Resumable: finished sprites
are skipped, face-on (yaw 0) first. Writes OUT/<mode>/<part>[-<state>]-a<deg>.webp
and OUT/manifest.json; tool/render/body/bundle.py copies them into the app.
"""
import argparse
import json
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from PIL import Image  # noqa: E402

import kit  # noqa: E402
from parts import PARTS  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('out')
ap.add_argument('--mode')
ap.add_argument('--part')
ap.add_argument('--state')
ap.add_argument('--yaw', type=int)
ap.add_argument('--yaw0', action='store_true')
ap.add_argument('--dry', action='store_true')
ap.add_argument('--force', action='store_true')
ap.add_argument('--px', type=float, default=3.5)
ap.add_argument('--ss', type=float, default=1.25)
ap.add_argument('--threads', type=int, default=0)
args = ap.parse_args()

META = ('canvas', 'yaws', 'states', 'stateYaw0', 'px', 'spp', 'slice', 'sliceX', 'box', 'edge', 'noShadow')
os.makedirs(args.out, exist_ok=True)
json.dump({'px': args.px, 'parts': {m: {n: {k: v for k, v in p.items() if k in META} for n, p in ps.items()}
                                    for m, ps in PARTS.items()}},
          open(f'{args.out}/manifest.json', 'w'), indent=1)

jobs = []
for mode, ps in PARTS.items():
    if args.mode and mode != args.mode:
        continue
    for name, p in ps.items():
        if args.part and name != args.part:
            continue
        for yaw in p['yaws']:
            if (args.yaw0 and yaw != 0) or (args.yaw is not None and yaw != args.yaw):
                continue
            for st in p.get('states') or [None]:
                if args.state and st != args.state:
                    continue
                if st and yaw != 0 and st in (p.get('stateYaw0') or []):
                    continue
                jobs.append((mode, name, st, yaw, p))
jobs.sort(key=lambda j: (j[3] != 0, j[3], j[0], j[1]))


def path(j):
    mode, name, st, yaw, _ = j
    return f"{args.out}/{mode}/{name}{'-' + st if st else ''}-a{yaw}.webp"


def clean_shadow(img):
    """The shadow catcher leaves a faint veil over the whole canvas (light the
    part blocks from the dark studio): take what's left at the border as
    zero, and fade the shadow out toward the canvas edge."""
    import numpy as np
    a = np.asarray(img).astype(np.float32) / 255
    al = a[..., 3]
    border = np.concatenate([al[:3].ravel(), al[-3:].ravel(), al[:, :3].ravel(), al[:, -3:].ravel()])
    base = float(np.median(border))
    shadow = al < 0.97
    al2 = np.where(shadow, np.clip((al - base) / max(1e-3, 1 - base), 0, 1), al)
    h, w = al.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    fade = np.clip(edge / (0.05 * min(w, h)), 0, 1)
    a[..., 3] = np.where(shadow, al2 * fade, al2)
    return Image.fromarray((a * 255 + 0.5).astype('uint8'), 'RGBA')


todo = [j for j in jobs if args.force or not os.path.exists(path(j))]
print(f'{len(jobs)} sprites, {len(todo)} to render', flush=True)
if args.dry:
    for j in todo:
        print(path(j))
    sys.exit()

for j in todo:
    mode, name, st, yaw, p = j
    t0 = time.time()
    scn = kit.reset()
    kit.clear_mats()
    kit.studio()
    cw, ch = p['canvas']
    px = p.get('px', args.px)
    ss = args.ss if yaw == 0 else 0.85
    root = kit.group('root')
    part = p['build'](st)
    part.parent = root
    if not p.get('noShadow'):
        kit.shadow_catcher().parent = root
    # turned about the body's long axis (image vertical): film shows its
    # right end coming toward the viewer (+), digital its left (-)
    root.rotation_euler.y = math.radians(yaw) * (-1 if mode == 'film' else 1)
    kit.camera(cw, ch, px * ss)
    spp = p.get('spp', 128)
    scn.cycles.samples = spp if yaw == 0 else min(spp, 48)
    if args.threads:
        scn.render.threads_mode = 'FIXED'
        scn.render.threads = args.threads
    os.makedirs(f'{args.out}/_tmp', exist_ok=True)
    tmp = f'{args.out}/_tmp/{mode}-{name}-{st}-{yaw}.png'
    scn.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    out = path(j)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img = Image.open(tmp).convert('RGBA')
    if not p.get('noShadow'):
        img = clean_shadow(img)
    w = round(cw * px)
    if img.width != w:
        img = img.resize((w, round(img.height * w / img.width)), Image.LANCZOS)
    img.save(out, 'WEBP', quality=90, method=6)
    print(f'done {mode}/{os.path.basename(out)} {time.time() - t0:.0f}s', flush=True)
print('all done', flush=True)
