class_name BuildSlotView
extends Sprite2D

## 建塔點的視覺。B2 的置換品——B3 會換成真正的美術與選取提示。
##
## 沒有它的話玩家看不到建塔點在哪、也看不到自己選中了什麼，
## B2 的人工驗收會變成對著記憶中的座標盲按。

const COLOR_IDLE := Color(1.0, 1.0, 1.0, 0.30)
const COLOR_SELECTED := Color(1.0, 0.88, 0.30, 0.85)

var slot_id: int = 0

func setup(p_slot_id: int, sprite_path: String, slot_position: Vector2) -> void:
	slot_id = p_slot_id
	texture = load(sprite_path)
	position = slot_position
	modulate = COLOR_IDLE

func set_selected(selected: bool) -> void:
	modulate = COLOR_SELECTED if selected else COLOR_IDLE
