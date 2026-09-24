#!/usr/bin/env python3
"""Reference renderer for Ginga Ninkyouden (MAME jaleco/ginganin.cpp).

Renders a captured video state (sim/oracle/gn_capture.lua's sNNNNN.bin) with
the ROM regions from ~/gn_images/<set>/ exactly as the driver describes, and
compares it with MAME's pictures. The rules (docs/PLAN.md 1.4):

  full frame 256 x 256, visible lines 16-239 (MAME's pixels() is those 224)
  BG     16x16 tiles from gn_11's map, 512 x 32 tiles, SCAN_COLS, opaque,
         colours 768-1023; vregs[3] scroll X, vregs[2] scroll Y
  FG     16x16 tiles from FG VRAM, 256 x 32 tiles, SCAN_COLS, pen 15 clear,
         colours 512-767; vregs[1] scroll X, vregs[0] scroll Y
  sprites 256 entries in index order (later over earlier), 16x16, pen 15
         clear, colours 256-511, code % 0xA00
  text   8x8 tiles, 32 x 32, SCAN_ROWS, no scroll, pen 15 clear, colours 0-255
  vregs[4] enables: bit 0 BG (off: fill with pen 0), 1 FG, 3 sprites, 2 text
  vregs[6] bit 0 clear = flipped: the whole 256 x 256 frame turned 180 degrees
  palette RGBx_444: R [15:12], G [11:8], B [7:4], 4 bits each, x 0x11; an
         entry never written shows MAME's default (i&1 R, i&2 G, i&4 B) (GN-1)

    tools/gn_model.py SET TRACE_DIR F [F ...]      compare state F with pictures F-1, F, F+1
    tools/gn_model.py SET TRACE_DIR --sweep STEP --offset 1
                                                   every STEP-th frame: state F against picture
                                                   F+1, coloured with state F+1's palette
"""
import argparse, os, sys
import numpy as np

W, H = 256, 256
VIS0, VIS1 = 16, 240

def img(setname, region):
    return np.frombuffer(open(os.path.expanduser(f'~/gn_images/{setname}/{region}.bin'), 'rb').read(), np.uint8)

class Roms:
    def __init__(self, setname):
        self.bgt, self.fgt, self.spr = (self.tiles16(img(setname, r)) for r in ('bgt', 'fgt', 'spr'))
        self.txt = self.tiles8(img(setname, 'text'))
        m = img(setname, 'bgmap')
        self.bgmap = (m[0::2].astype(np.uint16) << 8) | m[1::2]

    @staticmethod
    def nibbles(b):
        out = np.empty(b.shape[:-1] + (b.shape[-1] * 2,), np.uint8)
        out[..., 0::2] = b >> 4
        out[..., 1::2] = b & 15
        return out

    @classmethod
    def tiles16(cls, rom):
        # gfx_8x8x4_col_2x2_group_packed_msb: row r = bytes 4r..4r+3 (left 8 px)
        # then 64+4r..64+4r+3 (right 8 px); high nibble first
        t = rom.reshape(-1, 2, 16, 4)                  # tile, half, row, byte
        px = cls.nibbles(t)                            # tile, half, row, 8
        return np.concatenate([px[:, 0], px[:, 1]], axis=2)   # tile, row, 16

    @classmethod
    def tiles8(cls, rom):
        return cls.nibbles(rom.reshape(-1, 8, 4))      # tile, row, 8

class State:
    def __init__(self, path):
        b = np.frombuffer(open(path, 'rb').read(), '>u2')
        self.txt = b[0x000:0x400]
        self.spr = b[0x400:0x800]
        self.pal = b[0x800:0xC00]
        self.vregs = b[0xC00:0xC08]
        self.fg = b[0xC10:0xC10 + 0x2000]
        raw = open(path, 'rb').read()[0x5820:0x58A0]
        # GN-1: MAME shows its default palette for an entry never written
        self.written = np.unpackbits(np.frombuffer(raw, np.uint8), bitorder='little').astype(bool) \
            if len(raw) == 128 else np.ones(1024, bool)

def palette_rgb(pal, written):
    r = (pal >> 12) & 15; g = (pal >> 8) & 15; bl = (pal >> 4) & 15
    rgb = ((r * 0x11).astype(np.uint32) << 16) | ((g * 0x11).astype(np.uint32) << 8) | (bl * 0x11)
    i = np.arange(1024)
    dflt = ((i & 1) * 0xFF0000) | ((i >> 1 & 1) * 0x00FF00) | ((i >> 2 & 1) * 0x0000FF)
    return np.where(written, rgb, dflt).astype(np.uint32)

def tilemap(tiles, codes, ncols, nrows, scan_cols, tsize, scrollx, scrolly):
    """The whole map as pens (tsize px tiles), then the screen window."""
    ntiles = tiles.shape[0]
    idx = np.arange(ncols * nrows)
    col, row = (idx // nrows, idx % nrows) if scan_cols else (idx % ncols, idx // ncols)
    code = codes[idx]
    pen = tiles[(code & 0x0FFF) % ntiles]                            # true modulo (NMK-25)
    color = (code >> 12).astype(np.uint16)
    full = np.zeros((nrows * tsize, ncols * tsize), np.uint16)
    fpen = np.zeros_like(full)
    for i in range(len(idx)):
        y0, x0 = row[i] * tsize, col[i] * tsize
        fpen[y0:y0 + tsize, x0:x0 + tsize] = pen[i]
        full[y0:y0 + tsize, x0:x0 + tsize] = color[i]
    ys = (np.arange(H) + scrolly) % full.shape[0]
    xs = (np.arange(W) + scrollx) % full.shape[1]
    return fpen[np.ix_(ys, xs)], full[np.ix_(ys, xs)]

class Model:
    def __init__(self, setname):
        self.r = Roms(setname)
        self._bg = None

    def render(self, st, pal=None):
        """pal: the State whose palette colours the frame (MAME's picture F+1 is
        state F's composition with state F+1's palette: MS1Z-5, GN-2)."""
        pal = pal or st
        r, v = self.r, st.vregs
        ctrl, flip = int(v[4]), not (int(v[6]) & 1)
        out = np.zeros((H, W), np.uint16)                            # palette indices
        if ctrl & 1:
            pen, col = tilemap(r.bgt, r.bgmap, 512, 32, True, 16, int(v[3]), int(v[2]))
            out[:] = 768 + col * 16 + pen
        if ctrl & 2:
            pen, col = tilemap(r.fgt, st.fg, 256, 32, True, 16, int(v[1]), int(v[0]))
            m = pen != 15
            out[m] = (512 + col * 16 + pen)[m]
        if ctrl & 8:
            for i in range(256):
                y, x, code, attr = (int(w) for w in st.spr[i * 4:i * 4 + 4])
                x = (x & 0xFF) - (x & 0x100); y = (y & 0xFF) - (y & 0x100)
                fx, fy = bool(code & 0x4000), bool(code & 0x8000)
                t = r.spr[(code & 0x3FFF) % r.spr.shape[0]]
                if fx: t = t[:, ::-1]
                if fy: t = t[::-1, :]
                c = 256 + (attr >> 12) * 16
                for yy in range(16):
                    sy = y + yy
                    if not 0 <= sy < H: continue
                    for xx in range(16):
                        sx = x + xx
                        if 0 <= sx < W and t[yy, xx] != 15:
                            out[sy, sx] = c + int(t[yy, xx])
        if ctrl & 4:
            pen, col = tilemap(r.txt, st.txt, 32, 32, False, 8, 0, 0)
            m = pen != 15
            out[m] = (col * 16 + pen)[m]
        if flip:
            out = out[::-1, ::-1]
        return palette_rgb(pal.pal, pal.written)[out][VIS0:VIS1]

def picture(trace, F):
    p = os.path.join(trace, f'p{F:05d}.raw')
    if not os.path.exists(p): return None
    return np.frombuffer(open(p, 'rb').read(), '<u4').reshape(VIS1 - VIS0, W) & 0xFFFFFF

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('set'); ap.add_argument('trace'); ap.add_argument('frames', nargs='*', type=int)
    ap.add_argument('--sweep', type=int); ap.add_argument('--offset', type=int, default=None)
    ap.add_argument('--from', dest='frm', type=int, default=0)
    a = ap.parse_args()
    m = Model(a.set)
    if a.sweep:
        n = int(sorted(f for f in os.listdir(a.trace) if f.startswith('s'))[-1][1:6])
        exact = tot = nonblank = 0
        bad = []
        for F in range(a.frm, n, a.sweep):
            pic = picture(a.trace, F + a.offset)
            if pic is None: continue
            nxt = os.path.join(a.trace, f's{F + a.offset:05d}.bin')
            out = m.render(State(os.path.join(a.trace, f's{F:05d}.bin')),
                           State(nxt) if os.path.exists(nxt) else None)
            d = int((out != pic).sum()); tot += 1; exact += d == 0
            nonblank += int((pic != 0).sum()) > 0
            if d: bad.append((F, d))
        print(f'{a.trace}: offset {a.offset:+d}: {exact} / {tot} exact ({nonblank} non-blank); first bad {bad[:8]}')
        return
    for F in a.frames:
        out = m.render(State(os.path.join(a.trace, f's{F:05d}.bin')))
        res = []
        for k in (-1, 0, 1):
            pic = picture(a.trace, F + k)
            if pic is not None: res.append(f'pic {F + k}: {int((out != pic).sum())}')
        print(f'state {F}: ' + ', '.join(res) + f'  (non-black {int((out != 0).sum())})')

if __name__ == '__main__':
    main()
