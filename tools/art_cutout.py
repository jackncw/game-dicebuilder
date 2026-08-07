#!/usr/bin/env python3
"""Character art pipeline for the 2026-08 character overhaul.

Takes the six Gemini reference plates in `Art reference/character_*.jfif`,
cuts them off their cream background, normalises tone across the set, and
writes two Godot-ready assets per hero:

    assets/heroes/<id>_full.png   transparent full body, feet on the bottom edge
    assets/heroes/<id>_head.png   square head crop for offer cards / avatars

The badger plate is a 2x2 pose sheet; only the top-left pose is used.

    python tools/art_cutout.py            # full run
    python tools/art_cutout.py --debug    # also write qa/cutout_*.png contact sheets
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "Art reference")
OUT = os.path.join(ROOT, "assets", "heroes")
QA = os.path.join(ROOT, "qa")

# file -> hero. Identified by opening every plate, NOT by filename order:
# the numbering does not follow the design brief's listing order.
PLATES = [
    # (source file, hero id, crop box or None, head box in source pixels)
    ("character_1.jfif", "BADGER", (0, 0, 512, 512), (206, 40, 406, 240)),
    ("character_5.jfif", "HARE", None, (380, 44, 672, 336)),
    ("character_6.jfif", "HEDGE", None, (300, 150, 620, 470)),
    ("character_3.jfif", "OWL", None, (352, 80, 640, 368)),
    ("character_2.jfif", "FOX", None, (330, 60, 610, 340)),
    ("character_4.jfif", "BOAR", None, (372, 104, 672, 404)),
]

# Output canvas. Portraits are drawn at 2x the tallest in-game use (270px at
# 540 wide) so the 540 build still samples down rather than up.
FULL_H = 720
HEAD_PX = 256


# --------------------------------------------------------------- background

def _bg_mask(rgb: np.ndarray) -> np.ndarray:
    """True where the pixel is the cream plate background or its drop shadow.

    Flood filled inward from the border so cream *inside* the character (hare
    belly fur, badger face stripe, owl skull charm) is never eaten: the dark
    ink outline every plate shares walls the fill off.
    """
    h, w, _ = rgb.shape
    f = rgb.astype(np.float32) / 255.0
    mx = f.max(axis=2)
    mn = f.min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    val = mx
    # Background cream and its cast shadow are both desaturated and light.
    # The threshold has to reach down into the shadow (which bottoms out near
    # 0.66 value under the hare) without being able to walk into the pale fur
    # the hare, badger and hedgehog all have — the dark ink outline is what
    # makes that safe, so this is deliberately looser than a global key would
    # allow.
    cand = (sat < 0.20) & (val > 0.63)

    # iterative border flood fill on the candidate set
    seed = np.zeros((h, w), dtype=bool)
    seed[0, :] = cand[0, :]
    seed[-1, :] = cand[-1, :]
    seed[:, 0] = cand[:, 0]
    seed[:, -1] = cand[:, -1]
    filled = seed.copy()
    while True:
        grown = filled.copy()
        grown[1:, :] |= filled[:-1, :]
        grown[:-1, :] |= filled[1:, :]
        grown[:, 1:] |= filled[:, :-1]
        grown[:, :-1] |= filled[:, 1:]
        grown &= cand
        if grown.sum() == filled.sum():
            break
        filled = grown

    # Pockets of plate the border fill cannot reach — the hare's bow and its
    # string enclose one, and left in they read as a solid cream sail. A pocket
    # is background when it is as flat as the plate is (the plate is a single
    # printed colour; painted fur always carries a gradient).
    # Thresholds are measured, not guessed: across the six plates every real
    # pocket sits at mean-difference < 3 and channel std < 11, while the
    # lightest fur that survives the outline wall (hare belly, hedgehog face)
    # is at mean-difference 16+. The gap is wide, so the cut is generous.
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg_col = np.median(border.reshape(-1, 3), axis=0)
    for comp in _components(cand & ~filled):
        if comp.sum() < 800:
            continue
        px = rgb[comp].astype(np.float32)
        if px.std(axis=0).max() < 14.0 and np.abs(px.mean(axis=0) - bg_col).max() < 6.0:
            filled |= comp
    return filled


def _components(mask: np.ndarray):
    """Connected components of a boolean mask, 4-connected, as boolean masks."""
    h, w = mask.shape
    seen = np.zeros((h, w), dtype=bool)
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        comp = np.zeros((h, w), dtype=bool)
        comp[y0, x0] = True
        while True:
            grown = comp.copy()
            grown[1:, :] |= comp[:-1, :]
            grown[:-1, :] |= comp[1:, :]
            grown[:, 1:] |= comp[:, :-1]
            grown[:, :-1] |= comp[:, 1:]
            grown &= mask
            if grown.sum() == comp.sum():
                break
            comp = grown
        seen |= comp
        yield comp


def cutout(img: Image.Image) -> Image.Image:
    """RGBA with the plate background removed and the edge feathered."""
    rgb = np.asarray(img.convert("RGB"))
    bg = _bg_mask(rgb)
    alpha = np.where(bg, 0, 255).astype(np.uint8)
    a = Image.fromarray(alpha, "L")
    # 1px erode then a soft blur: kills the pale halo the flat cream leaves on
    # the anti-aliased outline without visibly thinning the silhouette.
    a = a.filter(ImageFilter.MinFilter(3))
    a = a.filter(ImageFilter.GaussianBlur(0.8))
    out = img.convert("RGBA")
    out.putalpha(a)
    return out


# --------------------------------------------------------------- tone

def _subject_stats(rgba: np.ndarray):
    """Mean and spread of the opaque pixels, per channel."""
    a = rgba[:, :, 3] > 200
    if a.sum() < 100:
        return np.array([128.0] * 3), np.array([40.0] * 3)
    px = rgba[:, :, :3][a].astype(np.float32)
    return px.mean(axis=0), px.std(axis=0)


def tone_match(rgba: Image.Image, target_mean, target_std, strength=0.75) -> Image.Image:
    """Pull one plate's colour temperature and contrast toward the set average.

    Partial (`strength`) on purpose — a full match flattens the fox's warm
    orange and the hedgehog's cold steel into the same brown mush.
    """
    arr = np.asarray(rgba).astype(np.float32)
    mean, std = _subject_stats(np.asarray(rgba))
    a = arr[:, :, 3:4] / 255.0
    rgb = arr[:, :, :3]
    scale = np.where(std > 1.0, target_std / np.maximum(std, 1.0), 1.0)
    scale = 1.0 + (scale - 1.0) * strength
    shift = (target_mean - mean) * strength
    adj = (rgb - mean) * scale + mean + shift
    out = np.concatenate([np.clip(adj, 0, 255), arr[:, :, 3:4]], axis=2)
    # keep fully-transparent pixels black so no colour bleeds on downscale
    out[:, :, :3] *= np.where(a > 0, 1.0, 0.0)
    return Image.fromarray(out.astype(np.uint8), "RGBA")


# --------------------------------------------------------------- framing

def trim(rgba: Image.Image, thresh=8) -> Image.Image:
    a = np.asarray(rgba)[:, :, 3]
    ys, xs = np.where(a > thresh)
    if len(ys) == 0:
        return rgba
    return rgba.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def fit_height(rgba: Image.Image, h: int) -> Image.Image:
    w = max(1, round(rgba.width * h / rgba.height))
    return rgba.resize((w, h), Image.LANCZOS)


def square(rgba: Image.Image, px: int) -> Image.Image:
    """Centre the art on a transparent square canvas of `px`."""
    s = fit_height(rgba, px) if rgba.height >= rgba.width else rgba.resize(
        (px, max(1, round(rgba.height * px / rgba.width))), Image.LANCZOS)
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    canvas.paste(s, ((px - s.width) // 2, (px - s.height) // 2))
    return canvas


# --------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    os.makedirs(QA, exist_ok=True)

    cuts = {}
    heads = {}
    for fname, hid, box, headbox in PLATES:
        src = Image.open(os.path.join(REF, fname))
        if box:
            src = src.crop(box)
        cut = cutout(src)
        cuts[hid] = cut
        heads[hid] = cut.crop(headbox)

    # one target tone for the whole cast, averaged over the six plates
    means = np.array([_subject_stats(np.asarray(c))[0] for c in cuts.values()])
    stds = np.array([_subject_stats(np.asarray(c))[1] for c in cuts.values()])
    t_mean, t_std = means.mean(axis=0), stds.mean(axis=0)
    print("tone target  mean=%s  std=%s" % (np.round(t_mean, 1), np.round(t_std, 1)))

    meta = {}
    for hid in cuts:
        full = trim(tone_match(cuts[hid], t_mean, t_std))
        full = fit_height(full, FULL_H)
        full.save(os.path.join(OUT, "%s_full.png" % hid.lower()))
        head = square(trim(tone_match(heads[hid], t_mean, t_std)), HEAD_PX)
        head.save(os.path.join(OUT, "%s_head.png" % hid.lower()))
        meta[hid] = {"full": [full.width, full.height], "aspect": round(full.width / full.height, 4)}
        print("%-7s full=%dx%d  head=%dx%d" % (hid, full.width, full.height, HEAD_PX, HEAD_PX))

    with open(os.path.join(OUT, "portraits.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    if args.debug:
        sheet = Image.new("RGBA", (6 * 260, 300), (40, 40, 46, 255))
        for i, hid in enumerate(cuts):
            im = fit_height(trim(cuts[hid]), 280)
            sheet.paste(im, (i * 260 + (250 - im.width) // 2, 10), im)
        sheet.save(os.path.join(QA, "cutout_contact.png"))
        hsheet = Image.new("RGBA", (6 * 270, 280), (40, 40, 46, 255))
        for i, hid in enumerate(heads):
            im = square(trim(heads[hid]), 256)
            hsheet.paste(im, (i * 270 + 7, 12), im)
        hsheet.save(os.path.join(QA, "head_contact.png"))
        print("debug sheets -> qa/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
