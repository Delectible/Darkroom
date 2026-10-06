// Y2K clamshell camera phone, opened. Original design.
import { rbox, slab, plastic, paint, decal, cyl, lens } from '/lib/parts.js';
import { canvas, tex, roundRect } from '/lib/tex.js';

function screenCanvas() {
  // 128x160 pixel art, upscaled with nearest-neighbour
  const [s, g] = canvas(128, 160);
  const sky = ['#1b1446', '#2d1a5e', '#4a1f6e', '#7a2a72', '#b83c6a', '#e8665a', '#f79a52', '#ffc861'];
  sky.forEach((c, i) => { g.fillStyle = c; g.fillRect(0, 14 + i * 9, 128, 9); });
  g.fillStyle = '#ffd98a'; g.beginPath(); g.arc(64, 92, 16, 0, Math.PI * 2); g.fill();
  g.fillStyle = '#ffeab8'; g.beginPath(); g.arc(64, 92, 11, 0, Math.PI * 2); g.fill();
  // sea with reflection stripes
  for (let i = 0; i < 6; i++) { g.fillStyle = ['#2b2a6e', '#24245c', '#1e1f4f', '#191a43', '#151638', '#11122e'][i]; g.fillRect(0, 96 + i * 6, 128, 6); }
  g.fillStyle = '#ffcf7a'; for (let i = 0; i < 6; i++) g.fillRect(64 - 14 + i * 2, 98 + i * 6, 28 - i * 4, 2);
  // hills silhouette
  g.fillStyle = '#140f2c';
  for (let x = 0; x < 128; x++) { const y = 92 + Math.round(6 * Math.sin(x / 11) + 3 * Math.sin(x / 4.3)); g.fillRect(x, y, 1, 96 - y + 2); }
  g.fillStyle = '#0b0820';
  for (let x = 0; x < 128; x++) { const y = 140 + Math.round(4 * Math.sin(x / 9 + 1)); g.fillRect(x, y, 1, 160 - y); }
  // status bar
  g.fillStyle = '#0b0b16'; g.fillRect(0, 0, 128, 14);
  g.fillStyle = '#9fe870'; for (let i = 0; i < 5; i++) g.fillRect(3 + i * 3, 10 - i * 2, 2, 2 + i * 2);
  g.fillStyle = '#ffffff'; g.font = 'bold 10px "DejaVu Sans Mono"'; g.textBaseline = 'top'; g.fillText('12:08', 48, 2);
  g.strokeStyle = '#9fe870'; g.strokeRect(106.5, 3.5, 16, 7); g.fillStyle = '#9fe870'; g.fillRect(108, 5, 11, 4); g.fillRect(123, 5, 2, 4);
  // soft key bar
  g.fillStyle = 'rgba(8,8,20,0.85)'; g.fillRect(0, 146, 128, 14);
  g.fillStyle = '#ffffff'; g.font = 'bold 9px "DejaVu Sans"'; g.fillText('Menu', 4, 148); g.fillText('Cam', 102, 148);
  const [c, cg] = canvas(512, 640);
  cg.imageSmoothingEnabled = false; cg.drawImage(s, 0, 0, 512, 640);
  // faint pixel grid
  cg.fillStyle = 'rgba(0,0,0,0.07)';
  for (let x = 0; x < 512; x += 4) cg.fillRect(x, 0, 1, 640);
  for (let y = 0; y < 640; y += 4) cg.fillRect(0, y, 512, 1);
  return c;
}

function keyCanvas(main, sub, color = '#1d1f24') {
  const [c, g] = canvas(220, 130);
  g.fillStyle = '#e6e8ec'; g.fillRect(0, 0, 220, 130);
  g.fillStyle = color; g.textBaseline = 'middle'; g.textAlign = 'center';
  g.font = `700 78px "Inter Display"`; g.fillText(main, sub ? 82 : 110, 68);
  if (sub) { g.font = `600 34px "DejaVu Sans Condensed"`; g.fillStyle = '#5b5f68'; g.fillText(sub, 160, 72); }
  return c;
}

export async function build(THREE) {
  const root = new THREE.Group();
  const shellPaint = paint(0x8f9cb0, { rough: 0.3, metal: 0.55 });
  const inner = plastic(0x22252b, { rough: 0.35, texture: 0.05, clearcoat: 0.4 });
  const W = 46, HB = 86, HL = 88, T = 10;

  // base (keypad half): outer shell + inner panel
  const base = new THREE.Group();
  const bShell = slab(W, HB, T, 9, 2.4, shellPaint); base.add(bShell);
  const bPanel = slab(W - 3, HB - 6, 0.8, 7.5, 0.3, inner); bPanel.position.set(0, -1.5, T / 2 + 0.1); base.add(bPanel);
  // keys
  const keyMat = (main, sub) => new THREE.MeshPhysicalMaterial({ map: tex(keyCanvas(main, sub)), roughness: 0.3, metalness: 0.15, clearcoat: 0.8, clearcoatRoughness: 0.15 });
  const labels = [['1', ''], ['2', 'ABC'], ['3', 'DEF'], ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'], ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'], ['*', ''], ['0', '+'], ['#', '']];
  labels.forEach(([m, s], i) => {
    const col = i % 3, row = Math.floor(i / 3);
    const k = rbox(12.6, 7.4, 1.6, 1.0, keyMat(m, s));
    k.position.set((col - 1) * 13.6, 6 - row * 9.6, T / 2 + 0.9);
    base.add(k);
  });
  // navigation ring + centre key
  const navMat = paint(0xc9ced6, { rough: 0.25, metal: 0.8 });
  const nav = new THREE.Mesh(new THREE.TorusGeometry(7.2, 2.1, 24, 96), navMat); nav.scale.z = 0.45; nav.position.set(0, 26, T / 2 + 0.9); base.add(nav);
  const ok = cyl(4.2, 1.6, navMat, 48); ok.rotation.x = Math.PI / 2; ok.position.set(0, 26, T / 2 + 0.9); base.add(ok);
  // soft keys, call / end
  const sk = (x, y, mat) => { const k = rbox(9, 5, 1.6, 1.2, mat); k.position.set(x, y, T / 2 + 0.9); base.add(k); };
  sk(-15.5, 31, navMat); sk(15.5, 31, navMat);
  const callMat = new THREE.MeshPhysicalMaterial({ map: tex((() => { const [c, g] = canvas(180, 100); g.fillStyle = '#e6e8ec'; g.fillRect(0, 0, 180, 100); g.fillStyle = '#1aa648'; roundRect(g, 55, 35, 70, 30, 12); g.fill(); return c; })()), roughness: 0.3, clearcoat: 0.8 });
  const endMat = new THREE.MeshPhysicalMaterial({ map: tex((() => { const [c, g] = canvas(180, 100); g.fillStyle = '#e6e8ec'; g.fillRect(0, 0, 180, 100); g.fillStyle = '#d42a2a'; roundRect(g, 55, 35, 70, 30, 12); g.fill(); return c; })()), roughness: 0.3, clearcoat: 0.8 });
  sk(-15.5, 21, callMat); sk(15.5, 21, endMat);
  // mic slot
  const mic = rbox(5, 1.2, 0.6, 0.5, new THREE.MeshStandardMaterial({ color: 0x050505 })); mic.position.set(0, -HB / 2 + 5, T / 2 + 0.5); base.add(mic);
  root.add(base);

  // hinge barrel
  const hingeY = HB / 2 + 1.0;
  const barrel = new THREE.Mesh(new THREE.CylinderGeometry(T / 2 + 0.2, T / 2 + 0.2, W - 12, 64), shellPaint);
  barrel.rotation.z = Math.PI / 2; barrel.position.set(0, hingeY, 0); root.add(barrel);
  const capL = new THREE.Mesh(new THREE.CylinderGeometry(T / 2, T / 2, 5.6, 64), paint(0xc3c9d2, { rough: 0.15, metal: 1 }));
  capL.rotation.z = Math.PI / 2; capL.position.set(-W / 2 + 3, hingeY, 0); root.add(capL);
  const capR = capL.clone(); capR.position.x = W / 2 - 3; root.add(capR);

  // lid (screen half), tilted forward around the hinge like a real open flip phone
  const lid = new THREE.Group();
  const lShell = slab(W, HL, T * 0.8, 10, 2.2, shellPaint); lShell.position.y = HL / 2 + 1; lid.add(lShell);
  const lPanel = slab(W - 3, HL - 5, 0.8, 8, 0.3, inner); lPanel.position.set(0, HL / 2 + 1, T * 0.4 + 0.1); lid.add(lPanel);
  // screen under glass, glowing
  const scr = new THREE.Mesh(new THREE.PlaneGeometry(31, 38.75), new THREE.MeshStandardMaterial({ map: tex(screenCanvas()), emissiveMap: tex(screenCanvas()), emissive: 0xffffff, emissiveIntensity: 0.9, roughness: 1 }));
  scr.position.set(0, HL / 2 + 6, T * 0.4 + 0.6); lid.add(scr);
  const glass = rbox(37, 50, 0.6, 1.5, new THREE.MeshPhysicalMaterial({ color: 0x050608, roughness: 0.02, transmission: 0.0, clearcoat: 1, transparent: false, opacity: 1 }));
  glass.position.set(0, HL / 2 + 4.5, T * 0.4 + 0.25); lid.add(glass);
  // earpiece
  const ear = rbox(10, 1.8, 0.6, 0.8, new THREE.MeshStandardMaterial({ color: 0x050505, roughness: 0.8 })); ear.position.set(0, HL - 4, T * 0.4 + 0.5); lid.add(ear);
  const brand = decal(24, 4, (c, w, h) => { c.fillStyle = '#c7ccd4'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.font = `800 ${h * 0.7}px "Inter Display"`; c.fillText('RETROCAM', w / 2, h / 2); }, { px: 40, rough: 0.3, metal: 0.7 });
  brand.position.set(0, HL / 2 - 23.5, T * 0.4 + 0.55); lid.add(brand);
  lid.position.set(0, hingeY, -0.6);
  lid.rotation.x = 0.26; // opened past flat would face away: tilt the screen half toward the viewer
  root.add(lid);

  root.rotation.y = 0.42; root.rotation.x = -0.08;
  const holder = new THREE.Group(); holder.add(root); holder.position.y = HB / 2 + 6;
  return { object: holder, floorY: 0, exposure: 1.15, env: { ambient: 0.22 }, camera: { fov: 20, position: [0, 120, 520], target: [0, 92, 0] } };
}
