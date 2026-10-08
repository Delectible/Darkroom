# One body sprite: object pass + soft shadow from the floor / bg passes,
# denoised, scaled to the app's density and saved as WebP.
#   sprite.py obj.png floor.png|- bg.png|- out.webp width_px
import sys, numpy as np, cv2
from PIL import Image
obj_p, floor_p, bg_p, out_p, width = sys.argv[1:6]
obj = cv2.imread(obj_p, cv2.IMREAD_UNCHANGED).astype(np.float32) / 255.0
H, W = obj.shape[:2]
rgb8 = (np.clip(obj[..., :3], 0, 1) * 255).astype(np.uint8)
den = cv2.fastNlMeansDenoisingColored(rgb8, None, 3, 3, 5, 15).astype(np.float32) / 255.0
a = obj[..., 3:4]
if floor_p != '-':
    def lum(p):
        im = cv2.imread(p, cv2.IMREAD_UNCHANGED).astype(np.float32) / 255.0
        im = cv2.resize(im, (W, H), interpolation=cv2.INTER_CUBIC)
        return cv2.GaussianBlur(im[..., :3] @ np.array([0.0722, 0.7152, 0.2126], np.float32), (0, 0), max(1.0, W / 400))
    lf, lb = lum(floor_p), lum(bg_p)
    shadow = np.where(lb > 0.02, 1.0 - lf / np.maximum(lb, 1e-3), 0.0)
    # far from the part the two passes should agree: take what's left at the
    # canvas border as the baseline (noise, bounce differences), not shadow
    border = np.concatenate([shadow[:4].ravel(), shadow[-4:].ravel(), shadow[:, :4].ravel(), shadow[:, -4:].ravel()])
    shadow = np.clip(shadow - np.median(border), 0, 1)
    shadow = cv2.GaussianBlur(shadow, (0, 0), max(1.0, W / 300)) * 0.9
    # fade out toward the canvas edge (no hard cut where the sprite ends)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    edge = np.minimum(np.minimum(xx, W - 1 - xx), np.minimum(yy, H - 1 - yy))
    shadow *= np.clip(edge / (0.06 * min(W, H)), 0, 1)
    sa = shadow[..., None] * (1 - a)
    out_a = a + sa
    out_rgb = np.where(out_a > 1e-4, (den * a) / np.maximum(out_a, 1e-4), 0)
else:
    out_a, out_rgb = a, den
out = np.concatenate([out_rgb, out_a], axis=2)
img = Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)[..., [2, 1, 0, 3]], 'RGBA')
w = int(width)
if img.width != w:
    img = img.resize((w, round(img.height * w / img.width)), Image.LANCZOS)
img.save(out_p, 'WEBP', quality=90, method=6)
