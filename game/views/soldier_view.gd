class_name SoldierView
extends Node2D

## 小兵的灰盒表現。崗位固定不動，所以不需要插值。
##
## 血條在這裡不是裝飾：耗損與回血是這個系統的核心，沒有血條，人工驗收時
## 無法分辨「系統正常運作」與「傷害根本沒進去」。

const BODY_SIZE := Vector2(14.0, 20.0)
const BAR_SIZE := Vector2(18.0, 3.0)
const BAR_OFFSET := Vector2(-9.0, -18.0)

## 同一座兵營的所有小兵 core/ 端都站在同一個 post_position——那是攔截判定的
## 依據，不能為了美術而挪動。表現層因此要自己把疊在一起的灰盒錯開，
## 否則 t1 的兩個兵、t2/t3 的三個兵畫面上會是同一個灰盒子，人工驗收無法
## 分辨「有幾個兵」「死了一個」「重生了」。
##
## 選垂直方向（Y 軸）而不是沿路徑法線：法線需要 view 拿得到路徑方向，
## 這個里程碑的路徑資訊留在 battle_scene，多傳一個方向向量比多傳一個
## int 麻煩得多。灰盒階段的驗收標準只有「看得出幾個、死一個看得出來」，
## 這個階段的關卡（level_01）路徑以水平段為主，垂直錯開能讓小兵沿著
## 路徑的橫向排開、不互相遮擋；等以後真的要做美術排版再換成法線。
## 已知限制：路徑若是垂直走向，小兵會疊成一條縱線而非並肩——記在這裡，
## 不在這個里程碑處理。
const SLOT_OFFSET_STEP := 16.0

var soldier_id: int = 0

var _hp_ratio: float = 1.0

func setup(p_soldier_id: int, post_position: Vector2, slot_index: int) -> void:
	soldier_id = p_soldier_id
	position = post_position + Vector2(0.0, float(slot_index) * SLOT_OFFSET_STEP)

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
