// Super 8 film cartridge. Original body and label design.
import { canvas, tex, noiseCanvas, normalFromHeight, roundRect, barcode } from '/lib/tex.js';

const W = 70, H = 66, D = 21;           // body (mm)
const NOTCH = { x0: 0, x1: 10, y0: 11, y1: 36 };
const HUB = { x: 47, y: 41, r: 8.5 };

function rr(shape, x, y, w, h, r) {
  shape.moveTo(x + r, y); shape.lineTo(x + w - r, y); shape.quadraticCurveTo(x + w, y, x + w, y + r);
  shape.lineTo(x + w, y + h - r); shape.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  shape.lineTo(x + r, y + h); shape.quadraticCurveTo(x, y + h, x, y + h - r); shape.lineTo(x, y + r);
  shape.quadraticCurveTo(x, y, x + r, y);
}

function outline(THREE) {
  const s = new THREE.Shape();
  const r = 4;
  s.moveTo(r, 0);
  s.lineTo(W - r, 0); s.quadraticCurveTo(W, 0, W, r);
  s.lineTo(W, H - r); s.quadraticCurveTo(W, H, W - r, H);
  // filter-key notch on the top edge
  s.lineTo(60, H); s.lineTo(60, H - 4.5); s.lineTo(53, H - 4.5); s.lineTo(53, H);
  s.lineTo(r, H); s.quadraticCurveTo(0, H, 0, H - r);
  // film gate notch on the left edge
  s.lineTo(0, NOTCH.y1); s.lineTo(NOTCH.x1 - 1.2, NOTCH.y1); s.quadraticCurveTo(NOTCH.x1, NOTCH.y1, NOTCH.x1, NOTCH.y1 - 1.2);
  s.lineTo(NOTCH.x1, NOTCH.y0 + 1.2); s.quadraticCurveTo(NOTCH.x1, NOTCH.y0, NOTCH.x1 - 1.2, NOTCH.y0); s.lineTo(0, NOTCH.y0);
  s.lineTo(0, r); s.quadraticCurveTo(0, 0, r, 0);
  const hole = new THREE.Path(); hole.absarc(HUB.x, HUB.y, HUB.r, 0, Math.PI * 2, true);
  s.holes.push(hole);
  return s;
}

function labelCanvas() {
  const PX = 24, w = 56 * PX, h = 58 * PX;
  const [c, g] = canvas(w, h);
  // label occupies x 12..68, y 4..62 in body coordinates
  const X = (bx) => (bx - 12) * PX, Y = (by) => (62 - by) * PX;
  g.fillStyle = '#efe6d2'; g.fillRect(0, 0, w, h);
  // deep blue upper field
  g.fillStyle = '#183a6b'; g.fillRect(0, 0, w, Y(30));
  // sunrise bands
  const bands = ['#f6b23c', '#ef8a2e', '#d9582a'];
  bands.forEach((col, i) => { g.fillStyle = col; g.fillRect(0, Y(30) + i * 2.2 * PX, w, 2.2 * PX); });
  // sun disc behind the hub, partly hidden by the hole
  g.fillStyle = '#f6b23c'; g.beginPath(); g.arc(X(HUB.x), Y(HUB.y), 13 * PX, 0, Math.PI * 2); g.fill();
  g.fillStyle = '#183a6b'; g.beginPath(); g.arc(X(HUB.x), Y(HUB.y), 11.2 * PX, 0, Math.PI * 2); g.fill();
  // format name
  g.fillStyle = '#f4ead6'; g.textBaseline = 'alphabetic'; g.textAlign = 'left';
  g.font = `900 ${9.5 * PX}px "Inter Display"`;
  g.fillText('S8', X(14), Y(46));
  g.font = `700 ${3.0 * PX}px "Inter Display"`;
  g.fillText('SUPER 8 FILM', X(14.3), Y(40.5));
  g.font = `600 ${2.2 * PX}px "DejaVu Sans Condensed"`; g.fillStyle = '#c9d6ea';
  g.fillText('COLOR REVERSAL', X(14.3), Y(37.2));
  g.fillText('DAYLIGHT 100D', X(14.3), Y(34.4));
  // lower cream panel
  g.fillStyle = '#2a2420';
  g.font = `800 ${4.2 * PX}px "Inter Display"`; g.fillText('100D', X(14), Y(16.5));
  g.font = `600 ${2.1 * PX}px "DejaVu Sans Condensed"`;
  g.fillText('15 m · 50 ft · 18/24 fps', X(14.3), Y(12.6));
  g.fillText('PROCESS E-6', X(14.3), Y(9.6));
  g.font = `800 ${2.5 * PX}px "Inter Display"`; g.textAlign = 'right';
  g.fillText('RETROCAM', X(66), Y(16.5));
  barcode(g, X(50), Y(13.4), 15 * PX, 5 * PX, 5, '#2a2420');
  g.font = `500 ${1.5 * PX}px "DejaVu Sans Mono"`; g.fillText('0 41771 2208 9', X(66), Y(6.4));
  // thin keyline
  g.strokeStyle = 'rgba(0,0,0,0.25)'; g.lineWidth = 0.3 * PX; g.strokeRect(0.6 * PX, 0.6 * PX, w - 1.2 * PX, h - 1.2 * PX);
  return c;
}

export async function build(THREE) {
  const group = new THREE.Group();
  const grain = normalFromHeight(noiseCanvas(512, 512, { base: 128, amp: 60, sx: 2, sy: 2, octaves: 2, seed: 4 }), 1.4);
  const grainTex = tex(grain, { srgb: false, repeat: true }); grainTex.repeat.set(4, 4);
  const body = new THREE.MeshPhysicalMaterial({ color: 0x2b2c2e, roughness: 0.62, metalness: 0, normalMap: grainTex, normalScale: new THREE.Vector2(0.35, 0.35), clearcoat: 0.15, clearcoatRoughness: 0.5 });
  const geo = new THREE.ExtrudeGeometry(outline(THREE), { depth: D - 1.6, bevelEnabled: true, bevelThickness: 0.8, bevelSize: 0.8, bevelSegments: 4, curveSegments: 32 });
  const shell = new THREE.Mesh(geo, body);
  shell.position.z = -D / 2 + 0.8;
  group.add(shell);

  // seam line around the middle (two halves)
  const seamMat = new THREE.MeshStandardMaterial({ color: 0x0b0b0b, roughness: 0.9 });
  const seam3 = new THREE.Mesh(new THREE.BoxGeometry(0.35, H - 8, 0.25), seamMat); seam3.position.set(W + 0.81, H / 2, 0); group.add(seam3);

  // grip ribs on the right edge
  for (let i = 0; i < 9; i++) {
    const rib = new THREE.Mesh(new THREE.BoxGeometry(0.9, 1.0, D - 6), body);
    rib.position.set(W + 0.9, 8 + i * 2.4, 0); group.add(rib);
  }

  // label (with the hub hole cut out)
  const ls = new THREE.Shape(); rr(ls, 12, 4, 56, 58, 1.2);
  const lh = new THREE.Path(); lh.absarc(HUB.x, HUB.y, HUB.r + 1.2, 0, Math.PI * 2, true); ls.holes.push(lh);
  const lgeo = new THREE.ShapeGeometry(ls, 48);
  const uv = lgeo.attributes.uv, lp = lgeo.attributes.position;
  for (let i = 0; i < lp.count; i++) uv.setXY(i, (lp.getX(i) - 12) / 56, (lp.getY(i) - 4) / 58);
  const labelMat = new THREE.MeshPhysicalMaterial({ map: tex(labelCanvas()), roughness: 0.45, clearcoat: 0.3, clearcoatRoughness: 0.35 });
  const label = new THREE.Mesh(lgeo, labelMat); label.position.z = D / 2 + 0.06; group.add(label);

  // take-up hub seen through the hole: black keyed core with three teeth
  const hubMat = new THREE.MeshPhysicalMaterial({ color: 0x0d0d0d, roughness: 0.4, clearcoat: 0.3 });
  const hub = new THREE.Mesh(new THREE.CylinderGeometry(6.2, 6.2, D - 3, 64), hubMat);
  hub.rotation.x = Math.PI / 2; hub.position.set(HUB.x, HUB.y, 0); group.add(hub);
  const hubIn = new THREE.Mesh(new THREE.CylinderGeometry(3.4, 3.4, D - 2, 48), new THREE.MeshStandardMaterial({ color: 0x030303, roughness: 0.8 }));
  hubIn.rotation.x = Math.PI / 2; hubIn.position.set(HUB.x, HUB.y, 0.3); group.add(hubIn);
  for (let k = 0; k < 3; k++) {
    const a = k * Math.PI * 2 / 3 + 0.3;
    const tooth = new THREE.Mesh(new THREE.BoxGeometry(1.6, 2.4, D - 2.4), hubMat);
    tooth.position.set(HUB.x + Math.cos(a) * 3.6, HUB.y + Math.sin(a) * 3.6, 0.2); tooth.rotation.z = a + Math.PI / 2; group.add(tooth);
  }
  // wound film visible around the core (dark brown edge of the roll)
  const roll = new THREE.Mesh(new THREE.RingGeometry(6.25, HUB.r + 0.2, 64), new THREE.MeshPhysicalMaterial({ color: 0x3a2418, roughness: 0.35, clearcoat: 0.5 }));
  roll.position.set(HUB.x, HUB.y, D / 2 - 3.5); group.add(roll);

  // film across the gate notch, with one row of perforations
  const PX = 60, fw = 8, fl = NOTCH.y1 - NOTCH.y0 + 2;
  const [fc, fg] = canvas(fw * PX, fl * PX);
  fg.fillStyle = '#fff'; fg.fillRect(0, 0, fw * PX, fl * PX); fg.fillStyle = '#000';
  for (let y = 1.0; y < fl - 1; y += 4.23) { roundRect(fg, 0.5 * PX, y * PX, 0.91 * PX, 1.14 * PX, 0.15 * PX); fg.fill(); }
  const filmMat = new THREE.MeshPhysicalMaterial({ color: 0x2a1a12, roughness: 0.25, clearcoat: 0.6, clearcoatRoughness: 0.1, alphaMap: tex(fc, { srgb: false }), alphaTest: 0.5, side: THREE.DoubleSide });
  const film = new THREE.Mesh(new THREE.PlaneGeometry(fw, fl), filmMat);
  film.position.set(1.0 + fw / 2, (NOTCH.y0 + NOTCH.y1) / 2, D / 2 - 5); group.add(film);
  // pressure pad behind the film
  const pad = new THREE.Mesh(new THREE.BoxGeometry(9.0, NOTCH.y1 - NOTCH.y0 - 2, 1.2), new THREE.MeshStandardMaterial({ color: 0x121212, roughness: 0.7 }));
  pad.position.set(5.0, (NOTCH.y0 + NOTCH.y1) / 2, D / 2 - 7.5); group.add(pad);

  // centre the cartridge, stand it up with a slight turn
  group.position.set(-W / 2, 0.8, 0);
  const holder = new THREE.Group(); holder.add(group);
  holder.rotation.y = 0.45;
  return {
    object: holder,
    floorY: 0,
    exposure: 1.3,
    camera: { fov: 20, position: [0, 66, 260], target: [0, 33, 0] },
  };
}
