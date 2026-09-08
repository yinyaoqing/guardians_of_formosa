extends GdUnitTestSuite

## ResultSystem.star_count() 的星等規則。第一章規格 §4.6：
## ★ 撐過所有波次（呼叫這個函式的前提)、★★ 平民撤離數達門檻（≥）、
## ★★★ 未失去聚落建物（聚落建物還不存在，恆為未達成）。
##
## 這是本里程碑唯一一條原本活在 game/ 的遊戲規則，搬進 core/ 之後補上的測試——
## 之前完全沒有覆蓋，星等算錯不會有任何測試變紅。

func _make_world(threshold: int, starting: int, remaining: int) -> WorldState:
	var world := WorldState.new()
	world.star_civilian_threshold = threshold
	world.starting_civilians = starting
	world.civilians_remaining = remaining
	return world

func test_surviving_below_the_threshold_earns_one_star() -> void:
	var world := _make_world(14, 20, 13)
	assert_int(ResultSystem.star_count(world)).override_failure_message(
		"救到人數低於門檻只該拿一顆星"
	).is_equal(1)

func test_surviving_exactly_at_the_threshold_earns_two_stars() -> void:
	# 邊界：規格是「≥ 門檻」，不是「> 門檻」。救到人數剛好等於門檻必須算過關。
	var world := _make_world(14, 20, 14)
	assert_int(ResultSystem.star_count(world)).override_failure_message(
		"規格是 ≥ 門檻，剛好等於門檻應該拿到第二顆星，而不是差一個沒拿到"
	).is_equal(2)

func test_surviving_above_the_threshold_earns_two_stars() -> void:
	var world := _make_world(14, 20, 20)
	assert_int(ResultSystem.star_count(world)).is_equal(2)

func test_the_third_star_is_permanently_unreachable() -> void:
	# 聚落建物尚未實作，沒有東西可以「沒有失去」——即使救滿全部平民，
	# 也不該拿到第三顆星。這條測試釘住這個「暫時」的事實，等聚落建物真的
	# 加進遊戲、ResultSystem 改成讀那個計數時，這條測試理應跟著失敗提醒。
	#
	# 只測「救滿平民時是 2」的話，這條與上面那條「超過門檻拿兩顆」的輸入完全一樣，
	# 排除不掉任何實作。改成掃一片輸入斷言上限，這樣任何一個會在某組輸入吐出 3
	# 的分支都會被抓到。
	for saved in [0, 1, 13, 14, 15, 19, 20]:
		var world := _make_world(14, saved, 20)
		assert_bool(ResultSystem.star_count(world) <= 2).override_failure_message(
			"救到 %d 人時算出 %d 顆星。聚落建物還不存在，沒有東西可以「沒有失去」，上限就是 2。" % [
				saved, ResultSystem.star_count(world)
			]
		).is_true()
