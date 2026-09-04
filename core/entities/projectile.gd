class_name Projectile
extends RefCounted

## 模擬層的投射物。追蹤目標且必中，傷害在命中那一 tick 才結算——
## 因此多座塔齊射一隻將死的敵人會浪費發數，這是塔防真實的策略層。

## 每次自池取出都配發全新號碼，即使物件本身被重複使用。
## 池化最常見的 bug 是 id 被回收後，表現層的舊 view 誤綁到新的投射物，
## 畫面上就會看到箭矢瞬移。一個遞增計數器即可根除整類問題。
var instance_id: int = 0

var active: bool = false
var projectile_id: StringName = &""     ## 視覺用
var position: Vector2 = Vector2.ZERO
var target_id: int = 0
var speed: float = 0.0                  ## 像素 / 秒
var damage: float = 0.0
var damage_type: StringName = &"physical"

## 命中時施加的狀態效果，以及它們的「來源」。
## 來源是發射者的 tower_id（塔的種類），見 StatusSystem 的堆疊規則。
var source_tower_id: StringName = &""
var on_hit_effects: Array[StringName] = []

var splash_radius: float = 0.0          ## 0 表示單體

func reset() -> void:
	instance_id = 0
	active = false
	projectile_id = &""
	position = Vector2.ZERO
	target_id = 0
	speed = 0.0
	damage = 0.0
	damage_type = &"physical"
	source_tower_id = &""
	on_hit_effects.clear()
	splash_radius = 0.0
