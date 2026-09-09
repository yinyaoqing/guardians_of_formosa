extends GdUnitTestSuite

const TICK := 1.0 / 30.0

const FENCE_DEF := {
	"id": "fence_tower", "name_key": "tower.fence_tower.name", "kind": "barracks",
	"damage_type": "physical", "icon": "res://icon.svg",
	"levels": [
		{"cost": 60, "soldier_count": 1, "soldier_hp": 90.0, "soldier_damage": 6.0,
		 "soldier_attack_interval": 1.0, "soldier_armor": 0.0, "respawn_time": 5.0,
		 "regen_per_second": 4.0, "sprite": "res://icon.svg"},
		{"cost": 110, "soldier_count": 2, "soldier_hp": 150.0, "soldier_damage": 10.0,
		 "soldier_attack_interval": 0.9, "soldier_armor": 0.0, "respawn_time": 4.0,
		 "regen_per_second": 6.0, "sprite": "res://icon.svg"}
	]
}

func _world() -> WorldState:
	var world := WorldState.new()
	world.tower_defs = {&"fence_tower": FENCE_DEF}
	world.available_towers = [&"fence_tower"]
	world.gold = 500
	world.sell_refund_ratio = 0.6
	var points := PackedVector2Array()
	for i in 41:
		points.append(Vector2(float(i) * 10.0, 0.0))
	world.paths[&"main"] = PathData.new(points, 10.0)
	var slot := BuildSlot.new()
	slot.position = Vector2(100.0, 20.0)
	world.add_build_slot(slot)
	return world

func _build(world: WorldState) -> Tower:
	BuildSystem.apply(world, GameIntent.build(world.build_slots[0].id, &"fence_tower"))
	return world.towers[0]

func _enemy_at(world: WorldState, distance: float, hp: float) -> Enemy:
	var enemy := Enemy.new()
	enemy.max_hp = hp
	enemy.hp = hp
	enemy.path_id = &"main"
	enemy.distance_along = distance
	enemy.melee_damage = 0.0
	enemy.base_speed = 45.0
	enemy.reset_derived_stats()
	world.add_enemy(enemy)
	return enemy

## 最容易生出來的 bug：小兵死了但沒清 blocked_by，敵人永遠卡在原地。
func test_a_blocked_enemy_resumes_when_its_soldier_dies() -> void:
	var world := _world()
	var tower := _build(world)
	var sim := BattleSim.new(world)
	var enemy := _enemy_at(world, 100.0, 500.0)

	sim.advance(TICK)                       # 補兵 + 交戰
	assert_int(enemy.blocked_by).is_not_equal(0)

	var soldier: Soldier = world.soldiers[0]
	soldier.hp = 0.0
	soldier.alive = false
	sim.advance(TICK)                       # 這一 tick 內 _remove_dead 清掉它

	assert_int(enemy.blocked_by).override_failure_message(
		"小兵死了但 blocked_by 沒清掉。敵人會永遠停在原地不動，而畫面上\n" +
		"看起來像「敵人卡住了」而不是「清理漏了一步」。"
	).is_equal(0)

	var before := enemy.distance_along
	sim.advance(TICK)
	assert_float(enemy.distance_along).is_greater(before)

func test_the_dead_soldiers_slot_starts_its_respawn_timer() -> void:
	var world := _world()
	var tower := _build(world)
	var sim := BattleSim.new(world)
	sim.advance(TICK)

	var soldier: Soldier = world.soldiers[0]
	soldier.alive = false
	sim.advance(TICK)

	assert_int(tower.soldier_ids[0]).is_equal(0)
	assert_float(tower.respawn_timers[0]).is_greater(0.0)

func test_a_soldier_is_released_when_its_enemy_dies() -> void:
	var world := _world()
	_build(world)
	var sim := BattleSim.new(world)
	var enemy := _enemy_at(world, 100.0, 500.0)
	sim.advance(TICK)

	var soldier: Soldier = world.soldiers[0]
	assert_int(soldier.engaged_enemy_id).is_equal(enemy.id)

	enemy.hp = 0.0
	enemy.alive = false
	sim.advance(TICK)

	assert_int(soldier.engaged_enemy_id).is_equal(0)

func test_selling_a_barracks_removes_its_soldiers_and_frees_the_enemy() -> void:
	var world := _world()
	var tower := _build(world)
	var sim := BattleSim.new(world)
	var enemy := _enemy_at(world, 100.0, 500.0)
	sim.advance(TICK)
	assert_int(world.soldiers.size()).is_equal(1)

	BuildSystem.apply(world, GameIntent.sell(tower.id))

	assert_int(world.soldiers.size()).is_equal(0)
	assert_int(world.soldiers_by_id.size()).is_equal(0)
	assert_int(enemy.blocked_by).is_equal(0)

func test_upgrading_a_barracks_heals_its_soldiers_to_the_new_max() -> void:
	var world := _world()
	var tower := _build(world)
	var sim := BattleSim.new(world)
	sim.advance(TICK)

	var soldier: Soldier = world.soldiers[0]
	soldier.hp = 20.0

	BuildSystem.apply(world, GameIntent.upgrade(tower.id))
	sim.advance(TICK)

	# 升級把名額陣列整個換掉，舊小兵移除、新等級的兩個補上，全部滿血
	assert_int(world.soldiers.size()).is_equal(2)
	for s: Soldier in world.soldiers:
		assert_float(s.hp).is_equal_approx(150.0, 0.001)
