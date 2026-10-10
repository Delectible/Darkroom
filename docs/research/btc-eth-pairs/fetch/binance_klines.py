#!/usr/bin/env python3
"""Download 12 months of 15m spot klines from data.binance.vision (monthly zips).

Usage: python3 -I binance_klines.py RAW_DIR OUT_DIR [--months 12]

Fetches the last N complete calendar months for each symbol, verifies each
zip against its .CHECKSUM file, and writes one merged CSV per symbol.
Exits non-zero if any month fails, so a caller can fall back to ccxt.
"""
import argparse
import csv
import datetime as dt
import hashlib
import io
import sys
import time
import zipfile
from pathlib import Path

import requests

BASE = "https://data.binance.vision/data/spot/monthly/klines"
SYMBOLS = ["BTCUSDT", "ETHUSDT"]
INTERVAL = "15m"
HEADER = ["open_time", "open", "high", "low", "close", "volume", "close_time",
          "quote_volume", "trades", "taker_buy_base", "taker_buy_quote", "ignore"]


def last_months(n, today=None):
    today = today or dt.date.today()
    y, m = today.year, today.month
    out = []
    for _ in range(n):
        m -= 1
        if m == 0:
            y, m = y - 1, 12
        out.append(f"{y:04d}-{m:02d}")
    return sorted(out)


def get(session, url, tries=4):
    for i in range(tries):
        try:
            r = session.get(url, timeout=60)
            r.raise_for_status()
            return r.content
        except requests.RequestException as e:
            if i == tries - 1 or getattr(e.response, "status_code", None) == 404:
                raise
            time.sleep(2 ** (i + 1))


def to_ms(ts):
    # Spot files from 2025 on use microseconds; normalise to milliseconds.
    ts = int(ts)
    return ts // 1000 if ts > 10**14 else ts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw_dir", type=Path)
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--months", type=int, default=12)
    args = ap.parse_args()
    args.raw_dir.mkdir(parents=True, exist_ok=True)
    args.out_dir.mkdir(parents=True, exist_ok=True)

    months = last_months(args.months)
    print(f"Months: {months[0]} .. {months[-1]}")
    s = requests.Session()
    failed = []

    for sym in SYMBOLS:
        rows = []
        for ym in months:
            name = f"{sym}-{INTERVAL}-{ym}.zip"
            url = f"{BASE}/{sym}/{INTERVAL}/{name}"
            zpath = args.raw_dir / name
            try:
                if not zpath.exists():
                    zpath.write_bytes(get(s, url))
                want = get(s, url + ".CHECKSUM").decode().split()[0]
                have = hashlib.sha256(zpath.read_bytes()).hexdigest()
                if want != have:
                    zpath.unlink()
                    raise ValueError(f"checksum mismatch ({have} != {want})")
                with zipfile.ZipFile(zpath) as zf:
                    member = zf.namelist()[0]
                    text = io.TextIOWrapper(zf.open(member), encoding="utf-8")
                    n = 0
                    for rec in csv.reader(text):
                        if not rec or not rec[0].isdigit():
                            continue  # header line, if any
                        rec[0], rec[6] = to_ms(rec[0]), to_ms(rec[6])
                        rows.append(rec)
                        n += 1
                print(f"  {name}: {n} rows")
            except Exception as e:
                print(f"  {name}: FAILED: {e}", file=sys.stderr)
                failed.append(name)

        rows.sort(key=lambda r: r[0])
        dedup = {r[0]: r for r in rows}
        out = args.out_dir / f"{sym}_{INTERVAL}_{months[0]}_{months[-1]}.csv"
        with out.open("w", newline="") as f:
            w = csv.writer(f)
            w.writerow(HEADER)
            w.writerows(dedup.values())
        print(f"{sym}: {len(dedup)} candles -> {out}")

    if failed:
        print(f"{len(failed)} file(s) failed: {failed}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
