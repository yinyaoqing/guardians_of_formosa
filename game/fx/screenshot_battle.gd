extends SceneTree

## 開發工具：載入戰場、跑幾秒、截圖、結束。給 AI 協作與人工驗收用，不進自動化測試。
##
##   godot --path . -s res://game/fx/screenshot_battle.gd -- --out=C:/dir/battle.png --seconds=6
##
## 用 SceneTree 腳本而不是改 battle_scene：戰場場景不該為了截圖多長一條 CLI 分支。

func _initialize() -> void:
	var out := ""
	var seconds := 6.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--seconds="):
			seconds = float(arg.trim_prefix("--seconds="))
	if out.is_empty():
		push_error("需要 --out=<path>")
		quit(1)
		return
	change_scene_to_file("res://game/level/battle_scene.tscn")
	_run(out, seconds)


func _run(out: String, seconds: float) -> void:
	await create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
