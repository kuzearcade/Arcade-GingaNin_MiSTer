#!/usr/bin/env python3
"""Add a <rom index="5"> cheat table to each .mra, from Pugsy's MAME cheat XML.

MiSTer's CONF_STR is compiled into the core and shared by every game on that
.rbf, so a per-game menu of cheat NAMES is not expressible. Instead the core
carries seven fixed, well-known slots and each .mra supplies that game's
addresses for them. Slots a game has no cheat for are hidden in the OSD via
status_menumask.

Pugsy writes the same poke in several forms -- maincpu.pb@ (program byte),
maincpu.rb@ (direct byte) and maincpu.pw@ (program word). They all mean "write
this value at this 68000 address", and accepting all three lifts coverage from
52 to 82 of our 94 sets. Cheats with a <parameter> (user-selected value) are
skipped: they need UI the OSD cannot give them.

Table layout, big-endian, 6 bytes per action, 3 actions per slot, 7 slots
(rtl/cheats.sv):
    1 byte   count for this slot (0..3)
    1 byte   reserved
    then 3 x { 3 bytes address, 1 byte kind, 2 bytes value }
    kind 0 byte, 1 word, 2 masked byte (value = {mask, byte})
"""
import re, glob, os, sys

# One game per core, so the OSD names the slots after THIS game's cheats
# (GingaNin.sv's CONF_STR, same order): the descs Pugsy uses in ginganin.xml
# and ginganina.xml. The seventh slot is unused.
SLOTS = ["Infinite Time", "Infinite Energy", "Infinite Beam", "Infinite Sword",
         "P1 Infinite Lives", "P2 Infinite Lives", "(unused)"]
MAXACT = 3
ACT = re.compile(r'<action(?:\s+condition="[^"]*")?\s*>'
                 r'maincpu\.([pr])([bw])@([0-9A-Fa-f]+)=([0-9A-Fa-f]+)</action>')
# X|(maincpu.pb@A BAND ~M): set the bits of M to X, keep the rest. Kind 2.
MASKED = re.compile(r'<action(?:\s+condition="[^"]*")?\s*>'
                    r'maincpu\.pb@([0-9A-Fa-f]+)=([0-9A-Fa-f]+)\|\(maincpu\.pb@\1 BAND ~([0-9A-Fa-f]+)\)</action>')

def parse(path):
    t = open(path, encoding='utf-8', errors='replace').read()
    out = {}
    for m in re.finditer(r'<cheat desc="([^"]*)"\s*>(.*?)</cheat>', t, re.S):
        d, body = m.group(1).strip(), m.group(2)
        if d not in SLOTS or '<parameter' in body or d in out:
            continue
        acts = [(int(a, 16), 1 if sz == 'w' else 0, int(v, 16)) for _, sz, a, v in ACT.findall(body)]
        # masked: value byte in the low half, mask in the high half
        acts += [(int(a, 16), 2, (int(m, 16) << 8) | int(v, 16)) for a, v, m in MASKED.findall(body)]
        if len(acts) > MAXACT:
            print(f'  {os.path.basename(path)}: "{d}" has {len(acts)} actions, engine holds {MAXACT}; skipped')
            continue
        if acts:
            out[d] = acts
    return out

def table(found):
    rows = []
    for name in SLOTS:
        acts = found.get(name, [])
        rec = [len(acts), 0]
        for i in range(MAXACT):
            if i < len(acts):
                a, sz, v = acts[i]
                rec += [(a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF, sz, (v >> 8) & 0xFF, v & 0xFF]
            else:
                rec += [0, 0, 0, 0, 0, 0]
        rows.append(rec)
    return rows

def main():
    D = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else '~/Downloads/cheat0279/cheat')
    root = os.path.dirname(os.path.abspath(__file__)) + '/..'
    added = skipped = 0
    for p in sorted(glob.glob(root + '/releases/*.mra') + glob.glob(root + '/releases/_alternatives/*/*.mra')):
        t = open(p, encoding='utf-8').read()
        if 'index="5"' in t:
            continue
        sn = re.search(r'<setname>([^<]+)', t).group(1).strip()
        src = f'{D}/{sn}.xml'
        if not os.path.exists(src):
            skipped += 1; continue
        found = parse(src)
        if not found:
            skipped += 1; continue
        rows = table(found)
        body = '\n'.join('        ' + ' '.join(f'{b:02X}' for b in r) for r in rows)
        names = ', '.join(n for n in SLOTS if n in found)
        blk = (f'\n  <!-- Cheats (Pugsy\'s MAME cheat database). Slots in fixed order:\n'
               f'       {", ".join(SLOTS)}.\n'
               f'       This set provides: {names}. See tools/gen_cheats_mra.py. -->\n'
               f'  <rom index="5" md5="none">\n    <part>\n{body}\n    </part>\n  </rom>\n')
        open(p, 'w', encoding='utf-8').write(t.replace('</misterromdescription>', blk + '</misterromdescription>'))
        added += 1
    print(f"added cheat tables to {added} .mra; {skipped} had no usable cheats")

if __name__ == '__main__':
    main()
