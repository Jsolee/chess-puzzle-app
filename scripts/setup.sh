#!/bin/bash
# Fetches what isn't kept in git: the Stockfish net (98.5 MB, CC0), checked by the hash in its name.
set -euo pipefail
cd "$(dirname "$0")/.."
NET=nn-1a298aa575a0.nnue
DEST=Scachs/Resources/$NET
if [[ ! -f "$DEST" ]]; then
  curl -fL --retry 3 -o "$DEST" "https://github.com/official-stockfish/networks/raw/master/$NET"
fi
[[ "$(shasum -a 256 "$DEST" | cut -c1-12)" == "1a298aa575a0" ]] || { rm -f "$DEST"; echo "Net hash mismatch"; exit 1; }
xcodegen generate
echo "Ready. Open Scachs.xcodeproj."
