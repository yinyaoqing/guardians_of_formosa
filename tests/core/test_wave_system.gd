extends GdUnitTestSuite

## 波次的推進、倒數、生成節奏與提前呼叫。整組是純邏輯，所以全部測得到——
## 這是把生成從場景層搬進 core/ 最大的好處。

const FRAME := 1.0 / 30.0
const PATH_ID := &"main"

func _make_world() -> WorldState:
	var world := WorldState.new()
	var points := PackedVector2Array([
		Vector2(0, 0), Vector2(200, 0), Vector2(400, 0), Vector2(600, 0),
	])
	world.paths[PATH_ID] = PathData.new(points, 200.0)
	world.enemy_defs = {
		&"orc_grunt": {
			"id": "orc_grunt", "name_key": "enemy.orc_grunt.name",
			"hp": 120.0, "speed": 45.0, "armor": 0.2, "magic_resist": 0.0,
			"bounty": 6, "sprite": "res://game/assets/placeholder_enemy.png",
			"frame_count": 8,
		},
	}
	world.call_bonus_per_second = 2
	world.gold = 0
	return world

## 兩波：第一波等 4 秒生 3 隻（間隔 1 秒），第二波等 6 秒生 2 隻
func _two_waves() -> Array:
	return [
		{"delay": 4.0, "groups": [
			{"enemy_id": "orc_grunt", "count": 3, "interval": 1.0, "path_id": "main", "start_delay": 0.0},
		]},
		{"delay": 6.0, "groups": [
			{"enemy_id": "orc_grunt", "count": 2, "interval": 1.0, "path_id": "main", "start_delay": 0.0},
		]},
	]

func _configure(world: WorldState, waves: Array) -> void:
	world.waves = waves
	world.reset_wave_state()

## 推進 seconds 秒，一次一個 tick。
##
## 注意 FRAME 是 1/30，二進位下不精確，所以 int(seconds / FRAME) 偶爾會比
## 「預期的」tick 數少一個（例如 4.1 秒算出來是 122 而不是 123）。現有的測試
## 都留了足夠餘裕吸收這一個 tick；若之後寫的測試卡在剛好一個 tick 的邊界上，
## 要改用明確的 tick 數而不是秒數。
func _run(world: WorldState, seconds: float) -> void:
	var ticks := int(seconds / FRAME)
	for i in ticks:
		WaveSystem.tick(world, FRAME)

func test_the_first_wave_waits_for_its_delay() -> void:
	var world := _make_world()
	_configure(world, _two_waves())

	_run(world, 3.0)
	assert_array(world.enemies).override_failure_message(
		"第一波的 delay 是開局的準備時間，時間沒到不該有敵人"
	).has_size(0)

	_run(world, 1.5)
	assert_int(world.enemies.size()).override_failure_message(
		"4 秒的 delay 過了就該開始生"
	).is_greater(0)

func test_enemies_spawn_on_the_group_interval() -> void:
	# 刻意檢查中間的時間點：一次全生出來的實作在「跑完整波」時看起來一樣。
	var world := _make_world()
	_configure(world, _two_waves())

	_run(world, 4.0 + 0.1)
	assert_array(world.enemies).override_failure_message(
		"剛開始生時只該有第一隻"
	).has_size(1)

	_run(world, 1.0)
	assert_array(world.enemies).has_size(2)

	_run(world, 1.0)
	assert_array(world.enemies).has_size(3)

	_run(world, 3.0)
	assert_array(world.enemies).override_failure_message(
		"這一波只有 3 隻，不該繼續生"
	).has_size(3)

func test_the_next_countdown_starts_after_spawning_finishes() -> void:
	# delay 的基準是「前一波生成完畢」，不是「前一波開始」，也不是「前一波打完」。
	var world := _make_world()
	_configure(world, _two_waves())

	# 4 秒倒數 + 前兩隻的間隔 2 秒 = 第三隻生出來、該波生成完畢
	_run(world, 4.0 + 2.0 + 0.1)
	assert_array(world.enemies).has_size(3)

	_run(world, 5.5)
	assert_array(world.enemies).override_failure_message(
		"第二波的 6 秒倒數要從第一波生完才起算"
	).has_size(3)

	_run(world, 1.0)
	assert_int(world.enemies.size()).is_greater(3)

func test_groups_can_be_staggered_within_a_wave() -> void:
	var world := _make_world()
	_configure(world, [
		{"delay": 0.0, "groups": [
			{"enemy_id": "orc_grunt", "count": 1, "interval": 1.0, "path_id": "main", "start_delay": 0.0},
			{"enemy_id": "orc_grunt", "count": 1, "interval": 1.0, "path_id": "main", "start_delay": 3.0},
		]},
	])

	_run(world, 0.5)
	assert_array(world.enemies).override_failure_message(
		"第二個群組的 start_delay 是 3 秒，此刻不該出現"
	).has_size(1)

	_run(world, 3.0)
	assert_array(world.enemies).has_size(2)

func test_a_spawned_enemy_starts_at_the_path_origin() -> void:
	var world := _make_world()
	_configure(world, [
		{"delay": 0.0, "groups": [
			{"enemy_id": "orc_grunt", "count": 1, "interval": 1.0, "path_id": "main", "start_delay": 0.0},
		]},
	])
	_run(world, 0.1)

	var enemy: Enemy = world.enemies[0]
	assert_float(enemy.distance_along).is_equal_approx(0.0, 0.001)
	assert_float(enemy.position.x).override_failure_message(
		"座標沒設的話 view 會先出現在原點再跳到路徑起點，看起來像瞬移"
	).is_equal_approx(0.0, 0.001)
	assert_float(enemy.speed).override_failure_message(
		"衍生值沒重算的話新生的敵人速度是 0"
	).is_equal_approx(45.0, 0.001)

func test_calling_early_pays_the_remaining_countdown() -> void:
	# 與 B3b 的退款一致性同類：顯示的與實付的漂移，是玩家會發現、測試不會的錯。
	#
	# 注意：這裡的 expected 是用實作自己的算式（countdown_before * call_bonus_per_second
	# 向下取整）算出來的，所以它守不住「比率本身對不對」——換掉比率或改變無條件捨去的
	# 規則，這條測試照樣是綠的。它真正守住的是「回傳值等於金幣的實際變動量」與
	# 「不是 0」，這兩點仍然值錢。比率本身由 tests/core/test_tick_order.gd 的
	# test_a_call_next_wave_intent_starts_the_wave_and_pays() 用具體數字釘死
	# （倒數 5 秒、每秒 2，斷言入帳恰好 10）——不要刪錯測試。
	var world := _make_world()
	_configure(world, _two_waves())

	_run(world, 1.0)          # 倒數剩約 3 秒
	var countdown_before := world.wave_state.countdown
	var gold_before := world.gold

	var paid := WaveSystem.call_next_wave(world)

	var expected := floori(countdown_before * float(world.call_bonus_per_second))
	assert_int(paid).override_failure_message(
		"回傳的獎勵必須等於剩餘秒數 %.3f × 每秒 %d 向下取整" % [countdown_before, world.call_bonus_per_second]
	).is_equal(expected)
	assert_int(world.gold - gold_before).override_failure_message(
		"實際加進世界的銀必須與回傳值一致"
	).is_equal(paid)
	assert_int(paid).override_failure_message(
		"獎勵不該是 0，否則這條測試在比較兩個零"
	).is_greater(0)

func test_calling_early_starts_the_wave_immediately() -> void:
	var world := _make_world()
	_configure(world, _two_waves())
	_run(world, 1.0)

	WaveSystem.call_next_wave(world)
	WaveSystem.tick(world, FRAME)

	assert_int(world.enemies.size()).override_failure_message(
		"呼叫之後那一波就該立刻開始生"
	).is_greater(0)

func test_calling_while_spawning_is_ignored() -> void:
	var world := _make_world()
	_configure(world, _two_waves())
	_run(world, 4.5)          # 生成中

	var gold_before := world.gold
	var paid := WaveSystem.call_next_wave(world)

	assert_int(paid).override_failure_message(
		"生成中呼叫應靜默忽略，沒有獎勵"
	).is_equal(0)
	assert_int(world.gold).is_equal(gold_before)

func test_calling_after_every_wave_is_spawned_is_ignored() -> void:
	var world := _make_world()
	_configure(world, _two_waves())
	_run(world, 30.0)

	assert_bool(WaveSystem.all_spawned(world)).is_true()
	var gold_before := world.gold
	assert_int(WaveSystem.call_next_wave(world)).is_equal(0)
	assert_int(world.gold).is_equal(gold_before)

func test_all_spawned_is_false_while_any_wave_remains() -> void:
	# 刻意在「第一波生完、第二波還沒開始」這個空檔問——一個只看
	# 「場上有沒有敵人」的實作會在這裡錯答成 true。
	var world := _make_world()
	_configure(world, _two_waves())
	_run(world, 6.5)

	assert_bool(WaveSystem.all_spawned(world)).override_failure_message(
		"第二波還沒生，不算全部生成完畢"
	).is_false()

func test_total_spawned_matches_the_data() -> void:
	var world := _make_world()
	_configure(world, _two_waves())
	_run(world, 30.0)

	assert_array(world.enemies).override_failure_message(
		"兩波合計 3 + 2 = 5 隻，多生或少生都是節奏錯誤"
	).has_size(5)

func test_a_sub_tick_interval_spawns_several_in_one_tick() -> void:
	# 這條守著 _tick_spawning 那個 while 迴圈存在的理由：interval 小於一個 tick 時，
	# 一個 tick 要生好幾隻。換成 if 會把生成速率靜默地壓在每秒 30 隻，而症狀是
	# 「最後一波感覺比資料上寫的稀疏」——現有資料與其他測試的 interval 全都遠大於
	# 一個 tick，所以在這條之前沒有任何一條抓得到。
	var world := _make_world()
	_configure(world, [
		{"delay": 0.0, "groups": [
			{"enemy_id": "orc_grunt", "count": 5, "interval": 0.001, "path_id": "main", "start_delay": 0.0},
		]},
	])

	WaveSystem.tick(world, FRAME)   # 倒數歸零，這一 tick 只開始不生成
	WaveSystem.tick(world, FRAME)   # 這一 tick 要把五隻都生完

	assert_array(world.enemies).override_failure_message(
		"interval 0.001 秒遠小於一個 tick，一個 tick 應該生完五隻；只生一隻代表 while 被換成了 if"
	).has_size(5)
