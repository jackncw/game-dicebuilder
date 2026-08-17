#!/usr/bin/env python
"""Copies the round-11 capture videos out of Playwright's hash-truncated
result dirs into qa/round11/<moment>.webm so the iteration log can point at
them.

    python tools/collect_caps.py
"""
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "web", "test-results")
DST = os.path.join(ROOT, "qa", "round11")

# dir-name fragment -> readable clip name (Playwright truncates long titles)
NAMES = [
    ("sign-drop", "menu"),
    ("one-more-run", "gameover"),
    ("banner-fog", "boss-intro"),
    ("light-column", "treasure"),
    ("battle-wipe", "map-walk"),
    ("enemy-beats", "battle-hits"),
    ("gold-roll-up", "reward"),
    ("victory", "victory"),
]


def main():
    os.makedirs(DST, exist_ok=True)
    n = 0
    for d in sorted(os.listdir(SRC)):
        if not d.startswith("round11cap"):
            continue
        video = os.path.join(SRC, d, "video.webm")
        if not os.path.exists(video):
            continue
        name = next((v for frag, v in NAMES if frag in d), None)
        if name is None:
            name = d[-24:]
        out = os.path.join(DST, name + ".webm")
        shutil.copyfile(video, out)
        print(f"  {name}.webm  {os.path.getsize(out)//1024} KB")
        n += 1
    print(f"{n} clips -> qa/round11/")


if __name__ == "__main__":
    main()
