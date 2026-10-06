// Early-2000s CCD compact: brushed aluminium, retracting zoom lens.
import { rbox, slab, brushedMetal, plastic, lens, decal, cyl, paint } from '/lib/parts.js';
import { canvas, tex } from '/lib/tex.js';

export async function build(THREE) {
  const g = new THREE.Group();
  const W = 94, H = 56, D = 22;
  const alu = brushedMetal(0xd6d7da, 0.3);
  const body = slab(W, H, D, 8, 2.6, alu);
  g.add(body);
  // darker inset band around the sides (two-piece shell)
  const band = slab(W - 0.6, H - 0.6, 3.0, 7.7, 0.4, plastic(0x6f7276, { rough: 0.4, texture: 0.1, metal: 0.6 }));
  band.position.z = -D / 2 + 3.2; g.add(band);

  const chrome = new THREE.MeshPhysicalMaterial({ color: 0xe8e8ea, metalness: 1, roughness: 0.12 });
  const black = plastic(0x111214, { rough: 0.45, texture: 0.08 });
  const satin = brushedMetal(0xbfc1c5, 0.22);

  // lens assembly
  const L = lens({
    profile: [[0, 0], [17.2, 0], [17.4, 0.6], [17.4, 2.2], [16.6, 2.9], [15.0, 3.0], [14.6, 3.2], [14.6, 6.4], [14.0, 6.6], [12.8, 6.7], [12.6, 7.0], [12.6, 9.6], [12.1, 9.8], [11.0, 9.9]],
    glassR: 7.2, glassZ: 10.4, mat: satin,
    rings: [
      { profile: [[11.05, 9.85], [11.1, 10.6], [10.6, 11.0], [8.2, 11.0], [7.6, 10.6], [7.3, 10.4]], mat: black },
      { profile: [[17.0, 2.95], [15.2, 3.05]], mat: chrome },
    ],
  });
  L.position.set(19, 1, D / 2 - 0.4); g.add(L);
  // lens spec ring text
  const ring = decal(23, 23, (c, w, h) => {
    c.translate(w / 2, h / 2); c.fillStyle = '#e9e9e9';
    c.font = `600 ${w * 0.045}px "DejaVu Sans Condensed"`; c.textAlign = 'center'; c.textBaseline = 'middle';
    const txt = 'ZOOM LENS 3x  5.8-17.4mm  1:2.8-4.9  ';
    const rr = w * 0.40;
    for (let i = 0; i < txt.length; i++) { c.save(); c.rotate(-Math.PI * 0.95 + i * (Math.PI * 1.9 / txt.length)); c.translate(0, -rr); c.fillText(txt[i], 0, 0); c.restore(); }
  }, { px: 40, rough: 0.45 });
  ring.position.set(19, 1, D / 2 - 0.4 + 11.02); g.add(ring);

  // flash window: frosted fresnel plastic in a chrome frame
  const [fc, fg] = canvas(280, 140);
  fg.fillStyle = '#f2f2ee'; fg.fillRect(0, 0, 280, 140);
  for (let x = 0; x < 280; x += 7) { fg.fillStyle = `rgba(0,0,0,${0.10 + 0.08 * Math.sin(x)})`; fg.fillRect(x, 0, 2, 140); }
  const flashMat = new THREE.MeshPhysicalMaterial({ map: tex(fc), roughness: 0.25, transmission: 0.3, thickness: 0.5, clearcoat: 1, clearcoatRoughness: 0.05 });
  const frame = rbox(17, 9, 1.6, 0.7, chrome); frame.position.set(-30, 17, D / 2 + 0.2); g.add(frame);
  const flash = rbox(15, 7, 1.6, 0.5, flashMat); flash.position.set(-30, 17, D / 2 + 0.55); g.add(flash);
  // optical viewfinder + AF assist lamp
  const vf = rbox(8, 5.6, 1.4, 0.8, new THREE.MeshPhysicalMaterial({ color: 0x0a0d12, roughness: 0.03, clearcoat: 1 }));
  vf.position.set(-12, 17.5, D / 2 + 0.3); g.add(vf);
  const af = cyl(2.0, 1.2, new THREE.MeshPhysicalMaterial({ color: 0xd8742a, roughness: 0.15, transmission: 0.4, thickness: 1, clearcoat: 1 }), 32);
  af.rotation.x = Math.PI / 2; af.position.set(-12, 6, D / 2 + 0.3); g.add(af);
  const afRing = new THREE.Mesh(new THREE.TorusGeometry(2.2, 0.35, 12, 48), chrome); afRing.position.set(-12, 6, D / 2 + 0.6); g.add(afRing);
  // mic holes
  for (let i = 0; i < 6; i++) { const h = cyl(0.45, 0.8, new THREE.MeshStandardMaterial({ color: 0x050505 }), 16); h.rotation.x = Math.PI / 2; h.position.set(-40 + (i % 3) * 1.6, 2 - Math.floor(i / 3) * 1.6, D / 2 + 0.05); g.add(h); }

  // printing on the front plate
  const logo = decal(40, 12, (c, w, h) => {
    c.fillStyle = '#2b2d31'; c.textBaseline = 'middle';
    c.font = `800 ${h * 0.42}px "Inter Display"`; c.fillText('RETROCAM', 0, h * 0.32);
    c.font = `600 ${h * 0.2}px "DejaVu Sans Condensed"`; c.fillStyle = '#3d4045';
    c.fillText('DIGITAL  4.0 MEGA PIXELS', 2, h * 0.78);
  }, { px: 30, rough: 0.5 });
  logo.position.set(-22, -15, D / 2 + 0.03); g.add(logo);
  const zoom = decal(30, 5, (c, w, h) => { c.fillStyle = '#2b2d31'; c.font = `700 ${h * 0.6}px "DejaVu Sans Condensed"`; c.textBaseline = 'middle'; c.fillText('3x OPTICAL ZOOM', 0, h / 2); }, { px: 30 });
  zoom.position.set(-26, 9.5, D / 2 + 0.03); g.add(zoom);

  // top controls: shutter with zoom collar, power button
  const collar = cyl(6.4, 1.8, plastic(0x1a1b1d, { rough: 0.3, texture: 0 }), 64); collar.position.set(-30, H / 2 + 0.6, 2); g.add(collar);
  const nub = rbox(3, 1.4, 2.2, 0.5, satin); nub.position.set(-36.6, H / 2 + 0.7, 2); g.add(nub);
  const shutter = cyl(4.4, 2.6, chrome, 64); shutter.position.set(-30, H / 2 + 1.2, 2); g.add(shutter);
  const shTop = new THREE.Mesh(new THREE.SphereGeometry(4.4, 48, 12, 0, Math.PI * 2, 0, 0.5), chrome); shTop.position.set(-30, H / 2 + 0.6, 2); g.add(shTop);
  const power = cyl(2.2, 1.2, plastic(0x2a2c2f, { rough: 0.35, texture: 0 }), 32); power.position.set(-14, H / 2 + 0.4, 2); g.add(power);
  const pled = cyl(0.7, 1.3, new THREE.MeshStandardMaterial({ color: 0x103a10, emissive: 0x33ff55, emissiveIntensity: 1.5 }), 16); pled.position.set(-8, H / 2 + 0.3, 2); g.add(pled);
  // strap lug on the right side (viewer's left when facing the back)
  const lug = rbox(3.5, 8, 6, 1.2, satin); lug.position.set(W / 2 + 1.2, 12, -4); g.add(lug);

  g.rotation.y = -0.5; g.rotation.x = 0.05;
  const holder = new THREE.Group(); holder.add(g); holder.position.y = H / 2 + 1;
  return { object: holder, floorY: 0, exposure: 1.1, env: { ambient: 0.3 }, camera: { fov: 20, position: [0, 130, 315], target: [0, 28, 0] } };
}
