extends GdUnitTestSuite

## 冒煙測試：確認 GdUnit4 已正確安裝，且本計畫使用的斷言 API 存在。
## 後續所有測試都只使用這裡驗證過的斷言形式。

func test_int_assertion() -> void:
	assert_int(2 + 2).is_equal(4)

func test_float_assertion() -> void:
	assert_float(0.1 + 0.2).is_equal_approx(0.3, 0.0001)

func test_bool_assertion() -> void:
	assert_bool(true).is_true()
	assert_bool(false).is_false()

func test_str_assertion() -> void:
	assert_str("hello world").contains("world")

func test_array_assertion() -> void:
	assert_array([1, 2, 3]).has_size(3)
	assert_array([1, 2, 3]).contains([2])

func test_comparison_assertions() -> void:
	assert_int(5).is_greater(3)
	assert_float(0.5).is_between(0.0, 1.0)

func test_custom_failure_message_api() -> void:
	# 後續的資料完整性測試大量使用 override_failure_message 指出是哪一筆資料出錯
	assert_bool(true).override_failure_message("這個訊息不該出現").is_true()
