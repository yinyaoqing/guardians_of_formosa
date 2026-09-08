class_name BuildMenuOptions
extends RefCounted

## 建塔選單要顯示哪些選項。
##
## 純靜態函式，與 input/ 的翻譯器同一個模式——因為這裡面是真正的決策
## （買不買得起、有沒有下一級、退款多少），寫在 Control 裡就沒有測試守得到，
## 而畫面那層抓不到錯是 B3a 的教訓。
##
## Control 只負責把回傳的陣列畫出來。

const KIND_BUILD := &"build"
const KIND_UPGRADE := &"upgrade"
const KIND_SELL := &"sell"

static func for_slot(world: WorldState, slot_id: int) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if slot_id == 0:
		return options
	var slot: BuildSlot = world.build_slots_by_id.get(slot_id)
	if slot == null:
		return options

	if slot.occupied_by == 0:
		_append_build_options(options, world)
	else:
		_append_tower_options(options, world, slot.occupied_by)
	return options

static func _append_build_options(options: Array[Dictionary], world: WorldState) -> void:
	for i in world.available_towers.size():
		var tower_id: StringName = world.available_towers[i]
		var def: Dictionary = world.tower_defs.get(tower_id, {})
		if def.is_empty():
			continue
		var cost := int(def["levels"][0]["cost"])
		options.append({
			"kind": KIND_BUILD,
			"tower_id": String(tower_id),
			"name_key": String(def["name_key"]),
			"icon": String(def["icon"]),
			"cost": cost,
			# 按下去要翻成 choose_tower(n)，n 自 1 起算。這個對應放在這裡
			# 而不是 Control 裡，才有測試守得到。
			"choice_index": i + 1,
			"affordable": world.gold >= cost,
		})

static func _append_tower_options(options: Array[Dictionary], world: WorldState, tower_entity_id: int) -> void:
	var tower := _find_tower(world, tower_entity_id)
	if tower == null:
		return
	var def: Dictionary = world.tower_defs.get(tower.tower_id, {})
	if def.is_empty():
		return
	var levels: Array = def["levels"]

	# 等級自 1 起算，所以「下一級」的索引就是 level。等於 size() 表示已達最高階。
	if tower.level < levels.size():
		var cost := int(levels[tower.level]["cost"])
		options.append({
			"kind": KIND_UPGRADE,
			"cost": cost,
			"affordable": world.gold >= cost,
		})

	options.append({
		"kind": KIND_SELL,
		"refund": _refund_for(def, tower.level, world.sell_refund_ratio),
	})

static func _find_tower(world: WorldState, entity_id: int) -> Tower:
	for tower: Tower in world.towers:
		if tower.id == entity_id:
			return tower
	return null

## 與 BuildSystem 的退款算法必須逐字元一致。
##
## 理想上兩處共用同一段程式，但 ui/ 的分層守衛禁止這一層認識 BuildSystem，
## 而那條守衛正是攔住 UI 繞過 signal 直接動核心系統的東西——為了省四行而放寬它，
## 換到的遠不如失去的。
##
## 代價是這四行有兩份。撐住這個決定的是
## test_the_refund_matches_what_selling_actually_pays：它同時看選單顯示的金額
## 與實際賣出後金幣的增量。沒有那條測試的話這個決定不成立。
static func _refund_for(def: Dictionary, level: int, ratio: float) -> int:
	var invested := 0
	for i in level:
		invested += int(def["levels"][i]["cost"])
	return floori(float(invested) * ratio)
