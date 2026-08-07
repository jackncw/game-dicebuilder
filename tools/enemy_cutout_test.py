#!/usr/bin/env python3
"""Self-checking suite for tools/enemy_cutout.py. No pytest on this box, so it
prints its own tally in the same shape as the GDScript suites:
    ENEMY CUTOUT: 9 tests, 0 failures
Run it AFTER the pipeline: python tools/enemy_cutout.py && python tools/enemy_cutout_test.py
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "enemies")
KEYS = ["E%02d" % i for i in range(1, 11)] + ["B1", "B2", "B3", "B4", "B5", "B6", "B3P2"]

# The eight sheet-sourced minions (`SHEET_CELLS` in enemy_cutout.py) come from
# ~250px cells of a 3x3 collection JPEG. JPEG compression at that size mashes
# fine cracks and small eyes into flat grey, so their measured eye+vein share
# of the body falls well under the 1.5% floor below — measured by running
# this file's own check (2026-08-07, eye+vein px from `_rot.png` / body px
# where sprite alpha>200):
#   E01 1.05%  E02 0.73%  E03 0.59%  E04 0.28%
#   E07 0.22%  E08 0.66%  E09 0.85%  E10 0.69%
# The nine full-resolution 1024px solo/boss plates all clear 1.5% (2.17%-
# 7.29%: B1 2.71% B2 2.84% B3 2.17% B3P2 3.45% B4 2.59% B5 4.38% B6 7.29%
# E05 3.32% E06 4.42%), so this is a resolution artifact of the sheet, not a
# property of these creatures' designs. Replacement 1024x1024 solo plates are
# requested per docs/design/2026-08-07-enemy-sprite-art.md 需要補圖清單. Each
# key is removed from this dict the moment its replacement plate lands in
# `tools/enemy_cutout.py`'s SOLO dict — do NOT lower the 1.5% floor and do
# NOT add a key here without a measured number to back it.
PENDING_ART = {
    "E01": "sheet cell, measured 1.05% eye+vein",
    "E02": "sheet cell, measured 0.73% eye+vein",
    "E03": "sheet cell, measured 0.59% eye+vein",
    "E04": "sheet cell, measured 0.28% eye+vein",
    "E07": "sheet cell, measured 0.22% eye+vein",
    "E08": "sheet cell, measured 0.66% eye+vein",
    "E09": "sheet cell, measured 0.85% eye+vein",
    "E10": "sheet cell, measured 0.69% eye+vein",
}
ROT_MIN_PCT = 1.5

# Ceilings: the floor above catches too little eye/vein material; nothing
# caught too much, which is exactly the direction the bug this task fixes
# ran in (loosen MASK_VAL_MIN or drop an erosion and the ink outline reads
# back in as rot material, so the percentage goes UP and the floor alone
# still passes, or passes more easily). Two ceilings, not one, because the
# two groups' legitimate ranges are different orders of magnitude and a
# single ceiling loose enough for the nine full-resolution plates would be
# useless against a regression on the eight low-res sheet cells.
#
# ROT_MAX_PCT (full-resolution plates): measured today (2026-08-07) the nine
# non-PENDING_ART keys range 2.17% (B3) to 7.29% (B6, the most heavily-
# corrupted boss) eye+vein of body. 9.0 leaves ~23% headroom above that
# measured max. Demonstrated to bite (see task-2-report.md): setting
# MASK_VAL_MIN = 0.0 and re-baking pushes all nine to 9.96%-22.19% -- every
# one clears this ceiling, none come close.
ROT_MAX_PCT = 9.0
# ROT_MAX_PCT_PENDING (sheet cells): their legitimate range today is
# 0.22%-1.05% (see PENDING_ART's comment) -- an order of magnitude below the
# full-resolution plates, because sheet-cell JPEG compression mashes fine
# eye/crack detail into flat grey. Demonstrated to bite the same way: the
# MASK_VAL_MIN = 0.0 re-bake pushes all eight PENDING_ART keys to
# 3.66%-26.05%, clearing 2.0 with room to spare.
ROT_MAX_PCT_PENDING = 2.0

tests = 0
fails = 0


def check(cond, msg):
    global tests, fails
    tests += 1
    if not cond:
        fails += 1
        print("  FAIL: " + msg)


def main():
    check(os.path.isdir(OUT), "assets/enemies/ exists")
    if not os.path.isdir(OUT):
        return report()

    meta_path = os.path.join(OUT, "enemies.json")
    check(os.path.isfile(meta_path), "enemies.json written")
    meta = json.load(open(meta_path, encoding="utf-8")) if os.path.isfile(meta_path) else {}

    missing = [k for k in KEYS if not os.path.isfile(os.path.join(OUT, k + ".png"))]
    check(not missing, "all 17 sprites written, missing=%s" % missing)

    for k in KEYS:
        p = os.path.join(OUT, k + ".png")
        if not os.path.isfile(p):
            continue
        rgba = np.asarray(Image.open(p).convert("RGBA"))
        a = rgba[:, :, 3]

        # trimmed to alpha bounds: every outer edge of the canvas is touched
        touched = (a[0].max() > 8 and a[-1].max() > 8
                   and a[:, 0].max() > 8 and a[:, -1].max() > 8)
        check(touched, "%s is trimmed to its alpha bounds" % k)

        # no cream left anywhere opaque — this is the vine-pocket regression
        op = a > 200
        if op.sum():
            px = rgba[:, :, :3][op].astype(np.float32) / 255.0
            mx, mn = px.max(axis=1), px.min(axis=1)
            sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
            cream = (sat < 0.12) & (mx > 0.85)
            check(cream.mean() < 0.005,
                  "%s has %.2f%% cream pixels left inside it" % (k, 100 * cream.mean()))

        # one subject, not a subject plus floating debris. 8-connected to
        # match the pipeline's own component labelling; ANY extra component
        # counts as debris regardless of size — a 0.01%-of-body smoke wisp
        # is exactly the defect this check exists to catch, and a window
        # that only looked at 2%-50% missed two of them (B2, E05) twice.
        lab, n = ndimage.label(a > 128, structure=np.ones((3, 3), bool))
        if n:
            sizes = ndimage.sum(a > 128, lab, range(1, n + 1))
            debris = sorted(sizes)[:-1]
            check(not debris,
                  "%s has %d detached fragment(s) besides the main body: %s"
                  % (k, len(debris), [int(s) for s in debris]))

        # metadata agrees with the file on disk
        if k in meta:
            h, w = a.shape
            check(meta[k]["size"] == [w, h], "%s enemies.json size matches the PNG" % k)

        # --- rot mask (eye/vein/ember bake) ---
        rot_p = os.path.join(OUT, k + "_rot.png")
        check(os.path.isfile(rot_p), "%s has a _rot.png mask" % k)
        if not os.path.isfile(rot_p):
            continue
        rot = np.asarray(Image.open(rot_p).convert("RGB"))
        check(rot.shape[:2] == a.shape, "%s _rot.png size matches its sprite" % k)
        if rot.shape[:2] != a.shape:
            continue

        eye = rot[:, :, 0] > 128
        vein = rot[:, :, 1] > 128
        ember = rot[:, :, 2] > 128
        # a pixel cannot be both a lit eye and a corruption crack, etc.
        overlap = (eye & vein) | (eye & ember) | (vein & ember)
        check(not overlap.any(),
              "%s rot mask channels overlap on %d px" % (k, int(overlap.sum())))

        # Shape control: B1 is the one sprite whose eye channel has been
        # verified pixel-by-pixel against the source art (task-2-report.md)
        # -- two small blobs sitting on the rabbit's two eye sockets, nothing
        # else, measured today as 2 connected components (218 px + 95 px).
        # The floor/ceiling above are a colour-volume signal; this is the
        # shape signal the review asked for, because it is what would
        # actually change if the ink outline (a long thin network, not a
        # blob) were readmitted: setting MASK_VAL_MIN = 0.0 and re-baking
        # turns B1's eye channel from 2 components into 39.
        if k == "B1":
            _, n_eye_comp = ndimage.label(eye, structure=np.ones((3, 3), bool))
            check(n_eye_comp == 2,
                  "B1 eye channel has %d connected component(s), expected "
                  "exactly 2 (the rabbit's eye sockets -- a regression toward "
                  "the ink-outline bug fragments this into dozens)" % n_eye_comp)

        body = int((a > 200).sum())
        pct = 100.0 * (eye.sum() + vein.sum()) / max(body, 1)
        if k in PENDING_ART:
            # Not enforced yet — see PENDING_ART's comment. Still printed so
            # the debt is visible in every run, not just the summary line.
            print("  PENDING_ART: %s eye+vein=%.2f%% of body (< %.1f%%, exempt: %s)"
                  % (k, pct, ROT_MIN_PCT, PENDING_ART[k]))
            check(pct <= ROT_MAX_PCT_PENDING,
                  "%s eye+vein is %.2f%% of body, need <= %.1f%% (regression "
                  "ceiling for sheet cells -- a runaway classification blows "
                  "well past this, see ROT_MAX_PCT_PENDING's comment)"
                  % (k, pct, ROT_MAX_PCT_PENDING))
        else:
            check(pct >= ROT_MIN_PCT,
                  "%s eye+vein is %.2f%% of body, need >= %.1f%% "
                  "(tier-progression glow has nothing to light up below this)"
                  % (k, pct, ROT_MIN_PCT))
            check(pct <= ROT_MAX_PCT,
                  "%s eye+vein is %.2f%% of body, need <= %.1f%% (regression "
                  "ceiling -- a runaway classification blows well past this, "
                  "see ROT_MAX_PCT's comment)"
                  % (k, pct, ROT_MAX_PCT))

        if k in meta and "rot_px" in meta[k]:
            rp = meta[k]["rot_px"]
            check(rp["eye"] == int(eye.sum()) and rp["vein"] == int(vein.sum())
                  and rp["ember"] == int(ember.sum()),
                  "%s enemies.json rot_px matches the mask PNG" % k)

    stale = [k for k in PENDING_ART if k not in KEYS]
    check(not stale, "PENDING_ART only names real keys, stale=%s" % stale)
    print("PENDING_ART: %d/%d keys still exempt from the eye+vein>=%.1f%% "
          "check pending replacement art: %s"
          % (len(PENDING_ART), len(KEYS), ROT_MIN_PCT, sorted(PENDING_ART)))

    return report()


def report():
    print("ENEMY CUTOUT: %d tests, %d failures" % (tests, fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
