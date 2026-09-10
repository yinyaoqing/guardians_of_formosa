extends SceneTree

## 開發工具：載入戰場、跑幾秒、截圖、結束。給 AI 協作與人工驗收用，不進自動化測試。
##
##   godot --path . -s res://game/fx/screenshot_battle.gd -- --out=C:/dir/battle.png --seconds=6
##   --build=0:musket_tower   在第 0 個建塔點蓋一座塔（可重複），讓截圖裡有戰鬥
##   --burst=4                連拍 4 張（每 0.15 秒一張，檔名加 _1.._4），看動態用
##   --menu=1                 截圖前選取第 1 個建塔點，讓建塔選單開著（看 UI 主題用）
##   --dialogue=portrait_elder  截圖前疊一張對話卡，肖像取 game/assets/chapter01/<id>.png
##   --hover-all              對每個建塔點的每一瓣各跑一次 hover 與 unhover。
##                            這條路徑沒有滑鼠就走不到，而它正是 M1-B5 最終審查
##                            抓到 Critical 的地方（兵營沒有 attack_range 鍵）。
##                            有錯會在輸出裡留下 SCRIPT ERROR / Invalid。
##
## 用 SceneTree 腳本而不是改 battle_scene：戰場場景不該為了截圖多長一條 CLI 分支。
##
## **這個工具會開一個真的視窗，而那個視窗會吃到真的滑鼠點擊。** 截圖跑的時候
## 順手在桌面上點兩下，點擊就會落進戰場：選到建塔點、再點到剛開出來的選單，
## 於是畫面上多出一座你沒蓋的塔。2026-09-10 追過一次，結論是環境不是 bug——
## 看到非預期的塔或選取時，先確認當時有沒有人在用滑鼠。

func _initialize() -> void:
	var out := ""
	var seconds := 6.0
	var builds: Array[String] = []
	var burst := 1
	var menu_slot := -1
	var dialogue := ""
	var hover_all := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--menu="):
			menu_slot = int(arg.trim_prefix("--menu="))
		if arg.begins_with("--dialogue="):
			dialogue = arg.trim_prefix("--dialogue=")
		if arg == "--hover-all":
			hover_all = true
		if arg.begins_with("--burst="):
			burst = int(arg.trim_prefix("--burst="))
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--seconds="):
			seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--build="):
			builds.append(arg.trim_prefix("--build="))
	if out.is_empty():
		push_error("需要 --out=<path>")
		quit(1)
		return
	change_scene_to_file("res://game/level/battle_scene.tscn")
	_run(out, seconds, builds, burst, menu_slot, dialogue, hover_all)


func _run(out: String, seconds: float, builds: Array[String], burst: int, menu_slot: int, dialogue: String, hover_all: bool) -> void:
	await process_frame
	await process_frame
	# 直接對模擬排建造意圖，與玩家點選單走的是同一條路（BuildSystem 驗證與扣錢照做）
	var scene := current_scene
	for spec in builds:
		var parts := spec.split(":")
		var slot_index := int(parts[0])
		var slots: Array = scene._sim.world.build_slots
		if slot_index < slots.size():
			scene._sim.world.queue_intent(GameIntent.build(slots[slot_index].id, StringName(parts[1])))
	await create_timer(seconds).timeout
	if hover_all:
		var slots_all: Array = scene._sim.world.build_slots
		for i in slots_all.size():
			scene._controller.selected_slot_id = slots_all[i].id
			# 讓場景重算這一格的選項（結構簽章變了，會走 show_options）
			scene._update_slot_views()
			await process_frame
			var count: int = scene._menu_options.size()
			var kinds: Array[String] = []
			for opt: Dictionary in scene._menu_options:
				kinds.append(String(opt["kind"]) + ("/" + String(opt.get("tower_id", "")) if opt.has("tower_id") else ""))
			print("建塔點 %d（佔用 %d）：%d 瓣 %s" % [i, slots_all[i].occupied_by, count, ", ".join(kinds)])
			for petal in count:
				scene._on_menu_option_hovered(petal)
				scene._on_menu_option_unhovered()
			# 越界索引也各打一次：handler 自己該擋住，不該讓它變成當機
			scene._on_menu_option_hovered(-1)
			scene._on_menu_option_hovered(count + 5)
		scene._controller.selected_slot_id = 0
		scene._update_slot_views()

	if menu_slot >= 0:
		# 與玩家點建塔點走同一條路：只改 controller 的選取狀態，選單由 battle_scene 重算
		var slots: Array = scene._sim.world.build_slots
		if menu_slot < slots.size():
			scene._controller.selected_slot_id = slots[menu_slot].id
	if not dialogue.is_empty():
		var card: DialogueCard = load("res://ui/dialogue_card.tscn").instantiate()
		scene.add_child(card)
		var portrait: Texture2D = load("res://game/assets/chapter01/%s.png" % dialogue)
		card.show_line(portrait, &"hud.pause", &"level.level_01.name")
	await process_frame
	await process_frame
	if burst <= 1:
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(out)
	else:
		for i in burst:
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(out.get_basename() + "_%d.png" % (i + 1))
			await create_timer(0.15).timeout
	quit()
