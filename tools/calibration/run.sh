#!/bin/bash
# Refits ExpectedPoints.kTable. Method and last results: docs/CALIBRATION.md.
# Streams at most MAX_BYTES of one Lichess dump (CC0) and stops as soon as the quotas are met. Nothing decompressed is stored.
# Each stage reuses its output in .cache/calibration; delete a file there to redo that stage. Evaluation resumes.
set -eu
cd "$(dirname "$0")/../.."

DUMP=${DUMP:-https://database.lichess.org/standard/lichess_db_standard_rated_2026-09.pgn.zst}
MAX_BYTES=${MAX_BYTES:-1000000000}
PER_BAND=${PER_BAND:-5000}
WORKERS=${WORKERS:-4}
NET=Scachs/Resources/nn-1a298aa575a0.nnue
OUT=.cache/calibration
mkdir -p "$OUT"

python3 -I tools/calibration/fit.py --check

if [ ! -x "$OUT/stockfish" ]; then
    rm -rf "$OUT/sf"
    cp -R Engine/Stockfish "$OUT/sf"
    # `all`, not `build`: that one needs ../scripts/net.sh, which isn't vendored. The net gets embedded, so it must be here.
    cp "$NET" "$OUT/sf/src/"
    make -C "$OUT/sf/src" -j"$WORKERS" all ARCH=apple-silicon > "$OUT/build.log" 2>&1
    cp "$OUT/sf/src/stockfish" "$OUT/stockfish"
    rm -rf "$OUT/sf"
fi

if [ ! -s "$OUT/positions.tsv" ]; then
    xcrun swiftc -O Scachs/Chess/Position.swift Scachs/Chess/PGN.swift tools/calibration/main.swift -o "$OUT/sample"
    # No pipefail: the sampler closing the pipe early is the normal way out, and it reports its own counts.
    curl -sS -r "0-$((MAX_BYTES - 1))" "$DUMP" | zstd -dc 2>/dev/null | "$OUT/sample" --per-band "$PER_BAND" > "$OUT/positions.tsv"
fi

python3 -I tools/calibration/evaluate.py --stockfish "$OUT/stockfish" --net "$NET" --workers "$WORKERS" "$OUT/positions.tsv" "$OUT/evals.tsv"
python3 -I tools/calibration/fit.py "$OUT/evals.tsv" | tee "$OUT/fit.txt"
