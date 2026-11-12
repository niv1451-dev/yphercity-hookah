"""Re-import the exported XML with Sollumz, report its structure and render it,
once at rest and once with steering, suspension and pedals posed.

Usage: python verify.py <gta_out_dir> <render_dir>
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
import render  # noqa: E402
import sz  # noqa: E402


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    lib.reset_scene(keep_prefs=True)       # keep the user's add-ons (Sollumz extension on Windows)
    sz.enable()
    res = bpy.ops.sollumz.import_assets(directory=src + os.sep, files=[{'name': 'onebike.yft.xml'}])
    print('import', res)
    frag = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    print('fragment', frag.name, 'bones', len(frag.data.bones))
    for b in frag.data.bones:
        print('  bone %-18s parent=%-12s head=(%.3f, %.3f, %.3f) physics=%s' % (
            b.name, b.parent.name if b.parent else '-', *b.head_local, b.sollumz_use_physics))
    kinds = {}
    for o in bpy.data.objects:
        kinds.setdefault(o.sollum_type, []).append(o.name)
    for k, v in sorted(kinds.items()):
        print(' ', k, len(v), v[:8])
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == 'MESH' and o.sollum_type == 'sollumz_drawable_model'
               for p in o.data.polygons)
    print('drawable model triangles (active LOD):', tris)
    for o in bpy.data.objects:
        if o.sollum_type and 'bound' in o.sollum_type:
            o.hide_render = True

    frag.location.z = 0.60  # the model origin sits 0.6 m above the ground
    render.studio()
    scene = bpy.context.scene
    scene.cycles.samples = 24
    scene.render.resolution_x = 900
    scene.render.resolution_y = 560
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'

    def shot(tag, view):
        cam = render.camera(view)
        scene.render.filepath = os.path.join(out, 'raw_%s.png' % tag)
        bpy.ops.render.render(write_still=True)
        render.composite(scene.render.filepath, os.path.join(out, 'verify_%s.jpg' % tag))
        bpy.data.objects.remove(cam)

    shot('rest', 'front34')
    shot('display', 'closeup_display')
    pose = frag.pose.bones
    for name, euler in (('handlebars', (0, 0, 25)), ('forks_u', (0, 0, 25)), ('crank', (45, 0, 0)),
                        ('pedal_r', (-45, 0, 0)), ('pedal_l', (-45, 0, 0)), ('swingarm', (-5, 0, 0))):
        pb = pose[name]
        pb.rotation_mode = 'XYZ'
        pb.rotation_euler = [math.radians(v) for v in euler]
    pose['forks_l'].location = (0, 0, -0.04)
    bpy.context.view_layer.update()
    shot('posed', 'front34')


main()
