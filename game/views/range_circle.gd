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

func _ready() -> void:
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
