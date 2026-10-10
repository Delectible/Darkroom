"""Stress tests + Monte Carlo on fixed reference strategies (no re-selection)."""
import sys, json, numpy as np, pandas as pd
from dataclasses import replace
from engine import Signals, Cfg, simulate, bars, LOOKBACK_DAYS
from common import load
from metrics import metrics
DATA, OUT = sys.argv[1], sys.argv[2]
REF = {
  "A: your 1% rule @1h": ("1hr", Cfg(L_days=7, hedge="ratio", rule="pct", entry=1.0, exit=0.25, stop=None, max_hold_frac=None,
                                      sizing="fixed5050", fixed_gross=1.0, vol_emergency=False, risk_limits=False)),
  "B: z-score @6h (WF modal: 28d, in 1.5, out 0.5)": ("6hr", Cfg(L_days=28, entry=1.5, exit=0.5)),
  "C: z-score @1h (WF modal: 7d, in 2.5, out 0)": ("1hr", Cfg(L_days=7, entry=2.5, exit=0.0)),
}
def transform(df, fn_e=None, fn_b=None):
    d = df.copy()
    for leg, fn in (("e", fn_e), ("b", fn_b)):
        if fn is None: continue
        for col in ("open", "close"):
            lp = np.log(d[f"{col}_{leg}"].values); d[f"{col}_{leg}"] = np.exp(fn(lp, col))
    return d
def run(df, tf, cfg, **kw):
    s = Signals(df, tf, bars(tf, cfg.L_days), cfg.hedge)
    st = bars(tf, max(LOOKBACK_DAYS[tf]))
    return simulate(s, cfg, st, len(df), **kw)
out = {}
for name, (tf, cfg) in REF.items():
    df = load(DATA, tf); n = len(df); mid = n // 2
    base = run(df, tf, cfg); mb = metrics(base)
    td = base.trades
    per_trade = dict(n=len(td), gross_bps_of_notional=float((td.gross / td.gross_notional).mean() * 1e4) if len(td) else None,
                     cost_bps_of_notional=float((td.costs / td.gross_notional).mean() * 1e4) if len(td) else None,
                     funding_bps_of_notional=float((td.funding / td.gross_notional).mean() * 1e4) if len(td) else None)
    rows = {"baseline (base costs)": mb}
    rows["optimistic costs"] = metrics(run(df, tf, cfg, cost="optimistic"))
    rows["pessimistic costs"] = metrics(run(df, tf, cfg, cost="pessimistic"))
    rows["fees x2 (12 bps/fill)"] = metrics(run(df, tf, cfg, fill_bps=12))
    rows["slippage x2 (8.5 bps/fill)"] = metrics(run(df, tf, cfg, fill_bps=8.5))
    rows["fees x2 + slippage x2 (13.5 bps)"] = metrics(run(df, tf, cfg, fill_bps=13.5))
    rows["execution 1 bar late"] = metrics(run(df, tf, cfg, delay="close"))
    rows["BTC leg fills 1 bar after ETH"] = metrics(run(df, tf, cfg, leg_delay=True))
    rows["funding 5 bps/8h on gross"] = metrics(run(df, tf, cfg, fund_bps_8h=5))
    # vol doubles from mid-sample on (both legs)
    def dbl(lp, col):
        r = lp.copy(); base_lvl = lp[mid]; r[mid:] = base_lvl + 2 * (lp[mid:] - base_lvl); return r
    rows["volatility doubles mid-sample"] = metrics(run(transform(df, dbl, dbl), tf, cfg))
    # correlation drops to ~0.6 from mid-sample (ETH gets independent noise), 30 seeds
    re_ = np.diff(np.log(df.close_e.values)); rb = np.diff(np.log(df.close_b.values)); rho = np.corrcoef(re_, rb)[0, 1]
    sn = re_.std() * np.sqrt((rho / 0.6) ** 2 - 1)
    cr = []
    for seed in range(30):
        g = np.random.default_rng(seed); noise = np.r_[np.zeros(mid), np.cumsum(g.normal(0, sn, n - mid))]
        cr.append(metrics(run(transform(df, lambda lp, col: lp + noise), tf, cfg))["ret_pct"])
    rows["correlation falls to 0.6 (30 seeds)"] = dict(ret_pct=float(np.mean(cr)), ret_p5=float(np.percentile(cr, 5)), ret_worst=float(np.min(cr)))
    # persistent divergence: ETH loses 10% vs BTC over 3 days and never comes back; 60 random start times
    st = bars(tf, max(LOOKBACK_DAYS[tf])); ramp = bars(tf, 3)
    pdv, pdd = [], []
    for seed in range(60):
        t0 = np.random.default_rng(1000 + seed).integers(st, n - ramp - 2)
        shift = np.zeros(n); shift[t0:t0 + ramp] = np.linspace(0, -0.10, ramp); shift[t0 + ramp:] = -0.10
        m = metrics(run(transform(df, lambda lp, col: lp + shift), tf, cfg)); pdv.append(m["ret_pct"]); pdd.append(m["max_dd_pct"])
    rows["spread breaks: ETH -10% vs BTC, permanent (60 runs)"] = dict(ret_pct=float(np.mean(pdv)), ret_worst=float(np.min(pdv)), dd_worst=float(np.min(pdd)))
    # crash: one-bar gap BTC -15%, ETH -22%, permanent; 60 random times
    cv, cd = [], []
    for seed in range(60):
        t0 = np.random.default_rng(2000 + seed).integers(st, n - 2)
        def gap(k): 
            def f(lp, col):
                r = lp.copy(); s = t0 if col == "close" else t0 + 1; r[s:] += np.log(1 + k); return r
            return f
        m = metrics(run(transform(df, gap(-0.22), gap(-0.15)), tf, cfg)); cv.append(m["ret_pct"]); cd.append(m["max_dd_pct"])
    rows["crash bar: BTC -15%, ETH -22% (60 runs)"] = dict(ret_pct=float(np.mean(cv)), ret_worst=float(np.min(cv)), dd_worst=float(np.min(cd)))
    # Monte Carlo: bootstrap per-trade returns, 1 year, sizing multipliers
    mc = {}
    if len(td) >= 5:
        r = (td.net / td.eq0).values; days = (base.eq.index[-1] - base.eq.index[0]) / pd.Timedelta(days=1)
        k = max(1, int(round(len(td) / days * 365)))
        g = np.random.default_rng(7)
        for mult in (0.5, 1.0, 2.0, 4.0):
            sims = g.choice(r, size=(10000, k)) * mult
            eq = np.cumprod(1 + np.clip(sims, -0.99, None), axis=1)
            dd = (eq / np.maximum.accumulate(np.c_[np.ones(10000), eq], axis=1)[:, 1:] - 1).min(axis=1)
            mc[f"{mult}x"] = dict(trades_per_year=k, median_year_ret_pct=float(np.median(eq[:, -1] - 1) * 100),
                                  p5_year_ret_pct=float(np.percentile(eq[:, -1] - 1, 5) * 100),
                                  p_loss=float((eq[:, -1] < 1).mean()), p_dd10=float((dd < -0.10).mean()),
                                  p_dd20=float((dd < -0.20).mean()), p_dd30=float((dd < -0.30).mean()),
                                  p_ruin50=float((eq.min(axis=1) < 0.5).mean()),
                                  p_3pct_week=float((eq[:, -1] >= 1.03 ** 52).mean()))
        # same bootstrap with the mean edge removed (what happens if the historical edge was luck)
        r0 = r - r.mean() - (td.costs / td.eq0).mean() * 0      # zero-mean before costs already inside r
        sims = g.choice(r - r.mean(), size=(10000, k)); eq = np.cumprod(1 + sims, axis=1)
        mc["1x, zero edge"] = dict(median_year_ret_pct=float(np.median(eq[:, -1] - 1) * 100), p_loss=float((eq[:, -1] < 1).mean()))
    out[name] = dict(tf=tf, per_trade=per_trade, stress=rows, monte_carlo=mc)
    print(f"\n### {name}  trades {len(td)}  gross/trade {per_trade['gross_bps_of_notional']} bps of notional, costs {per_trade['cost_bps_of_notional']} bps, funding {per_trade['funding_bps_of_notional']} bps")
    for k, m in rows.items():
        extra = "".join(f" {x}={m[x]:+.2f}" for x in ("ret_p5", "ret_worst", "dd_worst") if x in m)
        print(f"   {k:52s} ret {m['ret_pct']:+7.2f}%" + (f"  DD {m['max_dd_pct']:6.2f}%  trades {m['trades']}" if "trades" in m else "") + extra)
    for k, v in mc.items(): print("   MC", k, v)
def clean(o):
    if isinstance(o, dict): return {str(k): clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)): return [clean(v) for v in o]
    if isinstance(o, (np.floating, float)): return None if not np.isfinite(o) else float(o)
    if isinstance(o, (np.integer,)): return int(o)
    return o
json.dump(clean(out), open(f"{OUT}/stress.json", "w"), indent=1)
