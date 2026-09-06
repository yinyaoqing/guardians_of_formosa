# M1-B3b 環形建塔選單與塔種 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓玩家用 UI 建塔、升級、賣出，而不是靠記住快捷鍵；並把 M0 的佔位塔換成第一章設計的銃樓與獵寮。

**Architecture:** 選單是螢幕座標的 `CanvasLayer`，按鈕由程式從資料生成；它發 signal，由 `battle_scene` 翻成與鍵盤相同的 `InputAction`，走 B2 已有測試的那條路。選單裡真正的決策（買不買得起、有沒有下一級、退款多少）抽成 `ui/build_menu_options.gd` 的純靜態函式，可 headless 測試——畫面那層只負責畫。

**Tech Stack:** Godot 4.7.2、GDScript、GdUnit4 6.2.1。

## Global Constraints

出自 `CLAUDE.md`、架構規格與 B3b 設計規格。**每個任務的要求都隱含包含本節。**

- 只使用 Godot 4.x API。禁用 `KinematicBody2D`、`yield`、`export var`。
- 只使用 GDScript，不引入 C#。
- `core/` 不得 import 任何 Node 或引擎場景類別，也不得讀檔。**B3b 完全不動 `core/`。**
- `input/` 不含任何 Node。
- **`ui/` 可以讀 `WorldState` 與 `BattleSim`，但不得呼叫 `core/` 的系統、不得寫入 `WorldState`、不得自己排隊意圖。** 要讓事情發生只能發 signal。由 `tests/test_ui_layer.gd` 的原始碼掃描守衛驗證，禁止字串包含 `BuildSystem`、`DamageSystem`、`MovementSystem`、`ProjectileSystem`、`StatusSystem`、`TargetingSystem`、`queue_intent(`、`pending_intents`、`InputAction`，以及對持有的 `WorldState` / `BattleSim` 參照做欄位寫入。
- 傷害一律經過 `DamageSystem.apply()`。
- 實體之間只用字串 id 或整數實體 id 互相引用。
- 邏輯 tick 固定 30Hz。
- 遊戲資料一律 JSON，置於 `data/`；翻譯放 `i18n/`。
- **UI 與資料中只存 i18n key，不存字面文字。**
- **禁止用字串串接組出顯示文字**，格式字串本身要進翻譯檔。
- `.gd` 檔一律用 **tab** 縮排。
- Godot 為每個 `.gd` 產生 `.uid` 檔，**必須與腳本一起提交**。

### 工作目錄

**本計畫在 worktree 中執行**：`c:/Users/yinya/git/guardians_of_formosa/.worktrees/m1b3b`，分支 `feat/m1b3b-build-menu`。主目錄留給美術軌，**不要在那裡工作，也不要切換分支**。

**不要開啟 Godot 編輯器 GUI。** 全部走 headless CLI。

### 測試指令

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

`--ignoreHeadlessMode` 為必要旗標，缺少時 GdUnit4 直接 exit 103 不執行任何測試。`-c` 關閉「同一檔案遇到第一個失敗就停」。

改動資產或新增 `class_name` 後執行 `godot --headless --path . --import`；它即使成功也可能回傳非零結束碼，以輸出判斷。**改了資產沒先 `--import` 就跑測試，可能完全沒有輸出。**

既有的資料錯誤測試會印出 `push_error`，那是它們在運作。

`JSON.parse_string()` 一律把數字解析成 `float`，需要整數時必須明確轉換。

### 已驗證可用的斷言

`assert_int(x).is_equal(y)`、`assert_float(x).is_equal_approx(y, eps)`、`assert_bool(x).is_true()/.is_false()`、`assert_str(s).contains(...)`、`assert_str(s).is_equal(...)`、`assert_array(a).has_size(n)/.contains([...])`、`assert_int(x).is_greater(n)`、`assert_float(x).is_greater(n)`、`assert_float(x).is_between(lo, hi)`，以及鏈在最終斷言前的 `.override_failure_message("...")`。

**沒有 `is_less`**，寫成 `assert_bool(a < b).is_true()`。**`is_not_empty` 未驗證過**，寫成 `assert_bool(s != "").is_true()`。

### 起始狀態

分支 `feat/m1b3b-build-menu` 自 `main` 的 `48fe590` 分出，測試 **227/227**、21 個 suite。

---

## 已確認的環境事實

實測結果，可直接依賴：

- 美術資產已在版控中（`3fee8fa`）：`icon_tower_musket.png`、`icon_tower_hunter.png`（皆 64×64）、`tower_musket_t1/t2/t3.png`（128、128、192）、`tower_hunter_t1.png`（128）、`prop_buildsite.png`（128）。
- `BuildSystem._refund_for` 的算法是 `floori(float(invested) * ratio)`，其中 `invested` 是 `def["levels"][0..level-1]` 的 `cost` 總和。**選單那份必須逐字元一致。**
- `orc_grunt`：hp 120、armor 0.2、speed 45、bounty 6。
- `level_01`：起始金幣 200、生命 20、`sell_refund_ratio` 0.75。
- `tests/test_data_integrity.gd` 的 `test_every_referenced_sprite_path_exists` 目前讀塔的**頂層** `sprite`；`test_every_tower_level_has_required_fields` 要求每階有 `cost`/`damage`/`attack_range`/`fire_interval`；`test_tower_upgrade_costs_increase` 只要求 `levels.size() > 0`，**所以只有一階的塔是合法的**。
- `Tower.on_hit_effects` 由 `BuildSystem` 從 `level_def["on_hit_effects"]` 填入，值是狀態效果的 id 字串。

---

## File Structure

| 檔案 | 責任 |
|---|---|
| `data/towers/musket_tower.json` | 新增：銃樓三階 |
| `data/towers/hunter_tower.json` | 新增：獵寮一階 |
| `data/towers/archer_tower.json` | 刪除：M0 佔位 |
| `data/levels/level_01/meta.json` | 修改：`available_towers` |
| `i18n/strings.csv` | 修改：新增四個 key、移除一個 |
| `tests/test_data_integrity.gd` | 修改：每階 sprite 與 icon |
| `game/views/tower_view.gd` | 修改：能換圖、改用水平翻轉而非旋轉 |
| `game/views/build_slot_view.gd` | 修改：真美術、有塔時隱藏 |
| `game/views/range_circle.gd` | 新增 |
| `ui/build_menu_options.gd` | 新增：選項決策，純靜態函式 |
| `ui/build_menu.tscn` | 新增：只有一個 `CanvasLayer` 根節點 |
| `ui/build_menu.gd` | 新增：生成按鈕、發 signal |
| `game/level/battle_scene.gd` | 修改：等級換圖、掛載選單、射程圈、標記狀態 |
| `tests/ui/test_build_menu_options.gd` | 新增 |
| `game/assets/placeholder_tower.png` | 刪除 |
| `game/assets/placeholder_slot.png` | 刪除 |

`core/` 一律不動。

---

### Task 1: 塔的資料與每階換圖

**Files:**
- Create: `data/towers/musket_tower.json`、`data/towers/hunter_tower.json`
- Delete: `data/towers/archer_tower.json`、`game/assets/placeholder_tower.png`
- Modify: `data/levels/level_01/meta.json`、`i18n/strings.csv`、`tests/test_data_integrity.gd`、`game/views/tower_view.gd`、`game/level/battle_scene.gd`

**Interfaces:**
- Produces: 塔的 def 帶頂層 `icon` 與每階 `sprite`；`TowerView.set_sprite(path)`

資料與消費端放在同一個任務，因為 schema 一改，`battle_scene` 讀頂層 `sprite` 就會在執行期壞掉，而 headless 測試套件從不載入場景腳本——分開做會留下一個沒有任何測試看得到的破窗。

- [ ] **Step 1: 寫失敗的測試**

在 `tests/test_data_integrity.gd` 中，把 `test_every_referenced_sprite_path_exists` 整個換成：

```gdscript
func test_every_referenced_sprite_path_exists() -> void:
	for enemy_id: StringName in _registry.enemies:
		var path: String = _registry.enemies[enemy_id]["sprite"]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(
			"敵人 %s 引用的貼圖不存在: %s" % [enemy_id, path]
		).is_true()

	# 塔的三階在美術上是完全不同的東西（火繩槍手／三人排槍／稜堡砲位），
	# 所以圖在每一階裡，不在頂層。頂層另有 icon 給建塔選單用。
	for tower_id: StringName in _registry.towers:
		var def: Dictionary = _registry.towers[tower_id]

		assert_bool(def.has("icon")).override_failure_message(
			"塔 %s 沒有 icon。建塔選單靠它顯示，缺了選單上會是一個空按鈕。" % tower_id
		).is_true()
		var icon_path: String = def["icon"]
		assert_bool(ResourceLoader.exists(icon_path)).override_failure_message(
			"塔 %s 的選單圖示不存在: %s" % [tower_id, icon_path]
		).is_true()

		var levels: Array = def["levels"]
		for i in levels.size():
			var level_def: Dictionary = levels[i]
			assert_bool(level_def.has("sprite")).override_failure_message(
				"塔 %s 第 %d 級沒有 sprite。升級後畫面要換圖，每階都要有自己的圖。" % [tower_id, i + 1]
			).is_true()
			var level_path: String = level_def.get("sprite", "")
			assert_bool(ResourceLoader.exists(level_path)).override_failure_message(
				"塔 %s 第 %d 級引用的貼圖不存在: %s" % [tower_id, i + 1, level_path]
			).is_true()

func test_no_tower_keeps_a_top_level_sprite() -> void:
	# 舊 schema 的殘留。留著不會壞，但會讓下一個人以為那是圖的來源，
	# 而實際被畫出來的是每階的 sprite——兩者不一致時無聲無息。
	for tower_id: StringName in _registry.towers:
		assert_bool(_registry.towers[tower_id].has("sprite")).override_failure_message(
			"塔 %s 還留著頂層 sprite，那是舊 schema 的殘留" % tower_id
		).is_false()
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests -c
```

Expected: FAIL。`archer_tower` 沒有 `icon`、每階沒有 `sprite`，且它有頂層 `sprite`，所以兩條新測試都該紅。

- [ ] **Step 3: 建立兩種塔的資料**

Create `data/towers/musket_tower.json`:

```json
{
  "id": "musket_tower",
  "name_key": "tower.musket_tower.name",
  "damage_type": "physical",
  "icon": "res://game/assets/chapter01/icon_tower_musket.png",
  "levels": [
    {"cost": 70,  "damage": 18.0, "attack_range": 200.0, "fire_interval": 1.2, "projectile_speed": 700.0, "splash_radius": 0.0,  "on_hit_effects": [], "sprite": "res://game/assets/chapter01/tower_musket_t1.png"},
    {"cost": 130, "damage": 30.0, "attack_range": 210.0, "fire_interval": 1.1, "projectile_speed": 700.0, "splash_radius": 0.0,  "on_hit_effects": [], "sprite": "res://game/assets/chapter01/tower_musket_t2.png"},
    {"cost": 230, "damage": 52.0, "attack_range": 230.0, "fire_interval": 1.5, "projectile_speed": 480.0, "splash_radius": 70.0, "on_hit_effects": [], "sprite": "res://game/assets/chapter01/tower_musket_t3.png"}
  ]
}
```

Create `data/towers/hunter_tower.json`:

```json
{
  "id": "hunter_tower",
  "name_key": "tower.hunter_tower.name",
  "damage_type": "physical",
  "icon": "res://game/assets/chapter01/icon_tower_hunter.png",
  "levels": [
    {"cost": 50, "damage": 7.0, "attack_range": 130.0, "fire_interval": 0.9, "projectile_speed": 620.0, "splash_radius": 0.0, "on_hit_effects": ["chill"], "sprite": "res://game/assets/chapter01/tower_hunter_t1.png"}
  ]
}
```

數值是暫定的，來自第一章規格 §4.0 的定位描述而非平衡測試。三級刻意把射擊間隔拉長換到範圍傷害——那是砲不是槍。

- [ ] **Step 4: 刪掉佔位塔並改關卡與翻譯**

```bash
git rm data/towers/archer_tower.json game/assets/placeholder_tower.png game/assets/placeholder_tower.png.import
```

`data/levels/level_01/meta.json` 的 `available_towers` 改為：

```json
  "available_towers": ["musket_tower", "hunter_tower"],
```

`i18n/strings.csv`：把 `tower.archer_tower.name` 那一列**刪除**，並新增四列：

```
tower.musket_tower.name,銃樓,Musket Tower
tower.hunter_tower.name,獵寮,Hunter's Lodge
menu.upgrade_format,升級 %d,Upgrade %d
menu.sell_format,賣出 +%d,Sell +%d
```

CSV 為 UTF-8 無 BOM、LF 換行。既有的 i18n 完整性測試會抓到殘留或漏補。

- [ ] **Step 5: 讓 TowerView 能換圖，並改用水平翻轉**

`game/views/tower_view.gd` 的 `setup` 之後加入：

```gdscript
## 升級會換成完全不同的一張圖（火繩槍手 → 三人排槍 → 稜堡砲位），
## 所以圖不是建造時載入一次就結束。
func set_sprite(sprite_path: String) -> void:
	texture = load(sprite_path)
```

並把 `aim_at` 換成：

```gdscript
## 真美術是有上下之分的人與建築，整張旋轉會讓塔朝左開火時上下顛倒。
## 2D 的正解是水平翻轉，不是旋轉。rotation 保持 0。
func aim_at(target_position: Vector2) -> void:
	flip_h = target_position.x < position.x
```

`rotation` 純屬裝飾，投射物是從塔的座標生成的，不吃它。

- [ ] **Step 6: 讓場景讀每階的圖並在升級時換圖**

`game/level/battle_scene.gd`：在 `var _hud: BattleHud = null` 之後加入

```gdscript
## 每座塔上次畫出來的等級。升級換圖靠它偵測，與 HUD 只在值變動時才寫 Label
## 是同一個手法——每幀無條件重載一張 128px 的圖是白燒的。
var _shown_tower_levels: Dictionary = {}   ## tower id -> int
```

在 `_sync_views()` 中，把建立與更新塔 view 的那一段換成：

```gdscript
	for tower: Tower in _sim.world.towers:
		if not _tower_views.has(tower.id):
			var view := TowerViewScript.new() as TowerView
			view.setup(tower.id, _tower_sprite_for(tower), tower.position)
			_view_root.add_child(view)
			_tower_views[tower.id] = view
			_shown_tower_levels[tower.id] = tower.level
		elif _shown_tower_levels.get(tower.id, 0) != tower.level:
			_shown_tower_levels[tower.id] = tower.level
			(_tower_views[tower.id] as TowerView).set_sprite(_tower_sprite_for(tower))
```

在移除 view 的迴圈裡，`_tower_views.erase(view_id)` 之後加上：

```gdscript
			_shown_tower_levels.erase(view_id)
```

並在 `_find_tower_view_owner` 之後加入：

```gdscript
## 塔的等級自 1 起算，對應 levels 陣列的索引 level - 1——與 BuildSystem 一致。
func _tower_sprite_for(tower: Tower) -> String:
	var levels: Array = _registry.towers[tower.tower_id]["levels"]
	return levels[tower.level - 1]["sprite"]
```

- [ ] **Step 7: 匯入並執行全套件**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: **228** 個測試全部 PASS（227 + `test_no_tower_keeps_a_top_level_sprite`），exit 0。

- [ ] **Step 8: 靜態檢查與冒煙**

```bash
godot --headless --path . --check-only --script game/level/battle_scene.gd
godot --headless --path . --check-only --script game/views/tower_view.gd
godot --headless --path . --quit-after 2000
```

Expected: `--check-only` 無輸出；冒煙 exit 0，輸出中沒有 `SCRIPT ERROR`、`Invalid`、`Nil`、`Parse Error`。

畫面上不會有塔——headless 沒有人按鍵——這是正確的。

- [ ] **Step 9: 提交**

```bash
git add -A data/ i18n/strings.csv tests/test_data_integrity.gd \
        game/views/tower_view.gd game/level/battle_scene.gd game/assets/
git commit -m "feat(data): 銃樓與獵寮取代佔位塔，圖改為每階一張"
```

---

### Task 2: BuildMenuOptions 純函式

**Files:**
- Create: `ui/build_menu_options.gd`
- Test: `tests/ui/test_build_menu_options.gd`

**Interfaces:**
- Consumes: `WorldState`（`build_slots_by_id`、`available_towers`、`tower_defs`、`towers`、`gold`、`sell_refund_ratio`）
- Produces:
  - `BuildMenuOptions.KIND_BUILD` / `KIND_UPGRADE` / `KIND_SELL`
  - `BuildMenuOptions.for_slot(world: WorldState, slot_id: int) -> Array[Dictionary]`

**這個任務把選單裡真正的決策搬到測得到的地方。** 畫面那層抓不到錯是 B3a 的教訓；買不買得起、有沒有下一級、退款多少都是會出錯而且玩家會發現的東西。

- [ ] **Step 1: 寫失敗的測試**

Create `tests/ui/test_build_menu_options.gd`:

```gdscript
extends GdUnitTestSuite

## 建塔選單顯示什麼，是一批真正的決策——買不買得起、有沒有下一級、退款多少。
## 寫在 Control 裡就沒有任何測試守得到，所以抽成純函式在這裡釘住。

const SLOT_POS := Vector2(400, 200)

func _make_world() -> WorldState:
	var world := WorldState.new()
	world.tower_defs = {
		&"musket_tower": {
			"id": "musket_tower",
			"name_key": "tower.musket_tower.name",
			"damage_type": "physical",
			"icon": "res://game/assets/chapter01/icon_tower_musket.png",
			"levels": [
				{"cost": 70,  "damage": 18.0, "attack_range": 200.0, "fire_interval": 1.2,
				 "projectile_speed": 700.0, "splash_radius": 0.0, "on_hit_effects": [],
				 "sprite": "res://game/assets/chapter01/tower_musket_t1.png"},
				{"cost": 130, "damage": 30.0, "attack_range": 210.0, "fire_interval": 1.1,
				 "projectile_speed": 700.0, "splash_radius": 0.0, "on_hit_effects": [],
				 "sprite": "res://game/assets/chapter01/tower_musket_t2.png"},
			],
		},
		&"hunter_tower": {
			"id": "hunter_tower",
			"name_key": "tower.hunter_tower.name",
			"damage_type": "physical",
			"icon": "res://game/assets/chapter01/icon_tower_hunter.png",
			"levels": [
				{"cost": 50, "damage": 7.0, "attack_range": 130.0, "fire_interval": 0.9,
				 "projectile_speed": 620.0, "splash_radius": 0.0, "on_hit_effects": ["chill"],
				 "sprite": "res://game/assets/chapter01/tower_hunter_t1.png"},
			],
		},
	}
	world.available_towers = [&"musket_tower", &"hunter_tower"] as Array[StringName]
	world.sell_refund_ratio = 0.75
	world.gold = 200
	var slot := BuildSlot.new()
	slot.position = SLOT_POS
	world.add_build_slot(slot)
	return world

func _slot(world: WorldState) -> BuildSlot:
	return world.build_slots[0]

## 在建塔點上放一座指定塔種與等級的塔
func _place_tower(world: WorldState, tower_id: StringName, level: int) -> Tower:
	var tower := Tower.new()
	tower.tower_id = tower_id
	tower.level = level
	tower.position = SLOT_POS
	world.add_tower(tower)
	_slot(world).occupied_by = tower.id
	return tower

func test_no_selection_returns_nothing() -> void:
	var world := _make_world()
	assert_array(BuildMenuOptions.for_slot(world, 0)).has_size(0)

func test_unknown_slot_returns_nothing() -> void:
	var world := _make_world()
	assert_array(BuildMenuOptions.for_slot(world, 99999)).override_failure_message(
		"找不到的建塔點不該讓選單畫出東西，也不該當掉"
	).has_size(0)

func test_an_empty_slot_lists_every_available_tower() -> void:
	var world := _make_world()
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_array(options).has_size(2)
	for option: Dictionary in options:
		assert_str(option["kind"]).is_equal("build")

func test_build_options_carry_the_second_tower_correctly() -> void:
	# 刻意檢查第二筆：寫死 available_towers[0] 的實作會被這條抓到
	var world := _make_world()
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	var second: Dictionary = options[1]
	assert_str(second["tower_id"]).override_failure_message(
		"第二筆必須是 available_towers 的第二種，不是第一種"
	).is_equal("hunter_tower")
	assert_int(second["cost"]).override_failure_message(
		"造價必須取該塔一級的 cost"
	).is_equal(50)
	assert_str(second["icon"]).contains("icon_tower_hunter")
	assert_str(second["name_key"]).is_equal("tower.hunter_tower.name")

func test_build_options_carry_the_one_based_choice_index() -> void:
	# 選單按下去要翻成 InputAction.choose_tower(n)，n 自 1 起算。
	# 把這個對應放在這裡而不是 Control 裡，才有測試守得到。
	var world := _make_world()
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_int(options[0]["choice_index"]).is_equal(1)
	assert_int(options[1]["choice_index"]).override_failure_message(
		"第二種塔的 choice_index 必須是 2"
	).is_equal(2)

func test_unaffordable_towers_are_still_listed_but_marked() -> void:
	# 買不起要列出來玩家才知道有這個選項；擋不擋是 BuildSystem 的事，不是選單的。
	var world := _make_world()
	world.gold = 60
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_array(options).override_failure_message(
		"買不起不代表不顯示"
	).has_size(2)
	assert_bool(options[0]["affordable"]).override_failure_message(
		"銃樓 70 而金幣 60，應標為買不起"
	).is_false()
	assert_bool(options[1]["affordable"]).override_failure_message(
		"獵寮 50 而金幣 60，應標為買得起"
	).is_true()

func test_an_occupied_slot_offers_upgrade_and_sell() -> void:
	var world := _make_world()
	_place_tower(world, &"musket_tower", 1)
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_array(options).has_size(2)
	assert_str(options[0]["kind"]).is_equal("upgrade")
	assert_str(options[1]["kind"]).is_equal("sell")
	assert_int(options[0]["cost"]).override_failure_message(
		"升級費必須是下一級的 cost"
	).is_equal(130)

func test_a_maxed_tower_offers_no_upgrade() -> void:
	# 升到最高階：選單不該再顯示升級瓣
	var world := _make_world()
	_place_tower(world, &"musket_tower", 2)   # musket 在測試資料裡只有兩階
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_array(options).has_size(1)
	assert_str(options[0]["kind"]).override_failure_message(
		"已達最高階時只剩賣出"
	).is_equal("sell")

func test_a_single_tier_tower_offers_no_upgrade() -> void:
	# 另一條路徑：這種塔本來就只有一階。與升滿是不同的成因，兩者都要釘。
	var world := _make_world()
	_place_tower(world, &"hunter_tower", 1)
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_array(options).has_size(1)
	assert_str(options[0]["kind"]).is_equal("sell")

func test_an_unaffordable_upgrade_is_still_listed_but_marked() -> void:
	var world := _make_world()
	world.gold = 100
	_place_tower(world, &"musket_tower", 1)
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_bool(options[0]["affordable"]).override_failure_message(
		"升級要 130 而金幣 100，應標為買不起但仍列出"
	).is_false()

func test_the_refund_matches_what_selling_actually_pays() -> void:
	# 這一輪價值最高的測試。退款的算法在 BuildSystem 與選單各有一份
	# （ui/ 的分層守衛不允許選單認識 BuildSystem），兩者漂移時
	# 玩家會看到「賣出 +52」而實際只回 45——除非有一條測試同時看兩邊。
	var world := _make_world()
	var tower := _place_tower(world, &"musket_tower", 2)

	var shown_refund: int = BuildMenuOptions.for_slot(world, _slot(world).id)[1]["refund"]

	var gold_before := world.gold
	BuildSystem.apply(world, GameIntent.sell(tower.id))
	var actually_paid := world.gold - gold_before

	assert_int(shown_refund).override_failure_message(
		"選單顯示的退款 %d 與實際退的 %d 不一致" % [shown_refund, actually_paid]
	).is_equal(actually_paid)
	assert_int(actually_paid).override_failure_message(
		"退款不該是 0，否則這條測試在比較兩個零"
	).is_greater(0)
```

最後一條的第二個斷言不是多餘的：兩邊都回 0 的實作會通過第一個斷言。

- [ ] **Step 2: 執行測試確認失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests -c
```

Expected: FAIL，識別字 `BuildMenuOptions` 未定義。

- [ ] **Step 3: 實作**

Create `ui/build_menu_options.gd`:

```gdscript
class_name BuildMenuOptions
extends RefCounted

## 建塔選單要顯示哪些選項。
##
## 純靜態函式，與 input/ 的翻譯器同一個模式——因為這裡面是真正的決策
## （買不買得起、有沒有下一級、退款多少），寫在 Control 裡就沒有測試守得到，
## 而畫面那層抓不到錯是 B3a 的教訓。
##
## Control 只負責把回傳的陣列畫出來。

const KIND_BUILD := &"build"
const KIND_UPGRADE := &"upgrade"
const KIND_SELL := &"sell"

static func for_slot(world: WorldState, slot_id: int) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if slot_id == 0:
		return options
	var slot: BuildSlot = world.build_slots_by_id.get(slot_id)
	if slot == null:
		return options

	if slot.occupied_by == 0:
		_append_build_options(options, world)
	else:
		_append_tower_options(options, world, slot.occupied_by)
	return options

static func _append_build_options(options: Array[Dictionary], world: WorldState) -> void:
	for i in world.available_towers.size():
		var tower_id: StringName = world.available_towers[i]
		var def: Dictionary = world.tower_defs.get(tower_id, {})
		if def.is_empty():
			continue
		var cost := int(def["levels"][0]["cost"])
		options.append({
			"kind": KIND_BUILD,
			"tower_id": String(tower_id),
			"name_key": String(def["name_key"]),
			"icon": String(def["icon"]),
			"cost": cost,
			# 按下去要翻成 choose_tower(n)，n 自 1 起算。這個對應放在這裡
			# 而不是 Control 裡，才有測試守得到。
			"choice_index": i + 1,
			"affordable": world.gold >= cost,
		})

static func _append_tower_options(options: Array[Dictionary], world: WorldState, tower_entity_id: int) -> void:
	var tower := _find_tower(world, tower_entity_id)
	if tower == null:
		return
	var def: Dictionary = world.tower_defs.get(tower.tower_id, {})
	if def.is_empty():
		return
	var levels: Array = def["levels"]

	# 等級自 1 起算，所以「下一級」的索引就是 level。等於 size() 表示已達最高階。
	if tower.level < levels.size():
		var cost := int(levels[tower.level]["cost"])
		options.append({
			"kind": KIND_UPGRADE,
			"cost": cost,
			"affordable": world.gold >= cost,
		})

	options.append({
		"kind": KIND_SELL,
		"refund": _refund_for(def, tower.level, world.sell_refund_ratio),
	})

static func _find_tower(world: WorldState, entity_id: int) -> Tower:
	for tower: Tower in world.towers:
		if tower.id == entity_id:
			return tower
	return null

## 與 BuildSystem 的退款算法必須逐字元一致。
##
## 理想上兩處共用同一段程式，但 ui/ 的分層守衛禁止這一層認識 BuildSystem，
## 而那條守衛正是攔住 UI 繞過 signal 直接動核心系統的東西——為了省四行而放寬它，
## 換到的遠不如失去的。
##
## 代價是這四行有兩份。撐住這個決定的是
## test_the_refund_matches_what_selling_actually_pays：它同時看選單顯示的金額
## 與實際賣出後金幣的增量。沒有那條測試的話這個決定不成立。
static func _refund_for(def: Dictionary, level: int, ratio: float) -> int:
	var invested := 0
	for i in level:
		invested += int(def["levels"][i]["cost"])
	return floori(float(invested) * ratio)
```

- [ ] **Step 4: 執行全套件確認通過**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: **239** 個測試全部 PASS（228 + 11 新增），exit 0。

- [ ] **Step 5: 驗證退款一致性測試真的會咬人**

暫時把 `_refund_for` 的 `floori` 改成 `ceili`，重跑套件。

Expected: `test_the_refund_matches_what_selling_actually_pays` 失敗。

（`invested` 為 200、ratio 0.75 時 150.0 剛好整除，`ceili` 與 `floori` 相同——**若沒有失敗，改用一個會產生小數的比例（例如把測試世界的 `sell_refund_ratio` 暫時設成 0.7）再試一次**，並在報告中說明你實際用了什麼。）

還原後重跑確認全綠。

- [ ] **Step 6: 提交**

```bash
git add ui/build_menu_options.gd ui/build_menu_options.gd.uid \
        tests/ui/test_build_menu_options.gd tests/ui/test_build_menu_options.gd.uid
git commit -m "feat(ui): 新增 BuildMenuOptions，把選單的決策搬到測得到的地方"
```

---

### Task 3: BuildMenu

**Files:**
- Create: `ui/build_menu.tscn`、`ui/build_menu.gd`

**Interfaces:**
- Consumes: `BuildMenuOptions` 回傳的陣列
- Produces:
  - `BuildMenu extends CanvasLayer`
  - signal `option_chosen(option_index: int)`、`option_hovered(option_index: int)`、`option_unhovered`
  - `BuildMenu.show_options(options: Array[Dictionary], center: Vector2) -> void`
  - `BuildMenu.hide_menu() -> void`

**這個任務不接線。** 選單建好但還沒掛進場景，Task 5 才接。

- [ ] **Step 1: 寫場景**

Create `ui/build_menu.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://ui/build_menu.gd" id="1_menu"]

[node name="BuildMenu" type="CanvasLayer"]
script = ExtResource("1_menu")
```

**只有一個根節點是刻意的。** 按鈕由程式生成並以絕對座標加為 `CanvasLayer` 的子節點——環形排列用程式算比用錨點自然，數量自然跟著資料走，而且完全沒有看不見的容器，B3a 那個「空白間隔吃掉點擊」的問題從結構上就不存在。

- [ ] **Step 2: 寫腳本**

Create `ui/build_menu.gd`:

```gdscript
class_name BuildMenu
extends CanvasLayer

## 建塔選單。
##
## 只讀 BuildMenuOptions 算好的陣列來畫；要讓事情發生只發 signal，由 battle_scene
## 翻成與鍵盤相同的 InputAction。決策全部在 BuildMenuOptions 裡，這裡只有版面。
##
## 選項沿建塔點下方的半圓弧分布，不是整圈：最上排的建塔點在 y=200，整圈半徑 100
## 會把最上面那一瓣推到 y≈45，而 HUD 橫幅佔了畫面上緣約 120。下半圓從結構上避開
## 這個衝突，也不會蓋住建塔點本身或蓋好的塔。

signal option_chosen(option_index: int)
signal option_hovered(option_index: int)
signal option_unhovered

const RADIUS := 100.0
const BUTTON_SIZE := Vector2(110.0, 110.0)

## 相鄰兩瓣的夾角。以正下方為中心左右展開。
const ARC_STEP := deg_to_rad(60.0)

## 正下方。Godot 的畫面座標 y 向下，所以 +90 度是下方。
const ARC_CENTER := PI * 0.5

func show_options(options: Array[Dictionary], center: Vector2) -> void:
	_clear()
	var count := options.size()
	if count == 0:
		return
	for i in count:
		var button := _make_button(options[i], i)
		# 以正下方為中心左右展開：i 的中位數落在 ARC_CENTER 上
		var angle := ARC_CENTER + (float(i) - float(count - 1) * 0.5) * ARC_STEP
		button.position = center + Vector2(cos(angle), sin(angle)) * RADIUS - BUTTON_SIZE * 0.5
		add_child(button)

func hide_menu() -> void:
	_clear()

func _clear() -> void:
	for child in get_children():
		child.queue_free()

func _make_button(option: Dictionary, index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = BUTTON_SIZE
	button.size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	_style_button(button, option)
	button.pressed.connect(func() -> void: option_chosen.emit(index))
	button.mouse_entered.connect(func() -> void: option_hovered.emit(index))
	button.mouse_exited.connect(func() -> void: option_unhovered.emit())
	return button

func _style_button(button: Button, option: Dictionary) -> void:
	match StringName(option["kind"]):
		BuildMenuOptions.KIND_BUILD:
			button.icon = load(option["icon"])
			# 造價是純數字，沒有可翻譯的內容。硬做成 %d 的格式 key 會讓兩個語系
			# 完全相同，而那正好違反 B3a 的 test_the_two_locales_actually_differ。
			button.text = str(option["cost"])
			button.tooltip_text = tr(option["name_key"])
		BuildMenuOptions.KIND_UPGRADE:
			button.text = tr("menu.upgrade_format") % int(option["cost"])
		BuildMenuOptions.KIND_SELL:
			button.text = tr("menu.sell_format") % int(option["refund"])

	# 買不起仍然顯示，只是變暗——玩家要知道有這個選項存在。
	# 擋不擋是 BuildSystem 的事，不是選單的（沿用 B2 的分工）。
	var affordable: bool = option.get("affordable", true)
	button.modulate = Color(1, 1, 1, 1) if affordable else Color(0.55, 0.55, 0.55, 0.85)
```

`focus_mode = FOCUS_NONE` 是刻意的：選單的按鈕是短暫存在的，讓它們搶走焦點會在關閉後留下一個指向已釋放節點的焦點。HUD 的按鈕維持可聚焦（M4 的手把導航要用），這裡不需要。

- [ ] **Step 3: 擴充分層守衛的節點檢查**

`tests/test_ui_layer.gd` 的 `NODE_EXPECTATIONS` 只涵蓋 HUD。新增一條測試確認選單場景載入得了：

```gdscript
const BUILD_MENU_SCENE := "res://ui/build_menu.tscn"

func test_the_build_menu_scene_loads_and_exposes_its_signals() -> void:
	var packed: PackedScene = load(BUILD_MENU_SCENE)
	assert_bool(packed != null).override_failure_message(
		"載入不了 %s；.tscn 是手寫的，格式錯誤只會在這裡或人工驗收現形" % BUILD_MENU_SCENE
	).is_true()
	var menu := packed.instantiate()
	for signal_name: String in ["option_chosen", "option_hovered", "option_unhovered"]:
		assert_bool(menu.has_signal(signal_name)).override_failure_message(
			"選單少了 signal %s，battle_scene 接不上" % signal_name
		).is_true()
	menu.free()
```

既有的 `test_ui_scripts_do_not_bypass_the_signal_boundary` 會自動涵蓋新的 `.gd` 檔——不需要改它。

- [ ] **Step 4: 匯入並執行全套件**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: **240** 個測試全部 PASS（239 + 1 新增），exit 0。

Godot 可能在匯入時替 `.tscn` 補上 `uid`；那是正常的，照樣提交。

- [ ] **Step 5: 驗證分層守衛涵蓋了新檔案**

暫時在 `ui/build_menu.gd` 裡加一行 `var _leak := _world.pending_intents`（不是註解，要是真的程式行），重跑套件。

Expected: `test_ui_scripts_do_not_bypass_the_signal_boundary` 失敗，訊息指名 `ui/build_menu.gd`。

移除後重跑確認全綠。

- [ ] **Step 6: 提交**

```bash
git add ui/build_menu.gd ui/build_menu.gd.uid ui/build_menu.tscn tests/test_ui_layer.gd
git commit -m "feat(ui): 新增環形建塔選單"
```

---

### Task 4: 射程圈與建塔點的真美術

**Files:**
- Create: `game/views/range_circle.gd`
- Modify: `game/views/build_slot_view.gd`
- Delete: `game/assets/placeholder_slot.png`

**Interfaces:**
- Produces:
  - `RangeCircle extends Node2D`，`show_at(world_position: Vector2, radius: float)`、`hide_circle()`
  - `BuildSlotView.set_occupied(occupied: bool)`

兩者都是還沒接線的表現層元件，Task 5 才用。

- [ ] **Step 1: 寫射程圈**

Create `game/views/range_circle.gd`:

```gdscript
class_name RangeCircle
extends Node2D

## 塔的射程提示。
##
## 射程是世界單位的半徑畫在世界座標上，所以它是 Node2D 而不是 Control——
## ui/ 那一層不碰世界座標。要畫在哪、畫多大由 battle_scene 決定。

const FILL := Color(1.0, 0.88, 0.30, 0.10)
const OUTLINE := Color(1.0, 0.88, 0.30, 0.55)
const OUTLINE_WIDTH := 3.0
const SEGMENTS := 64

var _radius: float = 0.0

func _ready() -> void:
	visible = false

func show_at(world_position: Vector2, radius: float) -> void:
	position = world_position
	_radius = radius
	visible = radius > 0.0
	queue_redraw()

func hide_circle() -> void:
	visible = false

func _draw() -> void:
	if _radius <= 0.0:
		return
	draw_circle(Vector2.ZERO, _radius, FILL)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, SEGMENTS, OUTLINE, OUTLINE_WIDTH)
```

- [ ] **Step 2: 建塔點改用真美術**

把 `game/views/build_slot_view.gd` 整個換成：

```gdscript
class_name BuildSlotView
extends Sprite2D

## 建塔點的視覺。B3b 起是真美術（prop_buildsite），不再是白方塊。
##
## 有塔時隱藏：塔蓋在同一個座標上，標記留著只會從塔底下露出來。
##
## 選取提示改成輕微提亮而不是染黃——真美術染色會變濁，而且選中的主要回饋
## 其實是選單打開與射程圈出現，標記只需要一點呼應。

const COLOR_IDLE := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_SELECTED := Color(1.30, 1.25, 1.05, 1.0)

var slot_id: int = 0

var _occupied: bool = false
var _selected: bool = false

func setup(p_slot_id: int, sprite_path: String, slot_position: Vector2) -> void:
	slot_id = p_slot_id
	texture = load(sprite_path)
	position = slot_position
	modulate = COLOR_IDLE

func set_selected(selected: bool) -> void:
	_selected = selected
	modulate = COLOR_SELECTED if selected else COLOR_IDLE

func set_occupied(occupied: bool) -> void:
	_occupied = occupied
	visible = not occupied
```

- [ ] **Step 3: 刪掉不再被引用的置換圖**

```bash
git rm game/assets/placeholder_slot.png game/assets/placeholder_slot.png.import
```

- [ ] **Step 4: 匯入、執行全套件、靜態檢查**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
godot --headless --path . --check-only --script game/views/range_circle.gd
godot --headless --path . --check-only --script game/views/build_slot_view.gd
```

Expected: **240** 個測試全部 PASS，測試數不變（本任務只動表現層）。`--check-only` 無輸出。

**此時 `battle_scene.gd` 仍然指向已刪除的 `placeholder_slot.png`**，所以冒煙測試會壞——那是預期的，Task 5 才改場景。本任務不跑 `--quit-after`。

- [ ] **Step 5: 提交**

```bash
git add game/views/range_circle.gd game/views/range_circle.gd.uid \
        game/views/build_slot_view.gd game/assets/
git commit -m "feat(game): 新增射程圈，建塔點改用真美術"
```

---

### Task 5: 接線與人工驗收

**Files:**
- Modify: `game/level/battle_scene.gd`

**Interfaces:**
- Consumes: `BuildMenu`、`BuildMenuOptions`、`RangeCircle`、`BuildSlotView.set_occupied`、`InteractionController`、`InputAction`

本任務是 B3b 唯一走人工驗收的部分。**Step 7 的人工驗收需要有人看著螢幕，不要嘗試自己執行。**

- [ ] **Step 1: 常數與欄位**

在 `game/level/battle_scene.gd` 的 `const BattleHudScene` 之後加入：

```gdscript
const BuildMenuScene := preload("res://ui/build_menu.tscn")
const RangeCircleScript := preload("res://game/views/range_circle.gd")
```

把 `const SLOT_SPRITE` 的值改為：

```gdscript
const SLOT_SPRITE := "res://game/assets/chapter01/prop_buildsite.png"
```

在 `var _shown_tower_levels` 之後加入：

```gdscript
var _build_menu: BuildMenu = null
var _range_circle: RangeCircle = null

## 選單目前畫的是哪一批選項。重算與重建按鈕只在這個簽章變動時做——
## 每幀重建按鈕是白燒的配置，而 gold 一變（每次擊殺）買得起與否就可能翻轉。
var _menu_signature: Array = []
var _menu_options: Array[Dictionary] = []
```

- [ ] **Step 2: 在 `_ready()` 掛載**

在 `_hud.speed_pressed.connect(...)` 之後加入：

```gdscript

	_build_menu = BuildMenuScene.instantiate() as BuildMenu
	add_child(_build_menu)
	_build_menu.option_chosen.connect(_on_menu_option_chosen)
	_build_menu.option_hovered.connect(_on_menu_option_hovered)
	_build_menu.option_unhovered.connect(_on_menu_option_unhovered)

	_range_circle = RangeCircleScript.new() as RangeCircle
	_view_root.add_child(_range_circle)
```

- [ ] **Step 3: 每幀更新選單與標記**

把 `_update_slot_highlight()` 換成下面這一段，並在 `_process` 中維持同一個呼叫位置：

```gdscript
## 每幀更新選取提示、佔用狀態與選單。建塔點是個位數，直接全部設定即可。
func _update_slot_views() -> void:
	for view: BuildSlotView in _slot_views.values():
		view.set_selected(view.slot_id == _controller.selected_slot_id)
		var slot: BuildSlot = _sim.world.build_slots_by_id.get(view.slot_id)
		view.set_occupied(slot != null and slot.occupied_by != 0)
	_update_build_menu()

## 選單是選取狀態的純函數：選取變了就開、關、移動。控制器裡沒有任何選單狀態，
## 所以「點空白處關閉選單」是免費的——select_at 命中不到建塔點時本來就會清成 0。
func _update_build_menu() -> void:
	var signature := _current_menu_signature()
	if signature == _menu_signature:
		return
	_menu_signature = signature

	var slot_id := _controller.selected_slot_id
	_menu_options = BuildMenuOptions.for_slot(_sim.world, slot_id)
	if _menu_options.is_empty():
		_build_menu.hide_menu()
		_range_circle.hide_circle()
		return

	var slot: BuildSlot = _sim.world.build_slots_by_id.get(slot_id)
	_build_menu.show_options(_menu_options, slot.position)
	_show_range_for_selection(slot)

## 選單只在這幾個值變動時重算。gold 在裡面，因為買得起與否會隨擊殺翻轉。
func _current_menu_signature() -> Array:
	var slot_id := _controller.selected_slot_id
	var occupied := 0
	var level := 0
	var slot: BuildSlot = _sim.world.build_slots_by_id.get(slot_id)
	if slot != null:
		occupied = slot.occupied_by
		var tower := _find_tower_view_owner(occupied)
		if tower != null:
			level = tower.level
	return [slot_id, _sim.world.gold, occupied, level]
```

注意 `_find_tower_view_owner` 是既有的函式，接受實體 id 並回傳 `Tower`；名字是為 view 取的，但做的事正合用。

- [ ] **Step 4: 射程圈與選單的 signal**

在 `_on_hud_speed_pressed` 之後加入：

```gdscript
## 選中有塔的建塔點時顯示現有射程；空位不顯示，要滑過某一瓣才預覽。
func _show_range_for_selection(slot: BuildSlot) -> void:
	if slot.occupied_by == 0:
		_range_circle.hide_circle()
		return
	var tower := _find_tower_view_owner(slot.occupied_by)
	if tower == null:
		_range_circle.hide_circle()
		return
	_range_circle.show_at(tower.position, tower.attack_range)

## 選單的按鈕與鍵盤走同一條路：翻成 InputAction 餵給控制器。
## B2 已經有測試守著「動作 → 意圖 → 路由器」那條路。
func _on_menu_option_chosen(option_index: int) -> void:
	if option_index < 0 or option_index >= _menu_options.size():
		return
	var option: Dictionary = _menu_options[option_index]
	match StringName(option["kind"]):
		BuildMenuOptions.KIND_BUILD:
			_controller.handle(InputAction.choose_tower(int(option["choice_index"])), _sim.world)
		BuildMenuOptions.KIND_UPGRADE:
			_controller.handle(InputAction.simple(InputAction.UPGRADE), _sim.world)
		BuildMenuOptions.KIND_SELL:
			_controller.handle(InputAction.simple(InputAction.SELL), _sim.world)

## 滑過某一瓣時預覽那個選擇會帶來的射程。觸控沒有 hover，依已定案的觸控模型
## 點下去就建、不預覽——射程圈預覽是滑鼠獨有的額外好處。
func _on_menu_option_hovered(option_index: int) -> void:
	if option_index < 0 or option_index >= _menu_options.size():
		return
	var slot: BuildSlot = _sim.world.build_slots_by_id.get(_controller.selected_slot_id)
	if slot == null:
		return
	var option: Dictionary = _menu_options[option_index]
	match StringName(option["kind"]):
		BuildMenuOptions.KIND_BUILD:
			var levels: Array = _registry.towers[StringName(option["tower_id"])]["levels"]
			_range_circle.show_at(slot.position, float(levels[0]["attack_range"]))
		BuildMenuOptions.KIND_UPGRADE:
			var tower := _find_tower_view_owner(slot.occupied_by)
			if tower == null:
				return
			var next_levels: Array = _registry.towers[tower.tower_id]["levels"]
			_range_circle.show_at(tower.position, float(next_levels[tower.level]["attack_range"]))
		_:
			pass

func _on_menu_option_unhovered() -> void:
	var slot: BuildSlot = _sim.world.build_slots_by_id.get(_controller.selected_slot_id)
	if slot == null:
		_range_circle.hide_circle()
		return
	_show_range_for_selection(slot)
```

- [ ] **Step 5: 執行全套件與靜態檢查**

```bash
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
godot --headless --path . --check-only --script game/level/battle_scene.gd
```

Expected: **240** 個測試全部 PASS，測試數不變。**數字有變就代表有東西壞了或被誤刪。** `--check-only` 無輸出。

- [ ] **Step 6: headless 冒煙**

```bash
godot --headless --path . --quit-after 2000
```

Expected: exit 0，輸出中沒有 `SCRIPT ERROR`、`Invalid`、`Nil` 或 `Parse Error`。

畫面上不會有塔也不會有選單——headless 沒有人點擊——這是正確的。

- [ ] **Step 7: 人工驗收（需要人看著螢幕，不要自己執行）**

```bash
godot --path .
```

1. 建塔點顯示為 `prop_buildsite` 的真美術，不是白方塊
2. 點建塔點 → 選單在該點**下方**展開，兩瓣：銃樓 70、獵寮 50
3. 金幣不足時該瓣變暗，但仍然列出
4. 滑鼠停在某一瓣 → 畫出該塔一級的射程圈；停在按鈕上會顯示塔名 tooltip
5. 點一瓣 → 蓋出塔，**建塔點標記消失**，金幣減少
6. 點已有塔的建塔點 → 選單顯示升級與賣出，並畫出現有射程圈
7. 滑鼠停在升級瓣 → 射程圈變成下一級的大小
8. 升級 → **塔的外觀換成下一階的圖**（槍手 → 排槍 → 稜堡）
9. 銃樓升到三級後 → 選單不再顯示升級瓣
10. 獵寮蓋好後 → 選單只有賣出，沒有升級瓣
11. 賣出 → 塔消失、標記重新出現、金幣回一部分，且**金額與選單上顯示的一致**
12. 點空白處 → 選單關閉、射程圈消失
13. 快捷鍵 `1` `2` `U` `S` 仍然可用，與選單並存
14. 塔朝畫面左側的敵人開火時**沒有上下顛倒**（改用水平翻轉的驗收）

第 9 與第 10 項是「沒有下一級就不顯示升級」的兩種成因，兩種都要驗。

- [ ] **Step 8: 提交**

```bash
git add game/level/battle_scene.gd
git commit -m "feat(game): 接上建塔選單與射程圈"
```

---

## B3b 完成後

交付物：用 UI 就能建塔、升級、賣出，看得到射程，塔是第一章設計的銃樓與獵寮並且升級會換外觀。

後續：

| 項目 | 去向 |
|---|---|
| 駐守單位系統（柵欄出兵擋路）、路徑陷阱、地面 DoT | 獨立子里程碑，三者一起 |
| 長按查看詳細數值，與它需要的 `translate()` 簽名改動 | 同上或之後 |
| 敵人美術替換（六種敵人的圖已在 `game/assets/chapter01/`） | 內容子里程碑 |
| 勝敗結算、波次系統、敵人生成移入 tick | 獨立子里程碑 |
| 潮汐機制、平民撤離、貨幣正名為「銀」 | 第一章內容 |
| 第四種塔「稜堡砲位」與最小射程 | M3 |
| 字型子集化、觸控目標實體尺寸、選單幾何在不同長寬比下的表現 | M2 實機 |
