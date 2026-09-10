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
##
## battle_hud.tscn 裡 Root、Top 兩個容器與 SpacerLeft、SpacerRight 兩個空白
## Control 都明確設定 mouse_filter = 2（MOUSE_FILTER_IGNORE）。純 Control 預設
## 是 MOUSE_FILTER_STOP，不管看不看得見都會吃掉矩形範圍內的滑鼠事件；
## battle_scene.gd 的建塔點擊走 _unhandled_input，只有滑鼠事件沒被 GUI
## 系統吃掉才會傳到那裡。這兩個 Spacer 撐開整條頂欄的寬度，一旦沿用預設值，
## 頂欄下方（包含 48px 拾取半徑內）的建塔格全部點不到。
## Container 系列（MarginContainer、HBoxContainer）與 Label 的預設值本來就不
## 攔截（分別是 PASS、IGNORE），這裡照樣明寫，避免下一個人加新元件時，
## 誤以為「容器都要手動設」或忘記空白 Control 的預設值跟容器不一樣。
## 兩個 Button 刻意不設，維持預設的 STOP——按鈕自己要吃掉點擊，否則按暫停
## 會連帶把按鈕正下方的建塔格也點掉。
##
## 實測預設值（headless 逐節點類型量測）：MarginContainer/HBoxContainer/Label
## 皆已預設不攔截（分別是 PASS=1、PASS=1、IGNORE=2），Control 預設 STOP=0，
## Button 預設 STOP=0。容器與 Label 本來就安全，這裡照樣明寫是保險，不是修正；
## 真正要修的只有兩個 Spacer（Control）與 Root、Top 這兩處。

signal pause_pressed
signal speed_pressed
signal call_wave_pressed

## 頂欄與畫面邊緣的基本距離（設計單位）。安全區邊距疊加在這之上，不取代它——
## 桌面安全區是 0，沒有這個值數字會貼著螢幕左緣。
const EDGE_MARGIN := 24

@onready var _root: MarginContainer = $Root
@onready var _gold_label: Label = $Root/Top/GoldLabel
@onready var _civilians_label: Label = $Root/Top/CiviliansLabel
@onready var _level_name_label: Label = $Root/Top/LevelNameLabel
@onready var _wave_label: Label = $Root/Top/WaveLabel
@onready var _countdown_label: Label = $Root/Top/CountdownLabel
@onready var _call_wave_button: Button = $Root/Top/CallWaveButton
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
var _shown_civilians: int = -1
var _shown_speed: int = -1
var _shown_paused: bool = true    ## sim 起始為 false，故第一幀必定不同
var _shown_wave_index: int = -1
var _shown_wave_total: int = -1
var _shown_countdown: int = -1

func _ready() -> void:
	# 主題掛在 Root 上就會沿子樹傳下去；.tscn 裡不放任何顏色，全部由 GameTheme 決定。
	_root.theme = GameTheme.get_theme()
	_pause_button.pressed.connect(_on_pause_button_pressed)
	_speed_button.pressed.connect(_on_speed_button_pressed)
	_call_wave_button.text = tr("hud.call_wave")
	_call_wave_button.pressed.connect(_on_call_wave_button_pressed)
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

	if _world.civilians_remaining != _shown_civilians:
		_shown_civilians = _world.civilians_remaining
		_civilians_label.text = tr("hud.civilians_format") % _shown_civilians

	if _sim.paused != _shown_paused:
		_shown_paused = _sim.paused
		_pause_button.text = tr("hud.resume") if _shown_paused else tr("hud.pause")

	var speed := int(_sim.speed_multiplier)
	if speed != _shown_speed:
		_shown_speed = speed
		_speed_button.text = tr("hud.speed_format") % speed

	var wave_index := _world.wave_state.next_wave_index
	var wave_total := _world.waves.size()
	if wave_index != _shown_wave_index or wave_total != _shown_wave_total:
		_shown_wave_index = wave_index
		_shown_wave_total = wave_total
		# 顯示是 1 起算：next_wave_index 是 0 起算的索引，全部生完時等於總數，
		# 那時顯示總數本身而不是總數 + 1。
		_wave_label.text = tr("hud.wave_format") % [mini(wave_index + 1, wave_total), wave_total]

	# 倒數只顯示到秒。每幀寫一次 Label 是白燒的配置，而秒數一秒才變一次。
	var countdown := 0 if _world.wave_state.spawning else ceili(_world.wave_state.countdown)

	# 全部波次生完之後，WaveSystem 不會再改 countdown——它停在最後一次被
	# 減到的 0.0。單看 countdown 分不出「生成中」與「已經全部生完，剩下清場」
	# 這兩種情境，兩者的 countdown 都是 0；用 wave_index/wave_total 額外分辨。
	# all_done 用獨立的 -1 當顯示鍵，確保從「生成中」(countdown 0) 切到
	# 「已清場」時，即使 countdown 數值沒變，_shown_countdown 比對也會偵測到
	# 需要換字——否則清場的 60~75 秒整段時間會沿用生成中的「進行中」文字，
	# 讓玩家誤以為下一波要來了。
	var all_done := wave_index >= wave_total and not _world.wave_state.spawning
	var display_key := -1 if all_done else countdown
	if display_key != _shown_countdown:
		_shown_countdown = display_key
		if all_done:
			_countdown_label.text = tr("hud.waves_cleared")
		elif countdown <= 0:
			_countdown_label.text = tr("hud.wave_incoming")
		else:
			_countdown_label.text = tr("hud.countdown_format") % countdown
		# 規格 §8.1：呼叫鈕只在倒數中才按得下去。countdown <= 0 涵蓋生成中與
		# 全部生完的收尾兩種情境，跟 WaveSystem.call_next_wave() 靜默忽略的
		# 條件是同一組——按下去沒有反應時，按鈕本身至少要看起來按不下去。
		_call_wave_button.disabled = countdown <= 0

func _on_pause_button_pressed() -> void:
	pause_pressed.emit()

func _on_speed_button_pressed() -> void:
	speed_pressed.emit()

func _on_call_wave_button_pressed() -> void:
	call_wave_pressed.emit()

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

	_root.add_theme_constant_override("margin_left", EDGE_MARGIN + maxi(0, int(safe.position.x * scale_x)))
	_root.add_theme_constant_override("margin_top", EDGE_MARGIN + maxi(0, int(safe.position.y * scale_y)))
	_root.add_theme_constant_override("margin_right", EDGE_MARGIN + maxi(0, int((window.x - safe.end.x) * scale_x)))
