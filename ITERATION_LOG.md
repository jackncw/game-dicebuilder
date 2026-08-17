# 美術/UI 打磨輪 — ITERATION LOG

工具:`bash tools/gallery.sh <N> [--only tag] [--res 720|540]`
輸出:`art_iterations/iter_<N>/720/` + `.../540/`
評級:**P1** 嚴重(必修) / **P2** 明顯(盡量修) / **P3** 吹毛求疵 / ✅ 合格

---

## Iteration 1 — 基建

### 做咗乜

| 項目 | 檔案 |
|---|---|
| 設計 token 檔(spacing 4/8/12/16/24/32、圓角、描邊、三級字階、章節色版、對比度計算) | `scripts/ui/ui_theme.gd` (new) |
| `UIKit` 改為由 token 組裝;新增 `card()` / `card_box()` / `title()` / `text_block()` / `background()` / `cat_text()` / `surface()` | `scripts/ui/ui_kit.gd` |
| Gallery exporter:29 個畫面 × (戰鬥/圖鑑三語) × 720/540 = **84 張** | `tools/gallery_export.gd`, `tools/gallery.sh` |
| **G bug 修復**:浮動數字錨點 | `scripts/ui/screen_battle.gd` |

**G bug 根因同修法**:`_do_use()` → `_refresh()` → `_spawn_floats()`。`_refresh()` 會
`queue_free()` 成行卡片再起新嘅,新卡片喺同一 frame 未 sort 過,`get_global_rect()`
仲係 `(0,0,0,0)`,所以數字飛咗去左上角。修法:`_refresh()` **開頭**(未 free 之前)
用 `_capture_anchors()` 影低每個敵人/英雄卡嘅位,`_float_at_*()` 只喺 rect 真係
layout 過(`_laid_out()`:size>1 且 position≠0)先信 live rect,否則用快照;兩者
都冇就用幾何 fallback。座標仲會經 `_to_float_space()` 轉入 `float_layer` 空間,
所以 screen 被包喺有 transform 嘅父層(gallery exporter 就係)都準。
→ 驗證:`12_battle_enemy_both.png` 敵人結算,`-1 -1` 準確出喺 Moss 身上。

### 評審(iter_1)

#### A 可讀性
| # | 畫面 | 問題 | 級 |
|---|---|---|---|
| A1 | 全部戰鬥 | 敵人/英雄卡用 `Color(1,1,1,0.10)` 疊喺章節底色上 — 卡同底幾乎同色,只靠描邊分開;卡上 cream 文字對比度受底色擺佈 | P1 |
| A2 | `13_battle_status` | 狀態係一行文字湯「防5 毒6 燒4 棘3 弱2」,細、逼、無層次 | P1 |
| A3 | `54_victory` | 標題「森林已回復平靜! The forest is at peace!」冇 wrap,右邊爆框截字 | P1 |
| A4 | `02_charselect` | 2 欄卡右邊爆出畫面外 | P1 |
| A5 | 所有按鈕 | disabled 態(復原 Undo)灰底 + `#d8d4cb` 字 ≈ 1.9:1,讀唔到 | P1 |
| A6 | 540 全部 | 骰面名 12px × 0.75 ≈ 9px,雙語兩行,細到臨界 | P2 |
| A7 | `12_battle_enemy` | 同一目標兩個浮動數字重疊變「-1-1」 | P2 |

#### B 視覺層級
| # | 畫面 | 問題 | 級 |
|---|---|---|---|
| B1 | 全部戰鬥 | 玩家要做嘅嘢(骰、按鈕)同裝飾一樣搶眼;敵人卡太淡,意圖 chip 細過骰 | P1 |
| B2 | `21`–`26` boss | Boss 同小怪同一個卡尺寸,完全冇「王」嘅氣勢 | P1 |
| B3 | 骰三態 | 已用/鎖定/不可用:🔒 badge + 灰面 + veil 分得開 ✅ | ✅ |

#### C 一致性
| # | 畫面 | 問題 | 級 |
|---|---|---|---|
| C1 | 全部 | spacing 硬編碼(2/3/4/6/10/12/14/16/18/20/24/26/28/40…),未跟 4/8/12/16/24/32 | P1 |
| C2 | 全部 | 字級硬編碼 12–84 共 20 幾種,無三級制 | P1 |
| C3 | `32_shop` | 骰面卡(name+summary 兩行)同遺物/藥水(Button 多行 text)兩種完全唔同嘅卡型 | P2 |
| C4 | `03_map` | 節點只有中文字(戰/事/精/店/營/寶/王),純英文模式冇對應 | P2 |
| C5 | 藥水按鈕 | `Data.bi(pd.zh, "")` 寫死空英文,雙語模式下同其他 UI 唔一致 | P2 |

#### D 風格
| # | 畫面 | 問題 | 級 |
|---|---|---|---|
| D1 | 骰 | 2.5D 立方體 + 投影 + gloss,立體感成立 ✅ | ✅ |
| D2 | 戰鬥 | 章節色調只係一塊純色 + 一條 0.18 黑帶,`y=410` 有條硬邊接縫喺空白中間 | P2 |
| D3 | `01_menu` | 純色背景 + 5 個灰白按鈕,零裝飾,似 debug 選單 | P1 |
| D4 | `50_settings` | 音量用 Godot 預設 HSlider(灰線 + 灰波子),明顯 default 殘留 | P1 |

#### E 動效
| # | 項目 | 狀態 | 級 |
|---|---|---|---|
| E1 | 擲骰翻滾 | staggered tumble + elastic settle,有重量 ✅ | ✅ |
| E2 | 攻擊 lunge / 震屏 / 浮動數字 | 有,但浮動數字會疊字 | P2 |
| E3 | 畫面轉場 | 完全冇 — screen 之間硬切 | P2 |

#### F 完成度(placeholder 清單)
| # | 位置 | 問題 | 級 |
|---|---|---|---|
| F1 | 戰鬥 | `y≈300–520`、`y≈1070–1280` 兩大片死位,約佔螢幕 **35%** | P1 |
| F2 | `33_rest` `34_treasure` `35/36_event` `53_gameover` `01_menu` | 內容置中,上下各留 300–500px 純色空白 | P1 |
| F3 | `50_settings` | 預設 HSlider | P1 |
| F4 | `03_map` | 節點係純色圓形 + 一個字,冇圖示、冇圖例 | P2 |
| F5 | `34_treasure` | 三個 offer 撞到同一個面(連環擊 ×3)— 屬 `gen_treasure` 資料層,呢輪唔郁,已記錄 | 記錄 |

#### G 已知 bug
| # | 狀態 |
|---|---|
| G1 傷害數字飄左上角 | **已修**,見上文;`12_battle_enemy_both.png` 為證 ✅ |

### 本輪結論
P1 = 13 個。iteration 2 打戰鬥畫面 + 共用 widget;iteration 3 打其餘畫面版面。

---

## Iteration 2 — 戰鬥畫面 + 共用 widget

### 改動
| 項目 | 檔案 |
|---|---|
| 戰鬥版面重排:固定分區常數(敵人 64–466 / 地平線 474 / 施放區 492–584 / 英雄 596–1026 / 底部 tray 244px 釘死喺畫面底) | `screen_battle.gd` |
| 施放區改為**常駐**(閒置 55% 透明,拖住無目標骰先著綠) — 順手填走中段死位兼教操作 | `screen_battle.gd` |
| 敵人/英雄卡由 `Color(1,1,1,0.10)` 改為實色 `UITheme.surface(chapter)` + 陰影;敵人卡底部對齊「地面」 | `screen_battle.gd` |
| Boss 尺寸下限(art ≥210px、卡 ≥236px)+「首領 BOSS」標籤 + 紅色卡名 | `screen_battle.gd` |
| 狀態文字湯 → 會自動換行嘅 chip 排(同敵人意圖 chip、骰面分類條同一套語法) | `screen_battle.gd` |
| `UIKit.chip()`:深底 + 奶油字 + 亮色鑲邊。飽和中間色調載唔起 4.5:1 嘅字(紅/藍/紫全部得 ~3.2),所以全部細徽章統一呢個做法 | `ui_kit.gd`, `ui_theme.gd` (`CAT_DEEP`) |
| `hp_bar` 修 bug:`bg` 用 anchors 會被 HBoxContainer 拉高,填充條下面永遠有條黑坑。改為全部固定尺寸 + `SHRINK_CENTER` | `ui_kit.gd` |
| disabled 按鈕改為單一中性灰 `#b0aba0` + 深字 `#3a372f`(4.9:1);之前係 1.9:1 | `ui_kit.gd` |
| 浮動數字:同一目標第 N 個數字自動錯開;字級 30→34、描邊 6→8、置中對齊 | `screen_battle.gd` |
| 傷害預覽由綠 chip 改紅(綠 = 治療類別) | `screen_battle.gd` |
| 樹線背景(兩排扁平針葉樹,確定性高度/闊度,唔會閃) | `screen_battle.gd` → 之後升做 `UIKit.Treeline` |
| **`PawnArt.EXTENT` + `fit_height()` / `fitted()`** | `pawn_art.gd`, `tools/pawn_extents.gd` (new) |

**PawnArt 量度**:每隻造型都係人手畫,實際佔用高度差好遠(史萊姆只用 0.51×
`body_h`,蛙大巫師用 1.27×)。用名義高度排版就出現「細怪縮喺大卡中間一大浸空
位、boss 個帽爬上卡名度」。寫咗 `tools/pawn_extents.gd` 逐隻 render 入透明
SubViewport、量 alpha bounding box,得出 22 個 `Vector2(上伸, 半闊)`;
`fitted(kind, box)` 就按兩軸取細嗰個縮放,填滿個框又唔會爆框。

### 評審重點(對比 iter_1)
- F1 死位 **35% → ~6%** ✅
- A1 卡片對比:cream on `surface(1)` = **11.1:1** ✅
- B2 Boss 氣勢 ✅ / A5 disabled 對比 ✅ / A7 浮動數字疊字 ✅
- 新發現 P1:B3/B6 boss 造型爬上卡名(由 PawnArt 量度解決)

---

## Iteration 3 — 其餘畫面版面

### 改動
| 畫面 | 改動 |
|---|---|
| `UIKit` | 新增 `background(chapter, canopy, horizon)`、`Treeline`、`footer()`、`button_row()`、`slider()`、`glyph()/glyph_n()` |
| 主選單 | 由 5 個灰按鈕 → 標題牌匾 + 標語 + 隊伍企喺林地上 + 地面散落三粒真骰(用 `DieVisual`) |
| 地圖 | 節點由單個中文字 → **自繪圖示**(交叉劍/問號/星/皇冠/金幣/帳篷/寶箱),語言中立;底部 tray |
| 角色選擇 | 卡由 320→336 修爆框;鎖住嘅卡改為淺卡 + 純黑剪影(之前黑卡黑剪影 = 睇唔到);加「已揀 N/4」 |
| 設定 | Godot 預設 HSlider → `UIKit.slider()`;三張分區卡(音量/語言/危險區) |
| 勝利 | 標題加 wrap(之前雙語爆框截字);英雄解鎖改為頭像卡 |
| 失敗 | 加樹線、倒地隊伍、章節碑 |
| 商店 | 遺物/藥水/鍛造由多行 Button → 同 `offer_card()` 一套卡型;價錢改為右側金色 chip |
| 獎勵/寶箱/事件/休息 | 統一 `background + 頂對齊內容 + footer/隊伍剪影`;休息改為圍住營火嘅營地 |
| 圖鑑 | 未解鎖骰面由 55 行 `???` 壓縮成 `??? ×55` 一行;卡片改實色 surface |
| 頂欄 | 金幣/藥水/遺物改 chip(之前彩色字直接印喺天空底,對比唔夠) |

### 本輪引入又即刻修返嘅 regression
- `UIKit.text_block(width = 0)` 開住 autowrap → 喺 `CenterContainer` 入面塌成
  一個字一行,主選單標題變咗直排。修法:`width <= 0` 就唔開 autowrap。

---

## Iteration 4 — 語言一致性 + 細節

| 項目 | 詳情 |
|---|---|
| **C4 雙語一致性** | `UIKit.ICON_EN` + `glyph()`:純英文模式所有 chip / 骰面圖示 / 圖鑑摘要由「攻防毒燒」轉做 `ATK BLK PSN BRN`。雙語模式保留漢字(一個 chip 得一個漢字或三個字母嘅位,冇得兩樣都放) |
| 骰面大字 | 3 個字元以上(`STN`/`WLD`)自動由 34px 縮到 23px,唔會爆出 68px 骰面 |
| 骰面名 box | 38 → 46px:英文名 `Arrow Shot` 要兩行,之前第二行被切走 |
| 英雄狀態 chip | `F_MICRO(12)` → `F_CAPTION(15)`,540 解像度下先讀得到 |
| 浮動數字錨點 | 卡頂 +60 → +96,落喺角色身上而唔係壓住名牌 |
| 商店卡 | 價錢 chip 會遮長描述 → 文字欄右邊讓出 84px |
| 主選單/休息 | 標語闊度、地面高度、營火(石圈 + 交叉木 + 三塊火焰) |

---

## Iteration 5 / 6 — 收尾 + 驗收輪

| 項目 | 詳情 |
|---|---|
| 對比度收尾 | 直接印喺章節天空底嘅字全部改 `CREAM`:`CREAM_DARK` 喺第 1 章底色只有 **3.9:1**,`accent` 更差(2.9:1)。卡入面照用 `CREAM_DARK`(≥7:1) |
| **對比度回歸測試** | `tests/ui_smoke.gd::_t_contrast()` — 逐對驗 3 個章節 × (卡/tray/天空) × (cream / cream-dark / 六個 accent) + 六個 chip 底 + ink-on-cream + disabled 按鈕,全部要 ≥4.5:1 |

### iter_6 驗收評審 — **P1 = 0,P2 = 0** ✅

| 清單 | 判定 |
|---|---|
| A 可讀性 | 全部正文 ≥4.5:1(有測試守住);雙語模式無爆框/截字/重疊;8 粒骰面名兩行讀得晒(720 同 540 都試過);狀態 icon = 15px chip,深底奶油字 |
| B 視覺層級 | 可拖嘅骰係畫面最光嘅嘢(白骰面 + 亮色分類條),敵人卡實色深底退後;意圖 chip 有亮邊、已執行嘅會啞;已用/鎖定/不可用三態 = 灰面 + veil + 🔒/📌 badge |
| C 一致性 | 全遊戲 spacing 只用 4/8/12/16/24/32;字級只用 60/38/28/22/18/15/12 三級制;圓角 6/10/14/20;描邊 2/3/4/5;六色 category 喺骰面條、意圖 chip、狀態 chip、圖鑑、商店卡名同一套 |
| D 風格 | 扁平色塊 + `#2b2b2b` 粗描邊貫徹;奶油 `#f5efe0` 做紙同亮字;三章色調(翠綠/暮橙/暗紫)落到背景、卡面、樹線、營火光暈;骰 2.5D 立方體 + 投影 + gloss + 選中黃環 |
| E 動效 | 擲骰 staggered tumble + elastic 落地;攻擊 lunge;受擊震屏;浮動數字會錯開 |
| F 完成度 | 死位由 35% 減到 ~6%;預設 HSlider 已換;地圖節點有自繪圖示;主選單/休息/失敗/勝利都有場景 |
| G 傷害數字 bug | 已修 + 已截圖驗證 |

### 仍然留低嘅 P3(唔影響達標)
1. 540 解像度下雙語骰面名實際約 9–10px — 睇得到但細。要根治得縮 8 粒骰嘅資訊量,屬設計改動。
2. 畫面之間冇轉場動畫(E3),硬切。屬 `main.gd` 導航層,唔喺「視覺打磨」呢輪範圍。
3. 主選單地面散骰係靜態,冇 idle 動作。
4. `31_pick_replace` 12 格清單下方喺短名單時會有空白(ScrollContainer 本身)。
5. 圖鑑仍然係密集文字表;要再進一步就要改成分頁/摺疊,屬功能改動。

### 記錄(唔喺呢輪範圍,冇郁)
- `34_treasure` 三個 offer 有機會抽到同一個骰面(`RunState.gen_treasure`)。屬資料/規則層,本輪硬性約束禁止改。

---

## 附錄:G bug 第二個根因(iter_6 收尾時先揪到)

第一次修完之後,`14_battle_float_*` 呢張專門為驗證而加嘅截圖仍然見到敵人嘅
`-3` 飄咗去卡左上角外面。用一次性 debug scene 打印座標,揪到真正剩低嘅位:

```
DBG anchor_enemy(refresh 前) = { 0: (248, 320) }   ← 啱
DBG anchor_enemy(_do_use 後) = { 0: (106, 194) }   ← 俾人改壞咗
```

`_float_at_enemy()` 本身有一段「如果 live rect 睇落 layout 好咗就順手更新快照」。
問題係我原本嘅 `_laid_out()` 只驗 `position != Vector2.ZERO` —— 而**啱啱加入
置中 HBoxContainer 嘅新卡係「半排好」嘅**:佢已經攞到 row 嘅 y(64),但 x 仲係
0。`(0, 64) != Vector2.ZERO` → 檢查過關 → 一個好嘅快照被一個垃圾值蓋咗。

修法:
1. `_laid_out()` 兩軸都要 > 0.5,唔再接受半排好嘅 rect;
2. **`_float_at_*()` 完全唔再讀 live rect**,淨係讀快照;
3. `_refresh()` 尾加 `_capture_anchors.call_deferred()` —— container 嘅
   `queue_sort()` 喺重建期間排咗隊,deferred call 喺佢之後行,所以嗰一刻先係
   唯一可以信新 rect 嘅時機。

### 驗證
- **截圖**:`final/720/14_battle_float_both.png` — `-3` 準確落喺綠史萊姆身上。
- **自動測試**:`tests/ui_smoke.gd::_t_float_anchors()` — 分別驗英雄側
  (`enemy_hit` 事件)同敵人側(打一下,經完整 `_do_use` → `_refresh()` 重建),
  斷言浮動數字嘅中心點**落喺目標卡嘅 rect 入面**。兩個 case 都 pass。
  (呢個 assertion 比截圖更硬:截圖有機會撞啱時機,assertion 唔會。)

---

## 第二輪(真人試玩回饋)

| # | 回饋 | 做咗乜 | 驗證 |
|---|---|---|---|
| 1 | 點擊作用於自身嘅骰幾乎一定即刻用咗,好難取消 | 單點只選取/取消,永遠唔會用骰;拖曳要離開按落點 56px 先可以放低;英雄卡嘅 tap 目標縮到只蓋 portrait(以前係成張卡,連骰都冚住);armed 之後懸浮目標會放大 3.5% + 綠框預覽 | `drag_input_test` 加三個 case × 三種 input mode:原地放手、移 30px 停喺合法目標上放手(兩者都唔可以用到骰)、移足距離放喺自己身上(正常用) |
| 2 | 冇骰子感,淨係色版換面 | 每粒骰改成 SubViewport + 倒角立方體,6 面貼程序生成 atlas;等角靜止姿勢見頂面同兩側;長按開詳情浮層,粒骰可以用手指撥住轉(慣性 + 緩慢回正) | stress:8 粒靜止 0.38ms/frame、8 粒同時擲 0.59ms(720×1280、關 vsync)→ 全程 3D,唔使降級 |
| 3 | 擲骰冇「擲落去」感覺 | 彈起 → 兩軸 tumble 2-3 圈 → 彈兩下(旋轉逐下衰減)→ 定格 + squash;每粒隨機 delay 0~0.15s,落地各自出木聲,震屏封頂喺頭三粒 | 總長 0.68s;設定頁「快速動畫」縮到 0.30s |
| 4 | 換骰面純文字、冇換面感、底部角色冇名、睇唔到其他角色啲骰 | 12 面全部 tile 化分 A/B 組,每組配粒細 3D 骰;新面大大隻擺頂;換面動畫(舊 tile 飛走→新 tile 嵌入→骰 spin + 閃光→先確認);底部角色列有頭像同名,四個都撳得(非綁定嗰位標「只可查看」) | 商店/寶箱/獎勵/鍛造全部行同一個介面 |
| 5 | 骰面睇唔明、名詞冇解釋 | 35 個手畫向量 glyph;`data/glossary.json` 做唯一來源(補齊冥想/居合/迴響/淨化/每回合一次等隱含機制);FaceTile + DetailCard 喺戰鬥/換面/圖鑑/商店統一;狀態圖示同敵人意圖用同一套 glyph、長按開同一份解釋;教學加一步示範長按 | `keywords_test` 驗詳情卡數值同解釋都由 glossary 出 |
| 6 | UI/背景/按鈕/圖示太單調 | 三層景深(遠山冠/樹幹/草叢 + 四角暗角)、環境粒子(螢火蟲/落葉/孢子,可關)、木牌按鈕(木紋 + 木釘 + 按落下沉)、面板四角藤蔓、地圖蜿蜒泥路 + 石圈空地 + 兩旁散樹、主選單光束 + 木牌標題、圖鑑改成卡片 + FaceTile grid | `_t_contrast()` 照跑;裝飾只喺 border 同四角,唔入內容區 |
| 7 | 寶箱三選一有機會重複 | `gen_treasure` 去重(重抽 + 排序 pool 補底) | 固定 seed 掃 500 次 |

10 個測試套件全綠。新截圖:`final/`(舊版留喺 `final_round1/`)。

---

## 角色大改版輪 — 2026-08-06

`bash tools/gallery.sh chr` → `art_iterations/iter_chr/{720,540}/`(98 張)
驗收用嘅一套(中英各一)抄咗去 `qa/540/` 同 `qa/720/`。

### 美術 pipeline
`python tools/art_cutout.py --debug` → `assets/heroes/*_full.png` + `*_head.png`,
debug contact sheet 落 `qa/cutout_contact.png` / `qa/head_contact.png`。

六隻角色喺選角、戰鬥、獎勵 offer、圖鑑四個場景都接上咗:
- **選角**:立繪 108px 高,姓名/HP/Lv/被動齊,鎖住嘅角色出剪影
- **戰鬥**:英雄卡立繪(540 下約 55px 高)
- **offer 卡**:`*_head.png` 頭像圓框 —— 呢個係頭像檔存在嘅原因,面部填滿個圈,
  一眼認得出係邊個
- **圖鑑**:立繪放大到 184px,加圖鑑文

### 540 驗收
| 場景 | 判斷 |
|---|---|
| 選角 | ✅ 清晰,六張卡兩欄冇爆框 |
| 圖鑑 | ✅ 最大嘅一個框,細節全出 |
| offer 頭像 | ✅ 面部填滿圓框,認人零難度 |
| 戰鬥英雄卡 | ⚠ 武器同物種輪廓清楚(弓/斧/琥珀杖/圓盾都認得出),但**五官喺呢個尺寸係臨界** —— 四個英雄要塞入 540px,單張只得約 55px 高。建議 Jack 喺真機睇一次再決定要唔要改成用頭像 |

---

## Iteration R6 — 骰面資訊(第六輪任務2)

工具:`bash tools/gallery.sh r6a --only battle`(而家四個解像度:720 / 540 /
390×664 / 360×640,後兩個係真機可視高度,連瀏海 inset)

### 起點:P1 — 骰面唔開 tooltip 就讀唔到
骰上得 glyph + 數字、骰下得一個名。「翻湧 / Surge」對記得嗰個面嘅人有用,對
第一次見嘅人完全冇資訊 —— 讀自己一手八粒骰嘅唯一方法係逐粒長按半秒。

### 第 1 輪 — 加速記 pip + 施放帶效果句

| 做咗 | 檔案 |
|---|---|
| `Shorthand`:主效果 + 代價 + 修飾,最多 3 個 glyph+數字 pip | `scripts/ui/shorthand.gd` (new) |
| `BattleCore.live_face()`:折算晒弱化/蓄力/呼應/被動/遺物之後嘅面 | `scripts/core/battle_core.gd` |
| 骰下第二行 = pip 串;施放帶 = 完整雙語效果句 | `scripts/ui/screen_battle.gd` |
| 敵人意圖 chip 改用同一套 pip 語法 | 同上 |

**自評:P1 未清。** 施放帶**完全空白** —— 文字係啱嘅、句子係啱嘅,但個 Label
高度得 1px。成因:`clip_text = true` 令 Label 嘅最小高度報 1,而 PanelContainer
只會俾細路仔佢嘅最小尺寸。改成真嘅 fit(`_cast_font_for()` 用
`get_multiline_string_size` 逐級試),同時施放帶 62 → 78px(錢由敵人區出)。

### 第 2 輪 — 施放帶活返
✅ 施放帶讀到:「貫矢 Pierce Arrow — 對目標造成 5 點傷害(無視格擋)。/
Deal 5 damage to the target (ignores Block).」而且個 5 係**計晒屏息被動之後**
嘅實際值,唔係 faces.json 入面嗰個 2。

**自評:540 之下 P2。** pip 讀到數字同顏色(紅=攻、藍=擋、綠=療、紫=資源),
但 glyph 形狀喺 11px 之下糊咗,pip 同英雄卡底色差得太少。

### 第 3 輪 — pip 加鑲邊、放大
| 改動 | 理由 |
|---|---|
| pip 加 1px 真色鑲邊 | 冇鑲邊喺深色英雄卡上面糊成一撻;`UIKit.chip` 嘅 2px 會食咗 76px 入面嘅 4px |
| 字級 `F_CAPTION` → `F_BODY_SM` | `_fit` 會等比縮,而**大部分面得 1-2 個 pip**。為常見情況揀大字、罕見情況先縮 |

**自評:P1 清零。**
- 唔開 tooltip 睇到效果 ✅(⚔5 ➤ / 🛡3 棘1 / ✚2 / 🌿+1)
- 540 之下讀到 ✅
- 施放帶即時效果句,數值計晒修正 ✅
- 敵人意圖同玩家骰面講同一種語言 ✅
- 長按 glossary 照舊係最終解釋層 ✅

### 順手量到嘅
- 四個動作掣喺 F_H2 之下加埋 749px > 720px canvas(新增咗靈息重擲掣),
  「結束回合」掛咗出右邊 → 降到 F_BODY,540 之下仍有 16.5 物理像素。
- `layout_test` 由 90 個 assertion 升到 372 個(加咗四個裝置幾何)。

# 第十一輪:大作感打磨(2026-08-17)

驗收方式跟 spec:動效唔靠靜態圖 —— Playwright 對住 web build 錄 video
(`web/tests/round11cap.spec.js`,`CAP=1` 先行),八段片收入 `qa/round11/*.webm`,
逐個時刻自評「聲+光+動」三重齊唔齊。聲喺 video 度聽唔到,用兩個客觀代理:
`window.__dgMusic` 探針(音樂真係開始咗先會寫)+ SFX 檔案接線由 16 suites 罩住。

## 迭代一:首輪錄影自評

| 時刻 | 光 | 動 | 聲(代理) | 判定 |
|---|---|---|---|---|
| 標題畫面 | 木牌 lockup+光柱呼吸+motes | 招牌落地微幌、選單梯次入場 | __dgMusic=title ✅ | ✅ |
| 章節卡+地圖行進 | title 卡(章號+林緣+氛圍句) | 野豬 pawn 沿路三步小跳行到節點 | step×3 接線 | ✅ |
| 入戰鬥轉場 | 頂部直落 wipe,換屏藏喺遮罩後 | 0.10s 落+0.10s 收 | swoosh | ✅ |
| 擲骰 | 落地塵埃 puff | 8 骰 tumble 照舊 | 逐粒 knock+音高 jitter | ✅ |
| Boss 登場 | 黑幕→magenta 中英橫幅→腐化霧 | 橫幅 QUINT 滑入滑出 | __dgMusic=boss ✅(crossfade) | ✅ |
| 結算 | 摘要+三卡梯次彈入 | 金幣 0→23 滾數 | card×4 stagger | ✅ |
| 開寶箱 | 黑幕光柱立起+金粒爆發 | 戰利品翻面現身 | chest(拍+creak) | ✅ |
| 勝利(爆機) | 統計逐行行入 | Music.stop+win stinger | duck 接線 | ✅ |
| 敗北 | 0.85s 慢 fade+安慰統計(章2·戰5·節7) | 「再嚟一局」綠色主掣 | lose stinger | ✅ |

迭代一發現嘅兩個洞:
1. **Boss 腐化霧太疏** —— 12 粒一排,喺黑幕上讀成散星唔係霧。
2. **擊殺消散未上鏡** —— 首輪 battle 片三下攻擊殺唔死 15 HP 小怪,招牌時刻
   得個代碼路徑冇片證。

## 迭代二:修正
- 霧改兩排(22+16 粒、更大更慢飄),讀成一浸腐化湧出嚟。
- battle 錄影改三回合集火 enemy0,焗個 kill 出嚟俾消散上鏡(下表)。

## 迭代二:結果

- **擊殺消散上鏡**(確定性通道 `tools/dissolve_shots.sh`,有窗逐幀影):
  尖牙鼠卡片 rim flash → 身體 5 幀淡出、magenta 孢子上飄 → 卡位讓返俾生還者。
  九幀序列喺 `art_iterations/round11/dissolve_*.png`。
- **Boss 霧加濃**:兩排 22+16 粒、更慢更大,黑幕上讀成湧出嚟嘅腐化,唔再係散星。
- **battle 片**(`qa/round11/battle-hits.webm`):三回合集火,命中浮字/搖屏/
  敵人回合逐拍 telegraph 全上鏡。

## 效能(真 GPU headed,RTX 3070 laptop,540×960)

`web/tests/round11perf.spec.js`(PERF=1 --headed;共用 config 強制 SwiftShader,
perf spec 要自己清走 launch args,唔係量出嚟係 29fps 嘅 SwiftShader 數)。
場面:結束回合×2 —— telegraph 飛行+敵人命中+搖屏+浮字+8骰重擲+塵埃。

| 版本 | fps | worst | >33ms |
|---|---|---|---|
| 迭代一(全量 refresh 每拍重建 8 個 Die3D SubViewport) | 56.7 | 133ms | 7/600 |
| 迭代二(**Die3D 池化**:骰過場 reparent,唔再重建) | 58.5 | **67ms** | 7/600 |

結論:第九輪嗰個 133ms「轉場 hitch」有兩個身位 —— screen 轉場嗰下而家完全藏喺
wipe 遮罩後面(靜態遮罩下長 frame 對眼睛隱形);戰鬥內每拍 refresh 嘅重建成本由
Die3D 池化斬半(133→67ms),剩低 50-67ms 係逐拍全量重建嘅擴散成本(文字 shaping
+卡片重組),冇單一大件可斬 —— diff-based refresh 係下一步,but 喺打磨輪尾段
唔應該掂全 project 最複雜嘅 screen,記入 DECISIONS 做已知債。perf spec 鎖住
58.5fps/67ms/7 呢條線防回退。

## 首載大細(實測 gzip)

| 項 | 舊(第十輪) | 新 |
|---|---|---|
| wasm(gz) | 10.2MB | 10.1MB |
| pck(gz) | 6.7MB | 7.2MB(SFX 163KB+字型+雜項) |
| **首載合計** | ~17MB | **17.3MB** ✅(<18MB) |
| BGM(lazy,唔阻首載) | — | 2.6MB(docs/bgm/,首次要嗰軌先揦) |

中途量過一次 20.0MB(BGM 入 pck)超標 → 改行 spec 建議嘅 streaming 路線。

## 聲音驗收註記

Video 冇聲軌,音訊接線用三重代理驗:(1) `__dgMusic` 探針 —— title/ch1/boss
三個 assert 過晒(即係 fetch→decode→play 全鏈真係行到);(2) 22 個 SFX 檔案
接線由 Sfx 讀檔優先邏輯+16 suites 罩;(3) 上線後真耳驗(live 驗證步)。
