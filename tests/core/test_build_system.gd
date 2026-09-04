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

const TOWER_DEF := {
	"id": "archer_tower",
	"damage_type": "physical",
	"levels": [
		{"cost": 70,  "damage": 9.0,  "attack_range": 180.0, "fire_interval": 0.8,  "projectile_speed": 600.0, "splash_radius": 0.0, "on_hit_effects": []},
		{"cost": 130, "damage": 14.0, "attack_range": 190.0, "fire_interval": 0.75, "projectile_speed": 610.0, "splash_radius": 0.0, "on_hit_effects": []},
		{"cost": 220, "damage": 22.0, "attack_range": 200.0, "fire_interval": 0.7,  "projectile_speed": 620.0, "splash_radius": 0.0, "on_hit_effects": []},
	],
}

## 一個已配置好、有一個空建塔點的世界
func _make_world(gold: int) -> WorldState:
	var world := WorldState.new()
	world.tower_defs = {&"archer_tower": TOWER_DEF}
	world.available_towers = [&"archer_tower"] as Array[StringName]
	world.sell_refund_ratio = 0.75
	world.gold = gold
	var slot := BuildSlot.new()
	slot.position = Vector2(400, 200)
	world.add_build_slot(slot)
	return world

func _first_slot(world: WorldState) -> BuildSlot:
	return world.build_slots[0]

func test_building_places_a_tower_at_the_slot_and_spends_gold() -> void:
	var world := _make_world(200)
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	assert_array(world.towers).has_size(1)
	assert_float(world.towers[0].position.x).is_equal_approx(400.0, 0.001)
	assert_int(world.gold).is_equal(130)          # 200 − 70

func test_built_tower_gets_level_one_stats_from_data() -> void:
	var world := _make_world(200)
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	var tower: Tower = world.towers[0]
	assert_int(tower.level).is_equal(1)
	assert_float(tower.damage).is_equal_approx(9.0, 0.001)
	assert_float(tower.attack_range).is_equal_approx(180.0, 0.001)
	assert_float(tower.projectile_speed).override_failure_message(
		"投射物速度必須自資料取得；Tower 的預設值是 0，漏搬運會讓投射物不會動"
	).is_equal_approx(600.0, 0.001)

func test_building_marks_the_slot_occupied() -> void:
	var world := _make_world(200)
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	assert_int(_first_slot(world).occupied_by).is_equal(world.towers[0].id)

func test_building_on_an_occupied_slot_is_rejected() -> void:
	var world := _make_world(200)
	var slot_id := _first_slot(world).id
	BuildSystem.apply(world, GameIntent.build(slot_id, &"archer_tower"))
	BuildSystem.apply(world, GameIntent.build(slot_id, &"archer_tower"))
	assert_array(world.towers).override_failure_message(
		"同一個建塔點不得蓋出第二座塔"
	).has_size(1)
	assert_int(world.gold).override_failure_message(
		"被拒絕的建造不得扣款"
	).is_equal(130)

func test_building_without_enough_gold_is_rejected() -> void:
	var world := _make_world(50)          # 造價 70
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	assert_array(world.towers).has_size(0)
	assert_int(world.gold).is_equal(50)

func test_building_with_exactly_enough_gold_succeeds() -> void:
	# 邊界：剛好等於造價必須成立，否則玩家會覺得錢明明夠卻蓋不了
	var world := _make_world(70)
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	assert_array(world.towers).has_size(1)
	assert_int(world.gold).is_equal(0)

# 以下三個是「資料錯誤」類的拒絕。實作會呼叫 push_error，而 GdUnit4 無法攔截它，
# 所以這裡斷言的是「世界沒有被改動」——錯誤路徑同樣不得建出塔或扣款。
# 少了這幾個測試，一個把 push_error 寫成 push_error 後忘了 return 的實作會通過。

func test_building_on_a_nonexistent_slot_changes_nothing() -> void:
	var world := _make_world(200)
	BuildSystem.apply(world, GameIntent.build(9999, &"archer_tower"))
	assert_array(world.towers).has_size(0)
	assert_int(world.gold).override_failure_message(
		"引用不存在的建塔點是資料錯誤，除了報錯之外不得改動世界"
	).is_equal(200)

func test_building_an_unknown_tower_type_changes_nothing() -> void:
	var world := _make_world(200)
	# 刻意把這個 id 放進 available_towers,使它通過第三道守衛(本關可用清單),
	# 讓真正要測的第二道守衛(tower_defs.has())成為唯一還擋著它的關卡。
	# 若不這麼做,不存在於 tower_defs 的 id 也必然不存在於 available_towers,
	# 第三道守衛會搶先擋下,第二道守衛就完全沒被測到。
	world.available_towers.append(&"no_such_tower")
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"no_such_tower"))
	assert_array(world.towers).has_size(0)
	assert_int(world.gold).is_equal(200)

func test_building_a_tower_not_available_in_this_level_changes_nothing() -> void:
	# 塔種存在於資料中，但本關的 available_towers 沒有它
	var world := _make_world(200)
	world.tower_defs[&"cannon_tower"] = TOWER_DEF
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"cannon_tower"))
	assert_array(world.towers).override_failure_message(
		"本關不可用的塔種不得蓋出來，即使它存在於資料中"
	).has_size(0)
	assert_int(world.gold).is_equal(200)
	assert_int(_first_slot(world).occupied_by).is_equal(0)

## 蓋一座塔並回傳它，方便升級與賣出的測試取用
func _build_one(world: WorldState) -> Tower:
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	return world.towers[0]

func test_upgrading_raises_level_and_stats_and_spends_gold() -> void:
	var world := _make_world(300)
	var tower := _build_one(world)             # 花 70，剩 230
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))
	assert_int(tower.level).is_equal(2)
	assert_float(tower.damage).is_equal_approx(14.0, 0.001)
	assert_float(tower.projectile_speed).override_failure_message(
		"升級必須重新套用該等級的全部數值，不能只改傷害"
	).is_equal_approx(610.0, 0.001)
	assert_int(world.gold).is_equal(100)       # 230 − 130

func test_upgrading_at_max_level_is_rejected() -> void:
	var world := _make_world(1000)
	var tower := _build_one(world)
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))   # 到第 3 級
	var gold_at_max := world.gold
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))   # 應被拒絕
	assert_int(tower.level).override_failure_message(
		"塔只有三級，不得升到第四級"
	).is_equal(3)
	assert_int(world.gold).override_failure_message(
		"被拒絕的升級不得扣款"
	).is_equal(gold_at_max)

func test_upgrading_without_enough_gold_is_rejected() -> void:
	var world := _make_world(100)              # 蓋完剩 30，升級要 130
	var tower := _build_one(world)
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))
	assert_int(tower.level).is_equal(1)
	assert_int(world.gold).is_equal(30)

func test_upgrading_a_tower_that_no_longer_exists_is_rejected() -> void:
	# 塔可能在指令排隊期間被賣掉，這是正常競態而非錯誤
	var world := _make_world(300)
	BuildSystem.apply(world, GameIntent.upgrade(9999))
	assert_int(world.gold).is_equal(300)

func test_selling_a_level_one_tower_refunds_a_fraction_of_its_cost() -> void:
	var world := _make_world(200)
	var tower := _build_one(world)             # 花 70，剩 130
	BuildSystem.apply(world, GameIntent.sell(tower.id))
	assert_int(world.gold).is_equal(182)       # 130 + floor(70 × 0.75) = 130 + 52

func test_selling_refunds_every_level_invested_not_just_the_first() -> void:
	# 這個測試必須用等級大於 1 的塔。用一級塔的話，
	# 「退款 = 比例 × 全部投入」與「退款 = 比例 × 一級造價」結果相同，
	# 錯誤的實作會照樣通過。
	var world := _make_world(500)
	var tower := _build_one(world)                            # 花 70
	BuildSystem.apply(world, GameIntent.upgrade(tower.id))    # 花 130
	var gold_before := world.gold                             # 500 − 200 = 300
	BuildSystem.apply(world, GameIntent.sell(tower.id))
	# 已投入 70 + 130 = 200，退款 floor(200 × 0.75) = 150
	assert_int(world.gold).override_failure_message(
		"退款必須涵蓋所有已投入的等級造價，不能只算建造費"
	).is_equal(gold_before + 150)

func test_selling_removes_the_tower_and_frees_its_slot() -> void:
	var world := _make_world(200)
	var tower := _build_one(world)
	BuildSystem.apply(world, GameIntent.sell(tower.id))
	assert_array(world.towers).has_size(0)
	assert_int(_first_slot(world).occupied_by).override_failure_message(
		"賣出後建塔點必須回到空著的狀態，否則該位置永遠不能再蓋"
	).is_equal(0)

func test_a_freed_slot_can_be_built_on_again() -> void:
	var world := _make_world(300)
	var tower := _build_one(world)
	BuildSystem.apply(world, GameIntent.sell(tower.id))
	BuildSystem.apply(world, GameIntent.build(_first_slot(world).id, &"archer_tower"))
	assert_array(world.towers).has_size(1)

func test_selling_a_tower_that_no_longer_exists_is_rejected() -> void:
	var world := _make_world(200)
	BuildSystem.apply(world, GameIntent.sell(9999))
	assert_int(world.gold).override_failure_message(
		"賣一座不存在的塔不得憑空產生金幣"
	).is_equal(200)

# 以下兩個測試涵蓋一種資料錯誤：呼叫端把「建塔點 id」誤傳成 sell / upgrade
# 要的「塔的實體 id」。因為所有實體共用同一個全域 id 計數器（不分塔、敵人、
# 建塔點、投射物），_find_tower 光看「找不到」無法分辨這是正常競態（塔剛被
# 賣掉）還是呼叫端傳錯了型別；但因為 id 空間是共用的，可以額外檢查這個 id
# 是否剛好對得上一個建塔點，對得上就代表是後者，屬於資料錯誤，必須噴出來。

func test_upgrading_with_a_slot_id_instead_of_a_tower_id_changes_nothing() -> void:
	var world := _make_world(300)
	var slot_id := _first_slot(world).id
	BuildSystem.apply(world, GameIntent.upgrade(slot_id))
	assert_array(world.towers).has_size(0)
	assert_int(world.gold).override_failure_message(
		"把建塔點 id 當成塔 id 傳給 upgrade 是資料錯誤，不得改動世界"
	).is_equal(300)

func test_selling_with_a_slot_id_instead_of_a_tower_id_changes_nothing() -> void:
	var world := _make_world(200)
	var slot_id := _first_slot(world).id
	BuildSystem.apply(world, GameIntent.sell(slot_id))
	assert_array(world.towers).has_size(0)
	assert_int(world.gold).override_failure_message(
		"把建塔點 id 當成塔 id 傳給 sell 是資料錯誤，不得憑空產生金幣"
	).is_equal(200)
