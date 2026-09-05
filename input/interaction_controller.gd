class_name InteractionController
extends RefCounted

## 互動文法與選取狀態。純邏輯，不認得任何裝置——裝置的部分在翻譯器裡。
##
## 選取的對象永遠是建塔點，不是塔：所有塔都蓋在建塔點上且同座標，
## 所以「選中一座塔」等同「選中一個被占用的建塔點」，占用與否決定
## 哪些操作合法。狀態機因此只有一個變數。
##
## 本控制器只過濾「結構上做不做得到」，不判斷金錢——金錢是 BuildSystem
## 的權威。控制器若自己再判斷一次，就有了第二個事實來源，而兩者漂移的
## 那天不會有任何測試失敗。錢不夠時 intent 照發，由 core/ 靜默拒絕。

## 命中半徑。依架構規格 §6.4「觸控目標 ≥44pt」，半徑必須至少涵蓋那個尺寸，
## 否則觸控時會出現「看得到卻點不到」。48 留了一點餘裕。
const PICK_RADIUS := 48.0

var selected_slot_id: int = 0   ## 0 表示未選取

func handle(action: InputAction, world: WorldState) -> void:
	match action.kind:
		InputAction.SELECT_AT:
			_select_at(action.world_position, world)
		InputAction.CANCEL:
			selected_slot_id = 0
		InputAction.CHOOSE_TOWER:
			_choose_tower(action.index, world)
		InputAction.SELL:
			_sell(world)
		InputAction.UPGRADE:
			_upgrade(world)
		InputAction.TOGGLE_PAUSE:
			world.queue_intent(GameIntent.toggle_pause())
		InputAction.CYCLE_SPEED:
			world.queue_intent(GameIntent.cycle_speed())
		_:
			pass

## 選中半徑內最近的建塔點；半徑內沒有就解除選取。
## 建塔點數量是個位數，線性掃描綽綽有餘。
func _select_at(position: Vector2, world: WorldState) -> void:
	var best_id := 0
	var best_distance_squared := PICK_RADIUS * PICK_RADIUS
	for slot: BuildSlot in world.build_slots:
		var distance_squared := position.distance_squared_to(slot.position)
		# 用 <= 而非 < 是刻意的：這讓半徑邊界本身也算命中，觸控目標因此
		# 涵蓋整個 PICK_RADIUS，而不是差一點點打不到邊緣。副作用是兩個
		# 建塔點若剛好等距，會選到 build_slots 中較後面的那個。
		if distance_squared <= best_distance_squared:
			best_distance_squared = distance_squared
			best_id = slot.id
	selected_slot_id = best_id

## 目前選中的建塔點，未選取或找不到時回傳 null
func _selected_slot(world: WorldState) -> BuildSlot:
	if selected_slot_id == 0:
		return null
	return world.build_slots_by_id.get(selected_slot_id)

## index 自 1 起算，對應本關 available_towers 的第 n 種。
## 超出範圍是正常的使用者行為（按了「3」但本關只有兩種），靜默忽略。
func _choose_tower(index: int, world: WorldState) -> void:
	var slot := _selected_slot(world)
	if slot == null or slot.occupied_by != 0:
		return
	if index < 1 or index > world.available_towers.size():
		return
	world.queue_intent(GameIntent.build(slot.id, world.available_towers[index - 1]))

func _sell(world: WorldState) -> void:
	var slot := _selected_slot(world)
	if slot == null or slot.occupied_by == 0:
		return
	world.queue_intent(GameIntent.sell(slot.occupied_by))

func _upgrade(world: WorldState) -> void:
	var slot := _selected_slot(world)
	if slot == null or slot.occupied_by == 0:
		return
	world.queue_intent(GameIntent.upgrade(slot.occupied_by))
