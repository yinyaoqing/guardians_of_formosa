class_name ProjectileSystem
extends RefCounted

## 投射物的生成、飛行與命中結算。
##
## 追蹤且必中：每 tick 朝目標「當前」座標移動，當本 tick 的移動距離足以走到目標時命中。
## 這個判定保證不會穿透，且只要投射物速度高於敵人速度就必定在有限時間內命中
## （該條件由資料完整性測試把關）。

var _world: WorldState

func _init(world: WorldState) -> void:
	_world = world

## 自池取得一個投射物並初始化。生成位置為發射它的塔。
func spawn(
	tower: Tower,
	target_id: int,
	projectile_speed: float,
	splash_radius: float,
	on_hit_effects: Array[StringName]
) -> Projectile:
	var projectile: Projectile = _world.projectile_pool.acquire()
	projectile.reset()
	projectile.instance_id = _world.next_id()
	projectile.active = true
	projectile.position = tower.position
	projectile.target_id = target_id
	projectile.speed = projectile_speed
	projectile.damage = tower.damage
	projectile.damage_type = tower.damage_type
	projectile.source_tower_id = tower.tower_id
	projectile.splash_radius = splash_radius
	projectile.on_hit_effects.assign(on_hit_effects)
	_world.projectiles.append(projectile)
	return projectile

func tick(delta: float) -> void:
	# 由後往前走訪，這樣原地移除不會跳過元素，也不必重建陣列
	for i in range(_world.projectiles.size() - 1, -1, -1):
		var projectile: Projectile = _world.projectiles[i]
		var target: Enemy = _world.enemies_by_id.get(projectile.target_id)

		if target == null or not target.alive or target.leaked:
			_despawn(i)
			continue

		var to_target := target.position - projectile.position
		var step := projectile.speed * delta
		if to_target.length() <= step:
			projectile.position = target.position
			_on_impact(projectile, target)
			_despawn(i)
			continue

		projectile.position += to_target.normalized() * step

## 命中結算。傷害一律經過 DamageSystem，此處不做任何減免計算。
## 範圍內全額傷害，不做距離衰減——衰減會讓數值難以推理。
func _on_impact(projectile: Projectile, target: Enemy) -> void:
	if projectile.splash_radius <= 0.0:
		DamageSystem.apply(target, projectile.damage, projectile.damage_type)
		return

	# grid 是 broad phase，回傳的候選需自行做精確距離判定
	var radius_squared := projectile.splash_radius * projectile.splash_radius
	for candidate_id in _world.grid.query_radius(projectile.position, projectile.splash_radius):
		var enemy: Enemy = _world.enemies_by_id.get(candidate_id)
		if enemy == null or not enemy.alive or enemy.leaked:
			continue
		if projectile.position.distance_squared_to(enemy.position) > radius_squared:
			continue
		DamageSystem.apply(enemy, projectile.damage, projectile.damage_type)

func _despawn(index: int) -> void:
	var projectile: Projectile = _world.projectiles[index]
	projectile.active = false
	_world.projectiles.remove_at(index)
	_world.projectile_pool.release(projectile)
