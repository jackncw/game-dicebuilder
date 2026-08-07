#!/usr/bin/env python3
"""Enemy art pipeline for the 2026-08 enemy sprite overhaul.

Cuts the ten minions and seven boss plates out of the Gemini reference art and
writes Godot-ready transparent PNGs to `assets/enemies/`.

    python tools/enemy_cutout.py               # full run
    python tools/enemy_cutout.py --hsv-report  # HSV histograms for the shader

The subject is found by its INK OUTLINE, not by keying the cream background.
Every creature on these plates is wrapped in one closed near-black line and
none of the clutter is: the painted smoke, the generator's corner sparkle and
the ink spatter all sit loose on the plate. Taking the ink outline's largest
connected components and filling their interiors therefore removes the smoke,
seals the cream pockets trapped inside the bramble's coils, and drops the
watermark in a single step — none of which a cream key can do.

The source plates are never modified.
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "Art reference")
OUT = os.path.join(ROOT, "assets", "enemies")
QA = os.path.join(ROOT, "qa")

# The 3x3 collection sheet. Row 1 slime/rat/sporecap, row 2 beetle/(moth over
# bramble)/bone wolf, row 3 wraith/toad/viper. The middle cell holds two
# creatures, so the sheet yields eight — the moth and the bramble come from
# their own full-resolution plates instead (they are 1024px there against
# 145/203px here, and the sheet's bramble carries cream trapped in its coils).
SHEET = os.path.join(REF, "monster", "monster1.jfif")
SHEET_CELLS = {
    "E01": (0, 0), "E02": (0, 1), "E03": (0, 2),
    "E04": (1, 0), "E07": (1, 2),
    "E08": (2, 0), "E09": (2, 1), "E10": (2, 2),
}
SOLO = {
    "E05": os.path.join(REF, "monster", "moth_solo.jfif"),
    "E06": os.path.join(REF, "monster", "vine_solo.jfif"),
    "B3P2": os.path.join(REF, "monster", "boss3_phase2.jfif"),
    "B1": os.path.join(REF, "boss", "boss1.jfif"),
    "B2": os.path.join(REF, "boss", "boss2.jfif"),
    "B3": os.path.join(REF, "boss", "boss3.jfif"),
    "B4": os.path.join(REF, "boss", "boss4.jfif"),
    "B5": os.path.join(REF, "boss", "boss5.jfif"),
    "B6": os.path.join(REF, "boss", "boss6.jfif"),
}

# Ink is the darkest thing on every plate by a wide margin: a value histogram
# of the bone wolf cell (E07, the darkest-shadowed minion) shows the outline's
# density peak below 0.24 and its painted-shadow density peak above 0.34, with
# a trough at 0.28-0.32 between them — 0.30 sits in that trough.
# Swept 0.10-0.70 against every plate while chasing a cream-pocket test failure
# on B4 and B3P2: the value made no difference at any point in that range, so
# there was no evidence to move off this measurement. Root cause turned out to
# be a real gap in the pose (shoulder/horn on B4, underarm on B3P2) fully
# enclosed by ink on both sides — not a broken outline — so no INK_V can close
# it without also destroying the outline elsewhere. Both are on the
# needs-new-art list; see tools/enemy_cutout_test.py's cream check, which
# correctly still fails on them.
INK_V = 0.30
# A real body part is large; smoke, spatter and the corner sparkle are not.
# Anything under this fraction of the biggest ink component is clutter.
KEEP_FRAC = 0.05
# Battle art tops out at 200px (`_enemy_art_budget()`), so 512 leaves 2.5x of
# headroom. The sheet cells come in well under this and are never upscaled —
# baking a resize in would only freeze the softening into the PNG.
MAX_H = 512


# --------------------------------------------------------------- subject

def subject_mask(rgb: np.ndarray) -> np.ndarray:
    """True where the creature is, found through its ink outline."""
    val = rgb.astype(np.float32).max(axis=2) / 255.0
    ink = val < INK_V
    lab, n = ndimage.label(ink, structure=np.ones((3, 3), bool))
    if n == 0:
        return np.zeros(rgb.shape[:2], bool)
    sizes = ndimage.sum(ink, lab, range(1, n + 1))
    keep = np.zeros(rgb.shape[:2], bool)
    for i, s in enumerate(sizes):
        if s >= sizes.max() * KEEP_FRAC:
            keep |= lab == i + 1
    return ndimage.binary_fill_holes(keep)


def cut_subject(img: Image.Image) -> Image.Image:
    """RGBA with everything but the creature removed and the edge cleaned."""
    rgb = np.asarray(img.convert("RGB"))
    mask = subject_mask(rgb)
    a = Image.fromarray(np.where(mask, 255, 0).astype(np.uint8), "L")
    # 1px erode then a soft blur: kills the pale halo the flat cream leaves on
    # the anti-aliased outline without visibly thinning the silhouette.
    a = a.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    out = np.asarray(img.convert("RGBA")).copy()
    out[:, :, 3] = np.asarray(a)
    # Decontaminate: partly-transparent pixels still carry JPEG cream, which
    # fringes pale once composited. Replace their colour with the nearest fully
    # opaque colour by dilating the interior outward three times.
    solid = np.asarray(a) > 240
    rgb_f = out[:, :, :3].astype(np.float32)
    for _ in range(3):
        grow = ndimage.binary_dilation(solid, np.ones((3, 3), bool)) & ~solid
        if not grow.any():
            break
        near = np.zeros_like(rgb_f)
        cnt = np.zeros(solid.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.roll(np.where(solid[:, :, None], rgb_f, 0.0), (dy, dx), (0, 1))
            shc = np.roll(solid.astype(np.float32), (dy, dx), (0, 1))
            near += sh
            cnt += shc
        take = grow & (cnt > 0)
        rgb_f[take] = (near[take] / cnt[take, None])
        solid = solid | take
    out[:, :, :3] = np.clip(rgb_f, 0, 255).astype(np.uint8)
    # fully transparent pixels go black so nothing bleeds on downscale
    out[:, :, :3] *= (out[:, :, 3:4] > 0)
    return Image.fromarray(out, "RGBA")


def trim(rgba: Image.Image, thresh: int = 8) -> Image.Image:
    a = np.asarray(rgba)[:, :, 3]
    ys, xs = np.where(a > thresh)
    if len(ys) == 0:
        return rgba
    return rgba.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def cap_height(rgba: Image.Image, h: int) -> Image.Image:
    """Shrink to `h` if taller. Never upscales."""
    if rgba.height <= h:
        return rgba
    return rgba.resize((max(1, round(rgba.width * h / rgba.height)), h), Image.LANCZOS)


def edge_band_rgb(rgba: np.ndarray, px: int = 3) -> list:
    """Mean colour of the outermost `px` of the silhouette — the band the rim
    light lands on, and so the band `_t_enemy_legibility` measures."""
    solid = rgba[:, :, 3] > 200
    inner = ndimage.binary_erosion(solid, np.ones((3, 3), bool), iterations=px)
    band = solid & ~inner
    if band.sum() < 20:
        band = solid
    return [int(v) for v in rgba[:, :, :3][band].mean(axis=0).round()]


# --------------------------------------------------------------- main

def load_all() -> dict:
    """Every key cut and trimmed, before any resizing."""
    cuts = {}
    sheet = Image.open(SHEET).convert("RGB")
    cw, ch = sheet.width // 3, sheet.height // 3
    for key, (r, c) in SHEET_CELLS.items():
        cell = sheet.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
        cuts[key] = trim(cut_subject(cell))
    for key, path in SOLO.items():
        cuts[key] = trim(cut_subject(Image.open(path).convert("RGB")))
    return cuts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hsv-report", action="store_true")
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    os.makedirs(QA, exist_ok=True)
    cuts = load_all()

    if args.hsv_report:
        from enemy_hsv import report          # added in Task 2
        return report(cuts)

    meta = {}
    extent = []
    for key in sorted(cuts):
        im = cap_height(cuts[key], MAX_H)
        im.save(os.path.join(OUT, key + ".png"))
        arr = np.asarray(im)
        meta[key] = {"size": [im.width, im.height],
                     "aspect": round(im.width / im.height, 4),
                     "edge_rgb": edge_band_rgb(arr)}
        extent.append('"%s": Vector2(1.00, %.2f)' % (key, im.width / im.height / 2.0))
        print("%-5s %4dx%-4d aspect=%.3f edge=%s"
              % (key, im.width, im.height, meta[key]["aspect"], meta[key]["edge_rgb"]))

    with open(os.path.join(OUT, "enemies.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2, sort_keys=True)
    print("PAWN_EXTENT: {" + ", ".join(extent) + "}")

    _contact(cuts)
    return 0


def _contact(cuts: dict) -> None:
    """Magenta checkerboard contact sheet — white fringes and leftover cream
    are invisible on a dark sheet and obvious on this one."""
    keys = sorted(cuts)
    cell, cols = 300, 6
    rows = (len(keys) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell))
    px = sheet.load()
    for y in range(sheet.height):
        for x in range(sheet.width):
            px[x, y] = (150, 40, 150, 255) if ((x // 24 + y // 24) % 2) else (70, 70, 80, 255)
    for i, k in enumerate(keys):
        im = cap_height(cuts[k], cell - 40)
        sheet.paste(im, ((i % cols) * cell + (cell - im.width) // 2,
                         (i // cols) * cell + 20), im)
    sheet.save(os.path.join(QA, "enemy_cutout_contact.png"))
    print("qa -> qa/enemy_cutout_contact.png")


if __name__ == "__main__":
    sys.exit(main())
