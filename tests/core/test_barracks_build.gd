extends GdUnitTestSuite

const FENCE_DEF := {
	"id": "fence_tower",
	"name_key": "tower.fence_tower.name",
	"kind": "barracks",
	"damage_type": "physical",
	"icon": "res://icon.svg",
	"levels": [
		{"cost": 60, "soldier_count": 2, "soldier_hp": 90.0, "soldier_damage": 6.0,
		 "soldier_attack_interval": 1.0, "soldier_armor": 0.10, "respawn_time": 12.0,
		 "regen_per_second": 4.0, "sprite": "res://icon.svg"},
		{"cost": 110, "soldier_count": 3, "soldier_hp": 150.0, "soldier_damage": 10.0,
		 "soldier_attack_interval": 0.9, "soldier_armor": 0.20, "respawn_time": 11.0,
		 "regen_per_second": 6.0, "sprite": "res://icon.svg"}
	]
}

func _world_with_a_slot_and_a_path() -> WorldState:
	var world := WorldState.new()
	world.tower_defs = {&"fence_tower": FENCE_DEF}
	world.available_towers = [&"fence_tower"]
	world.gold = 500

	var points := PackedVector2Array()
	for i in 11:
		points.append(Vector2(float(i) * 10.0, 0.0))
	world.paths[&"main"] = PathData.new(points, 10.0)

	var slot := BuildSlot.new()
	slot.position = Vector2(70.0, 40.0)   # 最近的取樣點是 (70, 0)
	world.add_build_slot(slot)
	return world

func _build_fence(world: WorldState) -> Tower:
	var intent := GameIntent.build(world.build_slots[0].id, &"fence_tower")
	BuildSystem.apply(world, intent)
	return world.towers[0] if not world.towers.is_empty() else null

## 這條就是「不分派會 crash」的守衛：兵營的定義沒有 damage/attack_range 等鍵。
func test_building_a_barracks_does_not_touch_shooter_only_fields() -> void:
	var world := _world_with_a_slot_and_a_path()
	var tower := _build_fence(world)

	assert_object(tower).is_not_null()
	assert_str(tower.kind).is_equal("barracks")

func test_barracks_sizes_its_slot_arrays_to_the_level_soldier_count() -> void:
	var world := _world_with_a_slot_and_a_path()
	var tower := _build_fence(world)

	assert_int(tower.soldier_ids.size()).is_equal(2)
	assert_int(tower.respawn_timers.size()).is_equal(2)
	# 名額一開始是空的、倒數是 0，所以 GarrisonSystem 的第一個 tick 就會補滿
	assert_int(tower.soldier_ids[0]).is_equal(0)
	assert_float(tower.respawn_timers[0]).is_equal_approx(0.0, 0.001)

func test_barracks_post_is_the_nearest_path_position() -> void:
	var world := _world_with_a_slot_and_a_path()
	var tower := _build_fence(world)

	assert_str(tower.post_path_id).is_equal("main")
	assert_float(tower.post_distance).is_equal_approx(70.0, 0.001)
	assert_vector(tower.post_position).is_equal_approx(Vector2(70.0, 0.0), Vector2(0.001, 0.001))

func test_upgrading_a_barracks_resizes_the_slot_arrays() -> void:
	var world := _world_with_a_slot_and_a_path()
	var tower := _build_fence(world)
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))

	assert_int(tower.level).is_equal(2)
	assert_int(tower.soldier_ids.size()).is_equal(3)
	assert_float(tower.soldier_hp).is_equal_approx(150.0, 0.001)

## 射擊塔的既有行為不能因為分派而改變。
func test_shooter_towers_still_get_their_stats() -> void:
	var world := WorldState.new()
	world.tower_defs = {&"t": {
		"id": "t", "name_key": "k", "damage_type": "physical", "icon": "res://icon.svg",
		"levels": [{"cost": 10, "damage": 18.0, "attack_range": 200.0, "fire_interval": 1.2,
					"projectile_speed": 700.0, "splash_radius": 0.0, "on_hit_effects": [],
					"sprite": "res://icon.svg"}]
	}}
	world.available_towers = [&"t"]
	world.gold = 100
	var slot := BuildSlot.new()
	world.add_build_slot(slot)
	BuildSystem.apply(world, GameIntent.build(slot.id, &"t"))

	var tower: Tower = world.towers[0]
	assert_str(tower.kind).is_equal("shooter")
	assert_float(tower.damage).is_equal_approx(18.0, 0.001)
	assert_int(tower.soldier_ids.size()).is_equal(0)
