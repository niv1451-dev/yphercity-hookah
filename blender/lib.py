"""Geometry, material and scene helpers for building the One Bike model with bpy.

Axes follow GTA vehicles: +Y forward, +Z up, +X right. Units are metres.
Every object gets an "bone" custom property naming the GTA bone it will be
parented to at export time.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

V = Vector
FONT_SCRIPT = '/usr/share/fonts/truetype/freefont/FreeSerifBoldItalic.ttf'
FONT_SANS = '/usr/share/fonts/truetype/freefont/FreeSansBold.ttf'
# Windows has no GNU FreeFont: the logo script is closest to Edwardian Script (the 'B' loop), FreeSans is an
# Arial clone.
WIN_FONTS = {'FreeSerifBoldItalic.ttf': 'ITCEDSCR.TTF', 'FreeSansBold.ttf': 'arialbd.ttf'}

COLLECTION = None
MATS = {}
DETAIL = 1.0  # geometry resolution factor; lower values build game LODs


def n(value, lo=3):
    return max(lo, int(round(value * DETAIL)))


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    new_collection('OneBike')


def new_collection(name):
    global COLLECTION
    COLLECTION = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(COLLECTION)
    return COLLECTION


# ---------------------------------------------------------------- materials

def srgb(hex_color):
    h = hex_color.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


def material(name, color, rough=0.5, metal=0.0, coat=0.0, emit=0.0, bump=0.0, bump_scale=300.0, spec=0.5):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except AttributeError:
        pass
    nt = m.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = srgb(color)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Specular IOR Level'].default_value = spec
    if coat:
        bsdf.inputs['Coat Weight'].default_value = coat
        bsdf.inputs['Coat Roughness'].default_value = 0.04
    if emit:
        bsdf.inputs['Emission Color'].default_value = srgb(color)
        bsdf.inputs['Emission Strength'].default_value = emit
    if bump:
        tex = nt.nodes.new('ShaderNodeTexNoise')
        tex.inputs['Scale'].default_value = bump_scale
        tex.inputs['Detail'].default_value = 6.0
        bmp = nt.nodes.new('ShaderNodeBump')
        bmp.inputs['Strength'].default_value = bump
        bmp.inputs['Distance'].default_value = 0.0005
        nt.links.new(tex.outputs['Fac'], bmp.inputs['Height'])
        nt.links.new(bmp.outputs['Normal'], bsdf.inputs['Normal'])
    m.diffuse_color = srgb(color)
    MATS[name] = m
    return m


def make_materials():
    material('paint_black', '#0a0a0a', rough=0.18, coat=1.0)
    material('paint_yellow', '#f2c200', rough=0.22, coat=1.0)
    material('decal_yellow', '#f5c800', rough=0.35, coat=0.6)
    material('decal_black', '#0c0c0c', rough=0.35, coat=0.6)
    material('decal_white', '#e8e8e8', rough=0.35)
    material('decal_red', '#c41818', rough=0.35, coat=0.6)
    material('plastic_black', '#111111', rough=0.55)
    material('plastic_gloss', '#0a0a0a', rough=0.12, coat=0.6)
    material('rubber', '#141414', rough=0.88, bump=0.25, bump_scale=900.0, spec=0.3)
    material('tyre', '#0b0b0b', rough=0.86, bump=0.15, bump_scale=600.0, spec=0.25)
    material('alloy_black', '#151515', rough=0.32, metal=0.6)
    material('steel', '#9a9a9a', rough=0.28, metal=1.0)
    material('steel_dark', '#4a4a4a', rough=0.35, metal=1.0)
    material('chain', '#8c8c8c', rough=0.38, metal=1.0)
    material('rotor', '#b8b8b8', rough=0.22, metal=1.0)
    material('leather', '#0e0e0e', rough=0.48, bump=0.12, bump_scale=1500.0)
    nylon_fabric('fabric', '#141516')
    mesh_net('mesh_fabric', '#121314')
    material('piping', '#0c0c0c', rough=0.45, spec=0.4)
    material('zipper', '#1a1a1a', rough=0.38, spec=0.5, bump=0.4, bump_scale=2500.0)
    material('webbing', '#101010', rough=0.8, bump=0.3, bump_scale=900.0, spec=0.25)
    material('lens_white', '#fff4d6', rough=0.05, emit=6.0)
    material('lens_red', '#d01010', rough=0.1, emit=3.0)
    material('reflector_white', '#f0f0f0', rough=0.15)
    material('reflector_amber', '#f0a018', rough=0.15)
    material('screen', '#1b2b33', rough=0.08, emit=0.6)
    material('screen_text', '#bfe8ff', rough=0.2, emit=4.0)
    material('led_green', '#30e060', rough=0.2, emit=5.0)
    material('button_rubber', '#2a2a2a', rough=0.7)
    glass = material('glass', '#ffffff', rough=0.02)
    bsdf = glass.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Transmission Weight'].default_value = 1.0
    bsdf.inputs['IOR'].default_value = 1.5
    import os
    import textures
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'display.png')
    from PIL import Image
    sq = textures.display_image()                  # round gauge, centred on a wide black colour screen
    wide = Image.new('RGBA', (int(sq.height * 1.83), sq.height), (0, 0, 0, 255))
    wide.paste(sq, ((wide.width - sq.width) // 2, 0))
    wide.save(path)
    image_material('screen_display', path, 1.8)


def nylon_fabric(name, color):
    """Ripstop nylon: woven grid bump, soft sheen, slight colour variation."""
    m = material(name, color, rough=0.78, spec=0.35)
    nt = m.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    bsdf.inputs['Sheen Weight'].default_value = 0.15
    bsdf.inputs['Sheen Roughness'].default_value = 0.4
    coord = nt.nodes.new('ShaderNodeTexCoord')
    waves = []
    for axis in ('X', 'Z'):
        wv = nt.nodes.new('ShaderNodeTexWave')
        wv.bands_direction = axis
        wv.inputs['Scale'].default_value = 140.0
        wv.inputs['Distortion'].default_value = 0.6
        nt.links.new(coord.outputs['Object'], wv.inputs['Vector'])
        waves.append(wv)
    grid = nt.nodes.new('ShaderNodeMath')
    grid.operation = 'MAXIMUM'
    nt.links.new(waves[0].outputs['Fac'], grid.inputs[0])
    nt.links.new(waves[1].outputs['Fac'], grid.inputs[1])
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.18
    bump.inputs['Distance'].default_value = 0.0004
    nt.links.new(grid.outputs[0], bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    var = nt.nodes.new('ShaderNodeTexNoise')
    var.inputs['Scale'].default_value = 6.0
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = srgb('#0b0c0d')
    ramp.color_ramp.elements[1].color = srgb('#151618')
    nt.links.new(var.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    return m


def mesh_net(name, color):
    """Stretch mesh: a square net of small holes (alpha from two crossed sine waves)."""
    m = material(name, color, rough=0.85, spec=0.25)
    nt = m.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    coord = nt.nodes.new('ShaderNodeTexCoord')
    waves = []
    for axis in ('X', 'Y'):
        wv = nt.nodes.new('ShaderNodeTexWave')
        wv.bands_direction = axis
        wv.inputs['Scale'].default_value = 120.0
        wv.inputs['Distortion'].default_value = 0.0
        nt.links.new(coord.outputs['UV'], wv.inputs['Vector'])  # pocket UVs are in metres across the panel
        waves.append(wv)
    both = nt.nodes.new('ShaderNodeMath')
    both.operation = 'MULTIPLY'
    nt.links.new(waves[0].outputs['Fac'], both.inputs[0])
    nt.links.new(waves[1].outputs['Fac'], both.inputs[1])
    hole = nt.nodes.new('ShaderNodeMath')
    hole.operation = 'GREATER_THAN'
    hole.inputs[1].default_value = 0.42
    nt.links.new(both.outputs[0], hole.inputs[0])
    alpha = nt.nodes.new('ShaderNodeMath')
    alpha.operation = 'SUBTRACT'
    alpha.inputs[0].default_value = 1.0
    nt.links.new(hole.outputs[0], alpha.inputs[1])
    nt.links.new(alpha.outputs[0], bsdf.inputs['Alpha'])
    return m


def image_material(name, path, emit):
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(path, check_existing=True)
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Emission Color'])
    bsdf.inputs['Emission Strength'].default_value = emit
    bsdf.inputs['Roughness'].default_value = 0.3
    bsdf.inputs['Coat Weight'].default_value = 0.6  # glossy cover glass
    bsdf.inputs['Coat Roughness'].default_value = 0.03
    m.diffuse_color = (0.05, 0.05, 0.05, 1.0)
    MATS[name] = m
    return m


# ------------------------------------------------------------------ objects

def link(ob, bone, mat):
    COLLECTION.objects.link(ob)
    ob['bone'] = bone
    if mat is not None:
        ob.data.materials.append(MATS[mat] if isinstance(mat, str) else mat)
    return ob


def bm_to_obj(name, bm, mat, bone, smooth=True, weighted=False):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        me.shade_smooth()
    ob = bpy.data.objects.new(name, me)
    link(ob, bone, mat)
    if weighted:
        mod = ob.modifiers.new('WeightedNormal', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
    return ob


def add_bevel(ob, width, segments=3, angle=35.0):
    if DETAIL < 0.3:
        return None
    mod = ob.modifiers.new('Bevel', 'BEVEL')
    mod.width = width
    mod.segments = max(1, int(round(segments * DETAIL)))
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(angle)
    mod.harden_normals = True
    return mod


def add_subsurf(ob, levels=2):
    if DETAIL < 0.75:
        levels -= 1 if DETAIL >= 0.3 else levels
    if levels <= 0:
        return None
    mod = ob.modifiers.new('Subsurf', 'SUBSURF')
    mod.levels = levels
    mod.render_levels = levels
    return mod


def basis(x_axis, y_axis, z_axis, loc=(0, 0, 0)):
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][0], m[i][1], m[i][2] = x_axis[i], y_axis[i], z_axis[i]
    m.translation = V(loc)
    return m


def frame_from_z(z_axis, loc=(0, 0, 0), x_hint=(1, 0, 0)):
    """Matrix whose local Z points along z_axis."""
    z = V(z_axis).normalized()
    xh = V(x_hint)
    if abs(z.dot(xh.normalized())) > 0.95:
        xh = V((0, 1, 0)) if abs(z.y) < 0.9 else V((0, 0, 1))
    y = z.cross(xh).normalized()
    x = y.cross(z).normalized()
    return basis(x, y, z, loc)


def box(name, size, mat, bone, matrix=None, loc=None, bevel=0.0, segments=3):
    bm = bmesh.new()
    s = Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    m = matrix.copy() if matrix is not None else Matrix.Identity(4)
    if loc is not None:
        m.translation = V(loc)
    bmesh.ops.create_cube(bm, size=1.0, matrix=m @ s)
    ob = bm_to_obj(name, bm, mat, bone)
    if bevel:
        add_bevel(ob, bevel, segments)
    return ob


def cylinder(name, radius, length, mat, bone, start=None, end=None, matrix=None, verts=32,
             bevel=0.0, radius2=None):
    """Cylinder from start to end (or centred on matrix with local Z axis)."""
    if verts > 8:
        verts = n(verts, 8)
    bm = bmesh.new()
    if start is not None:
        a, b = V(start), V(end)
        length = (b - a).length
        m = frame_from_z(b - a, (a + b) / 2)
    else:
        m = matrix
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=length, matrix=m)
    ob = bm_to_obj(name, bm, mat, bone)
    if bevel:
        add_bevel(ob, bevel, 2, 40.0)
    return ob


def ring_prism(name, outer, inner, x0, x1, mat, bone, center=(0, 0, 0), smooth=False):
    """Prism along X between two closed YZ outlines with the same vertex count."""
    bm = bmesh.new()
    cy, cz = center[1], center[2]
    n = len(outer)
    o0 = [bm.verts.new((x0, cy + p[0], cz + p[1])) for p in outer]
    o1 = [bm.verts.new((x1, cy + p[0], cz + p[1])) for p in outer]
    i0 = [bm.verts.new((x0, cy + p[0], cz + p[1])) for p in inner]
    i1 = [bm.verts.new((x1, cy + p[0], cz + p[1])) for p in inner]
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new((o0[k], o0[j], i0[j], i0[k]))
        bm.faces.new((o1[k], i1[k], i1[j], o1[j]))
        bm.faces.new((o0[k], o1[k], o1[j], o0[j]))
        bm.faces.new((i0[k], i0[j], i1[j], i1[k]))
    return bm_to_obj(name, bm, mat, bone, smooth=smooth)


def disc_uv(name, center, u_axis, v_axis, radius, mat, bone, segments=64):
    """Flat round face with a UV map that fills the image (for screens)."""
    segments = n(segments, 16)
    c, u, v = V(center), V(u_axis), V(v_axis)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    mid = bm.verts.new(c)
    ring = []
    for k in range(segments):
        a = 2 * math.pi * k / segments
        ring.append((bm.verts.new(c + (u * math.cos(a) + v * math.sin(a)) * radius), math.cos(a), math.sin(a)))
    for k in range(segments):
        (v0, x0, y0), (v1, x1, y1) = ring[k], ring[(k + 1) % segments]
        f = bm.faces.new((mid, v0, v1))
        for loop, (x, y) in zip(f.loops, ((0, 0), (x0, y0), (x1, y1))):
            loop[uv].uv = (0.5 + x / 2, 0.5 + y / 2)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    return link(ob, bone, mat)


def rect_uv(name, center, u_axis, v_axis, w, h, mat, bone):
    """Flat rectangle with a UV map that fills the image (for screens)."""
    c, u, v = V(center), V(u_axis), V(v_axis)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    vs = [bm.verts.new(c + u * (a * w / 2) + v * (b * h / 2)) for a, b in corners]
    f = bm.faces.new(vs)
    for loop, (a, b) in zip(f.loops, corners):
        loop[uv].uv = ((a + 1) / 2, (b + 1) / 2)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    return link(ob, bone, mat)


def circle_pts(r, n, phase=0.0):
    return [(r * math.cos(phase + 2 * math.pi * k / n), r * math.sin(phase + 2 * math.pi * k / n)) for k in range(n)]


def gear_pts(teeth, r_pitch, depth):
    pts = []
    for k in range(teeth * 4):
        a = 2 * math.pi * k / (teeth * 4)
        phase = k % 4
        r = r_pitch + (depth * 0.55 if phase in (1, 2) else -depth * 0.45)
        pts.append((r * math.cos(a), r * math.sin(a)))
    return pts


def lathe(name, profile, steps, mat, bone, center, closed=False, axis=(1, 0, 0)):
    """Spin a (x, r) profile around the X axis through center."""
    steps = n(steps, 12)
    bm = bmesh.new()
    verts = [bm.verts.new((p[0], p[1], 0.0)) for p in profile]
    edges = [bm.edges.new((verts[k], verts[k + 1])) for k in range(len(verts) - 1)]
    if closed:
        edges.append(bm.edges.new((verts[-1], verts[0])))
    bmesh.ops.spin(bm, geom=verts + edges, cent=(0, 0, 0), axis=axis, angle=2 * math.pi,
                   steps=steps, use_merge=True)
    bmesh.ops.translate(bm, verts=bm.verts, vec=V(center))
    return bm_to_obj(name, bm, mat, bone)


# ------------------------------------------------------------------- paths

def fillet(points, radius, arc_steps=8):
    """Polyline with rounded corners (quadratic arcs)."""
    arc_steps = n(arc_steps, 2)
    pts = [V(p) for p in points]
    if len(pts) < 3 or radius <= 0:
        return pts
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        u, w = (a - b), (c - b)
        lu, lw = u.length, w.length
        u.normalize()
        w.normalize()
        ang = u.angle(w)
        if ang > math.pi - 1e-3:
            out.append(b)
            continue
        d = min(radius / math.tan(ang / 2), lu * 0.48, lw * 0.48)
        p1, p2 = b + u * d, b + w * d
        for s in range(arc_steps + 1):
            t = s / arc_steps
            out.append((1 - t) ** 2 * p1 + 2 * (1 - t) * t * b + t * t * p2)
    out.append(pts[-1])
    return out


def resample(points, step):
    step = step / max(DETAIL, 0.05)
    pts = [V(p) for p in points]
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        n = max(1, int((b - a).length / step))
        for k in range(1, n + 1):
            out.append(a.lerp(b, k / n))
    return out


def rrect_profile(w, h, r, corner_steps=5):
    corner_steps = n(corner_steps, 2)
    r = min(r, w / 2 - 1e-4, h / 2 - 1e-4)
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
                       (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(corner_steps + 1):
            a = math.radians(a0 + 90 * k / corner_steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def sweep(name, path, profile_fn, mat, bone, ref=(1, 0, 0), caps=True, weighted=True):
    """Sweep a closed 2D profile along a path.

    profile_fn(u) returns a list of (a, b) points, a along the side axis
    (close to `ref`) and b along the in-plane normal. All lists must have the
    same length.
    """
    path = [V(p) for p in path]
    n = len(path)
    lengths = [0.0]
    for a, b in zip(path, path[1:]):
        lengths.append(lengths[-1] + (b - a).length)
    total = lengths[-1]
    bm = bmesh.new()
    rings = []
    refv = V(ref).normalized()
    for i, p in enumerate(path):
        t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
        nrm = t.cross(refv)
        if nrm.length < 1e-5:
            nrm = t.cross(V((0, 0, 1)))
        nrm.normalize()
        side = nrm.cross(t).normalized()
        prof = profile_fn(lengths[i] / total if total else 0.0)
        rings.append([bm.verts.new(p + side * a + nrm * b) for a, b in prof])
    m = len(rings[0])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(m):
            j = (k + 1) % m
            bm.faces.new((r0[k], r0[j], r1[j], r1[k]))
    if caps:
        bm.faces.new(rings[0])
        bm.faces.new(list(reversed(rings[-1])))
    return bm_to_obj(name, bm, mat, bone, weighted=weighted)


def plate(name, outline, x0, x1, mat, bone, holes=(), bevel=0.0, segments=3, smooth=True):
    """Flat part drawn in side view: closed (y, z) outline (with optional holes) extruded from x0 to x1."""
    bm = bmesh.new()
    loops = [outline] + list(holes)
    edges = []
    for loop in loops:
        vs = [bm.verts.new((x0, p[0], p[1])) for p in loop]
        edges += [bm.edges.new((vs[k], vs[(k + 1) % len(vs)])) for k in range(len(vs))]
    faces = bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=True, edges=edges)['geom']
    faces = [f for f in faces if isinstance(f, bmesh.types.BMFace)]
    ext = bmesh.ops.extrude_face_region(bm, geom=faces)
    moved = [g for g in ext['geom'] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=moved, vec=(x1 - x0, 0.0, 0.0))
    ob = bm_to_obj(name, bm, mat, bone, smooth=smooth, weighted=True)
    if bevel:
        add_bevel(ob, bevel, segments, 30.0)
    return ob


def spline(points, steps=8):
    """Catmull-Rom curve through 2D or 3D points."""
    pts = [V(p) if len(p) == 3 else V((p[0], p[1], 0.0)) for p in points]
    flat = all(len(p) == 2 for p in points)
    out = []
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        for k in range(steps):
            t = k / steps
            t2, t3 = t * t, t * t * t
            q = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            out.append(q)
    out.append(pts[-1])
    return [(q.x, q.y) for q in out] if flat else out


def pipe(name, points, radius, mat, bone, fillet_r=0.0, verts=16, step=None, caps=True):
    path = fillet(points, fillet_r) if fillet_r else [V(p) for p in points]
    if step:
        path = resample(path, step)
    prof = circle_pts(radius, n(verts, 6))
    return sweep(name, path, lambda u: prof, mat, bone, caps=caps, weighted=False)


def path_frame(a, b, ref=(1, 0, 0)):
    """Tangent, in-plane normal and side vector of a straight segment."""
    t = (V(b) - V(a)).normalized()
    nrm = t.cross(V(ref)).normalized()
    side = nrm.cross(t).normalized()
    return t, nrm, side


# ------------------------------------------------------------------ decals

_fonts = {}


def font(path):
    if path not in _fonts:
        real, base = path, os.path.basename(path)
        if not os.path.exists(real) and base in WIN_FONTS:
            real = os.path.join(os.environ.get('WINDIR', r'C:\Windows'), 'Fonts', WIN_FONTS[base])
        _fonts[path] = bpy.data.fonts.load(real)
    return _fonts[path]


def text(name, body, size, mat, bone, matrix, font_path=FONT_SCRIPT, extrude=0.0003, bold=0.0):
    if DETAIL < 0.3:
        return None
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body = body
    cu.font = font(font_path)
    cu.size = size
    if bold:
        cu.offset = bold * size              # thicken thin calligraphic strokes
    cu.extrude = extrude if DETAIL >= 1.0 else 0.0
    cu.resolution_u = n(6, 2)
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    ob = bpy.data.objects.new(name, cu)
    ob.matrix_world = matrix
    return link(ob, bone, mat)


def side_matrix(center, read_dir_yz, side_sign, offset_x):
    """Matrix for a decal lying on a face whose normal is +/-X."""
    d = V((0.0, read_dir_yz[0], read_dir_yz[1])).normalized()
    nz = V((side_sign, 0.0, 0.0))
    y = nz.cross(d).normalized()
    loc = V((offset_x * side_sign, center[0], center[1]))
    return basis(d, y, nz, loc)


def stripes(name, a, b, half_w, height, count, stripe_w, slant_deg, mat, bone, sides=(1, -1),
            start=0.0, end=1.0, eps=0.0006, ref=(1, 0, 0), shift=0.0):
    """Diagonal stripe decals on both flat side faces of a tube segment a->b."""
    a, b = V(a), V(b)
    t, nrm, side = path_frame(a, b, ref)
    seg = (b - a).length
    bm = bmesh.new()
    slant = math.tan(math.radians(slant_deg)) * height / 2
    for sgn in sides:
        x = side * (half_w + eps) * sgn
        for k in range(count):
            u = start + (end - start) * (k + 0.5) / count
            c = a + t * (seg * u) + nrm * shift
            hw = stripe_w / 2
            quad = [c + t * (-hw - slant) - nrm * height / 2, c + t * (hw - slant) - nrm * height / 2,
                    c + t * (hw + slant) + nrm * height / 2, c + t * (-hw + slant) + nrm * height / 2]
            vs = [bm.verts.new(p + x) for p in quad]
            f = bm.faces.new(vs if sgn > 0 else list(reversed(vs)))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    return link(ob, bone, mat)


def logo(name, center, read_dir, side_sign, offset_x, size, mat, bone):
    """The One Bike badge as on the bike: a round emblem with a leaf swoosh standing in for the 'O',
    followed by 'ne Bike' in a calligraphic script, on a +/-X facing surface."""
    m = side_matrix(center, read_dir, side_sign, offset_x)
    ob = text(name, 'ne Bike', size * 1.6, mat, bone, m, bold=0.03)    # the script has a small x-height
    if ob is None:
        return
    bpy.context.view_layer.update()
    w = ob.dimensions.x
    d = V(m.col[0][:3])
    ring_r = 0.42 * size
    total = w + 2 * ring_r + 0.05 * size
    ob.matrix_world = Matrix.Translation(d * (total / 2 - w / 2)) @ m
    emblem_m = Matrix.Translation(d * -(total / 2 - ring_r) + V(m.col[1][:3]) * (0.06 * size)) @ m
    bm = bmesh.new()
    k = n(32, 12)
    outer = [bm.verts.new(emblem_m @ V((ring_r * math.cos(2 * math.pi * i / k), ring_r * math.sin(2 * math.pi * i / k),
                                         0))) for i in range(k)]
    inner = [bm.verts.new(emblem_m @ V((0.78 * ring_r * math.cos(2 * math.pi * i / k),
                                         0.78 * ring_r * math.sin(2 * math.pi * i / k), 0))) for i in range(k)]
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((outer[i], outer[j], inner[j], inner[i]))
    # leaf swoosh off the lower left of the ring
    leaf = []
    for i in range(9):
        t = i / 8
        leaf.append((-ring_r * (0.6 + 1.1 * t), -ring_r * (0.55 + 0.25 * math.sin(math.pi * t)) + 0.2 * ring_r * t))
    for i in range(8, -1, -1):
        t = i / 8
        leaf.append((-ring_r * (0.6 + 1.1 * t), -ring_r * (0.55 - 0.18 * math.sin(math.pi * t)) + 0.2 * ring_r * t))
    lv = [bm.verts.new(emblem_m @ V((x, y, 0))) for x, y in leaf[:-1]]
    try:
        bmesh.ops.triangle_fill(bm, edges=[bm.edges.new((lv[i], lv[(i + 1) % len(lv)])) for i in range(len(lv))],
                                use_beauty=True)
    except Exception:
        pass
    me = bpy.data.meshes.new(name + '_ring')
    bm.to_mesh(me)
    bm.free()
    link(bpy.data.objects.new(name + '_ring', me), bone, mat)
    text(name + '_mark', 'S', size * 0.62, mat, bone, emblem_m, bold=0.03)


# ------------------------------------------------------------------- scene

def look_at(ob, target):
    d = V(target) - ob.location
    ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()


def area_light(name, loc, target, power, size, size_y=None, color=(1, 1, 1)):
    ld = bpy.data.lights.new(name, 'AREA')
    ld.energy = power
    ld.shape = 'RECTANGLE'
    ld.size = size
    ld.size_y = size_y or size
    ld.color = color
    ob = bpy.data.objects.new(name, ld)
    ob.location = loc
    bpy.context.scene.collection.objects.link(ob)
    look_at(ob, target)
    return ob
