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
