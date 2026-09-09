class_name RangeCircle
extends Node2D

## 塔的射程提示。
##
## 射程是世界單位的半徑畫在世界座標上，所以它是 Node2D 而不是 Control——
## ui/ 那一層不碰世界座標。要畫在哪、畫多大由 battle_scene 決定。

const FILL := Color(1.0, 0.88, 0.30, 0.10)
const OUTLINE := Color(1.0, 0.88, 0.30, 0.55)
const OUTLINE_WIDTH := 3.0
const SEGMENTS := 64

var _radius: float = 0.0

## 預設隱藏，但不覆蓋已經設好的狀態。
## 專案裡的其他 view 都是 new() → setup() → add_child()，若這裡也照那個順序，
## 無條件的 visible = false 會把先呼叫的 show_at 蓋掉，而且畫面上不會有任何線索。
func _ready() -> void:
	# Views 開了 y_sort，所有子節點依 y 決定先後。射程圈的 y 是塔的 y，
	# 所以它會蓋住畫面上方的塔——那不是深度關係，是提示線該永遠在底下。
	# y-sort 只在同一個 z_index 內排序，壓到 -1 就永遠先畫。
	z_index = -1
	if _radius <= 0.0:
		visible = false

func show_at(world_position: Vector2, radius: float) -> void:
	position = world_position
	_radius = radius
	visible = radius > 0.0
	queue_redraw()

func hide_circle() -> void:
	visible = false

func _draw() -> void:
	if _radius <= 0.0:
		return
	draw_circle(Vector2.ZERO, _radius, FILL)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, SEGMENTS, OUTLINE, OUTLINE_WIDTH)
