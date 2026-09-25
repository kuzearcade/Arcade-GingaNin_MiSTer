#!/usr/bin/env python3
"""Generate the Arcade-GingaNin_MiSTer .mra files from tools/gn_romdata.py.

    tools/gen_gn_mra.py              write releases/*.mra (the clone under
                                     releases/_alternatives/_Ginga Ninkyouden/)
    tools/gen_gn_mra.py --images     write each set's image and its regions to
                                     ~/gn_images/<set>/ for the simulations

The image goes through the normal ROM download (ioctl index 0); the core keeps
its first 0x3C000 bytes in BRAM and writes the rest to SDRAM (PLAN D1 A).

Interleave maps: the rightmost map character is the LOWEST-addressed output
byte (measured on the board by MS1BCD for output="16": map="01" is the even
byte). gn_02 is the 68000's even (high) byte: LOAD16_BYTE at offset 0.

DIPs come from MAME's own -listxml (MS1-47). The DSW port is 16 bits:
<switches> byte 0 = DSW[7:0], byte 1 = DSW[15:8]. Byte 2 is flags: bit 7 is
the Autofire unlock (tools/gen_autofire_mra.py sets it in autofire_releases/).

Every file written is parsed as XML first (NMKBP964: a '--' inside a comment
broke strict parsers).
"""
import argparse, os, re, subprocess, sys, zipfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape as _xml_escape

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gn_romdata as R

ROOT = os.path.join(HERE, '..')
ROMS = os.path.join(ROOT, 'mame_roms')
RELEASES = os.path.join(ROOT, 'releases')
MAME = os.path.expanduser('~/mame/mame')
PARENT_DIR = '_alternatives/_Ginga Ninkyouden'

def x(v): return _xml_escape(str(v))
FAT_FORBIDDEN = {':': '-', '/': '-', '\\': '-', '?': '', '*': '', '<': '', '>': '', '|': '-', '"': "'"}
def fat_safe(desc): return ''.join(FAT_FORBIDDEN.get(c, c) for c in desc).rstrip('. ')

_COIN = re.compile(r'^(\d+) Coins?/(\d+) Credits?$')
def dip_id(name):
    if name == 'Free Play': return 'Free_Play'
    m = _COIN.match(name)
    return f'{m.group(1)}C_{m.group(2)}C' if m else name

def dips_from_mame(setname):
    xml = subprocess.run([MAME, '-listxml', setname], capture_output=True, text=True).stdout
    root = ET.fromstring(xml)
    mach = next(m for m in root.iter('machine') if m.get('name') == setname)
    default, dips = 0xFFFF, []
    for sw in mach.iter('dipswitch'):
        if sw.get('tag') not in ('DSW', ':DSW'):
            continue
        mask = int(sw.get('mask'))
        lo = (mask & -mask).bit_length() - 1
        hi = mask.bit_length() - 1
        ids = ['Undefined'] * (1 << (hi - lo + 1))
        for v in sw.iter('dipvalue'):
            ids[int(v.get('value')) >> lo] = v.get('name')
            if v.get('default') == 'yes':
                default = (default & ~mask) | int(v.get('value'))
        dips.append(dict(name=sw.get('name'), bits=(lo, hi), ids=ids))
    return default, dips

def switches_xml(setname, flags):
    default, dips = dips_from_mame(setname)
    out = [f'  <switches default="{default & 0xFF:02X},{default >> 8:02X},{flags:02X}">\n']
    for d in dips:
        if d['name'] in ('Unused', 'Unknown'):
            continue
        lo, hi = d['bits']
        bits = f'{lo}' if lo == hi else f'{lo},{hi}'
        out.append(f'    <dip bits="{bits}" name="{x(d["name"])}" ids="{",".join(x(dip_id(i)) for i in d["ids"])}"/>\n')
    out.append('  </switches>\n')
    return ''.join(out)

class Zips:
    """The set's zips in the .mra's order: a clone falls back to its parent."""
    def __init__(self, names): self.z = [zipfile.ZipFile(os.path.join(ROMS, n)) for n in names]
    def _find(self, name):
        for z in self.z:
            if name in z.namelist(): return z
        raise KeyError(name)
    def read(self, name): return self._find(name).read(name)
    def crc(self, name): return self._find(name).getinfo(name).CRC
    def size(self, name): return self._find(name).getinfo(name).file_size

def rom_xml(setname):
    s = R.SETS[setname]
    z = Zips(s['zips'])
    out = []
    for region, base, size in R.REGIONS:
        out.append(f'    <!-- {region}: 0x{size:05X} bytes at image 0x{base:06X} -->\n')
        used = 0
        for p in s['pieces'][region]:
            if p[0] == 'file':
                out.append(f'    <part crc="{z.crc(p[1]):08x}" name="{x(p[1])}"/>\n')
                used += z.size(p[1])
            elif p[0] == 'part':
                out.append(f'    <part crc="{z.crc(p[1]):08x}" name="{x(p[1])}" offset="0x{p[2]:X}" length="0x{p[3]:X}"/>\n')
                used += p[3]
            else:
                w, lanes = p[1], p[2]
                out.append(f'    <interleave output="{8 * w}">\n')
                for f, lane in lanes:
                    m = ''.join('1' if k == lane else '0' for k in reversed(range(w)))
                    out.append(f'      <part crc="{z.crc(f):08x}" name="{x(f)}" map="{m}"/>\n')
                out.append('    </interleave>\n')
                used += w * z.size(lanes[0][0])
        if used < size:
            out.append(f'    <part repeat="0x{size - used:X}">00</part>\n')
    return ''.join(out)

# Positional: MiSTer puts <buttons> entry k on joystick bit 4+k, and
# GingaNin.sv's CONF_STR J1 line and input mapping expect exactly this list.
# Button 3 is the autofire plain-fire alias (a plain Button 1 otherwise unused).
BUTTONS = ('Button 1,Button 2,Button 3,Start,Coin', 'Y,B,A,Start,R')

def mra(setname):
    s = R.SETS[setname]
    names, defaults = BUTTONS
    parent = f"\n  <parent>{s['parent']}</parent>" if s['parent'] else ''
    return f"""<!--
  {x(s['desc'])}: {x(s['manufacturer'])} {s['year']}, MAME jaleco/ginganin.cpp ({setname}).
  Generated by tools/gen_gn_mra.py from tools/gn_romdata.py; do not hand-edit.
  One image through the ROM download: the first 0x3C000 bytes (programs, text
  tiles, BG map) stay in BRAM, the rest goes to SDRAM. <switches> byte 2:
  bit 7 = Autofire unlock.
-->
<misterromdescription>
  <name>{x(s['desc'])}</name>
  <mratimestamp>202609240000</mratimestamp>
  <mameversion>0289</mameversion>
  <setname>{setname}</setname>{parent}
  <year>{s['year']}</year>
  <manufacturer>{x(s['manufacturer'])}</manufacturer>
  <category>Arcade</category>
  <rbf>GingaNin</rbf>
  <rotation>horizontal</rotation>

{switches_xml(setname, 0x00)}
  <buttons names="{names}" default="{defaults}"/>

  <rom index="0" zip="{'|'.join(s['zips'])}" md5="none">
{rom_xml(setname)}  </rom>
</misterromdescription>
"""

CARRY_RE = re.compile(r'\n  <!-- (?:High scores|Cheats).*?</rom>\n(?:  <nvram index="4"[^/]*/>\n)?', re.S)
def carry_over(path):
    if not os.path.exists(path): return ''
    return ''.join(CARRY_RE.findall(open(path, encoding='utf-8').read()))

def mra_path(sn):
    s = R.SETS[sn]
    d = RELEASES if not s['parent'] else os.path.join(RELEASES, PARENT_DIR)
    return os.path.join(d, fat_safe(s['desc']) + '.mra')

def images():
    for sn, s in R.SETS.items():
        img = R.build_image(sn, Zips(s['zips']).read)
        d = os.path.expanduser(f'~/gn_images/{sn}')
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, 'image.bin'), 'wb').write(img)
        for region, base, size in R.REGIONS:
            open(os.path.join(d, region + '.bin'), 'wb').write(img[base:base + size])
        print(f'{sn}: {len(img):#x} bytes -> {d}')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--images', action='store_true')
    a = ap.parse_args()
    if a.images: return images()
    for sn in R.SETS:
        path = mra_path(sn)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        text = mra(sn).replace('</misterromdescription>', carry_over(path) + '</misterromdescription>')
        ET.fromstring(text)                          # refuse to write a malformed .mra
        open(path, 'w', encoding='utf-8').write(text)
        print('wrote', os.path.relpath(path, ROOT))

if __name__ == '__main__':
    main()
