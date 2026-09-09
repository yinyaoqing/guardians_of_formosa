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

## reset() 走兩段式重生契約：只覆蓋「生命與戰鬥狀態」七個欄位，崗位、
## 身分與數值留給呼叫端（GarrisonSystem._spawn()）負責。這條測試把契約
## 變成可執行的文件——把每一個欄位都污染成明顯的非預設值，呼叫 reset()
## 之後，契約內的欄位要回到出生狀態，契約外的欄位要維持原樣（污染值）
## 不動。若未來有人擴大 reset() 的覆蓋範圍，這條會紅，逼他重新審視這個
## 刻意的分工，而不是默默地把它合併掉。
func test_reset_only_covers_life_and_combat_state_not_identity_post_or_stats() -> void:
	var soldier := Soldier.new()

	# 污染契約內的七個欄位（reset() 應該覆蓋）
	soldier.max_hp = 999.0
	soldier.hp = 1.0
	soldier.alive = false
	soldier.armor = 0.5
	soldier.magic_resist = 0.5
	soldier.cooldown = 3.0
	soldier.engaged_enemy_id = 42

	# 污染契約外的欄位（reset() 刻意不覆蓋，由呼叫端負責）
	soldier.id = 7
	soldier.barracks_id = 8
	soldier.slot_index = 3
	soldier.path_id = &"path_west"
	soldier.post_distance = 123.0
	soldier.position = Vector2(500.0, 600.0)
	soldier.damage = 999.0
	soldier.damage_type = &"magic"
	soldier.attack_interval = 9.0
	soldier.regen_per_second = 9.0

	soldier.reset(100.0, 0.2)

	# reset() 契約內：七個欄位回到出生狀態
	assert_float(soldier.max_hp).override_failure_message(
		"reset() 契約：max_hp 必須由 reset() 寫回出生狀態"
	).is_equal_approx(100.0, 0.001)
	assert_float(soldier.hp).override_failure_message(
		"reset() 契約：hp 必須由 reset() 寫回出生狀態"
	).is_equal_approx(100.0, 0.001)
	assert_bool(soldier.alive).override_failure_message(
		"reset() 契約：alive 必須由 reset() 寫回 true"
	).is_true()
	assert_float(soldier.armor).override_failure_message(
		"reset() 契約：armor 必須由 reset() 寫回傳入值"
	).is_equal_approx(0.2, 0.001)
	assert_float(soldier.magic_resist).override_failure_message(
		"reset() 契約：magic_resist 必須由 reset() 寫回 0.0"
	).is_equal_approx(0.0, 0.001)
	assert_float(soldier.cooldown).override_failure_message(
		"reset() 契約：cooldown 必須由 reset() 寫回 0.0"
	).is_equal_approx(0.0, 0.001)
	assert_int(soldier.engaged_enemy_id).override_failure_message(
		"reset() 契約：engaged_enemy_id 必須由 reset() 寫回 0（未交戰）"
	).is_equal(0)

	# reset() 契約外：崗位、身分、數值不是 reset() 的責任，污染值應維持
	# 不變——這是呼叫端（GarrisonSystem._spawn()）要負責的證據，不是漏測。
	assert_int(soldier.id).override_failure_message(
		"reset() 契約：id 不歸 reset() 管，應由呼叫端負責，不該被 reset() 動到"
	).is_equal(7)
	assert_int(soldier.barracks_id).override_failure_message(
		"reset() 契約：barracks_id 不歸 reset() 管，應由呼叫端負責，不該被 reset() 動到"
	).is_equal(8)
	assert_int(soldier.slot_index).override_failure_message(
		"reset() 契約：slot_index 不歸 reset() 管，應由呼叫端負責，不該被 reset() 動到"
	).is_equal(3)
	assert_str(String(soldier.path_id)).override_failure_message(
		"reset() 契約：path_id 不歸 reset() 管，應由呼叫端負責，不該被 reset() 動到"
	).is_equal("path_west")
	assert_float(soldier.post_distance).override_failure_message(
		"reset() 契約：post_distance 不歸 reset() 管，應由呼叫端負責，不該被 reset() 動到"
	).is_equal_approx(123.0, 0.001)
	assert_vector(soldier.position).override_failure_message(
		"reset() 契約：position 不歸 reset() 管，應由呼叫端負責，不該被 reset() 動到——" +
		"漏了這個會讓重生的小兵用上輩子的位置攔截敵人"
	).is_equal(Vector2(500.0, 600.0))
	assert_float(soldier.damage).override_failure_message(
		"reset() 契約：damage 不歸 reset() 管，應由呼叫端負責，不該被 reset() 動到"
	).is_equal_approx(999.0, 0.001)
	assert_str(String(soldier.damage_type)).override_failure_message(
		"reset() 契約：damage_type 不歸 reset() 管，應由呼叫端負責，不該被 reset() 動到"
	).is_equal("magic")
	assert_float(soldier.attack_interval).override_failure_message(
		"reset() 契約：attack_interval 不歸 reset() 管，應由呼叫端負責，不該被 reset() 動到"
	).is_equal_approx(9.0, 0.001)
	assert_float(soldier.regen_per_second).override_failure_message(
		"reset() 契約：regen_per_second 不歸 reset() 管，應由呼叫端負責，不該被 reset() 動到"
	).is_equal_approx(9.0, 0.001)
