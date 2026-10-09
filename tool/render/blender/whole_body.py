"""Whole-body renders: the camera as one object (body shell, leather or
aluminium, plates, every control in its place from the app's design
layout), seen through a perspective camera, face-on and turned for the swap.

    /opt/bpyenv/venv/bin/python whole_body.py OUT film|digital YAW [--px 2] [--spp 96]

Design space: 412 x H dp (x right, y down, like the app); Blender has +Y up.
"""
import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

import kit  # noqa: E402
import parts as P  # noqa: E402

W, H = 412.0, 915.0
CAP = W * 0.2          # body beyond the screen edge (app: SwapGeometry.cap)
THICK = W * 0.14       # side wall depth (SwapGeometry.thickness)
DIST = 1100.0          # camera distance from the face (dp)
HEIGHTS = 2.2          # controls stand this much prouder than life

LAYOUT = {
    # centre (x, y) in design dp; see lib/features/camera/presentation/camera_screen.dart
    'film': dict(top=106, bottom=879, frame=(14, 100, 398, 700), memo=(20, 725, 392, 773),
                 parts={'flash': (50, 74), 'flashtab': (23, 80), 'aspect': (128, 74), 'lens': (328, 74),
                        'lensdot': (328, 74), 'menu': (378, 74), 'print': (56, 830), 'shutter': (214, 830),
                        'tray': (356, 830)}),
    'digital': dict(frame=(14, 100, 398, 700), lcd=(20, 724, 238, 774),
                    parts={'pill': (50, 74), 'pillwide': (128, 74), 'lens': (328, 74), 'lensdot': (328, 74),
                           'pillsmall': (378, 74), 'rocker': (330, 745), 'review': (56, 830),
                           'shutter': (206, 830), 'tray': (356, 830)}),
}


def at(x, y):
    return (x - W / 2, H / 2 - y)


def proud(obj, x, y):
    """Place a part (built at the origin) at design (x, y), exaggerated in height."""
    g = kit.group('place')
    obj.parent = g
    g.location = (*at(x, y), 0)
    g.scale = (1, 1, HEIGHTS)
    return g


def shell(mode, root):
    film = mode == 'film'
    face = 'leather' if film else 'alu'
    full = W + 2 * CAP
    # the body: rounded ends, a little bevel all round
    kit.rbox(full, H + 40, THICK, 60, 8, 'blackPaint' if film else 'aluDark', -THICK - 2, root, 'shell')
    kit.rbox(full - 6, H + 34, 2, 57, 0.4, face, -2, root, 'skin')
    if film:
        lay = LAYOUT['film']
        for which, edge in (('top', lay['top']), ('bot', H - lay['bottom'])):
            h = edge + 40
            plate = kit.rbox(full - 4, h, 3, 4, 1.2, 'brushed', -0.5, root, 'plate')
            plate.location.y = H / 2 + 20 - h / 2 if which == 'top' else -(H / 2 + 20 - h / 2)
        kit.rabbit(13, 'ink', 'brushed', 2.5, 0.08, root, (*at(190, 77),))
        kit.text('DARKROOM', 7.2, 'ink', 2.5, 0.08, 'LEFT', spacing=1.25, parent=root, loc=at(200, 77))
        kit.text('No. 1998042  ·  MADE IN THE DARKROOM', 3.9, 'ink', 2.5, 0.08, 'CENTER',
                 'DejaVuSansCondensed-Bold.ttf', 1.15, root, at(206, 893))


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
        lcd = kit.rbox(x1 - x0 - 16, y1 - y0 - 16, 0.3, 6, 0.05, 'paper', 0.1, g, 'lcd')
        lcd.active_material = kit.mat('lcdGlass') if 'lcdGlass' in dir(kit) else lcd.active_material
    g.location = (*at((x0 + x1) / 2, (y0 + y1) / 2), 0)
    g.scale = (1, 1, HEIGHTS)


def build(mode):
    root = kit.group('body')
    shell(mode, root)
    frame(mode, root)
    label_box(mode, root)
    for name, (x, y) in LAYOUT[mode]['parts'].items():
        p = P.PARTS[mode][name]
        st = (p.get('states') or [None])[0]
        g = proud(p['build'](st), x, y)
        g.parent = root
        if name == 'flash':
            g.location.z = 0.9  # its slot sits in a raised plate

    return root


def camera(canvas_w, canvas_h, px, cy=0.0):
    scn = bpy.context.scene
    data = bpy.data.cameras.new('cam')
    data.sensor_fit = 'HORIZONTAL'
    data.lens_unit = 'FOV'
    data.angle = 2 * math.atan(canvas_w / 2 / DIST)
    data.clip_start = 10
    data.clip_end = 10000
    cam = bpy.data.objects.new('cam', data)
    cam.location = (0, cy, DIST)
    bpy.context.collection.objects.link(cam)
    scn.camera = cam
    scn.render.resolution_x = round(canvas_w * px)
    scn.render.resolution_y = round(canvas_h * px)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('mode')
    ap.add_argument('yaw', type=float)
    ap.add_argument('--px', type=float, default=2)
    ap.add_argument('--spp', type=int, default=96)
    ap.add_argument('--canvas', default='')
    a = ap.parse_args()
    scn = kit.reset()
    kit.clear_mats()
    kit.area_light('key', (-0.55, 0.6, 0.95), 2600, (700, 500), 5.5e7, (1.0, 0.965, 0.92))
    kit.area_light('strip', (0.95, 0.12, 0.5), 2600, (120, 2200), 1.6e7, (0.94, 0.97, 1.0))
    kit.area_light('fill', (0.35, -0.85, 0.55), 2600, (2000, 800), 6e6, (1.0, 0.9, 0.82))
    kit.area_light('kick', (-0.95, -0.25, 0.35), 2600, (200, 1200), 6e6, (1, 1, 1))
    kit.area_light('scrim', (0.2, 0.35, 1.0), 2600, (2800, 900), 8e6, (1, 1, 1))
    turn = kit.group('turn')
    body = build(a.mode)
    body.parent = turn
    turn.rotation_euler.y = math.radians(a.yaw) * (-1 if a.mode == 'film' else 1)
    cw, ch = (float(v) for v in a.canvas.split('x')) if a.canvas else (W, H)
    camera(cw, ch, a.px)
    scn.cycles.samples = a.spp
    scn.render.filepath = a.out
    bpy.ops.render.render(write_still=True)
