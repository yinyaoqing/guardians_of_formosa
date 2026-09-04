extends GdUnitTestSuite

const CHILL := {"id": "chill", "kind": "slow", "magnitude": 0.35, "duration": 2.5}
const DEEP_CHILL := {"id": "deep_chill", "kind": "slow", "magnitude": 0.60, "duration": 1.0}

var _system: StatusSystem

func before_test() -> void:
	var pool := ObjectPool.new(func() -> StatusEffect: return StatusEffect.new(), 16)
	_system = StatusSystem.new(pool)

func _make_enemy() -> Enemy:
	var enemy := Enemy.new()
	enemy.id = 1
	enemy.hp = 100.0
	enemy.max_hp = 100.0
	enemy.base_speed = 100.0
	enemy.base_armor = 0.2
	enemy.reset_derived_stats()
	return enemy

func test_applying_effect_adds_it_to_the_enemy() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	assert_array(enemy.active_effects).has_size(1)

func test_same_kind_and_source_refreshes_instead_of_stacking() -> void:
	# 三座同型塔打同一隻敵人不該疊三層
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.apply(enemy, CHILL, &"frost_tower")
	assert_array(enemy.active_effects).override_failure_message(
		"同一 kind 與 source 必須刷新既有效果，不得新增"
	).has_size(1)

func test_refresh_takes_the_longer_remaining_time() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")        # remaining 2.5
	enemy.active_effects[0].remaining = 0.5            # 模擬已經過了一段時間
	_system.apply(enemy, CHILL, &"frost_tower")        # 應刷新回 2.5
	assert_float(enemy.active_effects[0].remaining).is_equal_approx(2.5, 0.001)

func test_refresh_does_not_shorten_a_longer_remaining_time() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	enemy.active_effects[0].remaining = 10.0           # 比新效果長
	_system.apply(enemy, CHILL, &"frost_tower")
	assert_float(enemy.active_effects[0].remaining).is_equal_approx(10.0, 0.001)

func test_same_kind_from_different_source_coexists() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.apply(enemy, DEEP_CHILL, &"ice_mage_tower")
	assert_array(enemy.active_effects).override_failure_message(
		"不同來源的同類效果必須並存，強度在重算時才取最大值"
	).has_size(2)

func test_effect_records_source_and_magnitude() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	var effect: StatusEffect = enemy.active_effects[0]
	assert_str(effect.source).is_equal("frost_tower")
	assert_str(effect.kind).is_equal("slow")
	assert_float(effect.magnitude).is_equal_approx(0.35, 0.001)

func test_dot_effect_records_damage_type() -> void:
	var enemy := _make_enemy()
	var poison := {"id": "poison", "kind": "dot", "magnitude": 12.0, "duration": 4.0, "damage_type": "true"}
	_system.apply(enemy, poison, &"poison_tower")
	assert_str(enemy.active_effects[0].damage_type).is_equal("true")
