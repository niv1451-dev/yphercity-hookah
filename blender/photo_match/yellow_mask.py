"""Find thin yellow lines (the rim stripes) in the reference photo.
Usage: yellow_mask.py <reference.jpg> <out_dir>
Writes mask_yellow.png, mask_thin.png and thin_pts.npy (x, y pixel coords of thin yellow pixels).
"""
import os
import sys

import numpy as np
from PIL import Image

img = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(np.float32)
out = sys.argv[2]
os.makedirs(out, exist_ok=True)
r, g, b = img[..., 0], img[..., 1], img[..., 2]
mx = img.max(-1)
mn = img.min(-1)
sat = (mx - mn) / (mx + 1e-3)
yellow = (r > 120) & (g > 90) & (b < 0.55 * g) & (r >= g * 0.95) & (r < g * 1.6) & (sat > 0.45)


def shift_or(m, k):
    o = m.copy()
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            o |= np.roll(np.roll(m, dy, 0), dx, 1)
    return o


def shift_and(m, k):
    o = m.copy()
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            o &= np.roll(np.roll(m, dy, 0), dx, 1)
    return o


k = 4
opened = shift_or(shift_and(yellow, k), k)      # thick blobs survive an opening
thin = yellow & ~shift_or(opened, 2)             # thin lines only
Image.fromarray((yellow * 255).astype(np.uint8)).save(os.path.join(out, 'mask_yellow.png'))
Image.fromarray((thin * 255).astype(np.uint8)).save(os.path.join(out, 'mask_thin.png'))
ys, xs = np.nonzero(thin)
np.save(os.path.join(out, 'thin_pts.npy'), np.stack([xs, ys], 1))
print('yellow', int(yellow.sum()), 'thin', int(thin.sum()))
