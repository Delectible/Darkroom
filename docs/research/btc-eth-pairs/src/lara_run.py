"""Reproduce Lara's run on the uploaded Binance 1h candles. Usage: lara_run.py ALIGNED_CSV OUT_DIR"""
import sys, numpy as np, pandas as pd
from dataclasses import replace
from engine import Signals, Cfg, simulate, Result
from metrics import metrics
src, out = sys.argv[1], sys.argv[2]
j = pd.read_csv(src, index_col=0, parse_dates=True)
seg = (j.index.to_series().diff() != pd.Timedelta(hours=1)).cumsum()
L = 72
BASE = Cfg(L_days=3, hedge="ratio", rule="pct", entry=1.0, exit=0.0, stop=3.0,   # stop at 1% x (1+3) = 4% divergence
           max_hold_frac=1.0, sizing="fixed5050", fixed_gross=1.0,               # max hold 72 bars; $2,500 a leg at start, compounding
           vol_emergency=False, risk_limits=False)
def run(cfg, fill_bps=6.0, delay="open"):
    eq = 5000.0; eqs, trs = [], []
    for _, g in j.groupby(seg):
        s = Signals(g, "1hr", L, "ratio")
        r = simulate(s, cfg, L, len(g), fill_bps=fill_bps, fund_bps_8h=0.0, delay=delay, capital=eq)
        eqs.append(r.eq); eq = float(r.eq.iloc[-1])
        if len(r.trades): trs.append(r.trades)
    E = pd.concat(eqs); T = pd.concat(trs).reset_index(drop=True) if trs else pd.DataFrame()
    expo = pd.Series(0.0, index=E.index)
    for _, t in T.iterrows(): expo[(expo.index >= t.entry_time) & (expo.index < t.exit_time)] = 1.0
    return Result(E, expo, T, 0, 0)
variants = {
  "1. Lara as described: fill next-bar open, 4% divergence stop, 6 bps/fill": (BASE, 6.0, "open"),
  "2. Same, but fill at the signal bar's close": (BASE, 6.0, "same"),
  "3. Fill next open, stop = 4% loss on the trade instead": (replace(BASE, stop=None, loss_stop=0.04), 6.0, "open"),
  "4. Fill at signal close + 4% loss stop": (replace(BASE, stop=None, loss_stop=0.04), 6.0, "same"),
  "5. Costs 6 bps per leg per round trip (3 per fill), next open": (BASE, 3.0, "open"),
  "6. Costs 3 per fill + fill at signal close": (BASE, 3.0, "same"),
}
days = sum((g.index[-1] - g.index[L]) / pd.Timedelta(days=1) for _, g in j.groupby(seg))
print(f"Tradable days after a 72 h warm-up in each of {seg.nunique()} segments: {days:.0f}\n")
rows = []
for name, (cfg, fb, dl) in variants.items():
    r = run(cfg, fb, dl); g = run(cfg, 0.0, dl); m = metrics(r); T = r.trades
    gross_c = (g.eq.iloc[-1] / 5000 - 1) * 100
    ann = lambda x: ((1 + x / 100) ** (365 / days) - 1) * 100
    reasons = T.reason.value_counts().to_dict() if len(T) else {}
    print(f"{name}\n   trades {len(T)} ({len(T)/days*365:.0f}/yr pace) | gross {gross_c:+.2f}% (ann {ann(gross_c):+.1f}%) | net {m['ret_pct']:+.2f}% (ann {ann(m['ret_pct']):+.1f}%) | "
          f"end ${m['end']:,.0f} | costs ${T.costs.sum():,.0f} | win {m['win_rate']:.0f}% | avg hold {m['avg_hold_h']:.0f} h | max DD {m['max_dd_pct']:.2f}% | exits {reasons}")
    if name.startswith("1."):
        T.to_csv(f"{out}/lara_trades_v1.csv", index=False); r.eq.to_csv(f"{out}/lara_equity_v1.csv")
        per = T.assign(seg=pd.cut(T.entry_time, [j.index[0]] + [g.index[-1] for _, g in j.groupby(seg)], labels=False))
        print("   by segment:", {int(k): (len(v), round(v.net.sum(), 0)) for k, v in per.groupby("seg")})
