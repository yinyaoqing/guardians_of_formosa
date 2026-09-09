class_name PathData
extends RefCounted

## 等距取樣後的路徑。敵人只持有「沿路徑已行進距離」，
## 由本類別換算成座標。因為取樣是等距的，換算是 O(1)。
##
## 取樣工作由 game/level/ 從 Curve2D 完成後傳入，core/ 不接觸引擎的曲線類別。

var _points: PackedVector2Array
var _spacing: float
var _total_length: float

func _init(points: PackedVector2Array, spacing: float) -> void:
	assert(points.size() >= 2, "PathData 至少需要兩個取樣點")
	assert(spacing > 0.0, "取樣間距必須為正數")
	_points = points
	_spacing = spacing
	_total_length = spacing * float(points.size() - 1)

func total_length() -> float:
	return _total_length

## 回傳沿路徑行進 distance 後的座標。超出兩端時夾在端點。
func position_at(distance: float) -> Vector2:
	if distance <= 0.0:
		return _points[0]
	if distance >= _total_length:
		return _points[_points.size() - 1]
	var exact := distance / _spacing
	var index := int(exact)
	var t := exact - float(index)
	return _points[index].lerp(_points[index + 1], t)

## 路徑上離 point 最近的取樣點所對應的行進距離。
##
## 線性掃描全部取樣點。只在建塔的當下呼叫一次，不在 tick 內，所以
## 幾百次比較完全可以接受，不需要空間索引。
func nearest_distance_to(point: Vector2) -> float:
	var best_index := 0
	var best_squared := INF
	for i in _points.size():
		var squared := _points[i].distance_squared_to(point)
		if squared < best_squared:
			best_squared = squared
			best_index = i
	return float(best_index) * _spacing
