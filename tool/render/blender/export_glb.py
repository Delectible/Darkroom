"""The camera bodies as live 3D models for the app (Flutter Scene).

    /opt/bpyenv/venv/bin/python export_glb.py OUT [--mode film] [--size 4096] [--draft]

Builds each body exactly as whole_body.py renders it, then:
- every piece that moves (parts.py `moving`: keys, dial, lever, flash tab,
  rocker, shutter caps) becomes its own node, named `mv.<part>.<how>`, so
  the app can press / turn / slide it; each placed part's group is
  `part.<name>` (the alternative shutter, Super 8 RUN / camcorder REC, is
  `part.shutteralt`, hidden by the app unless that camera is picked);
- the procedural Cycles materials are baked into two texture atlases (the
  static body; the moving pieces): base colour (with ambient occlusion
  multiplied in), roughness + metal, and a normal map (leather pebbles,
  brushing, turning marks);
- the static body becomes one mesh, each moving piece one mesh.

Writes OUT/<mode>.glb and OUT/<mode>.json (design layout, press travel, the
strap lug, the camera). Units: 1 = 1 design dp; x right, y up, z toward the
viewer (the face at z = 0), the same as the renders.
"""
import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import kit  # noqa: E402
import parts as P  # noqa: E402
import whole_body as WB  # noqa: E402

# How far each pressed piece travels (its own units, before the part's
# scale), from the down states in parts.py.
PRESS = {
    'menu': 1.4, 'shutter': 0.9, 'shutteralt': 1.8, 'pill': 0.9, 'pillwide': 0.9, 'pillsmall': 0.9,
}
PRESS_DIGITAL = {'shutter': 1.0, 'shutteralt': 1.0}


def all_objects(root):
    return [root, *root.children_recursive]


def to_meshes(root):
    """Text, curves and modifiers baked down to plain meshes."""
    bpy.ops.object.select_all(action='DESELECT')
    objs = [o for o in all_objects(root) if o.type in ('FONT', 'CURVE') or (o.type == 'MESH' and o.modifiers)]
    for o in objs:
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.convert(target='MESH')


def owner(o):
    """The nearest moving ancestor of [o] (or None: the static body)."""
    p = o.parent
    while p is not None:
        if 'mv' in p.keys():
            return p
        p = p.parent
    return None


def part_name(o):
    p = o
    while p is not None:
        if p.name.startswith('at-'):
            return p.name[3:].split('.')[0]
        p = p.parent
    return 'body'


def drop_backs(objs):
    """Faces turned away from the viewer (the body never turns past ~50
    degrees) take no texture space."""
    import bmesh
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        # Cycles never minded inside-out faces; baking and the live
        # renderer (back faces culled) do
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        if o.matrix_world.determinant() < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
        rot = o.matrix_world.to_3x3()
        back = [f for f in bm.faces if (rot @ f.normal).normalized().z < -0.6]
        if back and len(back) < len(bm.faces):
            bmesh.ops.delete(bm, geom=back, context='FACES')
        bm.to_mesh(o.data)
        bm.free()


def unwrap(objs):
    """One shared UV atlas for [objs], the same texels per dp everywhere."""
    import bmesh
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.002, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    # smart_project sizes each object on its own, in its own (often scaled)
    # space: bring every object to its world-space area
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        uv = bm.loops.layers.uv.active
        mw = o.matrix_world
        world = uvarea = 0.0
        for f in bm.faces:
            vs = [mw @ v.co for v in f.verts]
            for i in range(1, len(vs) - 1):
                world += (vs[i] - vs[0]).cross(vs[i + 1] - vs[0]).length / 2
            us = [lp[uv].uv for lp in f.loops]
            for i in range(1, len(us) - 1):
                a, b = us[i] - us[0], us[i + 1] - us[0]
                uvarea += abs(a.x * b.y - a.y * b.x) / 2
        if uvarea > 0:
            k = math.sqrt(world / uvarea) / 1000
            for f in bm.faces:
                for lp in f.loops:
                    lp[uv].uv *= k
            bm.to_mesh(o.data)
        bm.free()
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.pack_islands(margin=0.002, rotate=True, scale=True)
    bpy.ops.object.mode_set(mode='OBJECT')


def materials_of(objs):
    ms = []
    for o in objs:
        for s in o.material_slots:
            if s.material and s.material not in ms:
                ms.append(s.material)
    return ms


def bake(objs, kind, img, samples, clear=True):
    """Bakes [kind] for [objs] into [img] (each material's target node)."""
    for m in materials_of(objs):
        nt = m.node_tree
        node = nt.nodes.get('bakeTarget') or nt.nodes.new('ShaderNodeTexImage')
        node.name = 'bakeTarget'
        node.image = img
        nt.nodes.active = node
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    scn = bpy.context.scene
    scn.cycles.samples = samples
    scn.render.bake.margin = 6
    scn.render.bake.use_clear = clear
    if kind == 'NORMAL':
        bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT')
    elif kind == 'AO':
        bpy.ops.object.bake(type='AO')
    else:
        bpy.ops.object.bake(type='EMIT')


def emit(objs, socket):
    """Rewires every material to emit its Principled [socket] (so an EMIT
    bake reads it); returns an undo function."""
    undo = []
    for m in materials_of(objs):
        nt = m.node_tree
        b = nt.nodes['Principled BSDF']
        out = nt.nodes['Material Output']
        old = out.inputs['Surface'].links[0].from_socket
        e = nt.nodes.new('ShaderNodeEmission')
        src = b.inputs[socket]
        if src.links:
            nt.links.new(src.links[0].from_socket, e.inputs['Color'])
        else:
            v = src.default_value
            e.inputs['Color'].default_value = tuple(v) if hasattr(v, '__len__') else (v, v, v, 1)
        nt.links.new(e.outputs['Emission'], out.inputs['Surface'])
        undo.append((nt, e, old, out))

    def restore():
        for nt, e, old, out in undo:
            nt.links.new(old, out.inputs['Surface'])
            nt.nodes.remove(e)
    return restore


def new_image(name, size, data):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    img.colorspace_settings.name = 'sRGB' if not data else 'Non-Color'
    return img


def pixels(img):
    a = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
    return a[::-1]  # Blender stores bottom-up


def hidden(objs, hide):
    for o in objs:
        o.hide_render = hide


def bake_atlas(objs, name, size, out_dir, draft, ao_passes):
    """[ao_passes]: (objects, objects hidden meanwhile): the two shutters
    share a place, so each sees the body without the other."""
    s = 1 if draft else 2
    imgs = {}
    for key, socket in (('base', 'Base Color'), ('rough', 'Roughness'), ('metal', 'Metallic')):
        img = new_image(f'{name}-{key}', size, key != 'base')
        restore = emit(objs, socket)
        bake(objs, 'EMIT', img, s)
        restore()
        imgs[key] = pixels(img)
    img = new_image(f'{name}-normal', size, True)
    bake(objs, 'NORMAL', img, s)
    imgs['normal'] = pixels(img)
    img = new_image(f'{name}-ao', size, True)
    for i, (subset, hide) in enumerate(ao_passes):
        if not subset:
            continue
        hidden(hide, True)
        bake(subset, 'AO', img, 8 if draft else 32, clear=i == 0)
        hidden(hide, False)
    imgs['ao'] = pixels(img)
    for m in materials_of(objs):
        n = m.node_tree.nodes.get('bakeTarget')
        if n:
            m.node_tree.nodes.remove(n)
    # base colour (sRGB) x ambient occlusion (softened); metal-rough packed
    # as glTF wants it (G roughness, B metal)
    from PIL import ImageFilter
    ao = Image.fromarray((np.clip(imgs['ao'][..., 0], 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    ao = (np.asarray(ao).astype(np.float32) / 255) ** 0.6
    Image.fromarray((ao * 255).astype(np.uint8)).save(os.path.join(out_dir, f'{name}-ao.png'))
    Image.fromarray((np.clip(imgs['base'][..., :3], 0, 1) * 255).astype(np.uint8)).save(
        os.path.join(out_dir, f'{name}-albedo.png'))
    base = imgs['base'][..., :3] * ao[..., None]
    mr = np.stack([np.ones_like(ao), imgs['rough'][..., 0], imgs['metal'][..., 0]], -1)
    files = {}
    for key, arr in (('base', base), ('mr', mr), ('normal', imgs['normal'][..., :3])):
        path = os.path.join(out_dir, f'{name}-{key}.png')
        Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB').save(path)
        files[key] = path
    return files


def atlas_material(name, files):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']

    def tex(key, data):
        n = nt.nodes.new('ShaderNodeTexImage')
        n.image = bpy.data.images.load(files[key])
        n.image.colorspace_settings.name = 'Non-Color' if data else 'sRGB'
        return n

    nt.links.new(tex('base', False).outputs['Color'], b.inputs['Base Color'])
    sep = nt.nodes.new('ShaderNodeSeparateColor')
    nt.links.new(tex('mr', True).outputs['Color'], sep.inputs['Color'])
    nt.links.new(sep.outputs['Green'], b.inputs['Roughness'])
    nt.links.new(sep.outputs['Blue'], b.inputs['Metallic'])
    nm = nt.nodes.new('ShaderNodeNormalMap')
    nt.links.new(tex('normal', True).outputs['Color'], nm.inputs['Color'])
    nt.links.new(nm.outputs['Normal'], b.inputs['Normal'])
    return m


def join(objs, name, parent, material):
    """Joins [objs] into one mesh named [name] under [parent] (its local
    transform identity) carrying [material]."""
    me = bpy.data.meshes.new(name)
    target = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(target)
    target.parent = parent
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    target.data.materials.clear()
    target.data.materials.append(material)
    for p in target.data.polygons:
        p.material_index = 0
    return target


BAND = 120.0  # dp each side of cutY: the stretch band (inside the viewfinder)


def split_band(body, root):
    """Cuts the static body into body.top / body.mid / body.bot at
    cutY -/+ BAND: the app stretches or squeezes body.mid (origin at cutY)
    to the phone's height and moves the top and bottom pieces with it."""
    import bmesh
    y0 = WB.H / 2 - WB.CUT_Y
    pieces = {}
    for name, keep in (('top', 1), ('mid', 0), ('bot', -1)):
        o = body.copy()
        o.data = body.data.copy()
        o.name = f'body.{name}'
        bpy.context.collection.objects.link(o)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        for plane_y, drop_above in ((y0 + BAND, keep != 1), (y0 - BAND, keep == -1)):
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, plane_y, 0), plane_no=(0, 1, 0),
                                   clear_outer=drop_above, clear_inner=not drop_above)
        bm.to_mesh(o.data)
        bm.free()
        pieces[name] = o
    # the band's origin on the cut line, so a y scale stretches it about it
    mid = pieces['mid']
    mid.data.transform(__import__('mathutils').Matrix.Translation((0, -y0, 0)))
    mid.location.y += y0
    bpy.data.objects.remove(body)
    return pieces


def export(mode, out, size, draft):
    scn = WB.fresh()
    for o in [o for o in bpy.data.objects if o.type == 'LIGHT']:
        bpy.data.objects.remove(o)
    scn.render.engine = 'CYCLES'
    scn.cycles.device = 'CPU'
    root, _ = WB.build(mode)
    lay = WB.LAYOUT[mode]
    x, y = lay['parts']['shutter']
    alt = lay['shutters'][1]
    WB.place(P.PARTS[mode][alt]['build']('up'), mode, 'shutteralt', x, y, root)
    to_meshes(root)
    bpy.context.view_layer.update()

    meshes = [o for o in all_objects(root) if o.type == 'MESH']
    static = [o for o in meshes if owner(o) is None]
    moving = [o for o in meshes if owner(o) is not None]
    tmp = os.path.join(out, f'.{mode}')
    os.makedirs(tmp, exist_ok=True)
    print(f'{mode}: {len(static)} static, {len(moving)} moving meshes', flush=True)
    drop_backs(meshes)
    unwrap(static)
    unwrap(moving)
    def under(name):
        return [o for o in meshes if part_name(o) == name]
    alt_objs, main_objs = under('shutteralt'), under('shutter')
    def passes(objs):
        return [([o for o in objs if o not in alt_objs], alt_objs), ([o for o in objs if o in alt_objs], main_objs)]
    body_files = bake_atlas(static, f'{mode}-body', size, tmp, draft, passes(static))
    print(f'{mode}: body baked', flush=True)
    part_files = bake_atlas(moving, f'{mode}-parts', size // 2, tmp, draft, passes(moving))
    print(f'{mode}: parts baked', flush=True)
    body_mat = atlas_material(f'{mode}-body', body_files)
    part_mat = atlas_material(f'{mode}-parts', part_files)

    # name the nodes the app drives
    owners = {}
    for o in moving:
        owners.setdefault(owner(o), []).append(o)
    for g, objs in owners.items():
        name = f"mv.{part_name(g)}.{g['mv']}"
        g.name = name
        join(objs, name + '.mesh', g, part_mat)
    split_band(join(static, 'body.mesh', root, body_mat), root)
    for o in all_objects(root):
        if o.name.startswith('at-'):
            o.name = 'part.' + o.name[3:].split('.')[0]
    lug = next(o for o in all_objects(root) if o.name.startswith('lug') and o.type == 'EMPTY')
    lug.name = 'anchor.lug'
    root.name = 'body'

    bpy.ops.object.select_all(action='DESELECT')
    for o in all_objects(root):
        o.select_set(True)
    path = os.path.join(out, f'{mode}.glb')
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True, export_yup=False,
        export_lights=False, export_cameras=False, export_image_format='JPEG', export_jpeg_quality=90,
        export_apply=True,
    )
    press = PRESS_DIGITAL if mode == 'digital' else {}
    meta = {
        'design': [WB.W, WB.H], 'cutY': WB.CUT_Y, 'dist': WB.DIST, 'heights': WB.HEIGHTS,
        'layout': lay, 'press': {**PRESS, **press}, 'alt': alt, 'band': BAND,
        'lug': list(lug.matrix_world.translation),
    }
    with open(os.path.join(out, f'{mode}.json'), 'w') as f:
        json.dump(meta, f, indent=1)
    print(f'{mode}: wrote {path} ({os.path.getsize(path) / 1e6:.1f} MB)', flush=True)


def write_hdr(path, rgb):
    """Radiance .hdr (flat RGBE scanlines, top row first)."""
    h, w, _ = rgb.shape
    m = rgb.max(-1)
    e = np.where(m > 1e-32, np.ceil(np.log2(np.maximum(m, 1e-32))), -128).astype(np.int32)
    scale = np.where(m > 1e-32, 256.0 / np.exp2(e.astype(np.float64)), 0)
    rgbe = np.zeros((h, w, 4), np.uint8)
    rgbe[..., :3] = np.clip(rgb * scale[..., None], 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8)
    with open(path, 'wb') as f:
        f.write(b'#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n')
        f.write(f'-Y {h} +X {w}\n'.encode())
        f.write(rgbe.tobytes())


def diffuse_sh(env, d):
    """SH-9 irradiance coefficients as Flutter Scene computes them
    (EnvironmentMap._projectEquirect: real basis, bands 0..2, Lambertian
    A_l / pi folded in), for [env] whose pixel directions are [d]."""
    x, y, z = d[..., 0], d[..., 1], d[..., 2]
    h, w = env.shape[:2]
    lat = np.arcsin(np.clip(y, -1, 1))
    weight = np.cos(lat) * (2 * math.pi * math.pi / (w * h))
    basis = [0.282095 + 0 * x, 0.488603 * y, 0.488603 * z, 0.488603 * x, 1.092548 * x * y, 1.092548 * y * z,
             0.315392 * (3 * z * z - 1), 1.092548 * x * z, 0.546274 * (x * x - y * y)]
    out = []
    for k, b in enumerate(basis):
        c = (env * (b * weight)[..., None]).sum((0, 1))
        c *= 1.0 if k == 0 else (2 / 3 if k <= 3 else 0.25)
        out.append([float(v) for v in c])
    return out


def studio_env(out, width=1024, flip_v=True, flip_x=True):
    """The renders' studio (whole_body.studio's soft boxes, seen from the
    body's centre) as an equirect environment for the live model, in Flutter
    Scene's mapping: u = atan2(z, x) / 2pi + 0.5, v = asin(y) / pi + 0.5.
    Each box shines its area light's radiance (power / (area * pi))."""
    kit.reset()
    WB.studio()
    bpy.context.view_layer.update()
    h = width // 2
    u = (np.arange(width) + 0.5) / width
    v = (np.arange(h) + 0.5) / h
    if flip_v:
        v = v[::-1]
    phi = (u - 0.5) * 2 * math.pi
    lat = (v - 0.5) * math.pi
    lat, phi = np.meshgrid(lat, phi, indexing='ij')
    d = np.stack([np.cos(lat) * np.cos(phi), np.sin(lat), np.cos(lat) * np.sin(phi)], -1)
    if flip_x:
        d[..., 0] *= -1
    env = np.zeros((h, width, 3), np.float32)
    for o in [o for o in bpy.data.objects if o.type == 'LIGHT']:
        L = o.data
        m = o.matrix_world
        c = np.array(m.translation)
        ax = np.array(m.to_3x3().col[0]).astype(np.float64)
        ay = np.array(m.to_3x3().col[1]).astype(np.float64)
        n = np.cross(ax, ay)
        t = (c @ n) / np.where(np.abs(d @ n) < 1e-9, 1e-9, d @ n)
        p = d * t[..., None] - c
        hit = (t > 0) & (np.abs(p @ ax) < L.size / 2) & (np.abs(p @ ay) < L.size_y / 2)
        radiance = L.energy / (L.size * L.size_y * math.pi)
        env[hit] += np.array(L.color) * radiance
    # the renders' world (kit.reset): a grey studio ceiling for reflections,
    # nearly black to diffuse light
    path = os.path.join(out, 'studio.hdr')
    write_hdr(path, env + np.array([0.2, 0.2, 0.21], np.float32))
    sh = diffuse_sh(env + np.array([0.02, 0.02, 0.022], np.float32), d)
    with open(os.path.join(out, 'studio.json'), 'w') as f:
        json.dump({'diffuseSH': sh, 'toneMapping': 'agx', 'exposure': 2 ** 0.35}, f, indent=1)
    print('wrote', path, float(env.max()), flush=True)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('--mode', choices=['film', 'digital'])
    ap.add_argument('--size', type=int, default=4096)
    ap.add_argument('--draft', action='store_true')
    ap.add_argument('--env', action='store_true', help='only the studio environment')
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    if a.env:
        return studio_env(a.out)
    for mode in [a.mode] if a.mode else ['film', 'digital']:
        export(mode, a.out, a.size, a.draft)


if __name__ == '__main__':
    main()
