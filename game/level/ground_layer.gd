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
