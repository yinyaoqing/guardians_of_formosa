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
		assert_bool(def["bounty"] >= 0.0).override_failure_message(
			"敵人 %s 的 bounty 不可為負" % enemy_id
		).is_true()

func test_every_tower_level_has_required_fields() -> void:
	var required := ["cost", "damage", "attack_range", "fire_interval"]
	for tower_id: StringName in _registry.towers:
		var def: Dictionary = _registry.towers[tower_id]
		assert_bool(def.has("levels")).is_true()
		var levels: Array = def["levels"]
		assert_int(levels.size()).override_failure_message(
			"塔 %s 的 levels 陣列是空的，無法建造" % tower_id
		).is_greater(0)
		for level_def: Dictionary in levels:
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

## DataRegistry._load_dir 用 id 欄位當字典的 key，兩個檔案宣告同一個 id
## 就會互相覆蓋,而且誰贏由作業系統的目錄列舉順序決定。
## 用「檔案數 == 註冊表筆數」偵測這種情況。
func test_no_duplicate_ids_across_data_files() -> void:
	var enemies_dir := DirAccess.open("res://data/enemies")
	var enemy_file_count := 0
	for file_name in enemies_dir.get_files():
		if file_name.ends_with(".json"):
			enemy_file_count += 1
	assert_int(_registry.enemies.size()).override_failure_message(
		"data/enemies 底下有 %d 個 .json 檔，但註冊表只有 %d 筆——代表有重複的 id 欄位互相覆蓋" % [enemy_file_count, _registry.enemies.size()]
	).is_equal(enemy_file_count)

	var towers_dir := DirAccess.open("res://data/towers")
	var tower_file_count := 0
	for file_name in towers_dir.get_files():
		if file_name.ends_with(".json"):
			tower_file_count += 1
	assert_int(_registry.towers.size()).override_failure_message(
		"data/towers 底下有 %d 個 .json 檔，但註冊表只有 %d 筆——代表有重複的 id 欄位互相覆蓋" % [tower_file_count, _registry.towers.size()]
	).is_equal(tower_file_count)

## make_enemy 是下一個任務會直接依賴的入口，之前完全沒有測試覆蓋。
func test_make_enemy_builds_entity_from_data() -> void:
	var def: Dictionary = _registry.enemies[&"orc_grunt"]
	var enemy := _registry.make_enemy(&"orc_grunt", &"main")

	assert_bool(enemy.enemy_id == &"orc_grunt").override_failure_message(
		"make_enemy 建出的 enemy_id 應為 orc_grunt，實際為 %s" % enemy.enemy_id
	).is_true()
	assert_bool(enemy.path_id == &"main").override_failure_message(
		"make_enemy 建出的 path_id 應為 main，實際為 %s" % enemy.path_id
	).is_true()
	assert_float(enemy.hp).is_equal_approx(enemy.max_hp, 0.001)
	assert_float(enemy.hp).is_equal_approx(float(def["hp"]), 0.001)
	assert_float(enemy.speed).is_equal_approx(float(def["speed"]), 0.001)
	assert_float(enemy.armor).is_equal_approx(float(def["armor"]), 0.001)
	assert_float(enemy.magic_resist).is_equal_approx(float(def["magic_resist"]), 0.001)
	assert_int(enemy.bounty).is_equal(int(def["bounty"]))
	assert_bool(enemy.alive).is_true()
	assert_bool(enemy.leaked).is_false()
	assert_float(enemy.distance_along).is_equal_approx(0.0, 0.001)
	assert_int(enemy.blocked_by).is_equal(0)

## 檔名和 id 欄位若脫鉤，程式碼引用時容易對錯檔案。
func test_json_id_matches_filename() -> void:
	for dir_path: String in ["res://data/enemies", "res://data/towers"]:
		var dir := DirAccess.open(dir_path)
		for file_name in dir.get_files():
			if not file_name.ends_with(".json"):
				continue
			var full_path := dir_path.path_join(file_name)
			var text := FileAccess.get_file_as_string(full_path)
			var parsed: Variant = JSON.parse_string(text)
			var def: Dictionary = parsed
			var expected_id := file_name.get_basename()
			var actual_id := str(def["id"])
			assert_bool(expected_id == actual_id).override_failure_message(
				"檔案 %s 的 id 欄位是 %s，與檔名不符（應為 %s）" % [full_path, actual_id, expected_id]
			).is_true()
