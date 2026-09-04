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

func _add_tower(world: WorldState, pos: Vector2, damage: float, fire_interval: float) -> Tower:
	var tower := Tower.new()
	tower.tower_id = &"archer_tower"
	tower.position = pos
	tower.attack_range = 150.0
	tower.damage = damage
	tower.damage_type = DamageSystem.PHYSICAL
	tower.fire_interval = fire_interval
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
	# 1 秒內、射速 0.5 秒一發，應打 2 發共 20 傷害，留下 980.0 HP
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
