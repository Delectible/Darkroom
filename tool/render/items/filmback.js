// The film camera body's back as the app shows it (phone-sized, units = dp),
// lying face up (+Y), image top = -Z: chrome top / bottom plates, pebbled
// leatherette, a machined viewfinder frame under glass, and every control
// modelled: flash slide switch, aspect dial, lens-flip knob, menu button,
// memo clip with the film box end, prints, shutter + advance lever, carton.
//
// Item: filmback[-a<deg>]  (deg: the body turned about its long axis, as in
// the swap). A look test for "every control in 3D".
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { FontLoader } from 'three/addons/loaders/FontLoader.js';
import { slab, brushedMetal, plastic, decal, cyl, lensGlass } from '/lib/parts.js';
import { canvas, tex, rng, noiseCanvas, normalFromHeight, roundRect } from '/lib/tex.js';
import { drawRabbit } from '/lib/logo.js';
import { build as buildShutter } from '/items/shutter.js';

const W = 412, H = 880, T = 40, TOP = T / 2;
const LEATHER_Z0 = -364, LEATHER_Z1 = 384, SKIN = 1.0;
const SURF = TOP + SKIN; // leather surface height

const shadowy = (o) => { o.traverse((m) => { if (m.isMesh) { m.castShadow = m.receiveShadow = true; } }); return o; };

// ---------------------------------------------------------------- textures
function pebbleMaps() {
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
  for (const t of [normal, rough, color]) t.repeat.set((W - 20) / 70, (LEATHER_Z1 - LEATHER_Z0) / 70);
  return { normal, rough, color };
}

function scenePhoto(w = 1152, h = 1536) {
  // A warm evening by the water, painted (no real photos in the repo).
  const [c, g] = canvas(w, h);
  const r = rng(21);
  const sky = g.createLinearGradient(0, 0, 0, h * 0.58);
  sky.addColorStop(0, '#47607a'); sky.addColorStop(0.45, '#c98f6a'); sky.addColorStop(0.8, '#f4c27c'); sky.addColorStop(1, '#f7d9a4');
  g.fillStyle = sky; g.fillRect(0, 0, w, h);
  // clouds
  for (let i = 0; i < 40; i++) {
    const x = r() * w, y = h * (0.05 + r() * 0.35), rw = 80 + r() * 220;
    const cg = g.createRadialGradient(x, y, 0, x, y, rw);
    cg.addColorStop(0, `rgba(255,${200 + r() * 40},${170 + r() * 40},${0.18 + r() * 0.15})`); cg.addColorStop(1, 'rgba(255,220,190,0)');
    g.fillStyle = cg; g.beginPath(); g.ellipse(x, y, rw, rw * 0.28, 0, 0, 7); g.fill();
  }
  // sun + glow
  const sx = w * 0.62, sy = h * 0.545;
  let gl = g.createRadialGradient(sx, sy, 0, sx, sy, w * 0.5);
  gl.addColorStop(0, 'rgba(255,236,190,0.95)'); gl.addColorStop(0.08, 'rgba(255,214,150,0.6)'); gl.addColorStop(1, 'rgba(255,190,120,0)');
  g.fillStyle = gl; g.fillRect(0, 0, w, h);
  // far hills
  g.fillStyle = '#6f6a72';
  g.beginPath(); g.moveTo(0, h * 0.56);
  for (let x = 0; x <= w; x += 8) g.lineTo(x, h * 0.55 - Math.sin(x / 140) * 16 - Math.sin(x / 47) * 5 - (x < w * 0.3 ? (w * 0.3 - x) * 0.12 : 0));
  g.lineTo(w, h * 0.6); g.lineTo(0, h * 0.6); g.fill();
  // water with sun path and ripples
  const wat = g.createLinearGradient(0, h * 0.58, 0, h);
  wat.addColorStop(0, '#d8a77a'); wat.addColorStop(0.4, '#6e5d5c'); wat.addColorStop(1, '#2c2b31');
  g.fillStyle = wat; g.fillRect(0, h * 0.58, w, h * 0.42);
  for (let i = 0; i < 1400; i++) {
    const y = h * 0.58 + Math.pow(r(), 1.6) * h * 0.42, spread = 30 + (y - h * 0.58) * 0.6;
    const x = sx + (r() - 0.5) * spread * 2, len = 6 + (y - h * 0.58) * 0.08 * r();
    g.fillStyle = `rgba(255,${210 + r() * 40},${150 + r() * 50},${0.25 + r() * 0.5})`;
    g.fillRect(x, y, len, 1 + (y - h * 0.58) * 0.006);
  }
  // jetty + figure silhouettes
  g.fillStyle = '#1c1714';
  g.fillRect(0, h * 0.70, w * 0.46, h * 0.018);
  for (let x = 20; x < w * 0.46; x += 70) g.fillRect(x, h * 0.70, 9, h * 0.09);
  g.beginPath(); g.ellipse(w * 0.33, h * 0.655, 13, 15, 0, 0, 7); g.fill();
  g.fillRect(w * 0.33 - 15, h * 0.665, 30, h * 0.036);
  g.fillRect(w * 0.33 - 13, h * 0.70 - 2, 10, 4); g.fillRect(w * 0.33 + 3, h * 0.70 - 2, 10, 4);
  // foreground grass
  for (let i = 0; i < 900; i++) {
    const x = r() * w, y0 = h * (0.86 + r() * 0.14), len = 30 + r() * 110;
    g.strokeStyle = `rgba(${18 + r() * 20},${16 + r() * 18},${12 + r() * 12},0.9)`;
    g.lineWidth = 1 + r() * 2.5; g.beginPath(); g.moveTo(x, h); g.quadraticCurveTo(x + (r() - 0.5) * 30, y0, x + (r() - 0.5) * 60, y0 - len * 0.4); g.stroke();
  }
  // film look: warm lift in the blacks, soft vignette, grain
  g.fillStyle = 'rgba(60,40,30,0.10)'; g.fillRect(0, 0, w, h);
  const v = g.createRadialGradient(w / 2, h / 2, w * 0.3, w / 2, h / 2, h * 0.75);
  v.addColorStop(0, 'rgba(0,0,0,0)'); v.addColorStop(1, 'rgba(0,0,0,0.38)');
  g.fillStyle = v; g.fillRect(0, 0, w, h);
  const id = g.getImageData(0, 0, w, h);
  for (let i = 0; i < id.data.length; i += 4) { const n = (r() - 0.5) * 22; id.data[i] += n; id.data[i + 1] += n; id.data[i + 2] += n; }
  g.putImageData(id, 0, 0);
  return c;
}

// Engraved, paint-filled lettering and marks: real (very thin) geometry
// lying on the metal. The path tracer ignored decal transparency in a scene
// this size, so nothing here relies on alpha.
const inkMat = new THREE.MeshPhysicalMaterial({ color: 0x0d0d0e, roughness: 0.55, clearcoat: 0.3 });
let _font = null;
async function font(name = 'helvetiker_bold') {
  if (!_font) _font = await new FontLoader().loadAsync(`/three/examples/fonts/${name}.typeface.json`);
  return _font;
}
// Text lying flat (+Y up), centred on x (align 'center') or starting at 0.
async function text(str, size, { mat = inkMat, align = 'center', spacing = 0, depth = 0.12 } = {}) {
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
function flat(shape, mat = inkMat, y = 0.12) {
  const m = new THREE.Mesh(new THREE.ShapeGeometry(shape, 12), mat);
  m.rotation.x = -Math.PI / 2; m.position.y = y;
  return m;
}
function capsule(x0, y0, x1, y1, r) {
  const s = new THREE.Shape(), a = Math.atan2(y1 - y0, x1 - x0);
  s.absarc(x1, y1, r, a - Math.PI / 2, a + Math.PI / 2, false);
  s.absarc(x0, y0, r, a + Math.PI / 2, a + Math.PI * 1.5, false);
  return s;
}
// The Darkroom rabbit (tool/render/lib/logo.js) as flat shapes, [h] tall,
// centred; the X eyes in [eyeMat].
function rabbit(h, mat = inkMat, eyeMat) {
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

function knurl(r, h, n, mat, depth = 0.6) {
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

function ringShape(ow, oh, or, iw, ih, ir) {
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
function frame(shape, depth, bevel, mat, y0) {
  const g = new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel, bevelSegments: 4, curveSegments: 16 });
  g.rotateX(-Math.PI / 2); // shape XY -> XZ (shape +Y -> -Z), extrude +Z -> +Y
  const m = new THREE.Mesh(g, mat);
  m.position.y = y0 + bevel;
  return m;
}

// A printed sheet lying flat at height y (texture top = -Z).
function sheet(w, d, mat, y) {
  const g = new THREE.PlaneGeometry(w, d);
  g.rotateX(-Math.PI / 2); g.translate(0, y, 0);
  return new THREE.Mesh(g, mat);
}

function screw(r, mat, slotMat, angle) {
  const g = new THREE.Group();
  const head = new THREE.Mesh(new THREE.SphereGeometry(r, 32, 12, 0, Math.PI * 2, 0, Math.PI / 2), mat);
  head.scale.y = 0.35; g.add(head);
  const slot = new THREE.Mesh(new THREE.BoxGeometry(r * 2.05, r * 0.5, r * 0.32), slotMat);
  slot.position.y = r * 0.22; slot.rotation.y = angle; g.add(slot);
  return g;
}

// ---------------------------------------------------------------- build
export async function build(THREE_, item) {
  const deg = +((item.match(/-a(-?\d+)/) || [])[1] || 0);
  const yaw = (deg * Math.PI) / 180;
  const root = new THREE.Group();
  const skip = new Set((new URLSearchParams(location.search).get('skip') || '').split(','));
  const add = (key, ...objs) => { if (!skip.has(key)) root.add(...objs); };

  const chrome = brushedMetal(0xdfe1e4, 0.2);
  const satin = brushedMetal(0xcfd2d6, 0.32);
  const polished = new THREE.MeshPhysicalMaterial({ color: 0xf0f1f3, metalness: 1, roughness: 0.06 });
  const blackAnod = new THREE.MeshPhysicalMaterial({ color: 0x141518, metalness: 0.6, roughness: 0.42, clearcoat: 0.2 });
  const blackPaint = new THREE.MeshPhysicalMaterial({ color: 0x0c0c0d, roughness: 0.35, clearcoat: 0.5, clearcoatRoughness: 0.2 });
  const gap = new THREE.MeshStandardMaterial({ color: 0x030303, roughness: 0.9 });
  const red = new THREE.MeshPhysicalMaterial({ color: 0xc8231b, roughness: 0.3, clearcoat: 1 });

  // Chassis: brushed chrome shell (top + bottom plates and the rim).
  const chassis = slab(W, H, T, 34, 3, chrome);
  chassis.rotation.x = -Math.PI / 2;
  add('chassis', chassis);

  // Leatherette panel, slightly proud of the metal, with a cut edge.
  const pm = pebbleMaps();
  const leatherMat = new THREE.MeshPhysicalMaterial({ map: pm.color, normalMap: pm.normal, normalScale: new THREE.Vector2(1.1, 1.1),
    roughnessMap: pm.rough, roughness: 1 });
  const lh = LEATHER_Z1 - LEATHER_Z0;
  const leather = slab(W - 18, lh, SKIN * 2, 22, 0.4, leatherMat);
  leather.rotation.x = -Math.PI / 2;
  leather.position.set(0, TOP, (LEATHER_Z0 + LEATHER_Z1) / 2);
  add('leather', leather);

  // ---- top plate: engraving, screws
  const plateZ = (-H / 2 + LEATHER_Z0) / 2; // centre of the top plate (~-402)
  const ink = '#141414';
  const mark = new THREE.Group();
  const logo = rabbit(15, inkMat, chrome); logo.position.x = -40; mark.add(logo);
  const word = await text('DARKROOM', 8.5, { align: 'left', spacing: 2.2 }); word.position.x = -28; mark.add(word);
  mark.position.set(22, TOP, plateZ - 2);
  root.add(mark);
  for (const [x, z, a] of [[-192, -426, 0.4], [192, -426, 1.2], [-192, 424, 2.1], [192, 424, 0.9]]) {
    const s = screw(3.4, polished, gap, a); s.position.set(x, TOP, z); root.add(s);
  }
  const serial = await text('No. 1998042  -  MADE IN THE DARKROOM', 4.2, { spacing: 0.9, mat: new THREE.MeshPhysicalMaterial({ color: 0x2a2a2c, roughness: 0.5 }) });
  serial.position.set(0, TOP, 412);
  root.add(serial);

  // ---- flash: three-position slide switch with engraved positions
  const fx = -154, fz = plateZ;
  for (const [t, u] of [['A', -26], ['ON', 0], ['OFF', 26]]) {
    const l = await text(t, 5.2, { spacing: 0.4 }); l.position.set(fx + u, TOP, fz - 14); root.add(l);
  }
  const slot = new THREE.Mesh(new RoundedBoxGeometry(64, 1.2, 8, 3, 0.6), gap);
  slot.position.set(fx, TOP - 0.3, fz + 2);
  root.add(slot);
  const tab = new THREE.Group();
  const tabBody = new THREE.Mesh(new RoundedBoxGeometry(15, 5.5, 12, 4, 1.6), polished);
  tabBody.position.y = 2.75; tab.add(tabBody);
  for (let i = -2; i <= 2; i++) {
    const rib = new THREE.Mesh(new RoundedBoxGeometry(1.1, 1.0, 10, 2, 0.4), satin);
    rib.position.set(i * 2.5, 5.6, 0); tab.add(rib);
  }
  tab.position.set(fx - 26, TOP, fz + 2);
  root.add(tab);
  const boltShape = new THREE.Shape();
  [[0.62, 0], [0.1, 0.58], [0.46, 0.58], [0.3, 1], [0.92, 0.38], [0.55, 0.38]].forEach(([u, v], i) => {
    const x = (u - 0.5) * 8, y = (0.5 - v) * 11;
    i ? boltShape.lineTo(x, y) : boltShape.moveTo(x, y);
  });
  const bolt = flat(boltShape); bolt.position.set(fx + 41, TOP, fz + 2); root.add(bolt);

  // ---- aspect: knurled dial, engraved ratio on top, index dot on the plate
  const ax = -82;
  const aspect = new THREE.Group();
  aspect.add(knurl(17, 8, 72, satin, 0.9));
  const aTop = new THREE.Mesh(new THREE.CylinderGeometry(15.6, 16.4, 1.2, 96), chrome);
  aTop.position.y = 8.6; aspect.add(aTop);
  const ratio = await text('3:2', 7.5, { spacing: 0.6 }); ratio.position.y = 9.2; aspect.add(ratio);
  for (let i = 0; i < 24; i++) {
    const a = (i / 24) * Math.PI * 2, long = i % 6 === 0;
    const tick = new THREE.Mesh(new THREE.BoxGeometry(long ? 2.6 : 1.6, 0.12, 0.35), inkMat);
    const r = long ? 12.8 : 13.3;
    tick.position.set(Math.cos(a) * r, 9.26, Math.sin(a) * r); tick.rotation.y = -a; aspect.add(tick);
  }
  aspect.position.set(ax, TOP, plateZ);
  root.add(aspect);
  const idx = cyl(1.3, 0.3, red, 24); idx.position.set(ax, TOP + 0.1, plateZ - 23); root.add(idx);

  // ---- lens flip: black knurled knob with a coated lens and a red index
  const lx = 124;
  const lensKnob = new THREE.Group();
  const collar = cyl(18.5, 2.4, chrome, 96); collar.position.y = 1.2; lensKnob.add(collar);
  const kn = knurl(16.2, 6.5, 60, blackAnod, 0.8); kn.position.y = 2.4; lensKnob.add(kn);
  const kTop = new THREE.Mesh(new THREE.CylinderGeometry(15.2, 15.8, 1.0, 96), blackPaint); kTop.position.y = 9.3; lensKnob.add(kTop);
  const lRing = new THREE.Mesh(new THREE.TorusGeometry(9.2, 0.9, 16, 96), polished); lRing.rotation.x = Math.PI / 2; lRing.position.y = 9.9; lensKnob.add(lRing);
  const well = cyl(8.6, 0.5, gap, 64); well.position.y = 9.7; lensKnob.add(well);
  const glass = new THREE.Mesh(new THREE.SphereGeometry(11, 64, 16, 0, Math.PI * 2, 0, Math.asin(8.3 / 11)), lensGlass());
  glass.position.y = 9.9 - 11 * Math.cos(Math.asin(8.3 / 11)) + 0.9; lensKnob.add(glass);
  const dotR = cyl(1.4, 0.3, red, 24); dotR.position.set(0, 9.85, -12.6); lensKnob.add(dotR);
  lensKnob.position.set(lx, TOP, plateZ);
  root.add(lensKnob);

  // ---- menu: flat-topped chrome button in a collar, engraved sliders glyph
  const mx = 172;
  const menu = new THREE.Group();
  const mc = cyl(14, 2.2, satin, 96); mc.position.y = 1.1; menu.add(mc);
  const mw = cyl(11.6, 0.4, gap, 64); mw.position.y = 2.2; menu.add(mw);
  const mb = new THREE.Mesh(new THREE.CylinderGeometry(10.4, 11, 4.2, 96), polished); mb.position.y = 4.3; menu.add(mb);
  for (const [yy, kx] of [[-3.2, 1.6], [0, -1.8], [3.2, 0.8]]) {
    const line = new THREE.Mesh(new THREE.BoxGeometry(10, 0.12, 0.9), inkMat); line.position.set(0, 6.45, yy); menu.add(line);
    const knob = cyl(1.3, 0.14, inkMat, 24); knob.position.set(kx, 6.5, yy); menu.add(knob);
  }
  menu.position.set(mx, TOP, plateZ);
  root.add(menu);

  // ---- viewfinder: anodised frame, polished chamfer, picture under glass
  const vz = -108, vw = 384, vh = 512;
  const outer = frame(ringShape(vw + 26, vh + 26, 16, vw, vh, 6), 3.2, 1.4, blackAnod, SURF);
  outer.position.z = vz; root.add(outer);
  const lip = frame(ringShape(vw + 4, vh + 4, 7, vw - 4, vh - 4, 4), 0.6, 0.9, polished, SURF + 2.6);
  lip.position.z = vz; root.add(lip);
  const photo = scenePhoto();
  const screen = new THREE.Mesh(new THREE.PlaneGeometry(vw - 4, vh - 4),
    new THREE.MeshPhysicalMaterial({ color: 0x000000, emissive: 0xffffff, emissiveMap: tex(photo), emissiveIntensity: 1.3, roughness: 0.4, clearcoat: 0.25, clearcoatRoughness: 0.03 }));
  screen.rotation.x = -Math.PI / 2; screen.position.set(0, SURF + 0.3, vz); root.add(screen);
  const glassPane = new THREE.Mesh(new THREE.BoxGeometry(vw - 2, 0.8, vh - 2),
    new THREE.MeshPhysicalMaterial({ color: 0xffffff, transmission: 1, thickness: 0.8, roughness: 0.02, ior: 1.5, metalness: 0 }));
  glassPane.position.set(0, SURF + 3.2, vz); if (skip.has('noglass')) add('glass', glassPane);

  // ---- memo clip with the film box end
  const mzz = 192, mxx = -30;
  // (single-material meshes only: the path tracer mixed up textures on
  // multi-material boxes)
  const cardTex = tex((() => {
      const [c, g] = canvas(1880, 460), r = rng(3);
      g.fillStyle = '#f1e9da'; g.fillRect(0, 0, 1880, 460);
      g.fillStyle = '#d99a3e'; g.fillRect(0, 300, 1880, 160);
      g.fillStyle = '#b8583a'; g.fillRect(0, 282, 1880, 12); g.fillRect(0, 440, 1880, 8);
      g.fillStyle = '#3b2a20'; g.textBaseline = 'alphabetic';
      g.font = '900 150px "Inter Display"'; g.fillText('PORTRAIT', 60, 190);
      g.font = '600 46px "DejaVu Sans Condensed"'; g.fillStyle = '#6b5040'; g.fillText('COLOR NEGATIVE FILM  ·  36 EXP  ·  C-41', 64, 258);
      g.fillStyle = '#b8583a'; roundRect(g, 1560, 40, 260, 200, 18); g.fill();
      g.fillStyle = '#fff7ea'; g.font = '900 150px "Inter Display"'; g.textAlign = 'center'; g.fillText('400', 1690, 200);
      g.fillStyle = '#3b2a20'; g.textAlign = 'left'; g.font = '800 64px "Inter Display"'; g.fillText('DARKROOM', 60, 405);
      drawRabbit(g, 1760, 380, 90, '#3b2a20');
      // card fibres and wear
      for (let i = 0; i < 6000; i++) { g.fillStyle = `rgba(${r() > 0.5 ? '255,255,255' : '60,40,20'},${r() * 0.06})`; g.fillRect(r() * 1880, r() * 460, 1 + r() * 6, 1); }
      return c;
    })());
  const card = new THREE.Group();
  card.add(new THREE.Mesh(new THREE.BoxGeometry(188, 0.6, 46), plastic(0xd8cdb6, { rough: 0.85, texture: 0.4 })));
  card.add(sheet(188, 46, new THREE.MeshPhysicalMaterial({ roughness: 0.62, map: cardTex }), 0.31));
  card.position.set(mxx, SURF + 0.35, mzz); add('card', card);
  const clip = frame(ringShape(200, 56, 6, 182, 38, 3), 1.6, 0.6, chrome, SURF + 0.7);
  clip.position.set(mxx, 0, mzz); root.add(clip);
  for (const sx of [-96, 96]) { const r = screw(2.2, polished, gap, sx > 0 ? 0.5 : 1.7); r.position.set(mxx + sx, SURF + 2.9, mzz); root.add(r); }

  // ---- prints: two glossy prints, gently curled, one under the other
  const printTex = (seed) => {
    const [c, g] = canvas(580, 700);
    g.fillStyle = '#f5f1e8'; g.fillRect(0, 0, 580, 700);
    g.drawImage(photo, 120 + seed * 60, 160, 900, 900, 34, 34, 512, 512);
    const r = rng(seed + 9);
    for (let i = 0; i < 1600; i++) { g.fillStyle = `rgba(120,100,80,${r() * 0.05})`; g.fillRect(r() * 580, r() * 700, 2, 2); }
    return tex(c);
  };
  const print = (seed, rot, x, z, y) => {
    const bend = (geo) => {
      const p = geo.attributes.position;
      for (let i = 0; i < p.count; i++) { const px = p.getX(i), pz = p.getZ(i); p.setY(i, p.getY(i) + 0.0011 * px * px + 0.0004 * pz * pz); }
      geo.computeVertexNormals();
      return geo;
    };
    const g = new THREE.Group();
    g.add(new THREE.Mesh(bend(new THREE.BoxGeometry(58, 0.35, 70, 24, 1, 28)), new THREE.MeshPhysicalMaterial({ color: 0xf2eee6, roughness: 0.7 })));
    const top = new THREE.PlaneGeometry(58, 70, 24, 28); top.rotateX(-Math.PI / 2); top.translate(0, 0.19, 0);
    g.add(new THREE.Mesh(bend(top), new THREE.MeshPhysicalMaterial({ map: printTex(seed), roughness: 0.32, clearcoat: 0.7, clearcoatRoughness: 0.12 })));
    g.rotation.y = rot; g.position.set(x, y, z);
    return g;
  };
  add('prints', print(2, 0.16, -146, 330, SURF + 0.4), print(0, -0.07, -152, 326, SURF + 1.1));

  // ---- shutter with the advance lever (the existing turntable model)
  const sh = (await buildShutter(THREE, 'shutter_film-all')).object;
  sh.scale.setScalar(138 / 40);
  sh.position.set(14, SURF, 330);
  add('shutter', sh);

  // ---- film carton lying on the body
  const cartonTop = tex((() => {
    const [c, g] = canvas(640, 480);
    g.fillStyle = '#f1e9da'; g.fillRect(0, 0, 640, 480);
    g.fillStyle = '#d99a3e'; g.fillRect(0, 300, 640, 180);
    g.fillStyle = '#b8583a'; g.fillRect(0, 286, 640, 10);
    g.fillStyle = '#3b2a20'; g.font = '900 96px "Inter Display"'; g.fillText('400', 30, 140);
    g.font = '800 44px "Inter Display"'; g.fillText('PORTRAIT', 30, 214);
    g.font = '600 26px "DejaVu Sans Condensed"'; g.fillStyle = '#6b5040'; g.fillText('35mm · 36 EXP', 30, 258);
    g.fillStyle = '#fff7ea'; g.font = '800 40px "Inter Display"'; g.fillText('DARKROOM', 30, 410);
    drawRabbit(g, 560, 390, 70, '#fff7ea');
    return c;
  })());
  const cardboard = new THREE.MeshPhysicalMaterial({ color: 0xe9dfcc, roughness: 0.7 });
  const band = new THREE.MeshPhysicalMaterial({ color: 0xd99a3e, roughness: 0.6 });
  const carton = new THREE.Group();
  carton.add(new THREE.Mesh(new RoundedBoxGeometry(64, 24, 48, 2, 0.8), cardboard));
  const band2 = new THREE.Mesh(new THREE.BoxGeometry(64.2, 9, 48.2), band); band2.position.y = -6; carton.add(band2);
  carton.add(sheet(62.4, 46.4, new THREE.MeshPhysicalMaterial({ map: cartonTop, roughness: 0.45, clearcoat: 0.25 }), 12.02));
  carton.rotation.y = 0.13; carton.position.set(152, SURF + 12, 330); add('carton', carton);

  shadowy(root);
  // the camera: straight down, swung about the body's long axis
  const fov = 13;
  const d = 500 / Math.tan((fov / 2) * Math.PI / 180);
  return {
    object: root,
    span: 1000,
    floorY: -T / 2,
    exposure: 1.0,
    fixedFrame: true,
    envRotation: 180,
    // Lit for a straight-down view: a big key softbox high front-left, a
    // strip light right for crisp edge highlights on the chrome, a weak warm
    // fill behind, a dark ceiling (no flat bounce washing the leather out).
    env: { ambient: 0.025, boxes: [
      { az: -40, el: 52, w: 46, h: 34, i: 9, c: [1.0, 0.96, 0.9] },
      { az: 70, el: 30, w: 8, h: 60, i: 10, c: [0.95, 0.97, 1.0] },
      { az: 160, el: 38, w: 60, h: 24, i: 2.2, c: [1.0, 0.92, 0.85] },
      { az: -120, el: 20, w: 20, h: 30, i: 1.5, c: [1, 1, 1] },
      // overhead scrim, off-centre: what the chrome mirrors from above
      { az: -25, el: 72, w: 150, h: 30, i: 3.2, c: [1, 1, 1] },
    ] },
    camera: { fov, position: [d * Math.sin(yaw), d * Math.cos(yaw), 0], target: [0, 0, 0], up: [0, 0, -1] },
  };
}
