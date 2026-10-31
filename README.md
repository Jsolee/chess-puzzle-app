# Scachs

Chess for people who love it and rarely play. A native iOS app: puzzles that adapt, your games from chess.com and Lichess reviewed move by move with Stockfish on the device, and short lessons drawn from your own mistakes. Enamel pieces and a board that catch real light as you tilt the phone.

The name is the word in the poem *Scachs d'amor* (Valencia, c.1475), the earliest known record of the modern queen and bishop. Say "skaks".

## Build

Needs Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
scripts/setup.sh
```

Then open `Scachs.xcodeproj`. The Stockfish target always builds optimised.

## Layout

- `Scachs/`: the app. `docs/ARCHITECTURE.md` has the map.
- `Engine/`: Stockfish 19 and the C bridge.
- `brand/`: identity, tokens, and the code that draws the pieces, the logo and the icon. `brand/BRAND.md` is the guide.
- `tools/`: reproducible data builds (puzzles, openings, lessons) and the label calibration (`docs/CALIBRATION.md`).
- `AppStore/`: TestFlight and store material. `scripts/testflight.sh` archives and uploads.

## Licence

GPL-3.0-or-later. Stockfish is GPLv3. See [COPYING.md](COPYING.md) for what's under which licence, including the name and logo.

Not affiliated with chess.com or Lichess. Move labels are computed by this app with its own model and may differ from other services.
