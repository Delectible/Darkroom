"""Pairs backtest engine: causal signals, next-bar execution, costs, funding, risk limits."""
import numpy as np, pandas as pd, warnings
from dataclasses import dataclass, field, replace
from statsmodels.tsa.stattools import coint
from common import load, rolling_ols, BAR_MIN
warnings.filterwarnings("ignore")

LOOKBACK_DAYS = {"15m": [1, 2, 4], "30m": [2, 4, 7], "1hr": [3, 7, 14], "6hr": [7, 14, 28], "1day": [30, 60, 90]}
def bars(tf, days): return int(round(days * 1440 / BAR_MIN[tf]))

# cost per leg per fill (fee + half spread + slippage), funding per 8h on gross notional
COSTS = {"optimistic": dict(fill_bps=2.0, fund_bps_8h=0.0),
         "base":       dict(fill_bps=7.0, fund_bps_8h=0.5),
         "pessimistic": dict(fill_bps=12.0, fund_bps_8h=1.5)}

@dataclass(frozen=True)
class Cfg:
    L_days: float = 7
    hedge: str = "roll"          # roll | static | retbeta | ratio (beta = 1)
    rule: str = "z"              # z | pct
    entry: float = 2.0           # z units, or pct (1.0 = 1%)
    exit: float = 0.5            # z units; for pct: fraction of entry divergence left (0.25 = 75% converged)
    stop: float = 1.5            # z: stop at entry+stop; pct: stop at entry*(1+stop); None = no stop
    max_hold_frac: float = 0.5   # max hold = frac * lookback bars; None = no limit
    sizing: str = "beta"         # beta | dollar | vol | fixed5050
    coint_filter: bool = False   # block entries if rolling EG p > 0.20, exit if > 0.50
    corr_filter: bool = False    # block entries if rolling return corr < 0.60
    vol_emergency: bool = True   # exit/block if short spread vol > 2.5x long
    risk: float = 0.01           # equity fraction lost at stop
    max_gross: float = 2.0       # max gross notional / equity
    fixed_gross: float = 1.0     # for fixed5050 sizing
    daily_loss: float = 0.02
    weekly_loss: float = 0.04
    max_dd: float = 0.15
    risk_limits: bool = True
    loss_stop: float = None      # exit if open trade loses this fraction of equity at entry

class Signals:
    """All causal series for one timeframe and lookback. Values at index t use data <= close t."""
    def __init__(self, df, tf, L, hedge, static_fit_end=None):
        self.df, self.tf, self.L = df, tf, L
        le, lb = np.log(df.close_e.values), np.log(df.close_b.values)
        n = len(df); re_ = np.r_[0, np.diff(le)]; rb = np.r_[0, np.diff(lb)]
        if hedge == "roll":
            a, b = rolling_ols(le, lb, L)
            e = le - a - b * lb
            sy = pd.Series(le); sx = pd.Series(lb)
            vy = sy.rolling(L).var(ddof=0); vx = sx.rolling(L).var(ddof=0)
            cxy = (sx * sy).rolling(L).mean() - sx.rolling(L).mean() * sy.rolling(L).mean()
            sig = np.sqrt(np.maximum((vy - cxy ** 2 / vx).values, 1e-12))
            dev, h = e, b
        else:
            if hedge == "static":
                k = static_fit_end
                b0, a0 = np.polyfit(lb[:k], le[:k], 1)
                s = le - b0 * lb; h = np.full(n, b0)
            elif hedge == "ratio":
                s = le - lb; h = np.ones(n)
            elif hedge == "retbeta":
                cov = pd.Series(re_ * rb).rolling(L).mean() - pd.Series(re_).rolling(L).mean() * pd.Series(rb).rolling(L).mean()
                var = pd.Series(rb).rolling(L).var(ddof=0)
                h = (cov / var).values
                hl = np.r_[np.nan, h[:-1]]                     # beta known before bar k
                inc = np.nan_to_num(re_ - hl * rb)
                s = np.cumsum(inc)
            ss = pd.Series(s)
            dev = (ss - ss.rolling(L).mean()).values
            sig = ss.rolling(L).std(ddof=0).values
        self.dev, self.sig, self.h = dev, sig, h
        self.z = dev / sig
        # return-vol ratio for vol sizing, rolling return corr
        self.volratio = (pd.Series(re_).rolling(L).std() / pd.Series(rb).rolling(L).std()).values
        self.corr = pd.Series(re_).rolling(max(L // 2, 10)).corr(pd.Series(rb)).values
        # vol emergency: short-window std of spread increments vs long window
        ds = pd.Series(np.r_[0, np.diff(np.nan_to_num(le - np.nan_to_num(h, nan=1.0) * lb))])
        ds = pd.Series(re_ - np.nan_to_num(h, nan=1.0) * rb)
        self.volspike = (ds.rolling(max(L // 6, 4)).std() / ds.rolling(L).std()).values
        self._coint = None; self._le, self._lb = le, lb

    def coint_p(self):
        if self._coint is None:
            n, L = len(self.df), self.L; step = max(1, L // 12)
            p = np.full(n, np.nan)
            for t in range(L, n + 1, step):
                p[t - 1] = coint(self._le[t - L:t], self._lb[t - L:t])[1]
            self._coint = pd.Series(p).ffill().values
        return self._coint

@dataclass
class Result:
    eq: pd.Series; expo: pd.Series; trades: pd.DataFrame; costs: float; funding: float

def simulate(sig: Signals, cfg: Cfg, start, end, cost="base", fill_bps=None, fund_bps_8h=None,
             delay="open", leg_delay=False, capital=5000.0):
    """Trade bars [start, end). Signal at close t, fill at open t+1 (delay='close': close t+1).
    Positions are flattened at the last bar so every trade is closed inside the segment."""
    df = sig.df
    c = COSTS[cost]; fb = (c["fill_bps"] if fill_bps is None else fill_bps) / 1e4
    fu = (c["fund_bps_8h"] if fund_bps_8h is None else fund_bps_8h) / 1e4 * BAR_MIN[sig.tf] / 480
    oe, ob, ce, cb = df.open_e.values, df.open_b.values, df.close_e.values, df.close_b.values
    t_idx = df.index
    z = sig.z if cfg.rule == "z" else sig.dev * 100
    sigma = sig.sig if cfg.rule == "z" else np.full(len(df), 0.01)
    entry = cfg.entry
    stop = None if cfg.stop is None else (entry + cfg.stop if cfg.rule == "z" else entry * (1 + cfg.stop))
    exit_lvl = cfg.exit if cfg.rule == "z" else entry * cfg.exit
    maxhold = None if cfg.max_hold_frac is None else max(2, int(cfg.max_hold_frac * sig.L))
    cp = sig.coint_p() if cfg.coint_filter else None
    eq = capital; peak = capital; halted = False
    qe = qb = 0.0; side = 0; held = 0; tr = None
    day_start = week_start = capital; cur_day = cur_week = None; cool = None
    n = end - start
    E = np.full(n, np.nan); X = np.zeros(n)
    trades = []; tot_cost = tot_fund = 0.0
    for i, t in enumerate(range(start, end)):
        if side:
            notional = abs(qe) * ce[t] + abs(qb) * cb[t]
            f = notional * fu; tot_fund += f; tr["funding"] += f
            eq_now = tr["eq0"] + qe * (ce[t] - tr["pe"]) + qb * (cb[t] - tr["pb"]) - tr["cost_entry"] - tr["funding"]
            held += 1; X[i] = notional / max(eq_now, 1e-9)
        else:
            eq_now = eq
        E[i] = eq_now; peak = max(peak, eq_now)
        ts = t_idx[t]; d, w = ts.date(), (ts - t_idx[start]).days // 7
        if d != cur_day: cur_day, day_start = d, eq_now
        if w != cur_week: cur_week, week_start = w, eq_now
        last = (t >= end - 2) or (t + 1 >= len(df))
        if last and not side: break
        nxt = min(t + 1, len(df) - 1)
        if delay == "same":                               # fill at the signal bar's own close
            nxt = t; fe, fbp = ce[t], cb[t]
        else:
            fe = oe[nxt] if delay == "open" else ce[nxt]
            fbp = ob[nxt] if delay == "open" else cb[nxt]
        if leg_delay: fbp = cb[nxt]
        zt = z[t]; reason = None
        if cfg.risk_limits:
            if eq_now <= peak * (1 - cfg.max_dd): halted = True; reason = "max_drawdown_halt"
            elif eq_now <= day_start * (1 - cfg.daily_loss): cool = ("d", d); reason = "daily_loss_limit"
            elif eq_now <= week_start * (1 - cfg.weekly_loss): cool = ("w", w); reason = "weekly_loss_limit"
        blocked = halted or (cool is not None and ((cool[0] == "d" and cool[1] == d) or (cool[0] == "w" and cool[1] == w)))
        emerg = cfg.vol_emergency and np.isfinite(sig.volspike[t]) and sig.volspike[t] > 2.5
        if side:
            if reason is None:
                if last: reason = "end_of_test"
                elif (side == -1 and zt <= exit_lvl) or (side == 1 and zt >= -exit_lvl): reason = "converged"
                elif stop is not None and ((side == -1 and zt >= stop) or (side == 1 and zt <= -stop)): reason = "stop"
                elif cfg.loss_stop is not None and eq_now - tr["eq0"] <= -cfg.loss_stop * tr["eq0"]: reason = "loss_stop"
                elif maxhold is not None and held >= maxhold: reason = "max_hold"
                elif emerg: reason = "vol_emergency"
                elif cp is not None and cp[t] > 0.5: reason = "relationship_break"
                elif not np.isfinite(zt): reason = "no_signal"
            if reason:
                cost_exit = fb * (abs(qe) * fe + abs(qb) * fbp)
                gross = qe * (fe - tr["re"]) + qb * (fbp - tr["rb"])
                net = gross - tr["cost_entry"] - cost_exit - tr["funding"]
                tot_cost += cost_exit; eq = tr["eq0"] + net
                tr.update(exit_time=t_idx[nxt], bars=held, reason=reason, gross=gross,
                          costs=tr["cost_entry"] + cost_exit, net=net)
                trades.append(tr); qe = qb = 0.0; side = 0; tr = None; held = 0
                E[i] = eq if last else E[i]
            if last: break
            continue
        if last or blocked or emerg or not np.isfinite(zt) or not np.isfinite(sigma[t]): continue
        if abs(zt) < entry or (stop is not None and abs(zt) >= stop): continue
        if cfg.coint_filter and not (cp[t] <= 0.20): continue
        if cfg.corr_filter and not (sig.corr[t] >= 0.60): continue
        h = sig.h[t] if np.isfinite(sig.h[t]) else 1.0
        h = float(np.clip(h, 0.2, 3.0))
        if cfg.sizing == "fixed5050":
            ne = nb = cfg.fixed_gross * eq / 2
        else:
            if stop is not None:
                stopdist = (stop - abs(zt)) * sigma[t] if cfg.rule == "z" else (stop - abs(zt)) / 100
            else:
                stopdist = 3 * sigma[t]
            ne = cfg.risk * eq / (max(stopdist, 1e-4) + 2 * (1 + h) * fb)
            gross_n = min(ne * (1 + h), cfg.max_gross * eq)
            if cfg.sizing == "beta": ne, nb = gross_n / (1 + h), gross_n * h / (1 + h)
            elif cfg.sizing == "dollar": ne = nb = gross_n / 2
            elif cfg.sizing == "vol":
                vr = sig.volratio[t] if np.isfinite(sig.volratio[t]) else 1.0
                ne, nb = gross_n / (1 + vr), gross_n * vr / (1 + vr)
        side = -1 if zt > 0 else 1                       # +1 = long ETH / short BTC
        qe = side * ne / fe; qb = -side * nb / fbp
        cost_entry = fb * (ne + nb); tot_cost += cost_entry
        tr = dict(entry_time=t_idx[nxt], side="long ETH/short BTC" if side == 1 else "short ETH/long BTC",
                  z_entry=float(zt), eq0=eq, re=fe, rb=fbp, pe=fe, pb=fbp, cost_entry=cost_entry,
                  funding=0.0, gross_notional=ne + nb, hedge=h)
    idx = t_idx[start:end]
    E = pd.Series(E, index=idx).ffill().fillna(capital); X = pd.Series(X, index=idx)
    return Result(E, X, pd.DataFrame(trades), tot_cost, tot_fund)
