extends GdUnitTestSuite

func test_add_soldier_registers_it_in_both_containers() -> void:
	var world := WorldState.new()
	var soldier := Soldier.new()
	world.add_soldier(soldier)

	assert_int(soldier.id).is_greater(0)
	assert_int(world.soldiers.size()).is_equal(1)
	assert_object(world.soldiers_by_id.get(soldier.id)).is_same(soldier)

## id 空間跨型別共用同一個計數器，這是 blocked_by 能同時指涉小兵而不會與
## 敵人 id 混淆的前提。BuildSystem._upgrade 也已經依賴這個性質來分辨
## 「呼叫端把 slot id 當 tower id 傳進來」。
func test_soldier_ids_do_not_collide_with_enemy_ids() -> void:
	var world := WorldState.new()
	var enemy := Enemy.new()
	var soldier := Soldier.new()
	world.add_enemy(enemy)
	world.add_soldier(soldier)

	assert_int(soldier.id).is_not_equal(enemy.id)

func test_soldier_is_a_combatant() -> void:
	assert_bool(Soldier.new() is Combatant).is_true()
