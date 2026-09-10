# M1-B6 關卡地圖改 TileMap — 實作計畫

> **2026-09-10 改號**：原編號 M1-B4 已由波次系統占用（`2026-09-06-m1b4-waves-design.md`，已在 main）。本文件改為 **M1-B6**。既有截圖檔名 `m1b4_*` 維持不變，那是實際存在的檔名。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 level_01 的地圖從一張 AI 整圖改成由 `data/levels/level_01/map.json` 驅動的 TileMap：同一份格座標折線同時產生敵人路徑（`PathData`）與路徑地磚，建塔點與擺件也由同一份資料指定。

**Architecture:** `core/spatial/level_map.gd`（RefCounted，純資料與座標換算）讀 `map.json`，提供路徑格集合、等距取樣點、水域格、潮汐差集、建塔點與擺件的像素座標；`game/level/ground_layer.gd`（TileMapLayer）與 `game/level/prop_layer.gd`（Node2D, y_sort）只負責把它畫出來。`battle_scene.gd` 不再讀場景裡的 `Path2D` 與 `Marker2D`，改由 `LevelMap` 烘焙。地磚由 `art/scripts/make_tiles.py` 程序化產生（色票內的平色），不用 AI。

**Tech Stack:** Godot 4.7 GDScript、GdUnit4、Python 3.12 + Pillow（地磚產生）

## Global Constraints

- `core/` 不得 import 任何 Node 或引擎場景類別（CLAUDE.md 硬規則 1；`tests/test_core_purity.gd` 自動驗證）。`LevelMap` 只用 `RefCounted`、`Vector2`、`Vector2i`、`PackedVector2Array`、`Dictionary`。
- 遊戲資料一律 JSON，置於 `data/`，不使用 `.tres`。TileSet 在執行期由圖集組成。
- 只用 GDScript；只用 Godot 4.x API。
- 邏輯 tick 固定 30Hz；本計畫不動 `BattleSim`。
- 地磚 **32px**（2026-09-09 決定）；路徑格 **素沙**（沙洲黃 `#C9A96B` 平色，不畫卵石）。
- 貼圖顏色只用 `data/art_palette.json` 的色票（`tests/test_art_palette.gd` 遞迴掃 `game/assets/`）；`game/assets/` 內單張 ≤ 128px 除非前綴另訂（`data/art_limits.json`）。
- 每個任務結束都要跑全套測試：`godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`（新增 PNG／CSV 後先 `godot --headless --path . --import`）。
- 視口 1920×1080（`project.godot`）；60×34 格 × 32px = 1920×1088，最後一列半格在畫面外，可接受。
- Commit 訊息結尾：`Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`。

---

## 檔案結構

| 檔案 | 責任 |
|---|---|
| `core/spatial/level_map.gd`（新） | `LevelMap`：解析 map.json、路徑格、取樣、水域、潮汐差集、建塔點、擺件、驗證 |
| `tests/core/test_level_map.gd`（新） | `LevelMap` 單元測試 |
| `data/levels/level_01/map.json`（新） | level_01 的地圖資料 |
| `core/data/data_registry.gd`（改） | `_load_level_dirs` 順帶讀 `map.json` 進 `levels[id]["map"]` |
| `tests/test_data_integrity.gd`（改） | 關卡地圖資料的閘門（路徑在格內、擺件與建塔點不落在路徑上、擺件貼圖存在） |
| `art/scripts/make_tiles.py`（改） | 路徑磚改素沙；輸出到 `game/assets/chapter01/tiles.png` 與 `shadow_ellipse.png` |
| `game/level/ground_layer.gd`（新） | `GroundLayer`：執行期組 TileSet、鋪地、潮汐換格 |
| `game/level/prop_layer.gd`（新） | `PropLayer`：擺件 + 接觸陰影，y_sort |
| `game/level/battle_scene.gd`、`battle_scene.tscn`（改） | 由 `LevelMap` 烘焙 `PathData` 與建塔點；掛 Ground／Props；移除 `Path2D` 與 `Marker2D` |
| `art/manifest/chapter01_assets.json`（改） | 新增四個擺件資產 |
| `game/fx/paper_overlay.gd`（新） | 兩層紙紋 shader（描邊只作用地圖、紙紋蓋全部） |
| `docs/superpowers/specs/2026-09-09-m1b6-tilemap-map-design.md`（改） | 狀態改「定案」、待決策填答案 |

---

### Task 1：`LevelMap` 核心類別

**Files:**
- Create: `core/spatial/level_map.gd`
- Test: `tests/core/test_level_map.gd`

**Interfaces:**
- Produces:
  - `LevelMap.new(def: Dictionary)`
  - `tile_px: int`、`cols: int`、`rows: int`
  - `path_cells() -> Dictionary`（`Vector2i -> true`）
  - `cell_center(cell: Vector2i) -> Vector2`
  - `sample_path(spacing: float) -> PackedVector2Array`（沿折線格中心等距取樣，含起點與終點）
  - `is_water(cell: Vector2i) -> bool`
  - `tide_low_sand_cells() -> Array[Vector2i]`（退潮時由水變沙的格子）
  - `build_slot_positions() -> Array[Vector2]`
  - `props() -> Array[Dictionary]`（每筆 `{id: String, cell: Vector2i, shadow: bool}`）
  - `validate() -> Array[String]`（空陣列＝合法；否則每筆一句錯誤）

- [ ] **Step 1：寫失敗的測試**

```gdscript
# tests/core/test_level_map.gd
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
```

- [ ] **Step 2：跑測試確認失敗**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_level_map.gd`
Expected: 解析錯誤 `Identifier "LevelMap" not declared`（class 尚未存在）。

- [ ] **Step 3：實作 `LevelMap`**

```gdscript
# core/spatial/level_map.gd
class_name LevelMap
extends RefCounted

## 關卡地圖的唯一真相（設計規格 2026-09-09-m1b6-tilemap-map-design.md §2）。
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
```

- [ ] **Step 4：跑測試確認通過**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/core/test_level_map.gd`
Expected: 11 tests passed。再跑全套確認 `test_core_purity` 仍綠（`LevelMap` 只 `extends RefCounted`）。

- [ ] **Step 5：Commit**

```bash
git add core/spatial/level_map.gd core/spatial/level_map.gd.uid tests/core/test_level_map.gd tests/core/test_level_map.gd.uid
git commit -m "feat(core): LevelMap——路徑折線同時產生 PathData 取樣點與路徑格

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2：level_01 的 `map.json`、註冊表載入與資料閘門

**Files:**
- Create: `data/levels/level_01/map.json`
- Modify: `core/data/data_registry.gd:57-70`（`_load_level_dirs`）
- Test: `tests/test_data_integrity.gd`（新增測試）

**Interfaces:**
- Consumes: `LevelMap.new(def)`、`LevelMap.validate()`、`LevelMap.props()`（Task 1）
- Produces: `DataRegistry.levels[level_id]["map"]: Dictionary`（沒有 map.json 的關卡沒有此鍵）

- [ ] **Step 1：寫失敗的測試**

在 `tests/test_data_integrity.gd` 的 `test_every_enemy_puppet_is_well_formed` 之後加入：

```gdscript
## 關卡地圖是路徑、地磚、建塔點、擺件的唯一真相；資料錯了不會在載入時報錯，
## 只會在關卡裡看到敵人穿過樹、塔蓋在路中間。這裡把它變成測試失敗。
func test_level_maps_are_valid() -> void:
	var checked := 0
	for level_id: StringName in _registry.levels:
		var meta: Dictionary = _registry.levels[level_id]
		if not meta.has("map"):
			continue
		checked += 1
		var map := LevelMap.new(meta["map"])
		var errors: Array[String] = map.validate()
		assert_array(errors).override_failure_message(
			"關卡 %s 的 map.json 不合法：%s" % [level_id, "; ".join(errors)]
		).is_empty()
		for prop: Dictionary in map.props():
			var path := "res://game/assets/chapter01/%s.png" % prop["id"]
			assert_bool(ResourceLoader.exists(path)).override_failure_message(
				"關卡 %s 的擺件 %s 沒有貼圖：%s" % [level_id, prop["id"], path]
			).is_true()
	assert_int(checked).override_failure_message(
		"沒有任何關卡帶 map.json，守衛形同虛設"
	).is_greater(0)
```

- [ ] **Step 2：跑測試確認失敗**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_data_integrity.gd`
Expected: `test_level_maps_are_valid` FAILED——「沒有任何關卡帶 map.json」。

- [ ] **Step 3：寫 `map.json`**

沿用現有 `battle_scene.tscn` 的路徑形狀（左上進、繞一個 U、沿下半橫貫到右邊）與四個建塔點的相對位置，換算成 32px 格座標。擺件先只放已有貼圖的 `prop_settlement`；四棵樹等 Task 7 出圖後再補。

```json
{
  "_doc": "level_01 地圖。tile_px 格邊長；path_waypoints 是路徑折線的格座標（左上為原點），path_width 為路徑寬（格）；water.rect 為 [x0, y0, x1, y1) 半開矩形；tide.low_extra_sand 為退潮時由水變沙的格子；props 的 cell 為擺件腳底所在格，shadow 預設 true；build_slots 為建塔點格。路徑與建塔點的像素座標都由 core/spatial/level_map.gd 算，不要在別處另寫一份。",
  "tile_px": 32,
  "cols": 60,
  "rows": 34,
  "path_waypoints": [[0, 4], [21, 4], [21, 7], [3, 7], [3, 18], [59, 18]],
  "path_width": 2,
  "water": {"rect": [46, 0, 60, 9]},
  "tide": {"low_extra_sand": [[46, 7], [47, 7], [46, 8], [47, 8], [48, 8], [49, 8]]},
  "props": [
    {"id": "prop_settlement", "cell": [40, 12], "shadow": false}
  ],
  "build_slots": [[12, 6], [12, 14], [28, 15], [44, 15]]
}
```

- [ ] **Step 4：註冊表順帶讀 map.json**

修改 `core/data/data_registry.gd` 的 `_load_level_dirs`，在 `result[StringName(meta["id"])] = meta` 之前加入：

```gdscript
		# 地圖是選配：沒有 map.json 的關卡仍可載入（M0 灰盒關卡就沒有）。
		# 有的話整份塞進 meta["map"]，由 LevelMap 解析；註冊表不解讀它的欄位。
		var map_path := dir_path.path_join(sub_dir).path_join("map.json")
		if FileAccess.file_exists(map_path):
			var map_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(map_path))
			assert(map_parsed is Dictionary, "JSON 格式錯誤: %s" % map_path)
			meta["map"] = map_parsed
```

- [ ] **Step 5：跑測試確認通過**

Run: 全套。Expected: `test_level_maps_are_valid` PASS；其餘不變（244 + 11 + 1）。

- [ ] **Step 6：Commit**

```bash
git add data/levels/level_01/map.json core/data/data_registry.gd tests/test_data_integrity.gd
git commit -m "feat(data): level_01 map.json 與載入；關卡地圖資料閘門

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3：地磚圖集進 `game/assets`

**Files:**
- Modify: `art/scripts/make_tiles.py`

**Interfaces:**
- Produces: `game/assets/chapter01/tiles.png`（128×96；列 0 草地 ×4、列 1 素沙 ×4、列 2 水 ×2，每格 32×32）、`game/assets/chapter01/shadow_ellipse.png`（24×10）

- [ ] **Step 1：改路徑磚為素沙、輸出到正式目錄**

把 `path()` 換成：

```python
def path(rng: random.Random) -> Image.Image:
    # 素沙（2026-09-09 決定）：沙洲黃平色，只撒極少量曝曬沙碎點打破重複感。
    # 路徑靠「沙洲黃 vs 翠綠」的色對比讀，不靠紋理——扁平幾何風格下紋理反而突兀。
    im = Image.new("RGBA", (TILE, TILE), P["sand"])
    d = ImageDraw.Draw(im)
    for _ in range(rng.randint(1, 3)):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        d.point((x, y), P["sun_sand"])
    return im
```

把 `OUT_DIR` 改為可由參數指定，預設進正式目錄：

```python
OUT_DIR = os.path.join(REPO, "game", "assets", "chapter01")
```

並在 `main()` 開頭加：

```python
    import argparse
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=OUT_DIR)
    args = ap.parse_args()
    out_dir = args.out
```

把 `main()` 內所有 `OUT_DIR` 改用 `out_dir`，輸出檔名改為 `tiles.png` 與 `shadow_ellipse.png`（去掉 `xp_` 前綴）。模組 docstring 的用法列同步改成 `python art/scripts/make_tiles.py`（正式）與 `--out art_src/03_processed_px`（實驗）。

- [ ] **Step 2：產生並匯入**

Run:
```bash
python art/scripts/make_tiles.py
godot --headless --path . --import
```
Expected: `game/assets/chapter01/tiles.png (128x96)`、`shadow_ellipse.png`，且各有 `.import`。

- [ ] **Step 3：跑全套測試**

Expected: 全綠。`test_art_palette` 掃到兩張新圖都在色票內（陰影橢圓是半透明焦茶，RGB 為 `(30,22,17)`——**若色票測試把它判為色票外，改用焦茶 `#3A2A22` 的 RGB 加 alpha 110**，不要放寬測試）。`test_art_limits` 對 `tiles.png` 用預設上限 128：128×96 合格。

- [ ] **Step 4：Commit**

```bash
git add art/scripts/make_tiles.py game/assets/chapter01/tiles.png game/assets/chapter01/tiles.png.import game/assets/chapter01/shadow_ellipse.png game/assets/chapter01/shadow_ellipse.png.import
git commit -m "feat(art): 地磚圖集（素沙路徑）與接觸陰影進 game/assets

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4：`GroundLayer`——執行期組 TileSet、鋪地、潮汐換格

**Files:**
- Create: `game/level/ground_layer.gd`

**Interfaces:**
- Consumes: `LevelMap.path_cells()`、`is_water()`、`tide_low_sand_cells()`、`cols`、`rows`、`tile_px`
- Produces:
  - `class_name GroundLayer extends TileMapLayer`
  - `setup(map: LevelMap, atlas: Texture2D, seed: int) -> void`
  - `set_tide_high(high: bool) -> void`（只 `set_cell` 潮汐差集）

UI／畫面不做自動化測試（CLAUDE.md），本任務以 Task 6 的截圖人工驗收。

- [ ] **Step 1：實作**

```gdscript
# game/level/ground_layer.gd
class_name GroundLayer
extends TileMapLayer

## 地面層。TileSet 在執行期由圖集組成（專案約定：資料一律 JSON，不進 .tres）。
## 鋪哪些格子完全由 LevelMap 決定；本類別只把格子畫出來。
##
## 圖集配置見 art/scripts/make_tiles.py：列 0 草地 ×4、列 1 素沙（路徑）×4、列 2 水 ×2。
## 潮汐（章節規格 1-1 機制）：漲潮／退潮只換 LevelMap.tide_low_sand_cells() 那幾格，
## 其餘畫面不重繪——這比色溫 shader 更直接，也解掉美術聖經 §6 第 4 項的待決策。

const GRASS := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
const SAND := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
const WATER := [Vector2i(0, 2), Vector2i(1, 2)]

var _map: LevelMap
var _source_id: int = -1
var _rng := RandomNumberGenerator.new()


func setup(map: LevelMap, atlas: Texture2D, seed: int = 1661) -> void:
	_map = map
	_rng.seed = seed
	var src := TileSetAtlasSource.new()
	src.texture = atlas
	src.texture_region_size = Vector2i(map.tile_px, map.tile_px)
	for coord in GRASS + SAND + WATER:
		src.create_tile(coord)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(map.tile_px, map.tile_px)
	_source_id = ts.add_source(src)
	tile_set = ts

	var path := map.path_cells()
	for y in map.rows:
		for x in map.cols:
			var c := Vector2i(x, y)
			var pool: Array = SAND if path.has(c) else (WATER if map.is_water(c) else GRASS)
			set_cell(c, _source_id, pool[_rng.randi_range(0, pool.size() - 1)])


## 漲潮＝潮間帶回到水；退潮＝潮間帶露出沙。只動差集。
func set_tide_high(high: bool) -> void:
	for c in _map.tide_low_sand_cells():
		var pool: Array = WATER if high else SAND
		set_cell(c, _source_id, pool[_rng.randi_range(0, pool.size() - 1)])
```

- [ ] **Step 2：語法檢查**

Run: `godot --headless --path . --check-only -s res://game/level/ground_layer.gd`
Expected: 無錯誤輸出（class 可被解析）。

- [ ] **Step 3：Commit**

```bash
git add game/level/ground_layer.gd game/level/ground_layer.gd.uid
git commit -m "feat(game): GroundLayer——由 LevelMap 鋪地磚，潮汐只換差集格

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5：`PropLayer`——擺件與 L1 接觸陰影

**Files:**
- Create: `game/level/prop_layer.gd`

**Interfaces:**
- Consumes: `LevelMap.props()`、`cell_center()`、`tile_px`
- Produces:
  - `class_name PropLayer extends Node2D`（`y_sort_enabled = true`）
  - `setup(map: LevelMap, asset_dir: String, shadow: Texture2D) -> void`

- [ ] **Step 1：實作**

```gdscript
# game/level/prop_layer.gd
class_name PropLayer
extends Node2D

## 擺件層：樹、聚落、礁石等由 map.json 指定格子，y_sort 讓站在後面的被前面的蓋住。
## 每個擺件底下一張共用的橢圓接觸陰影（精緻度規格 L1）——沒有它單位與擺件都像貼紙。
## 擺件貼圖來自 game/assets/chapter01/<id>.png，走 A4 管線，本層不處理美術。

var _shadow: Texture2D


func _ready() -> void:
	y_sort_enabled = true


func setup(map: LevelMap, asset_dir: String, shadow: Texture2D) -> void:
	_shadow = shadow
	for p in map.props():
		var tex: Texture2D = load(asset_dir.path_join("%s.png" % p["id"]))
		var foot := map.cell_center(p["cell"]) + Vector2(0, map.tile_px * 0.5)
		if p["shadow"]:
			_add_shadow(foot, tex.get_width() * 0.9)
		var s := Sprite2D.new()
		s.texture = tex
		s.position = foot
		s.offset = Vector2(0, -tex.get_height() * 0.5)
		add_child(s)


func _add_shadow(foot: Vector2, width: float) -> void:
	var s := Sprite2D.new()
	s.texture = _shadow
	s.position = foot
	s.scale = Vector2.ONE * (width / _shadow.get_width())
	s.z_index = -1
	add_child(s)
```

- [ ] **Step 2：語法檢查**

Run: `godot --headless --path . --check-only -s res://game/level/prop_layer.gd`
Expected: 無錯誤。

- [ ] **Step 3：Commit**

```bash
git add game/level/prop_layer.gd game/level/prop_layer.gd.uid
git commit -m "feat(game): PropLayer——擺件 + L1 接觸陰影，y_sort

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6：`BattleScene` 改由 `LevelMap` 烘焙路徑與建塔點，掛地面與擺件

**Files:**
- Modify: `game/level/battle_scene.gd`（`_ready`、`_bake_path`、`_bake_build_slots`、常數）
- Modify: `game/level/battle_scene.tscn`（移除 `MainPath`、`BuildSlots`）

**Interfaces:**
- Consumes: `LevelMap`（Task 1）、`registry.levels[LEVEL_ID]["map"]`（Task 2）、`GroundLayer.setup/set_tide_high`（Task 4）、`PropLayer.setup`（Task 5）、`tiles.png`／`shadow_ellipse.png`（Task 3）
- Produces: 場景不再依賴 `Path2D`／`Marker2D`；`PathData` 取樣間距仍為 `PATH_SAMPLE_SPACING = 8.0`

- [ ] **Step 1：改 `battle_scene.tscn`**

整份改為（只留 Views；地面與擺件由程式建立在 CanvasLayer -10）：

```
[gd_scene load_steps=2 format=3 uid="uid://c4hxr1a8w2qfn"]

[ext_resource type="Script" path="res://game/level/battle_scene.gd" id="1_bscn0"]

[node name="BattleScene" type="Node2D"]
script = ExtResource("1_bscn0")

[node name="Views" type="Node2D" parent="."]
```

- [ ] **Step 2：改 `battle_scene.gd`**

常數區新增，並刪除 `@onready var _path_node` 與 `@onready var _build_slots_root`：

```gdscript
const TILES_ATLAS := "res://game/assets/chapter01/tiles.png"
const SHADOW_ELLIPSE := "res://game/assets/chapter01/shadow_ellipse.png"
const PROP_ASSET_DIR := "res://game/assets/chapter01"

var _level_map: LevelMap
var _ground: GroundLayer
var _props: PropLayer
```

`_ready()` 開頭改為：

```gdscript
func _ready() -> void:
	_registry.load_from_disk()

	var meta: Dictionary = _registry.levels[LEVEL_ID]
	assert(meta.has("map"), "關卡 %s 沒有 map.json" % LEVEL_ID)
	_level_map = LevelMap.new(meta["map"])

	# 地面與擺件放在 CanvasLayer -10：一定在單位（根層，layer 0）之下，
	# 而且 Task 8 的描邊 pass（layer -5）只看得到它們、看不到單位。
	var ground_layers := CanvasLayer.new()
	ground_layers.name = "GroundLayers"
	ground_layers.layer = -10
	add_child(ground_layers)
	_ground = GroundLayer.new()
	_ground.setup(_level_map, load(TILES_ATLAS))
	ground_layers.add_child(_ground)
	_props = PropLayer.new()
	_props.setup(_level_map, PROP_ASSET_DIR, load(SHADOW_ELLIPSE))
	ground_layers.add_child(_props)

	var world := WorldState.new()
	world.configure_for_level(_registry, LEVEL_ID)
	world.paths[MAIN_PATH_ID] = PathData.new(_level_map.sample_path(PATH_SAMPLE_SPACING), PATH_SAMPLE_SPACING)

	_sim = BattleSim.new(world)
	_bake_build_slots(world)
	InputBindings.install()
	# …以下（HUD、選單、範圍圈）不變
```

刪除 `_bake_path()`；`_bake_build_slots()` 改為：

```gdscript
## 建塔點由 map.json 指定格子，LevelMap 換算成像素座標交給 core/。
## core/ 不認得格子與貼圖，與 LevelMap → PathData 是同一個分層邊界。
func _bake_build_slots(world: WorldState) -> void:
	for pos in _level_map.build_slot_positions():
		var slot := BuildSlot.new()
		slot.position = pos
		world.add_build_slot(slot)

		var view := BuildSlotViewScript.new() as BuildSlotView
		view.setup(slot.id, SLOT_SPRITE, slot.position)
		_view_root.add_child(view)
		_slot_views[slot.id] = view
```

檔頭註解第 1 點改為「從 `map.json` 的折線等距取樣出 `PathData`（core/ 不接觸 Curve2D，也不再需要 Path2D）」。

- [ ] **Step 3：跑全套測試**

Run: 全套。Expected: 全綠——`test_core_purity` 的兩個 battle_scene 源碼檢查（`configure_for_level`、`InputBindings.install`）仍成立。

- [ ] **Step 4：截圖人工驗收**

Run:
```bash
godot --path . -s res://game/fx/screenshot_battle.gd -- --out="C:/Users/yinya/git/guardians_of_formosa/art_src/contact/m1b4_tilemap_battle.png" --seconds=8
```
Expected（人眼）：翠綠地面、沙洲黃路徑自左上進、繞 U、沿下半橫貫；右上角一片台江靛水域；四個建塔點都在草地上；銃卒沿路徑走且腳在路徑格內；聚落擺件有陰影且不壓在路徑上。
再把畫面縮到 1/4 看：路徑走向仍一眼可辨（規格驗收 1）。

- [ ] **Step 5：驗收 2——改一個 waypoint 兩邊同時變**

暫時把 `map.json` 的 `[21, 4]` 改成 `[30, 4]`，重截圖：路徑地磚與敵人行走路線同時延長到第 30 欄。確認後改回。

- [ ] **Step 6：Commit**

```bash
git add game/level/battle_scene.gd game/level/battle_scene.tscn
git commit -m "feat(game): 戰場改由 LevelMap 烘焙路徑與建塔點，掛 GroundLayer 與 PropLayer；移除 Path2D／Marker2D

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7：擺件資產（扁平風格）進清單、出圖、挑選、入庫

**Files:**
- Modify: `art/manifest/chapter01_assets.json`（`assets` 陣列新增四筆）
- Modify: `data/levels/level_01/map.json`（`props` 補樹與礁石）
- Create（由管線產生）: `game/assets/chapter01/prop_banyan.png`、`prop_bamboo.png`、`prop_rock.png`、`prop_pandanus.png`

**Interfaces:**
- Consumes: `generate_batch.py --stage flat`、`select_masters.py`、`postprocess.py`（既有）
- Produces: 四張 ≤128px 擺件貼圖；`master_set.json` 多四筆

- [ ] **Step 1：清單新增四個擺件**

在 `chapter01_assets.json` 的 `assets` 陣列（`prop_settlement` 之後）加入：

```json
{
  "id": "prop_banyan", "cat": "prop", "fac": "none", "name": "擺件：榕樹",
  "subject": "a single banyan tree of tropical Formosa, a broad dense rounded canopy of deep green built from a few large flat facets, a short thick terracotta-brown trunk with two or three hanging aerial roots, the canopy clearly wider than the trunk.",
  "_silhouette_intent": "寬圓冠 + 短粗幹；重複擺放用，冠要圓、輪廓要單純"
},
{
  "id": "prop_bamboo", "cat": "prop", "fac": "none", "name": "擺件：竹叢",
  "subject": "a clump of five or six tall bamboo stalks in flat jade green with darker joint bands, leaning slightly apart at the top with a few simple leaf shapes, growing from a single point at the base.",
  "_silhouette_intent": "細高、多桿、頂部散開"
},
{
  "id": "prop_rock", "cat": "prop", "fac": "none", "name": "擺件：礁石",
  "subject": "a low rounded coastal boulder of the Taijiang lagoon in flat sand and light grey-brown facets with a darker underside, a little dry grass at its base.",
  "_silhouette_intent": "低矮圓塊，比人矮"
},
{
  "id": "prop_pandanus", "cat": "prop", "fac": "none", "name": "擺件：林投",
  "subject": "a single pandanus (screw pine) of the Taiwan coast: a short stilt-rooted trunk and a crown of long stiff spiky blade-like leaves radiating outward in flat jade and deep green facets.",
  "_silhouette_intent": "放射狀尖葉冠，與榕樹的圓冠拉開"
}
```

- [ ] **Step 2：出圖**

Run:
```bash
python art/scripts/generate_batch.py --stage flat --cat prop --batch 4 --only prop_banyan --only prop_bamboo --only prop_rock --only prop_pandanus
python art/scripts/select_masters.py --sheets --stage flat --only prop_banyan --only prop_bamboo --only prop_rock --only prop_pandanus
```
Expected: `art_src/candidates/prop_*_flat.png` 四張帶編號印樣。

- [ ] **Step 3：人工挑選（必須由人做）**

看印樣後執行，例如：
```bash
python art/scripts/select_masters.py --pick prop_banyan=2
python art/scripts/select_masters.py --pick prop_bamboo=1
python art/scripts/select_masters.py --pick prop_rock=3
python art/scripts/select_masters.py --pick prop_pandanus=1
```
判準：輪廓單純（重複擺 30 次不會亂）、底部有清楚的「腳」（接觸陰影要放的位置）、色域在色票內。

- [ ] **Step 4：過管線、只搬清單內的檔**

Run:
```bash
python art/scripts/postprocess.py --stage flat --outline-width 1 --only prop_banyan --only prop_bamboo --only prop_rock --only prop_pandanus
python - <<'EOF'
import shutil
for n in ("prop_banyan", "prop_bamboo", "prop_rock", "prop_pandanus"):
    shutil.copyfile(f"art_src/03_processed/{n}.png", f"game/assets/chapter01/{n}.png")
EOF
godot --headless --path . --import
```
（不要 `cp *.png`——`03_processed/` 混有實驗檔，A2 第二批踩過。）

- [ ] **Step 5：補 `map.json` 的擺件**

把 `props` 改為（全部在草地上、不壓路徑與建塔點；`validate()` 會擋）：

```json
  "props": [
    {"id": "prop_settlement", "cell": [40, 12], "shadow": false},
    {"id": "prop_banyan", "cell": [5, 1]}, {"id": "prop_banyan", "cell": [30, 1]},
    {"id": "prop_banyan", "cell": [8, 24]}, {"id": "prop_banyan", "cell": [26, 26]},
    {"id": "prop_banyan", "cell": [50, 28]}, {"id": "prop_banyan", "cell": [36, 9]},
    {"id": "prop_bamboo", "cell": [15, 11]}, {"id": "prop_bamboo", "cell": [52, 13]},
    {"id": "prop_bamboo", "cell": [2, 30]},
    {"id": "prop_rock", "cell": [44, 10]}, {"id": "prop_rock", "cell": [55, 11]},
    {"id": "prop_pandanus", "cell": [48, 12]}, {"id": "prop_pandanus", "cell": [58, 26]}
  ],
```

- [ ] **Step 6：跑全套測試 + 截圖**

Run: 全套（`test_level_maps_are_valid` 會驗擺件貼圖存在與不壓路徑）；再截一張 `art_src/contact/m1b4_tilemap_props.png` 人眼確認密度與陰影。

- [ ] **Step 7：Commit**

```bash
git add art/manifest/chapter01_assets.json art/manifest/master_set.json data/levels/level_01/map.json game/assets/chapter01/prop_banyan.png* game/assets/chapter01/prop_bamboo.png* game/assets/chapter01/prop_rock.png* game/assets/chapter01/prop_pandanus.png*
git commit -m "feat(art): 四個扁平風格擺件進清單與 game/assets；level_01 地圖擺件

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8：紙紋 shader 接進戰場（兩層）

**Files:**
- Create: `game/fx/paper_overlay.gd`
- Modify: `game/level/battle_scene.gd`（`_ready` 在加入 HUD **之前**加一行）

**Interfaces:**
- Consumes: `res://game/fx/paper_ink.gdshader`（既有；uniform：`enabled`、`ink_strength`、`paper_tint`、`vignette`）；Task 6 的 `GroundLayers`（CanvasLayer -10）
- Produces: `class_name PaperOverlay extends Node`，`static func attach(host: Node) -> PaperOverlay`；`set_enabled(on: bool)`

A2x §2.4 的結論：描邊只作用在地圖（單位輪廓已由管線加好），紙紋蓋全部。層序：

```
CanvasLayer -10  GroundLayers（Task 6）：地磚 + 擺件
CanvasLayer  -5  描邊 + 紙紋 pass —— screen texture 此時只畫了地圖
根層（0）        Views：單位、塔、投射物、建塔點（不動）
CanvasLayer   1  純紙紋 pass —— 與 HUD、BuildMenu 同為 layer 1，但**先加入**，故畫在它們底下
CanvasLayer   1  BattleHud、BuildMenu（既有，後加入，畫在紙紋之上，可點）
```

- [ ] **Step 1：實作**

```gdscript
# game/fx/paper_overlay.gd
class_name PaperOverlay
extends Node

## 「紙上的戲」兩層後處理（A2x §2.4）：
##   layer -5  描邊 + 紙紋——此時 screen texture 只畫了 GroundLayers（-10），地圖收成線稿
##   layer  1  只有紙紋——蓋住單位讓它們也躺在紙上；與 HUD 同層但先加入，HUD 仍在最上
## 單位在根層（0），輪廓已由 postprocess.py 加好，不再吃 Sobel。
## M2 要量它在中階 Android 的幀率；ENABLED 是總開關。

const SHADER := preload("res://game/fx/paper_ink.gdshader")
const ENABLED := true

var _ink: ShaderMaterial
var _paper: ShaderMaterial


## 必須在 HUD／BuildMenu 加入 host 之前呼叫，否則紙紋會蓋在 UI 上。
static func attach(host: Node) -> PaperOverlay:
	var o := PaperOverlay.new()
	o.name = "PaperOverlay"
	host.add_child(o)
	o._ink = o._layer(-5, false)
	o._paper = o._layer(1, true)
	o.set_enabled(ENABLED)
	return o


func _layer(index: int, paper_only: bool) -> ShaderMaterial:
	var layer := CanvasLayer.new()
	layer.layer = index
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	if paper_only:
		mat.set_shader_parameter("ink_strength", 0.0)
		mat.set_shader_parameter("paper_tint", 0.10)
		mat.set_shader_parameter("vignette", 0.0)
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)
	return mat


func set_enabled(on: bool) -> void:
	_ink.set_shader_parameter("enabled", on)
	_paper.set_shader_parameter("enabled", on)
```

- [ ] **Step 2：戰場掛上去**

`battle_scene.gd` 的 `_ready()`，在 `_hud = BattleHudScene.instantiate() as BattleHud` **之前**加：

```gdscript
	# 紙紋 pass 與 HUD 同在 CanvasLayer 1，靠加入順序決定上下：這行必須在 HUD 之前。
	PaperOverlay.attach(self)
```

- [ ] **Step 3：語法檢查、跑全套測試、截圖比對**

Run: `godot --headless --path . --check-only -s res://game/fx/paper_overlay.gd`；全套測試；截 `art_src/contact/m1b4_paper_on.png`。把 `PaperOverlay.ENABLED` 暫改 `false` 截 `m1b4_paper_off.png` 後改回。
Expected（人眼）：開啟時地圖有墨線與紙紋、單位輪廓不變粗（沒有被 Sobel 二次描邊）；HUD 與建塔選單仍在最上層且可點（用滑鼠點一個建塔點，選單要出現）。

- [ ] **Step 4：Commit**

```bash
git add game/fx/paper_overlay.gd game/fx/paper_overlay.gd.uid game/level/battle_scene.gd
git commit -m "feat(fx): 紙紋 shader 兩層接進戰場——描邊 pass 在地圖層之上、單位之下

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9：規格與紀錄收尾

**Files:**
- Modify: `docs/superpowers/specs/2026-09-09-m1b6-tilemap-map-design.md`
- Modify: `docs/superpowers/specs/2026-09-04-art-direction-bible.md`（§6 第 4 項）
- Modify: `docs/art/roadmap-2026-09-09.md`（§3 打勾）

- [ ] **Step 1：規格改定案**

`2026-09-09-m1b6-tilemap-map-design.md`：狀態列改「**定案**（2026-09-09）」；§6 待決策改為「已定：磚 32px；路徑格素沙（沙洲黃平色）。理由：扁平幾何風格下靠色對比讀路徑，紋理反而突兀」。§2 的資料範例換成 Task 2 實際的 `map.json` 內容。

- [ ] **Step 2：美術聖經 §6 第 4 項**

把「1-1 的潮汐色溫位移要做成即時 shader 還是兩套貼圖」改為：

```
4. ~~1-1 的潮汐色溫位移要做成即時 shader 還是兩套貼圖。~~ **2026-09-09 解掉，兩者都不用。** 地圖改為 TileMap 後，潮位變化＝換 `map.json` 指定的潮間帶格子（`GroundLayer.set_tide_high`），只重繪那幾格，沒有 shader 幀率成本，也沒有雙貼圖記憶體。全場景色溫位移若日後仍要，用 `paper_overlay` 的 `paper_tint` 參數即可。
```

- [ ] **Step 3：Roadmap §3 打勾並記截圖路徑**

在 `roadmap-2026-09-09.md` §3 標題後加一行：`**2026-09-09 完成**：截圖 art_src/contact/m1b4_tilemap_props.png、m1b4_paper_on.png；`map_1_1`、`map_tile_*` 三張整圖退役（留在 game/assets 作過場背景備用）`。

- [ ] **Step 4：Commit**

```bash
git add docs/superpowers/specs/2026-09-09-m1b6-tilemap-map-design.md docs/superpowers/specs/2026-09-04-art-direction-bible.md docs/art/roadmap-2026-09-09.md
git commit -m "docs: TileMap 規格定案；美術聖經 §6 潮汐待決策解掉；roadmap §3 完成

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## 自我檢查

- **規格覆蓋**：§1「做」的六項——地面層（T4）、路徑資料驅動（T1/T6）、擺件層 + 陰影（T5/T7）、建塔點由資料指定（T6）、潮汐換格（T1/T4，`set_tide_high` 已可呼叫，接 UI 留給潮汐機制的子里程碑）、紙紋 shader（T8）。§1「不做」的三項未實作。§4 驗收：1、2 在 T6；3 靠 `set_tide_high` 只動差集（T4）；4 在 T2 的 `test_level_maps_are_valid`；5 全套測試 + `tests/core/test_level_map.gd`（規格寫 `tests/test_level_map.gd`，本計畫放在 `tests/core/` 與其他 core 測試同目錄）。
- **型別一致**：`LevelMap.sample_path(spacing) -> PackedVector2Array` 餵 `PathData.new(points, spacing)`（T1/T6）；`build_slot_positions() -> Array[Vector2]`（T1/T6）；`props() -> Array[Dictionary]` 的鍵 `id/cell/shadow`（T1/T5/T2 測試）；`GroundLayer.setup(map, atlas, seed)`、`PropLayer.setup(map, asset_dir, shadow)`（T4/T5/T6）。
- **未定事項**：T3 陰影橢圓若被色票測試判為色票外，處置已寫在步驟內（改焦茶 + alpha），不放寬測試。T8 不搬 Views：描邊 pass 放在 GroundLayers（-10）與根層之間的 -5，紙紋 pass 與 HUD 同層（1）但先加入。HUD 是否仍可點是 T8 Step 3 的驗收項。
