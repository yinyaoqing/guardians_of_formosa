extends GdUnitTestSuite

func _make_enemy(armor: float, magic_resist: float) -> Enemy:
	var enemy := Enemy.new()
	enemy.id = 1
	enemy.hp = 100.0
	enemy.max_hp = 100.0
	enemy.base_armor = armor
	enemy.base_magic_resist = magic_resist
	enemy.reset_derived_stats()
	return enemy

func test_physical_damage_is_reduced_by_armor() -> void:
	var enemy := _make_enemy(0.5, 0.0)
	var dealt := DamageSystem.apply(enemy, 100.0, DamageSystem.PHYSICAL)
	assert_float(dealt).is_equal_approx(50.0, 0.001)
	assert_float(enemy.hp).is_equal_approx(50.0, 0.001)

func test_magic_damage_ignores_armor_and_uses_magic_resist() -> void:
	var enemy := _make_enemy(0.9, 0.25)
	var dealt := DamageSystem.apply(enemy, 100.0, DamageSystem.MAGIC)
	assert_float(dealt).is_equal_approx(75.0, 0.001)

func test_true_damage_ignores_all_reduction() -> void:
	var enemy := _make_enemy(0.9, 0.9)
	var dealt := DamageSystem.apply(enemy, 100.0, DamageSystem.TRUE_DAMAGE)
	assert_float(dealt).is_equal_approx(100.0, 0.001)

func test_lethal_damage_marks_enemy_dead_and_clamps_hp_to_zero() -> void:
	var enemy := _make_enemy(0.0, 0.0)
	DamageSystem.apply(enemy, 250.0, DamageSystem.PHYSICAL)
	assert_bool(enemy.alive).is_false()
	assert_float(enemy.hp).is_equal_approx(0.0, 0.001)

func test_damage_to_dead_enemy_deals_nothing() -> void:
	var enemy := _make_enemy(0.0, 0.0)
	enemy.alive = false
	var dealt := DamageSystem.apply(enemy, 50.0, DamageSystem.PHYSICAL)
	assert_float(dealt).is_equal_approx(0.0, 0.001)

func test_full_armor_reduction_deals_no_damage_but_does_not_heal() -> void:
	var enemy := _make_enemy(1.0, 0.0)
	var dealt := DamageSystem.apply(enemy, 100.0, DamageSystem.PHYSICAL)
	assert_float(dealt).is_equal_approx(0.0, 0.001)
	assert_float(enemy.hp).is_equal_approx(100.0, 0.001)

func test_negative_armor_does_not_amplify_damage() -> void:
	var enemy := _make_enemy(-1.0, 0.0)
	var dealt := DamageSystem.apply(enemy, 100.0, DamageSystem.PHYSICAL)
	assert_float(dealt).is_equal_approx(100.0, 0.001)
	assert_float(enemy.hp).is_equal_approx(0.0, 0.001)

func test_negative_magic_resist_does_not_amplify_damage() -> void:
	var enemy := _make_enemy(0.0, -0.5)
	var dealt := DamageSystem.apply(enemy, 100.0, DamageSystem.MAGIC)
	assert_float(dealt).is_equal_approx(100.0, 0.001)
	assert_float(enemy.hp).is_equal_approx(0.0, 0.001)

func test_reduction_above_one_deals_no_damage_and_does_not_heal() -> void:
	var enemy := _make_enemy(1.5, 0.0)
	var dealt := DamageSystem.apply(enemy, 100.0, DamageSystem.PHYSICAL)
	assert_float(dealt).is_equal_approx(0.0, 0.001)
	assert_float(enemy.hp).is_equal_approx(100.0, 0.001)
