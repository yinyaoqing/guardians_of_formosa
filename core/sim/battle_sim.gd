class_name BattleSim
extends RefCounted

## 固定步長模擬迴圈。渲染幀率與邏輯 tick 解耦，好處是：
##  - 暫停與加速只是「本幀跑幾個 tick」，不必把 delta 乘上倍率（後者必然產生數值錯誤）
##  - 手機掉幀時邏輯不會變慢，戰鬥結果在不同效能裝置上一致

const TICK_RATE := 30
const TICK_DELTA := 1.0 / float(TICK_RATE)

## 單幀最多執行的 tick 數。卡頓後若無上限地補跑積欠的 tick，
## 會讓下一幀更慢、積欠更多，形成死亡螺旋。真正積欠過多時丟棄積欠。
const MAX_TICKS_PER_FRAME := 8

var world: WorldState
var tick_count: int = 0
var speed_multiplier: float = 1.0
var paused: bool = false

var _accumulator: float = 0.0

func _init(p_world: WorldState = null) -> void:
	world = p_world if p_world != null else WorldState.new()

## 推進模擬。frame_delta 為渲染幀的實際經過秒數。
## 回傳本幀實際執行的 tick 數。
func advance(frame_delta: float) -> int:
	if paused:
		return 0
	_accumulator += frame_delta * speed_multiplier
	var ticks := 0
	while _accumulator >= TICK_DELTA and ticks < MAX_TICKS_PER_FRAME:
		_accumulator -= TICK_DELTA
		_tick()
		ticks += 1
	# 只在真的還積欠超過一個 tick 時才丟棄。「跑滿上限」不等於「積欠很多」——
	# 高速度倍率配低幀率會正好跑滿上限卻只剩極小零頭，那個零頭必須留給下一幀，
	# 否則模擬會悄悄跑得比設定的倍率慢。
	if ticks == MAX_TICKS_PER_FRAME and _accumulator > TICK_DELTA:
		_accumulator = 0.0
	return ticks

## 幀內進度 0.0 ~ 1.0，供表現層做渲染插值使用
func tick_progress() -> float:
	return clampf(_accumulator / TICK_DELTA, 0.0, 1.0)

func _tick() -> void:
	tick_count += 1
	MovementSystem.tick(world.enemies, world.paths, TICK_DELTA)
	_collect_leaked()
	_rebuild_grid()
	_tick_towers()
	_remove_dead()

## 走到終點的敵人扣玩家一條命，並立刻移出戰場（避免重複扣血）
func _collect_leaked() -> void:
	for enemy: Enemy in world.enemies:
		if enemy.leaked and enemy.alive:
			enemy.alive = false
			world.lives -= 1

func _rebuild_grid() -> void:
	world.grid.clear()
	for enemy: Enemy in world.enemies:
		if enemy.alive:
			world.grid.insert(enemy.id, enemy.position)

func _tick_towers() -> void:
	for tower: Tower in world.towers:
		tower.cooldown = maxf(0.0, tower.cooldown - TICK_DELTA)
		tower.target_id = TargetingSystem.find_first(tower, world.grid, world.enemies_by_id)
		if tower.target_id == 0 or tower.cooldown > 0.0:
			continue
		var target: Enemy = world.enemies_by_id[tower.target_id]
		DamageSystem.apply(target, tower.damage, tower.damage_type)
		tower.cooldown = tower.fire_interval
		if not target.alive and not target.leaked:
			world.gold += target.bounty

## 死亡與洩漏的敵人移出集合。M0 直接移除；M1 會改成先播死亡動畫再移除。
func _remove_dead() -> void:
	var survivors: Array[Enemy] = []
	for enemy: Enemy in world.enemies:
		if enemy.alive:
			survivors.append(enemy)
		else:
			world.enemies_by_id.erase(enemy.id)
	world.enemies = survivors
