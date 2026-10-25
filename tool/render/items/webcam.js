// Mid-2000s USB webcam (original design): glossy white eyeball on a
// clip-on stand, black face with the lens, blue status light, cable.
import { plastic, lens, decal, cyl, rbox } from '/lib/parts.js';
import { drawRabbit } from '/lib/logo.js';

export async function build(THREE) {
  const g = new THREE.Group();
  const R = 30;
  const white = plastic(0xf2f2f0, { rough: 0.18, texture: 0, clearcoat: 1 });
  const grey = plastic(0x9da2a8, { rough: 0.3, texture: 0.1, metal: 0.4 });
  const black = plastic(0x0d0e10, { rough: 0.25, texture: 0, clearcoat: 1 });
  const ball = new THREE.Mesh(new THREE.SphereGeometry(R, 96, 64), white); ball.position.y = 58; g.add(ball);
  // black front disc and the lens
  const face = new THREE.Mesh(new THREE.SphereGeometry(R + 0.2, 96, 32, 0, Math.PI * 2, 0, 0.75), black);
  face.rotation.x = Math.PI / 2; face.position.y = 58; g.add(face);
  const L = lens({ profile: [[0, 0], [11, 0], [11, 3], [9.5, 4.5], [7, 5]], glassR: 6.8, glassZ: 5.2, mat: grey });
  L.position.set(0, 58, R - 3.2); g.add(L);
  const led = new THREE.Mesh(new THREE.SphereGeometry(1.4, 16, 12), new THREE.MeshStandardMaterial({ color: 0x2244ff, emissive: 0x3366ff, emissiveIntensity: 2.5 }));
  led.position.set(13, 70, R - 4.2); g.add(led);
  const logo = decal(22, 6, (c, w, h) => { c.fillStyle = '#c9ccd0'; c.font = `800 ${h * 0.6}px "Inter Display"`; c.textBaseline = 'middle'; c.fillText('DARKROOM', w * 0.18, h / 2); drawRabbit(c, w * 0.08, h * 0.5, h * 0.7, '#c9ccd0'); }, { px: 30 });
  logo.position.set(0, 46.5, R - 1.2); logo.rotation.x = 0.42; g.add(logo);
  // neck and the folding clip base
  const neck = cyl(6, 22, grey, 32); neck.position.y = 24; g.add(neck);
  const collar = new THREE.Mesh(new THREE.TorusGeometry(8, 2.2, 16, 48), grey); collar.rotation.x = Math.PI / 2; collar.position.y = 31; g.add(collar);
  const base = rbox(70, 8, 46, 4, white, 6); base.position.y = 4; g.add(base);
  const foot = rbox(70, 6, 10, 3, grey, 4); foot.position.set(0, 3, -24); g.add(foot);
  const pad = rbox(60, 1.5, 38, 1, plastic(0x2a2a2a, { rough: 0.9, texture: 0.5 })); pad.position.y = -0.2; g.add(pad);
  // USB cable trailing off behind
  const curve = new THREE.CatmullRomCurve3([[0, 10, -26], [6, 6, -40], [24, 1.2, -52], [60, 1.2, -50], [96, 1.2, -66]].map((p) => new THREE.Vector3(...p)));
  g.add(new THREE.Mesh(new THREE.TubeGeometry(curve, 80, 1.6, 12), plastic(0x1a1a1a, { rough: 0.6, texture: 0 })));

  g.rotation.y = -0.35;
  return { object: g, floorY: 0, exposure: 1.1, env: { ambient: 0.28 }, camera: { fov: 20, position: [0, 110, 330], target: [0, 40, 0] } };
}
