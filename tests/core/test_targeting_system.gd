extends GdUnitTestSuite

func _make_tower() -> Tower:
	var tower := Tower.new()
	tower.id = 100
	tower.tower_id = &"archer_tower"
	tower.position = Vector2.ZERO
	tower.attack_range = 200.0
	tower.damage = 10.0
	tower.damage_type = DamageSystem.PHYSICAL
	tower.fire_interval = 1.0
	return tower

func _make_enemy(id: int, pos: Vector2, distance_along: float) -> Enemy:
	var enemy := Enemy.new()
	enemy.id = id
	enemy.hp = 100.0
	enemy.max_hp = 100.0
	enemy.position = pos
	enemy.distance_along = distance_along
	return enemy

## 把敵人陣列灌進 grid 與 id 查表，回傳 [grid, enemies_by_id]
func _index(enemies: Array) -> Array:
	var grid := UniformGrid.new()
	var by_id: Dictionary = {}
	for enemy: Enemy in enemies:
		grid.insert(enemy.id, enemy.position)
		by_id[enemy.id] = enemy
	return [grid, by_id]

func test_no_enemies_returns_zero() -> void:
	var indexed := _index([])
	assert_int(TargetingSystem.find_first(_make_tower(), indexed[0], indexed[1])).is_equal(0)

func test_single_enemy_in_range_is_selected() -> void:
	var indexed := _index([_make_enemy(1, Vector2(50, 0), 50.0)])
	assert_int(TargetingSystem.find_first(_make_tower(), indexed[0], indexed[1])).is_equal(1)

func test_enemy_outside_range_is_not_selected() -> void:
	# 落在 grid 查詢的方形範圍內，但超出圓形射程——驗證精確距離判定有做
	var indexed := _index([_make_enemy(1, Vector2(190, 190), 50.0)])
	assert_int(TargetingSystem.find_first(_make_tower(), indexed[0], indexed[1])).is_equal(0)

func test_first_strategy_picks_furthest_along_path() -> void:
	var indexed := _index([
		_make_enemy(1, Vector2(50, 0), 50.0),
		_make_enemy(2, Vector2(100, 0), 120.0),
		_make_enemy(3, Vector2(80, 0), 90.0),
	])
	assert_int(TargetingSystem.find_first(_make_tower(), indexed[0], indexed[1])).is_equal(2)

func test_dead_enemy_is_skipped() -> void:
	var dead := _make_enemy(1, Vector2(100, 0), 150.0)
	dead.alive = false
	var alive := _make_enemy(2, Vector2(50, 0), 50.0)
	var indexed := _index([dead, alive])
	assert_int(TargetingSystem.find_first(_make_tower(), indexed[0], indexed[1])).is_equal(2)

func test_leaked_enemy_is_skipped() -> void:
	var leaked := _make_enemy(1, Vector2(100, 0), 150.0)
	leaked.leaked = true
	var normal := _make_enemy(2, Vector2(50, 0), 50.0)
	var indexed := _index([leaked, normal])
	assert_int(TargetingSystem.find_first(_make_tower(), indexed[0], indexed[1])).is_equal(2)
