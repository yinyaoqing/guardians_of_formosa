extends GdUnitTestSuite

## LevelMap 是路徑、地磚、建塔點、擺件的唯一真相；這裡守的是「同一份資料算出來的
## 幾何互相一致」。改 map.json 一個點，PathData 與地磚必須一起變——靠的就是這些換算。

func _def() -> Dictionary:
	return {
		"tile_px": 32, "cols": 10, "rows": 6,
		"path_waypoints": [[0, 2], [4, 2], [4, 4], [9, 4]],
		"path_width": 2,
		"water": {"rect": [7, 0, 10, 2]},
		"tide": {"low_extra_sand": [[7, 1], [8, 1]]},
		"props": [{"id": "prop_banyan", "cell": [1, 0]}, {"id": "prop_settlement", "cell": [8, 3], "shadow": false}],
		"build_slots": [[2, 0], [6, 1]],
	}

func test_cell_center_is_middle_of_tile() -> void:
	var m := LevelMap.new(_def())
	var c := m.cell_center(Vector2i(1, 2))
	assert_float(c.x).is_equal_approx(48.0, 0.001)
	assert_float(c.y).is_equal_approx(80.0, 0.001)

func test_path_cells_follow_waypoints_with_width_two() -> void:
	var cells := LevelMap.new(_def()).path_cells()
	# 水平段 (0,2)→(4,2)：本列與下一列
	assert_bool(cells.has(Vector2i(2, 2))).is_true()
	assert_bool(cells.has(Vector2i(2, 3))).is_true()
	# 垂直段 (4,2)→(4,4)：本欄與右一欄
	assert_bool(cells.has(Vector2i(5, 3))).is_true()
	# 遠離路徑的格子不是路徑
	assert_bool(cells.has(Vector2i(0, 0))).is_false()
	assert_bool(cells.has(Vector2i(9, 0))).is_false()

func test_sample_path_starts_and_ends_at_waypoint_centres() -> void:
	var pts := LevelMap.new(_def()).sample_path(8.0)
	assert_int(pts.size()).is_greater(2)
	assert_float(pts[0].x).is_equal_approx(16.0, 0.001)
	assert_float(pts[0].y).is_equal_approx(80.0, 0.001)
	var last := pts[pts.size() - 1]
	assert_float(last.x).is_equal_approx(304.0, 0.001)
	assert_float(last.y).is_equal_approx(144.0, 0.001)

func test_sample_path_is_evenly_spaced_along_a_straight_segment() -> void:
	# 第一段 (0,2)→(4,2) 是 128px 的直線；轉角處相鄰取樣點是弦長，不驗
	var pts := LevelMap.new(_def()).sample_path(8.0)
	for i in range(1, 16):
		assert_float(pts[i].y).is_equal_approx(80.0, 0.001)
		assert_float(pts[i].distance_to(pts[i - 1])).is_equal_approx(8.0, 0.01)

func test_water_rect_is_half_open() -> void:
	var m := LevelMap.new(_def())
	assert_bool(m.is_water(Vector2i(7, 0))).is_true()
	assert_bool(m.is_water(Vector2i(9, 1))).is_true()
	assert_bool(m.is_water(Vector2i(10, 0))).is_false()
	assert_bool(m.is_water(Vector2i(7, 2))).is_false()

func test_tide_low_sand_cells_are_returned_as_vector2i() -> void:
	var cells := LevelMap.new(_def()).tide_low_sand_cells()
	assert_int(cells.size()).is_equal(2)
	assert_bool(cells[0] == Vector2i(7, 1)).is_true()

func test_build_slots_are_cell_centres() -> void:
	var slots := LevelMap.new(_def()).build_slot_positions()
	assert_int(slots.size()).is_equal(2)
	assert_float(slots[0].x).is_equal_approx(80.0, 0.001)
	assert_float(slots[0].y).is_equal_approx(16.0, 0.001)

func test_props_default_shadow_true() -> void:
	var props := LevelMap.new(_def()).props()
	assert_int(props.size()).is_equal(2)
	assert_bool(props[0]["shadow"]).is_true()
	assert_bool(props[1]["shadow"]).is_false()
	assert_str(props[1]["id"]).is_equal("prop_settlement")

func test_validate_passes_for_good_map() -> void:
	assert_array(LevelMap.new(_def()).validate()).is_empty()

func test_validate_rejects_prop_on_path() -> void:
	var d := _def()
	d["props"] = [{"id": "prop_banyan", "cell": [2, 2]}]
	var errors: Array[String] = LevelMap.new(d).validate()
	assert_int(errors.size()).is_equal(1)
	assert_str(errors[0]).contains("prop_banyan")

func test_validate_rejects_build_slot_on_path_and_waypoint_outside_grid() -> void:
	var d := _def()
	d["build_slots"] = [[3, 3]]
	d["path_waypoints"] = [[0, 2], [4, 2], [4, 4], [12, 4]]
	var errors: Array[String] = LevelMap.new(d).validate()
	assert_int(errors.size()).is_equal(2)
