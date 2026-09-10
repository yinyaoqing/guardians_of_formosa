class_name DialogueCard
extends CanvasLayer

## 對話卡：左肖像、右說話者與台詞。過場與關卡內的敘事都走這一張。
##
## 只顯示、不決定：誰說了什麼、下一句是什麼由呼叫端（未來的過場流程）決定，
## 這裡只發 advance_pressed。與 HUD、建塔選單相同的方向規則（tests/test_ui_layer.gd）。
##
## 肖像是 data 指定的貼圖路徑，不在這裡寫死任何角色——同一張卡要給第一章六個
## 說話者共用，而後續章節的說話者還會更多。

signal advance_pressed

@onready var _card: PanelContainer = $Root/Card
@onready var _portrait: TextureRect = $Root/Card/Row/PortraitFrame/Portrait
@onready var _speaker_label: Label = $Root/Card/Row/Text/SpeakerLabel
@onready var _body_label: Label = $Root/Card/Row/Text/BodyLabel

func _ready() -> void:
	$Root.theme = GameTheme.get_theme()
	_card.gui_input.connect(_on_card_gui_input)
	$Root.visible = false

## 顯示一句。portrait 可為 null（旁白），此時肖像框整個收起，文字佔滿。
func show_line(portrait: Texture2D, speaker_key: StringName, text_key: StringName) -> void:
	_portrait.texture = portrait
	_portrait.get_parent().visible = portrait != null
	_speaker_label.text = tr(speaker_key)
	_body_label.text = tr(text_key)
	$Root.visible = true

func hide_card() -> void:
	$Root.visible = false

func is_showing() -> bool:
	return $Root.visible

func _on_card_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance_pressed.emit()
	elif event is InputEventScreenTouch and event.pressed:
		advance_pressed.emit()
