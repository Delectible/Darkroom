"""Whole-body renders: each camera as one object (body shell with its ends,
leather or aluminium, plates, every control in its place from the shared
design layout), seen through one perspective camera.

    /opt/bpyenv/venv/bin/python whole_body.py OUT [--mode film] [--job rest|layers|turns] [--yaw 30]
        [--draft] [--force]

Writes into OUT/<mode>/ and OUT/manifest.json (the app's assets/body3):
- rest.webp: the body face-on, without its moving parts;
- layers: each moving part alone in each state (flash tab, keys, dials,
  shutters...), with the shadow it casts on the body, cropped to its rect;
- turn-aNN.webp: the whole body (moving parts in their resting state)
  turned NN degrees for the swap, cropped, plus each shutter turned with it.

Design space: 412 x 968 dp, x right, y down (like the app); the app trims
phones that are less tall out of the middle of the viewfinder (cutY).
Blender: +Y up, the face at z = 0, the camera DIST above the face centre.
Resumable: finished images are skipped (--force to redo).
"""
import argparse
import json
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from bpy_extras.object_utils import world_to_camera_view  # noqa: E402
from mathutils import Vector  # noqa: E402
from PIL import Image  # noqa: E402

import kit  # noqa: E402
import parts as P  # noqa: E402

W, H = 412.0, 968.0
CUT_Y = H / 2               # trimmed out of here (inside the viewfinder)
CAP = W * 0.2               # body beyond the screen edge (app: SwapGeometry.cap)
THICK = W * 0.14            # body depth (SwapGeometry.thickness)
DIST = 1400.0               # camera distance from the face (dp)
HEIGHTS = 2.6               # controls stand this much prouder than life
PLATE = 0.8                 # the chrome plates stand this proud of the leather
TURNS = list(range(0, 52, 3))
REST_PX, TURN_PX, LAYER_PX = 3.2, 1.5, 3.2

# Centres / rects in design dp; the app places its touch areas, labels and
# the live viewfinder from the same numbers (manifest 'layout').
TOP_Y, ROW_Y, LABEL_Y = 84.0, H - 108, H - 196
FRAME = (14.0, 126.0, 398.0, H - 236)
LAYOUT = {
    'film': {
        'frame': FRAME, 'screenInset': 9.0,
        'memo': (20.0, LABEL_Y - 24, 236.0, LABEL_Y + 24),
        'plateTop': 120.0, 'plateBottom': H - 54,
        'parts': {
            'flash': (50.0, TOP_Y), 'flashtab': (23.0, TOP_Y + 6), 'aspect': (128.0, TOP_Y),
            'lens': (328.0, TOP_Y), 'lensdot': (328.0, TOP_Y), 'menu': (378.0, TOP_Y),
            'print': (56.0, ROW_Y), 'shutter': (214.0, ROW_Y), 'tray': (356.0, ROW_Y),
        },
        # moving parts: drawn by the app over rest.webp, in their state
        'layers': {
            'flashtab': [None], 'aspect': [None], 'aspecttop': [None], 'lensdot': [None],
            'menu': ['up', 'down'], 'shutter': ['up', 'down'], 'release': ['up', 'down'],
            'lever': [None], 'run': ['up', 'down'],
        },
        'shutters': ['shutter', 'run'],
        'lug': 'right',
    },
    'digital': {
        'frame': FRAME, 'screenInset': 12.0,
        'lcd': (20.0, LABEL_Y - 25, 238.0, LABEL_Y + 25),
        'parts': {
            'pill': (50.0, TOP_Y), 'pillwide': (128.0, TOP_Y), 'lens': (328.0, TOP_Y),
            'lensdot': (328.0, TOP_Y), 'pillsmall': (378.0, TOP_Y), 'rocker': (330.0, LABEL_Y),
            'review': (56.0, ROW_Y), 'shutter': (206.0, ROW_Y), 'tray': (356.0, ROW_Y),
        },
        'layers': {
            'pill': ['up', 'down'], 'pillwide': ['up', 'down'], 'pillsmall': ['up', 'down'],
            'lensdot': [None], 'rocker': ['mid', 'w', 't'], 'shutter': ['up', 'down'], 'rec': ['up', 'down'],
        },
        'shutters': ['shutter', 'rec'],
        'lug': 'left',
    },
}
# Parts that are layers live at a part's position (aspecttop on aspect...).
LAYER_AT = {'aspecttop': 'aspect', 'release': 'shutter', 'lever': 'shutter', 'run': 'shutter', 'rec': 'shutter'}


def at(x, y):
    return (x - W / 2, H / 2 - y)


# ------------------------------------------------------------------ model
def shell(mode, root):
    film = mode == 'film'
    lay = LAYOUT[mode]
    full = W + 2 * CAP
    g = kit.group('shell', root)
    # the body: a deep rounded block, its face a little proud of the shell
    kit.rbox(full, H + 60, THICK, 46, 10, 'blackPaint' if film else 'aluDark', -THICK - 1.4, g, 'shell')
    kit.rbox(full - 8, H + 52, 2.4, 42, 0.6, 'leather' if film else 'alu', -2.4, g, 'skin')
    if film:
        for top in (True, False):
            edge = lay['plateTop'] if top else H - lay['plateBottom']
            h = edge + 30
            plate = kit.rbox(full - 6, h, PLATE + 2.4, 8, 1.2, 'brushed', -2.4, g, 'plate')
            plate.location.y = (H / 2 + 30 - h / 2) * (1 if top else -1)
            for x in (-W / 2 + 14, W / 2 - 14):
                kit.screw(3.4, PLATE, 0.4 if x < 0 else 1.2, g, (x, (H / 2 - edge + 12) * (1 if top else -1)))
        kit.rabbit(13, 'ink', 'brushed', PLATE, 0.08, g, at(190, TOP_Y + 3))
        kit.text('DARKROOM', 7.2, 'ink', PLATE, 0.08, 'LEFT', spacing=1.25, parent=g, loc=at(200, TOP_Y + 3))
        kit.text('No. 1998042  ·  MADE IN THE DARKROOM', 3.9, 'ink', PLATE, 0.08, 'CENTER',
                 'DejaVuSansCondensed-Bold.ttf', 1.15, g, at(206, H - 24))
    # strap lug on the end that turns toward you (film right, digital left)
    side = 1 if lay['lug'] == 'right' else -1
    lug = kit.group('lug', g)
    kit.rbox(10, 34, 14, 5, 2.5, 'satin', 0, lug, 'lug')
    lug.rotation_euler.y = math.radians(90) * side
    lug.location = (side * (full / 2 - 1), H / 2 - H * 0.24, -THICK / 2 - 7)
    return g


def frame(mode, root):
    x0, y0, x1, y1 = LAYOUT[mode]['frame']
    w, h = x1 - x0, y1 - y0
    g = kit.group('frame', root)
    if mode == 'film':
        kit.ring(w, h, 14, w - 16, h - 16, 8, 3.2, 1.4, 'blackAnod', 0, g)
        kit.ring(w - 14, h - 14, 9, w - 20, h - 20, 7, 0.6, 0.35, 'polished', 2.6, g)
    else:
        kit.ring(w - 4, h - 4, 10, w - 24, h - 24, 4, 2.4, 1.0, 'glossBlack', 0, g)
        kit.ring(w, h, 12, w - 6, h - 6, 10, 0.8, 0.3, 'aluDark', 0, g)
    kit.rbox(w - 14, h - 14, 0.4, 6, 0.1, 'gap', 0.05, g, 'screen')
    g.location = (*at((x0 + x1) / 2, (y0 + y1) / 2), 0)
    g.scale = (1, 1, HEIGHTS)


def label_box(mode, root):
    lay = LAYOUT[mode]
    if mode == 'film':
        x0, y0, x1, y1 = lay['memo']
        g = kit.group('memo', root)
        kit.ring(x1 - x0, y1 - y0, 6, x1 - x0 - 16, y1 - y0 - 14, 3, 1.6, 0.6, 'satin', 0.4, g)
        kit.rbox(x1 - x0 - 16, y1 - y0 - 14, 0.3, 3, 0.05, 'paper', 0.1, g, 'card')
        for sx in (-(x1 - x0) / 2 + 9, (x1 - x0) / 2 - 9):
            kit.screw(2.2, 2.0, 0.5 if sx > 0 else 1.7, g, (sx, 0))
    else:
        x0, y0, x1, y1 = lay['lcd']
        g = P.bezel(x1 - x0 - 16, y1 - y0 - 16, 6)(None)
        g.parent = root
        kit.rbox(x1 - x0 - 16, y1 - y0 - 16, 0.3, 6, 0.05, 'well', 0.1, g, 'lcd')
    g.location = (*at((x0 + x1) / 2, (y0 + y1) / 2), 0)
    g.scale = (1, 1, HEIGHTS)


def place(obj, mode, name, x, y, root):
    g = kit.group(f'at-{name}', root)
    obj.parent = g
    lay = LAYOUT[mode]
    # film's top controls stand on the chrome plate
    on_plate = 'plateTop' in lay and (y < lay['plateTop'] or y > lay['plateBottom'])
    g.location = (*at(x, y), (PLATE if on_plate else 0) + (0.9 if name == 'flash' else 0))
    g.scale = (1, 1, HEIGHTS)
    return g


def build_part(mode, name, state):
    if name == 'aspecttop':
        return P.f_aspect(None, top_only=True)
    return P.PARTS[mode][name]['build'](state)


def build(mode, *, skip=(), shutter='shutter', only=None, only_state=None):
    """The body with its parts. [skip]: part names left out; [only]: build
    just that moving part (others not at all) in [only_state]."""
    root = kit.group('body')
    lay = LAYOUT[mode]
    if only is not None:
        x, y = lay['parts'][LAYER_AT.get(only, only)]
        return root, place(build_part(mode, only, only_state), mode, only, x, y, root)
    shell(mode, root)
    frame(mode, root)
    label_box(mode, root)
    for name, (x, y) in lay['parts'].items():
        if name in skip:
            continue
        part = shutter if name == 'shutter' else name
        p = P.PARTS[mode][part]
        place(p['build']((p.get('states') or [None])[0]), mode, name, x, y, root)
    return root, None


# ------------------------------------------------------------------ studio
def studio():
    """A product studio scaled to the whole body: a large soft key high at the
    top left (shadows fall to the lower right, as in the app), a tall cool
    strip at the right for crisp metal edges, a dim warm fill, a kicker from
    the left that rims the turning end, and a broad scrim overhead for the
    chrome to mirror."""
    kit.area_light('key', (-0.55, 0.6, 0.95), 3000, (800, 560), 7.2e7, (1.0, 0.965, 0.92))
    kit.area_light('strip', (0.95, 0.12, 0.5), 3000, (140, 2600), 2.1e7, (0.94, 0.97, 1.0))
    kit.area_light('fill', (0.35, -0.85, 0.55), 3000, (2400, 900), 5.5e6, (1.0, 0.9, 0.82))
    kit.area_light('kick', (-0.95, -0.25, 0.35), 3000, (240, 1500), 1.0e7, (1, 1, 1))
    kit.area_light('scrim', (0.2, 0.35, 1.0), 3000, (3200, 1000), 9e6, (1, 1, 1))


def camera(canvas_w, canvas_h, px):
    scn = bpy.context.scene
    data = bpy.data.cameras.new('cam')
    data.sensor_fit = 'HORIZONTAL'
    data.lens_unit = 'FOV'
    data.angle = 2 * math.atan(canvas_w / 2 / DIST)
    data.clip_start = 10
    data.clip_end = 10000
    cam = bpy.data.objects.new('cam', data)
    cam.location = (0, 0, DIST)
    bpy.context.collection.objects.link(cam)
    scn.camera = cam
    scn.render.resolution_x = round(canvas_w * px)
    scn.render.resolution_y = round(canvas_h * px)
    scn.render.resolution_percentage = 100
    return cam


def to_design(scn, cam, co, canvas):
    """World point -> design dp (x right, y down; the face centre is (W/2, H/2))."""
    v = world_to_camera_view(scn, cam, Vector(co))
    cw, ch = canvas
    return (W / 2 + (v.x - 0.5) * cw, H / 2 + (0.5 - v.y) * ch)


def bounds(scn, cam, root, canvas):
    bpy.context.view_layer.update()
    xs, ys = [], []
    for o in [root, *root.children_recursive]:
        if o.type not in ('MESH', 'CURVE', 'FONT'):
            continue
        for c in o.bound_box:
            x, y = to_design(scn, cam, o.matrix_world @ Vector(c), canvas)
            xs.append(x)
            ys.append(y)
    return min(xs), min(ys), max(xs), max(ys)


def render(scn, path, spp, rect=None, canvas=None):
    """Render to [path]; [rect] (design dp) limits it to that region."""
    scn.cycles.samples = spp
    if rect:
        cw, ch = canvas
        x0, y0, x1, y1 = rect
        scn.render.use_border = True
        scn.render.use_crop_to_border = True
        scn.render.border_min_x = max(0.0, (x0 - (W - cw) / 2) / cw)
        scn.render.border_max_x = min(1.0, (x1 - (W - cw) / 2) / cw)
        scn.render.border_max_y = min(1.0, 1 - (y0 - (H - ch) / 2) / ch)
        scn.render.border_min_y = max(0.0, 1 - (y1 - (H - ch) / 2) / ch)
    tmp = path + '.png'
    scn.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = Image.open(tmp).convert('RGBA')
    os.remove(tmp)
    return img


def veil(img):
    """Shadow catchers leave a faint veil (light the part blocks from the
    dark studio): what's left at the crop's border counts as none."""
    import numpy as np
    a = np.asarray(img).astype(np.float32) / 255
    al = a[..., 3]
    border = np.concatenate([al[:2].ravel(), al[-2:].ravel(), al[:, :2].ravel(), al[:, -2:].ravel()])
    base = float(np.median(border))
    shadow = al < 0.97
    a[..., 3] = np.where(shadow, np.clip((al - base) / max(1e-3, 1 - base), 0, 1), al)
    return Image.fromarray((a * 255 + 0.5).astype('uint8'), 'RGBA')


def trim(img):
    """Crop to what's drawn; returns (image, (left, top) px)."""
    box = img.getchannel('A').point(lambda v: 255 if v > 2 else 0).getbbox()
    if not box:
        return img, (0, 0)
    return img.crop(box), box[:2]


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, 'WEBP', quality=90, method=6)


# ------------------------------------------------------------------ jobs
def fresh():
    scn = kit.reset()
    kit.clear_mats()
    studio()
    return scn


def job_rest(out, mode, a):
    path = f'{out}/{mode}/rest.webp'
    if os.path.exists(path) and not a.force:
        return
    scn = fresh()
    lay = LAYOUT[mode]
    build(mode, skip=set(lay['layers']) | {'shutter'})
    camera(W, H, a.px or REST_PX)
    img = render(scn, path, 48 if a.draft else 384)
    save(img, path)


def job_layers(out, mode, a, man):
    lay = LAYOUT[mode]
    canvas = (W, H)
    for name, states in lay['layers'].items():
        for st in states:
            key = name + (f'-{st}' if st else '')
            path = f'{out}/{mode}/layer-{key}.webp'
            meta = f'{path}.json'
            if os.path.exists(meta) and not a.force:
                man[key] = json.load(open(meta))
                continue
            scn = fresh()
            # the body is there to catch the part's shadow (and nothing else)
            body, _ = build(mode, skip=set(lay['layers']) | {'shutter'})
            for o in [body, *body.children_recursive]:
                o.is_shadow_catcher = True
            _, part = build(mode, only=name, only_state=st)
            noshadow = P.PARTS[mode].get(name, {}).get('noShadow') or name in ('aspecttop', 'lensdot', 'lever')
            if noshadow:
                for o in [body, *body.children_recursive]:
                    o.hide_render = True
            cam = camera(*canvas, a.px or LAYER_PX)
            x0, y0, x1, y1 = bounds(scn, cam, part, canvas)
            pad = 4 if noshadow else 16
            rect = (math.floor(x0 - pad), math.floor(y0 - pad), math.ceil(x1 + pad + (0 if noshadow else 8)),
                    math.ceil(y1 + pad + (0 if noshadow else 10)))
            img = render(scn, path, 32 if a.draft else 256, rect, canvas)
            if not noshadow:
                img = veil(img)
            # exact rect of the crop that came back (pixel-rounded by Blender)
            px = img.width / (rect[2] - rect[0])
            info = {'path': f'{mode}/layer-{key}.webp', 'rect': [rect[0], rect[1], rect[2] - rect[0], rect[3] - rect[1]],
                    'px': px}
            save(img, path)
            json.dump(info, open(meta, 'w'))
            man[key] = info
            print(f'done layer {mode}/{key}', flush=True)


def job_turns(out, mode, a, man, yaws):
    lay = LAYOUT[mode]
    canvas = (W + 2 * CAP + 2 * THICK, H * 1.3)
    sign = -1 if mode == 'film' else 1
    for yaw in yaws:
        rec = man.setdefault(str(yaw), {})
        path = f'{out}/{mode}/turn-a{yaw}.webp'
        meta = f'{path}.json'
        if os.path.exists(meta) and not a.force:
            rec.update(json.load(open(meta)))
        else:
            scn = fresh()
            body, _ = build(mode, skip={'shutter'})
            turn = kit.group('turn')
            body.parent = turn
            turn.rotation_euler.y = math.radians(yaw) * sign
            cam = camera(*canvas, a.px or TURN_PX)
            img = render(scn, path, 32 if a.draft else 128)
            bpy.context.view_layer.update()
            img, (lx, ly) = trim(img)
            k = img.width and (a.px or TURN_PX)
            # lug position for the app's strap
            lug = next(o for o in body.children_recursive if o.name.startswith('lug') and o.type == 'EMPTY')
            lp = to_design(scn, cam, lug.matrix_world.translation, canvas)
            x0 = (W - canvas[0]) / 2 + lx / k
            y0 = (H - canvas[1]) / 2 + ly / k
            info = {'path': f'{mode}/turn-a{yaw}.webp', 'rect': [x0, y0, img.width / k, img.height / k], 'px': k,
                    'lug': list(lp)}
            save(img, path)
            json.dump(info, open(meta, 'w'))
            rec.update(info)
            print(f'done turn {mode}/{yaw}', flush=True)
        # each shutter turned with the body, drawn over the turn frame
        for sh in lay['shutters']:
            spath = f'{out}/{mode}/turn-{sh}-a{yaw}.webp'
            smeta = f'{spath}.json'
            if os.path.exists(smeta) and not a.force:
                rec.setdefault('shutters', {})[sh] = json.load(open(smeta))
                continue
            scn = fresh()
            body, _ = build(mode, skip=set(lay['parts']))
            # shadow onto the body only
            for o in [body, *body.children_recursive]:
                o.is_shadow_catcher = True
            _, part = build(mode, only=sh, only_state='up')
            turn = kit.group('turn')
            for r in (body, part.parent):
                r.parent = turn
            turn.rotation_euler.y = math.radians(yaw) * sign
            bpy.context.view_layer.update()
            cam = camera(*canvas, a.px or TURN_PX)
            x0, y0, x1, y1 = bounds(scn, cam, part, canvas)
            rect = (math.floor(x0 - 14), math.floor(y0 - 14), math.ceil(x1 + 22), math.ceil(y1 + 24))
            img = veil(render(scn, spath, 32 if a.draft else 128, rect, canvas))
            k = img.width / (rect[2] - rect[0])
            info = {'path': f'{mode}/turn-{sh}-a{yaw}.webp', 'rect': [rect[0], rect[1], rect[2] - rect[0], rect[3] - rect[1]],
                    'px': k}
            save(img, spath)
            json.dump(info, open(smeta, 'w'))
            rec.setdefault('shutters', {})[sh] = info
            print(f'done turn {mode}/{sh}/{yaw}', flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('--mode')
    ap.add_argument('--job', default='rest,layers,turns')
    ap.add_argument('--yaw', type=int)
    ap.add_argument('--px', type=float)
    ap.add_argument('--draft', action='store_true')
    ap.add_argument('--force', action='store_true')
    a = ap.parse_args()
    jobs = a.job.split(',')
    man_path = f'{a.out}/manifest.json'
    man = json.load(open(man_path)) if os.path.exists(man_path) else {}
    man['design'] = {'w': W, 'h': H, 'cutY': CUT_Y, 'dist': DIST, 'cap': CAP, 'thick': THICK}
    man['layout'] = {m: {k: v for k, v in lay.items() if k not in ('layers', 'shutters')} for m, lay in LAYOUT.items()}
    for mode in ('film', 'digital'):
        if a.mode and mode != a.mode:
            continue
        t0 = time.time()
        m = man.setdefault(mode, {})
        if 'rest' in jobs:
            job_rest(a.out, mode, a)
            m['rest'] = {'path': f'{mode}/rest.webp', 'rect': [0, 0, W, H]}
        if 'layers' in jobs:
            job_layers(a.out, mode, a, m.setdefault('layers', {}))
        if 'turns' in jobs:
            job_turns(a.out, mode, a, m.setdefault('turns', {}), [a.yaw] if a.yaw is not None else TURNS)
        json.dump(man, open(man_path, 'w'), indent=1)
        print(f'{mode} done in {time.time() - t0:.0f}s', flush=True)
    print('all done', flush=True)


if __name__ == '__main__':
    main()
