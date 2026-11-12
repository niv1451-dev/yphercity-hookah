"""Builds the One Bike fat-tire e-bike from the reference photo.

Layout (side view, metres, measured on the photo through the solved camera in
reference/camera.json): rear axle RA, front axle FA, crank axle BB, swingarm
pivot PV, shock lower eye SN (swingarm), shock upper eye FM (under the arch),
folding hinge HG, steering axis 17 degrees from vertical through the front axle.
"""
import math

from mathutils import Matrix, Vector

import lib
from lib import V

RA = (-0.648, 0.33)
FA = (0.648, 0.33)
BB = (-0.083, 0.335)
PV = (-0.236, 0.305)
SN = (-0.144, 0.525)
FM = (-0.040, 0.604)
HEAD = math.radians(17.0)
UP = (-math.sin(HEAD), math.cos(HEAD))                             # steering axis, upward
FWD = (UP[1], -UP[0])                                              # perpendicular, forward


def on_axis(z):
    """Point of the steering axis at height z."""
    return (FA[0] - (z - FA[1]) * math.tan(HEAD), z)


HB = on_axis(0.79)                     # head tube bottom
HT_TOP = on_axis(0.91)                 # head tube top
HT_MID = on_axis(0.861)                # where the main tube meets the head tube
HG = (0.072, 0.598)                    # folding hinge
MT_A = (0.094, 0.626)                  # main tube start at the hinge
SEAT_A, SEAT_B = (-0.140, 0.565), (-0.190, 0.752)   # seat tube bottom end and clamp
STEM_TOP = (0.30, 1.265)
TYRE_R = 0.33
RACK_Z = 0.705          # top rail of the rear rack


def _front_geometry():
    """Fork leg tops, steering axis point at crown height, crown centre and headlight."""
    legs_top = (FA[0] + UP[0] * (HB[1] - 0.03 - FA[1]) / UP[1], HB[1] - 0.03)
    axis_at = (HB[0] + (HB[1] - legs_top[1]) / UP[1] * -UP[0], legs_top[1])
    cc = (axis_at[0] + (legs_top[0] - axis_at[0]) * 0.55, legs_top[1])
    hl = (cc[0] + FWD[0] * 0.06 + UP[0] * 0.035, cc[1] + FWD[1] * 0.06 + UP[1] * 0.035)
    return legs_top, axis_at, cc, hl


HEADLIGHT = (_front_geometry()[3][0] + 0.0175, _front_geometry()[3][1])   # headlight lens, for the exporter


def P(x, yz):
    return V((x, yz[0], yz[1]))


def add(a, b, s=1.0):
    return (a[0] + b[0] * s, a[1] + b[1] * s)


def along(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def ang_yz(a, b):
    return math.atan2(b[1] - a[1], b[0] - a[0])


def rot_x(angle, loc=(0, 0, 0)):
    m = Matrix.Rotation(angle, 4, 'X')
    m.translation = V(loc)
    return m


def tube_matrix(a3, b3, loc3):
    """Local Z along a->b, local X world X."""
    z = (V(b3) - V(a3)).normalized()
    x = V((1, 0, 0))
    y = z.cross(x).normalized()
    x = y.cross(z).normalized()
    return lib.basis(x, y, z, loc3)


# ------------------------------------------------------------------ wheels

def wheel(prefix, c, bone, rear):
    cy, cz = c
    center = (0.0, cy, cz)
    half = [(0.036, 0.206), (0.040, 0.214), (0.046, 0.228), (0.050, 0.245), (0.0515, 0.262),
            (0.0505, 0.280), (0.047, 0.296), (0.042, 0.307), (0.034, 0.315), (0.022, 0.320),
            (0.010, 0.3215), (0.0, 0.322)]
    prof = half + [(-x, r) for x, r in reversed(half[:-1])]
    lib.lathe(prefix + '_tyre', prof, 128, 'tyre', bone, center)

    import bmesh
    bm = bmesh.new()
    count = lib.n(58, 20)
    rows = [(0.0, 0.3215, 0.022, 0.026, 0.0, 0.0),
            (0.0255, 0.318, 0.019, 0.024, 0.5, 14.0),
            (-0.0255, 0.318, 0.019, 0.024, 0.5, -14.0),
            (0.0435, 0.3045, 0.013, 0.026, 0.0, 50.0),
            (-0.0435, 0.3045, 0.013, 0.026, 0.0, -50.0)]
    if lib.DETAIL < 0.45:
        rows = rows[:3]
    if lib.DETAIL < 0.2:
        rows = []
    for x, r, wx, wt, shift, tilt in rows:
        h = 0.0065
        for k in range(count):
            th = 2 * math.pi * (k + shift) / count
            m = (Matrix.Translation(V(center)) @ Matrix.Rotation(th, 4, 'X')
                 @ Matrix.Translation(V((x, 0, r))) @ Matrix.Rotation(math.radians(tilt), 4, 'Y')
                 @ Matrix.Translation(V((0, 0, h / 2 - 0.001)))
                 @ Matrix.Diagonal((wx, wt, h, 1.0)))
            bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    if rows:
        knobs = lib.bm_to_obj(prefix + '_tread', bm, 'tyre', bone)
        lib.add_bevel(knobs, 0.0022, 2, 30.0)

    rim = [(0.042, 0.2145), (0.0455, 0.2165), (0.0455, 0.205), (0.041, 0.197), (0.041, 0.186),
           (-0.041, 0.186), (-0.041, 0.197), (-0.0455, 0.205), (-0.0455, 0.2165), (-0.042, 0.2145),
           (-0.036, 0.206), (0.036, 0.206)]
    lib.lathe(prefix + '_rim', rim, 128, 'alloy_black', bone, center, closed=True)
    for s in (1, -1):
        x0 = s * 0.0457
        lib.ring_prism(prefix + '_rimstripe%+d' % s, lib.circle_pts(0.2132, lib.n(128, 24)), lib.circle_pts(0.2068, lib.n(128, 24)),
                       x0, x0 + s * 0.0006, 'decal_yellow', bone, center)

    # mag wheel with six pairs of thin spokes
    bm = bmesh.new()
    r_hub = 0.092 if rear else 0.05
    r_rim = 0.19
    steps = lib.n(6, 2)
    for i in range(12):
        pair, side = divmod(i, 2)
        sign = 1 if side else -1
        base = math.radians(pair * 60 + 12)
        outline = []
        for k in range(steps + 1):
            t = k / steps
            r = r_hub + (r_rim - r_hub) * t
            off = sign * (0.006 + 0.03 * t)
            w = 0.016 - 0.004 * t
            outline.append((off - w / 2, r))
        for k in range(steps, -1, -1):
            t = k / steps
            r = r_hub + (r_rim - r_hub) * t
            off = sign * (0.006 + 0.03 * t)
            w = 0.016 - 0.004 * t
            outline.append((off + w / 2, r))
        th = 0.012
        top, bot = [], []
        for tg, rr in outline:
            y = tg * math.cos(base) - rr * math.sin(base)
            z = tg * math.sin(base) + rr * math.cos(base)
            top.append(bm.verts.new((th, cy + y, cz + z)))
            bot.append(bm.verts.new((-th, cy + y, cz + z)))
        bm.faces.new(top)
        bm.faces.new(list(reversed(bot)))
        n = len(top)
        for k in range(n):
            j = (k + 1) % n
            bm.faces.new((top[k], bot[k], bot[j], top[j]))
    spokes = lib.bm_to_obj(prefix + '_spokes', bm, 'alloy_black', bone, smooth=True, weighted=True)
    lib.add_bevel(spokes, 0.003, 2, 30.0)

    if rear:
        m = lib.frame_from_z((1, 0, 0), center)
        lib.cylinder(prefix + '_motor', 0.094, 0.115, 'alloy_black', bone, matrix=m, verts=64, bevel=0.006)
        lib.cylinder(prefix + '_motorcap', 0.06, 0.125, 'steel_dark', bone, matrix=m, verts=48, bevel=0.003)
    else:
        m = lib.frame_from_z((1, 0, 0), center)
        lib.cylinder(prefix + '_hub', 0.052, 0.10, 'alloy_black', bone, matrix=m, verts=48, bevel=0.005)
        lib.cylinder(prefix + '_hubcap', 0.03, 0.12, 'steel_dark', bone, matrix=m, verts=32, bevel=0.003)
    lib.cylinder(prefix + '_axle', 0.0065, 0.235, 'steel', bone, matrix=lib.frame_from_z((1, 0, 0), center), verts=16)
    for s in (1, -1):
        lib.cylinder(prefix + '_nut%+d' % s, 0.0105, 0.009, 'steel', bone, verts=6,
                     matrix=lib.frame_from_z((1, 0, 0), (s * 0.112, cy, cz)))

    # disc rotor (left side)
    rx = -0.066 if rear else -0.062
    lib.ring_prism(prefix + '_rotor', lib.circle_pts(0.090, lib.n(96, 16)), lib.circle_pts(0.074, lib.n(96, 16)), rx, rx - 0.0018,
                   'rotor', bone, center)
    for k in range(5):
        a = 2 * math.pi * k / 5
        mid = 0.05
        m = rot_x(a, (rx - 0.0009, cy, cz)) @ Matrix.Translation(V((0, 0, mid)))
        lib.box(prefix + '_spider%d' % k, (0.0018, 0.012, 0.05), 'rotor', bone, matrix=m)

    # white spoke reflector
    a = math.radians(12 + 60 * 2)
    m = rot_x(a, center) @ Matrix.Translation(V((0, 0.0, 0.135)))
    lib.box(prefix + '_reflector', (0.032, 0.022, 0.075), 'reflector_white', bone, matrix=m, bevel=0.004)


# ------------------------------------------------------------------- frame

ARCH_OUTER = [(-0.178, 0.700), (-0.160, 0.710), (-0.107, 0.711), (-0.049, 0.699), (0.008, 0.668), (0.044, 0.637),
              (0.066, 0.603), (0.074, 0.575)]
ARCH_INNER = [(0.030, 0.552), (0.022, 0.572), (-0.002, 0.602), (-0.049, 0.628), (-0.110, 0.641), (-0.150, 0.640),
              (-0.172, 0.652), (-0.183, 0.676)]


def frame():
    # main tube: rectangular section, folding hinge -> head tube, 31 degrees up
    mt = lib.resample([P(0, MT_A), P(0, HT_MID)], 0.01)
    lib.sweep('frame_main', mt, lambda u: lib.rrect_profile(0.056, 0.074 - 0.006 * u, 0.019), 'paint_black', 'chassis')
    lib.sweep('frame_main_cap', lib.resample([P(0, along(MT_A, HT_MID, 0.88)), P(0, add(HT_MID, (0.012, 0.006)))], 0.01),
              lambda u: lib.rrect_profile(0.06, 0.07 + 0.012 * u, 0.02), 'paint_black', 'chassis')

    lib.cylinder('frame_headtube', 0.029, 0, 'paint_black', 'chassis',
                 start=P(0, add(HB, UP, -0.006)), end=P(0, add(HT_TOP, UP, 0.004)), verts=40, bevel=0.003)
    for t, name in ((-0.012, 'lower'), (0.128, 'upper')):
        c = add(HB, UP, t)
        lib.cylinder('headset_' + name, 0.031, 0.012, 'steel_dark', 'chassis',
                     start=P(0, add(c, UP, -0.006)), end=P(0, add(c, UP, 0.006)), verts=40)

    # folding hinge: two knuckle blocks, vertical barrels on the right, quick-release bolt with a knob
    lib.box('hinge_block_front', (0.064, 0.034, 0.122), 'paint_black', 'chassis', loc=(0, HG[0] + 0.016, HG[1] + 0.002),
            bevel=0.007)
    lib.box('hinge_block_rear', (0.064, 0.03, 0.118), 'paint_black', 'chassis', loc=(0, HG[0] - 0.016, HG[1] - 0.004),
            bevel=0.007)
    for k, z in enumerate((-0.045, -0.006, 0.033)):
        lib.cylinder('hinge_barrel%d' % k, 0.0105, 0, 'paint_black', 'chassis', start=V((0.031, HG[0] - 0.002, HG[1] + z)),
                     end=V((0.031, HG[0] - 0.002, HG[1] + z + 0.034)), verts=20, bevel=0.0015)
    lib.cylinder('hinge_pin', 0.0045, 0, 'steel', 'chassis', start=V((0.031, HG[0] - 0.002, HG[1] - 0.052)),
                 end=V((0.031, HG[0] - 0.002, HG[1] + 0.073)), verts=12)
    qr_z = HG[1] - 0.012
    lib.cylinder('hinge_qr_bolt', 0.0042, 0, 'steel', 'chassis', start=V((0.036, HG[0] - 0.012, qr_z)),
                 end=V((0.036, HG[0] + 0.052, qr_z - 0.003)), verts=12)
    lib.cylinder('hinge_qr_nut', 0.0075, 0, 'steel', 'chassis', start=V((0.036, HG[0] + 0.004, qr_z)),
                 end=V((0.036, HG[0] + 0.014, qr_z)), verts=6)
    lib.cylinder('hinge_qr_knob', 0.0085, 0, 'steel', 'chassis', start=V((0.036, HG[0] + 0.050, qr_z - 0.003)),
                 end=V((0.036, HG[0] + 0.066, qr_z - 0.004)), verts=20, bevel=0.002)

    # down post: from under the hinge down behind the chainring to the crank axle
    dp = lib.resample(lib.spline([(0.052, 0.585), (0.014, 0.52), (0.002, 0.455), (-0.03, 0.385), (-0.083, 0.345)], 6),
                      0.01)
    lib.sweep('frame_downpost', [P(0, p) for p in dp], lambda u: lib.rrect_profile(0.052, 0.074 - 0.012 * u, 0.016),
              'paint_black', 'chassis')
    lib.cylinder('frame_bbshell', 0.026, 0, 'paint_black', 'chassis', start=P(-0.048, BB), end=P(0.048, BB), verts=32,
                 bevel=0.002)

    # curved arch from the seat tube over the shock to the hinge, with a slot
    outline = lib.spline(ARCH_OUTER, 6) + lib.spline(ARCH_INNER, 6)
    slot = [(-0.098 + 0.017 * math.cos(a), 0.668 + 0.0065 * math.sin(a)) for a in
            (2 * math.pi * k / 20 for k in range(20))]
    lib.plate('frame_arch', outline, -0.021, 0.021, 'paint_black', 'chassis', holes=[slot], bevel=0.007)
    for s in (1, -1):
        lib.plate('shock_tab%+d' % s, [(-0.062, 0.632), (-0.022, 0.628), (-0.028, 0.596), (-0.052, 0.592)],
                  s * 0.013, s * 0.018, 'paint_black', 'chassis', bevel=0.0015)
    # dashes along the top of the arch (both sides)
    dash = lib.spline(ARCH_OUTER[1:6], 10)
    for s in (1, -1):
        bmname = 'decal_arch_dashes%+d' % s
        import bmesh
        bm = bmesh.new()
        for k in range(len(dash) - 1):
            if k % 2:
                continue
            a, b = V((0, *dash[k])), V((0, *dash[k + 1]))
            t = (b - a).normalized()
            nrm = V((0, -t.z, t.y))
            c = (a + b) / 2 - nrm * 0.0135
            w = 0.006
            quad = [c - t * w / 2 - nrm * 0.0045, c + t * w / 2 - nrm * 0.0045, c + t * w / 2 + nrm * 0.0045 + t * 0.003,
                    c - t * w / 2 + nrm * 0.0045 + t * 0.003]
            vs = [bm.verts.new((s * 0.0216, q.y, q.z)) for q in quad]
            bm.faces.new(vs if s > 0 else list(reversed(vs)))
        lib.bm_to_obj(bmname, bm, 'decal_yellow', 'chassis', smooth=False)

    # seat tube through the end of the arch, black clamp, seatpost
    sdir = (SEAT_B[0] - SEAT_A[0], SEAT_B[1] - SEAT_A[1])
    sl = math.hypot(*sdir)
    sdir = (sdir[0] / sl, sdir[1] / sl)
    lib.cylinder('frame_seattube', 0.0205, 0, 'paint_black', 'chassis', start=P(0, SEAT_A), end=P(0, SEAT_B), verts=32,
                 bevel=0.002)
    lib.cylinder('seat_collar', 0.0235, 0, 'plastic_gloss', 'chassis',
                 start=P(0, add(SEAT_B, sdir, -0.028)), end=P(0, add(SEAT_B, sdir, 0.003)), verts=32, bevel=0.002)
    m = tube_matrix(P(0, SEAT_A), P(0, SEAT_B), P(0.026, add(SEAT_B, sdir, -0.013)))
    lib.box('seat_qr_lever', (0.007, 0.062, 0.013), 'plastic_gloss', 'chassis',
            matrix=m @ Matrix.Translation(V((0, -0.022, 0))), bevel=0.003)
    sp_top = add(SEAT_B, sdir, 0.095)
    lib.cylinder('seatpost', 0.0158, 0, 'alloy_black', 'chassis', start=P(0, add(SEAT_B, sdir, -0.05)),
                 end=P(0, sp_top), verts=32)

    # yellow lower housing behind and under the crank, black stripes on its sides
    hous = lib.spline([(-0.040, 0.360), (-0.036, 0.290), (-0.080, 0.232), (-0.130, 0.206), (-0.178, 0.196),
                       (-0.226, 0.226), (-0.262, 0.272), (-0.258, 0.316), (-0.215, 0.338), (-0.130, 0.372),
                       (-0.070, 0.382)], 5)
    lib.plate('frame_lower_housing', hous[:-1], -0.034, 0.034, 'paint_yellow', 'chassis', bevel=0.007)
    for s in (1, -1):
        lib.stripes('decal_housing_stripes%+d' % s, P(0, (-0.205, 0.272)), P(0, (-0.085, 0.272)), 0.0342, 0.085, 6,
                    0.011, -30, 'decal_black', 'chassis', sides=(s,))

    # decals on the main tube: stripe block, logo with emblem, long run of thin stripes, "X4" on the down post
    lib.stripes('decal_stripes_head', P(0, MT_A), P(0, HT_MID), 0.0285, 0.06, 5, 0.008, 28, 'decal_yellow',
                'chassis', start=0.80, end=0.93)
    lib.stripes('decal_stripes_row', P(0, MT_A), P(0, HT_MID), 0.0285, 0.05, 14, 0.0065, 28, 'decal_yellow',
                'chassis', start=0.10, end=0.42, shift=-0.004)
    d = (HT_MID[0] - MT_A[0], HT_MID[1] - MT_A[1])
    dl = math.hypot(*d)
    d = (d[0] / dl, d[1] / dl)
    for s in (1, -1):
        rd = d if s > 0 else (-d[0], -d[1])
        lib.logo('decal_logo_frame%+d' % s, along(MT_A, HT_MID, 0.62), rd, s, 0.0284, 0.034, 'decal_yellow', 'chassis')
        lib.text('decal_x4%+d' % s, 'X4', 0.042, 'decal_yellow', 'chassis',
                 lib.side_matrix((0.006, 0.535), (0.25, 0.97) if s > 0 else (-0.25, -0.97), s, 0.0262),
                 font_path=lib.FONT_SANS)
        lib.stripes('decal_downpost_stripes%+d' % s, P(0, (0.022, 0.50)), P(0, (-0.01, 0.40)), 0.0262, 0.012, 9, 0.004,
                    0, 'decal_yellow', 'chassis', sides=(s,), shift=0.018)
    return sp_top


def saddle(sp_top):
    import bmesh
    right = [(0.034, 0.135), (0.045, 0.085), (0.062, 0.035), (0.092, -0.015), (0.108, -0.055),
             (0.112, -0.085), (0.095, -0.112), (0.05, -0.122)]
    outline = right + [(-x, y) for x, y in reversed(right)]
    bm = bmesh.new()
    cy, cz = sp_top[0] - 0.012, sp_top[1] + 0.045
    top = [bm.verts.new((x, cy + y, cz + 0.022 + 0.012 * (y < -0.05))) for x, y in outline]
    bot = [bm.verts.new((x * 0.92, cy + y * 0.95, cz - 0.03)) for x, y in outline]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(top)
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new((top[k], bot[k], bot[j], top[j]))
    ob = lib.bm_to_obj('saddle', bm, 'leather', 'chassis')
    lib.add_bevel(ob, 0.018, 3, 25.0)
    lib.add_subsurf(ob, 2)
    lib.box('saddle_base', (0.15, 0.2, 0.012), 'plastic_black', 'chassis', loc=(0, cy - 0.01, cz - 0.035), bevel=0.004)
    for s in (1, -1):
        lib.pipe('saddle_rail%+d' % s, [V((s * 0.022, cy + 0.08, cz - 0.035)), V((s * 0.022, cy + 0.05, cz - 0.05)),
                                        V((s * 0.022, cy - 0.06, cz - 0.05)), V((s * 0.025, cy - 0.09, cz - 0.035))],
                 0.0035, 'steel', 'chassis', fillet_r=0.01, verts=10)
    lib.box('saddle_clamp', (0.06, 0.045, 0.025), 'alloy_black', 'chassis', loc=(0, cy - 0.005, cz - 0.058), bevel=0.004)


BAT_A, BAT_B = (-0.200, 0.318), (-0.408, 0.762)     # battery axis, bottom -> top
BAT_DEPTH, BAT_W = 0.112, 0.092


def battery():
    a3, b3 = P(0, BAT_A), P(0, BAT_B)
    axis = (b3 - a3).normalized()
    length = (b3 - a3).length
    m = tube_matrix(a3, b3, (a3 + b3) / 2 - axis * 0.02)
    lib.box('battery', (BAT_W, BAT_DEPTH, length - 0.04), 'paint_black', 'swingarm', matrix=m, bevel=0.012)
    # top cap: grey-black plastic, sloped, with the key switch and the LED charge indicator
    capm = tube_matrix(a3, b3, b3 - axis * 0.026)
    lib.box('battery_cap', (BAT_W + 0.004, BAT_DEPTH + 0.006, 0.052), 'plastic_gloss', 'swingarm', matrix=capm, bevel=0.012)
    lib.box('battery_cap_top', (BAT_W - 0.006, BAT_DEPTH - 0.008, 0.012), 'plastic_black', 'swingarm',
            matrix=capm @ Matrix.Translation(V((0, 0, 0.027))), bevel=0.004)
    back = V((0, -axis.z, axis.y))          # towards the rear of the bike, perpendicular to the axis
    if back.y > 0:
        back = -back
    top = b3 + axis * 0.0015
    for k, (mat, off) in enumerate((('led_green', 0.0), ('lens_red', 0.011), ('lens_white', 0.022))):
        p = top + back * (0.018 + off) + V((0.012, 0, 0))
        lib.cylinder('battery_led%d' % k, 0.0042, 0, mat, 'swingarm', start=p, end=p + axis * 0.002, verts=16)
    p = top + back * 0.03 + V((-0.018, 0, 0))
    lib.cylinder('battery_key', 0.009, 0, 'steel_dark', 'swingarm', start=p - axis * 0.002, end=p + axis * 0.004, verts=20)
    lib.box('battery_base', (BAT_W + 0.004, BAT_DEPTH + 0.004, 0.03), 'plastic_black', 'swingarm',
            matrix=tube_matrix(a3, b3, a3 + axis * 0.0), bevel=0.006)
    lib.stripes('decal_battery_stripes', a3, b3, BAT_W / 2, BAT_DEPTH * 0.55, 15, 0.0085, -50, 'decal_yellow', 'swingarm',
                start=0.47, end=0.89, shift=BAT_DEPTH * 0.19)
    lib.stripes('decal_battery_stripes_low', a3, b3, BAT_W / 2, BAT_DEPTH * 0.45, 5, 0.0055, -50, 'decal_yellow',
                'swingarm', start=0.07, end=0.15, shift=BAT_DEPTH * 0.22)
    d = (BAT_B[0] - BAT_A[0], BAT_B[1] - BAT_A[1])
    dl = math.hypot(*d)
    d = (-d[0] / dl, -d[1] / dl)          # the script reads downwards along the battery
    for s in (1, -1):
        rd = d if s > 0 else (-d[0], -d[1])
        lib.logo('decal_logo_battery%+d' % s, along(BAT_A, BAT_B, 0.31), rd, s, BAT_W / 2 + 0.0005, 0.036,
                 'decal_yellow', 'swingarm')


SEATSTAY = [(-0.630, 0.372), (-0.560, 0.468), (-0.500, 0.530), (-0.430, 0.570), (-0.380, 0.578), (-0.300, 0.565),
            (-0.220, 0.540), (-0.165, 0.524)]


SEATSTAY_X = (0.100, 0.096, 0.090, 0.082, 0.076, 0.068, 0.060, 0.052)
CHAINSTAY3 = [(0.098, RA[0] + 0.012, RA[1] - 0.004), (0.084, -0.45, 0.318), (0.077, -0.30, 0.307),
              (0.072, PV[0] - 0.012, PV[1])]


def path_dashes(name, path, side, hw, count, width, height, slant_deg, mat, bone, shift=0.0, start=0.0, end=1.0):
    """Slanted decal dashes on the outer side face of a swept member that follows a curved 3D path."""
    import bmesh
    path = [V(p) for p in path]
    cum = [0.0]
    for a, b in zip(path, path[1:]):
        cum.append(cum[-1] + (b - a).length)
    total = cum[-1]
    bm = bmesh.new()
    k_slant = math.tan(math.radians(slant_deg)) * height
    for i in range(count):
        u = (start + (end - start) * (i + 0.5) / count) * total
        j = max(1, min(len(path) - 1, next((q for q, c in enumerate(cum) if c >= u), len(path) - 1)))
        f = (u - cum[j - 1]) / max(cum[j] - cum[j - 1], 1e-9)
        p = path[j - 1].lerp(path[j], f)
        t = (path[j] - path[j - 1]).normalized()
        t = V((0, t.y, t.z)).normalized()
        nrm = V((0, -t.z, t.y))
        if nrm.z < 0:
            nrm = -nrm
        c = V((p.x + side * (hw + 0.0006), p.y, p.z)) + nrm * shift
        h = height / 2
        quad = [c - t * (width / 2 + k_slant / 2) - nrm * h, c + t * (width / 2 - k_slant / 2) - nrm * h,
                c + t * (width / 2 + k_slant / 2) + nrm * h, c - t * (width / 2 - k_slant / 2) + nrm * h]
        vs = [bm.verts.new(q) for q in quad]
        bm.faces.new(vs if side > 0 else list(reversed(vs)))
    return lib.bm_to_obj(name, bm, mat, bone, smooth=False)


def swingarm():
    for s in (1, -1):
        cs = [V((s * x, y, z)) for x, y, z in lib.spline(CHAINSTAY3, 8)]
        lib.sweep('swingarm_chainstay%+d' % s, lib.resample(cs, 0.01),
                  lambda u: lib.rrect_profile(0.022, 0.034, 0.009), 'paint_yellow', 'swingarm')
        ss = [V((s * x, y, z)) for x, y, z in lib.spline([(x, y, z) for x, (y, z) in zip(SEATSTAY_X, SEATSTAY)], 6)]
        lib.sweep('swingarm_seatstay%+d' % s, lib.resample(ss, 0.01),
                  lambda u: lib.rrect_profile(0.021, 0.032, 0.009), 'paint_yellow', 'swingarm')
        # black dashes along the upper edge of the seat stay
        path_dashes('decal_stay_dashes%+d' % s, ss, s, 0.0105, 24, 0.0055, 0.010, 32, 'decal_black', 'swingarm',
                    shift=0.0085, start=0.30, end=0.97)
        # dropout plate with the axle slot
        lib.plate('dropout%+d' % s, [(RA[0] - 0.026, RA[1] - 0.018), (RA[0] + 0.03, RA[1] - 0.026),
                                     (RA[0] + 0.045, RA[1] + 0.03), (RA[0] + 0.012, RA[1] + 0.06),
                                     (RA[0] - 0.022, RA[1] + 0.03)],
                  s * 0.091, s * 0.104, 'paint_yellow', 'swingarm', bevel=0.003)
        # shock bracket plates with the silver bolt
        lib.plate('shock_bracket%+d' % s, [(SN[0] - 0.026, SN[1] - 0.022), (SN[0] + 0.02, SN[1] - 0.02),
                                           (SN[0] + 0.022, SN[1] + 0.018), (SN[0] - 0.012, SN[1] + 0.024),
                                           (SN[0] - 0.04, SN[1] + 0.002)],
                  s * 0.040, s * 0.056, 'paint_yellow', 'swingarm', bevel=0.004)
        lib.cylinder('shock_bolt%+d' % s, 0.0068, 0, 'steel', 'swingarm', start=P(s * 0.056, SN), end=P(s * 0.062, SN),
                     verts=6)
    lib.cylinder('pivot_housing', 0.02, 0, 'paint_yellow', 'swingarm', start=P(-0.072, PV), end=P(0.072, PV), verts=32,
                 bevel=0.003)
    for s in (1, -1):
        lib.cylinder('pivot_bolt%+d' % s, 0.009, 0, 'steel', 'swingarm', start=P(s * 0.072, PV), end=P(s * 0.078, PV),
                     verts=6)
    lib.cylinder('upper_bridge', 0.011, 0, 'paint_yellow', 'swingarm', start=P(-0.05, SN), end=P(0.05, SN), verts=24)
    # black link box between the shock bracket and the pivot, in front of the battery (controller), white label
    a3, b3 = P(0, (-0.205, 0.335)), P(0, (-0.152, 0.505))
    lm = tube_matrix(a3, b3, (a3 + b3) / 2)
    lib.box('controller', (0.056, 0.042, (b3 - a3).length), 'plastic_black', 'swingarm', matrix=lm, bevel=0.005)
    lib.box('controller_label', (0.001, 0.026, 0.05), 'decal_white', 'swingarm',
            matrix=lm @ Matrix.Translation(V((0.0285, 0.0, 0.035))))
    lib.cylinder('chainstay_bridge', 0.012, 0, 'paint_yellow', 'swingarm', start=P(-0.08, (-0.40, 0.311)),
                 end=P(0.08, (-0.40, 0.311)), verts=20)
    # onebike.co.il on the right chainstay, black on yellow, followed by a short block of slanted stripes
    cs = lib.spline(CHAINSTAY3, 8)
    near = lambda yy: min(cs, key=lambda p: abs(p.y - yy))
    a, b = near(-0.40), near(-0.32)
    xa = V((0, b.y - a.y, b.z - a.z)).normalized()
    za = V((1, 0, 0))
    ya = za.cross(xa).normalized()
    c = (a + b) / 2
    c.x += 0.0116
    lib.text('decal_url', 'onebike.co.il', 0.0148, 'decal_black', 'swingarm', lib.basis(xa, ya, za, c),
             font_path=lib.FONT_SANS)
    seg = [p for p in cs if -0.31 <= p.y <= -0.255]
    if len(seg) >= 2:
        path_dashes('decal_chainstay_stripes', seg, 1, 0.011, 5, 0.0045, 0.017, -30, 'decal_black', 'swingarm')


def shock():
    """Coil-over: black body and eye at the arch (FM), yellow spring down to the swingarm bracket (SN)."""
    a, b = P(0, FM), P(0, SN)
    d = (b - a)
    L = d.length
    u = d.normalized()
    lib.cylinder('shock_body', 0.0155, 0, 'alloy_black', 'chassis', start=a + u * 0.010, end=a + u * (0.46 * L), verts=32,
                 bevel=0.002)
    lib.cylinder('shock_body_cap', 0.0175, 0, 'alloy_black', 'chassis', start=a + u * 0.012, end=a + u * 0.032, verts=32,
                 bevel=0.002)
    lib.cylinder('shock_shaft', 0.0072, 0, 'steel', 'chassis', start=a + u * (0.40 * L), end=b - u * 0.012, verts=20)
    lib.cylinder('shock_bumper', 0.011, 0, 'rubber', 'chassis', start=a + u * (0.46 * L), end=a + u * (0.52 * L), verts=20)
    for p in (a, b):
        lib.cylinder('shock_eye', 0.0105, 0, 'steel_dark', 'chassis', start=p - V((0.013, 0, 0)), end=p + V((0.013, 0, 0)),
                     verts=20)
    lib.cylinder('shock_upper_bolt', 0.0062, 0, 'steel', 'chassis', start=a + V((0.018, 0, 0)), end=a + V((0.026, 0, 0)),
                 verts=6)
    s0, s1 = a + u * 0.036, b - u * 0.014
    lib.cylinder('spring_seat_a', 0.0285, 0, 'alloy_black', 'chassis', start=s0 - u * 0.006, end=s0, verts=32)
    lib.cylinder('spring_preload', 0.022, 0, 'alloy_black', 'chassis', start=s0 - u * 0.012, end=s0 - u * 0.006, verts=24)
    lib.cylinder('spring_seat_b', 0.027, 0, 'alloy_black', 'chassis', start=s1, end=s1 + u * 0.006, verts=32)
    m = lib.frame_from_z(u, (0, 0, 0))
    xa, ya = V(m.col[0][:3]), V(m.col[1][:3])
    coils, steps = 7.5, 7 * 28
    pts = []
    for k in range(steps + 1):
        t = k / steps
        ang = 2 * math.pi * coils * t
        pts.append(s0.lerp(s1, t) + (xa * math.cos(ang) + ya * math.sin(ang)) * 0.0215)
    lib.pipe('shock_spring', pts, 0.0048, 'paint_yellow', 'chassis', verts=10)


def fender(name, c, r, a0, a1, bone, hw=0.07):
    pts = []
    steps = lib.n(64, 12)
    for k in range(steps):
        a = math.radians(a0 + (a1 - a0) * k / (steps - 1))
        pts.append(P(0, (c[0] + r * math.cos(a), c[1] + r * math.sin(a))))
    sag, th = 0.022, 0.0035
    half = lib.n(8, 2)
    outer = [(hw * (k / half - 1), sag * (1 - (k / half - 1) ** 2)) for k in range(2 * half + 1)]
    prof = outer + [(a, b - th) for a, b in reversed(outer)]
    return lib.sweep(name, pts, lambda u: prof, 'plastic_gloss', bone, weighted=False)


RACK_X = 0.098
CUSHION = (-0.860, -0.494, 0.708, 0.758, 0.176)       # rear y, front y, base z, top z, width


def rack():
    """Yellow rack: on each side a top rail with a rounded rear loop that runs back down to the seat stay,
    an inner U-strut, and a front leg into the seat stay apex; cross tubes; quilted passenger cushion."""
    y = 'paint_yellow'
    r = 0.0105
    for s in (1, -1):
        x = s * RACK_X
        side = [V((s * 0.078, -0.392, 0.582)), V((s * 0.088, -0.432, 0.640)), V((x, -0.468, 0.700)),
                V((x, -0.500, RACK_Z)), V((x, -0.858, RACK_Z)), V((x, -0.882, 0.680)), V((x, -0.880, 0.628)),
                V((x, -0.862, 0.608)), V((s * 0.095, -0.700, 0.551)), V((s * 0.093, -0.536, 0.495))]
        lib.pipe('rack_side%+d' % s, side, r, y, 'swingarm', fillet_r=0.028, verts=18, step=0.008)
        inner = [V((x, -0.738, RACK_Z)), V((x, -0.730, 0.650)), V((s * 0.097, -0.700, 0.622)),
                 V((s * 0.092, -0.515, 0.514))]
        lib.pipe('rack_inner%+d' % s, inner, 0.0098, y, 'swingarm', fillet_r=0.03, verts=18, step=0.008)
        # rack mount plate on the seat stay, with a hole
        hole = [(-0.528 + 0.0065 * math.cos(a), 0.476 + 0.0065 * math.sin(a)) for a in
                (2 * math.pi * k / 16 for k in range(16))]
        lib.plate('rack_mount%+d' % s, [(-0.55, 0.47), (-0.51, 0.468), (-0.50, 0.51), (-0.525, 0.53), (-0.548, 0.505)],
                  s * 0.086, s * 0.094, y, 'swingarm', holes=[hole], bevel=0.002)
    for yy, zz, rr in ((-0.882, 0.652, 0.0095), (-0.80, RACK_Z, 0.008), (-0.56, RACK_Z, 0.008), (-0.47, 0.70, 0.009)):
        lib.cylinder('rack_cross', rr, 0, y, 'swingarm', start=V((-RACK_X, yy, zz)), end=V((RACK_X, yy, zz)), verts=16)
    cushion()
    lib.box('taillight_body', (0.072, 0.026, 0.032), 'plastic_gloss', 'swingarm', loc=(0, -0.872, 0.668), bevel=0.007)
    lib.box('taillight_lens', (0.060, 0.004, 0.021), 'lens_red', 'swingarm', loc=(0, -0.8855, 0.668), bevel=0.0015)


def cushion():
    """Passenger cushion: rounded block, top quilted in shallow transverse channels, piping round the top edge."""
    import bmesh
    y0, y1, zb, zt, w = CUSHION
    half = V((w / 2, (y1 - y0) / 2, (zt - zb) / 2))
    ctr = V((0, (y0 + y1) / 2, (zb + zt) / 2))
    rad = 0.018
    inner = half - V((rad, rad, rad))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=lib.n(30, 4), use_grid_fill=True)
    pitch = (y1 - y0) / 11
    for v in bm.verts:
        p = V((v.co.x * half.x, v.co.y * half.y, v.co.z * half.z))
        q = V((max(-inner.x, min(inner.x, p.x)), max(-inner.y, min(inner.y, p.y)), max(-inner.z, min(inner.z, p.z))))
        nd = (p - q)
        nd = nd.normalized() if nd.length > 1e-9 else V((0, 0, 1))
        out = q + nd * rad
        if nd.z > 0.3 and lib.DETAIL >= 0.5:
            ph = (p.y + half.y) / pitch
            groove = 0.0045 * (1 - abs(math.cos(math.pi * ph))) ** 6
            edge = max(0.0, 1 - abs(p.x) / half.x)
            out.z += 0.004 * min(1.0, edge * 4) - groove * min(1.0, edge * 3)
        v.co = ctr + out
    ob = lib.bm_to_obj('cushion', bm, 'leather', 'swingarm')
    lib.add_subsurf(ob, 1)
    lib.box('cushion_base', (w - 0.03, y1 - y0 - 0.03, 0.012), 'plastic_black', 'swingarm',
            loc=(0, (y0 + y1) / 2, zb + 0.002), bevel=0.003)
    edge = [V((sx * (half.x - 0.003), yy, zt - 0.006)) for sx, yy in
            [(1, y0 + 0.03), (1, y1 - 0.03), (-1, y1 - 0.03), (-1, y0 + 0.03), (1, y0 + 0.03)]]
    lib.pipe('cushion_piping', edge, 0.0028, 'piping', 'swingarm', fillet_r=0.02, verts=8, step=0.01)
    for s in (1, -1):
        lib.logo('decal_logo_cushion%+d' % s, (-0.665, (zb + zt) / 2 + 0.002), (1.0, 0.0) if s > 0 else (-1.0, 0.0), s,
                 half.x + 0.0006, 0.021, 'decal_yellow', 'swingarm')


# ------------------------------------------------------------- front end

def fork():
    legs_top, axis_at, cc, hl = _front_geometry()
    for s in (1, -1):
        x = s * 0.092
        lib.cylinder('fork_lower%+d' % s, 0.023, 0, 'alloy_black', 'forks_l', start=P(x, add(FA, UP, -0.02)),
                     end=P(x, add(FA, UP, 0.24)), verts=32, bevel=0.003)
        lib.cylinder('fork_stanchion%+d' % s, 0.0165, 0, 'paint_black', 'forks_u', start=P(x, add(FA, UP, 0.16)),
                     end=P(x, add(legs_top, UP, 0.01)), verts=32)
        lib.cylinder('fork_seal%+d' % s, 0.0195, 0, 'rubber', 'forks_l', start=P(x, add(FA, UP, 0.232)),
                     end=P(x, add(FA, UP, 0.246)), verts=32)
        for t, mat in ((0.10, 'decal_yellow'), (0.116, 'lens_red'), (0.132, 'decal_yellow'), (0.148, 'decal_white')):
            lib.cylinder('fork_band%+d' % s, 0.0236, 0, mat if mat != 'lens_red' else 'decal_red', 'forks_l',
                         start=P(x, add(FA, UP, t)), end=P(x, add(FA, UP, t + 0.011)), verts=32)
        lib.box('fork_dropout%+d' % s, (0.016, 0.04, 0.05), 'alloy_black', 'forks_l',
                matrix=tube_matrix(P(0, FA), P(0, add(FA, UP, 1)), P(x, add(FA, UP, 0.0))), bevel=0.005)
    # yellow ladder brackets from the fork legs back to the fender
    for s in (1, -1):
        a = P(s * 0.075, add(FA, UP, 0.135))
        phi = math.radians(165)
        b = P(s * 0.069, (FA[0] + 0.367 * math.cos(phi), FA[1] + 0.367 * math.sin(phi) + 0.01))
        t3 = (b - a).normalized()
        up3 = t3.cross(V((1, 0, 0))).normalized() * -1
        if up3.z < 0:
            up3 = -up3
        length = (b - a).length
        frame_m = lib.basis(V((1, 0, 0)), t3, up3, (a + b) / 2)
        for dz in (-0.019, 0.019):
            lib.box('fender_bracket_bar%+d' % s, (0.005, length, 0.008), 'paint_yellow', 'forks_l',
                    matrix=frame_m @ Matrix.Translation(V((0, 0, dz))), bevel=0.0015)
        for k in range(5):
            yy = -length / 2 + 0.006 + k * (length - 0.012) / 4
            lib.box('fender_bracket_rung%+d' % s, (0.005, 0.009, 0.046), 'paint_yellow', 'forks_l',
                    matrix=frame_m @ Matrix.Translation(V((0, yy, 0))), bevel=0.0015)
    # crown (yellow)
    lib.box('fork_crown', (0.215, 0.085, 0.036), 'paint_yellow', 'forks_u',
            matrix=tube_matrix(P(0, FA), P(0, add(FA, UP, 1)), P(0, cc)), bevel=0.008)
    lib.cylinder('steerer', 0.0145, 0, 'steel_dark', 'forks_u', start=P(0, axis_at), end=P(0, add(HT_TOP, UP, 0.03)),
                 verts=24)
    lib.cylinder('top_cap', 0.034, 0, 'paint_yellow', 'forks_u', start=P(0, add(HT_TOP, UP, 0.004)),
                 end=P(0, add(HT_TOP, UP, 0.03)), verts=40, bevel=0.003)
    # headlight on the crown
    lib.box('headlight_bracket', (0.02, 0.05, 0.01), 'alloy_black', 'forks_u', loc=(0, hl[0] - 0.03, hl[1] - 0.012))
    lib.cylinder('headlight_body', 0.024, 0, 'plastic_gloss', 'forks_u', start=P(0, add(hl, (1, 0), -0.03)),
                 end=P(0, add(hl, (1, 0), 0.015)), verts=32, bevel=0.004)
    lib.cylinder('headlight_lens', 0.0195, 0, 'lens_white', 'forks_u', start=P(0, add(hl, (1, 0), 0.015)),
                 end=P(0, add(hl, (1, 0), 0.0175)), verts=32)
    fender('fender_front', FA, 0.367, 58, 192, 'forks_l', hw=0.063)
    return hl


def cockpit():
    sdir = (STEM_TOP[0] - HT_TOP[0], STEM_TOP[1] - HT_TOP[1])
    sl = math.hypot(*sdir)
    sdir = (sdir[0] / sl, sdir[1] / sl)
    lib.cylinder('stem', 0.021, 0, 'paint_black', 'forks_u', start=P(0, add(HT_TOP, sdir, 0.02)), end=P(0, STEM_TOP), verts=32)
    fc = add(HT_TOP, sdir, 0.075)
    lib.cylinder('stem_fold_clamp', 0.0268, 0, 'paint_yellow', 'forks_u', start=P(0, add(fc, sdir, -0.024)),
                 end=P(0, add(fc, sdir, 0.024)), verts=32, bevel=0.003)
    lib.box('stem_fold_lever', (0.012, 0.016, 0.085), 'plastic_gloss', 'forks_u',
            matrix=tube_matrix(P(0, HT_TOP), P(0, STEM_TOP), P(-0.03, add(fc, sdir, 0.02))), bevel=0.004)
    lib.text('decal_logo_stem', 'One Bike', 0.022, 'decal_yellow', 'forks_u',
             lib.side_matrix(add(HT_TOP, sdir, 0.11), sdir, 1, 0.0213))
    lib.cylinder('bar_clamp', 0.023, 0, 'alloy_black', 'forks_u', start=V((-0.04, STEM_TOP[0] - 0.002, STEM_TOP[1] + 0.017)),
                 end=V((0.04, STEM_TOP[0] - 0.002, STEM_TOP[1] + 0.017)), verts=32, bevel=0.003)
    zc = STEM_TOP[1] + 0.017
    yc = STEM_TOP[0] - 0.002
    bar = [V((-0.335, yc - 0.083, zc + 0.045)), V((-0.20, yc - 0.078, zc + 0.045)), V((-0.12, yc - 0.045, zc + 0.025)),
           V((-0.06, yc, zc)), V((0.06, yc, zc)), V((0.12, yc - 0.045, zc + 0.025)), V((0.20, yc - 0.078, zc + 0.045)),
           V((0.335, yc - 0.083, zc + 0.045))]
    lib.pipe('handlebar', bar, 0.0112, 'alloy_black', 'forks_u', fillet_r=0.05, verts=20, step=0.01)
    bar_path = lib.resample(lib.fillet(bar, 0.05), 0.005)
    for s in (1, -1):
        seg = [p for p in bar_path if 0.042 <= s * p.x <= 0.17]
        if s < 0:
            seg.reverse()
        lib.pipe('bar_sleeve%+d' % s, seg, 0.0127, 'paint_yellow', 'forks_u', verts=20)
        g0, g1 = V((s * 0.205, yc - 0.0785, zc + 0.045)), V((s * 0.335, yc - 0.083, zc + 0.045))
        lib.cylinder('grip%+d' % s, 0.0168, 0, 'rubber', 'forks_u', start=g0, end=g1, verts=32, bevel=0.003)
        lib.cylinder('grip_end%+d' % s, 0.0178, 0, 'paint_yellow', 'forks_u', start=g1, end=g1 + V((s * 0.012, 0, 0)),
                     verts=32, bevel=0.003)
        lib.cylinder('lever_perch%+d' % s, 0.016, 0, 'alloy_black', 'forks_u', start=V((s * 0.183, yc - 0.075, zc + 0.044)),
                     end=V((s * 0.201, yc - 0.077, zc + 0.044)), verts=24)
        lib.box('lever_body%+d' % s, (0.03, 0.04, 0.026), 'alloy_black', 'forks_u',
                loc=(s * 0.195, yc - 0.062, zc + 0.05), bevel=0.006)
        lib.pipe('lever%+d' % s, [V((s * 0.20, yc - 0.05, zc + 0.04)), V((s * 0.215, yc - 0.035, zc + 0.034)),
                                  V((s * 0.315, yc - 0.04, zc + 0.024))], 0.0055, 'alloy_black', 'forks_u',
                 fillet_r=0.015, verts=12)
    lib.box('throttle', (0.026, 0.03, 0.034), 'plastic_gloss', 'forks_u', loc=(0.168, yc - 0.075, zc + 0.05), bevel=0.006)
    # handlebar remote (left thumb): +, -, M buttons facing the rider
    rc = V((-0.158, yc - 0.064, zc + 0.05))
    rn = V((0, -0.62, 0.785)).normalized()
    rm = lib.basis(V((1, 0, 0)), rn.cross(V((1, 0, 0))), rn, rc)
    lib.box('remote_body', (0.042, 0.034, 0.03), 'plastic_gloss', 'forks_u', matrix=rm, bevel=0.007)
    for k, (dx, dy, label) in enumerate(((-0.011, 0.007, '+'), (-0.011, -0.008, '\u2013'), (0.011, 0.0, 'M'))):
        bpos = rc + rn * 0.0155 + V((dx, 0, 0)) + rn.cross(V((1, 0, 0))) * dy
        lib.cylinder('remote_button%d' % k, 0.0055, 0.004, 'button_rubber', 'forks_u',
                     matrix=lib.frame_from_z(rn, bpos), verts=20, bevel=0.0012)
        lib.text('remote_label%d' % k, label, 0.008, 'decal_white', 'forks_u',
                 lib.basis(V((1, 0, 0)), rn.cross(V((1, 0, 0))), rn, bpos + rn * 0.0028), font_path=lib.FONT_SANS)

    # round colour TFT display, tilted toward the rider
    n_ = V((0, -0.5, 0.866))
    u_ = V((1, 0, 0))
    v_ = n_.cross(u_)
    dc = V((0, yc - 0.024, zc + 0.054))
    lib.cylinder('display_housing', 0.047, 0.026, 'plastic_gloss', 'forks_u', matrix=lib.frame_from_z(n_, dc), verts=64,
                 bevel=0.006)
    lib.cylinder('display_bezel', 0.0455, 0.003, 'alloy_black', 'forks_u', matrix=lib.frame_from_z(n_, dc + n_ * 0.0135),
                 verts=64, bevel=0.0012)
    lib.disc_uv('display_screen', dc + n_ * 0.0152, u_, v_, 0.0392, 'screen_display', 'forks_u')
    lib.cylinder('display_cable_boot', 0.009, 0.02, 'rubber', 'forks_u',
                 matrix=lib.frame_from_z(-v_, dc - v_ * 0.05 - n_ * 0.004), verts=20, bevel=0.002)
    lib.box('display_mount', (0.022, 0.035, 0.03), 'plastic_black', 'forks_u', loc=(0, yc - 0.008, zc + 0.022), bevel=0.004)
    lib.box('display_arm', (0.016, 0.012, 0.03), 'plastic_black', 'forks_u',
            matrix=lib.basis(u_, n_, -v_, dc - n_ * 0.018 - v_ * 0.005), bevel=0.003)

    # phone holder on the right
    lib.cylinder('phone_clamp', 0.016, 0, 'plastic_black', 'forks_u', start=V((0.085, yc - 0.012, zc + 0.006)),
                 end=V((0.11, yc - 0.017, zc + 0.008)), verts=24)
    lib.box('phone_arm', (0.014, 0.014, 0.035), 'plastic_black', 'forks_u', loc=(0.098, yc - 0.018, zc + 0.03), bevel=0.003)
    m = Matrix.Rotation(math.radians(-22), 4, 'X')
    m.translation = V((0.098, yc - 0.03, zc + 0.095))
    lib.box('phone_cradle', (0.085, 0.012, 0.11), 'plastic_black', 'forks_u', matrix=m, bevel=0.004)
    for s in (1, -1):
        mm = m @ Matrix.Translation(V((s * 0.047, 0.008, 0)))
        lib.box('phone_jaw%+d' % s, (0.008, 0.02, 0.04), 'plastic_black', 'forks_u', matrix=mm, bevel=0.002)

    # front bag strapped to the stem
    tilt = math.atan2(-sdir[0], sdir[1])
    bz = HT_TOP[1] + 0.172
    t = (bz - HT_TOP[1]) / sdir[1]
    bc = (HT_TOP[0] + sdir[0] * t + 0.106, bz)
    m = rot_x(tilt, P(0, bc))
    soft_bag(m, 0.29, 0.16, 0.33, yc, zc)
    return yc, zc


def soft_bag(m, w, d, h, yc, zc):
    """Soft fabric handlebar bag: rounded, bulging panels, sagging bottom, wrinkles,
    piping on the seams, a zip around the lid, mesh side pockets and velcro straps.
    `m` is the bag frame: local X across the bike, Y forward, Z up along the stem."""
    import bmesh
    from mathutils import noise

    half = V((w / 2, d / 2, h / 2))
    r = 0.024
    inner = half - V((r, r, r))

    def rounded(p):
        q = V((max(-inner.x, min(inner.x, p.x)), max(-inner.y, min(inner.y, p.y)), max(-inner.z, min(inner.z, p.z))))
        nd = p - q
        nd = nd.normalized() if nd.length > 1e-9 else V((0, 1, 0))
        return q + nd * r, nd

    def soften(p, nd):
        u, t, s_ = (max(-1.0, min(1.0, p[i] / half[i])) for i in range(3))
        out = p.copy()
        load = 1.0 + 0.06 * max(0.0, -s_)                                    # contents settle to the bottom
        out.x *= load
        out.y += (1 if p.y > 0 else -0.4) * 0.019 * (1 - u * u) * (1 - s_ * s_) * abs(nd.y) * load
        out.x += (1 if p.x > 0 else -1) * 0.012 * (1 - t * t) * (1 - s_ * s_) * abs(nd.x)
        out.z -= 0.009 * (1 - u * u) * (1 - t * t) * max(0.0, nd.z)          # lid dips between the zip
        out.z -= 0.007 * (1 - u * u) * (1 - t * t) * max(0.0, -nd.z)         # bottom sags
        lower = 0.55 + 0.45 * max(0.0, -s_)
        wr = (noise.noise(V((p.x * 20, p.y * 20, p.z * 70))) * 0.0032 +
              noise.noise(V((p.x * 8 + 3, p.y * 8, p.z * 10))) * 0.0026) * lower
        corner = max(0.0, abs(u) * abs(s_) - 0.55) / 0.45                       # creases toward the corners
        wr += noise.noise(V((p.x * 40 + p.z * 40, p.y * 30, p.z * 40 - p.x * 40))) * 0.004 * corner
        if lib.DETAIL >= 0.5:
            out += nd * wr
        return out

    # body
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=lib.n(18, 3), use_grid_fill=True)
    for v in bm.verts:
        p0, nd = rounded(V((v.co.x * half.x, v.co.y * half.y, v.co.z * half.z)))
        v.co = m @ soften(p0, nd)
    body = lib.bm_to_obj('bag', bm, 'fabric', 'forks_u')
    lib.add_subsurf(body, 1)

    def seam(points_local, name, radius, mat, closed=True):
        pts = []
        for p in points_local:
            p0, nd = rounded(p)
            pts.append(m @ (soften(p0, nd) + nd * radius * 0.6))
        if closed:
            pts.append(pts[0])
        lib.pipe(name, pts, radius, mat, 'forks_u', verts=8, caps=not closed)

    def ring(axis_val, axis, steps):
        """Points around the panel boundary facing +/-axis ('y' front/back or 'x' sides)."""
        pts = []
        for k in range(steps):
            a = 2 * math.pi * k / steps
            c, sn = math.cos(a), math.sin(a)
            if axis == 'y':
                e = V((c, 0, sn))
                p = V((inner.x * (1 if c > 0 else -1) if abs(c) > 0.7 else c * inner.x / 0.7,
                       axis_val, inner.z * (1 if sn > 0 else -1) if abs(sn) > 0.7 else sn * inner.z / 0.7))
                pts.append(p + (e.normalized() + V((0, 1 if axis_val > 0 else -1, 0))).normalized() * r * 1.4)
        return pts

    steps = lib.n(64, 16)
    seam(ring(inner.y, 'y', steps), 'bag_piping_front', 0.0028, 'piping')
    seam(ring(-inner.y, 'y', steps), 'bag_piping_back', 0.0028, 'piping')

    # zip around the lid (front and both sides), with tape and two pulls
    zl = []
    zi = 0.02
    for k in range(lib.n(40, 10) + 1):
        f = k / lib.n(40, 10)
        if f < 0.25:
            p = V((-half.x + zi, -half.y + 0.03 + (half.y * 2 - 0.03 - zi) * (f / 0.25), half.z))
        elif f < 0.75:
            p = V((-half.x + zi + (w - 2 * zi) * ((f - 0.25) / 0.5), half.y - zi, half.z))
        else:
            p = V((half.x - zi, half.y - zi - (half.y * 2 - 0.03 - zi) * ((f - 0.75) / 0.25), half.z))
        zl.append(p)
    seam(zl, 'bag_zip_tape', 0.0055, 'webbing', closed=False)
    seam([p + V((0, 0, 0.002)) for p in zl], 'bag_zip', 0.0028, 'zipper', closed=False)
    for k, px in enumerate((-0.035, 0.05)):
        p0, nd = rounded(V((px, half.y - zi, half.z)))
        top = soften(p0, nd)
        lib.box('bag_zip_slider%d' % k, (0.014, 0.022, 0.008), 'steel_dark', 'forks_u',
                matrix=m @ Matrix.Translation(top + V((0, 0, 0.004))), bevel=0.002)
        lib.box('bag_zip_pull%d' % k, (0.009, 0.004, 0.04), 'rubber', 'forks_u',
                matrix=m @ Matrix.Translation(top + V((0, 0.012, -0.012))) @ Matrix.Rotation(0.5, 4, 'X'), bevel=0.0015)

    # mesh side pockets with an elastic top
    for s in (1, -1):
        pb = bmesh.new()
        puv = pb.loops.layers.uv.new('UVMap')
        ny, nz = lib.n(10, 3), lib.n(8, 3)
        grid = []
        coords = {}
        for iz in range(nz + 1):
            row = []
            for iy in range(ny + 1):
                yy = -half.y + 0.022 + (2 * half.y - 0.044) * iy / ny
                zz = -half.z + 0.03 + 0.17 * iz / nz
                p0, nd = rounded(V((s * half.x, yy, zz)))
                bulge = 0.016 * (1 - (2 * iy / ny - 1) ** 2) * (1 - (iz / nz) ** 3)
                vert = pb.verts.new(m @ (soften(p0, nd) + nd * (0.003 + bulge)))
                coords[vert] = (yy, zz)
                row.append(vert)
            grid.append(row)
        for iz in range(nz):
            for iy in range(ny):
                q = (grid[iz][iy], grid[iz][iy + 1], grid[iz + 1][iy + 1], grid[iz + 1][iy])
                face = pb.faces.new(q if s > 0 else tuple(reversed(q)))
                for loop in face.loops:
                    loop[puv].uv = coords[loop.vert]
        edge = [v.co.copy() for v in grid[-1]]
        lib.bm_to_obj('bag_mesh_pocket%+d' % s, pb, 'mesh_fabric', 'forks_u')
        lib.pipe('bag_pocket_elastic%+d' % s, edge, 0.0035, 'webbing', 'forks_u', verts=8)

    # velcro straps around the stem and over the handlebar
    ys = -half.y - 0.024
    for zz in (-0.07, 0.09):
        loop = [m @ V((-0.035, -half.y + 0.004, zz))]
        for k in range(lib.n(20, 8) + 1):
            a = math.radians(60 - 300 * k / lib.n(20, 8))
            loop.append(m @ V((0.026 * math.cos(a), ys + 0.026 * math.sin(a), zz)))
        loop.append(m @ V((0.035, -half.y + 0.004, zz)))
        zaxis = (m.to_3x3() @ V((0, 0, 1))).normalized()
        lib.sweep('bag_stem_strap', loop, lambda u: lib.rrect_profile(0.024, 0.0035, 0.001), 'webbing', 'forks_u',
                  ref=tuple(zaxis), weighted=False)
    top_back = m @ V((0, -half.y + 0.012, half.z - 0.01))
    for sx in (-0.075, 0.075):
        rb = 0.0155
        pts = [V((sx, top_back.y, top_back.z)), V((sx, yc + rb + 0.004, zc - 0.004)), V((sx, yc + 0.002, zc + rb + 0.002)),
               V((sx, yc - rb - 0.003, zc + 0.002)), V((sx, yc - 0.002, zc - rb - 0.003)),
               V((sx, top_back.y - 0.006, top_back.z - 0.02))]
        path = lib.resample(lib.fillet(pts, 0.012, 6), 0.004)
        lib.sweep('bag_bar_strap', path, lambda u: lib.rrect_profile(0.022, 0.003, 0.001), 'webbing', 'forks_u',
                  weighted=False)


def _dense(points, step):
    out = [points[0]]
    for a, b in zip(points, points[1:]):
        k = max(1, int((b - a).length / step))
        out += [a.lerp(b, i / k) for i in range(1, k + 1)]
    return out


def drivetrain():
    import bmesh
    ring_outer = lib.gear_pts(52, 0.1052, 0.0075) if lib.DETAIL >= 0.8 else lib.circle_pts(0.106, lib.n(208, 16))
    lib.ring_prism('chainring', ring_outer, lib.circle_pts(0.088, len(ring_outer)), 0.091, 0.0945, 'steel_dark',
                   'crank', (0, BB[0], BB[1]))
    for k in range(5):
        m = rot_x(2 * math.pi * k / 5 + 0.3, (0.097, BB[0], BB[1])) @ Matrix.Translation(V((0, 0, 0.05)))
        lib.box('spider%d' % k, (0.006, 0.016, 0.08), 'alloy_black', 'crank', matrix=m, bevel=0.002)
    lib.ring_prism('chainguard', lib.circle_pts(0.113, lib.n(96, 16)), lib.circle_pts(0.028, lib.n(96, 16)), 0.1005, 0.104, 'plastic_gloss', 'crank',
                   (0, BB[0], BB[1]), smooth=False)
    bm = bmesh.new()
    for k in range(9):
        yy = -0.085 + k * 0.021
        quad = []
        for dy, dz in ((-0.006, -0.1), (0.006, -0.1), (0.006 + 0.03, -0.02), (-0.006 + 0.03, -0.02)):
            y = yy + dy
            lim = math.sqrt(max(0.108 ** 2 - y ** 2, 0.0))
            z = max(dz, -lim) if dz < 0 else dz
            quad.append(bm.verts.new((0.1045, BB[0] + y, BB[1] + z)))
        if all((v.co.y - BB[0]) ** 2 + (v.co.z - BB[1]) ** 2 < 0.109 ** 2 for v in quad):
            bm.faces.new(quad)
    me_ob = lib.bm_to_obj('decal_chainguard', bm, 'decal_yellow', 'crank', smooth=False)

    # crank arms and pedals
    for s, ang, bone in ((1, 21.0, 'pedal_r'), (-1, 201.0, 'pedal_l')):
        a = math.radians(ang)
        pe = (BB[0] + 0.17 * math.cos(a), BB[1] + 0.17 * math.sin(a))
        x = 0.117 if s > 0 else -0.072
        m = tube_matrix(P(x, BB), P(x, pe), P(x, along(BB, pe, 0.5)))
        lib.box('crank_arm%+d' % s, (0.014, 0.026, 0.205), 'alloy_black', 'crank', matrix=m, bevel=0.006)
        lib.cylinder('crank_cap%+d' % s, 0.013, 0, 'steel_dark', 'crank', start=P(x, BB), end=P(x + s * 0.009, BB), verts=24)
        if s > 0:
            dd = (math.cos(a), math.sin(a))
            lib.text('decal_prowheel', 'Prowheel', 0.012, 'decal_white', 'crank',
                     lib.side_matrix(along(BB, pe, 0.5), dd, 1, x + 0.0072), font_path=lib.FONT_SANS)
        px = x + s * 0.068
        lib.cylinder('pedal_spindle%+d' % s, 0.0065, 0, 'steel', bone, start=P(x, pe), end=P(px + s * 0.05, pe), verts=16)
        lib.box('pedal%+d' % s, (0.095, 0.10, 0.02), 'plastic_black', bone, loc=(px, pe[0], pe[1]), bevel=0.006)
        for dx in ((-0.035, 0.0, 0.035) if lib.DETAIL >= 0.6 else ()):
            for dy in (-0.04, 0.04):
                for dz in (0.011, -0.011):
                    lib.cylinder('pedal_pin', 0.0022, 0.005, 'steel', bone, verts=8,
                                 matrix=Matrix.Translation(V((px + dx, pe[0] + dy, pe[1] + dz))))

    # cassette
    cogs = [34, 28, 24, 20, 18, 16, 14]
    for i, teeth in enumerate(cogs):
        x = 0.064 + i * 0.0045
        rp = 0.0127 / (2 * math.sin(math.pi / teeth))
        outer = lib.gear_pts(teeth, rp, 0.006) if lib.DETAIL >= 0.8 else lib.circle_pts(rp, lib.n(teeth * 4, 10))
        lib.ring_prism('cog%d' % teeth, outer, lib.circle_pts(0.016, len(outer)), x, x + 0.0019,
                       'steel', 'wheel_lr', (0, RA[0], RA[1]))
    lib.cylinder('freehub', 0.018, 0, 'alloy_black', 'wheel_lr', start=P(0.06, RA), end=P(0.096, RA), verts=32)

    # derailleur
    ju, jl, rj = (RA[0] + 0.030, RA[1] - 0.068), (RA[0] + 0.054, RA[1] - 0.144), 0.0225
    lib.box('derailleur_body', (0.018, 0.03, 0.055), 'alloy_black', 'swingarm', loc=(0.104, RA[0] - 0.012, RA[1] - 0.035),
            bevel=0.005)
    for xx in (0.0745, 0.0925):
        lib.box('derailleur_cage', (0.004, 0.034, 0.11), 'alloy_black', 'swingarm',
                matrix=tube_matrix(P(0, jl), P(0, ju), P(xx, along(jl, ju, 0.5))), bevel=0.012)
    for name, c in (('jockey_u', ju), ('jockey_l', jl)):
        outer = lib.gear_pts(11, rj, 0.005) if lib.DETAIL >= 0.8 else lib.circle_pts(rj, 10)
        lib.ring_prism(name, outer, lib.circle_pts(0.006, len(outer)), 0.0805, 0.0855, 'plastic_black',
                       'swingarm', (0, c[0], c[1]))

    # chain
    rc = 0.0127 / (2 * math.sin(math.pi / 52))
    rg = 0.0127 / (2 * math.sin(math.pi / 20))
    pts = []

    def arc(c, r, a0, a1, n=16):
        for k in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * k / n)
            pts.append((c[0] + r * math.cos(a), c[1] + r * math.sin(a)))

    arc(RA, rg, 90, 270, 18)
    arc(ju, rj, 0, -150, 10)
    arc(jl, rj, 180, 300, 8)
    arc(BB, rc, 270, 450, 36)
    pts.append(pts[0])
    path = [V((0, p[0], p[1])) for p in pts]
    if lib.DETAIL < 0.8:
        loop = [V((0.086, p.y, p.z)) for p in lib.resample(path, 0.02)]
        lib.pipe('chain', loop, 0.0045, 'chain', 'chassis', verts=6, caps=False)
        return
    dense = [V((0, p.y, p.z)) for p in _dense(path, 0.002)]
    samples = [dense[0]]
    acc = 0.0
    for a, b in zip(dense, dense[1:]):
        acc += (b - a).length
        if acc >= 0.0127:
            samples.append(b)
            acc = 0.0
    bm = bmesh.new()
    for k, (a, b) in enumerate(zip(samples, samples[1:])):
        c = (a + b) / 2
        x = 0.093 + (0.0786 - 0.093) * ((BB[0] - c.y) / (BB[0] - RA[0]))
        x = min(0.093, max(0.0786, x))
        t = (b - a).normalized()
        nrm = t.cross(V((1, 0, 0))).normalized()
        wide = 0.0078 if k % 2 else 0.0058
        m = lib.basis(V((1, 0, 0)), t, -nrm, V((x, c.y, c.z)))
        m = lib.basis(V((1, 0, 0)), t, t.cross(V((1, 0, 0))).normalized() * -1, V((x, c.y, c.z)))
        bmesh.ops.create_cube(bm, size=1.0, matrix=m @ Matrix.Diagonal((wide, 0.0158, 0.0072, 1.0)))
    chain = lib.bm_to_obj('chain', bm, 'chain', 'chassis')
    lib.add_bevel(chain, 0.0012, 1, 30.0)


def brakes_and_cables(yc, zc):
    for name, c, x, bone in (('caliper_rear', RA, -0.086, 'swingarm'), ('caliper_front', FA, -0.084, 'forks_l')):
        ang = 40 if c is RA else 118
        a = math.radians(ang)
        p = (c[0] + 0.088 * math.cos(a), c[1] + 0.088 * math.sin(a))
        tang = (-math.sin(a), math.cos(a))
        m = tube_matrix(P(x, p), P(x, add(p, tang)), P(x, p))
        lib.box(name, (0.022, 0.03, 0.06), 'alloy_black', bone, matrix=m, bevel=0.006)
    sdir = (STEM_TOP[0] - HT_TOP[0], STEM_TOP[1] - HT_TOP[1])
    sl = math.hypot(*sdir)
    sdir = (sdir[0] / sl, sdir[1] / sl)
    back_stem = (-sdir[1], sdir[0]) if sdir[0] > 0 else (-abs(sdir[1]), -abs(sdir[0]))
    back_head = (-UP[1], UP[0])

    def under(a, b, t, gap):
        d = (b[0] - a[0], b[1] - a[1])
        dl = math.hypot(*d)
        down = (-d[1] / dl, d[0] / dl)
        if down[1] > 0:
            down = (-down[0], -down[1])
        return add(along(a, b, t), down, gap)

    def route(x, tail, lever):
        return ([lever, (lever[0] * 0.5, yc - 0.02, zc - 0.05)]
                + [(x,) + add(add(HT_TOP, sdir, 0.14), back_stem, 0.034),
                   (x,) + add(add(HB, UP, 0.07), back_head, 0.045),
                   (x,) + under(HT_MID, MT_A, 0.30, 0.05),
                   (x,) + under(HT_MID, MT_A, 0.92, 0.048),
                   (x * 1.5, 0.048, 0.50), (x * 1.5, 0.026, 0.42)] + tail)

    cables = {
        'cable_rear_brake': (route(-0.012, [(-0.04, -0.02, 0.37), (-0.066, -0.25, 0.345), (-0.078, -0.48, 0.36),
                                            (-0.086, -0.565, 0.375)], (0.19, yc - 0.07, zc + 0.04)), 0.0026),
        'cable_motor': (route(0.0, [(0.045, -0.02, 0.37), (0.075, -0.25, 0.288), (0.09, -0.50, 0.295),
                                    (0.10, RA[0] + 0.035, RA[1] - 0.012)], (0.168, yc - 0.075, zc + 0.04)), 0.0036),
        'cable_shift': (route(0.012, [(0.05, -0.02, 0.375), (0.078, -0.25, 0.292), (0.095, -0.50, 0.30),
                                      (0.104, RA[0] + 0.02, RA[1] - 0.05)], (0.15, yc - 0.075, zc + 0.04)), 0.0026),
        'cable_front_brake': ([(-0.19, yc - 0.07, zc + 0.04), (-0.10, yc - 0.03, zc - 0.05),
                               (-0.035,) + add(add(HT_TOP, sdir, 0.14), back_stem, 0.03),
                               (-0.06,) + add(add(HB, UP, 0.0), back_head, 0.03),
                               (-0.105,) + add(FA, UP, 0.30), (-0.106,) + add(FA, UP, 0.16),
                               (-0.09, 0.565, 0.43)], 0.0026),
    }
    for name, (pts, r) in cables.items():
        lib.pipe(name, [V(p) for p in pts], r, 'plastic_gloss', 'chassis', fillet_r=0.05, verts=10, step=0.02)
    # kickstand on the left, down on the ground as in the photo
    lib.box('kickstand_mount', (0.016, 0.05, 0.03), 'alloy_black', 'chassis', loc=(-0.042, -0.13, 0.218), bevel=0.003)
    # folded up along the left chainstay (not visible from the right in the photo)
    lib.pipe('kickstand', [V((-0.05, -0.13, 0.214)), V((-0.072, -0.40, 0.268))], 0.0095, 'alloy_black', 'chassis', verts=16)
    lib.box('kickstand_foot', (0.02, 0.05, 0.03), 'rubber', 'chassis', loc=(-0.074, -0.405, 0.27), bevel=0.003)


def build(reset=True, collection='OneBike'):
    if reset:
        lib.reset_scene()
        lib.make_materials()
    else:
        lib.new_collection(collection)
    wheel('wheel_r', RA, 'wheel_lr', True)
    wheel('wheel_f', FA, 'wheel_lf', False)
    sp_top = frame()
    saddle(sp_top)
    battery()
    swingarm()
    shock()
    fender('fender_rear', RA, 0.356, 47, 127, 'swingarm', hw=0.068)
    rack()
    hl = fork()
    yc, zc = cockpit()
    drivetrain()
    brakes_and_cables(yc, zc)
    return {'headlight': hl, 'seat': sp_top}
