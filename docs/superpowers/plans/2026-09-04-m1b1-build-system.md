# M1-B1 建塔系統 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓玩家能在關卡的建塔點上建造、升級、賣出塔，金錢正確結算，且所有指令都在固定步長的 tick 內套用。

**Architecture:** 指令做成 `GameIntent` 排入 `WorldState` 的佇列，由 `BattleSim` 在 tick 的**第一步**排空並交給 `BuildSystem` 結算。這讓所有改變世界的事情都發生在 tick 內的明確位置，代價是最多一個 tick（約 33 毫秒）的延遲。建塔點以場景中的 `Marker2D` 標示，載入時烘焙成純資料交給 `core/`——與 `Path2D → PathData` 同一模式。

**Tech Stack:** Godot 4.7.2、GDScript、GdUnit4 6.2.1。

## Global Constraints

出自 `docs/superpowers/specs/2026-09-04-tower-defense-architecture-design.md` 與 B1 設計規格。**每個任務的要求都隱含包含本節。**

- 只使用 Godot 4.x API。禁用 `KinematicBody2D`、`yield`、`export var`。
- 只使用 GDScript，不引入 C#。
- `core/` 不得 import 任何 Node 或引擎場景類別，也不得讀檔。允許 `FileAccess`、`DirAccess`、`JSON`、`Vector2`。所有新類別 `extends RefCounted`。由 `tests/test_core_purity.gd` 自動驗證。
- 傷害一律經過 `DamageSystem.apply()`。
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

`--ignoreHeadlessMode` 為必要旗標，缺少時 GdUnit4 直接 exit 103 不執行任何測試。**優先跑全套件**——單檔執行會在第一個失敗就停下，會誤導判斷。

新增 `class_name` 後執行 `godot --headless --path . --import` 重建全域類別快取。該指令即使成功也可能回傳非零結束碼，以輸出內容判斷。

`JSON.parse_string()` 一律把數字解析成 `float`，需要整數時必須明確轉換。

### 已驗證可用的斷言

只使用這些形式：`assert_int(x).is_equal(y)`、`assert_float(x).is_equal_approx(y, eps)`、`assert_bool(x).is_true()/.is_false()`、`assert_str(s).contains(...)`、`assert_str(s).is_equal(...)`、`assert_array(a).has_size(n)/.contains([...])`、`assert_int(x).is_greater(n)`、`assert_float(x).is_greater(n)`、`assert_float(x).is_between(lo, hi)`，以及鏈在最終斷言前的 `.override_failure_message("...")`。**沒有 `is_less`**，大小比較寫成 `assert_bool(a < b).is_true()`。

### 起始狀態

`main` 為 `5f033fc`，測試 127/127，14 個 suite。

---

## File Structure

| 檔案 | 責任 |
|---|---|
| `core/entities/game_intent.gd` | 新增：玩家意圖，含三個建構捷徑 |
| `core/entities/build_slot.gd` | 新增：建塔點 |
| `core/systems/build_system.gd` | 新增：建造／升級／賣出的唯一結算入口 |
| `core/sim/world_state.gd` | 修改：建塔點集合、意圖佇列、塔定義、可用塔種、`configure_for_level` |
| `core/sim/battle_sim.gd` | 修改：tick 第一步排空意圖佇列 |
| `core/data/data_registry.gd` | 修改：載入 `data/levels/` |
| `data/levels/level_01/meta.json` | 新增：起始資源、退款比例、可用塔種 |
| `game/level/battle_scene.tscn` | 修改：加入 `BuildSlots` 節點與 `Marker2D` 子節點 |
| `game/level/battle_scene.gd` | 修改：烘焙建塔點、改呼叫 `configure_for_level`、過渡的自動建塔 |
| `tests/core/test_build_system.gd` | 新增 |
| `tests/core/test_tick_order.gd` | 修改：意圖於 tick 第一步套用 |
| `tests/core/test_battle_integration.gd` | 修改：更名連帶影響的守衛測試 |
| `tests/test_data_integrity.gd` | 修改：關卡 meta 的檢查 |
| `tests/test_core_purity.gd` | 修改：接線守衛改抓新名稱 |

`MovementSystem`、`TargetingSystem`、`DamageSystem`、`ProjectileSystem`、`StatusSystem`、`UniformGrid`、`PathData`、`ObjectPool` 一律不動。

---

### Task 1: GameIntent、BuildSlot 與意圖佇列

**Files:**
- Create: `core/entities/game_intent.gd`
- Create: `core/entities/build_slot.gd`
- Modify: `core/sim/world_state.gd`
- Test: `tests/core/test_build_system.gd`

**Interfaces:**
- Consumes: `WorldState.next_id()`
- Produces:
  - `GameIntent` 常數 `KIND_BUILD`、`KIND_SELL`、`KIND_UPGRADE`；欄位 `kind`、`slot_id`、`tower_id`、`entity_id`；靜態建構子 `GameIntent.build(slot_id: int, tower_id: StringName)`、`GameIntent.sell(entity_id: int)`、`GameIntent.upgrade(entity_id: int)`
  - `BuildSlot` 欄位 `id: int`、`position: Vector2`、`occupied_by: int`
  - `WorldState.build_slots: Array[BuildSlot]`、`build_slots_by_id: Dictionary`、`add_build_slot(slot) -> void`
  - `WorldState.pending_intents: Array[GameIntent]`、`queue_intent(intent) -> void`

- [ ] **Step 1: 寫失敗的測試**

Create `tests/core/test_build_system.gd`:

```gdscript
extends GdUnitTestSuite

func test_build_intent_carries_slot_and_tower() -> void:
	var intent := GameIntent.build(7, &"archer_tower")
	assert_str(intent.kind).is_equal("build")
	assert_int(intent.slot_id).is_equal(7)
	assert_str(intent.tower_id).is_equal("archer_tower")

func test_sell_intent_carries_entity_id() -> void:
	var intent := GameIntent.sell(42)
	assert_str(intent.kind).is_equal("sell")
	assert_int(intent.entity_id).is_equal(42)

func test_upgrade_intent_carries_entity_id() -> void:
	var intent := GameIntent.upgrade(42)
	assert_str(intent.kind).is_equal("upgrade")
	assert_int(intent.entity_id).is_equal(42)

func test_added_build_slot_gets_an_entity_id_and_is_indexed() -> void:
	var world := WorldState.new()
	var slot := BuildSlot.new()
	slot.position = Vector2(400, 200)
	world.add_build_slot(slot)
	assert_int(slot.id).is_greater(0)
	assert_array(world.build_slots).has_size(1)
	assert_bool(world.build_slots_by_id.has(slot.id)).is_true()

func test_build_slots_share_the_entity_id_space_with_other_entities() -> void:
	# id 跨型別不重複，是「實體 id 永不衝突」這條性質的一部分
	var world := WorldState.new()
	var slot := BuildSlot.new()
	world.add_build_slot(slot)
	var enemy := Enemy.new()
	world.add_enemy(enemy)
	assert_bool(slot.id != enemy.id).override_failure_message(
		"建塔點與敵人的 id 必須來自同一個計數器，不得重複"
	).is_true()

func test_queued_intents_accumulate() -> void:
	var world := WorldState.new()
	world.queue_intent(GameIntent.build(1, &"archer_tower"))
	world.queue_intent(GameIntent.sell(2))
	assert_array(world.pending_intents).has_size(2)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: FAIL，識別字 `GameIntent` 未定義。

- [ ] **Step 3: 寫 GameIntent**

Create `core/entities/game_intent.gd`:

```gdscript
class_name GameIntent
extends RefCounted

## 玩家意圖。輸入層產生，排入 WorldState 的佇列，由 BattleSim 在 tick 第一步套用。
##
## 排隊而非立即套用，是為了讓所有改變世界的事情都發生在 tick 內的明確位置——
## 既有整套 tick 順序測試都建立在這條不變式上。代價是最多一個 tick 的延遲。
##
## 不做池化：intent 由人手驅動，每秒最多數個，與每秒數十個生滅的投射物
## 不是同一個量級。沿用「只池化 churn 最高的」原則。

const KIND_BUILD := &"build"
const KIND_SELL := &"sell"
const KIND_UPGRADE := &"upgrade"

var kind: StringName = &""
var slot_id: int = 0            ## KIND_BUILD 用
var tower_id: StringName = &""  ## KIND_BUILD 用，要蓋哪一種
var entity_id: int = 0          ## KIND_SELL / KIND_UPGRADE 用，動哪一座

static func build(p_slot_id: int, p_tower_id: StringName) -> GameIntent:
	var intent := GameIntent.new()
	intent.kind = KIND_BUILD
	intent.slot_id = p_slot_id
	intent.tower_id = p_tower_id
	return intent

static func sell(p_entity_id: int) -> GameIntent:
	var intent := GameIntent.new()
	intent.kind = KIND_SELL
	intent.entity_id = p_entity_id
	return intent

static func upgrade(p_entity_id: int) -> GameIntent:
	var intent := GameIntent.new()
	intent.kind = KIND_UPGRADE
	intent.entity_id = p_entity_id
	return intent
```

- [ ] **Step 4: 寫 BuildSlot**

Create `core/entities/build_slot.gd`:

```gdscript
class_name BuildSlot
extends RefCounted

## 關卡上可以蓋塔的一個離散位置。
## 位置由場景中的 Marker2D 標示，載入時烘焙成本類別交給 core/——
## 與 Path2D → PathData 同一模式，core/ 不認得 Marker2D。

var id: int = 0                ## 由 WorldState.next_id() 配發，與其他實體共用號碼空間
var position: Vector2 = Vector2.ZERO
var occupied_by: int = 0       ## 塔的實體 id，0 表示空著
```

- [ ] **Step 5: 在 WorldState 加入建塔點與佇列**

在 `core/sim/world_state.gd` 的 `enemies_by_id` 宣告之後加入：

```gdscript
var build_slots: Array[BuildSlot] = []
var build_slots_by_id: Dictionary = {}   ## int -> BuildSlot

## 待處理的玩家意圖。BattleSim 於 tick 第一步排空並套用。
var pending_intents: Array[GameIntent] = []
```

並在 `add_tower` 之後加入：

```gdscript
func add_build_slot(slot: BuildSlot) -> void:
	if slot.id == 0:
		slot.id = next_id()
	build_slots.append(slot)
	build_slots_by_id[slot.id] = slot

func queue_intent(intent: GameIntent) -> void:
	pending_intents.append(intent)
```

- [ ] **Step 6: 執行全套件確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 133 個測試全部 PASS（127 + 6 新增），exit 0。

- [ ] **Step 7: 提交**

```bash
git add core/entities/game_intent.gd core/entities/game_intent.gd.uid \
        core/entities/build_slot.gd core/entities/build_slot.gd.uid \
        core/sim/world_state.gd \
        tests/core/test_build_system.gd tests/core/test_build_system.gd.uid
git commit -m "feat(core): 新增 GameIntent、BuildSlot 與意圖佇列"
```

---

### Task 2: 關卡資料與 DataRegistry 載入

**Files:**
- Create: `data/levels/level_01/meta.json`
- Modify: `core/data/data_registry.gd`
- Modify: `tests/test_data_integrity.gd`

**Interfaces:**
- Consumes: 無
- Produces: `DataRegistry.levels: Dictionary`（`StringName` → 關卡 meta `Dictionary`）

**關卡的目錄形狀與其他資料不同**：`enemies/` 與 `towers/` 是「一個檔案一個實體、檔名等於 id」；關卡是「一個目錄一個關卡、檔案固定叫 `meta.json`」。因此不能沿用 `_load_dir`，也不能把 `data/levels` 直接塞進既有的檔名一致守衛——`meta.json` 的檔名永遠不等於 `level_01`，那樣做必然失敗。

- [ ] **Step 1: 建立關卡 meta**

Create `data/levels/level_01/meta.json`:

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

- [ ] **Step 2: 寫失敗的完整性測試**

在 `tests/test_data_integrity.gd` 末端加入：

```gdscript
func test_at_least_one_level_is_loaded() -> void:
	assert_int(_registry.levels.size()).is_greater(0)

func test_every_level_has_required_fields() -> void:
	var required := [
		"id", "name_key", "starting_gold", "starting_lives",
		"sell_refund_ratio", "available_towers",
	]
	for level_id: StringName in _registry.levels:
		var meta: Dictionary = _registry.levels[level_id]
		for field: String in required:
			assert_bool(meta.has(field)).override_failure_message(
				"關卡 %s 缺少必填欄位 %s" % [level_id, field]
			).is_true()

func test_every_level_has_sane_starting_resources() -> void:
	for level_id: StringName in _registry.levels:
		var meta: Dictionary = _registry.levels[level_id]
		assert_float(meta["starting_gold"]).override_failure_message(
			"關卡 %s 的起始金幣必須為正" % level_id
		).is_greater(0.0)
		assert_float(meta["starting_lives"]).override_failure_message(
			"關卡 %s 的起始生命必須為正" % level_id
		).is_greater(0.0)

func test_sell_refund_ratio_is_within_zero_to_one() -> void:
	# 大於 1 等於賣塔賺錢，玩家可以無限套利
	for level_id: StringName in _registry.levels:
		assert_float(_registry.levels[level_id]["sell_refund_ratio"]).override_failure_message(
			"關卡 %s 的退款比例必須落在 0 與 1 之間，否則賣塔會變成無限套利" % level_id
		).is_between(0.0, 1.0)

func test_level_available_towers_reference_existing_towers() -> void:
	for level_id: StringName in _registry.levels:
		for tower_id in _registry.levels[level_id]["available_towers"]:
			assert_bool(_registry.towers.has(StringName(tower_id))).override_failure_message(
				"關卡 %s 的可用塔種引用了不存在的塔 %s" % [level_id, tower_id]
			).is_true()

func test_level_directory_name_matches_its_id() -> void:
	# 關卡的形狀與 enemies/towers 不同：檔案固定叫 meta.json，
	# 所以身分由「目錄名」承載，既有的檔名一致守衛套不上來。
	var dir := DirAccess.open("res://data/levels")
	assert_bool(dir != null).is_true()
	var count := 0
	for sub_dir in dir.get_directories():
		count += 1
		assert_bool(_registry.levels.has(StringName(sub_dir))).override_failure_message(
			"關卡目錄 %s 底下的 meta.json 其 id 與目錄名不符" % sub_dir
		).is_true()
	assert_int(_registry.levels.size()).override_failure_message(
		"關卡目錄數與註冊表大小不符，表示有兩個關卡宣告了同一個 id 而互相覆蓋"
	).is_equal(count)
```

- [ ] **Step 3: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: FAIL，`_registry.levels` 不存在。

- [ ] **Step 4: 在 DataRegistry 加入關卡載入**

在 `core/data/data_registry.gd` 的 `status_effects` 宣告之後加入：

```gdscript
var levels: Dictionary = {}    ## StringName -> Dictionary
```

在 `load_from_disk` 末端加入：

```gdscript
	levels = _load_level_dirs(root.path_join("levels"))
```

並在 `_load_dir` 之後加入：

```gdscript
## 關卡的目錄形狀與其他資料不同：一個關卡一個目錄，檔案固定叫 meta.json，
## 身分由目錄名承載。因此不能沿用 _load_dir。
func _load_level_dirs(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	assert(dir != null, "找不到關卡目錄: %s" % dir_path)
	for sub_dir in dir.get_directories():
		var meta_path := dir_path.path_join(sub_dir).path_join("meta.json")
		assert(FileAccess.file_exists(meta_path), "關卡目錄缺少 meta.json: %s" % sub_dir)
		var text := FileAccess.get_file_as_string(meta_path)
		var parsed: Variant = JSON.parse_string(text)
		assert(parsed is Dictionary, "JSON 格式錯誤: %s" % meta_path)
		var meta: Dictionary = parsed
		assert(meta.has("id"), "關卡 meta 缺少 id 欄位: %s" % meta_path)
		result[StringName(meta["id"])] = meta
	return result
```

- [ ] **Step 5: 執行全套件確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 139 個測試全部 PASS（133 + 6 新增），exit 0。

- [ ] **Step 6: 驗證完整性測試真的會咬人**

暫時把 `data/levels/level_01/meta.json` 的 `sell_refund_ratio` 改成 `1.5`，重跑全套件。

Expected: FAIL，訊息為「關卡 level_01 的退款比例必須落在 0 與 1 之間，否則賣塔會變成無限套利」。

接著把該檔的 `id` 暫時改成 `level_99`，重跑全套件。

Expected: FAIL，訊息為「關卡目錄 level_01 底下的 meta.json 其 id 與目錄名不符」。

兩項都確認後把檔案改回原狀，並以 `git status --porcelain data/` 確認 `data/` 乾淨後再繼續。

- [ ] **Step 7: 提交**

```bash
git add data/levels/level_01/meta.json core/data/data_registry.gd tests/test_data_integrity.gd
git commit -m "feat(data): 新增關卡 meta 與其完整性守衛"
```

---

### Task 3: configure_for_level — 更名並擴大職責

`WorldState.apply_definitions()` 目前只注入 `effect_defs`。B1 之後它還要注入塔的定義、本關可用塔種、退款比例、起始金幣與生命。名稱已不符實，且**每多一項注入就多一個「要記得接線」的地方**——M1-A 的最終 review 正是抓到漏接 `effect_defs` 導致狀態效果在遊戲中無聲失效。

**Files:**
- Modify: `core/sim/world_state.gd`
- Modify: `game/level/battle_scene.gd`
- Modify: `tests/core/test_battle_integration.gd`
- Modify: `tests/test_core_purity.gd`

**Interfaces:**
- Consumes: `DataRegistry.levels`（Task 2）
- Produces:
  - `WorldState.tower_defs: Dictionary`、`available_towers: Array[StringName]`、`sell_refund_ratio: float`
  - `WorldState.configure_for_level(registry: DataRegistry, level_id: StringName) -> void`（取代 `apply_definitions`）

- [ ] **Step 1: 改寫守衛測試**

`tests/core/test_battle_integration.gd` 中的 `test_apply_definitions_wires_effect_defs_from_the_registry` 直接呼叫了舊方法。**不能只改方法名就算數**——新增的注入項目一樣需要守衛，否則等於把 M1-A 才修好的洞重新挖開。

把該測試整個換成：

```gdscript
func test_configure_for_level_wires_everything_the_world_needs() -> void:
	# 每多一項注入就多一個「要記得接線」的地方。M1-A 的最終 review 抓到漏接
	# effect_defs 導致狀態效果在遊戲中無聲失效，所以這裡逐項守住。
	var registry := DataRegistry.new()
	registry.load_from_disk()

	var world := WorldState.new()
	world.configure_for_level(registry, &"level_01")

	var meta: Dictionary = registry.levels[&"level_01"]

	assert_int(world.effect_defs.size()).override_failure_message(
		"未注入狀態效果定義，命中效果會在遊戲中無聲失效"
	).is_greater(0)
	assert_int(world.tower_defs.size()).override_failure_message(
		"未注入塔的定義，建塔會找不到資料"
	).is_greater(0)
	assert_int(world.available_towers.size()).override_failure_message(
		"未注入本關可用塔種，所有建造都會被拒絕"
	).is_equal(meta["available_towers"].size())
	assert_float(world.sell_refund_ratio).is_equal_approx(meta["sell_refund_ratio"], 0.001)
	assert_int(world.gold).is_equal(int(meta["starting_gold"]))
	assert_int(world.lives).is_equal(int(meta["starting_lives"]))
```

- [ ] **Step 2: 改寫原始碼掃描守衛**

`tests/test_core_purity.gd` 裡的 `test_battle_scene_wires_effect_definitions` 掃描 `battle_scene.gd` 的原始碼找 `apply_definitions`。把該測試改名為 `test_battle_scene_configures_the_world_for_its_level`，並把要找的字串改為 `configure_for_level`，失敗訊息也一併更新為說明未呼叫時整個世界都不會被配置。

其餘部分（讀檔方式、註解說明為何用原始碼掃描）保持不變。

- [ ] **Step 3: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: FAIL，`configure_for_level` 不存在。

- [ ] **Step 4: 在 WorldState 加入欄位並改寫方法**

在 `core/sim/world_state.gd` 的 `effect_defs` 宣告之後加入：

```gdscript
## 塔的 JSON 定義與本關可用的塔種，同樣由 configure_for_level 注入。
var tower_defs: Dictionary = {}              ## StringName -> Dictionary
var available_towers: Array[StringName] = []
var sell_refund_ratio: float = 0.0
```

把 `apply_definitions` 整個換成：

```gdscript
## 依關卡把整個世界配置好：資料定義、可用塔種、起始資源。
## core/ 不讀檔，所以定義由呼叫端自 DataRegistry 取得後傳入。
##
## 一次呼叫涵蓋全部，是為了讓「忘了接線」只會發生一次，而不是每加一項注入
## 就多一個要記得的地方。M1-A 的最終 review 正是抓到漏接 effect_defs，
## 導致命中狀態效果在實際遊戲中完全失效，而所有測試照樣通過。
func configure_for_level(registry: DataRegistry, level_id: StringName) -> void:
	assert(registry.levels.has(level_id), "找不到關卡定義: %s" % level_id)
	var meta: Dictionary = registry.levels[level_id]

	effect_defs = registry.status_effects
	tower_defs = registry.towers

	var towers_for_level: Array[StringName] = []
	for tower_id in meta["available_towers"]:
		towers_for_level.append(StringName(tower_id))
	available_towers = towers_for_level

	sell_refund_ratio = meta["sell_refund_ratio"]
	gold = int(meta["starting_gold"])
	lives = int(meta["starting_lives"])
```

- [ ] **Step 5: 更新場景的呼叫**

在 `game/level/battle_scene.gd` 的 `_ready` 中，把：

```gdscript
	world.apply_definitions(_registry)
```

換成：

```gdscript
	world.configure_for_level(_registry, &"level_01")
```

並刪掉緊接其後的這兩行——起始資源現在由關卡資料決定，寫死在場景裡會與 `meta.json` 不同步：

```gdscript
	world.gold = 200
	world.lives = 20
```

- [ ] **Step 6: 執行全套件確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 139 個測試全部 PASS，exit 0。測試數不變——本任務改寫既有測試而非新增。

- [ ] **Step 7: 驗證原始碼守衛真的會咬人**

暫時把 `game/level/battle_scene.gd` 裡的 `configure_for_level` 呼叫整行刪掉，重跑全套件。

Expected: FAIL，`test_battle_scene_configures_the_world_for_its_level` 失敗。

確認後把該行加回來，重跑確認回到全綠，並以 `git status` 確認沒有殘留修改。

- [ ] **Step 8: 提交**

```bash
git add core/sim/world_state.gd game/level/battle_scene.gd \
        tests/core/test_battle_integration.gd tests/test_core_purity.gd
git commit -m "refactor(core): apply_definitions 更名為 configure_for_level 並擴大職責"
```

---

### Task 4: BuildSystem — 建造

**Files:**
- Create: `core/systems/build_system.gd`
- Modify: `tests/core/test_build_system.gd`

**Interfaces:**
- Consumes: `GameIntent`、`BuildSlot`、`WorldState.tower_defs`、`available_towers`、`build_slots_by_id`、`add_tower`
- Produces: `BuildSystem.apply(world: WorldState, intent: GameIntent) -> void`

**拒絕分兩類，分野是「資料對不對」而非「時機對不對」：**

| 情況 | 處理 |
|---|---|
| 建塔點 id 不存在 | `push_error` — 資料錯誤 |
| 塔種不存在於 `tower_defs` | `push_error` — 資料錯誤 |
| 塔種不在本關 `available_towers` | `push_error` — UI 不該給得出此選項 |
| 建塔點已被占用 | 靜默拒絕 — 正常競態 |
| 金幣不足 | 靜默拒絕 — 正常競態 |

靜默拒絕不是錯誤：玩家快速點兩下、或 UI 用的是上一 tick 的金幣數，都會產生合法但已不成立的指令。把正常競態當錯誤噴，只會訓練所有人無視錯誤訊息。

- [ ] **Step 1: 寫失敗的測試**

在 `tests/core/test_build_system.gd` 末端加入：

```gdscript
const TOWER_DEF := {
	"id": "archer_tower",
	"damage_type": "physical",
	"levels": [
		{"cost": 70,  "damage": 9.0,  "attack_range": 180.0, "fire_interval": 0.8,  "projectile_speed": 600.0, "splash_radius": 0.0, "on_hit_effects": []},
		{"cost": 130, "damage": 14.0, "attack_range": 190.0, "fire_interval": 0.75, "projectile_speed": 610.0, "splash_radius": 0.0, "on_hit_effects": []},
		{"cost": 220, "damage": 22.0, "attack_range": 200.0, "fire_interval": 0.7,  "projectile_speed": 620.0, "splash_radius": 0.0, "on_hit_effects": []},
	],
}

## 一個已配置好、有一個空建塔點的世界
func _make_world(gold: int) -> WorldState:
	var world := WorldState.new()
	world.tower_defs = {&"archer_tower": TOWER_DEF}
	world.available_towers = [&"archer_tower"] as Array[StringName]
	world.sell_refund_ratio = 0.75
	world.gold = gold
	var slot := BuildSlot.new()
	slot.position = Vector2(400, 200)
	world.add_build_slot(slot)
	return world

func _first_slot(world: WorldState) -> BuildSlot:
	return world.build_slots[0]

func test_building_places_a_tower_at_the_slot_and_spends_gold() -> void:
	var world := _make_world(200)
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	assert_array(world.towers).has_size(1)
	assert_float(world.towers[0].position.x).is_equal_approx(400.0, 0.001)
	assert_int(world.gold).is_equal(130)          # 200 − 70

func test_built_tower_gets_level_one_stats_from_data() -> void:
	var world := _make_world(200)
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	var tower: Tower = world.towers[0]
	assert_int(tower.level).is_equal(1)
	assert_float(tower.damage).is_equal_approx(9.0, 0.001)
	assert_float(tower.attack_range).is_equal_approx(180.0, 0.001)
	assert_float(tower.projectile_speed).override_failure_message(
		"投射物速度必須自資料取得；Tower 的預設值是 0，漏搬運會讓投射物不會動"
	).is_equal_approx(600.0, 0.001)

func test_building_marks_the_slot_occupied() -> void:
	var world := _make_world(200)
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	assert_int(_first_slot(world).occupied_by).is_equal(world.towers[0].id)

func test_building_on_an_occupied_slot_is_rejected() -> void:
	var world := _make_world(200)
	var slot_id := _first_slot(world).id
	BuildSystem.apply(world, GameIntent.build(slot_id, &"archer_tower"))
	BuildSystem.apply(world, GameIntent.build(slot_id, &"archer_tower"))
	assert_array(world.towers).override_failure_message(
		"同一個建塔點不得蓋出第二座塔"
	).has_size(1)
	assert_int(world.gold).override_failure_message(
		"被拒絕的建造不得扣款"
	).is_equal(130)

func test_building_without_enough_gold_is_rejected() -> void:
	var world := _make_world(50)          # 造價 70
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	assert_array(world.towers).has_size(0)
	assert_int(world.gold).is_equal(50)

func test_building_with_exactly_enough_gold_succeeds() -> void:
	# 邊界：剛好等於造價必須成立，否則玩家會覺得錢明明夠卻蓋不了
	var world := _make_world(70)
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	assert_array(world.towers).has_size(1)
	assert_int(world.gold).is_equal(0)

# 以下三個是「資料錯誤」類的拒絕。實作會呼叫 push_error，而 GdUnit4 無法攔截它，
# 所以這裡斷言的是「世界沒有被改動」——錯誤路徑同樣不得建出塔或扣款。
# 少了這幾個測試，一個把 push_error 寫成 push_error 後忘了 return 的實作會通過。

func test_building_on_a_nonexistent_slot_changes_nothing() -> void:
	var world := _make_world(200)
	BuildSystem.apply(world, GameIntent.build(9999, &"archer_tower"))
	assert_array(world.towers).has_size(0)
	assert_int(world.gold).override_failure_message(
		"引用不存在的建塔點是資料錯誤，除了報錯之外不得改動世界"
	).is_equal(200)

func test_building_an_unknown_tower_type_changes_nothing() -> void:
	var world := _make_world(200)
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"no_such_tower"))
	assert_array(world.towers).has_size(0)
	assert_int(world.gold).is_equal(200)

func test_building_a_tower_not_available_in_this_level_changes_nothing() -> void:
	# 塔種存在於資料中，但本關的 available_towers 沒有它
	var world := _make_world(200)
	world.tower_defs[&"cannon_tower"] = TOWER_DEF
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"cannon_tower"))
	assert_array(world.towers).override_failure_message(
		"本關不可用的塔種不得蓋出來，即使它存在於資料中"
	).has_size(0)
	assert_int(world.gold).is_equal(200)
	assert_int(_first_slot(world).occupied_by).is_equal(0)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: FAIL，識別字 `BuildSystem` 未定義。

- [ ] **Step 3: 寫 BuildSystem**

Create `core/systems/build_system.gd`:

```gdscript
class_name BuildSystem
extends RefCounted

## 建造、升級、賣出的唯一結算入口。
##
## 拒絕分兩類，分野是「資料對不對」而非「時機對不對」：
##  - 資料錯誤（不存在的建塔點或塔種、本關不可用的塔種）→ push_error，那是 bug
##  - 時機不成立（已占用、錢不夠、塔已被賣掉、已滿級）→ 靜默忽略，那是正常競態。
##    玩家快速點兩下、或 UI 用的是上一 tick 的金幣數，都會產生這種指令。
##    把正常競態當錯誤噴，只會訓練所有人無視錯誤訊息。

static func apply(world: WorldState, intent: GameIntent) -> void:
	match intent.kind:
		GameIntent.KIND_BUILD:
			_build(world, intent)
		_:
			push_error("BuildSystem 收到未知的 intent kind: %s" % intent.kind)

static func _build(world: WorldState, intent: GameIntent) -> void:
	if not world.build_slots_by_id.has(intent.slot_id):
		push_error("build intent 引用了不存在的建塔點 id=%d" % intent.slot_id)
		return
	if not world.tower_defs.has(intent.tower_id):
		push_error("build intent 引用了不存在的塔種: %s" % intent.tower_id)
		return
	if not world.available_towers.has(intent.tower_id):
		push_error("塔種 %s 不在本關的可用清單中，UI 不該給得出此選項" % intent.tower_id)
		return

	var slot: BuildSlot = world.build_slots_by_id[intent.slot_id]
	if slot.occupied_by != 0:
		return

	var def: Dictionary = world.tower_defs[intent.tower_id]
	var cost := int(def["levels"][0]["cost"])
	if world.gold < cost:
		return

	world.gold -= cost
	var tower := Tower.new()
	tower.tower_id = intent.tower_id
	tower.position = slot.position
	_apply_level_stats(tower, def, 1)
	world.add_tower(tower)
	slot.occupied_by = tower.id

## 把指定等級的數值套到塔上。等級自 1 起算，對應 levels 陣列的索引 level - 1。
static func _apply_level_stats(tower: Tower, def: Dictionary, level: int) -> void:
	var level_def: Dictionary = def["levels"][level - 1]
	tower.level = level
	tower.damage = level_def["damage"]
	tower.damage_type = StringName(def["damage_type"])
	tower.attack_range = level_def["attack_range"]
	tower.fire_interval = level_def["fire_interval"]
	tower.projectile_speed = level_def["projectile_speed"]
	tower.splash_radius = level_def["splash_radius"]
	var effects: Array[StringName] = []
	for effect_id in level_def["on_hit_effects"]:
		effects.append(StringName(effect_id))
	tower.on_hit_effects = effects
```

- [ ] **Step 4: 執行全套件確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 145 個測試全部 PASS（139 + 6 新增），exit 0。

- [ ] **Step 5: 提交**

```bash
git add core/systems/build_system.gd core/systems/build_system.gd.uid tests/core/test_build_system.gd
git commit -m "feat(core): BuildSystem 支援建造"
```

---

### Task 5: BuildSystem — 升級

**Files:**
- Modify: `core/systems/build_system.gd`
- Modify: `tests/core/test_build_system.gd`

**Interfaces:**
- Consumes: Task 4 的 `_apply_level_stats`
- Produces: `BuildSystem.apply` 支援 `GameIntent.KIND_UPGRADE`

升級到第 n 級的造價是 `levels[n-1].cost`。等級自 1 起算，所以目前 `level` 級的塔要升級時，下一級在陣列中的索引正好是 `level`。

- [ ] **Step 1: 寫失敗的測試**

在 `tests/core/test_build_system.gd` 末端加入：

```gdscript
## 蓋一座塔並回傳它，方便升級與賣出的測試取用
func _build_one(world: WorldState) -> Tower:
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	return world.towers[0]

func test_upgrading_raises_level_and_stats_and_spends_gold() -> void:
	var world := _make_world(300)
	var tower := _build_one(world)             # 花 70，剩 230
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))
	assert_int(tower.level).is_equal(2)
	assert_float(tower.damage).is_equal_approx(14.0, 0.001)
	assert_float(tower.projectile_speed).override_failure_message(
		"升級必須重新套用該等級的全部數值，不能只改傷害"
	).is_equal_approx(610.0, 0.001)
	assert_int(world.gold).is_equal(100)       # 230 − 130

func test_upgrading_at_max_level_is_rejected() -> void:
	var world := _make_world(1000)
	var tower := _build_one(world)
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))   # 到第 3 級
	var gold_at_max := world.gold
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))   # 應被拒絕
	assert_int(tower.level).override_failure_message(
		"塔只有三級，不得升到第四級"
	).is_equal(3)
	assert_int(world.gold).override_failure_message(
		"被拒絕的升級不得扣款"
	).is_equal(gold_at_max)

func test_upgrading_without_enough_gold_is_rejected() -> void:
	var world := _make_world(100)              # 蓋完剩 30，升級要 130
	var tower := _build_one(world)
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))
	assert_int(tower.level).is_equal(1)
	assert_int(world.gold).is_equal(30)

func test_upgrading_a_tower_that_no_longer_exists_is_rejected() -> void:
	# 塔可能在指令排隊期間被賣掉，這是正常競態而非錯誤
	var world := _make_world(300)
	BuildSystem.apply(world, GameIntent.upgrade(9999))
	assert_int(world.gold).is_equal(300)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: FAIL，`BuildSystem` 對 `upgrade` 這個 kind 呼叫了 `push_error`，升級沒有發生。

- [ ] **Step 3: 實作升級**

在 `core/systems/build_system.gd` 的 `apply` 中，把 `match` 補上一個 case：

```gdscript
		GameIntent.KIND_UPGRADE:
			_upgrade(world, intent)
```

並在 `_build` 之後加入：

```gdscript
static func _upgrade(world: WorldState, intent: GameIntent) -> void:
	var tower := _find_tower(world, intent.entity_id)
	if tower == null:
		return

	var def: Dictionary = world.tower_defs[tower.tower_id]
	var levels: Array = def["levels"]
	# 等級自 1 起算，所以下一級在陣列中的索引正好是目前的 level
	if tower.level >= levels.size():
		return

	var cost := int(levels[tower.level]["cost"])
	if world.gold < cost:
		return

	world.gold -= cost
	_apply_level_stats(tower, def, tower.level + 1)

static func _find_tower(world: WorldState, entity_id: int) -> Tower:
	for tower: Tower in world.towers:
		if tower.id == entity_id:
			return tower
	return null
```

- [ ] **Step 4: 執行全套件確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 149 個測試全部 PASS（145 + 4 新增），exit 0。

- [ ] **Step 5: 提交**

```bash
git add core/systems/build_system.gd tests/core/test_build_system.gd
git commit -m "feat(core): BuildSystem 支援升級"
```

---

### Task 6: BuildSystem — 賣出

**Files:**
- Modify: `core/systems/build_system.gd`
- Modify: `tests/core/test_build_system.gd`

**Interfaces:**
- Consumes: Task 5 的 `_find_tower`
- Produces: `BuildSystem.apply` 支援 `GameIntent.KIND_SELL`

退款 = `sell_refund_ratio × 已投入的所有等級造價總和`，向下取整。**不在塔身上記帳**，而是自 `level` 反推 `levels[0..level-1]` 的造價總和——少一個會不同步的欄位。

**賣價測試必須使用等級大於 1 的塔。** 若以一級塔測試，「退款 = 比例 × 全部投入」與「退款 = 比例 × 一級造價」算出來一模一樣，錯誤的實作照樣通過。

- [ ] **Step 1: 寫失敗的測試**

在 `tests/core/test_build_system.gd` 末端加入：

```gdscript
func test_selling_a_level_one_tower_refunds_a_fraction_of_its_cost() -> void:
	var world := _make_world(200)
	var tower := _build_one(world)             # 花 70，剩 130
	BuildSystem.apply(world, GameIntent.sell(tower.id))
	assert_int(world.gold).is_equal(182)       # 130 + floor(70 × 0.75) = 130 + 52

func test_selling_refunds_every_level_invested_not_just_the_first() -> void:
	# 這個測試必須用等級大於 1 的塔。用一級塔的話，
	# 「退款 = 比例 × 全部投入」與「退款 = 比例 × 一級造價」結果相同，
	# 錯誤的實作會照樣通過。
	var world := _make_world(500)
	var tower := _build_one(world)                            # 花 70
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))    # 花 130
	var gold_before := world.gold                             # 500 − 200 = 300
	BuildSystem.apply(world, GameIntent.sell(tower.id))
	# 已投入 70 + 130 = 200，退款 floor(200 × 0.75) = 150
	assert_int(world.gold).override_failure_message(
		"退款必須涵蓋所有已投入的等級造價，不能只算建造費"
	).is_equal(gold_before + 150)

func test_selling_removes_the_tower_and_frees_its_slot() -> void:
	var world := _make_world(200)
	var tower := _build_one(world)
	BuildSystem.apply(world, GameIntent.sell(tower.id))
	assert_array(world.towers).has_size(0)
	assert_int(_first_slot(world).occupied_by).override_failure_message(
		"賣出後建塔點必須回到空著的狀態，否則該位置永遠不能再蓋"
	).is_equal(0)

func test_a_freed_slot_can_be_built_on_again() -> void:
	var world := _make_world(300)
	var tower := _build_one(world)
	BuildSystem.apply(world, GameIntent.sell(tower.id))
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	assert_array(world.towers).has_size(1)

func test_selling_a_tower_that_no_longer_exists_is_rejected() -> void:
	var world := _make_world(200)
	BuildSystem.apply(world, GameIntent.sell(9999))
	assert_int(world.gold).override_failure_message(
		"賣一座不存在的塔不得憑空產生金幣"
	).is_equal(200)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: FAIL，`BuildSystem` 對 `sell` 這個 kind 呼叫了 `push_error`，賣出沒有發生。

- [ ] **Step 3: 實作賣出**

在 `core/systems/build_system.gd` 的 `apply` 中，把 `match` 補上一個 case：

```gdscript
		GameIntent.KIND_SELL:
			_sell(world, intent)
```

並在 `_upgrade` 之後加入：

```gdscript
static func _sell(world: WorldState, intent: GameIntent) -> void:
	var tower := _find_tower(world, intent.entity_id)
	if tower == null:
		return

	var def: Dictionary = world.tower_defs[tower.tower_id]
	world.gold += _refund_for(def, tower.level, world.sell_refund_ratio)

	for slot: BuildSlot in world.build_slots:
		if slot.occupied_by == tower.id:
			slot.occupied_by = 0
			break
	world.towers.erase(tower)

## 退款 = 比例 × 已投入的所有等級造價總和，向下取整。
## 不在塔身上記帳，而是自等級反推——少一個會與資料不同步的欄位。
static func _refund_for(def: Dictionary, level: int, ratio: float) -> int:
	var invested := 0
	for i in level:
		invested += int(def["levels"][i]["cost"])
	return floori(float(invested) * ratio)
```

- [ ] **Step 4: 執行全套件確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 154 個測試全部 PASS（149 + 5 新增），exit 0。

- [ ] **Step 5: 提交**

```bash
git add core/systems/build_system.gd tests/core/test_build_system.gd
git commit -m "feat(core): BuildSystem 支援賣出"
```

---

### Task 7: 接入 tick 迴圈第一步

**Files:**
- Modify: `core/sim/battle_sim.gd`
- Modify: `tests/core/test_tick_order.gd`

**Interfaces:**
- Consumes: `BuildSystem.apply`、`WorldState.pending_intents`
- Produces: `BattleSim._tick()` 的第一步排空意圖佇列

tick 順序變成八步：

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

**排第一**的理由：這一 tick 蓋好的塔，這一 tick 就能開火；賣掉的塔在能開火之前就消失。兩者都符合直覺且不需要任何特例。

- [ ] **Step 1: 寫失敗的測試**

在 `tests/core/test_tick_order.gd` 末端加入：

```gdscript
## 一個配置好、有一個空建塔點與一隻停住的敵人的世界
func _make_buildable_world() -> WorldState:
	var world := _make_world()
	world.tower_defs = {
		&"archer_tower": {
			"id": "archer_tower",
			"damage_type": "physical",
			"levels": [
				{"cost": 70, "damage": 9.0, "attack_range": 500.0, "fire_interval": 0.8,
				 "projectile_speed": 600.0, "splash_radius": 0.0, "on_hit_effects": []},
			],
		}
	}
	world.available_towers = [&"archer_tower"] as Array[StringName]
	world.gold = 200
	var slot := BuildSlot.new()
	slot.position = Vector2(100, 0)
	world.add_build_slot(slot)
	return world

func test_intent_queued_before_a_tick_is_applied_in_that_tick() -> void:
	var world := _make_buildable_world()
	var sim := BattleSim.new(world)
	world.queue_intent(GameIntent.build(world.build_slots[0].id, &"archer_tower"))

	sim.advance(FRAME)

	assert_array(world.towers).override_failure_message(
		"排隊的意圖必須在下一個 tick 就被套用"
	).has_size(1)
	assert_array(world.pending_intents).override_failure_message(
		"套用後佇列必須清空，否則同一筆指令會被重複執行"
	).has_size(0)

func test_a_tower_built_this_tick_can_fire_this_tick() -> void:
	# 證明意圖套用排在 tick 的第一步。若挪到 tick 尾端，
	# 這一 tick 蓋的塔要等下一 tick 才會鎖定目標，冷卻也不會啟動。
	var world := _make_buildable_world()
	_add_enemy(world, 0.0)                 # 停在路徑起點 (0, 0)，在射程 500 內
	var sim := BattleSim.new(world)
	world.queue_intent(GameIntent.build(world.build_slots[0].id, &"archer_tower"))

	sim.advance(FRAME)

	var tower: Tower = world.towers[0]
	assert_int(tower.target_id).override_failure_message(
		"這一 tick 蓋好的塔，這一 tick 就該鎖定得到目標——代表意圖套用排在 tick 第一步"
	).is_greater(0)
	assert_float(tower.cooldown).override_failure_message(
		"這一 tick 蓋好的塔，這一 tick 就該開得了火"
	).is_greater(0.0)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: FAIL，佇列沒有被排空，`world.towers` 是空的。

- [ ] **Step 3: 在 BattleSim 接入**

在 `core/sim/battle_sim.gd` 中，把 `_tick` 改為：

```gdscript
func _tick() -> void:
	tick_count += 1
	_apply_pending_intents()
	world.status_system.tick(world.enemies, TICK_DELTA)
	MovementSystem.tick(world.enemies, world.paths, TICK_DELTA)
	_collect_leaked()
	_rebuild_grid()
	world.projectile_system.tick(TICK_DELTA)
	_tick_towers()
	_remove_dead()
```

並在 `_tick` 之後加入：

```gdscript
## tick 的第一步。輸入發生在渲染幀上，模擬跑固定步長，兩者不對齊；
## 排隊到 tick 內套用，讓所有改變世界的事情都發生在明確的位置。
## 排第一是為了讓這一 tick 蓋好的塔這一 tick 就能開火，
## 賣掉的塔在能開火之前就消失——兩者都符合直覺且不需要特例。
func _apply_pending_intents() -> void:
	for intent: GameIntent in world.pending_intents:
		match intent.kind:
			GameIntent.KIND_BUILD, GameIntent.KIND_SELL, GameIntent.KIND_UPGRADE:
				BuildSystem.apply(world, intent)
			_:
				push_error("BattleSim 收到未知的 intent kind: %s" % intent.kind)
	world.pending_intents.clear()
```

- [ ] **Step 4: 執行全套件確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 156 個測試全部 PASS（154 + 2 新增），exit 0。

- [ ] **Step 5: 驗證順序守衛真的會咬人**

暫時把 `_apply_pending_intents()` 那一行從 `_tick` 的開頭移到 `_remove_dead()` 之後，重跑全套件。

Expected: FAIL，`test_a_tower_built_this_tick_can_fire_this_tick` 失敗。

確認後把順序改回來，重跑確認回到全綠。**一個永遠不會失敗的順序守衛比沒有更糟。**

- [ ] **Step 6: 提交**

```bash
git add core/sim/battle_sim.gd tests/core/test_tick_order.gd
git commit -m "feat(core): 意圖佇列接入 tick 第一步"
```

---

### Task 8: 場景接線與過渡的自動建塔

本任務是 B1 唯一走人工驗收的部分——依規格，UI 與畫面不做自動化測試。

**Files:**
- Modify: `game/level/battle_scene.tscn`
- Modify: `game/level/battle_scene.gd`

**Interfaces:**
- Consumes: `WorldState.add_build_slot`、`queue_intent`、`GameIntent.build`
- Produces: 可執行的場景，塔透過意圖佇列建出來

**不要開啟 Godot 編輯器 GUI。** `.tscn` 是純文字格式，直接以文字撰寫。

- [ ] **Step 1: 在場景中加入建塔點**

在 `game/level/battle_scene.tscn` 的 `Views` 節點之後，加入一個 `BuildSlots` 節點與四個 `Marker2D` 子節點。目前的路徑為 `(100,150) → (700,150) → (700,250) → (100,250) → (100,600) → (1850,600)`，以下四個位置都落在某段路徑的射程內：

```
[node name="BuildSlots" type="Node2D" parent="."]

[node name="Slot0" type="Marker2D" parent="BuildSlots"]
position = Vector2(400, 200)

[node name="Slot1" type="Marker2D" parent="BuildSlots"]
position = Vector2(400, 450)

[node name="Slot2" type="Marker2D" parent="BuildSlots"]
position = Vector2(900, 480)

[node name="Slot3" type="Marker2D" parent="BuildSlots"]
position = Vector2(1400, 480)
```

`Slot0` 夾在 `y=150` 與 `y=250` 兩段之間，距兩段各 50，是覆蓋率最好的位置——M0 的示範塔就放在這裡。其餘三個覆蓋最後那段 `y=600` 的長直線。

- [ ] **Step 2: 烘焙建塔點並改用意圖建塔**

在 `game/level/battle_scene.gd` 中，於 `@onready var _view_root` 之後加入：

```gdscript
@onready var _build_slots_root: Node2D = $BuildSlots
```

在 `_ready` 中，把這一行：

```gdscript
	_place_tower(&"archer_tower", Vector2(400, 200))
```

換成：

```gdscript
	_bake_build_slots(world)

	# 過渡程式碼：真正的建塔 UI 要到 B3 才有，在那之前開場自動蓋一座塔，
	# 讓畫面維持可玩。刻意走意圖佇列而非直接建造，順便替新路徑做煙霧測試。
	# B3 接上 UI 時刪除本段。
	world.queue_intent(GameIntent.build(world.build_slots[0].id, &"archer_tower"))
```

**順序必須是**：先 `_bake_build_slots(world)`，再 `queue_intent(...)`。烘焙之前 `world.build_slots` 是空的，`build_slots[0]` 會越界。上面的程式碼片段已經是正確順序，照抄即可。

這兩行放在原本 `_place_tower` 那一行的位置，也就是 `_sim = BattleSim.new(world)` 之後。

並把整個 `_place_tower` 函式刪除——塔現在一律由 `BuildSystem` 依資料建出，場景不再重複一份建構邏輯。

在 `_bake_path` 之後加入：

```gdscript
## 把場景中的 Marker2D 烘焙成 BuildSlot 交給 core/。
## core/ 不認得 Marker2D，與 Path2D → PathData 是同一個分層邊界。
func _bake_build_slots(world: WorldState) -> void:
	for marker in _build_slots_root.get_children():
		var slot := BuildSlot.new()
		slot.position = marker.position
		world.add_build_slot(slot)
```

- [ ] **Step 3: 讓塔的 view 跟著模擬走**

`_place_tower` 被刪除後，塔的 view 沒有建立處。在 `_sync_views` 的塔迴圈之前加入建立與清除：

```gdscript
	for tower: Tower in _sim.world.towers:
		if not _tower_views.has(tower.id):
			var view := TowerViewScript.new() as TowerView
			view.setup(tower.id, _registry.towers[tower.tower_id]["sprite"], tower.position)
			_view_root.add_child(view)
			_tower_views[tower.id] = view

	for view_id: int in _tower_views.keys():
		if _find_tower_view_owner(view_id) == null:
			var view: TowerView = _tower_views[view_id]
			view.queue_free()
			_tower_views.erase(view_id)
```

並在 `_sync_views` 之後加入：

```gdscript
## 賣塔之後對應的 view 要跟著消失。塔的數量少，線性搜尋即可。
func _find_tower_view_owner(view_id: int) -> Tower:
	for tower: Tower in _sim.world.towers:
		if tower.id == view_id:
			return tower
	return null
```

- [ ] **Step 4: 確認單元測試未受影響**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 156 個測試全部 PASS，exit 0。本任務只動表現層，測試數不變。

- [ ] **Step 5: headless 冒煙**

```bash
godot --headless --path . --quit-after 2000
```

Expected: exit 0，輸出中沒有 `SCRIPT ERROR`、`Invalid`、`Nil` 或 `Parse Error`。

**注意 headless 不鎖幀率**，`--quit-after N` 的 N 是幀數而非時間，實際模擬時間遠短於 `N/60` 秒。要觀察塔開火（約 tick 90 之後）需要足夠大的 N，2000 已足夠。

- [ ] **Step 6: 人工驗收**

```bash
godot --path .
```

確認四件事：

1. 開場自動在 `(400,200)` 蓋出一座藍色方塊（塔）——證明意圖佇列這條路徑通了
2. 塔照常鎖定敵人並發射黃色箭矢
3. 敵人照常被擊殺並消失
4. 畫面沒有多出的塔，也沒有殘留的塔 view

若塔沒有出現，最可能的原因是起始金幣不足或 `available_towers` 沒接上——先確認 `data/levels/level_01/meta.json` 的 `starting_gold` 是 200 而造價是 70。

- [ ] **Step 7: 提交**

```bash
git add game/level/battle_scene.tscn game/level/battle_scene.gd
git commit -m "feat(game): 場景烘焙建塔點，塔改由意圖佇列建出"
```

---

## B1 完成後

交付物：建塔點、建造／升級／賣出、金錢結算、意圖佇列與 tick 第一步套用，全部有測試覆蓋。

後續：

| 項目 | 去向 |
|---|---|
| 原始事件 → GameIntent，觸控與鍵鼠翻譯器 | B2 |
| HUD、環形建塔選單、射程圈、安全區 | B3 |
| **刪除 `battle_scene.gd` 中開場自動建塔的過渡程式碼** | B3 |
| 分支升級（`UpgradeTower(tower_id, path)`） | M3 |
| 建塔點與路徑同屬「場景資料，完整性測試看不到」的盲點 | B3 與 M2 一併評估 |
