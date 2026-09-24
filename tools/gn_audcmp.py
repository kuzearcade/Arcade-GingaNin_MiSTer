#!/usr/bin/env python3
"""Compare two int16 sample streams at the same rate (docs/PLAN.md M0, GN-5).

    tools/gn_audcmp.py REF TEST [--max-offset N]

Finds the offset (TEST sample k+o against REF sample k, |o| <= N) with the
most exactly equal samples, then reports, over the overlap: exact matches,
max |difference|, correlation, and the level ratio in dB.
"""
import argparse, numpy as np
ap = argparse.ArgumentParser(); ap.add_argument('ref'); ap.add_argument('test'); ap.add_argument('--max-offset', type=int, default=300)
a = ap.parse_args()
r = np.fromfile(a.ref, '<i2').astype(np.int64); t = np.fromfile(a.test, '<i2').astype(np.int64)
n = min(len(r), len(t)) - 2 * a.max_offset
best = None
seg = slice(a.max_offset, a.max_offset + min(n, 200000))
for o in range(-a.max_offset, a.max_offset + 1):
    eq = int((r[seg] == t[seg.start + o:seg.stop + o]).sum())
    if best is None or eq > best[1]: best = (o, eq)
o = best[0]
R = r[a.max_offset:a.max_offset + n]; T = t[a.max_offset + o:a.max_offset + o + n]
d = T - R
rms = lambda x: np.sqrt((x.astype(float) ** 2).mean())
corr = np.corrcoef(R, T)[0, 1] if R.std() and T.std() else float('nan')
print(f'{a.test}: offset {o:+d} samples; exact {100 * (d == 0).mean():.2f}% of {n}; max |diff| {abs(d).max()}; '
      f'corr {corr:.5f}; level {20 * np.log10(rms(T) / rms(R)) if rms(R) else float("nan"):+.2f} dB; ref rms {rms(R):.0f}')
