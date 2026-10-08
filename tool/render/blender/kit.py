"""Modelling kit for the app's camera bodies in Blender (Cycles).

Units are dp. The body face is the XY plane (image right = +X, image up =
+Y), parts stand up along +Z toward the camera, which looks straight down
(orthographic). Everything here builds plain mesh / curve objects and
Principled materials; see parts.py for the parts and render_body.py to
render them.
"""
import math
import os

import bmesh
import bpy

FONTS = '/root/.local/share/fonts'


# ------------------------------------------------------------------ scene
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'
    scn.cycles.device = 'CPU'
    scn.cycles.use_denoising = True
    scn.cycles.denoiser = 'OPENIMAGEDENOISE'
    scn.cycles.max_bounces = 8
    scn.cycles.caustics_reflective = False
    scn.cycles.caustics_refractive = False
    scn.cycles.blur_glossy = 0.5
    scn.render.film_transparent = True
    scn.view_settings.view_transform = 'AgX'
    scn.view_settings.look = 'None'
    scn.view_settings.exposure = 0.35
    scn.render.image_settings.file_format = 'PNG'
    scn.render.image_settings.color_mode = 'RGBA'
    scn.render.image_settings.color_depth = '16'
    world = bpy.data.worlds.new('studio')
    scn.world = world
    world.use_nodes = True
    nt = world.node_tree
    # Dark to the camera and to diffuse light (the leather stays deep), a
    # soft grey studio ceiling for reflections (chrome reads as chrome).
    bg = nt.nodes['Background']
    bg.inputs['Color'].default_value = (0.02, 0.02, 0.022, 1)
    glossy = nt.nodes.new('ShaderNodeBackground')
    glossy.inputs['Color'].default_value = (0.2, 0.2, 0.21, 1)
    path = nt.nodes.new('ShaderNodeLightPath')
    mix = nt.nodes.new('ShaderNodeMixShader')
    nt.links.new(path.outputs['Is Glossy Ray'], mix.inputs['Fac'])
    nt.links.new(bg.outputs['Background'], mix.inputs[1])
    nt.links.new(glossy.outputs['Background'], mix.inputs[2])
    nt.links.new(mix.outputs['Shader'], nt.nodes['World Output'].inputs['Surface'])
    return scn


def _dir(x, y, z):
    n = math.sqrt(x * x + y * y + z * z)
    return x / n, y / n, z / n


def area_light(name, direction, dist, size, energy, color=(1, 1, 1)):
    """A rectangular soft box [dist] away along [direction] (pointing at the
    origin), [size] = (w, h) in dp. Invisible to the camera itself."""
    d = _dir(*direction)
    data = bpy.data.lights.new(name, 'AREA')
    data.shape = 'RECTANGLE'
    data.size, data.size_y = size
    data.energy = energy
    data.color = color
    obj = bpy.data.objects.new(name, data)
    obj.location = (d[0] * dist, d[1] * dist, d[2] * dist)
    # aim -Z of the light at the origin
    obj.rotation_euler = _look_at(obj.location)
    obj.visible_camera = False
    bpy.context.collection.objects.link(obj)
    return obj


def _look_at(loc):
    from mathutils import Vector
    v = Vector((0, 0, 0)) - Vector(loc)
    return v.to_track_quat('-Z', 'Y').to_euler()


def studio():
    """One fixed product studio for every part: a big key soft box high at
    the top left (shadows fall to the lower right, as in the app), a cooler
    strip light right for crisp edges on metal, a weak warm fill low at the
    bottom, a kicker left, and a broad dim scrim overhead for the chrome to
    mirror."""
    area_light('key', (-0.55, 0.6, 0.95), 1600, (900, 700), 2.2e7, (1.0, 0.965, 0.92))
    area_light('strip', (0.95, 0.12, 0.5), 1600, (90, 1400), 5.5e6, (0.94, 0.97, 1.0))
    area_light('fill', (0.35, -0.85, 0.55), 1600, (1200, 500), 4.0e6, (1.0, 0.9, 0.82))
    area_light('kick', (-0.95, -0.25, 0.35), 1600, (150, 600), 2.0e6, (1, 1, 1))
    area_light('scrim', (0.2, 0.35, 1.0), 1600, (1800, 600), 4.5e6, (1, 1, 1))


def camera(w, h, px):
    """Straight down, orthographic, framing w x h dp at [px] pixels per dp."""
    scn = bpy.context.scene
    data = bpy.data.cameras.new('cam')
    data.type = 'ORTHO'
    data.sensor_fit = 'HORIZONTAL'
    data.ortho_scale = w
    data.clip_start = 1
    data.clip_end = 5000
    cam = bpy.data.objects.new('cam', data)
    cam.location = (0, 0, 2000)
    bpy.context.collection.objects.link(cam)
    scn.camera = cam
    scn.render.resolution_x = round(w * px)
    scn.render.resolution_y = round(h * px)
    scn.render.resolution_percentage = 100


def shadow_catcher(size=3000):
    me = bpy.data.meshes.new('catcher')
    s = size / 2
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new('catcher', me)
    obj.is_shadow_catcher = True
    bpy.context.collection.objects.link(obj)
    return obj


# ------------------------------------------------------------------ materials
def _principled(name, base, metal=0.0, rough=0.5, **kw):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*base, 1)
    b.inputs['Metallic'].default_value = metal
    b.inputs['Roughness'].default_value = rough
    for k, v in kw.items():
        b.inputs[k].default_value = v
    return m, b


def _bump(m, b, height_socket, strength, distance=1.0):
    nt = m.node_tree
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = strength
    bump.inputs['Distance'].default_value = distance
    nt.links.new(height_socket, bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], b.inputs['Normal'])
    return bump


def _coords(nt, scale=(1, 1, 1)):
    tc = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Scale'].default_value = scale
    nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
    return mp.outputs['Vector']


_mats = {}


def mat(name):
    if name in _mats:
        return _mats[name]
    if name == 'brushed':      # chrome plates: fine horizontal brushing
        m, b = _principled(name, (0.86, 0.87, 0.89), 1.0, 0.2)
        nt = m.node_tree
        n = nt.nodes.new('ShaderNodeTexNoise')
        n.inputs['Scale'].default_value = 1.0
        n.inputs['Detail'].default_value = 6
        nt.links.new(_coords(nt, (0.004, 1.6, 1)), n.inputs['Vector'])
        _bump(m, b, n.outputs['Fac'], 0.12, 0.2)
    elif name == 'satin':      # small metal parts
        m, b = _principled(name, (0.82, 0.83, 0.85), 1.0, 0.27)
        nt = m.node_tree
        n = nt.nodes.new('ShaderNodeTexNoise')
        n.inputs['Scale'].default_value = 3.0
        nt.links.new(_coords(nt), n.inputs['Vector'])
        _bump(m, b, n.outputs['Fac'], 0.05, 0.1)
    elif name == 'spun':       # round tops: concentric turning marks
        m, b = _principled(name, (0.9, 0.91, 0.92), 1.0, 0.24)
        nt = m.node_tree
        w = nt.nodes.new('ShaderNodeTexWave')
        w.wave_type = 'RINGS'
        w.rings_direction = 'Z'
        w.inputs['Scale'].default_value = 1.6
        w.inputs['Distortion'].default_value = 0.6
        w.inputs['Detail'].default_value = 2
        nt.links.new(_coords(nt), w.inputs['Vector'])
        _bump(m, b, w.outputs['Fac'], 0.04, 0.06)
    elif name == 'polished':
        m, b = _principled(name, (0.92, 0.93, 0.94), 1.0, 0.06)
    elif name == 'blackAnod':
        m, b = _principled(name, (0.035, 0.036, 0.04), 1.0, 0.36)
    elif name == 'blackPaint':
        m, b = _principled(name, (0.012, 0.012, 0.013), 0.0, 0.32, **{'Coat Weight': 0.6, 'Coat Roughness': 0.15})
    elif name == 'glossBlack':
        m, b = _principled(name, (0.008, 0.008, 0.009), 0.0, 0.12, **{'Coat Weight': 1.0, 'Coat Roughness': 0.04})
    elif name == 'gap':
        m, b = _principled(name, (0.004, 0.004, 0.004), 0.0, 0.9)
    elif name == 'red':
        m, b = _principled(name, (0.62, 0.04, 0.025), 0.0, 0.42)
    elif name == 'redGloss':   # Super 8 RUN button
        m, b = _principled(name, (0.6, 0.035, 0.02), 0.0, 0.28, **{'Coat Weight': 0.8, 'Coat Roughness': 0.2})
    elif name == 'aluDark':
        m, b = _principled(name, (0.45, 0.47, 0.5), 1.0, 0.32)
    elif name == 'alu':        # digital face: brushed aluminium
        m, b = _principled(name, (0.74, 0.76, 0.79), 1.0, 0.26)
        nt = m.node_tree
        n = nt.nodes.new('ShaderNodeTexNoise')
        n.inputs['Scale'].default_value = 1.0
        n.inputs['Detail'].default_value = 6
        nt.links.new(_coords(nt, (0.004, 1.4, 1)), n.inputs['Vector'])
        _bump(m, b, n.outputs['Fac'], 0.1, 0.2)
    elif name == 'rubber':
        m, b = _principled(name, (0.022, 0.023, 0.025), 0.0, 0.72)
        nt = m.node_tree
        n = nt.nodes.new('ShaderNodeTexNoise')
        n.inputs['Scale'].default_value = 2.5
        nt.links.new(_coords(nt), n.inputs['Vector'])
        _bump(m, b, n.outputs['Fac'], 0.08, 0.1)
    elif name == 'leather':    # pebbled leatherette: ~5 dp pebbles, crisp valleys, fine grain
        m, b = _principled(name, (0.017, 0.014, 0.012), 0.0, 0.6)
        nt = m.node_tree
        co = _coords(nt)
        # warp the cells a little so the pebbles aren't a perfect lattice
        warp = nt.nodes.new('ShaderNodeTexNoise')
        warp.inputs['Scale'].default_value = 0.05
        wmix = nt.nodes.new('ShaderNodeMix')
        wmix.data_type = 'VECTOR'
        wmix.inputs['Factor'].default_value = 0.35
        nt.links.new(co, wmix.inputs['A'])
        nt.links.new(warp.outputs['Color'], wmix.inputs['B'])
        nt.links.new(co, warp.inputs['Vector'])
        # packed pebbles: narrow valleys along the cell edges, a gentle dome
        # toward each cell's centre
        edge = nt.nodes.new('ShaderNodeTexVoronoi')
        edge.feature = 'DISTANCE_TO_EDGE'
        edge.inputs['Scale'].default_value = 0.36
        edge.inputs['Randomness'].default_value = 0.95
        nt.links.new(wmix.outputs['Result'], edge.inputs['Vector'])
        f1 = nt.nodes.new('ShaderNodeTexVoronoi')
        f1.inputs['Scale'].default_value = 0.36
        f1.inputs['Randomness'].default_value = 0.95
        nt.links.new(wmix.outputs['Result'], f1.inputs['Vector'])
        valley = nt.nodes.new('ShaderNodeMapRange')
        valley.interpolation_type = 'SMOOTHSTEP'
        valley.inputs['From Min'].default_value = 0.0
        valley.inputs['From Max'].default_value = 0.1
        nt.links.new(edge.outputs['Distance'], valley.inputs['Value'])
        crown = nt.nodes.new('ShaderNodeMath')
        crown.operation = 'MULTIPLY_ADD'
        crown.inputs[1].default_value = -0.35
        crown.inputs[2].default_value = 1.0
        nt.links.new(f1.outputs['Distance'], crown.inputs[0])
        dome = nt.nodes.new('ShaderNodeMath')
        dome.operation = 'MULTIPLY'
        nt.links.new(valley.outputs['Result'], dome.inputs[0])
        nt.links.new(crown.outputs['Value'], dome.inputs[1])
        # fine grain on the tops
        fine = nt.nodes.new('ShaderNodeTexNoise')
        fine.inputs['Scale'].default_value = 4.5
        fine.inputs['Detail'].default_value = 4
        nt.links.new(co, fine.inputs['Vector'])
        h = nt.nodes.new('ShaderNodeMath')
        h.operation = 'MULTIPLY_ADD'
        h.inputs[1].default_value = 0.1
        nt.links.new(fine.outputs['Fac'], h.inputs[0])
        nt.links.new(dome.outputs['Value'], h.inputs[2])
        _bump(m, b, h.outputs['Value'], 0.6, 0.35)
        # tops a touch glossier (handled), valleys matte and a shade darker
        rr = nt.nodes.new('ShaderNodeMapRange')
        rr.inputs['To Min'].default_value = 0.72
        rr.inputs['To Max'].default_value = 0.5
        nt.links.new(dome.outputs['Value'], rr.inputs['Value'])
        nt.links.new(rr.outputs['Result'], b.inputs['Roughness'])
        col = nt.nodes.new('ShaderNodeMix')
        col.data_type = 'RGBA'
        col.inputs['A'].default_value = (0.008, 0.007, 0.006, 1)
        col.inputs['B'].default_value = (0.02, 0.017, 0.014, 1)
        nt.links.new(dome.outputs['Value'], col.inputs['Factor'])
        nt.links.new(col.outputs['Result'], b.inputs['Base Color'])
    elif name == 'glass':      # coated lens element
        m, b = _principled(name, (0.01, 0.012, 0.015), 0.0, 0.02,
                           **{'Coat Weight': 1.0, 'Coat Roughness': 0.0, 'IOR': 1.6})
        if 'Thin Film Thickness' in b.inputs:
            b.inputs['Thin Film Thickness'].default_value = 320
            b.inputs['Thin Film IOR'].default_value = 1.38
    elif name == 'paper':
        m, b = _principled(name, (0.95, 0.93, 0.88), 0.0, 0.32, **{'Coat Weight': 0.6, 'Coat Roughness': 0.12})
    elif name == 'well':
        m, b = _principled(name, (0.012, 0.012, 0.013), 0.0, 0.7)
    elif name == 'ink':
        m, b = _principled(name, (0.008, 0.008, 0.009), 0.0, 0.55)
    elif name == 'whiteInk':
        m, b = _principled(name, (0.8, 0.8, 0.78), 0.0, 0.5)
    else:
        raise KeyError(name)
    _mats[name] = m
    return m


def clear_mats():
    _mats.clear()


# ------------------------------------------------------------------ shapes
def _link(obj, material, parent=None):
    bpy.context.collection.objects.link(obj)
    if material is not None:
        obj.data.materials.append(mat(material) if isinstance(material, str) else material)
    if parent is not None:
        obj.parent = parent
    return obj


def group(name='g', parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(e)
    if parent is not None:
        e.parent = parent
    return e


def rrect_pts(w, h, r, seg=12):
    r = max(0.01, min(r, w / 2 - 1e-3, h / 2 - 1e-3))
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def slab(outlines, depth, bevel, material, z=0.0, parent=None, name='slab'):
    """A flat piece cut from 2D [outlines] (first = outside, others = holes),
    [depth] thick from z, every edge rounded by [bevel]."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '2D'
    cu.fill_mode = 'BOTH'
    cu.extrude = max(0.001, depth / 2 - bevel)
    cu.bevel_depth = bevel
    cu.bevel_resolution = 4
    for k, pts in enumerate(outlines):
        sp = cu.splines.new('POLY')
        sp.points.add(len(pts) - 1)
        for i, (x, y) in enumerate(pts):
            sp.points[i].co = (x, y, 0, 1)
        sp.use_cyclic_u = True
    obj = bpy.data.objects.new(name, cu)
    obj.location.z = z + depth / 2
    _link(obj, material, parent)
    return obj


def rbox(w, h, depth, r, bevel, material, z=0.0, parent=None, name='rbox'):
    """Rounded rectangle block (r = corner radius in plan)."""
    # the bevel grows the outline: shrink it to keep the footprint w x h
    return slab([rrect_pts(w - 2 * bevel, h - 2 * bevel, max(0.01, r - bevel))], depth, bevel, material, z, parent, name)


def ring(ow, oh, orr, iw, ih, ir, depth, bevel, material, z=0.0, parent=None, name='ring'):
    pts_o = rrect_pts(ow - 2 * bevel, oh - 2 * bevel, max(0.01, orr - bevel))
    pts_i = rrect_pts(iw + 2 * bevel, ih + 2 * bevel, ir + bevel)[::-1]
    return slab([pts_o, pts_i], depth, bevel, material, z, parent, name)


def cylinder(r, h, material, z=0.0, verts=128, bevel=0.0, parent=None, r_top=None, name='cyl'):
    """Lathed cylinder from z to z + h, optionally tapered (r_top) and with
    rounded top / bottom edges."""
    rt = r if r_top is None else r_top
    b = min(bevel, h / 2.01, r / 2, rt / 2)
    prof = [(0, z)]
    if b > 0:
        for i in range(5):
            a = math.radians(-90 + 90 * i / 4)
            prof.append((r - b + b * math.cos(a), z + b + b * math.sin(a)))
        for i in range(5):
            a = math.radians(0 + 90 * i / 4)
            prof.append((rt - b + b * math.cos(a), z + h - b + b * math.sin(a)))
    else:
        prof += [(r, z), (rt, z + h)]
    prof.append((0, z + h))
    return lathe(prof, material, verts, parent, name)


def lathe(profile, material, verts=128, parent=None, name='lathe'):
    """Spins an (r, z) profile round the Z axis."""
    bm = bmesh.new()
    vs = [bm.verts.new((r, 0, z)) for r, z in profile]
    edges = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    bmesh.ops.spin(bm, geom=vs + edges, cent=(0, 0, 0), axis=(0, 0, 1), angle=math.tau, steps=verts, use_duplicate=False)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    _link(obj, material, parent)
    return obj


def knurl(r, h, n, material, depth=0.8, z=0.0, parent=None):
    """Straight knurled band: [n] ridges round a cylinder."""
    bm = bmesh.new()
    core = r - depth * 0.35
    bmesh.ops.create_cone(bm, cap_ends=True, segments=96, radius1=core, radius2=core, depth=h)
    tooth = 2 * math.pi * r / n * 0.55
    for i in range(n):
        a = i / n * math.tau
        res = bmesh.ops.create_cube(bm, size=1)
        vs = res['verts']
        bmesh.ops.scale(bm, vec=(depth * 1.2, tooth, h), verts=vs)
        bmesh.ops.translate(bm, vec=(r - depth * 0.5, 0, 0), verts=vs)
        bmesh.ops.rotate(bm, verts=vs, cent=(0, 0, 0), matrix=_rotz(a))
    bmesh.ops.translate(bm, vec=(0, 0, z + h / 2), verts=bm.verts)
    me = bpy.data.meshes.new('knurl')
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new('knurl', me)
    _link(obj, material, parent)
    bev = obj.modifiers.new('bevel', 'BEVEL')
    bev.width = 0.12
    bev.segments = 2
    return obj


def _rotz(a):
    from mathutils import Matrix
    return Matrix.Rotation(a, 3, 'Z')


def box(w, h, d, material, loc=(0, 0, 0), rot_z=0.0, bevel=0.0, parent=None, name='box'):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    bmesh.ops.scale(bm, vec=(w, h, d), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = loc
    obj.rotation_euler.z = rot_z
    _link(obj, material, parent)
    if bevel > 0:
        b = obj.modifiers.new('bevel', 'BEVEL')
        b.width = bevel
        b.segments = 3
    return obj


def text(s, size, material='ink', z=0.0, depth=0.06, align='CENTER', font='InterDisplay-Bold.ttf',
         spacing=1.0, parent=None, loc=(0, 0)):
    cu = bpy.data.curves.new('txt', 'FONT')
    cu.body = s
    cu.size = size
    cu.extrude = depth / 2
    cu.align_x = align
    cu.align_y = 'CENTER'
    cu.space_character = spacing
    for d in (FONTS, '/usr/share/fonts/truetype/dejavu'):
        if os.path.exists(f'{d}/{font}'):
            cu.font = bpy.data.fonts.load(f'{d}/{font}', check_existing=True)
            break
    obj = bpy.data.objects.new('txt', cu)
    obj.location = (loc[0], loc[1], z + depth / 2)
    _link(obj, material, parent)
    return obj


def capsule_pts(x0, y0, x1, y1, r, seg=10):
    a = math.atan2(y1 - y0, x1 - x0)
    pts = []
    for i in range(seg + 1):
        t = a - math.pi / 2 + math.pi * i / seg
        pts.append((x1 + r * math.cos(t), y1 + r * math.sin(t)))
    for i in range(seg + 1):
        t = a + math.pi / 2 + math.pi * i / seg
        pts.append((x0 + r * math.cos(t), y0 + r * math.sin(t)))
    return pts


def ellipse_pts(cx, cy, rx, ry, seg=48):
    return [(cx + rx * math.cos(i / seg * math.tau), cy + ry * math.sin(i / seg * math.tau)) for i in range(seg)]


def rabbit(h, material='ink', eye_material='satin', z=0.0, depth=0.08, parent=None, loc=(0, 0)):
    """The Darkroom rabbit (tool/render/lib/logo.js geometry), [h] tall,
    centred, X eyes in [eye_material]."""
    s, cx, cy = h / 129, 104.5, 93.5
    P = lambda x, y: (loc[0] + (x - cx) * s, loc[1] - (y - cy) * s)
    g = group('rabbit', parent)
    # One mark, not overlapping pieces: the parts are merged into a single
    # mesh with a boolean union, so the ink is one uniform surface.
    pieces = [slab([o], depth, 0, material, z, None, 'rabbit') for o in (
        capsule_pts(*P(80, 104), *P(70, 40), 11 * s), capsule_pts(*P(110, 100), *P(120, 48), 11 * s),
        capsule_pts(*P(120, 48), *P(146, 60), 11 * s), ellipse_pts(*P(94, 122), 42 * s, 36 * s))]
    union(pieces, material, g, 'rabbit')
    for ex, ey in ((80, 118), (108, 118)):
        eye = [slab([capsule_pts(*P(ex - 7, ey - 7 * d), *P(ex + 7, ey + 7 * d), 2.75 * s)], depth, 0, eye_material,
                    z + depth * 0.5, None, 'eye') for d in (1, -1)]
        union(eye, eye_material, g, 'eye')
    return g


def union(objs, material, parent=None, name='union'):
    """Merges [objs] (curves or meshes) into one mesh: a boolean union of
    all of them, so overlapping parts leave no doubled surfaces."""
    dg = bpy.context.evaluated_depsgraph_get()
    meshes = []
    for o in objs:
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        m = bpy.data.objects.new(name, me)
        m.matrix_world = o.matrix_world.copy()
        bpy.context.collection.objects.link(m)
        meshes.append(m)
        bpy.data.objects.remove(o)
    base = meshes[0]
    for other in meshes[1:]:
        mod = base.modifiers.new('u', 'BOOLEAN')
        mod.operation = 'UNION'
        mod.solver = 'EXACT'
        mod.object = other
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(base.evaluated_get(dg))
        base.modifiers.clear()
        old = base.data
        base.data = me
        bpy.data.meshes.remove(old)
        bpy.data.objects.remove(other)
    base.data.materials.clear()
    base.data.materials.append(mat(material) if isinstance(material, str) else material)
    if parent is not None:
        base.parent = parent
    return base


def screw(r, z=0.0, angle=0.0, parent=None, loc=(0, 0)):
    g = group('screw', parent)
    g.location = (loc[0], loc[1], z)
    head = lathe([(0, 0), (r, 0)] + [(r * math.cos(t * math.pi / 2 / 8), r * 0.35 * math.sin(t * math.pi / 2 / 8)) for t in range(1, 9)], 'polished', 48, g, 'screw')
    box(r * 2.05, r * 0.32, r * 0.5, 'gap', (0, 0, r * 0.3), angle, 0, g, 'slot')
    return g
