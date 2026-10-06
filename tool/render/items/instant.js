// Late-80s instant camera: boxy cream shell, black lens plate, flash hump,
// and a fresh print half out of the slot (still blue-grey, developing).
import { rbox, slab, plastic, lens, decal, cyl } from '/lib/parts.js';

export async function build(THREE) {
  const g = new THREE.Group();
  const W = 96, H = 78, D = 92;
  const cream = plastic(0xe7e0d0, { rough: 0.42, texture: 0.25, clearcoat: 0.15 });
  const black = plastic(0x161616, { rough: 0.5, texture: 0.35 });
  const gloss = plastic(0x0e0e0e, { rough: 0.2, texture: 0.05, clearcoat: 0.6 });
  const accent = plastic(0xd2652a, { rough: 0.35, texture: 0.1, clearcoat: 0.4 });

  // main shell
  const body = slab(W, H, D, 9, 3, cream);
  g.add(body);

  // flash hump across the top front
  const hump = slab(W - 2, 24, 42, 7, 2.4, cream);
  hump.position.set(0, H / 2 + 9, D / 2 - 21); g.add(hump);
  const [fx, fy, fz] = [-20, H / 2 + 10, D / 2 + 0.2];
  const flashMat = new THREE.MeshPhysicalMaterial({ color: 0xf4f4ef, roughness: 0.3, transmission: 0.25, thickness: 0.5, clearcoat: 1 });
  const flashFrame = rbox(40, 15, 1.6, 1.2, gloss); flashFrame.position.set(fx, fy, fz); g.add(flashFrame);
  const flash = rbox(37, 12, 1.6, 0.9, flashMat); flash.position.set(fx, fy, fz + 0.4); g.add(flash);
  // fresnel ridges on the flash window
  const ridges = decal(37, 12, (c, w, h) => {
    for (let x = 0; x < w; x += 6) { c.fillStyle = `rgba(0,0,0,${0.12 + 0.06 * Math.sin(x)})`; c.fillRect(x, 0, 2, h); }
  }, { px: 20, rough: 0.3 });
  ridges.position.set(fx, fy, fz + 1.25); g.add(ridges);
  const vf = rbox(14, 10, 1.4, 1.5, new THREE.MeshPhysicalMaterial({ color: 0x0a0d12, roughness: 0.03, clearcoat: 1 }));
  vf.position.set(26, H / 2 + 10, D / 2 + 0.2); g.add(vf);

  // black lens plate on the lower front
  const plate = slab(W - 10, 50, 3, 6, 1, black);
  plate.position.set(0, -6, D / 2 + 1); g.add(plate);
  const L = lens({
    profile: [[0, 0], [17, 0], [17.2, 0.6], [17.2, 3.4], [16.4, 4.0], [14.2, 4.2], [13.8, 4.6], [13.8, 7.4], [13.2, 7.8], [11.6, 7.9]],
    glassR: 10.4, glassZ: 8.4, mat: gloss,
    rings: [{ profile: [[11.7, 7.85], [11.7, 8.6], [11.0, 8.9], [10.5, 8.9]], mat: black }],
  });
  L.position.set(0, -4, D / 2 + 2.4); g.add(L);
  // shutter button and exposure slider
  const btn = cyl(5.2, 3.4, accent, 48); btn.rotation.x = Math.PI / 2; btn.position.set(-35, -4, D / 2 + 3.4); g.add(btn);
  const slider = rbox(14, 3.2, 2.2, 0.8, plastic(0x2a2a2a, { rough: 0.4, texture: 0.1 }));
  slider.position.set(34, -24, D / 2 + 2.8); g.add(slider);
  const knob = rbox(3.4, 4.6, 3, 0.8, plastic(0xbfbfbf, { rough: 0.3, texture: 0, metal: 0.6 }));
  knob.position.set(36, -24, D / 2 + 3.6); g.add(knob);

  // branding: one accent stripe and the name (original design, no logos)
  const stripe = decal(6, 50, (c, w, h) => { c.fillStyle = '#d2652a'; c.fillRect(0, 0, w, h); }, { px: 10, rough: 0.4 });
  stripe.position.set(-25, -6, D / 2 + 2.6); g.add(stripe);
  const name = decal(56, 9, (c, w, h) => {
    c.fillStyle = '#ece6da'; c.textBaseline = 'middle'; c.textAlign = 'center';
    c.font = `800 ${h * 0.5}px "Inter Display"`; c.fillText('DARKROOM', w / 2, h * 0.36);
    c.font = `600 ${h * 0.26}px "DejaVu Sans Condensed"`; c.fillText('INSTANT  600', w / 2, h * 0.82);
  }, { px: 30, rough: 0.45 });
  name.position.set(0, 13.5, D / 2 + 2.6); g.add(name);

  // print slot below the plate, with a fresh print half ejected
  const slot = rbox(80, 3, 2, 1, new THREE.MeshStandardMaterial({ color: 0x050505, roughness: 0.8 }));
  slot.position.set(0, -H / 2 + 4, D / 2 + 0.6); g.add(slot);
  const print = new THREE.Group();
  const paper = rbox(76, 38, 0.9, 0.4, plastic(0xf6f4ee, { rough: 0.55, texture: 0.05, clearcoat: 0 }));
  paper.position.set(0, -19, 0); print.add(paper);
  const latent = new THREE.Mesh(new THREE.PlaneGeometry(66, 30), new THREE.MeshPhysicalMaterial({ color: 0x2c3a44, roughness: 0.15, clearcoat: 1, clearcoatRoughness: 0.05 }));
  latent.position.set(0, -20, 0.5); print.add(latent);
  print.position.set(0, -H / 2 + 4, D / 2 + 0.6); print.rotation.x = 0.5; g.add(print);

  g.rotation.y = -0.48; g.rotation.x = 0.04;
  const holder = new THREE.Group(); holder.add(g); holder.position.y = H / 2 + 22;
  return { object: holder, floorY: 0, exposure: 1.1, env: { ambient: 0.3 }, camera: { fov: 20, position: [0, 150, 420], target: [0, 50, 0] } };
}
