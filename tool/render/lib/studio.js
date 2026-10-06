import * as THREE from 'three';
// Procedural studio HDRI: dark cyclorama with large soft boxes. Returns an
// equirect Float32 DataTexture usable by both the rasteriser and path tracer.
export function studioEnv({ w = 1024, h = 512, ambient = 0.02, boxes } = {}) {
  boxes = boxes ?? [
    // theta: azimuth deg (0 = +Z toward camera), phi: elevation deg
    // az: 0 = toward the camera (+Z), +90 = camera right (+X)
    { az: -48, el: 32, w: 42, h: 46, i: 7.5, c: [1.0, 0.96, 0.90] },  // key softbox, front-left high
    { az: 78, el: 8, w: 9, h: 75, i: 9.0, c: [0.95, 0.97, 1.0] },     // strip light, right: crisp highlight line
    { az: 165, el: 32, w: 70, h: 22, i: 4.5, c: [1.0, 1.0, 1.0] },    // rim, behind
    { az: -125, el: 18, w: 18, h: 40, i: 2.2, c: [1.0, 0.95, 0.9] },  // kicker, back-left
    { az: 0, el: 85, w: 360, h: 12, i: 0.6, c: [1, 1, 1] },           // ceiling bounce
  ];
  const data = new Float32Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    const el = 90 - (y + 0.5) / h * 180;
    for (let x = 0; x < w; x++) {
      const u = (x + 0.5) / w;
      const az = (((0.75 - u) * 360 + 540) % 360) - 180;
      // dark grey gradient: slightly brighter above the horizon
      let g = ambient * (el > 0 ? 1.0 + el / 90 : 0.5 + 0.5 * (1 + el / 90));
      let r = g, gg = g, b = g;
      for (const s of boxes) {
        let daz = Math.abs(((az - s.az + 540) % 360) - 180);
        const dx = daz / (s.w / 2), dy = Math.abs(el - s.el) / (s.h / 2);
        // soft-edged rectangle
        const m = Math.max(dx, dy);
        if (m < 1.15) {
          const f = m < 0.85 ? 1 : 1 - (m - 0.85) / 0.3;
          r += s.i * s.c[0] * f; gg += s.i * s.c[1] * f; b += s.i * s.c[2] * f;
        }
      }
      const o = ((h - 1 - y) * w + x) * 4;
      data[o] = r; data[o + 1] = gg; data[o + 2] = b; data[o + 3] = 1;
    }
  }
  const t = new THREE.DataTexture(data, w, h, THREE.RGBAFormat, THREE.FloatType);
  t.mapping = THREE.EquirectangularReflectionMapping;
  t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearFilter;
  t.needsUpdate = true;
  return t;
}
