"""Copies whole-body renders into the app: every image the manifest names.

    python3 bundle_whole.py RENDER_OUT assets/body3
"""
import json
import os
import shutil
import sys

src, dst = sys.argv[1:3]
man = json.load(open(f'{src}/manifest.json'))
if os.path.isdir(dst):
    shutil.rmtree(dst)
n = 0


def take(info):
    global n
    os.makedirs(os.path.dirname(f"{dst}/{info['path']}"), exist_ok=True)
    shutil.copy2(f"{src}/{info['path']}", f"{dst}/{info['path']}")
    n += 1


for mode in ('film', 'digital'):
    m = man.get(mode)
    if not m:
        continue
    if 'rest' in m:
        take(m['rest'])
    for l in m.get('layers', {}).values():
        take(l)
    for t in m.get('turns', {}).values():
        take(t)
        for s in t.get('shutters', {}).values():
            take(s)
json.dump(man, open(f'{dst}/manifest.json', 'w'), indent=1)
size = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(dst) for f in fs)
print(f'bundled {n} images, {size / 1e6:.1f} MB into {dst}')
