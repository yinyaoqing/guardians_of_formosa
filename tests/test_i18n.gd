extends GdUnitTestSuite

## i18n 管線的完整性守衛。
##
## 「加了 key 忘了補英文」不是可能發生，是必然發生，而且不會有任何執行期錯誤——
## 英文語系下就只是顯示出 key 本身。這種腐化只有測試抓得到。

const CSV_PATH := "res://i18n/strings.csv"
const LOCALES: Array[String] = ["zh_TW", "en"]
const DATA_ROOT := "res://data"

var _saved_locale := ""

func before() -> void:
	_saved_locale = TranslationServer.get_locale()

func after() -> void:
	# TranslationServer 是行程全域的。不還原會汙染同一個行程裡的其他測試套件——
	# 與 InputMap 是同一類全域狀態陷阱。
	TranslationServer.set_locale(_saved_locale)

## 讀 CSV，回傳 key -> {locale: 譯文}
func _read_csv() -> Dictionary:
	var rows: Dictionary = {}
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		return rows
	var header := file.get_csv_line()
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < header.size() or line[0] == "":
			continue
		var by_locale: Dictionary = {}
		for i in range(1, header.size()):
			by_locale[header[i]] = line[i]
		rows[line[0]] = by_locale
	return rows

func test_the_csv_exists_and_has_both_locales() -> void:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	assert_bool(file != null).override_failure_message(
		"找不到 %s" % CSV_PATH
	).is_true()
	if file == null:
		return    # GdUnit 的斷言不會中止執行，後面會對 null 取值

	# get_csv_line() 回傳 PackedStringArray，轉成 Array 再交給 assert_array
	var header := Array(file.get_csv_line())
	for locale: String in LOCALES:
		assert_array(header).override_failure_message(
			"CSV 標頭缺少語系欄 %s；標頭是 %s" % [locale, header]
		).contains([locale])

func test_every_key_resolves_in_every_locale() -> void:
	# 這條同時抓兩種腐化：語系沒登記進 project.godot（tr 回傳 key 本身），
	# 以及某個語系的欄位是空的。
	var rows := _read_csv()
	assert_int(rows.size()).override_failure_message(
		"CSV 一個 key 都沒讀到，守衛形同虛設"
	).is_greater(0)

	for locale: String in LOCALES:
		TranslationServer.set_locale(locale)
		for key: String in rows.keys():
			var translated := TranslationServer.translate(key)
			assert_bool(translated != key).override_failure_message(
				"語系 %s 下 key '%s' 沒有翻譯——回傳的是 key 本身，代表語系未登記或該欄為空" % [locale, key]
			).is_true()
			assert_bool(translated != "").override_failure_message(
				"語系 %s 下 key '%s' 的譯文是空字串" % [locale, key]
			).is_true()

func test_data_name_keys_exist_in_the_csv() -> void:
	# data/ 裡的 name_key 是唯一會從 JSON 一路帶到畫面上的 i18n key。
	# 資料裡新增一個關卡卻忘了補譯文，就是在遊戲裡顯示出 "level.level_02.name"。
	var rows := _read_csv()
	var found_any := false
	for path: String in _collect_json_files(DATA_ROOT):
		var text := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text)
		if not (parsed is Dictionary):
			continue
		var dict: Dictionary = parsed
		if not dict.has("name_key"):
			continue
		found_any = true
		var key: String = dict["name_key"]
		assert_bool(rows.has(key)).override_failure_message(
			"%s 的 name_key '%s' 在 %s 裡找不到" % [path, key, CSV_PATH]
		).is_true()
	assert_bool(found_any).override_failure_message(
		"在 %s 底下找不到任何帶 name_key 的 JSON，守衛形同虛設" % DATA_ROOT
	).is_true()

func test_the_default_font_covers_every_character_used() -> void:
	# Godot 預設字型不含中日韓字符，實測 has_char("熱") 為 false。
	# 沒設字型或設錯路徑，畫面上就是一排豆腐框，而那要到人工驗收才看得見。
	var font_path: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	assert_bool(font_path != "").override_failure_message(
		"未設定 gui/theme/custom_font，所有中文都會是豆腐框"
	).is_true()

	var font: Font = load(font_path)
	assert_bool(font != null).override_failure_message(
		"載入不了字型 %s" % font_path
	).is_true()

	var rows := _read_csv()
	for key: String in rows.keys():
		for locale: String in LOCALES:
			var text: String = rows[key][locale]
			for i in text.length():
				var code := text.unicode_at(i)
				assert_bool(font.has_char(code)).override_failure_message(
					"字型缺少字符 '%s'（來自 %s 的 %s 欄）" % [text[i], key, locale]
				).is_true()

func _collect_json_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			found.append(root.path_join(file_name))
	for sub_dir in dir.get_directories():
		found.append_array(_collect_json_files(root.path_join(sub_dir)))
	return found
