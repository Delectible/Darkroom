// Late-2000s entry-level DSLR (original design): black polycarbonate body
// with a deep rubber grip, pentamirror hump, mode dial, kit zoom 18-55.
import { rbox, slab, plastic, lens, decal, cyl, rubber } from '/lib/parts.js';
import { drawRabbit } from '/lib/logo.js';

export async function build(THREE) {
  const g = new THREE.Group();
  const W = 128, H = 80, D = 62;
  const body = plastic(0x161718, { rough: 0.55, texture: 0.4 });
  const gripMat = rubber(0x0f0f10);
  const chrome = new THREE.MeshPhysicalMaterial({ color: 0xd0d0d0, metalness: 1, roughness: 0.2 });
  g.add(slab(W, H, D, 10, 3, body));
  // grip on the right (viewer's left when facing the lens): tall rounded block
  const grip = rbox(30, H + 4, D + 14, 13, gripMat, 8); grip.position.set(-W / 2 + 12, -1, 6); g.add(grip);
  // pentamirror hump and hot shoe
  const hump = new THREE.Mesh(new THREE.CylinderGeometry(14, 30, 26, 4, 1), body);
  hump.rotation.y = Math.PI / 4; hump.scale.set(1, 1, 0.9); hump.position.set(4, H / 2 + 11, -2); g.add(hump);
  const shoe = rbox(20, 2, 18, 0.6, chrome); shoe.position.set(4, H / 2 + 24.5, -2); g.add(shoe);
  // mode dial and shutter on the grip top
  const dial = cyl(11, 7, plastic(0x1d1e20, { rough: 0.4, texture: 0.3 }), 48); dial.position.set(36, H / 2 + 3.5, -6); g.add(dial);
  const dialTxt = decal(20, 20, (c, w, h) => {
    c.translate(w / 2, h / 2); c.fillStyle = '#e8e8e8'; c.font = `700 ${w * 0.11}px "DejaVu Sans Condensed"`; c.textAlign = 'center'; c.textBaseline = 'middle';
    ['P', 'Tv', 'Av', 'M', 'AUTO', 'SCN'].forEach((t, i) => { c.save(); c.rotate(i * Math.PI / 3); c.translate(0, -w * 0.36); c.fillText(t, 0, 0); c.restore(); });
  }, { px: 30 });
  dialTxt.rotation.x = -Math.PI / 2; dialTxt.position.set(36, H / 2 + 7.05, -6); g.add(dialTxt);
  const shutter = cyl(5, 3, chrome, 32); shutter.position.set(-W / 2 + 14, H / 2 + 5.5, 16); g.add(shutter);
  // kit lens: mount ring, zoom ring (rubber), focus ring, front element
  const L = lens({
    profile: [[0, 0], [30, 0], [30.5, 1.5], [29, 3], [28, 3], [28, 38], [27, 44], [26.5, 60], [27.5, 61], [27.5, 64], [24, 65]],
    glassR: 22, glassZ: 64.6, mat: plastic(0x141516, { rough: 0.35, texture: 0.15 }),
    rings: [
      { profile: [[28.2, 8], [29.3, 9], [29.3, 30], [28.2, 31]], mat: rubber(0x0c0c0c) },
      { profile: [[30.6, 0.6], [30.6, 1.4]], mat: chrome },
    ],
  });
  L.position.set(8, -4, D / 2 - 2); g.add(L);
  const ring = decal(52, 52, (c, w, h) => {
    c.translate(w / 2, h / 2); c.fillStyle = '#e6e6e6'; c.font = `600 ${w * 0.035}px "DejaVu Sans Condensed"`; c.textAlign = 'center'; c.textBaseline = 'middle';
    const t = 'ZOOM LENS  18-55mm  1:3.5-5.6  IS  Ø58mm  ';
    for (let i = 0; i < t.length; i++) { c.save(); c.rotate(-Math.PI * 0.9 + i * (Math.PI * 1.8 / t.length)); c.translate(0, -w * 0.45); c.fillText(t[i], 0, 0); c.restore(); }
  }, { px: 20 });
  ring.position.set(8, -4, D / 2 - 2 + 64.62); g.add(ring);
  // name plate above the lens, red dot at the mount
  const logo = decal(52, 9, (c, w, h) => { c.fillStyle = '#d9d9d9'; c.font = `800 ${h * 0.62}px "Inter Display"`; c.textBaseline = 'middle'; c.fillText('DARKROOM', w * 0.2, h / 2); drawRabbit(c, w * 0.08, h * 0.5, h * 0.8, '#d9d9d9'); }, { px: 24 });
  logo.position.set(8, H / 2 - 4, D / 2 + 0.05); g.add(logo);
  const model = decal(20, 6, (c, w, h) => { c.fillStyle = '#d9d9d9'; c.font = `700 ${h * 0.7}px "DejaVu Sans Condensed"`; c.textBaseline = 'middle'; c.fillText('D80', 0, h / 2); }, { px: 30 });
  model.position.set(46, -H / 2 + 8, D / 2 + 0.05); g.add(model);
  const red = cyl(1.4, 1, new THREE.MeshPhysicalMaterial({ color: 0xc81e1e, roughness: 0.3, clearcoat: 1 }), 16);
  red.rotation.x = Math.PI / 2; red.position.set(8 + 24, -4 + 26, D / 2 + 0.3); g.add(red);
  // strap lugs
  for (const x of [-W / 2 - 1, W / 2 + 1]) { const lug = rbox(4, 10, 8, 1.5, chrome); lug.position.set(x, H / 2 - 12, -6); g.add(lug); }

  g.rotation.y = -0.55; g.rotation.x = 0.05;
  const holder = new THREE.Group(); holder.add(g); holder.position.y = H / 2 + 3;
  return { object: holder, floorY: 0, exposure: 1.2, env: { ambient: 0.3 }, camera: { fov: 20, position: [0, 150, 420], target: [0, 40, 0] } };
}
