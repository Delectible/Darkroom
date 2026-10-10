# BTC/ETH pairs-trading study (Oct 2026)

Backtest of a BTC/ETH statistical-arbitrage strategy. Verdict: **NO-GO** (no out-of-sample edge after costs).
Full report: https://claude.ai/artifact/7vAY48RqxtMgTgmEtaBFyR (private).

- `data/` Gemini spot BTC/USD, ETH/USD candles (UTC bar opens). 1d = 12 months; 6h 91 d; 1h 61 d; 30m 30 d; 15m 14 d.
- `fetch/` scripts for 12 months of Binance bulk klines, with a ccxt fallback (Bybit/OKX). All three hosts were blocked in the cloud session.
- `src/` research code (Python 3.13, pandas, numpy, statsmodels):
  - `cd src && python3 study.py ../data ../results` relationship tests (Engle-Granger, ADF, half-life, variance ratios)
  - `python3 research.py ../data ../results` 1% benchmark, design tables, train/val/test selection, walk-forward
  - `python3 stress.py ../data ../results` stress tests and Monte Carlo
  - `python3 selftest.py` engine checks (synthetic pairs, look-ahead truncation test)
- To re-run on Binance data, write the candles as `gemini_<BTCUSD|ETHUSD>_<tf>.csv` with columns
  `open_time_ms,open,high,low,close,volume`, or change `common.load`.
