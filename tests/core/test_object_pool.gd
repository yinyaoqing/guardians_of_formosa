extends GdUnitTestSuite

func _make_pool(capacity: int) -> ObjectPool:
	return ObjectPool.new(func() -> StatusEffect: return StatusEffect.new(), capacity)

func test_pool_preallocates_to_capacity() -> void:
	var pool := _make_pool(4)
	assert_int(pool.capacity()).is_equal(4)
	assert_int(pool.free_count()).is_equal(4)

func test_acquire_reduces_free_count() -> void:
	var pool := _make_pool(4)
	pool.acquire()
	assert_int(pool.free_count()).is_equal(3)

func test_release_returns_object_to_pool() -> void:
	var pool := _make_pool(4)
	var obj: Variant = pool.acquire()
	pool.release(obj)
	assert_int(pool.free_count()).is_equal(4)

func test_exhausted_pool_grows_instead_of_returning_null() -> void:
	# 丟棄投射物等於玩家傷害憑空消失，是玩法 bug；擴容只是一次性配置
	var pool := _make_pool(2)
	pool.acquire()
	pool.acquire()
	var third: Variant = pool.acquire()
	assert_bool(third != null).override_failure_message(
		"池用盡時必須擴容並回傳可用物件，不得回傳 null"
	).is_true()
	assert_int(pool.capacity()).is_greater(2)

func test_capacity_and_free_count_stay_consistent_across_use() -> void:
	var pool := _make_pool(2)
	var obj1: Variant = pool.acquire()
	var obj2: Variant = pool.acquire()
	pool.release(obj1)
	pool.release(obj2)
	assert_int(pool.free_count()).is_equal(pool.capacity())

func test_reset_clears_effect_fields() -> void:
	var effect := StatusEffect.new()
	effect.kind = StatusEffect.KIND_SLOW
	effect.source = &"archer_tower"
	effect.magnitude = 0.5
	effect.damage_type = &"fire"
	effect.remaining = 3.0
	effect.reset()
	assert_str(effect.kind).is_equal("")
	assert_str(effect.source).is_equal("")
	assert_float(effect.magnitude).is_equal_approx(0.0, 0.001)
	assert_str(effect.damage_type).is_equal("")
	assert_float(effect.remaining).is_equal_approx(0.0, 0.001)
