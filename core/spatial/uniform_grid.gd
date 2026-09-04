class_name UniformGrid
extends RefCounted

## 均勻網格空間索引。100+ 敵人配 20+ 座塔時，逐幀暴力比對是 O(n²)，
## 手機承受不了。改為把敵人索引進固定格子，塔只查詢射程覆蓋到的格子。
##
## 每 tick 整個重建（clear + 逐筆 insert）比維護增量更新簡單，且效能足夠。

const CELL_SIZE := 64.0

## Vector2i -> Array[int]
## 必須用 Array 而非 PackedInt32Array：後者是值型別，
## _cells[key].append() 會修改暫存副本而非字典裡的陣列，且不會報錯。
var _cells: Dictionary = {}

func clear() -> void:
	_cells.clear()

func insert(entity_id: int, position: Vector2) -> void:
	var key := _cell_of(position)
	if not _cells.has(key):
		var bucket: Array[int] = []
		_cells[key] = bucket
	var existing: Array[int] = _cells[key]
	existing.append(entity_id)

## Broad phase：回傳「可能」落在半徑內的候選 id。
## 呼叫端必須自行做精確距離判定——本方法只保證不漏，不保證不多。
func query_radius(center: Vector2, radius: float) -> Array[int]:
	var result: Array[int] = []
	var min_cell := _cell_of(center - Vector2(radius, radius))
	var max_cell := _cell_of(center + Vector2(radius, radius))
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var key := Vector2i(x, y)
			if _cells.has(key):
				var bucket: Array[int] = _cells[key]
				result.append_array(bucket)
	return result

func _cell_of(position: Vector2) -> Vector2i:
	# 用 floori 而非 int()：int() 對負數是向零截斷，會讓 -10 與 10 落在同格
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))
