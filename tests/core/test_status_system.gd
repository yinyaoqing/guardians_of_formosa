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

func test_slow_reduces_derived_speed_without_touching_base() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.recompute(enemy)
	assert_float(enemy.speed).is_equal_approx(65.0, 0.001)     # 100 × (1 − 0.35)
	assert_float(enemy.base_speed).override_failure_message(
		"基礎值絕對不得被狀態效果寫入，否則效果到期後無法還原"
	).is_equal_approx(100.0, 0.001)

func test_strongest_slow_wins_and_slows_are_not_summed() -> void:
	# 0.35 與 0.60 相加會是 0.95，取最強應為 0.60
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.apply(enemy, DEEP_CHILL, &"ice_mage_tower")
	_system.recompute(enemy)
	assert_float(enemy.speed).override_failure_message(
		"不同來源的減速取最強，不相加"
	).is_equal_approx(40.0, 0.001)                              # 100 × (1 − 0.60)

func test_stun_zeroes_speed_and_overrides_slow() -> void:
	var enemy := _make_enemy()
	var stun := {"id": "stun_shock", "kind": "stun", "duration": 1.0}
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.apply(enemy, stun, &"shock_tower")
	_system.recompute(enemy)
	assert_float(enemy.speed).is_equal_approx(0.0, 0.001)
	assert_bool(enemy.stunned).is_true()

func test_armor_break_reduces_armor() -> void:
	var enemy := _make_enemy()
	var sunder := {"id": "sunder", "kind": "armor_break", "magnitude": 0.15, "duration": 5.0}
	_system.apply(enemy, sunder, &"sunder_tower")
	_system.recompute(enemy)
	assert_float(enemy.armor).is_equal_approx(0.05, 0.001)      # 0.2 − 0.15

func test_armor_break_cannot_push_armor_below_zero() -> void:
	var enemy := _make_enemy()
	var heavy_sunder := {"id": "heavy_sunder", "kind": "armor_break", "magnitude": 0.9, "duration": 5.0}
	_system.apply(enemy, heavy_sunder, &"sunder_tower")
	_system.recompute(enemy)
	assert_float(enemy.armor).override_failure_message(
		"護甲不得為負，否則會變成傷害放大"
	).is_equal_approx(0.0, 0.001)

func test_recompute_with_no_effects_restores_base_values() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.recompute(enemy)
	enemy.active_effects.clear()
	_system.recompute(enemy)
	assert_float(enemy.speed).is_equal_approx(100.0, 0.001)
	assert_bool(enemy.stunned).is_false()

func test_effect_expires_after_its_duration() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")     # duration 2.5
	_system.tick([enemy], 3.0)
	assert_array(enemy.active_effects).has_size(0)
	assert_float(enemy.speed).override_failure_message(
		"效果到期後速度必須回到基礎值"
	).is_equal_approx(100.0, 0.001)

func test_effect_survives_until_its_duration_elapses() -> void:
	var enemy := _make_enemy()
	_system.apply(enemy, CHILL, &"frost_tower")
	_system.tick([enemy], 1.0)
	assert_array(enemy.active_effects).has_size(1)
	assert_float(enemy.speed).is_equal_approx(65.0, 0.001)

func test_expired_effect_is_returned_to_the_pool() -> void:
	var pool := ObjectPool.new(func() -> StatusEffect: return StatusEffect.new(), 4)
	var system := StatusSystem.new(pool)
	var enemy := _make_enemy()
	system.apply(enemy, CHILL, &"frost_tower")
	assert_int(pool.free_count()).is_equal(3)
	system.tick([enemy], 3.0)
	assert_int(pool.free_count()).override_failure_message(
		"到期的效果實例必須歸還池中，否則池會逐漸耗盡"
	).is_equal(4)

func test_dot_deals_damage_scaled_by_delta() -> void:
	var enemy := _make_enemy()
	var poison := {"id": "poison", "kind": "dot", "magnitude": 10.0, "duration": 5.0, "damage_type": "true"}
	_system.apply(enemy, poison, &"poison_tower")
	_system.tick([enemy], 1.0)                      # 每秒 10 傷害 × 1 秒
	assert_float(enemy.hp).is_equal_approx(90.0, 0.001)

func test_dot_respects_damage_type() -> void:
	# 護甲 0.2 的敵人吃物理 DoT 應只受 80% 傷害，證明 DoT 走了 DamageSystem
	var enemy := _make_enemy()
	var bleed := {"id": "bleed", "kind": "dot", "magnitude": 10.0, "duration": 5.0, "damage_type": "physical"}
	_system.apply(enemy, bleed, &"blade_tower")
	_system.tick([enemy], 1.0)
	assert_float(enemy.hp).override_failure_message(
		"DoT 必須經過 DamageSystem，因此要吃護甲減免"
	).is_equal_approx(92.0, 0.001)                  # 100 − 10 × (1 − 0.2)

func test_dead_enemy_effects_are_not_ticked() -> void:
	var enemy := _make_enemy()
	var poison := {"id": "poison", "kind": "dot", "magnitude": 10.0, "duration": 5.0, "damage_type": "true"}
	_system.apply(enemy, poison, &"poison_tower")
	enemy.alive = false
	_system.tick([enemy], 1.0)
	assert_float(enemy.hp).is_equal_approx(100.0, 0.001)
