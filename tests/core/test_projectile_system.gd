extends GdUnitTestSuite

const PATH_ID := &"main"

func _make_world() -> WorldState:
	var world := WorldState.new()
	var points := PackedVector2Array([Vector2(0, 0), Vector2(500, 0), Vector2(1000, 0)])
	world.paths[PATH_ID] = PathData.new(points, 500.0)
	return world

func _add_enemy(world: WorldState, pos: Vector2, hp: float) -> Enemy:
	var enemy := Enemy.new()
	enemy.enemy_id = &"orc_grunt"
	enemy.hp = hp
	enemy.max_hp = hp
	enemy.base_speed = 0.0
	enemy.path_id = PATH_ID
	enemy.position = pos
	enemy.reset_derived_stats()
	world.add_enemy(enemy)
	return enemy

func _make_tower(world: WorldState, pos: Vector2) -> Tower:
	var tower := Tower.new()
	tower.tower_id = &"archer_tower"
	tower.position = pos
	tower.damage = 20.0
	tower.damage_type = DamageSystem.PHYSICAL
	tower.attack_range = 500.0
	tower.fire_interval = 1.0
	tower.projectile_speed = 600.0
	world.add_tower(tower)
	return tower

func test_spawned_projectile_starts_at_the_tower() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, Vector2(300, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	var system := ProjectileSystem.new(world)
	var projectile := system.spawn(tower, enemy.id, 600.0, 0.0, [] as Array[StringName])
	assert_float(projectile.position.x).is_equal_approx(0.0, 0.001)
	assert_array(world.projectiles).has_size(1)

func test_projectile_moves_toward_its_target() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, Vector2(300, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	var system := ProjectileSystem.new(world)
	var projectile := system.spawn(tower, enemy.id, 600.0, 0.0, [] as Array[StringName])
	system.tick(0.1)                       # 移動 60 像素
	assert_float(projectile.position.x).is_equal_approx(60.0, 0.001)

func test_damage_is_dealt_on_impact_not_on_spawn() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, Vector2(300, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	var system := ProjectileSystem.new(world)
	system.spawn(tower, enemy.id, 600.0, 0.0, [] as Array[StringName])
	system.tick(0.1)
	assert_float(enemy.hp).override_failure_message(
		"投射物尚未命中，不得結算傷害"
	).is_equal_approx(100.0, 0.001)
	system.tick(0.5)                       # 足以走完剩下的距離
	assert_float(enemy.hp).is_equal_approx(80.0, 0.001)

func test_projectile_is_released_after_hitting() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, Vector2(60, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	var system := ProjectileSystem.new(world)
	system.spawn(tower, enemy.id, 600.0, 0.0, [] as Array[StringName])
	system.tick(0.5)
	assert_array(world.projectiles).has_size(0)

func test_projectile_vanishes_when_target_dies_mid_flight() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, Vector2(500, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	var system := ProjectileSystem.new(world)
	system.spawn(tower, enemy.id, 100.0, 0.0, [] as Array[StringName])
	system.tick(0.1)
	enemy.alive = false
	system.tick(0.1)
	assert_array(world.projectiles).override_failure_message(
		"目標消失後投射物應直接歸還池中，傷害不轉移"
	).has_size(0)

func test_each_spawn_gets_a_fresh_instance_id() -> void:
	# 池會重複使用同一個物件，但 id 必須每次都不同，
	# 否則表現層的舊 view 可能誤綁到新的投射物；
	# 同時確認物件本身確實被重用，而非每次配置新物件
	var world := _make_world()
	var enemy := _add_enemy(world, Vector2(60, 0), 1000.0)
	var tower := _make_tower(world, Vector2(0, 0))
	var system := ProjectileSystem.new(world)
	var first := system.spawn(tower, enemy.id, 600.0, 0.0, [] as Array[StringName])
	var first_id := first.instance_id
	system.tick(0.5)                       # 命中並歸還
	var second := system.spawn(tower, enemy.id, 600.0, 0.0, [] as Array[StringName])
	assert_bool(is_same(first, second)).override_failure_message(
		"池應該重複使用同一個投射物物件；若每次都配置新物件，instance_id 的遞增就沒有意義了"
	).is_true()
	assert_int(second.instance_id).override_failure_message(
		"重複使用的投射物必須取得全新的 instance_id"
	).is_greater(first_id)

func test_splash_damages_every_enemy_in_radius() -> void:
	var world := _make_world()
	var primary := _add_enemy(world, Vector2(60, 0), 100.0)
	var nearby := _add_enemy(world, Vector2(90, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	# ProjectileSystem 用的是 grid，測試中需自行建好
	world.grid.clear()
	world.grid.insert(primary.id, primary.position)
	world.grid.insert(nearby.id, nearby.position)

	var system := ProjectileSystem.new(world)
	system.spawn(tower, primary.id, 600.0, 50.0, [] as Array[StringName])
	system.tick(0.5)

	assert_float(primary.hp).is_equal_approx(80.0, 0.001)
	assert_float(nearby.hp).override_failure_message(
		"半徑內的敵人必須受到全額傷害，不做距離衰減"
	).is_equal_approx(80.0, 0.001)

func test_splash_spares_enemies_outside_the_radius() -> void:
	# 此測試中的遠敵已被 broad phase 本身過濾，
	# 所以即使刪除精確圓形判定也不會失敗。
	# test_splash_spares_an_enemy_inside_the_query_square_but_outside_the_circle 才是
	# 真正測試精確判定的測試。
	var world := _make_world()
	var primary := _add_enemy(world, Vector2(60, 0), 100.0)
	var distant := _add_enemy(world, Vector2(400, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	world.grid.clear()
	world.grid.insert(primary.id, primary.position)
	world.grid.insert(distant.id, distant.position)

	var system := ProjectileSystem.new(world)
	system.spawn(tower, primary.id, 600.0, 50.0, [] as Array[StringName])
	system.tick(0.5)

	assert_float(distant.hp).is_equal_approx(100.0, 0.001)

func test_splash_spares_an_enemy_inside_the_query_square_but_outside_the_circle() -> void:
	# grid 的 broad phase 回傳的候選是以正方形覆蓋目標位置的所有格子，
	# 所以可能包含距離超過半徑的敵人。此處驗證精確的圓形判定確實會排除這些敵人。
	var world := _make_world()
	var primary := _add_enemy(world, Vector2(60, 0), 100.0)
	var near_miss := _add_enemy(world, Vector2(105, 45), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	world.grid.clear()
	world.grid.insert(primary.id, primary.position)
	world.grid.insert(near_miss.id, near_miss.position)

	var system := ProjectileSystem.new(world)
	system.spawn(tower, primary.id, 600.0, 50.0, [] as Array[StringName])
	system.tick(0.5)

	assert_float(primary.hp).is_equal_approx(80.0, 0.001)
	assert_float(near_miss.hp).override_failure_message(
		"grid 是 broad phase，只能初篩候選。精確的圓形距離判定才能排除位在查詢方形內、" +
		"但圓形外的敵人。若此判定被刪除，near_miss 會被誤傷"
	).is_equal_approx(100.0, 0.001)

func test_single_target_projectile_does_not_splash() -> void:
	var world := _make_world()
	var primary := _add_enemy(world, Vector2(60, 0), 100.0)
	var nearby := _add_enemy(world, Vector2(70, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	world.grid.clear()
	world.grid.insert(primary.id, primary.position)
	world.grid.insert(nearby.id, nearby.position)

	var system := ProjectileSystem.new(world)
	system.spawn(tower, primary.id, 600.0, 0.0, [] as Array[StringName])
	system.tick(0.5)

	assert_float(nearby.hp).override_failure_message(
		"splash_radius 為 0 時只能打到主目標"
	).is_equal_approx(100.0, 0.001)

## Fix 4 的迴歸守衛:主目標必須無條件被打到,不能只靠 grid 查詢碰巧命中。
## 這裡刻意不建 grid(維持空白),模擬 grid 尚未於本 tick 重建的情境——
## 若命中邏輯又退回「只靠 grid.query_radius 回傳主目標」,這裡就會失敗。
func test_splash_damages_its_target_even_if_the_grid_is_stale() -> void:
	var world := _make_world()
	var primary := _add_enemy(world, Vector2(60, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	# world.grid 故意留空,不插入 primary——這正是重現 bug 的關鍵設定

	var system := ProjectileSystem.new(world)
	system.spawn(tower, primary.id, 600.0, 50.0, [] as Array[StringName])
	system.tick(0.5)

	assert_float(primary.hp).override_failure_message(
		"splash 投射物的主目標必須直接命中,不能只靠 grid 查詢是否剛好回傳它——" +
		"grid 是否已在本 tick 重建是 BattleSim 的排程細節,主目標受不受傷不該取決於它"
	).is_equal_approx(80.0, 0.001)

func test_on_hit_effect_is_applied_to_the_target() -> void:
	var world := _make_world()
	world.effect_defs[&"chill"] = {"id": "chill", "kind": "slow", "magnitude": 0.5, "duration": 3.0}
	var enemy := _add_enemy(world, Vector2(60, 0), 100.0)
	enemy.base_speed = 100.0
	enemy.reset_derived_stats()
	var tower := _make_tower(world, Vector2(0, 0))

	var system := ProjectileSystem.new(world)
	system.spawn(tower, enemy.id, 600.0, 0.0, [&"chill"] as Array[StringName])
	system.tick(0.5)

	assert_array(enemy.active_effects).has_size(1)
	world.status_system.recompute(enemy)
	assert_float(enemy.speed).override_failure_message(
		"命中後施加的減速必須反映在衍生速度上"
	).is_equal_approx(50.0, 0.001)

func test_splash_applies_effects_to_everyone_hit() -> void:
	var world := _make_world()
	world.effect_defs[&"chill"] = {"id": "chill", "kind": "slow", "magnitude": 0.5, "duration": 3.0}
	var primary := _add_enemy(world, Vector2(60, 0), 100.0)
	var nearby := _add_enemy(world, Vector2(90, 0), 100.0)
	var tower := _make_tower(world, Vector2(0, 0))
	world.grid.clear()
	world.grid.insert(primary.id, primary.position)
	world.grid.insert(nearby.id, nearby.position)

	var system := ProjectileSystem.new(world)
	system.spawn(tower, primary.id, 600.0, 50.0, [&"chill"] as Array[StringName])
	system.tick(0.5)

	assert_array(nearby.active_effects).has_size(1)
