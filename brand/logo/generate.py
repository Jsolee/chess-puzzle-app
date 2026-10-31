#!/usr/bin/env python3
"""Scachs logo: the wordmark and the S outlined from Grenze Gotisch, so no font is needed to show them."""
import pathlib, sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

here = pathlib.Path(__file__).parent
FONT = here.parent.parent / '.cache/fonts/grenzegotisch_GrenzeGotisch[wght].ttf'

def wordmark(text='Scachs', wght=500, track=-6):
    f = instancer.instantiateVariableFont(TTFont(FONT), {'wght': wght})
    gs, cmap, hmtx = f.getGlyphSet(), f.getBestCmap(), f['hmtx']
    x, d = 0, []
    for ch in text:
        g = cmap[ord(ch)]
        pen = SVGPathPen(gs)
        gs[g].draw(TransformPen(pen, (1, 0, 0, -1, x, 0)))
        d.append(pen.getCommands())
        x += hmtx[g][0] + track
    return ' '.join(d), x, f['OS/2'].sTypoAscender, f['OS/2'].sTypoDescender, f

def initial(wght=500):
    f = instancer.instantiateVariableFont(TTFont(FONT), {'wght': wght})
    gs, cmap, hmtx = f.getGlyphSet(), f.getBestCmap(), f['hmtx']
    g = cmap[ord('S')]
    pen = SVGPathPen(gs)
    gs[g].draw(TransformPen(pen, (1, 0, 0, -1, 0, 0)))
    return pen.getCommands(), hmtx[g][0]

def svg(body, w, h, extra=''):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" {extra}>{body}</svg>'

if __name__ == '__main__':
    d, W, asc, desc, f = wordmark()
    (here / 'wordmark.svg').write_text(svg(f'<path fill="currentColor" d="{d}" transform="translate(0 {asc})"/>', W, asc - desc))
    s, sw = initial()
    (here / 'mark.svg').write_text(svg(f'<path fill="currentColor" d="{s}" transform="translate(0 {asc})"/>', sw, asc - desc))
    for name, colour in (('tin', '#f6f1e6'), ('ink', '#16121c'), ('green', '#0f3a33')):
        (here / f'wordmark-{name}.svg').write_text((here / 'wordmark.svg').read_text().replace('currentColor', colour))
        (here / f'mark-{name}.svg').write_text((here / 'mark.svg').read_text().replace('currentColor', colour))
    print('wordmark', W, asc, desc)
