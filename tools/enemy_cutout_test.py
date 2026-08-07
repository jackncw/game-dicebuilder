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

    return report()


def report():
    print("ENEMY CUTOUT: %d tests, %d failures" % (tests, fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
