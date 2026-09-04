extends GdUnitTestSuite

## 釘住 BattleSim._tick() 的步驟順序。
## 這些不變式沒有測試守著的話，任何一次重排都會靜默地改變遊戲行為。

const FRAME := 1.0 / 30.0
const PATH_ID := &"main"

func _make_world() -> WorldState:
	var world := WorldState.new()
	var points := PackedVector2Array([
		Vector2(0, 0), Vector2(200, 0), Vector2(400, 0), Vector2(600, 0),
	])
	world.paths[PATH_ID] = PathData.new(points, 200.0)
	world.gold = 0
	world.lives = 20
	return world

func _add_enemy(world: WorldState, speed: float) -> Enemy:
	var enemy := Enemy.new()
	enemy.enemy_id = &"orc_grunt"
	enemy.hp = 1000.0
	enemy.max_hp = 1000.0
	enemy.base_speed = speed
	enemy.bounty = 7
	enemy.path_id = PATH_ID
	enemy.reset_derived_stats()
	world.add_enemy(enemy)
	return enemy

func test_status_applied_this_tick_affects_movement_this_tick() -> void:
	# 證明 StatusSystem 排在 MovementSystem 之前。
	# 若順序相反，減速要到下一 tick 才生效，敵人這一 tick 會走滿速。
	var world := _make_world()
	var enemy := _add_enemy(world, 300.0)
	var sim := BattleSim.new(world)
	world.status_system.apply(enemy, {"id": "chill", "kind": "slow", "magnitude": 0.5, "duration": 5.0}, &"frost_tower")

	sim.advance(FRAME)

	var expected := 300.0 * 0.5 * BattleSim.TICK_DELTA
	assert_float(enemy.distance_along).override_failure_message(
		"這一 tick 施加的減速必須在同一 tick 就生效，代表 StatusSystem 排在 MovementSystem 之前"
	).is_equal_approx(expected, 0.001)

func test_killed_enemy_awards_bounty_exactly_once() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 0.0)
	enemy.hp = 1.0
	var sim := BattleSim.new(world)
	DamageSystem.apply(enemy, 999.0, DamageSystem.PHYSICAL)

	sim.advance(FRAME)
	sim.advance(FRAME)
	sim.advance(FRAME)

	assert_int(world.gold).override_failure_message(
		"被擊殺的敵人只能發一次賞金"
	).is_equal(7)

func test_leaked_enemy_awards_no_bounty() -> void:
	var world := _make_world()
	_add_enemy(world, 100000.0)      # 一 tick 就衝到終點
	var sim := BattleSim.new(world)

	sim.advance(FRAME)
	sim.advance(FRAME)

	assert_int(world.gold).override_failure_message(
		"走到終點的敵人不該給玩家賞金"
	).is_equal(0)
	assert_int(world.lives).is_equal(19)
