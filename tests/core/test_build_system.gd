extends GdUnitTestSuite

func test_build_intent_carries_slot_and_tower() -> void:
	var intent := GameIntent.build(7, &"archer_tower")
	assert_str(intent.kind).is_equal("build")
	assert_int(intent.slot_id).is_equal(7)
	assert_str(intent.tower_id).is_equal("archer_tower")

func test_sell_intent_carries_entity_id() -> void:
	var intent := GameIntent.sell(42)
	assert_str(intent.kind).is_equal("sell")
	assert_int(intent.entity_id).is_equal(42)

func test_upgrade_intent_carries_entity_id() -> void:
	var intent := GameIntent.upgrade(42)
	assert_str(intent.kind).is_equal("upgrade")
	assert_int(intent.entity_id).is_equal(42)

func test_added_build_slot_gets_an_entity_id_and_is_indexed() -> void:
	var world := WorldState.new()
	var slot := BuildSlot.new()
	slot.position = Vector2(400, 200)
	world.add_build_slot(slot)
	assert_int(slot.id).is_greater(0)
	assert_array(world.build_slots).has_size(1)
	assert_bool(world.build_slots_by_id.has(slot.id)).is_true()

func test_build_slots_share_the_entity_id_space_with_other_entities() -> void:
	# id 跨型別不重複，是「實體 id 永不衝突」這條性質的一部分
	var world := WorldState.new()
	var slot := BuildSlot.new()
	world.add_build_slot(slot)
	var enemy := Enemy.new()
	world.add_enemy(enemy)
	assert_bool(slot.id != enemy.id).override_failure_message(
		"建塔點與敵人的 id 必須來自同一個計數器，不得重複"
	).is_true()

func test_queued_intents_accumulate() -> void:
	var world := WorldState.new()
	world.queue_intent(GameIntent.build(1, &"archer_tower"))
	world.queue_intent(GameIntent.sell(2))
	assert_array(world.pending_intents).has_size(2)
