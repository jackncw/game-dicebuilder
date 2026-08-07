#!/usr/bin/env python3
"""HSV census of the cut enemy sprites, so the rot shader's colour gates are
measured rather than guessed.

The shader tells four kinds of pixel apart by hue/sat/value alone:
    eye     bright saturated magenta
    vein    the same magenta, darker — the corruption cracks
    ember   saturated orange, the lava toad only (heat, not rot)
    body    everything else
This prints where each one actually sits, and where the gaps between them are.
No gap means the shader cannot separate them and the approach has to change.
"""

import numpy as np

# ============================================================================
# MEASURED BOUNDARIES — read from `python tools/enemy_cutout.py --hsv-report`
# on the 17 cut sprites in `assets/enemies/` (2026-08-07). Task 3 copies these
# numbers into shader uniform defaults verbatim; do not touch them without
# rerunning the report and updating the evidence below.
#
# Reference paint colours (`scripts/ui/ui_theme.gd`), converted to HSV for
# comparison against the measured clusters:
#   ROT_VEIN     #e13cc0  hue=0.867 sat=0.733 val=0.882
#   ROT_VEIN_DIM #a83a90  hue=0.870 sat=0.655 val=0.659
#   ROT_EYE      #ff5ad8  hue=0.873 sat=0.647 val=1.000
#   ROT_EYE_DIM  #d34aae  hue=0.878 sat=0.649 val=0.827
#   EMBER        #ff8a3c  hue=0.067 sat=0.765 val=1.000
#
# --- HUE_LO / HUE_HI (magenta rot family: eye + vein together) ---
# The report's own printed magenta band (hue 0.75-1.00, no value floor) is
# NOT usable as the shader's hue gate: it is 94.20% of every opaque pixel on
# the whole sprite set, because the ink outline itself is painted a dark
# maroon, not neutral black, and that outline's hue sits in the same 0.78-0.90
# range as the intentional rot paint (sampled outline pixels: h=0.781-0.902).
# Confirmed by eye: overlaying `hue>0.75 & sat>0.45 & val<0.15` on B1/E07/E09
# highlights each creature's *entire linework*, not its corruption veins.
# Restricting to bright, saturated pixels only (`sat>0.45 & val>0.65`, i.e.
# excluding anything the ink line could produce) removes that contamination
# and shows a genuinely tight, near-empty-gapped cluster: a 40-bin hue
# histogram of that set has 99.3% of its mass (32540 / 32800 px) in bins
# 0.825-0.900, centred exactly on the reference paints (0.867-0.878), with
# hard zero density from 0.100 to 0.800. HUE_LO/HUE_HI below pad that
# measured span with margin on both sides while staying clear of the ember
# cluster (0.000-0.075) and a small toad-only near-red cluster at 0.95-1.00
# (see EMBER_HUE note). This *narrows* the brief's starting guess (0.78-0.97)
# — the wider guess would have re-admitted some of the ink-outline and
# near-red contamination this measurement was built to exclude.
HUE_LO = 0.80
HUE_HI = 0.91

# --- SAT_MIN ---
# The brief's literal recipe (p5 of the raw magenta-band saturation, no value
# floor) measures 0.160 — useless as a floor, since it is dragged down by the
# same ink-outline contamination as HUE_LO/HUE_HI (dark linework pixels are
# desaturated relative to true paint). Measured properly, on the same
# bright+magenta-hue set used above (hue 0.80-0.91, val>0.65, no sat filter
# yet): saturation there is p1=0.477, p5=0.581, p50=0.769 — i.e. once a pixel
# is confirmed bright and magenta-hued, it is already almost always highly
# saturated (only 224 / 32800 px, 0.68%, fall below 0.45 at all). This
# confirms the brief's starting guess: 0.45 sits just below the measured p1
# (0.477), so it keeps effectively all real paint while still being well
# above the desaturated body/shadow tones the sat gate exists to reject
# elsewhere in the hue band.
SAT_MIN = 0.45

# --- EYE_VAL — GATE FAILED. No boundary is recorded; do not invent one. ---
# The report's required histogram (`val histogram of magenta sat>0.45`, the
# exact one printed below) is NOT the bimodal eye/vein split the brief
# expected. It has one dominant peak at val 0.05-0.10 (359,264 px, the ink
# outline again — same contamination as above, confirmed by the B1/E07/E09
# overlay) that decays roughly monotonically through the rest of the range.
# Even the most charitable reading — treating the 0.40-0.45 bin (22,526 px)
# as a "vein" peak and the 0.95-1.00 bin (3,753 px) as an "eye" peak — fails
# the brief's own gate (trough floor < half of *both* neighbouring peaks):
# the intervening local minimum, the 0.85-0.90 bin, is 2,079 px, and half of
# the smaller peak (3,753) is 1,876.5 — 2,079 sits above that, not below it.
# There is no bin anywhere in 0.65-1.00 that clears the bar. Restricting to
# val>=0.30 (excluding the ink outline via the pipeline's own INK_V=0.30) does
# not rescue this in aggregate either: the sum across all 17 sprites is still
# a single peak at 0.40-0.45 (22,526) decaying to 2,079 at 0.85-0.90 with no
# second peak of comparable size. A handful of individual sprites (e.g. B2,
# whose reference-matching bright pink eyes and darker magenta veins are
# visibly distinct by eye) show a plausible per-sprite trough once ink is
# excluded, but this does not hold sprite-to-sprite (E07 has zero bright
# magenta pixels at all) and cannot be collapsed into one global value.
# CONCLUSION: value alone does not separate "eye" from "corruption vein"
# across this sprite set. A shader gate driven by a single EYE_VAL constant
# cannot be built from this data as specified; Task 3 needs a different
# signal (e.g. per-creature authored eye masks, which the "no hand-authored
# per-creature data" premise was trying to avoid) or a redefinition of what
# "eye" vs "vein" means for the tier shader. See task-2-report.md for detail.
EYE_VAL = None

# --- EMBER_HUE (lava toad's cracks; must stay out of the magenta gamut) ---
# Measured: within the same bright+saturated population used above, the
# ember cluster is hue 0.000-0.075 (935+328+123 = 1,386 px), centred on the
# reference EMBER hue (0.067), with hard separation from the magenta cluster
# (nothing at all between hue 0.100 and 0.800). That part of the "previous
# design round" decision holds up. EMBER_HUE_LO/HI below pad that span.
# Two caveats found while measuring, for Task 3 to account for:
#  1) The toad (E09) alone also produces 831 bright/saturated px at hue
#     0.95-1.00 — a near-pure-red highlight cluster, circularly closer to
#     EMBER (hue distance 0.08) than to ROT_EYE (hue distance 0.11). A hue
#     gate that treats HUE_HI=1.00 as "magenta" would misclassify these as
#     rot-eye pixels; this file's HUE_HI=0.91 already excludes them, but a
#     shader implementation must not silently widen that bound back to 1.0.
#  2) Hue+sat alone does not restrict "ember-coloured" to the lava toad only:
#     B2 (the boxer hare, no lava theme) has more orange-hue/sat>0.45 pixels
#     (19,704, its boxing-glove leather) than E09 itself (2,503). If Task 3
#     needs ember confined to the toad, colour alone is not sufficient gating
#     — it will also light up B2's gloves.
EMBER_HUE_LO = 0.00
EMBER_HUE_HI = 0.10


def _hsv(rgb: np.ndarray) -> np.ndarray:
    f = rgb.astype(np.float32) / 255.0
    mx, mn = f.max(axis=1), f.min(axis=1)
    d = mx - mn
    h = np.zeros_like(mx)
    r, g, b = f[:, 0], f[:, 1], f[:, 2]
    nz = d > 1e-6
    idx = nz & (mx == r)
    h[idx] = ((g[idx] - b[idx]) / d[idx]) % 6.0
    idx = nz & (mx == g)
    h[idx] = (b[idx] - r[idx]) / d[idx] + 2.0
    idx = nz & (mx == b)
    h[idx] = (r[idx] - g[idx]) / d[idx] + 4.0
    return np.stack([h / 6.0, np.where(mx > 0, d / np.maximum(mx, 1e-6), 0.0), mx], 1)


def _pct(a, qs=(1, 5, 50, 95, 99)):
    return "  ".join("p%d=%.3f" % (q, np.percentile(a, q)) for q in qs) if len(a) else "(none)"


def report(cuts: dict) -> int:
    rows = []
    for key in sorted(cuts):
        arr = np.asarray(cuts[key])
        px = arr[:, :, :3][arr[:, :, 3] > 200]
        if len(px):
            rows.append((key, _hsv(px)))

    allp = np.concatenate([h for _, h in rows])
    hue, sat, val = allp[:, 0], allp[:, 1], allp[:, 2]

    # magenta band: hue 0.78-0.97 is where ROT_VEIN (#e13cc0) and ROT_EYE
    # (#ff5ad8) both land. Widened either side so the census can show whether
    # the painted pixels really cluster there.
    mag = (hue > 0.75) & (hue < 1.0)
    orange = (hue > 0.00) & (hue < 0.13)
    print("=== all opaque pixels: %d" % len(allp))
    print("hue   ", _pct(hue))
    print("sat   ", _pct(sat))
    print("val   ", _pct(val))
    print("\n=== magenta-band pixels (hue 0.75-1.00): %d (%.2f%%)"
          % (mag.sum(), 100.0 * mag.mean()))
    print("  sat ", _pct(sat[mag]))
    print("  val ", _pct(val[mag]))
    hot = mag & (sat > 0.45)
    print("  of those, sat>0.45: %d" % hot.sum())
    print("  their val", _pct(val[hot]))
    print("  --> eye/vein split goes in the val trough above")
    print("\n=== orange-band pixels (hue 0.00-0.13): %d" % orange.sum())
    print("  sat ", _pct(sat[orange]))

    print("\n=== per sprite: %% magenta sat>0.45, and its val p50/p95")
    for key, h in rows:
        m = (h[:, 0] > 0.75) & (h[:, 2] > 0) & (h[:, 1] > 0.45)
        v = h[m][:, 2]
        print("  %-5s %5.2f%%  %s" % (key, 100.0 * m.mean(), _pct(v, (50, 95))))

    # the histogram the split is read off
    print("\n=== val histogram of magenta sat>0.45 (the eye/vein trough)")
    hist, edges = np.histogram(val[hot], bins=20, range=(0.0, 1.0))
    for i, c in enumerate(hist):
        print("  %.2f-%.2f %7d %s" % (edges[i], edges[i + 1], c, "#" * int(60 * c / max(hist.max(), 1))))
    return 0
