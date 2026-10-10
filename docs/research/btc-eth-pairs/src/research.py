"""Main study. Usage: python3 research.py DATA OUT"""
import sys, json, itertools, numpy as np, pandas as pd
from dataclasses import replace, asdict
from engine import Signals, Cfg, simulate, LOOKBACK_DAYS, bars, COSTS
from common import load
from metrics import metrics
DATA, OUT = sys.argv[1], sys.argv[2]
TFS = ["1day", "6hr", "1hr", "30m", "15m"]
WF = {"1day": (90, 30), "6hr": (21, 7), "1hr": (21, 7), "30m": (8, 4), "15m": (4, 2)}   # train days, test days
_cache = {}; n_runs = 0

def sig(tf, df, L_days, hedge, fit_end):
    k = (tf, L_days, hedge, fit_end if hedge == "static" else None)
    if k not in _cache: _cache[k] = Signals(df, tf, bars(tf, L_days), hedge, static_fit_end=fit_end)
    return _cache[k]

def run(tf, df, cfg, a, b, fit_end, **kw):
    global n_runs; n_runs += 1
    return simulate(sig(tf, df, cfg.L_days, cfg.hedge, fit_end), cfg, a, b, **kw)

def brief(m):
    keys = ["ret_pct", "net", "gross", "costs", "funding", "max_dd_pct", "sharpe", "trades", "win_rate", "profit_factor", "wk_mean", "time_in_mkt_pct"]
    return {k: (None if (isinstance(m[k], float) and not np.isfinite(m[k])) else round(m[k], 3) if isinstance(m[k], float) else m[k]) for k in keys}

def score(m):
    if m["trades"] < 3: return -np.inf
    return m["ret_pct"] / max(abs(m["max_dd_pct"]), 2.0)

def benchmark_cfg(tf):
    return Cfg(L_days=LOOKBACK_DAYS[tf][1], hedge="ratio", rule="pct", entry=1.0, exit=0.25, stop=None,
               max_hold_frac=None, sizing="fixed5050", fixed_gross=1.0, vol_emergency=False, risk_limits=False)

def base_cfg(tf):
    return Cfg(L_days=LOOKBACK_DAYS[tf][1])

def core_grid(tf):
    return [replace(base_cfg(tf), L_days=L, entry=e, exit=x)
            for L in LOOKBACK_DAYS[tf] for e in (1.5, 2.0, 2.5) for x in (0.0, 0.5)]

out = {}
for tf in TFS:
    df = load(DATA, tf); n = len(df)
    Lmax = bars(tf, max(LOOKBACK_DAYS[tf]))
    tr_end, va_end = int(0.5 * n), int(0.7 * n)
    R = dict(n=n, start=str(df.index[0]), end=str(df.index[-1]), warmup_end=str(df.index[Lmax]),
             train=[str(df.index[Lmax]), str(df.index[tr_end])], val=[str(df.index[tr_end]), str(df.index[va_end])],
             test=[str(df.index[va_end]), str(df.index[-1])])
    # ---- 1. user's 1% benchmark over whole tradable period and the untouched test segment
    bc = benchmark_cfg(tf); R["benchmark"] = {}
    for cost in COSTS:
        full = metrics(run(tf, df, bc, Lmax, n, tr_end, cost=cost)); test = metrics(run(tf, df, bc, va_end, n, tr_end, cost=cost))
        R["benchmark"][cost] = dict(full=full, test=test)
    # benchmark sensitivity to the % threshold (same simple rule)
    R["benchmark_thresholds"] = {}
    for p in (0.5, 0.75, 1.0, 1.25, 1.5, 2.0):
        m = metrics(run(tf, df, replace(bc, entry=p), Lmax, n, tr_end))
        R["benchmark_thresholds"][p] = brief(m)
    # ---- 2. one-factor design tables (base costs), dev = [Lmax, va_end), test = [va_end, n)
    b0 = base_cfg(tf); fac = {}
    variants = {
      "hedge": {h: replace(b0, hedge=h) for h in ["roll", "static", "retbeta", "ratio"]},
      "lookback_days": {L: replace(b0, L_days=L) for L in LOOKBACK_DAYS[tf]},
      "entry_pct": {f"{p}%": replace(b0, rule="pct", entry=p, exit=0.25, stop=1.0) for p in (0.5, 0.75, 1.0, 1.25, 1.5, 2.0)},
      "entry_z": {f"|z|>{z}": replace(b0, entry=z, exit=min(0.5, z / 3)) for z in (1.0, 1.5, 2.0, 2.5, 3.0)},
      "exit": {**{f"z->{x}": replace(b0, exit=x) for x in (0.0, 0.25, 0.5, 1.0)},
               "pct 75% converge": replace(b0, rule="pct", entry=1.0, exit=0.25, stop=1.0),
               "pct 100% converge": replace(b0, rule="pct", entry=1.0, exit=0.0, stop=1.0)},
      "asymmetric": {f"in {e} / out {x}": replace(b0, entry=e, exit=x) for e in (1.5, 2.0, 2.5) for x in (0.0, 0.5, 1.0)},
      "max_hold": {f"{h}xL" if h else "none": replace(b0, max_hold_frac=h) for h in (0.25, 0.5, 1.0, None)},
      "stop": {f"+{s}z" if s else "none": replace(b0, stop=s) for s in (1.0, 1.5, 2.5, None)},
      "sizing": {s: replace(b0, sizing=s) for s in ["beta", "dollar", "vol"]},
      "filters": {"vol-emergency only (default)": b0, "none": replace(b0, vol_emergency=False),
                  "+coint filter": replace(b0, coint_filter=True), "+corr filter": replace(b0, corr_filter=True),
                  "+coint+corr": replace(b0, coint_filter=True, corr_filter=True)},
    }
    for name, vs in variants.items():
        fac[name] = {}
        for k, c in vs.items():
            fac[name][str(k)] = dict(dev=brief(metrics(run(tf, df, c, Lmax, va_end, tr_end))),
                                     test=brief(metrics(run(tf, df, c, va_end, n, tr_end))))
    R["factors"] = fac
    # rank stability between dev and test across every design variant
    devs, tests = [], []
    for vs in fac.values():
        for v in vs.values(): devs.append(v["dev"]["ret_pct"]); tests.append(v["test"]["ret_pct"])
    R["dev_test_rank_corr"] = float(pd.Series(devs).rank().corr(pd.Series(tests).rank()))
    # ---- 3. locked selection: core grid scored on train, top-3 checked on validation, test once
    grid = core_grid(tf)
    sc = [(score(metrics(run(tf, df, c, Lmax, tr_end, tr_end))), i) for i, c in enumerate(grid)]
    top = [i for s, i in sorted(sc, reverse=True)[:3] if s > 0]
    best, best_v = None, -np.inf
    for i in top:
        mv = metrics(run(tf, df, grid[i], tr_end, va_end, tr_end))
        if mv["ret_pct"] > 0 and score(mv) > best_v: best, best_v = i, score(mv)
    R["locked"] = dict(train_scores={str(asdict(grid[i])): s for s, i in sc}, chosen=None)
    if best is not None:
        c = grid[best]; R["locked"]["chosen"] = dict(L_days=c.L_days, entry=c.entry, exit=c.exit)
        R["locked"]["test"] = {cost: metrics(run(tf, df, c, va_end, n, tr_end, cost=cost)) for cost in COSTS}
    else:
        R["locked"]["decision"] = "NO TRADE: no config positive on both train and validation"
    # ---- 4. walk-forward over the core grid
    trd, ted = WF[tf]; tb, eb = bars(tf, trd), bars(tf, ted)
    s0 = Lmax + tb; folds = []; pieces = {c: [] for c in COSTS}; tlist = {c: [] for c in COSTS}
    eqs = {c: 5000.0 for c in COSTS}
    while s0 + eb // 2 < n:
        e0 = min(s0 + eb, n)
        sc = [(score(metrics(run(tf, df, c, s0 - tb, s0, s0))), i) for i, c in enumerate(grid)]
        s_best, i_best = max(sc)
        fold = dict(test=[str(df.index[s0]), str(df.index[e0 - 1])], train_score=float(s_best) if np.isfinite(s_best) else None)
        if s_best > 0:
            c = grid[i_best]; fold.update(L_days=c.L_days, entry=c.entry, exit=c.exit)
            for cost in COSTS:
                r = run(tf, df, c, s0, e0, s0, cost=cost, capital=eqs[cost])
                pieces[cost].append(r.eq); eqs[cost] = float(r.eq.iloc[-1])
                if len(r.trades): tlist[cost].append(r.trades)
                if cost == "base": fold["net"] = float(r.eq.iloc[-1] - r.eq.iloc[0]); fold["trades"] = len(r.trades)
        else:
            fold.update(decision="flat (nothing positive in training)")
            for cost in COSTS:
                pieces[cost].append(pd.Series(eqs[cost], index=df.index[s0:e0]))
        folds.append(fold); s0 = e0
    R["walk_forward"] = dict(train_days=trd, test_days=ted, folds=folds)
    wf_res = {}
    for cost in COSTS:
        from engine import Result
        eq = pd.concat(pieces[cost]); eq = eq[~eq.index.duplicated()]
        td = pd.concat(tlist[cost]) if tlist[cost] else pd.DataFrame(columns=["net", "gross", "costs", "funding", "reason", "entry_time", "exit_time"])
        expo = pd.Series(0.0, index=eq.index)
        for _, t in td.iterrows(): expo[(expo.index >= t.entry_time) & (expo.index < t.exit_time)] = 1.0
        rr = Result(eq, expo, td.reset_index(drop=True), float(td.costs.sum()) if len(td) else 0, 0)
        wf_res[cost] = metrics(rr)
        if cost == "base":
            eq.to_csv(f"{OUT}/wf_equity_{tf}.csv"); td.to_csv(f"{OUT}/wf_trades_{tf}.csv", index=False)
    R["walk_forward"]["metrics"] = wf_res
    params = [(f.get("L_days"), f.get("entry"), f.get("exit")) for f in folds]
    R["walk_forward"]["distinct_param_sets"] = len(set(params)); R["walk_forward"]["n_folds"] = len(folds)
    # benchmark over the same walk-forward OOS window for a like-for-like comparison
    wf_start = Lmax + tb
    R["benchmark_wf_window"] = {cost: metrics(run(tf, df, bc, wf_start, n, tr_end, cost=cost)) for cost in COSTS}
    br = run(tf, df, bc, Lmax, n, tr_end); br.eq.to_csv(f"{OUT}/bench_equity_{tf}.csv"); br.trades.to_csv(f"{OUT}/bench_trades_{tf}.csv", index=False)
    out[tf] = R
    wm = wf_res["base"]; bm = R["benchmark"]["base"]["full"]
    print(f"{tf:5s} bench(full,base) {bm['ret_pct']:+7.2f}% tr {bm['trades']:4d} DD {bm['max_dd_pct']:6.2f}% | "
          f"WF-OOS(base) {wm['ret_pct']:+7.2f}% tr {wm['trades']:3d} DD {wm['max_dd_pct']:6.2f}% folds {len(folds)} distinct {R['walk_forward']['distinct_param_sets']} | "
          f"locked {R['locked']['chosen']} | dev/test rank corr {R['dev_test_rank_corr']:+.2f}", flush=True)
out["_meta"] = dict(total_backtests=n_runs)
def clean(o):
    if isinstance(o, dict): return {str(k): clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)): return [clean(v) for v in o]
    if isinstance(o, (np.floating, float)): return None if not np.isfinite(o) else float(o)
    if isinstance(o, (np.integer,)): return int(o)
    return o
json.dump(clean(out), open(f"{OUT}/research.json", "w"), indent=1)
print("total backtests run:", n_runs)
