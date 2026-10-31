#!/usr/bin/env python3
"""Builds Scachs/Resources/tag_frequency.json, the f_t(R) table the Recommender reads.

usage: gen_tag_frequency.py [--rows 1500000]

Uses the natural pool, not the curated puzzles.bin: the curated set flattens the motif mix (fork falls from 16.6% to
8.3% at 1300), and a table built from it would undervalue the common motifs. Pool filter matches the research
simulation: popularity >= 85, RD <= 95, plays >= 100, plies <= 8. IDs are random with respect to content, so the first
rows of the file are a fair sample. For a band b the frequency is the share of puzzles rated b-200..b+200 with the tag.
"""
import argparse, bisect, collections, csv, json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from engine_check_lessons import ROOT, SYLLABUS

CURRICULUM = sorted({t for s in SYLLABUS.values() for t in s[2]})
SOURCE = os.path.join(ROOT, ".cache/puzzles/lichess_db_puzzle.csv.zst")
OUT = os.path.join(ROOT, "Scachs/Resources/tag_frequency.json")

ap = argparse.ArgumentParser()
ap.add_argument("--rows", type=int, default=1500000)
args = ap.parse_args()

proc = subprocess.Popen(["zstd", "-dc", SOURCE], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
rows, seen = [], 0
reader = csv.DictReader(proc.stdout)
for x in reader:
    seen += 1
    if seen > args.rows:
        break
    if int(x["Popularity"]) < 85 or int(x["RatingDeviation"]) > 95 or int(x["NbPlays"]) < 100 or len(x["Moves"].split()) > 8:
        continue
    rows.append((int(x["Rating"]), x["Themes"].split()))
proc.kill()
rows.sort(key=lambda a: a[0])
ratings = [a[0] for a in rows]

bands = list(range(400, 2900, 100))
freq = {t: [] for t in CURRICULUM}
for b in bands:
    i, j = bisect.bisect_left(ratings, b - 200), bisect.bisect_right(ratings, b + 200)
    c = collections.Counter(t for a in rows[i:j] for t in a[1])
    n = max(1, j - i)
    for t in CURRICULUM:
        freq[t].append(round(c[t] / n, 5))

with open(OUT, "w") as f:
    json.dump({"source": "lichess_db_puzzle.csv.zst natural pool (CC0), popularity>=85 rd<=95 plays>=100 plies<=8",
               "rowsRead": seen - 1, "poolRows": len(rows), "window": 200, "bands": bands, "freq": freq}, f, separators=(",", ":"))
print(f"{seen - 1} rows read, pool {len(rows)}, wrote {OUT}")
