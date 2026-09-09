class_name SoldierView
extends Node2D

## 小兵的灰盒表現。崗位固定不動，所以不需要插值。
##
## 血條在這裡不是裝飾：耗損與回血是這個系統的核心，沒有血條，人工驗收時
## 無法分辨「系統正常運作」與「傷害根本沒進去」。

const BODY_SIZE := Vector2(14.0, 20.0)
const BAR_SIZE := Vector2(18.0, 3.0)
const BAR_OFFSET := Vector2(-9.0, -18.0)

var soldier_id: int = 0

var _hp_ratio: float = 1.0

func setup(p_soldier_id: int, post_position: Vector2) -> void:
	soldier_id = p_soldier_id
	position = post_position

func on_tick(hp_ratio: float) -> void:
	var clamped := clampf(hp_ratio, 0.0, 1.0)
	if is_equal_approx(clamped, _hp_ratio):
		return
	_hp_ratio = clamped
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-BODY_SIZE * 0.5, BODY_SIZE), Color(0.85, 0.80, 0.55))
	draw_rect(Rect2(BAR_OFFSET, BAR_SIZE), Color(0.15, 0.15, 0.15))
	draw_rect(
		Rect2(BAR_OFFSET, Vector2(BAR_SIZE.x * _hp_ratio, BAR_SIZE.y)),
		Color(0.35, 0.70, 0.35)
	)
