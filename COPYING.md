# Copying

This is a plain summary of what is under which licence, not legal advice. The licence texts decide.

Scachs is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It comes with no warranty. The full text is in [LICENSE](LICENSE). Linking Stockfish into the app makes the whole app one work under the GPL.

| What | Where | Licence |
|---|---|---|
| App code, bridge, tests, tools | `Scachs/`, `Engine/Bridge/`, `Tests/`, `tools/`, `scripts/` | GPL-3.0-or-later, © 2026 Joan Solé Jiménez |
| Stockfish 19 (tag `sf_19`) | `Engine/Stockfish/` | GPLv3, © The Stockfish developers, see `AUTHORS` and `Copying.txt` there |
| incbin, part of the Stockfish tree | `Engine/Stockfish/src/incbin/` | Unlicense |
| Net `nn-1a298aa575a0.nnue` | `Scachs/Resources/`, fetched by `scripts/setup.sh` | CC0-1.0 |
| Lichess puzzles (`puzzles.bin`) | `Scachs/Resources/` | CC0-1.0 |
| lichess-org/chess-openings (`openings.tsv`) | `Scachs/Resources/` | CC0-1.0 |
| Grenze Gotisch, Ysabeau Office | `Scachs/Resources/Fonts/` | SIL OFL 1.1, texts next to the fonts |

Stockfish's nets are trained on data from the Leela Chess Zero project, made available under the Open Database License (ODbL).

## Changes to Stockfish

Stock `sf_19` except for this, as GPLv3 section 5(a) asks:

- `Engine/Stockfish/src/shm.h`, 2026-10-30: `/tmp` shared memory disabled on iOS and its simulator.

## Name, logo and brand art

For the material whose copyright Joan Solé Jiménez holds, GPLv3 section 7(e) applies as an additional term: this licence grants no rights under trademark law to the name Scachs, its logo or the brand art in `brand/` and `Scachs/Assets.xcassets/`. A fork has to use its own name and logo.

That covers trademark use only. It does not take any art out of the GPL as a matter of copyright, and this repository makes no claim that it does.

## Open before an App Store release

These need a lawyer, and nothing above settles them:

- Whether art or lesson content can be licensed apart from the GPL inside one app. Until then, assume everything in this repository without its own line above is under GPL-3.0-or-later.
- How the App Store's usage rules sit with the GPL. The FSF has held that they conflict, and it has never been tested in court.
- Every shipped build needs an immutable tag here with its exact source, and a source link next to the binary.

The old web app on `master` carried an MIT notice in `src/LICENSE`. That code is not part of this native app, and the notice is gone on this branch.
