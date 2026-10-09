"""Copies export_glb.py's output into the app (assets/body3d):

    python3 bundle_live.py OUT assets/body3d

<mode>.glb (turned into Flutter Scene packages by hook/build.dart),
studio.hdr, and one manifest.json: design space, each body's layout,
press travel, alternative shutter and strap lug, and the studio's light
(diffuse SH, exposure, tone mapping).
"""
import json
import os
import shutil
import sys

W, H = 412.0, 968.0
CAP, THICK = W * 0.2, W * 0.14


def main(src, dst):
    os.makedirs(dst, exist_ok=True)
    studio = json.load(open(os.path.join(src, 'studio.json')))
    shutil.copy(os.path.join(src, 'studio.hdr'), os.path.join(dst, 'studio.hdr'))
    man = {'layout': {}, 'studio': studio}
    for mode in ('film', 'digital'):
        meta = json.load(open(os.path.join(src, f'{mode}.json')))
        shutil.copy(os.path.join(src, f'{mode}.glb'), os.path.join(dst, f'{mode}.glb'))
        w, h = meta['design']
        man['design'] = {'w': w, 'h': h, 'cutY': meta['cutY'], 'dist': meta['dist'], 'band': meta['band']}
        lay = meta['layout']
        man['layout'][mode] = lay
        side = 1 if lay['lug'] == 'right' else -1
        lug = meta.get('lug') or [side * ((W + 2 * CAP) / 2 - 1), H / 2 - H * 0.24, -THICK / 2 - 7]
        man[mode] = {'scene': f'{mode}.glb', 'alt': meta['alt'], 'press': meta['press'], 'lug': lug}
        print(mode, f"{os.path.getsize(os.path.join(dst, f'{mode}.glb')) / 1e6:.1f} MB")
    with open(os.path.join(dst, 'manifest.json'), 'w') as f:
        json.dump(man, f, indent=1)


if __name__ == '__main__':
    main(*sys.argv[1:3])
