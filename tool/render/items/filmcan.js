// 65/70 mm motion picture film can (original design): flat steel can, taped
// shut round the seam, a printed stock label on the lid and a strip of
// camera tape with the roll written on it.
import { decal, brushedMetal } from '/lib/parts.js';
import { roundRect } from '/lib/tex.js';
import { drawRabbit } from '/lib/logo.js';

export async function build(THREE) {
  const g = new THREE.Group();
  const R = 60, Hb = 12, Hl = 6;
  const steel = brushedMetal(0xb9bcbf, 0.34);
  // body (lathe with a rolled bottom edge) and the slightly wider lid
  const body = new THREE.Mesh(new THREE.LatheGeometry([[0, 0], [R - 1.2, 0], [R, 0.8], [R, Hb]].map(([r, y]) => new THREE.Vector2(r, y)), 160), steel);
  g.add(body);
  const lidProfile = [[R + 0.6, Hb - 3], [R + 1.2, Hb - 2.6], [R + 1.2, Hb + Hl - 1], [R + 0.4, Hb + Hl], [R - 3, Hb + Hl], [R - 4, Hb + Hl - 0.8], [R - 6, Hb + Hl - 0.8], [R - 7, Hb + Hl], [0, Hb + Hl]];
  g.add(new THREE.Mesh(new THREE.LatheGeometry(lidProfile.map(([r, y]) => new THREE.Vector2(r, y)), 160), steel));
  // tape round the seam
  const tape = new THREE.Mesh(new THREE.CylinderGeometry(R + 1.35, R + 1.35, 5, 160, 1, true),
    new THREE.MeshPhysicalMaterial({ color: 0xd8d2bf, roughness: 0.7, sheen: 0.3 }));
  tape.position.y = Hb - 1.2; g.add(tape);
  // printed stock label on the lid
  const label = decal(62, 40, (c, w, h) => {
    c.fillStyle = '#f1c21b'; roundRect(c, 0, 0, w, h, h * 0.05); c.fill();
    c.fillStyle = '#141414'; c.fillRect(0, h * 0.62, w, h * 0.38);
    c.fillStyle = '#141414'; c.textBaseline = 'alphabetic';
    c.font = `900 ${h * 0.26}px "Inter Display"`; c.fillText('EPIC 70', w * 0.06, h * 0.32);
    c.font = `700 ${h * 0.072}px "DejaVu Sans Condensed"`;
    c.fillText('COLOR NEGATIVE MOTION PICTURE FILM', w * 0.06, h * 0.46);
    c.fillText('65 mm  ·  500 FT  ·  EI 250D', w * 0.06, h * 0.56);
    c.fillStyle = '#f1c21b'; c.font = `700 ${h * 0.09}px "Inter Display"`; c.fillText('D A R K R O O M', w * 0.2, h * 0.86);
    drawRabbit(c, w * 0.11, h * 0.82, h * 0.1, '#f1c21b');
  }, { px: 14, rough: 0.5 });
  label.rotation.x = -Math.PI / 2; label.position.y = Hb + Hl + 0.05; g.add(label);
  // camera tape strip with the roll's notes in marker
  const strip = decal(70, 9, (c, w, h) => {
    c.fillStyle = '#efeadb'; c.fillRect(0, 0, w, h);
    c.fillStyle = '#1f2a6b'; c.font = `italic 700 ${h * 0.55}px "DejaVu Sans"`; c.textBaseline = 'middle';
    c.fillText('ROLL 7  ·  BEACH / DUSK  ·  EXPOSED', w * 0.04, h * 0.55);
  }, { px: 16, rough: 0.75 });
  strip.rotation.x = -Math.PI / 2; strip.rotation.z = 0.08; strip.position.set(0, Hb + Hl + 0.1, 29); g.add(strip);

  g.rotation.y = 0.35;
  return { object: g, floorY: 0, exposure: 1.25, env: { ambient: 0.3 }, camera: { fov: 20, position: [0, 260, 330], target: [0, 6, 0] } };
}
