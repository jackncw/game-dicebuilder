# 骰林 Dice Grove — 世界觀與 Boss 美術方向
# World Direction and Boss Art Spec

*2026-08-06,角色大改版輪。本文件是設計方向書,不是排期。*
*Written alongside the character overhaul. This is a direction document, not a schedule.*

---

## 1. 玩家陣營:森林義勇軍 The Grove Militia

六個玩家角色是**武裝小動物**,不是英雄、不是神選之人。他們是被逼上陣的鄰居:
獾是退伍的老班長,野兔是獵戶,刺蝟是打鐵的,梟是村裡最老的那位,狐狸來歷不明,
野豬只是很生氣。

The six playable characters are **armed woodland animals** — not heroes, not chosen
ones. They are neighbours who had to pick something up: a retired sergeant, a
hunter, a smith, the oldest bird in the village, someone with a past, and one who
is simply furious.

### 視覺規則 Visual rules

| 項目 | 規則 |
|---|---|
| 體型 | 擬人化,直立,約 5–6 頭身;比例接近人類矮壯體型 |
| 裝備 | **拼湊的**:皮甲、麻布、生鏽的鐵件、繩索、獸骨扣。沒有一件是配套的 |
| 武器 | 農具與獵具改造:斧、獵弓、圓木盾配短錘、雙匕、法杖、石鎚 |
| 色調 | 泥土色為主(棕、卡其、暗綠),每人一個記憶色點綴(狐狸的藍圍巾、梟的琥珀晶石) |
| 線條 | 統一的深色描邊,平塗上色,柔和陰影 |
| 表情 | 疲憊但不畏縮。他們知道自己在做甚麼,也知道代價 |

**已實裝**:六張立繪(`assets/heroes/*_full.png`)加頭像(`*_head.png`),
由 `tools/art_cutout.py` 從 `Art reference/character_*.jfif` 去背、對齊色溫後輸出。
六張已做全套色調對齊,不會有一張特別黃或特別灰。

---

## 2. 敵方陣營

### 2.1 小怪:維持現狀 Minions — unchanged

小怪是**普通的森林動物與菌菇**:史萊姆、老鼠、孢子菌、甲蟲、飛蛾、藤蔓、
骨狼、幽靈、火蟾、雙頭蛇。牠們不是被腐化的,只是餓、只是護巢、只是本來就住在那。

這一批**這輪不動**,程序繪製的現有造型繼續沿用。牠們的作用是襯托 —— 正因為
小怪只是動物,巨獸出場時的落差才有意義。

Minions stay exactly as they are: ordinary forest animals and fungi, procedurally
drawn. They are the baseline that makes the bosses land. **No art work this round.**

### 2.2 Boss:被腐化嘅巨獸 Corrupted Great Beasts

**這是本輪定下、下一批 boss 出圖要跟的 spec。現有 boss 美術暫時沿用,
不在這輪重畫。**

**This is the spec the NEXT batch of boss art follows. The existing boss art
stays in place for now and is not being redrawn this round.**

六隻 boss 的新方向:牠們曾經是這片森林的守護者 —— 最大的那頭鹿、最老的那隻熊、
巢裡最深處的那條蛇。腐化不是外來的怪物入侵,是**森林自己病了**,而病得最重的
永遠是最大最老的那幾隻。

The bosses were the forest's own guardians: the biggest stag, the oldest bear, the
snake at the bottom of the burrow. The corruption is not an invasion — the forest
is sick, and what sickens worst is always what is largest and oldest.

#### Boss 出圖規則 Boss art rules

| # | 規則 | 說明 |
|---|---|---|
| B-1 | **體型明顯大幾倍** | 站在玩家角色旁邊要有 3–5 倍的體積差。畫面上 boss 應該撐爆自己的框,而不是安分坐在框裡 |
| B-2 | **剪影黑化** | 主體向暗部壓,細節被吞掉。玩家角色是「看得清每一條皮帶」,boss 是「看得見一個形狀」。剪影本身要可辨識(角、背脊、翼) |
| B-3 | **身上腐化發光紋** | 沿肌肉走向、關節、舊傷口爬行的發光裂紋。**單一冷色**(建議腐化紫 `#9b6dd9` 或病綠 `#6fae5c`),與玩家陣營的泥土色形成唯一的高彩對比。紋路要看得出是「從體內滲出來」,不是畫在皮膚表面的圖案 |
| B-4 | **武器可保留,但巨型粗野化** | 如果牠拿東西,那東西應該是「本來的東西長大了、爛掉了」:裂開的木樁、纏著鏈的巨石、鏽死的農具。不要給 boss 精緻的武器 —— 精緻是義勇軍那邊的事 |
| B-5 | **眼睛是唯一的亮點** | 在黑化剪影裡,發光的眼睛是玩家第一眼會找的東西。與腐化紋同色 |
| B-6 | **仍然看得出物種** | 腐化不改變牠是甚麼。玩家要能認出「這是一頭鹿」,然後才意識到牠不對勁 |

#### 反例 What NOT to do

- ❌ 骷髏、亡靈、惡魔 —— 這不是死靈題材,腐化的東西還活著,而且很痛
- ❌ 機械、科技感 —— 森林裡沒有這種東西
- ❌ 把 boss 畫成「大一號的小怪」—— 體型差不夠就沒有壓迫感
- ❌ 多色發光 —— 腐化只有一種顏色,多了就變成霓虹燈

#### 現有六隻的改造方向 Direction for the existing six

| id | 現有 | 新方向 |
|---|---|---|
| B1 | 重擊兔 | 巨鹿:角已經長成不對稱的一團,腐化紋沿角的分叉爬 |
| B2 | 拳擊野兔 | 巨獾/熊:前肢過度發達,背脊拱起,舊傷口全部在發光 |
| B3 | 劍豪鵝騎士 | 巨鶴:頸過長,羽毛半數脫落露出發光的皮下紋路 |
| B4 | 魚骨貓 | 巨貓科:肋骨外突,尾巴分岔,腐化從口鼻滲出 |
| B5 | 武裝喵騎士 | 巨野豬:獠牙長到穿透自己的臉頰,鏽甲長進肉裡 |
| B6 | 蛙巫師 | 巨蟾/樹靈:已經半植物化,腐化紋是樹根的形狀 |

上表是**方向**不是定案 —— 出圖時以 B-1…B-6 六條規則為準,物種可調整。

---

## 3. 這輪未做、留給下一輪的

- Boss 立繪重畫(本文件即是那批圖的 spec)
- 小怪美術(維持程序繪製,沒有改動計劃)
- 腐化紋的 shader 化(目前 boss 是程序繪製,發光紋要等真圖進來才有意義)
- 世界觀文案:六隻 boss 的圖鑑描述仍然是舊的,應該在出圖那輪一併重寫
