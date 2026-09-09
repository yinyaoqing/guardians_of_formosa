class_name TowerView
extends Sprite2D

## 塔的視覺表現。塔不移動，所以不需要插值；
## 有目標時朝目標水平翻轉。
##
## 開火（精緻度規格 L5）：整張往目標反方向後座 4px 再彈回、槍口一點藤黃閃光。
## 兩者都是程式曲線與程序貼圖，不需要幀，也不需要把塔的人物拆件——
## 塔不走路，攻擊用「後座」表達比手臂分件便宜得多，且對三階完全不同的圖都成立。

const RECOIL_PX := 4.0
const RECOIL_SECONDS := 0.12
const FLASH_SECONDS := 0.06
const FLASH_COLOR := Color("#E0A93B")  # 藤黃

var tower_id: int = 0
var _flash: Sprite2D
var _recoil: Tween

func setup(p_tower_id: int, sprite_path: String, tower_position: Vector2) -> void:
	tower_id = p_tower_id
	texture = load(sprite_path)
	position = tower_position

## 升級會換成完全不同的一張圖（火繩槍手 → 三人排槍 → 稜堡砲位），
## 所以圖不是建造時載入一次就結束。
func set_sprite(sprite_path: String) -> void:
	texture = load(sprite_path)

## 真美術是有上下之分的人與建築，整張旋轉會讓塔朝左開火時上下顛倒。
## 2D 的正解是水平翻轉，不是旋轉。rotation 保持 0。
func aim_at(target_position: Vector2) -> void:
	flip_h = target_position.x < position.x


## 發射一枚投射物時呼叫：後座 + 槍口閃光
func play_fire(target_position: Vector2) -> void:
	aim_at(target_position)
	var away := (position - target_position).normalized()
	if _recoil != null and _recoil.is_valid():
		_recoil.kill()
	offset = away * RECOIL_PX
	_recoil = create_tween()
	_recoil.tween_property(self, "offset", Vector2.ZERO, RECOIL_SECONDS).set_ease(Tween.EASE_OUT)

	if _flash == null:
		_flash = Sprite2D.new()
		_flash.texture = _make_flash_texture()
		_flash.visible = false
		add_child(_flash)
	# 槍口在朝目標那一側、約人物胸口高度；翻轉時 x 跟著換邊
	var side := -1.0 if flip_h else 1.0
	_flash.position = Vector2(side * texture.get_width() * 0.32, -texture.get_height() * 0.08)
	_flash.visible = true
	_flash.scale = Vector2.ONE * randf_range(0.8, 1.2)
	var tw := create_tween()
	tw.tween_interval(FLASH_SECONDS)
	tw.tween_callback(func() -> void: _flash.visible = false)


static func _make_flash_texture() -> Texture2D:
	# 12px 的四芒星：中心亮、四個尖角，程序畫出來就不用多一張資產
	var size := 12
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size / 2.0 - 0.5
	for y in size:
		for x in size:
			var dx := absf(x - c)
			var dy := absf(y - c)
			var star := minf(dx, dy) * 1.6 + maxf(dx, dy) * 0.6
			var a := clampf(1.0 - star / (size * 0.42), 0.0, 1.0)
			img.set_pixel(x, y, Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, a))
	return ImageTexture.create_from_image(img)
