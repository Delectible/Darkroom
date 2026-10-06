// 1990s tape camcorder (original design): long body, big lens and hood,
// rear viewfinder tube with eyecup, padded hand strap.
import { rbox, slab, plastic, paint, lens, decal, cyl, rubber, brushedMetal } from '/lib/parts.js';
import { canvas, tex, roundRect } from '/lib/tex.js';

export async function build(THREE) {
  const root = new THREE.Group();
  // body runs along Z (lens at +Z), width along X
  const L = 150, H = 78, Wd = 64;
  const bodyMat = plastic(0x2e3033, { rough: 0.48, texture: 0.35 });
  const dark = plastic(0x18191b, { rough: 0.45, texture: 0.2 });
  const silver = paint(0x9fa4aa, { rough: 0.35, metal: 0.7, clearcoat: 0.4 });
  const chrome = new THREE.MeshPhysicalMaterial({ color: 0xd9d9d9, metalness: 1, roughness: 0.15 });

  const body = rbox(Wd, H, L, 9, bodyMat, 8); root.add(body);
  // silver accent panel along the left side
  const side = slab(L - 30, 30, 2, 6, 0.8, silver);
  side.rotation.y = -Math.PI / 2; side.position.set(-Wd / 2 - 0.3, -14, 4); root.add(side);
  // closed flip-out LCD panel on the left side
  const lcd = slab(64, 44, 7, 5, 2, dark); lcd.rotation.y = -Math.PI / 2; lcd.position.set(-Wd / 2 - 3.2, 10, -22); root.add(lcd);
  const lcdTxt = decal(30, 6, (c, w, h) => { c.fillStyle = '#9ea3a9'; c.font = `700 ${h * 0.55}px "DejaVu Sans Condensed"`; c.textBaseline = 'middle'; c.fillText('LCD  2.5"', 0, h / 2); }, { px: 30 });
  lcdTxt.rotation.y = -Math.PI / 2; lcdTxt.position.set(-Wd / 2 - 6.75, 26, -36); root.add(lcdTxt);
  const logo = decal(56, 14, (c, w, h) => {
    c.fillStyle = '#26292d'; c.textBaseline = 'middle';
    c.font = `800 ${h * 0.5}px "Inter Display"`; c.fillText('DARKROOM', 0, h * 0.33);
    c.font = `700 ${h * 0.24}px "DejaVu Sans Condensed"`; c.fillStyle = '#2e3136'; c.fillText('VIDEO  ·  22x ZOOM', 2, h * 0.78);
  }, { px: 24, rough: 0.4 });
  logo.rotation.y = -Math.PI / 2; logo.position.set(-Wd / 2 - 1.4, -13, 40); root.add(logo);

  // lens barrel + hood at the front
  const lensG = lens({
    profile: [[0, 0], [30, 0], [30, 2], [28, 3], [26.5, 3.2], [26.5, 18], [27.5, 19], [29.2, 29], [29.5, 30.5], [28.8, 31], [27.8, 30.4], [25.5, 22]],
    glassR: 19, glassZ: 21.6, mat: dark,
    rings: [{ profile: [[26.6, 6], [27.4, 6.6], [27.4, 15], [26.6, 15.6]], mat: rubber(0x101010) }],
  });
  lensG.position.set(0, 4, L / 2 - 2); root.add(lensG);
  const ringTxt = decal(44, 44, (c, w, h) => {
    c.translate(w / 2, h / 2); c.fillStyle = '#d8d8d8'; c.font = `600 ${w * 0.04}px "DejaVu Sans Condensed"`; c.textAlign = 'center'; c.textBaseline = 'middle';
    const t = 'VIDEO LENS  22x  f=3.9-85.8mm  1:1.6  Ø46  ';
    for (let i = 0; i < t.length; i++) { c.save(); c.rotate(-Math.PI * 0.85 + i * (Math.PI * 1.7 / t.length)); c.translate(0, -w * 0.45); c.fillText(t[i], 0, 0); c.restore(); }
  }, { px: 26 });
  ringTxt.position.set(0, 4, L / 2 - 2 + 21.62); root.add(ringTxt);

  // top: microphone grille at the front, zoom rocker at the back
  const mic = cyl(9, 26, dark, 48); mic.rotation.x = Math.PI / 2; mic.position.set(8, H / 2 + 6, L / 2 - 28); root.add(mic);
  const grille = new THREE.Mesh(new THREE.CylinderGeometry(9.2, 9.2, 18, 48, 1, true), new THREE.MeshPhysicalMaterial({ color: 0x0a0a0a, roughness: 0.55, metalness: 0.4 }));
  grille.rotation.x = Math.PI / 2; grille.position.set(8, H / 2 + 6, L / 2 - 28); root.add(grille);
  for (let i = 0; i < 12; i++) { const r = new THREE.Mesh(new THREE.TorusGeometry(9.25, 0.35, 6, 48), chrome); r.position.set(8, H / 2 + 6, L / 2 - 36 + i * 1.5); root.add(r); }
  const micMount = rbox(10, 8, 20, 3, dark); micMount.position.set(8, H / 2 + 1, L / 2 - 28); root.add(micMount);
  const rocker = rbox(9, 3, 16, 1.4, silver); rocker.position.set(14, H / 2 + 0.8, -30); root.add(rocker);
  const wt = decal(12, 6, (c, w, h) => { c.fillStyle = '#ddd'; c.font = `700 ${h * 0.6}px "DejaVu Sans"`; c.textBaseline = 'middle'; c.fillText('W  T', 0, h / 2); }, { px: 30 });
  wt.rotation.x = -Math.PI / 2; wt.rotation.z = Math.PI / 2; wt.position.set(22, H / 2 + 0.05, -30); root.add(wt);

  // viewfinder tube on top-left, rear, with rubber eyecup
  const vfBody = rbox(22, 20, 64, 8, bodyMat); vfBody.position.set(-14, H / 2 + 8, -L / 2 + 30); root.add(vfBody);
  const tube = cyl(9, 26, dark, 48); tube.rotation.x = Math.PI / 2; tube.position.set(-14, H / 2 + 9, -L / 2 - 6); root.add(tube);
  const cup = new THREE.Mesh(new THREE.TorusGeometry(10, 3.6, 24, 64), rubber(0x0c0c0c)); cup.position.set(-14, H / 2 + 9, -L / 2 - 19); root.add(cup);
  const cupFace = new THREE.Mesh(new THREE.CircleGeometry(9, 48), new THREE.MeshStandardMaterial({ color: 0x020202 })); cupFace.position.set(-14, H / 2 + 9, -L / 2 - 20); cupFace.rotation.y = Math.PI; root.add(cupFace);

  // hand strap on the right side: padded band with stitching
  const strapMat = new THREE.MeshPhysicalMaterial({ color: 0x1a1b1d, roughness: 0.9, sheen: 0.6, sheenColor: new THREE.Color(0x444444), sheenRoughness: 0.7 });
  const strap = rbox(10, 34, L - 34, 5, strapMat); strap.position.set(Wd / 2 + 7, 2, -2); root.add(strap);
  for (const zz of [L / 2 - 18, -L / 2 + 14]) { const tab = rbox(9, 22, 10, 3, dark); tab.position.set(Wd / 2 + 4, 2, zz); root.add(tab); }
  const strapTxt = decal(40, 8, (c, w, h) => { c.fillStyle = '#8b8f95'; c.font = `800 ${h * 0.55}px "Inter Display"`; c.textBaseline = 'middle'; c.fillText('DARKROOM', 0, h / 2); }, { px: 24, rough: 0.8 });
  strapTxt.rotation.y = Math.PI / 2; strapTxt.position.set(Wd / 2 + 12.1, 2, 4); root.add(strapTxt);

  // rear: battery pack and red REC button
  const batt = rbox(46, 40, 14, 4, plastic(0x3b3d40, { rough: 0.5, texture: 0.3 })); batt.position.set(4, -10, -L / 2 - 5); root.add(batt);
  const rec = cyl(5, 3, new THREE.MeshPhysicalMaterial({ color: 0xc41e1e, roughness: 0.3, clearcoat: 1 }), 48);
  rec.rotation.x = Math.PI / 2; rec.position.set(22, 18, -L / 2 - 0.5); root.add(rec);

  root.rotation.y = 0.9; root.rotation.x = 0.03;
  const holder = new THREE.Group(); holder.add(root); holder.position.y = H / 2 + 0.5;
  return { object: holder, floorY: 0, exposure: 1.15, env: { ambient: 0.22 }, camera: { fov: 20, position: [0, 150, 560], target: [0, 45, 0] } };
}
