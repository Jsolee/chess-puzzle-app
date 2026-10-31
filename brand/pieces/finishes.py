#!/usr/bin/env python3
"""Three finishes on the same silhouettes, baked as normal.xy + material + alpha so the board can relight them."""
import numpy as np
from PIL import Image
from silhouettes import S, X, Y, xs, ys, PIECES

def jfa(seed):
    """Distance to the nearest True pixel, by jump flooding."""
    sx = np.where(seed, xs, -1e5).astype(np.float32); sy = np.where(seed, ys, -1e5).astype(np.float32)
    best = (xs - sx) ** 2 + (ys - sy) ** 2
    step = S // 2
    while step >= 1:
        for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            cx, cy = np.roll(sx, (dy * step, dx * step), (0, 1)), np.roll(sy, (dy * step, dx * step), (0, 1))
            d = (xs - cx) ** 2 + (ys - cy) ** 2
            better = d < best
            sx, sy, best = np.where(better, cx, sx), np.where(better, cy, sy), np.where(better, d, best)
        step //= 2
    return np.sqrt(best)

def seg_dist(pts):
    d = np.full_like(X, 9.)
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        dx, dy = x1 - x0, y1 - y0
        t = np.clip(((X - x0) * dx + (Y - y0) * dy) / (dx * dx + dy * dy), 0, 1)
        d = np.minimum(d, np.hypot(X - (x0 + t * dx), Y - (y0 + t * dy)))
    return d

def gblur(a, sigma):
    r = max(1, int(round(sigma * 1.6)))
    out = a.astype(np.float32)
    for axis in (0, 1):
        n = out.shape[axis]
        hi, lo = np.clip(np.arange(n) + r + 1, 0, n), np.clip(np.arange(n) - r, 0, n)
        shape = [1, 1]; shape[axis] = -1
        w = (hi - lo).reshape(shape)
        for _ in range(3):
            c = np.cumsum(np.insert(out, 0, 0, axis=axis), axis=axis)
            out = (np.take(c, hi, axis=axis) - np.take(c, lo, axis=axis)) / w
    return out

def normals(z, sharpen=1.):
    gy, gx = np.gradient(gblur(z, 1.1))
    gx, gy = gx * S * sharpen, -gy * S * sharpen
    k = 1 / np.sqrt(gx * gx + gy * gy + 1)
    return -gx * k, -gy * k

def inflate(mask):
    S2 = S // 4
    m = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).resize((S2, S2), Image.BILINEAR)).astype(np.float32) / 255 > .5
    z = np.zeros_like(m, dtype=np.float32); h = 1 / S2
    for _ in range(2500):
        n = np.zeros_like(z)
        n[1:-1, 1:-1] = .25 * (z[:-2, 1:-1] + z[2:, 1:-1] + z[1:-1, :-2] + z[1:-1, 2:] + h * h * 4)
        z = np.where(m, n, 0)
    z = np.sqrt(np.maximum(z, 0) * 2)
    return np.asarray(Image.fromarray(z).resize((S, S), Image.BICUBIC)).astype(np.float32)

def esmalt(name):
    """Cloisonné: flat, glossy enamel held in metal wire. The wire takes the light and draws the outline."""
    return enamel(*PIECES[name]())

def enamel(m, wires, dots, rim_w=.021, wire_w=.0105):
    inside = m > .5
    d_in = jfa(~inside) / S
    rim = d_in < rim_w
    wire_d = np.full_like(X, 9.)
    for w in wires: wire_d = np.minimum(wire_d, seg_dist(w))
    wire = (wire_d < wire_w) & inside
    dot = np.zeros_like(wire)
    dot_h = np.zeros_like(X)
    for cx, cy, r in dots:
        d = np.hypot(X - cx, Y - cy)
        dot |= d < r
        dot_h = np.maximum(dot_h, np.where(d < r, np.sqrt(np.maximum(r * r - d * d, 0)), 0))
    metal = rim | wire | dot
    cells = inside & ~metal
    d_cell = jfa(~cells) / S
    z_en = .010 * (1 - np.exp(-d_cell / .030)) + .05 * gblur(cells.astype(np.float32), S * .05)
    z_rim = .022 * np.sqrt(np.clip(1 - ((d_in - rim_w * .5) / (rim_w * .5)) ** 2, 0, 1))
    z_wire = .016 * np.sqrt(np.clip(1 - (wire_d / wire_w) ** 2, 0, 1))
    z = np.where(cells, z_en, 0)
    z = np.maximum(z, np.where(rim, z_rim, 0))
    z = np.maximum(z, np.where(wire, z_wire, 0))
    z = np.maximum(z, dot_h * .8)
    nx, ny = normals(z)
    return nx, ny, gblur(metal.astype(np.float32), .8), gblur(m, .6), z

def vidriat(name):
    """Glazed: the silhouette swells into a soft ceramic body, with the wires pressed in as grooves."""
    m, wires, dots = PIECES[name]()
    inside = m > .5
    z = inflate(inside.astype(np.float32)) * .95
    for w in wires:
        d = seg_dist(w)
        z = z - .020 * np.clip(1 - d / .012, 0, 1) ** .7
    for cx, cy, r in dots:
        d = np.hypot(X - cx, Y - cy)
        z = z - .03 * np.clip(1 - d / r, 0, 1) ** .6
    z = np.where(inside, z, 0)
    nx, ny = normals(z)
    return nx, ny, np.zeros_like(X), gblur(m, .6), z

def tall(name):
    """Cut: no gloss at all. A flat shape, one crisp plane of shade, a drawn edge."""
    m, wires, dots = PIECES[name]()
    inside = m > .5
    d_in = jfa(~inside) / S
    edge = d_in < .018
    wire_d = np.full_like(X, 9.)
    for w in wires: wire_d = np.minimum(wire_d, seg_dist(w))
    wire = (wire_d < .009) & inside
    dot = np.zeros_like(wire)
    for cx, cy, r in dots: dot |= np.hypot(X - cx, Y - cy) < r
    shift = np.roll(np.roll(inside, -int(.055 * S), axis=1), int(.0 * S), axis=0)
    shade = inside & ~shift
    lines = edge | wire | dot
    return gblur(shade.astype(np.float32), .7), gblur(lines.astype(np.float32), .7), gblur(m, .6)
