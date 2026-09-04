class_name ProjectileView
extends Sprite2D

## 投射物的視覺表現。只讀模擬狀態，不寫回——資料流是單向的。
##
## 以 instance_id 而非物件本身識別。投射物走物件池，同一個 Projectile 物件會被
## 反覆重用，但每次自池取出都會配發全新的 instance_id。若拿物件當索引，舊的 view
## 會誤綁到重用後的新投射物，畫面上就是箭矢從上一發的位置瞬移過來。
##
## 邏輯 30Hz、畫面 60fps，直接套用座標會看到跳動，
## 所以記住前後兩個 tick 的座標，依幀內進度插值——與 EnemyView 同一套做法。

var instance_id: int = 0

var _previous_position: Vector2 = Vector2.ZERO
var _target_position: Vector2 = Vector2.ZERO

func setup(p_instance_id: int, sprite_path: String, start_position: Vector2) -> void:
	instance_id = p_instance_id
	texture = load(sprite_path)
	_previous_position = start_position
	_target_position = start_position
	position = start_position

## 每個邏輯 tick 呼叫一次，推進插值的目標點並轉向飛行方向
func on_tick(new_position: Vector2) -> void:
	_previous_position = _target_position
	_target_position = new_position

	# 位移為零時保持原角度。對零向量取 angle() 會回傳 0，
	# 那會讓剛生成、尚未移動的投射物先朝右再突然轉向。
	var step := _target_position - _previous_position
	if step.length_squared() > 0.0:
		rotation = step.angle()

## 每個渲染幀呼叫一次。alpha 為距離下個 tick 的進度 0.0 ~ 1.0
func interpolate(alpha: float) -> void:
	position = _previous_position.lerp(_target_position, alpha)
