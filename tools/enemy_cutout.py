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
# B4 and B3P2 initially failed the cream check with this value unchanged
# across a 0.10-0.70 sweep: their pockets (shoulder/horn on B4, both armpits
# on B3P2) are real background fully enclosed by ink on both sides, not a
# broken outline, so no INK_V closes them. That is a colour question, not an
# ink-threshold one — see `_background_pockets` below, which is what actually
# resolves them.
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
    filled = ndimage.binary_fill_holes(keep)
    # The subject is still found by ink alone; colour only adjudicates which
    # of fill_holes's *additions* (never the ink-kept pixels themselves) are
    # real background peeking through a pose gap — an armpit, a horn/shoulder
    # notch — versus a real enclosed body part (an eye socket, a shield boss).
    return filled & ~_background_pockets(rgb, filled & ~keep)


def _background_pockets(rgb: np.ndarray, holes: np.ndarray) -> np.ndarray:
    """Which connected pieces of `holes` are plate background (cream, or its
    cast shadow) rather than painted body interior.

    Two-part background test, both parts borrowed from `art_cutout._bg_mask`
    with the provenance it records, because a single flatness test cannot
    tell shadowed background from unshadowed background:

    - desaturated-and-light (`sat < 0.20 & val > 0.63`) — `_bg_mask`'s own
      candidate mask. Its comment there says the threshold "has to reach
      down into the shadow (which bottoms out near 0.66 value ... without
      being able to walk into the pale fur"; that is exactly the case here
      too. This is what actually clears E06's three pale coil pockets, which
      carry the bramble's own cast shadow and measure mean-difference 49-197
      from the plate's border median — nowhere near the flat test below.
    - flat and close to the plate's own border colour (`std < 14 &
      mean-difference < 6`, `_bg_mask`'s pocket check for the hare's bow) —
      covers clean, unshadowed cream, e.g. B4/B3P2's pose-gap pockets.

    A hole is background if either test passes on its 1px-eroded core (the
    ring where ink fades into background is neither ink nor flat plate, and
    on B4's real pocket alone it drags std from 5-8 to 26 — enough to falsely
    fail a genuinely flat cream pocket; erosion strips that ring, and the
    whole component, ring included, is dropped once its core passes — same
    as the outer silhouette's edge is cleaned up after the fact in
    `cut_subject`). The desaturated-and-light test is judged on the fraction
    of the core that qualifies, not the core's mean, so a real body part that
    merely borders a pale fleck does not get pulled in.
    """
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg_col = np.median(border.reshape(-1, 3), axis=0)
    f = rgb.astype(np.float32) / 255.0
    mx, mn = f.max(axis=2), f.min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    desat_light = (sat < 0.20) & (mx > 0.63)
    lab, n = ndimage.label(holes, structure=np.ones((3, 3), bool))
    pockets = np.zeros(rgb.shape[:2], bool)
    for i in range(1, n + 1):
        comp = lab == i
        core = ndimage.binary_erosion(comp, np.ones((3, 3), bool))
        core = core if core.any() else comp
        px = rgb[core].astype(np.float32)
        flat_bg = px.std(axis=0).max() < 14.0 and np.abs(px.mean(axis=0) - bg_col).max() < 6.0
        shadow_bg = desat_light[core].mean() > 0.9
        if flat_bg or shadow_bg:
            pockets |= comp
    return pockets


def cut_subject(img: Image.Image) -> Image.Image:
    """RGBA with everything but the creature removed and the edge cleaned."""
    rgb = np.asarray(img.convert("RGB"))
    mask = subject_mask(rgb)
    a = Image.fromarray(np.where(mask, 255, 0).astype(np.uint8), "L")
    # 1px erode: kills the pale halo the flat cream leaves on the
    # anti-aliased outline without visibly thinning the silhouette.
    a = a.filter(ImageFilter.MinFilter(3))
    # Clutter (a smoke wisp, a spatter fleck) can be 8-connected to the main
    # ink outline by a hairline anti-aliased touch, so it rides inside
    # `subject_mask`'s single largest-ink-component union and no KEEP_FRAC
    # ever sees it as separate. The erosion above severs that hairline and
    # leaves it as its own island. Measured across all 17 plates (connected
    # components of the resulting mask, 8-connected): 15 of 17 come out as
    # exactly one component; the two that don't (B2's two smoke wisps beside
    # the ear/glove, E05's antenna-adjacent flecks) are confirmed-by-eye
    # clutter, all under 1.1% of the body. No real anatomy anywhere in the
    # set separates this way — even E08's wraith hood, whose raw ink loop is
    # only a third the size of the body's, survives as one piece — so this
    # keeps the single largest component and drops everything else, with no
    # size threshold to tune.
    eroded = np.asarray(a) > 128
    lab, n = ndimage.label(eroded, structure=np.ones((3, 3), bool))
    if n > 1:
        sizes = ndimage.sum(eroded, lab, range(1, n + 1))
        main = int(np.argmax(sizes)) + 1
        a = Image.fromarray(np.where(lab == main, 255, 0).astype(np.uint8), "L")
    # Soft blur after the component filter, not before: blurring first would
    # let a severed island's soft edge creep back above the >128 threshold
    # used here.
    a = a.filter(ImageFilter.GaussianBlur(0.8))
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


# --------------------------------------------------------------- rot mask

# The corruption channels, baked here rather than recognised in the shader.
#
# The plates paint a lit eye and a corruption crack in the SAME value range —
# measured across the nine full-resolution plates, the eye's 25th percentile
# (0.49) and the crack's median (0.49) are the same number, and a split there
# misreads 48.9% of crack pixels as eye. What separates them is shape: an eye
# is a compact blob, a crack is a thin network. Two erosions delete the
# network and leave the blobs, which a fragment shader cannot do — it has no
# connected components. So the classification happens once, here, and the
# shader only samples the result.
#
# VAL_MIN exists because the ink outline is a dark maroon, not black: it lands
# inside the magenta hue band and, being dark, reports a high relative
# saturation. Without a value floor it is 56% of every "magenta" pixel counted.
MASK_HUE = (0.80, 0.91)
MASK_SAT_MIN = 0.45
MASK_VAL_MIN = 0.35
EMBER_HUE = (0.00, 0.10)
EMBER_SAT_MIN = 0.50
# Brown leather (B2's boxing gloves) sits in the ember hue band and outnumbers
# the lava toad's actual fissures. Lava is lit; leather is not.
EMBER_VAL_MIN = 0.62
EYE_ERODE = 2
EYE_MIN_PX = 20


def _hsv_planes(rgb: np.ndarray):
    f = rgb.astype(np.float32) / 255.0
    mx, mn = f.max(axis=2), f.min(axis=2)
    d = mx - mn
    h = np.zeros_like(mx)
    r, g, b = f[:, :, 0], f[:, :, 1], f[:, :, 2]
    nz = d > 1e-6
    i = nz & (mx == r)
    h[i] = ((g[i] - b[i]) / d[i]) % 6.0
    i = nz & (mx == g)
    h[i] = (b[i] - r[i]) / d[i] + 2.0
    i = nz & (mx == b)
    h[i] = (r[i] - g[i]) / d[i] + 4.0
    return h / 6.0, np.where(mx > 0, d / np.maximum(mx, 1e-6), 0.0), mx


def rot_mask(rgba: np.ndarray) -> Image.Image:
    """R = lit eye, G = corruption crack, B = lava ember."""
    h, s, v = _hsv_planes(rgba[:, :, :3])
    body = rgba[:, :, 3] > 200
    mag = (body & (h > MASK_HUE[0]) & (h < MASK_HUE[1])
           & (s > MASK_SAT_MIN) & (v > MASK_VAL_MIN))
    # blobs survive two erosions; thin crack networks do not
    core = ndimage.binary_erosion(mag, np.ones((3, 3), bool), iterations=EYE_ERODE)
    core = ndimage.binary_dilation(core, np.ones((3, 3), bool),
                                   iterations=EYE_ERODE) & mag
    lab, n = ndimage.label(core)
    eye = np.zeros_like(mag)
    if n:
        sizes = ndimage.sum(core, lab, range(1, n + 1))
        keep = [i + 1 for i, z in enumerate(sizes) if z >= EYE_MIN_PX]
        if keep:
            eye = np.isin(lab, keep)
    ember = (body & (h < EMBER_HUE[1]) & (s > EMBER_SAT_MIN) & (v > EMBER_VAL_MIN))
    out = np.zeros(rgba.shape[:2] + (3,), np.uint8)
    out[:, :, 0] = np.where(eye, 255, 0)
    out[:, :, 1] = np.where(mag & ~eye, 255, 0)
    out[:, :, 2] = np.where(ember, 255, 0)
    return Image.fromarray(out, "RGB")


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

        mask_im = rot_mask(arr)
        mask_im.save(os.path.join(OUT, key + "_rot.png"))
        mask_arr = np.asarray(mask_im)
        rot_px = {"eye": int((mask_arr[:, :, 0] > 128).sum()),
                  "vein": int((mask_arr[:, :, 1] > 128).sum()),
                  "ember": int((mask_arr[:, :, 2] > 128).sum())}

        meta[key] = {"size": [im.width, im.height],
                     "aspect": round(im.width / im.height, 4),
                     "edge_rgb": edge_band_rgb(arr),
                     "rot_px": rot_px}
        extent.append('"%s": Vector2(1.00, %.2f)' % (key, im.width / im.height / 2.0))
        print("%-5s %4dx%-4d aspect=%.3f edge=%s rot_px=%s"
              % (key, im.width, im.height, meta[key]["aspect"], meta[key]["edge_rgb"], rot_px))

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
