extends GdUnitTestSuite

const TICK := 1.0 / 30.0

func _world() -> WorldState:
	var world := WorldState.new()
	var points := PackedVector2Array()
	for i in 41:
		points.append(Vector2(float(i) * 10.0, 0.0))
	world.paths[&"main"] = PathData.new(points, 10.0)
	return world

func _soldier(world: WorldState, post: float, hp: float, damage: float, interval: float) -> Soldier:
	var soldier := Soldier.new()
	soldier.reset(hp, 0.0)
	soldier.path_id = &"main"
	soldier.post_distance = post
	soldier.position = Vector2(post, 0.0)
	soldier.damage = damage
	soldier.damage_type = DamageSystem.PHYSICAL
	soldier.attack_interval = interval
	world.add_soldier(soldier)
	return soldier

func _enemy(world: WorldState, distance: float, hp: float, melee: float) -> Enemy:
	var enemy := Enemy.new()
	enemy.max_hp = hp
	enemy.hp = hp
	enemy.path_id = &"main"
	enemy.distance_along = distance
	enemy.melee_damage = melee
	enemy.melee_interval = 1.0
	enemy.base_speed = 45.0
	enemy.reset_derived_stats()
	world.add_enemy(enemy)
	return enemy

func test_an_enemy_inside_the_window_gets_bound_to_the_soldier() -> void:
	var world := _world()
	var soldier := _soldier(world, 100.0, 90.0, 6.0, 1.0)
	var enemy := _enemy(world, 90.0, 120.0, 12.0)   # 差 10，在 24 的窗口內

	MeleeSystem.tick(world, TICK)

	assert_int(enemy.blocked_by).is_equal(soldier.id)
	assert_int(soldier.engaged_enemy_id).is_equal(enemy.id)

func test_an_enemy_outside_the_window_is_left_alone() -> void:
	var world := _world()
	_soldier(world, 100.0, 90.0, 6.0, 1.0)
	var enemy := _enemy(world, 60.0, 120.0, 12.0)   # 差 40，窗口外

	MeleeSystem.tick(world, TICK)

	assert_int(enemy.blocked_by).is_equal(0)

## 1:1。第四個敵人不該被綁住。
func test_three_soldiers_block_exactly_three_of_four_enemies() -> void:
	var world := _world()
	for i in 3:
		_soldier(world, 100.0, 90.0, 6.0, 1.0)
	var enemies: Array[Enemy] = []
	for i in 4:
		enemies.append(_enemy(world, 100.0 - float(i), 120.0, 12.0))

	MeleeSystem.tick(world, TICK)

	var blocked := 0
	for enemy in enemies:
		if enemy.blocked_by != 0:
			blocked += 1
	assert_int(blocked).override_failure_message(
		"1:1 攔截：三個小兵只能綁三個敵人，第四個必須走過去。"
	).is_equal(3)

## 交戰必須排在 MovementSystem 之前，否則剛被擋下的敵人還會多走一步。
## 這條走完整的 BattleSim，斷言的是位置精確不變——「差不多」會放過那個 bug。
func test_a_blocked_enemy_does_not_advance_on_the_tick_it_is_blocked() -> void:
	var world := _world()
	_soldier(world, 100.0, 90.0, 6.0, 1.0)
	var enemy := _enemy(world, 95.0, 120.0, 0.0)
	var sim := BattleSim.new(world)

	sim.advance(TICK)

	assert_float(enemy.distance_along).override_failure_message(
		"被攔截的敵人在攔截成立的那個 tick 內仍然前進了。\n" +
		"這代表 MeleeSystem 被排在 MovementSystem 之後。"
	).is_equal_approx(95.0, 0.0001)

func test_the_soldier_hits_the_enemy_through_the_damage_system() -> void:
	var world := _world()
	_soldier(world, 100.0, 90.0, 20.0, 1.0)
	var enemy := _enemy(world, 100.0, 200.0, 0.0)
	enemy.base_armor = 0.25
	enemy.reset_derived_stats()

	MeleeSystem.tick(world, TICK)

	# 20 × (1 - 0.25) = 15。若近戰自己算傷害、繞過減免，會扣 20。
	assert_float(enemy.hp).override_failure_message(
		"近戰傷害沒有套用護甲減免，代表它繞過了 DamageSystem——違反硬規則 #2。"
	).is_equal_approx(185.0, 0.001)

func test_the_enemy_hits_back() -> void:
	var world := _world()
	var soldier := _soldier(world, 100.0, 90.0, 6.0, 1.0)
	soldier.armor = 0.5
	var _enemy_ref := _enemy(world, 100.0, 200.0, 30.0)

	MeleeSystem.tick(world, TICK)

	# 30 × (1 - 0.5) = 15
	assert_float(soldier.hp).is_equal_approx(75.0, 0.001)

func test_attacks_respect_the_cooldown() -> void:
	var world := _world()
	_soldier(world, 100.0, 90.0, 20.0, 1.0)
	var enemy := _enemy(world, 100.0, 500.0, 0.0)

	# 第一個 tick 命中一次（冷卻自 0 起算），之後 29 個 tick 都在冷卻中
	for i in 30:
		MeleeSystem.tick(world, TICK)
	assert_float(enemy.hp).override_failure_message(
		"30 個 tick（1 秒）內，攻擊間隔 1 秒的小兵應該只打中一次。"
	).is_equal_approx(480.0, 0.001)

	# 理論上第 31 個 tick（累積滿 1.0 秒）冷卻就該歸零，但 cooldown 是逐 tick
	# 以浮點數相減：1.0 - 30 × (1/30) 在 IEEE-754 double 下不是精確的 0.0，
	# 而是殘留約 2e-16 的正值。第 31 個 tick 當下 cooldown 因此仍 > 0.0，
	# 第二次命中延後到第 32 個 tick 才發生。
	# 這不是這個系統獨有的怪癖——塔的 fire_interval 冷卻用的是同一種寫法
	# （maxf(0.0, cooldown - delta) 配 <= 0.0 判斷），同一種漂移已經記錄在
	# tests/core/test_battle_integration.gd 的 test_fire_interval_limits_shots
	# （那邊的殘值約 9.7e-17，一發射擊延後一個 tick）。兩處是同一件事，不是
	# 各自的巧合。
	for i in 2:
		MeleeSystem.tick(world, TICK)
	assert_float(enemy.hp).is_equal_approx(460.0, 0.001)

func test_a_leaked_enemy_is_never_engaged() -> void:
	var world := _world()
	_soldier(world, 100.0, 90.0, 6.0, 1.0)
	var enemy := _enemy(world, 100.0, 120.0, 12.0)
	enemy.leaked = true

	MeleeSystem.tick(world, TICK)
	assert_int(enemy.blocked_by).is_equal(0)

func test_soldiers_only_engage_enemies_on_their_own_path() -> void:
	var world := _world()
	var points := PackedVector2Array()
	for i in 41:
		points.append(Vector2(0.0, float(i) * 10.0))
	world.paths[&"side"] = PathData.new(points, 10.0)

	_soldier(world, 100.0, 90.0, 6.0, 1.0)          # path_id = main
	var enemy := _enemy(world, 100.0, 120.0, 12.0)
	enemy.path_id = &"side"

	MeleeSystem.tick(world, TICK)
	assert_int(enemy.blocked_by).is_equal(0)
