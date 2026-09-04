extends GdUnitTestSuite

## 把資料錯誤變成測試失敗，而不是執行到那一關才黑屏。
## 這條防線在 AI 協作下投報率極高：改完數值跑測試就知道有沒有改壞。

var _registry: DataRegistry

func before_test() -> void:
	_registry = DataRegistry.new()
	_registry.load_from_disk()

func test_at_least_one_enemy_is_loaded() -> void:
	assert_int(_registry.enemies.size()).is_greater(0)

func test_at_least_one_tower_is_loaded() -> void:
	assert_int(_registry.towers.size()).is_greater(0)

func test_every_enemy_has_required_fields() -> void:
	var required := ["id", "name_key", "hp", "speed", "armor", "magic_resist", "bounty", "sprite"]
	for enemy_id: StringName in _registry.enemies:
		var def: Dictionary = _registry.enemies[enemy_id]
		for field: String in required:
			assert_bool(def.has(field)).override_failure_message(
				"敵人 %s 缺少必填欄位 %s" % [enemy_id, field]
			).is_true()

func test_every_enemy_has_sane_numbers() -> void:
	for enemy_id: StringName in _registry.enemies:
		var def: Dictionary = _registry.enemies[enemy_id]
		assert_float(def["hp"]).override_failure_message(
			"敵人 %s 的 hp 必須為正" % enemy_id
		).is_greater(0.0)
		assert_float(def["speed"]).override_failure_message(
			"敵人 %s 的 speed 必須為正" % enemy_id
		).is_greater(0.0)
		assert_float(def["armor"]).is_between(0.0, 0.95)
		assert_float(def["magic_resist"]).is_between(0.0, 0.95)

func test_every_tower_level_has_required_fields() -> void:
	var required := ["cost", "damage", "attack_range", "fire_interval"]
	for tower_id: StringName in _registry.towers:
		var def: Dictionary = _registry.towers[tower_id]
		assert_bool(def.has("levels")).is_true()
		for level_def: Dictionary in def["levels"]:
			for field: String in required:
				assert_bool(level_def.has(field)).override_failure_message(
					"塔 %s 的某個等級缺少欄位 %s" % [tower_id, field]
				).is_true()

func test_tower_upgrade_costs_increase() -> void:
	for tower_id: StringName in _registry.towers:
		var levels: Array = _registry.towers[tower_id]["levels"]
		for i in range(1, levels.size()):
			assert_int(int(levels[i]["cost"])).override_failure_message(
				"塔 %s 第 %d 級的造價必須高於前一級" % [tower_id, i + 1]
			).is_greater(int(levels[i - 1]["cost"]))

func test_tower_damage_types_are_known() -> void:
	var known := [DamageSystem.PHYSICAL, DamageSystem.MAGIC, DamageSystem.TRUE_DAMAGE]
	for tower_id: StringName in _registry.towers:
		var damage_type := StringName(_registry.towers[tower_id]["damage_type"])
		assert_bool(known.has(damage_type)).override_failure_message(
			"塔 %s 的傷害類型 %s 不是已知類型" % [tower_id, damage_type]
		).is_true()

func test_every_referenced_sprite_path_exists() -> void:
	for enemy_id: StringName in _registry.enemies:
		var path: String = _registry.enemies[enemy_id]["sprite"]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(
			"敵人 %s 引用的貼圖不存在: %s" % [enemy_id, path]
		).is_true()
	for tower_id: StringName in _registry.towers:
		var path: String = _registry.towers[tower_id]["sprite"]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(
			"塔 %s 引用的貼圖不存在: %s" % [tower_id, path]
		).is_true()
