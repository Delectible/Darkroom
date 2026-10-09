"""Every part of the film and digital bodies the app draws (same names,
canvases and states as before; see photo_body.dart). A part sits with its
base centre at the origin on the body surface (z = 0); image up = +Y.

Each entry: canvas (w, h) dp, yaws to render, optional states (first is the
default; stateYaw0 = only rendered face-on), px (pixels per dp), spp,
slice / sliceX / box (stretched parts), edge (plates), noShadow, and
build(state) -> the part's root empty.
"""
import math

from kit import (box, capsule_pts, cylinder, group, knurl, lathe, rabbit, rbox, ring, screw, slab, text)

YAWS = [0, 6, 12, 18, 24, 30, 36, 42, 48]
PANEL_YAWS = [0, 16, 32, 48]
LEVER_REST = 0.18  # radians, clockwise on screen


def moving(g, how):
    """Marks [g] as a piece that moves on the live model (export_glb.py):
    'press' (pushed in), 'turn' (rotates about its origin), 'slide',
    'rock', 'lever'."""
    g['mv'] = how
    return g


# ------------------------------------------------------------------ film
def _swatch():
    g = group('swatch')
    rbox(80, 80, 2, 0.1, 0.2, 'leather', -2, g)
    return g


def f_panel(_):
    g = group('panel')
    rbox(412, 1000, 2, 0.1, 0.4, 'leather', -2, g)
    return g


def f_plate(h, which):
    def build(_):
        g = group('plate')
        # the plate's inner edge sits 20 dp in from the canvas edge that
        # faces the leather (bottom of the top plate, top of the bottom one)
        sign = 1 if which == 'top' else -1   # direction the plate runs from its edge
        edge = -sign * (h / 2 - 20)
        length = h - 20 + 60
        cy = edge + sign * length / 2
        rbox(424, length, 3, 0.1, 1.2, 'brushed', -0.5, g, 'plate').location.y = cy
        for x in (-192, 192):
            screw(3.4, 2.5, 0.4 if x < 0 else 1.2, g, (x, edge + sign * 12))
        if which == 'top':
            # maker's mark in the space between the top controls
            rabbit(13, 'ink', 'brushed', 2.5, 0.08, g, (-16, edge + 28))
            text('DARKROOM', 7.2, 'ink', 2.5, 0.08, 'LEFT', spacing=1.25, parent=g, loc=(-6, edge + 28))
        else:
            text('No. 1998042  ·  MADE IN THE DARKROOM', 3.9, 'ink', 2.5, 0.08, 'CENTER', 'DejaVuSansCondensed-Bold.ttf',
                 1.15, g, (0, edge - 14))
        return g
    return build


def f_frame(_):
    g = group('frame')
    ring(196, 196, 14, 180, 180, 8, 3.2, 1.4, 'blackAnod', 0, g)
    ring(182, 182, 9, 176, 176, 7, 0.6, 0.35, 'polished', 2.6, g)
    return g


def f_flash(_):
    g = group('flash')
    rbox(62, 8, 1.2, 3, 0.4, 'gap', -0.9, g).location = (-4, -6, -0.3)
    for t, u in (('A', -27), ('ON', -4), ('OFF', 19)):
        text(t, 5.4, 'ink', 0, 0.08, 'CENTER', 'InterDisplay-Bold.ttf', 1.05, g, (u, 9))
    pts = [((u - 0.5) * 8 + 36, (0.5 - v) * 11 - 6) for u, v in ((0.62, 0), (0.1, 0.58), (0.46, 0.58), (0.3, 1), (0.92, 0.38), (0.55, 0.38))]
    slab([pts], 0.08, 0, 'ink', 0, g, 'bolt')
    return g


def f_flashtab(_):
    g = moving(group('tab'), 'slide')
    rbox(15, 12, 5.5, 1.6, 1.2, 'polished', 0, g)
    for i in range(-2, 3):
        rbox(1.1, 10, 0.9, 0.4, 0.3, 'satin', 5.2, g).location.x = i * 2.5
    return g


def f_aspect(_, top_only=False):
    g = group('aspect')
    dial = moving(group('dial', g), 'turn')
    knurl(17, 8, 72, 'satin', 0.9, 0, dial)
    cylinder(16.4, 1.2, 'spun', 8, 128, 0.4, dial, r_top=15.6)
    for i in range(24):
        a = i / 24 * math.tau
        long = i % 6 == 0
        rr = 12.8 if long else 13.3
        box(2.6 if long else 1.6, 0.35, 0.12, 'ink', (math.cos(a) * rr, math.sin(a) * rr, 9.26), a, 0, dial)
    if not top_only:
        cylinder(1.3, 0.3, 'red', 0, 24, 0, g).location.y = 23
    return g


def f_aspect_top(_):
    # The dial alone (no index dot, no shadow): the app turns it a click
    # over the base render when the format changes; it repeats every 90
    # degrees (ticks, knurl), so it lands looking like the base again.
    return f_aspect(_, top_only=True)


def lens_knob(dark):
    def build(_):
        g = group('lens')
        cylinder(18.5, 2.4, 'aluDark' if dark else 'satin', 0, 128, 0.5, g)
        knurl(16.2, 6.5, 60, 'blackAnod', 0.8, 2.4, g)
        cylinder(15.8, 1.0, 'blackPaint', 8.9, 128, 0.3, g, r_top=15.2)
        lathe([(8.3 + 0.9 * math.cos(t / 16 * math.tau), 9.9 + 0.9 * math.sin(t / 16 * math.tau)) for t in range(17)], 'polished', 96, g, 'ring')
        cylinder(8.6, 0.5, 'gap', 9.4, 64, 0, g)
        R, phi = 11.0, math.asin(8.3 / 11.0)
        zc = 9.75 - R * math.cos(phi)
        lathe([(R * math.sin(phi * i / 16), zc + R * math.cos(phi * i / 16)) for i in range(17)], 'glass', 96, g, 'glass')
        return g
    return build


def lensdot(_):
    g = moving(group('dot'), 'turn')
    cylinder(1.4, 0.3, 'red', 9.85, 32, 0, g).location.y = 12.6
    return g


def f_menu(state):
    g = group('menu')
    cylinder(14, 2.2, 'satin', 0, 128, 0.4, g)
    cylinder(11.6, 0.4, 'gap', 1.9, 64, 0, g)
    lift = -1.4 if state == 'down' else 0
    press = moving(group('press', g), 'press')
    cylinder(11, 4.2, 'spun', 2.2 + lift, 128, 0.6, press, r_top=10.4)
    for yy, kx in ((3.2, 1.6), (0, -1.8), (-3.2, 0.8)):
        box(10, 0.9, 0.12, 'ink', (0, yy, 6.45 + lift), 0, 0, press)
        cylinder(1.3, 0.14, 'ink', 6.42 + lift, 24, 0, press).location = (kx, yy, 0)
    return g


def f_memo(_):
    g = group('memo')
    ring(120, 52, 6, 104, 38, 3, 1.6, 0.6, 'satin', 0.4, g)
    for sx in (-55, 55):
        screw(2.2, 2.0, 0.5 if sx > 0 else 1.7, g, (sx, 0))
    return g


def f_print(_):
    g = group('print')
    rbox(58, 70, 0.4, 1.0, 0.15, 'paper', 0.1, g)
    return g


def tray(dark):
    def build(_):
        g = group('tray')
        ring(66, 66, 12, 56, 56, 8, 1.6, 0.7, 'aluDark' if dark else 'satin', 0, g)
        rbox(56, 56, 0.6, 8, 0.1, 'well', -0.1, g)
        return g
    return build


# shutters (tool/render/items/shutter.js, mm -> scaled to dp)
def film_release(state, with_lever=True, cap=True):
    k = 138 / 40
    g = group('release')
    g.scale = (k, k, k)
    lathe([(0, 0), (9.0, 0), (9.0, 2.6), (8.6, 3.0), (6.9, 3.0), (6.9, 2.4), (0, 2.4)], 'satin', 128, g, 'collar')
    knurl(9.0, 2.2, 90, 'satin', 0.45, 0.3, g)
    cylinder(6.9, 0.4, 'gap', 2.3, 96, 0, g)
    if cap:
        top = 4.0 if state == 'down' else 4.9
        prof = [(0, top), (1.4, top), (1.5, top - 0.02)]
        r = 1.6
        while r <= 5.6:
            prof.append((r, top - 0.12 * ((r - 1.4) / 4.2) ** 2 - (int(r * 2) % 2) * 0.03))
            r += 0.5
        prof += [(6.0, top - 0.35), (6.2, top - 0.8), (6.2, 2.4), (0, 2.4)]
        press = moving(group('press', g), 'press')
        lathe(prof, 'polished', 128, press, 'cap')
        cylinder(1.0, 0.6, 'gap', top - 0.45, 48, 0, press)
    if with_lever:
        lever(g)
    return g


def lever(parent, angle=-LEVER_REST):
    pivot = moving(group('lever', parent), 'lever')
    pivot.rotation_euler.z = angle
    length = 15.7
    pts = capsule_pts(0, 0, -length, 0, 2.7)
    # tapered bar: hub end 2.7, tip 1.2
    pts = []
    for i in range(13):
        t = -math.pi / 2 + math.pi * i / 12
        pts.append((2.7 * math.cos(t), 2.7 * math.sin(t)))
    for i in range(13):
        t = math.pi / 2 + math.pi * i / 12
        pts.append((-length + 1.2 * math.cos(t), 1.2 * math.sin(t)))
    # under the collar (top 3.0), so the release sinks into the hub and the
    # bar never shows through the pressed cap
    slab([pts], 1.4, 0.25, 'satin', 1.1, pivot, 'bar')
    cylinder(2.0, 1.6, 'blackPaint', 2.2, 48, 0.4, pivot).location.x = -length
    return pivot


def f_shutter(state):
    return film_release(state)


def f_lever(_):
    k = 138 / 40
    g = group('lever-only')
    g.scale = (k, k, k)
    lever(g)
    return g


def f_release(state):
    return film_release(state, with_lever=False)


def f_run(state):
    k = 108 / 30
    g = group('run')
    g.scale = (k, k, k)
    lathe([(0, 0), (11.0, 0), (11.0, 2.8), (10.4, 3.4), (8.2, 3.4), (8.0, 2.6), (0, 2.6)], 'blackPaint', 128, g, 'collar')
    knurl(10.9, 2.6, 36, 'blackPaint', 0.7, 0.2, g)
    cylinder(8.0, 0.4, 'gap', 2.5, 96, 0, g)
    top = 3.6 if state == 'down' else 5.4
    press = moving(group('press', g), 'press')
    lathe([(0, top), (3.0, top - 0.08), (5.6, top - 0.35), (6.9, top - 0.9), (7.4, top - 1.6), (7.4, 2.6), (0, 2.6)], 'redGloss', 128, press, 'cap')
    text('RUN', 3.7, 'whiteInk', top - 0.02, 0.06, 'CENTER', 'InterDisplay-Bold.ttf', 1.0, press)
    return g


def digital_key(rec):
    def build(state):
        k = 96 / 30
        g = group('key')
        g.scale = (k, k, k)
        rbox(26, 22, 2.2, 1.0, 0.4, 'alu', 0, g)
        rbox(20.4, 16.4, 1.0, 0.8, 0.2, 'gap', 1.2, g)
        base = 2.2 if state == 'down' else 3.2
        press = moving(group('press', g), 'press')
        rbox(18.6, 14.6, 3.2, 1.5, 0.8, 'satin', base - 1.0, press)
        if rec:
            # a recording lamp: a chrome bezel and a domed red lens
            cylinder(3.0, 0.3, 'polished', base + 2.2, 64, 0.1, press)
            R, h = 2.5, 0.75
            lathe([(R * i / 12, base + 2.5 + h * (1 - (i / 12) ** 2)) for i in range(13)] + [(R, base + 2.5), (0, base + 2.5)],
                  'ledRed', 64, press, 'lens')
        return g
    return build


# ------------------------------------------------------------------ digital
def d_panel(_):
    g = group('panel')
    rbox(412, 1000, 2, 0.1, 0.4, 'alu', -2, g)
    return g


def d_frame(_):
    g = group('frame')
    ring(200, 200, 10, 180, 180, 4, 2.4, 1.0, 'glossBlack', 0, g)
    ring(204, 204, 12, 198, 198, 10, 0.8, 0.3, 'aluDark', 0, g)
    return g


def pill(w, h):
    def build(state):
        g = group('pill')
        rbox(w + 4, h + 4, 0.6, (h + 4) / 2, 0.1, 'gap', -0.4, g)
        ring(w + 8, h + 8, (h + 8) / 2, w + 3, h + 3, (h + 3) / 2, 0.8, 0.3, 'aluDark', 0, g)
        rbox(w, h, 4.2, h / 2, 1.4, 'rubber', 0.2 if state == 'down' else 1.1, moving(group('press', g), 'press'))
        return g
    return build


def bezel(w, h, r):
    def build(_):
        g = group('bezel')
        ring(w + 12, h + 12, r + 4, w, h, r, 1.8, 0.8, 'glossBlack', 0, g)
        ring(w + 16, h + 16, r + 6, w + 11, h + 11, r + 4, 0.6, 0.25, 'aluDark', 0, g)
        return g
    return build


def d_rocker(state):
    g = group('rocker')
    ring(108, 48, 24, 102, 42, 21, 0.8, 0.3, 'aluDark', 0, g)
    rbox(102, 42, 0.6, 21, 0.1, 'gap', -0.4, g)
    key = moving(group('key', g), 'rock')
    rbox(100, 40, 4.2, 20, 1.4, 'rubber', 0.8, key)
    box(1, 26, 0.6, 'gap', (0, 0, 5.0), 0, 0, key)
    for t, x in (('W', -25), ('T', 25)):
        text(t, 11, 'whiteInk', 4.95, 0.08, 'CENTER', 'InterDisplay-Bold.ttf', 1.0, key, (x, 0))
    key.rotation_euler.y = {'w': -0.035, 't': 0.035}.get(state, 0.0)
    return g


UPDOWN = dict(states=['up', 'down'], stateYaw0=['down'])

PARTS = {
    'film': {
        'panel': dict(canvas=(412, 1000), yaws=[0], spp=96, px=4, noShadow=True, build=f_panel),
        'plate-top': dict(canvas=(412, 180), yaws=YAWS, spp=96, px=3, edge=20, build=f_plate(180, 'top')),
        'plate-bot': dict(canvas=(412, 140), yaws=YAWS, spp=96, px=3, edge=20, build=f_plate(140, 'bot')),
        'frame': dict(canvas=(220, 220), box=(196, 196), yaws=YAWS, spp=128, slice=40, build=f_frame),
        'flash': dict(canvas=(100, 60), yaws=YAWS, build=f_flash),
        'flashtab': dict(canvas=(36, 36), yaws=YAWS, build=f_flashtab),
        'aspect': dict(canvas=(60, 64), yaws=YAWS, build=f_aspect),
        'aspecttop': dict(canvas=(60, 64), yaws=YAWS, noShadow=True, build=f_aspect_top),
        'lens': dict(canvas=(56, 56), yaws=YAWS, build=lens_knob(False)),
        'lensdot': dict(canvas=(40, 40), yaws=[0], noShadow=True, build=lensdot),
        'menu': dict(canvas=(48, 48), yaws=YAWS, build=f_menu, **UPDOWN),
        'memo': dict(canvas=(140, 72), box=(120, 52), yaws=YAWS, sliceX=36, build=f_memo),
        'print': dict(canvas=(84, 92), yaws=YAWS, build=f_print),
        'tray': dict(canvas=(84, 84), yaws=YAWS, build=tray(False)),
        'shutter': dict(canvas=(150, 150), yaws=YAWS, build=f_shutter, **UPDOWN),
        'lever': dict(canvas=(150, 150), yaws=[0], noShadow=True, build=f_lever),
        'release': dict(canvas=(150, 150), yaws=[0], states=['up', 'down'], build=f_release),
        'run': dict(canvas=(120, 120), yaws=YAWS, build=f_run, **UPDOWN),
    },
    'digital': {
        'panel': dict(canvas=(412, 1000), yaws=PANEL_YAWS, spp=64, px=3, noShadow=True, build=d_panel),
        'frame': dict(canvas=(220, 220), box=(204, 204), yaws=YAWS, spp=128, slice=40, build=d_frame),
        'pill': dict(canvas=(96, 56), yaws=YAWS, build=pill(76, 36), **UPDOWN),
        'pillwide': dict(canvas=(84, 56), yaws=YAWS, build=pill(64, 36), **UPDOWN),
        'pillsmall': dict(canvas=(64, 56), yaws=YAWS, build=pill(44, 36), **UPDOWN),
        'lens': dict(canvas=(56, 56), yaws=YAWS, build=lens_knob(True)),
        'lensdot': dict(canvas=(40, 40), yaws=[0], noShadow=True, build=lensdot),
        'lcd': dict(canvas=(124, 84), box=(116, 76), yaws=YAWS, slice=26, build=bezel(100, 60, 6)),
        'review': dict(canvas=(84, 84), yaws=YAWS, build=bezel(64, 64, 7)),
        'rocker': dict(canvas=(124, 64), yaws=YAWS, states=['mid', 'w', 't'], stateYaw0=['w', 't'], build=d_rocker),
        'tray': dict(canvas=(84, 84), yaws=YAWS, build=tray(True)),
        'shutter': dict(canvas=(120, 120), yaws=YAWS, build=digital_key(False), **UPDOWN),
        'rec': dict(canvas=(120, 120), yaws=YAWS, build=digital_key(True), **UPDOWN),
    },
}
