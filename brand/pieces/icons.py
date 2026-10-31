#!/usr/bin/env python3
"""App icon candidates, enamelled with the same pipeline as the pieces."""
import sys, pathlib
import numpy as np
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from silhouettes import S, X, Y, PIECES
import finishes as F
from preview import lin, norm, sstep, env, tone, PAL, gblur

FONT = pathlib.Path(__file__).parent.parent.parent / '.cache/fonts/grenzegotisch_GrenzeGotisch[wght].ttf'

def star_mask(r=.40):
    k = r * .7071
    a = Image.new('L', (S * 2, S * 2), 0); b = Image.new('L', (S * 2, S * 2), 0)
    c, R, K = S, r * S * 2, k * S * 2
    ImageDraw.Draw(a).rectangle([c - K, c - K, c + K, c + K], fill=255)
    ImageDraw.Draw(b).polygon([(c, c - R), (c + R, c), (c, c + R), (c - R, c)], fill=255)
    A, B = np.asarray(a.resize((S, S), Image.LANCZOS)).astype(np.float32) / 255, np.asarray(b.resize((S, S), Image.LANCZOS)).astype(np.float32) / 255
    return np.maximum(A, B), np.abs(A - B)

def letter_mask(ch='S', size=860, wght=500, dy=-.015):
    f = ImageFont.truetype(str(FONT), size * 2)
    f.set_variation_by_axes([wght])
    im = Image.new('L', (S * 2, S * 2), 0); d = ImageDraw.Draw(im)
    l, t, r, b = d.textbbox((0, 0), ch, font=f)
    d.text((S - (l + r) / 2, S - (t + b) / 2 + dy * S * 2), ch, fill=255, font=f)
    return np.asarray(im.resize((S, S), Image.LANCZOS)).astype(np.float32) / 255

def scale_piece(m, wires, dots, s, oy=0.):
    """Scale a piece around the icon centre and return it re-rasterised."""
    im = Image.fromarray((m * 255).astype(np.uint8))
    w = int(S * s)
    r = im.resize((w, w), Image.LANCZOS)
    out = Image.new('L', (S, S), 0); out.paste(r, ((S - w) // 2, (S - w) // 2 + int(oy * S)))
    def tr(p):
        return ((p[0]) * s, (p[1] - .5) * s + .5 - oy)
    return np.asarray(out).astype(np.float32) / 255, [[tr(p) for p in wl] for wl in wires], [(*tr(d[:2]), d[2] * s) for d in dots]

def lit(nx, ny, m, a, enamel_col, metal_dark, metal_lit, tilt=(0, 0)):
    nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
    n = np.dstack([nx, ny, nz])
    R = 2 * n[..., 2:3] * n - np.array([0, 0, 1], dtype=np.float32)
    L = norm(np.array([-.42, .70, .66], dtype=np.float32))
    wrap = np.clip(((n * L).sum(-1, keepdims=True) + .4) / 1.4, 0, 1)
    F0 = .045 + .955 * (1 - np.clip(nz[..., None], 0, 1)) ** 5
    E = env(R, tilt)
    en = enamel_col[None, None] * (.74 + .34 * wrap) * (1 - F0) + np.minimum(E, 5) * F0
    s = np.clip(E.mean(-1, keepdims=True) * .55 + wrap * .35, 0, 1.6)
    metal = metal_dark[None, None] * (1 - np.clip(s, 0, 1)) + metal_lit[None, None] * s
    return en * (1 - m[..., None]) + metal * m[..., None], a

def field(pal):
    """The glazed ground: a slight swell, so the window sits in its top left."""
    r = np.hypot(X, Y - .5)
    z = .10 * np.exp(-(r / .55) ** 2)
    gy, gx = np.gradient(z); gx, gy = gx * S, -gy * S
    k = 1 / np.sqrt(gx * gx + gy * gy + 1)
    n = np.dstack([-gx * k, -gy * k, k])
    v = norm(np.dstack([X * .5, (Y - .5) * .5, np.ones_like(X)]))
    R = 2 * (n * v).sum(-1, keepdims=True) * n - v
    FF = .04 + .96 * (1 - np.clip((n * v).sum(-1), 0, 1)) ** 5
    base = lin(pal['field'])[None, None] * (1.25 - .55 * np.clip(r * 1.3, 0, 1)[..., None])
    return base + env(R, (0, 0)) * FF[..., None] * .55

def over(bg, col, a): return bg * (1 - a[..., None]) + col * a[..., None]

def icon(kind, pal):
    bg = field(pal)
    tin, ink = lin(pal['tin']), lin(pal['ink'])
    dark, bright = lin(pal['lineOnInk']), lin(pal['metalBright'])
    if kind == 'estrella':
        outer, even = star_mask(.40)
        # even-odd pattern: tips in tin, octagon in glaze; wires everywhere the two squares cross
        nx, ny, m, a, _ = F.enamel(outer, [], [], rim_w=.012, wire_w=.007)
        col, al = lit(nx, ny, m, a, tin, dark, bright)
        core = np.clip(outer - even, 0, 1)
        nx2, ny2, m2, a2, _ = F.enamel(core, [], [], rim_w=.012, wire_w=.007)
        col2, al2 = lit(nx2, ny2, m2, a2, lin(pal['field']) * 1.5, dark, bright)
        return over(over(bg, col, al), col2, al2)
    if kind == 'dama':
        m, w, d = PIECES['q']()
        m, w, d = scale_piece(m, w, d, 1.0, .0)
        nx, ny, mm, a, _ = F.enamel(m, w, d)
        col, al = lit(nx, ny, mm, a, tin, dark, bright)
        sh = gblur(al, S * .012)
        return over(bg * (1 - .35 * np.roll(np.roll(sh, 10, 0), 6, 1))[..., None] * 1 if False else bg * (1 - .35 * np.roll(np.roll(sh, 10, 0), 6, 1))[..., None], col, al)
    if kind == 'cavall':
        m, w, d = PIECES['n']()
        m, w, d = scale_piece(m, w, d, 1.02, .0)
        nx, ny, mm, a, _ = F.enamel(m, w, d)
        col, al = lit(nx, ny, mm, a, tin, dark, bright)
        sh = gblur(al, S * .012)
        return over(bg * (1 - .35 * np.roll(np.roll(sh, 10, 0), 6, 1))[..., None], col, al)
    if kind == 'inicial':
        m = letter_mask('S')
        nx, ny, mm, a, _ = F.enamel(m, [], [], rim_w=.013)
        col, al = lit(nx, ny, mm, a, tin, dark, bright)
        sh = gblur(al, S * .012)
        return over(bg * (1 - .35 * np.roll(np.roll(sh, 10, 0), 6, 1))[..., None], col, al)

if __name__ == '__main__':
    out = pathlib.Path(sys.argv[1])
    for pal in sys.argv[2:]:
        for kind in ('estrella', 'dama', 'cavall', 'inicial'):
            Image.fromarray(tone(icon(kind, PAL[pal]))).save(out / f'icon-{kind}-{pal}.png')
            print(pal, kind)
