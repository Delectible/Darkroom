"""Relationship study: correlation, Engle-Granger, ADF, half-life, rolling stability, variance ratios."""
import sys, json, numpy as np, pandas as pd, warnings
from statsmodels.tsa.stattools import adfuller, coint
from common import load, rolling_ols, half_life, BAR_MIN
warnings.filterwarnings("ignore")
data, out = sys.argv[1], sys.argv[2]
WIN = {"1day": [30, 60, 90], "6hr": [28, 56, 112], "1hr": [72, 168, 336], "30m": [96, 192, 336], "15m": [96, 192, 384]}
res = {}
for tf in ["1day", "6hr", "1hr", "30m", "15m"]:
    j = load(data, tf); le, lb = np.log(j.close_e.values), np.log(j.close_b.values)
    re_, rb = np.diff(le), np.diff(lb)
    r = {"bars": len(j), "start": str(j.index[0]), "end": str(j.index[-1])}
    # full-sample Engle-Granger both directions + static OLS
    r["eg_p_eth_on_btc"] = float(coint(le, lb)[1]); r["eg_p_btc_on_eth"] = float(coint(lb, le)[1])
    b, a = np.polyfit(lb, le, 1); s = le - (a + b * lb)
    r["static_beta"] = float(b); r["adf_p_static_spread"] = float(adfuller(s, autolag="AIC")[1])
    r["half_life_static_bars"] = float(half_life(s)); r["ret_corr"] = float(np.corrcoef(re_, rb)[0, 1])
    r["ret_beta"] = float(np.polyfit(rb, re_, 1)[0])
    r["ratio_change_pct"] = float((np.exp((le[-1] - lb[-1]) - (le[0] - lb[0])) - 1) * 100)
    # variance ratio of the beta=1 log-ratio and of the ret-beta-hedged spread: VR(q) <1 => mean reversion
    d = re_ - r["ret_beta"] * rb
    vr = {}
    for q in [2, 4, 8, 16, 32]:
        if len(d) > 5 * q:
            cq = pd.Series(d).rolling(q).sum().dropna()
            vr[q] = float(cq.var() / (q * d.var()))
    r["variance_ratio_hedged"] = vr
    # rolling windows: share of windows where EG cointegration holds (p<0.05), rolling beta range, half-life
    roll = {}
    for w in WIN[tf]:
        if len(j) < w + 20: continue
        A, B = rolling_ols(le, lb, w)
        Bv = B[w - 1:]
        step = max(1, w // 8)
        ps, hls = [], []
        for t in range(w, len(j) + 1, step):
            ps.append(coint(le[t - w:t], lb[t - w:t])[1])
            bb, aa = np.polyfit(lb[t - w:t], le[t - w:t], 1)
            hls.append(half_life(le[t - w:t] - (aa + bb * lb[t - w:t])))
        corr = pd.Series(re_).rolling(w).corr(pd.Series(rb)).dropna()
        hls = np.array(hls); fin = hls[np.isfinite(hls)]
        roll[w] = {"hours": w * BAR_MIN[tf] / 60, "share_coint_p05": float(np.mean(np.array(ps) < 0.05)),
                   "share_coint_p10": float(np.mean(np.array(ps) < 0.10)), "n_windows": len(ps),
                   "beta_p5_p50_p95": [float(x) for x in np.nanpercentile(Bv, [5, 50, 95])],
                   "corr_min_med": [float(corr.min()), float(corr.median())],
                   "half_life_bars_median": float(np.median(fin)) if len(fin) else None,
                   "share_no_reversion": float(np.mean(~np.isfinite(hls)))}
    r["rolling"] = roll
    res[tf] = r
json.dump(res, open(f"{out}/study.json", "w"), indent=1)
for tf, r in res.items():
    print(f"\n== {tf}: {r['bars']} bars {r['start'][:16]} -> {r['end'][:16]}")
    print(f"  ETH/BTC ratio change over sample: {r['ratio_change_pct']:+.1f}%   ret corr {r['ret_corr']:.3f}  ret-beta {r['ret_beta']:.2f}")
    print(f"  Full-sample EG p (ETH~BTC) {r['eg_p_eth_on_btc']:.3f}  (BTC~ETH) {r['eg_p_btc_on_eth']:.3f}  static beta {r['static_beta']:.2f}  ADF p {r['adf_p_static_spread']:.3f}  half-life {r['half_life_static_bars']:.1f} bars")
    print("  variance ratio (hedged spread):", {k: round(v, 2) for k, v in r['variance_ratio_hedged'].items()})
    for w, x in r["rolling"].items():
        print(f"  win {w:4d} ({x['hours']:.0f}h): coint p<.05 in {x['share_coint_p05']:.0%} (p<.10 {x['share_coint_p10']:.0%}) of {x['n_windows']} windows; "
              f"beta 5/50/95% {[round(v,2) for v in x['beta_p5_p50_p95']]}; corr min/med {[round(v,2) for v in x['corr_min_med']]}; "
              f"half-life med {x['half_life_bars_median']} bars; no-reversion {x['share_no_reversion']:.0%}")
