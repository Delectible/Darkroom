"""The Super 8 projection reel for the corkboard: a grey plastic spool
(front flange with five round windows, a hub with its drive hole) with
film wound on it showing through, seen from the front, its shadow on the
cork. Transparent, so the board shows round it.

    /opt/bpyenv/venv/bin/python reel.py OUT.webp [--draft]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import kit  # noqa: E402
from PIL import Image  # noqa: E402

R = 100.0     # flange radius (units = canvas dp: the image is 2R + margin square)
T = 2.2       # flange thickness
GAP = 9.0     # between the flanges (the film's width)
HOLE_R, HOLE_AT = 21.0, 55.0
SIZE = 240.0  # canvas, dp
PX = 4.0      # pixels per dp


def plastic():
    m, b = kit._principled('reelPlastic', (0.6, 0.62, 0.64), 0.0, 0.42)
    nt = m.node_tree
    n = nt.nodes.new('ShaderNodeTexNoise')
    n.inputs['Scale'].default_value = 6.0
    nt.links.new(kit._coords(nt), n.inputs['Vector'])
    kit._bump(m, b, n.outputs['Fac'], 0.04, 0.1)
    kit._mats['reelPlastic'] = m


def film():
    m, b = kit._principled('woundFilm', (0.05, 0.03, 0.02), 0.0, 0.3, **{'Coat Weight': 0.5})
    nt = m.node_tree
    w = nt.nodes.new('ShaderNodeTexWave')
    w.wave_type = 'RINGS'
    w.rings_direction = 'Z'
    w.inputs['Scale'].default_value = 1.6
    w.inputs['Distortion'].default_value = 0.4
    nt.links.new(kit._coords(nt), w.inputs['Vector'])
    kit._bump(m, b, w.outputs['Fac'], 0.15, 0.2)
    ramp = nt.nodes.new('ShaderNodeMix')
    ramp.data_type = 'RGBA'
    ramp.inputs['A'].default_value = (0.04, 0.025, 0.018, 1)
    ramp.inputs['B'].default_value = (0.12, 0.07, 0.04, 1)
    nt.links.new(w.outputs['Fac'], ramp.inputs['Factor'])
    nt.links.new(ramp.outputs['Result'], b.inputs['Base Color'])
    kit._mats['woundFilm'] = m


def flange(z, front):
    """A flange: a disc (front: with five round windows and pressed lips
    round them and a rim round the edge)."""
    outline = [kit.ellipse_pts(0, 0, R, R, 160)]
    holes = [(math.cos(math.radians(90 + i * 72)) * HOLE_AT, math.sin(math.radians(90 + i * 72)) * HOLE_AT)
             for i in range(5)]
    if front:
        outline += [kit.ellipse_pts(x, y, HOLE_R, HOLE_R, 64)[::-1] for x, y in holes]
    kit.slab(outline, T, 0.5, 'reelPlastic', z, name='flange')
    if front:
        kit.lathe([(R - 7, z + T), (R - 5.5, z + T + 0.9), (R - 1.2, z + T + 0.9), (R, z + T)],
                  'reelPlastic', 160, name='rim')
        for x, y in holes:
            lip = kit.lathe([(HOLE_R - 0.2, z + T), (HOLE_R + 1.0, z + T + 0.7), (HOLE_R + 2.8, z + T)],
                            'reelPlastic', 64, name='lip')
            lip.location.x, lip.location.y = x, y


def main(out, draft):
    scn = kit.reset()
    plastic()
    film()
    # back flange on the cork, the wound film, the front flange
    flange(0, False)
    # a reel part wound: the back flange shows past the film in the windows
    kit.cylinder(R * 0.7, GAP, 'woundFilm', T, 160, 0.3, name='film')
    kit.cylinder(16, GAP, 'reelPlastic', T, 96, 0, name='core')
    flange(T + GAP, True)
    # hub: a raised boss with a square drive hole and a keyway
    z = 2 * T + GAP
    kit.cylinder(18, 2.4, 'reelPlastic', z, 96, 0.8, name='hub')
    kit.box(9, 9, 6, 'gap', (0, 0, z + 1), 0.0, 0.4)
    kit.box(3, 6, 6, 'gap', (0, 7.5, z + 1), 0.0, 0.2)
    kit.shadow_catcher(1200)
    kit.area_light('key', (-0.55, 0.6, 0.95), 1600, (900, 700), 2.2e7, (1.0, 0.965, 0.92))
    kit.area_light('fill', (0.35, -0.85, 0.55), 1600, (1200, 500), 3.0e6, (1.0, 0.9, 0.82))
    kit.area_light('scrim', (0.2, 0.35, 1.0), 1600, (1800, 600), 4.5e6, (1, 1, 1))
    kit.camera(SIZE, SIZE, PX)
    scn.camera.location = (0, 0, 1400)
    scn.camera.data.angle = 2 * math.atan(SIZE / 2 / 1400)
    scn.cycles.samples = 32 if draft else 256
    tmp = out + '.png'
    scn.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = Image.open(tmp).convert('RGBA')
    os.remove(tmp)
    img.save(out, 'WEBP', quality=90, method=6)
    print('wrote', out, img.size)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    main(args[0], '--draft' in args)
