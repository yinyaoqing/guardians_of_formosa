extends Node2D

## 「紙上的戲」風格實驗的示範場景。人工驗收用，不進自動化測試。
##
## 上排：目前 chapter01 的三個單位；下排：皮影實驗版；右側：兩者都以 1:1（128px）
## 放在地圖上，看戰場實際尺寸下的可讀性。整個畫面蓋一層 paper_ink.gdshader。
##
##   Space  切換 shader 開／關
##   Esc    離開
##
## 截圖模式（給 AI 協作或 CI 用，不開視窗互動）：
##   godot --path . res://game/fx/paper_ink_demo.tscn ++ --screenshot=C:/path/out.png
## 會渲染兩幀後把畫面存檔並結束；--screenshot-off=... 另存一張 shader 關閉的版本。

const SHADER := preload("res://game/fx/paper_ink.gdshader")
const MAP := "res://game/assets/chapter01/map_1_1.png"
const CURRENT := [
	"res://game/assets/chapter01/tower_hunter_t1.png",
	"res://game/assets/chapter01/enemy_musketeer.png",
	"res://game/assets/chapter01/enemy_ironman.png",
]
# 實驗產出在 art_src/（gitignore），沒有 .import，用 Image 直接讀檔。
const SHADOW := [
	"res://art_src/03_processed/xp_shadow_hunter.png",
	"res://art_src/03_processed/xp_shadow_musketeer.png",
	"res://art_src/03_processed/xp_shadow_ironman.png",
]
const LABELS := ["鏢手 tower_hunter_t1", "銃卒 enemy_musketeer", "鐵人 enemy_ironman"]
const FONT := "res://game/assets/fonts/TaipeiSansTCBeta-Regular.ttf"
const PAPER := Color("#E8DCC6")

# 兩層後處理：
#   layer 40  墨線 + 紙紋，只看得到地圖（單位還沒畫），地圖收成線稿
#   layer 50  單位——輪廓已由 postprocess.py 統一加好，不再吃 Sobel，
#             否則 128px 上量化出來的格紋每個像素邊都會被抓成墨線，鐵人糊成一團
#   layer 100 只有紙紋、不描邊，蓋在所有東西上讓單位也躺在紙上
#   layer 101 標籤，不進任何後處理
var _ink: ShaderMaterial
var _paper: ShaderMaterial
var _units: CanvasLayer
var _ui: CanvasLayer
var _enabled := true


func _ready() -> void:
	# 沒被地圖蓋到的地方也該是紙，不是引擎預設的灰
	RenderingServer.set_default_clear_color(PAPER)
	_units = CanvasLayer.new()
	_units.layer = 50
	add_child(_units)
	_ui = CanvasLayer.new()
	_ui.layer = 101
	add_child(_ui)
	_build_background()
	_build_rows()
	_build_overlay()
	_handle_cli()


func _build_background() -> void:
	var map := Sprite2D.new()
	map.texture = load(MAP)
	map.centered = false
	# 地圖貼片經 fit() 成 512×512，實際內容是置中的 16:9 帶，上下是透明邊。
	# 等比放大到 1920 寬，再把透明邊推到畫面外。
	var tex_w := float(map.texture.get_width())
	var tex_h := float(map.texture.get_height())
	var k := 1920.0 / tex_w
	var band := (tex_h - tex_w * 9.0 / 16.0) / 2.0
	map.scale = Vector2(k, k)
	map.position = Vector2(0.0, -band * k)
	add_child(map)


func _build_rows() -> void:
	# 左側兩排墊一塊紙色板，放大的細節才看得清；右側 1:1 直接放在地圖上
	_panel(Rect2(80, 30, 1240, 1020))
	# 上排：現況；下排：皮影。各以 3 倍放大好看細節。
	_row(CURRENT, 250, "現況（FLUX.2 平塗卡通）", true)
	_row(SHADOW, 770, "皮影實驗", false)
	# 右側：1:1 放在地圖上，模擬戰場尺寸
	var x := 1500
	for i in CURRENT.size():
		_sprite(CURRENT[i], true, Vector2(x + i * 130, 330), 1.0)
		_sprite(SHADOW[i], false, Vector2(x + i * 130, 780), 1.0)
	_label("1:1 戰場尺寸", Vector2(x - 20, 180))


func _row(paths: Array, y: int, title: String, imported: bool) -> void:
	_label(title, Vector2(100, y - 240))
	for i in paths.size():
		var x := 300 + i * 380
		_sprite(paths[i], imported, Vector2(x, y), 3.0)
		_label(LABELS[i], Vector2(x - 120, y + 200))


func _sprite(path: String, imported: bool, pos: Vector2, scale_factor: float) -> void:
	var tex: Texture2D
	if imported:
		tex = load(path)
	else:
		var abs_path := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(abs_path):
			_label("（尚未產出）", pos - Vector2(60, 0))
			return
		var img := Image.load_from_file(abs_path)
		tex = ImageTexture.create_from_image(img)
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.scale = Vector2.ONE * scale_factor
	# 放大看細節時用最近鄰，1:1 時用線性——跟戰場實際一致
	s.texture_filter = TEXTURE_FILTER_NEAREST if scale_factor > 1.0 else TEXTURE_FILTER_LINEAR
	_units.add_child(s)


func _panel(rect: Rect2) -> void:
	var r := ColorRect.new()
	r.color = Color(PAPER, 0.85)
	r.position = rect.position
	r.size = rect.size
	add_child(r)


func _label(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_override("font", load(FONT))
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color("#3A2A22"))
	l.add_theme_color_override("font_outline_color", Color("#E8DCC6"))
	l.add_theme_constant_override("outline_size", 6)
	_ui.add_child(l)


func _build_overlay() -> void:
	_ink = _overlay(40)
	_paper = _overlay(100)
	_paper.set_shader_parameter("ink_strength", 0.0)
	_paper.set_shader_parameter("paper_tint", 0.10)
	_paper.set_shader_parameter("vignette", 0.0)


func _overlay(layer_index: int) -> ShaderMaterial:
	var layer := CanvasLayer.new()
	layer.layer = layer_index
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)
	return mat


func _set_enabled(on: bool) -> void:
	_enabled = on
	_ink.set_shader_parameter("enabled", on)
	_paper.set_shader_parameter("enabled", on)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_set_enabled(not _enabled)
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()


func _handle_cli() -> void:
	var out := ""
	var out_off := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			out = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--screenshot-off="):
			out_off = arg.trim_prefix("--screenshot-off=")
	if out.is_empty() and out_off.is_empty():
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not out.is_empty():
		get_viewport().get_texture().get_image().save_png(out)
	if not out_off.is_empty():
		_set_enabled(false)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_off)
	get_tree().quit()
