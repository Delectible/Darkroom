// Canvas texture helpers shared by every item.
import * as THREE from 'three';

export function canvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return [c, c.getContext('2d')];
}

export function tex(c, { srgb = true, repeat = false, aniso = 8 } = {}) {
  const t = new THREE.CanvasTexture(c);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = aniso;
  if (repeat) { t.wrapS = t.wrapT = THREE.RepeatWrapping; }
  t.needsUpdate = true;
  return t;
}

// Deterministic PRNG so renders are repeatable.
export function rng(seed = 1) {
  let s = seed >>> 0;
  return () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

// Value-noise field painted into a greyscale canvas: base +/- amp, with
// optional streaks (brushed metal) when sx != sy.
export function noiseCanvas(w, h, { base = 128, amp = 30, sx = 8, sy = 8, octaves = 3, seed = 7, scratches = 0 } = {}) {
  const [c, g] = canvas(w, h);
  const img = g.createImageData(w, h);
  const r = rng(seed);
  const grids = [];
  for (let o = 0; o < octaves; o++) {
    const gw = Math.ceil(w / (sx * 2 ** (octaves - 1 - o))) + 2, gh = Math.ceil(h / (sy * 2 ** (octaves - 1 - o))) + 2;
    const v = new Float32Array(gw * gh).map(() => r() * 2 - 1);
    grids.push({ gw, gh, v, cx: sx * 2 ** (octaves - 1 - o), cy: sy * 2 ** (octaves - 1 - o) });
  }
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let n = 0, a = 1, tot = 0;
    for (const G of grids) {
      const fx = x / G.cx, fy = y / G.cy, ix = Math.floor(fx), iy = Math.floor(fy), tx = fx - ix, ty = fy - iy;
      const sxx = tx * tx * (3 - 2 * tx), syy = ty * ty * (3 - 2 * ty);
      const at = (i, j) => G.v[(j % G.gh) * G.gw + (i % G.gw)];
      const v = (at(ix, iy) * (1 - sxx) + at(ix + 1, iy) * sxx) * (1 - syy) + (at(ix, iy + 1) * (1 - sxx) + at(ix + 1, iy + 1) * sxx) * syy;
      n += v * a; tot += a; a *= 0.5;
    }
    const val = Math.max(0, Math.min(255, base + amp * n / tot));
    const o = (y * w + x) * 4; img.data[o] = img.data[o + 1] = img.data[o + 2] = val; img.data[o + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  // fine scratches: thin lines a little rougher than the surrounding surface
  for (let i = 0; i < scratches; i++) {
    g.strokeStyle = `rgba(255,255,255,${0.08 + r() * 0.12})`;
    g.lineWidth = 0.6 + r();
    g.beginPath();
    const x0 = r() * w, y0 = r() * h, ang = r() * Math.PI, len = 10 + r() * 60;
    g.moveTo(x0, y0); g.lineTo(x0 + Math.cos(ang) * len, y0 + Math.sin(ang) * len); g.stroke();
  }
  return c;
}

// Converts a height canvas into a tangent-space normal map canvas.
export function normalFromHeight(hc, strength = 2) {
  const w = hc.width, h = hc.height;
  const src = hc.getContext('2d').getImageData(0, 0, w, h).data;
  const [c, g] = canvas(w, h);
  const out = g.createImageData(w, h);
  const H = (x, y) => src[(((y + h) % h) * w + ((x + w) % w)) * 4] / 255;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const dx = (H(x + 1, y) - H(x - 1, y)) * strength, dy = (H(x, y + 1) - H(x, y - 1)) * strength;
    let nx = -dx, ny = -dy, nz = 1; const l = Math.hypot(nx, ny, nz); nx /= l; ny /= l; nz /= l;
    const o = (y * w + x) * 4;
    out.data[o] = (nx * 0.5 + 0.5) * 255; out.data[o + 1] = (ny * 0.5 + 0.5) * 255; out.data[o + 2] = (nz * 0.5 + 0.5) * 255; out.data[o + 3] = 255;
  }
  g.putImageData(out, 0, 0);
  return c;
}

export function roundRect(g, x, y, w, h, r) {
  g.beginPath();
  g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath();
}

// Code-128-ish barcode: purely decorative bar pattern from a seed.
export function barcode(g, x, y, w, h, seed = 3, color = '#111') {
  const r = rng(seed); let cx = x; g.fillStyle = color;
  while (cx < x + w) { const bw = [1, 1, 2, 3][Math.floor(r() * 4)] * (w / 95); if (r() > 0.45) g.fillRect(cx, y, bw, h); cx += bw; }
}
