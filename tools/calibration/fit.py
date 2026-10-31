#!/usr/bin/env python3
"""Fits k in EP = 1 / (1 + exp(-k * cp)) per rating band against actual game results, and tests it on held-out games.
usage: fit.py evals.tsv | fit.py --check
Draws count as 0.5. cp is clamped at the app's ceiling. Mates stay out of the fit and are only reported.
Games lost on time stay out too: a label judges the board, and in those games the board barely predicts the result
(k about 0.0005 in every band, see the subsets table). Leaving them in lowers k by 20 to 30%."""
import math, random, statistics, sys

CEIL = 1000
LICHESS_K = 0.00368208
BANDS = list(range(600, 2600, 200))
BOOTSTRAPS = 200


def ep(k, cp): return 1 / (1 + math.exp(-k * cp))


def previous_k(r): return 0.00306 + (0.0064 - 0.00306) * min(max((r - 600) / 1700, 0), 1)


def band_of(r): return min(max((r - 600) // 200, 0), len(BANDS) - 1)


def fit_k(pairs, k=0.004):
    """Newton on the mean log loss, which is convex in k. pairs are (y, cp).
    Bracketed, because a lost won position at 1000 cp makes a plain step from too high a k shoot far off."""
    lo, hi = 0.0, 0.03
    for _ in range(60):
        g = h = 0.0
        for y, cp in pairs:
            p = ep(k, cp)
            g += cp * (p - y)
            h += cp * cp * p * (1 - p)
        if g > 0: hi = k
        else: lo = k
        new = k - g / h if h > 0 else (lo + hi) / 2
        if not lo <= new <= hi: new = (lo + hi) / 2
        if abs(new - k) < 1e-7: return new
        k = new
    return k


def log_loss(rows, k_of):
    total = 0.0
    for r in rows:
        x = k_of(r['rating']) * r['cp']
        # log(1 + exp(-x)) and log(1 + exp(x)); fractional y keeps draws in.
        total += r['y'] * math.log1p(math.exp(-x)) + (1 - r['y']) * math.log1p(math.exp(x))
    return total / len(rows)


def monotone(values, weights):
    """Rating should only make k grow, so adjacent bands where noise says otherwise are pooled."""
    blocks = [[v, w, 1] for v, w in zip(values, weights)]
    i = 0
    while i < len(blocks) - 1:
        a, b = blocks[i], blocks[i + 1]
        if a[0] > b[0]:
            blocks[i:i + 2] = [[(a[0] * a[1] + b[0] * b[1]) / (a[1] + b[1]), a[1] + b[1], a[2] + b[2]]]
            i = max(i - 1, 0)
        else:
            i += 1
    return [v for v, _, n in blocks for _ in range(n)]


def interpolate(knots):
    def k_of(r):
        if r <= knots[0][0]: return knots[0][1]
        for (r0, k0), (r1, k1) in zip(knots, knots[1:]):
            if r <= r1: return k0 + (k1 - k0) * (r - r0) / (r1 - r0)
        return knots[-1][1]
    return k_of


def load(path):
    rows, mates = [], []
    for line in open(path):
        p = line.rstrip('\n').split('\t')
        row = {'stm': p[0].split()[1] == p[1], 'rating': int(p[2]), 'y': float(p[4]), 'game': int(p[5]), 'ply': int(p[6]),
               'speed': p[7], 'term': p[8], 'score': int(p[-1])}
        if p[-2] == 'cp':
            row['cp'] = max(-CEIL, min(CEIL, row['score']))
            rows.append(row)
        else:
            mates.append(row)
    return rows, mates


def bootstrap(rows, k0, rng):
    by_game = {}
    for r in rows: by_game.setdefault(r['game'], []).append((r['y'], r['cp']))
    games = list(by_game.values())
    fits = []
    for _ in range(BOOTSTRAPS):
        fits.append(fit_k([p for g in rng.choices(games, k=len(games)) for p in g], k0))
    fits.sort()
    return fits[int(.025 * BOOTSTRAPS)], fits[int(.975 * BOOTSTRAPS) - 1]


def main(path):
    everything, mates = load(path)
    rows = [r for r in everything if r['term'] == 'Normal']
    mates = [r for r in mates if r['term'] == 'Normal']
    rng = random.Random(1475)
    games = sorted({r['game'] for r in rows})
    held = set(rng.sample(games, len(games) // 5))
    train = [r for r in rows if r['game'] not in held]
    test = [r for r in rows if r['game'] in held]
    draws = sum(r['y'] == .5 for r in rows) / len(rows)
    print(f'{len(rows)} cp positions from {len(games)} games, draws {draws:.1%}; left out: {len(everything) - len(rows)} from games lost on time, {len(mates)} mate scores')
    print(f'train {len(train)}, held out {len(test)} (by game)\n')

    fitted, weights, medians, intervals = [], [], [], []
    for b in range(len(BANDS)):
        rows_b = [r for r in train if band_of(r['rating']) == b]
        k = fit_k([(r['y'], r['cp']) for r in rows_b])
        fitted.append(k); weights.append(len(rows_b))
        medians.append(round(statistics.median(r['rating'] for r in rows_b)))
        intervals.append(bootstrap(rows_b, k, rng))
    smooth = monotone(fitted, weights)
    k_of = interpolate(list(zip(medians, smooth)))

    print('band       n   median  k raw    95% interval      k table  previous held-out loss: table  previous .00368')
    for b, edge in enumerate(BANDS):
        t = [r for r in test if band_of(r['rating']) == b]
        print(f'{edge:>4}+ {weights[b]:>6} {medians[b]:>6}  {fitted[b]:.5f}  {intervals[b][0]:.5f}-{intervals[b][1]:.5f}  {smooth[b]:.5f}  '
              f'{previous_k(medians[b]):.5f}          {log_loss(t, k_of):.5f}  {log_loss(t, previous_k):.5f}  {log_loss(t, lambda _: LICHESS_K):.5f}')
    print(f'\nall held out: table {log_loss(test, k_of):.5f}, previous {log_loss(test, previous_k):.5f}, '
          f'constant .00368 {log_loss(test, lambda _: LICHESS_K):.5f}, coin flip {math.log(2):.5f}')

    print('\nheld-out calibration (cp from the record\'s side): predicted, actual, n, for table | previous')
    edges = [-1001, -500, -300, -200, -100, -50, 0, 50, 100, 200, 300, 500, 1000]
    gap_t = gap_p = 0.0
    for lo, hi in zip(edges, edges[1:]):
        m = [r for r in test if lo < r['cp'] <= hi]
        if not m: continue
        actual = sum(r['y'] for r in m) / len(m)
        table = sum(ep(k_of(r['rating']), r['cp']) for r in m) / len(m)
        previous = sum(ep(previous_k(r['rating']), r['cp']) for r in m) / len(m)
        gap_t += abs(table - actual) * len(m); gap_p += abs(previous - actual) * len(m)
        print(f'{lo:>6}..{hi:<5} {table:.3f} {actual:.3f} {len(m):>6} | {previous:.3f}')
    print(f'mean absolute gap, weighted by n: table {gap_t / len(test):.4f}, previous {gap_p / len(test):.4f}')

    both = test + [r for r in everything if r['term'] != 'Normal']
    print(f'same table on held-out games with the games lost on time put back ({len(both)}): table {log_loss(both, k_of):.5f}, previous {log_loss(both, previous_k):.5f}')

    stm = fit_k([(r['y'], r['cp']) for r in rows if r['stm']])
    other = fit_k([(r['y'], r['cp']) for r in rows if not r['stm']])
    print(f'\nk by point of view, all bands: side to move {stm:.5f}, other side {other:.5f}')

    print('\nk per band on subsets of all games, to see what the choice of data does:')
    print(' ' * 24 + ''.join(f'{e:>8}' for e in BANDS))
    subsets = [('all', lambda r: True), ('no time forfeits', lambda r: r['term'] == 'Normal'), ('time forfeits only', lambda r: r['term'] != 'Normal'),
               ('blitz', lambda r: r['speed'] == 'blitz'), ('rapid + classical', lambda r: r['speed'] != 'blitz'),
               ('ply under 30', lambda r: r['ply'] < 30), ('ply 30-59', lambda r: 30 <= r['ply'] < 60), ('ply 60+', lambda r: r['ply'] >= 60)]
    for name, keep in subsets:
        cells = []
        for b in range(len(BANDS)):
            m = [(r['y'], r['cp']) for r in everything if band_of(r['rating']) == b and keep(r)]
            cells.append(f'{fit_k(m):8.5f}' if len(m) >= 200 else ' ' * 8)
        n = sum(1 for r in everything if keep(r))
        print(f'{name:<18}{n:>6}' + ''.join(cells))

    print('\nmate scores, not fitted: mate distance for the record\'s side, actual score, app EP, n')
    for lo, hi in ((1, 3), (4, 8), (9, 99)):
        for sign in (1, -1):
            m = [r for r in mates if lo <= sign * r['score'] <= hi]
            if not m: continue
            app = sum(ep(k_of(r['rating']), sign * max(CEIL, 2500 - 100 * abs(r['score']))) for r in m) / len(m)
            print(f'{"+" if sign > 0 else "-"}{lo}..{hi:<3} {sum(r["y"] for r in m) / len(m):.3f}  {app:.3f}  {len(m)}')

    print('\nSwift table:')
    print('    static let kTable: [(rating: Int, k: Double)] = [')
    for r, k in zip(medians, smooth): print(f'        ({r}, {k:.5f}),')
    print('    ]')


def check():
    rng = random.Random(7)
    pairs = []
    for _ in range(40000):
        cp = rng.randint(-600, 600)
        pairs.append((1.0 if rng.random() < ep(0.005, cp) else 0.0, cp))
    assert abs(fit_k(pairs) - 0.005) < 0.0002, fit_k(pairs)
    # A draw is half a point, so all-draw records say nothing about cp and k collapses to zero.
    assert abs(fit_k([(.5, cp) for cp in (-200, -50, 50, 200)])) < 1e-4
    assert monotone([3, 1, 2], [1, 1, 1]) == [2, 2, 2]
    assert monotone([1, 2, 3], [1, 1, 1]) == [1, 2, 3]
    k_of = interpolate([(700, .003), (900, .005)])
    assert k_of(600) == .003 and k_of(800) == .004 and k_of(1000) == .005
    print('ok')


if sys.argv[1] == '--check': check()
else: main(sys.argv[1])
