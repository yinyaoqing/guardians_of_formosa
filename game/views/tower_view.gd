class_name TowerView
extends Sprite2D

## 塔的視覺表現。塔不移動，所以不需要插值；
## M0 只做「有目標時轉向目標」，開火特效留到 M1 的投射物系統。

var tower_id: int = 0

func setup(p_tower_id: int, sprite_path: String, tower_position: Vector2) -> void:
	tower_id = p_tower_id
	texture = load(sprite_path)
	position = tower_position

func aim_at(target_position: Vector2) -> void:
	rotation = (target_position - position).angle()
