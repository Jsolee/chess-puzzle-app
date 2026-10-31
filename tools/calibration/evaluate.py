#!/usr/bin/env python3
"""Evaluates sampled positions with Stockfish at the app's first-pass budget.
usage: evaluate.py --stockfish PATH --net PATH --workers 6 positions.tsv evals.tsv
Appends to evals.tsv and skips lines already there, so it can be stopped and resumed.
Output adds, from the record's point of view, the score as cp or mate (columns: ...input..., kind, value)."""
import argparse, os, queue, subprocess, sys, threading, time

ap = argparse.ArgumentParser()
ap.add_argument('--stockfish', required=True); ap.add_argument('--net', required=True)
ap.add_argument('--workers', type=int, default=6); ap.add_argument('--nodes', type=int, default=150000)
ap.add_argument('positions'); ap.add_argument('evals')
a = ap.parse_args()

done = set()
if os.path.exists(a.evals):
    with open(a.evals) as f:
        for line in f: done.add(line.split('\t')[0] + '|' + line.split('\t')[1])
todo = queue.Queue()
total = 0
with open(a.positions) as f:
    for line in f:
        parts = line.rstrip('\n').split('\t')
        if parts[0] + '|' + parts[1] not in done:
            todo.put(parts); total += 1
print(f'{total} to evaluate, {len(done)} already done', flush=True)
lock = threading.Lock()
out = open(a.evals, 'a')
count = [0]
start = time.time()

def worker():
    p = subprocess.Popen([a.stockfish], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
    def send(s): p.stdin.write(s + '\n'); p.stdin.flush()
    def until(word):
        while True:
            line = p.stdout.readline()
            if not line: raise RuntimeError('engine exited')
            if line.startswith(word): return line
    send('uci'); until('uciok')
    send(f'setoption name EvalFile value {a.net}'); send('setoption name Threads value 1'); send('setoption name Hash value 16')
    send('isready'); until('readyok')
    while True:
        try: parts = todo.get_nowait()
        except queue.Empty: break
        fen, view = parts[0], parts[1]
        send('ucinewgame'); send(f'position fen {fen}'); send(f'go nodes {a.nodes}')
        kind, value = None, None
        while True:
            line = p.stdout.readline()
            if line.startswith('bestmove'): break
            if ' score ' in line:
                t = line.split()
                i = t.index('score')
                kind, value = t[i + 1], int(t[i + 2])
        stm = fen.split()[1]
        if stm != view: value = -value
        with lock:
            out.write('\t'.join(parts + [kind, str(value)]) + '\n'); out.flush()
            count[0] += 1
            if count[0] % 500 == 0:
                print(f'{count[0]}/{total}  {count[0] / (time.time() - start):.1f}/s', flush=True)
    send('quit')

threads = [threading.Thread(target=worker) for _ in range(a.workers)]
for t in threads: t.start()
for t in threads: t.join()
print('done', count[0], flush=True)
