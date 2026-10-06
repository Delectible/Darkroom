// Late-90s floppy-disk digital camera (original design) with a 3.5" disk
// half-ejected from the side drive.
import { rbox, slab, plastic, paint, lens, decal, cyl, rubber, brushedMetal } from '/lib/parts.js';
import { canvas, tex, roundRect } from '/lib/tex.js';

function floppy(THREE) {
  const g = new THREE.Group();
  const S = 90, T = 3.3;
  const shellMat = plastic(0x2a4c9c, { rough: 0.42, texture: 0.15, clearcoat: 0.2 });
  const shell = slab(S, 94, T, 2, 0.4, shellMat);
  g.add(shell);
  // label recess with a paper label (exposed, outer end)
  const [lc, lg] = canvas(640, 520);
  lg.fillStyle = '#f6f3ea'; lg.fillRect(0, 0, 640, 520);
  lg.fillStyle = '#d64545'; lg.fillRect(0, 0, 640, 46);
  lg.strokeStyle = '#a9c3e6'; lg.lineWidth = 3; for (let y = 120; y < 520; y += 62) { lg.beginPath(); lg.moveTo(20, y); lg.lineTo(620, y); lg.stroke(); }
  lg.fillStyle = '#1d2a5a'; lg.font = 'italic 600 64px "DejaVu Serif"'; lg.fillText('Summer 99', 40, 168);
  lg.font = 'italic 500 46px "DejaVu Serif"'; lg.fillText('photos  #3', 44, 290);
  lg.fillStyle = '#ffffff'; lg.font = '800 30px "Inter Display"'; lg.fillText('1.44 MB  ·  2HD', 24, 34);
  const label = new THREE.Mesh(new THREE.PlaneGeometry(64, 52), new THREE.MeshPhysicalMaterial({ map: tex(lc), roughness: 0.75 }));
  label.position.set(0, -14, T / 2 + 0.02); g.add(label);
  // metal shutter sits at the far (inserted) end; hub ring on the back face
  const shutter = rbox(36, 26, T + 0.4, 0.3, brushedMetal(0xc8cacc, 0.25)); shutter.position.set(4, 34, 0); g.add(shutter);
  const win = rbox(9, 16, T + 0.6, 0.3, new THREE.MeshStandardMaterial({ color: 0x111111 })); win.position.set(4, 36, 0); g.add(win);
  // write-protect tab corner
  const wp = rbox(4, 4, T + 0.2, 0.3, plastic(0x111111, { rough: 0.5 })); wp.position.set(-40, -41, 0); g.add(wp);
  return g;
}

export async function build(THREE) {
  const root = new THREE.Group();
  const W = 128, H = 98, D = 62;
  const bodyMat = plastic(0x34363a, { rough: 0.5, texture: 0.35 });
  const plate = paint(0xa7abb1, { rough: 0.38, metal: 0.65, clearcoat: 0.5 });
  const black = plastic(0x121314, { rough: 0.45, texture: 0.15 });
  const chrome = new THREE.MeshPhysicalMaterial({ color: 0xdadada, metalness: 1, roughness: 0.14 });

  const body = slab(W, H, D, 7, 3, bodyMat); root.add(body);
  // silver front plate
  const fp = slab(W - 2, H - 2, 3, 6.5, 1, plate); fp.position.z = D / 2 - 0.6; root.add(fp);
  // rubber grip on the right
  const grip = slab(30, H - 6, 10, 9, 3.5, rubber()); grip.position.set(W / 2 - 17, -1, D / 2 + 2.5); root.add(grip);

  // big zoom lens on the left
  const L = lens({
    profile: [[0, 0], [27, 0], [27.5, 1], [27.5, 5], [25, 6], [23.2, 6.2], [23.2, 24], [22.4, 25], [21.4, 25.2], [21.4, 29.5], [20.6, 30.3], [17.2, 30.4]],
    glassR: 15.5, glassZ: 30.1, mat: black,
    rings: [{ profile: [[23.4, 9], [24.2, 9.5], [24.2, 21], [23.4, 21.5]], mat: rubber(0x0f0f0f) }],
  });
  L.position.set(-26, -3, D / 2 + 1); root.add(L);
  for (let i = 0; i < 18; i++) { const ridge = new THREE.Mesh(new THREE.TorusGeometry(24.2, 0.32, 8, 96), rubber(0x0d0d0d)); ridge.position.set(-26, -3, D / 2 + 1 + 10 + i * 0.62); root.add(ridge); }
  const spec = decal(44, 44, (c, w, h) => {
    c.translate(w / 2, h / 2); c.fillStyle = '#e4e4e4'; c.font = `600 ${w * 0.04}px "DejaVu Sans Condensed"`; c.textAlign = 'center'; c.textBaseline = 'middle';
    const txt = '10x ZOOM LENS  f=5.2-52mm  1:1.8-2.4  Ø37  ';
    for (let i = 0; i < txt.length; i++) { c.save(); c.rotate(-Math.PI * 0.9 + i * (Math.PI * 1.8 / txt.length)); c.translate(0, -w * 0.43); c.fillText(txt[i], 0, 0); c.restore(); }
  }, { px: 30 });
  spec.position.set(-26, -3, D / 2 + 1 + 30.45); root.add(spec);

  // flash window and AF sensor on the plate
  const [fc, fg] = canvas(300, 120); fg.fillStyle = '#efefe9'; fg.fillRect(0, 0, 300, 120);
  for (let x = 0; x < 300; x += 6) { fg.fillStyle = 'rgba(0,0,0,0.12)'; fg.fillRect(x, 0, 2, 120); }
  const flash = rbox(26, 10, 2, 0.8, new THREE.MeshPhysicalMaterial({ map: tex(fc), roughness: 0.2, clearcoat: 1, transmission: 0.25, thickness: 0.6 }));
  flash.position.set(14, 28, D / 2 + 1.4); root.add(flash);
  const sensor = rbox(8, 6, 1.6, 0.8, new THREE.MeshPhysicalMaterial({ color: 0x3a0a08, roughness: 0.05, clearcoat: 1 })); sensor.position.set(14, 16, D / 2 + 1.2); root.add(sensor);

  // print
  const logo = decal(54, 16, (c, w, h) => {
    c.fillStyle = '#26282c'; c.textBaseline = 'middle';
    c.font = `800 ${h * 0.42}px "Inter Display"`; c.fillText('DARKROOM', 0, h * 0.3);
    c.font = `600 ${h * 0.2}px "DejaVu Sans Condensed"`; c.fillStyle = '#3a3d42'; c.fillText('DIGITAL STILL CAMERA', 2, h * 0.68);
  }, { px: 24 });
  logo.position.set(6, -40, D / 2 + 1.05); root.add(logo);
  const fd = decal(20, 9, (c, w, h) => {
    c.strokeStyle = '#26282c'; c.lineWidth = h * 0.08; roundRect(c, h * 0.08, h * 0.08, w - h * 0.16, h - h * 0.16, h * 0.15); c.stroke();
    c.fillStyle = '#26282c'; c.font = `800 ${h * 0.5}px "Inter Display"`; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText('FD 1.44', w / 2, h / 2 + 1);
  }, { px: 30 });
  fd.position.set(14, 2, D / 2 + 1.05); root.add(fd);

  // top: shutter on the grip, mode dial, LCD status window
  const sh = cyl(5.4, 3, chrome, 64); sh.position.set(W / 2 - 17, H / 2 + 1.5, 16); root.add(sh);
  const shRing = new THREE.Mesh(new THREE.TorusGeometry(6.6, 1.0, 16, 64), black); shRing.rotation.x = Math.PI / 2; shRing.position.set(W / 2 - 17, H / 2 + 0.6, 16); root.add(shRing);
  const dial = cyl(9, 5, black, 72); dial.position.set(8, H / 2 + 2.5, 2); root.add(dial);
  for (let i = 0; i < 36; i++) { const a = i / 36 * Math.PI * 2; const k = rbox(1.0, 4.4, 1.2, 0.3, black); k.position.set(8 + Math.cos(a) * 9.1, H / 2 + 2.5, 2 + Math.sin(a) * 9.1); k.rotation.y = -a; root.add(k); }
  const dialTop = decal(16, 16, (c, w, h) => { c.fillStyle = '#ddd'; c.font = `700 ${w * 0.12}px "DejaVu Sans"`; c.textAlign = 'center'; c.translate(w / 2, h / 2); ['AUTO', 'P', '▶', 'SET'].forEach((t, i) => { c.save(); c.rotate(i * Math.PI / 2); c.fillText(t, 0, -w * 0.3); c.restore(); }); }, { px: 30 });
  dialTop.rotation.x = -Math.PI / 2; dialTop.position.set(8, H / 2 + 5.05, 2); root.add(dialTop);
  const hotshoe = rbox(20, 2, 18, 0.6, brushedMetal(0xbdbdbd, 0.3)); hotshoe.position.set(-26, H / 2 + 0.6, -6); root.add(hotshoe);

  // drive slot on the right side with the disk sticking out
  const slotZ = -D / 2 + 13;
  const slot = rbox(3, 94, 5.2, 1.2, new THREE.MeshStandardMaterial({ color: 0x050505, roughness: 0.9 }));
  slot.position.set(W / 2 + 0.1, 0, slotZ); root.add(slot);
  const disk = floppy(THREE);
  disk.rotation.z = Math.PI / 2;
  disk.position.set(W / 2 - 17, 0, slotZ);
  root.add(disk);
  const ej = rbox(3, 8, 6, 1, black); ej.position.set(W / 2 + 0.8, -30, slotZ + 10); root.add(ej);

  root.rotation.y = -0.62; root.rotation.x = 0.04;
  const holder = new THREE.Group(); holder.add(root); holder.position.y = H / 2 + 1;
  return { object: holder, floorY: 0, exposure: 1.15, env: { ambient: 0.24 }, camera: { fov: 20, position: [0, 170, 560], target: [0, 40, 0] } };
}
