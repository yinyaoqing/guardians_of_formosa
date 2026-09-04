extends GdUnitTestSuite

func test_empty_grid_returns_no_candidates() -> void:
	var grid := UniformGrid.new()
	assert_array(grid.query_radius(Vector2.ZERO, 100.0)).has_size(0)

func test_inserted_entity_is_found_in_range() -> void:
	var grid := UniformGrid.new()
	grid.insert(7, Vector2(10, 10))
	assert_array(grid.query_radius(Vector2.ZERO, 100.0)).contains([7])

func test_multiple_entities_in_same_cell_are_all_returned() -> void:
	# 驗證值型別陷阱：同格多筆資料不得互相覆蓋
	var grid := UniformGrid.new()
	grid.insert(1, Vector2(10, 10))
	grid.insert(2, Vector2(20, 20))
	grid.insert(3, Vector2(30, 30))
	assert_array(grid.query_radius(Vector2(20, 20), 50.0)).has_size(3)

func test_entity_far_outside_radius_is_not_returned() -> void:
	var grid := UniformGrid.new()
	grid.insert(7, Vector2(1000, 1000))
	assert_array(grid.query_radius(Vector2.ZERO, 50.0)).has_size(0)

func test_query_spans_multiple_cells() -> void:
	var grid := UniformGrid.new()
	grid.insert(1, Vector2(-100, 0))
	grid.insert(2, Vector2(100, 0))
	assert_array(grid.query_radius(Vector2.ZERO, 150.0)).has_size(2)

func test_clear_removes_all_entities() -> void:
	var grid := UniformGrid.new()
	grid.insert(1, Vector2(10, 10))
	grid.clear()
	assert_array(grid.query_radius(Vector2.ZERO, 100.0)).has_size(0)

func test_negative_coordinates_are_handled() -> void:
	# floori 對負數的行為與 int() 截斷不同，必須用 floori
	var grid := UniformGrid.new()
	grid.insert(5, Vector2(-10, -10))
	assert_array(grid.query_radius(Vector2(-10, -10), 10.0)).contains([5])
