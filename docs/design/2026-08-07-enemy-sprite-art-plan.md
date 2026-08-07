# 敵人 sprite 美術 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 10 隻小怪 + 6 隻 boss(連 B3 第二階段)由 `pawn_art.gd` 嘅程序繪圖,換成由 `Art reference/` 嘅 AI 生成圖裁出嚟嘅 sprite,tier 差異同暗底可讀性全部靠 shader 同粒子疊加。

**Architecture:** Python pipeline 用「墨線輪廓 + 填內部」由參考圖切出 17 張透明 PNG;`PawnArt` 由 `_draw_*` 程序繪圖改成走同主角一樣嘅貼圖路;一個 `canvas_item` shader 認出圖入面本身已經係洋紅/橙嘅像素做眼同腐化紋發光,再喺 alpha 邊界疊內側 rim light。

**Tech Stack:** Godot 4.7.1(GDScript)、Python 3.14 + numpy 2.5.1 / scipy 1.18.0 / Pillow 12.3.0(全部已安裝,**唔准加新依賴**;冇 pytest,Python 測試自己 print OK/FAIL)。

設計來源:`docs/design/2026-08-07-enemy-sprite-art.md`

## Global Constraints

- **鐵律:唔准手畫任何生物造型。** 准裁切、去背、縮放、色調、疊特效;唔准畫、改、補任何生物身體形狀。缺圖入補圖清單,唔准自己畫住頂檔。
- `Art reference/` 底下所有原圖**唯讀**,一個 byte 都唔准改。
- **只改視覺。** `scripts/core/` 任何檔案、`battle_core`、任何數值表一行都唔准郁。
- Godot binary: `C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe`
- Windows Godot exe 會脫離 console:一定要用 `--log-file`,等 process 完再讀 log。`tools/run.sh <log-name> <scene> [args]` 已經包咗。
- **要真視窗(唔准 `--headless`)**:任何 `await RenderingServer.frame_post_draw` 嘅工具 —— `pawn_extents`、`pawn_gallery`、`gallery_export`、新嘅 `enemy_legibility`。headless 之下 `frame_post_draw` 永遠唔會 fire,會 hang 到 timeout 然後寫零張圖。
- 加咗新 `class_name` 之後要跑一次 `Godot --headless --path . --import`,唔係依賴嗰啲 script 會 "Could not find type"。
- 可讀性門檻:**2.4:1**,維持不變。
- 代理 vs 真 render 校正門檻:**0.15:1**。超過就以真 render 為準,返轉頭校代理公式。
- 全部 12 個現有測試套件要綠:`bash tools/test_all.sh`。

---

## File Structure

**新增**

| 檔案 | 責任 |
|---|---|
| `tools/enemy_cutout.py` | 由參考圖切 17 張敵人 PNG,輸出 `enemies.json` 同 QA 圖。唯一掂原圖嘅嘢。 |
| `tools/enemy_cutout_test.py` | 上面嗰個嘅自檢套件(冇 pytest,自己 print)。 |
| `assets/shaders/rot_pawn.gdshader` | 認色發光 + 內側 rim。專案第一個 shader。 |
| `tools/enemy_legibility.gd` + `.tscn` | 真 render 量輪廓可辨性,同代理對數。 |
| `assets/enemies/*.png` × 17 | pipeline 產物。 |
| `assets/enemies/enemies.json` | 每隻嘅 aspect + 邊緣帶平均色,代理測試讀佢。 |

**修改**

| 檔案 | 改乜 |
|---|---|
| `scripts/ui/pawn_art.gd` | 刪 18 個 `_draw_*` 造型 routine 同只服務佢哋嘅 primitive;加 `ENEMY_TEX`、`chapter`、shader material、自動黑霧。 |
| `scripts/ui/ui_theme.gd` | 加 `rot_rim_for(chapter)` —— rim 強度嘅單一真源。 |
| `scripts/ui/screen_battle.gd` | `PawnArt.fitted(...)` 傳埋 chapter。 |
| `scripts/ui/screen_codex.gd` | 同上(tier strip + boss strip)。 |
| `tests/ui_smoke.gd` | `_t_enemy_legibility()` 改用代理量法;加 `_t_enemy_sprites()`。 |
| `tools/pawn_extents.gd` | 由「量程序繪圖」改成「覆核 sprite alpha bounds」。 |
| `tools/test_all.sh` | 加 `enemy_cutout_test` 呢個 Python 套件。 |
| `DECISIONS.md` | 記低判斷,尤其「墨線輪廓 + 填內部」呢把刀。 |
| `docs/design/2026-08-07-enemy-sprite-art.md` | 收尾時補上補圖清單。 |

---

## Task 1: 資產 pipeline —— 墨線分割

**Files:**
- Create: `tools/enemy_cutout.py`
- Create: `tools/enemy_cutout_test.py`
- Modify: `tools/test_all.sh`

**Interfaces:**
- Consumes: `tools/art_cutout.py` 嘅 `_bg_mask()`、`trim()`、`cutout()` 嘅邊緣處理手法(參考,唔係 import —— 呢個 pipeline 自己一套分割)。
- Produces:
  - `assets/enemies/<KEY>.png`,KEY ∈ `E01…E10, B1…B6, B3P2`(17 個)
  - `assets/enemies/enemies.json`:`{KEY: {"size":[w,h], "aspect":float, "edge_rgb":[r,g,b]}}`
  - stdout 印一行 `PAWN_EXTENT: { "E01": Vector2(1.00, 0.42), ... }`
  - `qa/enemy_cutout_contact.png`(洋紅格仔)、`qa/enemy_cutout_alpha.png`
  - Python API:`subject_mask(rgb: np.ndarray) -> np.ndarray`、`cut_subject(img: Image) -> Image`、`edge_band_rgb(rgba: np.ndarray, px:int=3) -> tuple[int,int,int]`

### 分割演算法(核心判斷)

呢批圖有一個穩定嘅生成特性:**主體必定被一條封閉深墨線包住,雜物(煙、✦ 水印、飛濺點)必定冇。** 所以:

1. 墨線遮罩 `ink = value < INK_V`
2. 8-連通標籤,揀最大嗰件;連埋所有 **≥ 最大件 5%** 嘅其他件(真身體部件夠大,雜物唔夠)
3. union 之後 `binary_fill_holes` → 主體
4. 呢一步同時殺:黐身灰煙(冇墨線)、藤嘅內圈奶白窟窿(被填)、✦ 水印同飛濺點(唔夠 5%)

- [ ] **Step 1: 寫失敗測試**

Create `tools/enemy_cutout_test.py`:

```python
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

        # one subject, not a subject plus floating debris
        lab, n = ndimage.label(a > 128)
        if n:
            sizes = ndimage.sum(a > 128, lab, range(1, n + 1))
            biggest = sizes.max()
            debris = [s for s in sizes if 0.02 * biggest < s < 0.5 * biggest]
            check(not debris, "%s has %d detached mid-size fragments" % (k, len(debris)))

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
```

- [ ] **Step 2: 跑測試,確認佢冚唪唥 fail**

Run: `python tools/enemy_cutout_test.py`
Expected: `FAIL: assets/enemies/ exists` 開頭,結尾 `ENEMY CUTOUT: 1 tests, 1 failures`,exit 1。

- [ ] **Step 3: 實作 pipeline**

Create `tools/enemy_cutout.py`:

```python
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

# Ink is the darkest thing on every plate by a wide margin: the outline sits
# under 0.30 value while the darkest painted body (the bone wolf's shadow side)
# stays above 0.38. Measured across all ten plates, not guessed.
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
```

- [ ] **Step 4: 跑 pipeline**

Run: `python tools/enemy_cutout.py`
Expected: 17 行 `Exx WxH aspect=… edge=[…]`,一行 `PAWN_EXTENT: {…}`,一行 `qa -> …`。

- [ ] **Step 5: 跑測試,確認全綠**

Run: `python tools/enemy_cutout_test.py`
Expected: `ENEMY CUTOUT: N tests, 0 failures`,exit 0。

如果 `cream pixels left inside it` fail,通常係 `INK_V` 太低(墨線斷咗,填唔到);逐 0.02 加上去再跑,唔好改去掃 cream —— 掃 cream 就返轉頭做返 cream key,呢個 pipeline 特登唔用嗰招。

- [ ] **Step 6: 用眼睇 QA 圖(必做,唔准跳)**

用 Read tool 開 `qa/enemy_cutout_contact.png`。逐隻確認:
- 冇奶白邊、冇灰煙殘留、冇 ✦ 水印
- 冇肢體俾 5% 門檻切走(睇下有冇斷手斷腳、觸鬚唔見咗)
- 藤(E06)嘅內圈冇白窟窿

**如果有肢體俾切走**,調低 `KEEP_FRAC` 到 0.02 再跑再睇。如果調到 0.02 都仲有主體部件飛咗,即係嗰隻嘅墨線本身斷開,**停低,寫入補圖清單**,唔准手畫補返。

- [ ] **Step 7: 掛入 test_all.sh**

Modify `tools/test_all.sh` —— 喺 `echo "-----"` 之前插入:

```bash
printf '%-24s ' "enemy_cutout"
LINE=$(python tools/enemy_cutout_test.py 2>&1 | grep -E "tests, .* failures" | tail -1)
echo "$LINE"
case "$LINE" in
  "") FAILED=$((FAILED+1));;
  *" 0 failures"*) ;;
  *failures*) FAILED=$((FAILED+1));;
esac
```

- [ ] **Step 8: 跑全套**

Run: `bash tools/test_all.sh`
Expected: 13 行,`ALL SUITES PASSED`。(`ui_smoke` 呢個時候仲係用舊嘅 `BODY` 量法,照樣綠。)

- [ ] **Step 9: Commit**

```bash
git add tools/enemy_cutout.py tools/enemy_cutout_test.py tools/test_all.sh assets/enemies qa/enemy_cutout_contact.png
git commit -m "feat(art): 用墨線輪廓分割由參考圖切出 17 隻敵人 sprite"
```

---

## Task 2: HSV 斷層統計 —— 認色方案嘅前提驗證

**Files:**
- Create: `tools/enemy_hsv.py`
- Modify: `tools/enemy_cutout.py`(`--hsv-report` 已經 import 咗佢)

**Interfaces:**
- Consumes: Task 1 嘅 `load_all() -> {key: Image}`
- Produces: `report(cuts: dict) -> int`;stdout 印出眼 / 腐化紋 / 岩漿 / 身體四類嘅 HSV 分佈同**建議界線**,由人手抄入 Task 3 嘅 shader uniform 預設值同 `DECISIONS.md`。

**呢個 task 係整套認色方案唯一未驗證嘅前提。** 界線係量出嚟,唔係估。如果四類之間根本冇斷層,認色行唔通 —— **停低同報告**,唔准硬揀個數當過關。

- [ ] **Step 1: 寫統計工具**

Create `tools/enemy_hsv.py`:

```python
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
```

- [ ] **Step 2: 跑統計**

Run: `python tools/enemy_cutout.py --hsv-report`
Expected: 印出四段統計同一個 20-bin 直方圖。

- [ ] **Step 3: 讀直方圖,揀界線**

睇 `val histogram of magenta sat>0.45`:眼係細舊高亮、腐化紋係大舊中亮,兩者之間應該有一個明顯低谷。

- 喺低谷中間揀 `EYE_VAL`
- 由 `magenta-band pixels` 嘅 sat p5 揀 `SAT_MIN`(要低過腐化紋,高過身體嘅紫調)
- 由 hue 分佈揀 `HUE_LO` / `HUE_HI`
- 由 orange 段揀 `EMBER_HUE`

**收貨閘:** 低谷要真係存在 —— 谷底至少要低過兩邊峰值嘅一半。如果直方圖係單峰、冇谷,即係眼同腐化紋分唔開。**停低,向用家報告**,唔准硬揀一個數。

- [ ] **Step 4: 記低數字**

喺 `tools/enemy_hsv.py` 頂加一個常數 block,寫實揀咗嘅四個數同**點解**(引用直方圖邊個 bin 係谷底)。Task 3 嘅 shader uniform 預設值抄呢度。

- [ ] **Step 5: Commit**

```bash
git add tools/enemy_hsv.py tools/enemy_cutout.py
git commit -m "feat(art): 量出敵人 sprite 嘅 HSV 斷層,shader 認色界線有數據支持"
```

---

## Task 3: shader + rim 強度單一真源

**Files:**
- Create: `assets/shaders/rot_pawn.gdshader`
- Modify: `scripts/ui/ui_theme.gd`(喺 `ROT_RIM` 常數後面加 `rot_rim_for()`)
- Modify: `tests/ui_smoke.gd`(加 `_t_rot_rim()`,喺 `_ready()` 嘅 `_t_enemy_legibility()` 前面叫)

**Interfaces:**
- Consumes: Task 2 揀出嘅 `HUE_LO/HUE_HI/SAT_MIN/EYE_VAL/EMBER_HUE`
- Produces:
  - `UITheme.rot_rim_for(chapter: int) -> float` —— rim 強度,0.0–1.0
  - shader uniforms:`eye_gain`、`vein_gain`、`rim_strength`、`rim_color`、`rim_px`、`hot_bounds: vec4`、`ember_hue: vec2`、`ember_gain`

### rim 係內側 rim

sprite trim 到 alpha bounds,`draw_texture_rect` 冇 padding,所以**向外**嘅 outline 會俾 rect 切走。rim 一定要畫喺剪影**內側**:取 ring 上最細嘅 alpha,`edge = src.a * (1 - amin)`。呢個做法順帶好處係 rim 正正落喺圖本身嗰條粗墨線上面 —— 墨線係最暗嘅部分,亦即係喺近黑卡面上最易溶掉嗰部分。

- [ ] **Step 1: 寫失敗測試**

Modify `tests/ui_smoke.gd` —— 喺 `_t_enemy_legibility()` 前面加:

```gdscript
## The rim light's strength is a single formula shared by GDScript and the
## shader. It has to grow as the chapter card gets darker, or the darkest
## chapter — the one that needs the rim most — gets the least of it.
func _t_rot_rim() -> void:
	var r1 := UITheme.rot_rim_for(1)
	var r2 := UITheme.rot_rim_for(2)
	var r3 := UITheme.rot_rim_for(3)
	_check(r3 > r1, "chapter 3 rim (%.2f) must be stronger than chapter 1 (%.2f)" % [r3, r1])
	_check(r1 <= r2 and r2 <= r3, "rim must not dip between chapters: %.2f/%.2f/%.2f" % [r1, r2, r3])
	for ch in [1, 2, 3]:
		var s := UITheme.rot_rim_for(ch)
		_check(s >= 0.0 and s <= 1.0, "chapter %d rim %.2f out of 0..1" % [ch, s])
	# the rim colour, at full strength, must clear the bar on its own card
	var lit := UITheme.ROT_RIM
	_check(UITheme.contrast(lit, UITheme.surface(3)) >= 2.4,
			"ROT_RIM %s on chapter 3 is %.2f:1, needs 2.4:1"
			% [lit.to_html(false), UITheme.contrast(lit, UITheme.surface(3))])
	print("rot rim: ch1 %.2f  ch2 %.2f  ch3 %.2f" % [r1, r2, r3])
```

同埋喺 `_ready()` 加 `_t_rot_rim()`。

- [ ] **Step 2: 跑測試,確認 fail**

Run: `bash tools/run.sh t_ui_smoke "res://tests/ui_smoke.tscn"` 然後讀 `art_export/t_ui_smoke.log`
Expected: 因為 `rot_rim_for` 未存在,script error / `UI SMOKE FAILED`。

- [ ] **Step 3: 加 `rot_rim_for`**

Modify `scripts/ui/ui_theme.gd` —— 喺 `ROT_RIM` 常數後面:

```gdscript
## How hard the rim light has to work on a given chapter's enemy card.
##
## The enemy plates are painted nearly black — they were drawn on a cream
## sheet, where that reads fine. Our cards are `surface(chapter)`, and
## chapter 3's is `#1e1429`, so the darker the card the more of the silhouette
## dissolves into it. Strength is therefore read straight off the card's own
## luminance rather than tabulated per chapter, which keeps this honest if a
## chapter surface is ever retuned.
##
## This is the SINGLE SOURCE for rim strength: `rot_pawn.gdshader` is handed
## the result through its `rim_strength` uniform, and `_t_enemy_legibility`
## predicts the lit edge with it. Two copies of this curve would let the test
## and the picture drift apart silently.
static func rot_rim_for(chapter: int) -> float:
	var l := luminance(surface(chapter))
	# 0.16 luminance (chapter 1's card) -> 0.35; 0.02 (chapter 3's) -> 1.0
	return clampf(remap(l, 0.02, 0.16, 1.0, 0.35), 0.0, 1.0)
```

- [ ] **Step 4: 跑測試,確認 pass**

Run: `bash tools/run.sh t_ui_smoke "res://tests/ui_smoke.tscn"`
Expected: log 有 `rot rim: ch1 … ch2 … ch3 …` 同 `UI SMOKE OK`。

如果 `ROT_RIM` 喺第 3 章夾唔到 2.4:1,調亮 `UITheme.ROT_RIM`(佢係光,唔係生物顏色,調得),唔好落 threshold。

- [ ] **Step 5: 寫 shader**

Create `assets/shaders/rot_pawn.gdshader`:

```glsl
shader_type canvas_item;
// Corruption pass for the enemy plates.
//
// The plates are art in their own right and nothing here repaints them: this
// shader only re-lights pixels the illustration already put down. The eyes and
// the corruption cracks are painted in one magenta family and the lava toad's
// fissures in orange, so the tier dials are gain values on colours that are
// already there rather than shapes drawn on top.
//
// Bounds come from `tools/enemy_hsv.py`, which measures where those four kinds
// of pixel actually sit across all seventeen sprites.

// x = hue low, y = hue high, z = min saturation, w = the value that splits a
// lit eye from a corruption crack.
uniform vec4  hot_bounds = vec4(0.78, 0.97, 0.45, 0.72);
uniform vec2  ember_hue  = vec2(0.00, 0.13);
uniform float eye_gain   : hint_range(0.0, 4.0) = 1.0;
uniform float vein_gain  : hint_range(0.0, 4.0) = 0.0;
uniform float ember_gain : hint_range(0.0, 2.0) = 0.6;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.0;
uniform vec3  rim_color : source_color = vec3(0.81, 0.66, 0.87);
uniform float rim_px = 3.0;

float hue_of(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float d = mx - mn;
	if (d < 0.0001) return 0.0;
	float h;
	if (mx == c.r)      h = mod((c.g - c.b) / d, 6.0);
	else if (mx == c.g) h = (c.b - c.r) / d + 2.0;
	else                h = (c.r - c.g) / d + 4.0;
	return h / 6.0;
}

float sat_of(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	if (mx < 0.0001) return 0.0;
	return (mx - min(c.r, min(c.g, c.b))) / mx;
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec3 lit = src.rgb;

	// --- bloom: a 5x5 gathered tap, but only magenta and ember pixels put
	// anything into it, so most of the sprite costs one branch per tap.
	vec3 glow = vec3(0.0);
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 o = vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE * 1.6;
			vec4 s = texture(TEXTURE, UV + o);
			if (s.a < 0.2) { continue; }
			float h = hue_of(s.rgb);
			float sa = sat_of(s.rgb);
			float v = max(s.rgb.r, max(s.rgb.g, s.rgb.b));
			float w = max(0.0, 1.0 - length(vec2(float(x), float(y))) / 3.2);
			if (sa > hot_bounds.z && h > hot_bounds.x && h < hot_bounds.y) {
				glow += s.rgb * w * (v > hot_bounds.w ? eye_gain : vein_gain);
			} else if (sa > 0.50 && h >= ember_hue.x && h <= ember_hue.y) {
				glow += s.rgb * w * ember_gain;
			}
		}
	}
	lit += glow * 0.055;

	// --- rim: lit on the INSIDE of the silhouette. The sprite is trimmed to
	// its alpha bounds and drawn into a rect of exactly that size, so an
	// outward glow would be clipped off. Inward also puts the light straight
	// onto the plate's own heavy ink outline, which is the part that
	// disappears first against a near-black card.
	if (rim_strength > 0.001 && src.a > 0.2) {
		float amin = 1.0;
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.7853981;
			vec2 o = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE * rim_px;
			amin = min(amin, texture(TEXTURE, UV + o).a);
		}
		float edge = src.a * (1.0 - amin);
		lit = mix(lit, rim_color, clamp(edge * rim_strength, 0.0, 1.0));
	}

	COLOR = vec4(lit, src.a) * COLOR;
}
```

- [ ] **Step 6: 確認 shader 編譯得**

Run: `"C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe" --headless --path . --import`
Expected: log 冇 `SHADER` / `error` 字眼。有 shader compile error 就會喺度爆。

- [ ] **Step 7: Commit**

```bash
git add assets/shaders/rot_pawn.gdshader scripts/ui/ui_theme.gd tests/ui_smoke.gd
git commit -m "feat(art): 加 rot_pawn shader 同 rot_rim_for 單一真源"
```

---

## Task 4: `PawnArt` 由程序繪圖轉貼圖

**Files:**
- Modify: `scripts/ui/pawn_art.gd`(大改:刪 ~700 行,加貼圖路)
- Modify: `scripts/ui/screen_battle.gd:681`
- Modify: `scripts/ui/screen_codex.gd:242,270`
- Modify: `tests/ui_smoke.gd`(加 `_t_enemy_sprites()`)

**Interfaces:**
- Consumes: `assets/enemies/*.png`、`assets/shaders/rot_pawn.gdshader`、`UITheme.rot_rim_for()`
- Produces:
  - `PawnArt.ENEMY_TEX: Dictionary` — key → `res://assets/enemies/<KEY>.png`
  - `PawnArt.BOSS_CHAPTER: Dictionary` — `{"B1":1,"B2":1,"B3":2,"B3P2":2,"B4":2,"B5":3,"B6":3}`
  - `PawnArt.enemy_texture(kind: String) -> Texture2D`
  - `PawnArt.make(kind, height, flip, tier, chapter := -1) -> PawnArt`(新增第 5 個參數)
  - `PawnArt.fitted(kind, box, flip, tier, chapter := -1) -> PawnArt`(同上)
  - `PawnArt.chapter_of(kind, tier) -> int` — boss 查表,其餘 = tier
  - `EXTENT` 入面 17 個敵人 key 換成 Task 1 印出嗰組

### 要刪嘅嘢

`scripts/ui/pawn_art.gd` 入面呢 18 個造型 routine 全刪:`_draw_slime`、`_draw_rat`、`_draw_sporecap`、`_draw_beetle`、`_draw_moth`、`_draw_vine`、`_draw_wolf`、`_draw_wraith`、`_draw_toad`、`_draw_viper`、`_draw_basher_bunny`、`_draw_boxer_hare`、`_draw_sir_croak`、`_draw_sir_croak_afoot`、`_draw_fishbone_cat`、`_draw_purrceval`、`_draw_croakomancer`,連同 `_draw()` 入面成個 `match kind:` block。

只服務佢哋嘅 primitive 一併刪:`_circle`、`_ellipse`、`_poly`、`_line`、`_arc`、`_smooth`、`_limb`、`_dome_points`、`_leaf`、`_veins`、`_cracks`、`_rot_eye`、`_rot_eyes`、`_rot`、`_body`、`_rim`,同埋常數 `OL`、`OLW`、`BODY`、`BONE`、`STEEL`、`WOOD`、`EMBER`、`HEAD`、`rot_shade`、`rot_body`。

**保留**:`_mist`、`_wisp`、`_c`、`rot_of`、`rot_level`。煙係特效唔係生物造型,而 `rot_of` 係 tier→0..1 嘅換算,shader gain 要用。

`_rim` 刪得,因為 rim 而家係 shader 做。

刪之前跑一次確認冇其他檔案用緊:

```bash
grep -rn "rot_body\|PawnArt.BODY\|PawnArt.HEAD\|rot_shade" --include=*.gd .
```

`tests/ui_smoke.gd:336-337` 會出現(舊嘅 `_t_enemy_legibility`)—— 嗰個喺 Task 5 換。所以 **Task 4 暫時保留 `BODY` 同 `rot_body`**,Task 5 先刪。

- [ ] **Step 1: 寫失敗測試**

Modify `tests/ui_smoke.gd` —— 加:

```gdscript
## Every enemy is a plate now. This is the rule that keeps the hand-drawn
## routines from creeping back: if a key has no texture there is no fallback
## that could quietly draw a creature instead.
func _t_enemy_sprites() -> void:
	var keys := ["E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09", "E10",
			"B1", "B2", "B3", "B3P2", "B4", "B5", "B6"]
	for k in keys:
		var tex := PawnArt.enemy_texture(k)
		_check(tex != null, "%s has no sprite in assets/enemies/" % k)
		if tex != null:
			_check(tex.get_width() > 40 and tex.get_height() > 40,
					"%s sprite is %dx%d, too small to be a real cut"
					% [k, tex.get_width(), tex.get_height()])
	# the pawn actually carries the corruption shader
	var pa := PawnArt.make("E01", 140.0, false, 3, 3)
	add_child(pa)
	await get_tree().process_frame
	_check(pa.material is ShaderMaterial, "E01 pawn has no ShaderMaterial")
	if pa.material is ShaderMaterial:
		var m: ShaderMaterial = pa.material
		_check(float(m.get_shader_parameter("rim_strength")) > 0.0,
				"chapter 3 pawn got no rim strength")
		_check(float(m.get_shader_parameter("vein_gain")) > 0.0,
				"tier 3 pawn got no vein glow")
	var t1 := PawnArt.make("E01", 140.0, false, 1, 1)
	add_child(t1)
	await get_tree().process_frame
	if t1.material is ShaderMaterial:
		_check(float((t1.material as ShaderMaterial).get_shader_parameter("vein_gain")) == 0.0,
				"tier 1 must have no vein glow — it is one of the five tier dials")
	pa.queue_free()
	t1.queue_free()
	# extents come off the sprites now: trimmed art always fills its height
	for k2 in keys:
		_check(is_equal_approx(PawnArt.extent(k2).x, 1.0),
				"%s extent.x is %.2f — trimmed sprites always reach 1.00"
				% [k2, PawnArt.extent(k2).x])
```

同埋喺 `_ready()` 加 `await _t_enemy_sprites()`。

- [ ] **Step 2: 跑測試,確認 fail**

Run: `bash tools/run.sh t_ui_smoke "res://tests/ui_smoke.tscn"`
Expected: log 有 `enemy_texture` 唔存在嘅 script error,或者 `UI SMOKE FAILED`。

- [ ] **Step 3: 改 `pawn_art.gd`**

刪走 Step「要刪嘅嘢」列出嘅全部(除咗 `BODY`/`rot_body`,Task 5 先刪)。跟住加/改:

```gdscript
## Painted enemy plates, by key. Cut off the reference art by
## `tools/enemy_cutout.py`; nothing in this file draws a creature any more.
const ENEMY_TEX := {
	"E01": "res://assets/enemies/E01.png", "E02": "res://assets/enemies/E02.png",
	"E03": "res://assets/enemies/E03.png", "E04": "res://assets/enemies/E04.png",
	"E05": "res://assets/enemies/E05.png", "E06": "res://assets/enemies/E06.png",
	"E07": "res://assets/enemies/E07.png", "E08": "res://assets/enemies/E08.png",
	"E09": "res://assets/enemies/E09.png", "E10": "res://assets/enemies/E10.png",
	"B1": "res://assets/enemies/B1.png", "B2": "res://assets/enemies/B2.png",
	"B3": "res://assets/enemies/B3.png", "B3P2": "res://assets/enemies/B3P2.png",
	"B4": "res://assets/enemies/B4.png", "B5": "res://assets/enemies/B5.png",
	"B6": "res://assets/enemies/B6.png",
}

## Which chapter each boss is met in. A minion's chapter is its tier — it is
## the same creature fought again — but a boss has no tier, so the rim light
## has nowhere else to learn how dark the card behind it will be.
const BOSS_CHAPTER := {"B1": 1, "B2": 1, "B3": 2, "B3P2": 2, "B4": 2, "B5": 3, "B6": 3}

const ROT_SHADER := "res://assets/shaders/rot_pawn.gdshader"

## Tier dials, as gains on colour the plate already carries. Index is tier-1.
const EYE_GAIN := [0.45, 0.85, 1.5]
const VEIN_GAIN := [0.0, 0.0, 1.1]     # T1/T2 dark, T3 alight
const MIST_COUNT := [0, 3, 5]

static var _shader_cache: Shader = null


static func enemy_texture(p_kind: String) -> Texture2D:
	if not ENEMY_TEX.has(p_kind):
		return null
	if not _tex_cache.has(p_kind):
		_tex_cache[p_kind] = load(String(ENEMY_TEX[p_kind])) as Texture2D
	return _tex_cache[p_kind]


## The plate for any pawn, hero or enemy.
static func plate(p_kind: String) -> Texture2D:
	var t := hero_texture(p_kind)
	return t if t != null else enemy_texture(p_kind)


## Which chapter's card this pawn will be standing on, when the caller has not
## said. Bosses are tabulated; a minion's tier IS its chapter.
static func chapter_of(p_kind: String, p_tier: int) -> int:
	if BOSS_CHAPTER.has(p_kind):
		return int(BOSS_CHAPTER[p_kind])
	return clampi(p_tier, 1, 3)
```

`make` / `fitted` 加參數:

```gdscript
static func make(p_kind: String, height := 140.0, p_flip := false, p_tier := 3,
		p_chapter := -1) -> PawnArt:
	var pa := PawnArt.new()
	pa.kind = p_kind
	pa.body_h = height
	pa.flip = p_flip
	pa.tier = clampi(p_tier, 1, 3)
	pa.chapter = chapter_of(p_kind, pa.tier) if p_chapter < 1 else clampi(p_chapter, 1, 3)
	pa._bob_seed = hash(p_kind) % 100 / 100.0 * TAU
	return pa


static func fitted(p_kind: String, box: Vector2, p_flip := false, p_tier := 3,
		p_chapter := -1) -> PawnArt:
	return make(p_kind, fit_height(p_kind, box), p_flip, p_tier, p_chapter)
```

加 `var chapter := 1` 落 `var tier := 3` 隔籬,同埋喺 `_ready()` 掛 material:

```gdscript
func _ready() -> void:
	set_process(true)
	_apply_rot_material()


## The corruption pass. Heroes never get one — magenta belongs to the enemy.
func _apply_rot_material() -> void:
	if not ENEMY_TEX.has(kind):
		return
	if _shader_cache == null:
		_shader_cache = load(ROT_SHADER) as Shader
	var m := ShaderMaterial.new()
	m.shader = _shader_cache
	var i := clampi(tier, 1, 3) - 1
	m.set_shader_parameter("eye_gain", EYE_GAIN[i])
	m.set_shader_parameter("vein_gain", VEIN_GAIN[i])
	m.set_shader_parameter("rim_strength", UITheme.rot_rim_for(chapter))
	m.set_shader_parameter("rim_color", Vector3(UITheme.ROT_RIM.r, UITheme.ROT_RIM.g,
			UITheme.ROT_RIM.b))
	material = m
```

`_draw()` 收編兩邊:

```gdscript
func _draw() -> void:
	var bob := 3.0 * floorf(fmod(_t * 2.2 + _bob_seed, 2.0))
	var tex := plate(kind)
	if tex == null:
		return          # no fallback: nothing in this file draws a creature
	var u := bulk(kind, tier)
	draw_set_transform(Vector2(0, bob) + _attack_offset, 0, Vector2.ONE)
	var h := body_h * u
	var w := h * float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
	# mist rises from behind the body, so it is drawn first
	if ENEMY_TEX.has(kind):
		_auto_mist(w, h)
	draw_texture_rect(tex, Rect2(-w * 0.5, -h, w, h), false, Color.WHITE, flip)


## Black mist along the base of the silhouette. Its spots used to be listed per
## creature, which only worked while this file also owned the creature's shape;
## with the plates they are spread across the sprite's own width instead, so
## swapping a plate cannot leave the smoke hanging in the wrong place.
func _auto_mist(w: float, h: float) -> void:
	var n: int = MIST_COUNT[clampi(tier, 1, 3) - 1]
	if n <= 0:
		return
	var spots := []
	for i in n:
		var f := (float(i) + 0.5) / float(n)
		spots.append([lerpf(-w * 0.46, w * 0.46, f), -h * 0.22,
				h * lerpf(0.30, 0.46, fmod(float(i) * 0.37, 1.0))])
	_mist(spots)
```

`bulk()` 要放行敵人(而家 `HERO_TEX.has(...)` 嗰條會令貼圖直接 return 1.0 —— 敵人要保留 tier 體型):

```gdscript
static func bulk(p_kind: String, p_tier: int) -> float:
	if is_boss(p_kind) or HERO_TEX.has(p_kind):
		return 1.0
	return float(TIER_BULK.get(clampi(p_tier, 1, 3), 1.0))
```

(呢個原樣冇改 —— 確認一次:boss 同主角 1.0,10 隻小怪照食 `TIER_BULK`。)

最後,`EXTENT` 入面 17 個敵人 key 換成 Task 1 `PAWN_EXTENT:` 印出嗰組。

- [ ] **Step 4: 呼叫端傳 chapter**

`scripts/ui/screen_battle.gd:681` —— `chapter` 呢個 local 喺 `_make_enemy_card` 已經有:

```gdscript
	var art := PawnArt.fitted(art_key, Vector2(inner_w, art_h), true, art_tier, chapter)
```

`scripts/ui/screen_codex.gd:242`(tier strip)—— tier 就係 chapter,傳 `tier`:

```gdscript
		var art := PawnArt.fitted(key, Vector2(96, 92.0), false, tier, tier)
```

`scripts/ui/screen_codex.gd:270`(boss strip)—— 唔傳,行 `BOSS_CHAPTER` 預設:

```gdscript
		var art := PawnArt.fitted(String(art_keys[i]), Vector2(140, 142.0))
```

- [ ] **Step 5: 跑測試**

Run: `"C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe" --headless --path . --import` 然後 `bash tools/run.sh t_ui_smoke "res://tests/ui_smoke.tscn"`
Expected: `UI SMOKE OK`。

- [ ] **Step 6: 跑全套**

Run: `bash tools/test_all.sh`
Expected: `ALL SUITES PASSED`。特別留意 `layout_test`(佢 assert 敵人卡唔可以撞出 band)—— extent 換咗,呢個係最可能爆嗰個。爆咗嘅話係 `EXTENT` 貼漏或者貼錯,唔好改 `ENEMY_CHROME_H` 去遷就。

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/pawn_art.gd scripts/ui/screen_battle.gd scripts/ui/screen_codex.gd tests/ui_smoke.gd
git commit -m "feat(art): 敵人改用 sprite,刪走全部手畫造型 routine"
```

---

## Task 5: 可讀性代理量法

**Files:**
- Modify: `tests/ui_smoke.gd`(`_t_enemy_legibility()` 全改)
- Modify: `scripts/ui/pawn_art.gd`(而家先刪 `BODY`、`rot_body`、`rot_shade`)

**Interfaces:**
- Consumes: `assets/enemies/enemies.json` 嘅 `edge_rgb`、`UITheme.rot_rim_for()`
- Produces: `_t_enemy_legibility()` 用新量法;`PawnArt.BODY` / `rot_body` / `rot_shade` 消失

代理模型:sprite 邊緣帶嘅平均色,同 rim 顏色按 `rot_rim_for(chapter)` 混合,得出「著咗 rim 之後嗰條輪廓實際係咩色」,再對 `surface(chapter)` 計對比。混合公式必須同 shader 嗰句 `mix(lit, rim_color, edge * rim_strength)` 對得上。

- [ ] **Step 1: 改寫測試**

Modify `tests/ui_smoke.gd` —— 成個 `_t_enemy_legibility()` 換成:

```gdscript
## Can you still tell where the creature ends and the card begins?
##
## The old version measured a flat body colour this file used to own. The
## bodies are painted plates now, so the thing that has to survive the card is
## the LIT EDGE: the outermost band of the silhouette with the rim light on it.
##
## `edge_rgb` is measured off each cut PNG by `tools/enemy_cutout.py`; the
## blend below mirrors `rot_pawn.gdshader`'s rim line, and both take their
## strength from `UITheme.rot_rim_for`. This is a MODEL of the picture, not the
## picture — `tools/enemy_legibility.gd` renders the real thing, and the two
## are reconciled before this number is trusted. See DECISIONS.md.
func _t_enemy_legibility() -> void:
	var f := FileAccess.open("res://assets/enemies/enemies.json", FileAccess.READ)
	_check(f != null, "assets/enemies/enemies.json is missing")
	if f == null:
		return
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	_check(meta.size() == 17, "enemies.json describes %d sprites, expected 17" % meta.size())

	var worst := 99.0
	var worst_what := ""
	for key in meta:
		var e: Array = meta[key]["edge_rgb"]
		var edge := Color8(int(e[0]), int(e[1]), int(e[2]))
		var chapters: Array = [int(PawnArt.BOSS_CHAPTER[key])] if PawnArt.BOSS_CHAPTER.has(key) \
				else [1, 2, 3]
		for ch in chapters:
			var lit := lit_edge(edge, int(ch))
			var r := UITheme.contrast(lit, UITheme.surface(int(ch)))
			if r < worst:
				worst = r
				worst_what = "%s on chapter %d" % [key, ch]
			_check(r >= 2.4, "%s lit edge %s on chapter %d card is %.2f:1, needs 2.4:1"
					% [key, lit.to_html(false), ch, r])
	print("enemy legibility (proxy): worst is %s at %.2f:1" % [worst_what, worst])


## The rim light applied to an edge colour, mirroring the `mix()` at the bottom
## of `rot_pawn.gdshader`. `edge` is 1.0 there because `edge_rgb` is sampled
## from exactly the band the shader lights.
func lit_edge(edge: Color, chapter: int) -> Color:
	return edge.lerp(UITheme.ROT_RIM, clampf(UITheme.rot_rim_for(chapter), 0.0, 1.0))
```

- [ ] **Step 2: 跑,睇實際數**

Run: `bash tools/run.sh t_ui_smoke "res://tests/ui_smoke.tscn"`
Expected: log 有 `enemy legibility (proxy): worst is … at …:1`。

如果有 case 唔夠 2.4:1,調嘅係 `UITheme.rot_rim_for` 嘅上限(rim 打強啲)或者 `ROT_RIM` 顏色 —— **唔准調 2.4 呢個門檻,亦唔准改 sprite 顏色**(sprite 而家係美術本體)。

- [ ] **Step 3: 刪走死咗嘅顏色機制**

Modify `scripts/ui/pawn_art.gd`:刪 `BODY`、`rot_shade`、`rot_body`。跑一次確認冇殘留引用:

```bash
grep -rn "rot_body\|rot_shade\|PawnArt.BODY" --include=*.gd .
```
Expected: 冇 output。

- [ ] **Step 4: 跑全套**

Run: `bash tools/test_all.sh`
Expected: `ALL SUITES PASSED`。

- [ ] **Step 5: Commit**

```bash
git add tests/ui_smoke.gd scripts/ui/pawn_art.gd
git commit -m "test(art): 可讀性改量 sprite 邊緣帶 + rim,刪走舊嘅 BODY 顏色量法"
```

---

## Task 6: 真 render 量度 + 同代理對數

**Files:**
- Create: `tools/enemy_legibility.gd`、`tools/enemy_legibility.tscn`
- Modify: `scripts/ui/ui_theme.gd` 或 `tests/ui_smoke.gd`(**只喺對數失敗時**才校)

**Interfaces:**
- Consumes: `PawnArt`、`UITheme`、`assets/enemies/enemies.json`
- Produces: stdout 一個表 `LEGIBILITY <key> ch<N> real=<r> proxy=<p> delta=<d>`,同一行 `LEGIBILITY WORST-DELTA <d>`

**呢個 task 係「實測」嘅憑證。代理綠唔算數。**

- [ ] **Step 1: 寫工具**

Create `tools/enemy_legibility.gd`:

```gdscript
extends Node
## Measures how legible each enemy silhouette actually is on the card it fights
## on — by rendering it, not by modelling it.
##
##   Godot --path . --log-file art_export/legib.log tools/enemy_legibility.tscn
##
## Must run with a REAL window: the grab awaits RenderingServer.frame_post_draw,
## which never fires headless.
##
## `ui_smoke._t_enemy_legibility` predicts the same number from `edge_rgb` and
## `UITheme.rot_rim_for`. That proxy is cheap and runs headless, but it is a
## model; this is the picture. Where they disagree by more than DELTA_MAX the
## proxy is wrong and gets corrected — never the other way round.

const MINIONS := ["E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09", "E10"]
const BOSSES := ["B1", "B2", "B3", "B3P2", "B4", "B5", "B6"]
const PAD := 260
const H := 200.0
## The band the rim lights, in screen pixels — matches `rim_px` in the shader.
const BAND_PX := 3
const DELTA_MAX := 0.15

var sub: SubViewport
var meta := {}


func _ready() -> void:
	var f := FileAccess.open("res://assets/enemies/enemies.json", FileAccess.READ)
	meta = JSON.parse_string(f.get_as_text())
	f.close()

	sub = SubViewport.new()
	sub.size = Vector2i(PAD * 2, PAD * 2)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.disable_3d = true
	add_child(sub)
	await get_tree().process_frame

	var worst_delta := 0.0
	var worst_case := ""
	var rows := []
	for key in MINIONS + BOSSES:
		var chapters: Array = [int(PawnArt.BOSS_CHAPTER[key])] \
				if PawnArt.BOSS_CHAPTER.has(key) else [1, 2, 3]
		for ch in chapters:
			var tier: int = int(ch) if key in MINIONS else 3
			var real := await _measure(key, tier, int(ch))
			var proxy := _proxy(key, int(ch))
			var d := absf(real - proxy)
			if d > worst_delta:
				worst_delta = d
				worst_case = "%s ch%d" % [key, ch]
			rows.append("LEGIBILITY %-5s ch%d real=%.2f proxy=%.2f delta=%.2f%s"
					% [key, ch, real, proxy, d, "  <-- 2.4 FAIL" if real < 2.4 else ""])

	for r in rows:
		print(r)
	print("LEGIBILITY WORST-DELTA %.3f at %s (max allowed %.2f)"
			% [worst_delta, worst_case, DELTA_MAX])
	print("LEGIBILITY %s" % ("CALIBRATED" if worst_delta <= DELTA_MAX else "PROXY NEEDS FIXING"))
	get_tree().quit()


## Renders the pawn on its chapter card and measures the contrast between the
## lit edge band and the card, the way a player's eye meets it.
func _measure(key: String, tier: int, chapter: int) -> float:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	var card := ColorRect.new()
	card.color = UITheme.surface(chapter)
	card.size = Vector2(PAD * 2, PAD * 2)
	sub.add_child(card)
	var pa := PawnArt.make(key, H, false, tier, chapter)
	pa.position = Vector2(PAD, PAD + H * 0.5)
	sub.add_child(pa)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()

	# the lit band: pixels that differ from the card, within BAND_PX of a pixel
	# that does not. Walk the image once and keep the outermost run per row.
	var surf := UITheme.surface(chapter)
	var band := []
	for y in img.get_height():
		var xs := []
		for x in img.get_width():
			if img.get_pixel(x, y).srgb_to_linear().distance_to(
					surf.srgb_to_linear()) > 0.02:
				xs.append(x)
		if xs.is_empty():
			continue
		for i in mini(BAND_PX, xs.size()):
			band.append(img.get_pixel(int(xs[i]), y))
			band.append(img.get_pixel(int(xs[xs.size() - 1 - i]), y))
	if band.is_empty():
		return 0.0
	var acc := Color(0, 0, 0)
	for c2 in band:
		acc += c2
	var mean := Color(acc.r / band.size(), acc.g / band.size(), acc.b / band.size())
	return UITheme.contrast(mean, surf)


## The same number as ui_smoke's proxy, recomputed here so the two can be
## compared in one run.
func _proxy(key: String, chapter: int) -> float:
	var e: Array = meta[key]["edge_rgb"]
	var edge := Color8(int(e[0]), int(e[1]), int(e[2]))
	var lit := edge.lerp(UITheme.ROT_RIM, clampf(UITheme.rot_rim_for(chapter), 0.0, 1.0))
	return UITheme.contrast(lit, UITheme.surface(chapter))
```

Create `tools/enemy_legibility.tscn` —— 照抄 `tools/pawn_extents.tscn` 嘅結構,`script` 指去 `enemy_legibility.gd`,root node 叫 `EnemyLegibility`。

- [ ] **Step 2: 跑真 render(要視窗)**

Run:
```bash
"C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe" --path . \
  --log-file art_export/legib.log tools/enemy_legibility.tscn
sed -e 's/\r$//' art_export/legib.log | grep LEGIBILITY
```
Expected: 37 行量度 + `WORST-DELTA` + `CALIBRATED` / `PROXY NEEDS FIXING`。

- [ ] **Step 3: 對數(收貨閘)**

睇 `WORST-DELTA`:

- **≤ 0.15** → 印 `CALIBRATED`,代理可信,去 Step 5。
- **> 0.15** → 代理錯咗。**以真 render 為準。** 睇 delta 最大嗰幾行嘅方向:
  - 代理**高估**(proxy > real):通常係 `lit_edge()` 當咗 `edge = 1.0`,但真 render 嘅 rim 冇食晒成條邊。喺 `ui_smoke.lit_edge()` 嘅 `rot_rim_for` 上面乘一個 `EDGE_COVERAGE` 係數,由最差嗰幾個 case 反解出嚟。
  - 代理**低估**:`edge_rgb` 取樣帶太深,喺 `enemy_cutout.py` 將 `edge_band_rgb(..., px=3)` 收窄到 2,重跑 pipeline。
  改完之後**返 Step 2 重量**,直到 `CALIBRATED`。

- [ ] **Step 4: 校完之後,代理要重新全綠**

Run: `bash tools/run.sh t_ui_smoke "res://tests/ui_smoke.tscn"`
Expected: `UI SMOKE OK`,而且 `enemy legibility (proxy): worst is …` 嗰個數要 ≥ 2.4。

如果校完代理之後有 case 跌穿 2.4:1 —— 咁即係**本來就唔夠**,代理之前係報喜不報憂。加強 `rot_rim_for` 再由 Step 2 行過。

- [ ] **Step 5: 兩把尺都綠先算數**

Run: `bash tools/test_all.sh`
Expected: `ALL SUITES PASSED`,而且 Step 2 嗰個 log 印 `CALIBRATED`。

- [ ] **Step 6: Commit**

```bash
git add tools/enemy_legibility.gd tools/enemy_legibility.tscn tests/ui_smoke.gd scripts/ui/ui_theme.gd
git commit -m "test(art): 真 render 量輪廓可辨性,同 headless 代理對數校正"
```

---

## Task 7: extents 覆核、gallery、實戰截圖、540 抽驗

**Files:**
- Modify: `tools/pawn_extents.gd`
- Run(唔改): `tools/pawn_gallery.gd`、`tools/gallery_export.gd`

**Interfaces:**
- Consumes: Task 4 貼咗嘅 `PawnArt.EXTENT`
- Produces: `art_iterations/sprite_1/` 37 張 + contact sheets;`art_iterations/iter_sprite/` 嘅三章實戰同 540 抽驗

- [ ] **Step 1: `pawn_extents` 改成覆核**

Modify `tools/pawn_extents.gd` —— 頭嗰段 doc comment 換,同埋喺 `_ready()` 印完之後加一段比對:

```gdscript
	# The sprites are trimmed to their own alpha bounds, so the measured extent
	# has to agree with what `PawnArt.EXTENT` was told. A mismatch means the
	# printed block from `tools/enemy_cutout.py` was pasted wrong, or a plate
	# was re-cut without re-pasting.
	var bad := 0
	for k3 in KINDS:
		var have: Vector2 = PawnArt.extent(k3)
		var got: Array = out[k3]
		if absf(have.x - float(got[0])) > 0.02 or absf(have.y - float(got[1])) > 0.02:
			bad += 1
			print("  MISMATCH %-5s EXTENT=(%.2f, %.2f) measured=(%.2f, %.2f)"
					% [k3, have.x, have.y, got[0], got[1]])
	print("EXTENTS: %d kinds, %d mismatches" % [KINDS.size(), bad])
```

- [ ] **Step 2: 跑覆核(要視窗)**

Run:
```bash
"C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe" --path . \
  --log-file art_export/extents.log tools/pawn_extents.tscn
sed -e 's/\r$//' art_export/extents.log | grep -E "MISMATCH|EXTENTS:"
```
Expected: `EXTENTS: 23 kinds, 0 mismatches`。有 mismatch 就將印出嗰個 `PAWN_EXTENT` block 重新貼入 `PawnArt.EXTENT`,再跑過。

- [ ] **Step 3: 射 37 張 gallery(要視窗)**

Run:
```bash
"C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe" --path . \
  --log-file art_export/pawns.log tools/pawn_gallery.tscn -- --out res://art_iterations/sprite_1/
sed -e 's/\r$//' art_export/pawns.log | grep -E "PAWNS|ERROR"
find art_iterations/sprite_1 -name '*.png' | wc -l
```
Expected: `PAWNS: DONE 41 shots`(37 張單張 + 4 張 contact sheet),`41`。

- [ ] **Step 4: 用眼睇(必做)**

用 Read tool 開 `art_iterations/sprite_1/sheet_t1.png`、`sheet_t2.png`、`sheet_t3.png`、`sheet_boss.png`。逐項確認:

1. **三個 tier 並排一眼分得開** —— 體型 0.90/1.00/1.12、眼發光強度、T3 先有嘅腐化紋 glow、黑霧(T1 冇、T2 少、T3 常駐)。分唔開就調 `EYE_GAIN` / `VEIN_GAIN` / `MIST_COUNT`,唔好調體型(0.90/1.00/1.12 係定咗嘅)。
2. **暗底可讀性** —— 第 3 章嗰啲卡,輪廓要同卡面分得開。
3. **邊緣質素** —— 冇白邊、冇灰煙殘留。
4. **解析度** —— 逐隻睇喺 200px 有冇明顯起毛。E02 鼠(源 143px)係頭號嫌疑。起毛嘅記低,入補圖清單。

- [ ] **Step 5: 三章實戰 + 540 抽驗(要視窗)**

Run:
```bash
bash tools/gallery.sh sprite --only battle
bash tools/gallery.sh sprite540 --res 540
```
Expected: 兩次都有檔案數 > 0。

- [ ] **Step 6: 用眼睇實戰同 540**

Read `art_iterations/iter_sprite/15_battle_ch1.png`、`15_battle_ch2.png`、`15_battle_ch3.png`,同 540 嗰組對應嘅圖。確認:三章都認得出邊隻係邊隻;540 之下三隻剪影仍然各自認得出;圖鑑 / 意圖區 / 長按詳情嘅新圖冇爆版。

- [ ] **Step 7: 跑全套**

Run: `bash tools/test_all.sh`
Expected: `ALL SUITES PASSED`。

- [ ] **Step 8: Commit**

```bash
git add tools/pawn_extents.gd scripts/ui/pawn_art.gd art_iterations/sprite_1
git commit -m "chore(art): 由 sprite alpha bounds 覆核 extents,射 37 張 gallery 同三章實戰"
```

---

## Task 8: DECISIONS.md 同補圖清單

**Files:**
- Modify: `DECISIONS.md`
- Modify: `docs/design/2026-08-07-enemy-sprite-art.md`(補上補圖清單)

- [ ] **Step 1: 寫 DECISIONS.md**

喺 `DECISIONS.md` 加以下幾節(依家嗰啲判斷保留,呢批係新增):

1. **「墨線輪廓 + 填內部」係呢批 AI 圖嘅通用刀法** —— 捉住生成特性:主體必有封閉墨線、雜物必冇。一招同時殺黐身灰煙、封藤嘅內圈奶白窟窿、掃 ✦ 水印。以後所有同源 AI 圖都用呢把刀,唔好返轉頭做 cream key。
2. **手畫造型 routine 全刪,唔留 fallback** —— 留住唔係保險,係一個貼圖 load 失敗就自動違反鐵律嘅後門。`_draw()` 而家搵唔到 plate 就乜都唔畫。要考古有 git history。
3. **`_mist`/`_wisp` 留低,`_rim` 刪咗** —— 煙同光係特效唔係生物造型;rim 而家係 shader 做。黑霧位置由 sprite 闊度自動撒,唔再手寫座標(手寫座標綁死喺舊造型上面)。
4. **shader 認色而唔係查表** —— 圖入面本來就有洋紅眼同洋紅裂紋,gain 落去就得,零手工資料,換圖唔使重量。界線由 `tools/enemy_hsv.py` 量出(記低揀咗嘅四個數同直方圖谷底喺邊個 bin)。橙帶單獨一條路,保住蟾蜍岩漿係「熱唔係腐」。
5. **rim 係內側唔係外側** —— sprite trim 到 alpha bounds,向外會俾 rect 切走;向內反而正正落喺圖本身條粗墨線上,即係近黑卡面上最易溶掉嗰部分。
6. **可讀性有兩把尺,而且對過數** —— headless 代理(`edge_rgb` + `rot_rim_for`)全量跑,真 render(`tools/enemy_legibility.gd`)做憑證。兩者差距門檻 0.15:1,超過以真 render 為準、返轉頭校代理。**記低今次實際 WORST-DELTA 係幾多、有冇校過、校咗乜。**
7. **E05/E06 用 solo plate 唔用合集中間格** —— 合集格得 145/203px(solo 1024px),而且合集嘅藤內圈有奶白窟窿。合集中間格上蛾下藤切得開(已驗證兩件唔黐),只係質素差。

- [ ] **Step 2: 寫補圖清單**

喺 `docs/design/2026-08-07-enemy-sprite-art.md` 尾加一節 `## 需要補圖清單`。內容由 Task 7 Step 4/6 真眼睇嘅結果決定,**唔准預先填**。每一項寫明:

- 邊個 key、邊度睇到問題(實戰 / 圖鑑 tier strip / boss strip / 長按詳情 / 540)
- 問題係「起毛」定「切唔乾淨」定「肢體缺失」
- 要生成乜:**主體係咩、咩姿勢、要對齊返合集嗰隻嘅造型**(補圖係換解析度,唔係換設計)
- 參考格式:「E02 毒鼠 —— 單隻獨立圖,1024×1024,奶白背景,同合集第 1 行中間嗰隻同一造型(四足側身、張口露齒、長尾上揚、洋紅裂紋 + 洋紅眼)」

如果 Task 7 睇完乜事都冇,就寫「本輪冇需要補圖」同埋列明係喺邊幾個放大位覆核過。

- [ ] **Step 3: Commit**

```bash
git add DECISIONS.md docs/design/2026-08-07-enemy-sprite-art.md
git commit -m "docs: 記低敵人 sprite 改版嘅判斷同補圖清單"
```

---

## Self-Review

**Spec coverage**

| Spec 要求 | Task |
|---|---|
| 逐隻裁出、去背、邊緣清乾淨、trim、輸出 `assets/enemies/` | 1 |
| monster sheet 對應表 | 1(`SHEET_CELLS`) |
| 中間格蛾/藤切唔乾淨就唔用、先搵獨立圖 | 1(已搵到 solo,`SOLO`) |
| B3 階段 1 騎鵝 / 階段 2 獨立圖 | 1(`B3` / `B3P2`) |
| tier 體型 0.90/1.00/1.12 | 4(`TIER_BULK` 原樣) |
| T1/T2/T3 眼發光、黑霧、腐化紋 glow 遞進 | 3(shader)+ 4(`EYE_GAIN`/`VEIN_GAIN`/`MIST_COUNT`) |
| 全部用 shader/modulate/粒子疊加,唔改圖入面造型 | 3、4 |
| 三 tier 並排一眼分得開 | 7 Step 4 |
| 唔准調圖顏色,改為 rim light/outline glow | 3(shader rim)、5(禁止改 sprite 顏色) |
| rim 強度按章節自動調 | 3(`rot_rim_for`)+ 4(傳 chapter) |
| `_t_enemy_legibility()` 門檻維持 2.4:1,改量輪廓可辨性 | 5 |
| 實測三章全過先收貨 | 6 |
| 代理同真 render 對數,0.15:1 門檻 | 6 Step 3 |
| idle/lunge/受擊閃光沿用 | 4(`play_attack`、`_process` 唔郁) |
| boss 黑霧同腐化 glow 用現有特效系統 | 4(`_mist`/`_wisp` 保留) |
| pawn_extents 由 alpha bounds 重量 | 7 Step 1-2 |
| fitted 正常 | 4(`EXTENT` x=1.00)、7 Step 2 |
| 圖鑑/意圖區/長按詳情自動用新圖並覆核 | 4 Step 4、7 Step 6 |
| 精英 badge 不變 | 冇 task —— 冇掂 `_status_chips`/badge 程式碼 |
| 37 張 gallery | 7 Step 3 |
| 三章實戰截圖 | 7 Step 5 |
| 540 抽驗 | 7 Step 5 |
| 全部測試套件綠 | 每個 task 尾 + 7 Step 7 |
| 需要補圖清單 | 8 Step 2 |
| 判斷記入 DECISIONS.md | 8 Step 1 |
| 只改視覺,唔掂 gameplay | Global Constraints |

**Placeholder scan:** 冇 TBD/TODO。唯一「稍後填」係 Task 8 Step 2 嘅補圖清單內容 —— 嗰個係**特登**要等 Task 7 真眼睇先寫,格式同判斷準則已經寫實。

**Type consistency:** `enemy_texture` / `plate` / `chapter_of` / `BOSS_CHAPTER` / `rot_rim_for` / `edge_band_rgb` / `subject_mask` / `lit_edge` 喺定義同使用兩邊名一致。`EXTENT` 嘅 key 集(17 敵 + 6 主角)同 `pawn_extents.KINDS` 一致(23)。shader uniform 名同 `_apply_rot_material()` 嘅 `set_shader_parameter` 名一致。

**一個要注意嘅次序依賴:** Task 4 唔准刪 `BODY`/`rot_body`(舊 `_t_enemy_legibility` 仲用緊),Task 5 先刪。計劃入面已經寫明。
