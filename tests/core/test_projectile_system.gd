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
