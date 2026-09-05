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
