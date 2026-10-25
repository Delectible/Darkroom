// Single-use camera (original design, after the green cardboard-wrapped
// drugstore disposables): black plastic box, printed card wrap, tiny lens,
// flash window and charge button, thumb wheel and frame counter on top.
import { rbox, slab, plastic, lens, decal, cyl } from '/lib/parts.js';
import { canvas, tex, roundRect, barcode } from '/lib/tex.js';
import { drawRabbit } from '/lib/logo.js';

export async function build(THREE) {
  const g = new THREE.Group();
  const W = 108, H = 56, D = 34;
  const black = plastic(0x141516, { rough: 0.5, texture: 0.25 });
  g.add(rbox(W, H, D, 4, black, 6));

  // printed card wrap: front and back faces with a gap for lens / flash
  const front = decal(W - 4, H - 8, (c, w, h) => {
    const grd = c.createLinearGradient(0, 0, 0, h);
    grd.addColorStop(0, '#0f8a4a'); grd.addColorStop(1, '#0a6a39');
    c.fillStyle = grd; roundRect(c, 0, 0, w, h, h * 0.06); c.fill();
    // white swoosh band
    c.fillStyle = '#ffffff'; c.beginPath(); c.moveTo(0, h * 0.62); c.bezierCurveTo(w * 0.3, h * 0.48, w * 0.6, h * 0.78, w, h * 0.6);
    c.lineTo(w, h * 0.74); c.bezierCurveTo(w * 0.6, h * 0.92, w * 0.3, h * 0.62, 0, h * 0.76); c.closePath(); c.fill();
    c.fillStyle = '#d6232a'; c.fillRect(0, h * 0.86, w, h * 0.06);
    // lens and flash openings are physical parts; keep their area dark
    c.fillStyle = '#121212';
    c.beginPath(); c.arc(w * 0.28, h * 0.38, h * 0.2, 0, Math.PI * 2); c.fill();
    roundRect(c, w * 0.66, h * 0.08, w * 0.3, h * 0.2, h * 0.03); c.fill();
    c.fillStyle = '#ffffff'; c.textBaseline = 'alphabetic';
    c.font = `900 ${h * 0.115}px "Inter Display"`; c.fillText('SINGLE-USE', w * 0.43, h * 0.45);
    c.font = `700 ${h * 0.068}px "DejaVu Sans Condensed"`; c.fillText('CAMERA  ·  WITH FLASH', w * 0.43, h * 0.54);
    c.fillStyle = '#0a6a39'; c.font = `900 ${h * 0.13}px "Inter Display"`; c.fillText('27', w * 0.30, h * 0.78);
    c.font = `700 ${h * 0.06}px "DejaVu Sans Condensed"`; c.fillText('EXP  ·  ISO 400', w * 0.39, h * 0.77);
    c.fillStyle = '#ffffff'; c.font = `700 ${h * 0.06}px "Inter Display"`; c.fillText('D A R K R O O M', w * 0.66, h * 0.97 - h * 0.11 + h * 0.07);
    drawRabbit(c, w * 0.62, h * 0.94 - h * 0.04, h * 0.06, '#ffffff');
  }, { px: 14, rough: 0.55 });
  front.position.z = D / 2 + 0.05; g.add(front);
  const back = decal(W - 4, H - 8, (c, w, h) => {
    c.fillStyle = '#0c7a42'; roundRect(c, 0, 0, w, h, h * 0.06); c.fill();
    c.fillStyle = '#fff'; c.fillRect(w * 0.06, h * 0.2, w * 0.3, h * 0.5);
    barcode(c, w * 0.08, h * 0.24, w * 0.26, h * 0.36, 27, '#111');
    c.fillStyle = '#ffffff'; c.font = `600 ${h * 0.06}px "DejaVu Sans Condensed"`;
    ['DO NOT OPEN', 'RETURN WHOLE CAMERA', 'FOR PROCESSING'].forEach((t, i) => c.fillText(t, w * 0.45, h * (0.3 + i * 0.1)));
  }, { px: 10, rough: 0.55 });
  back.position.z = -D / 2 - 0.05; back.rotation.y = Math.PI; g.add(back);

  // lens: small black cone with a flat element
  const L = lens({ profile: [[0, 0], [11, 0], [10.5, 2], [8, 3.5], [6.2, 4]], glassR: 5.4, glassZ: 4.1, mat: plastic(0x0c0c0c, { rough: 0.35, texture: 0 }) });
  L.position.set(-W / 2 + 0.28 * (W - 4) + 2, H / 2 - 4 - 0.38 * (H - 8), D / 2); g.add(L);
  // flash window
  const [fc, fg] = canvas(256, 128);
  fg.fillStyle = '#f4f3ee'; fg.fillRect(0, 0, 256, 128);
  for (let x = 0; x < 256; x += 6) { fg.fillStyle = `rgba(0,0,0,${0.08 + 0.06 * Math.sin(x)})`; fg.fillRect(x, 0, 2, 128); }
  const flash = rbox(30, 10, 2, 0.8, new THREE.MeshPhysicalMaterial({ map: tex(fc), roughness: 0.25, transmission: 0.25, thickness: 0.5, clearcoat: 1 }));
  flash.position.set(-W / 2 + 2 + 0.81 * (W - 4), H / 2 - 4 - 0.18 * (H - 8), D / 2 + 0.4); g.add(flash);
  // flash charge button below it, viewfinder window above the lens
  const btn = rbox(7, 9, 3, 1.2, plastic(0xe6e2d8, { rough: 0.4, texture: 0 })); btn.position.set(W / 2 - 9, 0, D / 2 + 1); g.add(btn);
  const vf = rbox(9, 6, 2, 1, new THREE.MeshPhysicalMaterial({ color: 0x0a0d12, roughness: 0.03, clearcoat: 1 }));
  vf.position.set(-6, H / 2 - 9, D / 2 + 0.3); g.add(vf);
  // top: shutter button, frame counter window, thumb wheel at the back right
  const sh = cyl(4.2, 2.4, plastic(0x1e1f20, { rough: 0.35, texture: 0 }), 32); sh.position.set(W / 2 - 22, H / 2 + 1, 4); g.add(sh);
  const counter = rbox(7, 1, 5, 0.8, new THREE.MeshPhysicalMaterial({ color: 0x9fb3a5, roughness: 0.1, transmission: 0.4, thickness: 1, clearcoat: 1 }));
  counter.position.set(W / 2 - 34, H / 2 + 0.3, 6); g.add(counter);
  const cnt = decal(5, 3.4, (c, w, h) => { c.fillStyle = '#111'; c.font = `800 ${h * 0.8}px "DejaVu Sans"`; c.textBaseline = 'middle'; c.fillText('27', w * 0.12, h / 2); }, { px: 40 });
  cnt.rotation.x = -Math.PI / 2; cnt.position.set(W / 2 - 34, H / 2 + 0.85, 6); g.add(cnt);
  const wheel = cyl(9, 5, plastic(0x1a1a1a, { rough: 0.6, texture: 0.6 }), 40); wheel.position.set(W / 2 - 10, H / 2 - 2, -D / 2 + 6); g.add(wheel);
  for (let i = 0; i < 40; i++) { const r = rbox(1, 5.2, 1.2, 0.3, black); const a = i / 40 * Math.PI * 2; r.position.set(W / 2 - 10 + Math.cos(a) * 9, H / 2 - 2, -D / 2 + 6 + Math.sin(a) * 9); r.rotation.y = -a; g.add(r); }

  g.rotation.y = -0.45; g.rotation.x = 0.06;
  const holder = new THREE.Group(); holder.add(g); holder.position.y = H / 2 + 0.5;
  return { object: holder, floorY: 0, exposure: 1.15, env: { ambient: 0.28 }, camera: { fov: 20, position: [0, 120, 330], target: [0, 28, 0] } };
}
