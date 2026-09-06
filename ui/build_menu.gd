class_name BuildMenu
extends CanvasLayer

## 建塔選單。
##
## 只讀 BuildMenuOptions 算好的陣列來畫；要讓事情發生只發 signal，由 battle_scene
## 翻成與鍵盤相同的 InputAction。決策全部在 BuildMenuOptions 裡，這裡只有版面。
##
## 選項沿建塔點下方的半圓弧分布，不是整圈：最上排的建塔點在 y=200，整圈半徑 100
## 會把最上面那一瓣推到 y≈45，而 HUD 橫幅佔了畫面上緣約 120。下半圓從結構上避開
## 這個衝突，也不會蓋住建塔點本身或蓋好的塔。

signal option_chosen(option_index: int)
signal option_hovered(option_index: int)
signal option_unhovered

const RADIUS := 100.0
const BUTTON_SIZE := Vector2(110.0, 110.0)

## 相鄰兩瓣的夾角。以正下方為中心左右展開。
const ARC_STEP := deg_to_rad(60.0)

## 正下方。Godot 的畫面座標 y 向下，所以 +90 度是下方。
const ARC_CENTER := PI * 0.5

func show_options(options: Array[Dictionary], center: Vector2) -> void:
	_clear()
	var count := options.size()
	if count == 0:
		return
	for i in count:
		var button := _make_button(options[i], i)
		# 以正下方為中心左右展開：i 的中位數落在 ARC_CENTER 上
		var angle := ARC_CENTER + (float(i) - float(count - 1) * 0.5) * ARC_STEP
		button.position = center + Vector2(cos(angle), sin(angle)) * RADIUS - BUTTON_SIZE * 0.5
		add_child(button)

func hide_menu() -> void:
	_clear()

func _clear() -> void:
	for child in get_children():
		child.queue_free()

func _make_button(option: Dictionary, index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = BUTTON_SIZE
	button.size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	_style_button(button, option)
	button.pressed.connect(func() -> void: option_chosen.emit(index))
	button.mouse_entered.connect(func() -> void: option_hovered.emit(index))
	button.mouse_exited.connect(func() -> void: option_unhovered.emit())
	return button

func _style_button(button: Button, option: Dictionary) -> void:
	match StringName(option["kind"]):
		BuildMenuOptions.KIND_BUILD:
			button.icon = load(option["icon"])
			# 造價是純數字，沒有可翻譯的內容。硬做成 %d 的格式 key 會讓兩個語系
			# 完全相同，而那正好違反 B3a 的 test_the_two_locales_actually_differ。
			button.text = str(option["cost"])
			button.tooltip_text = tr(option["name_key"])
		BuildMenuOptions.KIND_UPGRADE:
			button.text = tr("menu.upgrade_format") % int(option["cost"])
		BuildMenuOptions.KIND_SELL:
			button.text = tr("menu.sell_format") % int(option["refund"])

	# 買不起仍然顯示，只是變暗——玩家要知道有這個選項存在。
	# 擋不擋是 BuildSystem 的事，不是選單的（沿用 B2 的分工）。
	var affordable: bool = option.get("affordable", true)
	button.modulate = Color(1, 1, 1, 1) if affordable else Color(0.55, 0.55, 0.55, 0.85)
