#!/usr/bin/env python3
"""Explain M2's non-exact frames as tearing (GN-7).

    tools/gn_torn.py SET TRACE FRAMEDIR WRLOG RUNLOG

Inputs, from one sim/rtl/gn_frames run:
  FRAMEDIR  MP_FRAMEDIR's fNNNNN.raw pictures
  WRLOG     the "  wr fK line L addr data be" lines of MP_WRALL=1 MP_WRLOG=0,N
  RUNLOG    its stdout with MP_SHOWDIFF=1 (names the frames that differ)

The RTL's picture K+1 is drawn during frame period K (from line 240). For
every differing frame it rebuilds that picture line by line: the sprite and
text RAM as the core's own writes left it (replayed from boot), with every
write of period K made before line L-1 began visible on line L (the engines
draw line L during line L-1). Other layers come from MAME's state K. A line
also passes when its pixels are each explained by some cutoff inside line
L-1 (the log has line resolution; the engine reads entry by entry within it).
"""
import argparse, collections, copy, os, re, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gn_model as g

ap = argparse.ArgumentParser()
for k in ('set', 'trace', 'framedir', 'wrlog', 'runlog'): ap.add_argument(k)
a = ap.parse_args()
m = g.Model(a.set)
bad = sorted(set(int(x) for x in re.findall(r'frame (\d+) vs MAME', open(a.runlog).read())))
byf = collections.defaultdict(list)
for l in open(a.wrlog):
    w = l.split()
    if len(w) == 7 and w[0] == 'wr': byf[int(w[1][1:])].append(w)
tk = lambda w: (int(w[3]) - 240) % 250          # time order within a period

def apply(sp, tx, ws):
    for w in ws:
        ad, d, be = int(w[4], 16), int(w[5], 16), int(w[6])
        if 0x40000 <= ad < 0x40800: arr, off = sp, 0x40000
        elif 0x30000 <= ad < 0x30800: arr, off = tx, 0x30000
        else: continue
        i = (ad - off) // 2; v = int(arr[i])
        if be & 2: v = (v & 0x00FF) | (d & 0xFF00)
        if be & 1: v = (v & 0xFF00) | (d & 0x00FF)
        arr[i] = v

spr = np.zeros(1024, np.uint16); txt = np.zeros(1024, np.uint16)
want = set(bad); exact = window = 0; left = []
for K in range(0, (max(bad) if bad else 0)):
    cur = byf.get(K, [])
    if K + 1 in want:
        r = np.frombuffer(open(f'{a.framedir}/f{K + 1:05d}.raw', 'rb').read(), '<u4').reshape(224, 256) & 0xFFFFFF
        base, nxt = g.State(f'{a.trace}/s{K:05d}.bin'), g.State(f'{a.trace}/s{K + 1:05d}.bin')
        cache = {}
        def pic(n):
            if n not in cache:
                s = copy.copy(base); s.spr = spr.copy(); s.txt = txt.copy(); apply(s.spr, s.txt, cur[:n])
                cache[n] = m.render(s, nxt)
            return cache[n]
        d_line = d_win = 0
        for L in range(16, 240):
            n0 = sum(1 for w in cur if tk(w) < (L - 1 - 240) % 250)
            n1 = sum(1 for w in cur if tk(w) < (L - 240) % 250)
            e0 = int((pic(n0)[L - 16] != r[L - 16]).sum())
            d_line += e0
            if e0:
                rows = [pic(n)[L - 16] for n in range(n0, n1 + 1)]
                if not all(any(rw[x] == r[L - 16][x] for rw in rows) for x in range(256)):
                    d_win += min(int((rw != r[L - 16]).sum()) for rw in rows)
        if d_line == 0: exact += 1
        elif d_win == 0: window += 1
        else: left.append((K + 1, d_win))
    apply(spr, txt, cur)
print(f'{len(bad)} frames differ from MAME: {exact} are the torn frame exactly, '
      f'{window} within the line L-1 window, {len(left)} not explained: {left}')
