class_name GameTheme
extends RefCounted

## 遊戲 UI 主題：整份用程式建構，色票唯一來源是 data/art_palette.json。
##
## 為什麼不做 .tres：專案約定「資料一律 JSON、不用 .tres」；主題的每個數字（圓角、
## 邊框、色）都該能在 code review 裡看到 diff，而 .tres 的 diff 是一坨序列化噪音。
## 為什麼用 StyleBoxFlat 而不是 AI 出圖：路線圖 §0 的觀察——AI 出的圖示底框樣式
## 不一（圓、方、圓角），底框由 UI 畫一次，AI 只出符號。
##
## 造型語言與戰場一致（美術聖經 §1.1 扁平幾何）：硬邊、無漸層、一道右下實影
## 模擬剪紙貼在紙上的厚度；描邊用色票的焦茶而非純黑。
##
## 型別變體（theme_type_variation）：
##   IconButton   建塔選單的圖示鈕——方形底板，圖示在上、造價在下
##   DialogueCard 對話卡外框——深赭粗框、寬內距
##   HudLabel     頂欄數字——焦茶字配蚵殼灰外框，壓在任何地磚上都讀得到

const PALETTE_PATH := "res://data/art_palette.json"

const FONT_REGULAR := "res://game/assets/fonts/TaipeiSansTCBeta-Regular.ttf"
const FONT_BOLD := "res://game/assets/fonts/TaipeiSansTCBeta-Bold.ttf"

const CORNER := 6
const BORDER := 2
const SHADOW_OFFSET := Vector2(3, 3)

static var _theme: Theme = null
static var _palette: Dictionary = {}

## 主題只建一次；建塔選單每次開啟都要，重建是浪費也是不一致的來源。
static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme

## 依色票名稱取色（palette 與 skin 兩組都查）。找不到是資料錯，不是執行期狀況，
## 回洋紅讓它在畫面上立刻現形。
static func color(name: String, alpha: float = 1.0) -> Color:
	if _palette.is_empty():
		_load_palette()
	var hex: String = _palette.get(name, "")
	if hex.is_empty():
		push_error("art_palette.json 沒有色名 %s" % name)
		return Color.MAGENTA
	var c := Color.html(hex)
	c.a = alpha
	return c

static func _load_palette() -> void:
	var file := FileAccess.open(PALETTE_PATH, FileAccess.READ)
	if file == null:
		push_error("讀不到 %s" % PALETTE_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_palette = {}
		_palette.merge(parsed.get("palette", {}))
		_palette.merge(parsed.get("skin", {}))

static func build() -> Theme:
	var theme := Theme.new()
	var regular: Font = load(FONT_REGULAR)
	var bold: Font = load(FONT_BOLD)
	theme.default_font = regular
	theme.default_font_size = 28

	# ---- Button：紙片底板，右下實影 ----
	theme.set_stylebox("normal", "Button", plate(color("蚵殼灰")))
	theme.set_stylebox("hover", "Button", plate(color("曝曬沙")))
	theme.set_stylebox("pressed", "Button", plate(color("沙洲黃"), Vector2(1, 1)))
	theme.set_stylebox("disabled", "Button", plate(color("蚵殼灰"), Vector2.ZERO, color("鐵灰")))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", color("焦茶"))
	theme.set_color("font_hover_color", "Button", color("焦茶"))
	theme.set_color("font_pressed_color", "Button", color("深赭"))
	theme.set_color("font_disabled_color", "Button", color("鐵灰"))
	theme.set_font("font", "Button", bold)

	# ---- IconButton：建塔選單 ----
	theme.set_type_variation("IconButton", "Button")
	theme.set_constant("icon_max_width", "IconButton", 64)
	theme.set_constant("h_separation", "IconButton", 0)
	theme.set_font_size("font_size", "IconButton", 26)
	var icon_plate := plate(color("蚵殼灰"))
	icon_plate.content_margin_top = 8
	icon_plate.content_margin_bottom = 6
	theme.set_stylebox("normal", "IconButton", icon_plate)

	# ---- Label ----
	theme.set_color("font_color", "Label", color("焦茶"))

	theme.set_type_variation("HudLabel", "Label")
	theme.set_font("font", "HudLabel", bold)
	theme.set_font_size("font_size", "HudLabel", 40)
	theme.set_color("font_color", "HudLabel", color("焦茶"))
	theme.set_color("font_outline_color", "HudLabel", color("蚵殼灰"))
	theme.set_constant("outline_size", "HudLabel", 8)

	theme.set_type_variation("SpeakerLabel", "Label")
	theme.set_font("font", "SpeakerLabel", bold)
	theme.set_font_size("font_size", "SpeakerLabel", 36)
	theme.set_color("font_color", "SpeakerLabel", color("深赭"))

	theme.set_type_variation("BodyLabel", "Label")
	theme.set_font_size("font_size", "BodyLabel", 32)

	# ---- DialogueCard：對話卡外框 ----
	theme.set_type_variation("DialogueCard", "PanelContainer")
	var card := plate(color("蚵殼灰"), SHADOW_OFFSET * 2, color("深赭"))
	card.border_width_left = 4
	card.border_width_top = 4
	card.border_width_right = 4
	card.border_width_bottom = 4
	card.corner_radius_top_left = 10
	card.corner_radius_top_right = 10
	card.corner_radius_bottom_right = 10
	card.corner_radius_bottom_left = 10
	card.content_margin_left = 24
	card.content_margin_top = 20
	card.content_margin_right = 24
	card.content_margin_bottom = 20
	theme.set_stylebox("panel", "DialogueCard", card)

	# 肖像底板：深色石板（與肖像 framing 的 dark slate 背景同一語彙）
	theme.set_type_variation("PortraitFrame", "PanelContainer")
	var frame := plate(color("焦茶"), Vector2.ZERO, color("深赭"))
	frame.content_margin_left = 6
	frame.content_margin_top = 6
	frame.content_margin_right = 6
	frame.content_margin_bottom = 6
	theme.set_stylebox("panel", "PortraitFrame", frame)

	return theme

## 一片「紙片」：硬邊、單色、焦茶描邊、右下實影。所有 UI 面都由這一個工廠出，
## 換造型語言只改這裡。
static func plate(fill: Color, shadow: Vector2 = SHADOW_OFFSET, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	var border_color := border if border.a > 0.0 else color("焦茶")
	box.border_color = border_color
	box.set_border_width_all(BORDER)
	box.set_corner_radius_all(CORNER)
	box.corner_detail = 4
	box.anti_aliasing = false
	if shadow != Vector2.ZERO:
		box.shadow_color = color("焦茶", 0.35)
		box.shadow_size = 0
		box.shadow_offset = shadow
		# shadow_size 0 時 Godot 不畫影子；給 1 讓它畫實影（不模糊）
		box.shadow_size = 1
	box.set_content_margin_all(10)
	return box
