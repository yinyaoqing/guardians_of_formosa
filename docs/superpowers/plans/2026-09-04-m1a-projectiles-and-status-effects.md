# M1-A 投射物與狀態效果系統 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓塔發射有飛行時間的投射物，命中時才結算傷害並施加狀態效果（減速／暈眩／持續傷害／破甲），投射物與效果實例走物件池。

**Architecture:** 敵人的可變數值一分為二——`base_*` 由資料載入後永不寫入，衍生值每 tick 由 `StatusSystem` 重算覆寫。因此 `MovementSystem`、`TargetingSystem`、`DamageSystem` 一行都不用改，代價是 `StatusSystem` 必須排在 tick 迴圈最前面，此規則由測試釘住。投射物是模擬層的真實實體，帶來「過度打擊」的策略層。

**Tech Stack:** Godot 4.7.2、GDScript、GdUnit4 6.2.1。

## Global Constraints

出自 `docs/superpowers/specs/2026-09-04-tower-defense-architecture-design.md` 與 M1-A 設計規格。**每個任務的要求都隱含包含本節。**

- 只使用 Godot 4.x API。禁用 `KinematicBody2D`、`yield`、`export var`。
- 只使用 GDScript，不引入 C#。
- `core/` 不得 import 任何 Node 或引擎場景類別。允許 `FileAccess`、`DirAccess`、`JSON`、`Vector2`、`PackedVector2Array`。所有新類別 `extends RefCounted`。此規則由 `tests/test_core_purity.gd` 自動驗證。
- **傷害一律經過 `DamageSystem.apply()`**，DoT 與投射物命中都不例外。禁止任何地方自行計算減免。
- 實體之間只用字串 id 或整數實體 id 互相引用，不存直接物件引用。
- 邏輯 tick 固定 30Hz（`BattleSim.TICK_DELTA`）。
- 遊戲資料一律 JSON，置於 `data/`，不使用 `.tres`。
- UI 與資料中只存 i18n key，`name_key` 欄位不得放字面文字。
- `.gd` 檔一律用 **tab** 縮排。
- Godot 為每個腳本產生 `.uid` 檔，**必須與腳本一起提交**。

### 測試指令

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

`--ignoreHeadlessMode` 為必要旗標，缺少時 GdUnit4 直接 exit 103 不執行任何測試。單檔執行時把 `res://tests` 換成該檔路徑。

新增 `class_name` 後若出現「not declared in the current scope」，執行 `godot --headless --path . --import` 重建全域類別快取。該指令即使成功也可能回傳非零結束碼，以輸出內容判斷而非結束碼。

### 已驗證可用的斷言

只使用這些形式：`assert_int(x).is_equal(y)`、`assert_float(x).is_equal_approx(y, eps)`、`assert_bool(x).is_true()/.is_false()`、`assert_str(s).contains(...)`、`assert_array(a).has_size(n)/.contains([...])`、`assert_int(x).is_greater(n)`、`assert_float(x).is_between(lo, hi)`，以及鏈在最終斷言前的 `.override_failure_message("...")`。

`JSON.parse_string()` 一律把數字解析成 `float`，需要整數時必須明確轉換。

### 起始狀態

M0 已完成，`main` 為 `7103e56`。測試 67/67 通過，10 個 suite。

---

## 對規格的一處偏離

設計規格 §6.1 列出 `core/sim/projectile_pool.gd`。本計畫改為單一泛型 `core/sim/object_pool.gd`，同時供投射物與狀態效果實例使用。

理由：兩者的取得、歸還、擴容與警告邏輯完全相同，寫成兩份即為重複。泛型池以工廠 `Callable` 建構，約 40 行。

---

## File Structure

| 檔案 | 責任 |
|---|---|
| `core/entities/enemy.gd` | 修改：`base_*` 欄位、`active_effects`、`reset_derived_stats()` |
| `core/entities/status_effect.gd` | 新增：效果的執行期實例（非 JSON 定義） |
| `core/entities/projectile.gd` | 新增：投射物實體 |
| `core/sim/object_pool.gd` | 新增：泛型物件池，投射物與效果共用 |
| `core/systems/status_system.gd` | 新增：施加、堆疊、重算衍生值、持續時間、DoT |
| `core/systems/projectile_system.gd` | 新增：飛行、命中判定、單體與 AoE 結算 |
| `core/sim/world_state.gd` | 修改：`projectiles`、兩個池、`next_id()` |
| `core/sim/battle_sim.gd` | 修改：tick 順序、塔改為發射、賞金搬家 |
| `core/data/data_registry.gd` | 修改：載入 `status_effects/`、建立效果實例 |
| `data/status_effects/*.json` | 新增：四種 kind 各一 |
| `data/towers/archer_tower.json` | 修改：投射物參數與 `on_hit_effects` |
| `tests/core/test_status_system.gd` | 新增 |
| `tests/core/test_projectile_system.gd` | 新增 |
| `tests/core/test_object_pool.gd` | 新增 |
| `tests/core/test_tick_order.gd` | 新增：釘住 tick 順序 |
| `tests/test_data_integrity.gd` | 修改：效果與投射物的檢查 |

---

### Task 1: Enemy 基礎值與衍生值分離

純重構，行為不變。此任務結束時 `StatusSystem` 尚不存在，衍生值恆等於基礎值。

**Files:**
- Modify: `core/entities/enemy.gd`
- Modify: `core/data/data_registry.gd`（`make_enemy` 改設基礎值）
- Modify: `tests/core/test_movement_system.gd`、`tests/core/test_targeting_system.gd`、`tests/core/test_damage_system.gd`、`tests/core/test_battle_integration.gd`（測試輔助函式改設基礎值）

**Interfaces:**
- Consumes: 無
- Produces:
  - `Enemy.base_speed: float`、`Enemy.base_armor: float`、`Enemy.base_magic_resist: float`
  - `Enemy.reset_derived_stats() -> void`
  - 衍生欄位 `speed`、`armor`、`magic_resist`、`stunned` 語意變更為「由 StatusSystem 覆寫」

- [ ] **Step 1: 改寫 Enemy**

Replace the stat fields in `core/entities/enemy.gd`（保留 `id`、`enemy_id`、`hp`、`max_hp`、`bounty`、`path_id`、`distance_along`、`position`、`alive`、`leaked`、`blocked_by` 不動）:

```gdscript
## 基礎數值：資料載入時填入，之後永不寫入。
## 狀態效果只改衍生值，基礎值必須保持乾淨，否則效果到期後無法還原。
var base_speed: float = 0.0            ## 像素 / 秒
var base_armor: float = 0.0            ## 物理減免比例，0.0 ~ 0.95
var base_magic_resist: float = 0.0     ## 魔法減免比例，0.0 ~ 0.95

## 衍生數值：每 tick 由 StatusSystem 依 active_effects 重算並覆寫。
## 除 StatusSystem 外，任何程式碼都不得寫入這四個欄位。
var speed: float = 0.0
var armor: float = 0.0
var magic_resist: float = 0.0
var stunned: bool = false              ## 純供表現層顯示暈眩圖示

## 生效中的狀態效果。實例來自物件池，由 StatusSystem 管理生滅。
var active_effects: Array[StatusEffect] = []
```

在檔案末端加入：

```gdscript
## 把基礎值複製到衍生值。資料載入後呼叫一次，
## 之後每 tick 由 StatusSystem 在重算開頭呼叫。
func reset_derived_stats() -> void:
	speed = base_speed
	armor = base_armor
	magic_resist = base_magic_resist
	stunned = false
```

`active_effects` 的型別 `StatusEffect` 在 Task 2 才建立。**本任務先把該欄位宣告為 `Array`（無型別參數）**，Task 2 建立 `StatusEffect` 後再改為 `Array[StatusEffect]`。否則本任務無法通過解析。

- [ ] **Step 2: 更新 DataRegistry.make_enemy**

在 `core/data/data_registry.gd` 中，把 `make_enemy` 的數值指派改為：

```gdscript
	enemy.base_speed = def["speed"]
	enemy.base_armor = def["armor"]
	enemy.base_magic_resist = def["magic_resist"]
	enemy.reset_derived_stats()
```

（原本的 `enemy.speed = def["speed"]` 等三行刪除。`hp`、`max_hp`、`bounty`、`enemy_id`、`path_id` 的指派不動。）

- [ ] **Step 3: 更新四個測試檔的敵人建構**

四個檔案裡建立 `Enemy` 的輔助函式，凡是設定 `speed`、`armor`、`magic_resist` 的地方，改為設定 `base_*` 後呼叫 `reset_derived_stats()`。

例如 `tests/core/test_damage_system.gd` 的 `_make_enemy`：

```gdscript
func _make_enemy(armor: float, magic_resist: float) -> Enemy:
	var enemy := Enemy.new()
	enemy.id = 1
	enemy.hp = 100.0
	enemy.max_hp = 100.0
	enemy.base_armor = armor
	enemy.base_magic_resist = magic_resist
	enemy.reset_derived_stats()
	return enemy
```

`tests/core/test_movement_system.gd` 的 `_make_enemy` 同理，把 `enemy.speed = 50.0` 改為 `enemy.base_speed = 50.0` 後呼叫 `reset_derived_stats()`。

`tests/core/test_targeting_system.gd` 與 `tests/core/test_battle_integration.gd` 中所有直接指派這三個欄位的地方一律比照辦理。**不要改動任何斷言的期望值**——本任務行為不變，數字全部照舊。

- [ ] **Step 4: 執行全套件確認行為未變**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 67 個測試全部 PASS，exit 0。**任何斷言失敗都代表重構改變了行為，必須修正而非調整期望值。**

- [ ] **Step 5: 提交**

```bash
git add core/entities/enemy.gd core/data/data_registry.gd tests/core/
git commit -m "refactor(core): 敵人數值分離為基礎值與衍生值"
```

---

### Task 2: StatusEffect 實體與泛型物件池

**Files:**
- Create: `core/entities/status_effect.gd`
- Create: `core/sim/object_pool.gd`
- Modify: `core/entities/enemy.gd`（`active_effects` 補上型別參數）
- Test: `tests/core/test_object_pool.gd`

**Interfaces:**
- Consumes: 無
- Produces:
  - `StatusEffect` 常數 `KIND_SLOW`、`KIND_STUN`、`KIND_DOT`、`KIND_ARMOR_BREAK`（皆為 `StringName`）
  - `StatusEffect` 欄位 `kind`、`source`、`magnitude`、`damage_type`、`remaining`，方法 `reset() -> void`
  - `ObjectPool.new(factory: Callable, initial_capacity: int) -> ObjectPool`
  - `ObjectPool.acquire() -> Variant`、`.release(obj: Variant) -> void`
  - `ObjectPool.capacity() -> int`、`.free_count() -> int`

- [ ] **Step 1: 寫失敗的測試**

Create `tests/core/test_object_pool.gd`:

```gdscript
extends GdUnitTestSuite

func _make_pool(capacity: int) -> ObjectPool:
	return ObjectPool.new(func() -> StatusEffect: return StatusEffect.new(), capacity)

func test_pool_preallocates_to_capacity() -> void:
	var pool := _make_pool(4)
	assert_int(pool.capacity()).is_equal(4)
	assert_int(pool.free_count()).is_equal(4)

func test_acquire_reduces_free_count() -> void:
	var pool := _make_pool(4)
	pool.acquire()
	assert_int(pool.free_count()).is_equal(3)

func test_release_returns_object_to_pool() -> void:
	var pool := _make_pool(4)
	var obj := pool.acquire()
	pool.release(obj)
	assert_int(pool.free_count()).is_equal(4)

func test_exhausted_pool_grows_instead_of_returning_null() -> void:
	# 丟棄投射物等於玩家傷害憑空消失，是玩法 bug；擴容只是一次性配置
	var pool := _make_pool(2)
	pool.acquire()
	pool.acquire()
	var third: Variant = pool.acquire()
	assert_bool(third != null).override_failure_message(
		"池用盡時必須擴容並回傳可用物件，不得回傳 null"
	).is_true()
	assert_int(pool.capacity()).is_greater(2)

func test_reset_clears_effect_fields() -> void:
	var effect := StatusEffect.new()
	effect.kind = StatusEffect.KIND_SLOW
	effect.source = &"archer_tower"
	effect.magnitude = 0.5
	effect.remaining = 3.0
	effect.reset()
	assert_str(effect.kind).is_equal("")
	assert_float(effect.magnitude).is_equal_approx(0.0, 0.001)
	assert_float(effect.remaining).is_equal_approx(0.0, 0.001)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_object_pool.gd
```

Expected: FAIL，識別字 `ObjectPool` 與 `StatusEffect` 未定義。

- [ ] **Step 3: 寫 StatusEffect**

Create `core/entities/status_effect.gd`:

```gdscript
class_name StatusEffect
extends RefCounted

## 狀態效果的「執行期實例」，不是 JSON 定義本身。
## 實例走物件池：施加時取出、到期時歸還，避免戰鬥迴圈中配置新物件。

const KIND_SLOW := &"slow"
const KIND_STUN := &"stun"
const KIND_DOT := &"dot"
const KIND_ARMOR_BREAK := &"armor_break"

## 施加者的 tower_id（塔的「種類」，不是個別那座塔）。
## 堆疊規則以此判定「同來源刷新」或「不同來源並存」。
var source: StringName = &""

var kind: StringName = &""
var magnitude: float = 0.0
var damage_type: StringName = &""   ## 僅 KIND_DOT 使用
var remaining: float = 0.0          ## 剩餘秒數

func reset() -> void:
	source = &""
	kind = &""
	magnitude = 0.0
	damage_type = &""
	remaining = 0.0
```

- [ ] **Step 4: 寫 ObjectPool**

Create `core/sim/object_pool.gd`:

```gdscript
class_name ObjectPool
extends RefCounted

## 泛型物件池。投射物與狀態效果實例共用，兩者的取得／歸還／擴容邏輯完全相同。
##
## 用盡時擴容而非回傳 null：丟棄一個投射物等於玩家的傷害憑空消失，那是玩法 bug；
## 擴容只是一次性配置，擴完即穩定。警告讓容量不足在開發期浮現。

var _factory: Callable
var _free: Array = []
var _capacity: int = 0

func _init(factory: Callable, initial_capacity: int) -> void:
	assert(initial_capacity > 0, "物件池初始容量必須為正")
	_factory = factory
	for i in initial_capacity:
		_free.append(_factory.call())
	_capacity = initial_capacity

func acquire() -> Variant:
	if _free.is_empty():
		_grow()
	return _free.pop_back()

func release(obj: Variant) -> void:
	_free.append(obj)

func capacity() -> int:
	return _capacity

func free_count() -> int:
	return _free.size()

func _grow() -> void:
	var added := _capacity
	push_warning("ObjectPool 容量不足，自 %d 擴充至 %d。若頻繁發生應調高初始容量。" % [_capacity, _capacity + added])
	for i in added:
		_free.append(_factory.call())
	_capacity += added
```

- [ ] **Step 5: 補上 Enemy 的型別參數**

在 `core/entities/enemy.gd` 中把：

```gdscript
var active_effects: Array = []
```

改為：

```gdscript
var active_effects: Array[StatusEffect] = []
```

- [ ] **Step 6: 執行全套件確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 72 個測試全部 PASS（67 + 5 新增），exit 0。

- [ ] **Step 7: 提交**

```bash
git add core/entities/status_effect.gd core/entities/status_effect.gd.uid \
        core/sim/object_pool.gd core/sim/object_pool.gd.uid \
        core/entities/enemy.gd tests/core/test_object_pool.gd tests/core/test_object_pool.gd.uid
git commit -m "feat(core): 新增 StatusEffect 實體與泛型物件池"
```

---

### Task 3: 狀態效果資料與載入

**Files:**
- Create: `data/status_effects/chill.json`、`stun_shock.json`、`poison.json`、`sunder.json`
- Modify: `core/data/data_registry.gd`
- Modify: `tests/test_data_integrity.gd`

**Interfaces:**
- Consumes: `StatusEffect`（Task 2）
- Produces:
  - `DataRegistry.status_effects: Dictionary`（`StringName` → JSON `Dictionary`）
  - `DataRegistry.load_from_disk()` 一併載入 `status_effects/`

- [ ] **Step 1: 建立四個效果定義**

四種 `kind` 各一個，讓完整性測試有真實資料可驗。

Create `data/status_effects/chill.json`:

```json
{
  "id": "chill",
  "name_key": "status.chill.name",
  "kind": "slow",
  "magnitude": 0.35,
  "duration": 2.5
}
```

Create `data/status_effects/stun_shock.json`:

```json
{
  "id": "stun_shock",
  "name_key": "status.stun_shock.name",
  "kind": "stun",
  "duration": 1.0
}
```

Create `data/status_effects/poison.json`:

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

Create `data/status_effects/sunder.json`:

```json
{
  "id": "sunder",
  "name_key": "status.sunder.name",
  "kind": "armor_break",
  "magnitude": 0.15,
  "duration": 5.0
}
```

注意 `stun_shock.json` **刻意沒有 `magnitude`**——暈眩不使用該欄位，完整性測試必須容許這個例外。

- [ ] **Step 2: 寫失敗的完整性測試**

在 `tests/test_data_integrity.gd` 末端加入：

```gdscript
func test_at_least_one_status_effect_is_loaded() -> void:
	assert_int(_registry.status_effects.size()).is_greater(0)

func test_every_status_effect_has_known_kind() -> void:
	var known := [
		StatusEffect.KIND_SLOW,
		StatusEffect.KIND_STUN,
		StatusEffect.KIND_DOT,
		StatusEffect.KIND_ARMOR_BREAK,
	]
	for effect_id: StringName in _registry.status_effects:
		var kind := StringName(_registry.status_effects[effect_id]["kind"])
		assert_bool(known.has(kind)).override_failure_message(
			"狀態效果 %s 的 kind「%s」不是已知的四種之一" % [effect_id, kind]
		).is_true()

func test_every_status_effect_has_positive_duration() -> void:
	for effect_id: StringName in _registry.status_effects:
		assert_float(_registry.status_effects[effect_id]["duration"]).override_failure_message(
			"狀態效果 %s 的 duration 必須為正" % effect_id
		).is_greater(0.0)

func test_magnitude_is_positive_except_for_stun() -> void:
	# 暈眩不使用 magnitude，允許缺漏；其餘三種必須有正值
	for effect_id: StringName in _registry.status_effects:
		var def: Dictionary = _registry.status_effects[effect_id]
		if StringName(def["kind"]) == StatusEffect.KIND_STUN:
			continue
		assert_bool(def.has("magnitude")).override_failure_message(
			"狀態效果 %s 缺少 magnitude" % effect_id
		).is_true()
		assert_float(def["magnitude"]).override_failure_message(
			"狀態效果 %s 的 magnitude 必須為正" % effect_id
		).is_greater(0.0)

func test_slow_magnitude_is_within_zero_to_one() -> void:
	# 超過 1.0 會讓速度變成負數
	for effect_id: StringName in _registry.status_effects:
		var def: Dictionary = _registry.status_effects[effect_id]
		if StringName(def["kind"]) != StatusEffect.KIND_SLOW:
			continue
		assert_float(def["magnitude"]).override_failure_message(
			"減速效果 %s 的 magnitude 必須落在 0.0 與 1.0 之間" % effect_id
		).is_between(0.0, 1.0)

func test_dot_effects_declare_a_known_damage_type() -> void:
	var known := [DamageSystem.PHYSICAL, DamageSystem.MAGIC, DamageSystem.TRUE_DAMAGE]
	for effect_id: StringName in _registry.status_effects:
		var def: Dictionary = _registry.status_effects[effect_id]
		if StringName(def["kind"]) != StatusEffect.KIND_DOT:
			continue
		assert_bool(def.has("damage_type")).override_failure_message(
			"持續傷害效果 %s 缺少 damage_type" % effect_id
		).is_true()
		assert_bool(known.has(StringName(def["damage_type"]))).override_failure_message(
			"持續傷害效果 %s 的 damage_type 不是已知類型" % effect_id
		).is_true()
```

- [ ] **Step 3: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_data_integrity.gd
```

Expected: FAIL，`_registry.status_effects` 不存在。

- [ ] **Step 4: 在 DataRegistry 加入載入**

在 `core/data/data_registry.gd` 中，於 `towers` 宣告後加入：

```gdscript
var status_effects: Dictionary = {}   ## StringName -> Dictionary
```

並在 `load_from_disk` 末端加入：

```gdscript
	status_effects = _load_dir(root.path_join("status_effects"))
```

- [ ] **Step 5: 執行全套件確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 78 個測試全部 PASS（72 + 6 新增），exit 0。

- [ ] **Step 6: 驗證完整性測試真的會咬人**

暫時把 `data/status_effects/chill.json` 的 `magnitude` 改成 `1.5`，重跑：

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_data_integrity.gd
```

Expected: FAIL，訊息為「減速效果 chill 的 magnitude 必須落在 0.0 與 1.0 之間」。

確認後把 `magnitude` 改回 `0.35`，並以 `git status --porcelain data/` 確認 `data/` 乾淨後再繼續。

- [ ] **Step 7: 提交**

```bash
git add data/status_effects/ core/data/data_registry.gd tests/test_data_integrity.gd
git commit -m "feat(data): 新增四種狀態效果定義與其完整性測試"
```

---

### Task 4: StatusSystem — 施加與堆疊規則

**Files:**
- Create: `core/systems/status_system.gd`
- Test: `tests/core/test_status_system.gd`

**Interfaces:**
- Consumes: `StatusEffect`、`ObjectPool`、`Enemy`
- Produces:
  - `StatusSystem.new(effect_pool: ObjectPool) -> StatusSystem`
  - `StatusSystem.apply(enemy: Enemy, effect_def: Dictionary, source: StringName) -> void`

堆疊規則：同一 `(kind, source)` 已存在則刷新剩餘時間為兩者較大值並更新強度；否則新增一筆。**來源是塔的種類 `tower_id`，不是個別那座塔**——三座冰霜塔打同一隻敵人是互相刷新，不疊三層。

- [ ] **Step 1: 寫失敗的測試**

Create `tests/core/test_status_system.gd`:

```gdscript
extends GdUnitTestSuite

const CHILL := {"id": "chill", "kind": "slow", "magnitude": 0.35, "duration": 2.5}
const DEEP_CHILL := {"id": "deep_chill", "kind": "slow", "magnitude": 0.60, "duration": 1.0}

var _system: StatusSystem

func before_test() -> void:
	var pool := ObjectPool.new(func() -> StatusEffect: return StatusEffect.new(), 16)
	_system = StatusSystem.new(pool)

func _make_enemy() -> Enemy:
	var enemy := Enemy.new()
	enemy.id = 1
	enemy.hp = 100.0
	enemy.max_hp = 100.0
	enemy.base_speed = 100.0
	enemy.base_armor = 0.2
	enemy.reset_derived_stats()
	return enemy

func test_applying_effect_adds_it_to_the_enemy() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	assert_array(enemy.active_effects).has_size(1)

func test_same_kind_and_source_refreshes_instead_of_stacking() -> void:
	# 三座同型塔打同一隻敵人不該疊三層
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.apply(enemy, CHILL, &"frost_tower")
	assert_array(enemy.active_effects).override_failure_message(
		"同一 kind 與 source 必須刷新既有效果，不得新增"
	).has_size(1)

func test_refresh_takes_the_longer_remaining_time() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")        # remaining 2.5
	enemy.active_effects[0].remaining = 0.5            # 模擬已經過了一段時間
	_system.apply(enemy, CHILL, &"frost_tower")        # 應刷新回 2.5
	assert_float(enemy.active_effects[0].remaining).is_equal_approx(2.5, 0.001)

func test_refresh_does_not_shorten_a_longer_remaining_time() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	enemy.active_effects[0].remaining = 10.0           # 比新效果長
	_system.apply(enemy, CHILL, &"frost_tower")
	assert_float(enemy.active_effects[0].remaining).is_equal_approx(10.0, 0.001)

func test_same_kind_from_different_source_coexists() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.apply(enemy, DEEP_CHILL, &"ice_mage_tower")
	assert_array(enemy.active_effects).override_failure_message(
		"不同來源的同類效果必須並存，強度在重算時才取最大值"
	).has_size(2)

func test_effect_records_source_and_magnitude() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	var effect: StatusEffect = enemy.active_effects[0]
	assert_str(effect.source).is_equal("frost_tower")
	assert_str(effect.kind).is_equal("slow")
	assert_float(effect.magnitude).is_equal_approx(0.35, 0.001)

func test_dot_effect_records_damage_type() -> void:
	var enemy := _make_enemy()
	var poison := {"id": "poison", "kind": "dot", "magnitude": 12.0, "duration": 4.0, "damage_type": "true"}
	_system.apply(enemy, poison, &"poison_tower")
	assert_str(enemy.active_effects[0].damage_type).is_equal("true")
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_status_system.gd
```

Expected: FAIL，識別字 `StatusSystem` 未定義。

- [ ] **Step 3: 寫 StatusSystem 的施加部分**

Create `core/systems/status_system.gd`:

```gdscript
class_name StatusSystem
extends RefCounted

## 狀態效果的施加、堆疊、到期與衍生數值重算。
##
## 堆疊規則（架構規格 §4.3）：同來源刷新持續時間，不同來源取最強。
## 「來源」定義為施加者的 tower_id，也就是塔的「種類」而非個別那座塔——
## 三座同型冰霜塔打同一隻敵人是互相刷新，不疊三層。這是唯一不會讓多塔堆疊失控的定義。
##
## 來源只決定「刷新或新增」；強度只在重算衍生值時取各 kind 的最大值。
## 兩件事分開後規則就沒有歧義。

var _pool: ObjectPool

func _init(effect_pool: ObjectPool) -> void:
	_pool = effect_pool

## 對敵人施加一個效果。effect_def 為 DataRegistry 載入的 JSON 字典。
func apply(enemy: Enemy, effect_def: Dictionary, source: StringName) -> void:
	if not enemy.alive:
		return

	var kind := StringName(effect_def["kind"])
	var duration: float = effect_def["duration"]
	var magnitude: float = effect_def.get("magnitude", 0.0)
	var damage_type := StringName(effect_def.get("damage_type", ""))

	var existing := _find(enemy, kind, source)
	if existing != null:
		existing.remaining = maxf(existing.remaining, duration)
		existing.magnitude = magnitude
		existing.damage_type = damage_type
		return

	var effect: StatusEffect = _pool.acquire()
	effect.reset()
	effect.kind = kind
	effect.source = source
	effect.magnitude = magnitude
	effect.damage_type = damage_type
	effect.remaining = duration
	enemy.active_effects.append(effect)

func _find(enemy: Enemy, kind: StringName, source: StringName) -> StatusEffect:
	for effect: StatusEffect in enemy.active_effects:
		if effect.kind == kind and effect.source == source:
			return effect
	return null
```

- [ ] **Step 4: 執行測試確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_status_system.gd
```

Expected: 7 個測試全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add core/systems/status_system.gd core/systems/status_system.gd.uid tests/core/test_status_system.gd tests/core/test_status_system.gd.uid
git commit -m "feat(core): 新增 StatusSystem 的效果施加與堆疊規則"
```

---

### Task 5: StatusSystem — 衍生值重算

**Files:**
- Modify: `core/systems/status_system.gd`
- Modify: `tests/core/test_status_system.gd`

**Interfaces:**
- Consumes: Task 4 的 `StatusSystem.apply`
- Produces: `StatusSystem.recompute(enemy: Enemy) -> void`

每種 `kind` 取所有生效效果中**最強的一個，只套用一次**——不是相加。

- [ ] **Step 1: 寫失敗的測試**

在 `tests/core/test_status_system.gd` 末端加入：

```gdscript
func test_slow_reduces_derived_speed_without_touching_base() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.recompute(enemy)
	assert_float(enemy.speed).is_equal_approx(65.0, 0.001)     # 100 × (1 − 0.35)
	assert_float(enemy.base_speed).override_failure_message(
		"基礎值絕對不得被狀態效果寫入，否則效果到期後無法還原"
	).is_equal_approx(100.0, 0.001)

func test_strongest_slow_wins_and_slows_are_not_summed() -> void:
	# 0.35 與 0.60 相加會是 0.95，取最強應為 0.60
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.apply(enemy, DEEP_CHILL, &"ice_mage_tower")
	_system.recompute(enemy)
	assert_float(enemy.speed).override_failure_message(
		"不同來源的減速取最強，不相加"
	).is_equal_approx(40.0, 0.001)                              # 100 × (1 − 0.60)

func test_stun_zeroes_speed_and_overrides_slow() -> void:
	var enemy := _make_enemy()
	var stun := {"id": "stun_shock", "kind": "stun", "duration": 1.0}
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.apply(enemy, stun, &"shock_tower")
	_system.recompute(enemy)
	assert_float(enemy.speed).is_equal_approx(0.0, 0.001)
	assert_bool(enemy.stunned).is_true()

func test_armor_break_reduces_armor() -> void:
	var enemy := _make_enemy()
	var sunder := {"id": "sunder", "kind": "armor_break", "magnitude": 0.15, "duration": 5.0}
	_system.apply(enemy, sunder, &"sunder_tower")
	_system.recompute(enemy)
	assert_float(enemy.armor).is_equal_approx(0.05, 0.001)      # 0.2 − 0.15

func test_armor_break_cannot_push_armor_below_zero() -> void:
	var enemy := _make_enemy()
	var heavy_sunder := {"id": "heavy_sunder", "kind": "armor_break", "magnitude": 0.9, "duration": 5.0}
	_system.apply(enemy, heavy_sunder, &"sunder_tower")
	_system.recompute(enemy)
	assert_float(enemy.armor).override_failure_message(
		"護甲不得為負，否則會變成傷害放大"
	).is_equal_approx(0.0, 0.001)

func test_recompute_with_no_effects_restores_base_values() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.recompute(enemy)
	enemy.active_effects.clear()
	_system.recompute(enemy)
	assert_float(enemy.speed).is_equal_approx(100.0, 0.001)
	assert_bool(enemy.stunned).is_false()
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_status_system.gd
```

Expected: FAIL，`recompute` 方法不存在。

- [ ] **Step 3: 實作 recompute**

在 `core/systems/status_system.gd` 的 `apply` 之後加入：

```gdscript
## 依生效中的效果重算敵人的衍生數值。
## 每種 kind 取最強的一個，只套用一次——不相加。相加會讓多塔堆疊迅速失控。
func recompute(enemy: Enemy) -> void:
	enemy.reset_derived_stats()

	var strongest_slow := 0.0
	var strongest_armor_break := 0.0
	var has_stun := false

	for effect: StatusEffect in enemy.active_effects:
		match effect.kind:
			StatusEffect.KIND_SLOW:
				strongest_slow = maxf(strongest_slow, effect.magnitude)
			StatusEffect.KIND_STUN:
				has_stun = true
			StatusEffect.KIND_ARMOR_BREAK:
				strongest_armor_break = maxf(strongest_armor_break, effect.magnitude)
			StatusEffect.KIND_DOT:
				pass   # DoT 不影響衍生數值，在 tick 中結算傷害

	if has_stun:
		enemy.speed = 0.0
		enemy.stunned = true
	else:
		enemy.speed = enemy.base_speed * (1.0 - strongest_slow)

	enemy.armor = maxf(0.0, enemy.base_armor - strongest_armor_break)
```

- [ ] **Step 4: 執行測試確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_status_system.gd
```

Expected: 13 個測試全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add core/systems/status_system.gd tests/core/test_status_system.gd
git commit -m "feat(core): StatusSystem 依生效效果重算衍生數值"
```

---

### Task 6: StatusSystem — 持續時間與 DoT 結算

**Files:**
- Modify: `core/systems/status_system.gd`
- Modify: `tests/core/test_status_system.gd`

**Interfaces:**
- Consumes: Task 5 的 `recompute`
- Produces: `StatusSystem.tick(enemies: Array, delta: float) -> void`

單一入口，對每隻敵人依序做：推進持續時間、移除到期效果並歸還池、重算衍生值、結算 DoT。

- [ ] **Step 1: 寫失敗的測試**

在 `tests/core/test_status_system.gd` 末端加入：

```gdscript
func test_effect_expires_after_its_duration() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")     # duration 2.5
	_system.tick([enemy], 3.0)
	assert_array(enemy.active_effects).has_size(0)
	assert_float(enemy.speed).override_failure_message(
		"效果到期後速度必須回到基礎值"
	).is_equal_approx(100.0, 0.001)

func test_effect_survives_until_its_duration_elapses() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.tick([enemy], 1.0)
	assert_array(enemy.active_effects).has_size(1)
	assert_float(enemy.speed).is_equal_approx(65.0, 0.001)

func test_expired_effect_is_returned_to_the_pool() -> void:
	var pool := ObjectPool.new(func() -> StatusEffect: return StatusEffect.new(), 4)
	var system := StatusSystem.new(pool)
	var enemy := _make_enemy()
	system.apply(enemy, CHILL, &"frost_tower")
	assert_int(pool.free_count()).is_equal(3)
	system.tick([enemy], 3.0)
	assert_int(pool.free_count()).override_failure_message(
		"到期的效果實例必須歸還池中，否則池會逐漸耗盡"
	).is_equal(4)

func test_dot_deals_damage_scaled_by_delta() -> void:
	var enemy := _make_enemy()
	var poison := {"id": "poison", "kind": "dot", "magnitude": 10.0, "duration": 5.0, "damage_type": "true"}
	_system.apply(enemy, poison, &"poison_tower")
	_system.tick([enemy], 1.0)                      # 每秒 10 傷害 × 1 秒
	assert_float(enemy.hp).is_equal_approx(90.0, 0.001)

func test_dot_respects_damage_type() -> void:
	# 護甲 0.2 的敵人吃物理 DoT 應只受 80% 傷害，證明 DoT 走了 DamageSystem
	var enemy := _make_enemy()
	var bleed := {"id": "bleed", "kind": "dot", "magnitude": 10.0, "duration": 5.0, "damage_type": "physical"}
	_system.apply(enemy, bleed, &"blade_tower")
	_system.tick([enemy], 1.0)
	assert_float(enemy.hp).override_failure_message(
		"DoT 必須經過 DamageSystem，因此要吃護甲減免"
	).is_equal_approx(92.0, 0.001)                  # 100 − 10 × (1 − 0.2)

func test_dead_enemy_effects_are_not_ticked() -> void:
	var enemy := _make_enemy()
	var poison := {"id": "poison", "kind": "dot", "magnitude": 10.0, "duration": 5.0, "damage_type": "true"}
	_system.apply(enemy, poison, &"poison_tower")
	enemy.alive = false
	_system.tick([enemy], 1.0)
	assert_float(enemy.hp).is_equal_approx(100.0, 0.001)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_status_system.gd
```

Expected: FAIL，`tick` 方法不存在。

- [ ] **Step 3: 實作 tick**

在 `core/systems/status_system.gd` 末端加入：

```gdscript
## 每個邏輯 tick 呼叫一次，且必須排在 tick 迴圈的最前面——
## 否則後續所有系統讀到的都是上一 tick 的衍生值。
func tick(enemies: Array, delta: float) -> void:
	for enemy: Enemy in enemies:
		if not enemy.alive:
			continue
		_expire(enemy, delta)
		recompute(enemy)
		_apply_damage_over_time(enemy, delta)

## 推進剩餘時間，把到期的效果移出並歸還池中。
## 由後往前走訪，這樣原地移除不會跳過元素。
func _expire(enemy: Enemy, delta: float) -> void:
	for i in range(enemy.active_effects.size() - 1, -1, -1):
		var effect: StatusEffect = enemy.active_effects[i]
		effect.remaining -= delta
		if effect.remaining <= 0.0:
			enemy.active_effects.remove_at(i)
			_pool.release(effect)

## magnitude 是每秒傷害，因此乘上 delta。
## 一律經過 DamageSystem——這是硬規則第 2 條，DoT 不例外。
func _apply_damage_over_time(enemy: Enemy, delta: float) -> void:
	for effect: StatusEffect in enemy.active_effects:
		if effect.kind != StatusEffect.KIND_DOT:
			continue
		DamageSystem.apply(enemy, effect.magnitude * delta, effect.damage_type)
		if not enemy.alive:
			return
```

- [ ] **Step 4: 執行全套件確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 84 個測試全部 PASS（78 + 6 新增），exit 0。

- [ ] **Step 5: 提交**

```bash
git add core/systems/status_system.gd tests/core/test_status_system.gd
git commit -m "feat(core): StatusSystem 的持續時間到期與 DoT 結算"
```

---

### Task 7: 接入 tick 迴圈並釘住順序

**Files:**
- Modify: `core/sim/world_state.gd`
- Modify: `core/sim/battle_sim.gd`
- Create: `tests/core/test_tick_order.gd`

**Interfaces:**
- Consumes: `StatusSystem`
- Produces:
  - `WorldState.effect_pool: ObjectPool`
  - `WorldState.status_system: StatusSystem`
  - `WorldState.next_id() -> int`（供 Task 8 的投射物使用）
  - `BattleSim._tick()` 的第一步變為 `world.status_system.tick(...)`

最終 review 指出「把 `_tick()` 的五行任意重排，大部分測試仍會通過」。M1-A 把順序從五步增為七步，依賴更重，所以本任務同時補上守門測試。

- [ ] **Step 1: 寫失敗的測試**

Create `tests/core/test_tick_order.gd`:

```gdscript
extends GdUnitTestSuite

## 釘住 BattleSim._tick() 的步驟順序。
## 這些不變式沒有測試守著的話，任何一次重排都會靜默地改變遊戲行為。

const FRAME := 1.0 / 30.0
const PATH_ID := &"main"

func _make_world() -> WorldState:
	var world := WorldState.new()
	var points := PackedVector2Array([
		Vector2(0, 0), Vector2(200, 0), Vector2(400, 0), Vector2(600, 0),
	])
	world.paths[PATH_ID] = PathData.new(points, 200.0)
	world.gold = 0
	world.lives = 20
	return world

func _add_enemy(world: WorldState, speed: float) -> Enemy:
	var enemy := Enemy.new()
	enemy.enemy_id = &"orc_grunt"
	enemy.hp = 1000.0
	enemy.max_hp = 1000.0
	enemy.base_speed = speed
	enemy.bounty = 7
	enemy.path_id = PATH_ID
	enemy.reset_derived_stats()
	world.add_enemy(enemy)
	return enemy

func test_status_applied_this_tick_affects_movement_this_tick() -> void:
	# 證明 StatusSystem 排在 MovementSystem 之前。
	# 若順序相反，減速要到下一 tick 才生效，敵人這一 tick 會走滿速。
	var world := _make_world()
	var enemy := _add_enemy(world, 300.0)
	var sim := BattleSim.new(world)
	world.status_system.apply(enemy, {"id": "chill", "kind": "slow", "magnitude": 0.5, "duration": 5.0}, &"frost_tower")

	sim.advance(FRAME)

	var expected := 300.0 * 0.5 * BattleSim.TICK_DELTA
	assert_float(enemy.distance_along).override_failure_message(
		"這一 tick 施加的減速必須在同一 tick 就生效，代表 StatusSystem 排在 MovementSystem 之前"
	).is_equal_approx(expected, 0.001)

func test_killed_enemy_awards_bounty_exactly_once() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 0.0)
	enemy.hp = 1.0
	var sim := BattleSim.new(world)
	DamageSystem.apply(enemy, 999.0, DamageSystem.PHYSICAL)

	sim.advance(FRAME)
	sim.advance(FRAME)
	sim.advance(FRAME)

	assert_int(world.gold).override_failure_message(
		"被擊殺的敵人只能發一次賞金"
	).is_equal(7)

func test_leaked_enemy_awards_no_bounty() -> void:
	var world := _make_world()
	_add_enemy(world, 100000.0)      # 一 tick 就衝到終點
	var sim := BattleSim.new(world)

	sim.advance(FRAME)
	sim.advance(FRAME)

	assert_int(world.gold).override_failure_message(
		"走到終點的敵人不該給玩家賞金"
	).is_equal(0)
	assert_int(world.lives).is_equal(19)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_tick_order.gd
```

Expected: FAIL，`world.status_system` 不存在。

- [ ] **Step 3: 在 WorldState 加入池與系統**

在 `core/sim/world_state.gd` 的 `grid` 宣告後加入：

```gdscript
const EFFECT_POOL_CAPACITY := 64

## 狀態效果實例池與其系統。實例走池化，避免戰鬥迴圈中配置新物件。
var effect_pool := ObjectPool.new(func() -> StatusEffect: return StatusEffect.new(), EFFECT_POOL_CAPACITY)
var status_system := StatusSystem.new(effect_pool)
```

並在檔案末端加入：

```gdscript
## 配發一個全新的實體 id。敵人、塔、投射物共用同一個遞增計數器，
## 確保 id 在型別之間也不重複。
func next_id() -> int:
	var id := _next_entity_id
	_next_entity_id += 1
	return id
```

同時把 `add_enemy` 與 `add_tower` 裡的 id 配發改為呼叫 `next_id()`：

```gdscript
func add_enemy(enemy: Enemy) -> void:
	if enemy.id == 0:
		enemy.id = next_id()
	enemies.append(enemy)
	enemies_by_id[enemy.id] = enemy

func add_tower(tower: Tower) -> void:
	if tower.id == 0:
		tower.id = next_id()
	towers.append(tower)
```

- [ ] **Step 4: 改寫 BattleSim 的 tick 與賞金發放**

在 `core/sim/battle_sim.gd` 中，把 `_tick` 改為：

```gdscript
func _tick() -> void:
	tick_count += 1
	world.status_system.tick(world.enemies, TICK_DELTA)
	MovementSystem.tick(world.enemies, world.paths, TICK_DELTA)
	_collect_leaked()
	_rebuild_grid()
	_tick_towers()
	_remove_dead()
```

（`ProjectileSystem` 在 Task 10 才插入。）

把 `_tick_towers` 中的賞金發放刪除——刪掉這兩行：

```gdscript
		if not target.alive and not target.leaked:
			world.gold += target.bounty
```

並把 `_remove_dead` 改為：

```gdscript
## 死亡與洩漏的敵人移出集合，並在此處統一發放賞金。
## 傷害來源不只一處（塔、投射物、DoT），賞金邏輯若跟著複製會失去單一事實來源；
## 這裡本來就走訪所有死亡的敵人，且 leaked 旗標剛好能區分「被擊殺」與「走到終點」。
func _remove_dead() -> void:
	var survivors: Array[Enemy] = []
	for enemy: Enemy in world.enemies:
		if enemy.alive:
			survivors.append(enemy)
			continue
		if not enemy.leaked:
			world.gold += enemy.bounty
		_release_effects(enemy)
		world.enemies_by_id.erase(enemy.id)
	world.enemies = survivors

## 敵人離場時把它身上的效果實例歸還池中，否則池會逐漸耗盡。
func _release_effects(enemy: Enemy) -> void:
	for effect: StatusEffect in enemy.active_effects:
		world.effect_pool.release(effect)
	enemy.active_effects.clear()
```

- [ ] **Step 5: 執行全套件**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 87 個測試全部 PASS（84 + 3 新增），exit 0。既有的整合測試在此階段行為不變，因為塔仍是直接結算傷害。

- [ ] **Step 6: 驗證順序測試真的會咬人**

暫時把 `_tick` 中 `world.status_system.tick(...)` 那一行移到 `MovementSystem.tick(...)` 之後，重跑：

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_tick_order.gd
```

Expected: FAIL，訊息為「這一 tick 施加的減速必須在同一 tick 就生效……」。

確認後把順序改回來，重跑確認回到 PASS。**一個永遠不會失敗的順序守衛比沒有更糟。**

- [ ] **Step 7: 提交**

```bash
git add core/sim/world_state.gd core/sim/battle_sim.gd tests/core/test_tick_order.gd tests/core/test_tick_order.gd.uid
git commit -m "feat(core): StatusSystem 接入 tick 迴圈，賞金收斂至單一處"
```

---

### Task 8: Projectile 實體與世界狀態接線

**Files:**
- Create: `core/entities/projectile.gd`
- Modify: `core/sim/world_state.gd`

**Interfaces:**
- Consumes: `ObjectPool`、`WorldState.next_id()`
- Produces:
  - `Projectile` 欄位 `instance_id: int`、`active: bool`、`projectile_id: StringName`、`position: Vector2`、`target_id: int`、`speed: float`、`damage: float`、`damage_type: StringName`、`source_tower_id: StringName`、`on_hit_effects: Array[StringName]`、`splash_radius: float`，方法 `reset() -> void`
  - `WorldState.projectiles: Array[Projectile]`
  - `WorldState.projectile_pool: ObjectPool`

- [ ] **Step 1: 寫 Projectile**

Create `core/entities/projectile.gd`:

```gdscript
class_name Projectile
extends RefCounted

## 模擬層的投射物。追蹤目標且必中，傷害在命中那一 tick 才結算——
## 因此多座塔齊射一隻將死的敵人會浪費發數，這是塔防真實的策略層。

## 每次自池取出都配發全新號碼，即使物件本身被重複使用。
## 池化最常見的 bug 是 id 被回收後，表現層的舊 view 誤綁到新的投射物，
## 畫面上就會看到箭矢瞬移。一個遞增計數器即可根除整類問題。
var instance_id: int = 0

var active: bool = false
var projectile_id: StringName = &""     ## 視覺用
var position: Vector2 = Vector2.ZERO
var target_id: int = 0
var speed: float = 0.0                  ## 像素 / 秒
var damage: float = 0.0
var damage_type: StringName = &"physical"

## 命中時施加的狀態效果，以及它們的「來源」。
## 來源是發射者的 tower_id（塔的種類），見 StatusSystem 的堆疊規則。
var source_tower_id: StringName = &""
var on_hit_effects: Array[StringName] = []

var splash_radius: float = 0.0          ## 0 表示單體

func reset() -> void:
	instance_id = 0
	active = false
	projectile_id = &""
	position = Vector2.ZERO
	target_id = 0
	speed = 0.0
	damage = 0.0
	damage_type = &"physical"
	source_tower_id = &""
	on_hit_effects.clear()
	splash_radius = 0.0
```

- [ ] **Step 2: 在 WorldState 加入投射物集合與池**

在 `core/sim/world_state.gd` 的 `effect_pool` 宣告後加入：

```gdscript
const PROJECTILE_POOL_CAPACITY := 128

var projectiles: Array[Projectile] = []
var projectile_pool := ObjectPool.new(func() -> Projectile: return Projectile.new(), PROJECTILE_POOL_CAPACITY)
```

- [ ] **Step 3: 執行全套件確認未破壞既有行為**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 87 個測試全部 PASS，exit 0。本任務只新增結構，尚未有任何邏輯使用它。

- [ ] **Step 4: 提交**

```bash
git add core/entities/projectile.gd core/entities/projectile.gd.uid core/sim/world_state.gd
git commit -m "feat(core): 新增 Projectile 實體與投射物池"
```

---

### Task 9: ProjectileSystem — 飛行與單體命中

**Files:**
- Create: `core/systems/projectile_system.gd`
- Test: `tests/core/test_projectile_system.gd`

**Interfaces:**
- Consumes: `Projectile`、`Enemy`、`DamageSystem`、`WorldState`
- Produces:
  - `ProjectileSystem.new(world: WorldState) -> ProjectileSystem`
  - `ProjectileSystem.spawn(tower: Tower, target_id: int, projectile_speed: float, splash_radius: float, on_hit_effects: Array[StringName]) -> Projectile`
  - `ProjectileSystem.tick(delta: float) -> void`

命中條件為「到目標的距離 ≤ 本 tick 的移動距離」，保證不穿透且有限時間內必定命中。AoE 在 Task 11 加入，本任務只做單體。

- [ ] **Step 1: 寫失敗的測試**

Create `tests/core/test_projectile_system.gd`:

```gdscript
extends GdUnitTestSuite

const PATH_ID := &"main"

func _make_world() -> WorldState:
	var world := WorldState.new()
	var points := PackedVector2Array([Vector2(0, 0), Vector2(500, 0), Vector2(1000, 0)])
	world.paths[PATH_ID] = PathData.new(points, 500.0)
	return world

func _add_enemy(world: WorldState, pos: Vector2, hp: float) -> Enemy:
	var enemy := Enemy.new()
	enemy.enemy_id = &"orc_grunt"
	enemy.hp = hp
	enemy.max_hp = hp
	enemy.base_speed = 0.0
	enemy.path_id = PATH_ID
	enemy.position = pos
	enemy.reset_derived_stats()
	world.add_enemy(enemy)
	return enemy

func _make_tower(world: WorldState, pos: Vector2) -> Tower:
	var tower := Tower.new()
	tower.tower_id = &"archer_tower"
	tower.position = pos
	tower.damage = 20.0
	tower.damage_type = DamageSystem.PHYSICAL
	tower.attack_range = 500.0
	tower.fire_interval = 1.0
	world.add_tower(tower)
	return tower

func test_spawned_projectile_starts_at_the_tower() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, Vector2(300, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	var system := ProjectileSystem.new(world)
	var projectile := system.spawn(tower, enemy.id, 600.0, 0.0, [] as Array[StringName])
	assert_float(projectile.position.x).is_equal_approx(0.0, 0.001)
	assert_array(world.projectiles).has_size(1)

func test_projectile_moves_toward_its_target() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, Vector2(300, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	var system := ProjectileSystem.new(world)
	var projectile := system.spawn(tower, enemy.id, 600.0, 0.0, [] as Array[StringName])
	system.tick(0.1)                       # 移動 60 像素
	assert_float(projectile.position.x).is_equal_approx(60.0, 0.001)

func test_damage_is_dealt_on_impact_not_on_spawn() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, Vector2(300, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	var system := ProjectileSystem.new(world)
	system.spawn(tower, enemy.id, 600.0, 0.0, [] as Array[StringName])
	system.tick(0.1)
	assert_float(enemy.hp).override_failure_message(
		"投射物尚未命中，不得結算傷害"
	).is_equal_approx(100.0, 0.001)
	system.tick(0.5)                       # 足以走完剩下的距離
	assert_float(enemy.hp).is_equal_approx(80.0, 0.001)

func test_projectile_is_released_after_hitting() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, Vector2(60, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	var system := ProjectileSystem.new(world)
	system.spawn(tower, enemy.id, 600.0, 0.0, [] as Array[StringName])
	system.tick(0.5)
	assert_array(world.projectiles).has_size(0)

func test_projectile_vanishes_when_target_dies_mid_flight() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, Vector2(500, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	var system := ProjectileSystem.new(world)
	system.spawn(tower, enemy.id, 100.0, 0.0, [] as Array[StringName])
	system.tick(0.1)
	enemy.alive = false
	system.tick(0.1)
	assert_array(world.projectiles).override_failure_message(
		"目標消失後投射物應直接歸還池中，傷害不轉移"
	).has_size(0)

func test_each_spawn_gets_a_fresh_instance_id() -> void:
	# 池會重複使用同一個物件，但 id 必須每次都不同，
	# 否則表現層的舊 view 可能誤綁到新的投射物
	var world := _make_world()
	var enemy := _add_enemy(world, Vector2(60, 0), 1000.0)
	var tower := _make_tower(world, Vector2(0, 0))
	var system := ProjectileSystem.new(world)
	var first := system.spawn(tower, enemy.id, 600.0, 0.0, [] as Array[StringName])
	var first_id := first.instance_id
	system.tick(0.5)                       # 命中並歸還
	var second := system.spawn(tower, enemy.id, 600.0, 0.0, [] as Array[StringName])
	assert_int(second.instance_id).override_failure_message(
		"重複使用的投射物必須取得全新的 instance_id"
	).is_greater(first_id)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_projectile_system.gd
```

Expected: FAIL，識別字 `ProjectileSystem` 未定義。

- [ ] **Step 3: 寫 ProjectileSystem**

Create `core/systems/projectile_system.gd`:

```gdscript
class_name ProjectileSystem
extends RefCounted

## 投射物的生成、飛行與命中結算。
##
## 追蹤且必中：每 tick 朝目標「當前」座標移動，當本 tick 的移動距離足以走到目標時命中。
## 這個判定保證不會穿透，且只要投射物速度高於敵人速度就必定在有限時間內命中
## （該條件由資料完整性測試把關）。

var _world: WorldState

func _init(world: WorldState) -> void:
	_world = world

## 自池取得一個投射物並初始化。生成位置為發射它的塔。
func spawn(
	tower: Tower,
	target_id: int,
	projectile_speed: float,
	splash_radius: float,
	on_hit_effects: Array[StringName]
) -> Projectile:
	var projectile: Projectile = _world.projectile_pool.acquire()
	projectile.reset()
	projectile.instance_id = _world.next_id()
	projectile.active = true
	projectile.position = tower.position
	projectile.target_id = target_id
	projectile.speed = projectile_speed
	projectile.damage = tower.damage
	projectile.damage_type = tower.damage_type
	projectile.source_tower_id = tower.tower_id
	projectile.splash_radius = splash_radius
	projectile.on_hit_effects.assign(on_hit_effects)
	_world.projectiles.append(projectile)
	return projectile

func tick(delta: float) -> void:
	# 由後往前走訪，這樣原地移除不會跳過元素，也不必重建陣列
	for i in range(_world.projectiles.size() - 1, -1, -1):
		var projectile: Projectile = _world.projectiles[i]
		var target: Enemy = _world.enemies_by_id.get(projectile.target_id)

		if target == null or not target.alive or target.leaked:
			_despawn(i)
			continue

		var to_target := target.position - projectile.position
		var step := projectile.speed * delta
		if to_target.length() <= step:
			projectile.position = target.position
			_on_impact(projectile, target)
			_despawn(i)
			continue

		projectile.position += to_target.normalized() * step

## 命中結算。傷害一律經過 DamageSystem，此處不做任何減免計算。
func _on_impact(projectile: Projectile, target: Enemy) -> void:
	DamageSystem.apply(target, projectile.damage, projectile.damage_type)

func _despawn(index: int) -> void:
	var projectile: Projectile = _world.projectiles[index]
	projectile.active = false
	_world.projectiles.remove_at(index)
	_world.projectile_pool.release(projectile)
```

- [ ] **Step 4: 執行測試確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_projectile_system.gd
```

Expected: 6 個測試全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add core/systems/projectile_system.gd core/systems/projectile_system.gd.uid tests/core/test_projectile_system.gd tests/core/test_projectile_system.gd.uid
git commit -m "feat(core): 新增 ProjectileSystem 的飛行與單體命中"
```

---

### Task 10: 塔改為發射投射物，並重新推導既有整合測試

本任務改變遊戲行為：傷害從「開火即結算」變成「命中才結算」。既有的兩個整合測試期望值會變，**必須重新推導，不得把數字改成實際跑出來的值**。

**Files:**
- Modify: `core/sim/battle_sim.gd`
- Modify: `data/towers/archer_tower.json`
- Modify: `tests/core/test_battle_integration.gd`
- Modify: `tests/test_data_integrity.gd`

**Interfaces:**
- Consumes: `ProjectileSystem`
- Produces:
  - `WorldState.projectile_system: ProjectileSystem`
  - 塔資料每一級新增 `projectile_speed`、`splash_radius`、`on_hit_effects`

- [ ] **Step 1: 為塔資料補上投射物參數**

Replace `data/towers/archer_tower.json`:

```json
{
  "id": "archer_tower",
  "name_key": "tower.archer_tower.name",
  "damage_type": "physical",
  "levels": [
    {"cost": 70,  "damage": 9.0,  "attack_range": 180.0, "fire_interval": 0.8,  "projectile_speed": 600.0, "splash_radius": 0.0, "on_hit_effects": []},
    {"cost": 130, "damage": 14.0, "attack_range": 190.0, "fire_interval": 0.75, "projectile_speed": 600.0, "splash_radius": 0.0, "on_hit_effects": []},
    {"cost": 220, "damage": 22.0, "attack_range": 200.0, "fire_interval": 0.7,  "projectile_speed": 600.0, "splash_radius": 0.0, "on_hit_effects": []}
  ],
  "sprite": "res://game/assets/placeholder_tower.png"
}
```

- [ ] **Step 2: 擴充完整性測試**

在 `tests/test_data_integrity.gd` 末端加入：

```gdscript
func test_every_tower_level_declares_projectile_fields() -> void:
	var required := ["projectile_speed", "splash_radius", "on_hit_effects"]
	for tower_id: StringName in _registry.towers:
		for level_def: Dictionary in _registry.towers[tower_id]["levels"]:
			for field: String in required:
				assert_bool(level_def.has(field)).override_failure_message(
					"塔 %s 的某個等級缺少投射物欄位 %s" % [tower_id, field]
				).is_true()

func test_projectiles_outrun_every_enemy() -> void:
	# 命中保證的前提：投射物速度必須高於所有敵人，否則追不上
	var fastest_enemy := 0.0
	for enemy_id: StringName in _registry.enemies:
		fastest_enemy = maxf(fastest_enemy, _registry.enemies[enemy_id]["speed"])
	for tower_id: StringName in _registry.towers:
		for level_def: Dictionary in _registry.towers[tower_id]["levels"]:
			assert_float(level_def["projectile_speed"]).override_failure_message(
				"塔 %s 的投射物速度必須高於最快的敵人（%.1f），否則永遠追不上" % [tower_id, fastest_enemy]
			).is_greater(fastest_enemy)

func test_tower_on_hit_effects_reference_existing_effects() -> void:
	for tower_id: StringName in _registry.towers:
		for level_def: Dictionary in _registry.towers[tower_id]["levels"]:
			for effect_id in level_def["on_hit_effects"]:
				assert_bool(_registry.status_effects.has(StringName(effect_id))).override_failure_message(
					"塔 %s 引用了不存在的狀態效果 %s" % [tower_id, effect_id]
				).is_true()
```

- [ ] **Step 3: 把 ProjectileSystem 接進 WorldState 與 tick**

在 `core/sim/world_state.gd` 的 `projectile_pool` 宣告後加入：

```gdscript
var projectile_system: ProjectileSystem = null   ## 由 BattleSim 於建構時注入
```

在 `core/sim/battle_sim.gd` 的 `_init` 末端加入：

```gdscript
	world.projectile_system = ProjectileSystem.new(world)
```

把 `_tick` 改為：

```gdscript
func _tick() -> void:
	tick_count += 1
	world.status_system.tick(world.enemies, TICK_DELTA)
	MovementSystem.tick(world.enemies, world.paths, TICK_DELTA)
	_collect_leaked()
	_rebuild_grid()
	world.projectile_system.tick(TICK_DELTA)
	_tick_towers()
	_remove_dead()
```

`ProjectileSystem` 排在 `_tick_towers` 之前，這樣塔這一 tick 生成的投射物要等下一 tick 才開始飛。順序相反的話飛行時間會少一 tick。

- [ ] **Step 4: 讓塔發射而非直接結算**

把 `core/sim/battle_sim.gd` 的 `_tick_towers` 改為：

```gdscript
## 塔只負責發射，不再認識傷害結算。
## DamageSystem 的呼叫點因此收斂為兩處：投射物命中、DoT 結算，兩處都在系統層。
func _tick_towers() -> void:
	for tower: Tower in world.towers:
		tower.cooldown = maxf(0.0, tower.cooldown - TICK_DELTA)
		tower.target_id = TargetingSystem.find_first(tower, world.grid, world.enemies_by_id)
		if tower.target_id == 0 or tower.cooldown > 0.0:
			continue
		world.projectile_system.spawn(
			tower,
			tower.target_id,
			tower.projectile_speed,
			tower.splash_radius,
			tower.on_hit_effects
		)
		tower.cooldown = tower.fire_interval
```

在 `core/entities/tower.gd` 的 `target_id` 之後加入三個欄位：

```gdscript
var projectile_speed: float = 600.0     ## 像素 / 秒
var splash_radius: float = 0.0          ## 0 表示單體
var on_hit_effects: Array[StringName] = []
```

- [ ] **Step 5: 重新推導既有整合測試的期望值**

`tests/core/test_battle_integration.gd` 中的 `_add_tower` 補上新欄位：

```gdscript
	tower.projectile_speed = 600.0
	tower.splash_radius = 0.0
```

接著處理 `test_fire_interval_limits_shots`。**推導過程如下，請照著算，不要用實際輸出反推：**

- 塔在 `(50, 0)`，敵人在 `(50, 0)`，距離為 0
- 投射物於 tick N 生成，位置與塔相同；`ProjectileSystem` 排在 `_tick_towers` 之前，故該投射物於 tick N+1 才被處理
- tick N+1 時距離 0 ≤ 任何移動距離，立即命中
- 因此每一發的傷害延後 **恰好一個 tick**
- 原本 1 秒（30 tick）內命中兩發、剩餘 hp 980.0；延後一 tick 後，第二發於 tick 17 命中，仍在 30 tick 內
- **結論：期望值不變，仍為 980.0**

把該測試的註解更新為說明這個推導，斷言維持 `is_equal_approx(980.0, 0.001)`。

再處理 `test_shipped_data_lets_one_tower_kill_one_enemy`。該測試以「敵人死亡且未洩漏」為斷言，沒有寫死時間，因此**期望值不變**。但飛行時間會讓擊殺變晚，需確認 90 秒的上限仍然足夠：敵人在射程內約 15.4 秒、需 17 發、射速 0.8 秒，總計約 13.6 秒，加上每發約 0.03 秒的飛行延遲（距離短、速度 600），影響不到 1 秒。**上限充足，不需調整。**

- [ ] **Step 6: 寫過度打擊測試**

在 `tests/core/test_battle_integration.gd` 末端加入：

```gdscript
func test_overkill_wastes_shots_because_damage_lands_on_impact() -> void:
	# 兩座塔同時對一隻將死的敵人開火，第二發必須落空。
	# 這個測試直接釘住「傷害在命中時結算」的設計決定——
	# 若有人改回發射即結算，第二發會照樣扣血，測試立刻失敗。
	var world := _make_world()
	var enemy := _add_enemy(world, 15.0, 0.0, 5)
	enemy.position = Vector2(50, 0)
	_add_tower(world, Vector2(50, 0), 10.0, 5.0)
	_add_tower(world, Vector2(50, 0), 10.0, 5.0)
	var sim := BattleSim.new(world)

	_run(sim, 1.0)

	assert_int(world.gold).override_failure_message(
		"敵人應被擊殺並發放一次賞金"
	).is_equal(5)
	assert_array(world.projectiles).override_failure_message(
		"目標死亡後，仍在飛的投射物必須消失而非轉移目標"
	).has_size(0)
```

- [ ] **Step 7: 補上投射物的順序守衛**

設計規格 §6.2 要求 `test_tick_order.gd` 涵蓋「這一 tick 生成的投射物，這一 tick 不得移動」。Task 7 建立該檔時投射物尚不存在，現在補上。

在 `tests/core/test_tick_order.gd` 末端加入：

```gdscript
func test_projectile_spawned_this_tick_does_not_move_this_tick() -> void:
	# 證明 ProjectileSystem 排在 _tick_towers 之前。
	# 若順序相反，投射物會在生成的同一 tick 就移動一格，每一發的飛行時間都少一 tick。
	var world := _make_world()
	_add_enemy(world, 0.0)                 # 停在路徑起點 (0, 0)

	var tower := Tower.new()
	tower.tower_id = &"archer_tower"
	tower.position = Vector2(100, 0)
	tower.damage = 1.0
	tower.damage_type = DamageSystem.PHYSICAL
	tower.attack_range = 1000.0
	tower.fire_interval = 10.0             # 只讓它開一發
	tower.projectile_speed = 600.0
	world.add_tower(tower)

	var sim := BattleSim.new(world)
	sim.advance(FRAME)

	assert_array(world.projectiles).has_size(1)
	assert_float(world.projectiles[0].position.x).override_failure_message(
		"這一 tick 生成的投射物不得在同一 tick 移動，代表 ProjectileSystem 排在 _tick_towers 之前"
	).is_equal_approx(100.0, 0.001)
```

- [ ] **Step 8: 執行全套件**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 全部 PASS，exit 0。

**若 `test_fire_interval_limits_shots` 失敗，不要修改期望值**——回到 Step 5 的推導，找出實際行為與推導不符的原因。推導錯了就修正推導並說明；實作錯了就修實作。把數字改成實際輸出會讓這個測試變成行為的複印機。

- [ ] **Step 9: 提交**

```bash
git add core/sim/battle_sim.gd core/sim/world_state.gd core/entities/tower.gd \
        data/towers/archer_tower.json tests/core/test_battle_integration.gd \
        tests/core/test_tick_order.gd tests/test_data_integrity.gd
git commit -m "feat(core): 塔改為發射投射物，傷害於命中時結算"
```

---

### Task 11: AoE 範圍傷害

**Files:**
- Modify: `core/systems/projectile_system.gd`
- Modify: `tests/core/test_projectile_system.gd`

**Interfaces:**
- Consumes: `UniformGrid.query_radius`
- Produces: `ProjectileSystem._on_impact` 支援 `splash_radius > 0`

範圍內一律全額傷害，不做距離衰減。空間索引由 `_rebuild_grid()` 在同一 tick 稍早建好。

- [ ] **Step 1: 寫失敗的測試**

在 `tests/core/test_projectile_system.gd` 末端加入：

```gdscript
func test_splash_damages_every_enemy_in_radius() -> void:
	var world := _make_world()
	var primary := _add_enemy(world, Vector2(60, 0), 100.0)
	var nearby := _add_enemy(world, Vector2(90, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	# ProjectileSystem 用的是 grid，測試中需自行建好
	world.grid.clear()
	world.grid.insert(primary.id, primary.position)
	world.grid.insert(nearby.id, nearby.position)

	var system := ProjectileSystem.new(world)
	system.spawn(tower, primary.id, 600.0, 50.0, [] as Array[StringName])
	system.tick(0.5)

	assert_float(primary.hp).is_equal_approx(80.0, 0.001)
	assert_float(nearby.hp).override_failure_message(
		"半徑內的敵人必須受到全額傷害，不做距離衰減"
	).is_equal_approx(80.0, 0.001)

func test_splash_spares_enemies_outside_the_radius() -> void:
	var world := _make_world()
	var primary := _add_enemy(world, Vector2(60, 0), 100.0)
	var distant := _add_enemy(world, Vector2(400, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	world.grid.clear()
	world.grid.insert(primary.id, primary.position)
	world.grid.insert(distant.id, distant.position)

	var system := ProjectileSystem.new(world)
	system.spawn(tower, primary.id, 600.0, 50.0, [] as Array[StringName])
	system.tick(0.5)

	assert_float(distant.hp).is_equal_approx(100.0, 0.001)

func test_single_target_projectile_does_not_splash() -> void:
	var world := _make_world()
	var primary := _add_enemy(world, Vector2(60, 0), 100.0)
	var nearby := _add_enemy(world, Vector2(70, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	world.grid.clear()
	world.grid.insert(primary.id, primary.position)
	world.grid.insert(nearby.id, nearby.position)

	var system := ProjectileSystem.new(world)
	system.spawn(tower, primary.id, 600.0, 0.0, [] as Array[StringName])
	system.tick(0.5)

	assert_float(nearby.hp).override_failure_message(
		"splash_radius 為 0 時只能打到主目標"
	).is_equal_approx(100.0, 0.001)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_projectile_system.gd
```

Expected: `test_splash_damages_every_enemy_in_radius` FAIL——目前只打主目標。

- [ ] **Step 3: 實作 AoE**

把 `core/systems/projectile_system.gd` 的 `_on_impact` 改為：

```gdscript
## 命中結算。傷害一律經過 DamageSystem，此處不做任何減免計算。
## 範圍內全額傷害，不做距離衰減——衰減會讓數值難以推理。
func _on_impact(projectile: Projectile, target: Enemy) -> void:
	if projectile.splash_radius <= 0.0:
		DamageSystem.apply(target, projectile.damage, projectile.damage_type)
		return

	# grid 是 broad phase，回傳的候選需自行做精確距離判定
	var radius_squared := projectile.splash_radius * projectile.splash_radius
	for candidate_id in _world.grid.query_radius(projectile.position, projectile.splash_radius):
		var enemy: Enemy = _world.enemies_by_id.get(candidate_id)
		if enemy == null or not enemy.alive or enemy.leaked:
			continue
		if projectile.position.distance_squared_to(enemy.position) > radius_squared:
			continue
		DamageSystem.apply(enemy, projectile.damage, projectile.damage_type)
```

- [ ] **Step 4: 執行全套件確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 全部 PASS，exit 0。

- [ ] **Step 5: 提交**

```bash
git add core/systems/projectile_system.gd tests/core/test_projectile_system.gd
git commit -m "feat(core): 投射物支援範圍傷害"
```

---

### Task 12: 命中時施加狀態效果與端到端驗證

最後一塊：把投射物與狀態效果接起來，並證明整條鏈在真實資料下可運作。

**Files:**
- Modify: `core/systems/projectile_system.gd`
- Modify: `core/data/data_registry.gd`
- Modify: `tests/core/test_projectile_system.gd`
- Modify: `tests/core/test_battle_integration.gd`

**Interfaces:**
- Consumes: `StatusSystem.apply`、`DataRegistry.status_effects`
- Produces: `ProjectileSystem` 命中時對受擊者施加 `on_hit_effects`

- [ ] **Step 1: 寫失敗的測試**

在 `tests/core/test_projectile_system.gd` 末端加入：

```gdscript
func test_on_hit_effect_is_applied_to_the_target() -> void:
	var world := _make_world()
	world.effect_defs[&"chill"] = {"id": "chill", "kind": "slow", "magnitude": 0.5, "duration": 3.0}
	var enemy := _add_enemy(world, Vector2(60, 0), 100.0)
	enemy.base_speed = 100.0
	enemy.reset_derived_stats()
	var tower := _make_tower(world, Vector2(0, 0))

	var system := ProjectileSystem.new(world)
	system.spawn(tower, enemy.id, 600.0, 0.0, [&"chill"] as Array[StringName])
	system.tick(0.5)

	assert_array(enemy.active_effects).has_size(1)
	world.status_system.recompute(enemy)
	assert_float(enemy.speed).override_failure_message(
		"命中後施加的減速必須反映在衍生速度上"
	).is_equal_approx(50.0, 0.001)

func test_splash_applies_effects_to_everyone_hit() -> void:
	var world := _make_world()
	world.effect_defs[&"chill"] = {"id": "chill", "kind": "slow", "magnitude": 0.5, "duration": 3.0}
	var primary := _add_enemy(world, Vector2(60, 0), 100.0)
	var nearby := _add_enemy(world, Vector2(90, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	world.grid.clear()
	world.grid.insert(primary.id, primary.position)
	world.grid.insert(nearby.id, nearby.position)

	var system := ProjectileSystem.new(world)
	system.spawn(tower, primary.id, 600.0, 50.0, [&"chill"] as Array[StringName])
	system.tick(0.5)

	assert_array(nearby.active_effects).has_size(1)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_projectile_system.gd
```

Expected: FAIL，`world.effect_defs` 不存在。

- [ ] **Step 3: 讓 WorldState 持有效果定義**

在 `core/sim/world_state.gd` 的 `paths` 宣告後加入：

```gdscript
## 狀態效果的 JSON 定義，由表現層在載入關卡時自 DataRegistry 灌入。
## core/ 不自行讀檔，維持可在無檔案系統的情況下被測試。
var effect_defs: Dictionary = {}   ## StringName -> Dictionary
```

- [ ] **Step 4: 在命中時施加效果**

把 `core/systems/projectile_system.gd` 的 `_on_impact` 改為：

```gdscript
func _on_impact(projectile: Projectile, target: Enemy) -> void:
	if projectile.splash_radius <= 0.0:
		_hit_one(projectile, target)
		return

	var radius_squared := projectile.splash_radius * projectile.splash_radius
	for candidate_id in _world.grid.query_radius(projectile.position, projectile.splash_radius):
		var enemy: Enemy = _world.enemies_by_id.get(candidate_id)
		if enemy == null or not enemy.alive or enemy.leaked:
			continue
		if projectile.position.distance_squared_to(enemy.position) > radius_squared:
			continue
		_hit_one(projectile, enemy)

## 對單一敵人結算傷害並施加命中效果。
## 傷害一律經過 DamageSystem；效果的「來源」是發射塔的種類，決定堆疊時是刷新還是並存。
func _hit_one(projectile: Projectile, enemy: Enemy) -> void:
	DamageSystem.apply(enemy, projectile.damage, projectile.damage_type)
	for effect_id in projectile.on_hit_effects:
		var def: Dictionary = _world.effect_defs.get(effect_id, {})
		if def.is_empty():
			push_error("投射物引用了不存在的狀態效果: %s" % effect_id)
			continue
		_world.status_system.apply(enemy, def, projectile.source_tower_id)
```

- [ ] **Step 5: 執行全套件**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 全部 PASS，exit 0。

- [ ] **Step 6: 寫端到端測試**

在 `tests/core/test_battle_integration.gd` 末端加入：

```gdscript
func test_shipped_data_drives_a_full_projectile_and_status_chain() -> void:
	# 端到端：用真實 JSON 資料，塔發射投射物、命中、造成傷害並施加減速。
	# 不寫死任何平衡數字，全部從 registry 讀，數值調整時不需修改本測試。
	var registry := DataRegistry.new()
	registry.load_from_disk()

	var world := _make_world()
	world.effect_defs = registry.status_effects

	var enemy := registry.make_enemy(&"orc_grunt", PATH_ID)
	enemy.position = Vector2(50, 0)
	world.add_enemy(enemy)

	var tower_def: Dictionary = registry.towers[&"archer_tower"]
	var level_def: Dictionary = tower_def["levels"][0]
	var tower := Tower.new()
	tower.tower_id = &"archer_tower"
	tower.position = Vector2(50, 0)
	tower.damage = level_def["damage"]
	tower.damage_type = StringName(tower_def["damage_type"])
	tower.attack_range = level_def["attack_range"]
	tower.fire_interval = level_def["fire_interval"]
	tower.projectile_speed = level_def["projectile_speed"]
	tower.splash_radius = level_def["splash_radius"]
	tower.on_hit_effects.assign([&"chill"])
	world.add_tower(tower)

	var sim := BattleSim.new(world)
	_run(sim, 2.0)

	assert_bool(enemy.hp < enemy.max_hp).override_failure_message(
		"塔應已透過投射物對敵人造成傷害"
	).is_true()
	assert_array(enemy.active_effects).override_failure_message(
		"命中應施加 on_hit_effects 中的減速"
	).has_size(1)
	assert_bool(enemy.speed < enemy.base_speed).override_failure_message(
		"減速必須反映在衍生速度上，且基礎值不得被改動"
	).is_true()
	assert_float(enemy.base_speed).override_failure_message(
		"基礎速度必須維持 JSON 中的原值"
	).is_equal_approx(registry.enemies[&"orc_grunt"]["speed"], 0.001)
```

比較用 `assert_bool(a < b).is_true()` 而非 `is_less`——後者不在本專案已驗證可用的斷言清單中。

- [ ] **Step 7: 執行全套件並確認 core 純淨度**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 全部 PASS，exit 0，其中包含 `tests/test_core_purity.gd`——新增的四個 `core/` 檔案都不得引入 Node 依賴。

- [ ] **Step 8: 提交**

```bash
git add core/systems/projectile_system.gd core/sim/world_state.gd tests/core/
git commit -m "feat(core): 投射物命中時施加狀態效果，補上端到端測試"
```

---

## M1-A 完成後

交付物：投射物進入模擬層並帶來過度打擊的策略層、投射物與效果實例走物件池、四種狀態效果可用、tick 順序有測試守門。

尚未處理、已知的後續工作：

| 項目 | 去向 |
|---|---|
| 表現層的投射物 view 與插值 | M1-B（輸入與 HUD） |
| 士兵攔截（`Enemy.blocked_by`） | M1-C |
| 波次系統與 `paused` / `speed_multiplier` 未被 `game/` 讀取（最終 review 的 N2） | M1-D |
| `cooldown` 浮點累減的射速邊界（N3） | M1-D 或 M2 |
| 系統內部暫存陣列的配置（N4）、敵人池化 | M2，須先有實機數據 |
| `PROJECTILE_POOL_CAPACITY = 128` 的實際峰值 | M2 實機驗證 |
