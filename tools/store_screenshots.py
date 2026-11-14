#!/usr/bin/env python3
"""App Store screenshots, 1206 x 2622 (drawn at 1320 x 2868), from raw simulator captures.

usage: python3 tools/store_screenshots.py <dir with raw captures> [ca es en]

The raw captures are <lang>-<scene>.png at the simulator's 1206 x 2622, taken from a Debug build launched with
`-scene <scene>` (see Scachs/App/ScreenshotScene.swift). The slides are drawn in tools/store_screenshots.html as one
panorama, a cloisonné sea serpent swimming through the first three, and each slide is rendered by headless Chrome.
"""
import os, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
ASSETS = os.path.join(ROOT, "build/store")
SIZE = (1206, 2622)


def bake_pieces():
    """The enamel pieces, large, and the knight's silhouette for the shield's charge."""
    sys.path.insert(0, os.path.join(ROOT, "brand/pieces"))
    from preview import light, res, tone, PAL, bake
    os.makedirs(ASSETS, exist_ok=True)
    G = bake("esmalt")
    def save(rgba, name):
        im = Image.fromarray(rgba)
        im.crop(im.getchannel("A").getbbox()).save(os.path.join(ASSETS, name + ".png"))
    for name in ["wk", "wp", "wn", "wr", "bk", "bq", "bb"]:
        col, a = light(G, name[1], name[0] == "w", 1100, (0, 0), PAL["verd"], "esmalt")
        save(np.dstack([tone(col), (np.clip(a, 0, 1) * 255).astype(np.uint8)]), name)
    v = (np.clip(res(G["n_a"], 1100), 0, 1) * 255).astype(np.uint8)
    save(np.dstack([np.full_like(v, 255)] * 3 + [v]), "fign")


def render(lang, slide, raw, profiles):
    out = os.path.join(ASSETS, f"{lang}-{slide}.png")
    url = f"file://{ROOT}/tools/store_screenshots.html?lang={lang}&slide={slide}&raw={raw}&assets={ASSETS}"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    "--no-first-run", f"--user-data-dir={profiles}/{lang}{slide}", "--window-size=1320,2868",
                    "--allow-file-access-from-files", "--virtual-time-budget=10000", f"--screenshot={out}", url],
                   check=True, capture_output=True)
    dest = os.path.join(ROOT, "AppStore/screenshots", lang, f"{slide + 1:02d}.png")
    # App Store Connect requires the medium Dynamic Island size (6.3"); the larger sizes are optional.
    Image.open(out).convert("RGB").resize(SIZE, Image.LANCZOS).save(dest, optimize=True)
    return dest


def main():
    raw, langs = os.path.abspath(sys.argv[1]), sys.argv[2:] or ["ca", "es", "en"]
    bake_pieces()
    with tempfile.TemporaryDirectory() as profiles, ThreadPoolExecutor(6) as pool:
        for lang in langs:
            os.makedirs(os.path.join(ROOT, "AppStore/screenshots", lang), exist_ok=True)
        jobs = [pool.submit(render, lang, i, raw, profiles) for lang in langs for i in range(9)]
        for j in jobs:
            print(os.path.relpath(j.result(), ROOT))


if __name__ == "__main__":
    main()
