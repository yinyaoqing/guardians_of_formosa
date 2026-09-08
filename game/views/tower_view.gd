class_name TowerView
extends Sprite2D

## 塔的視覺表現。塔不移動，所以不需要插值；
## 有目標時朝目標水平翻轉，開火特效留到之後的投射物系統擴充。

var tower_id: int = 0

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
