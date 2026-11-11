#!/usr/bin/env python3
"""App Store screenshots, 1320 x 2868, from raw simulator captures.

usage: python3 tools/store_screenshots.py <ca|es|en> <dir with raw captures>

The raw captures are <lang>-<scene>.png at the simulator's 1206 x 2622, taken from a Debug build launched with
`-scene <scene>` (see Scachs/App/ScreenshotScene.swift). Slide 1 is the title slide; every other slide is the real
screen in a phone that runs off the bottom edge, under a two-line caption with one word in gold. Layout after the
before.click gallery and its ASO guide: more than half of the set shows the app in use, captions say what it does.
"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(ROOT, "Scachs/Resources/Fonts/")
W, H = 1320, 2868
FIELD, DEEP, TIN, GOLD, INK = (15, 58, 51), (11, 44, 39), (246, 241, 230), (231, 185, 108), (22, 18, 28)

SCENES = ["today", "review", "lesson", "path", "openings", "exercises", "atlas", "profile"]
TEXT = {
    "ca": {
        "title": ("Els escacs, per plaer.", "Puzzles, lliçons i les teves partides analitzades, en el tauler més bonic."),
        "today": "Aprèn de les teves *partides*", "review": "Cada jugada, *analitzada*",
        "lesson": "Lliçons que *corregeixen* a l'instant", "path": "De les regles d'or a la *mestria*",
        "openings": "*Vint* obertures, en un arbre", "exercises": "Exercicis de *finals* i tàctica",
        "atlas": "El *mapa* de les teves obertures", "profile": "Quina figura *medieval* ets?",
    },
    "es": {
        "title": ("El ajedrez, por placer.", "Puzzles, lecciones y tus partidas analizadas, en el tablero más bonito."),
        "today": "Aprende de tus *partidas*", "review": "Cada jugada, *analizada*",
        "lesson": "Lecciones que *corrigen* al instante", "path": "De las reglas de oro a la *maestría*",
        "openings": "*Veinte* aperturas, en un árbol", "exercises": "Ejercicios de *finales* y táctica",
        "atlas": "El *mapa* de tus aperturas", "profile": "¿Qué figura *medieval* eres?",
    },
    "en": {
        "title": ("Chess, for pleasure.", "Puzzles, lessons and your own games reviewed, on the most beautiful board."),
        "today": "Learn from your own *games*", "review": "Every move, *reviewed*",
        "lesson": "Lessons that *correct* you on the spot", "path": "From the golden rules to *mastery*",
        "openings": "*Twenty* openings, as a tree", "exercises": "Drills for *endgames* and tactics",
        "atlas": "A *map* of your openings", "profile": "Which *medieval* figure are you?",
    },
}


def field():
    c = Image.new("RGB", (W, H), FIELD)
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse((-500, -600, 1200, 900), fill=70)
    return Image.composite(Image.new("RGB", (W, H), (24, 80, 69)), c, glow.filter(ImageFilter.GaussianBlur(260)))


def words(text):
    """Splits '*gold*' markup into (word, is_gold) pairs."""
    out = []
    for part in text.split(" "):
        out.append((part.replace("*", ""), part.startswith("*") or part.endswith("*")))
    return out


def caption(d, text, top, size=124, width=W - 150):
    font = ImageFont.truetype(FONTS + "GrenzeGotisch-Medium.ttf", size)
    lines, line = [], []
    for w in words(text):
        trial = " ".join(x for x, _ in line + [w])
        if line and d.textlength(trial, font=font) > width:
            lines.append(line); line = [w]
        else:
            line.append(w)
    lines.append(line)
    y = top if len(lines) > 1 else top + size * 0.55
    space = d.textlength(" ", font=font)
    for line in lines:
        total = sum(d.textlength(x, font=font) for x, _ in line) + space * (len(line) - 1)
        x = (W - total) / 2
        for word, gold in line:
            d.text((x, y), word, font=font, fill=GOLD if gold else TIN)
            x += d.textlength(word, font=font) + space
        y += size * 1.1


def phone(canvas, shot, top):
    """The capture in a dark bezel with the brand's gold wire, running off the bottom of the slide."""
    sw = 1080
    sh = int(shot.height * sw / shot.width)
    bezel, r = 30, 150
    x0, y0 = (W - sw) // 2 - bezel, top
    body = (x0, y0, x0 + sw + 2 * bezel, y0 + sh + 2 * bezel)
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((body[0], body[1] + 30, body[2], body[3] + 30), radius=r, fill=120)
    canvas.paste(Image.new("RGB", (W, H), DEEP), (0, 0), shadow.filter(ImageFilter.GaussianBlur(40)))
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle(body, radius=r, fill=INK, outline=GOLD, width=4)
    screen = shot.resize((sw, sh), Image.LANCZOS)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=r - bezel, fill=255)
    canvas.paste(screen, (x0 + bezel, y0 + bezel), mask)
    cx = W // 2
    d.rounded_rectangle((cx - 112, y0 + bezel + 30, cx + 112, y0 + bezel + 96), radius=33, fill=(5, 5, 7))


def title_slide(raw_today, lang):
    c = field()
    d = ImageDraw.Draw(c)
    mark = Image.open(os.path.join(ROOT, "Scachs/Assets.xcassets/Wordmark.imageset/wordmark.png")).convert("RGBA")
    mw = 980
    mark = mark.resize((mw, int(mark.height * mw / mark.width)), Image.LANCZOS)
    tin = Image.new("RGBA", mark.size, TIN + (255,)); tin.putalpha(mark.split()[3])
    c.paste(tin, ((W - mw) // 2, 250), tin)
    head, sub = TEXT[lang]["title"]
    caption(d, "*" + head.replace(" ", "* *") + "*", 250 + mark.height + 70, size=96)
    small = ImageFont.truetype(FONTS + "YsabeauOffice-Regular.ttf", 52)
    lines, line = [], ""
    for w in sub.split():
        t = (line + " " + w).strip()
        if d.textlength(t, font=small) > W - 260 and line: lines.append(line); line = w
        else: line = t
    lines.append(line)
    y = 250 + mark.height + 220
    for l in lines:
        d.text(((W - d.textlength(l, font=small)) / 2, y), l, font=small, fill=(205, 212, 200)); y += 70
    # The real board from the Today screen, edge to edge, as it sits in the app.
    shot = Image.open(raw_today).convert("RGB")
    s = shot.width / 402
    board = shot.crop((0, int(256 * s), shot.width, int(256 * s) + shot.width))
    board = board.resize((W, W), Image.LANCZOS)
    top = H - W - 140
    c.paste(board, (0, top))
    d.line((0, top - 2, W, top - 2), fill=GOLD, width=4)
    d.line((0, top + W + 1, W, top + W + 1), fill=GOLD, width=4)
    return c


def main():
    lang, raw = sys.argv[1], sys.argv[2]
    out = os.path.join(ROOT, "AppStore/screenshots", lang)
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".png"): os.remove(os.path.join(out, f))
    title_slide(os.path.join(raw, f"{lang}-today.png"), lang).save(os.path.join(out, "01.png"), optimize=True)
    for i, scene in enumerate(SCENES, 2):
        src = os.path.join(raw, f"{lang}-{scene}.png")
        if not os.path.exists(src):
            print("missing", src); continue
        c = field()
        caption(ImageDraw.Draw(c), TEXT[lang][scene], 150)
        phone(c, Image.open(src).convert("RGB"), 520)
        c.save(os.path.join(out, f"{i:02d}.png"), optimize=True)
    print(lang, sorted(os.listdir(out)))


if __name__ == "__main__":
    main()
