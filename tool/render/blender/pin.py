"""Push pins for the corkboard: a traditional plastic push pin (flange,
waisted grip, domed cap, steel needle) stuck in the cork, leaning a little
to the top left, its shadow on the board. One transparent webp per colour.

The canvas is 40 x 40 dp with the needle entering the cork at (20, 16)
from the top left (`PinImage` in corkboard_screen.dart lines it up).

    /opt/bpyenv/venv/bin/python pin.py OUTDIR [--draft]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import kit  # noqa: E402
from PIL import Image  # noqa: E402

W = H = 40.0      # canvas, dp
AT = (20.0, 16.0)  # where the needle enters, dp from the top left
PX = 8.0           # pixels per dp
LEAN = math.radians(22)

# The app's pin colours (`_pinColors`), in order.
COLORS = ['D32F2F', '1976D2', 'FBC02D', '388E3C', '7B1FA2']

# (r, z) up the pin's axis, z = 0 at the cork.
BODY = [
    (0.0, 3.0), (6.6, 3.0), (7.3, 3.3), (7.5, 3.9), (7.1, 4.6), (4.4, 5.3),
    (3.5, 6.0), (3.0, 7.6), (2.9, 9.2), (3.1, 10.8), (3.7, 12.0),
    (5.9, 12.5), (6.4, 13.1), (6.3, 13.9), (5.4, 14.6), (3.4, 15.1), (0.0, 15.25),
]


def srgb(hexs):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(lin(int(hexs[i:i + 2], 16)) for i in (0, 2, 4))


def main(out_dir, draft):
    scn = kit.reset()
    plastic, b = kit._principled('pinPlastic', (0.5, 0.1, 0.1), 0.0, 0.32,
                                 **{'Coat Weight': 0.45, 'Coat Roughness': 0.2})
    kit._mats['pinPlastic'] = plastic
    kit._principled('pinSteel', (0.8, 0.8, 0.82), 1.0, 0.22)
    kit._mats['pinSteel'] = bpy.data.materials['pinSteel']

    pivot = bpy.data.objects.new('pin', None)
    bpy.context.collection.objects.link(pivot)
    body = kit.lathe(BODY, 'pinPlastic', 96, name='body')
    needle = kit.cylinder(0.55, 6.5, 'pinSteel', -3.0, 32, 0.0, name='needle')
    for o in (body, needle):
        o.parent = pivot
    # lean the head toward the top left (the key light), shadow to the lower right
    pivot.rotation_euler = (-LEAN / math.sqrt(2), -LEAN / math.sqrt(2), 0)

    kit.shadow_catcher(400)
    kit.area_light('key', (-0.55, 0.6, 0.95), 1600, (900, 700), 2.2e7, (1.0, 0.965, 0.92))
    kit.area_light('fill', (0.35, -0.85, 0.55), 1600, (1200, 500), 3.0e6, (1.0, 0.9, 0.82))
    kit.area_light('scrim', (0.2, 0.35, 1.0), 1600, (1800, 600), 4.5e6, (1, 1, 1))
    kit.camera(W, H, PX)
    # frame the canvas so the needle's entry lands at AT
    scn.camera.location = (W / 2 - AT[0], AT[1] - H / 2, 2000)
    scn.cycles.samples = 32 if draft else 256
    os.makedirs(out_dir, exist_ok=True)
    for i, c in enumerate(COLORS):
        b.inputs['Base Color'].default_value = (*srgb(c), 1)
        tmp = os.path.join(out_dir, f'pin_{i}.png')
        scn.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = Image.open(tmp).convert('RGBA')
        os.remove(tmp)
        out = os.path.join(out_dir, f'pin_{i}.webp')
        img.save(out, 'WEBP', quality=92, method=6)
        print('wrote', out, img.size, flush=True)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    main(args[0], '--draft' in args)
