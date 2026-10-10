import json, numpy as np, pandas as pd, warnings
from statsmodels.tsa.stattools import coint
from common import load, rolling_ols
from engine import Result
from metrics import metrics
warnings.filterwarnings("ignore")
D, O = "../data", "../out"
R = json.load(open(f"{O}/research.json")); S = json.load(open(f"{O}/stress.json")); ST = json.load(open(f"{O}/study.json"))
def eqser(path, step=1):
    e = pd.read_csv(path, index_col=0, parse_dates=True).iloc[:, 0]
    e = e.iloc[::step] if step > 1 else e
    return [[int(t.timestamp() * 1000), round(float(v), 2)] for t, v in e.items()]
def trades_metrics(eqpath, trpath):
    e = pd.read_csv(eqpath, index_col=0, parse_dates=True).iloc[:, 0]
    t = pd.read_csv(trpath, parse_dates=["entry_time", "exit_time"]) if pd.read_csv(trpath).shape[0] else pd.DataFrame(columns=["net","gross","costs","funding","reason","entry_time","exit_time","gross_notional"])
    expo = pd.Series(0.0, index=e.index)
    for _, r in t.iterrows(): expo[(expo.index >= r.entry_time) & (expo.index < r.exit_time)] = r.gross_notional / 5000 if "gross_notional" in r else 1
    return metrics(Result(e, expo, t, 0, 0)), e
def weeks(e):
    from metrics import weekly
    p, _ = weekly(e); t0 = e.index[0]
    return [[str((t0 + pd.Timedelta(days=7 * int(k))).date()), round(float(v), 2)] for k, v in p.items()]
TFL = {"1day": "1 day", "6hr": "6 hour", "1hr": "1 hour", "30m": "30 min", "15m": "15 min"}
variants = []; eq_series = {}; wk_series = {}
for tf in ["1day", "6hr", "1hr", "30m", "15m"]:
    m, e = trades_metrics(f"{O}/bench_equity_{tf}.csv", f"{O}/bench_trades_{tf}.csv")
    variants.append(dict(id=f"bench_{tf}", name=f"Your 1% rule · {TFL[tf]}", kind="benchmark", tf=tf, m=m,
                         cost=R[tf]["benchmark"], test=R[tf]["benchmark"]["base"]["test"]))
    eq_series[f"bench_{tf}"] = eqser(f"{O}/bench_equity_{tf}.csv", 6 if tf in ("1hr", "30m", "15m") else 1)
    wk_series[f"bench_{tf}"] = weeks(e)
for tf in ["1day", "6hr", "1hr", "30m", "15m"]:
    m, e = trades_metrics(f"{O}/wf_equity_{tf}.csv", f"{O}/wf_trades_{tf}.csv")
    variants.append(dict(id=f"wf_{tf}", name=f"Z-score walk-forward · {TFL[tf]}", kind="walkforward", tf=tf, m=m,
                         cost=R[tf]["walk_forward"]["metrics"], folds=R[tf]["walk_forward"]["folds"]))
    eq_series[f"wf_{tf}"] = eqser(f"{O}/wf_equity_{tf}.csv", 6 if tf in ("1hr", "30m", "15m") else 1)
    wk_series[f"wf_{tf}"] = weeks(e)
locked = {tf: R[tf]["locked"].get("chosen") or R[tf]["locked"].get("decision") for tf in R if tf != "_meta"}
locked_test = {tf: R[tf]["locked"]["test"] for tf in R if tf != "_meta" and "test" in R[tf]["locked"]}
# relationship series (daily)
j = load(D, "1day"); le, lb = np.log(j.close_e.values), np.log(j.close_b.values)
a, b = rolling_ols(le, lb, 60)
p = [None] * len(j)
for t in range(60, len(j) + 1): p[t - 1] = round(float(coint(le[t - 60:t], lb[t - 60:t])[1]), 4)
rel = [[int(ts.timestamp() * 1000), round(float(np.exp(le[i] - lb[i])), 5), None if not np.isfinite(b[i]) else round(float(b[i]), 3), p[i]] for i, ts in enumerate(j.index)]
scatter = {tf: [[v["dev"]["ret_pct"], v["test"]["ret_pct"], f"{fac}: {k}"] for fac, vs in R[tf]["factors"].items() for k, v in vs.items()] for tf in ["1day", "6hr", "1hr", "30m"]}
rank = {tf: R[tf]["dev_test_rank_corr"] for tf in ["1day", "6hr", "1hr", "30m", "15m"]}
factors = {tf: R[tf]["factors"] for tf in ["1day", "6hr", "1hr", "30m"]}
thresholds = {tf: R[tf]["benchmark_thresholds"] for tf in ["1day", "6hr", "1hr", "30m", "15m"]}
splits = {tf: dict(n=R[tf]["n"], start=R[tf]["start"], end=R[tf]["end"], train=R[tf]["train"], val=R[tf]["val"], test=R[tf]["test"]) for tf in TFL}
def clean(o):
    if isinstance(o, dict): return {str(k): clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)): return [clean(v) for v in o]
    if isinstance(o, (np.floating, float)): return None if not np.isfinite(o) else round(float(o), 4)
    if isinstance(o, (np.integer,)): return int(o)
    if isinstance(o, (np.bool_,)): return bool(o)
    return o
out = dict(variants=variants, eq=eq_series, wk=wk_series, locked=locked, locked_test=locked_test, rel=rel, scatter=scatter,
           rank=rank, factors=factors, thresholds=thresholds, study=ST, stress=S, splits=splits, total_backtests=R["_meta"]["total_backtests"])
s = json.dumps(clean(out), separators=(",", ":"))
open(f"{O}/report_data.json", "w").write(s); print(len(s) // 1024, "KB")
for v in variants:
    m = v["m"]; print(f"{v['name']:32s} weeks {m['weeks']:3d} >=150 {m['wk_ge_target']} pos<150 {m['wk_pos_below']} loss {m['wk_loss']} flat {m['wk_flat']} mean ${m['wk_mean']:.1f} med ${m['wk_median']:.1f} sd ${m['wk_std']:.1f} worst ${m['wk_worst']:.1f} sharpe {m['sharpe']}")
