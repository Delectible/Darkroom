# Picker artwork renderer

Photoreal product shots for the stock / camera picker, modelled in three.js
and path-traced with three-gpu-pathtracer in headless Chromium. Every design
(labels, bodies) is original; nothing is copied from real packaging.

```bash
cd tool/render
git clone --depth 1 --branch r185 https://github.com/mrdoob/three.js.git three
git clone --depth 1 https://github.com/gkjohnson/three-mesh-bvh.git
git clone --depth 1 https://github.com/gkjohnson/three-gpu-pathtracer.git
python3 gen_bvh.py            # run inside three-mesh-bvh/ (expands its *.template.js)
npm i -g playwright           # plus a Chromium for it
node serve.mjs &              # static server on :8765
./render_item.sh canister_portra 1024 192 out/   # object, floor and shadow passes
```

* `items/*.js` — one module per item (`canister_ektar|portra|hp5`, `cartridge`,
  `ccd`, `floppy`, `flip`, `camcorder`). `lib/studio.js` is the procedural
  softbox HDRI, `lib/parts.js` shared parts and materials.
* `render.html?item=...&mode=raster` gives an instant preview; `mode=pt`
  (default) path-traces. `composite.py` lifts the contact shadow from the floor
  pass onto a transparent background. Convert to WebP for `assets/artwork/`.
