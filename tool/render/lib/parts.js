// Reusable modelling parts and materials for the camera bodies.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { canvas, tex, noiseCanvas, normalFromHeight } from '/lib/tex.js';

export function rbox(w, h, d, r, mat, seg = 6) {
  return new THREE.Mesh(new RoundedBoxGeometry(w, h, d, seg, r), mat);
}

// Rounded rectangle prism with independent corner radius in XY and a small
// bevel on the Z edges (good for phone halves and camera bodies).
export function slab(w, h, d, r, bevel, mat) {
  const s = new THREE.Shape();
  const x = -w / 2, y = -h / 2;
  s.moveTo(x + r, y); s.lineTo(x + w - r, y); s.absarc(x + w - r, y + r, r, -Math.PI / 2, 0);
  s.lineTo(x + w, y + h - r); s.absarc(x + w - r, y + h - r, r, 0, Math.PI / 2);
  s.lineTo(x + r, y + h); s.absarc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
  s.lineTo(x, y + r); s.absarc(x + r, y + r, r, Math.PI, Math.PI * 1.5);
  const g = new THREE.ExtrudeGeometry(s, { depth: d - 2 * bevel, bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel, bevelSegments: 5, curveSegments: 24 });
  g.translate(0, 0, -(d - 2 * bevel) / 2);
  // planar UVs in mm-space normalised to the face
  const uv = g.attributes.uv, p = g.attributes.position;
  for (let i = 0; i < p.count; i++) uv.setXY(i, (p.getX(i) + w / 2) / w, (p.getY(i) + h / 2) / h);
  return new THREE.Mesh(g, mat);
}

let _brushed = null;
export function brushedMetal(color = 0xc8c8c8, rough = 0.32) {
  if (!_brushed) {
    const n = noiseCanvas(1024, 256, { base: 128, amp: 90, sx: 64, sy: 1, octaves: 3, seed: 9 });
    _brushed = { normal: tex(normalFromHeight(n, 1.2), { srgb: false, repeat: true }), rough: tex(noiseCanvas(512, 128, { base: 100, amp: 40, sx: 32, sy: 1, octaves: 3, seed: 10 }), { srgb: false, repeat: true }) };
  }
  return new THREE.MeshPhysicalMaterial({ color, metalness: 1, roughness: rough, normalMap: _brushed.normal, normalScale: new THREE.Vector2(0.18, 0.18), roughnessMap: _brushed.rough });
}

let _grain = null;
export function plastic(color, { rough = 0.5, texture = 0.3, clearcoat = 0.1, metal = 0 } = {}) {
  if (!_grain) {
    const g = tex(normalFromHeight(noiseCanvas(512, 512, { base: 128, amp: 70, sx: 2, sy: 2, octaves: 2, seed: 4 }), 1.4), { srgb: false, repeat: true });
    g.repeat.set(6, 6); _grain = g;
  }
  return new THREE.MeshPhysicalMaterial({ color, roughness: rough, metalness: metal, normalMap: texture > 0 ? _grain : null, normalScale: new THREE.Vector2(texture, texture), clearcoat, clearcoatRoughness: 0.3 });
}

// Metallic-flake paint (Y2K phones, camcorder accents).
export function paint(color, { rough = 0.35, metal = 0.6, clearcoat = 1.0 } = {}) {
  return new THREE.MeshPhysicalMaterial({ color, roughness: rough, metalness: metal, clearcoat, clearcoatRoughness: 0.06 });
}

export function rubber(color = 0x161616) {
  return plastic(color, { rough: 0.85, texture: 0.6, clearcoat: 0 });
}

// Coated glass element: dark, reflective, faint purple-green coating.
export function lensGlass() {
  return new THREE.MeshPhysicalMaterial({
    color: 0x05070a, roughness: 0.02, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.0,
    iridescence: 1, iridescenceIOR: 1.6, iridescenceThicknessRange: [220, 420], ior: 1.6,
  });
}

// A lens assembly built as a lathe around +Z: outer profile (r, z) pairs,
// then glass. Returns a group facing +Z with its back at z=0.
export function lens({ profile, glassR, glassZ, mat, innerMat, rings = [] }) {
  const g = new THREE.Group();
  const lathe = new THREE.LatheGeometry(profile.map(([r, z]) => new THREE.Vector2(r, z)), 128);
  lathe.rotateX(Math.PI / 2);  // lathe Y becomes +Z (forward)
  g.add(new THREE.Mesh(lathe, mat));
  for (const rg of rings) {
    const l = new THREE.LatheGeometry(rg.profile.map(([r, z]) => new THREE.Vector2(r, z)), 128);
    l.rotateX(Math.PI / 2); g.add(new THREE.Mesh(l, rg.mat));
  }
  // glass: shallow spherical cap
  const cap = new THREE.SphereGeometry(glassR * 2.2, 96, 24, 0, Math.PI * 2, 0, Math.asin(1 / 2.2));
  cap.rotateX(Math.PI / 2);
  const glass = new THREE.Mesh(cap, lensGlass());
  glass.position.z = glassZ - glassR * 2.2 * Math.cos(Math.asin(1 / 2.2));
  g.add(glass);
  // dark interior behind the glass
  const inner = new THREE.Mesh(new THREE.CircleGeometry(glassR * 1.02, 64), innerMat ?? new THREE.MeshStandardMaterial({ color: 0x020202, roughness: 0.6 }));
  inner.position.z = glassZ - 1.5; g.add(inner);
  return g;
}

// Flat decal (text, icons) with soft alpha from a canvas.
export function decal(w, h, draw, { px = 24, rough = 0.4, metal = 0, emissive = null } = {}) {
  const [c, g] = canvas(Math.round(w * px), Math.round(h * px));
  draw(g, c.width, c.height, px);
  // alpha from the canvas alpha channel
  const [ac, ag] = canvas(c.width, c.height);
  const src = g.getImageData(0, 0, c.width, c.height);
  const a = ag.createImageData(c.width, c.height);
  for (let i = 0; i < src.data.length; i += 4) a.data[i] = a.data[i + 1] = a.data[i + 2] = src.data[i + 3], a.data[i + 3] = 255;
  ag.putImageData(a, 0, 0);
  const mat = new THREE.MeshPhysicalMaterial({ map: tex(c), alphaMap: tex(ac, { srgb: false }), alphaTest: 0.5, roughness: rough, metalness: metal, transparent: false });
  if (emissive) { mat.emissiveMap = mat.map; mat.emissive = new THREE.Color(0xffffff); mat.emissiveIntensity = emissive; }
  return new THREE.Mesh(new THREE.PlaneGeometry(w, h), mat);
}

export function cyl(r, h, mat, seg = 64) {
  return new THREE.Mesh(new THREE.CylinderGeometry(r, r, h, seg), mat);
}
