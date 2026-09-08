extends Node2D

## 像素呈現 + TileMap 可讀性實驗。人工驗收用，不進自動化測試。
##
## 兩個問題一起回答：
##   ① 同一批資產縮到 64px、最近鄰放大 2 倍、視口 960×540，看起來如何
##   ② 地圖從「一張 AI 整圖」改成「平色地磚 + 高對比路徑 + 擺件」，可讀性差多少
##
## 結構：SubViewportContainer(1920×1080, shrink 2) > SubViewport(960×540, NEAREST)
##       > World(y_sort) > TileMapLayer + 擺件 + 單位（每個單位底下一個接觸陰影，L1）
##       最上層一個只有紙紋的 paper_ink 覆蓋（Space 切換）
##
## 截圖：godot --path . res://game/fx/pixel_demo.tscn ++ --screenshot=out.png

const TILE := 32
const COLS := 30
const ROWS := 17
const PX := "res://art_src/03_processed_px/"
const SHADER := preload("res://game/fx/paper_ink.gdshader")
const FONT := "res://game/assets/fonts/TaipeiSansTCBeta-Regular.ttf"
const PAPER := Color("#E8DCC6")

# 圖集座標（見 art/scripts/make_tiles.py）
const GRASS := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
const PATH := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
const WATER := [Vector2i(0, 2), Vector2i(1, 2)]

# 路徑折線（格座標），寬 2 格
const WAYPOINTS := [
	Vector2i(0, 8), Vector2i(9, 8), Vector2i(9, 3), Vector2i(17, 3),
	Vector2i(17, 11), Vector2i(29, 11),
]

var _world: Node2D
var _paper: ShaderMaterial
var _paper_on := true
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	RenderingServer.set_default_clear_color(PAPER)
	_rng.seed = 1661
	_build_viewport()
	_build_map()
	_build_props()
	_build_units()
	_build_paper()
	_handle_cli()


func _build_viewport() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = 2
	container.size = Vector2(1920, 1080)
	container.texture_filter = TEXTURE_FILTER_NEAREST
	var vp := SubViewport.new()
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.snap_2d_transforms_to_pixel = true
	_world = Node2D.new()
	_world.y_sort_enabled = true
	vp.add_child(_world)
	container.add_child(vp)
	add_child(container)


func _path_cells() -> Dictionary:
	var cells := {}
	for i in WAYPOINTS.size() - 1:
		var a: Vector2i = WAYPOINTS[i]
		var b: Vector2i = WAYPOINTS[i + 1]
		var step := (b - a).sign()
		var c := a
		while true:
			cells[c] = true
			# 寬 2 格：水平段往下多一格，垂直段往右多一格
			cells[c + (Vector2i(0, 1) if step.y == 0 else Vector2i(1, 0))] = true
			if c == b:
				break
			c += step
	# 轉角補齊成方塊，免得出現一格缺口
	for i in range(1, WAYPOINTS.size() - 1):
		var w: Vector2i = WAYPOINTS[i]
		for dx in 2:
			for dy in 2:
				cells[w + Vector2i(dx, dy)] = true
	return cells


func _is_water(c: Vector2i) -> bool:
	# 右上角一片潟湖，邊緣略帶弧度
	return c.x >= 22 and c.y <= 5 and (c.x - 22) + (5 - c.y) >= 4


func _build_map() -> void:
	var tex := _tex("xp_tiles.png")
	if tex == null:
		return
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE, TILE)
	for coord in GRASS + PATH + WATER:
		src.create_tile(coord)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var sid := ts.add_source(src)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	layer.z_index = -1
	var path := _path_cells()
	for y in ROWS:
		for x in COLS:
			var c := Vector2i(x, y)
			var pool: Array = PATH if path.has(c) else (WATER if _is_water(c) else GRASS)
			layer.set_cell(c, sid, pool[_rng.randi_range(0, pool.size() - 1)])
	_world.add_child(layer)


func _build_props() -> void:
	# 擺件放在草地上，沿路徑兩側加密——參考圖的密度感來自重複擺件，不是貼圖細節
	var trees := [
		Vector2i(2, 2), Vector2i(5, 1), Vector2i(3, 5), Vector2i(6, 11), Vector2i(2, 13),
		Vector2i(12, 7), Vector2i(14, 13), Vector2i(21, 8), Vector2i(26, 14), Vector2i(23, 12),
		Vector2i(13, 1), Vector2i(20, 15), Vector2i(7, 15), Vector2i(27, 8),
	]
	for t in trees:
		_prop("xp_prop_banyan.png", t, Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-4, 4)))
	for b in [Vector2i(7, 3), Vector2i(12, 14), Vector2i(24, 9), Vector2i(1, 11)]:
		_prop("xp_prop_bamboo.png", b)
	for r in [Vector2i(20, 2), Vector2i(21, 5), Vector2i(25, 7), Vector2i(11, 12)]:
		_prop("xp_prop_rock.png", r)
	for p in [Vector2i(28, 7), Vector2i(19, 0), Vector2i(23, 6)]:
		_prop("xp_prop_palm.png", p)
	_prop("prop_settlement.png", Vector2i(4, 8), Vector2.ZERO, false)
	_prop("prop_buildsite.png", Vector2i(12, 10))
	_prop("prop_buildsite.png", Vector2i(20, 8))
	_prop("tower_fence_t1.png", Vector2i(15, 6))


func _build_units() -> void:
	# 現況版走左半段，皮影版走右半段；各自沿路徑排開
	var current := ["tower_hunter_t1.png", "enemy_musketeer.png", "enemy_ironman.png"]
	var shadow := ["xp_shadow_hunter.png", "xp_shadow_musketeer.png", "xp_shadow_ironman.png"]
	var left := [Vector2(2.5, 9), Vector2(5.5, 9), Vector2(8, 9), Vector2(10, 6.5), Vector2(10, 4.5)]
	var right := [Vector2(14, 4), Vector2(18, 6), Vector2(18, 9), Vector2(21, 12), Vector2(25, 12)]
	for i in left.size():
		_unit(current[i % 3], left[i])
	for i in right.size():
		_unit(shadow[i % 3], right[i])
	_label("← 現況 64px", Vector2(60, 660))
	_label("皮影 64px →", Vector2(1500, 900))


func _tex(name: String) -> Texture2D:
	var abs_path := ProjectSettings.globalize_path(PX + name)
	if not FileAccess.file_exists(abs_path):
		return null
	return ImageTexture.create_from_image(Image.load_from_file(abs_path))


func _prop(name: String, cell: Vector2i, jitter: Vector2 = Vector2.ZERO, shadow: bool = true) -> void:
	var tex := _tex(name)
	if tex == null:
		return
	var pos := Vector2(cell) * TILE + Vector2(TILE / 2.0, TILE) + jitter
	if shadow:
		_shadow(pos, tex.get_width() * 0.9)
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.offset = Vector2(0, -tex.get_height() / 2.0)
	_world.add_child(s)


func _unit(name: String, cell: Vector2) -> void:
	var tex := _tex(name)
	if tex == null:
		return
	var pos := cell * TILE + Vector2(TILE / 2.0, TILE / 2.0)
	_shadow(pos, 28)
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.offset = Vector2(0, -tex.get_height() / 2.0 + 4)
	_world.add_child(s)


func _shadow(pos: Vector2, width: float) -> void:
	# 精緻度規格 L1：接觸陰影是共用的橢圓貼圖，不烘進資產
	var tex := _tex("xp_shadow_ellipse.png")
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.scale = Vector2.ONE * (width / tex.get_width())
	s.z_index = -1
	_world.add_child(s)


func _label(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_override("font", load(FONT))
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color("#3A2A22"))
	l.add_theme_color_override("font_outline_color", PAPER)
	l.add_theme_constant_override("outline_size", 6)
	var layer := CanvasLayer.new()
	layer.layer = 101
	layer.add_child(l)
	add_child(layer)


func _build_paper() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper = ShaderMaterial.new()
	_paper.shader = SHADER
	_paper.set_shader_parameter("ink_strength", 0.0)
	_paper.set_shader_parameter("paper_tint", 0.10)
	_paper.set_shader_parameter("vignette", 0.15)
	rect.material = _paper
	layer.add_child(rect)
	add_child(layer)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_paper_on = not _paper_on
			_paper.set_shader_parameter("enabled", _paper_on)
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()


func _handle_cli() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			out = arg.trim_prefix("--screenshot=")
	if out.is_empty():
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
