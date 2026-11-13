"""בדיקה: לאיזה כיוון פונים המשטחים של הצמיג והחישוק (החוצה או פנימה).

הרצה (מתוך blender/): blender -b --python win.py -- ../gametest/tyre_normals.py
לכל חלק של הגלגל הקדמי: כמה משטחים פונים החוצה מהצינור של הצמיג וכמה פנימה.
המשחק מצייר רק את הצד החיצוני של כל משטח, אז משטח שפונה פנימה נראה שקוף.
"""
import math
import os
import sys

import bpy  # noqa: F401

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'blender'))
import build  # noqa: E402

build.build()
FA = build.FA
for ob in bpy.data.objects:
    if ob.type != 'MESH' or not ob.name.startswith('front_') and 'wheel' not in ob.get('bone', ''):
        continue
    if ob.get('bone') != 'wheel_lf':
        continue
    me = ob.data
    mw = ob.matrix_world
    out = inn = 0
    for p in me.polygons:
        c = mw @ p.center
        n = (mw.to_3x3() @ p.normal).normalized()
        # מרכז הצינור של הצמיג: באותו כיוון רדיאלי, ברדיוס 0.25 ובאמצע הרוחב
        dy, dz = c.y - FA[0], c.z - FA[1]
        r = math.hypot(dy, dz) or 1.0
        tube = (0.0, FA[0] + dy / r * 0.25, FA[1] + dz / r * 0.25)
        v = (c.x - tube[0], c.y - tube[1], c.z - tube[2])
        if v[0] * n.x + v[1] * n.y + v[2] * n.z >= 0:
            out += 1
        else:
            inn += 1
    print(f'NORMALS {ob.name}: החוצה={out} פנימה={inn}')
