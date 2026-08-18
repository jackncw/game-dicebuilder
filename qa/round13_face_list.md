# 骰林 Dice Grove — 骰面完整列表(第十三輪,2026-08-18)

由 `data/faces.json` + `data/heroes.json` 生成。**eff** = 數值帶 linter 口徑嘅有效值
(Σ組件價值 − 自損 − 2×靈術費);✦ = 靈息相關面(產生或消耗)。
帶:單攻/防禦 C5-7 / R6-8 / E7-9;治療 C4-5 / R5-6 / E6-7;資源 C4-5 / R6-8;控制 C3-5 / R6-8 / E7-9。

合計 153 面(唔計空白):S 起始 57、C 30、R 40、E 26。

## 獾斧衛士 Badger Vanguard

被動 —— 老班長:所有攻擊面 +1,而且每回合開始時獲得 2 點格擋

### 戰斧骰(起始 6 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `bdg_chop2` | 劈砍 Chop | 攻擊 | S | 攻2 | 2.0 |  |
| `bdg_chop3` | 劈砍 Chop×2 | 攻擊 | S | 攻3 | 3.0 |  |
| `bdg_heavy4` | 重劈 Heavy Chop | 攻擊 | S | 攻4 | 4.0 |  |
| `bdg_guard2` | 格擋 Guard | 防禦 | S | 擋2 | 2.0 |  |
| `bdg_chopguard` | 劈擋 Chop and Guard | 攻擊 | S | 攻2 擋2 | 4.0 |  |

### 行囊骰(起始 6 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `bdgb_guard3` | 格擋 Guard×2 | 防禦 | S | 擋3 | 3.0 |  |
| `bdg_chop2` | 劈砍 Chop | 攻擊 | S | 攻2 | 2.0 |  |
| `bdgb_bandage` | 包紮 Bandage | 治療 | S | 療2 | 2.0 |  |
| `bdg_chopguard` | 劈擋 Chop and Guard | 攻擊 | S | 攻2 擋2 | 4.0 |  |
| `bdg_essenceguard` | 靈甲 Essence Guard | 防禦 | S | 擋3 靈息+1 | 5.0 ✦|  |

### 職業池(升級批次解鎖,每級 2 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| **L2** `bdg_heavy5` | 重劈 Heavy Chop | 攻擊 | C | 攻6 | 6.0 |  |
| **L2** `sp_focus` | 凝神 Focus | 防禦 | C | 擋4 蓄勢+2 | 6.0 |  |
| **L3** `bdg_chop3guard3` | 劈擋 Chop and Guard | 攻擊 | C | 攻3 擋3 | 6.0 |  |
| **L3** `sp_sweep_cut` | 掃擊 Sweep Cut | 攻擊 | C | 攻4 橫掃 | 6.0 |  |
| **L4** `bdg_infusedsmash` | 灌注猛擊 Infused Smash | 攻擊 | R | 攻11 靈術2 | 7.0 ✦|  |
| **L4** `bdg_spiritshield` | 靈盾 Spirit Shield | 防禦 | R | 擋5 靈息+1 | 7.0 ✦|  |
| **L5** `bdg_heal3` | 療傷 Tend Wounds | 治療 | R | 療5 | 5.0 |  |
| **L5** `bdg_essenceaxe` | 靈斧 Essence Axe | 攻擊 | R | 攻5 靈息+1 | 7.0 ✦|  |
| **L6** `bdg_smash6` | 猛劈 Great Cleave | 攻擊 | R | 攻7 | 7.0 |  |
| **L6** `bdg_rally` | 呼喝 Rally | 防禦 | R | 隊擋2 靈息+1 | 8.0 ✦|  |
| **L7** `bdg_guard4thorn` | 釘盾 Studded Guard | 防禦 | E | 擋6 棘2 | 8.0 |  |
| **L7** `bdg_oakheart` | 橡心 Oakheart | 治療 | E | 療3 再生2 | 7.0 |  |
| **L8** `bdg_warcry` | 戰吼 War Cry | 防禦 | E | 隊擋1 隊攻+2 | 9.0 |  |
| **L8** `bdg_essencebulwark` | 靈甲陣 Essence Phalanx | 防禦 | E | 隊擋3 靈術1 | 7.0 ✦|  |

## 野兔神射手 Hare Marksman

被動 —— 屏息:他所有帶「穿透」的攻擊面 +2

### 長弓骰(起始 6 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `hare_quick2` | 速射 Quick Shot | 攻擊 | S | 攻3 | 3.0 |  |
| `hare_quick3` | 速射 Quick Shot×2 | 攻擊 | S | 攻4 | 4.0 |  |
| `hare_pierce2` | 貫矢 Pierce Arrow | 攻擊 | S | 攻3 穿透 | 5.0 |  |
| `hare_aim4` | 瞄準 Take Aim | 攻擊 | S | 攻5 蓄力+2 | 5.0 |  |
| `hare_guard2` | 格擋 Guard | 防禦 | S | 擋2 | 2.0 |  |

### 箭袋骰(起始 6 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `hareb_pierce1` | 貫矢 Pierce Arrow | 攻擊 | S | 攻2 穿透 | 4.0 |  |
| `hare_quick2` | 速射 Quick Shot | 攻擊 | S | 攻3 | 3.0 |  |
| `hare_essencearrow` | 凝靈箭 Essence Arrow | 攻擊 | S | 攻5 穿透 靈術1 | 5.0 ✦|  |
| `hareb_resupply` | 補矢 Resupply | 資源 | S | 重擲+1 | 4.0 |  |
| `hareb_aim3` | 瞄準 Take Aim | 攻擊 | S | 攻4 蓄力+1 | 4.0 |  |
| `hareb_roll` | 翻滾 Tumble | 防禦 | S | 擋3 | 3.0 |  |

### 職業池(升級批次解鎖,每級 2 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| **L2** `hare_pierce3` | 貫穿 Punch Through | 攻擊 | C | 攻4 穿透 | 6.0 |  |
| **L2** `hare_longshot` | 遠射 Long Shot | 攻擊 | C | 攻6 | 6.0 |  |
| **L3** `hare_attunedaim` | 引靈瞄準 Attuned Aim | 資源 | C | 靈息+2 蓄力+1 | 4.0 ✦|  |
| **L3** `sp_charged_shot` | 蓄勢箭 Charged Shot | 攻擊 | C | 攻5 蓄力+2 | 5.0 |  |
| **L4** `hare_guard3` | 格擋 Guard | 防禦 | R | 擋6 | 6.0 |  |
| **L4** `hare_hawkfeather` | 鷹羽靈箭 Hawk-feather Arrow | 攻擊 | R | 攻5 靈息+1 | 7.0 ✦|  |
| **L5** `hare_volley` | 連珠 Rapid Volley | 攻擊 | R | 攻3×2 | 6.0 |  |
| **L5** `hare_windarrow` | 御風箭 Gale Arrow | 攻擊 | R | 攻9 靈術1 | 7.0 ✦|  |
| **L6** `hare_snipe6` | 狙殺 Snipe | 攻擊 | R | 攻5 先手+4(目標滿血時) | 7.0 |  |
| **L6** `hare_pinning` | 標靈箭 Marking Shot | 攻擊 | R | 攻3 靈息+1 標記 | 8.0 ✦|  |
| **L7** `hare_hawkeye` | 鷹眼 Hawkeye | 特殊 | E | 全隊穿透 | 0.0 | 越帶白名單 |
| **L7** `hare_moonpiercer` | 穿雲月箭 Moon Piercer | 攻擊 | E | 攻7 穿透 | 9.0 |  |
| **L8** `hare_deadly7` | 致命箭 Killing Arrow | 攻擊 | E | 攻6 先手+5(目標滿血時) | 8.5 |  |
| **L8** `hare_galestorm` | 破空靈嵐 Spirit Gale | 攻擊 | E | 攻10 穿透 靈術2 | 8.0 ✦|  |

## 刺蝟盾衛 Hedgehog Bulwark

被動 —— 棘甲:未消耗的格擋保留到下回合(上限 10)

### 圓盾骰(起始 6 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `hedge_guard3` | 格擋 Guard | 防禦 | S | 擋3 | 3.0 |  |
| `hedge_guard4` | 格擋 Guard | 防禦 | S | 擋4 | 4.0 |  |
| `hedge_guardthorn` | 棘擋 Barbed Guard | 防禦 | S | 擋3 棘1 | 4.0 |  |
| `hedge_thorns2` | 豎棘 Raise Quills | 防禦 | S | 棘2 | 2.0 |  |
| `hedge_hammer2` | 錘擊 Mace Blow | 攻擊 | S | 攻3 | 3.0 |  |
| `hedge_hold` | 堅守 Hold Fast | 防禦 | S | 擋2 堅守 | 2.0 |  |

### 短錘骰(起始 6 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `hedge_hammer2` | 錘擊 Mace Blow | 攻擊 | S | 攻3 | 3.0 |  |
| `hedgeb_hammer3` | 錘擊 Mace Blow | 攻擊 | S | 攻4 | 4.0 |  |
| `hedgeb_guard2` | 格擋 Guard | 防禦 | S | 擋2 | 2.0 |  |
| `hedge_thorns2` | 豎棘 Raise Quills | 防禦 | S | 棘2 | 2.0 |  |
| `hedgeb_hammerthorn` | 棘錘 Barbed Mace | 攻擊 | S | 攻3 棘1 | 4.0 |  |
| `hedge_quilldraw` | 棘息 Quill Draw | 防禦 | S | 擋2 棘1 靈息+1 | 5.0 ✦|  |

### 職業池(升級批次解鎖,每級 2 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| **L2** `hedge_guard5` | 格擋 Guard | 防禦 | C | 擋6 | 6.0 |  |
| **L2** `sp_thorn_shield` | 棘盾 Thorn Shield | 防禦 | C | 擋3 棘3 | 6.0 |  |
| **L3** `hedge_thorns3` | 豎棘 Raise Quills | 防禦 | C | 擋2 棘3 | 5.0 |  |
| **L3** `hedge_quillvolley` | 射棘 Quill Volley | 攻擊 | C | 攻3 棘2 | 5.0 |  |
| **L4** `hedge_recoil4` | 反震錘 Recoil Mace | 攻擊 | R | 攻5 呼應(格擋)+2 | 6.0 |  |
| **L4** `sp_protect` | 守護 Protect | 防禦 | R | 擋6 挑釁 | 7.0 |  |
| **L5** `hedge_essencebloom` | 靈棘綻放 Essence Bloom | 防禦 | R | 隊擋2 隊棘2 靈術2 | 8.0 ✦|  |
| **L5** `hedge_quillsurge` | 棘息蜷防 Quilled Respite | 防禦 | R | 擋3 棘1 靈息+1 自淨 | 7.0 ✦|  |
| **L6** `hedge_guard4thorn2` | 棘擋 Barbed Guard | 防禦 | R | 擋5 棘2 | 7.0 |  |
| **L6** `sp_briar_mail` | 荊棘鎧 Briar Mail | 防禦 | R | 擋5 棘3 | 8.0 |  |
| **L7** `hedge_bristle` | 豎刺 Bristle | 防禦 | E | 荊棘翻倍(上限4) | 0.0 | 越帶白名單 |
| **L7** `hedge_ironquills` | 鐵棘靈甲 Iron Quills | 防禦 | E | 擋4 棘2 靈息+1 挑釁 | 9.0 ✦|  |
| **L8** `hedge_shieldbash` | 盾擊 Shield Bash | 攻擊 | E | 傷害=當前格擋(上限6) | 0.0 | 越帶白名單 |
| **L8** `hedge_thornaegis` | 靈棘聖壁 Thorn Aegis | 防禦 | E | 隊擋2 隊棘2 靈術2 | 8.0 ✦|  |

## 梟賢者 Owl Sage

被動 —— 古老守林者:每場戰鬥開始時隊伍獲得 3 點靈息;隊伍靈息在 6 點或以上時,他所有骰面數值 +2

### 法杖骰(起始 6 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `owl_bolt2` | 秘法彈 Arcane Bolt×2 | 攻擊 | S | 攻3 | 3.0 |  |
| `owl_gather2` | 聚靈 Gather Essence | 資源 | S | 靈息+2 | 4.0 ✦|  |
| `owl_gatherbolt` | 引流 Channelled Bolt | 攻擊 | S | 攻2 靈息+1 | 4.0 ✦|  |
| `owl_starfall` | 星隕 Comet Fall | 攻擊 | S | 攻11 靈術3 | 5.0 ✦|  |
| `owl_wardshield` | 靈盾 Essence Shield | 防禦 | S | 擋7 靈術1 | 5.0 ✦|  |

### 圖騰骰(起始 6 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `owlb_gather1` | 聚靈 Gather Essence | 資源 | S | 靈息+1 | 2.0 ✦|  |
| `owl_gather2` | 聚靈 Gather Essence | 資源 | S | 靈息+2 | 4.0 ✦|  |
| `owlb_guard2` | 格擋 Guard | 防禦 | S | 擋2 | 2.0 |  |
| `owlb_moonheal` | 月癒 Moon Mend | 治療 | S | 療8 靈術2 | 4.0 ✦|  |
| `owlb_bolt3` | 秘法彈 Arcane Bolt | 攻擊 | S | 攻4 | 4.0 |  |
| `owlb_wisdom` | 智慧 Wisdom | 資源 | S | 重擲+1 靈息+1 | 6.0 ✦|  |

### 職業池(升級批次解鎖,每級 2 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| **L2** `owl_gather3` | 聚靈 Gather Essence | 資源 | C | 靈息+3 | 6.0 ✦| 越帶白名單 |
| **L2** `owl_moonbeam` | 月光束 Moonbeam | 攻擊 | C | 攻4 靈息+1 | 6.0 ✦|  |
| **L3** `owl_bolt4` | 秘法彈 Arcane Bolt | 攻擊 | C | 攻5 | 5.0 |  |
| **L3** `owl_blessing` | 祝禱 Blessing | 治療 | C | 療3 靈息+1 | 5.0 ✦|  |
| **L4** `owl_meditate` | 冥想 Meditate | 資源 | R | 重擲+2 | 8.0 |  |
| **L4** `sp_regenerate` | 再生術 Regenerate | 治療 | R | 再生3 | 6.0 |  |
| **L5** `owl_greatheal` | 大治癒 Greater Mend | 治療 | R | 療12 靈術3 | 6.0 ✦|  |
| **L5** `sp_mass_mend` | 群體治癒 Mass Mend | 治療 | R | 隊療2 | 6.0 |  |
| **L6** `owl_essenceward` | 靈息護體 Essence Aegis | 防禦 | R | 格擋=靈息×2(上限6) | 0.0 | 越帶白名單 |
| **L6** `sp_freeze` | 冰凍 Freeze | 控制 | R | 弱2 暈1 靈術1 | 6.0 ✦|  |
| **L7** `owl_starshower` | 星落 Starfall | 攻擊 | E | 攻8 全體 靈術4 | 8.0 ✦|  |
| **L7** `sp_echo_crystal` | 迴響水晶 Reverb Crystal | 治療 | E | 療6 迴響2 靈術1 | 6.0 ✦|  |
| **L8** `owl_meteor` | 隕星雨 Meteor Shower | 攻擊 | E | 攻6×3 靈術5 | 8.0 ✦|  |
| **L8** `sp_time_stop` | 時停 Time Stop | 控制 | E | 暈2 | 8.0 |  |

## 狐影雙刃 Fox Duelist

被動 —— 一唱一和:他的「呼應」條件成立時,加成額外再 +1

### 左刃骰(起始 6 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `fox_stab2` | 刺擊 Jab | 攻擊 | S | 攻3 | 3.0 |  |
| `fox_stab3` | 刺擊 Jab | 攻擊 | S | 攻4 | 4.0 |  |
| `fox_stab1x2` | 連刺 Double Jab | 攻擊 | S | 攻1×2 | 2.0 |  |
| `fox_echo3` | 呼應刺 Echo Jab | 攻擊 | S | 攻4 呼應(攻擊)+2 | 5.0 |  |
| `fox_guard2` | 格擋 Guard | 防禦 | S | 擋2 | 2.0 |  |
| `fox_shift` | 換位 Switch | 防禦 | S | 擋2 呼應(攻擊)+2 | 3.0 |  |

### 右刃骰(起始 6 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `fox_stab2` | 刺擊 Jab | 攻擊 | S | 攻3 | 3.0 |  |
| `fox_stab1x2` | 連刺 Double Jab | 攻擊 | S | 攻1×2 | 2.0 |  |
| `foxb_echo2` | 呼應刺 Echo Jab | 攻擊 | S | 攻3 呼應(攻擊)+2 | 4.0 |  |
| `fox_stab3` | 刺擊 Jab | 攻擊 | S | 攻4 | 4.0 |  |
| `fox_siphonstep` | 攝靈 Siphon Step | 攻擊 | S | 攻3 靈息+1 | 5.0 ✦|  |
| `foxb_dash` | 疾走 Dash | 攻擊 | S | 攻2 重擲+1 | 6.0 |  |

### 職業池(升級批次解鎖,每級 2 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| **L2** `fox_stab2x2` | 連刺 Double Jab | 攻擊 | C | 攻2×2 連擊 | 6.0 |  |
| **L2** `sp_echo_cut` | 呼應斬 Echo Cut | 攻擊 | C | 攻4 呼應(攻擊)+2 | 5.0 |  |
| **L3** `fox_guard3` | 迴身格擋 Turning Guard | 防禦 | C | 擋4 呼應(攻擊)+2 | 5.0 |  |
| **L3** `sp_trickery` | 詭計 Trickery | 控制 | C | 暈1 | 4.0 |  |
| **L4** `fox_echo4` | 呼應刺 Echo Jab | 攻擊 | R | 攻5 呼應(攻擊)+3 | 6.5 |  |
| **L4** `fox_essencefeint` | 攝靈連步 Essence Feint | 攻擊 | R | 攻3 靈息+1 連擊 | 7.0 ✦|  |
| **L5** `fox_essencewaltz` | 靈息雙舞 Essence Waltz | 攻擊 | R | 攻8 連擊 靈術2 | 6.0 ✦|  |
| **L5** `sp_chain_strike` | 連環擊 Chain Strike | 攻擊 | R | 攻5 連擊 | 7.0 |  |
| **L6** `fox_shadow3` | 影襲 Shadow Strike | 攻擊 | R | 攻4 穿透 | 6.0 |  |
| **L6** `fox_crossparry` | 攝靈迴防 Spirit Parry | 防禦 | R | 擋4 靈息+1 呼應(攻擊)+2 | 7.0 ✦|  |
| **L7** `fox_twindance` | 雙舞 Twin Dance | 特殊 | E | 雙舞 | 0.0 | 越帶白名單 |
| **L7** `sp_die_theft` | 奪骰 Die Theft | 特殊 | E | 奪骰 | 0.0 | 越帶白名單 |
| **L8** `fox_phantom` | 絕影 Phantom Flurry | 攻擊 | E | 攻1×4 需呼應(攻擊) | 4.0 | 越帶白名單 |
| **L8** `fox_spiritwaltz` | 靈魂圓舞 Spirit Waltz | 攻擊 | E | 攻3 靈息+2 連擊 | 9.0 ✦|  |

## 蠻豬破軍 Boar Berserker

被動 —— 背水之勢:HP 在 50% 或以下時,所有攻擊面 +2

### 石鎚骰(起始 6 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `boar_smash4` | 猛擊 Smash×2 | 攻擊 | S | 攻4 自損1 | 3.0 |  |
| `boar_crush6` | 碎擊 Crusher | 攻擊 | S | 攻6 自損2 | 4.0 |  |
| `boar_wild3` | 蠻擊 Wild Swing | 攻擊 | S | 攻3 | 3.0 |  |
| `boar_guard2` | 格擋 Guard | 防禦 | S | 擋2 | 2.0 |  |
| `boar_bloodtithe` | 以血引靈 Blood Tithe | 資源 | S | 靈息+3 自損2 | 4.0 ✦|  |

### 蠻勇骰(起始 6 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `boar_wild3` | 蠻擊 Wild Swing | 攻擊 | S | 攻3 | 3.0 |  |
| `boarb_smash5` | 猛擊 Smash | 攻擊 | S | 攻5 自損2 | 3.0 |  |
| `boarb_guard3` | 格擋 Guard | 防禦 | S | 擋3 | 3.0 |  |
| `boarb_bloodhit3` | 嗜血擊 Bloodthirst | 攻擊 | S | 攻3 命中回1 | 4.0 |  |
| `boarb_wild2` | 蠻擊 Wild Swing | 攻擊 | S | 攻2 | 2.0 |  |
| `boarb_allin` | 孤注 All In | 特殊 | S | 下骰+2 自損2 | 2.0 |  |

### 職業池(升級批次解鎖,每級 2 面)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| **L2** `boar_smash6` | 猛擊 Smash | 攻擊 | C | 攻7 自損1 | 6.0 |  |
| **L2** `sp_reckless` | 豁命揮擊 Reckless Swing | 攻擊 | C | 攻9 自損3 | 6.0 |  |
| **L3** `boar_ironhide` | 鐵皮 Iron Hide | 防禦 | C | 擋5 棘1 | 6.0 |  |
| **L3** `sp_leech_bite` | 吸血咬 Leech Bite | 攻擊 | C | 攻4 吸血 | 6.0 |  |
| **L4** `boar_bloodhit5` | 嗜血擊 Bloodthirst | 攻擊 | R | 攻5 命中回2 | 7.0 |  |
| **L4** `boar_painbrew` | 熬血引靈 Blood Brew | 資源 | R | 靈息+4 自損2 | 6.0 ✦|  |
| **L5** `boar_bloodsurge` | 血靈爆 Blood Surge | 攻擊 | R | 攻13 自損2 靈術2 | 7.0 ✦|  |
| **L5** `sp_great_blade` | 巨刃 Great Blade | 攻擊 | R | 攻10 自損2 | 8.0 |  |
| **L6** `boar_lastditch` | 背水 Last Ditch | 攻擊 | R | 攻5 半血以下攻9 | 5.0 | 越帶白名單 |
| **L6** `sp_gambit` | 賭命 Gambit | 攻擊 | R | 攻1-12 | 6.5 |  |
| **L7** `boar_avalanche8` | 崩山 Avalanche | 攻擊 | E | 攻11 自損3 | 8.0 |  |
| **L7** `boar_frenzy` | 狂亂血祭 Blood Frenzy | 攻擊 | E | 攻4×2 靈息+1 自損2 | 8.0 ✦|  |
| **L8** `boar_finale10` | 終焉 Finale | 攻擊 | E | 攻12 自損4 | 8.0 |  |
| **L8** `boar_worldbreaker` | 碎世血嵐 Worldbreaker | 攻擊 | E | 攻16 自損3 靈術3 | 7.0 ✦|  |

## 通用池(任何角色可得,offer/商店 30% 權重)

| id | 名稱 | 類別 | 稀有 | 效果 | eff | 備註 |
|---|---|---|---|---|---|---|
| `sp_torch` | 火把 Torch | 攻擊 | C | 攻4 燒2 | 7.0 |  |
| `sp_venom_knife` | 毒匕 Venom Knife | 攻擊 | C | 攻3 毒2 | 6.0 |  |
| `sp_shield_wall` | 盾牆 Shield Wall | 防禦 | C | 擋7 | 7.0 |  |
| `sp_first_aid` | 急救 First Aid | 治療 | C | 療4 淨化 | 5.0 |  |
| `sp_channel` | 汲靈 Draw Essence | 資源 | C | 靈息+2 | 4.0 ✦|  |
| `sp_insight` | 洞察 Insight | 資源 | C | 重擲+1 | 4.0 |  |
| `sp_lance` | 長矛突刺 Lance Thrust | 攻擊 | R | 攻6 穿透 | 8.0 |  |
| `sp_great_wall` | 巨壁 Great Wall | 防禦 | R | 擋8 | 8.0 |  |
| `sp_greater_cure` | 厚生術 Restoration | 治療 | R | 療6 | 6.0 |  |
| `sp_deep_channel` | 深汲 Deep Draw | 資源 | R | 靈息+4 | 8.0 ✦|  |
| `sp_annihilate` | 殲滅 Annihilate | 攻擊 | E | 攻12 自損4 | 8.0 |  |
| `sp_miracle` | 奇蹟 Miracle | 治療 | E | 療4 再生1 淨化 | 7.0 |  |

## 越帶白名單(9 面,linter 讀)

鷹眼/豎刺/盾擊/聚靈/靈息護體/雙舞/絕影/背水/奪骰 —— 理由逐條喺 `tests/value_band_test.gd` WHITELIST。
