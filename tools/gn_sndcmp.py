#!/usr/bin/env python3
"""Compare a sound-board bus trace with MAME's (docs/PLAN.md M0).

    tools/gn_sndcmp.py MAME_TRACE RTL_TRACE [--until-ms MS]

Both traces are sim/oracle/gn_sndtrace.lua's format, "t_ns dev R|W offset
data". Per device (ptm, opl, psg) the WRITE sequences are compared in order,
(offset, data) pairs; the first divergence is shown with its context. For the
matched prefix the time differences RTL - MAME are summarised (us), which
measures the 6809's and the PTM's timing against MAME's.
"""
import argparse, statistics

def load(path, until_ns):
    ev = {}
    for line in open(path):
        f = line.split()
        if len(f) != 5 or f[2] != 'W' or f[1] not in ('ptm', 'opl', 'psg'): continue
        t = float(f[0])
        if t > until_ns: continue
        ev.setdefault(f[1], []).append((t, int(f[3], 16), int(f[4], 16)))
    return ev

ap = argparse.ArgumentParser()
ap.add_argument('mame'); ap.add_argument('rtl'); ap.add_argument('--until-ms', type=float, default=1e12)
a = ap.parse_args()
m, r = load(a.mame, a.until_ms * 1e6), load(a.rtl, a.until_ms * 1e6)
for dev in ('ptm', 'opl', 'psg'):
    me, re_ = m.get(dev, []), r.get(dev, [])
    n = min(len(me), len(re_))
    k = next((i for i in range(n) if me[i][1:] != re_[i][1:]), n)
    dt = [(re_[i][0] - me[i][0]) / 1000 for i in range(k)]
    s = (f'dt us: first {dt[0]:+.2f}, mean {statistics.mean(dt):+.2f}, min {min(dt):+.2f}, max {max(dt):+.2f}' if dt else '')
    print(f'{dev}: MAME {len(me)} writes, RTL {len(re_)}; identical for the first {k}. {s}')
    if k < n:
        print(f'   first difference at #{k}: MAME t={me[k][0]/1e6:.3f} ms {me[k][1]:X}={me[k][2]:02X}, RTL t={re_[k][0]/1e6:.3f} ms {re_[k][1]:X}={re_[k][2]:02X}')
        print('   MAME:', ' '.join(f'{x[1]:X}={x[2]:02X}' for x in me[max(0, k - 4):k + 6]))
        print('   RTL: ', ' '.join(f'{x[1]:X}={x[2]:02X}' for x in re_[max(0, k - 4):k + 6]))
