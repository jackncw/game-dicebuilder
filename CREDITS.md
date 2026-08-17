# CREDITS — 外來資產授權清單

呢個遊戲將來會收費上架,所以每一件唔係我哋自己整嘅資產都喺度逐項記低:
來源、作者、授權、連結。收錄標準:**CC0 或明確允許商用**(OFL 字體可;
CC-BY 要記 attribution;CC-BY-NC / CC-BY-SA 一律唔收)。

## 字體

| 資產 | 作者 / 來源 | 授權 | 連結 |
|---|---|---|---|
| Noto Sans TC(subset 入 DiceGroveSans) | Google Fonts | SIL OFL 1.1 | <https://fonts.google.com/noto/specimen/Noto+Sans+TC> |
| Noto Sans Symbols 2(subset) | Google Fonts | SIL OFL 1.1 | <https://fonts.google.com/noto/specimen/Noto+Sans+Symbols+2> |
| Noto Emoji(subset) | Google Fonts | SIL OFL 1.1 | <https://fonts.google.com/noto/specimen/Noto+Emoji> |

OFL 全文喺 `assets/fonts/OFL.txt`。Subset 由 `tools/font_build.py` 產生。

## 音效(assets/audio/sfx/)

全部由 `tools/sfx_build.py` 產生:Kenney 包嘅樣本(CC0 1.0,商用免 attribution,
照記)經修剪/normalize/變調;魔法系事件係純程序合成(原創,無外來樣本)。

| 遊戲事件 | 來源 | 作者 | 授權 |
|---|---|---|---|
| roll(擲骰) | Casino Audio — dice-throw-1 | Kenney (kenney.nl) | CC0 1.0 |
| die(骰落地) | Impact Sounds — impactWood_light_000 | Kenney | CC0 1.0 |
| hit(輕命中) | Impact Sounds — impactSoft_medium_001 | Kenney | CC0 1.0 |
| hit_heavy(重擊) | Impact Sounds — impactPunch_heavy_000 + impactWood_heavy_001 | Kenney | CC0 1.0 |
| block(格擋) | Impact Sounds — impactPlate_light_001 | Kenney | CC0 1.0 |
| pierce(穿刺) | RPG Audio — knifeSlice | Kenney | CC0 1.0 |
| stun(暈眩) | Impact Sounds — impactBell_heavy_002 | Kenney | CC0 1.0 |
| buy(買嘢) | RPG Audio — handleCoins | Kenney | CC0 1.0 |
| card(揭卡) | RPG Audio — bookFlip2 | Kenney | CC0 1.0 |
| swoosh(轉場) | RPG Audio — cloth2 | Kenney | CC0 1.0 |
| button(按鈕) | Interface Sounds — click_001 | Kenney | CC0 1.0 |
| potion(藥水) | Interface Sounds — glass_004 | Kenney | CC0 1.0 |
| chest(開寶箱) | RPG Audio — metalLatch + creak1 | Kenney | CC0 1.0 |
| death(敵人死亡) | Impact Sounds — impactSoft_heavy_001 | Kenney | CC0 1.0 |
| boss(boss 登場鐘) | Impact Sounds — impactBell_heavy_000(降調) | Kenney | CC0 1.0 |
| heal / essence / cast / poison / burn / levelup / boss_swell | 程序合成(`tools/sfx_build.py`) | 本專案 | 原創 |

Kenney 包下載連結(全部 CC0 1.0,<https://kenney.nl/assets>):
[Casino Audio](https://kenney.nl/assets/casino-audio) ·
[Impact Sounds](https://kenney.nl/assets/impact-sounds) ·
[Interface Sounds](https://kenney.nl/assets/interface-sounds) ·
[RPG Audio](https://kenney.nl/assets/rpg-audio)

## 音樂(assets/audio/bgm/)

全部由 `tools/music_build.py` 程序合成(Karplus-Strong 撥弦 + pad + 風底),
無外來樣本 —— 本專案原創,無授權負擔。

## 其他

- 所有美術(英雄/敵人/場景/圖示)為專案內程序繪製或自製 sprite,無外來圖像資產。
- Godot Engine:MIT License(引擎本身,非資產)。
