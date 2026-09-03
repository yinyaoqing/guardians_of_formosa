extends GdUnitTestSuite

const FRAME_60FPS := 1.0 / 60.0

func test_one_second_of_60fps_frames_produces_30_ticks() -> void:
	var sim := BattleSim.new()
	for i in 60:
		sim.advance(FRAME_60FPS)
	assert_int(sim.tick_count).is_equal(30)

func test_paused_sim_does_not_tick() -> void:
	var sim := BattleSim.new()
	sim.paused = true
	var ticks := sim.advance(FRAME_60FPS * 10.0)
	assert_int(ticks).is_equal(0)
	assert_int(sim.tick_count).is_equal(0)

func test_double_speed_doubles_tick_count() -> void:
	var sim := BattleSim.new()
	sim.speed_multiplier = 2.0
	for i in 60:
		sim.advance(FRAME_60FPS)
	assert_int(sim.tick_count).is_equal(60)

func test_partial_frames_accumulate_without_loss() -> void:
	# 每幀不足一個 tick，但累積滿了就該觸發
	var sim := BattleSim.new()
	var ticks_first := sim.advance(0.01)
	assert_int(ticks_first).is_equal(0)
	sim.advance(0.01)
	sim.advance(0.01)
	sim.advance(0.01)
	# 累積 0.04 秒 > TICK_DELTA (0.0333)，應已跑過一次
	assert_int(sim.tick_count).is_equal(1)

func test_huge_frame_delta_is_capped_and_backlog_discarded() -> void:
	# 防死亡螺旋：卡頓一整秒後不該試圖補跑 30 個 tick
	var sim := BattleSim.new()
	var ticks := sim.advance(1.0)
	assert_int(ticks).is_equal(BattleSim.MAX_TICKS_PER_FRAME)
	# 積欠已被丟棄，下一個正常幀不該爆量
	var next_ticks := sim.advance(FRAME_60FPS)
	assert_int(next_ticks).is_equal(0)
