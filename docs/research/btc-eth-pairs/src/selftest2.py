import numpy as np
from selftest import synth
from engine import Signals, Cfg, simulate
cfg = Cfg(L_days=7, entry=2.0, exit=0.0)
for h in ["roll", "retbeta", "ratio"]:
    rets = []
    for seed in range(30):
        df = synth(3000, 1.0, 100 + seed)
        r = simulate(Signals(df, "1hr", 168, h), cfg, 168, 3000, fill_bps=0, fund_bps_8h=0)
        rets.append(r.eq.iloc[-1] / 5000 - 1)
    rets = np.array(rets) * 100
    print(f"random walk, zero cost, {h:8s}: mean {rets.mean():+.2f}%  sd {rets.std():.2f}%  t={rets.mean()/(rets.std()/np.sqrt(30)):+.2f}")
