# M1-B2 輸入抽象層 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓玩家用滑鼠與鍵盤實際建造、升級、賣出塔，並暫停與切換倍速，全程透過既有的意圖佇列。

**Architecture:** 三層——裝置翻譯器把原始事件轉成裝置無關的 `InputAction`，`InteractionController` 持有選取狀態並把動作序列翻成 `GameIntent`，佇列由 `BattleSim` 在 tick 第一步排空。翻譯器與控制器都是純函式或純邏輯，`input/` 整層可 headless 測試；只有場景中的事件轉發與座標換算走人工驗收。

**Tech Stack:** Godot 4.7.2、GDScript、GdUnit4 6.2.1。

## Global Constraints

出自 `docs/superpowers/specs/2026-09-04-tower-defense-architecture-design.md` 與 B2 設計規格。**每個任務的要求都隱含包含本節。**

- 只使用 Godot 4.x API。禁用 `KinematicBody2D`、`yield`、`export var`。
- 只使用 GDScript，不引入 C#。
- `core/` 不得 import 任何 Node 或引擎場景類別，也不得讀檔。由 `tests/test_core_purity.gd` 自動驗證。
- `input/` 層可讀 `core/`，但**本里程碑的 `input/` 不含任何 Node**——翻譯器是靜態函式，控制器 `extends RefCounted`。
- 傷害一律經過 `DamageSystem.apply()`。
- 實體之間只用字串 id 或整數實體 id 互相引用。
- 邏輯 tick 固定 30Hz。
- 遊戲資料一律 JSON，置於 `data/`。UI 與資料中只存 i18n key。
- `.gd` 檔一律用 **tab** 縮排。
- Godot 為每個腳本產生 `.uid` 檔，**必須與腳本一起提交**。

### 工作目錄

**本計畫在 worktree 中執行**：`c:/Users/yinya/git/guardians_of_formosa/.worktrees/m1b2`，分支 `feat/m1b2-input`。主目錄 `c:/Users/yinya/git/guardians_of_formosa` 留給美術軌，**不要在那裡工作，也不要切換分支**。

### 測試指令

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

`--ignoreHeadlessMode` 為必要旗標，缺少時 GdUnit4 直接 exit 103 不執行任何測試。**優先跑全套件**——單檔執行會在第一個失敗就停下。既有的資料錯誤測試會印出 `push_error`，那是它們在運作。

新增 `class_name` 後執行 `godot --headless --path . --import`。該指令即使成功也可能回傳非零結束碼，以輸出內容判斷。

`JSON.parse_string()` 一律把數字解析成 `float`，需要整數時必須明確轉換。

### 已驗證可用的斷言

只使用這些形式：`assert_int(x).is_equal(y)`、`assert_float(x).is_equal_approx(y, eps)`、`assert_bool(x).is_true()/.is_false()`、`assert_str(s).contains(...)`、`assert_str(s).is_equal(...)`、`assert_array(a).has_size(n)/.contains([...])`、`assert_int(x).is_greater(n)`、`assert_float(x).is_greater(n)`、`assert_float(x).is_between(lo, hi)`，以及鏈在最終斷言前的 `.override_failure_message("...")`。**沒有 `is_less`**，大小比較寫成 `assert_bool(a < b).is_true()`。

### 起始狀態

分支 `feat/m1b2-input` 自 `main` 的 `a54df42` 分出，測試 165/165、15 個 suite。

---

## 對規格的一處偏離

設計規格 §4.2 說按鍵動作定義在 `project.godot`。本計畫改為**在程式中註冊**（`input/input_bindings.gd`）。

理由：`project.godot` 的 `[input]` 區塊要序列化整個 `InputEvent` 物件，欄位集隨 Godot 版本變動，手寫極易出錯且錯了只在執行期才發現。程式註冊則是幾行 `InputMap.add_action()`，**而且可以被測試斷言**（安裝後檢查動作是否存在）。

代價是這些綁定不會出現在編輯器的專案設定介面裡。本專案目前沒有重新綁定的 UI，B3 或 M4 需要時再遷移。

---

## File Structure

| 檔案 | 責任 |
|---|---|
| `input/input_action.gd` | 新增：裝置無關的動作 |
| `input/interaction_controller.gd` | 新增：互動文法與選取狀態 |
| `input/input_bindings.gd` | 新增：以程式註冊 InputMap 動作 |
| `input/mouse_keyboard_input.gd` | 新增：翻譯器，靜態函式 |
| `core/entities/game_intent.gd` | 修改：新增兩個控制類 kind |
| `core/sim/battle_sim.gd` | 修改：路由器、暫停與倍速 |
| `game/assets/placeholder_slot.png` | 新增：建塔點置換標記 |
| `game/views/build_slot_view.gd` | 新增：建塔點視覺，選中換色 |
| `game/level/battle_scene.gd` | 修改：事件轉發、座標換算、建塔點 view、刪除過渡建塔 |
| `tests/input/test_interaction_controller.gd` | 新增 |
| `tests/input/test_mouse_keyboard_input.gd` | 新增 |
| `tests/core/test_tick_order.gd` | 修改：控制類 intent 與路由回歸守衛 |

`BuildSystem`、`WorldState`、`MovementSystem`、`TargetingSystem`、`DamageSystem`、`ProjectileSystem`、`StatusSystem` 一律不動。

---

### Task 1: InputAction 與選取

**Files:**
- Create: `input/input_action.gd`
- Create: `input/interaction_controller.gd`
- Test: `tests/input/test_interaction_controller.gd`

**Interfaces:**
- Consumes: `WorldState.build_slots`、`build_slots_by_id`
- Produces:
  - `InputAction` 常數 `SELECT_AT`、`CHOOSE_TOWER`、`SELL`、`UPGRADE`、`CANCEL`、`TOGGLE_PAUSE`、`CYCLE_SPEED`；欄位 `kind`、`world_position`、`index`；靜態建構子 `InputAction.select_at(pos)`、`.choose_tower(index)`、`.simple(kind)`
  - `InteractionController.PICK_RADIUS: float`
  - `InteractionController.selected_slot_id: int`
  - `InteractionController.handle(action: InputAction, world: WorldState) -> void`

- [ ] **Step 1: 寫失敗的測試**

Create `tests/input/test_interaction_controller.gd`:

```gdscript
extends GdUnitTestSuite

## 兩個建塔點，相距足夠遠以免命中半徑重疊
const SLOT_A_POS := Vector2(400, 200)
const SLOT_B_POS := Vector2(900, 480)

func _make_world() -> WorldState:
	var world := WorldState.new()
	for pos: Vector2 in [SLOT_A_POS, SLOT_B_POS]:
		var slot := BuildSlot.new()
		slot.position = pos
		world.add_build_slot(slot)
	return world

func _slot_a(world: WorldState) -> BuildSlot:
	return world.build_slots[0]

func _slot_b(world: WorldState) -> BuildSlot:
	return world.build_slots[1]

func test_clicking_on_a_slot_selects_it() -> void:
	var world := _make_world()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	assert_int(controller.selected_slot_id).is_equal(_slot_a(world).id)

func test_clicking_the_second_slot_selects_that_one() -> void:
	# 用第二個而非第一個，才能抓出「永遠回傳 build_slots[0]」的實作
	var world := _make_world()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_B_POS), world)
	assert_int(controller.selected_slot_id).override_failure_message(
		"必須選中被點到的那一個，不是清單中的第一個"
	).is_equal(_slot_b(world).id)

func test_clicking_just_inside_the_pick_radius_selects() -> void:
	var world := _make_world()
	var controller := InteractionController.new()
	var offset := Vector2(InteractionController.PICK_RADIUS - 1.0, 0.0)
	controller.handle(InputAction.select_at(SLOT_A_POS + offset), world)
	assert_int(controller.selected_slot_id).is_equal(_slot_a(world).id)

func test_clicking_outside_the_pick_radius_deselects() -> void:
	var world := _make_world()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	var offset := Vector2(InteractionController.PICK_RADIUS + 10.0, 0.0)
	controller.handle(InputAction.select_at(SLOT_A_POS + offset), world)
	assert_int(controller.selected_slot_id).override_failure_message(
		"點在所有建塔點的命中半徑之外，應解除選取"
	).is_equal(0)

func test_selecting_the_same_slot_twice_is_idempotent() -> void:
	# 做成切換的話，連點兩下會莫名解除選取，而連點在觸控上很常見
	var world := _make_world()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	assert_int(controller.selected_slot_id).is_equal(_slot_a(world).id)

func test_cancel_clears_the_selection() -> void:
	var world := _make_world()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.simple(InputAction.CANCEL), world)
	assert_int(controller.selected_slot_id).is_equal(0)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: FAIL，識別字 `InputAction` 未定義。

- [ ] **Step 3: 寫 InputAction**

Create `input/input_action.gd`:

```gdscript
class_name InputAction
extends RefCounted

## 裝置無關的玩家動作。翻譯器把原始 InputEvent 轉成本型別，
## InteractionController 再把動作序列翻成 GameIntent。
##
## 這一層存在的理由是把「互動文法」與「裝置」分開：文法只寫一次，
## M4 加手把時只需再寫一個薄翻譯器，文法一行都不用動。

const SELECT_AT := &"select_at"        ## 在某個世界座標點選
const CHOOSE_TOWER := &"choose_tower"  ## 選第 n 種本關可用的塔
const SELL := &"sell"
const UPGRADE := &"upgrade"
const CANCEL := &"cancel"
const TOGGLE_PAUSE := &"toggle_pause"
const CYCLE_SPEED := &"cycle_speed"

var kind: StringName = &""
var world_position: Vector2 = Vector2.ZERO  ## SELECT_AT 用
var index: int = 0                          ## CHOOSE_TOWER 用，1 起算

static func select_at(p_world_position: Vector2) -> InputAction:
	var action := InputAction.new()
	action.kind = SELECT_AT
	action.world_position = p_world_position
	return action

static func choose_tower(p_index: int) -> InputAction:
	var action := InputAction.new()
	action.kind = CHOOSE_TOWER
	action.index = p_index
	return action

## 不帶 payload 的動作
static func simple(p_kind: StringName) -> InputAction:
	var action := InputAction.new()
	action.kind = p_kind
	return action
```

- [ ] **Step 4: 寫 InteractionController 的選取部分**

Create `input/interaction_controller.gd`:

```gdscript
class_name InteractionController
extends RefCounted

## 互動文法與選取狀態。純邏輯，不認得任何裝置——裝置的部分在翻譯器裡。
##
## 選取的對象永遠是建塔點，不是塔：所有塔都蓋在建塔點上且同座標，
## 所以「選中一座塔」等同「選中一個被占用的建塔點」，占用與否決定
## 哪些操作合法。狀態機因此只有一個變數。
##
## 本控制器只過濾「結構上做不做得到」，不判斷金錢——金錢是 BuildSystem
## 的權威。控制器若自己再判斷一次，就有了第二個事實來源，而兩者漂移的
## 那天不會有任何測試失敗。錢不夠時 intent 照發，由 core/ 靜默拒絕。

## 命中半徑。依架構規格 §6.4「觸控目標 ≥44pt」，半徑必須至少涵蓋那個尺寸，
## 否則觸控時會出現「看得到卻點不到」。48 留了一點餘裕。
const PICK_RADIUS := 48.0

var selected_slot_id: int = 0   ## 0 表示未選取

func handle(action: InputAction, world: WorldState) -> void:
	match action.kind:
		InputAction.SELECT_AT:
			_select_at(action.world_position, world)
		InputAction.CANCEL:
			selected_slot_id = 0
		_:
			pass

## 選中半徑內最近的建塔點；半徑內沒有就解除選取。
## 建塔點數量是個位數，線性掃描綽綽有餘。
func _select_at(position: Vector2, world: WorldState) -> void:
	var best_id := 0
	var best_distance_squared := PICK_RADIUS * PICK_RADIUS
	for slot: BuildSlot in world.build_slots:
		var distance_squared := position.distance_squared_to(slot.position)
		if distance_squared <= best_distance_squared:
			best_distance_squared = distance_squared
			best_id = slot.id
	selected_slot_id = best_id
```

- [ ] **Step 5: 執行全套件確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 171 個測試全部 PASS（165 + 6 新增），exit 0。

- [ ] **Step 6: 提交**

```bash
git add input/input_action.gd input/input_action.gd.uid \
        input/interaction_controller.gd input/interaction_controller.gd.uid \
        tests/input/test_interaction_controller.gd tests/input/test_interaction_controller.gd.uid
git commit -m "feat(input): 新增 InputAction 與建塔點選取"
```

---

### Task 2: 建造、賣出、升級

**Files:**
- Modify: `input/interaction_controller.gd`
- Modify: `tests/input/test_interaction_controller.gd`

**Interfaces:**
- Consumes: `WorldState.available_towers`、`queue_intent`、`GameIntent.build/sell/upgrade`、`BuildSlot.occupied_by`
- Produces: `InteractionController.handle` 支援 `CHOOSE_TOWER`、`SELL`、`UPGRADE`

**建造測試必須用第二個建塔點與第二種塔。** 若用第一個與第一種，一個寫死 `build_slots[0].id` 與 `available_towers[0]` 的實作會照樣通過。

- [ ] **Step 1: 寫失敗的測試**

在 `tests/input/test_interaction_controller.gd` 末端加入：

```gdscript
## 兩種可用塔種，才能抓出「永遠用第一種」的實作
func _make_world_with_towers() -> WorldState:
	var world := _make_world()
	world.available_towers = [&"archer_tower", &"cannon_tower"] as Array[StringName]
	return world

func test_choosing_a_tower_on_an_empty_slot_queues_a_build() -> void:
	# 刻意用第二個建塔點與第二種塔，寫死索引 0 的實作會失敗
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_B_POS), world)
	controller.handle(InputAction.choose_tower(2), world)

	assert_array(world.pending_intents).has_size(1)
	var intent: GameIntent = world.pending_intents[0]
	assert_str(intent.kind).is_equal("build")
	assert_int(intent.slot_id).override_failure_message(
		"必須用被選中的建塔點，不是清單中的第一個"
	).is_equal(_slot_b(world).id)
	assert_str(intent.tower_id).override_failure_message(
		"必須用被選中的塔種，不是清單中的第一種"
	).is_equal("cannon_tower")

func test_choosing_a_tower_without_a_selection_does_nothing() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.choose_tower(1), world)
	assert_array(world.pending_intents).has_size(0)

func test_choosing_a_tower_on_an_occupied_slot_does_nothing() -> void:
	var world := _make_world_with_towers()
	_slot_b(world).occupied_by = 12345
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_B_POS), world)
	controller.handle(InputAction.choose_tower(1), world)
	assert_array(world.pending_intents).override_failure_message(
		"已經有塔的建塔點不能再蓋"
	).has_size(0)

func test_choosing_a_tower_index_beyond_the_available_list_does_nothing() -> void:
	# 本關只有兩種塔，按「3」是正常的使用者行為，靜默忽略
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.choose_tower(3), world)
	assert_array(world.pending_intents).has_size(0)

func test_selling_an_occupied_slot_queues_a_sell_for_its_tower() -> void:
	var world := _make_world_with_towers()
	_slot_b(world).occupied_by = 777
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_B_POS), world)
	controller.handle(InputAction.simple(InputAction.SELL), world)

	assert_array(world.pending_intents).has_size(1)
	var intent: GameIntent = world.pending_intents[0]
	assert_str(intent.kind).is_equal("sell")
	assert_int(intent.entity_id).override_failure_message(
		"賣出的對象是建塔點上那座塔的實體 id"
	).is_equal(777)

func test_upgrading_an_occupied_slot_queues_an_upgrade_for_its_tower() -> void:
	var world := _make_world_with_towers()
	_slot_b(world).occupied_by = 777
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_B_POS), world)
	controller.handle(InputAction.simple(InputAction.UPGRADE), world)

	assert_array(world.pending_intents).has_size(1)
	assert_str(world.pending_intents[0].kind).is_equal("upgrade")
	assert_int(world.pending_intents[0].entity_id).is_equal(777)

func test_selling_an_empty_slot_does_nothing() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.simple(InputAction.SELL), world)
	assert_array(world.pending_intents).has_size(0)

func test_selling_without_a_selection_does_nothing() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.simple(InputAction.SELL), world)
	assert_array(world.pending_intents).has_size(0)

func test_clicking_another_slot_switches_the_selection() -> void:
	# 轉移表要求已選取時點另一個建塔點是「改選」，不是忽略也不是取消
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.select_at(SLOT_B_POS), world)
	assert_int(controller.selected_slot_id).is_equal(_slot_b(world).id)

func test_upgrading_without_a_selection_does_nothing() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.simple(InputAction.UPGRADE), world)
	assert_array(world.pending_intents).has_size(0)

func test_building_does_not_change_the_selection() -> void:
	# 建造的 intent 下一 tick 才套用；建塔點自然從空變成有塔，
	# 可用操作也就從建造變成賣出與升級，不需要額外邏輯
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.choose_tower(1), world)
	assert_int(controller.selected_slot_id).is_equal(_slot_a(world).id)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: FAIL，`CHOOSE_TOWER` 等動作目前落在 `_:` 分支什麼都不做，佇列是空的。

- [ ] **Step 3: 實作三個動作**

在 `input/interaction_controller.gd` 的 `handle` 中，把 `match` 補上三個 case：

```gdscript
		InputAction.CHOOSE_TOWER:
			_choose_tower(action.index, world)
		InputAction.SELL:
			_sell(world)
		InputAction.UPGRADE:
			_upgrade(world)
```

並在 `_select_at` 之後加入：

```gdscript
## 目前選中的建塔點，未選取或找不到時回傳 null
func _selected_slot(world: WorldState) -> BuildSlot:
	if selected_slot_id == 0:
		return null
	return world.build_slots_by_id.get(selected_slot_id)

## index 自 1 起算，對應本關 available_towers 的第 n 種。
## 超出範圍是正常的使用者行為（按了「3」但本關只有兩種），靜默忽略。
func _choose_tower(index: int, world: WorldState) -> void:
	var slot := _selected_slot(world)
	if slot == null or slot.occupied_by != 0:
		return
	if index < 1 or index > world.available_towers.size():
		return
	world.queue_intent(GameIntent.build(slot.id, world.available_towers[index - 1]))

func _sell(world: WorldState) -> void:
	var slot := _selected_slot(world)
	if slot == null or slot.occupied_by == 0:
		return
	world.queue_intent(GameIntent.sell(slot.occupied_by))

func _upgrade(world: WorldState) -> void:
	var slot := _selected_slot(world)
	if slot == null or slot.occupied_by == 0:
		return
	world.queue_intent(GameIntent.upgrade(slot.occupied_by))
```

- [ ] **Step 4: 執行全套件確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 182 個測試全部 PASS（171 + 11 新增），exit 0。

- [ ] **Step 5: 提交**

```bash
git add input/interaction_controller.gd tests/input/test_interaction_controller.gd
git commit -m "feat(input): 控制器支援建造、賣出、升級"
```

---

### Task 3: 控制類 intent 與 BattleSim 路由器

**Files:**
- Modify: `core/entities/game_intent.gd`
- Modify: `core/sim/battle_sim.gd`
- Modify: `tests/core/test_tick_order.gd`

**Interfaces:**
- Consumes: `BuildSystem.apply`
- Produces:
  - `GameIntent.KIND_TOGGLE_PAUSE`、`KIND_CYCLE_SPEED`；靜態建構子 `GameIntent.toggle_pause()`、`.cycle_speed()`
  - `BattleSim.SPEED_STEPS: Array[float]`
  - `BattleSim._apply_pending_intents` 依 kind 分派

B1 的最終修正把 kind 分派收攏進 `BuildSystem`，並在 `BattleSim` 留了註解說明「等之後的里程碑引入不屬於 `BuildSystem` 的 intent，這裡才需要變成真正的路由器」。暫停與倍速正是那種 intent——它們改的是模擬控制參數而非世界狀態。

**這是會靜默漏掉某個 kind 的改動**，Step 1 的最後一個測試就是為此存在。

- [ ] **Step 1: 寫失敗的測試**

在 `tests/core/test_tick_order.gd` 末端加入：

```gdscript
func test_toggle_pause_intent_flips_the_paused_flag() -> void:
	var world := _make_world()
	var sim := BattleSim.new(world)
	assert_bool(sim.paused).is_false()

	world.queue_intent(GameIntent.toggle_pause())
	sim.advance(FRAME)
	assert_bool(sim.paused).is_true()

	world.queue_intent(GameIntent.toggle_pause())
	sim.advance(FRAME)
	assert_bool(sim.paused).is_false()

func test_cycle_speed_intent_wraps_back_to_one() -> void:
	# 必須驗到循環回頭。只測 1x → 2x 的話，「每次乘二」的實作也會通過。
	var world := _make_world()
	var sim := BattleSim.new(world)
	assert_float(sim.speed_multiplier).is_equal_approx(1.0, 0.001)

	world.queue_intent(GameIntent.cycle_speed())
	sim.advance(FRAME)
	assert_float(sim.speed_multiplier).is_equal_approx(2.0, 0.001)

	world.queue_intent(GameIntent.cycle_speed())
	sim.advance(FRAME)
	assert_float(sim.speed_multiplier).is_equal_approx(4.0, 0.001)

	world.queue_intent(GameIntent.cycle_speed())
	sim.advance(FRAME)
	assert_float(sim.speed_multiplier).override_failure_message(
		"倍速必須循環回 1x，不是無限倍增"
	).is_equal_approx(1.0, 0.001)

func test_build_intents_still_reach_the_build_system_after_routing() -> void:
	# 路由重構最可能的失敗是靜默漏掉某個 kind。這條守著建造那一路。
	#
	# 與 test_intent_queued_before_a_tick_is_applied_in_that_tick 涵蓋範圍重疊，
	# 這是刻意的：那一條的名字講的是「時機」，讀到它的人不會想到路由；
	# 這一條的名字說明了 kind 分派本身是不變式，重構的人才會知道自己動到了什麼。
	var world := _make_buildable_world()
	var sim := BattleSim.new(world)
	world.queue_intent(GameIntent.build(world.build_slots[0].id, &"archer_tower"))

	sim.advance(FRAME)

	assert_array(world.towers).override_failure_message(
		"改成路由器之後，建造類 intent 仍必須到得了 BuildSystem"
	).has_size(1)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: FAIL，`GameIntent.toggle_pause` 不存在。

- [ ] **Step 3: 在 GameIntent 加入兩個控制類 kind**

在 `core/entities/game_intent.gd` 的 `KIND_UPGRADE` 之後加入：

```gdscript

## 控制類：改的是模擬本身的參數，不是世界狀態，由 BattleSim 直接處理。
## 刻意不帶數值——intent 表達玩家動作而非結果值，回放時重現的才是
## 「玩家按了切換」而不是「速度變成 2」。
const KIND_TOGGLE_PAUSE := &"toggle_pause"
const KIND_CYCLE_SPEED := &"cycle_speed"
```

並在檔案末端加入：

```gdscript
static func toggle_pause() -> GameIntent:
	var intent := GameIntent.new()
	intent.kind = KIND_TOGGLE_PAUSE
	return intent

static func cycle_speed() -> GameIntent:
	var intent := GameIntent.new()
	intent.kind = KIND_CYCLE_SPEED
	return intent
```

- [ ] **Step 4: 把 BattleSim 改成路由器**

在 `core/sim/battle_sim.gd` 的 `MAX_TICKS_PER_FRAME` 之後加入：

```gdscript

## 倍速循環的順序。CYCLE_SPEED intent 不帶數值，由這裡決定下一段。
const SPEED_STEPS: Array[float] = [1.0, 2.0, 4.0]
```

把 `_apply_pending_intents` 上方那段「kind 的分派全交給 BuildSystem」的註解換成：

```gdscript
## kind 分派的路由器。建造類轉給 BuildSystem，控制類自己處理——
## 後者改的是模擬參數而非世界狀態，不屬於 BuildSystem 的職責。
##
## 未知的 kind 會落到 BuildSystem，由它既有的 push_error 攔下，
## 所以任何 kind 都不會被靜默丟掉。
```

並把函式本體換成：

```gdscript
func _apply_pending_intents() -> void:
	for intent: GameIntent in world.pending_intents:
		match intent.kind:
			GameIntent.KIND_TOGGLE_PAUSE:
				paused = not paused
			GameIntent.KIND_CYCLE_SPEED:
				_cycle_speed()
			_:
				BuildSystem.apply(world, intent)
	world.pending_intents.clear()

## 切到下一段倍速。find 找不到時回傳 -1，(-1 + 1) % n == 0，
## 因此速度被改成清單外的值時會安全地回到第一段而非當掉。
func _cycle_speed() -> void:
	var current := SPEED_STEPS.find(speed_multiplier)
	speed_multiplier = SPEED_STEPS[(current + 1) % SPEED_STEPS.size()]
```

- [ ] **Step 5: 執行全套件確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 185 個測試全部 PASS（182 + 3 新增），exit 0。

- [ ] **Step 6: 驗證路由守衛真的會咬人**

暫時把 `_apply_pending_intents` 的 `_:` 分支改成 `pass`（不再轉給 `BuildSystem`），重跑全套件。

Expected: FAIL，`test_build_intents_still_reach_the_build_system_after_routing` 以及 B1 既有的建造相關測試失敗。

確認後把 `_:` 分支改回 `BuildSystem.apply(world, intent)`，重跑確認回到全綠。

- [ ] **Step 7: 提交**

```bash
git add core/entities/game_intent.gd core/sim/battle_sim.gd tests/core/test_tick_order.gd
git commit -m "feat(core): 新增暫停與倍速 intent，BattleSim 成為路由器"
```

---

### Task 4: 控制器發出控制類 intent

**Files:**
- Modify: `input/interaction_controller.gd`
- Modify: `tests/input/test_interaction_controller.gd`

**Interfaces:**
- Consumes: Task 3 的 `GameIntent.toggle_pause()`、`.cycle_speed()`
- Produces: `InteractionController.handle` 支援 `TOGGLE_PAUSE`、`CYCLE_SPEED`

控制類動作**不需要任何選取**——暫停與倍速跟選中什麼無關。

- [ ] **Step 1: 寫失敗的測試**

在 `tests/input/test_interaction_controller.gd` 末端加入：

```gdscript
func test_toggle_pause_needs_no_selection() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.simple(InputAction.TOGGLE_PAUSE), world)
	assert_array(world.pending_intents).override_failure_message(
		"暫停與選中什麼無關，未選取時也該發得出去"
	).has_size(1)
	assert_str(world.pending_intents[0].kind).is_equal("toggle_pause")

func test_cycle_speed_needs_no_selection() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.simple(InputAction.CYCLE_SPEED), world)
	assert_array(world.pending_intents).has_size(1)
	assert_str(world.pending_intents[0].kind).is_equal("cycle_speed")

func test_control_actions_do_not_disturb_the_selection() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.simple(InputAction.TOGGLE_PAUSE), world)
	controller.handle(InputAction.simple(InputAction.CYCLE_SPEED), world)
	assert_int(controller.selected_slot_id).is_equal(_slot_a(world).id)
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: FAIL，佇列是空的——兩個動作目前落在 `_:` 分支。

- [ ] **Step 3: 實作**

在 `input/interaction_controller.gd` 的 `handle` 中，把 `match` 補上兩個 case：

```gdscript
		InputAction.TOGGLE_PAUSE:
			world.queue_intent(GameIntent.toggle_pause())
		InputAction.CYCLE_SPEED:
			world.queue_intent(GameIntent.cycle_speed())
```

- [ ] **Step 4: 執行全套件確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 188 個測試全部 PASS（185 + 3 新增），exit 0。

- [ ] **Step 5: 提交**

```bash
git add input/interaction_controller.gd tests/input/test_interaction_controller.gd
git commit -m "feat(input): 控制器發出暫停與倍速 intent"
```

---

### Task 5: 按鍵綁定與翻譯器

**Files:**
- Create: `input/input_bindings.gd`
- Create: `input/mouse_keyboard_input.gd`
- Test: `tests/input/test_mouse_keyboard_input.gd`

**Interfaces:**
- Consumes: `InputAction`
- Produces:
  - `InputBindings.install() -> void`，冪等
  - `MouseKeyboardInput.TOWER_CHOICE_COUNT: int`
  - `MouseKeyboardInput.translate(event: InputEvent, world_position: Vector2) -> InputAction`，無對應動作時回傳 `null`

按鍵綁定以程式註冊而非寫進 `project.godot`，理由見本計畫開頭的「對規格的一處偏離」。

**`CHOOSE_TOWER` 的測試要用索引 2 而非 1**，否則一個寫死回傳 1 的實作會通過。

- [ ] **Step 1: 寫失敗的測試**

Create `tests/input/test_mouse_keyboard_input.gd`:

```gdscript
extends GdUnitTestSuite

const WORLD_POS := Vector2(123.0, 456.0)

func before_test() -> void:
	InputBindings.install()

## 造一個按下指定實體按鍵的事件
func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event

func _mouse_event(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event

func test_install_registers_every_action() -> void:
	for action_name: String in [
		"gof_select", "gof_cancel", "gof_sell", "gof_upgrade",
		"gof_toggle_pause", "gof_cycle_speed",
		"gof_choose_tower_1", "gof_choose_tower_2", "gof_choose_tower_3",
	]:
		assert_bool(InputMap.has_action(action_name)).override_failure_message(
			"綁定安裝後動作 %s 必須存在，否則翻譯器問到的永遠是 false" % action_name
		).is_true()

func test_install_is_idempotent() -> void:
	InputBindings.install()
	InputBindings.install()
	assert_int(InputMap.action_get_events(&"gof_select").size()).override_failure_message(
		"重複安裝不得讓同一個動作累積重複的事件"
	).is_equal(1)

func test_left_click_becomes_select_at_with_the_given_position() -> void:
	var action := MouseKeyboardInput.translate(_mouse_event(MOUSE_BUTTON_LEFT), WORLD_POS)
	assert_str(action.kind).is_equal("select_at")
	assert_float(action.world_position.x).is_equal_approx(WORLD_POS.x, 0.001)
	assert_float(action.world_position.y).is_equal_approx(WORLD_POS.y, 0.001)

func test_right_click_becomes_cancel() -> void:
	var action := MouseKeyboardInput.translate(_mouse_event(MOUSE_BUTTON_RIGHT), WORLD_POS)
	assert_str(action.kind).is_equal("cancel")

func test_number_key_two_becomes_choose_tower_with_index_two() -> void:
	# 刻意用 2：寫死回傳 1 的實作會被這條抓到
	var action := MouseKeyboardInput.translate(_key_event(KEY_2), WORLD_POS)
	assert_str(action.kind).is_equal("choose_tower")
	assert_int(action.index).override_failure_message(
		"索引必須跟著按鍵走，不是固定的 1"
	).is_equal(2)

func test_s_becomes_sell() -> void:
	assert_str(MouseKeyboardInput.translate(_key_event(KEY_S), WORLD_POS).kind).is_equal("sell")

func test_u_becomes_upgrade() -> void:
	assert_str(MouseKeyboardInput.translate(_key_event(KEY_U), WORLD_POS).kind).is_equal("upgrade")

func test_space_becomes_toggle_pause() -> void:
	assert_str(MouseKeyboardInput.translate(_key_event(KEY_SPACE), WORLD_POS).kind).is_equal("toggle_pause")

func test_f_becomes_cycle_speed() -> void:
	assert_str(MouseKeyboardInput.translate(_key_event(KEY_F), WORLD_POS).kind).is_equal("cycle_speed")

func test_an_unbound_key_produces_nothing() -> void:
	assert_bool(MouseKeyboardInput.translate(_key_event(KEY_Q), WORLD_POS) == null).override_failure_message(
		"沒有綁定的按鍵必須回傳 null，否則場景會處理到不存在的動作"
	).is_true()
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: FAIL，識別字 `InputBindings` 未定義。

- [ ] **Step 3: 寫 InputBindings**

Create `input/input_bindings.gd`:

```gdscript
class_name InputBindings
extends RefCounted

## 以程式註冊 InputMap 動作，而不是寫進 project.godot。
##
## project.godot 的 [input] 區塊要序列化整個 InputEvent 物件，欄位集隨
## Godot 版本變動，手寫極易出錯且錯了只在執行期才發現。程式註冊是幾行
## add_action，而且可以被測試斷言。代價是綁定不出現在編輯器的專案設定
## 介面裡——本專案目前沒有重新綁定的 UI，需要時再遷移。
##
## 前綴 gof_ 避開 Godot 內建的 ui_* 動作。

## 可選塔種的快捷鍵數量。對應「本關第 n 種可用塔」，不是特定塔種，
## 所以換關卡不需要改綁定。
const TOWER_CHOICE_COUNT := 3

## 冪等：已存在的動作會先清掉再重建，重複呼叫不會累積重複事件。
static func install() -> void:
	_bind_mouse(&"gof_select", MOUSE_BUTTON_LEFT)
	_bind_mouse(&"gof_cancel", MOUSE_BUTTON_RIGHT)
	_add_key(&"gof_cancel", KEY_ESCAPE)
	_bind_key(&"gof_sell", KEY_S)
	_bind_key(&"gof_upgrade", KEY_U)
	_bind_key(&"gof_toggle_pause", KEY_SPACE)
	_bind_key(&"gof_cycle_speed", KEY_F)
	for i in range(1, TOWER_CHOICE_COUNT + 1):
		_bind_key(StringName("gof_choose_tower_%d" % i), (KEY_0 + i) as Key)

static func _reset_action(action_name: StringName) -> void:
	if InputMap.has_action(action_name):
		InputMap.action_erase_events(action_name)
	else:
		InputMap.add_action(action_name)

static func _bind_key(action_name: StringName, keycode: Key) -> void:
	_reset_action(action_name)
	_add_key(action_name, keycode)

static func _add_key(action_name: StringName, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action_name, event)

static func _bind_mouse(action_name: StringName, button: MouseButton) -> void:
	_reset_action(action_name)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action_name, event)
```

注意 `gof_cancel` 綁兩個事件（右鍵與 Esc），所以它先 `_bind_mouse` 清空重建、再 `_add_key` 追加。冪等測試檢查的是 `gof_select`，它只有一個事件。

- [ ] **Step 4: 寫 MouseKeyboardInput**

Create `input/mouse_keyboard_input.gd`:

```gdscript
class_name MouseKeyboardInput
extends RefCounted

## 把滑鼠與鍵盤事件翻成裝置無關的 InputAction。
##
## 是靜態函式而非 Node：螢幕座標換算成世界座標的工作留在場景做（它需要
## viewport），結果當參數傳入。因此整個 input/ 層沒有 Node、可 headless 測試。
##
## 觸控目前不需要專屬翻譯器：Godot 預設的 emulate_mouse_from_touch 會把
## 點擊轉成滑鼠事件，正好涵蓋 B2 範圍內的點選與取消。若同時再寫一個觸控
## 翻譯器，一次點擊會產生兩個動作。長按與環形選單手勢屬 B3。

const TOWER_CHOICE_COUNT := InputBindings.TOWER_CHOICE_COUNT

## 無對應動作時回傳 null——場景據此決定不轉發。
static func translate(event: InputEvent, world_position: Vector2) -> InputAction:
	if event.is_action_pressed(&"gof_select"):
		return InputAction.select_at(world_position)
	if event.is_action_pressed(&"gof_cancel"):
		return InputAction.simple(InputAction.CANCEL)
	if event.is_action_pressed(&"gof_sell"):
		return InputAction.simple(InputAction.SELL)
	if event.is_action_pressed(&"gof_upgrade"):
		return InputAction.simple(InputAction.UPGRADE)
	if event.is_action_pressed(&"gof_toggle_pause"):
		return InputAction.simple(InputAction.TOGGLE_PAUSE)
	if event.is_action_pressed(&"gof_cycle_speed"):
		return InputAction.simple(InputAction.CYCLE_SPEED)
	for i in range(1, TOWER_CHOICE_COUNT + 1):
		if event.is_action_pressed(StringName("gof_choose_tower_%d" % i)):
			return InputAction.choose_tower(i)
	return null
```

- [ ] **Step 5: 執行全套件確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 199 個測試全部 PASS（188 + 11 新增），exit 0。

- [ ] **Step 6: 提交**

```bash
git add input/input_bindings.gd input/input_bindings.gd.uid \
        input/mouse_keyboard_input.gd input/mouse_keyboard_input.gd.uid \
        tests/input/test_mouse_keyboard_input.gd tests/input/test_mouse_keyboard_input.gd.uid
git commit -m "feat(input): 按鍵綁定與滑鼠鍵盤翻譯器"
```

---

### Task 6: 場景接線與置換標記

本任務是 B2 唯一走人工驗收的部分——依規格，UI 與畫面不做自動化測試。

**Files:**
- Create: `game/assets/placeholder_slot.png`
- Create: `game/views/build_slot_view.gd`
- Modify: `game/level/battle_scene.gd`

**Interfaces:**
- Consumes: `InputBindings.install()`、`MouseKeyboardInput.translate`、`InteractionController`
- Produces: 可實際操作的場景

**不要開啟 Godot 編輯器 GUI。**

- [ ] **Step 1: 產生置換標記貼圖**

在 worktree 根目錄執行：

```bash
python3 - <<'PY'
import struct, zlib

def solid_png(path, rgba, size):
    raw = b''.join(b'\x00' + bytes(rgba) * size for _ in range(size))
    def chunk(tag, data):
        c = tag + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    open(path, 'wb').write(png)
    print(f"{path}: {size}x{size}, {len(png)} bytes")

# 白色方塊，實際顏色由 BuildSlotView 的 modulate 決定
solid_png('game/assets/placeholder_slot.png', (255, 255, 255, 255), 40)
PY
godot --headless --path . --import
ls game/assets/placeholder_slot.png game/assets/placeholder_slot.png.import
```

Expected: PNG 與其 `.import` 檔都存在。該 PNG 會走 Git LFS（`.gitattributes` 已設定 `*.png`）。

- [ ] **Step 2: 寫 BuildSlotView**

Create `game/views/build_slot_view.gd`:

```gdscript
class_name BuildSlotView
extends Sprite2D

## 建塔點的視覺。B2 的置換品——B3 會換成真正的美術與選取提示。
##
## 沒有它的話玩家看不到建塔點在哪、也看不到自己選中了什麼，
## B2 的人工驗收會變成對著記憶中的座標盲按。

const COLOR_IDLE := Color(1.0, 1.0, 1.0, 0.30)
const COLOR_SELECTED := Color(1.0, 0.88, 0.30, 0.85)

var slot_id: int = 0

func setup(p_slot_id: int, sprite_path: String, slot_position: Vector2) -> void:
	slot_id = p_slot_id
	texture = load(sprite_path)
	position = slot_position
	modulate = COLOR_IDLE

func set_selected(selected: bool) -> void:
	modulate = COLOR_SELECTED if selected else COLOR_IDLE
```

- [ ] **Step 3: 接上輸入與建塔點 view**

在 `game/level/battle_scene.gd` 的 `const ProjectileViewScript` 之後加入：

```gdscript
const BuildSlotViewScript := preload("res://game/views/build_slot_view.gd")

## 建塔點的置換標記。B3 會換成真正的美術。
const SLOT_SPRITE := "res://game/assets/placeholder_slot.png"
```

在 `var _projectile_views` 之後加入：

```gdscript
var _slot_views: Dictionary = {}        ## slot_id -> BuildSlotView
var _controller := InteractionController.new()
```

在 `_ready` 中，把這段過渡程式碼整段刪除——玩家現在自己就能建塔：

```gdscript
	# 過渡程式碼：真正的建塔 UI 要到 B3 才有，在那之前開場自動蓋一座塔，
	# 讓畫面維持可玩。刻意走意圖佇列而非直接建造，順便替新路徑做煙霧測試。
	# B3 接上 UI 時刪除本段。
	world.queue_intent(GameIntent.build(world.build_slots[0].id, &"archer_tower"))
```

並在 `_bake_build_slots(world)` 那一行之後加入：

```gdscript
	InputBindings.install()
```

在 `_bake_build_slots` 的迴圈中，建立 `BuildSlot` 之後同時建立它的 view：

```gdscript
func _bake_build_slots(world: WorldState) -> void:
	for marker in _build_slots_root.get_children():
		var slot := BuildSlot.new()
		slot.position = marker.position
		world.add_build_slot(slot)

		var view := BuildSlotViewScript.new() as BuildSlotView
		view.setup(slot.id, SLOT_SPRITE, slot.position)
		_view_root.add_child(view)
		_slot_views[slot.id] = view
```

在 `_process` 的末端、`_interpolate_views()` 之後加入：

```gdscript
	_update_slot_highlight()
```

並在 `_interpolate_views` 之後加入：

```gdscript
## 每幀更新選取提示。建塔點是個位數，直接全部設定即可。
func _update_slot_highlight() -> void:
	for view: BuildSlotView in _slot_views.values():
		view.set_selected(view.slot_id == _controller.selected_slot_id)

## 把原始事件翻成裝置無關的動作，交給控制器。
## 螢幕座標換算成世界座標需要 viewport，所以這一步留在場景。
## 關卡整幅入鏡、無鏡頭平移，因此只差一個畫布變換。
func _unhandled_input(event: InputEvent) -> void:
	var world_position: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position \
		if event is InputEventMouse else Vector2.ZERO
	var action := MouseKeyboardInput.translate(event, world_position)
	if action == null:
		return
	_controller.handle(action, _sim.world)
	get_viewport().set_input_as_handled()
```

- [ ] **Step 4: 確認單元測試未受影響**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 199 個測試全部 PASS，exit 0。本任務只動表現層，測試數不變。

- [ ] **Step 5: headless 冒煙**

```bash
godot --headless --path . --quit-after 2000
```

Expected: exit 0，輸出中沒有 `SCRIPT ERROR`、`Invalid`、`Nil` 或 `Parse Error`。

畫面上不會有塔——過渡的自動建塔已刪除，而 headless 沒有人按鍵。這是正確的。

**注意 headless 不鎖幀率**，`--quit-after N` 的 N 是幀數而非時間，實際模擬時間遠短於 `N/60` 秒。

- [ ] **Step 6: 人工驗收**

```bash
godot --path .
```

依序確認：

1. 四個半透明白色方塊出現在建塔點位置
2. 點擊其中一個 → 該方塊變成黃色
3. 按 `1` → 該位置蓋出塔，金幣減少
4. 點擊已有塔的建塔點，按 `U` → 塔升級；按 `S` → 塔消失
5. 點空白處 → 黃色提示消失
6. 空白鍵 → 敵人與投射物停住，再按恢復
7. `F` → 速度在 1x / 2x / 4x 間循環

第 6 項要留意一個 B1 的已知現象：**暫停中建造或賣出，畫面不會更新**，要到恢復才看得到。那是 `battle_scene` 只在 `ticks > 0` 時同步 view 造成的，B1 規格 §2.2 已記錄，屬 B3 處理。**驗收時勿誤判為 bug。**

- [ ] **Step 7: 提交**

```bash
git add game/assets/placeholder_slot.png game/assets/placeholder_slot.png.import \
        game/views/build_slot_view.gd game/views/build_slot_view.gd.uid \
        game/level/battle_scene.gd
git commit -m "feat(game): 接上輸入層，建塔點加上置換標記"
```

---

## B2 完成後

交付物：滑鼠鍵盤路線完整可玩——選取、建造、升級、賣出、暫停、倍速，全程透過意圖佇列。`input/` 整層可 headless 測試。

後續：

| 項目 | 去向 |
|---|---|
| 環形建塔選單、HUD、射程圈、安全區 | B3 |
| **置換用的建塔點標記** | B3 替換 |
| 觸控專屬翻譯器、長按查看資訊 | B3 |
| 暫停中的 view 同步 | B3 |
| 手把翻譯器與建塔點跳選 | M4 |
| 按鍵綁定遷回 `project.godot` 或做重新綁定 UI | 需要時 |
| 敵人生成仍在 tick 之外 | 波次系統子里程碑 |
