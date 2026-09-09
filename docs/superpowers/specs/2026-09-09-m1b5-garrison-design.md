# M1-B5 地面單位系統設計：柵欄三級與 `blocked_by` 近戰

- 日期：2026-09-09
- 前置：M1-B4（波次與勝敗結算，`main` = `2c95245`）
- 上位規格：`2026-09-04-tower-defense-architecture-design.md` §4.1、`2026-09-04-chapter-01-zeelandia-design.md` §4.0

---

## 1. 這個里程碑要解決什麼

架構規格 §4.1 只留了一句話：

> **攔截機制**（士兵擋路）不是動態尋路，而是敵人身上的 `blocked_by` 欄位：被攔截時停止推進 `distance_along` 並進入近戰狀態。

`Enemy.blocked_by` 這個欄位從 M0 就存在，`MovementSystem.tick` 也早就有 `if enemy.blocked_by != 0: continue`——但**至今沒有任何一行程式碼寫過那個欄位**。整條分支是死的。本里程碑把它接上。

選在此時做，不是因為柵欄最重要，而是因為它是 M1 剩餘內容的共用地基：

| 之後要做的東西 | 依賴這裡的什麼 |
|---|---|
| 弓箭手（§4.1「優先攻擊玩家的 blocker」） | 場上要先有 blocker 這種東西 |
| 英雄 | 會走、會打、會死、會重生的友方單位 |
| 掘壕隊（目標是塔而非終點） | 敵人對友方實體造成傷害的通道 |

若先做英雄，英雄裡會長出一份專用近戰程式碼，柵欄之後再抄第二份。

### 1.1 範圍

**做**：`Combatant` 基底類別、`Soldier` 實體、兵營維護系統、近戰系統、柵欄三級資料、小兵表現層（含血條）、既有敵人的近戰數值。

**不做**（各有去處）：

- 弓箭手、鐵人、藤牌兵、掘壕隊 → B6
- 獵寮 t2/t3（路徑陷阱、地面 DoT）→ B6
- 集結點與拖曳手勢 → 與英雄一起做
- 敵人血條 → 未排程
- 潮汐第二條路徑對崗位的影響 → B9（見 §5.3）

---

## 2. 玩法規則

以下五條在腦力激盪中逐條確認，是本規格的前提，不是待議事項。

| # | 規則 | 理由 |
|---|---|---|
| 1 | 柵欄是**兵營**：持續維持 N 個小兵，不是靜態障礙 | 章節規格 §4.0 定位欄寫「出兵擋路」；也才能與英雄共用地基 |
| 2 | **無集結點**：小兵自動站在離該建塔點最近的路徑位置 | 集結點要發明新的拖曳手勢，同時動 `input/`、`ui/`、`core/`。留到英雄一起做 |
| 3 | **1:1 攔截**：一個小兵綁一個敵人，多出來的敵人直接走過去 | 讓小兵數量成為真實數值、升級有意義，並自然產生「擋不住了」的張力 |
| 4 | **計時重生 + 脫戰回血** | 玩家不必一直盯著它；波次間隔成為恢復期，這讓「提前呼叫下一波換獎勵」真的有代價 |
| 5 | 升級 → 小兵**重置為新等級的滿血狀態**，重生倒數清零 | 等於一次治療，但要花錢，是 Kingdom Rush 的行為。已確認接受此副作用 |

---

## 3. 架構

### 3.1 `Combatant` 基底類別（唯一真正的架構決定）

硬規則 #2：「傷害一律經過 `DamageSystem.apply()`」。而現在的簽名是：

```gdscript
static func apply(enemy: Enemy, amount: float, damage_type: StringName) -> float
```

型別綁死 `Enemy`。「敵人砍小兵」必須進得了同一個門。

**採用方案**：新增 `core/entities/combatant.gd`，把五個欄位上移，兩種實體繼承它，`apply()` 的參數型別改為 `Combatant`。

```gdscript
class_name Combatant
extends RefCounted

## 會被傷害結算打到的東西。Enemy 與 Soldier 的共同基底。
##
## 存在的唯一理由是讓 DamageSystem.apply() 維持「一個入口 + 靜態型別」。
## 若改成兩個函式（apply / apply_to_soldier），減免邏輯就有兩份，
## 而兩份數值規則漂移的那天不會有任何測試失敗——這正是硬規則 #2 要防的事。

var hp: float = 0.0
var max_hp: float = 0.0
var alive: bool = true

var armor: float = 0.0          ## 物理減免比例
var magic_resist: float = 0.0   ## 魔法減免比例
```

`Enemy` 保留 `base_armor` / `base_magic_resist`（狀態效果的計算基準，`StatusSystem` 每 tick 由 base 重算寫回 `armor`）——那是 Enemy 專屬機制，不上移。`Soldier` 不吃狀態效果，`armor` / `magic_resist` 建塔時寫一次。

被否決的兩個方案，理由記錄在此以免日後重新提出：

- **加第二個函式 `apply_to_soldier()`**：不動 `Enemy`，但硬規則講的「唯一入口」就變成兩個。
- **拿掉型別註記走鴨子型別**：行數最少，但 `DamageSystem` 從此不知道自己在打什麼，GDScript 也不再檢查。

`Combatant` 不含 Node、不含引擎場景類別，`tests/test_core_purity.gd` 的既有掃描自動涵蓋。

### 3.2 `Soldier`

```gdscript
class_name Soldier
extends Combatant

var id: int = 0
var barracks_id: int = 0          ## 產出它的兵營（Tower）id
var slot_index: int = 0           ## 在兵營的第幾個名額，重生時要放回同一格

var path_id: StringName = &""     ## 崗位所在的路徑
var post_distance: float = 0.0    ## 崗位在該路徑上的位置
var position: Vector2 = Vector2.ZERO   ## 崗位的世界座標，建立時算一次

var damage: float = 0.0
var damage_type: StringName = &"physical"
var attack_interval: float = 1.0
var cooldown: float = 0.0

var engaged_enemy_id: int = 0     ## 0 表示未交戰
var regen_per_second: float = 0.0
```

`position` 存下來是因為表現層每 tick 要用，而它是常數——每次由 `PathData.position_at()` 重算是白花的。

### 3.3 `Tower` 的變更

```gdscript
var kind: StringName = &"shooter"          ## shooter | barracks
var soldier_ids: PackedInt32Array = PackedInt32Array()      ## 0 表示該名額空著
var respawn_timers: PackedFloat32Array = PackedFloat32Array()  ## 對應名額的重生剩餘秒數
```

三點說明：

1. **`kind` 是顯式欄位，不是「兵營把 damage 填 0」。** 後者要靠讀者推理，且 damage 為 0 的射擊塔是合法的資料錯誤，兩者就分不出來。
2. **兩個陣列長度固定為該級的兵數**，建塔／升級時重設一次。用 `Packed*Array` 而非 `Array` 是為了硬規則 #5「戰鬥迴圈中禁止配置新物件」——每 tick 只寫既有元素。
3. `_tick_towers` 依 `kind` 分派，未知 kind `push_error` + `assert(false)`。沿用 `_apply_pending_intents` 與 `ProjectileSystem._hit_one` 的既有慣例：資料錯誤要吵，不要安靜。

### 3.4 `Enemy` 的變更

```gdscript
var melee_damage: float = 0.0
var melee_interval: float = 1.0
var melee_cooldown: float = 0.0
```

`blocked_by` 已存在，語意不變（0 = 未被攔截，否則為攔截它的 `Soldier.id`）。id 空間共用 `WorldState.next_id()`，所以 `blocked_by` 不會與敵人 id 混淆。

### 3.5 `WorldState` 的變更

```gdscript
var soldiers: Array[Soldier] = []
var soldiers_by_id: Dictionary = {}      ## int -> Soldier

const SOLDIER_POOL_CAPACITY := 32
var soldier_pool := ObjectPool.new(func() -> Soldier: return Soldier.new(), SOLDIER_POOL_CAPACITY)
```

容量 32：M1 的關卡建塔點是個位數，全部蓋滿兵營也只有十餘個小兵，32 留了倍數餘裕。

### 3.6 兩個新系統

| 檔案 | 職責 |
|---|---|
| `core/systems/garrison_system.gd` | 兵營名額的維護：補兵、重生倒數、脫戰回血、賣塔與升級時的清理 |
| `core/systems/melee_system.gd` | 交戰的建立與解除、雙方互砍 |

**為什麼拆成兩個**：一個管「有幾個兵、血剩多少」，一個管「誰在打誰」。合成一個檔案時，「重生的兵要不要立刻接戰」會變成同一段程式碼裡的旗標，兩組規則互相絆倒。分開之後，重生系統不認得敵人，近戰系統不認得兵營。

---

## 4. tick 順序

```
_apply_pending_intents
WaveSystem.tick
status_system.tick
GarrisonSystem.tick     ← 新
MeleeSystem.tick        ← 新
MovementSystem.tick
_collect_leaked
_rebuild_grid
projectile_system.tick
_tick_towers
_remove_dead
_check_battle_finished
```

兩個位置有理由，不可任意調換：

- **`MeleeSystem` 在 `MovementSystem` 之前。** 否則剛被擋下的敵人會在本 tick 多走一步。在 4 倍速下這個誤差每 tick 都發生，玩家看得到敵人「陷進」小兵裡。
- **`GarrisonSystem` 在 `MeleeSystem` 之前。** 重生出來的小兵應該在同一 tick 就能接戰，而不是等下一 tick。

`_remove_dead` 要同時處理小兵，並且**清掉對應敵人的 `blocked_by`**。漏掉這一步，被攔截的敵人會永遠停在原地不動——這是本里程碑最容易生出來的 bug，而畫面上它看起來像是「敵人卡住了」而非「傷害系統壞了」，很難追。因此它有專屬測試（§8 T4）。

---

## 5. 攔截判定

### 5.1 崗位的決定

建塔（或升級成兵營）當下算一次，之後不再變動：

```
掃過 world.paths 每一條路徑的每一個取樣點，
取離該建塔點歐氏距離最近者 → (path_id, post_distance)
```

路徑取樣間距是 8 px（`battle_scene.gd` 的 `PATH_SAMPLE_SPACING`），level 1-1 的路徑長度是數千 px，所以是幾百次比較、只在建塔時做一次。不需要空間索引。

### 5.2 交戰條件

`MeleeSystem` 每 tick 對每個「未交戰且存活」的小兵，找一個符合下列**全部**條件的敵人：

1. `enemy.path_id == soldier.path_id`
2. `enemy.alive and not enemy.leaked`
3. `enemy.blocked_by == 0`（未被別人綁住）
4. `absf(enemy.distance_along - soldier.post_distance) <= ENGAGE_WINDOW`

`ENGAGE_WINDOW := 24.0`（px）。取值理由：銃卒速度 45 px/s，一 tick 走 1.5 px，窗口寬 48 px 相當於 32 個 tick 的通過時間，即使 4 倍速也不會有敵人在單 tick 內跳過整個窗口。倍速實作是「一幀跑多個 tick」而非放大 delta，所以每個 tick 的位移恆為 1.5 px，與倍速無關。

符合者若有多個，取 `distance_along` 最大者（最前面的那個）——與 `TargetingSystem.find_first` 的策略一致，玩家的直覺是「擋住最前面的」。

建立交戰時同時寫兩邊：`soldier.engaged_enemy_id = enemy.id`、`enemy.blocked_by = soldier.id`。

### 5.3 已知後果：潮汐開路時兵營不換崗

崗位在建塔當下算死。B9 做潮汐（第 5 波開通鹿耳門水道）時，新路徑出現，**已蓋好的兵營不會重算崗位**。

這是刻意的取捨而非疏漏：崗位若每 tick 重算，玩家的兵會在兩條路之間瞬移，那比不換崗更糟。B9 要處理的是「潮汐改變地形時，受影響的兵營如何重新指派」，屆時可選的方向包括「新路徑開通時對所有兵營重算一次」或「玩家手動重新指派」。此處只記錄依賴，不預先決定。

### 5.4 解除交戰

三種情況，全部在 `MeleeSystem` 或 `_remove_dead` 處理：

| 情況 | 處理 |
|---|---|
| 敵人死亡 | `soldier.engaged_enemy_id = 0`；小兵開始回血 |
| 小兵死亡 | `enemy.blocked_by = 0`；敵人下一 tick 恢復前進 |
| 兵營被賣掉 | 小兵移除，其敵人的 `blocked_by` 清零 |

敵人 leak 不需處理：被攔截的敵人 `distance_along` 不會推進，走不到終點。

---

## 6. 資料

### 6.1 `data/towers/fence_tower.json`（新）

```json
{
  "id": "fence_tower",
  "name_key": "tower.fence_tower.name",
  "kind": "barracks",
  "damage_type": "physical",
  "icon": "res://game/assets/chapter01/icon_tower_fence.png",
  "levels": [
    {"cost": 60,  "soldier_count": 2, "soldier_hp": 90.0,  "soldier_damage": 6.0,  "soldier_attack_interval": 1.0, "soldier_armor": 0.10, "respawn_time": 12.0, "regen_per_second": 4.0, "sprite": "res://game/assets/chapter01/tower_fence_t1.png"},
    {"cost": 110, "soldier_count": 3, "soldier_hp": 150.0, "soldier_damage": 10.0, "soldier_attack_interval": 0.9, "soldier_armor": 0.20, "respawn_time": 11.0, "regen_per_second": 6.0, "sprite": "res://game/assets/chapter01/tower_fence_t2.png"},
    {"cost": 190, "soldier_count": 3, "soldier_hp": 240.0, "soldier_damage": 15.0, "soldier_attack_interval": 0.8, "soldier_armor": 0.35, "respawn_time": 10.0, "regen_per_second": 9.0, "sprite": "res://game/assets/chapter01/tower_fence_t3.png"}
  ]
}
```

既有的 `musket_tower.json` 與 `hunter_tower.json` 補 `"kind": "shooter"`。

數值是首版，供人工驗收時調整。設計意圖：t1 兩人擋不住第 4 波之後的成群敵人（波次規模 4→16），t2 加到三人是質變，t3 的護甲 0.35 讓它能扛住銃卒的物理近戰。

**塔的 id 是 `fence_tower`，不是 `palisade`**：美術軌已經把這座塔的四張資產產出並匯入了（`tower_fence_t1/t2/t3.png`、`icon_tower_fence.png`），`art/manifest/chapter01_assets.json` 裡的名稱正是「柵欄一級：竹柵／二級：刀盾壯丁／三級：藤牌隊」。既有兩座塔的命名是 `musket_tower` 配 `tower_musket_t*.png`，本塔沿用同一套。`TowerView.setup` 直接 `load(sprite_path)`，路徑打錯是執行期 ERROR 而非編譯錯誤，所以資產路徑必須逐字比對現有檔名。

### 6.2 `data/enemies/orc_grunt.json`

補兩個欄位：

```json
"melee_damage": 12.0,
"melee_interval": 1.0
```

`EnemyFactory.from_def` 是唯一的敵人建構路徑（B4 建立，有原始碼守衛測試），兩個欄位在那裡搬運。

### 6.3 `data/levels/level_01/meta.json`

```json
"available_towers": ["musket_tower", "hunter_tower", "fence_tower"]
```

第三種塔會讓環形選單多一格。B3b 的 `build_menu_options.gd` 是純靜態函式、選項數量由 `available_towers` 決定，不需修改；但**環形選單的版面在三個選項下是否還好按，屬人工驗收項目**。

### 6.4 i18n

`i18n/strings.csv` 補 `tower.fence_tower.name`（zh-TW「柵欄」／en「Palisade」）。三級的分級名稱（竹柵／刀盾壯丁／藤牌隊）在 M1 的 UI 中沒有顯示位置，不加 key——YAGNI。

---

## 7. 表現層

`game/views/soldier_view.gd`（新）：灰盒色塊 **+ 血條**。

血條在這裡是必要的而非裝飾：小兵的耗損與回血是本里程碑的核心機制，沒有血條，人工驗收時無法分辨「系統正常運作」與「傷害根本沒進去」。敵人血條不在本里程碑範圍。

`battle_scene.gd` 的變更沿用既有模式：`_sync_views()` 依 `world.soldiers` 增刪 view、`_interpolate_views()` 不必處理小兵（崗位固定、不移動，無需插值）。

**場景佈線的原始碼守衛**：B2 的教訓是「忘記接一行線，整個功能安靜地不動，而且沒有任何測試會失敗」。小兵 view 的建立同樣落在 headless 測試永遠碰不到的區域，因此 `tests/test_core_purity.gd` 需比照既有做法，加上對 `battle_scene.gd` 的原始碼字串守衛。

---

## 8. 測試策略

`core/` 全部可在 headless 下測。以下是必要的鑑別性測試——每一條後面括號內是「什麼樣的錯誤實作會被它抓到」，寫測試時必須實際把production code 改壞驗證它會紅。

| # | 測試 | 抓什麼 |
|---|---|---|
| T1 | 兵營建好後，`GarrisonSystem.tick` 一次就補滿該級兵數 | 補兵完全沒跑；或只補一個 |
| T2 | 敵人走到崗位窗口內時 `blocked_by` 被寫入，且該 tick 之後 `distance_along` 不再增加 | 交戰沒建立；或建立了但排在 `MovementSystem` 之後（敵人會多走一步——**斷言的是位置精確相等，不是「差不多」**） |
| T3 | 三個小兵 + 四個敵人 → 恰有三個被擋、第四個的 `distance_along` 持續增加 | 1:1 規則寫成 1:N；或第四個也被錯誤地綁住 |
| T4 | 小兵被打死後，它擋住的敵人在下一 tick 恢復前進 | `_remove_dead` 沒清 `blocked_by`（敵人永遠卡住） |
| T5 | 敵人被打死後，小兵 `engaged_enemy_id` 歸零並開始回血 | 解除交戰只做了一半 |
| T6 | 重生倒數走完後同一個 `slot_index` 補回一個滿血小兵 | 重生沒跑；或重生了但名額錯位導致兵數失控 |
| T7 | 脫戰回血不會超過 `max_hp` | 少一個 `minf()` |
| T8 | 交戰中的小兵不回血 | 回血條件寫錯，變成永遠回血（防線就打不破了） |
| T9 | 賣掉兵營後小兵消失，被擋的敵人恢復前進 | 賣塔只刪了塔沒刪兵；或刪了兵沒清 `blocked_by` |
| T10 | 升級後小兵滿血且兵數為新等級的值 | §2 規則 5 沒實作 |
| T11 | `DamageSystem.apply()` 對 `Soldier` 套用它的 `armor` | `Combatant` 重構後減免對小兵失效（**護甲值須避開浮點恰好相等的巧合**，見下） |
| T12 | 敵人的近戰傷害走 `DamageSystem`，不繞過減免 | 近戰自己算傷害，違反硬規則 #2 |

**數值選擇的地雷**（B3b 的實際教訓）：T11 這類「驗證某個係數真的被套用」的測試，若挑到 `200 × 0.75 = 150` 這種在浮點下恰好整除、且 floor／round／ceil 三者答案一致的數字，測試會通過任何實作，等於什麼都沒驗到。選數值時必須挑一個會讓錯誤實作算出不同答案的組合，並實際跑過確認。

**`Combatant` 重構的迴歸風險**：`Enemy` 的五個欄位換家後，280 個既有測試全部必須照樣通過。實作計畫的第一個任務就是這次重構，且在它綠燈之前不寫任何新功能。

---

## 9. 完成判準

1. 全套測試通過，且新測試在對應的 production code 被改壞時會紅（逐條驗證過）。
2. `tests/test_core_purity.gd` 通過——包含新增的 `battle_scene.gd` 佈線守衛。
3. `godot --headless --path . game/level/battle_scene.tscn --quit-after 3000` 無 `SCRIPT ERROR` / `Invalid` / `Parse Error`。
4. 人工驗收：蓋一座柵欄，看得到小兵站上路徑、擋下敵人、互砍、其中一個死亡、倒數後重生、脫戰回血；第 4 個敵人從旁邊走過去；賣掉兵營後敵人立刻恢復前進。小兵在畫面上必須彼此可分辨（不能疊在同一點）。

---

## 10. 對後續里程碑的影響

| 里程碑 | 這裡留下的東西 |
|---|---|
| B6 敵種 | 弓箭手可直接以 `Soldier` 為目標；`Combatant` 讓「敵人攻擊塔」（掘壕隊）也只差一次繼承 |
| B7 英雄 | 英雄是「玩家可指揮的 `Combatant`」，近戰結算可直接沿用 `MeleeSystem` |
| B9 潮汐 | §5.3 的換崗問題必須在那裡解決 |
| B6 地圖資料化 | 崗位計算讀 `world.paths`，路徑改由 `map.json` 提供後不需修改 |
