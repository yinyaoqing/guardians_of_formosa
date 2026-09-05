extends GdUnitTestSuite

## 色票一致性測試。精緻度規格 §3「建議的自動檢查」第一項，
## 美術聖經 §5.3 要求與資料完整性測試同級：把美術錯誤變成測試失敗。
##
## 為什麼這條防線必要：AI 生成的資產風格漂移是必然發生的，而**人眼在單張圖上
## 看不出漂移，要到十幾張放在一起才發現**，此時已經產出一批廢圖。自動檢查把這個
## 回饋迴圈從幾週縮短到一次 CI。
##
## 色票來自 data/art_palette.json，與 art/scripts/postprocess.py 的量化器共用同一份
## ——兩邊各自寫死會漂開，量化器放行的顏色測試擋掉，或反之。

const PALETTE_PATH := "res://data/art_palette.json"
const ASSETS_DIR := "res://game/assets"

var _allowed: Dictionary = {}
var _exempt_prefixes: Array = []


func before_test() -> void:
	var text := FileAccess.get_file_as_string(PALETTE_PATH)
	assert_str(text).override_failure_message(
		"讀不到色票 %s" % PALETTE_PATH
	).is_not_empty()

	var data: Variant = JSON.parse_string(text)
	assert_bool(data is Dictionary).override_failure_message(
		"色票 JSON 格式錯誤"
	).is_true()

	_allowed = {}
	for section: String in ["palette", "skin", "outline"]:
		var group: Dictionary = data.get(section, {})
		for name: String in group:
			_allowed[Color(group[name]).to_rgba32()] = "%s/%s" % [section, name]
	_exempt_prefixes = data.get("exempt_prefixes", [])


func _png_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(ASSETS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".png"):
			var exempt := false
			for prefix: String in _exempt_prefixes:
				if name.begins_with(prefix):
					exempt = true
					break
			if not exempt:
				out.append("%s/%s" % [ASSETS_DIR, name])
		name = dir.get_next()
	dir.list_dir_end()
	return out


## 回傳越界色的清單；空陣列代表通過。
func offending_colors(path: String) -> Array:
	var image := Image.load_from_file(path)
	if image == null:
		return ["讀不到圖片"]
	var seen := {}
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var key := Color(c.r, c.g, c.b, 1.0).to_rgba32()
			if not _allowed.has(key) and not seen.has(key):
				seen[key] = true
	return seen.keys()


func test_palette_json_is_loaded() -> void:
	# 色票本身空掉的話，下面的測試會全部「通過」而毫無意義。
	assert_int(_allowed.size()).override_failure_message(
		"色票是空的——這會讓色票檢查形同虛設"
	).is_greater(10)


func test_all_assets_use_only_palette_colors() -> void:
	for path: String in _png_paths():
		var bad: Array = offending_colors(path)
		assert_int(bad.size()).override_failure_message(
			"%s 含 %d 種色票外的顏色，第一個是 %s" % [
				path, bad.size(),
				"#%06X" % (int(bad[0]) >> 8) if bad.size() > 0 else "",
			]
		).is_equal(0)


func test_detects_deliberately_injected_off_palette_color() -> void:
	# 美術聖經 §8 的 A4 完成判準：「測試能抓出刻意混入的色票外資產」。
	# 沒有這一項，前一個測試在資產目錄為空時也會通過，看起來像過了其實什麼都沒驗。
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color("#FF00FF"))  # 洋紅，§4.2 明列的負面色
	var tmp := "user://_palette_probe.png"
	assert_int(image.save_png(tmp)).is_equal(OK)

	var bad: Array = offending_colors(tmp)
	assert_int(bad.size()).override_failure_message(
		"刻意混入的洋紅沒有被抓出來——色票檢查沒有真的在檢查"
	).is_greater(0)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
