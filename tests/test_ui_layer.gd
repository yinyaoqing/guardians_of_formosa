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
const BUILD_MENU_SCENE := "res://ui/build_menu.tscn"

## 出現這些字串即代表 ui/ 繞過了 signal，自己動手做事。
## core/systems/ 底下每一個系統類別都要列進來——只列 BuildSystem 漏掉了
## DamageSystem、MovementSystem、ProjectileSystem、StatusSystem、
## TargetingSystem，這五個一樣是「ui/ 應該永遠不會直接呼叫」的核心系統。
const FORBIDDEN_PATTERNS := [
	"BuildSystem",
	"DamageSystem",
	"MovementSystem",
	"ProjectileSystem",
	"StatusSystem",
	"TargetingSystem",
	"queue_intent(",
	"pending_intents",
	"InputAction",
]

## 抓「ui/ 持有的 WorldState / BattleSim 參照被直接改欄位」——
## `sim.paused = not sim.paused` 一行就是這種違規，FORBIDDEN_PATTERNS
## 的字串比對抓不到它，因為它不呼叫任何系統類別、也不碰 InputAction。
##
## 作法：先掃出型別標成 WorldState 或 BattleSim 的變數/參數名稱
## （例如 `var _world: WorldState`、`p_sim: BattleSim`），再對這些名稱
## 個別產生「<name>.<field> 後面接賦值運算子」的比對。
##
## 刻意排除的假陽性：
##  - `_world = p_world`：對參照本身賦值，是合法的初始化，正規表達式
##    要求名稱後面立刻接 `.`，這裡沒有點號，不會誤觸。
##  - `_shown_gold = _world.gold`：賦值目標是 `_shown_gold`，`_world.gold`
##    只出現在等號右邊、後面沒有再接賦值運算子，不會誤觸。
##  - `_sim.paused == x`：比較用的 `==`，用 `(?!=)` 排除單一 `=` 後面
##    緊接著另一個 `=` 的情況；`!=`、`<=`、`>=` 因為第一個字元不是
##    `=`/`+`/`-`/`*`/`/`，同樣不會匹配。
##  - 複合賦值 `+=`、`-=`、`*=`、`/=` 必須抓到，所以明列在運算子群組裡。
## B3b 起 ui/build_menu_options.gd 會從 world.towers / world.build_slots_by_id
## 拉出活的 Tower、BuildSlot 參照來讀（例如 tower.level）。這些型別跟
## WorldState/BattleSim 一樣是「持有就可能被誤改欄位」的對象——
## `tower.level += 1` 不含任何系統類別名稱，FORBIDDEN_PATTERNS 抓不到，
## 只有這裡的寫入偵測抓得到。Enemy、Projectile 目前 ui/ 還沒碰，
## 一併列入是預防下一次真的碰到時忘記補這條守衛。
const HELD_REFERENCE_TYPES := ["WorldState", "BattleSim", "Tower", "BuildSlot", "Enemy", "Projectile"]
var _held_ref_regex := RegEx.create_from_string("(\\w+)\\s*:\\s*(?:%s)\\b" % "|".join(HELD_REFERENCE_TYPES))

## HUD 每個節點的路徑、型別與 mouse_filter 期望值。.tscn 是盲寫的，路徑打錯、
## 型別改錯只會在人工驗收才發現，而人工驗收是這個里程碑最貴的一步。
##
## 型別要單獨檢查，不能只靠 has_node()：把 GoldLabel 從 Label 改成
## RichTextLabel，路徑仍然存在，has_node() 照樣是 true，但腳本的
## `@onready var _gold_label: Label = $Root/Top/GoldLabel` 型別不符會在
## _ready() 之前直接報錯中止，PauseButton/SpeedButton 的 connect() 全部不會
## 執行——兩顆按鈕看起來都在，其實都是死的。
##
## mouse_filter 是另一次真實修復留下的守衛：Root/Top/SpacerLeft/SpacerRight
## 若退回預設值，SpacerLeft/SpacerRight（純 Control，預設 STOP）會擋住頂欄
## 下方建塔格的點擊；兩個 Button 則相反，必須維持會攔截的 STOP，
## 否則按暫停會連帶把正下方的建塔格也點掉。數值取自
## .superpowers/sdd/hud-mouse-filter-report.md 的實測結果。
const NODE_EXPECTATIONS := {
	"Root": {"type": "MarginContainer", "mouse_filter": Control.MOUSE_FILTER_IGNORE},
	"Root/Top": {"type": "HBoxContainer", "mouse_filter": Control.MOUSE_FILTER_IGNORE},
	"Root/Top/GoldLabel": {"type": "Label", "mouse_filter": Control.MOUSE_FILTER_IGNORE},
	"Root/Top/LivesLabel": {"type": "Label", "mouse_filter": Control.MOUSE_FILTER_IGNORE},
	"Root/Top/SpacerLeft": {"type": "Control", "mouse_filter": Control.MOUSE_FILTER_IGNORE},
	"Root/Top/LevelNameLabel": {"type": "Label", "mouse_filter": Control.MOUSE_FILTER_IGNORE},
	"Root/Top/SpacerRight": {"type": "Control", "mouse_filter": Control.MOUSE_FILTER_IGNORE},
	"Root/Top/PauseButton": {"type": "Button", "mouse_filter": Control.MOUSE_FILTER_STOP},
	"Root/Top/SpeedButton": {"type": "Button", "mouse_filter": Control.MOUSE_FILTER_STOP},
}

## 逐行掃描並跳過註解行。ui/battle_hud.gd 的說明文件註解本身會提到
## InputAction 兩次（用來解釋為什麼不能繞過 signal），若整份原始碼一次比對，
## 守衛會咬自己的文件註解。掃描的目的是抓「真的呼叫/引用了禁止對象的程式碼」，
## 註解本身不是程式碼，跳過它才讓守衛的名字名副其實。
##
## 代價：寫在程式碼行尾的註解（`foo() # InputAction`）仍然會被掃到，因為
## 整行只要不是「以 # 開頭」就照樣比對。這是可接受的不精確，見規格 §9。
##
## 這個代價還有另一面：整行都是註解的違規呼叫（例如重構後留下的
## `# world.queue_intent(...)`）現在會被跳過而抓不到，修正前的全檔案比對抓得到，
## 規格也記錄過那是「比漏抓好」的取捨。換掉它的理由是：HUD 說明整層方向規則的
## 文件註解，價值高於抓住一行已經被註解掉、不會執行的呼叫——後者本來就該由
## code review 擋下，不需要測試代勞。
func test_ui_scripts_do_not_bypass_the_signal_boundary() -> void:
	var scripts := _collect_gd_files(UI_ROOT)
	assert_int(scripts.size()).override_failure_message(
		"在 %s 底下找不到任何 .gd 檔，守衛測試形同虛設" % UI_ROOT
	).is_greater(0)

	var held_ref_names_seen: Dictionary = {}

	for path: String in scripts:
		var source := FileAccess.get_file_as_string(path)

		var held_ref_names: Dictionary = {}
		for m: RegExMatch in _held_ref_regex.search_all(source):
			held_ref_names[m.get_string(1)] = true
		for name: String in held_ref_names.keys():
			held_ref_names_seen[name] = true
		var write_regexes: Dictionary = {}
		for name: String in held_ref_names.keys():
			write_regexes[name] = RegEx.create_from_string(
				"\\b%s\\.\\w+\\s*(?:\\+=|-=|\\*=|/=|=(?!=))" % name
			)

		for line: String in source.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for pattern: String in FORBIDDEN_PATTERNS:
				assert_bool(line.contains(pattern)).override_failure_message(
					"%s 含有 '%s'。ui/ 要讓事情發生只能發 signal，由 battle_scene 翻成 InputAction。\n" % [path, pattern] +
					"繞過去的話，那條路上一條測試都沒有——而 B2 已經有測試守著 signal 那條路。"
				).is_false()
			for name: String in write_regexes.keys():
				var regex: RegEx = write_regexes[name]
				assert_bool(regex.search(line) != null).override_failure_message(
					"%s 這一行直接改了 %s 的欄位：`%s`。\n" % [path, name, line.strip_edges()] +
					"ui/ 只能讀 WorldState/BattleSim 來顯示，要讓事情發生只能發 signal，\n" +
					"由 battle_scene 翻成 InputAction 餵給 InteractionController——\n" +
					"`sim.paused = not sim.paused` 一行就能繞過去，而且會動，那條路上沒有任何測試守著。"
				).is_false()

	assert_int(held_ref_names_seen.size()).override_failure_message(
		"在 %s 底下找不到任何型別標為 %s 的變數/參數，寫入偵測形同虛設" % [UI_ROOT, ", ".join(HELD_REFERENCE_TYPES)]
	).is_greater(0)

func test_the_hud_scene_loads_and_has_every_expected_node() -> void:
	var packed: PackedScene = load(HUD_SCENE)
	assert_bool(packed != null).override_failure_message(
		"載入不了 %s；.tscn 是手寫的，格式錯誤只會在這裡或人工驗收現形" % HUD_SCENE
	).is_true()

	var hud := packed.instantiate()
	for node_path: String in NODE_EXPECTATIONS.keys():
		var expectation: Dictionary = NODE_EXPECTATIONS[node_path]
		assert_bool(hud.has_node(node_path)).override_failure_message(
			"HUD 缺少節點 %s。腳本的 @onready 依這些路徑取節點，路徑錯了就是執行期 null。" % node_path
		).is_true()
		if not hud.has_node(node_path):
			continue

		var node: Node = hud.get_node(node_path)
		var expected_type: String = expectation["type"]
		assert_str(node.get_class()).override_failure_message(
			"HUD 節點 %s 型別是 %s，預期是 %s。腳本的 @onready 型別標註對不上時，\n" % [node_path, node.get_class(), expected_type] +
			"會在 _ready() 之前直接報錯中止——按鈕的 connect() 全部不會執行，兩顆按鈕看起來都在，其實都是死的。"
		).is_equal(expected_type)

		if node is Control:
			var control: Control = node
			var expected_filter: int = expectation["mouse_filter"]
			assert_int(control.mouse_filter).override_failure_message(
				"HUD 節點 %s 的 mouse_filter 是 %d，預期是 %d。SpacerLeft/SpacerRight 若退回\n" % [node_path, control.mouse_filter, expected_filter] +
				"預設值會攔截點擊，讓頂欄下方的建塔格點不到；PauseButton/SpeedButton 若被改成\n" +
				"不攔截，按暫停會連帶點穿到正下方的建塔格。"
			).is_equal(expected_filter)
	hud.free()

func test_the_hud_exposes_both_signals() -> void:
	var packed: PackedScene = load(HUD_SCENE)
	var hud := packed.instantiate()
	for signal_name: String in ["pause_pressed", "speed_pressed"]:
		assert_bool(hud.has_signal(signal_name)).override_failure_message(
			"HUD 少了 signal %s，battle_scene 接不上" % signal_name
		).is_true()
	hud.free()

func test_the_build_menu_scene_loads_and_exposes_its_signals() -> void:
	var packed: PackedScene = load(BUILD_MENU_SCENE)
	assert_bool(packed != null).override_failure_message(
		"載入不了 %s；.tscn 是手寫的，格式錯誤只會在這裡或人工驗收現形" % BUILD_MENU_SCENE
	).is_true()
	var menu := packed.instantiate()
	for signal_name: String in ["option_chosen", "option_hovered", "option_unhovered"]:
		assert_bool(menu.has_signal(signal_name)).override_failure_message(
			"選單少了 signal %s，battle_scene 接不上" % signal_name
		).is_true()
	menu.free()

## show_options 的結構與 signal 行為。幾何（角度、座標）不驗——那是人工驗收的
## 範圍——但按鈕數量、索引有沒有對上按下去的按鈕、以及「換一批選項後舊按鈕
## 真的消失了」這三件事都測得到，而且都測得便宜。
func test_build_menu_show_options_creates_buttons_and_reports_the_right_index() -> void:
	var menu: BuildMenu = auto_free(BuildMenu.new())

	var three_options: Array[Dictionary] = [
		{"kind": "sell", "refund": 10},
		{"kind": "sell", "refund": 20},
		{"kind": "sell", "refund": 30},
	]
	menu.show_options(three_options, Vector2(400, 200))
	assert_int(menu.get_child_count()).override_failure_message(
		"show_options 給三個選項應該建出三顆按鈕"
	).is_equal(3)

	# 按下中間那顆，option_chosen 帶的必須是 1——這正是「按鈕捕捉到錯的索引」
	# 這種 bug 會現形的地方：捕捉錯了，這裡收到的會是 0 或 2。
	#
	# 用單元素陣列而不是單純的 int 變數來接：GDScript 的 lambda 對外圍區域變數是
	# 「建立當下拷貝一份值」而不是共用同一份，直接在 lambda 裡寫 `received_index = i`
	# 改的是拷貝，外面的變數看不到。陣列是參考型別，拷貝的是參考，兩邊仍指向
	# 同一份資料，這樣才能把 signal 帶的值帶出 lambda。
	var received := [-1]
	menu.option_chosen.connect(func(i: int) -> void: received[0] = i)
	var middle_button := menu.get_child(1) as Button
	middle_button.pressed.emit()
	assert_int(received[0]).override_failure_message(
		"中間按鈕（index 1）按下去應該回報 1，實際回報 %d" % received[0]
	).is_equal(1)

	# fix #1 的原地更新路徑：只改變暗與否，不重建、不改變按鈕數量。
	var updated_options: Array[Dictionary] = [
		{"kind": "sell", "refund": 10, "affordable": false},
		{"kind": "sell", "refund": 20, "affordable": true},
		{"kind": "sell", "refund": 30, "affordable": true},
	]
	menu.update_affordability(updated_options)
	assert_int(menu.get_child_count()).override_failure_message(
		"update_affordability 是原地更新，不該增減按鈕"
	).is_equal(3)
	assert_bool((menu.get_child(0) as Button).modulate.a < 1.0).override_failure_message(
		"標成買不起的選項，對應按鈕應該被調暗"
	).is_true()
	assert_bool(is_equal_approx((menu.get_child(1) as Button).modulate.a, 1.0)).override_failure_message(
		"標成買得起的選項不該被調暗"
	).is_true()

	# 換一批只有一個選項：重新叫 show_options 之後，子節點數要「穩定」回到 1。
	# queue_free() 是 call_deferred("free")——這一行呼叫完的當下，舊的三顆按鈕
	# 理論上還沒真的被移除，這一幀裡 get_child_count() 可能還看得到它們。
	# 所以不能緊接著斷言；要先讓一次 idle frame 把延後的 free() 真正跑完，
	# 才去看數量有沒有穩定下來。
	menu.show_options([{"kind": "sell", "refund": 99}], Vector2(400, 200))
	await await_idle_frame()
	assert_int(menu.get_child_count()).override_failure_message(
		"stale-button regression：show_options 換過一批選項後，子節點數該穩定回到 1"
	).is_equal(1)

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
