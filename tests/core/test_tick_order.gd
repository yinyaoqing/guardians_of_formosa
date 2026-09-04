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

func test_effects_on_a_killed_enemy_are_returned_to_the_pool() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 0.0)
	var sim := BattleSim.new(world)

	# Apply a status effect that won't expire during test
	world.status_system.apply(enemy, {"id": "chill", "kind": "slow", "magnitude": 0.5, "duration": 100.0}, &"frost_tower")

	# Record pool state after applying (i.e., the "borrowed" state)
	var free_count_borrowed := world.effect_pool.free_count()

	# Kill the enemy
	DamageSystem.apply(enemy, 1001.0, DamageSystem.PHYSICAL)

	# Advance one tick to trigger _remove_dead
	sim.advance(FRAME)

	# Verify the effect was released to the pool
	assert_array(enemy.active_effects).override_failure_message(
		"死亡敵人的效果清單必須被清空"
	).has_size(0)
	assert_int(world.effect_pool.free_count()).override_failure_message(
		"死亡敵人身上的效果必須歸還池中，否則長戰役中池會逐漸耗盡"
	).is_equal(free_count_borrowed + 1)

func test_projectile_spawned_this_tick_does_not_move_this_tick() -> void:
	# 證明 ProjectileSystem 排在 _tick_towers 之前。
	# 若順序相反，投射物會在生成的同一 tick 就移動一格，每一發的飛行時間都少一 tick。
	var world := _make_world()
	_add_enemy(world, 0.0)                 # 停在路徑起點 (0, 0)

	var tower := Tower.new()
	tower.tower_id = &"archer_tower"
	tower.position = Vector2(100, 0)
	tower.damage = 1.0
	tower.damage_type = DamageSystem.PHYSICAL
	tower.attack_range = 1000.0
	tower.fire_interval = 10.0             # 只讓它開一發
	tower.projectile_speed = 600.0
	world.add_tower(tower)

	var sim := BattleSim.new(world)
	sim.advance(FRAME)

	assert_array(world.projectiles).has_size(1)
	assert_float(world.projectiles[0].position.x).override_failure_message(
		"這一 tick 生成的投射物不得在同一 tick 移動，代表 ProjectileSystem 排在 _tick_towers 之前"
	).is_equal_approx(100.0, 0.001)

## 一個配置好、有一個空建塔點與一隻停住的敵人的世界
func _make_buildable_world() -> WorldState:
	var world := _make_world()
	world.tower_defs = {
		&"archer_tower": {
			"id": "archer_tower",
			"damage_type": "physical",
			"levels": [
				{"cost": 70, "damage": 9.0, "attack_range": 500.0, "fire_interval": 0.8,
				 "projectile_speed": 600.0, "splash_radius": 0.0, "on_hit_effects": []},
			],
		}
	}
	world.available_towers = [&"archer_tower"] as Array[StringName]
	world.gold = 200
	var slot := BuildSlot.new()
	slot.position = Vector2(100, 0)
	world.add_build_slot(slot)
	return world

func test_intent_queued_before_a_tick_is_applied_in_that_tick() -> void:
	var world := _make_buildable_world()
	var sim := BattleSim.new(world)
	world.queue_intent(GameIntent.build(world.build_slots[0].id, &"archer_tower"))

	sim.advance(FRAME)

	assert_array(world.towers).override_failure_message(
		"排隊的意圖必須在下一個 tick 就被套用"
	).has_size(1)
	assert_array(world.pending_intents).override_failure_message(
		"套用後佇列必須清空，否則同一筆指令會被重複執行"
	).has_size(0)

func test_a_tower_built_this_tick_can_fire_this_tick() -> void:
	# 證明意圖套用排在 tick 的第一步。若挪到 tick 尾端，
	# 這一 tick 蓋的塔要等下一 tick 才會鎖定目標，冷卻也不會啟動。
	var world := _make_buildable_world()
	_add_enemy(world, 0.0)                 # 停在路徑起點 (0, 0)，在射程 500 內
	var sim := BattleSim.new(world)
	world.queue_intent(GameIntent.build(world.build_slots[0].id, &"archer_tower"))

	sim.advance(FRAME)

	var tower: Tower = world.towers[0]
	assert_int(tower.target_id).override_failure_message(
		"這一 tick 蓋好的塔，這一 tick 就該鎖定得到目標——代表意圖套用排在 tick 第一步"
	).is_greater(0)
	assert_float(tower.cooldown).override_failure_message(
		"這一 tick 蓋好的塔，這一 tick 就該開得了火"
	).is_greater(0.0)
