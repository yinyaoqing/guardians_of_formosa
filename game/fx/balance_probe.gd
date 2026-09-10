extends SceneTree

## 開發工具：不開畫面、不等真實時間，直接把整關跑完，印出結果。給數值調校用。
##
##   godot --headless --path . -s res://game/fx/balance_probe.gd -- --build=0:musket_tower --build=1:musket_tower
##   --build=<建塔點索引>:<塔 id>   可重複；不給就是「一座塔都不蓋」的下限測試
##   --max-seconds=600             模擬時間上限，防止打不完時無限跑
##
## 為什麼不是測試：這裡量的是「這組數值好不好玩」，答案會隨調校一直變，
## 釘成斷言只會變成每次調數值都要改的假測試。數值的**結構**正確性
## （欄位齊全、id 存在）由 test_data_integrity 守，那才是不該變的部分。
##
## 直接驅動 BattleSim，不載入 battle_scene：表現層與真實時間都不參與，
## 八波打完只要幾秒。路徑與建塔點仍取自 map.json，與戰場同一份真相。

const LEVEL_ID := &"level_01"
const MAIN_PATH_ID := &"main"
const PATH_SAMPLE_SPACING := 8.0
const TICK := 1.0 / 30.0

func _initialize() -> void:
	var builds: Array[String] = []
	var max_seconds := 900.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--build="):
			builds.append(arg.trim_prefix("--build="))
		elif arg.begins_with("--max-seconds="):
			max_seconds = float(arg.trim_prefix("--max-seconds="))

	var registry := DataRegistry.new()
	registry.load_from_disk()
	var meta: Dictionary = registry.levels[LEVEL_ID]
	var level_map := LevelMap.new(meta["map"])

	var world := WorldState.new()
	world.configure_for_level(registry, LEVEL_ID)
	world.paths[MAIN_PATH_ID] = PathData.new(level_map.sample_path(PATH_SAMPLE_SPACING), PATH_SAMPLE_SPACING)
	for pos: Vector2 in level_map.build_slot_positions():
		var slot := BuildSlot.new()
		slot.position = pos
		world.add_build_slot(slot)

	var sim := BattleSim.new(world)
	# 建塔走與玩家相同的意圖路徑，BuildSystem 的驗證與扣錢照做。
	for spec in builds:
		var parts := spec.split(":")
		var index := int(parts[0])
		if index < world.build_slots.size():
			world.queue_intent(GameIntent.build(world.build_slots[index].id, StringName(parts[1])))

	var elapsed := 0.0
	var peak_alive := 0
	var wave_shown := -1
	while not world.battle_finished and elapsed < max_seconds:
		sim.advance(TICK)
		elapsed += TICK
		peak_alive = maxi(peak_alive, world.enemies.size())
		var wave: int = world.wave_state.next_wave_index
		if wave != wave_shown:
			wave_shown = wave
			print("  t=%6.1fs  已生成到第 %d 波   平民 %d   銀 %d" % [
				elapsed, wave, world.civilians_remaining, world.gold])

	print("")
	print("=== 結果 ===")
	print("  打完：%s（模擬 %.1f 秒）" % ["是" if world.battle_finished else "否（撞上上限）", elapsed])
	print("  平民：%d / %d" % [world.civilians_remaining, world.starting_civilians])
	print("  星等：%d" % ResultSystem.star_count(world))
	print("  同場最多敵人：%d" % peak_alive)
	print("  剩餘銀：%d" % world.gold)
	quit()
