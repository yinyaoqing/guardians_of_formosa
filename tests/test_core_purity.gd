extends GdUnitTestSuite

## 自動化驗證 CLAUDE.md 硬規則 #1：core/ 不得依賴 Node 或場景。
## 這條規則一旦破壞，core/ 就無法在 headless 下單元測試，
## 整個分層架構的價值就消失了——所以用測試把它釘死。

const CORE_ROOT := "res://core"
const INPUT_ROOT := "res://input"

## 出現這些字串即代表 core/ 碰到了 Node 或場景系統
const FORBIDDEN_PATTERNS := [
	"extends Node",
	"extends Node2D",
	"extends CanvasItem",
	"extends Control",
	"extends Resource",
	".tscn",
	"get_tree()",
	"get_node(",
	"add_child(",
	"queue_free(",
]

func test_core_scripts_do_not_depend_on_nodes() -> void:
	_assert_layer_is_node_free(CORE_ROOT, "core/")

## input/ 宣稱自己跟 core/ 一樣不碰 Node、可完全 headless 測試——
## 之後要加手把翻譯器，整套論證都建立在這個前提上。原本只掃 core/，
## 這條規則對 input/ 從來沒被驗證過，純粹是靠人讀程式碼相信而已。
func test_input_scripts_do_not_depend_on_nodes() -> void:
	_assert_layer_is_node_free(INPUT_ROOT, "input/")

func _assert_layer_is_node_free(root: String, layer_label: String) -> void:
	var scripts := _collect_gd_files(root)
	assert_int(scripts.size()).override_failure_message(
		"在 %s 底下找不到任何 .gd 檔，守衛測試形同虛設" % root
	).is_greater(0)

	for path: String in scripts:
		var source := FileAccess.get_file_as_string(path)
		for pattern: String in FORBIDDEN_PATTERNS:
			assert_bool(source.contains(pattern)).override_failure_message(
				"%s 含有被禁止的 Node 依賴 '%s'。%s 必須是純邏輯，見 CLAUDE.md 規則 #1。" % [path, pattern, layer_label]
			).is_false()

## 源代碼文本檢查，故意不執行 battle_scene 而檢查它的源碼。
## 因為 headless 測試套件根本不執行場景腳本，所以必須用靜態檢查守住這個架構規則。
## 若不呼叫 configure_for_level，整個世界都不會被配置——資料定義、可用塔種、
## 起始金幣與生命全部缺失，而每項測試仍照常通過。
func test_battle_scene_configures_the_world_for_its_level() -> void:
	var battle_scene_path := "res://game/level/battle_scene.gd"
	var source := FileAccess.get_file_as_string(battle_scene_path)
	assert_bool(source.contains("configure_for_level")).override_failure_message(
		"表現層必須在 WorldState 中注入資料定義，因為 core/ 不讀檔案。\n" +
		"headless 測試套件不執行場景腳本，所以沒有其他測試能抓到這個漏洞。\n" +
		"缺少 configure_for_level() 呼叫會導致整個世界都不會被配置——資料定義、可用塔種、起始金幣與生命全部缺失，同時每項測試都通過。\n" +
		"詳見 CLAUDE.md 分層架構和 tests/test_core_purity.gd 註解。"
	).is_true()

## 同一種問題的另一個實例：MouseKeyboardInput.translate() 每個分支都靠
## process-global 的 InputMap 狀態工作。少了 InputBindings.install()，
## 九個 is_action_pressed() 全部回傳 false，translate() 回傳 null，
## _unhandled_input() 提早結束——遊戲照樣啟動、渲染、生怪，只是完全聽不到
## 任何輸入。沒有錯誤、沒有警告，也沒有測試會失敗：翻譯器自己的測試在
## before_test() 裡就呼叫過 install()，蓋不到「場景忘記呼叫」這個情境。
func test_battle_scene_installs_input_bindings() -> void:
	var battle_scene_path := "res://game/level/battle_scene.gd"
	var source := FileAccess.get_file_as_string(battle_scene_path)
	assert_bool(source.contains("InputBindings.install")).override_failure_message(
		"表現層必須呼叫 InputBindings.install() 註冊 InputMap 動作。\n" +
		"漏掉這一行不會有任何錯誤或警告——遊戲會正常啟動、渲染、生怪，\n" +
		"只是 MouseKeyboardInput.translate() 問到的 is_action_pressed() 全部是 false，\n" +
		"變成一個對所有輸入都沒有反應的關卡。翻譯器測試自己在 before_test() 呼叫\n" +
		"install()，所以抓不到場景忘記呼叫的情況，只有這種原始碼文本檢查抓得到。"
	).is_true()

## 同一種問題的第三個實例：battle_scene.gd 呼叫 _hud.setup(...) 並接上
## pause_pressed 與 speed_pressed 兩個 signal，才能讓 HUD 的按鈕真的做事。
## 少了 setup() 呼叫，_world/_sim 未賦值，HUD 的 _process() 提早 return，
## 金幣與生命的數字永遠不動；少了任一 connect()，對應的按鈕看起來完好、
## 點下去卻毫無反應——鍵盤仍然管用，所以會被誤判成「按鈕本來就是裝飾」，
## 而不是「接線掉了」。headless 測試套件不執行場景腳本，抓不到這種漏接，
## 只有原始碼文本檢查抓得到。
func test_battle_scene_wires_up_the_hud() -> void:
	var battle_scene_path := "res://game/level/battle_scene.gd"
	var source := FileAccess.get_file_as_string(battle_scene_path)
	assert_bool(source.contains("_hud.setup(")).override_failure_message(
		"battle_scene.gd 沒有呼叫 _hud.setup()。\n" +
		"少了這一步，HUD 的 _world/_sim 都是 null，_process() 會提早 return，\n" +
		"金幣、生命、關卡名稱全部不會更新，但遊戲仍會正常啟動、渲染、生怪。"
	).is_true()
	assert_bool(source.contains("pause_pressed.connect")).override_failure_message(
		"battle_scene.gd 沒有接上 _hud.pause_pressed。\n" +
		"暫停鈕會正常顯示、正常可點，點下去卻毫無反應——鍵盤的暫停鍵仍然管用，\n" +
		"所以這個漏洞會被誤判成「按鈕是裝飾」而不是「接線掉了」，人工驗收很容易漏掉。"
	).is_true()
	assert_bool(source.contains("speed_pressed.connect")).override_failure_message(
		"battle_scene.gd 沒有接上 _hud.speed_pressed。\n" +
		"倍速鈕會正常顯示、正常可點，點下去卻毫無反應，同上一條，鍵盤仍然管用，\n" +
		"讀不出這是接線漏掉而不是設計如此。"
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
