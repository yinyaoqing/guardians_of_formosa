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
		_:
			pass

## 選中半徑內最近的建塔點；半徑內沒有就解除選取。
## 建塔點數量是個位數，線性掃描綽綽有餘。
func _select_at(position: Vector2, world: WorldState) -> void:
	var best_id := 0
	var best_distance_squared := PICK_RADIUS * PICK_RADIUS
	for slot: BuildSlot in world.build_slots:
		var distance_squared := position.distance_squared_to(slot.position)
		if distance_squared <= best_distance_squared:
			best_distance_squared = distance_squared
			best_id = slot.id
	selected_slot_id = best_id
