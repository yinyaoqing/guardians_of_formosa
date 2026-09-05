extends GdUnitTestSuite

## ui/ 層的方向規則守衛，以及手寫 .tscn 的煙霧測試。
##
## 方向規則是：ui/ 可以讀 WorldState 與 BattleSim 來顯示，但要讓事情發生只能發
## signal，由 battle_scene 翻成 InputAction 餵給 InteractionController。
##
## 這條規則違反起來毫不費力——`sim.paused = not sim.paused` 一行就好，而且會動。
## 但那條路上一條測試都沒有，而兩條路遲早會漂移。所以用測試盯著。

const UI_ROOT := "res://ui"
const HUD_SCENE := "res://ui/battle_hud.tscn"

## 出現這些字串即代表 ui/ 繞過了 signal，自己動手做事
const FORBIDDEN_PATTERNS := [
	"BuildSystem",
	"queue_intent(",
	"InputAction",
]

## HUD 的節點路徑。.tscn 是盲寫的，路徑打錯只會在人工驗收才發現，
## 而人工驗收是這個里程碑最貴的一步。
const REQUIRED_NODE_PATHS := [
	"Root",
	"Root/Top",
	"Root/Top/GoldLabel",
	"Root/Top/LivesLabel",
	"Root/Top/LevelNameLabel",
	"Root/Top/PauseButton",
	"Root/Top/SpeedButton",
]

## 逐行掃描並跳過註解行。ui/battle_hud.gd 的說明文件註解本身會提到
## InputAction 兩次（用來解釋為什麼不能繞過 signal），若整份原始碼一次比對，
## 守衛會咬自己的文件註解。掃描的目的是抓「真的呼叫/引用了禁止對象的程式碼」，
## 註解本身不是程式碼，跳過它才讓守衛的名字名副其實。
##
## 代價：寫在程式碼行尾的註解（`foo() # InputAction`）仍然會被掃到，因為
## 整行只要不是「以 # 開頭」就照樣比對。這是可接受的不精確，見規格 §9。
func test_ui_scripts_do_not_bypass_the_signal_boundary() -> void:
	var scripts := _collect_gd_files(UI_ROOT)
	assert_int(scripts.size()).override_failure_message(
		"在 %s 底下找不到任何 .gd 檔，守衛測試形同虛設" % UI_ROOT
	).is_greater(0)

	for path: String in scripts:
		var source := FileAccess.get_file_as_string(path)
		for line: String in source.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for pattern: String in FORBIDDEN_PATTERNS:
				assert_bool(line.contains(pattern)).override_failure_message(
					"%s 含有 '%s'。ui/ 要讓事情發生只能發 signal，由 battle_scene 翻成 InputAction。\n" % [path, pattern] +
					"繞過去的話，那條路上一條測試都沒有——而 B2 已經有測試守著 signal 那條路。"
				).is_false()

func test_the_hud_scene_loads_and_has_every_expected_node() -> void:
	var packed: PackedScene = load(HUD_SCENE)
	assert_bool(packed != null).override_failure_message(
		"載入不了 %s；.tscn 是手寫的，格式錯誤只會在這裡或人工驗收現形" % HUD_SCENE
	).is_true()

	var hud := packed.instantiate()
	for node_path: String in REQUIRED_NODE_PATHS:
		assert_bool(hud.has_node(node_path)).override_failure_message(
			"HUD 缺少節點 %s。腳本的 @onready 依這些路徑取節點，路徑錯了就是執行期 null。" % node_path
		).is_true()
	hud.free()

func test_the_hud_exposes_both_signals() -> void:
	var packed: PackedScene = load(HUD_SCENE)
	var hud := packed.instantiate()
	for signal_name: String in ["pause_pressed", "speed_pressed"]:
		assert_bool(hud.has_signal(signal_name)).override_failure_message(
			"HUD 少了 signal %s，battle_scene 接不上" % signal_name
		).is_true()
	hud.free()

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
