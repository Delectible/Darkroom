# Copies rendered body sprites into the app (assets/body) and writes its
# manifest with only the turns / states that exist, so the app never asks
# for a frame that isn't bundled (a partial render still works).
#   python3 body/bundle.py RENDER_OUT APP_ASSETS_BODY
import json, os, re, shutil, sys
src, dst = sys.argv[1:3]
man = json.load(open(f'{src}/manifest.json'))
have = {}
for mode in ('film', 'digital'):
    d = f'{src}/{mode}'
    if not os.path.isdir(d): continue
    os.makedirs(f'{dst}/{mode}', exist_ok=True)
    for f in sorted(os.listdir(d)):
        m = re.match(r'^(.+?)(?:-(up|down|mid|w|t))?-a(\d+)\.webp$', f)
        if not m: continue
        part, state, yaw = m.group(1), m.group(2), int(m.group(3))
        have.setdefault((mode, part), {}).setdefault(yaw, set()).add(state)
        shutil.copy2(f'{d}/{f}', f'{dst}/{mode}/{f}')
out = {'px': man['px'], 'parts': {}}
for mode, parts in man['parts'].items():
    for name, p in parts.items():
        got = have.get((mode, name))
        default = (p.get('states') or [None])[0]
        # a turn is usable when its default state is there
        if not got or default not in got.get(0, set()): continue
        q = dict(p)
        q['yaws'] = sorted(y for y, sts in got.items() if default in sts)
        out['parts'].setdefault(mode, {})[name] = q
json.dump(out, open(f'{dst}/manifest.json', 'w'), indent=1)
n = sum(len(v) for v in out['parts'].values())
print(f'bundled {n} parts into {dst}')
