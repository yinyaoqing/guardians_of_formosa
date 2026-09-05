extends GdUnitTestSuite

## 貼圖尺寸上限測試。精緻度規格 §3「建議的自動檢查」第三項，
## 上限來自美術聖經 §5.1：敵人／士兵 ≤128×128、塔（含底座）≤192×192。
##
## 為什麼這條要自動擋：超規格的貼圖不會讓遊戲壞掉，只會**安靜地吃記憶體**——
## 而記憶體是架構規格 §9 的 M2 閘門項目。等到 M2 實機測出問題才回頭找是哪幾張
## 圖超規，成本遠高於一次 CI。
##
## 幀數檢查（單一動作 6–8 幀）尚未實作，理由見 data/art_limits.json。

const LIMITS_PATH := "res://data/art_limits.json"
const ASSETS_DIR := "res://game/assets"

var _by_prefix: Dictionary = {}
var _default_max: int = 128
var _exempt_prefixes: Array = []


func before_test() -> void:
	var text := FileAccess.get_file_as_string(LIMITS_PATH)
	assert_str(text).override_failure_message("讀不到 %s" % LIMITS_PATH).is_not_empty()

	var data: Variant = JSON.parse_string(text)
	assert_bool(data is Dictionary).override_failure_message("尺寸上限 JSON 格式錯誤").is_true()

	_by_prefix = data.get("max_size_by_prefix", {})
	_default_max = int(data.get("_default_max_size", 128))
	_exempt_prefixes = data.get("exempt_prefixes", [])


func max_size_for(file_name: String) -> int:
	# 取最長的相符前綴，避免將來加入更細的前綴時被短前綴搶先。
	var best_len := -1
	var best := _default_max
	for prefix: String in _by_prefix:
		if file_name.begins_with(prefix) and prefix.length() > best_len:
			best_len = prefix.length()
			best = int(_by_prefix[prefix])
	return best


func _collect(dir_path: String, out: PackedStringArray) -> void:
	# 遞迴：資產會分章節放在子目錄（game/assets/chapter01/…），只掃頂層會讓閘門空轉。
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := "%s/%s" % [dir_path, name]
		if dir.current_is_dir():
			_collect(full, out)
		elif name.ends_with(".png"):
			var exempt := false
			for prefix: String in _exempt_prefixes:
				if name.begins_with(prefix):
					exempt = true
					break
			if not exempt:
				out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _png_paths() -> PackedStringArray:
	var out := PackedStringArray()
	_collect(ASSETS_DIR, out)
	return out


func test_limits_json_is_loaded() -> void:
	# 上限表空掉的話，下面的測試會全部「通過」而毫無意義。
	assert_int(_by_prefix.size()).override_failure_message(
		"尺寸上限表是空的——這會讓尺寸檢查形同虛設"
	).is_greater(0)


func test_prefix_matching_prefers_longest() -> void:
	# max_size_for 的正確性本身要驗，否則上限套錯了也看不出來。
	assert_int(max_size_for("tower_musket_t3.png")).is_equal(192)
	assert_int(max_size_for("icon_silver.png")).is_equal(64)
	assert_int(max_size_for("enemy_ironman.png")).is_equal(_default_max)
	# 更長的例外前綴必須勝過短前綴，否則 enemy_warjunk 會被套上士兵的 128 上限。
	assert_int(max_size_for("enemy_warjunk.png")).is_equal(192)
	assert_int(max_size_for("prop_settlement.png")).is_equal(192)
	assert_int(max_size_for("prop_buildsite.png")).is_equal(128)


func test_all_assets_within_size_limit() -> void:
	for path: String in _png_paths():
		var name := path.get_file()
		var image := Image.load_from_file(path)
		assert_object(image).override_failure_message("讀不到 %s" % path).is_not_null()
		var limit := max_size_for(name)
		var w := image.get_width()
		var h := image.get_height()
		assert_bool(w <= limit and h <= limit).override_failure_message(
			"%s 為 %dx%d，超過上限 %dx%d（美術聖經 §5.1）" % [name, w, h, limit, limit]
		).is_true()


func test_detects_oversized_asset() -> void:
	# 與色票檢查同樣的紀律：沒有這一項，資產目錄為空時上面的測試也會通過。
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var tmp := "user://_size_probe.png"
	assert_int(image.save_png(tmp)).is_equal(OK)

	var probe := Image.load_from_file(tmp)
	var limit := max_size_for("enemy_probe.png")
	assert_bool(probe.get_width() > limit).override_failure_message(
		"刻意放大的 256x256 沒有被判定超規——尺寸檢查沒有真的在檢查"
	).is_true()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
