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
		assert_int(levels.size()).override_failure_message(
			"塔 %s 的 levels 陣列是空的，無法建造" % tower_id
		).is_greater(0)
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

	var status_effects_dir := DirAccess.open("res://data/status_effects")
	var status_effect_file_count := 0
	for file_name in status_effects_dir.get_files():
		if file_name.ends_with(".json"):
			status_effect_file_count += 1
	assert_int(_registry.status_effects.size()).override_failure_message(
		"data/status_effects 底下有 %d 個 .json 檔，但註冊表只有 %d 筆——代表有重複的 id 欄位互相覆蓋" % [status_effect_file_count, _registry.status_effects.size()]
	).is_equal(status_effect_file_count)

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
	for dir_path: String in ["res://data/enemies", "res://data/towers", "res://data/status_effects"]:
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

## name_key 沒有必填檢查的話，缺漏只會在 UI 上顯示空白文字才會被發現。
## magnitude 刻意不列入必填：暈眩效果本來就不使用 magnitude，
## 這個例外已經由 test_magnitude_is_positive_except_for_stun 涵蓋。
func test_every_status_effect_has_required_fields() -> void:
	var required := ["id", "name_key", "kind", "duration"]
	for effect_id: StringName in _registry.status_effects:
		var def: Dictionary = _registry.status_effects[effect_id]
		for field: String in required:
			var has_field: bool = def.has(field) and str(def[field]) != ""
			assert_bool(has_field).override_failure_message(
				"狀態效果 %s 缺少必填欄位 %s" % [effect_id, field]
			).is_true()

## 若某個 kind 的效果全部被刪除，用 kind 過濾再迴圈的測試（例如減速的 magnitude
## 範圍檢查）會因為迴圈根本沒有執行而「無害地」通過，等於默默失去整個 kind 的覆蓋。
## 這個測試確保四種 kind 都至少有一個已載入的效果在把關。
func test_every_effect_kind_has_at_least_one_definition() -> void:
	var known_kinds := [
		StatusEffect.KIND_SLOW,
		StatusEffect.KIND_STUN,
		StatusEffect.KIND_DOT,
		StatusEffect.KIND_ARMOR_BREAK,
	]
	var seen_kinds: Array = []
	for effect_id: StringName in _registry.status_effects:
		var kind := StringName(_registry.status_effects[effect_id]["kind"])
		if not seen_kinds.has(kind):
			seen_kinds.append(kind)
	for kind: StringName in known_kinds:
		assert_bool(seen_kinds.has(kind)).override_failure_message(
			("這個里程碑應該交付全部四種狀態效果 kind，但找不到任何 kind 為 %s 的效果。" % kind) +
			"如果之後要刻意拿掉某個 kind，請刻意更新這個測試，而不是讓它默默地讓其他用 kind 過濾的測試（例如減速的 magnitude 範圍檢查）失去覆蓋、無害地通過。"
		).is_true()

func test_every_tower_level_declares_projectile_fields() -> void:
	var required := ["projectile_speed", "splash_radius", "on_hit_effects"]
	for tower_id: StringName in _registry.towers:
		for level_def: Dictionary in _registry.towers[tower_id]["levels"]:
			for field: String in required:
				assert_bool(level_def.has(field)).override_failure_message(
					"塔 %s 的某個等級缺少投射物欄位 %s" % [tower_id, field]
				).is_true()

func test_projectiles_outrun_every_enemy() -> void:
	# 命中保證的前提：投射物速度必須高於所有敵人，否則追不上。
	# 這裡拿來比較的是 base_speed（資料裡的 speed 欄位），這個檢查成立的前提是
	# 狀態效果目前永遠不會把敵人的衍生速度推得比 base_speed 更高——只有減速，
	# 沒有加速。未來若加入類似「狂暴/加速」的狀態效果，這個檢查就會失效，
	# 需要改成拿「可能達到的最高速度」而不是 base_speed 來比較。
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
			var has_field: bool = meta.has(field) and str(meta[field]) != ""
			assert_bool(has_field).override_failure_message(
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
		var available_towers: Array = _registry.levels[level_id]["available_towers"]
		assert_int(available_towers.size()).override_failure_message(
			"關卡 %s 的 available_towers 是空的，無法建造任何塔，關卡無法通關" % level_id
		).is_greater(0)
		for tower_id in available_towers:
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
