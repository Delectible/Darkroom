// Mid-2000s MiniDV palmcorder (original design): small upright silver body,
// lens up front, flip-out LCD opened to the side, hand strap, DV badge.
import { rbox, slab, plastic, paint, lens, decal, cyl, rubber } from '/lib/parts.js';
import { drawRabbit } from '/lib/logo.js';

export async function build(THREE) {
  const root = new THREE.Group();
  // body along Z (lens at +Z)
  const L = 112, H = 80, Wd = 52;
  const silver = paint(0xb7bcc2, { rough: 0.32, metal: 0.75, clearcoat: 0.6 });
  const dark = plastic(0x1a1b1e, { rough: 0.4, texture: 0.2 });
  root.add(rbox(Wd, H, L, 14, silver, 8));
  const lowerBand = rbox(Wd + 0.6, 18, L - 8, 8, dark, 6); lowerBand.position.y = -H / 2 + 11; root.add(lowerBand);
  // lens barrel at the front with a black hood
  const lensG = lens({
    profile: [[0, 0], [20, 0], [20, 10], [21, 11], [21, 16], [19, 17]],
    glassR: 14, glassZ: 16.6, mat: dark,
    rings: [{ profile: [[20.1, 2], [20.6, 2.5], [20.6, 8], [20.1, 8.5]], mat: silver }],
  });
  lensG.position.set(0, 12, L / 2 - 4); root.add(lensG);
  const ringTxt = decal(34, 34, (c, w, h) => {
    c.translate(w / 2, h / 2); c.fillStyle = '#e1e1e1'; c.font = `600 ${w * 0.045}px "DejaVu Sans Condensed"`; c.textAlign = 'center'; c.textBaseline = 'middle';
    const t = 'DIGITAL VIDEO  20x  1:1.8  f=2.5-50  ';
    for (let i = 0; i < t.length; i++) { c.save(); c.rotate(-Math.PI * 0.85 + i * (Math.PI * 1.7 / t.length)); c.translate(0, -w * 0.43); c.fillText(t[i], 0, 0); c.restore(); }
  }, { px: 26 });
  ringTxt.position.set(0, 12, L / 2 - 4 + 16.62); root.add(ringTxt);
  // flip-out LCD, opened out from the left side
  const hinge = new THREE.Group(); hinge.position.set(-Wd / 2 - 2, 6, 10); hinge.rotation.y = 1.15; root.add(hinge);
  const panel = slab(60, 46, 6, 6, 1.5, dark); panel.rotation.y = -Math.PI / 2; panel.position.set(0, 0, -32); hinge.add(panel);
  const screen = new THREE.Mesh(new THREE.PlaneGeometry(50, 37), new THREE.MeshPhysicalMaterial({ color: 0x0a2236, emissive: 0x2a6fa8, emissiveIntensity: 0.55, roughness: 0.05, clearcoat: 1 }));
  screen.rotation.y = Math.PI / 2; screen.position.set(3.1, 0, -32); hinge.add(screen);
  // top: zoom rocker, photo button; back: viewfinder and battery
  const rocker = rbox(8, 3, 14, 1.4, silver); rocker.position.set(10, H / 2 + 1, -18); root.add(rocker);
  const photo = cyl(4, 2.4, dark, 32); photo.position.set(10, H / 2 + 1, -2); root.add(photo);
  const vf = rbox(18, 16, 24, 5, dark); vf.position.set(-8, H / 2 - 4, -L / 2 - 6); root.add(vf);
  const batt = rbox(36, 30, 10, 3, plastic(0x2b2d31, { rough: 0.5, texture: 0.3 })); batt.position.set(4, -10, -L / 2 - 4); root.add(batt);
  // hand strap on the right
  const strapMat = new THREE.MeshPhysicalMaterial({ color: 0x15161a, roughness: 0.9, sheen: 0.6, sheenColor: new THREE.Color(0x444444) });
  const strap = rbox(9, 28, L - 30, 4.5, strapMat); strap.position.set(Wd / 2 + 6, 2, -2); root.add(strap);
  // badges on the left side
  const logo = decal(52, 16, (c, w, h) => {
    c.fillStyle = '#2b2e33'; c.textBaseline = 'middle';
    c.font = `800 ${h * 0.42}px "Inter Display"`; c.fillText('DARKROOM', w * 0.16, h * 0.3);
    drawRabbit(c, w * 0.07, h * 0.3, h * 0.42, '#2b2e33');
    c.font = `800 ${h * 0.34}px "DejaVu Sans"`; c.strokeStyle = '#2b2e33'; c.lineWidth = h * 0.05;
    c.strokeRect(w * 0.02, h * 0.56, w * 0.24, h * 0.38); c.fillText('miniDV', w * 0.035, h * 0.76);
    c.font = `700 ${h * 0.22}px "DejaVu Sans Condensed"`; c.fillText('HANDYCAM 800K', w * 0.32, h * 0.76);
  }, { px: 24, rough: 0.35 });
  logo.rotation.y = -Math.PI / 2; logo.position.set(-Wd / 2 - 0.15, -14, 22); root.add(logo);

  root.rotation.y = 0.95; root.rotation.x = 0.03;
  const holder = new THREE.Group(); holder.add(root); holder.position.y = H / 2 + 0.5;
  return { object: holder, floorY: 0, exposure: 1.15, env: { ambient: 0.25 }, camera: { fov: 20, position: [0, 150, 520], target: [0, 42, 0] } };
}
