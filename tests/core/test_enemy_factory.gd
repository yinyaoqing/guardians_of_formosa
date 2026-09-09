extends GdUnitTestSuite

## 造敵人的邏輯只能有一份。DataRegistry 給場景層用，WaveSystem 給 tick 用，
## 兩邊各寫一份就會漂移——而漂移的症狀是「某條路生出來的敵人少了護甲」，
## 沒有測試同時看兩邊就抓不到。

const DEF := {
	"id": "orc_grunt",
	"name_key": "enemy.orc_grunt.name",
	"hp": 120.0,
	"speed": 45.0,
	"armor": 0.2,
	"magic_resist": 0.1,
	"bounty": 6,
	"sprite": "res://game/assets/placeholder_enemy.png",
	"frame_count": 8,
}

func test_from_def_fills_every_stat() -> void:
	var enemy := EnemyFactory.from_def(DEF, &"orc_grunt", &"main")
	assert_bool(enemy.enemy_id == &"orc_grunt").is_true()
	assert_bool(enemy.path_id == &"main").is_true()
	assert_float(enemy.hp).is_equal_approx(120.0, 0.001)
	assert_float(enemy.max_hp).is_equal_approx(120.0, 0.001)
	assert_float(enemy.base_speed).is_equal_approx(45.0, 0.001)
	assert_float(enemy.base_armor).is_equal_approx(0.2, 0.001)
	assert_float(enemy.base_magic_resist).override_failure_message(
		"魔抗漏了會讓某些敵人莫名其妙變脆，而且只在特定塔種面前看得出來"
	).is_equal_approx(0.1, 0.001)
	assert_int(enemy.bounty).is_equal(6)

func test_from_def_resets_derived_stats() -> void:
	# 衍生值每 tick 由 StatusSystem 重算，但建構時就要是合理的初值，
	# 否則新生的敵人在第一個 tick 之前速度是 0。
	var enemy := EnemyFactory.from_def(DEF, &"orc_grunt", &"main")
	assert_float(enemy.speed).override_failure_message(
		"沒有呼叫 reset_derived_stats()，新生的敵人速度會是 0"
	).is_equal_approx(45.0, 0.001)
	assert_float(enemy.armor).is_equal_approx(0.2, 0.001)

func test_a_fresh_enemy_is_alive_and_at_the_start() -> void:
	var enemy := EnemyFactory.from_def(DEF, &"orc_grunt", &"main")
	assert_bool(enemy.alive).is_true()
	assert_bool(enemy.leaked).is_false()
	assert_float(enemy.distance_along).is_equal_approx(0.0, 0.001)
