#!/usr/bin/env python3
"""Checks Scachs/Resources/Lessons/*.json for chess truth with a real engine, and for text and schema rules.

usage: engine_check_lessons.py --stockfish PATH [--cache FILE] [--nodes 1000000] [--workers 8] [--static] [L01 L06 ...]

Rules enforced with the engine (nodes per search, default 1M):
  find, guided, test items  every accepted move is the engine's best or within 30 cp; goal.mate is met exactly.
                            In an opening lesson, watch and guided moves are theory and may lose up to 80 cp (gambits).
                            With goal.win, a move that stays at +300 or more passes and is printed as a note.
  find                      other moves within 30 cp of best must be listed in ok (ALT), except with goal win or draw,
                            where the runner asks the engine about unlisted moves
  bad                       the move loses at least 100 cp against best, and its reply is best or within 50 cp
  mate flags, # in text     the move really mates
Static rules: legal FENs and moves, shapes on real squares, tap answers against their rule, three languages,
no exclamation marks or long dashes, SAN named in the text exists in that step's positions.
Chess logic here is independent of Scachs/Chess/Position.swift on purpose, so the two cross-check each other.
"""
import argparse, json, os, queue, re, subprocess, sys, threading
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LESSONS = os.path.join(ROOT, "Scachs/Resources/Lessons")
LANGS = ("ca", "es", "en")

SYLLABUS = {
    "L01": (900, [], {"hangingPiece": 1}, "seeing"),
    "L02": (950, ["L01"], {"hangingPiece": .6, "defensiveMove": .3, "trappedPiece": .1}, "seeing"),
    "L03": (850, [], {"mateIn1": 1}, "seeing"),
    "L04": (1000, ["L03"], {"backRankMate": 1}, "seeing"),
    "L05": (1100, ["L03"], {"mateIn2": 1}, "seeing"),
    "L06": (1000, ["L01"], {"fork": 1}, "double"),
    "L07": (1150, ["L06"], {"fork": 1}, "double"),
    "L08": (1100, ["L01"], {"pin": 1}, "double"),
    "L09": (1250, ["L08"], {"pin": 1}, "double"),
    "L10": (1200, ["L08"], {"skewer": 1}, "double"),
    "L11": (1300, ["L08"], {"discoveredAttack": 1}, "double"),
    "L12": (1400, ["L11"], {"discoveredCheck": .7, "doubleCheck": .3}, "double"),
    "L13": (1400, ["L06"], {"capturingDefender": 1}, "obstacles"),
    "L14": (1450, ["L13"], {"deflection": 1}, "obstacles"),
    "L15": (1500, ["L14"], {"attraction": 1}, "obstacles"),
    "L16": (1350, ["L01"], {"trappedPiece": 1}, "obstacles"),
    "L17": (1350, ["L01"], {"advancedPawn": .5, "promotion": .45, "underPromotion": .05}, "obstacles"),
    "L18": (1650, ["L11"], {"intermezzo": 1}, "obstacles"),
    "L19": (1700, ["L11"], {"clearance": 1}, "obstacles"),
    "L20": (1750, ["L19"], {"interference": .5, "xRayAttack": .4, "collinearMove": .1}, "obstacles"),
    "L21": (1250, ["L03"], {"attackingF2F7": 1}, "attack"),
    "L22": (1300, ["L05"], {"smotheredMate": .35, "vukovicMate": .2, "arabianMate": .15, "cornerMate": .15, "hookMate": .15}, "attack"),
    "L23": (1350, ["L05"], {"epauletteMate": .3, "anastasiaMate": .15, "swallowstailMate": .15, "blindSwineMate": .1, "triangleMate": .1, "killBoxMate": .1, "dovetailMate": .1}, "attack"),
    "L24": (1400, ["L05"], {"operaMate": .3, "pillsburysMate": .3, "morphysMate": .15, "bodenMate": .1, "doubleBishopMate": .1, "balestraMate": .05}, "attack"),
    "L25": (1500, ["L21"], {"kingsideAttack": .6, "exposedKing": .25, "queensideAttack": .15}, "attack"),
    "L26": (1600, ["L25"], {"sacrifice": .8, "mateIn3": .2}, "attack"),
    "L27": (1550, ["L01"], {"defensiveMove": .95, "equality": .05}, "defence"),
    "L28": (1750, ["L26"], {"quietMove": 1}, "defence"),
    "R01": (700, [], {"opening": 1}, "rules"),
    "R02": (750, [], {"hangingPiece": 1}, "rules"),
    "R03": (800, [], {"endgame": 1}, "rules"),
    "O01": (800, [], {"opening": 1}, "openings"),
    "O02": (1000, [], {"opening": 1}, "openings"),
    "O03": (900, [], {"opening": 1}, "openings"),
    "O04": (850, [], {"opening": 1}, "openings"),
    "O05": (1100, [], {"opening": 1}, "openings"),
    "O06": (1000, [], {"opening": 1}, "openings"),
    "O07": (950, [], {"opening": 1}, "openings"),
    "O08": (900, [], {"opening": 1}, "openings"),
    "O09": (800, [], {"opening": 1}, "openings"),
    "O10": (1150, [], {"opening": 1}, "openings"),
    "O11": (950, [], {"opening": 1}, "openings"),
    "O12": (1150, [], {"opening": 1}, "openings"),
    "O13": (1000, [], {"opening": 1}, "openings"),
    "O14": (1500, [], {"opening": 1}, "openings"),
    "O15": (1400, [], {"opening": 1}, "openings"),
    "O16": (1100, [], {"opening": 1}, "openings"),
    "O17": (1200, [], {"opening": 1}, "openings"),
    "O18": (1500, [], {"opening": 1}, "openings"),
    "O19": (1700, [], {"opening": 1}, "openings"),
    "O20": (1300, [], {"opening": 1}, "openings"),
    "E01": (700, [], {"mate": 1}, "endgames"),
    "E02": (800, [], {"mate": 1}, "endgames"),
    "E03": (1000, [], {"pawnEndgame": 1}, "endgames"),
    "E04": (1300, [], {"rookEndgame": 1}, "endgames"),
    "E05": (1500, [], {"bishopEndgame": 0.5, "knightEndgame": 0.5}, "endgames"),
    "E06": (1700, [], {"queenEndgame": 1}, "endgames"),
    "M01": (1100, [], {"middlegame": 1}, "strategy"),
    "M02": (1250, [], {"middlegame": 1}, "strategy"),
    "M03": (1200, [], {"middlegame": 1}, "strategy"),
    "M04": (1400, [], {"middlegame": 1}, "strategy"),
    "M05": (1650, [], {"middlegame": 1}, "strategy"),
    "M06": (1800, [], {"middlegame": 1}, "strategy"),
    "A01": (1800, [], {"long": 1}, "mastery"),
    "A02": (1900, [], {"crushing": 1}, "mastery"),
    "A03": (1950, [], {"sacrifice": 1}, "mastery"),
    "A04": (2000, [], {"zugzwang": 1}, "mastery"),
    "A05": (2050, [], {"defensiveMove": 1}, "mastery"),
    "L29": (1300, [], {"pawnEndgame": .8, "zugzwang": .2}, "endgames"),
    "L30": (1500, ["L29"], {"rookEndgame": 1}, "endgames"),
}
HAND_TESTS = {"L02", "L29", "L30", "R01", "R02", "R03", "O01", "O02", "O03", "O04", "O05", "O06", "O07", "O08", "O09", "O10", "O11", "O12", "O13", "O14", "O15", "O16", "O17", "O18", "O19", "O20", "E01", "E02", "E03", "E04", "E05", "E06", "M01", "M02", "M03", "M04", "M05", "M06", "A01", "A02", "A03", "A04", "A05"}

# ---- chess core -------------------------------------------------------------
def sqn(s): return "abcdefgh"[s % 8] + str(s // 8 + 1)
def sq(n): return "abcdefgh".index(n[0]) + (int(n[1]) - 1) * 8
KN = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
KG = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
RD, BD = [(1, 0), (0, 1), (-1, 0), (0, -1)], [(1, 1), (-1, 1), (-1, -1), (1, -1)]

def on(f, r): return 0 <= f < 8 and 0 <= r < 8

class Pos:
    def __init__(s, fen):
        p = fen.split()
        s.b = [None] * 64
        for ri, row in enumerate(p[0].split("/")):
            f = 0
            for c in row:
                if c.isdigit(): f += int(c)
                else:
                    s.b[(7 - ri) * 8 + f] = c
                    f += 1
        s.stm = p[1]
        s.cr = p[2] if len(p) > 2 else "-"
        s.ep = sq(p[3]) if len(p) > 3 and p[3] != "-" else None
        s.hm = int(p[4]) if len(p) > 4 else 0
        s.fm = int(p[5]) if len(p) > 5 else 1

    def fen(s):
        rows = []
        for r in range(7, -1, -1):
            row, e = "", 0
            for f in range(8):
                c = s.b[r * 8 + f]
                if c is None: e += 1
                else:
                    if e: row += str(e); e = 0
                    row += c
            rows.append(row + (str(e) if e else ""))
        return f"{'/'.join(rows)} {s.stm} {s.cr} {sqn(s.ep) if s.ep is not None else '-'} {s.hm} {s.fm}"

    def key(s):  # the EPD fields only, so equal positions share engine results
        return " ".join(s.fen().split()[:4])

    def own(s, c, side): return c is not None and (c.isupper() == (side == "w"))
    def king(s, side):
        k = "K" if side == "w" else "k"
        return s.b.index(k) if k in s.b else None

    def attackers(s, t, by):
        out, tf, tr = [], t % 8, t // 8
        for d, kinds in ((RD, "RQ"), (BD, "BQ")):
            for df, dr in d:
                f, r = tf + df, tr + dr
                while on(f, r):
                    c = s.b[r * 8 + f]
                    if c is not None:
                        if s.own(c, by) and c.upper() in kinds: out.append(r * 8 + f)
                        break
                    f += df; r += dr
        for L, kind in ((KN, "N"), (KG, "K")):
            for df, dr in L:
                f, r = tf + df, tr + dr
                if on(f, r):
                    c = s.b[r * 8 + f]
                    if s.own(c, by) and c.upper() == kind: out.append(r * 8 + f)
        pr = tr - 1 if by == "w" else tr + 1
        for f in (tf - 1, tf + 1):
            if on(f, pr):
                c = s.b[pr * 8 + f]
                if s.own(c, by) and c.upper() == "P": out.append(pr * 8 + f)
        return out

    def in_check(s, side=None):
        side = side or s.stm
        k = s.king(side)
        return k is not None and bool(s.attackers(k, "b" if side == "w" else "w"))

    def pseudo(s):
        out, us = [], s.stm
        them = "b" if us == "w" else "w"
        for fr in range(64):
            c = s.b[fr]
            if not s.own(c, us): continue
            k, f, r = c.upper(), fr % 8, fr // 8
            if k == "P":
                d = 1 if us == "w" else -1
                last = 7 if us == "w" else 0
                def add(to):
                    if to // 8 == last: out.extend((fr, to, p) for p in "qrbn")
                    else: out.append((fr, to, None))
                if on(f, r + d) and s.b[(r + d) * 8 + f] is None:
                    add((r + d) * 8 + f)
                    if r == (1 if us == "w" else 6) and s.b[(r + 2 * d) * 8 + f] is None:
                        out.append((fr, (r + 2 * d) * 8 + f, None))
                for ff in (f - 1, f + 1):
                    if on(ff, r + d):
                        to = (r + d) * 8 + ff
                        if s.own(s.b[to], them) or to == s.ep: add(to)
            elif k in "NK":
                for df, dr in (KN if k == "N" else KG):
                    if on(f + df, r + dr) and not s.own(s.b[(r + dr) * 8 + f + df], us):
                        out.append((fr, (r + dr) * 8 + f + df, None))
            else:
                ds = (RD if k in "RQ" else []) + (BD if k in "BQ" else [])
                for df, dr in ds:
                    ff, rr = f + df, r + dr
                    while on(ff, rr):
                        to = rr * 8 + ff
                        if s.own(s.b[to], us): break
                        out.append((fr, to, None))
                        if s.b[to] is not None: break
                        ff += df; rr += dr
        back = 0 if us == "w" else 56
        if s.b[back + 4] == ("K" if us == "w" else "k") and not s.in_check(us):
            kc, qc = ("K", "Q") if us == "w" else ("k", "q")
            if kc in s.cr and s.b[back + 7] == ("R" if us == "w" else "r") and s.b[back + 5] is None and s.b[back + 6] is None \
                    and not s.attackers(back + 5, them) and not s.attackers(back + 6, them):
                out.append((back + 4, back + 6, None))
            if qc in s.cr and s.b[back] == ("R" if us == "w" else "r") and all(s.b[back + i] is None for i in (1, 2, 3)) \
                    and not s.attackers(back + 3, them) and not s.attackers(back + 2, them):
                out.append((back + 4, back + 2, None))
        return out

    def push(s, m):
        fr, to, pr = m
        n = Pos.__new__(Pos)
        n.b, n.stm, n.cr, n.ep = s.b[:], ("b" if s.stm == "w" else "w"), s.cr, None
        c = n.b[fr]
        cap = n.b[to] is not None
        n.b[to], n.b[fr] = c, None
        if c.upper() == "P":
            if to == s.ep: n.b[to + (-8 if s.stm == "w" else 8)] = None; cap = True
            if abs(to - fr) == 16: n.ep = (to + fr) // 2
            if pr: n.b[to] = pr.upper() if s.stm == "w" else pr
        if c.upper() == "K" and abs(to - fr) == 2:
            rf, rt = (fr + 3, fr + 1) if to > fr else (fr - 4, fr - 1)
            n.b[rt], n.b[rf] = n.b[rf], None
        for t, flag in ((0, "Q"), (7, "K"), (56, "q"), (63, "k")):
            if fr == t or to == t: n.cr = n.cr.replace(flag, "")
        if c == "K": n.cr = n.cr.replace("K", "").replace("Q", "")
        if c == "k": n.cr = n.cr.replace("k", "").replace("q", "")
        n.cr = n.cr or "-"
        n.hm = 0 if cap or c.upper() == "P" else s.hm + 1
        n.fm = s.fm + (1 if s.stm == "b" else 0)
        return n

    def moves(s):
        return [m for m in s.pseudo() if not s.push(m).in_check(s.stm)]

    def is_mate(s): return s.in_check() and not s.moves()
    def is_stalemate(s): return not s.in_check() and not s.moves()

    def parse(s, uci):
        m = (sq(uci[:2]), sq(uci[2:4]), uci[4] if len(uci) > 4 else None)
        return m if m in s.moves() else None

    def san(s, m):
        fr, to, pr = m
        c = s.b[fr].upper()
        if c == "K" and abs(to - fr) == 2: out = "O-O" if to > fr else "O-O-O"
        else:
            cap = s.b[to] is not None or (c == "P" and to == s.ep)
            if c == "P":
                out = (sqn(fr)[0] + "x" if cap else "") + sqn(to) + ("=" + pr.upper() if pr else "")
            else:
                others = [x for x in s.moves() if x[1] == to and x[0] != fr and s.b[x[0]].upper() == c]
                dis = ""
                if others:
                    if all(x[0] % 8 != fr % 8 for x in others): dis = sqn(fr)[0]
                    elif all(x[0] // 8 != fr // 8 for x in others): dis = sqn(fr)[1]
                    else: dis = sqn(fr)
                out = c + dis + ("x" if cap else "") + sqn(to)
        n = s.push(m)
        return out + ("#" if n.is_mate() else "+" if n.in_check() else "")

    def legal_fen_issue(s):
        for side in "wb":
            if s.b.count("K" if side == "w" else "k") != 1: return "needs one king per side"
        if s.in_check("b" if s.stm == "w" else "w"): return "side not to move is in check"
        if any(s.b[i] and s.b[i].upper() == "P" for i in list(range(8)) + list(range(56, 64))): return "pawn on back rank"
        if s.b.count("P") > 8 or s.b.count("p") > 8: return "too many pawns"
        for flag, kf, rf, k, r in (("K", 4, 7, "K", "R"), ("Q", 4, 0, "K", "R"), ("k", 60, 63, "k", "r"), ("q", 60, 56, "k", "r")):
            if flag in s.cr and (s.b[kf] != k or s.b[rf] != r): return "castling rights do not match"
        return None

    def pinned(s, side):
        them, k, out = ("b" if side == "w" else "w"), s.king(side), []
        for i in range(64):
            if s.own(s.b[i], side) and s.b[i].upper() != "K":
                t = Pos.__new__(Pos); t.b = s.b[:]; t.stm = s.stm; t.cr = "-"; t.ep = None; t.hm = 0; t.fm = 1
                before = len(s.attackers(k, them))
                t.b[i] = None
                if len(t.attackers(k, them)) > before: out.append(i)
        return out

# ---- tap rules: each returns the set of squares the rule says are right ----
def key_squares(pawn, side):
    f, r, d = pawn % 8, pawn // 8, 1 if side == "w" else -1
    rel = r if side == "w" else 7 - r  # 0-based relative rank
    ranks = [r + 2 * d] if rel <= 3 else [r + d, r + 2 * d]
    if f in (0, 7):  # rook pawn: the two squares on the next file in, level with and past the seventh
        ff = 1 if f == 0 else 6
        return {(7 if side == "w" else 0) * 8 + ff, (6 if side == "w" else 1) * 8 + ff}
    return {rr * 8 + ff for rr in ranks for ff in (f - 1, f, f + 1) if 0 <= rr < 8}

def knight_from(t):
    return {(t // 8 + dr) * 8 + t % 8 + df for df, dr in KN if on(t % 8 + df, t // 8 + dr)}

def tap_rule(p, rule):
    kind = rule["rule"]
    if kind == "knightFork":
        ts = [knight_from(sq(t)) for t in rule["targets"]]
        return set.intersection(*ts)
    if kind == "attackers": return set(p.attackers(sq(rule["of"]), rule["by"]))
    if kind == "loose":
        side = rule["side"]; them = "b" if side == "w" else "w"
        return {i for i in range(64) if p.own(p.b[i], side) and p.b[i].upper() not in "KP" and not p.attackers(i, side)
                and (not rule.get("attacked") or p.attackers(i, them))}
    if kind == "mateSquares": return {m[1] for m in p.moves() if p.push(m).is_mate()}
    if kind == "checks":
        fr = sq(rule["from"]) if "from" in rule else None
        return {m[1] for m in p.moves() if (fr is None or m[0] == fr) and p.push(m).in_check()}
    if kind == "pinned": return set(p.pinned(rule["side"]))
    if kind == "keySquares": return key_squares(sq(rule["pawn"]), rule["side"])
    if kind == "dests": return {m[1] for m in p.moves() if m[0] == sq(rule["from"])}
    if kind == "forkSquares":
        fr, targets, out = sq(rule["from"]), [sq(t) for t in rule["targets"]], set()
        for m in p.moves():
            if m[0] == fr:
                n = p.push(m)
                if all(m[1] in n.attackers(t, p.stm) for t in targets): out.add(m[1])
        return out
    raise ValueError(f"unknown tap rule {kind}")

# ---- engine -----------------------------------------------------------------
class Engine:
    def __init__(s, path):
        s.p = subprocess.Popen([path], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        s.send("uci"); s.until("uciok")
        s.send("setoption name Threads value 1"); s.send("setoption name Hash value 128")
        s.send("isready"); s.until("readyok")

    def send(s, t): s.p.stdin.write(t + "\n"); s.p.stdin.flush()
    def until(s, tok):
        while True:
            line = s.p.stdout.readline()
            if line.startswith(tok): return line

    def search(s, fen, moves, multipv, nodes):
        s.send("ucinewgame"); s.send(f"setoption name MultiPV value {multipv}")
        s.send("isready"); s.until("readyok")
        s.send(f"position fen {fen}")
        s.send(f"go nodes {nodes}" + (" searchmoves " + " ".join(moves) if moves else ""))
        lines = {}
        while True:
            line = s.p.stdout.readline().split()
            if not line: raise RuntimeError("engine died")
            if line[0] == "bestmove": break
            if line[0] == "info" and "multipv" in line and "score" in line and "pv" in line:
                i = line.index("score")
                if line[i + 2] in ("lowerbound", "upperbound") or line[i + 3:i + 4] in (["lowerbound"], ["upperbound"]): continue
                v = (30000 - int(line[i + 2]) if int(line[i + 2]) > 0 else -30000 - int(line[i + 2])) if line[i + 1] == "mate" else int(line[i + 2])
                lines[int(line[line.index("multipv") + 1])] = {"v": v, "m": int(line[i + 2]) if line[i + 1] == "mate" else None,
                    "depth": int(line[line.index("depth") + 1]), "move": line[line.index("pv") + 1], "pv": line[line.index("pv") + 1:][:12]}
        return [lines[k] for k in sorted(lines)]

class Oracle:
    def __init__(s, path, nodes, workers, cache):
        s.path, s.nodes, s.cachefile, s.lock = path, nodes, cache, threading.Lock()
        s.cache = json.load(open(cache)) if cache and os.path.exists(cache) else {}
        s.pool, s.made, s.workers = queue.Queue(), 0, workers
        s.mindepth, s.searches = 999, 0

    def search(s, fen, moves=None, multipv=1):
        key = f"{fen}|{','.join(sorted(moves or []))}|{multipv}|{s.nodes}"
        with s.lock:
            if key in s.cache:
                return s.cache[key]
            need_new = s.pool.empty() and s.made < s.workers
            if need_new: s.made += 1
        e = Engine(s.path) if need_new else s.pool.get()
        try:
            r = e.search(fen, moves, multipv, s.nodes)
        finally:
            s.pool.put(e)
        with s.lock:
            s.cache[key] = r
            s.searches += 1
        return r

    def save(s):
        if s.cachefile:
            with open(s.cachefile, "w") as f: json.dump(s.cache, f)

def fmt(v):
    if v > 25000: return f"#{30000 - v}"
    if v < -25000: return f"#-{30000 + v}"
    return f"{v:+d}"

# ---- text rules -------------------------------------------------------------
SAN_RE = re.compile(r"(?<![\w-])(O-O-O|O-O|[KQRBN][a-h1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?|[a-h]x[a-h][1-8](?:=[QRBN])?[+#]?|[a-h][1-8]=[QRBN][+#]?|[a-h][1-8][+#])(?![\w])")
BANNED = {"ca": [r"\breina\b", r"\bhorquilla\b", r"\bforca\b", r"\bmate\b", r"\benroque\b", r"\bcaball\b", r"\bpeon\b"],
          "es": [r"\breina\b", r"\bforquilla\b", r"\bcavall\b"],
          "en": []}

def text_values(step):
    for k in ("say", "after", "name"):
        if k in step: yield k, step[k]
    for h in step.get("hints", []):
        if "say" in h: yield "hint", h["say"]
    for u, b in (step.get("bad") or {}).items():
        if "say" in b: yield f"bad {u}", b["say"]
    for n, o in enumerate(step.get("options", [])):
        yield f"option{n + 1}", o
    for it in step.get("items", []):
        yield from text_values(it)

def check_text(step, where, err, warn):
    for label, t in text_values(step):
        for lang in LANGS:
            if not t.get(lang, "").strip():
                err(f"{where} {label}: missing {lang}")
                continue
            x = t[lang]
            if "!" in x or "¡" in x: err(f"{where} {label} {lang}: exclamation mark")
            if "—" in x or "–" in x: err(f"{where} {label} {lang}: long dash")
            if x.count('"'): warn(f"{where} {label} {lang}: straight quote")
            for b in BANNED[lang]:
                if re.search(b, x, re.I): err(f"{where} {label} {lang}: banned word {b}")
            n = len(re.findall(r"[.?…:](?:\s|$)", x))
            if label in ("say", "after") and n > 3: warn(f"{where} {label} {lang}: {n} sentences")
            if label in ("say", "after") and len(x.split()) > 45: warn(f"{where} {label} {lang}: {len(x.split())} words")
        toks = {lang: sorted(SAN_RE.findall(t.get(lang, ""))) for lang in LANGS}
        if not (toks["ca"] == toks["es"] == toks["en"]):
            err(f"{where} {label}: SAN differs across languages {toks}")
        if len(set(t.get(l) for l in LANGS)) < 3:
            warn(f"{where} {label}: identical text across languages")

def san_tokens(step):
    out = set()
    for _, t in text_values(step):
        out.update(SAN_RE.findall(t.get("en", "")))
    return out

# ---- lesson walk -----------------------------------------------------------
class R:
    def __init__(s, lid): s.lid, s.errors, s.warns, s.notes, s.stats = lid, [], [], [], {"find": 0, "guided": 0, "bad": 0, "mate": 0, "tap": 0, "tap_rule": 0, "watch": 0, "items": 0}
    def err(s, m): s.errors.append(m)
    def warn(s, m): s.warns.append(m)

def check_shapes(step, p, where, r):
    for sh in step.get("draw", []) or []:
        if not re.fullmatch(r"[GRYB][a-h][1-8]([a-h][1-8])?", sh): r.err(f"{where}: bad shape {sh}")

def apply_uci(p, uci, where, r):
    m = p.parse(uci)
    if not m:
        r.err(f"{where}: illegal {uci} in {p.fen()}")
        return None
    return p.push(m)

def engine_move_checks(p, ok, step, where, r, o):
    """Accepted moves are best or within 30 cp; bad moves are really worse and their reply is a real refutation."""
    fen = p.fen()
    best = o.search(fen)[0]
    o.mindepth = min(o.mindepth, best["depth"])
    goal = step.get("goal") or {}
    for u in ok:
        s_ = o.search(fen, [u])[0]
        loss = 0 if u == best["move"] else best["v"] - s_["v"]  # same move: two searches differ only by noise
        if loss > (80 if step.get("book") else 30):
            # Won endings the engine cannot finish without tablebases give noisy scores in the hundreds: keeping the win is the test.
            if goal.get("win") and s_["v"] >= 300:
                r.notes.append(f"{where}: {u} {fmt(s_['v'])} keeps the win, best {best['move']} {fmt(best['v'])}")
            else:
                r.err(f"{where}: {u} scores {fmt(s_['v'])}, best {best['move']} {fmt(best['v'])} (loss {loss})")
        if "mate" in goal and not (s_["m"] and 0 < s_["m"] <= goal["mate"]):
            r.err(f"{where}: {u} claims mate in {goal['mate']} but engine says {fmt(s_['v'])}")
        if goal.get("win") and s_["v"] < 300: r.err(f"{where}: {u} claims a win but engine says {fmt(s_['v'])}")
        if goal.get("draw") and abs(s_["v"]) > 60: r.err(f"{where}: {u} claims a draw but engine says {fmt(s_['v'])}")
    return best

def check_alternatives(p, ok, bad, where, r, o, best):
    fen = p.fen()
    for line in o.search(fen, None, 5):
        u = line["move"]
        if u not in ok and best["v"] - line["v"] <= 30:
            if u in bad: r.err(f"{where}: bad move {u} is as good as best ({fmt(line['v'])} vs {fmt(best['v'])})")
            else: r.warn(f"{where}: ALT {u} {fmt(line['v'])} within 30 cp of best {fmt(best['v'])}, not in ok")

def check_bad(p, bad, where, r, o, best):
    fen = p.fen()
    for u, b in bad.items():
        r.stats["bad"] += 1
        n = apply_uci(p, u, f"{where} bad", r)
        if n is None: continue
        s_ = o.search(fen, [u])[0]
        if best["v"] - s_["v"] < 100:
            r.err(f"{where}: bad {u} only loses {best['v'] - s_['v']} cp ({fmt(s_['v'])} vs {fmt(best['v'])})")
        rep = b.get("reply")
        if rep is None:
            if n.moves(): r.warn(f"{where}: bad {u} has no reply")
            continue
        m = n.parse(rep)
        if not m:
            r.err(f"{where}: bad {u} reply {rep} illegal")
            continue
        rb = o.search(n.fen())[0]
        rs = o.search(n.fen(), [rep])[0]
        if rep != rb["move"] and rb["v"] - rs["v"] > 50:
            r.err(f"{where}: bad {u} reply {rep} {fmt(rs['v'])}, engine prefers {rb['move']} {fmt(rb['v'])}")

def check_reply(n, rep, where, r, o):
    if not rep: return
    rb = o.search(n.fen())[0]
    rs = o.search(n.fen(), [rep])[0]
    if rb["v"] - rs["v"] > 50 and rb["v"] > -600:
        r.warn(f"{where}: reply {rep} {fmt(rs['v'])}, defence {rb['move']} is better {fmt(rb['v'])}")

def check_san_in_text(step, positions, where, r):
    table = {}
    for p in positions:
        for m in p.moves():
            s_ = p.san(m)
            table.setdefault(s_.rstrip("+#"), set()).add(s_)
    for tok in san_tokens(step):
        base = tok.rstrip("+#")
        if base not in table:
            r.warn(f"{where}: text names {tok}, not legal in this step's positions")
        elif tok != base and tok not in table[base]:
            r.err(f"{where}: text says {tok}, the move is {sorted(table[base])}")
        elif tok == base and all(x != base for x in table[base]):
            r.warn(f"{where}: text says {tok} without suffix, the move is {sorted(table[base])}")

def check_move_step(step, p, ok, where, r, o):
    """Shared by find, guided and hand-written test items. Returns the position after ok[0] and its reply."""
    if not p.moves():
        r.err(f"{where}: no legal moves")
        return None
    bad = step.get("bad") or {}
    if set(ok) & set(bad): r.err(f"{where}: move both ok and bad")
    n = None
    for i, u in enumerate(ok):
        x = apply_uci(p, u, where, r)
        if i == 0: n = x
    if n is None: return None
    if o:
        best = engine_move_checks(p, ok, step, where, r, o)
        goal = step.get("goal") or {}
        if step.get("t") != "guided" and not (goal.get("win") or goal.get("draw")):  # with these the runner asks the engine
            check_alternatives(p, ok, bad, where, r, o, best)
        check_bad(p, bad, where, r, o, best)
    else:
        for u, b in bad.items():
            x = apply_uci(p, u, f"{where} bad", r)
            if x is not None and b.get("reply"): apply_uci(x, b["reply"], f"{where} bad reply", r)
    if step.get("mate") and not n.is_mate(): r.err(f"{where}: flagged mate but {ok[0]} does not mate")
    if "mate" in (step.get("goal") or {}): r.stats["mate"] += 1
    rep = step.get("reply")
    if rep:
        if n.is_mate(): r.err(f"{where}: reply after mate")
        if o: check_reply(n, rep, where, r, o)
        return apply_uci(n, rep, f"{where} reply", r)
    return n

def check_lesson(path, o):
    d = json.load(open(path))
    lid = d.get("id", os.path.basename(path)[:3])
    r = R(lid)
    syl = SYLLABUS.get(lid)
    for k in ("v", "id", "title", "min", "c", "requires", "tags", "section", "steps", "review"):
        if k not in d: r.err(f"missing {k}")
    if r.errors: return r
    if syl:
        if d["c"] != syl[0]: r.err(f"c {d['c']} != {syl[0]}")
        if d["requires"] != syl[1]: r.err(f"requires {d['requires']} != {syl[1]}")
        if d["tags"] != syl[2]: r.err(f"tags {d['tags']} != {syl[2]}")
        if d["section"] != syl[3]: r.err(f"section {d['section']} != {syl[3]}")
    if not (3 <= d["min"] <= 5): r.err(f"min {d['min']}")
    if not (7 <= len(d["steps"]) <= 14): r.err(f"{len(d['steps'])} steps")
    if d["review"] != {"days": [1, 3, 7], "n": 2}: r.err("review must be days 1,3,7 n 2")
    kinds = [s.get("t") for s in d["steps"]]
    if kinds[-2:] != ["test", "recap"]: r.err(f"must end test, recap: {kinds[-2:]}")
    if "find" not in kinds: r.err("no find step")
    if "find" in kinds and kinds.index("find") < 2: r.warn("find before shown and guided steps")
    if "guided" not in kinds: r.warn("no guided step")
    for lang in LANGS:
        if not d["title"].get(lang): r.err(f"title missing {lang}")
    fens, cur = set(), None
    for i, step in enumerate(d["steps"]):
        t, where = step.get("t"), f"{lid} step{i + 1} {step.get('t')}"
        if d.get("section") == "openings" and t in ("watch", "guided"): step = dict(step, book=True)
        if t not in ("explain", "watch", "guided", "find", "tap", "choose", "recap", "test"):
            r.err(f"{where}: unknown step type")
            continue
        check_text(step, where, r.err, r.warn)
        if t in ("explain", "watch", "guided", "find", "tap", "choose", "recap") and "say" not in step: r.err(f"{where}: needs say")
        if t == "test":
            check_test(step, d, where, r, o)
            continue
        if "fen" in step:
            try:
                cur = Pos(step["fen"])
                if cur.fen().split()[:4] != step["fen"].split()[:4]: r.warn(f"{where}: FEN not canonical")
                issue = cur.legal_fen_issue()
                if issue: r.err(f"{where}: {issue}: {step['fen']}")
                fens.add(step["fen"].split()[0])
            except Exception as e:
                r.err(f"{where}: bad FEN {step['fen']} ({e})")
                cur = None
        if cur is None:
            r.err(f"{where}: no position")
            continue
        check_shapes(step, cur, where, r)
        for h in step.get("hints", []):
            check_shapes(h, cur, where, r)
        before = cur
        seen = [cur]
        if t == "watch":
            r.stats["watch"] += 1
            for j, u in enumerate(step.get("line", [])):
                nx = apply_uci(cur, u, f"{where} line[{j}]", r)
                if nx is None: break
                if o:
                    best = o.search(cur.fen())[0]
                    s_ = o.search(cur.fen(), [u])[0]
                    allowed = step.get("shows", {}).get("mistakeAt")
                    if allowed == j:
                        if best["v"] - s_["v"] < 100: r.err(f"{where}: line[{j}] {u} shown as a mistake but only loses {best['v'] - s_['v']}")
                    elif u != best["move"] and best["v"] - s_["v"] > (80 if step.get("book") else 50) and best["v"] > -600:
                        if (step.get("goal") or {}).get("win") and s_["v"] >= 300:
                            r.notes.append(f"{where}: line[{j}] {u} {fmt(s_['v'])} keeps the win, best {best['move']} {fmt(best['v'])}")
                        else:
                            r.err(f"{where}: line[{j}] {u} {fmt(s_['v'])}, best {best['move']} {fmt(best['v'])}")
                cur = nx
                seen.append(cur)
            if step.get("mate") and not cur.is_mate(): r.err(f"{where}: flagged mate, line does not mate")
            if step.get("mate"): r.stats["mate"] += 1
        elif t == "guided":
            r.stats["guided"] += 1
            nx = check_move_step(step, cur, [step.get("uci", "")], where, r, o) if step.get("uci") else None
            if nx is None: r.err(f"{where}: no result")
            else: cur = nx; seen.append(cur)
        elif t == "find":
            r.stats["find"] += 1
            ok = step.get("ok") or []
            if not ok: r.err(f"{where}: empty ok")
            nx = check_move_step(step, cur, ok, where, r, o)
            if len(ok) > 1 and i + 1 < len(d["steps"]) and "fen" not in d["steps"][i + 1] and d["steps"][i + 1].get("t") != "test":
                r.err(f"{where}: several ok moves, so the next step needs its own fen")
            if nx is None: r.err(f"{where}: no result")
            else: cur = nx; seen.append(cur)
            for u in (step.get("bad") or {}):
                x = before.parse(u)
                if x: seen.append(before.push(x))
        elif t == "tap":
            r.stats["tap"] += 1
            want = {sq(x) for x in step.get("squares", [])}
            if not want: r.err(f"{where}: no squares")
            if "rule" in step:
                r.stats["tap_rule"] += 1
                got = tap_rule(cur, step["rule"])
                if got != want:
                    r.err(f"{where}: squares {sorted(sqn(x) for x in want)} but rule gives {sorted(sqn(x) for x in got)}")
            else:
                r.warn(f"{where}: tap without a rule")
        elif t == "choose":
            opts = step.get("options") or []
            if not 2 <= len(opts) <= 4: r.err(f"{where}: {len(opts)} options")
            if not isinstance(step.get("answer"), int) or not 0 <= step["answer"] < len(opts): r.err(f"{where}: answer out of range")
            if "after" not in step: r.err(f"{where}: needs after")
        elif t == "recap":
            if "card" not in step or "name" not in step: r.err(f"{where}: needs card and name")
        check_san_in_text(step, seen + ([Pos(d['steps'][i + 1]['fen'])] if i + 1 < len(d['steps']) and 'fen' in d['steps'][i + 1] else []), where, r)
    if len(fens) < 3: r.warn(f"only {len(fens)} distinct positions")
    return r

VOCAB = set(("opening middlegame endgame rookEndgame bishopEndgame knightEndgame queenEndgame pawnEndgame queenRookEndgame advancedPawn attackingF2F7 "
    "capturingDefender discoveredAttack doubleCheck exposedKing fork hangingPiece kingsideAttack queensideAttack pin sacrifice skewer trappedPiece attraction "
    "clearance collinearMove discoveredCheck defensiveMove deflection interference intermezzo quietMove xRayAttack zugzwang mate mateIn1 mateIn2 mateIn3 mateIn4 "
    "mateIn5 arabianMate cornerMate hookMate smotheredMate vukovicMate anastasiaMate backRankMate blindSwineMate dovetailMate epauletteMate killBoxMate "
    "swallowstailMate triangleMate balestraMate bodenMate doubleBishopMate pillsburysMate morphysMate operaMate castling enPassant promotion underPromotion "
    "equality advantage crushing oneMove short long veryLong master masterVsMaster superGM").split())

def check_test(step, d, where, r, o):
    lid = d["id"]
    if not step.get("n") or not step.get("pass"): r.err(f"{where}: needs n and pass")
    if "items" in step:
        if lid not in HAND_TESTS: r.warn(f"{where}: hand-written test in a query lesson")
        items = step["items"]
        if len(items) < step.get("n", 0): r.err(f"{where}: fewer items than n")
        if not any(it.get("decoy") for it in items): r.err(f"{where}: no decoy")
        for j, it in enumerate(items):
            r.stats["items"] += 1
            w = f"{where} item{j + 1}"
            p = Pos(it["fen"])
            issue = p.legal_fen_issue()
            if issue: r.err(f"{w}: {issue}")
            n = check_move_step(it, p, it.get("ok") or [], w, r, o)
            if n is None: r.err(f"{w}: no result")
    else:
        if lid in HAND_TESTS: r.err(f"{where}: {lid} needs hand-written items")
        q = step.get("query") or {}
        if not q.get("any"): r.err(f"{where}: query needs any")
        for tag in q.get("any", []):
            if tag not in VOCAB: r.err(f"{where}: unknown tag {tag}")
        if "maxPlies" not in q or "gap" not in q: r.err(f"{where}: query needs maxPlies and gap")
        if step.get("decoys", 0) < 1: r.err(f"{where}: needs a decoy")
    if step.get("pass", 0) > step.get("n", 0): r.err(f"{where}: pass > n")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stockfish"); ap.add_argument("--cache"); ap.add_argument("--nodes", type=int, default=1000000)
    ap.add_argument("--workers", type=int, default=8); ap.add_argument("--static", action="store_true")
    ap.add_argument("--dir", default=LESSONS); ap.add_argument("ids", nargs="*")
    a = ap.parse_args()
    o = None if a.static else Oracle(a.stockfish, a.nodes, a.workers, a.cache)
    ids = a.ids or sorted(f[:-5] for f in os.listdir(a.dir) if re.fullmatch(r"L\d\d\.json", f))
    def run(i):
        try:
            return check_lesson(os.path.join(a.dir, i + ".json"), o)
        except Exception as e:
            x = R(i); x.err(f"crash: {e!r}"); return x
    with ThreadPoolExecutor(a.workers) as ex:
        results = list(ex.map(run, ids))
    if o: o.save()
    tot, nerr, nwarn = {}, 0, 0
    for r in results:
        for k, v in r.stats.items(): tot[k] = tot.get(k, 0) + v
        nerr += len(r.errors); nwarn += len(r.warns)
        for m in r.errors: print("FAIL", m)
        for m in r.warns: print("warn", m)
        for m in r.notes: print("note", m)
    print(f"{len(results)} lessons, {nerr} failures, {nwarn} warnings; {tot}" + (f"; engine: {o.searches} new searches, min depth {o.mindepth}" if o else "; static only"))
    sys.exit(1 if nerr else 0)

if __name__ == "__main__":
    main()
