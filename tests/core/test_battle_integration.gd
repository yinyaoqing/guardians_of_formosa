extends GdUnitTestSuite

const FRAME_60FPS := 1.0 / 60.0
const PATH_ID := &"main"

func _make_world() -> WorldState:
	var world := WorldState.new()
	var points := PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(200, 0),
		Vector2(300, 0),
	])
	world.paths[PATH_ID] = PathData.new(points, 100.0)
	world.gold = 0
	world.lives = 20
	return world

func _add_enemy(world: WorldState, hp: float, speed: float, bounty: int) -> Enemy:
	var enemy := Enemy.new()
	enemy.enemy_id = &"orc_grunt"
	enemy.hp = hp
	enemy.max_hp = hp
	enemy.base_speed = speed
	enemy.reset_derived_stats()
	enemy.bounty = bounty
	enemy.path_id = PATH_ID
	world.add_enemy(enemy)
	return enemy

func _add_tower(world: WorldState, pos: Vector2, damage: float, fire_interval: float, projectile_speed: float = 600.0) -> Tower:
	var tower := Tower.new()
	tower.tower_id = &"archer_tower"
	tower.position = pos
	tower.attack_range = 150.0
	tower.damage = damage
	tower.damage_type = DamageSystem.PHYSICAL
	tower.fire_interval = fire_interval
	tower.projectile_speed = projectile_speed
	tower.splash_radius = 0.0
	world.add_tower(tower)
	return tower

## 推進模擬指定秒數
func _run(sim: BattleSim, seconds: float) -> void:
	var frames := int(seconds / FRAME_60FPS)
	for i in frames:
		sim.advance(FRAME_60FPS)

func test_tower_kills_enemy_in_range() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 30.0, 0.0, 5)
	enemy.position = Vector2(50, 0)
	_add_tower(world, Vector2(50, 0), 10.0, 0.5)
	var sim := BattleSim.new(world)
	_run(sim, 2.0)
	assert_bool(enemy.alive).is_false()

func test_killing_enemy_awards_bounty_once() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 10.0, 0.0, 7)
	enemy.position = Vector2(50, 0)
	_add_tower(world, Vector2(50, 0), 10.0, 0.5)
	var sim := BattleSim.new(world)
	_run(sim, 3.0)
	assert_int(world.gold).is_equal(7)

func test_enemy_reaching_end_costs_a_life() -> void:
	var world := _make_world()
	_add_enemy(world, 1000.0, 400.0, 5)
	var sim := BattleSim.new(world)
	_run(sim, 2.0)
	assert_int(world.lives).is_equal(19)

func test_leaked_enemy_only_costs_one_life() -> void:
	var world := _make_world()
	_add_enemy(world, 1000.0, 400.0, 5)
	var sim := BattleSim.new(world)
	_run(sim, 5.0)
	assert_int(world.lives).is_equal(19)

func test_tower_out_of_range_does_not_damage() -> void:
	var world := _make_world()
	var enemy := _add_enemy(world, 100.0, 0.0, 5)
	enemy.position = Vector2(0, 0)
	_add_tower(world, Vector2(1000, 1000), 10.0, 0.5)
	var sim := BattleSim.new(world)
	_run(sim, 2.0)
	assert_float(enemy.hp).is_equal_approx(100.0, 0.001)

func test_fire_interval_limits_shots() -> void:
	# 塔與敵人同座標，距離為 0：投射物於生成的下一 tick 立即命中
	# （ProjectileSystem 排在 _tick_towers 之前，故 tick N 生成的投射物要到
	# tick N+1 才被處理；那一 tick 的移動距離必然 >= 0，於是命中）。
	# 因此每一發的傷害相對「開火即結算」延後恰好一個 tick：
	# 第一發於 tick 1 開火、tick 2 命中。第二發理論上該在 15 tick 冷卻
	# （射速 0.5 秒）後、也就是 tick 16 開火，但 cooldown 是逐 tick 以浮點數
	# 減去 TICK_DELTA（1.0/30.0）：連續 15 次從 0.5 減去 1/30，殘留的浮點
	# 誤差約 9.7e-17（並非精確的 0），使 tick 16 當下 cooldown 仍 > 0，
	# 於是實際上第二發於 tick 17 開火、tick 18 命中。兩發都仍落在 1 秒
	# （30 tick）之內，傷害總量不變：兩發共 20 傷害，留下 980.0 HP。
	var world := _make_world()
	var enemy := _add_enemy(world, 1000.0, 0.0, 5)
	enemy.position = Vector2(50, 0)
	_add_tower(world, Vector2(50, 0), 10.0, 0.5)
	var sim := BattleSim.new(world)
	_run(sim, 1.0)
	assert_float(enemy.hp).is_equal_approx(980.0, 0.001)

## 下面這份路徑點與取樣間距,對應 game/level/battle_scene.tscn 的
## MainPath（Curve2D 折線頂點 (100,150)→(700,150)→(700,250)→(100,250)→
## (100,600)→(1850,600)，控制點皆為 0）與 battle_scene.gd 的
## PATH_SAMPLE_SPACING = 8.0。兩邊描述的是同一條 demo 路徑，
## 修改其中一邊時必須同步修改另一邊，否則這個測試就不再代表 demo 場景。
var DEMO_PATH_WAYPOINTS := PackedVector2Array([
	Vector2(100, 150),
	Vector2(700, 150),
	Vector2(700, 250),
	Vector2(100, 250),
	Vector2(100, 600),
	Vector2(1850, 600),
])
const DEMO_PATH_SPACING := 8.0
const DEMO_TOWER_POSITION := Vector2(400, 200)

## 依 battle_scene.gd 的 _bake_path 邏輯，把折線等距取樣成點陣列後交給 PathData。
func _bake_demo_path() -> PathData:
	var curve := Curve2D.new()
	for point: Vector2 in DEMO_PATH_WAYPOINTS:
		curve.add_point(point)
	var length := curve.get_baked_length()
	var sample_count := int(length / DEMO_PATH_SPACING) + 1
	var points := PackedVector2Array()
	for i in sample_count:
		points.append(curve.sample_baked(float(i) * DEMO_PATH_SPACING))
	return PathData.new(points, DEMO_PATH_SPACING)

## M0 的里程碑場景就是「敵人沿路徑走、塔開火、敵人死亡」。這個測試用真實的
## data/ 數值與 demo 路徑幾何重現那個場景——不手動指定任何傷害/血量/射程數字，
## 因為那些數字本來就會變，測試要盯住的是「這組出貨數值仍然打得死」這件事本身。
func test_shipped_data_lets_one_tower_kill_one_enemy() -> void:
	var registry := DataRegistry.new()
	registry.load_from_disk()

	var world := WorldState.new()
	world.paths[PATH_ID] = _bake_demo_path()
	world.gold = 0
	world.lives = 20

	var enemy := registry.make_enemy(&"orc_grunt", PATH_ID)
	enemy.position = world.paths[PATH_ID].position_at(0.0)
	world.add_enemy(enemy)

	var tower_def: Dictionary = registry.towers[&"archer_tower"]
	var level_def: Dictionary = tower_def["levels"][0]
	var tower := Tower.new()
	tower.tower_id = &"archer_tower"
	tower.position = DEMO_TOWER_POSITION
	tower.damage = level_def["damage"]
	tower.damage_type = StringName(tower_def["damage_type"])
	tower.attack_range = level_def["attack_range"]
	tower.fire_interval = level_def["fire_interval"]
	tower.projectile_speed = level_def["projectile_speed"]
	tower.splash_radius = level_def["splash_radius"]
	var on_hit_effects: Array[StringName] = []
	for effect_id in level_def["on_hit_effects"]:
		on_hit_effects.append(StringName(effect_id))
	tower.on_hit_effects = on_hit_effects
	world.add_tower(tower)

	var starting_gold := world.gold
	var starting_lives := world.lives
	var bounty := enemy.bounty

	var sim := BattleSim.new(world)
	var max_frames := int(90.0 / FRAME_60FPS)
	for i in max_frames:
		sim.advance(FRAME_60FPS)
		if not enemy.alive:
			break

	# 敵人在這條路徑上一定會在 ~75.6 秒（3400px / 45px/s）走到終點,所以
	# 「alive 變 false」在死亡與洩漏兩種情況下都成立,真正能分辨勝負的是
	# leaked——這才是數值失衡時真正會炸開的斷言,因此把說明訊息掛在這裡。
	assert_bool(enemy.leaked).override_failure_message(
		"出貨數值(data/enemies/orc_grunt.json 的 hp/armor 與 data/towers/archer_tower.json 第一級的 damage/attack_range/fire_interval)已經無法在 demo 路徑上讓一座塔擊殺一隻敵人——敵人在塔殺死它之前就洩漏到路徑終點,里程碑的視覺驗收會失敗,請重新調整平衡數值。"
	).is_false()
	assert_bool(enemy.alive).is_false()
	assert_int(world.gold).is_equal(starting_gold + bounty)
	assert_int(world.lives).is_equal(starting_lives)
	assert_float(tower.projectile_speed).override_failure_message(
		"Tower.projectile_speed 沒有從關卡資料複製過去——改 data/towers/archer_tower.json 的 projectile_speed 不會有任何效果"
	).is_equal_approx(float(level_def["projectile_speed"]), 0.001)

func test_damage_is_not_applied_at_fire_time() -> void:
	# 驗證傷害在命中時結算，而非開火時結算。兩座塔同時對敵人開火，
	# 敵人血量充足（1000 HP vs 每發 10 傷害）。推進恰好一個 tick，
	# 也就是兩座塔剛開火的那一 tick，立刻檢查。若傷害在「發射當下」結算，
	# 敵人此刻就該已經掉血；但本專案設計傷害要到「命中那一 tick」才結算，
	# 所以敵人應該還是滿血，兩發投射物都還在飛行中、尚未被消耗。
	# 敵人的實際座標由 MovementSystem 每 tick 依 distance_along 從路徑重新換算
	# （position_at），直接指定 .position 會在第一個 tick 就被蓋掉,所以這裡改用
	# distance_along 來控制座標——_make_world 的路徑點都落在 x 軸上、取樣間距 100，
	# 所以 distance_along = 50.0 換算回來正好是 (50, 0)。
	var world := _make_world()
	var enemy := _add_enemy(world, 1000.0, 0.0, 5)
	enemy.distance_along = 50.0
	_add_tower(world, Vector2(50, 0), 10.0, 5.0)
	_add_tower(world, Vector2(50, 0), 10.0, 5.0)
	var sim := BattleSim.new(world)

	_run(sim, 2.0 * FRAME_60FPS)  # 恰好一個 tick：兩座塔剛開火，投射物尚未命中

	assert_float(enemy.hp).override_failure_message(
		"傷害不可以在開火當下結算——命中還沒發生，敵人血量必須維持滿血"
	).is_equal_approx(1000.0, 0.001)
	assert_array(world.projectiles).override_failure_message(
		"兩座塔剛開火那一 tick，兩發投射物都應該還在飛行中"
	).has_size(2)

func test_projectile_is_wasted_when_its_target_dies_first() -> void:
	# 兩座塔對準同一隻敵人：近塔的投射物下一 tick 就命中並一擊斃命，
	# 遠塔的投射物飛行速度慢、距離又長，命中前敵人已經死亡。
	# 這個測試釘住「目標死亡的投射物會被釋放而非轉移目標」——
	# 若實作改成幫飛行中的投射物重新鎖定最近的敵人，旁邊那隻無辜的
	# 待轟敵人就會平白受傷，斷言會立刻失敗。
	#
	# 敵人的實際座標由 MovementSystem 每 tick 依 distance_along 從路徑重新換算,
	# 直接指定 .position 在第一個 tick 就會被蓋掉,所以這裡一律用 distance_along
	# 控制座標（_make_world 的路徑點都落在 x 軸上、取樣間距 100，換算是線性的）。
	var world := _make_world()

	var victim := _add_enemy(world, 5.0, 0.0, 5)
	victim.distance_along = 100.0  # 換算座標 (100, 0)

	var bystander := _add_enemy(world, 100.0, 0.0, 3)
	# distance_along 故意比 victim 小，確保 TargetingSystem（挑 distance_along
	# 最大者）兩座塔永遠選中 victim、不會選到它；換算座標 (90, 0) 離 victim 只有
	# 10，緊鄰 victim，足以驗證傷害沒有轉移過來。
	bystander.distance_along = 90.0

	_add_tower(world, Vector2(100, 0), 10.0, 5.0)          # 近塔：距離 0,下一 tick 命中
	_add_tower(world, Vector2(230, 0), 10.0, 5.0, 300.0)   # 遠塔：距離 130,飛行速度慢

	var sim := BattleSim.new(world)
	_run(sim, 8.0 * FRAME_60FPS)  # 4 個 tick：足夠近塔命中、victim 死亡、遠塔投射物被釋放

	assert_bool(victim.alive).override_failure_message(
		"近塔的投射物應該已經命中並擊殺 victim"
	).is_false()
	assert_int(world.gold).override_failure_message(
		"victim 的賞金只能發放一次"
	).is_equal(5)
	assert_float(bystander.hp).override_failure_message(
		"victim 死亡時，遠塔那發還在飛的投射物必須被釋放而非轉移到旁邊的 bystander 身上"
	).is_equal_approx(100.0, 0.001)
	assert_array(world.projectiles).override_failure_message(
		"遠塔的投射物在確認目標已死後應該被釋放，不會一直卡在 world.projectiles 裡"
	).has_size(0)

func test_configure_for_level_wires_everything_the_world_needs() -> void:
	# 每多一項注入就多一個「要記得接線」的地方。M1-A 的最終 review 抓到漏接
	# effect_defs 導致狀態效果在遊戲中無聲失效，所以這裡逐項守住。
	var registry := DataRegistry.new()
	registry.load_from_disk()

	var world := WorldState.new()
	world.configure_for_level(registry, &"level_01")

	var meta: Dictionary = registry.levels[&"level_01"]

	assert_int(world.effect_defs.size()).override_failure_message(
		"未注入狀態效果定義，命中效果會在遊戲中無聲失效"
	).is_greater(0)
	assert_int(world.tower_defs.size()).override_failure_message(
		"未注入塔的定義，建塔會找不到資料"
	).is_greater(0)
	assert_int(world.available_towers.size()).override_failure_message(
		"未注入本關可用塔種，所有建造都會被拒絕"
	).is_equal(meta["available_towers"].size())
	assert_float(world.sell_refund_ratio).is_equal_approx(meta["sell_refund_ratio"], 0.001)
	assert_int(world.gold).is_equal(int(meta["starting_gold"]))
	assert_int(world.lives).is_equal(int(meta["starting_lives"]))

## Fix 5 的浸泡測試:池的斷言到目前為止都只涵蓋單一物件、單一 tick,
## 真正的洩漏只會在一整場戰鬥的規模下才會現形。這裡連續生成數十隻敵人、
## 讓一座塔持續開火並施加 on_hit 效果,經歷死亡、洩漏與效果到期後,
## 驗證投射物池與效果池都確實回滿。
func test_pools_return_to_full_capacity_after_a_long_battle() -> void:
	var world := _make_world()
	var starting_lives := world.lives
	world.effect_defs[&"chill"] = {"id": "chill", "kind": "slow", "magnitude": 0.3, "duration": 1.0}

	var tower := _add_tower(world, Vector2(150, 0), 5.0, 0.2, 600.0)
	tower.attack_range = 500.0  # 覆蓋整條路徑,確保塔全程都有目標可打
	tower.on_hit_effects.assign([&"chill"] as Array[StringName])

	var sim := BattleSim.new(world)

	const SPAWN_INTERVAL := 0.75
	const SPAWN_PHASE_SECONDS := 20.0
	const TOTAL_TICKS := 900   # 30 秒,含尾端 10 秒淨空期

	var spawn_timer := 0.0
	var elapsed := 0.0
	var spawn_toggle := false

	for tick_i in TOTAL_TICKS:
		elapsed += BattleSim.TICK_DELTA
		if elapsed <= SPAWN_PHASE_SECONDS:
			spawn_timer -= BattleSim.TICK_DELTA
			if spawn_timer <= 0.0:
				spawn_timer = SPAWN_INTERVAL
				if spawn_toggle:
					_add_enemy(world, 10.0, 40.0, 3)     # 血薄,會被塔擊殺
				else:
					_add_enemy(world, 5000.0, 250.0, 3)  # 血厚腳快,會洩漏到終點
				spawn_toggle = not spawn_toggle
		sim.advance(BattleSim.TICK_DELTA)   # 每次呼叫剛好推進一個 tick

	# 驗證戰鬥確實發生過：空戰場的池結果會自動滿足,因此需要證明至少殺死與洩漏了敵人
	assert_int(world.gold).override_failure_message(
		"浸泡測試無意義,除非戰鬥實際擊殺並支付賞金——空戰場的池結果會自動滿足池滿檢驗"
	).is_greater(0)
	assert_bool(world.lives < starting_lives).override_failure_message(
		"浸泡測試無意義,除非戰鬥實際讓敵人洩漏到路徑終點——空戰場的池結果會自動滿足池滿檢驗"
	).is_true()

	# 驗證戰鬥已結束：任何仍在場上的敵人會持著池內物件,導致下方池檢驗失敗時指向錯誤的根本原因
	assert_array(world.enemies).override_failure_message(
		"場上仍有敵人未清理,它們持著已分配的池內狀態效果實例,下方的池檢驗會因此失敗——原因不是洩漏,而是戰鬥未完成"
	).has_size(0)

	assert_array(world.projectiles).override_failure_message(
		"整場戰鬥結束後仍有投射物殘留在 world.projectiles,代表命中或釋放邏輯漏掉了某些飛行中的投射物"
	).has_size(0)
	assert_int(world.projectile_pool.free_count()).override_failure_message(
		"投射物池未回滿:代表某些投射物被取用後從未歸還,真實對戰中池會無上限增長"
	).is_equal(world.projectile_pool.capacity())
	assert_int(world.effect_pool.free_count()).override_failure_message(
		"效果池未回滿:代表某些狀態效果實例被取用後從未歸還,真實對戰中池會無上限增長"
	).is_equal(world.effect_pool.capacity())

func test_shipped_data_drives_a_full_projectile_and_status_chain() -> void:
	# 端到端：用真實 JSON 資料，塔發射投射物、命中、造成傷害並施加減速。
	# 不寫死任何平衡數字，全部從 registry 讀，數值調整時不需修改本測試。
	var registry := DataRegistry.new()
	registry.load_from_disk()

	var world := _make_world()
	world.effect_defs = registry.status_effects

	var enemy := registry.make_enemy(&"orc_grunt", PATH_ID)
	enemy.position = Vector2(50, 0)
	world.add_enemy(enemy)

	var tower_def: Dictionary = registry.towers[&"archer_tower"]
	var level_def: Dictionary = tower_def["levels"][0]
	var tower := Tower.new()
	tower.tower_id = &"archer_tower"
	tower.position = Vector2(50, 0)
	tower.damage = level_def["damage"]
	tower.damage_type = StringName(tower_def["damage_type"])
	tower.attack_range = level_def["attack_range"]
	tower.fire_interval = level_def["fire_interval"]
	tower.projectile_speed = level_def["projectile_speed"]
	tower.splash_radius = level_def["splash_radius"]
	tower.on_hit_effects.assign([&"chill"])
	world.add_tower(tower)

	var sim := BattleSim.new(world)
	_run(sim, 2.0)

	assert_bool(enemy.hp < enemy.max_hp).override_failure_message(
		"塔應已透過投射物對敵人造成傷害"
	).is_true()
	assert_array(enemy.active_effects).override_failure_message(
		"命中應施加 on_hit_effects 中的減速"
	).has_size(1)
	assert_bool(enemy.speed < enemy.base_speed).override_failure_message(
		"減速必須反映在衍生速度上，且基礎值不得被改動"
	).is_true()
	assert_float(enemy.base_speed).override_failure_message(
		"基礎速度必須維持 JSON 中的原值"
	).is_equal_approx(registry.enemies[&"orc_grunt"]["speed"], 0.001)
