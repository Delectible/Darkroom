import numpy as np, pandas as pd
from engine import Signals, Cfg, simulate
from metrics import metrics
rng = np.random.default_rng(0)
def synth(n, phi, seed):
    r = np.random.default_rng(seed)
    lb = np.log(50000) + np.cumsum(r.normal(0, 0.004, n))
    u = np.zeros(n)
    for i in range(1, n): u[i] = phi * u[i - 1] + r.normal(0, 0.003)
    le = np.log(2500) + 1.2 * (lb - lb[0]) + u
    idx = pd.date_range("2026-01-01", periods=n, freq="1h", tz="UTC")
    ce, cb = np.exp(le), np.exp(lb)
    return pd.DataFrame(dict(open_e=np.r_[ce[0], ce[:-1]], close_e=ce, open_b=np.r_[cb[0], cb[:-1]], close_b=cb), index=idx)
cfg = Cfg(L_days=7, entry=2.0, exit=0.0)
for name, phi in [("mean-reverting (phi=0.9)", 0.9), ("random walk (phi=1)", 1.0)]:
    df = synth(3000, phi, 1); s = Signals(df, "1hr", 168, "roll")
    for cost in ["optimistic", "base"]:
        r = simulate(s, cfg, 168, len(df), cost=cost); m = metrics(r)
        recon = abs(r.trades.net.sum() - (r.eq.iloc[-1] - 5000)) if len(r.trades) else 0
        print(f"{name:26s} {cost:10s} ret {m['ret_pct']:+7.2f}%  trades {m['trades']:3d}  win {m['win_rate']:.0f}%  reconcile err ${recon:.6f}")
# look-ahead: run on truncated data, decisions up to the cut must match
df = synth(3000, 0.9, 2); full = simulate(Signals(df, "1hr", 168, "roll"), cfg, 168, 3000)
cut = simulate(Signals(df.iloc[:2000], "1hr", 168, "roll"), cfg, 168, 2000)
a = full.eq.iloc[:1800]; b = cut.eq.iloc[:1800]
print("look-ahead check, max equity diff before cut:", float((a - b).abs().max()))
for h in ["static", "retbeta", "ratio"]:
    full = simulate(Signals(df, "1hr", 168, h, static_fit_end=1000), cfg, 1000, 3000)
    cut = simulate(Signals(df.iloc[:2400], "1hr", 168, h, static_fit_end=1000), cfg, 1000, 2400)
    print(f"  {h:8s} max diff:", float((full.eq.iloc[:1300] - cut.eq.iloc[:1300]).abs().max()))
