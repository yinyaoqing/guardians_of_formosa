class_name ResultPanel
extends CanvasLayer

## 通關的結算面板。
##
## 它不需要暫停任何東西——BattleSim 在 world.battle_finished 成立時就自己停了。
## 讓面板去寫 sim.paused 會是第二條改變模擬狀態的路，而 B2 與 B3a 花了兩個
## 里程碑確保只有一條。
##
## 星等依第一章規格 §4.6：★ 撐過所有波次、★★ 平民撤離數達門檻、
## ★★★ 未失去聚落建物。第三顆恆為未達成——聚落建物還不存在。

signal restart_pressed

const STAR_FILLED := "★"
const STAR_EMPTY := "☆"
const STAR_COUNT := 3

@onready var _title_label: Label = $Root/Box/TitleLabel
@onready var _stars_label: Label = $Root/Box/StarsLabel
@onready var _waves_label: Label = $Root/Box/WavesLabel
@onready var _saved_label: Label = $Root/Box/SavedLabel
@onready var _restart_button: Button = $Root/Box/RestartButton

func _ready() -> void:
	visible = false
	_title_label.text = tr("result.title")
	_restart_button.text = tr("result.restart")
	_restart_button.pressed.connect(func() -> void: restart_pressed.emit())

## 前置條件：必須在 add_child() 之後呼叫。@onready 的節點要等進場景樹才解析，
## 提前呼叫會在寫第一個 Label 時對 null 取值。與 BattleHud.setup() 同一個守衛，
## 理由也相同——assert 在 release build 會被剝除，所以它是開發期的文件與攔截，
## 不是執行期的保護。
func show_result(stars: int, waves: int, saved: int, total: int) -> void:
	assert(is_inside_tree(), "ResultPanel.show_result() 必須在 add_child() 之後呼叫，否則 @onready 節點尚未解析")
	# 星星是符號不是文字，兩個語系都一樣，所以不進翻譯檔——
	# 進了反而會觸發 test_the_two_locales_actually_differ。
	var filled := clampi(stars, 0, STAR_COUNT)
	_stars_label.text = STAR_FILLED.repeat(filled) + STAR_EMPTY.repeat(STAR_COUNT - filled)
	_waves_label.text = tr("result.waves_format") % waves
	_saved_label.text = tr("result.saved_format") % [saved, total]
	visible = true
