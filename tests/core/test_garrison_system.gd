extends GdUnitTestSuite

const TICK := 1.0 / 30.0

func _barracks(world: WorldState, count: int, hp: float, respawn: float, regen: float) -> Tower:
	var tower := Tower.new()
	tower.kind = Tower.KIND_BARRACKS
	tower.post_path_id = &"main"
	tower.post_distance = 70.0
	tower.post_position = Vector2(70.0, 0.0)
	tower.soldier_hp = hp
	tower.soldier_damage = 6.0
	tower.soldier_attack_interval = 1.0
	tower.soldier_armor = 0.1
	tower.respawn_time = respawn
	tower.regen_per_second = regen
	tower.soldier_ids.resize(count)
	tower.respawn_timers.resize(count)
	world.add_tower(tower)
	return tower

func test_a_new_barracks_fills_every_slot_on_the_first_tick() -> void:
	var world := WorldState.new()
	var tower := _barracks(world, 3, 90.0, 12.0, 4.0)

	GarrisonSystem.tick(world, TICK)

	assert_int(world.soldiers.size()).is_equal(3)
	for i in 3:
		assert_int(tower.soldier_ids[i]).is_greater(0)

func test_soldiers_are_born_at_the_barracks_post() -> void:
	var world := WorldState.new()
	_barracks(world, 1, 90.0, 12.0, 4.0)
	GarrisonSystem.tick(world, TICK)

	var soldier: Soldier = world.soldiers[0]
	assert_str(soldier.path_id).is_equal("main")
	assert_float(soldier.post_distance).is_equal_approx(70.0, 0.001)
	assert_float(soldier.hp).is_equal_approx(90.0, 0.001)

func test_an_empty_slot_waits_out_its_respawn_timer() -> void:
	var world := WorldState.new()
	var tower := _barracks(world, 1, 90.0, 1.0, 4.0)
	tower.respawn_timers[0] = 1.0

	# 29 個 tick = 0.9667 秒，還不到 1.0
	for i in 29:
		GarrisonSystem.tick(world, TICK)
	assert_int(world.soldiers.size()).is_equal(0)

	# 第 30 個 tick 剛好走完，同一個 tick 內就補兵——這不是「剛好」，是
	# respawn_timers 用 PackedFloat32Array（單精度）儲存導致的捨入結果
	# （見 core/entities/tower.gd 的欄位註解）。若有人把它改成 double，
	# 這裡會晚一個 tick 才補兵，這條測試就會紅。
	GarrisonSystem.tick(world, TICK)
	assert_int(world.soldiers.size()).is_equal(1)

func test_the_respawned_soldier_goes_back_to_the_same_slot_index() -> void:
	var world := WorldState.new()
	var tower := _barracks(world, 3, 90.0, 0.0, 4.0)
	GarrisonSystem.tick(world, TICK)

	# 模擬第 1 號名額的小兵死掉並被清理
	var dead_id := tower.soldier_ids[1]
	tower.soldier_ids[1] = 0
	tower.respawn_timers[1] = 0.0
	var dead: Soldier = world.soldiers_by_id[dead_id]
	world.soldiers.erase(dead)
	world.soldiers_by_id.erase(dead_id)

	GarrisonSystem.tick(world, TICK)

	assert_int(world.soldiers.size()).is_equal(3)
	assert_int(tower.soldier_ids[1]).is_greater(0)
	assert_int(tower.soldier_ids[1]).is_not_equal(dead_id)

func test_an_idle_soldier_regenerates() -> void:
	var world := WorldState.new()
	# regen 特意不選 30.0：30 × (1/30) 恰好整除成 1.0，會讓「每 tick 回滿一秒的
	# 量」這種誤用與正確的「每 tick 回 regen × delta」算出一樣的答案，測試就
	# 失去鑑別力。7.0 讓一個 tick 回 7/30 = 0.2333…，兩種實作的結果會分岔。
	_barracks(world, 1, 100.0, 12.0, 7.0)
	GarrisonSystem.tick(world, TICK)
	var soldier: Soldier = world.soldiers[0]
	soldier.hp = 40.0

	# 7.0 每秒 × 一個 tick(1/30 秒) = 7.0/30.0 = 0.2333...
	GarrisonSystem.tick(world, TICK)
	assert_float(soldier.hp).is_equal_approx(40.0 + 7.0 / 30.0, 0.0001)

func test_regeneration_stops_at_max_hp() -> void:
	var world := WorldState.new()
	_barracks(world, 1, 100.0, 12.0, 30.0)
	GarrisonSystem.tick(world, TICK)
	var soldier: Soldier = world.soldiers[0]
	soldier.hp = 99.9

	GarrisonSystem.tick(world, TICK)
	assert_float(soldier.hp).is_equal_approx(100.0, 0.001)

## 交戰中不回血，否則防線永遠打不破。
func test_an_engaged_soldier_does_not_regenerate() -> void:
	var world := WorldState.new()
	_barracks(world, 1, 100.0, 12.0, 30.0)
	GarrisonSystem.tick(world, TICK)
	var soldier: Soldier = world.soldiers[0]
	soldier.hp = 40.0
	soldier.engaged_enemy_id = 999

	GarrisonSystem.tick(world, TICK)
	assert_float(soldier.hp).is_equal_approx(40.0, 0.001)

## 射擊塔沒有名額陣列，GarrisonSystem 必須完全跳過它。
func test_shooter_towers_are_ignored() -> void:
	var world := WorldState.new()
	var tower := Tower.new()
	tower.kind = Tower.KIND_SHOOTER
	world.add_tower(tower)

	GarrisonSystem.tick(world, TICK)
	assert_int(world.soldiers.size()).is_equal(0)

## 池化的小兵帶著上輩子的欄位值回來。這條抓的是「重生時沒有整個重設」。
func test_a_recycled_soldier_is_not_born_already_engaged() -> void:
	var world := WorldState.new()
	var tower := _barracks(world, 1, 90.0, 0.0, 4.0)
	GarrisonSystem.tick(world, TICK)

	var first: Soldier = world.soldiers[0]
	first.engaged_enemy_id = 777
	first.hp = 3.0
	first.cooldown = 0.5
	first.alive = false
	# 走 _remove_dead 的清理路徑：歸還到池、名額空出來
	world.soldiers.erase(first)
	world.soldiers_by_id.erase(first.id)
	world.soldier_pool.release(first)
	tower.soldier_ids[0] = 0
	tower.respawn_timers[0] = 0.0

	GarrisonSystem.tick(world, TICK)

	var reborn: Soldier = world.soldiers[0]
	assert_int(reborn.engaged_enemy_id).override_failure_message(
		"重生的小兵帶著上輩子的 engaged_enemy_id。它會以為自己正在跟一個早就\n" +
		"不存在的敵人交戰，於是永遠不接戰、也永遠不回血，但畫面上站得好好的。"
	).is_equal(0)
	assert_float(reborn.hp).is_equal_approx(90.0, 0.001)
	assert_float(reborn.cooldown).is_equal_approx(0.0, 0.001)
	assert_bool(reborn.alive).is_true()
