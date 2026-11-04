"""Splits a live 3D body (.glb from export_glb.py) so the app loads only what
it shows (2.0.7):

  <body>.glb            the body, its parts and ONE finish (the default skin),
                        body maps at 2048 (enough for screens up to ~1080 px
                        wide: the 4096 level was never sampled there)
  <body>_hd.glb         the body maps at full size (4096), swapped in on
                        sharper screens (a swatch: one triangle + material)
  <body>_skin_<k>.glb   each other skin's maps (a swatch): base colour, and
                        metal-rough / normal only where they differ from the
                        default's (most skins share them)

Every finish used to be a full copy of the same three panels with its own
three maps, all resident at once (~290 MB of GPU memory for both bodies).
The app swaps a swatch's textures onto the one set of panels
(whole_body.dart, LiveBody.setFinish).

  python3 slim_glb.py IN.glb OUT_DIR DEFAULT_SKIN
"""

import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

LO = 2048          # body map size in the base file
SAME = 8           # max per-channel difference still counted as the same map


def read_glb(path):
    b = Path(path).read_bytes()
    jlen = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + jlen])
    bin_start = 20 + jlen + 8
    blen = struct.unpack('<I', b[20 + jlen:24 + jlen])[0]
    return j, b[bin_start:bin_start + blen]


def write_glb(path, j, chunks):
    """chunks: list of bytes per bufferView, in j['bufferViews'] order."""
    out = bytearray()
    for i, data in enumerate(chunks):
        while len(out) % 4:
            out.append(0)
        j['bufferViews'][i]['byteOffset'] = len(out)
        j['bufferViews'][i]['byteLength'] = len(data)
        j['bufferViews'][i]['buffer'] = 0
        out += data
    while len(out) % 4:
        out.append(0)
    j['buffers'] = [{'byteLength': len(out)}]
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
        f.write(struct.pack('<II', len(out), 0x004E4942) + bytes(out))


def view_bytes(j, binary, i):
    v = j['bufferViews'][i]
    o = v.get('byteOffset', 0)
    return binary[o:o + v['byteLength']]


def decode(data):
    return Image.open(io.BytesIO(data))


def encode(img, mime):
    buf = io.BytesIO()
    if mime == 'image/jpeg':
        img.convert('RGB').save(buf, 'JPEG', quality=95)
    else:
        img.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def shrink(img, role):
    if img.width <= LO:
        return img
    small = img.resize((LO, LO * img.height // img.width), Image.LANCZOS)
    if role != 'normal':
        return small
    # re-normalise the averaged vectors
    a = np.asarray(small.convert('RGB')).astype(np.float32) / 127.5 - 1
    a /= np.maximum(np.linalg.norm(a, axis=2, keepdims=True), 1e-6)
    return Image.fromarray(np.clip((a + 1) * 127.5, 0, 255).astype(np.uint8))


def same(a, b):
    x = np.asarray(a.convert('RGBA')).astype(np.int16)
    y = np.asarray(b.convert('RGBA')).astype(np.int16)
    return x.shape == y.shape and int(np.abs(x - y).max()) <= SAME


def prune(j, binary):
    """Drops everything no node reaches, remapping indices; returns the
    bufferView bytes for the kept views."""
    meshes = sorted({n['mesh'] for n in j['nodes'] if 'mesh' in n})
    mats, accs = set(), set()
    for m in meshes:
        for p in j['meshes'][m]['primitives']:
            if 'material' in p:
                mats.add(p['material'])
            accs.update(p['attributes'].values())
            if 'indices' in p:
                accs.add(p['indices'])
    texs = set()
    for m in mats:
        mat = j['materials'][m]
        for k, v in mat.get('pbrMetallicRoughness', {}).items():
            if k.endswith('Texture'):
                texs.add(v['index'])
        for k in ('normalTexture', 'occlusionTexture', 'emissiveTexture'):
            if k in mat:
                texs.add(mat[k]['index'])
    imgs = {j['textures'][t]['source'] for t in texs}
    views = {j['accessors'][a]['bufferView'] for a in accs if 'bufferView' in j['accessors'][a]}
    views |= {j['images'][i]['bufferView'] for i in imgs}

    def remap(items, keep):
        keep = sorted(keep)
        return [items[i] for i in keep], {old: new for new, old in enumerate(keep)}

    j['meshes'], mm = remap(j['meshes'], meshes)
    j['materials'], ma = remap(j['materials'], mats)
    j['accessors'], ac = remap(j['accessors'], accs)
    j['textures'], tx = remap(j['textures'], texs)
    j['images'], im = remap(j['images'], imgs)
    chunks = [view_bytes(j, binary, v) for v in sorted(views)]
    j['bufferViews'], vw = remap(j['bufferViews'], views)
    for n in j['nodes']:
        if 'mesh' in n:
            n['mesh'] = mm[n['mesh']]
    for m in j['meshes']:
        for p in m['primitives']:
            if 'material' in p:
                p['material'] = ma[p['material']]
            p['attributes'] = {k: ac[v] for k, v in p['attributes'].items()}
            if 'indices' in p:
                p['indices'] = ac[p['indices']]
    for mat in j['materials']:
        for k, v in mat.get('pbrMetallicRoughness', {}).items():
            if k.endswith('Texture'):
                v['index'] = tx[v['index']]
        for k in ('normalTexture', 'occlusionTexture', 'emissiveTexture'):
            if k in mat:
                mat[k]['index'] = tx[mat[k]['index']]
    for t in j['textures']:
        t['source'] = im[t['source']]
    for i in j['images']:
        i['bufferView'] = vw[i['bufferView']]
    for a in j['accessors']:
        if 'bufferView' in a:
            a['bufferView'] = vw[a['bufferView']]
    return chunks


def swatch(name, maps, sampler):
    """A glb with one triangle wearing [maps] ({'base'|'mr'|'normal': (bytes,
    mime)}): the app takes the material's textures and drops the rest."""
    pos = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0]], np.float32)
    nrm = np.array([[0, 0, 1]] * 3, np.float32)
    uv = np.array([[0, 0], [1, 0], [0, 1]], np.float32)
    chunks = [pos.tobytes(), nrm.tobytes(), uv.tobytes()]
    views = [{'buffer': 0}, {'buffer': 0}, {'buffer': 0}]
    accs = [
        {'bufferView': 0, 'componentType': 5126, 'count': 3, 'type': 'VEC3', 'min': [0, 0, 0], 'max': [1, 1, 0]},
        {'bufferView': 1, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
        {'bufferView': 2, 'componentType': 5126, 'count': 3, 'type': 'VEC2'},
    ]
    images, textures = [], []
    mat = {'name': name, 'doubleSided': True, 'pbrMetallicRoughness': {}}
    for role, (data, mime) in maps.items():
        chunks.append(data)
        views.append({'buffer': 0})
        images.append({'name': f'{name}-{role}', 'mimeType': mime, 'bufferView': len(views) - 1})
        textures.append({'sampler': 0, 'source': len(images) - 1})
        ref = {'index': len(textures) - 1}
        if role == 'base':
            mat['pbrMetallicRoughness']['baseColorTexture'] = ref
        elif role == 'mr':
            mat['pbrMetallicRoughness']['metallicRoughnessTexture'] = ref
        else:
            mat['normalTexture'] = ref
    j = {
        'asset': {'version': '2.0', 'generator': 'darkroom slim_glb'},
        'scene': 0,
        'scenes': [{'nodes': [0]}],
        'nodes': [{'name': 'swatch', 'mesh': 0}],
        'meshes': [{'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2}, 'material': 0}]}],
        'materials': [mat],
        'accessors': accs,
        'bufferViews': views,
        'samplers': [sampler],
        'textures': textures,
        'images': images,
    }
    return j, chunks


def main(src, out_dir, default):
    out = Path(out_dir)
    body = Path(src).stem
    j, binary = read_glb(src)
    mats = {m['name']: i for i, m in enumerate(j['materials'])}
    sampler = (j.get('samplers') or [{}])[0]

    def maps_of(mat_name):
        mat = j['materials'][mats[mat_name]]
        out = {}
        pbr = mat.get('pbrMetallicRoughness', {})
        for role, ref in (('base', pbr.get('baseColorTexture')), ('mr', pbr.get('metallicRoughnessTexture')),
                          ('normal', mat.get('normalTexture'))):
            if ref is None:
                continue
            img = j['images'][j['textures'][ref['index']]['source']]
            out[role] = (img['bufferView'], img.get('mimeType', 'image/png'))
        return out

    skins = sorted({n['name'].split('.')[1] for n in j['nodes'] if n.get('name', '').startswith('finish.')})
    assert default in skins, (default, skins)
    default_maps = maps_of(f'{body}-finish-{default}')
    decoded = {}

    def img(view):
        if view not in decoded:
            decoded[view] = decode(view_bytes(j, binary, view))
        return decoded[view]

    # The other skins, as swatches with only what differs from the default.
    for k in skins:
        if k == default:
            continue
        maps = {}
        for role, (view, mime) in maps_of(f'{body}-finish-{k}').items():
            if role != 'base' and same(img(view), img(default_maps[role][0])):
                continue
            maps[role] = (view_bytes(j, binary, view), mime)
        sj, sc = swatch(f'{body}-skin-{k}', maps, sampler)
        write_glb(out / f'{body}_skin_{k}.glb', sj, sc)
        print(f'{body}_skin_{k}.glb: {sorted(maps)}')

    # Full-size body maps, for sharp screens.
    body_maps = maps_of(f'{body}-body')
    hj, hc = swatch(f'{body}-hd', {r: (view_bytes(j, binary, v), m) for r, (v, m) in body_maps.items()}, sampler)
    write_glb(out / f'{body}_hd.glb', hj, hc)
    print(f'{body}_hd.glb: {sorted(body_maps)}')

    # The base: one finish (the other finish nodes stay, empty, so their
    # names still list the skins), body maps at LO.
    for n in j['nodes']:
        name = n.get('name', '')
        if name.startswith('finish.') and name.split('.')[1] != default:
            n.pop('mesh', None)
    shrunk = {}
    for role, (view, mime) in body_maps.items():
        shrunk[view] = encode(shrink(img(view), role), mime)
    old_views = list(range(len(j['bufferViews'])))
    raw = {v: (shrunk.get(v) or view_bytes(j, binary, v)) for v in old_views}
    # prune() reads bytes through view_bytes: feed it a binary with the
    # shrunk images laid out where it expects them
    patched = bytearray()
    for v in old_views:
        while len(patched) % 4:
            patched.append(0)
        j['bufferViews'][v]['byteOffset'] = len(patched)
        j['bufferViews'][v]['byteLength'] = len(raw[v])
        patched += raw[v]
    chunks = prune(j, bytes(patched))
    write_glb(out / f'{body}.glb', j, chunks)
    print(f'{body}.glb: {len(j["images"])} maps, skins {skins}, default {default}')


if __name__ == '__main__':
    main(*sys.argv[1:4])
