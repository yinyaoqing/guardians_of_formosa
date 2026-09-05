extends GdUnitTestSuite

## 兩個建塔點，相距足夠遠以免命中半徑重疊
const SLOT_A_POS := Vector2(400, 200)
const SLOT_B_POS := Vector2(900, 480)

func _make_world() -> WorldState:
	var world := WorldState.new()
	for pos: Vector2 in [SLOT_A_POS, SLOT_B_POS]:
		var slot := BuildSlot.new()
		slot.position = pos
		world.add_build_slot(slot)
	return world

func _slot_a(world: WorldState) -> BuildSlot:
	return world.build_slots[0]

func _slot_b(world: WorldState) -> BuildSlot:
	return world.build_slots[1]

func test_clicking_on_a_slot_selects_it() -> void:
	var world := _make_world()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	assert_int(controller.selected_slot_id).is_equal(_slot_a(world).id)

func test_clicking_the_second_slot_selects_that_one() -> void:
	# 用第二個而非第一個，才能抓出「永遠回傳 build_slots[0]」的實作
	var world := _make_world()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_B_POS), world)
	assert_int(controller.selected_slot_id).override_failure_message(
		"必須選中被點到的那一個，不是清單中的第一個"
	).is_equal(_slot_b(world).id)

func test_clicking_just_inside_the_pick_radius_selects() -> void:
	var world := _make_world()
	var controller := InteractionController.new()
	var offset := Vector2(InteractionController.PICK_RADIUS - 1.0, 0.0)
	controller.handle(InputAction.select_at(SLOT_A_POS + offset), world)
	assert_int(controller.selected_slot_id).is_equal(_slot_a(world).id)

func test_clicking_outside_the_pick_radius_deselects() -> void:
	var world := _make_world()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	var offset := Vector2(InteractionController.PICK_RADIUS + 10.0, 0.0)
	controller.handle(InputAction.select_at(SLOT_A_POS + offset), world)
	assert_int(controller.selected_slot_id).override_failure_message(
		"點在所有建塔點的命中半徑之外，應解除選取"
	).is_equal(0)

func test_selecting_the_same_slot_twice_is_idempotent() -> void:
	# 做成切換的話，連點兩下會莫名解除選取，而連點在觸控上很常見
	var world := _make_world()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	assert_int(controller.selected_slot_id).is_equal(_slot_a(world).id)

func test_cancel_clears_the_selection() -> void:
	var world := _make_world()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.simple(InputAction.CANCEL), world)
	assert_int(controller.selected_slot_id).is_equal(0)

func test_nearest_slot_wins_when_two_are_in_range() -> void:
	# 兩個建塔點都落在同一次點擊的命中半徑內，且刻意把「比較遠的」
	# 排在 build_slots 前面：只掃到第一個落在半徑內的點就回傳、
	# 沒有持續比較最小距離的實作，會選到錯的那一個。
	var world := WorldState.new()
	var click_pos := Vector2(400, 200)
	var far_slot := BuildSlot.new()
	far_slot.position = click_pos + Vector2(40.0, 0.0)
	world.add_build_slot(far_slot)
	var near_slot := BuildSlot.new()
	near_slot.position = click_pos + Vector2(10.0, 0.0)
	world.add_build_slot(near_slot)
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(click_pos), world)
	assert_int(controller.selected_slot_id).override_failure_message(
		"半徑內有兩個建塔點時應選較近的那個，不是清單中先掃到的那個"
	).is_equal(near_slot.id)

func test_clicking_exactly_at_the_pick_radius_selects() -> void:
	# 邊界值：實作用 <= 比較平方距離，剛好等於 PICK_RADIUS 的點必須命中。
	# 用 PICK_RADIUS 本身建構偏移量，確保平方距離沒有浮點誤差。
	var world := _make_world()
	var controller := InteractionController.new()
	var offset := Vector2(InteractionController.PICK_RADIUS, 0.0)
	controller.handle(InputAction.select_at(SLOT_A_POS + offset), world)
	assert_int(controller.selected_slot_id).override_failure_message(
		"命中半徑的邊界本身也該算命中，不是只到邊界前一點"
	).is_equal(_slot_a(world).id)

## 兩種可用塔種，才能抓出「永遠用第一種」的實作
func _make_world_with_towers() -> WorldState:
	var world := _make_world()
	world.available_towers = [&"archer_tower", &"cannon_tower"] as Array[StringName]
	return world

func test_choosing_a_tower_on_an_empty_slot_queues_a_build() -> void:
	# 刻意用第二個建塔點與第二種塔，寫死索引 0 的實作會失敗
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_B_POS), world)
	controller.handle(InputAction.choose_tower(2), world)

	assert_array(world.pending_intents).has_size(1)
	var intent: GameIntent = world.pending_intents[0]
	assert_str(intent.kind).is_equal("build")
	assert_int(intent.slot_id).override_failure_message(
		"必須用被選中的建塔點，不是清單中的第一個"
	).is_equal(_slot_b(world).id)
	assert_str(intent.tower_id).override_failure_message(
		"必須用被選中的塔種，不是清單中的第一種"
	).is_equal("cannon_tower")

func test_choosing_a_tower_without_a_selection_does_nothing() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.choose_tower(1), world)
	assert_array(world.pending_intents).has_size(0)

func test_choosing_a_tower_on_an_occupied_slot_does_nothing() -> void:
	var world := _make_world_with_towers()
	_slot_b(world).occupied_by = 12345
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_B_POS), world)
	controller.handle(InputAction.choose_tower(1), world)
	assert_array(world.pending_intents).override_failure_message(
		"已經有塔的建塔點不能再蓋"
	).has_size(0)

func test_choosing_a_tower_index_beyond_the_available_list_does_nothing() -> void:
	# 本關只有兩種塔，按「3」是正常的使用者行為，靜默忽略
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.choose_tower(3), world)
	assert_array(world.pending_intents).has_size(0)

func test_selling_an_occupied_slot_queues_a_sell_for_its_tower() -> void:
	var world := _make_world_with_towers()
	_slot_b(world).occupied_by = 777
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_B_POS), world)
	controller.handle(InputAction.simple(InputAction.SELL), world)

	assert_array(world.pending_intents).has_size(1)
	var intent: GameIntent = world.pending_intents[0]
	assert_str(intent.kind).is_equal("sell")
	assert_int(intent.entity_id).override_failure_message(
		"賣出的對象是建塔點上那座塔的實體 id"
	).is_equal(777)

func test_upgrading_an_occupied_slot_queues_an_upgrade_for_its_tower() -> void:
	var world := _make_world_with_towers()
	_slot_b(world).occupied_by = 777
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_B_POS), world)
	controller.handle(InputAction.simple(InputAction.UPGRADE), world)

	assert_array(world.pending_intents).has_size(1)
	assert_str(world.pending_intents[0].kind).is_equal("upgrade")
	assert_int(world.pending_intents[0].entity_id).is_equal(777)

func test_selling_an_empty_slot_does_nothing() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.simple(InputAction.SELL), world)
	assert_array(world.pending_intents).has_size(0)

func test_selling_without_a_selection_does_nothing() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.simple(InputAction.SELL), world)
	assert_array(world.pending_intents).has_size(0)

func test_clicking_another_slot_switches_the_selection() -> void:
	# 轉移表要求已選取時點另一個建塔點是「改選」，不是忽略也不是取消
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.select_at(SLOT_B_POS), world)
	assert_int(controller.selected_slot_id).is_equal(_slot_b(world).id)

func test_upgrading_without_a_selection_does_nothing() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.simple(InputAction.UPGRADE), world)
	assert_array(world.pending_intents).has_size(0)

func test_building_does_not_change_the_selection() -> void:
	# 建造的 intent 下一 tick 才套用；建塔點自然從空變成有塔，
	# 可用操作也就從建造變成賣出與升級，不需要額外邏輯
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.choose_tower(1), world)
	assert_int(controller.selected_slot_id).is_equal(_slot_a(world).id)

func test_toggle_pause_needs_no_selection() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.simple(InputAction.TOGGLE_PAUSE), world)
	assert_array(world.pending_intents).override_failure_message(
		"暫停與選中什麼無關，未選取時也該發得出去"
	).has_size(1)
	assert_str(world.pending_intents[0].kind).is_equal("toggle_pause")

func test_cycle_speed_needs_no_selection() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.simple(InputAction.CYCLE_SPEED), world)
	assert_array(world.pending_intents).has_size(1)
	assert_str(world.pending_intents[0].kind).is_equal("cycle_speed")

func test_control_actions_do_not_disturb_the_selection() -> void:
	var world := _make_world_with_towers()
	var controller := InteractionController.new()
	controller.handle(InputAction.select_at(SLOT_A_POS), world)
	controller.handle(InputAction.simple(InputAction.TOGGLE_PAUSE), world)
	controller.handle(InputAction.simple(InputAction.CYCLE_SPEED), world)
	assert_int(controller.selected_slot_id).is_equal(_slot_a(world).id)
