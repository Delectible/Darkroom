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
npm i playwright              # uses a local Chromium (headless, SwiftShader WebGL)
node serve.mjs &              # static server on :8765
./render_item.sh canister_portra 1024 128 out/   # object, floor and shadow passes
```

Labels are canvas text in **Inter Display** and **DejaVu Sans Condensed**;
install both (e.g. Inter's `extras/ttf` into `~/.local/share/fonts`, and
`fonts-dejavu-extra`) or the boxes render in a fallback serif. A 1024 px
item at 128 spp takes roughly 9 minutes on a CPU.

* `items/*.js` — one module per item (`canister_ektar|portra|hp5`, `cartridge`,
  `instant`, `ccd`, `floppy`, `flip`, `camcorder`). `lib/studio.js` is the
  procedural softbox HDRI, `lib/parts.js` shared parts and materials,
  `lib/tex.js` canvas textures, `lib/logo.js` the Darkroom rabbit for labels
  (same geometry as `tool/icon/make_icons.py`).
* `shoot.mjs` splices `scenes/head.html` (import map) into a scene, loads it
  in headless Chromium and saves the PNG the page posts back.
* `render.html?item=...&mode=raster` gives an instant preview; `mode=pt`
  (default) path-traces. `composite.py` lifts the contact shadow from the floor
  pass onto a transparent background. Convert to WebP for `assets/artwork/`
(Pillow or `cwebp`, quality 90), named after the stock / camera id: `canister_ektar` ->
`ektar100.webp`, `canister_portra` -> `portra400`, `canister_hp5` ->
`hp5plus400`, `cartridge` -> `super8`, `instant` -> `polaroid600`,
`floppy` -> `floppy99`, `ccd` -> `ccd2003`, `flip` -> `flipphone`,
`camcorder` -> `camcorder90`.
