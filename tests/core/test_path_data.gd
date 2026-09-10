extends GdUnitTestSuite

## 一條水平直線路徑：(0,0) → (100,0) → (200,0)，取樣間距 100
func _make_straight_path() -> PathData:
	var points := PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(200, 0),
	])
	return PathData.new(points, 100.0)

func test_total_length_is_spacing_times_segments() -> void:
	assert_float(_make_straight_path().total_length()).is_equal_approx(200.0, 0.001)

func test_position_at_start() -> void:
	var pos := _make_straight_path().position_at(0.0)
	assert_float(pos.x).is_equal_approx(0.0, 0.001)

func test_position_at_midpoint_interpolates() -> void:
	var pos := _make_straight_path().position_at(150.0)
	assert_float(pos.x).is_equal_approx(150.0, 0.001)

func test_position_before_start_clamps_to_first_point() -> void:
	var pos := _make_straight_path().position_at(-50.0)
	assert_float(pos.x).is_equal_approx(0.0, 0.001)

func test_position_beyond_end_clamps_to_last_point() -> void:
	var pos := _make_straight_path().position_at(999.0)
	assert_float(pos.x).is_equal_approx(200.0, 0.001)

func test_position_exactly_at_end_returns_last_point() -> void:
	var pos := _make_straight_path().position_at(200.0)
	assert_float(pos.x).is_equal_approx(200.0, 0.001)

## 一條沿 x 軸、間距 10、長度 100 的直線路徑
func _straight_path() -> PathData:
	var points := PackedVector2Array()
	for i in 11:
		points.append(Vector2(float(i) * 10.0, 0.0))
	return PathData.new(points, 10.0)

func test_nearest_distance_finds_the_closest_sample() -> void:
	var path := _straight_path()
	# (32, 25) 最近的取樣點是 (30, 0)，行進距離 30
	assert_float(path.nearest_distance_to(Vector2(32.0, 25.0))).is_equal_approx(30.0, 0.001)

func test_nearest_distance_at_the_far_end() -> void:
	var path := _straight_path()
	assert_float(path.nearest_distance_to(Vector2(500.0, 0.0))).is_equal_approx(100.0, 0.001)

## 這條的存在理由：若實作誤用「第一個距離小於某門檻的取樣點」而非「真正最近者」，
## 上面兩條仍會通過（起點附近沒有干擾），這條不會。
func test_nearest_distance_prefers_the_actual_nearest_not_the_first_close_one() -> void:
	var path := _straight_path()
	# (71, 3) 離 (70,0) 距離 3、離 (80,0) 距離 ~9.5，答案必須是 70
	assert_float(path.nearest_distance_to(Vector2(71.0, 3.0))).is_equal_approx(70.0, 0.001)
