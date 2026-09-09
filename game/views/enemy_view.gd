class_name EnemyView
extends Node2D

## 敵人的視覺表現。只讀模擬狀態，不寫回——資料流是單向的。
##
## 邏輯 30Hz、畫面 60fps，直接套用座標會看到跳動，
## 所以記住前後兩個 tick 的座標，依幀內進度插值。
##
## 兩種畫法，由敵人定義決定：
##   - 單張貼圖（"sprite"）：一個 Sprite2D，M0 灰盒與逐格路線用
##   - 分件（"puppet"）：data/puppets/<id>.json 列出的幾塊 Sprite2D，
##     腿繞髖關節擺動、軀幹起伏，相位由**走過的距離**推進——速度變了步頻跟著變，
##     不需要任何幀。這是 docs/art/A2x §6 實測後選的戰場動畫路線。
## 側面朝右為預設；往左走時整個節點水平翻轉。
##
## 受擊與死亡（精緻度規格 L5）：受擊＝整體白閃一下；死亡＝往行進方向倒下並淡出後自毀。
## 兩者都是程式曲線，不需要任何幀。血量比例由 battle_scene 每 tick 傳入，view 只讀不寫。

var enemy_id: int = 0

var _previous_position: Vector2 = Vector2.ZERO
var _target_position: Vector2 = Vector2.ZERO

var _leg_a: Sprite2D
var _leg_b: Sprite2D
var _body: Sprite2D
var _leg_a_rest_y := 0.0
var _leg_b_rest_y := 0.0
var _body_rest_y := 0.0
var _swing := 0.0        # 弧度
var _bob := 0.0          # 像素
var _stride := 1.0       # 走多少像素算一圈
var _phase := 0.0        # 0..1
var _last_drawn := Vector2.ZERO
var _last_hp_ratio := 1.0
var _facing := 1.0       # 1 朝右、-1 朝左
var _dying := false

const FLASH_SECONDS := 0.08
const DEATH_SECONDS := 0.45


func setup(p_enemy_id: int, sprite_path: String, start_position: Vector2, puppet_id: String = "") -> void:
	enemy_id = p_enemy_id
	_previous_position = start_position
	_target_position = start_position
	_last_drawn = start_position
	position = start_position
	if puppet_id.is_empty():
		var sprite := Sprite2D.new()
		sprite.texture = load(sprite_path)
		add_child(sprite)
	else:
		_build_puppet("res://data/puppets/%s.json" % puppet_id)


func _build_puppet(path: String) -> void:
	var def: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_swing = deg_to_rad(float(def.get("swing_deg", 28.0)))
	_bob = float(def.get("bob_px", 2.0))
	_stride = maxf(1.0, float(def.get("stride_px", 40.0)))
	# parts 的順序就是繪製順序：腿先、軀幹後，軀幹的衣襬蓋住髖關節的接縫
	for part: Dictionary in def["parts"]:
		var s := Sprite2D.new()
		s.name = part["name"]
		s.texture = load(part["texture"])
		s.centered = false
		var origin := Vector2(part["origin"][0], part["origin"][1])
		var pivot := Vector2(part["pivot"][0], part["pivot"][1])
		# position 放在關節上、offset 把圖推回原位，rotation 就繞著關節轉
		s.position = pivot
		s.offset = origin - pivot
		add_child(s)
		match String(part["role"]):
			"leg_a":
				_leg_a = s
				_leg_a_rest_y = pivot.y
			"leg_b":
				_leg_b = s
				_leg_b_rest_y = pivot.y
			"body":
				_body = s
				_body_rest_y = pivot.y


## 每個邏輯 tick 呼叫一次，推進插值的目標點；血量下降就閃一下
func on_tick(new_position: Vector2, hp_ratio: float = 1.0) -> void:
	_previous_position = _target_position
	_target_position = new_position
	if hp_ratio < _last_hp_ratio - 0.001:
		_flash()
	_last_hp_ratio = hp_ratio


func _flash() -> void:
	modulate = Color(2.2, 2.2, 2.2)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, FLASH_SECONDS)


## 敵人已從模擬移除、且不是走到終點：倒向行進方向、淡出、自毀。
## 呼叫後不再接受 on_tick／interpolate。
func play_death() -> void:
	if _dying:
		return
	_dying = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "rotation", _facing * PI / 2.0, DEATH_SECONDS).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, DEATH_SECONDS).set_delay(DEATH_SECONDS * 0.4)
	tw.chain().tween_callback(queue_free)


## 每個渲染幀呼叫一次。alpha 為距離下個 tick 的進度 0.0 ~ 1.0
func interpolate(alpha: float) -> void:
	if _dying:
		return
	position = _previous_position.lerp(_target_position, alpha)
	var moved := position - _last_drawn
	_last_drawn = position
	if absf(moved.x) > 0.01:
		_facing = -1.0 if moved.x < 0.0 else 1.0
	if _body == null:
		return
	_phase = fmod(_phase + moved.length() / _stride, 1.0)
	scale.x = _facing
	_pose(_phase)


func _pose(phase: float) -> void:
	var ang := _swing * sin(phase * TAU)
	var bob := -_bob * absf(cos(phase * TAU))
	if _leg_a != null:
		_leg_a.rotation = -ang
		_leg_a.position.y = _leg_a_rest_y + bob
	if _leg_b != null:
		_leg_b.rotation = ang
		_leg_b.position.y = _leg_b_rest_y + bob
	_body.position.y = _body_rest_y + bob
