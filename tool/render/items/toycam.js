// Toy pixel camera (original design, after late-90s handheld game camera
// add-ons and kids' digital cameras): chunky two-tone plastic, a big
// googly lens on a swivel ball, oversized buttons, a tiny 128 px badge.
import { rbox, plastic, lens, decal, cyl } from '/lib/parts.js';
import { roundRect } from '/lib/tex.js';

export async function build(THREE) {
  const g = new THREE.Group();
  const W = 96, H = 64, D = 30;
  const blue = plastic(0x2f6fd6, { rough: 0.35, texture: 0.2, clearcoat: 0.6 });
  const yellow = plastic(0xffc928, { rough: 0.35, texture: 0.15, clearcoat: 0.6 });
  const red = plastic(0xe0352b, { rough: 0.3, texture: 0, clearcoat: 1 });
  g.add(rbox(W, H, D, 12, blue, 8));
  // handle bumps either side
  for (const x of [-W / 2 + 4, W / 2 - 4]) { const h = rbox(18, H + 6, D + 6, 9, yellow, 6); h.position.x = x; g.add(h); }
  // swivel eyeball with the lens
  const ballMat = plastic(0xf4f1ea, { rough: 0.25, texture: 0, clearcoat: 1 });
  const ball = new THREE.Mesh(new THREE.SphereGeometry(17, 64, 48), ballMat); ball.position.set(0, H / 2 + 8, 0); g.add(ball);
  const L = lens({ profile: [[0, 0], [9.5, 0], [9.5, 2.5], [8, 3.5], [6, 4]], glassR: 5.6, glassZ: 4.2, mat: plastic(0x111111, { rough: 0.3, texture: 0 }) });
  L.position.set(0, H / 2 + 8, 14.8); g.add(L);
  const neck = cyl(7, 10, yellow, 32); neck.position.set(0, H / 2 - 1, 0); g.add(neck);
  // front face: little screen-print badge and big buttons
  const badge = decal(46, 22, (c, w, h) => {
    c.fillStyle = '#ffffff'; roundRect(c, 0, 0, w, h, h * 0.18); c.fill();
    c.fillStyle = '#2f6fd6'; c.font = `900 ${h * 0.34}px "Inter Display"`; c.textBaseline = 'alphabetic'; c.fillText('PIXEL CAM', w * 0.07, h * 0.46);
    c.fillStyle = '#e0352b'; c.font = `800 ${h * 0.2}px "DejaVu Sans Condensed"`; c.fillText('128 x 112 · 4 TONES', w * 0.07, h * 0.82);
    // pixel squares
    const s = h * 0.1; ['#e0352b', '#ffc928', '#35b44a', '#2f6fd6'].forEach((col, i) => { c.fillStyle = col; c.fillRect(w * 0.78 + (i % 2) * s * 1.2, h * 0.12 + Math.floor(i / 2) * s * 1.2, s, s); });
  }, { px: 20, rough: 0.4 });
  badge.position.set(0, 4, D / 2 + 0.1); g.add(badge);
  const shutter = cyl(6, 4, red, 40); shutter.position.set(-W / 2 + 6, H / 2 + 5, 0); g.add(shutter);
  for (const [x, col] of [[-12, 0x35b44a], [12, 0xffffff]]) { const b = cyl(4, 3, plastic(col, { rough: 0.3, texture: 0, clearcoat: 1 }), 32); b.rotation.x = Math.PI / 2; b.position.set(x, -H / 2 + 12, D / 2 + 1); g.add(b); }
  // wrist strap loop
  const loop = new THREE.Mesh(new THREE.TorusGeometry(8, 1.6, 12, 40), plastic(0xe0352b, { rough: 0.8, texture: 0.4 }));
  loop.position.set(W / 2 + 10, -H / 2 + 6, 0); loop.rotation.y = Math.PI / 2; g.add(loop);

  g.rotation.y = -0.4; g.rotation.x = 0.05;
  const holder = new THREE.Group(); holder.add(g); holder.position.y = H / 2 + 4;
  return { object: holder, floorY: 0, exposure: 1.1, env: { ambient: 0.3 }, camera: { fov: 20, position: [0, 130, 360], target: [0, 40, 0] } };
}
