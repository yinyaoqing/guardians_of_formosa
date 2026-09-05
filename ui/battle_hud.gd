class_name BattleHud
extends CanvasLayer

## 戰鬥 HUD。
##
## 只讀 WorldState 與 BattleSim 來顯示；要讓事情發生只發 signal，由 battle_scene
## 翻成 InputAction 餵給 InteractionController。
##
## 這樣做的理由不是整齊，是測試覆蓋：暫停鈕與空白鍵最後產生同一個
## InputAction.simple(TOGGLE_PAUSE)，走 B2 已經有測試守著的那條路。HUD 若自己改
## sim.paused，那條路一條測試都沒有，而兩條路遲早會漂移。
##
## 此規則由 tests/test_ui_layer.gd 的原始碼掃描守住。

signal pause_pressed
signal speed_pressed

@onready var _root: MarginContainer = $Root
@onready var _gold_label: Label = $Root/Top/GoldLabel
@onready var _lives_label: Label = $Root/Top/LivesLabel
@onready var _level_name_label: Label = $Root/Top/LevelNameLabel
@onready var _pause_button: Button = $Root/Top/PauseButton
@onready var _speed_button: Button = $Root/Top/SpeedButton

var _world: WorldState = null
var _sim: BattleSim = null

## 上一次實際寫進 Label 的值。每秒 60 次的 tr() 與字串格式化全是白燒的配置，
## 而這些值大多數幀都沒變。與「戰鬥迴圈中禁止配置新物件」是同一個考量，
## 只是換到表現層。
##
## 初始值刻意取不可能出現的數，強制第一幀一定寫入。
var _shown_gold: int = -1
var _shown_lives: int = -1
var _shown_speed: int = -1
var _shown_paused: bool = true    ## sim 起始為 false，故第一幀必定不同

func _ready() -> void:
	_pause_button.pressed.connect(_on_pause_button_pressed)
	_speed_button.pressed.connect(_on_speed_button_pressed)
	_apply_safe_area()

## 前提：呼叫前必須先 add_child 把這個節點放進場景樹。_level_name_label 是
## @onready，要等 _ready() 跑過才會解析；順序顛倒的話這裡若不是直接炸掉，
## 就是 _world 與 _sim 都已賦值、關卡名卻悄悄沒寫進去，表面上一切正常。
##
## assert() 在 release build 會被拿掉，所以這裡只在開發期記錄並攔下這個順序，
## 不是執行期防線——這個規則本該由呼叫端遵守，不是靠這行 assert 兜底。
func setup(p_world: WorldState, p_sim: BattleSim, level_name_key: StringName) -> void:
	assert(is_inside_tree(), "BattleHud.setup() 必須在 add_child() 之後呼叫，否則 @onready 節點尚未解析")
	_world = p_world
	_sim = p_sim
	_level_name_label.text = tr(level_name_key)

func _process(_delta: float) -> void:
	if _world == null or _sim == null:
		return

	if _world.gold != _shown_gold:
		_shown_gold = _world.gold
		_gold_label.text = tr("hud.gold_format") % _shown_gold

	if _world.lives != _shown_lives:
		_shown_lives = _world.lives
		_lives_label.text = tr("hud.lives_format") % _shown_lives

	if _sim.paused != _shown_paused:
		_shown_paused = _sim.paused
		_pause_button.text = tr("hud.resume") if _shown_paused else tr("hud.pause")

	var speed := int(_sim.speed_multiplier)
	if speed != _shown_speed:
		_shown_speed = speed
		_speed_button.text = tr("hud.speed_format") % speed

func _on_pause_button_pressed() -> void:
	pause_pressed.emit()

func _on_speed_button_pressed() -> void:
	speed_pressed.emit()

## 手機的瀏海與 home indicator 會直接吃掉角落的數字。
##
## 桌面上安全區等於整個螢幕，算出來的邊距是 0，所以這段在 PC 上無作用——但它必須
## 現在就寫，因為它的失敗要到 M2 實機測試才看得見，而那時候補等於重驗一次版面。
##
## 安全區是螢幕像素，版面是 1920×1080 的設計單位，所以要換算。全螢幕時視窗尺寸
## 等於螢幕尺寸；非全螢幕時安全區可能比視窗大，換算結果會是負數，故一律夾到 0。
func _apply_safe_area() -> void:
	var window := DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0:
		return
	var safe := DisplayServer.get_display_safe_area()
	var canvas := get_viewport().get_visible_rect().size
	var scale_x := canvas.x / float(window.x)
	var scale_y := canvas.y / float(window.y)

	_root.add_theme_constant_override("margin_left", maxi(0, int(safe.position.x * scale_x)))
	_root.add_theme_constant_override("margin_top", maxi(0, int(safe.position.y * scale_y)))
	_root.add_theme_constant_override("margin_right", maxi(0, int((window.x - safe.end.x) * scale_x)))
