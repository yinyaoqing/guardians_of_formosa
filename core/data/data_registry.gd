class_name DataRegistry
extends RefCounted

## JSON 資料載入與 id 查表。
## 使用 FileAccess / DirAccess / JSON——這些是引擎類別但不是 Node，
## 因此不違反「core/ 不依賴 Node」的規則。

var enemies: Dictionary = {}   ## StringName -> Dictionary
var towers: Dictionary = {}    ## StringName -> Dictionary

func load_from_disk(root: String = "res://data") -> void:
	enemies = _load_dir(root.path_join("enemies"))
	towers = _load_dir(root.path_join("towers"))

## 依 id 建出一個 Enemy 實體。id 引用失敗時直接報錯——
## 靜默回傳 null 會讓錯誤在很遠的地方才炸開。
func make_enemy(enemy_id: StringName, path_id: StringName) -> Enemy:
	assert(enemies.has(enemy_id), "找不到敵人定義: %s" % enemy_id)
	var def: Dictionary = enemies[enemy_id]
	var enemy := Enemy.new()
	enemy.enemy_id = enemy_id
	enemy.hp = def["hp"]
	enemy.max_hp = def["hp"]
	enemy.base_speed = def["speed"]
	enemy.base_armor = def["armor"]
	enemy.base_magic_resist = def["magic_resist"]
	enemy.reset_derived_stats()
	enemy.bounty = def["bounty"]
	enemy.path_id = path_id
	return enemy

func _load_dir(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	assert(dir != null, "找不到資料目錄: %s" % dir_path)
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var full_path := dir_path.path_join(file_name)
		var text := FileAccess.get_file_as_string(full_path)
		var parsed: Variant = JSON.parse_string(text)
		assert(parsed is Dictionary, "JSON 格式錯誤: %s" % full_path)
		var def: Dictionary = parsed
		assert(def.has("id"), "資料檔缺少 id 欄位: %s" % full_path)
		result[StringName(def["id"])] = def
	return result
