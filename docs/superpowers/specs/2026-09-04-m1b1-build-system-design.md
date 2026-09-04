# M1-B1：建塔系統 — 設計規格

- 日期：2026-09-04
- 狀態：已確認，待轉為實作計畫
- 上層規格：`2026-09-04-tower-defense-architecture-design.md`（§5.2 資料結構、§6.1 GameIntent）
- 前置：M1-A 已完成（`main` 的 `d24dd2e`），測試 127/127

## 1. 範圍與拆分理由

原本的 M1-B 描述為「輸入抽象與 HUD：GameIntent 層、觸控與鍵鼠翻譯器、環形建塔選單、HUD、安全區適配」。實際檢視發現它綁了三件可各自獨立交付的東西，且為單向依賴：

| 子計畫 | 內容 | 性質 | 驗收 |
|---|---|---|---|
| **B1**（本規格） | 建塔點、建造／賣出／升級、金錢結算 | 純 `core/` 邏輯 | 單元測試 |
| **B2** | 原始事件 → GameIntent，觸控與鍵鼠翻譯器 | `input/` 層 | 灌 intent 測試 |
| **B3** | HUD、環形建塔選單、射程圈、安全區 | `ui/` 表現層 | 人工驗收 |

沒有 B1，`BuildTower` / `SellTower` / `UpgradeTower` 三個 intent 指涉的操作在 `core/` 裡並不存在；沒有 B2，B3 的按鈕沒有出口。故順序為 B1 → B2 → B3。

**B1 不包含**：任何輸入處理、任何 UI、法術、英雄、波次。

### 1.1 已確認的決定

| 決定 | 選擇 | 理由 |
|---|---|---|
| 升級模型 | **線性三級，分支延後至 M3** | 現有 `levels` 陣列即可承載；垂直切片不需要分支就能驗證好不好玩。intent 簡化為 `UpgradeTower(tower_id)` |
| 建塔點來源 | **場景中的 `Marker2D`** | 與 `Path2D` 同一模式，排版微調最快。代價是資料完整性測試看不到，與路徑同一個已知盲點 |
| 指令生效時機 | **排入佇列，於 tick 第一步套用** | 見 §2 |

### 1.2 修正上層規格的一處矛盾

架構規格 §6.1 將 intent 寫為 `UpgradeTower(tower_id, path)`，該 `path` 參數暗示分支專精；但 `data/towers/*.json` 是扁平的 `levels` 陣列，沒有分支的位置。依 §1.1 的決定，intent 簽章更正為 `UpgradeTower(tower_id)`，分支留待 M3。

## 2. 核心架構決定：指令排入佇列，於 tick 內套用

### 2.1 決定

輸入產生的指令進入 `WorldState` 的待處理佇列，由 `BattleSim._tick()` 在**第一步**排空並套用。

### 2.2 理由

輸入發生在渲染幀上，模擬跑 30Hz 固定步長，兩者不對齊。排入佇列讓**所有改變世界的事情都發生在 tick 內的明確位置**——這正是既有整套 tick 順序測試賴以成立的前提。副產品是把一串 intent 灌進模擬層即可完整重現一場戰鬥，離線平衡模擬與戰鬥回放都免費取得。

代價是最多一個 tick（約 33 毫秒）的延遲，肉眼不可察覺；以及表現層不得假設「按下去塔就存在」，需等下一次同步。

### 2.3 已評估並排除的替代方案

- **收到即套用**：零延遲、程式最少，但世界會在任何 tick 之外被改動，而 `advance()` 一幀可能跑 0 到 8 個 tick，改動落在哪兩個 tick 之間並不確定。確定性、回放與離線平衡模擬全數喪失，且日後要加回來需重寫整條路徑。
- **幀首套用**：改動仍在 tick 之外，確定性一樣不成立。實質為前者的劣化版。

### 2.4 為何排在 tick 第一步

這一 tick 蓋好的塔，這一 tick 就能開火；賣掉的塔在能開火之前就消失。兩者皆符合直覺且不需任何特例。

## 3. 資料模型

### 3.1 GameIntent

沿用架構規格 §6.1 的詞彙。B1 只用三種 kind，但 B2 的法術、英雄、加速、暫停將進同一佇列。

```gdscript
class_name GameIntent
extends RefCounted

const KIND_BUILD := &"build"
const KIND_SELL := &"sell"
const KIND_UPGRADE := &"upgrade"

var kind: StringName = &""
var slot_id: int = 0            ## KIND_BUILD 用
var tower_id: StringName = &""  ## KIND_BUILD 用，要蓋哪一種
var entity_id: int = 0          ## KIND_SELL / KIND_UPGRADE 用，動哪一座
```

**不做池化。** intent 由人手驅動，每秒最多數個，與每秒數十個生滅的投射物不同量級。沿用 M1-A 訂下的「只池化 churn 最高的」原則。

### 3.2 BuildSlot

```gdscript
class_name BuildSlot
extends RefCounted

var id: int = 0                ## 由 WorldState.next_id() 配發
var position: Vector2 = Vector2.ZERO
var occupied_by: int = 0       ## 塔的實體 id，0 表示空著
```

id 走 `WorldState.next_id()` 的共用計數器，與敵人、塔、投射物同一號碼空間，維持「實體 id 永不跨型別重複」的性質。

場景中以 `Marker2D` 標位置，載入時烘焙成 `BuildSlot` 陣列交給 `core/`——與 `Path2D → PathData` 同一模式，`core/` 一樣不認得 `Marker2D`。

### 3.3 關卡 meta

架構規格 §5.2 描述過 `data/levels/level_01/meta.json`，但 M0 只建立了 `enemies/` 與 `towers/`，`data/levels/` 至今不存在。B1 一併建立：

```json
{
  "id": "level_01",
  "name_key": "level.level_01.name",
  "starting_gold": 200,
  "starting_lives": 20,
  "sell_refund_ratio": 0.75,
  "available_towers": ["archer_tower"]
}
```

`sell_refund_ratio` 置於關卡而非全域，理由是它可能因關卡難度而異；今日所有關卡同值，但不需為單一數字發明新的全域資料檔。

### 3.4 WorldState 新增欄位

- `build_slots: Array[BuildSlot]`、`build_slots_by_id: Dictionary`
- `pending_intents: Array[GameIntent]`、`queue_intent(intent) -> void`
- `tower_defs: Dictionary`、`available_towers: Array[StringName]`、`sell_refund_ratio: float`

## 4. 命名變更：`apply_definitions` → `configure_for_level`

`WorldState.apply_definitions()` 目前只注入 `effect_defs`。B1 之後它還需注入塔的定義、本關可用塔種、起始金幣與生命，名稱已不符實。

改為 `configure_for_level(registry: DataRegistry, level_id: StringName) -> void`，**一次呼叫把世界配置完成，沒有第二處要記得**。

這正面回應 M1-A 最終 review 抓到的 Critical：漏接線之所以發生，正因為「要記得的地方」不只一處。`tests/test_core_purity.gd` 中掃描 `battle_scene.gd` 原始碼的接線守衛，須同步改抓新名稱。

## 5. 金錢規則

| 動作 | 花費／回收 |
|---|---|
| 建造 | `levels[0].cost` |
| 升級至第 n 級 | `levels[n-1].cost` |
| 賣出 | `sell_refund_ratio × (levels[0..level-1] 造價總和)` |

**賣價由資料算出，不額外記帳。** 塔身上不儲存「已投入多少」，而是自 `level` 反推造價總和，少一個會不同步的欄位。

## 6. 拒絕條件

指令被拒絕分為兩類，分野是「資料對不對」而非「時機對不對」。

| 情況 | 處理 |
|---|---|
| 建塔點 id 不存在 | **`push_error`** — 資料錯誤 |
| 塔種不存在於 `tower_defs` | **`push_error`** — 資料錯誤 |
| 塔種不在本關 `available_towers` | **`push_error`** — UI 不該給得出此選項 |
| 建塔點已被占用 | 靜默拒絕 — 競態 |
| 金幣不足 | 靜默拒絕 — 競態 |
| 要賣／升級的塔已不存在 | 靜默拒絕 — 可能剛被賣掉 |
| 已達最高級 | 靜默拒絕 |

**靜默拒絕是預期中的正常結果，不是錯誤。** 玩家快速點兩下、或 UI 使用上一 tick 的金幣數，都會產生合法但已不成立的指令。把正常競態當成錯誤噴出，只會訓練所有人無視錯誤訊息。

## 7. 賣塔在 core 中是乾淨的

投射物身上的 `source_tower_id` 是**塔的種類**（`StringName`），不是實體 id。因此賣掉一座塔不會使任何飛行中的投射物產生懸空引用——它們照常飛完並結算。表現層需清除對應的 view，但那屬於 B3。

## 8. 檔案結構

```
core/entities/build_slot.gd       新增
core/entities/game_intent.gd      新增
core/systems/build_system.gd      新增
core/sim/world_state.gd           修改：§3.4 的欄位、configure_for_level
core/sim/battle_sim.gd            修改：tick 第一步套用 intent
core/data/data_registry.gd        修改：載入 data/levels/
data/levels/level_01/meta.json    新增
game/level/battle_scene.tscn      修改：加入 Marker2D 建塔點
game/level/battle_scene.gd        修改：烘焙建塔點、改呼叫 configure_for_level
tests/core/test_build_system.gd   新增
tests/core/test_tick_order.gd     修改
tests/core/test_battle_integration.gd  修改：apply_definitions 更名連帶影響
tests/test_data_integrity.gd      修改
tests/test_core_purity.gd         修改：接線守衛改抓新名稱
```

`tests/core/test_battle_integration.gd` 中的 `test_apply_definitions_wires_effect_defs_from_the_registry` 直接呼叫了 `apply_definitions`，會因 §4 的更名而失敗。該測試是 M1-A 為了擋住漏接線而加的，**必須跟著改名並改為驗證 `configure_for_level` 注入的全部內容**（效果定義、塔定義、可用塔種、起始金幣與生命），而不是只改個方法名就算數——否則新增的注入項目一樣沒有守衛。

`MovementSystem`、`TargetingSystem`、`DamageSystem`、`ProjectileSystem`、`StatusSystem`、`UniformGrid`、`PathData`、`ObjectPool` 一律不動。

### 8.1 tick 順序（八步）

```
套用待處理 intent    ← 新增，第一步
StatusSystem
MovementSystem
collect leaked
rebuild grid
ProjectileSystem
tick towers
remove dead
```

`BattleSim` 排空佇列並依 `kind` 分派。B1 只有一個去處（`BuildSystem`），B2 新增 kind 時擴充 case。

## 9. 測試策略

除各拒絕條件與成功路徑的單元測試外，兩處特別易犯本專案反覆出現的錯誤——測試通過了它宣稱要排除的實作：

**賣價測試必須使用等級大於 1 的塔。** 若以一級塔測試，「退款 = 比例 × 全部投入」與「退款 = 比例 × 一級造價」結果相同，錯誤實作照樣通過。

**「tick 第一步套用」的測試必須觀察同一 tick 內的後果**，例如「這一 tick 建造的塔，這一 tick 就開火」。僅斷言「下一 tick 塔存在」的話，把套用挪至 tick 尾端也會通過。

資料完整性測試擴充：關卡 meta 的必填欄位、`available_towers` 引用存在的塔、`sell_refund_ratio` 落在 0 到 1、起始金幣與生命為正。

**但關卡目錄不能直接套用既有的兩道通用守衛。** `enemies/` 與 `towers/` 是「一個實體一個檔案，且檔名等於 id」；關卡是「一個關卡一個**目錄**，檔案固定叫 `meta.json`」。既有的 `test_json_id_matches_filename` 若直接把 `data/levels` 加進目錄清單，會因為 `meta.json` 的檔名永遠不等於 `level_01` 而必然失敗。

正確做法是為關卡寫一條對應的守衛：**目錄名等於 `id`**，並確認關卡數等於註冊表大小以擋掉重複 id。這是既有守衛的同一個意圖套用在不同的目錄形狀上，不是放寬。

## 10. 一個刻意留下的過渡程式碼

B1 完成後畫面上將一座塔都沒有——現有那座是 `battle_scene.gd` 寫死免費放置的，B1 會移除它，而真正的建塔 UI 要到 B3 才有。

過渡做法：於 `battle_scene.gd` 保留一行「開場自動對第一個建塔點送出一筆 build intent」。畫面維持可玩，且該行本身即走新的佇列路徑，等同順手為它做煙霧測試。

**此行屬於 B3 的刪除清單**，須在規格與程式碼註解中皆標明，避免成為永久的怪異程式碼。

## 11. 待後續決策事項

- 分支升級的資料格式與 intent 簽章（M3）
- 建塔點來源與路徑同屬「場景資料，完整性測試看不到」的盲點；是否引入場景資料的自動驗證手段，留待 B3 與 M2 一併評估
