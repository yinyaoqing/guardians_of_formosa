class_name BuildSystem
extends RefCounted

## 建造、升級、賣出的唯一結算入口。
##
## 拒絕分兩類，分野是「資料對不對」而非「時機對不對」：
##  - 資料錯誤（不存在的建塔點或塔種、本關不可用的塔種）→ push_error，那是 bug
##  - 時機不成立（已占用、錢不夠、塔已被賣掉、已滿級）→ 靜默忽略，那是正常競態。
##    玩家快速點兩下、或 UI 用的是上一 tick 的金幣數，都會產生這種指令。
##    把正常競態當錯誤噴，只會訓練所有人無視錯誤訊息。

static func apply(world: WorldState, intent: GameIntent) -> void:
	match intent.kind:
		GameIntent.KIND_BUILD:
			_build(world, intent)
		GameIntent.KIND_UPGRADE:
			_upgrade(world, intent)
		_:
			push_error("BuildSystem 收到未知的 intent kind: %s" % intent.kind)

static func _build(world: WorldState, intent: GameIntent) -> void:
	if not world.build_slots_by_id.has(intent.slot_id):
		push_error("build intent 引用了不存在的建塔點 id=%d" % intent.slot_id)
		return
	if not world.tower_defs.has(intent.tower_id):
		push_error("build intent 引用了不存在的塔種: %s" % intent.tower_id)
		return
	if not world.available_towers.has(intent.tower_id):
		push_error("塔種 %s 不在本關的可用清單中，UI 不該給得出此選項" % intent.tower_id)
		return

	var slot: BuildSlot = world.build_slots_by_id[intent.slot_id]
	if slot.occupied_by != 0:
		return

	var def: Dictionary = world.tower_defs[intent.tower_id]
	var cost := int(def["levels"][0]["cost"])
	if world.gold < cost:
		return

	world.gold -= cost
	var tower := Tower.new()
	tower.tower_id = intent.tower_id
	tower.position = slot.position
	_apply_level_stats(tower, def, 1)
	world.add_tower(tower)
	slot.occupied_by = tower.id

static func _upgrade(world: WorldState, intent: GameIntent) -> void:
	var tower := _find_tower(world, intent.entity_id)
	if tower == null:
		return

	var def: Dictionary = world.tower_defs[tower.tower_id]
	var levels: Array = def["levels"]
	# 等級自 1 起算，所以下一級在陣列中的索引正好是目前的 level
	if tower.level >= levels.size():
		return

	var cost := int(levels[tower.level]["cost"])
	if world.gold < cost:
		return

	world.gold -= cost
	_apply_level_stats(tower, def, tower.level + 1)

static func _find_tower(world: WorldState, entity_id: int) -> Tower:
	for tower: Tower in world.towers:
		if tower.id == entity_id:
			return tower
	return null

## 把指定等級的數值套到塔上。等級自 1 起算，對應 levels 陣列的索引 level - 1。
static func _apply_level_stats(tower: Tower, def: Dictionary, level: int) -> void:
	var level_def: Dictionary = def["levels"][level - 1]
	tower.level = level
	tower.damage = level_def["damage"]
	tower.damage_type = StringName(def["damage_type"])
	tower.attack_range = level_def["attack_range"]
	tower.fire_interval = level_def["fire_interval"]
	tower.projectile_speed = level_def["projectile_speed"]
	tower.splash_radius = level_def["splash_radius"]
	var effects: Array[StringName] = []
	for effect_id in level_def["on_hit_effects"]:
		effects.append(StringName(effect_id))
	tower.on_hit_effects = effects
