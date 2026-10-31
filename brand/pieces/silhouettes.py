#!/usr/bin/env python3
"""The Scachs set, drawn from code. One source for every finish: silhouettes, then the wires inside them."""
import numpy as np
from PIL import Image, ImageDraw

S = 1024
ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
X = (xs + .5) / S - .5
Y = 1 - (ys + .5) / S

def spline(pts, sub=14):
    """Closed Catmull-Rom. A point written (x, y, 'c') is a hard corner."""
    P = [np.array(p[:2], dtype=float) for p in pts]; n = len(P)
    corner = [len(p) > 2 for p in pts]
    out = []
    for i in range(n):
        p0, p1, p2, p3 = P[(i - 1) % n], P[i], P[(i + 1) % n], P[(i + 2) % n]
        if corner[i]: p0 = p1
        if corner[(i + 1) % n]: p3 = p2
        for t in np.linspace(0, 1, sub, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return out

def fill(pts):
    im = Image.new('L', (S * 2, S * 2), 0)
    ImageDraw.Draw(im).polygon([((x + .5) * S * 2, (1 - y) * S * 2) for x, y in spline(pts)], fill=255)
    return np.asarray(im.resize((S, S), Image.LANCZOS)).astype(np.float32) / 255

def mirror(half):
    """Half outline from bottom centre to top centre, x >= 0, mirrored to a whole one."""
    left = [(-p[0],) + tuple(p[1:]) for p in reversed(half[1:-1])]
    return list(half) + left

def disc(cx, cy, r):
    return np.clip((r - np.hypot(X - cx, Y - cy)) * S + .5, 0, 1).astype(np.float32)

def band(x0, x1, y):
    return [(x0, y), (x1, y)]

BASE = [(0, .085, 'c'), (.285, .085, 'c'), (.296, .106), (.285, .136, 'c'), (.238, .150, 'c')]

def pawn():
    half = BASE + [(.178, .20), (.128, .275), (.100, .355), (.094, .392, 'c'), (.170, .402, 'c'), (.186, .421), (.170, .440, 'c'), (.100, .448, 'c'), (.06, .47, 'c'), (0, .48, 'c')]
    m = np.maximum(fill(mirror(half)), disc(0, .572, .142))
    return m, [band(-.27, .27, .136), band(-.17, .17, .402), band(-.17, .17, .440)], []

def rook():
    half = BASE + [(.205, .205), (.186, .31), (.176, .46), (.184, .52), (.25, .575, 'c'), (.262, .592, 'c'), (.262, .735, 'c'), (.128, .735, 'c'), (.128, .668, 'c'), (.058, .668, 'c'), (.058, .735, 'c'), (0, .735, 'c')]
    m = fill(mirror(half))
    return m, [band(-.27, .27, .136), band(-.25, .25, .592), band(-.26, .26, .640)], []

def bishop():
    half = BASE + [(.176, .205), (.122, .285), (.094, .365), (.088, .428, 'c'), (.170, .438, 'c'), (.186, .456), (.170, .474, 'c'), (.12, .482, 'c'),
                   (.168, .545), (.182, .60), (.158, .675), (.098, .750), (.040, .808, 'c'), (0, .815, 'c')]
    m = np.maximum(fill(mirror(half)), disc(0, .845, .040))
    # the cut runs along a diagonal: it is how the piece moves
    cut = fill([(.205, .575, 'c'), (.215, .605, 'c'), (.060, .712, 'c'), (.042, .688, 'c')])
    m = np.clip(m - cut, 0, 1)
    return m, [band(-.27, .27, .136), band(-.17, .17, .438), band(-.17, .17, .474)], []

def queen():
    half = BASE + [(.178, .205), (.125, .29), (.096, .375), (.090, .448, 'c'), (.170, .458, 'c'), (.186, .476), (.170, .494, 'c'), (.104, .502, 'c'),
                   (.128, .57), (.190, .665), (.282, .775, 'c'), (.182, .705, 'c'), (.150, .825, 'c'), (.066, .715, 'c'), (0, .85, 'c')]
    m = fill(mirror(half))
    for cx, cy, r in ((.288, .790, .033), (-.288, .790, .033), (.152, .842, .033), (-.152, .842, .033), (0, .872, .037)):
        m = np.maximum(m, disc(cx, cy, r))
    return m, [band(-.27, .27, .136), band(-.17, .17, .458), band(-.17, .17, .494), [(-.205, .668), (0, .640), (.205, .668)]], []

def king():
    half = BASE + [(.178, .205), (.125, .29), (.096, .375), (.090, .448, 'c'), (.170, .458, 'c'), (.186, .476), (.170, .494, 'c'), (.104, .502, 'c'),
                   (.122, .57), (.166, .655), (.222, .725, 'c'), (.226, .742, 'c'), (.205, .758, 'c'), (.150, .790), (.078, .822, 'c'), (.032, .828, 'c'),
                   (.032, .868, 'c'), (.102, .852, 'c'), (.102, .922, 'c'), (.032, .906, 'c'), (.050, .978, 'c'), (0, .978, 'c')]
    m = fill(mirror(half))
    return m, [band(-.27, .27, .136), band(-.17, .17, .458), band(-.17, .17, .494), band(-.21, .21, .725)], []

def knight():
    outline = [
        (.285, .085, 'c'), (-.285, .085, 'c'), (-.296, .106), (-.285, .136, 'c'), (-.238, .150, 'c'),
        (-.195, .205), (-.130, .275), (-.078, .345), (-.040, .410), (-.020, .452, 'c'),
        (-.085, .440), (-.150, .392), (-.210, .362), (-.262, .362), (-.292, .392), (-.268, .424, 'c'), (-.315, .442), (-.328, .482), (-.305, .535),
        (-.235, .625), (-.165, .705), (-.100, .770), (-.058, .800, 'c'), (-.040, .900, 'c'), (.030, .826, 'c'), (.082, .880, 'c'), (.112, .800),
        (.190, .745), (.262, .645), (.302, .525), (.306, .400), (.280, .290), (.238, .200), (.238, .150, 'c'), (.285, .136, 'c'), (.296, .106),
    ]
    m = fill(outline)
    wires = [band(-.27, .27, .136),
             [(-.020, .452), (-.010, .515), (-.060, .565)],                                  # jaw
             [(.030, .826), (.112, .725), (.190, .620), (.222, .505), (.215, .385), (.175, .280), (.128, .205)]]  # mane
    dots = [(-.128, .632, .026), (-.272, .472, .016)]                                        # eye, nostril
    return m, wires, dots

PIECES = {'p': pawn, 'n': knight, 'b': bishop, 'r': rook, 'q': queen, 'k': king}
