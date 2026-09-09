extends SceneTree

## 開發工具：載入戰場、跑幾秒、截圖、結束。給 AI 協作與人工驗收用，不進自動化測試。
##
##   godot --path . -s res://game/fx/screenshot_battle.gd -- --out=C:/dir/battle.png --seconds=6
##   --build=0:musket_tower   在第 0 個建塔點蓋一座塔（可重複），讓截圖裡有戰鬥
##   --burst=4                連拍 4 張（每 0.15 秒一張，檔名加 _1.._4），看動態用
##
## 用 SceneTree 腳本而不是改 battle_scene：戰場場景不該為了截圖多長一條 CLI 分支。

func _initialize() -> void:
	var out := ""
	var seconds := 6.0
	var builds: Array[String] = []
	var burst := 1
	for arg in OS.get_cmdline_user_args():
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
	_run(out, seconds, builds, burst)


func _run(out: String, seconds: float, builds: Array[String], burst: int) -> void:
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
	if burst <= 1:
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(out)
	else:
		for i in burst:
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(out.get_basename() + "_%d.png" % (i + 1))
			await create_timer(0.15).timeout
	quit()
