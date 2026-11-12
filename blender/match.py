"""Render the bike through the camera solved from the reference photo and compare it with the photo.

Usage: python match.py <out_dir> <samples> [scale] [photo]
The camera comes from reference/camera.json (solved by photo_match/calib.py from the yellow rim stripes).
The front end is turned by the steering angle seen in the photo.
Writes match_render.png (RGBA), match_over.jpg (model over the photo), match_blend.jpg (50/50),
match_outline.jpg (model silhouette on the photo) and match_side.jpg (photo | model).
With 'photo' as 4th argument the lighting tries to match the shaded daylight of the photo.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector
from PIL import Image, ImageChops, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build  # noqa: E402
import lib  # noqa: E402
import render  # noqa: E402

REF = os.path.join(HERE, '..', 'reference', 'reference.jpg')
CAM = os.path.join(HERE, '..', 'reference', 'camera.json')
STEER_BONES = ('forks_u', 'forks_l', 'wheel_lf')


def steer(angle_deg):
    axis = Vector((0.0, build.UP[0], build.UP[1])).normalized()
    pivot = Vector((0.0, build.HB[0], build.HB[1]))
    m = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(angle_deg), 4, axis) @ Matrix.Translation(-pivot)
    for ob in bpy.data.objects:
        if ob.get('bone') in STEER_BONES:
            ob.matrix_world = m @ ob.matrix_world


def photo_camera(cam_json, width):
    c = json.load(open(cam_json))
    r, u, f = (Vector(c[k]) for k in ('right', 'up', 'forward'))
    data = bpy.data.cameras.new('match_cam')
    data.sensor_fit = 'HORIZONTAL'
    data.sensor_width = 36.0
    data.lens = c['lens_mm']
    data.clip_start = 0.05
    ob = bpy.data.objects.new('match_cam', data)
    bpy.context.scene.collection.objects.link(ob)
    rot = Matrix((r, u, -f)).transposed()
    ob.matrix_world = Matrix.Translation(Vector(c['location'])) @ rot.to_4x4()
    bpy.context.scene.camera = ob
    return c


def photo_light():
    """Bright overcast shade under a building: soft sky from the open side, weak bounce, no hard sun."""
    scene = bpy.context.scene
    bg = scene.world.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value = (0.86, 0.88, 0.92, 1)
    bg.inputs['Strength'].default_value = 0.9
    for name in ('key', 'fill', 'rim', 'top'):
        bpy.data.objects[name].data.energy *= 0.5
    lib.area_light('sky_open', (3.5, -1.5, 2.5), (0, 0, 0.5), 900, 4.0, color=(0.92, 0.95, 1.0))


def main():
    out, samples = sys.argv[1], int(sys.argv[2])
    scale = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
    photo = len(sys.argv) > 4 and sys.argv[4] == 'photo'
    os.makedirs(out, exist_ok=True)
    ref = Image.open(REF).convert('RGB')
    W, H = ref.size
    build.build()
    render.studio()
    if photo:
        photo_light()
    if not photo:   # no shadow catcher: its shadow would swamp the silhouette
        bpy.data.objects.remove(bpy.data.objects['floor'])
    c = photo_camera(CAM, W)
    steer(c['front_steer_deg'])
    scene = bpy.context.scene
    scene.cycles.samples = samples
    scene.render.resolution_x = int(W * scale)
    scene.render.resolution_y = int(H * scale)
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    raw = os.path.join(out, 'match_render.png')
    scene.render.filepath = raw
    bpy.ops.render.render(write_still=True)

    ren = Image.open(raw).convert('RGBA').resize((W, H), Image.LANCZOS)
    base = ref.convert('RGBA')
    over = base.copy()
    over.alpha_composite(ren)
    over.convert('RGB').save(os.path.join(out, 'match_over.jpg'), quality=90)
    flat = Image.new('RGBA', (W, H), (235, 235, 235, 255))
    flat.alpha_composite(ren)
    Image.blend(ref, flat.convert('RGB'), 0.5).save(os.path.join(out, 'match_blend.jpg'), quality=90)
    a = ren.split()[3].point(lambda v: 255 if v > 100 else 0)
    edge = ImageChops.subtract(a.filter(ImageFilter.MaxFilter(3)), a.filter(ImageFilter.MinFilter(3)))
    outl = ref.copy()
    outl.paste((0, 255, 255), mask=edge)
    outl.save(os.path.join(out, 'match_outline.jpg'), quality=90)
    side = Image.new('RGB', (W * 2 + 20, H), (255, 255, 255))
    side.paste(ref, (0, 0))
    side.paste(over.convert('RGB'), (W + 20, 0))
    side.resize((side.width // 2, side.height // 2), Image.LANCZOS).save(os.path.join(out, 'match_side.jpg'), quality=90)
    print('match done', out, flush=True)


if __name__ == '__main__':
    main()
