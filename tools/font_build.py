#!/usr/bin/env python3
"""Builds `assets/fonts/DiceGroveSans-Regular.ttf` — the game's only font.

    python tools/font_build.py           # needs network, ~15MB of downloads

Why the game ships a font at all
--------------------------------
It did not, until the Web build. On Windows, Godot's bundled Noto Sans covers
the Latin text and the OS quietly supplies a fallback for everything else, so
the Chinese renders from Microsoft JhengHei and nobody notices. A browser has no
system font to fall back to: the first web export came out with every Chinese
glyph as a tofu box, title included. So the glyphs the game uses have to travel
with the game.

Why it is built rather than downloaded whole
--------------------------------------------
Noto Sans TC is 5.7MB as a subset OTF and 12MB as the variable TTF. The game
draws 959 distinct CJK characters. Cutting the face down to the glyphs actually
used takes it to ~390KB, which matters when the whole web payload is ~46MB and
the font is on the critical path for the first frame of text.

Why three faces get merged
--------------------------
Noto Sans TC does not have every glyph the UI types. Measured, not guessed:
    U+2726 ✦  cast-zone header      -> Noto Sans Symbols 2
    U+2715 ✕  / U+2717 ✗            -> Noto Sans Symbols 2
    U+1F4B0 💰 gold chip            -> Noto Sans Symbols 2
    U+1F9EA 🧪 potion chip          -> Noto Emoji
    U+2B6E ⭮  reroll counter        -> Noto Sans Symbols 2
U+21BB ↻, which the reroll counter used before, is in NONE of the Noto faces —
it was only ever rendering because Windows had Segoe UI Symbol. It is replaced
in `screen_battle.gd` by U+2B6E, the same arrow in a shippable font.

Godot can chain fallback fonts, which would avoid the merge, but the fallback
list lives in a `.import` file that has to be hand-edited outside the editor and
fails silently when it is wrong. One file with a verified cmap is checkable:
this script asserts the coverage it claims and refuses to write a face that
misses a glyph the project uses.

All three sources are SIL OFL 1.1; the licence travels in assets/fonts/OFL.txt.
"""
import os
import subprocess
import sys
import urllib.request

from fontTools.merge import Merger
from fontTools.ttLib import TTFont
from fontTools.ttLib.scaleUpem import scale_upem
from fontTools.varLib import instancer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "fonts", "DiceGroveSans-Regular.ttf")
LICENCE = os.path.join(ROOT, "assets", "fonts", "OFL.txt")
WORK = os.path.join(ROOT, "art_export", "fontwork")

GH = "https://github.com/google/fonts/raw/main/ofl/"
SOURCES = {
    "tc": GH + "notosanstc/NotoSansTC%5Bwght%5D.ttf",
    "sym": GH + "notosanssymbols2/NotoSansSymbols2-Regular.ttf",
    "emo": GH + "notoemoji/NotoEmoji%5Bwght%5D.ttf",
}
LICENCE_URL = "https://github.com/notofonts/noto-cjk/raw/main/Sans/LICENSE"

# Directories that hold no shipped text: reference art, screenshot output,
# the exported build itself.
SKIP_DIRS = {".git", ".godot", "art_iterations", "art_export", "final",
             "final_round1", "qa", "docs", "__pycache__", "Art reference"}
# Typed at runtime rather than sitting in a source file, so the scan cannot see
# them: digits and punctuation the UI composes, plus the reroll arrow.
EXTRA = ("×·—–…“”‘’「」『』()《》【】、。,.!?:;%+-/"
         "✦♦●○■□▲▼◀▶★☆∞⭮✓✕✗")


def used_glyphs() -> set:
    chars = set()
    for root, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if not f.endswith((".gd", ".json", ".tscn", ".godot")):
                continue
            try:
                chars.update(open(os.path.join(root, f), encoding="utf-8").read())
            except (OSError, UnicodeDecodeError):
                pass
    chars = {c for c in chars if c.isprintable() and not c.isspace()}
    chars.update(chr(c) for c in range(0x20, 0x7F))
    chars.update(EXTRA)
    chars.discard("↻")          # see the module docstring
    return chars


def fetch(url: str, path: str) -> str:
    if not os.path.isfile(path):
        print("  downloading %s" % os.path.basename(path))
        urllib.request.urlretrieve(url, path)
    return path


def flatten(path: str) -> str:
    """A static 400-weight face at 1000 upem, with no variation data left."""
    f = TTFont(path)
    if "fvar" in f:
        f = instancer.instantiateVariableFont(f, {"wght": 400}, inplace=False,
                                              updateFontNames=False)
    for t in ("fvar", "gvar", "avar", "HVAR", "VVAR", "MVAR", "STAT", "cvar",
              # BASE is the one table carrying an ItemVariationStore after
              # instancing, and fontTools.merge has no merger for it. It only
              # holds script baseline offsets; Godot lays out from hhea/OS-2.
              "BASE", "DSIG"):
        if t in f:
            del f[t]
    if f["head"].unitsPerEm != 1000:
        scale_upem(f, 1000)
    out = path.replace(".ttf", ".flat.ttf")
    f.save(out)
    return out


def cut(src: str, chars: set, out: str) -> str:
    txt = out + ".chars.txt"
    open(txt, "w", encoding="utf-8").write("".join(sorted(chars)))
    subprocess.run([sys.executable, "-m", "fontTools.subset", src,
                    "--text-file=" + txt, "--output-file=" + out,
                    "--layout-features=*", "--notdef-outline",
                    "--recalc-bounds", "--drop-tables+=DSIG"], check=True)
    return out


def main() -> int:
    os.makedirs(WORK, exist_ok=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    want = used_glyphs()
    print("project uses %d distinct glyphs (%d CJK)"
          % (len(want), len([c for c in want if ord(c) >= 0x2E80])))

    flat = {}
    for key, url in SOURCES.items():
        flat[key] = flatten(fetch(url, os.path.join(WORK, key + ".ttf")))
    fetch(LICENCE_URL, LICENCE)

    # Each face supplies only what the ones before it could not, so no glyph is
    # contributed twice and the merge has nothing to arbitrate.
    parts = []
    left = set(want)
    for key in ("tc", "sym", "emo"):
        cov = set(TTFont(flat[key]).getBestCmap())
        mine = {c for c in left if ord(c) in cov}
        left -= mine
        print("  %-3s supplies %4d glyphs" % (key, len(mine)))
        if mine:
            parts.append(cut(flat[key], mine, os.path.join(WORK, "part_%s.ttf" % key)))
    if left:
        print("REFUSING TO WRITE: no Noto face has %s"
              % sorted(hex(ord(c)) for c in left))
        return 1

    ref = TTFont(parts[0])
    hhea = (ref["hhea"].ascent, ref["hhea"].descent, ref["hhea"].lineGap)
    os2 = (ref["OS/2"].sTypoAscender, ref["OS/2"].sTypoDescender,
           ref["OS/2"].sTypoLineGap, ref["OS/2"].usWinAscent,
           ref["OS/2"].usWinDescent)

    merged = Merger().merge(parts)
    # fontTools.merge takes the first font's metrics, but restating them makes
    # that checkable rather than assumed. Line height is a layout input: every
    # screenshot and every `layout_test` bound was measured against these.
    merged["head"].unitsPerEm = 1000
    (merged["hhea"].ascent, merged["hhea"].descent, merged["hhea"].lineGap) = hhea
    (merged["OS/2"].sTypoAscender, merged["OS/2"].sTypoDescender,
     merged["OS/2"].sTypoLineGap, merged["OS/2"].usWinAscent,
     merged["OS/2"].usWinDescent) = os2
    merged["name"].setName("Dice Grove Sans", 1, 3, 1, 0x409)
    merged["name"].setName("Regular", 2, 3, 1, 0x409)
    merged["name"].setName("DiceGroveSans-Regular", 4, 3, 1, 0x409)
    merged["name"].setName("DiceGroveSans-Regular", 6, 3, 1, 0x409)
    merged.save(OUT)

    cmap = set(TTFont(OUT).getBestCmap())
    missing = sorted(hex(ord(c)) for c in want if ord(c) not in cmap)
    print("wrote %s (%d bytes, %d glyphs)" % (OUT, os.path.getsize(OUT), len(cmap)))
    print("coverage gap: %s" % (missing or "none"))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
