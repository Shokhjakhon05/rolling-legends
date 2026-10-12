#!/usr/bin/env python3
"""Writes data/levels/*.json from the campaign table below.

The table is the source of truth for level design; the JSON files are what the game reads.
After editing run:  python3 tool/gen_levels.py && godot --headless -s tests/run_tests.gd
(the tests play every level with a bot and fail if one cannot be finished).
"""
import json
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'levels')


def S(n, width=5, rise=0, items=None):
    p = {'t': 'straight', 'len': n}
    if width != 5: p['width'] = width
    if rise: p['rise'] = rise
    if items: p['items'] = items
    return p


def T(angle, n, width=5, rise=0, items=None):
    p = {'t': 'turn', 'angle': angle, 'len': n}
    if width != 5: p['width'] = width
    if rise: p['rise'] = rise
    if items: p['items'] = items
    return p


def G(n, items=None):
    p = {'t': 'gap', 'len': n}
    if items: p['items'] = items
    return p


def H(n, frm, to, at=2, rows=None, width=5, items=None):
    """A stretch of road with columns frm..to (0..6) missing."""
    p = {'t': 'hole', 'len': n, 'from': frm, 'to': to, 'at': at, 'rows': rows if rows else n - at - 2}
    if width != 5: p['width'] = width
    if items: p['items'] = items
    return p


def C(n, cols, alt=0, at=3, width=5, items=None):
    """Cracked tiles in the given columns; with alt the pattern mirrors every `alt` rows."""
    p = {'t': 'crumble', 'len': n, 'cols': cols, 'at': at, 'rows': n - at - 3}
    if alt: p['alt'] = alt
    if width != 5: p['width'] = width
    if items: p['items'] = items
    return p


def I(count, plat=6, gap=3, width=5, items=None):
    p = {'t': 'islands', 'count': count, 'plat': plat, 'gap': gap}
    if width != 5: p['width'] = width
    if items: p['items'] = items
    return p


def cr(s, d=0.0, n=1, step=2.0, dd=0.0, arc=None):
    c = {'t': 'crystal', 's': s, 'd': d}
    if n > 1: c.update(n=n, step=step)
    if dd: c['dd'] = dd
    if arc: c['arc'] = arc
    return c


def cp(s): return {'t': 'checkpoint', 's': s}
def bar(s, d, w=2.0): return {'t': 'barrier', 's': s, 'd': d, 'w': w}
def pen(s, amp=2.0, period=2.4, phase=0.0, r=0.8): return {'t': 'pendulum', 's': s, 'amp': amp, 'period': period, 'phase': phase, 'r': r}
def npen(s, period=2.6, phase=0.0): return pen(s, 1.6, period, phase, 0.45)  # for a 3-wide bridge
def gate(s, period=3.0, open=1.7, phase=0.0): return {'t': 'gate', 's': s, 'period': period, 'open': open, 'phase': phase}
def boost(s, d=0.0): return {'t': 'boost', 's': s, 'd': d}


SKY, DESERT, NEON = 'sky_islands', 'desert_canyon', 'neon_nights'

# (world, par seconds or 0, pieces). Names live in the translation tables: level_<n>.
LEVELS = [
    # ---- World 1: Sky Islands - learn to steer ------------------------------------------
    (SKY, 0, [S(30, 7), S(40, 7, items=[cr(8, 0, 3, 4)]), S(30, 7)]),
    (SKY, 0, [S(24, 7), S(30, 7, items=[cr(4, -2, 3, 3)]), S(30, 7, items=[cr(4, 2, 3, 3)]),
              S(30, 7, items=[cr(4, 0, 3, 3)]), S(16, 7)]),
    (SKY, 0, [S(24), T(40, 30, items=[cr(10, 0, 3, 3)]), S(22), T(-40, 30, items=[cr(10, 0, 3, 3)]),
              S(24, items=[cr(8, 0, 3, 3)])]),
    (SKY, 0, [S(26), H(20, 1, 3, at=4, rows=10, items=[cr(5, 2, 3, 3)]), S(16),
              H(20, 3, 5, at=4, rows=10, items=[cr(5, -2, 3, 3)]), S(18),
              G(3, items=[cr(0.2, 0, 3, 1.1, arc=1.3)]), S(22)]),
    (SKY, 0, [S(24, items=[cr(8, 0, 3, 3)]), G(3), S(20, items=[cp(4)]), T(35, 26, items=[cr(8, 0, 3, 3)]),
              H(18, 1, 3, at=4, rows=8), S(14), G(4, items=[cr(0.3, 0, 3, 1.3, arc=1.4)]), S(20)]),
    (SKY, 0, [S(22), S(26, 3, items=[cr(6, 0, 4, 4)]), S(16), S(22, 3, items=[cr(6, 0, 3, 5)]),
              S(14, items=[cp(3)]), T(30, 24, 3, items=[cr(8, 0, 2, 6)]), S(18)]),
    (SKY, 0, [S(24), S(18, items=[bar(8, -1.5, 2), cr(8, 1.5)]), S(18, items=[bar(8, 1.5, 2), cr(8, -1.5)]),
              S(18, items=[bar(8, 0, 2), cr(8, 2)]), S(14, items=[cp(3)]),
              T(-35, 26, items=[bar(13, 1.5, 2), cr(13, -1.5)]), S(18, items=[bar(8, -1.5, 2), bar(14, 1.5, 2)]),
              S(14, items=[cr(4, 0, 2, 3)])]),
    (SKY, 0, [S(26), S(22, items=[pen(11, 2.0, 2.8), cr(4, 0, 2, 3)]), S(22, items=[pen(11, 2.0, 2.6, 0.5), cr(16, 0)]),
              S(14, items=[cp(3)]), S(26, items=[pen(8, 2.0, 2.4), pen(18, 2.0, 2.4, 0.5), cr(13, 0)]),
              S(16, items=[cr(5, 0, 2, 3)])]),
    (SKY, 0, [S(22), T(55, 34, items=[cr(8, 2, 5, 4)]), S(16, items=[cr(6, 0, 2, 3)]),
              T(-55, 34, items=[cr(8, -2, 5, 4)]), S(14, items=[cp(3)]),
              T(-40, 26, items=[cr(8, -2, 3, 4)]), T(40, 26, items=[cr(8, 2, 3, 4)]), S(16)]),
    (SKY, 62, [S(22, items=[cr(8, 0, 3, 3)]), H(18, 1, 3, at=4, rows=8), T(40, 26, items=[cr(8, 0, 2, 5)]),
               S(20, 3, items=[cr(5, 0, 3, 4)]), S(14, items=[cp(3)]), G(4, items=[cr(0.3, 0, 3, 1.3, arc=1.4)]),
               S(22, items=[bar(8, -1.5, 2), bar(15, 1.5, 2)]), T(-45, 28), S(24, items=[pen(12, 2.0, 2.6)]),
               S(14, items=[cp(3)]), H(18, 3, 5, at=4, rows=8, items=[cr(6, -2, 3, 3)]), S(16)]),

    # ---- World 2: Desert Canyon - narrow bridges, gates, falling tiles ------------------
    (DESERT, 0, [S(22), T(50, 36, 3, items=[cr(8, 0, 4, 6)]), S(14, items=[cp(3)]),
                 T(-50, 36, 3, items=[cr(8, 0, 4, 6)]), S(16), S(22, 3, items=[cr(5, 0, 3, 5)]), S(16)]),
    (DESERT, 0, [S(22), T(-60, 44, 3, items=[cr(8, 0, 4, 8)]), S(12, items=[cp(3)]),
                 T(70, 48, 3, items=[cr(8, 0, 4, 8)]), S(12, items=[cp(3)]), S(26, 3, items=[bar(13, 0.9, 1.2), cr(13, -0.9)]),
                 T(-30, 22, 3), S(16)]),
    (DESERT, 0, [S(26), S(22, items=[gate(11, 3.2, 1.9), cr(4, 0, 2, 3)]), S(22, items=[gate(11, 3.2, 1.9, 0.5), cr(16, 0)]),
                 S(14, items=[cp(3)]), T(40, 28, items=[cr(8, 0, 2, 6)]), S(22, items=[gate(11, 3.0, 1.7), cr(16, 0)]), S(16)]),
    (DESERT, 0, [S(24), S(20, items=[gate(10, 3.0, 1.7)]), S(18, 3, items=[cr(5, 0, 3, 4)]),
                 S(20, items=[gate(10, 2.8, 1.6, 0.3), cp(16)]), T(-45, 30, items=[cr(8, 0, 3, 5)]),
                 S(26, items=[gate(8, 3.0, 1.7), gate(20, 3.0, 1.7, 0.5), cr(14, 0)]), S(16)]),
    (DESERT, 0, [S(24), C(22, [1, 2], items=[cr(6, 2, 4, 3)]), S(12), C(22, [4, 5], items=[cr(6, -2, 4, 3)]),
                 S(12, items=[cp(3)]), C(30, [1, 2], alt=8, items=[cr(6, 2, 2, 3), cr(14, -2, 2, 3), cr(22, 2, 2, 3)]),
                 S(14), C(20, [1, 5], items=[cr(6, 0, 4, 3)]), S(16)]),
    (DESERT, 0, [S(24), I(3, 7, 3, items=[cr(4, 0, 1), cr(14, 0, 1), cr(24, 0, 1)]), S(10, items=[cp(3)]),
                 T(35, 24), I(3, 6, 3, items=[cr(4, 0, 1), cr(13, 0, 1), cr(22, 0, 1)]), S(16)]),
    (DESERT, 0, [S(24), I(4, 6, 4, items=[cr(5, 0, 1), cr(15, 0, 1), cr(25, 0, 1), cr(35, 0, 1)]), S(10, items=[cp(3)]),
                 S(18, 3, items=[cr(5, 0, 3, 4)]), I(3, 5, 4, width=3, items=[cr(5, 0, 1), cr(14, 0, 1), cr(23, 0, 1)]), S(16)]),
    (DESERT, 0, [S(24), S(26, 3, items=[npen(13, 2.6), cr(5, 0, 2, 3)]), S(12, items=[cp(3)]),
                 T(40, 28, 3, items=[cr(8, 0, 3, 6)]), S(26, 3, items=[npen(9, 2.4), npen(19, 2.4, 0.5), cr(14, 0)]), S(16)]),
    (DESERT, 0, [S(24), S(24, 3, items=[npen(12, 2.4), cr(5, 0, 2, 3)]), G(3), S(10, items=[cp(3)]),
                 T(-50, 34, 3, items=[cr(8, 0, 3, 8)]), S(24, items=[pen(8, 2.0, 2.2), pen(16, 2.0, 2.2, 0.5), cr(12, 0)]),
                 S(20, 3, items=[cr(5, 0, 3, 4)]), S(16)]),
    (DESERT, 95, [S(22, items=[cr(8, 0, 3, 3)]), T(45, 32, 3, items=[cr(8, 0, 3, 7)]), S(12, items=[cp(3)]),
                  S(22, items=[gate(11, 3.0, 1.7)]), C(24, [1, 2], alt=8, items=[cr(6, 2, 2, 3), cr(14, -2, 2, 3)]),
                  S(12, items=[cp(3)]), I(3, 6, 3, items=[cr(4, 0, 1), cr(13, 0, 1), cr(22, 0, 1)]), S(10),
                  T(-45, 32, 3), S(12, items=[cp(3)]), S(26, 3, items=[npen(13, 2.4), cr(6, 0, 2, 12)]),
                  S(20, items=[bar(7, -1.5, 2), bar(14, 1.5, 2)]), S(16)]),

    # ---- World 3: Neon Nights - speed and rhythm -----------------------------------------
    (NEON, 0, [S(24), S(30, items=[boost(6), cr(12, 0, 5, 4)]), T(30, 30, items=[cr(8, 0, 3, 6)]),
               S(30, items=[boost(6), cr(12, -1, 3, 5)]), S(12, items=[cp(3)]), T(-30, 30), S(30, items=[boost(6), cr(12, 1, 3, 5)]), S(16)]),
    (NEON, 0, [S(24), S(26, items=[boost(6), cr(12, 0, 3, 4)]), G(6, items=[cr(0.5, 0, 3, 2.0, arc=1.4)]), S(16, items=[cp(4)]),
               T(40, 30, items=[boost(6), cr(12, 0, 3, 5)]), H(22, 1, 3, at=5, rows=10, items=[cr(6, 2, 3, 3)]),
               S(24, items=[boost(6), bar(18, -1.5, 2), cr(18, 1.5)]), S(16)]),
    (NEON, 0, [S(24), S(20, items=[gate(10, 2.2, 1.3), cr(4, 0, 2, 3)]), S(20, items=[gate(10, 2.2, 1.3, 0.5), cr(15, 0)]),
               S(12, items=[cp(3)]), S(20, items=[gate(10, 2.0, 1.2), cr(15, 0)]), T(35, 26, items=[cr(8, 0, 3, 5)]),
               S(22, items=[gate(8, 2.2, 1.3), gate(16, 2.2, 1.3, 0.5)]), S(16)]),
    (NEON, 0, [S(24), S(22, items=[boost(4), gate(14, 2.4, 1.4), cr(18, 0)]), S(22, items=[gate(8, 2.0, 1.2), pen(16, 2.0, 2.0), cr(12, 0)]),
               S(12, items=[cp(3)]), T(-40, 28, items=[cr(8, 0, 3, 6)]), S(24, items=[gate(8, 2.0, 1.2, 0.3), gate(17, 2.0, 1.2, 0.8), cr(12, 0)]), S(16)]),
    (NEON, 0, [S(24), S(22, items=[boost(6), cr(12, 0, 3, 3)]), G(6, items=[cr(0.5, 0, 3, 2.0, arc=1.4)]), S(14, items=[cp(4)]),
               S(22, items=[boost(6), cr(12, 0, 3, 3)]), G(6, items=[cr(0.5, 0, 3, 2.0, arc=1.4)]), S(14, items=[cp(4)]),
               T(40, 28), S(20, 3, items=[cr(5, 0, 3, 4)]), S(16)]),
    (NEON, 0, [S(24), C(24, [1, 2], alt=7, items=[cr(6, 2, 2, 3)]), S(16, items=[cp(3), bar(11, -1.5, 2)]),
               C(26, [4, 5], alt=7, items=[cr(6, -2, 2, 3)]), S(18, items=[pen(10, 2.0, 2.4)]),
               C(22, [1, 5], items=[cr(6, 0, 4, 3)]), S(16)]),
    (NEON, 0, [S(24), C(24, [1, 2, 3], items=[cr(6, 2, 3, 3)]), S(16, items=[cp(3), bar(11, 1.5, 2)]),
               T(45, 30, items=[cr(8, 0, 3, 6)]), C(26, [3, 4, 5], items=[cr(6, -2, 3, 3)]),
               S(16, items=[cp(3), bar(11, -1.5, 2)]), C(26, [1, 2], alt=6, items=[cr(6, 2, 2, 3), cr(12, -2, 2, 3)]), S(16)]),
    (NEON, 0, [S(24), S(22, items=[boost(5), bar(16, -1.5, 2), cr(16, 1.5)]), I(3, 6, 4, items=[cr(5, 0, 1), cr(15, 0, 1), cr(25, 0, 1)]),
               S(10, items=[cp(3)]), S(22, 3, items=[npen(11, 2.2), cr(5, 0)]), T(-45, 30, 3, items=[cr(8, 0, 3, 7)]),
               S(22, items=[gate(11, 2.2, 1.3), cr(16, 0)]), S(16)]),
    (NEON, 0, [S(24), T(50, 34, 3, items=[cr(8, 0, 3, 8)]), S(10, items=[cp(3)]), C(24, [1, 2], alt=6, items=[cr(6, 2, 2, 3)]),
               S(20, items=[gate(10, 2.0, 1.2)]), S(10, items=[cp(3)]), S(22, items=[boost(5), cr(10, 0, 3, 3)]),
               G(6, items=[cr(0.5, 0, 3, 2.0, arc=1.4)]), S(24, items=[pen(10, 2.0, 2.0), pen(18, 2.0, 2.0, 0.5)]), S(16)]),
    (NEON, 120, [S(22, items=[cr(8, 0, 3, 3)]), S(22, items=[boost(5), bar(16, 1.5, 2), cr(16, -1.5)]), T(45, 30, 3, items=[cr(8, 0, 2, 10)]),
                 S(10, items=[cp(3)]), S(22, items=[gate(8, 2.2, 1.3), gate(16, 2.2, 1.3, 0.5)]),
                 C(24, [1, 2], alt=6, items=[cr(6, 2, 2, 3), cr(12, -2, 2, 3)]), S(10, items=[cp(3)]),
                 I(3, 6, 4, items=[cr(5, 0, 1), cr(15, 0, 1), cr(25, 0, 1)]), S(10), T(-45, 30),
                 S(10, items=[cp(3)]), S(24, 3, items=[npen(8, 2.2), npen(17, 2.2, 0.5)]),
                 S(22, items=[boost(5), cr(10, 0, 3, 3)]), G(6, items=[cr(0.5, 0, 3, 2.0, arc=1.4)]),
                 S(22, items=[pen(11, 2.0, 2.0)]), S(16)]),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    index = []
    counts = {}
    for n, (world, par, pieces) in enumerate(LEVELS, 1):
        counts[world] = counts.get(world, 0) + 1
        w = [SKY, DESERT, NEON].index(world) + 1
        folder = 'world_%02d' % w
        os.makedirs(os.path.join(OUT, folder), exist_ok=True)
        name = '%s/level_%03d.json' % (folder, n)
        crystals = sum(int(i.get('n', 1)) for p in pieces for i in p.get('items', []) if i['t'] == 'crystal')
        data = {
            'schemaVersion': 1,
            'id': 'world_%02d_level_%03d' % (w, n),
            'number': n,
            'world': world,
            'stars': {'crystals': max(1, round(crystals * 0.7)), 'par': par},
            'pieces': pieces,
        }
        with open(os.path.join(OUT, name), 'w') as f:
            json.dump(data, f, indent=1)
            f.write('\n')
        index.append(name)
    with open(os.path.join(OUT, 'index.json'), 'w') as f:
        json.dump({'schemaVersion': 1, 'levels': index}, f, indent=1)
        f.write('\n')
    print('wrote %d levels: %s' % (len(index), counts))


if __name__ == '__main__':
    main()
