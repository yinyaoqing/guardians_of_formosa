extends Node2D

## 行走循環實驗：逐格（AI 幀）vs 分件（皮影拆件 + 程式擺動）。人工驗收用。
##
## 每列一種做法，同一個單位（鄭軍銃卒），循環 4 幀 / 0.5 秒：
##   A  逐格・扁平幾何   AI 用 Klein 參考圖編輯產的 4 幀，128px
##   B  逐格・同上 48px  同一批幀縮到 48px、最近鄰放大——「像素藏瑕疵」的驗證
##   C  逐格・皮影       AI 幀，128px
##   D  分件・皮影       母本拆成軀幹 + 兩腿，腿繞髖關節擺動，軀幹上下起伏
##
## 素材由 art/scripts/walk_pack.py 產到 art_src/04_walk/。
##   Space 暫停／繼續   Esc 離開
## 截圖：godot --path . res://game/fx/walk_demo.tscn ++ --frames=C:/dir/prefix
##   會在循環的 0、¼、½、¾ 各存一張 prefix_1..4.png 後結束

const WALK := "res://art_src/04_walk/"
const FONT := "res://game/assets/fonts/TaipeiSansTCBeta-Regular.ttf"
const PAPER := Color("#E8DCC6")
const CYCLE := 0.5      # 一圈秒數
const FRAMES := 4
const SCALE := 2.0      # 128px 放大 2 倍，四列剛好塞進 1080

var _t := 0.0
var _paused := false
var _sprites: Array[AnimatedSprite2D] = []
var _puppet: Node2D
var _meta_cache := {}


func _ready() -> void:
	RenderingServer.set_default_clear_color(PAPER)
	_row("A  逐格・扁平幾何 128px", 0, "face", 128, TEXTURE_FILTER_LINEAR, SCALE)
	_row("B  逐格・扁平幾何 48px（最近鄰）", 1, "face48", 48, TEXTURE_FILTER_NEAREST, SCALE * 128.0 / 48.0)
	_row("C  逐格・皮影 128px", 2, "shadow", 128, TEXTURE_FILTER_LINEAR, SCALE)
	_puppet_row("D  分件・皮影（程式擺動）", 3)
	_handle_cli()


func _row_y(i: int) -> float:
	return 30.0 + i * 262.0


func _tex(name: String) -> Texture2D:
	var p := ProjectSettings.globalize_path(WALK + name)
	if not FileAccess.file_exists(p):
		return null
	return ImageTexture.create_from_image(Image.load_from_file(p))


func _row(title: String, i: int, prefix: String, _size: int, filter: int, scale: float) -> void:
	var y := _row_y(i)
	_label(title, Vector2(40, y))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("walk")
	frames.set_animation_loop("walk", true)
	frames.set_animation_speed("walk", FRAMES / CYCLE)
	var ok := 0
	for f in FRAMES:
		var tex := _tex("%s_%d.png" % [prefix, f + 1])
		if tex == null:
			continue
		frames.add_frame("walk", tex)
		ok += 1
		# 靜態並排：四幀攤開
		var s := Sprite2D.new()
		s.texture = tex
		s.texture_filter = filter
		s.scale = Vector2.ONE * scale
		s.position = Vector2(900 + f * 200, y + 130)
		add_child(s)
	if ok == 0:
		_label("（尚未產出）", Vector2(300, y + 80))
		return
	var a := AnimatedSprite2D.new()
	a.sprite_frames = frames
	a.texture_filter = filter
	a.scale = Vector2.ONE * scale
	a.position = Vector2(400, y + 130)
	a.play("walk")
	add_child(a)
	_sprites.append(a)


func _puppet_row(title: String, i: int) -> void:
	var y := _row_y(i)
	_label(title, Vector2(40, y))
	var body := _tex("puppet_body.png")
	var back := _tex("puppet_leg_back.png")
	var front := _tex("puppet_leg_front.png")
	if body == null or back == null or front == null:
		_label("（尚未產出）", Vector2(300, y + 80))
		return
	var meta := _meta()
	_puppet = Node2D.new()
	_puppet.position = Vector2(400, y + 130)
	_puppet.scale = Vector2.ONE * SCALE
	add_child(_puppet)
	# 腿在軀幹後面：先加腿再加軀幹。節點名稱固定，_pose_puppet 用名稱取節點，
	# duplicate() 出來的幽靈也一樣適用。
	for leg_name in ["leg_back", "leg_front"]:
		var leg := Sprite2D.new()
		leg.name = leg_name
		leg.texture = back if leg_name == "leg_back" else front
		leg.centered = false
		var pivot: Vector2 = meta[leg_name]["pivot"]
		var origin: Vector2 = meta[leg_name]["origin"]
		leg.position = pivot
		leg.offset = origin - pivot
		_puppet.add_child(leg)
	var body_sprite := Sprite2D.new()
	body_sprite.name = "body"
	body_sprite.texture = body
	body_sprite.centered = false
	body_sprite.position = meta["body"]["origin"]
	_puppet.add_child(body_sprite)
	# 靜態並排：四個相位攤開
	for f in FRAMES:
		var ghost := _puppet.duplicate()
		ghost.position = Vector2(900 + f * 200, y + 130)
		add_child(ghost)
		_pose_puppet(ghost, float(f) / FRAMES)


func _meta() -> Dictionary:
	# walk_pack.py 寫出的 JSON：各件左上角相對於圖心的位置（origin）與髖關節（pivot），單位是 128px 版的像素
	if not _meta_cache.is_empty():
		return _meta_cache
	var p := ProjectSettings.globalize_path(WALK + "puppet.json")
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p))
	var out := {}
	for k in d:
		out[k] = {}
		for kk in d[k]:
			out[k][kk] = Vector2(d[k][kk][0], d[k][kk][1])
	_meta_cache = out
	return out


func _pose_puppet(root: Node2D, phase: float) -> void:
	# phase 0..1 一圈。腿：正弦擺動 ±28°，兩腿反相；軀幹：兩次起伏（每步一次）
	var ang := deg_to_rad(28.0) * sin(phase * TAU)
	var m := _meta()
	var bob := -2.0 * absf(cos(phase * TAU))
	var back := root.get_node("leg_back") as Sprite2D
	var front := root.get_node("leg_front") as Sprite2D
	var body := root.get_node("body") as Sprite2D
	back.rotation = -ang
	front.rotation = ang
	back.position.y = m["leg_back"]["pivot"].y + bob
	front.position.y = m["leg_front"]["pivot"].y + bob
	body.position.y = m["body"]["origin"].y + bob


func _process(delta: float) -> void:
	if _paused or _puppet == null:
		return
	_t = fmod(_t + delta, CYCLE)
	_pose_puppet(_puppet, _t / CYCLE)


func _label(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_override("font", load(FONT))
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color("#3A2A22"))
	add_child(l)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_paused = not _paused
			for s in _sprites:
				s.speed_scale = 0.0 if _paused else 1.0
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()


func _handle_cli() -> void:
	var prefix := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			prefix = arg.trim_prefix("--frames=")
	if prefix.is_empty():
		return
	# 逐幀擺到指定相位、停住動畫，各截一張
	_paused = true
	for f in FRAMES:
		for s in _sprites:
			s.stop()
			s.frame = f
		if _puppet != null:
			_pose_puppet(_puppet, float(f) / FRAMES)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, f + 1])
	get_tree().quit()
