import numpy as np, pandas as pd
from pathlib import Path

BAR_MIN = {"15m": 15, "30m": 30, "1hr": 60, "6hr": 360, "1day": 1440}

def load(data_dir, tf):
    d = Path(data_dir)
    b = pd.read_csv(d / f"gemini_BTCUSD_{tf}.csv"); e = pd.read_csv(d / f"gemini_ETHUSD_{tf}.csv")
    j = b.merge(e, on="open_time_ms", suffixes=("_b", "_e"))
    j.index = pd.to_datetime(j.open_time_ms, unit="ms", utc=True)
    return j

def rolling_ols(y, x, w):
    """OLS y = a + b x over trailing window w (inclusive of t). Returns a, b arrays (nan before w)."""
    y = pd.Series(y); x = pd.Series(x)
    mx = x.rolling(w).mean(); my = y.rolling(w).mean()
    cov = (x * y).rolling(w).mean() - mx * my
    var = (x * x).rolling(w).mean() - mx * mx
    b = cov / var
    a = my - b * mx
    return a.values, b.values

def half_life(s):
    s = pd.Series(s).dropna()
    ds = s.diff().dropna(); lag = s.shift(1).dropna().loc[ds.index]
    lam = np.polyfit(lag.values, ds.values, 1)[0]
    return np.inf if lam >= 0 else -np.log(2) / np.log(1 + lam)
