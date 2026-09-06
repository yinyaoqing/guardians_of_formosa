# M1-B3b：環形建塔選單與塔種 — 設計規格

- 日期：2026-09-06
- 狀態：定案
- 上游規格：`2026-09-04-tower-defense-architecture-design.md` §6、`2026-09-04-chapter-01-zeelandia-design.md` §4.0、`2026-09-05-m1b3a-hud-i18n-design.md`

---

## 1. 範圍

B3a 讓畫面上有了看得懂的文字。B3b 讓玩家用 UI 建塔，而不是靠快捷鍵。

### 1.1 一項更正

先前多次記述「補足三種塔是純 JSON」。**那是錯的。** 第一章設計規格 §4.0 早已定義三種塔，其中兩種需要新的戰鬥機制：

| 塔 | 定位 | 純資料？ |
|---|---|---|
| **銃樓**（火繩槍手 → 排槍齊射 → 稜堡砲位） | 單體高傷、低射速 | ✅ 三階都是射擊塔，最高階加範圍傷害 |
| **獵寮**（鏢手 → 鹿陷阱 → 火燒獵場） | 低傷、短射程、施加減速 | 一階可以；**二階是路徑陷阱、三階是地面 DoT，都不是射擊塔** |
| **柵欄**（竹柵 → 刀盾壯丁 → 藤牌隊） | 出兵擋路 | ❌ 需要駐守單位系統 |

當時只看到 `chill` 與 `splash_radius` 已存在就下了結論，沒有讀第一章的塔種設計。

架構上有一半是備好的：`Enemy.blocked_by` 已存在，`MovementSystem` 已經會在它非零時停止推進。缺的是生成士兵、士兵選目標、近戰結算、陣亡與再生。

### 1.2 B3b 做什麼

- 環形建塔選單（空位顯示可建的塔與造價；有塔顯示升級與賣出）
- 射程圈
- 塔資料 schema 改為**每階一張圖**，`TowerView` 在升級時換圖
- **銃樓三階完整、獵寮一階**，取代 M0 的佔位 `archer_tower`
- 用 `prop_buildsite.png` 取代建塔點的置換標記

### 1.3 不在 B3b 範圍

長按查看詳細數值、`MouseKeyboardInput.translate()` 的簽名改動、駐守單位系統、路徑陷阱、地面 DoT、柵欄、獵寮二三階、敵人美術替換、勝敗結算、波次系統。

---

## 2. 選單住在 `ui/`，用螢幕座標

`ui/build_menu.gd` 是 `Control`。`.tscn` 只有一個根節點——**選項按鈕由程式從資料生成，排在圓周上**。

選這條路而非世界座標的 `Node2D`，理由有三：

1. **重用既有的動作文法。** 按鈕發 signal，`battle_scene` 翻成 `InputAction.choose_tower(n)` / `SELL` / `UPGRADE`——跟鍵盤產生的是同一批動作，B2 已有端到端測試守著那條路。新增的文法是零。
2. **不動控制器的狀態機。** B2 刻意把選取壓成單一個 `selected_slot_id`。世界座標的做法要在控制器裡加入「選單開著」的狀態與扇形命中判定。
3. **Godot 的 `Control` 已經處理命中判定、觸控目標尺寸、hover，以及 M4 需要的焦點導航。** 世界座標等於把這些重做一遍。

代價是幾何（圓周半徑、按鈕位置）沒有自動化測試。那本來就是人工驗收的守備範圍，而 §4 把可測試的部分搬了出來。

**按鈕以程式生成而非手寫進 `.tscn`**，一來環形排列用程式算比用錨點自然，二來數量自然跟著 `available_towers` 走，三來避開 B3a 咬過我們的盲寫風險。

### 2.1 選單是選取狀態的純函數

選單不持有自己的開關狀態。它是 `InteractionController.selected_slot_id` 的函數：

- `selected_slot_id == 0` → 不顯示
- 指向空位 → 顯示可建的塔
- 指向有塔的建塔點 → 顯示升級與賣出

**點空白處關閉選單因此是免費的**——`select_at` 命中不到任何建塔點時本來就會把選取清成 0。不需要全螢幕的點擊攔截層，也不需要新的取消路徑。

### 2.2 選單開在建塔點下方的半圓弧，不是整圈

選項沿**下半圓**分布，以正下方為中心左右展開，半徑 100、按鈕 110×110（沿用 B3a 訂的 ≥44pt 觸控目標換算）。

不做整圈的理由是具體的：最上排的建塔點在 y=200，整圈半徑 100 會把最上面那一瓣推到 y≈45，而 HUD 橫幅佔了畫面上緣約 120。下半圓從結構上就避開了這個衝突，也不會蓋住建塔點本身或蓋好的塔。

最下排建塔點在 y=480，加上 100 + 55 仍在 1080 之內，另一端也不會出界。

### 2.3 `ui/` 的方向規則不變

B3a 訂下的規則照舊：`ui/` 可以讀 `WorldState` 與 `BattleSim` 來顯示，要讓事情發生只能發 signal。`tests/test_ui_layer.gd` 的原始碼掃描守衛涵蓋新檔案。

---

## 3. 把決策搬到測得到的地方

B3a 的教訓是畫面那層抓不到錯。B3b 的選單裡有一批**真正的決策**——買不買得起、有沒有下一級、退款多少——如果它們寫在 `Control` 裡，就沒有任何測試守得到。

因此抽成一個純函式：

```
BuildMenuOptions.for_slot(world: WorldState, slot_id: int) -> Array[Dictionary]
```

回傳要顯示的選項，`Control` 只負責畫。

| 情境 | 回傳 |
|---|---|
| `slot_id == 0` 或找不到 | 空陣列 |
| 空位 | 每種 `available_towers` 一筆 `{kind: "build", tower_id, icon, cost, affordable}` |
| 有塔且還有下一級 | 一筆 `{kind: "upgrade", cost, affordable}` |
| 有塔 | 一筆 `{kind: "sell", refund}` |

`affordable` 只影響顯示（買不起變暗但仍然列出，玩家才知道有這個選項）。**它不阻擋 intent**——沿用 B2 的分工：金錢的權威在 `BuildSystem`，控制器與 UI 都不做第二次判斷。買不起時 intent 照發，由 `core/` 靜默拒絕。

### 3.1 退款金額：一段刻意接受的重複

`refund` 必須與賣出時實際退的金額一致。理想上兩處共用同一段邏輯，但**不能**：B3a 的 `ui/` 分層守衛禁止 `ui/` 底下出現字串 `BuildSystem`，而那條守衛正是攔住 UI 繞過 signal 直接動核心系統的東西。為了省四行而放寬它，換到的遠不如失去的。

所幸不需要放寬。退款是「已投入金額 × 退款比例」，而已投入金額是 `world.tower_defs[tower_id]["levels"][0..level-1]` 的造價總和——**`BuildMenuOptions` 從 `WorldState` 就算得出來，完全不必認識 `BuildSystem`。**

代價是那個四行的加總在兩個地方各有一份。這是刻意接受的，條件是 §8.1 那條一致性測試：它同時看選單顯示的金額與實際賣出後金幣的增量，兩者漂移就會紅。**沒有那條測試的話這個決定不成立。**

`BuildMenuOptions` 放在 `ui/`，`extends RefCounted`，全靜態函式——與 `input/` 的翻譯器同一個模式，因此可 headless 測試。

---

## 4. 射程圈住在世界座標

射程是世界單位的半徑畫在世界座標上，所以它是 `game/views/range_circle.gd`（`Node2D`），不是 `Control`。

顯示時機：

| 狀態 | 圓心 | 半徑 |
|---|---|---|
| 選中有塔的建塔點 | 塔的位置 | 該塔當前等級的 `attack_range` |
| 滑鼠停在某個「建造」選項上 | 該建塔點 | 那種塔**一級**的 `attack_range` |
| 滑鼠停在「升級」選項上 | 塔的位置 | **下一級**的 `attack_range` |
| 未選取 | — | 不顯示 |

最後兩列讓「這次升級換到多少射程」看得見，而成本幾乎為零。

選單發 `option_hovered(index)` 與 `option_unhovered`，由 `battle_scene` 決定畫在哪、畫多大——`ui/` 不碰世界座標。

**觸控沒有 hover。** 依已定案的觸控模型，點下去就建、不預覽；射程圈預覽是滑鼠獨有的額外好處。觸控玩家蓋了才看得到射程，賣掉退 75%。

---

## 5. 塔的資料 schema：每階一張圖

三階在美術上是完全不同的東西——火繩槍手、三人排槍、稜堡砲位。但目前 `data/towers/*.json` 只有一個頂層 `sprite`，`TowerView.setup()` 也只在建造時 `load()` 一次。

### 5.1 改動

```json
{
  "id": "musket_tower",
  "name_key": "tower.musket_tower.name",
  "damage_type": "physical",
  "icon": "res://game/assets/chapter01/icon_tower_musket.png",
  "levels": [
    { "cost": 70, "...": "...", "sprite": "res://game/assets/chapter01/tower_musket_t1.png" }
  ]
}
```

頂層 `sprite` 移除，`icon` 新增（選單用）。

連帶要改的消費端：

- `battle_scene.gd` 建立 `TowerView` 時改讀當前等級的 `sprite`
- `TowerView` 需要能換圖，`battle_scene` 需要偵測等級變化才知道要換——與 B3a 的 HUD 一樣，快取上次顯示的值
- `tests/test_data_integrity.gd` 的 `test_every_referenced_sprite_path_exists` 目前讀頂層 `sprite`，要改成走訪每一階並額外檢查 `icon`

### 5.2 塔的數值

**數值是暫定的，來自定位描述而非平衡測試。** M1 的驗收標準是玩法手感，數值要在實際遊玩後調整，不要當成已定案的設計。

`orc_grunt` 的 hp 120、armor 0.2、speed 45，作為對照。

**銃樓 `musket_tower`**（physical）——單體高傷、低射速，有明顯裝填節奏：

| 級 | 造價 | 傷害 | 射程 | 射擊間隔 | 投射物速度 | 範圍半徑 |
|---|---|---|---|---|---|---|
| 一：火繩槍手 | 70 | 18 | 200 | 1.2 | 700 | 0 |
| 二：排槍齊射 | 130 | 30 | 210 | 1.1 | 700 | 0 |
| 三：稜堡砲位 | 230 | 52 | 230 | 1.5 | 480 | 70 |

三級刻意把間隔拉長而換到範圍傷害——那是砲不是槍。

**獵寮 `hunter_tower`**（physical）——低傷、短射程、施加減速：

| 級 | 造價 | 傷害 | 射程 | 射擊間隔 | 投射物速度 | 命中效果 |
|---|---|---|---|---|---|---|
| 一：鏢手 | 50 | 7 | 130 | 0.9 | 620 | `chill` |

第一章規格說獵寮這條線「施加減速與流血」。**一級只給 `chill`（減速）**，流血屬於未實作的二三階。驗收時只有一種效果在跑，出問題比較容易歸因。

起始金幣 200：可以蓋銃樓 70 + 獵寮 50 = 120，或兩座銃樓 140。**兩種買得起與買不起的狀態在第一關就都能驗到。**

### 5.3 `archer_tower` 刪除

它是 M0 的佔位。`data/levels/level_01/meta.json` 的 `available_towers` 改為 `["musket_tower", "hunter_tower"]`，i18n 的 `tower.archer_tower.name` 一併移除——B3a 的 i18n 完整性測試會抓到沒清乾淨的殘留。

`game/assets/placeholder_tower.png` 因此不再被引用，一併刪除。

---

## 6. 建塔點標記

`BuildSlotView` 改用 `prop_buildsite.png`。

兩項行為改動：

- **有塔時隱藏標記。** 塔會蓋在同一個位置上，標記留著只會從塔底下露出來。
- 選取提示改為輕微的亮度調整。真美術染成黃色會變濁；選中的主要回饋其實是選單打開與射程圈出現。

`game/assets/placeholder_slot.png` 不再被引用，一併刪除。

---

## 7. 文字

新增：

| key | zh-TW | en |
|---|---|---|
| `tower.musket_tower.name` | `銃樓` | `Musket Tower` |
| `tower.hunter_tower.name` | `獵寮` | `Hunter's Lodge` |
| `menu.upgrade_format` | `升級 %d` | `Upgrade %d` |
| `menu.sell_format` | `賣出 +%d` | `Sell +%d` |

移除：`tower.archer_tower.name`。

塔名在滑鼠停在建造選項上時顯示，走 `data/` 的 `name_key`。

### 7.1 造價數字不進翻譯檔

建造選項上的造價就是一個數字，直接 `str(cost)`。

理由有兩層。表層是它沒有可翻譯的內容。更實際的一層是：若硬做成 `menu.cost_format` 且兩個語系都填 `%d`，會**觸發 B3a 加入的 `test_the_two_locales_actually_differ`**——那條測試要求每個 key 的兩個語系不同，以攔截「把中文複製到英文欄」的錯誤。

升級與賣出仍走格式字串，因為它們有可翻譯的詞。

---

## 8. 測試策略

### 8.1 自動化

| 測試 | 抓什麼 |
|---|---|
| `BuildMenuOptions` 的選項決策 | 空位列出所有可建的塔；有塔列出升級與賣出；**沒有下一級時不列升級**；買不起仍然列出但 `affordable` 為 false；未選取回傳空陣列 |
| 退款金額與 `BuildSystem` 一致 | 兩處若各算一次就會漂移。測試直接比對選項給的 `refund` 與實際賣出後金幣的增量 |
| 資料完整性（既有測試擴充） | 每一階都有 `sprite` 且檔案存在；每種塔都有 `icon` 且檔案存在 |
| `ui/` 分層守衛（既有測試） | 新檔案不得繞過 signal 邊界 |
| i18n 完整性（既有測試） | 新的塔名 key 兩個語系都在；`archer_tower` 的殘留會被抓到 |

**退款一致性那條是這一輪價值最高的測試。** 選單顯示「賣出 +52」而實際只回 45，是玩家會發現但測試不會的那種錯——除非有一條測試同時看兩邊。

### 8.2 人工驗收

UI 與畫面不做自動化（`CLAUDE.md`）。跑 `godot --path .`：

1. 建塔點顯示為 `prop_buildsite` 的真美術，不是白方塊
2. 點建塔點 → 環形選單在該點附近展開，兩瓣：銃樓 70、獵寮 50
3. 金幣不足時該瓣變暗，但仍然列出
4. 滑鼠停在某一瓣 → 畫出該塔一級的射程圈，並顯示塔名
5. 點一瓣 → 蓋出塔，**建塔點標記消失**，金幣減少
6. 點已有塔的建塔點 → 選單顯示升級與賣出，並畫出現有射程圈
7. 滑鼠停在升級瓣 → 射程圈變成下一級的大小
8. 升級 → **塔的外觀換成下一階的圖**（槍手 → 排槍 → 稜堡）
9. 銃樓升到三級後 → 選單不再顯示升級瓣
10. 獵寮蓋好後 → 選單只有賣出，沒有升級瓣
11. 賣出 → 塔消失、標記重新出現、金幣回一部分
12. 點空白處 → 選單關閉、射程圈消失
13. 快捷鍵 `1` `2` `U` `S` 仍然可用，與選單並存

第 9 與第 10 項是「沒有下一級就不顯示升級」在畫面上的兩種路徑，**兩種都要驗**——一種是升滿，一種是這種塔本來就只有一階。

---

## 9. 檔案結構

```
ui/build_menu.tscn                     新增：只有根節點，按鈕由程式生成
ui/build_menu.gd                       新增：渲染與 signal
ui/build_menu_options.gd               新增：選項決策，純靜態函式
game/views/range_circle.gd             新增
game/views/tower_view.gd               修改：能換圖
game/views/build_slot_view.gd          修改：改用真美術、有塔時隱藏
game/level/battle_scene.gd             修改：掛載選單、接 signal、等級變化換圖、射程圈
data/towers/musket_tower.json          新增
data/towers/hunter_tower.json          新增
data/towers/archer_tower.json          刪除
data/levels/level_01/meta.json         修改：available_towers
i18n/strings.csv                       修改：新增四個 key、移除一個
game/assets/placeholder_tower.png      刪除
game/assets/placeholder_slot.png       刪除
tests/test_data_integrity.gd           修改：每階 sprite 與 icon
tests/ui/test_build_menu_options.gd    新增
```

`core/` 一律不動。B3b 沒有任何 `core/` 的改動——與 B3a 相同，這是表現層里程碑的證據。

---

## 10. 待後續決策事項

- 駐守單位系統（柵欄出兵擋路）、路徑陷阱（獵寮二階）、地面 DoT（獵寮三階）——三者合起來是一個獨立子里程碑
- 長按查看詳細數值，以及它需要的 `translate()` 簽名改動（目前只看 `is_action_pressed`，完全丟棄放開事件）
- 敵人美術替換（六種敵人的圖已存在於 `game/assets/chapter01/`）
- 勝敗結算與波次系統；敵人生成移入 tick
- 潮汐機制（第一章 §4.2 的核心，HUD 已有 `icon_tide` 圖示）
- 平民撤離（HUD 已有 `icon_civilian` 圖示），可能與 `lives` 的語意重疊，需釐清
- 貨幣是「銀」而非泛稱金幣（`icon_silver`），HUD 文案與 `hud.gold_format` 之後要對齊
- 第四種塔「稜堡砲位」與其最小射程機制（M3）
- 字型子集化、觸控目標實體尺寸驗證（M2）
- 選單幾何在不同長寬比下的表現（M2 實機）
