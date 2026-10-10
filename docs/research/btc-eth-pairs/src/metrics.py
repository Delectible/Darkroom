import numpy as np, pandas as pd

def weekly(eq):
    """7-day blocks from segment start."""
    t0 = eq.index[0]; blk = ((eq.index - t0) / pd.Timedelta(days=7)).astype(int)
    g = eq.groupby(blk); ends = g.last(); starts = g.first()
    prev = ends.shift(1); prev.iloc[0] = eq.iloc[0]
    span = g.apply(lambda s: (s.index[-1] - s.index[0]) / pd.Timedelta(days=1))
    pnl = ends - prev; ret = pnl / prev
    return pnl, ret          # every block kept (the last one may be partial) so weekly P&L sums to net P&L

def metrics(res, capital=5000.0, target=150.0):
    eq, td = res.eq, res.trades
    days = (eq.index[-1] - eq.index[0]) / pd.Timedelta(days=1)
    end = float(eq.iloc[-1]); ret = end / capital - 1
    daily = eq.resample("1D").last().ffill(); dr = daily.pct_change().dropna()
    sd = dr.std(); dsd = dr[dr < 0].std() if (dr < 0).sum() > 1 else np.nan
    dd = eq / eq.cummax() - 1
    wp, wr = weekly(eq)
    n = len(td)
    m = dict(start=capital, end=end, days=round(days, 1), ret_pct=ret * 100,
             ann_ret_pct=((end / capital) ** (365 / days) - 1) * 100 if days >= 90 and end > 0 else np.nan,
             gross=float(td.gross.sum()) if n else 0.0, net=end - capital,
             costs=float(td.costs.sum()) if n else 0.0, funding=float(td.funding.sum()) if n else 0.0,
             max_dd_pct=float(dd.min()) * 100, vol_ann_pct=sd * np.sqrt(365) * 100 if sd == sd else np.nan,
             sharpe=dr.mean() / sd * np.sqrt(365) if sd and sd > 0 else np.nan,
             sortino=dr.mean() / dsd * np.sqrt(365) if dsd and dsd > 0 else np.nan,
             trades=n, win_rate=float((td.net > 0).mean() * 100) if n else np.nan,
             avg_win=float(td.net[td.net > 0].mean()) if n and (td.net > 0).any() else np.nan,
             avg_loss=float(td.net[td.net <= 0].mean()) if n and (td.net <= 0).any() else np.nan,
             profit_factor=float(td.net[td.net > 0].sum() / -td.net[td.net <= 0].sum()) if n and (td.net <= 0).any() and td.net[td.net <= 0].sum() < 0 else np.nan,
             weeks=len(wp), wk_mean=float(wp.mean()), wk_median=float(wp.median()), wk_std=float(wp.std()),
             wk_mean_pct=float(wr.mean() * 100), wk_median_pct=float(wr.median() * 100),
             wk_pos_pct=float((wp > 0).mean() * 100), wk_best=float(wp.max()), wk_worst=float(wp.min()),
             wk_ge_target=int((wp >= target).sum()), wk_pos_below=int(((wp > 0) & (wp < target)).sum()),
             wk_loss=int((wp < 0).sum()), wk_flat=int((wp == 0).sum()),
             time_in_mkt_pct=float((res.expo > 0).mean() * 100),
             avg_gross_lev=float(res.expo[res.expo > 0].mean()) if (res.expo > 0).any() else 0.0)
    if n:
        dur = (td.exit_time - td.entry_time) / pd.Timedelta(hours=1)
        m.update(avg_hold_h=float(dur.mean()), max_hold_h=float(dur.max()))
        s = (td.net <= 0).astype(int).values; best = cur = 0
        for v in s: cur = cur + 1 if v else 0; best = max(best, cur)
        m["max_loss_streak"] = best
        m["exit_reasons"] = td.reason.value_counts().to_dict()
    else:
        m.update(avg_hold_h=np.nan, max_hold_h=np.nan, max_loss_streak=0, exit_reasons={})
    return m
