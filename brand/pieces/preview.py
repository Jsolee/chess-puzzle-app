#!/usr/bin/env python3
"""Offline twin of the board shader, to judge finishes and palettes in a PNG."""
import sys, pathlib, json
import numpy as np
from PIL import Image
from silhouettes import PIECES, S
import finishes as F

here = pathlib.Path(__file__).parent
cache = here / 'baked'; cache.mkdir(exist_ok=True)

def srgb(x): return np.where(x <= .0031308, x * 12.92, 1.055 * np.maximum(x, 1e-6) ** (1 / 2.4) - .055)
def lin(h):
    c = np.array([int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)], dtype=np.float32)
    return np.where(c <= .04045, c / 12.92, ((c + .055) / 1.055) ** 2.4)
def norm(v): return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-6)
def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)
gblur = F.gblur

def env(R, tilt):
    r = R.copy(); r[..., 0] += tilt[0]; r[..., 1] += tilt[1]; r = norm(r)
    sky = np.array([.70, .72, .78], dtype=np.float32)[None, None] * sstep(-.4, .9, r[..., 1])[..., None] * .9
    floor = np.array([.04, .04, .05], dtype=np.float32)[None, None]
    wx, wy = (r[..., 0] + .34) / .22, (r[..., 1] - .48) / .30
    d = np.maximum(np.abs(wx), np.abs(wy))
    window = (1 - sstep(.45, 1.0, d))[..., None] * np.array([1., .97, .92], dtype=np.float32)
    return floor + sky + window * 5.5

def bake(finish):
    p = cache / f'{finish}.npz'
    if p.exists(): return np.load(p)
    out = {}
    for n in PIECES:
        b = getattr(F, finish)(n)
        for key, v in zip(('nx', 'ny', 'm', 'a', 'z'), b): out[f'{n}_{key}'] = v
    np.savez_compressed(p, **out)
    return np.load(p)

def res(a, size): return np.asarray(Image.fromarray(a).resize((size, size), Image.LANCZOS)).astype(np.float32)

def light(G, name, white, size, tilt, pal, finish):
    if finish == 'tall':
        shade, lines, a = res(G[f'{name}_nx'], size), res(G[f'{name}_ny'], size), res(G[f'{name}_m'], size)
        body = lin(pal['tin'] if white else pal['ink'])
        sh = lin(pal['tinShade'] if white else pal['inkLift'])
        line = lin(pal['line'] if white else pal['lineOnInk'])
        col = body[None, None] * (1 - shade[..., None]) + sh[None, None] * shade[..., None]
        col = col * (1 - lines[..., None]) + line[None, None] * lines[..., None]
        return col, np.clip(a, 0, 1)
    nx, ny, m, a = res(G[f'{name}_nx'], size), res(G[f'{name}_ny'], size), res(G[f'{name}_m'], size), res(G[f'{name}_a'], size)
    a = np.clip(a, 0, 1); m = np.clip(m, 0, 1)
    nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
    n = np.dstack([nx, ny, nz])
    R = 2 * n[..., 2:3] * n - np.array([0, 0, 1], dtype=np.float32)
    L = norm(np.array([-.42, .70, .66], dtype=np.float32))
    wrap = np.clip(((n * L).sum(-1, keepdims=True) + .4) / 1.4, 0, 1)
    F0 = .045 + .955 * (1 - np.clip(nz[..., None], 0, 1)) ** 5
    E = env(R, tilt)
    if white:
        alb = lin(pal['tin'])[None, None]
        en = alb * (.70 + .36 * wrap) * (1 - F0) + np.minimum(E, 5) * F0 * .9
        if finish == 'vidriat':
            en = en * (.42 + .58 * sstep(.0, .42, nz[..., None]))
        metal_dark, metal_lit = lin(pal['line']), lin(pal['metal'])
    else:
        alb = lin(pal['ink'])[None, None]
        en = alb * (.80 + .5 * wrap) * (1 - F0) + np.minimum(E, 5) * (F0 * 1.05 + .012)
        if finish == 'vidriat':
            rim = (1 - nz[..., None]) ** 2
            en = en + lin(pal['metal'])[None, None] * rim * .55
        metal_dark, metal_lit = lin(pal['lineOnInk']), lin(pal['metalBright'])
    s = np.clip(E.mean(-1, keepdims=True) * .55 + wrap * .35, 0, 1.6)
    metal = metal_dark[None, None] * (1 - np.clip(s, 0, 1)) + metal_lit[None, None] * s
    col = en * (1 - m[..., None]) + metal * m[..., None]
    return col, a

def board(N, tilt, pal, seed=7, wire=True):
    px = N / 8
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    fx, fy = x / px, y / px
    ix, iy = np.floor(fx).astype(int), np.floor(fy).astype(int)
    ux, uy = fx - ix, fy - iy
    rs = np.random.RandomState(seed)
    tt = (rs.rand(8, 8, 2) - .5).astype(np.float32) * .022
    tone = rs.rand(8, 8).astype(np.float32)
    nx, ny = tt[iy, ix, 0], tt[iy, ix, 1]
    n = norm(np.dstack([nx, ny, np.ones_like(nx)]))
    v = norm(np.dstack([(x / N - .5) * .7, -(y / N - .5) * .7, np.ones_like(x)]))
    R = 2 * (n * v).sum(-1, keepdims=True) * n - v
    dark = (ix + iy) % 2 == 1
    alb = np.where(dark[..., None], lin(pal['tileDark'])[None, None] * (1 + (tone[iy, ix, None] - .5) * .12), lin(pal['tileLight'])[None, None] * (1 + (tone[iy, ix, None] - .5) * .03))
    FF = .04 + .96 * (1 - np.clip((n * v).sum(-1), 0, 1)) ** 5
    E = env(R, tilt)
    if pal.get('metalTiles'):
        tint = lin(pal['tileDark'])[None, None]
        sheen = np.clip(E.mean(-1, keepdims=True) * .55, 0, 2.5)
        met = tint * (.55 + sheen * 1.5)
        col = np.where(dark[..., None], met, alb * .94 + E * FF[..., None] * .7)
    else:
        col = alb * .94 + E * FF[..., None] * .75
    if wire:
        edge = np.minimum(np.minimum(ux, 1 - ux), np.minimum(uy, 1 - uy))
        w = 1.25 / px
        wm = (1 - sstep(w * .6, w * 1.2, edge))[..., None]
        wc = lin(pal['wire'])[None, None] * np.clip(.7 + E.mean(-1, keepdims=True) * .55, 0, 1.8)
        col = col * (1 - wm) + wc * wm
    return col

FEN = 'r1bq1rk1/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1'

def compose(finish, pal, N=1179, tilt=(0, 0), fen=FEN):
    G = bake(finish)
    bd = board(N, tilt, pal)
    px = N / 8; sz = int(px * 1.04)
    for ry, row in enumerate(fen.split('/')):
        fx = 0
        for ch in row:
            if ch.isdigit(): fx += int(ch); continue
            x0, y0 = int(fx * px - sz * .02), int(ry * px - sz * .03)
            col, a = light(G, ch.lower(), ch.isupper(), sz, tilt, pal, finish)
            sh = gblur(a, sz * .03)
            ox, oy = int(sz * .018), int(sz * .024)
            xa, ya, xb, yb = max(0, x0 + ox), max(0, y0 + oy), min(N, x0 + ox + sz), min(N, y0 + oy + sz)
            bd[ya:yb, xa:xb] *= (1 - .42 * sh[ya - (y0 + oy):yb - (y0 + oy), xa - (x0 + ox):xb - (x0 + ox), None])
            xa, ya, xb, yb = max(0, x0), max(0, y0), min(N, x0 + sz), min(N, y0 + sz)
            ca, aa = col[ya - y0:yb - y0, xa - x0:xb - x0], a[ya - y0:yb - y0, xa - x0:xb - x0, None]
            bd[ya:yb, xa:xb] = bd[ya:yb, xa:xb] * (1 - aa) + ca * aa
            fx += 1
    return bd

def tone(c):
    c = np.clip(c, 0, None)
    return (np.clip(srgb(c * (1 + c / 9.0) / (1 + c * .22)), 0, 1) * 255).astype(np.uint8)

def save(c, path): Image.fromarray(tone(c)).save(path)

PAL = json.load(open(here / 'palettes.json'))
