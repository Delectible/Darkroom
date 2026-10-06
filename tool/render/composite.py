# Combines the object pass with a shadow extracted from floor/bg passes, and
# lightly denoises the path-traced object pass.
import sys, numpy as np, cv2
obj_p, floor_p, bg_p, out_p = sys.argv[1:5]
strength = float(sys.argv[5]) if len(sys.argv) > 5 else 0.85
obj = cv2.imread(obj_p, cv2.IMREAD_UNCHANGED).astype(np.float32) / 255.0   # BGRA, straight alpha
H, W = obj.shape[:2]
def lum(p):
    im = cv2.imread(p, cv2.IMREAD_UNCHANGED).astype(np.float32) / 255.0
    im = cv2.resize(im, (W, H), interpolation=cv2.INTER_CUBIC)
    l = im[..., :3] @ np.array([0.0722, 0.7152, 0.2126], np.float32)
    return cv2.GaussianBlur(l, (0, 0), W / 512 * 2.0)
lf, lb = lum(floor_p), lum(bg_p)
shadow = np.where(lb > 0.02, np.clip(1.0 - lf / np.maximum(lb, 1e-3), 0, 1), 0.0)
shadow = cv2.GaussianBlur(shadow, (0, 0), W / 512 * 1.5) * strength
# keep only shadows close to the object (kills horizon noise far away)
a8 = (obj[..., 3] > 0.05).astype(np.uint8)
near = cv2.dilate(a8, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(W * 0.12) | 1, int(W * 0.12) | 1)))
near = cv2.GaussianBlur(near.astype(np.float32), (0, 0), W * 0.03)
ys = np.nonzero(a8.any(axis=1))[0]
if len(ys):
    yy = np.arange(H, dtype=np.float32)[:, None]
    # shadows only from the lower half of the object downwards
    below = np.clip((yy - (ys[0] + (ys[-1] - ys[0]) * 0.5)) / (H * 0.05), 0, 1)
    near = near * below
shadow = shadow * np.clip(near, 0, 1)
# denoise colour where the object is (edge-preserving)
rgb8 = (np.clip(obj[..., :3], 0, 1) * 255).astype(np.uint8)
den = cv2.fastNlMeansDenoisingColored(rgb8, None, 3, 3, 5, 15).astype(np.float32) / 255.0
a = obj[..., 3:4]
# object over shadow (shadow is black with alpha)
sa = shadow[..., None] * (1 - a)
out_a = a + sa
out_rgb = np.where(out_a > 1e-4, (den * a) / np.maximum(out_a, 1e-4), 0)
out = np.concatenate([out_rgb, out_a], axis=2)
cv2.imwrite(out_p, (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8))
