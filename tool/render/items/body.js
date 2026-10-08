// The camera bodies the app draws, as path-traced sprites: every part of the
// film and digital bodies (panels, plates, viewfinder frame, controls) is
// rendered on its own, straight down (orthographic, units = dp), lit by one
// fixed studio, and composited by the app into its normal responsive layout
// (lib/features/camera/presentation/photo_body.dart). Parts that stand proud
// of the body are rendered turned 0..48 degrees about the body's long axis
// too, for the camera swap.
//
// Item: body_<mode>-<part>[-<state>]-a<deg>
//   mode: film | digital     deg: yaw (film turns +, digital -; see PARTS)
// The part sits with its base centre at the origin on the body surface
// (y = 0), image top = -Z. The canvas (`ortho`) is the part's box plus a
// margin for its shadow and for parallax when turned.
import * as THREE from 'three';
import {
  RoundedBoxGeometry, mergeGeometries, slab, brushedMetal, plastic, cyl, lensGlass, canvas, tex, rng,
  noiseCanvas, normalFromHeight, pebbleMaps, inkMat, text, flat, capsule, rabbit, knurl, ringShape, frame,
  screw, shadowy,
} from '/lib/bodykit.js';
import { build as buildShutter } from '/items/shutter.js';

// ------------------------------------------------------------------ studio
// Lit for a straight-down view (see filmback.js): a big key softbox high
// front-left, a strip light right for crisp edges on metal, a weak warm
// fill behind, an off-centre overhead scrim for the chrome to mirror.
export const STUDIO = {
  ambient: 0.025,
  boxes: [
    { az: -40, el: 52, w: 46, h: 34, i: 9, c: [1.0, 0.96, 0.9] },
    { az: 70, el: 30, w: 8, h: 60, i: 10, c: [0.95, 0.97, 1.0] },
    { az: 160, el: 38, w: 60, h: 24, i: 2.2, c: [1.0, 0.92, 0.85] },
    { az: -120, el: 20, w: 20, h: 30, i: 1.5, c: [1, 1, 1] },
    { az: -25, el: 72, w: 150, h: 30, i: 3.2, c: [1, 1, 1] },
  ],
};

// ------------------------------------------------------------------ materials
let M = null;
function mats() {
  if (M) return M;
  M = {
    chrome: brushedMetal(0xdfe1e4, 0.2),
    satin: brushedMetal(0xcfd2d6, 0.32),
    polished: new THREE.MeshPhysicalMaterial({ color: 0xf0f1f3, metalness: 1, roughness: 0.06 }),
    blackAnod: new THREE.MeshPhysicalMaterial({ color: 0x141518, metalness: 0.6, roughness: 0.42, clearcoat: 0.2 }),
    blackPaint: new THREE.MeshPhysicalMaterial({ color: 0x0c0c0d, roughness: 0.35, clearcoat: 0.5, clearcoatRoughness: 0.2 }),
    gap: new THREE.MeshStandardMaterial({ color: 0x030303, roughness: 0.9 }),
    red: new THREE.MeshPhysicalMaterial({ color: 0xd0261c, roughness: 0.55 }),
    alu: brushedMetal(0xc9ced6, 0.26),
    aluDark: new THREE.MeshPhysicalMaterial({ color: 0x8d939c, metalness: 1, roughness: 0.32 }),
    rubber: plastic(0x1a1b1d, { rough: 0.78, texture: 0.5, clearcoat: 0 }),
    glossBlack: new THREE.MeshPhysicalMaterial({ color: 0x0a0b0c, roughness: 0.12, clearcoat: 1, clearcoatRoughness: 0.05 }),
    paper: new THREE.MeshPhysicalMaterial({ color: 0xf4f0e7, roughness: 0.55, clearcoat: 0.6, clearcoatRoughness: 0.15 }),
    photoArea: new THREE.MeshPhysicalMaterial({ color: 0x8a8a8a, roughness: 0.3, clearcoat: 0.7 }),
    whiteInk: new THREE.MeshPhysicalMaterial({ color: 0xe9e9e6, roughness: 0.5 }),
    // Small parts: fine satin (a brushed texture is far too coarse at this
    // size) and a spun, ringed finish for round tops.
    satinSmall: new THREE.MeshPhysicalMaterial({ color: 0xd2d5d9, metalness: 1, roughness: 0.27 }),
    spun: spunMetal(0xbcc0c6, 0.2),
  };
  return M;
}

// Concentric turning marks for round tops (cylinder caps map 0..1 across).
function spunMetal(color, rough) {
  const N = 1024, [c, g] = canvas(N, N), r = rng(17);
  g.fillStyle = '#808080'; g.fillRect(0, 0, N, N);
  for (let i = 0; i < 900; i++) {
    const rad = r() * N * 0.5, v = 128 + (r() - 0.5) * 120;
    g.strokeStyle = `rgb(${v},${v},${v})`; g.lineWidth = 0.6 + r() * 1.4;
    g.beginPath(); g.arc(N / 2, N / 2, rad, 0, Math.PI * 2); g.stroke();
  }
  const normal = tex(normalFromHeight(c, 1.6), { srgb: false });
  return new THREE.MeshPhysicalMaterial({ color, metalness: 1, roughness: rough, normalMap: normal, normalScale: new THREE.Vector2(0.45, 0.45) });
}

let _leather = null;
function leather() {
  if (_leather) return _leather;
  const pm = pebbleMaps(1, 1);
  _leather = (w, h) => {
    const m = new THREE.MeshPhysicalMaterial({ map: pm.color, normalMap: pm.normal, normalScale: new THREE.Vector2(1.1, 1.1),
      roughnessMap: pm.rough, roughness: 1 });
    // ~70 dp per pebble tile, whatever the panel's size
    for (const t of [m.map, m.normalMap, m.roughnessMap]) { t.repeat.set(w / 70, h / 70); }
    return m;
  };
  return _leather;
}

// ------------------------------------------------------------------ parts
// Each part: canvas [w, h] in dp (box + margins), yaws to render, states,
// and build(state) -> Object3D (base centre at the origin, surface y = 0).
const YAWS = [0, 6, 12, 18, 24, 30, 36, 42, 48];
const PANEL_YAWS = [0, 16, 32, 48];
const LEVER_REST = 0.18;

const film = {
  // The body panels: leatherette (tall: the app crops it to the screen) and
  // the chrome plates at the top and bottom (cropped at the screen edge).
  panel: { canvas: [412, 1000], yaws: [0], spp: 48, px: 3, noShadow: true, build: () => {
    const g = new THREE.Group();
    const m = slab(412, 1000, 2, 0.1, 0.4, leather()(412, 1000));
    m.rotation.x = -Math.PI / 2; m.position.y = -1; g.add(m);
    return g;
  } },
  // (each has 20 dp of leather below / above its edge for its shadow)
  'plate-top': { canvas: [412, 180], yaws: YAWS, spp: 64, px: 3, edge: 20, build: () => plate(180, 'top') },
  'plate-bot': { canvas: [412, 140], yaws: YAWS, spp: 64, px: 3, edge: 20, build: () => plate(140, 'bot') },
  // Viewfinder frame, a 9-slice source: 30 dp corners round a 140 dp window.
  frame: { canvas: [220, 220], box: [196, 196], yaws: YAWS, spp: 96, slice: 40, build: () => {
    const { blackAnod, polished } = mats();
    const g = new THREE.Group();
    g.add(frame(ringShape(196, 196, 14, 180, 180, 8), 3.2, 1.4, blackAnod, 0));
    g.add(frame(ringShape(182, 182, 9, 176, 176, 7), 0.6, 0.9, polished, 2.6));
    return g;
  } },
  // Flash: a three-position slide (A / ON / OFF) with an engraved bolt; the
  // tab is its own sprite, slid by the app.
  flash: { canvas: [100, 60], yaws: YAWS, build: async () => {
    const { gap, chrome } = mats();
    const g = new THREE.Group();
    const slot = new THREE.Mesh(new RoundedBoxGeometry(62, 1.2, 8, 3, 0.6), gap); slot.position.set(-4, -0.3, 6); g.add(slot);
    for (const [t, u] of [['A', -30], ['ON', -4], ['OFF', 22]]) {
      const l = await text(t, 5.4, { spacing: 0.4 }); l.position.set(u, 0, -10); g.add(l);
    }
    const bolt = new THREE.Shape();
    [[0.62, 0], [0.1, 0.58], [0.46, 0.58], [0.3, 1], [0.92, 0.38], [0.55, 0.38]].forEach(([u, v], i) => {
      const x = (u - 0.5) * 8, y = (0.5 - v) * 11;
      i ? bolt.lineTo(x, y) : bolt.moveTo(x, y);
    });
    const b = flat(bolt); b.position.set(36, 0, 6); g.add(b);
    return g;
  } },
  flashtab: { canvas: [36, 36], yaws: YAWS, build: () => {
    const { polished, satinSmall: satin } = mats();
    const g = new THREE.Group();
    const body = new THREE.Mesh(new RoundedBoxGeometry(15, 5.5, 12, 4, 1.6), polished); body.position.y = 2.75; g.add(body);
    for (let i = -2; i <= 2; i++) {
      const rib = new THREE.Mesh(new RoundedBoxGeometry(1.1, 1.0, 10, 2, 0.4), satin); rib.position.set(i * 2.5, 5.6, 0); g.add(rib);
    }
    return g;
  } },
  // Aspect: knurled dial with a blank top (the app prints the ratio on it)
  // and a red index dot on the plate above it.
  aspect: { canvas: [60, 64], yaws: YAWS, build: () => {
    const { satinSmall, spun, red } = mats();
    const g = new THREE.Group();
    g.add(knurl(17, 8, 72, satinSmall, 0.9));
    const top = new THREE.Mesh(new THREE.CylinderGeometry(15.6, 16.4, 1.2, 96), [satinSmall, spun, satinSmall]); top.position.y = 8.6; g.add(top);
    for (let i = 0; i < 24; i++) {
      const a = (i / 24) * Math.PI * 2, long = i % 6 === 0;
      const tick = new THREE.Mesh(new THREE.BoxGeometry(long ? 2.6 : 1.6, 0.12, 0.35), inkMat);
      const r = long ? 12.8 : 13.3;
      tick.position.set(Math.cos(a) * r, 9.26, Math.sin(a) * r); tick.rotation.y = -a; g.add(tick);
    }
    const idx = cyl(1.3, 0.3, red, 24); idx.position.set(0, 0.1, -23); g.add(idx);
    return g;
  } },
  // Lens flip: chrome collar, black knurled knob, coated lens. The red
  // index on the knob is a separate sprite (lensdot) the app turns.
  lens: { canvas: [56, 56], yaws: YAWS, build: () => lensKnob(false) },
  lensdot: { canvas: [40, 40], yaws: [0], noShadow: true, build: () => {
    const d = cyl(1.4, 0.3, mats().red, 24); d.position.set(0, 9.85, -12.6);
    const g = new THREE.Group(); g.add(d); return g;
  } },
  menu: { canvas: [48, 48], yaws: YAWS, states: ['up', 'down'], stateYaw0: ['down'], build: (s) => {
    const { satinSmall, gap, spun } = mats();
    const g = new THREE.Group();
    const c = cyl(14, 2.2, satinSmall, 96); c.position.y = 1.1; g.add(c);
    const w = cyl(11.6, 0.4, gap, 64); w.position.y = 2.2; g.add(w);
    const lift = s === 'down' ? -1.4 : 0;
    const b = new THREE.Mesh(new THREE.CylinderGeometry(10.4, 11, 4.2, 96), [satinSmall, spun, satinSmall]); b.position.y = 4.3 + lift; g.add(b);
    for (const [yy, kx] of [[-3.2, 1.6], [0, -1.8], [3.2, 0.8]]) {
      const line = new THREE.Mesh(new THREE.BoxGeometry(10, 0.12, 0.9), inkMat); line.position.set(0, 6.45 + lift, yy); g.add(line);
      const k = cyl(1.3, 0.14, inkMat, 24); k.position.set(kx, 6.5 + lift, yy); g.add(k);
    }
    return g;
  } },
  // Memo clip, a horizontal 3-slice source: the app stretches the middle to
  // the card's width (the card itself is drawn by the app).
  memo: { canvas: [140, 72], box: [120, 52], yaws: YAWS, sliceX: 36, build: () => {
    const { satinSmall, polished, gap } = mats();
    const g = new THREE.Group();
    g.add(frame(ringShape(120, 52, 6, 104, 38, 3), 1.6, 0.6, satinSmall, 0.4));
    for (const sx of [-55, 55]) { const r = screw(2.2, polished, gap, sx > 0 ? 0.5 : 1.7); r.position.set(sx, 2.6, 0); g.add(r); }
    return g;
  } },
  // Gallery: a glossy print with an empty picture area (the app draws the
  // latest print into it).
  print: { canvas: [84, 92], yaws: YAWS, build: () => {
    const { paper } = mats();
    const g = new THREE.Group();
    const geo = new THREE.BoxGeometry(58, 0.35, 70, 24, 1, 28);
    const p = geo.attributes.position;
    for (let i = 0; i < p.count; i++) { const px = p.getX(i), pz = p.getZ(i); p.setY(i, p.getY(i) + 0.0008 * px * px + 0.0003 * pz * pz); }
    geo.computeVertexNormals();
    const m = new THREE.Mesh(geo, paper); m.position.y = 0.4; g.add(m);
    return g;
  } },
  // Stock: a recessed tray the app shows the loaded film's artwork in.
  tray: { canvas: [84, 84], yaws: YAWS, build: () => tray(false) },
  // Shutters (tool/render/items/shutter.js parts, in this studio): the
  // film release with its lever, and Super 8's RUN button.
  shutter: { canvas: [150, 150], yaws: YAWS, states: ['up', 'down'], stateYaw0: ['down'], build: (s) => shutter('film', s) },
  lever: { canvas: [150, 150], yaws: [0], noShadow: true, build: () => shutter('film', 'lever') },
  // The release without its lever, for the lever's stroke (face-on only).
  release: { canvas: [150, 150], yaws: [0], states: ['up', 'down'], build: (s) => shutter('film', s === 'down' ? 'bare-down' : 'bare') },
  run: { canvas: [120, 120], yaws: YAWS, states: ['up', 'down'], stateYaw0: ['down'], build: (s) => shutter('run', s) },
};

const digital = {
  // One-piece brushed aluminium face; its reflections move as it turns.
  panel: { canvas: [412, 1000], yaws: PANEL_YAWS, spp: 48, px: 3, noShadow: true, build: () => {
    const g = new THREE.Group();
    const m = slab(412, 1000, 2, 0.1, 0.4, mats().alu);
    m.rotation.x = -Math.PI / 2; m.position.y = -1; g.add(m);
    return g;
  } },
  // LCD surround: glossy black with a dark lip (9-slice).
  frame: { canvas: [220, 220], box: [204, 204], yaws: YAWS, spp: 96, slice: 40, build: () => {
    const { glossBlack, aluDark } = mats();
    const g = new THREE.Group();
    g.add(frame(ringShape(200, 200, 10, 180, 180, 4), 2.4, 1.0, glossBlack, 0));
    g.add(frame(ringShape(204, 204, 12, 198, 198, 10), 0.8, 0.5, aluDark, 0));
    return g;
  } },
  // Rubber pill keys (flash, aspect, menu): labels are printed by the app.
  pill: { canvas: [96, 56], yaws: YAWS, states: ['up', 'down'], stateYaw0: ['down'], build: (s) => pill(76, 36, s) },
  pillwide: { canvas: [84, 56], yaws: YAWS, states: ['up', 'down'], stateYaw0: ['down'], build: (s) => pill(64, 36, s) },
  pillsmall: { canvas: [64, 56], yaws: YAWS, states: ['up', 'down'], stateYaw0: ['down'], build: (s) => pill(44, 36, s) },
  lens: { canvas: [56, 56], yaws: YAWS, build: () => lensKnob(true) },
  lensdot: film.lensdot,
  // The segment LCD's bezel (9-slice) and the review screen round the
  // gallery thumbnail: black surround, aluminium chamfer, open screen.
  lcd: { canvas: [120, 80], box: [116, 76], yaws: YAWS, slice: 26, build: () => bezel(100, 60, 6) },
  review: { canvas: [84, 84], yaws: YAWS, build: () => bezel(64, 64, 7) },
  // W | T rocker.
  rocker: { canvas: [124, 64], yaws: YAWS, states: ['mid', 'w', 't'], stateYaw0: ['w', 't'], build: (s) => rocker(s) },
  tray: { canvas: [84, 84], yaws: YAWS, build: () => tray(true) },
  shutter: { canvas: [120, 120], yaws: YAWS, states: ['up', 'down'], stateYaw0: ['down'], build: (s) => shutter('digital', s) },
  rec: { canvas: [120, 120], yaws: YAWS, states: ['up', 'down'], stateYaw0: ['down'], build: (s) => shutter('digitalrec', s) },
};

export const PARTS = { film, digital };

// ------------------------------------------------------------------ builders
function plate(h, which) {
  const { chrome, polished, gap } = mats();
  const g = new THREE.Group();
  // The plate runs past the canvas at the screen edge; its inner edge (20 dp
  // in from the canvas edge, over the leather) has a chamfer.
  const len = h - 20 + 40, sign = which === 'top' ? 1 : -1;
  const m = slab(420, len, 3, 0.1, 1.2, chrome);
  m.rotation.x = -Math.PI / 2;
  m.position.set(0, 1.5, sign * (h / 2 - 20 - len / 2));
  g.add(m);
  const zEdge = sign * (h / 2 - 20);
  for (const x of [-192, 192]) { const s = screw(3.4, polished, gap, x > 0 ? 1.2 : 0.4); s.position.set(x, 3, zEdge - sign * 12); g.add(s); }
  return g;
}

function lensKnob(dark) {
  const { satinSmall, blackAnod, blackPaint, polished, gap } = mats();
  const g = new THREE.Group();
  const collar = cyl(18.5, 2.4, dark ? mats().aluDark : satinSmall, 96); collar.position.y = 1.2; g.add(collar);
  const kn = knurl(16.2, 6.5, 60, blackAnod, 0.8); kn.position.y = 2.4; g.add(kn);
  const kTop = new THREE.Mesh(new THREE.CylinderGeometry(15.2, 15.8, 1.0, 96), blackPaint); kTop.position.y = 9.3; g.add(kTop);
  const ring = new THREE.Mesh(new THREE.TorusGeometry(9.2, 0.9, 16, 96), polished); ring.rotation.x = Math.PI / 2; ring.position.y = 9.9; g.add(ring);
  const well = cyl(8.6, 0.5, gap, 64); well.position.y = 9.7; g.add(well);
  const glass = new THREE.Mesh(new THREE.SphereGeometry(11, 64, 16, 0, Math.PI * 2, 0, Math.asin(8.3 / 11)), lensGlass());
  glass.position.y = 9.9 - 11 * Math.cos(Math.asin(8.3 / 11)) + 0.9; g.add(glass);
  return g;
}

function tray(dark) {
  const { satinSmall, aluDark } = mats();
  const g = new THREE.Group();
  g.add(frame(ringShape(66, 66, 12, 56, 56, 8), 1.6, 0.7, dark ? aluDark : satinSmall, 0));
  const well = puck(56, 56, 0.6, 8, 0.1, new THREE.MeshPhysicalMaterial({ color: 0x101011, roughness: 0.7 }));
  g.add(well);
  return g;
}

// A flat rounded-rect block lying on the body: w x h footprint, [depth]
// tall from y = 0, corner radius r (in plan), edges bevelled.
function puck(w, h, depth, r, bevel, mat) {
  const m = slab(w, h, depth, Math.min(r, Math.min(w, h) / 2 - 0.01), bevel, mat);
  m.rotation.x = -Math.PI / 2; m.position.y = depth / 2;
  return m;
}

function pill(w, h, state) {
  const { rubber, aluDark, gap } = mats();
  const g = new THREE.Group();
  const well = puck(w + 4, h + 4, 0.6, (h + 4) / 2, 0.1, gap); well.position.y = -0.2; g.add(well);
  const rim = frame(ringShape(w + 8, h + 8, (h + 8) / 2 - 0.01, w + 3, h + 3, (h + 3) / 2 - 0.01), 0.8, 0.5, aluDark, 0); g.add(rim);
  const key = puck(w, h, 4.2, h / 2, 1.4, rubber);
  key.position.y = state === 'down' ? 0.2 : 1.1; g.add(key);
  return g;
}

function bezel(w, h, r) {
  const { glossBlack, aluDark } = mats();
  const g = new THREE.Group();
  g.add(frame(ringShape(w + 12, h + 12, r + 4, w, h, r), 1.8, 0.8, glossBlack, 0));
  g.add(frame(ringShape(w + 16, h + 16, r + 6, w + 11, h + 11, r + 4), 0.6, 0.4, aluDark, 0));
  return g;
}

async function rocker(state) {
  const { rubber, aluDark, gap, whiteInk } = mats();
  const g = new THREE.Group();
  g.add(frame(ringShape(108, 48, 23.99, 102, 42, 20.99), 0.8, 0.5, aluDark, 0));
  const well = puck(102, 42, 0.6, 21, 0.1, gap); well.position.y = -0.2; g.add(well);
  const key = new THREE.Group();
  const body = puck(100, 40, 4.2, 20, 1.4, rubber); body.position.y = 0.8; key.add(body);
  const groove = new THREE.Mesh(new THREE.BoxGeometry(1, 0.6, 26), gap); groove.position.y = 5.05; key.add(groove);
  for (const [t, x] of [['W', -25], ['T', 25]]) { const l = await text(t, 11, { mat: whiteInk, depth: 5.08 }); l.position.x = x; key.add(l); }
  // pressed: the rocker tips toward the side held
  key.rotation.z = state === 'w' ? 0.035 : state === 't' ? -0.035 : 0;
  g.add(key);
  return g;
}

async function shutter(kind, state) {
  if (state === 'lever') {
    const o = (await buildShutter(THREE, `shutter_film-lever`)).object;
    const g = new THREE.Group(); o.scale.setScalar(138 / 40); g.add(o); return g;
  }
  let o;
  if (state === 'bare' || state === 'bare-down') {
    o = new THREE.Group();
    o.add((await buildShutter(THREE, 'shutter_film-base')).object);
    o.add((await buildShutter(THREE, `shutter_film-cap${state === 'bare-down' ? '-down' : ''}`)).object);
  } else {
    o = (await buildShutter(THREE, `shutter_${kind}-all${state === 'down' ? '-down' : ''}`)).object;
  }
  const scale = { film: 138 / 40, run: 108 / 30, digital: 96 / 30, digitalrec: 96 / 30 }[kind];
  o.scale.setScalar(scale);
  const g = new THREE.Group(); g.add(o);
  return g;
}

// ------------------------------------------------------------------ build
export async function build(THREE_, item) {
  const m = item.match(/^body_(film|digital)-([a-z]+(?:-(?:top|bot))?)(?:-(up|down|mid|w|t))?-a(-?\d+)$/);
  if (!m) throw new Error(`bad item ${item}`);
  const [, mode, partName, state, deg] = m;
  const part = PARTS[mode][partName];
  const yaw = (+deg * Math.PI) / 180 * (mode === 'film' ? 1 : -1);
  const obj = await part.build(state);
  shadowy(obj);
  // Turned about the body's long axis (image vertical = Z), with its own
  // patch of body surface for the shadow passes.
  const root = new THREE.Group(); root.add(obj); root.rotation.z = yaw;
  const floorMesh = new THREE.Mesh(new THREE.PlaneGeometry(3000, 3000),
    new THREE.MeshStandardMaterial({ color: 0xb0b0b0, roughness: 0.9, metalness: 0 }));
  floorMesh.rotation.x = -Math.PI / 2; floorMesh.position.y = -0.02; floorMesh.receiveShadow = true;
  const floor = new THREE.Group(); floor.add(floorMesh); floor.rotation.z = yaw;
  const [cw, ch] = part.canvas;
  return {
    object: root,
    floor,
    span: Math.max(cw, ch),
    fixedFrame: true,
    exposure: 1.0,
    envRotation: 180,
    env: STUDIO,
    camera: { ortho: [cw, ch], position: [0, 5000, 0], target: [0, 0, 0], up: [0, 0, -1] },
  };
}
