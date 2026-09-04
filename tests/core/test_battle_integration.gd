extends GdUnitTestSuite

const FRAME_60FPS := 1.0 / 60.0
const PATH_ID := &"main"

func _make_world() -> WorldState:
	var world := WorldState.new()
	var points := PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(200, 0),
		Vector2(300, 0),
	])
	world.paths[PATH_ID] = PathData.new(points, 100.0)
	world.gold = 0
	world.lives = 20
	return world

func _add_enemy(world: WorldState, hp: float, speed: float, bounty: int) -> Enemy:
	var enemy := Enemy.new()
	enemy.enemy_id = &"orc_grunt"
	enemy.hp = hp
	enemy.max_hp = hp
	enemy.speed = speed
	enemy.bounty = bounty
	enemy.path_id = PATH_ID
	world.add_enemy(enemy)
	return enemy

func _add_tower(world: WorldState, pos: Vector2, damage: float, fire_interval: float) -> Tower:
	var tower := Tower.new()
	tower.tower_id = &"archer_tower"
	tower.position = pos
	tower.attack_range = 150.0
	tower.damage = damage
	tower.damage_type = DamageSystem.PHYSICAL
	tower.fire_interval = fire_interval
	world.add_tower(tower)
	return tower

## 推進模擬指定秒數
func _run(sim: BattleSim, seconds: float) -> void:
	var frames := int(seconds / FRAME_60FPS)
	for i in frames:
		sim.advance(FRAME_60FPS)

func test_tower_kills_enemy_in_range() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 30.0, 0.0, 5)
	enemy.position = Vector2(50, 0)
	_add_tower(world, Vector2(50, 0), 10.0, 0.5)
	var sim := BattleSim.new(world)
	_run(sim, 2.0)
	assert_bool(enemy.alive).is_false()

func test_killing_enemy_awards_bounty_once() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 10.0, 0.0, 7)
	enemy.position = Vector2(50, 0)
	_add_tower(world, Vector2(50, 0), 10.0, 0.5)
	var sim := BattleSim.new(world)
	_run(sim, 3.0)
	assert_int(world.gold).is_equal(7)

func test_enemy_reaching_end_costs_a_life() -> void:
	var world := _make_world()
	_add_enemy(world, 1000.0, 400.0, 5)
	var sim := BattleSim.new(world)
	_run(sim, 2.0)
	assert_int(world.lives).is_equal(19)

func test_leaked_enemy_only_costs_one_life() -> void:
	var world := _make_world()
	_add_enemy(world, 1000.0, 400.0, 5)
	var sim := BattleSim.new(world)
	_run(sim, 5.0)
	assert_int(world.lives).is_equal(19)

func test_tower_out_of_range_does_not_damage() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 100.0, 0.0, 5)
	enemy.position = Vector2(0, 0)
	_add_tower(world, Vector2(1000, 1000), 10.0, 0.5)
	var sim := BattleSim.new(world)
	_run(sim, 2.0)
	assert_float(enemy.hp).is_equal_approx(100.0, 0.001)

func test_fire_interval_limits_shots() -> void:
	# 1 秒內、射速 0.5 秒一發，應打 2 發共 20 傷害，留下 980.0 HP
	var world := _make_world()
	var enemy := _add_enemy(world, 1000.0, 0.0, 5)
	enemy.position = Vector2(50, 0)
	_add_tower(world, Vector2(50, 0), 10.0, 0.5)
	var sim := BattleSim.new(world)
	_run(sim, 1.0)
	assert_float(enemy.hp).is_equal_approx(980.0, 0.001)
