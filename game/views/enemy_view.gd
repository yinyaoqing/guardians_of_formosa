class_name EnemyView
extends Sprite2D

## 敵人的視覺表現。只讀模擬狀態，不寫回——資料流是單向的。
##
## 邏輯 30Hz、畫面 60fps，直接套用座標會看到跳動，
## 所以記住前後兩個 tick 的座標，依幀內進度插值。

var enemy_id: int = 0

var _previous_position: Vector2 = Vector2.ZERO
var _target_position: Vector2 = Vector2.ZERO

func setup(p_enemy_id: int, sprite_path: String, start_position: Vector2) -> void:
	enemy_id = p_enemy_id
	texture = load(sprite_path)
	_previous_position = start_position
	_target_position = start_position
	position = start_position

## 每個邏輯 tick 呼叫一次，推進插值的目標點
func on_tick(new_position: Vector2) -> void:
	_previous_position = _target_position
	_target_position = new_position

## 每個渲染幀呼叫一次。alpha 為距離下個 tick 的進度 0.0 ~ 1.0
func interpolate(alpha: float) -> void:
	position = _previous_position.lerp(_target_position, alpha)
