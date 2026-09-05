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

## 冪等：已存在的動作會先清掉再重建，重複呼叫不會累積重複事件。
static func install() -> void:
	_bind_mouse(&"gof_select", MOUSE_BUTTON_LEFT)
	_bind_mouse(&"gof_cancel", MOUSE_BUTTON_RIGHT)
	_add_key(&"gof_cancel", KEY_ESCAPE)
	_bind_key(&"gof_sell", KEY_S)
	_bind_key(&"gof_upgrade", KEY_U)
	_bind_key(&"gof_toggle_pause", KEY_SPACE)
	_bind_key(&"gof_cycle_speed", KEY_F)
	for i in range(1, TOWER_CHOICE_COUNT + 1):
		_bind_key(StringName("gof_choose_tower_%d" % i), (KEY_0 + i) as Key)

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
