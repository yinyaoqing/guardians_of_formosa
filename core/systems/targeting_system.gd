class_name TargetingSystem
extends RefCounted

## 目標選擇。First 策略（射程內最接近終點者）在塔防裡特別便宜：
## 敵人沿固定路徑走，「最前面」就是 distance_along 最大者，不需要幾何運算。

## 回傳射程內 distance_along 最大的敵人 id，找不到時回傳 0。
static func find_first(tower: Tower, grid: UniformGrid, enemies_by_id: Dictionary) -> int:
	var candidates := grid.query_radius(tower.position, tower.attack_range)
	var best_id := 0
	var best_distance := -1.0
	var range_squared := tower.attack_range * tower.attack_range
	for candidate_id in candidates:
		var enemy: Enemy = enemies_by_id[candidate_id]
		if not enemy.alive or enemy.leaked:
			continue
		# grid 只做 broad phase，這裡補上精確的圓形射程判定
		if tower.position.distance_squared_to(enemy.position) > range_squared:
			continue
		if enemy.distance_along > best_distance:
			best_distance = enemy.distance_along
			best_id = enemy.id
	return best_id
