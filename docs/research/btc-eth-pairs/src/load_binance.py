"""Load uploaded Binance 1h kline CSVs, align BTC/ETH, report gaps. Usage: load_binance.py UPLOAD_DIR OUT_CSV GEMINI_DIR"""
import sys, glob, re, numpy as np, pandas as pd
up, out, gem = sys.argv[1], sys.argv[2], sys.argv[3]
legs = {}
for sym in ("BTCUSDT", "ETHUSDT"):
    parts = []
    for f in sorted(glob.glob(f"{up}/*-{sym}-1h-*.csv")):
        d = pd.read_csv(f)
        unit = "us" if d.open_time.iloc[0] > 1e14 else "ms"
        d.index = pd.to_datetime(d.open_time, unit=unit, utc=True)
        parts.append(d[["open", "high", "low", "close", "volume"]])
    df = pd.concat(parts); dup = df.index.duplicated().sum()
    df = df[~df.index.duplicated()].sort_index(); legs[sym] = df
    print(f"{sym}: {len(df)} unique bars ({dup} duplicate rows dropped), {df.index[0]} -> {df.index[-1]}")
start, end = pd.Timestamp("2025-10-11", tz="UTC"), pd.Timestamp("2026-10-09 23:00", tz="UTC")
full = pd.date_range(start, end, freq="1h")
print(f"\nRequested window 2025-10-11 00:00 -> 2026-10-09 23:00 UTC: {len(full)} hourly bars expected")
for sym, df in legs.items():
    have = full.isin(df.index); miss = full[~have]
    runs = []
    if len(miss):
        s = miss[0]; p = miss[0]
        for t in miss[1:]:
            if t - p != pd.Timedelta(hours=1): runs.append((s, p)); s = t
            p = t
        runs.append((s, p))
    print(f"{sym}: present {have.sum()}, missing {len(miss)} bars in {len(runs)} gaps")
    for a, b in runs: print(f"   missing {a:%Y-%m-%d %H:%M} -> {b:%Y-%m-%d %H:%M}  ({int((b - a) / pd.Timedelta(hours=1)) + 1} bars)")
j = legs["BTCUSDT"].join(legs["ETHUSDT"], how="inner", lsuffix="_b", rsuffix="_e")
j = j[(j.index >= start) & (j.index <= end)]
print(f"\nAligned (both legs present): {len(j)} bars of {len(full)} ({len(j)/len(full):.0%})")
seg = (j.index.to_series().diff() != pd.Timedelta(hours=1)).cumsum()
for k, g in j.groupby(seg): print(f"   segment {k}: {g.index[0]:%Y-%m-%d %H:%M} -> {g.index[-1]:%Y-%m-%d %H:%M}  {len(g)} bars ({len(g)/24:.1f} days)")
bad = j[(j[["open_b", "close_b", "open_e", "close_e"]] <= 0).any(axis=1)]
print("non-positive prices:", len(bad), "| BTC close range", j.close_b.min(), "-", j.close_b.max(), "| ETH", j.close_e.min(), "-", j.close_e.max())
# cross-check against Gemini spot 1h where they overlap
for sym, g in (("BTCUSD", "close_b"), ("ETHUSD", "close_e")):
    G = pd.read_csv(f"{gem}/gemini_{sym}_1hr.csv"); G.index = pd.to_datetime(G.open_time_ms, unit="ms", utc=True)
    o = j[[g]].join(G.close, how="inner")
    if len(o): print(f"vs Gemini {sym}: {len(o)} overlapping bars, median |diff| {((o[g]/o.close-1).abs().median()*1e4):.1f} bps, max {((o[g]/o.close-1).abs().max()*1e4):.1f} bps")
j.index.name = "time"; j.to_csv(out)
