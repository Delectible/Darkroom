# Puts renders side by side on the carousel's dark spotlight background.
import sys, numpy as np
from PIL import Image
paths, out = sys.argv[1:-1], sys.argv[-1]
ims = [Image.open(p).convert('RGBA') for p in paths]
s = ims[0].size[0]
W, H = s * len(ims), s
y, x = np.mgrid[0:H, 0:W]
arr = np.zeros((H, W, 4), np.uint8)
v = np.full((H, W), 18.0)
for k in range(len(ims)):
    d = np.sqrt((x - s * k - s / 2) ** 2 + (y - s / 2) ** 2) / (0.62 * s)
    v = np.maximum(v, 18 + (44 - 18) * np.clip(1 - d, 0, 1))
arr[..., :3] = v[..., None].astype(np.uint8); arr[..., 3] = 255
bg = Image.fromarray(arr, 'RGBA')
for k, im in enumerate(ims): bg.alpha_composite(im, (s * k, 0))
bg.convert('RGB').save(out)
