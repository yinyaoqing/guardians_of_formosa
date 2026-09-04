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

	# 交錯添加不同類型實體，驗證它們取 id 的順序
	var slot1 := BuildSlot.new()
	slot1.position = Vector2(100, 100)
	world.add_build_slot(slot1)
	var id1 := slot1.id

	var enemy := Enemy.new()
	world.add_enemy(enemy)
	var id2 := enemy.id

	var slot2 := BuildSlot.new()
	slot2.position = Vector2(200, 200)
	world.add_build_slot(slot2)
	var id3 := slot2.id

	var tower := Tower.new()
	tower.position = Vector2(300, 300)
	world.add_tower(tower)
	var id4 := tower.id

	# 所有實體 id 應連續遞增，表示他們共用同一個計數器
	# 若各型別有獨立計數器，這個測試會失敗
	assert_int(id2).is_equal(id1 + 1).override_failure_message(
		"建塔點與敵人的 id 必須來自同一個計數器，不得重複。per-type 計數器會導致型別間 id 衝突"
	)
	assert_int(id3).is_equal(id2 + 1).override_failure_message(
		"建塔點與敵人的 id 必須來自同一個計數器，不得重複。per-type 計數器會導致型別間 id 衝突"
	)
	assert_int(id4).is_equal(id3 + 1).override_failure_message(
		"建塔點與敵人的 id 必須來自同一個計數器，不得重複。per-type 計數器會導致型別間 id 衝突"
	)

func test_queued_intents_accumulate() -> void:
	var world := WorldState.new()
	world.queue_intent(GameIntent.build(1, &"archer_tower"))
	world.queue_intent(GameIntent.sell(2))
	assert_array(world.pending_intents).has_size(2)
