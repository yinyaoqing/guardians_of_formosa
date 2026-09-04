class_name MovementSystem
extends RefCounted

## 沿固定路徑推進敵人。不做尋路——路徑在編輯器畫好並烘焙成等距點陣列，
## 敵人只需要累加「已行進距離」。

static func tick(enemies: Array, paths: Dictionary, delta: float) -> void:
	for enemy: Enemy in enemies:
		if not enemy.alive or enemy.leaked:
			continue
		if enemy.blocked_by != 0:
			continue
		if not paths.has(enemy.path_id):
			push_error("MovementSystem: 敵人 id=%d 引用了不存在的路徑 path_id=%s" % [enemy.id, enemy.path_id])
			continue
		var path: PathData = paths[enemy.path_id]
		enemy.distance_along += enemy.speed * delta
		if enemy.distance_along >= path.total_length():
			enemy.distance_along = path.total_length()
			enemy.leaked = true
		enemy.position = path.position_at(enemy.distance_along)
