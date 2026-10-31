# Expected-points calibration

`ExpectedPoints.kTable` in `Scachs/Review/Classifier.swift` sets how fast a score in centipawns turns into expected points: `EP = 1 / (1 + exp(-k * cp))`, with `k` read off the table at the mover's rating. The class names and the loss bands (0.02, 0.05, 0.10, 0.20) are the ones chess.com publishes. The curve is ours, fitted on Lichess games, so our labels are not chess.com's and nothing may say they are.

Rerun with `tools/calibration/run.sh`. Each stage keeps its output in `.cache/calibration`.

## Data

- Source: `lichess_db_standard_rated_2026-09.pgn.zst` from database.lichess.org (CC0), streamed. It reads at most 1 GB and stops when the quotas are met, here after 1,016,588 games. Nothing decompressed is stored. No chess.com data: its User Agreement bars harvesting it for this.
- Games: rated blitz, rapid and classical from the normal start, players within 100 points of each other, 24 plies or more.
- Positions: 50,000 from 37,365 games, 5,000 for each 200-point band from 600 to 2400+. At most two per game, 20 plies apart, from ply 12 on. Half are seen from the side to move and half from the other side, since the app asks for both.
- Evaluation: Stockfish 19 built from `Engine/Stockfish/src`, `nn-1a298aa575a0.nnue`, 150,000 nodes as in the first review pass, one thread, fresh hash. No embedded `%eval`: old dumps mix Stockfish scales.
- Fit: maximum likelihood per band against the game result, a draw counting 0.5, cp clamped at the app's 1000. 80% of games to fit, 20% held out by game.
- Left out: 1,717 mate scores, and 11,160 positions from games lost on time. A label judges the board, and in those games the board barely predicts the result (k about 0.0005 in every band). This is a judgement call: leaving them in lowers k by 20 to 30%.

## Result

| Band | Median rating | k (table) | 95% interval | Previous k |
|---|---|---|---|---|
| 600+ | 733 | 0.00159 | 0.00147 to 0.00172 | 0.00332 |
| 800+ | 927 | 0.00183 | 0.00167 to 0.00199 | 0.00370 |
| 1000+ | 1113 | 0.00195 | 0.00179 to 0.00210 | 0.00407 |
| 1200+ | 1309 | 0.00207 | 0.00185 to 0.00225 | 0.00445 |
| 1400+ | 1505 | 0.00214 | 0.00192 to 0.00232 | 0.00484 |
| 1600+ | 1697 | 0.00238 | 0.00217 to 0.00256 | 0.00522 |
| 1800+ | 1889 | 0.00259 | 0.00239 to 0.00285 | 0.00559 |
| 2000+ | 2077 | 0.00296 | 0.00269 to 0.00324 | 0.00596 |
| 2200+ | 2267 | 0.00361 | 0.00325 to 0.00399 | 0.00634 |
| 2400+ | 2489 | 0.00389 | 0.00351 to 0.00432 | 0.00640 |

Fit error on the 7,398 held-out positions, games lost on time excluded:

| | Log loss | Mean gap, predicted to actual score |
|---|---|---|
| This table | 0.590 | 0.021 |
| Previous k | 0.652 | 0.095 |
| Constant 0.00368 | 0.621 | |
| Coin flip | 0.693 | |

With the games lost on time put back (18,558 positions) the table scores 0.692 and the previous k 0.857. `k` comes out the same from either point of view (0.00220 both ways), and below 2000 it moves little with game phase. Rapid and classical run somewhat higher than blitz. `fit.txt` in the cache has the full subsets table.

## What moved in the labels

The curve is about 2.1 times flatter up to 2100, and less above. At 1500, from an equal position, the bands now start at these drops:

| Class | Before | Now |
|---|---|---|
| Good | 17 cp | 37 cp |
| Inaccuracy | 41 cp | 94 cp |
| Mistake | 84 cp | 190 cp |
| Blunder (still needs lost material or an allowed mate) | 175 cp | 396 cp |

In clearly won or lost positions the flatter curve goes the other way: it no longer saturates, so a drop from +10 to +3 costs more than it did.

Every other expected-points threshold in `Thresholds` is our own and can't be fitted from results. They were scaled down by the same 2.1 so that they keep their meaning in centipawns: otherwise Miss halves (8 instead of 18 on the sample below). Thresholds in centipawns and the deep-pass win-percent check stay as they were.

Eight Lichess games, the first in the stream near each of 800, 1300, 1800 and 2300 (569 moves), reviewed before and after. 404 moves keep their class. Eight games are an illustration, not a measurement.

| Class | Before | After |
|---|---|---|
| Brilliant | 1 | 1 |
| Great | 7 | 7 |
| Best | 212 | 210 |
| Excellent | 76 | 101 |
| Good | 63 | 79 |
| Inaccuracy | 60 | 51 |
| Mistake | 68 | 37 |
| Miss | 18 | 17 |
| Blunder | 10 | 12 |

Book (48) and Forced (6) don't move. Accuracy has its own curve and stays put, apart from small shifts when a position gets a different deep search. Deep searches drop from 232 to 209.

## Open points

- Lichess ratings aren't chess.com ratings. An imported chess.com game looks up the table with its chess.com rating, with no offset, because we have no verified mapping.
- The one chess.com rating sweep on record (-4.25 to mated in 5: Blunder, Mistake, Inaccuracy at 670, 1670, 2670) no longer holds: this table gives Blunder, Blunder, Mistake. That sweep needs k above 0.0033 at 1670 and 0.0052 at 2670, so chess.com's curve looks steeper than results on Lichess support, and our labels will read softer than theirs.
- Mate scores are not fitted. Players scored 0.87 to 0.93 from winning mate scores, against 0.95 to 0.99 from the app's mate table.
- The fit uses the 150,000-node pass only, and the 1M-node deep pass reads the same table.
- The rescaled thresholds have not been tuned against hand-labelled positions.
