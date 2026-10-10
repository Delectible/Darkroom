#!/usr/bin/env python3
"""Fallback: pull 12 months of 15m BTC/USDT and ETH/USDT candles via ccxt.

Usage: python3 -I ccxt_klines.py OUT_DIR [--exchanges bybit okx] [--months 12]

Tries each exchange in order and uses the first that works. Covers the same
window as binance_klines.py: the last N complete calendar months.
Output CSV: open_time (ms, UTC), open, high, low, close, volume.
"""
import argparse
import csv
import datetime as dt
import sys
import time
from pathlib import Path

import ccxt

SYMBOLS = {"BTCUSDT": "BTC/USDT", "ETHUSDT": "ETH/USDT"}
TF, TF_MS = "15m", 15 * 60 * 1000


def window(months):
    first_of_this = dt.date.today().replace(day=1)
    y, m = first_of_this.year, first_of_this.month - months
    while m <= 0:
        y, m = y - 1, m + 12
    to_ms = lambda d: int(dt.datetime(d.year, d.month, 1, tzinfo=dt.timezone.utc).timestamp() * 1000)
    return to_ms(dt.date(y, m, 1)), to_ms(first_of_this)


def fetch_all(ex, symbol, since, until):
    rows, cursor = {}, since
    limit = 1000 if ex.id == "bybit" else 100  # OKX history caps at 100
    while cursor < until:
        for i in range(5):
            try:
                batch = ex.fetch_ohlcv(symbol, TF, since=cursor, limit=limit)
                break
            except (ccxt.NetworkError, ccxt.ExchangeNotAvailable) as e:
                if i == 4:
                    raise
                time.sleep(2 ** (i + 1))
        batch = [b for b in batch if since <= b[0] < until]
        if not batch:
            cursor += limit * TF_MS  # gap (or no data yet): skip ahead
            continue
        for b in batch:
            rows[b[0]] = b
        cursor = batch[-1][0] + TF_MS
    return [rows[k] for k in sorted(rows)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--exchanges", nargs="+", default=["bybit", "okx"])
    ap.add_argument("--months", type=int, default=12)
    args = ap.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    since, until = window(args.months)
    label = lambda ms: dt.datetime.fromtimestamp(ms / 1000, dt.timezone.utc).strftime("%Y-%m-%d")
    print(f"Window: {label(since)} .. {label(until)} (exclusive)")

    for ex_id in args.exchanges:
        ex = getattr(ccxt, ex_id)({"enableRateLimit": True})
        try:
            ex.load_markets()
            for name, symbol in SYMBOLS.items():
                rows = fetch_all(ex, symbol, since, until)
                out = args.out_dir / f"{name}_{TF}_{ex_id}_{label(since)}_{label(until)}.csv"
                with out.open("w", newline="") as f:
                    w = csv.writer(f)
                    w.writerow(["open_time", "open", "high", "low", "close", "volume"])
                    w.writerows(rows)
                expected = (until - since) // TF_MS
                print(f"{ex_id} {symbol}: {len(rows)}/{expected} candles -> {out}")
            return
        except Exception as e:
            print(f"{ex_id}: FAILED: {type(e).__name__}: {str(e)[:200]}", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
