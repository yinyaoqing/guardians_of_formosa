class_name LevelMap
extends RefCounted

## 關卡地圖的唯一真相（設計規格 2026-09-09-m1b4-tilemap-map-design.md §2）。
## 路徑折線同時產生敵人路徑（sample_path → PathData）與路徑地磚（path_cells），
## 兩者不可能漂開。core/ 只做資料與座標換算，不碰 TileMapLayer。

var tile_px: int
var cols: int
var rows: int
var _waypoints: Array[Vector2i] = []
var _path_width: int
var _water_rect: Rect2i
var _tide_low_sand: Array[Vector2i] = []
var _build_slots: Array[Vector2i] = []
var _props: Array[Dictionary] = []
var _path_cells_cache: Dictionary = {}


func _init(def: Dictionary) -> void:
	tile_px = int(def.get("tile_px", 32))
	cols = int(def["cols"])
	rows = int(def["rows"])
	for wp in def["path_waypoints"]:
		_waypoints.append(Vector2i(int(wp[0]), int(wp[1])))
	_path_width = int(def.get("path_width", 2))
	var water: Dictionary = def.get("water", {})
	if water.has("rect"):
		var r: Array = water["rect"]
		_water_rect = Rect2i(int(r[0]), int(r[1]), int(r[2]) - int(r[0]), int(r[3]) - int(r[1]))
	var tide: Dictionary = def.get("tide", {})
	for c in tide.get("low_extra_sand", []):
		_tide_low_sand.append(Vector2i(int(c[0]), int(c[1])))
	for s in def.get("build_slots", []):
		_build_slots.append(Vector2i(int(s[0]), int(s[1])))
	for p in def.get("props", []):
		_props.append({
			"id": String(p["id"]),
			"cell": Vector2i(int(p["cell"][0]), int(p["cell"][1])),
			"shadow": bool(p.get("shadow", true)),
		})


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * float(tile_px) + Vector2(tile_px, tile_px) * 0.5


## 折線經過的格子，寬 path_width：水平段往下加列、垂直段往右加欄，轉角補成方塊。
func path_cells() -> Dictionary:
	if not _path_cells_cache.is_empty():
		return _path_cells_cache
	var cells := {}
	for i in _waypoints.size() - 1:
		var a := _waypoints[i]
		var b := _waypoints[i + 1]
		var step := (b - a).sign()
		var c := a
		while true:
			for k in _path_width:
				cells[c + (Vector2i(0, k) if step.y == 0 else Vector2i(k, 0))] = true
			if c == b:
				break
			c += step
	for i in range(1, _waypoints.size() - 1):
		for dx in _path_width:
			for dy in _path_width:
				cells[_waypoints[i] + Vector2i(dx, dy)] = true
	_path_cells_cache = cells
	return cells


## 沿折線（格中心連線）等距取樣，給 PathData 用。最後一點永遠是終點中心。
func sample_path(spacing: float) -> PackedVector2Array:
	assert(spacing > 0.0, "取樣間距必須為正數")
	var centres: Array[Vector2] = []
	for wp in _waypoints:
		centres.append(cell_center(wp))
	var points := PackedVector2Array()
	var carry := 0.0
	points.append(centres[0])
	for i in centres.size() - 1:
		var a := centres[i]
		var b := centres[i + 1]
		var seg := a.distance_to(b)
		var d := spacing - carry
		while d <= seg:
			points.append(a.lerp(b, d / seg))
			d += spacing
		carry = seg - (d - spacing)
	if points[points.size() - 1] != centres[centres.size() - 1]:
		points.append(centres[centres.size() - 1])
	return points


func is_water(cell: Vector2i) -> bool:
	return _water_rect.has_area() and _water_rect.has_point(cell)


func tide_low_sand_cells() -> Array[Vector2i]:
	return _tide_low_sand.duplicate()


func build_slot_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for s in _build_slots:
		out.append(cell_center(s))
	return out


func props() -> Array[Dictionary]:
	return _props.duplicate(true)


func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows


## 資料閘門：路徑在格內、建塔點與擺件不落在路徑上。回傳錯誤訊息，空陣列即合法。
func validate() -> Array[String]:
	var errors: Array[String] = []
	for wp in _waypoints:
		if not _in_grid(wp):
			errors.append("路徑點 %s 超出 %dx%d 的格子" % [wp, cols, rows])
	var cells := path_cells()
	for s in _build_slots:
		if cells.has(s):
			errors.append("建塔點 %s 落在路徑上" % s)
	for p in _props:
		if cells.has(p["cell"]):
			errors.append("擺件 %s 落在路徑格 %s 上" % [p["id"], p["cell"]])
		if _build_slots.has(p["cell"]):
			errors.append("擺件 %s 與建塔點 %s 重疊" % [p["id"], p["cell"]])
	return errors
