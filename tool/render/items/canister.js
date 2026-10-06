// 35mm film cartridge (135). Original label designs; no real brand marks.
import { canvas, tex, noiseCanvas, normalFromHeight, roundRect, barcode, rng } from '/lib/tex.js';
import { drawRabbit } from '/lib/logo.js';

const R = 12.4;              // shell radius (mm)
const CAP = 1.6;             // cap thickness
const SHELL = 44;            // shell length
const Y0 = CAP, Y1 = CAP + SHELL, TOP = Y1 + CAP;
const FILM_W = 35, FILM_Y = (Y0 + Y1) / 2 - FILM_W / 2;

const VARIANTS = {
  ektar: {
    iso: '100', word: 'VIVID', kind: 'COLOR NEGATIVE FILM', process: 'PROCESS C-41', din: '21°',
    base: '#c3161f', band: '#f2711c', stripe: '#ffd23f', ink: '#ffffff', ink2: '#ffe9d6', numBg: '#111111', numInk: '#ffffff',
    cap: 0x1a1a1a, capMetal: 0.35, capRough: 0.38, film: 0x1e110b, filmSheen: 0x5a3826, seed: 11,
  },
  portra: {
    iso: '400', word: 'PORTRAIT', kind: 'COLOR NEGATIVE FILM', process: 'PROCESS C-41', din: '27°',
    base: '#f1e9da', band: '#d99a3e', stripe: '#b8583a', ink: '#3b2a20', ink2: '#6b5040', numBg: '#b8583a', numInk: '#fff7ea',
    cap: 0xc9c9c9, capMetal: 1.0, capRough: 0.28, film: 0x20120c, filmSheen: 0x5e3a28, seed: 23,
  },
  hp5: {
    iso: '400', word: 'CLASSIC', kind: 'BLACK & WHITE FILM', process: 'B&W NEGATIVE', din: '27°',
    base: '#151515', band: '#e9e9e6', stripe: '#9a9a9a', ink: '#f2f2f0', ink2: '#bdbdbd', numBg: '#f2f2f0', numInk: '#121212',
    cap: 0x1b1b1b, capMetal: 0.35, capRough: 0.42, film: 0x1d1b22, filmSheen: 0x55525f, seed: 37,
  },
};

const ROT = 0.55;                       // yaw applied to the group
const FRONT = 0.5 - ROT / (2 * Math.PI); // label u that faces the lens

function fitFont(g, text, weight, family, maxW, maxH) {
  let size = maxH;
  g.font = `${weight} ${size}px "${family}"`;
  const w = g.measureText(text).width;
  if (w > maxW) size *= maxW / w;
  g.font = `${weight} ${size}px "${family}"`;
  return size;
}

function labelCanvas(v) {
  const W = 2048, H = Math.round(W * SHELL / (2 * Math.PI * R));
  const [c, g] = canvas(W, H);
  const U = (u) => ((u % 1) + 1) % 1 * W, Vy = (y) => y * H;
  const F = (du) => U(FRONT + du);
  g.fillStyle = v.base; g.fillRect(0, 0, W, H);
  // lower band carrying the speed, with pinstripes
  g.fillStyle = v.band; g.fillRect(0, Vy(0.55), W, Vy(0.33));
  g.fillStyle = v.stripe; g.fillRect(0, Vy(0.515), W, Vy(0.022)); g.fillRect(0, Vy(0.90), W, Vy(0.014));
  g.textBaseline = 'alphabetic';
  // big product word, centred on the front
  g.fillStyle = v.ink; g.textAlign = 'center';
  fitFont(g, v.word, 900, 'Inter Display', U(0.30), Vy(0.25));
  g.fillText(v.word, F(0), Vy(0.40));
  g.fillStyle = v.ink2;
  fitFont(g, v.kind, 600, 'DejaVu Sans Condensed', U(0.30), Vy(0.06));
  g.fillText(v.kind, F(0), Vy(0.48));
  // speed in the band
  g.fillStyle = v.numInk;
  fitFont(g, v.iso, 900, 'Inter Display', U(0.16), Vy(0.27));
  g.fillText(v.iso, F(-0.045), Vy(0.835));
  g.textAlign = 'left';
  fitFont(g, 'ISO ' + v.iso + '/' + v.din, 700, 'DejaVu Sans Condensed', U(0.11), Vy(0.06));
  g.fillText('ISO ' + v.iso + '/' + v.din, F(0.045), Vy(0.68));
  fitFont(g, '135-36 EXP', 700, 'DejaVu Sans Condensed', U(0.11), Vy(0.06));
  g.fillText('135-36 EXP', F(0.045), Vy(0.76));
  fitFont(g, v.process, 600, 'DejaVu Sans Condensed', U(0.11), Vy(0.05));
  g.fillText(v.process, F(0.045), Vy(0.835));
  // the app's own wordmark, small, top front
  g.fillStyle = v.ink2; g.textAlign = 'center';
  fitFont(g, 'D A R K R O O M', 700, 'Inter Display', U(0.16), Vy(0.05));
  g.fillText('D A R K R O O M', F(0.016), Vy(0.11));
  drawRabbit(g, F(-0.094), Vy(0.095), Vy(0.075), v.ink2);
  // left side: exposure guide
  g.textAlign = 'left'; g.fillStyle = v.ink2;
  const rows = v.iso === '100'
    ? ['SUN  1/125 f/16', 'HAZE  1/125 f/11', 'CLOUD  1/125 f/8', 'SHADE  1/60 f/8']
    : ['SUN  1/500 f/16', 'HAZE  1/500 f/11', 'CLOUD  1/250 f/8', 'SHADE  1/125 f/5.6'];
  g.font = `600 ${Vy(0.05)}px "DejaVu Sans Condensed"`;
  rows.forEach((t, i) => g.fillText(t, F(-0.46), Vy(0.15 + i * 0.075)));
  // right side (towards the lips): storage note
  g.font = `600 ${Vy(0.045)}px "DejaVu Sans Condensed"`;
  ['DEVELOP BEFORE 09-2028', 'LOAD IN SUBDUED LIGHT', 'KEEP COOL AND DRY'].forEach((t, i) => g.fillText(t, F(0.30), Vy(0.17 + i * 0.07)));
  // back: barcode patch
  const bx = F(0.5) - U(0.06);
  g.fillStyle = '#ffffff'; g.fillRect(bx, Vy(0.1), U(0.12), Vy(0.34));
  barcode(g, bx + U(0.008), Vy(0.13), U(0.104), Vy(0.24), v.seed, '#111');
  g.fillStyle = '#111'; g.font = `500 ${Vy(0.04)}px "DejaVu Sans Mono"`; g.fillText('0 41771 ' + v.seed + '82 4', bx + U(0.01), Vy(0.405));
  // DX code chequer (bare tin vs black paint), back bottom
  const dxX = F(0.38), dxY = Vy(0.905), cw = U(0.0105), ch = Vy(0.042);
  const r = rng(v.seed);
  for (let row = 0; row < 2; row++) for (let i = 0; i < 12; i++) {
    g.fillStyle = (i === 0 || r() > 0.5) ? '#c0c0c0' : '#0e0e0e';
    g.fillRect(dxX + i * cw, dxY + row * ch, cw, ch);
  }
  c.dx = [dxX, dxX + 12 * cw, dxY, dxY + 2 * ch];
  return c;
}

// G = roughness, B = metalness (three.js convention). DX squares are bare tin.
function labelORM(lc, v) {
  const W = lc.width, H = lc.height;
  const [c, g] = canvas(W, H);
  const n = noiseCanvas(256, 128, { base: 0, amp: 1, sx: 8, sy: 8, seed: v.seed });
  const nd = n.getContext('2d').getImageData(0, 0, 256, 128).data;
  const src = lc.getContext('2d').getImageData(0, 0, W, H).data;
  const img = g.createImageData(W, H);
  const [dxX0, dxX1, dxY0, dxY1] = lc.dx;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const o = (y * W + x) * 4;
    const nn = nd[(((y * 128 / H) | 0) * 256 + ((x * 256 / W) | 0)) * 4] / 255;
    const bare = x >= dxX0 && x < dxX1 && y >= dxY0 && y < dxY1 && src[o] > 150;
    img.data[o] = 255;
    img.data[o + 1] = (bare ? 0.22 : 0.30 + 0.12 * nn) * 255;
    img.data[o + 2] = bare ? 255 : 0;
    img.data[o + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  return c;
}

// Leader alpha: full width at the lips, long curved cut down to a half-width
// tongue, KS perforations along both edges.
function leaderAlpha(L) {
  const PX = 40, W = Math.round(L * PX), H = Math.round(FILM_W * PX);
  const [c, g] = canvas(W, H);
  g.fillStyle = '#000'; g.fillRect(0, 0, W, H);
  g.fillStyle = '#fff';
  const tongue = 16.5;
  g.beginPath();
  g.moveTo(0, 0); g.lineTo(W, 0);
  g.lineTo(W, (tongue - 3) * PX); g.quadraticCurveTo(W, tongue * PX, W - 3 * PX, tongue * PX);
  g.lineTo(26 * PX, tongue * PX);
  g.bezierCurveTo(16 * PX, tongue * PX, 12 * PX, H, 5 * PX, H);
  g.lineTo(0, H); g.closePath(); g.fill();
  g.fillStyle = '#000';
  const hole = (sx, hy) => { roundRect(g, sx * PX, (hy - 1.4) * PX, 1.98 * PX, 2.79 * PX, 0.45 * PX); g.fill(); };
  for (let s = 1.2; s < L - 2.5; s += 4.75) hole(s, 2.0);                       // top edge (y=0 is the top)
  for (let s = 1.2; s < 7.5; s += 4.75) hole(s, FILM_W - 2.0);                   // bottom edge only before the cut
  return c;
}

export async function build(THREE, item) {
  const v = VARIANTS[item.split('_')[1]];
  const group = new THREE.Group();

  // shell + label
  const lc = labelCanvas(v);
  const orm = labelORM(lc, v);
  const bump = normalFromHeight(noiseCanvas(512, 256, { base: 128, amp: 10, sx: 3, sy: 3, seed: v.seed + 1, scratches: 30 }), 0.6);
  const labelMat = new THREE.MeshPhysicalMaterial({
    map: tex(lc), roughnessMap: tex(orm, { srgb: false }), metalnessMap: tex(orm, { srgb: false }),
    normalMap: tex(bump, { srgb: false }), normalScale: new THREE.Vector2(0.25, 0.25),
    roughness: 1, metalness: 1, clearcoat: 0.6, clearcoatRoughness: 0.14,
  });
  const shell = new THREE.Mesh(new THREE.CylinderGeometry(R, R, SHELL, 192, 1, true, Math.PI), labelMat);
  shell.position.y = (Y0 + Y1) / 2;
  group.add(shell);

  // end caps (lathe, rolled rim)
  const capMat = new THREE.MeshPhysicalMaterial({ color: v.cap, metalness: v.capMetal, roughness: v.capRough, clearcoat: v.capMetal < 1 ? 0.5 : 0, clearcoatRoughness: 0.2 });
  const capProfile = [[0, 0.35], [10.2, 0.35], [10.9, 0.12], [12.3, 0.0], [12.95, 0.22], [13.15, 0.7], [13.05, 1.25], [12.7, 1.58], [12.38, 1.62]];
  const bottom = new THREE.Mesh(new THREE.LatheGeometry(capProfile.map(([r, y]) => new THREE.Vector2(r, y)), 160), capMat);
  const top = new THREE.Mesh(new THREE.LatheGeometry(capProfile.slice().reverse().map(([r, y]) => new THREE.Vector2(r, TOP - y)), 160), capMat);
  group.add(bottom, top);
  // embossed ring on the top cap
  const ring = new THREE.Mesh(new THREE.TorusGeometry(7.6, 0.28, 12, 120), capMat);
  ring.rotation.x = Math.PI / 2; ring.position.y = TOP - 0.25; group.add(ring);

  // spool ends: long keyed stub on top, short one below (black plastic)
  const plastic = new THREE.MeshPhysicalMaterial({ color: 0x0c0c0c, roughness: 0.42, clearcoat: 0.3, clearcoatRoughness: 0.35 });
  const stub = [[0, 7.0], [3.0, 7.0], [3.55, 6.75], [3.75, 6.2], [3.75, 0.6], [4.3, 0.2], [4.3, 0.0]];
  const topStub = new THREE.Mesh(new THREE.LatheGeometry(stub.map(([r, y]) => new THREE.Vector2(r, TOP - 0.3 + y)).reverse(), 96), plastic);
  group.add(topStub);
  const slotMat = new THREE.MeshStandardMaterial({ color: 0x020202, roughness: 0.9 });
  for (const a of [0, Math.PI / 2]) {
    const slot = new THREE.Mesh(new THREE.BoxGeometry(7.8, 1.6, 1.25), slotMat);
    slot.position.y = TOP - 0.3 + 7.0 - 0.75; slot.rotation.y = a; group.add(slot);
  }
  const botStub = new THREE.Mesh(new THREE.LatheGeometry([[0, -1.3], [3.2, -1.3], [3.7, -1.0], [3.75, 0.4]].map(([r, y]) => new THREE.Vector2(r, y)), 96), plastic);
  group.add(botStub);

  // light-trap mouth at +X: extruded lip blended into the shell, velvet in the slot
  const lipShape = new THREE.Shape();
  const a0 = -0.42, a1 = 0.30;
  lipShape.moveTo(R * Math.cos(a0) - 0.6, R * Math.sin(a0));
  lipShape.quadraticCurveTo(R + 0.9, -3.2, R + 2.5, -1.9);
  lipShape.quadraticCurveTo(R + 3.0, -1.5, R + 3.0, -0.95);
  lipShape.lineTo(R + 3.0, 0.95);
  lipShape.quadraticCurveTo(R + 3.0, 1.9, R + 2.1, 2.25);
  lipShape.quadraticCurveTo(R + 0.5, 2.9, R * Math.cos(a1) - 0.6, R * Math.sin(a1));
  lipShape.closePath();
  const lipGeo = new THREE.ExtrudeGeometry(lipShape, { depth: SHELL - 0.6, bevelEnabled: true, bevelThickness: 0.3, bevelSize: 0.3, bevelSegments: 3, curveSegments: 24 });
  lipGeo.rotateX(-Math.PI / 2);
  const lipMat = new THREE.MeshPhysicalMaterial({ color: new THREE.Color(v.base), roughness: 0.32, metalness: 0.0, clearcoat: 0.6, clearcoatRoughness: 0.15 });
  const lip = new THREE.Mesh(lipGeo, lipMat);
  lip.position.y = Y0 + 0.3;
  group.add(lip);
  const velvet = new THREE.MeshPhysicalMaterial({ color: 0x050505, roughness: 1, sheen: 1, sheenRoughness: 0.6, sheenColor: new THREE.Color(0x3a3a3a) });
  for (const z of [-0.55, 0.55]) {
    const strip = new THREE.Mesh(new THREE.BoxGeometry(0.8, SHELL - 2.4, 0.95), velvet);
    strip.position.set(R + 2.8, (Y0 + Y1) / 2, z); group.add(strip);
  }

  // film leader leaving the slot, curling gently backwards
  const L = 34;
  const alpha = tex(leaderAlpha(L), { srgb: false });
  const segs = 160;
  const geo = new THREE.PlaneGeometry(L, FILM_W, segs, 1);
  const pos = geo.attributes.position;
  const k = 1 / 34;
  // integrate the centreline
  const pts = [];
  let x = R + 2.9, z = 0, ang = 0;
  const ds = L / segs;
  for (let i = 0; i <= segs; i++) {
    pts.push([x, z, ang]);
    const s = i * ds;
    ang = -k * s * (0.4 + 0.6 * Math.min(1, s / 18));
    x += Math.cos(ang) * ds; z += Math.sin(ang) * ds;
  }
  for (let i = 0; i < pos.count; i++) {
    const px = pos.getX(i), py = pos.getY(i);
    const idx = Math.round((px + L / 2) / ds);
    const [cx, cz] = pts[Math.min(segs, Math.max(0, idx))];
    pos.setXYZ(i, cx, (Y0 + Y1) / 2 + py, cz);
  }
  geo.computeVertexNormals();
  const filmMat = new THREE.MeshPhysicalMaterial({
    color: v.film, roughness: 0.45, metalness: 0, alphaMap: alpha, alphaTest: 0.5, side: THREE.DoubleSide,
    sheen: 0.08, sheenColor: new THREE.Color(v.filmSheen), sheenRoughness: 0.6, clearcoat: 0.12, clearcoatRoughness: 0.35,
  });
  group.add(new THREE.Mesh(geo, filmMat));

  // composition: quarter turn so the front label faces the lens and the
  // leader trails off to the right
  group.rotation.y = ROT;
  const cy = TOP / 2 + 2;
  return {
    object: group,
    floorY: -1.3,
    exposure: 1.35,
    camera: { fov: 20, position: [0, cy + 32, 188], target: [3, cy - 1, 0] },
    envRotation: 0,
  };
}
