"""Solve the photo camera from the two yellow rim-stripe ellipses.
Usage: calib.py <reference.jpg> <calib_dir>
Needs thin_pts.npy from yellow_mask.py. Writes camera.json and overlay.jpg.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ref_path, cdir = sys.argv[1], sys.argv[2]
pts = np.load(os.path.join(cdir, 'thin_pts.npy')).astype(np.float64)
W, H = Image.open(ref_path).size
rng = np.random.default_rng(1)

# ----------------------------------------------------------- ellipse fit (RANSAC)
def fit_conic(p):
    x, y = p[:, 0], p[:, 1]
    D = np.stack([x * x, x * y, y * y, x, y, np.ones_like(x)], 1)
    _, _, vt = np.linalg.svd(D, full_matrices=False)
    return vt[-1]


def conic_dist(c, p):
    a, b, cc, d, e, f = c
    x, y = p[:, 0], p[:, 1]
    val = a * x * x + b * x * y + cc * y * y + d * x + e * y + f
    gx = 2 * a * x + b * y + d
    gy = b * x + 2 * cc * y + e
    return np.abs(val) / (np.hypot(gx, gy) + 1e-9)


def is_ellipse(c):
    a, b, cc = c[:3]
    return b * b - 4 * a * cc < 0


def ransac(p, iters=4000, tol=3.0):
    best, best_in = None, None
    for _ in range(iters):
        s = p[rng.choice(len(p), 6, replace=False)]
        c = fit_conic(s)
        if not is_ellipse(c):
            continue
        inl = conic_dist(c, p) < tol
        if best_in is None or inl.sum() > best_in.sum():
            best, best_in = c, inl
    for _ in range(3):
        best = fit_conic(p[best_in])
        best_in = conic_dist(best, p) < tol
    return best, best_in


boxes = {'rear': (430, 880, 900, 1300), 'front': (1640, 840, 1890, 1225)}
obs = {}
for name, (x0, y0, x1, y1) in boxes.items():
    m = (pts[:, 0] >= x0) & (pts[:, 0] <= x1) & (pts[:, 1] >= y0) & (pts[:, 1] <= y1)
    p = pts[m]
    c, inl = ransac(p)
    obs[name] = p[inl]
    print(name, 'points', len(p), 'inliers', int(inl.sum()))

# ----------------------------------------------------------- camera model
UPAX = np.array([0.0, -math.sin(math.radians(20)), math.cos(math.radians(20))])   # solve used for reference/camera.json
R_STRIPE = 0.21
X_STRIPE = 0.0457
ZC = 0.33


def rot_axis(axis, ang):
    axis = axis / np.linalg.norm(axis)
    k = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + math.sin(ang) * k + (1 - math.cos(ang)) * k @ k


def cam_axes(yaw, pitch, roll):
    d = np.array([math.cos(pitch) * math.sin(yaw), math.cos(pitch) * math.cos(yaw), math.sin(pitch)])
    right = np.cross(d, [0, 0, 1.0])
    right /= np.linalg.norm(right)
    up = np.cross(right, d)
    r2 = math.cos(roll) * right + math.sin(roll) * up
    u2 = -math.sin(roll) * right + math.cos(roll) * up
    return r2, u2, d


def project(P, prm):
    cx, cy, cz, yaw, pitch, roll, f = prm[:7]
    r, u, d = cam_axes(yaw, pitch, roll)
    v = P - np.array([cx, cy, cz])
    zc = v @ d
    return np.stack([W / 2 + f * (v @ r) / zc, H / 2 - f * (v @ u) / zc], 1)


def circle(prm, which, n=720):
    L, steer = prm[7], prm[8]
    t = np.linspace(0, 2 * math.pi, n, endpoint=False)
    loc = np.stack([np.full(n, X_STRIPE), R_STRIPE * np.cos(t), R_STRIPE * np.sin(t)], 1)
    if which == 'rear':
        c = np.array([0.0, -L / 2, ZC])
        return loc + c
    c = np.array([0.0, L / 2, ZC])
    return loc @ rot_axis(UPAX, steer).T + c


def residuals(prm):
    res = []
    for which in ('rear', 'front'):
        q = project(circle(prm, which), prm)
        o = obs_s[which]
        d2 = ((o[:, None, :] - q[None, :, :]) ** 2).sum(-1)
        res.append(np.sqrt(d2.min(1)))
    # weak priors: roll near 0, focal near a 26 mm phone lens
    f0 = 27.0 / 36.0 * W
    res.append(np.array([prm[5] * 200.0, (prm[6] - f0) / f0 * 20.0]))
    return np.concatenate(res)


obs_s = {k: v[rng.choice(len(v), min(500, len(v)), replace=False)] for k, v in obs.items()}

# initial guess from the old 'photo' view
loc0 = np.array([1.9, -0.42, 1.38])
tgt0 = np.array([0.0, 0.02, 0.64])
d0 = tgt0 - loc0
d0 /= np.linalg.norm(d0)
prm = np.array([*loc0, math.atan2(d0[0], d0[1]), math.asin(d0[2]), 0.0, 27.0 / 36.0 * W, 1.24, 0.0])

lam = 1e-2
r0 = residuals(prm)
cost = (r0 ** 2).sum()
for it in range(200):
    J = np.zeros((len(r0), len(prm)))
    for k in range(len(prm)):
        h = 1e-4 * max(1.0, abs(prm[k]))
        p2 = prm.copy()
        p2[k] += h
        J[:, k] = (residuals(p2) - r0) / h
    A = J.T @ J
    g = J.T @ r0
    while True:
        step = np.linalg.solve(A + lam * np.diag(np.diag(A) + 1e-9), -g)
        p2 = prm + step
        r2 = residuals(p2)
        c2 = (r2 ** 2).sum()
        if c2 < cost:
            prm, r0, cost = p2, r2, c2
            lam = max(lam / 3, 1e-7)
            break
        lam *= 4
        if lam > 1e8:
            break
    if lam > 1e8 or np.linalg.norm(step) < 1e-9:
        break

n_obs = sum(len(v) for v in obs_s.values())
rms = math.sqrt((r0[:n_obs] ** 2).mean())
r, u, d = cam_axes(*prm[3:6])
cam = {
    'location': prm[:3].tolist(),
    'forward': d.tolist(), 'up': u.tolist(), 'right': r.tolist(),
    'lens_mm': float(prm[6] * 36.0 / W),
    'wheelbase': float(prm[7]),
    'front_steer_deg': float(math.degrees(prm[8])),
    'rms_px': rms,
    'f_px': float(prm[6]),
}
print(json.dumps(cam, indent=1))
json.dump(cam, open(os.path.join(cdir, 'camera.json'), 'w'), indent=1)

img = Image.open(ref_path).convert('RGB')
dr = ImageDraw.Draw(img)
for which, col in (('rear', (0, 255, 255)), ('front', (255, 0, 255))):
    q = project(circle(prm, which), prm)
    dr.line([tuple(x) for x in q] + [tuple(q[0])], fill=col, width=3)
    for x, y in obs[which][::7]:
        dr.point((x, y), fill=(255, 0, 0))
img.save(os.path.join(cdir, 'overlay.jpg'), quality=90)
