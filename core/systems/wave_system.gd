class_name WaveSystem
extends RefCounted

## 波次的倒數、生成與提前呼叫。
##
## 住在 core/ 並在 tick 裡跑，所以不認得場景層——敵人定義由 configure_for_level
## 注入 WorldState，與 BuildSystem 從 tower_defs 造塔是同一個形狀。
##
## B3a 曾因為生成跑在渲染 delta 上而讓暫停與倍速對它無效；搬進 tick 之後，
## 倒數與生成自動跟著暫停與倍速，不需要任何特例。

static func tick(world: WorldState, delta: float) -> void:
	var state := world.wave_state
	if state.spawning:
		_tick_spawning(world, state, delta)
		return
	if state.next_wave_index >= world.waves.size():
		return
	state.countdown = maxf(0.0, state.countdown - delta)
	if state.countdown <= 0.0:
		_start_wave(world, state)

## 提前呼叫下一波，回傳實際發放的銀。被忽略時回傳 0。
##
## 忽略的情境（生成中、已全部生成完、倒數已歸零）一律靜默——沿用 B1 起的分野：
## 時機性的失敗靜默，資料錯誤才 push_error。
static func call_next_wave(world: WorldState) -> int:
	var state := world.wave_state
	if state.spawning or state.next_wave_index >= world.waves.size():
		return 0
	if state.countdown <= 0.0:
		return 0

	var bonus := floori(state.countdown * float(world.call_bonus_per_second))
	world.gold += bonus
	state.countdown = 0.0
	_start_wave(world, state)
	return bonus

## 所有波次都已生成完畢。注意這與「場上沒有敵人」是兩件事——
## 兩波之間的空檔場上可能是空的，但還沒生完。
static func all_spawned(world: WorldState) -> bool:
	var state := world.wave_state
	return state.next_wave_index >= world.waves.size() and not state.spawning

static func _start_wave(world: WorldState, state: WaveState) -> void:
	var wave: Dictionary = world.waves[state.next_wave_index]
	state.active_groups.clear()
	for group: Dictionary in wave["groups"]:
		state.active_groups.append({
			"enemy_id": StringName(group["enemy_id"]),
			"path_id": StringName(group["path_id"]),
			"remaining": int(group["count"]),
			"interval": float(group["interval"]),
			# timer 先擺 start_delay，歸零時生一隻，再加回 interval
			"timer": float(group.get("start_delay", 0.0)),
		})
	state.spawning = true

static func _tick_spawning(world: WorldState, state: WaveState, delta: float) -> void:
	var any_left := false
	for group: Dictionary in state.active_groups:
		if int(group["remaining"]) <= 0:
			continue
		group["timer"] = float(group["timer"]) - delta
		# while 而非 if：interval 小於一個 tick 時，一個 tick 要生好幾隻
		while float(group["timer"]) <= 0.0 and int(group["remaining"]) > 0:
			_spawn_one(world, group)
			group["remaining"] = int(group["remaining"]) - 1
			group["timer"] = float(group["timer"]) + float(group["interval"])
		if int(group["remaining"]) > 0:
			any_left = true

	if any_left:
		return

	state.spawning = false
	state.active_groups.clear()
	state.next_wave_index += 1
	if state.next_wave_index < world.waves.size():
		state.countdown = float(world.waves[state.next_wave_index]["delay"])

static func _spawn_one(world: WorldState, group: Dictionary) -> void:
	var enemy_id: StringName = group["enemy_id"]
	var def: Dictionary = world.enemy_defs.get(enemy_id, {})
	if def.is_empty():
		push_error("波次引用了不存在的敵人: %s" % enemy_id)
		return
	var path_id: StringName = group["path_id"]
	var path: PathData = world.paths.get(path_id)
	if path == null:
		push_error("波次引用了不存在的路徑: %s" % path_id)
		return

	var enemy := EnemyFactory.from_def(def, enemy_id, path_id)
	# 先把座標設到路徑起點：否則 view 會先出現在原點，等第一個 tick 才跳過去。
	enemy.position = path.position_at(0.0)
	world.add_enemy(enemy)
