class_name BuildSlotView
extends Sprite2D

## 建塔點的視覺。B3b 起是真美術（prop_buildsite），不再是白方塊。
##
## 有塔時隱藏：塔蓋在同一個座標上，標記留著只會從塔底下露出來。
##
## 選取提示改成輕微提亮而不是染黃——真美術染色會變濁，而且選中的主要回饋
## 其實是選單打開與射程圈出現，標記只需要一點呼應。

const COLOR_IDLE := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_SELECTED := Color(1.30, 1.25, 1.05, 1.0)

var slot_id: int = 0

var _occupied: bool = false
var _selected: bool = false

func setup(p_slot_id: int, sprite_path: String, slot_position: Vector2) -> void:
	slot_id = p_slot_id
	texture = load(sprite_path)
	position = slot_position
	modulate = COLOR_IDLE

func set_selected(selected: bool) -> void:
	_selected = selected
	modulate = COLOR_SELECTED if selected else COLOR_IDLE

func set_occupied(occupied: bool) -> void:
	_occupied = occupied
	visible = not occupied
