#!/usr/bin/env python3
"""Bakes the Esmalt set for the app.
pieces.rgba: raw RGBA8 strip, 6 cells of 384 px (p n b r q k). R,G = normal.xy, B = metal mask, A = alpha.
Raw bytes, because a PNG decoder would premultiply the normals by alpha.
Also writes lit and flat PNGs for places the Metal board doesn't reach: promotion picker, move list figurines."""
import pathlib, sys
import numpy as np
from PIL import Image
from silhouettes import PIECES
import finishes as F
from preview import light, res, tone, PAL, bake

CELL = 384
root = pathlib.Path(__file__).parent.parent.parent / 'Scachs/Resources'
G = bake('esmalt')
strip = np.zeros((CELL, CELL * 6, 4), dtype=np.uint8)
for i, n in enumerate('pnbrqk'):
    nx, ny, m, a = (res(G[f'{n}_{k}'], CELL) for k in ('nx', 'ny', 'm', 'a'))
    strip[:, i * CELL:(i + 1) * CELL, 0] = np.clip(nx * .5 + .5, 0, 1) * 255
    strip[:, i * CELL:(i + 1) * CELL, 1] = np.clip(ny * .5 + .5, 0, 1) * 255
    strip[:, i * CELL:(i + 1) * CELL, 2] = np.clip(m, 0, 1) * 255
    strip[:, i * CELL:(i + 1) * CELL, 3] = np.clip(a, 0, 1) * 255
(root / 'pieces.rgba').write_bytes(strip.tobytes())
out = root / 'Pieces'; out.mkdir(exist_ok=True)
pal = PAL['verd']
for n in 'pnbrqk':
    for side, white in (('w', True), ('b', False)):
        col, a = light(G, n, white, 288, (0, 0), pal, 'esmalt')
        rgba = np.dstack([tone(col), (np.clip(a, 0, 1) * 255).astype(np.uint8)])
        Image.fromarray(rgba).save(out / f'{side}{n}.png')
    # figurine: one flat silhouette as a template image, drawn at the height of a capital
    _, _, _, a = (res(G[f'{n}_{k}'], 96) for k in ('nx', 'ny', 'm', 'a'))
    v = np.clip(a, 0, 1)
    rgba = np.dstack([np.full_like(v, 255, dtype=np.uint8)] * 3 + [(v * 255).astype(np.uint8)])
    fig = Image.fromarray(rgba)
    fig.crop(fig.getchannel('A').getbbox()).save(out / f'fig{n}.png')
print('baked', (root / 'pieces.rgba').stat().st_size)
