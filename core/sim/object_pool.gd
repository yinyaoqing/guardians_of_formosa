class_name ObjectPool
extends RefCounted

## 泛型物件池。投射物與狀態效果實例共用，兩者的取得／歸還／擴容邏輯完全相同。
##
## 用盡時擴容而非回傳 null：丟棄一個投射物等於玩家的傷害憑空消失，那是玩法 bug；
## 擴容只是一次性配置，擴完即穩定。警告讓容量不足在開發期浮現。

var _factory: Callable
var _free: Array = []
var _capacity: int = 0

func _init(factory: Callable, initial_capacity: int) -> void:
	assert(initial_capacity > 0, "物件池初始容量必須為正")
	_factory = factory
	for i in initial_capacity:
		_free.append(_factory.call())
	_capacity = initial_capacity

func acquire() -> Variant:
	if _free.is_empty():
		_grow()
	return _free.pop_back()

func release(obj: Variant) -> void:
	_free.append(obj)

func capacity() -> int:
	return _capacity

func free_count() -> int:
	return _free.size()

func _grow() -> void:
	var added := _capacity
	push_warning("ObjectPool 容量不足，自 %d 擴充至 %d。若頻繁發生應調高初始容量。" % [_capacity, _capacity + added])
	for i in added:
		_free.append(_factory.call())
	_capacity += added
