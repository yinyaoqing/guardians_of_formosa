extends GdUnitTestSuite

const PATH_ID := &"main"

func _make_paths() -> Dictionary:
	var points := PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(200, 0),
	])
	return {PATH_ID: PathData.new(points, 100.0)}

func _make_enemy() -> Enemy:
	var enemy := Enemy.new()
	enemy.id = 1
	enemy.enemy_id = &"orc_grunt"
	enemy.hp = 100.0
	enemy.max_hp = 100.0
	enemy.speed = 50.0
	enemy.path_id = PATH_ID
	return enemy

func test_enemy_advances_by_speed_times_delta() -> void:
	var enemy := _make_enemy()
	MovementSystem.tick([enemy], _make_paths(), 1.0)
	assert_float(enemy.distance_along).is_equal_approx(50.0, 0.001)

func test_position_is_cached_after_tick() -> void:
	var enemy := _make_enemy()
	MovementSystem.tick([enemy], _make_paths(), 1.0)
	assert_float(enemy.position.x).is_equal_approx(50.0, 0.001)

func test_enemy_reaching_path_end_is_marked_leaked() -> void:
	var enemy := _make_enemy()
	enemy.distance_along = 190.0
	MovementSystem.tick([enemy], _make_paths(), 1.0)
	assert_bool(enemy.leaked).is_true()
	assert_float(enemy.distance_along).is_equal_approx(200.0, 0.001)

func test_leaked_enemy_does_not_advance_further() -> void:
	var enemy := _make_enemy()
	enemy.leaked = true
	enemy.distance_along = 200.0
	MovementSystem.tick([enemy], _make_paths(), 1.0)
	assert_float(enemy.distance_along).is_equal_approx(200.0, 0.001)

func test_dead_enemy_does_not_advance() -> void:
	var enemy := _make_enemy()
	enemy.alive = false
	MovementSystem.tick([enemy], _make_paths(), 1.0)
	assert_float(enemy.distance_along).is_equal_approx(0.0, 0.001)

func test_blocked_enemy_does_not_advance() -> void:
	# 攔截機制不是重新尋路，而是停止推進 distance_along
	var enemy := _make_enemy()
	enemy.blocked_by = 42
	MovementSystem.tick([enemy], _make_paths(), 1.0)
	assert_float(enemy.distance_along).is_equal_approx(0.0, 0.001)
