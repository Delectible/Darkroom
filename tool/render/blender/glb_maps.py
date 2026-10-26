"""Puts the lossless bakes of the roughness/metal and normal maps into a .glb.

    python3 glb_maps.py BODY.glb BAKE_DIR

Blender's glTF exporter writes every texture as JPEG (or every one as PNG).
JPEG is fine for base colour, but on the data maps it shows: metal sits in
the blue channel, which JPEG keeps at half resolution in 8x8 / 16x16
blocks, and the roughness / normal steps it leaves catch the light as
square patches on the shiny plates. So the `*-mr` and `*-normal` images are
swapped for the PNGs export_glb.py saved next to the bake (BAKE_DIR/<image
name>.png); base colour stays JPEG. Used by export_glb.py after every
export; runnable on its own for a .glb whose bakes are still around.
"""
import io
import json
import os
import struct
import sys

from PIL import Image


def _png(path):
    buf = io.BytesIO()
    Image.open(path).convert('RGB').save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def lossless_maps(glb_path, bake_dir):
    data = open(glb_path, 'rb').read()
    magic, version, _ = struct.unpack('<4sII', data[:12])
    assert magic == b'glTF' and version == 2, glb_path
    json_len, json_type = struct.unpack('<I4s', data[12:20])
    assert json_type == b'JSON'
    doc = json.loads(data[20:20 + json_len])
    bin_start = 20 + json_len + 8
    bin_len = struct.unpack('<I', data[20 + json_len:24 + json_len])[0]
    blob = data[bin_start:bin_start + bin_len]

    views = doc['bufferViews']
    chunks = [blob[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']] for v in views]
    swapped = []
    for image in doc.get('images', []):
        name = image.get('name', '')
        if not (name.endswith('-mr') or name.endswith('-normal')):
            continue
        src = os.path.join(bake_dir, name + '.png')
        if not os.path.exists(src):
            print(f'glb_maps: no lossless bake for {name}, kept as is', flush=True)
            continue
        chunks[image['bufferView']] = _png(src)
        image['mimeType'] = 'image/png'
        swapped.append(name)

    # Lay the views out again (4-byte aligned) with their new lengths.
    out = bytearray()
    for v, chunk in zip(views, chunks):
        out += b'\0' * (-len(out) % 4)
        v['byteOffset'] = len(out)
        v['byteLength'] = len(chunk)
        out += chunk
    out += b'\0' * (-len(out) % 4)
    doc['buffers'][0]['byteLength'] = len(out)

    js = json.dumps(doc, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(glb_path, 'wb') as f:
        f.write(struct.pack('<4sII', b'glTF', 2, total))
        f.write(struct.pack('<I4s', len(js), b'JSON') + js)
        f.write(struct.pack('<I4s', len(out), b'BIN\0') + bytes(out))
    print(f'glb_maps: {len(swapped)} maps lossless in {glb_path} ({total / 1e6:.1f} MB)', flush=True)
    return swapped


if __name__ == '__main__':
    lossless_maps(sys.argv[1], sys.argv[2])
