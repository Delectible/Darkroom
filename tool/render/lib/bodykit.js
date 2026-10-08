// Shared modelling kit for the camera bodies drawn by the app
// (items/body.js): materials, textures and small parts. Units are dp.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { FontLoader } from 'three/addons/loaders/FontLoader.js';
import { slab, brushedMetal, plastic, cyl, lensGlass } from '/lib/parts.js';
import { canvas, tex, rng, noiseCanvas, normalFromHeight, roundRect } from '/lib/tex.js';

export { RoundedBoxGeometry, mergeGeometries, slab, brushedMetal, plastic, cyl, lensGlass, canvas, tex, rng, noiseCanvas, normalFromHeight, roundRect };

export const shadowy = (o) => { o.traverse((m) => { if (m.isMesh) { m.castShadow = m.receiveShadow = true; } }); return o; };

// ---------------------------------------------------------------- textures
export function pebbleMaps(repeatX = 6, repeatY = 12) {
  // Worley-style pebbles: each cell a soft dome, valleys between.
  const N = 1024, cells = 34, r = rng(5);
  const pts = [];
  for (let j = 0; j < cells; j++) for (let i = 0; i < cells; i++) pts.push([(i + 0.15 + r() * 0.7) / cells * N, (j + 0.15 + r() * 0.7) / cells * N, 0.7 + r() * 0.5]);
  const [hc, hg] = canvas(N, N);
  const img = hg.createImageData(N, N);
  const cs = N / cells;
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const ci = Math.floor(x / cs), cj = Math.floor(y / cs);
    let d1 = 1e9, d2 = 1e9, hgt = 1;
    for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) {
      const ii = (ci + di + cells) % cells, jj = (cj + dj + cells) % cells, p = pts[jj * cells + ii];
      let dx = x - p[0], dy = y - p[1];
      if (dx > N / 2) dx -= N; if (dx < -N / 2) dx += N; if (dy > N / 2) dy -= N; if (dy < -N / 2) dy += N;
      const d = Math.hypot(dx, dy) / p[2];
      if (d < d1) { d2 = d1; d1 = d; hgt = p[2]; } else if (d < d2) d2 = d;
    }
    const edge = Math.min(1, (d2 - d1) / (cs * 0.28)); // 0 in the valleys
    const v = Math.pow(edge, 0.55) * (0.75 + 0.25 * hgt);
    const o = (y * N + x) * 4;
    img.data[o] = img.data[o + 1] = img.data[o + 2] = 40 + v * 200; img.data[o + 3] = 255;
  }
  hg.putImageData(img, 0, 0);
  // fine micro-noise on top
  const fine = noiseCanvas(N, N, { base: 128, amp: 40, sx: 3, sy: 3, octaves: 2, seed: 11 });
  hg.globalAlpha = 0.18; hg.globalCompositeOperation = 'overlay'; hg.drawImage(fine, 0, 0);
  hg.globalAlpha = 1; hg.globalCompositeOperation = 'source-over';
  const normal = tex(normalFromHeight(hc, 5.5), { srgb: false, repeat: true });
  // roughness: tops a touch smoother (worn by hands), valleys matte
  const [rc, rg2] = canvas(N, N);
  rg2.drawImage(hc, 0, 0);
  rg2.globalCompositeOperation = 'difference'; rg2.fillStyle = '#fff'; rg2.fillRect(0, 0, N, N);
  rg2.globalCompositeOperation = 'source-over';
  rg2.fillStyle = 'rgba(150,150,150,0.55)'; rg2.fillRect(0, 0, N, N);
  const rough = tex(rc, { srgb: false, repeat: true });
  // colour: near-black with a faint warm cast, valleys darker
  const [cc, cg] = canvas(N, N);
  cg.fillStyle = '#0d0b0a'; cg.fillRect(0, 0, N, N);
  cg.globalAlpha = 0.12; cg.drawImage(hc, 0, 0); cg.globalAlpha = 1;
  const color = tex(cc, { repeat: true });
  for (const t of [normal, rough, color]) t.repeat.set(repeatX, repeatY);
  return { normal, rough, color };
}

// Engraved, paint-filled lettering and marks: real (very thin) geometry
// lying on the metal. The path tracer ignored decal transparency in a scene
// this size, so nothing here relies on alpha.
export const inkMat = new THREE.MeshPhysicalMaterial({ color: 0x0d0d0e, roughness: 0.55, clearcoat: 0.3 });
let _font = null;
export async function font(name = 'helvetiker_bold') {
  if (!_font) _font = await new FontLoader().loadAsync(`/three/examples/fonts/${name}.typeface.json`);
  return _font;
}
// Text lying flat (+Y up), centred on x (align 'center') or starting at 0.
export async function text(str, size, { mat = inkMat, align = 'center', spacing = 0, depth = 0.12 } = {}) {
  const f = await font();
  const shapes = [];
  let x = 0;
  const glyphs = [];
  for (const ch of str) {
    const sh = f.generateShapes(ch, size);
    const g = new THREE.ShapeGeometry(sh, 4);
    g.computeBoundingBox();
    const adv = ch === ' ' ? size * 0.32 : (g.boundingBox.max.x - g.boundingBox.min.x) + size * 0.1;
    glyphs.push([g, x - (ch === ' ' ? 0 : g.boundingBox.min.x)]);
    x += adv + spacing;
  }
  const width = x - spacing;
  const geos = glyphs.map(([g, gx]) => { g.translate(gx - (align === 'center' ? width / 2 : 0), -size / 2, 0); return g; });
  const merged = mergeGeometries(geos);
  const ex = new THREE.Mesh(merged, mat);
  ex.rotation.x = -Math.PI / 2; // shape XY -> lying on XZ, reading toward -Z = up
  ex.position.y = depth;
  const g = new THREE.Group(); g.add(ex);
  return g;
}
// A flat shape (in the XY of the drawing, y up = image up) lying on the part.
export function flat(shape, mat = inkMat, y = 0.12) {
  const m = new THREE.Mesh(new THREE.ShapeGeometry(shape, 12), mat);
  m.rotation.x = -Math.PI / 2; m.position.y = y;
  return m;
}
export function capsule(x0, y0, x1, y1, r) {
  const s = new THREE.Shape(), a = Math.atan2(y1 - y0, x1 - x0);
  s.absarc(x1, y1, r, a - Math.PI / 2, a + Math.PI / 2, false);
  s.absarc(x0, y0, r, a + Math.PI / 2, a + Math.PI * 1.5, false);
  return s;
}
// The Darkroom rabbit (tool/render/lib/logo.js) as flat shapes, [h] tall,
// centred; the X eyes in [eyeMat].
export function rabbit(h, mat = inkMat, eyeMat) {
  const g = new THREE.Group(), s = h / 129, cx = 104.5, cy = 93.5;
  const P = (x, y) => [(x - cx) * s, -(y - cy) * s];
  const ear1 = capsule(...P(80, 104), ...P(70, 40), 11 * s);
  const ear2a = capsule(...P(110, 100), ...P(120, 48), 11 * s), ear2b = capsule(...P(120, 48), ...P(146, 60), 11 * s);
  const head = new THREE.Shape(); head.absellipse(...P(94, 122), 42 * s, 36 * s, 0, Math.PI * 2);
  for (const sh of [ear1, ear2a, ear2b, head]) g.add(flat(sh, mat));
  for (const [ex, ey] of [[80, 118], [108, 118]]) {
    for (const d of [1, -1]) {
      g.add(flat(capsule(...P(ex - 7, ey - 7 * d), ...P(ex + 7, ey + 7 * d), 2.75 * s), eyeMat, 0.2));
    }
  }
  return g;
}

export function knurl(r, h, n, mat, depth = 0.6) {
  const ridge = new THREE.BoxGeometry(depth * 1.2, h, (2 * Math.PI * r / n) * 0.55);
  const geos = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2, g = ridge.clone();
    g.rotateY(-a); g.translate(Math.cos(a) * r, h / 2, Math.sin(a) * r);
    geos.push(g);
  }
  const core = new THREE.CylinderGeometry(r - depth * 0.3, r - depth * 0.3, h, 96); core.translate(0, h / 2, 0);
  geos.push(core);
  return new THREE.Mesh(mergeGeometries(geos.map((g) => g.toNonIndexed())), mat);
}

export function ringShape(ow, oh, or, iw, ih, ir) {
  const s = new THREE.Shape(), x = -ow / 2, y = -oh / 2;
  s.moveTo(x + or, y); s.lineTo(x + ow - or, y); s.absarc(x + ow - or, y + or, or, -Math.PI / 2, 0);
  s.lineTo(x + ow, y + oh - or); s.absarc(x + ow - or, y + oh - or, or, 0, Math.PI / 2);
  s.lineTo(x + or, y + oh); s.absarc(x + or, y + oh - or, or, Math.PI / 2, Math.PI);
  s.lineTo(x, y + or); s.absarc(x + or, y + or, or, Math.PI, Math.PI * 1.5);
  const h2 = new THREE.Path(), a = -iw / 2, b = -ih / 2;
  h2.moveTo(a + ir, b); h2.lineTo(a + iw - ir, b); h2.absarc(a + iw - ir, b + ir, ir, -Math.PI / 2, 0);
  h2.lineTo(a + iw, b + ih - ir); h2.absarc(a + iw - ir, b + ih - ir, ir, 0, Math.PI / 2);
  h2.lineTo(a + ir, b + ih); h2.absarc(a + ir, b + ih - ir, ir, Math.PI / 2, Math.PI);
  h2.lineTo(a, b + ir); h2.absarc(a + ir, b + ir, ir, Math.PI, Math.PI * 1.5);
  s.holes.push(h2);
  return s;
}
// A flat frame lying on the face (extruded up +Y from y0).
export function frame(shape, depth, bevel, mat, y0) {
  const g = new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel, bevelSegments: 4, curveSegments: 16 });
  g.rotateX(-Math.PI / 2); // shape XY -> XZ (shape +Y -> -Z), extrude +Z -> +Y
  const m = new THREE.Mesh(g, mat);
  m.position.y = y0 + bevel;
  return m;
}

// A printed sheet lying flat at height y (texture top = -Z).
export function sheet(w, d, mat, y) {
  const g = new THREE.PlaneGeometry(w, d);
  g.rotateX(-Math.PI / 2); g.translate(0, y, 0);
  return new THREE.Mesh(g, mat);
}

export function screw(r, mat, slotMat, angle) {
  const g = new THREE.Group();
  const head = new THREE.Mesh(new THREE.SphereGeometry(r, 32, 12, 0, Math.PI * 2, 0, Math.PI / 2), mat);
  head.scale.y = 0.35; g.add(head);
  const slot = new THREE.Mesh(new THREE.BoxGeometry(r * 2.05, r * 0.5, r * 0.32), slotMat);
  slot.position.y = r * 0.22; slot.rotation.y = angle; g.add(slot);
  return g;
}

