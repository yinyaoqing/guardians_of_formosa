# M1-A：投射物、物件池與狀態效果系統 — 設計規格

- 日期：2026-09-04
- 狀態：已確認，待轉為實作計畫
- 上層規格：`2026-09-04-tower-defense-architecture-design.md`（§4.3 傷害與狀態效果、§4.4 投射物與物件池）
- 前置：M0 已完成（commit `0bf6167`），戰鬥核心可運作，測試 67/67

## 1. 範圍

M1-A 交付三件事：

1. **投射物**進入模擬層，有飛行時間，命中才結算傷害
2. **物件池**，供投射物與狀態效果實例使用
3. **狀態效果系統**：減速、暈眩、持續傷害、破甲

不在此範圍：士兵攔截（M1-C）、波次系統（M1-D）、輸入與 HUD（M1-B）、敵人本身的池化（見 §5.4）。

### 1.1 已確認的決定

| 決定 | 選擇 | 理由 |
|---|---|---|
| 投射物飛行模型 | **追蹤目標、必中** | 實作單純、數值可推理。目標中途消失則投射物消失，傷害不轉移 |
| 投射物是否進模擬層 | **進入** | 飛行時間帶來「過度打擊」的策略層：多塔齊射快死的敵人會浪費發數 |
| 攻擊型態 | **單體投射物 + 範圍傷害** | 兩者共用同一投射物實體與池，只差在命中時的結算對象。hitscan 延後 |
| 狀態效果如何修改數值 | **基礎欄位 + 每 tick 重算的衍生欄位** | 見 §2 |

## 2. 核心架構決定：基礎值與衍生值分離

### 2.1 決定

敵人的可被狀態效果影響的數值一分為二：

```gdscript
# 基礎值：資料載入時填入，之後永不寫入
var base_speed: float
var base_armor: float
var base_magic_resist: float

# 衍生值：每 tick 被 StatusSystem 覆寫，任何其他程式碼都不得寫入
var speed: float
var armor: float
var magic_resist: float
var stunned: bool          ## 純供表現層顯示暈眩圖示
```

`StatusSystem.tick()` 每 tick 重算衍生值。消費端一行都不用改——`MovementSystem` 照樣讀 `speed`、`DamageSystem` 照樣讀 `armor`。

### 2.2 已評估並排除的替代方案

- **顯式取值函式**（消費端改呼叫 `StatusSystem.effective_speed(enemy)`）：正確性等同，但每個消費端都必須記得改用取值函式，漏掉一處就是靜默的數值錯誤。在 AI 協作下風險過高。
- **直接改欄位、到期還原**：消費端完全不用動，但兩個來源的效果重疊時還原順序會錯，基礎值一旦丟失無法救回。本專案已因此模式踩過一次——`DamageSystem` 的 `clampf(reduction, 0.0, 1.0)` 正是為了防堵破甲直接寫 `enemy.armor` 而加的。

### 2.3 代價與對策

多一條排序規則：`StatusSystem` 必須第一個執行。以 `tests/core/test_tick_order.gd` 釘住（見 §6.2）。

衍生欄位可能被誤寫。以命名（`base_` 前綴）與註解標明「每 tick 被覆寫，不得寫入」處理。

### 2.4 暈眩不需要特例邏輯

暈眩是一個把 `speed` 乘以 0 的修正。`MovementSystem` 完全不知道暈眩存在，敵人只是速度變成 0。`stunned` 布林值純粹供表現層使用。

## 3. tick 順序

```
StatusSystem.tick()      新增，必須第一個
MovementSystem.tick()
_collect_leaked()
_rebuild_grid()
ProjectileSystem.tick()  新增
_tick_towers()
_remove_dead()
```

兩個排序決定的理由：

- **`StatusSystem` 第一個**：否則後續所有系統讀到的是上一 tick 的衍生值。
- **`ProjectileSystem` 在 `_tick_towers` 之前**：塔在這一 tick 生成的投射物，要等下一 tick 才開始飛。若順序相反，投射物會在生成的同一 tick 就移動一格，飛行時間少一 tick。

### 3.1 賞金發放收斂到單一處

目前賞金在 `_tick_towers` 內發放。M1-A 之後傷害來自兩處（投射物命中、DoT 結算），賞金邏輯不能複製兩份。

改為在 `_remove_dead` 的移除迴圈中發放：該處本來就走訪所有死亡的敵人，且 `leaked` 旗標可區分「被擊殺」與「走到終點」。一個地方、一次發放。

## 4. 狀態效果系統

### 4.1 資料格式

JSON，置於 `data/status_effects/`：

```json
{
  "id": "chill",
  "name_key": "status.chill.name",
  "kind": "slow",
  "magnitude": 0.35,
  "duration": 2.5
}
```

```json
{
  "id": "poison",
  "name_key": "status.poison.name",
  "kind": "dot",
  "magnitude": 12.0,
  "duration": 4.0,
  "damage_type": "true"
}
```

四種 `kind`：

| kind | magnitude 的意義 | 作用 |
|---|---|---|
| `slow` | 速度減免比例 0.0–1.0 | `speed = base_speed × (1 − magnitude)` |
| `stun` | 未使用 | `speed = 0` |
| `dot` | **每秒**傷害 | 每 tick 造成 `magnitude × TICK_DELTA` |
| `armor_break` | 護甲減免絕對值 | `armor = max(0, base_armor − magnitude)` |

塔的每一級以 id 引用：`"on_hit_effects": ["chill"]`。

### 4.2 堆疊規則

架構規格 §4.3 訂「同來源刷新持續時間；不同來源取最強」。落實需先定義來源。

**來源 = 施加者的 `tower_id`（塔的種類，不是個別那座塔）。**

三座冰霜塔打同一隻敵人是互相刷新，不疊三層減速。這是 Kingdom Rush 的行為，也是唯一不會讓多塔堆疊失控的定義。

**施加時：**

- 同一 `(kind, source)` 已存在 → 刷新剩餘時間為兩者較大值，並更新強度為新值
- 否則 → 新增一筆

**重算衍生值時**，每種 `kind` 取所有生效效果中最強的一個，只套用一次：

```
speed  = 0                              若有任何 stun 生效
       = base_speed × (1 − 最強 slow)   否則
armor  = max(0, base_armor − 最強 armor_break)
```

來源只決定「刷新或新增」，強度只取最大值。兩件事分開後規則無歧義。

### 4.3 生效中的效果存在哪裡

每隻敵人持有一個 `active_effects: Array[StatusEffect]`。`StatusEffect` 是執行期實例（非 JSON 定義本身），欄位為 `kind`、`source`、`magnitude`、`damage_type`、`remaining`。

實例走池化（見 §5.4）：`StatusSystem` 持有一個效果實例池，施加時取出、到期時歸還。敵人身上的陣列在敵人建立時配置一次，之後只做 append 與原地移除，不重建。

效果存在敵人身上而非集中式登錄表，理由是重算衍生值時只需走訪該敵人自己的效果，不必掃描全域；而敵人被移除時效果自然一併歸還，不會有懸空登錄。

### 4.4 DoT 走 DamageSystem

`magnitude` 是每秒傷害，每 tick 造成 `magnitude × TICK_DELTA`，**必須呼叫 `DamageSystem.apply()`**。這是硬規則第 2 條，DoT 不例外。

好處是中毒傷害同樣吃傷害類型與減免，`"damage_type": "true"` 才能穿甲。

DoT 擊殺的賞金由 §3.1 的 `_remove_dead` 統一發放，不需特例。

死亡敵人身上的效果不再結算。

## 5. 投射物與物件池

### 5.1 實體

```gdscript
class_name Projectile
extends RefCounted

var instance_id: int            ## 每次自池取出都是全新號碼，見 §5.3
var active: bool = false
var projectile_id: StringName   ## 視覺用
var position: Vector2
var target_id: int
var speed: float                ## 像素 / 秒
var damage: float
var damage_type: StringName
var source_tower_id: StringName ## 狀態效果的來源，見 §4.2
var on_hit_effects: Array[StringName]
var splash_radius: float = 0.0  ## 0 表示單體
```

### 5.2 命中判定

投射物自**發射它的塔的座標**生成。

每 tick 朝目標**當前座標**移動 `speed × TICK_DELTA`。命中條件：

```
到目標的距離 ≤ 本 tick 的移動距離
```

保證不穿透，且有限時間內必定命中——後者的前提是投射物速度高於敵人速度，此條件納入資料完整性測試。

目標若在飛行途中死亡或走到終點，投射物歸還池中，不造成傷害、不轉移目標。

### 5.3 instance_id 必須每次取出都換新

池化最常見的 bug：id 被回收再用時，表現層的舊 view 可能誤綁到新的投射物，畫面上出現箭矢瞬移。一個遞增計數器即可根除整類問題。

### 5.4 池化範圍

硬規則「戰鬥迴圈中禁止配置新物件」目前已被違反（最終 review 的 N4：每 tick 重建陣列、每次查詢配置回傳陣列）。M1-A 的範圍：

| 對象 | 池化 | 理由 |
|---|---|---|
| 投射物 | 做 | 每秒數十個生滅，churn 最高 |
| 狀態效果實例 | 做 | 每次命中都可能新增，churn 同樣高 |
| 敵人 | 不做 | 每秒約一隻，churn 低 |
| 系統內部暫存陣列 | 不做 | 屬 N4，需實測才知是否值得，併入 M2 |

先池化 churn 最高的，其餘等 M2 的實機數據再決定。在沒有量測前全面池化，是拿可讀性換未經驗證的效能。

### 5.5 池的行為

```gdscript
const INITIAL_CAPACITY := 128
```

建構時一次配置滿。**用盡時擴容並發出警告，不丟棄投射物**——丟棄等於玩家傷害憑空消失，是玩法 bug；擴容只是一次性配置，擴完即穩定。警告讓此事在開發期浮現。

活躍投射物的移除採原地交換移除，不重建陣列。

### 5.6 AoE

命中時若 `splash_radius > 0`，用 `_rebuild_grid()` 已建好的空間索引查詢半徑內敵人，逐一精確距離判定後套用傷害與效果。

**全額傷害，不做距離衰減。** 衰減使數值難以推理，且 Kingdom Rush 的迫擊砲亦為全額。主目標本身在半徑內，不需特例。

tick 順序已保證索引是新的。

### 5.7 對既有程式碼的影響

`_tick_towers` 從「直接呼叫 `DamageSystem`」改為「向池取得投射物並初始化」。塔不再認識傷害結算，只認識發射。

`DamageSystem` 的呼叫點因此收斂為兩處：投射物命中、DoT 結算。兩處都在系統層，塔的程式碼中一個都沒有——正是硬規則第 2 條要的形狀。

## 6. 檔案結構與測試

### 6.1 檔案

```
core/
├── entities/projectile.gd        新增
├── entities/enemy.gd             修改 — base_* 欄位
├── systems/status_system.gd      新增
├── systems/projectile_system.gd  新增
├── sim/projectile_pool.gd        新增
├── sim/world_state.gd            修改 — projectiles、projectile_pool
├── sim/battle_sim.gd             修改 — tick 順序、賞金搬家
└── data/data_registry.gd         修改 — 載入 status_effects/
data/status_effects/*.json        新增
```

`MovementSystem`、`TargetingSystem`、`DamageSystem`、`UniformGrid`、`PathData` 不動。這是 §2 選擇衍生欄位方案換來的。

池置於 `core/sim/` 而非新開 `core/pool/`，讓架構規格的目錄結構維持不變。

### 6.2 測試策略

除各系統的單元測試外，三類必須顧到：

**釘住本次的設計決定。** 最重要的是**過度打擊測試**：兩座塔對一隻將死的敵人同時開火，第二發必須落空浪費。此測試直接證明「傷害在命中時結算而非發射時結算」；若日後有人為省事改回發射即結算，它會立刻失敗。

**釘住 tick 順序。** 最終 review 指出目前「把 `_tick()` 五行任意重排，大部分測試仍會通過」。M1-A 將順序從五步增為七步，依賴更重。新增 `tests/core/test_tick_order.gd`：

- 這一 tick 施加的減速，必須在同一 tick 就影響移動（證明 `StatusSystem` 先於 `MovementSystem`）
- 這一 tick 生成的投射物，這一 tick 不得移動
- 被擊殺的敵人發一次賞金，走到終點的敵人不發賞金

**堆疊規則的對抗性案例。** 同來源刷新而非疊加、不同來源取最強而非相加、暈眩壓過減速、破甲後護甲不得為負。規則沒有測試就會腐化。

### 6.3 資料完整性測試擴充

- `kind` 必須是四種已知值之一
- `duration` 必須為正
- `magnitude` 必須為正——**但 `stun` 除外**，該類型不使用 `magnitude`，允許缺漏或為 0
- `slow` 的 `magnitude` 必須落在 0.0–1.0（超過 1.0 會使速度為負）
- `dot` 類效果的 `damage_type` 必須是已知傷害類型
- 塔的 `on_hit_effects` 引用的 id 必須存在
- 投射物速度必須高於所有敵人的 `base_speed`（§5.2 的命中保證前提）

### 6.4 既有整合測試的破壞性影響

**既有整合測試會壞掉，而且應該壞掉。** 塔目前開火即結算傷害，改為投射物後傷害延後一個飛行時間，以下兩個測試的期望值會變：

- `test_fire_interval_limits_shots` — 目前斷言 1 秒後 hp 恰為 980.0
- `test_shipped_data_lets_one_tower_kill_one_enemy` — 擊殺時間變長

這不是回歸，是設計變更的正確後果。但實作計畫必須明確要求**重新推導這兩個期望值**，不得在測試紅掉時把數字改成「跑出來是多少就填多少」——那會把測試變成行為的複印機，失去守門意義。新期望值須自飛行時間推導，並在測試中寫明推導過程。

## 7. 待後續決策事項

- `INITIAL_CAPACITY = 128` 為起始值，實際峰值須待 M2 實機驗證後調整
- 系統內部暫存陣列的配置（最終 review 的 N4）併入 M2，須有實機數據才決定是否值得池化
- 敵人本身的池化同上
