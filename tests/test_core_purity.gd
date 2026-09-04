extends GdUnitTestSuite

## 自動化驗證 CLAUDE.md 硬規則 #1：core/ 不得依賴 Node 或場景。
## 這條規則一旦破壞，core/ 就無法在 headless 下單元測試，
## 整個分層架構的價值就消失了——所以用測試把它釘死。

const CORE_ROOT := "res://core"

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
	var scripts := _collect_gd_files(CORE_ROOT)
	assert_int(scripts.size()).override_failure_message(
		"在 %s 底下找不到任何 .gd 檔，守衛測試形同虛設" % CORE_ROOT
	).is_greater(0)

	for path: String in scripts:
		var source := FileAccess.get_file_as_string(path)
		for pattern: String in FORBIDDEN_PATTERNS:
			assert_bool(source.contains(pattern)).override_failure_message(
				"%s 含有被禁止的 Node 依賴 '%s'。core/ 必須是純邏輯，見 CLAUDE.md 規則 #1。" % [path, pattern]
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
