extends GdUnitTestSuite

## 釘住 BattleSim._tick() 的步驟順序。
## 這些不變式沒有測試守著的話，任何一次重排都會靜默地改變遊戲行為。
##
## 本分支新增的兩條順序不變式不在這裡釘：MeleeSystem 必須排在 MovementSystem
## 之前，釘在 test_melee_system.gd 的 test_a_blocked_enemy_does_not_advance_on_the_tick_it_is_blocked；
## GarrisonSystem 必須排在 MeleeSystem 之前，釘在 test_garrison_lifecycle.gd 的
## test_a_blocked_enemy_resumes_when_its_soldier_dies（第一次 advance 之後
## blocked_by 就非 0，代表補兵與交戰在同一個 tick 內依序發生）。

const FRAME := 1.0 / 30.0
const PATH_ID := &"main"

func _make_world() -> WorldState:
	var world := WorldState.new()
	var points := PackedVector2Array([
		Vector2(0, 0), Vector2(200, 0), Vector2(400, 0), Vector2(600, 0),
	])
	world.paths[PATH_ID] = PathData.new(points, 200.0)
	world.gold = 0
	world.civilians_remaining = 20
	return world

func _add_enemy(world: WorldState, speed: float) -> Enemy:
	var enemy := Enemy.new()
	enemy.enemy_id = &"orc_grunt"
	enemy.hp = 1000.0
	enemy.max_hp = 1000.0
	enemy.base_speed = speed
	enemy.bounty = 7
	enemy.path_id = PATH_ID
	enemy.reset_derived_stats()
	world.add_enemy(enemy)
	return enemy

func test_status_applied_this_tick_affects_movement_this_tick() -> void:
	# 證明 StatusSystem 排在 MovementSystem 之前。
	# 若順序相反，減速要到下一 tick 才生效，敵人這一 tick 會走滿速。
	var world := _make_world()
	var enemy := _add_enemy(world, 300.0)
	var sim := BattleSim.new(world)
	world.status_system.apply(enemy, {"id": "chill", "kind": "slow", "magnitude": 0.5, "duration": 5.0}, &"frost_tower")

	sim.advance(FRAME)

	var expected := 300.0 * 0.5 * BattleSim.TICK_DELTA
	assert_float(enemy.distance_along).override_failure_message(
		"這一 tick 施加的減速必須在同一 tick 就生效，代表 StatusSystem 排在 MovementSystem 之前"
	).is_equal_approx(expected, 0.001)

func test_killed_enemy_awards_bounty_exactly_once() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 0.0)
	enemy.hp = 1.0
	var sim := BattleSim.new(world)
	DamageSystem.apply(enemy, 999.0, DamageSystem.PHYSICAL)

	sim.advance(FRAME)
	sim.advance(FRAME)
	sim.advance(FRAME)

	assert_int(world.gold).override_failure_message(
		"被擊殺的敵人只能發一次賞金"
	).is_equal(7)

func test_leaked_enemy_awards_no_bounty() -> void:
	var world := _make_world()
	_add_enemy(world, 100000.0)      # 一 tick 就衝到終點
	var sim := BattleSim.new(world)

	sim.advance(FRAME)
	sim.advance(FRAME)

	assert_int(world.gold).override_failure_message(
		"走到終點的敵人不該給玩家賞金"
	).is_equal(0)
	assert_int(world.civilians_remaining).is_equal(19)

func test_effects_on_a_killed_enemy_are_returned_to_the_pool() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 0.0)
	var sim := BattleSim.new(world)

	# Apply a status effect that won't expire during test
	world.status_system.apply(enemy, {"id": "chill", "kind": "slow", "magnitude": 0.5, "duration": 100.0}, &"frost_tower")

	# Record pool state after applying (i.e., the "borrowed" state)
	var free_count_borrowed := world.effect_pool.free_count()

	# Kill the enemy
	DamageSystem.apply(enemy, 1001.0, DamageSystem.PHYSICAL)

	# Advance one tick to trigger _remove_dead
	sim.advance(FRAME)

	# Verify the effect was released to the pool
	assert_array(enemy.active_effects).override_failure_message(
		"死亡敵人的效果清單必須被清空"
	).has_size(0)
	assert_int(world.effect_pool.free_count()).override_failure_message(
		"死亡敵人身上的效果必須歸還池中，否則長戰役中池會逐漸耗盡"
	).is_equal(free_count_borrowed + 1)

func test_projectile_spawned_this_tick_does_not_move_this_tick() -> void:
	# 證明 ProjectileSystem 排在 _tick_towers 之前。
	# 若順序相反，投射物會在生成的同一 tick 就移動一格，每一發的飛行時間都少一 tick。
	var world := _make_world()
	_add_enemy(world, 0.0)                 # 停在路徑起點 (0, 0)

	var tower := Tower.new()
	tower.tower_id = &"archer_tower"
	tower.position = Vector2(100, 0)
	tower.damage = 1.0
	tower.damage_type = DamageSystem.PHYSICAL
	tower.attack_range = 1000.0
	tower.fire_interval = 10.0             # 只讓它開一發
	tower.projectile_speed = 600.0
	world.add_tower(tower)

	var sim := BattleSim.new(world)
	sim.advance(FRAME)

	assert_array(world.projectiles).has_size(1)
	assert_float(world.projectiles[0].position.x).override_failure_message(
		"這一 tick 生成的投射物不得在同一 tick 移動，代表 ProjectileSystem 排在 _tick_towers 之前"
	).is_equal_approx(100.0, 0.001)

## 一個配置好、有一個空建塔點與一隻停住的敵人的世界
func _make_buildable_world() -> WorldState:
	var world := _make_world()
	world.tower_defs = {
		&"archer_tower": {
			"id": "archer_tower",
			"damage_type": "physical",
			"levels": [
				{"cost": 70, "damage": 9.0, "attack_range": 500.0, "fire_interval": 0.8,
				 "projectile_speed": 600.0, "splash_radius": 0.0, "on_hit_effects": []},
				{"cost": 130, "damage": 14.0, "attack_range": 510.0, "fire_interval": 0.75,
				 "projectile_speed": 610.0, "splash_radius": 0.0, "on_hit_effects": []},
			],
		}
	}
	world.available_towers = [&"archer_tower"] as Array[StringName]
	world.gold = 200
	var slot := BuildSlot.new()
	slot.position = Vector2(100, 0)
	world.add_build_slot(slot)
	return world

func test_intent_queued_before_a_tick_is_applied_in_that_tick() -> void:
	var world := _make_buildable_world()
	var sim := BattleSim.new(world)
	world.queue_intent(GameIntent.build(world.build_slots[0].id, &"archer_tower"))

	sim.advance(FRAME)

	assert_array(world.towers).override_failure_message(
		"排隊的意圖必須在下一個 tick 就被套用"
	).has_size(1)
	assert_array(world.pending_intents).override_failure_message(
		"套用後佇列必須清空，否則同一筆指令會被重複執行"
	).has_size(0)

func test_a_tower_built_this_tick_can_fire_this_tick() -> void:
	# 證明意圖套用排在 tick 的第一步。若挪到 tick 尾端，
	# 這一 tick 蓋的塔要等下一 tick 才會鎖定目標，冷卻也不會啟動。
	var world := _make_buildable_world()
	_add_enemy(world, 0.0)                 # 停在路徑起點 (0, 0)，在射程 500 內
	var sim := BattleSim.new(world)
	world.queue_intent(GameIntent.build(world.build_slots[0].id, &"archer_tower"))

	sim.advance(FRAME)

	var tower: Tower = world.towers[0]
	assert_int(tower.target_id).override_failure_message(
		"這一 tick 蓋好的塔，這一 tick 就該鎖定得到目標——代表意圖套用排在 tick 第一步"
	).is_greater(0)
	assert_float(tower.cooldown).override_failure_message(
		"這一 tick 蓋好的塔，這一 tick 就該開得了火"
	).is_greater(0.0)

## 以下兩個測試釘住 sell 與 upgrade 兩種 intent 真的會走到 BattleSim.advance()。
## 先前只有 build 被排進 tick 迴圈測試過；一個只把 build 接到 BuildSystem、
## 把 sell 與 upgrade 漏接的實作會讓全套件照樣通過，直到這兩個測試出現。

func test_sell_intent_queued_through_the_tick_removes_the_tower() -> void:
	var world := _make_buildable_world()
	var sim := BattleSim.new(world)
	var slot_id := world.build_slots[0].id
	world.queue_intent(GameIntent.build(slot_id, &"archer_tower"))
	sim.advance(FRAME)
	var tower: Tower = world.towers[0]

	world.queue_intent(GameIntent.sell(tower.id))
	sim.advance(FRAME)

	assert_array(world.towers).override_failure_message(
		"sell intent 必須經由 tick 排空並套用到 BuildSystem，塔才會消失"
	).has_size(0)
	assert_int(world.build_slots[0].occupied_by).override_failure_message(
		"賣出後建塔點必須經由 tick 釋放，才能再次建造"
	).is_equal(0)

func test_upgrade_intent_queued_through_the_tick_raises_the_level() -> void:
	var world := _make_buildable_world()
	var sim := BattleSim.new(world)
	var slot_id := world.build_slots[0].id
	world.queue_intent(GameIntent.build(slot_id, &"archer_tower"))
	sim.advance(FRAME)
	var tower: Tower = world.towers[0]

	world.queue_intent(GameIntent.upgrade(tower.id))
	sim.advance(FRAME)

	assert_int(tower.level).override_failure_message(
		"upgrade intent 必須經由 tick 排空並套用到 BuildSystem，等級才會提升"
	).is_equal(2)

## 釘住整條佇列在單一 tick 內一次排空，且依排隊順序逐一套用。
## 兩座塔分蓋在不同建塔點，彼此之間沒有前向引用問題（第二筆不需要第一筆才知道的 id），
## 讓金幣特意只夠蓋一座：若佇列真的照順序套用，先排的那筆會成功、後排的那筆會因錢不夠被拒絕；
## 若實作只套用佇列的最後一筆、或把佇列打散成多個 tick 分批套用，這個測試會失敗。
func test_multiple_intents_queued_in_one_frame_all_apply_in_order() -> void:
	var world := _make_buildable_world()
	world.gold = 100                        # 只夠蓋一座（造價 70），兩座蓋不起
	var slot1_id := world.build_slots[0].id
	var slot2 := BuildSlot.new()
	slot2.position = Vector2(200, 0)
	world.add_build_slot(slot2)
	var sim := BattleSim.new(world)

	world.queue_intent(GameIntent.build(slot1_id, &"archer_tower"))
	world.queue_intent(GameIntent.build(slot2.id, &"archer_tower"))
	sim.advance(FRAME)

	assert_array(world.pending_intents).override_failure_message(
		"單一 advance() 之後佇列必須完全排空，代表整條佇列在同一個 tick 內套用完畢"
	).has_size(0)
	assert_array(world.towers).has_size(1)
	assert_int(world.build_slots[0].occupied_by).override_failure_message(
		"先排隊的 build intent 必須先套用，第一個建塔點應該蓋出塔"
	).is_greater(0)
	assert_int(world.build_slots[1].occupied_by).override_failure_message(
		"金幣只夠蓋一座，後排隊的 build intent 必須被拒絕，第二個建塔點應維持空著"
	).is_equal(0)
	assert_int(world.gold).is_equal(30)     # 100 − 70

## 暫停時 advance() 提早回傳、_tick() 從未執行，但佇列不該因此無止盡累積——
## 玩家在暫停下規劃建塔、賣塔是預期中的操作。這裡釘住暫停時佇列仍會被排空。
func test_intent_queued_while_paused_is_still_applied_and_the_queue_drains() -> void:
	var world := _make_buildable_world()
	var sim := BattleSim.new(world)
	sim.paused = true
	var slot_id := world.build_slots[0].id

	world.queue_intent(GameIntent.build(slot_id, &"archer_tower"))
	var ticks := sim.advance(FRAME)

	assert_int(ticks).override_failure_message(
		"暫停時不該真的跑 tick，其餘模擬步驟仍要維持完全不動"
	).is_equal(0)
	assert_array(world.towers).override_failure_message(
		"暫停時排隊的建造意圖仍必須被套用——暫停下規劃建塔是預期中的操作"
	).has_size(1)
	assert_array(world.pending_intents).override_failure_message(
		"套用後佇列必須清空，否則會在暫停時無止盡累積，恢復時一次性爆發套用"
	).has_size(0)

func test_toggle_pause_intent_flips_the_paused_flag() -> void:
	var world := _make_world()
	var sim := BattleSim.new(world)
	assert_bool(sim.paused).is_false()

	world.queue_intent(GameIntent.toggle_pause())
	sim.advance(FRAME)
	assert_bool(sim.paused).is_true()

	world.queue_intent(GameIntent.toggle_pause())
	sim.advance(FRAME)
	assert_bool(sim.paused).is_false()

func test_cycle_speed_intent_wraps_back_to_one() -> void:
	# 必須驗到循環回頭。只測 1x → 2x 的話，「每次乘二」的實作也會通過。
	var world := _make_world()
	var sim := BattleSim.new(world)
	assert_float(sim.speed_multiplier).is_equal_approx(1.0, 0.001)

	world.queue_intent(GameIntent.cycle_speed())
	sim.advance(FRAME)
	assert_float(sim.speed_multiplier).is_equal_approx(2.0, 0.001)

	world.queue_intent(GameIntent.cycle_speed())
	sim.advance(FRAME)
	assert_float(sim.speed_multiplier).is_equal_approx(4.0, 0.001)

	world.queue_intent(GameIntent.cycle_speed())
	sim.advance(FRAME)
	assert_float(sim.speed_multiplier).override_failure_message(
		"倍速必須循環回 1x，不是無限倍增"
	).is_equal_approx(1.0, 0.001)

func test_build_intents_still_reach_the_build_system_after_routing() -> void:
	# 路由重構最可能的失敗是靜默漏掉某個 kind。這條守著建造那一路。
	#
	# 與 test_intent_queued_before_a_tick_is_applied_in_that_tick 涵蓋範圍重疊，
	# 這是刻意的：那一條的名字講的是「時機」，讀到它的人不會想到路由；
	# 這一條的名字說明了 kind 分派本身是不變式，重構的人才會知道自己動到了什麼。
	var world := _make_buildable_world()
	var sim := BattleSim.new(world)
	world.queue_intent(GameIntent.build(world.build_slots[0].id, &"archer_tower"))

	sim.advance(FRAME)

	assert_array(world.towers).override_failure_message(
		"改成路由器之後，建造類 intent 仍必須到得了 BuildSystem"
	).has_size(1)

## 補跑迴圈（catch-up loop）不會重讀 paused 的話，卡頓後一次補跑多個 tick 時，
## 排在第一個 tick 的 toggle_pause 意圖只會讓「下一次」advance() 暫停，
## 這一次呼叫仍會把積欠的 tick 全部跑完——移動、開火、扣血都照跑，
## 暫停因此晚了最多 MAX_TICKS_PER_FRAME - 1 個 tick 才真正生效。
## 這裡讓一次 advance() 欠下 5 個 tick，證明實際只跑了 1 個（drain 出 toggle_pause 的那個）。
func test_pause_drained_mid_catchup_stops_the_loop_immediately() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 300.0)
	var sim := BattleSim.new(world)
	world.queue_intent(GameIntent.toggle_pause())

	var ticks := sim.advance(FRAME * 5.0)   # 一次欠 5 個 tick

	assert_int(ticks).override_failure_message(
		"迴圈條件必須重讀 paused：欠 5 個 tick 時，第一個 tick 排空的 toggle_pause 必須讓其餘 4 個 tick 完全不跑"
	).is_equal(1)
	assert_bool(sim.paused).override_failure_message(
		"toggle_pause 意圖必須在它被排空的那個 tick 就生效"
	).is_true()
	var expected_distance := 300.0 * BattleSim.TICK_DELTA
	assert_float(enemy.distance_along).override_failure_message(
		"敵人只能走完整 1 個 tick 的距離；若還跑出剩下 4 個 tick 的位移，代表暫停沒有立刻打斷補跑迴圈"
	).is_equal_approx(expected_distance, 0.001)

	# 上面只釘住了「暫停當下沒多跑」，沒釘住「欠的那 4 個 tick 有沒有留著」。
	# _accumulator 若在暫停跳出時被清成 0（而不是保留剩下欠的量），這裡的
	# 斷言全部會通過、上面五個斷言也全部通過，卻悄悄丟掉了最多
	# MAX_TICKS_PER_FRAME - 1 個 tick（本例是 4 個、133ms）的戰鬥時間。
	# 解除暫停後只推進極小的 delta（1 毫秒），若欠的 4 個 tick 還在，
	# 這一次 advance() 應該補跑出那 4 個 tick；若欠款已經被清空，
	# 這裡只會再跑出 0 個 tick。
	sim.paused = false
	var resumed_ticks := sim.advance(0.001)

	assert_int(resumed_ticks).override_failure_message(
		"解除暫停後必須補跑暫停時欠下的 4 個 tick（_accumulator 保留了 4/30 秒，" +
		"加上這次極小的 0.001 秒 delta 仍不足以湊出第 5 個 tick）。" +
		"若這裡跑出的 tick 數不是 4，代表 _accumulator 在暫停跳出的那一刻被清空或改動了，" +
		"暫停期間積欠的模擬時間就這樣憑空消失，戰鬥時間軸會對不上。"
	).is_equal(4)

func test_a_leaked_enemy_costs_one_civilian() -> void:
	var world := _make_world()
	world.civilians_remaining = 3
	var enemy := _add_enemy(world, 100000.0)   # 一 tick 就走完整條路
	var sim := BattleSim.new(world)

	sim.advance(FRAME)

	assert_bool(enemy.leaked).is_true()
	assert_int(world.civilians_remaining).override_failure_message(
		"漏過去一隻敵人，就少救一個平民"
	).is_equal(2)

func test_civilians_never_go_below_zero() -> void:
	# 歸零不是失敗，只是一個都沒救到。玩家會繼續打完剩下的波次，
	# 期間漏掉的敵人不該讓計數變成負數——結算畫面會印出負的人數。
	var world := _make_world()
	world.civilians_remaining = 1
	_add_enemy(world, 100000.0)
	_add_enemy(world, 100000.0)
	_add_enemy(world, 100000.0)
	var sim := BattleSim.new(world)

	sim.advance(FRAME)

	assert_int(world.civilians_remaining).override_failure_message(
		"三隻漏過去但只剩一個平民，應該夾在 0 而不是變成 -2"
	).is_equal(0)

## 一波、一隻、立刻生的世界，用來驗通關判定
func _make_one_enemy_wave_world() -> WorldState:
	var world := _make_world()
	world.enemy_defs = {
		&"orc_grunt": {
			"id": "orc_grunt", "name_key": "enemy.orc_grunt.name",
			"hp": 120.0, "speed": 0.0, "armor": 0.0, "magic_resist": 0.0,
			"bounty": 6, "sprite": "res://game/assets/placeholder_enemy.png",
			"frame_count": 8,
		},
	}
	world.waves = [
		{"delay": 0.0, "groups": [
			{"enemy_id": "orc_grunt", "count": 1, "interval": 1.0, "path_id": "main", "start_delay": 0.0},
		]},
	]
	world.reset_wave_state()
	return world

## WaveSystem 的第一個 tick 只把倒數歸零、把該波標記成 spawning（_start_wave），
## 實際生成要等下一個 tick 的 _tick_spawning 才發生——這條 2-tick 節奏在
## test_wave_system.gd（test_a_sub_tick_interval_spawns_several_in_one_tick）
## 就已經釘住，不是本任務要改的行為。所以這裡也要跑滿 2 個 tick，
## 那隻唯一的敵人才會真的在 world.enemies 裡。
func _advance_until_the_one_enemy_spawns(sim: BattleSim) -> void:
	sim.advance(FRAME)
	sim.advance(FRAME)

func test_waves_advance_inside_the_tick() -> void:
	var world := _make_one_enemy_wave_world()
	var sim := BattleSim.new(world)

	_advance_until_the_one_enemy_spawns(sim)

	assert_array(world.enemies).override_failure_message(
		"波次要在 tick 裡推進；還留在場景層的話這條會是空的"
	).has_size(1)

func test_the_battle_is_not_finished_while_an_enemy_is_alive() -> void:
	var world := _make_one_enemy_wave_world()
	var sim := BattleSim.new(world)
	_advance_until_the_one_enemy_spawns(sim)

	assert_bool(world.battle_finished).override_failure_message(
		"全部生成完但場上還有活著的敵人，還沒通關"
	).is_false()

func test_the_battle_finishes_on_the_very_tick_the_last_enemy_dies() -> void:
	# 這條是本任務最重要的一條。一個在 _remove_dead() 之前判定的實作會通過
	# 大部分測試——多數 tick 裡最後一隻敵人早就死了。這裡刻意讓牠「這一 tick
	# 才剛被打死」：判定若排在移除死亡之前，這一 tick 就會錯答成未完成。
	var world := _make_one_enemy_wave_world()
	var sim := BattleSim.new(world)
	_advance_until_the_one_enemy_spawns(sim)
	var enemy: Enemy = world.enemies[0]

	# 直接把牠打死，模擬「這一 tick 傷害剛好結算完」
	enemy.hp = 0.0
	enemy.alive = false
	sim.advance(FRAME)

	assert_array(world.enemies).has_size(0)
	assert_bool(world.battle_finished).override_failure_message(
		"最後一隻在這一 tick 被移除，通關判定必須在同一 tick 成立"
	).is_true()

func test_a_finished_battle_stops_advancing() -> void:
	var world := _make_one_enemy_wave_world()
	var sim := BattleSim.new(world)
	_advance_until_the_one_enemy_spawns(sim)
	world.enemies[0].alive = false
	sim.advance(FRAME)
	assert_bool(world.battle_finished).is_true()

	var ticks_before := sim.tick_count
	var ticks := sim.advance(FRAME * 10.0)

	assert_int(ticks).override_failure_message(
		"通關後 advance() 必須回傳 0——模擬自己停住，不需要 UI 去暫停它"
	).is_equal(0)
	assert_int(sim.tick_count).override_failure_message(
		"通關後 tick 不該再前進"
	).is_equal(ticks_before)

## 與 test_pause_drained_mid_catchup_stops_the_loop_immediately() 同一個道理，
## 換成 battle_finished 這個跳出條件：一次補跑欠 5 個 tick，若唯一的敵人在
## 第 2 個 tick 才漏過終點（battle_finished 因此在第 2 個 tick 結尾成立），
## 其餘 3 個 tick 不該再跑——不然通關那一刻之後敵人、投射物、金幣仍會照跑，
## 只是「碰巧」在下一幀才真的停下來，跟 ui/result_panel.gd 依賴的
## 「world.battle_finished 成立時模擬已經自己停了」這個假設矛盾。
func test_battle_finished_mid_catchup_stops_the_loop_immediately() -> void:
	var world := _make_one_enemy_wave_world()
	var sim := BattleSim.new(world)
	_advance_until_the_one_enemy_spawns(sim)
	var enemy: Enemy = world.enemies[0]
	# 路徑總長 600px。每 tick 走 400px：第 1 個 tick 到 400（未漏），
	# 第 2 個 tick 累積到 800（觸發漏過終點）——刻意不讓它在第 1 個 tick 就結束，
	# 否則跟「補跑迴圈根本沒機會多跑」的情境測不出差別。
	enemy.base_speed = 12000.0
	enemy.reset_derived_stats()

	var ticks := sim.advance(FRAME * 5.0)   # 一次欠 5 個 tick

	assert_int(ticks).override_failure_message(
		"迴圈條件必須重讀 battle_finished：欠 5 個 tick 時，唯一的敵人在第 2 個 tick 漏過終點，" +
		"其餘 3 個 tick 完全不該跑"
	).is_equal(2)
	assert_bool(world.battle_finished).override_failure_message(
		"battle_finished 必須在敵人漏過終點、場上不再有活著敵人的那個 tick 就成立"
	).is_true()

func test_a_call_next_wave_intent_starts_the_wave_and_pays() -> void:
	var world := _make_one_enemy_wave_world()
	world.waves[0]["delay"] = 5.0
	world.call_bonus_per_second = 2
	world.reset_wave_state()
	world.gold = 0
	var sim := BattleSim.new(world)

	world.queue_intent(GameIntent.call_next_wave())
	sim.advance(FRAME)

	assert_int(world.gold).override_failure_message(
		"意圖必須真的走到 WaveSystem——倒數剩 5 秒、每秒 2，應該入帳 10"
	).is_equal(10)
	assert_array(world.enemies).override_failure_message(
		"呼叫之後那一波要立刻開始生"
	).has_size(1)
