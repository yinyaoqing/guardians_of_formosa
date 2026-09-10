class_name MouseKeyboardInput
extends RefCounted

## 把滑鼠與鍵盤事件翻成裝置無關的 InputAction。
##
## 是靜態函式而非 Node：螢幕座標換算成世界座標的工作留在場景做（它需要
## viewport），結果當參數傳入。因此整個 input/ 層沒有 Node、可 headless 測試。
##
## 觸控目前不需要專屬翻譯器：Godot 預設的 emulate_mouse_from_touch 會把
## 點擊轉成滑鼠事件，正好涵蓋 B2 範圍內的點選與取消。若同時再寫一個觸控
## 翻譯器，一次點擊會產生兩個動作。長按與環形選單手勢屬 B3。

const TOWER_CHOICE_COUNT := InputBindings.TOWER_CHOICE_COUNT

## 無對應動作時回傳 null——場景據此決定不轉發。
static func translate(event: InputEvent, world_position: Vector2) -> InputAction:
	if event.is_action_pressed(&"gof_select"):
		return InputAction.select_at(world_position)
	if event.is_action_pressed(&"gof_cancel"):
		return InputAction.simple(InputAction.CANCEL)
	if event.is_action_pressed(&"gof_sell"):
		return InputAction.simple(InputAction.SELL)
	if event.is_action_pressed(&"gof_upgrade"):
		return InputAction.simple(InputAction.UPGRADE)
	if event.is_action_pressed(&"gof_toggle_pause"):
		return InputAction.simple(InputAction.TOGGLE_PAUSE)
	if event.is_action_pressed(&"gof_cycle_speed"):
		return InputAction.simple(InputAction.CYCLE_SPEED)
	if event.is_action_pressed(&"gof_call_wave"):
		return InputAction.simple(InputAction.CALL_NEXT_WAVE)
	for i in range(1, TOWER_CHOICE_COUNT + 1):
		if event.is_action_pressed(StringName("gof_choose_tower_%d" % i)):
			return InputAction.choose_tower(i)
	return null
