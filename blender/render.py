"""Build the bike and render studio previews.

Usage: python render.py <out_dir> <width> <samples> <view> [<view> ...]
Views: front34, side, rear34, front, closeup_rear, closeup_cockpit
"""
import os
import sys

import bpy
from mathutils import Vector
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build  # noqa: E402
import lib  # noqa: E402

VIEWS = {
    'front34': ((2.45, 2.25, 1.3), (0.0, 0.02, 0.62), 50),
    'side': ((3.7, 0.0, 0.62), (0.0, 0.0, 0.60), 50),
    'rear34': ((-2.2, -2.15, 1.3), (0.0, -0.05, 0.55), 50),
    'front': ((0.25, 3.6, 0.95), (0.0, 0.0, 0.62), 50),
    'closeup_rear': ((1.05, -0.35, 0.75), (0.02, -0.25, 0.45), 45),
    'closeup_cockpit': ((0.75, 1.0, 1.45), (0.0, 0.38, 1.0), 45),
    'photo': ((1.9, -0.42, 1.38), (0.0, 0.02, 0.64), 24),
    'closeup_logo': ((0.55, 0.17, 0.62), (0.0, 0.17, 0.59), 50),
    'closeup_bag': ((0.75, 0.95, 1.28), (0.0, 0.42, 1.10), 50),
    'closeup_display': ((0.07, 0.03, 1.43), (-0.045, 0.30, 1.155), 38),
}


def studio():
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    try:
        scene.view_settings.view_transform = 'Standard'
        scene.view_settings.look = 'None'
    except TypeError:
        pass
    world = bpy.data.worlds.new('World')
    scene.world = world
    try:
        world.use_nodes = True
    except AttributeError:
        pass
    bg = world.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value = (0.9, 0.9, 0.92, 1)
    bg.inputs['Strength'].default_value = 0.28

    me = bpy.data.meshes.new('floor')
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=6.0)
    bm.to_mesh(me)
    bm.free()
    floor = bpy.data.objects.new('floor', me)
    floor.is_shadow_catcher = True
    scene.collection.objects.link(floor)

    lib.area_light('key', (2.6, 1.6, 3.0), (0, 0, 0.5), 420, 2.5)
    lib.area_light('fill', (-2.6, 2.2, 1.8), (0, 0, 0.5), 150, 3.0)
    lib.area_light('rim', (0.3, -3.4, 2.4), (0, 0, 0.6), 380, 2.0)
    lib.area_light('top', (0.0, 0.0, 4.0), (0, 0, 0), 140, 3.5)


def outdoor():
    """Sunlit paved courtyard instead of the studio backdrop."""
    scene = bpy.context.scene
    scene.render.film_transparent = False
    floor = bpy.data.objects['floor']
    floor.is_shadow_catcher = False
    floor.scale = (12, 12, 1)
    mat = bpy.data.materials.new('pavers')
    nt = mat.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    geo = nt.nodes.new('ShaderNodeNewGeometry')  # world-space position, so pavers have a real size
    brick = nt.nodes.new('ShaderNodeTexBrick')
    nt.links.new(geo.outputs['Position'], brick.inputs['Vector'])
    brick.inputs['Scale'].default_value = 2.6
    brick.inputs['Mortar Size'].default_value = 0.004
    brick.inputs['Color1'].default_value = (0.15, 0.145, 0.14, 1)
    brick.inputs['Color2'].default_value = (0.11, 0.105, 0.10, 1)
    brick.inputs['Mortar'].default_value = (0.05, 0.048, 0.045, 1)
    noise = nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 60.0
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.25
    nt.links.new(brick.outputs['Color'], bsdf.inputs['Base Color'])
    nt.links.new(noise.outputs['Fac'], bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    bsdf.inputs['Roughness'].default_value = 0.85
    floor.data.materials.append(mat)
    bg = scene.world.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value = (0.78, 0.82, 0.88, 1)
    bg.inputs['Strength'].default_value = 0.55
    for name in ('key', 'fill', 'rim', 'top'):
        bpy.data.objects[name].data.energy *= 0.35
    sun_data = bpy.data.lights.new('sun', 'SUN')
    sun_data.energy = 2.6
    sun_data.angle = 0.02
    sun = bpy.data.objects.new('sun', sun_data)
    sun.rotation_euler = (0.85, 0.15, 2.4)
    scene.collection.objects.link(sun)


def camera(view):
    loc, target, lens = VIEWS[view]
    cam_data = bpy.data.cameras.new('cam')
    cam_data.lens = lens
    cam = bpy.data.objects.new('cam', cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = loc
    lib.look_at(cam, target)
    bpy.context.scene.camera = cam
    return cam


def composite(src, dst):
    fg = Image.open(src).convert('RGBA')
    w, h = fg.size
    bg = Image.new('RGBA', (w, h))
    d = ImageDraw.Draw(bg)
    for y in range(h):
        t = y / h
        c = int(244 - 26 * t)
        d.line([(0, y), (w, y)], fill=(c, c, c - 3, 255))
    bg.alpha_composite(fg)
    bg.convert('RGB').save(dst, quality=92)


def main():
    out, width, samples = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    views = sys.argv[4:]
    os.makedirs(out, exist_ok=True)
    build.build()
    studio()
    if os.environ.get('OUTDOOR'):
        outdoor()
    scene = bpy.context.scene
    scene.cycles.samples = samples
    scene.render.resolution_x = width
    scene.render.resolution_y = int(width * 0.625)
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, 'onebike.blend'))
    for v in views:
        scene.render.resolution_y = int(width * (0.5625 if v == 'photo' else 0.625))
        cam = camera(v)
        raw = os.path.join(out, 'raw_%s.png' % v)
        scene.render.filepath = raw
        bpy.ops.render.render(write_still=True)
        if os.environ.get('OUTDOOR'):
            Image.open(raw).convert('RGB').save(os.path.join(out, 'onebike_%s.jpg' % v), quality=92)
        else:
            composite(raw, os.path.join(out, 'onebike_%s.jpg' % v))
        bpy.data.objects.remove(cam)
        print('rendered', v, flush=True)


if __name__ == '__main__':
    main()
