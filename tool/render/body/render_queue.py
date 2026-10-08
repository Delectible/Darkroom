# Renders every body sprite (items/body.js PARTS): resumable (finished
# sprites are skipped), N renders at once, yaw-0 sprites first.
#   python3 body/render_queue.py OUTDIR [--jobs 3] [--only film] [--yaw0] [--dry]
# Needs serve.mjs running on :8765. Writes OUTDIR/<mode>/<file>.webp and
# OUTDIR/manifest.json (sizes, slices, yaws, states) for the app.
import json, os, subprocess, sys, time, argparse, concurrent.futures as cf
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.dirname(here)
ap = argparse.ArgumentParser(); ap.add_argument('out'); ap.add_argument('--jobs', type=int, default=3)
ap.add_argument('--only'); ap.add_argument('--part'); ap.add_argument('--yaw0', action='store_true'); ap.add_argument('--dry', action='store_true')
ap.add_argument('--px', type=float, default=3.5, help='output px per dp'); ap.add_argument('--ss', type=float, default=1.25, help='render supersampling')
args = ap.parse_args()
parts = json.loads(subprocess.check_output(['node', f'{here}/list.mjs'], cwd=root))
jobs = []
for mode, ps in parts.items():
    if args.only and mode != args.only: continue
    for name, p in ps.items():
        if args.part and name != args.part: continue
        states = p.get('states') or [None]
        for yaw in p['yaws']:
            for st in states:
                if st and yaw != 0 and st in (p.get('stateYaw0') or []): continue
                if args.yaw0 and yaw != 0: continue
                jobs.append((mode, name, st, yaw, p))
jobs.sort(key=lambda j: (j[3] != 0, j[3], j[0], j[1]))
man = {m: {n: {k: v for k, v in p.items()} for n, p in ps.items()} for m, ps in parts.items()}
os.makedirs(args.out, exist_ok=True)
json.dump({'px': args.px, 'parts': man}, open(f'{args.out}/manifest.json', 'w'), indent=1)

def render(job):
    mode, name, st, yaw, p = job
    file = f"{name}{'-' + st if st else ''}-a{yaw}"
    out = f'{args.out}/{mode}/{file}.webp'
    if os.path.exists(out): return None
    os.makedirs(os.path.dirname(out), exist_ok=True)
    cw, ch = p['canvas']; px = p.get('px', args.px)
    # turned frames are only seen in motion, decoded at 60 %: render lighter
    ss = args.ss if yaw == 0 else 0.8
    rw, rh = round(cw * px * ss), round(ch * px * ss)
    item = f"body_{mode}-{file}"
    tmp = f'{args.out}/_tmp/{mode}-{file}'; os.makedirs(os.path.dirname(tmp), exist_ok=True)
    spp = p.get('spp', 128) if yaw == 0 else min(p.get('spp', 128), 48)
    t0 = time.time()
    def shoot(q, dst, timeout):
        r = subprocess.run(['node', 'shoot.mjs', f'render.html?{q}', dst, str(timeout)], cwd=root, capture_output=True, text=True)
        if not os.path.exists(dst): raise RuntimeError(r.stdout[-400:] + r.stderr[-400:])
    shoot(f'item={item}&size={rw}&h={rh}&spp={spp}&pass=obj', f'{tmp}_obj.png', 14400)
    if p.get('noShadow'):
        fl = bg = '-'
    else:
        fl, bg = f'{tmp}_floor.png', f'{tmp}_bg.png'
        shoot(f'item={item}&size={rw // 2}&h={rh // 2}&spp=24&pass=floor&bounces=3', fl, 3600)
        shoot(f'item={item}&size={rw // 2}&h={rh // 2}&spp=24&pass=bg&bounces=3', bg, 3600)
    subprocess.check_call(['python3', f'{here}/sprite.py', f'{tmp}_obj.png', fl, bg, out, str(round(cw * px))])
    return f'{mode}/{file} {time.time() - t0:.0f}s'

todo = [j for j in jobs if not os.path.exists(f"{args.out}/{j[0]}/{j[1]}{'-' + j[2] if j[2] else ''}-a{j[3]}.webp")]
print(f'{len(jobs)} sprites, {len(todo)} to render', flush=True)
if args.dry:
    for j in todo: print(j[0], j[1], j[2], j[3])
    sys.exit()
with cf.ThreadPoolExecutor(args.jobs) as ex:
    for f in cf.as_completed([ex.submit(render, j) for j in todo]):
        try:
            r = f.result()
            if r: print('done', r, flush=True)
        except Exception as e:
            print('FAILED', e, flush=True)
print('all done', flush=True)
