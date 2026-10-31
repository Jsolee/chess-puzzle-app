#!/usr/bin/env python3
"""Curates the bundled puzzle set from the Lichess export (CC0) and writes puzzles.bin.

usage: tools/curate_puzzles.py [--src .cache/puzzles/lichess_db_puzzle.csv.zst] [--out Scachs/Resources/puzzles.bin]

Streams the .zst through `zstd -dc`, never writes the decompressed CSV. Deterministic: the
same input gives the same bytes. Recut at each major release.

File format, little-endian, sorted by rating then id, read by Scachs/Puzzles/PuzzleStore.swift:

  Header, 64 bytes:
    0   magic "SCPZ"            4   version u16        6   tag count u16     8   puzzle count u32
    12  tag table offset u32    16  rating column      20  id column         24  mask column
    28  flags column            32  plies column       36  popularity col    40  occupancy column
    44  offset column           48  blobs              52  file length u32   56  daily count u32
    60  reserved u32
  Tag table: tag names joined by newlines; line n is bit n of the mask.
  Columns, one entry per puzzle:
    rating u16 | id u32 (5-char base-62) | mask u64 | flags u8 | plies u8 | popularity i8 |
    occupancy u64 (bit 0 = a1) | offset u32 (from the start of the blobs)
  flags: 1 black to move in the FEN, 2 K, 4 Q, 8 k, 16 q, 32 has ep file, 64 daily, 128 spare.
  Blob: 4-bit pieces in ascending square order (PNBRQKpnbrqk = 0..11, low nibble first, 0xF pad);
    ep file byte (0-7) if flagged; moves u16 each (from | to << 6 | promotion << 12, promotion
    0 none, 1 n, 2 b, 3 r, 4 q).

Derived tags are not stored: mateInN is min(plies / 2, 5) when `mate` is set, and the length tag
comes from plies. Halfmove and fullmove counters are dropped.
"""
import argparse
import collections
import csv
import gc
import hashlib
import io
import math
import os
import struct
import subprocess
import sys
import zlib

STRICT = dict(pop=90, plays=500, rd=85, plies=8)
RELAXED = dict(pop=80, plays=100, rd=100, plies=10)
RELAXED_PER_TAG_PER_BAND = 60
MATE_IN_1_CAP = 0.08
TAGLESS_CAP = 0.20

DERIVED = {'oneMove', 'short', 'long', 'veryLong', 'mateIn1', 'mateIn2', 'mateIn3', 'mateIn4', 'mateIn5'}
# Tags that describe the puzzle rather than teach a skill.
NON_SKILL = DERIVED | {'mate', 'advantage', 'crushing', 'equality', 'master', 'masterVsMaster', 'superGM',
                       'opening', 'middlegame', 'endgame'}

BASE62 = {c: i for i, c in enumerate('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz')}
PIECE = {c: i for i, c in enumerate('PNBRQKpnbrqk')}
PROMOTION = {'': 0, 'n': 1, 'b': 2, 'r': 3, 'q': 4}
F_BLACK, F_EP, F_DAILY = 1, 32, 64


def band_quota(band):
    if band < 400:
        return 0
    if band < 800:
        return 1600
    if band < 2000:
        return 6400
    if band < 2400:
        return 3200
    return 800


Row = collections.namedtuple('Row', 'relaxed neg_score id rating pop plays fen moves tags daily mate')


def valid_id(s):
    return len(s) == 5 and all(c in BASE62 for c in s)


def stream(src):
    """Yields (header columns, row) for every well-formed CSV row, parsed by header name."""
    proc = subprocess.Popen(['zstd', '-dc', src], stdout=subprocess.PIPE)
    reader = csv.reader(io.TextIOWrapper(proc.stdout, encoding='utf-8', newline=''))
    header = next(reader)
    col = {name: i for i, name in enumerate(header)}
    for name in ('PuzzleId', 'FEN', 'Moves', 'Rating', 'RatingDeviation', 'Popularity', 'NbPlays', 'Themes'):
        if name not in col:
            sys.exit(f'CSV has no {name} column: {header}')
    for x in reader:
        if len(x) == len(header):
            yield col, x
    if proc.wait() != 0:
        sys.exit('zstd failed')


def classify(x, col):
    pop, plays, rd = int(x[col['Popularity']]), int(x[col['NbPlays']]), int(x[col['RatingDeviation']])
    plies = x[col['Moves']].count(' ') + 1
    strict = pop >= STRICT['pop'] and plays >= STRICT['plays'] and rd <= STRICT['rd'] and plies <= STRICT['plies']
    relaxed = pop >= RELAXED['pop'] and plays >= RELAXED['plays'] and rd <= RELAXED['rd'] and plies <= RELAXED['plies']
    return strict, relaxed, pop, plays


def survey(src):
    """First pass: tag frequencies and the natural mate share per band."""
    stats, natural, natural_mate, seen_tags, freq = (collections.Counter() for _ in range(5))
    for col, x in stream(src):
        stats['rows'] += 1
        tags = x[col['Themes']].split()
        seen_tags.update(tags)
        if 'equality' in tags:
            stats['equality'] += 1
            continue
        band = int(x[col['Rating']]) // 100 * 100
        natural[band] += 1
        if 'mate' in tags:
            natural_mate[band] += 1
        strict, relaxed, _, _ = classify(x, col)
        stats['strict'] += strict
        stats['relaxed'] += relaxed
        stats['daily'] += 'DailyDate' in col and x[col['DailyDate']] != ''
        if relaxed:
            freq.update(t for t in tags if t not in NON_SKILL)
    return stats, natural, natural_mate, seen_tags, freq


def primary_tag(tags, freq):
    """The puzzle's rarest skill tag, else its mate length, else nothing."""
    skills = [t for t in tags if t not in NON_SKILL]
    if skills:
        return min(skills, key=lambda t: (freq[t], t))
    for t in ('mateIn1', 'mateIn2', 'mateIn3', 'mateIn4', 'mateIn5'):
        if t in tags:
            return t
    return 'tagless'


def collect(src, freq):
    """Second pass: the candidates per band and primary tag, trimmed as they come to keep memory bounded."""
    strict_rows = collections.defaultdict(lambda: collections.defaultdict(list))
    relaxed_rows = collections.defaultdict(lambda: collections.defaultdict(list))
    dailies = collections.defaultdict(list)

    def add(bucket, row, limit):
        bucket.append(row)
        if len(bucket) >= 2 * limit:
            bucket.sort()
            del bucket[limit:]

    for col, x in stream(src):
        tags = x[col['Themes']].split()
        if 'equality' in tags:
            continue
        rating = int(x[col['Rating']])
        band = rating // 100 * 100
        quota = band_quota(band)
        if quota == 0 or not valid_id(x[col['PuzzleId']]):
            continue
        strict, relaxed, pop, plays = classify(x, col)
        daily = 'DailyDate' in col and x[col['DailyDate']] != ''
        if not (strict or relaxed or daily):
            continue
        tags = tuple(sys.intern(t) for t in tags)
        row = Row(not strict, -(pop + 4 * math.log10(max(1, plays))), x[col['PuzzleId']], rating, pop, plays,
                  x[col['FEN']], x[col['Moves']], tags, daily, 'mate' in tags)
        if daily:
            dailies[band].append(row)
        elif strict:
            add(strict_rows[band][primary_tag(tags, freq)], row, quota)
        else:
            add(relaxed_rows[band][primary_tag(tags, freq)], row, RELAXED_PER_TAG_PER_BAND)
    return strict_rows, relaxed_rows, dailies


def select(strict_rows, relaxed_rows, dailies, natural, natural_mate, freq):
    selected, report = [], {}
    for band in sorted(set(strict_rows) | set(relaxed_rows) | set(dailies)):
        quota = band_quota(band)
        buckets = {}
        for t in set(strict_rows[band]) | set(relaxed_rows[band]):
            buckets[t] = sorted(strict_rows[band][t])[:quota] + sorted(relaxed_rows[band][t])[:RELAXED_PER_TAG_PER_BAND]
        # Every daily is kept and counts against the band's quota and caps.
        sel = list(dailies[band])
        taken = collections.Counter(primary_tag(x.tags, freq) for x in sel)
        mates = sum(x.mate for x in sel)
        mate_cap = round(quota * natural_mate[band] / natural[band])
        mate1_cap, tagless_cap = int(quota * MATE_IN_1_CAP), int(quota * TAGLESS_CAP)
        cursor = collections.Counter()
        order = sorted(buckets, key=lambda t: (len(buckets[t]), t))
        alive = True
        while len(sel) < quota and alive:
            alive = False
            for t in order:
                if len(sel) >= quota:
                    break
                if (t == 'tagless' and taken[t] >= tagless_cap) or (t == 'mateIn1' and taken[t] >= mate1_cap):
                    continue
                bucket = buckets[t]
                i = cursor[t]
                while i < len(bucket):
                    x = bucket[i]
                    i += 1
                    if x.mate and mates >= mate_cap:
                        continue
                    # Strict rows sort first, so a relaxed row here means strict supply ran out.
                    if x.relaxed and taken[t] >= RELAXED_PER_TAG_PER_BAND:
                        i = len(bucket)
                        break
                    sel.append(x)
                    taken[t] += 1
                    mates += x.mate
                    alive = True
                    break
                cursor[t] = i
        selected.extend(sel)
        report[band] = dict(quota=quota, got=len(sel), mate=mates, cap=mate_cap,
                            natural=natural_mate[band] / natural[band], relaxed=sum(x.relaxed for x in sel))
    selected.sort(key=lambda x: (x.rating, x.id))
    return selected, report


def id30(s):
    v = 0
    for c in s:
        v = v * 62 + BASE62[c]
    return v


def sq(s):
    return ord(s[0]) - 97 + (ord(s[1]) - 49) * 8


def mv16(u):
    return sq(u[:2]) | sq(u[2:4]) << 6 | PROMOTION[u[4:]] << 12


def parse_fen(fen):
    fields = fen.split()
    board, stm, castling, ep = fields[0], fields[1], fields[2], fields[3]
    occ, pieces = 0, {}
    for ri, rank in enumerate(board.split('/')):
        f = 0
        for ch in rank:
            if ch.isdigit():
                f += int(ch)
            else:
                s = (7 - ri) * 8 + f
                occ |= 1 << s
                pieces[s] = PIECE[ch]
                f += 1
    flags = F_BLACK if stm == 'b' else 0
    for i, c in enumerate('KQkq'):
        if c in castling:
            flags |= 2 << i
    ep_file = None
    if ep != '-':
        flags |= F_EP
        ep_file = ord(ep[0]) - 97
    return occ, [pieces[s] for s in sorted(pieces)], flags, ep_file


def nibbles(ps):
    out = bytearray()
    for i in range(0, len(ps), 2):
        out.append(ps[i] | (ps[i + 1] if i + 1 < len(ps) else 0xF) << 4)
    return bytes(out)


def write_bin(selected, out):
    tag_names = sorted({t for x in selected for t in x.tags if t not in DERIVED})
    if len(tag_names) > 64:
        sys.exit(f'{len(tag_names)} stored tags do not fit the u64 mask: {tag_names}')
    bit = {t: i for i, t in enumerate(tag_names)}
    tag_table = '\n'.join(tag_names).encode()

    n = len(selected)
    rating, ident, mask, flags, plies, pop, occ, offs, blobs = [], [], [], bytearray(), bytearray(), [], [], [], bytearray()
    for x in selected:
        o, ps, f, ep = parse_fen(x.fen)
        ms = x.moves.split()
        rating.append(x.rating)
        ident.append(id30(x.id))
        mask.append(sum(1 << bit[t] for t in set(x.tags) if t in bit))
        flags.append(f | (F_DAILY if x.daily else 0))
        plies.append(len(ms))
        pop.append(x.pop)
        occ.append(o)
        offs.append(len(blobs))
        blobs += nibbles(ps)
        if ep is not None:
            blobs.append(ep)
        blobs += struct.pack(f'<{len(ms)}H', *map(mv16, ms))

    columns = [struct.pack(f'<{n}H', *rating), struct.pack(f'<{n}I', *ident), struct.pack(f'<{n}Q', *mask), bytes(flags),
               bytes(plies), struct.pack(f'<{n}b', *pop), struct.pack(f'<{n}Q', *occ), struct.pack(f'<{n}I', *offs)]
    at = 64
    tag_at = at
    at += len(tag_table)
    col_at = []
    for c in columns:
        col_at.append(at)
        at += len(c)
    blobs_at = at
    length = at + len(blobs)
    daily = sum(x.daily for x in selected)
    header = struct.pack('<4sHHI13I', b'SCPZ', 1, len(tag_names), n, tag_at, *col_at, blobs_at, length, daily, 0)
    assert len(header) == 64
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(header + tag_table + b''.join(columns) + bytes(blobs))
    os.replace(tmp, out)
    return tag_names


def check_round_trip(selected, out):
    """Decodes every record back from the file and compares it with the CSV values."""
    data = open(out, 'rb').read()
    magic, version, n_tags, n, tag_at, r_at, i_at, m_at, f_at, p_at, pop_at, o_at, off_at, b_at, length, daily, _ = \
        struct.unpack_from('<4sHHI13I', data)
    assert magic == b'SCPZ' and length == len(data) and n == len(selected)
    names = data[tag_at:r_at].decode().split('\n')
    assert len(names) == n_tags
    alphabet = {v: k for k, v in BASE62.items()}
    letters = 'PNBRQKpnbrqk'
    bad = 0
    prev = -1
    for k, x in enumerate(selected):
        rating = struct.unpack_from('<H', data, r_at + 2 * k)[0]
        ident = struct.unpack_from('<I', data, i_at + 4 * k)[0]
        mask = struct.unpack_from('<Q', data, m_at + 8 * k)[0]
        flags, plies = data[f_at + k], data[p_at + k]
        pop = struct.unpack_from('<b', data, pop_at + k)[0]
        occ = struct.unpack_from('<Q', data, o_at + 8 * k)[0]
        at = b_at + struct.unpack_from('<I', data, off_at + 4 * k)[0]
        s = ''
        for _ in range(5):
            s = alphabet[ident % 62] + s
            ident //= 62
        count = bin(occ).count('1')
        ps = []
        for j in range(count):
            byte = data[at + j // 2]
            ps.append(byte & 15 if j % 2 == 0 else byte >> 4)
        at += (count + 1) // 2
        ep = None
        if flags & F_EP:
            ep = data[at]
            at += 1
        ms = struct.unpack_from(f'<{plies}H', data, at)
        squares = [j for j in range(64) if occ >> j & 1]
        board = {sq_: letters[p] for sq_, p in zip(squares, ps)}
        ranks = []
        for r in range(7, -1, -1):
            row, empty = '', 0
            for f in range(8):
                c = board.get(r * 8 + f)
                if c is None:
                    empty += 1
                else:
                    row += (str(empty) if empty else '') + c
                    empty = 0
            ranks.append(row + (str(empty) if empty else ''))
        castling = ''.join(c for i, c in enumerate('KQkq') if flags & (2 << i)) or '-'
        black = flags & F_BLACK
        ep_sq = chr(97 + ep) + ('3' if black else '6') if ep is not None else '-'
        fen = f"{'/'.join(ranks)} {'b' if black else 'w'} {castling} {ep_sq}"
        uci = []
        for m in ms:
            a, b, c = m & 63, m >> 6 & 63, m >> 12
            uci.append(f"{chr(97 + a % 8)}{a // 8 + 1}{chr(97 + b % 8)}{b // 8 + 1}{['', 'n', 'b', 'r', 'q'][c]}")
        tags = {names[i] for i in range(n_tags) if mask >> i & 1}
        ok = (s == x.id and rating == x.rating and pop == x.pop and ' '.join(uci) == x.moves
              and ' '.join(x.fen.split()[:4]) == fen and tags == {t for t in x.tags if t not in DERIVED}
              and bool(flags & F_DAILY) == x.daily and rating >= prev)
        prev = rating
        bad += not ok
    return bad, daily


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default=os.path.join(root, '.cache/puzzles/lichess_db_puzzle.csv.zst'))
    ap.add_argument('--out', default=os.path.join(root, 'Scachs/Resources/puzzles.bin'))
    args = ap.parse_args()

    print('source', args.src, os.path.getsize(args.src), 'bytes')
    digest = hashlib.sha256()
    with open(args.src, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            digest.update(chunk)
    print('source sha256', digest.hexdigest())

    gc.disable()  # millions of small tuples and nothing cyclic
    stats, natural, natural_mate, seen_tags, freq = survey(args.src)
    print(dict(stats))
    print('tags in the CSV', len(seen_tags))
    print('natural mate share (non-equality)', round(sum(natural_mate.values()) / sum(natural.values()), 4))
    strict_rows, relaxed_rows, dailies = collect(args.src, freq)
    selected, report = select(strict_rows, relaxed_rows, dailies, natural, natural_mate, freq)
    tag_names = write_bin(selected, args.out)

    print('band quota got relaxed mate cap natural%')
    for band, b in sorted(report.items()):
        print(f"{band:5d} {b['quota']:5d} {b['got']:5d} {b['relaxed']:5d} {b['mate']:5d} {b['cap']:5d} {b['natural'] * 100:5.1f}")
    n = len(selected)
    print('selected', n, 'of total quota', sum(b['quota'] for b in report.values()))
    print('outside the bands, dropped:', sum(v for k, v in natural.items() if band_quota(k) == 0))
    print('avg popularity', round(sum(x.pop for x in selected) / n, 1), 'avg plays', round(sum(x.plays for x in selected) / n), 'relaxed', sum(x.relaxed for x in selected))
    print('plies', sorted(collections.Counter(x.moves.count(' ') + 1 for x in selected).items()))
    print('mate share', round(sum(x.mate for x in selected) / n, 4))
    counts = collections.Counter(t for x in selected for t in x.tags)
    print('tags stored', len(tag_names), 'of which seen in the CSV', len(set(tag_names) & set(seen_tags)))
    print('tags absent from the set:', sorted(set(seen_tags) - set(counts)))
    for t, c in counts.most_common():
        print(f'  {t:20s} {c:6d} {c / n * 100:5.1f}%')

    bad, daily = check_round_trip(selected, args.out)
    data = open(args.out, 'rb').read()
    print('round trip failures', bad, 'of', n)
    print('daily flagged', daily)
    print('puzzles.bin', len(data), 'bytes', round(len(data) / n, 2), 'B/puzzle')
    print('deflate level 9 (download stand-in)', len(zlib.compress(data, 9)), 'bytes')
    print('sha256', hashlib.sha256(data).hexdigest())
    if bad:
        sys.exit('round trip failed')


if __name__ == '__main__':
    main()
