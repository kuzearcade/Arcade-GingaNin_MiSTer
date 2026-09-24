"""The one ROM table of Arcade-GingaNin_MiSTer (docs/PLAN.md Appendix D).

One image, downloaded as ioctl index 0, the same layout for both sets:

    0x000000  main program   128 KB   16-bit interleave, gn_02 = even (high) byte
    0x020000  sound program   64 KB   gn_05 (the core uses 0x4000-0xFFFF)
    0x030000  text tiles      16 KB   gn_10 / 10.bin
    0x034000  BG map          32 KB   gn_11 (big-endian word per tile)
    0x03C000  BG tiles       128 KB   gn_15, gn_14
    0x05C000  FG tiles       128 KB   gn_12, gn_13
    0x07C000  sprites        320 KB   MAME's region order: gn_06 first half, gn_07,
                                      gn_08, gn_09, gn_06 second half (ROM_CONTINUE)
    0x0CC000  ADPCM          128 KB   gn_04, gn_03
    0x0EC000  end

The core keeps 0x000000-0x03BFFF in BRAM and writes the rest to SDRAM at
image offset - 0x03C000 (Appendix B: BG 0, FG 0x20000, sprites 0x40000,
ADPCM 0x90000).

Each region is a list of pieces:
    ('il', width, [(file, lane), ...])   interleave; lane 0 = lowest address byte
    ('file', name)                        the file as it is
    ('part', name, offset, length)        a slice of a file
"""

REGIONS = [
    ('main',  0x000000, 0x20000),
    ('snd',   0x020000, 0x10000),
    ('text',  0x030000, 0x04000),
    ('bgmap', 0x034000, 0x08000),
    ('bgt',   0x03C000, 0x20000),
    ('fgt',   0x05C000, 0x20000),
    ('spr',   0x07C000, 0x50000),
    ('adpcm', 0x0CC000, 0x20000),
]
TOTAL = 0x0EC000
BRAM_END = 0x03C000          # the image below this goes to BRAM, the rest to SDRAM

_COMMON = {
    'snd':   [('file', 'gn_05.bin')],
    'bgmap': [('file', 'gn_11.bin')],
    'bgt':   [('file', 'gn_15.bin'), ('file', 'gn_14.bin')],
    'fgt':   [('file', 'gn_12.bin'), ('file', 'gn_13.bin')],
    'spr':   [('part', 'gn_06.bin', 0, 0x10000), ('file', 'gn_07.bin'), ('file', 'gn_08.bin'),
              ('file', 'gn_09.bin'), ('part', 'gn_06.bin', 0x10000, 0x10000)],
    'adpcm': [('file', 'gn_04.bin'), ('file', 'gn_03.bin')],
}

SETS = {
    'ginganin': dict(
        desc='Ginga Ninkyouden (set 1)', year='1987', manufacturer='Jaleco',
        zips=['ginganin.zip'], parent=None,
        pieces=dict(_COMMON, main=[('il', 2, [('gn_02.bin', 0), ('gn_01.bin', 1)])],
                    text=[('file', 'gn_10.bin')])),
    'ginganina': dict(
        desc='Ginga Ninkyouden (set 2)', year='1987', manufacturer='Jaleco',
        zips=['ginganina.zip', 'ginganin.zip'], parent='ginganin',
        pieces=dict(_COMMON, main=[('il', 2, [('2.bin', 0), ('1.bin', 1)])],
                    text=[('file', '10.bin')])),
}


def build_image(setname, read):
    """The image exactly as the .mra produces it. read(name) -> bytes."""
    img = bytearray(TOTAL)
    for region, base, size in REGIONS:
        pos = base
        for p in SETS[setname]['pieces'][region]:
            if p[0] == 'file':
                d = read(p[1]); img[pos:pos + len(d)] = d; pos += len(d)
            elif p[0] == 'part':
                d = read(p[1])[p[2]:p[2] + p[3]]; img[pos:pos + len(d)] = d; pos += len(d)
            else:
                w, lanes = p[1], p[2]
                datas = [(read(f), lane) for f, lane in lanes]
                n = len(datas[0][0])
                for i in range(n):
                    for d, lane in datas:
                        img[pos + w * i + lane] = d[i]
                pos += w * n
        assert pos - base <= size, (setname, region, hex(pos - base))
    return img
