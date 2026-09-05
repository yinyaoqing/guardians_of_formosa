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

	# CSV 的值裡沒有任何 0-9（都是 %d 這種格式碼，不是字面數字），但畫面上
	# 實際畫出來的是「金幣 200」「生命 20」「2 倍速」這種代入後的結果，數字
	# 一定會上畫面。M2 若照著 CSV 內容做字型子集化，字面上抓不到數字，
	# 這條測試若只查 CSV 字元集，會眼睜睜看著數字變成豆腐框卻依然全綠——
	# 所以要獨立於 CSV 之外，直接對照真正的字型檔案。
	for digit in range(10):
		var code := String.num_int64(digit).unicode_at(0)
		assert_bool(font.has_char(code)).override_failure_message(
			"字型缺少數字字符 '%d'。CSV 裡沒有字面數字（只有 %%d 格式碼），\n" % digit +
			"但代入後的畫面一定有數字，字型子集化若只依 CSV 字元集會漏掉這些字符。"
		).is_true()

## 規格 §7.1 要求整合性測試同時掃描兩個方向：data/ 的 name_key（上面那條）
## 與程式碼裡的 tr("...") 字面呼叫（這一條）。原本只做了第一個方向——把
## ui/battle_hud.gd 的 tr("hud.gold_format") 打錯成 tr("hud.gold_fromat")，
## 不會讓任何測試變紅，英文/中文語系下都只是把 key 本身畫到螢幕上，
## 要等人工驗收才會發現。
##
## 侷限：tr(some_variable) 沒辦法用字面掃描抓出實際傳進去的字串。目前唯一
## 這樣呼叫的地方是 ui/battle_hud.gd 的 tr(level_name_key)（關卡名稱），
## 它已經被上面的 test_data_name_keys_exist_in_the_csv 從 data/ 端蓋到——
## name_key 本來就是從 JSON 讀出來、再原封不動傳給 tr() 的同一個字串。
## 這裡只做得到「找出所有 tr("字面字串")」，不是總覆蓋，特此記錄而非假裝完整。
func test_ui_and_game_tr_keys_exist_in_the_csv() -> void:
	var rows := _read_csv()
	var regex := RegEx.create_from_string("tr\\(\\s*\"([^\"]+)\"\\s*\\)")

	var scripts: Array[String] = []
	scripts.append_array(_collect_gd_files("res://ui"))
	scripts.append_array(_collect_gd_files("res://game"))

	var found_any := false
	for path: String in scripts:
		var source := FileAccess.get_file_as_string(path)
		for m: RegExMatch in regex.search_all(source):
			var key := m.get_string(1)
			found_any = true
			assert_bool(rows.has(key)).override_failure_message(
				"%s 呼叫 tr(\"%s\")，但這個 key 在 %s 裡找不到。\n" % [path, key, CSV_PATH] +
				"這不會有任何執行期錯誤——畫面上會直接顯示這串 key 本身，兩個語系都一樣。"
			).is_true()

	assert_bool(found_any).override_failure_message(
		"在 res://ui 與 res://game 底下找不到任何 tr(\"字面字串\") 呼叫，守衛形同虛設"
	).is_true()

## §6：format 字串本身活在翻譯檔裡，代表譯者編輯的是程式碼要拿去 % 運算的語法。
## hud.speed_format 的 en 值若被改成 x%（從 %dx 挪動或拿掉 %d），
## tr("hud.speed_format") % speed 會在每次速度變動時丟出執行期格式錯誤——
## 而且只有英文語系會炸，開發機多半設 zh_TW，不會有人看到任何測試失敗。
func test_format_specifiers_agree_across_locales() -> void:
	var rows := _read_csv()
	assert_int(rows.size()).override_failure_message(
		"CSV 一個 key 都沒讀到，守衛形同虛設"
	).is_greater(0)

	var specifier_regex := RegEx.create_from_string("%[-+0# ]*\\d*(?:\\.\\d+)?[a-zA-Z%]")

	for key: String in rows.keys():
		var reference_specifiers := ""
		var reference_locale := ""
		for locale: String in LOCALES:
			var text: String = rows[key][locale]
			var found: Array[String] = []
			for m: RegExMatch in specifier_regex.search_all(text):
				found.append(m.get_string())
			var joined := ", ".join(found)
			if reference_locale == "":
				reference_specifiers = joined
				reference_locale = locale
				continue
			assert_str(joined).override_failure_message(
				"key '%s' 的 %% 格式碼在語系間不一致：%s 是 [%s]，%s 是 [%s]。\n" % [key, reference_locale, reference_specifiers, locale, joined] +
				"format 字串存在翻譯檔裡，這裡改壞了只會在執行期、且只在該語系下才會炸。"
			).is_equal(reference_specifiers)

## §7.1 的另一半：en 不能只是「跟 key 不一樣」，還必須「跟 zh_TW 的譯文不一樣」。
## 只驗前半的話，一次複製貼上把 en 欄整欄填成中文會通過所有既有檢查——
## tr() 在 en 語系下回傳的的確不是 key 本身——卻完全沒有做出真正的英文版。
func test_the_two_locales_actually_differ() -> void:
	var rows := _read_csv()
	assert_int(rows.size()).override_failure_message(
		"CSV 一個 key 都沒讀到，守衛形同虛設"
	).is_greater(0)

	for key: String in rows.keys():
		var zh_value: String = rows[key]["zh_TW"]
		var en_value: String = rows[key]["en"]
		assert_bool(en_value != zh_value).override_failure_message(
			"key '%s' 的 en 欄跟 zh_TW 欄一模一樣（都是 '%s'）。\n" % [key, zh_value] +
			"tr() 在 en 語系下回傳的確不是 key 本身，既有測試會全線通過，卻沒有真的做出英文版。"
		).is_true()

func _collect_gd_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			found.append(root.path_join(file_name))
	for sub_dir in dir.get_directories():
		found.append_array(_collect_gd_files(root.path_join(sub_dir)))
	return found

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
