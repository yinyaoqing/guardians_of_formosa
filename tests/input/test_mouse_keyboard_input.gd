extends GdUnitTestSuite

const WORLD_POS := Vector2(123.0, 456.0)

func before_test() -> void:
	InputBindings.install()

## 造一個按下指定實體按鍵的事件
func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event

func _mouse_event(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event

func test_install_registers_every_action() -> void:
	for action_name: String in [
		"gof_select", "gof_cancel", "gof_sell", "gof_upgrade",
		"gof_toggle_pause", "gof_cycle_speed",
		"gof_choose_tower_1", "gof_choose_tower_2", "gof_choose_tower_3",
	]:
		assert_bool(InputMap.has_action(action_name)).override_failure_message(
			"綁定安裝後動作 %s 必須存在，否則翻譯器問到的永遠是 false" % action_name
		).is_true()
		# 只驗證動作存在還不夠：一個把九個動作都 add_action() 卻忘記
		# action_add_event() 的 install() 一樣會讓上面的斷言全過，
		# 但 is_action_pressed() 永遠是 false，跟本測試想排除的失敗一模一樣。
		assert_int(InputMap.action_get_events(StringName(action_name)).size()).override_failure_message(
			"動作 %s 必須至少綁定一個事件，否則存在的動作依然問不出 is_action_pressed" % action_name
		).is_greater(0)

func test_install_is_idempotent() -> void:
	InputBindings.install()
	InputBindings.install()
	assert_int(InputMap.action_get_events(&"gof_select").size()).override_failure_message(
		"重複安裝不得讓同一個動作累積重複的事件"
	).is_equal(1)

func test_left_click_becomes_select_at_with_the_given_position() -> void:
	var action := MouseKeyboardInput.translate(_mouse_event(MOUSE_BUTTON_LEFT), WORLD_POS)
	assert_str(action.kind).is_equal("select_at")
	assert_float(action.world_position.x).is_equal_approx(WORLD_POS.x, 0.001)
	assert_float(action.world_position.y).is_equal_approx(WORLD_POS.y, 0.001)

func test_right_click_becomes_cancel() -> void:
	var action := MouseKeyboardInput.translate(_mouse_event(MOUSE_BUTTON_RIGHT), WORLD_POS)
	assert_str(action.kind).is_equal("cancel")

func test_escape_becomes_cancel() -> void:
	# gof_cancel 是唯一綁了兩個事件的動作：install() 裡 _bind_mouse() 先靠
	# _reset_action() 清空舊事件，_add_key() 才把 Escape 疊加上去。順序一旦
	# 顛倒，_reset_action() 會把剛加上去的 Escape 也一併清掉——右鍵仍然能
	# 取消，其他測試照樣全過，只有直接按 Escape 這條路會悄悄失靈。
	var action := MouseKeyboardInput.translate(_key_event(KEY_ESCAPE), WORLD_POS)
	assert_str(action.kind).is_equal("cancel")

func test_number_key_two_becomes_choose_tower_with_index_two() -> void:
	# 刻意用 2：寫死回傳 1 的實作會被這條抓到
	var action := MouseKeyboardInput.translate(_key_event(KEY_2), WORLD_POS)
	assert_str(action.kind).is_equal("choose_tower")
	assert_int(action.index).override_failure_message(
		"索引必須跟著按鍵走，不是固定的 1"
	).is_equal(2)

func test_s_becomes_sell() -> void:
	assert_str(MouseKeyboardInput.translate(_key_event(KEY_S), WORLD_POS).kind).is_equal("sell")

func test_u_becomes_upgrade() -> void:
	assert_str(MouseKeyboardInput.translate(_key_event(KEY_U), WORLD_POS).kind).is_equal("upgrade")

func test_space_becomes_toggle_pause() -> void:
	assert_str(MouseKeyboardInput.translate(_key_event(KEY_SPACE), WORLD_POS).kind).is_equal("toggle_pause")

func test_f_becomes_cycle_speed() -> void:
	assert_str(MouseKeyboardInput.translate(_key_event(KEY_F), WORLD_POS).kind).is_equal("cycle_speed")

func test_an_unbound_key_produces_nothing() -> void:
	assert_bool(MouseKeyboardInput.translate(_key_event(KEY_Q), WORLD_POS) == null).override_failure_message(
		"沒有綁定的按鍵必須回傳 null，否則場景會處理到不存在的動作"
	).is_true()

## 判斷一個事件是不是 Space。內建動作存 keycode、gof_* 存 physical_keycode，
## 只看一個欄位會漏。
func _is_space_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	return key.keycode == KEY_SPACE or key.physical_keycode == KEY_SPACE

func _action_has_space(action_name: StringName) -> bool:
	for event: InputEvent in InputMap.action_get_events(action_name):
		if _is_space_event(event):
			return true
	return false

func test_space_is_released_from_ui_accept() -> void:
	InputBindings.install()
	assert_bool(_action_has_space(&"ui_accept")).override_failure_message(
		"ui_accept 仍綁著 Space。HUD 按鈕一取得焦點就會吃掉空白鍵，暫停靜默失效。"
	).is_false()

func test_space_is_released_from_ui_select() -> void:
	InputBindings.install()
	assert_bool(_action_has_space(&"ui_select")).override_failure_message(
		"ui_select 也綁著 Space，漏掉它等於沒修"
	).is_false()

func test_enter_survives_on_ui_accept() -> void:
	# 刻意設計成有鑑別力：把 ui_accept 整個清空的實作會通過上面那條「沒有 Space」，
	# 卻會靜默打壞 HUD 的鍵盤觸發與 M4 的手把導航。
	InputBindings.install()
	var has_enter := false
	for event: InputEvent in InputMap.action_get_events(&"ui_accept"):
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_ENTER:
			has_enter = true
	assert_bool(has_enter).override_failure_message(
		"Enter 必須留在 ui_accept，否則按鈕無法用鍵盤或手把觸發"
	).is_true()

func test_install_converges_ui_accept_regardless_of_prior_state() -> void:
	# 舊版本只比對事件「數量」不變，erase-only 的實作不管有沒有真的拔 Space
	# 數量都不會變，測試永遠綠燈。這裡改成主動把 Space 塞回去（用內建動作
	# 原本的存法：keycode，不是 physical_keycode，才是 InputMap 真實會出現
	# 的狀態），驗證 install() 不管呼叫前 ui_accept 長怎樣，都會收斂回「沒有
	# Space」。
	InputBindings.install()
	var space_event := InputEventKey.new()
	space_event.keycode = KEY_SPACE
	InputMap.action_add_event(&"ui_accept", space_event)
	assert_bool(_action_has_space(&"ui_accept")).override_failure_message(
		"前置條件沒設好：手動塞回去的 Space 事件沒有被 InputMap 接受"
	).is_true()

	InputBindings.install()

	assert_bool(_action_has_space(&"ui_accept")).override_failure_message(
		"重新 install() 之後 Space 必須再度被拔掉，不管呼叫前 ui_accept 處於什麼狀態"
	).is_false()
	# 同時檢查 Enter：把整個動作清空再重建的實作能通過上面那條，
	# 卻會在這裡現形。
	var has_enter := false
	for event: InputEvent in InputMap.action_get_events(&"ui_accept"):
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_ENTER:
			has_enter = true
	assert_bool(has_enter).override_failure_message(
		"Enter 必須留在 ui_accept，清空整個動作的實作不能通過這條"
	).is_true()
