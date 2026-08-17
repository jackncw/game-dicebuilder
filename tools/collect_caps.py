#!/usr/bin/env python
"""Copies the round-11 capture videos out of Playwright's hashed result dirs
into qa/round11/<moment>.webm so the iteration log can point at them.

    python tools/collect_caps.py
"""
import os
import re
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "web", "test-results")
DST = os.path.join(ROOT, "qa", "round11")


def main():
    os.makedirs(DST, exist_ok=True)
    n = 0
    for d in sorted(os.listdir(SRC)):
        m = re.match(r"round11cap.*round11-moment-capture-([a-z0-9-]+?)(-chromium.*)?$", d)
        if not m:
            continue
        video = os.path.join(SRC, d, "video.webm")
        if not os.path.exists(video):
            continue
        name = m.group(1)
        out = os.path.join(DST, name + ".webm")
        shutil.copyfile(video, out)
        print(f"  {name}.webm  {os.path.getsize(out)//1024} KB")
        n += 1
    print(f"{n} clips -> qa/round11/")


if __name__ == "__main__":
    main()
