class_name GarrisonSystem
extends RefCounted

## 兵營名額的維護：補兵、重生倒數、脫戰回血。
##
## 這個系統不認得敵人。「誰在打誰」是 MeleeSystem 的事——兩者分開之後，
## 「重生的兵要不要立刻接戰」就不會變成同一段程式碼裡的旗標。
## 唯一的耦合是這裡讀 soldier.engaged_enemy_id 來決定回不回血，那是
## 一個唯讀的查詢，不是控制流的交纏。

static func tick(world: WorldState, delta: float) -> void:
	for tower: Tower in world.towers:
		if tower.kind != Tower.KIND_BARRACKS:
			continue
		_tick_barracks(world, tower, delta)
	_regenerate(world, delta)

## 走過每一個名額：有人就跳過，沒人就扣倒數，倒數歸零就補一個。
##
## 倒數先扣再判斷，所以走完的那一個 tick 內就補兵，不會慢一拍。
static func _tick_barracks(world: WorldState, tower: Tower, delta: float) -> void:
	for i in tower.soldier_ids.size():
		if tower.soldier_ids[i] != 0:
			continue
		tower.respawn_timers[i] = maxf(0.0, tower.respawn_timers[i] - delta)
		if tower.respawn_timers[i] > 0.0:
			continue
		tower.soldier_ids[i] = _spawn(world, tower, i).id

static func _spawn(world: WorldState, tower: Tower, slot_index: int) -> Soldier:
	var soldier: Soldier = world.soldier_pool.acquire()
	# 池裡拿到的是上一個死掉的小兵，欄位全是它上輩子的值。reset() 負責
	# 血量與戰鬥狀態，這裡負責身分與崗位——兩者加起來必須覆蓋每一個欄位。
	soldier.reset(tower.soldier_hp, tower.soldier_armor)
	soldier.id = 0                      # 讓 add_soldier 配發新 id
	soldier.barracks_id = tower.id
	soldier.slot_index = slot_index
	soldier.path_id = tower.post_path_id
	soldier.post_distance = tower.post_distance
	soldier.position = tower.post_position
	soldier.damage = tower.soldier_damage
	soldier.damage_type = tower.damage_type
	soldier.attack_interval = tower.soldier_attack_interval
	soldier.regen_per_second = tower.regen_per_second
	world.add_soldier(soldier)
	return soldier

## 脫戰回血。交戰中的不回，否則防線永遠打不破。
static func _regenerate(world: WorldState, delta: float) -> void:
	for soldier: Soldier in world.soldiers:
		if not soldier.alive or soldier.engaged_enemy_id != 0:
			continue
		soldier.hp = minf(soldier.max_hp, soldier.hp + soldier.regen_per_second * delta)
