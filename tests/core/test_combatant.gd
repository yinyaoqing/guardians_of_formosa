extends GdUnitTestSuite

## Combatant 存在的唯一理由是讓 DamageSystem.apply() 同時吃得下敵人與小兵，
## 而且維持「一個入口 + 靜態型別」。這個測試套件守的就是那件事。

## 一個不是 Enemy 的 Combatant。這裡刻意不用 Soldier——Task 1 的時候
## Soldier 還不存在，而且用它會讓這個測試依賴一個它不該認識的型別。
class PlainCombatant extends Combatant:
	pass

func test_damage_system_accepts_a_combatant_that_is_not_an_enemy() -> void:
	var target := PlainCombatant.new()
	target.max_hp = 100.0
	target.hp = 100.0
	target.armor = 0.25

	# 40 × (1 - 0.25) = 30。刻意避開會讓錯誤實作也算對的巧合數字：
	# 護甲若被忽略會得到 40，若誤用 magic_resist(0.0) 也是 40，兩者都與 30 不同。
	var dealt := DamageSystem.apply(target, 40.0, DamageSystem.PHYSICAL)

	assert_float(dealt).is_equal_approx(30.0, 0.001)
	assert_float(target.hp).is_equal_approx(70.0, 0.001)

func test_enemy_is_a_combatant() -> void:
	var enemy := Enemy.new()
	assert_bool(enemy is Combatant).override_failure_message(
		"Enemy 必須繼承 Combatant，否則 DamageSystem.apply() 的型別註記會把敵人擋在門外。"
	).is_true()

func test_magic_resist_still_applies_to_enemies_after_the_refactor() -> void:
	# 五個欄位換家之後，最容易壞的是「衍生值被寫在基底、基礎值留在 Enemy」
	# 這類半途而廢的搬運。這條確認魔抗那一路仍然完整。
	var enemy := Enemy.new()
	enemy.max_hp = 200.0
	enemy.hp = 200.0
	enemy.base_magic_resist = 0.4
	enemy.reset_derived_stats()

	# 50 × (1 - 0.4) = 30
	var dealt := DamageSystem.apply(enemy, 50.0, DamageSystem.MAGIC)
	assert_float(dealt).is_equal_approx(30.0, 0.001)
