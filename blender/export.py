"""Turn the procedural One Bike into a GTA V vehicle fragment and export CodeWalker XML.

Usage: python export.py <out_dir>

Output: onebike.yft.xml, onebike_hi.yft.xml, onebike.ytd.xml and the DDS
textures, ready for CodeWalker's "Import XML". The skeleton follows the
vanilla Inductor e-bike (same bone names, so the same bone tags).
"""
import importlib
import math
import os
import sys
from collections import defaultdict

import bpy  # noqa: I001  (bpy must be imported before bmesh)
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build  # noqa: E402
import lib  # noqa: E402
import sz  # noqa: E402
import textures  # noqa: E402

ORIGIN_Z = 0.60
LODS = [('VERYHIGH', 0.9), ('HIGH', 0.55), ('MEDIUM', 0.33), ('LOW', 0.2), ('VERYLOW', 0.12)]
WHEEL_BONES = ('wheel_lf', 'wheel_lr')
STEER = Matrix.Rotation(math.radians(20), 4, 'X')

# lib material -> (shader, diffuse texture, light id)
SHADERS = {
    'paint_black': ('vehicle_paint1', 'onebike_white', None),
    'decal_black': ('vehicle_paint1', 'onebike_white', None),
    'paint_yellow': ('vehicle_paint2', 'onebike_white', None),
    'decal_yellow': ('vehicle_paint2', 'onebike_white', None),
    'decal_white': ('vehicle_mesh', 'onebike_refl', None),
    'decal_red': ('vehicle_mesh', 'onebike_red', None),
    'plastic_black': ('vehicle_mesh', 'onebike_plastic', None),
    'plastic_gloss': ('vehicle_mesh', 'onebike_gloss', None),
    'rubber': ('vehicle_mesh', 'onebike_rubber', None),
    'tyre': ('vehicle_tire', 'onebike_tyre', None),
    'alloy_black': ('vehicle_mesh', 'onebike_alloy', None),
    'steel': ('vehicle_mesh', 'onebike_steel', None),
    'steel_dark': ('vehicle_mesh', 'onebike_steeldark', None),
    'chain': ('vehicle_mesh', 'onebike_chain', None),
    'rotor': ('vehicle_mesh', 'onebike_rotor', None),
    'leather': ('vehicle_mesh', 'onebike_leather', None),
    'fabric': ('vehicle_mesh', 'onebike_fabric', None),
    'mesh_fabric': ('vehicle_mesh', 'onebike_mesh', None),
    'piping': ('vehicle_mesh', 'onebike_gloss', None),
    'zipper': ('vehicle_mesh', 'onebike_plastic', None),
    'webbing': ('vehicle_mesh', 'onebike_fabric', None),
    'lens_white': ('vehicle_lightsemissive', 'onebike_lens', 1),
    'lens_red': ('vehicle_lightsemissive', 'onebike_red', 3),
    'reflector_white': ('vehicle_mesh', 'onebike_refl', None),
    'reflector_amber': ('vehicle_paint2', 'onebike_white', None),
    'screen': ('vehicle_mesh', 'onebike_screen', None),
    'screen_text': ('vehicle_mesh', 'onebike_screentext', None),
    'led_green': ('vehicle_mesh', 'onebike_green', None),
    'button_rubber': ('vehicle_mesh', 'onebike_rubber', None),
    'screen_display': ('vehicle_lightsemissive', 'onebike_display', 0),  # light id 0: always on
}
SAMPLER_DEFAULTS = {
    'DirtSampler': 'onebike_dirt',
    'DamageSampler': 'onebike_damage',
    'SpecSampler': 'onebike_spec',
    'BumpSampler': 'onebike_nrm',
}

# How shiny each surface is in game: spec map + shader values, after GTA's own e-bike (Inductor: paint
# specularIntensityMult 0.15, falloff 180, fresnel 0.97). The first export used one bright spec map everywhere,
# which made fabric, rubber and plastic look like chrome.
SPEC = {   # kind: (spec texture, specularIntensityMult, specularFalloffMult, specularFresnel)
    'paint': ('onebike_spec_paint', 0.15, 180.0, 0.97),
    'gloss': ('onebike_spec_gloss', 0.55, 90.0, 0.90),
    'satin': ('onebike_spec_satin', 0.30, 40.0, 0.75),
    'matte': ('onebike_spec_matte', 0.08, 12.0, 0.50),
    'metal': ('onebike_spec_metal', 1.00, 120.0, 0.97),
    'light': ('onebike_spec_gloss', 0.60, 100.0, 0.95),
}
SURFACE = {
    'paint_black': 'paint', 'decal_black': 'paint', 'paint_yellow': 'paint', 'decal_yellow': 'paint',
    'reflector_amber': 'paint', 'decal_white': 'satin', 'decal_red': 'satin',
    'plastic_black': 'satin', 'plastic_gloss': 'gloss', 'piping': 'gloss', 'zipper': 'satin', 'alloy_black': 'satin',
    'rubber': 'matte', 'tyre': 'matte', 'leather': 'satin', 'fabric': 'matte', 'mesh_fabric': 'matte',
    'webbing': 'matte', 'button_rubber': 'matte',
    'steel': 'metal', 'steel_dark': 'metal', 'chain': 'metal', 'rotor': 'metal',
    'lens_white': 'light', 'lens_red': 'light', 'reflector_white': 'gloss', 'screen': 'gloss', 'screen_text': 'gloss',
    'led_green': 'light', 'screen_display': 'light',
}


def P(x, yz):
    return Vector((x, yz[0], yz[1] - ORIGIN_Z))


def bone_table():
    """(name, parent, armature-space matrix) in the vanilla Inductor order."""
    b = build
    yc, zc = b.BAR[0], b.BAR[1]                     # handlebar grip line
    pe_r = (b.BB[0] + 0.17 * math.cos(math.radians(b.CRANK_DEG)), b.BB[1] + 0.17 * math.sin(math.radians(b.CRANK_DEG)))
    pe_l = (b.BB[0] - (pe_r[0] - b.BB[0]), b.BB[1] - (pe_r[1] - b.BB[1]))
    head = Matrix.Translation(P(0, b.HT_TOP)) @ STEER
    t = lambda v: Matrix.Translation(v)
    seat = (b.SEAT_B[0] - 0.035, b.SEAT_B[1] + 0.165)   # top of the saddle, where the rider sits
    return [
        ('chassis', None, t(P(0, (0, ORIGIN_Z)))),
        ('chassis_lowlod', 'chassis', t(P(0, (0, ORIGIN_Z)))),
        ('seat_f', 'chassis', t(P(0, seat))),
        ('crank', 'chassis', t(P(0, b.BB))),
        ('pedal_l', 'crank', t(P(-0.14, pe_l))),
        ('pedal_r', 'crank', t(P(0.185, pe_r))),
        ('bodyshell', 'chassis', t(P(0, (0, ORIGIN_Z)))),
        ('swingarm', 'chassis', t(P(0, b.PV))),
        ('wheel_lr', 'swingarm', t(P(0, b.RA))),
        ('wheelmeshbk_r', 'wheel_lr', t(P(0, b.RA))),
        ('wheelmeshbk_r_l1', 'wheel_lr', t(P(0, b.RA))),
        ('wheelmeshbk_r_l2', 'wheel_lr', t(P(0, b.RA))),
        ('wheelmeshbk_r_ng', 'wheel_lr', t(P(0, b.RA))),
        ('handlebars', 'chassis', head),
        ('hbgrip_l', 'handlebars', t(Vector((-0.27, yc, zc - ORIGIN_Z)))),
        ('hbgrip_r', 'handlebars', t(Vector((0.27, yc, zc - ORIGIN_Z)))),
        ('forks_u', 'chassis', Matrix.Translation(P(0, b.HB)) @ STEER),
        ('forks_l', 'forks_u', Matrix.Translation(P(0, b.add(b.FA, b.UP, 0.24))) @ STEER),
        ('wheel_lf', 'forks_l', t(P(0, b.FA))),
        ('wheelmeshbk_f', 'wheel_lf', t(P(0, b.FA))),
        ('wheelmeshbk_f_l1', 'wheel_lf', t(P(0, b.FA))),
        ('wheelmeshbk_f_l2', 'wheel_lf', t(P(0, b.FA))),
        ('wheelmeshbk_f_ng', 'wheel_lf', t(P(0, b.FA))),
        ('dials', 'chassis', t(Vector((0, b.STEM_TOP[0] - 0.006, b.STEM_TOP[1] + 0.068 - ORIGIN_Z)))),
        ('headlight_l', 'forks_u', t(P(0, b.HEADLIGHT))),
        # motorbike bones (the bike now drives like GTA's electric motorbike): rear light on the rack, hub motor
        ('taillight_l', 'swingarm', t(P(0, b.TAILLIGHT))),
        ('brakelight_l', 'swingarm', t(P(0, b.TAILLIGHT))),
        ('engine', 'swingarm', t(P(0, b.RA))),
        ('chassis_dummy', 'chassis', t(P(0, (0, ORIGIN_Z)))),
    ]


# Which bone each modelled part rides on in game (the steering parts split between
# handlebars and forks_u, both of which the game turns with the steering input).
HANDLEBAR_PARTS = ('stem', 'bar_', 'handlebar', 'grip', 'lever', 'throttle', 'bell', 'remote', 'display', 'phone',
                   'decal_logo_stem')


def target_bone(ob):
    bone = ob['bone']
    if bone == 'forks_u' and ob.name.startswith(HANDLEBAR_PARTS):
        return 'handlebars'
    return bone


# ------------------------------------------------------------------ baking

def bake_lod(coll, lod_name, mats_order, bone_mats):
    """Evaluate every part, move it into its bone's space and merge per bone."""
    dg = bpy.context.evaluated_depsgraph_get()
    per_bone = defaultdict(list)
    for ob in list(coll.objects):
        if ob.get('render_only'):
            continue
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), depsgraph=dg)
        me.transform(Matrix.Translation((0, 0, -ORIGIN_Z)) @ ob.matrix_world)
        if lod_name == 'VERYLOW' and me.vertices:
            xs = [v.co for v in me.vertices]
            span = max(max(c[i] for c in xs) - min(c[i] for c in xs) for i in range(3))
            if span < 0.05:
                bpy.data.meshes.remove(me)
                continue
        if not me.polygons:
            bpy.data.meshes.remove(me)
            continue
        names = [m.name for m in me.materials]
        indices = [mats_order.index(names[p.material_index]) for p in me.polygons]
        me.materials.clear()  # note: clearing slots resets every face to slot 0
        for m in mats_order:
            me.materials.append(bpy.data.materials[m])
        me.polygons.foreach_set('material_index', indices)
        per_bone[target_bone(ob)].append(me)

    out = {}
    for bone, meshes in per_bone.items():
        bm = bmesh.new()
        for me in meshes:
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)
        sharp = [e for e in bm.edges if not e.is_manifold or e.calc_face_angle(math.pi) > math.radians(40)]
        bmesh.ops.split_edges(bm, edges=sharp)
        bmesh.ops.transform(bm, matrix=bone_mats[bone].inverted(), verts=bm.verts)
        src_uv = bm.loops.layers.uv.get('UVMap')  # authored UVs (the display screen)
        uv = bm.loops.layers.uv.new('UVMap 0')
        uv2 = bm.loops.layers.uv.new('UVMap 1')
        col = bm.loops.layers.color.new('Color 1')
        world = bone_mats[bone]
        for f in bm.faces:
            f.smooth = True
            nrm = (world.to_3x3() @ f.normal)
            ax = max(range(3), key=lambda i: abs(nrm[i]))
            light = SHADERS[mats_order[f.material_index]][2]
            authored = src_uv is not None and mats_order[f.material_index] == 'screen_display'
            for loop in f.loops:
                p = world @ loop.vert.co
                a, b = [(p.y, p.z), (p.x, p.z), (p.x, p.y)][ax]
                loop[uv].uv = loop[src_uv].uv if authored else (a * 4.0, b * 4.0)
                loop[uv2].uv = loop[uv].uv
                loop[col] = (1.0, 1.0, 1.0, (light / 255.0) if light is not None else 1.0)
        if src_uv is not None:
            bm.loops.layers.uv.remove(src_uv)
        me = bpy.data.meshes.new(f'{bone}_{lod_name}')
        bm.to_mesh(me)
        bm.free()
        for m in mats_order:
            me.materials.append(bpy.data.materials[m])
        out[bone] = me
    return out


def trim_materials(mesh, shader_mats):
    """Swap the lib materials for the Sollumz shader materials and drop unused slots."""
    used = sorted({p.material_index for p in mesh.polygons})
    remap = {old: new for new, old in enumerate(used)}
    names = [mesh.materials[i].name for i in used]
    indices = [remap[p.material_index] for p in mesh.polygons]
    mesh.materials.clear()  # resets every face to slot 0, so the indices are restored below
    for nme in names:
        mesh.materials.append(shader_mats[nme])
    mesh.polygons.foreach_set('material_index', indices)


# --------------------------------------------------------------- sollumz

def make_shader_materials(tex_dir, sm, shader_mats_mod):
    mats = {}
    images = {}

    def image(name):
        if name not in images:
            img = bpy.data.images.load(os.path.join(tex_dir, name + '.dds'), check_existing=True)
            img.name = name
            images[name] = img
        return images[name]

    for libname, (shader, diffuse, _light) in SHADERS.items():
        mat = shader_mats_mod.create_shader(shader + '.sps')
        mat.name = 'onebike_' + libname
        spec_tex, spec_mult, spec_falloff, spec_fresnel = SPEC[SURFACE[libname]]
        for node in mat.node_tree.nodes:
            if node.bl_idname == 'ShaderNodeTexImage':
                if node.name == 'DiffuseSampler':
                    tex = diffuse
                elif node.name == 'SpecSampler':
                    tex = spec_tex
                else:
                    tex = SAMPLER_DEFAULTS.get(node.name, 'onebike_white')
                node.image = image(tex)
                node.texture_properties.embedded = False
            elif node.bl_idname == 'SOLLUMZ_NT_SHADER_Parameter':
                value = {'specularIntensityMult': spec_mult, 'specularFalloffMult': spec_falloff,
                         'specularFresnel': spec_fresnel, 'reflectivePower': 0.45}.get(node.name)
                if value is not None:
                    node.set_float(value)
        mats[libname] = mat
    return mats


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    tex_dir = os.path.join(out, 'onebike')
    info = textures.generate(tex_dir)
    textures.write_ytd_xml(info, os.path.join(out, 'onebike.ytd.xml'))

    lib.reset_scene(keep_prefs=True)       # keep the user's add-ons (Sollumz extension on Windows)
    lib.make_materials()
    sz.enable()
    mod = lambda name: importlib.import_module(sz.PKG + '.' + name)
    # Sollumz writes every physics child with a minimum breaking impulse of 0; GTA's own bikes use 100 on every
    # child. (This alone did not fix the hanging wheels; see the bone-transform patch below.)
    yftexport = mod('yft.yftexport')
    if not getattr(yftexport, '_onebike_patched', False):
        _phys_child = yftexport.PhysChild

        def phys_child_100(*args, **kwargs):
            kwargs['min_breaking_impulse'] = 100.0
            return _phys_child(*args, **kwargs)

        yftexport.PhysChild = phys_child_100

        # Sollumz also fills the fragment's bone-transform set (CW XML <BoneTransforms>) with every bone's full
        # model-space matrix. GTA's own bikes (powersurge, inductor, both LODs) keep it all identity. With the full
        # matrices the game added the wheel offset twice: in game both wheels hung about twice as far out and low,
        # and the bike stood 0.7 m in the air. Physics is built from the real matrices before this point, so only
        # the stored set changes.
        # 2026-11-13: found by comparing with powersurge.yft; NOT yet confirmed in game.
        _core = yftexport.create_fragment_asset_core

        def core_identity_bones(*args, **kwargs):
            from mathutils import Matrix
            frag, hi_frag = _core(*args, **kwargs)
            for f in (frag, hi_frag):
                ms = getattr(f, 'matrix_set', None) if f is not None else None
                if ms is not None and getattr(ms, 'matrices', None):
                    ms.matrices = [Matrix(((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0))) for _ in ms.matrices]
            return frag, hi_frag

        yftexport.create_fragment_asset_core = core_identity_bones
        yftexport._onebike_patched = True
    SollumType = mod('sollumz_properties').SollumType
    LODLevel = mod('sollumz_properties').LODLevel
    bh = mod('tools.blenderhelper')
    dh = mod('tools.drawablehelper')
    meshh = mod('tools.meshhelper')
    colmats = mod('ybn.collision_materials')
    shader_mats_mod = mod('ydr.shader_materials')

    bones = bone_table()
    bone_mats = {name: m for name, _p, m in bones}
    mats_order = list(SHADERS.keys())

    lod_meshes = {}
    for lod_name, detail in LODS:
        lib.DETAIL = detail
        build.build(reset=False, collection='LOD_' + lod_name)
        coll = lib.COLLECTION
        lod_meshes[lod_name] = bake_lod(coll, lod_name, mats_order, bone_mats)
        for ob in list(coll.objects):
            bpy.data.objects.remove(ob)
        bpy.data.collections.remove(coll)
        print('baked', lod_name, {k: len(v.polygons) for k, v in lod_meshes[lod_name].items()}, flush=True)

    shader_mats = make_shader_materials(tex_dir, None, shader_mats_mod)

    # fragment + skeleton
    scene_coll = bpy.data.collections.new('onebike_export')
    bpy.context.scene.collection.children.link(scene_coll)
    layer_coll = bpy.context.view_layer.layer_collection.children['onebike_export']
    bpy.context.view_layer.active_layer_collection = layer_coll

    arm = bpy.data.armatures.new('skel')
    frag = bh.create_blender_object(SollumType.FRAGMENT, 'onebike', object_data=arm)
    bpy.context.view_layer.objects.active = frag
    frag.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name, parent, m in bones:
        eb = arm.edit_bones.new(name)
        eb.head = (0, 0, 0)
        eb.tail = (0, 0.05, 0)
        eb.matrix = m
        if parent:
            eb.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')

    def flags(bone, names):
        for nme in names:
            arm.bones[bone].bone_properties.flags.add().name = nme

    # bone degrees of freedom exactly as in GTA's own bikes (Powersurge, Inductor): every bone may rotate on all
    # axes, the chassis and the wheels may also move on all axes. With single-axis flags the game placed the
    # wheels once more at their own offset, so they hung next to the bike.
    for name, _parent, _m in bones:
        flags(name, ('RotX', 'RotY', 'RotZ'))
    for bone in ('chassis', 'wheel_lf', 'wheel_lr'):
        flags(bone, ('TransX', 'TransY', 'TransZ'))
    # physics groups as in GTA's own bikes (Powersurge / Inductor): chassis, each wheel, the seat and chassis_dummy
    for bone in ('chassis', 'wheel_lf', 'wheel_lr', 'seat_f', 'chassis_dummy'):
        arm.bones[bone].sollumz_use_physics = True

    drawable = bh.create_empty_object(SollumType.DRAWABLE, 'onebike.drawable')
    drawable.parent = frag

    for bone in sorted(lod_meshes['HIGH'].keys()):
        hi_mesh = lod_meshes['HIGH'][bone]
        trim_materials(hi_mesh, {k: shader_mats[k] for k in SHADERS})
        ob = bpy.data.objects.new(bone, hi_mesh)
        scene_coll.objects.link(ob)
        dh.convert_obj_to_model(ob)
        for lod_name, level in (('VERYHIGH', LODLevel.VERYHIGH), ('MEDIUM', LODLevel.MEDIUM),
                                ('LOW', LODLevel.LOW), ('VERYLOW', LODLevel.VERYLOW)):
            me = lod_meshes[lod_name].get(bone)
            if me is None:
                continue
            trim_materials(me, {k: shader_mats[k] for k in SHADERS})
            ob.sz_lods.get_lod(level).mesh = me
        ob.parent = drawable
        bh.add_child_of_bone_constraint(ob, frag, bone)
        if bone in WHEEL_BONES:
            ob.sollumz_is_physics_child_mesh = True

    # collisions
    comp = bh.create_empty_object(SollumType.BOUND_COMPOSITE, 'onebike.col')
    comp.parent = frag
    car_metal = colmats.create_collision_material_from_index(116)
    rubber = colmats.create_collision_material_from_index(93)
    type_flags = ('vehicle_not_bvh',)
    include_flags = ('map_weapon', 'map_dynamic', 'map_animal', 'map_cover', 'map_vehicle', 'vehicle_not_bvh',
                     'vehicle_bvh', 'ped', 'ragdoll', 'animal', 'animal_ragdoll', 'object', 'plant', 'projectile',
                     'explosion', 'forklift_forks', 'test_weapon', 'test_camera', 'test_ai', 'test_script',
                     'test_vehicle_wheel', 'glass')

    def bound(obj, bone, mat, mass):
        obj.data.materials.append(mat)
        for f in type_flags:
            setattr(obj.composite_flags1, f, True)
        for f in include_flags:
            setattr(obj.composite_flags2, f, True)
        obj.child_properties.mass = mass
        obj.parent = comp
        bh.add_child_of_bone_constraint(obj, frag, bone)

    z = -ORIGIN_Z
    # chassis: three pieces like the Powersurge (front/cockpit, frame and drive, rear rack and battery)
    boxes = [   # matched to the photo-measured model (see build.py)
        ('front', (0.66, 0.34, 0.62), (0.0, 0.45, 1.04 + z), 63.0),
        ('frame', (0.14, 0.78, 0.58), (0.0, 0.02, 0.52 + z), 63.0),
        ('rear', (0.24, 0.62, 0.46), (0.0, -0.58, 0.55 + z), 63.0),
    ]
    for name, size, center, mass in boxes:
        obj = bh.create_blender_object(SollumType.BOUND_BOX, f'col_{name}')
        meshh.create_box(obj.data, 1, Matrix.LocRotScale(Vector(center), None, Vector(size)))
        bound(obj, 'chassis', car_metal, mass)
    # each wheel has two identical discs in its group, the first one carries the wheel mesh (as in the game's bikes)
    for bone, mass in (('wheel_lf', 9.3), ('wheel_lr', 12.0)):
        for k in range(2):
            obj = bh.create_blender_object(SollumType.BOUND_DISC, f'col_{bone}_{k}')
            meshh.create_disc(obj.data, radius=build.TYRE_R, length=0.10)
            bound(obj, bone, rubber, mass)
    # seat: a capsule along the bike on seat_f
    obj = bh.create_blender_object(SollumType.BOUND_CAPSULE, 'col_seat')
    meshh.create_capsule(obj.data, radius=0.15, length=0.42, axis='Y')
    bound(obj, 'seat_f', car_metal, 49.0)
    # chassis_dummy: one box round the whole bike
    lo = Vector((-0.35, -0.90, build.GROUND_Z + 0.02 - ORIGIN_Z))
    hi = Vector((0.35, 0.96, 1.40 - ORIGIN_Z))
    obj = bh.create_blender_object(SollumType.BOUND_BOX, 'col_dummy')
    meshh.create_box(obj.data, 1, Matrix.LocRotScale((lo + hi) / 2, None, hi - lo))
    bound(obj, 'chassis_dummy', car_metal, 420.0)

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, 'onebike_gta.blend'))
    # CodeWalker XML always; binary .yft too when Sollumz has PyMateria (the Windows install has it)
    formats = {'CWXML'}
    try:
        import pymateria  # noqa: F401
        formats.add('NATIVE')
    except ImportError:
        pass
    res = bpy.ops.sollumz.export_assets(directory=out + os.sep, direct_export=True, use_custom_settings=True,
                                        target_formats=formats, target_versions={'GEN8'}, limit_to_selected=False)
    print('export result', res, sorted(formats), flush=True)


main()
