extends GdUnitTestSuite

## 建塔選單顯示什麼，是一批真正的決策——買不買得起、有沒有下一級、退款多少。
## 寫在 Control 裡就沒有任何測試守得到，所以抽成純函式在這裡釘住。

const SLOT_POS := Vector2(400, 200)

func _make_world() -> WorldState:
	var world := WorldState.new()
	world.tower_defs = {
		&"musket_tower": {
			"id": "musket_tower",
			"name_key": "tower.musket_tower.name",
			"damage_type": "physical",
			"icon": "res://game/assets/chapter01/icon_tower_musket.png",
			"levels": [
				{"cost": 70,  "damage": 18.0, "attack_range": 200.0, "fire_interval": 1.2,
				 "projectile_speed": 700.0, "splash_radius": 0.0, "on_hit_effects": [],
				 "sprite": "res://game/assets/chapter01/tower_musket_t1.png"},
				{"cost": 130, "damage": 30.0, "attack_range": 210.0, "fire_interval": 1.1,
				 "projectile_speed": 700.0, "splash_radius": 0.0, "on_hit_effects": [],
				 "sprite": "res://game/assets/chapter01/tower_musket_t2.png"},
			],
		},
		&"hunter_tower": {
			"id": "hunter_tower",
			"name_key": "tower.hunter_tower.name",
			"damage_type": "physical",
			"icon": "res://game/assets/chapter01/icon_tower_hunter.png",
			"levels": [
				{"cost": 50, "damage": 7.0, "attack_range": 130.0, "fire_interval": 0.9,
				 "projectile_speed": 620.0, "splash_radius": 0.0, "on_hit_effects": ["chill"],
				 "sprite": "res://game/assets/chapter01/tower_hunter_t1.png"},
			],
		},
	}
	world.available_towers = [&"musket_tower", &"hunter_tower"] as Array[StringName]
	# 刻意不用 0.75——那是 level_01 出貨用的值，用它的話把任一份 _refund_for
	# 的 ratio 參數寫死成 0.75 仍然會綠燈。見 test_the_refund_matches_what_selling_actually_pays。
	world.sell_refund_ratio = 0.65
	world.gold = 200
	var slot := BuildSlot.new()
	slot.position = SLOT_POS
	world.add_build_slot(slot)
	return world

func _slot(world: WorldState) -> BuildSlot:
	return world.build_slots[0]

## 在建塔點上放一座指定塔種與等級的塔
func _place_tower(world: WorldState, tower_id: StringName, level: int) -> Tower:
	var tower := Tower.new()
	tower.tower_id = tower_id
	tower.level = level
	tower.position = SLOT_POS
	world.add_tower(tower)
	_slot(world).occupied_by = tower.id
	return tower

func test_no_selection_returns_nothing() -> void:
	var world := _make_world()
	assert_array(BuildMenuOptions.for_slot(world, 0)).has_size(0)

func test_unknown_slot_returns_nothing() -> void:
	var world := _make_world()
	assert_array(BuildMenuOptions.for_slot(world, 99999)).override_failure_message(
		"找不到的建塔點不該讓選單畫出東西，也不該當掉"
	).has_size(0)

func test_an_empty_slot_lists_every_available_tower() -> void:
	var world := _make_world()
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_array(options).has_size(2)
	for option: Dictionary in options:
		assert_str(option["kind"]).is_equal("build")

func test_build_options_carry_the_second_tower_correctly() -> void:
	# 刻意檢查第二筆：寫死 available_towers[0] 的實作會被這條抓到
	var world := _make_world()
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	var second: Dictionary = options[1]
	assert_str(second["tower_id"]).override_failure_message(
		"第二筆必須是 available_towers 的第二種，不是第一種"
	).is_equal("hunter_tower")
	assert_int(second["cost"]).override_failure_message(
		"造價必須取該塔一級的 cost"
	).is_equal(50)
	assert_str(second["icon"]).contains("icon_tower_hunter")
	assert_str(second["name_key"]).is_equal("tower.hunter_tower.name")

func test_build_options_carry_the_one_based_choice_index() -> void:
	# 選單按下去要翻成 InputAction.choose_tower(n)，n 自 1 起算。
	# 把這個對應放在這裡而不是 Control 裡，才有測試守得到。
	var world := _make_world()
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_int(options[0]["choice_index"]).is_equal(1)
	assert_int(options[1]["choice_index"]).override_failure_message(
		"第二種塔的 choice_index 必須是 2"
	).is_equal(2)

func test_unaffordable_towers_are_still_listed_but_marked() -> void:
	# 買不起要列出來玩家才知道有這個選項；擋不擋是 BuildSystem 的事，不是選單的。
	var world := _make_world()
	world.gold = 60
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_array(options).override_failure_message(
		"買不起不代表不顯示"
	).has_size(2)
	assert_bool(options[0]["affordable"]).override_failure_message(
		"銃樓 70 而金幣 60，應標為買不起"
	).is_false()
	assert_bool(options[1]["affordable"]).override_failure_message(
		"獵寮 50 而金幣 60，應標為買得起"
	).is_true()

func test_a_cost_exactly_equal_to_gold_is_affordable() -> void:
	# 60 對 70/50 兩種塔而言，`>=` 與 `>` 給的答案完全一樣，drift 成 `>`
	# 不會被 test_unaffordable_towers_are_still_listed_but_marked 抓到。
	# 這裡釘住剛好打平的邊界：第一輪真實會走到的狀態是 200 起始 → 蓋銃樓花 70
	# → 剩 130 → 二階升級剛好要 130，玩家點得下去，選單卻可能把它畫暗。
	var world := _make_world()
	world.gold = 130
	_place_tower(world, &"musket_tower", 1)
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_bool(options[0]["affordable"]).override_failure_message(
		"升級費 130 剛好等於金幣 130，應標為買得起"
	).is_true()

func test_a_build_cost_exactly_equal_to_gold_is_affordable() -> void:
	# 建造與升級各有一份 `world.gold >= cost`，相隔十幾行。上面那條只釘住升級那份，
	# 建造那份單方面 drift 成 `>` 仍然全綠——而這個狀態也走得到：二階升級花掉 130
	# 之後剛好剩 70，正好是銃樓的造價。
	var world := _make_world()
	world.gold = 70
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_int(options[0]["cost"]).override_failure_message(
		"這條測試假定第一種塔的造價是 70，資料改了要跟著改"
	).is_equal(70)
	assert_bool(options[0]["affordable"]).override_failure_message(
		"造價 70 剛好等於金幣 70，應標為買得起"
	).is_true()

func test_an_occupied_slot_offers_upgrade_and_sell() -> void:
	var world := _make_world()
	_place_tower(world, &"musket_tower", 1)
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_array(options).has_size(2)
	assert_str(options[0]["kind"]).is_equal("upgrade")
	assert_str(options[1]["kind"]).is_equal("sell")
	assert_int(options[0]["cost"]).override_failure_message(
		"升級費必須是下一級的 cost"
	).is_equal(130)

func test_a_maxed_tower_offers_no_upgrade() -> void:
	# 升到最高階：選單不該再顯示升級瓣
	var world := _make_world()
	_place_tower(world, &"musket_tower", 2)   # musket 在測試資料裡只有兩階
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_array(options).has_size(1)
	assert_str(options[0]["kind"]).override_failure_message(
		"已達最高階時只剩賣出"
	).is_equal("sell")

func test_a_single_tier_tower_offers_no_upgrade() -> void:
	# 另一條路徑：這種塔本來就只有一階。與升滿是不同的成因，兩者都要釘。
	var world := _make_world()
	_place_tower(world, &"hunter_tower", 1)
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_array(options).has_size(1)
	assert_str(options[0]["kind"]).is_equal("sell")

func test_an_unaffordable_upgrade_is_still_listed_but_marked() -> void:
	var world := _make_world()
	world.gold = 100
	_place_tower(world, &"musket_tower", 1)
	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	assert_bool(options[0]["affordable"]).override_failure_message(
		"升級要 130 而金幣 100，應標為買不起但仍列出"
	).is_false()

func test_the_refund_matches_what_selling_actually_pays() -> void:
	# 這一輪價值最高的測試。退款的算法在 BuildSystem 與選單各有一份
	# （ui/ 的分層守衛不允許選單認識 BuildSystem），兩者漂移時
	# 玩家會看到「賣出 +52」而實際只回 45——除非有一條測試同時看兩邊。
	#
	# 兩階都要測：level 2 的投入總額 200 × 0.65 = 130.0 剛好整除，floori、
	# roundi、ceili 三個都回 130，看不出取捨的差別。level 1 的 70 × 0.65 = 45.5
	# 才會讓 floor 與 round 分道揚鑣——只測 level 2 的話，_refund_for 把 floori
	# 換成 roundi 這種「看起來像修 bug」的整理，測試會渾然不覺。
	_assert_refund_matches_actual_payout(&"musket_tower", 1)
	_assert_refund_matches_actual_payout(&"musket_tower", 2)

## 建一座指定等級的塔、讀選單顯示的退款、實際賣掉、比較兩者。
## sell 選項一定是陣列最後一筆（未滿級時前面還有一筆 upgrade，見 for_slot）。
func _assert_refund_matches_actual_payout(tower_id: StringName, level: int) -> void:
	var world := _make_world()
	var tower := _place_tower(world, tower_id, level)

	var options := BuildMenuOptions.for_slot(world, _slot(world).id)
	var sell_option: Dictionary = options[options.size() - 1]
	assert_str(sell_option["kind"]).override_failure_message(
		"選項陣列最後一筆應該是 sell，測試假設不成立"
	).is_equal("sell")
	var shown_refund: int = sell_option["refund"]

	var gold_before := world.gold
	BuildSystem.apply(world, GameIntent.sell(tower.id))
	var actually_paid := world.gold - gold_before

	assert_int(shown_refund).override_failure_message(
		"level %d：選單顯示的退款 %d 與實際退的 %d 不一致" % [level, shown_refund, actually_paid]
	).is_equal(actually_paid)
	assert_int(actually_paid).override_failure_message(
		"退款不該是 0，否則這條測試在比較兩個零"
	).is_greater(0)
