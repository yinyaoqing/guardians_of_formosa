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
