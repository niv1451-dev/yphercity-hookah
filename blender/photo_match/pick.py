"""Pixel ruler crops and pixel -> metric conversion on a bike plane.
  pick.py ruler <out.jpg> x0 y0 x1 y1           crop with a pixel ruler (labels in full-photo pixels)
  pick.py conv <x_plane> u,v u,v ...           print y,z of photo pixels on plane x = x_plane
  pick.py convs <x_plane> u,v ...              same, on the steered front plane
"""
import json
import os
import math
import sys

import numpy as np
from PIL import Image, ImageDraw

REF = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "reference", "reference.jpg")
CAM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "reference", "camera.json")
mode = sys.argv[1]

if mode == 'ruler':
    out = sys.argv[2]
    x0, y0, x1, y1 = (int(v) for v in sys.argv[3:7])
    img = Image.open(REF).convert('RGB').crop((x0, y0, x1, y1))
    k = max(1, int(900 / max(img.size)))
    img = img.resize((img.width * k, img.height * k), Image.LANCZOS)
    pad = 40
    can = Image.new('RGB', (img.width + pad, img.height + pad), (255, 255, 255))
    can.paste(img, (pad, pad))
    d = ImageDraw.Draw(can, 'RGBA')
    for u in range((x0 // 10) * 10, x1 + 1, 10):
        if u < x0:
            continue
        px = pad + (u - x0) * k
        major = u % 50 == 0
        d.line([(px, pad - (14 if major else 6)), (px, pad)], fill=(0, 0, 0), width=1)
        if major:
            d.line([(px, pad), (px, can.height)], fill=(255, 0, 0, 90), width=1)
            d.text((px - 12, 2), str(u), fill=(0, 0, 0))
    for v in range((y0 // 10) * 10, y1 + 1, 10):
        if v < y0:
            continue
        py = pad + (v - y0) * k
        major = v % 50 == 0
        d.line([(pad - (14 if major else 6), py), (pad, py)], fill=(0, 0, 0), width=1)
        if major:
            d.line([(pad, py), (can.width, py)], fill=(0, 120, 255, 90), width=1)
            d.text((1, py - 12), str(v), fill=(0, 0, 0))
    can.save(out, quality=92)
    print('ruler ok', out)
    sys.exit()

cam = json.load(open(CAM))
C = np.array(cam['location'])
r, u, d = (np.array(cam[k]) for k in ('right', 'up', 'forward'))
f = cam['f_px']
W, H = 2576, 1449
xp = float(sys.argv[2])
L = cam['wheelbase']
UPAX = np.array([0.0, -math.sin(math.radians(20)), math.cos(math.radians(20))])
HB = np.array([0.0, 0.648, 0.33])     # steering pivot: an axis through the front axle (see calib.py)


def rot_axis(axis, ang):
    axis = axis / np.linalg.norm(axis)
    k = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + math.sin(ang) * k + (1 - math.cos(ang)) * k @ k


Rs = rot_axis(UPAX, math.radians(cam['front_steer_deg'])) if mode == 'convs' else np.eye(3)
n = Rs @ np.array([1.0, 0, 0])
p0 = Rs @ (np.array([xp, 0, 0]) - HB) + HB if mode == 'convs' else np.array([xp, 0, 0])
for s in sys.argv[3:]:
    uu, vv = (float(t) for t in s.split(',')[:2])
    ray = d + r * (uu - W / 2) / f - u * (vv - H / 2) / f
    t = ((p0 - C) @ n) / (ray @ n)
    P = C + ray * t
    loc = Rs.T @ (P - HB) + HB if mode == 'convs' else P
    print('%s -> y=%.3f z=%.3f' % (s, loc[1], loc[2]))
