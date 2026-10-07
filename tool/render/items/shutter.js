// Shutter buttons for the camera bodies, rendered straight down as aligned
// layers the app stacks: a fixed base, the button cap (which shifts a little
// against the base as the body tips, for depth) and, for film, the advance
// lever (rotated by the app as it swings).
//
// Item names: shutter_<kind>-<layer>[-down]
//   kind:  digital | digitalrec | film | run
//   layer: base | cap | lever (film only)
// All share one fixed top-down camera, so the layers line up exactly.
import { rbox, brushedMetal, plastic, cyl, decal } from '/lib/parts.js';

export async function build(THREE, item) {
  const [, spec] = item.split('_');
  const [kind, layer, state] = spec.split('-');
  const down = state === 'down';
  const g = new THREE.Group();

  const chrome = new THREE.MeshPhysicalMaterial({ color: 0xeceef0, metalness: 1, roughness: 0.1 });
  const satinChrome = new THREE.MeshPhysicalMaterial({ color: 0xd9dce0, metalness: 1, roughness: 0.22 });
  const blackPlastic = plastic(0x121315, { rough: 0.45, texture: 0.08 });
  const gap = new THREE.MeshStandardMaterial({ color: 0x050505, roughness: 0.9 });

  // Lathe around the Y axis from an [r, y] profile.
  const lathe = (profile, mat, seg = 96) =>
    new THREE.Mesh(new THREE.LatheGeometry(profile.map(([r, y]) => new THREE.Vector2(r, y)), seg), mat);

  let span = 30;
  if (kind === 'digital' || kind === 'digitalrec') {
    if (layer === 'base') {
      // Brushed bezel round a dark well.
      const alu = brushedMetal(0xd3d5d8, 0.28);
      const outer = rbox(26, 2.2, 22, 1.0, alu);
      outer.position.y = 1.1;
      g.add(outer);
      const well = rbox(20.4, 1.0, 16.4, 0.8, gap);
      well.position.y = 1.9;
      g.add(well);
    } else {
      // The key: a soft-cornered block with a gently domed top.
      const keyMat = new THREE.MeshPhysicalMaterial({
        color: 0xb9bdc3,
        metalness: 0.85,
        roughness: 0.28,
        clearcoat: 0.6,
        clearcoatRoughness: 0.2,
      });
      const key = rbox(18.6, 3.2, 14.6, 1.5, keyMat, 8);
      key.position.y = (down ? 2.2 : 3.2) + 1.6;
      g.add(key);
      if (kind === 'digitalrec') {
        const dot = cyl(2.6, 0.25, new THREE.MeshPhysicalMaterial({ color: 0xd8261c, roughness: 0.3, clearcoat: 1 }), 64);
        dot.position.y = key.position.y + 1.62;
        g.add(dot);
      }
    }
  } else if (kind === 'film') {
    span = 40;
    if (layer === 'base') {
      // Knurled collar of the advance-lever hub.
      g.add(lathe([[0, 0], [9.0, 0], [9.0, 2.6], [8.6, 3.0], [6.9, 3.0], [6.9, 2.4], [0, 2.4]], satinChrome));
      const ridge = new THREE.BoxGeometry(0.45, 2.2, 0.7);
      for (let i = 0; i < 90; i++) {
        const a = (i / 90) * Math.PI * 2;
        const m = new THREE.Mesh(ridge, satinChrome);
        m.position.set(Math.cos(a) * 9.0, 1.4, Math.sin(a) * 9.0);
        m.rotation.y = -a;
        g.add(m);
      }
      const well = cyl(6.9, 0.4, gap, 96);
      well.position.y = 2.5;
      g.add(well);
    } else if (layer === 'cap') {
      // Machined chrome release, with turned rings and a cable-release socket.
      const top = down ? 4.0 : 4.9;
      const prof = [[0, top], [1.4, top], [1.5, top - 0.02]];
      for (let r = 1.6; r <= 5.6; r += 0.5) prof.push([r, top - 0.12 * ((r - 1.4) / 4.2) ** 2 - (Math.floor(r * 2) % 2) * 0.03]);
      prof.push([6.0, top - 0.35], [6.2, top - 0.8], [6.2, 2.4], [0, 2.4]);
      g.add(lathe(prof.reverse(), chrome, 128));
      const socket = cyl(1.0, 0.6, gap, 48);
      socket.position.y = top - 0.15;
      g.add(socket);
    } else {
      // Advance lever: a tapered bar to the left of the hub, thumb pad at its tip.
      const len = 15.7;
      const shape = new THREE.Shape();
      shape.moveTo(0, -2.7);
      shape.lineTo(-len, -1.2);
      shape.absarc(-len, 0, 1.2, -Math.PI / 2, Math.PI / 2, true);
      shape.lineTo(0, 2.7);
      shape.absarc(0, 0, 2.7, Math.PI / 2, -Math.PI / 2, true);
      const bar = new THREE.Mesh(
        new THREE.ExtrudeGeometry(shape, { depth: 0.9, bevelEnabled: true, bevelThickness: 0.25, bevelSize: 0.25, bevelSegments: 4, curveSegments: 32 }),
        satinChrome,
      );
      bar.rotation.x = -Math.PI / 2;
      bar.position.y = 3.1;
      g.add(bar);
      const pad = cyl(2.0, 1.6, plastic(0x141210, { rough: 0.55, texture: 0.15 }), 64);
      pad.position.set(-len, 4.4, 0);
      g.add(pad);
    }
  } else {
    // Super 8: a chunky red RUN button in a ribbed black lock collar.
    if (layer === 'base') {
      g.add(lathe([[0, 0], [11.0, 0], [11.0, 2.8], [10.4, 3.4], [8.2, 3.4], [8.0, 2.6], [0, 2.6]], blackPlastic));
      const rib = new THREE.BoxGeometry(0.7, 2.6, 1.0);
      for (let i = 0; i < 36; i++) {
        const a = (i / 36) * Math.PI * 2;
        const m = new THREE.Mesh(rib, blackPlastic);
        m.position.set(Math.cos(a) * 10.9, 1.5, Math.sin(a) * 10.9);
        m.rotation.y = -a;
        g.add(m);
      }
      const well = cyl(8.0, 0.4, gap, 96);
      well.position.y = 2.7;
      g.add(well);
    } else {
      const red = new THREE.MeshPhysicalMaterial({ color: 0xc8231b, roughness: 0.32, clearcoat: 0.8, clearcoatRoughness: 0.25 });
      const top = down ? 3.6 : 5.4;
      g.add(lathe([[0, top], [3.0, top - 0.08], [5.6, top - 0.35], [6.9, top - 0.9], [7.4, top - 1.6], [7.4, 2.6], [0, 2.6]], red, 128));
      const label = decal(7, 3, (c, w, h) => {
        c.fillStyle = 'rgba(255,240,230,0.92)';
        c.font = `800 ${h * 0.8}px "Inter Display"`;
        c.textAlign = 'center';
        c.textBaseline = 'middle';
        c.fillText('RUN', w / 2, h / 2);
      }, { px: 60, rough: 0.5 });
      label.rotation.x = -Math.PI / 2;
      label.position.y = top + 0.02;
      g.add(label);
    }
  }

  // Straight down from above; the studio's key light (front-left) is turned
  // round so it falls from the image's top-left.
  const fov = 6;
  const d = span / 2 / Math.tan((fov / 2) * Math.PI / 180);
  return {
    object: g,
    floorY: 0,
    exposure: 1.0,
    fixedFrame: true,
    envRotation: 180,
    env: { ambient: 0.25 },
    camera: { fov, position: [0, d, 0.001], target: [0, 0, 0] },
  };
}
