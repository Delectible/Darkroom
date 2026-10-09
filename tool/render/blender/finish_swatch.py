"""Four finishes for the digital body, side by side (a look check before
re-baking its textures):

    /opt/bpyenv/venv/bin/python finish_swatch.py OUT.png
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401
import kit  # noqa: E402
import whole_body as WB  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

PX = 1.0


def metal(name, base, rough, brushed=True):
    """A brushed (or plain) anodized metal under [name]."""
    m, b = kit._principled(name, base, 1.0, rough)
    if brushed:
        nt = m.node_tree
        n = nt.nodes.new('ShaderNodeTexNoise')
        n.inputs['Scale'].default_value = 1.0
        n.inputs['Detail'].default_value = 6
        nt.links.new(kit._coords(nt, (0.004, 1.8, 1)), n.inputs['Vector'])
        kit._bump(m, b, n.outputs['Fac'], 0.08, 0.2)
    kit._mats[name] = m


def panel(material, y0, y1, z=0.0, depth=0.5):
    """A skin over the face from design y0 to y1 (the full body width)."""
    full = WB.W + 2 * WB.CAP - 8
    o = kit.rbox(full, y1 - y0, depth, 40 if y1 > WB.H else 6, 0.3, material, z)
    o.location.y = WB.H / 2 - (y0 + y1) / 2
    return o


VARIANTS = {
    'Silver + black grip': (lambda: None, lambda: panel('leather', 742, WB.H + 26)),
    'Gunmetal': (lambda: (metal('alu', (0.27, 0.28, 0.3), 0.3), metal('aluDark', (0.1, 0.1, 0.11), 0.34, False)), None),
    'Champagne': (lambda: (metal('alu', (0.82, 0.7, 0.52), 0.27), metal('aluDark', (0.42, 0.35, 0.27), 0.32, False)), None),
    'Two-tone (silver / blue)': (lambda: metal('blueAnod', (0.07, 0.13, 0.34), 0.33), lambda: panel('blueAnod', 120, WB.H + 26)),
}


def main(out):
    tiles = []
    for name, (mats, extra) in VARIANTS.items():
        scn = WB.fresh()
        mats()
        WB.build('digital')
        if extra:
            extra()
        WB.camera(WB.W, WB.H, PX)
        tiles.append((name, WB.render(scn, f'/tmp/swatch-{len(tiles)}', 64)))
        print('done', name, flush=True)
    w, h = tiles[0][1].size
    sheet = Image.new('RGB', (len(tiles) * (w + 16) + 16, h + 70), (20, 20, 22))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf', 22)
    for i, (name, img) in enumerate(tiles):
        bg = Image.new('RGBA', img.size, (12, 11, 10, 255))
        bg.alpha_composite(img)
        sheet.paste(bg.convert('RGB'), (16 + i * (w + 16), 16))
        d.text((20 + i * (w + 16), h + 30), name, font=font, fill=(235, 232, 225))
    sheet.save(out)


if __name__ == '__main__':
    main(sys.argv[-1])
