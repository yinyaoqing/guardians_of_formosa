class_name InputBindings
extends RefCounted

## 以程式註冊 InputMap 動作，而不是寫進 project.godot。
##
## project.godot 的 [input] 區塊要序列化整個 InputEvent 物件，欄位集隨
## Godot 版本變動，手寫極易出錯且錯了只在執行期才發現。程式註冊是幾行
## add_action，而且可以被測試斷言。代價是綁定不出現在編輯器的專案設定
## 介面裡——本專案目前沒有重新綁定的 UI，需要時再遷移。
##
## 前綴 gof_ 避開 Godot 內建的 ui_* 動作。

## 可選塔種的快捷鍵數量。對應「本關第 n 種可用塔」，不是特定塔種，
## 所以換關卡不需要改綁定。
const TOWER_CHOICE_COUNT := 3

## 內建的 ui_accept 與 ui_select 都把 Space 綁在上面。
const BUILTIN_ACTIONS_TO_FREE_SPACE: Array[StringName] = [&"ui_accept", &"ui_select"]

## 冪等：已存在的動作會先清掉再重建，重複呼叫不會累積重複事件。
static func install() -> void:
	_bind_mouse(&"gof_select", MOUSE_BUTTON_LEFT)
	_bind_mouse(&"gof_cancel", MOUSE_BUTTON_RIGHT)
	_add_key(&"gof_cancel", KEY_ESCAPE)
	_bind_key(&"gof_sell", KEY_S)
	_bind_key(&"gof_upgrade", KEY_U)
	_bind_key(&"gof_toggle_pause", KEY_SPACE)
	_bind_key(&"gof_cycle_speed", KEY_F)
	_bind_key(&"gof_call_wave", KEY_N)
	for i in range(1, TOWER_CHOICE_COUNT + 1):
		_bind_key(StringName("gof_choose_tower_%d" % i), (KEY_0 + i) as Key)
	_release_space_from_builtin_ui()

static func _reset_action(action_name: StringName) -> void:
	if InputMap.has_action(action_name):
		InputMap.action_erase_events(action_name)
	else:
		InputMap.add_action(action_name)

static func _bind_key(action_name: StringName, keycode: Key) -> void:
	_reset_action(action_name)
	_add_key(action_name, keycode)

static func _add_key(action_name: StringName, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action_name, event)

static func _bind_mouse(action_name: StringName, button: MouseButton) -> void:
	_reset_action(action_name)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action_name, event)

## 把 Space 從內建的 UI 動作上拆下來。
##
## HUD 一存在，玩家點過任何按鈕之後那顆按鈕就取得焦點，Space 會被 _gui_input
## 吃掉去觸發它，永遠到不了 _unhandled_input——暫停從此失效，而且沒有任何線索。
##
## 拔 Space 而保留 Enter 與 KP Enter：按鈕照樣可聚焦、可用方向鍵導航、可用 Enter
## 觸發，M4 的手把導航不受影響。改用 focus_mode = FOCUS_NONE 反而會毀掉那件事，
## 而且那是一條「每加一顆按鈕都要記得」的紀律規則，沒有測試抓得到漏掉的那一顆。
##
## 內建動作存的是 keycode（physical_keycode 為 0），而 gof_* 存的是
## physical_keycode，所以兩個欄位都要看。
static func _release_space_from_builtin_ui() -> void:
	for action_name: StringName in BUILTIN_ACTIONS_TO_FREE_SPACE:
		if not InputMap.has_action(action_name):
			continue
		# 對副本迭代：迴圈中會從 InputMap 移除事件
		for event: InputEvent in InputMap.action_get_events(action_name).duplicate():
			if event is InputEventKey and _is_space(event as InputEventKey):
				InputMap.action_erase_event(action_name, event)

static func _is_space(event: InputEventKey) -> bool:
	return event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE
